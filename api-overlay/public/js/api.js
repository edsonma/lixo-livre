// Talking to the server: the JSON request helper and the device token.

export async function api(path, method, body) {
  var res = await fetch(path, { method: method || "GET", headers: body ? { "Content-Type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined });
  var data = await res.json().catch(function () { return {}; });
  return { ok: res.ok, status: res.status, data: data };
}

var memoryToken = null;

function storedToken() { try { return localStorage.getItem("lixo-device-token"); } catch (e) { return memoryToken; } }

export function saveToken(t) { memoryToken = t; try { localStorage.setItem("lixo-device-token", t); } catch (e) {} }

export async function deviceToken() {
  var t = storedToken();
  if (t) return t;
  var res = await fetch("/api/v1/devices", { method: "POST" });
  if (!res.ok) throw new Error("Não foi possível iniciar o envio.");
  t = (await res.json()).token;
  saveToken(t);
  return t;
}
