// Following a place, and the notifications it brings.

import { state } from "./state.js";
import { api } from "./api.js";
import { openAuth } from "./auth.js";
import { $, el, show, toast } from "./dom.js";
import { closePlace, openPlace, place } from "./place.js";

export function setFollowButton(following) {
  var b = $("dt-follow"); b.classList.toggle("on", !!following);
  b.textContent = following ? "🔔 Seguindo · toque para parar" : "🔔 Seguir este local";
}

var ALERT_TEXT = {
  worse: ["⚠️", "Local que você segue piorou"],
  cleaned: ["✅", "Local que você segue foi limpo"]
};

function timeAgo(iso) {
  var m = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (m < 2) return "agora"; if (m < 60) return "há " + m + " min";
  var h = Math.round(m / 60); if (h < 24) return "há " + h + " h";
  return "há " + Math.round(h / 24) + " d";
}

function setBadge(count) {
  ["bell-count", "nav-alerts-count"].forEach(function (id) {
    var b = $(id); if (!b) return;
    b.textContent = count > 9 ? "9+" : String(count); b.style.display = count ? "" : "none";
  });
  show("pf-dot", !!count && !!state.me, "inline-block");
}

var alertsTimer = null;

export async function pollAlerts() {
  clearTimeout(alertsTimer);
  if (!state.me) return setBadge(0);
  var res = await api("/api/v1/notifications").catch(function () { return null; });
  if (res && res.ok) setBadge(res.data.unread);
  alertsTimer = setTimeout(pollAlerts, 60000);
}

export async function openAlerts() {
  var body = $("al-body"); body.replaceChildren(el("div", "Carregando…", "rv-empty"));
  show("alerts", true, "flex");
  var res = await api("/api/v1/notifications").catch(function () { return null; });
  body.replaceChildren();
  if (!res || !res.ok) return body.appendChild(el("div", "Não foi possível carregar agora.", "rv-empty"));
  if (!res.data.items.length) {
    body.appendChild(el("div", "Sem avisos por enquanto. Toque em “Seguir este local” nos detalhes de um local e avisamos quando ele piorar ou for limpo.", "rv-empty"));
  }
  res.data.items.forEach(function (n) {
    var info = ALERT_TEXT[n.kind] || ["🔔", "Novidade"], item = el("button", null, "al-item" + (n.read ? "" : " unread")); item.type = "button";
    item.appendChild(el("span", info[0], "ico"));
    var txt = el("div"), sub = n.kind === "worse" ? "Nota " + Math.round(n.previous_score || 0) + " → " + Math.round(n.score || 0) : "Agora aparece como limpo no mapa";
    txt.appendChild(el("b", info[1])); txt.appendChild(el("small", sub + " · " + timeAgo(n.created_at)));
    item.appendChild(txt);
    item.onclick = function () { show("alerts", false); openPlace(n.h3); };
    body.appendChild(item);
  });
  if (res.data.unread) { setBadge(0); api("/api/v1/notifications/read", "POST").catch(function () {}); }
}

export function boot() {
  $("dt-follow").onclick = async function () {
    if (!place) return;
    if (!state.me) { closePlace(); return openAuth("Entre para seguir este local e receber avisos."); }
    var button = this, h3 = place.h3, was = !!place.following;
    button.disabled = true;
    var res = await (was ? api("/api/v1/follows/" + encodeURIComponent(h3), "DELETE") : api("/api/v1/follows", "POST", { h3_index: h3 })).catch(function () { return null; });
    button.disabled = false;
    if (!res || !(res.ok || res.status === 204)) return toast("Não foi possível agora. Tente de novo.");
    if (place && place.h3 === h3) { place.following = !was; setFollowButton(place.following); }
    toast(was ? "Você parou de seguir este local." : "Você vai receber um aviso se este local piorar ou for limpo.");
  };

  $("al-back").onclick = function () { show("alerts", false); };
}
