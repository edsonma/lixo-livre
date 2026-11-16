// Tap a photo to see all of it: the small picture crops it to a strip, this shows it whole on a dark screen.
// Tap anywhere, press the X or Escape to close. Works for every photo marked class "an-photo".

import { $, show } from "./dom.js";

export function closeViewer() { show("viewer", false); $("vw-img").removeAttribute("src"); }

export function boot() {
  document.addEventListener("click", function (e) {
    var img = e.target.closest && e.target.closest("img.an-photo");
    if (!img || !img.getAttribute("src")) return;
    $("vw-img").src = img.getAttribute("src");
    $("vw-img").alt = img.alt || "";
    show("viewer", true, "flex");
  });
  $("viewer").onclick = closeViewer; // anywhere, the picture included
}
