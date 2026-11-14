// Terms of Use and Privacy Policy, and asking for consent.

import { state } from "./state.js";
import { api } from "./api.js";
import { applyAuth } from "./auth.js";
import { status } from "./core.js";
import { $, el, show } from "./dom.js";

var legalTab = "terms";

var afterAccept = null;

function showLegal(tab, acceptMode) {
  legalTab = tab === "privacy" ? "privacy" : "terms";
  var doc = window.LEGAL(status.legal)[legalTab], body = $("lg-body"); body.replaceChildren();
  $("lg-title").textContent = doc.title;
  $("lg-tab-terms").classList.toggle("on", legalTab === "terms"); $("lg-tab-privacy").classList.toggle("on", legalTab === "privacy");
  doc.sections.forEach(function (sec) { body.appendChild(el("h3", sec[0])); body.appendChild(el("p", sec[1])); });
  body.appendChild(el("p", "Versão de " + ((status.legal && status.legal.version) || ""), "lg-version"));
  body.scrollTop = 0;
  if (acceptMode !== undefined) { show("lg-accept-box", acceptMode, "flex"); }
  show("legal", true, "flex");
}

// People who signed up before the terms existed (or when they change) accept once, before reporting.
export function askConsent(next) {
  afterAccept = next || null;
  $("lg-check").checked = false; $("lg-accept").disabled = true; $("lg-error").textContent = "";
  showLegal("terms", true);
}

export function boot() {
  document.addEventListener("click", function (e) {
    var t = e.target.closest && e.target.closest("[data-legal]");
    if (!t) return;
    e.preventDefault();
    showLegal(t.dataset.legal, t.classList.contains("link") ? false : undefined);
  });

  $("lg-back").onclick = function () { show("legal", false); afterAccept = null; };

  $("lg-check").onchange = function () { $("lg-accept").disabled = !this.checked; };

  $("lg-accept").onclick = async function () {
    this.disabled = true; $("lg-error").textContent = "";
    var r = await api("/api/v1/consent", "POST", { accepted_terms: true }).catch(function () { return null; });
    if (!r || !r.ok) { this.disabled = false; $("lg-error").textContent = "Não foi possível registrar agora. Tente de novo."; return; }
    state.me = r.data.user; applyAuth(); show("legal", false);
    var next = afterAccept; afterAccept = null; if (next) next();
  };
}
