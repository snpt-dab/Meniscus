# Draws the micro menu icons as vector shapes and writes them as textures:
#   python dist/icons.py        (run from the addon folder)
# Each icon is described on a 24 x 24 grid (x right, y down) with strokes that
# have round ends and joins, rings, dots and rounded boxes. They are
# rasterized from exact distances to the shapes, so every edge is smoothly
# anti-aliased, into Media/micro_<name>.tga: white, with the shape in the
# alpha channel (the format the game's SetTexture + SetVertexColor want, as
# Media/rounded.tga). New texture files need a full game restart to be seen.
import math, os, struct

GRID = 24.0
SIZE = 32          # texture is SIZE x SIZE pixels
STROKE = 2.3       # default stroke width, in grid units


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    L = vx * vx + vy * vy
    t = 0.0 if L == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / L))
    return math.hypot(px - (ax + t * vx), py - (ay + t * vy))


def arc_points(cx, cy, r, a0, a1, n=20):
    # Angles in degrees, 0 = right, 90 = up (screen y is down).
    pts = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        pts.append((cx + r * math.cos(a), cy - r * math.sin(a)))
    return pts


class Icon:
    def __init__(self):
        self.shapes = []   # each: function(px, py) -> signed distance (grid units, <0 inside)

    def line(self, pts, w=STROKE, close=False):
        pts = list(pts)
        if close:
            pts.append(pts[0])
        def d(px, py, pts=pts, w=w):
            return min(seg_dist(px, py, *pts[i], *pts[i + 1]) for i in range(len(pts) - 1)) - w / 2
        self.shapes.append(d)
        return self

    def ring(self, cx, cy, r, w=STROKE):
        self.shapes.append(lambda px, py: abs(math.hypot(px - cx, py - cy) - r) - w / 2)
        return self

    def dot(self, cx, cy, r):
        self.shapes.append(lambda px, py: math.hypot(px - cx, py - cy) - r)
        return self

    def box(self, x0, y0, x1, y1, rad=2.0, w=STROKE, fill=False):
        cx, cy, hx, hy = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 - rad, (y1 - y0) / 2 - rad
        def d(px, py):
            qx, qy = abs(px - cx) - hx, abs(py - cy) - hy
            sd = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - rad
            return sd if fill else abs(sd) - w / 2
        self.shapes.append(d)
        return self

    def arc(self, cx, cy, r, a0, a1, w=STROKE):
        return self.line(arc_points(cx, cy, r, a0, a1), w)

    def render(self):
        k = SIZE / GRID
        out = bytearray()
        for y in range(SIZE):
            for x in range(SIZE):
                # 3 x 3 sub-samples of the exact coverage.
                a = 0.0
                for sy in (-1 / 3, 0, 1 / 3):
                    for sx in (-1 / 3, 0, 1 / 3):
                        gx, gy = (x + 0.5 + sx) / k, (y + 0.5 + sy) / k
                        dist = min(s(gx, gy) for s in self.shapes) * k   # in pixels
                        a += max(0.0, min(1.0, 0.5 - dist))
                out += bytes([255, 255, 255, int(round(a / 9 * 255))])
        return bytes(out)


def icons():
    # Every icon is drawn inside the same 16 x 16 "live area" in the middle of
    # the 24 x 24 grid (4..20 on both axes) and with the same stroke, so they
    # read as one set: equal weight, equal apparent size, equal gaps between
    # neighbours. The 4-unit margin all round is the breathing room.
    I = {}
    # head and shoulders
    I['character'] = Icon().ring(12, 8.2, 3.2).arc(12, 21.5, 7.0, 25, 155)
    # hammer: a handle and a heavy head set across it
    I['profession'] = Icon().line([(6.5, 19), (12.5, 13)]).line([(10.5, 7.5), (16.5, 13.5)], w=4.6)
    # open book
    I['spell'] = Icon().box(4.5, 6.5, 19.5, 17.5, rad=2).line([(12, 6.5), (12, 17.5)])
    # three linked points (same stroke as everything else)
    I['talent'] = (Icon().dot(12, 6.5, 2.7).dot(6.2, 17.3, 2.7).dot(17.8, 17.3, 2.7)
                   .line([(12, 6.5), (6.2, 17.3), (17.8, 17.3)], close=True))
    # diamond
    I['achievement'] = Icon().line([(12, 4.8), (19.2, 12), (12, 19.2), (4.8, 12)], close=True)
    # shield
    I['legacy'] = Icon().line([(6, 5.2), (18, 5.2), (18, 12), (12, 19), (6, 12)], close=True)
    # exclamation mark
    I['quest'] = Icon().line([(12, 5.2), (12, 14)], w=2.8).dot(12, 18.6, 1.7)
    # flag on a pole
    I['guild'] = Icon().line([(8, 4.8), (8, 19.4)]).line([(8, 5.8), (17.4, 5.8), (17.4, 12), (8, 12)])
    # two heads over a line
    I['group'] = Icon().ring(8.2, 9.6, 2.9).ring(15.8, 9.6, 2.9).line([(5.2, 18), (18.8, 18)])
    # four tiles
    I['collection'] = (Icon().box(5, 5, 11, 11, 1.5, fill=True).box(13, 5, 19, 11, 1.5, fill=True)
                       .box(5, 13, 11, 19, 1.5, fill=True).box(13, 13, 19, 19, 1.5, fill=True))
    # compass
    I['journal'] = Icon().ring(12, 12, 7.0).line([(9.6, 14.4), (14.4, 9.6)], w=3.0)
    # bag with a handle
    I['store'] = Icon().box(6, 10, 18, 19.4, rad=2).arc(12, 10, 3.4, 0, 180)
    # three bars
    I['mainmenu'] = Icon().line([(6, 7.4), (18, 7.4)]).line([(6, 12), (18, 12)]).line([(6, 16.6), (18, 16.6)])
    # question mark: a hook, a stem, a dot
    hook = arc_points(12, 9, 3.8, 180, -45, 24) + [(12, 14.6)]
    I['help'] = Icon().line(hook, w=2.5).dot(12, 18.8, 1.7)
    return I


def main():
    os.makedirs('Media', exist_ok=True)
    header = bytes([0, 0, 2]) + bytes(9) + struct.pack('<HHBB', SIZE, SIZE, 32, 40)
    for name, icon in icons().items():
        path = os.path.join('Media', 'micro_%s.tga' % name)
        open(path, 'wb').write(header + icon.render())
        print(path)


if __name__ == '__main__':
    main()
