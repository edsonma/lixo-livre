// The three pages (Explorar | Mapa | Perfil), the bottom tab bar and the notification bell.

import { state } from "./state.js";
import { openAuth } from "./auth.js";
import { $, show } from "./dom.js";
import { loadRankings } from "./explore.js";
import { loadFeed } from "./my_photos.js";
import { openAlerts } from "./notifications.js";

var PAGES = ["explore", "map", "profile"];

var pager;

export var currentPage = "map";

function syncPage() {
  var i = Math.max(0, Math.min(PAGES.length - 1, Math.round(pager.scrollLeft / Math.max(1, pager.clientWidth))));
  if (PAGES[i] === currentPage) return;
  currentPage = PAGES[i];
  document.body.dataset.page = currentPage;
  if (currentPage === "profile") loadFeed(true); // fresh grid every time the profile is opened, and the map goes to my latest published report
  if (currentPage === "explore") loadRankings();
  markNav();
}

// Notificações is a screen over the pages, so while it is open its tab is the lit one.
function markNav() {
  var alertsOpen = $("alerts").style.display === "flex";
  PAGES.concat("alerts").forEach(function (name) {
    var tab = $("nav-" + name), on = alertsOpen ? name === "alerts" : name === currentPage;
    tab.classList.toggle("on", on);
    if (on) tab.setAttribute("aria-current", "page"); else tab.removeAttribute("aria-current");
  });
}

export function goPage(name, instant) {
  pager.scrollTo({ left: PAGES.indexOf(name) * pager.clientWidth, behavior: instant ? "auto" : "smooth" });
}

export function boot() {
  ["nav-alerts", "bell"].forEach(function (id) {
    $(id).onclick = function () { if (!state.me) return openAuth("Entre para receber avisos dos locais que você segue."); openAlerts(); };
  });

  pager = $("pager");

  new MutationObserver(markNav).observe($("alerts"), { attributes: true, attributeFilter: ["style"] });

  pager.addEventListener("scroll", syncPage, { passive: true });

  window.addEventListener("resize", function () { goPage(currentPage, true); });

  $("nav-map").onclick = $("explore-map").onclick = function () { goPage("map"); };

  $("nav-explore").onclick = function () { goPage("explore"); };

  $("nav-profile").onclick = function () { goPage("profile"); };

  ["nav-map", "nav-explore", "nav-profile"].forEach(function (id) { $(id).addEventListener("click", function () { show("alerts", false); }); });
}
