"""Placeholder launcher icon: the navigation ring from the app's own design.

A stand-in until artwork is produced (see docs/ICONS.md). Drawn rather than
downloaded so the repository carries no unattributed image.
"""
import math, struct, zlib

S = 4          # supersampling
N = 1024
GROUND = (0x0B, 0x10, 0x20)
AMBER = (0xE9, 0xA9, 0x3F)

def render(transparent):
    px = N * S
    rows = bytearray()
    # Design grid is 1024; the subject stays inside the middle ~62% so that
    # Android's adaptive-icon crop cannot reach it.
    cx = cy = 512.0
    r_outer, r_inner = 300.0, 210.0   # the ring
    r_dot = 118.0                      # the OK button
    notch_half = 46.0                  # gaps at the four compass points

    for j in range(N):
        rows.append(0)
        for i in range(N):
            acc = 0.0
            for dj in range(S):
                for di in range(S):
                    x = (i + (di + 0.5) / S) * 1024.0 / N - cx
                    y = (j + (dj + 0.5) / S) * 1024.0 / N - cy
                    d = math.hypot(x, y)
                    on = False
                    if d <= r_dot:
                        on = True
                    elif r_inner <= d <= r_outer:
                        # carve a gap where each arrow would sit
                        on = not (abs(x) < notch_half or abs(y) < notch_half)
                    acc += 1.0 if on else 0.0
            a = acc / (S * S)
            if transparent:
                rows += bytes((*AMBER, round(a * 255)))
            else:
                rows += bytes(tuple(round(g + (c - g) * a) for c, g in zip(AMBER, GROUND)) + (255,))
    return bytes(rows)

def png(path, raw):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )

png("assets/icon/icon_foreground.png", render(transparent=True))
png("assets/icon/icon.png", render(transparent=False))
print("נוצרו assets/icon/icon.png ו-icon_foreground.png")
