#!/usr/bin/env python3
"""Draws the Nori app icon (a rounded dark tile with a clipboard glyph) and writes a multi-size .ico.

No third-party modules: pixels are rasterised by hand, 16/32/48 are stored as BMP entries and 256 as PNG.
Usage: python3 scripts/make_icon.py windows/Nori.Windows/Assets/nori.ico
"""
import math
import struct
import sys
import zlib


def blend(dst, src, a):
    return tuple(int(round(d * (1 - a) + s * a)) for d, s in zip(dst, src))


def rounded_rect_coverage(x, y, x0, y0, x1, y1, r):
    """Anti-aliased coverage of pixel (x, y) by a rounded rectangle, sampled 4x4."""
    hits = 0
    for sy in range(4):
        for sx in range(4):
            px = x + (sx + 0.5) / 4
            py = y + (sy + 0.5) / 4
            if px < x0 or px > x1 or py < y0 or py > y1:
                continue
            cx = min(max(px, x0 + r), x1 - r)
            cy = min(max(py, y0 + r), y1 - r)
            if (px - cx) ** 2 + (py - cy) ** 2 <= r * r:
                hits += 1
    return hits / 16


def render(size):
    """Returns rows of RGBA tuples (top-down)."""
    s = size
    tile_r = s * 0.22
    pixels = []
    for y in range(s):
        row = []
        for x in range(s):
            t = y / s
            base = blend((0x5E, 0x5C, 0xE6), (0x3B, 0x39, 0xB8), t)  # indigo gradient
            cov = rounded_rect_coverage(x, y, s * 0.03, s * 0.03, s * 0.97, s * 0.97, tile_r)
            color = base
            alpha = cov
            # Clipboard body: white rounded rectangle.
            body = rounded_rect_coverage(x, y, s * 0.26, s * 0.24, s * 0.74, s * 0.84, s * 0.07)
            color = blend(color, (0xFF, 0xFF, 0xFF), body * 0.96)
            # Clip at the top: a small dark rounded bar.
            clip = rounded_rect_coverage(x, y, s * 0.40, s * 0.17, s * 0.60, s * 0.30, s * 0.05)
            color = blend(color, (0x2A, 0x28, 0x7A), clip)
            # Three "text lines" on the sheet.
            for i, w in enumerate((0.30, 0.22, 0.26)):
                ly = s * (0.42 + i * 0.13)
                line = rounded_rect_coverage(x, y, s * 0.34, ly, s * (0.34 + w), ly + s * 0.06, s * 0.03)
                color = blend(color, (0x5E, 0x5C, 0xE6), line * 0.85)
            row.append((color[0], color[1], color[2], int(round(alpha * 255))))
        pixels.append(row)
    return pixels


def png_bytes(pixels):
    size = len(pixels)
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def bmp_bytes(pixels):
    """32-bit BGRA DIB with an empty AND mask, bottom-up, as ICO expects."""
    size = len(pixels)
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, size * size * 4, 0, 0, 0, 0)
    body = bytearray()
    for row in reversed(pixels):
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    mask_row = ((size + 31) // 32) * 4
    return header + bytes(body) + bytes(mask_row * size)


def main(path):
    entries = []
    for size in (16, 32, 48):
        entries.append((size, bmp_bytes(render(size))))
    entries.append((256, png_bytes(render(256))))
    out = bytearray(struct.pack("<HHH", 0, 1, len(entries)))
    offset = 6 + 16 * len(entries)
    blobs = bytearray()
    for size, data in entries:
        dim = 0 if size == 256 else size
        out += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset + len(blobs))
        blobs += data
    with open(path, "wb") as f:
        f.write(out + blobs)
    print(f"wrote {path} ({len(out) + len(blobs)} bytes)")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "nori.ico")
