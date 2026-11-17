local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Nameplates: Blizzard's plates restyled in place (they keep all their
-- logic: colors, threat, debuffs, secret-value handling). Health and cast
-- bars become the same pills as the unit frames: dark track, hairline ring,
-- a bright line riding the end of the fill and a soft sheen. Borders and
-- the selection glow go; instead the ring itself says what the plate is:
--   your target   bright ring
--   elite / rare  gold / silver ring (as on the target's portrait)
--   boss          ember ring
-- Names use the theme font, the cast icon is rounded.
-- Forbidden plates (some instanced enemy plates) can't be touched and are
-- left as Blizzard draws them.

local NP = ns:NewModule("Nameplates", { enabled = true })
local MEDIA = "Interface/AddOns/Meniscus/Media/"

local function zero(obj)
    if not obj or obj.__muiZero or not obj.SetAlpha then return end
    obj.__muiZero = true
    obj:SetAlpha(0)
    hooksecurefunc(obj, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
end

-- Pill-ify a StatusBar: mask its fill (and background), add a ring.
-- Re-picks the mask ratio when the bar is resized.
local function pillify(bar)
    if not bar or bar.__muiPill then return end
    bar.__muiPill = true
    local mask = bar:CreateMaskTexture()
    mask:SetAllPoints(bar)
    local ring = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    ring:SetAllPoints(bar)
    ring:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
    bar.__muiRing = ring
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    bg:AddMaskTexture(mask)
    -- Soft sheen toward the top, as on the unit frame pills.
    local sheen = bar:CreateTexture(nil, "OVERLAY", nil, 4)
    sheen:SetAllPoints(bar)
    sheen:SetColorTexture(1, 1, 1, 1)
    pcall(sheen.SetGradient, sheen, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.14))
    sheen:AddMaskTexture(mask)
    -- Bright line riding the end of the fill.
    local edge = bar:CreateTexture(nil, "OVERLAY", nil, 3)
    edge:SetWidth(1.5)
    edge:SetColorTexture(1, 1, 1, 0.45)
    edge:AddMaskTexture(mask)
    local function ride(fl)
        edge:ClearAllPoints()
        edge:SetPoint("TOPRIGHT", fl, "TOPRIGHT")
        edge:SetPoint("BOTTOMRIGHT", fl, "BOTTOMRIGHT")
    end

    local function fit()
        local w, h = bar:GetSize()
        if not w or not h or h <= 0 then return end
        local base = MEDIA .. "pill" .. ns.PillRatio(w, h)
        mask:SetTexture(base .. "_mask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ring:SetTexture(base .. "_ring.tga")
    end
    fit()
    bar:HookScript("OnSizeChanged", fit)

    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetTexture(T.bar)
        fill:AddMaskTexture(mask)
        ride(fill)
    end
    -- Blizzard swaps the fill texture now and then; keep it flat and masked.
    hooksecurefunc(bar, "SetStatusBarTexture", function(self)
        local f = self:GetStatusBarTexture()
        if f and not f.__muiMasked then f.__muiMasked = true; f:AddMaskTexture(mask) end
        if f then ride(f) end
    end)
    if fill then fill.__muiMasked = true end

    -- Hide Blizzard's own background/border pieces.
    for _, key in ipairs({ "border", "Border", "background", "Background", "bgTexture", "BorderShield" }) do
        if key ~= "BorderShield" then zero(bar[key]) end
    end
    for _, r in ipairs({ bar:GetRegions() }) do
        if r ~= fill and r ~= bg and r ~= ring and r ~= sheen and r ~= edge and r:IsObjectType("Texture") then
            local layer = r:GetDrawLayer()
            if layer == "BACKGROUND" or layer == "BORDER" then zero(r) end
        end
    end
end

local function roundIcon(icon)
    if not icon or icon.__muiRound then return end
    icon.__muiRound = true
    local m = icon:GetParent():CreateMaskTexture()
    m:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:AddMaskTexture(m)
end

local function fontOf(fs)
    if not fs or fs.__muiFont then return end
    fs.__muiFont = true
    local _, size, flags = fs:GetFont()
    ns:SetFont(fs, size or 10, flags or "")
end

-- Ring colors by what the plate is (the same palette as the target strip).
local GOLD, SILVER, EMBER = { 0.90, 0.72, 0.30 }, { 0.70, 0.78, 0.92 }, { 0.80, 0.22, 0.14 }
local BRIGHT = { 0.92, 0.92, 0.96 }
local function secret(v) return issecretvalue and issecretvalue(v) end

local function healthBarOf(uf)
    return uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
end

-- unit is the plate's token ("nameplate3"). Anything hidden from addons
-- simply leaves the neutral ring.
local function ringFor(uf, unit)
    local hb = healthBarOf(uf)
    local ring = hb and hb.__muiRing
    if not ring or not unit then return end
    local c = T.border
    local kind = UnitClassification and UnitClassification(unit)
    if type(kind) == "string" and not secret(kind) then
        local lvl = UnitLevel(unit)
        if kind == "worldboss" or (type(lvl) == "number" and not secret(lvl) and lvl < 0) then c = EMBER
        elseif (kind == "elite" or kind == "rareelite") and ns.IsBossUnit and ns.IsBossUnit(unit) then c = EMBER
        elseif kind == "elite" or kind == "rareelite" then c = GOLD
        elseif kind == "rare" then c = SILVER end
    end
    local isTarget = UnitIsUnit(unit, "target")
    if not secret(isTarget) and isTarget then c = BRIGHT end
    ring:SetVertexColor(c[1], c[2], c[3], 1)
end

local function stylePlate(plate, unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local uf = plate.UnitFrame
    if not uf then return end
    if not uf.__mui then
        uf.__mui = true
        local hb = healthBarOf(uf)
        pcall(pillify, hb)
        if uf.HealthBarsContainer then
            zero(uf.HealthBarsContainer.border)
            zero(uf.HealthBarsContainer.background)
        end
        -- Blizzard's own "this is your target" glow and its elite dragon: the
        -- ring carries both now.
        zero(uf.selectionHighlight)
        zero(uf.SelectionHighlight)
        local cf = uf.ClassificationFrame
        if cf then zero(cf.classificationIndicator); zero(cf.ClassificationIndicator) end
        local cb = uf.castBar or uf.CastBar
        if cb then
            pcall(pillify, cb)
            pcall(roundIcon, cb.Icon)
            pcall(fontOf, cb.Text)
            zero(cb.Spark)
        end
        pcall(fontOf, uf.name)
        if uf.name and uf.name.SetShadowOffset then
            uf.name:SetShadowOffset(1, -1)
            uf.name:SetShadowColor(0, 0, 0, 0.9)
        end
    end
    pcall(ringFor, uf, unit or plate.namePlateUnitToken or uf.unit)
end

-- ── Combat numbers ────────────────────────────────────────────────────────
-- Our own floating numbers, in place of the game's world text (which can't
-- be had without its purple "XP: 1,650" as well). On unless switched off;
-- while on, the game's own numbers are turned down (see quietGame).
--   * Over a unit's nameplate: what it takes (damage in the spell school's
--     colour, heals in green, "Miss" / "Dodge" and the like, dim). A
--     critical is larger and lands with a small pop.
--   * By your character: what you take (red, to the left) and heals on you
--     (green, to the right).
-- What the game gives is "this unit took this much" (UNIT_COMBAT), not who
-- dealt it: in a group, a mob's numbers are everyone's.
-- Amounts are hidden values in combat: they are handed straight to the
-- text and never read, so there is no "+" in front and no adding up.
local NUM_POOL, NUM_LIFE, NUM_RISE = 40, 1.05, 44
local SCHOOL_TINT = ns.SCHOOL -- (Theme.lua: one list for the whole addon)
local PET_TINT = { 0.86, 0.74, 0.54 }
-- The kind of damage, as the character panel's resistance emblems (and a
-- blade for physical, a star for holy), drawn just left of the number in
-- the number's own colour. A pilot: the client names one school per hit,
-- so a bleed shows as physical and a poison as nature.
local SCHOOL_ICON = { [1] = "micro_stat_melee.tga", [2] = "micro_buff.tga", [4] = "micro_stat_fire.tga",
    [8] = "micro_stat_nature.tga", [16] = "micro_stat_frost.tga", [32] = "micro_stat_shadow.tga",
    [64] = "micro_stat_arcane.tga" }
local WORDS = { MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", RESIST = "Resist",
    IMMUNE = "Immune", ABSORB = "Absorb", EVADE = "Evade", DEFLECT = "Deflect", REFLECT = "Reflect" }
-- The game's own world text: its damage and healing numbers off, and the
-- rest (the XP line, which has no switch) scaled up so far that the game
-- no longer draws it. (Scaled down to nothing it was still there, tiny;
-- a very large scale is what other players report works.) What was there before is
-- kept, and put back when our numbers are switched off.
local QUIET = { floatingCombatTextCombatDamage_v2 = "0", floatingCombatTextCombatHealing_v2 = "0",
    floatingCombatTextPetMeleeDamage_v2 = "0", floatingCombatTextPetSpellDamage_v2 = "0", WorldTextScale_v2 = "1000", WorldTextScale = "1000" }
local function quietGame(on)
    local db = NP.db
    if on then
        db.cvarsWas = db.cvarsWas or {}
        for name, v in pairs(QUIET) do
            local ok, cur = pcall(GetCVar, name)
            if ok and cur ~= nil then
                if db.cvarsWas[name] == nil then db.cvarsWas[name] = cur end
                if cur ~= v then pcall(SetCVar, name, v) end
            end
        end
    elseif db.cvarsWas then
        for name, v in pairs(db.cvarsWas) do pcall(SetCVar, name, v) end
        db.cvarsWas = nil
    end
end
NP.QuietGame = quietGame

local function buildNumbers()
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetAllPoints()
    host:SetFrameStrata("HIGH")
    local items, spawned = {}, 0
    local driver = CreateFrame("Frame")
    driver:Hide()
    -- How a number looks and moves (larger than the first version, and
    -- dressed a little, in the addon's own way):
    --   * a soft dark patch behind it, so it reads over grass or snow
    --     without a hard outline box;
    --   * it opens small and settles to size in a tenth of a second, then
    --     drifts up and a little outward, like a spark leaving a fire;
    --   * a critical is larger, lands with a pop, and for a moment shows
    --     the lens fringe the Quick Buff pill has: a faint warm copy to one
    --     side and a cool one to the other, closing in to a narrow one
    --     that stays, and shifts a little, while the number rises and fades.
    local SIZE = 20
    local function item()
        for i = 1, #items do if not items[i].live then return items[i] end end
        if #items >= NUM_POOL then return nil end
        local f = CreateFrame("Frame", nil, host)
        f:SetSize(10, 10)
        -- A hit for nothing hides itself, by a window that is only open
        -- when the amount is 1 or more. The amount is a hidden value in a
        -- fight: it can't be compared, and the game refused to run it
        -- through a curve. A bar will take it, though: this one runs from 0
        -- to 1, so an amount of 0 leaves its fill with no width and
        -- anything more fills it. The number, its patch, its emblem and its
        -- flash are all drawn inside a clipping frame laid over that fill:
        -- no fill, nothing seen. (This is how the "0" beside every Heroic
        -- Strike goes: the game reports that as two hits, the strike and an
        -- empty swing.)
        f.bar = CreateFrame("StatusBar", nil, f)
        f.bar:SetSize(300, 170)
        f.bar:SetPoint("CENTER")
        f.bar:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
        f.bar:SetStatusBarColor(0, 0, 0, 0)
        f.bar:SetMinMaxValues(0, 1)
        f.bar:SetValue(1)
        f.clip = CreateFrame("Frame", nil, f)
        f.clip:SetClipsChildren(true)
        local fill = f.bar:GetStatusBarTexture()
        local okClip = fill and pcall(function()
            f.clip:SetPoint("TOPLEFT", fill, "TOPLEFT")
            f.clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
        end)
        if not okClip then f.clip:ClearAllPoints(); f.clip:SetAllPoints(f.bar); f.bar = nil end
        if MinimalUIDB then MinimalUIDB.zeroclip = okClip and "window laid over the bar's fill" or "could not lay the window over the fill" end
        -- (What is clipped has to be a child frame of the clip, not a
        -- texture on the clip itself.)
        local outer = f
        f = CreateFrame("Frame", nil, outer.clip)
        f:SetSize(10, 10)
        f:SetPoint("CENTER", outer, "CENTER")
        outer.body = f
        f.back = f:CreateTexture(nil, "BACKGROUND")
        f.back:SetTexture("Interface/AddOns/Meniscus/Media/spot.tga")
        f.back:SetVertexColor(0, 0, 0, 0.42)
        f.back:SetSize(SIZE * 3.4, SIZE * 1.9)
        f.back:SetPoint("CENTER")
        local function line(layer, sub)
            local t = f:CreateFontString(nil, layer, nil)
            ns:SetFont(t, SIZE, "OUTLINE", true)
            t:SetPoint("CENTER")
            return t
        end
        f.warm, f.cool = line("ARTWORK"), line("ARTWORK")
        f.warm:SetTextColor(1.00, 0.45, 0.40)
        f.cool:SetTextColor(0.45, 0.62, 1.00)
        f.fs = line("OVERLAY")
        f.fs:SetShadowOffset(1, -1)
        f.fs:SetShadowColor(0, 0, 0, 0.9)
        f.burst = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.burst:SetTexture("Interface/AddOns/Meniscus/Media/spot.tga")
        f.burst:SetBlendMode("ADD")
        f.burst:SetPoint("CENTER")
        f.burst:SetAlpha(0)
        f.kind = f:CreateTexture(nil, "OVERLAY")
        f.kind:SetSize(SIZE * 0.78, SIZE * 0.78)
        f.kind:SetPoint("RIGHT", f.fs, "LEFT", -2, 0)
        f.kind:Hide()
        outer.back, outer.warm, outer.cool, outer.fs, outer.burst, outer.kind = f.back, f.warm, f.cool, f.fs, f.burst, f.kind
        f = outer
        items[#items + 1] = f
        return f
    end
    driver:SetScript("OnUpdate", function(self, dt)
        local any = false
        for i = 1, #items do
            local f = items[i]
            if f.live then
                f.age = f.age + dt
                local k = f.age / (f.life or NUM_LIFE)
                if k >= 1 then
                    f.live = false
                    f:Hide()
                else
                    any = true
                    -- Up quickly, then easing off; clear until the last third.
                    -- (A critical first hangs where it landed for a third of
                    -- a second, at full size, and only then starts to rise.)
                    local kr = k
                    if f.crit then
                        local life = f.life or NUM_LIFE
                        kr = f.age < 0.34 and 0 or (f.age - 0.34) / (life - 0.34)
                    end
                    local e = 1 - (1 - kr) * (1 - kr)
                    -- Opening: small (a critical: large) to its own size.
                    -- (Positions are in the frame's own units, so the scale
                    -- is divided out.)
                    local sc = f.scale
                    if f.crit then
                        -- Lands at well over its size and snaps down to it.
                        if f.age < 0.20 then sc = f.scale * (1.7 - 0.7 * (f.age / 0.20) ^ 0.6) end
                    elseif f.age < 0.10 then
                        sc = f.scale * (0.6 + 0.4 * f.age / 0.10)
                    end
                    f:SetScale(sc)
                    if not pcall(f.SetPoint, f, "CENTER", f.rel or UIParent, f.rel and "TOP" or "BOTTOMLEFT",
                                 (f.x + f.drift * e) / sc, (f.y + NUM_RISE * e) / sc) then
                        f.live = false
                        f:Hide()
                    end
                    f:SetAlpha(k < 0.66 and 1 or (1 - k) / 0.34)
                    if f.crit then
                        -- The fringe: wide apart as it lands, closing in under a
                        -- second to a narrow one that it keeps for the rest of
                        -- its life (it used to close fully and leave a plain
                        -- number). At rest the split breathes a little, its
                        -- lean turns slowly, and the two tints wander (red
                        -- through amber and rose, blue through cyan and
                        -- violet), as light does through a turning glass. It
                        -- fades with the number.
                        local q = f.age < 0.9 and (1 - f.age / 0.9) or 0
                        local a = f.age
                        local pull = 5.5 * (0.36 + 0.64 * q) * (1 + 0.16 * (1 - q) * math.sin(a * 4.6))
                        local lean = 0.18 + 0.42 * (1 - q) * math.sin(a * 1.9)
                        local dx, dy = pull * math.cos(lean), pull * math.sin(lean)
                        f.warm:SetPoint("CENTER", -dx, dy)
                        f.cool:SetPoint("CENTER", dx, -dy)
                        local w = (1 - q) * math.sin(a * 2.7)
                        f.warm:SetTextColor(1.00, 0.45 + 0.22 * w, 0.40 - 0.18 * w)
                        f.cool:SetTextColor(0.45 - 0.16 * w, 0.62 + 0.20 * w, 1.00)
                        local fa = 0.60 + 0.30 * q
                        f.warm:SetAlpha(fa); f.cool:SetAlpha(fa)
                        -- A burst of light behind it as it lands, gone in under half a second.
                        -- (Brighter than it was: full strength at the landing,
                        -- and paler, nearer white, than the number's colour.)
                        local bq = f.age < 0.48 and (1 - f.age / 0.48) or 0
                        f.burst:SetAlpha(bq * bq)
                        local bs = SIZE * (3.2 + 2.2 * (1 - bq))
                        f.burst:SetSize(bs * 1.5, bs)
                    end
                end
            end
        end
        if not any then self:Hide() end
    end)
    -- rel: the frame the number rises from (a nameplate), or nil for a
    -- place on the screen. A nameplate may not be measured by an addon
    -- ("restricted region"), only anchored to: so the number is hung on it.
    local showUnit -- (the unit the hit being shown is on; set by the event below)
    local WIDE_ORDER = { 0, 2, -2, 1, -1, 3, -3 }
    local zeroCurve, zeroBack
    local function show(rel, x, y, value, r, g, b, crit, small, kind)
        local f = item()
        if not f then return end
        f.unit = showUnit
        f.onTarget = false
        if showUnit and showUnit ~= "player" then
            local okT, isT = pcall(UnitIsUnit, showUnit, "target")
            f.onTarget = okT and not secret(isT) and isT == true
        end
        if kind then
            f.kind:SetTexture("Interface/AddOns/Meniscus/Media/" .. kind)
            f.kind:SetVertexColor(r, g, b, 1)
            f.kind:Show()
        else
            f.kind:Hide()
        end
        -- A hit for nothing hides itself. In a fight the amounts are hidden
        -- values: they can be shown but not looked at, so "is it zero?"
        -- can't be asked here. The game can be asked to run the amount
        -- through a curve, though (0 gives 0, 1 or more gives 1), and what
        -- comes back, hidden too, is used as the opacity of the number's
        -- colour, its dark patch and its emblem. (Colour opacity is the one
        -- place a hidden opacity is known to be drawn: the pet's mood word
        -- works that way.) This is how the "0" beside every Heroic Strike
        -- goes: the game reports that as two hits at once, the strike and
        -- an empty swing.
        local seen = nil -- the opacity to draw with, when it could be had
        if secret(value) then
            if zeroCurve == nil then
                zeroCurve, zeroBack = false, false
                if C_CurveUtil and C_CurveUtil.CreateCurve then
                    local okC, c = pcall(C_CurveUtil.CreateCurve)
                    if okC and c and pcall(function() c:AddPoint(0, 0); c:AddPoint(0.5, 0); c:AddPoint(1, 1) end) then zeroCurve = c end
                    local okB, cb = pcall(C_CurveUtil.CreateCurve)
                    if okB and cb and pcall(function() cb:AddPoint(0, 0); cb:AddPoint(0.5, 0); cb:AddPoint(1, 0.42) end) then zeroBack = cb end
                end
            end
            local how = "no curve"
            if zeroCurve then
                local okE, a = pcall(zeroCurve.Evaluate, zeroCurve, value)
                if okE and a ~= nil then
                    seen = a
                    how = "curve gave an opacity"
                    local okB, ab = false, nil
                    if zeroBack then okB, ab = pcall(zeroBack.Evaluate, zeroBack, value) end
                    if not (okB and ab ~= nil and pcall(f.back.SetVertexColor, f.back, 0, 0, 0, ab)) then f.back:SetVertexColor(0, 0, 0, 0.42) end
                    if kind and not pcall(f.kind.SetVertexColor, f.kind, r, g, b, a) then f.kind:SetVertexColor(r, g, b, 1) end
                else
                    how = "the curve would not take a hidden amount: " .. tostring(a):sub(1, 80)
                    f.back:SetVertexColor(0, 0, 0, 0.42)
                end
            end
            if MinimalUIDB and MinimalUIDB.zerodiag ~= how then MinimalUIDB.zerodiag = how end
        else
            f.back:SetVertexColor(0, 0, 0, 0.42)
        end
        f.zeroSeen = seen
        if f.bar and not pcall(f.bar.SetValue, f.bar, secret(value) and value or 1) then
            f.bar:SetValue(1)
            if MinimalUIDB then MinimalUIDB.zeroclip = "the bar would not take the amount" end
        end
        -- (A hidden amount goes straight in; nothing is done with it here.)
        local ok = pcall(f.fs.SetText, f.fs, value)
        if MinimalUIDB and not MinimalUIDB.ctdiag then
            MinimalUIDB.ctdiag = "first number: hidden=" .. tostring(secret(value)) .. " type=" .. type(value) .. " shown=" .. tostring(ok)
        end
        if not ok then return end
        if crit then
            pcall(f.warm.SetText, f.warm, value)
            pcall(f.cool.SetText, f.cool, value)
        else
            f.warm:SetText(""); f.cool:SetText("")
        end
        f.warm:SetAlpha(0); f.cool:SetAlpha(0)
        f.back:SetShown(not small)
        spawned = spawned + 1
        local scale = crit and 1.55 or (small and 0.85 or 1)
        f.burst:SetVertexColor(r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45, 1)
        f.burst:SetAlpha(0)
        f.crit, f.scale = crit, scale
        -- A critical stays up most of a second longer than an ordinary
        -- hit, and its colour fringe takes longer to close.
        f.life = crit and (NUM_LIFE + 0.9) or NUM_LIFE
        f:SetScale(scale)
        f.rel = rel
        -- Lanes side by side, so a burst doesn't stack; each drifts a little
        -- further out the way it already leans. Over a nameplate: five
        -- narrow ones. From the target frame or on the rails there is room,
        -- and every hit starts from the one spot, so: seven, well apart,
        -- taken in an order that puts each new number far from the last
        -- (middle, right, left, further right, ...) and on alternating
        -- heights, so two numbers a moment apart never share a line.
        if rel then
            local lane = (spawned % 5) - 2
            f.x = x + lane * 16
            f.drift = lane * 7
            f.y = y
        else
            local lane = WIDE_ORDER[(spawned % 7) + 1]
            f.x = x + lane * 38
            f.drift = lane * 9
            f.y = y + ((spawned % 2 == 0) and 0 or 16)
        end
        if f.zeroSeen == nil or not pcall(f.fs.SetTextColor, f.fs, r, g, b, f.zeroSeen) then f.fs:SetTextColor(r, g, b, 1) end
        f.age, f.live = 0, true
        f:SetAlpha(1)
        f:ClearAllPoints()
        local okP, errP = pcall(f.SetPoint, f, "CENTER", rel or UIParent, rel and "TOP" or "BOTTOMLEFT", f.x / scale, f.y / scale)
        if not okP then
            -- (Not allowed to hang on this plate either: give this one up.)
            f.live = false
            if MinimalUIDB then MinimalUIDB.ctdiag = "anchor refused: " .. tostring(errP) end
            return
        end
        f:Show()
        driver:Show()
    end
    -- Where a unit's numbers start: just above its nameplate.
    local function plateOf(unit)
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
        return plate
    end
    -- Whose hit was that? The client has no combat log: it says a unit took
    -- damage, never who dealt it. So, a best guess (db.numbersMine): a
    -- number over a nameplate is shown only if you did something that could
    -- have caused it:
    --   * a harmful spell or wand shot of yours has just gone off (within
    --     2.6 s; each one accounts for one hit) and the unit is your target;
    --   * or the unit carries a damage-over-time effect of yours and the
    --     hit falls on a tick (every 3 s from when you cast it);
    --   * a heal: you have just cast a helping spell.
    -- It misses melee swings (they announce nothing), and lets through
    -- someone else's hit that lands in the same instant as yours.
    local RAILKEY = {} -- stands for "your target, with no nameplate" where a nameplate would be the key
    -- The rails: three of them, their own, high on the screen (above where
    -- the loot and experience pills finish their climb). Your target's
    -- numbers rise on the middle one; other enemies you are hitting take
    -- the right and the left, each keeping its rail while the hits keep
    -- coming, so two enemies' numbers don't pile into one column.
    local RAIL_DX = { [0] = 0, 150, -150 }
    local RAIL_DY = { [0] = 0, -22, -22 }
    local RAIL_KEEP = 5 -- seconds an enemy keeps its rail after its last number
    local railOf = setmetatable({}, { __mode = "k" }) -- [key] = { rail, when }
    local sideUsed = { 0, 0 }
    -- Or, the usual place now: rising from the top of our target frame.
    -- The place is the frame's, but the numbers are not hung on it: the
    -- game drops your target the moment it dies and the frame hides, and a
    -- number hung on it went too. So where the frame is gets measured (it
    -- is ours, and can be) and remembered, and the number is put there on
    -- the screen itself.
    local frameX, frameY
    local function frameSpot()
        local UFm = ns.modules.UnitFrames
        local tf = UFm and UFm.target
        local at = tf and (tf.healthPill or tf)
        if at then
            local okC, cx = pcall(at.GetCenter, at)
            local okT, top = pcall(at.GetTop, at)
            if okC and okT and type(cx) == "number" and type(top) == "number" and not secret(cx) and not secret(top) then
                local k = at:GetEffectiveScale() / UIParent:GetEffectiveScale()
                frameX, frameY = cx * k, top * k + 78 -- (clear of the frame, not starting on it)
            end
        end
        return frameX, frameY
    end
    local function railSpot(key, isTarget)
        if NP.db.numbersWhere ~= "rail" then
            local fx, fy = frameSpot()
            if fx then return fx, fy end
        end
        local now = GetTime()
        local idx = 0
        local had = key and railOf[key]
        if had and now - had[2] < RAIL_KEEP then
            idx = had[1]
            had[2] = now
        elseif key then
            if not isTarget then
                idx = (sideUsed[1] <= sideUsed[2]) and 1 or 2
            end
            if had then had[1], had[2] = idx, now else railOf[key] = { idx, now } end
        end
        if idx > 0 then sideUsed[idx] = now end
        return UIParent:GetWidth() / 2 + RAIL_DX[idx], UIParent:GetHeight() * 0.72 + RAIL_DY[idx]
    end
    local guess = NP.db.numbersMine ~= false
    local hits, heals, dots = {}, {}, {}   -- when each allowance runs out; plate -> when your effect went on
    local function helpful(spellID)
        local f = C_Spell and C_Spell.IsSpellHelpful
        local ok, h = pcall(f or _G.IsHelpfulSpell, spellID)
        return ok and not secret(h) and h == true
    end
    local function take(list, now)
        while list[1] and list[1] < now do table.remove(list, 1) end
        if list[1] then table.remove(list, 1) return true end
        return false
    end
    -- Melee swings announce nothing, so they are counted by rhythm: while
    -- you are auto-attacking your target, one hit (or miss, dodge, parry) on
    -- it is taken as yours each time a swing's worth of time has passed.
    -- (In a group someone else's blow can take that place; it evens out.)
    local lastSwing, why = 0, ""
    local swingSchools, swingExtra, hitSchool = {}, 0, nil
    local function swinging(now)
        local f = (C_Spell and C_Spell.IsCurrentSpell) or _G.IsCurrentSpell
        local okA, auto = pcall(f, 6603)
        if not okA or secret(auto) or not auto then
            why = "not auto-attacking: " .. (not okA and "error" or secret(auto) and "hidden" or "no")
            return false
        end
        local okS, speed = pcall(UnitAttackSpeed, "player")
        if not okS or secret(speed) or type(speed) ~= "number" or speed <= 0 then speed = 2 end
        local sch = hitSchool
        if secret(sch) or type(sch) ~= "number" then sch = 0 end
        if now - lastSwing >= speed * 0.8 then
            lastSwing = now
            wipe(swingSchools)
            swingSchools[sch] = true
            swingExtra = 0
            return true
        end
        -- One swing can land as two hits a moment apart: the blow and what
        -- rides on it (a paladin's seal struck holy first, and the weapon's
        -- own hit, half a second later, was thrown away). So for a second
        -- after a counted swing, up to two more hits of a kind not yet seen
        -- in it are taken as part of the same swing.
        if now - lastSwing <= 1.0 and swingExtra < 2 and not swingSchools[sch] then
            swingSchools[sch] = true
            swingExtra = swingExtra + 1
            why = "with the swing"
            return true
        end
        why = string.format("%.1f s after a swing", now - lastSwing)
        return false
    end
    -- Your pet's hits, by the same kind of guess (db.numbersPet): the unit
    -- is what your pet is attacking, and either the pet has just used an
    -- ability (one hit each) or a swing's worth of its time has passed.
    -- Asked only after your own rules have passed a hit up, so with both of
    -- you on one enemy a blow can now and then be given to the wrong one.
    local petHits, lastPetSwing, byPet = {}, 0, false
    local function pets(unit, now)
        if NP.db.numbersPet == false then return false end
        local okE, has = pcall(UnitExists, "pet")
        if not okE or secret(has) or not has then return false end
        local okT, on = pcall(UnitIsUnit, unit, "pettarget")
        if not okT or secret(on) or not on then return false end
        if take(petHits, now) then why = "pet cast"; return true end
        local okS, speed = pcall(UnitAttackSpeed, "pet")
        if not okS or secret(speed) or type(speed) ~= "number" or speed <= 0 then speed = 2 end
        if now - lastPetSwing >= speed * 0.8 then lastPetSwing = now; why = "pet swing"; return true end
        return false
    end
    local yoursOnly
    local function yours(unit, plate, action, now)
        byPet = false
        if yoursOnly(unit, plate, action, now) then return true end
        if action ~= "HEAL" and pets(unit, now) then byPet = true; return true end
        return false
    end
    yoursOnly = function(unit, plate, action, now)
        why = ""
        if action == "HEAL" then why = "heal"; return take(heals, now) end
        local okT, isTarget = pcall(UnitIsUnit, unit, "target")
        isTarget = okT and not secret(isTarget) and isTarget == true
        if isTarget and take(hits, now) then why = "cast"; return true end
        if isTarget and swinging(now) then if why == "" then why = "swing" end; return true end
        local list = plate and dots[plate]
        -- Your target's effects are also kept under the target itself: its
        -- nameplate goes when it leaves the screen (the camera turned away,
        -- or too far off) and comes back as a different one, and the ticks
        -- were lost with it.
        if isTarget and not (list and #list > 0) then list = dots[RAILKEY] end
        if list and #list > 0 then
            -- (Whether the unit still carries your effect was asked of the
            -- game here, and the answer could not be relied on: it is only
            -- noted now, and the timing alone decides.)
            local okA, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|PLAYER")
            local hit = false
            for i = #list, 1, -1 do
                local age = now - list[i]
                if age > 31 then
                    table.remove(list, i)
                elseif age > 1 then
                    local ph = age % 3
                    -- (Measured: ticks arrive 2.91 to 2.99 s after the beat before.)
                    if ph < 0.3 or ph > 2.6 then hit = true; why = "tick" end
                    -- What was seen, for tuning (MinimalUIDB.dotdiag, the last 16).
                    if MinimalUIDB then
                        local d = MinimalUIDB.dotdiag
                        if type(d) ~= "table" then d = {}; MinimalUIDB.dotdiag = d end
                        d[#d + 1] = string.format("%s age %.2f beat %.2f aura %s/%s %s", action, age, ph, tostring(okA), tostring(a ~= nil), hit and "shown" or "dropped")
                        if #d > 16 then table.remove(d, 1) end
                    end
                end
            end
            if hit then return true end
        elseif MinimalUIDB and action == "WOUND" then
            MinimalUIDB.dotnote = "a hit with no cast of yours on record for that nameplate (plate " .. tostring(plate ~= nil) .. ")"
        end
        return false
    end
    if guess then
        local pcast = CreateFrame("Frame")
        pcall(pcast.RegisterUnitEvent, pcast, "UNIT_SPELLCAST_SUCCEEDED", "pet")
        pcast:SetScript("OnEvent", function(_, _, _, _, spellID)
            if secret(spellID) or type(spellID) ~= "number" or helpful(spellID) then return end
            petHits[#petHits + 1] = GetTime() + 1.6
            if #petHits > 4 then table.remove(petHits, 1) end
        end)
        local cast = CreateFrame("Frame")
        pcall(cast.RegisterUnitEvent, cast, "UNIT_SPELLCAST_SUCCEEDED", "player")
        cast:SetScript("OnEvent", function(_, _, _, _, spellID)
            if secret(spellID) or type(spellID) ~= "number" then return end
            local now = GetTime()
            if MinimalUIDB then
                local d = MinimalUIDB.ctlog
                if type(d) ~= "table" then d = {}; MinimalUIDB.ctlog = d end
                local okN, n = pcall(C_Spell.GetSpellName, spellID)
                d[#d + 1] = string.format("%.2f CAST %s", now % 1000, tostring(okN and not secret(n) and n or spellID))
                if #d > 40 then table.remove(d, 1) end
            end
            if helpful(spellID) then
                heals[#heals + 1] = now + 1.2
                return
            end
            local ok, can = pcall(UnitCanAttack, "player", "target")
            if not ok or secret(can) or not can then return end
            hits[#hits + 1] = now + 2.6 -- (a bolt thrown from far off is in the air well over a second: 1.2 lost those)
            if #hits > 6 then table.remove(hits, 1) end
            -- When an effect of yours may have gone on (its ticks are counted
            -- from here). Not a wand or bow shot: those repeat every second
            -- or two, and each one was moving the count, so no tick ever
            -- fell on it.
            local auto = false
            local fa = C_Spell and C_Spell.IsAutoRepeatSpell
            if fa then
                local okR, r = pcall(fa, spellID)
                auto = okR and not secret(r) and r == true
            end
            if not auto then
                local okN, n = pcall(C_Spell.GetSpellName, spellID)
                auto = okN and not secret(n) and (n == "Shoot" or n == "Auto Shot")
            end
            if not auto then
                local function note(key)
                    local list = dots[key]
                    if not list then list = {}; dots[key] = list end
                    list[#list + 1] = now
                    if #list > 4 then table.remove(list, 1) end
                end
                local plate = plateOf("target")
                if plate then note(plate) end
                note(RAILKEY)
            end
        end)
        -- (A new target: what was kept under "your target" was the old one's.
        -- The old one's nameplate keeps its own list.)
        local tc = CreateFrame("Frame")
        tc:RegisterEvent("PLAYER_TARGET_CHANGED")
        tc:SetScript("OnEvent", function() dots[RAILKEY] = nil end)
        -- (And a nameplate is handed on to the next enemy that needs one,
        -- with the last one's record still on it: a mob you had only
        -- targeted, running past, showed a stranger's fire damage as a tick
        -- of yours. A nameplate starts clean each time it is given out.)
        local pa = CreateFrame("Frame")
        pcall(pa.RegisterEvent, pa, "NAME_PLATE_UNIT_ADDED")
        pa:SetScript("OnEvent", function(_, _, unit)
            if type(unit) ~= "string" or secret(unit) then return end
            local plate = plateOf(unit)
            if plate then dots[plate] = nil end
        end)
    end

    -- A nameplate going away with numbers still rising from it (the mob
    -- died a moment after the hit was shown): they move to where the target
    -- frame sits and finish there, instead of vanishing with the plate.
    -- (Shown or not: this client drops your target the moment it dies, so
    -- the frame has usually just gone too, which is why asking for it to be
    -- showing lost the killing blow every time. A hidden frame still has
    -- its place.)
    local gone = CreateFrame("Frame")
    pcall(gone.RegisterEvent, gone, "NAME_PLATE_UNIT_REMOVED")
    gone:SetScript("OnEvent", function(_, _, unit)
        if type(unit) ~= "string" or secret(unit) then return end
        local rx, ry = railSpot(plateOf(unit), false)
        local moved = 0
        for i = 1, #items do
            local f = items[i]
            if f.live and f.unit == unit and f.rel then
                -- (It keeps its lane, and goes on rising from where the
                -- rail starts.)
                f.rel, f.unit = nil, nil
                f.x, f.y = rx + (f.x or 0), ry
                moved = moved + 1
            end
        end
        if MinimalUIDB and moved > 0 then
            local d = MinimalUIDB.ctlog
            if type(d) == "table" then
                d[#d + 1] = string.format("%.2f PLATE GONE %s: %d moved to the rail", GetTime() % 1000, unit, moved)
            end
        end
    end)

    -- A number onto the screen: what kind it is decides its colour and mark.
    local function present(unit, rel, x, y, action, indicator, amount, school, mine, petShown)
        showUnit = unit
        local crit = not secret(indicator) and indicator == "CRITICAL"
        local kind = NP.db.numbersKind ~= false and not secret(school) and SCHOOL_ICON[school] or nil
        if action == "HEAL" then
            show(rel, x, y, amount, 0.42, 0.92, 0.50, crit)
        elseif action == "WOUND" then
            if mine then
                show(rel, x, y, amount, 0.96, 0.42, 0.38, crit, nil, kind)
            elseif petShown then
                -- Your pet's: its own kind, whatever the school. A paw, a
                -- sandy colour, and a size down so your own hits lead.
                show(rel, x, y, amount, PET_TINT[1], PET_TINT[2], PET_TINT[3], crit, not crit,
                     NP.db.numbersKind ~= false and "micro_class_druid.tga" or nil)
            else
                local c = (not secret(school) and SCHOOL_TINT[school]) or SCHOOL_TINT[1]
                show(rel, x, y, amount, c[1], c[2], c[3], crit, nil, kind)
            end
        elseif WORDS[action] then
            show(rel, x, y, WORDS[action], 0.80, 0.80, 0.86, false, true)
        end
    end

    -- ── Whose hit: the combat log's word for it ──────────────────────────
    -- The client gives addons no combat log to read, and what its own
    -- Combat Log tab prints reaches us sealed (a ticket the screen can
    -- redeem and we can't). But it does say WHEN a line is printed: one
    -- event a line, in step with the hits (measured: the same instant, or
    -- up to a tenth of a second before, now and then a frame after). And
    -- the log's usual filter, "My actions", prints only what you and your
    -- pet do. So: a line arriving with a hit means the hit is yours. That
    -- replaces the guessing above whenever it can be used:
    --   * the log has to be sending its lines out. It does that by itself
    --     only while its tab is in front; asking it to keep on is allowed
    --     (tried: no objection), and is asked again whenever it has stopped,
    --     out of combat;
    --   * its filter has to be "My actions". On any other, and whenever the
    --     lines aren't coming, the guess is used as before.
    -- A line is good for one hit, for 0.8 s: both lines of a swing (the
    -- blow, and a seal's or a weapon's own extra) are printed together at
    -- the swing, while the second hit is only reported some half a second
    -- later (measured; at a third of a second the second hit of every
    -- swing was being thrown away). A hit that comes ahead of its line
    -- waits a quarter of a second for it.
    --
    -- The blow that kills. When it is that later, second hit that kills,
    -- the game never reports the hit at all (the enemy is gone before it
    -- would have): there is its log line, the log's white "You killed"
    -- notice, and nothing else, and the amount is inside the sealed line.
    -- That case is recognised (more lines printed with the kill notice than
    -- hits reported with it) so that its line is not left over for some
    -- later hit to use, and nothing is shown for it: there is no amount.
    local CL = C_CombatLog
    local logLines, held = {}, {}
    local logHeard = false
    local lastLine, lineCount = -99, 0
    local lineTimes, claimTimes = {}, {} -- when lines came, and when a hit took one (the last dozen of each)
    local twinKey, twinAt
    local threatWorks = false -- the game has answered "is it fighting you?" at least once
    -- ── A filter that prints only your hits ──────────────────────────────
    -- "My actions" as it comes prints your heals, their ticks and more
    -- beside your hits, and nothing for a miss. Each spare line could be
    -- spent on somebody else's hit (a healer in a group saw everyone's
    -- numbers), and misses had to be guessed. With the filter set to pass
    -- only damage and misses, a line means exactly one hit or miss of yours.
    --
    -- An addon may not set that: handing the log a filter was tried, and the
    -- game put up its "blocked from an action" box (the log's own code ends
    -- in calls only the game's interface may make). It may be READ, though,
    -- and the player can set it by hand in the log's own settings (Combat
    -- Log tab, right-click, Settings, "My actions", Message Types): heals
    -- off, misses on. So what the filter in use passes is looked at:
    --   ownSeen:   it passes nothing but damage, misses and deaths;
    --   missLines: it passes misses.
    -- and the rules below use whichever holds. (Looked at again every few
    -- seconds: it can be changed at any time.)
    local ownSeen, missLines = false, false
    local OWN_OK = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, DAMAGE_SPLIT = true,
                     DAMAGE_SHIELD = true, SWING_MISSED = true, RANGE_MISSED = true, SPELL_MISSED = true, SPELL_PERIODIC_MISSED = true,
                     DAMAGE_SHIELD_MISSED = true, PARTY_KILL = true, UNIT_DIED = true, UNIT_DESTROYED = true, UNIT_DISSIPATES = true }
    local filterAt = -99
    local function filterCheck(now)
        if now - filterAt < 3 then return end
        filterAt = now
        local own, miss = false, false
        local cur = _G.Blizzard_CombatLog_CurrentSettings
        local fl = type(cur) == "table" and cur.filters
        if type(fl) == "table" then
            own = true
            for _, f in pairs(fl) do
                -- (An entry that names no one, the second one of "My
                -- actions", passes nothing: not counted.)
                local live = false
                if type(f) == "table" then
                    for _, flags in pairs({ f.sourceFlags, f.destFlags }) do
                        if type(flags) == "table" then for _, on in pairs(flags) do if on then live = true end end end
                    end
                end
                if live and type(f.eventList) == "table" then
                    for k, on in pairs(f.eventList) do
                        if on and not OWN_OK[k] then own = false end
                    end
                    if f.eventList.SWING_MISSED and f.eventList.SPELL_MISSED then miss = true end
                end
            end
        end
        if MinimalUIDB and (own ~= ownSeen or miss ~= missLines or not MinimalUIDB.ownfilter) then
            MinimalUIDB.ownfilter = date("%H:%M:%S") .. " the log's filter passes " .. (own and "only your damage" or "more than your damage")
                .. (miss and ", with misses" or ", without misses")
        end
        ownSeen, missLines = own, miss
    end
    -- One line taken for a hit: the oldest still good.
    -- tight: only a line printed in this very moment will do (a hit with no
    -- other sign of being yours; a line is stamped 0.8 s ahead of its time).
    local function takeLine(now, tight)
        while logLines[1] and logLines[1] < now do table.remove(logLines, 1) end
        local got
        if tight then
            for i = 1, #logLines do
                if logLines[i] - 0.8 >= now - 0.12 then got = table.remove(logLines, i) break end
            end
        else
            got = table.remove(logLines, 1)
        end
        if not got then return false end
        claimTimes[#claimTimes + 1] = now
        if #claimTimes > 12 then table.remove(claimTimes, 1) end
        return true
    end
    local MY_ACTIONS = _G.QUICKBUTTON_NAME_MY_ACTIONS or "My actions"
    local function logOn()
        if not logHeard or NP.db.numbersLog == false then return false end
        if not (CL and CL.AreFilteredEventsEnabled) then return false end
        local okE, on = pcall(CL.AreFilteredEventsEnabled)
        if not okE or secret(on) or not on then return false end
        local cur = _G.Blizzard_CombatLog_CurrentSettings
        local name = type(cur) == "table" and cur.name
        return type(name) == "string" and not secret(name) and (name == MY_ACTIONS or name == "My actions")
    end
    local function note(text)
        if not MinimalUIDB then return end
        local d = MinimalUIDB.ctlog
        if type(d) ~= "table" then d = {}; MinimalUIDB.ctlog = d end
        d[#d + 1] = string.format("%.2f %s", GetTime() % 1000, text)
        if #d > 280 then table.remove(d, 1) end
    end
    -- ── The game's damage meter as a ledger of YOUR hits (a measurement) ──
    -- The meter keeps your damage apart from everyone else's, by ability.
    -- Its totals are hidden in a fight, but how many abilities are listed is
    -- not, and the meter can be wiped. Wiped after every look, anything
    -- listed under you is damage you did since the last look: yours for
    -- certain, in a group too, and with its ability. (Another addon,
    -- MidnightBattleText, draws its numbers this way.) The cost: the game's
    -- own damage meter shows nothing while this runs.
    -- For now only written into the log beside the hits, to see how the
    -- two line up before any rule is hung on it.
    -- meterOn: the meter is the proof that a hit was yours. It moves, with
    -- something listed under you, in the very moment a blow of yours lands
    -- (seen: the same instant as the hit's own report, or up to a second
    -- before it; never after). So a hit reported on an enemy waits
    -- (pendingW) for the meter to move in that instant, and when the meter
    -- moves with no hit yet reported, the next one reported is the one
    -- (grantAt). The number, the place and the critical all come from the
    -- hit's own report, as before: the meter's amounts are per ability, and
    -- a thunder clap on three enemies is one sum there.
    -- Not for the ticks of an effect of yours: those reach the meter only
    -- together with your next blow, so they go by their own sign.
    -- (db.numbersMeter = false: the older rules decide, as before.)
    local meterOn, pendingW = false, {}
    local grantAt, grantNow = nil, nil
    do
        local DM = C_DamageMeter
        if DM and DM.ResetAllCombatSessions and DM.GetCombatSessionSourceFromType then
            local mf = CreateFrame("Frame")
            local heard = pcall(mf.RegisterEvent, mf, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
            if MinimalUIDB then MinimalUIDB.meterdiag = "the meter's update event " .. (heard and "can be listened for" or "cannot be listened for") end
            meterOn = heard and NP.db.numbersMeter ~= false
            local guid, quietAt = nil, -9
            local function show(v) if secret(v) then return "hidden" end return tostring(v) end
            local function look(how, kind)
                local now = GetTime()
                if how == "told" and not secret(kind) and kind ~= 0 then return end
                if not guid then local okG, g = pcall(UnitGUID, "player"); guid = okG and g or nil end
                local ok, src = pcall(DM.GetCombatSessionSourceFromType, 0, 0, guid)
                local list = ok and type(src) == "table" and not secret(src) and src.combatSpells
                local n = (type(list) == "table" and not secret(list)) and #list or -1
                if n <= 0 then
                    if how == "told" and now - quietAt > 0.5 then
                        quietAt = now
                        note("    METER moved: nothing of yours listed" .. (n < 0 and (" (could not be read: " .. show(ok and "no list" or src) .. ")") or ""))
                    end
                    return
                end
                local parts = {}
                for i = 1, math.min(n, 4) do
                    local sp = list[i]
                    local okN, name = pcall(C_Spell.GetSpellName, sp.spellID)
                    local okI, icon = pcall(C_Spell.GetSpellTexture, sp.spellID)
                    parts[#parts + 1] = string.format("[name %s, icon %s, amount %s, by %s]", okN and show(name) or "refused", okI and show(icon) or "refused",
                        show(sp.totalAmount), show(sp.creatureName))
                end
                local drawn = 0
                if meterOn then
                    for i = 1, #pendingW do
                        local rec = pendingW[i]
                        if now - rec.t <= 0.03 then
                            drawn = drawn + 1
                            present(rec.unit, rec.rel, rec.x, rec.y, "WOUND", rec.indicator, rec.amount, rec.school, false, rec.pet)
                        end
                    end
                    wipe(pendingW)
                    if drawn > 0 then grantNow, grantAt = now, nil else grantAt = now end
                end
                local okR, err = pcall(DM.ResetAllCombatSessions)
                note(string.format("    METER (%s): %d of yours, %d drawn %s; wiped: %s", how, n, drawn, table.concat(parts, " "), okR and "yes" or ("refused: " .. tostring(err):sub(1, 80))))
            end
            -- (Some hits moved the meter without the game saying so: it is
            -- also looked at every frame of a fight, to see whether the
            -- damage was there all along.)
            mf:SetScript("OnEvent", function(_, _, kind) look("told", kind) end)
        elseif MinimalUIDB then
            MinimalUIDB.meterdiag = "no damage meter to ask"
        end
    end
    local function dropStale(now)
        while held[1] and now - held[1].t > 0.25 do
            table.remove(held, 1)
            note("  a held hit got no log line: not yours, dropped")
        end
    end
    if guess and CL and CL.SetFilteredEventsEnabled and CL.AreFilteredEventsEnabled then
        local lf = CreateFrame("Frame")
        if pcall(lf.RegisterEvent, lf, "COMBAT_LOG_MESSAGE") then
            logHeard = true
            -- The log refilling. At every login and reload (and whenever its
            -- filter is changed) the log prints its old lines again, a
            -- hundred or two of them a hundredth of a second apart. Those
            -- are not hits: taken as such they filled this record (a whole
            -- session's worth was written over by them) and set off the
            -- kill reckoning for every old kill. A run of more than six
            -- lines inside a quarter of a second, out of combat, is a
            -- refill: ignored until the lines have been quiet for half a
            -- second. (In combat a burst that size is an area spell.)
            local recent, refilling, lastAny = {}, false, 0
            local function isRefill(now)
                if refilling and now - lastAny > 0.5 then refilling = false; wipe(recent) end
                lastAny = now
                if refilling then return true end
                recent[#recent + 1] = now
                while recent[1] and now - recent[1] > 0.25 do table.remove(recent, 1) end
                if #recent > 6 then
                    local okC, fighting = pcall(UnitAffectingCombat, "player")
                    if okC and not secret(fighting) and not fighting then
                        refilling = true
                        wipe(logLines); wipe(lineTimes); wipe(held)
                        lastLine = -99
                        note("(the log is refilling with old lines: ignored)")
                        return true
                    end
                end
                return false
            end
            -- An experiment (/men logtext): the log's lines themselves, put
            -- on the screen as they arrive. Their text is sealed (it can be
            -- drawn, not read), but under "My actions" every line is yours,
            -- and the amount is in it. If the line can be made short enough
            -- by the log's own formatting settings, the line could BE the
            -- combat text, with nothing to guess. This shows what they look
            -- like; their colours go in the record (ctlog) with each LINE.
            local strip, stripAt = nil, 0
            local function stripShow(msg, r, g, b)
                if not (MinimalUIDB and MinimalUIDB.logtext) then
                    if strip then strip:Hide() end
                    return
                end
                if not strip then
                    strip = CreateFrame("Frame", nil, UIParent)
                    strip:SetSize(700, 150)
                    strip:SetPoint("TOP", UIParent, "TOP", 0, -120)
                    strip:SetFrameStrata("HIGH")
                    strip.rows = {}
                    for i = 1, 8 do
                        local t = strip:CreateFontString(nil, "OVERLAY")
                        ns:SetFont(t, 13, "OUTLINE", true)
                        t:SetPoint("TOP", 0, -(i - 1) * 18)
                        strip.rows[i] = t
                    end
                end
                strip:Show()
                stripAt = stripAt % 8 + 1
                local t = strip.rows[stripAt]
                if not pcall(t.SetText, t, msg) then t:SetText("(a line that could not be drawn)") end
                if not (type(r) == "number" and not secret(r) and pcall(t.SetTextColor, t, r, g, b)) then t:SetTextColor(1, 1, 1) end
                for i = 1, 8 do strip.rows[i]:SetAlpha(i == stripAt and 1 or 0.55) end
            end
            ns.commands.logtext = function()
                if not MinimalUIDB then return end
                MinimalUIDB.logtext = not MinimalUIDB.logtext or nil
                if strip and not MinimalUIDB.logtext then strip:Hide() end
                ns:Print("Combat log lines on screen: " .. (MinimalUIDB.logtext and "on (hit something)" or "off") .. ".")
            end
            local function rgbNote(r, g, b)
                if type(r) ~= "number" or secret(r) or secret(g) or secret(b) then return " (colour hidden)" end
                return string.format(" colour %.2f %.2f %.2f", r, g, b)
            end
            lf:SetScript("OnEvent", function(_, _, msg, r, g, b)
                if isRefill(GetTime()) then return end
                pcall(stripShow, msg, r, g, b)
                -- (White lines are the log's notices, "You killed ..." and
                -- the like: not a hit.)
                if type(r) == "number" and not secret(r) and r > 0.95 and g > 0.95 and b > 0.95 then
                    -- The kill notice. It is printed among the lines of the
                    -- blow that killed, not always after them (seen: before
                    -- one of them), so the lines and the hits around it are
                    -- counted a moment later: more lines than hits means a
                    -- hit the game will never report.
                    local at = GetTime()
                    note("LINE (white: a notice)")
                    C_Timer.After(0.2, function()
                        local lines, claims = 0, 0
                        for i = 1, #lineTimes do if math.abs(lineTimes[i] - at) <= 0.15 then lines = lines + 1 end end
                        for i = 1, #claimTimes do if claimTimes[i] >= at - 0.15 and claimTimes[i] <= at + 0.2 then claims = claims + 1 end end
                        if lines > claims then
                            note(string.format("  at the kill: %d lines, %d hits reported: the unreported one has no number, nothing shown", lines, claims))
                            -- (Those lines are spent: nothing later may use them.)
                            for i = #logLines, 1, -1 do
                                if math.abs((logLines[i] - 0.8) - at) <= 0.15 then table.remove(logLines, i) end
                            end
                            -- (The words "Killing blow" were shown here for a
                            -- while. Taken out by request: with no amount to
                            -- give, better nothing than words.)
                        end
                    end)
                    return
                end
                local now = GetTime()
                filterCheck(now)
                lastLine = now
                lineCount = lineCount + 1
                lineTimes[#lineTimes + 1] = now
                if #lineTimes > 12 then table.remove(lineTimes, 1) end
                if MinimalUIDB then MinimalUIDB.ctlines = lineCount .. " log lines heard this session, the last at " .. string.format("%.2f", now % 1000) end
                note("LINE" .. rgbNote(r, g, b))
                dropStale(now)
                local h = table.remove(held, 1)
                if h then
                    claimTimes[#claimTimes + 1] = now
                    if #claimTimes > 12 then table.remove(claimTimes, 1) end
                    note("  its log line came: shown")
                    present(h.unit, h.rel, h.x, h.y, h.action, h.indicator, h.amount, h.school, false, h.pet)
                    -- (And its twin, if it had one waiting: see "twin".)
                    for i = #held, 1, -1 do
                        local o = held[i]
                        if o.t == h.t and o.key == h.key then
                            table.remove(held, i)
                            note("  and its twin")
                            present(o.unit, o.rel, o.x, o.y, o.action, o.indicator, o.amount, o.school, false, o.pet)
                        end
                    end
                    return
                end
                -- (Never two with the same stamp: the kill's line is known by it.)
                local stamp = now + 0.8
                local prev = logLines[#logLines]
                if prev and stamp <= prev then stamp = prev + 0.0001 end
                logLines[#logLines + 1] = stamp
                if #logLines > 12 then table.remove(logLines, 1) end
            end)
            -- Keep the log sending. (Out of combat only: whether the game
            -- would mind mid-fight hasn't been tried.)
            local function keep()
                if InCombatLockdown() or NP.db.numbersLog == false then return end
                local okE, on = pcall(CL.AreFilteredEventsEnabled)
                if okE and not secret(on) and not on then pcall(CL.SetFilteredEventsEnabled, true) end
            end
            local kf = CreateFrame("Frame")
            kf:RegisterEvent("PLAYER_REGEN_ENABLED")
            kf:RegisterEvent("PLAYER_ENTERING_WORLD")
            kf:SetScript("OnEvent", function() C_Timer.After(1, keep) end)
            C_Timer.NewTicker(3, keep)
        end
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_COMBAT")
    ev:SetScript("OnEvent", function(_, _, unit, action, indicator, amount, school)
        if type(unit) ~= "string" or secret(unit) or secret(action) or type(action) ~= "string" then return end
        showUnit = unit
        local mine = unit == "player"
        local x, y, rel
        local onRail, key = false, nil
        local petShown = false
        if mine then
            -- What you take already rises out of the health orb, when that
            -- is on (Extras: orbText): not shown a second time here.
            local EX = ns.modules.Extras
            local OR = ns.modules.Orbs
            if EX and EX.db and EX.db.orbText ~= false and OR and OR.health and OR.health:IsShown() then return end
            -- Switched off there: off, not moved here. (Beside your
            -- character is only for when there is no health orb to use.)
            if EX and EX.db and EX.db.orbText == false then return end
            local w, h = UIParent:GetWidth(), UIParent:GetHeight()
            x, y = w / 2 + (action == "HEAL" and 80 or -80), h * 0.46
        elseif unit:find("^nameplate") or unit == "target" then
            -- Over the enemy's nameplate, or on the rail beside your
            -- character: a fixed place on the screen that is ours, used
            --   * for everything, if that is what the setting says;
            --   * when the target is too far off to have a nameplate;
            --   * for the blow that kills (the nameplate is already on its
            --     way out, and a number hung on it went with it).
            -- (The target frame was tried as that second place: the client
            -- drops your target at death, the frame hides, and the number
            -- was never seen there.)
            if unit == "target" then
                -- With a nameplate up, the nameplate's own report of the
                -- same hit is the one shown.
                if not plateOf("target") then onRail, key = true, RAILKEY end
            else
                rel = plateOf(unit)
                key = rel
                if rel then
                    local okD, dead = pcall(UnitIsDeadOrGhost, unit)
                    if (okD and not secret(dead) and dead) or NP.db.numbersWhere ~= "plate" then onRail = true end
                end
            end
            if onRail then
                local isT = key == RAILKEY
                if not isT then
                    local okT, t = pcall(UnitIsUnit, unit, "target")
                    isT = okT and not secret(t) and t == true
                end
                rel = nil
                x, y = railSpot(key, isT)
            elseif rel then
                x, y = 0, 4
            end
            -- A hit for nothing at all isn't worth a number (when the
            -- amount can be read; in a fight it usually can't).
            if action == "WOUND" and not secret(amount) and amount == 0 then return end
            hitSchool = school
            local now = GetTime()
            local mineHit
            if meterOn and key and guess and action == "WOUND" then
                local own = yoursOnly(unit, key, action, now)
                local tick = own and why == "tick"
                local pet = (not own) and pets(unit, now) or false
                if tick then
                    mineHit, byPet, why = true, false, "tick of your effect"
                elseif grantNow == now then
                    mineHit, byPet, why = true, pet, "the meter moved for you this instant"
                elseif grantAt and now - grantAt <= 1.4 then
                    grantNow, grantAt = now, nil
                    mineHit, byPet, why = true, pet, "the meter moved for you a moment ago"
                else
                    if x then
                        pendingW[#pendingW + 1] = { t = now, unit = unit, rel = rel, x = x, y = y, indicator = indicator, amount = amount, school = school, pet = pet }
                        if #pendingW > 16 then table.remove(pendingW, 1) end
                    end
                    mineHit, why = false, "waits for the meter"
                end
            elseif not (key and guess) then
                mineHit, byPet, why = true, false, ""
            elseif logOn() then
                -- Yours or your pet's, for how it is drawn: the old signs
                -- are still good for telling those two apart.
                local own = yoursOnly(unit, key, action, now)
                local ownWhy = why
                local pet = (not own) and action ~= "HEAL" and pets(unit, now) or false
                dropStale(now)
                -- In a group a log line alone is not enough. Your heals and
                -- their ticks write lines too, and each one was spent on the
                -- next blow anyone landed: a healer saw the whole party's
                -- numbers without attacking. There, a hit also has to look
                -- like yours by the old signs (a cast, your swing, your dot,
                -- your pet's).
                local grouped = IsInGroup and IsInGroup()
                if secret(grouped) then grouped = false end
                -- On your own there is a plainer sign than any of the
                -- timing: the enemy is fighting you (you are on its threat
                -- list). Nobody else is hitting it, as a rule, so whatever
                -- lands on it is yours or your pet's: hits, ticks, misses,
                -- all of it, with no line to wait for. (Its line, if one
                -- is there, is still used up, so it can't be spent on a
                -- stranger's hit a moment later.) Not in a group, where
                -- everyone is on that list. If the game won't say, the
                -- rules below decide as before.
                local onMe = false
                if not grouped and action ~= "HEAL" and UnitThreatSituation then
                    local okT, t = pcall(UnitThreatSituation, "player", unit)
                    onMe = okT and t ~= nil and not secret(t)
                    if onMe then threatWorks = true end
                    if MinimalUIDB and not MinimalUIDB.threatdiag then
                        MinimalUIDB.threatdiag = "first asked: ok=" .. tostring(okT) .. " hidden=" .. tostring(secret(t)) .. " value=" .. (secret(t) and "?" or tostring(t))
                    end
                end
                if grouped and not ownSeen and not (own or pet) then
                    mineHit = false
                    why = "in a group, and no sign it was yours"
                elseif ownSeen and action == "HEAL" then
                    -- (The filter prints no heals: a heal goes by your cast alone.)
                    mineHit, byPet = own and true or false, false
                    why = own and "heal, by your cast" or "a heal, and no cast of yours"
                elseif threatWorks and not grouped and action ~= "HEAL" and not onMe and not ((own and ownWhy ~= "tick") or pet) then
                    -- On your own, an enemy that is not fighting you, and
                    -- nothing of yours aimed at it: somebody else's fight.
                    -- (A mage's missiles on a mob nearby were shown: a log
                    -- line of yours, left over from a hit already shown by
                    -- another rule, was spent on them.) Your opening blow,
                    -- before the enemy has turned on you, still passes: it
                    -- is on your target and follows a cast or swing. (A
                    -- "tick of your effect" does not pass here: an enemy
                    -- carrying an effect of yours is fighting you.)
                    mineHit = false
                    why = "not fighting you, and no sign it was yours"
                elseif onMe then
                    if action == "WOUND" and not (twinKey == key and twinAt == now) then
                        takeLine(now)
                        twinKey, twinAt = key, now
                    end
                    mineHit, byPet = true, pet
                    why = "on your own, and it is fighting you" .. (pet and ": pet's" or "")
                elseif action ~= "WOUND" and action ~= "HEAL" and not missLines then
                    -- (Where the filter passes misses, a miss has a line
                    -- like any hit, and is matched to it below.)
                    -- A miss, dodge, parry or block: the log prints no line
                    -- for these under "My actions" (seen: none within
                    -- seconds of any of them), so waiting for one threw away
                    -- every miss that came within three seconds of a hit,
                    -- which in a steady fight is nearly all of them. They go
                    -- by the old signs alone (your swing, your cast, your
                    -- pet's), and use up no line.
                    mineHit, byPet = (own or pet) and true or false, pet
                    why = mineHit and ("no line is written for a miss: by the old signs" .. (pet and ", pet's" or "")) or "a miss, and no sign it was yours"
                elseif twinKey == key and twinAt == now then
                    -- The same enemy, the same instant as a hit just shown:
                    -- one blow reported as two (Heroic Strike and its empty
                    -- swing), with one log line between them.
                    mineHit, byPet = true, pet
                    why = "twin of the hit before"
                elseif takeLine(now, ownSeen and grouped and not (own or pet)) then
                    -- (In a group, a hit with no other sign of being yours
                    -- has to arrive with its line, not merely within the
                    -- line's 0.8 s: someone else's blow rarely does.)
                    mineHit, byPet = true, pet
                    twinKey, twinAt = key, now
                    why = pet and "log line, pet's" or "log line"
                elseif (own or pet) and now - lastLine > 3 then
                    -- No lines have come for a while (in the first test of
                    -- this they stopped coming altogether, and every hit
                    -- was thrown away): the old signs are believed.
                    mineHit, byPet = true, pet
                    why = "no lines lately: by the old signs" .. (pet and ", pet's" or "")
                else
                    -- No line yet: it may be a frame behind. Kept a moment.
                    local h = { t = now, unit = unit, rel = rel, x = x, y = y, action = action, indicator = indicator,
                                amount = amount, school = school, pet = pet, key = key }
                    held[#held + 1] = h
                    if #held > 8 then table.remove(held, 1) end
                    mineHit = false
                    why = "no log line yet: held"
                end
            else
                mineHit = yours(unit, key, action, now)
            end
            -- What arrives for nameplates, and what was done with it (the
            -- last 24, MinimalUIDB.ctlog): to find out why misses and dodges
            -- on a mob were not showing.
            if MinimalUIDB then
                local d = MinimalUIDB.ctlog
                if type(d) ~= "table" then d = {}; MinimalUIDB.ctlog = d end
                d[#d + 1] = string.format("%.2f %s %s / %s  amount %s  school %s  %s%s", GetTime() % 1000,
                    unit == "target" and (onRail and "target(rail)" or "target(skipped: has a plate)") or (onRail and "plate(rail)" or "plate"), action,
                    tostring(not secret(indicator) and indicator or "?"),
                    secret(amount) and "hidden" or tostring(amount),
                    secret(school) and "hidden" or tostring(school),
                    mineHit and "shown" or "dropped", why ~= "" and (" (" .. why .. ")") or "")
                if #d > 90 then table.remove(d, 1) end
            end
            if not mineHit then return end
            petShown = byPet
        end
        if not x then return end
        present(unit, rel, x, y, action, indicator, amount, school, mine, petShown)
    end)
end

function NP:OnInit(db)
    self.db = db
    if db.numbers ~= false then
        pcall(quietGame, true)
        local ok, err = pcall(buildNumbers)
        if not ok and MinimalUIDB then MinimalUIDB.ctdiag = "build failed: " .. tostring(err) end
    end
    if not C_NamePlate then return end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            -- The bright ring moves to the new target's plate.
            for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do pcall(stylePlate, plate) end
            return
        end
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then pcall(stylePlate, plate, unit) end
    end)
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do pcall(stylePlate, plate) end
end
