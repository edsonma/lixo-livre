// Deleting the account.

import { state } from "./state.js";
import { api, saveToken } from "./api.js";
import { applyAuth } from "./auth.js";
import { $, toast } from "./dom.js";
import { loadHeat } from "./map.js";
import { goPage } from "./navigation.js";

var armDeleteAccount = null;

export function boot() {
  $("pf-delete").onclick = async function () {
    var b = this;
    if (!b.classList.contains("armed")) {
      b.classList.add("armed"); b.textContent = "Toque de novo: apaga conta e fotos";
      armDeleteAccount = setTimeout(function () { b.classList.remove("armed"); b.textContent = "Excluir minha conta"; }, 4000);
      return;
    }
    clearTimeout(armDeleteAccount); b.disabled = true;
    var r = await api("/api/v1/account", "DELETE").catch(function () { return null; });
    b.disabled = false; b.classList.remove("armed"); b.textContent = "Excluir minha conta";
    if (!r || !(r.ok || r.status === 204)) return toast("Não foi possível excluir agora. Tente de novo.");
    state.me = null; saveToken(""); applyAuth(); state.feed = []; goPage("map"); loadHeat(); toast("Conta excluída.");
  };
}
