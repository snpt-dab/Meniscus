local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Thin XP pill along the bottom, spanning either the orbs or the bar 2/3 blocks.
-- Rested XP shows as a lighter band ahead of the fill. Hover for details.
-- Replaces Blizzard's status tracking bars (hidden on load).

local XP = ns:NewModule("XP", { enabled = true, span = "bars" }) -- "orbs" | "bars"

local HEIGHT = 6
local GAP = 14 -- below the orbs/blocks; clears the orbs' glow halo (10 below the ring)
local XP_COLOR = { 0.56, 0.44, 0.96 }
-- Rested: blue like the default UI; purple otherwise. A palette tints the
-- fill, the rested band, the gain ghost and the gain flash. The amber trail
-- stays amber (it's the contrast color).
local PALETTES = {
    normal = { fill = XP_COLOR, ghost = { 0.80, 0.74, 1.00, 0.55 },
               flash = { 0.85, 0.80, 1 }, bloom = { 0.72, 0.62, 1 }, burst = { 0.92, 0.88, 1 } },
    rested = { fill = { 0.26, 0.56, 1.00 }, ghost = { 0.72, 0.84, 1.00, 0.55 },
               flash = { 0.80, 0.90, 1 }, bloom = { 0.55, 0.74, 1 }, burst = { 0.88, 0.94, 1 } },
}

-- Blizzard's tracking bars must keep their parent: Edit Mode calls layout
-- methods on it (reparenting them broke Edit Mode). So they stay in place,
-- fully transparent, with the mouse disabled so they can't steal hover from
-- our XP pill.
-- Running alpha animations (e.g. a fade-in on show) override SetAlpha until
-- they finish, which showed as a brief flash on load. Stop them.
local function stopAg(...)
    for i = 1, select("#", ...) do
        local ag = select(i, ...)
        if ag:IsPlaying() then ag:Stop() end
    end
end
local function stopAnims(obj)
    if obj.GetAnimationGroups then stopAg(obj:GetAnimationGroups()) end
end

-- (Runs twice a second for good: walks with reusable buffers, no tables.)
local function quiet(f, depth)
    depth = depth or 0
    stopAnims(f)
    local regs, nr = ns.Regs(f, depth)
    for i = 1, nr do stopAnims(regs[i]) end
    f:SetAlpha(0)
    if f.EnableMouse and not (f.IsProtected and f:IsProtected() and InCombatLockdown()) then
        pcall(f.EnableMouse, f, false)
    end
    local kids, nk = ns.Kids(f, depth)
    for i = 1, nk do quiet(kids[i], depth + 1) end
end

local TRACKING = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local function hideBlizzardTracking()
    for _, name in ipairs(TRACKING) do
        local f = _G[name]
        if f then pcall(quiet, f, 0) end
    end
end

-- Hide as early as possible: Blizzard's bars already exist while addon files load.
pcall(hideBlizzardTracking)

function XP:Anchor()
    local p = self.pill
    if not p then return end
    local O, B = ns.modules.Orbs, ns.modules.Bars
    local left, right
    if self.db.span == "bars" and B and B.block2 and B.block3 then
        left, right = B.block2, B.block3
    elseif O and O.health and O.power then
        left, right = O.health, O.power
    end
    p:ClearAllPoints()
    if left then
        p:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -GAP)
        p:SetPoint("TOPRIGHT", right, "BOTTOMRIGHT", 0, -GAP)
        p:SetHeight(HEIGHT)
    else
        p:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 10)
        p:SetSize(768, HEIGHT)
    end
end

local function readXP()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local rest = GetXPExhaustion()
    return cur, max, rest
end

local function plain(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if issecretvalue(v) then return false end
    end
    return true
end

-- Watched reputation: name, standing id, min, max, value (or nil).
local function readRep()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local ok, d = pcall(C_Reputation.GetWatchedFactionData)
        if ok and d and d.name then
            return d.name, d.reaction, d.currentReactionThreshold or 0,
                d.nextReactionThreshold or 1, d.currentStanding or 0
        end
    end
    if GetWatchedFactionInfo then
        local name, standing, min, max, value = GetWatchedFactionInfo()
        if name then return name, standing, min, max, value end
    end
end

local function repColor(standing)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing]
    if c then return c.r, c.g, c.b end
    return 0.35, 0.75, 0.45
end

local function isMaxed()
    local maxed = IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()
    if maxed == nil and GetMaxPlayerLevel then maxed = UnitLevel("player") >= GetMaxPlayerLevel() end
    return maxed and not issecretvalue(maxed)
end

-- ── XP gain animation ─────────────────────────────────────────────────────
-- On a gain: the pill flashes, the gained stretch appears at once as a pale
-- "ghost" band, and after a beat the purple fill eases up to meet it. A
-- level-up fills to the end first, then starts over from zero.
-- Sequence: flash + ghost band together; flash fades out (FLASH); a pause
-- (WAIT); then the fill eases in-out (slow, fast through the middle, slow
-- into the end) over FILL. Later level-up phases start without the wait.
local FLASH, WAIT, FILL = 0.6, 0.5, 1.5
local HOLD = FLASH + WAIT
local GAIN_COLOR = { 0.80, 0.74, 1.00, 0.55 }
local MEDIA = "Interface/AddOns/Meniscus/Media/"

-- Prismatic light (as on the level-up card): each light of the gain flash
-- is three copies, red, green and blue, added together. They start pulled
-- a few pixels apart (colour fringes) and close up into the palette's
-- tint as the flash fades. A group stands in for a single texture:
-- SetAlpha / SetVertexColor / SetSize / SetHeight / ClearAllPoints /
-- SetPoint apply to all three, and Spread(px) sets how far apart they are.
local PRISM = { { 1.00, 0.12, 0.22 }, { 0.15, 1.00, 0.35 }, { 0.22, 0.38, 1.00 } }
local PULL = { -1, 0, 1 }
local PRISM_A = 0.72 -- the three added together are brighter than one
local Prism = {}
Prism.__index = Prism
local function prismGroup(make)
    local g = setmetatable({ n = 0, pts = {}, spread = 0 }, Prism)
    for i = 1, 3 do g[i] = make(i) end
    return g
end
function Prism:SetAlpha(a) for i = 1, 3 do self[i]:SetAlpha(a * PRISM_A) end end
function Prism:SetVertexColor(r, g, b)
    for i = 1, 3 do
        local c = PRISM[i]
        self[i]:SetVertexColor(r * c[1], g * c[2], b * c[3], 1)
    end
end
function Prism:SetSize(w, h) for i = 1, 3 do self[i]:SetSize(w, h) end end
function Prism:SetHeight(h) for i = 1, 3 do self[i]:SetHeight(h) end end
function Prism:ClearAllPoints() self.n = 0 end
function Prism:SetPoint(point, rel, relPoint, x, y)
    local n = self.n + 1
    self.n = n
    local pt = self.pts[n] or {}
    self.pts[n] = pt
    pt[1], pt[2], pt[3], pt[4], pt[5] = point, rel, relPoint, x or 0, y or 0
    self:Place()
end
function Prism:Place()
    for i = 1, 3 do
        local t, dx = self[i], PULL[i] * self.spread
        t:ClearAllPoints()
        for k = 1, self.n do
            local pt = self.pts[k]
            t:SetPoint(pt[1], pt[2], pt[3], pt[4] + dx, pt[5])
        end
    end
end
function Prism:Spread(px)
    if px == self.spread then return end
    self.spread = px
    self:Place()
end
local phases, phase, pt, ft = {}, nil, 0, nil
local power = 1 -- flash strength for the current gain, 0.35..1

-- Trail: the stretch you just earned, in a contrasting color. It fills with
-- the bar, stays for LINGER seconds so a missed gain can still be read, then
-- fades away left to right over SWEEP. Gains that land while a trail is
-- still showing extend it, so it always covers everything not yet seen.
local LINGER, SWEEP, EDGE = 5, 3, 36
local TRAIL_COLOR = { 1.00, 0.80, 0.38 }
local trail -- { left, max, stage = "fill" | "linger" | "sweep", t, left0, right }

local function hideTrail(self)
    trail = nil
    if self.trailMain then self.trailMain:Hide(); self.trailEdge:Hide() end
end

-- Draw the trail over [left, right] (bar units). The left end always
-- tapers: a gradient that starts a little inside the purple and ramps up,
-- so the amber grows out of the bar instead of starting with a hard cap.
-- ts (pixels, optional): where the taper starts. By default a little inside
-- the purple; the closing sweep slides it rightward past the trail's end, so
-- the last of the amber fades out through the gradient, never cut off.
local TRAIL_A = 0.9
-- The taper's two gradient colors are made once and re-filled: this runs
-- every frame while a gain animates, and a new pair of color objects each
-- time was most of the addon's memory churn in combat.
local gradL, gradR, gradAL, gradAR
local function drawTrail(self, left, right, max, ts)
    local w = self.pill:GetWidth()
    local x1, x2 = w * left / math.max(max, 1), w * right / math.max(max, 1)
    ts = ts or (x1 - EDGE * 0.4)
    local main, edge = self.trailMain, self.trailEdge
    local vl = math.max(ts, 0)
    if x2 - vl < 0.5 then main:Hide(); edge:Hide(); return end
    -- Taper: the part of [ts, ts + EDGE] that's inside [vl, x2], with the
    -- gradient's alpha at each visible end matching the full ramp.
    local er = math.min(ts + EDGE, x2)
    if er - vl >= 0.5 then
        local aL, aR = (vl - ts) / EDGE * TRAIL_A, (er - ts) / EDGE * TRAIL_A
        if aL ~= gradAL or aR ~= gradAR then
            local c = TRAIL_COLOR
            if not gradL then
                gradL, gradR = CreateColor(c[1], c[2], c[3], aL), CreateColor(c[1], c[2], c[3], aR)
            end
            if gradL.SetRGBA then
                gradL:SetRGBA(c[1], c[2], c[3], aL); gradR:SetRGBA(c[1], c[2], c[3], aR)
            else
                gradL.a, gradR.a = aL, aR
            end
            gradAL, gradAR = aL, aR
            pcall(edge.SetGradient, edge, "HORIZONTAL", gradL, gradR)
        end
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", self.pill, "TOPLEFT", vl, 0)
        edge:SetPoint("BOTTOMRIGHT", self.pill, "BOTTOMLEFT", er, 0)
        edge:Show()
    else
        edge:Hide()
    end
    if x2 - (ts + EDGE) >= 0.5 then
        main:ClearAllPoints()
        main:SetPoint("TOPLEFT", self.pill, "TOPLEFT", ts + EDGE, 0)
        main:SetPoint("BOTTOMRIGHT", self.pill, "BOTTOMLEFT", x2, 0)
        main:Show()
    else
        main:Hide()
    end
end

-- How hard to flash: by the share of the bar gained, on a square-root curve
-- so small gains still register and big ones (quests, ~5%+) hit full. A
-- mob at high level (~0.5% of the bar) still gets about half strength.
local function flashPower(frac)
    if frac <= 0 then return 0.35 end
    return math.min(1, 0.35 + 0.65 * math.sqrt(frac / 0.05))
end

function XP:StopGain()
    wipe(phases)
    phase, ft = nil, nil
    self.shown = nil
    hideTrail(self)
    if self.gain then
        self.gain:SetValue(0)
        self.flash:SetAlpha(0); self.bloom:SetAlpha(0); self.burst:SetAlpha(0)
        self.driver:Hide()
    end
end

local function startPhase(self)
    local wasRunning = phase ~= nil
    phase = table.remove(phases, 1)
    pt = wasRunning and HOLD or 0 -- only the first phase waits for the flash
    if not phase then
        self.gain:SetValue(0)
        if trail then trail.stage, trail.t = "linger", 0 end
        return
    end
    -- Trail: continue an unfinished one on the same bar, else start here.
    if trail and trail.max == phase.max then
        trail.stage = "fill"
    else
        trail = { left = phase.from, max = phase.max, stage = "fill" }
    end
    local p = self.pill
    p.bar:SetMinMaxValues(0, phase.max)
    self.gain:SetMinMaxValues(0, phase.max)
    p.bar:SetValue(phase.from)
    self.gain:SetValue(phase.to)
end

local function tick(self, dt)
    if ft then
        ft = ft + dt
        local k = math.min(1, ft / FLASH)
        -- Sharp attack (peak at ~15%), long soft decay.
        local a = k < 0.15 and (k / 0.15) or (1 - (k - 0.15) / 0.85) ^ 2
        self.flash:SetAlpha(0.8 * power * a)
        self.bloom:SetAlpha(0.9 * power * a)
        self.burst:SetAlpha(power * a)
        -- The three lights start apart and close up (in whole pixels, so
        -- the layers don't shimmer against each other).
        local px = self.px or 1
        local apart = (2 + 6 * power) * (1 - k) ^ 2
        apart = math.floor(apart / px + 0.5) * px
        self.flash:Spread(apart)
        self.bloom:Spread(apart * 1.5)
        self.burst:Spread(apart * 2)
        -- The burst swells outward as it fades.
        local bs = self.burstSize * (0.7 + 0.6 * k)
        self.burst:SetSize(bs * 2.4, bs)
        if k >= 1 then
            ft = nil
            self.flash:SetAlpha(0); self.bloom:SetAlpha(0); self.burst:SetAlpha(0)
        end
    end
    if phase then
        pt = pt + dt
        local k = math.max(0, math.min(1, (pt - HOLD) / FILL))
        -- Asymmetric ease-in-out: speeds up over the first 40% of the time,
        -- then a longer, gentler slow-down over the last 60% (top speed and
        -- the handover at 40% / 40% of the gain, so the motion is seamless).
        local M = 0.4
        local e
        if k < M then e = M * (k / M) ^ 3
        else e = M + (1 - M) * (1 - (1 - (k - M) / (1 - M)) ^ 3) end
        self.shown = phase.from + (phase.to - phase.from) * e
        self.pill.bar:SetValue(self.shown)
        if trail then trail.right = self.shown; drawTrail(self, trail.left, self.shown, phase.max) end
        if k >= 1 then startPhase(self) end
    elseif trail and trail.stage == "linger" then
        trail.t = trail.t + dt
        if trail.t >= LINGER then
            local w = self.pill:GetWidth()
            trail.stage, trail.t = "sweep", 0
            trail.ts0 = w * trail.left / math.max(trail.max, 1) - EDGE * 0.4
        end
    elseif trail and trail.stage == "sweep" then
        trail.t = trail.t + dt
        local k = math.min(1, trail.t / SWEEP)
        local e = k < 0.5 and 2 * k * k or 1 - (-2 * k + 2) ^ 2 / 2
        local right = trail.right or trail.left
        local w = math.max(self.pill:GetWidth(), 1)
        -- The taper's start slides from where it sat all the way to the end.
        local ts = trail.ts0 + (w * right / math.max(trail.max, 1) - trail.ts0) * e
        -- Keep left (bar units) in step, for a gain landing mid-sweep.
        trail.left = math.min(right, math.max(trail.left, (ts + EDGE * 0.4) * trail.max / w))
        drawTrail(self, trail.left, right, trail.max, ts)
        if k >= 1 then hideTrail(self) end
    end
    if not (phase or ft or trail) then
        -- Idle: nothing may stay lit.
        self.flash:SetAlpha(0); self.bloom:SetAlpha(0); self.burst:SetAlpha(0)
        self.driver:Hide()
    end
end

-- Set the XP pill to cur / max, animating a gain since the last call.
function XP:ShowXP(cur, max)
    local p = self.pill
    local last, lastMax = self.target, self.targetMax
    self.target, self.targetMax = cur, max
    if not plain(cur, max) or not last or not plain(last, lastMax) or self.mode == "rep" then
        self:StopGain()
        p.bar:SetMinMaxValues(0, max)
        p.bar:SetValue(cur)
        self.gain:SetMinMaxValues(0, max)
        self.gain:SetValue(0)
        self.target, self.targetMax = cur, max
        return
    end
    if cur == last and max == lastMax then return end -- nothing new (other events)
    -- Mid level-up animation, the new numbers belong to the new bar.
    local from = (phase and phase.max ~= max) and 0 or (self.shown or last)
    wipe(phases)
    if max == lastMax and cur > last then
        table.insert(phases, { from = from, to = cur, max = max })
    elseif max ~= lastMax or cur < last then
        -- Level-up: finish the old bar, then fill the new one from zero.
        table.insert(phases, { from = from, to = lastMax, max = lastMax })
        if cur > 0 then table.insert(phases, { from = 0, to = cur, max = max }) end
        if #phases == 1 and cur == 0 then table.insert(phases, { from = 0, to = 0, max = max }) end
    else
        -- XP went down (rare: death penalty, etc.): just show it.
        self:StopGain()
        self.target, self.targetMax = cur, max
        p.bar:SetMinMaxValues(0, max); p.bar:SetValue(cur)
        return
    end
    -- Flash strength and where the burst sits (middle of the new stretch).
    local first = phases[1]
    local frac = #phases > 1 and 1 or ((first.to - first.from) / math.max(first.max, 1))
    power = flashPower(frac)
    local w = p:GetWidth()
    local last1 = phases[#phases]
    local mid = (#phases > 1) and last1.to / math.max(last1.max, 1) or ((first.from + first.to) / 2 / math.max(first.max, 1))
    self.burst:ClearAllPoints()
    self.burst:SetPoint("CENTER", p, "LEFT", w * mid, 0)
    self.burstSize = 26 + 40 * power
    self.bloom:SetHeight(10 + 26 * power)
    self.px = ns.Pixel and ns.Pixel() or 1
    ft = 0
    phase = nil -- a new gain restarts the sequence (flash, wait, fill)
    self.driver:Show()
    startPhase(self)
end

-- Purple <-> blue as rested XP comes and goes. The fill eases between them.
function XP:SetPalette(rested)
    local pal = rested and PALETTES.rested or PALETTES.normal
    if self.palette == pal then return end
    self.palette = pal
    local bar, band = self.pill.bar, self.rested
    local c = pal.fill
    ns.TweenColor(bar, function(r, g, b)
        bar:SetStatusBarColor(r, g, b)
        band:SetStatusBarColor(r, g, b, 0.35)
    end, c[1], c[2], c[3], 1, 0.6)
    self.gain:SetStatusBarColor(unpack(pal.ghost))
    -- Tint only (vertex color). Re-setting the flash's color texture here
    -- left it fully lit when rested ran out right after a gain's flash.
    self.flash:SetVertexColor(pal.flash[1], pal.flash[2], pal.flash[3], 1)
    self.bloom:SetVertexColor(pal.bloom[1], pal.bloom[2], pal.bloom[3], 1)
    self.burst:SetVertexColor(pal.burst[1], pal.burst[2], pal.burst[3], 1)
    if not ft then
        self.flash:SetAlpha(0); self.bloom:SetAlpha(0); self.burst:SetAlpha(0)
    end
end

function XP:Update()
    local p = self.pill
    self.mode = nil
    if isMaxed() then
        -- At max level the pill shows the watched reputation instead.
        local name, standing, min, max, value = readRep()
        if not name or not plain(min, max, value) then p:Hide() return end
        self.mode = "rep"
        self:StopGain()
        self.target = nil
        p:Show()
        self.palette = nil
        p.bar.__muiCol = nil -- rep color is set directly, outside the tween
        p.bar:SetStatusBarColor(repColor(standing))
        p.bar:SetMinMaxValues(0, math.max(1, max - min))
        p.bar:SetValue(value - min)
        self.rested:SetValue(0)
        return
    end
    p:Show()
    local cur, max, rest = readXP()
    self:SetPalette(rest and plain(rest) and rest > 0)
    self:ShowXP(cur, max)
    self.rested:SetMinMaxValues(0, max)
    if rest and plain(cur, max, rest) then
        self.rested:SetValue(math.min(cur + rest, max))
    else
        self.rested:SetValue(0)
    end
end

local function showTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if XP.mode == "rep" then
        local name, standing, min, max, value = readRep()
        if name then
            GameTooltip:AddLine(name, 1, 1, 1)
            local label = _G["FACTION_STANDING_LABEL" .. tostring(standing)] or ""
            local r, g, b = repColor(standing)
            GameTooltip:AddDoubleLine("Standing", label, 0.8, 0.8, 0.85, r, g, b)
            if plain(min, max, value) and max > min then
                GameTooltip:AddDoubleLine("Progress", string.format("%s / %s  (%.1f%%)",
                    BreakUpLargeNumbers(value - min), BreakUpLargeNumbers(max - min),
                    (value - min) / (max - min) * 100), 0.8, 0.8, 0.85, 1, 1, 1)
            end
        end
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine("Level " .. tostring(UnitLevel("player")), 1, 1, 1)
    local cur, max, rest = readXP()
    if plain(cur, max) and max > 0 then
        GameTooltip:AddDoubleLine("Experience",
            string.format("%s / %s  (%.1f%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(max),
                cur / max * 100), 0.8, 0.8, 0.85, 1, 1, 1)
        GameTooltip:AddDoubleLine("To level", BreakUpLargeNumbers(max - cur), 0.8, 0.8, 0.85, 1, 1, 1)
    end
    if rest and plain(rest) and rest > 0 then
        GameTooltip:AddDoubleLine("Rested", BreakUpLargeNumbers(rest), 0.8, 0.8, 0.85,
            PALETTES.rested.fill[1] + 0.25, PALETTES.rested.fill[2] + 0.2, 1)
    end
    GameTooltip:Show()
end

function XP:OnInit(db)
    self.db = db
    local p = ns:CreatePillBar(UIParent, 768, HEIGHT) -- 128:1 pill
    self.pill = p
    p:SetFrameStrata("LOW") -- always draws beneath the orbs and buttons
    p.bar:SetStatusBarColor(unpack(XP_COLOR))

    -- Rested band: a second fill under the XP fill, clipped by the same pill mask.
    local rested = CreateFrame("StatusBar", nil, p)
    rested:SetAllPoints(p)
    rested:SetStatusBarTexture(T.bar)
    rested:SetStatusBarColor(XP_COLOR[1], XP_COLOR[2], XP_COLOR[3], 0.35)
    rested:GetStatusBarTexture():AddMaskTexture(p.mask)
    rested:SetFrameLevel(p:GetFrameLevel() + 1)
    self.rested = rested

    -- Gain ghost: the stretch just earned, pale, until the fill catches up.
    local gain = CreateFrame("StatusBar", nil, p)
    gain:SetAllPoints(p)
    gain:SetStatusBarTexture(T.bar)
    gain:SetStatusBarColor(unpack(GAIN_COLOR))
    gain:GetStatusBarTexture():AddMaskTexture(p.mask)
    gain:SetFrameLevel(p:GetFrameLevel() + 2)
    gain:SetMinMaxValues(0, 1)
    gain:SetValue(0)
    self.gain = gain
    p.bar:SetFrameLevel(p:GetFrameLevel() + 3)

    -- Flash: a soft light pulse over the whole pill.
    local over = CreateFrame("Frame", nil, p)
    over:SetAllPoints(p)
    over:SetFrameStrata("MEDIUM") -- the spill draws over neighbours, not under them
    over:SetFrameLevel(p:GetFrameLevel() + 6)
    local flash = prismGroup(function()
        local t = over:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1) -- white; the palette tints it
        t:SetBlendMode("ADD")
        t:AddMaskTexture(p.mask)
        return t
    end)
    flash:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    flash:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    flash:SetVertexColor(0.85, 0.80, 1)
    flash:SetAlpha(0)
    self.flash = flash
    -- Spill: soft light past the pill's edges (unmasked), plus a burst
    -- where the XP landed. Both scale with the flash strength.
    local bloom = prismGroup(function()
        local t = over:CreateTexture(nil, "OVERLAY", nil, -1)
        t:SetTexture(MEDIA .. "spot.tga")
        t:SetBlendMode("ADD")
        return t
    end)
    bloom:SetVertexColor(0.72, 0.62, 1)
    bloom:SetPoint("LEFT", p, "LEFT", -40, 0)
    bloom:SetPoint("RIGHT", p, "RIGHT", 40, 0)
    bloom:SetHeight(24)
    bloom:SetAlpha(0)
    self.bloom = bloom
    local burst = prismGroup(function()
        local t = over:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture(MEDIA .. "spot.tga")
        t:SetBlendMode("ADD")
        return t
    end)
    burst:SetVertexColor(0.92, 0.88, 1)
    burst:SetSize(80, 32)
    burst:SetPoint("CENTER", p, "LEFT", 0, 0)
    burst:SetAlpha(0)
    self.burst = burst
    self.burstSize = 40

    -- Trail layer: above the purple fill, below the flash.
    local tf = CreateFrame("Frame", nil, p)
    tf:SetAllPoints(p)
    tf:SetFrameLevel(p:GetFrameLevel() + 4)
    local tm = tf:CreateTexture(nil, "ARTWORK")
    tm:SetColorTexture(TRAIL_COLOR[1], TRAIL_COLOR[2], TRAIL_COLOR[3], 0.9)
    tm:AddMaskTexture(p.mask)
    tm:Hide()
    local te = tf:CreateTexture(nil, "ARTWORK")
    te:SetColorTexture(1, 1, 1, 1)
    pcall(te.SetGradient, te, "HORIZONTAL",
        CreateColor(TRAIL_COLOR[1], TRAIL_COLOR[2], TRAIL_COLOR[3], 0),
        CreateColor(TRAIL_COLOR[1], TRAIL_COLOR[2], TRAIL_COLOR[3], 0.9))
    te:AddMaskTexture(p.mask)
    te:Hide()
    self.trailMain, self.trailEdge = tm, te

    -- Runs only while a gain is animating.
    self.driver = CreateFrame("Frame", nil, p)
    self.driver:Hide()
    self.driver:SetScript("OnUpdate", function(_, dt) tick(XP, dt) end)

    p:EnableMouse(true)
    p:SetScript("OnEnter", showTooltip)
    p:SetScript("OnLeave", GameTooltip_Hide)

    self:Anchor()
    -- Re-anchor whenever the bar layout is rebuilt (blocks move with the orbs).
    local B = ns.modules.Bars
    if B and B.Arrange then hooksecurefunc(B, "Arrange", function() XP:Anchor() end) end

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP",
                         "PLAYER_ENTERING_WORLD", "UPDATE_FACTION", "PLAYER_REGEN_ENABLED" }) do
        ev:RegisterEvent(e)
    end
    -- Re-quiet on every event: Blizzard creates/refreshes bars (e.g. a newly
    -- watched reputation) and may restore their alpha.
    ev:SetScript("OnEvent", function()
        hideBlizzardTracking()
        XP:Update()
    end)
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnHide", hideBlizzardTracking)
    end
    -- Blizzard restores the bars' visibility after load (and at other times
    -- we don't get an event for), so keep re-checking twice a second.
    -- Every frame for the first few seconds (no visible flash on load), then
    -- twice a second.
    local acc, age = 0, 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, dt)
        acc, age = acc + dt, age + dt
        if age > 5 and acc < 0.5 then return end
        acc = 0
        hideBlizzardTracking()
    end)
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local f = _G[name]
        if f then f:HookScript("OnShow", function(self) self:SetAlpha(0) end) end
    end
    hideBlizzardTracking()
    self:Update()
end

function XP:SetSpan(span)
    self.db.span = span
    self:Anchor()
end

-- ── Level-up banner ───────────────────────────────────────────────────────
-- In place of the game's gold-lined "You've Reached Level N": a card in the
-- middle of the screen, its top 30% of the way down. A round badge with the new level
-- sits on its top edge; under "Level N" the card grows downward as what the
-- level gave you is written in, one line at a time.
-- It borrows the XP bar's gain effect: a soft flash and a bloom of light as
-- it lands, the gains written in the trail's amber, which then settles to
-- the bar's purple before the whole card fades.
-- The game's own banner is made invisible for as long as ours is up (alpha
-- only: it still runs, so its sound plays). /men levelup previews it.
local LV_W, LV_D, LV_ROW = 200, 62, 19
local LV_HEAD = LV_D / 2 + 8 + 24 + 9   -- badge overhang, title, rule
local LV_COLOR = { 0.66, 0.56, 1.00 }
local LV_AMBER = { 1.00, 0.80, 0.38 }
local LV_CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
-- The three lights of the flash, and which way each is pulled (-1 left,
-- 0 centre, +1 right).
local LV_PRISM = { { 1.00, 0.12, 0.22 }, { 0.15, 1.00, 0.35 }, { 0.22, 0.38, 1.00 } }
local LV_PULL = { -1, 0, 1 }
local LV_SEG = 24 -- segments in each light of the afterglow line
local LV_CENTER = 2 -- seconds the finished card waits in the middle before it moves
local LV_LINGER = 7 -- extra seconds the card stays in all (the wait, then parked on the left)
local banner

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

local function buildBanner()
    local f = CreateFrame("Frame", "MeniscusLevelUp", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(LV_W, LV_HEAD)
    -- Centered, the card's top edge 15% of the way down the screen (the
    -- badge sits half above that).
    f:SetPoint("TOP", UIParent, "TOP", 0, -0.15 * UIParent:GetHeight())
    f:EnableMouse(false)
    f:Hide()
    -- (The ring is a whole rounded shape lying behind the fill, so for the
    -- card to be see-through both are translucent: together about 84%.)
    ns.RoundedRect(f, -8, 0, 14, LV_COLOR[1] * 0.7, LV_COLOR[2] * 0.7, LV_COLOR[3] * 0.7, 0.55)
    ns.RoundedRect(f, -7, 1, 13, 0.06, 0.06, 0.07, 0.65)

    -- Flash: the whole card goes almost white for a moment.
    -- It is drawn three times, in red, green and blue light, added
    -- together. Dead on top of each other they make white; pulled apart
    -- sideways they fringe into colour at the edges, like a lens that
    -- hasn't focused yet. The flash starts pulled wide and snaps together.
    f.flashes = {}
    for i, c in ipairs(LV_PRISM) do
        local fl = CreateFrame("Frame", nil, f)
        fl:SetAllPoints()
        fl:SetFrameLevel(f:GetFrameLevel() + 4)
        ns.RoundedRect(fl, 1, 0, 14, c[1], c[2], c[3], 1, "OVERLAY")
        for _, r in ipairs({ fl:GetRegions() }) do
            if r.SetBlendMode then r:SetBlendMode("ADD") end
        end
        fl:SetAlpha(0)
        f.flashes[i] = fl
    end

    f.title = ns:CreateText(f, 17, T.text)
    ns:SetFont(f.title, 17, "", true)
    f.title:SetPoint("TOP", f, "TOP", 0, -(LV_D / 2 + 8))
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(LV_D / 2 + 8 + 24))
    rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -(LV_D / 2 + 8 + 24))

    -- The gains: label on the left, amount on the right, one per line.
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -LV_HEAD)
    holder:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -LV_HEAD)
    holder:SetHeight(1)
    holder:SetClipsChildren(true)
    local inner = CreateFrame("Frame", nil, holder)
    inner:SetPoint("TOPLEFT"); inner:SetPoint("TOPRIGHT")
    inner:SetHeight(400)
    f.holder, f.rows = holder, {}
    for i = 1, 8 do
        local label = ns:CreateText(inner, 11, T.textDim)
        label:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -(i - 1) * LV_ROW)
        local value = ns:CreateText(inner, 12, T.text)
        ns:SetFont(value, 12, "", true)
        value:SetPoint("TOPRIGHT", inner, "TOPRIGHT", 0, -(i - 1) * LV_ROW)
        f.rows[i] = { label = label, value = value }
    end

    local badge = CreateFrame("Frame", nil, f)
    badge:SetSize(LV_D, LV_D)
    badge:SetPoint("CENTER", f, "TOP", 0, 0)
    badge:SetFrameLevel(f:GetFrameLevel() + 6)
    local function disc(size, sub, r, g, b)
        local t = badge:CreateTexture(nil, "BACKGROUND", nil, sub)
        t:SetSize(size, size); t:SetPoint("CENTER")
        t:SetColorTexture(r, g, b, 1)
        local m = badge:CreateMaskTexture()
        m:SetTexture(LV_CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        return t
    end
    disc(LV_D, 0, LV_COLOR[1], LV_COLOR[2], LV_COLOR[3])
    disc(LV_D - 5, 1, 0.07, 0.07, 0.085)
    f.wash = disc(LV_D - 5, 2, LV_COLOR[1], LV_COLOR[2], LV_COLOR[3])
    f.num = ns:CreateText(badge, 26, T.text)
    ns:SetFont(f.num, 26, "", true)
    f.num:SetPoint("CENTER", 0, 0)
    -- Bloom: light spilling out from behind the badge as it lands.
    local glow = CreateFrame("Frame", nil, f)
    glow:SetFrameLevel(f:GetFrameLevel() + 5)
    glow:SetSize(1, 1)
    glow:SetPoint("CENTER", badge, "CENTER")
    -- Bloom and streak, each also in the three lights. The bloom's copies
    -- part sideways; the streak's part up and down, so it splits into a
    -- thin rainbow band.
    f.blooms, f.streaks = {}, {}
    for i, c in ipairs(LV_PRISM) do
        local bl = glow:CreateTexture(nil, "ARTWORK")
        bl:SetTexture(MEDIA .. "spot.tga")
        bl:SetVertexColor(c[1], c[2], c[3], 1)
        bl:SetBlendMode("ADD")
        bl:SetAlpha(0)
        f.blooms[i] = bl
        local st = glow:CreateTexture(nil, "ARTWORK", nil, 1)
        st:SetTexture(MEDIA .. "spot.tga")
        st:SetVertexColor(c[1], c[2], c[3], 1)
        st:SetBlendMode("ADD")
        st:SetAlpha(0)
        f.streaks[i] = st
    end
    f.core = glow:CreateTexture(nil, "ARTWORK", nil, 2)
    f.core:SetTexture(MEDIA .. "spot.tga")
    f.core:SetVertexColor(1, 1, 1, 1)
    f.core:SetBlendMode("ADD")
    f.core:SetPoint("CENTER")
    f.core:SetAlpha(0)
    -- The level number's own fringes: a red and a blue copy behind it.
    f.ghosts = {}
    for i, c in ipairs({ LV_PRISM[1], LV_PRISM[3] }) do
        local g = badge:CreateFontString(nil, "ARTWORK")
        ns:SetFont(g, 26, "", true)
        g:SetTextColor(c[1], c[2], c[3])
        g:SetAlpha(0)
        f.ghosts[i] = g
    end

    -- Afterglow: a thin, straight line of light through the badge, along
    -- the card's top edge. It arrives with the flash and stays as the card
    -- does, slowly dimming, thinning and drawing in. It is drawn in the
    -- three lights a pixel apart (red above, blue below), so it is white
    -- with the faintest coloured edge. Each light is a chain of short
    -- segments, which is what lets it taper to nothing at the tips.
    f.beams = {}
    for i, c in ipairs(LV_PRISM) do
        local segs = {}
        for j = 1, LV_SEG do
            local ln = glow:CreateLine(nil, "ARTWORK", nil, 3)
            ln:SetColorTexture(c[1], c[2], c[3], 1)
            pcall(ln.SetBlendMode, ln, "ADD")
            ln:SetAlpha(0)
            segs[j] = ln
        end
        f.beams[i] = segs
    end
    f.beamAt = glow

    f:SetScript("OnUpdate", function(self, dt)
        local t = self.t + dt
        self.t = t
        local n = self.n
        local px = self.px or 1
        local written = 0.35 + n * 0.12 + 0.2   -- every line is in
        local turn = written + 2.2              -- amber starts settling to purple
        -- It flashes in the middle of the screen, where you can't miss it,
        -- and once its lines are written it slides off to the left and
        -- stays there a while longer (LV_LINGER), out of the way.
        local out = turn + 1.0 + 0.9 + LV_LINGER -- the card starts to fade
        if t >= out + 0.6 then self:Hide() return end
        -- (It waits LV_CENTER seconds in the middle first, then sets off
        -- gently, picks up, and settles just as gently: two seconds, slow
        -- at both ends.)
        local mv = clamp01((t - (written + 0.5 + LV_CENTER)) / 2.0)
        mv = mv * mv * mv * (mv * (mv * 6 - 15) + 10)
        if mv ~= self.mv then
            self.mv = mv
            local x = -self.slide * mv
            -- A slight arc, not a straight line: the path bows upward in
            -- the middle (by an eighth of the distance travelled), like
            -- something tossed gently to its place.
            local dy = self.endY - self.topY
            local bow = 0.125 * math.sqrt(self.slide * self.slide + dy * dy)
            local y = self.topY + dy * mv + bow * math.sin(math.pi * mv)
            self:ClearAllPoints()
            self:SetPoint("TOP", UIParent, "TOP", math.floor(x / px + 0.5) * px, math.floor(y / px + 0.5) * px)
        end
        self:SetAlpha(t < 0.2 and t / 0.2 or (t > out and 1 - (t - out) / 0.6) or 1)
        -- Flash and bloom: sharp attack, long soft decay (as on the XP bar).
        -- It hits hard and out of focus: the three lights start pulled well
        -- apart, so the first instant is a smear of red, green and blue,
        -- and snap together into white. They never quite meet again, which
        -- leaves a thin rainbow edge on everything through the afterglow.
        local fk = t / 1.6
        local a = fk < 0.07 and fk / 0.07 or (fk < 1 and (1 - (fk - 0.07) / 0.93) ^ 2 or 0)
        local k = clamp01(fk)
        local snap = clamp01(t / 0.45)
        -- Afterglow: once the flash has gone, the three lights stay on,
        -- very faintly and a couple of pixels apart, breathing slowly. The
        -- card keeps a thin coloured edge until it fades.
        local glowIn = clamp01((t - 0.6) / 1.2)
        local after = glowIn * (0.075 + 0.025 * math.sin(t * 1.7))
        local pull = 26 * (1 - snap) ^ 3 + 5 * (1 - k)           -- pixels apart
            + glowIn * (2.5 + 1.0 * math.sin(t * 1.1))
        -- (Moved in whole screen pixels. The lights used to shiver a little
        -- as they settled, on fractions of a pixel, and with three layers
        -- re-snapping against each other the card's edge visibly jittered
        -- while it grew.)
        pull = math.floor(pull / px + 0.5) * px
        local bs = LV_D * (2.6 + 3.4 * k)
        for i = 1, 3 do
            local dx = LV_PULL[i] * pull
            local fl = self.flashes[i]
            fl:ClearAllPoints()
            fl:SetPoint("TOPLEFT", self, "TOPLEFT", dx, 0)
            fl:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", dx, 0)
            fl:SetAlpha(math.max(0.85 * a, after))
            local bl = self.blooms[i]
            bl:ClearAllPoints()
            bl:SetPoint("CENTER", dx * 1.8, 0)
            bl:SetSize(bs, bs)
            bl:SetAlpha(a)
            local st = self.streaks[i]
            st:ClearAllPoints()
            st:SetPoint("CENTER", dx * 3, LV_PULL[i] * (pull * 0.45 + 3 * (1 - k)))
            st:SetSize(LV_W * (2.2 + 3.0 * k), 40 - 16 * k)
            st:SetAlpha(0.95 * a)
        end
        for i = 1, 2 do
            local g = self.ghosts[i]
            g:ClearAllPoints()
            g:SetPoint("CENTER", self.num, "CENTER", (i == 1 and -1 or 1) * math.max(px, pull * 0.5), 0)
            g:SetAlpha(math.max(clamp01(a * 1.6), 0.45 * glowIn)) -- the number keeps its fringe
        end
        -- The core burns out fastest.
        self.core:SetAlpha(a * a)
        self.core:SetSize(LV_D * (1.2 + 0.8 * k), LV_D * (1.2 + 0.8 * k))
        self.wash:SetAlpha(0.10 + 0.9 * a)
        -- The card grows downward as the lines are written.
        local g = clamp01((t - 0.25) / (written - 0.25))
        local e = 1 - (1 - g) ^ 3
        local body = math.floor((n * LV_ROW + 8) * e / px + 0.5) * px
        local h = LV_HEAD + body
        self:SetHeight(h)
        self.holder:SetHeight(math.max(1, body))
        -- The line: bright at the flash, then dimmer, thinner and shorter
        -- all the way to the fade. Always straight.
        local life = clamp01((t - 0.4) / (out + 0.6 - 0.4))
        local half = LV_W * (1.9 - 0.55 * life)                      -- half its length
        -- (Gone before the card moves off: it fades out over the half
        -- second after the last line is written.)
        local lineOut = 1 - clamp01((t - written) / 0.45)
        local la = math.max(a, glowIn * (0.62 - 0.30 * life)) * lineOut
        local thick = math.max(px, 2.4 - 1.2 * life)
        local at = self.beamAt
        for i = 1, 3 do
            local segs = self.beams[i]
            local y = -LV_PULL[i] * px
            local x0 = -half
            for j = 1, LV_SEG do
                local u = -1 + 2 * j / LV_SEG                         -- -1 .. 1 along the line
                local x1 = u * half
                local ln = segs[j]
                ln:SetStartPoint("CENTER", at, x0, y)
                ln:SetEndPoint("CENTER", at, x1, y)
                ln:SetThickness(thick)
                -- Brightest at the middle, tapering to nothing at the tips.
                local m = u - 1 / LV_SEG
                local taper = 1 - m * m
                ln:SetAlpha(la * taper * taper)
                x0 = x1
            end
        end
        -- Amber, then purple.
        local c = clamp01((t - turn) / 1.0)
        c = c * c * (3 - 2 * c)
        local r = LV_AMBER[1] + (LV_COLOR[1] - LV_AMBER[1]) * c
        local gg = LV_AMBER[2] + (LV_COLOR[2] - LV_AMBER[2]) * c
        local b = LV_AMBER[3] + (LV_COLOR[3] - LV_AMBER[3]) * c
        for i = 1, n do
            local row = self.rows[i]
            local ra = clamp01((t - (0.35 + (i - 1) * 0.12)) / 0.2)
            row.label:SetAlpha(ra)
            row.value:SetAlpha(ra)
            row.value:SetTextColor(r, gg, b)
        end
    end)
    banner = f
end

-- The game's own level-up banner is EventToastManagerFrame ("You've
-- Reached Level 3"; MinimalUIDB.levelprobe). It used to be faded only while
-- our card was up, and given its alpha back when ours closed, but its toast
-- runs longer than our card, so it reappeared. Now it stays invisible until
-- the toast manager itself closes (the end of that run of toasts), with a
-- 30 s limit in case it never does.
local quietUntil = 0
local TOASTS = { "EventToastManagerFrame", "LevelUpDisplay" }
local function setToastAlpha(a)
    for i = 1, #TOASTS do
        local b = _G[TOASTS[i]]
        if b and not (b.IsForbidden and b:IsForbidden()) then b:SetAlpha(a) end
    end
end
local function quietTick()
    if GetTime() > quietUntil then return setToastAlpha(1) end
    setToastAlpha(0)
    C_Timer.After(0.1, quietTick)
end
function XP:QuietToasts()
    local running = GetTime() < quietUntil
    quietUntil = GetTime() + 30
    for i = 1, #TOASTS do
        local b = _G[TOASTS[i]]
        if b and not b.__menQuietHook and b.HookScript then
            b.__menQuietHook = true
            b:HookScript("OnHide", function(self)
                -- Done: give it back its alpha for the next toast.
                quietUntil = 0
                self:SetAlpha(1)
            end)
        end
    end
    if not running then quietTick() end
end

function XP:ShowLevelUp(level, health, power, talents, _, str, agi, sta, int)
    if type(level) ~= "number" or issecretvalue(level) then return end
    if not banner then buildBanner() end
    local f = banner
    f.num:SetText(level)
    for i = 1, #f.ghosts do f.ghosts[i]:SetText(level) end
    f.title:SetText("Level " .. level)
    local _, tok = UnitPowerType("player")
    local powerName = type(tok) == "string" and _G[tok] or "Power"
    local n = 0
    local function add(v, label)
        if type(v) == "number" and not issecretvalue(v) and v > 0 and n < #f.rows then
            n = n + 1
            f.rows[n].label:SetText(label)
            f.rows[n].value:SetText("+" .. v)
        end
    end
    add(health, "Health"); add(power, powerName)
    add(str, "Strength"); add(agi, "Agility"); add(sta, "Stamina"); add(int, "Intellect")
    add(talents, talents == 1 and "Talent point" or "Talent points")
    for i = 1, #f.rows do
        local row = f.rows[i]
        row.label:SetShown(i <= n); row.value:SetShown(i <= n)
        row.label:SetAlpha(0); row.value:SetAlpha(0)
    end
    f.n = n
    f.t = 0
    -- Start in the middle. Parked, it rests just above the chat panel,
    -- centred on it (down and to the left); without the panel, at the
    -- left of the screen at the same height.
    f.mv = nil
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    f.topY = -0.15 * sh
    f.endY = f.topY
    local cx = 20 + LV_W / 2
    local B = ns.modules.Bars
    local well = B and B.plate and B.plate.chatWell
    if well and well:IsShown() and well:GetLeft() and well:GetTop() then
        cx = math.max(8 + LV_W / 2, (well:GetLeft() + well:GetRight()) / 2)
        -- (The card's full height once its lines are written.)
        local fullH = LV_HEAD + n * LV_ROW + 8
        f.endY = (well:GetTop() + 12 + fullH) - sh
    end
    f.slide = sw / 2 - cx
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, f.topY)
    f.px = ns.Pixel and ns.Pixel() or 1
    f:SetHeight(LV_HEAD)
    f.holder:SetHeight(1)
    f:SetAlpha(0)
    f:Show()
    XP:QuietToasts()
end

local lvEv = CreateFrame("Frame")
lvEv:RegisterEvent("PLAYER_LEVEL_UP")
-- Which frame is the game's own level-up banner? Recorded at real level-ups
-- (the made-up one doesn't bring it up): every visible frame in the upper
-- middle of the screen, with any text in it. Read from MinimalUIDB.levelprobe.
local function texts(f, depth, out)
    if #out >= 4 or depth > 3 then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetText and r:IsVisible() then
            local t = r:GetText()
            if type(t) == "string" and not issecretvalue(t) and t ~= "" then out[#out + 1] = t:sub(1, 40) end
        end
    end
    for _, k in ipairs({ f:GetChildren() }) do
        if k:IsVisible() then texts(k, depth + 1, out) end
    end
end
local function levelProbe(tag)
    if not MinimalUIDB then return end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local rec = MinimalUIDB.levelprobe or {}
    MinimalUIDB.levelprobe = rec
    rec[#rec + 1] = "-- " .. tag .. " at " .. date("%H:%M:%S")
    for _, f in ipairs({ UIParent:GetChildren() }) do
        local ok = pcall(function()
            if f:IsForbidden() or not f:IsVisible() or f == banner then return end
            local l, b, w, h = f:GetRect()
            if not (l and w and w > 0 and h > 0) then return end
            if l + w < W * 0.2 or l > W * 0.8 or b + h < H * 0.4 then return end
            local tx = {}
            texts(f, 0, tx)
            rec[#rec + 1] = string.format("%s %s %s %dx%d @%d,%d a=%.2f %s",
                f:GetName() or "?", f:GetObjectType(), f:GetFrameStrata(), w, h, l, b,
                f:GetEffectiveAlpha() or -1, table.concat(tx, " | "))
        end)
        local _ = ok
    end
    while #rec > 300 do table.remove(rec, 1) end
end

lvEv:SetScript("OnEvent", function(_, _, ...)
    if MinimalUIDB then MinimalUIDB.levelprobe = nil end
    for _, d in ipairs({ 0.3, 1.2, 3 }) do
        C_Timer.After(d, function() pcall(levelProbe, "+" .. d .. "s") end)
    end
    if not (XP.db and XP.db.enabled ~= false and XP.db.levelBanner ~= false) then return end
    pcall(XP.ShowLevelUp, XP, ...)
end)

-- /men levelup: a made-up level-up, to look at the banner.
ns.commands.levelup = function()
    local lvl = UnitLevel("player")
    XP:ShowLevelUp(type(lvl) == "number" and not issecretvalue(lvl) and lvl or 10, 27, 28, 1, 0, 1, 2, 1, 1)
end
