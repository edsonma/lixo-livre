// Address search (OpenStreetMap Nominatim).

import { $, el } from "./dom.js";
import { map } from "./map.js";

var searching = false;

function hideResults() { $("results").style.display = "none"; $("results").replaceChildren(); }

function showResults(items, message) {
  var ul = $("results"); ul.replaceChildren();
  if (message) { var li = el("li", message, "empty"); ul.appendChild(li); }
  items.forEach(function (r) {
    var li = el("li", r.display_name);
    li.onclick = function () {
      hideResults(); $("search").value = r.display_name.split(",").slice(0, 2).join(",");
      var box = r.boundingbox; // south, north, west, east
      if (box) map.fitBounds([[+box[2], +box[0]], [+box[3], +box[1]]], { maxZoom: 17, padding: 40 });
      else map.flyTo({ center: [+r.lon, +r.lat], zoom: 16 });
    };
    ul.appendChild(li);
  });
  ul.style.display = "block";
}

export function boot() {
  $("search-form").onsubmit = async function (e) {
    e.preventDefault();
    var q = $("search").value.trim();
    if (!q || searching) return;
    searching = true;
    try {
      var url = "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=5&countrycodes=br&q=" + encodeURIComponent(q);
      var res = await fetch(url, { headers: { "Accept-Language": "pt-BR" } });
      if (!res.ok) throw new Error("search failed");
      var found = await res.json();
      showResults(found, found.length ? "" : "Não encontramos esse endereço. Tente outro nome.");
    } catch (err) {
      showResults([], "A busca não respondeu. Tente de novo em instantes.");
    }
    searching = false;
  };

  $("search").oninput = function () { $("search-clear").style.display = this.value ? "block" : "none"; if (!this.value) hideResults(); };

  $("search-clear").onclick = function () { $("search").value = ""; $("search-clear").style.display = "none"; hideResults(); $("search").focus(); };
}
