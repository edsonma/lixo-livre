#!/usr/bin/env python3
"""Generates the synthetic street scenes used as fake report photos in demo mode
(api-overlay/db/demo_photos/severity-<1..5>-<a|b|c>.jpg).

They are drawings, not photographs: a wall, a pavement and a pile of bags, boxes and bottles
that grows with the severity. No people, no real places. The files are committed; run this only
to regenerate them:

    python3 tools/generate_demo_photos.py

Needs Pillow and numpy.
"""
import pathlib
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "api-overlay" / "db" / "demo_photos"
W, H = 480, 320
HORIZON = 175  # where the wall meets the pavement
ITEMS_BY_SEVERITY = {1: 2, 2: 7, 3: 16, 4: 30, 5: 52}
SPREAD_BY_SEVERITY = {1: 22, 2: 42, 3: 68, 4: 95, 5: 125}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def background(d, rng):
    for y in range(0, 100):
        d.line([(0, y), (W, y)], fill=lerp((176, 205, 232), (222, 232, 240), y / 100))
    wall = rng.choice([(206, 190, 163), (190, 186, 180), (172, 178, 160), (216, 201, 180), (196, 170, 150)])
    d.rectangle([0, 70, W, HORIZON], fill=wall)
    for x in range(rng.randint(10, 40), W, rng.randint(70, 110)):  # windows / shutters
        d.rectangle([x, 95, x + 38, 140], fill=lerp(wall, (60, 70, 85), 0.55))
        d.rectangle([x, 95, x + 38, 140], outline=lerp(wall, (255, 255, 255), 0.4), width=2)
    for y in range(HORIZON, H):  # pavement
        d.line([(0, y), (W, y)], fill=lerp((136, 136, 130), (92, 92, 90), (y - HORIZON) / (H - HORIZON)))
    d.rectangle([0, HORIZON, W, HORIZON + 6], fill=(88, 88, 86))  # base of the wall
    for x in range(-40, W + 40, 60):  # paving joints
        d.line([(x, HORIZON + 6), (x - 60, H)], fill=(110, 110, 106), width=1)


def bag(d, x, y, s, rng):
    color = rng.choice([(24, 24, 28), (24, 24, 28), (36, 44, 96), (232, 232, 232), (44, 112, 64), (210, 70, 60)])
    w, h = s * 1.5, s * 1.25
    d.ellipse([x - w / 2, y - h, x + w / 2, y], fill=color)
    d.polygon([(x - s * 0.18, y - h + 2), (x + s * 0.18, y - h + 2), (x + s * 0.05, y - h - s * 0.3)], fill=color)
    hi = lerp(color, (255, 255, 255), 0.35)
    d.ellipse([x - w * 0.25, y - h * 0.8, x - w * 0.05, y - h * 0.55], fill=hi)


def box(d, x, y, s, rng):
    w, h = s * 1.4, s * 0.9
    base = rng.choice([(168, 126, 76), (150, 112, 68), (190, 150, 98)])
    d.rectangle([x - w / 2, y - h, x + w / 2, y], fill=base)
    d.rectangle([x - w / 2, y - h, x + w / 2, y], outline=lerp(base, (0, 0, 0), 0.4), width=2)
    d.line([(x - w / 2, y - h * 0.55), (x + w / 2, y - h * 0.55)], fill=lerp(base, (255, 255, 255), 0.3), width=2)


def bottle(d, x, y, s, rng):
    color = rng.choice([(70, 150, 90), (200, 220, 230), (60, 110, 190), (170, 110, 60)])
    w, h = s * 0.38, s * 1.1
    d.rectangle([x - w / 2, y - h, x + w / 2, y], fill=color)
    d.rectangle([x - w * 0.22, y - h - s * 0.28, x + w * 0.22, y - h], fill=color)


def scrap(d, x, y, s, rng):
    c = rng.choice([(240, 240, 235), (225, 200, 80), (200, 60, 60), (70, 140, 210)])
    pts = [(x + rng.uniform(-s, s) * 0.5, y + rng.uniform(-s, 0) * 0.3) for _ in range(4)]
    d.polygon(pts, fill=c)


def can(d, x, y, s, rng):
    w, h = s * 0.45, s * 0.6
    d.rectangle([x - w / 2, y - h, x + w / 2, y], fill=rng.choice([(170, 170, 175), (190, 60, 50), (60, 120, 170)]))
    d.ellipse([x - w / 2, y - h - 2, x + w / 2, y - h + 3], fill=(205, 205, 210))


PIECES = [(bag, 5), (box, 2), (bottle, 3), (scrap, 3), (can, 2)]


def scene(severity, variant_seed):
    rng = random.Random(severity * 1000 + variant_seed)
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    background(d, rng)

    cx = W * rng.uniform(0.38, 0.62)
    cy = H * 0.80
    spread = SPREAD_BY_SEVERITY[severity]
    pieces = []
    for _ in range(ITEMS_BY_SEVERITY[severity]):
        x = min(max(rng.gauss(cx, spread), 20), W - 20)
        y = min(max(cy + rng.gauss(0, spread * 0.26), HORIZON + 14), H - 6)
        kind = rng.choices([p for p, _ in PIECES], weights=[w for _, w in PIECES])[0]
        pieces.append((y, kind, x))
    for y, kind, x in sorted(pieces, key=lambda p: p[0]):  # far items first
        scale = 12 + (y - HORIZON) / (H - HORIZON) * 30  # nearer items are bigger
        d.ellipse([x - scale * 0.8, y - 3, x + scale * 0.8, y + 4], fill=(70, 70, 68))  # shadow
        kind(d, x, y, scale, rng)

    img = img.filter(ImageFilter.GaussianBlur(0.7))
    noise = np.random.default_rng(severity * 1000 + variant_seed).normal(0, 4, (H, W, 3))
    arr = np.clip(np.asarray(img).astype(float) + noise, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for severity in range(1, 6):
        for i, variant in enumerate("abc"):
            path = OUT / f"severity-{severity}-{variant}.jpg"
            scene(severity, i + 1).save(path, "JPEG", quality=80)
            print(f"{path.name}: {path.stat().st_size} bytes")
