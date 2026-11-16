// The report steps: place -> photo -> upload -> poll until the AI has scored it.

import { state } from "./state.js";
import { showAnalysis } from "./analysis.js";
import { deviceToken, saveToken } from "./api.js";
import { applyAuth, openAuth } from "./auth.js";
import { captureFrame, setChosen, showCaptureState, showReviewState, startCamera, stopCamera } from "./camera.js";
import { status } from "./core.js";
import { $, chrome, el, show, toast } from "./dom.js";
import { loadHeat, loadHeatSoon, map } from "./map.js";
import { goPage } from "./navigation.js";
import { closePlace } from "./place.js";
import { camMessage, dropMarker, placeError, sheetPadding, showCoords, showError } from "./report.js";
import { askConsent } from "./terms.js";

// Step 1: the pin stays in the middle of the screen, the map moves under it.
function goToPlace() {
  state.step = "place";
  dropMarker(); stopCamera(); state.draft = null;
  show("analysis", false); show("camera", false); show("report", false); show("place", true); show("pin", true); chrome(false);
  placeError(""); showCoords();
  map.easeTo({ padding: { bottom: 0 }, center: state.placed || map.getCenter(), zoom: Math.max(map.getZoom(), 16), duration: 300 });
}

// Step 2: the place is fixed on a marker; a full camera screen opens on top.
function goToPhoto() {
  state.step = "photo";
  state.placed = map.getCenter();
  var pin = document.createElement("div");
  pin.className = "placed-pin"; pin.textContent = "📍";
  state.marker = new maplibregl.Marker({ element: pin, anchor: "bottom" }).setLngLat(state.placed).addTo(map);
  show("pin", false); show("place", false); show("report", false);
  show("camera", true, "flex");
  if (state.chosen) showReviewState();
  else { showCaptureState(); startCamera(); }
}

// Step 3: the camera screen closes and the sheet shows the progress and the score.
function goToProgress() {
  state.step = "progress";
  stopCamera(); show("camera", false);
  show("progress", true); show("report", true);
  map.easeTo({ center: state.placed, padding: { bottom: sheetPadding() }, duration: 300 });
}

var reportKind = "dirty";

export function openReport(kind, at) {
  if (!state.me) return openAuth("Entre para reportar lixo no mapa.");
  if (!state.me.terms_ok) return askConsent(function () { openReport(kind, at); });
  if (status.mail && status.mail.enabled && !state.me.email_verified) { goPage("profile"); return toast("Confirme seu e-mail para reportar. Veja o aviso no perfil."); }
  resetReport();
  reportKind = kind === "cleanup" ? "cleanup" : "dirty";
  state.reporting = true; state.placed = null;
  goPage("map", true); map.resize(); // started from Perfil/Explorar: the map page must be on screen
  if (at) map.jumpTo({ center: at, zoom: 17 });
  goToPlace();
}

export function closeReport() {
  state.polling++; clearTimeout(state.pollTimer);
  state.reporting = false; state.step = null; dropMarker(); stopCamera();
  show("analysis", false); show("camera", false); show("place", false); show("report", false); show("pin", false); chrome(true);
  map.easeTo({ padding: { bottom: 0 }, duration: 200 });
}

function resetReport() {
  state.polling++; clearTimeout(state.pollTimer);
  stopCamera(); state.draft = null; show("analysis", false);
  $("photo").value = ""; $("photo-camera").value = ""; state.chosen = null;
  show("progress", false);
  $("again").style.display = "none"; $("done").style.display = "none";
  showError(""); camMessage("");
  showCaptureState();
  if (state.previewUrl) { URL.revokeObjectURL(state.previewUrl); state.previewUrl = null; }
}

export function setStatus(spinning, text, severity) {
  var box = $("status");
  box.replaceChildren();
  if (spinning) box.appendChild(el("span", null, "spinner"));
  if (severity != null) {
    var score = el("div", String(severity), "score");
    score.appendChild(el("small", "/100"));
    score.setAttribute("aria-label", severity + " de 100");
    box.appendChild(score);
    var meter = el("div", null, "meter"), fill = document.createElement("div");
    fill.style.width = severity + "%";
    fill.style.background = "hsl(" + Math.round(120 * (1 - severity / 100)) + ", 70%, 45%)";
    meter.appendChild(fill);
    box.appendChild(meter);
  }
  box.appendChild(el("span", text));
}

function renderStage(r) {
  if (r.stage === "protecting_photo") return setStatus(true, "Protegendo sua privacidade…");
  if (r.stage === "analyzing") return setStatus(true, "Analisando…");
  if (r.stage === "scored") return showAnalysis(r);
  if (r.stage === "published") {
    loadHeatSoon();
    return showAnalysis(r);
  }
  if (r.stage === "still_dirty") return setStatus(false, "A foto ainda mostra lixo, então o local continua sujo no mapa. Tire uma foto do local já limpo.");
  if (r.stage === "nothing_to_clean") return setStatus(false, "Não há registros de lixo recentes neste local para marcar como limpo.");
  if (r.stage === "not_trash") return setStatus(false, "A IA não encontrou lixo nessa foto. Tente outra mais de perto.");
  return setStatus(false, "Sua foto ficou em revisão. Ela aparece no mapa depois de aprovada.");
}

async function poll(id, token, run, tries) {
  if (run !== state.polling) return; // cancelled or replaced
  var r = null;
  try {
    var res = await fetch("/api/v1/me/trashes/" + id, { headers: { "X-Device-Token": token } });
    if (res.ok) r = await res.json();
  } catch (e) {}
  if (run !== state.polling) return;
  if (r) {
    renderStage(r);
    if (r.done) { $("again").style.display = "inline-block"; $("done").style.display = "inline-block"; return; }
  }
  if (tries >= 40) {
    setStatus(false, "Ainda processando. Volte em instantes: sua foto já foi enviada.");
    $("again").style.display = "inline-block"; $("done").style.display = "inline-block";
    return;
  }
  state.pollTimer = setTimeout(function () { poll(id, token, run, tries + 1); }, 1500);
}

export function boot() {
  $("report-btn").onclick = function () { openReport(); };

  $("place-ok").onclick = goToPhoto;

  $("place-cancel").onclick = closeReport;

  $("cam-back").onclick = goToPlace;

  $("again").onclick = function () { openReport(); };

  $("done").onclick = function () { closeReport(); loadHeat(); };

  $("shutter").onclick = function () {
    if (state.liveCamera) captureFrame(); else $("photo-camera").click(); // no live preview: use the phone's camera app
  };

  $("flip").onclick = function () { state.facing = state.facing === "environment" ? "user" : "environment"; startCamera(); };

  $("gallery-btn").onclick = $("tab-gallery").onclick = function () { $("photo").click(); };

  $("tab-camera").onclick = function () { if (!state.liveCamera && !state.chosen) startCamera(); };

  $("retake").onclick = function () {
    $("photo").value = ""; $("photo-camera").value = ""; state.chosen = null;
    showCaptureState(); startCamera();
  };

  // Photos from the gallery or from the phone's camera app keep their own EXIF (GPS, camera); frames captured by the live preview have none.
  $("photo").onchange = $("photo-camera").onchange = function () {
    var file = this.files[0];
    if (!file) return; // picker cancelled: keep what we had
    setChosen(file);
  };

  $("locate").onclick = function () {
    placeError("");
    if (!navigator.geolocation) return placeError("Seu navegador não oferece localização. Mova o mapa até o local.");
    $("locate").disabled = true;
    navigator.geolocation.getCurrentPosition(function (pos) {
      $("locate").disabled = false;
      map.flyTo({ center: [pos.coords.longitude, pos.coords.latitude], zoom: 17 });
    }, function () {
      $("locate").disabled = false;
      placeError("Não foi possível obter sua localização. Mova o mapa até o local.");
    }, { enableHighAccuracy: true, timeout: 10000 });
  };

  // While choosing the place, a tap on the map moves the pin there instead of opening the info panel.
  map.on("click", function (e) { if (state.step === "place") map.easeTo({ center: e.lngLat }); });

  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape") return;
    if ($("viewer").style.display === "flex") show("viewer", false); else if (state.reporting) closeReport(); else if ($("editprofile").style.display === "flex") show("editprofile", false); else if ($("twofa").style.display === "flex") show("twofa", false); else if ($("legal").style.display === "flex") show("legal", false); else if ($("settings").style.display === "flex") show("settings", false); else if ($("alerts").style.display === "flex") show("alerts", false); else if ($("myphoto").style.display === "flex") show("myphoto", false); else if ($("review").style.display === "flex") show("review", false); else if ($("detail").style.display === "flex") closePlace();
  });

  // Never keep the camera on in the background; bring it back when the person returns to the photo step.
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) { if (state.liveCamera) stopCamera(); }
    else if (state.step === "photo" && !state.chosen) startCamera();
  });

  window.addEventListener("pagehide", stopCamera);

  $("send").onclick = async function () {
    var file = state.chosen;
    if (!file) return;
    camMessage(""); $("send").disabled = true;
    try {
      var token = await deviceToken();
      var c = state.placed || map.getCenter();
      var form = new FormData();
      form.append("photo", file);
      form.append("lat", c.lat); form.append("lng", c.lng);
      form.append("kind", reportKind);
      // A gallery photo was usually taken earlier: its file date is the best guess (the server also reads the EXIF).
      var taken = file.lastModified && file.lastModified > 946684800000 && file.lastModified <= Date.now() ? new Date(file.lastModified) : new Date();
      form.append("taken_at", taken.toISOString());
      var res = await fetch("/api/v1/trashes", { method: "POST", headers: { "X-Device-Token": token }, body: form });
      var body = await res.json().catch(function () { return {}; });
      if (res.status === 403 && body.error === "email_unverified") {
        state.me = Object.assign({}, state.me, { email_verified: false }); applyAuth(); closeReport(); goPage("profile");
        return toast("Confirme seu e-mail para reportar. Veja o aviso no perfil.");
      }
      if (res.status === 403 && body.error === "terms_required") {
        $("send").disabled = false; return askConsent(function () { $("send").click(); });
      }
      if (res.status === 401 && body.error === "login_required") {
        state.me = null; applyAuth(); closeReport(); openAuth("Sua sessão expirou. Entre de novo para enviar a foto.");
        return;
      }
      if (res.status === 401) { saveToken(""); throw new Error("Sessão expirada. Tente enviar de novo."); }
      if (!res.ok) {
        var msgs = body.errors ? Object.keys(body.errors).map(function (k) { return k + " " + body.errors[k].join(", "); }).join("; ") : "Erro " + res.status;
        throw new Error(msgs);
      }
      goToProgress();
      setStatus(true, "Enviando…");
      var run = ++state.polling;
      poll(body.id, token, run, 0);
    } catch (e) {
      camMessage(e.message || "Falha no envio."); // the camera screen is still open
      $("send").disabled = false;
    }
  };
}
