// Camera: live preview with getUserMedia (the phone's own camera app is the fallback).

import { state } from "./state.js";
import { $, show } from "./dom.js";
import { camMessage } from "./report.js";

export function stopCamera() {
  state.camRun++;
  if (state.stream) { state.stream.getTracks().forEach(function (t) { t.stop(); }); state.stream = null; }
  $("video").srcObject = null;
  state.liveCamera = false;
}

function showFallback(text) {
  stopCamera();
  show("video", false); show("cam-fallback", true, "flex"); $("cam-fallback").textContent = text;
  $("flip").style.visibility = "hidden";
}

export async function startCamera() {
  stopCamera();
  var run = state.camRun;
  camMessage("");
  show("shot", false); show("video", true); show("cam-fallback", false);
  $("flip").style.visibility = "hidden";
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    return showFallback("Toque no botão verde para abrir a câmera do celular.");
  }
  try {
    var s = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: state.facing }, width: { ideal: 1920 }, height: { ideal: 1440 } }, audio: false
    });
    if (run !== state.camRun) { s.getTracks().forEach(function (t) { t.stop(); }); return; } // the person moved on while the permission prompt was open
    state.stream = s; state.liveCamera = true;
    $("video").srcObject = s;
    $("flip").style.visibility = "visible";
    try { await $("video").play(); } catch (e) {}
  } catch (e) {
    if (run !== state.camRun) return;
    showFallback("Sem acesso à câmera. Toque no botão verde para usar a câmera do celular, ou escolha uma foto da galeria.");
  }
}

export function captureFrame() {
  var v = $("video");
  if (!v.videoWidth) return camMessage("A câmera ainda está iniciando. Tente de novo.");
  $("shutter").disabled = true; // feedback right away, and no double tap while the photo is encoded
  var scale = Math.min(1, 2000 / Math.max(v.videoWidth, v.videoHeight));
  var canvas = document.createElement("canvas");
  canvas.width = Math.round(v.videoWidth * scale); canvas.height = Math.round(v.videoHeight * scale);
  canvas.getContext("2d").drawImage(v, 0, 0, canvas.width, canvas.height);
  canvas.toBlob(function (blob) {
    if (!blob) { $("shutter").disabled = false; return camMessage("Não foi possível capturar a foto. Tente de novo."); }
    setChosen(new File([blob], "foto.jpg", { type: "image/jpeg", lastModified: Date.now() }));
  }, "image/jpeg", 0.9);
}

// The camera screen has two states: taking a photo (shutter, tabs) and reviewing it (retake, send).
export function showCaptureState() {
  show("shot", false); show("cam-caption", true);
  show("cam-controls", true, "flex"); show("cam-tabs", true, "flex"); show("cam-review", false);
  $("send").disabled = true; $("shutter").disabled = false;
}

export function showReviewState() {
  if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
  state.previewUrl = URL.createObjectURL(state.chosen);
  $("shot").src = state.previewUrl;
  show("video", false); show("cam-fallback", false); show("shot", true); show("cam-caption", false);
  show("cam-controls", false); show("cam-tabs", false); show("cam-review", true, "flex");
  $("send").disabled = false;
  camMessage("");
}

export function setChosen(file) {
  stopCamera();
  state.chosen = file;
  showReviewState();
}
