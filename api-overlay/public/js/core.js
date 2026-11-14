// Start-up: the first page, the server status and the demo badge.

import { $ } from "./dom.js";

export var status = { center: { lat: -15.7942, lng: -47.8825 }, demo_mode: false };

export async function boot() {
  $("pager").scrollLeft = $("pager").clientWidth; // the pages are Explorar | Mapa | Perfil: start on the map

  document.body.dataset.page = "map";

  try { status = await (await fetch("/api/v1/status")).json(); } catch (e) {}

  document.getElementById("demo").style.display = status.demo_mode ? "inline-block" : "none";
}
