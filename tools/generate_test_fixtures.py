#!/usr/bin/env python3
"""Generates the image fixtures used by the Rails test suite (api-overlay/test/fixtures/files).

Needs Pillow and numpy. The fixtures are committed, so you only run this to regenerate them:

    python3 tools/generate_test_fixtures.py

EXIF blocks are built by hand (instead of with a library) so we control byte order and
exact values. The noise images are deliberately high-frequency so the tests can tell a
redacted (mosaic) region from an untouched one by comparing standard deviation.
"""
import io
import pathlib
import struct

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "api-overlay" / "test" / "fixtures" / "files"

ASCII, SHORT, LONG, RATIONAL = 2, 3, 4, 5
TYPE_SIZE = {ASCII: 1, SHORT: 2, LONG: 4, RATIONAL: 8}


def noise_image(width, height, seed):
    rng = np.random.default_rng(seed)
    return Image.fromarray(rng.integers(0, 256, (height, width, 3), dtype=np.uint8), "RGB")


def jpeg_bytes(image, quality=85):
    buf = io.BytesIO()
    image.save(buf, "JPEG", quality=quality)
    return buf.getvalue()


def dms(value):
    """Decimal degrees -> [(deg,1),(min,1),(sec*100,100)] rationals."""
    value = abs(value)
    degrees = int(value)
    minutes = int((value - degrees) * 60)
    seconds = round(((value - degrees) * 60 - minutes) * 60 * 100)
    return [(degrees, 1), (minutes, 1), (seconds, 100)]


def encode_entry_data(endian, kind, values):
    e = "<" if endian == "II" else ">"
    if kind == ASCII:
        return values.encode("ascii") + b"\0", len(values) + 1
    if kind == SHORT:
        return b"".join(struct.pack(e + "H", v) for v in values), len(values)
    if kind == LONG:
        return b"".join(struct.pack(e + "L", v) for v in values), len(values)
    if kind == RATIONAL:
        return b"".join(struct.pack(e + "LL", n, d) for n, d in values), len(values)
    raise ValueError(kind)


def build_ifd(endian, entries, start_offset, pointers):
    """entries: list of (tag, kind, values) sorted by tag. kind 'ptr' = LONG taken from `pointers`.
    Returns (table_bytes, data_bytes) assuming the table is placed at start_offset."""
    e = "<" if endian == "II" else ">"
    table_size = 2 + 12 * len(entries) + 4
    data = b""
    table = struct.pack(e + "H", len(entries))
    for tag, kind, values in entries:
        if kind == "ptr":
            kind, values = LONG, [pointers[values]]
        raw, count = encode_entry_data(endian, kind, values)
        if len(raw) <= 4:
            inline = raw.ljust(4, b"\0")
        else:
            inline = struct.pack(e + "L", start_offset + table_size + len(data))
            data += raw + (b"\0" if len(raw) % 2 else b"")
        table += struct.pack(e + "HHL", tag, kind, count) + inline
    table += struct.pack(e + "L", 0)  # no next IFD
    return table, data


def build_tiff(endian, ifd0, exif, gps):
    e = "<" if endian == "II" else ">"
    header = endian.encode() + struct.pack(e + "HL", 42, 8)

    def layout(pointers):
        blobs, offset = [], 8
        for entries in (ifd0, exif, gps):
            table, data = build_ifd(endian, entries, offset, pointers)
            blobs.append((offset, table + data))
            offset += len(table) + len(data)
        return blobs

    blobs = layout({"exif": 0, "gps": 0})  # first pass only to learn the offsets
    pointers = {"exif": blobs[1][0], "gps": blobs[2][0]}
    blobs = layout(pointers)
    return header + b"".join(blob for _, blob in blobs)


def exif_block(endian, lat, lng, taken, make="FakeCam", model="PhotoPhone 9", orientation=1):
    ifd0 = sorted([
        (0x010F, ASCII, make),
        (0x0110, ASCII, model),
        (0x0112, SHORT, [orientation]),
        (0x8769, "ptr", "exif"),
        (0x8825, "ptr", "gps"),
    ])
    exif = [(0x9003, ASCII, taken)]
    gps = [
        (1, ASCII, "N" if lat >= 0 else "S"),
        (2, RATIONAL, dms(lat)),
        (3, ASCII, "E" if lng >= 0 else "W"),
        (4, RATIONAL, dms(lng)),
    ]
    return build_tiff(endian, ifd0, exif, gps)


def with_exif(jpeg, tiff):
    payload = b"Exif\0\0" + tiff
    app1 = b"\xff\xe1" + struct.pack(">H", len(payload) + 2) + payload
    pos = 2
    if jpeg[2:4] == b"\xff\xe0":  # keep JFIF (APP0) first
        pos = 4 + struct.unpack(">H", jpeg[4:6])[0]
    return jpeg[:pos] + app1 + jpeg[pos:]


def write(name, data):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_bytes(data)
    print(f"{name}: {len(data)} bytes")


if __name__ == "__main__":
    BRASILIA = (-15.7942, -47.8825)

    # No metadata at all, tiny.
    gradient = np.tile(np.linspace(0, 255, 64, dtype=np.uint8), (48, 1))
    write("plain.jpg", jpeg_bytes(Image.fromarray(np.stack([gradient] * 3, axis=2), "RGB")))

    # 200x150 noise with camera info, capture time and GPS (little endian, like most Androids).
    noisy = jpeg_bytes(noise_image(200, 150, seed=1))
    write("exif_gps.jpg", with_exif(noisy, exif_block("II", *BRASILIA, "2026:10:20 14:30:00")))

    # Same data, big endian (like iPhones), tiny.
    tiny = jpeg_bytes(noise_image(40, 30, seed=2))
    write("exif_gps_bigendian.jpg", with_exif(tiny, exif_block("MM", 40.7128, -74.0060, "2025:01:02 03:04:05")))

    # Stored 120x80 (landscape) with Orientation=6: displays rotated 90 degrees, i.e. 80x120.
    sideways = jpeg_bytes(noise_image(120, 80, seed=3))
    write("exif_rotated.jpg", with_exif(sideways, exif_block("II", *BRASILIA, "2026:10:20 14:30:00", orientation=6)))

    # Looks like a JPEG (right magic bytes, so it passes upload checks) but cannot be decoded.
    write("corrupt.jpg", b"\xff\xd8\xff\xe0" + b"this is not really a jpeg")

    # Not an image: a minimal PDF.
    write("not_an_image.pdf", b"%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n")
