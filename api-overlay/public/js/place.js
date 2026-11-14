// The place screen: tap a spot on the map to see its photos, history and trend.

import { state } from "./state.js";
import { addressParts } from "./analysis.js";
import { TYPE_INFO } from "./analysis_types.js";
import { $, el, show, toast } from "./dom.js";
import { levelOf, map } from "./map.js";
import { trendBadge } from "./map_filters.js";
import { goPage } from "./navigation.js";
import { setFollowButton } from "./notifications.js";
import { openReport } from "./report_flow.js";

// Meters per pixel at this zoom, times ~40px: clicking selects roughly that area.
function radiusFor() {
  var lat = map.getCenter().lat * Math.PI / 180;
  var mpp = 156543.03 * Math.cos(lat) / Math.pow(2, map.getZoom());
  return Math.max(10, Math.min(500, Math.round(mpp * 40)));
}

var MONTH_NAMES = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];

export var place = null;

var placeRun = 0;

export function shortDate(iso) {
  var d = new Date(iso);
  return d.getDate() + " " + MONTH_NAMES[d.getMonth()].toLowerCase() + " " + d.getFullYear();
}

export function photoPath(url) { try { return new URL(url, location.href).pathname; } catch (e) { return ""; } }

// The closest cell of the map to a tap, within ~44px (works at any zoom, also where pins are not drawn).
function cellNear(point) {
  var best = null, bestDistance = 44;
  map.querySourceFeatures("heat").forEach(function (f) {
    var p = map.project(f.geometry.coordinates), d = Math.hypot(p.x - point.x, p.y - point.y);
    if (d < bestDistance) { best = f; bestDistance = d; }
  });
  return best;
}

function chartSvg(points) {
  var W = 320, H = 150, L = 30, R = 12, T = 12, B = 26, NS = "http://www.w3.org/2000/svg";
  function node(name, attrs, text) {
    var n = document.createElementNS(NS, name);
    Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); });
    if (text != null) n.textContent = text;
    return n;
  }
  var svg = node("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "Evolução da limpeza por mês" });
  var y = function (v) { return T + (H - T - B) * (1 - v / 100); };
  [0, 50, 100].forEach(function (v) {
    svg.appendChild(node("line", { x1: L, x2: W - R, y1: y(v), y2: y(v), stroke: "#e3e8e4", "stroke-width": 1 }));
    svg.appendChild(node("text", { x: L - 6, y: y(v) + 4, "text-anchor": "end", "font-size": 10, fill: "#7a857e" }, v));
  });
  var step = points.length > 1 ? (W - L - R - 20) / (points.length - 1) : 0;
  var xs = points.map(function (p, i) { return points.length > 1 ? L + 10 + step * i : (L + W - R) / 2; });
  if (points.length > 1) {
    svg.appendChild(node("polyline", { points: points.map(function (p, i) { return xs[i] + "," + y(p.average); }).join(" "), fill: "none", stroke: "#9aa59e", "stroke-width": 2, "stroke-linejoin": "round" }));
  }
  points.forEach(function (p, i) {
    var title = node("title", {}, MONTH_NAMES[+p.month.slice(5) - 1] + ": " + p.average + "/100 (" + p.reports + " registro" + (p.reports > 1 ? "s" : "") + ")");
    var dot = node("circle", { cx: xs[i], cy: y(p.average), r: 5, fill: levelOf(p.average).color, stroke: "#fff", "stroke-width": 2 });
    dot.appendChild(title); svg.appendChild(dot);
    svg.appendChild(node("text", { x: xs[i], y: H - 8, "text-anchor": "middle", "font-size": 11, fill: "#7a857e" }, MONTH_NAMES[+p.month.slice(5) - 1]));
  });
  return svg;
}

function selectPhoto(report) {
  var level = levelOf(report.severity);
  $("detail").style.setProperty("--lvl", level.color);
  $("dt-photo").src = photoPath(report.photo_url);
  $("dt-badge").textContent = "🗑 " + level.label + " · " + report.severity;
  $("dt-date").textContent = shortDate(report.taken_at);
  var types = (report.trash_types || []).map(function (t) { return (TYPE_INFO[t] || ["", t])[1]; });
  $("dt-desc").textContent = report.extra_info || (types.length ? "Itens: " + types.join(", ") + "." : "");
  document.querySelectorAll("#dt-photos img").forEach(function (img) { img.classList.toggle("on", +img.dataset.id === report.id); });
}

export async function openPlace(h3) {
  var run = ++placeRun;
  place = null;
  $("dt-title").textContent = "Carregando…"; $("dt-sub").textContent = ""; $("dt-desc").textContent = "";
  $("dt-photo").removeAttribute("src"); $("dt-badge").textContent = ""; $("dt-date").textContent = "";
  show("dt-trend", false); $("dt-chart").replaceChildren(); $("dt-photos").replaceChildren(); $("dt-photos").classList.remove("all"); $("dt-all").textContent = "Ver todas";
  show("detail", true, "flex");
  var data = null;
  try {
    var res = await fetch("/api/v1/places/" + encodeURIComponent(h3));
    if (res.ok) data = await res.json();
  } catch (e) {}
  if (run !== placeRun) return;
  if (!data) { show("detail", false); return toast("Não foi possível abrir este local agora."); }
  place = data;
  setFollowButton(data.following);

  selectPhoto(data.latest);
  data.photos.forEach(function (r) {
    var img = document.createElement("img");
    img.src = photoPath(r.photo_url); img.alt = "Foto de " + shortDate(r.taken_at); img.loading = "lazy"; img.dataset.id = r.id;
    img.onclick = function () { selectPhoto(r); };
    $("dt-photos").appendChild(img);
  });
  selectPhoto(data.latest);
  show("dt-all", data.photos.length > 4, "inline-block");

  var chart = $("dt-chart");
  if (data.history.length) chart.appendChild(chartSvg(data.history));
  else chart.appendChild(el("div", "Ainda sem histórico neste local.", "none"));

  var tbadge = trendBadge(data.trend), tbox = $("dt-trend"); tbox.replaceChildren();
  if (tbadge) tbox.appendChild(tbadge);
  show("dt-trend", !!tbadge, "block");
  if (data.cleaned_at) $("dt-desc").textContent = "✅ Marcado como limpo em " + shortDate(data.cleaned_at) + ". " + $("dt-desc").textContent;
  $("dt-title").textContent = "Local no mapa";
  $("dt-sub").textContent = data.center.lat.toFixed(5) + ", " + data.center.lng.toFixed(5);
  var parts = await addressParts(data.center.lat, data.center.lng);
  if (run === placeRun && parts) {
    $("dt-title").textContent = parts.street || parts.area;
    $("dt-sub").textContent = parts.street ? parts.area : "";
  }
}

export function closePlace() { placeRun++; place = null; show("detail", false); }

export function boot() {
  map.on("click", function (e) {
    if (state.reporting) return;
    var cell = cellNear(e.point);
    if (!cell) return toast("Nenhum registro aqui. Aproxime o mapa e toque em um pino.");
    openPlace(cell.properties.h3);
  });

  $("dt-back").onclick = closePlace;

  $("dt-all").onclick = function () {
    var all = $("dt-photos").classList.toggle("all");
    this.textContent = all ? "Ver menos" : "Ver todas";
  };

  $("dt-clean").onclick = function () {
    if (!place) return;
    var at = [place.center.lng, place.center.lat];
    closePlace(); goPage("map");
    openReport("cleanup", at);
  };
}
