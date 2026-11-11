local _, ns = ...
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

    c:HookScript("OnClick", function(self, button, down)
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
    if castable and not e.passive then
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

-- ── Paging / tabs ─────────────────────────────────────────────────────────
function S:Refresh()
    if not win or not win:IsShown() then return end
    if InCombatLockdown() then pending.refresh = true; updateCooldowns(); return end
    pending.refresh = false

    local tabs = tabList()
    -- Tab pills (rebuilt only when the set of tabs changes).
    local sig = {}
    for _, t in ipairs(tabs) do table.insert(sig, t.key .. t.label) end
    sig = table.concat(sig, "|")
    if sig ~= self.tabSig then
        self.tabSig = sig
        for _, b in ipairs(tabButtons) do b:Hide() end
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
    win.pageText:SetPoint("BOTTOM", win, "BOTTOM", 0, 20)
    win.prev:SetPoint("RIGHT", win.pageText, "LEFT", -14, 0)
    win.next:SetPoint("LEFT", win.pageText, "RIGHT", 14, 0)

    win:SetScript("OnShow", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN)
        S.shownAt = GetTime()
        S:Refresh()
    end)
    win:SetScript("OnHide", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE)
        win.search:ClearFocus()
    end)
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
local function takeover(toggle)
    if S.bypass then return end
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
            if S.bypass or not f:IsShown() or InCombatLockdown() then return end
            local book = f.SpellBookFrame
            if book and book:IsShown() then takeover(false) end
        end)
    end)
end

local function hookMicro()
    local b = _G.SpellbookMicroButton
    if not b or S.hookedMicro then return end
    S.hookedMicro = true
    b:HookScript("OnClick", function() takeover(true) end)
end

function S:OnInit(db)
    self.db = db
    hookUtil()
    hookFrame()
    hookMicro()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_LOADED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "SPELL_UPDATE_COOLDOWN",
                         "PET_SPELLS_CHANGED", "UNIT_PET", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then hookUtil(); hookFrame(); hookMicro(); return end
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
