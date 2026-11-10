local _, ns = ...
local T = ns.Theme

-- Window shell: the header band every MinimalUI window shares (the NPC
-- dialog's look). A slightly lighter band with a faint white-noise grain,
-- a ring on the left holding a 3D head (popping out of the top) or an icon,
-- title, dim subtitle, an optional status chip, a round close button, and a
-- bottom-right slot for window controls (search, toggles).
--
--   local sh = ns:CreateShell(win, { onClose = fn })
--   sh:SetTitle(text [, r, g, b])   sh:SetSubtitle(text)
--   sh:SetChip(text, color) / sh:SetChip(nil)
--   sh:SetRing(color)               sh:SetUnit(unit) / sh:SetIcon(texture)
--   sh.band   -- anchor controls to its BOTTOMRIGHT (-14, 14)
-- Content goes below ns.SHELL_H.

local MEDIA = "Interface/AddOns/MinimalUI/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local BAND = { 0.095, 0.10, 0.11, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local TALK_ANIM = 60
ns.SHELL_H = 92

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

-- Footer band: the header's twin at the bottom of a window (same grain,
-- hairline on top), so the action pills sit on their own clearly marked
-- strip instead of floating at the end of the content.
--   local band = ns:CreateFooter(win, height)
function ns:CreateFooter(win, h)
    local band = CreateFrame("Frame", nil, win)
    band:SetPoint("BOTTOMLEFT", 1, 1)
    band:SetPoint("BOTTOMRIGHT", -1, 1)
    band:SetHeight(h)
    ns.RoundedRect(band, -6, 0, 13, unpack(BAND))
    local sq = band:CreateTexture(nil, "BACKGROUND", nil, -5) -- square top corners
    sq:SetPoint("TOPLEFT"); sq:SetPoint("TOPRIGHT"); sq:SetHeight(14)
    sq:SetColorTexture(unpack(BAND))
    local noise = band:CreateTexture(nil, "BACKGROUND", nil, -4)
    noise:SetPoint("TOPLEFT", 6, 0)
    noise:SetPoint("BOTTOMRIGHT", -6, 2)
    noise:SetTexture(MEDIA .. "noise.tga", "REPEAT", "REPEAT")
    noise:SetHorizTile(true); noise:SetVertTile(true)
    noise:SetVertexColor(1, 1, 1, 0.07)
    local line = band:CreateTexture(nil, "BORDER")
    line:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
    return band
end

function ns:CreateShell(win, opts)
    opts = opts or {}
    local S = {}

    local band = CreateFrame("Frame", nil, win)
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(ns.SHELL_H)
    ns.RoundedRect(band, -6, 0, 13, unpack(BAND))
    local sq = band:CreateTexture(nil, "BACKGROUND", nil, -5) -- square bottom corners
    sq:SetPoint("BOTTOMLEFT"); sq:SetPoint("BOTTOMRIGHT"); sq:SetHeight(14)
    sq:SetColorTexture(unpack(BAND))
    local noise = band:CreateTexture(nil, "BACKGROUND", nil, -4)
    noise:SetPoint("TOPLEFT", 6, -2)
    noise:SetPoint("BOTTOMRIGHT", -6, 0)
    noise:SetTexture(MEDIA .. "noise.tga", "REPEAT", "REPEAT")
    noise:SetHorizTile(true); noise:SetVertTile(true)
    noise:SetVertexColor(1, 1, 1, 0.07)
    local line = band:CreateTexture(nil, "BORDER")
    line:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
    S.band = band

    -- Ring: 3D head popping out, or an icon.
    local D = 64
    local av = CreateFrame("Frame", nil, band)
    av:SetSize(D, D)
    av:SetPoint("LEFT", band, "LEFT", 16, -4)
    local function disc(size, sub)
        local t = av:CreateTexture(nil, "BACKGROUND", nil, sub)
        t:SetSize(size, size); t:SetPoint("CENTER")
        local m = av:CreateMaskTexture()
        m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        return t
    end
    local ring = disc(D, 0)
    local inner = disc(D - 4, 1)
    inner:SetColorTexture(0.05, 0.05, 0.06, 1)
    local tint = disc(D - 4, 2)
    local flat = av:CreateTexture(nil, "ARTWORK")
    flat:SetSize(D - 4, D - 4); flat:SetPoint("CENTER")
    local fm = av:CreateMaskTexture()
    fm:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fm:SetAllPoints(flat)
    flat:AddMaskTexture(fm)
    local icon = av:CreateTexture(nil, "ARTWORK", nil, 1)
    icon:SetSize(D - 22, D - 22); icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local im = av:CreateMaskTexture()
    im:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    im:SetAllPoints(icon)
    icon:AddMaskTexture(im)
    local model = CreateFrame("PlayerModel", nil, av)
    model:SetFrameLevel(av:GetFrameLevel() + 1)
    model:SetSize(0.8 * D, 1.05 * D)
    model:SetPoint("BOTTOM", av, "CENTER", 0, -0.3 * D)
    model:SetScript("OnAnimFinished", function(self) pcall(self.SetAnimation, self, 0) end)
    local lip = CreateFrame("Frame", nil, av)
    lip:SetAllPoints()
    lip:SetFrameLevel(model:GetFrameLevel() + 1)
    local lipRing
    for i, file in ipairs({ "lip_fill.tga", "lip_rim.tga", "lip_ring.tga" }) do
        local t = lip:CreateTexture(nil, "ARTWORK", nil, i)
        t:SetAllPoints()
        t:SetTexture(MEDIA .. file)
        if i == 1 then t:SetVertexColor(0.05, 0.05, 0.06, 1)
        elseif i == 2 then t:SetVertexColor(1, 1, 1, 0.35)
        else lipRing = t end
    end
    S.model = model

    local title = text(band, 16, true)
    title:SetPoint("TOPLEFT", av, "TOPRIGHT", 14, -6)
    title:SetPoint("RIGHT", band, "RIGHT", -44, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    local sub = text(band, 11, false, T.textDim)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    local chip = CreateFrame("Frame", nil, band)
    chip:SetHeight(16)
    chip:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -6)
    local chipPaint = ns.RoundedRect(chip, -6, 0, 8, 0.2, 0.2, 0.2, 1)
    local chipText = text(chip, 10, true)
    chipText:SetPoint("CENTER")
    chip:Hide()

    local close = CreateFrame("Button", nil, band)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -12, -12)
    local cm = close:CreateMaskTexture()
    cm:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    cm:SetSize(20, 20); cm:SetPoint("CENTER")
    local cbg = close:CreateTexture(nil, "BACKGROUND")
    cbg:SetSize(20, 20); cbg:SetPoint("CENTER")
    cbg:SetColorTexture(0.16, 0.16, 0.18, 1)
    cbg:AddMaskTexture(cm)
    local xs = {}
    for i, p in ipairs({ { -1, 1, 1, -1 }, { -1, -1, 1, 1 } }) do
        local l = close:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetStartPoint("CENTER", close, p[1] * 4, p[2] * 4)
        l:SetEndPoint("CENTER", close, p[3] * 4, p[4] * 4)
        l:SetColorTexture(unpack(T.textDim))
        xs[i] = l
    end
    close:SetScript("OnEnter", function()
        cbg:SetColorTexture(unpack(T.accent)); for _, l in ipairs(xs) do l:SetColorTexture(unpack(TEXT_DARK)) end
    end)
    close:SetScript("OnLeave", function()
        cbg:SetColorTexture(0.16, 0.16, 0.18, 1); for _, l in ipairs(xs) do l:SetColorTexture(unpack(T.textDim)) end
    end)
    close:SetScript("OnClick", function() if opts.onClose then opts.onClose() else win:Hide() end end)
    S.close = close

    function S:SetTitle(t, r, g, b)
        title:SetText(t or "")
        if r then title:SetTextColor(r, g, b) else title:SetTextColor(unpack(T.text)) end
    end
    function S:SetSubtitle(t) sub:SetText(t or "") end
    function S:SetSubtitleWidth(w) sub:SetWidth(w) end
    function S:SetChip(t, color)
        if not t then chip:Hide(); return end
        color = color or T.accent
        chipText:SetText(t)
        chipText:SetTextColor(color[1], color[2], color[3])
        chipPaint(color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 1)
        chip:SetWidth(chipText:GetStringWidth() + 16)
        chip:Show()
    end
    function S:SetRing(color)
        color = color or { T.border[1] + 0.15, T.border[2] + 0.15, T.border[3] + 0.15 }
        ring:SetColorTexture(color[1], color[2], color[3], 1)
        tint:SetColorTexture(color[1], color[2], color[3], 0.12)
        lipRing:SetVertexColor(color[1], color[2], color[3], 1)
    end
    -- 3D head of a unit (talk animation optional), flat portrait if out of sight.
    function S:SetUnit(unit, talk)
        icon:Hide()
        local exists = UnitExists(unit)
        local visible = exists and UnitIsVisible(unit)
        if issecretvalue and issecretvalue(visible) then visible = true end
        if visible then
            flat:Hide()
            lip:Show()
            model:Show()
            model:ClearModel()
            model:SetUnit(unit)
            pcall(model.SetPortraitZoom, model, 1)
            pcall(model.SetCamDistanceScale, model, 1)
            pcall(model.SetPosition, model, 0, 0.04, 0)
            pcall(model.SetAnimation, model, talk and TALK_ANIM or 0)
        else
            model:Hide()
            lip:Hide()
            if exists then SetPortraitTexture(flat, unit) end
            flat:SetShown(exists)
        end
    end
    function S:SetIcon(texture)
        model:Hide()
        lip:Hide()
        flat:Hide()
        icon:SetTexture(texture)
        icon:Show()
    end
    function S:ClearModel() model:ClearModel() end
    -- NPC windows: ring + chip show how the NPC sees you (same everywhere).
    function S:SetAttitude(unit)
        local r
        if UnitExists(unit) then
            local ok, v = pcall(UnitReaction, unit, "player")
            if ok and type(v) == "number" and not (issecretvalue and issecretvalue(v)) then r = v end
        end
        if not r then self:SetRing(); self:SetChip(nil); return end
        local label, color
        if r <= 3 then label, color = "Hostile", { 0.92, 0.38, 0.35 }
        elseif r == 4 then label, color = "Neutral", { 0.95, 0.80, 0.35 }
        else label, color = "Friendly", { 0.45, 0.85, 0.50 } end
        self:SetRing(color)
        self:SetChip(label, color)
    end
    -- Controls placed on the band must sit above it, or the band's own
    -- background paints over theirs (same frame level).
    function S:Lift(...)
        for i = 1, select("#", ...) do
            local f = select(i, ...)
            if f and f.SetFrameLevel then f:SetFrameLevel(band:GetFrameLevel() + 5) end
        end
    end

    S:SetRing()
    return S
end
