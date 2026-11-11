local _, ns = ...
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

function NP:OnInit(db)
    self.db = db
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
