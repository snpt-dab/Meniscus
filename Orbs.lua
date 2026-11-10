local _, ns = ...
local T = ns.Theme

-- Health and resource orbs for the player.
-- Fill is a vertical StatusBar whose texture is cropped by a circle mask, so it
-- only ever receives SetMinMaxValues/SetValue (safe with secret values).
-- Polish layers (all masked to the circle): depth vignette, glass shine,
-- bright "liquid surface" line riding the fill level, gloss cap. Frame: hairline
-- ring + dark track (pill style), value in a pill badge on the bottom edge.

local DEFAULT = {
    health = { x = -362, y = 30 },
    power  = { x = 362,  y = 30 },
}

local Orbs = ns:NewModule("Orbs", {
    enabled = true,
    size = 120,
    health = { x = DEFAULT.health.x, y = DEFAULT.health.y },
    power  = { x = DEFAULT.power.x,  y = DEFAULT.power.y },
})

local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local SWIRL = "Interface/AddOns/MinimalUI/Media/swirl.tga"
local MEDIA = "Interface/AddOns/MinimalUI/Media/"
local RING_W = 1.5 -- hairline outer ring
local INSET = 4    -- dark track between ring and liquid
local CHIP_W = 112 -- value badge (8:1 pill -> 14px tall)

local POWER = {
    [0] = { 0.25, 0.50, 0.98 }, -- mana
    [1] = { 0.80, 0.16, 0.08 }, -- rage (RAGE_STOPS holds the real ramp)
    [2] = { 0.92, 0.62, 0.25 }, -- focus
    [3] = { 0.96, 0.88, 0.35 }, -- energy
}
local HEALTH = { 0.20, 0.74, 0.34 } -- green

local function newMask(frame, size)
    local m = frame:CreateMaskTexture()
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetPoint("CENTER", frame, "CENTER")
    m:SetSize(size, size)
    return m
end

local function setText(fs, value)
    if not issecretvalue(value) then
        local n = value
        if n >= 1e6 then fs:SetText(string.format("%.1fm", n / 1e6))
        elseif n >= 1e3 then fs:SetText(string.format("%.1fk", n / 1e3))
        else fs:SetText(tostring(math.floor(n))) end
        return
    end
    if AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, value)
        if ok and s ~= nil then fs:SetText(s) return end
    end
    fs:SetText("")
end

local function setValue(bar, v)
    local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    if interp and pcall(bar.SetValue, bar, v, interp) then return end
    bar:SetValue(v)
end

local function createOrb(name, size)
    local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    f:SetSize(size, size)
    f:SetAttribute("unit", "player")
    f:SetAttribute("*type1", "target") -- any modifiers (see UnitFrames.lua)
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyDown", "AnyUp") -- secure buttons act on the press
    -- Clickable area = the square inscribed in the circle, so the orb's empty
    -- corners never steal clicks from neighbouring buttons.
    local hit = size * (1 - 0.7071) / 2
    f:SetHitRectInsets(hit, hit, hit, hit)
    f:SetClampedToScreen(true)

    -- Pill language: hairline neutral ring -> dark track -> inset liquid.
    -- No colored halo (it bled into the scene).
    local track = size - RING_W * 2           -- inside the hairline ring
    local inner = size - (RING_W + INSET) * 2 -- the liquid
    local ringMask = newMask(f, size)
    local trackMask = newMask(f, track)
    local innerMask = newMask(f, inner)

    f.ring = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.ring:SetAllPoints()
    f.ring:SetColorTexture(unpack(T.border))
    f.ring:AddMaskTexture(ringMask)

    f.track = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.track:SetPoint("CENTER")
    f.track:SetSize(track, track)
    f.track:SetColorTexture(0.05, 0.05, 0.06, 0.96)
    f.track:AddMaskTexture(trackMask)

    f.inner, f.innerMask = inner, innerMask

    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.bg:SetPoint("CENTER")
    f.bg:SetSize(inner, inner)
    f.bg:SetColorTexture(0.02, 0.025, 0.03, 1)
    f.bg:AddMaskTexture(innerMask)

    -- Textured backdrop: slow liquid streaks visible in the empty part of the orb.
    f.swirlBack = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    f.swirlBack:SetPoint("CENTER")
    f.swirlBack:SetSize(inner, inner)
    f.swirlBack:SetTexture(SWIRL, "REPEAT", "REPEAT")
    f.swirlBack:SetVertexColor(0.7, 0.8, 0.9, 0.20)
    f.swirlBack:AddMaskTexture(innerMask)

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetPoint("CENTER")
    f.bar:SetSize(inner, inner)
    f.bar:SetOrientation("VERTICAL")
    f.bar:SetStatusBarTexture(T.bar)
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(1)
    local fill = f.bar:GetStatusBarTexture()
    fill:AddMaskTexture(innerMask)

    -- Color change crossfade: health is hidden from addons, so its color
    -- can't be blended in Lua. Instead this copy of the fill keeps the old
    -- color and fades out over the new one.
    f.oldFill = f.bar:CreateTexture(nil, "ARTWORK", nil, 7)
    f.oldFill:SetTexture(T.bar)
    f.oldFill:SetAllPoints(fill)
    f.oldFill:AddMaskTexture(innerMask)
    f.oldFill:SetAlpha(0)
    -- Driven by hand, not an Animation: an animation only takes over on the
    -- next frame, so each heal showed the new color for a frame, snapped
    -- back to the old one, then faded (a visible flicker per bandage tick).
    local fader = CreateFrame("Frame", nil, f)
    fader:Hide()
    fader:SetScript("OnUpdate", function(self, dt)
        self.t = self.t + dt
        local p = self.t / 0.45
        if p >= 1 then
            f.oldFill:SetAlpha(0)
            self:Hide()
        else
            f.oldFill:SetAlpha((1 - p) * (1 - p)) -- ease out
        end
    end)
    f.fillFader = fader

    -- A second, larger streak layer drifting the other way gives the fill depth.
    f.swirlTop = f.bar:CreateTexture(nil, "OVERLAY", nil, -2)
    f.swirlTop:SetAllPoints(f.bar)
    f.swirlTop:SetTexture(SWIRL, "REPEAT", "REPEAT")
    f.swirlTop:SetVertexColor(1, 1, 1, 0.09)
    f.swirlTop:AddMaskTexture(innerMask)

    -- Drift driver (non-secure child so the secure orb button stays untouched).
    local driver = CreateFrame("Frame", nil, f)
    local phase = math.random() * 10
    driver:SetScript("OnUpdate", function(_, dt)
        phase = phase + dt
        local u, v = phase * 0.010, phase * 0.017
        f.swirlBack:SetTexCoord(u, u + 1, v, v + 1)
        local s = 0.62
        f.swirlTop:SetTexCoord(-u * 1.4, -u * 1.4 + s, v * 1.2, v * 1.2 + s)
    end)

    -- Bright meniscus riding the fill level.
    f.line = f.bar:CreateTexture(nil, "OVERLAY", nil, 0)
    f.line:SetHeight(2)
    f.line:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, -1)
    f.line:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, -1)
    f.line:SetColorTexture(1, 1, 1, 0.8)
    f.line:AddMaskTexture(innerMask)

    -- Depth: darker toward the bottom of the orb.
    f.depth = f.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    f.depth:SetAllPoints(f.bar)
    f.depth:SetColorTexture(0, 0, 0, 1)
    pcall(f.depth.SetGradient, f.depth, "VERTICAL",
        CreateColor(0, 0, 0, 0.50), CreateColor(0, 0, 0, 0))
    f.depth:AddMaskTexture(innerMask)

    -- Glass: faint brightening toward the top (same sheen as the pills).
    f.shine = f.bar:CreateTexture(nil, "OVERLAY", nil, 2)
    f.shine:SetAllPoints(f.bar)
    f.shine:SetColorTexture(1, 1, 1, 1)
    pcall(f.shine.SetGradient, f.shine, "VERTICAL",
        CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.05))
    f.shine:AddMaskTexture(innerMask)

    -- Glare: a pre-rendered soft specular highlight lit from the upper left
    -- (tilted blob + tiny hot spot) with a faint bounce rim on the lower
    -- right. Both orbs share the same light direction.
    f.gloss = f.bar:CreateTexture(nil, "OVERLAY", nil, 3)
    f.gloss:SetAllPoints(f.bar)
    f.gloss:SetTexture(MEDIA .. "orb_glare.tga")
    f.gloss:AddMaskTexture(innerMask)

    -- Value badge: a small pill sitting on the orb's bottom edge, like the
    -- unit frame pills (dark fill, hairline ring tinted by the resource).
    local chip = CreateFrame("Frame", nil, f)
    chip:SetSize(CHIP_W, CHIP_W / 8) -- 8:1 pill textures
    chip:SetPoint("CENTER", f, "BOTTOM", 0, RING_W + 2)
    chip:SetFrameLevel(f.bar:GetFrameLevel() + 3)
    local chipMask = chip:CreateMaskTexture()
    chipMask:SetTexture(MEDIA .. "pill8_mask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    chipMask:SetAllPoints()
    f.chipMask = chipMask
    local chipBg = chip:CreateTexture(nil, "BACKGROUND")
    chipBg:SetAllPoints()
    chipBg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
    chipBg:AddMaskTexture(chipMask)
    f.chipRing = chip:CreateTexture(nil, "BORDER")
    f.chipRing:SetAllPoints()
    f.chipRing:SetTexture(MEDIA .. "pill8_ring.tga")
    f.chipRing:SetVertexColor(unpack(T.border))
    f.chip = chip

    f.text = ns:CreateText(chip, 11)
    f.text:SetPoint("CENTER", chip, "CENTER", 0, 0)
    f.text:SetShadowOffset(1, -1)
    f.text:SetShadowColor(0, 0, 0, 0.8)

    -- Low-resource flash: a bright pulse over the liquid. The pulse loops
    -- forever; its holder's alpha (0 = off) sets how strong it is, so the
    -- strength can come straight from a curve evaluated on a secret value.
    local flashHolder = CreateFrame("Frame", nil, f.bar)
    flashHolder:SetAllPoints(f.bar)
    flashHolder:SetFrameLevel(f.bar:GetFrameLevel() + 1)
    flashHolder:SetAlpha(0)
    -- Covers the whole orb (ring, track and glass), not just the liquid.
    local flash = flashHolder:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints(f)
    flash:SetColorTexture(1, 1, 1, 1)
    flash:SetBlendMode("ADD")
    flash:AddMaskTexture(ringMask)
    f.flash = flash
    flash:SetAlpha(0)
    local pulse = flash:CreateAnimationGroup()
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(0.55)
    a:SetDuration(0.45)
    a:SetSmoothing("IN_OUT")
    pulse:SetLooping("BOUNCE")
    -- Rim: the dark border (hairline + track) pulses bright white in step
    -- with the glow. Same holder, so it only shows when the glow does.
    local rim = flashHolder:CreateTexture(nil, "OVERLAY", nil, 2)
    rim:SetAllPoints(f)
    rim:SetTexture(MEDIA .. "orb_rim.tga")
    rim:SetBlendMode("ADD")
    rim:SetAlpha(0)
    local rimPulse = rim:CreateAnimationGroup()
    local ra = rimPulse:CreateAnimation("Alpha")
    ra:SetFromAlpha(0)
    ra:SetToAlpha(1)
    ra:SetDuration(0.45)
    ra:SetSmoothing("IN_OUT")
    rimPulse:SetLooping("BOUNCE")
    rim:Hide()
    pulse:Play()
    rimPulse:Play()
    f.flashHolder, f.flashAnim = flashHolder, a
    f.rim, f.rimAnim = rim, ra

    function f:SetTint(r, g, b)
        self.bar:SetStatusBarColor(r, g, b)
        self.chipRing:SetVertexColor(r * 0.8, g * 0.8, b * 0.8, 1)
        self.tintR, self.tintG, self.tintB = r, g, b
        self.swirlBack:SetVertexColor(r * 0.5 + 0.4, g * 0.5 + 0.4, b * 0.5 + 0.4, self.swirlBackA or 0.20)
        self.line:SetColorTexture(math.min(r * 1.25 + 0.15, 1),
                                  math.min(g * 1.25 + 0.15, 1),
                                  math.min(b * 1.25 + 0.15, 1), 0.85)
    end
    return f
end

-- ── Fill color by percentage ──────────────────────────────────────────────
-- Stops: { pct, r, g, b }, colors blend linearly between them.
-- Flash: { pct, strength } (holder alpha; 0 = no flash).
local HEALTH_STOPS = {
    { 0.00, 0.90, 0.18, 0.18 }, -- red
    { 0.15, 0.90, 0.20, 0.20 },
    { 0.30, 0.95, 0.52, 0.16 }, -- orange
    { 0.50, 0.95, 0.84, 0.24 }, -- yellow
    { 0.75, 0.56, 0.80, 0.26 }, -- yellow-green
    { 0.90, 0.20, 0.74, 0.34 }, -- green
    { 1.00, 0.20, 0.74, 0.34 },
}
local HEALTH_FLASH = { { 0.00, 1.0 }, { 0.15, 0.85 }, { 0.30, 0.35 }, { 0.40, 0.0 }, { 1.00, 0.0 } }
-- Mana: the same idea, quieter. Blue drifts toward violet and dims a little
-- when low; a slow, faint pulse under 20%.
local MANA_STOPS = {
    { 0.00, 0.42, 0.30, 0.78 },
    { 0.25, 0.30, 0.40, 0.92 },
    { 0.50, 0.25, 0.50, 0.98 },
    { 1.00, 0.25, 0.50, 0.98 },
}
local MANA_FLASH = { { 0.00, 0.45 }, { 0.20, 0.0 }, { 1.00, 0.0 } }

-- Other power types. stops(c) builds color stops from the base color c.
local function dim(c, k) return c[1] * k, c[2] * k, c[3] * k end
local function heat(c) -- builder: darker when empty, brighter/warmer when full
    local r, g, b = dim(c, 0.55)
    return { { 0.00, r, g, b }, { 0.50, c[1], c[2], c[3] },
             { 1.00, math.min(c[1] + 0.12, 1), math.min(c[2] + 0.18, 1), math.min(c[3] + 0.10, 1) } }
end
local function steady(c)
    local r, g, b = dim(c, 0.75)
    return { { 0.00, r, g, b }, { 0.40, c[1], c[2], c[3] }, { 1.00, c[1], c[2], c[3] } }
end
local POWER_FX = {
    builder = { stops = heat, flash = { { 0.00, 0 }, { 0.70, 0 }, { 1.00, 0.50 } },
                dur = 0.6, flashColor = { 1.0, 0.45, 0.25 } },
    [1] = { stops = heat, flash = { { 0.00, 0 }, { 0.70, 0 }, { 1.00, 0.75 } },   -- rage
            dur = 0.6, flashColor = { 1.0, 0.40, 0.25 } },
    [2] = { stops = steady, flash = { { 0.00, 0 }, { 0.92, 0 }, { 1.00, 0.30 } }, -- focus
            dur = 1.2, flashColor = { 1.0, 0.75, 0.40 } },
    [3] = { stops = steady, flash = { { 0.00, 0 }, { 0.92, 0 }, { 1.00, 0.30 } }, -- energy
            dur = 1.2, flashColor = { 1.0, 0.95, 0.55 } },
}

local function lerpStops(stops, pct)
    if pct <= stops[1][1] then return stops[1][2], stops[1][3], stops[1][4] end
    for i = 2, #stops do
        local a, b = stops[i - 1], stops[i]
        if pct <= b[1] then
            local t = (pct - a[1]) / math.max(b[1] - a[1], 1e-6)
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    local l = stops[#stops]
    return l[2], l[3], l[4]
end

local function lerpFlash(points, pct)
    if pct <= points[1][1] then return points[1][2] end
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        if pct <= b[1] then
            return a[2] + (b[2] - a[2]) * (pct - a[1]) / math.max(b[1] - a[1], 1e-6)
        end
    end
    return points[#points][2]
end

-- Curves for the secret path: the client evaluates them on the hidden %.
local function colorCurve(stops)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    if Enum and Enum.LuaCurveType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    for _, s in ipairs(stops) do c:AddPoint(s[1], CreateColor(s[2], s[3], s[4], 1)) end
    return c
end
local function floatCurve(points)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then return nil end
    if Enum and Enum.LuaCurveType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    for _, p in ipairs(points) do c:AddPoint(p[1], p[2]) end
    return c
end

-- Fill colors as three float curves (r, g, b): evaluating a color curve
-- returns a fresh Color table every time, which in combat (many health and
-- rage updates a second) was a steady stream of garbage.
local function rgbCurves(stops)
    local r, g, b = {}, {}, {}
    for i, st in ipairs(stops) do
        r[i], g[i], b[i] = { st[1], st[2] }, { st[1], st[3] }, { st[1], st[4] }
    end
    local cr, cg, cb = floatCurve(r), floatCurve(g), floatCurve(b)
    if cr and cg and cb then return { rgb = true, cr, cg, cb } end
    return colorCurve(stops)
end

local curves = {}
local function getCurves()
    if not curves.built then
        curves.built = true
        pcall(function()
            curves.healthColor, curves.healthFlash = rgbCurves(HEALTH_STOPS), floatCurve(HEALTH_FLASH)
            curves.manaColor, curves.manaFlash = rgbCurves(MANA_STOPS), floatCurve(MANA_FLASH)
        end)
    end
    return curves
end

-- r, g, b may be hidden values: they're only handed to the engine.
local function paintFill(f, r, g, b)
    if f.fillR ~= nil then
        f.oldFill:SetVertexColor(f.fillR, f.fillG, f.fillB, 1)
        f.oldFill:SetAlpha(1)
        f.fillFader.t = 0
        f.fillFader:Show()
    end
    f.fillR, f.fillG, f.fillB = r, g, b
    f.bar:SetStatusBarColor(r, g, b)
    f.chipRing:SetVertexColor(r, g, b, 1)
end

local function setFill(f, r, g, b)
    -- Plain values: skip the fade when nothing visibly changed (mana ticks).
    if f.fillR ~= nil and not issecretvalue(f.fillR)
        and math.abs(f.fillR - r) + math.abs(f.fillG - g) + math.abs(f.fillB - b) < 0.01 then return end
    paintFill(f, r, g, b)
end

-- Curve evaluators, called through pcall without building closures.
local function evalFill(f, pctFn, c)
    if c.rgb then
        paintFill(f, pctFn(c[1]), pctFn(c[2]), pctFn(c[3]))
    else
        paintFill(f, pctFn(c):GetRGB())
    end
end
local function evalAlpha(frame, pctFn, c) frame:SetAlpha(pctFn(c)) end

-- cur/max: values (maybe secret). pctFn(curve): the client's percent
-- evaluator for this resource (UnitHealthPercent / UnitPowerPercent).
local function colorByPercent(f, cur, max, stops, flashPts, cColor, cFlash, pctFn)
    if not issecretvalue(cur) and not issecretvalue(max) then
        local pct = (max and max > 0) and cur / max or 1
        setFill(f, lerpStops(stops, pct))
        f.flashHolder:SetAlpha(lerpFlash(flashPts, pct))
        f.colorPath = "plain"
        return
    end
    if pctFn and cColor then
        local ok = pcall(evalFill, f, pctFn, cColor)
        local okF = cFlash and pcall(evalAlpha, f.flashHolder, pctFn, cFlash)
        if not okF then f.flashHolder:SetAlpha(0) end
        f.colorPath = ok and "curve" or "static"
        if ok then return end
    end
    -- No way to read the percentage: static full color, no flash.
    setFill(f, stops[#stops][2], stops[#stops][3], stops[#stops][4])
    f.flashHolder:SetAlpha(0)
    f.colorPath = "static"
end

-- ── Rage: a roiling boil ──────────────────────────────────────────────────
-- Deep crimson when low, heating toward bright orange-red. Inside the liquid
-- (clipped at the surface): two magma streak layers drifting upward, bubbles
-- popping at the surface (throwing sparks near full), a heat flicker and a
-- glowing surface band, all faster, denser and brighter as rage climbs.
-- Crossing 15 rage throws a flare-up. (A sloshing surface was tried and
-- dropped: bubbles escaped the liquid.)
local RAGE_STOPS = {
    { 0.00, 0.34, 0.03, 0.05 }, -- deep crimson
    { 0.15, 0.50, 0.05, 0.06 },
    { 0.45, 0.76, 0.11, 0.06 },
    { 0.75, 0.94, 0.28, 0.08 },
    { 1.00, 1.00, 0.46, 0.13 }, -- bright orange-red
}
local RAGE_FLASH = { { 0.00, 0 }, { 0.85, 0 }, { 1.00, 0.35 } }
local RAGE_ALPHA = { { 0.00, 0 }, { 0.01, 0.45 }, { 1.00, 1 } } -- secret path only
-- Hidden rage (Forever hides it from addons): the client evaluates these on
-- the hidden percentage and sets each layer's opacity, so the boil still
-- builds up without Lua ever reading the number.
local HOT_ALPHA = { { 0.00, 0 }, { 0.30, 0 }, { 1.00, 1 } }   -- fine magma + heat
local BOIL_ALPHA = { { 0.00, 0 }, { 0.50, 0 }, { 1.00, 1 } }  -- the fast bubbles
local SPARK_ALPHA = { { 0.00, 0 }, { 0.50, 0 }, { 0.55, 0.3 }, { 1.00, 1 } }
local IDENT = { { 0.00, 0 }, { 1.00, 1 } }                     -- percent itself (probes)
local FLARE_AT, FLARE_DUR = { 15, 60, 100 }, 1.0 -- flare when rage climbs past each
local MAX_BUBBLES, MAX_SPARKS = 36, 14
local SPOT = MEDIA .. "spot.tga"
local BREACH = 8 -- px bubbles may poke above the surface before popping

local function freeBubble(R, i)
    local b = R.live[i]
    b.tex:Hide()
    R.live[i] = R.live[#R.live]
    R.live[#R.live] = nil
    table.insert(b.home, b)
end

-- Bubbles come from two pools: the base simmer and the fast "boil" set,
-- which hidden-rage mode fades in from 50% (BOIL_ALPHA). k: how hot.
local function spawnBubble(R, half, pool, k)
    if not R.secret and R.surf < -half + 10 then return end
    local b = table.remove(pool)
    if not b then return end
    local e = k * k -- steep: calm for most of the range, violent near full
    -- b.y is measured from the liquid's surface (the fill's top edge, which
    -- the client places even when rage is hidden): negative = below it.
    local room
    if R.secret then
        -- Depth unknown: start anywhere down the orb; those below the bottom
        -- stay clipped until they rise into view.
        b.y = -2 * half * (0.15 + 0.85 * math.random())
        room = half * 0.75
    else
        b.y = -(R.surf + half) + 4 -- from the bottom of the liquid
        -- Stay inside the circle where the bubble will pop (near full, the
        -- surface is up where the orb is narrow and the mask hid everything).
        local popY = math.min(R.surf, half * 0.8)
        room = math.sqrt(math.max(0, half * half - popY * popY))
    end
    b.y0 = b.y
    b.x = (math.random() * 2 - 1) * math.min(half * 0.6, room * 0.8)
    b.vy = (14 + 30 * k + 110 * e) * (0.7 + 0.6 * math.random())
    b.s = 2 + math.random() * (2 + 5 * k)
    b.a = 0.30 + 0.60 * k
    b.wf, b.wp, b.wa = 2 + math.random() * 3, math.random() * 6.28, 0.5 + math.random() * 2
    b.pop = nil
    b.tex:Show()
    table.insert(R.live, b)
end

local buildProbes -- (defined below, with the other hidden-rage code)
local function buildRage(f)
    if f.rage then return f.rage end
    local inner, mask = f.inner, f.innerMask
    local half = inner / 2
    local fill = f.bar:GetStatusBarTexture()
    local R = CreateFrame("Frame", nil, f.bar)
    R:SetAllPoints(f.bar)
    R:SetFrameLevel(f.bar:GetFrameLevel() + 1)
    f.flashHolder:SetFrameLevel(f.bar:GetFrameLevel() + 2)
    R.k, R.t, R.v1, R.v2, R.spawn = 0, 0, 0, 0, 0
    R.surf = -half
    R.live, R.pool, R.boilPool = {}, {}, {}

    -- Everything below the surface lives in this clip frame.
    local clip = CreateFrame("Frame", nil, R)
    clip:SetPoint("TOPLEFT", fill, "TOPLEFT")
    clip:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
    clip:SetClipsChildren(true)
    local function layer(sub, parent)
        local t = (parent or clip):CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetSize(inner, inner)
        t:SetPoint("CENTER", f.bar, "CENTER")
        t:SetBlendMode("ADD")
        t:AddMaskTexture(mask)
        return t
    end
    R.magma1 = layer(0)
    R.magma1:SetTexture(SWIRL, "REPEAT", "REPEAT")
    R.magma1:SetVertexColor(1, 0.40, 0.10)
    -- Bubbles get their own clip, a little taller, so they can breach the
    -- surface before popping.
    local bclip = CreateFrame("Frame", nil, R)
    bclip:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, BREACH)
    bclip:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
    bclip:SetClipsChildren(true)
    -- Holders whose opacity the client sets from hidden rage.
    R.hotHolder = CreateFrame("Frame", nil, clip)
    R.hotHolder:SetAllPoints(clip)
    R.boilHolder = CreateFrame("Frame", nil, bclip)
    R.boilHolder:SetAllPoints(bclip)
    R.magma2 = layer(1, R.hotHolder)
    R.magma2:SetTexture(SWIRL, "REPEAT", "REPEAT")
    R.magma2:SetVertexColor(1, 0.68, 0.25)
    -- Heat: hotter at the bottom of the liquid.
    R.heat = layer(2, R.hotHolder)
    R.heat:SetColorTexture(1, 1, 1, 1)
    pcall(R.heat.SetGradient, R.heat, "VERTICAL", CreateColor(1, 0.55, 0.15, 1), CreateColor(1, 0.30, 0.08, 0.2))

    for i = 1, MAX_BUBBLES do
        local boil = i > MAX_BUBBLES / 2
        local t = (boil and R.boilHolder or bclip):CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetTexture(SPOT)
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.78, 0.40)
        t:AddMaskTexture(mask)
        t:Hide()
        local home = boil and R.boilPool or R.pool
        table.insert(home, { tex = t, home = home })
    end

    -- Glowing band riding the surface (spills a little above it).
    R.surface = R:CreateTexture(nil, "OVERLAY", nil, 1)
    R.surface:SetTexture(SPOT)
    R.surface:SetBlendMode("ADD")
    R.surface:SetVertexColor(1, 0.62, 0.22)
    R.surface:SetSize(inner * 1.1, 14)
    R.surface:SetPoint("CENTER", fill, "TOP", 0, 0)
    R.surface:AddMaskTexture(mask)

    -- Flare-up: its own frame so it ignores the boil's alpha, and it may
    -- spill past the orb for a moment.
    local fl = CreateFrame("Frame", nil, f)
    R.flareFrame = fl
    fl:SetAllPoints(f)
    fl:SetFrameLevel(f.bar:GetFrameLevel() + 5)
    R.burst = fl:CreateTexture(nil, "OVERLAY", nil, 0)
    R.burst:SetTexture(SPOT)
    R.burst:SetBlendMode("ADD")
    R.burst:SetVertexColor(1, 0.45, 0.12)
    R.burst:SetPoint("CENTER", f, "CENTER")
    R.core = fl:CreateTexture(nil, "OVERLAY", nil, 1)
    R.core:SetColorTexture(1, 0.62, 0.22, 1)
    R.core:SetBlendMode("ADD")
    R.core:SetAllPoints(f.bar)
    R.core:AddMaskTexture(mask)
    -- Two flame tongues (offset, out of step) and a white-hot center.
    local function tongue(sub)
        local t = fl:CreateTexture(nil, "OVERLAY", nil, sub)
        t:SetTexture(SPOT)
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.70, 0.30)
        return t
    end
    R.tongue, R.tongue2 = tongue(2), tongue(3)
    R.hot = fl:CreateTexture(nil, "OVERLAY", nil, 4)
    R.hot:SetTexture(SPOT)
    R.hot:SetBlendMode("ADD")
    R.hot:SetVertexColor(1, 0.92, 0.70)
    R.hot:SetPoint("CENTER", f, "CENTER", 0, inner * 0.05)
    R.flareTex = { R.burst, R.core, R.tongue, R.tongue2, R.hot }
    for _, t in ipairs(R.flareTex) do t:SetAlpha(0) end

    -- Sparks: thrown out of the surface by popping bubbles once rage is up.
    -- Not masked to the circle, so near full they fly out of the orb's top.
    -- Positions are relative to the liquid's surface (the fill's top edge),
    -- which the client places even when the rage value is hidden.
    R.sparks, R.sparkPool = {}, {}
    R.sparkHolder = CreateFrame("Frame", nil, fl)
    R.sparkHolder:SetAllPoints(fl)
    for _ = 1, MAX_SPARKS do
        local t = R.sparkHolder:CreateTexture(nil, "OVERLAY", nil, 5)
        t:SetTexture(SPOT)
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.93, 0.62) -- hotter and whiter than the bubbles
        t:Hide()
        table.insert(R.sparkPool, { tex = t })
    end

    -- One spark leaving the liquid at x, y0 below the surface (0 = on it).
    function R:Spark(x, y0)
        local s = table.remove(self.sparkPool)
        if not s then return end
        s.x, s.y = x, y0
        s.vx, s.vy = (math.random() - 0.5) * 30, 50 + math.random() * 70
        s.life, s.age = 0.5 + math.random() * 0.6, 0
        s.size = 1.6 + math.random() * 0.8 -- thin streaks, not dots
        s.tex:Show()
        table.insert(self.sparks, s)
    end

    R:SetScript("OnUpdate", function(self, dt)
        if dt > 0.05 then dt = 0.05 end -- keep the springs stable through hitches
        local t = self.t + dt
        self.t = t
        -- Plain rage: everything follows k. Hidden rage: the base layers run
        -- calm (k) and the hot layers fast (kh); the client's curves fade the
        -- hot layers in as rage rises (see rageFX).
        local hidden = self.secret
        local k = hidden and 0.3 or self.k
        local kh = hidden and 0.9 or k
        local e, eh = k * k, kh * kh
        local speed = 0.35 + 0.8 * k + 2.6 * e
        local speedH = 0.35 + 0.8 * kh + 2.6 * eh
        local flick = 0.78 + 0.22 * math.sin(t * (6 + 10 * kh)) * math.sin(t * (2.3 + 3 * kh) + 1.7)

        self.surface:SetAlpha((0.25 + 0.60 * (hidden and 0.6 or k)) * (0.72 + 0.28 * math.sin(t * 9.7)))

        -- Magma streaks rise (v grows) and sway; the finer second layer
        -- only really shows once rage is up.
        self.v1 = self.v1 + dt * 0.045 * speed
        self.v2 = self.v2 + dt * 0.085 * speedH
        local u1, u2 = 0.04 * math.sin(t * 0.6), 0.3 + 0.06 * math.sin(t * 0.9 + 2)
        self.magma1:SetTexCoord(u1, u1 + 0.9, self.v1, self.v1 + 0.9)
        self.magma2:SetTexCoord(u2, u2 + 0.55, self.v2, self.v2 + 0.55)
        self.magma1:SetAlpha((0.10 + 0.40 * k) * flick)
        self.magma2:SetAlpha((0.03 + 0.37 * eh) * flick)
        self.heat:SetAlpha(0.24 * eh * flick)

        -- Bubbles: more, bigger and faster as rage climbs; pop at the surface.
        self.spawn = self.spawn + dt * (1.5 + 6 * k + 44 * e)
        if hidden then
            self.spawnH = (self.spawnH or 0) + dt * (1.5 + 6 * kh + 44 * eh)
            while self.spawn >= 1 do self.spawn = self.spawn - 1; spawnBubble(self, half, self.pool, k) end
            while self.spawnH >= 1 do self.spawnH = self.spawnH - 1; spawnBubble(self, half, self.boilPool, kh) end
            -- The real surface is unknown here (bubbles just vanish into the
            -- clip there), so sparks leave it on a timer; SPARK_ALPHA keeps
            -- them invisible below 50%.
            self.sparkT = (self.sparkT or 0) + dt * 7
            while self.sparkT >= 1 do
                self.sparkT = self.sparkT - 1
                self:Spark((math.random() * 2 - 1) * half * 0.35, 0)
            end
        else
            while self.spawn >= 1 do
                self.spawn = self.spawn - 1
                spawnBubble(self, half, #self.pool > 0 and self.pool or self.boilPool, k)
            end
        end
        local i = 1
        while i <= #self.live do
            local b = self.live[i]
            local gone = false
            if b.pop then
                b.pop = b.pop + dt
                local p = b.pop / 0.18
                if p >= 1 then
                    gone = true
                else
                    b.tex:SetSize(b.s * (1 + 1.4 * p), b.s * (1 + 0.8 * p))
                    b.tex:SetAlpha(b.a * (1 - p))
                    b.y = b.y + dt * 12 -- the burst lifts off the surface
                end
            else
                b.y = b.y + b.vy * dt
                -- Breach: the bubble's top pokes through, then it pops. Near
                -- full (plain rage) the surface is up in the orb's narrow
                -- top, so pop lower to stay inside the visible circle.
                local top = 2
                if not hidden then top = math.min(top, half * 0.8 - self.surf) end
                if b.y >= top then
                    b.pop = 0
                    -- From half rage up, pops throw sparks out of the liquid:
                    -- none below 50%, rising to most pops at full.
                    if not hidden and k >= 0.5 and math.random() < (k - 0.5) * 1.6 then
                        self:Spark(b.x, b.y)
                    end
                end
                b.tex:SetSize(b.s, b.s)
                b.tex:SetAlpha(b.a * math.min(1, (b.y - b.y0) / 14))
            end
            if gone then
                freeBubble(self, i)
            else
                b.tex:SetPoint("CENTER", fill, "TOP", b.x + math.sin(t * b.wf + b.wp) * b.wa, b.y)
                i = i + 1
            end
        end

        -- Sparks: arc up, slow down, flicker out.
        local j = 1
        while j <= #self.sparks do
            local s = self.sparks[j]
            s.age = s.age + dt
            local p = s.age / s.life
            if p >= 1 then
                s.tex:Hide()
                self.sparks[j] = self.sparks[#self.sparks]
                self.sparks[#self.sparks] = nil
                table.insert(self.sparkPool, s)
            else
                s.vy = s.vy - 60 * dt
                s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
                -- A streak along its flight, shrinking as it cools.
                s.tex:SetSize(s.size, s.size * (3 + 0.03 * math.abs(s.vy)) * (1 - 0.5 * p))
                s.tex:SetAlpha((1 - p) * (0.7 + 0.3 * math.sin(s.age * 40)))
                s.tex:SetPoint("CENTER", fill, "TOP", s.x, s.y)
                j = j + 1
            end
        end

        -- Flare-up: white-hot snap, a big burst spilling past the orb, the
        -- liquid lit up, and two flame tongues licking upward out of it.
        if self.flareT then
            self.flareT = self.flareT + dt
            local p = self.flareT / FLARE_DUR
            if p >= 1 then
                self.flareT = nil
                for _, tx in ipairs(self.flareTex) do tx:SetAlpha(0) end
            else
                local a = p < 0.08 and p / 0.08 or (1 - (p - 0.08) / 0.92) ^ 1.6
                local snap = p < 0.05 and p / 0.05 or math.max(0, 1 - (p - 0.05) / 0.25)
                local s = inner * 2.3 * (0.55 + 0.7 * p)
                self.burst:SetSize(s, s)
                self.burst:SetAlpha(a)
                self.core:SetAlpha(0.9 * a)
                local hs = inner * (0.7 + 0.5 * p)
                self.hot:SetSize(hs, hs)
                self.hot:SetAlpha(snap)
                local sway = math.sin(p * 9) * inner * 0.04
                self.tongue:SetSize(inner * (0.6 - 0.25 * p), inner * (1.1 + 1.3 * p))
                self.tongue:ClearAllPoints()
                self.tongue:SetPoint("BOTTOM", f, "CENTER", sway - inner * 0.08, -inner * 0.2 + inner * 0.55 * p)
                self.tongue:SetAlpha(a)
                local p2 = math.max(0, p - 0.12)
                self.tongue2:SetSize(inner * (0.45 - 0.2 * p2), inner * (0.8 + 1.1 * p2))
                self.tongue2:ClearAllPoints()
                self.tongue2:SetPoint("BOTTOM", f, "CENTER", -sway + inner * 0.12, -inner * 0.1 + inner * 0.5 * p2)
                self.tongue2:SetAlpha(p < 0.12 and 0 or 0.85 * a)
            end
        end
    end)
    -- Sparks live on the flare frame (so they can leave the orb), which
    -- stays shown: when the boil stops, clear them and any bubbles, or they
    -- freeze in place.
    R:SetScript("OnHide", function(self)
        for i = #self.sparks, 1, -1 do
            local sp = self.sparks[i]
            sp.tex:Hide()
            self.sparks[i] = nil
            table.insert(self.sparkPool, sp)
        end
        for i = #self.live, 1, -1 do freeBubble(self, i) end
        self.spawn, self.spawnH, self.sparkT = 0, 0, 0
        self.flareT = nil
        for _, tx in ipairs(self.flareTex) do tx:SetAlpha(0) end
    end)
    buildProbes(f, R)
    R:Hide()
    f.rage = R
    return R
end

-- ── Hidden rage: flares ───────────────────────────────────────────────────
-- When the client hides rage, Lua can't tell when it crosses 15 or 60. Each
-- flare threshold gets a tiny invisible StatusBar fed the hidden percentage,
-- with a range a hair wide just under the threshold: its fill changes size
-- only as rage crosses it, and OnSizeChanged tells us that happened (but not
-- which way). The flare's opacity then comes from a step curve the client
-- evaluates, 0 below the threshold and 1 above, so a crossing on the way
-- down stays invisible. (The old version counted these events to estimate
-- the level, and drifted to "full" within a fight.)
local PROBE_W = 10
local FLARE_COOLDOWN = 3 -- seconds; swallows repeat events while rage hovers

-- (Thresholds are capped at 99%: reading the hidden value at exactly full
-- has failed before, which would swallow the 100% flare.)
local function flareX(at) return math.min(at, 99) / 100 end
local function stepCurve(at)
    local x = flareX(at)
    return { { 0, 0 }, { x - 0.006, 0 }, { x - 0.004, 1 }, { 1, 1 } }
end

function buildProbes(f, R)
    R.probes, R.probeEvents = {}, 0
    -- Their first layout also fires OnSizeChanged; ignore the first second.
    R.probesReady = false
    C_Timer.After(1, function() R.probesReady = true end)
    for _, at in ipairs(FLARE_AT) do
        local sb = CreateFrame("StatusBar", nil, f)
        sb:SetSize(PROBE_W, 1)
        sb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        sb:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
        sb:SetStatusBarColor(0, 0, 0, 0)
        sb:SetMinMaxValues(flareX(at) - 0.006, flareX(at) - 0.004)
        sb:SetValue(0)
        local p = { at = at, sb = sb, events = 0, last = -99 }
        local probe = CreateFrame("Frame", nil, sb)
        probe:SetPoint("TOPLEFT", sb, "TOPLEFT")
        probe:SetPoint("BOTTOMRIGHT", sb:GetStatusBarTexture(), "BOTTOMRIGHT")
        probe:SetScript("OnSizeChanged", function()
            if not (R.probesReady and R.secret and R.pctFn) then return end
            p.events = p.events + 1
            R.probeEvents = R.probeEvents + 1
            local now = GetTime()
            if now - p.last < FLARE_COOLDOWN then return end
            local curve = R.curves and R.curves["step" .. at]
            if not curve then return end
            -- Opacity 0 if this was a drop below the threshold.
            if not pcall(evalAlpha, R.flareFrame, R.pctFn, curve) then return end
            p.last = now
            R.flareT = 0
            R.spawnH = (R.spawnH or 0) + 10
        end)
        R.probes[#R.probes + 1] = p
    end
end

-- Feed the probes the hidden percentage (0..1).
local function feedProbes(R)
    if not (R.probes and R.pctFn and R.curves and R.curves.ident) then return end
    local ok, pct = pcall(R.pctFn, R.curves.ident)
    if not ok then return end
    for _, p in ipairs(R.probes) do p.sb:SetValue(pct) end
end

-- Drive the boil from this rage reading (plain numbers, or the curve path
-- when the client hides the value).
-- If a curve read fails (it did at exactly full rage), keep the layer's
-- last opacity instead of dropping to a fallback.
local function setCurveAlpha(R, frame, c, pctFn, fallback)
    if c and pctFn and pcall(evalAlpha, frame, pctFn, c) then
        frame.curveOK = true
    else
        R.curveFails = (R.curveFails or 0) + 1
        if not frame.curveOK then frame:SetAlpha(fallback) end
    end
end

local function rageFX(f, cur, max, pctFn, curves)
    local R = buildRage(f)
    local half = f.inner / 2
    R.pctFn, R.curves = pctFn, curves
    if not issecretvalue(cur) and not issecretvalue(max) then
        if R.secret then
            R.secret = false
            R.hotHolder:SetAlpha(1)
            R.boilHolder:SetAlpha(1)
            R.sparkHolder:SetAlpha(1)
        end
        R.flareFrame:SetAlpha(1)
        local pct = (max and max > 0) and math.min(1, cur / max) or 0
        if cur <= 0 then
            R.prev = 0
            R:Hide()
            return
        end
        R.k = pct
        R.surf = -half + f.inner * pct
        R:SetAlpha(1)
        local p100 = pct * 100 -- percent, so it holds if max rage isn't 100
        for _, at in ipairs(FLARE_AT) do
            if R.prev and R.prev < at and p100 >= at then
                R.flareT = 0
                R.spawn = R.spawn + 10 -- the flare kicks up a burst of bubbles
                if f.rageTest then ns:Print("Rage flare-up at " .. cur) end
                break
            end
        end
        R.prev = p100
    else
        -- Hidden value: the client fades each layer in from the curves
        -- (hot magma from 30%, fast boil from 50%, sparks from 50%); the
        -- bubbles rise to the real surface and vanish into the clip there.
        R.secret = true
        R.k = 0.3
        R.surf = half * 0.6
        feedProbes(R)
        setCurveAlpha(R, R, curves and curves.alpha, pctFn, 0.6)
        setCurveAlpha(R, R.hotHolder, curves and curves.hot, pctFn, 0)
        setCurveAlpha(R, R.boilHolder, curves and curves.boil, pctFn, 0)
        setCurveAlpha(R, R.sparkHolder, curves and curves.spark, pctFn, 0)
    end
    R:Show()
end

local function applyRage(f, cur, max, pctFn)
    f:SetTint(unpack(POWER[1]))
    f.line:SetColorTexture(1, 0.62, 0.25, 0.9)
    f.flashAnim:SetDuration(0.5)
    f.rimAnim:SetDuration(0.5)
    f.rim:Show()
    f.flash:SetColorTexture(1, 0.42, 0.15, 1)
    local cv = getCurves()
    if cv.rage == nil then
        cv.rage = { rgbCurves(RAGE_STOPS) or false, floatCurve(RAGE_FLASH) or false }
        local fx = {
            alpha = floatCurve(RAGE_ALPHA), hot = floatCurve(HOT_ALPHA), boil = floatCurve(BOIL_ALPHA),
            spark = floatCurve(SPARK_ALPHA), ident = floatCurve(IDENT),
        }
        for _, at in ipairs(FLARE_AT) do fx["step" .. at] = floatCurve(stepCurve(at)) end
        cv.rageFx = fx
    end
    colorByPercent(f, cur, max, RAGE_STOPS, RAGE_FLASH, cv.rage[1] or nil, cv.rage[2] or nil, pctFn)
    rageFX(f, cur, max, pctFn, cv.rageFx)
end

-- ── Energy: storm, splash, drips, ready arcs ─────────────────────────────
-- Storm: soft flashes blinking deep in the liquid, like lightning inside a
-- cloud, more often as it fills.
-- Splash: spending a big chunk flashes the surface and throws a few
-- droplets. Drips: the first spend from full leaves beads running down the
-- glass to the new surface. Arcs: once energy is (nearly) capped, a slow, gentle arc of
-- light crawls along the rim now and then, a "spend it" nudge.
-- With hidden energy the client's curves set each layer's opacity, and the
-- splash comes from the spell's energy cost (not from reading energy).
local FIZZ_ALPHA = { { 0.00, 0 }, { 0.10, 0.35 }, { 1.00, 1 } }
local ZAP_ALPHA = { { 0.00, 0 }, { 0.94, 0 }, { 0.95, 1 }, { 1.00, 1 } }
local ZAP_AT = 0.95
local MAX_FLASH, MAX_DROPS, MAX_DRIPS = 6, 8, 14
local FULL_ALPHA = { { 0.00, 0 }, { 0.985, 0 }, { 0.99, 1 }, { 1.00, 1 } }
local ZAP_ARCS, ZAP_SEGS = 2, 5
local SPLASH_MIN = 20     -- energy cost that earns a splash
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

local function buildEnergy(f)
    if f.energy then return f.energy end
    local inner, mask = f.inner, f.innerMask
    local half = inner / 2
    local fill = f.bar:GetStatusBarTexture()
    local E = CreateFrame("Frame", nil, f.bar)
    E:SetAllPoints(f.bar)
    E:SetFrameLevel(f.bar:GetFrameLevel() + 1)
    E.k, E.spawn = 0, 0

    -- Below the surface (clipped to the fill, like the rage boil).
    local clip = CreateFrame("Frame", nil, E)
    clip:SetPoint("TOPLEFT", fill, "TOPLEFT")
    clip:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
    clip:SetClipsChildren(true)
    -- Storm: soft flashes deep in the liquid, like lightning inside a cloud.
    E.fizzHolder = CreateFrame("Frame", nil, clip)
    E.fizzHolder:SetAllPoints(clip)
    E.live, E.pool = {}, {}
    -- Each flash: a broad glow that lights most of the liquid, plus a
    -- brighter core so it's clear where the strike was.
    for _ = 1, MAX_FLASH do
        local w = E.fizzHolder:CreateTexture(nil, "ARTWORK", nil, 2)
        w:SetTexture(SPOT)
        w:SetBlendMode("ADD")
        w:SetVertexColor(1, 0.93, 0.62)
        w:AddMaskTexture(mask)
        w:Hide()
        local t = E.fizzHolder:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetTexture(SPOT)
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.97, 0.80)
        t:AddMaskTexture(mask)
        t:Hide()
        table.insert(E.pool, { tex = t, wide = w })
    end

    -- Drips: after spending from full, beads form on the glass at the top
    -- and run down to the (now lower) surface. Their clip is the empty part
    -- of the orb, so they end exactly at the liquid, hidden value or not.
    local dclip = CreateFrame("Frame", nil, E)
    dclip:SetPoint("TOPLEFT", f.bar, "TOPLEFT")
    dclip:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT")
    dclip:SetClipsChildren(true)
    E.dripHolder = CreateFrame("Frame", nil, dclip)
    E.dripHolder:SetAllPoints(dclip)
    E.drips, E.dripPool = {}, {}
    -- Film: what's left clinging to the top of the glass, fading as it drains.
    E.film = E.dripHolder:CreateTexture(nil, "ARTWORK", nil, 2)
    E.film:SetTexture(SPOT)
    E.film:SetBlendMode("ADD")
    E.film:SetVertexColor(1, 0.88, 0.42)
    E.film:SetSize(inner * 1.05, inner * 0.42)
    E.film:SetPoint("CENTER", f.bar, "CENTER", 0, half * 0.97)
    E.film:AddMaskTexture(mask)
    E.film:SetAlpha(0)
    for _ = 1, MAX_DRIPS do
        local t = E.dripHolder:CreateTexture(nil, "ARTWORK", nil, 4)
        t:SetTexture(SPOT)
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.90, 0.45)
        t:AddMaskTexture(mask)
        t:Hide()
        -- The wet streak a drip leaves on the glass behind it.
        local tr = E.dripHolder:CreateTexture(nil, "ARTWORK", nil, 3)
        tr:SetColorTexture(1, 0.86, 0.40, 1)
        tr:SetBlendMode("ADD")
        tr:AddMaskTexture(mask)
        tr:Hide()
        table.insert(E.dripPool, { tex = t, trail = tr })
    end


    -- Splash: a flash riding the surface and droplets thrown out of it.
    local sp = CreateFrame("Frame", nil, f)
    sp:SetAllPoints(f)
    sp:SetFrameLevel(f.bar:GetFrameLevel() + 4)
    E.flash = sp:CreateTexture(nil, "OVERLAY", nil, 2)
    E.flash:SetTexture(SPOT)
    E.flash:SetBlendMode("ADD")
    E.flash:SetVertexColor(1, 0.97, 0.78)
    E.flash:SetPoint("CENTER", fill, "TOP", 0, 0)
    E.flash:AddMaskTexture(mask)
    E.flash:SetAlpha(0)
    E.drops, E.dropPool = {}, {}
    for _ = 1, MAX_DROPS do
        local t = sp:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetTexture(SPOT)
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.94, 0.62)
        t:AddMaskTexture(mask)
        t:Hide()
        table.insert(E.dropPool, { tex = t })
    end

    -- Arcs: a short chain of segments along the rim that fades in, crawls a
    -- little, and fades out; then a pause before the next one.
    local zap = CreateFrame("Frame", nil, f)
    zap:SetAllPoints(f)
    zap:SetFrameLevel(f.bar:GetFrameLevel() + 5)
    zap:SetAlpha(0)
    E.zap = zap
    E.arcs = {}
    for a = 1, ZAP_ARCS do
        local arc = { segs = {}, wait = 0.4 + a * 0.9, life = 0, age = 0, jit = {} }
        for s = 1, ZAP_SEGS do
            local l = zap:CreateLine(nil, "OVERLAY", nil, 6)
            l:SetColorTexture(1, 0.96, 0.74, 1)
            pcall(l.SetBlendMode, l, "ADD")
            l:SetThickness(1)
            l:Hide()
            arc.segs[s] = l
        end
        for s = 0, ZAP_SEGS do arc.jit[s] = 0 end
        E.arcs[a] = arc
    end
    local rimR = f:GetWidth() / 2 - 1

    local function placeArc(arc, alpha)
        local px, py
        for s = 0, ZAP_SEGS do
            local a = arc.a0 + arc.span * s / ZAP_SEGS
            local r = rimR + arc.jit[s]
            local x, y = math.cos(a) * r, math.sin(a) * r
            if s > 0 then
                local l = arc.segs[s]
                l:SetStartPoint("CENTER", f, px, py)
                l:SetEndPoint("CENTER", f, x, y)
                -- Brightest mid-arc, tapering to the ends.
                local mid = 1 - math.abs((s - 0.5) / ZAP_SEGS * 2 - 1)
                l:SetAlpha(alpha * (0.35 + 0.65 * mid))
                l:Show()
            end
            px, py = x, y
        end
    end
    local function jitter(arc)
        for s = 0, ZAP_SEGS do
            arc.jit[s] = (s == 0 or s == ZAP_SEGS) and 0 or (math.random() * 2 - 1) * 1.8
        end
    end
    local function hideArc(arc)
        for _, l in ipairs(arc.segs) do l:Hide() end
    end
    E.hideArcs = function()
        for _, arc in ipairs(E.arcs) do hideArc(arc); arc.life = 0 end
    end

    -- Spending from full: the liquid had been touching the top of the glass,
    -- so as it drains a film is left up there and drips keep forming along
    -- the top of the orb and running down for a second or two.
    function E:Drip()
        if #self.drips > 0 then return end
        self.filmT = 0
        local n = 5 + math.floor(math.random() * 3)
        for _ = 1, n do
            local d = table.remove(self.dripPool)
            if not d then break end
            -- Somewhere along the top arc, just inside the glass.
            local a = math.rad(50 + math.random() * 80)
            local r = half - 3
            d.x, d.y = math.cos(a) * r, math.sin(a) * r
            d.y0 = d.y
            d.vy, d.age = 0, 0
            d.delay = math.random() * 0.7       -- staggered, briefly
            d.hold = 0.08 + math.random() * 0.17 -- thin liquid: barely clings
            d.fall = 0.7
            d.s = 1.8 + math.random() * 1.1
            d.repeats = math.random() < 0.35 and 1 or 0 -- now and then a spot drips again
            d.tex:SetAlpha(0)
            d.trail:SetAlpha(0)
            d.tex:Hide()
            d.trail:Hide()
            table.insert(self.drips, d)
        end
    end

    function E:Splash(strength)
        if not self:IsShown() then return end
        self.flashT, self.flashS = 0, strength
        local n = math.floor(3 + 4 * strength)
        for _ = 1, n do
            local d = table.remove(self.dropPool)
            if not d then break end
            d.x, d.y = (math.random() * 2 - 1) * half * 0.45, 0
            d.vx = (math.random() - 0.5) * 50
            d.vy = (40 + 60 * strength) * (0.6 + 0.6 * math.random())
            d.age, d.life = 0, 0.45 + math.random() * 0.3
            d.s = 1.8 + math.random() * 1.6
            d.tex:Show()
            table.insert(self.drops, d)
        end
    end

    E:SetScript("OnUpdate", function(self, dt)
        if dt > 0.05 then dt = 0.05 end
        local k = self.secret and 0.7 or self.k
        local t = GetTime()

        -- Storm: now and then a soft glow blinks somewhere in the liquid,
        -- two or three quick pulses, sometimes answered by a second one
        -- nearby. y is measured from the surface (the fill's top edge), so
        -- they stay in the liquid (deeper ones are clipped at the bottom).
        self.spawn = self.spawn + dt * (0.35 + 0.65 * k) -- ~1 every 3s low, ~1/s full
        while self.spawn >= 1 do
            self.spawn = self.spawn - 1
            local b = table.remove(self.pool)
            if not b then self.spawn = 0; break end
            if self.lastX and math.random() < 0.25 then -- an echo near the last one
                b.x = self.lastX + (math.random() * 2 - 1) * 14
                b.y = math.min(-6, self.lastY + (math.random() * 2 - 1) * 12)
            else
                b.x = (math.random() * 2 - 1) * half * 0.6
                b.y = -inner * (0.08 + 0.7 * math.random())
            end
            self.lastX, self.lastY = b.x, b.y
            b.s = inner * (0.30 + 0.20 * math.random()) -- core: a larger spread
            b.age, b.life = 0, 0.35 + math.random() * 0.3 -- slower, softer blinks
            b.pulses = 1 + math.floor(math.random() * 2.2)
            b.a = 0.12 + 0.14 * math.random() -- faint: a glow, not a strobe
            b.tex:SetSize(b.s, b.s * (0.7 + 0.3 * math.random()))
            b.tex:ClearAllPoints()
            b.tex:SetPoint("CENTER", fill, "TOP", b.x, b.y)
            b.tex:SetAlpha(0)
            b.tex:Show()
            local ws = inner * (1.5 + 0.4 * math.random()) -- reaches across the orb
            b.wide:SetSize(ws, ws)
            b.wide:ClearAllPoints()
            b.wide:SetPoint("CENTER", fill, "TOP", b.x * 0.6, b.y * 0.8)
            b.wide:SetAlpha(0)
            b.wide:Show()
            table.insert(self.live, b)
        end
        local i = 1
        while i <= #self.live do
            local b = self.live[i]
            b.age = b.age + dt
            local p = b.age / b.life
            if p >= 1 then
                b.tex:Hide()
                b.wide:Hide()
                self.live[i] = self.live[#self.live]
                self.live[#self.live] = nil
                table.insert(self.pool, b)
            else
                -- Flicker: |sin| pulses under a fading envelope.
                local flick = math.abs(math.sin(p * math.pi * b.pulses))
                local a = b.a * flick * (1 - p * 0.6)
                b.tex:SetAlpha(a)
                b.wide:SetAlpha(a * 0.45)
                i = i + 1
            end
        end

        -- Film: bright where the liquid just left, fading over two seconds.
        if self.filmT then
            self.filmT = self.filmT + dt
            local p = self.filmT / 1.2
            if p >= 1 then
                self.filmT = nil
                self.film:SetAlpha(0)
            else
                self.film:SetAlpha(0.22 * (1 - p) * (1 - p))
            end
        end

        -- Drips: wait their turn, gather into a bead on the glass, then let
        -- go: slow at first (clinging), then faster, leaving a faint streak.
        -- The clip ends them exactly at the liquid's surface.
        local m = 1
        while m <= #self.drips do
            local d = self.drips[m]
            d.age = d.age + dt
            local t1 = d.age - d.delay
            if t1 >= d.hold + d.fall and d.repeats > 0 and d.age < 1.2 then
                -- Another drop gathers where this one left.
                d.repeats = d.repeats - 1
                d.delay = d.age + 0.08 + math.random() * 0.3
                d.y, d.vy = d.y0, 0
                d.hold = 0.06 + math.random() * 0.12
                d.s = d.s * 0.85
                d.tex:Hide()
                d.trail:Hide()
                m = m + 1
            elseif t1 >= d.hold + d.fall then
                d.tex:Hide()
                d.trail:Hide()
                self.drips[m] = self.drips[#self.drips]
                self.drips[#self.drips] = nil
                table.insert(self.dripPool, d)
            else
                if t1 >= 0 then
                    if not d.tex:IsShown() then d.tex:Show(); d.trail:Show() end
                    if t1 < d.hold then
                        local g = t1 / d.hold -- the bead swells
                        d.tex:SetSize(d.s * (0.6 + 0.4 * g), d.s * (0.6 + 0.7 * g))
                        d.tex:SetAlpha(0.5 * g)
                    else
                        d.vy = d.vy + (d.vy < 12 and 140 or 560) * dt
                        d.y = d.y - d.vy * dt
                        d.tex:SetSize(d.s * 0.7, d.s * (1.4 + d.vy * 0.03))
                        local q = (t1 - d.hold) / d.fall
                        d.tex:SetAlpha(0.5 * (1 - q * q))
                        local len = d.y0 - d.y
                        d.trail:ClearAllPoints()
                        d.trail:SetPoint("TOP", f.bar, "CENTER", d.x, d.y0)
                        d.trail:SetSize(1.1, math.max(1, len))
                        d.trail:SetAlpha(0.08 * (1 - q) * (1 - q))
                    end
                    d.tex:SetPoint("CENTER", f.bar, "CENTER", d.x, d.y)
                end
                m = m + 1
            end
        end

        -- Splash: surface flash and droplets arcing back into the liquid.
        if self.flashT then
            self.flashT = self.flashT + dt
            local p = self.flashT / 0.5
            if p >= 1 then
                self.flashT = nil
                self.flash:SetAlpha(0)
            else
                local s = self.flashS
                self.flash:SetSize(inner * (0.7 + 0.6 * p), 10 + 10 * s * (1 - p))
                self.flash:SetAlpha((0.5 + 0.4 * s) * (1 - p) * (1 - p))
            end
        end
        local j = 1
        while j <= #self.drops do
            local d = self.drops[j]
            d.age = d.age + dt
            local p = d.age / d.life
            if p >= 1 then
                d.tex:Hide()
                self.drops[j] = self.drops[#self.drops]
                self.drops[#self.drops] = nil
                table.insert(self.dropPool, d)
            else
                d.vy = d.vy - 260 * dt
                d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
                d.tex:SetSize(d.s, d.s)
                d.tex:SetAlpha(0.9 * (1 - p))
                d.tex:SetPoint("CENTER", fill, "TOP", d.x, d.y)
                j = j + 1
            end
        end

        -- Arcs: each one waits, fades in, crawls, fades out.
        if self.zapLive then
            for _, arc in ipairs(self.arcs) do
                if arc.life > 0 then
                    arc.age = arc.age + dt
                    local p = arc.age / arc.life
                    if p >= 1 then
                        hideArc(arc)
                        arc.life = 0
                        arc.wait = 0.8 + math.random() * 1.6
                    else
                        arc.a0 = arc.a0 + arc.drift * dt
                        arc.jt = arc.jt - dt
                        if arc.jt <= 0 then arc.jt = 0.14; jitter(arc) end
                        placeArc(arc, 0.8 * math.sin(p * math.pi))
                    end
                else
                    arc.wait = arc.wait - dt
                    if arc.wait <= 0 then
                        arc.a0 = math.random() * 6.283
                        arc.span = math.rad(18 + math.random() * 22)
                        arc.drift = (math.random() - 0.5) * 0.5
                        arc.age, arc.life, arc.jt = 0, 0.7 + math.random() * 0.6, 0
                    end
                end
            end
        end
    end)
    E:SetScript("OnHide", function(self)
        for n = #self.live, 1, -1 do
            local b = self.live[n]
            b.tex:Hide(); b.wide:Hide()
            self.live[n] = nil
            table.insert(self.pool, b)
        end
        for n = #self.drops, 1, -1 do
            local d = self.drops[n]
            d.tex:Hide()
            self.drops[n] = nil
            table.insert(self.dropPool, d)
        end
        self.filmT = nil
        self.film:SetAlpha(0)
        for n = #self.drips, 1, -1 do
            local d = self.drips[n]
            d.tex:Hide()
            d.trail:Hide()
            self.drips[n] = nil
            table.insert(self.dripPool, d)
        end
        self.flashT = nil
        self.flash:SetAlpha(0)
        self.hideArcs()
        self.zap:SetAlpha(0)
    end)

    -- Splash on spends: the spell's energy cost is plain data even when the
    -- energy itself is hidden.
    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:SetScript("OnEvent", function(_, _, _, _, spellID)
        if not (E:IsShown() and spellID and C_Spell and C_Spell.GetSpellPowerCost) then return end
        local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
        if not ok or type(costs) ~= "table" then return end
        for _, c in ipairs(costs) do
            local n = c.cost or c.minCost or 0
            if c.type == ENERGY and not issecretvalue(n) and n >= SPLASH_MIN then
                E:Splash(math.min(1, (n - SPLASH_MIN) / 40 + 0.3))
                -- Drips only on the first spend from full. The energy update
                -- may land just before or just after this cast, so look at
                -- the reading from before the latest update if it was recent.
                -- (At the cap no updates arrive, so "seen full a moment ago"
                -- never worked: the last reading could be minutes old.)
                local recent = E.updAt and GetTime() - E.updAt < 0.5
                local full -- (no and/or here: a hidden value can't be tested)
                if recent then full = E.fullBefore else full = E.fullNow end
                if issecretvalue(full) then
                    -- A hidden 0/1 the client evaluated; only SetAlpha can use it.
                    E.dripHolder:SetAlpha(full)
                    E:Drip()
                elseif type(full) == "number" and full >= 1 then
                    E.dripHolder:SetAlpha(1)
                    E:Drip()
                end
                return
            end
        end
    end)
    E:Hide()
    f.energy = E
    return E
end

local function energyFX(f, cur, max, pctFn)
    local E = buildEnergy(f)
    local cv = getCurves()
    if cv.energyFx == nil then
        cv.energyFx = { fizz = floatCurve(FIZZ_ALPHA) or false, zap = floatCurve(ZAP_ALPHA) or false,
                        full = floatCurve(FULL_ALPHA) or false }
    end
    E.pctFn, E.fullCurve = pctFn, cv.energyFx.full or nil
    -- "Was it full?" before and after this update (plain 0/1, or a hidden
    -- value from the client's curve), for the drips on the next spend.
    E.fullBefore = E.fullNow
    E.updAt = GetTime()
    if not issecretvalue(cur) and not issecretvalue(max) then
        E.fullNow = ((max and max > 0) and cur / max >= 0.99) and 1 or 0
    else
        local fc = cv.energyFx.full
        local ok, v = false, nil
        if fc and pctFn then ok, v = pcall(pctFn, fc) end
        if ok then E.fullNow = v else E.fullNow = nil end
    end
    if not issecretvalue(cur) and not issecretvalue(max) then
        E.secret = false
        local pct = (max and max > 0) and math.min(1, cur / max) or 0
        -- Preview / plain readings: a drop of a chunk splashes too.
        if E.prevPct and E.prevPct - pct >= SPLASH_MIN / 100 and E.fromPreview then
            E:Splash(math.min(1, (E.prevPct - pct - 0.2) / 0.4 + 0.3))
            if E.prevPct >= 0.99 then E.dripHolder:SetAlpha(1); E:Drip() end
        end
        E.prevPct = pct
        E.k = pct
        E.fizzHolder:SetAlpha(pct < 0.02 and 0 or 0.35 + 0.65 * pct)
        local live = pct >= ZAP_AT
        if E.zapLive and not live then E.hideArcs() end
        E.zapLive = live
        E.zap:SetAlpha(live and 1 or 0)
    else
        E.secret = true
        E.zapLive = true -- running always; the curve decides if it shows
        -- (A failed read keeps the last opacity: reads failed at exactly full.)
        setCurveAlpha(E, E.fizzHolder, cv.energyFx.fizz or nil, pctFn, 0.6)
        setCurveAlpha(E, E.zap, cv.energyFx.zap or nil, pctFn, 0)
    end
    E:Show()
end

-- ── Clear glass above the liquid (all orbs) ─────────────────────────────────
-- The drifting streaks normally show through the empty part of the orb too.
-- With on = true the empty part is nearly clear glass: the back streaks drop
-- to a tenth of their strength and the front streaks are clipped to the
-- liquid (which keeps its full movement).
local function setClearGlass(f, on)
    if f.clearGlass == on then return end
    f.clearGlass = on
    if not f.swirlClip then
        local clip = CreateFrame("Frame", nil, f.bar)
        clip:SetPoint("TOPLEFT", f.bar:GetStatusBarTexture(), "TOPLEFT")
        clip:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
        clip:SetClipsChildren(true)
        -- The streaks go on a child frame of the clip: clipping reliably
        -- applies to child frames (reparenting the texture onto the clip
        -- frame itself left it unclipped).
        local holder = CreateFrame("Frame", nil, clip)
        holder:SetAllPoints(f.bar)
        f.swirlClip = holder
    end
    -- (Through the vertex alpha: SetTint rewrites it on every update, and a
    -- plain SetAlpha on this texture didn't take.)
    f.swirlBackA = on and 0.02 or 0.20
    if f.tintR then
        f.swirlBack:SetVertexColor(f.tintR * 0.5 + 0.4, f.tintG * 0.5 + 0.4, f.tintB * 0.5 + 0.4, f.swirlBackA)
    end
    f.swirlTop:SetParent(on and f.swirlClip or f.bar)
    f.swirlTop:SetDrawLayer("OVERLAY", -2)
end

-- ── Mana: prism motes + caustics ──────────────────────────────────────────
-- Motes: a few tiny sparkles suspended in the liquid, drifting slowly. Each
-- is three soft dots (red, green, blue) that sit on top of each other as a
-- pale blue-white point; when one twinkles they split apart like light
-- through a prism. More motes the fuller you are.
-- Caustics: slow, wavering light patterns in the liquid, like sunlight
-- through a pool: two streak layers drifting against each other.
-- Everything is clipped to the liquid. With hidden mana the client's curve
-- sets the motes' opacity.
local MOTE_ALPHA = { { 0.00, 0 }, { 0.05, 0.3 }, { 1.00, 1 } }
-- Pill visibility with hidden mana: on until (nearly) full. The cut sits a
-- little under 100% because reads at exactly full have failed before.
local NOT_FULL = { { 0.00, 1 }, { 0.978, 1 }, { 0.985, 0 }, { 1.00, 0 } }
local MAX_MOTES = 16
local PRISM = { { 1.00, 0.35, 0.45 }, { 0.40, 1.00, 0.55 }, { 0.45, 0.60, 1.00 } }
local BURST_SPARKS = 22

-- Pastel color from a hue (0..1 around the wheel).
local function hueRGB(h)
    h = (h % 1) * 6
    local i6 = math.floor(h)
    local u = h - i6
    local q = 1 - u
    local r, g, b
    if i6 == 0 then r, g, b = 1, u, 0
    elseif i6 == 1 then r, g, b = q, 1, 0
    elseif i6 == 2 then r, g, b = 0, 1, u
    elseif i6 == 3 then r, g, b = 0, q, 1
    elseif i6 == 4 then r, g, b = u, 0, 1
    else r, g, b = 1, 0, q end
    return 0.35 + 0.65 * r, 0.35 + 0.65 * g, 0.35 + 0.65 * b
end

local function buildMana(f)
    if f.mana then return f.mana end
    local inner, mask = f.inner, f.innerMask
    local half = inner / 2
    local fill = f.bar:GetStatusBarTexture()
    local M = CreateFrame("Frame", nil, f.bar)
    M:SetAllPoints(f.bar)
    M:SetFrameLevel(f.bar:GetFrameLevel() + 1)
    M.k, M.t, M.surf = 0, 0, half

    -- Liquid only: a clip at the surface, with child holders (clipping is
    -- reliable for child frames).
    local clip = CreateFrame("Frame", nil, M)
    clip:SetPoint("TOPLEFT", fill, "TOPLEFT")
    clip:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
    clip:SetClipsChildren(true)

    M.causticHolder = CreateFrame("Frame", nil, clip)
    M.causticHolder:SetAllPoints(f.bar)
    local function caustic(sub, r, g, b)
        local t = M.causticHolder:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetAllPoints(f.bar)
        t:SetTexture(SWIRL, "REPEAT", "REPEAT")
        t:SetBlendMode("ADD")
        t:SetVertexColor(r, g, b, 1)
        t:AddMaskTexture(mask)
        return t
    end
    M.c1 = caustic(1, 0.55, 0.78, 1.00)
    M.c2 = caustic(2, 0.62, 0.88, 1.00)

    -- Mana regen on the value pill under the orb:
    --   cast that costs mana -> the pill's color fades and it fills again
    --     from empty over the five-second rule, a soft pulse each second;
    --   five seconds over     -> it stays full (translucent) and keeps
    --     pulsing once a second while mana regenerates;
    --   mana full             -> the color fades out.
    -- The caustics surge briefly when regen resumes.
    local chip = f.chip
    local holder = CreateFrame("Frame", nil, chip)
    holder:SetAllPoints(chip)
    holder:SetFrameLevel(chip:GetFrameLevel() + 1)
    M.pillHolder = holder -- hidden mana: the client's "not full" curve
    local top = CreateFrame("Frame", nil, chip)
    top:SetAllPoints(chip)
    top:SetFrameLevel(chip:GetFrameLevel() + 2)
    f.chipRing:SetParent(top) -- keep the ring and the number above the fill
    f.text:SetParent(top)
    local function pillTex(sub)
        local t = holder:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetVertexColor(0.42, 0.62, 1.00, 0)
        t:AddMaskTexture(f.chipMask)
        return t
    end
    M.pillFill = pillTex(2)
    M.pillFill:SetPoint("TOPLEFT", chip, "TOPLEFT")
    M.pillFill:SetPoint("BOTTOMLEFT", chip, "BOTTOMLEFT")
    M.pillFill:SetWidth(1)
    -- The previous full pill, fading out when a cast interrupts regen.
    M.pillGhost = pillTex(1)
    M.pillGhost:SetAllPoints(chip)
    -- A soft glow riding the fill's leading edge (brightens on each pulse).
    M.pillEdge = holder:CreateTexture(nil, "ARTWORK", nil, 3)
    M.pillEdge:SetTexture(SPOT)
    M.pillEdge:SetBlendMode("ADD")
    M.pillEdge:SetSize(22, chip:GetHeight() * 1.6)
    M.pillEdge:SetPoint("CENTER", M.pillFill, "RIGHT")
    M.pillEdge:AddMaskTexture(f.chipMask)
    M.pillEdge:SetVertexColor(0.70, 0.86, 1.00, 0)
    M.pillW = chip:GetWidth()

    -- Hidden mana: a step curve on the holder would snap the color off the
    -- instant mana tops off. Instead a tiny invisible StatusBar spanning
    -- 97.5-98% is fed the hidden percentage; its fill changes size only when
    -- mana crosses that line, and that event starts the normal 0.5s fade.
    -- (It doesn't say which way it crossed: a cast in the same moment means
    -- mana went down, and the cast restarts the fill anyway.)
    local probe = CreateFrame("StatusBar", nil, M)
    probe:SetSize(10, 1)
    probe:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    probe:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
    probe:SetStatusBarColor(0, 0, 0, 0)
    probe:SetMinMaxValues(0.975, 0.98)
    probe:SetValue(0)
    M.fullProbe = probe
    local watch = CreateFrame("Frame", nil, probe)
    watch:SetPoint("TOPLEFT", probe, "TOPLEFT")
    watch:SetPoint("BOTTOMRIGHT", probe:GetStatusBarTexture(), "BOTTOMRIGHT")
    M.probeReady = false
    C_Timer.After(1, function() M.probeReady = true end)
    watch:SetScript("OnSizeChanged", function()
        if not (M.secret and M.probeReady) then return end
        M.probeSeen = true
        M.pillHolder:SetAlpha(1) -- from now on the probe decides
        if M.fsrEnd or (M.castAt and GetTime() - M.castAt < 0.6) then return end
        M.full = true
    end)
    -- Level pin: the orb's fill eases down after a cast, and when mana is
    -- hidden we can't read where it's going. A second, invisible StatusBar
    -- with the same geometry is fed the same values with no easing, so it
    -- jumps straight to the new level; the mist is placed relative to its
    -- top edge (the true waterline) and stays put while the fill catches up.
    -- Its size change also tells us the moment mana has dropped.
    local lv = CreateFrame("StatusBar", nil, M)
    lv:SetAllPoints(f.bar)
    lv:SetOrientation("VERTICAL")
    lv:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
    lv:SetStatusBarColor(0, 0, 0, 0)
    lv:SetMinMaxValues(0, 1)
    lv:SetValue(1)
    M.levelBar = lv
    local pin = CreateFrame("Frame", nil, lv)
    pin:SetPoint("TOPLEFT", f.bar, "TOPLEFT")
    pin:SetPoint("BOTTOMRIGHT", lv:GetStatusBarTexture(), "TOPRIGHT")
    pin:SetScript("OnSizeChanged", function() M.levelMoved = true end)
    M.pin = pin
    M.pillA = 0       -- the pill's current base opacity
    M.ghostA = 0

    function M:StartFSR()
        if not self:IsShown() then return end
        -- Whatever was showing fades out; the new fill starts from empty.
        if self.pillA > 0.01 then
            self.ghostA = self.pillA
            self.pillGhost:SetVertexColor(0.42, 0.62, 1.00, self.ghostA * 0.30)
        end
        self.pillA = 0
        self.full = false
        self.castAt = GetTime()
        self.fsrEnd = GetTime() + 5
        self.fsrDoneT = nil
    end

    -- Eddies: now and then a slow prismatic vortex turns somewhere in the
    -- liquid and fades away. Each disc (an outer one and a smaller one
    -- turning the other way) is drawn three times in colors a third of the
    -- way apart around the color wheel, each copy turned and nudged a little
    -- differently: where they overlap they add up to a pale glow, and along
    -- the streaks they fan out into rainbow fringes. The colors drift around
    -- the wheel as it turns.
    M.eddyHolder = CreateFrame("Frame", nil, clip)
    M.eddyHolder:SetAllPoints(f.bar)
    M.eddies, M.eddyPool = {}, {}
    for _ = 1, 2 do
        local e = { layers = {} }
        for disc = 1, 2 do
            for c = 1, 3 do
                local t = M.eddyHolder:CreateTexture(nil, "ARTWORK", nil, 3)
                t:SetTexture(SWIRL)
                t:SetBlendMode("ADD")
                t:AddMaskTexture(mask)
                local soft = M.eddyHolder:CreateMaskTexture()
                soft:SetTexture(SPOT, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                soft:SetAllPoints(t)
                t:AddMaskTexture(soft)
                t:SetVertexColor(1, 1, 1, 0)
                table.insert(e.layers, { tex = t, disc = disc, c = c })
            end
        end
        table.insert(M.eddyPool, e)
    end
    M.eddyT = 2 + math.random() * 3

    local function spawnEddy(self)
        local e = table.remove(self.eddyPool)
        if not e then return end
        local top = self.secret and half * 0.5 or self.surf - 14
        if top < -half + 20 then table.insert(self.eddyPool, e); return end
        e.x = (math.random() * 2 - 1) * half * 0.45
        e.y = -half + 18 + (top - (-half + 18)) * math.random()
        e.s = inner * (0.30 + 0.16 * math.random())
        e.age, e.life = 0, 8 + math.random() * 4
        -- The current: the liquid turns slowly around the orb's middle, with a
        -- little meander, and the eddy rides it.
        e.flow = (math.random() < 0.5 and -1 or 1) * (0.10 + math.random() * 0.06) -- rad/s
        e.mp, e.mf = math.random() * 6.283, 0.3 + math.random() * 0.3
        e.rot = math.random() * 6.283
        e.spin = (math.random() < 0.5 and -1 or 1) * (0.5 + math.random() * 0.4) -- rad/s: slow
        e.hue = math.random()
        e.a = 0.13 + 0.06 * math.random()
        e.axis = math.random() * 6.283
        table.insert(self.eddies, e)
    end
    M.SpawnEddy = spawnEddy

    -- Cast: the mana the spell used turns straight to mist. The slice it
    -- filled (just above the new surface) bursts into prismatic wisps that
    -- start white-hot and fade to color as they swirl up and cloud the
    -- empty glass. Wisps live in fixed orb coordinates, so they don't ride
    -- the waterline down. The motes in the remaining mana get blasted.
    -- Whole-orb flash: the glass lights up all at once, white with a
    -- shimmer of color through it, and dies away fast. A soft radial glow
    -- bigger than the orb, so it's even across it with no edge of its own.
    local fl = CreateFrame("Frame", nil, M)
    fl:SetAllPoints(f.bar)
    fl:SetFrameLevel(f.bar:GetFrameLevel() + 4)
    M.flashTex = {}
    for c = 1, 3 do
        local t = fl:CreateTexture(nil, "ARTWORK", nil, 4)
        t:SetTexture(SPOT)
        t:SetBlendMode("ADD")
        t:AddMaskTexture(mask)
        t:SetSize(inner * 2.2, inner * 2.2)
        t:SetPoint("CENTER", f.bar, "CENTER", (c - 2) * 2, 0)
        t:SetVertexColor(1, 1, 1, 0)
        M.flashTex[c] = t
    end

    local emb = CreateFrame("Frame", nil, M)
    emb:SetAllPoints(f.bar)
    emb:SetFrameLevel(f.bar:GetFrameLevel() + 5)
    M.bSparks, M.bPool = {}, {}
    for _ = 1, BURST_SPARKS do
        local t = emb:CreateTexture(nil, "ARTWORK", nil, 6)
        t:SetTexture(SWIRL)
        t:SetBlendMode("ADD")
        t:AddMaskTexture(mask)
        local sm = emb:CreateMaskTexture()
        sm:SetTexture(SPOT, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        sm:SetAllPoints(t)
        t:AddMaskTexture(sm)
        t:SetVertexColor(1, 1, 1, 0)
        t:Hide()
        table.insert(M.bPool, { tex = t })
    end

    -- Where the liquid's surface is, relative to the orb's center.
    local function liquidTop(self)
        if not self.secret then return self.surf end
        local ok, top = pcall(fill.GetTop, fill)
        local ok2, _, cy = pcall(f.bar.GetCenter, f.bar)
        if ok and ok2 and type(top) == "number" and type(cy) == "number"
            and not issecretvalue(top) and not issecretvalue(cy) then
            return top - cy
        end
        return half * 0.2
    end

    -- share: fraction of max mana spent; strength 0..1 for the extras.
    function M:Burst(strength, share)
        if not self:IsShown() then return end
        share = share or 0.08
        local h = math.max(6, inner * math.min(share, 0.6))
        self.burnH, self.burnS, self.burnT = h, strength, 0
        self.burnHue = math.random()
        self.flashT = 0
        self.levelMoved = false
        self.disturb = math.max(self.disturb, strength * 0.6)
        -- The burn blasts the motes away from it: a hard shove, scattered a
        -- little off-line, curling as it slows so they spiral back into
        -- the slow drift.
        local push = 90 + 110 * strength
        local sx, sy = 0, liquidTop(self)
        for _, m in ipairs(self.motes) do
            local dx, dy = m.x - sx, m.y - sy
            local d = math.max(6, math.sqrt(dx * dx + dy * dy))
            local a = math.atan2(dy, dx) + (math.random() - 0.5) * 1.2
            local v = push * (0.6 + 0.6 * math.random()) * math.max(0.35, 1 - d / (inner * 1.2))
            m.ix, m.iy = math.cos(a) * v, math.sin(a) * v
            m.curl = (math.random() < 0.5 and -1 or 1) * (1.2 + math.random() * 1.2)
            m.kick = 1
        end
        for _, e in ipairs(self.eddies) do
            e.ix = (e.ix or 0) + (e.x >= 0 and 1 or -1) * push * 0.3
            e.iy = (e.iy or 0) - push * 0.25
        end
        self.emberQ = math.floor(12 + 10 * strength) -- mist wisps, released at once
        self.emberAcc = 0
    end

    M.disturb, M.ct = 0, 0

    M.moteHolder = CreateFrame("Frame", nil, clip)
    M.moteHolder:SetAllPoints(f.bar)
    M.motes, M.pool = {}, {}
    for _ = 1, MAX_MOTES do
        local m = { dots = {} }
        for c = 1, 3 do
            local t = M.moteHolder:CreateTexture(nil, "ARTWORK", nil, 4)
            t:SetTexture(SPOT)
            t:SetBlendMode("ADD")
            t:SetVertexColor(PRISM[c][1], PRISM[c][2], PRISM[c][3])
            t:AddMaskTexture(mask)
            t:Hide()
            m.dots[c] = t
        end
        table.insert(M.pool, m)
    end

    local function spawnMote(self)
        local m = table.remove(self.pool)
        if not m then return end
        -- Fixed in the orb (not riding the surface): when mana drops they
        -- stay put, and any left above the new waterline are clipped away.
        -- Plain mana: start below the surface; hidden: anywhere.
        local top = self.secret and half or self.surf
        if top < -half + 6 then top = -half + 6 end
        m.x = (math.random() * 2 - 1) * half * 0.75
        m.y = -half + 4 + (top - 4 - (-half + 4)) * math.random()
        m.vx = (math.random() - 0.5) * 6
        m.vy = (math.random() - 0.35) * 5 -- a slight upward lean
        m.age, m.life = 0, 3 + math.random() * 3
        m.s = 1.6 + math.random() * 1.6
        m.a = 0.22 + 0.25 * math.random()
        m.tw, m.tp = 0.2 + math.random() * 0.4, math.random() * 6.28 -- slow twinkles
        m.dir = math.random() * 6.283 -- the axis the colors split along
        for c = 1, 3 do m.dots[c]:SetAlpha(0); m.dots[c]:Show() end
        table.insert(self.motes, m)
    end

    M:SetScript("OnUpdate", function(self, dt)
        if dt > 0.05 then dt = 0.05 end
        local t = self.t + dt
        self.t = t
        local k = self.secret and 0.8 or self.k

        -- Caustics: two layers at different scales drifting against each
        -- other, breathing slowly. Faint.
        -- Disturbance from a cast burst decays over ~1.5s.
        local dist = self.disturb
        if dist > 0 then
            dist = math.max(0, dist - dt * 0.7)
            self.disturb = dist
        end
        -- Caustics run on their own clock, which races while disturbed.
        self.ct = self.ct + dt * (1 + 5 * dist)
        local ct = self.ct
        local wob = 0.03 * dist * math.sin(t * 9)
        local u1, v1 = 0.05 * math.sin(ct * 0.21) + wob, ct * 0.018
        local u2, v2 = 0.4 - ct * 0.013 - wob, 0.2 + 0.05 * math.sin(ct * 0.17 + 1)
        self.c1:SetTexCoord(u1, u1 + 0.75, v1, v1 + 0.75)
        self.c2:SetTexCoord(u2, u2 + 0.45, v2, v2 + 0.45)
        local breathe = 0.85 + 0.15 * math.sin(t * 0.7)
        -- (Vertex alpha: a plain SetAlpha on the swirl texture didn't take.)
        -- Pill: five-second fill, then hold and pulse while regenerating,
        -- fade when full. Pulses: a soft swell at each whole second.
        local now = GetTime()
        local surge = 0
        local width, pulse, target
        if self.fsrEnd then
            local left = self.fsrEnd - now
            if left <= 0 then
                self.fsrEnd = nil
                self.fsrDoneT = 0
                self.regenFrom = now
            else
                local el = 5 - left
                local since = el - math.floor(el)
                pulse = (el >= 1) and math.max(0, 1 - since / 0.45) or 0
                width = self.pillW * el / 5
                target = 1
            end
        end
        if not self.fsrEnd then
            width = self.pillW
            if self.full then
                target = 0
                pulse = 0
            else
                self.regenFrom = self.regenFrom or now
                local since = (now - self.regenFrom) % 1
                pulse = math.max(0, 1 - since / 0.45)
                target = 1
            end
        end
        pulse = pulse * pulse
        -- Ease the base opacity toward its target (fade out over ~0.6s).
        local a = self.pillA
        if a < target then a = math.min(target, a + dt * 4) elseif a > target then a = math.max(target, a - dt * 2) end -- 0.5s fade
        self.pillA = a
        self.pillFill:SetWidth(math.max(1, width))
        self.pillFill:SetVertexColor(0.42, 0.62, 1.00, a * (0.30 + 0.18 * pulse))
        self.pillEdge:SetVertexColor(0.70, 0.86, 1.00, self.fsrEnd and a * (0.25 + 0.55 * pulse) or 0)
        if self.ghostA > 0 then
            self.ghostA = math.max(0, self.ghostA - dt * 1.2)
            self.pillGhost:SetVertexColor(0.42, 0.62, 1.00, self.ghostA * 0.30)
        end
        -- Caustics surge as regen resumes.
        if self.fsrDoneT then
            self.fsrDoneT = self.fsrDoneT + dt
            local q = self.fsrDoneT / 1.1
            if q >= 1 then
                self.fsrDoneT = nil
            else
                surge = q < 0.12 and q / 0.12 or (1 - (q - 0.12) / 0.88) ^ 2
            end
        end

        self.c1:SetVertexColor(0.55, 0.78, 1.00, (0.10 + 0.08 * k) * breathe + 0.12 * surge)
        self.c2:SetVertexColor(0.62, 0.88, 1.00, (0.08 + 0.08 * k) * (1.85 - breathe) + 0.10 * surge)

        -- Eddies: one every 6-12s, at most two at a time.
        self.eddyT = self.eddyT - dt
        if self.eddyT <= 0 then
            self.eddyT = 6 + math.random() * 6
            spawnEddy(self)
        end
        local ei = 1
        while ei <= #self.eddies do
            local e = self.eddies[ei]
            e.age = e.age + dt
            local p = e.age / e.life
            if p >= 1 then
                for _, l in ipairs(e.layers) do l.tex:SetVertexColor(1, 1, 1, 0) end
                self.eddies[ei] = self.eddies[#self.eddies]
                self.eddies[#self.eddies] = nil
                table.insert(self.eddyPool, e)
            else
                -- Forms over the first fifth, then slowly spreads out and
                -- thins away: it grows, its spin winds down, and its colors
                -- fan further apart as it dissipates.
                local env = p < 0.2 and (p / 0.2) or (1 - (p - 0.2) / 0.8)
                env = env * env * (3 - 2 * env) -- smooth
                e.rot = e.rot + e.spin * dt * (1 - 0.7 * p + 4 * dist)
                e.hue = e.hue + dt * 0.05          -- colors drift round the wheel
                e.axis = e.axis + dt * 0.2
                local sc = 1 + 0.7 * p * p
                local split = 1.5 + 4 * p + 5 * dist
                -- Ride the current: swing around the orb's middle, meander.
                local ca, sa = math.cos(e.flow * dt), math.sin(e.flow * dt)
                e.x, e.y = e.x * ca - e.y * sa, e.x * sa + e.y * ca
                e.x = e.x + math.sin(e.age * e.mf + e.mp) * 3 * dt
                e.y = e.y + (math.cos(e.age * e.mf * 0.8 + e.mp) * 2 + 0.8) * dt
                if e.ix then
                    e.x, e.y = e.x + e.ix * dt, e.y + e.iy * dt
                    local damp = math.exp(-2.2 * dt)
                    e.ix, e.iy = e.ix * damp, e.iy * damp
                end
                local ax, ay = math.cos(e.axis), math.sin(e.axis)
                for _, l in ipairs(e.layers) do
                    local o = l.c - 2 -- -1, 0, 1
                    local size = (l.disc == 1 and 1 or 0.55) * e.s * sc * (1 + 0.04 * o)
                    local t = l.tex
                    t:SetSize(size, size)
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", f.bar, "CENTER", e.x + ax * split * o, e.y + ay * split * o)
                    local r = l.disc == 1 and e.rot or -e.rot * 1.7
                    t:SetRotation(r + 0.10 * o)
                    -- Hue a third of the wheel apart per copy; soft pastels.
                    local h = (e.hue + (l.c - 1) / 3) % 1 * 6
                    local i6 = math.floor(h)
                    local fr = h - i6
                    local q, u = 1 - fr, fr
                    local cr, cg, cb
                    if i6 == 0 then cr, cg, cb = 1, u, 0
                    elseif i6 == 1 then cr, cg, cb = q, 1, 0
                    elseif i6 == 2 then cr, cg, cb = 0, 1, u
                    elseif i6 == 3 then cr, cg, cb = 0, q, 1
                    elseif i6 == 4 then cr, cg, cb = u, 0, 1
                    else cr, cg, cb = 1, 0, q end
                    cr, cg, cb = 0.35 + 0.65 * cr, 0.35 + 0.65 * cg, 0.35 + 0.65 * cb
                    t:SetVertexColor(cr, cg, cb, e.a * env * (l.disc == 1 and 1 or 0.8))
                end
                ei = ei + 1
            end
        end

        -- Whole-orb flash: up in a blink, gone in ~0.3s; each of the three
        -- copies carries a different hue that bleaches toward white at the
        -- peak, so the tail of the flash is a faint rainbow shimmer.
        if self.flashT then
            self.flashT = self.flashT + dt
            local T = self.flashT
            if T >= 0.4 then
                self.flashT = nil
                for _, t in ipairs(self.flashTex) do t:SetVertexColor(1, 1, 1, 0) end
            else
                local a = (T < 0.03 and T / 0.03 or math.exp(-(T - 0.03) * 11))
                    * (0.10 + 0.10 * self.burnS)
                local w = math.exp(-T * 14) -- white at the peak, color after
                for c, t in ipairs(self.flashTex) do
                    local r, g, b = hueRGB(self.burnHue + (c - 1) / 3 + T)
                    t:SetVertexColor(r + (1 - r) * w, g + (1 - g) * w, b + (1 - b) * w, a)
                end
            end
        end
        -- Cast: spawn the mist (a beat after the cast, so the level has
        -- dropped and the wisps fill the space it left).
        if self.burnT then
            self.burnT = self.burnT + dt
            local T = self.burnT
            if T >= 0.45 then
                self.burnT = nil
            elseif T >= 0.02 and (self.levelMoved or T >= 0.2) then
                -- All the wisps at once, across the vacated slice.
                if self.emberQ and self.emberQ > 0 then
                    self.emberAcc = self.emberAcc + dt * 250
                    while self.emberAcc >= 1 and self.emberQ > 0 do
                        self.emberAcc = self.emberAcc - 1
                        self.emberQ = self.emberQ - 1
                        local sp = table.remove(self.bPool)
                        if not sp then break end
                        -- Relative to the waterline (the pin's bottom edge).
                        sp.x = (math.random() * 2 - 1) * half * 0.55
                        sp.y = self.burnH * (0.1 + 0.9 * math.random())
                        sp.vx, sp.vy = (math.random() - 0.5) * 14, 8 + math.random() * 12
                        sp.age, sp.life = 0, 2.6 + math.random() * 1.4
                        sp.s0 = 14 + math.min(self.burnH, 28) * (0.6 + 0.4 * math.random())
                        sp.s1 = sp.s0 * (2.6 + math.random())
                        sp.rot = math.random() * 6.283
                        sp.spin = (math.random() < 0.5 and -1 or 1) * (0.4 + math.random() * 0.6)
                        sp.sw, sp.ph = 0.8 + math.random() * 0.8, math.random() * 6.283
                        sp.a = 0.08 + 0.06 * self.burnS
                        sp.r, sp.g, sp.b = hueRGB(self.burnHue + math.random())
                        sp.tex:SetVertexColor(sp.r, sp.g, sp.b, 0)
                        sp.tex:Show()
                        table.insert(self.bSparks, sp)
                    end
                end
            end
        end
        local bi = 1
        while bi <= #self.bSparks do
            local sp = self.bSparks[bi]
            sp.age = sp.age + dt
            local q = sp.age / sp.life
            if q >= 1 then
                sp.tex:Hide()
                self.bSparks[bi] = self.bSparks[#self.bSparks]
                self.bSparks[#self.bSparks] = nil
                table.insert(self.bPool, sp)
            else
                -- Rises and slows, swells, turns, thins away.
                local damp = math.exp(-0.7 * dt)
                sp.vx, sp.vy = sp.vx * damp, sp.vy * damp
                -- Swirl: a lazy side-to-side loop as it rises.
                local sw = math.sin(sp.age * sp.sw + sp.ph)
                sp.x = sp.x + (sp.vx + sw * 10) * dt
                sp.y = sp.y + (sp.vy + math.cos(sp.age * sp.sw + sp.ph) * 4) * dt
                sp.rot = sp.rot + sp.spin * dt
                local e = 1 - (1 - q) * (1 - q)
                local size = sp.s0 + (sp.s1 - sp.s0) * e
                sp.tex:SetSize(size, size * 0.8)
                sp.tex:SetRotation(sp.rot)
                local hot = math.exp(-sp.age * 9)
                local env = (1 - q) ^ 1.4 * (1 + 2.5 * hot)
                sp.tex:SetVertexColor(sp.r + (1 - sp.r) * hot, sp.g + (1 - sp.g) * hot,
                    sp.b + (1 - sp.b) * hot, sp.a * env)
                sp.tex:ClearAllPoints()
                sp.tex:SetPoint("CENTER", self.pin, "BOTTOM", sp.x, sp.y)
                bi = bi + 1
            end
        end

        -- Keep a population that grows with mana.
        local want = math.floor(4 + (MAX_MOTES - 4) * k)
        if #self.motes < want then
            self.spawnT = (self.spawnT or 0) + dt
            if self.spawnT > 0.25 then self.spawnT = 0; spawnMote(self) end
        end
        local i = 1
        while i <= #self.motes do
            local m = self.motes[i]
            m.age = m.age + dt
            local p = m.age / m.life
            if p >= 1 then
                for c = 1, 3 do m.dots[c]:Hide() end
                self.motes[i] = self.motes[#self.motes]
                self.motes[#self.motes] = nil
                table.insert(self.pool, m)
            else
                m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
                if m.ix then
                    -- Curl the shove so it spirals out into the drift.
                    if m.curl then
                        local ca, sa = math.cos(m.curl * dt), math.sin(m.curl * dt)
                        m.ix, m.iy = m.ix * ca - m.iy * sa, m.ix * sa + m.iy * ca
                    end
                    m.x, m.y = m.x + m.ix * dt, m.y + m.iy * dt
                    local damp = math.exp(-1.8 * dt)
                    m.ix, m.iy = m.ix * damp, m.iy * damp
                    -- Glance off the glass and the surface.
                    local r = math.sqrt(m.x * m.x + m.y * m.y)
                    local lim = half * 0.85
                    if r > lim then
                        local nx, ny = m.x / r, m.y / r
                        m.x, m.y = nx * lim, ny * lim
                        local dot = m.ix * nx + m.iy * ny
                        if dot > 0 then m.ix, m.iy = m.ix - 1.6 * dot * nx, m.iy - 1.6 * dot * ny end
                    end
                    if not self.secret and m.y > self.surf - 3 then
                        m.y = self.surf - 3
                        if m.iy > 0 then m.iy = -m.iy * 0.6 end
                    end
                    if m.ix * m.ix + m.iy * m.iy < 1 then m.ix, m.curl = nil, nil end
                end
                m.dir = m.dir + dt * 0.25
                local env = math.min(1, p * 5, (1 - p) * 4)
                local tw = math.sin(m.age * m.tw * 6.28 + m.tp)
                local spark = tw > 0.6 and (tw - 0.6) / 0.4 or 0 -- 0..1, eased in and out
                spark = spark * spark
                -- Split: the three colors drift apart along the mote's axis.
                local d = 0.2 + 1.4 * spark
                local ox, oy = math.cos(m.dir) * d, math.sin(m.dir) * d
                if m.ix then
                    local sp2 = math.sqrt(m.ix * m.ix + m.iy * m.iy)
                    local st = math.min(4, sp2 * 0.03)
                    ox, oy = ox + m.ix / sp2 * st, oy + m.iy / sp2 * st
                end
                local size = m.s * (1 + 0.25 * spark)
                local a = m.a * env * (0.75 + 0.25 * tw + 0.35 * spark)
                for c = 1, 3 do
                    local dot = m.dots[c]
                    local o = c - 2 -- -1, 0, 1
                    dot:SetSize(size, size)
                    dot:SetAlpha(a)
                    dot:SetPoint("CENTER", f.bar, "CENTER", m.x + ox * o, m.y + oy * o)
                end
                i = i + 1
            end
        end
    end)
    M:SetScript("OnHide", function(self)
        self.fsrEnd, self.fsrDoneT = nil, nil
        self.pillA, self.ghostA, self.regenFrom = 0, 0, nil
        self.burnT, self.disturb, self.emberQ = nil, 0, nil
        for _, m in ipairs(self.motes) do m.ix, m.curl = nil, nil end
        self.flashT = nil
        for _, t in ipairs(self.flashTex) do t:SetVertexColor(1, 1, 1, 0) end
        for n = #self.bSparks, 1, -1 do
            local sp = self.bSparks[n]
            sp.tex:Hide()
            self.bSparks[n] = nil
            table.insert(self.bPool, sp)
        end
        for n = #self.eddies, 1, -1 do
            local e = self.eddies[n]
            for _, l in ipairs(e.layers) do l.tex:SetVertexColor(1, 1, 1, 0) end
            self.eddies[n] = nil
            table.insert(self.eddyPool, e)
        end
        self.pillFill:SetVertexColor(0.42, 0.62, 1.00, 0)
        self.pillGhost:SetVertexColor(0.42, 0.62, 1.00, 0)
        self.pillFill:SetVertexColor(0.42, 0.62, 1.00, 0)
        self.pillEdge:SetVertexColor(0.70, 0.86, 1.00, 0)
        for n = #self.motes, 1, -1 do
            local m = self.motes[n]
            for c = 1, 3 do m.dots[c]:Hide() end
            self.motes[n] = nil
            table.insert(self.pool, m)
        end
    end)
    -- Casts that cost mana start the five-second count (cost is plain data
    -- even when mana itself is hidden).
    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:SetScript("OnEvent", function(_, _, _, _, spellID)
        if not (M:IsShown() and spellID and C_Spell and C_Spell.GetSpellPowerCost) then return end
        local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
        if not ok or type(costs) ~= "table" then return end
        for _, c in ipairs(costs) do
            local n = c.cost or c.minCost or 0
            if c.type == 0 and not issecretvalue(n) and n > 0 then
                M:StartFSR()
                -- Burst sized by the share of max mana spent (a 10% spell is
                -- a solid burst, 20%+ is the biggest).
                local share = 0.08
                local okM, mx = pcall(UnitPowerMax, "player", 0)
                if okM and mx and not issecretvalue(mx) and mx > 0 then share = n / mx end
                M:Burst(math.min(1, 0.2 + share * 4), share)
                return
            end
        end
    end)
    M:Hide()
    f.mana = M
    return M
end

local function manaFX(f, cur, max, pctFn)
    local M = buildMana(f)
    local cv = getCurves()
    if cv.manaFx == nil then
        cv.manaFx = { motes = floatCurve(MOTE_ALPHA) or false, notFull = floatCurve(NOT_FULL) or false,
                      ident = floatCurve(IDENT) or false }
    end
    pcall(M.levelBar.SetMinMaxValues, M.levelBar, 0, max)
    pcall(M.levelBar.SetValue, M.levelBar, cur)
    if not issecretvalue(cur) and not issecretvalue(max) then
        M.secret = false
        local pct = (max and max > 0) and math.min(1, cur / max) or 0
        M.k = pct
        M.surf = -f.inner / 2 + f.inner * pct
        M.full = pct >= 0.999
        M.pillHolder:SetAlpha(1)
        M.moteHolder:SetAlpha(pct < 0.02 and 0 or 0.3 + 0.7 * pct)
    else
        M.secret = true
        setCurveAlpha(M, M.moteHolder, cv.manaFx.motes or nil, pctFn, 0.6)
        -- Feed the full-line probe the hidden percentage.
        local id = cv.manaFx.ident
        if id and pctFn then
            local ok, v = pcall(pctFn, id)
            if ok then M.fullProbe:SetValue(v) end
        end
        -- Until the probe has fired once (right after login we can't know
        -- if mana is full), fall back to the step curve.
        if not M.probeSeen then
            setCurveAlpha(M, M.pillHolder, cv.manaFx.notFull or nil, pctFn, 1)
        end
    end
    M:Show()
end

-- Percent evaluators, made once (not per update).
local healthPct = UnitHealthPercent and function(curve) return UnitHealthPercent("player", true, curve) end
local powerPctFns = {}
local function powerPct(ptype)
    local fn = powerPctFns[ptype]
    if not fn and UnitPowerPercent then
        fn = function(curve) return UnitPowerPercent("player", ptype, false, curve) end
        powerPctFns[ptype] = fn
    end
    return fn
end

local function updateHealth(f)
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    f.bar:SetMinMaxValues(0, max)
    setValue(f.bar, cur)
    setText(f.text, cur)
    local c = getCurves()
    colorByPercent(f, cur, max, HEALTH_STOPS, HEALTH_FLASH, c.healthColor, c.healthFlash,
        healthPct)
end

local function updatePower(f)
    if f.rageTest then return end -- /mui rage preview running
    local ptype = UnitPowerType("player")
    local cur, max = UnitPower("player", ptype), UnitPowerMax("player", ptype)
    f.bar:SetMinMaxValues(0, max)
    setValue(f.bar, cur)
    setText(f.text, cur)
    if f.energy and ptype ~= 3 then f.energy:Hide() end
    if f.mana and ptype ~= 0 then f.mana:Hide() end
    if ptype == 1 then
        return applyRage(f, cur, max,
            powerPct(ptype))
    end
    if f.rage then f.rage:Hide() end
    local c = POWER[ptype]
    if not c and PowerBarColor and PowerBarColor[ptype] then
        local i = PowerBarColor[ptype]
        c = { i.r, i.g, i.b }
    end
    if c then f:SetTint(c[1], c[2], c[3]) end
    if ptype == 0 then
        -- Mana: quiet color drift + faint slow pulse when low.
        f.flashAnim:SetDuration(0.9)
        f.rimAnim:SetDuration(0.9)
        f.rim:Hide()
        f.flash:SetColorTexture(0.45, 0.60, 1, 1) -- (druids switch power types)
        local cv = getCurves()
        colorByPercent(f, cur, max, MANA_STOPS, MANA_FLASH, cv.manaColor, cv.manaFlash,
            powerPct(ptype))
        manaFX(f, cur, max, powerPct(ptype))
    elseif c then
        -- Builders (rage, runic power...): color heats up as it fills and the
        -- orb glows warm near full. Regenerating resources (energy, focus):
        -- steady color with a soft "ready" pulse when (nearly) full.
        local fx = POWER_FX[ptype] or POWER_FX.builder
        f.flashAnim:SetDuration(fx.dur)
        f.rimAnim:SetDuration(fx.dur)
        f.rim:Show()
        f.flash:SetColorTexture(fx.flashColor[1], fx.flashColor[2], fx.flashColor[3], 1)
        local key = "fx" .. tostring(ptype)
        local cv = getCurves()
        if cv[key] == nil then
            local st = fx.stops(c)
            cv[key] = { rgbCurves(st) or false, floatCurve(fx.flash) or false, st }
        end
        local stops = cv[key][3]
        colorByPercent(f, cur, max, stops, fx.flash, cv[key][1] or nil, cv[key][2] or nil,
            powerPct(ptype))
        if ptype == 3 then energyFX(f, cur, max, powerPct(ptype)) end
    else
        f.flashHolder:SetAlpha(0)
    end
end

-- /mui rage : preview the rage boil on the power orb (any class). Rage
-- arrives in chunks to 100, holds, then drains like it does out of combat.
ns.commands.rage = function(rest)
    local f = ns.modules.Orbs.power
    if not f then return end
    if rest == "flare" then
        -- Fire just the flare-up and report what it actually drew.
        local R = buildRage(f)
        if not R:IsShown() then R.k, R.surf = 0.3, -f.inner / 2 + f.inner * 0.3; R:Show() end
        R.flareT = 0
        C_Timer.After(FLARE_DUR + 0.1, function()
            if UnitPowerType("player") ~= 1 and not f.rageTest then R:Hide() end
        end)
        C_Timer.After(0.1, function()
            local b = R.burst
            local w, h = b:GetSize()
            ns:Print(string.format("flare: t=%s burst a=%.2f %dx%d vis=%s  R vis=%s  orb vis=%s strata=%s lvl=%d",
                tostring(R.flareT and string.format("%.2f", R.flareT)), b:GetAlpha(), w or 0, h or 0,
                tostring(b:IsVisible()), tostring(R:IsVisible()), tostring(f:IsVisible()),
                tostring(b:GetParent():GetFrameStrata()), b:GetParent():GetFrameLevel()))
        end)
        return
    end
    if f.rageTest then return end
    f.rageTest = true
    if f.rage then f.rage.prev = 0 end
    local t0 = GetTime()
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        local e = GetTime() - t0
        local v
        if e < 9 then v = math.floor(e / 9 * 100 / 6) * 6
        elseif e < 12 then v = 100
        elseif e < 18 then v = 100 - (e - 12) / 6 * 100
        else v = 0 end
        v = math.max(0, math.min(100, v))
        f.bar:SetMinMaxValues(0, 100)
        setValue(f.bar, v)
        setText(f.text, v)
        applyRage(f, v, 100)
        if e >= 18.5 then
            ticker:Cancel()
            f.rageTest = nil
            updatePower(f)
        end
    end)
    ns:Print("Rage preview: building to 100, then draining (about 18s).")
end

-- /mui energy : preview energy on the power orb (any class): refills to
-- full, crackles while capped, spends in chunks, refills.
ns.commands.energy = function(rest)
    local f = ns.modules.Orbs.power
    if rest == "drip" and f then
        local E = buildEnergy(f)
        E:Show()
        E.dripHolder:SetAlpha(1)
        E:Drip()
        ns:Print("Drips: " .. #E.drips .. " spawned (energy hidden=" .. tostring(E.secret) .. ").")
        return
    end
    if not f or f.rageTest then return end
    f.rageTest = true -- blocks live updates (shared with the rage preview)
    if f.rage then f.rage:Hide() end
    local c = POWER[3]
    f:SetTint(c[1], c[2], c[3])
    local t0 = GetTime()
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        local e = GetTime() - t0
        local v
        if e < 5 then v = 20 + e / 5 * 80
        elseif e < 9 then v = 100            -- capped: crackle
        elseif e < 9.5 then v = 65           -- a finisher
        elseif e < 10 then v = 30
        elseif e < 14 then v = 30 + (e - 10) / 4 * 70
        else v = 100 end
        v = math.max(0, math.min(100, v))
        f.bar:SetMinMaxValues(0, 100)
        setValue(f.bar, v)
        setText(f.text, v)
        if f.energy then f.energy.fromPreview = true end
        energyFX(f, v, 100)
        if e >= 16 then
            ticker:Cancel()
            f.rageTest = nil
            if f.energy then f.energy.fromPreview = nil end
            updatePower(f)
        end
    end)
    ns:Print("Energy preview (about 16s).")
end

-- /mui mana : preview mana on the power orb (any class): drains, then
-- refills (motes thin out and fill back in).
ns.commands.mana = function(rest)
    local f = ns.modules.Orbs.power
    if rest == "burst" and f and f.mana then
        if not f.mana:IsShown() then return ns:Print("Mana effects only run while the orb shows mana.") end
        f.mana:Burst(0.8, 0.18)
        return
    end
    if rest == "fsr" and f and f.mana then
        if not f.mana:IsShown() then return ns:Print("Mana effects only run while the orb shows mana.") end
        f.mana:StartFSR()
        return ns:Print("Five-second rule preview.")
    end
    if not f or f.rageTest then return end
    f.rageTest = true -- blocks live updates (shared with the other previews)
    if f.rage then f.rage:Hide() end
    if f.energy then f.energy:Hide() end
    f:SetTint(unpack(POWER[0]))
    local t0 = GetTime()
    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        local e = GetTime() - t0
        local v
        if e < 8 then v = 100 - e / 8 * 85 else v = 15 + (e - 8) / 6 * 85 end
        v = math.max(0, math.min(100, v))
        f.bar:SetMinMaxValues(0, 100)
        setValue(f.bar, v)
        setText(f.text, v)
        local cv = getCurves()
        colorByPercent(f, v, 100, MANA_STOPS, MANA_FLASH, cv.manaColor, cv.manaFlash)
        manaFX(f, v, 100)
        if e >= 14.5 then
            ticker:Cancel()
            f.rageTest = nil
            updatePower(f)
        end
    end)
    C_Timer.After(1, function() if f.mana then f.mana:StartFSR() end end)
    C_Timer.After(0.5, function() if f.mana then f.mana:SpawnEddy() end end)
    C_Timer.After(6, function() if f.mana then f.mana:SpawnEddy() end end)
    C_Timer.After(2.5, function() if f.mana then f.mana:Burst(0.4, 0.06) end end)
    C_Timer.After(7.5, function() if f.mana then f.mana:Burst(1, 0.22) end end)
    ns:Print("Mana preview (about 15s).")
end

-- /mui orbcolor : which path the orb colors use on this client.
ns.commands.orbcolor = function()
    local O = ns.modules.Orbs
    if not O.health then return end
    ns:Print("health color:", tostring(O.health.colorPath), " power color:", tostring(O.power.colorPath),
        " curves:", tostring(getCurves().healthColor ~= nil))
    local P = O.power
    ns:Print(string.format("glass: clear=%s  back streaks alpha=%.2f  front streaks clipped=%s",
        tostring(P.clearGlass), P.swirlBack:GetAlpha(), tostring(P.swirlTop:GetParent() == P.swirlClip)))
    local R = O.power.rage
    if R then
        local ev = {}
        for _, p in ipairs(R.probes or {}) do ev[#ev + 1] = p.at .. ":" .. p.events end
        ns:Print("rage: hidden=" .. tostring(R.secret) .. "  flare probe events " .. table.concat(ev, " ")
            .. "  curve fails " .. tostring(R.curveFails or 0))
    end
end

local function place(f, pos)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", pos.x, pos.y)
end

-- ── Combo points ──────────────────────────────────────────────────────────
-- Little orbs (same glass as the big ones) in an arc over the power orb.
-- Each pip is its own StatusBar spanning one point (i-1 .. i) and all of them
-- get the same value, so the engine fills exactly the earned pips, even if
-- the count is ever hidden from addons. Shown for rogues and cat-form
-- druids (anyone on energy who has combo points).
local PIP = 24          -- pip diameter
local PIP_MAX = 7       -- talents can raise the cap past 5
local PIP_STEP = 17     -- degrees between pips along the arc
local PIP_GAP = 16      -- arc distance outside the power orb's edge
local COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local PIP_STOPS = {     -- warm gold for the first point, deep red for the finisher
    { 1.00, 0.78, 0.30 }, { 1.00, 0.62, 0.22 }, { 0.98, 0.46, 0.16 },
    { 0.94, 0.32, 0.13 }, { 0.86, 0.18, 0.12 }, { 0.80, 0.12, 0.14 }, { 0.74, 0.08, 0.16 },
}

local function buildPip(holder, i)
    local p = CreateFrame("Frame", nil, holder)
    p:SetSize(PIP, PIP)
    local ring = p:CreateTexture(nil, "BACKGROUND", nil, 0)
    ring:SetAllPoints()
    ring:SetColorTexture(unpack(T.border))
    ring:AddMaskTexture(newMask(p, PIP))
    local track = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    track:SetPoint("CENTER")
    track:SetSize(PIP - 2, PIP - 2)
    track:SetColorTexture(0.12, 0.12, 0.13, 0.92) -- lighter than the big orbs: they read as part of the HUD, not holes
    track:AddMaskTexture(newMask(p, PIP - 2))
    local inner = PIP - 6
    local mask = newMask(p, inner)
    local bg = p:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetPoint("CENTER")
    bg:SetSize(inner, inner)
    bg:SetColorTexture(0.09, 0.085, 0.07, 1) -- empty pip: a faint warm glass, not black
    bg:AddMaskTexture(mask)

    local c = PIP_STOPS[i]
    local bar = CreateFrame("StatusBar", nil, p)
    bar:SetPoint("CENTER")
    bar:SetSize(inner, inner)
    bar:SetOrientation("VERTICAL")
    bar:SetStatusBarTexture(T.bar)
    bar:SetStatusBarColor(c[1], c[2], c[3])
    bar:SetMinMaxValues(i - 1, i)
    bar:SetValue(0)
    local fill = bar:GetStatusBarTexture()
    fill:AddMaskTexture(mask)
    local function over(sub)
        local t = bar:CreateTexture(nil, "OVERLAY", nil, sub)
        t:SetAllPoints(bar)
        t:AddMaskTexture(mask)
        return t
    end
    local depth = over(1)
    depth:SetColorTexture(0, 0, 0, 1)
    pcall(depth.SetGradient, depth, "VERTICAL", CreateColor(0, 0, 0, 0.30), CreateColor(0, 0, 0, 0))
    local gloss = over(3)
    gloss:SetTexture(MEDIA .. "orb_glare.tga")

    -- Pop when the point lands: a hot flash in the pip, a soft burst around it.
    local fx = CreateFrame("Frame", nil, p)
    fx:SetAllPoints(p)
    fx:SetFrameLevel(bar:GetFrameLevel() + 2)
    local hot = fx:CreateTexture(nil, "OVERLAY", nil, 0)
    hot:SetAllPoints(bar)
    hot:SetColorTexture(1, 0.92, 0.70, 1)
    hot:SetBlendMode("ADD")
    hot:AddMaskTexture(mask)
    hot:SetAlpha(0)
    local burst = fx:CreateTexture(nil, "OVERLAY", nil, 1)
    burst:SetTexture(MEDIA .. "spot.tga")
    burst:SetBlendMode("ADD")
    burst:SetVertexColor(c[1], c[2] * 0.9 + 0.1, c[3] * 0.8 + 0.1)
    burst:SetPoint("CENTER")
    burst:SetAlpha(0)
    fx:Hide()
    fx:SetScript("OnUpdate", function(self, dt)
        self.t = self.t + dt
        local q = self.t / 0.4
        if q >= 1 then
            hot:SetAlpha(0); burst:SetAlpha(0)
            self:Hide()
            return
        end
        local a = (1 - q) * (1 - q)
        hot:SetAlpha(0.85 * a)
        local s = PIP * (1.2 + 1.4 * q)
        burst:SetSize(s, s)
        burst:SetAlpha(0.75 * a)
    end)
    function p:Pop()
        fx.t = 0
        fx:Show()
    end
    p.bar = bar
    return p
end

local function layoutCombo(C, max)
    C.max = max
    local first = 90 + (max - 1) * PIP_STEP / 2 -- point 1 on the left
    for i = 1, PIP_MAX do
        local p = C.pips[i]
        if i <= max then
            local a = math.rad(first - (i - 1) * PIP_STEP)
            p:ClearAllPoints()
            p:SetPoint("CENTER", C, "CENTER", math.cos(a) * C.radius, math.sin(a) * C.radius)
            p:Show()
        else
            p:Hide()
        end
    end
end

local function comboMax()
    local ok, m = pcall(UnitPowerMax, "player", COMBO)
    if not ok or m == nil or issecretvalue(m) or m <= 0 then return 5 end
    return math.min(m, PIP_MAX)
end

local function updateCombo(C)
    if C.preview then return end
    local _, class = UnitClass("player")
    local want = class == "ROGUE" or (class == "DRUID" and UnitPowerType("player") == 3)
    C:SetShown(want and Orbs.power:IsShown())
    if not want then return end
    local max = comboMax()
    if max ~= C.max then layoutCombo(C, max) end
    local cur = UnitPower("player", COMBO)
    for i = 1, max do setValue(C.pips[i].bar, cur) end
    if not issecretvalue(cur) then
        local prev = C.prev or 0
        for i = prev + 1, math.min(cur, max) do C.pips[i]:Pop() end
        C.prev = cur
    end
end

local function buildCombo(O)
    local C = CreateFrame("Frame", "MinimalUI_ComboPoints", UIParent)
    C:SetAllPoints(O.power) -- moves with the power orb
    C:SetFrameStrata(O.power:GetFrameStrata())
    C:SetFrameLevel(O.power:GetFrameLevel() + 8)
    C.radius = O.power:GetWidth() / 2 + PIP_GAP
    C.pips = {}
    for i = 1, PIP_MAX do C.pips[i] = buildPip(C, i) end
    layoutCombo(C, 5)
    C:Hide()
    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function() updateCombo(C) end)
    for _, e in ipairs({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        ev:RegisterUnitEvent(e, "player")
    end
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED") -- older rules keep points on the target
    hooksecurefunc(O.power, "Show", function() updateCombo(C) end)
    hooksecurefunc(O.power, "Hide", function() C:Hide() end)
    O.combo = C
    updateCombo(C)
end

-- /mui combo : preview the combo pips on any class (fills to 5, spends, ends).
ns.commands.combo = function()
    local C = Orbs.combo
    if not C then return end
    C.preview = true
    layoutCombo(C, 5)
    C:Show()
    local steps = { 1, 2, 3, 4, 5, 5, 0, 1, 2, 0 }
    local prev = 0
    for n, v in ipairs(steps) do
        C_Timer.After(n * 0.7, function()
            for i = 1, 5 do setValue(C.pips[i].bar, v) end
            for i = prev + 1, v do C.pips[i]:Pop() end
            prev = v
        end)
    end
    C_Timer.After(#steps * 0.7 + 1, function()
        C.preview = false
        C.prev = nil
        updateCombo(C)
    end)
    ns:Print("Combo point preview (about 8s).")
end

function Orbs:OnInit(db)
    self.db = db
    self.health = createOrb("MinimalUI_HealthOrb", db.size)
    self.power = createOrb("MinimalUI_PowerOrb", db.size)
    self.health:SetTint(unpack(HEALTH))
    -- Health's surface line stays neutral as the fill shifts color.
    self.health.line:SetColorTexture(1, 1, 1, 0.75)
    -- Pulse tints: warm red for health, cool blue for mana.
    self.health.flash:SetColorTexture(1, 0.30, 0.25, 1)
    self.power.flash:SetColorTexture(0.45, 0.60, 1, 1)
    place(self.health, db.health)
    place(self.power, db.power)
    -- Every orb: nearly clear glass above the liquid.
    setClearGlass(self.health, true)
    setClearGlass(self.power, true)

    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, event)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            updateHealth(self.health)
        elseif event == "PLAYER_ENTERING_WORLD" then
            updateHealth(self.health); updatePower(self.power)
        else
            updatePower(self.power)
        end
    end)
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do ev:RegisterUnitEvent(e, "player") end
    for _, e in ipairs({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        ev:RegisterUnitEvent(e, "player")
    end
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    updateHealth(self.health)
    updatePower(self.power)
    buildCombo(self)
end

-- ── Show/hide and movement ────────────────────────────────────────────────
ns.commands.orbs = function()
    if InCombatLockdown() then return ns:Print("Can't toggle orbs in combat.") end
    local show = not Orbs.health:IsShown()
    Orbs.health:SetShown(show)
    Orbs.power:SetShown(show)
    ns:Print("Orbs", show and "shown" or "hidden")
end

local overlays = {}
local function makeOverlay(key, frame)
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
    label:SetText(key .. " orb")
    o:SetScript("OnDragStart", function()
        ns:SnapDragStart(frame)
    end)
    o:SetScript("OnDragStop", function()
        ns:SnapDragStop()
        if InCombatLockdown() then return end
        local fx = frame:GetCenter()
        local ux = UIParent:GetCenter()
        local pos = Orbs.db[key]
        pos.x = math.floor(fx - ux + 0.5)
        pos.y = math.floor(frame:GetBottom() + 0.5)
        place(frame, pos)
    end)
    o:Hide()
    return o
end

function Orbs:SetLocked(locked)
    for key, frame in pairs({ health = self.health, power = self.power }) do
        ns:RegisterSnapTarget(frame)
        overlays[key] = overlays[key] or makeOverlay(key, frame)
        frame:SetMovable(true)
        overlays[key]:SetShown(not locked and frame:IsShown())
    end
end

-- Piggyback on the existing /mui unlock | lock | reset commands.
local baseUnlock, baseLock, baseReset = ns.commands.unlock, ns.commands.lock, ns.commands.reset
ns.commands.unlock = function(...)
    if baseUnlock then baseUnlock(...) end
    if not InCombatLockdown() and Orbs.health then Orbs:SetLocked(false) end
end
ns.commands.lock = function(...)
    if baseLock then baseLock(...) end
    if Orbs.health then Orbs:SetLocked(true) end
end
ns.commands.reset = function(...)
    if baseReset then baseReset(...) end
    if InCombatLockdown() or not Orbs.health then return end
    for key, pos in pairs(DEFAULT) do
        Orbs.db[key].x, Orbs.db[key].y = pos.x, pos.y
        place(Orbs[key], Orbs.db[key])
    end
end
