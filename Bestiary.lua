local _, ns = ...
local CreateFrame = ns.CreateFrame or CreateFrame
local T = ns.Theme

-- Bestiary (0.1.560): what you have learned of the creatures you meet, kept
-- as you go and browsable (/men bestiary, or from the inspect window on a
-- creature). The record began in Inspect.lua (0.1.530) as "what you have
-- seen"; it lives here now and notes more.
--
-- One small record for each KIND of creature (not each one), written only
-- when something is learned:
--   MinimalUIDB.bestiary[npcID] = {
--     n  = name,            lo, hi = levels seen,
--     t  = kind (Beast),    f = family (Cat),   cl = rank (elite, rare...),
--     ag = 1 hostile / 0 neutral,
--     z  = { [zone] = true }            where (6 at most),
--     dsp = { [display id] = true }     its looks (0.1.575, 12 at most):
--          one creature can wear several bodies (a Southsea Brigand is a
--          gnoll, a troll, a human... and still the one creature to the
--          game, with one set of numbers),
--     hp = { [level] = health }         its full health at that level,
--     he = { [level] = health worked out from your damage (the least seen) },
--     hn = { [level] = kills that went into he }   (0.1.577, below),
--     c  = { [spell name] = spell id or true }   what it casts (16): cast
--          bars, and since 0.1.579 casts with no bar (instant ones) where
--          the game says what they were,
--     db = { [debuff name] = spell id or true }  what it leaves on you (12):
--          the debuffs found on you when a fight with it ends,
--     hit = { [attack name] = hardest hit on you } (from death recaps),
--     q  = { { t = what it said, k = "yell" / "emote" / nil (said),
--              l = language, u = true when you did not understand it } } (12),
--     k  = kills,           kd = times it killed you,
--     ln = corpses of it you have looted,   lk = kills since loot was
--          counted (0.1.571): the loot rates are out of the larger,
--     l  = { [itemID] = corpses that had it }   its loot table (60 items),
--     d  = { [itemID] = times }         older tallies, from before corpses
--                                       were counted (quest items, green+)
--   }
-- Where it comes from: whatever you target, point at, or see a nameplate
-- of (name, level, kind, health when the game will say it); cast bars on
-- your target and on nameplates; a death with it targeted and yours (a
-- kill); the loot window; and the death recap, which is the only place an
-- attack without a cast bar and the size of a hit can be read: there is no
-- combat log for addons on this client.

local B = ns:NewModule("Bestiary", { enabled = true, collapsed = {} })
ns.Bestiary = B

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local FILL = { 0.06, 0.06, 0.07, 0.97 }
local ELITE, RARE = { 0.95, 0.76, 0.34, 1 }, { 0.62, 0.78, 0.96, 1 }
local RED = { 0.92, 0.38, 0.35, 1 }
local RANK = { elite = "Elite", rareelite = "Rare elite", rare = "Rare", worldboss = "Boss" }
local MELEE_ICON = "Interface/Icons/Ability_MeleeDamage"

local function secret(v) return issecretvalue and issecretvalue(v) end
local call = ns.Call
local function plain(v) return type(v) == "number" and not secret(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" end
local function isTrue(v) return not secret(v) and v == true end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end
local nameIndex -- (name to id, built when first asked for; thrown away when a creature is added)

-- ── The record ────────────────────────────────────────────────────────────
local function npcOf(guid)
    if type(guid) ~= "string" or secret(guid) then return end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
local function npcID(unit)
    local g = call(UnitGUID, unit)
    local id = npcOf(g)
    if id then return id, g end
end
local function record(id, make)
    if not (id and MinimalUIDB) then return end
    local all = MinimalUIDB.bestiary
    if not all then
        if not make then return end
        all = {}; MinimalUIDB.bestiary = all
    end
    local r = all[id]
    if not r and make then r = {}; all[id] = r end
    return r
end
B.npcID, B.record = npcID, record

-- ── What other players have learned ───────────────────────────────────────
-- (0.1.571) BestiaryData.lua, shipped with the addon, is everyone's
-- records put together (dist/bestiary_merge.py, from the files players
-- send: "/men bestiary export", then "Share Bestiary.bat"). It is read
-- only. What is shown of a creature is that and your own record as one:
-- names and kinds from yours first, levels and health the widest, attacks,
-- zones and speech together, loot counts added up. Your kills, your
-- deaths and the list of what you have met stay your own.
-- Your own counts must not be added twice once your file is part of the
-- shipped data: the data names who is in it and which export of theirs
-- (from[who] = time of export), and each export leaves a note here of the
-- counts it sent (MinimalUIDB.bestiarySent[time]), which are taken off.
local SH = ns.BestiaryShared or {}
SH.r, SH.from = SH.r or {}, SH.from or {}
local views = {}
local function sentCounts()
    local who = MinimalUIDB and MinimalUIDB.bestiaryWho
    local at = who and SH.from[who]
    if not at then return nil, false end
    return MinimalUIDB.bestiarySent and MinimalUIDB.bestiarySent[at] or nil, true
end
local function addCount(own, shared, sent, included)
    own, shared = own or 0, shared or 0
    if not included then return own + shared end
    if sent then return math.max(own, own + shared - sent) end
    return math.max(own, shared) -- (yours is in there, how much is not known)
end
local function view(id)
    local own = record(id)
    local sh = SH.r[id]
    if not sh then return own end
    local v = views[id]
    if v then return v end
    local met = own ~= nil and own.n ~= nil
    own = own or {}
    local sent, included = sentCounts()
    local s = sent and (sent[id] or {})
    v = { shared = true, met = met, n = own.n or sh.n, t = own.t or sh.t, f = own.f or sh.f,
          cl = own.cl or sh.cl, ag = own.ag or sh.ag, k = own.k, kd = own.kd, d = own.d }
    v.lo = (own.lo and sh.lo) and math.min(own.lo, sh.lo) or own.lo or sh.lo
    v.hi = (own.hi and sh.hi) and math.max(own.hi, sh.hi) or own.hi or sh.hi
    if not v.hi then v.lo = nil end
    for _, key in ipairs({ "z", "c", "hp", "hit", "dsp", "db" }) do
        if own[key] or sh[key] then
            local t = {}
            for k, val in pairs(sh[key] or {}) do t[k] = val end
            for k, val in pairs(own[key] or {}) do
                local have = t[k]
                if have == nil or have == true or (type(val) == "number" and type(have) == "number" and val > have) then t[k] = val end
            end
            v[key] = t
        end
    end
    if own.he or sh.he then
        v.he, v.hn = {}, {}
        for _, src in ipairs({ sh, own }) do
            for l, h in pairs(src.he or {}) do
                if not v.he[l] or h < v.he[l] then v.he[l] = h end
                v.hn[l] = (v.hn[l] or 0) + (src.hn and src.hn[l] or 1)
            end
        end
    end
    if own.q or sh.q then
        local q, has = {}, {}
        for _, list in ipairs({ own.q or {}, sh.q or {} }) do
            for _, line in ipairs(list) do
                if not has[line.t] and #q < 16 then has[line.t] = true; q[#q + 1] = line end
            end
        end
        v.q = q
    end
    v.ln = addCount(own.ln, sh.ln, s and (s.ln or 0), included)
    v.lk = addCount(own.lk, sh.lk, s and (s.lk or 0), included)
    if own.l or sh.l then
        v.l = {}
        for item in pairs(sh.l or {}) do v.l[item] = true end
        for item in pairs(own.l or {}) do v.l[item] = true end
        for item in pairs(v.l) do
            v.l[item] = addCount(own.l and own.l[item], sh.l and sh.l[item], s and (s.l and s.l[item] or 0), included)
        end
    end
    views[id] = v
    return v
end
B.view = view

-- Something was learned: whoever shows it redraws (soon, not now).
local listeners = {}
function B.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed(id)
    if id then views[id] = nil else wipe(views) end
    for _, fn in ipairs(listeners) do pcall(fn, id) end
end

-- "/men bestiary export": your records, without your kills and deaths, set
-- down where "Share Bestiary.bat" can lift them out of the saved file
-- (MinimalUIDB.bestiaryOut, written at the next reload or logout), under a
-- made-up id that says only "the same sender as before".
local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and copy(v) or v end
    return c
end
local function export()
    local all = MinimalUIDB and MinimalUIDB.bestiary
    if not all or not next(all) then return ns:Print("Nothing in the bestiary to share yet.") end
    local who = MinimalUIDB.bestiaryWho
    if not who then
        who = string.format("%06x%06x%06x", math.random(0, 0xffffff), math.random(0, 0xffffff), math.random(0, 0xffffff))
        MinimalUIDB.bestiaryWho = who
    end
    local at = time()
    local out, snap, n = {}, {}, 0
    for id, r in pairs(all) do
        if r.n then
            local c = {}
            for k, v in pairs(r) do
                if k ~= "k" and k ~= "kd" and k ~= "d" then c[k] = type(v) == "table" and copy(v) or v end
            end
            out[id] = c
            n = n + 1
            if r.ln or r.lk or r.l then snap[id] = { ln = r.ln, lk = r.lk, l = r.l and copy(r.l) or nil } end
        end
    end
    MinimalUIDB.bestiaryOut = { v = 1, who = who, at = at, r = out }
    local sent = MinimalUIDB.bestiarySent or {}
    MinimalUIDB.bestiarySent = sent
    sent[at] = snap
    local stamps = {}
    for t in pairs(sent) do stamps[#stamps + 1] = t end
    table.sort(stamps)
    for i = 1, #stamps - 4 do sent[stamps[i]] = nil end -- (the last four exports' notes are kept)
    ns:Print(n .. " creatures set down for sharing. Reload (/reload) or log out, then double-click \"Share Bestiary.bat\" in the Meniscus folder.")
end

local function zoneNow()
    local z = call(GetRealZoneText)
    if not str(z) then z = call(GetZoneText) end
    return str(z) and z or nil
end

-- A creature in front of you: unit is your target, what the mouse is on,
-- or a nameplate. seen[guid]: 1 once its standing facts are written, 2 once
-- its health is too (nothing more to learn from looking at this one).
local seen, nSeen = {}, 0
local function observe(unit)
    local id, guid = npcID(unit)
    if not id or seen[guid] == 2 then return end
    if not isTrue(call(UnitCanAttack, "player", unit)) then return end
    if isTrue(call(UnitPlayerControlled, unit)) then return end
    local kind = call(UnitCreatureType, unit)
    if str(kind) and kind == "Critter" then return end
    local first = not seen[guid]
    if first then
        if nSeen > 600 then wipe(seen); nSeen = 0 end
        nSeen = nSeen + 1
    end
    local new = false
    local r = MinimalUIDB and MinimalUIDB.bestiary and MinimalUIDB.bestiary[id]
    if not r then r = record(id, true); new = true; nameIndex = nil end
    if not r then return end
    local lvl = call(UnitLevel, unit)
    local okLvl = plain(lvl) and lvl > 0
    if first then
        local name = call(UnitName, unit)
        if str(name) then r.n = name end
        if okLvl then
            if not r.lo or lvl < r.lo then r.lo = lvl; new = true end
            if not r.hi or lvl > r.hi then r.hi = lvl; new = true end
        end
        if str(kind) then r.t = kind end
        local fam = call(UnitCreatureFamily, unit)
        if str(fam) then r.f = fam end
        local cl = call(UnitClassification, unit)
        if str(cl) and RANK[cl] then r.cl = cl end
        local react = call(UnitReaction, unit, "player")
        if plain(react) then r.ag = react < 4 and 1 or 0 end
        local z = zoneNow()
        if z then
            r.z = r.z or {}
            if not r.z[z] and count(r.z) < 6 then r.z[z] = true; new = true end
        end
    end
    -- Its full health: only out of a fight will the game say (a hidden
    -- value otherwise), so it is asked again each time it is looked at.
    local hp = call(UnitHealthMax, unit)
    if first and MinimalUIDB then
        local dg = MinimalUIDB.hpdiag or {}
        MinimalUIDB.hpdiag = dg
        local key = (secret(hp) and "hidden" or type(hp)) .. (InCombatLockdown() and ", in a fight" or ", out of a fight")
        dg[key] = (dg[key] or 0) + 1
    end
    if okLvl and plain(hp) and hp > 0 then
        r.hp = r.hp or {}
        if (r.hp[lvl] or 0) < hp then r.hp[lvl] = hp; new = true end
        seen[guid] = 2
    else
        seen[guid] = 1
    end
    if new then changed(id) end
end

-- Its look: the game does not say which body a creature wears, but a
-- model frame shown the unit can be asked what it drew. One unseen frame,
-- pointed at your target; asked a moment later (the model takes a frame
-- or two to arrive).
local lookFrame, lookSeen = nil, {}
local function noteLook()
    local id, guid = npcID("target")
    if not id or lookSeen[guid] then return end
    local r = record(id)
    if not r then return end
    if not lookFrame then
        lookFrame = CreateFrame("PlayerModel", nil, UIParent)
        lookFrame:SetSize(4, 4)
        lookFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        lookFrame:SetAlpha(0)
        lookFrame:EnableMouse(false)
    end
    local function diag(key)
        if not MinimalUIDB then return end
        local dg = MinimalUIDB.lookdiag or {}
        MinimalUIDB.lookdiag = dg
        dg[key] = (dg[key] or 0) + 1
    end
    if not lookFrame.GetDisplayInfo then diag("no GetDisplayInfo") return end
    if not pcall(lookFrame.SetUnit, lookFrame, "target") then diag("SetUnit refused") return end
    C_Timer.After(0.4, function()
        local _, g2 = npcID("target")
        if g2 ~= guid then return end
        local d = call(lookFrame.GetDisplayInfo, lookFrame)
        pcall(lookFrame.ClearModel, lookFrame)
        diag(secret(d) and "hidden" or (plain(d) and (d > 0 and "got one" or "zero") or type(d)))
        if not (plain(d) and d > 0) then return end
        lookSeen[guid] = true
        r.dsp = r.dsp or {}
        if not r.dsp[d] and count(r.dsp) < 12 then r.dsp[d] = true; changed(id) end
    end)
end

local function noteCast(unit, spellID, done)
    if done and MinimalUIDB then
        local dg = MinimalUIDB.castdiag or {}
        MinimalUIDB.castdiag = dg
        local key = secret(unit) and "hidden unit" or (type(unit) ~= "string" and "no unit")
            or (unit == "player" and "you") or (unit:find("^nameplate") and "a nameplate") or unit:gsub("%d+", "")
        dg["from " .. key] = (dg["from " .. key] or 0) + 1
    end
    if secret(unit) then return end
    if unit ~= "target" and not (type(unit) == "string" and unit:find("^nameplate")) then return end
    if done and MinimalUIDB then
        -- (how a cast with no bar arrives on this client: counted, to be read later)
        local dg = MinimalUIDB.castdiag or {}
        MinimalUIDB.castdiag = dg
        local key = secret(spellID) and "hidden id" or (plain(spellID) and "id" or "no id")
        dg[key] = (dg[key] or 0) + 1
        if not plain(spellID) then return end -- (no bar to ask the name of)
    end
    local id = npcID(unit)
    if not id then return end
    local name
    if plain(spellID) and C_Spell and C_Spell.GetSpellName then name = call(C_Spell.GetSpellName, spellID) end
    if not str(name) then
        name = call(UnitCastingInfo, unit)
        if not str(name) then name = call(UnitChannelInfo, unit) end
    end
    if not str(name) then return end
    local r = record(id, true)
    r.c = r.c or {}
    local have = r.c[name]
    if have == nil and count(r.c) >= 16 then return end
    if have == nil or (have == true and plain(spellID)) then
        r.c[name] = plain(spellID) and spellID or true
        changed(id)
    end
end

local function idByName(name)
    local all = MinimalUIDB and MinimalUIDB.bestiary
    if not all then return end
    if not nameIndex then
        nameIndex = {}
        for id, r in pairs(all) do if r.n then nameIndex[r.n] = id end end
    end
    return nameIndex[name]
end
local seenDead, seenLoot, nDead, nLoot = {}, {}, 0, 0
local fightKills = {} -- (what died to you in the fight going on)
-- A kill. Three signs, and a death is counted by whichever comes first
-- (0.1.584; with two of them, three corpses were looted of a creature
-- that had one kill to its name):
--   seen dead: your target or a nameplate's creature, dead and not someone
--     else's, asked when its health changes and when the fight ends;
--   looted: a corpse you open was a kill of yours, whether or not it was
--     seen to die (these two know which creature it was: counted once);
--   the game's line "<name> dies, you gain N experience": yours by
--     definition, but it gives a name and no more, so it is paired with
--     the other two by name: a death counted from this line lets the next
--     sighting or looting of that name pass (within five minutes), and one
--     already sighted lets this line pass (within ten seconds).
local owedByXP, owedBySight = {}, {}
local function owe(t, name)
    local q = t[name]
    if not q then q = {}; t[name] = q end
    q[#q + 1] = GetTime()
end
local function take(t, name, within)
    local q = name and t[name]
    if not q then return false end
    local now = GetTime()
    while q[1] and now - q[1] > within do table.remove(q, 1) end
    if q[1] then table.remove(q, 1) return true end
    return false
end
local function diag(key, what)
    if not MinimalUIDB then return end
    local dg = MinimalUIDB[key] or {}
    MinimalUIDB[key] = dg
    dg[what] = (dg[what] or 0) + 1
end
local function addKill(id, lvl, inFight)
    local r = record(id, true)
    r.k = (r.k or 0) + 1
    r.lk = (r.lk or 0) + 1
    if inFight then fightKills[#fightKills + 1] = { id = id, lvl = lvl } end
    changed(id)
end
local function markDead(guid)
    if nDead > 600 then wipe(seenDead); nDead = 0 end
    seenDead[guid] = true; nDead = nDead + 1
end
local function noteDeath(unit)
    unit = unit or "target"
    if not isTrue(call(UnitIsDead, unit)) then return end
    local id, guid = npcID(unit)
    if not id or seenDead[guid] then return end
    if isTrue(call(UnitIsTapDenied, unit)) then return end
    markDead(guid)
    local r = record(id)
    local name = r and r.n
    if take(owedByXP, name, 300) then diag("killdiag", "seen dead, already had the experience line") return end
    if name then owe(owedBySight, name) end
    local lvl = call(UnitLevel, unit)
    diag("killdiag", "counted when seen dead")
    addKill(id, plain(lvl) and lvl > 0 and lvl or nil, true)
end
-- (from the loot window: creditLoot, below)
local function lootKill(id, guid)
    if seenDead[guid] then return end
    markDead(guid)
    local r = record(id)
    if take(owedByXP, r and r.n, 300) then return end
    diag("killdiag", "counted when looted")
    addKill(id, nil, false)
end
local function noteXP(text)
    if secret(text) then diag("killdiag", "experience line hidden") return end
    if not str(text) then return end
    local name = text:match("^(.-) dies, you gain")
    if not name then diag("killdiag", "experience line, other wording") return end
    local id = idByName(name)
    if not id then diag("killdiag", "experience line, creature not in the book") return end
    if take(owedBySight, name, 10) then return end
    owe(owedByXP, name)
    local lvl
    if npcID("target") == id then
        lvl = call(UnitLevel, "target")
        lvl = plain(lvl) and lvl > 0 and lvl or nil
    end
    local r = record(id)
    if not lvl and r and r.lo and r.lo == r.hi then lvl = r.lo end
    diag("killdiag", "counted from the experience line")
    addKill(id, lvl, true)
end

-- Health, worked out (0.1.577). The game hides a creature's health from
-- addons, so it is never simply read. But its own damage meter keeps your
-- running total, which can be read between fights: what it went up by in
-- a fight where you (and your pet) killed exactly one creature, alone, is
-- about that creature's health. A little over (the last blow's excess),
-- or under if it was already hurt or someone helped, so the least of the
-- samples is kept and it is shown as "about".
local dmgBefore, petBefore
local function dmgTotal()
    local get = C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType
    if not get then return end
    local sum = 0
    local pet = call(UnitGUID, "pet")
    for _, g in ipairs({ call(UnitGUID, "player"), pet }) do
        if str(g) then
            local src = call(get, 0, 0, g)
            if type(src) == "table" then
                local t = src.totalAmount
                if secret(t) then return end
                if type(t) == "number" then sum = sum + t end
            end
        end
    end
    return sum, str(pet) and pet or "none"
end
local function fightStart()
    wipe(fightKills)
    local ok, t, pet = pcall(dmgTotal)
    if ok and plain(t) then dmgBefore, petBefore = t, pet end
end
local function fightEnd()
    if InCombatLockdown() then return end
    local ok, now, pet = pcall(dmgTotal)
    if not ok then now = nil end
    if plain(now) and plain(dmgBefore) and pet == petBefore and #fightKills == 1
        and not (IsInGroup and isTrue(call(IsInGroup))) then
        local k = fightKills[1]
        local d = math.floor(now - dmgBefore + 0.5)
        local r = record(k.id)
        local L = k.lvl or 0 -- (0: which level it was is not known)
        if r and d > 0 and not (r.hp and r.hp[L]) then
            r.he, r.hn = r.he or {}, r.hn or {}
            if not r.he[L] or d < r.he[L] then r.he[L] = d end
            r.hn[L] = (r.hn[L] or 0) + 1
            changed(k.id)
        end
    end
    if plain(now) then dmgBefore, petBefore = now, pet end
    -- What it left on you: your debuffs, now that they can be read. One
    -- the game ties to a creature still about goes to that creature; one
    -- with no owner left goes to what you killed, if that was one thing.
    pcall(function()
        local U = C_UnitAuras
        if not (U and U.GetAuraDataByIndex) then return end
        for i = 1, 16 do
            local a = U.GetAuraDataByIndex("player", i, "HARMFUL")
            if type(a) ~= "table" then break end
            local name, src = a.name, a.sourceUnit
            if str(name) then
                local id
                if str(src) then id = npcID(src)
                elseif src == nil and #fightKills == 1 then id = fightKills[1].id end
                local r = id and record(id)
                if r then
                    r.db = r.db or {}
                    if r.db[name] == nil and count(r.db) < 12 then
                        r.db[name] = plain(a.spellId) and a.spellId or true
                        changed(id)
                    end
                end
            end
        end
    end)
    wipe(fightKills)
end

-- Its loot table (0.1.569): every item on every corpse you open, and how
-- many corpses of it you have opened, so each item has a rate: corpses
-- that had it out of corpses looted. A corpse is counted once (seenLoot by
-- its id), an item once per corpse whatever the stack. A slot can come
-- from several corpses at once (looting a heap): each is credited.
-- A corpse with nothing on it can't be opened, so it is never counted:
-- the rates are "of those that had anything", a little high.
local function creditLoot(item, guid, ...)
    if guid == nil then return end
    local id = npcOf(guid)
    if id then
        local r = record(id, true)
        if not seenLoot[guid] then
            if nLoot > 600 then wipe(seenLoot); nLoot = 0 end
            seenLoot[guid] = {}; nLoot = nLoot + 1
            r.ln = (r.ln or 0) + 1
            pcall(lootKill, id, guid)
            changed(id)
        end
        local had = seenLoot[guid]
        if item and not had[item] then
            had[item] = true
            r.l = r.l or {}
            if r.l[item] or count(r.l) < 60 then r.l[item] = (r.l[item] or 0) + 1; changed(id) end
        end
    end
    return creditLoot(item, select(2, ...)) -- (guid, quantity, guid, quantity...)
end
local function noteLoot()
    if not (GetNumLootItems and GetLootSourceInfo and GetLootSlotLink) then return end
    local n = call(GetNumLootItems)
    if not plain(n) then return end
    for slot = 1, n do
        local link = call(GetLootSlotLink, slot)
        local item = str(link) and tonumber(link:match("item:(%d+)")) or nil
        pcall(function() creditLoot(item, GetLootSourceInfo(slot)) end)
    end
end

-- What it says (0.1.568): a creature's say, yell and emote lines, for one
-- already in the book (the line comes with the speaker's name only, so it
-- is matched by name). Your own name in a line is kept as $N. A line in a
-- language you don't speak arrives already scrambled by the game, and the
-- scramble can't be undone later: it is kept as heard, marked as not
-- understood, with the language's name. Once you know the language and
-- hear the creature again, its lines come in clear, and the scrambled
-- ones in that language are dropped then.
local function understood(lang)
    if not str(lang) then return true end
    if not (GetNumLanguages and GetLanguageByIndex) then return true end
    local n = call(GetNumLanguages)
    if not plain(n) or n == 0 then return true end
    for i = 1, n do
        local name = call(GetLanguageByIndex, i)
        if str(name) and name == lang then return true end
    end
    return false
end
local function noteSpeech(kind, text, who, lang)
    if not (str(text) and str(who)) then return end
    local id = idByName(who)
    local r = id and record(id)
    if not r then return end
    local me = call(UnitName, "player")
    if str(me) then text = text:gsub(me:gsub("%p", "%%%0"), "$N") end
    local clear = understood(lang)
    r.q = r.q or {}
    for _, line in ipairs(r.q) do if line.t == text then return end end
    if clear and str(lang) then
        for i = #r.q, 1, -1 do
            if r.q[i].u and r.q[i].l == lang then table.remove(r.q, i) end
        end
    end
    if #r.q >= 12 then return end
    r.q[#r.q + 1] = { t = text, k = kind, l = str(lang) and lang or nil, u = (not clear) or nil }
    changed(id)
end

-- The death recap (DeathRecap.lua hands it over when it is opened): who
-- hit you, with what, and how hard. It names the attacker and nothing
-- else, so it is matched to a record by name; the killing blow is first.
-- A recap looked at twice is counted once (its time is remembered).
function B.Recap(events)
    local all = MinimalUIDB and MinimalUIDB.bestiary
    if type(events) ~= "table" or not all or not events[1] then return end
    local stamp = events[1].time
    if stamp and MinimalUIDB.bestiaryRecap == stamp then return end
    MinimalUIDB.bestiaryRecap = stamp
    local byName = {}
    for id, r in pairs(all) do if r.n then byName[r.n] = id end end
    for i, e in ipairs(events) do
        local id = e.source and byName[e.source]
        local r = id and all[id]
        if r then
            if i == 1 then r.kd = (r.kd or 0) + 1 end
            local name = e.spellId and e.name or "Melee"
            if type(name) == "string" and name ~= "" then
                if e.spellId then
                    r.c = r.c or {}
                    if r.c[name] == nil or r.c[name] == true then r.c[name] = e.spellId end
                end
                if type(e.amount) == "number" and e.amount > 0 then
                    r.hit = r.hit or {}
                    if (r.hit[name] or 0) < e.amount then r.hit[name] = e.amount end
                end
            end
            changed(id)
        end
    end
end

-- ── What is known of one, as rows ─────────────────────────────────────────
-- (The character window's list rows: header / stat.) full: the standing
-- facts too (the inspect window has those from the creature itself).
local function levels(r)
    if not r.lo then return nil end
    return r.lo == r.hi and tostring(r.lo) or (r.lo .. "-" .. r.hi)
end
local function levelLabel(r) return r.lo ~= r.hi and "Level range" or "Level" end
local function head(rows, title, glyph) rows[#rows + 1] = { kind = "header", text = title, glyph = glyph } end
local function stat(rows, label, value, color)
    if value == nil then return end
    rows[#rows + 1] = { kind = "stat", label = label, value = value, color = color }
end
-- Behavior (0.1.576): what a creature is seen to do, read off its emotes
-- ("%s attempts to run away in fear!"). The emote is kept as it was heard
-- (in q, with what it says); the label is decided here when it is shown,
-- so this list can grow and be reworded and what is already written down
-- follows. An emote that matches nothing stays under "Says".
--   { words to find in the emote (lower case, any of them), label, what it means }
local BEHAVIORS = {
    { { "run away in fear", "attempts to flee", "flees" }, "Runs away in fear",
      "Runs when badly hurt, and may come back with others." },
    { { "calls for help", "call for help", "calls for aid" }, "Calls for help",
      "Brings nearby allies into the fight." },
    { { "enrage" }, "Enrages", "Hits harder or faster once it is hurt." },
    { { "frenzy" }, "Goes into a frenzy", "Attacks faster for a while." },
}
local function behaviorOf(line)
    if line.k ~= "emote" or type(line.t) ~= "string" then return end
    local low = line.t:lower()
    for _, b in ipairs(BEHAVIORS) do
        for _, w in ipairs(b[1]) do
            if low:find(w, 1, true) then return b end
        end
    end
end
B.BehaviorOf = behaviorOf

function B.Rows(rows, id, full)
    local r = id and view(id)
    if not r then
        rows[#rows + 1] = { kind = "stat", value = "",
            label = id and "Nothing yet: it fills in as you meet it" or "Nothing is kept for this one" }
        return rows
    end
    if full then
        head(rows, "About", "micro_character.tga")
        stat(rows, "Type", r.t and (r.f and (r.t .. ", " .. r.f) or r.t) or nil)
        stat(rows, "Rank", r.cl and RANK[r.cl] or nil, T.accent)
        if r.ag then stat(rows, "Disposition", r.ag == 1 and "Hostile" or "Neutral", r.ag == 1 and RED or { 0.92, 0.82, 0.36, 1 }) end
        if r.lo then stat(rows, levelLabel(r), levels(r)) end
    elseif r.lo then
        stat(rows, levelLabel(r), levels(r))
    end
    if r.shared and not r.met then
        rows[#rows + 1] = { kind = "stat", label = "Met by you", value = "not yet", color = T.textDim }
    else
        stat(rows, "Kills", string.format("%d", r.k or 0))
    end
    if r.kd then stat(rows, "Killed you", string.format("%d", r.kd), RED) end
    -- health, by level
    do
        local seenLv, lv = {}, {}
        for l in pairs(r.hp or {}) do seenLv[l] = true end
        for l in pairs(r.he or {}) do seenLv[l] = true end
        for l in pairs(seenLv) do lv[#lv + 1] = l end
        table.sort(lv)
        local function big(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
        for _, l in ipairs(lv) do
            if r.hp and r.hp[l] then
                stat(rows, "Health at " .. l, big(r.hp[l]))
            else
                local n = r.hn and r.hn[l] or 1
                rows[#rows + 1] = { kind = "stat", label = l > 0 and ("Health at " .. l) or "Health", value = "about " .. big(r.he[l]),
                    tooltip = function(tip)
                        tip:SetText(l > 0 and ("Health at level " .. l) or "Health", 1, 1, 1)
                        tip:AddLine("The game hides a creature's health from addons. This is worked out from the damage it took to kill one alone ("
                            .. n .. (n == 1 and " kill" or " kills") .. " so far; the least is kept).", 0.86, 0.86, 0.89, true)
                    end }
            end
        end
        if #lv == 0 then
            rows[#rows + 1] = { kind = "stat", label = "Health", value = "not learned yet", color = T.textDim,
                tooltip = function(tip)
                    tip:SetText("Health", 1, 1, 1)
                    tip:AddLine("The game hides a creature's health from addons. It is worked out when you kill one by yourself, in a fight with nothing else in it.",
                        0.86, 0.86, 0.89, true)
                end }
        end
    end
    -- what it does
    local names = {}
    for name in pairs(r.c or {}) do names[name] = true end
    for name in pairs(r.hit or {}) do names[name] = true end
    for name in pairs(r.db or {}) do names[name] = true end
    if next(names) then
        head(rows, "Attacks and abilities", "micro_spell.tga")
        local list = {}
        for name in pairs(names) do list[#list + 1] = name end
        table.sort(list, function(a, b) if (a == "Melee") ~= (b == "Melee") then return a == "Melee" end return a < b end)
        for _, name in ipairs(list) do
            local sid = r.c and type(r.c[name]) == "number" and r.c[name]
                or (r.db and type(r.db[name]) == "number" and r.db[name]) or nil
            local debuff = r.db and r.db[name] ~= nil
            local icon = name == "Melee" and MELEE_ICON
                or (sid and C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, sid)) or nil
            local hit = r.hit and r.hit[name]
            rows[#rows + 1] = { kind = "stat", label = name, labelColor = T.text, icon = str(icon) and icon or (plain(icon) and icon) or nil,
                value = (hit and ("up to " .. hit) or "") .. (debuff and ((hit and "   ·   " or "") .. "debuff") or ""), color = T.textDim,
                tooltip = function(tip)
                    if not (sid and pcall(tip.SetSpellByID, tip, sid)) then tip:SetText(name, 1, 1, 1) end
                    tip:AddLine(" ")
                    if r.c and r.c[name] ~= nil then tip:AddLine("Seen it use this.", 0.6, 0.6, 0.65) end
                    if debuff then tip:AddLine("Found on you after a fight with it.", 0.6, 0.6, 0.65) end
                    if hit then tip:AddLine("Hardest hit on you: " .. hit .. " (from a death recap).", 0.6, 0.6, 0.65) end
                    tip:Show()
                end }
        end
    end
    if (r.l and next(r.l)) or (r.d and next(r.d)) then
        -- (Out of kills, where those were counted: a corpse with nothing
        -- on it can't be opened, so corpses looted alone runs high. A kill
        -- you walked away from without looting counts as nothing found.)
        local looted = r.ln or 0
        local ln = math.max(looted, r.lk or 0)
        head(rows, ln > 0 and ("Loot   (" .. ln .. (ln == 1 and " kill)" or " kills)")) or "Loot", "micro_journal.tga")
        if ln > looted then
            rows[#rows + 1] = { kind = "stat", label = "Nothing on it", labelColor = T.textDim, color = T.textDim,
                value = string.format("%d%%", math.floor((ln - looted) / ln * 100 + 0.5)) }
        end
        local ids = {}
        for item in pairs(r.l or {}) do ids[#ids + 1] = item end
        for item in pairs(r.d or {}) do if not (r.l and r.l[item]) then ids[#ids + 1] = item end end
        local function share(item) return r.l and r.l[item] or -1 end
        table.sort(ids, function(a, b) if share(a) ~= share(b) then return share(a) > share(b) end return a < b end)
        for _, item in ipairs(ids) do
            local _, link = nil, nil
            if C_Item and C_Item.GetItemInfo then _, link = call(C_Item.GetItemInfo, item) end
            local icon = C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, item)
            local n = r.l and r.l[item]
            local value, color
            if n and ln > 0 then
                value = string.format("%d%%", math.floor(n / ln * 100 + 0.5)) -- (the counts are in the tooltip)
            else
                value, color = "seen" .. (r.d and (r.d[item] or 0) > 1 and (" x" .. r.d[item]) or ""), T.textDim
            end
            rows[#rows + 1] = { kind = "stat", label = str(link) and link or ("Item " .. item),
                labelColor = T.text, icon = icon, value = value, color = color,
                tooltip = function(tip)
                    pcall(tip.SetHyperlink, tip, "item:" .. item)
                    tip:AddLine(" ")
                    if n and ln > 0 then
                        tip:AddLine(string.format("On %d of %d kills%s.", n, ln, r.shared and ", yours and other players'" or ""), 0.6, 0.6, 0.65, true)
                        if ln < 20 then tip:AddLine("Few kills so far: the rate will settle.", 0.6, 0.6, 0.65, true) end
                    else
                        tip:AddLine("Seen before corpses were counted: no rate yet.", 0.6, 0.6, 0.65, true)
                    end
                    tip:Show()
                end }
        end
    end
    -- what it does, then what it says (an emote that is a known behavior
    -- is listed as that, once)
    local does, says = {}, {}
    for _, line in ipairs(r.q or {}) do
        local b = behaviorOf(line)
        if b then
            if not does[b] then does[b] = line; does[#does + 1] = b end
        else
            says[#says + 1] = line
        end
    end
    if #does > 0 then
        head(rows, "Behavior", "micro_eye.tga")
        for _, b in ipairs(does) do
            local heard = does[b].t
            if r.n then heard = heard:gsub("%%s", (r.n:gsub("%%", "%%%%"))) end
            rows[#rows + 1] = { kind = "stat", wide = true, label = b[2], labelColor = T.text, value = "",
                tooltip = function(tip)
                    tip:SetText(b[2], 1, 1, 1)
                    tip:AddLine(b[3], 0.86, 0.86, 0.89, true)
                    tip:AddLine(" ")
                    tip:AddLine("Seen as: " .. heard, 0.6, 0.6, 0.65, true)
                end }
        end
    end
    if #says > 0 then
        head(rows, "Says", "micro_chat.tga")
        local me = call(UnitName, "player")
        for _, line in ipairs(says) do
            local said = str(me) and line.t:gsub("%$N", me) or line.t
            if r.n then said = said:gsub("%%s", (r.n:gsub("%%", "%%%%"))) end
            local how = line.k == "yell" and "Yells" or (line.k == "emote" and "Emote") or "Says"
            rows[#rows + 1] = { kind = "stat", wide = true, value = "",
                label = line.k == "emote" and said or ("\"" .. said .. "\""),
                labelColor = line.u and T.textDim or T.text,
                tooltip = function(tip)
                    tip:SetText(how .. (line.l and (", in " .. line.l) or ""), 1, 1, 1)
                    tip:AddLine(said, 0.86, 0.86, 0.89, true)
                    if line.u then
                        tip:AddLine(" ")
                        tip:AddLine("You don't speak " .. (line.l or "this language") .. ": this is how it sounded to you. "
                            .. "It is replaced with the real words when you hear this creature after learning the language.",
                            0.6, 0.6, 0.65, true)
                    end
                end }
        end
    end
    if full and r.z and next(r.z) then
        head(rows, "Found in", "micro_journal.tga")
        local zs = {}
        for z in pairs(r.z) do zs[#zs + 1] = z end
        table.sort(zs)
        for _, z in ipairs(zs) do rows[#rows + 1] = { kind = "stat", label = z, labelColor = T.text, value = "" } end
    end
    return rows
end

-- ── The window ────────────────────────────────────────────────────────────
-- The header band; on the left every creature known, under the zones it
-- was met in (the zone you are in is open, the rest fold); on the right
-- the one picked: what it looks like, where the game will draw it, and
-- what is known.
local PAGE_TOP = (ns.SHELL_H or 92) + 14
local LIST_W, CARD_W, ROW_H = 300, 372, 22
local LIST_ROWS = 20
local LIST_H = LIST_ROWS * ROW_H
local MODEL_H = 154
local W, H = 14 + LIST_W + 10 + CARD_W + 14, PAGE_TOP + LIST_H + 12 + 14
local ELSEWHERE = "Met before zones were kept"
local win, picked, stale
-- Search (0.1.568): every word typed must be found somewhere in what is
-- known of the creature: its name, type and family, rank, disposition, the
-- zones, its attacks, what it says, what it drops. A number is a level
-- (12 finds everything whose range takes in 12; 14-18 everything that
-- overlaps that). The text searched is put together once for a record
-- and thrown away when the record changes.
local query, hay = "", {}
local openNames = {} -- (names with several forms that are open in the list: this session)
local function haystack(id, r)
    local h = hay[id]
    if h then return h end
    local bits = { r.n or "", r.t or "", r.f or "", r.cl and RANK[r.cl] or "",
                   r.ag == 1 and "hostile" or (r.ag == 0 and "neutral" or "") }
    for z in pairs(r.z or {}) do bits[#bits + 1] = z end
    for name in pairs(r.c or {}) do bits[#bits + 1] = name end
    for name in pairs(r.db or {}) do bits[#bits + 1] = name end
    for name in pairs(r.hit or {}) do bits[#bits + 1] = name end
    for _, line in ipairs(r.q or {}) do
        bits[#bits + 1] = line.t
        local b = behaviorOf(line)
        if b then bits[#bits + 1] = b[2] end
    end
    local drops = {}
    for item in pairs(r.d or {}) do drops[item] = true end
    for item in pairs(r.l or {}) do drops[item] = true end
    for item in pairs(drops) do
        local name = C_Item and C_Item.GetItemNameByID and call(C_Item.GetItemNameByID, item)
        if str(name) then bits[#bits + 1] = name end
    end
    h = table.concat(bits, "\n"):lower()
    hay[id] = h
    return h
end
local function matches(id, r, words)
    local h
    for _, w in ipairs(words) do
        local a, b = w:match("^(%d+)%-(%d+)$")
        local n = tonumber(w)
        if a then
            a, b = tonumber(a), tonumber(b)
            if not (r.lo and r.hi >= math.min(a, b) and r.lo <= math.max(a, b)) then return false end
        elseif n then
            if not (r.lo and n >= r.lo and n <= r.hi) then return false end
        else
            h = h or haystack(id, r)
            if not h:find(w, 1, true) then return false end
        end
    end
    return true
end

local function card(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    ns.RoundedRect(f, -6, 0, 10, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(f, -5, 1, 9, 0.085, 0.085, 0.095, 1)
    return f
end

local function listData()
    local d = {}
    local all = MinimalUIDB and MinimalUIDB.bestiary or {}
    local here = zoneNow()
    local zones, total, kills, found = {}, 0, 0, 0
    local words
    if query ~= "" then
        words = {}
        for w in query:gmatch("%S+") do words[#words + 1] = w end
    end
    local ids = {}
    for id in pairs(all) do ids[id] = true end
    for id in pairs(SH.r) do ids[id] = true end
    for id in pairs(ids) do
        local r = view(id) or {}
        if r.n then
            total = total + 1
            kills = kills + (r.k or 0)
        end
        if r.n and (not words or matches(id, r, words)) then
            found = found + 1
            if r.z and next(r.z) then
                for z in pairs(r.z) do zones[z] = zones[z] or {}; table.insert(zones[z], id) end
            else
                zones[ELSEWHERE] = zones[ELSEWHERE] or {}; table.insert(zones[ELSEWHERE], id)
            end
        end
    end
    local names = {}
    for z in pairs(zones) do names[#names + 1] = z end
    local function rank(z) return z == here and 0 or (z == ELSEWHERE and 2 or 1) end
    table.sort(names, function(a, b) if rank(a) ~= rank(b) then return rank(a) < rank(b) end return a < b end)
    for _, z in ipairs(names) do
        local col = B.db.collapsed[z]
        if col == nil then col = z ~= here end
        if words then col = false end -- (a search shows what it found)
        table.insert(d, { kind = "header", text = z .. "   |cff7d7d88" .. #zones[z] .. "|r", collapsed = col,
            onClick = function() B.db.collapsed[z] = not col; B:Refresh() end })
        if not col then
            local ids = zones[z]
            -- (by the lowest level of the name, so its forms sit together)
            local nameLow = {}
            for _, id in ipairs(ids) do
                local v = view(id)
                if v.lo and (not nameLow[v.n] or v.lo < nameLow[v.n]) then nameLow[v.n] = v.lo end
            end
            table.sort(ids, function(a, b)
                local ra, rb = view(a), view(b)
                if ra.n == rb.n then
                    if (ra.lo or 0) ~= (rb.lo or 0) then return (ra.lo or 0) < (rb.lo or 0) end
                    return a < b
                end
                local la, lb = nameLow[ra.n] or 0, nameLow[rb.n] or 0
                if la ~= lb then return la < lb end
                return ra.n < rb.n
            end)
            -- Creatures of one name that are not one creature (a Southsea
            -- Brigand is a gnoll here, a troll there: each its own kind
            -- to the game, with its own look) go under one row that
            -- opens. Shut, it stands for the first; open, each is a row.
            local function color(r, on)
                return on and T.accent or (r.shared and not r.met and T.textDim)
                    or ((r.cl == "elite" or r.cl == "worldboss" or r.cl == "rareelite") and ELITE)
                    or (r.cl == "rare" and RARE) or T.text
            end
            local i = 1
            while i <= #ids do
                local id = ids[i]
                local r = view(id)
                local j = i
                while ids[j + 1] and view(ids[j + 1]).n == r.n do j = j + 1 end
                if j == i then
                    local nl = 0
                    for _ in pairs(r.dsp or {}) do nl = nl + 1 end
                    table.insert(d, { kind = "stat", label = r.n .. (nl > 1 and ("   |cff7d7d88" .. nl .. " forms|r") or ""),
                        labelColor = color(r, id == picked), indent = 10,
                        value = levels(r) or "", color = T.textDim,
                        onClick = function() B:Pick(id) end })
                else
                    local key = z .. "\n" .. r.n
                    local isOpen = words ~= nil or openNames[key] == true
                    local lo, hi, has, sameType = nil, nil, false, true
                    for k = i, j do
                        local v = view(ids[k])
                        if v.lo and (not lo or v.lo < lo) then lo = v.lo end
                        if v.hi and (not hi or v.hi > hi) then hi = v.hi end
                        if ids[k] == picked then has = true end
                        if (v.f or v.t) ~= (r.f or r.t) then sameType = false end
                    end
                    table.insert(d, { kind = "stat", label = r.n .. "   |cff7d7d88" .. (j - i + 1) .. " forms|r",
                        labelColor = color(r, has and not isOpen), indent = 10, folded = not isOpen,
                        value = lo and (lo == hi and tostring(lo) or (lo .. "-" .. hi)) or "", color = T.textDim,
                        onClick = function()
                            openNames[key] = not isOpen
                            if not isOpen and not has then B:Pick(id) else B:Refresh() end
                        end })
                    if isOpen then
                        for k = i, j do
                            local vid = ids[k]
                            local v = view(vid)
                            local what = not sameType and (v.f or v.t) or nil
                            table.insert(d, { kind = "stat", label = "Form " .. (k - i + 1) .. (what and ("   |cff7d7d88" .. what .. "|r") or ""),
                                labelColor = color(v, vid == picked), indent = 24,
                                value = levels(v) or "", color = T.textDim,
                                onClick = function() B:Pick(vid) end })
                        end
                    end
                end
                i = j + 1
            end
        end
    end
    return d, total, kills, words and found or nil
end

local formAt = 1
local function looksOf(id)
    local r = id and view(id)
    local list = {}
    for d in pairs(r and r.dsp or {}) do list[#list + 1] = d end
    table.sort(list)
    return list
end
local function showModel(id, form)
    local m = win.model
    local shown = false
    local looks = looksOf(id)
    if id then
        pcall(m.ClearModel, m)
        if form and looks[form] and m.SetDisplayInfo then
            formAt = form
            shown = pcall(m.SetDisplayInfo, m, looks[form])
        elseif npcID("target") == id then
            formAt = 0 -- (the one in front of you, whichever it is)
            shown = pcall(m.SetUnit, m, "target")
        elseif looks[1] and m.SetDisplayInfo then
            formAt = 1
            shown = pcall(m.SetDisplayInfo, m, looks[1])
        elseif m.SetCreature then
            shown = pcall(m.SetCreature, m, id)
        end
        if shown then pcall(m.SetFacing, m, m.facing or 0.4) end
    end
    m:SetShown(shown)
    win.modelNote:SetShown(not shown)
    win.modelNote:SetText(id and "No picture of it: target one with this open" or "Pick a creature")
    -- "Forms 1 2 3": the looks known, when there is more than one
    local many = #looks > 1
    win.formLabel:SetShown(many)
    for i = 1, math.max(#looks, #win.formPills) do
        local b = win.formPills[i]
        if many and i <= #looks and i <= 8 then
            if not b then
                b = ns.Pill(win.top, tostring(i), function() showModel(picked, i) end, { h = 18, pad = 12, minW = 0, font = 10 })
                if i == 1 then b:SetPoint("LEFT", win.formLabel, "RIGHT", 8, 0)
                else b:SetPoint("LEFT", win.formPills[i - 1], "RIGHT", 4, 0) end
                win.formPills[i] = b
            end
            b.selected = i == formAt
            b:Repaint()
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

function B:Pick(id)
    picked = id
    if win then showModel(id) end
    self:Refresh()
end

function B:Refresh()
    if not win or not win:IsShown() then return end
    stale = false
    local d, total, kills, found = listData()
    win.list:SetData(d)
    win.list.empty:SetText(found and "Nothing in the book matches that." or "Nothing met yet. Target or point at a creature.")
    win.shell:SetSubtitle(total == 0 and "Nothing met yet"
        or (found and string.format("%d of %d kinds of creature match", found, total))
        or string.format("%d kinds of creature known   ·   %d killed by you", total, kills))
    local r = picked and view(picked)
    if r then
        win.name:SetText(r.n or "")
        local c = ((r.cl == "elite" or r.cl == "worldboss" or r.cl == "rareelite") and ELITE) or (r.cl == "rare" and RARE) or T.text
        win.name:SetTextColor(c[1], c[2], c[3])
        local bits = {}
        if levels(r) then bits[#bits + 1] = "Level " .. levels(r) end
        if r.cl and RANK[r.cl] then bits[#bits + 1] = RANK[r.cl] end
        if r.t then bits[#bits + 1] = r.t end
        win.sub:SetText(table.concat(bits, "   ·   "))
        win.detail:SetData(B.Rows({}, picked, true))
    else
        win.name:SetText("")
        win.sub:SetText("")
        win.detail:SetData({})
    end
end

-- The journal's two tabs (0.1.564): "Quests" and "Bestiary", in the same
-- place on the header band of the quest log and of this window, the one
-- you are on lit. They are two windows, each put away as the other comes
-- up (in the same dock), so L opens the journal on Quests and the
-- bestiary is one click from there.
function B.JournalTabs(w, here)
    if not B.db then return end -- (the bestiary is switched off)
    local opts = { h = 22, pad = 22, minW = 0 }
    local function go(which)
        if which == here then return end
        w:Hide()
        if which == "bestiary" then
            B:Open()
        else
            local Q = ns.modules.QuestLog
            if Q and Q.Open then pcall(Q.Open, Q) end
        end
    end
    local bst = ns.Pill(w, "Bestiary", function() go("bestiary") end, opts)
    bst:SetPoint("TOPRIGHT", w, "TOPRIGHT", -20, -((ns.SHELL_H or 92) - 32))
    local qst = ns.Pill(w, QUESTS_LABEL or "Quests", function() go("quests") end, opts)
    qst:SetPoint("RIGHT", bst, "LEFT", -6, 0)
    bst.selected, qst.selected = here == "bestiary", here == "quests"
    bst:Repaint(); qst:Repaint()
    if w.shell and w.shell.Lift then w.shell:Lift(bst, qst) end
    return qst
end

local function build()
    local Cm = ns.modules.Character
    if not (Cm and Cm.MakeList) then return false end
    win = CreateFrame("Frame", "MinimalUIBestiary", UIParent)
    win:SetSize(W, H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetPoint("CENTER", 0, 40)
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIBestiary")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))
    win.shell = ns:CreateShell(win)
    win.shell:SetTitle("Bestiary")
    win.shell:SetIcon("Interface/Icons/INV_Misc_Book_09")
    local Qm = ns.modules.QuestLog
    local tabs = Qm and Qm.db and Qm.Open and B.JournalTabs(win, "bestiary") or nil
    local box = CreateFrame("EditBox", nil, win)
    box:SetAutoFocus(false)
    box:SetSize(250, 22)
    if tabs then box:SetPoint("RIGHT", tabs, "LEFT", -10, 0)
    else box:SetPoint("TOPRIGHT", win, "TOPRIGHT", -20, -((ns.SHELL_H or 92) - 32)) end
    box:SetTextInsets(10, 10, 0, 0)
    ns:SetFont(box, 11, "")
    box:SetTextColor(unpack(T.text))
    ns.RoundedRect(box, -8, 0, 11, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(box, -7, 1, 10, 0.05, 0.05, 0.06, 1)
    local hint = box:CreateFontString(nil, "OVERLAY")
    ns:SetFont(hint, 11, "")
    hint:SetTextColor(unpack(T.textDim))
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText("Search: name, type, zone, level, attack...")
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        hint:SetShown(t == "" and not self:HasFocus())
        query = t:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if win.list then win.list.offset = 0 end
        B:Refresh()
    end)
    box:SetScript("OnEditFocusGained", function() hint:Hide() end)
    box:SetScript("OnEditFocusLost", function(self) hint:SetShown((self:GetText() or "") == "") end)
    win.shell:Lift(box)

    local left = card(win, LIST_W, LIST_H + 12)
    left:SetPoint("TOPLEFT", 14, -PAGE_TOP)
    win.list = Cm.MakeList(left, LIST_W - 8, LIST_H, ROW_H, 100)
    win.list:SetPoint("TOPLEFT", 4, -6)
    win.list.empty:SetText("Nothing met yet. Target or point at a creature.")

    local top = card(win, CARD_W, MODEL_H)
    top:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    local spot = top:CreateTexture(nil, "BACKGROUND", nil, 1)
    spot:SetTexture(MEDIA .. "spot.tga")
    spot:SetSize(220, 220)
    spot:SetPoint("CENTER", top, "LEFT", 78, 0)
    spot:SetVertexColor(1, 1, 1, 0.07)
    local clip = CreateFrame("Frame", nil, top)
    clip:SetPoint("TOPLEFT", 2, -2)
    clip:SetPoint("BOTTOMRIGHT", -2, 2)
    clip:SetClipsChildren(true)
    local m = CreateFrame("PlayerModel", nil, clip)
    m:SetPoint("TOPLEFT", top, "TOPLEFT", 6, -6)
    m:SetSize(144, MODEL_H - 12)
    m.facing = 0.4
    m:EnableMouse(true)
    m:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
    m:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    m:SetScript("OnHide", function(self) self.dragX = nil end)
    m:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = self.facing + (x - self.dragX) / (UIParent:GetEffectiveScale() * 90)
        self.dragX = x
        self:SetFacing(self.facing)
    end)
    m:Hide()
    win.model = m
    local function words(size, bold, color)
        local fs = top:CreateFontString(nil, "OVERLAY")
        ns:SetFont(fs, size, "", bold)
        fs:SetTextColor(unpack(color or T.text))
        fs:SetJustifyH("LEFT")
        return fs
    end
    win.modelNote = words(10, false, T.textDim)
    win.modelNote:SetPoint("CENTER", top, "LEFT", 78, 0)
    win.modelNote:SetWidth(120)
    win.modelNote:SetJustifyH("CENTER")
    win.name = words(16, true)
    win.name:SetPoint("TOPLEFT", top, "TOPLEFT", 162, -40)
    win.name:SetPoint("RIGHT", top, "RIGHT", -12, 0)
    win.name:SetWordWrap(true)
    win.sub = words(11, false, T.textDim)
    win.sub:SetPoint("TOPLEFT", win.name, "BOTTOMLEFT", 0, -6)
    win.sub:SetPoint("RIGHT", top, "RIGHT", -12, 0)
    win.sub:SetWordWrap(true)
    win.top, win.formPills = top, {}
    -- "My target": the book opens on what you have targeted; this turns
    -- to it again without closing the window (0.1.583).
    local mine = ns.Pill(top, "My target", function()
        local id = npcID("target")
        if not id then return ns:Print("Nothing targeted that the bestiary keeps.") end
        pcall(observe, "target")
        if not view(id) then return ns:Print("Not in the bestiary yet: it has to be something you can attack.") end
        B:Pick(id)
    end, { h = 20, pad = 18, minW = 0, font = 10 })
    mine:SetPoint("TOPRIGHT", top, "TOPRIGHT", -10, -10)
    win.formLabel = words(10, true, T.textDim)
    win.formLabel:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 162, 16)
    win.formLabel:SetText("FORMS")
    win.formLabel:Hide()

    local dh = LIST_H + 12 - MODEL_H - 10
    local bottom = card(win, CARD_W, dh)
    bottom:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -10)
    local rowsFit = math.floor((dh - 12) / ROW_H)
    win.detail = Cm.MakeList(bottom, CARD_W - 8, rowsFit * ROW_H, ROW_H, 100)
    win.detail:SetPoint("TOPLEFT", 4, -6)
    win.detail.empty:SetText("Pick a creature on the left.")

    win:SetScript("OnShow", function()
        -- what you have targeted, if it is in the book; else the last pick
        local id = npcID("target")
        if id and view(id) then picked = id end
        showModel(picked)
        B:Refresh()
    end)
    -- (records change in bursts: one redraw for the lot)
    local acc = 0
    win:SetScript("OnUpdate", function(_, dt)
        if not stale then return end
        acc = acc + dt
        if acc < 0.3 then return end
        acc = 0
        B:Refresh()
    end)
    return true
end

function B:Open(id)
    if not win and not build() then return ns:Print("The bestiary needs the character window module.") end
    if id then picked = id end
    if win:IsShown() and not id then win:Hide() return end
    if win:IsShown() then showModel(picked); self:Refresh() else win:Show() end
end
ns.commands = ns.commands or {}
ns.commands.bestiary = function(rest)
    if type(rest) == "string" and rest:find("^%s*export") then return export() end
    B:Open()
end

function B:OnInit(db)
    self.db = db
    db.collapsed = db.collapsed or {}
    -- A fresh book (0.1.582, agreed): what was kept before kills were
    -- counted properly had loot without kills and tallies from three
    -- different ways of counting. Everything is met again from here.
    if MinimalUIDB and MinimalUIDB.bestiaryRev ~= 2 then
        MinimalUIDB.bestiary, MinimalUIDB.bestiaryOut, MinimalUIDB.bestiarySent = nil, nil, nil
        MinimalUIDB.hpdiag, MinimalUIDB.castdiag, MinimalUIDB.lookdiag = nil, nil, nil
        MinimalUIDB.bestiaryRev = 2
        nameIndex = nil
    end
    B.OnChange(function(id)
        if id then hay[id] = nil end
        if win and win:IsShown() then stale = true end
    end)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "LOOT_OPENED",
                         "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_COMBAT_XP_GAIN", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
                         "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local SPEECH = { CHAT_MSG_MONSTER_SAY = "say", CHAT_MSG_MONSTER_YELL = "yell", CHAT_MSG_MONSTER_EMOTE = "emote" }
    ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
        if SPEECH[e] then
            -- (text, speaker, language)
            pcall(noteSpeech, SPEECH[e] ~= "say" and SPEECH[e] or nil, a1, a2, a3)
            return
        end
        if e == "PLAYER_REGEN_DISABLED" then pcall(fightStart) return end
        if e == "PLAYER_ENTERING_WORLD" then C_Timer.After(3, function() if not InCombatLockdown() then pcall(fightStart) end end) return end
        if e == "CHAT_MSG_COMBAT_XP_GAIN" then pcall(noteXP, a1) return end
        if e == "PLAYER_REGEN_ENABLED" then
            C_Timer.After(0.3, function() pcall(noteDeath, "target") end)
            C_Timer.After(0.6, function() pcall(fightEnd) end)
        end
        if e == "PLAYER_TARGET_CHANGED" or e == "PLAYER_REGEN_ENABLED" then pcall(observe, "target")
            -- (noteLook is not run: the game answered 0 for every creature
            -- asked, 39 of 39, so its forms can't be learned this way.)
        elseif e == "UPDATE_MOUSEOVER_UNIT" then pcall(observe, "mouseover")
        elseif e == "NAME_PLATE_UNIT_ADDED" then if type(a1) == "string" then pcall(observe, a1) end
        elseif e == "LOOT_OPENED" then pcall(noteLoot)
        else pcall(noteCast, a1, a3, e == "UNIT_SPELLCAST_SUCCEEDED") end
    end)
    local hp = CreateFrame("Frame")
    pcall(hp.RegisterEvent, hp, "UNIT_HEALTH")
    hp:SetScript("OnEvent", function(_, _, unit)
        if type(unit) ~= "string" or secret(unit) then return end
        if unit == "target" or unit:find("^nameplate") then pcall(noteDeath, unit) end
    end)
end
