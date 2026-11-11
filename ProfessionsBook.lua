local _, ns = ...
local T = ns.Theme

-- Professions book (K): Meniscus's version of Blizzard's book, which on
-- Forever is ProfessionsFrame with no profession open.
--   header     "Professions", "N of 2 professions" chip
--   primary    a card per profession slot: icon, name, rank, slim skill bar,
--              its abilities as pills (click casts / opens the profession),
--              a quiet Unlearn; an empty slot says where to learn one
--   secondary  Cooking, Fishing, First Aid (+ Archaeology if learned) side
--              by side, same bits, or "visit a trainer"
--   footer     Close
-- Ability pills are secure buttons: attributes only change out of combat.

local PB = ns:NewModule("ProfessionsBook", { enabled = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local W = 580
local TOP = (ns.SHELL_H or 92) + 14
local PRIM_H = 96
local SEC_H = 156
local FOOTER_H = 52
local H = TOP + PRIM_H * 2 + 8 + 12 + SEC_H + 12 + FOOTER_H
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local CARD = { 0.10, 0.10, 0.115, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local SKILL = { 0.40, 0.72, 0.95 }
local RED = { 0.95, 0.42, 0.40, 1 }

local SB = C_SpellBook or {}
local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0

local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not secret(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

-- Cards are secure buttons too: clicking anywhere on a learned profession's
-- card opens it (casts its first active ability; see fillAbilities).
-- Drag a card or pill onto an action bar. The button casts on release
-- (useOnKeyDown false) so pressing to drag doesn't open the profession.
local function dragSpell(b)
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("useOnKeyDown", false)
    b:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local a = self.main or self
        if a.slot and SB.PickupSpellBookItem and pcall(SB.PickupSpellBookItem, a.slot, BANK) then return end
        if a.spellID and C_Spell and C_Spell.PickupSpell then call(C_Spell.PickupSpell, a.spellID) end
    end)
end

local cardCount = 0
local function card(parent, w, h)
    cardCount = cardCount + 1
    local c = CreateFrame("Button", "MinimalUIProfBookCard" .. cardCount, parent, "SecureActionButtonTemplate")
    c:SetSize(w, h)
    -- Down + up: Forever's secure template acts on whichever edge the
    -- ActionButtonUseKeyDown CVar picks; "AnyUp" alone never fired.
    c:RegisterForClicks("AnyDown", "AnyUp")
    c:HookScript("PreClick", function() ns.profBookKeyAt = nil end)
    dragSpell(c)
    c.ring = ns.RoundedRect(c, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    c.fillPaint = ns.RoundedRect(c, -7, 1, 11, unpack(CARD))
    c:HookScript("OnEnter", function(self)
        if not self.main then return end
        self.ring(unpack(T.accent)); self.fillPaint(0.125, 0.125, 0.145, 1)
        ns.TipAnchor(self)
        if not pcall(GameTooltip.SetSpellBookItem, GameTooltip, self.main.slot, BANK) then
            GameTooltip:SetText(self.main.name)
        end
        GameTooltip:AddLine("Click to open, drag to an action bar", 0.6, 0.6, 0.65)
        GameTooltip:Show()
    end)
    c:HookScript("OnLeave", function(self)
        self.ring(T.border[1], T.border[2], T.border[3], 1); self.fillPaint(unpack(CARD))
        GameTooltip:Hide()
    end)
    return c
end

local function iconBox(parent, size, radius)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(size, size)
    ns.RoundedRect(box, -8, 0, radius, T.border[1], T.border[2], T.border[3], 1)
    local mask = box:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 1, -1); mask:SetPoint("BOTTOMRIGHT", -1, 1)
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetAllPoints(mask)
    box.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.icon:AddMaskTexture(mask)
    return box
end

-- Slim skill bar: track + fill, rounded, value text above its right end.
local function skillBar(parent, w)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(w, 6)
    ns.RoundedRect(b, -8, 0, 3, 0.05, 0.05, 0.06, 1)
    b.fillFrame = CreateFrame("Frame", nil, b)
    b.fillFrame:SetPoint("TOPLEFT"); b.fillFrame:SetPoint("BOTTOMLEFT")
    b.fill = ns.RoundedRect(b.fillFrame, -7, 0, 3, SKILL[1], SKILL[2], SKILL[3], 1)
    b.value = text(b, 10, true, T.textDim)
    b.value:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 4)
    function b:Set(cur, max, mod)
        if not (num(cur) and num(max) and max > 0) then self:Hide(); return end
        self:Show()
        self.fillFrame:SetWidth(math.max(6, w * math.min(1, cur / max)))
        local t = cur .. " / " .. max
        if num(mod) and mod > 0 then t = t .. string.format("  |cff8fd19e+%d|r", mod) end
        self.value:SetText(t)
        local done = cur >= max
        self.fill(done and 0.45 or SKILL[1], done and 0.85 or SKILL[2], done and 0.50 or SKILL[3], 1)
    end
    return b
end

-- Ability pill: a secure spell button styled like our pills.
local pillCount = 0
local function abilityPill(parent)
    pillCount = pillCount + 1
    local b = CreateFrame("Button", "MinimalUIProfBookPill" .. pillCount, parent, "SecureActionButtonTemplate")
    b:SetHeight(24)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:HookScript("PreClick", function() ns.profBookKeyAt = nil end)
    dragSpell(b)
    b.fs = text(b, 11, true)
    b.fs:SetPoint("LEFT", 30, 0)
    b.ic = b:CreateTexture(nil, "ARTWORK")
    b.ic:SetSize(16, 16)
    b.ic:SetPoint("LEFT", 8, 0)
    b.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.RoundedRect(b, -7, -1, 13, T.border[1], T.border[2], T.border[3], 1)
    b.paint = ns.EasePaint(b, ns.RoundedRect(b, -6, 0, 12, unpack(PILL_OFF)))
    b:HookScript("OnEnter", function(self)
        self.hover = true
        if not self.passive then self.paint(unpack(PILL_HOVER)) end
        ns.TipAnchor(self)
        if not (self.slot and pcall(GameTooltip.SetSpellBookItem, GameTooltip, self.slot, BANK))
                and not (self.spellID and pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)) then
            GameTooltip:SetText(self.fs:GetText() or "")
        end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function(self)
        self.hover = false
        self.paint(unpack(PILL_OFF))
        GameTooltip:Hide()
    end)
    return b
end

-- ── Data ──────────────────────────────────────────────────────────────────
local function profData(index)
    if not index then return nil end
    local name, icon, rank, maxRank, numSpells, offset, skillLine, mod = call(GetProfessionInfo, index)
    if not str(name) then return nil end
    local p = { name = name, icon = icon, rank = rank, max = maxRank, mod = mod, skillLine = skillLine, abilities = {} }
    if num(numSpells) and num(offset) then
        for i = 1, numSpells do
            local slot = offset + i
            local info = call(SB.GetSpellBookItemInfo, slot, BANK)
            if type(info) == "table" and str(info.name) then
                table.insert(p.abilities, { slot = slot, name = info.name, icon = info.iconID,
                    spellID = info.spellID or info.actionID, passive = info.isPassive, sub = str(info.subName) })
                -- The profession's own spell carries the rank title ("Apprentice").
                if not p.title and info.name == name and str(info.subName) then p.title = info.subName end
            end
        end
    end
    return p
end

-- ── Window ────────────────────────────────────────────────────────────────
local win
local pendingRefresh = false

local function fillAbilities(c, p)
    local combat = InCombatLockdown()
    -- The card opens the profession: its first active ability.
    local main
    for _, a in ipairs(p and p.abilities or {}) do
        if not a.passive then main = a; break end
    end
    c.main = main
    if not combat then
        c:SetAttribute("type1", main and "spell" or nil)
        c:SetAttribute("spell", main and (main.spellID or main.name) or nil)
    end
    -- Pills only when there's a choice (two or more abilities); a lone one
    -- would just repeat what the card does.
    local list = (p and #p.abilities > 1) and p.abilities or {}
    local x = 0
    local room = c:GetWidth() - c.pillX - 10
    for i, b in ipairs(c.pills) do
        local a = list[i]
        -- Skip pills that would run past the card's edge.
        if a then
            ns:SetFont(b.fs, 11, "", true)
            b.fs:SetText(a.name)
            if x + b.fs:GetStringWidth() + 44 > room then a = nil end
        end
        if a then
            b.slot, b.spellID, b.passive = a.slot, a.spellID, a.passive
            b.fs:SetText(a.name)
            b.fs:SetTextColor(unpack(a.passive and T.textDim or T.text))
            b.ic:SetTexture(a.icon)
            local w = math.floor(b.fs:GetStringWidth() + 44)
            if not combat then
                b:SetWidth(w)
                b:ClearAllPoints()
                b:SetPoint(c.pillAnchor, c, c.pillAnchor, c.pillX + (c.pillDir * x), c.pillY)
                b:SetAttribute("type1", (not a.passive) and "spell" or nil)
                b:SetAttribute("spell", (not a.passive) and (a.spellID or a.name) or nil)
                b:Show()
            end
            x = x + w + 6
        elseif not combat then
            b.slot, b.spellID = nil, nil
            b:SetAttribute("type1", nil); b:SetAttribute("spell", nil)
            b:Hide()
        end
    end
    if combat then pendingRefresh = true end
end

local EMPTY_PRIMARY = "Visit a profession trainer in a major city to learn a profession. You can have two, in any mix of gathering and crafting."
local SECONDARY = {
    { key = "cook", name = PROFESSIONS_COOKING or "Cooking", icon = "Interface/Icons/INV_Misc_Food_15",
      hint = "Visit a trainer to learn cooking: turn meat and fish into food that restores health and gives buffs." },
    { key = "fish", name = PROFESSIONS_FISHING or "Fishing", icon = "Interface/Icons/Trade_Fishing",
      hint = "Visit a trainer to learn fishing: catch fish and other strange things from water." },
    { key = "aid", name = PROFESSIONS_FIRST_AID or "First Aid", icon = "Interface/Icons/Spell_Holy_SealOfSacrifice",
      hint = "Visit a trainer to learn first aid: turn cloth into bandages for healing yourself and others." },
}

local function buildPrimary(i)
    local c = card(win, W - 36, PRIM_H)
    c:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(TOP + (i - 1) * (PRIM_H + 8)))
    c.box = iconBox(c, 44, 10)
    c.box:SetPoint("TOPLEFT", 14, -14)
    c.name = text(c, 14, true)
    c.name:SetPoint("TOPLEFT", c.box, "TOPRIGHT", 12, -4)
    c.title = text(c, 11, false, T.textDim)
    c.title:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -5)
    c.bar = skillBar(c, 220)
    c.bar:SetPoint("TOPRIGHT", c, "TOPRIGHT", -16, -32)
    c.unlearn = CreateFrame("Button", nil, c)
    c.unlearn:SetSize(60, 16)
    c.unlearn:SetPoint("BOTTOMRIGHT", -14, 16)
    c.unlearn.fs = text(c.unlearn, 10, false, T.textDim)
    c.unlearn.fs:SetPoint("RIGHT")
    c.unlearn.fs:SetText("Unlearn")
    c.unlearn:SetScript("OnEnter", function(self) self.fs:SetTextColor(unpack(RED)) end)
    c.unlearn:SetScript("OnLeave", function(self) self.fs:SetTextColor(unpack(T.textDim)) end)
    c.unlearn:SetScript("OnClick", function(self)
        local p = c.prof
        if not p or not p.skillLine then return end
        StaticPopup_Show("MINIMALUI_UNLEARN_PROFESSION", p.name, nil, p.skillLine)
    end)
    c.empty = text(c, 11, false, T.textDim)
    c.empty:SetPoint("LEFT", c.box, "RIGHT", 12, 0)
    c.empty:SetPoint("RIGHT", c, "RIGHT", -20, 0)
    c.empty:SetJustifyH("LEFT")
    c.empty:SetSpacing(3)
    c.pills = {}
    for k = 1, 4 do c.pills[k] = abilityPill(c) end
    c.pillAnchor, c.pillX, c.pillY, c.pillDir = "BOTTOMLEFT", 70, 12, 1
    return c
end

local function buildSecondary(i, w)
    local c = card(win, w, SEC_H)
    c:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + (i - 1) * (w + 8), -(TOP + PRIM_H * 2 + 8 + 12))
    c.box = iconBox(c, 36, 9)
    c.box:SetPoint("TOPLEFT", 12, -12)
    c.name = text(c, 13, true)
    c.name:SetPoint("TOPLEFT", c.box, "TOPRIGHT", 10, -2)
    c.title = text(c, 10, false, T.textDim)
    c.title:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
    c.bar = skillBar(c, w - 24)
    c.bar:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -78)
    c.empty = text(c, 10, false, T.textDim)
    c.empty:SetPoint("TOPLEFT", c.box, "BOTTOMLEFT", 0, -12)
    c.empty:SetWidth(w - 24)
    c.empty:SetJustifyH("LEFT")
    c.empty:SetSpacing(2)
    c.pills = {}
    for k = 1, 2 do c.pills[k] = abilityPill(c) end
    c.pillAnchor, c.pillX, c.pillY, c.pillDir = "BOTTOMLEFT", 12, 12, 1
    return c
end

local function fillPrimary(c, p)
    c.prof = p
    if p then
        c.box.icon:SetTexture(p.icon); c.box.icon:SetDesaturated(false); c.box:SetAlpha(1)
        c.name:SetText(p.name); c.name:SetTextColor(unpack(T.text))
        c.title:SetText(p.title or ""); c.title:Show()
        c.bar:Set(p.rank, p.max, p.mod)
        c.unlearn:Show()
        c.empty:Hide()
    else
        c.box.icon:SetTexture("Interface/Icons/INV_Misc_Book_09"); c.box.icon:SetDesaturated(true); c.box:SetAlpha(0.5)
        c.name:SetText("")
        c.title:Hide()
        c.bar:Hide()
        c.unlearn:Hide()
        c.empty:SetText(EMPTY_PRIMARY); c.empty:Show()
    end
    fillAbilities(c, p)
end

local function fillSecondary(c, p, def)
    c.prof = p
    if p then
        c.box.icon:SetTexture(p.icon); c.box.icon:SetDesaturated(false); c.box:SetAlpha(1)
        c.name:SetText(p.name); c.name:SetTextColor(unpack(T.text))
        c.title:SetText(p.title or "")
        c.bar:Set(p.rank, p.max, p.mod)
        c.empty:Hide()
    else
        c.box.icon:SetTexture(def.icon); c.box.icon:SetDesaturated(true); c.box:SetAlpha(0.5)
        c.name:SetText(def.name); c.name:SetTextColor(unpack(T.textDim))
        c.title:SetText("Not learned")
        c.bar:Hide()
        c.empty:SetText(def.hint); c.empty:Show()
    end
    fillAbilities(c, p)
end

function PB:Refresh()
    if not win or not win:IsShown() then return end
    local p1, p2, arch, fish, cook, aid = call(GetProfessions)
    local prim = { profData(p1), profData(p2) }
    local learned = (prim[1] and 1 or 0) + (prim[2] and 1 or 0)
    -- Learned ones first, so an empty slot is always the lower card.
    if not prim[1] and prim[2] then prim[1], prim[2] = prim[2], nil end
    fillPrimary(win.prim[1], prim[1])
    fillPrimary(win.prim[2], prim[2])
    local sec = { cook = profData(cook), fish = profData(fish), aid = profData(aid) }
    for i, def in ipairs(SECONDARY) do fillSecondary(win.sec[i], sec[def.key], def) end
    local sh = win.shell
    sh:SetChip(learned .. " of 2 professions", learned == 2 and { 0.45, 0.85, 0.50 } or T.accent)
    local a = profData(arch)
    sh:SetSubtitle(a and string.format("Primary professions and secondary skills   ·   %s %s / %s",
        a.name, tostring(a.rank), tostring(a.max)) or "Primary professions and secondary skills")
    sh:SetIcon((prim[1] and prim[1].icon) or "Interface/Icons/INV_Misc_Book_09")
end

local function build()
    win = CreateFrame("Frame", "MinimalUIProfessionsBook", UIParent)
    win:SetSize(W, H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        PB.db.pos = { p, rp, x, y }
    end)
    local pos = PB.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIProfessionsBook")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win)
    win.shell:SetTitle(TRADE_SKILLS or "Professions")
    win.shell:SetRing(SKILL)
    win.shell:SetSubtitleWidth(W - 220)

    win.prim = { buildPrimary(1), buildPrimary(2) }
    local sw = math.floor((W - 36 - 16) / 3)
    win.sec = {}
    for i = 1, 3 do win.sec[i] = buildSecondary(i, sw) end

    win.footer = ns:CreateFooter(win, FOOTER_H)
    local close = CreateFrame("Button", nil, win.footer)
    close:SetHeight(24)
    close.fs = text(close, 11, true)
    close.fs:SetPoint("CENTER")
    close.fs:SetText(CLOSE or "Close")
    close:SetWidth(close.fs:GetStringWidth() + 30)
    ns.RoundedRect(close, -7, -1, 13, T.border[1], T.border[2], T.border[3], 1)
    close.paint = ns.EasePaint(close, ns.RoundedRect(close, -6, 0, 12, unpack(PILL_OFF)))
    close:SetScript("OnEnter", function(self) self.hover = true; self.paint(unpack(PILL_HOVER)) end)
    close:SetScript("OnLeave", function(self) self.hover = false; self.paint(unpack(PILL_OFF)) end)
    close:SetScript("OnClick", function() win:Hide() end)
    close:SetPoint("LEFT", win.footer, "LEFT", 14, 0)

    win:SetScript("OnShow", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN)
        PB:Refresh()
    end)
    win:SetScript("OnHide", function()
        GameTooltip:Hide()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE)
    end)
end

function PB:Open()
    if InCombatLockdown() and not win then return false end -- secure pills can't be made in combat
    if not win then build() end
    win:Show()
    return true
end

function PB:Toggle()
    if win and win:IsShown() then win:Hide() else self:Open() end
end

-- ── Taking over Blizzard's book ───────────────────────────────────────────
-- K runs ToggleProfessionsBook, which shows ProfessionsFrame with no
-- profession open. Hide that and toggle ours instead. (With a profession
-- open, the frame belongs to the crafting window: left alone here.)
local function blizzBookShown()
    local f = _G.ProfessionsFrame
    return f and f:IsShown() and not ns.profTradeOpen
end

local function hideBlizz()
    local f = _G.ProfessionsFrame
    if f and f:IsShown() and not ns.profTradeOpen then
        if HideUIPanel then HideUIPanel(f) else f:Hide() end
    end
end

local function hookBlizz()
    local f = _G.ProfessionsFrame
    if not f or f.__muiBookHooked then return end
    f.__muiBookHooked = true
    f:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if PB.toggling or not blizzBookShown() then return end
            hideBlizz()
            PB:Open()
        end)
    end)
end

function PB:OnInit(db)
    self.db = db
    if not InCombatLockdown() then build() end -- secure pills: make them now
    StaticPopupDialogs["MINIMALUI_UNLEARN_PROFESSION"] = {
        text = "Unlearn %s?\nYou'll lose all skill and recipes in it.",
        button1 = "Unlearn", button2 = CANCEL or "Cancel",
        OnAccept = function(_, skillLine) call(_G.AbandonSkill, skillLine) end,
        timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    }
    if _G.ToggleProfessionsBook then
        hooksecurefunc("ToggleProfessionsBook", function()
            local now = GetTime()
            -- K while a crafting window was open: Blizzard's toggle just
            -- closed it. That's the whole action; don't open the book too.
            if ns.profTradeClosedAt == now and ns.profTradeShownAt ~= now then return end
            ns.profBookKeyAt = now
            if ns.profTradeOpen then
                -- Opened during this same toggle = Blizzard reopening the
                -- last profession. Undo it and treat K as the book key.
                if ns.profTradeShownAt ~= now then return end
                if ns.ProfSuppressTrade then ns.ProfSuppressTrade() end
            end
            local wasOpen = win and win:IsShown()
            PB.toggling = true
            hideBlizz()
            if wasOpen then win:Hide() else PB:Open() end
            C_Timer.After(0, function() PB.toggling = false end)
        end)
    end
    hookBlizz()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_LOADED", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "SPELLS_CHANGED",
                         "PLAYER_REGEN_ENABLED", "TRADE_SKILL_SHOW" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e)
        if e == "ADDON_LOADED" then hookBlizz(); return end
        if e == "TRADE_SKILL_SHOW" then
            -- A profession opened: the craft window takes over from the book
            -- (checked next frame, after a K auto-reopen has been undone).
            C_Timer.After(0, function()
                if ns.profTradeOpen and win and win:IsShown() and not InCombatLockdown() then win:Hide() end
            end)
            return
        end
        if e == "PLAYER_REGEN_ENABLED" then
            if not pendingRefresh then return end
            pendingRefresh = false
        end
        PB:Refresh()
    end)
end

ns.commands.profbook = function() PB:Toggle() end
