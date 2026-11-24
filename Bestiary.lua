local _, ns = ...
local CreateFrame = ns.CreateFrame or CreateFrame
local T = ns.Theme

-- Bestiary (0.1.560): what you have learned of the creatures you meet, kept
-- as you go and browsable (/men bestiary, or from the inspect window on a
-- creature). The record began in Inspect.lua (0.1.530) as "what you have
-- seen"; it lives here now and notes more.
--
-- One small record for each KIND of creature (not each one), written only
-- when something is learned. (A number below zero is made up: a creature
-- known by its name alone so far, met in a dungeon. See "In a dungeon".)
--   MinimalUIDB.bestiary[npcID] = {
--     n  = name,            lo, hi = levels seen,
--     t  = kind (Beast),    f = family (Cat),   cl = rank (elite, rare...),
--     ag = 1 hostile / 0 neutral,
--     z  = { [zone] = true }            where (6 at most); for an instance
--          the value is what sort it is ("party", "raid"), not true,
--     (0.1.592) mana = true (it has mana), uc = its class as the game has
--          it (MAGE, WARRIOR...), tame = true (a hunter was told so),
--          sk = how its corpse is gathered (leather / herb / rock / bolts),
--          qs = { [quest name] = true } quests it counted for (4),
--          rep = { [faction] = change per kill } (3),
--          xp = experience for a kill, xl = your level when it gave that,
--          cn = coin found on its corpses in all (copper),
--     dsp = { [display id] = true }     its looks (0.1.575, 12 at most):
--          one creature can wear several bodies (a Southsea Brigand is a
--          gnoll, a troll, a human... and still the one creature to the
--          game, with one set of numbers),
--     hp = { [level] = health }         its full health at that level,
--     hs = { [level] = { [health worked out] = times } }  the samples,
--     he = { [level] = the one most often seen },  hn = how often (below),
--     c  = { [spell name] = spell id or true }   what it casts (16): cast
--          bars, and since 0.1.579 casts with no bar (instant ones) where
--          the game says what they were,
--     cc = { [spell name] = kind }      how it takes control of you: STUN,
--          FEAR, ROOT, SILENCE... (0.1.588, from the game's own "loss of
--          control" notice, with the spell kept in c),
--     dbt = { [debuff name] = Magic / Poison / Disease / Curse },
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
    for _, key in ipairs({ "mana", "uc", "tame", "sk", "xp", "xl" }) do
        if own[key] ~= nil then v[key] = own[key] else v[key] = sh[key] end
    end
    -- (coin for a kill: your own corpses if you have any, else the others')
    if own.cn then v.cn, v.cb = own.cn, math.max(own.lk or 0, own.ln or 0)
    elseif sh.cn then v.cn, v.cb = sh.cn, math.max(sh.lk or 0, sh.ln or 0) end
    for _, key in ipairs({ "z", "c", "hp", "hit", "dsp", "db", "cc", "dbt", "qs", "rep" }) do
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
                local n = src.hn and src.hn[l] or 1
                if not v.he[l] or h < v.he[l] then v.he[l] = h end
                v.hn[l] = (v.hn[l] or 0) + n
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
        -- (not one known by its name alone: its number here is made up)
        if r.n and id > 0 then
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
B.zoneNow = zoneNow

-- ── In a dungeon (0.1.622; reworked 0.1.645) ──────────────────────────────
-- Inside an instance the game hides who a creature is: its name comes back
-- hidden and so does the rest of what observe() goes by (a whole run of the
-- Wailing Caverns left twenty creatures with loot and no name, and some 230
-- kills of "a creature not in the book"). What is still said in the clear:
--   the experience line, with the name;
--   a corpse being looted, with which creature it was (its number);
--   your target's level and rank, with no name to them;
--   a boss's name, as its fight begins (MinimalUIDB.bossNames, UnitFrames).
-- So a dungeon's creature comes into the book by two doors, and the two are
-- made one:
--   * by its NAME, the moment one dies (the experience line): a record
--     under a made-up number below zero, which holds its kills, what a kill
--     is worth, where, and the level and rank of the one that died if it was
--     your target;
--   * by its NUMBER, when you loot one: a record with no name yet, which
--     holds the loot. Its name is asked of the game's own tooltip (askName,
--     below), which only answers once you are out of the instance.
-- The moment the numbered one gets its name, the other is folded into it.
-- (Until 0.1.645 what was known by name was kept out of the book until
-- then, in MinimalUIDB.bestiaryPend: a creature killed and never looted BY
-- YOU, which in a group is most of them, was never in it at all.)
local function idByName(name)
    local all = MinimalUIDB and MinimalUIDB.bestiary
    if not all then return end
    if not nameIndex then
        nameIndex = {}
        -- (a numbered record before one known by name alone, should both be there)
        for id, r in pairs(all) do
            if r.n and (id > 0 or nameIndex[r.n] == nil) then nameIndex[r.n] = id end
        end
    end
    return nameIndex[name]
end
-- The record of a creature known by its name alone: made here.
local function nameOnly(name)
    if not (MinimalUIDB and str(name)) then return end
    local n = 0
    for id in pairs(MinimalUIDB.bestiary or {}) do if id < 0 then n = n + 1 end end
    if n >= 400 then return end
    local seq = (MinimalUIDB.bestiarySeq or 0) + 1
    MinimalUIDB.bestiarySeq = seq
    local r = record(-seq, true)
    if not r then return end
    r.n = name
    nameIndex = nil
    return -seq, r
end
-- kind: what sort of instance z is ("party", "raid"...), when it is one. A
-- place first written down plainly and then met as an instance is marked.
local function addZone(r, z, kind)
    if not z then return end
    r.z = r.z or {}
    if r.z[z] == nil then
        if count(r.z) < 6 then r.z[z] = kind or true end
    elseif kind and r.z[z] == true then
        r.z[z] = kind
    end
end
-- Where you are, for the book: inside an instance, the instance's own name
-- (the zone's name is not to be relied on in there: for a moment after you
-- come in it is still the name of the place you came from, and a whole
-- dungeon was once filed under the city at its door), and what kind of
-- instance it is; anywhere else, the zone.
local function placeNow()
    if IsInInstance then
        local inside, kind = call(IsInInstance)
        if isTrue(inside) then
            kind = str(kind) and kind or "party"
            local name = GetInstanceInfo and call(GetInstanceInfo)
            local zone = zoneNow()
            if MinimalUIDB then
                -- (What the game calls the instance beside what it calls the
                -- zone in there: kept, a dozen at most, to see how they differ.)
                local dg = MinimalUIDB.instdiag
                if type(dg) ~= "table" then dg = {}; MinimalUIDB.instdiag = dg end
                local key = tostring(str(name) and name or "(no name given)") .. " / " .. tostring(zone)
                if dg[key] or count(dg) < 12 then dg[key] = (dg[key] or 0) + 1 end
            end
            return str(name) and name or zone, kind
        end
    end
    return zoneNow(), nil
end
B.placeNow = placeNow
-- (d: level, rank, kind as read off a target; r: a record)
local function addFacts(r, d)
    if d.l then
        if not r.lo or d.l < r.lo then r.lo = d.l end
        if not r.hi or d.l > r.hi then r.hi = d.l end
    end
    if d.lo then
        if not r.lo or d.lo < r.lo then r.lo = d.lo end
        if not r.hi or d.hi > r.hi then r.hi = d.hi end
    end
    if r.cl == nil then r.cl = d.cl end
    if r.t == nil then r.t = d.t end
    if r.f == nil then r.f = d.f end
    if r.ag == nil then r.ag = d.ag end
end
-- One record of a creature folded into another of the same creature (the
-- one known by name into the one with its number).
local function fold(r, s)
    addFacts(r, s)
    for _, key in ipairs({ "mana", "uc", "tame", "sk", "xp", "xl" }) do
        if r[key] == nil then r[key] = s[key] end
    end
    for z, kind in pairs(s.z or {}) do addZone(r, z, kind ~= true and kind or nil) end
    for _, key in ipairs({ "c", "db", "dbt", "cc", "qs", "rep", "hp", "hit", "dsp" }) do
        if s[key] then
            r[key] = r[key] or {}
            for k, v in pairs(s[key]) do
                local have = r[key][k]
                if have == nil or have == true or (type(v) == "number" and type(have) == "number" and v > have) then r[key][k] = v end
            end
        end
    end
    if s.hs then
        r.hs, r.he, r.hn = r.hs or {}, r.he or {}, r.hn or {}
        for L, h in pairs(s.hs) do
            r.hs[L] = r.hs[L] or {}
            for v, n in pairs(h) do r.hs[L][v] = (r.hs[L][v] or 0) + n end
            if r.he[L] == nil and s.he then r.he[L], r.hn[L] = s.he[L], s.hn and s.hn[L] or 1 end
        end
    end
    if s.q then
        r.q = r.q or {}
        local has = {}
        for _, line in ipairs(r.q) do has[line.t] = true end
        for _, line in ipairs(s.q) do
            if not has[line.t] and #r.q < 12 then has[line.t] = true; r.q[#r.q + 1] = line end
        end
    end
    -- (Its kills by the experience line are all of them; those counted at
    -- its corpse while it had no name are among them: the greater.)
    if (s.k or 0) > (r.k or 0) then r.k = s.k end
    if (s.lk or 0) > (r.lk or 0) then r.lk = s.lk end
    if s.kd then r.kd = (r.kd or 0) + s.kd end
end
-- (A record known by name that has been folded into a numbered one: where
-- it went, for a window that was showing it.)
local mergedTo = {}
B.mergedTo = mergedTo
local function setName(id, name)
    local r = record(id)
    if not r or r.n then return end
    local all = MinimalUIDB.bestiary
    local sid = id > 0 and idByName(name) or nil
    local s = sid and sid < 0 and all[sid] or nil
    r.n = name; nameIndex = nil
    if s then
        fold(r, s)
        all[sid] = nil
        mergedTo[sid] = id
    end
    changed(s and nil or id)
end
-- The creature you have targeted, by what can be read of it without
-- knowing which it is; and the one you had until a moment ago (the game
-- drops your target as it dies).
local tgt, tgtGone
local function noteTarget()
    if isTrue(call(UnitExists, "target")) then
        tgt = nil
        if isTrue(call(UnitIsPlayer, "target")) or isTrue(call(UnitPlayerControlled, "target")) then return end
        local react = call(UnitReaction, "target", "player")
        if not (plain(react) and react <= 4) then return end
        -- (A level of "??", which the game gives as a number below zero, is
        -- a boss: no level to keep, but its rank is as good as any. These
        -- were passed over whole until 0.1.645, and no boss had a rank.)
        local lvl = call(UnitLevel, "target")
        if not plain(lvl) then return end
        local kind = call(UnitCreatureType, "target")
        if str(kind) and kind == "Critter" then return end
        local cl, fam = call(UnitClassification, "target"), call(UnitCreatureFamily, "target")
        tgt = { l = lvl > 0 and lvl or nil, t = str(kind) and kind or nil, f = str(fam) and fam or nil,
                cl = str(cl) and RANK[cl] and cl or nil, ag = react < 4 and 1 or 0 }
    elseif tgt then
        tgtGone, tgt = tgt, nil
        tgtGone.at = GetTime()
    end
end
-- (The one that just died, if it was your target: asked once for each.)
local function deadTarget()
    if tgt and not tgt.used and isTrue(call(UnitIsDead, "target")) then tgt.used = true return tgt end
    if tgtGone and not tgtGone.used and GetTime() - tgtGone.at < 1.5 then tgtGone.used = true return tgtGone end
end
-- (What stopped a creature being read, inside an instance: counted.)
local function obsWhy(what)
    if not (MinimalUIDB and IsInInstance and isTrue((call(IsInInstance)))) then return end
    local d = MinimalUIDB.obsdiag or {}
    MinimalUIDB.obsdiag = d
    d[what] = (d[what] or 0) + 1
end

-- A creature in front of you: unit is your target, what the mouse is on,
-- or a nameplate. seen[guid]: 1 once its standing facts are written, 2 once
-- its health is too (nothing more to learn from looking at this one).
local seen, nSeen = {}, 0
local noteTip -- (below: what its tooltip says)
local function observe(unit)
    local id, guid = npcID(unit)
    if not id then
        if secret(call(UnitGUID, unit)) then obsWhy("which creature: hidden") end
        return
    end
    if seen[guid] == 2 then return end
    local can = call(UnitCanAttack, "player", unit)
    if not isTrue(can) then
        if secret(can) then obsWhy("whether it can be attacked: hidden") end
        return
    end
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
    -- (The level of the one you last had targeted, kept for its death:
    -- the game drops your target as it dies, so the kill, counted from the
    -- experience line, had no level, and its health sample went under
    -- "level not known": one in five did, and all of some creatures'. 0.1.609)
    if okLvl and unit == "target" then
        B.tl = B.tl or {}
        local e = B.tl[id] or {}
        B.tl[id] = e
        e.l, e.t = lvl, GetTime()
    end
    if first then
        local name = call(UnitName, unit)
        if str(name) then
            if r.n then r.n = name else setName(id, name) end
        else
            obsWhy(secret(name) and "read, but its name hidden" or "read, no name")
        end
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
        local pt, pm = call(UnitPowerType, unit), call(UnitPowerMax, unit, 0)
        if plain(pt) and pt == 0 and plain(pm) and pm > 0 and not r.mana then r.mana = true; new = true end
        local _, uc = call(UnitClass, unit)
        if str(uc) then r.uc = uc end
        pcall(noteTip, unit, id, r)
        local z, zk = placeNow()
        if z then
            local had = r.z and r.z[z]
            addZone(r, z, zk)
            if r.z[z] ~= had then new = true end
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

-- What the game's own tooltip says of it: that a hunter can tame it, how
-- its corpse can be gathered, which of your quests it counts for.
local SKIN = {}
SKIN[_G.UNIT_SKINNABLE_LEATHER or "Skinnable"] = "leather"
SKIN[_G.UNIT_SKINNABLE_HERB or "Requires Herbalism"] = "herb"
SKIN[_G.UNIT_SKINNABLE_ROCK or "Requires Mining"] = "rock"
SKIN[_G.UNIT_SKINNABLE_BOLTS or "Requires Engineering"] = "bolts"
function noteTip(unit, id, r)
    local TI = C_TooltipInfo
    if not (TI and TI.GetUnit) then return end
    local data = call(TI.GetUnit, unit)
    local lines = type(data) == "table" and data.lines
    if type(lines) ~= "table" then return end
    local QT = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle
    local new = false
    for i = 2, #lines do
        local ln = lines[i]
        local text = type(ln) == "table" and ln.leftText
        if str(text) then
            if text == (_G.TAMEABLE or "Tameable") then
                if not r.tame then r.tame = true; new = true end
            elseif SKIN[text] then
                if r.sk ~= SKIN[text] then r.sk = SKIN[text]; new = true end
            elseif QT and not secret(ln.type) and ln.type == QT then
                r.qs = r.qs or {}
                if not r.qs[text] and count(r.qs) < 4 then r.qs[text] = true; new = true end
            end
        end
    end
    if new then changed(id) end
end
-- (A corpse: looked at again, for "Skinnable", which only a corpse says.)
local corpseSeen, nCorpse = {}, 0
local function noteCorpse(unit)
    if not isTrue(call(UnitIsDead, unit)) then return end
    local id, guid = npcID(unit)
    local r = id and record(id)
    if not r or corpseSeen[guid] then return end
    if nCorpse > 300 then wipe(corpseSeen); nCorpse = 0 end
    corpseSeen[guid] = true; nCorpse = nCorpse + 1
    noteTip(unit, id, r)
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
    local dg = MinimalUIDB[key]
    if type(dg) ~= "table" then dg = {}; MinimalUIDB[key] = dg end
    dg[what] = (dg[what] or 0) + 1
end
-- The name of a creature known only by its number (a looted corpse in a
-- dungeon): the game's tooltip for it, asked by that number. The first
-- asking can come back empty (the game fetches it), so it is asked again.
local function askName(id, guid)
    local r = record(id)
    if not r then return end
    if r.n then return r.n end
    local TI = C_TooltipInfo
    if not (TI and TI.GetHyperlink) then diag("namediag", "no way to ask") return end
    local data = call(TI.GetHyperlink, "unit:" .. (guid or ("Creature-0-0-0-0-" .. id .. "-0000000000")))
    local ln = type(data) == "table" and type(data.lines) == "table" and data.lines[1]
    local text = type(ln) == "table" and ln.leftText or nil
    if secret(text) then diag("namediag", "name hidden") return end
    if not str(text) or text == (_G.UNKNOWN or "Unknown") or text:find("^Retrieving") then
        diag("namediag", "no answer")
        return
    end
    diag("namediag", "named")
    -- (What the tooltip says below the name, for the first few: a creature
    -- named this way has no kind and often no level, and if the game puts
    -- "Level 16 Undead (Elite)" there, that is where to get them.)
    if MinimalUIDB then
        local td = MinimalUIDB.bestiaryTip
        if type(td) ~= "table" then td = {}; MinimalUIDB.bestiaryTip = td end
        if #td < 8 then
            local more = {}
            for i = 2, math.min(#data.lines, 5) do
                local l = data.lines[i]
                local t = type(l) == "table" and l.leftText
                more[#more + 1] = str(t) and t or (secret(t) and "(hidden)" or "(nothing)")
            end
            td[#td + 1] = text .. ": " .. (#more > 0 and table.concat(more, " | ") or "no more lines")
        end
    end
    setName(id, text)
    -- (Where it was looted. Asked later, at login, you are somewhere else:
    -- 0.1.622 filed a whole dungeon under the zone outside its door.)
    if guid then addZone(r, placeNow()) end
    return text
end
local function nameTheNameless()
    local n = 0
    for id, r in pairs(MinimalUIDB and MinimalUIDB.bestiary or {}) do
        if not r.n and n < 60 then
            n = n + 1
            askName(id)
        end
    end
    return n
end
-- Reputation for a kill: the game's line "Reputation with X increased by
-- N" names no creature. It goes to the kill it arrives with (two seconds
-- either side).
local lastKill, repWait = nil, {}
local function attachRep(id, faction, n)
    local r = record(id)
    if not r then return end
    r.rep = r.rep or {}
    if r.rep[faction] == nil and count(r.rep) >= 3 then return end
    if r.rep[faction] ~= n then r.rep[faction] = n; changed(id) end
end
local function noteRep(text)
    if not str(text) then return end
    local faction, n = text:match("eputation with (.-) increased by (%d+)")
    if faction then n = tonumber(n)
    else
        faction, n = text:match("eputation with (.-) decreased by (%d+)")
        n = faction and -tonumber(n) or nil
    end
    if not (faction and n) then return end
    local now = GetTime()
    if lastKill and now - lastKill.t < 2 then attachRep(lastKill.id, faction, n)
    elseif #repWait < 6 then repWait[#repWait + 1] = { f = faction, n = n, t = now } end
end
-- looted: counted as its corpse was opened.
-- (lk is what an item's rate is out of: kills whose corpse you could have
-- opened. On your own that is every kill, and one you walked away from
-- counts as nothing found. In a group most corpses are someone else's to
-- open: fifty-eight kills of a creature with eleven corpses opened put every
-- drop at a fifth of its true rate. There only the corpses opened count,
-- since 0.1.645.)
local function addKill(id, lvl, inFight, looted)
    local r = record(id, true)
    r.k = (r.k or 0) + 1
    if looted or not (IsInGroup and isTrue((call(IsInGroup)))) then r.lk = (r.lk or 0) + 1 end
    local now = GetTime()
    lastKill = { id = id, t = now }
    for _, w in ipairs(repWait) do
        if now - w.t < 2 then attachRep(id, w.f, w.n) end
    end
    wipe(repWait)
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
    local name = (r and r.n) or askName(id, guid)
    if take(owedByXP, name, 300) then return end
    diag("killdiag", "counted when looted")
    addKill(id, nil, false, true)
end
local function noteXP(text)
    if secret(text) then diag("killdiag", "experience line hidden") return end
    if not str(text) then return end
    local name = text:match("^(.-) dies, you gain")
    if not name then diag("killdiag", "experience line, other wording") return end
    local id = idByName(name)
    local gained = tonumber(text:match("you gain (%d+) experience"))
    local mine = call(UnitLevel, "player")
    if not id then
        -- (No such creature in the book: it goes in by its name alone, and
        -- is counted like any other from here on. See "In a dungeon".)
        diag("killdiag", "experience line, creature not in the book")
        id = nameOnly(name)
        if not id then
            owe(owedByXP, name)
            return
        end
    end
    local rx = record(id)
    if rx and gained and gained > 0 then
        rx.xp, rx.xl = gained, plain(mine) and mine or nil
    end
    if take(owedBySight, name, 10) then return end
    owe(owedByXP, name)
    local lvl
    if npcID("target") == id then
        lvl = call(UnitLevel, "target")
        lvl = plain(lvl) and lvl > 0 and lvl or nil
    end
    local r = record(id)
    if not lvl and r and r.lo and r.lo == r.hi then lvl = r.lo end
    local e = not lvl and B.tl and B.tl[id]
    if e and GetTime() - e.t < 120 then lvl = e.l end
    if r and not r.uc then
        -- (One never read as a creature: known by its name, or named from
        -- its corpse, in a dungeon. Where it died is kept each time; its
        -- level and rank when the one that died was your target.)
        addZone(r, placeNow())
        local d = deadTarget()
        if d then
            addFacts(r, d)
            lvl = d.l or lvl
        end
    end
    diag("killdiag", "counted from the experience line")
    addKill(id, lvl, true)
end

-- Stuns, fears and the like (0.1.588). When you lose control of your
-- character the game says so, with what did it and what kind it is (this
-- is what its own "Stunned" banner is drawn from). It does not say who:
-- it is put down to your target if that is a creature you are fighting,
-- else kept until the fight ends and given to what you killed, if that
-- was one thing.
local CONTROL = { STUN = "Stuns", STUN_MECHANIC = "Stuns", FEAR = "Fears", FEAR_MECHANIC = "Fears", ROOT = "Roots",
                  SILENCE = "Silences", DISARM = "Disarms", CONFUSE = "Confuses", CHARM = "Charms", POSSESS = "Takes you over",
                  PACIFY = "Pacifies", PACIFYSILENCE = "Pacifies", SCHOOL_INTERRUPT = "Interrupts your casting",
                  DISORIENT = "Disorients", INCAPACITATE = "Incapacitates", SAP = "Incapacitates", CYCLONE = "Lifts you out of the fight",
                  BANISH = "Banishes", SNARE = "Slows", DAZE = "Dazes", SLEEP = "Puts you to sleep", HORROR = "Fears", POLYMORPH = "Polymorphs" }
function B.ControlWord(kind) return CONTROL[kind] or kind end
local controlWait = {}
local function creditControl(id, name, kind, sid)
    local r = id and record(id)
    if not r then return end
    r.cc = r.cc or {}
    -- (a kind learned later replaces "unknown"; a name learned later replaces "?")
    if name ~= "?" and r.cc["?"] then r.cc["?"] = nil end
    if (r.cc[name] == nil and count(r.cc) < 8) or (r.cc[name] == "UNKNOWN" and kind ~= "UNKNOWN") then
        if not (name == "?" and next(r.cc)) then r.cc[name] = kind; changed(id) end
    end
    r.c = r.c or {}
    if plain(sid) and (r.c[name] == nil or r.c[name] == true) then r.c[name] = sid end
end
local function noteControl()
    local L = C_LossOfControl
    local get = L and (L.GetActiveLossOfControlData or L.GetEventInfo)
    local n = L and L.GetActiveLossOfControlDataCount and call(L.GetActiveLossOfControlDataCount) or 1
    if not get then diag("ccdiag", "no way to ask") return end
    if not plain(n) then diag("ccdiag", "count hidden") return end
    for i = 1, math.min(n, 4) do
        local d = call(get, i)
        if type(d) ~= "table" then diag("ccdiag", "nothing given")
        else
            local kind, sid = d.locType, d.spellID
            -- (0.1.599) In a fight the game hides what kind it was (a kodo's
            -- knock-down came through as "kind hidden", twice). That it
            -- happened at all is still worth an icon: kept as UNKNOWN, with
            -- the spell's name if that much is given. Which of the notice's
            -- fields can be read is counted, to see what else there is.
            if not str(kind) then
                diag("ccdiag", secret(kind) and "kind hidden" or "no kind")
                for _, f in ipairs({ "spellID", "displayText", "iconTexture", "duration", "lockoutSchool", "priority" }) do
                    local v = d[f]
                    diag("ccdiag", f .. (secret(v) and " hidden" or (v == nil and " absent" or " readable")))
                end
                kind = "UNKNOWN"
            end
            do
                local name = plain(sid) and C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, sid)
                if not str(name) then name = str(d.displayText) and d.displayText or (kind == "UNKNOWN" and "?" or kind) end
                if not plain(sid) then sid = nil end
                diag("ccdiag", "got " .. kind)
                local id = npcID("target")
                if id and isTrue(call(UnitCanAttack, "player", "target")) then
                    creditControl(id, name, kind, sid)
                elseif #controlWait < 8 then
                    controlWait[#controlWait + 1] = { name = name, kind = kind, sid = sid }
                end
            end
        end
    end
end

-- Health, worked out. The game hides a creature's health from addons, but
-- its own damage meter can be read once a fight is over, and it keeps the
-- fight just ended apart ("session 1").
-- 0.1.577 took how much your damage total went up by in a fight with one
-- kill. That was far off (764 for a creature of 427): anything else you
-- hit in the fight was in the sum, and kills were being missed, so a
-- fight with two looked like a fight with one.
-- 0.1.585: the meter's "enemy damage taken", where this client has it: one
-- line per enemy with what that one took and whether it died, which for
-- one that died from full is its health. Failing that, your and your
-- pet's damage in a fight with one kill, as before. Less the last blow's
-- excess when only one died (the meter keeps it apart). Every sample is
-- kept by its value (hs), and what is shown is the value seen most often,
-- the lower of two seen as often: an already hurt creature or a second
-- enemy gives an odd number once, the true figure comes up again and again.
-- The same reading says what hit you: the meter's "damage taken" lists
-- each attack with the creature that made it, which is how attacks with
-- no cast bar (and plain melee) get into the book without a death recap.
local function meterLog(line)
    if not MinimalUIDB then return end
    -- (Its own name, 0.1.589: "meterdiag" is a line of text the nameplates
    -- keep, and writing a log into that failed, which stopped the whole
    -- reading: five kills of a creature and no health to show for it.)
    local dg = MinimalUIDB.bestiaryMeter
    if type(dg) ~= "table" then dg = {}; MinimalUIDB.bestiaryMeter = dg end
    dg.log = dg.log or {}
    if #dg.log < 40 then dg.log[#dg.log + 1] = line end
end
-- Which of the samples to believe (0.1.590). What can be read is the
-- damage you did in a fight with one kill, and on this client the last
-- blow's excess is not told apart, nor is there a per-enemy view: so a
-- sample is the creature's health plus whatever the last blow did beyond
-- it, plus anything else you hit. Never less than its health, unless it
-- was already hurt. So the least sample is the nearest (a level 15 with
-- 346 had been put at 330-428: the 428 was a fight with a stray hit in
-- it). The least is passed over only when it stands well apart from the
-- next (under four fifths of it, with three samples or more): that one
-- was already hurt. hn is how many samples there are.
local function settle(r, L)
    local h = r.hs and r.hs[L]
    if not h then return end
    local vals, n = {}, 0
    for v, c in pairs(h) do vals[#vals + 1] = v; n = n + c end
    if #vals == 0 then return end
    table.sort(vals)
    local best = vals[1]
    if n >= 3 and vals[2] and vals[1] < vals[2] * 0.8 and h[vals[1]] == 1 then best = vals[2] end
    r.he, r.hn = r.he or {}, r.hn or {}
    r.he[L], r.hn[L] = best, n
end
local function healthSample(id, lvl, value)
    local r = record(id)
    local L = lvl or 0 -- (0: which level it was is not known)
    if not r or value <= 0 or (r.hp and r.hp[L]) then return end
    r.hs = r.hs or {}
    local h = r.hs[L] or {}
    r.hs[L] = h
    h[value] = (h[value] or 0) + 1
    if count(h) > 10 then -- (the rarest goes, the largest of those)
        local drop
        for v, n in pairs(h) do
            if v ~= value and (not drop or n < h[drop] or (n == h[drop] and v > drop)) then drop = v end
        end
        if drop then h[drop] = nil end
    end
    settle(r, L)
    changed(id)
end
local function fightStart()
    wipe(fightKills)
end
-- (0.1.587) Five kills and nothing learned: the meter was asked 0.6 s
-- after the fight, when its figures are still hidden (they were plain
-- when a probe asked 4 s after), and this client has no list of the
-- meter's views by name (Enum.DamageMeterType), so the two views wanted
-- were never asked for at all. Now: asked again, later, until the figures
-- can be read (readMeter says false while they can't); and the views are
-- found by what is in them. One that lists creatures is taken for "what
-- each enemy took" only if what it says they took, all together, is close
-- to what you and your pet did, in a fight you fought alone.
local function readMeter(kills)
    local DM = C_DamageMeter
    if not (DM and DM.GetCombatSessionSourceFromType) then return true end
    local me = call(UnitGUID, "player")
    if not str(me) then return true end
    local mine = call(DM.GetCombatSessionSourceFromType, 1, 0, me)
    if type(mine) == "table" and secret(mine.totalAmount) then return false end
    local nKilled, levelOf, killed = #kills, {}, {}
    for _, k in ipairs(kills) do
        levelOf[k.id] = k.lvl or levelOf[k.id]
        killed[k.id] = true
    end
    -- what you and your pet did in the fight, and the excess of the last blows
    local done, over = 0, 0
    for _, g in ipairs({ me, call(UnitGUID, "pet") }) do
        local src = str(g) and call(DM.GetCombatSessionSourceFromType, 1, 0, g)
        if type(src) == "table" then
            if plain(src.totalAmount) then done = done + src.totalAmount end
            for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
                if plain(sp.overkillAmount) then over = over + sp.overkillAmount end
            end
        end
    end
    local alone = not (IsInGroup and isTrue(call(IsInGroup)))
    meterLog("fight read: you did " .. done .. ", excess " .. over .. ", kills noted " .. nKilled)
    local sampled = false
    if DM.GetCombatSessionFromType and nKilled > 0 and done > 0 then
        for n = 1, 15 do
            local ses = call(DM.GetCombatSessionFromType, 1, n)
            local list = type(ses) == "table" and type(ses.combatSources) == "table" and ses.combatSources or nil
            if list and list[1] and npcOf(list[1].sourceGUID) then
                local sum = 0
                for _, src in ipairs(list) do
                    if plain(src.totalAmount) then sum = sum + src.totalAmount end
                    meterLog("view " .. n .. ": " .. tostring(str(src.name) and src.name or "?") .. " " .. tostring(plain(src.totalAmount) and src.totalAmount or "?")
                        .. " death " .. tostring(plain(src.deathTimeSeconds) and src.deathTimeSeconds or "?"))
                end
                if not sampled and alone and sum >= done * 0.9 and sum <= done * 1.05 + 1 then
                    for _, src in ipairs(list) do
                        local id = npcOf(src.sourceGUID)
                        local total = src.totalAmount
                        if id and killed[id] and plain(total) and total > 0 then
                            local v = total
                            if nKilled == 1 and over < v then v = v - over end
                            healthSample(id, levelOf[id], math.floor(v + 0.5))
                            sampled = true
                        end
                    end
                end
            end
        end
    end
    if not sampled and nKilled == 1 and done > over and alone then
        healthSample(kills[1].id, kills[1].lvl, math.floor(done - over + 0.5))
    end
    -- In a group (0.1.647): a fight in which one thing died, which in a
    -- dungeon is mostly a boss. What the whole group did to it, everyone's
    -- damage and their pets' together, less the last blow's excess, is its
    -- health: the same sum as on your own, with more hands in it. Only when
    -- every member's figure can be read (one still hidden: asked again
    -- later, like your own). It runs high if something else was hit and
    -- lived, low if the creature was already hurt or healed itself: a
    -- sample like any other, shown with "~" until it comes up again.
    -- (MinimalUIDB.grouphp counts how these readings went.)
    if not alone and nKilled == 1 then
        local sum, ov, hidden, hands, seenG = done, over, false, done > 0 and 1 or 0, { [me] = true }
        local raid = IsInRaid and isTrue((call(IsInRaid)))
        for i = 1, raid and 40 or 4 do
            for _, unit in ipairs({ (raid and "raid" or "party") .. i, (raid and "raidpet" or "partypet") .. i }) do
                local g = call(UnitGUID, unit)
                if str(g) and not seenG[g] then
                    seenG[g] = true
                    local src = call(DM.GetCombatSessionSourceFromType, 1, 0, g)
                    if type(src) == "table" then
                        if secret(src.totalAmount) then hidden = true
                        elseif plain(src.totalAmount) and src.totalAmount > 0 then
                            sum, hands = sum + src.totalAmount, hands + 1
                            for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
                                if plain(sp.overkillAmount) then ov = ov + sp.overkillAmount end
                            end
                        end
                    end
                end
            end
        end
        if hidden then
            diag("grouphp", "a member's figure still hidden: asked again")
            return false
        elseif hands < 2 then
            diag("grouphp", "nobody's damage but yours could be read: no sample")
        elseif sum > ov then
            diag("grouphp", "sampled")
            healthSample(kills[1].id, kills[1].lvl, math.floor(sum - ov + 0.5))
        end
    end
    -- what hit you: a view in which your own line lists attacks by creature
    local got = false
    for n = 1, 15 do
        local taken = not got and call(DM.GetCombatSessionSourceFromType, 1, n, me)
        for _, sp in ipairs(type(taken) == "table" and type(taken.combatSpells) == "table" and taken.combatSpells or {}) do
            local sid = sp.spellID
            local who = str(sp.creatureName) and sp.creatureName or nil
            if who then
                got = true
                meterLog("view " .. n .. ": hit by " .. who .. " spell " .. tostring(plain(sid) and sid or "?") .. " total "
                    .. tostring(plain(sp.totalAmount) and sp.totalAmount or "?"))
                local id = idByName(who)
                local r = id and record(id)
                if r and plain(sid) then
                    local name = sid == 6603 and "Melee" or (C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, sid))
                    if str(name) then
                        r.c = r.c or {}
                        if (r.c[name] == nil and count(r.c) < 16) or r.c[name] == true then
                            r.c[name] = sid
                            changed(id)
                        end
                    end
                end
            end
        end
    end
    return true
end
local function fightEnd(kills, try)
    if InCombatLockdown() then return end
    local ok, read = pcall(readMeter, kills)
    if not ok then meterLog("error: " .. tostring(read)) end
    if ok and read == false then
        if try < 6 then
            C_Timer.After(try < 3 and 1 or 3, function() fightEnd(kills, try + 1) end)
        else
            meterLog("the meter stayed hidden for 12 s after a fight")
        end
        return
    end
    local fightKills = kills
    if #kills == 1 then
        for _, w in ipairs(controlWait) do creditControl(kills[1].id, w.name, w.kind, w.sid) end
    end
    wipe(controlWait)
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
                    if str(a.dispelName) and r.db[name] ~= nil then
                        r.dbt = r.dbt or {}
                        r.dbt[name] = a.dispelName
                    end
                end
            end
        end
    end)
end

-- Its loot table (0.1.569): every item on every corpse you open, and how
-- many corpses of it you have opened, so each item has a rate: corpses
-- that had it out of corpses looted. A corpse is counted once (seenLoot by
-- its id), an item once per corpse whatever the stack. A slot can come
-- from several corpses at once (looting a heap): each is credited.
-- A corpse with nothing on it can't be opened, so it is never counted:
-- the rates are "of those that had anything", a little high.
local coinNow -- (the coin in the slot being read: to the first corpse it came from)
local function creditLoot(item, guid, ...)
    if guid == nil then return end
    local id = npcOf(guid)
    if id then
        local r = record(id, true)
        if coinNow then
            r.cn = (r.cn or 0) + coinNow
            coinNow = nil
        end
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
local coinSeen = {}
local function noteLoot()
    if not (GetNumLootItems and GetLootSourceInfo and GetLootSlotLink) then return end
    local n = call(GetNumLootItems)
    if not plain(n) then return end
    for slot = 1, n do
        local link = call(GetLootSlotLink, slot)
        local item = str(link) and tonumber(link:match("item:(%d+)")) or nil
        coinNow = nil
        if not item and GetLootSlotInfo then
            -- (a slot with no item is coin: "1 Silver 20 Copper", read once for each corpse)
            local _, text = call(GetLootSlotInfo, slot)
            local src = call(GetLootSourceInfo, slot)
            if str(text) and str(src) and not coinSeen[src] then
                local c = (tonumber(text:match("(%d+) Gold")) or 0) * 10000 + (tonumber(text:match("(%d+) Silver")) or 0) * 100
                    + (tonumber(text:match("(%d+) Copper")) or 0)
                if c > 0 then coinNow = c; coinSeen[src] = true end
            end
        end
        pcall(function() creditLoot(item, GetLootSourceInfo(slot)) end)
        coinNow = nil
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
-- "grabs for her poisoned dagger" and "grabs for his poisoned dagger" are
-- one line said by two creatures of a kind: kept once, as "their" (0.1.608).
local THEY = { his = "their", her = "their", himself = "themselves", herself = "themselves" }
local function neutral(text)
    return (text:gsub("%f[%a]([Hh][ie]%a+)%f[%A]", function(w)
        local to = THEY[w:lower()]
        if not to then return nil end
        return w:sub(1, 1) == "H" and (to:sub(1, 1):upper() .. to:sub(2)) or to
    end))
end
local function noteSpeech(kind, text, who, lang)
    if not (str(text) and str(who)) then return end
    local id = idByName(who)
    local r = id and record(id)
    if not r then return end
    local me = call(UnitName, "player")
    if str(me) then text = text:gsub(me:gsub("%p", "%%%0"), "$N") end
    local clear = understood(lang)
    if clear then text = neutral(text) end
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
      "Runs when badly hurt, and may come back with others.", "micro_pointer.tga" },
    -- ("lets out a shriek, calling for help!": the Sunscale Screecher, 0.1.603)
    { { "for help", "for aid", "for assistance", "calls for reinforcements" }, "Calls for help",
      "Brings nearby allies into the fight.", "micro_group.tga" },
    { { "enrage" }, "Enrages", "Hits harder or faster once it is hurt.", "micro_stat_str.tga" },
    { { "frenzy" }, "Goes into a frenzy", "Attacks faster for a while.", "micro_stat_str.tga" },
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

-- Its rank, as shown. A dungeon's boss is plain "elite" to the game (or
-- has no rank read at all, its level being "??"): it is a boss here if a
-- boss fight of its name has been begun (MinimalUIDB.bossNames, kept by the
-- unit frames since they first marked bosses).
local function rankOf(r)
    local names = MinimalUIDB and MinimalUIDB.bossNames
    if r.n and type(names) == "table" and names[r.n] and r.cl ~= "rare" then return "worldboss" end
    return r.cl
end
B.RankOf = rankOf

-- The traits (0.1.592): what is true of a creature that a small picture
-- can say, each with a tooltip. The bestiary shows them as a strip of
-- round icons under its name, in place of rows of words.
local BLUE, GOLD, GREEN, GREY = { 0.45, 0.68, 1.00 }, { 0.95, 0.80, 0.35 }, { 0.45, 0.85, 0.50 }, { 0.62, 0.62, 0.68 }
local DISPEL = { Poison = { "micro_dispel_poison.tga", { 0.45, 0.85, 0.40 } }, Disease = { "micro_dispel_disease.tga", { 0.80, 0.62, 0.35 } },
                 Curse = { "micro_dispel_curse.tga", { 0.72, 0.45, 0.95 } }, Magic = { "micro_dispel_magic.tga", { 0.45, 0.68, 1.00 } } }
local GATHER = { leather = { "Skinnable", "Its corpse can be skinned." }, herb = { "Herbs on its corpse", "Its corpse can be gathered with Herbalism." },
                 rock = { "Ore on its corpse", "Its corpse can be mined." }, bolts = { "Parts on its corpse", "Its corpse can be salvaged with Engineering." } }
local VERB = { Pacifies = "pacify", Banishes = "banish" } -- ("Stuns" gives "stun" by itself; these don't)
function B.Traits(id)
    local r = id and view(id)
    local t = {}
    if not r then return t end
    local function add(tex, c, title, text) t[#t + 1] = { tex = MEDIA .. tex, c = c, title = title, text = text } end
    if r.ag == 1 then add("micro_stat_melee.tga", RED, "Hostile", "Attacks you on sight.")
    elseif r.ag == 0 then add("micro_stat_melee.tga", GOLD, "Neutral", "Leaves you alone unless you attack it.") end
    local rk = rankOf(r)
    if rk == "rare" then add("micro_achievement.tga", RARE, "Rare", "A rare spawn: not often there.")
    elseif rk == "worldboss" then add("micro_achievement.tga", ELITE, "Boss", "A boss: a fight of its own, far tougher than its level says.")
    elseif rk then add("micro_achievement.tga", ELITE, RANK[rk] or "Elite", "Much tougher than its level says.") end
    if r.mana or r.uc == "MAGE" then add("micro_stat_spell.tga", BLUE, "Caster", "Has mana and casts spells.")
    elseif r.uc == "PALADIN" then add("micro_stat_spell.tga", GREY, "Fighter with spells", "Fights hand to hand, with some mana to call on.") end
    local seenB = {}
    for _, line in ipairs(r.q or {}) do
        local b = B.BehaviorOf(line)
        if b and not seenB[b] then
            seenB[b] = true
            add(b[4] or "micro_eye.tga", GREY, b[2], b[3])
        end
    end
    local said = {} -- (abilities an icon has already spoken for)
    for name, kind in pairs(r.cc or {}) do
        local word = B.ControlWord(kind)
        local verb = VERB[word] or (not word:find(" ") and word:lower():gsub("s$", "")) or nil
        if kind == "UNKNOWN" then
            add("micro_stat_resist.tga", RED, "Disables you",
                "Can stun you, knock you down or otherwise take control of your character" .. (name ~= "?" and (" with " .. name) or "")
                .. ". The game does not say which in a fight.")
        else
            add("micro_stat_resist.tga", RED, word, verb and ("Can " .. verb .. " you with " .. name .. ".") or (word .. ", with " .. name .. "."))
        end
        if name ~= "?" then said[name] = true end
    end
    local byKind = {}
    for name, kind in pairs(r.dbt or {}) do
        if DISPEL[kind] then
            byKind[kind] = byKind[kind] or {}
            table.insert(byKind[kind], name)
            said[name] = true
        end
    end
    for kind, list in pairs(byKind) do
        table.sort(list)
        local same = #list == 1 and list[1]:lower() == kind:lower()
        add(DISPEL[kind][1], DISPEL[kind][2], kind, "Can apply " .. (same and kind:lower() or (table.concat(list, ", ") .. " (" .. kind:lower() .. ")")) .. ".")
    end
    -- its attacks and abilities, each as its own picture (the spell's),
    -- after the kinds above: what it casts, what hit you, what it applied
    local names, list = {}, {}
    for name in pairs(r.c or {}) do names[name] = true end
    for name in pairs(r.hit or {}) do names[name] = true end
    for name in pairs(r.db or {}) do names[name] = true end
    for name in pairs(names) do if not said[name] then list[#list + 1] = name end end
    table.sort(list, function(a, b) if (a == "Melee") ~= (b == "Melee") then return a == "Melee" end return a < b end)
    for _, name in ipairs(list) do
        local sid = (r.c and type(r.c[name]) == "number" and r.c[name]) or (r.db and type(r.db[name]) == "number" and r.db[name]) or nil
        local hit = r.hit and r.hit[name]
        local tex = name == "Melee" and MELEE_ICON or (sid and C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, sid)) or nil
        local bits = {}
        if r.db and r.db[name] ~= nil then bits[#bits + 1] = "Can apply " .. name .. "." end
        if r.c and r.c[name] ~= nil and name ~= "Melee" then bits[#bits + 1] = "Seen using it." end
        if hit then bits[#bits + 1] = "Hardest hit on you: " .. hit .. "." end
        if name ~= "Melee" or hit then
            t[#t + 1] = { raw = (str(tex) or plain(tex)) and tex or "Interface/Icons/INV_Misc_QuestionMark", c = { 0.86, 0.86, 0.89 },
                          title = name, text = table.concat(bits, " "), sid = name ~= "Melee" and sid or nil }
        end
    end
    if r.tame then add("micro_class_hunter.tga", GREEN, "Tameable", "A hunter can tame it." .. (r.f and (" Family: " .. r.f .. ".") or ""))
    elseif r.t == "Beast" and r.f then add("micro_class_hunter.tga", GREY, "Likely tameable", "A beast of the " .. r.f .. " family. Not confirmed: only a hunter is told.") end
    if r.sk and GATHER[r.sk] then add(r.sk == "leather" and "micro_skin.tga" or (r.sk == "rock" and "micro_node_ore.tga" or "micro_node.tga"), GOLD, GATHER[r.sk][1], GATHER[r.sk][2]) end
    if r.qs and next(r.qs) then
        local names = {}
        for q in pairs(r.qs) do names[#names + 1] = q end
        table.sort(names)
        add("micro_quest.tga", GOLD, "Quest target", "Counted for: " .. table.concat(names, ", ") .. ".")
    end
    if r.rep and next(r.rep) then
        local bits, gain = {}, false
        for f, n in pairs(r.rep) do bits[#bits + 1] = f .. " " .. (n > 0 and "+" or "") .. n; if n > 0 then gain = true end end
        table.sort(bits)
        add("micro_guild.tga", gain and GREEN or RED, "Reputation", "For a kill: " .. table.concat(bits, ", ") .. ".")
    end
    return t
end
local function coins(c) return ns.Money(c) or "" end

local lootOpen = {} -- (creatures whose whole loot list is open: this session)
-- An item's name is only known once the game has fetched the item, which
-- it has not for things you looked at in another session (a dungeon's loot,
-- a day later, read "Item 6631": 0.1.648). One with no name yet is asked
-- for, once, and the page it is on is drawn again when the answer comes.
local itemWait, itemAsked = {}, {}
local function wantItem(item, id)
    itemWait[item] = id
    if not itemAsked[item] then
        itemAsked[item] = true
        local req = C_Item and C_Item.RequestLoadItemDataByID
        if req then pcall(req, item) end
    end
end
do
    local iw = CreateFrame("Frame")
    pcall(iw.RegisterEvent, iw, "GET_ITEM_INFO_RECEIVED")
    iw:SetScript("OnEvent", function(_, _, item)
        local id = type(item) == "number" and not secret(item) and itemWait[item]
        if id then
            itemWait[item] = nil
            changed(id)
        end
    end)
end
function B.Rows(rows, id, full)
    local r = id and view(id)
    if not r then
        rows[#rows + 1] = { kind = "stat", value = "",
            label = id and "Nothing yet: it fills in as you meet it" or "Nothing is kept for this one" }
        return rows
    end
    if full then
        -- (Type, rank and disposition are in the header line and the icons.)
        head(rows, "About", "micro_character.tga")
        if r.f then stat(rows, "Family", r.f) end
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
    -- Health, on one line (0.1.586, as asked):
    --   "~345"     still being worked out: a figure, or "~307-345", from
    --              too few samples to stand on;
    --   "307-345"  settled: every level it comes in has a figure that has
    --              come up at least twice (or that the game gave outright),
    --              lowest level's to highest's; one level, one number.
    -- The tooltip has each level's figure and how often it has come up.
    do
        local SURE = 3
        local function big(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
        local by, lv = {}, {}
        for l, h in pairs(r.he or {}) do by[l] = { h = h, n = r.hn and r.hn[l] or 1 } end
        for l, h in pairs(r.hp or {}) do by[l] = { h = h, n = SURE, exact = true } end
        local leveled = false
        for l in pairs(by) do if l > 0 then leveled = true end end
        if leveled then by[0] = nil end -- (a sample whose level is not known: only when there is nothing else)
        for l in pairs(by) do lv[#lv + 1] = l end
        table.sort(lv)
        if #lv == 0 then
            rows[#rows + 1] = { kind = "stat", label = "Health", value = "not learned yet", color = T.textDim,
                tooltip = function(tip)
                    tip:SetText("Health", 1, 1, 1)
                    tip:AddLine("The game hides a creature's health from addons. It is worked out from the damage it takes when you kill one.",
                        0.86, 0.86, 0.89, true)
                    if not r.t and not r.uc then
                        tip:AddLine(" ")
                        tip:AddLine("In a group it is worked out from everyone's damage, in a fight where nothing else dies: for a boss, the next time you kill it.",
                            0.6, 0.6, 0.65, true)
                    end
                end }
        else
            local lowest, highest
            for _, l in ipairs(lv) do
                local h = by[l].h
                if not lowest or h < lowest then lowest = h end
                if not highest or h > highest then highest = h end
            end
            -- settled: a sure figure for every level from its lowest to its highest
            local settled = r.lo ~= nil
            if settled then
                for l = r.lo, r.hi do
                    if not (by[l] and by[l].n >= SURE) then settled = false break end
                end
            end
            if settled then
                lowest, highest = by[r.lo].h, by[r.hi].h
                if lowest > highest then lowest, highest = highest, lowest end
            end
            local value = (settled and "" or "~") .. (lowest == highest and big(lowest) or (big(lowest) .. "-" .. big(highest)))
            rows[#rows + 1] = { kind = "stat", label = "Health", value = value, color = settled and T.text or T.textDim,
                tooltip = function(tip)
                    tip:SetText("Health", 1, 1, 1)
                    for _, l in ipairs(lv) do
                        local e = by[l]
                        tip:AddDoubleLine(l > 0 and ("Level " .. l) or "Level not known", big(e.h)
                            .. (e.exact and "" or ("   from " .. e.n .. (e.n == 1 and " kill" or " kills"))),
                            0.86, 0.86, 0.89, 1, 1, 1)
                    end
                    tip:AddLine(" ")
                    tip:AddLine(settled and "Settled: every level it comes in has a figure from three kills or more."
                        or "Still being worked out (~): it settles once every level it comes in has a figure from three kills.",
                        0.6, 0.6, 0.65, true)
                    tip:AddLine("The game hides a creature's health from addons: these are worked out from the damage it took to kill one.",
                        0.6, 0.6, 0.65, true)
                end }
        end
    end
    -- (What it does was a section of rows here, "Attacks and abilities":
    -- each is an icon in the strip now, 0.1.595.)
    if (r.l and next(r.l)) or (r.d and next(r.d)) or r.cn then
        -- (Out of kills, where those were counted: a corpse with nothing
        -- on it can't be opened, so corpses looted alone runs high. A kill
        -- you walked away from without looting counts as nothing found.)
        local looted = r.ln or 0
        local ln = math.max(looted, r.lk or 0)
        -- The coin it carries, on the heading itself (0.1.598: it was a row,
        -- "Coin per kill"): an average, so "~"; what it is, on hover.
        local base = r.cb or ln
        local coin = r.cn and base > 0 and coins(r.cn / base) or nil
        -- (Out of corpses, said as such, where there were more kills than
        -- that: kills in a group, whose corpses were mostly not yours to open.)
        local one, many = "kill", "kills"
        if looted > 0 and (r.k or 0) > ln then one, many = "corpse", "corpses" end
        head(rows, (ln > 0 and ("Loot   (" .. ln .. " " .. (ln == 1 and one or many) .. ")") or "Loot")
            .. (coin and ("     |cffeeeef2~" .. coin .. "|r") or ""), "micro_journal.tga")
        if coin then
            rows[#rows].tooltip = function(tip)
                tip:SetText("Coin", 1, 1, 1)
                tip:AddLine("About " .. coin .. " on each one (averaged over " .. base .. " " .. (base == 1 and one or many) .. ").", 0.86, 0.86, 0.89, true)
            end
        end
        -- (A row "Nothing on it  50%" stood here: not wanted, 0.1.605. Each
        -- item's rate is out of kills already, empty corpses included.)
        local ids = {}
        for item in pairs(r.l or {}) do ids[#ids + 1] = item end
        for item in pairs(r.d or {}) do if not (r.l and r.l[item]) then ids[#ids + 1] = item end end
        local function share(item) return r.l and r.l[item] or -1 end
        table.sort(ids, function(a, b) if share(a) ~= share(b) then return share(a) > share(b) end return a < b end)
        -- The list is kept short (0.1.591): a creature with a rank (elite,
        -- rare, boss) shows everything it has dropped; any other shows
        -- what drops at least one time in five, and quest items, with
        -- the rest folded under one row that opens.
        local COMMON = 0.20 -- (was 0.30)
        local whole = rankOf(r) ~= nil or lootOpen[id] == true
        local all, folded = ids, 0
        ids = {}
        for _, item in ipairs(all) do
            local n = r.l and r.l[item]
            local common = n and ln > 0 and n / ln >= COMMON
            local quest = false
            if not common and not whole and C_Item and C_Item.GetItemInfoInstant then
                local _, _, _, _, _, classID = call(C_Item.GetItemInfoInstant, item)
                quest = classID == 12
            end
            if whole or common or quest then ids[#ids + 1] = item else folded = folded + 1 end
        end
        for _, item in ipairs(ids) do
            local _, link = nil, nil
            if C_Item and C_Item.GetItemInfo then _, link = call(C_Item.GetItemInfo, item) end
            if not str(link) then wantItem(item, id) end
            local icon = C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, item)
            local n = r.l and r.l[item]
            local value, color
            if n and ln > 0 then
                value = string.format("%d%%", math.floor(n / ln * 100 + 0.5)) -- (the counts are in the tooltip)
            else
                value, color = "seen" .. (r.d and (r.d[item] or 0) > 1 and (" x" .. r.d[item]) or ""), T.textDim
            end
            -- (a quest item: marked as one, 0.1.594: "!" before the rate, in the quest gold)
            local isQuest = false
            if C_Item and C_Item.GetItemInfoInstant then
                local _, _, _, _, _, classID = call(C_Item.GetItemInfoInstant, item)
                isQuest = classID == 12
            end
            if isQuest then value = "|cfff2cc59Quest|r   " .. value end
            rows[#rows + 1] = { kind = "stat", label = str(link) and link or ("Item " .. item),
                labelColor = T.text, icon = icon, value = value, color = color,
                tooltip = function(tip)
                    pcall(tip.SetHyperlink, tip, "item:" .. item)
                    tip:AddLine(" ")
                    if isQuest then tip:AddLine("A quest item: it only drops while you are on its quest.", 0.95, 0.80, 0.35, true) end
                    if n and ln > 0 then
                        tip:AddLine(string.format("On %d of %d %s%s.", n, ln, many, r.shared and ", yours and other players'" or ""), 0.6, 0.6, 0.65, true)
                        if ln < 20 then tip:AddLine("Few " .. many .. " so far: the rate will settle.", 0.6, 0.6, 0.65, true) end
                    else
                        tip:AddLine("Seen before corpses were counted: no rate yet.", 0.6, 0.6, 0.65, true)
                    end
                    tip:Show()
                end }
        end
        if folded > 0 or (lootOpen[id] and rankOf(r) == nil and #all > 0) then
            local open = lootOpen[id] == true
            rows[#rows + 1] = { kind = "stat", value = "", labelColor = T.textDim,
                label = open and "Show only the common drops" or (folded .. (folded == 1 and " rarer drop" or " rarer drops") .. " (under 20%)"),
                folded = not open, indent = 14,
                onClick = function() lootOpen[id] = not open; changed(id) end }
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
        for _, z in ipairs(zs) do
            rows[#rows + 1] = { kind = "stat", label = z, labelColor = T.text, value = r.z[z] ~= true and "dungeon" or "", color = T.textDim }
        end
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
    local rk = rankOf(r)
    local bits = { r.n or "", r.t or "", r.f or "", rk and RANK[rk] or "",
                   r.ag == 1 and "hostile" or (r.ag == 0 and "neutral" or "") }
    for z, kind in pairs(r.z or {}) do
        bits[#bits + 1] = z
        if kind ~= true then bits[#bits + 1] = "dungeon" end
    end
    for name in pairs(r.c or {}) do bits[#bits + 1] = name end
    for name in pairs(r.db or {}) do bits[#bits + 1] = name end
    for _, tr in ipairs(B.Traits(id)) do bits[#bits + 1] = tr.title end
    for q in pairs(r.qs or {}) do bits[#bits + 1] = q end
    for f in pairs(r.rep or {}) do bits[#bits + 1] = f end
    for name, kind in pairs(r.cc or {}) do bits[#bits + 1] = name; bits[#bits + 1] = (CONTROL[kind] or kind) end
    for _, kind in pairs(r.dbt or {}) do bits[#bits + 1] = kind end
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
    -- (A dungeon has a heading of its own, apart from a zone of the same
    -- name: the Ruins of Lordaeron are both.)
    local DUNGEON = "  (dungeon)"
    local here, hereKind = placeNow()
    if here and hereKind then here = here .. DUNGEON end
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
                for z, kind in pairs(r.z) do
                    if kind ~= true then z = z .. DUNGEON end
                    zones[z] = zones[z] or {}; table.insert(zones[z], id)
                end
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
        local shownName = z
        if z:sub(-#DUNGEON) == DUNGEON then shownName = z:sub(1, -#DUNGEON - 1) .. "   |cff7d7d88dungeon|r" end
        table.insert(d, { kind = "header", text = shownName .. "   |cff7d7d88" .. #zones[z] .. "|r", collapsed = col,
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
                local rk = rankOf(r)
                return on and T.accent or (r.shared and not r.met and T.textDim)
                    or ((rk == "elite" or rk == "worldboss" or rk == "rareelite") and ELITE)
                    or (rk == "rare" and RARE) or T.text
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

B.ListData = listData -- (for dist/tests: the list as rows, with no window needed)

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
        elseif m.SetCreature and id > 0 then
            shown = pcall(m.SetCreature, m, id)
        end
        if shown then pcall(m.SetFacing, m, m.facing or 0.52) end
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

-- The strip of trait icons, for either window: f:Set(id) fills it and
-- says how many rows of icons it came to.
function B.MakeStrip(parent, perRow)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(perRow * 28, 24)
    f.btns = {}
    function f:Set(id)
        local list = id and B.Traits(id) or {}
        local shown = 0
        for i = 1, math.max(#list, #self.btns) do
            local b, d = self.btns[i], list[i]
            if d and i <= perRow * 2 then
                if not b then
                    b = CreateFrame("Button", nil, self)
                    b:SetSize(24, 24)
                    b.rim = b:CreateTexture(nil, "ARTWORK", nil, 0)
                    b.rim:SetTexture(MEDIA .. "circle.tga")
                    b.rim:SetAllPoints()
                    b.fill = b:CreateTexture(nil, "ARTWORK", nil, 1)
                    b.fill:SetTexture(MEDIA .. "circle.tga")
                    b.fill:SetPoint("TOPLEFT", 1.5, -1.5)
                    b.fill:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
                    b.fill:SetVertexColor(0.06, 0.06, 0.07, 1)
                    b.icon = b:CreateTexture(nil, "OVERLAY")
                    b.icon:SetSize(14, 14)
                    b.icon:SetPoint("CENTER")
                    -- (an ability's own picture: full colour, cut round)
                    b.mask = b:CreateMaskTexture()
                    b.mask:SetTexture(MEDIA .. "circle.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    b.mask:SetPoint("TOPLEFT", 2, -2)
                    b.mask:SetPoint("BOTTOMRIGHT", -2, 2)
                    b.pic = b:CreateTexture(nil, "OVERLAY")
                    b.pic:SetAllPoints(b.mask)
                    b.pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    b.pic:AddMaskTexture(b.mask)
                    b:SetPoint("TOPLEFT", self, "TOPLEFT", ((i - 1) % perRow) * 28, -math.floor((i - 1) / perRow) * 28)
                    b:SetScript("OnEnter", function(btn)
                        local d2 = btn.d
                        if not d2 then return end
                        btn.fill:SetVertexColor(0.13, 0.13, 0.15, 1)
                        -- (over the icon it belongs to, not beside the window: 0.1.595)
                        GameTooltip:SetOwner(btn, "ANCHOR_TOP", 0, 6)
                        if not (d2.sid and pcall(GameTooltip.SetSpellByID, GameTooltip, d2.sid)) then
                            GameTooltip:SetText(d2.title, d2.c[1], d2.c[2], d2.c[3])
                        elseif d2.text and d2.text ~= "" then
                            GameTooltip:AddLine(" ")
                        end
                        if d2.text and d2.text ~= "" then GameTooltip:AddLine(d2.text, 0.86, 0.86, 0.89, true) end
                        GameTooltip:Show()
                    end)
                    b:SetScript("OnLeave", function(btn) btn.fill:SetVertexColor(0.06, 0.06, 0.07, 1); GameTooltip:Hide() end)
                    self.btns[i] = b
                end
                b.d = d
                if d.raw then
                    b.pic:SetTexture(d.raw)
                    b.pic:Show(); b.icon:Hide()
                    b.rim:SetVertexColor(0.30, 0.30, 0.34, 1)
                else
                    b.icon:SetTexture(d.tex)
                    b.icon:SetVertexColor(d.c[1], d.c[2], d.c[3], 1)
                    b.icon:Show(); b.pic:Hide()
                    b.rim:SetVertexColor(d.c[1] * 0.55, d.c[2] * 0.55, d.c[3] * 0.55, 1)
                end
                b:Show()
                shown = i
            elseif b then
                b:Hide()
            end
        end
        return math.ceil(shown / perRow)
    end
    return f
end
local function showTraits(id)
    if win.strip then win.strip:Set(id) end
end

function B:Pick(id)
    picked = id
    if win then showModel(id) end
    self:Refresh()
end

function B:Refresh()
    if not win or not win:IsShown() then return end
    stale = false
    -- (One known by name that has since been given its number: follow it.)
    if picked and mergedTo[picked] then picked = mergedTo[picked] end
    local d, total, kills, found = listData()
    win.list:SetData(d)
    win.list.empty:SetText(found and "Nothing in the book matches that." or "Nothing met yet. Target or point at a creature.")
    win.shell:SetSubtitle(total == 0 and "Nothing met yet"
        or (found and string.format("%d of %d kinds of creature match", found, total))
        or string.format("%d kinds of creature known   ·   %d killed by you", total, kills))
    local r = picked and view(picked)
    if r then
        win.name:SetText(r.n or "")
        local rk = rankOf(r)
        local c = ((rk == "elite" or rk == "worldboss" or rk == "rareelite") and ELITE) or (rk == "rare" and RARE) or T.text
        win.name:SetTextColor(c[1], c[2], c[3])
        local bits = {}
        if levels(r) then bits[#bits + 1] = "Level " .. levels(r) end
        if rk and RANK[rk] then bits[#bits + 1] = RANK[rk] end
        if r.t then bits[#bits + 1] = r.t end
        -- (One met only inside a dungeon, where the game hides what a
        -- creature is: said, so a bare page explains itself.)
        if not r.t and not r.uc then
            bits[#bits + 1] = picked < 0 and "known by name: loot one to learn more" or "met in a dungeon"
        end
        win.sub:SetText(table.concat(bits, "   ·   "))
        win.detail:SetData(B.Rows({}, picked, true))
        showTraits(picked)
    else
        win.name:SetText("")
        win.sub:SetText("")
        win.detail:SetData({})
        showTraits(nil)
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
    m.facing = 0.52
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
    win.strip = B.MakeStrip(top, 7)
    win.strip:SetPoint("TOPLEFT", win.sub, "BOTTOMLEFT", 0, -10)
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
-- "/men bestiary hp 346": the health you can read on your target's frame
-- (the game shows it to you and hides it from addons), set down as the
-- exact figure for that creature at that level. It replaces the estimate.
local function setHealth(n)
    local id = npcID("target")
    local lvl = call(UnitLevel, "target")
    if not (id and plain(lvl) and lvl > 0) then return ns:Print("Target the creature first (one you can attack).") end
    if not (n and n > 0 and n < 1e9) then return ns:Print("Say its full health as a number:  /men bestiary hp 346") end
    pcall(observe, "target")
    local r = record(id, true)
    r.hp = r.hp or {}
    r.hp[lvl] = math.floor(n)
    changed(id)
    ns:Print((r.n or "It") .. ", level " .. lvl .. ": health set to " .. math.floor(n) .. ".")
end
ns.commands.bestiary = function(rest)
    if type(rest) == "string" and rest:find("^%s*export") then return export() end
    local hp = type(rest) == "string" and rest:match("^%s*hp%s*(%d*)")
    if hp then return setHealth(tonumber(hp)) end
    B:Open()
end

function B:OnInit(db)
    self.db = db
    db.collapsed = db.collapsed or {}
    -- A fresh book (0.1.582, agreed): what was kept before kills were
    -- counted properly had loot without kills and tallies from three
    -- different ways of counting. Everything is met again from here.
    -- (0.1.588: this read "~= 2", so once the number went past 2 it emptied
    -- the book at every reload: loot, speech and health all gone each time.)
    if MinimalUIDB and (MinimalUIDB.bestiaryRev or 0) < 2 then
        MinimalUIDB.bestiary, MinimalUIDB.bestiaryOut, MinimalUIDB.bestiarySent = nil, nil, nil
        MinimalUIDB.hpdiag, MinimalUIDB.castdiag, MinimalUIDB.lookdiag = nil, nil, nil
        MinimalUIDB.bestiaryRev = 2
        nameIndex = nil
    end
    if MinimalUIDB and MinimalUIDB.bestiaryRev == 2 then -- (0.1.585: the first health estimates were far off)
        for _, r in pairs(MinimalUIDB.bestiary or {}) do r.he, r.hn, r.hs = nil, nil, nil end
        MinimalUIDB.bestiaryRev = 3
    end
    if MinimalUIDB and MinimalUIDB.bestiaryRev == 3 then MinimalUIDB.bestiaryRev = 4 end
    if MinimalUIDB and MinimalUIDB.bestiaryRev == 4 then -- (0.1.590: the samples are read differently)
        for _, r in pairs(MinimalUIDB.bestiary or {}) do
            r.he, r.hn = nil, nil
            for L in pairs(r.hs or {}) do settle(r, L) end
        end
        MinimalUIDB.bestiaryRev = 5
    end
    if MinimalUIDB and MinimalUIDB.bestiaryRev == 5 then -- (0.1.608: "his"/"her" lines made one)
        for _, r in pairs(MinimalUIDB.bestiary or {}) do
            if type(r.q) == "table" then
                local have = {}
                for i = #r.q, 1, -1 do
                    local line = r.q[i]
                    if str(line.t) and not line.u then line.t = neutral(line.t) end
                    if have[line.t] then table.remove(r.q, i) else have[line.t] = true end
                end
            end
        end
        MinimalUIDB.bestiaryRev = 6
    end
    if MinimalUIDB and MinimalUIDB.bestiaryRev == 6 then
        -- (0.1.622: the kills inside instances that went uncounted, their
        -- creatures having no name here, are read back out of the record of
        -- play, where there is one: "/men record".)
        for _, list in pairs(type(MinimalUIDB.journal) == "table" and MinimalUIDB.journal or {}) do
            local inside, zone, mine = false, nil, nil
            for _, line in ipairs(type(list) == "table" and list or {}) do
                local what, rest = nil, nil
                if type(line) == "string" then what, rest = line:match("^[%d%.]+|([%u_]+)|(.*)$") end
                if what == "S" then
                    inside = false
                    mine = tonumber((select(5, strsplit("|", rest))))
                elseif what == "WORLD" then
                    local z, _, _, _, _, kind = strsplit("|", rest)
                    zone = z ~= "" and z or nil
                    inside = kind ~= nil and kind ~= "" and kind ~= "none"
                elseif what == "COMBAT_XP_GAIN" and inside then
                    local name = rest:match("^(.-) dies, you gain")
                    local id = name and idByName(name)
                    local p
                    if name and not id then id, p = nameOnly(name) elseif id and id < 0 then p = record(id) end
                    if p then
                        p.k = (p.k or 0) + 1
                        local gained = tonumber(rest:match("you gain (%d+) experience"))
                        if gained and gained > 0 then p.xp, p.xl = gained, mine end
                        addZone(p, zone, "party")
                    end
                end
            end
        end
        MinimalUIDB.bestiaryRev = 7
    end
    if MinimalUIDB and MinimalUIDB.bestiaryRev == 7 then
        -- (0.1.624: the first reading found none of the Wailing Caverns'
        -- kills, the record of play having been cut short above the line
        -- that says "inside an instance", and the creatures, named at login,
        -- were filed under where you stood. Read again: for every creature
        -- named from its number and never read as one, its experience lines
        -- wherever they are, and the zone they were in.)
        local want, tally = {}, {}
        for _, r in pairs(MinimalUIDB.bestiary or {}) do
            if r.n and not r.t and not r.lo then want[r.n] = r; r.z = nil end
        end
        for _, list in pairs(type(MinimalUIDB.journal) == "table" and MinimalUIDB.journal or {}) do
            local zone, mine, first, early = nil, nil, true, {}
            for _, line in ipairs(type(list) == "table" and list or {}) do
                local what, rest = nil, nil
                if type(line) == "string" then what, rest = line:match("^[%d%.]+|([%u_]+)|(.*)$") end
                if what == "S" then
                    mine = tonumber((select(5, strsplit("|", rest))))
                elseif what == "WORLD" or what == "ZONE" then
                    local z, _, _, _, _, kind = strsplit("|", rest)
                    if first then
                        -- (Lines above the first place named: the same
                        -- instance, if this is one being come back into.)
                        first = false
                        if what == "WORLD" and z ~= "" and kind and kind ~= "" and kind ~= "none" then
                            for name in pairs(early) do addZone(want[name], z) end
                        end
                    end
                    zone = z ~= "" and z or nil
                elseif what == "COMBAT_XP_GAIN" then
                    local name = rest:match("^(.-) dies, you gain")
                    local r = name and want[name]
                    if r then
                        tally[name] = (tally[name] or 0) + 1
                        local gained = tonumber(rest:match("you gain (%d+) experience"))
                        if gained and gained > 0 and mine then r.xp, r.xl = gained, mine end
                        if zone then addZone(r, zone) elseif first then early[name] = true end
                    end
                end
            end
        end
        for name, n in pairs(tally) do
            local r = want[name]
            if n > (r.k or 0) then r.k = n end
            if n > (r.lk or 0) then r.lk = n end
        end
        MinimalUIDB.bestiaryRev = 8
    end
    if MinimalUIDB and MinimalUIDB.bestiaryRev == 8 then
        -- (0.1.645, see "In a dungeon". Three things put right in what is
        -- already written down.)
        local all = MinimalUIDB.bestiary or {}
        MinimalUIDB.bestiary = all
        -- 1. Which zone names are instances, and which were only the place
        --    you had just come from. The record of play has, as you come
        --    into an instance, the old zone's name on the line for coming in
        --    and the instance's own a moment later: the 0.1.622 reading
        --    went by the first, and filed a dungeon under the city at its door.
        local stale, inst = {}, {}
        for _, list in pairs(type(MinimalUIDB.journal) == "table" and MinimalUIDB.journal or {}) do
            local was, wasAt
            for _, line in ipairs(type(list) == "table" and list or {}) do
                local at, what, rest
                if type(line) == "string" then at, what, rest = line:match("^([%d%.]+)|([%u_]+)|(.*)$") end
                if what == "WORLD" or what == "ZONE" then
                    local z, _, _, _, _, kind = strsplit("|", rest)
                    local inside = kind ~= nil and kind ~= "" and kind ~= "none" and z ~= nil and z ~= ""
                    at = tonumber(at) or 0
                    if inside then inst[z] = kind end
                    if what == "WORLD" then
                        was, wasAt = inside and z or nil, at
                    else
                        if was and inside and z ~= was and at >= wasAt and at - wasAt <= 5 then stale[was] = z end
                        was = nil
                    end
                elseif what == "S" then
                    was = nil
                end
            end
        end
        -- (A zone some creature was read in the ordinary way is a zone, not an instance.)
        local plainZone = {}
        for _, r in pairs(all) do
            if r.uc or r.t then
                for z, kind in pairs(r.z or {}) do if kind == true then plainZone[z] = true end end
            end
        end
        local function dungeonZones(r)
            if not r.z then return end
            local z2 = {}
            for z in pairs(r.z) do
                local to = stale[z] or z
                z2[to] = (inst[to] or not plainZone[to]) and (inst[to] or "party") or true
            end
            r.z = z2
        end
        -- 2. Creatures never read as creatures: named from a corpse, in a
        --    dungeon. Their zones as above; and an item's rate out of the
        --    corpses you opened, not out of every kill the group made.
        for _, r in pairs(all) do
            if r.n and not r.uc and not r.t then
                dungeonZones(r)
                if (r.lk or 0) > (r.ln or 0) then r.lk = r.ln end
            end
        end
        -- 3. What was known by name and kept out of the book comes into it.
        nameIndex = nil
        for name, pd in pairs(type(MinimalUIDB.bestiaryPend) == "table" and MinimalUIDB.bestiaryPend or {}) do
            if str(name) and type(pd) == "table" then
                local id = idByName(name)
                local r = id and record(id)
                if not r then id, r = nameOnly(name) end
                if r then
                    dungeonZones(pd)
                    fold(r, pd)
                end
            end
        end
        MinimalUIDB.bestiaryPend = nil
        nameIndex = nil
        MinimalUIDB.bestiaryRev = 9
    end
    -- (Creatures with a number and no name: asked now, and once more for
    -- those the game had to fetch.)
    C_Timer.After(6, function()
        if pcall(nameTheNameless) then C_Timer.After(8, function() pcall(nameTheNameless) end) end
    end)
    B.OnChange(function(id)
        if id then hay[id] = nil end
        if win and win:IsShown() then stale = true end
    end)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "LOOT_OPENED",
                         "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "CHAT_MSG_COMBAT_FACTION_CHANGE", "LOSS_OF_CONTROL_ADDED", "CHAT_MSG_COMBAT_XP_GAIN", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
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
        if e == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(3, function() if not InCombatLockdown() then pcall(fightStart) end end)
            -- (Out of a dungeon: the creatures looted in there can be asked
            -- their names now; inside, the answer comes back hidden. 0.1.626)
            C_Timer.After(6, function()
                if IsInInstance and IsInInstance() == true then return end
                if pcall(nameTheNameless) then C_Timer.After(8, function() pcall(nameTheNameless) end) end
            end)
            return
        end
        if e == "CHAT_MSG_COMBAT_XP_GAIN" then pcall(noteXP, a1) return end
        if e == "LOSS_OF_CONTROL_ADDED" then pcall(noteControl) return end
        if e == "CHAT_MSG_COMBAT_FACTION_CHANGE" then pcall(noteRep, a1) return end
        if e == "PLAYER_TARGET_CHANGED" then pcall(noteTarget); pcall(noteCorpse, "target") end
        if e == "PLAYER_REGEN_ENABLED" then
            C_Timer.After(0.3, function() pcall(noteDeath, "target") end)
            C_Timer.After(0.6, function()
                local kills = {}
                for i, k in ipairs(fightKills) do kills[i] = k end
                wipe(fightKills)
                pcall(fightEnd, kills, 1)
            end)
        end
        if e == "PLAYER_TARGET_CHANGED" or e == "PLAYER_REGEN_ENABLED" then pcall(observe, "target")
            -- (noteLook is not run: the game answered 0 for every creature
            -- asked, 39 of 39, so its forms can't be learned this way.)
        elseif e == "UPDATE_MOUSEOVER_UNIT" then pcall(observe, "mouseover"); pcall(noteCorpse, "mouseover")
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
