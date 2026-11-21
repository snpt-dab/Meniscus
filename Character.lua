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
--   { kind = "pair",   a, b }   two stats side by side (each as a "stat")
-- A header may carry glyph = a Media icon: it is then drawn with that icon
-- and a hairline running out to the right, instead of the chevron.
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
    row.glyph = row:CreateTexture(nil, "ARTWORK")
    row.glyph:SetSize(14, 14)
    row.glyph:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.glyph:Hide()
    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    row.rule:Hide()
    return row
end

-- The two halves of a "pair" row: each its own hover and tooltip.
local function pairCells(row)
    if row.cells then return row.cells end
    row.cells = {}
    for i = 1, 2 do
        local c = CreateFrame("Button", nil, row)
        c.hl = ns.RoundedRect(c, -8, 0, 6, 1, 1, 1, 0)
        c.label = text(c, 11, false, T.textDim)
        c.label:SetPoint("LEFT", c, "LEFT", 3, 0)
        c.label:SetJustifyH("LEFT")
        c.label:SetWordWrap(false)
        c.value = text(c, 11, true)
        c.value:SetPoint("RIGHT", c, "RIGHT", -3, 0)
        c.value:SetJustifyH("RIGHT")
        c.label:SetPoint("RIGHT", c.value, "LEFT", -4, 0)
        -- A faint line under each, as a ledger has.
        local under = c:CreateTexture(nil, "BACKGROUND")
        under:SetHeight(1)
        under:SetPoint("BOTTOMLEFT", 2, 0); under:SetPoint("BOTTOMRIGHT", -2, 0)
        under:SetColorTexture(1, 1, 1, 0.045)
        c:SetScript("OnEnter", function(self)
            local d = self.data
            if not (d and d.tooltip) then return end
            self.hl(1, 1, 1, 0.05)
            ns.TipAnchor(self)
            d.tooltip(GameTooltip)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function(self) self.hl(1, 1, 1, 0); GameTooltip:Hide() end)
        row.cells[i] = c
    end
    return row.cells
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
    row.glyph:Hide(); row.rule:Hide()
    if row.cells then row.cells[1]:Hide(); row.cells[2]:Hide() end
    if d.kind == "pair" then
        row.label:SetText("")
        local cells = pairCells(row)
        local rw = row:GetWidth()
        if not rw or rw < 20 then rw = (row:GetParent():GetWidth() or 240) - 8 end
        local w = (rw - 8) / 2 -- two cells and an 8 gap between them
        for i = 1, 2 do
            local c, s = cells[i], (i == 1) and d.a or d.b
            c.data = s
            c.hl(1, 1, 1, 0)
            if s then
                c:ClearAllPoints()
                c:SetPoint("LEFT", row, "LEFT", (i - 1) * (w + 8), 0)
                c:SetSize(w, row:GetHeight())
                c.label:SetText(s.label)
                c.value:SetText(s.value)
                c.value:SetTextColor(unpack(s.color or T.text))
                c:Show()
            end
        end
        return
    end
    if d.kind == "header" and d.glyph then
        local dim = d.collapsed and 0.55 or 1
        row.glyph:SetTexture(MEDIA .. d.glyph)
        row.glyph:SetVertexColor(0.72 * dim, 0.72 * dim, 0.76 * dim, 1)
        row.glyph:Show()
        ns:SetFont(row.label, 10, "", true)
        row.label:SetTextColor(T.textDim[1] * dim, T.textDim[2] * dim, T.textDim[3] * dim)
        row.label:SetPoint("LEFT", row, "LEFT", 22, 0)
        row.label:SetText(d.text)
        row.rule:ClearAllPoints()
        row.rule:SetPoint("LEFT", row, "LEFT", 22 + row.label:GetStringWidth() + 8, 0)
        row.rule:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.rule:Show()
        return
    end
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
C.MakeList = makeList -- (the bestiary's two lists)

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
        local a = self.advice
        if a then
            GameTooltip:AddLine(" ")
            if a.empty then
                GameTooltip:AddLine("Nothing worn here", 0.95, 0.62, 0.45)
            else
                local d = math.floor(math.abs(a.gap) + 0.5)
                local how = d == 0 and "level with" or (d .. (a.gap < 0 and " above" or " below"))
                local c = a.behind and { 0.95, 0.62, 0.45 } or { 0.6, 0.6, 0.65 }
                GameTooltip:AddLine(string.format("Item level %d: %s %s (%d)", a.lvl, how, a.against, math.floor(a.par + 0.5)), c[1], c[2], c[3])
            end
            if a.ratio and a.ratio < 0.7 and self.advFavour then
                GameTooltip:AddLine("Little of what you gear for (" .. self.advFavour .. ")", 0.95, 0.62, 0.45)
            end
            if a.top then GameTooltip:AddLine("Next upgrade: the slot most worth replacing", T.accent[1], T.accent[2], T.accent[3]) end
        end
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

-- ── What to upgrade next ──────────────────────────────────────────────────
-- (0.1.559) Which slot is holding your gear back. Each piece's item level
-- is set against a mark: the average of what you wear, or your own level
-- when the average is under it (so a character whose gear is all old still
-- gets an answer). How far a slot is under the mark is weighed by how much
-- the slot carries: a chest or legs piece holds about twice the stats of a
-- belt or a ring, and your weapon (the bow, for a hunter) counts for more
-- than any armour. A slot with nothing in it counts as far behind, once
-- you are of a level where pieces for it are to be had (no helmets at 8),
-- and only where your class uses it. The slot that comes out worst gets
-- the marker; a slot well under the mark has its level in orange.
-- Item level only: it says where to look, not which piece to take (the
-- upgrade marks in the bags and on loot weigh the stats).
local SLOT_WEIGHT = { Head = 1, Chest = 1, Legs = 1, Shoulder = 0.75, Hands = 0.75, Feet = 0.75,
                      Waist = 0.55, Wrist = 0.55, Back = 0.55, Neck = 0.55, Finger0 = 0.55, Finger1 = 0.55,
                      Trinket0 = 0.3, Trinket1 = 0.3 }
-- the level from which an empty slot is worth a word
local FROM_LEVEL = { Back = 6, Waist = 5, Wrist = 5, Shoulder = 12, Head = 18, Finger0 = 18, Finger1 = 18,
                     Neck = 20, Trinket0 = 40, Trinket1 = 40 }
--                    main  off  ranged   empty off hand from, empty ranged from (nil: never)
local WEAPON_WEIGHT = {
    WARRIOR = { 1.8, 0.7, 0.3, 1, 10 },
    PALADIN = { 1.8, 0.7, 0, 1, nil },
    ROGUE   = { 1.8, 0.9, 0.3, 10, 10 },
    HUNTER  = { 0.7, 0.5, 1.8, 20, 1 },
    SHAMAN  = { 1.4, 0.7, 0, 1, nil },
    DRUID   = { 0.9, 0.5, 0, 15, nil },
    PRIEST  = { 0.9, 0.5, 0.6, 15, 8 },
    MAGE    = { 0.9, 0.5, 0.6, 15, 8 },
    WARLOCK = { 0.9, 0.5, 0.6, 15, 8 },
}
local SLOT_LABEL = { Shoulder = "Shoulders", Back = "Cloak", Wrist = "Bracers", Hands = "Gloves", Waist = "Belt",
                     Feet = "Boots", Finger0 = "Ring", Finger1 = "Ring", Trinket0 = "Trinket", Trinket1 = "Trinket",
                     MainHand = "Main hand", SecondaryHand = "Off hand", Ranged = "Ranged" }
local TOOL_SUB = { [14] = true, [20] = true } -- (a pick or a fishing pole in hand is not your weapon)
local BEHIND = { 0.95, 0.62, 0.45 }
-- What you are gearing for (0.1.563), read off what you wear: the totals
-- of the five attributes on your gear, which is the graph's gear shape.
-- Mostly Stamina, then Strength, then Agility, say. Each attribute gets a
-- weight from its share (the largest is 1), steadied with a third of the
-- class's usual weights so a few odd pieces at a low level don't decide
-- it. A piece of armour is then judged by how much of THOSE it carries for
-- its slot's size, against what your pieces usually carry: one with
-- little of them counts as lower than its item level (down to 0.6 of it),
-- one with plenty as a little higher (up to 1.2). Weapons and trinkets are
-- left at their item level: they are worth what they do, not their stats.
local ADV_KEY = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
                  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" }
local ADV_NAME = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local function statJudged(name) return SLOT_WEIGHT[name] ~= nil and name ~= "Trinket0" and name ~= "Trinket1" end

local function gearAdvice()
    local out = { list = {} }
    local level = UnitLevel("player")
    local _, cls = UnitClass("player")
    local sum, n = 0, 0
    for _, b in ipairs(tiles) do
        b.advice = nil
        if b.lvl then sum, n = sum + b.lvl, n + 1 end
    end
    if n == 0 or not plain(level) then return out end
    local avg = sum / n
    local par = (level > avg and level < avg * 2 + 10) and level or avg
    out.avg, out.par, out.level = avg, par, level
    -- what you favour, and what your pieces usually carry of it
    local lean, usual
    do
        local tot, sumAll = { 0, 0, 0, 0, 0 }, 0
        for _, b in ipairs(tiles) do
            b.attrs = nil
            local link = b.lvl and GetInventoryItemLink("player", b.slot)
            local st = link and not secret(link) and ns.ItemStats and ns.ItemStats(link)
            if st then
                local a = {}
                for i = 1, 5 do
                    local v = st[ADV_KEY[i]]
                    a[i] = plain(v) and v or 0
                    tot[i] = tot[i] + a[i]
                    sumAll = sumAll + a[i]
                end
                b.attrs = a
            end
        end
        local mx = math.max(tot[1], tot[2], tot[3], tot[4], tot[5])
        if sumAll >= 10 and mx > 0 then
            local cw = ns.StatWeights and ns.StatWeights[cls or ""]
            lean = {}
            for i = 1, 5 do lean[i] = 0.65 * tot[i] / mx + 0.35 * (cw and cw[i] or 0.5) end
            local order = { 1, 2, 3, 4, 5 }
            table.sort(order, function(x, y) return tot[x] > tot[y] end)
            local names = {}
            for _, i in ipairs(order) do
                if #names < 3 and tot[i] >= mx * 0.25 then names[#names + 1] = ADV_NAME[i] end
            end
            out.favour = table.concat(names, ", ")
            local rs, rn = 0, 0
            for _, b in ipairs(tiles) do
                if b.attrs and statJudged(b.slotName) then
                    local v = 0
                    for i = 1, 5 do v = v + lean[i] * b.attrs[i] end
                    b.rate = v / SLOT_WEIGHT[b.slotName]
                    rs, rn = rs + b.rate, rn + 1
                else
                    b.rate = nil
                end
            end
            if rn >= 4 and rs > 0 then usual = rs / rn else lean = nil end
        end
    end
    local ww = WEAPON_WEIGHT[cls or ""] or WEAPON_WEIGHT.WARRIOR
    local info = C_Item and C_Item.GetItemInfoInstant
    local function kind(slot)
        local link = info and GetInventoryItemLink("player", slot)
        if not link or secret(link) then return end
        local _, _, _, loc, _, classID, subID = call(info, link)
        return loc, classID, subID
    end
    local twoHand = kind(16) == "INVTYPE_2HWEAPON"
    for _, b in ipairs(tiles) do
        local name = b.slotName
        local w, from
        if name == "MainHand" then w, from = ww[1], 1
        elseif name == "SecondaryHand" then w, from = ww[2], ww[4]
        elseif name == "Ranged" then w, from = ww[3], ww[5]
        else w, from = SLOT_WEIGHT[name], FROM_LEVEL[name] or 1 end
        if w and w > 0 then
            local e
            if b.lvl then
                local _, classID, subID = kind(b.slot)
                if not (classID == 2 and TOOL_SUB[subID]) then
                    e = { lvl = b.lvl, gap = par - b.lvl }
                    if lean and usual and b.rate then
                        e.ratio = b.rate / usual
                        e.egap = par - b.lvl * (0.6 + 0.4 * math.min(e.ratio, 1.5))
                    end
                end
            elseif not GetInventoryItemTexture("player", b.slot) and from and level >= from
                and not (name == "SecondaryHand" and twoHand) then
                e = { empty = true, gap = math.min(15, math.max(5, par)) }
            end
            if e then
                e.tile, e.label, e.avg, e.par = b, SLOT_LABEL[name] or name, avg, par
                e.against = par == avg and "your gear's average" or "your level"
                e.score = (e.egap or e.gap) * w
                e.behind = e.empty or (e.egap or e.gap) >= math.max(4, par * 0.15)
                b.advice = e
                table.insert(out.list, e)
            end
        end
    end
    table.sort(out.list, function(x, y) return x.score > y.score end)
    local first = out.list[1]
    if first and first.score >= 2 then first.top = true; out.top = first end
    return out
end

-- "Next upgrade" (0.1.561; it was a chip over the model and a badge on the
-- tile's corner): one round icon beside the slot that came out worst, on
-- the tile's inner side, level with its middle (above it, for the weapons
-- along the bottom). The ranking and what the numbers mean are in its
-- tooltip. Off with the "Next upgrade" switch (Windows page).
local function applyAdvice()
    local ok, adv = pcall(gearAdvice)
    if not ok then adv = { list = {} } end
    for _, b in ipairs(tiles) do
        local a = b.advice
        b.advFavour = adv.favour
        if a and a.behind then b.ilvl:SetTextColor(BEHIND[1], BEHIND[2], BEHIND[3]) else b.ilvl:SetTextColor(1, 1, 1) end
    end
    local icon = win and win.nextIcon
    if not icon then return end
    icon.adv = adv
    local t = adv.top
    if not t or C.db.nextUpgrade == false then icon:Hide() return end
    local b = t.tile
    icon:ClearAllPoints()
    if b.side == "left" then icon:SetPoint("LEFT", b, "RIGHT", 6, 0)
    elseif b.side == "right" then icon:SetPoint("RIGHT", b, "LEFT", -6, 0)
    else icon:SetPoint("BOTTOM", b, "TOP", 0, 6) end
    icon:Show()
end

-- ── Stat tooltips ─────────────────────────────────────────────────────────
-- What each number on the stats card means for you right now. A tooltip is
-- a title (the stat and its value) and lines: a string is a sentence, a
-- pair is "label ... value". Values the game hides in combat are left out.
local DIM, BODY = { 0.6, 0.6, 0.65 }, { 0.86, 0.86, 0.89 }
local function statTip(title, lines)
    return function(tip)
        tip:SetText(title, 1, 1, 1)
        for _, ln in ipairs(lines) do
            if type(ln) == "table" then
                tip:AddDoubleLine(ln[1], ln[2], DIM[1], DIM[2], DIM[3], 1, 1, 1)
            elseif ln == "" then
                tip:AddLine(" ")
            else
                tip:AddLine(ln, BODY[1], BODY[2], BODY[3], true)
            end
        end
    end
end
-- Base / bonus / penalty lines for a stat that comes as (base, +, -).
local function parts(lines, base, pos, neg)
    if not plain(base) then return end
    lines[#lines + 1] = { "Base", string.format("%d", base) }
    if plain(pos) and pos > 0 then lines[#lines + 1] = { "From gear and buffs", string.format("+%d", pos) } end
    if plain(neg) and neg < 0 then lines[#lines + 1] = { "From debuffs", string.format("%d", neg) } end
end
-- Share of a physical hit that armor takes off, against an attacker of a
-- given level (the game's own sum when it offers one).
local function armorCut(armor, level)
    if not plain(armor, level) then return nil end
    if _G.PaperDollFrame_GetArmorReduction then
        local ok, v = pcall(PaperDollFrame_GetArmorReduction, armor, level)
        if ok and plain(v) then return v end
    end
    local cut
    if level < 60 then cut = armor / (armor + 400 + 85 * level)
    else cut = armor / (armor + 467.5 * level - 22167.5) end
    return math.max(0, math.min(0.75, cut)) * 100
end
local function armorTip(unit, armor, base, pos, neg)
    local lines = {}
    local lvl = UnitLevel(unit)
    local same = armorCut(armor, lvl)
    if same then
        lines[#lines + 1] = string.format("Takes %.1f%% off physical damage from an attacker of your level (%d).", same, lvl)
        local up = armorCut(armor, lvl + 3)
        if up then lines[#lines + 1] = { "Against level " .. (lvl + 3), string.format("%.1f%%", up) } end
        lines[#lines + 1] = ""
    else
        lines[#lines + 1] = "Takes a share off every physical hit; the higher the attacker's level, the smaller the share."
    end
    parts(lines, base, pos, neg)
    return statTip("Armor" .. (plain(armor) and ("  " .. string.format("%d", armor)) or ""), lines)
end

-- ── Stats ─────────────────────────────────────────────────────────────────
local SECTION_GLYPH = { Melee = "micro_stat_melee.tga", Ranged = "micro_stat_ranged.tga",
                        Spell = "micro_stat_spell.tga", Defense = "micro_stat_defense.tga" }
local function statsData(unit)
    unit = unit or "player"
    local pet = unit == "pet"
    local d = {}
    local function section(key, title, rows)
        if #rows == 0 then return end
        key = (pet and "pet_" or "") .. key
        local col = C.db.collapsed[key]
        table.insert(d, { kind = "header", text = title, collapsed = col, glyph = SECTION_GLYPH[title],
            onClick = function() C.db.collapsed[key] = not col; C:Refresh() end })
        -- Two stats to a line.
        if not col then
            for i = 1, #rows, 2 do table.insert(d, { kind = "pair", a = rows[i], b = rows[i + 1] }) end
        end
    end
    local function stat(rows, label, value, color, tooltip)
        if value ~= nil then
            table.insert(rows, { kind = "stat", label = label, value = value, color = color, tooltip = tooltip })
        end
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
    do
        local lines = {}
        local ap = total(base, pos, neg)
        if plain(ap) then lines[1] = string.format("Adds %.1f damage per second to your melee attacks.", math.max(ap, 0) / 14); lines[2] = "" end
        parts(lines, base, pos, neg)
        stat(rows, "Attack power", fmt(ap, "%d"), buffColor(pos, neg), statTip("Melee attack power", lines))
    end
    local lo, hi, oLo, oHi = call(UnitDamage, unit)
    local speed, oSpeed = call(UnitAttackSpeed, unit)
    if plain(lo, hi) then
        local lines = { "What one swing of your main-hand weapon deals before the target's armor." }
        if plain(speed) and speed > 0 then lines[#lines + 1] = { "Damage per second", string.format("%.1f", (lo + hi) / 2 / speed) } end
        if plain(oLo, oHi, oSpeed) and oSpeed > 0 then
            lines[#lines + 1] = { "Off hand", string.format("%d - %d", oLo, oHi) }
            lines[#lines + 1] = { "Off hand per second", string.format("%.1f", (oLo + oHi) / 2 / oSpeed) }
        end
        stat(rows, "Damage", string.format("%d - %d", lo, hi), nil, statTip("Melee damage", lines))
    end
    do
        local lines = { "Seconds between your main-hand swings." }
        if plain(oSpeed) and oSpeed > 0 then lines[#lines + 1] = { "Off hand", string.format("%.2f", oSpeed) } end
        stat(rows, "Speed", fmt(speed, "%.2f"), nil, statTip("Attack speed", lines))
    end
    if not pet then
        stat(rows, "Crit chance", pct(call(GetCritChance)), nil,
            statTip("Melee critical strike", { "The chance a melee attack lands as a critical strike, for double damage." }))
        local hit = call(GetHitModifier)
        if plain(hit) and hit > 0 then
            stat(rows, "Hit", string.format("+%d%%", hit), nil,
                statTip("Melee hit", { "Taken off your chance to miss with melee and ranged attacks." }))
        end
    end
    section("melee", "Melee", rows)

    if pet then
        rows = {}
        local aBase, armor, _, aPos, aNeg = call(UnitArmor, unit)
        stat(rows, "Armor", fmt(armor, "%d"), buffColor(aPos, aNeg), armorTip(unit, armor, aBase, aPos, aNeg))
        section("defense", "Defense", rows)
        return d
    end

    rows = {}
    local rSpeed, rLo, rHi = call(UnitRangedDamage, "player")
    if plain(rSpeed) and rSpeed > 0 then
        local rb, rp, rn = call(UnitRangedAttackPower, "player")
        do
            local lines = {}
            local ap = total(rb, rp, rn)
            if plain(ap) then lines[1] = string.format("Adds %.1f damage per second to your ranged attacks.", math.max(ap, 0) / 14); lines[2] = "" end
            parts(lines, rb, rp, rn)
            stat(rows, "Attack power", fmt(ap, "%d"), buffColor(rp, rn), statTip("Ranged attack power", lines))
        end
        if plain(rLo, rHi) then
            stat(rows, "Damage", string.format("%d - %d", rLo, rHi), nil, statTip("Ranged damage", {
                "What one shot deals before the target's armor (ammunition included).",
                { "Damage per second", string.format("%.1f", (rLo + rHi) / 2 / rSpeed) } }))
        end
        stat(rows, "Speed", fmt(rSpeed, "%.2f"), nil, statTip("Ranged speed", { "Seconds between your shots." }))
        stat(rows, "Crit chance", pct(call(GetRangedCritChance)), nil,
            statTip("Ranged critical strike", { "The chance a shot lands as a critical strike." }))
    end
    section("ranged", "Ranged", rows)

    rows = {}
    local maxMana = call(UnitPowerMax, "player", 0)
    if not plain(maxMana) or maxMana > 0 then
        local SCHOOLS = { [2] = "Holy", [3] = "Fire", [4] = "Nature", [5] = "Frost", [6] = "Shadow", [7] = "Arcane" }
        local function bySchool(fn, f)
            local lines = {}
            for school = 2, 7 do
                local v = call(fn, school)
                if plain(v) then lines[#lines + 1] = { SCHOOLS[school], string.format(f, v) } end
            end
            return lines
        end
        do
            local lines = bySchool(GetSpellBonusDamage, "%d")
            table.insert(lines, 1, "Added to your damaging spells, in part: the longer the cast, the larger the part.")
            table.insert(lines, 2, "")
            stat(rows, "Bonus damage", fmt(best(GetSpellBonusDamage), "%d"), nil, statTip("Spell damage", lines))
        end
        stat(rows, "Bonus healing", fmt(call(GetSpellBonusHealing), "%d"), nil,
            statTip("Healing", { "Added to your healing spells, in part: the longer the cast, the larger the part." }))
        local sc = best(GetSpellCritChance)
        if sc then
            local lines = bySchool(GetSpellCritChance, "%.2f%%")
            table.insert(lines, 1, "The chance a spell lands as a critical strike.")
            table.insert(lines, 2, "")
            stat(rows, "Crit chance", pct(sc), nil, statTip("Spell critical strike", lines))
        end
        local sh = call(GetSpellHitModifier)
        if plain(sh) and sh > 0 then
            stat(rows, "Hit", string.format("+%d%%", sh), nil, statTip("Spell hit", { "Taken off the chance your spells are resisted outright." }))
        end
        local regen, casting = call(GetManaRegen)
        if plain(regen) then
            local lines = { "Mana you get back every five seconds while you are not casting." }
            if plain(casting) then lines[#lines + 1] = { "While casting", string.format("%d / 5s", casting * 5) } end
            stat(rows, "Mana regen", string.format("%d / 5s", regen * 5), nil, statTip("Mana regeneration", lines))
        end
    end
    section("spell", "Spell", rows)

    rows = {}
    local aBase, armor, _, aPos, aNeg = call(UnitArmor, "player")
    stat(rows, "Armor", fmt(armor, "%d"), buffColor(aPos, aNeg), armorTip("player", armor, aBase, aPos, aNeg))
    -- (This client has no UnitDefense: the row never showed. It is asked as
    -- UnitDefenseSkill here, and failing that read from the Defense skill
    -- line, number 95.)
    local dBase, dMod
    local defFn = _G.UnitDefense or _G.UnitDefenseSkill
    if defFn then dBase, dMod = call(defFn, "player") end
    if not plain(dBase) and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local info = call(C_SkillInfo.GetSkillLineInfoByID, 95)
        if type(info) == "table" then dBase, dMod = info.rank or info.skillRank, info.modifier or info.skillModifier end
    end
    if MinimalUIDB and not MinimalUIDB.defdiag then
        MinimalUIDB.defdiag = "UnitDefense " .. tostring(_G.UnitDefense ~= nil) .. ", UnitDefenseSkill "
            .. tostring(_G.UnitDefenseSkill ~= nil) .. ", read " .. tostring(plain(dBase) and true or false)
    end
    if plain(dBase) then
        local def = dBase + (plain(dMod) and dMod or 0)
        local lines = { "Each point makes you a little harder to hit and to critically hit, and adds to your dodge, parry and block." }
        local lvl = UnitLevel("player")
        if plain(lvl) then
            -- (It read "Against your level (100)   -2", which said little.)
            local full = lvl * 5
            local over = def - full
            lines[#lines + 1] = { "Yours", string.format("%d", def) }
            lines[#lines + 1] = { "Full for level " .. lvl, string.format("%d", full) }
            if over == 0 then
                lines[#lines + 1] = "You are at full: an enemy of your level hits and crits you at the normal rate."
            else
                lines[#lines + 1] = string.format("You are %d %s, so an enemy of your level hits you and crits you %.2f%% %s often than normal.",
                    math.abs(over), over < 0 and "short" or "over", math.abs(over) * 0.04, over < 0 and "more" or "less")
            end
        end
        stat(rows, "Defense", string.format("%d", def), nil, statTip("Defense", lines))
    end
    stat(rows, "Dodge", pct(call(GetDodgeChance)), nil,
        statTip("Dodge", { "The chance a melee attack against you misses entirely. Works from the front and the sides." }))
    local parry, block = call(GetParryChance), call(GetBlockChance)
    if not plain(parry) or parry > 0 then
        stat(rows, "Parry", pct(parry), nil,
            statTip("Parry", { "The chance you turn aside a melee attack from the front, and swing again sooner." }))
    end
    if not plain(block) or block > 0 then
        local lines = { "The chance your shield takes part of a melee hit from the front." }
        local amount = _G.GetShieldBlock and call(GetShieldBlock)
        if plain(amount) and amount > 0 then lines[#lines + 1] = { "Damage blocked", string.format("%d", amount) } end
        stat(rows, "Block", pct(block), nil, statTip("Block", lines))
    end
    section("defense", "Defense", rows)
    return d
end

local RESISTS = {
    -- (Colours from the addon's one list, Theme.lua.)
    { 2, "Fire", ns.SCHOOL[4], "micro_stat_fire.tga" }, { 3, "Nature", ns.SCHOOL[8], "micro_stat_nature.tga" },
    { 4, "Frost", ns.SCHOOL[16], "micro_stat_frost.tga" }, { 5, "Shadow", ns.SCHOOL[32], "micro_stat_shadow.tga" },
    { 6, "Arcane", ns.SCHOOL[64], "micro_stat_arcane.tga" },
}

-- The five primary attributes, as a row of tiles across the top of the stats
-- card: a short colored label over the buffed value (green when raised by
-- buffs or gear effects, red when lowered). Hover for the breakdown.
local ATTRS = {
    { "Str", SPELL_STAT1_NAME or "Strength",  { 0.92, 0.48, 0.38 }, "micro_stat_str.tga" },
    { "Agi", SPELL_STAT2_NAME or "Agility",   { 0.58, 0.85, 0.42 }, "micro_stat_agi.tga" },
    { "Sta", SPELL_STAT3_NAME or "Stamina",   { 0.95, 0.72, 0.32 }, "micro_stat_sta.tga" },
    { "Int", SPELL_STAT4_NAME or "Intellect", { 0.42, 0.66, 1.00 }, "micro_stat_int.tga" },
    { "Spi", SPELL_STAT5_NAME or "Spirit",    { 0.76, 0.62, 0.96 }, "micro_stat_spi.tga" },
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

-- The graph's three shapes. The game gives one bonus per attribute, gear
-- and buffs together; the gear's share is added up here from what is worn
-- (the item's own stats: an enchant counts with the buffs), and the rest is
-- called buffs. Only the player has gear to add up.
local GEAR_KEY = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
                   "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" }
local NO_GEAR = {}
local function updateRadar(card, unit, gearOver)
    local rd = card.radar
    if not rd then return end
    local gear = rd.gear
    for i = 1, 5 do gear[i] = gearOver and gearOver[i] or 0 end
    local getStats = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
    if unit == "player" and getStats and not gearOver then
        for slot = 1, 19 do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local ok, st = pcall(getStats, link)
                if ok and type(st) == "table" then
                    for i = 1, 5 do
                        local v = st[GEAR_KEY[i]]
                        if plain(v) then gear[i] = gear[i] + v end
                    end
                end
            end
        end
    end
    local top, bad = 0, false
    for i, src in ipairs(card.attrs) do
        local tile = card.corners[i]
        tile.bare, tile.gear, tile.buff = nil, nil, nil
        local eff, pos, neg = src.eff, src.pos, src.neg
        tile.eff, tile.pos, tile.neg, tile.unit, tile.index = eff, pos, neg, src.unit, src.index
        -- (Every corner is written before giving up on the shapes: it
        -- used to stop at the first unknown one, and a creature was left
        -- with the numbers of the last player looked at.)
        tile.value:SetText(fmt(eff, "%d") or (unit == "player" and "0" or "?"))
        rd.raw[i], rd.e[i] = eff, nil
        if not (plain(eff) and plain(pos) and plain(neg)) then
            bad = true
        else
            rd.e[i], rd.b[i], rd.g[i], rd.f[i] = eff, math.max(0, eff - pos - neg),
                math.min(math.max(pos, 0), gear[i]), math.max(0, pos - math.min(math.max(pos, 0), gear[i]))
            local bare = math.max(0, eff - pos - neg)
            local g = math.min(math.max(pos, 0), gear[i])
            tile.bare, tile.gear, tile.buff = bare, g, math.max(0, pos - g)
            rd.v[3][i], rd.v[2][i], rd.v[1][i] = bare, bare + g, math.max(0, eff)
            top = math.max(top, eff, bare + g)
        end
    end
    if card.bars then pcall(card.bars.fill, rd, unit) end
    if bad or top <= 0 then rd.shapes:Hide(); card.radarScale:SetText(""); return end
    local scale = math.ceil(top / 10) * 10
    for n = 1, 3 do
        for i = 1, 5 do rd.v[n][i] = math.min(1, rd.v[n][i] / scale) end
        rd.draw(rd.layers[n], rd.v[n])
    end
    card.radarScale:SetText("")
    rd.shapes:Show()
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
    pcall(updateRadar, card, unit or "player")
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

-- ── Statistics ────────────────────────────────────────────────────────────
-- The game's own tallies (creatures killed, deaths, gold, quests...), which
-- this client keeps but shows only inside the achievements window. The
-- categories as the game groups them: a top one as a header, the ones under
-- it as headers set in. A tally the game has nothing for yet ("--") is left
-- out, and a category with nothing left goes with it, unless "Not yet
-- counted" at the bottom is opened. Headers fold (kept in db.collapsed).
local function statisticsData()
    local d = {}
    local cats = call(GetStatisticsCategoryList)
    if type(cats) ~= "table" then return d end
    local showAll = C.db.statsAll and true or false
    local top, kids, hidden = {}, {}, 0
    for _, id in ipairs(cats) do
        local name, parent = call(GetCategoryInfo, id)
        if type(name) == "string" and not secret(name) and plain(parent) then
            if parent == -1 then top[#top + 1] = { id = id, name = name }
            else kids[parent] = kids[parent] or {}; table.insert(kids[parent], { id = id, name = name }) end
        end
    end
    local function rowsOf(id, indent)
        local rows = {}
        local n = call(GetCategoryNumAchievements, id)
        if not plain(n) then return rows end
        for k = 1, n do
            local sid, sname = call(GetAchievementInfo, id, k)
            if sid ~= nil and type(sname) == "string" and not secret(sname) then
                local v = call(GetStatistic, sid)
                local empty = v == nil or (not secret(v) and (v == "--" or v == ""))
                if empty then hidden = hidden + 1 end
                if not empty or showAll then
                    rows[#rows + 1] = { kind = "stat", label = sname, value = empty and "--" or v, indent = indent,
                                        color = empty and T.textDim or nil, labelColor = empty and T.textDim or nil }
                end
            end
        end
        return rows
    end
    local function section(c, indent, glyphless)
        local key = "stat:" .. c.id
        local col = C.db.collapsed[key]
        local own = rowsOf(c.id, indent + 12)
        local subs = {}
        for _, k in ipairs(kids[c.id] or {}) do
            local r = rowsOf(k.id, indent + 24)
            if #r > 0 then subs[#subs + 1] = { c = k, rows = r } end
        end
        if #own == 0 and #subs == 0 then return end
        table.insert(d, { kind = "header", text = c.name, collapsed = col, indent = indent,
            onClick = function() C.db.collapsed[key] = not col; C:Refresh() end })
        if col then return end
        for _, r in ipairs(own) do table.insert(d, r) end
        for _, sub in ipairs(subs) do
            local skey = "stat:" .. sub.c.id
            local scol = C.db.collapsed[skey]
            table.insert(d, { kind = "header", text = sub.c.name, collapsed = scol, indent = indent + 12,
                onClick = function() C.db.collapsed[skey] = not scol; C:Refresh() end })
            if not scol then for _, r in ipairs(sub.rows) do table.insert(d, r) end end
        end
    end
    for _, c in ipairs(top) do section(c, 0) end
    if hidden > 0 then
        table.insert(d, { kind = "header", text = "Not yet counted (" .. hidden .. ")", collapsed = not showAll,
            onClick = function() C.db.statsAll = not showAll; C:Refresh() end })
    end
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
    -- Forever: the mood from the hidden happiness value (see Bars.lua),
    -- the matching word faded in by the client; not happy pulses.
    local curves = not h and ns.PetMoodCurves and ns.PetMoodCurves()
    local shown = false
    if curves then
        shown = pcall(function()
            for i = 1, 3 do ns.PetMoodWord(page.moodWords[i], curves, i) end
        end)
    end
    page.moodBox:SetShown(shown)
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
    { key = "stats", label = "Statistics", kw = { "statistic" },
      available = function() return _G.GetStatistic ~= nil and _G.GetStatisticsCategoryList ~= nil and _G.GetCategoryInfo ~= nil end },
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
local statCards = {} -- (every card made: the graph's style is switched on all of them)
function C.ApplyGraphStyle() for _, c in ipairs(statCards) do c.restyle() end end
local function makeStatsCard(page, top, pageH)
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", page, "TOPLEFT", 440, top)
    card:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 16)
    ns.RoundedRect(card, -6, 0, 10, unpack(CARD))

    -- Attribute tiles: the top row.
    card.attrs = {}
    local TW, TH, TG = 44, 54, 6
    local ATTR_ROW = TH + 8
    local ax0 = (W - 20 - 440) / 2 - (#ATTRS * TW + (#ATTRS - 1) * TG) / 2
    for i, a in ipairs(ATTRS) do
        local tile = CreateFrame("Frame", nil, card)
        tile:SetSize(TW, TH)
        tile:SetPoint("TOPLEFT", card, "TOPLEFT", ax0 + (i - 1) * (TW + TG), -8)
        ns.RoundedRect(tile, -4, 0, 7, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(tile, -3, 1, 6, unpack(FILL))
        -- Its icon in the attribute's colour, the value, a small label.
        local glyph = tile:CreateTexture(nil, "ARTWORK")
        glyph:SetTexture(MEDIA .. a[4])
        glyph:SetSize(17, 17)
        glyph:SetPoint("TOP", 0, -6)
        glyph:SetVertexColor(a[3][1], a[3][2], a[3][3], 1)
        tile.value = text(tile, 13, true)
        tile.value:SetPoint("TOP", glyph, "BOTTOM", 0, -3)
        local label = text(tile, 9, false, T.textDim)
        label:SetPoint("BOTTOM", 0, 5)
        label:SetText(a[1])
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

    -- "Resistances": a divider (icon, word, hairline), then a pill for each
    -- school under the tiles: the school's icon in its colour and the value.
    local divY = -8 - TH - 12
    local dg = card:CreateTexture(nil, "ARTWORK")
    dg:SetTexture(MEDIA .. "micro_stat_resist.tga")
    dg:SetSize(14, 14)
    dg:SetPoint("LEFT", card, "TOPLEFT", ax0, divY)
    dg:SetVertexColor(0.72, 0.72, 0.76, 1)
    local dl = text(card, 10, true, T.textDim)
    dl:SetPoint("LEFT", dg, "RIGHT", 6, 0)
    dl:SetText("Resistances")
    local dr = card:CreateTexture(nil, "ARTWORK")
    dr:SetHeight(1)
    dr:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    dr:SetPoint("LEFT", dl, "RIGHT", 8, 0)
    dr:SetPoint("RIGHT", card, "TOPLEFT", ax0 + #ATTRS * TW + (#ATTRS - 1) * TG, divY)
    card.resistHead = { dg, dl, dr }
    card.resists = {}
    local CH = 20
    for i, r in ipairs(RESISTS) do
        local chip = CreateFrame("Frame", nil, card)
        chip:SetSize(TW, CH)
        chip:SetPoint("TOPLEFT", card, "TOPLEFT", ax0 + (i - 1) * (TW + TG), divY - 12)
        ns.RoundedRect(chip, -4, 0, CH / 2, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(chip, -3, 1, CH / 2 - 1, unpack(FILL))
        local glyph = chip:CreateTexture(nil, "ARTWORK")
        glyph:SetTexture(MEDIA .. r[4])
        glyph:SetSize(13, 13)
        glyph:SetPoint("LEFT", 6, 0)
        glyph:SetVertexColor(r[3][1], r[3][2], r[3][3], 1)
        chip.fs = text(chip, 10, true)
        chip.fs:SetPoint("LEFT", glyph, "RIGHT", 2, 0)
        chip.fs:SetPoint("RIGHT", -5, 0)
        chip.fs:SetJustifyH("CENTER")
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

    local cardW, cardH = W - 20 - 440, (pageH or (H - PAGE_TOP)) + top - 16
    local listTop = 8 + TH + 12 + 12 + CH + 8 + 20 -- tiles, divider, pills, a gap, the view switch
    -- (As wide as the row of tiles, plus the 8 the rows keep clear on the
    -- right for the scroll thumb.)
    local tilesW = #ATTRS * TW + (#ATTRS - 1) * TG
    local listH = cardH - listTop - 6
    card.list = makeList(card, tilesW + 8, listH, 20)
    card.list:SetPoint("TOPLEFT", card, "TOPLEFT", ax0, -listTop)

    -- The five attributes as a graph: a pentagon with a corner for each,
    -- and three shapes drawn one inside the next: what you have with
    -- nothing on (dim), with your gear (silver), and with buffs as well
    -- (the green outline). The gap between two shapes is that bonus. The
    -- outer edge is your highest attribute, rounded up, so the shape shows
    -- how the five compare, not how strong you are. Each corner has the
    -- attribute's icon and its total; hover it for the split. It is the
    -- card's second view, in the list's place: "Details" / "Graph" above
    -- the list switch between them.
    card.corners = {}
    local graph = CreateFrame("Frame", nil, card)
    graph:SetSize(tilesW, listH)
    graph:SetPoint("TOPLEFT", card, "TOPLEFT", ax0, -listTop)
    card.graph = graph
    -- As large as the space allows: how far out the corner labels sit, and
    -- the pentagon's radius inside them.
    local LR = math.max(40, math.min(86, (listH - 36) / 1.81))
    local RR = LR - 22
    local holder = CreateFrame("Frame", nil, graph)
    holder:SetSize(2, 2)
    holder:SetPoint("CENTER", graph, "TOP", 0, -(LR + 18))
    local ux, uy = {}, {}
    for i = 1, 5 do
        local ang = math.rad(90 - (i - 1) * 72)
        ux[i], uy[i] = math.cos(ang), math.sin(ang)
    end
    local function line(layer, sub, r, g, bl, al, thick)
        local l = holder:CreateLine(nil, layer, nil, sub or 0)
        l:SetThickness(thick or 1)
        l:SetColorTexture(r, g, bl, al)
        return l
    end
    local function span(l, x1, y1, x2, y2)
        l:SetStartPoint("CENTER", holder, x1, y1)
        l:SetEndPoint("CENTER", holder, x2, y2)
    end
    -- The grid: three rings and the five spokes.
    for ring = 1, 3 do
        local r = RR * ring / 3
        for i = 1, 5 do
            local j = i % 5 + 1
            span(line("BORDER", 0, T.border[1], T.border[2], T.border[3], ring == 3 and 1 or 0.55),
                r * ux[i], r * uy[i], r * ux[j], r * uy[j])
        end
    end
    for i = 1, 5 do
        span(line("BORDER", 0, T.border[1], T.border[2], T.border[3], 0.55), 0, 0, RR * ux[i], RR * uy[i])
    end
    local BUFF_BLUE = { 0.40, 0.68, 1.00 }
    -- The shapes. A filled wedge is a square texture with its corners
    -- moved: two onto the middle, two onto the shape's corners.
    local BOX = 4
    local shapes = CreateFrame("Frame", nil, holder)
    shapes:SetAllPoints()
    -- Three colours that can be told apart at a glance (gear and base
    -- were two greys): what you are is white, what you wear adds green
    -- (the game's colour for an item's bonus), what is cast on you adds
    -- blue. Each band shows between its own edge and the one inside it.
    local LAYERS = {
        { fill = { BUFF_BLUE[1], BUFF_BLUE[2], BUFF_BLUE[3], 0.34 }, edge = { BUFF_BLUE[1], BUFF_BLUE[2], BUFF_BLUE[3], 0.95 }, sub = 1 }, -- total
        { fill = { GREEN[1], GREEN[2], GREEN[3], 0.36 }, edge = { GREEN[1], GREEN[2], GREEN[3], 0.90 }, sub = 2 },                         -- with gear
        { fill = { 0.60, 0.62, 0.68, 0.62 }, edge = { 0.93, 0.94, 0.97, 0.90 }, sub = 3 },                                                 -- bare
    }
    local canFill = true
    for _, L in ipairs(LAYERS) do
        L.tri, L.line = {}, {}
        for i = 1, 5 do
            local t = shapes:CreateTexture(nil, "BACKGROUND", nil, L.sub)
            t:SetColorTexture(1, 1, 1, 1)
            t:SetVertexColor(L.fill[1], L.fill[2], L.fill[3], L.fill[4])
            t:SetSize(BOX, BOX)
            t:SetPoint("CENTER", holder, "CENTER")
            if not t.SetVertexOffset then canFill = false; t:Hide() end
            L.tri[i] = t
            local l = shapes:CreateLine(nil, "ARTWORK", nil, L.sub)
            l:SetThickness(1.2)
            l:SetColorTexture(L.edge[1], L.edge[2], L.edge[3], L.edge[4])
            L.line[i] = l
        end
    end
    local px, py = {}, {}
    -- vals[layer][i] in 0..1
    local function drawShape(L, v)
        for i = 1, 5 do
            local r = RR * (0.05 + 0.95 * v[i])
            px[i], py[i] = r * ux[i], r * uy[i]
        end
        for i = 1, 5 do
            local j = i % 5 + 1
            L.line[i]:SetStartPoint("CENTER", holder, px[i], py[i])
            L.line[i]:SetEndPoint("CENTER", holder, px[j], py[j])
            if canFill then
                local t, h = L.tri[i], BOX / 2
                t:SetVertexOffset(1, h, -h)                     -- upper left  -> the middle
                t:SetVertexOffset(3, -h, -h)                    -- upper right -> the middle
                t:SetVertexOffset(2, px[i] + h, py[i] + h)      -- lower left  -> one corner
                t:SetVertexOffset(4, px[j] - h, py[j] + h)      -- lower right -> the next
            end
        end
    end
    card.radar = { shapes = shapes, layers = LAYERS, draw = drawShape,
                   v = { {}, {}, {} }, gear = {}, tmp = {},
                   raw = {}, e = {}, b = {}, g = {}, f = {}, you = {} }
    -- What each shape is.
    local LEGEND = { { "Buffs", LAYERS[1].edge }, { "Gear", LAYERS[2].edge }, { "Base", LAYERS[3].edge } }
    for n, e in ipairs(LEGEND) do
        local sw = graph:CreateTexture(nil, "ARTWORK")
        sw:SetColorTexture(e[2][1], e[2][2], e[2][3], 1)
        sw:SetSize(7, 2)
        sw:SetPoint("LEFT", graph, "TOPLEFT", 0, -8 - (n - 1) * 11)
        local fs = text(graph, 9, false, T.textDim)
        fs:SetPoint("LEFT", sw, "RIGHT", 4, 0)
        fs:SetText(e[1])
    end
    card.radarScale = text(graph, 9, false, T.textDim)
    card.radarScale:SetPoint("RIGHT", graph, "TOPRIGHT", 0, -8)
    -- The corners: icon and total, and the hover.
    for i, a in ipairs(ATTRS) do
        local tile = CreateFrame("Frame", nil, graph)
        tile:SetSize(40, 32)
        tile:SetPoint("CENTER", holder, "CENTER", LR * ux[i], LR * uy[i])
        local glyph = tile:CreateTexture(nil, "ARTWORK")
        glyph:SetTexture(MEDIA .. a[4])
        glyph:SetSize(15, 15)
        glyph:SetPoint("TOP", 0, -1)
        glyph:SetVertexColor(a[3][1], a[3][2], a[3][3], 1)
        tile.value = text(tile, 12, true)
        tile.value:SetPoint("TOP", glyph, "BOTTOM", 0, -2)
        tile:EnableMouse(true)
        tile:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(a[2], a[3][1], a[3][2], a[3][3])
            if self.eff ~= nil then GameTooltip:AddLine(fmt(self.eff, "%d"), 1, 1, 1) end
            if plain(self.bare) then
                GameTooltip:AddDoubleLine("Base", string.format("%d", self.bare), 0.6, 0.6, 0.65, 1, 1, 1)
                if self.gear and self.gear > 0 then
                    GameTooltip:AddDoubleLine("From gear", string.format("+%d", self.gear), 0.6, 0.6, 0.65, GREEN[1], GREEN[2], GREEN[3])
                end
                if self.buff and self.buff > 0 then
                    GameTooltip:AddDoubleLine("From buffs", string.format("+%d", self.buff), 0.6, 0.6, 0.65, BUFF_BLUE[1], BUFF_BLUE[2], BUFF_BLUE[3])
                end
            elseif plain(self.pos) and self.pos > 0 then
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
        card.corners[i] = tile
    end

    -- The same as bars (0.1.540, a setting: "Attributes as bars"): a bar
    -- for each attribute, in three lengths end to end (what the class and
    -- race have, what the gear adds, what buffs add), all five to one
    -- scale, with the total at the end and the parts spelled out under it.
    -- An attribute the class has little use for is dimmed. On someone
    -- else's card a tick on each bar marks where your own stands.
    local bars = CreateFrame("Frame", nil, card)
    bars:SetSize(tilesW, listH)
    bars:SetPoint("TOPLEFT", card, "TOPLEFT", ax0, -listTop)
    bars.rows = {}
    local ROW = math.min(46, math.floor((listH - 16) / 5))
    local BAR_Y, BAR_H = 19, 6
    local SEG = { { 0.82, 0.84, 0.88, 0.95 }, { GREEN[1], GREEN[2], GREEN[3], 0.95 }, { BUFF_BLUE[1], BUFF_BLUE[2], BUFF_BLUE[3], 0.95 } }
    for i, a in ipairs(ATTRS) do
        local r = CreateFrame("Frame", nil, bars)
        r:SetSize(tilesW, ROW)
        r:SetPoint("TOPLEFT", bars, "TOPLEFT", 0, -(i - 1) * ROW)
        local glyph = r:CreateTexture(nil, "ARTWORK")
        glyph:SetTexture(MEDIA .. a[4])
        glyph:SetSize(14, 14)
        glyph:SetPoint("TOPLEFT", 0, -1)
        glyph:SetVertexColor(a[3][1], a[3][2], a[3][3], 1)
        local name = text(r, 10, true, T.textDim)
        name:SetPoint("LEFT", glyph, "RIGHT", 5, 0)
        name:SetText(a[2])
        r.total = text(r, 12, true)
        r.total:SetPoint("TOPRIGHT", 0, -1)
        local track = r:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(1, 1, 1, 0.07)
        track:SetHeight(BAR_H)
        track:SetPoint("TOPLEFT", 0, -BAR_Y)
        track:SetPoint("TOPRIGHT", 0, -BAR_Y)
        r.seg = {}
        for n = 1, 3 do
            local t = r:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(SEG[n][1], SEG[n][2], SEG[n][3], SEG[n][4])
            t:SetHeight(BAR_H)
            t:Hide()
            r.seg[n] = t
        end
        r.you = r:CreateTexture(nil, "OVERLAY")
        r.you:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        r.you:SetSize(2, BAR_H + 6)
        r.you:Hide()
        r.sub = text(r, 9, false, T.textDim)
        r.sub:SetPoint("TOPLEFT", 0, -(BAR_Y + BAR_H + 3))
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(a[2], a[3][1], a[3][2], a[3][3])
            if self.e then
                GameTooltip:AddDoubleLine("Base", string.format("%d", self.b), 0.6, 0.6, 0.65, 1, 1, 1)
                if self.g > 0 then GameTooltip:AddDoubleLine("From gear", string.format("+%d", self.g), 0.6, 0.6, 0.65, GREEN[1], GREEN[2], GREEN[3]) end
                if self.f > 0 then GameTooltip:AddDoubleLine("From buffs", string.format("+%d", self.f), 0.6, 0.6, 0.65, BUFF_BLUE[1], BUFF_BLUE[2], BUFF_BLUE[3]) end
                if self.mine then GameTooltip:AddDoubleLine("Yours (the tick)", string.format("%d", self.mine), 0.6, 0.6, 0.65, T.accent[1], T.accent[2], T.accent[3]) end
            else
                GameTooltip:AddLine("Not known.", 0.6, 0.6, 0.65)
            end
            if self.dimmed then GameTooltip:AddLine("Of little use to this class.", 0.6, 0.6, 0.65) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bars.rows[i] = r
    end
    function bars.fill(rd, unit)
        local other = unit ~= "player"
        local top = 0
        for i = 1, 5 do
            local e = rd.e[i]
            if e and e > top then top = e end
            rd.you[i] = nil
            if other then
                local _, mine = call(UnitStat, "player", i)
                if plain(mine) then
                    rd.you[i] = mine
                    if mine > top then top = mine end
                end
            end
        end
        local scale = top > 0 and math.ceil(top / 10) * 10 or 1
        local _, class = UnitClass(unit)
        local w = ns.StatWeights and type(class) == "string" and not secret(class) and ns.StatWeights[class]
        for i, r in ipairs(bars.rows) do
            local e = rd.e[i]
            r.e, r.b, r.g, r.f, r.mine = e, rd.b[i], rd.g[i], rd.f[i], rd.you[i]
            r.dimmed = w and w[i] < 0.3 or false
            r:SetAlpha(r.dimmed and 0.45 or 1)
            if not e then
                r.total:SetText(fmt(rd.raw[i], "%d") or "?")
                r.sub:SetText("")
                for n = 1, 3 do r.seg[n]:Hide() end
                r.you:Hide()
            else
                local x = 0
                for n = 1, 3 do
                    local v = (n == 1 and r.b) or (n == 2 and r.g) or r.f
                    local px = v / scale * tilesW
                    local t = r.seg[n]
                    if px >= 0.5 then
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", r, "TOPLEFT", x, -BAR_Y)
                        t:SetWidth(px)
                        t:Show()
                        x = x + px
                    else
                        t:Hide()
                    end
                end
                -- (Someone whose base is not known: what is shown is only
                -- what their gear and buffs add.)
                r.total:SetText((other and r.b == 0 and e > 0) and ("+" .. e) or string.format("%d", e))
                local parts = r.b > 0 and (r.b .. " base") or ""
                if r.g > 0 then parts = parts .. (parts ~= "" and "   " or "") .. "+" .. r.g .. " gear" end
                if r.f > 0 then parts = parts .. (parts ~= "" and "   " or "") .. "+" .. r.f .. " buffs" end
                r.sub:SetText(parts)
                if r.mine then
                    r.you:ClearAllPoints()
                    r.you:SetPoint("CENTER", r, "TOPLEFT", r.mine / scale * tilesW, -(BAR_Y + BAR_H / 2))
                    r.you:Show()
                else
                    r.you:Hide()
                end
            end
        end
    end
    card.bars = bars

    -- The switch between the two views.
    local tabs = {}
    local function setView(v)
        if C.db then C.db.statsView = v end
        card.view = v
        local isGraph = v == "graph"
        local asBars = C.db and C.db.graphBars and true or false
        graph:SetShown(isGraph and not asBars)
        bars:SetShown(isGraph and asBars)
        card.list:SetShown(not isGraph)
        for key, t in pairs(tabs) do
            local on = key == v
            local c = on and T.text or T.textDim
            t.fs:SetTextColor(c[1], c[2], c[3])
            t.bar:SetShown(on)
        end
    end
    local tx = ax0
    for _, def in ipairs({ { "details", "Details" }, { "graph", "Graph" } }) do
        local t = CreateFrame("Button", nil, card)
        t.fs = text(t, 10, true, T.textDim)
        t.fs:SetPoint("LEFT")
        t.fs:SetText(def[2])
        t:SetSize(math.max(30, (t.fs:GetStringWidth() or 30)) + 2, 16)
        t:SetPoint("TOPLEFT", card, "TOPLEFT", tx, -(listTop - 20))
        t.bar = t:CreateTexture(nil, "ARTWORK")
        t.bar:SetHeight(1)
        t.bar:SetColorTexture(T.text[1], T.text[2], T.text[3], 0.8)
        t.bar:SetPoint("BOTTOMLEFT", 0, 0)
        t.bar:SetPoint("BOTTOMRIGHT", -2, 0)
        t:SetScript("OnClick", function() setView(def[1]) end)
        tabs[def[1]] = t
        t.x = tx
        tx = tx + t:GetWidth() + 12
    end
    setView(C.db and C.db.statsView == "graph" and "graph" or "details")
    card.restyle = function() setView(card.view or "details") end
    statCards[#statCards + 1] = card

    -- Without the resistances (someone else's card, when there is nothing
    -- to be known of theirs): the row goes and what is under it moves up.
    function card.setResists(on)
        on = on and true or false
        if card.resistsOn == on then return end
        card.resistsOn = on
        for _, o in ipairs(card.resistHead) do o:SetShown(on) end
        for _, chip in ipairs(card.resists) do chip:SetShown(on) end
        local up = on and 0 or (12 + CH + 12)
        card.list:SetPoint("TOPLEFT", card, "TOPLEFT", ax0, -(listTop - up))
        graph:SetPoint("TOPLEFT", card, "TOPLEFT", ax0, -(listTop - up))
        bars:SetPoint("TOPLEFT", card, "TOPLEFT", ax0, -(listTop - up))
        for _, t in pairs(tabs) do t:SetPoint("TOPLEFT", card, "TOPLEFT", t.x, -(listTop - 20 - up)) end
    end

    return card
end

-- The same card for someone else (the inspect window, 0.1.533): the tiles,
-- the resistances and the graph, with the list under "Details" filled by
-- the caller. The game's own numbers are used where it gives them for the
-- unit; else base[i] (what their class and race have at that level, where
-- known) plus gear[i] (added up from what they wear); gear alone shows as
-- "+12"; with neither, "?".
C.CARD_W = W - 20 - 440
function C.MakeStatsCard(page, top, pageH) return makeStatsCard(page, top, pageH) end
-- Resistances: the game's number where it gives one above nothing, else
-- res[school] (from their gear); with neither, the row is hidden.
-- buff[i]: what their buffs add to an attribute (read from the buffs' own
-- tooltips by the caller); it goes on top and shows as the graph's blue.
function C.FillOtherCard(card, unit, base, gear, rows, res, buff)
    for i, tile in ipairs(card.attrs) do
        local b0, eff, pos, neg = call(UnitStat, unit, i)
        local col = T.text
        if plain(eff) and eff > 0 then
            col = buffColor(pos, neg) or T.text
            tile.value:SetText(string.format("%d", eff))
        else
            local g, b = gear and gear[i], base and base[i]
            local bf = buff and buff[i] or 0
            if bf > 0 then g = (g or 0) + bf end
            if b then
                b0, eff, pos, neg = b, b + (g or 0), g or 0, 0
                tile.value:SetText(string.format("%d", eff))
            elseif g then
                b0, eff, pos, neg = nil, g, g, 0
                tile.value:SetText("+" .. g)
                col = g > 0 and GREEN or T.textDim
            else
                b0, eff, pos, neg = nil, nil, nil, nil
                tile.value:SetText("?")
                col = T.textDim
            end
        end
        tile.base, tile.eff, tile.pos, tile.neg, tile.unit, tile.index = b0, eff, pos, neg, unit, i
        tile.value:SetTextColor(col[1], col[2], col[3])
        tile:Show()
    end
    pcall(updateRadar, card, unit, gear or NO_GEAR)
    local anyRes = res ~= nil
    for _, chip in ipairs(card.resists) do
        local _, total = call(UnitResistance, unit, chip.school)
        if plain(total) and total > 0 then anyRes = true
        else total = res and res[chip.school] or 0 end
        chip.value = total
        chip.fs:SetText(string.format("%d", total))
    end
    card.setResists(anyRes)
    card.list:SetData(rows)
end

local function buildGear(page)
    local top = -4
    for i, s in ipairs(LEFT_SLOTS) do
        local b = makeTile(page, s)
        if b then b.side = "left"; b:SetPoint("TOPLEFT", page, "TOPLEFT", 20, top - (i - 1) * (TILE + GAP)) end
    end
    for i, s in ipairs(RIGHT_SLOTS) do
        local b = makeTile(page, s)
        if b then b.side = "right"; b:SetPoint("TOPLEFT", page, "TOPLEFT", 420 - TILE, top - (i - 1) * (TILE + GAP)) end
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

    -- "Next upgrade" (gearAdvice, applyAdvice): the icon that sits beside
    -- the slot, over the model's edge.
    local nx = CreateFrame("Button", nil, page)
    nx:SetSize(20, 20)
    nx:SetFrameLevel(win.model:GetFrameLevel() + 5)
    local rim = nx:CreateTexture(nil, "ARTWORK", nil, 0)
    rim:SetTexture(MEDIA .. "circle.tga")
    rim:SetVertexColor(0.04, 0.04, 0.05, 1)
    rim:SetAllPoints()
    local disc = nx:CreateTexture(nil, "ARTWORK", nil, 1)
    disc:SetTexture(MEDIA .. "circle.tga")
    disc:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    disc:SetPoint("TOPLEFT", 1.5, -1.5)
    disc:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    local arrow = nx:CreateTexture(nil, "ARTWORK", nil, 2)
    arrow:SetTexture(MEDIA .. "micro_up.tga")
    arrow:SetVertexColor(0.05, 0.05, 0.06, 1)
    arrow:SetPoint("TOPLEFT", 3, -3)
    arrow:SetPoint("BOTTOMRIGHT", -3, 3)
    nx:SetScript("OnEnter", function(self)
        local adv = self.adv
        local t = adv and adv.top
        if not t then return end
        local W1, DIMC, BODYC = { 1, 1, 1 }, { 0.6, 0.6, 0.65 }, { 0.86, 0.86, 0.89 }
        local par = math.floor(adv.par + 0.5)
        local function line(e)
            if e.empty then return "nothing worn" end
            local d = math.floor(e.gap + 0.5)
            return "item level " .. string.format("%d", e.lvl) .. (d > 0 and ("  (" .. d .. " below)") or "")
        end
        ns.TipAnchor(self)
        GameTooltip:SetText("Next upgrade: " .. t.label, W1[1], W1[2], W1[3])
        if t.empty then
            GameTooltip:AddLine("Nothing is worn in this slot.", BODYC[1], BODYC[2], BODYC[3], true)
        else
            GameTooltip:AddDoubleLine("This piece's item level", string.format("%d", t.lvl), BODYC[1], BODYC[2], BODYC[3], BEHIND[1], BEHIND[2], BEHIND[3])
        end
        GameTooltip:AddDoubleLine(t.against == "your level" and "Your level" or "Your gear's average item level", tostring(par),
            BODYC[1], BODYC[2], BODYC[3], 1, 1, 1)
        if not t.empty then
            local d = math.floor(t.gap + 0.5)
            GameTooltip:AddDoubleLine(d >= 0 and "Behind by" or "Ahead by", tostring(math.abs(d)), BODYC[1], BODYC[2], BODYC[3], BEHIND[1], BEHIND[2], BEHIND[3])
        end
        if adv.favour and adv.favour ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("You gear for", adv.favour, BODYC[1], BODYC[2], BODYC[3], 1, 1, 1)
            if t.ratio then
                local how = t.ratio < 0.4 and "almost none" or (t.ratio < 0.7 and "less than your usual")
                    or (t.ratio > 1.2 and "more than your usual") or "about your usual"
                GameTooltip:AddDoubleLine("This piece has of those", how, BODYC[1], BODYC[2], BODYC[3],
                    t.ratio < 0.7 and BEHIND[1] or 1, t.ratio < 0.7 and BEHIND[2] or 1, t.ratio < 0.7 and BEHIND[3] or 1)
            end
        end
        local shown = 0
        for i = 2, #adv.list do
            local e = adv.list[i]
            if shown >= 3 or e.score < 2 then break end
            if shown == 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("After that", DIMC[1], DIMC[2], DIMC[3])
            end
            shown = shown + 1
            GameTooltip:AddDoubleLine(e.label, line(e), BODYC[1], BODYC[2], BODYC[3], BODYC[1], BODYC[2], BODYC[3])
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("\"Below\" is how far a piece's item level is under "
            .. (t.against == "your level"
                and ("your level (" .. par .. "), used because your gear's average (" .. math.floor(adv.avg + 0.5) .. ") is lower still.")
                or ("the average of everything you wear (" .. par .. ")."))
            .. " Slots that hold more stats count for more (weapon, then chest, legs and head)"
            .. (adv.favour and adv.favour ~= "" and ", and armour with little of the stats you gear for (read off what you wear) counts as lower than its item level" or "")
            .. ", so the pick is not always the lowest number.",
            DIMC[1], DIMC[2], DIMC[3], true)
        GameTooltip:Show()
    end)
    nx:SetScript("OnLeave", function() GameTooltip:Hide() end)
    nx:Hide()
    win.nextIcon = nx
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
    -- Mood words, stacked in one place (only the matching one is visible).
    local box = CreateFrame("Frame", nil, page)
    box:SetSize(200, 16)
    box:SetPoint("TOP", page, "TOPLEFT", 220, -340)
    local pulse = CreateFrame("Frame", nil, box)
    pulse:SetAllPoints()
    local pag = pulse:CreateAnimationGroup()
    pag:SetLooping("BOUNCE")
    local pa = pag:CreateAnimation("Alpha")
    pa:SetFromAlpha(1); pa:SetToAlpha(0.25); pa:SetDuration(0.6); pa:SetSmoothing("IN_OUT")
    box:SetScript("OnShow", function() pag:Play() end)
    page.moodWords = {}
    for i, m in ipairs(ns.PET_MOOD or HAPPINESS) do
        local label = type(m[1]) == "string" and m[1] or HAPPINESS[i][1]
        local wf = CreateFrame("Frame", nil, i == 3 and box or pulse)
        wf:SetAllPoints(box)
        local fs = text(wf, 12, true)
        fs:SetPoint("CENTER")
        fs:SetText(label)
        fs:SetTextColor(0, 0, 0, 0)
        fs:SetShadowOffset(0, 0)
        page.moodWords[i] = fs
    end
    box:Hide()
    page.moodBox = box
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
    for _, k in ipairs({ "rep", "skills", "currency", "honor", "stats" }) do buildListPage(pages[k]) end

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

local LIST_DATA = { rep = repData, skills = skillsData, currency = currencyData, honor = honorData, stats = statisticsData }

function C:Refresh()
    if not win or not win:IsShown() then return end
    for _, b in ipairs(tiles) do pcall(updateTile, b) end
    pcall(updateHeader)
    pcall(applyAdvice)
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
            -- (Feed Pet wants food from your bags, not gear: the bags open.)
            if ok and want and not (ns.IsFeedingPet and ns.IsFeedingPet()) then
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