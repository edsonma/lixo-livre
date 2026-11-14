// Map filters: period and type (the server re-scores the cells from the matching reports).

import { state } from "./state.js";
import { TYPE_INFO } from "./analysis_types.js";
import { $, el } from "./dom.js";
import { loadHeat } from "./map.js";

var TREND_TEXT = { worse: "↗ piorando", better: "↘ melhorando", stable: "→ estável" };

export function trendBadge(t) {
  if (!t) return null;
  var b = el("span", TREND_TEXT[t.label] || "", "trend " + t.label);
  b.title = (t.delta > 0 ? "+" : "") + t.delta + " pontos em 14 dias";
  return b;
}

export function boot() {
  (function () {
    var sel = $("type-filter");
    Object.keys(TYPE_INFO).forEach(function (k) {
      var o = document.createElement("option"); o.value = k; o.textContent = TYPE_INFO[k][0] + " " + TYPE_INFO[k][1]; sel.appendChild(o);
    });
    sel.onchange = function () { state.typeKey = this.value; sel.classList.toggle("on", !!state.typeKey); loadHeat(); };
    document.querySelectorAll("#chips2 .chip").forEach(function (chip) {
      chip.onclick = function () {
        state.periodDays = chip.dataset.days;
        document.querySelectorAll("#chips2 .chip").forEach(function (c) { c.setAttribute("aria-pressed", c === chip ? "true" : "false"); });
        loadHeat();
      };
    });
  })();
}
