local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Character window: Meniscus's own replacement for Blizzard's character
-- screen (Character, Reputation and Skills tabs). Opening the character
-- screen any normal way (C / U / K keys, micro menu) opens this instead.
-- Other Blizzard tabs (honor, pet, currency) still open Blizzard's window, and
-- `/men blizzchar` opens Blizzard's character screen on demand.
--
--   header   name (class color), "Level 60 Race Class · Guild", item level pill
--   gear     rounded tiles (quality ring, item level, durability bar,
--            cooldowns) around a drag-to-rotate model on a soft spotlight
--   stats    attribute tiles + resistance chips + collapsible stat sections (buffed values
--            green, debuffed red)
--   rep      pill bars colored by standing, collapsible headers, click to watch
--   skills   pill bars with rank / max

local C = ns:NewModule("Character", { enabled = true, collapsed = {} })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
-- Header band (ns.SHELL_H), then tabs, a hairline, and the pages.
local TABS_Y = (ns.SHELL_H or 92) + 12
local PAGE_TOP = TABS_Y + 38
local W, H = 720, 480 - 96 + PAGE_TOP
local TILE, GAP = 38, 6
local FILL = { 0.06, 0.06, 0.07, 0.97 }
local CARD = { 0.10, 0.10, 0.115, 0.9 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local PILL_OFF = { 0.13, 0.13, 0.15, 0.95 }
local PILL_HOVER = { 0.20, 0.20, 0.23, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local GREEN, RED = { 0.40, 0.85, 0.45, 1 }, { 0.95, 0.40, 0.40, 1 }

local LEFT_SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" }
local RIGHT_SLOTS = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" }
local WEAPON_SLOTS = { "MainHand", "SecondaryHand", "Ranged", "Ammo" }
local NO_ILVL = { Shirt = true, Tabard = true, Ammo = true }

local REACTION = {
    { 0.80, 0.25, 0.25 }, { 0.85, 0.35, 0.25 }, { 0.90, 0.50, 0.25 }, { 0.90, 0.80, 0.30 },
    { 0.40, 0.80, 0.40 }, { 0.30, 0.75, 0.60 }, { 0.30, 0.60, 0.95 }, { 0.70, 0.50, 1.00 },
}
local REACTION_NAME = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- ── Small helpers ─────────────────────────────────────────────────────────
local function secret(v) return issecretvalue and issecretvalue(v) end

local call = ns.Call

-- Format a number for display; secret values pass straight through (SetText
-- accepts them), nil means "don't show this row".
local function fmt(v, pattern)
    if v == nil then return nil end
    if secret(v) then return v end
    if type(v) ~= "number" then return tostring(v) end
    return pattern and string.format(pattern, v) or tostring(v)
end

local function plain(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == nil or secret(v) or type(v) ~= "number" then return false end
    end
    return true
end

local function buffColor(pos, neg)
    if plain(neg) and neg < 0 then return RED end
    if plain(pos) and pos > 0 then return GREEN end
end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local function circle(parent, size, layer, sub)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(size, size)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetSize(size, size)
    t:AddMaskTexture(mask)
    mask:SetPoint("CENTER", t, "CENTER")
    return t
end

local function itemLevel(link)
    if not link then return end
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
    local lvl = call(f, link)
    if plain(lvl) and lvl > 0 then return lvl end
    if C_Item and C_Item.GetItemInfo then
        local l = select(4, call(C_Item.GetItemInfo, link))
        if plain(l) and l > 0 then return l end
    end
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, pages, tabButtons = nil, {}, {}

local function savePos()
    local p, _, rp, x, y = win:GetPoint(1)
    C.db.pos = { p, rp, x, y }
end

local PILL_OPTS = { h = 22, pad = 28, minW = 60, dimIdle = true }
local function pillButton(parent, label, onClick)
    return ns.Pill(parent, label, onClick, PILL_OPTS)
end

local function closeButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local bg = circle(b, 20, "BACKGROUND")
    bg:SetPoint("CENTER")
    bg:SetColorTexture(0.16, 0.16, 0.18, 1)
    local lines = {}
    for i, pts in ipairs({ { -1, 1, 1, -1 }, { -1, -1, 1, 1 } }) do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetStartPoint("CENTER", b, pts[1] * 4, pts[2] * 4)
        l:SetEndPoint("CENTER", b, pts[3] * 4, pts[4] * 4)
        l:SetColorTexture(unpack(T.textDim))
        lines[i] = l
    end
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(unpack(T.accent))
        for _, l in ipairs(lines) do l:SetColorTexture(unpack(TEXT_DARK)) end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(0.16, 0.16, 0.18, 1)
        for _, l in ipairs(lines) do l:SetColorTexture(unpack(T.textDim)) end
    end)
    b:SetScript("OnClick", function() win:Hide() end)
    return b
end

-- ── Scrolling list (stats, reputation, skills) ───────────────────────────
-- Fixed pool of rows; data is a flat array of
--   { kind = "header", text, collapsed, onClick, indent }
--   { kind = "stat",   label, value, color, tooltip }
--   { kind = "bar",    label, min, max, value, text, color, onClick, tooltip, indent, active }
local function chevron(row, collapsed)
    local a, b = row.chev[1], row.chev[2]
    local x = 10
    if collapsed then
        a:SetStartPoint("LEFT", row, x - 2, 4); a:SetEndPoint("LEFT", row, x + 2, 0)
        b:SetStartPoint("LEFT", row, x + 2, 0); b:SetEndPoint("LEFT", row, x - 2, -4)
    else
        a:SetStartPoint("LEFT", row, x - 4, 2); a:SetEndPoint("LEFT", row, x, -2)
        b:SetStartPoint("LEFT", row, x, -2); b:SetEndPoint("LEFT", row, x + 4, 2)
    end
end

local function makeRow(list, i)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(list.rowH)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * list.rowH)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -(i - 1) * list.rowH)
    row:RegisterForClicks("LeftButtonUp")
    row.hl = ns.RoundedRect(row, -8, 0, 6, 1, 1, 1, 0)
    row.chev = {}
    for k = 1, 2 do
        local l = row:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetColorTexture(unpack(T.textDim))
        row.chev[k] = l
    end
    row.label = text(row, 11)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.value = text(row, 11)
    row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.value:SetJustifyH("RIGHT")
    if list.barW then
        row.bar = ns:CreatePillBar(row, list.barW, 12)
        row.bar:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.bar.text = row.bar:CreateText(9, nil, true)
        row.bar.text:SetPoint("CENTER", row.bar, "CENTER", 0, 0)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local iconMask = row:CreateMaskTexture()
    iconMask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    iconMask:SetAllPoints(row.icon)
    row.icon:AddMaskTexture(iconMask)
    row:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        if d.onClick or d.tooltip then self.hl(1, 1, 1, 0.05) end
        if d.tooltip then
            ns.TipAnchor(self)
            d.tooltip(GameTooltip)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self) self.hl(1, 1, 1, 0); GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self) if self.data and self.data.onClick then self.data.onClick() end end)
    return row
end

local function fillRow(row, d)
    row.data = d
    row.hl(1, 1, 1, 0)
    if not d then row:Hide(); return end
    row:Show()
    local indent = d.indent or 0
    row.label:ClearAllPoints()
    if row.bar then row.bar:Hide() end
    row.value:Hide()
    row.chev[1]:Hide(); row.chev[2]:Hide()
    row.icon:Hide()
    if d.icon and d.kind ~= "header" then
        row.icon:SetTexture(d.icon)
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", 20 + indent, 0)
        row.icon:Show()
        indent = indent + 22
    end
    if d.kind == "header" then
        ns:SetFont(row.label, 11, "", true)
        row.label:SetTextColor(unpack(T.text))
        row.label:SetPoint("LEFT", row, "LEFT", 20 + indent, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.label:SetText(d.text)
        if d.onClick then
            chevron(row, d.collapsed)
            row.chev[1]:Show(); row.chev[2]:Show()
        end
    elseif d.kind == "stat" then
        ns:SetFont(row.label, 11, "")
        row.label:SetTextColor(unpack(d.labelColor or T.textDim))
        row.label:SetPoint("LEFT", row, "LEFT", 20 + indent, 0)
        row.label:SetText(d.label)
        row.value:Show()
        row.value:SetText(d.value)
        row.value:SetTextColor(unpack(d.color or T.text))
    else -- bar
        ns:SetFont(row.label, 11, "", d.active)
        row.label:SetTextColor(unpack(d.active and T.accent or T.text))
        row.label:SetPoint("LEFT", row, "LEFT", 20 + indent, 0)
        row.label:SetPoint("RIGHT", row.bar, "LEFT", -10, 0)
        row.label:SetText(d.label)
        row.bar:Show()
        row.bar.bar:SetMinMaxValues(d.min or 0, d.max or 1)
        row.bar.bar:SetValue(d.value or 0)
        local c = d.color or T.accent
        row.bar.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
        row.bar:SetRingColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
        row.bar.text:SetText(d.text or "")
    end
end

local function makeList(parent, w, h, rowH, barW)
    local L = CreateFrame("Frame", nil, parent)
    L:SetSize(w, h)
    L.rowH, L.barW, L.rows, L.data, L.offset = rowH, barW, {}, {}, 0
    L.visible = math.floor(h / rowH)
    for i = 1, L.visible do L.rows[i] = makeRow(L, i) end
    L.thumb = L:CreateTexture(nil, "OVERLAY")
    L.thumb:SetWidth(3)
    L.thumb:SetColorTexture(T.border[1] + 0.1, T.border[2] + 0.1, T.border[3] + 0.1, 1)
    L.empty = text(L, 11, false, T.textDim)
    L.empty:SetPoint("TOP", L, "TOP", 0, -40)
    L.empty:SetText("Nothing to show yet.")
    L:EnableMouseWheel(true)
    L:SetScript("OnMouseWheel", function(self, delta) self:SetOffset(self.offset - delta * 3) end)
    function L:SetOffset(o)
        self.empty:SetShown(#self.data == 0)
        local maxO = math.max(0, #self.data - self.visible)
        self.offset = math.max(0, math.min(o, maxO))
        for i, row in ipairs(self.rows) do fillRow(row, self.data[i + self.offset]) end
        if #self.data > self.visible then
            local th = h * self.visible / #self.data
            self.thumb:SetHeight(th)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(h - th) * self.offset / maxO)
            self.thumb:Show()
        else
            self.thumb:Hide()
        end
    end
    function L:SetData(data) self.data = data; self:SetOffset(self.offset) end
    return L
end

-- ── Gear tiles ────────────────────────────────────────────────────────────
local tiles = {}

local function updateTile(b)
    local id = b.slot
    local tex = GetInventoryItemTexture("player", id)
    if tex then
        b.icon:SetTexture(tex)
        b.icon:SetDesaturated(IsInventoryItemLocked and IsInventoryItemLocked(id) or false)
        b.icon:SetAlpha(1)
    else
        b.icon:SetTexture(b.empty)
        b.icon:SetDesaturated(true)
        b.icon:SetAlpha(0.3)
    end
    local q = tex and GetInventoryItemQuality("player", id)
    local c = plain(q) and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then b.ring(c.r, c.g, c.b, 1) else b.ring(T.border[1], T.border[2], T.border[3], 1) end

    b.lvl = tex and not NO_ILVL[b.slotName] and itemLevel(GetInventoryItemLink("player", id)) or nil
    b.ilvl:SetText(b.lvl and string.format("%d", b.lvl) or "")

    local cur, max = call(GetInventoryItemDurability, id)
    local pct = tex and plain(cur, max) and max > 0 and cur / max
    if pct and pct < 0.5 then
        b.duraBg:Show(); b.dura:Show()
        b.dura:SetWidth(math.max(1, (TILE - 8) * pct))
        if pct < 0.2 then b.dura:SetColorTexture(unpack(RED)) else b.dura:SetColorTexture(0.95, 0.80, 0.30, 1) end
    else
        b.duraBg:Hide(); b.dura:Hide()
    end

    if b.slotName == "Ammo" then
        -- Only real ammunition has a count: an empty slot, or one holding
        -- something that isn't a projectile, still reports 1.
        local item = tex and call(GetInventoryItemID, "player", id)
        local class = plain(item) and item > 0 and C_Item and C_Item.GetItemInfoInstant
            and select(6, call(C_Item.GetItemInfoInstant, item))
        local n = class == ((Enum and Enum.ItemClass and Enum.ItemClass.Projectile) or 6)
            and call(GetInventoryItemCount, "player", id)
        b.count:SetText(plain(n) and n > 0 and n or "")
    end

    local start, dur, enable = call(GetInventoryItemCooldown, "player", id)
    if tex and plain(start, dur) and dur > 0 and enable ~= 0 and enable ~= false then
        b.cd:SetCooldown(start, dur)
    else
        b.cd:Clear()
    end
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

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(mask)
    pcall(b.cd.SetDrawEdge, b.cd, false)

    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(b.cd:GetFrameLevel() + 1)
    b.ilvl = over:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.ilvl, 9, "OUTLINE", true)
    b.ilvl:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -3)
    b.count = over:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.count, 9, "OUTLINE", true)
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    b.duraBg = over:CreateTexture(nil, "OVERLAY", nil, 1)
    b.duraBg:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 4)
    b.duraBg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
    b.duraBg:SetHeight(3)
    b.duraBg:SetColorTexture(0, 0, 0, 0.8)
    b.dura = over:CreateTexture(nil, "OVERLAY", nil, 2)
    b.dura:SetPoint("BOTTOMLEFT", b.duraBg, "BOTTOMLEFT")
    b.dura:SetHeight(3)

    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self)
        if IsShiftKeyDown() or IsControlKeyDown() then
            local link = GetInventoryItemLink("player", self.slot)
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        elseif SpellIsTargeting and SpellIsTargeting() then
            -- The cursor is waiting for a gear target and this slot isn't a
            -- valid one (valid slots are covered by a secure button, see
            -- OnInit). Picking the item up here would be the blocked action.
            return
        else
            PickupInventoryItem(self.slot)
        end
    end)
    b:SetScript("OnDragStart", function(self) PickupInventoryItem(self.slot) end)
    b:SetScript("OnReceiveDrag", function(self) PickupInventoryItem(self.slot) end)
    -- This IS the equipped item, so there is nothing to compare it with: the
    -- game's comparison tooltips (which it adds beside any item tooltip
    -- when "always compare" is on, showing the same item twice here) are
    -- put away for as long as the mouse is on the tile.
    local function noCompare()
        for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3" }) do
            local st = _G[name]
            if st and st:IsShown() then st:Hide() end
        end
    end
    b:SetScript("OnEnter", function(self)
        ns.TipAnchor(self)
        local has = GameTooltip:SetInventoryItem("player", self.slot)
        if not has then GameTooltip:SetText(_G[self.slotName:upper() .. "SLOT"] or self.slotName) end
        GameTooltip:Show()
        noCompare()
        self:SetScript("OnUpdate", noCompare)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
    table.insert(tiles, b)
    return b
end

-- ── Header ────────────────────────────────────────────────────────────────
-- Full character name. Forever characters can carry a second name; it may
-- come back as UnitName's second value or in "Name-Second" form, the same
-- slots realm names use, so a part that matches the realm is dropped.
function C.FullName(unit)
    local name, extra = UnitName(unit)
    if secret(name) or not name then return name end
    if not extra or secret(extra) or extra == "" then
        local full = call(GetUnitName, unit, true)
        if full and not secret(full) then
            local a, b = full:match("^([^%-]+)%-(.+)$")
            if a then name, extra = a, b end
        end
    end
    local realms = { (call(GetRealmName)), (call(GetNormalizedRealmName)) }
    if extra and not secret(extra) and extra ~= "" then
        for _, r in ipairs(realms) do
            if r and not secret(r) and (extra == r or extra == r:gsub("%s", "")) then extra = nil; break end
        end
    end
    if extra and not secret(extra) and extra ~= "" then return name .. " " .. extra end
    return name
end

-- The header's 3D head is only re-set when its unit changes or the window
-- reopens (re-setting on every refresh would restart the model).
local function headFor(unit)
    if C.headUnit ~= unit or C.headStale then
        C.headUnit, C.headStale = unit, false
        win.shell:SetUnit(unit)
    end
end

local function updateHeader()
    local sh = win.shell
    -- Pet tab: the header describes the pet instead.
    if C.tab == "pet" and UnitExists("pet") then
        sh:SetTitle(UnitName("pet"))
        local lvl, fam = UnitLevel("pet"), call(UnitCreatureFamily, "pet")
        if lvl and not secret(lvl) then
            sh:SetSubtitle(string.format("Level %d %s", lvl, (fam and not secret(fam)) and fam or ""))
        else
            sh:SetSubtitle("")
        end
        sh:SetChip(nil)
        sh:SetRing({ 0.55, 0.75, 0.45 })
        headFor("pet")
        return
    end
    local _, token = UnitClass("player")
    local cc = token and not secret(token) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if cc then sh:SetTitle(C.FullName("player"), cc.r, cc.g, cc.b) else sh:SetTitle(C.FullName("player")) end
    sh:SetRing(cc and { cc.r, cc.g, cc.b } or nil)
    headFor("player")

    local parts = {}
    local lvl = UnitLevel("player")
    local race = UnitRace("player")
    local class = UnitClass("player")
    if lvl and not secret(lvl) then
        table.insert(parts, string.format("Level %d %s %s", lvl, race or "", class or ""))
    end
    local guild = call(GetGuildInfo, "player")
    if guild and not secret(guild) then table.insert(parts, guild) end
    sh:SetSubtitle(table.concat(parts, "  ·  "))

    local sum, n = 0, 0
    for _, b in ipairs(tiles) do
        if b.lvl then sum, n = sum + b.lvl, n + 1 end
    end
    if n > 0 then
        sh:SetChip(string.format("Item level %d", math.floor(sum / n + 0.5)), T.accent)
    else
        sh:SetChip(nil)
    end
end

-- ── Stats ─────────────────────────────────────────────────────────────────
local function statsData(unit)
    unit = unit or "player"
    local pet = unit == "pet"
    local d = {}
    local function section(key, title, rows)
        if #rows == 0 then return end
        key = (pet and "pet_" or "") .. key
        local col = C.db.collapsed[key]
        table.insert(d, { kind = "header", text = title, collapsed = col,
            onClick = function() C.db.collapsed[key] = not col; C:Refresh() end })
        if not col then for _, r in ipairs(rows) do table.insert(d, r) end end
    end
    local function stat(rows, label, value, color)
        if value ~= nil then table.insert(rows, { kind = "stat", label = label, value = value, color = color }) end
    end
    local function total(a, b, c)
        if plain(a, b, c) then return a + b + c end
        return a
    end
    local function pct(v) if plain(v) then return string.format("%.2f%%", v) end return fmt(v) end
    local function best(fn)
        local m
        for school = 2, 7 do
            local v = call(fn, school)
            if plain(v) and (not m or v > m) then m = v end
        end
        return m
    end

    -- (The five attributes are tiles across the top of the card, not rows
    -- here: see ATTRS / updateAttrs.)
    local rows = {}
    local base, pos, neg = call(UnitAttackPower, unit)
    stat(rows, "Attack power", fmt(total(base, pos, neg), "%d"), buffColor(pos, neg))
    local lo, hi = call(UnitDamage, unit)
    if plain(lo, hi) then stat(rows, "Damage", string.format("%d - %d", lo, hi)) end
    local speed = call(UnitAttackSpeed, unit)
    stat(rows, "Speed", fmt(speed, "%.2f"))
    if not pet then
        stat(rows, "Crit chance", pct(call(GetCritChance)))
        local hit = call(GetHitModifier)
        if plain(hit) and hit > 0 then stat(rows, "Hit", string.format("+%d%%", hit)) end
    end
    section("melee", "Melee", rows)

    if pet then
        rows = {}
        local _, armor, _, aPos, aNeg = call(UnitArmor, unit)
        stat(rows, "Armor", fmt(armor, "%d"), buffColor(aPos, aNeg))
        section("defense", "Defense", rows)
        return d
    end

    rows = {}
    local rSpeed, rLo, rHi = call(UnitRangedDamage, "player")
    if plain(rSpeed) and rSpeed > 0 then
        local rb, rp, rn = call(UnitRangedAttackPower, "player")
        stat(rows, "Attack power", fmt(total(rb, rp, rn), "%d"), buffColor(rp, rn))
        if plain(rLo, rHi) then stat(rows, "Damage", string.format("%d - %d", rLo, rHi)) end
        stat(rows, "Speed", fmt(rSpeed, "%.2f"))
        stat(rows, "Crit chance", pct(call(GetRangedCritChance)))
    end
    section("ranged", "Ranged", rows)

    rows = {}
    local maxMana = call(UnitPowerMax, "player", 0)
    if not plain(maxMana) or maxMana > 0 then
        stat(rows, "Bonus damage", fmt(best(GetSpellBonusDamage), "%d"))
        stat(rows, "Bonus healing", fmt(call(GetSpellBonusHealing), "%d"))
        local sc = best(GetSpellCritChance)
        if sc then stat(rows, "Crit chance", pct(sc)) end
        local sh = call(GetSpellHitModifier)
        if plain(sh) and sh > 0 then stat(rows, "Hit", string.format("+%d%%", sh)) end
        local regen = call(GetManaRegen)
        if plain(regen) then stat(rows, "Mana regen", string.format("%d / 5s", regen * 5)) end
    end
    section("spell", "Spell", rows)

    rows = {}
    local _, armor, _, aPos, aNeg = call(UnitArmor, "player")
    stat(rows, "Armor", fmt(armor, "%d"), buffColor(aPos, aNeg))
    local dBase, dMod = call(UnitDefense, "player")
    if plain(dBase) then stat(rows, "Defense", string.format("%d", dBase + (plain(dMod) and dMod or 0))) end
    stat(rows, "Dodge", pct(call(GetDodgeChance)))
    local parry, block = call(GetParryChance), call(GetBlockChance)
    if not plain(parry) or parry > 0 then stat(rows, "Parry", pct(parry)) end
    if not plain(block) or block > 0 then stat(rows, "Block", pct(block)) end
    section("defense", "Defense", rows)
    return d
end

local RESISTS = {
    { 2, "Fire", { 1.00, 0.50, 0.25 } }, { 3, "Nature", { 0.45, 0.85, 0.35 } },
    { 4, "Frost", { 0.45, 0.75, 1.00 } }, { 5, "Shadow", { 0.68, 0.48, 0.95 } },
    { 6, "Arcane", { 0.95, 0.88, 0.55 } },
}

-- The five primary attributes, as a row of tiles across the top of the stats
-- card: a short colored label over the buffed value (green when raised by
-- buffs or gear effects, red when lowered). Hover for the breakdown.
local ATTRS = {
    { "STR", SPELL_STAT1_NAME or "Strength",  { 0.92, 0.48, 0.38 } },
    { "AGI", SPELL_STAT2_NAME or "Agility",   { 0.58, 0.85, 0.42 } },
    { "STA", SPELL_STAT3_NAME or "Stamina",   { 0.95, 0.72, 0.32 } },
    { "INT", SPELL_STAT4_NAME or "Intellect", { 0.42, 0.66, 1.00 } },
    { "SPI", SPELL_STAT5_NAME or "Spirit",    { 0.76, 0.62, 0.96 } },
}

-- What an attribute is worth to this character right now, as tooltip lines:
-- { label, value } pairs. Everything comes from the client's own functions
-- (they already account for class), and a line only appears when its
-- function exists here and returns a plain positive number, so a class that
-- gets nothing from a stat simply shows fewer lines.
local function attrEffects(i, unit, eff)
    local out = {}
    if not plain(eff) then return out end
    local function add(label, v, pattern)
        if plain(v) and v > 0.005 then out[#out + 1] = { label, string.format(pattern, v) } end
    end
    local player = unit == "player"
    local function ap()
        if player and GetAttackPowerForStat then return call(GetAttackPowerForStat, i, eff) end
    end
    if i == 1 then -- Strength
        add("Attack power", ap(), "+%d")
    elseif i == 2 then -- Agility
        add("Attack power", ap(), "+%d")
        if GetCritChanceFromAgility then add("Crit chance", call(GetCritChanceFromAgility, unit), "+%.2f%%") end
        if type(ARMOR_PER_AGILITY) == "number" then add("Armor", eff * ARMOR_PER_AGILITY, "+%d") end
    elseif i == 3 then -- Stamina
        local per = type(HEALTH_PER_STAMINA) == "number" and HEALTH_PER_STAMINA
            or (UnitHPPerStamina and call(UnitHPPerStamina, unit))
        if plain(per) then
            -- (The first 20 points give 1 health each on classic rules.)
            local base = type(HEALTH_PER_STAMINA) == "number" and math.min(20, eff) or 0
            add("Health", base + (eff - base) * per, "+%d")
        end
    elseif i == 4 then -- Intellect
        local hasMana = call(UnitPowerMax, unit, 0)
        if type(MANA_PER_INTELLECT) == "number" and plain(hasMana) and hasMana > 0 then
            local base = math.min(20, eff)
            add("Mana", base + (eff - base) * MANA_PER_INTELLECT, "+%d")
        end
        if GetSpellCritChanceFromIntellect then
            add("Spell crit chance", call(GetSpellCritChanceFromIntellect, unit), "+%.2f%%")
        end
    elseif i == 5 then -- Spirit
        if GetUnitHealthRegenRateFromSpirit then
            add("Health regen out of combat", call(GetUnitHealthRegenRateFromSpirit, unit), "%d per tick")
        end
        if GetUnitManaRegenRateFromSpirit then
            local m = call(GetUnitManaRegenRateFromSpirit, unit)
            if plain(m) then add("Mana regen while not casting", m * 5, "%d per 5s") end
        end
    end
    return out
end

-- Returns whether the unit reports any attributes (some pets, demons on
-- this client, report none: their tiles are hidden).
local function updateAttrs(card, unit)
    local any = false
    for i, tile in ipairs(card.attrs) do
        local base, eff, pos, neg = call(UnitStat, unit or "player", i)
        tile.base, tile.eff, tile.pos, tile.neg = base, eff, pos, neg
        tile.unit, tile.index = unit or "player", i
        tile.value:SetText(fmt(eff, "%d") or "0")
        local col = buffColor(pos, neg) or T.text
        tile.value:SetTextColor(col[1], col[2], col[3])
        if not plain(eff) or eff ~= 0 then any = true end
    end
    local show = any or (unit or "player") == "player"
    for _, tile in ipairs(card.attrs) do tile:SetShown(show) end
    return any
end

local function updateResists(chips, unit)
    for _, chip in ipairs(chips) do
        local _, totalR = call(UnitResistance, unit or "player", chip.school)
        chip.value = totalR
        chip.fs:SetText(fmt(totalR, "%d") or "0")
    end
end

-- ── Reputation ────────────────────────────────────────────────────────────
local function factionAt(i)
    local R = C_Reputation
    if R and R.GetFactionDataByIndex then return call(R.GetFactionDataByIndex, i) end
    local name, desc, standing, bMin, bMax, val, _, _, isHeader, isCollapsed, hasRep, isWatched, isChild =
        call(GetFactionInfo, i)
    if not name then return end
    return { name = name, description = desc, reaction = standing, currentReactionThreshold = bMin,
             nextReactionThreshold = bMax, currentStanding = val, isHeader = isHeader,
             isCollapsed = isCollapsed, isHeaderWithRep = hasRep, isWatched = isWatched, isChild = isChild }
end

local function toggleFactionHeader(i, collapsed)
    local R = C_Reputation or {}
    local fn = collapsed and (R.ExpandFactionHeader or _G.ExpandFactionHeader)
        or (R.CollapseFactionHeader or _G.CollapseFactionHeader)
    call(fn, i)
    C:Refresh()
end

local function watchFaction(i, watched)
    local R = C_Reputation or {}
    local fn = R.SetWatchedFactionByIndex or _G.SetWatchedFactionIndex
    call(fn, watched and 0 or i)
    C:Refresh()
end

local function repData()
    local d = {}
    local R = C_Reputation
    local n = call(R and R.GetNumFactions or _G.GetNumFactions) or 0
    for i = 1, n do
        local f = factionAt(i)
        if f and f.name then
            local indent = f.isChild and 12 or 0
            if f.isHeader and not f.isHeaderWithRep then
                table.insert(d, { kind = "header", text = f.name, collapsed = f.isCollapsed, indent = indent,
                    onClick = function() toggleFactionHeader(i, f.isCollapsed) end })
            else
                local r = f.reaction or 4
                local lo, hi, cur = f.currentReactionThreshold or 0, f.nextReactionThreshold or 1, f.currentStanding or 0
                local label = _G["FACTION_STANDING_LABEL" .. r] or REACTION_NAME[r] or ""
                local span, into = hi - lo, cur - lo
                table.insert(d, {
                    kind = "bar", label = f.name, min = 0, max = math.max(span, 1), value = into,
                    text = label .. "   " .. into .. " / " .. span,
                    color = REACTION[r] or REACTION[4], active = f.isWatched, indent = f.isHeader and indent or indent + 12,
                    onClick = function() watchFaction(i, f.isWatched) end,
                    tooltip = function(tip)
                        tip:SetText(f.name, 1, 1, 1)
                        if f.description and f.description ~= "" then tip:AddLine(f.description, 0.8, 0.8, 0.8, true) end
                        tip:AddLine(f.isWatched and "Click to stop tracking" or "Click to track on the XP bar", 0.5, 0.75, 1)
                    end,
                })
            end
        end
    end
    return d
end

-- ── Skills ────────────────────────────────────────────────────────────────
-- Classic skill lines when the client has them; otherwise professions.
local SKILL_COLOR = { 0.35, 0.62, 0.90 }

-- Skill lines: the classic globals, or Forever's C_SkillInfo (same calls in a
-- namespace; it may return a table instead of separate values).
local function skillAPI()
    local S = C_SkillInfo
    if S and S.GetNumSkillLines then
        return S.GetNumSkillLines, S.GetSkillLineInfo, S.CollapseSkillHeader, S.ExpandSkillHeader
    end
    if _G.GetNumSkillLines then
        return GetNumSkillLines, GetSkillLineInfo, _G.CollapseSkillHeader, _G.ExpandSkillHeader
    end
end

local function skillLine(getInfo, i)
    local a, b, c, d, e, f, g, h, i2, j, k, l, m = call(getInfo, i)
    if type(a) ~= "table" then return a, b, c, d, e, f, g, h, i2, j, k, l, m end
    local t = a
    local name = t.skillName or t.name
    if not name and not C.loggedSkillKeys then
        C.loggedSkillKeys = true
        local keys = {}
        for key, v in pairs(t) do table.insert(keys, tostring(key) .. "=" .. tostring(v)) end
        MinimalUIDB.skillkeys = keys
    end
    return name, t.isHeader or t.header, t.isExpanded or t.expanded,
        t.skillRank or t.rank or t.currentRank, t.numTempPoints, t.skillModifier or t.modifier,
        t.skillMaxRank or t.maxRank, nil, nil, nil, nil, nil, t.skillDescription or t.description
end

local function skillsData()
    local d = {}
    local getNum, getInfo, collapse, expand = skillAPI()
    -- One-time record of what the skill API actually returns (saved on reload).
    if getNum and not C.skillDiag then
        C.skillDiag = true
        local function ser(...)
            local t = {}
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                if type(v) == "table" then
                    local kv = {}
                    for k, x in pairs(v) do kv[#kv + 1] = tostring(k) .. "=" .. tostring(x) end
                    v = "{" .. table.concat(kv, ", ") .. "}"
                end
                t[i] = tostring(v)
            end
            return table.concat(t, " | ")
        end
        local diag = { "num: " .. ser(pcall(getNum)) }
        for i = 0, 4 do table.insert(diag, "info" .. i .. ": " .. ser(pcall(getInfo, i))) end
        local S = C_SkillInfo
        if S and S.GetSkillLineInfoByID then
            for _, id in ipairs({ 95, 162, 136, 173, 228, 109 }) do
                table.insert(diag, "byID " .. id .. ": " .. ser(pcall(S.GetSkillLineInfoByID, id)))
            end
        end
        if S and S.GetSelectedSkill then table.insert(diag, "selected: " .. ser(pcall(S.GetSelectedSkill))) end
        MinimalUIDB.skilldiag = diag
    end
    if getNum then
        local n = call(getNum) or 0
        local header, seen = nil, {}
        for i = 1, (plain(n) and n or 0) do
            local name, isHeader, _, rank, _, mod, maxRank, _, _, _, _, _, desc = skillLine(getInfo, i)
            if name then
                if isHeader then
                    -- Whether a header is open is read from the list itself
                    -- (rows follow it) rather than the API's flag, which
                    -- doesn't come back in a form we can read here.
                    header = { kind = "header", text = name, collapsed = true, index = i }
                    local h = header
                    h.onClick = function()
                        call(h.collapsed and expand or collapse, h.index)
                        C:Refresh()
                    end
                    seen = {}
                    table.insert(d, h)
                elseif not seen[name] then -- the list repeats some professions
                    seen[name] = true
                    if header then header.collapsed = false end
                    local tip = desc and desc ~= "" and function(t)
                        t:SetText(name, 1, 1, 1); t:AddLine(desc, 0.8, 0.8, 0.8, true)
                    end or nil
                    if plain(maxRank) and maxRank <= 1 then
                        -- Known/not-known skills (specs, armor): no bar.
                        table.insert(d, { kind = "stat", label = name, value = "Known", color = T.textDim,
                            labelColor = T.text, indent = 12, tooltip = tip })
                    else
                        local t = tostring(rank or 0) .. " / " .. tostring(maxRank or 0)
                        if plain(mod) and mod ~= 0 then t = t .. string.format("  (%+d)", mod) end
                        table.insert(d, { kind = "bar", label = name, min = 0,
                            max = plain(maxRank) and math.max(maxRank, 1) or 1,
                            value = rank or 0, text = t, color = SKILL_COLOR, indent = 12, tooltip = tip })
                    end
                end
            end
        end
        if #d > 0 then return d end
    end

    if not _G.GetProfessions then return d end
    local p1, p2, arch, fish, cook, extra = call(GetProfessions)
    local function prof(index, rows)
        if not index then return end
        local name, icon, rank, maxRank, _, _, _, mod = call(GetProfessionInfo, index)
        if not name then return end
        local t = tostring(rank) .. " / " .. tostring(maxRank)
        if plain(mod) and mod > 0 then t = t .. string.format("  (+%d)", mod) end
        table.insert(rows, { kind = "bar", label = name, icon = icon, min = 0,
            max = plain(maxRank) and math.max(maxRank, 1) or 1, value = rank or 0, text = t, color = SKILL_COLOR })
    end
    local function group(title, list)
        local rows = {}
        for _, i in ipairs(list) do prof(i, rows) end
        if #rows == 0 then return end
        table.insert(d, { kind = "header", text = title })
        for _, r in ipairs(rows) do table.insert(d, r) end
    end
    group(PROFESSIONS_PRIMARY or "Professions", { p1 or false, p2 or false })
    group("Secondary skills", { cook or false, fish or false, arch or false, extra or false })
    return d
end

-- ── Currency ──────────────────────────────────────────────────────────────
local function currencyData()
    local d, CI = {}, C_CurrencyInfo
    local n = CI and call(CI.GetCurrencyListSize) or 0
    if not plain(n) then return d end
    for i = 1, n do
        local c = call(CI.GetCurrencyListInfo, i)
        if c and c.name then
            if c.isHeader then
                table.insert(d, { kind = "header", text = c.name, collapsed = not c.isHeaderExpanded,
                    onClick = function() call(CI.ExpandCurrencyList, i, not c.isHeaderExpanded); C:Refresh() end })
            else
                local v = fmt(c.quantity, "%d") or "0"
                if plain(c.quantity, c.maxQuantity) and c.maxQuantity > 0 then
                    v = string.format("%d / %d", c.quantity, c.maxQuantity)
                end
                table.insert(d, { kind = "stat", label = c.name, value = v, icon = c.iconFileID, indent = 12,
                    tooltip = function(tip)
                        if tip.SetCurrencyToken then tip:SetCurrencyToken(i) else tip:SetText(c.name) end
                    end })
            end
        end
    end
    return d
end

-- ── Honor ─────────────────────────────────────────────────────────────────
-- Classic honor stats; return shapes vary by client, so values are read
-- loosely: first = honorable kills, later numbers = honor.
local HONOR_COLOR = { 0.88, 0.72, 0.36 }

local function honorData()
    local d = {}
    local function sec(title, rows)
        if #rows == 0 then return end
        table.insert(d, { kind = "header", text = title })
        for _, r in ipairs(rows) do table.insert(d, r) end
    end
    local function st(rows, label, v)
        local s = fmt(v, "%d")
        if s ~= nil then table.insert(rows, { kind = "stat", label = label, value = s }) end
    end
    local function vals(fn)
        local t = { call(fn) }
        return t, table.maxn(t)
    end

    local rows = {}
    local rank = call(UnitPVPRank, "player")
    if plain(rank) and rank > 0 then
        local rname, rnum = call(GetPVPRankInfo, rank)
        local prog = call(GetPVPRankProgress)
        if rname and plain(prog) then
            table.insert(rows, { kind = "bar", label = rname, min = 0, max = 1, value = prog, color = HONOR_COLOR,
                text = string.format("Rank %d   %d%%", plain(rnum) and rnum or 0, prog * 100) })
        elseif rname then
            st(rows, rname, rnum)
        end
    end
    sec("Rank", rows)

    for _, p in ipairs({ { "Today", _G.GetPVPSessionStats }, { "Yesterday", _G.GetPVPYesterdayStats },
                         { "This week", _G.GetPVPThisWeekStats }, { "Last week", _G.GetPVPLastWeekStats } }) do
        rows = {}
        local t, n = vals(p[2])
        st(rows, "Honorable kills", t[1])
        if n >= 2 then st(rows, "Honor", p[1] == "Last week" and n >= 4 and t[3] or t[n]) end
        sec(p[1], rows)
    end

    rows = {}
    local t, n = vals(_G.GetPVPLifetimeStats)
    st(rows, "Honorable kills", t[1])
    if n >= 3 and plain(t[2]) and t[2] > 0 then st(rows, "Dishonorable kills", t[2]) end
    local highest = n >= 2 and t[n]
    if plain(highest) and highest > 0 then
        local hname = call(GetPVPRankInfo, highest)
        if hname then table.insert(rows, { kind = "stat", label = "Highest rank", value = hname }) end
    end
    sec("Lifetime", rows)
    return d
end

-- ── Pet ───────────────────────────────────────────────────────────────────
local HAPPINESS = { { "Unhappy", RED }, { "Content", { 0.95, 0.80, 0.30, 1 } }, { "Happy", GREEN } }

local function updatePet(page)
    if not UnitExists("pet") then return end
    -- Re-set the model only when the pet changes (or the page is reopened),
    -- not on every stat/aura refresh.
    local guid = UnitGUID("pet")
    if secret(guid) or guid ~= page.guid or not page.model:IsVisible() or page.stale then
        page.guid, page.stale = guid, false
        page.model:SetUnit("pet")
        page.model:SetFacing(page.model.facing)
        -- Pull the camera back a little: pets (and their effects, like an
        -- imp's flames) are bulkier than characters and clipped at the edges.
        pcall(page.model.SetCamDistanceScale, page.model, 1.25)
    end
    updateResists(page.card.resists, "pet")
    pcall(updateAttrs, page.card, "pet")
    local ok, d = pcall(statsData, "pet")
    if ok then page.card.list:SetData(d) end

    local cur, max = call(GetPetExperience)
    if plain(cur, max) and max > 0 then
        page.xp.bar:SetMinMaxValues(0, max)
        page.xp.bar:SetValue(cur)
        page.xp.label:SetText(string.format("Experience   %d / %d", cur, max))
        page.xp:Show()
    else
        page.xp:Hide()
    end

    local parts = {}
    local happy, dmg = call(GetPetHappiness)
    local h = plain(happy) and HAPPINESS[happy]
    if h then
        local c = h[2]
        table.insert(parts, string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, h[1]))
        if plain(dmg) then table.insert(parts, string.format("%d%% damage", dmg)) end
    end
    local loyalty = call(GetPetLoyalty)
    if loyalty and not secret(loyalty) then table.insert(parts, loyalty) end
    local tp = call(GetPetTrainingPoints)
    if plain(tp) then table.insert(parts, string.format("%d training points", tp)) end
    page.status:SetText(table.concat(parts, "   ·   "))
end

-- ── Build ─────────────────────────────────────────────────────────────────
-- kw: words that identify the matching tab on Blizzard's character screen.
local TABS = {
    { key = "gear", label = "Character", kw = { "character" } },
    { key = "pet", label = "Pet", kw = { "pet" },
      available = function() return (call(HasPetUI)) and UnitExists("pet") and true or false end },
    { key = "rep", label = "Reputation", kw = { "reputation" } },
    { key = "skills", label = "Skills", kw = { "skill", "profession" },
      available = function() return skillAPI() ~= nil or _G.GetProfessions ~= nil end },
    { key = "currency", label = "Currency", kw = { "currency", "token" },
      available = function()
          local n = C_CurrencyInfo and call(C_CurrencyInfo.GetCurrencyListSize)
          return plain(n) and n > 0
      end },
    { key = "honor", label = "Honor", kw = { "honor", "pvp" },
      available = function() return _G.GetPVPLifetimeStats ~= nil or _G.UnitPVPRank ~= nil end },
}
local TAB_BY_KEY = {}
for _, t in ipairs(TABS) do TAB_BY_KEY[t.key] = t end

local function tabAvailable(key)
    local t = TAB_BY_KEY[key]
    return t and (not t.available or t.available()) or false
end

-- Lay out the visible tab pills (pet comes and goes; Blizzard-only tabs are
-- shown while Blizzard shows them).
local function layoutTabs()
    local x = 20
    for _, b in ipairs(tabButtons) do
        local show
        if b.blizzTab then show = b.blizzTab:IsShown() else show = tabAvailable(b.key) end
        b:SetShown(show)
        if show then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -TABS_Y)
            x = x + b:GetWidth() + 6
        end
    end
end

function C:SetTab(key)
    if not pages[key] or not tabAvailable(key) then key = "gear" end
    self.tab = key
    for k, p in pairs(pages) do p:SetShown(k == key) end
    for _, b in ipairs(tabButtons) do b.selected = (b.key == key); b:Repaint() end
    self:Refresh()
end

-- Open Blizzard's character screen on one of its own tabs.
local function openBlizzardTab(blizzTab)
    C.bypass = true
    win:Hide()
    ShowUIPanel(CharacterFrame)
    if blizzTab and blizzTab:IsEnabled() then blizzTab:Click() end
end

-- Model on a soft spotlight (tinted) with a floor shadow. The model fits
-- itself inside its frame with empty space under the feet, so the frame sits
-- DROP lower to plant the feet on the shadow; it stays at the page's own
-- frame level so tiles and bars drawn over its lower edge keep their clicks.
local DROP = 24
local function makeModelArea(page, x1, y1, x2, y2, tint)
    local cx = (x1 + x2) / 2
    local spot = page:CreateTexture(nil, "BACKGROUND", nil, 1)
    spot:SetTexture(MEDIA .. "spot.tga")
    spot:SetSize(320, 320)
    spot:SetPoint("CENTER", page, "TOPLEFT", cx, (y1 + y2) / 2 - 2)
    if tint then spot:SetVertexColor(tint.r, tint.g, tint.b, 0.16) else spot:SetVertexColor(1, 1, 1, 0.08) end
    local floor = page:CreateTexture(nil, "BACKGROUND", nil, 2)
    floor:SetTexture(MEDIA .. "spot.tga")
    floor:SetVertexColor(0, 0, 0, 0.7)
    floor:SetSize(170, 30)
    floor:SetPoint("CENTER", page, "TOPLEFT", cx, y2 + 12)

    local model = CreateFrame("PlayerModel", nil, page)
    model:SetPoint("TOPLEFT", page, "TOPLEFT", x1, y1 - DROP)
    model:SetPoint("BOTTOMRIGHT", page, "TOPLEFT", x2, y2 - DROP)
    model:SetFrameLevel(page:GetFrameLevel())
    model.facing, model.zoom, model.floor = 0, 0, floor
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then self.dragX = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnHide", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = self.facing + (x - self.dragX) / (UIParent:GetEffectiveScale() * 90)
        self.dragX = x
        self:SetFacing(self.facing)
    end)
    model:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = math.max(0, math.min(0.75, self.zoom + delta * 0.1))
        pcall(self.SetPortraitZoom, self, self.zoom)
        -- Zooming lifts the feet off the floor: fade the shadow out.
        self.floor:SetAlpha(math.max(0, 1 - self.zoom / 0.3))
    end)
    return model
end

-- Stats card: resistance chips across the top, scrolling stat list below.
local function makeStatsCard(page, top)
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", page, "TOPLEFT", 440, top)
    card:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 16)
    ns.RoundedRect(card, -6, 0, 10, unpack(CARD))

    -- Attribute tiles: the top row.
    card.attrs = {}
    local TW, TH, TG = 44, 38, 6
    local ATTR_ROW = TH + 8
    local ax0 = (W - 20 - 440) / 2 - (#ATTRS * TW + (#ATTRS - 1) * TG) / 2
    for i, a in ipairs(ATTRS) do
        local tile = CreateFrame("Frame", nil, card)
        tile:SetSize(TW, TH)
        tile:SetPoint("TOPLEFT", card, "TOPLEFT", ax0 + (i - 1) * (TW + TG), -8)
        ns.RoundedRect(tile, -4, 0, 7, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(tile, -3, 1, 6, unpack(FILL))
        local label = text(tile, 9, true, a[3])
        label:SetPoint("TOP", 0, -5)
        label:SetText(a[1])
        -- A short stroke in the attribute's color under its label.
        local stroke = tile:CreateTexture(nil, "ARTWORK")
        stroke:SetSize(14, 1)
        stroke:SetPoint("TOP", label, "BOTTOM", 0, -2)
        stroke:SetColorTexture(a[3][1], a[3][2], a[3][3], 0.55)
        tile.value = text(tile, 13, true)
        tile.value:SetPoint("BOTTOM", 0, 5)
        tile:EnableMouse(true)
        tile:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(a[2], a[3][1], a[3][2], a[3][3])
            if self.eff ~= nil then GameTooltip:AddLine(fmt(self.eff, "%d"), 1, 1, 1) end
            if plain(self.base) then GameTooltip:AddDoubleLine("Base", string.format("%d", self.base), 0.6, 0.6, 0.65, 1, 1, 1) end
            if plain(self.pos) and self.pos > 0 then
                GameTooltip:AddDoubleLine("Bonus", string.format("+%d", self.pos), 0.6, 0.6, 0.65, GREEN[1], GREEN[2], GREEN[3])
            end
            if plain(self.neg) and self.neg < 0 then
                GameTooltip:AddDoubleLine("Penalty", string.format("%d", self.neg), 0.6, 0.6, 0.65, RED[1], RED[2], RED[3])
            end
            -- What it gives this character.
            local ok, fx = pcall(attrEffects, self.index or i, self.unit or "player", self.eff)
            if ok and #fx > 0 then
                GameTooltip:AddLine(" ")
                for _, e in ipairs(fx) do
                    GameTooltip:AddDoubleLine(e[1], e[2], a[3][1], a[3][2], a[3][3], 1, 1, 1)
                end
            end
            GameTooltip:Show()
        end)
        tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card.attrs[i] = tile
    end

    card.resists = {}
    local D, step = 28, 40
    local x0 = (W - 20 - 440) / 2 - (#RESISTS - 1) * step / 2
    for i, r in ipairs(RESISTS) do
        local chip = CreateFrame("Frame", nil, card)
        chip:SetSize(D, D)
        chip:SetPoint("CENTER", card, "TOPLEFT", x0 + (i - 1) * step, -24 - ATTR_ROW)
        local ring = circle(chip, D, "ARTWORK", 1)
        ring:SetPoint("CENTER")
        ring:SetColorTexture(r[3][1], r[3][2], r[3][3], 0.9)
        local inner = circle(chip, D - 4, "ARTWORK", 2)
        inner:SetPoint("CENTER")
        inner:SetColorTexture(unpack(FILL))
        chip.fs = text(chip, 10, true, r[3])
        chip.fs:SetPoint("CENTER", 0, 0)
        chip.school = r[1]
        chip:EnableMouse(true)
        chip:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText((_G["RESISTANCE" .. r[1] .. "_NAME"] or (r[2] .. " Resistance")), r[3][1], r[3][2], r[3][3])
            if self.value ~= nil then GameTooltip:AddLine(fmt(self.value, "%d"), 1, 1, 1) end
            GameTooltip:Show()
        end)
        chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(card.resists, chip)
    end

    local cardW, cardH = W - 20 - 440, H - PAGE_TOP + top - 16
    card.list = makeList(card, cardW - 12, cardH - 52 - ATTR_ROW, 18)
    card.list:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -46 - ATTR_ROW)
    return card
end

local function buildGear(page)
    local top = -4
    for i, s in ipairs(LEFT_SLOTS) do
        local b = makeTile(page, s)
        if b then b:SetPoint("TOPLEFT", page, "TOPLEFT", 20, top - (i - 1) * (TILE + GAP)) end
    end
    for i, s in ipairs(RIGHT_SLOTS) do
        local b = makeTile(page, s)
        if b then b:SetPoint("TOPLEFT", page, "TOPLEFT", 420 - TILE, top - (i - 1) * (TILE + GAP)) end
    end
    local weapons = {}
    for _, s in ipairs(WEAPON_SLOTS) do
        local b = makeTile(page, s)
        if b then table.insert(weapons, b) end
    end
    local rowW = #weapons * TILE + (#weapons - 1) * GAP
    local cx = (20 + 420) / 2
    for i, b in ipairs(weapons) do
        b:SetPoint("TOPLEFT", page, "TOPLEFT", cx - rowW / 2 + (i - 1) * (TILE + GAP), top - 7 * (TILE + GAP))
    end

    local _, token = UnitClass("player")
    local cc = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    win.model = makeModelArea(page, 20 + TILE + 10, top, 420 - TILE - 10, top - 7 * (TILE + GAP) + 6, cc)
    win.card = makeStatsCard(page, top)
end

local function buildPet(page)
    local top = -4
    page.model = makeModelArea(page, 40, top, 400, -296, { r = 0.55, g = 0.75, b = 0.45 })
    page.card = makeStatsCard(page, top)

    page.xp = ns:CreatePillBar(page, 384, 12)
    page.xp:SetPoint("TOPLEFT", page, "TOPLEFT", 28, -318)
    page.xp.bar:SetStatusBarColor(0.62, 0.45, 0.95, 1)
    page.xp:SetRingColor(0.37, 0.27, 0.57, 1)
    page.xp:SetFrameLevel(page:GetFrameLevel() + 2)
    page.xp.label = page.xp:CreateText(9, nil, true)
    page.xp.label:SetPoint("CENTER", page.xp, "CENTER", 0, 0)

    page.status = text(page, 11, false, T.textDim)
    page.status:SetPoint("TOP", page, "TOPLEFT", 220, -342)
end

local function buildListPage(page)
    page.list = makeList(page, W - 40, H - PAGE_TOP - 20, 22, 384)
    page.list:SetPoint("TOPLEFT", 20, -4)
end

local function build()
    win = CreateFrame("Frame", "MinimalUICharacter", UIParent)
    win:SetSize(W, H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self)
        if C.HideGearCovers then pcall(C.HideGearCovers) end
        self:StartMoving()
    end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
    local pos = C.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER", 0, 40) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUICharacter")

    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win)

    for _, t in ipairs(TABS) do
        local b = pillButton(win, t.label, function() C:SetTab(t.key) end)
        b.key = t.key
        table.insert(tabButtons, b)
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", 0, -PAGE_TOP)
        page:SetPoint("BOTTOMRIGHT")
        page:Hide()
        pages[t.key] = page
    end

    -- Any tab on Blizzard's screen that has no page here (or whose page the
    -- client can't support) gets a pill that opens Blizzard's screen on it.
    local i = 1
    while _G["CharacterFrameTab" .. i] do
        local bt = _G["CharacterFrameTab" .. i]
        local fs = bt.Text or _G[bt:GetName() .. "Text"]
        local label = (fs and fs:GetText()) or (bt.GetText and bt:GetText())
        if label and not secret(label) and label ~= "" then
            local low, native = label:lower(), nil
            for _, t in ipairs(TABS) do
                for _, w in ipairs(t.kw) do
                    if low:find(w, 1, true) then native = t end
                end
            end
            if not native or (native.available and not native.available()) then
                local b = pillButton(win, label, function() openBlizzardTab(bt) end)
                b.blizzTab = bt
                b.fs:SetTextColor(unpack(T.textDim))
                table.insert(tabButtons, b)
            end
        end
        i = i + 1
    end

    local line = win:CreateTexture(nil, "BORDER")
    line:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.8)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 20, -(TABS_Y + 32))
    line:SetPoint("TOPRIGHT", -20, -(TABS_Y + 32))

    buildGear(pages.gear)
    buildPet(pages.pet)
    for _, k in ipairs({ "rep", "skills", "currency", "honor" }) do buildListPage(pages[k]) end

    win:SetScript("OnShow", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        C.headStale = true
        win.model:SetUnit("player")
        win.model:SetFacing(win.model.facing)
        layoutTabs()
        C:Refresh()
    end)
    win:SetScript("OnHide", function()
        if C.HideGearCovers then pcall(C.HideGearCovers) end
        pages.pet.stale = true
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end)
end

local LIST_DATA = { rep = repData, skills = skillsData, currency = currencyData, honor = honorData }

function C:Refresh()
    if not win or not win:IsShown() then return end
    for _, b in ipairs(tiles) do pcall(updateTile, b) end
    pcall(updateHeader)
    if self.tab == "gear" then
        pcall(updateResists, win.card.resists, "player")
        pcall(updateAttrs, win.card, "player")
        local ok, d = pcall(statsData, "player")
        if ok then win.card.list:SetData(d) else ns:Print("Character stats: " .. tostring(d)) end
    elseif self.tab == "pet" then
        local ok, err = pcall(updatePet, pages.pet)
        if not ok then ns:Print("Pet: " .. tostring(err)) end
    elseif LIST_DATA[self.tab] then
        local ok, d = pcall(LIST_DATA[self.tab])
        if ok then pages[self.tab].list:SetData(d) else ns:Print(self.tab .. ": " .. tostring(d)) end
    end
end

function C:Open(tab)
    if not win then build() end
    win:Show()
    self:SetTab(tab or self.tab or "gear")
end

function C:Toggle(tab)
    if win and win:IsShown() and (tab == nil or tab == self.tab) then win:Hide() else self:Open(tab) end
end

-- ── Taking over Blizzard's character screen ──────────────────────────────
local TAB_FOR = { PaperDollFrame = "gear", PetPaperDollFrame = "pet", ReputationFrame = "rep",
                  SkillFrame = "skills", TokenFrame = "currency", HonorFrame = "honor" }

local function subFrameTab()
    for frameName, key in pairs(TAB_FOR) do
        local f = _G[frameName]
        if f and f:IsShown() then return key end
    end
end

-- want: the tab the caller asked for. Forever has no SkillFrame, so for K
-- (ToggleCharacter("SkillFrame")) no sub-frame ever shows: Blizzard's window
-- opened empty and invisible (just the sound) and we never took over.
local function takeOver(want)
    if C.bypass or not CharacterFrame or not CharacterFrame:IsShown() then return end
    local tab = want or subFrameTab()
    if not tab or not tabAvailable(tab) then return end
    HideUIPanel(CharacterFrame)
    return tab
end

local function attach()
    if C.attached or not _G.CharacterFrame then return end
    C.attached = true
    if ToggleCharacter then
        hooksecurefunc("ToggleCharacter", function(frameName)
            if C.bypass or not TAB_FOR[frameName] or not tabAvailable(TAB_FOR[frameName]) then return end
            local tab = TAB_FOR[frameName]
            local wasOpen = win and win:IsShown() and C.tab == tab
            -- Blizzard's window may or may not have opened (no SkillFrame on
            -- Forever); either way it goes, and ours toggles.
            takeOver(tab)
            if wasOpen then win:Hide() else C:Open(tab) end
        end)
    end
    -- Anything else that shows Blizzard's window (other addons, direct calls).
    CharacterFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            local tab = takeOver()
            if tab then C:Open(tab) end
        end)
    end)
    CharacterFrame:HookScript("OnHide", function() C.bypass = false end)
end

function C:OnInit(db)
    self.db = db
    db.collapsed = db.collapsed or {}

    -- Using something that has to be applied to a piece of gear (an armor
    -- kit, a sharpening stone, an enchant) turns the cursor into "apply to
    -- what?". Blizzard's bag buttons open the character window at that
    -- point; our bag tiles don't run that code, so we do it here.
    --
    -- Applying it is a protected action: our gear tiles' own click
    -- (PickupInventoryItem) gets "blocked from an action only available to
    -- the Blizzard UI" while the cursor is targeting. So while it is, each
    -- gear slot is covered by an invisible secure button that applies the
    -- pending item / spell to that slot (a "/use <slot>" macro, plus the
    -- secure button's own target-slot attribute as a second route).
    -- The covers are separate frames placed over the tiles by screen
    -- position, not children of the window and not anchored to it, so the
    -- window itself stays free to open and close in combat. They can only
    -- be shown out of combat; in combat, use /men blizzchar.
    local covers = {}
    -- Can the thing on the cursor go on what is in this slot? Blizzard's own
    -- test for dimming non-matching items (an armor kit: chest, legs, hands,
    -- feet). An empty slot never can. If the client doesn't have the test,
    -- any slot with an item counts.
    local function validSlot(slot)
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if type(id) ~= "number" or id <= 0 then return false end
        local test = C_Item and C_Item.DoesItemMatchTargetEnchantingSpell
        if test and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
            local ok, res = pcall(function()
                local loc = ItemLocation:CreateFromEquipmentSlot(slot)
                if C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return false end
                return test(loc)
            end)
            if ok and res ~= nil and not (issecretvalue and issecretvalue(res)) then return res and true or false end
        end
        return true
    end
    local function hideCovers()
        if InCombatLockdown() then C.coversStale = true return end
        C.coversStale = false
        for _, cv in ipairs(covers) do cv:Hide() end
    end
    local function showCovers()
        if InCombatLockdown() then
            ns:Print("Can't target gear from this window in combat. Use /men blizzchar for Blizzard's.")
            return
        end
        for i, tile in ipairs(tiles) do
            local cv = covers[i]
            if not cv then
                cv = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
                cv:SetFrameStrata("DIALOG")
                cv:RegisterForClicks("AnyDown", "AnyUp")
                -- A light wash in the accent color: "this is a valid target".
                -- (A wash, not a ring: the gear icon has to stay visible.)
                ns.RoundedRect(cv, 0, 0, 7, T.accent[1], T.accent[2], T.accent[3], 0.22, "OVERLAY")
                cv:SetScript("OnEnter", function(self)
                    local t = self.tile
                    local fn = t and t:GetScript("OnEnter")
                    if fn then pcall(fn, t) end
                end)
                cv:SetScript("OnLeave", function() GameTooltip:Hide() end)
                covers[i] = cv
            end
            cv.tile = tile
            local slot = tile.slot
            local l, b = tile:GetLeft(), tile:GetBottom()
            if slot and l and b and tile:IsVisible() and validSlot(slot) then
                local k = tile:GetEffectiveScale() / UIParent:GetEffectiveScale()
                cv:SetAttribute("type", "macro")
                cv:SetAttribute("macrotext", "/use " .. slot)
                cv:SetAttribute("target-slot", slot)
                cv:ClearAllPoints()
                cv:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, b * k)
                cv:SetSize(tile:GetWidth() * k, tile:GetHeight() * k)
                cv:Show()
            else
                cv:Hide()
            end
        end
    end
    C.HideGearCovers = hideCovers

    local aim = CreateFrame("Frame")
    for _, e in ipairs({ "CURRENT_SPELL_CAST_CHANGED", "CURSOR_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        pcall(aim.RegisterEvent, aim, e)
    end
    local queued = false
    aim:SetScript("OnEvent", function()
        if queued then return end
        queued = true
        C_Timer.After(0, function()
            queued = false
            if not (SpellIsTargeting and SpellCanTargetItem) then return end
            local ok, want = pcall(function() return SpellIsTargeting() and SpellCanTargetItem() end)
            if ok and want then
                if not (win and win:IsShown() and C.tab == "gear") then pcall(C.Open, C, "gear") end
                -- After the window has laid its tiles out.
                C_Timer.After(0, function()
                    if win and win:IsShown() and C.tab == "gear" then pcall(showCovers) end
                end)
            else
                pcall(hideCovers)
            end
        end)
    end)

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_LOADED", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY",
                         "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_LEVEL_UP", "UPDATE_FACTION",
                         "SKILL_LINES_CHANGED", "PLAYER_GUILD_UPDATE", "COMBAT_RATING_UPDATE",
                         "CHARACTER_POINTS_CHANGED", "PET_UI_UPDATE", "CURRENCY_DISPLAY_UPDATE",
                         "PLAYER_PVP_KILLS_CHANGED", "PLAYER_PVP_RANK_CHANGED", "TRADE_SKILL_LIST_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    for _, e in ipairs({ "UNIT_INVENTORY_CHANGED", "UNIT_STATS", "UNIT_AURA", "UNIT_ATTACK_POWER",
                         "UNIT_RANGED_ATTACK_POWER", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED",
                         "UNIT_RESISTANCES", "UNIT_DEFENSE", "UNIT_MODEL_CHANGED", "UNIT_PET",
                         "UNIT_HAPPINESS", "UNIT_PET_EXPERIENCE", "UNIT_LEVEL", "UNIT_NAME_UPDATE" }) do
        pcall(ev.RegisterUnitEvent, ev, e, "player", "pet")
    end
    -- Coalesce bursts of events into one refresh.
    local dirty, model = false, false
    ev:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then attach(); return end
        if not win or not win:IsShown() then return end
        if event == "UNIT_PET" or event == "PET_UI_UPDATE" then
            layoutTabs()
            if C.tab == "pet" and not tabAvailable("pet") then C:SetTab("gear") end
        end
        dirty = true
        if event == "UNIT_MODEL_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then model = true end
    end)
    local acc = 0
    ev:SetScript("OnUpdate", function(_, dt)
        if not dirty then return end
        acc = acc + dt
        if acc < 0.15 then return end
        acc, dirty = 0, false
        if model and win.model then win.model:SetUnit("player"); win.model:SetFacing(win.model.facing) end
        model = false
        C:Refresh()
    end)
    attach()
end

-- /men char : open Meniscus's character window.
-- /men blizzchar : open Blizzard's character screen instead (this once).
ns.commands.char = function() if C.db then C:Toggle("gear") end end
ns.commands.blizzchar = function()
    C.bypass = true
    if ToggleCharacter then ToggleCharacter("PaperDollFrame") else ShowUIPanel(CharacterFrame) end
end

-- /men charprobe : record what this client offers for names and skills into
-- MinimalUIDB.charprobe (/reload afterwards to save it).
ns.commands.charprobe = function()
    local out = {}
    local function add(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
        table.insert(out, table.concat(t, " | "))
    end
    add("UnitName", UnitName("player"))
    add("GetUnitName(true)", call(GetUnitName, "player", true))
    add("UnitFullName", call(UnitFullName, "player"))
    add("UnitPVPName", call(UnitPVPName, "player"))
    add("GetRealmName", call(GetRealmName), call(GetNormalizedRealmName))
    local i = 1
    while _G["CharacterFrameTab" .. i] do
        local bt = _G["CharacterFrameTab" .. i]
        local fs = bt.Text or _G[bt:GetName() .. "Text"]
        add("tab", i, fs and fs:GetText(), bt:IsShown())
        i = i + 1
    end
    for _, n in ipairs({ "SkillFrame", "SkillFrameScrollFrame", "SkillListScrollFrame", "SkillDetailScrollFrame" }) do
        add("frame", n, _G[n] ~= nil)
    end
    local g = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:lower():find("skill") and type(v) == "function" then table.insert(g, k) end
    end
    table.sort(g)
    add("skill functions", table.concat(g, ", "))
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^C_") and type(v) == "table" then
            local fns = {}
            for fk in pairs(v) do
                if type(fk) == "string" and (fk:lower():find("skill") or k:lower():find("skill")) then
                    table.insert(fns, fk)
                end
            end
            if #fns > 0 then table.sort(fns); add(k, table.concat(fns, ", ")) end
        end
    end
    MinimalUIDB.charprobe = out
    ns:Print("Recorded " .. #out .. " lines. /reload to save them.")
end