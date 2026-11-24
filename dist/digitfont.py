"""Makes Media/digits-<family>.ttf: a typeface in which only the numerals draw.

Why: the game's Combat Log hands an addon each of its lines as a ticket that
can be drawn on the screen but not read ("Your Melee hit Wretched Zombie 52
Physical. (16 Overkill)"). Drawn in a typeface where every character but a
numeral is blank and takes up no room, such a line shows as its number alone:
the amount of a hit of yours, which is what the combat text needs when the
game reports no amount any other way (the blow that kills, above all).

In these files:
  * 0-9 are the numerals of the family's bold weight (Inter 600, Manrope 700),
    with their own widths;
  * "(" is wide: whatever a line adds in brackets after the amount
    ("(16 Overkill)", "(8 Blocked)") is pushed to the right, out of the small
    window the number is shown through;
  * every other character is blank and of no width. They are all MAPPED to a
    blank glyph (not left out of the file), so the game has no reason to draw
    them from some other typeface.

How wide a "(" the game will honour had to be found out. Measured in the
game (0.1.648): the blank characters come out at a tenth of a pixel each,
near enough nothing, but a BLANK "(" twelve ems wide came out at a pixel or
two: the game does not go by the advance of a glyph with nothing drawn in
it. So there are several makes of each file, and the addon measures them in
the game and uses the first that behaves (Nameplates.lua, digitCheck):
  -r   "(" is WIDE_EMS wide with a speck of ink at its far right end: wide by
       its advance and by where its ink is, and the speck falls outside the
       window;
  -q   the same width with the speck at its near end (a faint dot after the
       number, if the game goes by the advance alone);
  -p   blank, WIDE_EMS wide (in case a moderate blank width is honoured);
  (none) blank, PAREN_EMS wide: the first make, kept to be measured against.

No font library is used: the few tables a TrueType file needs are written
here by hand. Run:  python dist/digitfont.py     (from the addon's folder)
The source files are under the SIL Open Font License 1.1 (Media/FONTS.txt),
which allows changed versions under another name; these are named
"Meniscus Digits".
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, '..', 'Media')
SOURCES = [('inter', 'inter-600.ttf'), ('manrope', 'manrope-700.ttf')]
PAREN_EMS = 12      # how far the first make's blank "(" was meant to push what follows it
WIDE_EMS = 4.5      # the other makes: wider than the window the number shows through (80 px at size 20)
VARIANTS = ['', 'p', 'q', 'r']
CHUNK = 2048        # the most codes one blank stretch of the character map covers


def tables_of(d):
    n = struct.unpack('>H', d[4:6])[0]
    out = {}
    for i in range(n):
        tag, _, off, ln = struct.unpack('>4sIII', d[12 + 16 * i:28 + 16 * i])
        out[tag.decode('latin-1')] = d[off:off + ln]
    return out


def cmap_reader(cmap):
    """A function code -> glyph number, from the file's Unicode (format 4) map."""
    n = struct.unpack('>H', cmap[2:4])[0]
    sub = None
    for i in range(n):
        pid, eid, off = struct.unpack('>HHI', cmap[4 + 8 * i:12 + 8 * i])
        if (pid, eid) in ((3, 1), (0, 3)) and struct.unpack('>H', cmap[off:off + 2])[0] == 4:
            sub = off
    assert sub is not None, 'no format 4 character map'
    segx2 = struct.unpack('>H', cmap[sub + 6:sub + 8])[0]
    seg = segx2 // 2
    ends = struct.unpack('>%dH' % seg, cmap[sub + 14:sub + 14 + segx2])
    starts = struct.unpack('>%dH' % seg, cmap[sub + 16 + segx2:sub + 16 + 2 * segx2])
    deltas = struct.unpack('>%dh' % seg, cmap[sub + 16 + 2 * segx2:sub + 16 + 3 * segx2])
    ro_at = sub + 16 + 3 * segx2
    offs = struct.unpack('>%dH' % seg, cmap[ro_at:ro_at + segx2])

    def look(c):
        for i in range(seg):
            if ends[i] >= c:
                if starts[i] > c:
                    return 0
                if offs[i] == 0:
                    return (c + deltas[i]) & 0xFFFF
                pos = ro_at + 2 * i + offs[i] + 2 * (c - starts[i])
                g = struct.unpack('>H', cmap[pos:pos + 2])[0]
                return (g + deltas[i]) & 0xFFFF if g else 0
        return 0
    return look


def glyph_of(t, gid):
    long_loca = struct.unpack('>h', t['head'][50:52])[0] == 1
    if long_loca:
        a, b = struct.unpack('>II', t['loca'][4 * gid:4 * gid + 8])
    else:
        a, b = struct.unpack('>HH', t['loca'][2 * gid:2 * gid + 4])
        a, b = a * 2, b * 2
    return t['glyf'][a:b]


def plain(g):
    """A simple glyph with its hinting instructions taken out (they call on
    tables that are not carried over). Returns (data, points, contours, box)."""
    nc = struct.unpack('>h', g[0:2])[0]
    assert nc > 0, 'a numeral built from other glyphs: not handled'
    box = struct.unpack('>4h', g[2:10])
    ends = struct.unpack('>%dH' % nc, g[10:10 + 2 * nc])
    il = struct.unpack('>H', g[10 + 2 * nc:12 + 2 * nc])[0]
    rest = g[12 + 2 * nc + il:]
    out = g[:10 + 2 * nc] + struct.pack('>H', 0) + rest
    if len(out) % 4:
        out += b'\0' * (4 - len(out) % 4)
    return out, ends[-1] + 1, nc, box


def checksum(b):
    if len(b) % 4:
        b = b + b'\0' * (4 - len(b) % 4)
    return sum(struct.unpack('>%dI' % (len(b) // 4), b)) & 0xFFFFFFFF


def build_cmap(first_digit_gid, paren_gid, blank_gid):
    segs = []   # (start, end, delta, uses the shared run of blanks)

    def blanks(a, b):
        while a <= b:
            e = min(b, a + CHUNK - 1)
            segs.append((a, e, 0, True))
            a = e + 1
    blanks(0x20, 0x27)
    segs.append((0x28, 0x28, (paren_gid - 0x28) & 0xFFFF, False))
    blanks(0x29, 0x2F)
    segs.append((0x30, 0x39, (first_digit_gid - 0x30) & 0xFFFF, False))
    blanks(0x3A, 0xD7FF)
    blanks(0xE000, 0xFFFD)
    segs.append((0xFFFF, 0xFFFF, 1, False))
    n = len(segs)
    es = 0
    while (2 << es) <= n:
        es += 1
    sr = 2 * (1 << es)
    sub = struct.pack('>HHHHHHH', 4, 16 + 8 * n + 2 * CHUNK, 0, 2 * n, sr, es, 2 * n - sr)
    sub += struct.pack('>%dH' % n, *[s[1] for s in segs]) + struct.pack('>H', 0)
    sub += struct.pack('>%dH' % n, *[s[0] for s in segs])
    sub += struct.pack('>%dH' % n, *[s[2] for s in segs])
    # (Every blank stretch points at the start of the one shared run.)
    sub += struct.pack('>%dH' % n, *[(2 * (n - i) if s[3] else 0) for i, s in enumerate(segs)])
    sub += struct.pack('>%dH' % CHUNK, *([blank_gid] * CHUNK))
    head = struct.pack('>HH', 0, 2) + struct.pack('>HHI', 0, 3, 20) + struct.pack('>HHI', 3, 1, 20)
    return head + sub


def build_name(family):
    full = 'Meniscus Digits ' + family
    recs = [(1, full), (2, 'Regular'), (3, full + ' 1.0'), (4, full), (5, 'Version 1.0'),
            (6, 'MeniscusDigits-' + family)]
    strings, entries = b'', b''
    for nid, s in recs:
        b = s.encode('utf-16-be')
        entries += struct.pack('>HHHHHH', 3, 1, 0x409, nid, len(b), len(strings))
        strings += b
    return struct.pack('>HHH', 0, len(recs), 6 + 12 * len(recs)) + entries + strings


def speck(x0, y0, size):
    """A small square of ink: a simple glyph of one contour, four points."""
    x1, y1 = x0 + size, y0 + size
    head = struct.pack('>h4h', 1, x0, y0, x1, y1)
    body = struct.pack('>H', 3) + struct.pack('>H', 0)            # the contour ends at point 3; no instructions
    body += bytes([0x01] * 4)                                     # four points on the curve, each a full step in x and y
    body += struct.pack('>4h', x0, 0, size, 0)                    # x: to the start, up the side, across, down the side
    body += struct.pack('>4h', y0, size, 0, -size)
    out = head + body
    if len(out) % 4:
        out += b'\0' * (4 - len(out) % 4)
    return out, (x0, y0, x1, y1)


def make(family, src_name, variant=''):
    src = open(os.path.join(MEDIA, src_name), 'rb').read()
    t = tables_of(src)
    look = cmap_reader(t['cmap'])
    upm = struct.unpack('>H', t['head'][18:20])[0]
    nhm = struct.unpack('>H', t['hhea'][34:36])[0]
    paren = int((PAREN_EMS if variant == '' else WIDE_EMS) * upm)
    assert paren < 32768

    # glyphs: 0 the "missing" glyph, 1 blank, 2 the wide one, 3-12 the numerals
    wide, wide_box = b'', None
    if variant == 'q':
        wide, wide_box = speck(int(0.02 * upm), 0, int(0.06 * upm))
    elif variant == 'r':
        size = int(0.10 * upm)
        wide, wide_box = speck(paren - size - int(0.02 * upm), 0, size)
    glyphs = [b'', b'', wide]
    metrics = [(0, 0), (0, 0), (paren, wide_box[0] if wide_box else 0)]
    pts = cons = 0
    boxes = []
    if wide_box:
        boxes.append((paren, wide_box))
        pts, cons = 4, 1
    for ch in '0123456789':
        gid = look(ord(ch))
        assert gid, 'no numeral ' + ch
        data, np_, nc, box = plain(glyph_of(t, gid))
        adv = struct.unpack('>H', t['hmtx'][4 * min(gid, nhm - 1):4 * min(gid, nhm - 1) + 2])[0]
        glyphs.append(data)
        metrics.append((adv, box[0]))
        boxes.append((adv, box))
        pts, cons = max(pts, np_), max(cons, nc)
    n = len(glyphs)

    glyf, loca = b'', [0]
    for g in glyphs:
        glyf += g
        loca.append(len(glyf))
    loca_t = struct.pack('>%dI' % (n + 1), *loca)
    hmtx = b''.join(struct.pack('>Hh', a, l) for a, l in metrics)

    xmin = min(b[0] for _, b in boxes); ymin = min(b[1] for _, b in boxes)
    xmax = max(b[2] for _, b in boxes); ymax = max(b[3] for _, b in boxes)
    head = bytearray(t['head'][:54])
    head[8:12] = struct.pack('>I', 0)                       # checksum adjustment: filled in last
    head[36:44] = struct.pack('>4h', xmin, ymin, xmax, ymax)
    head[50:52] = struct.pack('>h', 1)                      # long offsets to the glyphs
    hhea = bytearray(t['hhea'][:36])
    hhea[10:12] = struct.pack('>H', paren)                  # widest advance
    hhea[12:14] = struct.pack('>h', min(b[0] for _, b in boxes))
    hhea[14:16] = struct.pack('>h', min(a - b[2] for a, b in boxes))
    hhea[16:18] = struct.pack('>h', xmax)
    hhea[34:36] = struct.pack('>H', n)
    maxp = struct.pack('>IHHHHHHHHHHHHHH', 0x00010000, n, pts, cons, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    os2 = bytearray(t['OS/2'])
    os2[2:4] = struct.pack('>h', sum(a for a, _ in boxes) // len(boxes))
    os2[64:68] = struct.pack('>HH', 0x20, 0xFFFD)           # first and last character
    post = struct.pack('>Ii', 0x00030000, 0) + t['post'][8:12] + struct.pack('>IIIII', 0, 0, 0, 0, 0)

    out_tables = {
        'OS/2': bytes(os2), 'cmap': build_cmap(3, 2, 1), 'glyf': glyf, 'head': bytes(head), 'hhea': bytes(hhea),
        'hmtx': hmtx, 'loca': loca_t, 'maxp': maxp, 'name': build_name(family.capitalize() + (' ' + variant.upper() if variant else '')), 'post': post,
    }
    tags = sorted(out_tables)
    nt = len(tags)
    es = 0
    while (2 << es) <= nt:
        es += 1
    font = struct.pack('>IHHHH', 0x00010000, nt, 16 * (1 << es), es, 16 * nt - 16 * (1 << es))
    off = 12 + 16 * nt
    body, where = b'', {}
    for tag in tags:
        data = out_tables[tag]
        pad = data + b'\0' * ((4 - len(data) % 4) % 4)
        where[tag] = (off + len(body), len(data))
        font += struct.pack('>4sIII', tag.encode('latin-1'), checksum(data), off + len(body), len(data))
        body += pad
    font += body
    adj = (0xB1B0AFBA - checksum(font)) & 0xFFFFFFFF
    ho = where['head'][0]
    font = font[:ho + 8] + struct.pack('>I', adj) + font[ho + 12:]
    path = os.path.join(MEDIA, 'digits-%s%s.ttf' % (family, '-' + variant if variant else ''))
    open(path, 'wb').write(font)
    return path, len(font), upm, [a for a, _ in boxes], paren


if __name__ == '__main__':
    for fam, name in SOURCES:
        for variant in VARIANTS:
            p, size, upm, advs, paren = make(fam, name, variant)
            print('%s  %d bytes  %d units to the em  "(" %d wide' % (
                os.path.relpath(p, os.path.join(HERE, '..')).replace(os.sep, '/'), size, upm, paren))
