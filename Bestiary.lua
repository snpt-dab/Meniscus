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
--     hp = { [level] = health }         its full health at that level,
--     c  = { [spell name] = spell id or true }   what it casts (16),
--     hit = { [attack name] = hardest hit on you } (from death recaps),
--     q  = { { t = what it said, k = "yell" / "emote" / nil (said),
--              l = language, u = true when you did not understand it } } (12),
--     k  = kills,           kd = times it killed you,
--     d  = { [itemID] = times }         quest items and green or better (8)
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

-- Something was learned: whoever shows it redraws (soon, not now).
local listeners = {}
function B.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed(id)
    for _, fn in ipairs(listeners) do pcall(fn, id) end
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
    if okLvl and plain(hp) and hp > 0 then
        r.hp = r.hp or {}
        if (r.hp[lvl] or 0) < hp then r.hp[lvl] = hp; new = true end
        seen[guid] = 2
    else
        seen[guid] = 1
    end
    if new then changed(id) end
end

local function noteCast(unit, spellID)
    if unit ~= "target" and not (type(unit) == "string" and unit:find("^nameplate")) then return end
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
local function noteDeath()
    if not isTrue(call(UnitIsDead, "target")) then return end
    local id, guid = npcID("target")
    if not id or seenDead[guid] then return end
    if isTrue(call(UnitIsTapDenied, "target")) then return end
    if nDead > 300 then wipe(seenDead); nDead = 0 end
    seenDead[guid] = true; nDead = nDead + 1
    local r = record(id, true)
    r.k = (r.k or 0) + 1
    changed(id)
end

local function noteLoot()
    if not (GetNumLootItems and GetLootSourceInfo and GetLootSlotLink and GetLootSlotInfo) then return end
    local n = call(GetNumLootItems)
    if not plain(n) then return end
    for slot = 1, n do
        local link = call(GetLootSlotLink, slot)
        local _, _, _, _, quality, _, isQuest = call(GetLootSlotInfo, slot)
        local guid = call(GetLootSourceInfo, slot)
        local id = npcOf(guid)
        local item = str(link) and tonumber(link:match("item:(%d+)"))
        if id and item and (isTrue(isQuest) or (plain(quality) and quality >= 2)) then
            local key = guid .. ":" .. item
            if not seenLoot[key] then
                if nLoot > 300 then wipe(seenLoot); nLoot = 0 end
                seenLoot[key] = true; nLoot = nLoot + 1
                local r = record(id, true)
                r.d = r.d or {}
                if r.d[item] or count(r.d) < 8 then r.d[item] = (r.d[item] or 0) + 1; changed(id) end
            end
        end
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
local nameIndex
local function idByName(name)
    local all = MinimalUIDB and MinimalUIDB.bestiary
    if not all then return end
    if not nameIndex then
        nameIndex = {}
        for id, r in pairs(all) do if r.n then nameIndex[r.n] = id end end
    end
    return nameIndex[name]
end
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
function B.Rows(rows, id, full)
    local r = id and record(id)
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
    stat(rows, "Kills", string.format("%d", r.k or 0))
    if r.kd then stat(rows, "Killed you", string.format("%d", r.kd), RED) end
    -- health, by level
    if r.hp and next(r.hp) then
        local lv = {}
        for l in pairs(r.hp) do lv[#lv + 1] = l end
        table.sort(lv)
        for _, l in ipairs(lv) do stat(rows, "Health at " .. l, BreakUpLargeNumbers and BreakUpLargeNumbers(r.hp[l]) or tostring(r.hp[l])) end
    else
        rows[#rows + 1] = { kind = "stat", label = "Health", value = "not learned yet", color = T.textDim }
    end
    -- what it does
    local names = {}
    for name in pairs(r.c or {}) do names[name] = true end
    for name in pairs(r.hit or {}) do names[name] = true end
    if next(names) then
        head(rows, "Attacks", "micro_spell.tga")
        local list = {}
        for name in pairs(names) do list[#list + 1] = name end
        table.sort(list, function(a, b) if (a == "Melee") ~= (b == "Melee") then return a == "Melee" end return a < b end)
        for _, name in ipairs(list) do
            local sid = r.c and type(r.c[name]) == "number" and r.c[name] or nil
            local icon = name == "Melee" and MELEE_ICON
                or (sid and C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, sid)) or nil
            local hit = r.hit and r.hit[name]
            rows[#rows + 1] = { kind = "stat", label = name, labelColor = T.text, icon = str(icon) and icon or (plain(icon) and icon) or nil,
                value = hit and ("up to " .. hit) or "", color = T.textDim,
                tooltip = sid and function(tip) pcall(tip.SetSpellByID, tip, sid) end or nil }
        end
    end
    if r.d and next(r.d) then
        head(rows, "Drops", "micro_journal.tga")
        local ids = {}
        for item in pairs(r.d) do ids[#ids + 1] = item end
        table.sort(ids)
        for _, item in ipairs(ids) do
            local _, link = nil, nil
            if C_Item and C_Item.GetItemInfo then _, link = call(C_Item.GetItemInfo, item) end
            local icon = C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, item)
            rows[#rows + 1] = { kind = "stat", label = str(link) and link or ("Item " .. item),
                labelColor = T.text, icon = icon, value = r.d[item] > 1 and ("x" .. r.d[item]) or "",
                tooltip = function(tip) pcall(tip.SetHyperlink, tip, "item:" .. item) end }
        end
    end
    if r.q and #r.q > 0 then
        head(rows, "Says", "micro_chat.tga")
        local me = call(UnitName, "player")
        for _, line in ipairs(r.q) do
            local said = str(me) and line.t:gsub("%$N", me) or line.t
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
local function haystack(id, r)
    local h = hay[id]
    if h then return h end
    local bits = { r.n or "", r.t or "", r.f or "", r.cl and RANK[r.cl] or "",
                   r.ag == 1 and "hostile" or (r.ag == 0 and "neutral" or "") }
    for z in pairs(r.z or {}) do bits[#bits + 1] = z end
    for name in pairs(r.c or {}) do bits[#bits + 1] = name end
    for name in pairs(r.hit or {}) do bits[#bits + 1] = name end
    for _, line in ipairs(r.q or {}) do bits[#bits + 1] = line.t end
    for item in pairs(r.d or {}) do
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
    for id, r in pairs(all) do
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
            table.sort(ids, function(a, b)
                local ra, rb = all[a], all[b]
                if (ra.lo or 0) ~= (rb.lo or 0) then return (ra.lo or 0) < (rb.lo or 0) end
                return ra.n < rb.n
            end)
            for _, id in ipairs(ids) do
                local r = all[id]
                local c = id == picked and T.accent
                    or ((r.cl == "elite" or r.cl == "worldboss" or r.cl == "rareelite") and ELITE)
                    or (r.cl == "rare" and RARE) or T.text
                table.insert(d, { kind = "stat", label = r.n, labelColor = c, indent = 10,
                    value = levels(r) or "", color = T.textDim,
                    onClick = function() B:Pick(id) end })
            end
        end
    end
    return d, total, kills, words and found or nil
end

local function showModel(id)
    local m = win.model
    local shown = false
    if id then
        pcall(m.ClearModel, m)
        if npcID("target") == id then
            shown = pcall(m.SetUnit, m, "target")
        elseif m.SetCreature then
            shown = pcall(m.SetCreature, m, id)
        end
        if shown then pcall(m.SetFacing, m, m.facing or 0.4) end
    end
    m:SetShown(shown)
    win.modelNote:SetShown(not shown)
    win.modelNote:SetText(id and "No picture of it: target one with this open" or "Pick a creature")
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
        or string.format("%d kinds of creature met   ·   %d killed", total, kills))
    local r = picked and record(picked)
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
    win.name:SetPoint("TOPLEFT", top, "TOPLEFT", 162, -22)
    win.name:SetPoint("RIGHT", top, "RIGHT", -12, 0)
    win.name:SetWordWrap(true)
    win.sub = words(11, false, T.textDim)
    win.sub:SetPoint("TOPLEFT", win.name, "BOTTOMLEFT", 0, -6)
    win.sub:SetPoint("RIGHT", top, "RIGHT", -12, 0)
    win.sub:SetWordWrap(true)

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
        if id and record(id) then picked = id end
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
ns.commands.bestiary = function() B:Open() end

function B:OnInit(db)
    self.db = db
    db.collapsed = db.collapsed or {}
    B.OnChange(function(id)
        if id then hay[id] = nil end
        if win and win:IsShown() then stale = true end
    end)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "LOOT_OPENED",
                         "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
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
        if e == "PLAYER_TARGET_CHANGED" or e == "PLAYER_REGEN_ENABLED" then pcall(observe, "target")
        elseif e == "UPDATE_MOUSEOVER_UNIT" then pcall(observe, "mouseover")
        elseif e == "NAME_PLATE_UNIT_ADDED" then if type(a1) == "string" then pcall(observe, a1) end
        elseif e == "LOOT_OPENED" then pcall(noteLoot)
        else pcall(noteCast, a1, a3) end
    end)
    local hp = CreateFrame("Frame")
    pcall(hp.RegisterUnitEvent, hp, "UNIT_HEALTH", "target")
    hp:SetScript("OnEvent", function() pcall(noteDeath) end)
end
