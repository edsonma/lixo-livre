(async function () {
  var $ = function (id) { return document.getElementById(id); };
  $("pager").scrollLeft = $("pager").clientWidth; // the pages are Explorar | Mapa | Perfil: start on the map
  document.body.dataset.page = "map";
  // severity is 0-100
  var status = { center: { lat: -15.7942, lng: -47.8825 }, demo_mode: false };
  try { status = await (await fetch("/api/v1/status")).json(); } catch (e) {}

  document.getElementById("demo").style.display = status.demo_mode ? "inline-block" : "none";

  var map = new maplibregl.Map({
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
  window.__lixo = { map: map }; // a handle for the browser tests

  var EMPTY = { type: "FeatureCollection", features: [] };

  // Levels of a spot, from the decayed score of its cell. The chips filter on these.
  var LEVELS = [
    { key: "limpo", label: "Limpo", max: 25, color: "#2e9e4f" },
    { key: "moderado", label: "Moderado", max: 50, color: "#f2a900" },
    { key: "sujo", label: "Sujo", max: 75, color: "#e8452c" },
    { key: "muito-sujo", label: "Muito sujo", max: Infinity, color: "#b3261e" }
  ];
  function levelOf(score) { return LEVELS.find(function (l) { return score < l.max; }); }
  function levelLabel(s) { return levelOf(s).label; }

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
  function applyFilter() {
    if (!map.getLayer("heat")) return;
    var expr = filterKey === "todos" ? null : ["==", ["get", "level"], filterKey];
    map.setFilter("heat", expr); map.setFilter("pins", expr);
  }

  async function loadHeat() {
    var b = map.getBounds();
    var bbox = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()].join(",");
    try {
      var data = await (await fetch("/api/v1/heatmap?bbox=" + bbox)).json();
      data.features.forEach(function (f) { f.properties.level = levelOf(f.properties.score).key; });
      map.getSource("heat").setData(data);
    } catch (e) {}
  }

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
      id: "pins", type: "symbol", source: "heat", minzoom: 11,
      layout: {
        "icon-image": ["concat", "pin-", ["get", "level"]], "icon-allow-overlap": true,
        "icon-size": ["interpolate", ["linear"], ["zoom"], 11, 0.5, 16, 0.85]
      }
    });
    map.on("mouseenter", "pins", function () { map.getCanvas().style.cursor = "pointer"; });
    map.on("mouseleave", "pins", function () { map.getCanvas().style.cursor = ""; });
    map.on("moveend", loadHeat);
    applyFilter();
    loadHeat();
  });

  // ---- Level chips ----
  document.querySelectorAll("#chips .chip").forEach(function (chip) {
    chip.onclick = function () {
      filterKey = chip.dataset.level;
      document.querySelectorAll("#chips .chip").forEach(function (c) { c.setAttribute("aria-pressed", c === chip ? "true" : "false"); });
      applyFilter();
    };
  });

  // ---- Address search (OpenStreetMap Nominatim: type and press Enter, one request at a time) ----
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

  // ---- Bottom navigation (the other tabs come with their screens) ----
  var toastTimer = null;
  function toast(msg) {
    var t = $("toast"); t.textContent = msg; t.style.display = "block";
    clearTimeout(toastTimer); toastTimer = setTimeout(function () { t.style.display = "none"; }, 2200);
  }
  ["nav-alerts", "bell"].forEach(function (id) {
    $(id).onclick = function () { toast("Em breve"); };
  });

  // ---- Pages: swipe left to Explorar, right to Perfil ----
  var PAGES = ["explore", "map", "profile"], pager = $("pager"), currentPage = "map";
  function syncPage() {
    var i = Math.max(0, Math.min(PAGES.length - 1, Math.round(pager.scrollLeft / Math.max(1, pager.clientWidth))));
    if (PAGES[i] === currentPage) return;
    currentPage = PAGES[i];
    document.body.dataset.page = currentPage;
    PAGES.forEach(function (name) {
      var tab = $("nav-" + name), on = name === currentPage;
      tab.classList.toggle("on", on);
      if (on) tab.setAttribute("aria-current", "page"); else tab.removeAttribute("aria-current");
    });
  }
  function goPage(name, instant) {
    pager.scrollTo({ left: PAGES.indexOf(name) * pager.clientWidth, behavior: instant ? "auto" : "smooth" });
  }
  pager.addEventListener("scroll", syncPage, { passive: true });
  window.addEventListener("resize", function () { goPage(currentPage, true); });
  $("nav-map").onclick = $("explore-map").onclick = function () { goPage("map"); };
  $("nav-explore").onclick = function () { goPage("explore"); };
  $("nav-profile").onclick = function () { goPage("profile"); };

  // ---- Accounts: email + password, Google, and passkeys (fingerprint / face) ----
  var me = null, authMode = "in", googleLoaded = false;
  var passkeysSupported = !!(window.PublicKeyCredential && navigator.credentials && navigator.credentials.create);

  async function api(path, method, body) {
    var res = await fetch(path, { method: method || "GET", headers: body ? { "Content-Type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined });
    var data = await res.json().catch(function () { return {}; });
    return { ok: res.ok, status: res.status, data: data };
  }
  function firstName(user) { return String(user.name || user.email).split(" ")[0]; }

  // What the page shows depends on being logged in: the + button, the account icon, the profile page.
  function applyAuth() {
    $("report-btn").style.display = me ? "" : "none"; // only logged-in people can report
    $("acct-icon").style.display = me ? "none" : "";
    $("acct-initial").style.display = me ? "flex" : "none";
    $("acct").setAttribute("aria-label", me ? "Conta de " + me.name : "Conta: entrar ou criar conta");
    $("pf-guest").style.display = me ? "none" : "";
    $("pf-user").style.display = me ? "" : "none";
    if (!me) return;
    var initial = firstName(me).charAt(0).toUpperCase();
    $("acct-initial").textContent = initial; $("pf-avatar").textContent = initial;
    $("pf-name").textContent = me.name; $("pf-email").textContent = me.email;
    $("pf-role").style.display = me.admin ? "inline-block" : "none";
    $("pf-passkey").style.display = passkeysSupported ? "" : "none";
    $("pf-review").style.display = me.moderator ? "" : "none";
    if (me.moderator) refreshReviewCount();
    $("pf-passkey-info").textContent = me.passkeys ? "Biometria ativa em " + me.passkeys + (me.passkeys > 1 ? " aparelhos." : " aparelho.") : "";
  }
  async function loadMe() {
    try { var r = await api("/api/v1/session"); me = r.ok ? r.data.user : null; } catch (e) { me = null; }
    applyAuth();
  }

  function authError(msg) { $("au-error").textContent = msg || ""; }
  function setAuthMode(mode) {
    authMode = mode;
    $("au-tab-in").classList.toggle("on", mode === "in"); $("au-tab-up").classList.toggle("on", mode === "up");
    $("au-tab-in").setAttribute("aria-selected", mode === "in"); $("au-tab-up").setAttribute("aria-selected", mode === "up");
    show("au-name-row", mode === "up");
    $("au-submit").textContent = mode === "up" ? "Criar conta" : "Entrar";
    $("au-title").textContent = mode === "up" ? "Criar conta" : "Entrar";
    $("au-pass").setAttribute("autocomplete", mode === "up" ? "new-password" : "current-password");
    show("au-alt", mode === "in");
    authError("");
  }
  function openAuth(why, mode) {
    setAuthMode(mode || "in");
    $("au-why").textContent = why || "";
    show("au-passkey", passkeysSupported, "block");
    show("auth", true, "flex");
    setupGoogle();
  }
  function closeAuth() { show("auth", false); $("au-pass").value = ""; authError(""); }

  function signedIn(user) {
    me = user; applyAuth(); closeAuth();
    toast("Olá, " + firstName(user) + "!");
  }
  function failure(r, fallback) {
    if (r.status === 429) return "Muitas tentativas. Tente de novo em alguns minutos.";
    if (r.status === 401 && r.data.error === "invalid_credentials") return "E-mail ou senha incorretos.";
    var errs = r.data.errors || {};
    if (errs.email) return "Esse e-mail é inválido ou já tem conta. Tente entrar.";
    if (errs.password) return "A senha precisa ter pelo menos 8 caracteres.";
    if (r.status === 400) return "Preencha e-mail e senha.";
    return fallback;
  }

  $("au-form").onsubmit = async function (e) {
    e.preventDefault();
    var email = $("au-email").value.trim(), pass = $("au-pass").value;
    if (!email || !pass) return authError("Preencha e-mail e senha.");
    if (authMode === "up" && pass.length < 8) return authError("A senha precisa ter pelo menos 8 caracteres.");
    authError(""); $("au-submit").disabled = true;
    try {
      var r = authMode === "up"
        ? await api("/api/v1/users", "POST", { name: $("au-name").value.trim(), email: email, password: pass })
        : await api("/api/v1/session", "POST", { email: email, password: pass });
      if (r.ok) signedIn(r.data.user); else authError(failure(r, "Não foi possível entrar agora."));
    } catch (err) { authError("Sem conexão. Tente de novo."); }
    $("au-submit").disabled = false;
  };
  $("au-tab-in").onclick = function () { setAuthMode("in"); };
  $("au-tab-up").onclick = function () { setAuthMode("up"); };
  $("au-back").onclick = closeAuth;
  $("acct").onclick = function () { if (me) goPage("profile"); else openAuth(); };
  $("pf-login").onclick = function () { openAuth("Entre para reportar lixo no mapa."); };
  $("pf-logout").onclick = async function () {
    try { await api("/api/v1/session", "DELETE"); } catch (e) {}
    me = null; saveToken(""); applyAuth();
    if (reporting) closeReport();
    goPage("map"); toast("Você saiu.");
  };

  // Google: the "Sign in with Google" button gives us an ID token; the server checks it with Google.
  function setupGoogle() {
    var clientId = status.auth && status.auth.google_client_id;
    if (!clientId || googleLoaded) return;
    googleLoaded = true;
    var s = document.createElement("script");
    s.src = "https://accounts.google.com/gsi/client"; s.async = true;
    s.onload = function () {
      google.accounts.id.initialize({ client_id: clientId, callback: async function (resp) {
        var r = await api("/api/v1/session/google", "POST", { credential: resp.credential });
        if (r.ok) signedIn(r.data.user); else authError("Não foi possível entrar com o Google.");
      } });
      google.accounts.id.renderButton($("au-google"), { theme: "outline", size: "large", shape: "pill", text: "continue_with", locale: "pt-BR", width: 280 });
    };
    s.onerror = function () { googleLoaded = false; };
    document.head.appendChild(s);
  }

  // Passkeys: base64url <-> bytes, because the server speaks JSON and the browser speaks ArrayBuffers.
  function fromB64(text) {
    var b64 = String(text).replace(/-/g, "+").replace(/_/g, "/"), pad = (4 - b64.length % 4) % 4;
    var bin = atob(b64 + "====".slice(0, pad)), bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes.buffer;
  }
  function toB64(buffer) {
    var bytes = new Uint8Array(buffer), bin = "";
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  // What went wrong, in words, with the technical detail at the end so it can be reported.
  function serverDetail(r) { return "servidor " + r.status + (r.data && (r.data.message || r.data.error) ? " – " + (r.data.message || r.data.error) : ""); }
  function passkeyMessage(e, fallback, withDetail) {
    var name = e && e.name;
    if (name === "NotAllowedError") return "Cancelado ou não reconhecido pelo aparelho. Tente de novo.";
    if (name === "InvalidStateError") return "Este aparelho já tem biometria ativa nesta conta.";
    if (name === "NotSupportedError") return "Este aparelho ou navegador não aceita biometria (passkeys). Verifique se há bloqueio de tela (digital, rosto ou PIN).";
    if (name === "SecurityError") return "O navegador bloqueou a biometria para este endereço (precisa ser https).";
    return withDetail ? fallback + " (" + (e && (e.message || e.name) || "erro desconhecido") + ")." : fallback;
  }

  async function addPasskey() {
    $("pf-passkey").disabled = true; $("pf-passkey-info").textContent = "";
    try {
      var o = await api("/api/v1/passkeys/registration_options", "POST");
      if (!o.ok) throw new Error(serverDetail(o));
      var pk = o.data;
      pk.challenge = fromB64(pk.challenge); pk.user.id = fromB64(pk.user.id);
      (pk.excludeCredentials || []).forEach(function (c) { c.id = fromB64(c.id); });
      var cred = await navigator.credentials.create({ publicKey: pk });
      var r = await api("/api/v1/passkeys", "POST", { nickname: (navigator.platform || "Aparelho"), credential: {
        id: cred.id, rawId: toB64(cred.rawId), type: cred.type,
        response: { attestationObject: toB64(cred.response.attestationObject), clientDataJSON: toB64(cred.response.clientDataJSON) },
        clientExtensionResults: cred.getClientExtensionResults ? cred.getClientExtensionResults() : {}
      } });
      if (!r.ok) throw new Error(serverDetail(r));
      me.passkeys = (me.passkeys || 0) + 1; applyAuth(); toast("Biometria ativada!");
    } catch (e) {
      $("pf-passkey-info").textContent = passkeyMessage(e, "Não foi possível ativar a biometria", true);
    }
    $("pf-passkey").disabled = false;
  }
  $("pf-passkey").onclick = addPasskey;

  async function passkeyLogin() {
    authError(""); $("au-passkey").disabled = true;
    try {
      var o = await api("/api/v1/passkeys/authentication_options", "POST");
      if (!o.ok) throw new Error(serverDetail(o));
      var pk = o.data; pk.challenge = fromB64(pk.challenge);
      (pk.allowCredentials || []).forEach(function (c) { c.id = fromB64(c.id); });
      var cred = await navigator.credentials.get({ publicKey: pk });
      var r = await api("/api/v1/passkeys/authenticate", "POST", { credential: {
        id: cred.id, rawId: toB64(cred.rawId), type: cred.type,
        response: {
          authenticatorData: toB64(cred.response.authenticatorData), clientDataJSON: toB64(cred.response.clientDataJSON),
          signature: toB64(cred.response.signature), userHandle: cred.response.userHandle ? toB64(cred.response.userHandle) : null
        },
        clientExtensionResults: cred.getClientExtensionResults ? cred.getClientExtensionResults() : {}
      } });
      if (r.ok) signedIn(r.data.user); else authError("Biometria não reconhecida. Entre com e-mail e senha.");
    } catch (e) {
      authError(passkeyMessage(e, "Não foi possível usar a biometria", true));
    }
    $("au-passkey").disabled = false;
  }
  $("au-passkey").onclick = passkeyLogin;
  loadMe();

  // Hides the map-screen chrome while a report is being made (the report steps use the whole screen).
  function chrome(on) {
    ["topbar", "chips", "nav"].forEach(function (id) { $(id).style.display = on ? "" : "none"; });
  }

  // Meters per pixel at this zoom, times ~40px: clicking selects roughly that area.
  function radiusFor() {
    var lat = map.getCenter().lat * Math.PI / 180;
    var mpp = 156543.03 * Math.cos(lat) / Math.pow(2, map.getZoom());
    return Math.max(10, Math.min(500, Math.round(mpp * 40)));
  }

  function el(tag, text, cls) {
    var n = document.createElement(tag);
    if (text != null) n.textContent = text;
    if (cls) n.className = cls;
    return n;
  }



  // ---- Place screen: tap a spot on the map ----
  var MONTH_NAMES = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];
  var place = null, placeRun = 0;

  function shortDate(iso) {
    var d = new Date(iso);
    return d.getDate() + " " + MONTH_NAMES[d.getMonth()].toLowerCase() + " " + d.getFullYear();
  }
  function photoPath(url) { try { return new URL(url, location.href).pathname; } catch (e) { return ""; } }

  // The closest cell of the map to a tap, within ~44px (works at any zoom, also where pins are not drawn).
  function cellNear(point) {
    var best = null, bestDistance = 44;
    map.querySourceFeatures("heat").forEach(function (f) {
      var p = map.project(f.geometry.coordinates), d = Math.hypot(p.x - point.x, p.y - point.y);
      if (d < bestDistance) { best = f; bestDistance = d; }
    });
    return best;
  }

  map.on("click", function (e) {
    if (reporting) return;
    var cell = cellNear(e.point);
    if (!cell) return toast("Nenhum registro aqui. Aproxime o mapa e toque em um pino.");
    openPlace(cell.properties.h3);
  });

  function chartSvg(points) {
    var W = 320, H = 150, L = 30, R = 12, T = 12, B = 26, NS = "http://www.w3.org/2000/svg";
    function node(name, attrs, text) {
      var n = document.createElementNS(NS, name);
      Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); });
      if (text != null) n.textContent = text;
      return n;
    }
    var svg = node("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "Evolução da limpeza por mês" });
    var y = function (v) { return T + (H - T - B) * (1 - v / 100); };
    [0, 50, 100].forEach(function (v) {
      svg.appendChild(node("line", { x1: L, x2: W - R, y1: y(v), y2: y(v), stroke: "#e3e8e4", "stroke-width": 1 }));
      svg.appendChild(node("text", { x: L - 6, y: y(v) + 4, "text-anchor": "end", "font-size": 10, fill: "#7a857e" }, v));
    });
    var step = points.length > 1 ? (W - L - R - 20) / (points.length - 1) : 0;
    var xs = points.map(function (p, i) { return points.length > 1 ? L + 10 + step * i : (L + W - R) / 2; });
    if (points.length > 1) {
      svg.appendChild(node("polyline", { points: points.map(function (p, i) { return xs[i] + "," + y(p.average); }).join(" "), fill: "none", stroke: "#9aa59e", "stroke-width": 2, "stroke-linejoin": "round" }));
    }
    points.forEach(function (p, i) {
      var title = node("title", {}, MONTH_NAMES[+p.month.slice(5) - 1] + ": " + p.average + "/100 (" + p.reports + " registro" + (p.reports > 1 ? "s" : "") + ")");
      var dot = node("circle", { cx: xs[i], cy: y(p.average), r: 5, fill: levelOf(p.average).color, stroke: "#fff", "stroke-width": 2 });
      dot.appendChild(title); svg.appendChild(dot);
      svg.appendChild(node("text", { x: xs[i], y: H - 8, "text-anchor": "middle", "font-size": 11, fill: "#7a857e" }, MONTH_NAMES[+p.month.slice(5) - 1]));
    });
    return svg;
  }

  function selectPhoto(report) {
    var level = levelOf(report.severity);
    $("detail").style.setProperty("--lvl", level.color);
    $("dt-photo").src = photoPath(report.photo_url);
    $("dt-badge").textContent = "🗑 " + level.label + " · " + report.severity;
    $("dt-date").textContent = shortDate(report.taken_at);
    var types = (report.trash_types || []).map(function (t) { return (TYPE_INFO[t] || ["", t])[1]; });
    $("dt-desc").textContent = report.extra_info || (types.length ? "Itens: " + types.join(", ") + "." : "");
    document.querySelectorAll("#dt-photos img").forEach(function (img) { img.classList.toggle("on", +img.dataset.id === report.id); });
  }

  async function openPlace(h3) {
    var run = ++placeRun;
    place = null;
    $("dt-title").textContent = "Carregando…"; $("dt-sub").textContent = ""; $("dt-desc").textContent = "";
    $("dt-photo").removeAttribute("src"); $("dt-badge").textContent = ""; $("dt-date").textContent = "";
    $("dt-chart").replaceChildren(); $("dt-photos").replaceChildren(); $("dt-photos").classList.remove("all"); $("dt-all").textContent = "Ver todas";
    show("detail", true, "flex");
    var data = null;
    try {
      var res = await fetch("/api/v1/places/" + encodeURIComponent(h3));
      if (res.ok) data = await res.json();
    } catch (e) {}
    if (run !== placeRun) return;
    if (!data) { show("detail", false); return toast("Não foi possível abrir este local agora."); }
    place = data;

    selectPhoto(data.latest);
    data.photos.forEach(function (r) {
      var img = document.createElement("img");
      img.src = photoPath(r.photo_url); img.alt = "Foto de " + shortDate(r.taken_at); img.loading = "lazy"; img.dataset.id = r.id;
      img.onclick = function () { selectPhoto(r); };
      $("dt-photos").appendChild(img);
    });
    selectPhoto(data.latest);
    show("dt-all", data.photos.length > 4, "inline-block");

    var chart = $("dt-chart");
    if (data.history.length) chart.appendChild(chartSvg(data.history));
    else chart.appendChild(el("div", "Ainda sem histórico neste local.", "none"));

    $("dt-title").textContent = "Local no mapa";
    $("dt-sub").textContent = data.center.lat.toFixed(5) + ", " + data.center.lng.toFixed(5);
    var parts = await addressParts(data.center.lat, data.center.lng);
    if (run === placeRun && parts) {
      $("dt-title").textContent = parts.street || parts.area;
      $("dt-sub").textContent = parts.street ? parts.area : "";
    }
  }

  function closePlace() { placeRun++; place = null; show("detail", false); }
  $("dt-back").onclick = closePlace;
  $("dt-all").onclick = function () {
    var all = $("dt-photos").classList.toggle("all");
    this.textContent = all ? "Ver menos" : "Ver todas";
  };
  $("dt-follow").onclick = function () { toast("Em breve"); };


  // ---- Moderation (admins and moderators): held reports and flagged photos ----
  var REASON_TEXT = {
    not_trash: "não é lixo", privacy: "privacidade", inappropriate: "inadequada", duplicate: "duplicada", wrong_location: "local errado"
  };
  function reasonText(r) {
    if (r.kind === "flagged") {
      var parts = Object.keys(r.flags || {}).map(function (k) { return (REASON_TEXT[k] || k) + (r.flags[k] > 1 ? " ×" + r.flags[k] : ""); });
      return "Denunciada: " + (parts.join(", ") || "sem motivo") + (r.hidden ? " (já escondida)" : "");
    }
    if (r.reason === "metadata_mismatch") {
      var far = r.exif_distance_m ? " (a foto foi tirada a " + (r.exif_distance_m >= 1000 ? (r.exif_distance_m / 1000).toFixed(1) + " km" : r.exif_distance_m + " m") + " do pino)" : "";
      return "A foto parece ter sido tirada longe do local marcado ou em outra data" + far + ".";
    }
    if (r.reason === "low_confidence") return "A IA ficou em dúvida" + (r.ai_confidence ? " (" + Math.round(r.ai_confidence * 100) + "% de confiança)" : "") + ".";
    if (r.reason === "failed") return "Falha técnica no processamento" + (r.hold_reason ? ": " + r.hold_reason : "") + ".";
    return "Aguardando revisão.";
  }

  function reviewCard(r) {
    var card = el("div", null, "rv-card");
    var photo = el("div", null, "rv-photo");
    if (r.photo_url) {
      var img = document.createElement("img"); img.src = photoPath(r.photo_url); img.alt = "Foto enviada"; img.loading = "lazy"; photo.appendChild(img);
    } else {
      photo.appendChild(el("div", "Foto ainda não protegida (rostos e placas não foram borrados). Ela não é mostrada e não pode ser aprovada.", "rv-nophoto"));
    }
    photo.appendChild(el("span", r.kind === "flagged" ? "Denunciada" : "Em revisão", "rv-tag"));
    card.appendChild(photo);
    card.appendChild(el("div", reasonText(r), "rv-reason"));

    var meta = el("div", null, "rv-meta");
    meta.appendChild(document.createTextNode((r.uploader ? r.uploader.name + " (" + r.uploader.email + ")" : "Anônimo") + " · " + shortDate(r.taken_at) + " · " + r.lat.toFixed(4) + ", " + r.lng.toFixed(4) + " · "));
    var see = el("button", "ver no mapa", "link"); see.type = "button";
    see.onclick = function () { show("review", false); goPage("map"); map.jumpTo({ center: [r.lng, r.lat], zoom: 17 }); };
    meta.appendChild(see);
    card.appendChild(meta);

    var slider = null;
    if (r.kind === "held") {
      var box = el("div", null, "rv-sev");
      var label = el("label"); label.appendChild(el("span", "Nível de sujeira")); var value = el("b"); label.appendChild(value);
      slider = document.createElement("input"); slider.type = "range"; slider.min = 0; slider.max = 100; slider.value = r.severity != null ? r.severity : 50;
      var paint = function () { var l = levelOf(+slider.value); value.textContent = l.label + " · " + slider.value; box.style.setProperty("--lvl", l.color); };
      slider.oninput = paint; paint();
      box.appendChild(label); box.appendChild(slider); card.appendChild(box);
    }

    var err = el("div", null, "error"); err.setAttribute("role", "alert");
    var actions = el("div", null, "rv-actions");
    var yes = el("button", r.kind === "held" ? "Aprovar e publicar" : "Manter no mapa", "btn primary"); yes.type = "button";
    var no = el("button", r.kind === "held" ? "Rejeitar" : "Remover", "btn danger"); no.type = "button";
    if (r.kind === "held" && !r.photo_url) yes.disabled = true;

    async function act(path, body, done) {
      yes.disabled = no.disabled = true; err.textContent = "";
      try {
        var res = await api("/api/v1/admin/reviews/" + r.id + "/" + path, "POST", body || {});
        if (!res.ok) { err.textContent = res.status === 403 ? "Você não tem permissão." : (res.data.message || "Não foi possível agora."); yes.disabled = no.disabled = false; return; }
        card.remove(); toast(done); refreshReviewCount(); loadHeat();
        if (!$("rv-body").querySelector(".rv-card")) loadReviews();
      } catch (e) { err.textContent = "Sem conexão. Tente de novo."; yes.disabled = no.disabled = false; }
    }
    yes.onclick = function () { act("approve", slider ? { severity: +slider.value } : {}, r.kind === "held" ? "Publicado no mapa." : "Mantida no mapa."); };
    var armTimer = null;
    no.onclick = function () { // two taps: the first only arms it
      if (!no.classList.contains("armed")) {
        no.classList.add("armed"); no.textContent = "Toque de novo para confirmar";
        armTimer = setTimeout(function () { no.classList.remove("armed"); no.textContent = r.kind === "held" ? "Rejeitar" : "Remover"; }, 3500);
        return;
      }
      clearTimeout(armTimer);
      act("reject", {}, r.kind === "held" ? "Rejeitada." : "Removida do mapa.");
    };
    actions.appendChild(yes); actions.appendChild(no);
    card.appendChild(actions); card.appendChild(err);
    return card;
  }

  async function loadReviews() {
    var body = $("rv-body"); body.replaceChildren(el("div", "Carregando…", "rv-empty"));
    var res = await api("/api/v1/admin/reviews").catch(function () { return null; });
    body.replaceChildren();
    if (!res || !res.ok) { body.appendChild(el("div", res && res.status === 403 ? "Você não tem permissão para moderar." : "Não foi possível carregar a fila agora.", "rv-empty")); return; }
    var d = res.data;
    $("pf-review-count").textContent = (d.counts.held + d.counts.flagged) || "";
    if (!d.held.length && !d.flagged.length) { body.appendChild(el("div", "Nada para revisar por enquanto. 🎉", "rv-empty")); return; }
    if (d.held.length) { body.appendChild(el("h3", "Em revisão (" + d.counts.held + ")")); d.held.forEach(function (r) { body.appendChild(reviewCard(r)); }); }
    if (d.flagged.length) { body.appendChild(el("h3", "Fotos denunciadas (" + d.counts.flagged + ")")); d.flagged.forEach(function (r) { body.appendChild(reviewCard(r)); }); }
  }
  async function refreshReviewCount() {
    var res = await api("/api/v1/admin/reviews").catch(function () { return null; });
    if (res && res.ok) $("pf-review-count").textContent = (res.data.counts.held + res.data.counts.flagged) || "";
  }
  $("pf-review").onclick = function () { show("review", true, "flex"); loadReviews(); };
  $("rv-back").onclick = function () { show("review", false); };
  $("rv-refresh").onclick = loadReviews;

  // ---- Report a photo: upload, then poll until the AI has scored it ----
  var memoryToken = null;
  function storedToken() { try { return localStorage.getItem("lixo-device-token"); } catch (e) { return memoryToken; } }
  function saveToken(t) { memoryToken = t; try { localStorage.setItem("lixo-device-token", t); } catch (e) {} }
  async function deviceToken() {
    var t = storedToken();
    if (t) return t;
    var res = await fetch("/api/v1/devices", { method: "POST" });
    if (!res.ok) throw new Error("Não foi possível iniciar o envio.");
    t = (await res.json()).token;
    saveToken(t);
    return t;
  }

  var previewUrl = null, pollTimer = null, polling = 0;

  function showError(msg) { $("error").textContent = msg || ""; }

  // The flow: 1. choose the place on the map, 2. take or choose the photo, 3. watch the AI score it.
  var reporting = false, step = null, placed = null, marker = null, chosen = null;
  var stream = null, facing = "environment", liveCamera = false, camRun = 0;

  function show(id, on, display) { $(id).style.display = on ? (display || "block") : "none"; }
  function placeError(msg) { $("place-error").textContent = msg || ""; }
  function camMessage(msg) { $("cam-error").textContent = msg || ""; }
  function sheetPadding() { return Math.min(340, Math.round(window.innerHeight * 0.42)); }

  function showCoords() {
    var c = map.getCenter();
    $("coords").textContent = c.lat.toFixed(5) + ", " + c.lng.toFixed(5);
  }
  map.on("move", function () { if (step === "place") showCoords(); });

  function dropMarker() {
    if (marker) { marker.remove(); marker = null; }
  }

  // ---- Camera (live preview with getUserMedia; the phone's own camera app is the fallback) ----
  function stopCamera() {
    camRun++;
    if (stream) { stream.getTracks().forEach(function (t) { t.stop(); }); stream = null; }
    $("video").srcObject = null;
    liveCamera = false;
  }

  function showFallback(text) {
    stopCamera();
    show("video", false); show("cam-fallback", true, "flex"); $("cam-fallback").textContent = text;
    $("flip").style.visibility = "hidden";
  }

  async function startCamera() {
    stopCamera();
    var run = camRun;
    camMessage("");
    show("shot", false); show("video", true); show("cam-fallback", false);
    $("flip").style.visibility = "hidden";
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      return showFallback("Toque no botão verde para abrir a câmera do celular.");
    }
    try {
      var s = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: facing }, width: { ideal: 1920 }, height: { ideal: 1440 } }, audio: false
      });
      if (run !== camRun) { s.getTracks().forEach(function (t) { t.stop(); }); return; } // the person moved on while the permission prompt was open
      stream = s; liveCamera = true;
      $("video").srcObject = s;
      $("flip").style.visibility = "visible";
      try { await $("video").play(); } catch (e) {}
    } catch (e) {
      if (run !== camRun) return;
      showFallback("Sem acesso à câmera. Toque no botão verde para usar a câmera do celular, ou escolha uma foto da galeria.");
    }
  }

  function captureFrame() {
    var v = $("video");
    if (!v.videoWidth) return camMessage("A câmera ainda está iniciando. Tente de novo.");
    $("shutter").disabled = true; // feedback right away, and no double tap while the photo is encoded
    var scale = Math.min(1, 2000 / Math.max(v.videoWidth, v.videoHeight));
    var canvas = document.createElement("canvas");
    canvas.width = Math.round(v.videoWidth * scale); canvas.height = Math.round(v.videoHeight * scale);
    canvas.getContext("2d").drawImage(v, 0, 0, canvas.width, canvas.height);
    canvas.toBlob(function (blob) {
      if (!blob) { $("shutter").disabled = false; return camMessage("Não foi possível capturar a foto. Tente de novo."); }
      setChosen(new File([blob], "foto.jpg", { type: "image/jpeg", lastModified: Date.now() }));
    }, "image/jpeg", 0.9);
  }

  // The camera screen has two states: taking a photo (shutter, tabs) and reviewing it (retake, send).
  function showCaptureState() {
    show("shot", false); show("cam-caption", true);
    show("cam-controls", true, "flex"); show("cam-tabs", true, "flex"); show("cam-review", false);
    $("send").disabled = true; $("shutter").disabled = false;
  }
  function showReviewState() {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    previewUrl = URL.createObjectURL(chosen);
    $("shot").src = previewUrl;
    show("video", false); show("cam-fallback", false); show("shot", true); show("cam-caption", false);
    show("cam-controls", false); show("cam-tabs", false); show("cam-review", true, "flex");
    $("send").disabled = false;
    camMessage("");
  }
  function setChosen(file) {
    stopCamera();
    chosen = file;
    showReviewState();
  }


  // ---- Analysis screen: the AI's result, then "Publicar no Lixo Livre" or "Voltar" ----
  var TYPE_INFO = {
    plastic: ["🧴", "Plástico"], paper: ["📄", "Papel e papelão"], glass: ["🍾", "Vidro"], metal: ["🥫", "Metal"],
    organic: ["🍂", "Resíduos orgânicos"], construction_debris: ["🧱", "Entulho"], electronics: ["🔌", "Eletrônicos"],
    bulky_items: ["🛋️", "Itens volumosos"], textile: ["👕", "Têxteis"], hazardous: ["⚠️", "Perigosos"],
    mixed: ["🗑️", "Lixo misto"], other: ["📦", "Outros"]
  };
  var draft = null;

  function anMessage(msg) { $("an-error").textContent = msg || ""; }

  // { street, area } from OpenStreetMap, or null when it cannot say.
  async function addressParts(lat, lng) {
    try {
      var res = await fetch("https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&lat=" + lat + "&lon=" + lng, { headers: { "Accept-Language": "pt-BR" } });
      if (!res.ok) return null;
      var a = (await res.json()).address || {};
      var street = a.road || a.pedestrian || a.footway || a.path || null;
      var area = [a.suburb || a.neighbourhood || a.quarter, a.city || a.town || a.village, a.state].filter(Boolean).join(" - ");
      return street || area ? { street: street, area: area } : null;
    } catch (e) { return null; }
  }
  async function addressOf(lat, lng) {
    var parts = await addressParts(lat, lng);
    return parts ? [parts.street, parts.area].filter(Boolean).join(", ") : null;
  }

  function showAnalysis(r) {
    draft = r; step = "analysis";
    var level = levelOf(r.severity);
    $("analysis").style.setProperty("--lvl", level.color);
    $("an-level").textContent = level.label;
    $("an-num").textContent = r.severity;
    try { $("an-photo").src = new URL(r.photo_url, location.href).pathname; } catch (e) {}
    var box = $("an-items"); box.replaceChildren();
    (r.trash_types || []).forEach(function (type) {
      var info = TYPE_INFO[type] || ["📦", type];
      var item = el("div", null, "an-item");
      item.appendChild(el("span", info[0], "ico")); item.appendChild(el("span", info[1]));
      box.appendChild(item);
    });
    if (!box.children.length) box.appendChild(el("div", "Nenhum item específico identificado.", "an-none"));
    $("an-address").textContent = "Local escolhido no mapa";
    $("an-coords").textContent = r.lat.toFixed(5) + ", " + r.lng.toFixed(5);
    anMessage(""); $("an-publish").disabled = false; $("an-discard").disabled = false;
    show("report", false); show("analysis", true, "flex");
    addressOf(r.lat, r.lng).then(function (text) { if (text && draft === r) $("an-address").textContent = text; });
  }

  async function ownReportRequest(method, suffix) {
    var token = await deviceToken();
    return fetch("/api/v1/me/trashes/" + draft.id + (suffix || ""), { method: method, headers: { "X-Device-Token": token } });
  }

  $("an-publish").onclick = async function () {
    if (!draft) return;
    anMessage(""); $("an-publish").disabled = true; $("an-discard").disabled = true;
    try {
      var res = await ownReportRequest("POST", "/publish");
      if (!res.ok) throw new Error("Não foi possível publicar agora. Tente de novo.");
      show("analysis", false);
      setStatus(false, "Publicado no mapa. Obrigado por ajudar!");
      show("progress", true); show("report", true); step = "progress";
      $("again").style.display = "inline-block"; $("done").style.display = "inline-block";
      draft = null;
      // the heat cell is re-scored in the background: look again a little later
      [1500, 5000].forEach(function (ms) { setTimeout(loadHeat, ms); });
    } catch (e) {
      anMessage(e.message); $("an-publish").disabled = false; $("an-discard").disabled = false;
    }
  };

  // "Voltar": the report was never published, so it is deleted and the person is back on the map.
  $("an-discard").onclick = $("an-back").onclick = async function () {
    if (!draft) return closeReport();
    anMessage(""); $("an-publish").disabled = true; $("an-discard").disabled = true;
    try {
      var res = await ownReportRequest("DELETE");
      if (!res.ok && res.status !== 404) throw new Error("Não foi possível descartar agora. Tente de novo.");
      draft = null; closeReport();
    } catch (e) {
      anMessage(e.message); $("an-publish").disabled = false; $("an-discard").disabled = false;
    }
  };

  // ---- Steps ----
  // Step 1: the pin stays in the middle of the screen, the map moves under it.
  function goToPlace() {
    step = "place";
    dropMarker(); stopCamera(); draft = null;
    show("analysis", false); show("camera", false); show("report", false); show("place", true); show("pin", true); chrome(false);
    placeError(""); showCoords();
    map.easeTo({ padding: { bottom: 0 }, center: placed || map.getCenter(), zoom: Math.max(map.getZoom(), 16), duration: 300 });
  }

  // Step 2: the place is fixed on a marker; a full camera screen opens on top.
  function goToPhoto() {
    step = "photo";
    placed = map.getCenter();
    var pin = document.createElement("div");
    pin.className = "placed-pin"; pin.textContent = "📍";
    marker = new maplibregl.Marker({ element: pin, anchor: "bottom" }).setLngLat(placed).addTo(map);
    show("pin", false); show("place", false); show("report", false);
    show("camera", true, "flex");
    if (chosen) showReviewState();
    else { showCaptureState(); startCamera(); }
  }

  // Step 3: the camera screen closes and the sheet shows the progress and the score.
  function goToProgress() {
    step = "progress";
    stopCamera(); show("camera", false);
    show("progress", true); show("report", true);
    map.easeTo({ center: placed, padding: { bottom: sheetPadding() }, duration: 300 });
  }

  function openReport() {
    if (!me) return openAuth("Entre para reportar lixo no mapa.");
    resetReport();
    reporting = true; placed = null;
    goToPlace();
  }
  function closeReport() {
    polling++; clearTimeout(pollTimer);
    reporting = false; step = null; dropMarker(); stopCamera();
    show("analysis", false); show("camera", false); show("place", false); show("report", false); show("pin", false); chrome(true);
    map.easeTo({ padding: { bottom: 0 }, duration: 200 });
  }
  function resetReport() {
    polling++; clearTimeout(pollTimer);
    stopCamera(); draft = null; show("analysis", false);
    $("photo").value = ""; $("photo-camera").value = ""; chosen = null;
    show("progress", false);
    $("again").style.display = "none"; $("done").style.display = "none";
    showError(""); camMessage("");
    showCaptureState();
    if (previewUrl) { URL.revokeObjectURL(previewUrl); previewUrl = null; }
  }

  $("report-btn").onclick = openReport;
  $("place-ok").onclick = goToPhoto;
  $("place-cancel").onclick = closeReport;
  $("cam-back").onclick = goToPlace;
  $("again").onclick = openReport;
  $("done").onclick = function () { closeReport(); loadHeat(); };

  $("shutter").onclick = function () {
    if (liveCamera) captureFrame(); else $("photo-camera").click(); // no live preview: use the phone's camera app
  };
  $("flip").onclick = function () { facing = facing === "environment" ? "user" : "environment"; startCamera(); };
  $("gallery-btn").onclick = $("tab-gallery").onclick = function () { $("photo").click(); };
  $("tab-camera").onclick = function () { if (!liveCamera && !chosen) startCamera(); };
  $("retake").onclick = function () {
    $("photo").value = ""; $("photo-camera").value = ""; chosen = null;
    showCaptureState(); startCamera();
  };
  // Photos from the gallery or from the phone's camera app keep their own EXIF (GPS, camera); frames captured by the live preview have none.
  $("photo").onchange = $("photo-camera").onchange = function () {
    var file = this.files[0];
    if (!file) return; // picker cancelled: keep what we had
    setChosen(file);
  };

  $("locate").onclick = function () {
    placeError("");
    if (!navigator.geolocation) return placeError("Seu navegador não oferece localização. Mova o mapa até o local.");
    $("locate").disabled = true;
    navigator.geolocation.getCurrentPosition(function (pos) {
      $("locate").disabled = false;
      map.flyTo({ center: [pos.coords.longitude, pos.coords.latitude], zoom: 17 });
    }, function () {
      $("locate").disabled = false;
      placeError("Não foi possível obter sua localização. Mova o mapa até o local.");
    }, { enableHighAccuracy: true, timeout: 10000 });
  };

  // While choosing the place, a tap on the map moves the pin there instead of opening the info panel.
  map.on("click", function (e) { if (step === "place") map.easeTo({ center: e.lngLat }); });

  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape") return;
    if (reporting) closeReport(); else if ($("review").style.display === "flex") show("review", false); else if ($("detail").style.display === "flex") closePlace();
  });
  // Never keep the camera on in the background; bring it back when the person returns to the photo step.
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) { if (liveCamera) stopCamera(); }
    else if (step === "photo" && !chosen) startCamera();
  });
  window.addEventListener("pagehide", stopCamera);

  function setStatus(spinning, text, severity) {
    var box = $("status");
    box.replaceChildren();
    if (spinning) box.appendChild(el("span", null, "spinner"));
    if (severity != null) {
      var score = el("div", String(severity), "score");
      score.appendChild(el("small", "/100"));
      score.setAttribute("aria-label", severity + " de 100");
      box.appendChild(score);
      var meter = el("div", null, "meter"), fill = document.createElement("div");
      fill.style.width = severity + "%";
      fill.style.background = "hsl(" + Math.round(120 * (1 - severity / 100)) + ", 70%, 45%)";
      meter.appendChild(fill);
      box.appendChild(meter);
    }
    box.appendChild(el("span", text));
  }

  function renderStage(r) {
    if (r.stage === "protecting_photo") return setStatus(true, "Protegendo sua privacidade…");
    if (r.stage === "analyzing") return setStatus(true, "Analisando…");
    if (r.stage === "scored") return showAnalysis(r);
    if (r.stage === "published") return setStatus(false, "Publicado no mapa. Obrigado por ajudar!");
    if (r.stage === "not_trash") return setStatus(false, "A IA não encontrou lixo nessa foto. Tente outra mais de perto.");
    return setStatus(false, "Sua foto ficou em revisão. Ela aparece no mapa depois de aprovada.");
  }

  async function poll(id, token, run, tries) {
    if (run !== polling) return; // cancelled or replaced
    var r = null;
    try {
      var res = await fetch("/api/v1/me/trashes/" + id, { headers: { "X-Device-Token": token } });
      if (res.ok) r = await res.json();
    } catch (e) {}
    if (run !== polling) return;
    if (r) {
      renderStage(r);
      if (r.done) { $("again").style.display = "inline-block"; $("done").style.display = "inline-block"; return; }
    }
    if (tries >= 40) {
      setStatus(false, "Ainda processando. Volte em instantes: sua foto já foi enviada.");
      $("again").style.display = "inline-block"; $("done").style.display = "inline-block";
      return;
    }
    pollTimer = setTimeout(function () { poll(id, token, run, tries + 1); }, 1500);
  }

  $("send").onclick = async function () {
    var file = chosen;
    if (!file) return;
    camMessage(""); $("send").disabled = true;
    try {
      var token = await deviceToken();
      var c = placed || map.getCenter();
      var form = new FormData();
      form.append("photo", file);
      form.append("lat", c.lat); form.append("lng", c.lng);
      // A gallery photo was usually taken earlier: its file date is the best guess (the server also reads the EXIF).
      var taken = file.lastModified && file.lastModified > 946684800000 && file.lastModified <= Date.now() ? new Date(file.lastModified) : new Date();
      form.append("taken_at", taken.toISOString());
      var res = await fetch("/api/v1/trashes", { method: "POST", headers: { "X-Device-Token": token }, body: form });
      var body = await res.json().catch(function () { return {}; });
      if (res.status === 401 && body.error === "login_required") {
        me = null; applyAuth(); closeReport(); openAuth("Sua sessão expirou. Entre de novo para enviar a foto.");
        return;
      }
      if (res.status === 401) { saveToken(""); throw new Error("Sessão expirada. Tente enviar de novo."); }
      if (!res.ok) {
        var msgs = body.errors ? Object.keys(body.errors).map(function (k) { return k + " " + body.errors[k].join(", "); }).join("; ") : "Erro " + res.status;
        throw new Error(msgs);
      }
      goToProgress();
      setStatus(true, "Enviando…");
      var run = ++polling;
      poll(body.id, token, run, 0);
    } catch (e) {
      camMessage(e.message || "Falha no envio."); // the camera screen is still open
      $("send").disabled = false;
    }
  };

})();
