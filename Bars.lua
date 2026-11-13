local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Restyles Blizzard's own action buttons (so paging/stances keep working) and
-- lays them out:
--   [bar 2: 3x4] [health orb] [ main bar: 12 in a row ] [power orb] [bar 3: 3x4]
-- With the minimap dome on (Minimap.lua) the main bar splits around it:
--   [health orb] [1 2 3 / 4 5 6] ( dome ) [7 8 9 / 0 - =] [power orb]
-- (two blocks of 3 x 2: a single split row would not fit between the orbs).
-- Bar 2 / bar 3 blocks are anchored to the orbs, so they follow when orbs move.
-- Escape hatch if anything misbehaves: /men actionbars, then /reload.

local DEFAULT_MAIN = { x = 0, y = 30 }

local Bars = ns:NewModule("Bars", {
    enabled = true,
    main  = { size = 44, gap = 4, x = DEFAULT_MAIN.x, y = DEFAULT_MAIN.y },
    small = { size = 26, gap = 3, cols = 4, margin = 14 }, -- ~60% of main
    -- A dark rounded plate behind the whole bottom row (side bars, orbs,
    -- main bar, minimap dome), so it reads as one console. /men console
    plate = true,
    -- The plate runs the full width of the screen and seats the chat window
    -- in its left wing and the damage meter in its right. /men console wings
    wings = true,
    wingFill = 0.5, -- share of each wing's width the chat / meter panel takes (outer side)
    petGrid = true, -- empty pet action slots are drawn too (/men petgrid)
})

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Bars.lastError = err end
    return ok
end

local function killRegion(r)
    if not r then return end
    safe(function()
        r:SetAlpha(0)
        if r.Hide then r:Hide() end
        if not r.__muiHooked and r.Show then
            r.__muiHooked = true
            hooksecurefunc(r, "Show", function(self) self:SetAlpha(0) end)
        end
    end)
end

local ROUND = "Interface/AddOns/Meniscus/Media/rounded.tga"

local function newMask(owner)
    local m = owner:CreateMaskTexture()
    m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return m
end

local function fadeGroup(region, from, to)
    local ag = region:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(0.12)
    ag:SetToFinalAlpha(true)
    return ag
end

-- Our proc glow on/off; Blizzard's alert frame stays but is invisible.
local function setProc(b, on)
    local p = b and b.__muiProc
    if not p then return end
    p.glow:SetShown(on)
    p.ring:SetShown(on)
    if on then p.anim:Play() else p.anim:Stop() end
    for _, key in ipairs({ "SpellActivationAlert", "overlay" }) do
        local alert = b[key]
        if alert and alert.SetAlpha then alert:SetAlpha(0) end
    end
end

local procHooked = false
local function hookProcs()
    if procHooked then return end
    procHooked = true
    local M = _G.ActionButtonSpellAlertManager
    if M and M.ShowAlert then
        hooksecurefunc(M, "ShowAlert", function(_, b) setProc(b, true) end)
        hooksecurefunc(M, "HideAlert", function(_, b) setProc(b, false) end)
    end
    if type(_G.ActionButton_ShowOverlayGlow) == "function" then
        hooksecurefunc("ActionButton_ShowOverlayGlow", function(b) setProc(b, true) end)
        hooksecurefunc("ActionButton_HideOverlayGlow", function(b) setProc(b, false) end)
    end
end

local function skin(b, fontSize, thick)
    hookProcs()
    if not b.__muiSkinned then
        b.__muiSkinned = true

        killRegion(b.SlotBackground)
        killRegion(b.SlotArt)
        killRegion(b.Border)
        killRegion(b.FlyoutBorder)
        killRegion(b.FlyoutBorderShadow)
        -- The gold separators between slots: each button's own right / bottom
        -- divider, shown when Edit Mode's bar art is on (fresh layouts).
        killRegion(b.RightDivider)
        killRegion(b.BottomDivider)
        killRegion(b.LeftDivider)
        killRegion(b.TopDivider)
        if b.GetNormalTexture then killRegion(b:GetNormalTexture()) end

        -- Rounded back plate: ring (+ accent hover ring) under a dark fill.
        local back = CreateFrame("Frame", nil, b)
        back:SetAllPoints(b)
        back:SetFrameLevel(math.max(b:GetFrameLevel() - 1, 0))

        local outer = newMask(back)
        outer:SetAllPoints(back)
        local innerBack = newMask(back)
        innerBack:SetPoint("TOPLEFT", back, "TOPLEFT", thick, -thick)
        innerBack:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", -thick, thick)

        local ring = back:CreateTexture(nil, "BACKGROUND", nil, 0)
        ring:SetAllPoints()
        ring:SetColorTexture(unpack(T.border))
        ring:AddMaskTexture(outer)
        b.__muiRing = ring

        local hover = back:CreateTexture(nil, "BACKGROUND", nil, 1)
        hover:SetAllPoints()
        hover:SetColorTexture(unpack(T.accent))
        hover:AddMaskTexture(outer)
        hover:SetAlpha(0)

        local plate = back:CreateTexture(nil, "BACKGROUND", nil, 2)
        plate:SetPoint("TOPLEFT", thick, -thick)
        plate:SetPoint("BOTTOMRIGHT", -thick, thick)
        plate:SetColorTexture(0.06, 0.06, 0.07, 0.95)
        plate:AddMaskTexture(innerBack)

        local innerB = newMask(b)
        innerB:SetPoint("TOPLEFT", b, "TOPLEFT", thick, -thick)
        innerB:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -thick, thick)

        -- Proc glow (spell activation): a gold rounded halo just outside the
        -- button plus a gold ring, pulsing. Replaces Blizzard's square flipbook.
        local halo = newMask(back)
        halo:SetPoint("TOPLEFT", back, "TOPLEFT", -4, 4)
        halo:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", 4, -4)
        local glow = back:CreateTexture(nil, "BACKGROUND", nil, -1)
        glow:SetPoint("TOPLEFT", back, "TOPLEFT", -4, 4)
        glow:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", 4, -4)
        glow:SetColorTexture(1.0, 0.80, 0.30, 0.55)
        glow:AddMaskTexture(halo)
        local procRing = back:CreateTexture(nil, "BACKGROUND", nil, 1)
        procRing:SetAllPoints()
        procRing:SetColorTexture(1.0, 0.84, 0.38, 1)
        procRing:AddMaskTexture(outer)
        local procAnim = glow:CreateAnimationGroup()
        local pa = procAnim:CreateAnimation("Alpha")
        pa:SetFromAlpha(1)
        pa:SetToAlpha(0.25)
        pa:SetDuration(0.55)
        pa:SetSmoothing("IN_OUT")
        procAnim:SetLooping("BOUNCE")
        glow:Hide()
        procRing:Hide()
        b.__muiProc = { glow = glow, ring = procRing, anim = procAnim }

        local fadeIn, fadeOut = fadeGroup(hover, 0, 1), fadeGroup(hover, 1, 0)
        b:HookScript("OnEnter", function() fadeOut:Stop(); fadeIn:Play() end)
        b:HookScript("OnLeave", function() fadeIn:Stop(); fadeOut:Play() end)

        local icon = b.icon or b.Icon
        if icon then
            safe(function()
                if b.IconMask and icon.RemoveMaskTexture then
                    icon:RemoveMaskTexture(b.IconMask)
                    b.IconMask:Hide()
                end
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", thick, -thick)
                icon:SetPoint("BOTTOMRIGHT", -thick, thick)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:AddMaskTexture(innerB)
            end)
        end

        safe(function()
            local hl = b.GetHighlightTexture and b:GetHighlightTexture()
            if hl then hl:SetColorTexture(1, 1, 1, 0.10); hl:SetAllPoints(b); hl:AddMaskTexture(innerB) end
            local pu = b.GetPushedTexture and b:GetPushedTexture()
            if pu then pu:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.30); pu:SetAllPoints(b); pu:AddMaskTexture(innerB) end
            local ck = b.GetCheckedTexture and b:GetCheckedTexture()
            if ck then ck:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.22); ck:SetAllPoints(b); ck:AddMaskTexture(innerB) end
            if b.Name then b.Name:SetAlpha(0) end
        end)

        -- Cooldown swipes: inset to the icon and drawn with the rounded
        -- texture, so the dark sweep matches the button shape (not a square).
        for _, cd in ipairs({ b.cooldown, b.chargeCooldown, b.lossOfControlCooldown }) do
            if cd then
                safe(function()
                    cd:ClearAllPoints()
                    cd:SetPoint("TOPLEFT", b, "TOPLEFT", thick, -thick)
                    cd:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -thick, thick)
                    cd:SetSwipeTexture(ROUND)
                    cd:SetSwipeColor(0, 0, 0, 0.65)
                end)
            end
        end

        -- Blizzard's square cast/interrupt/targeting animations on the button
        -- (the yellow fill while casting). Our cast bars cover this; silence
        -- them with alpha (combat-safe, no Show/Hide on secure children).
        for _, key in ipairs({ "SpellCastAnimFrame", "InterruptDisplay", "TargetReticleAnimFrame" }) do
            local anim = b[key]
            if anim then
                safe(function()
                    anim:SetAlpha(0)
                    hooksecurefunc(anim, "SetAlpha", function(self, a)
                        if a ~= 0 then self:SetAlpha(0) end
                    end)
                end)
            end
        end
    end

    safe(function()
        -- Edit Mode "icon size" can scale the bar (parent) or the button, which shrinks
        -- our sizes and offsets. Make the button's effective scale equal UIParent's.
        local parent = b:GetParent()
        if parent then
            local want = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
            if math.abs(b:GetScale() - want) > 0.001 then b:SetScale(want) end
        end
        if b.HotKey then
            ns:SetFont(b.HotKey, fontSize, "OUTLINE")
            b.HotKey:ClearAllPoints()
            b.HotKey:SetPoint("TOPRIGHT", -2, -2)
            -- A button with no key bound shows the game's range mark in
            -- that corner instead: a "●" character, white in range and
            -- red out of it. Our font has no such character, so it came
            -- out as an empty box. The character is hidden and a small
            -- red dot of our own shows while the target is out of range.
            if not b.__muiRangeDot then
                b.__muiRangeDot = true
                local hk = b.HotKey
                local dot = b:CreateTexture(nil, "OVERLAY", nil, 2)
                dot:SetTexture("Interface/AddOns/Meniscus/Media/circle.tga")
                dot:SetSize(7, 7)
                dot:SetPoint("TOPRIGHT", -4, -4)
                dot:SetVertexColor(0.92, 0.30, 0.26, 1)
                dot:Hide()
                local mark = _G.RANGE_INDICATOR
                local function sync()
                    local t = hk:GetText()
                    local isMark = type(t) == "string" and not issecretvalue(t) and mark ~= nil and t == mark
                    hk:SetAlpha(isMark and 0 or 1)
                    local far = false
                    if isMark and hk:IsShown() then
                        local r, g = hk:GetTextColor()
                        far = type(r) == "number" and not issecretvalue(r) and r > 0.8 and g < 0.35
                    end
                    dot:SetShown(far)
                end
                for _, m in ipairs({ "SetText", "SetVertexColor", "SetTextColor", "Show", "Hide", "SetShown" }) do
                    if hk[m] then hooksecurefunc(hk, m, sync) end
                end
                sync()
            end
        end
        if b.Count then
            ns:SetFont(b.Count, fontSize + 1, "OUTLINE")
            b.Count:ClearAllPoints()
            b.Count:SetPoint("BOTTOMRIGHT", -2, 2)
        end
    end)
end

local function newAnchor(name, w, h)
    local a = CreateFrame("Frame", name, UIParent)
    a:SetSize(w, h)
    return a
end

-- Width of the gap the minimap dome needs in the middle of the main bar,
-- or nil when the dome is off. (Read from the saved settings: this module
-- starts before the minimap's.)
local DOME_MARGIN = 14
function Bars:DomeGap()
    local mm = ns.modules.Minimap and ns.modules.Minimap.db
    if not mm then mm = ns.db and ns.db.modules and ns.db.modules.Minimap end
    if type(mm) ~= "table" or mm.enabled == false or not mm.dome then return nil end
    return (mm.domeD or 130) + 11 + DOME_MARGIN * 2
end

function Bars:Arrange()
    if InCombatLockdown() then self.pending = true return end
    self.pending = false
    local db = self.db
    local O = ns.modules.Orbs
    local m, s = db.main, db.small
    local gap = self:DomeGap()
    self.split = gap

    -- Main bar: 12 buttons in a row, centered at the bottom; or two blocks
    -- of 3 x 2 either side of the minimap dome.
    local step = m.size + m.gap
    local blockW = 3 * m.size + 2 * m.gap
    local mainW = gap and (2 * blockW + gap) or (12 * m.size + 11 * m.gap)
    local mainH = gap and (2 * m.size + m.gap) or m.size
    self.main = self.main or newAnchor("MinimalUI_MainBar", mainW, mainH)
    self.main:SetSize(mainW, mainH)
    self.main:ClearAllPoints()
    self.main:SetPoint("BOTTOM", UIParent, "BOTTOM", m.x, m.y)
    for i = 1, 12 do
        local b = _G["ActionButton" .. i]
        if b then
            skin(b, 10, 2)
            safe(function()
                b:ClearAllPoints()
                if gap then
                    local k = (i - 1) % 6
                    local x = (k % 3) * step + (i > 6 and (blockW + gap) or 0)
                    local y = (1 - math.floor(k / 3)) * step
                    b:SetPoint("BOTTOMLEFT", self.main, "BOTTOMLEFT", x, y)
                else
                    b:SetPoint("BOTTOMLEFT", self.main, "BOTTOMLEFT", (i - 1) * step, 0)
                end
                b:SetSize(m.size, m.size)
            end)
        end
    end

    -- Split layout: the orbs close in beside the main bar's blocks, as far
    -- from them as the blocks are from the minimap dome (the side bars are
    -- anchored to the orbs, so they come along). The orbs' own saved
    -- positions are left alone and used again when the dome is off.
    if O and O.health and O.power and O.db then
        local od = O.db
        if gap then
            local x = mainW / 2 + DOME_MARGIN + (od.size or 120) / 2
            safe(function()
                O.health:ClearAllPoints()
                O.health:SetPoint("BOTTOM", UIParent, "BOTTOM", m.x - x, od.health.y)
                O.power:ClearAllPoints()
                O.power:SetPoint("BOTTOM", UIParent, "BOTTOM", m.x + x, od.power.y)
            end)
            self.orbsMoved = true
        elseif self.orbsMoved then
            self.orbsMoved = false
            safe(function()
                O.health:ClearAllPoints()
                O.health:SetPoint("BOTTOM", UIParent, "BOTTOM", od.health.x, od.health.y)
                O.power:ClearAllPoints()
                O.power:SetPoint("BOTTOM", UIParent, "BOTTOM", od.power.x, od.power.y)
            end)
        end
    end

    -- Bars 2 and 3: blocks of 3 rows x 4 columns outside the orbs.
    local rows = math.ceil(12 / s.cols)
    local blockW = s.cols * s.size + (s.cols - 1) * s.gap
    local blockH = rows * s.size + (rows - 1) * s.gap
    local blocks = {
        { key = "block2", prefix = "MultiBarBottomLeftButton",  side = "left"  },
        { key = "block3", prefix = "MultiBarBottomRightButton", side = "right" },
    }
    for _, blk in ipairs(blocks) do
        local anchor = self[blk.key] or newAnchor("MinimalUI_" .. blk.key, blockW, blockH)
        self[blk.key] = anchor
        anchor:ClearAllPoints()
        if blk.side == "left" then
            if O and O.health then
                anchor:SetPoint("BOTTOMRIGHT", O.health, "BOTTOMLEFT", -s.margin, 0)
            else
                anchor:SetPoint("BOTTOMRIGHT", self.main, "BOTTOMLEFT", -160, 0)
            end
        else
            if O and O.power then
                anchor:SetPoint("BOTTOMLEFT", O.power, "BOTTOMRIGHT", s.margin, 0)
            else
                anchor:SetPoint("BOTTOMLEFT", self.main, "BOTTOMRIGHT", 160, 0)
            end
        end
        for i = 1, 12 do
            local b = _G[blk.prefix .. i]
            if b then
                skin(b, 8, 1.5)
                local col, row = (i - 1) % s.cols, math.floor((i - 1) / s.cols)
                safe(function()
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", anchor, "TOPLEFT",
                        col * (s.size + s.gap), -row * (s.size + s.gap))
                    b:SetSize(s.size, s.size)
                end)
            end
        end
    end

    -- Stance/aura row (left) and pet row (right), small buttons just above the
    -- main bar. Blizzard still shows/hides them (no stances, no pet).
    -- Split around the dome: two rows of five, so neither row reaches over
    -- the dome (first five on the lower row).
    -- With the console's wings on, the pet bar leaves the main bar and sits
    -- in the plate's left slot (between the chat panel and the side bar),
    -- under the pet's own frame: one pet unit, seated in the plate.
    local step = s.size + s.gap
    local slots = self.Slots and self:Slots()
    local petW = 5 * step - s.gap
    local PET_PILL = 22 -- the pet frame's height (UnitFrames.lua, "tiny")
    self.petSlot = nil
    local slotW = slots and (slots.right.x1 - slots.right.x0) or 0
    local od = (O and O.db) or (ns.db and ns.db.modules and ns.db.modules.Orbs) or {}
    local orbD = math.floor((od.size or 120) * 0.6 + 0.5) -- pet health orb (Orbs.lua)
    local gridH = 2 * s.size + s.gap
    local orbUnitW = orbD + 8 + 10 + petW -- orb, its power orb's overhang, a gap, the bar
    if slots and od.petOrbs ~= false and slotW >= orbUnitW + 8 then
        -- Pet orbs on the left, the pet's action bar to their right, both
        -- centered on the slot's middle line.
        -- (A little above the middle: the info pill hangs off the bottom of
        -- the well that frames them.)
        local cx, cy = (slots.right.x0 + slots.right.x1) / 2, (slots.y0 + slots.y1) / 2 + 6
        local x0 = cx - orbUnitW / 2
        self.petSlot = { orbs = true, orbX = x0, orbBottom = cy - orbD / 2,
                         x = x0 + orbD + 18, w = petW, gridTop = cy + gridH / 2, top = cy + gridH / 2,
                         well = { x = x0 - 10, y = cy - orbD / 2 - 8, w = orbUnitW + 20, h = orbD + 16 } }
    elseif slots and slotW >= petW + 8 then
        local unitH = PET_PILL + 6 + gridH
        local top = slots.y1 - math.max(0, ((slots.y1 - slots.y0) - unitH) / 2)
        local px = (slots.right.x0 + slots.right.x1) / 2 - petW / 2
        self.petSlot = { x = px, top = top, w = petW, gridTop = top - PET_PILL - 6,
                         well = { x = px - 16, y = top - unitH - 8, w = petW + 32, h = unitH + 16 } }
    end
    -- Character panel, in the console's left slot: your portrait on the
    -- left, buffs and debuffs to its right, in a well the same size as the
    -- pet's, with a name pill on its bottom edge (Bars:ApplyCharWell).
    self.charSlot = nil
    if slots then
        -- The pet well's width, or the slot's if that is a touch narrower
        -- (on a 2100-wide UI the slot is 251.5 against 252, which is why
        -- nothing showed at first).
        local L = slots.left
        local cw = math.min(orbUnitW + 20, L.x1 - L.x0)
        if cw >= 200 then
            local cx, cy = (L.x0 + L.x1) / 2, (slots.y0 + slots.y1) / 2 + 6
            local wx, wy, wh = cx - cw / 2, cy - orbD / 2 - 8, orbD + 16
            self.charSlot = {
                well = { x = wx, y = wy, w = cw, h = wh },
                avD = 60, avX = wx + 12 + 30, avY = cy + 2,       -- portrait: size, center
                -- Buffs / debuffs: where the icons themselves may start and
                -- end. The left edge is a few pixels off the portrait's rim.
                auraX0 = wx + 78, auraX1 = wx + cw - 6,
                auraTop = wy + wh - 6, auraBottom = wy + 10,
            }
        end
    end
    local petSlot = self.petSlot
    -- Stances / forms / stealth: with the character panel up, a row of
    -- small buttons on the panel's top edge, growing leftwards from its right
    -- end (half in, half out,
    -- the way the name pill sits on its bottom edge). Things that sit above
    -- the panel (Quick Buff pill, party column) move up by stanceLift.
    local STANCE = 24
    local nForms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    if type(nForms) ~= "number" or issecretvalue(nForms) then nForms = 0 end
    local cs = self.charSlot
    local stanceW = nForms * STANCE + math.max(0, nForms - 1) * 4
    self.stanceLift = (cs and nForms > 0) and (STANCE / 2 + 5) or 0
    for i = 1, 10 do
        local col, up = i - 1, 0
        if gap then col, up = (i - 1) % 5, math.floor((i - 1) / 5) * step end
        local b = _G["StanceButton" .. i]
        if b then
            skin(b, 8, 1.5)
            safe(function()
                b:ClearAllPoints()
                if cs and nForms > 0 then
                    local wl = cs.well
                    -- From the panel's right end leftwards: the first stance
                    -- is the rightmost, each further one to its left.
                    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                        wl.x + wl.w - 14 - STANCE - (i - 1) * (STANCE + 4), wl.y + wl.h - STANCE / 2)
                    b:SetSize(STANCE, STANCE)
                else
                    b:SetPoint("BOTTOMLEFT", self.main, "TOPLEFT", col * step, 8 + up)
                    b:SetSize(s.size, s.size)
                end
            end)
        end
        local pb = _G["PetActionButton" .. i]
        if pb then
            skin(pb, 8, 1.5)
            Bars:SkinPetButton(pb, i)
            safe(function()
                pb:ClearAllPoints()
                if petSlot then
                    pb:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", petSlot.x + ((i - 1) % 5) * step,
                        petSlot.gridTop - math.floor((i - 1) / 5) * step)
                elseif gap then
                    pb:SetPoint("BOTTOMRIGHT", self.main, "TOPRIGHT", -(4 - col) * step, 8 + up)
                else
                    pb:SetPoint("BOTTOMRIGHT", self.main, "TOPRIGHT", -(10 - i) * step, 8)
                end
                pb:SetSize(s.size, s.size)
            end)
        end
    end

    -- Hide default bar decoration; buttons work without it.
    for _, bar in ipairs({ MainActionBar, MultiBarBottomLeft, MultiBarBottomRight, StanceBar, PetActionBar }) do
        if bar then
            for _, k in ipairs({ "BorderArt", "EndCaps", "Background" }) do killRegion(bar[k]) end
            -- The bar's own frame (not its buttons, which are placed one by
            -- one) still lies where Blizzard put it, invisible, and takes
            -- the mouse: the main bar's lay across the top of the minimap
            -- dome, so dots under it gave no tooltip. Only the buttons need
            -- the mouse. (A protected frame: out of combat only; arranging
            -- runs again after a fight.)
            if bar.EnableMouse and bar.IsMouseEnabled and bar:IsMouseEnabled() and not InCombatLockdown() then
                pcall(bar.EnableMouse, bar, false)
            end
        end
    end
    -- With Edit Mode's "hide bar art" off (any fresh character's default
    -- layout), the main bar also draws gold dividers between its buttons and
    -- the page number with its up / down arrows. Our buttons have their own
    -- plates, so these go too, whatever the layout says.
    local mab = _G.MainActionBar or _G.MainMenuBar
    if mab then
        -- (Forever: the dividers are 12x44 frames from VerticalDividersPool
        -- and HorizontalDividersPool, children of the bar; /men barprobe.)
        local function noDividers(bar)
            for _, key in ipairs({ "dividersPool", "VerticalDividersPool", "HorizontalDividersPool" }) do
                local pool = bar[key]
                if pool and pool.EnumerateActive then
                    for d in pool:EnumerateActive() do killRegion(d) end
                end
            end
            for _, k in ipairs({ "ActionBarButtonDividers", "Dividers" }) do killRegion(bar[k]) end
        end
        -- (The other bars have the same pools.)
        for _, bar in ipairs({ mab, _G.MultiBarBottomLeft, _G.MultiBarBottomRight, _G.MultiBarRight, _G.MultiBarLeft }) do
            safe(noDividers, bar)
            if bar.UpdateDividers and not bar.__muiDivHook then
                bar.__muiDivHook = true
                hooksecurefunc(bar, "UpdateDividers", function(b) safe(noDividers, b) end)
            end
            -- New dividers handed out later (a layout change) are caught too.
            for _, key in ipairs({ "VerticalDividersPool", "HorizontalDividersPool" }) do
                local pool = bar[key]
                if pool and pool.Acquire and not pool.__muiHook then
                    pool.__muiHook = true
                    hooksecurefunc(pool, "Acquire", function()
                        C_Timer.After(0, function() safe(noDividers, bar) end)
                    end)
                end
            end
        end
        killRegion(mab.ActionBarPageNumber)
        for _, n in ipairs({ "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber" }) do
            killRegion(_G[n])
        end
        if mab.ActionBarPageNumber then
            killRegion(mab.ActionBarPageNumber.UpButton)
            killRegion(mab.ActionBarPageNumber.DownButton)
            killRegion(mab.ActionBarPageNumber.Text)
        end
    end
    self:ApplyPetWell()
    self:ApplyCharWell()
    -- Once the anchors above have real positions.
    C_Timer.After(0, function() Bars:ApplyPlate() end)
end

-- ── Pet area ──────────────────────────────────────────────────────────────
-- While you have a pet, its part of the console (pet orbs or pet frame, and
-- the pet action bar) is framed by an inset well, with:
--   * a plate in every pet action slot, so empty slots show like the other
--     bars' do (db.petGrid; Blizzard hides its own empty pet buttons, and
--     those are secure, so the plates are ours, drawn behind them)
--   * a pill on the well's bottom edge, like the minimap's: level | name |
--     mood (hunter pets: Happy / Content / Unhappy, which also colors the
--     pill's ring)
-- None of it is secure: it is shown and hidden freely, in combat too.
local MOOD = {
    { "Unhappy", 0.85, 0.30, 0.25 },
    { "Content", 0.90, 0.75, 0.30 },
    { "Happy",   0.35, 0.78, 0.40 },
}
-- Pet mood (hunter pets). Forever has no GetPetHappiness: the mood is the
-- pet's "happiness" power (0-1000), a hidden value nothing may compare. So
-- the client evaluates curves on it: one per word (1 inside that word's
-- band, 0 outside: used as the word's alpha) and one per ring colour
-- channel. ns.PetMoodCurves() returns them while you have a pet with a
-- mood, else nil; ns.PetMoodPct(curve) evaluates one.
-- Bands: below LOW unhappy, below HIGH content, else happy. (Thirds, the
-- classic server's split; if the word disagrees with the game's own
-- tooltip, these are the numbers.)
local LOW, HIGH, E = 0.333, 0.666, 0.002
local moodCurves
local function curve(pts)
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then return nil end
    if Enum and Enum.LuaCurveType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    for _, pt in ipairs(pts) do c:AddPoint(pt[1], pt[2]) end
    return c
end
local function band(lo, hi)
    local pts = {}
    if lo > 0 then pts[#pts + 1] = { 0, 0 }; pts[#pts + 1] = { lo - E, 0 } end
    pts[#pts + 1] = { math.max(lo, 0), 1 }
    pts[#pts + 1] = { math.min(hi, 1), 1 }
    if hi < 1 then pts[#pts + 1] = { hi + E, 0 }; pts[#pts + 1] = { 1, 0 } end
    return curve(pts)
end
local function channel(k)
    local u, c, h = MOOD[1][k + 1] * 0.8, MOOD[2][k + 1] * 0.8, MOOD[3][k + 1] * 0.8
    return curve({ { 0, u }, { LOW - E, u }, { LOW, c }, { HIGH - E, c }, { HIGH, h }, { 1, h } })
end
local MOOD_OFF = { 0.06, 0.06, 0.07 }
-- Sets a mood word's colour and alpha from the hidden value. (The alpha
-- has to go in the text colour: a hidden value given to SetAlpha, on the
-- font string or on a frame, was stored but not drawn; /men moodprobe.)
function ns.PetMoodWord(fs, c, i)
    local t, p = c.text[i], ns.PetMoodPct
    fs:SetTextColor(p(t[1]), p(t[2]), p(t[3]), p(c[i]))
end
local HAPPY = (Enum and Enum.PowerType and Enum.PowerType.Happiness) or 27
function ns.PetMoodPct(c) return UnitPowerPercent("pet", HAPPY, false, c) end
function ns.PetMoodCurves()
    local max = UnitPowerMax("pet", HAPPY)
    local secret = issecretvalue or function() return false end
    if not (type(max) == "number" and not secret(max) and max > 0) then return nil end
    if moodCurves == nil then
        moodCurves = false
        if UnitPowerPercent and C_CurveUtil and C_CurveUtil.CreateCurve then
            local c = { band(0, LOW - E), band(LOW, HIGH - E), band(HIGH, 1),
                        r = channel(1), g = channel(2), b = channel(3) }
            local ok = true
            for _, k in ipairs({ 1, 2, 3, "r", "g", "b" }) do if not c[k] then ok = false end end
            -- Each word's text colour: its own colour inside its band, the
            -- dark of the pill outside it (in case the alpha is ignored too).
            local los, his = { 0, LOW, HIGH }, { LOW - E, HIGH - E, 1 }
            c.text = {}
            for i = 1, 3 do
                local lo, hi = los[i], his[i]
                local t = {}
                for k = 1, 3 do
                    local on, off = MOOD[i][k + 1], MOOD_OFF[k]
                    local pts = {}
                    if lo > 0 then pts[#pts + 1] = { 0, off }; pts[#pts + 1] = { lo - E, off } end
                    pts[#pts + 1] = { lo, on }
                    pts[#pts + 1] = { hi, on }
                    if hi < 1 then pts[#pts + 1] = { hi + E, off }; pts[#pts + 1] = { 1, off } end
                    t[k] = curve(pts)
                    if not t[k] then ok = false end
                end
                c.text[i] = t
            end
            if ok then moodCurves = c end
        end
    end
    return moodCurves or nil
end
ns.PET_MOOD = MOOD

-- The pill's ring color says what the pet is:
--   hunter pets: their mood (green / yellow / red, as the word beside it)
--   demons: each kind its own color (imp ember, voidwalker deep blue,
--           succubus magenta, felhunter fel green, felguard violet, ...)
--   anything else by creature type, then neutral.
-- Family names are the English client's; other languages fall back to the
-- creature-type color.
local PET_FAMILY = {
    imp          = { 0.95, 0.50, 0.18 },
    voidwalker   = { 0.36, 0.40, 0.92 },
    succubus     = { 0.90, 0.36, 0.66 },
    incubus      = { 0.90, 0.36, 0.66 },
    felhunter    = { 0.45, 0.82, 0.25 },
    felguard     = { 0.62, 0.38, 0.88 },
    infernal     = { 0.60, 0.85, 0.20 },
    doomguard    = { 0.82, 0.24, 0.24 },
    ["water elemental"] = { 0.30, 0.68, 0.95 },
    ghoul        = { 0.45, 0.72, 0.62 },
}
local PET_TYPE = {
    demon     = { 0.62, 0.38, 0.88 },
    beast     = { 0.82, 0.62, 0.30 },
    elemental = { 0.30, 0.68, 0.95 },
    undead    = { 0.45, 0.72, 0.62 },
}
local function petColor()
    local secret = issecretvalue or function() return false end
    local fam = UnitCreatureFamily and UnitCreatureFamily("pet")
    if type(fam) == "string" and not secret(fam) then
        local c = PET_FAMILY[fam:lower()]
        if c then return c end
    end
    local kind = UnitCreatureType and UnitCreatureType("pet")
    if type(kind) == "string" and not secret(kind) then
        local c = PET_TYPE[kind:lower()]
        if c then return c end
    end
    return nil
end

function Bars:ApplyPetWell()
    local slot = self.petSlot
    local w = self.petWell
    if not (slot and slot.well) then
        if w then w.on = false; w:Hide() end
        return
    end
    local s = self.db.small
    if not w then
        w = CreateFrame("Frame", "MinimalUI_PetWell", UIParent)
        w:SetFrameStrata("BACKGROUND")
        w:SetFrameLevel(2)
        ns.RoundedRect(w, -6, 0, 10, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(w, -5, 1, 9, 0.03, 0.03, 0.035, 0.95)
        w.plates = {}
        for i = 1, 10 do
            local pl = CreateFrame("Frame", nil, w)
            pl:SetFrameLevel(w:GetFrameLevel() + 1)
            ns.RoundedRect(pl, -4, 0, 6, T.border[1], T.border[2], T.border[3], 0.7)
            ns.RoundedRect(pl, -3, 1.5, 5, 0.06, 0.06, 0.07, 0.95)
            w.plates[i] = pl
        end

        local pill = CreateFrame("Frame", nil, w)
        pill:SetHeight(14)
        pill:SetFrameLevel(w:GetFrameLevel() + 3)
        pill:EnableMouse(true)
        local paintRing = ns.RoundedRect(pill, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(pill, -7, 1, 6, 0.06, 0.06, 0.07, 0.97)
        local lvl = ns:CreateText(pill, 10, T.textDim)
        lvl:SetPoint("CENTER", pill, "LEFT", 12, 0)
        local div = pill:CreateTexture(nil, "ARTWORK")
        div:SetSize(1, 8)
        div:SetPoint("LEFT", pill, "LEFT", 22, 0)
        div:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
        -- The mood: Forever has no GetPetHappiness; the mood is the pet's
        -- "happiness" power (0-1000), and it is a hidden value, so nothing
        -- here can compare it. Instead all three words sit in the same
        -- place and the client sets each one's alpha from a curve on the
        -- hidden percentage (1 inside that word's band, 0 outside), and the
        -- ring's colour the same way. Content and Unhappy sit in a holder
        -- that pulses, so a pet that isn't happy is hard to miss.
        local mood = ns:CreateText(pill, 10, T.textDim) -- keeps the room for the words
        mood:SetPoint("RIGHT", pill, "RIGHT", -9, 0)
        mood:SetText("Unhappy")
        mood:SetAlpha(0)
        local pulse = CreateFrame("Frame", nil, pill)
        pulse:SetAllPoints()
        local pag = pulse:CreateAnimationGroup()
        pag:SetLooping("BOUNCE")
        local pa = pag:CreateAnimation("Alpha")
        pa:SetFromAlpha(1); pa:SetToAlpha(0.25); pa:SetDuration(0.6); pa:SetSmoothing("IN_OUT")
        pag:Play()
        pulse:SetScript("OnShow", function() pag:Play() end)
        -- Each word in its own frame, and the frame's alpha is what the
        -- curve sets: a hidden value given to a font string's SetAlpha was
        -- ignored (all three words showed), while frames take it (the orbs'
        -- flash works that way).
        local words, wordText = {}, {}
        for i, m in ipairs(MOOD) do
            local wf = CreateFrame("Frame", nil, i == 3 and pill or pulse)
            wf:SetAllPoints(pill)
            local fs = ns:CreateText(wf, 10)
            fs:SetPoint("RIGHT", pill, "RIGHT", -9, 0)
            fs:SetText(m[1])
            fs:SetTextColor(0, 0, 0, 0)
            fs:SetShadowOffset(0, 0)
            words[i], wordText[i] = wf, fs
        end
        local name = ns:CreateText(pill, 11)
        -- Centred on the whole pill (not on the room between the level and
        -- the mood word, which sat it left of centre); its width keeps the
        -- same clearance on both sides, the larger of the two ends.
        name:SetPoint("CENTER", pill, "CENTER", 0, 0)
        function pill.fitName()
            local room = math.max(28, 9 + (mood:GetStringWidth() or 40) + 6)
            name:SetWidth(math.max(40, (pill:GetWidth() or 120) - 2 * room))
        end
        name:SetJustifyH("CENTER")
        name:SetWordWrap(false)
        for _, fs in ipairs({ lvl, mood, name }) do
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 0.8)
        end
        pill:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if pcall(GameTooltip.SetUnit, GameTooltip, "pet") then GameTooltip:Show() end
        end)
        pill:SetScript("OnLeave", function() GameTooltip:Hide() end)
        w.pill = pill

        local secret = issecretvalue or function() return false end
        function w.refresh()
            local has = UnitExists("pet")
            if secret(has) then has = true end
            w:SetShown(w.on and has and true or false)
            if not (w.on and has) then return end
            local l = UnitLevel("pet")
            if l == nil or secret(l) or (type(l) == "number" and l <= 0) then lvl:SetText("") else lvl:SetText(l) end
            -- The name may be a hidden value in combat: it goes straight to
            -- the font string.
            name:SetText((UnitName("pet")))
            local r, g, bl = T.border[1], T.border[2], T.border[3]
            local okc, pc = pcall(petColor)
            if okc and pc then r, g, bl = pc[1] * 0.85, pc[2] * 0.85, pc[3] * 0.85 end
            w.baseRing = w.baseRing or {}
            w.baseRing[1], w.baseRing[2], w.baseRing[3] = r, g, bl
            w.mood()
        end

        local curves
        local pct = ns.PetMoodPct
        local function apply()
            for i = 1, 3 do ns.PetMoodWord(wordText[i], curves, i) end
            paintRing(pct(curves.r), pct(curves.g), pct(curves.b), 1)
        end
        function w.mood()
            curves = ns.PetMoodCurves()
            if curves and pcall(apply) then
                pulse:Show()
                return
            end
            -- Not a hunter pet (or no way to read it): no mood, the pet's own colour.
            for i = 1, 3 do wordText[i]:SetTextColor(0, 0, 0, 0) end
            local c = w.baseRing
            if c then paintRing(c[1], c[2], c[3], 1) end
        end
        -- /men moodprobe: what the curves give and what the words end up at.
        ns.commands.moodprobe = function()
            local out = {}
            local function show(v)
                if issecretvalue and issecretvalue(v) then return "<secret>" end
                return tostring(v)
            end
            local c = ns.PetMoodCurves()
            out[#out + 1] = "curves " .. tostring(c and true or false) .. "  max " .. show(UnitPowerMax("pet", 27))
                .. "  cur " .. show(UnitPower("pet", 27))
            if c then
                for _, k in ipairs({ 1, 2, 3, "r", "g", "b" }) do
                    local ok, v = pcall(ns.PetMoodPct, c[k])
                    out[#out + 1] = "  pct(" .. k .. ") ok=" .. tostring(ok) .. " -> " .. show(v)
                    -- Plain evaluation of the curve itself at a few points.
                    local t = {}
                    for _, x in ipairs({ 0, 0.2, 0.5, 0.9, 1, 50, 100 }) do
                        local ok2, y = pcall(c[k].Evaluate, c[k], x)
                        t[#t + 1] = x .. "=" .. (ok2 and show(y) or "err")
                    end
                    out[#out + 1] = "    curve " .. table.concat(t, " ")
                end
                local okA, errA = pcall(apply)
                out[#out + 1] = "apply ok=" .. tostring(okA) .. " " .. tostring(errA)
            end
            for i = 1, 3 do
                local r, g, b, a = wordText[i]:GetTextColor()
                out[#out + 1] = string.format("word %d text=%s,%s,%s,%s visible=%s", i,
                    show(r), show(g), show(b), show(a), tostring(wordText[i]:IsVisible()))
            end
            out[#out + 1] = "pulse alpha=" .. show(pulse:GetAlpha())
            MinimalUIDB.moodprobe = out
            ns:Print("Pet mood recorded. /reload so it can be read.")
        end
        local ev = CreateFrame("Frame")
        for _, e in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
        pcall(ev.RegisterUnitEvent, ev, "UNIT_PET", "player")
        for _, e in ipairs({ "UNIT_LEVEL", "UNIT_NAME_UPDATE", "UNIT_HAPPINESS" }) do pcall(ev.RegisterUnitEvent, ev, e, "pet") end
        pcall(ev.RegisterUnitEvent, ev, "UNIT_POWER_UPDATE", "pet")
        pcall(ev.RegisterUnitEvent, ev, "UNIT_MAXPOWER", "pet")
        ev:SetScript("OnEvent", function(_, e, _, token)
            if e == "UNIT_POWER_UPDATE" or e == "UNIT_MAXPOWER" then
                -- Only the mood (the pet's energy / focus ticks constantly).
                if token == "HAPPINESS" or (type(token) ~= "string") then
                    if w:IsShown() then w.mood() end
                end
                return
            end
            C_Timer.After(0, w.refresh)
        end)
        self.petWell = w
    end
    local wl = slot.well
    w:ClearAllPoints()
    w:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", wl.x, wl.y)
    w:SetSize(wl.w, wl.h)
    w.pill:ClearAllPoints()
    w.pill:SetPoint("CENTER", w, "BOTTOM", 0, 0)
    w.pill:SetWidth(math.max(120, wl.w)) -- as wide as the well, for long names
    w.pill.fitName()
    local step = s.size + s.gap
    for i, pl in ipairs(w.plates) do
        pl:ClearAllPoints()
        pl:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", slot.x + ((i - 1) % 5) * step,
            slot.gridTop - math.floor((i - 1) / 5) * step)
        pl:SetSize(s.size, s.size)
        pl:SetShown(self.db.petGrid ~= false)
    end
    w.on = true
    w.refresh()
end

-- ── Character area ────────────────────────────────────────────────────────
-- The pet area's twin on the other side: a well holding your portrait (the
-- player frame's own avatar, placed there by UnitFrames.lua) and your buffs
-- and debuffs (Blizzard's frames, seated by Auras.lua), with a pill on its
-- bottom edge carrying your name, ringed in your class color.
function Bars:ApplyCharWell()
    local slot = self.charSlot
    local w = self.charWell
    if not slot then
        if w then w:Hide() end
        return
    end
    if not w then
        w = CreateFrame("Frame", "MinimalUI_CharWell", UIParent)
        w:SetFrameStrata("BACKGROUND")
        w:SetFrameLevel(2)
        ns.RoundedRect(w, -6, 0, 10, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(w, -5, 1, 9, 0.03, 0.03, 0.035, 0.95)
        local pill = CreateFrame("Frame", nil, w)
        pill:SetHeight(14)
        pill:SetFrameLevel(w:GetFrameLevel() + 3)
        pill:EnableMouse(true)
        local paintRing = ns.RoundedRect(pill, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(pill, -7, 1, 6, 0.06, 0.06, 0.07, 0.97)
        local name = ns:CreateText(pill, 11)
        name:SetPoint("LEFT", 10, 0); name:SetPoint("RIGHT", -10, 0)
        name:SetJustifyH("CENTER")
        name:SetWordWrap(false)
        name:SetShadowOffset(1, -1)
        name:SetShadowColor(0, 0, 0, 0.8)
        pill:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if pcall(GameTooltip.SetUnit, GameTooltip, "player") then GameTooltip:Show() end
        end)
        pill:SetScript("OnLeave", function() GameTooltip:Hide() end)
        w.pill = pill

        -- Level at the pill's left end, behind a divider (as on the pet's
        -- pill); it moved here from the health orb's pill.
        local lvl = ns:CreateText(pill, 10, T.textDim)
        -- (Its section is as wide as XP's at the other end.)
        lvl:SetPoint("CENTER", pill, "LEFT", 17, 0)
        lvl:SetShadowOffset(1, -1)
        lvl:SetShadowColor(0, 0, 0, 0.8)
        local ldiv = pill:CreateTexture(nil, "ARTWORK")
        ldiv:SetSize(1, 8)
        ldiv:SetPoint("LEFT", pill, "LEFT", 33, 0)
        ldiv:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
        local function refreshLevel(_, _, newLevel)
            local l = type(newLevel) == "number" and newLevel or UnitLevel("player")
            if l == nil or (issecretvalue and issecretvalue(l)) then lvl:SetText("") else lvl:SetText(l) end
        end
        local lev = CreateFrame("Frame")
        lev:RegisterEvent("PLAYER_LEVEL_UP")
        lev:RegisterEvent("PLAYER_ENTERING_WORLD")
        lev:SetScript("OnEvent", refreshLevel)
        refreshLevel()

        -- XP as a percentage at the pill's right end, behind a divider (the
        -- bar itself stays under the action bars). Blue while rested. Gone
        -- at max level, or when the client hides the numbers.
        local xp = ns:CreateText(pill, 10, T.textDim)
        xp:SetPoint("CENTER", pill, "RIGHT", -17, 0)
        xp:SetShadowOffset(1, -1)
        xp:SetShadowColor(0, 0, 0, 0.8)
        local xdiv = pill:CreateTexture(nil, "ARTWORK")
        xdiv:SetSize(1, 8)
        xdiv:SetPoint("RIGHT", pill, "RIGHT", -33, 0)
        xdiv:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
        local function refreshXP()
            local secret = issecretvalue or function() return false end
            local cur, max = UnitXP("player"), UnitXPMax("player")
            local capped = IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()
            local show = type(cur) == "number" and type(max) == "number" and not secret(cur) and not secret(max)
                and max > 0 and not capped
            xp:SetShown(show and true or false)
            xdiv:SetShown(show and true or false)
            -- The name stays centered on the pill: the same room is kept
            -- clear on both sides.
            local inset = 36 -- the level's section on the left, XP's (or its mirror) on the right
            name:ClearAllPoints()
            name:SetPoint("LEFT", inset, 0); name:SetPoint("RIGHT", -inset, 0)
            if not show then return end
            xp:SetText(math.floor(cur / max * 100) .. "%")
            local rested = GetXPExhaustion and GetXPExhaustion()
            if type(rested) == "number" and not secret(rested) and rested > 0 then
                xp:SetTextColor(0.45, 0.65, 1.0)
            else
                xp:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
            end
        end
        local xev = CreateFrame("Frame")
        for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_ENTERING_WORLD" }) do
            pcall(xev.RegisterEvent, xev, e)
        end
        xev:SetScript("OnEvent", function() C_Timer.After(0, refreshXP) end)
        w.refreshXP = refreshXP

        function w.refresh()
            -- First and second name (Character.lua knows where this client
            -- keeps the second one).
            local CM = ns.modules.Character
            local ok, full
            if CM and CM.FullName then ok, full = pcall(CM.FullName, "player") end
            if not ok or type(full) ~= "string" then full = (UnitName("player")) end
            name:SetText(full)
            local _, class = UnitClass("player")
            local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
            if c then paintRing(c.r * 0.85, c.g * 0.85, c.b * 0.85, 1) end
        end
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        pcall(ev.RegisterUnitEvent, ev, "UNIT_NAME_UPDATE", "player")
        ev:SetScript("OnEvent", function() w.refresh() end)
        self.charWell = w
    end
    local wl = slot.well
    w:ClearAllPoints()
    w:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", wl.x, wl.y)
    w:SetSize(wl.w, wl.h)
    w.pill:ClearAllPoints()
    w.pill:SetPoint("CENTER", w, "BOTTOM", 0, 0)
    w.pill:SetWidth(math.max(120, wl.w)) -- as wide as the well, for long names
    w:Show()
    w.refresh()
    w.refreshXP()
end

ns.commands.petgrid = function()
    Bars.db.petGrid = Bars.db.petGrid == false
    Bars:ApplyPetWell()
    ns:Print("Empty pet action slots", Bars.db.petGrid and "shown" or "hidden")
end

-- ── Micro menu glyphs ─────────────────────────────────────────────────────
-- Our own icons for the micro menu buttons, in the dim text color,
-- brightening on hover. They are vector drawings rendered to small textures
-- (Media/micro_<name>.tga, made by dist/icons.py: edit the shapes there and
-- re-run it). Drawing them in game from lines and circles was tried first
-- and looked rough at this size: no smoothing, and corners that didn't
-- quite meet.
-- A button is matched by a word in its name or its tooltip title; a button
-- nobody matches keeps Blizzard's (greyed) art. The buttons underneath are
-- untouched: clicks, tooltips and key bindings are theirs.
local MICRO_GLYPHS = {
    { "character", "character" }, { "profession", "profession" },
    { "spell", "spell" }, { "talent", "talent" },
    { "achievement", "achievement" }, { "legacy", "legacy" },
    { "quest", "quest" }, { "guild", "guild" },
    { "lfd", "group" }, { "lfg", "group" }, { "group", "group" },
    { "collection", "collection" },
    { "ej", "journal" }, { "journal", "journal" }, { "adventure", "journal" },
    { "store", "store" }, { "shop", "store" },
    { "mainmenu", "mainmenu" }, { "help", "help" },
}
local MICRO_MEDIA = "Interface/AddOns/Meniscus/Media/micro_"

local function microGlyph(btn)
    if btn.__muiGlyph ~= nil then return btn.__muiGlyph end
    -- Matched on the button's name and, failing that, on its tooltip title
    -- (a button can be named for one thing and labelled another).
    local name = (btn.GetName and btn:GetName() or ""):lower()
    local tip = rawget(btn, "tooltipText")
    if type(tip) == "string" then name = name .. " " .. tip:lower() end
    local file
    for _, g in ipairs(MICRO_GLYPHS) do
        if name:find(g[1], 1, true) then file = g[2] break end
    end
    if not file then btn.__muiGlyph = false return false end
    local w, h = btn:GetWidth(), btn:GetHeight()
    -- Sized from the button's width, which is also how far apart the
    -- buttons sit: the drawings fill the middle two thirds of their texture,
    -- so each icon covers about half its button's width and the gap to the
    -- next one is about as wide as the icon.
    local S = w * 0.82
    local f = CreateFrame("Frame", nil, btn)
    f:SetSize(S, S)
    f:SetPoint("CENTER", btn, "CENTER", 0, 0)
    f:SetFrameLevel(btn:GetFrameLevel() + 2)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(MICRO_MEDIA .. file .. ".tga")
    local function tint(c) tex:SetVertexColor(c[1], c[2], c[3], 1) end
    tint(T.textDim)
    btn:HookScript("OnEnter", function() tint(T.text) end)
    btn:HookScript("OnLeave", function() tint(T.textDim) end)
    -- Blizzard's art on this button goes (and stays gone: it is re-shown
    -- on every state change).
    for _, reg in ipairs({ btn:GetRegions() }) do
        if reg:IsObjectType("Texture") and not reg.__muiGone then
            reg.__muiGone = true
            reg:SetAlpha(0)
            hooksecurefunc(reg, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
        end
    end
    btn.__muiGlyph = f
    return f
end

-- ── Console plate ─────────────────────────────────────────────────────────
-- One card behind the whole bottom row, in the windows' own language (dark
-- fill, hairline rounded border), from the screen's bottom edge to just
-- above the main bar; the orbs and the minimap dome rise out of its top
-- edge. With wings on it runs the full width of the screen, and the chat
-- window (left) and the damage meter (right) are seated in it, each in a
-- slightly darker inset well.
-- It is placed from measured positions (not anchored to the secure bars),
-- so it never runs into combat restrictions; it follows the layout on the
-- next arrange / reload, not while an orb is being dragged.
--
-- Seated frames are Blizzard's (Edit Mode's): they are not reparented, only
-- re-anchored and re-sized, and put back whenever Blizzard's own layout
-- moves them (hooks on SetPoint / SetSize), as with the minimap dome and the
-- buff frames.
local PLATE_PAD, EDGE, WELL_PAD = 14, 8, 10
local seats, hooked, seating = {}, {}, false
local function reseat(f)
    local s = seats[f]
    if not s or seating then return end
    seating = true
    pcall(function()
        f:ClearAllPoints()
        if s.rel then
            if s.scale then f:SetScale(s.scale) end
            -- (ox / oy are in the frame's own units, as SetPoint expects.)
            f:SetPoint("CENTER", s.rel, "CENTER", s.ox or 0, s.oy or 0)
        else
            f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s.x, s.y)
            if s.w and s.h then f:SetSize(s.w, s.h) elseif s.w then f:SetWidth(s.w) end
        end
    end)
    seating = false
end
-- Centered on one of our own frames, at a scale of our choosing.
local function seatOn(f, rel, scale)
    if not f then return end
    seats[f] = { rel = rel, scale = scale }
    if not hooked[f] then
        hooked[f] = true
        hooksecurefunc(f, "SetPoint", function(self) if not seating then reseat(self) end end)
    end
    reseat(f)
end
local function seat(f, x, y, w, h)
    if not f then return end
    seats[f] = { x = x, y = y, w = w, h = h }
    if not hooked[f] then
        hooked[f] = true
        hooksecurefunc(f, "SetPoint", function(self) if not seating then reseat(self) end end)
        if w then
            hooksecurefunc(f, "SetSize", function(self) if not seating then reseat(self) end end)
        end
    end
    reseat(f)
end

-- The console's geometry, worked out from the settings (not measured, so it
-- is available before anything has been laid out): the vertical range
-- inside the plate, and the two free slots between the chat / meter panels
-- and the side bars. nil unless the split bar, the plate and its wings are
-- all on.
--   left slot:  buffs over debuffs (Auras.lua)
--   right slot: the pet (its orbs / frame and its action bar)
function Bars:Slots()
    local db, gap = self.db, self.split
    if not (db and gap and db.plate and db.wings) then return nil end
    local O = ns.modules.Orbs
    local od = (O and O.db) or (ns.db and ns.db.modules and ns.db.modules.Orbs) or {}
    local m, s = db.main, db.small
    local sw = UIParent:GetWidth()
    local cx = sw / 2 + m.x
    local blockW = 3 * m.size + 2 * m.gap
    local mainW, mainH = 2 * blockW + gap, 2 * m.size + m.gap
    local sideW = s.cols * s.size + (s.cols - 1) * s.gap
    -- From the center out to a side bar's outer edge.
    local reach = mainW / 2 + 14 + (od.size or 120) + s.margin + sideW
    local pl, pr = EDGE, sw - EDGE
    local bottom, ptop = 2, m.y + mainH + 12
    local fill = math.max(0.25, math.min(1, db.wingFill or 0.5))
    local lx0, lxFull = pl + WELL_PAD, cx - reach - PLATE_PAD - WELL_PAD
    local rxFull, rx1 = cx + reach + PLATE_PAD + WELL_PAD, pr - WELL_PAD
    return {
        y0 = bottom + 8, y1 = ptop - 8,
        left = { x0 = lx0 + (lxFull - lx0) * fill + WELL_PAD, x1 = lxFull },
        right = { x0 = rxFull, x1 = rx1 - (rx1 - rxFull) * fill - WELL_PAD },
    }
end

local function well(plate, key)
    local wl = plate[key]
    if not wl then
        wl = CreateFrame("Frame", nil, plate)
        wl:SetFrameLevel(plate:GetFrameLevel() + 1)
        ns.RoundedRect(wl, -6, 0, 10, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(wl, -5, 1, 9, 0.03, 0.03, 0.035, 0.95)
        plate[key] = wl
    end
    return wl
end

-- What the damage meter is on this client (MinimalUIDB.dmseat), for
-- fitting it to its well properly.
local function probeMeter(root, wantW, wantH)
    if not MinimalUIDB then return end
    local out = {}
    local function line(tag, f, depth)
        local ok, s = pcall(function()
            local p, rel, rp, x, y = f:GetPoint(1)
            return string.rep("  ", depth) .. tag .. " [" .. f:GetObjectType() .. "] " .. tostring(f:GetName() or "?")
                .. (f:IsShown() and "" or " hidden")
                .. string.format(" %.0fx%.0f", f:GetWidth(), f:GetHeight())
                .. " @" .. tostring(p) .. ">" .. tostring(rel and (rel.GetName and rel:GetName() or "?")) .. " " .. tostring(rp)
                .. string.format(" %.0f,%.0f", x or 0, y or 0)
                .. " scale=" .. string.format("%.2f", f:GetScale())
                .. " resizable=" .. tostring(f.IsResizable and f:IsResizable())
        end)
        out[#out + 1] = ok and s or (tag .. " error: " .. tostring(s))
    end
    out[1] = string.format("wanted %.0fx%.0f", wantW, wantH)
    line("DamageMeter", root, 0)
    local names = {}
    for k, v in pairs(root) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
    for _, c in ipairs({ root:GetChildren() }) do
        line(names[c] or "#", c, 1)
        local n = 0
        for _, g in ipairs({ c:GetChildren() }) do
            n = n + 1
            if n <= 6 then line("#", g, 2) end
        end
    end
    MinimalUIDB.dmseat = out
end

function Bars:ApplyPlate()
    -- (The bag pill is a secure button: nothing here runs in combat; the
    -- next arrange after the fight catches up.)
    if InCombatLockdown() then self.pending = true return end
    local p = self.plate
    if not (self.db and self.db.plate) then
        if p then p:Hide() end
        return
    end
    local l, r, m = self.block2, self.block3, self.main
    local left, right, top = l and l:GetLeft(), r and r:GetRight(), m and m:GetTop()
    if not (left and right and top) then
        -- Layout not resolved yet (first frame after login).
        if not self.plateRetry then
            self.plateRetry = true
            C_Timer.After(0.5, function() Bars.plateRetry = false; Bars:ApplyPlate() end)
        end
        return
    end
    if not p then
        p = CreateFrame("Frame", "MinimalUI_Console", UIParent)
        p:SetFrameStrata("BACKGROUND")
        p:SetFrameLevel(0)
        p:EnableMouse(false)
        ns.RoundedRect(p, -8, 0, 16, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(p, -7, 1, 15, 0.05, 0.05, 0.06, 0.90)
        -- (The header bands' noise grain was tried on the plate and dropped.)
        self.plate = p
    end
    local bottom, ptop = 2, top + 12
    local wings = self.db.wings
    local pl, pr = left - PLATE_PAD, right + PLATE_PAD
    if wings then pl, pr = EDGE, UIParent:GetWidth() - EDGE end
    p:ClearAllPoints()
    p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pl, bottom)
    p:SetSize(pr - pl, ptop - bottom)
    p:Show()

    -- Wings: a rounded panel at each end of the plate, taller than the plate
    -- so it rises out of its top edge the way the orbs do. Chat sits in the
    -- left one, the damage meter in the right one, and each has a pill on
    -- its bottom edge: the micro menu (left) and the bags (right).
    local WING_H, PILL_H = 210, 22
    local wy = bottom + 12 -- room for the pill's lower half above the screen edge
    local lx0, lx1 = pl + WELL_PAD, left - PLATE_PAD - WELL_PAD
    local rx0, rx1 = right + PLATE_PAD + WELL_PAD, pr - WELL_PAD
    -- The panels take only part of their wing, hugging the screen edges.
    local fill = math.max(0.25, math.min(1, self.db.wingFill or 0.5))
    lx1 = lx0 + (lx1 - lx0) * fill
    rx0 = rx1 - (rx1 - rx0) * fill
    local chatOK = wings and (lx1 - lx0) >= 140 and _G.ChatFrame1
    local meterOK = wings and (rx1 - rx0) >= 120 and _G.DamageMeter
    ns.consoleMenus = (chatOK or meterOK) and true or false -- Declutter.lua stops fading them
    if p.chatWell then p.chatWell:SetShown(chatOK and true or false) end
    if p.meterWell then p.meterWell:SetShown(meterOK and true or false) end

    local function pillOn(wl, key)
        local pill = wl[key]
        if not pill then
            pill = CreateFrame("Frame", nil, wl)
            pill:SetFrameLevel(wl:GetFrameLevel() + 2)
            pill.paintRing = ns.RoundedRect(pill, -8, 0, PILL_H / 2, T.border[1], T.border[2], T.border[3], 1)
            ns.RoundedRect(pill, -7, 1, PILL_H / 2 - 1, 0.06, 0.06, 0.07, 0.97)
            wl[key] = pill
        end
        pill:ClearAllPoints()
        pill:SetPoint("CENTER", wl, "BOTTOM", 0, 0)
        pill:SetSize(math.max(100, wl:GetWidth() - 28), PILL_H)
        return pill
    end

    if chatOK then
        local wl = well(p, "chatWell")
        wl:ClearAllPoints()
        wl:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", lx0, wy)
        wl:SetSize(lx1 - lx0, WING_H)
        wl:Show()
        -- From the bottom up: the pill's upper half, the edit box strip, the
        -- messages, then the tabs, which Blizzard hangs on top of the
        -- message area (so they end up just inside the wing's top edge).
        local EB, TABS = 28, 24
        local base = wy + PILL_H / 2 + 2
        local cf = _G.ChatFrame1
        pcall(cf.SetClampRectInsets, cf, 0, 0, 0, 0)
        pcall(cf.SetClampedToScreen, cf, false)
        seat(cf, lx0 + 8, base + EB + 2, (lx1 - lx0) - 16, (wy + WING_H - 8 - TABS) - (base + EB + 2))
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if eb then seat(eb, lx0, base - 2, lx1 - lx0) end
        end
        -- The wing is the chat's background now: Blizzard's own (which also
        -- shades a strip beside the window on hover) is switched off.
        local CHm = ns.modules.Chat
        if CHm and CHm.Seated then pcall(CHm.Seated, CHm) end

        -- Micro menu: Blizzard's own buttons, scaled to the pill and held on
        -- it, in grey (their art is recolored, not replaced).
        local pill = pillOn(wl, "menuPill")
        local mm = _G.MicroMenu
        if mm then
            pcall(function()
                -- Measured from the buttons themselves: the menu frame's own
                -- box is larger than what they cover and not centered on
                -- them, which left the row small and low in the pill.
                local l, r2, tp, bt
                local es = mm:GetEffectiveScale()
                for _, btn in ipairs({ mm:GetChildren() }) do
                    if btn:IsShown() and btn:GetLeft() then
                        local k = btn:GetEffectiveScale() / es
                        local bl, br, btp, bb = btn:GetLeft() * k, btn:GetRight() * k, btn:GetTop() * k, btn:GetBottom() * k
                        l = l and math.min(l, bl) or bl
                        r2 = r2 and math.max(r2, br) or br
                        tp = tp and math.max(tp, btp) or btp
                        bt = bt and math.min(bt, bb) or bb
                    end
                    local okg, glyph = pcall(microGlyph, btn)
                    if MinimalUIDB then
                        MinimalUIDB.microprobe = MinimalUIDB.microprobe or {}
                        MinimalUIDB.microprobe[tostring(btn.GetName and btn:GetName() or "?")] =
                            (okg and glyph) and "drawn" or ("stock (" .. tostring(not okg and glyph or "no match") .. ")")
                    end
                    if not (okg and glyph) then
                        -- No glyph of ours for this one: Blizzard's art, greyed.
                        for _, reg in ipairs({ btn:GetRegions() }) do
                            if reg:IsObjectType("Texture") then
                                pcall(reg.SetDesaturated, reg, true)
                                pcall(reg.SetVertexColor, reg, 1, 1, 1, 1)
                            end
                        end
                    end
                    -- The dark tile behind each icon: the pill is the tile.
                    for _, key in ipairs({ "Background", "PushedBackground" }) do
                        local tile = btn[key]
                        if tile and tile.SetAlpha and not tile.__muiGone then
                            tile.__muiGone = true
                            tile:SetAlpha(0)
                            hooksecurefunc(tile, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
                        end
                    end
                end
                for _, holder in ipairs({ mm, _G.MicroMenuContainer }) do
                    if holder then
                        for _, reg in ipairs({ holder:GetRegions() }) do pcall(reg.SetAlpha, reg, 0) end
                    end
                end
                if l and (r2 - l) > 0 and (tp - bt) > 0 then
                    local cur = mm:GetScale()
                    local parentScale = es / cur
                    -- Sized to sit inside the pill's height (their art fills
                    -- its box), and never wider than the pill.
                    -- (With their tiles hidden the glyphs are smaller than the
                    -- buttons, so the buttons may stand a little past the pill.)
                    local k = math.min((pill:GetWidth() - 14) / (r2 - l), (PILL_H + 5) / (tp - bt))
                    -- Where the buttons' center is relative to the menu's.
                    local mcx, mcy = (mm:GetLeft() + mm:GetRight()) / 2, (mm:GetTop() + mm:GetBottom()) / 2
                    local ox, oy = (l + r2) / 2 - mcx, (tp + bt) / 2 - mcy
                    local _ = parentScale
                    seats[mm] = { rel = pill, scale = k, ox = -ox, oy = -oy }
                    if not hooked[mm] then
                        hooked[mm] = true
                        hooksecurefunc(mm, "SetPoint", function(self) if not seating then reseat(self) end end)
                    end
                    reseat(mm)
                end
            end)
        end
    end

    if meterOK then
        local wl = well(p, "meterWell")
        wl:ClearAllPoints()
        wl:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rx0, wy)
        wl:SetSize(rx1 - rx0, WING_H)
        wl:Show()
        -- The meter fills the wing above the pill. Its own card is switched
        -- off while it is seated (ns.dmNoCard, Skins.lua): the wing is its
        -- frame.
        local dm = _G.DamageMeter
        local base = wy + PILL_H / 2 + 4
        local w, h = (rx1 - rx0) - 12, (wy + WING_H - 6) - base
        -- The wing is a context panel (Tracker.lua): a tab strip on top, and
        -- under it either the meter or our objectives list.
        local TRK = ns.modules.Tracker
        local tabs = (TRK and TRK.Console and TRK.db) and 24 or 0
        seat(dm, rx0 + 6, base, w, h - tabs)
        if tabs > 0 then pcall(TRK.Console, TRK, rx0 + 6, base, w, h) end

        -- Bags: free / total slots; a click opens our bags (through the
        -- secure toggle, so it works in combat). Blizzard's bag bar is moved
        -- off screen while this is on.
        local pill = pillOn(wl, "bagPill")
        local btn = pill.btn
        if not btn then
            btn = CreateFrame("Button", "MinimalUI_BagPill", pill, "SecureActionButtonTemplate")
            btn:SetAllPoints(pill)
            btn:SetAttribute("type", "click")
            btn:SetAttribute("clickbutton", _G.MinimalUIBagsToggle)
            btn:RegisterForClicks("AnyDown", "AnyUp")
            local label = ns:CreateText(btn, 10, T.textDim)
            label:SetPoint("LEFT", 12, 0)
            label:SetText("Bags")
            local count = ns:CreateText(btn, 11)
            count:SetPoint("LEFT", label, "RIGHT", 8, 0)
            -- Your money on the right: gold / silver / copper, zero parts
            -- left out, the letters in their coin colors.
            local coins = ns:CreateText(btn, 11)
            coins:SetPoint("RIGHT", -12, 0)
            for _, fs in ipairs({ label, count, coins }) do
                fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.8)
            end
            local function refreshMoney()
                local m = GetMoney and GetMoney() or 0
                if type(m) ~= "number" or (issecretvalue and issecretvalue(m)) then coins:SetText("") return end
                local g, s, c = math.floor(m / 10000), math.floor(m / 100) % 100, m % 100
                local parts = {}
                if g > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. "|cffffd24ag|r" end
                if s > 0 or g > 0 then parts[#parts + 1] = s .. "|cffc7c7cfs|r" end
                parts[#parts + 1] = c .. "|cffd98a4cc|r"
                coins:SetText(table.concat(parts, " "))
            end
            local mev = CreateFrame("Frame")
            mev:RegisterEvent("PLAYER_MONEY")
            mev:RegisterEvent("PLAYER_ENTERING_WORLD")
            mev:SetScript("OnEvent", refreshMoney)
            refreshMoney()
            local function refresh()
                local free, total = 0, 0
                local CC = C_Container
                if CC and CC.GetContainerNumSlots then
                    for bag = 0, (NUM_BAG_SLOTS or 4) do
                        local n = CC.GetContainerNumSlots(bag) or 0
                        total = total + n
                        if n > 0 then free = free + (CC.GetContainerNumFreeSlots(bag) or 0) end
                    end
                end
                count:SetText(free .. " / " .. total)
                if total > 0 and free == 0 then count:SetTextColor(0.90, 0.35, 0.30)
                elseif total > 0 and free <= 3 then count:SetTextColor(0.92, 0.76, 0.32)
                else count:SetTextColor(T.text[1], T.text[2], T.text[3]) end
            end
            local ev = CreateFrame("Frame")
            ev:RegisterEvent("BAG_UPDATE_DELAYED")
            ev:RegisterEvent("PLAYER_ENTERING_WORLD")
            ev:SetScript("OnEvent", refresh)
            refresh()
            btn:SetScript("OnEnter", function() pill.paintRing(0.42, 0.42, 0.47, 1) end)
            btn:SetScript("OnLeave", function() pill.paintRing(T.border[1], T.border[2], T.border[3], 1) end)
            pill.btn = btn
        end
        if _G.BagsBar then
            pcall(_G.BagsBar.SetClampedToScreen, _G.BagsBar, false)
            seat(_G.BagsBar, -3000, -3000)
        end
    end

    if not self.trackerProbed then
        self.trackerProbed = true
        C_Timer.After(4, function() pcall(Bars.ProbeTracker, Bars) end)
    end
end

-- What the quest tracker is on this client (MinimalUIDB.trackerprobe), for
-- seating it in the right wing as an "Objectives" tab.
function Bars:ProbeTracker()
    if not MinimalUIDB then return end
    local out = {}
    local tr = _G.ObjectiveTrackerFrame
    if not tr then MinimalUIDB.trackerprobe = { "ObjectiveTrackerFrame missing" } return end
    local function line(tag, f, depth)
        local ok, s = pcall(function()
            local p, rel, rp, x, y = f:GetPoint(1)
            local prot = f.IsProtected and select(1, f:IsProtected())
            return string.rep("  ", depth) .. tag .. " [" .. f:GetObjectType() .. "] " .. tostring(f:GetName() or "?")
                .. (f:IsShown() and "" or " hidden")
                .. string.format(" %.0fx%.0f", f:GetWidth(), f:GetHeight())
                .. " @" .. tostring(p) .. ">" .. tostring(rel and (rel.GetName and rel:GetName() or "?")) .. " " .. tostring(rp)
                .. string.format(" %.0f,%.0f", x or 0, y or 0)
                .. " scale=" .. string.format("%.2f", f:GetScale())
                .. " strata=" .. tostring(f:GetFrameStrata())
                .. " protected=" .. tostring(prot) .. " points=" .. tostring(f:GetNumPoints())
        end)
        out[#out + 1] = ok and s or (tag .. " error: " .. tostring(s))
    end
    line("ObjectiveTrackerFrame", tr, 0)
    local keys = {}
    for k, v in pairs(tr) do
        local t = type(v)
        if type(k) == "string" and (t == "number" or t == "boolean" or t == "string") then
            keys[#keys + 1] = k .. "=" .. tostring(v)
        end
    end
    table.sort(keys)
    out[#out + 1] = "fields: " .. table.concat(keys, ", ")
    local names = {}
    for k, v in pairs(tr) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
    for _, c in ipairs({ tr:GetChildren() }) do
        line(names[c] or "#", c, 1)
        local n = 0
        for _, g in ipairs({ c:GetChildren() }) do
            n = n + 1
            if n <= 5 then line("#", g, 2) end
        end
    end
    local methods = {}
    for _, mname in ipairs({ "SetHeight", "UpdateHeight", "Update", "SetCollapsed", "GetAvailableHeight", "UpdateSystem" }) do
        methods[#methods + 1] = mname .. "=" .. tostring(type(tr[mname]) == "function")
    end
    out[#out + 1] = "methods: " .. table.concat(methods, ", ")
    out[#out + 1] = string.format("screen %.0fx%.0f", UIParent:GetWidth(), UIParent:GetHeight())
    MinimalUIDB.trackerprobe = out
end

ns.commands.console = function(rest)
    if rest and rest:find("wings") then
        Bars.db.wings = not Bars.db.wings
        Bars:ApplyPlate()
        if Bars.db.wings then
            ns:Print("Console wings on: chat and damage meter seated in the plate.")
        else
            ns.needsReload = true
            ns:Print("Console wings off: /reload to hand chat and the damage meter back to Edit Mode.")
        end
        return
    end
    Bars.db.plate = not Bars.db.plate
    Bars:ApplyPlate()
    ns:Print("Bottom console plate", Bars.db.plate and "on" or "off")
end

-- Pet buttons: no keybind text (ctrl-1… cluttered the small tiles) and
-- Blizzard's autocast corner brackets/shine replaced by the button's own ring
-- turning accent blue while autocast is on. Alpha only (secure buttons).
local function fadeKeep(obj)
    if not obj or not obj.SetAlpha or obj.__muiFaded then return end
    obj.__muiFaded = true
    obj:SetAlpha(0)
    hooksecurefunc(obj, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
end

function Bars:SkinPetButton(pb, i)
    if not pb.__muiPet then
        pb.__muiPet = true
        local name = pb:GetName()
        fadeKeep(pb.HotKey)
        for _, k in ipairs({ "AutoCastable", "AutoCastShine", "AutoCastOverlay", "SpellHighlightTexture" }) do
            fadeKeep(pb[k])
        end
        fadeKeep(_G[name .. "AutoCastable"])
        fadeKeep(_G[name .. "Shine"])
        fadeKeep(_G[name .. "AutoCast"])
    end
    pb.__muiPetIndex = i
end

function Bars:UpdatePetAutocast()
    if not GetPetActionInfo then return end
    for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
        local pb = _G["PetActionButton" .. i]
        if pb and pb.__muiRing then
            local ok, _, _, _, _, allowed, enabled = pcall(GetPetActionInfo, i)
            if ok and enabled and not (issecretvalue and issecretvalue(enabled)) then
                pb.__muiRing:SetColorTexture(unpack(T.accent))
            else
                pb.__muiRing:SetColorTexture(unpack(T.border))
            end
        end
    end
end

function Bars:OnInit(db)
    self.db = db
    -- Seated in a wing, the damage meter doesn't draw its own card. Decided
    -- before its first styling pass (Skins.lua).
    ns.dmNoCard = (db.plate and db.wings) and true or false
    self:Arrange()
    local pev = CreateFrame("Frame")
    for _, e in ipairs({ "PET_BAR_UPDATE", "UNIT_PET", "PET_UI_UPDATE", "PLAYER_ENTERING_WORLD",
                         "PET_BAR_UPDATE_USABLE", "PLAYER_CONTROL_GAINED" }) do
        pcall(pev.RegisterEvent, pev, e)
    end
    pev:SetScript("OnEvent", function()
        C_Timer.After(0, function() Bars:UpdatePetAutocast() end)
    end)

    for _, bar in ipairs({ MainActionBar, MultiBarBottomLeft, MultiBarBottomRight, StanceBar, PetActionBar }) do
        if bar and bar.UpdateGridLayout then
            hooksecurefunc(bar, "UpdateGridLayout", function() Bars:Arrange() end)
        end
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() Bars:Arrange() end)
end

-- ── Move the main bar with /men unlock | lock | reset ─────────────────────
local overlay
local function mainOverlay()
    if overlay then return overlay end
    local o = ns:CreatePanel(UIParent)
    o:SetAllPoints(Bars.main)
    o:SetFrameStrata("DIALOG")
    o.bg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.7)
    o:SetBorderColor(unpack(T.accent))
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    local label = ns:CreateText(o, 11)
    label:SetTextColor(0.07, 0.07, 0.08, 1)
    label:SetShadowColor(1, 1, 1, 0.25)
    label:SetPoint("CENTER")
    label:SetText("main bar (drag)")
    Bars.main:SetMovable(true)
    Bars.main:SetClampedToScreen(true)
    ns:RegisterSnapTarget(Bars.main)
    o:SetScript("OnDragStart", function()
        ns:SnapDragStart(Bars.main)
    end)
    o:SetScript("OnDragStop", function()
        ns:SnapDragStop()
        if InCombatLockdown() then return end
        local cx = Bars.main:GetCenter()
        local ux = UIParent:GetCenter()
        local m = Bars.db.main
        m.x = math.floor(cx - ux + 0.5)
        m.y = math.floor(Bars.main:GetBottom() + 0.5)
        Bars:Arrange()
    end)
    overlay = o
    return o
end

local baseUnlock, baseLock, baseReset = ns.commands.unlock, ns.commands.lock, ns.commands.reset
ns.commands.unlock = function(...)
    if baseUnlock then baseUnlock(...) end
    if not InCombatLockdown() and Bars.main then mainOverlay():Show() end
end
ns.commands.lock = function(...)
    if baseLock then baseLock(...) end
    if overlay then overlay:Hide() end
end
ns.commands.reset = function(...)
    if baseReset then baseReset(...) end
    if InCombatLockdown() or not Bars.db then return end
    Bars.db.main.x, Bars.db.main.y = DEFAULT_MAIN.x, DEFAULT_MAIN.y
    Bars:Arrange()
end

ns.commands.actionbars = function()
    local mdb = ns.db.modules.Bars
    mdb.enabled = not (mdb.enabled ~= false)
    ns:Print("Action bar styling", mdb.enabled and "enabled" or "disabled", "- /reload to apply")
end

ns.commands.barerr = function()
    ns:Print("last Bars error:", tostring(Bars.lastError))
end

-- Stances learned or lost (a new form, a respec): the stance row's width and
-- the things stacked above it change. Re-arranged out of combat only.
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    local owed, last = false, -1
    ev:SetScript("OnEvent", function(_, e)
        if e == "UPDATE_SHAPESHIFT_FORMS" then
            local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
            if n == last then return end
            last, owed = n, true
        end
        if not owed or InCombatLockdown() or not Bars.main then return end
        owed = false
        local MM = ns.modules.Minimap
        if MM and MM.ArrangeAround then pcall(MM.ArrangeAround, MM) else pcall(Bars.Arrange, Bars) end
    end)
end
