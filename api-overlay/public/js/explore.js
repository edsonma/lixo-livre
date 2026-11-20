// Explorar: the worst places near me and a ranking of regions.

import { addressParts } from "./analysis.js";
import { api } from "./api.js";
import { $, el } from "./dom.js";
import { levelOf, map } from "./map.js";
import { trendBadge } from "./map_filters.js";
import { goPage } from "./navigation.js";
import { openPlace } from "./place.js";

var userPos = null;

var rankRun = 0;

var regionNames = {};

function currentCenter() {
  return new Promise(function (resolve) {
    var fallback = function () { var c = map.getCenter(); resolve({ lat: c.lat, lng: c.lng, here: false }); };
    if (userPos) return resolve(userPos);
    if (!navigator.geolocation) return fallback();
    navigator.geolocation.getCurrentPosition(function (pos) {
      userPos = { lat: pos.coords.latitude, lng: pos.coords.longitude, here: true }; resolve(userPos);
    }, fallback, { timeout: 4000, maximumAge: 300000 });
  });
}

function metersText(m) { return m < 1000 ? m + " m" : (m / 1000).toFixed(1).replace(".", ",") + " km"; }

export async function loadRankings() {
  var run = ++rankRun, c = await currentCenter();
  $("ex-where").textContent = c.here ? "Perto de você" : "Perto do centro do mapa";
  var res = await api("/api/v1/rankings?lat=" + c.lat + "&lng=" + c.lng + "&radius_km=10").catch(function () { return null; });
  if (run !== rankRun) return;
  var worstBox = $("ex-worst"), regBox = $("ex-regions"); worstBox.replaceChildren(); regBox.replaceChildren();
  if (!res || !res.ok) { worstBox.appendChild(el("div", "Não foi possível carregar agora.", "rv-empty")); return; }
  if (!res.data.worst.length) worstBox.appendChild(el("div", "Nenhum local sujo por perto. 🎉", "rv-empty"));
  res.data.worst.forEach(function (w, i) {
    var row = el("button", null, "place-row"); row.type = "button";
    row.appendChild(el("span", String(i + 1), "rank"));
    var txt = el("div"), title = el("b", "Local a " + metersText(w.meters));
    txt.appendChild(title); txt.appendChild(el("small", w.count + (w.count > 1 ? " registros" : " registro")));
    row.appendChild(txt);
    var meta = el("div", null, "meta"), lvl = el("span", levelOf(w.score).label + " · " + Math.round(w.score), "lvl");
    lvl.style.color = levelOf(w.score).ink; meta.appendChild(lvl);
    var tb = trendBadge(w.trend); if (tb) meta.appendChild(tb);
    row.appendChild(meta);
    row.onclick = function () { openPlace(w.h3); };
    worstBox.appendChild(row);
    addressParts(w.lat, w.lng).then(function (p) { if (p && run === rankRun) title.textContent = (p.street || p.area) + " · " + metersText(w.meters); });
  });
  if (!res.data.regions.length) regBox.appendChild(el("div", "Sem regiões para classificar ainda.", "rv-empty"));
  res.data.regions.forEach(function (r, i) {
    var row = el("button", null, "place-row"); row.type = "button";
    row.appendChild(el("span", String(i + 1), "rank"));
    var txt = el("div"), title = el("b", regionNames[r.region] || "Região"); 
    txt.appendChild(title); txt.appendChild(el("small", r.cells + (r.cells > 1 ? " locais sujos" : " local sujo")));
    row.appendChild(txt);
    var meta = el("div", null, "meta"), lvl = el("span", "média " + Math.round(r.score), "lvl");
    lvl.style.color = levelOf(r.score).ink; meta.appendChild(lvl);
    var tb = trendBadge(r.trend); if (tb) meta.appendChild(tb);
    row.appendChild(meta);
    row.onclick = function () { goPage("map"); map.flyTo({ center: [r.lng, r.lat], zoom: 14 }); };
    regBox.appendChild(row);
    if (!regionNames[r.region]) setTimeout(function () {
      if (run !== rankRun) return;
      addressParts(r.lat, r.lng).then(function (p) { if (p) { regionNames[r.region] = p.area || p.street; title.textContent = regionNames[r.region]; } });
    }, 350 * (i + 1));
  });
}

export function boot() {
  $("ex-refresh").onclick = function () { userPos = null; loadRankings(); };
}
