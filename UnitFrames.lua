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
    local r, g, b
    if attackable and ns.CreatureLevelColor then r, g, b = ns.CreatureLevelColor(unit, lvl) end
    if r then
        badge.text:SetTextColor(r, g, b)
    else
        badge.text:SetTextColor(unpack(T.text))
    end
end

-- The role bubble on a portrait (see where it is made).
local ROLE_EMBLEM = { TANK = { "micro_stat_defense.tga", 0.45, 0.68, 1.00 }, HEALER = { "micro_role_healer.tga", 0.45, 0.90, 0.55 } }
function UF.SetWho(self, unit)
    local rb = self.roleBadge
    local role
    if UF.db.whoBadges ~= false and self.key ~= "player" and UnitGroupRolesAssigned then
        local okP, isPlayer = pcall(UnitIsPlayer, unit)
        if okP and not issecretvalue(isPlayer) and isPlayer then
            local okR, r = pcall(UnitGroupRolesAssigned, unit)
            role = okR and type(r) == "string" and not issecretvalue(r) and ROLE_EMBLEM[r] or nil
        end
    end
    if role then
        rb.icon:SetTexture(MEDIA .. role[1])
        rb.icon:SetVertexColor(role[2], role[3], role[4], 1)
    end
    rb:SetShown(role ~= nil)
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

-- Dungeon bosses: the game calls them plain "elite" (only raid bosses and
-- skull-level mobs are "worldboss"). They are told apart three ways, any
-- of which may or may not answer on this client:
--   * the game says so (UnitIsBossMob);
--   * the unit is one of the fight's boss units (boss1-5);
--   * its name is that of an encounter you have started before. Those are
--     remembered (MinimalUIDB.bossNames), so from the second visit on a
--     boss is marked before the pull.
local BOSS_TOKENS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local function isBossUnit(unit)
    if UnitIsBossMob then
        local ok, b = pcall(UnitIsBossMob, unit)
        if ok and not issecretvalue(b) and b == true then return true end
    end
    for i = 1, #BOSS_TOKENS do
        local ok, same = pcall(UnitIsUnit, unit, BOSS_TOKENS[i])
        if ok and not issecretvalue(same) and same == true then return true end
    end
    local names = MinimalUIDB and MinimalUIDB.bossNames
    if names then
        local ok, n = pcall(UnitName, unit)
        if ok and type(n) == "string" and not issecretvalue(n) and names[n] then return true end
    end
    return false
end
ns.IsBossUnit = isBossUnit

local function classOf(unit)
    local c = UnitClassification and UnitClassification(unit)
    if type(c) ~= "string" or issecretvalue(c) then c = "normal" end
    local lvl = UnitLevel(unit)
    local skull = type(lvl) == "number" and not issecretvalue(lvl) and lvl < 0
    local player = UnitIsPlayer(unit)
    if issecretvalue(player) then player = false end
    if c == "worldboss" or (skull and not player) then return "boss" end
    if (c == "elite" or c == "rareelite") and not player and isBossUnit(unit) then return "boss" end
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
-- Where the name tag ("BOSS", "ELITE") sits: on the top of the portrait's
-- ring, as a rule. Where the portrait hangs under the health bar (the
-- target above the dome) that put the tag in the middle of the bar, hiding
-- what little of the bar showed between the two: there it sits on the
-- bar's top edge instead (av.tagBar, set by the layout).
-- The same layout has the boss's turning spikes cross the health bar:
-- there the spikes are drawn in two parts, each behind a mask that stays
-- put while the spikes turn. The part below the bar is as it was; the part
-- over the bar is drawn at SPIKES_OVER: 0, not at all, so the spikes look
-- to pass behind the bar (0.35 was tried first: faint, but still on it).
local SPIKES_OVER = 0
local function placeTag(av)
    local c = av.crest
    local tag = c and c.tag
    if not tag then return end
    c.split = av.tagBar ~= nil
    c.maskLo:ClearAllPoints(); c.maskHi:ClearAllPoints()
    if c.split then
        c.maskLo:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT"); c.maskLo:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT")
        c.maskLo:SetPoint("TOP", av.tagBar, "BOTTOM")
        c.maskHi:SetPoint("TOPLEFT", c, "TOPLEFT"); c.maskHi:SetPoint("TOPRIGHT", c, "TOPRIGHT")
        c.maskHi:SetPoint("BOTTOM", av.tagBar, "BOTTOM")
    else
        c.maskLo:SetAllPoints(c); c.maskHi:SetAllPoints(c)
    end
    c.spikesHi:SetShown(c.split and c.kind == "boss" and SPIKES_OVER > 0)
    -- The elite's studs and the rare's stars flank the top of the ring,
    -- which here is behind the bar: turned upside down, they flank the
    -- bottom instead, either side of the level badge.
    if c.split then
        c.studs:SetTexCoord(0, 1, 1, 0); c.stars:SetTexCoord(0, 1, 1, 0)
    else
        c.studs:SetTexCoord(0, 1, 0, 1); c.stars:SetTexCoord(0, 1, 0, 1)
    end
    tag:ClearAllPoints()
    if av.tagBar then
        tag:SetPoint("CENTER", av.tagBar, "TOP", 0, 1)
    else
        tag:SetPoint("CENTER", av, "TOP", 0, 5)
    end
end
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
    c.spikesHi = tex("crest_spikes.tga", 0) -- (the part over a health bar: see placeTag)
    c.spikesHi:Hide()
    local function part(t)
        local m = c:CreateMaskTexture()
        m:SetTexture("Interface/Buttons/WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints()
        t:AddMaskTexture(m)
        return m
    end
    c.maskLo, c.maskHi = part(c.spikes), part(c.spikesHi)
    -- Shimmer: bright streaks moving round, only where the ring is.
    c.fx = c:CreateTexture(nil, "ARTWORK", nil, 4)
    c.fx:SetAllPoints()
    c.fx:SetTexture(SWIRL_TEX, "REPEAT", "REPEAT")
    local mask = c:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "crest_ring.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    c.fx:AddMaskTexture(mask)
    -- (The ring the spikes stand on, its studs, stars and shimmer go behind
    -- the bar with them: cut off by the same mask.)
    c.ring:AddMaskTexture(c.maskLo); c.studs:AddMaskTexture(c.maskLo)
    c.stars:AddMaskTexture(c.maskLo); c.fx:AddMaskTexture(c.maskLo)
    -- Name tag: a small dark pill sitting on the top of the ring.
    local tag = CreateFrame("Frame", nil, c)
    tag:SetFrameLevel(av:GetFrameLevel() + 12)
    tag:SetHeight(12)
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
            self.spikesHi:SetRotation(ph * 0.12)
            local k = 0.5 + 0.5 * math.sin(ph * 1.6)
            local r, g, b = EMBER[1] + (GOLD[1] - EMBER[1]) * k, EMBER[2] + (GOLD[2] - EMBER[2]) * k,
                EMBER[3] + (GOLD[3] - EMBER[3]) * k
            self.spikes:SetVertexColor(r, g, b, 1)
            self.spikesHi:SetVertexColor(r, g, b, SPIKES_OVER)
            self.ring:SetVertexColor(r, g, b, 1)
        end
    end)
    c:Hide()
    av.crest = c
    placeTag(av)
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
    c.spikesHi:SetShown(kind == "boss" and c.split == true and SPIKES_OVER > 0)
    c.spikesHi:SetRotation(0)
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
    if self.roleBadge then pcall(UF.SetWho, self, unit) end
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
        UF.restyleTarget = UF.restyleTarget or function() pcall(styleClass, self, self.unit or "target") end
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
    -- Target, party and the other frames (not your own): the unit's tooltip
    -- when you point at the frame, the same one (and in the same place) as
    -- pointing at them in the world.
    if unit ~= "player" then
        f:HookScript("OnEnter", function(self)
            if UF.db and UF.db.partyTip == false then return end
            if not UnitExists(self.unit) then return end
            if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
            else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
            if pcall(GameTooltip.SetUnit, GameTooltip, self.unit) then GameTooltip:Show() end
        end)
        f:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- "*" = any modifier combination. Plain "type1" only matches with no
    -- modifiers held, so Click Casting's remapped target click (e.g.
    -- shift-ctrl-left) found no action.
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    -- Pings: the game only pings a unit frame that says it can take one
    -- (as its own frames do): the ping mixin, which answers "whose frame
    -- is this" from f.unit, and the receiver attribute.
    ns.MakePingable(f, unit, function() return f.avatar and f.avatar.IsMouseOver and f.avatar:IsMouseOver() end)
    -- One edge only, the one the client acts on (the ActionButtonUseKeyDown
    -- setting: the press, by default). With both registered, targeting and
    -- the menu still fired once, but a Click Casting spell fired on the
    -- press AND the release: every heal was followed by a second, failed
    -- cast and a "Spell is not ready yet" (seen 100 times in one dungeon).
    local onPress = true
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and v == false then onPress = false end
    end
    f:RegisterForClicks(onPress and "AnyDown" or "AnyUp")

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

        -- Their part in a group, on the portrait's upper edge, in the same
        -- bubble: a tank's shield or a healer's plus. (Damage dealers get
        -- no mark: it is the two that matter. A class emblem was tried
        -- here too and taken out: the bar's colour already says the class.)
        local function bubble(side)
            local bb = CreateFrame("Frame", nil, f.avatar)
            bb:SetSize(d, d)
            bb:SetPoint("CENTER", f.avatar, "CENTER", side * s.D * 0.36, s.D * 0.36)
            bb:SetFrameLevel(f.avatar:GetFrameLevel() + 5)
            local br = bb:CreateTexture(nil, "BACKGROUND", nil, 0)
            br:SetAllPoints()
            br:SetColorTexture(unpack(T.border))
            br:AddMaskTexture(newMask(bb, d))
            local bfm = newMask(bb, d - 3)
            local bf = bb:CreateTexture(nil, "BACKGROUND", nil, 1)
            bf:SetPoint("CENTER")
            bf:SetSize(d - 3, d - 3)
            bf:SetColorTexture(0.17, 0.17, 0.19, 1)
            bf:AddMaskTexture(bfm)
            bb.icon = bb:CreateTexture(nil, "OVERLAY")
            bb.icon:SetPoint("CENTER")
            bb.icon:SetSize(d - 4, d - 4)
            bb:Hide()
            return bb
        end
        local outer = cfg.side == "LEFT" and -1 or 1
        f.roleBadge = bubble(outer)
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
        av.tagBar = hp
        placeTag(av)
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
        av.tagBar = nil
        placeTag(av)
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

-- A fight with a boss has begun: remember its name, and look at the target
-- again (it may have been marked "Elite" a moment ago).
do
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "ENCOUNTER_START")
    pcall(ev.RegisterEvent, ev, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    ev:SetScript("OnEvent", function(_, e, _, name)
        if e == "ENCOUNTER_START" and type(name) == "string" and not issecretvalue(name) and name ~= "" and MinimalUIDB then
            MinimalUIDB.bossNames = MinimalUIDB.bossNames or {}
            MinimalUIDB.bossNames[name] = true
        end
        if UF.restyleTarget then C_Timer.After(0.2, UF.restyleTarget) end
    end)
end

-- ── Notes on the group's frames ───────────────────────────────────────────
-- A small chip on the top edge of a member's health pill (and your own),
-- for two things a healer otherwise finds out by wasting a cast:
--   * "Shield in 12": you shielded them; Weakened Soul stops another for
--     that long (a second Power Word: Shield fails as "Immune"). Counted
--     from your own cast, so it needs nothing read from the unit in combat.
--   * "Res incoming" while someone is casting a resurrection on them, and
--     "Res pending" once one has landed and they have yet to accept.
local SHIELD_ID, SHIELD_LOCK = 17, 15
local RES_IDS = { 2006, 7328, 2008, 20484, 50769 }
function UF:BuildNotes()
    if self.db.notes == false then return end
    local function spellName(id)
        local ok, n = pcall(C_Spell.GetSpellName, id)
        return ok and type(n) == "string" and not issecretvalue(n) and n or nil
    end
    local shieldName = spellName(SHIELD_ID)
    local resNames = {}
    for _, id in ipairs(RES_IDS) do local n = spellName(id); if n then resNames[n] = true end end

    local list = {}
    local function add(f)
        if not (f and f.healthPill) then return end
        local chip = CreateFrame("Frame", nil, f)
        chip:SetHeight(13)
        if f == self.player and f.avatar then
            -- Yours: on the bottom of your portrait (in the console your
            -- health is an orb, and the pill this would sit on is up among
            -- the buffs).
            chip:SetPoint("CENTER", f.avatar, "BOTTOM", 0, 3)
            chip:SetFrameStrata("MEDIUM")
            chip:SetFrameLevel((f.avatar:GetFrameLevel() or 1) + 20)
        else
            chip:SetPoint("RIGHT", f.healthPill, "TOPRIGHT", -10, 0)
            chip:SetFrameLevel(f:GetFrameLevel() + 12)
        end
        chip.ring = ns.RoundedRect(chip, -8, 0, 6.5, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(chip, -7, 1, 5.5, 0.06, 0.06, 0.07, 1)
        chip.text = ns:CreateText(chip, 9)
        chip.text:SetPoint("CENTER", 0, 0)
        chip:Hide()
        list[#list + 1] = { f = f, chip = chip, shieldUntil = 0, res = nil, resUntil = 0 }
    end
    add(self.player)
    for _, f in ipairs(self.party or {}) do add(f) end
    if #list == 0 then return end

    local function show(n, label, r, g, b)
        if n.label ~= label then
            n.label = label
            n.chip.text:SetText(label)
            n.chip.text:SetTextColor(r, g, b)
            n.chip.ring(r * 0.7, g * 0.7, b * 0.7, 1)
            n.chip:SetWidth(math.max(24, (n.chip.text:GetStringWidth() or 20) + 12))
        end
        n.chip:Show()
    end
    local driver = CreateFrame("Frame")
    driver:Hide()
    local acc = 1
    driver:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        local now, any = GetTime(), false
        for _, n in ipairs(list) do
            if n.res then
                -- Up again (or the note has gone stale): done.
                local ok, dead = pcall(UnitIsDeadOrGhost, n.f.unit)
                if (ok and not issecretvalue(dead) and not dead) or (n.res == "pending" and now > n.resUntil) then n.res = nil end
            end
            if n.res then
                any = true
                show(n, n.res == "incoming" and "Res incoming" or "Res pending", 0.42, 0.92, 0.50)
            elseif n.shieldUntil > now then
                any = true
                show(n, "Shield in " .. math.ceil(n.shieldUntil - now), GOLD[1], GOLD[2], GOLD[3])
            else
                n.label = nil
                n.chip:Hide()
            end
        end
        if not any then self:Hide() end
    end)
    local function wake() acc = 1; driver:Show() end

    local function noteFor(test)
        for _, n in ipairs(list) do
            local u = n.f.unit
            if u and UnitExists(u) and test(u) then return n end
        end
    end
    local function byName(name)
        if type(name) ~= "string" or issecretvalue(name) then return end
        local short = name:match("^([^%-]+)") or name
        return noteFor(function(u)
            local ok, n = pcall(UnitName, u)
            return ok and type(n) == "string" and not issecretvalue(n) and (n == name or n == short)
        end)
    end
    local function byUnit(unit)
        return noteFor(function(u)
            local ok, same = pcall(UnitIsUnit, u, unit)
            return ok and not issecretvalue(same) and same == true
        end)
    end

    local sentGUID, sentTarget, lastRes = nil, nil, 0
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "INCOMING_RESURRECT_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e, unit, a2, a3, a4)
        if e == "UNIT_SPELLCAST_SENT" then
            -- (unit, target, castGUID, spellID)
            if unit == "player" and not issecretvalue(a3) then sentGUID, sentTarget = a3, a2 end
        elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
            -- (unit, castGUID, spellID)
            if issecretvalue(unit) or issecretvalue(a3) or type(a3) ~= "number" then return end
            local name = spellName(a3)
            if not name then return end
            if resNames[name] then lastRes = GetTime() end
            if unit == "player" and shieldName and name == shieldName and not issecretvalue(a2) and a2 == sentGUID then
                local n = byName(sentTarget) or byUnit("player")
                if n then n.shieldUntil = GetTime() + SHIELD_LOCK; wake() end
            end
        elseif e == "INCOMING_RESURRECT_CHANGED" then
            if type(unit) ~= "string" or issecretvalue(unit) or not UnitHasIncomingResurrection then return end
            local n = byUnit(unit)
            if not n then return end
            local ok, has = pcall(UnitHasIncomingResurrection, n.f.unit)
            if not ok or issecretvalue(has) then return end
            if has then
                n.res = "incoming"
                wake()
            elseif n.res == "incoming" then
                -- The cast ended. If a resurrection has just landed, they
                -- have it waiting; otherwise it was broken off.
                C_Timer.After(0.4, function()
                    if n.res ~= "incoming" then return end
                    if GetTime() - lastRes < 2 then n.res, n.resUntil = "pending", GetTime() + 60
                    else n.res = nil end
                    wake()
                end)
            end
        end
    end)
end

-- ── Quick Cure ──────────────────────────────────────────────────────────────
-- Something on a group member (or you) that your class can take off.
--   * In a fight the game lets nothing choose a spell's target for you, and
--     lets no casting button be shown or moved. So there can't be one
--     button that finds whoever needs curing: there is a button for EACH
--     person, fixed on them and in its place before the fight (the way the
--     old Decursive worked). See "What is shown" in BuildCure.
--   * A class with two cures has them on the two mouse buttons (a priest:
--     left Dispel Magic, right Cure Disease); a square shows a small "R"
--     when it is the right-button one that is wanted, the pill says so.
local CURES = {
    PRIEST  = { { "Dispel Magic", "Magic" }, { "Abolish Disease", "Disease" }, { "Cure Disease", "Disease" } },
    PALADIN = { { "Cleanse", "Magic", "Poison", "Disease" }, { "Purify", "Poison", "Disease" } },
    DRUID   = { { "Abolish Poison", "Poison" }, { "Cure Poison", "Poison" }, { "Remove Curse", "Curse" } },
    SHAMAN  = { { "Cure Poison", "Poison" }, { "Cure Disease", "Disease" } },
    MAGE    = { { "Remove Lesser Curse", "Curse" } },
}
local CURE_TINT = { Magic = { 0.25, 0.55, 1.00 }, Curse = { 0.65, 0.30, 0.95 },
                    Disease = { 0.75, 0.52, 0.22 }, Poison = { 0.30, 0.80, 0.30 } }
local CURE_S = 18
_G["BINDING_NAME_CLICK MeniscusQuickCure:LeftButton"] = "Quick Cure (cure yourself)"
-- Each kind of affliction has its own light, and something that comes off
-- that light (0.1.676, asked for: "disease can be a kind of yellowish-green
-- smoke that comes off the light pulse"):
--   Disease  a sickly yellow-green light; a thin ring of murky dust off the edge
--   Poison   a vivid green light; small bubbles, bursting
--   Curse    a violet light; dark wisps, curling
--   Magic    a blue light; quick glints
-- (each kicked out from all round the edge at every pulse: see Draw)
-- The ring keeps the kind's usual colour (CURE_TINT, as on the game's own
-- debuff borders). Where the kind is hidden (in a fight it can be): gold,
-- and nothing comes off it.
local CURE_FX = {
    Disease = { light = { 0.80, 0.84, 0.34 }, mote = { 0.62, 0.72, 0.22 }, how = "smoke" },
    Poison  = { light = { 0.36, 0.90, 0.42 }, mote = { 0.42, 0.95, 0.48 }, how = "bubbles" },
    Curse   = { light = { 0.70, 0.42, 1.00 }, mote = { 0.50, 0.24, 0.84 }, how = "wisps" },
    Magic   = { light = { 0.46, 0.70, 1.00 }, mote = { 0.80, 0.91, 1.00 }, how = "glints" },
}
local CURE_PERIOD = 2.2 -- seconds from one pulse of light to the next
-- (The same scatter every time for a given mote and pulse: no state kept.)
local function cureRnd(i, k)
    local v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v)
end
-- ── Quick Cure, drawn by the game (0.1.693) ─────────────────────────────────
-- An addon may not READ a debuff in a fight (CLAUDE.md, "Quick Cure": every
-- road to it is closed on purpose). But the game will
-- SHOW one for it: an "aura container" is given a unit and a filter, and the
-- game itself tracks, filters and draws what matches, in a fight as out of
-- one. So the pill and the chips are no longer drawn by this addon at all.
-- For you and for each of the party:
--   * a container with a SLOT for each kind of affliction you have a cure
--     for (filter "HARMFUL|RAID", what the game says you can dispel,
--     narrowed to that kind: both must hold, as they had to before);
--   * each slot's aura button (the game's own) is dressed ONCE, as it is
--     made, as the whole face for that kind: ring, fill, the words, the
--     picture (which the game fills in), the light, and what comes off the
--     light. Light and motes are animations, which the game starts when the
--     button appears and stops when it goes: no script of ours may run on
--     an aura button, and in a fight it may not even be touched;
--   * over them, unseen, the casting button fixed on that unit, as before.
--     It is there for the whole of every fight; out of one, only while you
--     have something to cure (that much can still be read, out of a fight).
-- All of this is from the game's own source for this very build (1.60.1
-- 71091: the public mirror Gethe/wow-ui-source, branch "forever", folder
-- Blizzard_AuraContainer), not from trying things:
--   * a slot shows the first aura that passes its filter string and its
--     candidate filters; `includeDispelTypes` / `excludeDispelTypes` are
--     maps keyed by the kind's name ("Magic", "Curse", "Disease", "Poison");
--   * whatever is handed to an aura button (picture, animation groups) must
--     be a child of that button, however deep, and an animation's target
--     too; nothing can be added to a group once it is handed over;
--   * the button is shown with a hidden yes-or-no, so nothing can ask it
--     whether it is shown, in a fight or out of one; and while auras are
--     secret an addon is refused every call on it. So: dressed in the
--     `initializeFrame` callback, which the game runs before that begins;
--   * aura buttons pass all mouse input on (the game makes them), so the
--     casting button could lie under them; it lies over them, to be sure.
-- The animations are written so as not to lean on what is not known of the
-- game's animator: every animated thing has ONE fade, which ends at the
-- strength the thing has at rest; a mote that must fade in and then out is
-- two things (a frame that fades in, holding a picture that fades out).
-- The same faces are built on plain frames for `/men cure show`, so that
-- how they look can be judged without catching anything.
local function cureEdge(frac, w, h)
    local r = h / 2
    local straight = math.max(0, w - h)
    local cap = math.pi * r
    local at = (frac % 1) * (2 * straight + 2 * cap)
    if at < straight then return -straight / 2 + at, r, 0, 1 end
    at = at - straight
    if at < cap then
        local th = math.pi / 2 - at / r
        return straight / 2 + r * math.cos(th), r * math.sin(th), math.cos(th), math.sin(th)
    end
    at = at - cap
    if at < straight then return straight / 2 - at, -r, 0, -1 end
    at = at - straight
    local th = -math.pi / 2 - at / r
    return -straight / 2 + r * math.cos(th), r * math.sin(th), math.cos(th), math.sin(th)
end
-- One mote's whole life in numbers (the sums are cureMotes' own, with the
-- scatter fixed: an animation is the same at every pulse). From the middle
-- of a face w by h: where it starts (x, y), how far it goes (dx, dy), its
-- size and how it swells, how strong, when after the pulse and for how long.
local function cureMote(fx, i, n, w, h)
    local how = fx.how
    local r1, r2, r3 = cureRnd(i, 3), cureRnd(i + 7, 3), cureRnd(i + 13, 3)
    local ex, ey, nx, ny = cureEdge((i - 1 + 0.8 * r1) / n, w, h)
    local m = { r = fx.mote[1], g = fx.mote[2], b = fx.mote[3] }
    if how == "smoke" then
        -- (the dust of 0.1.687: tight to the edge, faint, rising a touch)
        local k = h < 22 and 0.6 or 1
        ex, ey, nx, ny = cureEdge((i - 1 + 1.6 * (r1 - 0.5)) / n, w, h)
        m.delay, m.life = 0.18 * r3, 1.8 + 0.2 * r2
        m.x, m.y = ex + nx * 2 * k, ey + ny * 2 * k
        m.dx, m.dy = nx * (3 + 3 * r3) * k, ny * (3 + 3 * r3) * k + (4 + 3 * r2) * k
        m.w = 26 * k
        m.h = m.w * (0.40 + 0.18 * r3)
        m.grow = (36 + 6 * r2) / 26
        m.rot = math.atan2(ny, nx) + math.pi / 2 + (r2 - 0.5) * 0.7
        m.a, m.rise = 0.17, 0.18
        m.file, m.blend = "smoke" .. (1 + i % 4) .. ".tga", "BLEND"
        m.r, m.g, m.b = 0.60 + 0.08 * r2, 0.64 + 0.08 * r3, 0.36 + 0.08 * r1
        m.ease, m.swell = "OUT", "OUT"
    elseif how == "bubbles" then
        local out = 12 + 10 * r2
        m.delay, m.life = 0.14 * r3, 0.8 + 0.4 * r2
        m.x, m.y, m.dx, m.dy = ex, ey, nx * out, ny * out
        m.w = 3 + 3 * r2
        m.h = m.w
        m.grow = 1.5 -- (it bursts: wider at the last)
        m.a, m.rise = 0.85, 0.06
        m.file, m.blend = "circle.tga", "ADD"
        m.ease, m.swell, m.fall = "OUT", "IN", "IN"
    elseif how == "wisps" then
        local out, side = 15 + 11 * r2, math.sin(4 + i * 2) * 5 -- (it curls as it goes)
        m.delay, m.life = 0.10 * r3, 1.2 + 0.4 * r2
        m.x, m.y, m.dx, m.dy = ex, ey, nx * out - ny * side, ny * out + nx * side
        m.w, m.h = 8, 8
        m.grow = 19 / 8
        m.a, m.rise = 0.66, 0.12
        m.file, m.blend = "spot.tga", "BLEND"
        m.ease = "OUT"
    else -- glints
        local out = 9 + 6 * r2
        m.delay, m.life = 0.45 * r3, 0.42
        m.x, m.y, m.dx, m.dy = ex + nx * 3, ey + ny * 3, nx * out, ny * out
        m.w = (3 + 3 * r1) * 1.3
        m.h = m.w
        m.grow = 1
        m.a, m.rise = 0.95, 0.5
        m.file, m.blend = "circle.tga", "ADD"
        m.fall = "IN"
    end
    return m
end
-- A face, on f (an aura button of the game's, or a plain frame): what is
-- always there. o = { kind (nil: gold, for "anything else"), chip, w, h,
-- level (f's own), under (the level for what comes off it: behind it) }.
local function cureFace(f, o)
    local kind, w, h = o.kind, o.w, o.h
    local F = { kind = kind, chip = o.chip and true or false, w = w, h = h, level = o.level, under = o.under,
                loops = {}, arrives = {}, motes = {} }
    local c = (kind and CURE_TINT[kind]) or GOLD
    local mask = f:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "circle.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if F.chip then
        F.ring = f:CreateTexture(nil, "BACKGROUND")
        F.ring:SetAllPoints()
        F.ring:SetTexture(MEDIA .. "circle.tga")
        F.ring:SetVertexColor(c[1], c[2], c[3], 1)
        mask:SetPoint("TOPLEFT", 2, -2)
        mask:SetPoint("BOTTOMRIGHT", -2, 2)
        F.hint = ns:CreateText(f, 8)
        F.hint:SetPoint("CENTER", f, "BOTTOMRIGHT", -1, 2)
        F.hint:SetShadowOffset(1, -1)
        F.hint:SetShadowColor(0, 0, 0, 1)
    else
        ns.RoundedRect(f, -8, 0, h / 2, c[1], c[2], c[3], 1)
        ns.RoundedRect(f, -7, 1.5, h / 2 - 1.5, 0.06, 0.06, 0.07, 0.97)
        mask:SetSize(h - 6, h - 6)
        mask:SetPoint("LEFT", 3, 0)
        -- What it says is the DEBUFF's name, written by the game (see
        -- cureAdopt); F.text, small at the right, only says when the cure
        -- is on the right button.
        F.text = ns:CreateText(f, 9)
        F.text:SetPoint("RIGHT", f, "RIGHT", -(h / 2) + 2, 0)
        F.text:SetTextColor(1, 1, 1, 0.55)
        F.text:SetWordWrap(false)
        F.name = ns:CreateText(f, 11)
        F.name:SetPoint("LEFT", mask, "RIGHT", 6, 0)
        F.name:SetPoint("RIGHT", F.text, "LEFT", -4, 0)
        F.name:SetJustifyH("LEFT")
        F.name:SetWordWrap(false)
    end
    F.icon = f:CreateTexture(nil, "ARTWORK")
    F.icon:SetAllPoints(mask)
    F.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    F.icon:AddMaskTexture(mask)
    return F
end
-- The light, and what comes off it. Arriving, a strong flash; then a
-- fainter pulse every CURE_PERIOD seconds, each kicking the kind's motes
-- off the edge. F.arrives: groups to play as it arrives; F.loops: groups
-- that run for as long as it is seen.
local function cureFaceFx(f, F)
    local kind, w, h = F.kind, F.w, F.h
    local c = (kind and CURE_TINT[kind]) or GOLD
    local fx = kind and CURE_FX[kind] or nil
    local lt = fx and fx.light or nil
    local function looped(region)
        local ag = region:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        F.loops[#F.loops + 1] = ag
        return ag
    end
    local function once(region)
        local ag = region:CreateAnimationGroup()
        F.arrives[#F.arrives + 1] = ag
        return ag
    end
    -- (rest: idle time after it, which is how every looped group is made
    -- exactly CURE_PERIOD long, so that light and motes keep one clock)
    local function fade(ag, from, to, dur, delay, smooth, rest)
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(from)
        a:SetToAlpha(to)
        a:SetDuration(dur)
        if delay and delay > 0 then a:SetStartDelay(delay) end
        if smooth then a:SetSmoothing(smooth) end
        if rest and rest > 0 then a:SetEndDelay(rest) end
        return a
    end
    local function swell(ag, to, dur, delay, smooth)
        local a = ag:CreateAnimation("Scale")
        a:SetScaleFrom(1, 1)
        a:SetScaleTo(to, to)
        a:SetDuration(dur)
        if delay and delay > 0 then a:SetStartDelay(delay) end
        if smooth then a:SetSmoothing(smooth) end
        return a
    end
    if F.chip then
        local l = lt or c
        local br, bg, bb = l[1] + (1 - l[1]) * 0.4, l[2] + (1 - l[2]) * 0.4, l[3] + (1 - l[3]) * 0.4
        local function burst(size)
            local t = f:CreateTexture(nil, "BACKGROUND", nil, -1)
            t:SetTexture(MEDIA .. "spot.tga")
            t:SetBlendMode("ADD")
            t:SetPoint("CENTER")
            t:SetSize(size, size)
            t:SetVertexColor(br, bg, bb)
            t:SetAlpha(0)
            return t
        end
        -- Arriving: a burst of light opens behind it, and its picture
        -- goes white for a moment.
        local g1 = once(burst(w * 2.4))
        fade(g1, 1, 0, 0.55, 0, "OUT")
        swell(g1, 4.6 / 2.4, 0.55)
        local white = f:CreateTexture(nil, "OVERLAY")
        white:SetTexture(MEDIA .. "circle.tga")
        white:SetBlendMode("ADD")
        white:SetAllPoints()
        white:SetAlpha(0)
        fade(once(white), 1, 0, 0.32)
        -- While it waits: a smaller burst at every pulse, and the ring breathes.
        local g2 = looped(burst(w * 1.8))
        fade(g2, 0.55, 0, 0.7, 0, "OUT", CURE_PERIOD - 0.7)
        swell(g2, 3.4 / 1.8, 0.7)
        local gb = F.ring:CreateAnimationGroup()
        gb:SetLooping("BOUNCE")
        fade(gb, 1, 0.25, 0.63, 0, "IN_OUT")
        F.loops[#F.loops + 1] = gb
    else
        -- (the light a little towards white: a flash, not a wash of colour)
        local tr, tg, tb = 1, 1, 1
        if lt then tr, tg, tb = lt[1] + (1 - lt[1]) * 0.3, lt[2] + (1 - lt[2]) * 0.3, lt[3] + (1 - lt[3]) * 0.3 end
        local function flash()
            local host = CreateFrame("Frame", nil, f)
            host:SetAllPoints(f)
            host:SetFrameLevel(F.level + 1)
            ns.RoundedRect(host, 6, 0, h / 2, tr, tg, tb, 1, "OVERLAY")
            host:SetAlpha(0)
            return host
        end
        fade(once(flash()), 0.9, 0, 0.55, 0, "OUT")
        fade(looped(flash()), 0.42, 0, 0.7, 0, "OUT", CURE_PERIOD - 0.7)
    end
    if not fx then return end
    local n = F.chip and 8 or 14
    for i = 1, n do
        local m = cureMote(fx, i, n, w, h)
        -- (A frame that fades IN, at rest full; in it a picture that fades
        -- OUT, at rest nothing. Behind the face: smoke is large.)
        local host = CreateFrame("Frame", nil, f)
        host:SetFrameLevel(F.under)
        host:SetSize(m.w, m.h)
        host:SetPoint("CENTER", f, "CENTER", m.x, m.y)
        local t = host:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(MEDIA .. m.file)
        t:SetBlendMode(m.blend)
        if m.rot then pcall(t.SetRotation, t, m.rot) end
        t:SetVertexColor(m.r, m.g, m.b)
        t:SetAlpha(0) -- (after the colour, always: the two are one value)
        local rest = math.max(0, CURE_PERIOD - m.delay - m.life)
        local g = looped(host)
        fade(g, 0, 1, m.life * m.rise, m.delay, "OUT")
        local mv = g:CreateAnimation("Translation")
        mv:SetOffset(m.dx, m.dy)
        mv:SetDuration(m.life)
        if m.delay > 0 then mv:SetStartDelay(m.delay) end
        if m.ease then mv:SetSmoothing(m.ease) end
        if rest > 0 then mv:SetEndDelay(rest) end
        if m.grow ~= 1 then swell(g, m.grow, m.life, m.delay, m.swell) end
        fade(looped(t), m.a, 0, m.life, m.delay, m.fall, rest)
        F.motes[i] = { host = host, move = mv }
    end
    -- The pill's width follows its words: the motes are set round it again.
    function F.reseat(w2)
        F.w = w2
        for i, mo in ipairs(F.motes) do
            local m = cureMote(fx, i, #F.motes, w2, h)
            mo.host:ClearAllPoints()
            mo.host:SetPoint("CENTER", f, "CENTER", m.x, m.y)
            mo.move:SetOffset(m.dx, m.dy)
        end
    end
end
-- A face handed to the game's aura button f. Returns the first refusal's
-- words, if any. (What arrives is put in both lists: the game plays the
-- "assigned" ones a moment BEFORE it shows the button, and whether a group
-- can start on a thing not yet shown is not known; the "shown" ones are
-- played right after.)
local function cureAdopt(f, F)
    local err
    local function try(fn, ...)
        if type(fn) ~= "function" then err = err or "a way is missing" return end
        local ok, e = pcall(fn, f, ...)
        if not ok then err = err or tostring(e) end
    end
    try(f.SetIcon, F.icon)
    -- (the debuff's own name; from here on the string is the game's to write)
    if F.name then try(f.SetSpellName, F.name) end
    for _, g in ipairs(F.arrives) do
        try(f.AddAuraAssignedAnimation, g)
        try(f.AddAuraShownAnimation, g)
    end
    for _, g in ipairs(F.loops) do try(f.AddAuraShownAnimation, g) end
    return err
end

function UF:BuildCure()
    if self.db.cure == false or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local _, cls = UnitClass("player")
    local list = CURES[cls or ""]
    if not list then return end
    if MinimalUIDB then
        -- (the records of the roads that are closed, and of the first try: done with)
        for _, k in ipairs({ "cureapi", "cureSurveyDone", "cureagree", "cureways", "curefight", "cureprobe",
                             "cureerr", "cureerr2", "curediag", "curecontainer" }) do
            MinimalUIDB[k] = nil
        end
    end
    local function note(str)
        if not MinimalUIDB then return end
        local t = type(MinimalUIDB.curecontainer) == "table" and MinimalUIDB.curecontainer or {}
        MinimalUIDB.curecontainer = t
        if #t < 40 then t[#t + 1] = (InCombatLockdown() and "[fight] " or "[calm] ") .. tostring(str):sub(1, 400) end
    end
    -- (0.1.711: the display of before 0.1.693, drawn by this addon and
    -- blind to what is caught in a fight, is gone: the player has seen this
    -- one work. It is in the history at the tag stage/before-cure-old-removed.)
    self.db.cureOld = nil
    local okC, cont = pcall(CreateFrame, "AuraContainer", "MeniscusCureAuras", UIParent, "CustomAuraContainerTemplate")
    if not okC or type(cont) ~= "table" or type(cont.AddAuraSlot) ~= "function" then
        note("no aura container to be had (" .. tostring(cont) .. "): no Quick Cure")
        return
    end

    local typeSpell, spells = {}, {}       -- kind -> spell; the (up to two) spells, left then right
    local function known(name)
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if not ok or type(info) ~= "table" or type(info.spellID) ~= "number" then return false end
        local k
        if C_SpellBook and C_SpellBook.IsSpellKnown then k = select(2, pcall(C_SpellBook.IsSpellKnown, info.spellID)) end
        if k == nil and IsSpellKnown then k = select(2, pcall(IsSpellKnown, info.spellID)) end
        return k ~= false
    end
    local function resolve()
        for k in pairs(typeSpell) do typeSpell[k] = nil end
        for i = #spells, 1, -1 do spells[i] = nil end
        for _, e in ipairs(list) do
            if known(e[1]) then
                local used = false
                for i = 2, #e do
                    if not typeSpell[e[i]] then typeSpell[e[i]] = e[1]; used = true end
                end
                if used and #spells < 2 then spells[#spells + 1] = e[1] end
            end
        end
    end
    resolve()
    -- Every kind this class has any cure for, in the list's order. A slot
    -- is made for a kind once you have a cure for it (now, or out of a
    -- fight after you learn one): what is seen is what the game says you
    -- can dispel AND is of a kind you hold the spell for, as it was when
    -- this addon did the reading.
    local kinds = {}
    do
        local seen = {}
        for _, e in ipairs(list) do
            for i = 2, #e do
                if not seen[e[i]] then seen[e[i]] = true; kinds[#kinds + 1] = e[i] end
            end
        end
    end
    -- What a face says besides the debuff's name: which button the cure
    -- is on, when it is the right one.
    local function sayFor(kind)
        local spell = typeSpell[kind]
        return (spell and spells[2] ~= nil and spell == spells[2]) and "right-click" or ""
    end
    local function hintFor(kind)
        local spell = typeSpell[kind]
        return (spell and spells[2] ~= nil and spell == spells[2]) and "R" or ""
    end

    local onPress = true
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and v == false then onPress = false end
    end
    local PH, LV = 24, 10
    local faces, casters, units = {}, {}, {}

    -- One unit's share: a container c, whose slots lie on `anchor` (that
    -- unit's casting button).
    local function unitShare(c, unit, anchor, isChip, w, h, level)
        local U = { c = c, unit = unit, anchor = anchor, chip = isChip, w = w, h = h, level = level, n = 0,
                    has = {}, on = {}, tried = {} }
        for _, st in ipairs({ { "size", c.SetSize, 1, 1 }, { "place", c.SetPoint, "CENTER", anchor, "CENTER", 0, 0 },
                              { "level", c.SetFrameLevel, level }, { "unit", c.SetUnit, unit } }) do
            local ok, e = pcall(st[2], c, unpack(st, 3))
            if not ok then U.refused = U.refused or (st[1] .. ": " .. tostring(e)) end
        end
        -- (not in Edit Mode's sample auras: a pill would stand there for a made-up debuff)
        if c.SetEditModePreviewEnabled then pcall(c.SetEditModePreviewEnabled, c, false) end
        units[#units + 1] = U
        return U
    end
    -- A slot for one kind, dressed as it is made. Returns the face, or
    -- nil and the refusal's words.
    local function slotFor(U, kind)
        U.n = U.n + 1
        local lv = U.level + 2 * U.n
        local F, errB, errA
        local function dress(fr)
            local okB, eB = pcall(function()
                fr:SetAllPoints(U.anchor)
                fr:SetFrameLevel(lv)
                F = cureFace(fr, { kind = kind, chip = U.chip, w = U.w, h = U.h, level = lv, under = U.level })
                F.said = F.chip and hintFor(kind) or sayFor(kind)
                local words = F.text or F.hint
                words:SetText(F.said)
                -- (until the game writes the debuff's name, or should it refuse to: the cure's)
                if F.name then F.name:SetText(typeSpell[kind] or "") end
            end)
            if not okB then errB = eB or "?" return end
            -- (The light and motes apart: if they fail, the face still stands.)
            local okX, eX = pcall(cureFaceFx, fr, F)
            if not okX then errB = eX end
            errA = cureAdopt(fr, F)
            -- (its tooltip is the game's own, of the debuff itself)
            if fr.SetTooltipAnchorPoint then
                pcall(fr.SetTooltipAnchorPoint, fr, U.chip and "ANCHOR_RIGHT" or "ANCHOR_TOP", 0, U.chip and 0 or 6)
            end
        end
        local ok, e = pcall(U.c.AddAuraSlot, U.c, kind, "HARMFUL|RAID", {
            candidateFilters = { includeDispelTypes = { [kind] = true } },
            initializeFrame = dress,
        })
        if not ok then return nil, "slot " .. kind .. ": " .. tostring(e) end
        -- (Should the game not have run the dressing as it made the frame:
        -- on the frame it hands back, which is open to us out of a fight.)
        if not F and not errB and type(e) == "table" then
            dress(e)
            if F then note(kind .. ": dressed after the making, not in it") end
        end
        if not F then return nil, "dressing " .. kind .. ": " .. tostring(errB) end
        faces[#faces + 1] = F
        return F, (errB and ("light of " .. kind .. ": " .. tostring(errB))) or (errA and ("handing over " .. kind .. ": " .. tostring(errA))) or nil
    end
    -- Every unit has a slot for every kind you now have a cure for; one
    -- whose cure is gone is switched off. Out of a fight only: nothing of
    -- the game's can be dressed in one.
    local function slots()
        for _, U in ipairs(units) do
            local made, was = 0, U.made or 0
            for _, kind in ipairs(kinds) do
                local want = typeSpell[kind] ~= nil
                -- (once: a slot the game would not make is not asked for again and again)
                if want and not U.has[kind] and not U.tried[kind] then
                    U.tried[kind] = true
                    local F, e = slotFor(U, kind)
                    if e then U.refused = U.refused or e end
                    if F then U.has[kind] = true; U.on[kind] = true end
                end
                if U.has[kind] and U.on[kind] ~= want then
                    U.on[kind] = want
                    if U.c.SetAuraSlotEnabled then pcall(U.c.SetAuraSlotEnabled, U.c, kind, want) end
                end
                if U.has[kind] and want then made = made + 1 end
            end
            U.made = made
            if made ~= was or (U.refused and not U.told) then
                U.told = U.refused ~= nil
                local wantN = 0
                for _, kind in ipairs(kinds) do if typeSpell[kind] then wantN = wantN + 1 end end
                note(tostring(U.unit) .. ": " .. made .. " of " .. wantN .. " faces" .. (U.refused and ("; REFUSED " .. U.refused) or ""))
            end
        end
    end

    -- The casting button, for you: left of your cast bar.
    local pill = CreateFrame("Button", "MeniscusQuickCure", UIParent, "SecureActionButtonTemplate")
    pill:SetSize(150, PH)
    -- (MEDIUM: at HIGH it lay over the full-screen map. Skins.lua puts it
    -- and the container lower still while that map is open.)
    pill:SetFrameStrata("MEDIUM")
    pill:SetFrameLevel(LV + 14)
    pill:RegisterForClicks(onPress and "AnyDown" or "AnyUp")
    pill:SetAttribute("unit", "player")
    -- (So that the game's button under it still hears the mouse come and
    -- go: its tooltip. The game lets this be set out of a fight only.)
    if pill.SetPropagateMouseMotion and not InCombatLockdown() then pcall(pill.SetPropagateMouseMotion, pill, true) end
    if not InCombatLockdown() then pill:Hide() end
    casters[1] = pill
    local function seatPill()
        if InCombatLockdown() then return end
        pill:ClearAllPoints()
        -- (Level with your cast bar, its right end a little short of the
        -- bar's left end. Worked out on the screen, not hung on the bar,
        -- so that the bar stays free to move in a fight.)
        local CBm = ns.modules.CastBars
        local bar = CBm and CBm.player
        if bar and bar.GetLeft then
            local okL, left = pcall(bar.GetLeft, bar)
            local okC, _, cy = pcall(bar.GetCenter, bar)
            if okL and okC and type(left) == "number" and type(cy) == "number"
                and not issecretvalue(left) and not issecretvalue(cy) then
                local k = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
                pill:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", left * k - 10, cy * k)
                return
            end
        end
        local QBm = ns.modules.QuickBuff
        local qb = _G.MinimalUIQuickBuff
        local dome = _G.MinimalUI_MinimapDome
        if dome and dome:IsShown() then
            pill:SetPoint("BOTTOM", dome, "TOP", 0, 8)
        elseif qb and QBm and QBm.Place and pcall(QBm.Place) and qb:GetPoint(1) then
            pill:SetPoint("BOTTOM", qb, "TOP", 0, 6)
        else
            pill:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150)
        end
    end
    -- As wide as the longest thing it may have to say.
    local hold = CreateFrame("Frame", nil, UIParent)
    hold:Hide()
    local ruler = ns:CreateText(hold, 11)
    local function widthNow()
        local widest = 0
        local function measure(str)
            ruler:SetText(str)
            local okW, wv = pcall(ruler.GetStringWidth, ruler)
            if okW and type(wv) == "number" and not issecretvalue(wv) and wv > widest then widest = wv end
        end
        -- (A debuff's name can't be measured, and in a fight the pill can't
        -- be resized: room for some eighteen letters, longer names are cut.)
        if spells[1] then measure(spells[1]) end
        if spells[2] then measure(spells[2]) end
        ruler:SetText("")
        return math.max(170, math.floor(3 + (PH - 6) + 6 + widest + PH / 2 + 0.5)) + (spells[2] and 52 or 0)
    end
    local W = widthNow()
    if not InCombatLockdown() then pill:SetWidth(W) end
    seatPill()
    pcall(cont.SetFrameStrata, cont, "MEDIUM")
    unitShare(cont, "player", pill, false, W, PH, LV)
    self.cureContainer = cont

    -- The party: a casting button beside each one's bar (their buffs start
    -- past it), and a container of their own.
    for i, pf in ipairs(self.party or {}) do
        if pf.healthPill then
            local unit = pf.realUnit or pf.unit
            local b = CreateFrame("Button", "MeniscusCure" .. i, pf, "SecureActionButtonTemplate")
            b:SetSize(CURE_S, CURE_S)
            b:SetFrameLevel(pf:GetFrameLevel() + 22)
            b:RegisterForClicks(onPress and "AnyDown" or "AnyUp")
            b:SetAttribute("unit", unit)
            if b.SetPropagateMouseMotion and not InCombatLockdown() then pcall(b.SetPropagateMouseMotion, b, true) end
            local skip = pf.orbSide == "RIGHT" and (pf.healthPill:GetHeight() + 4) or 0
            b:SetPoint("LEFT", pf.healthPill, "RIGHT", 5 + skip, 0)
            pf.cureSlot = true -- (Auras.lua starts the aura row past it)
            casters[#casters + 1] = b
            local okP, pc = pcall(CreateFrame, "AuraContainer", "MeniscusCureAuras" .. i, pf, "CustomAuraContainerTemplate")
            if okP and type(pc) == "table" then
                unitShare(pc, unit, b, true, CURE_S, CURE_S, pf:GetFrameLevel() + 6)
            else
                note(tostring(unit) .. ": no container (" .. tostring(pc) .. ")")
            end
        end
    end

    -- The slots, now: this is the one moment at which the game lets them be
    -- dressed whatever else is going on (even a reload in mid-fight).
    do
        local ok, e = pcall(slots)
        if not ok then note("slots: " .. tostring(e)) end
    end

    -- Spells on the buttons, the pill's width, and what the faces say: out
    -- of a fight (the buttons are casting buttons; the faces are the
    -- game's, and closed to us in one).
    local stale = false
    local function assign()
        if InCombatLockdown() then stale = true return end
        stale = false
        resolve()
        for _, b in ipairs(casters) do
            for n = 1, 2 do
                b:SetAttribute("type" .. n, spells[n] and "spell" or nil)
                b:SetAttribute("spell" .. n, spells[n])
            end
        end
        W = widthNow()
        pill:SetWidth(W)
        seatPill()
        -- (a new pill face is made to today's width; the others are refitted below)
        for _, U in ipairs(units) do
            if not U.chip then U.w = W end
        end
        if not pcall(slots) then stale = true end
        for _, F in ipairs(faces) do
            local say = F.chip and hintFor(F.kind) or sayFor(F.kind)
            if say ~= F.said then
                local words = F.text or F.hint
                if pcall(words.SetText, words, say) then F.said = say else stale = true end
            end
            if not F.chip and F.reseat and F.w ~= W and not pcall(F.reseat, W) then stale = true end
        end
    end

    -- Is the casting pill wanted? In a fight: always (it can't be brought
    -- out once one is on). Out of one: while you have something a face
    -- would show for, which can be read then; and where even that is
    -- refused (auras can be secret out of a fight too), it stays, to be
    -- safe.
    local fightOn = false
    local told = {}
    local function wanted()
        if #spells == 0 then return false end
        if fightOn or InCombatLockdown() then return true end
        for idx = 1, 8 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", idx, "HARMFUL|RAID")
            if not ok then return true end
            if not a then return false end
            local d = a.dispelName
            if issecretvalue(d) or (type(d) == "string" and typeSpell[d]) then
                -- (Once a session for each kind, in the record: nothing can
                -- ask the game's face whether it is showing, so that this
                -- was read is what "nothing appeared" can be held against.)
                local k = issecretvalue(d) and "a hidden kind" or d
                if not told[k] then
                    told[k] = true
                    note("read on you, out of a fight: " .. k .. " (its face should have shown)")
                end
                return true
            end
        end
        return false
    end
    local function updatePill()
        if InCombatLockdown() then return end
        local want = wanted()
        if want and not pill:IsShown() then
            seatPill()
            pill:Show()
        elseif not want and pill:IsShown() then
            pill:Hide()
        end
    end

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED",
                         "PLAYER_REGEN_DISABLED", "ENCOUNTER_START" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
    local secretNoted = false
    ev:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_DISABLED" or e == "ENCOUNTER_START" then
            -- A fight is starting (the lockdown has not begun yet): the
            -- casting pill is put in its place for the length of it.
            fightOn = true
            if not InCombatLockdown() and #spells > 0 then
                seatPill()
                pill:Show()
            end
            if not secretNoted then
                C_Timer.After(1.5, function()
                    if secretNoted or not InCombatLockdown() then return end
                    secretNoted = true
                    local okSec, sec = pcall(function() return C_Secrets.ShouldAurasBeSecret() end)
                    note("auras secret in a fight: " .. (okSec and tostring(sec) or "could not ask")
                        .. "; the casting pill is " .. (pill:IsShown() and "there" or "NOT there"))
                end)
            end
            return
        end
        if e == "UNIT_AURA" then pcall(updatePill) return end
        if e == "PLAYER_REGEN_ENABLED" then fightOn = false end
        if e == "GROUP_ROSTER_UPDATE" then
            -- (someone else may stand behind "party2" now: look again)
            for _, U in ipairs(units) do
                if U.chip and U.c.UpdateAllAuras then pcall(U.c.UpdateAllAuras, U.c) end
            end
        end
        if e ~= "PLAYER_REGEN_ENABLED" or stale then pcall(assign) end
        pcall(updatePill)
    end)
    assign()
    -- (The cast bar is built after this module: the seat, once more.)
    C_Timer.After(3, function() pcall(assign); pcall(updatePill) end)

    -- `/men cure show [disease | poison | curse | magic]`: the
    -- same faces on plain frames, over the pill's place, for a dozen
    -- seconds. Nothing of the game's is touched: how the light and motes
    -- LOOK can be judged without a debuff, apart from whether the game
    -- shows the real thing.
    local shows, showToken = {}, 0
    self.curePreview = function(arg)
        arg = (arg or ""):lower()
        local kind
        for k in pairs(CURE_FX) do
            if arg ~= "" and k:lower():find(arg, 1, true) == 1 then kind = k end
        end
        if not kind then kind = typeSpell.Disease and "Disease" or kinds[1] or "Disease" end
        local key = kind
        local S = shows[key]
        if not S then
            local okI, info = pcall(C_Spell.GetSpellInfo, typeSpell[kind] or spells[1] or "")
            local pic = okI and type(info) == "table" and info.iconID or 134400
            S = {}
            local function sample(isChip, w, h, x)
                local fr = CreateFrame("Frame", nil, UIParent)
                fr:SetFrameStrata("HIGH")
                fr:SetFrameLevel(20)
                fr:SetSize(w, h)
                fr:SetPoint("BOTTOMLEFT", pill, "TOPLEFT", x, 44)
                fr:Hide()
                local F = cureFace(fr, { kind = kind, chip = isChip, w = w, h = h, level = 20, under = 19 })
                local okX, e = pcall(cureFaceFx, fr, F)
                if not okX then ns:Print("Quick Cure sample:", tostring(e)) end
                F.icon:SetTexture(pic)
                if F.text then F.text:SetText(sayFor(kind)) end
                if F.name then F.name:SetText("The " .. kind:lower() .. "'s name") end
                if F.hint then F.hint:SetText(hintFor(kind)) end
                -- (which is which: the chip is small enough to be taken for something else)
                local cap = ns:CreateText(fr, 10)
                cap:SetTextColor(1, 1, 1, 0.7)
                cap:SetPoint("BOTTOM", fr, "TOP", 0, 5)
                cap:SetText(isChip and "on a party member" or "on you")
                S[#S + 1] = { frame = fr, face = F }
            end
            sample(false, W, PH, 0)
            sample(true, CURE_S, CURE_S, W + 30)
            shows[key] = S
        end
        showToken = showToken + 1
        local mine = showToken
        for _, other in pairs(shows) do
            for _, s in ipairs(other) do
                for _, g in ipairs(s.face.arrives) do g:Stop() end
                for _, g in ipairs(s.face.loops) do g:Stop() end
                s.frame:Hide()
            end
        end
        for _, s in ipairs(S) do
            s.frame:Show()
            for _, g in ipairs(s.face.arrives) do g:Play() end
            for _, g in ipairs(s.face.loops) do g:Play() end
        end
        ns:Print("Quick Cure sample (" .. key:lower() .. "), 12 seconds, left of your cast bar: the pill as it shows for you, and the small round one as it sits on a party member's frame.")
        C_Timer.After(12, function()
            if mine ~= showToken then return end
            for _, s in ipairs(S) do
                for _, g in ipairs(s.face.arrives) do g:Stop() end
                for _, g in ipairs(s.face.loops) do g:Stop() end
                s.frame:Hide()
            end
        end)
    end
end

-- /men cure show [kind]   a sample of the pill and a chip, for 12 seconds
ns.commands.cure = function(rest)
    rest = (rest or ""):lower()
    if rest:find("^old") or rest:find("^new") then
        return ns:Print("Quick Cure is drawn by the game; the display of before 0.1.693 was removed in 0.1.711.")
    end
    if UF.curePreview then
        UF.curePreview(rest:match("^show%s*(%a*)") or rest)
    else
        ns:Print("Quick Cure: no sample (it is off, or your class has no cure).")
    end
end

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
    -- (0.1.705) Our own container, drawn by the game in our look (Auras.lua
    -- BuildLiveTarget): it takes the seat, and Blizzard's icons stay unseen
    -- under their ghosted frame. One unbroken run, debuffs first.
    local AU = ns.modules.Auras
    local live = AU and AU.liveTarget
    if live and t then
        local strip = self.targetStrip
        pcall(function()
            live:SetFlowLayoutAnchorPoint(strip and "TOPLEFT" or "BOTTOMLEFT")
            live:ClearAllPoints()
            if strip then
                -- under the pill, from beside the portrait that hangs from its middle
                live:SetPoint("TOPLEFT", t.healthPill, "BOTTOM", t.avatar.D / 2 + 6, -4)
            else
                live:SetPoint("BOTTOMLEFT", t.healthPill, "TOPLEFT", 0, 5)
            end
        end)
        tcSeat = nil
        if root and root.GetAuraContainer then
            local okB, cont = pcall(root.GetAuraContainer, root)
            if okB and type(cont) == "table" and cont.SetAlpha then pcall(cont.SetAlpha, cont, 0) end
        end
        self.targetAurasRight = false
        self.liveTargetCont = live
        return
    end
    if not (root and t and root.__muiGhost and root.GetAuraContainer) then return end
    local ok, cont = pcall(root.GetAuraContainer, root)
    if not ok or type(cont) ~= "table" or not cont.SetPoint then return end
    -- Which corner the icons flow from decides which corner gets pinned.
    local corner = "BOTTOMLEFT"
    local okA, ap = pcall(function() return cont.GetFlowLayoutAnchorPoint and cont:GetFlowLayoutAnchorPoint() end)
    if okA and type(ap) == "string" and not issecretvalue(ap) and ap ~= "" then corner = ap end
    local right = corner:find("RIGHT") ~= nil
    local down = corner:find("TOP") ~= nil
    self.targetAurasRight = right -- (the Inspect button takes the other side of the portrait)
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
    -- Party members' pets: a tiny pill (as your own pet's) tucked under the
    -- right end of its owner's bar, below the row of auras. Shown by the
    -- game only while that member has a pet out.
    self.partyPets = {}
    if db.partyPets ~= false then
        for i = 1, 4 do
            local ok, pf = pcall(create, "partypet" .. i, "PartyPet" .. i, { size = "tiny", avatar = "flat",
                side = "LEFT", watch = true, events = { "UNIT_PET", "GROUP_ROSTER_UPDATE" } })
            if ok and pf then
                pf:SetPoint("TOPLEFT", self.party[i].healthPill, "BOTTOMRIGHT", 18, 0)
                self.partyPets[i] = pf
            elseif MinimalUIDB then
                MinimalUIDB.partyPetErr = tostring(pf)
            end
        end
    end
    self:LayoutParty()
    do
        local ok, err = pcall(self.BuildNotes, self)
        if not ok and MinimalUIDB then MinimalUIDB.notesErr = tostring(err) end
        ok, err = pcall(self.BuildCure, self)
        if not ok and MinimalUIDB then MinimalUIDB.cureErr = tostring(err) end
    end
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
    -- A group member's pet is not "in the party" by the game's reckoning,
    -- so it never faded. It fades by its own distance where the game will
    -- say, and by its owner's where it won't.
    local owner
    if type(unit) == "string" then
        local kind, n = unit:match("^(party)pet(%d+)$")
        if not kind then kind, n = unit:match("^(raid)pet(%d+)$") end
        if kind then owner = kind .. n; grouped = true end
    end
    if not grouped then
        if unit == "target" then
            f:SetAlpha(targetInActionRange() == false and OUT_ALPHA or 1)
        else
            f:SetAlpha(1)
        end
        return
    end
    if safeBool(UnitIsConnected, owner or unit) == false then f:SetAlpha(OUT_ALPHA) return end
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if owner and (not ok or (not issecretvalue(inRange) and checked ~= true)) then
        ok, inRange, checked = pcall(UnitInRange, owner)
    end
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
    -- (0.1.710, stage 1 of "polling to events") The game says when a group
    -- member comes into or goes out of range (UNIT_IN_RANGE_UPDATE): that
    -- frame is faded at once, instead of up to a fifth of a second later.
    -- The look five times a second below stays exactly as it was (it also
    -- does the target and the 3D portraits); how often the game speaks is
    -- counted (MinimalUIDB.pollcheck) before anything is slowed down.
    -- "/men poll old" puts the new signals aside.
    local told = CreateFrame("Frame")
    if pcall(told.RegisterEvent, told, "UNIT_IN_RANGE_UPDATE") then
        told:SetScript("OnEvent", function(_, _, unit)
            if (MinimalUIDB and MinimalUIDB.pollOld) or type(unit) ~= "string" or issecretvalue(unit) then return end
            for _, f in ipairs(UF.frames) do
                if f.unit == unit and f:IsShown() then
                    pcall(applyRange, f)
                    if ns.PollNote then ns.PollNote("group range: told by the game") end
                end
            end
        end)
    end
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
