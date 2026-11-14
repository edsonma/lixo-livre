// Report a photo: the shared state and small helpers of the flow.

import { state } from "./state.js";
import { $ } from "./dom.js";
import { map } from "./map.js";

export function showError(msg) { $("error").textContent = msg || ""; }

export function placeError(msg) { $("place-error").textContent = msg || ""; }

export function camMessage(msg) { $("cam-error").textContent = msg || ""; }

export function sheetPadding() { return Math.min(340, Math.round(window.innerHeight * 0.42)); }

export function showCoords() {
  var c = map.getCenter();
  $("coords").textContent = c.lat.toFixed(5) + ", " + c.lng.toFixed(5);
}

export function dropMarker() {
  if (state.marker) { state.marker.remove(); state.marker = null; }
}

export function boot() {
  map.on("move", function () { if (state.step === "place") showCoords(); });
}
