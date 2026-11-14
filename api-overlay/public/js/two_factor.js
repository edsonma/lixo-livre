// Two-factor login (authenticator app).

import { state } from "./state.js";
import { api } from "./api.js";
import { applyAuth } from "./auth.js";
import { $, show, toast } from "./dom.js";

function tfError(msg) { $("tf-error").textContent = msg || ""; }

function tfShow(section) { ["tf-off", "tf-setup", "tf-codes", "tf-on"].forEach(function (id) { show(id, id === section); }); tfError(""); }

export function boot() {
  $("set-2fa").onclick = function () { tfShow(state.me && state.me.two_factor ? "tf-on" : "tf-off"); $("tf-off-code").value = ""; show("twofa", true, "flex"); };

  $("tf-back").onclick = function () { show("twofa", false); };

  $("tf-start").onclick = async function () {
    this.disabled = true; tfError("");
    var r = await api("/api/v1/two_factor/setup", "POST").catch(function () { return null; });
    this.disabled = false;
    if (!r || !r.ok) return tfError("Não foi possível iniciar agora. Tente de novo.");
    $("tf-secret").textContent = r.data.secret.replace(/(.{4})/g, "$1 ").trim();
    $("tf-link").href = r.data.uri; $("tf-code").value = "";
    tfShow("tf-setup");
  };

  $("tf-enable").onclick = async function () {
    this.disabled = true; tfError("");
    var r = await api("/api/v1/two_factor/enable", "POST", { code: $("tf-code").value.trim() }).catch(function () { return null; });
    this.disabled = false;
    if (!r) return tfError("Sem conexão. Tente de novo.");
    if (!r.ok) return tfError(r.status === 429 ? "Muitas tentativas. Aguarde alguns minutos." : "Código incorreto. Confira o código atual do app (muda a cada 30 segundos).");
    state.me = r.data.user; applyAuth();
    $("tf-codes-list").textContent = r.data.recovery_codes.join("\n");
    tfShow("tf-codes");
  };

  $("tf-copy").onclick = function () {
    var text = $("tf-codes-list").textContent;
    (navigator.clipboard ? navigator.clipboard.writeText(text) : Promise.reject()).then(function () { toast("Códigos copiados."); }, function () { toast("Selecione e copie os códigos manualmente."); });
  };

  $("tf-done").onclick = function () { $("tf-codes-list").textContent = ""; show("twofa", false); toast("Verificação em duas etapas ativada."); };

  $("tf-disable").onclick = async function () {
    this.disabled = true; tfError("");
    var r = await api("/api/v1/two_factor/disable", "POST", { code: $("tf-off-code").value.trim() }).catch(function () { return null; });
    this.disabled = false;
    if (!r) return tfError("Sem conexão. Tente de novo.");
    if (!r.ok) return tfError("Código incorreto.");
    state.me = r.data.user; applyAuth(); show("twofa", false); toast("Verificação em duas etapas desativada.");
  };
}
