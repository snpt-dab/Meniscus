"""The bestiary, tried outside the game on a COPY of your own saved book.

Loads the saved file as it is (nothing is written back), runs the bestiary's
start-up tidy-ups on it, then plays a short visit to a dungeon at it: kills
named by the experience line, a target that dies, a boss whose level is "??",
a corpse looted, and the walk out (where a looted creature gets its name).
Prints the creatures watched at each step, the list's headings and one
creature's rows.

    PYTHONPATH=<folder with lupa> python dist/tests/bestiary_book.py
"""
import io, os, sys, glob
HERE = os.path.dirname(os.path.abspath(__file__))
from lupa import lua51 as L
ADDON = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..')
MOCK = io.open(os.path.join(ADDON, 'dist', 'tests', 'mock.lua'), encoding='utf-8').read()
SRC = io.open(os.path.join(ADDON, 'Bestiary.lua'), encoding='utf-8').read()
SV = io.open(glob.glob(os.path.join(ADDON, '../../../WTF/Account/*/SavedVariables/Meniscus.lua'))[0], encoding='utf-8', errors='replace').read()
rt = L.LuaRuntime(unpack_returned_tuples=True)
rt.execute(MOCK)
rt.execute(SV)
rt.execute(r'''
ZONE, INST, INSTNAME, INSTKIND = "Tirisfal Glades", false, nil, nil
function GetRealZoneText() return ZONE end
function GetZoneText() return ZONE end
function IsInInstance() return INST, INSTKIND or "none" end
function GetInstanceInfo() return INSTNAME, INSTKIND end
function strsplit(sep, text)
    local out = {}
    for part in (text .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
    return unpack(out)
end
time = os.time
TARGET = nil
function UnitExists(u) return u == "target" and TARGET ~= nil end
function UnitIsPlayer() return false end
function UnitPlayerControlled() return false end
function UnitReaction(u) return TARGET and 2 or nil end
function UnitLevel(u) if u == "player" then return 22 end return TARGET and TARGET.l or nil end
function UnitCreatureType() return SECRET(1) end
function UnitCreatureFamily() return nil end
function UnitClassification() return TARGET and TARGET.cl or nil end
function UnitIsDead(u) return TARGET and TARGET.dead or false end
function UnitName(u) if u == "player" then return "Tester" end return SECRET(1) end
function UnitGUID(u) if u == "player" then return "Player-1-0001" end return SECRET(1) end
function UnitCanAttack() return true end
function IsInGroup() return GROUPED end
GROUPED = true
TIP = {}
C_TooltipInfo = { GetHyperlink = function(link)
    local id = tonumber(link:match("Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if INST then return { lines = { { leftText = SECRET(1) } } } end
    local name = TIP[id]
    return name and { lines = { { leftText = name } } } or { lines = { { leftText = "Unknown" } } }
end }
LOOTS = {}
function GetNumLootItems() return #LOOTS end
function GetLootSlotLink(i) return "|Hitem:" .. LOOTS[i].item .. "::|h[x]|h" end
function GetLootSourceInfo(i) return LOOTS[i].guid, 1 end
function GetLootSlotInfo(i) return nil, "x" end
ns.Call = function(fn, ...)
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end
ns.Money = function(c) return tostring(c) .. "c" end
''')
load = rt.eval('function(src, name) local f, e = loadstring(src, name); if not f then error(e) end; return f end')
rt.globals()['__chunk'] = load(SRC, 'Bestiary.lua')
rt.execute('__chunk("Meniscus", ns)')
dump = rt.eval(r'''function(names)
    local out = {}
    local want = {}
    for n in names:gmatch("[^,]+") do want[n] = true end
    for id, r in pairs(MinimalUIDB.bestiary) do
        if r.n and (names == "*neg" and id < 0 or want[r.n]) then
            local z = {}
            for k, v in pairs(r.z or {}) do z[#z + 1] = k .. "=" .. tostring(v) end
            table.sort(z)
            out[#out + 1] = string.format("%-8s %-20s k=%-3s lk=%-4s ln=%-4s lvl=%s-%s cl=%-6s xp=%-4s z={%s}", tostring(id), r.n, tostring(r.k), tostring(r.lk), tostring(r.ln),
                tostring(r.lo), tostring(r.hi), tostring(r.cl), tostring(r.xp), table.concat(z, ", "))
        end
    end
    table.sort(out)
    return table.concat(out, "\n")
end''')
count = '(function() local n = 0; for _ in pairs(%s or {}) do n = n + 1 end return n end)()'
WATCH = "Skeleton,Ghoul,Druid of the Fang,The Baron,Broodling,Rift Spawn,Mindless Undead,Plague Ghoul,Deviate Coiler,Witherfang,Crypt Fiend"
print('--- before (rev %s, kept aside by name: %s, creatures %s)' % (rt.eval('MinimalUIDB.bestiaryRev'), rt.eval(count % 'MinimalUIDB.bestiaryPend'), rt.eval(count % 'MinimalUIDB.bestiary')))
print(dump(WATCH))
rt.execute('B = ns.modules.Bestiary; B:OnInit({ enabled = true, collapsed = {} })')
print('--- after the tidy-up (rev %s, kept aside: %s, creatures %s)' % (rt.eval('MinimalUIDB.bestiaryRev'), rt.eval('tostring(MinimalUIDB.bestiaryPend)'), rt.eval(count % 'MinimalUIDB.bestiary')))
print(dump(WATCH))
print('--- known by name alone')
print(dump("*neg"))

rt.execute(r'''
INST, INSTKIND, INSTNAME, ZONE = true, "party", "Ruins of Lordaeron", "Ruins of Lordaeron"
run(1)
fire("CHAT_MSG_COMBAT_XP_GAIN", "Mindless Undead dies, you gain 24 experience. (+7 group bonus)")
TARGET = { l = 17, cl = "elite" }
fire("PLAYER_TARGET_CHANGED")
run(0.5)
TARGET = nil
fire("PLAYER_TARGET_CHANGED")
run(0.2)
fire("CHAT_MSG_COMBAT_XP_GAIN", "Crypt Fiend dies, you gain 80 experience. (+20 group bonus)")
run(1)
fire("CHAT_MSG_COMBAT_XP_GAIN", "Crypt Fiend dies, you gain 80 experience. (+20 group bonus)")
MinimalUIDB.bossNames = MinimalUIDB.bossNames or {}
MinimalUIDB.bossNames["Lord Rot"] = true
TARGET = { l = -1, cl = "elite" }
fire("PLAYER_TARGET_CHANGED")
run(0.5)
TARGET = nil
fire("PLAYER_TARGET_CHANGED")
fire("CHAT_MSG_COMBAT_XP_GAIN", "Lord Rot dies, you gain 300 experience.")
run(1)
LOOTS = { { item = 2589, guid = "Creature-0-1-2-3-250999-0000000001" } }
fire("LOOT_OPENED")
run(1)
''')
# a boss fight in a group: one thing dies; you did 400, two others 900 and 700 (30 of it past the kill)
rt.execute(r'''
METER = { ["Player-1-0001"] = { totalAmount = 400 }, ["Player-1-0002"] = { totalAmount = 900 },
          ["Player-1-0003"] = { totalAmount = 700, combatSpells = { { overkillAmount = 30 } } } }
C_DamageMeter = { GetCombatSessionSourceFromType = function(_, _, g) return METER[g] end }
local oldGUID = UnitGUID
function UnitGUID(u)
    if u == "party1" then return "Player-1-0002" elseif u == "party2" then return "Player-1-0003" end
    return oldGUID(u)
end
WORLD.combat = true
fire("PLAYER_REGEN_DISABLED")
run(1)
fire("CHAT_MSG_COMBAT_XP_GAIN", "Lord Rot dies, you gain 300 experience.")
WORLD.combat = false
fire("PLAYER_REGEN_ENABLED")
run(3)
''')
print('boss health worked out:', rt.eval('''(function() for id, r in pairs(MinimalUIDB.bestiary) do if r.n == "Lord Rot" then
    local t = {} for L, h in pairs(r.he or {}) do t[#t + 1] = "level " .. L .. ": " .. h end
    return table.concat(t, ", ") .. " | " .. tostring(MinimalUIDB.grouphp and MinimalUIDB.grouphp.sampled) end end end)()'''))
print('--- after a few kills inside (in a group)')
print(dump(WATCH + ",Lord Rot"))
print('numbered, no name yet:', rt.eval('(function() local t = {} for id, r in pairs(MinimalUIDB.bestiary) do if not r.n then t[#t + 1] = id .. " k=" .. tostring(r.k) .. " lk=" .. tostring(r.lk) .. " ln=" .. tostring(r.ln) end end return table.concat(t, "; ") end)()'))
rt.execute(r'''
INST, INSTKIND, INSTNAME, ZONE = false, nil, nil, "Undercity"
TIP[250999] = "Crypt Fiend"
fire("PLAYER_ENTERING_WORLD")
run(16)
''')
print('--- out of the dungeon (the looted one is asked its name)')
print(dump(WATCH + ",Lord Rot"))
print('folded:', rt.eval('(function() local t = {} for a, b in pairs(B.mergedTo) do t[#t + 1] = a .. " -> " .. b end return table.concat(t, "; ") end)()'))
print('rank shown for Lord Rot:', rt.eval('(function() for id, r in pairs(MinimalUIDB.bestiary) do if r.n == "Lord Rot" then return B.RankOf(r) end end end)()'))
print('--- the headings of the list')
print(rt.eval(r'''(function()
    local d, total, kills = B.ListData()
    local out = {}
    for _, row in ipairs(d) do
        if row.kind == "header" then out[#out + 1] = (row.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    end
    return table.concat(out, "\n") .. "\n(total " .. total .. ", kills " .. kills .. ")"
end)()'''))
print('--- rows for a dungeon creature')
print(rt.eval(r'''(function()
    for id, r in pairs(MinimalUIDB.bestiary) do
        if r.n == "Skeleton" then
            local rows = B.Rows({}, id, true)
            local out = {}
            for _, x in ipairs(rows) do
                local t = x.kind == "header" and ("[" .. tostring(x.text) .. "]") or (tostring(x.label) .. " " .. tostring(x.value))
                out[#out + 1] = (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            end
            return table.concat(out, " / ")
        end
    end
end)()'''))
inst = rt.eval('MinimalUIDB.instdiag')
tip = rt.eval('MinimalUIDB.bestiaryTip')
print('instance names seen:', dict(inst.items()) if inst else None)
print('tooltip lines seen:', list(tip.values()) if tip else None)
