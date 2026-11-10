local _, ns = ...
local T = ns.Theme

-- Loot: MinimalUI's loot window and group loot rolls.
--   window  a compact card (at the cursor with Loot Under Mouse on): small noise band ("Loot", source
--           name, close), item rows with quality-ringed icons, counts, a
--           quest marker; click to loot, shift-click to link
--   rolls   cards stacked above the action bars: item, a draining timer,
--           Need / Greed / Pass pills (only the rolls you're allowed)
-- Blizzard's loot frame stops listening for loot events; its roll frames are
-- hidden as they appear. Blizzard's confirmation popups (bind on pickup,
-- etc.) still show as usual.

local L = ns:NewModule("Loot", { enabled = true })

local MEDIA = "Interface/AddOns/MinimalUI/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local BAND = { 0.095, 0.10, 0.11, 1 }
local CARD = { 0.10, 0.10, 0.115, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local GOLD = { 1.0, 0.82, 0.25, 1 }
local LOOT_W, ROW_H = 250, 40

local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local function qualityColor(q)
    local c = type(q) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function noiseBand(parent, h)
    local band = CreateFrame("Frame", nil, parent)
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(h)
    ns.RoundedRect(band, -6, 0, 11, unpack(BAND))
    local sq = band:CreateTexture(nil, "BACKGROUND", nil, -5)
    sq:SetPoint("BOTTOMLEFT"); sq:SetPoint("BOTTOMRIGHT"); sq:SetHeight(12)
    sq:SetColorTexture(unpack(BAND))
    local noise = band:CreateTexture(nil, "BACKGROUND", nil, -4)
    noise:SetPoint("TOPLEFT", 6, -2); noise:SetPoint("BOTTOMRIGHT", -6, 0)
    noise:SetTexture(MEDIA .. "noise.tga", "REPEAT", "REPEAT")
    noise:SetHorizTile(true); noise:SetVertTile(true)
    noise:SetVertexColor(1, 1, 1, 0.07)
    local line = band:CreateTexture(nil, "BORDER")
    line:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
    return band
end

local function closeX(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    local m = b:CreateMaskTexture()
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetSize(18, 18); m:SetPoint("CENTER")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(18, 18); bg:SetPoint("CENTER")
    bg:SetColorTexture(0.16, 0.16, 0.18, 1)
    bg:AddMaskTexture(m)
    local xs = {}
    for i, p in ipairs({ { -1, 1, 1, -1 }, { -1, -1, 1, 1 } }) do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.4)
        l:SetStartPoint("CENTER", b, p[1] * 3.5, p[2] * 3.5)
        l:SetEndPoint("CENTER", b, p[3] * 3.5, p[4] * 3.5)
        l:SetColorTexture(unpack(T.textDim))
        xs[i] = l
    end
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(unpack(T.accent)); for _, l in ipairs(xs) do l:SetColorTexture(unpack(TEXT_DARK)) end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(0.16, 0.16, 0.18, 1); for _, l in ipairs(xs) do l:SetColorTexture(unpack(T.textDim)) end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function iconBox(parent, size)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(size, size)
    box.ring = ns.RoundedRect(box, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    local mask = box:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2); mask:SetPoint("BOTTOMRIGHT", -2, 2)
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetAllPoints(mask)
    box.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.icon:AddMaskTexture(mask)
    box.count = box:CreateFontString(nil, "OVERLAY")
    ns:SetFont(box.count, 10, "OUTLINE", true)
    box.count:SetPoint("BOTTOMRIGHT", -2, 2)
    return box
end

local PILL_OPTS = { h = 22, pad = 24, minW = 56 }
local function pill(parent, label, onClick)
    return ns.Pill(parent, label, onClick, PILL_OPTS)
end

-- ── Loot window ───────────────────────────────────────────────────────────
local win, rows = nil, {}
local closing = false

local function buildLoot()
    win = CreateFrame("Frame", "MinimalUILoot", UIParent)
    win:SetWidth(LOOT_W)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Remembered only for the fixed spot (Loot Under Mouse off).
        local p, _, rp, x, y = self:GetPoint(1)
        L.db.pos = { p, rp, x, y }
    end)
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUILoot")
    ns.RoundedRect(win, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 11, unpack(FILL))
    local band = noiseBand(win, 38)
    win.title = text(band, 13, true)
    win.title:SetPoint("LEFT", 14, 0)
    win.title:SetPoint("RIGHT", -36, 0)
    win.title:SetJustifyH("LEFT")
    win.title:SetWordWrap(false)
    local x = closeX(band, function() win:Hide() end)
    x:SetPoint("RIGHT", -10, 0)
    win:SetScript("OnHide", function()
        if not closing then call(CloseLoot) end
    end)
end

local function lootRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, win)
    r:SetSize(LOOT_W - 16, ROW_H - 4)
    r.ring = ns.RoundedRect(r, -8, 0, 9, T.border[1], T.border[2], T.border[3], 1)
    r.fill = ns.RoundedRect(r, -7, 1, 8, unpack(CARD))
    r.box = iconBox(r, ROW_H - 10)
    r.box:SetPoint("LEFT", 3, 0)
    r.name = text(r, 12)
    r.name:SetPoint("LEFT", r.box, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", -24, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.quest = text(r, 14, true, GOLD)
    r.quest:SetPoint("RIGHT", -10, 0)
    r.quest:SetText("!")
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnEnter", function(self)
        self.ring(unpack(T.accent)); self.fill(0.13, 0.13, 0.15, 1)
        ns.TipAnchor(self)
        if self.slot and not pcall(GameTooltip.SetLootItem, GameTooltip, self.slot) then GameTooltip:Hide() return end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self.ring(self.rr, self.rg, self.rb, 1); self.fill(unpack(CARD)); GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        if IsModifiedClick() then
            local link = call(GetLootSlotLink, self.slot)
            if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
        end
        call(LootSlot, self.slot)
    end)
    rows[i] = r
    return r
end

local function fillLoot()
    local n = call(GetNumLootItems) or 0
    local shown = 0
    for slot = 1, n do
        local tex, item, qty, _, quality, locked, isQuest = call(GetLootSlotInfo, slot)
        if tex then
            shown = shown + 1
            local r = lootRow(shown)
            r.slot = slot
            r.box.icon:SetTexture(tex)
            r.box.icon:SetDesaturated(locked and true or false)
            r.box.count:SetText(type(qty) == "number" and qty > 1 and qty or "")
            local cr, cg, cb = qualityColor(quality)
            r.name:SetText(item or "")
            r.name:SetTextColor(cr, cg, cb)
            local q = type(quality) == "number" and quality >= 2
            r.rr, r.rg, r.rb = q and cr * 0.7 or T.border[1], q and cg * 0.7 or T.border[2], q and cb * 0.7 or T.border[3]
            r.ring(r.rr, r.rg, r.rb, 1)
            r.box.ring(q and cr or T.border[1], q and cg or T.border[2], q and cb or T.border[3], 1)
            r.quest:SetShown(isQuest and true or false)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -(38 + 8 + (shown - 1) * ROW_H))
            r:Show()
        end
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    win:SetHeight(38 + 8 + shown * ROW_H + 6)
    return shown
end

local function sourceName()
    local n = UnitExists("target") and UnitIsDead("target") and UnitName("target")
    if n and not secret(n) then return n end
    return LOOT or "Loot"
end

local function openLoot(autoLoot)
    if not win then buildLoot() end
    win.title:SetText(sourceName())
    local function show()
        if (call(GetNumLootItems) or 0) == 0 then return end
        if fillLoot() == 0 then return end
        if not win:IsShown() then
            win:ClearAllPoints()
            local under = GetCVarBool and GetCVarBool("lootUnderMouse")
            if under then
                -- Loot Under Mouse: open at the cursor, first row under the pointer.
                local x, y = GetCursorPosition()
                local s = UIParent:GetEffectiveScale()
                win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 40, y / s + 52)
            else
                -- Fixed spot: where you last dragged it, else Blizzard's (left side).
                local pos = L.db.pos
                if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
                else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -160) end
            end
            win:Show()
        end
    end
    -- With auto-loot the window usually empties at once; don't flash it.
    if autoLoot then C_Timer.After(0.25, function() if L.lootOpen then show() end end) else show() end
end

local function closeLootWindow()
    if win and win:IsShown() then
        closing = true
        win:Hide()
        closing = false
    end
end

-- ── Group loot rolls ──────────────────────────────────────────────────────
local rollCards, holder = {}, nil
local ROLL_W, ROLL_H = 320, 66

local function layoutRolls()
    local i = 0
    for _, c in ipairs(rollCards) do
        if c:IsShown() then
            c:ClearAllPoints()
            c:SetPoint("BOTTOM", holder, "BOTTOM", 0, i * (ROLL_H + 8))
            i = i + 1
        end
    end
end

local function rollCard()
    for _, c in ipairs(rollCards) do if not c:IsShown() then return c end end
    local c = CreateFrame("Frame", nil, holder)
    c:SetSize(ROLL_W, ROLL_H)
    c:EnableMouse(true)
    c.ringPaint = ns.RoundedRect(c, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(c, -7, 1, 11, unpack(FILL))
    c.box = iconBox(c, 40)
    c.box:SetPoint("TOPLEFT", 10, -10)
    c.box:EnableMouse(true)
    c.box:SetScript("OnEnter", function(self)
        ns.TipAnchor(self)
        pcall(GameTooltip.SetLootRollItem, GameTooltip, c.rollID)
        GameTooltip:Show()
    end)
    c.box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.name = text(c, 12, true)
    c.name:SetPoint("TOPLEFT", c.box, "TOPRIGHT", 10, -2)
    c.name:SetPoint("RIGHT", c, "RIGHT", -10, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.bind = text(c, 10, false, T.textDim)
    c.bind:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -2)
    -- Timer: a thin bar draining along the bottom.
    c.track = c:CreateTexture(nil, "ARTWORK")
    c.track:SetPoint("BOTTOMLEFT", 10, 8)
    c.track:SetPoint("BOTTOMRIGHT", -10, 8)
    c.track:SetHeight(3)
    c.track:SetColorTexture(0.16, 0.16, 0.18, 1)
    c.timer = c:CreateTexture(nil, "ARTWORK", nil, 1)
    c.timer:SetPoint("BOTTOMLEFT", c.track, "BOTTOMLEFT")
    c.timer:SetHeight(3)
    c.timer:SetColorTexture(unpack(T.accent))
    local function roll(kind)
        return function()
            call(RollOnLoot, c.rollID, kind)
            c:Hide(); layoutRolls()
        end
    end
    c.pass = pill(c, PASS or "Pass", roll(0))
    c.pass:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -10, 16)
    c.greed = pill(c, GREED or "Greed", roll(2))
    c.greed:SetPoint("RIGHT", c.pass, "LEFT", -6, 0)
    c.need = pill(c, NEED or "Need", roll(1))
    c.need:SetPoint("RIGHT", c.greed, "LEFT", -6, 0)
    c.need.primary = true
    c:SetScript("OnUpdate", function(self)
        local left = call(GetLootRollTimeLeft, self.rollID)
        if type(left) ~= "number" or not self.total or self.total <= 0 then return end
        local w = (ROLL_W - 20) * math.max(0, math.min(1, left / self.total))
        self.timer:SetWidth(math.max(1, w))
        if left <= 0 then self:Hide(); layoutRolls() end
    end)
    table.insert(rollCards, c)
    return c
end

local function startRoll(rollID, rollTime)
    if not holder then
        holder = CreateFrame("Frame", "MinimalUILootRolls", UIParent)
        holder:SetSize(ROLL_W, 10)
        holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 250)
        holder:SetFrameStrata("DIALOG")
    end
    local tex, name, count, quality, bop, canNeed, canGreed = call(GetLootRollItemInfo, rollID)
    if not tex then return end
    local c = rollCard()
    -- rollTime and GetLootRollTimeLeft are both milliseconds.
    c.rollID, c.total = rollID, rollTime or 60000
    c.box.icon:SetTexture(tex)
    c.box.count:SetText(type(count) == "number" and count > 1 and count or "")
    local r, g, b = qualityColor(quality)
    c.name:SetText(name or "")
    c.name:SetTextColor(r, g, b)
    c.box.ring(r, g, b, 1)
    c.ringPaint(r * 0.55, g * 0.55, b * 0.55, 1)
    c.bind:SetText(bop and "Binds when picked up" or "")
    c.need:SetEnabled(canNeed ~= false)
    c.greed:SetEnabled(canGreed ~= false)
    c:Show()
    layoutRolls()
end

local function cancelRoll(rollID)
    for _, c in ipairs(rollCards) do
        if c:IsShown() and c.rollID == rollID then c:Hide() end
    end
    layoutRolls()
end

-- ── Wiring ────────────────────────────────────────────────────────────────
function L:OnInit(db)
    self.db = db
    -- Blizzard's loot window stops listening; ours handles loot events.
    local lf = _G.LootFrame
    if lf then
        for _, e in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED", "LOOT_READY" }) do
            pcall(lf.UnregisterEvent, lf, e)
        end
    end
    -- Blizzard's roll frames: hidden as they appear.
    local i = 1
    while _G["GroupLootFrame" .. i] do
        local f = _G["GroupLootFrame" .. i]
        f:HookScript("OnShow", function(self) self:SetAlpha(0); self:EnableMouse(false); self:Hide() end)
        i = i + 1
    end
    if _G.GroupLootContainer then
        GroupLootContainer:SetAlpha(0)
        GroupLootContainer:EnableMouse(false)
    end

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED",
                         "START_LOOT_ROLL", "CANCEL_LOOT_ROLL" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e, a1, a2)
        if e == "LOOT_OPENED" then
            L.lootOpen = true
            openLoot(a1)
        elseif e == "LOOT_SLOT_CLEARED" or e == "LOOT_SLOT_CHANGED" then
            if win and win:IsShown() then
                if fillLoot() == 0 then closeLootWindow() end
            end
        elseif e == "LOOT_CLOSED" then
            L.lootOpen = false
            closeLootWindow()
        elseif e == "START_LOOT_ROLL" then
            startRoll(a1, a2)
        elseif e == "CANCEL_LOOT_ROLL" then
            cancelRoll(a1)
        end
    end)
end

-- /mui testroll : preview a roll card (uses your first bag item's look).
ns.commands.testroll = function()
    if not holder then
        holder = CreateFrame("Frame", "MinimalUILootRolls", UIParent)
        holder:SetSize(ROLL_W, 10)
        holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 250)
        holder:SetFrameStrata("DIALOG")
    end
    local c = rollCard()
    c.rollID, c.total = -1, 20
    c.box.icon:SetTexture("Interface/Icons/INV_Sword_04")
    c.name:SetText("Test Blade of Rolling")
    c.name:SetTextColor(0.12, 1, 0)
    c.box.ring(0.12, 1, 0, 1)
    c.ringPaint(0.07, 0.55, 0, 1)
    c.bind:SetText("Preview")
    c.need:SetEnabled(true); c.greed:SetEnabled(true)
    c:Show()
    layoutRolls()
    C_Timer.After(20, function() if c.rollID == -1 then c:Hide(); layoutRolls() end end)
end
