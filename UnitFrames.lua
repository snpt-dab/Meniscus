local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

local UF = ns:NewModule("UnitFrames", {
    enabled = true,
    hideBlizzard = true,
    -- Blizzard's own target frame is kept running (invisible) instead of
    -- being switched off, so its buff / debuff icons, the only ones that
    -- can update in combat, are there to borrow. See ghostTarget.
    liveTargetAuras = true,
    player = { x = -310, y = -354 },
    -- "frame": the usual player frame (avatar + health / power pills).
    -- "none": no player frame and no portrait; your level is set into the
    -- health orb's value pill and the resting z's rise from the orb's rim
    -- (/men noportrait).
    -- (Two portrait experiments were tried and dropped: "orb", the avatar
    -- on the health orb's rim, and "rest", a portrait inside the orb. A
    -- saved value of either becomes "none".)
    playerStyle = "none",
    target = { x = 310, y = -354 },
    focus  = { x = 326, y = -249 },
    -- attach = true stacks party frames directly above the player frame;
    -- false lets them float at x/y (drag with /men unlock).
    party  = { attach = true, x = -420, y = 0 },
    boss   = { x = 326, y = 0 },
    -- 3D pop-out avatar camera; tune live with /men portrait <key> <value>
    -- fidget = 0 keeps the plain breathing idle (no yawns/stretches that hit
    -- the model window's edges); 1 allows Blizzard's random idle fidgets.
    portrait = { zoom = 1.0, dist = 1.0, z = 0, facing = 0, pop = 0.35, x = 0.01, fit = 3, fidget = 0, sdist = 1.5, bust3d = 0 },
})

local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local MEDIA = "Interface/AddOns/Meniscus/Media/"

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
    player = { x = -310, y = -354 },
    target = { x = 310, y = -354 },
    focus  = { x = 326, y = -249 },
    party  = { x = -420, y = 0 },
    boss   = { x = 326, y = 0 },
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
local SWIRL_TEX = "Interface/AddOns/Meniscus/Media/swirl.tga"

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

-- The crest: what makes an elite, rare or boss target impossible to miss.
-- A second ring just outside the portrait's own, with ornaments per kind
-- (art from dist/crest.py), a slow shimmer running round the ring, a name
-- tag on top, and a short "snap" when such a target is picked:
--   elite       gold ring, four gold studs
--   rare        silver ring, four silver stars that twinkle
--   rare elite  gold ring and studs, silver stars
--   boss        ember ring of spikes that turns slowly and breathes to gold
-- Only on portraits big enough to carry it; nothing glows past the art.
local CREST_RING_R = 0.80 -- the ring's outer edge in the textures (dist/crest.py)
local CREST_LABEL = { elite = "Elite", rare = "Rare", rareelite = "Rare Elite", boss = "Boss" }
local function crestOf(av)
    if av.crest then return av.crest end
    local d = av.D or 0
    if d < 36 then return nil end
    local c = CreateFrame("Frame", nil, av)
    local S = (d + 9) / CREST_RING_R
    c:SetSize(S, S)
    c:SetPoint("CENTER")
    c:SetFrameLevel(av:GetFrameLevel())
    local function tex(file, sub)
        local t = c:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetAllPoints()
        t:SetTexture(MEDIA .. file)
        return t
    end
    c.ring = tex("crest_ring.tga", 1)
    c.studs = tex("crest_studs.tga", 2)
    c.stars = tex("crest_stars.tga", 3)
    -- The spikes turn, so they get a holder of their own.
    c.spikes = tex("crest_spikes.tga", 0)
    -- Shimmer: bright streaks moving round, only where the ring is.
    c.fx = c:CreateTexture(nil, "ARTWORK", nil, 4)
    c.fx:SetAllPoints()
    c.fx:SetTexture(SWIRL_TEX, "REPEAT", "REPEAT")
    local mask = c:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "crest_ring.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    c.fx:AddMaskTexture(mask)
    -- Name tag: a small dark pill sitting on the top of the ring.
    local tag = CreateFrame("Frame", nil, c)
    tag:SetFrameLevel(av:GetFrameLevel() + 12)
    tag:SetHeight(12)
    tag:SetPoint("CENTER", av, "TOP", 0, 5)
    tag.ring = ns.RoundedRect(tag, -8, 0, 6, 1, 1, 1, 1)
    ns.RoundedRect(tag, -7, 1, 5, 0.05, 0.05, 0.06, 0.97)
    tag.text = tag:CreateFontString(nil, "OVERLAY")
    ns:SetFont(tag.text, 8, "", true)
    tag.text:SetPoint("CENTER", 0, 0)
    c.tag = tag
    -- The snap: the crest lands from a little larger, fading in.
    local ag = c:CreateAnimationGroup()
    local sc = ag:CreateAnimation("Scale")
    sc:SetScaleFrom(1.35, 1.35); sc:SetScaleTo(1, 1); sc:SetDuration(0.28); sc:SetSmoothing("OUT")
    local al = ag:CreateAnimation("Alpha")
    al:SetFromAlpha(0); al:SetToAlpha(1); al:SetDuration(0.2)
    c.snap = ag
    local ph = 0
    c:SetScript("OnUpdate", function(self, dt)
        ph = ph + dt
        local kind = self.kind
        local speed = (kind == "rare") and 0.16 or 0.09
        local u, v = ph * speed, ph * speed * 0.6
        self.fx:SetTexCoord(u, u + 0.8, v, v + 0.8)
        if kind == "rare" or kind == "rareelite" then
            -- Twinkle: the stars brighten and dim, never fully out.
            local k = 0.62 + 0.38 * math.sin(ph * 3.1)
            self.stars:SetVertexColor(SILVER[1], SILVER[2], SILVER[3], k)
        elseif kind == "boss" then
            self.spikes:SetRotation(ph * 0.12)
            local k = 0.5 + 0.5 * math.sin(ph * 1.6)
            local r, g, b = EMBER[1] + (GOLD[1] - EMBER[1]) * k, EMBER[2] + (GOLD[2] - EMBER[2]) * k,
                EMBER[3] + (GOLD[3] - EMBER[3]) * k
            self.spikes:SetVertexColor(r, g, b, 1)
            self.ring:SetVertexColor(r, g, b, 1)
        end
    end)
    c:Hide()
    av.crest = c
    return c
end

local function showCrest(av, kind)
    if kind == "normal" then
        if av.crest then av.crest:Hide() end
        return
    end
    local c = crestOf(av)
    if not c then return end
    c.kind = kind
    local main = (kind == "rare") and SILVER or (kind == "boss") and EMBER or GOLD
    c.ring:SetVertexColor(main[1], main[2], main[3], 1)
    c.studs:SetShown(kind == "elite" or kind == "rareelite")
    c.studs:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    c.stars:SetShown(kind == "rare" or kind == "rareelite")
    c.stars:SetVertexColor(SILVER[1], SILVER[2], SILVER[3], 1)
    c.spikes:SetShown(kind == "boss")
    c.spikes:SetRotation(0)
    -- (The shimmer: pale, over the ring's own colour.)
    c.fx:SetVertexColor(1, 0.96, 0.86, kind == "boss" and 0.75 or 0.55)
    c.tag.text:SetText(string.upper(CREST_LABEL[kind] or ""))
    c.tag.text:SetTextColor(main[1], main[2], main[3], 1)
    c.tag.ring(main[1] * 0.8, main[2] * 0.8, main[3] * 0.8, 1)
    c.tag:SetWidth(math.max(26, (c.tag.text:GetStringWidth() or 20) + 12))
    c:Show()
    c.snap:Stop(); c.snap:Play()
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
    pcall(showCrest, av, kind)
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
local ORB_GLARE = "Interface/AddOns/Meniscus/Media/orb_glare.tga"
-- Built like the player's orbs, at a fraction of the size and with nothing
-- moving: hairline ring, dark track, the liquid, a bright line on its
-- surface, depth toward the bottom, glass sheen and glare.
local function powerOrb(self)
    if self.pOrb then return self.pOrb end
    local hp = self.healthPill
    local d = hp:GetHeight()
    local RING, TRACK = 1.2, 2.2 -- (the big orbs: 1.5 and 4, at 120 across)
    local o = CreateFrame("Frame", nil, self)
    o:SetSize(d, d)
    -- Left end for the target (its target's portrait takes the right end).
    -- Party members: also on the left, outside their portrait (orbGap
    -- clears it), which leaves the right end free for buffs and debuffs.
    if self.orbSide == "RIGHT" then
        o:SetPoint("LEFT", hp, "RIGHT", 4, 0)
    else
        o:SetPoint("RIGHT", hp, "LEFT", -(self.orbGap or 4), 0)
    end
    local ring = o:CreateTexture(nil, "BACKGROUND", nil, 0)
    ring:SetAllPoints()
    ring:SetColorTexture(unpack(T.border))
    ring:AddMaskTexture(newMask(o, d))
    local td = d - RING * 2
    local track = o:CreateTexture(nil, "BACKGROUND", nil, 1)
    track:SetPoint("CENTER"); track:SetSize(td, td)
    track:SetColorTexture(0.05, 0.05, 0.06, 0.96)
    track:AddMaskTexture(newMask(o, td))
    local inner = d - (RING + TRACK) * 2
    local imask = newMask(o, inner)
    local bg = o:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetPoint("CENTER"); bg:SetSize(inner, inner)
    bg:SetColorTexture(0.02, 0.025, 0.03, 1)
    bg:AddMaskTexture(imask)
    o.bar = CreateFrame("StatusBar", nil, o)
    o.bar:SetPoint("CENTER"); o.bar:SetSize(inner, inner)
    o.bar:SetOrientation("VERTICAL")
    o.bar:SetStatusBarTexture(T.bar)
    local fill = o.bar:GetStatusBarTexture()
    fill:AddMaskTexture(imask)
    -- Bright line on the liquid's surface. (In a clip just short of the
    -- top and bottom, so a full or empty orb shows no stray stroke on its
    -- rim; see the big orbs.)
    local lineClip = CreateFrame("Frame", nil, o.bar)
    lineClip:SetPoint("TOPLEFT", o.bar, "TOPLEFT", 0, -2)
    lineClip:SetPoint("BOTTOMRIGHT", o.bar, "BOTTOMRIGHT", 0, 2)
    lineClip:SetClipsChildren(true)
    local lineHold = CreateFrame("Frame", nil, lineClip)
    lineHold:SetAllPoints(o.bar)
    o.line = lineHold:CreateTexture(nil, "OVERLAY", nil, 0)
    o.line:SetHeight(1)
    o.line:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, -1)
    o.line:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, -1)
    o.line:SetColorTexture(1, 1, 1, 0.7)
    o.line:AddMaskTexture(imask)
    -- Darker toward the bottom, a faint sheen toward the top, then the glare.
    local depth = o.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    depth:SetAllPoints(o.bar)
    depth:SetColorTexture(0, 0, 0, 1)
    pcall(depth.SetGradient, depth, "VERTICAL", CreateColor(0, 0, 0, 0.50), CreateColor(0, 0, 0, 0))
    depth:AddMaskTexture(imask)
    local shine = o.bar:CreateTexture(nil, "OVERLAY", nil, 2)
    shine:SetAllPoints(o.bar)
    shine:SetColorTexture(1, 1, 1, 1)
    pcall(shine.SetGradient, shine, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.05))
    shine:AddMaskTexture(imask)
    local gloss = o.bar:CreateTexture(nil, "OVERLAY", nil, 3)
    gloss:SetAllPoints(o.bar)
    gloss:SetTexture(ORB_GLARE)
    gloss:AddMaskTexture(imask)
    function o:SetTint(r, g, b)
        self.bar:SetStatusBarColor(r, g, b)
        self.line:SetColorTexture(math.min(r * 1.25 + 0.15, 1), math.min(g * 1.25 + 0.15, 1),
                                  math.min(b * 1.25 + 0.15, 1), 0.85)
    end
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
    -- The name splits at the fill edge too: dark over the fill (the user's
    -- preference for names), light over the empty track, where dark text
    -- on the dark track could not be read once a bar had drained past it.
    local nameOver = self.name.dark
    if nameOver then
        self.name:SetTextColor(unpack(T.text))
        self.name:SetShadowColor(0, 0, 0, 0.8)
        nameOver:SetTextColor(0.07, 0.07, 0.08, 1)
        nameOver:SetShadowColor(1, 1, 1, 0.25)
    else
        self.name:SetTextColor(0.07, 0.07, 0.08, 1)
        self.name:SetShadowColor(1, 1, 1, 0.25)
    end
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

    if self.key == "tot" and self.avatar and self.avatar.ring then
        -- In the strip this frame is just a portrait, and its ring is its
        -- health: a ring-shaped bar that drains from the top down (the
        -- portrait covers the middle of a round, vertical status bar, so
        -- hidden health values work). Its color says who the target is on:
        -- red = you, otherwise their class / reaction color.
        local ringBar = self.hpRing
        if UF.targetStrip and ringBar then
            local onMe = UnitIsUnit(unit, "player")
            if issecretvalue(onMe) then onMe = false end
            self.avatar.ring:SetColorTexture(0, 0, 0, 0)
            ringBar:SetMinMaxValues(0, UnitHealthMax(unit))
            ringBar:SetValue(UnitHealth(unit))
            if onMe then ringBar:SetStatusBarColor(0.92, 0.26, 0.22)
            else ringBar:SetStatusBarColor(r, g, b) end
        else
            self.avatar.ring:SetColorTexture(unpack(T.border))
        end
    end
    if self.key == "target" then
        pcall(styleClass, self, unit)
        local isPlayer = UnitIsPlayer(unit)
        if issecretvalue(isPlayer) then isPlayer = false end
        if isPlayer then
            local o = powerOrb(self)
            o.bar:SetMinMaxValues(0, pmax)
            o.bar:SetValue(pcur)
            if c then o:SetTint(c[1], c[2], c[3]) end
            o:Show()
        elseif self.pOrb then
            self.pOrb:Hide()
        end
        -- In the console's strip there is no power pill at all: players get
        -- the orb, everything else just the health bar.
        self.powerPill:SetShown(not isPlayer and not UF.targetStrip)
    elseif self.orbSide then
        -- Party members: a power orb beside the bar instead of the power
        -- pill, always.
        local o = powerOrb(self)
        o.bar:SetMinMaxValues(0, pmax)
        o.bar:SetValue(pcur)
        if c then o:SetTint(c[1], c[2], c[3]) end
        o:Show()
        self.powerPill:Hide()
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
    -- (While the portrait tuner is open the target's bust is framed like
    -- every other portrait, so what you fit on a target is what players and
    -- party members of that race will look like.)
    local bust = av.bust and not UF.tuning
    m:SetSize(0.8 * d, (0.8 + (bust and 0 or p.pop)) * d)
    m:SetPoint("BOTTOM", av, "CENTER", 0, -0.3 * d)
end

local function visible(unit)
    local v = UnitIsVisible(unit)
    if issecretvalue(v) then return true end
    return v
end

-- Models differ by race and gender (height, head size, where the face sits
-- in the frame), so the camera can be tuned per race + gender: db.portrait
-- .byModel["Human3"] = { x =, z =, dist = } overrides the shared values.
-- Players only (creatures have no race). Set with /men portrait fit.
local function modelKey(unit)
    if not UnitIsPlayer(unit) then return nil end
    local name, race = UnitRace(unit)
    local sex = UnitSex(unit)
    if type(race) ~= "string" or issecretvalue(race) or type(sex) ~= "number" or issecretvalue(sex) then return nil end
    -- Skyborne (Forever's own race) look the same in both factions, which
    -- may be two race entries: one fit for both.
    if race:lower():find("sky", 1, true)
        or (type(name) == "string" and not issecretvalue(name) and name:lower():find("skyborne", 1, true)) then
        race = "Skyborne"
    end
    return race .. sex
end
UF.ModelKey = modelKey

-- Built-in fits for every classic race + Skyborne, both genders (tuned by
-- hand with the portrait tuner, 2026-11-12). A fit saved in the profile
-- (tuner Save, /men portrait fit) takes precedence.
local FITS = {
    Human2    = { x = 0.02, z = -0.02, dist = 1.05 }, Human3    = { x = 0.02,  z = 0,     dist = 0.9 },
    Dwarf2    = { x = 0.03, z = -0.03, dist = 1.15 }, Dwarf3    = { x = 0.01,  z = 0,     dist = 1.0 },
    NightElf2 = { x = 0.07, z = -0.02, dist = 1.15 }, NightElf3 = { x = 0.03,  z = 0,     dist = 1.1 },
    Gnome2    = { x = 0.04, z = -0.03, dist = 1.0 },  Gnome3    = { x = 0.08,  z = -0.05, dist = 1.0 },
    Orc2      = { x = 0.03, z = -0.02, dist = 1.15 }, Orc3      = { x = 0.06,  z = -0.03, dist = 1.05 },
    Scourge2  = { x = 0.06, z = 0,     dist = 1.0 },  Scourge3  = { x = 0,     z = 0,     dist = 1.15 },
    Tauren2   = { x = 0.18, z = -0.25, dist = 1.75 }, Tauren3   = { x = 0.16,  z = -0.08, dist = 1.4 },
    Troll2    = { x = 0.10, z = -0.01, dist = 1.15 }, Troll3    = { x = 0.06,  z = -0.03, dist = 1.05 },
    Skyborne2 = { x = 0.02, z = 0,     dist = 1.1 },  Skyborne3 = { x = -0.02, z = -0.01, dist = 0.8 },
}
local function fitFor(p, key)
    return key and ((p.byModel and p.byModel[key]) or FITS[key]) or nil
end

function UF:RefreshAvatar(av)
    local unit = av.unit
    if not UnitExists(unit) then return end
    local m = av.model
    local p = self.db.portrait
    -- A "bust" avatar (the target strip's) has to stay inside its circle.
    -- A 3D model can't be masked: a big creature fills the model's whole
    -- rectangle and its corners show outside the ring. So the bust uses the
    -- game's own head-and-shoulders portrait, which masks cleanly
    -- (/men portrait bust3d 1 brings the model back).
    -- With 3D on, only players get the model there: creatures come in every
    -- size and spill out of the circle, so they keep the flat portrait.
    local isPlayer = UnitIsPlayer(unit)
    if issecretvalue(isPlayer) then isPlayer = false end
    local flatBust = av.bust and (p.bust3d ~= 1 or not isPlayer)
    if av.lip then av.lip:SetShown(not flatBust) end
    if m and visible(unit) and not flatBust then
        av.flat:Hide()
        m:Show()
        m:ClearModel()
        m:SetUnit(unit)
        pcall(m.SetPortraitZoom, m, p.zoom)
        -- A "bust" avatar (the target strip's, hanging under the bar) pulls
        -- the camera back so the whole head and the shoulders fit inside
        -- the circle, instead of the head rising out of its top.
        local key = modelKey(unit)
        local o = key and ((UF.preview and UF.preview.key == key and UF.preview)
            or fitFor(p, key)) or nil
        -- (The bust's own distance, scaled by the race's fit when there is one.)
        local bustDist = (p.sdist or 1.5) * ((o and o.dist and p.dist and p.dist > 0) and (o.dist / p.dist) or 1)
        pcall(m.SetCamDistanceScale, m, (av.bust and not UF.tuning) and bustDist or (o and o.dist) or p.dist)
        -- x nudges the model sideways (negative = left) so the face sits
        -- centered in the circle, clear of the model window's straight edges.
        -- (-0.03 was the first, wrong-way guess: positive y moves the model left.)
        if p.x == nil or p.x == -0.03 then p.x = 0.04 end
        pcall(m.SetPosition, m, 0, (o and o.x) or p.x, (o and o.z) or p.z)
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
    f.name = hp:CreateText(s.font, nil, true) -- splits at the fill edge, like the value
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
    if self.db.playerStyle == "rest" or self.db.playerStyle == "orb" then self.db.playerStyle = "none" end
    local style = self.db.playerStyle
    local on = style == "none" and orb and orb:IsShown() and true or false
    local bare = on and style == "none"
    -- "none": no pills. With the console's character panel (Bars.charSlot)
    -- the portrait lives there, larger; without it the frame is only an
    -- invisible anchor for what hangs off it.
    local BR = ns.modules.Bars
    local char = bare and BR and BR.charSlot or nil
    f.avatar:SetShown((not bare) or char ~= nil)
    f:EnableMouse((not bare) or char ~= nil)
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
    self:PlaceFocus()
    local AU = ns.modules.Auras
    if AU and AU.SeatBlizzard and AU.db then AU:SeatBlizzard() end
end

-- Console layout: the focus frame goes on the pet's side. Classes without a
-- pet have that slot of the plate free, so it sits in it. Classes with a
-- standing pet (their pet panel is there) get it just above that panel,
-- rising out of the plate the way the party does on the other side.
-- (Decided by class, not by whether a pet is out right now: the frame is a
-- secure one and can't be moved when that changes mid-fight.)
local PET_CLASSES = { HUNTER = true, WARLOCK = true, DEATHKNIGHT = true }
function UF:PlaceFocus()
    local fo = self.focus
    if not fo or InCombatLockdown() then return end
    local B = ns.modules.Bars
    local slots = self.orbStyleOn and B and B.Slots and B:Slots()
    fo:ClearAllPoints()
    if slots then
        local R = slots.right
        local cx, cy = (R.x0 + R.x1) / 2, (slots.y0 + slots.y1) / 2 + 6
        local _, class = UnitClass("player")
        local av = fo.avatar and fo.avatar.D or 40
        -- (Shifted left by half the portrait that hangs off its right end.)
        if class and PET_CLASSES[class] then
            fo:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx - av / 4, cy + 44 + 16)
        else
            fo:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx - av / 4, cy + 8)
        end
    else
        place(fo, self.db.focus)
    end
    local CB = ns.modules.CastBars
    if CB and CB.focus and CB.focus.place then CB.focus.place() end
end

-- Console layout (minimap dome + character panel): the target stands over
-- the map, where your eyes are in a fight, 15% larger and turned upside
-- down so its portrait can hang under the bar:
--     target's cast bar
--     health pill         (name / value; no power pill: players get a
--                          small power orb beside it, NPCs nothing)
--        ( portrait )     centered under the bar, overlapping its bottom edge
--     -- your cast bar -- just above the dome's top edge
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
    -- The health pill fills from the left, like every other bar: as health
    -- drops, the bar's end moves to the left. (Filling from the right was
    -- tried here by mistake; pills still support it through SetReverse.)
    if hp.SetReverse then hp:SetReverse(false) end
    if strip then
        t:SetScale(STRIP_SCALE)
        hp:SetPoint("BOTTOM", t, "BOTTOM")
        pw:SetPoint("TOP", t, "TOP")
        av:SetPoint("TOP", hp, "BOTTOM", 0, STRIP_OVERLAP)
        if not av.bust then av.bust = true; self:LayoutAvatar(av); self:RefreshAvatar(av) end
        -- No avatar on the bar's end any more: both texts use the caps' inset.
        t.name:SetPoint("LEFT", hp, "LEFT", s.H / 2, 0)
        t.hpText:SetPoint("RIGHT", hp, "RIGHT", -s.H / 2, 0)
        -- Above the dome: your cast bar (18), a gap (4), then the
        -- portrait, whose top is STRIP_OVERLAP inside the bar. Offsets are in
        -- the frame's own (scaled) units.
        -- (plus the level badge, which hangs about 11 below the portrait and
        -- was sitting on your cast bar)
        -- (your cast bar: 4 above the dome and 14 tall)
        local up = 18 + 4 + 13 + (av.D - STRIP_OVERLAP) * STRIP_SCALE
        t:SetPoint("BOTTOM", dome, "TOP", 0, up / STRIP_SCALE)
    else
        t:SetScale(1)
        hp:SetPoint("TOP", t, "TOP")
        pw:SetPoint("BOTTOM", t, "BOTTOM")
        av:SetPoint("CENTER", hp, "RIGHT", 0, -2)
        if av.bust then av.bust = nil; self:LayoutAvatar(av); self:RefreshAvatar(av) end
        local avatarInset = s.D / 2 + 6
        t.name:SetPoint("LEFT", hp, "LEFT", s.H / 2, 0)
        t.hpText:SetPoint("RIGHT", hp, "RIGHT", -avatarInset, 0)
        place(t, self.db.target)
    end
    t.name:SetPoint("RIGHT", t.hpText, "LEFT", -6, 0)
    if tot then
        -- Strip: the target's target is a round portrait on the bar's right
        -- end, as tall as the bar (the mirror of a player target's power
        -- orb on the left end). No bars; hover for who it is.
        local st = SIZES.tiny
        local tav = tot.avatar
        tot:ClearAllPoints()
        tav:ClearAllPoints()
        tot.healthPill:SetShown(not strip)
        tot.powerPill:SetShown(not strip)
        if strip then
            local d = s.H
            tot:SetScale(STRIP_SCALE)
            tot:SetSize(d, d)
            tav:SetScale(d / tav.D)
            tav:SetPoint("CENTER", tot, "CENTER")
            tot:SetPoint("LEFT", hp, "RIGHT", 4, 0)
            if not tot.hpRing then
                -- Health ring: a round status bar just behind the portrait,
                -- a little larger than it, over a dark disc for the part
                -- that's gone.
                local rd = d + 3
                local back = tot:CreateTexture(nil, "BACKGROUND", nil, 0)
                back:SetPoint("CENTER"); back:SetSize(rd, rd)
                back:SetColorTexture(0.13, 0.13, 0.15, 1)
                back:AddMaskTexture(newMask(tot, rd))
                local rb = CreateFrame("StatusBar", nil, tot)
                rb:SetPoint("CENTER"); rb:SetSize(rd, rd)
                rb:SetFrameLevel(math.max(tav:GetFrameLevel() - 1, 0))
                rb:SetOrientation("VERTICAL")
                rb:SetStatusBarTexture(T.bar)
                rb:GetStatusBarTexture():AddMaskTexture(newMask(rb, rd))
                tot.hpRing, tot.hpRingBack = rb, back
            end
            tot.hpRing:Show(); tot.hpRingBack:Show()
            if not tot.__tip then
                tot.__tip = true
                tot:HookScript("OnEnter", function(self)
                    if not UF.targetStrip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    if pcall(GameTooltip.SetUnit, GameTooltip, self.unit) then GameTooltip:Show() end
                end)
                tot:HookScript("OnLeave", function() GameTooltip:Hide() end)
            end
        else
            if tot.hpRing then tot.hpRing:Hide(); tot.hpRingBack:Hide() end
            tot:SetScale(1)
            tot:SetSize(st.W, st.H + st.GAP + st.PH)
            tav:SetScale(1)
            tav:SetPoint("CENTER", tot.healthPill, "RIGHT", 0, -2)
            tot:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -SMALL_FRAME_GAP)
        end
        pcall(update, tot)
    end
    local CB = ns.modules.CastBars
    if CB and CB.target and CB.target.place then CB.target.place() end
    if CB and CB.player and CB.player.place then CB.player.place() end
    local AU = ns.modules.Auras
    if AU and AU.PlaceTargetRow then pcall(AU.PlaceTargetRow, AU, strip) end
    pcall(self.SeatTargetAuras, self)
end

local STYLE_NAMES = { frame = "normal frame", none = "character panel (no frame)" }
function UF:SetPlayerStyle(style)
    if InCombatLockdown() then return ns:Print("Can't change the player frame in combat.") end
    self.db.playerStyle = STYLE_NAMES[style] and style or "frame"
    self:ApplyPlayerStyle()
    if self.db.playerStyle ~= "frame" and not self.orbStyleOn then
        ns:Print("That player style needs the orbs, which are hidden (/men orbs).")
    else
        ns:Print("Player portrait:", STYLE_NAMES[self.db.playerStyle])
    end
end
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
    local B = ns.modules.Bars
    local char = B and B.charSlot
    if self.db.party.attach and char and self.orbStyleOn then
        -- Console: the party rises out of the console above the character
        -- panel, centered on it, clear of the Quick Buff pill that sits on
        -- the panel's top edge. (Width: power orb, portrait overhang, bar.)
        local wl = char.well
        local colW = s.H + 4 + s.D / 2 + s.W
        a:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            wl.x + (wl.w - colW) / 2 + s.H + 4 + s.D / 2, wl.y + wl.h + 3 + 30 + 10 + (B.stanceLift or 0))
    elseif self.db.party.attach then
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

-- Blizzard's target frame as a ghost: still shown by the game when you have
-- a target and still receiving its events (so its own, untainted code keeps
-- its aura icons current in combat), but fully transparent and deaf to the
-- mouse. Nothing is unregistered, hidden or reparented.
local function quietMouse(fr, depth)
    if fr.EnableMouse then pcall(fr.EnableMouse, fr, false) end
    if depth > 0 then
        for _, child in ipairs({ fr:GetChildren() }) do quietMouse(child, depth - 1) end
    end
end
local function ghostTarget()
    local fr = _G.TargetFrame
    if not fr or fr.__muiGhost then return end
    fr.__muiGhost = true
    fr:SetAlpha(0)
    hooksecurefunc(fr, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
    quietMouse(fr, 4)
end

-- Blizzard's target frame keeps its buff / debuff icons in a managed "aura
-- container" (TargetFrame:GetAuraContainer()). That container is the one
-- thing that can show a target's auras live in combat, and it only stays
-- that way if nothing of ours is written into it: calling its setters from
-- addon code would taint its fields and its next combat update would be
-- refused like ours are. So it is only ever touched through plain widget
-- calls: made visible despite its ghosted parent, and re-anchored onto our
-- target strip (and put back whenever Blizzard's layout re-anchors it).
-- Icon size, rows and "buffs on top" stay Edit Mode's target-frame settings.
local tcSeat, tcSeating = nil, false
local tcHooked = setmetatable({}, { __mode = "k" }) -- (kept here: nothing is written on the container)
local function reseatTargetAuras(cont)
    if not tcSeat or tcSeating then return end
    tcSeating = true
    pcall(function()
        cont:ClearAllPoints()
        cont:SetPoint(tcSeat[1], tcSeat[2], tcSeat[3], tcSeat[4], tcSeat[5])
    end)
    tcSeating = false
end
function UF:SeatTargetAuras()
    local root, t = _G.TargetFrame, self.target
    if not (root and t and root.__muiGhost and root.GetAuraContainer) then return end
    local ok, cont = pcall(root.GetAuraContainer, root)
    if not ok or type(cont) ~= "table" or not cont.SetPoint then return end
    -- Which corner the icons flow from decides which corner gets pinned.
    local corner = "BOTTOMLEFT"
    local okA, ap = pcall(function() return cont.GetFlowLayoutAnchorPoint and cont:GetFlowLayoutAnchorPoint() end)
    if okA and type(ap) == "string" and not issecretvalue(ap) and ap ~= "" then corner = ap end
    local right = corner:find("RIGHT") ~= nil
    local down = corner:find("TOP") ~= nil
    if self.targetStrip then
        -- Console strip: under the health pill, beside the portrait that
        -- hangs from its middle (the user's preferred spot). Blizzard's
        -- icons come as one unbroken run, so they can't sit either side of
        -- the portrait as ours did: they start next to it, on the side they
        -- flow toward, and run outward. Offsets are in the container's own
        -- scale; the pill belongs to the enlarged strip.
        local k = STRIP_SCALE
        local x = (t.avatar.D / 2 + 6) * k
        -- Flowing downward: hang from the pill's bottom edge. Flowing upward
        -- ("buffs on top" in Edit Mode): the first row is dropped below the
        -- pill; further rows would climb into it.
        local y = down and (-4 * k) or (-(4 + 30) * k)
        tcSeat = { corner, t.healthPill, "BOTTOM", right and -x or x, y }
    else
        -- Normal target frame: above the cast bar, from the pill's end on
        -- the side the icons flow from.
        local y = 6 + 14 + 8 + (down and 44 or 0)
        tcSeat = { corner, t.healthPill, right and "TOPRIGHT" or "TOPLEFT", right and -6 or 6, y }
    end
    pcall(function()
        cont:SetIgnoreParentAlpha(true)
        cont:SetAlpha(1)
    end)
    if not tcHooked[cont] then
        tcHooked[cont] = true
        hooksecurefunc(cont, "SetPoint", function(self2) if not tcSeating then reseatTargetAuras(self2) end end)
    end
    reseatTargetAuras(cont)
    self.liveTargetCont = cont
end

-- What Blizzard's target frame is made of on this client, and where its
-- aura icons sit (MinimalUIDB.targetprobe): needed to borrow them. Taken
-- automatically the first time a target shows any aura icons; /men
-- targetprobe forces it.
local function probeTarget()
    local root = _G.TargetFrame
    if not (root and MinimalUIDB) then return 0 end
    -- (Positions and sizes come back hidden in combat, which made the last
    -- recording useless: only record outside it.)
    if InCombatLockdown() then return -1 end
    local out, auraLike = {}, 0
    local function f0(v) return type(v) == "number" and string.format("%.0f", v) or tostring(v) end
    local function line(tag, f, depth)
        local ok, s = pcall(function()
            local p, rel, rp, x, y = f:GetPoint(1)
            local prot = f.IsProtected and select(1, f:IsProtected())
            local hasIcon = type(rawget(f, "Icon")) == "table"
            return string.rep("  ", depth) .. tag .. " [" .. f:GetObjectType() .. "] " .. tostring(f:GetName() or "?")
                .. (f:IsShown() and "" or " hidden") .. " " .. f0(f:GetWidth()) .. "x" .. f0(f:GetHeight())
                .. " @" .. tostring(p) .. ">" .. tostring(rel and (rel.GetName and rel:GetName() or "?")) .. " "
                .. tostring(rp) .. " " .. f0(x) .. "," .. f0(y)
                .. " L=" .. f0(f:GetLeft()) .. " B=" .. f0(f:GetBottom())
                .. " scale=" .. string.format("%.2f", f:GetScale())
                .. " level=" .. tostring(f:GetFrameLevel()) .. " prot=" .. tostring(prot)
                .. (hasIcon and " ICON" or "")
        end)
        out[#out + 1] = ok and s or (tag .. " error: " .. tostring(s))
    end
    local function keysOf(f)
        local ks = {}
        for k, v in pairs(f) do
            if type(k) == "string" and k:sub(1, 2) ~= "__" then ks[#ks + 1] = k .. ":" .. type(v) end
        end
        table.sort(ks)
        return table.concat(ks, ", ")
    end
    line("TargetFrame", root, 0)
    out[#out + 1] = "TargetFrame keys: " .. keysOf(root)
    local function walk(f, depth)
        if depth > 4 or (f.IsForbidden and f:IsForbidden()) then return end
        local names = {}
        for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
        for _, c in ipairs({ f:GetChildren() }) do
            local icon = type(rawget(c, "Icon")) == "table"
            if icon and c:IsShown() then
                auraLike = auraLike + 1
                if auraLike <= 3 then
                    line(names[c] or "#", c, depth)
                    out[#out + 1] = string.rep("  ", depth + 1) .. "keys: " .. keysOf(c)
                end
            elseif not icon then
                line(names[c] or "#", c, depth)
                walk(c, depth + 1)
            end
        end
    end
    walk(root, 1)
    -- The icons are not children of the target frame: they live in a
    -- managed "aura container" the frame hands out.
    local okc, cont = pcall(function() return root.GetAuraContainer and root:GetAuraContainer() end)
    if okc and type(cont) == "table" and cont.GetObjectType then
        out[#out + 1] = "--- aura container ---"
        line("container", cont, 0)
        pcall(function()
            out[#out + 1] = "alpha=" .. string.format("%.2f", cont:GetAlpha()) .. " effAlpha=" .. string.format("%.2f", cont:GetEffectiveAlpha())
                .. " visible=" .. tostring(cont:IsVisible()) .. " strata=" .. tostring(cont:GetFrameStrata())
                .. " ignoreParentAlpha=" .. tostring(cont.IsIgnoringParentAlpha and cont:IsIgnoringParentAlpha())
                .. " R=" .. f0(cont:GetRight()) .. " T=" .. f0(cont:GetTop())
            for i = 1, cont:GetNumPoints() do
                local p, rel, rp, x, y = cont:GetPoint(i)
                out[#out + 1] = "  point " .. i .. ": " .. tostring(p) .. " > " .. tostring(rel and (rel.GetName and rel:GetName() or "?"))
                    .. " " .. tostring(rp) .. " " .. f0(x) .. "," .. f0(y)
            end
            local chain, pr = {}, cont:GetParent()
            while pr and #chain < 6 do chain[#chain + 1] = tostring(pr:GetName() or "?"); pr = pr:GetParent() end
            out[#out + 1] = "parents: " .. table.concat(chain, " < ")
        end)
        out[#out + 1] = "container keys: " .. keysOf(cont)
        local shown = 0
        pcall(function()
            for _, c in ipairs({ cont:GetChildren() }) do
                if c:IsShown() then
                    shown = shown + 1
                    if shown <= 5 then
                        line("icon" .. shown, c, 1)
                        out[#out + 1] = "    R=" .. f0(c:GetRight()) .. " T=" .. f0(c:GetTop()) .. " keys: " .. keysOf(c)
                    end
                end
            end
        end)
        out[#out + 1] = "container children shown: " .. shown
        auraLike = auraLike + shown
        pcall(function()
            out[#out + 1] = "frame: buffsOnTop=" .. tostring(root.buffsOnTop) .. " auraRows=" .. tostring(root.auraRows)
            local sb = root.spellbar
            if sb then line("spellbar", sb, 0) end
        end)
    else
        out[#out + 1] = "aura container: " .. tostring(okc) .. " / " .. tostring(cont)
    end
    out[#out + 1] = "shown aura-like children: " .. auraLike
    out[#out + 1] = string.format("screen %.0fx%.0f", UIParent:GetWidth(), UIParent:GetHeight())
    local best = MinimalUIDB.targetprobeCount or -1
    if auraLike >= best then
        MinimalUIDB.targetprobe, MinimalUIDB.targetprobeCount = out, auraLike
    end
    return auraLike
end
ns.commands.targetprobe = function()
    if MinimalUIDB then MinimalUIDB.targetprobeCount = -1 end
    local n = probeTarget()
    ns:Print("Target frame recorded (" .. tostring(n) .. " aura icons showing). /reload so it can be read.")
end

function UF:ApplyBlizzard(hide)
    if InCombatLockdown() then return ns:Print("Can't change Blizzard frames in combat.") end
    if not hide then
        -- Their events are gone; only a reload brings them back cleanly.
        return ns:Print("Blizzard unit frames will return after /reload.")
    end
    local live = self.db.liveTargetAuras ~= false
    if live then
        ghostTarget()
        if not self.targetProbeEv then
            -- Record the frame once it has aura icons to show.
            local ev = CreateFrame("Frame")
            self.targetProbeEv = ev
            ev:RegisterEvent("PLAYER_TARGET_CHANGED")
            ev:RegisterUnitEvent("UNIT_AURA", "target")
            local tries = 0
            ev:SetScript("OnEvent", function(frame)
                if not InCombatLockdown() and not UF.liveTargetCont then pcall(UF.SeatTargetAuras, UF) end
                if tries >= 12 then return end
                C_Timer.After(1, function()
                    if not UnitExists("target") then return end
                    tries = tries + 1
                    local ok, n = pcall(probeTarget)
                    if ok and type(n) == "number" and n > 0 then tries = tries + 3 end
                end)
            end)
        end
    end
    for _, fr in ipairs({ PlayerFrame, (not live) and TargetFrame or false, FocusFrame, PartyFrame, CompactPartyFrame,
                          PlayerCastingBarFrame, (not live) and TargetFrameSpellBar or false, FocusFrameSpellBar,
                          PetFrame, _G.BossTargetFrameContainer }) do
        if fr and not fr.__muiDisabled then
            fr.__muiDisabled = true
            silence(fr, 3)
            if fr.SetUnit then pcall(fr.SetUnit, fr, nil) end -- cast bars
            fr:Hide()
            fr:SetParent(hidden)
            self.gone = self.gone or {}
            self.gone[#self.gone + 1] = fr
            -- If the game takes the frame back, put it away again.
            hooksecurefunc(fr, "SetParent", function(_, p)
                if p ~= hidden then C_Timer.After(0, function() UF:KeepHidden() end) end
            end)
        end
    end
    if not self.keeper then
        -- On a cold login the game lays out its frames (the Edit Mode
        -- layout) after we have put these away, and that brought the player
        -- frame back to the screen. Check again once that has happened.
        local k = CreateFrame("Frame")
        self.keeper = k
        k:RegisterEvent("PLAYER_ENTERING_WORLD")
        k:RegisterEvent("PLAYER_REGEN_ENABLED")
        pcall(k.RegisterEvent, k, "EDIT_MODE_LAYOUTS_UPDATED")
        k:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" and not UF.keepPending then return end
            UF:KeepHidden()
            if event ~= "PLAYER_REGEN_ENABLED" then
                C_Timer.After(1, function() UF:KeepHidden() end)
                C_Timer.After(4, function() UF:KeepHidden() end)
            end
        end)
    end
end

function UF:KeepHidden()
    if not self.gone then return end
    if InCombatLockdown() then self.keepPending = true return end
    self.keepPending = nil
    for i = 1, #self.gone do
        local fr = self.gone[i]
        if fr:GetParent() ~= hidden then pcall(fr.SetParent, fr, hidden) end
        if fr:IsShown() then pcall(fr.Hide, fr) end
    end
end

-- ── Init ──────────────────────────────────────────────────────────────────
function UF:OnInit(db)
    self.db = db
    -- Fit the pop-out (once): the head and hair were reaching the model
    -- window's straight sides and top. Camera further back, a taller window
    -- above the circle, the face nudged toward the middle.
    local p = db.portrait
    if p and (p.fit or 0) < 1 then
        p.fit = 1
        p.dist = math.max(p.dist or 1, 1.2)
        p.pop = math.max(p.pop or 0.25, 0.45)
        p.x = 0.06
    end
    -- The target's portrait is a live 3D face again (it can be fitted per
    -- race and gender now); the switch in settings still turns it off.
    if p and (p.fit or 0) < 2 then
        p.fit = 2
        p.bust3d = 1
    end
    -- ...and flat again: creatures don't fit, and the race fits are made on
    -- the player frame now.
    if p and (p.fit or 0) < 3 then
        p.fit = 3
        p.bust3d = 0
    end
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
        -- A power orb instead of a power pill (see update), to the left
        -- of the portrait.
        self.party[i].orbSide = "LEFT"
        self.party[i].orbGap = SIZES.party.D / 2 + 4
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

-- /men party attach | detach | test
ns.commands.party = function(rest)
    rest = rest or ""
    if rest == "attach" or rest == "detach" then
        if InCombatLockdown() then return ns:Print("Can't move party frames in combat.") end
        UF.db.party.attach = rest == "attach"
        UF:LayoutParty()
        ns:Print("Party frames", UF.db.party.attach and "attached above the player frame"
            or "detached (move with /men unlock)")
    elseif rest == "test" then
        UF:SetPartyTest(not UF.partyTest)
    else
        ns:Print("usage: /men party attach | detach | test   (currently "
            .. (UF.db.party.attach and "attached" or "detached") .. ")")
    end
end

-- ── Movable frames ────────────────────────────────────────────────────────
-- /men unlock : drag the frames, positions save automatically
-- /men lock   : lock again    /men reset : restore default positions
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
    ns:Print(locked and "Frames locked." or "Frames unlocked: drag them, then /men lock.")
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
        ns:Print("Combat started: move mode paused. /men lock when out of combat.")
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

-- /men portrait                 show current camera values
-- /men portrait <key> <value>   zoom | dist | z | facing | pop | fidget   (applies live)
-- /men portrait reset
ns.commands.portrait = function(rest)
    local p = UF.db and UF.db.portrait
    if not p then return end
    if p.x == nil or p.x == -0.03 then p.x = 0.04 end
    local key, val = (rest or ""):match("^(%S+)%s+(%S+)$")
    val = tonumber(val)
    if rest == "tune" then return UF:OpenTuner() end
    if rest == "todo" then
        local missing, have, total = UF:FitsMissing()
        return ns:Print(#missing == 0 and ("All " .. total .. " race and gender fits done.")
            or string.format("%d of %d fitted. Still to do: %s", have, total, table.concat(missing, ", ")))
    end
    -- /men portrait fit <x|z|dist> <number>: for the race + gender of your
    -- target (or yourself with no player targeted). "fit clear" drops it.
    local fk, fv = (rest or ""):match("^fit%s+(%S+)%s*(%S*)$")
    if fk then
        local unit = (UnitExists("target") and UnitIsPlayer("target")) and "target" or "player"
        local mk = modelKey(unit)
        if not mk then return ns:Print("Can't tell that model's race and gender.") end
        p.byModel = p.byModel or {}
        if fk == "clear" then
            p.byModel[mk] = nil
        elseif (fk == "x" or fk == "z" or fk == "dist") and tonumber(fv) then
            if not p.byModel[mk] then
                local b = FITS[mk] or {}
                p.byModel[mk] = { x = b.x, z = b.z, dist = b.dist }
            end
            p.byModel[mk][fk] = tonumber(fv)
        else
            return ns:Print("usage: /men portrait fit <x|z|dist> <number>  |  /men portrait fit clear")
        end
        eachModel(function(av) UF:RefreshAvatar(av) end)
        local o = fitFor(p, mk) or {}
        return ns:Print(string.format("%s (%s): x %s  z %s  dist %s  (blank = shared value)", mk,
            unit == "target" and "your target" or "you", tostring(o.x or "-"), tostring(o.z or "-"), tostring(o.dist or "-")))
    end
    if rest == "reset" then
        if InCombatLockdown() then return ns:Print("Can't resize avatars in combat.") end
        p.zoom, p.dist, p.z, p.facing, p.pop, p.fidget, p.x = 1.0, 1.0, 0, 0, 0.35, 0, 0.01
        eachModel(function(av) UF:LayoutAvatar(av); UF:RefreshAvatar(av) end)
    elseif key and val and p[key] ~= nil then
        if InCombatLockdown() and key == "pop" then
            return ns:Print("Can't resize avatars in combat.")
        end
        p[key] = val
        eachModel(function(av) UF:LayoutAvatar(av); UF:RefreshAvatar(av) end)
    elseif rest and rest ~= "" then
        ns:Print("usage: /men portrait <zoom|dist|sdist|bust3d|x|z|facing|pop|fidget> <number>  |  /men portrait reset  |  /men portrait fit <x|z|dist> <number> (your target's race and gender)")
    end
    ns:Print(string.format("portrait zoom %.2f  dist %.2f  x %.2f  z %.2f  facing %.2f  pop %.2f  fidget %d  |  target strip dist (sdist) %.2f",
        p.zoom, p.dist, p.x, p.z, p.facing, p.pop, p.fidget, p.sdist or 1.5))
end

-- ── Portrait tuner (temporary) ────────────────────────────────────────────
-- A small window for fitting the 3D portrait camera per race and gender:
-- nudge x / z / dist with - and +, watch the portraits change, then Save
-- (kept for that race and gender) or Revert. /men portrait tune opens it.
local tuner
local STEP = { x = 0.01, z = 0.01, dist = 0.05 }
local function tunerUnit() return "player" end

-- The races and genders to fit, and which are still missing: the classic
-- races and Skyborne (one fit for both factions).
local FIT_RACES = { { "Human", "Human" }, { "Dwarf", "Dwarf" }, { "NightElf", "Night Elf" }, { "Gnome", "Gnome" },
                    { "Orc", "Orc" }, { "Scourge", "Undead" }, { "Tauren", "Tauren" }, { "Troll", "Troll" },
                    { "Skyborne", "Skyborne" } }
function UF:FitsMissing()
    local done = (self.db.portrait.byModel) or {}
    local missing, total, have = {}, 0, 0
    for _, r in ipairs(FIT_RACES) do
        for _, sx in ipairs({ { 2, "Male" }, { 3, "Female" } }) do
            total = total + 1
            if done[r[1] .. sx[1]] or FITS[r[1] .. sx[1]] then have = have + 1
            else missing[#missing + 1] = sx[2] .. " " .. r[2] end
        end
    end
    return missing, have, total
end
local function refreshAll()
    eachModel(function(av) pcall(UF.RefreshAvatar, UF, av) end)
end
local function setTuning(on)
    UF.tuning = on or nil
    eachModel(function(av) pcall(UF.LayoutAvatar, UF, av) end)
end
local function tunerLoad()
    local p = UF.db.portrait
    local unit = tunerUnit()
    local key = modelKey(unit)
    tuner.key = key
    if not key then
        UF.preview = nil
        tuner.title:SetText("Target a player")
        return
    end
    local saved = fitFor(p, key) or {}
    UF.preview = { key = key, x = saved.x or p.x, z = saved.z or p.z, dist = saved.dist or p.dist }
    local race = UnitRace(unit)
    local sex = UnitSex(unit) == 3 and "Female" or "Male"
    tuner.title:SetText(sex .. " " .. (type(race) == "string" and not issecretvalue(race) and race or key)
        .. (unit == "player" and "  (you)" or ""))
    tuner.saved = fitFor(p, key) ~= nil
end
local function tunerShow()
    local missing, have, total = UF:FitsMissing()
    tuner.todo:SetText(#missing == 0 and ("All " .. total .. " fitted.")
        or string.format("%d of %d fitted. Still to do: %s", have, total, table.concat(missing, ", ")))
    local pv = UF.preview
    for k, row in pairs(tuner.rows) do
        row.value:SetText(pv and string.format(k == "dist" and "%.2f" or "%.2f", pv[k]) or "-")
    end
    tuner.state:SetText(tuner.key and (tuner.dirty and "Not saved" or (tuner.saved and "Saved for this race" or "Using the shared camera")) or "")
    refreshAll()
end

function UF:OpenTuner()
    if not tuner then
        tuner = CreateFrame("Frame", "MeniscusPortraitTuner", UIParent)
        tuner:SetSize(240, 252)
        tuner:SetPoint("RIGHT", UIParent, "RIGHT", -360, 120)
        tuner:SetFrameStrata("DIALOG")
        tuner:EnableMouse(true)
        tuner:SetMovable(true)
        tuner:RegisterForDrag("LeftButton")
        tuner:SetScript("OnDragStart", tuner.StartMoving)
        tuner:SetScript("OnDragStop", tuner.StopMovingOrSizing)
        ns.RoundedRect(tuner, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(tuner, -7, 1, 11, 0.06, 0.06, 0.07, 0.97)
        tuner.title = ns:CreateText(tuner, 12)
        ns:SetFont(tuner.title, 12, "", true)
        tuner.title:SetPoint("TOP", 0, -12)
        tuner.state = ns:CreateText(tuner, 10, T.textDim)
        tuner.state:SetPoint("TOP", tuner.title, "BOTTOM", 0, -3)
        tuner.todo = ns:CreateText(tuner, 10, T.textDim)
        tuner.todo:SetPoint("TOPLEFT", tuner, "TOPLEFT", 14, -126)
        tuner.todo:SetPoint("TOPRIGHT", tuner, "TOPRIGHT", -14, -126)
        tuner.todo:SetJustifyH("LEFT")
        tuner.todo:SetWordWrap(true)
        tuner.rows = {}
        local labels = { x = "Sideways", z = "Up / down", dist = "Distance" }
        for i, k in ipairs({ "x", "z", "dist" }) do
            local y = -48 - (i - 1) * 26
            local l = ns:CreateText(tuner, 11, T.textDim)
            l:SetPoint("LEFT", tuner, "TOPLEFT", 14, y)
            l:SetText(labels[k])
            local function nudge(dir)
                if not UF.preview then return end
                UF.preview[k] = UF.preview[k] + dir * STEP[k]
                tuner.dirty = true
                tunerShow()
            end
            local plus = ns.Pill(tuner, "+", function() nudge(1) end, { h = 20, minW = 26, pad = 10 })
            plus:SetPoint("RIGHT", tuner, "TOPRIGHT", -12, y)
            local val = ns:CreateText(tuner, 11)
            val:SetPoint("RIGHT", plus, "LEFT", -8, 0)
            val:SetWidth(38)
            val:SetJustifyH("CENTER")
            local minus = ns.Pill(tuner, "-", function() nudge(-1) end, { h = 20, minW = 26, pad = 10 })
            minus:SetPoint("RIGHT", val, "LEFT", -8, 0)
            tuner.rows[k] = { value = val }
        end
        local close = ns.Pill(tuner, "Close", function() tuner:Hide() end, { h = 22, minW = 54, pad = 16 })
        close:SetPoint("BOTTOMLEFT", 12, 12)
        local revert = ns.Pill(tuner, "Revert", function()
            tuner.dirty = false
            tunerLoad(); tunerShow()
        end, { h = 22, minW = 54, pad = 16 })
        revert:SetPoint("LEFT", close, "RIGHT", 6, 0)
        local save = ns.Pill(tuner, "Save", function()
            local pv = UF.preview
            if not (pv and tuner.key) then return end
            local p = UF.db.portrait
            p.byModel = p.byModel or {}
            p.byModel[tuner.key] = { x = pv.x, z = pv.z, dist = pv.dist }
            tuner.dirty, tuner.saved = false, true
            tunerShow()
            ns:Print("Portrait camera saved for " .. tuner.title:GetText() .. ".")
        end, { h = 22, minW = 54, pad = 16, primary = true })
        save:SetPoint("BOTTOMRIGHT", -12, 12)
        if ns.SetButtonPrimary then pcall(ns.SetButtonPrimary, save, true) end
        tuner:SetScript("OnHide", function()
            UF.preview = nil
            setTuning(false)
            tuner.dirty = false
            refreshAll()
        end)
        local ev = CreateFrame("Frame", nil, tuner)
        ev:RegisterEvent("PLAYER_TARGET_CHANGED")
        ev:SetScript("OnEvent", function()
            if tuner:IsShown() and not tuner.dirty then tunerLoad(); tunerShow() end
        end)
    end
    tuner.dirty = false
    tuner:Show()
    setTuning(true)
    tunerLoad()
    tunerShow()
end
