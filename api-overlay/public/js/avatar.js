// Paints a round avatar: the person's picture when they have one, otherwise their first initial.

import { el } from "./dom.js";

export function paintAvatar(node, user) {
  node.textContent = "";
  if (user.avatar_url && /^\//.test(user.avatar_url)) { // a path on this site, never another address
    var img = el("img"); img.src = user.avatar_url; img.alt = ""; img.decoding = "async";
    node.appendChild(img);
  } else {
    node.textContent = String(user.name || user.email || "?").trim().charAt(0).toUpperCase();
  }
}

// What a profile link may point to: only a web address.
export function safeWebAddress(url) { return /^https?:\/\//i.test(String(url || "")) ? url : ""; }
