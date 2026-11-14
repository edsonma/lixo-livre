// Profile header buttons and the settings screen (the menu).

import { $, show } from "./dom.js";
import { openAlerts } from "./notifications.js";
import { openReport } from "./report_flow.js";

export function boot() {
  $("pf-menu").onclick = function () { show("settings", true, "flex"); };

  $("set-back").onclick = function () { show("settings", false); };

  $("pf-add").onclick = $("pf-report").onclick = function () { openReport(); };

  $("set-alerts").onclick = function () { openAlerts(); };

  $("pf-logout").addEventListener("click", function () { show("settings", false); });
}
