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
--   MinimalUIDB.bestiary[npcID]: kept and described in Bestiary.lua (since
--   0.1.560; it began here).

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
-- (Kept by Bestiary.lua, which is loaded first: the records, and the rows
-- that show one.)
local Bst = ns.Bestiary
if not Bst then -- (a new file: not there until the game is restarted)
    local none = function() end
    Bst = { npcID = none, record = none, OnChange = none, Open = none, Rows = function(rows) return rows end }
end
local npcID, record = Bst.npcID, Bst.record
local function isTrue(v) return not secret(v) and v == true end

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
-- What someone's buffs add, read from the buffs' own tooltips (the game
-- gives no numbers with a buff here, but the tooltip says "Increases
-- Stamina by 54." and can be had for anyone's buff out of a fight).
-- English wording; a percentage, or anything that reduces, is left out.
-- Kept by the buff's instance until another unit is shown.
local STAT_WORDS = { "strength", "agility", "stamina", "intellect", "spirit" }
local RES_WORDS = { [2] = "fire", [3] = "nature", [4] = "frost", [5] = "shadow", [6] = "arcane" }
local auraCache = {}
local function numIn(low, pat)
    local _, e, v = low:find(pat)
    if v and low:sub(e + 1, e + 1) ~= "%" then return tonumber(v) end
end
local function auraGives(unit, id) -- { [1..5] = attribute, [12..16] = resistance by school + 10 } or false
    if id == nil or secret(id) then return false end
    local c = auraCache[id]
    if c ~= nil then return c end
    c = false
    local TI = C_TooltipInfo
    local d = TI and TI.GetUnitBuffByAuraInstanceID and call(TI.GetUnitBuffByAuraInstanceID, unit, id)
    local line = type(d) == "table" and type(d.lines) == "table" and d.lines[2]
    local txt = type(line) == "table" and line.leftText
    if type(txt) == "string" and not secret(txt) and txt ~= "" then
        local low = txt:lower()
        if not low:find("reduc") and not low:find("decreas") then
            local all = numIn(low, "all attributes[^%.%d]*by (%d+)") or numIn(low, "all stats[^%.%d]*by (%d+)")
            local allR = numIn(low, "all[%a ]*resistances?[^%.%d]*by (%d+)")
            local g, any = {}, false
            for i, w in ipairs(STAT_WORDS) do
                local v = all or numIn(low, w .. "[^%.%d]*by (%d+)")
                if v then g[i] = v; any = true end
            end
            for school, w in pairs(RES_WORDS) do
                local v = allR or numIn(low, w .. " resistance[^%.%d]*by (%d+)")
                if v then g[10 + school] = v; any = true end
            end
            if any then c = g end
        end
    end
    auraCache[id] = c
    return c
end
local function buffSums(unit)
    local U = C_UnitAuras
    if not (U and U.GetAuraDataByIndex) then return end
    local sum
    for i = 1, 40 do
        local ok, a = pcall(U.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or type(a) ~= "table" then break end
        local g = auraGives(unit, a.auraInstanceID)
        if g then
            sum = sum or {}
            for k, v in pairs(g) do sum[k] = (sum[k] or 0) + v end
        end
    end
    return sum
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
    local buff = buffSums(unit)
    if buff then
        for school = 2, 6 do
            local v = buff[10 + school]
            if v then res = res or {}; res[school] = (res[school] or 0) + v end
        end
    end
    head(rows, "About", "micro_character.tga")
    local _, real = call(UnitStat, unit, 1)
    if not (plain(real) and real > 0) then
        if I.mode ~= "gear" then note(rows, "Out of reach: their gear is not shown")
        elseif read == 0 then note(rows, "Their gear has not arrived yet")
        elseif base then note(rows, "Attributes: class and race, gear, buffs")
        else note(rows, "Attributes: from their gear and buffs") end
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
    return rows, base, gear, res, buff
end
local function fillCreature(unit)
    local rows = {}
    head(rows, "About", "micro_character.tga")
    local kind = call(UnitCreatureType, unit)
    -- (Its type is in the header line; rank and disposition are icons now.)
    local family = call(UnitCreatureFamily, unit)
    if family and (secret(family) or family ~= "") then stat(rows, "Family", family) end
    local cls = call(UnitClassification, unit)
    if isTrue(call(UnitIsTapDenied, unit)) then stat(rows, "Claimed", "By someone else", DIM) end
    if isTrue(call(UnitIsDead, unit)) then stat(rows, "State", "Dead", DIM) end
    stat(rows, "Targeting", (call(UnitName, unit .. "target")))
    if rows[#rows].kind == "header" then rows[#rows] = nil end -- (nothing to say under "About")
    -- (With none on it the section is left out; in a fight they can't be read, and it says so.)
    head(rows, "Buffs and debuffs", "micro_buff.tga")
    if auras(rows, unit, "HELPFUL", 16) + auras(rows, unit, "HARMFUL", 16) == 0 then
        if InCombatLockdown() then note(rows, "Not readable in a fight") else rows[#rows] = nil end
    end
    local id = npcID(unit)
    head(rows, "What you have seen", "micro_journal.tga")
    Bst.Rows(rows, id)
    if id and record(id) then
        rows[#rows + 1] = { kind = "stat", label = "Open the bestiary", labelColor = T.accent, value = "",
            onClick = function() Bst:Open(id) end }
    end
    return rows
end
local function fillInfo(unit)
    local Cm = ns.modules.Character
    if not (win and win.card and Cm and Cm.FillOtherCard) then return end
    local rows, base, gear, res, buff
    -- A creature has no attributes the game will tell (the tiles and the
    -- graph showed "?" all round, 0.1.573): it gets a plain card, the
    -- whole height, of what is known of it.
    local beast = not isTrue(call(UnitIsPlayer, unit)) and win.beast
    if win.beast then
        win.beast:SetShown(beast and true or false)
        win.card:SetShown(not beast)
    end
    if beast then
        beast.list:SetData(fillCreature(unit))
        if beast.strip then
            -- (one row of icons or two: the list sits right under them)
            local rowsOf = beast.strip:Set((npcID(unit)))
            beast.list:ClearAllPoints()
            beast.list:SetPoint("TOPLEFT", 2, -8 - (rowsOf > 0 and (rowsOf * 28 + 6) or 0))
        end
        return
    end
    if isTrue(call(UnitIsPlayer, unit)) then rows, base, gear, res, buff = fillPlayer(unit) else rows = fillCreature(unit) end
    Cm.FillOtherCard(win.card, unit, base, gear, rows, res, buff)
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
        local link
        if I.snap then link = I.snapLink(self.slot) else link = call(GetInventoryItemLink, I.unit, self.slot) end
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    b:SetScript("OnEnter", function(self)
        ns.TipAnchor(self)
        local has
        if I.snap then
            local link = I.snapLink(self.slot)
            has = link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        else
            has = I.unit and GameTooltip:SetInventoryItem(I.unit, self.slot)
        end
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
    -- (Turned a little to one side to start with, about 30 degrees: 0.1.601.)
    model.facing, model.spot, model.floor = 0.52, spot, floor
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

-- ── A saved character (0.1.672) ───────────────────────────────────────────
-- The same window for one of your own characters as it was last seen
-- (Alts.lua keeps the record; the Roster tab of the character window opens
-- this). Tiles from the saved links, the card from the saved numbers. The
-- figure in the middle is a stand-in: a model of that race and sex put in
-- the saved gear, where the game will make one (the face and hair are not
-- on file); else the class emblem.
function I.snapLink(slot)
    local g = I.snap and I.snap.ch and I.snap.ch.g
    local l = type(g) == "table" and g[slot]
    return type(l) == "string" and l or nil
end
local POWER = { MANA = "Mana", RAGE = "Rage", ENERGY = "Energy", FOCUS = "Focus" }
local function refreshSnap()
    local snap = I.snap
    local ch, who = snap.ch, snap.who
    local A = ns.Alts
    local sum, n = 0, 0
    wipe(gearSum)
    local read = 0
    for _, b in pairs(tiles) do
        local link = I.snapLink(b.slot)
        local tex
        if link and C_Item and C_Item.GetItemInfoInstant then
            local _, _, _, _, t = call(C_Item.GetItemInfoInstant, link)
            tex = t
        end
        b.icon:SetTexture(tex or b.empty)
        b.icon:SetDesaturated(not tex)
        b.icon:SetAlpha(tex and 1 or 0.3)
        local q = link and C_Item and C_Item.GetItemQualityByID and call(C_Item.GetItemQualityByID, link)
        local c = tex and qualityColor(q)
        if c then b.ring(c.r, c.g, c.b, 1) else b.ring(T.border[1], T.border[2], T.border[3], 1) end
        b.lvl = tex and not NO_ILVL[b.slotName] and itemLevel(link) or nil
        b.ilvl:SetText(b.lvl and string.format("%d", b.lvl) or "")
        if b.lvl then sum, n = sum + b.lvl, n + 1 end
        local st = link and ns.ItemStats and ns.ItemStats(link)
        if st then
            read = read + 1
            for k, v in pairs(st) do
                if type(v) == "number" and not secret(v) then gearSum[k] = (gearSum[k] or 0) + v end
            end
        end
    end
    -- The card: attributes as saved, with the share that is gear; else
    -- gear alone.
    local base, gear, res
    if read > 0 then
        gear = {}
        for i = 1, 5 do gear[i] = gearSum[STAT_KEYS[i]] or 0 end
    end
    if type(ch.s) == "table" then
        base = {}
        for i = 1, 5 do base[i] = math.max(0, (ch.s[i] or 0) - (gear and gear[i] or 0)) end
    end
    if type(ch.rs) == "table" then
        res = ch.rs
    elseif read > 0 then
        res = {}
        for school = 2, 6 do res[school] = gearSum["RESISTANCE" .. school .. "_NAME"] or 0 end
    end
    local rows = {}
    head(rows, "As last seen", "micro_character.tga")
    stat(rows, "When", A and A.Ago and A.Ago(ch.t) or nil)
    stat(rows, "Where", ch.z)
    stat(rows, "Money", ch.m and ns.Money and ns.Money(ch.m) or nil)
    if ch.xp then stat(rows, "Into this level", ch.xp .. "%" .. ((ch.rx or 0) > 0 and "  (rested)" or "")) end
    stat(rows, "Health", ch.hp)
    if ch.mp and ch.mp > 0 then stat(rows, POWER[ch.pt or ""] or "Power", ch.mp) end
    stat(rows, "Armor", ch.ar or ((gearSum.RESISTANCE0_NAME or 0) > 0 and string.format("%d from gear", gearSum.RESISTANCE0_NAME)) or nil)
    if not ch.s then note(rows, "Log this character in once for the rest of its sheet") end
    if type(ch.pr) == "table" and #ch.pr > 0 then
        head(rows, "Professions", "micro_profession.tga")
        for i = 1, #ch.pr, 3 do
            local max = ch.pr[i + 2]
            stat(rows, ch.pr[i], tostring(ch.pr[i + 1]) .. (max and max > 0 and (" / " .. max) or ""))
        end
    end
    local Cm = ns.modules.Character
    if win.card and Cm and Cm.FillOtherCard then
        if win.beast then win.beast:Hide() end
        win.card:Show()
        Cm.FillOtherCard(win.card, "none", base, gear, rows, res, nil)
    end
    -- Header.
    local sh = win.shell
    local cc = ch.c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ch.c]
    if cc then sh:SetTitle(who, cc.r, cc.g, cc.b) else sh:SetTitle(who) end
    sh:SetRing(cc and { cc.r, cc.g, cc.b } or nil)
    local cls = ch.c and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[ch.c] or ch.c) or ""
    sh:SetSubtitle(string.format("Level %s %s %s", tostring(ch.l or "?"), ch.r or "", cls)
        .. "  \194\183  as of " .. (A and A.Ago and A.Ago(ch.t) or "some time ago"))
    if n > 0 then sh:SetChip(string.format("Item level %d", math.floor(sum / n + 0.5)), T.accent) else sh:SetChip(nil) end
end
function I:Refresh()
    if win and win:IsShown() and self.snap then
        local ok, err = pcall(refreshSnap)
        if not ok and MinimalUIDB then MinimalUIDB.inspectErr = tostring(err) end
        return
    end
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
        if Cm.MakeList then
            local cw = (Cm.CARD_W or INFO_W - 20)
            local ch = H - PAGE_TOP - 16
            local beast = CreateFrame("Frame", nil, page)
            beast:SetPoint("TOPLEFT", page, "TOPLEFT", W, 0)
            beast:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 16)
            ns.RoundedRect(beast, -6, 0, 10, 0.085, 0.085, 0.095, 1)
            -- (the bestiary's trait icons across the top, 0.1.594; the list under them)
            local STRIP = Bst.MakeStrip and 62 or 0
            local rowsFit = math.floor((ch - 16 - 30 - STRIP) / 20) -- (room for "Refresh" under the list)
            if Bst.MakeStrip then
                beast.strip = Bst.MakeStrip(beast, 8)
                beast.strip:SetPoint("TOPLEFT", beast, "TOPLEFT", 14, -12)
            end
            -- Refresh (0.1.583): shows whatever you have targeted now, and
            -- reads it again. For when the window has not followed.
            local rf = ns.Pill(beast, "Refresh", function()
                if UnitExists("target") and I.Retarget then I.Retarget() else I:Refresh() end
            end, { h = 22, pad = 22, minW = 0 })
            rf:SetPoint("BOTTOMRIGHT", beast, "BOTTOMRIGHT", -10, 8)
            beast.list = Cm.MakeList(beast, cw - 12, rowsFit * 20, 20, 100)
            beast.list:SetPoint("TOPLEFT", 2, -8 - STRIP)
            beast:Hide()
            win.beast = beast
        end
    end

    win:SetScript("OnHide", function()
        I.snap = nil
        if I.figureOff then I.figureOff() end
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
    I.snap = nil
    if I.figureOff then I.figureOff() end
    win.model:Show()
    local og = UnitGUID(unit)
    if secret(og) or secret(I.guid) or I.guid ~= og then wipe(auraCache) end
    I.unit = unit
    I.guid = UnitGUID(unit)
    win.shell:SetUnit(unit)
    win.model:ClearModel()
    win.model:SetUnit(unit)
    win.model.facing = 0.52
    win.model:SetFacing(0.52)
    -- The shadow on the floor is where a player's feet come: a creature's
    -- model is fitted to the space its own way (a tall one stands smaller
    -- and higher), and it floated over the shadow. Players only.
    if win.model.floor then win.model.floor:SetShown(isTrue(call(UnitIsPlayer, unit))) end
    local _, token = UnitClass(unit)
    local cc = token and not secret(token) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if cc then win.model.spot:SetVertexColor(cc.r, cc.g, cc.b, 0.16) else win.model.spot:SetVertexColor(1, 1, 1, 0.08) end
    if not win:IsShown() then win:Show() end
    I:Refresh()
end

local CLASS_MARK = { DRUID = 1, HUNTER = 1, MAGE = 1, PALADIN = 1, PRIEST = 1, ROGUE = 1, SHAMAN = 1, WARLOCK = 1, WARRIOR = 1 }

-- ── The figure on a saved character's sheet (0.1.675) ─────────────────────
-- What this client was found to offer (0.1.674's record, 2026-11-25):
--   * no model, of either kind, can be told a race and sex (SetCustomRace
--     is missing from the dress-up model and from a model scene's figure);
--   * a dress-up model takes a unit, a body number (SetDisplayInfo) and
--     gear (Undress, TryOn); a model scene's figure takes a unit and gear.
-- And what was seen: for a character of your own race and sex, your own
-- figure came up, but in YOUR gear: it was set up while the window was
-- still hidden, and undressed before it had loaded.
--
-- So a figure is now stood up one of these ways, in this order:
--   own      your own figure (the saved character is of your race and
--            sex), told not to dress itself, then put in the saved gear;
--   display  a dress-up model given that race and sex's plain body by its
--            number, then the saved gear;
--   scene    the same body in a model scene of the dressing-room kind;
--   file     the body by its model file, where one was measured.
-- The body's number is the character's own, measured when it is played
-- (Alts.lua: `di`), else from RACE_BODY: the numbers the classic game data
-- gives each race and sex. Those are a GUESS for this game until a
-- character of that race has been measured (MinimalUIDB.figdiag says what
-- yours measured; compare).
--
-- The window is shown FIRST, and the gear goes on when the model says it
-- has loaded and again a little later (items still arriving answer "data
-- pending"). Whether gear takes on a body that was not made from a unit is
-- not known: each try-on's answer is written to MinimalUIDB.dolldiag. A
-- way that brings no model at all gives way to the next. With more than
-- one way to hand, a small pill over the figure steps through them and
-- remembers your pick (db.figurePick), so that the right one can be found
-- by eye in one sitting.
-- 0.1.707. The player's word on all of the above: "the paper doll isn't
-- working". The game's own code has one more way, and it is the one its
-- shop uses to show a mount or an outfit on another race: a model scene's
-- figure made from YOUR unit with a race handed over as the last value
-- (SetModelByUnit(unit, sheathe, autoDress, hideWeapons, nativeForm,
-- holdBowString, customRaceID)). A true character's body, so gear goes on
-- it as on your own; the sex and face stay yours (nothing takes a sex).
--   race     that, then the saved gear.
-- It is tried first for a character that is not of your race and sex, and
-- if it brings nothing the class emblem stands there: the older ways
-- (display, scene, file) are no longer fallen back to by themselves, only
-- reached by the pill. "/men figure off" shows the emblem always.
local RACE_BODY = { [1] = { 49, 50 }, [2] = { 51, 52 }, [3] = { 53, 54 }, [4] = { 55, 56 },
                    [5] = { 57, 58 }, [6] = { 59, 60 }, [7] = { 1563, 1564 }, [8] = { 1478, 1479 } }
local FIG = { serial = 0, notes = {}, ways = {} }
local function has(o, m) return o ~= nil and type(o[m]) == "function" end
local function methods(o, list)
    local out = {}
    for _, m in ipairs(list) do out[#out + 1] = m .. (has(o, m) and "+" or "-") end
    return table.concat(out, " ")
end
local function figNote(str)
    local n = FIG.notes
    if #n < 40 then n[#n + 1] = str end
    if MinimalUIDB then MinimalUIDB.dolldiag = table.concat(n, " | ") end
end
local function bodyOf(ch)
    if plain(ch.di) and ch.di > 0 then return ch.di, "measured" end
    local t = plain(ch.ri) and RACE_BODY[ch.ri]
    local d = t and plain(ch.sx) and t[ch.sx - 1]
    if d then return d, "from the table" end
end
-- The saved gear, armour first, then what is held (ranged before the
-- hands, so that the hands' weapons are what shows).
local HELD = { [18] = 101, [16] = 102, [17] = 103 }
local HAND = { [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT" }
local function gearLinks()
    local out = {}
    for _, b in pairs(tiles) do
        local link = I.snapLink(b.slot)
        if link then out[#out + 1] = { slot = b.slot, link = link, at = HELD[b.slot] or b.slot } end
    end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
end
-- Undress it and put the saved gear on. Returns what the game answered to
-- each piece, counted ("0 x14" = fourteen taken), whether any piece's
-- data was still on its way, and whether every piece was taken.
local PENDING = Enum and Enum.ItemTryOnReason and Enum.ItemTryOnReason.DataPending
local TAKEN = Enum and Enum.ItemTryOnReason and Enum.ItemTryOnReason.Success
local function dressWith(obj)
    if has(obj, "Undress") then pcall(obj.Undress, obj) end
    local tally, pending, all, n = {}, false, TAKEN ~= nil, 0
    for _, e in ipairs(gearLinks()) do
        local ok, res = pcall(obj.TryOn, obj, e.link, HAND[e.slot])
        local k
        n = n + 1
        if not ok then k = "refused"
        elseif res == nil then k = "no answer"
        elseif secret(res) then k = "hidden"
        else
            k = tostring(res)
            if PENDING ~= nil and res == PENDING then pending = true end
        end
        if not (ok and res ~= nil and not secret(res) and res == TAKEN) then all = false end
        tally[k] = (tally[k] or 0) + 1
    end
    local parts = {}
    for k, c in pairs(tally) do parts[#parts + 1] = k .. " x" .. c end
    table.sort(parts)
    return (#parts > 0 and table.concat(parts, ", ") or "nothing to wear"), pending, all and n > 0
end
local function getDoll()
    if win.doll or FIG.dollTried then return win.doll end
    FIG.dollTried = true
    local ok, d = pcall(CreateFrame, "DressUpModel", nil, win.model:GetParent())
    if not (ok and d) then
        figNote("no dress-up model: " .. tostring(d))
        return nil
    end
    d:SetAllPoints(win.model)
    d.facing = 0.52
    d:EnableMouse(true)
    d:SetScript("OnMouseDown", function(self, btn) if btn == "LeftButton" then self.dragX = GetCursorPosition() end end)
    d:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    d:SetScript("OnHide", function(self) self.dragX = nil end)
    d:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = self.facing + (x - self.dragX) / (UIParent:GetEffectiveScale() * 90)
        self.dragX = x
        self:SetFacing(self.facing)
    end)
    if not pcall(d.SetScript, d, "OnModelLoaded", function()
        if FIG.onLoaded then FIG.onLoaded("as it loaded") end
    end) then
        figNote("the dress-up model does not say when it has loaded")
    end
    figNote("dress-up model: " .. methods(d, { "SetUnit", "SetDisplayInfo", "SetModel", "SetAutoDress", "Undress", "TryOn",
        "GetModelFileID", "GetDisplayInfo" }))
    d:Hide()
    win.doll = d
    return d
end
local function getScene()
    if win.scene or FIG.sceneTried then return win.scene end
    FIG.sceneTried = true
    local ok, sc = pcall(CreateFrame, "ModelScene", nil, win.model:GetParent(), "ModelSceneMixinTemplate")
    if not (ok and sc) then
        figNote("no model scene: " .. tostring(sc))
        return nil
    end
    sc:SetAllPoints(win.model)
    local okS, err = pcall(function()
        if has(sc, "SetFromModelSceneID") then sc:SetFromModelSceneID(290, true) end
    end)
    if not okS then figNote("the dressing-room scene was refused: " .. tostring(err)) end
    sc:Hide()
    win.scene = sc
    return sc
end
-- Which ways are open for this character, and its body's number.
local function waysFor(ch)
    local ways = {}
    local d = getDoll()
    local body, from = bodyOf(ch)
    local okR, _, _, myRace = pcall(UnitRace, "player")
    local okS, mySex = pcall(UnitSex, "player")
    if d and has(d, "SetUnit") and has(d, "TryOn") and plain(ch.ri) and plain(ch.sx)
        and okR and okS and plain(myRace) and plain(mySex) and myRace == ch.ri and mySex == ch.sx then
        ways[#ways + 1] = "own"
    end
    if ways[1] ~= "own" and plain(ch.ri) and (win.scene or not FIG.sceneTried) then ways[#ways + 1] = "race" end
    if body and d and has(d, "SetDisplayInfo") and has(d, "TryOn") then ways[#ways + 1] = "display" end
    if body and (win.scene or not FIG.sceneTried) then ways[#ways + 1] = "scene" end
    if plain(ch.mf) and ch.mf > 0 and d and has(d, "SetModel") and has(d, "TryOn") then ways[#ways + 1] = "file" end
    return ways, body, from
end
-- Stand the figure up one way. Returns what to dress, and a function
-- that says whether a model has come (true / false; nil = can't be told).
-- Errors where the way is not to be had.
local function startWay(way, ch, body)
    if way == "scene" or way == "race" then
        local sc = getScene()
        if not sc then error("no model scene") end
        local actor = has(sc, "GetPlayerActor") and sc:GetPlayerActor() or nil
        local byHand = false
        if not actor then
            actor = FIG.actor or (has(sc, "CreateActor") and sc:CreateActor() or nil)
            FIG.actor = actor
            byHand = true
        end
        if not actor then error("no figure in the scene") end
        figNote("scene's figure (" .. (byHand and "made by hand" or "the scene's own") .. "): "
            .. methods(actor, { "SetModelByCreatureDisplayID", "SetModelByUnit", "Undress", "TryOn", "IsLoaded", "ClearModel" }))
        if way == "scene" and not has(actor, "SetModelByCreatureDisplayID") then error("the scene's figure takes no body number") end
        if way == "race" and not has(actor, "SetModelByUnit") then error("the scene's figure takes no unit") end
        if not has(actor, "TryOn") then error("the scene's figure takes no gear") end
        if has(actor, "SetOnModelLoadedCallback") then
            pcall(actor.SetOnModelLoadedCallback, actor, function()
                if FIG.onLoaded then FIG.onLoaded("as it loaded") end
            end)
        end
        sc:Show()
        if has(actor, "ClearModel") then pcall(actor.ClearModel, actor) end
        if way == "race" then
            -- (not sheathed, not dressing itself, weapons not hidden, its own form, no bowstring; the race)
            local took = actor:SetModelByUnit("player", false, false, false, true, false, ch.ri)
            figNote("race: your figure as race " .. tostring(ch.ri) .. ", the game answered " .. (secret(took) and "<hidden>" or tostring(took)))
            if not secret(took) and took == false then error("the game would not make your figure of race " .. tostring(ch.ri)) end
        else
            actor:SetModelByCreatureDisplayID(body, false)
        end
        if has(actor, "SetYaw") then pcall(actor.SetYaw, actor, 0.52) end
        return actor, function()
            if has(actor, "IsLoaded") then return actor:IsLoaded() and true or false end
            return nil
        end
    end
    local d = getDoll()
    if not d then error("no dress-up model") end
    d:Show()
    pcall(d.ClearModel, d)
    if way == "own" then
        -- (Told not to dress itself: it came up in your gear, and an
        -- "undress" sent before it had loaded was lost.)
        if has(d, "SetAutoDress") then pcall(d.SetAutoDress, d, false) end
        d:SetUnit("player")
    elseif way == "display" then
        d:SetDisplayInfo(body)
    else
        d:SetModel(ch.mf)
    end
    d.facing = 0.52
    pcall(d.SetFacing, d, 0.52)
    return d, function()
        if not has(d, "GetModelFileID") then return nil end
        local f = d:GetModelFileID()
        if secret(f) then return nil end
        return f ~= nil and f ~= 0
    end
end
local WAY_SAYS = {
    own = "A stand-in: your own figure, in its gear",
    display = "A stand-in: its race, sex and gear; not its face",
    scene = "A stand-in: its race, sex and gear; not its face",
    race = "A stand-in: its race and gear, on your own character's build",
    file = "A stand-in: its race, sex and gear; not its face",
}
-- Away with it (a live unit is shown, or the window closes).
function I.figureOff()
    FIG.serial = FIG.serial + 1
    FIG.onLoaded = nil
    if not win then return end
    if win.doll then pcall(win.doll.ClearModel, win.doll); win.doll:Hide() end
    if win.scene then win.scene:Hide() end
    if win.figPill then win.figPill:Hide() end
    if win.crest then win.crest:Hide(); win.standin:Hide() end
end
-- Show way number idx of FIG.ways (past the last: the emblem). auto: it
-- was not asked for by hand, so a way that fails gives way to the next.
local showWay
showWay = function(idx, auto)
    local ch = I.snap and I.snap.ch
    if not ch then return end
    FIG.serial = FIG.serial + 1
    local serial = FIG.serial
    FIG.onLoaded, FIG.retry = nil, false
    if win.doll then win.doll:Hide() end
    if win.scene then win.scene:Hide() end
    local ways = FIG.ways
    local way = ways[idx]
    FIG.idx = idx
    local shown = false
    if way then
        local ok, target, loadedFn = pcall(startWay, way, ch, FIG.body)
        if ok and target then
            shown = true
            -- The gear goes on when the model says it has loaded (twice at
            -- most: should dressing make it say so again, that would go
            -- round for ever), at three set moments, and up to four times
            -- more while items are still arriving. Once a model is there
            -- and every piece was taken, it is left alone.
            local passes, loadPasses, retries, done, sawLoad = 0, 0, 0, false, false
            local pass
            pass = function(why, fromLoad)
                if FIG.serial ~= serial or not (win:IsShown() and I.snap) then return nil end
                if fromLoad then
                    sawLoad = true
                    if loadPasses >= 2 then return nil end
                    loadPasses = loadPasses + 1
                end
                local okL, loaded = pcall(loadedFn)
                if not okL then loaded = nil end
                if done or passes >= 10 then return loaded end
                passes = passes + 1
                local res, pending, all = dressWith(target)
                figNote(way .. ", " .. why .. ": model " .. (loaded == nil and "can't be told" or (loaded and "there" or "not there"))
                    .. "; try-on " .. res)
                if all and loaded then done = true end
                if pending and not FIG.retry and retries < 4 then
                    FIG.retry = true
                    retries = retries + 1
                    C_Timer.After(1.0, function()
                        if FIG.serial ~= serial then return end
                        FIG.retry = false
                        pass("items were still arriving")
                    end)
                end
                return loaded
            end
            FIG.onLoaded = function(why) pass(why, true) end
            C_Timer.After(0.4, function() pass("0.4 s on") end)
            C_Timer.After(1.2, function() pass("1.2 s on") end)
            C_Timer.After(2.6, function()
                if FIG.serial ~= serial then return end
                local loaded = pass("2.6 s on")
                -- (Only where it is sure: asked, the model says it is not
                -- there, and it never said it had loaded.)
                if loaded == false and not sawLoad and auto and FIG.serial == serial then
                    figNote(way .. ": no model came; the emblem")
                    showWay(#ways + 1, true)
                end
            end)
        else
            figNote(way .. " refused: " .. tostring(target))
            -- (0.1.707: by itself only "own" gives way to the next, which is "race")
            if auto and idx <= #ways then return showWay(way == "own" and idx + 1 or #ways + 1, true) end
        end
    end
    win.crest:SetShown(not shown)
    if win.model.floor then win.model.floor:SetShown(shown and way ~= "scene" and way ~= "race") end
    local why
    if shown then why = WAY_SAYS[way]
    elseif I.db.figureOff then why = "Figures are switched off (/men figure on)"
    elseif #ways == 0 then why = "Log this character in once more and a figure in its gear stands here"
    else why = "The game would not stand a figure up here" end
    win.standin:SetText(why)
    win.standin:Show()
    if #ways >= 2 then
        win.figPill:SetLabel(shown and ("Figure " .. idx .. " of " .. #ways) or ("Figure: none of " .. #ways))
        win.figPill:Show()
    else
        win.figPill:Hide()
    end
end

function I:OpenSnapshot(who, ch)
    if type(ch) ~= "table" then return end
    if not win then build() end
    local f = _G.InspectFrame
    if f and f:IsShown() then pcall(HideUIPanel, f) end
    win.setMode("gear")
    I.unit, I.guid = nil, nil
    I.snap = { who = who, ch = ch }
    local mark = MEDIA .. "micro_class_" .. (CLASS_MARK[ch.c or ""] and ch.c:lower() or "other") .. ".tga"
    local cc = ch.c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ch.c]
    local r, g, b = cc and cc.r or 0.8, cc and cc.g or 0.8, cc and cc.b or 0.85
    if win.shell.SetEmblem then win.shell:SetEmblem(mark, r, g, b) end
    win.model:ClearModel()
    win.model:Hide()
    if win.model.floor then win.model.floor:Hide() end
    win.model.spot:SetVertexColor(r, g, b, 0.16)
    if not win.crest then
        local page = win.model:GetParent()
        win.crest = page:CreateTexture(nil, "ARTWORK")
        win.crest:SetSize(120, 120)
        win.crest:SetPoint("CENTER", win.model, "CENTER", 0, 10)
        win.standin = text(page, 10, false, DIM)
        win.standin:SetPoint("TOP", win.model, "BOTTOM", 0, 22)
    end
    if not win.figPill then
        local page = win.model:GetParent()
        win.figPill = ns.Pill(page, "Figure", function()
            local n = #FIG.ways
            if n == 0 then return end
            local nextIdx = ((FIG.idx or 0) % n) + 1
            if (FIG.idx or 0) > n then nextIdx = 1 end
            if type(I.db.figurePick) ~= "table" then I.db.figurePick = {} end
            I.db.figurePick[FIG.kind or "other"] = FIG.ways[nextIdx]
            showWay(nextIdx, false)
        end, { h = 18, pad = 16, minW = 0, font = 10 })
        win.figPill:SetPoint("BOTTOM", win.model, "TOP", 0, 3)
        win.figPill:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Another way of drawing this figure", 1, 1, 1)
            GameTooltip:AddLine("The game offers several and they do not all work. Your pick is remembered.", 0.6, 0.6, 0.65, true)
            GameTooltip:Show()
        end)
        win.figPill:HookScript("OnLeave", function() GameTooltip:Hide() end)
        win.figPill:Hide()
    end
    win.crest:SetTexture(mark)
    win.crest:SetVertexColor(r, g, b, 0.85)
    -- (The window first: a model set up while it was hidden came up
    -- dressed as you are.)
    if not win:IsShown() then win:Show() end
    I:Refresh()
    -- (Under guard: the sheet itself must open whatever the figure does.)
    local okFig, errFig = pcall(function()
        FIG.notes = {}
        for _, e in ipairs(gearLinks()) do
            if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e.link) end
        end
        local ways, body, from = waysFor(ch)
        if I.db.figureOff then ways = {} end
        -- (0.1.707: a way picked by hand among the old ones is forgotten once, so that the new one is seen)
        if I.db.figRev ~= 2 then I.db.figurePick = nil; I.db.figRev = 2 end
        FIG.ways, FIG.body = ways, body
        FIG.kind = (ways[1] == "own") and "same" or "other"
        figNote("race " .. tostring(ch.ri) .. ", sex " .. tostring(ch.sx) .. ", body " .. tostring(body)
            .. (from and (" (" .. from .. ")") or "") .. "; ways: " .. (#ways > 0 and table.concat(ways, ", ") or "none"))
        local pick = type(I.db.figurePick) == "table" and I.db.figurePick[FIG.kind] or nil
        local idx = 1
        for i, w in ipairs(ways) do
            if w == pick then idx = i end
        end
        showWay(idx, true)
    end)
    if not okFig then
        figNote("the figure failed: " .. tostring(errFig))
        if win.doll then win.doll:Hide() end
        if win.scene then win.scene:Hide() end
        win.crest:Show()
        win.standin:SetText("The game would not stand a figure up here")
        win.standin:Show()
    end
end

-- Open on your target, whatever it is (the button by the target frame,
-- /men inspect); again to close. A player in reach goes through the game's
-- own inspect (which brings their gear); anything else is shown as it is.
I.Retarget = function() open("target", "plain") end
function I:Open()
    if win and win:IsShown() then win:Hide() return end
    if not UnitExists("target") then return ns:Print("Nothing targeted to inspect.") end
    if isTrue(call(UnitIsPlayer, "target")) and isTrue(call(CanInspect, "target")) and type(InspectUnit) == "function" then
        pcall(InspectUnit, "target")
        if win and win:IsShown() then return end
        -- The game's inspect window can take a moment to come up (and ours
        -- with it). Opening the plain view meanwhile showed for an instant:
        -- a larger model and an empty card, then the real thing. Wait for
        -- it; the plain view only if it has not come.
        C_Timer.After(0.8, function()
            if not (win and win:IsShown()) and UnitExists("target") then open("target", "plain") end
        end)
        return
    end
    open("target", "plain")
end
ns.commands = ns.commands or {}
ns.commands.inspect = function() I:Open() end
-- "/men figure off | on": the figure on another character of yours' sheet
ns.commands.figure = function(rest)
    if not I.db then return end
    if rest and rest:find("off") then I.db.figureOff = true elseif rest and rest:find("on") then I.db.figureOff = nil end
    ns:Print("Figures on your other characters' sheets: " .. (I.db.figureOff and "off, the class emblem stands there (/men figure on)."
        or "on (/men figure off shows the class emblem instead).") .. " Open the sheet again to see it.")
end

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
    Bst.OnChange(function() if win and win:IsShown() and I.mode == "plain" then dirty = true end end)
    ev:SetScript("OnEvent", function(_, e, arg, _, spellID)
        if e == "ADDON_LOADED" then hookFrame(); return end
        -- What is seen of creatures is noted whether the window is open or not.
        local shown = win and win:IsShown()
        if e == "PLAYER_TARGET_CHANGED" then
            -- (Showing a creature, or someone out of reach: it follows your target.)
            if shown and I.mode == "plain" then
                if UnitExists("target") then open("target", "plain") else win:Hide() end
            end
            return
        elseif e == "LOOT_OPENED" or e == "UNIT_SPELLCAST_START" or e == "UNIT_SPELLCAST_CHANNEL_START"
            or e == "UNIT_HEALTH" then
            return -- (the bestiary notes these, and says when a record changed: below)
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
        if not tf or InCombatLockdown() or db.button == false then return end
        -- A small round button with a magnifying glass (it was a pill with
        -- the word).
        local b = CreateFrame("Button", nil, tf)
        b:SetSize(22, 22)
        local ring = b:CreateTexture(nil, "BACKGROUND")
        ring:SetTexture(MEDIA .. "circle.tga")
        ring:SetAllPoints()
        ring:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
        local fill = b:CreateTexture(nil, "BORDER")
        fill:SetTexture(MEDIA .. "circle.tga")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetVertexColor(0.06, 0.06, 0.07, 1)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(15, 15)
        icon:SetPoint("CENTER")
        -- (A new file: until the game has been restarted, the character icon.)
        if icon:SetTexture(MEDIA .. "micro_inspect.tga") == false then icon:SetTexture(MEDIA .. "micro_character.tga") end
        icon:SetVertexColor(DIM[1], DIM[2], DIM[3], 1)
        b:SetScript("OnEnter", function(self)
            icon:SetVertexColor(T.text[1], T.text[2], T.text[3], 1)
            fill:SetVertexColor(0.13, 0.13, 0.15, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Inspect", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            icon:SetVertexColor(DIM[1], DIM[2], DIM[3], 1)
            fill:SetVertexColor(0.06, 0.06, 0.07, 1)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function() I:Open() end)
        -- Where: under the bar, beside the portrait that hangs from its
        -- middle, on the side the buffs do not run to (above the bar is the
        -- cast bar, at its ends the power orb and the target's target).
        -- The plain target frame has no hanging portrait: under its left end.
        local function seat()
            pcall(function()
                local hp, av = tf.healthPill, tf.avatar
                b:ClearAllPoints()
                if UFm.targetStrip and hp and av and av.D then
                    local x = av.D / 2 + 6
                    if UFm.targetAurasRight then b:SetPoint("LEFT", hp, "BOTTOM", x, -19)
                    else b:SetPoint("RIGHT", hp, "BOTTOM", -x, -19) end
                else
                    b:SetPoint("TOPLEFT", tf, "BOTTOMLEFT", 14, -4)
                end
            end)
        end
        b:SetScript("OnShow", seat)
        seat()
        b:SetFrameLevel(tf:GetFrameLevel() + 5)
        I.button = b
    end)
end
