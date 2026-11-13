local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Minimap: rounded-square map with a hairline rounded border, Blizzard's
-- ring/compass/zoom buttons and calendar button removed, mouse-wheel zoom,
-- zone name in the theme font. The addon compartment, tracking, clock and
-- mail/queue indicators are left alone.

-- dome = true: a round map sitting on the main action bar (see MM:ApplyDome).
-- domeMode: how the dome's map gets its size. "scale" keeps the map at the
-- size the game made it and scales the frame (so its dots and the areas
-- that answer the mouse stay in step); "size" resizes it (dots keep their
-- full size, but their hover areas drifted toward the middle of the map).
local MM = ns:NewModule("Minimap", { enabled = true, dome = true, domeD = 130, domeMode = "size", domeGap = 2 })
local MEDIA = "Interface/AddOns/Meniscus/Media/"

-- Blizzard art to remove. Names differ between client generations, so each
-- is optional.
local function clutter()
    local C = MinimapCluster
    return {
        _G.MinimapBorder, _G.MinimapBorderTop, _G.MinimapCompassTexture, _G.MinimapNorthTag,
        _G.MinimapBackdrop, _G.MinimapZoomIn, _G.MinimapZoomOut, _G.MiniMapWorldMapButton,
        _G.MinimapToggleButton, _G.GameTimeFrame,
        Minimap.ZoomIn, Minimap.ZoomOut, Minimap.ZoomHitArea,
        C and C.BorderTop,
    }
end

function MM:OnInit(db)
    self.db = db
    if not Minimap then return end
    -- The size the game gave the map, before anything here touches it.
    self.native = Minimap:GetWidth()
    if MinimalUIDB then MinimalUIDB.domeNative = self.native end

    -- Square shape (rounded corners via the mask). Addons that place minimap
    -- buttons ask GetMinimapShape().
    Minimap:SetMaskTexture(MEDIA .. "rounded.tga")
    _G.GetMinimapShape = function() return "SQUARE" end

    -- Border: drawn on a frame behind the map, sharing the map's parent so it
    -- can sit one level below it.
    local border = CreateFrame("Frame", nil, Minimap:GetParent())
    border:SetFrameStrata(Minimap:GetFrameStrata())
    border:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
    border:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 2, -2)
    ns.RoundedRect(border, 0, 0, 16, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(border, 1, 1, 15, 0.05, 0.05, 0.06, 1)
    self.border = border

    for _, obj in pairs(clutter()) do
        if obj then pcall(ns.Kill, obj) end
    end

    -- Mouse-wheel zoom.
    Minimap:EnableMouseWheel(true)
    Minimap:HookScript("OnMouseWheel", function(self, delta)
        local z = self:GetZoom()
        if delta > 0 and z < self:GetZoomLevels() - 1 then
            self:SetZoom(z + 1)
        elseif delta < 0 and z > 0 then
            self:SetZoom(z - 1)
        end
    end)

    -- Zone text: restyle Blizzard's (it keeps its click/tooltip behavior).
    local zoneText = _G.MinimapZoneText or (MinimapCluster and MinimapCluster.ZoneTextButton
        and MinimapCluster.ZoneTextButton.Text)
    if zoneText and zoneText.SetFont then
        local _, size = zoneText:GetFont()
        ns:SetFont(zoneText, size or 12, "")
        zoneText:SetShadowOffset(1, -1)
        zoneText:SetShadowColor(0, 0, 0, 0.8)
    end

    -- After the other modules (the bar's position decides the default spot).
    if db.dome then
        C_Timer.After(0, function() MM:ApplyDome(); MM:ArrangeAround() end)
        C_Timer.After(3, function() MM:ProbeDome() end)
    end
end

-- ── Dome ──────────────────────────────────────────────────────────────────
-- The map as a third orb in the middle of the main action bar, which splits
-- into two blocks around it (Bars.lua): same construction as an orb
-- (hairline ring, dark track, glass glare), standing on the bars' baseline. The map is not
-- reparented (its cluster is Edit Mode's); it is re-anchored to a holder of
-- ours, and put back there if Blizzard's layout moves it. The zone name
-- rides on top of the dome. Tracking, mail, clock and the addon menu stay
-- where the cluster has them for now.
-- /men dome toggles it, /men dome move shows a drag handle, /men dome reset
-- puts it back on the bar. Turning it off takes a reload.
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local function circleMask(frame, size)
    local k = frame:CreateMaskTexture()
    k:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    k:SetPoint("CENTER")
    k:SetSize(size, size)
    return k
end

local function domeDefault()
    local B = ns.modules.Bars
    local main = B and B.db and B.db.main
    return { x = main and main.x or 0, y = main and main.y or 30 }
end

function MM:PlaceDome()
    local h = self.domeHolder
    if not h then return end
    local pos = self.db.domePos or domeDefault()
    h:ClearAllPoints()
    h:SetPoint("BOTTOM", UIParent, "BOTTOM", pos.x, pos.y)
end

-- The main bar (and what sits on it) makes room for the dome, or closes up.
function MM:ArrangeAround()
    local B = ns.modules.Bars
    if B and B.Arrange and B.db then B:Arrange() end
    local QB = ns.modules.QuickBuff
    if QB and QB.Place then pcall(QB.Place) end
    local OR = ns.modules.Orbs
    if OR and OR.PlacePet and OR.db and OR.health then pcall(OR.PlacePet, OR) end
    -- The player-style pass places the pet frame and the buff frames, both
    -- of which depend on where the bars just went.
    local UF = ns.modules.UnitFrames
    if UF and UF.ApplyPlayerStyle and UF.db and UF.player then UF:ApplyPlayerStyle() end
    local AU = ns.modules.Auras
    if AU and AU.SeatBlizzard and AU.db then AU:SeatBlizzard() end
    local CB = ns.modules.CastBars
    if CB and CB.player and CB.player.place and not InCombatLockdown() then CB.player.place() end
end

function MM:ApplyDome()
    if not Minimap or self.domeHolder then return end
    local D = self.db.domeD or 130
    local RING, INSET = 1.5, 4
    local outer = D + (RING + INSET) * 2

    local h = CreateFrame("Frame", "MinimalUI_MinimapDome", UIParent)
    h:SetSize(outer, outer)
    -- The ring and track sit in the lowest strata; the map keeps whatever
    -- strata and level Blizzard gave it (changing those was one suspect for
    -- the map drawing black, and with the bar split nothing has to cover it).
    h:SetFrameStrata("BACKGROUND")
    h:SetFrameLevel(3) -- above the console plate (Bars.lua), which is at 0
    h:SetClampedToScreen(true)
    self.domeHolder = h
    self:PlaceDome()

    local ring = h:CreateTexture(nil, "BACKGROUND", nil, 0)
    ring:SetAllPoints()
    ring:SetColorTexture(unpack(T.border))
    ring:AddMaskTexture(circleMask(h, outer))
    local track = h:CreateTexture(nil, "BACKGROUND", nil, 1)
    track:SetPoint("CENTER")
    track:SetSize(outer - RING * 2, outer - RING * 2)
    track:SetColorTexture(0.05, 0.05, 0.06, 0.96)
    track:AddMaskTexture(circleMask(h, outer - RING * 2))

    if self.border then self.border:Hide() end
    -- Our own disc. On this client the map drew nothing with either of the
    -- game's round masks (the portrait circle, Textures/MinimapMask); only a
    -- mask file of ours (white, shape in the alpha) works.
    Minimap:SetMaskTexture(MEDIA .. "circle.tga")
    _G.GetMinimapShape = function() return "ROUND" end

    -- A parent that clips its children would hide a map moved outside it
    -- (the map's own buttons, which belong to other parents, would still
    -- show: exactly what a black dome with its badges around it looks like).
    local unclipped = 0
    local par = Minimap:GetParent()
    while par and par ~= UIParent do
        if par.DoesClipChildren and par:DoesClipChildren() then
            pcall(par.SetClipsChildren, par, false)
            unclipped = unclipped + 1
        end
        par = par:GetParent()
    end
    self.domeUnclipped = unclipped
    local placing = false
    local native = self.native
    -- (Scaling the map instead of resizing it was tried: everything on it
    -- shrank and the tooltips were no better. Kept only as /men dome try.)
    if self.db.domeMode ~= "size" then self.db.domeMode = "size" end
    local byScale = false
    local want = D -- the frame's own size
    local function seat()
        if placing then return end
        placing = true
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", h, "CENTER")
        Minimap:SetSize(want, want)
        Minimap:SetScale(byScale and (D / native) or 1)
        placing = false
    end
    seat()
    -- For trying the ways of fitting the map without a reload.
    function MM:TryDome(mode)
        if mode == "scale" and type(native) == "number" and native > 20 then byScale, want = true, native
        elseif mode == "native" and type(native) == "number" and native > 20 then byScale, want = false, native
        else byScale, want = false, D end
        seat()
    end
    -- Blizzard's cluster layout re-anchors (and re-sizes) the map now and
    -- then. Each time it is put back, its hover areas need settling again
    -- (see settle, below): without that the gold dots' tooltips sat beside
    -- the dots until the next loading screen.
    local settleSoon
    hooksecurefunc(Minimap, "SetPoint", function(_, _, rel)
        if not placing and rel ~= h then seat(); if settleSoon then settleSoon() end end
    end)
    hooksecurefunc(Minimap, "SetSize", function(_, w)
        if placing then return end
        -- (Only when the game really changed the size.)
        if type(w) == "number" and math.abs(w - want) > 0.5 then
            seat()
            if settleSoon then settleSoon() end
        end
    end)
    -- The map only takes on its new size, for drawing its markers AND for
    -- working out which marker the mouse is over, after a zoom change that
    -- it actually gets to process. Flipping the zoom there and back inside
    -- one frame (as this did at first) redrew the map but left the hover
    -- areas at the old size, so tooltips appeared beside the marker they
    -- belonged to. So: one step now, the step back a moment later, and the
    -- same again whenever the world is (re)entered.
    -- The step back has to come well after the step out. With 0.3 s
    -- between them the map was drawn at the old zoom again but the hover
    -- areas stayed at the stepped-out zoom: the dots' tooltips then sat
    -- closer to the middle than the dots, worse toward the rim. The client
    -- seems to take only one zoom change at a time for the hover areas, so
    -- the second one waits (db.domeGap seconds; /men dome fix <seconds>
    -- runs one by hand).
    local settling = false
    local function settle(gap)
        if settling then return end
        local ok, z = pcall(Minimap.GetZoom, Minimap)
        if not ok or type(z) ~= "number" then return end
        local other = z > 0 and z - 1 or z + 1
        settling = true
        pcall(Minimap.SetZoom, Minimap, other)
        C_Timer.After(gap or MM.db.domeGap or 2, function()
            settling = false
            -- (Unless you zoomed yourself in the meantime.)
            local ok2, now = pcall(Minimap.GetZoom, Minimap)
            if ok2 and now == other then pcall(Minimap.SetZoom, Minimap, z) end
        end)
    end
    MM.SettleDome = function(_, gap) settle(gap) end
    -- One settle for any burst of changes, a moment after the last one.
    local settleAt, settleQueued = 0, false
    settleSoon = function()
        settleAt = GetTime() + 0.8
        if settleQueued then return end
        settleQueued = true
        local function run()
            if GetTime() < settleAt - 0.05 then C_Timer.After(settleAt - GetTime(), run) return end
            settleQueued = false
            settle()
        end
        C_Timer.After(0.8, run)
    end
    C_Timer.After(0.5, settle)
    local sev = CreateFrame("Frame")
    -- (Not on every sub-zone change: each settle shows as a zoom step.)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        pcall(sev.RegisterEvent, sev, e)
    end
    sev:SetScript("OnEvent", function() settleSoon() end)

    -- Glass glare, as on the orbs. Drawn on the map's own frame, as one of
    -- its textures. It used to be a frame of its own laid over the map, one
    -- strata up: where that frame covered the map, the dots' tooltips no
    -- longer lined up with the dots (outside it they did), even though the
    -- frame took no mouse input.
    local gloss = Minimap:CreateTexture(nil, "OVERLAY", nil, 7)
    gloss:SetPoint("CENTER", Minimap, "CENTER")
    gloss:SetSize(D, D)
    gloss:SetTexture(MEDIA .. "orb_glare.tga")
    gloss:SetAlpha(0.55)
    local glossMask = Minimap:CreateMaskTexture()
    glossMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    glossMask:SetPoint("CENTER", Minimap, "CENTER")
    glossMask:SetSize(D, D)
    gloss:AddMaskTexture(glossMask)
    self.domeGloss = gloss

    -- With the map moved out, Blizzard's cluster is an empty shell left
    -- where Edit Mode puts it, and it still takes the mouse: on a fresh
    -- layout it measured 1279x1158 and swallowed right-click turning over
    -- most of the screen. The shell and its map container stop taking the
    -- mouse; their buttons (tracking, addon menu, clock) keep theirs.
    local function letThrough()
        if InCombatLockdown() then return end
        local C = MinimapCluster
        if C then
            pcall(C.EnableMouse, C, false)
            if C.MinimapContainer then pcall(C.MinimapContainer.EnableMouse, C.MinimapContainer, false) end
        end
    end
    letThrough()
    local lev = CreateFrame("Frame")
    lev:RegisterEvent("PLAYER_ENTERING_WORLD")
    lev:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    lev:RegisterEvent("PLAYER_REGEN_ENABLED")
    lev:SetScript("OnEvent", function() C_Timer.After(0, letThrough) end)

    self:BuildZonePill(h)
end

-- The zone name in a pill on the dome's bottom edge, built like the value
-- chips on the orbs. Hover: zone, subzone, server time and your coordinates.
-- Click: world map. Blizzard's own header (gold bar, zone button, clock)
-- and the coordinates line under the map are faded out; the tracking button
-- and the addon menu button move to the pill's ends.
local CHIP_W, CHIP_H = 150, 14 -- a little wider than the dome; the orbs' pill height
-- Ring color: the orbs' chips take their liquid's color at 80%; the map's
-- takes a muted gold the same way.
local GOLD = { 0.80, 0.62, 0.24 }
local GOLD_HOVER = { 1.00, 0.80, 0.36 }
local function fadeOut(obj)
    if not obj then return end
    pcall(function()
        obj:SetAlpha(0)
        if obj.EnableMouse then obj:EnableMouse(false) end
    end)
end

function MM:BuildZonePill(h)
    local chip = CreateFrame("Button", nil, h)
    chip:SetSize(CHIP_W, CHIP_H)
    chip:SetPoint("CENTER", h, "BOTTOM", 0, 3.5)
    chip:SetFrameStrata("MEDIUM") -- see the glass: the cluster gets raised
    chip:SetFrameLevel(2)
    -- Drawn with rounded rectangles, not the pill textures: those only come
    -- in fixed 8:1 / 16:1 shapes, and this pill is wider than 8:1 at the
    -- orbs' pill height.
    local paintRing = ns.RoundedRect(chip, -8, 0, CHIP_H / 2, GOLD[1], GOLD[2], GOLD[3], 1)
    ns.RoundedRect(chip, -7, 1, CHIP_H / 2 - 1, 0.06, 0.06, 0.07, 0.97)
    local ring = { SetVertexColor = function(_, r, g, b, a) paintRing(r, g, b, a or 1) end }
    local text = ns:CreateText(chip, 11)
    -- The left end of the pill is the tracking button (below).
    text:SetPoint("LEFT", 21, 0); text:SetPoint("RIGHT", -21, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.8)
    self.zonePill = chip

    local function refresh()
        local z = GetMinimapZoneText and GetMinimapZoneText() or ""
        text:SetText(type(z) == "string" and z or "")
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        ev:RegisterEvent(e)
    end
    ev:SetScript("OnEvent", refresh)
    refresh()

    local function tip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local zone, sub = GetRealZoneText and GetRealZoneText() or "", GetMinimapZoneText and GetMinimapZoneText() or ""
        GameTooltip:SetText(zone ~= "" and zone or sub, 1, 1, 1)
        if sub ~= "" and sub ~= zone then GameTooltip:AddLine(sub, 0.8, 0.8, 0.85) end
        local hh, mm = GetGameTime()
        if type(hh) == "number" then GameTooltip:AddDoubleLine("Server time", string.format("%02d:%02d", hh, mm), 0.6, 0.6, 0.65, 1, 1, 1) end
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local ok, pos = pcall(function() return mapID and C_Map.GetPlayerMapPosition(mapID, "player") end)
        if ok and pos and pos.GetXY then
            local x, y = pos:GetXY()
            if type(x) == "number" and not (issecretvalue and issecretvalue(x)) then
                GameTooltip:AddDoubleLine("Coordinates", string.format("%.1f, %.1f", x * 100, y * 100), 0.6, 0.6, 0.65, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end
    -- Coordinates change as you walk: refresh the tooltip while hovering.
    local acc = 0
    chip:SetScript("OnEnter", function(self) acc = 0; tip(self); ring:SetVertexColor(GOLD_HOVER[1], GOLD_HOVER[2], GOLD_HOVER[3], 1) end)
    chip:SetScript("OnLeave", function() GameTooltip:Hide(); ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
    chip:SetScript("OnUpdate", function(self, dt)
        if not self:IsMouseOver() then return end
        acc = acc + dt
        if acc >= 0.5 then acc = 0; if GameTooltip:IsOwned(self) then tip(self) end end
    end)
    chip:SetScript("OnClick", function() if not InCombatLockdown() and ToggleWorldMap then ToggleWorldMap() end end)

    -- Blizzard's header pieces.
    local C = MinimapCluster
    if not C then return end
    fadeOut(C.ZoneTextButton)
    fadeOut(_G.TimeManagerClockButton)
    fadeOut(C.BorderTop)
    -- Blizzard's "you have mail" envelope stays behind in the corner when
    -- the map moves (our own mail mark is on the character panel).
    local ind = C.IndicatorFrame
    if ind then
        fadeOut(ind)
        fadeOut(ind.MailFrame)
        fadeOut(ind.CraftingOrderFrame)
    end
    fadeOut(_G.MiniMapMailFrame)
    for _, r in ipairs({ C:GetRegions() }) do pcall(r.SetAlpha, r, 0) end
    local cont = C.MinimapContainer
    fadeOut(cont and cont.PlayerCoords)
    -- The day / night dial (an unnamed ~42 px frame in the map's container)
    -- stays behind in the corner when the map moves: faded out too. The
    -- time is in the pill's tooltip.
    if cont then
        for _, c in ipairs({ cont:GetChildren() }) do
            local w = c.GetWidth and c:GetWidth() or 0
            if c ~= Minimap and c ~= cont.PlayerCoords and w >= 36 and w <= 48 then fadeOut(c) end
        end
    end
    fadeOut(_G.GameTimeFrame)
    -- Tracking: set into the pill's left end. A magnifier of ours is drawn
    -- there (a ring and a handle, in the pill's own colors) with a hairline
    -- divider; Blizzard's button sits invisibly on top of it and still opens
    -- its own tracking menu.
    local glyph = CreateFrame("Frame", nil, chip)
    glyph:SetSize(14, 14)
    glyph:SetPoint("LEFT", chip, "LEFT", 4, 0)
    glyph:SetFrameLevel(chip:GetFrameLevel() + 1)
    local lens = glyph:CreateTexture(nil, "ARTWORK", nil, 0)
    lens:SetSize(8, 8)
    lens:SetPoint("CENTER", -1, 1)
    lens:SetColorTexture(1, 1, 1, 1)
    local lensMask = circleMask(glyph, 8)
    lensMask:ClearAllPoints(); lensMask:SetPoint("CENTER", lens, "CENTER")
    lens:AddMaskTexture(lensMask)
    local hole = glyph:CreateTexture(nil, "ARTWORK", nil, 1)
    hole:SetSize(5, 5)
    hole:SetPoint("CENTER", lens, "CENTER")
    hole:SetColorTexture(0.06, 0.06, 0.07, 1)
    local holeMask = circleMask(glyph, 5)
    holeMask:ClearAllPoints(); holeMask:SetPoint("CENTER", lens, "CENTER")
    hole:AddMaskTexture(holeMask)
    local handle = glyph:CreateLine(nil, "ARTWORK", nil, 0)
    handle:SetThickness(1.6)
    handle:SetColorTexture(1, 1, 1, 1)
    handle:SetStartPoint("CENTER", glyph, 1.6, -1.6)
    handle:SetEndPoint("CENTER", glyph, 4.6, -4.6)
    local div = chip:CreateTexture(nil, "ARTWORK")
    div:SetSize(1, 8)
    div:SetPoint("LEFT", chip, "LEFT", 19, 0)
    div:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    local function tint(c)
        lens:SetVertexColor(c[1], c[2], c[3], 1)
        handle:SetVertexColor(c[1], c[2], c[3], 1)
    end
    tint(T.textDim)

    pcall(function()
        local t = C.Tracking
        if t then
            local btn = t.Button
            t:ClearAllPoints()
            t:SetPoint("CENTER", glyph, "CENTER")
            -- Its art goes; the frames stay (and stay clickable).
            for _, r in ipairs({ t:GetRegions() }) do pcall(r.SetAlpha, r, 0) end
            if btn then
                for _, r in ipairs({ btn:GetRegions() }) do pcall(r.SetAlpha, r, 0) end
                for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                    local tex = btn[get] and btn[get](btn)
                    if tex then pcall(tex.SetAlpha, tex, 0) end
                end
                -- Above the pill and the map, and kept there: the cluster
                -- re-levels its children when it is raised, which left the
                -- button under the pill with only its edges reachable.
                btn:SetFrameStrata("MEDIUM")
                btn:SetFrameLevel(chip:GetFrameLevel() + 3)
                if btn.SetFixedFrameStrata then pcall(btn.SetFixedFrameStrata, btn, true) end
                if btn.SetFixedFrameLevel then pcall(btn.SetFixedFrameLevel, btn, true) end
                -- And the pill itself lets the mouse through at that end, so
                -- the button is reachable whatever the order ends up being.
                chip:SetHitRectInsets(21, 21, 0, 0)
                -- The whole left section of the pill is the button.
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", chip, "TOPLEFT", -2, 3)
                btn:SetPoint("BOTTOMRIGHT", chip, "BOTTOMLEFT", 20, -3)
                btn:HookScript("OnEnter", function() tint(GOLD_HOVER) end)
                btn:HookScript("OnLeave", function() tint(T.textDim) end)
            end
        end
    end)

    -- The addon menu button (its count) takes the pill's right end the same
    -- way: Blizzard's button, art faded, its number restyled, behind a
    -- divider.
    local div2 = chip:CreateTexture(nil, "ARTWORK")
    div2:SetSize(1, 8)
    div2:SetPoint("RIGHT", chip, "RIGHT", -19, 0)
    div2:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    pcall(function()
        local a = _G.AddonCompartmentFrame
        if not a then div2:Hide() return end
        for _, r in ipairs({ a:GetRegions() }) do
            if r:IsObjectType("Texture") then pcall(r.SetAlpha, r, 0) end
        end
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
            local tex = a[get] and a[get](a)
            if tex then pcall(tex.SetAlpha, tex, 0) end
        end
        -- The count is drawn by us, on the pill: restyling Blizzard's own
        -- label in place left it invisible. Theirs is faded out and read
        -- for its number.
        local theirs = a.Text or (a.GetFontString and a:GetFontString())
        if theirs then pcall(theirs.SetAlpha, theirs, 0) end
        local count = ns:CreateText(chip, 10, T.textDim)
        count:SetPoint("CENTER", chip, "RIGHT", -10, 0)
        count:SetShadowOffset(1, -1)
        count:SetShadowColor(0, 0, 0, 0.8)
        local function refreshCount()
            local t = theirs and theirs.GetText and theirs:GetText()
            if type(t) ~= "string" or t == "" then
                local list = a.registeredAddons
                t = type(list) == "table" and tostring(#list) or ""
            end
            count:SetText(t)
        end
        if theirs then hooksecurefunc(theirs, "SetText", function() C_Timer.After(0, refreshCount) end) end
        for _, method in ipairs({ "UpdateDisplay", "RegisterAddon" }) do
            if type(a[method]) == "function" then pcall(hooksecurefunc, a, method, function() C_Timer.After(0, refreshCount) end) end
        end
        refreshCount()
        C_Timer.After(2, refreshCount)
        a:HookScript("OnEnter", function() count:SetTextColor(GOLD_HOVER[1], GOLD_HOVER[2], GOLD_HOVER[3]) end)
        a:HookScript("OnLeave", function() count:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3]) end)
        a:SetFrameStrata("MEDIUM")
        a:SetFrameLevel(chip:GetFrameLevel() + 3)
        if a.SetFixedFrameStrata then pcall(a.SetFixedFrameStrata, a, true) end
        if a.SetFixedFrameLevel then pcall(a.SetFixedFrameLevel, a, true) end
        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", chip, "TOPRIGHT", -20, 3)
        a:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", 2, -3)
    end)
end

-- What the map looks like to the client right now (MinimalUIDB.domeprobe;
-- read from the saved variables when the map doesn't draw).
function MM:ProbeDome()
    if not MinimalUIDB then return end
    local out = {}
    local function f2(v) return type(v) == "number" and string.format("%.2f", v) or tostring(v) end
    local function describe(tag, fr)
        local ok, line = pcall(function()
            local p, rel, rp, x, y = fr:GetPoint(1)
            return tag .. " shown=" .. tostring(fr:IsShown()) .. " visible=" .. tostring(fr:IsVisible())
                .. " alpha=" .. f2(fr:GetAlpha()) .. " effAlpha=" .. f2(fr:GetEffectiveAlpha())
                .. " scale=" .. f2(fr:GetScale()) .. " effScale=" .. f2(fr:GetEffectiveScale())
                .. " size=" .. f2(fr:GetWidth()) .. "x" .. f2(fr:GetHeight())
                .. " strata=" .. tostring(fr:GetFrameStrata()) .. " level=" .. tostring(fr:GetFrameLevel())
                .. " point=" .. tostring(p) .. ">" .. tostring(rel and (rel.GetName and rel:GetName() or "?")) .. " "
                .. tostring(rp) .. " " .. f2(x) .. "," .. f2(y)
                .. " left=" .. f2(fr:GetLeft()) .. " bottom=" .. f2(fr:GetBottom())
        end)
        out[#out + 1] = ok and line or (tag .. " error: " .. tostring(line))
    end
    describe("Minimap", Minimap)
    local p, depth = Minimap:GetParent(), 1
    while p and depth <= 4 do
        describe("parent" .. depth .. " " .. tostring(p.GetName and p:GetName() or "?"), p)
        p, depth = p:GetParent(), depth + 1
    end
    if self.domeHolder then describe("holder", self.domeHolder) end
    out[#out + 1] = "clipping parents switched off: " .. tostring(self.domeUnclipped)
    local function tree(fr, key, depth)
        if depth > 3 or (fr.IsForbidden and fr:IsForbidden()) then return end
        local ok, line = pcall(function()
            local p, rel, rp, x, y = fr:GetPoint(1)
            local txt = ""
            if fr.GetText then local t = fr:GetText(); if type(t) == "string" then txt = " text=" .. t end end
            return string.rep("  ", depth) .. key .. " [" .. fr:GetObjectType() .. "] " .. tostring(fr.GetName and fr:GetName() or "?")
                .. (fr:IsShown() and "" or " hidden") .. " " .. f2(fr:GetWidth()) .. "x" .. f2(fr:GetHeight())
                .. " @" .. tostring(p) .. ">" .. tostring(rel and (rel.GetName and rel:GetName() or "?")) .. " "
                .. tostring(rp) .. " " .. f2(x) .. "," .. f2(y)
                .. (fr.DoesClipChildren and fr:DoesClipChildren() and " CLIPS" or "") .. txt
        end)
        out[#out + 1] = ok and line or (string.rep("  ", depth) .. key .. " error: " .. tostring(line))
        if not fr.GetChildren then return end
        local names = {}
        for k, v in pairs(fr) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
        for _, r in ipairs({ fr:GetRegions() }) do
            if r:IsObjectType("FontString") then
                local t = r:GetText()
                out[#out + 1] = string.rep("  ", depth + 1) .. "- " .. tostring(names[r] or r:GetName() or "?")
                    .. " [FontString]" .. (r:IsShown() and "" or " hidden") .. " text=" .. tostring(type(t) == "string" and t or "?")
            end
        end
        for _, c in ipairs({ fr:GetChildren() }) do
            if c ~= Minimap then tree(c, names[c] or "#", depth + 1) end
        end
    end
    if MinimapCluster then pcall(tree, MinimapCluster, "MinimapCluster", 0) end
    out[#out + 1] = "Minimap children:"
    pcall(function()
        for _, c in ipairs({ Minimap:GetChildren() }) do tree(c, "#", 1) end
    end)
    pcall(function()
        out[#out + 1] = "zoom=" .. tostring(Minimap:GetZoom()) .. " levels=" .. tostring(Minimap:GetZoomLevels())
            .. " indoors=" .. tostring(IsIndoors and IsIndoors())
            .. " rotate=" .. tostring(GetCVar and GetCVar("rotateMinimap"))
        local kids, regs = { Minimap:GetChildren() }, { Minimap:GetRegions() }
        out[#out + 1] = "children=" .. #kids .. " regions=" .. #regs
        for i, r in ipairs(regs) do
            if i <= 12 then
                out[#out + 1] = "  region " .. tostring(r:GetObjectType()) .. " shown=" .. tostring(r:IsShown())
                    .. " layer=" .. tostring(r.GetDrawLayer and r:GetDrawLayer())
                    .. " tex=" .. tostring(r.GetTexture and r:GetTexture())
                    .. " size=" .. f2(r:GetWidth()) .. "x" .. f2(r:GetHeight())
            end
        end
        for i, c in ipairs(kids) do
            if i <= 16 and c:IsShown() then
                out[#out + 1] = "  child " .. tostring(c:GetObjectType()) .. " " .. tostring(c.GetName and c:GetName() or "?")
                    .. " level=" .. tostring(c:GetFrameLevel()) .. " alpha=" .. f2(c:GetAlpha())
                    .. " size=" .. f2(c:GetWidth()) .. "x" .. f2(c:GetHeight())
            end
        end
    end)
    MinimalUIDB.domeprobe = out
end

-- Drag handle over the dome (the map itself uses clicks for pings).
function MM:SetDomeMover(on)
    local h = self.domeHolder
    if not h then return end
    local mv = self.domeMover
    if not mv then
        mv = CreateFrame("Frame", nil, UIParent)
        mv:SetAllPoints(h)
        mv:SetFrameStrata("DIALOG")
        mv:EnableMouse(true)
        mv:RegisterForDrag("LeftButton")
        local t = mv:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        t:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.25)
        t:AddMaskTexture(circleMask(mv, h:GetWidth()))
        local label = ns:CreateText(mv, 11)
        label:SetPoint("CENTER")
        label:SetText("Drag  ·  /men dome move to finish")
        h:SetMovable(true)
        mv:SetScript("OnDragStart", function() if not InCombatLockdown() then h:StartMoving() end end)
        mv:SetScript("OnDragStop", function()
            h:StopMovingOrSizing()
            -- Store as an offset from the bottom center of the screen.
            local cx, by = h:GetCenter(), h:GetBottom()
            local ux = UIParent:GetWidth() / 2
            MM.db.domePos = { x = math.floor(cx - ux + 0.5), y = math.floor(by + 0.5) }
            MM:PlaceDome()
        end)
        self.domeMover = mv
        mv:Hide()
    end
    if on == nil then on = not mv:IsShown() end
    mv:SetShown(on)
end

ns.commands.dome = function(rest)
    rest = rest or ""
    if rest:find("move") then
        if not MM.domeHolder then return ns:Print("Turn the dome on first: /men dome") end
        MM:SetDomeMover()
        return
    end
    if rest:find("probe") then
        MM:ProbeDome()
        return ns:Print("Minimap state saved; /reload so it can be read.")
    end
    -- /men dome fix [seconds] : settle the hover areas now (zoom one step,
    -- wait, step back); /men dome gap <seconds> keeps that wait.
    local fixGap = rest:match("fix%s*([%d%.]*)")
    if fixGap then
        if not MM.SettleDome then return ns:Print("Turn the dome on first: /men dome") end
        local g = tonumber(fixGap)
        MM:SettleDome(g)
        return ns:Print("Minimap: zoom stepped, stepping back in " .. tostring(g or MM.db.domeGap or 2) .. " s. Then point at a dot.")
    end
    local keepGap = rest:match("gap%s*([%d%.]+)")
    if keepGap and tonumber(keepGap) then
        MM.db.domeGap = math.max(0.2, math.min(10, tonumber(keepGap)))
        return ns:Print("Minimap: the settle wait is now " .. MM.db.domeGap .. " s.")
    end
    -- /men dome try size | scale | native : other ways of fitting the map,
    -- until the next reload (for finding out what this client wants).
    local try = rest:match("try%s*(%a+)")
    if try then
        if not MM.TryDome then return ns:Print("Turn the dome on first: /men dome") end
        MM:TryDome(try)
        return ns:Print("Minimap fitted by '" .. try .. "' until you reload (the map's own size here is "
            .. tostring(MM.native and math.floor(MM.native + 0.5)) .. "). /men dome fix settles it.")
    end
    if rest:find("reset") then
        MM.db.domePos = nil
        MM:PlaceDome()
        return ns:Print("Minimap dome back on the action bar.")
    end
    if InCombatLockdown() then return ns:Print("Can't rearrange the action bar in combat.") end
    MM.db.dome = not MM.db.dome
    if MM.db.dome then
        MM:ApplyDome()
        MM:ArrangeAround()
        C_Timer.After(1, function() MM:ProbeDome() end)
        ns:Print("Minimap dome on. /men dome move to drag it, /men dome reset to put it back on the bar.")
    else
        MM:ArrangeAround()
        if MM.domeMover then MM.domeMover:Hide() end
        ns.needsReload = true
        ns:Print("Minimap dome off: /reload to put the minimap back.")
    end
end

-- /men minimap : list what was found/removed (for tuning on this client).
ns.commands.minimap = function()
    if not Minimap then return ns:Print("No Minimap frame.") end
    local n = 0
    for _, obj in pairs(clutter()) do
        if obj then
            n = n + 1
            ns:Print(string.format("%s killed=%s shown=%s", obj:GetName() or obj:GetDebugName() or "?",
                tostring(obj.__muiKilled), tostring(obj:IsShown())))
        end
    end
    ns:Print(n .. " clutter pieces found. Parent:", Minimap:GetParent() and Minimap:GetParent():GetName())
end
