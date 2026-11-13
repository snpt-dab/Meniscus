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
    # ── marks used outside the micro menu (heavier: drawn at 10-12 px) ──
    # up arrow: "better than what you wear"
    I['up'] = Icon().line([(5.5, 12.5), (12, 6), (18.5, 12.5)], w=3.6).line([(12, 7), (12, 19)], w=3.6)
    # wrench: gear needs repair
    I['repair'] = Icon().arc(8.6, 8.6, 4.0, 180, 450, w=3.0).line([(11.4, 11.4), (18.6, 18.6)], w=3.4)
    # envelope: mail waiting
    I['mail'] = Icon().box(4.2, 6.6, 19.8, 17.4, rad=2).line([(5.2, 8.2), (12, 13.2), (18.8, 8.2)], w=2.0)
    # speech bubble: a whisper you haven't answered
    I['chat'] = Icon().box(4.2, 5, 19.8, 15.6, rad=3.2).line([(8.4, 15.6), (8.4, 19.6), (12.6, 15.6)], w=2.0)
    # arrowhead (points up; turned in game): the way to your corpse
    I['pointer'] = Icon().line([(12, 4.6), (18.2, 18.6), (12, 15.2), (5.8, 18.6)], w=2.6, close=True)
    # star burst: a self-buff has dropped
    I['buff'] = Icon().line([(12, 4.4), (14.2, 9.8), (19.6, 12), (14.2, 14.2), (12, 19.6), (9.8, 14.2), (4.4, 12), (9.8, 9.8)], w=2.2, close=True)
    # drumstick: pet food
    I['food'] = Icon().dot(9.6, 9.6, 4.6).line([(12.6, 12.6), (18.2, 18.2)], w=2.6).dot(18.6, 18.6, 1.8)
    # ── character stats page ──
    # strength: a flexed arm (upper arm, forearm up to a fist, the bicep's bulge)
    I['stat_str'] = (Icon().line([(20, 18.2), (9, 18.2), (9, 9.6)], w=2.6)
                     .box(6.2, 4.4, 12.6, 9.8, rad=2.2, fill=True)
                     .arc(14.6, 18.2, 4.7, 0, 180, w=2.5))
    # agility: a bolt
    I['stat_agi'] = Icon().line([(13.4, 4.6), (7.4, 13.2), (11.8, 13.2), (10.6, 19.4), (16.6, 10.8), (12.2, 10.8)], w=2.1, close=True)
    # stamina: a heart
    heart = []
    for i in range(40):
        t = 2 * math.pi * i / 40
        hx = 16 * math.sin(t) ** 3
        hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        heart.append((12 + hx * 0.44, 11.4 - hy * 0.44))
    I['stat_sta'] = Icon().line(heart, w=2.2, close=True)
    # intellect: a lit bulb
    I['stat_int'] = Icon().ring(12, 10, 5.2).line([(9.8, 17.4), (14.2, 17.4)], w=2.2).line([(10.6, 20), (13.4, 20)], w=2.0)
    # spirit: a four-point spark
    I['stat_spi'] = Icon().line([(12, 4.4), (14.2, 9.8), (19.6, 12), (14.2, 14.2), (12, 19.6), (9.8, 14.2), (4.4, 12), (9.8, 9.8)], w=2.2, close=True)
    # fire: a flame
    I['stat_fire'] = Icon().line([(12, 4.4), (15.6, 9), (17.2, 13.6), (15.8, 17.4), (12, 19.4), (8.2, 17.4), (6.8, 13.6), (8.8, 10.2), (10.6, 12.2)], w=2.2, close=True)
    # nature: a leaf with its vein
    I['stat_nature'] = (Icon().line([(5.4, 18.6), (5.8, 11.2), (10.8, 6), (18.6, 5.4), (18, 13.2), (12.8, 18.2)], w=2.2, close=True)
                        .line([(5.4, 18.6), (13.4, 10.6)], w=2.0))
    # frost: a six-armed flake
    flake = Icon()
    for ang in (90, 30, 150):
        a = math.radians(ang)
        dx, dy = 7.4 * math.cos(a), 7.4 * math.sin(a)
        flake.line([(12 - dx, 12 + dy), (12 + dx, 12 - dy)], w=2.1)
    I['stat_frost'] = flake.dot(12, 12, 1.6)
    # shadow: a crescent moon
    I['stat_shadow'] = Icon().arc(11.4, 12, 7.2, 62, 298, w=2.3).arc(16.2, 12, 6.2, 118, 242, w=2.3)
    # arcane: a five-point star
    star = []
    for i in range(10):
        a = math.radians(90 + i * 36)
        r = 7.8 if i % 2 == 0 else 3.4
        star.append((12 + r * math.cos(a), 12.6 - r * math.sin(a)))
    I['stat_arcane'] = Icon().line(star, w=2.0, close=True)
    # melee: a sword (blade, guard, pommel)
    I['stat_melee'] = Icon().line([(8.6, 15.4), (18.6, 5.4)], w=2.5).line([(6.4, 12.4), (11.6, 17.6)], w=2.3).dot(5.8, 18.2, 1.7)
    # ranged: a bow, its string, an arrow
    I['stat_ranged'] = (Icon().arc(5.6, 12, 8.8, -52, 52, w=2.3).line([(11, 5.1), (11, 18.9)], w=1.7)
                        .line([(5, 12), (19.6, 12)], w=2.0).line([(16.6, 9.2), (19.6, 12), (16.6, 14.8)], w=2.0))
    # spell: a wand and a spark at its tip
    I['stat_spell'] = (Icon().line([(5.6, 18.4), (14.2, 9.8)], w=2.6)
                       .line([(17.4, 3.8), (17.4, 9.6)], w=1.9).line([(14.5, 6.7), (20.3, 6.7)], w=1.9))
    # defense: a shield
    I['stat_defense'] = Icon().line([(6, 5.2), (18, 5.2), (18, 12), (12, 19), (6, 12)], close=True)
    # resistances: a halved shield
    I['stat_resist'] = Icon().line([(6, 5.2), (18, 5.2), (18, 12), (12, 19), (6, 12)], close=True).line([(12, 5.2), (12, 19)], w=2.0)
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
