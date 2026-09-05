"""Every Mac icon, drawn from the same navigation ring the phone app uses.

The two platforms were drifting: Android carried the ring, the menubar carried
an unrelated television glyph, and the app icon was the phone's full-bleed
square — which on macOS reads as a foreign object next to properly shaped
icons. One drawing, rendered three ways, keeps it one product.
"""
import math, struct, zlib

GROUND_TOP = (0x0E, 0x14, 0x28)
GROUND_BOTTOM = (0x07, 0x0B, 0x16)
AMBER = (0xE9, 0xA9, 0x3F)

# Proportions of the ring on a 1024 grid, shared with the phone artwork.
R_OUTER, R_INNER, R_DOT, NOTCH = 300.0, 210.0, 118.0, 46.0

# Apple's icon grid: a 1024 canvas whose artwork sits in a centred 824 square,
# so the icon lines up with every other icon in the Dock.
PLATE = 824.0
SQUIRCLE_N = 5.0        # superellipse exponent, close to Apple's continuous corner


def ring_coverage(x, y, scale):
    """1 inside the glyph, 0 outside, for a point in 1024-grid coordinates."""
    d = math.hypot(x, y) / scale
    if d <= R_DOT:
        return True
    if R_INNER <= d <= R_OUTER:
        return not (abs(x / scale) < NOTCH or abs(y / scale) < NOTCH)
    return False


def png(path, width, height, raw):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    with open(path, "wb") as fh:
        fh.write(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b"")
        )


def app_icon(path, n=1024, s=3):
    """The rounded plate with the ring on it, ready for iconutil."""
    half, plate_half = n / 2.0, PLATE / 2.0 * n / 1024.0
    # The ring must keep the same share of the plate that it has of the phone
    # icon's full canvas. Drawing it at the design size on a smaller plate made
    # it too heavy, and widened the four gaps into visible wedges.
    scale = n / 1024.0 * (PLATE / 1024.0)
    rows = bytearray()
    for j in range(n):
        rows.append(0)
        for i in range(n):
            plate = glyph = 0.0
            for dj in range(s):
                for di in range(s):
                    x = i + (di + 0.5) / s - half
                    y = j + (dj + 0.5) / s - half
                    inside = (abs(x) / plate_half) ** SQUIRCLE_N + (abs(y) / plate_half) ** SQUIRCLE_N <= 1.0
                    if not inside:
                        continue
                    plate += 1.0
                    if ring_coverage(x, y, scale):
                        glyph += 1.0
            total = s * s
            a = plate / total
            if a == 0.0:
                rows += b"\0\0\0\0"
                continue
            # A gentle top-to-bottom shift gives the plate depth without turning
            # the icon into a gradient exercise.
            t = j / (n - 1)
            ground = tuple(
                round(top + (bottom - top) * t)
                for top, bottom in zip(GROUND_TOP, GROUND_BOTTOM)
            )
            g = glyph / total / a if a else 0.0
            rows += bytes(
                tuple(round(base + (amber - base) * g) for amber, base in zip(AMBER, ground))
                + (round(a * 255),)
            )
    png(path, n, n, rows)


def tray_icon(path, n, s=8):
    """Menubar template: black with alpha only, so macOS can tint it."""
    half = n / 2.0
    # The glyph fills the square rather than sitting in Apple's icon plate — a
    # menubar icon is a symbol, not an app tile.
    scale = n / 1024.0 * (1024.0 / (R_OUTER * 2.0)) * (n - 2.0) / n
    rows = bytearray()
    for j in range(n):
        rows.append(0)
        for i in range(n):
            acc = 0.0
            for dj in range(s):
                for di in range(s):
                    x = i + (di + 0.5) / s - half
                    y = j + (dj + 0.5) / s - half
                    if ring_coverage(x, y, scale):
                        acc += 1.0
            rows += bytes((0, 0, 0, round(acc / (s * s) * 255)))
    png(path, n, n, rows)


if __name__ == "__main__":
    for size, name in ((16, "trayTemplate.png"), (32, "trayTemplate@2x.png"), (48, "trayTemplate@3x.png")):
        tray_icon(f"assets/{name}", size)
        print(f"  ✓ assets/{name}")
    app_icon("assets/appicon-1024.png")
    print("  ✓ assets/appicon-1024.png")
