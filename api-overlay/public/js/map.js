// The map, its heat layer and pins, the level chips, and loading the heat cells.

import { state } from "./state.js";
import { status } from "./core.js";
import { toast } from "./dom.js";
import { mineOnly, myCells } from "./my_photos.js";

export var map;

var geolocate;

var EMPTY = { type: "FeatureCollection", features: [] };

// Levels of a spot, from the decayed score of its cell. The chips filter on these.
var LEVELS = [
  { key: "limpo", label: "Limpo", max: 25, color: "#2e9e4f" },
  { key: "moderado", label: "Moderado", max: 50, color: "#f2a900" },
  { key: "sujo", label: "Sujo", max: 75, color: "#e8452c" },
  { key: "muito-sujo", label: "Muito sujo", max: Infinity, color: "#b3261e" }
];

export function levelOf(score) { return LEVELS.find(function (l) { return score < l.max; }); }

// Round pin with a trash can, one image per level, drawn here so there is nothing to download.
function pinImage(color) {
  var size = 72, c = document.createElement("canvas"); c.width = c.height = size;
  var g = c.getContext("2d");
  g.beginPath(); g.arc(36, 36, 30, 0, Math.PI * 2);
  g.fillStyle = color; g.fill(); g.lineWidth = 5; g.strokeStyle = "#fff"; g.stroke();
  g.fillStyle = "#fff";
  g.fillRect(23, 24, 26, 4);                       // lid
  g.fillRect(32, 20, 8, 5);                        // handle
  g.beginPath(); g.moveTo(25, 31); g.lineTo(47, 31); g.lineTo(44.5, 51); g.lineTo(27.5, 51); g.closePath(); g.fill(); // body
  g.fillStyle = color;
  [31, 36, 41].forEach(function (x) { g.fillRect(x - 0.9, 34, 1.8, 14); });                                          // slats
  return g.getImageData(0, 0, size, size);
}

var filterKey = "todos";
var PHOTO_ZOOM = 14; // from here on every photo gets its own small pin (the hexagon pin is shown below this zoom)

export function applyFilter() {
  if (!map.getLayer("heat")) return;
  var parts = [];
  if (filterKey !== "todos") parts.push(["==", ["get", "level"], filterKey]);
  if (typeof mineOnly !== "undefined" && mineOnly) parts.push(["in", ["get", "h3"], ["literal", myCells().concat(["-"])]]);
  var expr = parts.length ? ["all"].concat(parts) : null;
  map.setFilter("heat", expr); map.setFilter("pins", expr); map.setFilter("photo-pins", expr);
}

// A new report is scored in the background: look again a few times so the pin appears without a manual refresh.
export function loadHeatSoon() { [800, 2500, 6000, 12000, 25000].forEach(function (ms) { setTimeout(loadHeat, ms); }); }

export async function loadHeat() {
  var b = map.getBounds();
  var bbox = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()].join(",");
  try {
    var extra = (state.periodDays ? "&days=" + state.periodDays : "") + (state.typeKey ? "&type=" + encodeURIComponent(state.typeKey) : "");
    var data = await (await fetch("/api/v1/heatmap?bbox=" + bbox + extra)).json();
    data.features.forEach(function (f) { f.properties.level = levelOf(f.properties.score).key; });
    map.getSource("heat").setData(data);
    loadPhotos(data, extra);
  } catch (e) {}
}

// Zoomed in close: a small pin for each photo, at the exact spot, so a new photo in a place that already has a
// pin is still seen. Only photos of cells that are drawn (the same rules and filters as the hexagon pins).
async function loadPhotos(heat, extra) {
  var source = map.getSource("photos");
  if (!source) return;
  if (map.getZoom() < PHOTO_ZOOM) { source.setData(EMPTY); return; }
  var b = map.getBounds();
  var bbox = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()].join(",");
  try {
    var data = await (await fetch("/api/v1/heatmap/reports?bbox=" + bbox + extra)).json();
    var drawn = {}; heat.features.forEach(function (f) { drawn[f.properties.h3] = true; });
    data.features = data.features.filter(function (f) { return drawn[f.properties.h3]; });
    data.features.forEach(function (f) { f.properties.level = f.properties.kind === "cleanup" ? "limpo" : levelOf(f.properties.severity).key; });
    source.setData(data);
  } catch (e) {}
}

export function boot() {
  map = new maplibregl.Map({
    container: "map",
    center: [status.center.lng, status.center.lat],
    zoom: 12,
    style: {
      version: 8,
      sources: { osm: { type: "raster", tileSize: 256, attribution: "© OpenStreetMap contributors",
        tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"] } },
      layers: [{ id: "osm", type: "raster", source: "osm" }]
    }
  });

  map.addControl(new maplibregl.NavigationControl(), "bottom-right");

  // "Go to my location": centers the map on the GPS position, shows a blue dot and follows while the person moves.
  geolocate = new maplibregl.GeolocateControl({
    positionOptions: { enableHighAccuracy: true, timeout: 10000 },
    trackUserLocation: true, showAccuracyCircle: true, fitBoundsOptions: { maxZoom: 16 }
  });

  map.addControl(geolocate, "bottom-right");

  // The app asks for the position by itself when it opens, so the map starts where the person is. If that
  // automatic attempt fails (permission refused, no signal) it stays quiet: the message is for taps on the button.
  var automatic = true;
  geolocate.on("geolocate", function () { automatic = false; });
  geolocate.on("error", function () {
    if (automatic) { automatic = false; return; }
    toast("Não foi possível obter sua localização. Verifique a permissão de GPS.");
  });
  map.once("load", function () { geolocate.trigger(); });

  window.__lixo = { map: map }; // a handle for the browser tests

  map.on("load", function () {
    LEVELS.forEach(function (l) { map.addImage("pin-" + l.key, pinImage(l.color), { pixelRatio: 2 }); });
    map.addSource("heat", { type: "geojson", data: EMPTY });
    map.addLayer({
      id: "heat", type: "heatmap", source: "heat",
      paint: {
        "heatmap-weight": ["interpolate", ["linear"], ["get", "score"], 0, 0, 100, 1],
        "heatmap-radius": ["interpolate", ["linear"], ["zoom"], 8, 15, 14, 45],
        "heatmap-opacity": 0.8,
        "heatmap-color": ["interpolate", ["linear"], ["heatmap-density"],
          0, "rgba(46,158,79,0)", 0.2, "#2e9e4f", 0.5, "#f2d43d", 1, "#d92b2b"]
      }
    });
    map.addLayer({
      id: "pins", type: "symbol", source: "heat", minzoom: 11, maxzoom: PHOTO_ZOOM,
      layout: {
        "icon-image": ["concat", "pin-", ["get", "level"]], "icon-allow-overlap": true,
        "icon-size": ["interpolate", ["linear"], ["zoom"], 11, 0.5, 16, 0.85]
      }
    });
    map.addSource("photos", { type: "geojson", data: EMPTY });
    map.addLayer({
      id: "photo-pins", type: "circle", source: "photos", minzoom: PHOTO_ZOOM,
      paint: {
        "circle-radius": ["interpolate", ["linear"], ["zoom"], 16, 7, 19, 10],
        "circle-color": ["match", ["get", "level"], "limpo", "#2e9e4f", "moderado", "#f2a900", "sujo", "#e8452c", "#b3261e"],
        "circle-stroke-width": 2.5, "circle-stroke-color": "#fff"
      }
    });
    map.on("mouseenter", "pins", function () { map.getCanvas().style.cursor = "pointer"; });
    map.on("mouseleave", "pins", function () { map.getCanvas().style.cursor = ""; });
    map.on("moveend", loadHeat);
    applyFilter();
    loadHeat();
  });

  document.querySelectorAll("#chips .chip").forEach(function (chip) {
    chip.onclick = function () {
      filterKey = chip.dataset.level;
      document.querySelectorAll("#chips .chip").forEach(function (c) { c.setAttribute("aria-pressed", c === chip ? "true" : "false"); });
      applyFilter();
    };
  });
}
