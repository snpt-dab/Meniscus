"""The bestiary's reading of a fight from the game's damage meter, tried outside the game.

An empty book with a few creatures in it (nothing of yours is read), a
stand-in meter that answers by view number and creature number as the game's
own documentation says it does, and fights played at Bestiary.lua. Checks
the health learned from the "enemy damage taken" view (0.1.706), that the
reading before it still runs where the view gives nothing or is put aside,
what hit you, and a boss fight's end.

    PYTHONPATH=<folder with lupa> python dist/tests/bestiary_meter.py
"""
import io, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
from lupa import lua51 as L
ADDON = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..')
MOCK = io.open(os.path.join(ADDON, 'dist', 'tests', 'mock.lua'), encoding='utf-8').read()
SRC = io.open(os.path.join(ADDON, 'Bestiary.lua'), encoding='utf-8').read()
rt = L.LuaRuntime(unpack_returned_tuples=True)
rt.execute(MOCK)
rt.execute(r'''
MinimalUIDB = { bestiaryRev = 9, bestiary = {
    [100] = { n = "Wolf" }, [101] = { n = "Boar" }, [102] = { n = "Bear" }, [103] = { n = "Spider" }, [104] = { n = "Bat" },
    [105] = { n = "Crab" }, [106] = { n = "Hawk" }, [107] = { n = "Toad" }, [200] = { n = "Lord Rot" }, [201] = { n = "Lady Bone" },
    [108] = { n = "Rat" }, [109] = { n = "Mole" }, [202] = { n = "Old Gnash" },
} }
date = date or os.date
function GetRealZoneText() return "Tirisfal Glades" end
function GetZoneText() return "Tirisfal Glades" end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return nil end
function strsplit(sep, text)
    local out = {}
    for part in (text .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
    return unpack(out)
end
time = os.time
function UnitExists() return false end
function UnitIsPlayer() return false end
function UnitPlayerControlled() return false end
function UnitReaction() return nil end
function UnitLevel(u) if u == "player" then return 22 end return nil end
function UnitCreatureType() return nil end
function UnitCreatureFamily() return nil end
function UnitClassification() return nil end
function UnitIsDead() return false end
function UnitName(u) if u == "player" then return "Tester" end return nil end
function UnitGUID(u)
    if u == "player" then return "Player-1-0001" end
    if GROUPED and u == "party1" then return "Player-1-0002" end
    return nil
end
function UnitCanAttack() return true end
function IsInGroup() return GROUPED end
GROUPED = false
C_TooltipInfo = { GetHyperlink = function() return { lines = { { leftText = "Unknown" } } } end }
function GetNumLootItems() return 0 end
ns.Call = function(fn, ...)
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end
ns.Money = function(c) return tostring(c) .. "c" end
-- The meter. VIEWS[type] = the lines of a view; ONE[type][guid or creature
-- number] = one line asked for by itself (its spells). As in the game: a
-- creature's line has a creature number and no GUID.
Enum = { DamageMeterType = { DamageDone = 0, DamageTaken = 7, EnemyDamageTaken = 10 } }
VIEWS, ONE, ASKED = {}, {}, {}
C_DamageMeter = {
    GetCombatSessionFromType = function(ses, ty)
        ASKED[#ASKED + 1] = ty
        return { combatSources = VIEWS[ty] or {} }
    end,
    GetCombatSessionSourceFromType = function(ses, ty, guid, cid)
        local t = ONE[ty] or {}
        return t[guid or false] or t[cid or false] or { combatSpells = {}, totalAmount = 0 }
    end,
}
function fight(lines, opts)
    opts = opts or {}
    VIEWS, ONE = { [10] = opts.enemies }, { [0] = { ["Player-1-0001"] = { totalAmount = opts.mine or 0, combatSpells = {} },
        ["Player-1-0002"] = { totalAmount = opts.theirs or 0, combatSpells = {} } }, [7] = opts.taken, [10] = opts.one }
    if opts.setup then opts.setup() end
    WORLD.combat = true
    fire("PLAYER_REGEN_DISABLED")
    run(1)
    for _, l in ipairs(lines) do fire("CHAT_MSG_COMBAT_XP_GAIN", l .. " dies, you gain 50 experience.") end
    if opts.enc then fire("ENCOUNTER_END", 77, "The Rotten Court", 1, 5, opts.enc[1], opts.enc[2]) end
    WORLD.combat = false
    fire("PLAYER_REGEN_ENABLED")
    run(opts.wait or 3)
end
function health(id)
    local r = MinimalUIDB.bestiary[id]
    local t = {}
    for L, h in pairs(r and r.he or {}) do t[#t + 1] = h end
    table.sort(t)
    return table.concat(t, ",")
end
function said(what)
    local t = MinimalUIDB.metercheck and MinimalUIDB.metercheck.log or {}
    for _, l in ipairs(t) do if l:find(what, 1, true) then return true end end
    return false
end
''')
load = rt.eval('function(src, name) local f, e = loadstring(src, name); if not f then error(e) end; return f end')
rt.globals()['__chunk'] = load(SRC, 'Bestiary.lua')
rt.execute('__chunk("Meniscus", ns)')
rt.execute('B = ns.modules.Bestiary; B:OnInit({ enabled = true, collapsed = {} })')

bad = 0
def check(what, got, want):
    global bad
    ok = got == want
    if not ok: bad += 1
    print(('ok   ' if ok else 'FAIL ') + what + ('' if ok else '   got %r, wanted %r' % (got, want)))
ev = rt.eval

# 1. Alone, one kill, with a second creature hit that lived: the old reading
#    would take everything you did (396); the view says what each one took.
rt.execute('''fight({ "Wolf" }, { mine = 396, enemies = {
    { sourceCreatureID = 100, name = "Wolf", totalAmount = 346, deathTimeSeconds = 12, classification = "normal" },
    { sourceCreatureID = 101, name = "Boar", totalAmount = 50, deathTimeSeconds = 0, classification = "normal" } } })''')
check('one kill among two fought: its health is what IT took', ev('health(100)'), '346')
check('the one that lived gets no health', ev('health(101)'), '')
check('the view was asked for by its number', ev('ASKED[1]'), 10)
check('what the old way would have said is written beside it', ev('said("the old way would have said 396")'), True)

# 2. A boss in a group, with its fight's end heard, an excess on the last blow, and adds about.
rt.execute('''GROUPED = true
fight({ "Lord Rot" }, { mine = 400, theirs = 1900, enc = { 1, { { creatureID = 200, creatureName = "Lord Rot", remainingHealthPercent = 0 },
        { creatureID = 201, creatureName = "Lady Bone", remainingHealthPercent = 0 } } },
    enemies = { { sourceCreatureID = 200, name = "Lord Rot", totalAmount = 2000, deathTimeSeconds = 80, classification = "elite" },
                { sourceCreatureID = 103, name = "Spider", totalAmount = 300, deathTimeSeconds = 0, classification = "normal" } },
    one = { [200] = { combatSpells = { { overkillAmount = 30 } } } } })
GROUPED = false''')
check("a boss's health in a group, less the last blow's excess", ev('health(200)'), '1970')
check('the group sum of before was not used as well', ev('MinimalUIDB.grouphp == nil'), True)
check("every boss of the fight is a boss by name, whatever the fight is called", ev('MinimalUIDB.bossNames["Lady Bone"] == true and MinimalUIDB.bossNames["Lord Rot"] == true'), True)
check('and by number', ev('MinimalUIDB.bossIDs[200] == true and MinimalUIDB.bossIDs[201] == true'), True)
check('rank shown for it: boss', ev('B.RankOf(MinimalUIDB.bestiary[201])'), 'worldboss')

# 3. Two of a kind died and the meter has one line for both: nothing learned.
rt.execute('''fight({ "Bear", "Bear" }, { mine = 700, enemies = {
    { sourceCreatureID = 102, name = "Bear", totalAmount = 700, deathTimeSeconds = 20, classification = "normal" } } })''')
check('two died, one line: no health taken from it', ev('health(102)'), '')
check('  and the fight is read once, not asked again', ev('MinimalUIDB.metercheck.n["enemy view read, no health learned"]'), 1)
# 4. Two of a kind, a line each: both are samples (the least is shown).
rt.execute('''fight({ "Bat", "Bat" }, { mine = 205, enemies = {
    { sourceCreatureID = 104, name = "Bat", totalAmount = 105, deathTimeSeconds = 9, classification = "normal" },
    { sourceCreatureID = 104, name = "Bat", totalAmount = 100, deathTimeSeconds = 15, classification = "normal" } } })''')
check('two died, a line each: both taken', ev('health(104)'), '100')
check('  (two samples)', ev('MinimalUIDB.bestiary[104].hn[0]'), 2)

# 5. Figures still hidden just after the fight: asked again, then read.
rt.execute('''fight({ "Crab" }, { mine = 222, wait = 0.8, enemies = {
    { sourceCreatureID = 105, name = "Crab", totalAmount = SECRET(1), deathTimeSeconds = SECRET(1), classification = "normal" } } })''')
check('hidden: nothing yet', ev('health(105)'), '')
rt.execute('VIEWS[10][1].totalAmount = 210; VIEWS[10][1].deathTimeSeconds = 5; run(4)')
check('readable a moment later: taken then', ev('health(105)'), '210')

# 6. A name the game hides, with the creature number in the clear.
rt.execute('''fight({ "Hawk" }, { mine = 150, enemies = {
    { sourceCreatureID = 106, name = SECRET(1), totalAmount = 140, deathTimeSeconds = 5, classification = "normal" } } })''')
check('name hidden, number plain: still taken', ev('health(106)'), '140')

# 7. Put aside by the player: the reading of before (everything you did, one kill).
rt.execute('''ns.commands.bestiary("meter old")
fight({ "Toad" }, { mine = 180, enemies = {
    { sourceCreatureID = 107, name = "Toad", totalAmount = 160, deathTimeSeconds = 5, classification = "normal" } } })''')
check('"/men bestiary meter old": as before', ev('health(107)'), '180')
rt.execute('ns.commands.bestiary("meter new")')
check('"/men bestiary meter new" changes back', ev('MinimalUIDB.bestMeterOld'), None)

# 8. A client with no list of views: the reading of before, by itself.
rt.execute('''local keep = Enum; Enum = nil
fight({ "Rat" }, { mine = 90, enemies = { { sourceCreatureID = 108, name = "Rat", totalAmount = 80, deathTimeSeconds = 5 } } })
Enum = keep''')
check('no list of views: as before', ev('health(108)'), '90')
# 9. The view gives nothing: as before.
rt.execute('''fight({ "Mole" }, { mine = 75 })''')
check('an empty view: as before', ev('health(109)'), '75')

# 10. What hit you, from the "damage taken" view by its number.
rt.execute('''C_Spell = { GetSpellName = function(id) return id == 5 and "Rend" or nil end }
fight({ "Wolf" }, { mine = 346, enemies = { { sourceCreatureID = 100, name = "Wolf", totalAmount = 346, deathTimeSeconds = 5 } },
    taken = { ["Player-1-0001"] = { combatSpells = { { spellID = 6603, creatureName = "Wolf", totalAmount = 40 }, { spellID = 5, creatureName = "Wolf", totalAmount = 12 } } } } })''')
check('its attacks on you are in the book', ev('MinimalUIDB.bestiary[100].c.Melee == 6603 and MinimalUIDB.bestiary[100].c.Rend == 5'), True)

# 11. A boss fight lost with the boss at 40%: written down, not taken.
rt.execute('''GROUPED = true
fight({}, { mine = 300, theirs = 900, enc = { 0, { { creatureID = 202, creatureName = "Old Gnash", remainingHealthPercent = 40 } } },
    enemies = { { sourceCreatureID = 202, name = "Old Gnash", totalAmount = 1200, deathTimeSeconds = 0, classification = "elite" } } })
GROUPED = false''')
check('a boss not killed: no health taken', ev('health(202)'), '')
check('  but what it would come to is written down', ev('said("makes about 2000")'), True)
check('nothing went wrong in the reading', ev('MinimalUIDB.metercheck.n["enemy view: error"]'), None)

print()
print('what the record says:')
for k, v in sorted(dict(ev('MinimalUIDB.metercheck.n').items()).items()): print('  %s: %s' % (k, v))
if '-v' in sys.argv:
    for l in ev('MinimalUIDB.metercheck.log').values(): print('  ' + l)
print(('%d FAILED' % bad) if bad else 'all passed')
sys.exit(1 if bad else 0)
