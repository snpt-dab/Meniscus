# Puts together the shared bestiary: python dist/bestiary_merge.py
# (run from the Meniscus folder).
#
# In:  dist/bestiary/*.txt   the files players send (made by "/men bestiary
#                            export" in game, then "Share Bestiary.bat")
#      and this machine's own export, read straight from the saved file
#      (WTF/Account/*/SavedVariables/Meniscus.lua, MinimalUIDB.bestiaryOut).
# Out: BestiaryData.lua      shipped with the addon, read by Bestiary.lua.
#
# It is rebuilt from the files every time, never added to: a player's
# newer file replaces their older one (same "who"), so nobody is counted
# twice. What comes in is other people's data going out to everyone, so it
# is checked field by field: only the known fields, of the known types and
# sizes, and no "|" in any text (the game's escape for links and pictures).
import glob, io, os, re, sys

# ── reading the game's saved-variables format ──
class P:
    def __init__(s, t): s.t, s.i = t, 0
    def ws(s):
        t = s.t
        while s.i < len(t):
            c = t[s.i]
            if c in ' \t\r\n': s.i += 1
            elif t.startswith('--', s.i):
                j = t.find('\n', s.i)
                s.i = len(t) if j < 0 else j
            else: break
    def value(s):
        s.ws(); t = s.t; c = t[s.i]
        if c == '{': return s.table()
        if c == '"': return s.string()
        for word, val in (('true', True), ('false', False), ('nil', None)):
            if t.startswith(word, s.i): s.i += len(word); return val
        m = re.compile(r'-?(0x[0-9a-fA-F]+|\d+\.?\d*(e[-+]?\d+)?)').match(t, s.i)
        if not m: raise ValueError('unexpected %r at %d' % (t[s.i:s.i + 20], s.i))
        s.i = m.end(); x = m.group(0)
        return int(x, 0) if re.fullmatch(r'-?(0x[0-9a-fA-F]+|\d+)', x) else float(x)
    def string(s):
        t = s.t; s.i += 1; out = []
        while True:
            c = t[s.i]
            if c == '"': s.i += 1; break
            if c == '\\':
                s.i += 1; e = t[s.i]
                if e.isdigit():
                    m = re.compile(r'\d{1,3}').match(t, s.i); out.append(chr(int(m.group(0)))); s.i = m.end(); continue
                out.append({'n': '\n', 'r': '\r', 't': '\t'}.get(e, e)); s.i += 1
            else: out.append(c); s.i += 1
        # (bytes above 127 came through as \ddd: put the UTF-8 back together)
        r = ''.join(out)
        try: return r.encode('latin-1').decode('utf-8')
        except (UnicodeEncodeError, UnicodeDecodeError): return r
    def table(s):
        s.i += 1; d = {}; n = 0
        while True:
            s.ws()
            if s.t[s.i] == '}': s.i += 1; break
            if s.t[s.i] == '[':
                s.i += 1; k = s.value(); s.ws(); assert s.t[s.i] == ']'; s.i += 1
                s.ws(); assert s.t[s.i] == '='; s.i += 1
                d[k] = s.value()
            else:
                n += 1; d[n] = s.value()
            s.ws()
            if s.t[s.i] in ',;': s.i += 1
        return d

def block(text, key):
    """the table saved under ["key"] at the top level, or None"""
    m = re.search(r'\n\["%s"\] = \{' % re.escape(key), text)
    if not m: return None
    p = P(text); p.i = m.end() - 1
    return p.table()

# ── checking what came in ──
def txt(v, n):
    if not isinstance(v, str): return None
    v = re.sub(r'[\x00-\x1f|]', '', v).strip()
    return v[:n] if v else None
def num(v, lo, hi):
    return v if isinstance(v, int) and not isinstance(v, bool) and lo <= v <= hi else None
RANKS = {'elite', 'rareelite', 'rare', 'worldboss'}
def clean(r):
    if not isinstance(r, dict): return None
    o = {}
    o['n'] = txt(r.get('n'), 80)
    if not o['n']: return None
    lo, hi = num(r.get('lo'), 1, 255), num(r.get('hi'), 1, 255)
    if lo and hi and lo <= hi: o['lo'], o['hi'] = lo, hi
    for k, n in (('t', 40), ('f', 40)):
        v = txt(r.get(k), n)
        if v: o[k] = v
    if r.get('cl') in RANKS: o['cl'] = r['cl']
    if r.get('ag') in (0, 1): o['ag'] = r['ag']
    z = {txt(k, 60): True for k in (r.get('z') or {}) if txt(k, 60)} if isinstance(r.get('z'), dict) else {}
    if z: o['z'] = z
    hp = {k: v for k, v in (r.get('hp') or {}).items() if num(k, 1, 255) and num(v, 1, 10**9)} if isinstance(r.get('hp'), dict) else {}
    if hp: o['hp'] = hp
    c = {}
    for k, v in (r.get('c') or {}).items() if isinstance(r.get('c'), dict) else ():
        k = txt(k, 60)
        if k: c[k] = v if num(v, 1, 10**7) else True
    if c: o['c'] = c
    hit = {}
    for k, v in (r.get('hit') or {}).items() if isinstance(r.get('hit'), dict) else ():
        k = txt(k, 60)
        if k and num(v, 1, 10**7): hit[k] = v
    if hit: o['hit'] = hit
    q = []
    src = r.get('q') if isinstance(r.get('q'), dict) else {}
    for i in sorted(k for k in src if isinstance(k, int)):
        line = src[i]
        if not isinstance(line, dict): continue
        t = txt(line.get('t'), 300)
        if not t: continue
        e = {'t': t}
        if line.get('k') in ('yell', 'emote'): e['k'] = line['k']
        l = txt(line.get('l'), 30)
        if l: e['l'] = l
        if line.get('u') is True: e['u'] = True
        q.append(e)
    if q: o['q'] = q
    ln, lk = num(r.get('ln'), 0, 10**7) or 0, num(r.get('lk'), 0, 10**7) or 0
    l = {}
    for k, v in (r.get('l') or {}).items() if isinstance(r.get('l'), dict) else ():
        if num(k, 1, 10**7) and num(v, 1, ln): l[k] = v
    if ln: o['ln'] = ln
    if lk: o['lk'] = lk
    if l: o['l'] = l
    return o

# ── putting records together ──
def merge(a, b):
    if a is None: return b
    if 'lo' in b:
        a['lo'], a['hi'] = min(a.get('lo', b['lo']), b['lo']), max(a.get('hi', b['hi']), b['hi'])
    for k in ('t', 'f', 'cl', 'ag'):
        if k not in a and k in b: a[k] = b[k]
    if 'z' in b: a.setdefault('z', {}).update(b['z'])
    for k in ('hp', 'hit'):
        for x, v in b.get(k, {}).items():
            d = a.setdefault(k, {})
            d[x] = max(d.get(x, 0), v)
    for x, v in b.get('c', {}).items():
        d = a.setdefault('c', {})
        if x not in d or d[x] is True: d[x] = v
    if 'q' in b:
        q = a.setdefault('q', [])
        have = {e['t'] for e in q}
        q += [e for e in b['q'] if e['t'] not in have]
    a['ln'] = a.get('ln', 0) + b.get('ln', 0)
    a['lk'] = a.get('lk', 0) + b.get('lk', 0)
    for x, v in b.get('l', {}).items():
        d = a.setdefault('l', {})
        d[x] = d.get(x, 0) + v
    return a
def finish(r):
    # a line heard clearly makes the scrambled ones in that language moot
    if 'q' in r:
        clear = {e.get('l') for e in r['q'] if not e.get('u')}
        r['q'] = [e for e in r['q'] if not (e.get('u') and e.get('l') in clear)][:16]
    if 'z' in r: r['z'] = dict(sorted(r['z'].items())[:8])
    if 'c' in r: r['c'] = dict(sorted(r['c'].items())[:24])
    if 'l' in r: r['l'] = dict(sorted(r['l'].items(), key=lambda kv: -kv[1])[:120])
    for k in ('ln', 'lk'):
        if not r.get(k): r.pop(k, None)
    return r

# ── writing Lua ──
KEYWORDS = set('and break do else elseif end false for function if in local nil not or repeat return then true until while'.split())
def lua(v, ind=0):
    if v is True: return 'true'
    if isinstance(v, int): return str(v)
    if isinstance(v, str): return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(v, list): return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    parts = []
    for k in sorted(v, key=lambda k: (isinstance(k, str), k)):
        key = ('[%d]' % k) if isinstance(k, int) else (k if re.fullmatch(r'[A-Za-z_]\w*', k) and k not in KEYWORDS else '[%s]' % lua(k))
        parts.append('%s = %s' % (key, lua(v[k])))
    return '{ ' + ', '.join(parts) + ' }' if parts else '{}'

def main():
    sources = []
    for p in sorted(glob.glob('dist/bestiary/*.txt')):
        t = io.open(p, encoding='utf-8', errors='replace').read()
        i = t.find('{')
        if i < 0: print('skipped (no table):', os.path.basename(p)); continue
        try:
            pp = P(t); pp.i = i; sources.append((os.path.basename(p), pp.table()))
        except Exception as e:
            print('skipped (%s): %s' % (e, os.path.basename(p)))
    for p in glob.glob('../../../WTF/Account/*/SavedVariables/Meniscus.lua'):
        try:
            b = block(io.open(p, encoding='utf-8', errors='replace').read(), 'bestiaryOut')
            if b: sources.append(('this machine', b))
        except Exception as e:
            print('skipped this machine\'s saved file (%s)' % e)
    latest = {}
    for name, d in sources:
        who, at = d.get('who'), d.get('at')
        if not (isinstance(who, str) and re.fullmatch(r'[0-9a-f]{6,40}', who) and isinstance(at, int) and isinstance(d.get('r'), dict)):
            print('skipped (not an export):', name); continue
        if who not in latest or latest[who][0] < at: latest[who] = (at, d['r'], name)
    out = {}
    for who, (at, recs, name) in sorted(latest.items()):
        n = 0
        for id_, r in recs.items():
            c = clean(r) if num(id_, 1, 10**8) else None
            if c: out[id_] = merge(out.get(id_), c); n += 1
        print('%-28s %5d creatures' % (name, n))
    for r in out.values(): finish(r)
    lines = ['local _, ns = ...',
             '-- The shared bestiary: what the players who sent their records in have',
             '-- learned, put together. Written by dist/bestiary_merge.py; not edited',
             '-- by hand. Read by Bestiary.lua (which explains "from").',
             'ns.BestiaryShared = {',
             '    from = %s,' % lua({who: at for who, (at, _, _) in latest.items()}),
             '    r = {']
    for id_ in sorted(out):
        lines.append('        [%d] = %s,' % (id_, lua(out[id_])))
    lines += ['    },', '}', '']
    io.open('BestiaryData.lua', 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
    print('BestiaryData.lua: %d creatures from %d players' % (len(out), len(latest)))

if __name__ == '__main__':
    main()
