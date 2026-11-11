local _, ns = ...

-- Flat dark, hairline borders, single accent.
local Theme = {
    bg      = { 0.07, 0.07, 0.08, 0.92 },
    bgAlt   = { 0.11, 0.11, 0.13, 0.92 },
    border  = { 0.20, 0.20, 0.23, 1 },
    accent  = { 0.31, 0.76, 0.97, 1 },
    text    = { 0.92, 0.92, 0.94, 1 },
    textDim = { 0.60, 0.60, 0.65, 1 },
    font    = STANDARD_TEXT_FONT or (GameFontNormal and GameFontNormal:GetFont()),
    fontSize = 12,
    bar     = "Interface/Buttons/WHITE8X8",
}
ns.Theme = Theme

-- ── Fonts ─────────────────────────────────────────────────────────────────
-- All Meniscus text goes through ns:SetFont, which remembers each string's
-- size/flags so a font change applies live (ns:ApplyFont).
-- Choices: Inter (bundled in Media, the default), font files the client
-- actually has (from Blizzard's font objects plus known stock files, each
-- verified by rendering test text), plus Media/font.ttf if you drop one there.
-- bold = true uses the family's heavier weight (names, headings) when it has one.
local MEDIA_FONTS = "Interface/AddOns/Meniscus/Media/"
local INTER = { key = "inter", label = "Inter", path = MEDIA_FONTS .. "inter-400.ttf",
                bold = MEDIA_FONTS .. "inter-600.ttf" }
-- Manrope runs a step heavier than its nominal weights (500 body, 700 bold):
-- its 400 is thin at UI sizes.
local MANROPE = { key = "manrope", label = "Manrope", path = MEDIA_FONTS .. "manrope-500.ttf",
                  bold = MEDIA_FONTS .. "manrope-700.ttf" }
local BUNDLED = { [INTER.key] = INTER, [MANROPE.key] = MANROPE }
Theme.defaultFont = Theme.font -- Blizzard's
Theme.font, Theme.fontBold = INTER.path, INTER.bold

ns.fontStrings = setmetatable({}, { __mode = "k" })

function ns:SetFont(fs, size, flags, bold)
    self.fontStrings[fs] = { size or Theme.fontSize, flags or "", bold }
    fs:SetFont(bold and Theme.fontBold or Theme.font, size or Theme.fontSize, flags or "")
end

local function fontWorks(path)
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    local ok = pcall(probe.SetFont, probe, path, 14, "")
    if not ok then return false end
    local ok2 = pcall(probe.SetText, probe, "Abc 123")
    local w = ok2 and probe:GetStringWidth() or 0
    probe:SetText("")
    return w > 0
end

local KNOWN = {
    frizqt__ = "Friz Quadrata", arialn = "Arial Narrow", skurri = "Skurri",
    morpheus = "Morpheus", ["2002"] = "2002", ["2002b"] = "2002 Bold",
}
local function labelFor(path)
    local base = path:gsub("\\", "/"):match("([^/]+)%.[tT][tT][fF]$") or path
    return KNOWN[base:lower()] or base
end

function ns:BuildFontList()
    local list, seen = {}, {}
    local function add(key, label, path, trusted, bold)
        local norm = path:gsub("\\", "/"):lower()
        if seen[norm] or not (trusted or fontWorks(path)) then return end
        seen[norm] = true
        table.insert(list, { key = key, label = label, path = path, bold = bold })
    end
    add(INTER.key, INTER.label, INTER.path, true, INTER.bold)
    add(MANROPE.key, MANROPE.label, MANROPE.path, true, MANROPE.bold)
    add("default", "Blizzard (" .. labelFor(Theme.defaultFont) .. ")", Theme.defaultFont, true)
    local paths = {}
    for _, obj in ipairs({ "GameFontNormal", "ChatFontNormal", "NumberFontNormal", "QuestFont",
                           "SystemFont_Med1", "GameFontNormalHuge", "SystemFont_Shadow_Huge3",
                           "Game72Font", "Fancy16Font", "DestinyFontLarge" }) do
        local o = _G[obj]
        if o and o.GetFont then
            local p = o:GetFont()
            if p then table.insert(paths, p) end
        end
    end
    for _, p in ipairs({ "Fonts/FRIZQT__.TTF", "Fonts/ARIALN.TTF", "Fonts/skurri.ttf",
                         "Fonts/MORPHEUS.TTF", "Fonts/2002.ttf", "Fonts/2002B.ttf" }) do
        table.insert(paths, p)
    end
    for _, p in ipairs(paths) do add(p:gsub("\\", "/"):lower(), labelFor(p), p) end
    add("custom", "Custom (Media/font.ttf)", "Interface/AddOns/Meniscus/Media/font.ttf")
    Theme.fonts = list
    return list
end

-- Switch every Meniscus string to the chosen font now, and remember it.
local function setAll(path, bold)
    Theme.font, Theme.fontBold = path, bold or path
    for fs, s in pairs(ns.fontStrings) do
        pcall(fs.SetFont, fs, s[3] and Theme.fontBold or path, s[1], s[2])
    end
end

function ns:ApplyFont(key)
    local list = Theme.fonts or self:BuildFontList()
    local choice = list[1]
    for _, f in ipairs(list) do if f.key == key then choice = f end end
    setAll(choice.path, choice.bold)
    if MinimalUIDB then
        MinimalUIDB.font, MinimalUIDB.fontPath, MinimalUIDB.fontBold = choice.key, choice.path, choice.bold
    end
    return choice
end

-- On load, use the saved path directly (it was verified when chosen), so
-- startup doesn't depend on font files being loaded yet. No choice yet = Inter.
local fontLoader = CreateFrame("Frame")
fontLoader:RegisterEvent("ADDON_LOADED")
fontLoader:SetScript("OnEvent", function(self, _, name)
    if name ~= ns.name then return end
    self:UnregisterAllEvents()
    local db = MinimalUIDB
    -- The saved font paths include the addon's folder name. After the addon
    -- was renamed they pointed at a folder that no longer exists, every
    -- SetFont failed, and the first SetText on such a string raised "Font
    -- not set" (which took the unit frames down). Point them at wherever
    -- this addon lives now.
    if db then
        for _, k in ipairs({ "fontPath", "fontBold" }) do
            if type(db[k]) == "string" then
                db[k] = (db[k]:gsub("^Interface/AddOns/[^/]+/", "Interface/AddOns/" .. ns.name .. "/"))
            end
        end
    end
    -- One-time switch to Inter when it was introduced (earlier picks were tests).
    if db and not db.fontInterMigrated then
        db.fontInterMigrated, db.font, db.fontPath, db.fontBold = true, INTER.key, INTER.path, INTER.bold
    end
    if not db or not db.font or db.font == INTER.key or not db.fontPath then
        Theme.font, Theme.fontBold = INTER.path, INTER.bold
        if db then db.font = INTER.key end
    elseif BUNDLED[db.font] then
        -- Bundled families always use their current files (weights may change).
        local f = BUNDLED[db.font]
        Theme.font, Theme.fontBold = f.path, f.bold
        db.fontPath, db.fontBold = f.path, f.bold
    elseif db.font == "default" then
        Theme.font, Theme.fontBold = Theme.defaultFont, Theme.defaultFont
    else
        Theme.font, Theme.fontBold = db.fontPath, db.fontBold or db.fontPath
    end
end)

-- /men font : what Meniscus is using right now.
ns.commands = ns.commands or {}
ns.commands.font = function()
    ns:Print("Font in use: " .. tostring(Theme.font) .. "  (saved: " .. tostring(MinimalUIDB.font) .. ")")
    for _, f in ipairs(Theme.fonts or ns:BuildFontList()) do ns:Print("  " .. f.label .. " -> " .. f.path) end
end

-- Rounded rectangle (hand-built 9-slice: rounded.tga quarter corners plus
-- flat bands) drawn as textures on f, so the radius stays round at any size.
local CORNER_Q = 14 / 64 -- corner region of rounded.tga (radius 14 of 64)
function ns.RoundedRect(f, sub, inset, radius, r, g, b, a, layer)
    layer = layer or "BACKGROUND"
    local corners, bands = {}, {}
    local function corner(point, l, rr, t, bb, x, y)
        local c = f:CreateTexture(nil, layer, nil, sub)
        c:SetTexture("Interface/AddOns/Meniscus/Media/rounded.tga")
        c:SetTexCoord(l, rr, t, bb)
        c:SetVertexColor(r, g, b, a)
        c:SetSize(radius, radius)
        c:SetPoint(point, f, point, x, y)
        table.insert(corners, c)
    end
    local q = CORNER_Q
    corner("TOPLEFT", 0, q, 0, q, inset, -inset)
    corner("TOPRIGHT", 1 - q, 1, 0, q, -inset, -inset)
    corner("BOTTOMLEFT", 0, q, 1 - q, 1, inset, inset)
    corner("BOTTOMRIGHT", 1 - q, 1, 1 - q, 1, -inset, inset)
    local function band()
        local t = f:CreateTexture(nil, layer, nil, sub)
        t:SetColorTexture(r, g, b, a)
        table.insert(bands, t)
        return t
    end
    local mid = band()
    mid:SetPoint("TOPLEFT", f, "TOPLEFT", inset + radius, -inset)
    mid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(inset + radius), inset)
    local left = band()
    left:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -(inset + radius))
    left:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", inset + radius, inset + radius)
    local right = band()
    right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -(inset + radius))
    right:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -(inset + radius), inset + radius)
    -- Recolor all parts at once (corners use vertex color, bands color texture).
    return function(nr, ng, nb, na)
        for _, c in ipairs(corners) do c:SetVertexColor(nr, ng, nb, na) end
        for _, t in ipairs(bands) do t:SetColorTexture(nr, ng, nb, na) end
    end
end

-- ── Color tweens ──────────────────────────────────────────────────────────
-- Hover / press feedback eases between colors instead of snapping:
-- ease-out cubic, ~120ms in, ~180ms out, ~40ms on press. One shared driver,
-- only running while something is animating. key.__muiCol holds the color
-- currently shown, so a new target starts from wherever the last one got.
local tweens = {}
local tweener = CreateFrame("Frame")
tweener:Hide()
tweener:SetScript("OnUpdate", function(self, dt)
    for key, t in pairs(tweens) do
        t.e = t.e + dt
        local k = t.d > 0 and math.min(1, t.e / t.d) or 1
        local e = 1 - (1 - k) ^ 3
        local c = key.__muiCol
        for i = 1, 4 do c[i] = t.from[i] + (t.to[i] - t.from[i]) * e end
        t.paint(c[1], c[2], c[3], c[4])
        if k >= 1 then tweens[key] = nil end
    end
    if not next(tweens) then self:Hide() end
end)

function ns.TweenColor(key, paint, r, g, b, a, dur)
    a = a or 1
    key.__muiCol = key.__muiCol or { r, g, b, a }
    local c, t = key.__muiCol, tweens[key]
    if t and t.to[1] == r and t.to[2] == g and t.to[3] == b and t.to[4] == a then return end
    if not t and c[1] == r and c[2] == g and c[3] == b and c[4] == a then paint(r, g, b, a); return end
    -- Hidden frames snap: nobody sees the fade, so don't spend frames on it.
    if dur == 0 or (key.IsVisible and not key:IsVisible()) then
        tweens[key] = nil
        c[1], c[2], c[3], c[4] = r, g, b, a
        paint(r, g, b, a)
        return
    end
    tweens[key] = { from = { c[1], c[2], c[3], c[4] }, to = { r, g, b, a }, e = 0, d = dur or 0.15, paint = paint }
    tweener:Show()
end

-- Wrap a RoundedRect paint function so the button's color changes ease:
-- quick toward hover, a touch slower back to rest.
function ns.EasePaint(b, raw)
    return function(r, g, bl, a)
        ns.TweenColor(b, raw, r, g, bl, a, b.hover and 0.12 or 0.18)
    end
end

-- Garbage-free frame walking. `{ f:GetChildren() }` builds a new table on
-- every call, and the recurring scans (damage meter, tracker, Blizzard aura
-- frames) made hundreds a second. These fill a reusable buffer instead.
-- Recursive walks pass their depth so each level gets its own buffer:
--   local kids, n = ns.Kids(f, depth)
--   for i = 1, n do local c = kids[i] ... end
-- Don't hold on to the buffer: the next call at that depth overwrites it.
-- (Avoid on frames with hundreds of children, e.g. UIParent: select(i, ...)
-- makes the copy quadratic.)
local kidBufs, regBufs = {}, {}
local function fill(buf, ...)
    local n = select("#", ...)
    for i = 1, n do buf[i] = (select(i, ...)) end
    for i = n + 1, buf.n or 0 do buf[i] = nil end
    buf.n = n
    return buf, n
end
function ns.Kids(f, depth)
    depth = depth or 0
    local b = kidBufs[depth]
    if not b then b = { n = 0 }; kidBufs[depth] = b end
    return fill(b, f:GetChildren())
end
function ns.Regs(f, depth)
    depth = depth or 0
    local b = regBufs[depth]
    if not b then b = { n = 0 }; regBufs[depth] = b end
    return fill(b, f:GetRegions())
end

-- Item / spell tooltips in Meniscus windows: use the player's tooltip
-- placement (Edit Mode default anchor) instead of pinning beside the button.
function ns.TipAnchor(owner)
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, owner)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
end

-- Hide a non-secure Blizzard region/frame and keep it hidden.
function ns.Kill(obj)
    if not obj or obj.__muiKilled then return end
    if obj.IsProtected and obj:IsProtected() then return end
    obj.__muiKilled = true
    obj:Hide()
    hooksecurefunc(obj, "Show", function(self) self:Hide() end)
    if obj.SetShown then
        hooksecurefunc(obj, "SetShown", function(self, s) if s then self:Hide() end end)
    end
end

local function px() -- 1 physical pixel in UI units
    local _, h = GetPhysicalScreenSize()
    local scale = UIParent:GetEffectiveScale()
    return (768 / h) / scale
end
ns.Pixel = px

-- Flat panel with 1px border built from textures (no Backdrop dependency).
function ns:CreatePanel(parent, name)
    local p = CreateFrame("Frame", name, parent or UIParent)
    local t = p:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(unpack(Theme.bg))
    p.bg = t

    local w = px()
    p.borders = {}
    local function edge(a1, a2, setSize)
        local e = p:CreateTexture(nil, "BORDER")
        e:SetColorTexture(unpack(Theme.border))
        e:SetPoint(a1, p, a1)
        e:SetPoint(a2, p, a2)
        setSize(e)
        table.insert(p.borders, e)
    end
    edge("TOPLEFT", "TOPRIGHT",       function(e) e:SetHeight(w) end)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", function(e) e:SetHeight(w) end)
    edge("TOPLEFT", "BOTTOMLEFT",     function(e) e:SetWidth(w) end)
    edge("TOPRIGHT", "BOTTOMRIGHT",   function(e) e:SetWidth(w) end)

    function p:SetBorderColor(r, g, b, a)
        for _, e in ipairs(self.borders) do e:SetColorTexture(r, g, b, a or 1) end
    end
    return p
end

-- Flat status bar. Safe with secret values: only call SetMinMaxValues/SetValue.
function ns:CreateBar(parent, name)
    local bar = CreateFrame("StatusBar", name, parent)
    bar:SetStatusBarTexture(Theme.bar)
    bar:SetStatusBarColor(unpack(Theme.accent))
    return bar
end

function ns:CreateText(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size or Theme.fontSize, "")
    fs:SetTextColor(unpack(color or Theme.text))
    return fs
end

-- ── Pill bars ─────────────────────────────────────────────────────────────
-- Rounded-end status bars. Masks/rings are generated at fixed aspect ratios
-- (8:1, 16:1, 32:1) so the end caps stay perfectly round; pick w/h to match.
local MEDIA = "Interface/AddOns/Meniscus/Media/"
-- 128:1 is for long thin bars whose width follows other frames (XP bar); at
-- ~6px tall the caps are tiny, so stretching it to other long ratios is invisible.
local PILL_RATIOS = { 8, 16, 32, 128 }

local function pickRatio(w, h)
    local best, bestErr = 8, math.huge
    for _, r in ipairs(PILL_RATIOS) do
        local err = math.abs(w / h - r)
        if err < bestErr then best, bestErr = r, err end
    end
    return best
end
ns.PillRatio = pickRatio

-- Returns a Frame with:
--   .bar   StatusBar (safe for secret values: SetMinMaxValues/SetValue only)
--   .ring  outline texture  (:SetRingColor(r,g,b,a))
--   .text  layer helper: use pill:CreateText(size) to put text above the ring
function ns:CreatePillBar(parent, w, h)
    local ratio = pickRatio(w, h)
    local base = MEDIA .. "pill" .. ratio

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)

    local mask = f:CreateMaskTexture()
    mask:SetTexture(base .. "_mask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(f)
    f.mask = mask

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    f.bg:AddMaskTexture(mask)

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetAllPoints(f)
    f.bar:SetStatusBarTexture(Theme.bar)
    f.bar:SetStatusBarColor(unpack(Theme.accent))
    local fill = f.bar:GetStatusBarTexture()
    fill:AddMaskTexture(mask)

    -- Bright edge riding the end of the fill (echoes the orbs' surface line).
    f.edge = f.bar:CreateTexture(nil, "OVERLAY", nil, 0)
    f.edge:SetWidth(2)
    f.edge:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    f.edge:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    f.edge:SetColorTexture(1, 1, 1, 0.45)
    f.edge:AddMaskTexture(mask)

    -- Soft sheen toward the top.
    f.sheen = f.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    f.sheen:SetAllPoints(f.bar)
    f.sheen:SetColorTexture(1, 1, 1, 1)
    pcall(f.sheen.SetGradient, f.sheen, "VERTICAL",
        CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.14))
    f.sheen:AddMaskTexture(mask)

    f.ring = f.bar:CreateTexture(nil, "OVERLAY", nil, 3)
    f.ring:SetAllPoints(f)
    f.ring:SetTexture(base .. "_ring.tga")
    f.ring:SetVertexColor(unpack(Theme.border))

    function f:SetRingColor(r, g, b, a) self.ring:SetVertexColor(r, g, b, a or 1) end

    -- Fill from the right end instead of the left: what is left of the bar
    -- stays against the right cap and the empty part grows from the left.
    -- The bright edge and any split text (below) follow the moving end.
    function f:SetReverse(on)
        on = on and true or false
        if self.reversed == on then return end
        self.reversed = on
        self.bar:SetReverseFill(on)
        local fl = self.bar:GetStatusBarTexture()
        self.edge:ClearAllPoints()
        if on then
            self.edge:SetPoint("TOPLEFT", fl, "TOPLEFT")
            self.edge:SetPoint("BOTTOMLEFT", fl, "BOTTOMLEFT")
        else
            self.edge:SetPoint("TOPRIGHT", fl, "TOPRIGHT")
            self.edge:SetPoint("BOTTOMRIGHT", fl, "BOTTOMRIGHT")
        end
        for _, sp in ipairs(self.bar.__splits or {}) do
            sp.track:ClearAllPoints(); sp.over:ClearAllPoints()
            if on then
                sp.track:SetPoint("TOPLEFT", self.bar, "TOPLEFT")
                sp.track:SetPoint("BOTTOMRIGHT", fl, "BOTTOMLEFT")
                sp.over:SetPoint("TOPLEFT", fl, "TOPLEFT")
                sp.over:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT")
            else
                sp.track:SetPoint("TOPLEFT", fl, "TOPRIGHT")
                sp.track:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT")
                sp.over:SetPoint("TOPLEFT", self.bar, "TOPLEFT")
                sp.over:SetPoint("BOTTOMRIGHT", fl, "BOTTOMRIGHT")
            end
        end
    end

    -- split = true: the text follows the fill, light over the empty track and
    -- dark where the fill has reached (ns.SplitText).
    function f:CreateText(size, color, split)
        local fs = ns:CreateText(self.bar, size, color)
        fs:SetDrawLayer("OVERLAY", 7)
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.8)
        if split then ns.SplitText(self.bar, fs) end
        return fs
    end
    return f
end

-- Text that adapts to a bar's fill: the given font string is clipped to the
-- empty track (keeps its light color), and a dark copy is clipped to the
-- fill. The cut follows the fill's edge, so a half-full bar reads dark on
-- the filled part and light on the rest. The copy mirrors text, font,
-- justification and visibility; position it by anchoring the original.
-- Works with hidden (secret) values: the engine places the fill edge.
local DARK = { 0.07, 0.07, 0.08, 1 }
function ns.SplitText(bar, fs)
    local fill = bar:GetStatusBarTexture()
    local level = bar:GetFrameLevel() + 4 -- above the pill's ring and sheen
    local track = CreateFrame("Frame", nil, bar)
    track:SetClipsChildren(true)
    track:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    track:SetFrameLevel(level)
    local over = CreateFrame("Frame", nil, bar)
    over:SetClipsChildren(true)
    over:SetPoint("TOPLEFT", bar, "TOPLEFT")
    over:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    over:SetFrameLevel(level)
    fs:SetParent(track)
    -- (Remembered so the pill can swap them when its fill is reversed.)
    bar.__splits = bar.__splits or {}
    table.insert(bar.__splits, { track = track, over = over })

    local dark = over:CreateFontString(nil, "OVERLAY", nil, 7)
    dark:SetAllPoints(fs)
    local font, size, flags = fs:GetFont()
    if font then dark:SetFont(font, size, flags) end
    dark:SetJustifyH(fs:GetJustifyH())
    dark:SetJustifyV(fs:GetJustifyV())
    dark:SetWordWrap(false)
    dark:SetTextColor(unpack(DARK))
    dark:SetShadowOffset(1, -1)
    dark:SetShadowColor(1, 1, 1, 0.25)
    dark:SetText(fs:GetText() or "")
    dark:SetShown(fs:IsShown())

    hooksecurefunc(fs, "SetText", function(_, t) dark:SetText(t) end)
    hooksecurefunc(fs, "SetFormattedText", function(_, ...) pcall(dark.SetFormattedText, dark, ...) end)
    hooksecurefunc(fs, "SetFont", function(_, ...) dark:SetFont(...) end)
    hooksecurefunc(fs, "SetJustifyH", function(_, j) dark:SetJustifyH(j) end)
    hooksecurefunc(fs, "Show", function() dark:Show() end)
    hooksecurefunc(fs, "Hide", function() dark:Hide() end)
    hooksecurefunc(fs, "SetShown", function(_, s) dark:SetShown(s) end)
    fs.dark = dark
    return dark
end

-- ── Shared helpers ────────────────────────────────────────────────────────
-- Protected call that returns the function's results (nothing on error or
-- when fn isn't a function). No table per call, so it's safe in hot paths.
local function pass(ok, ...)
    if ok then return ... end
end
function ns.Call(fn, ...)
    if type(fn) ~= "function" then return end
    return pass(pcall(fn, ...))
end

-- Pill button, shared by every window.
--   opts.h       height (22)            opts.font    text size (11)
--   opts.pad     side padding (24)      opts.minW    minimum width (44)
--   opts.ring    hairline ring          opts.dimIdle dim text until hovered
--   opts.primary light "main action" pill (accent on hover)
-- State: b.on / b.selected (lit), b.primary, disabled via SetEnabled.
-- b:SetLabel(text, minW) resizes to fit; b:Repaint() after changing state.
local PILL_OFF, PILL_HOVER = { 0.15, 0.15, 0.17, 1 }, { 0.21, 0.21, 0.24, 1 }
local PILL_ON, PILL_TEXT_DARK = { 0.86, 0.86, 0.89, 1 }, { 0.08, 0.08, 0.09, 1 }
local NO_OPTS = {}
local function pillRepaint(self)
    local fs = self.fs
    if not self:IsEnabled() then
        self.paint(0.11, 0.11, 0.12, 1); fs:SetTextColor(0.38, 0.38, 0.42)
    elseif self.primary then
        local c = self.hover and Theme.accent or PILL_ON
        self.paint(c[1], c[2], c[3], c[4] or 1); fs:SetTextColor(0.08, 0.08, 0.09)
    elseif self.on or self.selected then
        self.paint(0.86, 0.86, 0.89, 1); fs:SetTextColor(0.08, 0.08, 0.09)
    elseif self.hover then
        self.paint(0.21, 0.21, 0.24, 1); fs:SetTextColor(Theme.text[1], Theme.text[2], Theme.text[3])
    else
        local c = self.dimIdle and Theme.textDim or Theme.text
        self.paint(0.15, 0.15, 0.17, 1); fs:SetTextColor(c[1], c[2], c[3])
    end
end
local function pillSetLabel(self, l, minW)
    self.fs:SetWidth(0)
    self.fs:SetText(l)
    self:SetWidth(math.max(self.fs:GetStringWidth() + self.pad, minW or self.minW))
end
local function pillEnter(self) self.hover = true; self:Repaint() end
local function pillLeave(self) self.hover = false; self:Repaint() end
function ns.Pill(parent, label, onClick, opts)
    opts = opts or NO_OPTS
    local h = opts.h or 22
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(h)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.fs, opts.font or 11, "", true)
    b.fs:SetPoint("CENTER")
    if opts.ring then
        ns.RoundedRect(b, -7, -1, h / 2 + 1, Theme.border[1], Theme.border[2], Theme.border[3], 1)
    end
    b.paint = ns.EasePaint(b, ns.RoundedRect(b, -6, 0, h / 2, unpack(PILL_OFF)))
    b.pad, b.minW = opts.pad or 24, opts.minW or 44
    b.dimIdle, b.primary = opts.dimIdle, opts.primary
    b.Repaint, b.SetLabel = pillRepaint, pillSetLabel
    b:SetScript("OnEnter", pillEnter)
    b:SetScript("OnLeave", pillLeave)
    b:SetScript("OnClick", onClick)
    hooksecurefunc(b, "SetEnabled", pillRepaint)
    b:SetLabel(label or "")
    b:Repaint()
    return b
end
