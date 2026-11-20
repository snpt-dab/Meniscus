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

-- ── The column of details ────────────────────────────────────────────────
-- Headings, "label ... value" rows, wrapped notes and rows of aura
-- pictures, laid out down a card; all from one pool, refilled each time.
local info
local IW = INFO_W - 20 - 28
local DIM = T.textDim or { 0.6, 0.6, 0.65, 1 }
local function infoReset()
    for i = 1, #info.rows do info.rows[i]:Hide() end
    for i = 1, #info.icons do info.icons[i]:Hide() end
    info.n, info.ni, info.y = 0, 0, -14
end
local function infoRow(h)
    info.n = info.n + 1
    local r = info.rows[info.n]
    if not r then
        r = CreateFrame("Frame", nil, info.card)
        r.l = r:CreateFontString(nil, "OVERLAY")
        r.v = r:CreateFontString(nil, "OVERLAY")
        r.l:SetJustifyH("LEFT"); r.l:SetJustifyV("TOP")
        r.v:SetJustifyH("RIGHT")
        r.v:SetPoint("TOPRIGHT")
        r:SetScript("OnEnter", function(self)
            if not self.item then return end
            ns.TipAnchor(self)
            if pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item) then GameTooltip:Show() end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        info.rows[info.n] = r
    end
    r.item = nil
    r:EnableMouse(false)
    r.v:SetText("")
    r.l:ClearAllPoints()
    r.l:SetPoint("TOPLEFT")
    r.l:SetWidth(0)
    r.l:SetWordWrap(false)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", info.card, "TOPLEFT", 14, info.y)
    r:SetSize(IW, h)
    r:Show()
    return r
end
local function rowFont(r, key, ls, lb, vs, vb) -- (set once per look: SetFont makes a table each time)
    if r.font == key then return end
    r.font = key
    ns:SetFont(r.l, ls, "", lb)
    if vs then ns:SetFont(r.v, vs, "", vb) end
end
local function infoHead(label)
    if info.n > 0 then info.y = info.y - 10 end
    local r = infoRow(14)
    rowFont(r, "head", 9, true)
    r.l:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    r.l:SetText(label:upper())
    info.y = info.y - 18
end
local function infoLine(label, value, c)
    local r = infoRow(15)
    rowFont(r, "line", 11, false, 11, true)
    r.l:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    r.l:SetText(label)
    c = c or T.text
    r.v:SetTextColor(c[1], c[2], c[3], 1)
    r.v:SetText(value) -- (a hidden value goes straight through)
    info.y = info.y - 17
    return r
end
local function infoNote(str, c)
    local r = infoRow(14)
    rowFont(r, "note", 10, false)
    c = c or DIM
    r.l:SetTextColor(c[1], c[2], c[3], 1)
    r.l:SetWidth(IW)
    r.l:SetWordWrap(true)
    r.l:SetText(str)
    local h = math.max(r.l:GetStringHeight() or 0, 12)
    r:SetHeight(h)
    info.y = info.y - h - 5
    return r
end
local function infoItem(item, times)
    local name, link = nil, nil
    if C_Item and C_Item.GetItemInfo then name, link = call(C_Item.GetItemInfo, item) end
    local r = infoLine(type(link) == "string" and link or ("Item " .. item), times > 1 and ("x" .. times) or "")
    r.l:SetTextColor(1, 1, 1, 1)
    r.l:SetWidth(IW - 30)
    r.item = item
    r:EnableMouse(true)
end
local ICON, PER = 22, 8
local function infoAuras(unit, filter, max)
    local U = C_UnitAuras
    if not (U and U.GetAuraDataByIndex) then return 0 end
    local shown = 0
    for i = 1, max do
        local ok, a = pcall(U.GetAuraDataByIndex, unit, i, filter)
        if not ok or type(a) ~= "table" then break end
        info.ni = info.ni + 1
        local b = info.icons[info.ni]
        if not b then
            b = CreateFrame("Frame", nil, info.card)
            b:SetSize(ICON, ICON)
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints()
            b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b:EnableMouse(true)
            b:SetScript("OnEnter", function(self)
                if not (self.aura and GameTooltip.SetUnitAuraByAuraInstanceID) then return end
                ns.TipAnchor(self)
                if pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self.unit, self.aura) then GameTooltip:Show() end
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            info.icons[info.ni] = b
        end
        b.unit, b.aura = unit, a.auraInstanceID
        b.tex:SetTexture(a.icon)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", info.card, "TOPLEFT", 14 + (shown % PER) * (ICON + 3), info.y - math.floor(shown / PER) * (ICON + 3))
        b:Show()
        shown = shown + 1
    end
    if shown > 0 then info.y = info.y - math.ceil(shown / PER) * (ICON + 3) - 3 end
    return shown
end

local STAT_KEYS = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
                    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" }
local STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local RANK = { elite = "Elite", rareelite = "Rare elite", rare = "Rare", worldboss = "Boss", trivial = "Trivial", minus = "Minor" }
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
local function fillPlayer(unit)
    infoHead("Attributes")
    if I.mode == "gear" then
        wipe(gearSum)
        local read = 0
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
        local exact, guessed, bare = false, false, false
        for i = 1, 5 do
            local _, real = call(UnitStat, unit, i)
            local gear = gearSum[STAT_KEYS[i]] or 0
            local label = _G["SPELL_STAT" .. i .. "_NAME"] or STAT_NAMES[i]
            if plain(real) and real > 0 then
                exact = true
                infoLine(label, string.format("%d", real))
            else
                local base = baseFor(unit, i)
                if base then
                    guessed = true
                    infoLine(label, string.format("~%d", base + gear))
                else
                    bare = true
                    infoLine(label, string.format("+%d", gear), gear > 0 and T.text or DIM)
                end
            end
        end
        local armor = gearSum.RESISTANCE0_NAME
        if armor and armor > 0 then infoLine(_G.ARMOR or "Armor", string.format("%d", armor)) end
        if read == 0 then infoNote("Their gear has not arrived yet.")
        elseif guessed then infoNote("About: what their class and race have at this level, plus their gear. Talents and buffs are not counted.")
        elseif bare and not exact then infoNote("From their gear alone. What their class and race add at this level is not known yet.") end
    else
        infoNote("Out of reach: their gear cannot be seen from here.")
    end
    infoHead("About")
    local _, rank = call(GetGuildInfo, unit)
    if type(rank) == "string" and not secret(rank) and rank ~= "" then infoLine("Guild rank", rank) end
    local _, faction = call(UnitFactionGroup, unit)
    if type(faction) == "string" and not secret(faction) and faction ~= "" then infoLine("Faction", faction) end
    if isTrue(call(UnitIsPVP, unit)) then infoLine("Player combat", "Flagged", { 0.92, 0.38, 0.35 }) end
    local tn = call(UnitName, unit .. "target")
    if tn then infoLine("Targeting", tn) end
    infoHead("Buffs")
    if infoAuras(unit, "HELPFUL", 24) == 0 then infoNote(InCombatLockdown() and "Not readable in a fight." or "None.") end
end
local function fillCreature(unit)
    infoHead("About")
    local kind = call(UnitCreatureType, unit)
    if kind and (secret(kind) or kind ~= "") then infoLine("Kind", kind) end
    local family = call(UnitCreatureFamily, unit)
    if family and (secret(family) or family ~= "") then infoLine("Family", family) end
    local cls = call(UnitClassification, unit)
    if type(cls) == "string" and not secret(cls) and RANK[cls] then infoLine("Rank", RANK[cls], T.accent) end
    if isTrue(call(UnitIsTapDenied, unit)) then infoLine("Claimed", "By someone else", DIM) end
    if isTrue(call(UnitIsDead, unit)) then infoLine("State", "Dead", DIM) end
    local tn = call(UnitName, unit .. "target")
    if tn then infoLine("Targeting", tn) end
    infoHead("On it")
    local n = infoAuras(unit, "HELPFUL", 16) + infoAuras(unit, "HARMFUL", 16)
    if n == 0 then infoNote(InCombatLockdown() and "Not readable in a fight." or "Nothing.") end
    local id = npcID(unit)
    local r = id and record(id)
    infoHead("What you have seen")
    if not r then
        infoNote(id and "Nothing yet. Kills, casts and notable drops are noted as you fight it."
            or "Nothing is kept for this one.")
        return
    end
    infoLine("Kills", string.format("%d", r.k or 0))
    if r.lo then infoLine("Levels", r.lo == r.hi and tostring(r.lo) or (r.lo .. " to " .. r.hi)) end
    if r.c and next(r.c) then
        local names = {}
        for name in pairs(r.c) do names[#names + 1] = name end
        table.sort(names)
        infoNote("Casts: " .. table.concat(names, ", "), T.text)
    end
    if r.d and next(r.d) then
        infoNote("Dropped for you:")
        local ids = {}
        for item in pairs(r.d) do ids[#ids + 1] = item end
        table.sort(ids)
        for _, item in ipairs(ids) do infoItem(item, r.d[item]) end
    end
end
local function fillInfo(unit)
    if not info then return end
    infoReset()
    if isTrue(call(UnitIsPlayer, unit)) then fillPlayer(unit) else fillCreature(unit) end
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
    pcall(fillInfo, unit)
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
    local avg = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and call(C_PaperDollInfo.GetInspectItemLevel, unit)
    if not (plain(avg) and avg > 0) then avg = n > 0 and sum / n or nil end
    if avg then sh:SetChip(string.format("Item level %d", math.floor(avg + 0.5)), T.accent) else sh:SetChip(nil) end
end

local function build()
    win = CreateFrame("Frame", "MinimalUIInspect", UIParent)
    win:SetSize(W + INFO_W, H)
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
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", page, "TOPLEFT", W, 0)
    card:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 20)
    ns.RoundedRect(card, -6, 0, 10, 1, 1, 1, 0.035)
    info = { card = card, rows = {}, icons = {}, n = 0, ni = 0, y = -14 }

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
    -- "Inspect" beside the target frame (to its left, level with it): there
    -- whenever you have a target, since it is the frame's child.
    C_Timer.After(1, function()
        local UFm = ns.modules.UnitFrames
        local tf = UFm and UFm.target
        if not (tf and ns.Pill) or InCombatLockdown() or db.button == false then return end
        local b = ns.Pill(tf, "Inspect", function() I:Open() end, { h = 16, font = 9, pad = 16, ring = true, dimIdle = true })
        b:SetPoint("RIGHT", tf, "LEFT", -8, 0)
        b:SetFrameLevel(tf:GetFrameLevel() + 5)
        I.button = b
    end)
end
