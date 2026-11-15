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
    local function item()
        for i = 1, #items do if not items[i].live then return items[i] end end
        if #items >= NUM_POOL then return nil end
        local f = CreateFrame("Frame", nil, host)
        f:SetSize(10, 10)
        f.fs = f:CreateFontString(nil, "OVERLAY")
        ns:SetFont(f.fs, 15, "OUTLINE", true)
        f.fs:SetPoint("CENTER")
        f.fs:SetShadowOffset(1, -1)
        f.fs:SetShadowColor(0, 0, 0, 0.9)
        items[#items + 1] = f
        return f
    end
    driver:SetScript("OnUpdate", function(self, dt)
        local any = false
        for i = 1, #items do
            local f = items[i]
            if f.live then
                f.age = f.age + dt
                local k = f.age / NUM_LIFE
                if k >= 1 then
                    f.live = false
                    f:Hide()
                else
                    any = true
                    -- Up quickly, then easing off; clear until the last third.
                    local e = 1 - (1 - k) * (1 - k)
                    -- (A critical lands large and settles; positions are in
                    -- the frame's own units, so the scale is divided out.)
                    local sc = f.scale
                    if f.crit and f.age < 0.16 then sc = 1.7 - 0.4 * f.age / 0.16 end
                    f:SetScale(sc)
                    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", f.x / sc, (f.y + NUM_RISE * e) / sc)
                    f:SetAlpha(k < 0.66 and 1 or (1 - k) / 0.34)
                end
            end
        end
        if not any then self:Hide() end
    end)
    local function show(x, y, value, r, g, b, crit, small)
        local f = item()
        if not f then return end
        -- (A hidden amount goes straight in; nothing is done with it here.)
        local ok = pcall(f.fs.SetText, f.fs, value)
        if MinimalUIDB and not MinimalUIDB.ctdiag then
            MinimalUIDB.ctdiag = "first number: hidden=" .. tostring(secret(value)) .. " type=" .. type(value) .. " shown=" .. tostring(ok)
        end
        if not ok then return end
        spawned = spawned + 1
        local scale = crit and 1.3 or (small and 0.8 or 1)
        f.crit, f.scale = crit, scale
        f:SetScale(scale)
        f.x = x + ((spawned % 5) - 2) * 13
        f.y = y
        f.fs:SetTextColor(r, g, b)
        f.age, f.live = 0, true
        f:SetAlpha(1)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", f.x / scale, f.y / scale)
        f:Show()
        driver:Show()
    end
    -- Where a unit's numbers start: just above its nameplate.
    local function plateSpot(unit)
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
        local x, y = plate:GetCenter()
        if not (x and y) then return end
        local k = plate:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return x * k, y * k + 16
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_COMBAT")
    ev:SetScript("OnEvent", function(_, _, unit, action, indicator, amount, school)
        if type(unit) ~= "string" or secret(unit) or secret(action) or type(action) ~= "string" then return end
        local mine = unit == "player"
        local x, y
        if mine then
            -- What you take already rises out of the health orb, when that
            -- is on (Extras: orbText): not shown a second time here.
            local EX = ns.modules.Extras
            local OR = ns.modules.Orbs
            if EX and EX.db and EX.db.orbText ~= false and OR and OR.health and OR.health:IsShown() then return end
            local w, h = UIParent:GetWidth(), UIParent:GetHeight()
            x, y = w / 2 + (action == "HEAL" and 80 or -80), h * 0.46
        elseif unit:find("^nameplate") then
            x, y = plateSpot(unit)
        end
        if not x then return end
        local crit = not secret(indicator) and indicator == "CRITICAL"
        if action == "HEAL" then
            show(x, y, amount, 0.42, 0.92, 0.50, crit)
        elseif action == "WOUND" then
            if mine then
                show(x, y, amount, 0.96, 0.42, 0.38, crit)
            else
                local c = (not secret(school) and SCHOOL_TINT[school]) or SCHOOL_TINT[1]
                show(x, y, amount, c[1], c[2], c[3], crit)
            end
        elseif WORDS[action] then
            show(x, y, WORDS[action], 0.62, 0.62, 0.68, false, true)
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
