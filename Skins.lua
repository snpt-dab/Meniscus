local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Skins: restyles Blizzard windows in place (nothing moved or rebuilt):
-- dark rounded card behind the window, frame art / portraits faded, round
-- close button, pill buttons, theme font on titles.
--   Game menu (Esc), gossip and quest dialogs (with light text instead of
--   parchment-brown), merchant (+ a "Sell junk" pill), mail, friends,
--   dressing room, and the world map (+ a coordinates pill).
-- Everything is alpha-only on Blizzard regions, so combat is never a problem.

local S = ns:NewModule("Skins", { enabled = true, coords = true })

local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local FILL = { 0.06, 0.06, 0.07, 0.97 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local BODY = { 0.86, 0.86, 0.89 }
local TITLE = { 1, 1, 1 }

local function fade(o)
    if not o or not o.SetAlpha or o.__muiFaded then return end
    o.__muiFaded = true
    o:SetAlpha(0)
    hooksecurefunc(o, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
end

-- Background-ish textures directly on a frame (parchment, panel art).
local function stripBackground(f)
    if not f or not f.GetRegions then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local layer = r:GetDrawLayer()
            if layer == "BACKGROUND" or layer == "BORDER" then fade(r) end
        end
    end
end

-- ── Round close button ────────────────────────────────────────────────────
local function skinClose(b)
    if not b or b.__muiSkin then return end
    b.__muiSkin = true
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then fade(b[get](b)) end
    end
    for _, r in ipairs({ b:GetRegions() }) do if r:IsObjectType("Texture") then fade(r) end end
    local skin = CreateFrame("Frame", nil, b)
    skin:SetSize(20, 20)
    skin:SetPoint("CENTER")
    local mask = skin:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    local bg = skin:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.16, 0.18, 1)
    bg:AddMaskTexture(mask)
    local lines = {}
    for i, p in ipairs({ { -1, 1, 1, -1 }, { -1, -1, 1, 1 } }) do
        local l = skin:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetStartPoint("CENTER", skin, p[1] * 4, p[2] * 4)
        l:SetEndPoint("CENTER", skin, p[3] * 4, p[4] * 4)
        l:SetColorTexture(unpack(T.textDim))
        lines[i] = l
    end
    b:HookScript("OnEnter", function()
        bg:SetColorTexture(unpack(T.accent))
        for _, l in ipairs(lines) do l:SetColorTexture(unpack(TEXT_DARK)) end
    end)
    b:HookScript("OnLeave", function()
        bg:SetColorTexture(0.16, 0.16, 0.18, 1)
        for _, l in ipairs(lines) do l:SetColorTexture(unpack(T.textDim)) end
    end)
end

-- ── Pill buttons (UIPanelButtonTemplate and friends) ──────────────────────
local btnFont, btnFontDim, btnFontDark
local function buttonFonts()
    if btnFont then return end
    btnFont = CreateFont("MinimalUIButtonFont")
    btnFont:SetFont(T.fontBold, 12, "")
    btnFont:SetTextColor(unpack(T.text))
    btnFont:SetShadowOffset(0, 0)
    btnFontDim = CreateFont("MinimalUIButtonFontDim")
    btnFontDim:SetFont(T.fontBold, 12, "")
    btnFontDim:SetTextColor(0.45, 0.45, 0.5)
    btnFontDark = CreateFont("MinimalUIButtonFontDark")
    btnFontDark:SetFont(T.fontBold, 12, "")
    btnFontDark:SetTextColor(unpack(TEXT_DARK))
    btnFontDark:SetShadowOffset(0, 0)
end

-- Primary (light pill, dark text) vs secondary (dark pill, light text).
function ns.SetButtonPrimary(b, on)
    if not b or not b.__muiPaint then return end
    b.__muiPrimary = on and true or false
    pcall(b.SetNormalFontObject, b, on and btnFontDark or btnFont)
    pcall(b.SetHighlightFontObject, b, on and btnFontDark or btnFont)
    b.__muiRepaint()
end

function ns.SkinButton(b)
    if not b or b.__muiSkin or not b.IsObjectType or not b:IsObjectType("Button") then return end
    b.__muiSkin = true
    buttonFonts()
    local name = b:GetName()
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do
        fade(b[k]); if name then fade(_G[name .. k]) end
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then fade(b[get](b)) end
    end
    -- Any other art the template draws on the button itself (e.g. the game
    -- menu's red bars): fade every texture already there.
    for _, r in ipairs({ b:GetRegions() }) do
        if r:IsObjectType("Texture") then fade(r) end
    end
    local h = math.max(b:GetHeight(), 16)
    local raw = ns.RoundedRect(b, -6, 2, math.floor(h / 2) - 2, 0.17, 0.17, 0.20, 1)
    b.__muiCol = { 0.17, 0.17, 0.20, 1 }
    -- Every color change eases (see ns.TweenColor): quick in, a touch
    -- slower out, near-instant when pressed.
    local function paint(r, g, bl, a, dur)
        ns.TweenColor(b, raw, r, g, bl, a, dur)
    end
    b.__muiPaint = paint
    local function rest()
        if b.__muiPrimary then paint(0.86, 0.86, 0.89, 1, 0.18) else paint(0.17, 0.17, 0.20, 1, 0.18) end
    end
    b.__muiRepaint = rest
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then paint(T.accent[1], T.accent[2], T.accent[3], 0.85, 0.12) end end)
    b:HookScript("OnLeave", rest)
    b:HookScript("OnMouseDown", function(self) if self:IsEnabled() then paint(T.accent[1] * 0.8, T.accent[2] * 0.8, T.accent[3] * 0.8, 1, 0.04) end end)
    b:HookScript("OnMouseUp", function(self) if self:IsEnabled() and self:IsMouseOver() then paint(T.accent[1], T.accent[2], T.accent[3], 0.85, 0.1) end end)
    pcall(b.SetNormalFontObject, b, btnFont)
    pcall(b.SetHighlightFontObject, b, btnFont)
    pcall(b.SetDisabledFontObject, b, btnFontDim)
    -- The label sat high in the pill (Blizzard's templates lift it a pixel,
    -- and our font's box sits high on its letters): centre it on the pill,
    -- a pixel low, so the letters look centred.
    local fs = b:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", b, "CENTER", 0, -1)
    end
end

-- ── Window card ───────────────────────────────────────────────────────────
function ns.SkinWindow(f, opts)
    if not f or f.__muiSkin then return end
    f.__muiSkin = true
    opts = opts or {}
    local name = f:GetName()
    for _, o in ipairs({ f.NineSlice, f.Bg, f.Background, f.TopTileStreaks, f.PortraitContainer, f.portrait,
                         f.Border, f.Header and f.Header.LeftBG, f.Header and f.Header.RightBG,
                         f.Header and f.Header.CenterBG }) do
        fade(o)
    end
    if name then
        for _, k in ipairs({ "Portrait", "PortraitFrame", "Bg", "TopTileStreaks", "BtnCornerLeft", "BtnCornerRight",
                             "ButtonBottomBorder" }) do
            fade(_G[name .. k])
        end
    end
    for _, sub in ipairs({ f.Inset, f.BorderFrame, name and _G[name .. "Inset"] }) do
        if sub then
            for _, o in ipairs({ sub.NineSlice, sub.Bg, sub.TopTileStreaks, sub.PortraitContainer, sub.portrait,
                                 sub.InsetBorderTop, sub.InsetBorderBottom, sub.InsetBorderLeft, sub.InsetBorderRight,
                                 sub.InsetBorderTopLeft, sub.InsetBorderTopRight, sub.InsetBorderBottomLeft,
                                 sub.InsetBorderBottomRight }) do
                fade(o)
            end
        end
    end
    if opts.strip then stripBackground(f) end

    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", opts.l or 0, -(opts.t or 0))
    holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(opts.r or 0), opts.b or 0)
    holder:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    ns.RoundedRect(holder, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(holder, -7, 1, 11, unpack(FILL))
    f.__muiHolder = holder

    skinClose(f.CloseButton or (f.BorderFrame and f.BorderFrame.CloseButton) or (name and _G[name .. "CloseButton"]))
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or (f.BorderFrame and f.BorderFrame.TitleContainer
        and f.BorderFrame.TitleContainer.TitleText) or (name and _G[name .. "TitleText"])
        or (f.Header and f.Header.Text)
    if title then
        local _, size = title:GetFont()
        ns:SetFont(title, math.max(size or 13, 13), "", true)
        title:SetTextColor(unpack(T.text))
    end
end

local function skinButtonsIn(f, depth)
    if not f or (depth or 0) > 3 then return end
    for _, c in ipairs({ f:GetChildren() }) do
        if c:IsObjectType("Button") and (c.Left or c.Middle) and c:GetFontString() then ns.SkinButton(c) end
        skinButtonsIn(c, (depth or 0) + 1)
    end
end

-- ── Game menu (Esc) ───────────────────────────────────────────────────────
local function skinGameMenu()
    local g = _G.GameMenuFrame
    if not g then return end
    -- Border and header art (names vary by client): fade every texture on
    -- the menu and on its non-button children, before our card is added.
    local function stripArt(f, depth)
        for _, r in ipairs({ f:GetRegions() }) do
            if r:IsObjectType("Texture") then fade(r) end
        end
        if depth >= 3 then return end
        for _, c in ipairs({ f:GetChildren() }) do
            if not c:IsObjectType("Button") then stripArt(c, depth + 1) end
        end
    end
    stripArt(g, 0)
    ns.SkinWindow(g)
    -- The title rides Blizzard's header plaque, which hangs over the top
    -- edge; with the plaque gone, bring the title inside the card so it sits
    -- evenly between the top edge and the first button.
    local title = (g.Header and (g.Header.Text or g.Header.text)) or _G.GameMenuFrameHeaderText
    if title then
        title:ClearAllPoints()
        title:SetPoint("TOP", g, "TOP", 0, -22)
    end
    local function buttons()
        for _, c in ipairs({ g:GetChildren() }) do
            if c:IsObjectType("Button") and c:GetFontString() and c ~= g.CloseButton then ns.SkinButton(c) end
        end
    end
    if g.InitButtons then hooksecurefunc(g, "InitButtons", buttons) end
    g:HookScript("OnShow", buttons)
    -- InitButtons re-sets OnEnter/OnLeave on its pooled buttons with
    -- SetScript, which wipes our hover hooks (and can leave a button stuck
    -- lit). Drive hover from our own child frame instead: it only ticks
    -- while the menu is shown, and nothing of Blizzard's touches it. On
    -- every change, every button is repainted, so stale highlights clear.
    local driver = CreateFrame("Frame", nil, g)
    driver:SetSize(1, 1)
    driver:SetPoint("TOPLEFT")
    local hovered, down = false, false
    local function paintAll(now, pressed)
        for _, c in ipairs({ g:GetChildren() }) do
            if c.__muiPaint then
                if c == now then
                    local k = pressed and 0.8 or 1
                    c.__muiPaint(T.accent[1] * k, T.accent[2] * k, T.accent[3] * k, pressed and 1 or 0.85,
                        pressed and 0.04 or 0.12)
                elseif c.__muiRepaint then
                    c.__muiRepaint()
                end
            end
        end
    end
    driver:SetScript("OnUpdate", function()
        local now
        local kids, n = ns.Kids(g, 0)
        for i = 1, n do
            local c = kids[i]
            if c.__muiPaint and c:IsShown() and c.IsEnabled and c:IsEnabled() and c:IsMouseOver() then
                now = c; break
            end
        end
        local pressed = now and IsMouseButtonDown("LeftButton") or false
        if now == hovered and pressed == down then return end
        hovered, down = now, pressed
        paintAll(now, pressed)
    end)
    driver:SetScript("OnShow", function() hovered = false; paintAll(nil) end)
end

-- ── Gossip / quest dialogs ────────────────────────────────────────────────
-- Blizzard colors this text brown for parchment; on our dark card it needs
-- to be light. Hooks catch every place Blizzard re-colors it.
local function lightText()
    -- Theme font too (Blizzard's quest fonts are the serif / Morpheus faces).
    local function restyle(n, path, color)
        local fo = _G[n]
        if not (fo and fo.SetTextColor) then return end
        local _, size, flags = fo:GetFont()
        if size then
            size = path == T.fontBold and math.min(size, 16) or math.max(size, 12)
            pcall(fo.SetFont, fo, path, size, flags or "")
        end
        fo:SetTextColor(unpack(color))
        pcall(fo.SetShadowOffset, fo, 0, 0)
    end
    for _, n in ipairs({ "QuestFont", "QuestFontLeft", "QuestFontNormalSmall", "QuestFont_Shadow_Small",
                         "QuestFontHighlight", "QuestFont_Large" }) do
        restyle(n, T.font, BODY)
    end
    for _, n in ipairs({ "QuestTitleFont", "QuestTitleFontBlackShadow", "QuestFont_Super_Huge",
                         "QuestFont_Huge", "QuestFont_Shadow_Huge" }) do
        restyle(n, T.fontBold, TITLE)
    end
    if _G.QuestFrame_SetTitleTextColor then
        hooksecurefunc("QuestFrame_SetTitleTextColor", function(fs) if fs then fs:SetTextColor(unpack(TITLE)) end end)
    end
    if _G.QuestFrame_SetTextColor then
        hooksecurefunc("QuestFrame_SetTextColor", function(fs) if fs then fs:SetTextColor(unpack(BODY)) end end)
    end
end

-- Slim scrollbar: arrows and track art gone, the thumb becomes a thin
-- rounded bar.
function ns.SkinScrollBar(sb)
    if not sb or sb.__muiSkin then return end
    sb.__muiSkin = true
    local function fadeAll(f)
        if not f then return end
        for _, r in ipairs({ f:GetRegions() }) do if r:IsObjectType("Texture") then fade(r) end end
    end
    for _, k in ipairs({ "Back", "Forward", "ScrollUpButton", "ScrollDownButton" }) do
        local b = sb[k]
        if b then fadeAll(b); b:SetAlpha(0); b:EnableMouse(false) end
    end
    fadeAll(sb)
    local track = sb.Track
    if track then
        fadeAll(track)
        local thumb = track.Thumb or sb.ThumbTexture
        if thumb and thumb.GetRegions then
            fadeAll(thumb)
            local bar = CreateFrame("Frame", nil, thumb)
            bar:SetPoint("TOP", 0, -2)
            bar:SetPoint("BOTTOM", 0, 2)
            bar:SetWidth(4)
            ns.RoundedRect(bar, 0, 0, 2, 0.32, 0.32, 0.36, 1)
        end
    end
end

-- ── Talking NPC portrait ──────────────────────────────────────────────────
-- The NPC's 3D head pops out over the dialog's top-left corner (same
-- construction as the unit-frame avatars: dark circle, a model window whose
-- head rises out of the top, a crescent lip hiding the window's edges), and
-- it plays a short talk animation whenever the dialog opens or turns a page.
local MEDIA = "Interface/AddOns/Meniscus/Media/"
local TALK_ANIM = 60 -- EmoteTalk

local function makeTalker(frame, unit)
    local D = 74
    local av = CreateFrame("Frame", nil, frame)
    av:SetSize(D, D)
    av:SetPoint("CENTER", frame, "TOPLEFT", 26, -22)
    av:SetFrameLevel(frame:GetFrameLevel() + 20)
    local function circleTex(size, sub, r, g, b, a)
        local t = av:CreateTexture(nil, "BACKGROUND", nil, sub)
        t:SetSize(size, size)
        t:SetPoint("CENTER")
        t:SetColorTexture(r, g, b, a)
        local m = av:CreateMaskTexture()
        m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        return t
    end
    circleTex(D, 0, T.border[1], T.border[2], T.border[3], 1)
    circleTex(D - 4, 1, 0.05, 0.05, 0.06, 1)
    av.tint = circleTex(D - 4, 2, 1, 1, 1, 0.10)

    av.flat = av:CreateTexture(nil, "ARTWORK")
    av.flat:SetSize(D - 4, D - 4)
    av.flat:SetPoint("CENTER")
    local fm = av:CreateMaskTexture()
    fm:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fm:SetAllPoints(av.flat)
    av.flat:AddMaskTexture(fm)
    av.flat:Hide()

    local m = CreateFrame("PlayerModel", nil, av)
    m:SetFrameLevel(av:GetFrameLevel() + 1)
    m:SetSize(0.8 * D, 1.05 * D)
    m:SetPoint("BOTTOM", av, "CENTER", 0, -0.3 * D)
    m:SetScript("OnAnimFinished", function(self) pcall(self.SetAnimation, self, 0) end)
    av.model = m

    local lip = CreateFrame("Frame", nil, av)
    lip:SetAllPoints()
    lip:SetFrameLevel(m:GetFrameLevel() + 1)
    for i, file in ipairs({ "lip_fill.tga", "lip_rim.tga", "lip_ring.tga" }) do
        local t = lip:CreateTexture(nil, "ARTWORK", nil, i)
        t:SetAllPoints()
        t:SetTexture(MEDIA .. file)
        if i == 1 then t:SetVertexColor(0.05, 0.05, 0.06, 1)
        elseif i == 2 then t:SetVertexColor(1, 1, 1, 0.35)
        else t:SetVertexColor(unpack(T.border)) end
    end

    function av:Talk()
        if not UnitExists(unit) then self:Hide(); return end
        self:Show()
        local r, g, b = 1, 1, 1
        local ok, reaction = pcall(UnitReaction, unit, "player")
        if ok and type(reaction) == "number" and not (issecretvalue and issecretvalue(reaction)) then
            if reaction <= 3 then r, g, b = 0.9, 0.35, 0.3 elseif reaction == 4 then r, g, b = 0.95, 0.8, 0.35
            else r, g, b = 0.4, 0.85, 0.5 end
        end
        self.tint:SetColorTexture(r, g, b, 0.14)
        local visible = UnitIsVisible(unit)
        if issecretvalue and issecretvalue(visible) then visible = true end
        if visible then
            self.flat:Hide()
            m:Show()
            m:ClearModel()
            m:SetUnit(unit)
            pcall(m.SetPortraitZoom, m, 1)
            pcall(m.SetCamDistanceScale, m, 1)
            pcall(m.SetPosition, m, 0, 0.04, 0)
            pcall(m.SetAnimation, m, TALK_ANIM)
        else
            m:Hide()
            SetPortraitTexture(self.flat, unit)
            self.flat:Show()
        end
    end

    -- The name moves beside the head, left-aligned.
    local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or _G[(frame:GetName() or "") .. "TitleText"]
    if title then
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 72, -14)
        title:SetJustifyH("LEFT")
    end
    frame:HookScript("OnShow", function() av:Talk() end)
    return av
end

local function skinDialogs()
    lightText()
    local q = _G.QuestFrame
    if q then
        ns.SkinWindow(q, { strip = true })
        for _, n in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel",
                             "QuestFrameGreetingPanel", "QuestDetailScrollFrame", "QuestProgressScrollFrame",
                             "QuestRewardScrollFrame", "QuestGreetingScrollFrame", "QuestDetailScrollChildFrame",
                             "QuestRewardScrollChildFrame" }) do
            stripBackground(_G[n])
        end
        skinButtonsIn(q)
        for _, n in ipairs({ "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame",
                             "QuestGreetingScrollFrame" }) do
            local sf = _G[n]
            if sf then ns.SkinScrollBar(sf.ScrollBar or _G[n .. "ScrollBar"]) end
        end
        -- (Our own dialog window replaces these when the Dialogs module is on.)
        if ns.db.modules.Dialogs and ns.db.modules.Dialogs.enabled == false then
            q.__muiTalker = makeTalker(q, "questnpc")
        end
    end
    local gf = _G.GossipFrame
    if gf then
        ns.SkinWindow(gf, { strip = true })
        stripBackground(gf.GreetingPanel)
        if gf.GreetingPanel then
            stripBackground(gf.GreetingPanel.ScrollBox)
            if gf.GreetingPanel.GoodbyeButton then ns.SkinButton(gf.GreetingPanel.GoodbyeButton) end
        end
        skinButtonsIn(gf)
        if gf.GreetingPanel then ns.SkinScrollBar(gf.GreetingPanel.ScrollBar) end
        if ns.db.modules.Dialogs and ns.db.modules.Dialogs.enabled == false then
            gf.__muiTalker = makeTalker(gf, "npc")
        end
        -- Option rows are pooled: lighten their text as they appear.
        gf:HookScript("OnShow", function()
            C_Timer.After(0, function()
                local box = gf.GreetingPanel and gf.GreetingPanel.ScrollBox
                if box and box.ForEachFrame then
                    box:ForEachFrame(function(row)
                        local fs = row.GetFontString and row:GetFontString()
                        if fs then fs:SetTextColor(unpack(BODY)) end
                        if row.GreetingText then row.GreetingText:SetTextColor(unpack(BODY)) end
                    end)
                end
            end)
        end)
    end

    -- Each new page of the conversation: the NPC talks again.
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e)
        C_Timer.After(0, function()
            local t = e == "GOSSIP_SHOW" and gf and gf.__muiTalker or (q and q.__muiTalker)
            if t and t:GetParent():IsShown() then t:Talk() end
        end)
    end)
end

-- ── Merchant: skin + "Sell junk" ──────────────────────────────────────────
local function skinMerchant()
    local m = _G.MerchantFrame
    if not m then return end
    ns.SkinWindow(m)
    skinButtonsIn(m)
    local MF = C_MerchantFrame
    if not (MF and MF.SellAllJunkItems) then return end
    local b = CreateFrame("Button", nil, m)
    b:SetSize(100, 24)
    b:SetPoint("BOTTOMRIGHT", m, "TOPRIGHT", 0, 6)
    local paint = ns.RoundedRect(b, -6, 0, 12, 0.86, 0.86, 0.89, 1)
    local fs = b:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, 11, "", true)
    fs:SetTextColor(unpack(TEXT_DARK))
    fs:SetPoint("CENTER")
    b:SetScript("OnEnter", function() paint(unpack(T.accent)) end)
    b:SetScript("OnLeave", function() paint(0.86, 0.86, 0.89, 1) end)
    b:SetScript("OnClick", function() pcall(MF.SellAllJunkItems) end)
    local function update()
        local ok, n = pcall(MF.GetNumJunkItems)
        if ok and type(n) == "number" and n > 0 then
            fs:SetText(string.format("Sell junk (%d)", n))
            b:SetWidth(fs:GetStringWidth() + 28)
            b:Show()
        else
            b:Hide()
        end
    end
    m:HookScript("OnShow", update)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("MERCHANT_SHOW")
    ev:SetScript("OnEvent", function() if m:IsShown() then update() end end)
end

-- ── World map: skin + coordinates ─────────────────────────────────────────
local function skinMap()
    local wm = _G.WorldMapFrame
    if not wm then return end
    ns.SkinWindow(wm)
    if not S.db.coords then return end
    local sc = wm.ScrollContainer
    local chip = CreateFrame("Frame", nil, sc or wm)
    chip:SetHeight(22)
    chip:SetPoint("BOTTOMLEFT", sc or wm, "BOTTOMLEFT", 10, 10)
    chip:SetFrameLevel((sc or wm):GetFrameLevel() + 50)
    ns.RoundedRect(chip, -6, 0, 11, 0.06, 0.06, 0.07, 0.88)
    local fs = chip:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, 11, "", true)
    fs:SetTextColor(unpack(T.text))
    fs:SetPoint("CENTER")
    local acc = 0
    chip:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        local you, cur
        local mapID = wm.GetMapID and wm:GetMapID()
        if mapID and C_Map and C_Map.GetPlayerMapPosition then
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
            if ok and pos and pos.GetXY then
                local x, y = pos:GetXY()
                if x and y and not (issecretvalue and (issecretvalue(x) or issecretvalue(y))) and (x > 0 or y > 0) then
                    you = string.format("You  %.1f, %.1f", x * 100, y * 100)
                end
            end
        end
        if sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver() then
            local ok, x, y = pcall(sc.GetNormalizedCursorPosition, sc)
            if ok and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                cur = string.format("|cff9a9aa5Cursor|r  %.1f, %.1f", x * 100, y * 100)
            end
        end
        local text = (you and cur) and (you .. "     " .. cur) or you or cur or ""
        -- (Alpha, not Hide: a hidden frame's OnUpdate stops, and the chip
        -- would never come back.)
        chip:SetAlpha(text ~= "" and 1 or 0)
        if text ~= chip.__text then
            chip.__text = text
            fs:SetText(text)
            chip:SetWidth(fs:GetStringWidth() + 24)
        end
    end)
end

-- ── Other windows ─────────────────────────────────────────────────────────
-- ── Popups (StaticPopup1-4) ───────────────────────────────────────────────
-- Logout countdown, abandon quest, bind on pickup, delete item, buy bank
-- slot...: small dark card, theme font, pill buttons (the main action light,
-- Cancel / No / Decline dark), a rounded input field, and a thin bar draining
-- along the bottom for timed ones (logout, quit, resurrect).
local NEGATIVE = {}
local function negatives()
    for _, k in ipairs({ "CANCEL", "NO", "DECLINE", "OKAY_CANCEL", "CLOSE", "NEVERMIND" }) do
        local v = _G[k]
        if type(v) == "string" then NEGATIVE[v] = true end
    end
end

local function stripDeep(f, depth)
    if not f then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") then fade(r) end
    end
    if depth >= 2 then return end
    for _, c in ipairs({ f:GetChildren() }) do stripDeep(c, depth + 1) end
end

local function skinPopup(f)
    if not f or f.__muiPopup then return end
    f.__muiPopup = true
    local name = f:GetName()
    -- Frame art: the popup's own textures and its border pieces.
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= (f.AlertIcon or _G[name .. "AlertIcon"]) then fade(r) end
    end
    stripDeep(f.Border, 0); stripDeep(f.NineSlice, 0); stripDeep(f.BG, 0)
    ns.SkinWindow(f)

    local buttons = {}
    for j = 1, 4 do
        local b = f["button" .. j] or _G[name .. "Button" .. j]
            or (f.ButtonContainer and f.ButtonContainer["Button" .. j])
            or (f.GetButton and select(2, pcall(f.GetButton, f, j)))
        if type(b) ~= "table" then b = nil end
        if b then ns.SkinButton(b); buttons[j] = b end
    end
    -- Input field: Blizzard's box art off, our rounded field on.
    local eb = f.editBox or f.EditBox or _G[name .. "EditBox"]
    if eb then
        for _, r in ipairs({ eb:GetRegions() }) do
            if r:IsObjectType("Texture") then fade(r) end
        end
        for _, k in ipairs({ "Left", "Middle", "Right" }) do fade(eb[k]); fade(_G[eb:GetName() and (eb:GetName() .. k) or ""]) end
        ns.RoundedRect(eb, -8, -4, 11, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(eb, -7, -3, 10, 0.05, 0.05, 0.06, 1)
        pcall(eb.SetTextInsets, eb, 6, 6, 0, 0)
    end
    -- Countdown bar.
    local holder = f.__muiHolder or f
    local track = holder:CreateTexture(nil, "ARTWORK")
    track:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 14, 7)
    track:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -14, 7)
    track:SetHeight(3)
    track:SetColorTexture(0.16, 0.16, 0.18, 1)
    local bar = holder:CreateTexture(nil, "ARTWORK", nil, 1)
    bar:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT")
    bar:SetHeight(3)
    bar:SetColorTexture(unpack(T.accent))
    track:Hide(); bar:Hide()

    f:HookScript("OnShow", function(self)
        local text = self.text or self.Text or _G[name .. "Text"]
        if text then
            local _, size = text:GetFont()
            pcall(text.SetFont, text, T.font, math.max(size or 13, 13), "")
            text:SetTextColor(unpack(T.text))
            text:SetShadowOffset(0, 0)
        end
        -- Main action light unless it's a Cancel/No (e.g. logout's only button).
        local first = true
        for j = 1, 4 do
            local b = buttons[j]
            if b and b:IsShown() then
                local label = b:GetText()
                ns.SetButtonPrimary(b, first and not (label and NEGATIVE[label]))
                first = false
            end
        end
        -- With the alert icon on the left, Blizzard centres the message in
        -- the room beside it but the buttons on the whole popup, so they
        -- sat left of the text. Line the button row up under the message.
        C_Timer.After(0, function()
            if not self:IsShown() or InCombatLockdown() then return end
            local row = self.ButtonContainer or buttons[1]
            local msg = self.text or self.Text or _G[name .. "Text"]
            if not (row and msg) then return end
            local p, rel, rp, x, y = row:GetPoint(1)
            if not p then return end
            local base = x - (self.__muiDx or 0)
            local icon = self.AlertIcon or _G[name .. "AlertIcon"]
            local dx = 0
            if icon and icon:IsShown() then
                local mx, fx = msg:GetCenter(), self:GetCenter()
                if mx and fx then dx = math.floor(mx - fx + 0.5) end
            end
            self.__muiDx = dx
            row:SetPoint(p, rel, rp, base + dx, y)
        end)
        self.__muiMax = (type(self.timeleft) == "number" and self.timeleft > 0) and self.timeleft or nil
        track:SetShown(self.__muiMax ~= nil)
        bar:SetShown(self.__muiMax ~= nil)
    end)
    f:HookScript("OnUpdate", function(self)
        local max = self.__muiMax
        if not max then return end
        local left = type(self.timeleft) == "number" and self.timeleft or 0
        bar:SetWidth(math.max(1, track:GetWidth() * math.max(0, math.min(1, left / max))))
    end)
end

local function skinPopups()
    negatives()
    for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do pcall(skinPopup, _G["StaticPopup" .. i]) end
end

-- ── Tabard designer (restyle in place) ────────────────────────────────────
-- Round arrow buttons with drawn chevrons (dir -1 left, 1 right).
local function arrowButton(b, dir)
    if not b or b.__muiSkin then return end
    b.__muiSkin = true
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then fade(b[get](b)) end
    end
    for _, r in ipairs({ b:GetRegions() }) do if r:IsObjectType("Texture") then fade(r) end end
    local skin = CreateFrame("Frame", nil, b)
    skin:SetSize(22, 22)
    skin:SetPoint("CENTER")
    local m = skin:CreateMaskTexture()
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints()
    local bg = skin:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.16, 0.18, 1)
    bg:AddMaskTexture(m)
    local lines = {}
    for i, p in ipairs({ { 2, 4, -2, 0 }, { -2, 0, 2, -4 } }) do
        local l = skin:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.6)
        l:SetStartPoint("CENTER", skin, p[1] * dir * -1, p[2])
        l:SetEndPoint("CENTER", skin, p[3] * dir * -1, p[4])
        l:SetColorTexture(unpack(T.text))
        lines[i] = l
    end
    b:HookScript("OnEnter", function()
        bg:SetColorTexture(unpack(T.accent)); for _, l in ipairs(lines) do l:SetColorTexture(unpack(TEXT_DARK)) end
    end)
    b:HookScript("OnLeave", function()
        bg:SetColorTexture(0.16, 0.16, 0.18, 1); for _, l in ipairs(lines) do l:SetColorTexture(unpack(T.text)) end
    end)
end

local function skinTabard()
    local f = _G.TabardFrame
    if not f or f.__muiTabard then return end
    f.__muiTabard = true
    -- Frame art off, except the emblem preview.
    for _, r in ipairs({ f:GetRegions() }) do
        local n = r.GetName and r:GetName() or ""
        if r:IsObjectType("Texture") and not n:find("Emblem") then fade(r) end
    end
    -- Borders and boxes live on child frames too (customization block, cost
    -- and money boxes): fade their textures, skipping buttons (arrows, coin
    -- icons), models, and the emblem preview.
    local function stripKids(fr, depth)
        for _, c in ipairs({ fr:GetChildren() }) do
            local isButton = c:IsObjectType("Button")
            local isModel = c:IsObjectType("PlayerModel") or c:IsObjectType("Model") or c:IsObjectType("DressUpModel")
                or (c.IsObjectType and c:IsObjectType("TabardModel"))
            if not isButton and not isModel then
                for _, r in ipairs({ c:GetRegions() }) do
                    local n = r.GetName and r:GetName() or ""
                    if r:IsObjectType("Texture") and not n:find("Emblem") then fade(r) end
                end
                if depth < 2 then stripKids(c, depth + 1) end
            end
        end
    end
    pcall(stripKids, f, 0)
    ns.SkinWindow(f)
    -- Title: the vendor's name in white, with room to show in full.
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.TabardFrameNameText
        or _G.TabardFrameTitleText
    local function fixTitle()
        if not title then return end
        ns:SetFont(title, 14, "", true)
        title:SetTextColor(unpack(T.text))
        title:SetWidth(f:GetWidth() - 90)
        title:SetWordWrap(false)
    end
    fixTitle()
    f:HookScript("OnShow", function() C_Timer.After(0, fixTitle) end)
    local greet = _G.TabardFrameGreetingText
    if greet then ns:SetFont(greet, 13, ""); greet:SetTextColor(unpack(T.text)) end

    for i = 1, 5 do
        local row = _G["TabardFrameCustomization" .. i]
        if row then
            for _, r in ipairs({ row:GetRegions() }) do
                if r:IsObjectType("Texture") then fade(r) end
                if r:IsObjectType("FontString") then ns:SetFont(r, 12, "", true); r:SetTextColor(unpack(T.text)) end
            end
            ns.RoundedRect(row, -6, 2, 12, 0.12, 0.12, 0.14, 1)
            local n = row:GetName()
            arrowButton(row.LeftButton or _G[n .. "LeftButton"], -1)
            arrowButton(row.RightButton or _G[n .. "RightButton"], 1)
        end
    end
    arrowButton(_G.TabardCharacterModelRotateLeftButton, -1)
    arrowButton(_G.TabardCharacterModelRotateRightButton, 1)

    local accept, cancel = _G.TabardFrameAcceptButton, _G.TabardFrameCancelButton
    ns.SkinButton(accept); ns.SkinButton(cancel)
    ns.SetButtonPrimary(accept, true)

    -- Cost and money: dark pills.
    for _, n in ipairs({ "TabardFrameCostFrame", "TabardFrameMoneyBg", "TabardFrameMoneyInset", "TabardFrameMoneyFrame" }) do
        local fr = _G[n]
        if fr and fr.GetRegions then
            for _, r in ipairs({ fr:GetRegions() }) do
                local rn = r.GetName and r:GetName() or ""
                -- keep coin icons (named ...Texture inside money buttons are children, not regions)
                if r:IsObjectType("Texture") and not rn:find("Coin") then fade(r) end
            end
            if (n == "TabardFrameCostFrame" or n == "TabardFrameMoneyBg" or n == "TabardFrameMoneyInset")
                and not fr.__muiPill then
                fr.__muiPill = true
                local h = math.max(16, fr:GetHeight() or 22)
                ns.RoundedRect(fr, -6, 0, math.floor(h / 2), 0.12, 0.12, 0.14, 1)
            end
        end
    end
    -- Dark panels behind the model and emblem: soft cards.
    for _, n in ipairs({ "TabardFrameInset", "TabardFrameCustomizationBorder" }) do
        local fr = _G[n]
        if fr and fr.GetRegions then
            for _, r in ipairs({ fr:GetRegions() }) do if r:IsObjectType("Texture") then fade(r) end end
            if fr.NineSlice then fade(fr.NineSlice) end
        elseif fr and fr.IsObjectType and fr:IsObjectType("Texture") then
            fade(fr) -- some of these are single images, not frames
        end
    end
end

-- ── Right-click menus ─────────────────────────────────────────────────────
-- Unit, party and chat-name menus (and any other menu built with Blizzard's
-- menu system, plus old-style dropdown lists): dark rounded card with a
-- hairline border and the theme font. Restyled each time one opens
-- (menus are pooled, so the faded art stays faded).
-- The card is drawn as textures ON the menu frame (its lowest layers), not
-- on a child frame: menus get re-raised every time they open, which lifted a
-- child card above the menu items. Our textures are remembered so the
-- art-fading pass never touches them.
-- (Drawing on the menu itself didn't show on old-style dropdown lists, and a
-- child frame got lifted above the items when the menu was re-raised.) So
-- the card is a separate frame shadowing the menu: same strata, one level
-- below it, re-synced every frame while the menu is open.
local function menuCard(f)
    if not f or f.__muiCard then return end
    local card = CreateFrame("Frame", nil, UIParent)
    card:SetAllPoints(f)
    card:EnableMouse(false)
    ns.RoundedRect(card, -8, 0, 9, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(card, -7, 1, 8, 0.08, 0.08, 0.09, 0.98)
    local function sync()
        card:SetFrameStrata(f:GetFrameStrata())
        card:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
        card:SetShown(f:IsVisible())
    end
    card:SetScript("OnUpdate", sync)
    f:HookScript("OnShow", function() card:Show(); sync() end)
    f:HookScript("OnHide", function() card:Hide() end)
    f.__muiCard = card
    f.__muiCardSync = sync
    sync()
end

local function fadeArt(f)
    local own = f.__muiOwn or {}
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") and not own[r] then fade(r) end
    end
end

local function themeFonts(f, depth)
    if not f or depth > 4 then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("FontString") then
            local _, size, flags = r:GetFont()
            if size then pcall(r.SetFont, r, T.font, size, flags or "") end
        end
    end
    for _, c in ipairs({ f:GetChildren() }) do themeFonts(c, depth + 1) end
end

-- Rows of the newer menu system (all direct children of the menu frame,
-- matched by what the probe showed they are):
--   136810  hover highlight (gold quest-title glow) -> soft accent wash
--   130940  submenu arrow (gold triangle)            -> drawn chevron
--   radial/check atlases                            -> accent / dim
--   gold text on non-button rows = section header   -> dim bold label
-- Rows are pooled and reused, so this runs every time a menu opens, and the
-- chevron follows its arrow's own visibility.
local FILE_HIGHLIGHT, FILE_ARROW = "136810", "130940"
local function fileOf(t)
    local f = t:GetTexture()
    return f and tostring(f) or ""
end

-- Submenu arrows: Blizzard's own arrow texture, recolored in place to a
-- quiet grey (drawing our own chevron on top went wrong: the compositor
-- recycles and re-anchors these textures freely, so anything that tracks
-- them lags behind). Recolored, Blizzard alone decides when it shows. The
-- same texture object is reused for other icons (raid markers), so a hook
-- puts the color back whenever it's given any other image.
local function greyArrow(r)
    r:SetDesaturated(true)
    r:SetVertexColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
    if r.__muiArrowHook then return end
    r.__muiArrowHook = true
    local function check(self)
        if fileOf(self) == FILE_ARROW then
            self:SetDesaturated(true)
            self:SetVertexColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
        else
            self:SetDesaturated(false)
            self:SetVertexColor(1, 1, 1, 1)
        end
    end
    hooksecurefunc(r, "SetTexture", check)
    if r.SetAtlas then hooksecurefunc(r, "SetAtlas", check) end
end

local function isHeaderGold(cr, cg, cb)
    return type(cr) == "number" and cr > 0.95 and cg > 0.78 and cg < 0.86 and cb < 0.1
end
local function dimHeader(self, cr, cg, cb)
    if isHeaderGold(cr, cg, cb) then
        self:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
    end
end
local function styleMenuRows(menu)
    -- Runs ten times a second per open menu: reusable buffers, no tables.
    local rows, nRows = ns.Kids(menu, 8)
    for i = 1, nRows do
        local row = rows[i]
        local regs, nRegs = nil, 0
        if not row.__muiOurs then regs, nRegs = ns.Regs(row, 8) end
        for j = 1, nRegs do
            local r = regs[j]
            if r:IsObjectType("Texture") and not r:IsObjectType("Line") then
                local atlas = r.GetAtlas and r:GetAtlas()
                atlas = type(atlas) == "string" and atlas:lower() or ""
                local file = fileOf(r)
                if file == FILE_HIGHLIGHT then
                    r:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.16)
                    r:SetAlpha(1)
                elseif file == FILE_ARROW then
                    greyArrow(r)
                elseif atlas == "" and file == "" and r:GetDrawLayer() == "BACKGROUND" then
                    -- A recycled highlight already turned into our color fill.
                    r:SetAlpha(1)
                elseif atlas:find("radialtick") or atlas:find("checkmark") or atlas:find("tick%-yellow") then
                    r:SetDesaturated(true)
                    r:SetVertexColor(unpack(T.accent))
                elseif atlas:find("tickradial") or atlas:find("ticksquare") then
                    r:SetDesaturated(true)
                    r:SetVertexColor(0.45, 0.45, 0.50)
                end
            elseif r:IsObjectType("FontString") then
                local cr, cg, cb = r:GetTextColor()
                -- Blizzard gold (1, .82, 0) = section header. Colored raid
                -- marker names (Star is 1, .92, 0) stay as they are.
                if isHeaderGold(cr, cg, cb) then
                    r:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
                end
                -- Blizzard re-colors headers when it refills an open menu
                -- (picking a raid marker): catch that the moment it happens,
                -- so the gold never shows until the next pass.
                if not r.__muiHdrHook then
                    r.__muiHdrHook = true
                    hooksecurefunc(r, "SetTextColor", dimHeader)
                end
            end
        end
    end
end

local menuErrShown = false
local function safely(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not menuErrShown then
        menuErrShown = true
        ns:Print("Menu styling error (please screenshot): " .. tostring(err))
    end
end

local function styleMenu(menu)
    if not menu then return end
    fadeArt(menu)
    menuCard(menu)
    C_Timer.After(0, function()
        -- Menus are styled as they're created, a moment before they're on
        -- screen: re-check the card's visibility now that it is.
        if menu.__muiCardSync then menu.__muiCardSync() end
        -- Submenus: Blizzard tucks their edge ~10px under the parent menu
        -- (its art had transparent margins). Nudge them clear. Submenus are
        -- anchored to a row of their parent menu; the main menu (anchored to
        -- the cursor / UIParent) is left alone. Blizzard re-anchors on every
        -- open, so only shift an anchor we haven't shifted yet.
        local p, rel, rp, x, y = menu:GetPoint(1)
        if p and rel and rel ~= UIParent and rel.GetParent and rel:GetParent() ~= UIParent
            and type(x) == "number" and menu.__muiShiftedX ~= x then
            local nx = x + (p:find("RIGHT") and -10 or 10)
            menu:ClearAllPoints()
            menu:SetPoint(p, rel, rp, nx, y)
            menu.__muiShiftedX = nx
        end
        -- (No font changes here: Blizzard's menu compositor forbids SetFont
        -- on its rows and reports every attempt as an error.)
        safely(styleMenuRows, menu)
    end)
    -- Blizzard can refill a menu that's already open (right-clicking another
    -- unit, for instance) without hiding it, so OnShow never fires and the
    -- old chevrons stay on rows that now hold other items. Re-check the rows
    -- a few times a second while the menu is open.
    -- (Blizzard clears the menu's own OnUpdate, taking hooks with it, so
    -- the tick lives on a child frame of ours.)
    if not menu.__muiRowTick then
        local tick = CreateFrame("Frame", nil, menu)
        tick.__muiOurs = true
        tick:SetSize(1, 1)
        tick:SetPoint("TOPLEFT")
        menu.__muiRowTick = tick
        local acc = 0
        tick:SetScript("OnShow", function() acc = 0; safely(styleMenuRows, menu) end)
        tick:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.1 then return end
            acc = 0
            safely(styleMenuRows, menu)
        end)
    end
end

-- Menu frames are recognized by their background art. Once seen, a menu is
-- restyled every time it opens (they're pooled).
local knownMenus = {}
local function isMenuFrame(f)
    if f.__muiIsMenu ~= nil then return f.__muiIsMenu end
    local yes = false
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local a = r.GetAtlas and r:GetAtlas()
            if type(a) == "string" and a:find("dropdown%-bg") then yes = true break end
        end
    end
    f.__muiIsMenu = yes
    if yes then
        knownMenus[#knownMenus + 1] = f
        f:HookScript("OnShow", function(self) styleMenu(self) end)
    end
    return yes
end

-- While a menu is open, look for new menu frames (submenus are separate
-- frames on UIParent) and style them when they first appear.
-- The watcher only runs while a menu is open (it stops itself when the last
-- one closes). Looking through all of UIParent's children is the costly
-- part, so that happens ten times a second, and only frames not yet ruled
-- out are examined; whether anything is still open comes from the short
-- list of menus already found.
local watcher = CreateFrame("Frame")
watcher:Hide()
local acc = 0
local scanMenus
watcher:SetScript("OnUpdate", function(self, dt)
    acc = acc + dt
    if acc < 0.1 then return end
    acc = 0
    if ns.Timed then ns.Timed("menu watcher", scanMenus, self) else scanMenus(self) end
end)
local function checkOne(c)
    -- Forbidden (protected Blizzard) frames can't even be asked IsShown.
    if c and c.__muiIsMenu == nil and not (c.IsForbidden and c:IsForbidden()) and c:IsShown() then
        isMenuFrame(c)
    end
end
-- UIParent has hundreds of children: taken eight at a time (a tail call, so
-- no table and no deep stack) instead of select(i, ...) per child.
local function checkTop(n, a, b, c, d, e, f, g, h, ...)
    checkOne(a); checkOne(b); checkOne(c); checkOne(d)
    checkOne(e); checkOne(f); checkOne(g); checkOne(h)
    if n > 8 then return checkTop(n - 8, ...) end
end
function scanMenus(self)
    checkTop(select("#", UIParent:GetChildren()), UIParent:GetChildren())
    local anyOpen = false
    for i = 1, #knownMenus do
        local c = knownMenus[i]
        if c:IsShown() then
            anyOpen = true
            if not c.__muiStyledOnce then c.__muiStyledOnce = true; styleMenu(c) end
        end
    end
    if not anyOpen then self:Hide() end
end
local function watchMenus() acc = 0.1; watcher:Show() end

-- Submenus are separate menu frames: ask every element that has its own
-- submenu to call us when that submenu is acquired (recursively).
local function hookSubmenus(desc, depth)
    if not desc or depth > 4 or not desc.EnumerateElementDescriptions then return end
    local ok, iter, state, init = pcall(desc.EnumerateElementDescriptions, desc)
    if not ok or not iter then return end
    for _, elem in iter, state, init do
        if type(elem) == "table" then
            local hasKids = elem.HasElements and select(2, pcall(elem.HasElements, elem))
            if hasKids and elem.AddMenuAcquiredCallback and not elem.__muiHooked then
                elem.__muiHooked = true
                pcall(elem.AddMenuAcquiredCallback, elem, function(m) styleMenu(m) end)
            end
            hookSubmenus(elem, depth + 1)
        end
    end
end

local function skinMenus()
    -- Newer menu system (MenuUtil / Menu manager).
    if Menu and Menu.GetManager then
        local mgr = Menu.GetManager()
        if mgr then
            local function onOpen(manager, _, desc)
                local ok, menu = pcall(manager.GetOpenMenu, manager)
                if ok and menu then styleMenu(menu) end
                if desc and desc.AddMenuAcquiredCallback then
                    pcall(desc.AddMenuAcquiredCallback, desc, function(m) styleMenu(m) end)
                end
                pcall(hookSubmenus, desc, 0)
                watchMenus()
            end
            for _, fn in ipairs({ "OpenMenu", "OpenContextMenu" }) do
                if mgr[fn] then hooksecurefunc(mgr, fn, onOpen) end
            end
        end
    end
    -- Old-style dropdown lists: per-row touches each time a list opens.
    local function chevron(holder)
        if holder.__muiChev then return end
        for _, r in ipairs({ holder:GetRegions() }) do if r:IsObjectType("Texture") then fade(r) end end
        if holder.GetNormalTexture then fade(holder:GetNormalTexture()) end
        local lines = {}
        for k, p in ipairs({ { -2, 4, 2, 0 }, { 2, 0, -2, -4 } }) do
            local l = holder:CreateLine(nil, "OVERLAY")
            l:SetThickness(1.5)
            l:SetColorTexture(unpack(T.textDim))
            l:SetStartPoint("CENTER", holder, p[1], p[2])
            l:SetEndPoint("CENTER", holder, p[3], p[4])
            lines[k] = l
        end
        holder.__muiChev = lines
    end
    local function styleRows(list)
        local name = list:GetName()
        local n = list.numButtons or _G.UIDROPDOWNMENU_MAXBUTTONS or 32
        for j = 1, n do
            local b = _G[name .. "Button" .. j]
            if not b then break end
            if b:IsShown() then
                -- Section headers: dim bold labels instead of gold.
                local fs = _G[b:GetName() .. "NormalText"] or (b.GetFontString and b:GetFontString())
                if fs then
                    local r, g, bl = fs:GetTextColor()
                    if r and r > 0.85 and g > 0.6 and g < 0.9 and bl < 0.35 then
                        local _, size = fs:GetFont()
                        pcall(fs.SetFont, fs, T.fontBold, size or 11, "")
                        fs:SetTextColor(unpack(T.textDim))
                    end
                end
                -- Hover: a soft accent wash instead of Blizzard's glow.
                local hl = _G[b:GetName() .. "Highlight"] or b.Highlight
                if hl and hl.SetColorTexture then hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.16) end
                -- Check marks / radio dots in the accent; empty ones dim.
                local check = _G[b:GetName() .. "Check"] or b.Check
                if check then check:SetVertexColor(unpack(T.accent)) end
                local uncheck = _G[b:GetName() .. "UnCheck"] or b.UnCheck
                if uncheck then uncheck:SetVertexColor(0.45, 0.45, 0.5) end
                -- Submenu arrows: drawn chevrons.
                local arrow = _G[b:GetName() .. "ExpandArrow"] or b.ExpandArrow
                if arrow then chevron(arrow) end
            end
        end
    end
    for i = 1, (_G.UIDROPDOWNMENU_MAXLEVELS or 3) do
        local l = _G["DropDownList" .. i]
        if l then
            -- Backdrop frames hold only art; fade their textures, not the frames.
            for _, b in ipairs({ _G["DropDownList" .. i .. "Backdrop"], _G["DropDownList" .. i .. "MenuBackdrop"] }) do
                if b then
                    for _, r in ipairs({ b:GetRegions() }) do if r:IsObjectType("Texture") then fade(r) end end
                    if b.NineSlice then fade(b.NineSlice) end
                end
            end
            fadeArt(l)
            menuCard(l)
            l:HookScript("OnShow", function(self)
                pcall(themeFonts, self, 0)
                pcall(styleRows, self)
            end)
        end
    end
end

-- Large art textures (parchment, classic panel corners) directly on a frame
-- and its direct children: anything bigger than 100x100 that isn't an icon.
local function stripBigArt(f, depth)
    if not f or depth > 1 then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") and r:GetWidth() > 100 and r:GetHeight() > 100 then fade(r) end
    end
    for _, c in ipairs({ f:GetChildren() }) do
        if not c:IsObjectType("Button") then stripBigArt(c, depth + 1) end
    end
end

-- ── Deep pass for big Blizzard windows ────────────────────────────────────
-- Walks the whole window and restyles the common building blocks wherever
-- they appear: inset panels, ornate art, scroll bars, edit boxes, dropdowns,
-- check boxes, side tabs, gold text. Idempotent (flags per object), run on
-- show and once a second while shown, because content is pooled and built
-- lazily. Our own frames carry __muiOurs and are skipped.
local GOLD_ATLAS = { "filigree", "corner", "ornament", "parchment", "divider", "edge", "-bg", "background",
                     "border", "frame" }
local function isOrnateAtlas(a)
    if type(a) ~= "string" or a == "" then return false end
    a = a:lower()
    if a:find("icon") or a:find("portrait") then return false end
    for _, k in ipairs(GOLD_ATLAS) do if a:find(k, 1, true) then return true end end
    return false
end

local function ours(f) f.__muiOurs = true; return f end

-- A quiet card behind an inset panel. Blizzard's inset borders are often
-- separate frames layered ABOVE their content (the guild member list's
-- InsetFrame sits at level 100, the rows at 3-5; its middle is see-through).
-- So the card is a frame of ours under the inset's parent, at the parent's
-- own level (below the content), covering the inset's bounds.
local function card(f, r, g, b, a)
    if f.__muiCard then return end
    f.__muiCard = true
    local parent = f:GetParent() or f
    local h = ours(CreateFrame("Frame", nil, parent))
    h:SetAllPoints(f)
    h:SetFrameLevel(parent:GetFrameLevel())
    ns.RoundedRect(h, -8, 0, 8, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(h, -7, 1, 7, r or 0.09, g or 0.09, b or 0.105, a or 0.9)
    -- Follow the inset's visibility (pages share one window).
    h:SetShown(f:IsShown())
    hooksecurefunc(f, "Show", function() h:Show() end)
    hooksecurefunc(f, "Hide", function() h:Hide() end)
    hooksecurefunc(f, "SetShown", function(_, v) h:SetShown(v) end)
end

local function fadeRegions(f, except)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= except then fade(r) end
    end
end

-- Small stock controls we keep but drain of colour (scroll arrows and
-- thumbs, collapse toggles, dropdown arrows, rotate buttons). Their art is
-- swapped on every hover / press / state change, which brings the gold
-- back, so the grey is re-applied on those moments (and by the deep pass).
local GREY = { 0.62, 0.62, 0.67 }
local function greyNow(b)
    local regs, n = ns.Regs(b, 12) -- its own buffer: the deep pass uses 0-9
    for i = 1, n do
        local r = regs[i]
        if r:IsObjectType("Texture") and not r.__muiFaded then
            local c = r.__muiTint or GREY
            r:SetDesaturated(true)
            r:SetVertexColor(c[1], c[2], c[3])
        end
    end
end
local function greySoon(self)
    greyNow(self)
    C_Timer.After(0, function() greyNow(self) end)
end
local function keepGrey(b)
    if not b or b.__muiGrey or not b.GetRegions then return end
    b.__muiGrey = true
    greyNow(b)
    for _, ev in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnShow", "OnEnable", "OnDisable" }) do
        pcall(b.HookScript, b, ev, greySoon)
    end
end
-- Atlas families that mark such a control.
local GREY_ATLAS = { "common-dropdown", "questcollapse", "redbutton-", "campaign_headericon", "transmog-nav-slot",
                     "minimal-scrollbar" }
local GREY_KEYS = { "RotateLeftButton", "RotateRightButton", "RightPaneToggleButton", "ToggleCollapseButton" }
local function isGreyAtlas(a)
    if type(a) ~= "string" then return false end
    a = a:lower()
    for i = 1, #GREY_ATLAS do if a:find(GREY_ATLAS[i], 1, true) then return true end end
    return false
end

local function deepScrollBar(f)
    if f.__muiDeepSB then return true end
    -- Modern scroll bar: Track / Thumb / Back / Forward.
    local thumb = f.Thumb or (f.Track and f.Track.Thumb)
    if f.Track and thumb and (f.Back or f.Forward) then
        f.__muiDeepSB = true
        fadeRegions(f.Track)
        -- Recolor, never replace: Blizzard's scroll bar reads the thumb's
        -- atlas back (GetAtlasInfo) and errors without one, which aborts
        -- the list update it's part of (empty guild roster).
        keepGrey(f.Back); keepGrey(f.Forward); keepGrey(thumb)
        return true
    end
    -- Classic slider scroll bar: up / down buttons and a thumb texture.
    local name = f.GetName and f:GetName()
    local up = f.ScrollUpButton or (name and _G[name .. "ScrollUpButton"])
    local down = f.ScrollDownButton or (name and _G[name .. "ScrollDownButton"])
    if f:IsObjectType("Slider") and (up or down) then
        f.__muiDeepSB = true
        local thumb = f:GetThumbTexture()
        fadeRegions(f, thumb)
        for _, b in ipairs({ up, down }) do if b then fadeRegions(b) end end
        if thumb then thumb:SetDesaturated(true); thumb:SetVertexColor(0.55, 0.55, 0.6) end
        return true
    end
end

local function deepEditBox(f)
    if f.__muiDeepEB or not f:IsObjectType("EditBox") then return end
    local name = f:GetName()
    local l = f.Left or (name and _G[name .. "Left"])
    local m = f.Middle or f.Mid or (name and (_G[name .. "Middle"] or _G[name .. "Mid"]))
    local r = f.Right or (name and _G[name .. "Right"])
    if not (l or m or r) then return end
    f.__muiDeepEB = true
    fade(l); fade(m); fade(r)
    for _, k in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom" }) do fade(f[k]) end
    local h = ours(CreateFrame("Frame", nil, f))
    if not f:IsMultiLine() and f:GetHeight() > 30 then
        -- A single-line box in a tall frame (guild chat; its art spans the
        -- whole frame): a normal-height field, centered on the text line.
        -- (Guild chat's box hangs 4px past the chat panel each side.)
        h:SetPoint("LEFT", f, "LEFT", 1, 9); h:SetPoint("RIGHT", f, "RIGHT", -1, 9)
        h:SetHeight(24)
        -- Raise the typed text with the field: text centers between the
        -- insets, so 18 more at the bottom lifts it 9.
        local il, ir, it, ib = f:GetTextInsets()
        f:SetTextInsets((il or 0) + 6, (ir or 0) + 6, it or 0, (ib or 0) + 18)
    elseif l and r and l:GetNumPoints() > 0 and r:GetNumPoints() > 0 then
        -- Blizzard's art marks where the field really is.
        h:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0); h:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    else
        h:SetPoint("TOPLEFT", -6, 2); h:SetPoint("BOTTOMRIGHT", 2, -2)
    end
    h:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    local ring = ns.RoundedRect(h, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(h, -7, 1, 6, 0.05, 0.05, 0.06, 1)
    f:HookScript("OnEditFocusGained", function() ring(unpack(T.accent)) end)
    f:HookScript("OnEditFocusLost", function() ring(T.border[1], T.border[2], T.border[3], 1) end)
end

local function deepDropdown(f)
    if f.__muiDeepDD or not (f.Arrow and f.Text and f:IsObjectType("Button")) then return end
    f.__muiDeepDD = true
    fade(f.Background)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do fade(f[k]) end
    if f.Arrow.SetDesaturated then f.Arrow:SetDesaturated(true); f.Arrow:SetVertexColor(0.7, 0.7, 0.75) end
    local h = ours(CreateFrame("Frame", nil, f))
    h:SetAllPoints()
    h:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    local paint = ns.RoundedRect(h, -6, 0, math.floor(math.max(f:GetHeight(), 16) / 2), 0.17, 0.17, 0.20, 1)
    f:HookScript("OnEnter", function() paint(0.24, 0.24, 0.28, 1) end)
    f:HookScript("OnLeave", function() paint(0.17, 0.17, 0.20, 1) end)
end

-- Square side tabs with an icon (guild chat / roster, collections pages).
local function deepSideTab(f)
    if f.__muiDeepTab or not (f.Icon and f.Icon.IsObjectType and f.Icon:IsObjectType("Texture")) then return end
    local w, h = f:GetWidth(), f:GetHeight()
    if not (w >= 26 and w <= 64 and h >= 26 and h <= 64) then return end
    f.__muiDeepTab = true
    fadeRegions(f, f.Icon)
    if f.GetCheckedTexture then fade(f:GetCheckedTexture()) end
    f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local holder = ours(CreateFrame("Frame", nil, f))
    holder:SetAllPoints(f.Icon)
    holder:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    f.__muiTabRing = ns.RoundedRect(holder, -8, -3, 8, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(holder, -7, -2, 7, 0.06, 0.06, 0.07, 1)
end

local function deepCheck(f)
    if f.__muiDeepCB or not f:IsObjectType("CheckButton") or f.Icon then return end
    local w = f:GetWidth()
    if not (w >= 12 and w <= 34) then return end
    f.__muiDeepCB = true
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if f[get] then fade(f[get](f)) end
    end
    local ck = f:GetCheckedTexture()
    if ck then ck:SetDesaturated(true); ck:SetVertexColor(unpack(T.accent)) end
    local h = ours(CreateFrame("Frame", nil, f))
    h:SetPoint("TOPLEFT", 4, -4); h:SetPoint("BOTTOMRIGHT", -4, 4)
    h:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    ns.RoundedRect(h, -8, 0, 4, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(h, -7, 1, 3, 0.05, 0.05, 0.06, 1)
end

-- Counters drawn as a bar with an ornate frame ("Total Mounts 2"): the
-- frame goes, the fill goes flat and quiet, a dark rounded track sits behind.
local function deepBar(f)
    local w, h = f:GetWidth(), f:GetHeight()
    if not (w and h) or issecretvalue(w) or issecretvalue(h) or w < 1 or h < 1 then return end -- not laid out yet
    f.__muiDeepBar = true
    if not (w > 60 and h >= 8 and h <= 30) then return end
    local fill = f:GetStatusBarTexture()
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= fill then fade(r) end
    end
    for _, k in ipairs({ "border", "Border", "Background", "BG", "bg", "BorderMid", "BorderLeft", "BorderRight" }) do
        local o = f[k]
        if o and o ~= f and o.SetAlpha then fade(o) end
    end
    if fill then
        fill:SetTexture(T.bar)
        fill:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.55)
    end
    local back = ours(CreateFrame("Frame", nil, f))
    back:SetPoint("TOPLEFT", -2, 2); back:SetPoint("BOTTOMRIGHT", 2, -2)
    back:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    ns.RoundedRect(back, -8, 0, 6, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(back, -7, 1, 5, 0.06, 0.06, 0.07, 1)
end

-- List rows and section headers drawn as a bar of art (brown header bars
-- with a gold rim, the red-tinted mount / pet rows): the art goes and a
-- rounded plate of ours takes its place. A row's "selected" overlay becomes
-- a rounded accent wash, and its icon gets rounded corners.
local ROUND_TGA = "Interface/AddOns/Meniscus/Media/rounded.tga"
local SELECT_KEYS = { "selectedTexture", "SelectedTexture", "Selected", "selected", "SelectedHighlight", "SelectedBar" }
local ICON_KEYS = { "icon", "Icon", "IconTexture", "iconTexture" }

local function roundIcon(f)
    f.__muiIconDone = true
    for i = 1, #ICON_KEYS do
        local ic = rawget(f, ICON_KEYS[i])
        if ic and not ic.__muiRound and ic.IsObjectType and ic:IsObjectType("Texture") and ic.AddMaskTexture then
            local w, h = ic:GetWidth(), ic:GetHeight()
            -- Not laid out yet: look again on a later pass.
            if not (w and h) or issecretvalue(w) or issecretvalue(h) or w < 1 then f.__muiIconDone = nil end
            if w and h and not issecretvalue(w) and not issecretvalue(h) and w >= 18 and w <= 110
                    and h >= 18 and math.abs(w - h) <= 4 then
                ic.__muiRound = true
                local m = f:CreateMaskTexture()
                m:SetTexture(ROUND_TGA, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(ic)
                ic:AddMaskTexture(m)
                -- Its square hover glow follows the same shape.
                local hl = rawget(f, "HighlightTexture") or (f.GetHighlightTexture and f:GetHighlightTexture())
                if hl and hl.AddMaskTexture and not hl.__muiRound then
                    hl.__muiRound = true
                    hl:SetColorTexture(1, 1, 1, 0.12)
                    hl:ClearAllPoints(); hl:SetAllPoints(ic)
                    hl:AddMaskTexture(m)
                end
            end
        end
    end
end

local function deepRow(f)
    local w, h = f:GetWidth(), f:GetHeight()
    if not (w and h) or issecretvalue(w) or issecretvalue(h) or w < 1 or h < 1 then return end -- not laid out yet
    f.__muiRow = true
    if w < 150 or h < 14 or h > 64 then return end
    local sel = {}
    for i = 1, #SELECT_KEYS do
        local o = rawget(f, SELECT_KEYS[i])
        if o and o.IsObjectType and o:IsObjectType("Texture") then sel[o] = true end
    end
    local found = false
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local rw, rh = r:GetWidth(), r:GetHeight()
            if sel[r] then
                r:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.20)
                local m = f:CreateMaskTexture()
                m:SetTexture(ROUND_TGA, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(r)
                r:AddMaskTexture(m)
            elseif r:GetDrawLayer() ~= "HIGHLIGHT" and rw >= w * 0.8 and rh >= h * 0.6 then
                fade(r); found = true
            end
        end
    end
    if not found then return end
    if h <= 30 then
        -- A header: its small glyphs (the yellow minus / plus) go grey.
        for _, r in ipairs({ f:GetRegions() }) do
            if r:IsObjectType("Texture") and not r.__muiFaded and r:GetWidth() <= 24 and r:GetHeight() <= 24 then
                r:SetDesaturated(true); r:SetVertexColor(0.7, 0.7, 0.75)
            end
        end
    end
    local rad = math.min(8, h / 2)
    ns.RoundedRect(f, -8, 0, rad, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(f, -7, 1, rad - 1, 0.09, 0.09, 0.105, 1)
end

local function isGold(fs)
    local r, g, b = fs:GetTextColor()
    if type(r) ~= "number" or (issecretvalue and issecretvalue(r)) then return false end
    return r > 0.9 and g > 0.7 and g < 0.88 and b < 0.15
end

-- Theme font on Blizzard text, keeping its size and outline. Checked every
-- pass: Blizzard resets fonts when it reuses rows or switches pages.
local function themeFont(o)
    local ok, path, size, flags = pcall(o.GetFont, o)
    if not ok or type(size) ~= "number" or (issecretvalue and issecretvalue(size)) then return end
    if path == T.font or path == T.fontBold then return end
    pcall(o.SetFont, o, T.font, math.floor(size + 0.5), flags or "")
end

-- deepVisibleOnly: the once-a-second passes skip everything that's hidden
-- (most of a big window is hidden panels). The pass made when the window
-- opens walks all of it, so panels already built are styled before you
-- switch to them.
local deepVisibleOnly = false
local function deepSkin(f, depth)
    if depth > 9 or f.__muiOurs or (f.IsForbidden and f:IsForbidden()) then return end
    if deepVisibleOnly and depth > 0 and not f:IsShown() then return end
    local isButton = f:IsObjectType("Button")
    if depth > 0 and not f.__muiDeepArt then
        f.__muiDeepArt = true
        -- Inset panels: their ornate border goes, a quiet card replaces it.
        local inset = f.NineSlice and f.NineSlice ~= f
        if inset then fade(f.NineSlice) end
        for _, k in ipairs({ "Bg", "Background", "InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft",
                             "InsetBorderRight", "InsetBorderTopLeft", "InsetBorderTopRight",
                             "InsetBorderBottomLeft", "InsetBorderBottomRight", "FilligreeOverlay", "Filigree" }) do
            local o = f[k]
            if o and o ~= f and o.IsObjectType and (o:IsObjectType("Texture") or k:find("Fili")) then fade(o) end
        end
        if inset and not isButton and f:GetWidth() > 100 and f:GetHeight() > 60 then card(f) end
    end
    if f:IsObjectType("EditBox") then themeFont(f) end
    if depth > 0 and not f.__muiDeepBar and f:IsObjectType("StatusBar") then pcall(deepBar, f) end
    -- Previous / next page: our round chevrons.
    if not f.__muiPaging and f.PrevPageButton and f.NextPageButton then
        f.__muiPaging = true
        pcall(arrowButton, f.PrevPageButton, -1)
        pcall(arrowButton, f.NextPageButton, 1)
    end
    if f.__muiGrey then greyNow(f) end
    if depth > 0 and not f.__muiGreyKeys then
        f.__muiGreyKeys = true
        for i = 1, #GREY_KEYS do
            local b = rawget(f, GREY_KEYS[i])
            if b and b.IsObjectType and b:IsObjectType("Button") then keepGrey(b) end
        end
        -- Appearance tiles: a model on a black square. The square goes and a
        -- rounded card takes its place.
        if f.Border and f:IsObjectType("DressUpModel") then
            for _, r in ipairs({ f:GetRegions() }) do
                if r:IsObjectType("Texture") and r:GetDrawLayer() == "BACKGROUND" and not r:GetAtlas() then fade(r) end
            end
            ns.RoundedRect(f, -8, -3, 8, T.border[1], T.border[2], T.border[3], 1)
            ns.RoundedRect(f, -7, -2, 7, 0.085, 0.085, 0.10, 1)
        end
    end
    if depth > 0 then
        if not f.__muiIconDone then pcall(roundIcon, f) end
        if isButton and not f.__muiRow and not f.__muiSkin and not f.__muiDeepDD and not f.__muiDeepTab
                and not (f.Arrow and f.Text) then
            pcall(deepRow, f)
        end
    end
    if not deepScrollBar(f) then
        deepEditBox(f)
        deepDropdown(f)
        deepSideTab(f)
        deepCheck(f)
        if isButton and not f.__muiSkin and (f.Left or f.Middle) and f.GetFontString and f:GetFontString() then
            ns.SkinButton(f)
        end
    end
    if f.__muiTabRing and f.GetChecked then
        if f:GetChecked() then f.__muiTabRing(unpack(T.accent)) else f.__muiTabRing(T.border[1], T.border[2], T.border[3], 1) end
    end
    local regs, nr = ns.Regs(f, depth)
    for ri = 1, nr do
        local r = regs[ri]
        if r:IsObjectType("Texture") then
            if not r.__muiDeepSeen then
                r.__muiDeepSeen = true
                local a = r.GetAtlas and r:GetAtlas()
                if isButton and not f.__muiGrey and not f.__muiSkin and isGreyAtlas(a) then
                    -- The selected ring of a slot picker keeps a colour: ours.
                    local sel = rawget(f, "SelectedTexture")
                    if sel and sel.IsObjectType then sel.__muiTint = T.accent end
                    keepGrey(f)
                elseif isOrnateAtlas(a) then
                    fade(r)
                elseif not isButton and r:GetWidth() > 100 and r:GetHeight() > 100 then
                    fade(r)  -- panel art (parchment, painted backgrounds)
                elseif isButton and not a and not f.__muiSkin and r:GetDrawLayer() == "HIGHLIGHT"
                        and r:GetWidth() > 60 and r:GetHeight() > 8 and r:GetHeight() <= 32 then
                    -- List-row hover / selection bar (gold in Blizzard's art;
                    -- a selected guild member locks it on): a flat accent wash.
                    r:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
                end
            end
        elseif r:IsObjectType("FontString") then
            themeFont(r)
            if isGold(r) then r:SetTextColor(unpack(T.text)) end
        end
    end
    local kids, nk = ns.Kids(f, depth)
    for ci = 1, nk do deepSkin(kids[ci], depth + 1) end
end

local function deepDriver(f, name)
    local d = ours(CreateFrame("Frame", nil, f))
    d:SetSize(1, 1)
    d:SetPoint("TOPLEFT")
    local acc, errShown = 1, false
    local soon = 0 -- extra quick passes still owed after a click
    local calm = 0 -- seconds since the window was shown or clicked
    local function run(all)
        deepVisibleOnly = not all
        local ok, err = ns.Timed(all and ("deep:" .. name .. " (full)") or ("deep:" .. name), pcall, deepSkin, f, 0)
        deepVisibleOnly = false
        if not ok and not errShown then errShown = true; ns:Print("Skin " .. name .. ": " .. tostring(err)) end
    end
    d:SetScript("OnShow", function() acc, calm = 0, 0; run(true) end)
    d:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if soon > 0 then
            -- A click in the window (tab, page, filter) usually reveals new
            -- content: restyle on the next frame and once more shortly after.
            if soon == 2 or acc >= 0.25 then soon = soon - 1; acc = 0; run() end
            return
        end
        -- Once a second while the window is fresh; every 3 s after it has
        -- sat untouched for a while (a click brings the quick passes back).
        calm = calm + dt
        if acc < (calm > 6 and 3 or 1) then return end
        acc = 0
        run()
    end)
    if pcall(d.RegisterEvent, d, "GLOBAL_MOUSE_UP") then
        d:SetScript("OnEvent", function() if f:IsVisible() and f:IsMouseOver() then soon, calm = 2, 0 end end)
    end
end

-- name = options (strip: fade BACKGROUND/BORDER on the frame, big: fade
-- large classic panel art too, deep: the deep pass above).
local OTHERS = {
    MailFrame = {}, FriendsFrame = {}, DressUpFrame = {}, TaxiFrame = {}, FlightMapFrame = {}, BankFrame = {},
    CommunitiesFrame = { strip = true, deep = true, b = -14 },     -- guild & communities
    LFGParentFrame = { strip = true, big = true, deep = true },    -- group finder (classic layout)
    CollectionsJournal = { strip = true, deep = true },
    PlayerSpellsFrame = {},                                        -- talents (the spellbook tab is ours)
    SocialUIFrame = { strip = true, deep = true },                 -- friends / ignore / recent allies / raid
    -- Blizzard's character window. Our own replaces its gear, pet,
    -- reputation, skills tabs; the ones it still shows itself on Forever
    -- (PvP, currency, statistics) get the generic treatment.
    CharacterFrame = { strip = true, big = true, deep = true },
}
local function skinOthers()
    for n, opts in pairs(OTHERS) do
        local f = _G[n]
        if f and not f.__muiSkin then
            local ok, err = pcall(function()
                if opts.big then stripBigArt(f, 0) end
                -- Portrait medallions hanging off the top-left corner.
                for _, k in ipairs({ "PortraitOverlay", "PortraitContainer", "PortraitFrame", "portrait" }) do
                    if opts.deep and f[k] then fade(f[k]) end
                end
                ns.SkinWindow(f, opts)
                skinButtonsIn(f)
                if opts.deep then
                    if f.__muiHolder then ours(f.__muiHolder) end
                    -- Red maximize / minimize toggle: grey glyph.
                    local mm = f.MaximizeMinimizeFrame
                    if mm then
                        for _, b in ipairs({ mm:GetChildren() }) do
                            for _, r in ipairs({ b:GetRegions() }) do
                                if r:IsObjectType("Texture") then r:SetDesaturated(true); r:SetVertexColor(0.7, 0.7, 0.75) end
                            end
                        end
                    end
                    -- Guild & communities list: ornate frame, filigree and
                    -- painted backdrop, all as plain textures. Everything
                    -- that isn't a button (the entries) goes; a card replaces it.
                    local list = f.CommunitiesList
                    if list then
                        local function strip(x, d)
                            for _, r in ipairs({ x:GetRegions() }) do
                                if r:IsObjectType("Texture") then fade(r) end
                            end
                            if d >= 2 then return end
                            for _, c in ipairs({ x:GetChildren() }) do
                                if not c:IsObjectType("Button") and not c.ScrollTarget and not c.__muiOurs then
                                    strip(c, d + 1)
                                end
                            end
                        end
                        strip(list, 0)
                        card(list)
                    end
                    -- Pop-out panels hanging off the window (guild member
                    -- details): a full window card each, so nothing behind
                    -- shows through, and our close button.
                    for _, k in ipairs({ "GuildMemberDetailFrame" }) do
                        local pop = f[k]
                        if pop and not pop.__muiSkin then
                            ns.SkinWindow(pop)
                            if pop.__muiHolder then ours(pop.__muiHolder) end
                        end
                    end
                    deepDriver(f, n)
                end
            end)
            if not ok then ns:Print("Skin " .. n .. ": " .. tostring(err)) end
        end
    end
end

-- ── World map and quest log ───────────────────────────────────────────────
-- The map window keeps its frame art on a BorderFrame child (which is why
-- the plain window skin left it gold), has a breadcrumb bar drawn as red
-- arrow tabs, and carries the quest log as a side panel. The frame art
-- goes, the breadcrumbs become plain text, and the rest of the window gets
-- the generic deep pass. The map canvas itself is fenced off from that pass
-- (it holds hundreds of pins and the zone lettering, which must not be
-- restyled or walked every second).
local function deepMap()
    local wm = _G.WorldMapFrame
    if not wm or wm.__muiDeepMap then return end
    wm.__muiDeepMap = true
    if wm.ScrollContainer then ours(wm.ScrollContainer) end
    local bf = wm.BorderFrame
    if bf then
        fade(bf.NineSlice)
        fade(bf.PortraitContainer)
        fade(bf.Bg)
        fadeRegions(bf)
        if bf.TitleContainer then fadeRegions(bf.TitleContainer) end
        local mm = bf.MaxMinButtonFrame
        if mm then
            for _, b in ipairs({ mm:GetChildren() }) do keepGrey(b) end
        end
    end
    -- Painted backdrops of the quest log side (not the map canvas).
    for _, k in ipairs({ "QuestLog", "SidePanelToggle" }) do
        if wm[k] then stripBigArt(wm[k], 0) end
    end
    if _G.QuestMapFrame and _G.QuestMapFrame ~= wm.QuestLog then stripBigArt(_G.QuestMapFrame, 0) end
    if wm.__muiHolder then ours(wm.__muiHolder) end

    -- Breadcrumbs: every button's art goes (they are created as you move
    -- between maps, so this is repeated while the window is open).
    local nb = wm.NavBar
    local crumbCount = -1
    local function crumbs()
        if not nb then return end
        local n = nb:GetNumChildren()
        if n == crumbCount then return end
        crumbCount = n
        fadeRegions(nb)
        if nb.overlay then fadeRegions(nb.overlay) end
        for _, b in ipairs({ nb:GetChildren() }) do
            if b:IsObjectType("Button") and not b.__muiCrumb then
                b.__muiCrumb = true
                for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                    if b[get] then fade(b[get](b)) end
                end
                fadeRegions(b)
                local fs = b.GetFontString and b:GetFontString() or b.text
                if fs and fs.SetTextColor then
                    local _, size = fs:GetFont()
                    ns:SetFont(fs, size or 12, "", true)
                    fs:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
                    b:HookScript("OnEnter", function() fs:SetTextColor(T.text[1], T.text[2], T.text[3]) end)
                    b:HookScript("OnLeave", function() fs:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3]) end)
                end
                -- The little dropdown arrow beside a crumb: grey.
                local arrow = b.MenuArrowButton
                if arrow then
                    for _, r in ipairs({ arrow:GetRegions() }) do
                        if r:IsObjectType("Texture") then r:SetDesaturated(true); r:SetVertexColor(0.7, 0.7, 0.75) end
                    end
                end
            end
        end
    end
    -- The client's own "Player: x, y" line duplicates our coordinates chip:
    -- found by its text (a few tries after the map opens), then hidden.
    local tries, coordGone = 0, not (S.db and S.db.coords)
    local function findCoords(f, d)
        for _, r in ipairs({ f:GetRegions() }) do
            if r:IsObjectType("FontString") and not r.__muiOurs then
                local t = r:GetText()
                if type(t) == "string" and not issecretvalue(t) and t:find("^Player:%s*%d") then fade(r); coordGone = true end
            end
        end
        if d >= 2 then return end
        for _, c in ipairs({ f:GetChildren() }) do
            if c ~= wm.QuestLog and not (c.IsForbidden and c:IsForbidden()) and c:GetNumRegions() < 40 then findCoords(c, d + 1) end
        end
    end
    -- A quest's details beside the map: the game writes them in near-black
    -- for a parchment page, and with the parchment gone they can't be read.
    -- Any dark text in that pane becomes light (headings white, the rest
    -- our body colour), and the wooden banner behind "Rewards" goes. The
    -- game re-colours the text each time it shows a quest. So each piece of
    -- text gets a watch on its own colour: the moment it is set dark it is
    -- set light again, in the same frame, and nothing dark is ever drawn.
    -- The watches are put on when the map first opens (the pane's text
    -- exists before any quest is shown), and the slow tick catches any
    -- text created later.
    local function light(fs)
        local cr, cg, cb = fs:GetTextColor()
        if type(cr) ~= "number" or issecretvalue(cr) or (0.3 * cr + 0.59 * cg + 0.11 * cb) >= 0.4 then return end
        local _, size = fs:GetFont()
        if type(size) == "number" and size >= 15 then fs:SetTextColor(TITLE[1], TITLE[2], TITLE[3])
        else fs:SetTextColor(BODY[1], BODY[2], BODY[3]) end
        pcall(fs.SetShadowOffset, fs, 0, 0)
    end
    local function readable(f, d)
        local regs = ns.Regs(f, 13 + d)
        for i = 1, regs.n do
            local r = regs[i]
            if r:IsObjectType("FontString") then
                if not r.__muiQText then
                    r.__muiQText = true
                    hooksecurefunc(r, "SetTextColor", light)
                end
                light(r)
            elseif r:IsObjectType("Texture") and not r.__muiQArt then
                local w, h = r:GetWidth(), r:GetHeight()
                if type(w) == "number" and not issecretvalue(w) and w > 0 then
                    r.__muiQArt = true
                    if w > 180 and h >= 20 then fade(r) end -- banners and page art, not icons
                end
            end
        end
        if d >= 6 then return end
        local kids = ns.Kids(f, 13 + d)
        for i = 1, kids.n do
            local c = kids[i]
            if not (c.IsForbidden and c:IsForbidden()) then readable(c, d + 1) end
        end
    end
    -- (Shown or not: the point is to be there before the first showing.
    -- The quest text blocks live in QuestInfoFrame and are moved into the
    -- pane when a quest is displayed.)
    local function questPane()
        local q = _G.QuestMapFrame
        local df = q and q.DetailsFrame
        if df then readable(df, 0) end
        for _, name in ipairs({ "MapQuestInfoRewardsFrame", "QuestInfoFrame", "QuestInfoRewardsFrame" }) do
            local f = _G[name]
            if f and not (f.IsForbidden and f:IsForbidden()) then readable(f, 0) end
        end
    end
    -- The rewards block at the foot of that pane: on this client its
    -- holder comes out shorter than the block inside it (126 against 148
    -- for one item), so the last reward hangs down behind the Abandon /
    -- Share / Track buttons. The holder is given the block's height; it is
    -- pinned by its bottom, so it grows upward into the scrolling text.
    local fitting = false
    local function fitRewards()
        local q = _G.QuestMapFrame
        local c = q and q.DetailsFrame and q.DetailsFrame.RewardsFrameContainer
        local rf = c and c.RewardsFrame
        if not rf or fitting then return end
        if not c.__muiFit then
            c.__muiFit = true
            hooksecurefunc(c, "SetHeight", function() pcall(fitRewards) end)
            hooksecurefunc(rf, "SetHeight", function() pcall(fitRewards) end)
        end
        local ch, rh = c:GetHeight(), rf:GetHeight()
        if type(ch) == "number" and type(rh) == "number" and rh - ch > 1 then
            fitting = true
            c:SetHeight(rh)
            fitting = false
        end
        -- The scroll bar runs the whole height of the pane, but only the
        -- text above the rewards scrolls: it is cut to end where the
        -- rewards begin (and given its full height back when a quest has
        -- none).
        local df = q.DetailsFrame
        local bar = df.__muiBar
        if bar == nil then
            local sf = df.ScrollFrame
            bar = (sf and sf.ScrollBar) or df.ScrollBar or false
            if not bar then
                for _, k in ipairs({ df:GetChildren() }) do
                    if k.Track and (k.Back or k.Forward) then bar = k break end
                    for _, k2 in ipairs({ k:GetChildren() }) do
                        if k2.Track and (k2.Back or k2.Forward) then bar = k2 break end
                    end
                    if bar then break end
                end
            end
            df.__muiBar = bar
            if bar then
                bar.__muiPts = {}
                for i = 1, bar:GetNumPoints() do bar.__muiPts[i] = { bar:GetPoint(i) } end
            end
        end
        if bar and bar.__muiPts and #bar.__muiPts > 0 then
            local top, edge = bar:GetTop(), c:IsShown() and c:GetTop()
            local want = (top and edge) and "short" or "full"
            if want == "short" then
                local k = c:GetEffectiveScale() / bar:GetEffectiveScale()
                local h = top - edge * k - 4
                if h > 40 and (bar.__muiCut ~= "short" or math.abs((bar.__muiH or 0) - h) > 1) then
                    local p
                    for _, e in ipairs(bar.__muiPts) do
                        if type(e[1]) == "string" and e[1]:find("TOP") then p = e break end
                    end
                    if p then
                        bar.__muiCut, bar.__muiH = "short", h
                        bar:ClearAllPoints()
                        bar:SetPoint(p[1], p[2], p[3], p[4], p[5])
                        bar:SetHeight(h)
                    end
                end
            elseif bar.__muiCut == "short" then
                bar.__muiCut = "full"
                bar:ClearAllPoints()
                for _, e in ipairs(bar.__muiPts) do bar:SetPoint(e[1], e[2], e[3], e[4], e[5]) end
            end
        end
    end
    if _G.QuestInfo_Display then
        hooksecurefunc("QuestInfo_Display", function()
            if wm:IsShown() then pcall(questPane); pcall(fitRewards) end
        end)
    end
    pcall(questPane)
    pcall(fitRewards)

    local tick = ours(CreateFrame("Frame", nil, wm))
    tick:SetSize(1, 1)
    tick:SetPoint("TOPLEFT")
    local acc = 1
    tick:SetScript("OnShow", function() acc = 1 end)
    tick:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        pcall(crumbs)
        local qm = _G.QuestMapFrame
        if qm and qm.DetailsFrame and qm.DetailsFrame:IsVisible() then pcall(questPane); pcall(fitRewards) end
        if not coordGone and tries < 12 then tries = tries + 1; pcall(findCoords, wm, 0) end
    end)
    pcall(crumbs)
    deepDriver(wm, "WorldMapFrame")
end

-- ── Talents (PlayerSpellsFrame.TalentsFrame) ──────────────────────────────
-- The game's own talent window, restyled in place (its trees run on the
-- trait system: staged points, prerequisites, Apply Changes; none of that
-- is touched). What changes is the dressing:
--   frame     the brown page, gold inner frame, dividers, clouds and dust go;
--             the class painting stays as a faint tint behind the trees,
--             with a dark gutter between them and a hairline under the top
--             strip
--   talents   rounded icon in a hairline ring that carries the state the
--             game's gold / neon-green squares did (accent: can be learned,
--             amber: full, grey: not yet); no drop shadow or glow; the rank
--             in a small dark chip
--   the rest  tree headers and "Unspent Talents" in our font, the count in
--             a pill, search box and its filter button like the others
-- Talent buttons are pooled and made as the trees are laid out, so a slow
-- tick styles new ones while the window is open.
local function dim(o, a)
    if not o or not o.SetAlpha or o.__muiDim then return end
    o.__muiDim = true
    o:SetAlpha(a)
    hooksecurefunc(o, "SetAlpha", function(self, v) if type(v) == "number" and v > a + 0.001 then self:SetAlpha(a) end end)
end

local TALENT_FULL, TALENT_BAD, TALENT_SPENT = { 0.86, 0.72, 0.36 }, { 0.88, 0.36, 0.32 }, { 0.50, 0.50, 0.56 }
local function talentRing(atlas)
    if type(atlas) ~= "string" then return T.border end
    atlas = atlas:lower()
    if atlas:find("green", 1, true) then return T.accent end
    if atlas:find("yellow", 1, true) or atlas:find("gold", 1, true) then return TALENT_FULL end
    if atlas:find("red", 1, true) then return TALENT_BAD end
    if atlas:find("gray", 1, true) or atlas:find("grey", 1, true) then return TALENT_SPENT end
    return T.border
end

local function styleTalent(b)
    if b.__muiTalent then return end
    local sb, icon = rawget(b, "StateBorder"), rawget(b, "Icon")
    if not (sb and icon and sb.GetAtlas) then return end
    b.__muiTalent = true
    for _, k in ipairs({ "Shadow", "StateBorder", "StateBorderHover", "Glow", "SelectableGlow", "BorderSheen" }) do
        fade(rawget(b, k))
    end
    -- The ring: a rounded square just larger than the icon, behind it.
    local ring = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    ring:SetTexture(ROUND_TGA)
    ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    local over = false
    local function paint()
        local c = talentRing(sb:GetAtlas())
        if over then ring:SetVertexColor(math.min(1, c[1] + 0.22), math.min(1, c[2] + 0.22), math.min(1, c[3] + 0.22), 1)
        else ring:SetVertexColor(c[1], c[2], c[3], 1) end
    end
    hooksecurefunc(sb, "SetAtlas", paint)
    b:HookScript("OnEnter", function() over = true; paint() end)
    b:HookScript("OnLeave", function() over = false; paint() end)
    paint()
    pcall(roundIcon, b)
    local ov = rawget(b, "DisabledOverlay")
    if ov and ov.AddMaskTexture and not ov.__muiRound then
        ov.__muiRound = true
        local m = b:CreateMaskTexture()
        m:SetTexture(ROUND_TGA, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(icon)
        ov:AddMaskTexture(m)
    end
    -- Rank: our font on a small dark chip (the game stacks four offset
    -- copies of the number as an outline; those go).
    local st = rawget(b, "SpendText")
    if st and st.SetFont then
        for i = 1, 4 do fade(rawget(b, "SpendTextShadow" .. i)) end
        pcall(ns.SetFont, ns, st, 11, "", true)
        pcall(st.SetShadowOffset, st, 1, -1)
        pcall(st.SetShadowColor, st, 0, 0, 0, 0.9)
        local chip = b:CreateTexture(nil, "OVERLAY", nil, -1)
        chip:SetTexture("Interface/AddOns/Meniscus/Media/circle.tga") -- a round chip
        chip:SetVertexColor(0.05, 0.05, 0.06, 0.94)
        chip:SetSize(17, 17)
        chip:SetPoint("CENTER", st, "CENTER", 0, 0)
        -- The game sets the number right on the icon's bottom-right edge,
        -- where the disc hung out past the ring: both sit inside the corner.
        st:ClearAllPoints()
        st:SetPoint("CENTER", icon, "BOTTOMRIGHT", -8, 8)
        local busy = false
        local function sync()
            local t = st:GetText()
            chip:SetShown(type(t) == "string" and not issecretvalue(t) and t ~= "")
            if busy then return end
            -- The game's pure green becomes the accent.
            local r, g, bl = st:GetTextColor()
            if type(r) == "number" and not issecretvalue(r) and g > 0.9 and r < 0.4 and bl < 0.4 then
                busy = true
                st:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                busy = false
            end
        end
        hooksecurefunc(st, "SetText", sync)
        hooksecurefunc(st, "SetTextColor", sync)
        sync()
    end
end

-- Text and art of a small label frame (a tree's header, the unspent
-- count): our font, gold and neon green to our colours, frames and glows
-- gone, icons kept.
local function styleLabel(f, d)
    if not f or (f.IsForbidden and f:IsForbidden()) then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("FontString") then
            if not r.__muiTalentFont then
                r.__muiTalentFont = true
                local _, size = r:GetFont()
                pcall(ns.SetFont, ns, r, math.max(11, math.min(type(size) == "number" and size or 13, 17)), "", true)
                pcall(r.SetShadowOffset, r, 1, -1)
                local busy = false
                local function recolor()
                    if busy then return end
                    local cr, cg, cb = r:GetTextColor()
                    if type(cr) ~= "number" or issecretvalue(cr) then return end
                    busy = true
                    if cg > 0.9 and cr < 0.4 and cb < 0.4 then r:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                    elseif cr > 0.9 and cg > 0.65 and cg < 0.9 and cb < 0.3 then r:SetTextColor(T.text[1], T.text[2], T.text[3]) end
                    busy = false
                end
                hooksecurefunc(r, "SetTextColor", recolor)
                recolor()
            end
        elseif r:IsObjectType("Texture") and not r.__muiTalentArt then
            r.__muiTalentArt = true
            local a = r:GetAtlas()
            a = type(a) == "string" and a:lower() or ""
            if a ~= "" and not a:find("icon", 1, true)
                and (a:find("border", 1, true) or a:find("frame", 1, true) or a:find("ring", 1, true)
                     or a:find("glow", 1, true) or a:find("divider", 1, true) or a:find("line", 1, true)
                     or a:find("bg", 1, true) or a:find("background", 1, true) or a:find("shadow", 1, true)
                     or a:find("header", 1, true) or a:find("currency", 1, true)) then
                fade(r)
            end
        end
    end
    if d >= 2 then return end
    for _, c in ipairs({ f:GetChildren() }) do styleLabel(c, d + 1) end
end

-- A tree's header (icon, name, points spent): the icon rounded in a
-- hairline ring like the talents under it, the count on a small chip.
-- (Its gold ring, count box and underline are already gone.)
local function styleTreeHeader(c)
    local icon, text = rawget(c, "Icon"), rawget(c, "Text")
    if c.__muiHead or not (rawget(c, "MainRing") and icon) then return end
    c.__muiHead = true
    fade(c.MainRing); fade(rawget(c, "TextBackground")); fade(rawget(c, "Divider"))
    local ring = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    ring:SetTexture(ROUND_TGA)
    ring:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
    ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    local m = c:CreateMaskTexture()
    m:SetTexture(ROUND_TGA, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(icon)
    icon:AddMaskTexture(m)
    if text and text.SetFont then
        pcall(ns.SetFont, ns, text, 11, "", true)
        local chip = c:CreateTexture(nil, "OVERLAY", nil, -1)
        chip:SetTexture("Interface/AddOns/Meniscus/Media/circle.tga")
        chip:SetVertexColor(0.05, 0.05, 0.06, 0.94)
        chip:SetSize(18, 18)
        chip:SetPoint("CENTER", text, "CENTER", 0, 0)
        text:ClearAllPoints()
        text:SetPoint("CENTER", icon, "BOTTOMRIGHT", -8, 8)
    end
end

local function deepTalents()
    local psf = _G.PlayerSpellsFrame
    local tf = psf and psf.TalentsFrame
    if not tf or tf.__muiTalents then return end
    tf.__muiTalents = true
    fadeRegions(psf)
    for _, k in ipairs({ "Background", "OverlayBackgroundRight", "OverlayBackgroundMid", "Clouds1", "Clouds2",
                         "AirParticlesClose", "AirParticlesFar", "BackgroundBorder", "DividerHorizontalLeft",
                         "DividerHorizontalRight", "DividerVerticalLeft", "DividerVerticalRight" }) do
        fade(tf[k])
    end
    dim(tf.ClassBackground, 0.20)
    -- A hairline where each gold divider stood, between the trees, and one
    -- under the top strip (the faded art still marks the places).
    for _, k in ipairs({ "DividerVerticalLeft", "DividerVerticalRight" }) do
        local dv = tf[k]
        if dv then
            local g = tf:CreateTexture(nil, "BORDER", nil, 1)
            g:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
            g:SetWidth(1)
            g:SetPoint("TOP", dv, "TOP", 0, 0)
            g:SetPoint("BOTTOM", dv, "BOTTOM", 0, 0)
        end
    end
    local dl, dr = tf.DividerHorizontalLeft, tf.DividerHorizontalRight
    if dl and dr then
        local line = tf:CreateTexture(nil, "BORDER", nil, 1)
        line:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
        line:SetHeight(1)
        line:SetPoint("LEFT", dl, "LEFT", 6, 0)
        line:SetPoint("RIGHT", dr, "RIGHT", -6, 0)
    end

    -- Search: our field drawn on the box itself. (Its stock art sits
    -- higher than the text, so a field drawn where that art was came out
    -- above the words with the magnifier hanging outside.)
    local sbx = tf.SearchBox
    if sbx and not sbx.__muiDeepEB then
        sbx.__muiDeepEB = true
        for _, k in ipairs({ "Left", "Middle", "Mid", "Right" }) do fade(sbx[k]) end
        local h = ours(CreateFrame("Frame", nil, sbx))
        h:SetPoint("TOPLEFT", sbx, "TOPLEFT", -6, -3)
        h:SetPoint("BOTTOMRIGHT", sbx, "BOTTOMRIGHT", 0, 3)
        h:SetFrameLevel(math.max(sbx:GetFrameLevel() - 1, 0))
        local ring = ns.RoundedRect(h, -8, 0, 11, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(h, -7, 1, 10, 0.05, 0.05, 0.06, 1)
        sbx:HookScript("OnEditFocusGained", function() ring(unpack(T.accent)) end)
        sbx:HookScript("OnEditFocusLost", function() ring(T.border[1], T.border[2], T.border[3], 1) end)
        pcall(themeFont, sbx)
    end
    if tf.SearchOptionsDropdown then pcall(keepGrey, tf.SearchOptionsDropdown) end

    -- "Unspent Talents": the number sits in a pill.
    local cd = tf.ClassCurrencyDisplay
    local box = cd and cd.CurrentAmountContainer
    if cd then fade(cd.Border) end -- the brown plaque behind the label
    if box and not box.__muiPill then
        box.__muiPill = true
        fadeRegions(box)             -- the gold box, in nine pieces
        local pillHold = ours(CreateFrame("Frame", nil, box))
        pillHold:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -6)
        pillHold:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 6)
        pillHold:SetFrameLevel(math.max(box:GetFrameLevel() - 1, 0))
        ns.RoundedRect(pillHold, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(pillHold, -7, 1, 11, 0.05, 0.05, 0.06, 1)
    end

    -- One look at how the pieces we don't know yet are made, for the next
    -- round of tuning (tree headers, the unspent count).
    local seen = 0
    local function labels()
        pcall(styleLabel, cd, 0)
        for _, c in ipairs({ tf:GetChildren() }) do
            if c ~= tf.ButtonsParent and c ~= cd and not c:IsObjectType("Button") and not c:IsObjectType("EditBox")
                and not c:IsObjectType("ModelScene") then
                local w, h = c:GetWidth(), c:GetHeight()
                if type(w) == "number" and w >= 30 and w <= 400 and h >= 20 and h <= 120 then
                    pcall(styleLabel, c, 0)
                    pcall(styleTreeHeader, c)
                end
            end
        end
    end
    local function record()
        if not MinimalUIDB or MinimalUIDB.talentprobe2 then return end
        MinimalUIDB.talentprobe = nil
        local out = {}
        local function dump(f, key, d)
            if #out > 120 or d > 2 then return end
            out[#out + 1] = string.rep("  ", d) .. key .. " [" .. f:GetObjectType() .. "] "
                .. string.format("%.0fx%.0f", f:GetWidth(), f:GetHeight()) .. (f:IsShown() and "" or " hidden")
            local names = {}
            for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
            for _, r in ipairs({ f:GetRegions() }) do
                local line = string.rep("  ", d + 1) .. "- " .. (names[r] or "#") .. " <" .. r:GetObjectType() .. ">"
                if r:IsObjectType("Texture") then line = line .. " atlas=" .. tostring(r:GetAtlas()) .. " " .. tostring(r:GetDrawLayer())
                elseif r:IsObjectType("FontString") then
                    local t = r:GetText()
                    line = line .. ' "' .. ((type(t) == "string" and not issecretvalue(t)) and t:sub(1, 24) or "") .. '"'
                end
                out[#out + 1] = line .. string.format(" %.0fx%.0f a=%.2f", r:GetWidth(), r:GetHeight(), r:GetAlpha())
            end
            for _, c in ipairs({ f:GetChildren() }) do dump(c, names[c] or "#", d + 1) end
        end
        for _, c in ipairs({ tf:GetChildren() }) do
            local w = c:GetWidth()
            if c ~= tf.ButtonsParent and c ~= cd and type(w) == "number" and w > 40 and w < 60 then
                pcall(dump, c, "header?", 0)
                local n = c:GetNumPoints()
                for i = 1, n do
                    local p, rel, rp, x, y = c:GetPoint(i)
                    out[#out + 1] = string.format("    point %s > %s %s %.0f,%.0f", tostring(p),
                        tostring(rel and (rel.GetName and rel:GetName() or "?")), tostring(rp), x or 0, y or 0)
                end
            end
        end
        if tf.SearchBox then pcall(dump, tf.SearchBox, "SearchBox", 0) end
        MinimalUIDB.talentprobe2 = out
    end

    local bp = tf.ButtonsParent
    if bp then ours(bp) end -- the generic deep pass keeps out: these are styled here
    local count, acc = -1, 1
    local tick = ours(CreateFrame("Frame", nil, tf))
    tick:SetSize(1, 1)
    tick:SetPoint("TOPLEFT")
    tick:SetScript("OnShow", function() acc = 1 end)
    tick:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        if bp then
            local n = bp:GetNumChildren()
            if n ~= count then
                count = n
                local kids = ns.Kids(bp, 13)
                for i = 1, kids.n do
                    local b = kids[i]
                    if b:IsObjectType("Button") then pcall(styleTalent, b) end
                end
            end
        end
        if seen < 6 then
            seen = seen + 1
            pcall(labels)
            if seen == 3 then pcall(record) end
        end
    end)
end

-- ── Damage meter (Blizzard's built-in one) ────────────────────────────────
-- First pass, generic: its rows are pooled and appear as fights happen, so
-- a slow scan (twice a second, only while the meter is shown) styles
-- anything new. Window art (NineSlice / Background / Bg) is faded and the
-- window gets our card; bars get a flat fill; text gets the theme font.
local DM_ART = { "NineSlice", "Background", "Bg", "BackgroundTexture" }
-- Sizes in the meter can be secret values (combat data): read them only
-- when they're plain numbers.
local function dmSize(o)
    local ok, w, h = pcall(o.GetSize, o)
    if not ok or type(w) ~= "number" or type(h) ~= "number" then return end
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return end
    return w, h
end
local DM_ATLAS = { "header", "gradient", "bg", "background", "divider", "line", "gold", "border", "frame", "glow" }
local function dmOrnate(r)
    local a = r.GetAtlas and r:GetAtlas()
    if type(a) ~= "string" or a == "" or (issecretvalue and issecretvalue(a)) then return false end
    a = a:lower()
    if a:find("icon") or a:find("bar%-fill") or a:find("statusbar") then return false end
    for _, k in ipairs(DM_ATLAS) do if a:find(k, 1, true) then return true end end
    return false
end

local function dmCard(f)
    if ns.dmNoCard then return end -- seated in the console's wing (Bars.lua)
    if f.__muiDMCard then return end
    local holder = CreateFrame("Frame", nil, f)
    holder.__muiDMOurs = true
    holder:SetAllPoints()
    holder:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    ns.RoundedRect(holder, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(holder, -7, 1, 9, 0.06, 0.06, 0.07, 0.92)
    f.__muiDMCard = holder
end

local function dmButton(f)
    -- Small icon buttons (mode dropdown, settings gear, minimize): grey
    -- glyphs, brightening on hover. Only buttons with button art, so
    -- class / spec icons on the bars are left alone.
    if f.__muiDMBtn or not f:IsObjectType("Button") then return end
    local hasArt = (f.GetNormalTexture and f:GetNormalTexture()) or f.Arrow or f.Background or f.Icon
    if not hasArt or (f.GetFontString and f:GetFontString()) then return end
    local w, h = dmSize(f)
    if not w or w > 36 or h > 36 or w < 8 then return end
    f.__muiDMBtn = true
    -- Plain grey glyphs, brightening on hover (no backing disc).
    local hover = false
    local function rest()
        local v = hover and 0.95 or 0.7
        for _, r in ipairs({ f:GetRegions() }) do
            if r:IsObjectType("Texture") and r.SetDesaturated then
                r:SetDesaturated(true); r:SetVertexColor(v, v, v + 0.03)
            end
        end
    end
    rest()
    fade(f.GetHighlightTexture and f:GetHighlightTexture())
    f:HookScript("OnEnter", function() hover = true; rest() end)
    f:HookScript("OnLeave", function() hover = false; rest() end)
    -- Blizzard swaps the art on state changes (pressed, collapsed).
    f:HookScript("OnMouseUp", function() C_Timer.After(0, rest) end)
    f:HookScript("OnClick", function() C_Timer.After(0, rest) end)
    f.__muiDMRest = rest
end

local function dmStyle(f, depth)
    if depth > 9 or f.__muiDMOurs or (f.IsForbidden and f:IsForbidden()) then return end
    local isBar = f:IsObjectType("StatusBar")
    local isButton = f:IsObjectType("Button")
    if not f.__muiDMArt then
        f.__muiDMArt = true
        local faded = false
        for _, k in ipairs(DM_ART) do
            if f[k] and f[k] ~= f then fade(f[k]); faded = true end
        end
        -- Any texture filling (nearly) the whole frame is its backdrop.
        local fw, fh = dmSize(f)
        if fw and not isBar and not isButton and fw > 100 and fh > 40 then
            for _, r in ipairs({ f:GetRegions() }) do
                if r:IsObjectType("Texture") then
                    local w, h = dmSize(r)
                    if w and w >= fw - 24 and h >= fh - 24 then fade(r); faded = true end
                end
            end
            if faded then dmCard(f) end
        end
    end
    if isBar and not f.__muiDMBar then
        f.__muiDMBar = true
        local tex = f:GetStatusBarTexture()
        local layer = tex and tex:GetDrawLayer()
        pcall(f.SetStatusBarTexture, f, "Interface/Buttons/WHITE8x8")
        tex = f:GetStatusBarTexture()
        if tex and layer then pcall(tex.SetDrawLayer, tex, layer) end
    end
    dmButton(f)
    local regs, nr = ns.Regs(f, depth)
    for ri = 1, nr do
        local r = regs[ri]
        if r:IsObjectType("FontString") then
            if not r.__muiDMFont then
                r.__muiDMFont = true
                local _, size, flags = r:GetFont()
                if type(size) == "number" then pcall(ns.SetFont, ns, r, math.floor(size + 0.5), flags or "", false) end
            end
            -- Blizzard gold (titles, headers) -> our text color. Re-checked
            -- every pass, since Blizzard re-colors on updates.
            local cr, cg, cb = r:GetTextColor()
            if type(cr) == "number" and not (issecretvalue and issecretvalue(cr))
                and cr > 0.9 and cg > 0.65 and cg < 0.9 and cb < 0.25 then
                r:SetTextColor(unpack(T.text))
            end
        elseif not isBar and not f.__muiDMBtn and r:IsObjectType("Texture") and not r.__muiDMSeen then
            r.__muiDMSeen = true
            local w, h = dmSize(r)
            if w and h > 0 and h <= 4 and w > 60 then
                -- Thin divider line under the header.
                r:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
                r:SetHeight(1)
            elseif dmOrnate(r) then
                fade(r)  -- header glow / gradient band, gold frame bits
            end
        end
    end
    local kids, nk = ns.Kids(f, depth)
    for ci = 1, nk do
        local ok, err = pcall(dmStyle, kids[ci], depth + 1)
        if not ok and not S.dmErr then S.dmErr = true; ns:Print("Damage meter styling: " .. tostring(err)) end
    end
end

-- New rows appear as fights happen: scan twice a second in combat, every
-- 3 s otherwise, and right away when combat starts or ends.
-- After a login / reload (and whenever the meter is shown again) it is
-- styled on the very next frame, before it is first drawn, and then every
-- frame for a couple of seconds while it finishes building itself, so its
-- stock art is never seen.
local dmDriver = CreateFrame("Frame")
local dmAcc, dmBurst = 99, 2.5
dmDriver:RegisterEvent("PLAYER_REGEN_DISABLED")
dmDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
dmDriver:RegisterEvent("PLAYER_ENTERING_WORLD")
dmDriver:RegisterEvent("ADDON_LOADED")
dmDriver:SetScript("OnEvent", function(_, e)
    dmAcc = 99
    -- (Every addon that loads fires ADDON_LOADED; once the meter is hooked
    -- its own OnShow starts the burst.)
    local root = _G.DamageMeter
    if e == "PLAYER_ENTERING_WORLD" or (e == "ADDON_LOADED" and not (root and root.__muiDMShow)) then dmBurst = 2.5 end
end)
dmDriver:SetScript("OnUpdate", function(_, dt)
    dmAcc = dmAcc + dt
    if dmBurst > 0 then
        dmBurst = dmBurst - dt
    elseif dmAcc < (InCombatLockdown() and 0.5 or 3) then
        return
    end
    dmAcc = 0
    local root = _G.DamageMeter
    if not (S.db and S.db.enabled ~= false and S.db.damageMeter ~= false) then return end
    if root and not root.__muiDMShow then
        root.__muiDMShow = true
        root:HookScript("OnShow", function() dmAcc = 99; if dmBurst < 0.5 then dmBurst = 0.5 end end)
    end
    if root and root:IsShown() then
        local ok, err = ns.Timed("damage meter", pcall, dmStyle, root, 0)
        if not ok and not S.dmErr then S.dmErr = true; ns:Print("Damage meter styling: " .. tostring(err)) end
    end
end)

-- Some of these load on demand (flight map): skin them when they arrive.
local lod = CreateFrame("Frame")
lod:RegisterEvent("ADDON_LOADED")
lod:SetScript("OnEvent", function()
    if S.db and S.db.enabled ~= false then pcall(skinOthers); pcall(skinTabard); pcall(deepMap); pcall(deepTalents) end
end)

-- ── The game's Options window ─────────────────────────────────────────────
-- The frame only: card, title, close button, tabs, the two panes, search
-- box, scroll bars and the Close / Apply / Defaults buttons. The controls
-- inside each setting row (checkboxes, sliders, dropdowns, key bindings)
-- are left exactly as Blizzard draws them: they are recycled as the list
-- scrolls and feed the game's protected settings code. Alpha and color
-- only; nothing is moved, resized or replaced.
-- Off: /men blizzopts (or the switch in /men), then reload.
local function optCategoryRow(row)
    if row.__muiOpt then return end
    row.__muiOpt = true
    -- Section header ("Gameplay"): its ornate plate goes, the label stays.
    if row.Background and row.Background.GetAtlas then fade(row.Background) end
    -- Category button: the gold selected / hover bar becomes a grey one
    -- tinted with the accent (recolored, so the game's own show / hide and
    -- atlas swaps keep working).
    local bar = row.Texture
    if bar and bar.SetDesaturated then
        bar:SetDesaturated(true)
        bar:SetVertexColor(T.accent[1], T.accent[2], T.accent[3])
    end
end

local function optPane(P, f, l, t, r, b)
    local h = ours(CreateFrame("Frame", nil, P))
    h:SetPoint("TOPLEFT", f, "TOPLEFT", -l, t)
    h:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", r, -b)
    h:SetFrameLevel(P:GetFrameLevel())
    ns.RoundedRect(h, -8, 0, 8, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(h, -7, 1, 7, 0.09, 0.09, 0.105, 0.9)
end

local function optTab(tab)
    if not tab or tab.__muiOpt then return end
    tab.__muiOpt = true
    local line = tab:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, 3)
    line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 3)
    -- Which tab is selected is read off the game's own art (it swaps the
    -- tab's atlas), which stays in place, faded.
    local left = tab.Left
    local function refresh()
        local a = left and left.GetAtlas and left:GetAtlas()
        line:SetShown(type(a) == "string" and a:find("Active", 1, true) ~= nil)
    end
    refresh()
    if left then hooksecurefunc(left, "SetAtlas", refresh) end
    tab:HookScript("OnShow", refresh)
    fade(tab.Left); fade(tab.Middle); fade(tab.Right)
end

local function optBuild(P)
    if P.__muiSkin then return end
    P.__muiSkin = true
    -- Window card. (Not ns.SkinWindow: the title lives on the border frame,
    -- so the border's art is faded piece by piece and the frame is kept.)
    fade(P.Bg)
    if P.NineSlice then
        for _, r in ipairs({ P.NineSlice:GetRegions() }) do
            if r:IsObjectType("Texture") then fade(r) end
        end
        local title = P.NineSlice.Text
        if title then
            ns:SetFont(title, 13, "", true)
            title:SetTextColor(unpack(T.text))
        end
    end
    -- The gold inner frame around the two panes.
    for _, r in ipairs({ P:GetRegions() }) do
        if r:IsObjectType("Texture") then fade(r) end
    end
    local holder = ours(CreateFrame("Frame", nil, P))
    holder:SetAllPoints(P)
    holder:SetFrameLevel(math.max(P:GetFrameLevel() - 1, 0))
    ns.RoundedRect(holder, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(holder, -7, 1, 11, unpack(FILL))
    P.__muiHolder = holder

    skinClose(P.ClosePanelButton)
    optTab(P.GameTab); optTab(P.AddOnsTab)

    -- The two panes, each on a quiet card.
    local list, cont = P.CategoryList, P.Container
    if list then optPane(P, list, 6, 6, 4, 6) end
    if cont then optPane(P, cont, 4, 6, 6, 6) end

    -- Category list: rows are recycled, so each is settled once, the first
    -- time the list hands it out.
    local box = list and list.ScrollBox
    if box and box.ForEachFrame then
        local function rows() pcall(box.ForEachFrame, box, optCategoryRow) end
        hooksecurefunc(box, "Update", rows)
        rows()
    end
    if list and list.ScrollBar then pcall(deepScrollBar, list.ScrollBar) end

    local sl = cont and cont.SettingsList
    if sl then
        if sl.ScrollBar then pcall(deepScrollBar, sl.ScrollBar) end
        local head = sl.Header
        if head then
            if head.Title then
                ns:SetFont(head.Title, 18, "", true)
                head.Title:SetTextColor(unpack(T.text))
            end
            -- Gold divider under the page title: a hairline of ours.
            for _, r in ipairs({ head:GetRegions() }) do
                if r:IsObjectType("Texture") and r:GetAtlas() == "Options_HorizontalDivider" then
                    local hair = head:CreateTexture(nil, "ARTWORK")
                    hair:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
                    hair:SetAllPoints(r)
                    fade(r)
                end
            end
            ns.SkinButton(head.DefaultsButton)
        end
    end
    ns.SkinButton(P.CloseButton)
    ns.SkinButton(P.ApplyButton)
    if P.SearchBox then pcall(deepEditBox, P.SearchBox) end
end

local function skinOptions()
    if S.db and S.db.options == false then return end
    local waiting
    local function build()
        local P = _G.SettingsPanel
        if not P or P.__muiSkin then return end
        if InCombatLockdown() then
            if not waiting then
                waiting = CreateFrame("Frame")
                waiting:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    build()
                end)
            end
            waiting:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        local ok, err = pcall(optBuild, P)
        if not ok then ns:Print("Options skin: " .. tostring(err)) end
    end
    local function hook()
        local P = _G.SettingsPanel
        if not P then return false end
        if P.__muiOptHook then return true end
        P.__muiOptHook = true
        -- Built the first time the window is opened (its lists are filled
        -- by then), not at login.
        P:HookScript("OnShow", build)
        if P:IsShown() then build() end
        return true
    end
    if not hook() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("ADDON_LOADED")
        w:SetScript("OnEvent", function(self) if hook() then self:UnregisterAllEvents() end end)
    end
end

-- /men blizzopts : the game's Options window as Blizzard draws it (or back).
ns.commands = ns.commands or {}
ns.commands.blizzopts = function()
    local d = S.db
    if not d then return end
    d.options = d.options == false
    ns:Print("Options window skin " .. (d.options and "on" or "off") .. ". /reload to apply.")
end

-- ── Friends window (SocialUIFrame): a polish pass ─────────────────────────
-- Blizzard's window keeps doing the work; what the generic skin leaves
-- behind is put right here, by fading and tinting only (nothing Blizzard
-- reads back is replaced):
--   * names were cut off: Blizzard sizes the name to its own font, and ours
--     is wider. Each row's name is given the width its text needs.
--   * "Add New Friend" (and the same button on the other tabs) loses its
--     stretched red caps, leaving the pill the skin already draws.
--   * the side tabs lose their plate and glow; their gold icons go silver,
--     and the open tab has a small accent bar.
--   * the row buttons and the menu button lose their gold boxes for a
--     hairline rounded square, icons silver.
--   * the blue BattleTag bar becomes a hairline pill.
-- Rows are pooled and re-used by Blizzard, so they are gone over again a
-- couple of times a second while the window is open.
local function skinSocial()
    if S.db and S.db.social == false then return end
    local function secret(v) return issecretvalue and issecretvalue(v) end
    local function fade(t) if t and t.SetAlpha then t:SetAlpha(0) end end
    local function silver(t, k)
        if not (t and t.SetVertexColor) then return end
        if t.SetDesaturated then t:SetDesaturated(true) end
        k = k or 1
        t:SetVertexColor(0.80 * k, 0.83 * k, 0.90 * k)
    end
    local function flat(b, iconKey)
        if not b then return end
        if not b.__muiSoc then
            b.__muiSoc = true
            local w = b:GetWidth()
            local inset = w > 30 and 4 or 2
            ns.RoundedRect(b, -4, inset, 7, T.border[1], T.border[2], T.border[3], 1)
            ns.RoundedRect(b, -3, inset + 1, 6, 0.06, 0.06, 0.07, 0.97)
        end
        fade(b.GetNormalTexture and b:GetNormalTexture())
        fade(b.GetPushedTexture and b:GetPushedTexture())
        fade(b.GetHighlightTexture and b:GetHighlightTexture())
        silver(b[iconKey or "Icon"] or b.ActionIcon or b.Icon)
    end
    local function redCaps(b)
        if not b then return end
        local regs, n = ns.Regs(b, 7)
        for i = 1, n do
            local r = regs[i]
            if r.GetAtlas then
                local a = r:GetAtlas()
                if type(a) == "string" and not secret(a) and a:find("RedButton", 1, true) then r:SetAlpha(0) end
            end
        end
    end
    -- (Battle.net names are protected strings: their "unbounded" width
    -- reads as almost nothing. So: give the text room, see how wide it
    -- drew, and fit to that.)
    local function fit(fs, max)
        if not (fs and fs.GetStringWidth and fs:IsShown()) then return end
        fs:SetWidth(max)
        local w = fs:GetStringWidth()
        if type(w) == "number" and not secret(w) and w > 4 then fs:SetWidth(math.min(w + 4, max)) end
    end
    local function row(r)
        if r.FriendName then
            fit(r.FriendName, 250)
            fit(r.Name, 200)
            if r.PartyButton then flat(r.PartyButton, "ActionIcon") end
        elseif r.CollapseButton then
            local regs, n = ns.Regs(r.CollapseButton, 7)
            for i = 1, n do silver(regs[i]) end
        end
    end
    local function rows(box)
        local target = box and box.ScrollTarget
        if not (target and box:IsVisible()) then return end
        local kids, n = ns.Kids(target, 6)
        for i = 1, n do pcall(row, kids[i]) end
    end

    local done = false
    local function build()
        local F = _G.SocialUIFrame
        if not F or done then return F ~= nil end
        done = true
        fade(F.TopFade); fade(F.BottomFade)
        local bar = F.BattleNetBar
        local cc = bar and bar.ControlsContainer
        if bar then fade(bar.Background) end
        if cc then
            fade(cc.BattleNetBackground)
            local tag = cc.PersonalBattleTagDisplay
            if tag then
                local h = tag:GetHeight()
                ns.RoundedRect(tag, -4, 0, h / 2, T.border[1], T.border[2], T.border[3], 1)
                ns.RoundedRect(tag, -3, 1, h / 2 - 1, 0.06, 0.06, 0.07, 0.97)
                local copy = tag.CopyBattleTagToClipboardButton
                if copy then silver(copy.Icon) end
            end
            flat(cc.BattleNetMenuButton, "Icon")
            local dd = cc.OnlineStatusDropdown
            if dd then fade(dd.Background); silver(dd.Arrow) end
        end
        -- The lists (friends, recent allies, requests...): each is a child
        -- with a ScrollBox, and most have the red button at the bottom.
        local boxes, tabs = {}, {}
        local kids, n = ns.Kids(F, 5)
        for i = 1, n do
            local c = kids[i]
            if c.ScrollBox then
                boxes[#boxes + 1] = c.ScrollBox
                fade(c.TopDivider); fade(c.BottomDivider)
                if c.ActionButton then redCaps(c.ActionButton) end
            end
            if c.SelectedTexture and c.Icon and c.Background and c.GetObjectType and c:GetObjectType() == "Button" then
                tabs[#tabs + 1] = c
            end
        end
        -- The side tabs are made after the window is, so they are looked
        -- for until found. The generic skin has already given each a
        -- rounded square (__muiTabRing): its ring is the accent on the open
        -- tab, and the gold icon is silver.
        local function findTabs()
            local ks, kn = ns.Kids(F, 5)
            for i = 1, kn do
                local c = ks[i]
                if c.SelectedTexture and c.Icon and c.Icon.SetDesaturated and c.GetObjectType
                    and c:GetObjectType() == "Button" then
                    tabs[#tabs + 1] = c
                end
            end
        end
        local function sweep()
            for _, box in ipairs(boxes) do rows(box) end
            if #tabs == 0 then findTabs() end
            for _, t in ipairs(tabs) do
                local sel = t.SelectedTexture:IsShown()
                -- (Blizzard swaps the icon's art when a tab opens or
                -- closes; the tint is put back each time.)
                silver(t.Icon, sel and 1.2 or 0.75)
                if t.__muiTabRing then
                    if sel then t.__muiTabRing(T.accent[1], T.accent[2], T.accent[3], 1)
                    else t.__muiTabRing(T.border[1], T.border[2], T.border[3], 1) end
                end
            end
        end
        for _, box in ipairs(boxes) do
            if type(box.Update) == "function" then
                pcall(hooksecurefunc, box, "Update", function() pcall(rows, box) end)
            end
        end
        -- Ticked from a frame of ours (Blizzard clears OnUpdate hooks on
        -- some of its own), only while the window is open.
        local tick = CreateFrame("Frame", nil, F)
        local acc = 1
        tick:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.4 then return end
            acc = 0
            ns.Timed("friends window", sweep)
        end)
        F:HookScript("OnShow", function() acc = 1 end)
        return true
    end
    if not build() then
        -- The window is loaded when first opened.
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("ADDON_LOADED")
        local tries = 0
        wait:SetScript("OnEvent", function(self)
            if pcall(build) and done then self:UnregisterAllEvents() end
        end)
        C_Timer.NewTicker(2, function(self)
            tries = tries + 1
            local ok = pcall(build)
            if (ok and done) or tries > 600 then self:Cancel() end
        end)
    end
end

function S:OnInit(db)
    self.db = db
    for _, step in ipairs({ skinGameMenu, skinDialogs, skinMerchant, skinMap, deepMap, deepTalents, skinOthers, skinPopups,
                            skinTabard, skinMenus, skinOptions, skinSocial }) do
        local ok, err = pcall(step)
        if not ok then ns:Print("Skins: " .. tostring(err)) end
    end
end
