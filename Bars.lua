local _, ns = ...
local T = ns.Theme

-- Restyles Blizzard's own action buttons (so paging/stances keep working) and
-- lays them out:
--   [bar 2: 3x4] [health orb] [ main bar: 12 in a row ] [power orb] [bar 3: 3x4]
-- With the minimap dome on (Minimap.lua) the main bar splits around it:
--   [health orb] [1 2 3 / 4 5 6] ( dome ) [7 8 9 / 0 - =] [power orb]
-- (two blocks of 3 x 2: a single split row would not fit between the orbs).
-- Bar 2 / bar 3 blocks are anchored to the orbs, so they follow when orbs move.
-- Escape hatch if anything misbehaves: /mui actionbars, then /reload.

local DEFAULT_MAIN = { x = 0, y = 30 }

local Bars = ns:NewModule("Bars", {
    enabled = true,
    main  = { size = 44, gap = 4, x = DEFAULT_MAIN.x, y = DEFAULT_MAIN.y },
    small = { size = 26, gap = 3, cols = 4, margin = 14 }, -- ~60% of main
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

local ROUND = "Interface/AddOns/MinimalUI/Media/rounded.tga"

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
    local step = s.size + s.gap
    for i = 1, 10 do
        local col, up = i - 1, 0
        if gap then col, up = (i - 1) % 5, math.floor((i - 1) / 5) * step end
        local b = _G["StanceButton" .. i]
        if b then
            skin(b, 8, 1.5)
            safe(function()
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", self.main, "TOPLEFT", col * step, 8 + up)
                b:SetSize(s.size, s.size)
            end)
        end
        local pb = _G["PetActionButton" .. i]
        if pb then
            skin(pb, 8, 1.5)
            Bars:SkinPetButton(pb, i)
            safe(function()
                pb:ClearAllPoints()
                if gap then
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
        end
    end
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

-- ── Move the main bar with /mui unlock | lock | reset ─────────────────────
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
