// Small DOM helpers used by every screen.

export var $ = function (id) { return document.getElementById(id); };

var toastTimer = null;

export function toast(msg) {
  var t = $("toast"); t.textContent = msg; t.style.display = "block";
  clearTimeout(toastTimer); toastTimer = setTimeout(function () { t.style.display = "none"; }, 2200);
}

// Hides the map-screen chrome while a report is being made (the report steps use the whole screen).
export function chrome(on) {
  ["topbar", "chips", "chips2", "nav"].forEach(function (id) { $(id).style.display = on ? "" : "none"; });
}

export function el(tag, text, cls) {
  var n = document.createElement(tag);
  if (text != null) n.textContent = text;
  if (cls) n.className = cls;
  return n;
}

export function show(id, on, display) { $(id).style.display = on ? (display || "block") : "none"; }
