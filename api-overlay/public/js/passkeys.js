// Passkeys (fingerprint / face) for sign-in and for adding a device.

import { state } from "./state.js";
import { api } from "./api.js";
import { applyAuth, authError, signedIn } from "./auth.js";
import { $, toast } from "./dom.js";

// Passkeys: base64url <-> bytes, because the server speaks JSON and the browser speaks ArrayBuffers.
function fromB64(text) {
  var b64 = String(text).replace(/-/g, "+").replace(/_/g, "/"), pad = (4 - b64.length % 4) % 4;
  var bin = atob(b64 + "====".slice(0, pad)), bytes = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function toB64(buffer) {
  var bytes = new Uint8Array(buffer), bin = "";
  for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// What went wrong, in words, with the technical detail at the end so it can be reported.
function serverDetail(r) { return "servidor " + r.status + (r.data && (r.data.message || r.data.error) ? " – " + (r.data.message || r.data.error) : ""); }

function passkeyMessage(e, fallback, withDetail) {
  var name = e && e.name;
  if (name === "NotAllowedError") return "Cancelado ou não reconhecido pelo aparelho. Tente de novo.";
  if (name === "InvalidStateError") return "Este aparelho já tem biometria ativa nesta conta.";
  if (name === "NotSupportedError") return "Este aparelho ou navegador não aceita biometria (passkeys). Verifique se há bloqueio de tela (digital, rosto ou PIN).";
  if (name === "SecurityError") return "O navegador bloqueou a biometria para este endereço (precisa ser https).";
  return withDetail ? fallback + " (" + (e && (e.message || e.name) || "erro desconhecido") + ")." : fallback;
}

async function addPasskey() {
  $("pf-passkey").disabled = true; $("pf-passkey-info").textContent = "";
  try {
    var o = await api("/api/v1/passkeys/registration_options", "POST");
    if (!o.ok) throw new Error(serverDetail(o));
    var pk = o.data;
    pk.challenge = fromB64(pk.challenge); pk.user.id = fromB64(pk.user.id);
    (pk.excludeCredentials || []).forEach(function (c) { c.id = fromB64(c.id); });
    var cred = await navigator.credentials.create({ publicKey: pk });
    var r = await api("/api/v1/passkeys", "POST", { nickname: (navigator.platform || "Aparelho"), credential: {
      id: cred.id, rawId: toB64(cred.rawId), type: cred.type,
      response: { attestationObject: toB64(cred.response.attestationObject), clientDataJSON: toB64(cred.response.clientDataJSON) },
      clientExtensionResults: cred.getClientExtensionResults ? cred.getClientExtensionResults() : {}
    } });
    if (!r.ok) throw new Error(serverDetail(r));
    state.me.passkeys = (state.me.passkeys || 0) + 1; applyAuth(); toast("Biometria ativada!");
  } catch (e) {
    $("pf-passkey-info").textContent = passkeyMessage(e, "Não foi possível ativar a biometria", true);
  }
  $("pf-passkey").disabled = false;
}

async function passkeyLogin() {
  authError(""); $("au-passkey").disabled = true;
  try {
    var o = await api("/api/v1/passkeys/authentication_options", "POST");
    if (!o.ok) throw new Error(serverDetail(o));
    var pk = o.data; pk.challenge = fromB64(pk.challenge);
    (pk.allowCredentials || []).forEach(function (c) { c.id = fromB64(c.id); });
    var cred = await navigator.credentials.get({ publicKey: pk });
    var r = await api("/api/v1/passkeys/authenticate", "POST", { credential: {
      id: cred.id, rawId: toB64(cred.rawId), type: cred.type,
      response: {
        authenticatorData: toB64(cred.response.authenticatorData), clientDataJSON: toB64(cred.response.clientDataJSON),
        signature: toB64(cred.response.signature), userHandle: cred.response.userHandle ? toB64(cred.response.userHandle) : null
      },
      clientExtensionResults: cred.getClientExtensionResults ? cred.getClientExtensionResults() : {}
    } });
    if (r.ok) signedIn(r.data.user); else authError("Biometria não reconhecida. Entre com e-mail e senha.");
  } catch (e) {
    authError(passkeyMessage(e, "Não foi possível usar a biometria", true));
  }
  $("au-passkey").disabled = false;
}

export function boot() {
  $("pf-passkey").onclick = addPasskey;

  $("au-passkey").onclick = passkeyLogin;
}
