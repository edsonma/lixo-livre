// Analysis screen: the AI's result. Already on the map: "Ver no mapa" or "Fechar". Not yet: "Publicar no Lixo Livre" or "Descartar foto".

import { state } from "./state.js";
import { TYPE_INFO } from "./analysis_types.js";
import { deviceToken } from "./api.js";
import { $, el, show } from "./dom.js";
import { levelOf, loadHeat, loadHeatSoon, map, paintLevel } from "./map.js";
import { goPage } from "./navigation.js";
import { closeReport, setStatus } from "./report_flow.js";

function anMessage(msg) { $("an-error").textContent = msg || ""; }

// { street, area } from OpenStreetMap, or null when it cannot say.
export async function addressParts(lat, lng) {
  try {
    var res = await fetch("https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&lat=" + lat + "&lon=" + lng, { headers: { "Accept-Language": "pt-BR" } });
    if (!res.ok) return null;
    var a = (await res.json()).address || {};
    var street = a.road || a.pedestrian || a.footway || a.path || null;
    var area = [a.suburb || a.neighbourhood || a.quarter, a.city || a.town || a.village, a.state].filter(Boolean).join(" - ");
    return street || area ? { street: street, area: area } : null;
  } catch (e) { return null; }
}

export async function addressOf(lat, lng) {
  var parts = await addressParts(lat, lng);
  return parts ? [parts.street, parts.area].filter(Boolean).join(", ") : null;
}

export function showAnalysis(r) {
  state.draft = r; state.step = "analysis";
  var level = levelOf(r.severity);
  paintLevel($("analysis"), level);
  $("an-level").textContent = level.label;
  $("an-num").textContent = r.severity;
  try { $("an-photo").src = new URL(r.photo_url, location.href).pathname; } catch (e) {}
  var box = $("an-items"); box.replaceChildren();
  (r.trash_types || []).forEach(function (type) {
    var info = TYPE_INFO[type] || ["📦", type];
    var item = el("div", null, "an-item");
    item.appendChild(el("span", info[0], "ico")); item.appendChild(el("span", info[1]));
    box.appendChild(item);
  });
  if (!box.children.length) box.appendChild(el("div", "Nenhum item específico identificado.", "an-none"));
  $("an-address").textContent = "Local escolhido no mapa";
  $("an-coords").textContent = r.lat.toFixed(5) + ", " + r.lng.toFixed(5);
  var done = !!(r.published || r.stage === "published"), cleanup = r.kind === "cleanup";
  $("an-title").textContent = done ? (cleanup ? "Limpeza confirmada" : "Foto publicada") : "Análise da imagem";
  $("an-note").textContent = done ? (cleanup ? "Obrigado! Este local aparece como limpo no mapa." : "Já está no mapa. Obrigado por ajudar!") : "";
  show("an-note", done, "block");
  $("an-publish").textContent = done ? "Ver no mapa" : "Publicar no Lixo Livre";
  $("an-discard").textContent = done ? "Fechar" : "Descartar foto"; // nothing is left to finish once it is on the map; before that, this button deletes the report
  anMessage(""); $("an-publish").disabled = false; $("an-discard").disabled = false;
  show("report", false); show("analysis", true, "flex");
  addressOf(r.lat, r.lng).then(function (text) { if (text && state.draft === r) $("an-address").textContent = text; });
}

async function ownReportRequest(method, suffix) {
  var token = await deviceToken();
  return fetch("/api/v1/me/trashes/" + state.draft.id + (suffix || ""), { method: method, headers: { "X-Device-Token": token } });
}

export function boot() {
  $("an-publish").onclick = async function () {
    if (!state.draft) return;
    if (state.draft.published || state.draft.stage === "published") { // already on the map: just go and look at it
      var at = [state.draft.lng, state.draft.lat]; state.draft = null; closeReport(); loadHeat();
      goPage("map"); // whichever page the report was started from (Perfil, say), the person ends up looking at the map
      map.jumpTo({ center: at, zoom: 17 }); loadHeatSoon();
      return;
    }
    anMessage(""); $("an-publish").disabled = true; $("an-discard").disabled = true;
    try {
      var res = await ownReportRequest("POST", "/publish");
      if (!res.ok) throw new Error("Não foi possível publicar agora. Tente de novo.");
      show("analysis", false);
      setStatus(false, "Publicado no mapa. Obrigado por ajudar!");
      show("progress", true); show("report", true); state.step = "progress";
      $("again").style.display = "inline-block"; $("done").style.display = "inline-block";
      state.draft = null;
      // the heat cell is re-scored in the background: look again a little later
      loadHeatSoon();
    } catch (e) {
      anMessage(e.message); $("an-publish").disabled = false; $("an-discard").disabled = false;
    }
  };

  // "Descartar foto" (or the back arrow): the report was never published, so it is deleted. "Fechar": it stays on the map.
  $("an-discard").onclick = $("an-back").onclick = async function () {
    if (!state.draft) return closeReport();
    if (state.draft.published || state.draft.stage === "published") { state.draft = null; closeReport(); loadHeat(); return; } // it stays on the map
    anMessage(""); $("an-publish").disabled = true; $("an-discard").disabled = true;
    try {
      var res = await ownReportRequest("DELETE");
      if (!res.ok && res.status !== 404) throw new Error("Não foi possível descartar agora. Tente de novo.");
      state.draft = null; closeReport();
    } catch (e) {
      anMessage(e.message); $("an-publish").disabled = false; $("an-discard").disabled = false;
    }
  };
}
