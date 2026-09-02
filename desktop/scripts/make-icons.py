"""Generate the menubar template icon. Pure stdlib: a 4x supersampled TV glyph
encoded straight to PNG, so the build needs no image toolchain."""
import zlib, struct, math

def rounded_rect(x, y, w, h, r, px, py, t):
    """Signed distance from a rounded-rect outline of thickness t."""
    cx, cy = abs(px - (x + w / 2)) - (w / 2 - r), abs(py - (y + h / 2)) - (h / 2 - r)
    d = math.hypot(max(cx, 0), max(cy, 0)) + min(max(cx, cy), 0) - r
    return abs(d) - t / 2

def segment(ax, ay, bx, by, px, py, t):
    vx, vy = bx - ax, by - ay
    L = vx * vx + vy * vy
    u = 0 if L == 0 else max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / L))
    return math.hypot(px - (ax + u * vx), py - (ay + u * vy)) - t / 2

def render(size):
    S, s = 4, size          # supersample factor
    N = size * S
    k = N / 22.0            # design grid is 22pt
    cov = [[0.0] * N for _ in range(N)]
    for j in range(N):
        for i in range(N):
            px, py = (i + 0.5) / k, (j + 0.5) / k
            d = min(
                rounded_rect(2.0, 7.0, 18.0, 12.0, 2.6, px, py, 1.7),   # screen
                segment(7.5, 3.0, 10.6, 6.6, px, py, 1.6),              # left antenna
                segment(14.5, 3.0, 11.4, 6.6, px, py, 1.6),             # right antenna
            )
            cov[j][i] = 1.0 if d <= 0 else 0.0

    rows = bytearray()
    for j in range(s):
        rows.append(0)
        for i in range(s):
            a = sum(cov[j * S + dj][i * S + di] for dj in range(S) for di in range(S)) / (S * S)
            rows += bytes((0, 0, 0, round(a * 255)))
    return bytes(rows), s

def png(path, raw, size):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    out = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(out)

for size, name in ((22, "assets/trayTemplate.png"), (44, "assets/trayTemplate@2x.png"), (66, "assets/trayTemplate@3x.png")):
    raw, s = render(size)
    png(name, raw, s)
    print(f"  {name}  {size}×{size}")
