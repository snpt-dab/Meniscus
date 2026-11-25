# Draws the smoke puffs the Quick Cure pill gives off for a disease, and
# writes them as textures:
#   python dist/smoke.py        (run from the addon folder)
# Each puff is a billow: several soft round lobes run together, a little
# uneven inside, fading to nothing well before the texture's edge. White,
# with the shape in the alpha channel (the game tints it), as the icons
# are. Four of them, so that a cloud of puffs is not one shape repeated.
# Media/smoke1.tga .. smoke4.tga. New texture files need only a /reload.
import math, os, random, struct

SIZE = 96


def _lerp(a, b, t):
    return a + (b - a) * t


def _noise_grid(rng, n):
    return [[rng.random() for _ in range(n + 1)] for _ in range(n + 1)]


def _value(grid, n, x, y):
    # smooth value noise on an n x n lattice, x and y in 0..1
    fx, fy = x * n, y * n
    ix, iy = min(int(fx), n - 1), min(int(fy), n - 1)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = _lerp(grid[iy][ix], grid[iy][ix + 1], tx)
    b = _lerp(grid[iy + 1][ix], grid[iy + 1][ix + 1], tx)
    return _lerp(a, b, ty)


def puff(seed, size=SIZE):
    """The puff's density, size x size, each 0..1."""
    rng = random.Random(seed)
    lobes = []
    for k in range(6):
        ang, far = rng.random() * 2 * math.pi, 0.04 + rng.random() ** 0.7 * 0.17
        lobes.append((0.5 + math.cos(ang) * far, 0.5 + math.sin(ang) * far, 0.17 + rng.random() * 0.11))
    coarse, fine = _noise_grid(rng, 3), _noise_grid(rng, 7)
    out = []
    for py in range(size):
        row = []
        for px in range(size):
            x, y = (px + 0.5) / size, (py + 0.5) / size
            keep = 1.0
            for cx, cy, r in lobes:
                d = math.hypot(x - cx, y - cy) / r
                if d < 1.6:
                    keep *= 1 - math.exp(-d * d * 1.5) * 0.72 if d > 0 else 0.28
            dens = 1 - keep
            # uneven, and eaten into at its rim (a billow has no clean outline):
            # gently, at two sizes, so there is no hard pattern to catch the eye
            wear = 0.62 + 0.34 * _value(coarse, 3, x, y) + 0.10 * _value(fine, 7, x, y)
            dens = max(0.0, min(1.0, dens * wear)) ** 1.2
            # nothing at all near the texture's edge
            far = math.hypot(x - 0.5, y - 0.5)
            edge = 1 - min(1, max(0, (far - 0.22) / 0.27))
            dens *= edge * edge * (3 - 2 * edge)
            row.append(max(0.0, min(1.0, dens)))
        out.append(row)
    return out


def main():
    os.makedirs('Media', exist_ok=True)
    header = bytes([0, 0, 2]) + bytes(9) + struct.pack('<HHBB', SIZE, SIZE, 32, 40)
    for k, seed in enumerate((11, 23, 37, 58), 1):
        grid = puff(seed)
        body = bytearray()
        for row in grid:
            for v in row:
                body += bytes([255, 255, 255, int(round(v * 255))])
        path = os.path.join('Media', 'smoke%d.tga' % k)
        open(path, 'wb').write(header + bytes(body))
        print(path)


if __name__ == '__main__':
    main()
