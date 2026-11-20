// The profile: everything I sent, as a grid, with its highlights, places and per-photo screen.

import { state } from "./state.js";
import { addressOf, addressParts } from "./analysis.js";
import { TYPE_INFO } from "./analysis_types.js";
import { api, deviceToken } from "./api.js";
import { $, el, show, toast } from "./dom.js";
import { applyFilter, levelOf, loadHeat, map, paintLevel } from "./map.js";
import { goPage } from "./navigation.js";
import { openPlace, photoPath, shortDate } from "./place.js";
import { openReport } from "./report_flow.js";

var feedLoading = false;

var STATE_TEXT = {
  protecting_photo: "Protegendo", analyzing: "Analisando", scored: "Publicar", in_review: "Em revisão", not_trash: "Sem lixo", still_dirty: "Ainda sujo", nothing_to_clean: "Sem registro"
};

var STATUS_LINE = {
  published: "Publicada no mapa. Obrigado por ajudar!",
  scored: "A IA já analisou. Falta você publicar no mapa.",
  in_review: "Em revisão: aparece no mapa depois de aprovada.",
  not_trash: "A IA não encontrou lixo nessa foto.",
  still_dirty: "A foto ainda mostra lixo: o local continua sujo.",
  nothing_to_clean: "Não havia lixo registrado neste local.",
  analyzing: "Analisando…", protecting_photo: "Protegendo a privacidade da foto…"
};

var zoomWanted = false; // the profile was just opened: when the feed is here, take the map to the latest published report

// The newest report of mine that is on the map: the map moves there (zoom 17), ready for when the Mapa tab is opened.
function showLatestOnMap() {
  var latest = state.feed.find(function (r) { return r.published && isFinite(r.lat) && isFinite(r.lng) && r.lat !== null && r.lng !== null; });
  if (latest) map.jumpTo({ center: [latest.lng, latest.lat], zoom: 17 });
}

export async function loadFeed(zoomToLatest) {
  if (zoomToLatest) zoomWanted = true;
  if (!state.me || feedLoading) return;
  feedLoading = true;
  var res = await api("/api/v1/me/feed").catch(function () { return null; });
  feedLoading = false;
  if (!res || !res.ok) { zoomWanted = false; return; }
  state.feed = res.data; renderFeed();
  if (zoomWanted) { zoomWanted = false; showLatestOnMap(); }
}

var feedTab = "all";

var feedSort = "new";

export var mineOnly = false;

function isPending(r) { return !r.published && r.stage !== "not_trash" && r.stage !== "still_dirty" && r.stage !== "nothing_to_clean"; }

function weekOf(d) { return Math.floor((new Date(d).getTime() + 3 * 86400000) / (7 * 86400000)); } // weeks start on Monday

// Places helped, points and the weekly streak, from my own reports.
function impactOf(list) {
  var pub = list.filter(function (r) { return r.published; }), cells = {}, points = 0;
  pub.forEach(function (r) { if (r.h3_index) cells[r.h3_index] = true; points += r.kind === "cleanup" ? 30 : 10; });
  var weeks = {}; pub.forEach(function (r) { weeks[weekOf(r.taken_at)] = true; });
  var w = weekOf(new Date()), streak = 0;
  if (!weeks[w]) w--; // this week may not have a report yet
  while (weeks[w]) { streak++; w--; }
  return { places: Object.keys(cells).length, points: points, streak: streak };
}

function renderImpact() {
  var i = impactOf(state.feed);
  $("st-places").textContent = i.places; $("st-points").textContent = i.points;
  $("pf-bio").textContent = i.streak ? "🔥 " + i.streak + (i.streak > 1 ? " semanas seguidas ajudando a limpar a cidade" : " semana ajudando a limpar a cidade") : "";
  renderHighlights();
}

// Like Instagram highlights: one round photo per place I helped, ringed in the color of how dirty it is now.
function renderHighlights() {
  var box = $("pf-highlights"); box.replaceChildren();
  var add = el("button", null, "hl new"); add.type = "button";
  add.appendChild(el("div", null, "circle")); add.firstChild.appendChild(el("span", "+")); add.appendChild(el("span", "Novo", "t"));
  add.onclick = function () { openReport(); };
  box.appendChild(add);
  groupPlaces(state.feed.filter(function (r) { return r.published; })).slice(0, 12).forEach(function (g) {
    var b = el("button", null, "hl"); b.type = "button";
    var color = g.last.severity != null ? levelOf(g.last.severity).color : "#b9c4bd";
    var circle = el("div", null, "circle"); circle.style.setProperty("--ring", color);
    if (g.last.thumb_url) { var img = document.createElement("img"); img.src = photoPath(g.last.thumb_url); img.alt = ""; img.loading = "lazy"; circle.appendChild(img); }
    else circle.appendChild(el("span", "📍"));
    b.appendChild(circle);
    var label = el("span", "Local", "t"); b.appendChild(label);
    b.onclick = function () { openPlace(g.h3); };
    box.appendChild(b);
    addressParts(g.last.lat, g.last.lng).then(function (p) { if (p) label.textContent = p.street || p.area; });
  });
}

function sortedFeed(list) {
  var out = list.slice();
  if (feedSort === "dirty") out.sort(function (a, b) { return (b.severity == null ? -1 : b.severity) - (a.severity == null ? -1 : a.severity); });
  else if (feedSort === "clean") out.sort(function (a, b) { return (a.severity == null ? 101 : a.severity) - (b.severity == null ? 101 : b.severity); });
  return out; // "new": the server already sends newest first
}

function groupPlaces(list) {
  var groups = {};
  list.forEach(function (r) { if (r.h3_index) (groups[r.h3_index] = groups[r.h3_index] || []).push(r); });
  return Object.keys(groups).map(function (h3) {
    var rs = groups[h3].sort(function (a, b) { return new Date(a.taken_at) - new Date(b.taken_at); });
    return { h3: h3, reports: rs, first: rs[0], last: rs[rs.length - 1] };
  }).sort(function (a, b) { return new Date(b.last.taken_at) - new Date(a.last.taken_at); });
}

export function myCells() { var o = {}; state.feed.forEach(function (r) { if (r.published && r.h3_index) o[r.h3_index] = true; }); return Object.keys(o); }

function renderFeed() {
  var grid = $("feed-grid"); grid.replaceChildren();
  $("st-total").textContent = state.feed.length;
  renderImpact();
  document.querySelectorAll(".pf-tabs button").forEach(function (b) { b.classList.toggle("on", b.dataset.tab === feedTab); });
  var places = feedTab === "places";
  show("feed-grid", !places, "grid"); show("places-list", places, "flex");
  var list = state.feed.filter(function (r) { return feedTab === "pub" ? r.published : feedTab === "wait" ? isPending(r) : true; });
  show("feed-empty", !state.feed.length);
  if (places) return renderPlaces();
  sortedFeed(list).forEach(function (r) {
    var cell = el("button", null, "feed-cell"); cell.type = "button";
    cell.setAttribute("aria-label", "Foto de " + shortDate(r.taken_at) + (r.severity != null ? ", nota " + r.severity : "") + (STATE_TEXT[r.stage] ? ", " + STATE_TEXT[r.stage] : ""));
    if (r.thumb_url) {
      var img = document.createElement("img"); img.src = photoPath(r.thumb_url); img.alt = ""; img.loading = "lazy"; cell.appendChild(img);
    } else {
      cell.appendChild(el("span", "⏳", "wait"));
    }
    if (r.severity != null) { var sc = el("i", String(r.severity), "feed-score"); sc.style.background = levelOf(r.severity).color; sc.style.color = levelOf(r.severity).on; cell.appendChild(sc); }
    if (STATE_TEXT[r.stage] && r.stage !== "published") cell.appendChild(el("span", STATE_TEXT[r.stage], "feed-state"));
    cell.onclick = function () { openMyPhoto(r); };
    grid.appendChild(cell);
  });
}

function renderPlaces() {
  var box = $("places-list"); box.replaceChildren();
  var groups = groupPlaces(state.feed.filter(function (r) { return r.published; }));
  if (!groups.length) { box.appendChild(el("div", "Seus locais publicados aparecem aqui.", "rv-empty")); return; }
  groups.forEach(function (g) {
    var row = el("button", null, "place-row"); row.type = "button";
    var pic = g.last.thumb_url ? document.createElement("img") : el("span", "📍", "ph");
    if (g.last.thumb_url) { pic.src = photoPath(g.last.thumb_url); pic.alt = ""; pic.loading = "lazy"; }
    row.appendChild(pic);
    var txt = el("div"); var title = el("b", g.reports.length + (g.reports.length > 1 ? " fotos" : " foto") + " neste local");
    txt.appendChild(title); txt.appendChild(el("small", "Última em " + shortDate(g.last.taken_at)));
    row.appendChild(txt);
    var lvl = el("span", g.last.severity != null ? levelOf(g.last.severity).label + " · " + g.last.severity : "", "lvl");
    if (g.last.severity != null) lvl.style.color = levelOf(g.last.severity).ink;
    row.appendChild(lvl);
    row.onclick = function () { openPlace(g.h3); };
    box.appendChild(row);
    addressParts(g.last.lat, g.last.lng).then(function (p) { if (p) title.textContent = (p.street || p.area) + " · " + g.reports.length + (g.reports.length > 1 ? " fotos" : " foto"); });
  });
}

var myPhoto = null;

function myError(msg) { $("mp-error").textContent = msg || ""; }

function openMyPhoto(r) {
  myPhoto = r; myError("");
  var level = r.severity != null ? levelOf(r.severity) : null;
  paintLevel($("myphoto"), level);
  $("mp-photo").src = r.photo_url ? photoPath(r.photo_url) : "";
  show("mp-badge", !!level, "flex");
  if (level) $("mp-badge").textContent = "🗑 " + level.label + " · " + r.severity;
  $("mp-date").textContent = shortDate(r.taken_at);
  $("mp-status").textContent = STATUS_LINE[r.stage] || "";
  var box = $("mp-items"); box.replaceChildren();
  (r.trash_types || []).forEach(function (type) {
    var info = TYPE_INFO[type] || ["📦", type], item = el("div", null, "an-item");
    item.appendChild(el("span", info[0], "ico")); item.appendChild(el("span", info[1])); box.appendChild(item);
  });
  if (!box.children.length) box.appendChild(el("div", "Nenhum item específico identificado.", "an-none"));
  $("mp-coords").textContent = r.lat.toFixed(5) + ", " + r.lng.toFixed(5);
  $("mp-address").textContent = "Local escolhido no mapa";
  addressOf(r.lat, r.lng).then(function (text) { if (text && myPhoto === r) $("mp-address").textContent = text; });

  var primary = $("mp-primary"), secondary = $("mp-secondary");
  primary.disabled = secondary.disabled = false;
  show("mp-primary", r.can_publish || r.published, "block");
  primary.textContent = r.published ? "Ver no mapa" : "Publicar no Lixo Livre";
  show("mp-secondary", r.stage !== "analyzing" && r.stage !== "protecting_photo", "block");
  secondary.textContent = "Excluir foto"; secondary.classList.remove("armed");
  show("mp-revisit", !!r.published, "block");
  var group = r.h3_index ? groupPlaces(state.feed.filter(function (x) { return x.h3_index === r.h3_index && x.published && x.thumb_url; })) : [];
  show("mp-share", group.length && group[0].reports.length > 1, "block");
  show("myphoto", true, "flex");
}

// Before / after card: the first and the latest photo of this place, as a picture to share.
function loadImg(url) {
  return new Promise(function (resolve, reject) {
    var i = new Image(); i.onload = function () { resolve(i); }; i.onerror = reject; i.src = url;
  });
}

// The first of these photos that can be loaded (a photo whose file is gone, such as one stored before S3 was
// turned on, is skipped). Returns { report, img }, or null when none of them loads.
async function firstLoadable(reports) {
  for (var i = 0; i < reports.length; i++) {
    try { return { report: reports[i], img: await loadImg(photoPath(reports[i].photo_url)) }; } catch (e) { /* try the next one */ }
  }
  return null;
}

function drawCover(g, img, x, y, w, h) {
  var k = Math.max(w / img.naturalWidth, h / img.naturalHeight), iw = w / k, ih = h / k;
  g.drawImage(img, (img.naturalWidth - iw) / 2, (img.naturalHeight - ih) / 2, iw, ih, x, y, w, h);
}

function ownRequest(method, suffix) {
  return deviceToken().then(function (token) {
    return fetch("/api/v1/me/trashes/" + myPhoto.id + (suffix || ""), { method: method, headers: { "X-Device-Token": token } });
  });
}

function finishMyPhoto(message) {
  show("myphoto", false); myPhoto = null; toast(message); loadFeed(); loadHeat();
}

function ownFailure(res) {
  return res.status === 404 ? "Esta foto não está na sua conta (ou já foi excluída)." : "Não foi possível agora. Tente de novo.";
}

var armDelete = null;

export function boot() {
  document.querySelectorAll(".pf-tabs button").forEach(function (b) { b.onclick = function () { feedTab = b.dataset.tab; renderFeed(); }; });

  $("pf-sort").onchange = function () { feedSort = this.value; renderFeed(); };

  $("pf-mine").onclick = function () {
    mineOnly = !mineOnly; this.classList.toggle("on", mineOnly);
    applyFilter();
    if (mineOnly) { var c = myCells(); toast(c.length ? "Mostrando só os locais das suas fotos." : "Você ainda não tem fotos publicadas."); goPage("map"); }
  };

  $("mp-revisit").onclick = function () {
    if (!myPhoto) return;
    var at = [myPhoto.lng, myPhoto.lat]; show("myphoto", false); myPhoto = null; goPage("map");
    openReport("dirty", at);
  };

  $("mp-share").onclick = async function () {
    if (!myPhoto) return;
    var button = this; button.disabled = true; myError("");
    try {
      var g1 = groupPlaces(state.feed.filter(function (x) { return x.h3_index === myPhoto.h3_index && x.published && x.photo_url; }))[0];
      var oldest = await firstLoadable(g1.reports), newest = await firstLoadable(g1.reports.slice().reverse());
      if (!oldest || !newest || oldest.report.id === newest.report.id) { myError("Este local ainda não tem duas fotos disponíveis para comparar."); button.disabled = false; return; }
      var before = oldest.report, after = newest.report, imgs = [oldest.img, newest.img];
      var W = 1080, H = 1350, c = document.createElement("canvas"); c.width = W; c.height = H;
      var g = c.getContext("2d");
      g.fillStyle = "#14231a"; g.fillRect(0, 0, W, H);
      g.fillStyle = "#fff"; g.font = "700 56px system-ui, sans-serif"; g.fillText("Lixo Livre", 60, 100);
      g.font = "400 30px system-ui, sans-serif"; g.fillStyle = "#b9c8bd"; g.fillText("Antes e depois deste local", 60, 146);
      [[before, imgs[0], "ANTES"], [after, imgs[1], "DEPOIS"]].forEach(function (x, idx) {
        var px = 60, py = 190 + idx * 550, w = 960, h = 500, lv = x[0].severity != null ? levelOf(x[0].severity) : null;
        drawCover(g, x[1], px, py, w, h);
        g.fillStyle = lv ? lv.color : "#555"; g.fillRect(px, py, 330, 70);
        g.fillStyle = lv ? lv.on : "#fff"; g.font = "700 34px system-ui, sans-serif";
        g.fillText(x[2] + (x[0].severity != null ? " · " + x[0].severity + "/100" : ""), px + 18, py + 47);
        g.fillStyle = "#fff"; g.font = "400 26px system-ui, sans-serif"; g.fillText(shortDate(x[0].taken_at), px + w - 190, py + h - 20);
      });
      var blob = await new Promise(function (res) { c.toBlob(res, "image/jpeg", 0.9); });
      if (!blob) throw new Error("blob");
      var file = new File([blob], "lixo-livre-antes-e-depois.jpg", { type: "image/jpeg" });
      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title: "Lixo Livre", text: "Antes e depois no Lixo Livre" });
      } else {
        var a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = file.name; a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); }, 4000); toast("Imagem salva.");
      }
    } catch (e) {
      if (!e || e.name !== "AbortError") myError("Não foi possível criar a imagem agora.");
    }
    button.disabled = false;
  };

  $("mp-primary").onclick = async function () {
    if (!myPhoto) return;
    if (myPhoto.published) { show("myphoto", false); goPage("map"); map.jumpTo({ center: [myPhoto.lng, myPhoto.lat], zoom: 17 }); return; }
    this.disabled = true; myError("");
    try {
      var res = await ownRequest("POST", "/publish");
      if (res.ok) return finishMyPhoto("Publicada no mapa!");
      myError(ownFailure(res));
    } catch (e) { myError("Sem conexão. Tente de novo."); }
    this.disabled = false;
  };

  $("mp-secondary").onclick = async function () {
    if (!myPhoto) return;
    var button = this;
    if (!button.classList.contains("armed")) { // two taps: the first only arms it
      button.classList.add("armed"); button.textContent = myPhoto.published ? "Toque de novo: sai do mapa" : "Toque de novo para excluir";
      armDelete = setTimeout(function () { button.classList.remove("armed"); button.textContent = "Excluir foto"; }, 3500);
      return;
    }
    clearTimeout(armDelete); button.disabled = true; myError("");
    try {
      var res = await ownRequest("DELETE");
      if (res.ok || res.status === 204) return finishMyPhoto("Foto excluída.");
      myError(ownFailure(res));
    } catch (e) { myError("Sem conexão. Tente de novo."); }
    button.disabled = false;
  };

  $("mp-back").onclick = function () { show("myphoto", false); myPhoto = null; };
}
