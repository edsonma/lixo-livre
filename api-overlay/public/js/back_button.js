// The phone's back button closes the open screen instead of leaving the app.

import { state } from "./state.js";
import { currentPage, goPage } from "./navigation.js";

export function boot() {
  // The browser's back gesture (edge swipe on the phone) must not leave the app: it closes the open screen,
  // or brings the person back to the map, and only then stays put.
  try { history.replaceState({ lixo: 1 }, ""); history.pushState({ lixo: 2 }, ""); } catch (e) {}

  window.addEventListener("popstate", function () {
    try { history.pushState({ lixo: 2 }, ""); } catch (e) {}
    var open = state.reporting || Array.prototype.some.call(document.querySelectorAll(".screen"), function (n) { return n.style.display === "flex"; });
    if (open) document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    else if (currentPage !== "map") goPage("map");
  });
}
