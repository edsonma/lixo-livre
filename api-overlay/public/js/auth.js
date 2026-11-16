// Accounts: sign in, sign up, Google, password reset, sign out.

import { state } from "./state.js";
import { api, saveToken } from "./api.js";
import { status } from "./core.js";
import { $, show, toast } from "./dom.js";
import { paintAvatar, safeWebAddress } from "./avatar.js";
import { refreshReviewCount } from "./moderation.js";
import { loadFeed } from "./my_photos.js";
import { currentPage, goPage } from "./navigation.js";
import { pollAlerts } from "./notifications.js";
import { closeReport } from "./report_flow.js";

var authMode = "in";

var googleLoaded = false;

var passkeysSupported = !!(window.PublicKeyCredential && navigator.credentials && navigator.credentials.create);

function firstName(user) { return String(user.name || user.email).split(" ")[0]; }

// What the page shows depends on being logged in: the + button, the account icon, the profile page.
export function applyAuth() {
  $("report-btn").style.display = state.me ? "" : "none"; // only logged-in people can report
  $("acct-icon").style.display = state.me ? "none" : "";
  $("acct-initial").style.display = state.me ? "flex" : "none";
  $("acct").setAttribute("aria-label", state.me ? "Conta de " + state.me.name : "Conta: entrar ou criar conta");
  $("pf-guest").style.display = state.me ? "none" : "";
  $("pf-user").style.display = state.me ? "" : "none";
  show("pf-feed", !!state.me); show("pf-head", !state.me);
  pollAlerts();
  if (!state.me) return show("settings", false);
  if (currentPage === "profile") loadFeed();
  paintAvatar($("acct-initial"), state.me); paintAvatar($("pf-avatar"), state.me); paintAvatar($("set-avatar"), state.me);
  $("pf-name").textContent = state.me.name; $("pf-fullname").textContent = state.me.name; $("set-name").textContent = state.me.name; $("pf-email").textContent = state.me.email;
  $("pf-about").textContent = state.me.bio || "";
  var site = safeWebAddress(state.me.website);
  $("pf-site").style.display = site ? "inline-block" : "none";
  $("pf-site").textContent = site.replace(/^https?:\/\//i, "").replace(/\/$/, ""); $("pf-site").href = site || "#";
  $("pf-role").style.display = state.me.admin ? "inline-block" : "none";
  show("pf-verify", !!(status.mail && status.mail.enabled && !state.me.email_verified), "flex");
  $("pf-verify-email").textContent = state.me.email;
  $("set-2fa-state").textContent = state.me.two_factor ? "Ativa" : "Desativada";
  $("pf-passkey").style.display = passkeysSupported ? "" : "none";
  $("pf-review").style.display = state.me.moderator ? "" : "none";
  if (state.me.moderator) refreshReviewCount();
  $("pf-passkey-info").textContent = state.me.passkeys ? "Biometria ativa em " + state.me.passkeys + (state.me.passkeys > 1 ? " aparelhos." : " aparelho.") : "";
}

export async function loadMe() {
  try { var r = await api("/api/v1/session"); state.me = r.ok ? r.data.user : null; } catch (e) { state.me = null; }
  applyAuth();
}

export function authError(msg) { $("au-error").textContent = msg || ""; }

var otpAsked = false;

function authInfo(msg) { $("au-info").textContent = msg || ""; }

function setAuthMode(mode) {
  authMode = mode;
  var tabs = mode === "in" || mode === "up", titles = { in: "Entrar", up: "Criar conta", forgot: "Recuperar senha", reset: "Nova senha" };
  show("au-tabs", tabs, "flex");
  $("au-tab-in").classList.toggle("on", mode === "in"); $("au-tab-up").classList.toggle("on", mode === "up");
  $("au-tab-in").setAttribute("aria-selected", mode === "in"); $("au-tab-up").setAttribute("aria-selected", mode === "up");
  show("au-name-row", mode === "up");
  show("au-email-row", mode !== "reset");
  show("au-pass-row", mode !== "forgot");
  $("au-pass-label").textContent = mode === "reset" ? "Nova senha (mínimo 8 caracteres)" : "Senha";
  show("au-otp-row", mode === "in" && otpAsked);
  show("au-forgot", mode === "in", "block");
  show("au-tologin", mode === "forgot" || mode === "reset", "block");
  $("au-submit").textContent = { in: "Entrar", up: "Criar conta", forgot: "Enviar link por e-mail", reset: "Salvar nova senha" }[mode];
  $("au-title").textContent = titles[mode];
  $("au-pass").setAttribute("autocomplete", mode === "in" ? "current-password" : "new-password");
  show("au-terms-row", mode === "up", "flex");
  show("au-passkey", mode === "in" && passkeysSupported, "block");
  show("au-alt", tabs);
  authError(""); authInfo("");
}

export function openAuth(why, mode) {
  setAuthMode(mode || "in");
  $("au-why").textContent = why || "";
  show("auth", true, "flex");
  setupGoogle();
}

function closeAuth() { show("auth", false); $("au-pass").value = ""; $("au-otp").value = ""; otpAsked = false; authError(""); authInfo(""); }

export function signedIn(user) {
  state.me = user; applyAuth(); closeAuth();
  toast("Olá, " + firstName(user) + "!");
}

function failure(r, fallback) {
  if (r.data && r.data.error === "terms_required") return "É preciso aceitar os Termos de Uso e a Política de Privacidade.";
  if (r.status === 429) return "Muitas tentativas. Tente de novo em alguns minutos.";
  if (r.status === 401 && r.data.error === "invalid_credentials") return "E-mail ou senha incorretos.";
  if (r.status === 401 && r.data.error === "invalid_otp") return "Código incorreto ou já usado. Tente o próximo código do app.";
  if (r.data && r.data.error === "invalid_token") return "Este link expirou ou já foi usado. Peça um novo em “Esqueci minha senha”.";
  var errs = r.data.errors || {};
  if (errs.email) return "Esse e-mail é inválido ou já tem conta. Tente entrar.";
  if (errs.password) return "A senha precisa ter pelo menos 8 caracteres.";
  if (r.status === 400) return "Preencha e-mail e senha.";
  return fallback;
}

// Google: the "Sign in with Google" button gives us an ID token; the server checks it with Google.
function setupGoogle() {
  var clientId = status.auth && status.auth.google_client_id;
  if (!clientId || googleLoaded) return;
  googleLoaded = true;
  var s = document.createElement("script");
  s.src = "https://accounts.google.com/gsi/client"; s.async = true;
  s.onload = function () {
    google.accounts.id.initialize({ client_id: clientId, callback: async function (resp) {
      var r = await api("/api/v1/session/google", "POST", { credential: resp.credential, accepted_terms: authMode === "up" && $("au-terms").checked });
      if (r.ok) signedIn(r.data.user);
      else if (r.data && r.data.error === "terms_required") {
        setAuthMode("up");
        authError("Esta conta Google ainda não existe aqui. Marque que aceita os Termos e a Política de Privacidade e toque no botão do Google de novo.");
      } else authError("Não foi possível entrar com o Google.");
    } });
    google.accounts.id.renderButton($("au-google"), { theme: "outline", size: "large", shape: "pill", text: "continue_with", locale: "pt-BR", width: 280 });
  };
  s.onerror = function () { googleLoaded = false; };
  document.head.appendChild(s);
}

export function boot() {
  $("au-form").onsubmit = async function (e) {
    e.preventDefault();
    var email = $("au-email").value.trim(), pass = $("au-pass").value;
    if (authMode === "forgot") {
      if (!email) return authError("Digite seu e-mail.");
      authError(""); $("au-submit").disabled = true;
      var f = await api("/api/v1/password/forgot", "POST", { email: email }).catch(function () { return null; });
      $("au-submit").disabled = false;
      if (!f || !(f.ok || f.status === 204)) return authError(f && f.status === 429 ? "Muitas tentativas. Tente de novo mais tarde." : "Sem conexão. Tente de novo.");
      return authInfo(status.mail && status.mail.enabled ? "Se existir uma conta com esse e-mail, enviamos um link para criar uma nova senha. Olhe também o spam." : "O envio de e-mails não está ativo neste servidor.");
    }
    if (authMode === "reset") {
      if (pass.length < 8) return authError("A senha precisa ter pelo menos 8 caracteres.");
      authError(""); $("au-submit").disabled = true;
      var rr = await api("/api/v1/password/reset", "POST", { token: state.resetToken, password: pass }).catch(function () { return null; });
      $("au-submit").disabled = false;
      if (!rr) return authError("Sem conexão. Tente de novo.");
      if (!(rr.ok || rr.status === 204)) return authError(failure(rr, "Não foi possível salvar agora."));
      state.resetToken = null; $("au-pass").value = ""; setAuthMode("in"); return authInfo("Senha alterada! Entre com a nova senha.");
    }
    if (!email || !pass) return authError("Preencha e-mail e senha.");
    if (authMode === "up" && pass.length < 8) return authError("A senha precisa ter pelo menos 8 caracteres.");
    if (authMode === "up" && !$("au-terms").checked) return authError("Para criar a conta, marque que leu e aceita os Termos de Uso e a Política de Privacidade.");
    authError(""); $("au-submit").disabled = true;
    try {
      var body = authMode === "in" ? { email: email, password: pass } : null;
      if (authMode === "in" && otpAsked) body.otp = $("au-otp").value.trim();
      var r = authMode === "up"
        ? await api("/api/v1/users", "POST", { name: $("au-name").value.trim(), email: email, password: pass, accepted_terms: true })
        : await api("/api/v1/session", "POST", body);
      if (r.ok) { otpAsked = false; $("au-otp").value = ""; signedIn(r.data.user); }
      else if (r.status === 401 && r.data.error === "otp_required") {
        otpAsked = true; show("au-otp-row", true); $("au-otp").focus();
        authError("Digite o código de 6 dígitos do seu app autenticador (ou um código de recuperação).");
      } else authError(failure(r, "Não foi possível entrar agora."));
    } catch (err) { authError("Sem conexão. Tente de novo."); }
    $("au-submit").disabled = false;
  };

  $("au-forgot").onclick = function () { var keep = $("au-email").value; setAuthMode("forgot"); $("au-email").value = keep; };

  $("au-tologin").onclick = function () { setAuthMode("in"); };

  $("au-tab-in").onclick = function () { setAuthMode("in"); };

  $("au-tab-up").onclick = function () { setAuthMode("up"); };

  $("au-back").onclick = closeAuth;

  $("acct").onclick = function () { if (state.me) goPage("profile"); else openAuth(); };

  $("pf-login").onclick = function () { openAuth("Entre para reportar lixo no mapa."); };

  $("pf-logout").onclick = async function () {
    try { await api("/api/v1/session", "DELETE"); } catch (e) {}
    state.me = null; saveToken(""); applyAuth();
    if (state.reporting) closeReport();
    goPage("map"); toast("Você saiu.");
  };
}
