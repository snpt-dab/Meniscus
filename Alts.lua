local _, ns = ...
local CreateFrame = ns.CreateFrame or CreateFrame

-- Alts: what your characters could craft for one another.
--
-- An addon only sees the character you are on, so each one leaves two
-- things on file as it plays (MinimalUIDB.roster[realm][name]):
--   what it wears    c class, l level, a heaviest armour, w weapon kinds it
--                    has the skill for, g = { [slot] = link }, t when
--   what it crafts   p[profession] = { t when, r = { [item made] =
--                    { n = recipe, m = { reagent, count, ... } } } }
--                    (gear only; written while its profession window is
--                    open: recipes can't be read at any other time)
--
-- From those, two questions are answered:
--   A.ForMe()        on any character: which crafted pieces, from any of
--                    your characters' recipes, beat what you wear now
--                    (the character window marks the slots and lists them)
--   A.ForAlts(item)  on a crafter: which of your other characters, as last
--                    seen, a piece would be an upgrade for (the professions
--                    window marks those recipes)
-- Both go by the same judging as the upgrade arrows in the bags
-- (ns.JudgeUpgrade, Theme.lua). Pieces wearable within AHEAD levels are
-- included and say from which level. Bind on pickup pieces count only for
-- the character that makes them.

local A = ns:NewModule("Alts", { enabled = true })
ns.Alts = A

local AHEAD = 3
local function secret(v) return issecretvalue and issecretvalue(v) end
local function plainStr(v) return type(v) == "string" and not secret(v) and v ~= "" end
local function plainNum(v) return type(v) == "number" and not secret(v) end

local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulders", [5] = "Chest", [6] = "Belt", [7] = "Legs",
                    [8] = "Boots", [9] = "Bracers", [10] = "Gloves", [11] = "Ring", [12] = "Ring", [13] = "Trinket",
                    [14] = "Trinket", [15] = "Cloak", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }
function A.SlotName(slot) return SLOT_NAME[slot] or "Gear" end
A.SLOT_ORDER = { 16, 17, 18, 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14 }

-- The skill line behind each kind of weapon (item subclass -> skill).
local WEAPON_SKILL = { [0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229, [7] = 43, [8] = 55,
                       [10] = 136, [13] = 162, [15] = 173, [16] = 176, [18] = 226, [19] = 228 }
-- Where a character's own skills were not to be read: what its class can
-- ever learn to hold.
local function set(...)
    local t = {}
    for i = 1, select("#", ...) do t[(select(i, ...))] = true end
    return t
end
local CLASS_WEAPON = {
    WARRIOR = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
    PALADIN = set(0, 1, 4, 5, 6, 7, 8),
    HUNTER  = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
    ROGUE   = set(2, 3, 4, 7, 13, 15, 16, 18),
    PRIEST  = set(4, 10, 15, 19),
    MAGE    = set(7, 10, 15, 19),
    WARLOCK = set(7, 10, 15, 19),
    SHAMAN  = set(0, 1, 4, 5, 10, 13, 15),
    DRUID   = set(4, 5, 6, 10, 13, 15),
}
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local TOOL = { [14] = true, [20] = true }

-- ── The book ──────────────────────────────────────────────────────────────
-- (0.1.654: GetRealmName() answers "" on this client, which is why nothing
-- was ever put on file. The realm is asked three ways; with none of them
-- answering, everything goes in one book, "-". Should a realm name turn
-- up later, that book is folded into the realm's.)
local NOREALM = "-"
local function ident()
    local name = UnitName("player")
    if not plainStr(name) then return end
    -- (The one realm name the whole addon goes by: Core's, remembered
    -- from a login where the game gave it.)
    local realm = ns.RealmName and ns:RealmName() or nil
    if not plainStr(realm) then realm = nil end
    local db = MinimalUIDB
    local roster = db and type(db.roster) == "table" and db.roster or nil
    -- (0.1.673: books kept under another spelling of this realm are
    -- folded in as well. For a few versions the realm was asked three
    -- ways, and one of them answers without the spaces: characters read
    -- then sat in a book of their own and the Roster never showed them.
    -- Of two records of one character, the later reading stays.)
    if realm and roster then
        local function bare(r) return (r:gsub("[%s%-']", "")):lower() end
        local mine = bare(realm)
        local fold = {}
        for k, book in pairs(roster) do
            -- (Or a short form of it: one of the three ways gave only
            -- the realm name's first word.)
            local bk = type(k) == "string" and bare(k) or ""
            if k ~= realm and type(k) == "string" and type(book) == "table"
                and (k == NOREALM or bk == mine or (#bk >= 4 and mine:sub(1, #bk) == bk)) then
                fold[#fold + 1] = k
            end
        end
        for _, k in ipairs(fold) do
            roster[realm] = type(roster[realm]) == "table" and roster[realm] or {}
            for who, ch in pairs(roster[k]) do
                local had = roster[realm][who]
                if type(had) ~= "table" or (type(ch) == "table" and (ch.t or 0) > (had.t or 0)) then
                    roster[realm][who] = ch
                end
            end
            roster[k] = nil
        end
    end
    return name, realm or NOREALM
end
local function realmBook(create)
    local db = MinimalUIDB
    if not db then return end
    local name, realm = ident()
    if not name then return end
    if create then
        db.roster = db.roster or {}
        db.roster[realm] = db.roster[realm] or {}
    end
    local book = type(db.roster) == "table" and db.roster[realm] or nil
    if type(book) ~= "table" then return end
    return book, name
end

local makers            -- [item] = { { who, prof, n, m, me, c }, ... }
local mine              -- A.ForMe()'s answer, until something changes
local verdict = {}      -- [item] = false / an entry: settled answers for this character
local altVerdict = {}   -- [item] = false / a list: settled answers for the others
local waiting = false   -- something was asked of the game and has not come
local listeners = {}
function A.Listen(fn) listeners[#listeners + 1] = fn end
local fireQueued = false
local function fire()
    if fireQueued then return end
    fireQueued = true
    C_Timer.After(0.4, function()
        fireQueued = false
        for _, fn in ipairs(listeners) do pcall(fn) end
    end)
end
local function forget(all)
    mine = nil
    if all then
        makers = nil
        wipe(verdict)
        wipe(altVerdict)
    end
end

-- (0.1.652: after a client restart the record held no roster and no note
-- at all, and every call here was under a bare pcall, so there was nothing
-- to say why. Now each step leaves a word in MinimalUIDB.alttrail, and a
-- failure leaves its message.)
local trail = {}
local function mark(k, v)
    trail[k] = v
    local db = MinimalUIDB
    if not db then return end
    local parts = {}
    for name, val in pairs(trail) do parts[#parts + 1] = name .. ": " .. tostring(val) end
    table.sort(parts)
    db.alttrail = table.concat(parts, " | ")
end
local function kind(v) return v == nil and "nil" or (secret(v) and "hidden") or (v == "" and "empty") or type(v) end
local function snapshot(fromChange)
    local book, name = realmBook(true)
    if not book then
        local okN, n = pcall(UnitName, "player")
        local okR, r = pcall(GetRealmName)
        mark("no book", "saved table " .. kind(MinimalUIDB) .. ", name " .. (okN and kind(n) or "failed")
            .. ", realm " .. (okR and kind(r) or "failed"))
        return
    end
    mark("book", "ok")
    local me = book[name]
    if type(me) ~= "table" then me = {}; book[name] = me end
    local _, cls = UnitClass("player")
    local lvl = UnitLevel("player")
    if plainStr(cls) then me.c = cls end
    if plainNum(lvl) and lvl > 0 then me.l = lvl end
    -- (0.1.707: which side it is on, "Alliance" / "Horde". Kept, not yet
    -- used: whether this game lets your characters of opposite sides send
    -- each other things is for the player to say, not for us to assume.)
    local okF, side = pcall(UnitFactionGroup, "player")
    if okF and plainStr(side) then me.fa = side end
    local okA, best = pcall(ns.BestArmor)
    if okA and plainNum(best) then me.a = best end
    me.t = time()
    local g, any = {}, false
    for _, slot in ipairs(GEAR_SLOTS) do
        local ok, link = pcall(GetInventoryItemLink, "player", slot)
        if ok and plainStr(link) then g[slot] = link; any = true end
    end
    -- (Right after logging in the game may not have your gear yet: an
    -- empty reading only replaces a full one when it follows a change.)
    if any or fromChange or type(me.g) ~= "table" then me.g = g end
    local S = _G.C_SkillInfo
    if S and S.GetSkillLineInfoByID then
        local w, n = {}, 0
        for subID, skill in pairs(WEAPON_SKILL) do
            local ok, info = pcall(S.GetSkillLineInfoByID, skill)
            local rank = ok and type(info) == "table" and (info.maxRank or info.rank) or nil
            if plainNum(rank) and rank > 0 then w[subID] = true; n = n + 1 end
        end
        -- (None at all, or every one of them: the reading says nothing.)
        if n > 0 and n < 15 then me.w = w else me.w = nil end
        if MinimalUIDB then MinimalUIDB.altdiag = "weapon skills read: " .. n .. " of 15 known" end
    end
    -- (0.1.670, for the Roster tab: the rest of a character's sheet as
    -- it stood. Each thing is kept only when the game gives it plainly:
    -- in a fight some of it is hidden, and the last good reading stays.)
    local function keep(key, fn, ...)
        local ok, v = pcall(fn, ...)
        if ok and (plainNum(v) or plainStr(v)) then me[key] = v end
    end
    keep("r", function() local r = UnitRace("player"); return r end)
    -- (0.1.672, for the full sheet of an alt: race number and sex, to
    -- stand a model up in its gear; resistances.)
    keep("ri", function() local _, _, id = UnitRace("player"); return id end)
    keep("sx", UnitSex, "player")
    do
        local rs, all = {}, true
        for school = 2, 6 do
            local ok, _, _, total = pcall(UnitResistance, "player", school) -- (base, real, EFFECTIVE, bonus: the game shows the third)
            if ok and plainNum(total) then rs[school] = total else all = false end
        end
        if all then me.rs = rs end
    end
    keep("z", function() return (GetRealZoneText and GetRealZoneText()) or GetZoneText() end)
    keep("m", GetMoney)
    keep("hp", UnitHealthMax, "player")
    keep("mp", UnitPowerMax, "player")
    keep("pt", function() local _, token = UnitPowerType("player"); return token end)
    keep("ar", function() local _, eff = UnitArmor("player"); return eff end)
    keep("xp", function()
        local x, mx = UnitXP("player"), UnitXPMax("player")
        if plainNum(x) and plainNum(mx) and mx > 0 then return math.floor(x / mx * 100 + 0.5) end
    end)
    keep("rx", function() local e = GetXPExhaustion and GetXPExhaustion(); return plainNum(e) and e or 0 end)
    local st, full = {}, true
    for i = 1, 5 do
        local ok, _, eff = pcall(UnitStat, "player", i)
        if ok and plainNum(eff) then st[i] = eff else full = false end
    end
    if full then me.s = st end
    -- Professions and their ranks (primary, then secondary).
    if GetProfessions and GetProfessionInfo then
        local okP, a, b, arch, fish, cook, aid = pcall(GetProfessions)
        if okP then
            local list = {}
            for _, idx in ipairs({ a or false, b or false, cook or false, fish or false, aid or false, arch or false }) do
                if idx then
                    local okI, name, _, rank, maxRank = pcall(GetProfessionInfo, idx)
                    if okI and plainStr(name) and plainNum(rank) then
                        list[#list + 1] = name
                        list[#list + 1] = rank
                        list[#list + 1] = plainNum(maxRank) and maxRank or 0
                    end
                end
            end
            if #list > 0 or not fromChange then me.pr = list end
        end
    end
    mark("snapshot", "done")
end
local snapN = 0
local function snap(fromChange, why)
    snapN = snapN + 1
    local ok, err = pcall(snapshot, fromChange)
    mark("calls", snapN .. " (last: " .. why .. ")")
    if not ok then mark("failed", tostring(err):sub(1, 200)) end
end

-- A recipe that makes gear, as the professions window reads it.
function ns.RecordCraft(prof, name, item, list)
    if not A.on then return end
    if not (plainStr(prof) and plainStr(name) and plainNum(item)) then return end
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, item)
    if not ok or not (ns.EquipSlots and ns.EquipSlots[loc]) then return end
    local book, me = realmBook(true)
    if not book then return end
    local ch = book[me]
    if type(ch) ~= "table" then ch = {}; book[me] = ch end
    ch.p = type(ch.p) == "table" and ch.p or {}
    local P = ch.p[prof]
    if type(P) ~= "table" or type(P.r) ~= "table" then P = { r = {} }; ch.p[prof] = P end
    P.t = time()
    local m = {}
    for _, rg in ipairs(type(list) == "table" and list or {}) do
        if plainNum(rg.itemID) then
            m[#m + 1] = rg.itemID
            m[#m + 1] = plainNum(rg.need) and rg.need or 1
        end
    end
    local old = P.r[item]
    P.r[item] = { n = name, m = m }
    if not old then
        makers = nil
        mine = nil
        fire()
    end
end

-- One side only (0.1.708; the player, 2026-11-25: characters of opposite
-- sides can't send each other gear in this game). A character's side is
-- what it wrote down when last played (fa), else what the game says of its
-- race; where neither is known it is let through, as before.
local function sideOf(ch)
    if plainStr(ch.fa) then return ch.fa end
    local CI = _G.C_CreatureInfo
    if plainNum(ch.ri) and CI and CI.GetFactionInfo then
        local ok, info = pcall(CI.GetFactionInfo, ch.ri)
        if ok and type(info) == "table" and plainStr(info.groupTag) then return info.groupTag end
    end
end
local function sameSide(ch)
    local ok, mine = pcall(UnitFactionGroup, "player")
    local theirs = sideOf(ch)
    if not (ok and plainStr(mine) and theirs) then return true end
    return mine == theirs
end
A.SameSide = sameSide

local function buildMakers()
    makers = {}
    local book, myName = realmBook()
    if not book then return end
    for name, ch in pairs(book) do
        if type(ch) == "table" and type(ch.p) == "table" and (name == myName or sameSide(ch)) then
            for prof, P in pairs(ch.p) do
                if type(P) == "table" and type(P.r) == "table" then
                    for item, rec in pairs(P.r) do
                        if type(item) == "number" and type(rec) == "table" then
                            local t = makers[item]
                            if not t then t = {}; makers[item] = t end
                            t[#t + 1] = { who = name, prof = prof, n = rec.n, m = rec.m, me = name == myName, c = ch.c }
                        end
                    end
                end
            end
        end
    end
end

-- What the game knows of an item; nil (and asked for, once) when it has
-- not fetched it this session.
local asked = {}
local function ask(id)
    waiting = true
    if asked[id] then return end
    asked[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end
local function itemInfo(id)
    local ok, name, link, quality, _, minLevel, _, _, _, loc, icon, _, classID, subID, bind = pcall(C_Item.GetItemInfo, id)
    if not ok or not plainStr(name) or not plainStr(link) then ask(id) return nil end
    return name, link, quality, minLevel, loc, icon, classID, subID, bind
end

-- ── On any character: what could be made for you ─────────────────────────
local function levelLine(why, minLevel)
    local fmt = _G.ITEM_MIN_LEVEL
    if type(fmt) == "string" then
        local ok, s = pcall(string.format, fmt, minLevel)
        if ok and s == why then return true end
    end
    return why:find("%f[%d]" .. minLevel .. "%f[%D]") ~= nil and why:lower():find("level", 1, true) ~= nil
end
-- (0.1.741, MinimalUIDB.craftwhy: the mark was said not to come for empty
-- slots. For a craftable piece that goes in a slot of yours that is EMPTY,
-- what was decided and why. Item names only. Rewritten each session.)
local craftwhy
local function whyMine(name, loc, minLevel, word)
    if not MinimalUIDB then return end
    local slots = ns.EquipSlots and ns.EquipSlots[loc]
    if type(slots) ~= "table" then return end
    local bare
    for _, s in ipairs(slots) do
        if not GetInventoryItemLink("player", s) then bare = s break end
    end
    if not bare then return end
    if not craftwhy then craftwhy = { n = 0 }; MinimalUIDB.craftwhy = craftwhy end
    local key = name .. " (slot " .. bare .. ", needs level " .. tostring(minLevel) .. ")"
    if craftwhy[key] == nil then
        if craftwhy.n >= 80 then return end
        craftwhy.n = craftwhy.n + 1
    end
    craftwhy[key] = word
end
local function judgeMine(item, who, lvl)
    local name, link, quality, minLevel, loc, icon, _, _, bind = itemInfo(item)
    if not name then return nil end
    local res, slot, gain = ns.JudgeUpgrade(link)
    if res == nil then waiting = true whyMine(name, loc, minLevel, "its figures have not come yet") return nil end
    if not res then whyMine(name, loc, minLevel, "judged no better than what is worn") return false end
    local from = {}
    for _, m in ipairs(who) do
        if m.me or bind ~= 1 then from[#from + 1] = m end
    end
    if #from == 0 then whyMine(name, loc, minLevel, "binds to its maker, who is not you") return false end
    local soon
    local why = ns.ItemUnusable(link)
    if why then
        if plainNum(minLevel) and plainNum(lvl) and minLevel > lvl and minLevel - lvl <= AHEAD and levelLine(why, minLevel) then
            soon = minLevel
        elseif plainNum(minLevel) and plainNum(lvl) and minLevel > lvl and levelLine(why, minLevel) then
            -- (0.1.742) Too many levels away for a mark, but worth a line
            -- in the slot's tooltip: what is coming, and from when.
            whyMine(name, loc, minLevel, "later: more than " .. AHEAD .. " levels away")
            return { item = item, link = link, name = name, icon = icon, q = quality, slot = slot, gain = gain or 0,
                     later = minLevel, from = from }
        else
            whyMine(name, loc, minLevel, "you can't use it: " .. tostring(why))
            return false
        end
    end
    whyMine(name, loc, minLevel, "marked, slot " .. tostring(slot))
    return { item = item, link = link, name = name, icon = icon, q = quality, slot = slot, gain = gain or 0, soon = soon, from = from }
end

local EMPTY = { bySlot = {}, list = {}, later = {}, pending = false, makers = 0 }
local ORDER_OF = {}
for i, slot in ipairs(A.SLOT_ORDER) do ORDER_OF[slot] = i end
local function byGain(a, b)
    if (a.soon and 1 or 0) ~= (b.soon and 1 or 0) then return not a.soon end
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.name < b.name
end
local function bySlotThenGain(a, b)
    local oa, ob = ORDER_OF[a.slot] or 99, ORDER_OF[b.slot] or 99
    if oa ~= ob then return oa < ob end
    return byGain(a, b)
end
function A.ForMe()
    if not A.on then return EMPTY end
    if mine then return mine end
    if not makers then buildMakers() end
    local out = { bySlot = {}, list = {}, later = {}, pending = false, makers = 0 }
    local lvl = UnitLevel("player")
    for item, who in pairs(makers) do
        out.makers = out.makers + 1
        local v = verdict[item]
        if v == nil then
            local ok, r = pcall(judgeMine, item, who, lvl)
            if ok then v = r else v = false end
            if v ~= nil then verdict[item] = v end
        end
        if v == nil then
            out.pending = true
        elseif v and v.later then
            local slot = v.slot or 0
            local t = out.later[slot]
            if not t then t = {}; out.later[slot] = t end
            t[#t + 1] = v
        elseif v then
            out.list[#out.list + 1] = v
            local slot = v.slot or 0
            local t = out.bySlot[slot]
            if not t then t = {}; out.bySlot[slot] = t end
            t[#t + 1] = v
        end
    end
    table.sort(out.list, bySlotThenGain)
    for _, t in pairs(out.bySlot) do table.sort(t, byGain) end
    for _, t in pairs(out.later) do
        table.sort(t, function(a, b) if a.later ~= b.later then return a.later < b.later end return a.name < b.name end)
    end
    mine = out
    return out
end

-- ── On a crafter: who a piece would be an upgrade for ────────────────────
local function usableBy(ch, minLevel, classID, subID)
    if plainNum(minLevel) and minLevel > ch.l + AHEAD then return false end
    local soon = plainNum(minLevel) and minLevel > ch.l and minLevel or nil
    if classID == 4 and type(subID) == "number" then
        if subID >= 1 and subID <= 4 then
            if plainNum(ch.a) and subID > ch.a then return false end
        elseif subID == 6 then
            if not SHIELD[ch.c] then return false end
        elseif subID > 6 then
            return false
        end
    elseif classID == 2 then
        if TOOL[subID] then return false end
        if type(ch.w) == "table" then
            if not ch.w[subID] then return false end
        else
            local cw = CLASS_WEAPON[ch.c]
            if cw and not cw[subID] then return false end
        end
    end
    return true, soon
end
local gearAsked = {}
local function askGear(name, ch)
    waiting = true
    if gearAsked[name] then return end
    gearAsked[name] = true
    for _, link in pairs(ch.g) do
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then ask(id) end
    end
end
function A.ForAlts(item)
    if not A.on or not plainNum(item) then return nil end
    local v = altVerdict[item]
    if v ~= nil then return v or nil end
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, item)
    if not ok or not (ns.EquipSlots and ns.EquipSlots[loc]) then altVerdict[item] = false return nil end
    local book, myName = realmBook()
    if not book then return nil end
    local name, link, _, minLevel, _, _, classID, subID, bind = itemInfo(item)
    if not name then return nil end
    if bind == 1 then altVerdict[item] = false return nil end
    local list, pending = {}, false
    for altName, ch in pairs(book) do
        if altName ~= myName and type(ch) == "table" and type(ch.g) == "table" and plainStr(ch.c) and plainNum(ch.l) and sameSide(ch) then
            local can, soon = usableBy(ch, minLevel, classID, subID)
            -- (0.1.733, MinimalUIDB.altwhy: for a weapon, what was decided
            -- for each of the others, by class and level only: no names.)
            local function why(word)
                if classID ~= 2 or not MinimalUIDB then return end
                local t = MinimalUIDB.altwhy
                if type(t) ~= "table" then t = {}; MinimalUIDB.altwhy = t end
                local key = tostring(item) .. " (kind " .. tostring(subID) .. ", needs level " .. tostring(minLevel) .. ") for " .. ch.c .. " " .. ch.l
                if t[key] == nil then
                    local n = 0
                    for _ in pairs(t) do n = n + 1 end
                    if n >= 80 then return end
                end
                t[key] = word
            end
            if not can then
                why((plainNum(minLevel) and minLevel > ch.l + AHEAD) and "left out: more than " .. AHEAD .. " levels away"
                    or "left out: cannot hold this kind")
            end
            if can then
                local okJ, res, slot, gain = pcall(ns.JudgeUpgrade, link, ch)
                if not okJ then res = false end
                why(res == nil and "waiting for its gear to be read" or (res and ("upgrade, slot " .. tostring(slot) .. ", gain " .. tostring(gain))
                    or "not better than what is worn"))
                if res == nil then
                    pending = true
                    askGear(altName, ch)
                elseif res then
                    list[#list + 1] = { who = altName, c = ch.c, l = ch.l, slot = slot, soon = soon, gain = gain or 0,
                                        worn = slot and ch.g[slot] or nil, t = ch.t, link = link }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.who < b.who end)
    if not pending then altVerdict[item] = #list > 0 and list or false end
    return #list > 0 and list or nil
end

-- How many of your other characters are on file with their gear (the
-- professions window only offers its filter when there is one).
function A.Others()
    if not A.on then return 0 end
    local book, myName = realmBook()
    local n = 0
    for name, ch in pairs(book or {}) do
        if name ~= myName and type(ch) == "table" and type(ch.g) == "table" and next(ch.g) and sameSide(ch) then n = n + 1 end
    end
    return n
end

-- Everyone on file, for the Roster tab: you first, then by level, then
-- by name. Each: { who, me, ch } (ch is the saved record itself: read it,
-- do not write to it).
function A.Roster()
    local out = {}
    if not A.on then return out end
    local book, myName = realmBook()
    for name, ch in pairs(book or {}) do
        if type(ch) == "table" then out[#out + 1] = { who = name, me = name == myName, ch = ch } end
    end
    table.sort(out, function(x, y)
        if x.me ~= y.me then return x.me end
        local lx, ly = x.ch.l or 0, y.ch.l or 0
        if lx ~= ly then return lx > ly end
        return x.who < y.who
    end)
    return out
end
-- Read this character now (the Roster tab asks when it is opened, so that
-- your own line is of this minute).
function A.ReadNow() pcall(snapshot, false) end

-- "3 days ago", for how old a character's last reading is.
function A.Ago(t)
    if not plainNum(t) then return "some time ago" end
    local d = time() - t
    if d < 3600 then return "within the hour" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    local days = math.floor(d / 86400)
    return days .. (days == 1 and " day ago" or " days ago")
end
function A.ClassHex(c)
    local cc = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
    if not cc then return "|cffdbdbe3" end
    return string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
end

-- The body this character wears, as the game numbers it (0.1.675): what
-- another character of yours needs to stand a figure of this one up on its
-- full sheet (Inspect.lua), since no model here can be told a race and
-- sex. Measured the way the bestiary measures a creature's look: an unseen
-- model is shown you and asked what it drew. Kept as `di` (the body) and
-- `mf` (its model file). Not while a druid or shaman wears another shape.
local figFrame
local function measureFigure(tries)
    tries = tries or 0
    local book, name = realmBook(false)
    local me = book and book[name]
    if type(me) ~= "table" then
        if tries < 5 then C_Timer.After(10, function() pcall(measureFigure, tries + 1) end) end
        return
    end
    local _, cls = UnitClass("player")
    if cls == "DRUID" or cls == "SHAMAN" then
        local okF, form = pcall(GetShapeshiftForm)
        if not (okF and plainNum(form) and form == 0) then
            if tries < 20 then C_Timer.After(60, function() pcall(measureFigure, tries + 1) end) end
            return
        end
    end
    if not figFrame then
        local ok, m = pcall(CreateFrame, "PlayerModel", nil, UIParent)
        if not ok or not m then return end
        m:SetSize(4, 4)
        m:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        m:SetAlpha(0)
        m:EnableMouse(false)
        figFrame = m
    end
    local m = figFrame
    local function say(str) if MinimalUIDB then MinimalUIDB.figdiag = str end end
    if type(m.GetDisplayInfo) ~= "function" then return say("own body: the model can not be asked") end
    m:Show()
    if not pcall(m.SetUnit, m, "player") then return say("own body: the model would not be shown you") end
    local n = 0
    local function read()
        n = n + 1
        local okD, d = pcall(m.GetDisplayInfo, m)
        local okM, mf = false, nil
        if type(m.GetModelFileID) == "function" then okM, mf = pcall(m.GetModelFileID, m) end
        local got = okD and plainNum(d) and d > 0
        if got then me.di = d end
        if okM and plainNum(mf) and mf > 0 then me.mf = mf end
        if got or n >= 8 then
            pcall(m.ClearModel, m)
            m:Hide()
            say("own body: number " .. (got and tostring(d) or "not had") .. ", model file " .. tostring(me.mf or "not had")
                .. ", race " .. tostring(me.ri) .. ", sex " .. tostring(me.sx))
        else
            C_Timer.After(0.5, read)
        end
    end
    C_Timer.After(0.5, read)
end

function A:OnInit(db)
    self.db = db
    A.on = true
    C_Timer.After(9, function() pcall(measureFigure, 0) end)
    mark("started", date and date("%H:%M:%S") or "yes")
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED",
                         "PLAYER_LOGOUT" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local snapQueued = false
    ev:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_LOGOUT" then
            snap(false, "logout")
        elseif e == "GET_ITEM_INFO_RECEIVED" then
            if waiting then
                waiting = false
                if mine and mine.pending then mine = nil end
                fire()
            end
        elseif not snapQueued then
            snapQueued = true
            local change = e == "PLAYER_EQUIPMENT_CHANGED"
            C_Timer.After(1, function()
                snapQueued = false
                snap(change, e)
                wipe(verdict)
                mine = nil
                fire()
            end)
        end
    end)
    C_Timer.After(6, function() snap(false, "login") end)
    -- (And once more, in case the first came before the game had a name.)
    C_Timer.After(20, function() if not (MinimalUIDB and MinimalUIDB.roster) then snap(false, "second try") end end)
end

-- /men alts: who is on file, and when each was last read.
ns.commands.alts = function(rest)
    if rest == "forget" then
        local db = MinimalUIDB
        local _, realm = ident()
        if db and db.roster and realm then db.roster[realm] = nil end
        forget(true)
        pcall(snapshot, false)
        ns:Print("Alts: the characters on file for this realm were cleared. Each one is read again when you next play it.")
        return
    end
    local book, myName = realmBook()
    if not A.on or not book then
        ns:Print("Alts: nothing on file yet.", A.on and ("(" .. tostring(MinimalUIDB and MinimalUIDB.alttrail) .. ")") or "(switched off)")
        return
    end
    for name, ch in pairs(book) do
        if type(ch) == "table" then
            local profs = {}
            for prof, P in pairs(type(ch.p) == "table" and ch.p or {}) do
                local n = 0
                for _ in pairs(type(P) == "table" and type(P.r) == "table" and P.r or {}) do n = n + 1 end
                profs[#profs + 1] = prof .. " (" .. n .. " gear recipes)"
            end
            ns:Print(A.ClassHex(ch.c) .. name .. "|r" .. (name == myName and " (you)" or "") .. ": level " .. tostring(ch.l or "?")
                .. ", gear read " .. A.Ago(ch.t) .. (#profs > 0 and ("; " .. table.concat(profs, ", ")) or "; no recipes read"))
        end
    end
end
