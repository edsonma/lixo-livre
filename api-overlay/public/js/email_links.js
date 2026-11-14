// Email confirmation, and the links in emails (?verify=, ?reset=).

import { state } from "./state.js";
import { api } from "./api.js";
import { loadMe, openAuth } from "./auth.js";
import { $, toast } from "./dom.js";

export async function handleEmailLinks() {
  var q = new URLSearchParams(location.search), verify = q.get("verify"), reset = q.get("reset");
  if (!verify && !reset) return;
  try { history.replaceState(history.state, "", location.pathname); } catch (e) {} // the token must not stay in the address bar
  if (verify) {
    var r = await api("/api/v1/email/verify", "POST", { token: verify }).catch(function () { return null; });
    if (r && r.ok) { await loadMe(); toast("E-mail confirmado! Agora você já pode reportar."); }
    else toast("Este link de confirmação expirou ou já foi usado. Entre e peça um novo no perfil.");
  } else {
    state.resetToken = reset; openAuth("Escolha uma nova senha para a sua conta.", "reset");
  }
}

export function boot() {
  $("pf-verify-resend").onclick = async function () {
    this.disabled = true;
    var r = await api("/api/v1/email/resend", "POST").catch(function () { return null; });
    this.disabled = false;
    toast(r && (r.ok || r.status === 204) ? "Enviamos o e-mail de novo. Olhe também o spam." : "Não foi possível enviar agora. Tente de novo em instantes.");
  };
}
