local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Inspect: Meniscus's inspect window, the character window's look for
-- someone else. Shared header (their 3D head, class-colored name, "Level 60
-- Race Class · Guild", item level chip) and gear tiles around a
-- drag-to-rotate model.
-- Blizzard's inspect frame stays open but invisible: closing it clears the
-- inspect data. Closing ours closes it.
--
-- 0.1.530: it opens for anything you have targeted ("Inspect" beside the
-- target frame, or /men inspect), with a column of what can be known:
--   a player in reach: gear as before, attributes (the game's own numbers
--     if it gives them, else gear's bonuses, on top of the class and race
--     base where that is known), guild rank, buffs;
--   a player out of reach: the model and the same without gear;
--   a creature or pet: its kind, family, rank, who it is after, what is on
--     it, and what you have seen of it (below).
--
-- What you have seen of a creature: one small record for each kind of
-- creature (not each one), written only when something happens:
--   MinimalUIDB.bestiary[npcID] = { n = name, k = kills, lo, hi = levels
--     seen, c = { [spell name] = true } (casts with a cast bar, 12 at most),
--     d = { [itemID] = times } (quest items and green or better, 8) }
-- A kill is one that died while you had it targeted and it was yours.
-- There is no combat log for addons here, so what it does without a cast
-- bar is not known.

local I = ns:NewModule("Inspect", { enabled = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local PAGE_TOP = (ns.SHELL_H or 92) + 16
local TILE, GAP = 38, 6
local GEAR_W = 380
local W = GEAR_W + 20
local INFO_W = 250 -- (the column of details to the right of the gear)
local H = PAGE_TOP + 8 * (TILE + GAP) + TILE + 30
local FILL = { 0.06, 0.06, 0.07, 0.97 }

local LEFT_SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" }
local RIGHT_SLOTS = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" }
local WEAPON_SLOTS = { "MainHand", "SecondaryHand", "Ranged" }
local NO_ILVL = { Shirt = true, Tabard = true }

local function secret(v) return issecretvalue and issecretvalue(v) end
local call = ns.Call
local function plain(v) return type(v) == "number" and not secret(v) end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local function itemLevel(link)
    if not link or secret(link) then return end
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
    local lvl = call(f, link)
    if plain(lvl) and lvl > 0 then return lvl end
    if C_Item and C_Item.GetItemInfo then
        local l = select(4, call(C_Item.GetItemInfo, link))
        if plain(l) and l > 0 then return l end
    end
end

local function qualityColor(q)
    return plain(q) and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
end

-- ── What you have seen of a creature ─────────────────────────────────────
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
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end
local function isTrue(v) return not secret(v) and v == true end
local seenDead, seenLoot, nDead, nLoot = {}, {}, 0, 0
local function noteTarget()
    local id = npcID("target")
    if not id or not isTrue(call(UnitCanAttack, "player", "target")) then return end
    local r = record(id, true)
    local name = call(UnitName, "target")
    if type(name) == "string" and not secret(name) then r.n = name end
    local lvl = call(UnitLevel, "target")
    if plain(lvl) and lvl > 0 then
        if not r.lo or lvl < r.lo then r.lo = lvl end
        if not r.hi or lvl > r.hi then r.hi = lvl end
    end
end
local function noteCast(spellID)
    local id = npcID("target")
    if not id then return end
    local name
    if plain(spellID) and C_Spell and C_Spell.GetSpellName then name = call(C_Spell.GetSpellName, spellID) end
    if type(name) ~= "string" or secret(name) then
        name = call(UnitCastingInfo, "target")
        if type(name) ~= "string" or secret(name) then name = call(UnitChannelInfo, "target") end
    end
    if type(name) ~= "string" or secret(name) or name == "" then return end
    local r = record(id, true)
    r.c = r.c or {}
    if not r.c[name] and count(r.c) < 12 then r.c[name] = true; return true end
end
local function noteDeath()
    if not isTrue(call(UnitIsDead, "target")) then return end
    local id, guid = npcID("target")
    if not id or seenDead[guid] then return end
    if isTrue(call(UnitIsTapDenied, "target")) then return end
    if nDead > 300 then wipe(seenDead); nDead = 0 end
    seenDead[guid] = true; nDead = nDead + 1
    local r = record(id, true)
    r.k = (r.k or 0) + 1
    return true
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
        local item = type(link) == "string" and not secret(link) and tonumber(link:match("item:(%d+)"))
        if id and item and (isTrue(isQuest) or (plain(quality) and quality >= 2)) then
            local key = guid .. ":" .. item
            if not seenLoot[key] then
                if nLoot > 300 then wipe(seenLoot); nLoot = 0 end
                seenLoot[key] = true; nLoot = nLoot + 1
                local r = record(id, true)
                r.d = r.d or {}
                if r.d[item] or count(r.d) < 8 then r.d[item] = (r.d[item] or 0) + 1 end
            end
        end
    end
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, tiles = nil, {}
local closing = false

-- ── The details card ─────────────────────────────────────────────────────
-- The character window's own card (Character.lua: attribute tiles across
-- the top, resistances, and "Details" or "Graph" under them), filled for
-- whoever is shown. The rows here are what goes under "Details".
local STAT_KEYS = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
                    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" }
local RANK = { elite = "Elite", rareelite = "Rare elite", rare = "Rare", worldboss = "Boss", trivial = "Trivial", minus = "Minor" }
local RED = { 0.92, 0.38, 0.35, 1 }
local DIM = T.textDim or { 0.6, 0.6, 0.65, 1 }
local gearSum = {}
-- What a class and race have at a level before gear, where it is known:
-- so far only what the game has told this account about its own characters
-- (MinimalUIDB.baseStats, Probe.lua). A table for everyone is to come once
-- the published classic one has been checked against those.
local function baseFor(unit, i)
    local _, class = UnitClass(unit)
    local _, race = UnitRace(unit)
    local lvl = UnitLevel(unit)
    if type(class) ~= "string" or secret(class) or type(race) ~= "string" or secret(race) or not plain(lvl) then return end
    local t = MinimalUIDB and MinimalUIDB.baseStats and MinimalUIDB.baseStats[class .. "|" .. race]
    local line = t and t[lvl]
    if type(line) ~= "string" then return end
    local n = 0
    for v in line:gmatch("[^,]+") do
        n = n + 1
        if n == i then return tonumber(v) end
    end
end
local function head(rows, title, glyph) rows[#rows + 1] = { kind = "header", text = title, glyph = glyph } end
local function stat(rows, label, value, color, tooltip, icon)
    if not secret(value) and value == nil then return end -- (a hidden value is shown as it is)
    rows[#rows + 1] = { kind = "stat", label = label, value = value, color = color, tooltip = tooltip, icon = icon }
end
local function note(rows, str) rows[#rows + 1] = { kind = "stat", label = str, value = "" } end
local function auras(rows, unit, filter, max)
    local U = C_UnitAuras
    if not (U and U.GetAuraDataByIndex) then return 0 end
    local shown = 0
    for i = 1, max do
        local ok, a = pcall(U.GetAuraDataByIndex, unit, i, filter)
        if not ok or type(a) ~= "table" then break end
        local id, icon, count = a.auraInstanceID, a.icon, a.applications
        rows[#rows + 1] = { kind = "stat", label = a.name, labelColor = filter == "HARMFUL" and RED or T.text,
            icon = (icon ~= nil and not secret(icon)) and icon or nil,
            value = (plain(count) and count > 1) and ("x" .. count) or "",
            tooltip = function(tip)
                if tip.SetUnitAuraByAuraInstanceID then pcall(tip.SetUnitAuraByAuraInstanceID, tip, unit, id) end
            end }
        shown = shown + 1
    end
    return shown
end
local function fillPlayer(unit)
    local rows, base, gear, res = {}, nil, nil, nil
    local read = 0
    if I.mode == "gear" then
        wipe(gearSum)
        for _, b in pairs(tiles) do
            local link = call(GetInventoryItemLink, unit, b.slot)
            local st = link and not secret(link) and ns.ItemStats and ns.ItemStats(link)
            if st then
                read = read + 1
                for k, v in pairs(st) do
                    if type(v) == "number" and not secret(v) then gearSum[k] = (gearSum[k] or 0) + v end
                end
            end
        end
        if read > 0 then
            gear = {}
            for i = 1, 5 do gear[i] = gearSum[STAT_KEYS[i]] or 0 end
            -- (Resistances as their gear has them: what a race or a buff
            -- adds is not counted. 2 fire, 3 nature, 4 frost, 5 shadow, 6 arcane.)
            res = {}
            for school = 2, 6 do res[school] = gearSum["RESISTANCE" .. school .. "_NAME"] or 0 end
        end
    end
    for i = 1, 5 do
        local b = baseFor(unit, i)
        if b then base = base or {}; base[i] = b end
    end
    head(rows, "About", "micro_character.tga")
    local _, real = call(UnitStat, unit, 1)
    if not (plain(real) and real > 0) then
        if I.mode ~= "gear" then note(rows, "Out of reach: their gear is not shown")
        elseif read == 0 then note(rows, "Their gear has not arrived yet")
        elseif base then note(rows, "Attributes: class and race, plus gear")
        else note(rows, "Attributes: from their gear alone") end
    end
    local armor = gear and gearSum.RESISTANCE0_NAME
    if armor and armor > 0 then stat(rows, "Armor from gear", string.format("%d", armor)) end
    local _, rank = call(GetGuildInfo, unit)
    if type(rank) == "string" and not secret(rank) and rank ~= "" then stat(rows, "Guild rank", rank) end
    local _, faction = call(UnitFactionGroup, unit)
    if type(faction) == "string" and not secret(faction) and faction ~= "" then stat(rows, "Faction", faction) end
    if isTrue(call(UnitIsPVP, unit)) then stat(rows, "Player combat", "Flagged", RED) end
    stat(rows, "Targeting", (call(UnitName, unit .. "target")))
    head(rows, "Buffs", "micro_buff.tga")
    if auras(rows, unit, "HELPFUL", 24) == 0 then note(rows, InCombatLockdown() and "Not readable in a fight" or "None") end
    return rows, base, gear, res
end
local function fillCreature(unit)
    local rows = {}
    head(rows, "About", "micro_character.tga")
    local kind = call(UnitCreatureType, unit)
    if kind and (secret(kind) or kind ~= "") then stat(rows, "Kind", kind) end
    local family = call(UnitCreatureFamily, unit)
    if family and (secret(family) or family ~= "") then stat(rows, "Family", family) end
    local cls = call(UnitClassification, unit)
    if type(cls) == "string" and not secret(cls) and RANK[cls] then stat(rows, "Rank", RANK[cls], T.accent) end
    if isTrue(call(UnitIsTapDenied, unit)) then stat(rows, "Claimed", "By someone else", DIM) end
    if isTrue(call(UnitIsDead, unit)) then stat(rows, "State", "Dead", DIM) end
    stat(rows, "Targeting", (call(UnitName, unit .. "target")))
    head(rows, "On it", "micro_buff.tga")
    if auras(rows, unit, "HELPFUL", 16) + auras(rows, unit, "HARMFUL", 16) == 0 then
        note(rows, InCombatLockdown() and "Not readable in a fight" or "Nothing")
    end
    local id = npcID(unit)
    local r = id and record(id)
    head(rows, "What you have seen", "micro_journal.tga")
    if not r then
        note(rows, id and "Nothing yet: it fills in as you fight it" or "Nothing is kept for this one")
        return rows
    end
    stat(rows, "Kills", string.format("%d", r.k or 0))
    if r.lo then stat(rows, "Levels", r.lo == r.hi and tostring(r.lo) or (r.lo .. " to " .. r.hi)) end
    if r.c and next(r.c) then
        local names = {}
        for name in pairs(r.c) do names[#names + 1] = name end
        table.sort(names)
        for n, name in ipairs(names) do stat(rows, n == 1 and "Casts" or "", name) end
    end
    if r.d and next(r.d) then
        local ids = {}
        for item in pairs(r.d) do ids[#ids + 1] = item end
        table.sort(ids)
        for _, item in ipairs(ids) do
            local _, link = nil, nil
            if C_Item and C_Item.GetItemInfo then _, link = call(C_Item.GetItemInfo, item) end
            local icon = C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, item)
            rows[#rows + 1] = { kind = "stat", label = type(link) == "string" and link or ("Item " .. item),
                labelColor = T.text, icon = icon, value = r.d[item] > 1 and ("x" .. r.d[item]) or "",
                tooltip = function(tip) pcall(tip.SetHyperlink, tip, "item:" .. item) end }
        end
    end
    return rows
end
local function fillInfo(unit)
    local Cm = ns.modules.Character
    if not (win and win.card and Cm and Cm.FillOtherCard) then return end
    local rows, base, gear, res
    if isTrue(call(UnitIsPlayer, unit)) then rows, base, gear, res = fillPlayer(unit) else rows = fillCreature(unit) end
    Cm.FillOtherCard(win.card, unit, base, gear, rows, res)
end

local function makeTile(parent, slotName)
    local id, empty = call(GetInventorySlotInfo, slotName .. "Slot")
    if not id then return end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TILE, TILE)
    b.slot, b.empty, b.slotName = id, empty, slotName
    b.ring = ns.RoundedRect(b, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(b, -7, 1, 6, unpack(FILL))
    local mask = b:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2)
    mask:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(mask)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:AddMaskTexture(mask)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(mask)
    hl:SetColorTexture(1, 1, 1, 0.12)
    hl:AddMaskTexture(mask)
    b.ilvl = b:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.ilvl, 9, "OUTLINE", true)
    b.ilvl:SetPoint("TOPRIGHT", -3, -3)
    b:SetScript("OnClick", function(self)
        local link = call(GetInventoryItemLink, I.unit, self.slot)
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    b:SetScript("OnEnter", function(self)
        ns.TipAnchor(self)
        local has = I.unit and GameTooltip:SetInventoryItem(I.unit, self.slot)
        if not has then GameTooltip:SetText(_G[self.slotName:upper() .. "SLOT"] or self.slotName) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tiles[slotName] = b
    return b
end

local function makeModel(page, x1, y1, x2, y2)
    local cx = (x1 + x2) / 2
    local spot = page:CreateTexture(nil, "BACKGROUND", nil, 1)
    spot:SetTexture(MEDIA .. "spot.tga")
    spot:SetSize(300, 300)
    spot:SetPoint("CENTER", page, "TOPLEFT", cx, (y1 + y2) / 2 - 2)
    local floor = page:CreateTexture(nil, "BACKGROUND", nil, 2)
    floor:SetTexture(MEDIA .. "spot.tga")
    floor:SetVertexColor(0, 0, 0, 0.7)
    floor:SetSize(160, 28)
    floor:SetPoint("CENTER", page, "TOPLEFT", cx, y2 + 12)
    local model = CreateFrame("PlayerModel", nil, page)
    model:SetPoint("TOPLEFT", page, "TOPLEFT", x1, y1 - 24)
    model:SetPoint("BOTTOMRIGHT", page, "TOPLEFT", x2, y2 - 24)
    model.facing, model.spot = 0, spot
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self, btn) if btn == "LeftButton" then self.dragX = GetCursorPosition() end end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnHide", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = self.facing + (x - self.dragX) / (UIParent:GetEffectiveScale() * 90)
        self.dragX = x
        self:SetFacing(self.facing)
    end)
    return model
end

function I:Refresh()
    if not win or not win:IsShown() or not self.unit then return end
    local unit = self.unit
    local sum, n = 0, 0
    local okInfo, errInfo = pcall(fillInfo, unit)
    if not okInfo and MinimalUIDB then MinimalUIDB.inspectErr = tostring(errInfo) end
    if not isTrue(call(UnitIsPlayer, unit)) then
        -- A creature or a pet: its name in its attitude's colour, and
        -- "Level 12 Beast" under it.
        local sh = win.shell
        sh:SetAttitude(unit)
        sh:SetTitle(UnitName(unit))
        local lvl = UnitLevel(unit)
        local kind = call(UnitCreatureType, unit)
        local bits = {}
        if plain(lvl) then bits[#bits + 1] = "Level " .. (lvl > 0 and lvl or "??") end
        if type(kind) == "string" and not secret(kind) and kind ~= "" then bits[#bits + 1] = kind end
        sh:SetSubtitle(table.concat(bits, " "))
        return
    end
    for _, b in pairs(self.mode == "gear" and tiles or {}) do
        local tex = call(GetInventoryItemTexture, unit, b.slot)
        b.icon:SetTexture(tex or b.empty)
        b.icon:SetDesaturated(not tex)
        b.icon:SetAlpha(tex and 1 or 0.3)
        local c = tex and qualityColor(call(GetInventoryItemQuality, unit, b.slot))
        if c then b.ring(c.r, c.g, c.b, 1) else b.ring(T.border[1], T.border[2], T.border[3], 1) end
        b.lvl = tex and not NO_ILVL[b.slotName] and itemLevel(call(GetInventoryItemLink, unit, b.slot)) or nil
        b.ilvl:SetText(b.lvl and string.format("%d", b.lvl) or "")
        if b.lvl then sum, n = sum + b.lvl, n + 1 end
    end

    -- Header.
    local sh = win.shell
    local name = ns.modules.Character and ns.modules.Character.FullName and ns.modules.Character.FullName(unit)
        or UnitName(unit)
    local _, token = UnitClass(unit)
    local cc = token and not secret(token) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if cc then sh:SetTitle(name, cc.r, cc.g, cc.b) else sh:SetTitle(name) end
    sh:SetRing(cc and { cc.r, cc.g, cc.b } or nil)
    local parts = {}
    local lvl = UnitLevel(unit)
    if plain(lvl) then
        table.insert(parts, string.format("Level %s %s %s", lvl > 0 and lvl or "??", UnitRace(unit) or "",
            UnitClass(unit) or ""))
    end
    local guild = call(GetGuildInfo, unit)
    if guild and not secret(guild) then table.insert(parts, guild) end
    sh:SetSubtitle(table.concat(parts, "  ·  "))
    -- The average of the pieces worn, as your own window has it. (The
    -- game's inspect figure read 9 for someone whose pieces averaged 17:
    -- it seems to count empty slots as nothing. Used only with no tiles.)
    local avg = n > 0 and sum / n or nil
    if not avg then
        avg = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and call(C_PaperDollInfo.GetInspectItemLevel, unit)
        if not (plain(avg) and avg > 0) then avg = nil end
    end
    if avg then sh:SetChip(string.format("Item level %d", math.floor(avg + 0.5)), T.accent) else sh:SetChip(nil) end
end

local function build()
    win = CreateFrame("Frame", "MinimalUIInspect", UIParent)
    -- (As wide as the gear and the character window's stats card.)
    local Cm = ns.modules.Character
    win:SetSize(W + (Cm and Cm.CARD_W or INFO_W - 20) + 20, H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        I.db.pos = { p, rp, x, y }
    end)
    local pos = I.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("CENTER", UIParent, "CENTER", 120, 40) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIInspect")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))
    win.shell = ns:CreateShell(win)

    local page = CreateFrame("Frame", nil, win)
    page:SetPoint("TOPLEFT", 0, -PAGE_TOP)
    page:SetPoint("BOTTOMRIGHT")
    local top = 0
    for i, s in ipairs(LEFT_SLOTS) do
        local b = makeTile(page, s)
        if b then b:SetPoint("TOPLEFT", page, "TOPLEFT", 20, top - (i - 1) * (TILE + GAP)) end
    end
    for i, s in ipairs(RIGHT_SLOTS) do
        local b = makeTile(page, s)
        if b then b:SetPoint("TOPLEFT", page, "TOPLEFT", GEAR_W - TILE, top - (i - 1) * (TILE + GAP)) end
    end
    local weapons = {}
    for _, s in ipairs(WEAPON_SLOTS) do
        local b = makeTile(page, s)
        if b then table.insert(weapons, b) end
    end
    local rowW = #weapons * TILE + (#weapons - 1) * GAP
    local cx = (20 + GEAR_W) / 2
    for i, b in ipairs(weapons) do
        b:SetPoint("TOPLEFT", page, "TOPLEFT", cx - rowW / 2 + (i - 1) * (TILE + GAP), top - 8 * (TILE + GAP))
    end
    win.model = makeModel(page, 20 + TILE + 10, top, GEAR_W - TILE - 10, top - 8 * (TILE + GAP) + 6)
    -- With no gear to show (a creature, someone out of reach) the tiles go
    -- and the model has the whole of their side.
    win.setMode = function(mode)
        I.mode = mode
        for _, b in pairs(tiles) do b:SetShown(mode == "gear") end
        local m = win.model
        m:ClearAllPoints()
        if mode == "gear" then
            m:SetPoint("TOPLEFT", page, "TOPLEFT", 20 + TILE + 10, top - 24)
            m:SetPoint("BOTTOMRIGHT", page, "TOPLEFT", GEAR_W - TILE - 10, top - 8 * (TILE + GAP) + 6 - 24)
        else
            m:SetPoint("TOPLEFT", page, "TOPLEFT", 20, top - 10)
            m:SetPoint("BOTTOMRIGHT", page, "TOPLEFT", GEAR_W, top - 8 * (TILE + GAP) - TILE)
        end
    end
    if Cm and Cm.MakeStatsCard then
        local card = Cm.MakeStatsCard(page, 0, H - PAGE_TOP)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", page, "TOPLEFT", W, 0)
        card:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 16)
        win.card = card
    end

    win:SetScript("OnHide", function()
        win.shell:ClearModel()
        win.model:ClearModel()
        local f = _G.InspectFrame
        if not closing and f and f:IsShown() then HideUIPanel(f) end
    end)
end

local function open(unit, mode)
    if not unit or not UnitExists(unit) then return end
    if not win then build() end
    win.setMode(mode or "gear")
    I.unit = unit
    I.guid = UnitGUID(unit)
    win.shell:SetUnit(unit)
    win.model:ClearModel()
    win.model:SetUnit(unit)
    win.model.facing = 0
    win.model:SetFacing(0)
    local _, token = UnitClass(unit)
    local cc = token and not secret(token) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if cc then win.model.spot:SetVertexColor(cc.r, cc.g, cc.b, 0.16) else win.model.spot:SetVertexColor(1, 1, 1, 0.08) end
    if not win:IsShown() then win:Show() end
    I:Refresh()
end

-- Open on your target, whatever it is (the button by the target frame,
-- /men inspect); again to close. A player in reach goes through the game's
-- own inspect (which brings their gear); anything else is shown as it is.
function I:Open()
    if win and win:IsShown() then win:Hide() return end
    if not UnitExists("target") then return ns:Print("Nothing targeted to inspect.") end
    if isTrue(call(UnitIsPlayer, "target")) and isTrue(call(CanInspect, "target")) and type(InspectUnit) == "function" then
        pcall(InspectUnit, "target")
        if win and win:IsShown() then return end
    end
    open("target", "plain")
end
ns.commands = ns.commands or {}
ns.commands.inspect = function() I:Open() end

local function close()
    if win and win:IsShown() then
        closing = true
        win:Hide()
        closing = false
    end
end

-- Blizzard's inspect frame (load-on-demand): kept open, invisible.
local function hookFrame()
    local f = _G.InspectFrame
    if not f or f.__muiGhost then return end
    f.__muiGhost = true
    local function apply(self)
        self:SetAlpha(0); self:SetScale(0.001); self:EnableMouse(false)
        open(self.unit or "target")
    end
    f:HookScript("OnShow", apply)
    f:HookScript("OnHide", close)
    if f:IsShown() then apply(f) end
end

function I:OnInit(db)
    self.db = db
    hookFrame()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_LOADED", "INSPECT_READY", "UNIT_INVENTORY_CHANGED", "GET_ITEM_INFO_RECEIVED",
                         "UNIT_MODEL_CHANGED", "PLAYER_TARGET_CHANGED", "LOOT_OPENED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_HEALTH", "UNIT_AURA", "UNIT_TARGET" }) do
        pcall(ev.RegisterUnitEvent, ev, e, "target")
    end
    local dirty, acc = false, 0
    ev:SetScript("OnEvent", function(_, e, arg, _, spellID)
        if e == "ADDON_LOADED" then hookFrame(); return end
        -- What is seen of creatures is noted whether the window is open or not.
        local shown = win and win:IsShown()
        if e == "PLAYER_TARGET_CHANGED" then
            pcall(noteTarget)
            -- (Showing a creature, or someone out of reach: it follows your target.)
            if shown and I.mode == "plain" then
                if UnitExists("target") then open("target", "plain") else win:Hide() end
            end
            return
        elseif e == "LOOT_OPENED" then
            pcall(noteLoot)
            if shown and I.mode == "plain" then dirty = true end
            return
        elseif e == "UNIT_SPELLCAST_START" or e == "UNIT_SPELLCAST_CHANNEL_START" then
            local ok, new = pcall(noteCast, spellID)
            if ok and new and shown and I.mode == "plain" then dirty = true end
            return
        elseif e == "UNIT_HEALTH" then
            local ok, new = pcall(noteDeath)
            if ok and new and shown and I.mode == "plain" then dirty = true end
            return
        elseif e == "UNIT_AURA" or e == "UNIT_TARGET" then
            if shown and I.unit == "target" then dirty = true end
            return
        end
        if not shown then return end
        if e == "INSPECT_READY" and arg and I.guid and arg ~= I.guid then return end
        if (e == "UNIT_INVENTORY_CHANGED" or e == "UNIT_MODEL_CHANGED") and arg ~= I.unit then return end
        if e == "UNIT_MODEL_CHANGED" then win.model:SetUnit(I.unit) end
        dirty = true
    end)
    ev:SetScript("OnUpdate", function(_, dt)
        if not dirty then return end
        acc = acc + dt
        if acc < 0.15 then return end
        acc, dirty = 0, false
        I:Refresh()
    end)
    -- "Inspect" by the target frame: there
    -- whenever you have a target, since it is the frame's child.
    C_Timer.After(1, function()
        local UFm = ns.modules.UnitFrames
        local tf = UFm and UFm.target
        if not (tf and ns.Pill) or InCombatLockdown() or db.button == false then return end
        local b = ns.Pill(tf, "Inspect", function() I:Open() end, { h = 16, font = 9, pad = 16, ring = true, dimIdle = true })
        -- (Above its left end: to the left of it is the power orb.)
        b:SetPoint("BOTTOMLEFT", tf, "TOPLEFT", 14, 5)
        b:SetFrameLevel(tf:GetFrameLevel() + 5)
        I.button = b
    end)
end
