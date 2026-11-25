local _, ns = ...
local CreateFrame = ns.CreateFrame

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

-- A font string whose SetFont didn't take has no font at all, and its first
-- SetText raises "Font not set", which took a whole module down at login.
-- So the result is checked: on a miss, the regular weight is tried, then
-- the game's own font, with a sane size; the miss is noted (with where it
-- came from) in MinimalUIDB.fontFail for the next look at the saved file.
local function fontTook(fs)
    local ok, path = pcall(fs.GetFont, fs)
    return ok and path ~= nil
end
function ns:SetFont(fs, size, flags, bold)
    size, flags = size or Theme.fontSize, flags or ""
    self.fontStrings[fs] = { size, flags, bold }
    local want = bold and Theme.fontBold or Theme.font
    pcall(fs.SetFont, fs, want, size, flags)
    if fontTook(fs) then return end
    local sane = (type(size) == "number" and size == size and size >= 4 and size <= 200) and size or 12
    local db = MinimalUIDB
    if db then
        db.fontFail = db.fontFail or {}
        if #db.fontFail < 8 then
            db.fontFail[#db.fontFail + 1] = { path = tostring(want), size = tostring(size), flags = tostring(flags),
                bold = bold and true or false, regular = tostring(Theme.font), at = date("%H:%M:%S"),
                stack = debugstack(2, 8, 0) }
        end
    end
    pcall(fs.SetFont, fs, Theme.font, sane, flags)
    if not fontTook(fs) then
        pcall(fs.SetFont, fs, _G.STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF", sane, flags)
    end
    -- The wanted font may simply not have been ready this early (a cold
    -- start): try it again shortly, over the stand-in.
    if C_Timer and type(want) == "string" then
        C_Timer.After(1.5, function() pcall(fs.SetFont, fs, want, sane, flags) end)
    end
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
    -- A fresh install (no font saved at all) starts on Manrope.
    if db and not db.fontInterMigrated then
        if db.font == nil then
            db.fontInterMigrated, db.font, db.fontPath, db.fontBold = true, MANROPE.key, MANROPE.path, MANROPE.bold
        else
            db.fontInterMigrated, db.font, db.fontPath, db.fontBold = true, INTER.key, INTER.path, INTER.bold
        end
    end
    if db and db.font and BUNDLED[db.font] and db.font ~= INTER.key and not db.fontPath then
        -- (A bundled family named without its files, as the defaults
        -- migration in Core.lua leaves it: filled in just below.)
        db.fontPath = BUNDLED[db.font].path
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
    -- Warm the font files up now. The client loads a font file the first
    -- time it is used, and for a moment after that first use the string has
    -- no font: the unit frames (the first module to draw text, at login)
    -- got exactly that, every time, and a label that set its text straight
    -- away raised "Font not set". Two hidden strings ask for both weights
    -- here, a little before anything is built.
    for _, path in ipairs({ Theme.font, Theme.fontBold }) do
        if type(path) == "string" then
            local warm = UIParent:CreateFontString(nil, "BACKGROUND")
            warm:SetAlpha(0)
            if pcall(warm.SetFont, warm, path, 12, "") then pcall(warm.SetText, warm, "Aa") end
        end
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
-- The bands' grain, edge to edge. A band is rounded on one side (top for a
-- header, bottom for a footer), and a tiled texture can't follow a curve on
-- its own, so it is laid in pieces: the body, the strip between the two
-- rounded corners, and one piece per corner cut to the curve with a mask.
-- (It used to stop 6 px short of each side instead, which left a plain
-- stripe down both edges of every window.)
function ns.BandNoise(band, radius, top)
    local function piece()
        local t = band:CreateTexture(nil, "BACKGROUND", nil, -4)
        t:SetTexture("Interface/AddOns/Meniscus/Media/noise.tga", "REPEAT", "REPEAT")
        t:SetHorizTile(true); t:SetVertTile(true)
        t:SetVertexColor(1, 1, 1, 0.07)
        return t
    end
    local v, o = top and "TOP" or "BOTTOM", top and "BOTTOM" or "TOP"
    local body = piece()
    body:SetPoint(v .. "LEFT", band, v .. "LEFT", 0, top and -radius or radius)
    body:SetPoint(o .. "RIGHT", band, o .. "RIGHT", 0, 0)
    local mid = piece()
    mid:SetPoint(v .. "LEFT", band, v .. "LEFT", radius, 0)
    mid:SetPoint(v .. "RIGHT", band, v .. "RIGHT", -radius, 0)
    mid:SetHeight(radius)
    local size = radius / (14 / 64) -- rounded.tga at the size whose corner is this radius
    for _, h in ipairs({ "LEFT", "RIGHT" }) do
        local c = piece()
        c:SetSize(radius, radius)
        c:SetPoint(v .. h, band, v .. h, 0, 0)
        local m = band:CreateMaskTexture()
        m:SetTexture("Interface/AddOns/Meniscus/Media/rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetSize(size, size)
        m:SetPoint(v .. h, band, v .. h, 0, 0)
        c:AddMaskTexture(m)
    end
end

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

-- Item / spell tooltips in Meniscus windows sit beside the window the
-- mouse is in, level with the thing hovered: on the window's right, or its
-- left when there is more room there (a window docked on the right). So a
-- tooltip is always next to what it describes and never covers the list
-- being read. Anything outside our windows uses the player's own tooltip
-- placement (Edit Mode default anchor).
local function ownWindow(f)
    local cur = f
    for _ = 1, 12 do
        if not cur or cur == UIParent then return nil end
        if rawget(cur, "shell") then return cur end -- our windows keep their header shell here
        cur = cur.GetParent and cur:GetParent()
    end
end
local function plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end

function ns.TipAnchor(owner)
    local win = ownWindow(owner)
    if win and win:IsShown() then
        local l, r, wt, ot = win:GetLeft(), win:GetRight(), win:GetTop(), owner:GetTop()
        if plain(l) and plain(r) and plain(wt) and plain(ot) then
            local k = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local spaceR, spaceL = UIParent:GetWidth() - r * k, l * k
            local dy = math.min(0, ot * (owner:GetEffectiveScale() / win:GetEffectiveScale()) - wt)
            GameTooltip:SetOwner(owner, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            if spaceR >= 340 or spaceR >= spaceL then
                GameTooltip:SetPoint("TOPLEFT", win, "TOPRIGHT", 8, dy)
            else
                GameTooltip:SetPoint("TOPRIGHT", win, "TOPLEFT", -8, dy)
            end
            return
        end
    end
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, owner)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
end

-- ── "Compared with what you wear" ─────────────────────────────────────────
-- Adds, to an item tooltip, how the item's stats differ from the piece
-- equipped in its slot: green for what you gain, red for what you lose.
-- (For rings, trinkets and one-hand weapons: against each of the two.)
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
ns.EquipSlots = SLOTS -- (Alts.lua: which crafted things are gear)
local function itemStats(link)
    local f = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
    if not f then return nil end
    local ok, t = pcall(f, link)
    return ok and type(t) == "table" and t or nil
end
ns.ItemStats = itemStats -- (the inspect window adds up someone's gear with it)
local function statLabel(key)
    local s = _G[key]
    if type(s) == "string" and s ~= "" then return s end
    return (key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower():gsub("^%l", string.upper))
end

-- A stat's emblem, as text markup: the character panel's own icons (heart
-- for Stamina, bulb for Intellect...), each in its own colour, so that a
-- comparison reads as pictures and numbers. nil for a stat with no emblem.
-- The colour of each kind of damage, by the game's school number: one list
-- for the whole addon (combat numbers, the health orb, the character
-- window's resistances, item comparisons), so fire is the same orange
-- wherever it shows.
ns.SCHOOL = { [1] = { 0.94, 0.94, 0.96 }, -- physical
              [2] = { 1.00, 0.90, 0.50 }, -- holy
              [4] = { 1.00, 0.56, 0.28 }, -- fire
              [8] = { 0.55, 0.90, 0.45 }, -- nature
              [16] = { 0.55, 0.82, 1.00 }, -- frost
              [32] = { 0.74, 0.60, 1.00 }, -- shadow
              [64] = { 1.00, 0.62, 0.90 } } -- arcane
local SC = ns.SCHOOL

local STAT_MARK = {
    ITEM_MOD_STRENGTH_SHORT = { "stat_str", 0.92, 0.48, 0.38 },
    ITEM_MOD_AGILITY_SHORT = { "stat_agi", 0.55, 0.85, 0.40 },
    ITEM_MOD_STAMINA_SHORT = { "stat_sta", 0.95, 0.72, 0.32 },
    ITEM_MOD_INTELLECT_SHORT = { "stat_int", 0.45, 0.68, 1.00 },
    ITEM_MOD_SPIRIT_SHORT = { "stat_spi", 0.72, 0.58, 1.00 },
    RESISTANCE0_NAME = { "stat_defense", 0.78, 0.80, 0.86 },
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = { "stat_melee", 0.86, 0.86, 0.90 },
    ITEM_MOD_SPELL_POWER_SHORT = { "stat_spell", 0.70, 0.80, 1.00 },
    RESISTANCE2_NAME = { "stat_fire", SC[4][1], SC[4][2], SC[4][3] },
    RESISTANCE3_NAME = { "stat_nature", SC[8][1], SC[8][2], SC[8][3] },
    RESISTANCE4_NAME = { "stat_frost", SC[16][1], SC[16][2], SC[16][3] },
    RESISTANCE5_NAME = { "stat_shadow", SC[32][1], SC[32][2], SC[32][3] },
    RESISTANCE6_NAME = { "stat_arcane", SC[64][1], SC[64][2], SC[64][3] },
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = { "stat_guard", 0.62, 0.78, 0.92 },
}
-- The game lists some stats under two names (an item's fire resistance came
-- as both, and showed twice in a comparison: once as a picture, once in
-- words). The second names, and the one each is kept under. (0.1.627)
local STAT_ALIAS = {
    ITEM_MOD_FIRE_RESISTANCE_SHORT = "RESISTANCE2_NAME", ITEM_MOD_NATURE_RESISTANCE_SHORT = "RESISTANCE3_NAME",
    ITEM_MOD_FROST_RESISTANCE_SHORT = "RESISTANCE4_NAME", ITEM_MOD_SHADOW_RESISTANCE_SHORT = "RESISTANCE5_NAME",
    ITEM_MOD_ARCANE_RESISTANCE_SHORT = "RESISTANCE6_NAME", ITEM_MOD_ARMOR_SHORT = "RESISTANCE0_NAME",
    ITEM_MOD_DEFENSE_SKILL_SHORT = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
}
-- (By their words too, whatever the name: "Fire Resistance", "Defense".)
local aliasByWord
local function canon(key)
    if STAT_ALIAS[key] then return STAT_ALIAS[key] end
    if STAT_MARK[key] then return key end
    if not aliasByWord then
        aliasByWord = {}
        for k in pairs(STAT_MARK) do
            local w = _G[k]
            if type(w) == "string" and w ~= "" then aliasByWord[w:lower()] = k end
        end
        for n = 2, 6 do
            local w = _G["RESISTANCE" .. n .. "_NAME"]
            if type(w) == "string" then aliasByWord[w:lower()] = "RESISTANCE" .. n .. "_NAME" end
        end
        for w, k in pairs({ ["fire resistance"] = 2, ["nature resistance"] = 3, ["frost resistance"] = 4,
                            ["shadow resistance"] = 5, ["arcane resistance"] = 6 }) do
            aliasByWord[w] = "RESISTANCE" .. k .. "_NAME"
        end
        aliasByWord["defense"] = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"
    end
    local w = _G[key]
    return type(w) == "string" and aliasByWord[w:lower()] or key
end
-- An item's stats with each kept once, under its first name.
local function tidy(t)
    if not t then return nil end
    local out
    for k, v in pairs(t) do
        local c = canon(k)
        if c ~= k then
            out = out or {}
            out[k] = c
        end
    end
    if not out then return t end
    local r = {}
    for k, v in pairs(t) do if not out[k] then r[k] = v end end
    for k, c in pairs(out) do if r[c] == nil then r[c] = t[k] end end
    return r
end
function ns.StatMark(key, size, dy)
    local m = STAT_MARK[key]
    if not m then return nil end
    size = size or 16
    dy = dy or -2
    -- (Drawn larger than the text and dropped a little: the emblem only
    -- fills the middle two thirds of its square, so at the text's own size
    -- it looked small and sat high on the line.)
    return string.format("|TInterface/AddOns/Meniscus/Media/micro_%s.tga:%d:%d:0:%d:32:32:0:32:0:32:%d:%d:%d|t",
        m[1], size, size, dy, math.floor(m[2] * 255), math.floor(m[3] * 255), math.floor(m[4] * 255))
end
-- The same emblem, asked for by the stat's name as the game writes it
-- ("Stamina", "Armor"): for marking up lines the game wrote.
local markByName
function ns.StatMarkByName(name, size, dy)
    if not markByName then
        markByName = {}
        for key in pairs(STAT_MARK) do
            local word = _G[key]
            if type(word) == "string" and word ~= "" then markByName[word:lower()] = key end
        end
        -- (Their plain English names too, should a global be missing.)
        for word, key in pairs({ strength = "ITEM_MOD_STRENGTH_SHORT", agility = "ITEM_MOD_AGILITY_SHORT",
                                 stamina = "ITEM_MOD_STAMINA_SHORT", intellect = "ITEM_MOD_INTELLECT_SHORT",
                                 spirit = "ITEM_MOD_SPIRIT_SHORT", armor = "RESISTANCE0_NAME" }) do
            if not markByName[word] and STAT_MARK[key] then markByName[word] = key end
        end
    end
    local key = type(name) == "string" and markByName[name:lower()]
    return key and ns.StatMark(key, size, dy) or nil
end
-- Pings: the game only pings a frame that says it can take one, as its own
-- unit frames do: a ping mixin (it answers "what is this" from f.unit) and
-- the receiver attribute. Your own frame and orbs take the player's own
-- kind where the client has it: pinging the stock player frame says your
-- health and mana in chat, and the plain unit kind only pointed at you.
-- What each frame was given, and what it answers, is kept in
-- MinimalUIDB.pingdiag.
-- Inside an instance (0.1.626): the game hides from addons which creature a
-- unit is, and a ping on one of our frames has to say exactly that, so it
-- did nothing there (read from the count: "target, creature hidden, in an
-- instance"). The game's own "/ping [@unit]" can still say it. So, inside
-- an instance only, the ping key is pointed at a hidden button that runs
-- that line for as long as the pointer is on the frame; it is all done by
-- the game's protected handlers, so it holds in a fight. Outside, nothing
-- is changed and the hold-for-the-wheel ping works as before.
local pingHead, pingFrames = nil, {}
local function pingKeys()
    if InCombatLockdown() then pingHead.late = true return end
    pingHead.late = nil
    local inside = IsInInstance and IsInInstance()
    local k1, k2
    if inside == true and GetBindingKey then k1, k2 = GetBindingKey("TOGGLEPINGLISTENER") end
    for _, fr in ipairs(pingFrames) do
        pcall(fr.SetAttribute, fr, "men-pingkey1", k1 or nil)
        pcall(fr.SetAttribute, fr, "men-pingkey2", k2 or nil)
        if ClearOverrideBindings then pcall(ClearOverrideBindings, fr) end
    end
    if MinimalUIDB then
        MinimalUIDB.pingkeys = (inside == true and "inside" or "outside") .. ", ping key " .. (k1 and "found" or "none")
            .. ", frames " .. #pingFrames
    end
end
local function pingByKey(f, unit)
    if not (SecureHandlerWrapScript and f.IsProtected and f:IsProtected()) or InCombatLockdown() then return "not set up" end
    if not pingHead then
        pingHead = CreateFrame("Frame", "MeniscusPingHead", UIParent, "SecureHandlerBaseTemplate")
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED" }) do
            pcall(pingHead.RegisterEvent, pingHead, e)
        end
        pingHead:SetScript("OnEvent", function(self, e)
            if e == "PLAYER_REGEN_ENABLED" and not self.late then return end
            pcall(pingKeys)
        end)
    end
    local name = "MeniscusPing_" .. unit
    local b = _G[name]
    if not b then
        b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/ping [@" .. unit .. ",exists]")
        b:RegisterForClicks("AnyDown", "AnyUp")
        -- (Both edges, as everywhere here: the game acts on the one its
        -- own key-down setting names, so it is one ping for one press.)
    end
    f:SetAttribute("men-pingbtn", name)
    SecureHandlerWrapScript(f, "OnEnter", pingHead, [[
        local b = self:GetAttribute("men-pingbtn")
        local k1, k2 = self:GetAttribute("men-pingkey1"), self:GetAttribute("men-pingkey2")
        if k1 then self:SetBindingClick(true, k1, b) end
        if k2 then self:SetBindingClick(true, k2, b) end
    ]])
    SecureHandlerWrapScript(f, "OnLeave", pingHead, [[ self:ClearBindings() ]])
    pcall(SecureHandlerWrapScript, f, "OnHide", pingHead, [[ self:ClearBindings() ]])
    pingFrames[#pingFrames + 1] = f
    return "key route set"
end
function ns.MakePingable(f, unit, portrait)
    if not Mixin then return end
    -- The player's kind asks one thing of its frame: is the pointer over
    -- the portrait (self.PlayerFrameContainer.PlayerPortrait)? Over it, the
    -- ping is the ordinary one at you; anywhere else on the frame it is the
    -- "my health and mana" one. Ours had no such piece and the game's code
    -- stopped on that. An orb has no portrait: all of it is the resource.
    -- (portrait: a function saying whether the pointer is over one.)
    if unit == "player" and f.PlayerFrameContainer == nil then
        f.PlayerFrameContainer = { PlayerPortrait = {
            IsMouseOver = function() return portrait and portrait() and true or false end } }
    end
    local own = unit == "player" and _G.PingableType_PlayerUnitFrameMixin
    local mix = own or _G.PingableType_UnitFrameMixin
    if not mix then return end
    pcall(Mixin, f, mix)
    local note = (own and "player kind" or "unit kind")
    if own then
        -- (If the player's kind can't answer for a frame of ours, the plain
        -- one is put back: a ping that points at you beats a Lua error.)
        local okT, a, b, c = pcall(f.GetTargetInfo, f)
        note = note .. " GetTargetInfo ok=" .. tostring(okT) .. " " .. tostring(a) .. " " .. tostring(b) .. " " .. tostring(c)
        if type(a) == "table" then
            local parts = {}
            for k, v in pairs(a) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
            note = note .. " {" .. table.concat(parts, ", ") .. "}"
        end
        if not okT and _G.PingableType_UnitFrameMixin then
            pcall(Mixin, f, _G.PingableType_UnitFrameMixin)
            note = note .. " -> unit kind put back"
        end
    end
    -- (0.1.625: pings on the target frame stopped working, with an error
    -- inside the game's ping code during a dungeon run and none since.
    -- What the game is answered each time it asks one of our frames is
    -- counted, by kind only, in MinimalUIDB.pingask: to be read, not guessed.)
    if not own and type(f.GetTargetInfo) == "function" then
        local ask = f.GetTargetInfo
        f.GetTargetInfo = function(self, ...)
            local ok, info = pcall(ask, self, ...)
            pcall(function()
                local how = not ok and ("error: " .. tostring(info):sub(1, 120))
                    or type(info) ~= "table" and ("answer is " .. type(info))
                    or (issecretvalue and issecretvalue(info.guid)) and "creature hidden"
                    or ("creature " .. type(info.guid))
                local inst = IsInInstance and IsInInstance()
                how = tostring(self.unit) .. ", " .. how .. (inst == true and ", in an instance" or ", outside")
                    .. (InCombatLockdown() and ", in a fight" or "")
                MinimalUIDB.pingask = MinimalUIDB.pingask or {}
                MinimalUIDB.pingask[how] = (MinimalUIDB.pingask[how] or 0) + 1
            end)
            if not ok then error(info, 0) end
            return info
        end
    end
    pcall(f.SetAttribute, f, "ping-receiver", true)
    if not own and type(unit) == "string" and unit ~= "player" then
        local ok, how = pcall(pingByKey, f, unit)
        note = note .. ", " .. tostring(ok and how or ("key route failed: " .. tostring(how):sub(1, 100)))
    end
    if MinimalUIDB then
        MinimalUIDB.pingdiag = MinimalUIDB.pingdiag or {}
        MinimalUIDB.pingdiag[tostring(f.GetName and f:GetName() or unit)] = note
    end
end

-- A coin, as text markup: a small flat disc in gold, silver or copper.
ns.COIN = {
    g = "|TInterface/AddOns/Meniscus/Media/circle.tga:9:9:2:0:32:32:0:32:0:32:230:194:90|t",
    s = "|TInterface/AddOns/Meniscus/Media/circle.tga:9:9:2:0:32:32:0:32:0:32:184:188:198|t",
    c = "|TInterface/AddOns/Meniscus/Media/circle.tga:9:9:2:0:32:32:0:32:0:32:201:138:82|t",
}

-- The same comparison as one short coloured line for a tile:
-- "+3 Agi  +12 Armor  -2 Sta" (biggest changes first, at most four).
-- Returns nil for things that aren't gear or whose data hasn't arrived,
-- "" .. note for an empty slot / identical stats.
local SHORT = { Agility = "Agi", Strength = "Str", Stamina = "Sta", Intellect = "Int", Spirit = "Spi",
                ["Damage Per Second"] = "DPS", ["Attack Power"] = "AP", ["Spell Power"] = "SP",
                ["Critical Strike"] = "Crit" }
local function byMagnitude(a, b) return math.abs(a[2]) > math.abs(b[2]) end
function ns.CompareWith(link, worn)
    local new = tidy(itemStats(link))
    if not new then return nil end
    if not worn then return "|cff8fd19eNothing equipped there|r" end
    if worn == link then return "|cff9a9aa5You're wearing this|r" end
    local old = tidy(itemStats(worn))
    if not old then return nil end
    local diffs = {}
    for k, v in pairs(new) do
        local d = v - (old[k] or 0)
        if math.abs(d) > 0.05 then diffs[#diffs + 1] = { k, d } end
    end
    for k, v in pairs(old) do
        if new[k] == nil and v > 0.05 then diffs[#diffs + 1] = { k, -v } end
    end
    if #diffs == 0 then return "|cff9a9aa5Same stats as equipped|r" end
    table.sort(diffs, byMagnitude)
    local out = ""
    for i = 1, math.min(#diffs, 4) do
        local d = diffs[i][2]
        local a = math.abs(d)
        local label = statLabel(diffs[i][1])
        label = SHORT[label] or label
        local mark = ns.StatMark(diffs[i][1], 16)
        out = out .. (i > 1 and "   " or "") .. (mark and (mark .. " ") or "") .. (d > 0 and "|cff73d980+" or "|cffe57373-")
            .. ((a % 1 > 0.05) and string.format("%.1f", a) or string.format("%d", a + 0.5))
            .. (mark and "" or (" " .. label)) .. "|r"
    end
    if #diffs > 4 then out = out .. "  |cff9a9aa5\226\128\166|r" end
    return out
end
function ns.CompareLine(link)
    if type(link) ~= "string" or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, link)
    local slots = ok and SLOTS[loc]
    if not slots then return nil end
    local worn
    for _, slot in ipairs(slots) do
        local l = GetInventoryItemLink("player", slot)
        if l then worn = l break end
    end
    return ns.CompareWith(link, worn)
end

-- The comparison as rows for a card: a list of coloured strings, one stat
-- per row, biggest change first (at most "max"). A single grey row says
-- when there is nothing to list. nil: not gear, or its data hasn't arrived.
function ns.CompareRows(link, max)
    if type(link) ~= "string" or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, link)
    local slots = ok and SLOTS[loc]
    if not slots then return nil end
    local new = tidy(itemStats(link))
    if not new then return nil end
    local worn
    for _, slot in ipairs(slots) do
        local l = GetInventoryItemLink("player", slot)
        if l then worn = l break end
    end
    if not worn then return { "|cff8fd19eEmpty slot|r" } end
    if worn == link then return { "|cff9a9aa5Equipped|r" } end
    local old = tidy(itemStats(worn))
    if not old then return nil end
    local diffs = {}
    for k, v in pairs(new) do
        local d = v - (old[k] or 0)
        if math.abs(d) > 0.05 then diffs[#diffs + 1] = { k, d } end
    end
    for k, v in pairs(old) do
        if new[k] == nil and v > 0.05 then diffs[#diffs + 1] = { k, -v } end
    end
    if #diffs == 0 then return { "|cff9a9aa5No change|r" } end
    table.sort(diffs, byMagnitude)
    max = max or 4
    local rows = {}
    for i = 1, math.min(#diffs, max) do
        local d = diffs[i][2]
        local a = math.abs(d)
        -- (The emblem stands for the word where there is one.)
        local mark = ns.StatMark(diffs[i][1], 17)
        rows[i] = (mark and (mark .. " ") or "") .. (d > 0 and "|cff73d980+" or "|cffe57373-")
            .. ((a % 1 > 0.05) and string.format("%.1f", a) or string.format("%d", a + 0.5))
            .. (mark and "" or (" " .. statLabel(diffs[i][1]))) .. "|r"
    end
    if #diffs > max then rows[max] = rows[max] .. "  |cff9a9aa5+" .. (#diffs - max) .. " more|r" end
    return rows
end

-- Is this piece an upgrade? A quick yes / no for a mark on a tile (the
-- tooltip's stat comparison is the detail): gear you can use, of the armor
-- type you wear, with a higher item level than what is in its slot (the
-- weaker of the two for rings and trinkets), or for a slot that is empty.
-- Answers are remembered per link until your gear or level changes.
local upCache = {}
local OFFHAND = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }
local function gearLevel(link)
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
    if not f then return nil end
    local ok, l = pcall(f, link)
    if ok and type(l) == "number" and not issecretvalue(l) then return l end
end
-- Weapon subclasses that are tools: 14 miscellaneous (skinning knife,
-- mining pick, blacksmith hammer), 20 fishing poles.
local TOOL_WEAPON = { [14] = true, [20] = true }
local function weaponDps(link)
    local st = itemStats(link)
    local d = st and st.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
    if type(d) == "number" and not issecretvalue(d) then return d end
end
local function equipLocOf(link)
    local ok, _, _, _, loc, _, classID, subID = pcall(C_Item.GetItemInfoInstant, link)
    if ok then return loc, classID, subID end
end
-- What a piece is worth to your class (0.1.526): each stat times a weight,
-- and a little for its armour. Armour, rings, trinkets and things held in
-- the off hand are judged by this, not by item level: a higher-level green
-- with fewer of the stats you want was being marked over a blue (a robe
-- with +6 Int +3 Spi over one with +6 Sta +4 Int +4 Spi). The weights are
-- by class, not by build, and plain on purpose: what a levelling character
-- of that class mostly wants. Enchantments are not counted on either side
-- (the game's stat reading leaves them out).
--                 Str   Agi   Sta   Int   Spi   armour
local WEIGHTS = {
    WARRIOR = { 1.0, 0.6, 0.8, 0.0, 0.1, 0.03 },
    PALADIN = { 1.0, 0.4, 0.8, 0.5, 0.2, 0.03 },
    HUNTER  = { 0.2, 1.0, 0.6, 0.3, 0.2, 0.02 },
    ROGUE   = { 0.6, 1.0, 0.6, 0.0, 0.05, 0.02 },
    PRIEST  = { 0.0, 0.0, 0.5, 1.0, 0.8, 0.01 },
    MAGE    = { 0.0, 0.0, 0.5, 1.0, 0.5, 0.01 },
    WARLOCK = { 0.0, 0.0, 0.9, 0.8, 0.4, 0.01 },
    SHAMAN  = { 0.6, 0.5, 0.7, 0.8, 0.4, 0.02 },
    DRUID   = { 0.6, 0.6, 0.7, 0.8, 0.5, 0.02 },
}
ns.StatWeights = WEIGHTS -- (the stats card dims the attributes a class has no use for)
local WEIGHT_KEY = { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 3,
                     ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_SPIRIT_SHORT = 5, RESISTANCE0_NAME = 6 }
local function gearScore(link, cls)
    local st = itemStats(link)
    if not st then return nil end
    if not cls then
        local _, mine = UnitClass("player")
        cls = mine
    end
    local w = WEIGHTS[cls or ""] or WEIGHTS.WARRIOR
    local caster = w[4] >= 0.8
    local total = 0
    for k, v in pairs(st) do
        if type(v) == "number" and not issecretvalue(v) and type(k) == "string" then
            local i = WEIGHT_KEY[k]
            local m
            if i then m = w[i]
            elseif k == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then m = 0
            elseif k:find("^RESISTANCE") then m = 0.1                       -- a resistance
            elseif k:find("SPELL") or k:find("HEAL") or k:find("MANA") then m = caster and 0.8 or 0.1
            elseif k:find("ATTACK_POWER") then m = caster and w[1] < 0.5 and 0.05 or 0.5
            else m = 0.5 end                                               -- anything else: worth something
            total = total + v * m
        end
    end
    return total
end

-- The judging itself, for you (who = nil: what you wear now) or for one of
-- your other characters as last seen (who = { c = class, a = the heaviest
-- armour worn, g = { [slot] = link } }: Alts.lua keeps those). Returns
-- true / false, or nil while something it needs has not arrived from the
-- game; with a yes, also the slot it would go in and by how much it wins
-- (in whatever it was judged by: only good for ranking pieces for one
-- slot). Whether the character can use the thing at all is the caller's
-- to ask.
local function wornIn(who, slot)
    if who then
        local l = who.g and who.g[slot]
        return type(l) == "string" and l or nil
    end
    return GetInventoryItemLink("player", slot)
end
local function judge(link, who)
    local loc, classID, subID = equipLocOf(link)
    local slots = loc and SLOTS[loc]
    if not slots then return false end
    local new = gearLevel(link)
    if not new then return nil end -- its data hasn't arrived: ask again later
    local cls = who and who.c or nil
    local res, at, gain = false, nil, nil
    local best = who and who.a or ns.BestArmor()
    local wrongArmor = classID == 4 and type(subID) == "number" and subID >= 1 and subID <= 4
        and loc ~= "INVTYPE_CLOAK" and subID ~= best
    -- Tools that go in a weapon slot (a skinning knife, a mining pick, a
    -- fishing pole) are never an upgrade: they have a higher item level
    -- than starter weapons, but with one in hand your weapon abilities
    -- stop working.
    local isWeapon = classID == 2
    local tool = isWeapon and TOOL_WEAPON[subID]
    -- Weapons are judged by their damage per second, not their item level.
    local newDps = isWeapon and weaponDps(link) or nil
    local newScore = not isWeapon and gearScore(link, cls) or nil
    if not tool then
        local lowest, empty, same = nil, false, false
        local lowScore, scored = nil, newScore ~= nil -- (scored: every piece compared could be read)
        local beats = false
        local heavierWorn = false -- what is worn there is a heavier kind of armour than this
        local emptyAt, beatAt, lowAt, lvlAt, unread
        local main = wornIn(who, 16)
        local mainLoc = main and equipLocOf(main)
        for _, slot in ipairs(slots) do
            local worn = wornIn(who, slot)
            local count = true
            if slot == 17 then
                if loc == "INVTYPE_WEAPON" then
                    -- A one-hander is only compared with the off hand when
                    -- a weapon is held there (dual wielding).
                    local wl = worn and equipLocOf(worn)
                    count = wl == "INVTYPE_WEAPON" or wl == "INVTYPE_WEAPONOFFHAND"
                elseif not worn and OFFHAND[loc] and mainLoc == "INVTYPE_2HWEAPON" then
                    count = false -- the off hand is empty because of a two-hander
                end
            end
            if count then
                if not worn then empty = true; emptyAt = emptyAt or slot
                elseif worn == link then same = true
                else
                    local _, wClass, wSub = equipLocOf(worn)
                    if classID == 4 and wClass == 4 and type(wSub) == "number" and type(subID) == "number"
                        and wSub >= 1 and wSub <= 4 and wSub > subID then
                        heavierWorn = true
                    end
                    local wornDps = isWeapon and wClass == 2 and weaponDps(worn) or nil
                    if isWeapon and wClass == 2 and TOOL_WEAPON[wSub] then
                        beats = true -- any real weapon beats a tool
                        beatAt = beatAt or slot
                    elseif newDps and wornDps then
                        if newDps > wornDps + 0.05 then
                            beats = true
                            if not gain or newDps - wornDps > gain then beatAt, gain = slot, newDps - wornDps end
                        end
                    else
                        local l = gearLevel(worn)
                        if not l then unread = true end
                        if l and (not lowest or l < lowest) then lowest = l; lvlAt = slot end
                        local sc = scored and gearScore(worn, cls) or nil
                        if not sc then scored = false
                        elseif not lowScore or sc < lowScore then lowScore = sc; lowAt = slot end
                    end
                end
            end
        end
        -- Something is better than nothing: an empty slot makes it an
        -- upgrade even when it is a lighter kind of armour than your class
        -- wants (a warrior with a bare chest and a cloth robe in the bag).
        -- Armour lighter than your class's best is judged against what is
        -- actually worn: cloth can replace cloth (a shaman still in cloth,
        -- finding better cloth), but never the leather or mail already on.
        if same then res = false
        elseif empty then res, at, gain = true, emptyAt, newDps or newScore or new
        elseif wrongArmor and heavierWorn then res = false
        elseif beats then res, at = true, beatAt
        elseif who and unread then return nil -- (a piece of theirs this game session has not read yet)
        -- (Any gain counts, since 0.1.668. The margin was 0.05, and for
        -- a cloth class armour weighs 0.01 a point: a level 2 mage's
        -- robe with 8 armour over one with 3 scored exactly 0.05 more,
        -- and shoes with 5 over 2 scored 0.03, so neither was marked.)
        elseif scored and lowScore then res, at, gain = newScore > lowScore + 0.001, lowAt, newScore - lowScore
        elseif lowest and new > lowest then res, at, gain = true, lvlAt, new - lowest end -- (stats not to be had: by item level)
    end
    if not res then return false end
    return true, at, gain or 0
end
ns.JudgeUpgrade = judge

function ns.IsUpgrade(link)
    if type(link) ~= "string" or issecretvalue(link) or not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local known = upCache[link]
    if known ~= nil then return known end
    local res = judge(link)
    if res == nil then return false end -- (not kept: asked again later)
    if res and ns.ItemUnusable(link) then res = false end
    upCache[link] = res
    return res
end
do
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "SPELLS_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function()
        if next(upCache) == nil then return end
        wipe(upCache)
        local B = ns.modules and ns.modules.Bags
        if B and B.Refresh then C_Timer.After(0.1, function() pcall(B.Refresh, B) end) end
    end)
end

-- Can this character use the item? The game marks what stops you in red in
-- the item's tooltip (an armor type you can't wear, a level or class
-- requirement): returns that red line's text, or nil when nothing is red.
local scanTip
local function isRed(r, g, b) return type(r) == "number" and r > 0.9 and g < 0.2 and b < 0.2 end
-- (0.1.713) While the game is still fetching an item, its tooltip is one
-- red line, "Retrieving item information": that was taken for the reason
-- the item can't be used, and a quest reward said "(Can't use · Retrieving
-- item information)". It is no verdict: nil, and a second value true to say
-- "ask again in a moment".
local function fetching(text)
    if type(text) ~= "string" or issecretvalue(text) then return false end
    local w = _G.RETRIEVING_ITEM_INFO
    return text == (type(w) == "string" and w or "Retrieving item information")
end
function ns.ItemUnusable(link)
    if type(link) ~= "string" then return nil end
    local TI = _G.C_TooltipInfo
    if TI and TI.GetHyperlink then
        local ok, data = pcall(TI.GetHyperlink, link)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for _, ln in ipairs(data.lines) do
                local lc, rc = ln.leftColor, ln.rightColor
                if fetching(ln.leftText) then return nil, true end
                if lc and isRed(lc.r, lc.g, lc.b) and type(ln.leftText) == "string" and ln.leftText ~= "" then return ln.leftText end
                if rc and isRed(rc.r, rc.g, rc.b) and type(ln.rightText) == "string" and ln.rightText ~= "" then return ln.rightText end
            end
            return nil
        end
    end
    if not scanTip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "MeniscusItemScan", UIParent, "GameTooltipTemplate")
        if not ok then return nil end
        scanTip = tip
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    if not pcall(scanTip.SetHyperlink, scanTip, link) then return nil end
    for i = 2, scanTip:NumLines() do
        for s = 1, 2 do
            local fs = _G["MeniscusItemScanText" .. (s == 1 and "Left" or "Right") .. i]
            if fs then
                local r, g, b = fs:GetTextColor()
                local txt = fs:GetText()
                if type(txt) == "string" and not issecretvalue(txt) and fetching(txt) then return nil, true end
                if isRed(r, g, b) and type(txt) == "string" and not issecretvalue(txt) and txt ~= "" then return txt end
            end
        end
    end
    return nil
end

-- The heaviest armor this character can wear, as the item subclass number
-- (1 cloth, 2 leather, 3 mail, 4 plate). Read from the armor proficiencies
-- the character actually knows; if those can't be read, from the class
-- (with the usual step up at level 40).
local ARMOR_SPELL = { [4] = 750, [3] = 8737, [2] = 9077, [1] = 9078 }
local CLASS_ARMOR = { WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4, HUNTER = 3, SHAMAN = 3, EVOKER = 3,
                      ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2, MAGE = 1, PRIEST = 1, WARLOCK = 1 }
function ns.BestArmor()
    local known = _G.IsPlayerSpell or _G.IsSpellKnown
    if known then
        local any = false
        for sub = 4, 1, -1 do
            local ok, has = pcall(known, ARMOR_SPELL[sub])
            if ok and has == true then return sub end
            if ok and has ~= nil then any = true end
        end
        local _ = any
    end
    local _, class = UnitClass("player")
    local best = CLASS_ARMOR[class] or 1
    local lvl = UnitLevel("player")
    if type(lvl) == "number" and not issecretvalue(lvl) and lvl < 40 and best >= 3 then best = best - 1 end
    return best
end

function ns.AddCompare(tip, link)
    if type(link) ~= "string" or not (C_Item and C_Item.GetItemInfoInstant) then return end
    local ok, _, _, _, loc, _, classID, subID = pcall(C_Item.GetItemInfoInstant, link)
    local slots = ok and SLOTS[loc]
    if not slots then return end
    if classID == 2 and TOOL_WEAPON[subID] then
        tip:AddLine(" ")
        tip:AddLine("A tool, not a fighting weapon: your weapon abilities don't work while it is in your hand.", 0.95, 0.76, 0.32, true)
    end
    local new = tidy(itemStats(link))
    if not new then return end
    local shownAny = false
    for _, slot in ipairs(slots) do
        local worn = GetInventoryItemLink("player", slot)
        if worn and worn ~= link then
            local old = tidy(itemStats(worn))
            if old then
                local gains, losses = {}, {}
                for k, v in pairs(new) do
                    local d = v - (old[k] or 0)
                    if d > 0.05 then gains[#gains + 1] = { k, d } elseif d < -0.05 then losses[#losses + 1] = { k, d } end
                end
                for k, v in pairs(old) do
                    if new[k] == nil and v > 0.05 then losses[#losses + 1] = { k, -v } end
                end
                local name = worn:match("%[(.-)%]") or "equipped"
                tip:AddLine(" ")
                tip:AddLine("Instead of " .. name .. ":", 0.6, 0.6, 0.65, true)
                local function fmt(d)
                    local a = math.abs(d)
                    return (d > 0 and "+" or "-") .. ((a % 1 > 0.05) and string.format("%.1f", a) or string.format("%d", a + 0.5))
                end
                -- (In a tooltip there is room for the word too: emblem, number, name.)
                local function row(e) return (ns.StatMark(e[1], 16) or "") .. " " .. fmt(e[2]) .. " " .. statLabel(e[1]) end
                for _, e in ipairs(gains) do tip:AddLine(row(e), 0.45, 0.85, 0.50) end
                for _, e in ipairs(losses) do tip:AddLine(row(e), 0.90, 0.45, 0.45) end
                if #gains == 0 and #losses == 0 then tip:AddLine("Same stats", 0.85, 0.85, 0.88) end
                shownAny = true
            end
        end
    end
    if not shownAny then
        tip:AddLine(" ")
        tip:AddLine("Nothing equipped in that slot", 0.6, 0.6, 0.65)
    end
    tip:Show() -- resize for the added lines
end

-- What a reward card says about an item, for any window that lists rewards
-- (the quest log's cards; the quest giver's in Dialogs.lua say the same):
--   what   "Wrist  ·  Mail" (the armor type green when it is the heaviest
--          you can wear, blue when lighter), a weapon's type, or the item's
--          kind; with "(Can't equip)" in red when you can't use it
--   cant   true when you can't use it
--   rows   how it differs from what you wear, as one string ("" if nothing)
--   price  what a vendor pays for the stack, or nil if not known yet
-- Returns nil while the item's data hasn't arrived.
local CARD_SINGULAR = { Staves = "Staff", Thrown = "Thrown", Miscellaneous = "Miscellaneous" }
function ns.RewardInfo(link, count, usable)
    if type(link) ~= "string" or issecretvalue(link) or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, _, typ, sub, loc, _, classID, subID = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return nil end
    local weapon = classID == 2 or (classID == 4 and subID == 6)
    local weight = (classID == 4 and type(subID) == "number" and subID >= 1 and subID <= 4
        and loc ~= "INVTYPE_CLOAK") and subID or nil
    local sn = type(loc) == "string" and loc ~= "" and _G[loc]
    local slotName = (type(sn) == "string" and sn ~= "") and sn or nil
    local why = ns.ItemUnusable(link)
    local cant = type(why) == "string" or usable == false
    local best = ns.BestArmor()
    local RED = "|cffe57373"
    local tint
    if cant then
        if why == sub or (weight and best and weight > best) then tint = RED end
    elseif weight and best then
        if weight == best then tint = "|cff73d980" elseif weight < best then tint = "|cff73b3f2" end
    end
    local what
    if weapon and type(sub) == "string" and sub ~= "" then
        what = CARD_SINGULAR[sub] or (sub:gsub("s$", ""))
    elseif slotName then
        what = slotName
        if type(sub) == "string" and sub ~= "" and sub ~= slotName then
            what = what .. "  \194\183  " .. (tint and (tint .. sub .. "|r") or sub)
        end
    else
        what = type(typ) == "string" and typ or ""
    end
    if cant then
        local note = slotName and "Can't equip" or "Can't use"
        if type(why) == "string" and why ~= "" and why ~= sub and why ~= slotName then note = note .. "  \194\183  " .. why end
        what = what .. (what ~= "" and "  " or "") .. RED .. "(" .. note .. ")|r"
    end
    -- A tool in a weapon slot: say so, where the comparison would be.
    if classID == 2 and TOOL_WEAPON[subID] and not cant then
        what = what .. (what ~= "" and "  " or "") .. "|cfff2c252(Tool: weapon abilities don't work with it)|r"
    end
    local rows = (not cant) and ns.CompareRows(link, 6) or nil
    local price
    if C_Item.GetItemInfo then
        local okp, p = pcall(function() return (select(11, C_Item.GetItemInfo(link))) end)
        if okp and type(p) == "number" and not issecretvalue(p) then
            price = p * ((type(count) == "number" and not issecretvalue(count) and count > 1) and count or 1)
        end
    end
    return { what = what, cant = cant, rows = type(rows) == "table" and table.concat(rows, "     ") or "", price = price }
end

-- Hide a non-secure Blizzard region/frame and keep it hidden.
-- The colour of a creature's level against yours (0.1.606). The target
-- frame asked the game's GetCreatureDifficultyColor(level), which on this
-- client called a level 14 grey to a level 20 while the game's own
-- nameplate had it green (and it does still give experience). So: the
-- game's judgement of the creature itself where it offers one (what its
-- own frames use), else the old game's rule worked out here: red from 5
-- levels over you, orange from 3, yellow to 2 under, green down to the
-- level that stops giving experience, grey below that.
-- ns.CreatureLevelColor(unit, level): r, g, b, or nil when it can't say.
local function greyLevel(pl)
    if pl <= 5 then return 0 end
    if pl <= 39 then return pl - math.floor(pl / 10) - 5 end
    if pl <= 59 then return pl - math.floor(pl / 5) - 1 end
    return pl - 9
end
function ns.CreatureLevelColor(unit, lvl)
    local P = C_PlayerInfo
    if unit and P and P.GetContentDifficultyCreatureForPlayer and GetDifficultyColor then
        local ok, d = pcall(P.GetContentDifficultyCreatureForPlayer, unit)
        if ok and d ~= nil and not issecretvalue(d) then
            local ok2, c = pcall(GetDifficultyColor, d)
            if ok2 and type(c) == "table" and c.r then
                if MinimalUIDB then MinimalUIDB.lvldiag = "the game's own judgement of the creature" end
                return c.r, c.g, c.b
            end
        end
    end
    local pl = UnitLevel("player")
    if type(lvl) ~= "number" or issecretvalue(lvl) or type(pl) ~= "number" or issecretvalue(pl) or lvl <= 0 then return nil end
    if MinimalUIDB then MinimalUIDB.lvldiag = "the old rule, worked out" end
    local diff = lvl - pl
    if diff >= 5 then return 1.00, 0.10, 0.10 end
    if diff >= 3 then return 1.00, 0.50, 0.25 end
    if diff >= -2 then return 1.00, 0.82, 0.00 end
    if lvl > greyLevel(pl) then return 0.25, 0.75, 0.25 end
    return 0.50, 0.50, 0.50
end

-- Money, the one way (0.1.596): each amount followed by a small disc in
-- its coin's colour, "2(gold) 42(silver) 36(copper)", parts that are zero
-- left out. Every window had its own copy of this; the console's Bags
-- pill, the loot pills and the bestiary wrote letters (2g 42s 36c).
-- ns.Money(copper, sep): nil for what is not a plain number.
local DISC = "|TInterface/AddOns/Meniscus/Media/circle.tga:9:9:2:0:32:32:0:32:0:32:%s|t"
ns.CoinMark = { g = DISC:format("230:194:90"), s = DISC:format("184:188:198"), c = DISC:format("201:138:82") }
function ns.Money(copper, sep)
    if type(copper) ~= "number" or issecretvalue(copper) then return nil end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. ns.CoinMark.g end
    if s > 0 then parts[#parts + 1] = s .. ns.CoinMark.s end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. ns.CoinMark.c end
    return table.concat(parts, sep or " ")
end

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
