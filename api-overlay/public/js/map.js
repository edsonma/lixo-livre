// The map, its heat layer and pins, the level chips, and loading the heat cells.

import { state } from "./state.js";
import { status } from "./core.js";
import { toast } from "./dom.js";
import { mineOnly, myCells } from "./my_photos.js";

export var map;

var geolocate;

var EMPTY = { type: "FeatureCollection", features: [] };

// Levels of a spot, from the decayed score of its cell. The chips filter on these. Colours are the brand guide's
// severity tokens (also in app.css). `ink` is a darker shade for text on white; `on` is the text colour on the fill.
var LEVELS = [
  { key: "limpo", label: "Limpo", max: 20, color: "#4CAF50", ink: "#1B5E20", on: "#fff" },
  { key: "moderado", label: "Moderado", max: 40, color: "#FFC107", ink: "#7A5A00", on: "#1F2937" },
  { key: "sujo", label: "Sujo", max: 60, color: "#FF9800", ink: "#A34E00", on: "#1F2937" },
  { key: "muito-sujo", label: "Muito sujo", max: 80, color: "#F44336", ink: "#C62828", on: "#fff" },
  { key: "critico", label: "Crítico", max: Infinity, color: "#B71C1C", ink: "#B71C1C", on: "#fff" }
];

// Puts a level's colours on an element as CSS variables (--lvl fill, --lvl-ink text, --lvl-on text on the fill).
export function paintLevel(element, level) {
  element.style.setProperty("--lvl", level ? level.color : "#9AA3AE");
  element.style.setProperty("--lvl-ink", level ? level.ink : "#6B7280");
  element.style.setProperty("--lvl-on", level ? level.on : "#fff");
}

export function levelOf(score) { return LEVELS.find(function (l) { return score < l.max; }); }

// The brand pin (a drop with a trash can in a white circle), one image per level, drawn here so there is
// nothing to download. Its tip is the bottom of the image: the layers anchor it there.
function pinImage(color) {
  var w = 72, h = 92, c = document.createElement("canvas"); c.width = w; c.height = h;
  var g = c.getContext("2d");
  g.shadowColor = "rgba(31,41,55,.35)"; g.shadowBlur = 4; g.shadowOffsetY = 2;
  g.beginPath(); g.arc(36, 34, 30, Math.PI * 0.80, Math.PI * 0.20); g.lineTo(36, 88); g.closePath();
  g.fillStyle = color; g.fill();
  g.shadowColor = "transparent"; g.lineWidth = 3; g.strokeStyle = "#fff"; g.stroke();
  g.beginPath(); g.arc(36, 34, 19, 0, Math.PI * 2); g.fillStyle = "#fff"; g.fill();
  g.fillStyle = color;
  g.fillRect(25, 23, 22, 3.5);                     // lid
  g.fillRect(32, 19.5, 8, 4);                      // handle
  g.beginPath(); g.moveTo(27, 28.5); g.lineTo(45, 28.5); g.lineTo(43, 46); g.lineTo(29, 46); g.closePath(); g.fill(); // body
  g.fillStyle = "#fff";
  [32, 36, 40].forEach(function (x) { g.fillRect(x - 0.8, 31.5, 1.6, 11.5); });                                    // slats
  return g.getImageData(0, 0, w, h);
}

var filterKey = "todos";
var PHOTO_ZOOM = 14; // from here on every photo gets its own small pin (the hexagon pin is shown below this zoom)

export function applyFilter() {
  if (!map.getLayer("heat")) return;
  var parts = [];
  if (filterKey !== "todos") parts.push(["==", ["get", "level"], filterKey]);
  if (typeof mineOnly !== "undefined" && mineOnly) parts.push(["in", ["get", "h3"], ["literal", myCells().concat(["-"])]]);
  var expr = parts.length ? ["all"].concat(parts) : null;
  map.setFilter("heat", expr); map.setFilter("pins", expr);
  map.setFilter("photo-pins", expr); map.setFilter("photo-heat", expr);
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
    loadPhotos(extra);
  } catch (e) {}
}

// Zoomed in close: a small pin for each photo, at the exact spot, so a new photo in a place that already has a
// pin is still seen. Every published photo in view is drawn, even when its hexagon is too cool to get a pin.
async function loadPhotos(extra) {
  var source = map.getSource("photos");
  if (!source) return;
  if (map.getZoom() < PHOTO_ZOOM) { source.setData(EMPTY); return; }
  var b = map.getBounds();
  var bbox = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()].join(",");
  try {
    var data = await (await fetch("/api/v1/heatmap/reports?bbox=" + bbox + extra)).json();
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
      layers: [{ id: "osm", type: "raster", source: "osm",
        paint: { "raster-saturation": -0.6, "raster-contrast": -0.15, "raster-brightness-min": 0.08 } }]
    }
  });

  map.addControl(new maplibregl.NavigationControl(), "bottom-right");

  // "Go to my location": centers the map on the GPS position once and shows a blue dot. It does not keep following:
  // a following map pulls itself back to the GPS while the person drags the pin to another place to report.
  geolocate = new maplibregl.GeolocateControl({
    positionOptions: { enableHighAccuracy: true, timeout: 10000 },
    trackUserLocation: false, showAccuracyCircle: true, fitBoundsOptions: { maxZoom: 16 }
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
      id: "heat", type: "heatmap", source: "heat", maxzoom: PHOTO_ZOOM,
      paint: {
        "heatmap-weight": ["interpolate", ["linear"], ["get", "score"], 0, 0, 100, 1],
        "heatmap-radius": ["interpolate", ["linear"], ["zoom"], 8, 15, 14, 45],
        "heatmap-opacity": 0.5,
        "heatmap-color": ["interpolate", ["linear"], ["heatmap-density"],
          0, "rgba(76,175,80,0)", 0.2, "#4CAF50", 0.4, "#FFC107", 0.6, "#FF9800", 0.8, "#F44336", 1, "#B71C1C"]
      }
    });
    map.addLayer({
      id: "pins", type: "symbol", source: "heat", minzoom: 11, maxzoom: PHOTO_ZOOM,
      layout: {
        "icon-image": ["concat", "pin-", ["get", "level"]], "icon-allow-overlap": true, "icon-anchor": "bottom",
        "icon-size": ["interpolate", ["linear"], ["zoom"], 11, 0.7, 16, 1]
      }
    });
    map.addSource("photos", { type: "geojson", data: EMPTY });
    // Zoomed in: the smoke is drawn around each photo itself (not around the hexagon centre), in the colour of
    // its severity, and the pin is the same small trash-can icon as the hexagon pin.
    map.addLayer({
      id: "photo-heat", type: "circle", source: "photos", minzoom: PHOTO_ZOOM,
      paint: {
        // a soft glow in the colour of the pin's level (green / amber / red / dark red); bigger for dirtier spots
        "circle-color": ["match", ["get", "level"], "limpo", "#4CAF50", "moderado", "#FFC107", "sujo", "#FF9800", "muito-sujo", "#F44336", "#B71C1C"],
        "circle-radius": ["interpolate", ["linear"], ["zoom"], 14, ["+", 10, ["*", 0.25, ["get", "severity"]]], 19, ["+", 30, ["*", 0.9, ["get", "severity"]]]],
        "circle-blur": 1, "circle-opacity": 0.45
      }
    }, "pins");
    map.addLayer({
      id: "photo-pins", type: "symbol", source: "photos", minzoom: PHOTO_ZOOM,
      layout: {
        "icon-image": ["concat", "pin-", ["get", "level"]], "icon-allow-overlap": true, "icon-anchor": "bottom",
        "icon-size": ["interpolate", ["linear"], ["zoom"], 14, 0.75, 19, 1]
      }
    });
    map.on("mouseenter", "photo-pins", function () { map.getCanvas().style.cursor = "pointer"; });
    map.on("mouseleave", "photo-pins", function () { map.getCanvas().style.cursor = ""; });
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
