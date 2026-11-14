local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Loot: Meniscus's loot window and group loot rolls.
--   window  a compact card (at the cursor with Loot Under Mouse on): small noise band ("Loot", source
--           name, close), item rows with quality-ringed icons, counts, a
--           quest marker; click to loot, shift-click to link
--   rolls   cards stacked above the action bars: item, a draining timer,
--           Need / Greed / Pass pills (only the rolls you're allowed)
--   text    what you take floats up from above the minimap and fades: icon,
--           name in its quality colour, count; coins too. With auto-loot
--           this is all you see, unless something is left on the corpse
--           (full bags), in which case the window opens with the rest.
-- Blizzard's loot frame stops listening for loot events; its roll frames are
-- hidden as they appear. Blizzard's confirmation popups (bind on pickup,
-- etc.) still show as usual.

local L = ns:NewModule("Loot", { enabled = true, float = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
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
    ns.BandNoise(band, 11, true)
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
    win:SetAlpha(1)
    -- With auto-loot the game empties the corpse at once, and the floating
    -- text says what you got: the window only opens if something is still
    -- there a moment later (full bags, an item that needs confirming).
    if autoLoot then
        local seq = (L.openSeq or 0) + 1
        L.openSeq = seq
        C_Timer.After(0.35, function()
            if L.openSeq == seq and L.lootOpen then show() end
        end)
    else
        show()
    end
end

local function closeLootWindow()
    if win and win:IsShown() then
        closing = true
        win:Hide()
        closing = false
    end
end

-- ── Floating loot text ────────────────────────────────────────────────────
-- What the corpse held is noted when it opens; each slot that then empties
-- is something you took, and floats up from just above the minimap: a small
-- icon, the name in its quality colour, the count. A line rises by about
-- the minimap's own height at a steady pace and fades out at the top; the
-- lines of one corpse follow each other up, a beat apart. Nothing here can
-- be clicked. (With the minimap up in its corner, where there is no room
-- above it, the text rises from where the cursor was instead.)
local snap, snapN = {}, 0          -- slot -> { tex, name, qty, quality }
local floats, active = {}, 0       -- pooled lines; how many are showing
local floatX, floatY = 0, 0
local FLOAT_LIFE, FLOAT_IN, FLOAT_OUT, FLOAT_GAP = 3.0, 0.15, 0.6, 0.55
local floatRise = 130
-- Rails. Above your character each kind of pill has its own line to rise
-- along, so you know what a pill is from where it is:
--   left    what you loot, beside your left shoulder (the pill ends there
--           and reaches out to the left)
--   right   skill-ups and experience, beside your right shoulder (reaching right)
--   center  quest progress and warnings, above your head
-- Each rail keeps its own beat, so a burst of loot doesn't hold a quest
-- pill back. (Above the minimap there is one line for everything.)
local RAILS = {
    left   = { dx = -64, dy = 0,  anchor = "RIGHT" },
    right  = { dx = 64,  dy = 0,  anchor = "LEFT" },
    center = { dx = 0,   dy = 74, anchor = "CENTER" },
}
local ONE_RAIL = { dx = 0, dy = 0, anchor = "CENTER" }
local floatRails = false       -- true while pills rise above the character
local floatRail = "center"     -- which rail the next pill takes
local lastStart = {}           -- per rail: when its last pill set off
local floatDriver
local MONEY_SLOT = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2
local PILL_H, PILL_PAD = 24, 10
local COIN = { g = "|cffe6c25ag|r", s = "|cffb8bcc6s|r", c = "|cffc98a52c|r" }

local function snapshot()
    local n = call(GetNumLootItems) or 0
    snapN = n
    for slot = 1, n do
        local e = snap[slot]
        if not e then e = {}; snap[slot] = e end
        local tex, item, qty, _, quality = call(GetLootSlotInfo, slot)
        e.tex, e.name, e.qty, e.quality = tex, item, qty, quality
        e.money = (call(GetLootSlotType, slot) == MONEY_SLOT)
    end
end

-- Where pills start and how far they climb: just above the minimap, by its
-- height. (With the minimap up in its corner there is no room above it;
-- then from the cursor.)
local function floatOrigin()
    local sc = UIParent:GetEffectiveScale()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local mm = _G.Minimap
    floatRails = false
    -- Above your character (the default): on the rails, from shoulder
    -- height at the middle of the screen.
    if not (L.db and L.db.floatChar == false) then
        floatX, floatY, floatRise, floatRails = w / 2, h * 0.52, 120, true
        return
    end
    local top = mm and mm:IsVisible() and mm:GetTop()
    local cx = top and mm:GetCenter()
    if top and cx then
        local k = mm:GetEffectiveScale() / sc
        local mh = mm:GetHeight() * k
        if top * k + 14 + mh < h - 40 then
            floatX, floatY, floatRise = cx * k, top * k + 22, mh
            return
        end
    end
    local x, y = GetCursorPosition()
    floatX = math.max(140, math.min(w - 140, x / sc))
    floatY = math.max(80, math.min(h - 200, y / sc + 30))
    floatRise = 130
end

-- Each line is a small pill in the house style: dark fill, a hairline ring
-- in the item's quality colour, a round icon set into its left end, the
-- name, and a dim count. It opens out of its icon (a dot that widens into
-- the pill), drifts up, and closes back to the dot as it fades.
local OPEN, CLOSE = 0.28, 0.45
local function floatTick(_, dt)
    local any = false
    for i = 1, #floats do
        local f = floats[i]
        if f.live then
            f.age = f.age + dt
            local t = f.age
            if t >= FLOAT_LIFE then
                f.live = false
                f:Hide()
                active = active - 1
            elseif t >= 0 then
                any = true
                local k = t / FLOAT_LIFE
                local left = FLOAT_LIFE - t
                f:SetAlpha(t < FLOAT_IN and t / FLOAT_IN or (left < FLOAT_OUT and left / FLOAT_OUT) or 1)
                -- Width: out of the dot (eased), full, back toward the dot.
                local o = 1
                if t < OPEN then o = 1 - (1 - t / OPEN) ^ 3
                elseif left < CLOSE then o = (left / CLOSE) ^ 2 end
                f:SetWidth(PILL_H + (f.full - PILL_H) * o)
                -- A steady climb: every line moves at the same speed, so
                -- the distance between two of them never changes.
                f:SetPoint(f.anchor or "CENTER", UIParent, "BOTTOMLEFT", f.x, f.y + f.rise * k)
            else
                any = true
            end
        end
    end
    if not any then active = 0; floatDriver:Hide() end
end

local function floatLine()
    for i = 1, #floats do if not floats[i].live then return floats[i] end end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(PILL_H, PILL_H)
    f:EnableMouse(false)
    f:SetClipsChildren(true)
    f.ring = ns.RoundedRect(f, -8, 0, PILL_H / 2, T.border[1], T.border[2], T.border[3], 1)
    f.fill = ns.RoundedRect(f, -7, 1, PILL_H / 2 - 1, FILL[1], FILL[2], FILL[3], 0.94)
    -- (Clipped textures go on a child of the clip frame, not on it.)
    local inner = CreateFrame("Frame", nil, f)
    inner:SetPoint("LEFT")
    inner:SetSize(400, PILL_H)
    local mask = inner:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(PILL_H - 6, PILL_H - 6)
    mask:SetPoint("LEFT", 3, 0)
    f.icon = inner:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(mask)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon:AddMaskTexture(mask)
    f.text = text(inner, 11, true)
    f.text:SetPoint("LEFT", mask, "RIGHT", 7, 0)
    f.text:SetWordWrap(false)
    f.count = text(inner, 10, false, T.textDim)
    f.count:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
    -- A soft light that crosses the pill once, for the rarer kinds (a
    -- skill going up). On the clipped child, so it stays inside the pill.
    local sheen = inner:CreateTexture(nil, "OVERLAY")
    sheen:SetTexture(MEDIA .. "spot.tga")
    sheen:SetBlendMode("ADD")
    sheen:SetSize(46, PILL_H * 2.4)
    sheen:SetPoint("CENTER", inner, "LEFT", -30, 0)
    sheen:SetAlpha(0)
    local ag = sheen:CreateAnimationGroup()
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(0.55); fadeIn:SetDuration(0.15); fadeIn:SetStartDelay(OPEN); fadeIn:SetOrder(1)
    local move = ag:CreateAnimation("Translation")
    move:SetDuration(0.8); move:SetSmoothing("IN_OUT"); move:SetOrder(2)
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.55); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.2); fadeOut:SetOrder(3)
    ag:SetScript("OnPlay", function() sheen:SetAlpha(0) end)
    ag:SetScript("OnFinished", function() sheen:SetAlpha(0) end)
    f.sheen, f.sheenMove = ag, move
    floats[#floats + 1] = f
    return f
end

-- One pill: icon, text (may carry colour codes), an optional dim note after
-- it, the ring's colour, and an optional fill (a warning's tint).
local function floatPill(tex, label, tr, tg, tb, note, rr, rg, rb, fr, fg, fb)
    local f = floatLine()
    f.label, f.quest = label, nil
    f.icon:SetTexture(tex)
    f.icon:SetVertexColor(1, 1, 1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.sheen:Stop()
    f.text:SetText(label)
    f.text:SetTextColor(tr, tg, tb)
    local hasNote = type(note) == "string" and note ~= ""
    f.count:SetText(hasNote and note or "")
    f.count:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
    f.ring(rr, rg, rb, 1)
    if fr then f.fill(fr, fg, fb, 0.96) else f.fill(FILL[1], FILL[2], FILL[3], 0.94) end
    f.full = math.ceil((PILL_H - 3) + 7 + f.text:GetStringWidth()
        + (hasNote and (6 + f.count:GetStringWidth()) or 0) + PILL_PAD)
    f:SetWidth(PILL_H)
    -- Each line starts from the same spot, a beat after the one before.
    -- (The beat is however long it takes the line ahead to climb clear:
    -- a pill's height and a little air.)
    local now = GetTime()
    local gap = math.max(FLOAT_GAP, (PILL_H + 5) / (math.max(floatRise, 40) / FLOAT_LIFE))
    local railKey = floatRails and floatRail or "one"
    local rail = floatRails and RAILS[floatRail] or ONE_RAIL
    local start = math.max(now, (lastStart[railKey] or 0) + gap)
    lastStart[railKey] = start
    f.x, f.y, f.rise = floatX, floatY, floatRise
    f.x, f.y, f.anchor = floatX + rail.dx, floatY + rail.dy, rail.anchor
    f.age = now - start
    f.live = true
    active = active + 1
    f:SetAlpha(0)
    f:ClearAllPoints()
    f:SetPoint(f.anchor, UIParent, "BOTTOMLEFT", f.x, f.y)
    f:Show()
    if not floatDriver then
        floatDriver = CreateFrame("Frame")
        floatDriver:SetScript("OnUpdate", floatTick)
    end
    floatDriver:Show()
    return f
end

-- A pill with this label that went up within the last moment, if any.
-- Looting a quest item makes two announcements, the item and the quest
-- count, a fraction of a second apart and in either order: the second one
-- is folded into the first's pill instead of adding its own.
local FOLD = 1.5
local function recentPill(label)
    for i = 1, #floats do
        local f = floats[i]
        if f.live and f.label == label and f.age < FOLD then return f end
    end
end
-- Put the quest count on a pill: the count as its note, gold ring (green
-- and green text when that completes the objective).
local function markQuest(f, have, need)
    local done = tonumber(have) >= tonumber(need)
    f.quest = true
    f.count:SetText(have .. "/" .. need)
    if done then
        f.text:SetTextColor(0.62, 0.90, 0.66)
        f.ring(0.35, 0.72, 0.42, 1)
    else
        f.ring(0.74, 0.60, 0.20, 1)
    end
    f.full = math.ceil((PILL_H - 3) + 7 + f.text:GetStringWidth() + 6 + f.count:GetStringWidth() + PILL_PAD)
end

-- For the rest of the addon: a warning pill in the same place and motion
-- as loot (red ring, dark red fill). Used for low ammunition.
function ns.FloatWarning(tex, label, note)
    if not pcall(floatOrigin) then return end
    floatRail = "center"
    pcall(floatPill, tex, label, 1.0, 0.86, 0.84, note, 0.90, 0.35, 0.30, 0.20, 0.07, 0.07)
end

-- A skill going up ("Your skill in Herbalism has increased to 76."): rarer
-- than loot, so it is dressed differently from it. Accent ring and a
-- tinted fill, the skill's own icon (our up-arrow for skills that have
-- none), the new level as the note, and a light that crosses the pill
-- once. Every 25th point, and the last point of a tier, is gold.
local SKILL_PATTERN
local function skillPattern()
    if SKILL_PATTERN == nil then
        local g = _G.ERR_SKILL_UP_SI
        if type(g) == "string" then
            -- "Your skill in %s has increased to %d." -> a pattern
            local p = g:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
            SKILL_PATTERN = "^" .. p .. "$"
        else
            SKILL_PATTERN = false
        end
    end
    return SKILL_PATTERN
end
local skillIcons
local function skillIcon(name)
    if not skillIcons then
        skillIcons = {}
        if _G.GetProfessions and _G.GetProfessionInfo then
            local list = { call(GetProfessions) }
            for i = 1, 8 do
                local idx = list[i]
                if idx then
                    local n, icon = call(GetProfessionInfo, idx)
                    if type(n) == "string" and icon then skillIcons[n] = icon end
                end
            end
        end
    end
    local icon = skillIcons[name]
    if icon then return icon end
    local f = C_Spell and C_Spell.GetSpellTexture
    icon = f and call(f, name)
    if icon and not secret(icon) then skillIcons[name] = icon return icon end
    return nil
end
local function floatSkill(msg)
    if not (L.db and L.db.skillFloat ~= false) then return end
    if type(msg) ~= "string" or secret(msg) then return end
    local pat = skillPattern()
    if not pat then return end
    local name, level = msg:match(pat)
    if not name then return end
    level = tonumber(level)
    if not pcall(floatOrigin) then return end
    local gold = level and (level % 25 == 0)
    local r, g, b = T.accent[1], T.accent[2], T.accent[3]
    if gold then r, g, b = 0.95, 0.78, 0.32 end
    local icon = skillIcon(name)
    floatRail = "right"
    local ok, f = pcall(floatPill, icon or (MEDIA .. "micro_up.tga"), name, 1, 1, 1, level and tostring(level) or nil,
        r, g, b, r * 0.16 + 0.03, g * 0.16 + 0.03, b * 0.16 + 0.03)
    if not (ok and f) then return end
    if not icon then
        f.icon:SetTexCoord(0, 1, 0, 1)
        f.icon:SetVertexColor(r, g, b, 1)
    end
    f.count:SetTextColor(r, g, b)
    f.skill = true
    f.sheenMove:SetOffset(f.full + 60, 0)
    f.sheen:Play()
end

-- Experience gained: a pill on the right rail, with skill-ups (the rail
-- for what you yourself gain), in the XP bar's purple: "+120 XP" and how
-- far through the level that leaves you. Gains that arrive together (a
-- kill and the quest it finished) are one pill. Read from the change in
-- your experience, so it is right whatever the source; a level-up in
-- between is counted across.
local XP_TINT = { 0.66, 0.56, 1.00 }
local xpWas, xpMaxWas, xpSum, xpDue = nil, nil, 0, false
local function floatXP()
    xpDue = false
    local gain = xpSum
    xpSum = 0
    if gain <= 0 or not (L.db and L.db.xpFloat ~= false) then return end
    if not pcall(floatOrigin) then return end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local note
    if type(cur) == "number" and type(max) == "number" and not secret(cur) and not secret(max) and max > 0 then
        note = string.format("%d%%", math.floor(cur / max * 100))
    end
    local r, g, b = XP_TINT[1], XP_TINT[2], XP_TINT[3]
    floatRail = "right"
    local ok, f = pcall(floatPill, MEDIA .. "micro_up.tga", "+" .. gain .. " XP", 1, 1, 1, note,
        r, g, b, r * 0.16 + 0.03, g * 0.16 + 0.03, b * 0.16 + 0.03)
    if not (ok and f) then return end
    f.icon:SetTexCoord(0, 1, 0, 1)
    f.icon:SetVertexColor(r, g, b, 1)
    f.count:SetTextColor(r, g, b)
end
local function xpChanged(fresh)
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if type(cur) ~= "number" or type(max) ~= "number" or secret(cur) or secret(max) then return end
    if xpWas and not fresh then
        local gain = cur - xpWas
        if gain < 0 then gain = (xpMaxWas - xpWas) + cur end -- levelled in between
        if gain > 0 then
            xpSum = xpSum + gain
            if not xpDue then xpDue = true; C_Timer.After(0.3, function() pcall(floatXP) end) end
        end
    end
    xpWas, xpMaxWas = cur, max
end
do
    local xf = CreateFrame("Frame")
    xf:RegisterEvent("PLAYER_XP_UPDATE")
    xf:RegisterEvent("PLAYER_ENTERING_WORLD")
    xf:SetScript("OnEvent", function(_, e) pcall(xpChanged, e == "PLAYER_ENTERING_WORLD") end)
end

-- /men skillup : show a sample skill-up pill (and a gold one).
ns.commands = ns.commands or {}
ns.commands.skillup = function()
    local fmt = _G.ERR_SKILL_UP_SI or "Your skill in %s has increased to %d."
    local name = "Herbalism"
    if _G.GetProfessions and _G.GetProfessionInfo then
        local first = call(GetProfessions)
        local n = first and call(GetProfessionInfo, first)
        if type(n) == "string" then name = n end
    end
    floatSkill(fmt:format(name, 74))
    floatSkill(fmt:format(name, 75))
end

-- Quest progress ("Restabilization Cog: 3/8", "Leper Gnome slain: 2/10"):
-- the game prints these in large yellow letters mid-screen. Here they are a
-- pill in the same stream as loot: the objective, a dim count, a gold ring
-- (green once the objective is complete). Returns true if it took the
-- message; anything that isn't a count is left to the game's own text.
local QUEST_ICON = "Interface/Icons/INV_Misc_Note_01"
local function floatQuest(msg)
    if type(msg) ~= "string" or secret(msg) then return false end
    local what, have, need = msg:match("^(.-)%s*:%s*(%d+)%s*/%s*(%d+)$")
    if not what or what == "" then return false end
    -- The item was just looted (or the same count just went up, two kills
    -- in a breath): that pill takes the new count.
    local seen = recentPill(what)
    if seen then
        pcall(markQuest, seen, have, need)
        return true
    end
    if not pcall(floatOrigin) then return false end
    floatRail = "center"
    local ok, f = pcall(floatPill, QUEST_ICON, what, T.text[1], T.text[2], T.text[3], nil,
        T.border[1], T.border[2], T.border[3])
    if ok and f then pcall(markQuest, f, have, need) end
    return ok
end

local function floatSlot(slot)
    if not (L.db and L.db.float ~= false) then return end
    local e = type(slot) == "number" and slot <= snapN and snap[slot]
    if not e or not e.tex then return end
    local name = e.name
    if type(name) ~= "string" or secret(name) or name == "" then return end
    local tex, qty, quality = e.tex, e.qty, e.quality
    e.tex = nil -- one line per slot
    local cr, cg, cb = qualityColor(quality)
    local fine = type(quality) == "number" and quality >= 2
    if e.money then
        -- "1 Silver / 25 Copper" as "1s 25c", coins in their colours.
        local out = ""
        for num, word in name:gmatch("(%d+)%s*(%a)") do
            out = out .. (out ~= "" and " " or "") .. num .. (COIN[word:lower()] or "")
        end
        name = out ~= "" and out or (name:gsub("\n", "  "))
        fine = false
    end
    -- The quest count for this item is already up: that pill gets the
    -- item's icon, and no second one is added.
    local seen = not e.money and recentPill(name)
    if seen and seen.quest then
        seen.icon:SetTexture(tex)
        return
    end
    local many = type(qty) == "number" and not secret(qty) and qty > 1 and not e.money
    -- The ring carries the quality; plain things keep the usual hairline.
    local tr, tg, tb = T.text[1], T.text[2], T.text[3]
    local rr, rg, rb = T.border[1], T.border[2], T.border[3]
    if fine then tr, tg, tb, rr, rg, rb = cr, cg, cb, cr * 0.75, cg * 0.75, cb * 0.75 end
    floatRail = "left"
    floatPill(tex, name, tr, tg, tb, many and ("\195\151" .. qty) or nil, rr, rg, rb)
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
    local rollLink = _G.GetLootRollItemLink and call(_G.GetLootRollItemLink, rollID)
    local isUp = type(rollLink) == "string" and ns.IsUpgrade and ns.IsUpgrade(rollLink)
    c.bind:SetText((isUp and "|cff6beb80Upgrade for you|r" or "")
        .. ((isUp and bop) and "   " or "") .. (bop and "Binds when picked up" or ""))
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
    -- The game's mid-screen messages ("Out of range", quest progress): in
    -- our font and a calmer size. Quest progress is taken out of them and
    -- shown as pills instead (floatQuest); the rest still print there.
    local ue = _G.UIErrorsFrame
    if ue then
        pcall(ns.SetFont, ns, ue, 13, "", true)
        pcall(ue.SetShadowOffset, ue, 1, -1)
        pcall(ue.SetShadowColor, ue, 0, 0, 0, 0.9)
        if db.questFloat ~= false then
            pcall(ue.UnregisterEvent, ue, "UI_INFO_MESSAGE")
            local q = CreateFrame("Frame")
            q:RegisterEvent("UI_INFO_MESSAGE")
            q:SetScript("OnEvent", function(_, _, kind, msg)
                if floatQuest(msg) then return end
                if ue.TryDisplayMessage then
                    if pcall(ue.TryDisplayMessage, ue, kind, msg, 1, 0.82, 0.25) then return end
                end
                pcall(ue.AddMessage, ue, msg, 1, 0.82, 0.25)
            end)
        end
    end
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
    local sk = CreateFrame("Frame")
    sk:RegisterEvent("CHAT_MSG_SKILL")
    sk:RegisterEvent("SKILL_LINES_CHANGED")
    sk:SetScript("OnEvent", function(_, e, msg)
        if e == "SKILL_LINES_CHANGED" then skillIcons = nil return end
        pcall(floatSkill, msg)
    end)
    ev:SetScript("OnEvent", function(_, e, a1, a2)
        if e == "LOOT_OPENED" then
            closeLootWindow()
            L.lootOpen = true
            pcall(snapshot)
            pcall(floatOrigin)
            openLoot(a1)
        elseif e == "LOOT_SLOT_CLEARED" or e == "LOOT_SLOT_CHANGED" then
            if e == "LOOT_SLOT_CLEARED" and L.lootOpen then pcall(floatSlot, a1) end
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

-- /men testroll : preview a roll card (uses your first bag item's look).
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
