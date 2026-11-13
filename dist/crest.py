# Draws the target portrait's "crest" for elite / rare / boss units:
#   python dist/crest.py        (run from the addon folder)
# A thin ring that sits just outside the portrait's own ring, and the
# ornaments that go with it, each in its own texture so the game can tint
# and animate them separately. White, shape in the alpha channel, 128 x 128.
# Geometry is in units of the texture's half-size (centre 0,0; edge 1.0):
# the ring's outer edge is at RING_R, ornaments reach out to about 0.98.
# UnitFrames.lua sizes the crest frame from RING_R, so keep them in step.
# New texture files need a full game restart to be seen.
import math, os, struct

SIZE = 128
SS = 4                      # sub-samples per axis
RING_R, RING_W = 0.80, 0.055


def ring(x, y):
    r = math.hypot(x, y)
    return RING_R - RING_W <= r <= RING_R


def polar(x, y):
    # angle in degrees, 0 = right, 90 = up (texture y runs down)
    return math.hypot(x, y), math.degrees(math.atan2(-y, x))


def diamond_at(x, y, ang, rad, half_r, half_t):
    # A diamond centred at (rad, ang), long axis pointing outward.
    a = math.radians(ang)
    cx, cy = rad * math.cos(a), -rad * math.sin(a)
    dx, dy = x - cx, y - cy
    # radial / tangential components
    ur, ut = dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a)
    return abs(ur) / half_r + abs(ut) / half_t <= 1.0


def studs(x, y):
    # elite: four studs flanking the top (the label sits at the very top)
    return any(diamond_at(x, y, a, RING_R + 0.065, 0.105, 0.062) for a in (90 - 68, 90 - 42, 90 + 42, 90 + 68))


def star_at(x, y, ang, rad, arm):
    a = math.radians(ang)
    cx, cy = rad * math.cos(a), -rad * math.sin(a)
    dx, dy = abs(x - cx), abs(y - cy)
    # four-point star (astroid)
    return dx ** (2 / 3) + dy ** (2 / 3) <= arm ** (2 / 3)


def stars(x, y):
    # rare: a star either side of the top, and a small one lower on each side
    return (star_at(x, y, 90 - 48, RING_R + 0.03, 0.17) or star_at(x, y, 90 + 48, RING_R + 0.03, 0.17)
            or star_at(x, y, 90 - 82, RING_R + 0.05, 0.10) or star_at(x, y, 90 + 82, RING_R + 0.05, 0.10))


def spikes(x, y):
    # boss: sixteen spikes all the way round
    r, ang = polar(x, y)
    n, height, half = 16, 0.18, 7.0
    step = 360.0 / n
    off = (ang + step / 2) % step - step / 2      # angle from the nearest spike's axis
    if abs(off) > half:
        return False
    return RING_R - 0.01 <= r <= RING_R + height * (1 - abs(off) / half)


def render(inside):
    out = bytearray()
    for py in range(SIZE):
        for px in range(SIZE):
            hit = 0
            for sy in range(SS):
                for sx in range(SS):
                    x = ((px + (sx + 0.5) / SS) / SIZE) * 2 - 1
                    y = ((py + (sy + 0.5) / SS) / SIZE) * 2 - 1
                    if inside(x, y):
                        hit += 1
            out += bytes([255, 255, 255, int(round(hit * 255 / (SS * SS)))])
    return bytes(out)


def main():
    os.makedirs('Media', exist_ok=True)
    header = bytes([0, 0, 2]) + bytes(9) + struct.pack('<HHBB', SIZE, SIZE, 32, 40)
    for name, fn in (('ring', ring), ('studs', studs), ('stars', stars), ('spikes', spikes)):
        path = os.path.join('Media', 'crest_%s.tga' % name)
        open(path, 'wb').write(header + render(fn))
        print(path)


if __name__ == '__main__':
    main()
