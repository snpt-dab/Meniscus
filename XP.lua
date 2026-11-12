local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Thin XP pill along the bottom, spanning either the orbs or the bar 2/3 blocks.
-- Rested XP shows as a lighter band ahead of the fill. Hover for details.
-- Replaces Blizzard's status tracking bars (hidden on load).

local XP = ns:NewModule("XP", { enabled = true, span = "orbs" }) -- "orbs" | "bars"

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
    local flash = over:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints(p)
    flash:SetColorTexture(1, 1, 1, 1) -- white; the palette tints it
    flash:SetVertexColor(0.85, 0.80, 1, 1)
    flash:SetBlendMode("ADD")
    flash:AddMaskTexture(p.mask)
    flash:SetAlpha(0)
    self.flash = flash
    -- Spill: soft light past the pill's edges (unmasked), plus a burst
    -- where the XP landed. Both scale with the flash strength.
    local bloom = over:CreateTexture(nil, "OVERLAY", nil, -1)
    bloom:SetTexture(MEDIA .. "spot.tga")
    bloom:SetVertexColor(0.72, 0.62, 1, 1)
    bloom:SetBlendMode("ADD")
    bloom:SetPoint("LEFT", p, "LEFT", -40, 0)
    bloom:SetPoint("RIGHT", p, "RIGHT", 40, 0)
    bloom:SetHeight(24)
    bloom:SetAlpha(0)
    self.bloom = bloom
    local burst = over:CreateTexture(nil, "OVERLAY", nil, 1)
    burst:SetTexture(MEDIA .. "spot.tga")
    burst:SetVertexColor(0.92, 0.88, 1, 1)
    burst:SetBlendMode("ADD")
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
-- In place of the game's gold-lined "You've Reached Level N": a round badge
-- with the new level, and a dark pill that opens out of it with "Level N"
-- and what the level gave you (health, power, stats, talent points). It
-- holds for a few seconds, then closes back into the badge and fades.
-- The game's own banner is made invisible for as long as ours is up (alpha
-- only: it still runs, so its sound plays). /men levelup previews it.
local LV_H, LV_D, LV_LIFE = 56, 74, 6.0
local LV_COLOR = { 0.66, 0.56, 1.00 }
local LV_CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local banner

local function buildBanner()
    local off = LV_D / 2 - LV_H / 2 -- the pill starts under the badge
    local f = CreateFrame("Frame", "MeniscusLevelUp", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(LV_D, LV_D)
    f:SetPoint("TOP", UIParent, "TOP", 0, -180)
    f:EnableMouse(false)
    f:Hide()

    local pill = CreateFrame("Frame", nil, f)
    pill:SetSize(LV_H, LV_H)
    pill:SetPoint("LEFT", f, "LEFT", off, 0)
    pill:SetClipsChildren(true)
    ns.RoundedRect(pill, -8, 0, LV_H / 2, LV_COLOR[1] * 0.7, LV_COLOR[2] * 0.7, LV_COLOR[3] * 0.7, 1)
    ns.RoundedRect(pill, -7, 1, LV_H / 2 - 1, 0.06, 0.06, 0.07, 0.97)
    local inner = CreateFrame("Frame", nil, pill)
    inner:SetPoint("LEFT")
    inner:SetSize(700, LV_H)
    local tx = LV_D / 2 + LV_H / 2 + 12
    f.title = ns:CreateText(inner, 19, T.text)
    ns:SetFont(f.title, 19, "", true)
    f.title:SetPoint("BOTTOMLEFT", inner, "LEFT", tx, 0)
    f.gains = ns:CreateText(inner, 11, T.textDim)
    f.gains:SetPoint("TOPLEFT", inner, "LEFT", tx, -4)

    local badge = CreateFrame("Frame", nil, f)
    badge:SetSize(LV_D, LV_D)
    badge:SetPoint("LEFT")
    badge:SetFrameLevel(pill:GetFrameLevel() + 3)
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
    f.num = ns:CreateText(badge, 30, T.text)
    ns:SetFont(f.num, 30, "", true)
    f.num:SetPoint("CENTER", 0, 0)

    f.pill, f.off = pill, off
    f:SetScript("OnUpdate", function(self, dt)
        local t = self.t + dt
        self.t = t
        if t >= LV_LIFE then self:Hide() return end
        local left = LV_LIFE - t
        self:SetAlpha(t < 0.25 and t / 0.25 or (left < 0.5 and left / 0.5) or 1)
        -- Open out of the badge (eased), hold, close back into it.
        local o = 1
        if t < 0.2 then o = 0
        elseif t < 0.75 then o = 1 - (1 - (t - 0.2) / 0.55) ^ 3
        elseif left < 0.7 then o = math.max(0, (left - 0.2) / 0.5) ^ 2 end
        local w = LV_H + (self.full - LV_H) * o
        self.pill:SetWidth(w)
        self:SetWidth(math.max(LV_D, self.off + w)) -- stays centered as it opens
        -- The badge's tint: bright at first, settling to a faint wash.
        self.wash:SetAlpha(0.10 + 0.5 * math.max(0, 1 - t / 0.9) ^ 2)
    end)
    f:SetScript("OnHide", function()
        for _, name in ipairs({ "EventToastManagerFrame", "LevelUpDisplay" }) do
            local b = _G[name]
            if b and not (b.IsForbidden and b:IsForbidden()) then b:SetAlpha(1) end
        end
    end)
    banner = f
end

local function gainText(n, label)
    if type(n) == "number" and not issecretvalue(n) and n > 0 then return "+" .. n .. " " .. label end
end

function XP:ShowLevelUp(level, health, power, talents, _, str, agi, sta, int)
    if type(level) ~= "number" or issecretvalue(level) then return end
    if not banner then buildBanner() end
    local f = banner
    f.num:SetText(level)
    f.title:SetText("Level " .. level)
    local _, tok = UnitPowerType("player")
    local powerName = type(tok) == "string" and _G[tok] or "Power"
    local out
    local function add(s) if s then out = out and (out .. "    " .. s) or s end end
    add(gainText(health, "Health")); add(gainText(power, powerName))
    add(gainText(str, "Strength")); add(gainText(agi, "Agility"))
    add(gainText(sta, "Stamina")); add(gainText(int, "Intellect"))
    if type(talents) == "number" and not issecretvalue(talents) and talents > 0 then
        add("+" .. talents .. (talents == 1 and " Talent point" or " Talent points"))
    end
    f.gains:SetText(out or "You've reached a new level")
    f.full = math.ceil(LV_D / 2 + LV_H / 2 + 12
        + math.max(f.title:GetStringWidth(), f.gains:GetStringWidth()) + 26)
    f.t = 0
    f.pill:SetWidth(LV_H)
    f:SetWidth(LV_D)
    f:SetAlpha(0)
    f:Show()
    -- The game's banner: invisible while ours is up. It can appear a moment
    -- after the event and set its own alpha, so this is re-applied.
    local function quiet()
        if not f:IsShown() then return end
        for _, name in ipairs({ "EventToastManagerFrame", "LevelUpDisplay" }) do
            local b = _G[name]
            if b and not (b.IsForbidden and b:IsForbidden()) then b:SetAlpha(0) end
        end
        C_Timer.After(0.1, quiet)
    end
    quiet()
end

local lvEv = CreateFrame("Frame")
lvEv:RegisterEvent("PLAYER_LEVEL_UP")
lvEv:SetScript("OnEvent", function(_, _, ...)
    if not (XP.db and XP.db.enabled ~= false and XP.db.levelBanner ~= false) then return end
    pcall(XP.ShowLevelUp, XP, ...)
end)

ns.commands.levelup = function()
    local lvl = UnitLevel("player")
    XP:ShowLevelUp(type(lvl) == "number" and not issecretvalue(lvl) and lvl or 10, 17, 12, 0, 0, 1, 2, 1, 0)
end
