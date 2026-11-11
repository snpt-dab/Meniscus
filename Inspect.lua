local _, ns = ...
local T = ns.Theme

-- Inspect: Meniscus's inspect window, the character window's look for
-- someone else. Shared header (their 3D head, class-colored name, "Level 60
-- Race Class · Guild", item level chip) and gear tiles around a
-- drag-to-rotate model.
-- Blizzard's inspect frame stays open but invisible: closing it clears the
-- inspect data. Closing ours closes it.

local I = ns:NewModule("Inspect", { enabled = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local PAGE_TOP = (ns.SHELL_H or 92) + 16
local TILE, GAP = 38, 6
local GEAR_W = 380
local W = GEAR_W + 20
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

-- ── Window ────────────────────────────────────────────────────────────────
local win, tiles = nil, {}
local closing = false

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
    for _, b in pairs(tiles) do
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
    win:SetSize(W, H)
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

    win:SetScript("OnHide", function()
        win.shell:ClearModel()
        win.model:ClearModel()
        local f = _G.InspectFrame
        if not closing and f and f:IsShown() then HideUIPanel(f) end
    end)
end

local function open(unit)
    if not unit or not UnitExists(unit) then return end
    if not win then build() end
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
                         "UNIT_MODEL_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local dirty, acc = false, 0
    ev:SetScript("OnEvent", function(_, e, arg)
        if e == "ADDON_LOADED" then hookFrame(); return end
        if not win or not win:IsShown() then return end
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
end
