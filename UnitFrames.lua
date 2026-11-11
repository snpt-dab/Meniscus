local _, ns = ...
local T = ns.Theme

local UF = ns:NewModule("UnitFrames", {
    enabled = true,
    hideBlizzard = false,
    player = { x = -180, y = -180 },
    -- "frame": the usual player frame (avatar + health / power pills).
    -- "orb": just the avatar, pinned to the 10 o'clock edge of the health
    -- orb; the orbs already show health and power (/mui orbportrait).
    -- "none": no player frame and no portrait; your level is set into the
    -- health orb's value pill and the resting z's rise from the orb's rim
    -- (/mui noportrait).
    -- ("rest", a portrait inside the orb, was tried and dropped; a saved
    -- "rest" is turned into "none".)
    playerStyle = "frame",
    target = { x = 180, y = -180 },
    focus  = { x = 196, y = -96 },
    -- attach = true stacks party frames directly above the player frame;
    -- false lets them float at x/y (drag with /mui unlock).
    party  = { attach = true, x = -420, y = 0 },
    boss   = { x = 560, y = 140 },
    -- 3D pop-out avatar camera; tune live with /mui portrait <key> <value>
    -- fidget = 0 keeps the plain breathing idle (no yawns/stretches that hit
    -- the model window's edges); 1 allows Blizzard's random idle fidgets.
    portrait = { zoom = 1.0, dist = 1.0, z = 0, facing = 0, pop = 0.25, fidget = 0 },
})

local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local MEDIA = "Interface/AddOns/MinimalUI/Media/"

-- Pill sizes must keep the generated aspect ratios: health 8:1, power 32:1.
local SIZES = {
    large = { W = 224, H = 28, PH = 7, GAP = 4, D = 46, font = 12 }, -- player, target
    small = { W = 192, H = 24, PH = 6, GAP = 3, D = 40, font = 11 }, -- focus
    party = { W = 192, H = 24, PH = 6, GAP = 3, D = 30, font = 11 }, -- party1-4
    tiny  = { W = 128, H = 16, PH = 4, GAP = 2, D = 22, font = 10 }, -- target-of-target, pet
}
local BOSS_SPACING = 14
local SMALL_FRAME_GAP = 8 -- below a large frame (its cast bar moves under the small one)
ns.SMALL_FRAME_GAP = SMALL_FRAME_GAP
local PARTY_SPACING = 10
local PARTY_ATTACH_GAP = 28 -- clears the player avatar's popped-out head

local DEFAULT_POS = {
    player = { x = -180, y = -180 },
    target = { x = 180, y = -180 },
    focus  = { x = 196, y = -96 },
    party  = { x = -420, y = 0 },
    boss   = { x = 560, y = 140 },
}

-- ── Colors and text ───────────────────────────────────────────────────────
local function classColor(unit)
    if UnitIsPlayer(unit) then
        local ok, _, token = pcall(UnitClass, unit)
        if ok and token and not issecretvalue(token) then
            local c = RAID_CLASS_COLORS[token]
            if c then return c.r, c.g, c.b end
        end
    end
    local reaction = UnitReaction(unit, "player")
    if reaction and not issecretvalue(reaction) then
        if reaction <= 2 then return 0.80, 0.27, 0.27 end -- hostile
        if reaction == 3 or reaction == 4 then return 0.90, 0.75, 0.30 end -- unfriendly/neutral
        return 0.35, 0.75, 0.45 -- friendly
    end
    return unpack(T.accent)
end

-- Muted power colors that sit well on a flat dark UI.
local POWER = {
    [0] = { 0.30, 0.52, 0.90 }, -- mana
    [1] = { 0.85, 0.30, 0.30 }, -- rage
    [2] = { 0.90, 0.60, 0.25 }, -- focus
    [3] = { 0.90, 0.85, 0.35 }, -- energy
}

local function abbrev(n)
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(math.floor(n))
end

-- Health text that survives secret values. Returns which path produced the text.
local function setHealthText(self, unit)
    local fs = self.hpText
    local hp = UnitHealth(unit)
    if not issecretvalue(hp) then
        fs:SetText(abbrev(hp))
        return "plain"
    end
    if AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, hp)
        if ok and s ~= nil then fs:SetText(s) return "abbreviate" end
    end
    if UnitHealthPercent then
        local scale = CurveConstants and CurveConstants.ScaleTo100
        local ok = pcall(function()
            fs:SetFormattedText("%d%%", UnitHealthPercent(unit, true, scale))
        end)
        if ok then return "percent" end
    end
    fs:SetText("")
    return "none"
end

-- Level in the badge, colored by difficulty relative to you (gray..red).
-- Unknown level (-1, e.g. raid bosses) shows "??" in red.
local function setLevel(badge, unit)
    local lvl = UnitLevel(unit)
    if lvl == nil or issecretvalue(lvl) then
        badge.text:SetText("")
        return
    end
    if lvl < 0 then
        badge.text:SetText("??")
        badge.text:SetTextColor(0.95, 0.30, 0.30)
        return
    end
    badge.text:SetText(lvl)
    local attackable = UnitCanAttack("player", unit)
    if issecretvalue(attackable) then attackable = false end
    local c = attackable and GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl)
    if type(c) == "table" and c.r then
        badge.text:SetTextColor(c.r, c.g, c.b)
    else
        badge.text:SetTextColor(unpack(T.text))
    end
end

local newMask -- (defined with the avatar code below; used by the power orb here)

-- ── Elite / rare / boss ───────────────────────────────────────────────────
-- Shown on the portrait's ring (and the health pill's hairline):
--   elite       warm gold ring
--   rare        cool silver-blue ring
--   rare elite  gold ring, silver hairline on the bar
--   boss        the ring turns molten: slow streaks of ember and gold moving
--               around it, and the portrait grows by a fifth. No glow
--               outside the ring.
-- (Boss = a world boss, or anything whose level is hidden: the skull.)
local GOLD, SILVER, EMBER = { 0.90, 0.72, 0.30 }, { 0.70, 0.78, 0.92 }, { 0.80, 0.22, 0.14 }
local SWIRL_TEX = "Interface/AddOns/MinimalUI/Media/swirl.tga"

local function classOf(unit)
    local c = UnitClassification and UnitClassification(unit)
    if type(c) ~= "string" or issecretvalue(c) then c = "normal" end
    local lvl = UnitLevel(unit)
    local skull = type(lvl) == "number" and not issecretvalue(lvl) and lvl < 0
    local player = UnitIsPlayer(unit)
    if issecretvalue(player) then player = false end
    if c == "worldboss" or (skull and not player) then return "boss" end
    if c == "rareelite" then return "rareelite" end
    if c == "elite" then return "elite" end
    if c == "rare" then return "rare" end
    return "normal"
end

local function moltenRing(av)
    if av.molten or not av.lip then return av.molten end
    local lip = av.lip
    local fx = lip:CreateTexture(nil, "ARTWORK", nil, 3)
    fx:SetAllPoints()
    fx:SetTexture(SWIRL_TEX, "REPEAT", "REPEAT")
    fx:SetVertexColor(1.0, 0.78, 0.32, 1)
    -- Only where the ring is: the ring's own texture is the mask.
    local mask = lip:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "lip_ring.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    fx:AddMaskTexture(mask)
    fx:Hide()
    local driver = CreateFrame("Frame", nil, lip)
    driver:Hide()
    local ph = 0
    driver:SetScript("OnUpdate", function(_, dt)
        ph = ph + dt
        local u, v = ph * 0.11, ph * 0.07
        fx:SetTexCoord(u, u + 0.9, v, v + 0.9)
        -- A slow breath between ember and gold underneath the streaks.
        local k = 0.5 + 0.5 * math.sin(ph * 1.6)
        av.lipRing:SetVertexColor(EMBER[1] + (GOLD[1] - EMBER[1]) * k, EMBER[2] + (GOLD[2] - EMBER[2]) * k,
                                  EMBER[3] + (GOLD[3] - EMBER[3]) * k, 1)
    end)
    av.molten, av.moltenDriver = fx, driver
    return fx
end

local function styleClass(self, unit)
    local av = self.avatar
    if not av then return end
    local kind = classOf(unit)
    if self.__kind == kind then return end
    self.__kind = kind
    local c = T.border
    if kind == "elite" or kind == "rareelite" then c = GOLD
    elseif kind == "rare" then c = SILVER
    elseif kind == "boss" then c = EMBER end
    if av.ring then av.ring:SetColorTexture(c[1], c[2], c[3], 1) end
    if av.lipRing then av.lipRing:SetVertexColor(c[1], c[2], c[3], 1) end
    local bar = (kind == "rareelite") and SILVER or c
    if self.healthPill and self.healthPill.SetRingColor then self.healthPill:SetRingColor(bar[1], bar[2], bar[3], 1) end
    local boss = kind == "boss"
    if boss or av.molten then
        local fx = moltenRing(av)
        if fx then
            fx:SetShown(boss)
            av.moltenDriver:SetShown(boss)
        end
    end
    -- The portrait's size is a protected matter only for its parent; the
    -- avatar itself is an ordinary frame, so this is fine in combat.
    av.kindScale = boss and 1.2 or 1
    av:SetScale((av.baseScale or 1) * av.kindScale)
end

-- ── Player targets: a power orb instead of the power pill ─────────────────
-- For a player (not an NPC) the thin power pill is replaced by a small orb
-- to the left of the health pill, as tall as the pill and with the same
-- curve as its cap. An ordinary frame, so it can come and go in combat.
local ORB_GLARE = "Interface/AddOns/MinimalUI/Media/orb_glare.tga"
local function powerOrb(self)
    if self.pOrb then return self.pOrb end
    local hp = self.healthPill
    local d = hp:GetHeight()
    local o = CreateFrame("Frame", nil, self)
    o:SetSize(d, d)
    o:SetPoint("RIGHT", hp, "LEFT", -4, 0)
    local ring = o:CreateTexture(nil, "BACKGROUND", nil, 0)
    ring:SetAllPoints()
    ring:SetColorTexture(unpack(T.border))
    ring:AddMaskTexture(newMask(o, d))
    local inner = d - 5
    local imask = newMask(o, inner)
    local bg = o:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("CENTER"); bg:SetSize(inner, inner)
    bg:SetColorTexture(0.04, 0.045, 0.05, 1)
    bg:AddMaskTexture(imask)
    o.bar = CreateFrame("StatusBar", nil, o)
    o.bar:SetPoint("CENTER"); o.bar:SetSize(inner, inner)
    o.bar:SetOrientation("VERTICAL")
    o.bar:SetStatusBarTexture(T.bar)
    o.bar:GetStatusBarTexture():AddMaskTexture(imask)
    local gloss = o.bar:CreateTexture(nil, "OVERLAY", nil, 3)
    gloss:SetAllPoints(o.bar)
    gloss:SetTexture(ORB_GLARE)
    gloss:AddMaskTexture(imask)
    self.pOrb = o
    return o
end

local function update(self)
    local unit = self.unit
    if not UnitExists(unit) then return end
    -- Health values may be secret: hand them straight to the StatusBar.
    self.health:SetMinMaxValues(0, UnitHealthMax(unit))
    self.health:SetValue(UnitHealth(unit))
    local r, g, b = classColor(unit)
    self.health:SetStatusBarColor(r, g, b)
    local av = self.avatar
    if av then
        av.tint:SetColorTexture(r, g, b, 0.22)
        if av.lipFill then
            -- Lip matches the tinted circle so it reads as one surface.
            av.lipFill:SetVertexColor(0.05 + (r - 0.05) * 0.22, 0.05 + (g - 0.05) * 0.22,
                                      0.06 + (b - 0.06) * 0.22, 1)
            av.lipRim:SetVertexColor(r, g, b, 0.55)
        end
    end

    -- Names: always dark (user preference). Health value: adaptive contrast,
    -- dark on light fills (e.g. priest white), light otherwise.
    self.name:SetTextColor(0.07, 0.07, 0.08, 1)
    self.name:SetShadowColor(1, 1, 1, 0.25)
    -- The value splits at the fill edge: light over the empty track always;
    -- over the fill, dark on light fills (e.g. priest white), light otherwise.
    local light = (0.299 * r + 0.587 * g + 0.114 * b) > 0.68
    self.hpText:SetTextColor(unpack(T.text))
    self.hpText:SetShadowColor(0, 0, 0, 0.8)
    local over = self.hpText.dark
    if over then
        if light then
            over:SetTextColor(0.07, 0.07, 0.08, 1)
            over:SetShadowColor(1, 1, 1, 0.25)
        else
            over:SetTextColor(unpack(T.text))
            over:SetShadowColor(0, 0, 0, 0.8)
        end
    end
    self.name:SetText(UnitName(unit))
    if self.levelBadge then setLevel(self.levelBadge, unit) end
    self.hpPath = setHealthText(self, unit)
    local ptype = UnitPowerType(unit)
    local pmax, pcur = UnitPowerMax(unit, ptype), UnitPower(unit, ptype)
    self.power:SetMinMaxValues(0, pmax)
    self.power:SetValue(pcur)
    local c = POWER[ptype]
    if not c and PowerBarColor and PowerBarColor[ptype] then
        local i = PowerBarColor[ptype]
        c = { i.r, i.g, i.b }
    end
    if c then self.power:SetStatusBarColor(c[1], c[2], c[3]) end

    if self.key == "target" then
        pcall(styleClass, self, unit)
        local isPlayer = UnitIsPlayer(unit)
        if issecretvalue(isPlayer) then isPlayer = false end
        if isPlayer then
            local o = powerOrb(self)
            o.bar:SetMinMaxValues(0, pmax)
            o.bar:SetValue(pcur)
            if c then o.bar:SetStatusBarColor(c[1], c[2], c[3]) end
            o:Show()
        elseif self.pOrb then
            self.pOrb:Hide()
        end
        self.powerPill:SetShown(not isPlayer)
    end
end

-- ── Avatars ───────────────────────────────────────────────────────────────
-- "3d": pop-out PlayerModel. Models can't be masked, but their background is
-- transparent. So: a dark tinted circle behind, and a model window narrower
-- than the circle whose bottom corners sit exactly on the circle edge (chord
-- at 0.3D below center, where the chord width is 0.8D). A crescent "lip"
-- (Looney Tunes hole rim) covers the window's straight edges; the head rises
-- out of the top of the circle.
-- "flat": the 2D portrait masked to the circle (cheap; used for party).
function newMask(owner, size)
    local m = owner:CreateMaskTexture()
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetPoint("CENTER", owner, "CENTER")
    m:SetSize(size, size)
    return m
end

function UF:CreateAvatar(f, unit, side, d, mode)
    local av = CreateFrame("Frame", nil, f)
    av.D, av.unit = d, unit
    av:SetSize(d, d)
    av:SetPoint("CENTER", f.healthPill, side, 0, -2)
    av:SetFrameLevel(f:GetFrameLevel() + 6)

    local ring = av:CreateTexture(nil, "BACKGROUND", nil, 0)
    ring:SetAllPoints()
    ring:SetColorTexture(unpack(T.border))
    ring:AddMaskTexture(newMask(av, d))
    av.ring = ring

    local innerMask = newMask(av, d - 4)
    av.bg = av:CreateTexture(nil, "BACKGROUND", nil, 1)
    av.bg:SetPoint("CENTER")
    av.bg:SetSize(d - 4, d - 4)
    av.bg:SetColorTexture(0.05, 0.05, 0.06, 1)
    av.bg:AddMaskTexture(innerMask)

    -- Class/reaction tint, faint, so each avatar reads as "theirs".
    av.tint = av:CreateTexture(nil, "BACKGROUND", nil, 2)
    av.tint:SetAllPoints(av.bg)
    av.tint:SetColorTexture(1, 1, 1, 1)
    av.tint:AddMaskTexture(innerMask)

    -- 2D portrait (flat mode, or 3D fallback when out of range), masked to the circle.
    av.flat = av:CreateTexture(nil, "ARTWORK")
    av.flat:SetAllPoints(av.bg)
    av.flat:AddMaskTexture(innerMask)
    av.flat:Hide()

    if mode ~= "3d" then return av end

    local m = CreateFrame("PlayerModel", nil, av)
    m:SetFrameLevel(av:GetFrameLevel() + 1)
    -- Re-pin the base stand animation whenever a cycle ends, so random
    -- idle variations (yawn, stretch) never start.
    m:SetScript("OnAnimFinished", function(self)
        if UF.db.portrait.fidget == 0 then pcall(self.SetAnimation, self, 0, 0) end
    end)
    av.model = m

    local lip = CreateFrame("Frame", nil, av)
    av.lip = lip
    lip:SetAllPoints(av)
    lip:SetFrameLevel(m:GetFrameLevel() + 1)
    local function layer(file, sub)
        local t = lip:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetAllPoints()
        t:SetTexture(MEDIA .. file)
        return t
    end
    av.lipFill = layer("lip_fill.tga", 0)
    av.lipFill:SetVertexColor(0.05, 0.05, 0.06, 1)
    av.lipRim = layer("lip_rim.tga", 1)
    av.lipRim:SetVertexColor(1, 1, 1, 0.35)
    av.lipRing = layer("lip_ring.tga", 2)
    av.lipRing:SetVertexColor(unpack(T.border))

    self:LayoutAvatar(av)
    return av
end

function UF:LayoutAvatar(av)
    local m = av.model
    if not m then return end
    local p = self.db and self.db.portrait or { pop = 0.25 }
    local d = av.D
    m:ClearAllPoints()
    m:SetSize(0.8 * d, (0.8 + p.pop) * d)
    m:SetPoint("BOTTOM", av, "CENTER", 0, -0.3 * d)
end

local function visible(unit)
    local v = UnitIsVisible(unit)
    if issecretvalue(v) then return true end
    return v
end

function UF:RefreshAvatar(av)
    local unit = av.unit
    if not UnitExists(unit) then return end
    local m = av.model
    if m and visible(unit) then
        local p = self.db.portrait
        av.flat:Hide()
        m:Show()
        m:ClearModel()
        m:SetUnit(unit)
        pcall(m.SetPortraitZoom, m, p.zoom)
        pcall(m.SetCamDistanceScale, m, p.dist)
        -- x nudges the model sideways (negative = left) so the face sits
        -- centered in the circle, clear of the model window's straight edges.
        -- (-0.03 was the first, wrong-way guess: positive y moves the model left.)
        if p.x == nil or p.x == -0.03 then p.x = 0.04 end
        pcall(m.SetPosition, m, 0, p.x, p.z)
        pcall(m.SetFacing, m, p.facing)
        if p.fidget == 0 then pcall(m.SetAnimation, m, 0, 0) end
    else
        if m then m:Hide() end
        SetPortraitTexture(av.flat, unit)
        av.flat:Show()
    end
end

-- ── Frame builder ─────────────────────────────────────────────────────────
-- cfg = { size = "large"|"small"|"party", avatar = "3d"|"flat",
--         side = "LEFT"|"RIGHT", watch = bool, events = { extra events } }
local function create(unit, label, cfg)
    local s = SIZES[cfg.size]
    local f = CreateFrame("Button", "MinimalUI_" .. label, UIParent, "SecureUnitButtonTemplate")
    f.unit, f.realUnit, f.key = unit, unit, label:lower()
    f:SetSize(s.W, s.H + s.GAP + s.PH)
    f:SetAttribute("unit", unit)
    -- "*" = any modifier combination. Plain "type1" only matches with no
    -- modifiers held, so Click Casting's remapped target click (e.g.
    -- shift-ctrl-left) found no action.
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    -- Modern secure buttons act on the mouse press; "AnyUp"-only clicks arrive
    -- but never target. Register both so either client behavior works.
    f:RegisterForClicks("AnyDown", "AnyUp")

    -- Two stacked pills: health (name + value inside) and a slim power pill.
    local hp = ns:CreatePillBar(f, s.W, s.H)
    hp:SetPoint("TOP", f, "TOP")
    f.healthPill, f.health = hp, hp.bar

    local pw = ns:CreatePillBar(f, s.W, s.PH)
    pw:SetPoint("BOTTOM", f, "BOTTOM")
    f.powerPill, f.power = pw, pw.bar

    -- Text inset past the rounded caps (radius = H/2) and the avatar.
    f.name = hp:CreateText(s.font)
    ns:SetFont(f.name, s.font, "", true) -- names in the heavier weight
    f.hpText = hp:CreateText(s.font, nil, true) -- splits at the fill edge
    f.name:SetJustifyH("LEFT")
    -- One line, cut with "…": long names on small pills used to wrap into
    -- two lines spilling over the bar (Forever names have surnames).
    f.name:SetWordWrap(false)
    pcall(f.name.SetNonSpaceWrap, f.name, false)
    pcall(f.name.SetMaxLines, f.name, 1)
    local avatarInset = s.D / 2 + 6
    if cfg.side == "LEFT" then
        f.name:SetPoint("LEFT", hp, "LEFT", avatarInset, 0)
        f.hpText:SetPoint("RIGHT", hp, "RIGHT", -s.H / 2, 0)
    else
        f.name:SetPoint("LEFT", hp, "LEFT", s.H / 2, 0)
        f.hpText:SetPoint("RIGHT", hp, "RIGHT", -avatarInset, 0)
    end
    f.name:SetPoint("RIGHT", f.hpText, "LEFT", -6, 0)

    f.avatar = UF:CreateAvatar(f, unit, cfg.side, s.D, cfg.avatar)

    -- Level badge: a small circle hanging off the bottom of the avatar
    -- (skipped on tiny frames, where it would be unreadable).
    if s.D >= 30 then
        local d = math.floor(s.D * 0.42 + 0.5)
        local badge = CreateFrame("Frame", nil, f.avatar)
        badge:SetSize(d, d)
        badge:SetPoint("CENTER", f.avatar, "BOTTOM", 0, 1)
        badge:SetFrameLevel(f.avatar:GetFrameLevel() + 5) -- above the model and lip
        local ring = badge:CreateTexture(nil, "BACKGROUND", nil, 0)
        ring:SetAllPoints()
        ring:SetColorTexture(unpack(T.border))
        ring:AddMaskTexture(newMask(badge, d))
        local fillMask = newMask(badge, d - 3)
        local fill = badge:CreateTexture(nil, "BACKGROUND", nil, 1)
        fill:SetPoint("CENTER")
        fill:SetSize(d - 3, d - 3)
        fill:SetColorTexture(0.17, 0.17, 0.19, 1) -- dark gray (lifts it off the black lip)
        fill:AddMaskTexture(fillMask)
        badge.text = badge:CreateFontString(nil, "OVERLAY")
        ns:SetFont(badge.text, math.max(8, math.floor(d * 0.52)), "")
        badge.text:SetPoint("CENTER", 0, 0)
        badge.text:SetShadowOffset(1, -1)
        badge.text:SetShadowColor(0, 0, 0, 0.9)
        f.levelBadge = badge
    end

    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function() update(f) end)
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
                         "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL" }) do
        ev:RegisterUnitEvent(e, unit)
    end
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Avatar refreshes only when the model/portrait actually changes (SetUnit is costly).
    local pev = CreateFrame("Frame")
    pev:SetScript("OnEvent", function() UF:RefreshAvatar(f.avatar) end)
    for _, e in ipairs({ "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_CONNECTION" }) do
        pev:RegisterUnitEvent(e, unit)
    end
    pev:RegisterEvent("PLAYER_ENTERING_WORLD")

    for _, e in ipairs(cfg.events or {}) do
        ev:RegisterEvent(e)
        pev:RegisterEvent(e)
    end
    f.ev, f.pev = ev, pev

    -- Units without their own events (targettarget) are polled.
    if cfg.poll then
        C_Timer.NewTicker(0.25, function()
            if not f:IsVisible() then return end
            update(f)
            local g = UnitGUID(f.unit)
            if g ~= nil and issecretvalue(g) then return end
            if g ~= f.__guid then
                f.__guid = g
                UF:RefreshAvatar(f.avatar)
            end
        end)
    end

    f.watch = cfg.watch
    if cfg.watch then RegisterUnitWatch(f) end
    table.insert(UF.frames, f)
    return f
end

local function place(frame, pos)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
end

-- ── Player on the health orb ──────────────────────────────────────────────
-- playerStyle "orb": the player frame shrinks to its avatar and sits on the
-- health orb's rim at 10 o'clock; the pills (and with them name and health
-- text) are hidden. Everything that hangs off the player frame follows it:
-- the pet frame moves to the avatar's left, the cast bar goes above the orb
-- (CastBars.lua asks UF.orbStyleOn), attached party frames stack above.
-- Falls back to the normal frame while the orbs are hidden.
local ORB_ANGLE = math.rad(150) -- 10 o'clock
function UF:ApplyPlayerStyle()
    local f = self.player
    if not f then return end
    if InCombatLockdown() then self.stylePending = true return end
    self.stylePending = false
    local O = ns.modules.Orbs
    local orb = O and O.health
    if self.db.playerStyle == "rest" then self.db.playerStyle = "none" end
    local style = self.db.playerStyle
    local on = (style == "orb" or style == "none") and orb and orb:IsShown() and true or false
    local bare = on and style == "none"
    -- "none": no pills. With the console's character panel (Bars.charSlot)
    -- the portrait lives there, larger; without it the frame is only an
    -- invisible anchor for what hangs off it.
    local BR = ns.modules.Bars
    local char = bare and BR and BR.charSlot or nil
    f.avatar:SetShown((not bare) or char ~= nil)
    f:EnableMouse((not bare) or char ~= nil)
    if O and O.SetRestPortrait then O:SetRestPortrait(false) end
    local s = SIZES.large
    local av = f.avatar
    self.orbStyleOn = on
    self.playerBaseLevel = self.playerBaseLevel or f:GetFrameLevel()
    f.healthPill:SetShown(not on)
    f.powerPill:SetShown(not on)
    f:ClearAllPoints()
    av:ClearAllPoints()
    av:SetScale(1)
    if char then
        -- The frame is the portrait's click area; the avatar itself is
        -- scaled up to the panel's portrait size.
        f:SetSize(char.avD, char.avD)
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", char.avX, char.avY)
        av:SetScale(char.avD / av.D)
        av:SetPoint("CENTER", f, "CENTER")
        f:SetFrameStrata("LOW")
        f:SetFrameLevel(5)
    elseif on then
        local R = orb:GetWidth() / 2
        f:SetSize(av.D, av.D)
        f:SetPoint("CENTER", orb, "CENTER", math.cos(ORB_ANGLE) * R, math.sin(ORB_ANGLE) * R)
        av:SetPoint("CENTER", f, "CENTER")
        -- Above the orb and everything drawn on it.
        f:SetFrameStrata(orb:GetFrameStrata())
        f:SetFrameLevel(orb:GetFrameLevel() + 40)
    else
        f:SetSize(s.W, s.H + s.GAP + s.PH)
        place(f, self.db.player)
        av:SetPoint("CENTER", f.healthPill, "LEFT", 0, -2)
        f:SetFrameLevel(self.playerBaseLevel)
    end
    -- Keep the avatar's layers in order whatever the frame level did.
    local base = f:GetFrameLevel()
    av:SetFrameLevel(base + 6)
    if av.model then av.model:SetFrameLevel(base + 7) end
    if av.lip then av.lip:SetFrameLevel(base + 8) end
    -- Level badge and resting z's: on the avatar normally. With no portrait
    -- the level goes into the health orb's value pill (Orbs:SetChipLevel)
    -- and the z's rise from the orb's rim at 10 o'clock.
    local badge, zs = f.levelBadge, self.rest
    if badge then
        badge:SetParent(av)
        badge:SetScale(1)
        badge:ClearAllPoints()
        badge:SetPoint("CENTER", av, "BOTTOM", 0, 1)
        badge:SetFrameLevel(base + 11)
        -- In the character panel the level is on the panel's pill.
        badge:SetShown(not char)
    end
    -- (With the character panel the level is on its pill instead.)
    if O and O.SetChipLevel then O:SetChipLevel(bare and not char) end
    if zs then
        zs:SetParent((bare and not char) and f or av)
        zs:ClearAllPoints()
        if bare and not char then
            local R = orb:GetWidth() / 2
            zs:SetPoint("BOTTOMLEFT", orb, "CENTER", math.cos(ORB_ANGLE) * R - 8, math.sin(ORB_ANGLE) * R - 4)
        else
            zs:SetPoint("BOTTOMLEFT", av, "TOPRIGHT", -10, -8)
        end
        zs:SetFrameLevel(base + 14)
    end
    if char then pcall(self.RefreshAvatar, self, av) end
    if self.pet then
        -- Pet orbs (Orbs.lua) replace the pet's frame while they are on.
        local petOrbs = O and O.petOrbsOn
        if petOrbs and not self.petHidden then
            self.petHidden = true
            UnregisterUnitWatch(self.pet)
            self.pet:Hide()
        elseif not petOrbs and self.petHidden then
            self.petHidden = false
            RegisterUnitWatch(self.pet)
        end
        self.pet:ClearAllPoints()
        local B = ns.modules.Bars
        local slot = B and B.petSlot
        if slot and slot.orbs then
            self.pet:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", slot.x, slot.top + 28)
        elseif slot then
            -- Console layout: over the pet's action bar in the plate's
            -- pet slot (Bars.lua), centered on it.
            local pw = self.pet:GetWidth()
            self.pet:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", slot.x + (slot.w - pw) / 2 + 6, slot.top)
        elseif on then
            self.pet:SetPoint("RIGHT", f, "LEFT", -10, 0)
        else
            self.pet:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -SMALL_FRAME_GAP)
        end
    end
    local CB = ns.modules.CastBars
    if CB and CB.player and CB.player.place then CB.player.place() end
    if self.partyAnchor then self:LayoutParty() end
    self:PlaceTarget()
    local AU = ns.modules.Auras
    if AU and AU.SeatBlizzard and AU.db then AU:SeatBlizzard() end
end

-- Console layout (minimap dome + character panel): the target stands over
-- the map, where your eyes are in a fight, 15% larger and turned upside
-- down so its portrait can hang under the bar:
--     target's cast bar
--     power pill          (thin, now on top)
--     health pill         (name / value)
--        ( portrait )     centered under the bar, overlapping its bottom edge
--     -- your cast bar -- straddling the dome's top edge
--        (  the map  )
-- The portrait sits directly above the map dome, circle over circle. The
-- target's buffs / debuffs go beside the portrait, under the bar (Auras.lua).
-- Its target is a small pill to the right for now.
-- Otherwise the target is wherever you put it, in its normal shape.
local STRIP_SCALE, STRIP_OVERLAP = 1.15, 10
function UF:PlaceTarget()
    local t, tot = self.target, self.tot
    if not t or InCombatLockdown() then return end
    local dome = _G.MinimalUI_MinimapDome
    local B = ns.modules.Bars
    local strip = dome and B and B.charSlot and true or false
    self.targetStrip = strip
    local s = SIZES.large
    local hp, pw, av = t.healthPill, t.powerPill, t.avatar
    t:ClearAllPoints()
    hp:ClearAllPoints(); pw:ClearAllPoints(); av:ClearAllPoints()
    t.name:ClearAllPoints(); t.hpText:ClearAllPoints()
    -- In the strip the health pill fills from its right end (see SetReverse).
    if hp.SetReverse then hp:SetReverse(strip) end
    if strip then
        t:SetScale(STRIP_SCALE)
        hp:SetPoint("BOTTOM", t, "BOTTOM")
        pw:SetPoint("TOP", t, "TOP")
        av:SetPoint("TOP", hp, "BOTTOM", 0, STRIP_OVERLAP)
        -- No avatar on the bar's end any more: both texts use the caps' inset.
        t.name:SetPoint("LEFT", hp, "LEFT", s.H / 2, 0)
        t.hpText:SetPoint("RIGHT", hp, "RIGHT", -s.H / 2, 0)
        -- Above the dome: your cast bar's upper half (7), a gap (4), then the
        -- portrait, whose top is STRIP_OVERLAP inside the bar. Offsets are in
        -- the frame's own (scaled) units.
        local up = 7 + 4 + (av.D - STRIP_OVERLAP) * STRIP_SCALE
        t:SetPoint("BOTTOM", dome, "TOP", 0, up / STRIP_SCALE)
    else
        t:SetScale(1)
        hp:SetPoint("TOP", t, "TOP")
        pw:SetPoint("BOTTOM", t, "BOTTOM")
        av:SetPoint("CENTER", hp, "RIGHT", 0, -2)
        local avatarInset = s.D / 2 + 6
        t.name:SetPoint("LEFT", hp, "LEFT", s.H / 2, 0)
        t.hpText:SetPoint("RIGHT", hp, "RIGHT", -avatarInset, 0)
        place(t, self.db.target)
    end
    t.name:SetPoint("RIGHT", t.hpText, "LEFT", -6, 0)
    if tot then
        tot:ClearAllPoints()
        if strip then
            tot:SetPoint("LEFT", t, "RIGHT", 12, 0)
        else
            tot:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -SMALL_FRAME_GAP)
        end
    end
    local CB = ns.modules.CastBars
    if CB and CB.target and CB.target.place then CB.target.place() end
    if CB and CB.player and CB.player.place then CB.player.place() end
    local AU = ns.modules.Auras
    if AU and AU.PlaceTargetRow then pcall(AU.PlaceTargetRow, AU, strip) end
end

local STYLE_NAMES = { frame = "normal frame", orb = "on the health orb's edge", none = "none (level in the health orb's pill)" }
function UF:SetPlayerStyle(style)
    if InCombatLockdown() then return ns:Print("Can't change the player frame in combat.") end
    self.db.playerStyle = STYLE_NAMES[style] and style or "frame"
    self:ApplyPlayerStyle()
    if self.db.playerStyle ~= "frame" and not self.orbStyleOn then
        ns:Print("That player style needs the orbs, which are hidden (/mui orbs).")
    else
        ns:Print("Player portrait:", STYLE_NAMES[self.db.playerStyle])
    end
end
ns.commands.orbportrait = function() UF:SetPlayerStyle(UF.db.playerStyle == "orb" and "frame" or "orb") end
ns.commands.noportrait = function() UF:SetPlayerStyle(UF.db.playerStyle == "none" and "frame" or "none") end

-- ── Party ─────────────────────────────────────────────────────────────────
function UF:LayoutParty()
    if InCombatLockdown() then self.partyPending = true return end
    self.partyPending = false
    local s = SIZES.party
    local rowH = s.H + s.GAP + s.PH
    local a = self.partyAnchor
    a:SetSize(s.W, 4 * rowH + 3 * PARTY_SPACING)
    a:ClearAllPoints()
    if self.db.party.attach then
        -- Pill left edges line up with the player's, so avatars form a column.
        a:SetPoint("BOTTOMLEFT", self.player, "TOPLEFT", 0, PARTY_ATTACH_GAP)
    else
        place(a, self.db.party)
    end
    -- party1 sits closest to the player; the stack grows upward.
    for i, f in ipairs(self.party) do
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, (i - 1) * (rowH + PARTY_SPACING))
    end
end

-- Resting indicator: three z's drifting up from the player's avatar,
-- staggered, each fading in and out (shown in inns/cities).
function UF:CreateRestIndicator()
    local av = self.player.avatar
    local holder = CreateFrame("Frame", nil, av)
    holder:SetSize(30, 30)
    holder:SetPoint("BOTTOMLEFT", av, "TOPRIGHT", -10, -8)
    holder:SetFrameLevel(av:GetFrameLevel() + 8)
    for i, spec in ipairs({ { 9, 0, 0 }, { 11, 7, 6 }, { 14, 14, 13 } }) do
        local z = holder:CreateFontString(nil, "OVERLAY")
        ns:SetFont(z, spec[1], "", true)
        z:SetText("z")
        z:SetTextColor(0.80, 0.86, 1.0)
        z:SetShadowOffset(1, -1)
        z:SetShadowColor(0, 0, 0, 0.9)
        z:SetPoint("BOTTOMLEFT", spec[2], spec[3])
        z:SetAlpha(0)
        local ag = z:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local wait = ag:CreateAnimation("Alpha") -- stagger
        wait:SetFromAlpha(0); wait:SetToAlpha(0); wait:SetDuration((i - 1) * 0.45 + 0.01); wait:SetOrder(1)
        local fin = ag:CreateAnimation("Alpha")
        fin:SetFromAlpha(0); fin:SetToAlpha(1); fin:SetDuration(0.5); fin:SetOrder(2)
        local rise = ag:CreateAnimation("Translation")
        rise:SetOffset(3, 6); rise:SetDuration(1.4); rise:SetOrder(2); rise:SetSmoothing("OUT")
        local fout = ag:CreateAnimation("Alpha")
        fout:SetFromAlpha(1); fout:SetToAlpha(0); fout:SetDuration(0.9)
        fout:SetStartDelay(0.5); fout:SetOrder(2)
        local rest = ag:CreateAnimation("Alpha") -- pause before the next cycle
        rest:SetFromAlpha(0); rest:SetToAlpha(0); rest:SetDuration((3 - i) * 0.45 + 0.4); rest:SetOrder(3)
        holder[i] = ag
    end
    local function refresh()
        local resting = IsResting()
        if issecretvalue(resting) then resting = false end
        holder:SetShown(resting and true or false)
        for i = 1, 3 do
            if resting then holder[i]:Play() else holder[i]:Stop() end
        end
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_UPDATE_RESTING")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", refresh)
    refresh()
    self.rest = holder
end

-- Boss stack: boss1 on top, growing downward from the anchor's top.
function UF:LayoutBoss()
    if InCombatLockdown() then return end
    local s = SIZES.small
    local rowH = s.H + s.GAP + s.PH
    local a = self.bossAnchor
    a:SetSize(s.W, 5 * rowH + 4 * BOSS_SPACING)
    place(a, self.db.boss)
    for i, f in ipairs(self.boss) do
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -(i - 1) * (rowH + BOSS_SPACING))
    end
end

-- Test mode: show all four party frames using your own character as data.
function UF:SetPartyTest(on)
    if InCombatLockdown() then return ns:Print("Can't change party test mode in combat.") end
    self.partyTest = on
    for _, f in ipairs(self.party) do
        local u = on and "player" or f.realUnit
        f.unit, f.avatar.unit = u, u
        f:SetAttribute("unit", u)
        if on then UnregisterUnitWatch(f); f:Show() else RegisterUnitWatch(f) end
        update(f)
        self:RefreshAvatar(f.avatar)
    end
    local A = ns.modules.Auras
    if A and A.RefreshAll then A:RefreshAll() end
    ns:Print("Party test mode", on and "on" or "off")
end

-- ── Blizzard frames ───────────────────────────────────────────────────────
local hidden = CreateFrame("Frame")
hidden:Hide()

-- Disable a Blizzard frame the way established unit frame addons do: stop its
-- events (and its children's) first, so its code never runs against a frame
-- it no longer controls (that caused TargetFrame.lua errors), then hide it.
local function silence(fr, depth)
    pcall(fr.UnregisterAllEvents, fr)
    if depth > 0 then
        for _, child in ipairs({ fr:GetChildren() }) do silence(child, depth - 1) end
    end
end

function UF:ApplyBlizzard(hide)
    if InCombatLockdown() then return ns:Print("Can't change Blizzard frames in combat.") end
    if not hide then
        -- Their events are gone; only a reload brings them back cleanly.
        return ns:Print("Blizzard unit frames will return after /reload.")
    end
    for _, fr in ipairs({ PlayerFrame, TargetFrame, FocusFrame, PartyFrame, CompactPartyFrame,
                          PlayerCastingBarFrame, TargetFrameSpellBar, FocusFrameSpellBar,
                          PetFrame, _G.BossTargetFrameContainer }) do
        if fr and not fr.__muiDisabled then
            fr.__muiDisabled = true
            silence(fr, 3)
            if fr.SetUnit then pcall(fr.SetUnit, fr, nil) end -- cast bars
            fr:Hide()
            fr:SetParent(hidden)
        end
    end
end

-- ── Init ──────────────────────────────────────────────────────────────────
function UF:OnInit(db)
    self.db = db
    self.frames = {}

    self.player = create("player", "Player", { size = "large", avatar = "3d", side = "LEFT" })
    self.target = create("target", "Target", { size = "large", avatar = "3d", side = "RIGHT",
        watch = true, events = { "PLAYER_TARGET_CHANGED" } })
    self.focus = create("focus", "Focus", { size = "small", avatar = "3d", side = "RIGHT",
        watch = true, events = { "PLAYER_FOCUS_CHANGED" } })
    place(self.player, db.player)
    place(self.target, db.target)
    place(self.focus, db.focus)

    self.partyAnchor = CreateFrame("Frame", "MinimalUI_PartyAnchor", UIParent)
    self.party = {}
    for i = 1, 4 do
        self.party[i] = create("party" .. i, "Party" .. i, { size = "party", avatar = "3d",
            side = "LEFT", watch = true, events = { "GROUP_ROSTER_UPDATE" } })
    end
    self:LayoutParty()
    pcall(self.CreateRestIndicator, self)

    -- Target-of-target under the target frame, pet under the player frame
    -- (both tiny pills that follow their parent frame).
    self.tot = create("targettarget", "ToT", { size = "tiny", avatar = "flat", side = "RIGHT",
        watch = true, poll = true, events = { "PLAYER_TARGET_CHANGED" } })
    self.tot:SetPoint("TOPRIGHT", self.target, "BOTTOMRIGHT", 0, -SMALL_FRAME_GAP)
    self.pet = create("pet", "Pet", { size = "tiny", avatar = "flat", side = "LEFT",
        watch = true, events = { "UNIT_PET" } })
    self.pet:SetPoint("TOPLEFT", self.player, "BOTTOMLEFT", 0, -SMALL_FRAME_GAP)

    -- Boss frames: a movable stack of five, flat avatars.
    self.bossAnchor = CreateFrame("Frame", "MinimalUI_BossAnchor", UIParent)
    self.boss = {}
    for i = 1, 5 do
        self.boss[i] = create("boss" .. i, "Boss" .. i, { size = "small", avatar = "flat", side = "RIGHT",
            watch = true, events = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGETABLE_CHANGED" } })
    end
    self:LayoutBoss()

    ns:RegisterSnapTarget(self.bossAnchor)
    ns:RegisterSnapTarget(self.player)
    ns:RegisterSnapTarget(self.target)
    ns:RegisterSnapTarget(self.focus)
    ns:RegisterSnapTarget(self.partyAnchor, function() return not UF.db.party.attach end)

    for _, f in ipairs(self.frames) do update(f) end
    if db.hideBlizzard then self:ApplyBlizzard(true) end

    local regen = CreateFrame("Frame")
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    regen:SetScript("OnEvent", function() if UF.partyPending then UF:LayoutParty() end end)

    self:StartRangeFade()
end

-- ── Range fading ──────────────────────────────────────────────────────────
-- Group members out of range (or offline) fade to OUT_ALPHA. Alpha only, so
-- it's combat-safe on secure frames. Target/focus fade too when they're in
-- your group. Range may be a secret value on Forever: then the engine applies
-- it via SetAlphaFromBoolean without us reading it.
local OUT_ALPHA = 0.45

local function safeBool(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or issecretvalue(v) then return nil end
    return v
end

-- Non-group target: in range if ANY ranged ability on your action bars can
-- reach it (heals count for friendly targets, attacks for hostile ones).
-- Slots are cached and rebuilt when bars/spells change.
local rangeSlots
local IsActionInRangeFn = (C_ActionBar and C_ActionBar.IsActionInRange) or IsActionInRange
local function buildRangeSlots()
    rangeSlots = {}
    for slot = 1, 180 do
        local okH, has = pcall(HasAction, slot)
        if okH and has == true then
            local okR, ranged = pcall(ActionHasRange, slot)
            if okR and ranged == true then table.insert(rangeSlots, slot) end
        end
    end
end
local slotWatch = CreateFrame("Frame")
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
                     "UPDATE_BONUS_ACTIONBAR" }) do
    pcall(slotWatch.RegisterEvent, slotWatch, e)
end
slotWatch:SetScript("OnEvent", function() rangeSlots = nil end)

local function targetInActionRange()
    if not IsActionInRangeFn then return nil end
    if not rangeSlots then buildRangeSlots() end
    local anyOut = false
    for _, slot in ipairs(rangeSlots) do
        local ok, r = pcall(IsActionInRangeFn, slot)
        if ok and not issecretvalue(r) then
            if r == true then return true end
            if r == false then anyOut = true end
        end
    end
    if anyOut then return false end
    return nil -- no ability applies to this target: don't fade
end

local function applyRange(f)
    local unit = f.unit
    if not UnitExists(unit) or safeBool(UnitIsUnit, unit, "player") then
        f:SetAlpha(1) return
    end
    local grouped = safeBool(UnitInParty, unit) or safeBool(UnitInRaid, unit)
    if not grouped then
        if unit == "target" then
            f:SetAlpha(targetInActionRange() == false and OUT_ALPHA or 1)
        else
            f:SetAlpha(1)
        end
        return
    end
    if safeBool(UnitIsConnected, unit) == false then f:SetAlpha(OUT_ALPHA) return end
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if not ok then f:SetAlpha(1) return end
    if issecretvalue(inRange) then
        if f.SetAlphaFromBoolean then f:SetAlphaFromBoolean(inRange, 1, OUT_ALPHA) else f:SetAlpha(1) end
    elseif checked == false then
        f:SetAlpha(1) -- range unknown (e.g. instance edge cases): don't fade
    else
        f:SetAlpha(inRange and 1 or OUT_ALPHA)
    end
end

function UF:StartRangeFade()
    local acc = 0
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        for _, f in ipairs(UF.frames) do
            if f:IsShown() then
                local ok = pcall(applyRange, f)
                if not ok then f:SetAlpha(1) end
                -- 3D avatars need a refresh when a member comes into view
                -- (models only load for visible units; far away = flat portrait).
                if f.avatar and f.avatar.model then
                    local v = visible(f.unit) and true or false
                    if f.__vis ~= v then
                        f.__vis = v
                        UF:RefreshAvatar(f.avatar)
                    end
                end
            end
        end
    end)
end

ns.commands.blizz = function()
    local db = UF.db
    db.hideBlizzard = not db.hideBlizzard
    UF:ApplyBlizzard(db.hideBlizzard)
    if db.hideBlizzard then ns:Print("Blizzard unit frames hidden") end
end

-- /mui party attach | detach | test
ns.commands.party = function(rest)
    rest = rest or ""
    if rest == "attach" or rest == "detach" then
        if InCombatLockdown() then return ns:Print("Can't move party frames in combat.") end
        UF.db.party.attach = rest == "attach"
        UF:LayoutParty()
        ns:Print("Party frames", UF.db.party.attach and "attached above the player frame"
            or "detached (move with /mui unlock)")
    elseif rest == "test" then
        UF:SetPartyTest(not UF.partyTest)
    else
        ns:Print("usage: /mui party attach | detach | test   (currently "
            .. (UF.db.party.attach and "attached" or "detached") .. ")")
    end
end

-- ── Movable frames ────────────────────────────────────────────────────────
-- /mui unlock : drag the frames, positions save automatically
-- /mui lock   : lock again    /mui reset : restore default positions
local overlays = {}

local function makeOverlay(key, frame, onMoved)
    local o = ns:CreatePanel(UIParent)
    o:SetAllPoints(frame)
    o:SetFrameStrata("DIALOG")
    o.bg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.7)
    o:SetBorderColor(unpack(T.accent))
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    local label = ns:CreateText(o, 11)
    label:SetTextColor(0.07, 0.07, 0.08, 1)
    label:SetShadowColor(1, 1, 1, 0.25)
    label:SetPoint("CENTER")
    label:SetText(key .. " (drag)")
    o:SetScript("OnDragStart", function()
        ns:SnapDragStart(frame)
    end)
    o:SetScript("OnDragStop", function()
        ns:SnapDragStop()
        if InCombatLockdown() then return end
        local fx, fy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local pos = UF.db[key]
        pos.x, pos.y = math.floor(fx - ux + 0.5), math.floor(fy - uy + 0.5)
        place(frame, pos) -- re-anchor to CENTER so the saved offset is exact
        if onMoved then onMoved() end
    end)
    o:Hide()
    return o
end

local function movers()
    local t = { player = UF.player, target = UF.target, focus = UF.focus, boss = UF.bossAnchor }
    if not UF.db.party.attach then t.party = UF.partyAnchor end
    return t
end

function UF:SetLocked(locked)
    if InCombatLockdown() then return ns:Print("Can't move frames in combat.") end
    self.unlocked = not locked
    for key, frame in pairs(movers()) do
        overlays[key] = overlays[key] or makeOverlay(key, frame,
            (key == "party" and function() UF:LayoutParty() end)
            or (key == "boss" and function() UF:LayoutBoss() end) or nil)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        local watched = frame.watch
        if locked then
            overlays[key]:Hide()
            if watched then RegisterUnitWatch(frame) end
        else
            if watched then UnregisterUnitWatch(frame); frame:Show() end
            overlays[key]:Show()
        end
    end
    if overlays.party and (locked or UF.db.party.attach) then overlays.party:Hide() end
    ns:Print(locked and "Frames locked." or "Frames unlocked: drag them, then /mui lock.")
end

ns.commands.unlock = function() UF:SetLocked(false) end
ns.commands.lock   = function() UF:SetLocked(true) end
ns.commands.reset  = function()
    if InCombatLockdown() then return ns:Print("Can't move frames in combat.") end
    for key, pos in pairs(DEFAULT_POS) do
        UF.db[key].x, UF.db[key].y = pos.x, pos.y
    end
    place(UF.player, UF.db.player)
    place(UF.target, UF.db.target)
    place(UF.focus, UF.db.focus)
    UF:LayoutParty()
    UF:LayoutBoss()
    ns:Print("Frame positions reset.")
end

-- Never leave frames in a half-unlocked state when combat starts.
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function()
    if UF.unlocked then
        for _, o in pairs(overlays) do o:Hide() end
        ns:Print("Combat started: move mode paused. /mui lock when out of combat.")
    end
end)

-- ── Diagnostics and tuning ────────────────────────────────────────────────
ns.commands.hp = function()
    for _, f in ipairs(UF.frames or {}) do
        ns:Print(f.key, "health text path:", tostring(f.hpPath))
    end
end

local function eachModel(fn)
    for _, f in ipairs(UF.frames or {}) do
        if f.avatar and f.avatar.model then fn(f.avatar) end
    end
end

-- /mui portrait                 show current camera values
-- /mui portrait <key> <value>   zoom | dist | z | facing | pop | fidget   (applies live)
-- /mui portrait reset
ns.commands.portrait = function(rest)
    local p = UF.db and UF.db.portrait
    if not p then return end
    if p.x == nil or p.x == -0.03 then p.x = 0.04 end
    local key, val = (rest or ""):match("^(%S+)%s+(%S+)$")
    val = tonumber(val)
    if rest == "reset" then
        if InCombatLockdown() then return ns:Print("Can't resize avatars in combat.") end
        p.zoom, p.dist, p.z, p.facing, p.pop, p.fidget, p.x = 1.0, 1.0, 0, 0, 0.25, 0, 0.04
        eachModel(function(av) UF:LayoutAvatar(av); UF:RefreshAvatar(av) end)
    elseif key and val and p[key] ~= nil then
        if InCombatLockdown() and key == "pop" then
            return ns:Print("Can't resize avatars in combat.")
        end
        p[key] = val
        eachModel(function(av) UF:LayoutAvatar(av); UF:RefreshAvatar(av) end)
    elseif rest and rest ~= "" then
        ns:Print("usage: /mui portrait <zoom|dist|x|z|facing|pop|fidget> <number>  |  /mui portrait reset")
    end
    ns:Print(string.format("portrait zoom %.2f  dist %.2f  x %.2f  z %.2f  facing %.2f  pop %.2f  fidget %d",
        p.zoom, p.dist, p.x, p.z, p.facing, p.pop, p.fidget))
end
