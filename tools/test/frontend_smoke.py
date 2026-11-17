#!/usr/bin/env python3
"""Browser smoke test for the web app in api-overlay/public (no Rails, no database needed).

It serves public/ with a small fake API, drives the real screens in headless Chromium and prints a
TRACE: for every step, which screen is open, a few key texts, the API calls that step made, and any
console error. The trace is the test: take it before a front-end refactor, take it after, and
`diff` the two. Same trace = same behaviour.

    python3 tools/test/frontend_smoke.py > /tmp/after.json
    python3 tools/test/frontend_smoke.py --check /tmp/before.json     # exit 1 and show the diff

Needs: pip install playwright (and a Chromium it can find, e.g. `playwright install chromium`).
"""
import argparse, difflib, json, os, re, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from email.parser import BytesParser
from email.policy import default

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "api-overlay", "public")
MIME = {".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
        ".png": "image/png", ".svg": "image/svg+xml", ".json": "application/json", ".map": "application/json"}
PIXEL = __import__("base64").b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

CENTER = {"lat": -15.7942, "lng": -47.8825}
USER = {"id": 1, "name": "Ana Souza", "email": "ana@example.com", "role": "user", "admin": False, "moderator": True,
        "passkeys": 0, "google": False, "terms_ok": True, "email_verified": True, "two_factor": False,
        "bio": None, "website": None, "gender": None, "avatar_url": None}


def report(id, stage="published", **kw):
    r = {"id": id, "ai_status": "validated", "kind": "dirty", "stage": stage, "done": True, "severity": 60,
         "trash_types": ["plastic"], "taken_at": "2026-11-01T12:00:00Z", "lat": CENTER["lat"], "lng": CENTER["lng"],
         "h3_index": "89a8100c0d3ffff", "published": stage == "published", "can_publish": stage == "scored",
         "photo_ready": True, "photo_url": "/fake/photo.png", "thumb_url": "/fake/photo.png"}
    r.update(kw)
    return r


class Fake:
    """The fake server's memory: who is logged in and what the user has reported."""
    def __init__(self):
        self.user = None
        self.requests = []
        self.uploaded = False
        self.published = False


STATE = Fake()


def api(method, path, query, body):
    """-> (status, json). Only what the screens ask for."""
    p = path.removeprefix("/api/v1")
    if p == "/status":
        return 200, {"status": "ok", "demo_mode": False, "center": CENTER, "legal": {"version": "2026-11", "name": "Lixo Livre", "email": "oi@example.com"},
                     "mail": {"enabled": True}, "auth": {"google_client_id": None}, "counts": {"reports": 2, "heat_cells": 2}}
    if p == "/session":
        if method == "GET":
            return (200, {"user": STATE.user}) if STATE.user else (401, {"error": "unauthorized"})
        if method == "POST":
            if body.get("password") == "wrong-password":
                return 401, {"error": "invalid_credentials"}
            STATE.user = dict(USER)
            return 200, {"user": STATE.user}
        if method == "DELETE":
            STATE.user = None
            return 200, {}
    if p == "/profile" and method == "PATCH":
        if not STATE.user:
            return 401, {"error": "unauthorized"}
        errors = {}
        if not (body.get("name") or "").strip():
            errors["name"] = ["can't be blank"]
        site = (body.get("website") or "").strip()
        if site and not re.match(r"(?i)https?://[^\s/]+\.[^\s/]+", site if re.match(r"(?i)https?://", site) else "https://" + site):
            errors["website"] = ["is not a valid web address"]
        if errors:
            return 422, {"errors": errors}
        STATE.user["name"] = body["name"].strip()
        STATE.user["bio"] = (body.get("bio") or "").strip() or None
        STATE.user["website"] = (site if re.match(r"(?i)https?://", site) else "https://" + site) if site else None
        STATE.user["gender"] = body.get("gender") or None
        if body.get("avatar"):
            STATE.user["avatar_url"] = "/fake/photo.png"
        elif body.get("remove_avatar") == "true":
            STATE.user["avatar_url"] = None
        STATE.profile_fields = sorted(k for k in body if k in ("name", "bio", "website", "gender", "avatar", "remove_avatar"))
        return 200, {"user": STATE.user}
    if p == "/users" and method == "POST":
        STATE.user = dict(USER, name=body.get("name") or "Nova Pessoa", email=body.get("email", "n@example.com"))
        return 201, {"user": STATE.user}
    if p == "/heatmap":
        feats = [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [CENTER["lng"], CENTER["lat"]]},
                  "properties": {"h3": "89a8100c0d3ffff", "score": 80.0, "count": 3, "trend": "up", "cleaned": False}},
                 {"type": "Feature", "geometry": {"type": "Point", "coordinates": [CENTER["lng"] + 0.01, CENTER["lat"] + 0.01]},
                  "properties": {"h3": "89a8100c0c7ffff", "score": 20.0, "count": 1, "trend": "down", "cleaned": False}}]
        return 200, {"type": "FeatureCollection", "features": feats}
    if p == "/rankings":
        return 200, {"radius_km": 5, "worst": [{"h3": "89a8100c0d3ffff", "lat": CENTER["lat"], "lng": CENTER["lng"], "score": 80.0, "count": 3, "trend": "up", "meters": 120}],
                     "regions": [{"name": "Asa Sul", "score": 55.0, "count": 4}]}
    if p.startswith("/places/"):
        photo = {"id": 7, "kind": "dirty", "severity": 80, "trash_types": ["plastic"], "extra_info": None, "taken_at": "2026-11-01T12:00:00Z",
                 "lat": CENTER["lat"], "lng": CENTER["lng"], "photo_url": "/fake/photo.png", "uploader": {"id": 1, "name": "Ana Souza"}}
        return 200, {"h3": p.rsplit("/", 1)[1], "center": CENTER, "score": 80.0, "cleaned_at": None, "trend": "up", "reports_count": 3,
                     "following": False, "latest": photo, "photos": [photo],
                     "history": [{"month": "2026-10", "average": 40, "reports": 1}, {"month": "2026-11", "average": 80, "reports": 2}]}
    if p == "/me/feed":
        return (200, [report(1), report(2, stage="in_review", published=False, severity=None)]) if STATE.user else (401, {"error": "unauthorized"})
    if p == "/notifications":
        return 200, {"unread": 1, "items": [{"id": 1, "kind": "worse", "h3": "89a8100c0d3ffff", "score": 80.0, "previous_score": 40.0,
                                                     "lat": CENTER["lat"], "lng": CENTER["lng"], "read": False, "created_at": "2026-11-02T10:00:00Z"}]}
    if p == "/notifications/read":
        return 200, {}
    if p.startswith("/follows"):
        return 200, []
    if p == "/admin/reviews":
        held = {"id": 5, "kind": "held", "reason": "low_confidence", "flags": {}, "severity": None, "trash_types": [], "ai_confidence": 0.4,
                "extra_info": None, "taken_at": "2026-11-01T12:00:00Z", "created_at": "2026-11-01T12:01:00Z", "lat": CENTER["lat"], "lng": CENTER["lng"],
                "exif_distance_m": 12, "hold_reason": None, "uploader": {"id": 2, "name": "Beto", "email": "beto@example.com"}, "hidden": False,
                "photo_protected": True, "photo_url": "/fake/photo.png"}
        return 200, {"counts": {"held": 1, "flagged": 0}, "held": [held], "flagged": []}
    if p == "/devices" and method == "POST":
        return 201, {"id": 1, "token": "tok"}
    if p == "/trashes" and method == "POST":
        STATE.uploaded = True
        return 201, report(9, stage="analyzing", done=False, published=False, photo_ready=False, photo_url=None, thumb_url=None, severity=None)
    if re.fullmatch(r"/me/trashes/9", p):
        return 200, report(9, stage="published" if STATE.published else "scored", published=STATE.published)
    if re.fullmatch(r"/me/trashes/9/publish", p):
        STATE.published = True
        return 200, report(9)
    if p in ("/consent", "/two_factor/setup", "/passkeys", "/account", "/email/resend"):
        return 200, {"secret": "JBSWY3DPEHPK3PXP", "uri": "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP"}
    return 404, {"error": "not_found", "path": p}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, status, body, ctype):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self):
        u = urlparse(self.path)
        if u.path.startswith("/api/v1/"):
            n = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(n) if n else b""
            ctype = self.headers.get("Content-Type") or ""
            if ctype.startswith("multipart/form-data"):  # a form with a picture: text fields as strings, files as True
                msg = BytesParser(policy=default).parsebytes(b"Content-Type: " + ctype.encode() + b"\r\n\r\n" + raw)
                body = {part.get_param("name", header="content-disposition"): (True if part.get_filename() else part.get_content().strip())
                        for part in msg.iter_parts()}
            else:
                try:
                    body = json.loads(raw) if raw else {}
                except ValueError:
                    body = {}
            STATE.requests.append(f"{self.command} {u.path}")
            status, data = api(self.command, u.path, parse_qs(u.query), body)
            return self._send(status, json.dumps(data).encode(), "application/json")
        if u.path.startswith("/fake/"):
            return self._send(200, PIXEL, "image/png")
        path = "index.html" if u.path == "/" else u.path.lstrip("/")
        full = os.path.normpath(os.path.join(ROOT, path))
        if not full.startswith(os.path.normpath(ROOT)) or not os.path.isfile(full):
            return self._send(404, b"not found", "text/plain")
        with open(full, "rb") as f:
            self._send(200, f.read(), MIME.get(os.path.splitext(full)[1], "application/octet-stream"))

    do_GET = do_POST = do_DELETE = do_PUT = do_PATCH = _handle


SCREENS = ["place", "camera", "settings", "editprofile", "viewer", "auth", "legal", "myphoto", "twofa", "alerts", "review", "detail", "analysis", "report"]
TEXTS = ["pf-name", "pf-email", "acct-initial", "bell-count", "nav-alerts-count", "toast", "au-title", "au-error", "place-title",
         "ex-where", "st-total", "pf-review-count", "set-2fa-state", "pf-about", "pf-site", "ep-error", "an-title", "an-score", "an-level", "dt-title", "lg-title"]
SNAP_JS = """([screens, texts]) => {
  const vis = e => !!e && getComputedStyle(e).display !== 'none' && getComputedStyle(e).visibility !== 'hidden';
  const out = { page: document.body.dataset.page,
    nav_on: [...document.querySelectorAll('#nav .on')].map(e => e.id).sort(),
    open: screens.filter(id => vis(document.getElementById(id))),
    text: {}, counts: {} };
  texts.forEach(id => { const e = document.getElementById(id); if (e && vis(e) && e.textContent.trim()) out.text[id] = e.textContent.trim().slice(0, 60); });
  for (const [k, sel] of Object.entries({ feed: '#feed-grid > *', worst: '#ex-worst > *', regions: '#ex-regions > *', alerts: '#al-body > *', review: '#rv-body > *', places: '#places-list > *' }))
    out.counts[k] = document.querySelectorAll(sel).length;
  const av = document.querySelectorAll('#pf-avatar img').length; if (av) out.counts.avatar_img = av;
  out.map_layers = window.__lixo && window.__lixo.map ? ['heat', 'pins'].filter(l => window.__lixo.map.getLayer(l)) : null;
  out.map_features = window.__lixo && window.__lixo.map && window.__lixo.map.getSource('heat') && window.__lixo.map.getSource('heat')._data ? (window.__lixo.map.getSource('heat')._data.features || []).length : null;
  return out;
}"""


def run(headed=False):
    from playwright.sync_api import sync_playwright
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    trace = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=not headed, args=[
            "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
            "--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream"])
        ctx = browser.new_context(viewport={"width": 390, "height": 800}, has_touch=True, permissions=["geolocation", "camera"],
                                  geolocation={"latitude": CENTER["lat"], "longitude": CENTER["lng"]}, locale="pt-BR")
        ctx.route(re.compile(r"https://(tile\.openstreetmap\.org|nominatim\.openstreetmap\.org|accounts\.google\.com).*"),
                  lambda r: r.fulfill(status=200, content_type="application/json", body="[]") if "nominatim" in r.request.url else r.fulfill(status=200, content_type="image/png", body=PIXEL))
        page = ctx.new_page()
        errors = []
        page.on("console", lambda m: errors.append("console." + m.type + ": " + m.text[:160]) if m.type in ("error",) and "favicon" not in m.text else None)
        page.on("pageerror", lambda e: errors.append("pageerror: " + str(e)[:200]))

        def step(name, fn=None, wait=250):
            STATE.requests.clear()
            del errors[:]
            err = None
            try:
                if fn:
                    fn()
                page.wait_for_timeout(wait)
            except Exception as e:  # a step that cannot be done is part of the trace too
                err = type(e).__name__ + ": " + str(e).split("\n")[0][:120]
            snap = page.evaluate(SNAP_JS, [SCREENS, TEXTS])
            trace.append({"step": name, "ui": snap, "api": sorted(set(STATE.requests)), "errors": sorted(set(errors)), "step_error": err})

        click = lambda sel: (lambda: page.click(sel, timeout=3000))

        step("boot as guest", lambda: page.goto(base + "/"), wait=1800)
        step("map pins render", lambda: page.wait_for_function("window.__lixo && __lixo.map.loaded() && __lixo.map.getSource('heat')._data.features.length > 0", timeout=8000))
        step("tab Explorar", click("#nav-explore"), wait=900)
        step("tab Perfil (guest)", click("#nav-profile"), wait=900)
        step("tab Mapa", click("#nav-map"), wait=900)
        step("bell as guest asks to sign in", click("#bell"))
        step("close auth", click("#au-back"))
        step("open account", click("#acct"))
        step("switch to sign up", click("#au-tab-up"))
        step("switch to sign in", click("#au-tab-in"))
        step("wrong password", lambda: (page.fill("#au-email", "ana@example.com"), page.fill("#au-pass", "wrong-password"), page.click("#au-submit")), wait=500)
        step("sign in", lambda: (page.fill("#au-pass", "password123"), page.click("#au-submit")), wait=900)
        step("tab Perfil (signed in)", click("#nav-profile"), wait=1600)  # long enough for the sign-in toast (2.2 s) to be gone every time
        step("opening the profile took the map to my latest published report", lambda: page.evaluate("""() => {
            var c = __lixo.map.getCenter(), z = __lixo.map.getZoom();
            if (Math.abs(c.lat - %s) > 0.0005 || Math.abs(c.lng - %s) > 0.0005 || Math.abs(z - 17) > 0.05) throw new Error('map at ' + c.lat + ',' + c.lng + ' z' + z);
        }""" % (CENTER["lat"], CENTER["lng"])), wait=300)
        step("open settings", click("#pf-menu"))
        step("open two-factor", click("#set-2fa"), wait=500)
        step("close two-factor", click("#tf-back"))
        step("close settings", click("#set-back"))
        step("open a photo from my feed", click("#feed-grid > *:first-child"), wait=500)
        step("close my photo", click("#mp-back"))
        step("open notifications", click("#nav-alerts"), wait=700)
        step("close notifications via Mapa tab", click("#nav-map"), wait=700)
        step("open moderation", lambda: (page.click("#nav-profile"), page.wait_for_timeout(600), page.click("#pf-menu"), page.wait_for_timeout(300), page.click("#pf-review")), wait=900)
        step("close moderation", lambda: (page.click("#rv-back"), page.wait_for_timeout(200), page.click("#set-back")))
        step("tap a pin on the map", lambda: (page.click("#nav-map"), page.wait_for_timeout(700),
                                              page.mouse.click(*[round(v) for v in page.evaluate("(() => { const p = __lixo.map.project([%f, %f]); const r = document.getElementById('map').getBoundingClientRect(); return [r.left + p.x, r.top + p.y]; })()" % (CENTER["lng"], CENTER["lat"]))])), wait=1000)
        step("close place screen", lambda: page.evaluate("document.getElementById('dt-back') && document.getElementById('dt-back').click()"))
        step("filter chips: Sujo", lambda: page.evaluate("[...document.querySelectorAll('#chips button, #chips .chip')].find(b => /sujo/i.test(b.textContent) && !/muito/i.test(b.textContent)).click()"), wait=600)
        step("report button -> confirm place", click("#report-btn"), wait=900)
        step("cancel place", click("#place-cancel"))
        step("report button again -> confirm", click("#report-btn"), wait=700)
        step("confirm place -> camera", click("#place-ok"), wait=1500)
        step("take a photo", click("#shutter"), wait=900)
        step("send the photo", click("#send"), wait=2500)
        step("publish the result", click("#an-publish"), wait=1200)
        step("close report screen", click("#done"), wait=700)
        step("open edit profile from the profile page", lambda: (page.click("#nav-profile"), page.wait_for_timeout(500), page.click("#pf-edit")), wait=400)
        step("the email field is read-only", lambda: page.evaluate("if (!document.getElementById('ep-email').disabled) throw new Error('email is editable')"))
        step("edit: empty name is refused before sending", lambda: (page.fill("#ep-name", ""), page.click("#ep-save")), wait=300)
        step("edit: server refuses a script link", lambda: (page.fill("#ep-name", "Ana Maria Souza"), page.fill("#ep-website", "javascript:alert(1)"), page.click("#ep-save")), wait=600)
        step("edit: a too-large picture is refused", lambda: page.set_input_files("#ep-file", {"name": "big.jpg", "mimeType": "image/jpeg", "buffer": b"x" * (8 * 1024 * 1024 + 1)}), wait=300)
        step("edit: save everything with a picture", lambda: (page.fill("#ep-website", "ana.example.com"), page.fill("#ep-bio", "Cuido da minha quadra"),
                                                              page.select_option("#ep-gender", "female"), page.set_input_files("#ep-file", {"name": "me.png", "mimeType": "image/png", "buffer": PIXEL}),
                                                              page.click("#ep-save")), wait=900)
        step("the profile shows the new details", None)
        step("edit from settings, then Escape closes it", lambda: (page.click("#pf-menu"), page.wait_for_timeout(300), page.click("#set-edit"), page.wait_for_timeout(300), page.keyboard.press("Escape")), wait=300)
        step("edit: remove the picture and clear the bio", lambda: (page.click("#pf-edit"), page.wait_for_timeout(300), page.click("#ep-remove"), page.fill("#ep-bio", ""),
                                                                   page.fill("#ep-name", "Ana Souza"), page.fill("#ep-website", ""), page.select_option("#ep-gender", ""),
                                                                   page.click("#ep-save")), wait=900)
        step("tap a photo to see all of it", lambda: (page.evaluate("var i = document.getElementById('dt-photo'); i.src = '/fake/photo.png'; document.getElementById('detail').style.display = 'flex'"), page.click("#dt-photo")), wait=300)
        step("Escape closes the full photo, not the screen under it", lambda: page.keyboard.press("Escape"), wait=300)
        step("tap the full photo to close it", lambda: (page.click("#dt-photo"), page.wait_for_timeout(200), page.click("#vw-img")), wait=300)
        step("leave the detail screen", lambda: page.evaluate("document.getElementById('detail').style.display = 'none'"), wait=200)
        step("back to the map tab", click("#nav-map"), wait=1800)
        step("sign out", lambda: (page.click("#nav-profile"), page.wait_for_timeout(500), page.click("#pf-menu"), page.wait_for_timeout(300), page.click("#pf-logout")), wait=900)
        browser.close()
    server.shutdown()
    return trace


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", help="compare the trace with this file and fail on any difference")
    ap.add_argument("--headed", action="store_true")
    a = ap.parse_args()
    text = json.dumps(run(a.headed), indent=1, ensure_ascii=False, sort_keys=True) + "\n"
    if not a.check:
        sys.stdout.write(text)
        sys.exit(0)
    want = open(a.check, encoding="utf-8").read()
    if want == text:
        print("frontend trace identical (%d steps)" % len(json.loads(text)))
        sys.exit(0)
    sys.stdout.writelines(difflib.unified_diff(want.splitlines(1), text.splitlines(1), "before", "after", n=2))
    sys.exit(1)
