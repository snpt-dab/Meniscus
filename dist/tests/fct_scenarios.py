"""The combat numbers, tried outside the game.

mock.lua stands in for the game (frames that accept anything, a clock,
timers, events); Nameplates.lua is loaded into it as it is, and each case
below plays a few events at it (a log line, a hit reported, a kill) and looks
at what was put on the screen and what the record says.

    PYTHONPATH=<folder with lupa> python dist/tests/fct_scenarios.py

(lupa is the Lua 5.1 used for the syntax check: see CLAUDE.md. Run from the
addon's folder, or give the addon's folder as the first argument.)
"""
import io, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
from lupa import lua51 as L

ADDON = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..')
MOCK = io.open(os.path.join(HERE, 'mock.lua'), encoding='utf-8').read()
SRC = io.open(os.path.join(ADDON, 'Nameplates.lua'), encoding='utf-8').read()

SETUP = r'''
C_NamePlate.GetNamePlateForUnit = function(u)
    local id = WORLD.units[u]
    if not id then return nil end
    for name, other in pairs(WORLD.units) do
        if other == id and name:find("^nameplate") then return WORLD.plates[name] end
    end
    return nil
end
function mob(unit, id)
    WORLD.units[unit] = id
    WORLD.plates[unit] = WORLD.plates[unit] or CreateFrame("Frame")
    WORLD.threat[id] = true
end
function gone(unit)          -- its nameplate goes
    fire("NAME_PLATE_UNIT_REMOVED", unit)
    WORLD.units[unit] = nil
end
function die(id)             -- dead: no longer your target, no longer fighting you
    WORLD.dead[id] = true
    if WORLD.units.target == id then WORLD.units.target = nil end
end
local NP = ns.modules.Nameplates
NP:OnInit({ enabled = true, numbersMode = "ours" })
fire("PLAYER_ENTERING_WORLD")
run(12)
START_NOTES, START_DRAWS = #(MinimalUIDB.ctlog or {}), #LOG
'''

def scenario(name, code, broken=False, expect=None):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(MOCK)
    if broken:
        rt.execute('BROKEN_FONT = true')
    load = rt.eval('function(src, name) local f, e = loadstring(src, name); if not f then error(e) end; return f end')
    chunk = load(SRC, 'Nameplates.lua')
    rt.globals()['__chunk'] = chunk
    rt.execute('__chunk("Meniscus", ns)')
    rt.execute(SETUP)
    print('=' * 100)
    print(name)
    print('  typeface check:', rt.eval('MinimalUIDB.digitface'))
    rt.execute(code)
    notes = list(rt.eval('notes(START_NOTES)').values())
    draws = list(rt.eval('draws(START_DRAWS)').values())
    for n in notes:
        print('   note |', n)
    for d in draws:
        print('   DRAW |', d)
    lw = rt.eval('MinimalUIDB.linewide')
    if lw:
        print('  line widths:', lw)
    if expect:
        ok, why = expect(notes, draws)
        print('  RESULT:', 'PASS' if ok else 'FAIL', why or '')
        return ok
    return True

def count(draws, font_part, text_part=None):
    n = 0
    for d in draws:
        parts = d.split(' ', 3)
        if parts[1] == 'text' and font_part in parts[2] and (text_part is None or text_part in parts[3]):
            n += 1
    return n

results = []

# A. alone, a plain swing kills, and the game never reports the hit
results.append(scenario('A. alone: a swing kills, no hit is ever reported', r'''
mob("nameplate1", "wolf"); WORLD.units.target = "wolf"
A_MSG = line("swing")
line("kill")
die("wolf"); gone("nameplate1")
run(2.5)
''', expect=lambda n, d: (count(d, 'digits', '|Ky') == 1 and count(d, 'manrope-700') == 0, 'one number, from the line')))

# B. alone, a swing kills, and its hit IS reported 0.3 s later on the dead enemy's nameplate
results.append(scenario('B. alone: a swing kills, its hit reported 0.30 s later on the nameplate', r'''
mob("nameplate1", "wolf"); WORLD.units.target = "wolf"
line("swing")
line("kill")
die("wolf")
run(0.30)
hit("nameplate1", 31, 1)
run(0.2)
gone("nameplate1")
run(2.5)
''', expect=lambda n, d: (count(d, 'digits', '|Ky') == 1 and count(d, 'manrope-700', 'amount') == 0, 'one number (the line), the late report not drawn again')))

# C. alone, an ordinary swing: reported 0.26 s later, drawn from the report as before
results.append(scenario('C. alone: an ordinary swing, reported 0.26 s later', r'''
mob("nameplate1", "wolf"); WORLD.units.target = "wolf"
line("swing")
run(0.26)
hit("nameplate1", 22, 1, "CRITICAL")
hit("target", 22, 1, "CRITICAL")
run(2.5)
''', expect=lambda n, d: (count(d, 'digits') == 0 and count(d, 'manrope-700', 'amount(22)') >= 1, 'drawn from its report (a critical: three strings), nothing from the line')))

# D. in a group: a swing, somebody else's blow lands on the same enemy first, then your own report
results.append(scenario('D. in a group: your swing; a stranger\'s blow at 0.26 s, your own report at 0.58 s', r'''
WORLD.grouped = true
MinimalUIDB.swingd = { { d = 0.26, n = 20 }, { d = 0.58, n = 20 }, { d = 1.30, n = 20 } }
mob("nameplate1", "ogre"); WORLD.units.target = "ogre"
line("swing")
run(0.26)
hit("nameplate1", 99, 1)       -- somebody else's
run(0.32)
hit("nameplate1", 22, 1)       -- yours
run(2.5)
''', expect=lambda n, d: (count(d, 'digits', '|Ky') == 1 and count(d, 'manrope-700', 'amount') == 0, 'exactly one number, the line\'s own amount, no stranger\'s amount')))

# E. Heroic Strike kills: empty swing, kill notice, spell line, the strike (all in one moment)
results.append(scenario('E. a Heroic Strike kills (the order recorded at 459.19)', r'''
mob("nameplate1", "wolf"); WORLD.units.target = "wolf"
hit("nameplate1", 0, 1)
hit("target", 0, 1)
line("kill")
line("spell")
hit("nameplate1", 40, 1)
hit("target", 40, 1)
die("wolf")
run(0.3)
gone("nameplate1")
run(2.5)
''', expect=lambda n, d: (count(d, 'manrope-700', 'amount(40)') == 1 and count(d, 'digits', '|Ky') == 1 and any('stands behind it' in x for x in n),
                          'the strike from its report, its line standing behind it (one hidden copy)')))

# F. a spell line with no hit reported (an enemy with no nameplate, not your target)
results.append(scenario('F. a spell\'s line, no hit reported for it', r'''
mob("nameplate1", "wolf"); WORLD.units.target = "wolf"
line("spell")
run(1.0)
''', expect=lambda n, d: (count(d, 'digits', '|Ky') == 1, 'drawn from the line when its moment has passed')))

# G. out of a fight (the log refilling): nothing is drawn
results.append(scenario('G. lines out of a fight (the log printing old lines)', r'''
WORLD.combat = false
line("spell"); line("swing"); line("kill"); line("tick")
run(3)
''', expect=lambda n, d: (count(d, 'digits') == 0 and count(d, 'manrope-700') == 0, 'nothing drawn')))

# H. a swing, and the enemy's nameplate goes (killed by someone else) before it is reported
results.append(scenario('H. in a group: your swing, the enemy dies to someone else before the report', r'''
WORLD.grouped = true
mob("nameplate1", "ogre"); WORLD.units.target = "ogre"
line("swing")
run(0.15)
die("ogre"); gone("nameplate1")
run(0.2)
mob("nameplate1", "bat")       -- the nameplate is handed to another enemy
hit("nameplate1", 55, 1)       -- somebody's blow on that one
run(2.5)
''', expect=lambda n, d: (count(d, 'digits', '|Ky') == 1 and count(d, 'manrope-700', 'amount') == 0, 'one number as the nameplate goes; the next enemy\'s hit is not taken for it')))

# I. a tick kills: hit first, then its line, then the kill notice
results.append(scenario('I. a tick kills (hit, its line, the kill notice)', r'''
mob("nameplate1", "wolf"); WORLD.units.target = "wolf"
hit("nameplate1", 9, 1)
line("tick")
line("kill")
die("wolf")
run(2.5)
''', expect=lambda n, d: (count(d, 'manrope-700', 'amount(9)') == 1 and any('stands behind it' in x for x in n), 'the tick from its report, its line behind it')))

# J. the typeface does not measure up in the game: everything as before (a swing kill has no number)
results.append(scenario('J. typeface NOT as it should be: nothing changes', r'''
mob("nameplate1", "wolf"); WORLD.units.target = "wolf"
line("swing")
line("kill")
die("wolf"); gone("nameplate1")
run(2.5)
mob("nameplate2", "boar"); WORLD.units.target = "boar"
line("swing")
run(0.26)
hit("nameplate2", 22, 1)
run(2.5)
''', broken=True, expect=lambda n, d: (count(d, 'digits', '|Ky') == 0 and count(d, 'manrope-700', 'amount(22)') == 1, 'no line numbers; the ordinary swing still drawn from its report')))

# K. alone, with a stranger on your enemy a moment before: a swing's report draws the line's own amount
results.append(scenario('K. alone, a stranger hitting your enemy: your swing reported 0.58 s later', r'''
mob("nameplate1", "wolf"); WORLD.units.target = "wolf"
hit("nameplate1", 70, 4)       -- a stranger's fire
run(0.5)
line("swing")
run(0.58)
hit("nameplate1", 22, 1, "CRITICAL")
run(2.5)
''', expect=lambda n, d: (count(d, 'digits', '|Ky') == 3 and count(d, 'manrope-700', 'amount') == 0, 'the swing drawn from its line, as a critical (three strings), nothing of the stranger\'s')))

# L. two fights in a row alone: kill by swing, then a new enemy's first swing is not swallowed
results.append(scenario('L. a kill by a swing, then at once a swing on the next enemy', r'''
mob("nameplate1", "wolf"); mob("nameplate2", "boar"); WORLD.units.target = "wolf"
line("swing")
line("kill")
die("wolf"); gone("nameplate1")
WORLD.units.target = "boar"
run(0.4)
line("swing")
run(0.26)
hit("nameplate2", 18, 1)
hit("target", 18, 1)
run(2.5)
''', expect=lambda n, d: (count(d, 'digits', '|Ky') == 1 and count(d, 'manrope-700', 'amount(18)') == 1, 'the kill from its line, the next swing from its report')))

print('=' * 100)
print('passed %d of %d' % (sum(1 for r in results if r), len(results)))
