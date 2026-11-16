// Edit profile: full name, picture, bio, website and gender. The email is the login, so it is shown but never sent.

import { state } from "./state.js";
import { apiForm } from "./api.js";
import { applyAuth } from "./auth.js";
import { paintAvatar } from "./avatar.js";
import { $, show, toast } from "./dom.js";

var MAX_PICTURE_BYTES = 8 * 1024 * 1024;
var pickedFile = null;   // a picture chosen but not saved yet
var removePicture = false;
var previewUrl = null;

var FIELD_LABEL = { name: "Nome", bio: "Bio", website: "Site", gender: "Gênero", avatar: "Foto" };
var MESSAGE = {
  name: "o nome não pode ficar vazio.",
  bio: "use no máximo 160 caracteres.",
  website: "digite um endereço válido, como seusite.com.br.",
  gender: "escolha uma das opções.",
  avatar: "não consegui usar esse arquivo. Escolha uma foto JPG, PNG ou WebP de até 8 MB."
};

function setError(msg) { $("ep-error").textContent = msg || ""; }

function updateCount() { $("ep-bio-count").textContent = $("ep-bio").value.length + "/160"; }

function paintPreview() {
  var node = $("ep-avatar");
  if (pickedFile) {
    node.textContent = "";
    var img = document.createElement("img"); img.src = previewUrl; img.alt = "";
    node.appendChild(img);
  } else {
    paintAvatar(node, removePicture ? { name: state.me.name, email: state.me.email } : state.me);
  }
  show("ep-remove", !!(pickedFile || (state.me.avatar_url && !removePicture)), "inline-block");
}

function forgetPreview() { if (previewUrl) URL.revokeObjectURL(previewUrl); previewUrl = null; pickedFile = null; removePicture = false; }

export function openEditProfile() {
  if (!state.me) return;
  forgetPreview();
  $("ep-name").value = state.me.name || "";
  $("ep-email").value = state.me.email || "";
  $("ep-bio").value = state.me.bio || "";
  $("ep-website").value = state.me.website || "";
  $("ep-gender").value = state.me.gender || "";
  $("ep-file").value = "";
  setError(""); updateCount(); paintPreview();
  show("settings", false);
  show("editprofile", true, "flex");
}

function closeEditProfile() { show("editprofile", false); forgetPreview(); }

function describeErrors(errors) {
  var fields = Object.keys(errors || {}).filter(function (f) { return FIELD_LABEL[f]; });
  if (!fields.length) return "Não foi possível salvar. Tente de novo.";
  return fields.map(function (f) { return FIELD_LABEL[f] + ": " + MESSAGE[f]; }).join(" ");
}

async function save(ev) {
  ev.preventDefault();
  setError("");
  if (!$("ep-name").value.trim()) return setError("Nome: " + MESSAGE.name);
  var form = new FormData();
  form.append("name", $("ep-name").value.trim());
  form.append("bio", $("ep-bio").value);
  form.append("website", $("ep-website").value);
  form.append("gender", $("ep-gender").value);
  if (pickedFile) form.append("avatar", pickedFile, pickedFile.name || "avatar");
  else if (removePicture) form.append("remove_avatar", "true");
  $("ep-save").disabled = true;
  var res;
  try { res = await apiForm("/api/v1/profile", "PATCH", form); }
  catch (e) { res = { ok: false, data: {} }; }
  $("ep-save").disabled = false;
  if (res.status === 429) return setError("Muitas tentativas. Aguarde alguns minutos.");
  if (res.status === 401) { setError("Sua sessão expirou. Entre de novo."); return; }
  if (!res.ok) return setError(describeErrors(res.data && res.data.errors));
  state.me = res.data.user;
  applyAuth();
  closeEditProfile();
  toast("Perfil atualizado");
}

export function boot() {
  $("pf-edit").onclick = $("set-edit").onclick = openEditProfile;
  $("ep-back").onclick = closeEditProfile;
  $("ep-bio").addEventListener("input", updateCount);
  $("ep-pick").onclick = function () { $("ep-file").click(); };
  $("ep-file").addEventListener("change", function () {
    var file = $("ep-file").files[0];
    if (!file) return;
    if (file.size > MAX_PICTURE_BYTES) { $("ep-file").value = ""; return setError("Foto: " + MESSAGE.avatar); }
    setError("");
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    pickedFile = file; removePicture = false; previewUrl = URL.createObjectURL(file);
    paintPreview();
  });
  $("ep-remove").onclick = function () {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    previewUrl = null; pickedFile = null; removePicture = true; $("ep-file").value = "";
    paintPreview();
  };
  $("ep-form").addEventListener("submit", save);
}
