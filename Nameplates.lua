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
local SCHOOL_TINT = { [1] = { 0.94, 0.94, 0.96 }, [2] = { 1.00, 0.90, 0.50 }, [4] = { 1.00, 0.56, 0.28 },
    [8] = { 0.55, 0.90, 0.45 }, [16] = { 0.55, 0.82, 1.00 }, [32] = { 0.74, 0.60, 1.00 }, [64] = { 1.00, 0.62, 0.90 } }
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
    --     side and a cool one to the other, closing in.
    local SIZE = 20
    local function item()
        for i = 1, #items do if not items[i].live then return items[i] end end
        if #items >= NUM_POOL then return nil end
        local f = CreateFrame("Frame", nil, host)
        f:SetSize(10, 10)
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
                        -- The fringe: apart at first, closing and fading in half a second.
                        local q = f.age < 0.9 and (1 - f.age / 0.9) or 0
                        f.warm:SetPoint("CENTER", -5.5 * q, 1.0 * q)
                        f.cool:SetPoint("CENTER", 5.5 * q, -1.0 * q)
                        f.warm:SetAlpha(0.9 * q); f.cool:SetAlpha(0.9 * q)
                        -- A burst of light behind it as it lands, gone in under half a second.
                        local bq = f.age < 0.42 and (1 - f.age / 0.42) or 0
                        f.burst:SetAlpha(0.60 * bq * bq)
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
        f.burst:SetVertexColor(r, g, b, 1)
        f.burst:SetAlpha(0)
        f.crit, f.scale = crit, scale
        -- A critical stays up most of a second longer than an ordinary
        -- hit, and its colour fringe takes longer to close.
        f.life = crit and (NUM_LIFE + 0.9) or NUM_LIFE
        f:SetScale(scale)
        f.rel = rel
        -- Five lanes side by side, so a burst doesn't stack; each drifts a
        -- little further out the way it already leans.
        local lane = (spawned % 5) - 2
        f.x = x + lane * 16
        f.drift = lane * 7
        f.y = y
        f.fs:SetTextColor(r, g, b)
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
    --     1.2 s; each one accounts for one hit) and the unit is your target;
    --   * or the unit carries a damage-over-time effect of yours and the
    --     hit falls on a tick (every 3 s from when you cast it);
    --   * a heal: you have just cast a helping spell.
    -- It misses melee swings (they announce nothing), and lets through
    -- someone else's hit that lands in the same instant as yours.
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
    local function swinging(now)
        local f = (C_Spell and C_Spell.IsCurrentSpell) or _G.IsCurrentSpell
        local okA, auto = pcall(f, 6603)
        if not okA or secret(auto) or not auto then return false end
        local okS, speed = pcall(UnitAttackSpeed, "player")
        if not okS or secret(speed) or type(speed) ~= "number" or speed <= 0 then speed = 2 end
        if now - lastSwing >= speed * 0.8 then lastSwing = now; return true end
        return false
    end
    local function yours(unit, plate, action, now)
        why = ""
        if action == "HEAL" then why = "heal"; return take(heals, now) end
        local okT, isTarget = pcall(UnitIsUnit, unit, "target")
        isTarget = okT and not secret(isTarget) and isTarget == true
        if isTarget and take(hits, now) then why = "cast"; return true end
        if isTarget and swinging(now) then why = "swing"; return true end
        local list = plate and dots[plate]
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
            hits[#hits + 1] = now + 1.2
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
            local plate = not auto and plateOf("target")
            if not auto and not plate then
                -- (No nameplate at this range: the target frame stands in.)
                local UFm = ns.modules.UnitFrames
                local tf = UFm and UFm.target
                plate = tf and (tf.healthPill or tf) or nil
            end
            if plate then
                local list = dots[plate]
                if not list then list = {}; dots[plate] = list end
                list[#list + 1] = now
                if #list > 4 then table.remove(list, 1) end
            end
        end)
    end

    -- A nameplate going away with numbers still rising from it (the mob
    -- died a moment after the hit was shown): they move to the target
    -- frame and finish there, instead of vanishing with the plate.
    local gone = CreateFrame("Frame")
    pcall(gone.RegisterEvent, gone, "NAME_PLATE_UNIT_REMOVED")
    gone:SetScript("OnEvent", function(_, _, unit)
        if type(unit) ~= "string" or secret(unit) then return end
        local UFm = ns.modules.UnitFrames
        local tf = UFm and UFm.target
        local home = tf and tf:IsShown() and (tf.healthPill or tf) or nil
        local moved, dropped = 0, 0
        for i = 1, #items do
            local f = items[i]
            if f.live and f.unit == unit then
                if home and f.onTarget then
                    f.rel, f.unit = home, nil
                    moved = moved + 1
                else
                    f.live = false
                    f:Hide()
                    dropped = dropped + 1
                end
            end
        end
        if MinimalUIDB and (moved + dropped) > 0 then
            local d = MinimalUIDB.ctlog
            if type(d) == "table" then
                d[#d + 1] = string.format("%.2f PLATE GONE %s: %d moved to the target frame, %d dropped", GetTime() % 1000, unit, moved, dropped)
            end
        end
    end)
    -- The same, found another way: your target is dead. (Its nameplate can
    -- stop being drawn at death without being reported as removed; a number
    -- hung on it went with it.) Looked for ten times a second while any
    -- number is up.
    local watch = CreateFrame("Frame")
    local wacc = 0
    watch:SetScript("OnUpdate", function(_, dt)
        wacc = wacc + dt
        if wacc < 0.1 then return end
        wacc = 0
        local any = false
        for i = 1, #items do if items[i].live and items[i].onTarget and items[i].unit then any = true break end end
        if not any then return end
        local okD, dead = pcall(UnitIsDeadOrGhost, "target")
        if not okD or secret(dead) or not dead then return end
        local UFm = ns.modules.UnitFrames
        local tf = UFm and UFm.target
        local home = tf and tf:IsShown() and (tf.healthPill or tf) or nil
        if not home then return end
        local moved = 0
        for i = 1, #items do
            local f = items[i]
            if f.live and f.onTarget and f.unit then
                f.rel, f.unit = home, nil
                moved = moved + 1
            end
        end
        if MinimalUIDB and moved > 0 and type(MinimalUIDB.ctlog) == "table" then
            local d = MinimalUIDB.ctlog
            d[#d + 1] = string.format("%.2f TARGET DEAD: %d moved to the target frame", GetTime() % 1000, moved)
        end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_COMBAT")
    ev:SetScript("OnEvent", function(_, _, unit, action, indicator, amount, school)
        if type(unit) ~= "string" or secret(unit) or secret(action) or type(action) ~= "string" then return end
        showUnit = unit
        local mine = unit == "player"
        local x, y, rel
        if mine then
            -- What you take already rises out of the health orb, when that
            -- is on (Extras: orbText): not shown a second time here.
            local EX = ns.modules.Extras
            local OR = ns.modules.Orbs
            if EX and EX.db and EX.db.orbText ~= false and OR and OR.health and OR.health:IsShown() then return end
            local w, h = UIParent:GetWidth(), UIParent:GetHeight()
            x, y = w / 2 + (action == "HEAL" and 80 or -80), h * 0.46
        elseif unit:find("^nameplate") or unit == "target" then
            if unit == "target" then
                -- Your target is too far off to have a nameplate (they only
                -- reach so far): its numbers rise from the target frame
                -- instead. With a nameplate up, the nameplate's own report
                -- of the same hit is the one shown.
                if not plateOf("target") then
                    local UFm = ns.modules.UnitFrames
                    local tf = UFm and UFm.target
                    rel = tf and tf:IsShown() and (tf.healthPill or tf) or nil
                end
            else
                rel = plateOf(unit)
                -- The blow that kills: the nameplate is on its way out (it
                -- goes with the mob), and a number hung on it went with it.
                -- If it is your target, the number goes on the target frame.
                local okD, dead = pcall(UnitIsDeadOrGhost, unit)
                if rel and okD and not secret(dead) and dead then
                    local okT, isT = pcall(UnitIsUnit, unit, "target")
                    local UFm = ns.modules.UnitFrames
                    local tf = UFm and UFm.target
                    if okT and not secret(isT) and isT and tf and tf:IsShown() then rel = tf.healthPill or tf end
                end
            end
            if rel then x, y = 0, 4 end
            -- A hit for nothing at all isn't worth a number (when the
            -- amount can be read; in a fight it usually can't).
            if action == "WOUND" and not secret(amount) and amount == 0 then return end
            local mineHit = not (rel and guess) or yours(unit, rel, action, GetTime())
            -- What arrives for nameplates, and what was done with it (the
            -- last 24, MinimalUIDB.ctlog): to find out why misses and dodges
            -- on a mob were not showing.
            if MinimalUIDB then
                local d = MinimalUIDB.ctlog
                if type(d) ~= "table" then d = {}; MinimalUIDB.ctlog = d end
                d[#d + 1] = string.format("%.2f %s %s / %s  amount %s  school %s  %s%s", GetTime() % 1000,
                    unit == "target" and (rel and "target(frame)" or "target(skipped: has a plate)") or "plate", action,
                    tostring(not secret(indicator) and indicator or "?"),
                    secret(amount) and "hidden" or tostring(amount),
                    secret(school) and "hidden" or tostring(school),
                    mineHit and "shown" or "dropped", why ~= "" and (" (" .. why .. ")") or "")
                if #d > 40 then table.remove(d, 1) end
            end
            if not mineHit then return end
        end
        if not x then return end
        local crit = not secret(indicator) and indicator == "CRITICAL"
        local kind = NP.db.numbersKind ~= false and not secret(school) and SCHOOL_ICON[school] or nil
        if action == "HEAL" then
            show(rel, x, y, amount, 0.42, 0.92, 0.50, crit)
        elseif action == "WOUND" then
            if mine then
                show(rel, x, y, amount, 0.96, 0.42, 0.38, crit, nil, kind)
            else
                local c = (not secret(school) and SCHOOL_TINT[school]) or SCHOOL_TINT[1]
                show(rel, x, y, amount, c[1], c[2], c[3], crit, nil, kind)
            end
        elseif WORDS[action] then
            show(rel, x, y, WORDS[action], 0.80, 0.80, 0.86, false, true)
        end
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
