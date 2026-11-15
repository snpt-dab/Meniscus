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

    def poly(self, pts):
        # A filled polygon (for silhouettes, which read better than line
        # art at very small sizes).
        pts = list(pts)
        n = len(pts)
        def d(px, py):
            inside = False
            best = 1e9
            for i in range(n):
                ax, ay = pts[i]
                bx, by = pts[(i + 1) % n]
                best = min(best, seg_dist(px, py, ax, ay, bx, by))
                if (ay > py) != (by > py) and px < (bx - ax) * (py - ay) / (by - ay) + ax:
                    inside = not inside
            return -best if inside else best
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
    # a foaming mug: food and drink
    I['mug'] = (Icon().box(5.6, 8.6, 14.6, 19.6, rad=1.6, w=2.0)
                .arc(14.8, 13.8, 3.5, -78, 78, w=2.0)
                .dot(7.3, 7.4, 2.0).dot(10.1, 6.4, 2.2).dot(12.9, 7.4, 2.0))
    # ── who someone is: class, faction, race (player tooltips) ──
    # One plain emblem each, in the set's stroke: what the class is known
    # by, a banner shape for the faction, a sign for the race.
    import math as _m
    def rays(ic, cx, cy, r0, r1, n, w, turn=0.0):
        for i in range(n):
            a = turn + 2 * _m.pi * i / n
            ic.line([(cx + r0 * _m.cos(a), cy + r0 * _m.sin(a)), (cx + r1 * _m.cos(a), cy + r1 * _m.sin(a))], w=w)
        return ic
    # warrior: a sword
    I['class_warrior'] = Icon().line([(8.8, 15.2), (18.6, 5.4)], w=2.6).line([(6.2, 12.2), (11.8, 17.8)], w=2.4).dot(5.6, 18.4, 1.8)
    # paladin: a war hammer
    I['class_paladin'] = Icon().line([(12, 10.5), (12, 20)], w=2.6).box(6.2, 4.4, 17.8, 10.6, rad=1.6, fill=True)
    # hunter: a drawn bow
    I['class_hunter'] = (Icon().arc(5.6, 12, 8.8, -52, 52, w=2.3).line([(11, 5.1), (11, 18.9)], w=1.7)
                         .line([(5, 12), (19.6, 12)], w=2.0).line([(16.6, 9.2), (19.6, 12), (16.6, 14.8)], w=2.0))
    # rogue: a dagger, point down
    I['class_rogue'] = Icon().poly([(12, 20.4), (9.3, 10.2), (14.7, 10.2)]).line([(7.6, 9.6), (16.4, 9.6)], w=2.4).line([(12, 9), (12, 4.6)], w=2.6)
    # priest: a cross
    I['class_priest'] = Icon().line([(12, 4.6), (12, 19.8)], w=2.8).line([(7.2, 9.6), (16.8, 9.6)], w=2.8)
    # shaman: a bolt of lightning
    I['class_shaman'] = Icon().poly([(14, 3.8), (7, 13.2), (11.4, 13.2), (9.8, 20.4), (17.2, 10.4), (12.8, 10.4)])
    # mage: a six-pointed spark
    I['class_mage'] = rays(Icon().dot(12, 12, 1.9), 12, 12, 2.6, 8.0, 6, 2.2, turn=_m.pi / 2)
    # warlock: a flame
    I['class_warlock'] = Icon().line([(12, 3.8), (16.4, 10.6), (17.2, 15), (14.6, 19.2), (9.4, 19.2), (6.8, 15), (8.2, 10.4), (10.6, 12.8)], w=2.2, close=True)
    # druid: a paw print
    I['class_druid'] = Icon().dot(12, 15.4, 3.8).dot(6.6, 11.2, 1.9).dot(10, 7.2, 1.9).dot(14, 7.2, 1.9).dot(17.4, 11.2, 1.9)
    # monk, death knight, demon hunter, evoker (should the client have them): a plain ring
    I['class_other'] = Icon().ring(12, 12, 6.2)
    # Alliance: a shield.  Horde: a swallow-tailed banner.
    I['faction_alliance'] = Icon().line([(6, 5.2), (18, 5.2), (18, 12.4), (12, 20), (6, 12.4)], w=2.3, close=True)
    I['faction_horde'] = Icon().line([(7, 4.6), (17, 4.6), (17, 19.6), (12, 14.8), (7, 19.6)], w=2.3, close=True)
    # races
    I['race_human'] = Icon().line([(5, 17.4), (5, 8.2), (8.6, 12.2), (12, 6.4), (15.4, 12.2), (19, 8.2), (19, 17.4)], w=2.2, close=True)   # a crown
    I['race_dwarf'] = Icon().poly([(4.2, 8.6), (19.8, 8.6), (19.8, 11.8), (15.2, 12.6), (14.4, 15.6), (17.4, 15.6),
                                  (17.4, 19.6), (6.6, 19.6), (6.6, 15.6), (9.6, 15.6), (8.8, 12.6), (4.2, 11.4)])       # an anvil
    I['race_nightelf'] = Icon().arc(12.6, 12, 6.6, 55, 305, w=2.6)                                                                         # a crescent moon
    I['race_gnome'] = rays(Icon().ring(12, 12, 3.8, w=2.2), 12, 12, 6.0, 8.2, 6, 3.0)                                                      # a cog
    I['race_orc'] = (Icon().line([(12, 4.4), (12, 20)], w=2.4)                                                                             # a two-bladed axe
                     .poly([(12, 6.2), (5.8, 4.6), (6.8, 9.4), (5.8, 13.8), (12, 12.2)])
                     .poly([(12, 6.2), (18.2, 4.6), (17.2, 9.4), (18.2, 13.8), (12, 12.2)]))
    I['race_scourge'] = Icon().ring(12, 10.4, 5.4, w=2.2).box(9, 13.4, 15, 19, rad=1.2, w=2.0).dot(10, 10.6, 1.25).dot(14, 10.6, 1.25)     # a skull
    I['race_tauren'] = Icon().arc(12, 6.4, 7.2, 180, 360, w=2.6).ring(12, 17.6, 2.0, w=1.9)                                               # horns and a nose ring
    I['race_troll'] = (Icon().line([(6.2, 4.8), (17.8, 4.8), (12, 17.4)], w=2.2, close=True)                                # a tusked mask
                       .line([(8.8, 8.6), (11, 9.8)], w=1.9).line([(15.2, 8.6), (13, 9.8)], w=1.9)
                       .line([(8.2, 14.6), (6.4, 19.8)], w=2.0).line([(15.8, 14.6), (17.6, 19.8)], w=2.0))
    I['race_bloodelf'] = (Icon().line([(4.2, 10.4), (8.6, 6.4), (12, 11.2), (15.4, 6.4), (19.8, 10.4)], w=2.3)             # a phoenix
                          .dot(12, 7.6, 1.5).line([(12, 11.2), (12, 16.4)], w=2.3)
                          .line([(12, 16.4), (8.8, 20.2)], w=1.8).line([(12, 16.4), (12, 20.6)], w=1.8).line([(12, 16.4), (15.2, 20.2)], w=1.8))
    I['race_draenei'] = Icon().line([(12, 3.8), (18, 10.6), (12, 20.2), (6, 10.6)], w=2.2, close=True).line([(6, 10.6), (18, 10.6)], w=1.7)  # a crystal
    I['race_other'] = Icon().ring(12, 9, 3.6).arc(12, 22, 7.0, 25, 155)                                                                     # head and shoulders

    # ── character stats page ──
    # strength: a flexed arm, in outline: the fist curled in at the top, the bicep's swell at the right
    def fit(pts, k=0.86):
        return [(12 + (x - 12) * k, 12 + (y - 12) * k) for x, y in pts]
    I['stat_str'] = (Icon()
        .line(fit([(12.4, 13.0), (13.5, 11.2), (15.5, 10.2), (17.6, 10.1), (19.8, 11.0), (21.4, 12.8), (22, 15),
                   (21.2, 17.8), (19, 20), (16, 21.5), (13, 22), (8.5, 21.6), (4.8, 20.6), (2.6, 19.5), (2.0, 18.2),
                   (2.2, 13), (3.2, 8), (5.2, 4.4), (7.6, 2.6), (10, 2), (12, 2.8), (13, 5), (12.4, 6.4), (11, 7),
                   (9.6, 6.7), (9, 6)]), w=1.9)
        .line(fit([(15, 14), (13, 12.9), (10.5, 13.2), (8.5, 14.4), (7.4, 16)]), w=1.7)
        .line(fit([(9.96, 6.8), (9.0, 8.5), (9.2, 11.5), (8.7, 13.5), (8, 15)]), w=1.7))
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
    # A potion: a round flask with a short neck and a lip.
    I['potion'] = (Icon().arc(12, 14.6, 5.3, 110, 430)
                   .line([(10.2, 9.7), (10.2, 5.6)]).line([(13.8, 9.7), (13.8, 5.6)])
                   .line([(8.9, 4.9), (15.1, 4.9)], w=2.0))
    # The group finder's eye: the two lids only (the pupil is drawn in game,
    # so it can look about).
    I['eye'] = Icon().arc(12, 15.9, 8.9, 26, 154, w=2.0).arc(12, 8.1, 8.9, 206, 334, w=2.0)
    # A remembered gathering node on the world map: a dot in a thin ring.
    I['node'] = Icon().dot(12, 12, 3.4).ring(12, 12, 8.6, w=1.6)
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
