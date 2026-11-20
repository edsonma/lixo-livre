// Moderation (admins and moderators): held reports and flagged photos.

import { api } from "./api.js";
import { $, el, show, toast } from "./dom.js";
import { levelOf, loadHeat, map, paintLevel } from "./map.js";
import { goPage } from "./navigation.js";
import { photoPath, shortDate } from "./place.js";

var REASON_TEXT = {
  not_trash: "não é lixo", privacy: "privacidade", inappropriate: "inadequada", duplicate: "duplicada", wrong_location: "local errado"
};

function reasonText(r) {
  if (r.kind === "flagged") {
    var parts = Object.keys(r.flags || {}).map(function (k) { return (REASON_TEXT[k] || k) + (r.flags[k] > 1 ? " ×" + r.flags[k] : ""); });
    return "Denunciada: " + (parts.join(", ") || "sem motivo") + (r.hidden ? " (já escondida)" : "");
  }
  if (r.reason === "metadata_mismatch") {
    var far = r.exif_distance_m ? " (a foto foi tirada a " + (r.exif_distance_m >= 1000 ? (r.exif_distance_m / 1000).toFixed(1) + " km" : r.exif_distance_m + " m") + " do pino)" : "";
    return "A foto parece ter sido tirada longe do local marcado ou em outra data" + far + ".";
  }
  if (r.reason === "low_confidence") return "A IA ficou em dúvida" + (r.ai_confidence ? " (" + Math.round(r.ai_confidence * 100) + "% de confiança)" : "") + ".";
  if (r.reason === "failed") return "Falha técnica no processamento" + (r.hold_reason ? ": " + r.hold_reason : "") + ".";
  return "Aguardando revisão.";
}

function reviewCard(r) {
  var card = el("div", null, "rv-card");
  var photo = el("div", null, "rv-photo");
  if (r.photo_url) {
    var img = document.createElement("img"); img.src = photoPath(r.photo_url); img.alt = "Foto enviada"; img.loading = "lazy"; photo.appendChild(img);
  } else {
    photo.appendChild(el("div", "Foto ainda não protegida (rostos e placas não foram borrados). Ela não é mostrada e não pode ser aprovada.", "rv-nophoto"));
  }
  photo.appendChild(el("span", r.kind === "flagged" ? "Denunciada" : "Em revisão", "rv-tag"));
  card.appendChild(photo);
  card.appendChild(el("div", reasonText(r), "rv-reason"));

  var meta = el("div", null, "rv-meta");
  meta.appendChild(document.createTextNode((r.uploader ? r.uploader.name + " (" + r.uploader.email + ")" : "Anônimo") + " · " + shortDate(r.taken_at) + " · " + r.lat.toFixed(4) + ", " + r.lng.toFixed(4) + " · "));
  var see = el("button", "ver no mapa", "link"); see.type = "button";
  see.onclick = function () { show("review", false); goPage("map"); map.jumpTo({ center: [r.lng, r.lat], zoom: 17 }); };
  meta.appendChild(see);
  card.appendChild(meta);

  var slider = null;
  if (r.kind === "held") {
    var box = el("div", null, "rv-sev");
    var label = el("label"); label.appendChild(el("span", "Nível de sujeira")); var value = el("b"); label.appendChild(value);
    slider = document.createElement("input"); slider.type = "range"; slider.min = 0; slider.max = 100; slider.value = r.severity != null ? r.severity : 50;
    var paint = function () { var l = levelOf(+slider.value); value.textContent = l.label + " · " + slider.value; paintLevel(box, l); };
    slider.oninput = paint; paint();
    box.appendChild(label); box.appendChild(slider); card.appendChild(box);
  }

  var err = el("div", null, "error"); err.setAttribute("role", "alert");
  var actions = el("div", null, "rv-actions");
  var yes = el("button", r.kind === "held" ? "Aprovar e publicar" : "Manter no mapa", "btn primary"); yes.type = "button";
  var no = el("button", r.kind === "held" ? "Rejeitar" : "Remover", "btn danger"); no.type = "button";
  if (r.kind === "held" && !r.photo_url) yes.disabled = true;

  async function act(path, body, done) {
    yes.disabled = no.disabled = true; err.textContent = "";
    try {
      var res = await api("/api/v1/admin/reviews/" + r.id + "/" + path, "POST", body || {});
      if (!res.ok) { err.textContent = res.status === 403 ? "Você não tem permissão." : (res.data.message || "Não foi possível agora."); yes.disabled = no.disabled = false; return; }
      card.remove(); toast(done); refreshReviewCount(); loadHeat();
      if (!$("rv-body").querySelector(".rv-card")) loadReviews();
    } catch (e) { err.textContent = "Sem conexão. Tente de novo."; yes.disabled = no.disabled = false; }
  }
  yes.onclick = function () { act("approve", slider ? { severity: +slider.value } : {}, r.kind === "held" ? "Publicado no mapa." : "Mantida no mapa."); };
  var armTimer = null;
  no.onclick = function () { // two taps: the first only arms it
    if (!no.classList.contains("armed")) {
      no.classList.add("armed"); no.textContent = "Toque de novo para confirmar";
      armTimer = setTimeout(function () { no.classList.remove("armed"); no.textContent = r.kind === "held" ? "Rejeitar" : "Remover"; }, 3500);
      return;
    }
    clearTimeout(armTimer);
    act("reject", {}, r.kind === "held" ? "Rejeitada." : "Removida do mapa.");
  };
  actions.appendChild(yes); actions.appendChild(no);
  card.appendChild(actions); card.appendChild(err);
  return card;
}

async function loadReviews() {
  var body = $("rv-body"); body.replaceChildren(el("div", "Carregando…", "rv-empty"));
  var res = await api("/api/v1/admin/reviews").catch(function () { return null; });
  body.replaceChildren();
  if (!res || !res.ok) { body.appendChild(el("div", res && res.status === 403 ? "Você não tem permissão para moderar." : "Não foi possível carregar a fila agora.", "rv-empty")); return; }
  var d = res.data;
  $("pf-review-count").textContent = (d.counts.held + d.counts.flagged) || "";
  if (!d.held.length && !d.flagged.length) { body.appendChild(el("div", "Nada para revisar por enquanto. 🎉", "rv-empty")); return; }
  if (d.held.length) { body.appendChild(el("h3", "Em revisão (" + d.counts.held + ")")); d.held.forEach(function (r) { body.appendChild(reviewCard(r)); }); }
  if (d.flagged.length) { body.appendChild(el("h3", "Fotos denunciadas (" + d.counts.flagged + ")")); d.flagged.forEach(function (r) { body.appendChild(reviewCard(r)); }); }
}

export async function refreshReviewCount() {
  var res = await api("/api/v1/admin/reviews").catch(function () { return null; });
  if (res && res.ok) $("pf-review-count").textContent = (res.data.counts.held + res.data.counts.flagged) || "";
}

export function boot() {
  $("pf-review").onclick = function () { show("review", true, "flex"); loadReviews(); };

  $("rv-back").onclick = function () { show("review", false); };

  $("rv-refresh").onclick = loadReviews;
}
