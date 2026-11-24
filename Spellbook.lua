local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Spellbook: Meniscus's own spellbook window (the talent half of Blizzard's
-- PlayerSpellsFrame stays Blizzard's; a "Talents" pill opens it).
--   header   title, search, "All ranks" toggle, Talents pill, close
--   tabs     one pill per spell school (General, Affliction…, Pet)
--   grid     3 x 7 spell cards per page: round-cornered icon, name, rank /
--            "Passive" / "Learn at level N"; cooldown sweep on the icon
--   footer   page pills
-- Cards are SecureActionButtons (left-click casts, like Blizzard's book);
-- drag puts the spell on your bars, shift-click links it. Secure cards make
-- the window protected: it can't open, close, page or switch tabs in combat
-- (pressing the spellbook key mid-fight with ours closed opens Blizzard's).

local S = ns:NewModule("Spellbook", { enabled = true, allRanks = false })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
-- Header band (ns.SHELL_H), tabs, a hairline, then the card grid.
local TABS_Y = (ns.SHELL_H or 92) + 12
local CARDS_TOP = TABS_Y + 42
local W, H = 720, 500 - 102 + CARDS_TOP
local COLS, ROWS = 3, 7
local CARD_W, CARD_H, CARD_GAP = 214, 44, 8
local PER_PAGE = COLS * ROWS
local FILL = { 0.06, 0.06, 0.07, 0.97 }
local PILL_OFF = { 0.13, 0.13, 0.15, 0.95 }
local PILL_HOVER = { 0.20, 0.20, 0.23, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }

local SB = C_SpellBook or {}
local BANK_PLAYER = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local BANK_PET = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet or 1
local IT = Enum and Enum.SpellBookItemType or {}
local TYPE_SPELL, TYPE_FUTURE, TYPE_FLYOUT, TYPE_PET = IT.Spell or 1, IT.FutureSpell or 3, IT.Flyout or 2, IT.PetAction or 4

local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not secret(v) end

-- ── Data ──────────────────────────────────────────────────────────────────
-- Tabs: { key, label, icon, bank, first, count }
local function tabList()
    local tabs = {}
    local n = call(SB.GetNumSpellBookSkillLines) or 0
    for i = 1, (num(n) and n or 0) do
        local info = call(SB.GetSpellBookSkillLineInfo, i)
        if type(info) == "table" and info.name and not info.shouldHide and (info.numSpellBookItems or 0) > 0 then
            table.insert(tabs, { key = "line" .. i, label = info.name, icon = info.iconID, bank = BANK_PLAYER,
                                 first = (info.itemIndexOffset or 0) + 1, count = info.numSpellBookItems })
        end
    end
    local petCount = call(SB.HasPetSpells)
    if num(petCount) and petCount > 0 then
        table.insert(tabs, { key = "pet", label = PET or "Pet", bank = BANK_PET, first = 1, count = petCount })
    end
    return tabs
end

local function rankOf(sub)
    if not sub or secret(sub) then return 0 end
    return tonumber(sub:match("%d+")) or 0
end

-- Spells of one tab, filtered by search; older ranks fold under the best one.
local function spellsFor(tab, search)
    local list, byName = {}, {}
    for idx = tab.first, tab.first + tab.count - 1 do
        local info = call(SB.GetSpellBookItemInfo, idx, tab.bank)
        if type(info) == "table" and info.name and not secret(info.name) and info.itemType and info.itemType ~= 0 then
            local e = { index = idx, bank = tab.bank, name = info.name, sub = info.subName, icon = info.iconID,
                        spellID = info.spellID or info.actionID, itemType = info.itemType, passive = info.isPassive }
            if not search or search == "" or e.name:lower():find(search, 1, true) then
                local prev = byName[e.name]
                if S.db.allRanks or not prev then
                    table.insert(list, e)
                    byName[e.name] = e
                elseif rankOf(e.sub) >= rankOf(prev.sub) then
                    for k, v in pairs(e) do prev[k] = v end
                end
            end
        end
    end
    return list
end

-- ── Widgets ───────────────────────────────────────────────────────────────
local win, cards, tabButtons = nil, {}, {}
local pending = { refresh = false, hide = false }

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local PILL_OPTS = { h = 22, pad = 24, minW = 44, dimIdle = true }
local function pill(parent, label, onClick)
    return ns.Pill(parent, label, onClick, PILL_OPTS)
end

local function closeButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local mask = b:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(20, 20)
    mask:SetPoint("CENTER")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    bg:SetColorTexture(0.16, 0.16, 0.18, 1)
    bg:AddMaskTexture(mask)
    local lines = {}
    for i, p in ipairs({ { -1, 1, 1, -1 }, { -1, -1, 1, 1 } }) do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetStartPoint("CENTER", b, p[1] * 4, p[2] * 4)
        l:SetEndPoint("CENTER", b, p[3] * 4, p[4] * 4)
        l:SetColorTexture(unpack(T.textDim))
        lines[i] = l
    end
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(unpack(T.accent))
        for _, l in ipairs(lines) do l:SetColorTexture(unpack(TEXT_DARK)) end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(0.16, 0.16, 0.18, 1)
        for _, l in ipairs(lines) do l:SetColorTexture(unpack(T.textDim)) end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- ── Spell cards ───────────────────────────────────────────────────────────
local function pickupSpell(e)
    if not e then return end
    if SB.PickupSpellBookItem and pcall(SB.PickupSpellBookItem, e.index, e.bank) then return end
    if e.spellID and C_Spell and C_Spell.PickupSpell then call(C_Spell.PickupSpell, e.spellID) end
end

local function newCard(i)
    local c = CreateFrame("Button", "MinimalUISpellCard" .. i, win, "SecureActionButtonTemplate")
    c:SetSize(CARD_W, CARD_H)
    c:RegisterForClicks("AnyDown", "AnyUp")
    c:RegisterForDrag("LeftButton")
    -- Cast on release, not on the press: pressing to drag a spell out to
    -- the bars was casting it (as the profession book's cards already do).
    c:SetAttribute("useOnKeyDown", false)
    c:SetAttribute("shift-type1", "") -- shift-click links instead of casting
    c.hl = ns.RoundedRect(c, -8, 0, 10, 1, 1, 1, 0)

    local D = CARD_H - 8
    local ring = CreateFrame("Frame", nil, c)
    ring:SetSize(D, D)
    ring:SetPoint("LEFT", 4, 0)
    c.ring = ns.RoundedRect(ring, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(ring, -7, 1, 6, unpack(FILL))
    local mask = ring:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2)
    mask:SetPoint("BOTTOMRIGHT", -2, 2)
    c.icon = ring:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints(mask)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.icon:AddMaskTexture(mask)
    c.cd = CreateFrame("Cooldown", nil, ring, "CooldownFrameTemplate")
    c.cd:SetAllPoints(mask)
    pcall(c.cd.SetDrawEdge, c.cd, false)

    c.name = text(c, 12, true)
    c.name:SetPoint("TOPLEFT", ring, "TOPRIGHT", 10, -5)
    c.name:SetPoint("RIGHT", c, "RIGHT", -6, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.sub = text(c, 10, false, T.textDim)
    c.sub:SetPoint("BOTTOMLEFT", ring, "BOTTOMRIGHT", 10, 5)
    -- What it is bound to for click casting, if anything ("Shift + Right click").
    c.bind = text(c, 9, false, T.accent)
    c.bind:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 6)

    c:HookScript("OnClick", function(self, button, down)
        if S.bindMode then
            if not down and button == "LeftButton" and self.entry then S.PickBindSpell(self.entry) end
            return
        end
        if down or button ~= "LeftButton" or not IsShiftKeyDown() or not self.entry then return end
        local link = call(SB.GetSpellBookItemLink, self.entry.index, self.entry.bank)
        if link and not secret(link) then
            if ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end
    end)
    c:SetScript("OnDragStart", function(self) pickupSpell(self.entry) end)
    c:SetScript("OnEnter", function(self)
        self.hl(1, 1, 1, 0.05)
        local e = self.entry
        if not e then return end
        ns.TipAnchor(self)
        if not (GameTooltip.SetSpellBookItem and pcall(GameTooltip.SetSpellBookItem, GameTooltip, e.index, e.bank)) then
            if e.spellID then GameTooltip:SetSpellByID(e.spellID) end
        end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(self) self.hl(1, 1, 1, 0); GameTooltip:Hide() end)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    c:SetPoint("TOPLEFT", win, "TOPLEFT", 20 + col * (CARD_W + CARD_GAP), -(CARDS_TOP + row * (CARD_H + CARD_GAP)))
    return c
end

-- ── Click casting: what is bound ──────────────────────────────────────────
-- "Click casting" is the game's own feature: a spell cast on someone by
-- clicking their frame, with no targeting first. Its bindings live in the
-- game (C_ClickBindings), one list per character: this only reads and
-- rewrites that list, so bindings made here and in the game's own window
-- are the same bindings.
local CBn = C_ClickBindings
local BTN_NAME = { BUTTON1 = "Left", BUTTON2 = "Right", BUTTON3 = "Middle", BUTTON4 = "Button 4", BUTTON5 = "Button 5" }
local MOUSE_TO = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local SPELL_TYPE = (Enum and Enum.ClickBindingType and Enum.ClickBindingType.Spell) or 1
local function ccAvailable() return CBn ~= nil and CBn.GetProfileInfo ~= nil and CBn.SetProfileByInfo ~= nil end
local function ccProfile()
    if not ccAvailable() then return {} end
    local ok, list = pcall(CBn.GetProfileInfo)
    return ok and type(list) == "table" and list or {}
end
-- "Shift + Right click"
local function ccLabel(info)
    local parts = {}
    local mods = info.modifiers
    if type(mods) == "number" and mods ~= 0 and CBn.GetStringFromModifiers then
        local ok, s = pcall(CBn.GetStringFromModifiers, mods)
        if ok and type(s) == "string" then
            for part in s:gmatch("[^%-]+") do parts[#parts + 1] = part:sub(1, 1):upper() .. part:sub(2):lower() end
        end
    end
    local b = tostring(info.button or "")
    parts[#parts + 1] = (BTN_NAME[b:upper()] or BTN_NAME[MOUSE_TO[b] or ""] or b) .. " click"
    return table.concat(parts, " + ")
end
-- spell id (and spell name, so a newer rank still shows it) -> its label
local ccCache
local function ccMap()
    if ccCache then return ccCache end
    ccCache = {}
    for _, info in ipairs(ccProfile()) do
        if type(info) == "table" and info.type == SPELL_TYPE and info.actionID then
            local label = ccLabel(info)
            ccCache[info.actionID] = label
            local ok, n = pcall(C_Spell.GetSpellName, info.actionID)
            if ok and type(n) == "string" and not secret(n) then ccCache[n] = label end
        end
    end
    return ccCache
end
local ccPick -- the spell chosen in the book, waiting for its button

-- A card's looks (picture, name, the line under it): nothing here is
-- protected, so it may be done in a fight.
local function paintCard(c, e)
    c.entry = e
    if not e then return end
    c.icon:SetTexture(e.icon)
    c.name:SetText(e.name)
    local future = e.itemType == TYPE_FUTURE
    if future then
        local lvl = call(SB.GetSpellBookItemLevelLearned, e.index, e.bank)
        c.sub:SetText(num(lvl) and lvl > 0 and ("Learn at level " .. lvl) or "Not learned yet")
    elseif e.passive then
        c.sub:SetText("Passive")
    else
        c.sub:SetText((e.sub and not secret(e.sub) and e.sub ~= "") and e.sub or "")
    end
    c.icon:SetDesaturated(future)
    c.icon:SetAlpha(future and 0.45 or 1)
    c.name:SetTextColor(unpack(future and T.textDim or T.text))
    local m = ccMap()
    c.bind:SetText((e.spellID and m[e.spellID]) or m[e.name] or "")
end

local function fillCard(c, e)
    c.entry = e
    if not e then
        c:SetAttribute("type1", nil)
        c:SetAttribute("spell", nil)
        c:Hide()
        return
    end
    c:Show()
    c.icon:SetTexture(e.icon)
    c.name:SetText(e.name)
    local castable = e.itemType == TYPE_SPELL or e.itemType == TYPE_PET
    local future = e.itemType == TYPE_FUTURE
    if future then
        local lvl = call(SB.GetSpellBookItemLevelLearned, e.index, e.bank)
        c.sub:SetText(num(lvl) and lvl > 0 and ("Learn at level " .. lvl) or "Not learned yet")
    elseif e.passive then
        c.sub:SetText("Passive")
    else
        c.sub:SetText((e.sub and not secret(e.sub) and e.sub ~= "") and e.sub or "")
    end
    c.icon:SetDesaturated(future)
    c.icon:SetAlpha(future and 0.45 or 1)
    c.name:SetTextColor(unpack(future and T.textDim or T.text))
    local m = ccMap()
    c.bind:SetText((e.spellID and m[e.spellID]) or m[e.name] or "")
    local picked = S.bindMode and ccPick and ccPick.spellID ~= nil and ccPick.spellID == e.spellID
    c.ring(picked and T.accent[1] or T.border[1], picked and T.accent[2] or T.border[2], picked and T.accent[3] or T.border[3], 1)
    -- (While click casting is being set up, a click picks the spell.)
    if castable and not e.passive and not S.bindMode then
        c:SetAttribute("type1", "spell")
        c:SetAttribute("spell", e.bank == BANK_PET and e.name or e.spellID)
    else
        c:SetAttribute("type1", nil)
        c:SetAttribute("spell", nil)
    end
end

local function updateCooldowns()
    for _, c in ipairs(cards) do
        local e = c:IsShown() and c.entry
        local cd = e and call(SB.GetSpellBookItemCooldown, e.index, e.bank)
        if type(cd) == "table" and num(cd.startTime) and num(cd.duration) and cd.duration > 1.5 then
            c.cd:SetCooldown(cd.startTime, cd.duration)
        else
            c.cd:Clear()
        end
    end
end

-- ── Click casting: setting it up ──────────────────────────────────────────
-- Done in our own book, in two steps a newcomer can follow: turn on "Click
-- casting" (the pill at the right of the tabs), click a spell, then press
-- the mouse button you want for it over the box in the side panel. While
-- it is on, clicking a spell picks it; nothing is cast.
--   * Targeting someone and opening their menu are bindings too (plain
--     left and plain right click, unless moved), listed first in the panel.
--     Click one of them and press a new combination to move it: a healer
--     who wants plain clicks for spells puts them on Ctrl + Shift + click.
--   * A click that targets or opens the menu can't be given to a spell
--     while it still does that: move it first. (That is what stops anyone
--     ending up with no way to target at all.)
--   * Binding a combination that another spell has takes it over, and says so.
--   * The panel lists what is bound, each spell with a cross to unbind it.
local ccPanel, ccPill
local INTERACT_TYPE = (Enum and Enum.ClickBindingType and Enum.ClickBindingType.Interaction) or 3
local CI = Enum and Enum.ClickBindingInteraction
local INTERACTIONS = {
    { id = CI and CI.Target or 1, name = "Target Unit", was = "BUTTON1",
      held = "That click is how you target them. Move \"Target Unit\" to another click first: click it below, then press its new combination." },
    { id = CI and CI.OpenContextMenu or 2, name = "Open Unit Menu", was = "BUTTON2",
      held = "That click opens their menu. Move \"Open Unit Menu\" to another click first: click it below, then press its new combination." },
}
local function sameButton(a, b)
    if a == b then return true end
    return (MOUSE_TO[a] or a) == (MOUSE_TO[b] or b)
end
-- Where an interaction is now: its entry in the list, or (not in the list)
-- the plain click it has by default.
local function interactionAt(list, it)
    for _, i in ipairs(list) do
        if type(i) == "table" and i.type == INTERACT_TYPE and i.actionID == it.id then return i.button, i.modifiers or 0 end
    end
    return it.was, 0
end
-- pick: a spell from the book ({ spellID, name }), or one of INTERACTIONS.
local function ccSet(pick, mouseButton)
    local btn = MOUSE_TO[mouseButton]
    if not btn then return "That button can't be used for this." end
    local mods = 0
    if CBn.MakeModifiers then
        local ok, m = pcall(CBn.MakeModifiers)
        if ok and type(m) == "number" then mods = m end
    end
    local list, out = ccProfile(), {}
    local typ, act = SPELL_TYPE, pick.spellID
    if pick.id then typ, act = INTERACT_TYPE, pick.id end
    -- Is that click one that targets or opens the menu (and not the very
    -- thing being moved)?
    for _, it in ipairs(INTERACTIONS) do
        if not (pick.id and pick.id == it.id) then
            local ib, im = interactionAt(list, it)
            if sameButton(ib, btn) and im == mods then return it.held end
        end
    end
    if typ == SPELL_TYPE and CBn.CanSpellBeClickBound then
        local ok, can = pcall(CBn.CanSpellBeClickBound, act)
        if ok and can == false then return pick.name .. " can't be cast by clicking a frame." end
    end
    -- (Buttons are written the way the list already writes them.)
    local want = btn
    for _, i in ipairs(list) do
        if type(i) == "table" and type(i.button) == "string" and MOUSE_TO[i.button] then want = mouseButton break end
    end
    local took
    for _, i in ipairs(list) do
        if type(i) == "table" then
            local here = sameButton(i.button, btn) and (i.modifiers or 0) == mods
            local same = i.type == typ and i.actionID == act
            if here and not same and i.type == SPELL_TYPE then took = i.actionID end
            if not here and not same then out[#out + 1] = i end
        end
    end
    out[#out + 1] = { type = typ, actionID = act, button = want, modifiers = mods }
    local ok, err = pcall(CBn.SetProfileByInfo, out)
    if not ok then return "The game refused that: " .. tostring(err) end
    ccCache = nil
    local tookName
    if took then
        local okN, n = pcall(C_Spell.GetSpellName, took)
        tookName = okN and type(n) == "string" and not secret(n) and n or nil
    end
    return nil, tookName
end
local function ccClear(spellID)
    local out = {}
    for _, i in ipairs(ccProfile()) do
        if type(i) == "table" and not (i.type == SPELL_TYPE and i.actionID == spellID) then out[#out + 1] = i end
    end
    pcall(CBn.SetProfileByInfo, out)
    ccCache = nil
end
local function ccPaint(note, bad)
    if not ccPanel then return end
    local p = ccPanel
    if ccPick then
        p.boxText:SetText("Press a mouse button here\nfor " .. ccPick.name)
        p.boxRing(T.accent[1], T.accent[2], T.accent[3], 1)
    else
        p.boxText:SetText("Click a spell in the book first")
        p.boxRing(T.border[1], T.border[2], T.border[3], 1)
    end
    p.note:SetText(note or "")
    if bad then p.note:SetTextColor(0.95, 0.55, 0.50) else p.note:SetTextColor(0.50, 0.92, 0.58) end
    local list = ccProfile()
    for k, it in ipairs(INTERACTIONS) do
        local r = p.fixed[k]
        local ib, im = interactionAt(list, it)
        r.label:SetText(ccLabel({ button = ib, modifiers = im }))
        local on = ccPick and ccPick.id == it.id
        r.name:SetTextColor(unpack(on and T.accent or T.text))
    end
    local n = 0
    for _, info in ipairs(list) do
        if type(info) == "table" and info.type == SPELL_TYPE and info.actionID and n < #p.rows then
            n = n + 1
            local r = p.rows[n]
            local okN, name = pcall(C_Spell.GetSpellName, info.actionID)
            local okT, tex = pcall(C_Spell.GetSpellTexture, info.actionID)
            r.icon:SetTexture(okT and tex or 134400)
            r.name:SetText(okN and type(name) == "string" and not secret(name) and name or ("Spell " .. tostring(info.actionID)))
            r.label:SetText(ccLabel(info))
            r.spellID = info.actionID
            r:Show()
        end
    end
    for i = n + 1, #p.rows do p.rows[i]:Hide() end
end
local function ccBuild()
    local p = CreateFrame("Frame", nil, win)
    local PW, IN = 268, 16
    p:SetSize(PW, 442)
    p:SetPoint("TOPLEFT", win, "TOPRIGHT", 10, 0)
    p:EnableMouse(true)
    ns.RoundedRect(p, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(p, -7, 1, 13, unpack(FILL))
    local function line(size, bold, color, yTop, str)
        local fs = text(p, size, bold, color)
        fs:SetPoint("TOPLEFT", IN, yTop)
        fs:SetWidth(PW - IN * 2)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetText(str)
        return fs
    end
    local y = -16
    line(14, true, nil, y, "Click casting")
    y = y - 24
    local t2 = line(11, false, T.textDim, y, "Cast a spell on someone by clicking their frame. No need to target them first.")
    y = y - (t2:GetStringHeight() or 28) - 12
    local t3 = line(11, false, nil, y, "1   Click a spell in the book, or one of the two lines under \"Your bindings\".")
    y = y - (t3:GetStringHeight() or 28) - 6
    local t4 = line(11, false, nil, y, "2   Point at the box below and press the mouse button you want for it. Hold Shift, Ctrl or Alt to make a combination.")
    y = y - (t4:GetStringHeight() or 42) - 10
    -- The box that takes the press.
    local box = CreateFrame("Button", nil, p)
    box:SetSize(PW - IN * 2, 54)
    box:SetPoint("TOPLEFT", IN, y)
    p.boxRing = ns.RoundedRect(box, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(box, -7, 1.5, 9, 0.09, 0.09, 0.10, 1)
    p.boxText = text(box, 11, true)
    p.boxText:SetPoint("CENTER")
    p.boxText:SetJustifyH("CENTER")
    box:SetScript("OnMouseDown", function(_, button)
        if InCombatLockdown() then return ccPaint("Not during a fight.", true) end
        if not ccPick then return ccPaint("Click a spell in the book first.", true) end
        local err, took = ccSet(ccPick, button)
        if err then return ccPaint(err, true) end
        local done = ccPick.id and (ccPick.name .. " has moved.") or (ccPick.name .. " is bound.")
        if took then done = done .. " (It took that click from " .. took .. ".)" end
        ccPick = nil
        ccPaint(done)
        S:Refresh()
    end)
    y = y - 54 - 8
    p.note = line(10, false, nil, y, "")
    y = y - 46
    line(10, true, T.textDim, y, "YOUR BINDINGS")
    y = y - 18
    -- Targeting and the menu: always there, each to be moved by clicking it.
    p.fixed = {}
    for k, it in ipairs(INTERACTIONS) do
        local r = CreateFrame("Button", nil, p)
        r:SetSize(PW - IN * 2, 22)
        r:SetPoint("TOPLEFT", IN, y)
        r.hl = ns.RoundedRect(r, -8, -4, 6, 1, 1, 1, 0)
        r.name = text(r, 11)
        r.name:SetPoint("LEFT", 0, 0)
        r.name:SetText(it.name)
        r.label = text(r, 10, false, T.textDim)
        r.label:SetPoint("RIGHT", -2, 0)
        r:SetScript("OnEnter", function(self)
            self.hl(1, 1, 1, 0.06)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(it.name, 1, 1, 1)
            GameTooltip:AddLine("Click, then press a new combination in the box to move it. That frees its old click for a spell.", 0.8, 0.8, 0.85, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function(self) self.hl(1, 1, 1, 0); GameTooltip:Hide() end)
        r:SetScript("OnClick", function()
            if InCombatLockdown() then return ccPaint("Not during a fight.", true) end
            ccPick = { id = it.id, name = it.name }
            ccPaint()
            S:Refresh()
        end)
        p.fixed[k] = r
        y = y - 24
    end
    y = y - 4
    p.rows = {}
    for i = 1, 6 do
        local r = CreateFrame("Frame", nil, p)
        r:SetSize(PW - IN * 2, 22)
        r:SetPoint("TOPLEFT", IN, y - (i - 1) * 24)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 0, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = text(r, 11)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetWidth(96)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        local x = closeButton(r, function()
            if InCombatLockdown() then return ccPaint("Not during a fight.", true) end
            local nm = r.name:GetText() or "That spell"
            ccClear(r.spellID)
            ccPaint(nm .. " is unbound.")
            S:Refresh()
        end)
        x:SetScale(0.8)
        x:SetPoint("RIGHT", 0, 0)
        r.label = text(r, 10, false, T.textDim)
        r.label:SetPoint("RIGHT", x, "LEFT", -6, 0)
        r.label:SetJustifyH("RIGHT")
        r:Hide()
        p.rows[i] = r
    end
    local done = pill(p, "Done", function() S.SetBindMode(false) end)
    done:SetPoint("BOTTOMRIGHT", -IN, 14)
    ccPanel = p
    -- What the client has for this, once, for the record.
    if MinimalUIDB then
        local d = { "available " .. tostring(ccAvailable()) }
        for k in pairs(CBn or {}) do d[#d + 1] = "fn " .. tostring(k) end
        for i, info in ipairs(ccProfile()) do
            if i <= 8 and type(info) == "table" then
                d[#d + 1] = string.format("entry type=%s action=%s button=%s mods=%s", tostring(info.type),
                    tostring(info.actionID), tostring(info.button), tostring(info.modifiers))
            end
        end
        MinimalUIDB.clickdiag = d
    end
end
function S.SetBindMode(on)
    if not win then return end
    if on and InCombatLockdown() then return end
    if on and not ccAvailable() then
        ns:Print("Click casting isn't available on this client.")
        return
    end
    S.bindMode = on and true or false
    ccPick = nil
    ccCache = nil
    if on and not ccPanel then ccBuild() end
    if ccPanel then ccPanel:SetShown(S.bindMode) end
    if ccPill then ccPill.on = S.bindMode; ccPill:Repaint() end
    ccPaint()
    if not InCombatLockdown() then S:Refresh() end
end
function S.PickBindSpell(e)
    if not e or e.passive or e.itemType ~= TYPE_SPELL or e.bank == BANK_PET or not e.spellID then
        return ccPaint("That one can't be bound: pick a spell you cast.", true)
    end
    ccPick = e
    ccPaint()
    S:Refresh()
end

-- ── In a fight ────────────────────────────────────────────────────────────
-- Turning a page means giving each card another spell to cast, and ordinary
-- code may not do that in combat. Secure code may. So, as a fight starts,
-- the whole book is written down for it (every tab, every page, which spell
-- sits on which card: the book doesn't change mid-fight), and the tabs, the
-- page buttons and the close button each get an unseen secure twin lying
-- on top of them. In combat the twin's own snippet turns the page from
-- that record (or closes the window), and ordinary code then repaints the
-- pictures and names, which is allowed. Out of combat the twin just does
-- what the button under it always did.
local ctl
local snapTabs, snap = {}, {}
local function castValue(e)
    -- What a card casts; 0 = a card that is shown but casts nothing.
    if (e.itemType ~= TYPE_SPELL and e.itemType ~= TYPE_PET) or e.passive then return 0 end
    return (e.bank == BANK_PET and e.name) or e.spellID or 0
end
local function snapshot()
    if not ctl or InCombatLockdown() then return end
    local tabs = tabList()
    for i = #snapTabs, 1, -1 do snapTabs[i] = nil end
    local tabAt
    for ti, t in ipairs(tabs) do
        snapTabs[ti] = t
        local list = spellsFor(t, nil)
        local pages = math.max(1, math.ceil(#list / PER_PAGE))
        local st = snap[ti]
        if not st then st = {}; snap[ti] = st end
        -- (As many pages as the larger of now and last time, so a page
        -- that no longer exists is written down as empty.)
        for pi = 1, math.max(pages, st.n or 0) do
            local sp = st[pi]
            if not sp then sp = {}; st[pi] = sp end
            for ci = 1, PER_PAGE do
                local e = pi <= pages and list[(pi - 1) * PER_PAGE + ci] or nil
                sp[ci] = e or false
                ctl:SetAttribute("s" .. ti .. "_" .. pi .. "_" .. ci, e and castValue(e) or nil)
            end
        end
        st.n = pages
        ctl:SetAttribute("pages" .. ti, pages)
        if t.key == S.tab then tabAt = ti end
    end
    ctl:SetAttribute("tab", tabAt or 1)
    ctl:SetAttribute("page", S.page or 1)
end
S.Snapshot = snapshot
-- After a secure twin has turned the page in combat: the looks to match.
local function combatPaint()
    if not ctl then return end
    local ti, pi = ctl:GetAttribute("tab") or 1, ctl:GetAttribute("page") or 1
    local t = snapTabs[ti]
    if not t then return end
    S.tab, S.page = t.key, pi
    local page = snap[ti] and snap[ti][pi]
    local n = 0
    for ci, c in ipairs(cards) do
        local e = page and page[ci] or nil
        paintCard(c, e or nil)
        if e then n = n + 1 end
    end
    updateCooldowns()
    for _, b in ipairs(tabButtons) do b.on = (b.key == S.tab); b:Repaint() end
    local pages = ctl:GetAttribute("pages" .. ti) or 1
    win.pageText:SetText(pages > 1 and string.format("%d / %d", pi, pages) or "")
    win.prev:SetShown(pages > 1)
    win.next:SetShown(pages > 1)
    win.shell:SetSubtitle(t.label)
    win.empty:SetShown(n == 0)
end
-- An unseen secure button over `target`: `snippet` runs in combat (it
-- begins by leaving if there is no fight), `plain` otherwise.
local function secureOver(target, snippet, plain)
    local o = CreateFrame("Button", nil, win, "SecureHandlerClickTemplate")
    o:SetAllPoints(target)
    o:SetFrameLevel(target:GetFrameLevel() + 6)
    o:RegisterForClicks("AnyUp")
    o:SetAttribute("_onclick", snippet)
    if SecureHandlerSetFrameRef then
        SecureHandlerSetFrameRef(o, "ctl", ctl)
        SecureHandlerSetFrameRef(o, "win", win)
    end
    o:HookScript("OnClick", function()
        if InCombatLockdown() then pcall(combatPaint) else plain() end
    end)
    o:SetScript("OnEnter", function() local f = target:GetScript("OnEnter"); if f then pcall(f, target) end end)
    o:SetScript("OnLeave", function() local f = target:GetScript("OnLeave"); if f then pcall(f, target) end end)
    return o
end
local TAB_SNIPPET = [[
    if not PlayerInCombat() then return end
    local ctl = self:GetFrameRef("ctl")
    ctl:SetAttribute("tab", self:GetAttribute("tabindex") or 1)
    ctl:SetAttribute("page", 1)
    ctl:RunAttribute("apply")
]]
local STEP_SNIPPET = [[
    if not PlayerInCombat() then return end
    local ctl = self:GetFrameRef("ctl")
    local ti = ctl:GetAttribute("tab") or 1
    local pages = ctl:GetAttribute("pages" .. ti) or 1
    local pi = (ctl:GetAttribute("page") or 1) + (self:GetAttribute("step") or 0)
    if pi < 1 then pi = 1 elseif pi > pages then pi = pages end
    ctl:SetAttribute("page", pi)
    ctl:RunAttribute("apply")
]]
local CLOSE_SNIPPET = [[
    if not PlayerInCombat() then return end
    local w = self:GetFrameRef("win")
    if w then w:Hide() end
]]
local function buildCombat()
    ctl = CreateFrame("Frame", "MinimalUISpellbookCtl", win, "SecureHandlerBaseTemplate")
    for i, c in ipairs(cards) do
        if SecureHandlerSetFrameRef then SecureHandlerSetFrameRef(ctl, "card" .. i, c) end
    end
    ctl:SetAttribute("apply", string.format([[
        local ti, pi = self:GetAttribute("tab") or 1, self:GetAttribute("page") or 1
        for ci = 1, %d do
            local card = self:GetFrameRef("card" .. ci)
            if card then
                local v = self:GetAttribute("s" .. ti .. "_" .. pi .. "_" .. ci)
                if v == nil then
                    card:Hide()
                else
                    card:Show()
                    if v == 0 then
                        card:SetAttribute("type1", nil)
                        card:SetAttribute("spell", nil)
                    else
                        card:SetAttribute("type1", "spell")
                        card:SetAttribute("spell", v)
                    end
                end
            end
        end
    ]], PER_PAGE))
    local prev = secureOver(win.prev, STEP_SNIPPET, function() S.page = (S.page or 1) - 1; S:Refresh() end)
    prev:SetAttribute("step", -1)
    local nxt = secureOver(win.next, STEP_SNIPPET, function() S.page = (S.page or 1) + 1; S:Refresh() end)
    nxt:SetAttribute("step", 1)
    -- The close button: the shell's own sits at the window's top right.
    local x = CreateFrame("Frame", nil, win)
    x:SetSize(22, 22)
    x:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -12)
    x:SetFrameLevel(win:GetFrameLevel() + 60) -- (above the header band and what is lifted onto it)
    local xo = secureOver(x, CLOSE_SNIPPET, function() S:Close() end)
    -- (It lies over the shell's own X and takes the mouse, so the X never
    -- lit up under the pointer: it felt covered by something unseen. What
    -- the pointer does here is now passed on to the X.)
    local function pass(script)
        local c = win.shell and win.shell.close
        local f = c and c:GetScript(script)
        if f then pcall(f, c) end
    end
    xo:SetScript("OnEnter", function() pass("OnEnter") end)
    xo:SetScript("OnLeave", function() pass("OnLeave") end)
end

-- ── Paging / tabs ─────────────────────────────────────────────────────────
-- force: fill it in even while it is hidden (done as a fight starts, so
-- that the book is up to date if it is opened mid-fight).
function S:Refresh(force)
    if not win or not (force or win:IsShown()) then return end
    if InCombatLockdown() then pending.refresh = true; updateCooldowns(); return end
    pending.refresh = false

    local tabs = tabList()
    -- Tab pills (rebuilt only when the set of tabs changes).
    local sig = {}
    for _, t in ipairs(tabs) do table.insert(sig, t.key .. t.label) end
    sig = table.concat(sig, "|")
    if sig ~= self.tabSig then
        self.tabSig = sig
        for _, b in ipairs(tabButtons) do b:Hide(); if b.over then b.over:Hide() end end
        local x = 20
        for i, t in ipairs(tabs) do
            local b = tabButtons[i]
            if not b then
                b = pill(win, "", function(self) S.tab = self.key; S.page = 1; S:Refresh() end)
                tabButtons[i] = b
            end
            b.key = t.key
            b.fs:SetText(t.label)
            b:SetWidth(math.max(b.fs:GetStringWidth() + 24, 44))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -TABS_Y)
            b:Show()
            if ctl then
                if not b.over then
                    local pillB = b
                    b.over = secureOver(b, TAB_SNIPPET, function() S.tab = pillB.key; S.page = 1; S:Refresh() end)
                end
                b.over:SetAttribute("tabindex", i)
                b.over:Show()
            end
            x = x + b:GetWidth() + 6
        end
    end
    local current
    for _, t in ipairs(tabs) do if t.key == self.tab then current = t end end
    if not current then
        -- Default to the first class school (second line), else the first tab.
        current = tabs[2] or tabs[1]
        self.tab, self.page = current and current.key, 1
    end
    for _, b in ipairs(tabButtons) do b.on = (b.key == self.tab); b:Repaint() end

    local list = current and spellsFor(current, self.search) or {}
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    self.page = math.max(1, math.min(self.page or 1, pages))
    local first = (self.page - 1) * PER_PAGE
    for i, c in ipairs(cards) do fillCard(c, list[first + i]) end
    updateCooldowns()

    win.shell:SetSubtitle(current and string.format("%s  ·  %d spells", current.label, #list) or "")
    win.pageText:SetText(pages > 1 and string.format("%d / %d", self.page, pages) or "")
    win.prev:SetShown(pages > 1)
    win.next:SetShown(pages > 1)
    win.empty:SetShown(#list == 0)
end

local function build()
    win = CreateFrame("Frame", "MinimalUISpellbook", UIParent)
    win:SetSize(W, H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        S.db.pos = { p, rp, x, y }
    end)
    local pos = S.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER", 0, 40) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUISpellbook")

    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win, { onClose = function() S:Close() end })
    win.shell:SetTitle(SPELLBOOK or "Spellbook")
    win.shell:SetIcon("Interface/Icons/INV_Misc_Book_09")
    win.shell:SetRing({ 0.62, 0.48, 0.95 })

    local ranks = pill(win, "All ranks", function(self)
        if InCombatLockdown() then return end
        S.db.allRanks = not S.db.allRanks
        self.on = S.db.allRanks; self:Repaint()
        S:Refresh()
    end)
    ranks.on = S.db.allRanks; ranks:Repaint()
    ranks:SetPoint("BOTTOMRIGHT", win.shell.band, "BOTTOMRIGHT", -14, 14)

    local talentsFn = PlayerSpellsUtil and (PlayerSpellsUtil.ToggleClassTalentFrame
        or PlayerSpellsUtil.ToggleClassTalentOrSpecFrame or PlayerSpellsUtil.OpenToClassTalentsTab)
    local anchor = ranks
    if talentsFn then
        local tal = pill(win, TALENTS or "Talents", function()
            if InCombatLockdown() then return end
            local lvl = UnitLevel("player")
            if num(lvl) and lvl < 10 then
                UIErrorsFrame:AddMessage("Talents unlock at level 10.", 1, 0.82, 0)
                return
            end
            S.bypass = true
            S:Close()
            call(talentsFn)
            -- If Blizzard's window didn't actually open, don't stay in bypass
            -- (that made the next spellbook key open Blizzard's book).
            C_Timer.After(0.3, function()
                local f = _G.PlayerSpellsFrame
                if not (f and f:IsShown()) then S.bypass = false end
            end)
        end)
        tal:HookScript("OnEnter", function(self)
            local lvl = UnitLevel("player")
            if num(lvl) and lvl < 10 then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText("Talents unlock at level 10", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        tal:HookScript("OnLeave", function() GameTooltip:Hide() end)
        tal:SetPoint("RIGHT", ranks, "LEFT", -6, 0)
        anchor = tal
    end

    -- Search.
    local box = CreateFrame("EditBox", nil, win)
    box:SetAutoFocus(false)
    box:SetSize(160, 22)
    box:SetPoint("RIGHT", anchor, "LEFT", -10, 0)
    box:SetTextInsets(10, 10, 0, 0)
    ns:SetFont(box, 11, "")
    box:SetTextColor(unpack(T.text))
    ns.RoundedRect(box, -8, 0, 11, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(box, -7, 1, 10, 0.05, 0.05, 0.06, 1)
    local hint = text(box, 11, false, T.textDim)
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText("Search")
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        hint:SetShown(t == "" and not self:HasFocus())
        S.search, S.page = t:lower(), 1
        S:Refresh()
    end)
    box:SetScript("OnEditFocusGained", function() hint:Hide() end)
    box:SetScript("OnEditFocusLost", function(self) hint:SetShown((self:GetText() or "") == "") end)
    win.search = box
    win.shell:Lift(box, ranks, anchor)

    local line = win:CreateTexture(nil, "BORDER")
    line:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.8)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 20, -(TABS_Y + 32))
    line:SetPoint("TOPRIGHT", -20, -(TABS_Y + 32))

    for i = 1, PER_PAGE do cards[i] = newCard(i) end

    ccPill = pill(win, "Click casting", function() S.SetBindMode(not S.bindMode) end)
    ccPill:SetPoint("TOPRIGHT", win, "TOPRIGHT", -20, -TABS_Y)
    ccPill:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Click casting", 1, 1, 1)
        GameTooltip:AddLine("Set spells to cast when you click someone's frame.", 0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    ccPill:HookScript("OnLeave", function() GameTooltip:Hide() end)

    win.empty = text(win, 11, false, T.textDim)
    win.empty:SetPoint("TOP", win, "TOP", 0, -(CARDS_TOP + 58))
    win.empty:SetText("No spells match.")

    win.prev = pill(win, "Previous", function()
        if InCombatLockdown() then return end
        S.page = (S.page or 1) - 1; S:Refresh()
    end)
    win.next = pill(win, "Next", function()
        if InCombatLockdown() then return end
        S.page = (S.page or 1) + 1; S:Refresh()
    end)
    win.pageText = text(win, 11, true, T.textDim)
    -- The pills hang off a frame, not off the text: the in-combat buttons
    -- laid over them are protected, and the game refuses to place one of
    -- those (through any chain) against a piece of text. That refusal
    -- stopped the whole in-combat book from being built.
    local pageBox = CreateFrame("Frame", nil, win)
    pageBox:SetSize(84, 22)
    pageBox:SetPoint("BOTTOM", win, "BOTTOM", 0, 15)
    win.pageText:SetPoint("CENTER", pageBox, "CENTER", 0, 0)
    win.prev:SetPoint("RIGHT", pageBox, "LEFT", -6, 0)
    win.next:SetPoint("LEFT", pageBox, "RIGHT", 6, 0)
    local okC, errC = pcall(buildCombat)
    if not okC then ctl = nil; if MinimalUIDB then MinimalUIDB.spellbookErr = tostring(errC) end end

    win:SetScript("OnShow", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN)
        S.shownAt = GetTime()
        S:Refresh()
    end)
    win:SetScript("OnHide", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE)
        win.search:ClearFocus()
        if S.bindMode then
            S.bindMode, ccPick = false, nil
            if ccPanel then ccPanel:Hide() end
            if ccPill then ccPill.on = false; ccPill:Repaint() end
        end
    end)
    -- The key's secure toggle (below) is told which window is ours.
    if S.toggle and SecureHandlerSetFrameRef then pcall(SecureHandlerSetFrameRef, S.toggle, "win", win) end
end

function S:Open()
    if not win then
        if InCombatLockdown() then return false end
        build()
    end
    if win:IsShown() then return true end
    if InCombatLockdown() then return false end
    win:Show()
    return true
end

function S:Close()
    if not win or not win:IsShown() then return end
    if InCombatLockdown() then pending.hide = true; return end
    win:Hide()
end

function S:Toggle()
    if win and win:IsShown() then self:Close() else self:Open() end
end

-- ── Taking over Blizzard's spellbook ──────────────────────────────────────
-- After Blizzard's spellbook functions run: close Blizzard's window and
-- open (or, if ours was already open before this frame, close) ours. In
-- combat, while ours is closed, Blizzard's stays.
-- Setting up Click Casting: the game's binding window works by clicking a
-- spell in the game's OWN spellbook (ours would just cast it). While that
-- window is open the game's book is left alone, and ours stays shut.
local function binding()
    local f = _G.ClickBindingFrame
    return f and f.IsShown and f:IsShown() or false
end
local function takeover(toggle)
    if S.bypass or binding() then return end
    local f = _G.PlayerSpellsFrame
    local wasOpen = win and win:IsShown() and S.shownAt ~= GetTime()
    if toggle and wasOpen then
        if f and f:IsShown() and not InCombatLockdown() then HideUIPanel(f) end
        S:Close()
        return
    end
    if S:Open() and f and f:IsShown() then HideUIPanel(f) end
end

local function hookUtil()
    local U = _G.PlayerSpellsUtil
    if not U or S.hookedUtil then return end
    S.hookedUtil = true
    if U.ToggleSpellBookFrame then hooksecurefunc(U, "ToggleSpellBookFrame", function() takeover(true) end) end
    for _, fn in ipairs({ "OpenToSpellBookTab", "OpenToSpellBookTabAtSpell" }) do
        if U[fn] then hooksecurefunc(U, fn, function() takeover(false) end) end
    end
end

local function hookFrame()
    local f = _G.PlayerSpellsFrame
    if not f or S.hookedFrame then return end
    S.hookedFrame = true
    f:HookScript("OnHide", function() S.bypass = false end)
    -- Paths that open Blizzard's book without going through PlayerSpellsUtil
    -- (the micro-menu button): once the frame has settled on a tab, take
    -- over if it landed on the spellbook. Talents stay Blizzard's.
    f:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if S.bypass or binding() or not f:IsShown() or InCombatLockdown() then return end
            local book = f.SpellBookFrame
            if book and book:IsShown() then takeover(false) end
        end)
    end)
end

-- The binding window opening: put ours away and bring up the game's book
-- beside it (it usually opens the book itself; this covers ours having
-- been open already).
local function hookBinding()
    local f = _G.ClickBindingFrame
    if not f or S.hookedBinding or not f.HookScript then return end
    S.hookedBinding = true
    -- Side by side: the binding window goes to the right of the game's
    -- book, level with its top (they were landing one over the other).
    local function arrange()
        local ps = _G.PlayerSpellsFrame
        if not (binding() and ps and ps:IsShown()) or InCombatLockdown() then return end
        pcall(function()
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", ps, "TOPRIGHT", 12, 0)
        end)
    end
    f:HookScript("OnShow", function()
        if InCombatLockdown() then return end
        if win and win:IsShown() then S:Close() end
        C_Timer.After(0.1, function()
            local ps = _G.PlayerSpellsFrame
            if binding() and not (ps and ps:IsShown()) then
                local U = _G.PlayerSpellsUtil
                if U and U.OpenToSpellBookTab then pcall(U.OpenToSpellBookTab) end
            end
        end)
        C_Timer.After(0.3, arrange)
        C_Timer.After(1.0, arrange)
    end)
    local ps0 = _G.PlayerSpellsFrame
    if ps0 and ps0.HookScript then
        ps0:HookScript("OnShow", function() C_Timer.After(0.2, arrange) end)
    end
end

local function hookMicro()
    local b = _G.SpellbookMicroButton
    if not b or S.hookedMicro then return end
    S.hookedMicro = true
    b:HookScript("OnClick", function() takeover(true) end)
end

-- The spellbook key, in a fight. Our window holds secure buttons (the spell
-- cards), and ordinary code may not show or hide such a window in combat:
-- so the game's own book used to open instead. Now the key (whatever is
-- bound to "Toggle Spellbook") clicks a secure button of ours, and secure
-- code is allowed to show and hide the window mid-fight. As with the bags.
--   * The window is built soon after login, so it exists before a fight.
--   * What it lists can't be redone in combat: it shows the book as it was
--     when the fight began, and catches up afterwards.
--   * Out of combat the key does what it always did.
local function buildToggle()
    local toggle = CreateFrame("Button", "MinimalUISpellbookToggle", UIParent, "SecureHandlerClickTemplate")
    S.toggle = toggle
    toggle:SetAttribute("_onclick", [[
        if not PlayerInCombat() then return end
        local w = self:GetFrameRef("win")
        if not w then return end
        if w:IsShown() then w:Hide() else w:Show() end
    ]])
    local function blizzToggle()
        local U = _G.PlayerSpellsUtil
        if U and U.ToggleSpellBookFrame then pcall(U.ToggleSpellBookFrame)
        elseif _G.ToggleSpellBook then pcall(_G.ToggleSpellBook, "spell") end
    end
    toggle:HookScript("OnClick", function()
        if S.bypass or binding() then return blizzToggle() end
        if InCombatLockdown() then
            -- Ours was never built (a fight right at login). The game's own
            -- book can't stand in: opened from here mid-fight it is blocked
            -- at every step.
            if not win and ns.Print then ns:Print("The spellbook opens once this fight is over.") end
            return
        end
        local f = _G.PlayerSpellsFrame
        if f and f:IsShown() then pcall(HideUIPanel, f) end
        S:Toggle()
    end)
    if win and SecureHandlerSetFrameRef then pcall(SecureHandlerSetFrameRef, toggle, "win", win) end
    local owner = CreateFrame("Frame")
    local function bindKeys()
        if InCombatLockdown() then owner.pending = true; return end
        owner.pending = false
        ClearOverrideBindings(owner)
        for _, action in ipairs({ "TOGGLESPELLBOOK" }) do
            local keys = { GetBindingKey(action) }
            for _, key in ipairs(keys) do
                if key then SetOverrideBindingClick(owner, false, key, "MinimalUISpellbookToggle") end
            end
        end
    end
    owner:RegisterEvent("PLAYER_ENTERING_WORLD")
    owner:RegisterEvent("UPDATE_BINDINGS")
    owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    owner:RegisterEvent("PLAYER_REGEN_DISABLED")
    owner:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_DISABLED" then
            -- (Setting up click casting ends, so the cards cast again.)
            if S.bindMode and not InCombatLockdown() then pcall(S.SetBindMode, false) end
            -- A fight is starting (the lockdown has not begun yet): bring
            -- the hidden book up to date, for the last time until it ends.
            if win and not win:IsShown() and not InCombatLockdown() then pcall(S.Refresh, S, true) end
            if win and S.Snapshot then pcall(S.Snapshot) end
            return
        end
        if e == "PLAYER_REGEN_ENABLED" then
            if owner.pending then bindKeys() end
            -- (And build the window now, if a fight at login put it off.)
            if not win then pcall(build); if win then win:Hide() end end
            return
        end
        bindKeys()
    end)
    -- Build the window ahead of need: a little after login, or right now
    -- when login lands in a fight (a reload mid-combat), while it still can
    -- be built.
    if not win and not InCombatLockdown() and UnitAffectingCombat and UnitAffectingCombat("player") then
        pcall(build)
        if win then win:Hide() end
    end
    C_Timer.After(4, function()
        if win or InCombatLockdown() then return end
        pcall(build)
        if win then win:Hide(); pcall(S.Refresh, S, true) end
    end)
end

function S:OnInit(db)
    self.db = db
    hookUtil()
    hookFrame()
    hookMicro()
    hookBinding()
    pcall(buildToggle)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_LOADED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "SPELL_UPDATE_COOLDOWN",
                         "PET_SPELLS_CHANGED", "UNIT_PET", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then hookUtil(); hookFrame(); hookMicro(); hookBinding(); return end
        if event == "PLAYER_REGEN_ENABLED" then
            if pending.hide then pending.hide = false; if win then win:Hide() end end
            if pending.refresh then S:Refresh() end
            return
        end
        if not win or not win:IsShown() then return end
        if event == "SPELL_UPDATE_COOLDOWN" then updateCooldowns() else S:Refresh() end
    end)
end

ns.commands.spells = function() if S.db then S:Toggle() end end
