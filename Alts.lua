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
                       [10] = 136, [13] = 473, [15] = 173, [16] = 176, [18] = 226, [19] = 228 }
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
local function ident()
    local name = UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if not plainStr(name) or not plainStr(realm) then return end
    return name, realm
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

local function buildMakers()
    makers = {}
    local book, myName = realmBook()
    if not book then return end
    for name, ch in pairs(book) do
        if type(ch) == "table" and type(ch.p) == "table" then
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
local function judgeMine(item, who, lvl)
    local name, link, quality, minLevel, _, icon, _, _, bind = itemInfo(item)
    if not name then return nil end
    local res, slot, gain = ns.JudgeUpgrade(link)
    if res == nil then waiting = true return nil end
    if not res then return false end
    local from = {}
    for _, m in ipairs(who) do
        if m.me or bind ~= 1 then from[#from + 1] = m end
    end
    if #from == 0 then return false end
    local soon
    local why = ns.ItemUnusable(link)
    if why then
        if plainNum(minLevel) and plainNum(lvl) and minLevel > lvl and minLevel - lvl <= AHEAD and levelLine(why, minLevel) then
            soon = minLevel
        else
            return false
        end
    end
    return { item = item, link = link, name = name, icon = icon, q = quality, slot = slot, gain = gain or 0, soon = soon, from = from }
end

local EMPTY = { bySlot = {}, list = {}, pending = false, makers = 0 }
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
    local out = { bySlot = {}, list = {}, pending = false, makers = 0 }
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
        if altName ~= myName and type(ch) == "table" and type(ch.g) == "table" and plainStr(ch.c) and plainNum(ch.l) then
            local can, soon = usableBy(ch, minLevel, classID, subID)
            if can then
                local okJ, res, slot, gain = pcall(ns.JudgeUpgrade, link, ch)
                if not okJ then res = false end
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
        if name ~= myName and type(ch) == "table" and type(ch.g) == "table" and next(ch.g) then n = n + 1 end
    end
    return n
end

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

function A:OnInit(db)
    self.db = db
    A.on = true
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
