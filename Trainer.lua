local _, ns = ...
local T = ns.Theme

-- Trainer: Meniscus's trainer window (shared header with the trainer's 3D
-- head; "N to learn" chip; Train all and Show unavailable pills). Spells as
-- cards: icon, name and rank, cost (red when you can't afford it), and a
-- level chip for ones you can't learn yet. Click a card to learn it.
-- Blizzard's trainer frame stays open but invisible.

local TR = ns:NewModule("Trainer", { enabled = true, showUnavailable = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local W = 460
local ROW_H = 44
local ROWS = 9
local LIST_TOP = (ns.SHELL_H or 92) + 14
local FOOT_H = 50
local H = LIST_TOP + ROWS * ROW_H + 18 + FOOT_H
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local CARD = { 0.10, 0.10, 0.115, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local GREEN = { 0.45, 0.85, 0.50, 1 }

local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not secret(v) end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local PILL_OPTS = { h = 22, pad = 24, minW = 50 }
local function pill(parent, label, onClick)
    return ns.Pill(parent, label, onClick, PILL_OPTS)
end

local function money(c, red)
    if not num(c) or c <= 0 then return "" end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    local col = red and "|cfff26b66" or "|cffeeeef2"
    if g > 0 then table.insert(parts, col .. g .. "|r|cffe6c25a g|r") end
    if s > 0 then table.insert(parts, col .. s .. "|r|cffb8bcc6 s|r") end
    if cp > 0 then table.insert(parts, col .. cp .. "|r|cffc98a52 c|r") end
    return table.concat(parts, " ")
end

-- ── Ranks ─────────────────────────────────────────────────────────────────
-- Forever's GetTrainerServiceInfo has no rank, so read the service's spell
-- from a hidden tooltip (SetTrainerService + GetSpell) and take its rank
-- from the spell's subtext ("Rank 2"), or from the tooltip's rank text.
local scan
local function serviceSpell(i)
    if not scan then
        scan = CreateFrame("GameTooltip", "MinimalUITrainerScan", UIParent, "GameTooltipTemplate")
    end
    scan:SetOwner(UIParent, "ANCHOR_NONE")
    scan:ClearLines()
    if not pcall(scan.SetTrainerService, scan, i) then return end
    local _, id = call(scan.GetSpell, scan)
    local rank = id and call(C_Spell and C_Spell.GetSpellSubtext, id)
    if not (type(rank) == "string" and rank:find("%d")) then
        rank = nil
        for _, side in ipairs({ "Right", "Left" }) do
            for l = 1, math.min(scan:NumLines(), 3) do
                local fs = _G["MinimalUITrainerScan" .. "Text" .. side .. l]
                local t = fs and fs:GetText()
                if type(t) == "string" and not secret(t) and t:match("^%a+ %d+$") then rank = t end
            end
        end
    end
    scan:Hide()
    return id, rank
end

local function rankNum(r) return type(r) == "string" and tonumber(r:match("(%d+)")) end

-- What you already know, by spell name: the highest rank and its spell.
local known
local function knownSpells()
    if known then return known end
    known = {}
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local lines = call(SB and SB.GetNumSpellBookSkillLines) or 0
    for l = 1, (num(lines) and lines or 0) do
        local info = call(SB.GetSpellBookSkillLineInfo, l)
        if type(info) == "table" then
            local first = (info.itemIndexOffset or 0) + 1
            for slot = first, first + (info.numSpellBookItems or 0) - 1 do
                local s = call(SB.GetSpellBookItemInfo, slot, bank)
                if type(s) == "table" and type(s.name) == "string" then
                    local id = s.spellID or s.actionID
                    local sub = s.subName
                    if not (type(sub) == "string" and sub:find("%d")) and id then
                        sub = call(C_Spell and C_Spell.GetSpellSubtext, id)
                    end
                    local n = rankNum(sub) or 0
                    local k = known[s.name]
                    if not k or n > k.n then known[s.name] = { n = n, id = id, rank = sub } end
                end
            end
        end
    end
    return known
end

-- Same text with the numbers blanked: two ranks line up when these match.
local function shape(s) return (s:gsub("%d+%.?%d*", "#")) end

-- Old vs new rank text, like an item's stat comparison. Returns:
--   new text with a green "(+15)" after each changed number (the number
--   itself keeps the line's color), and the old text with its changed
--   numbers in red. Nil when the texts don't line up or nothing changed.
local function compareText(old, new)
    if type(old) ~= "string" or type(new) ~= "string" or secret(old) or secret(new) then return end
    if shape(old) ~= shape(new) then return end
    local olds, news = {}, {}
    for n in old:gmatch("%d+%.?%d*") do olds[#olds + 1] = tonumber(n) end
    for n in new:gmatch("%d+%.?%d*") do news[#news + 1] = tonumber(n) end
    local i, changed = 0, false
    local newOut = new:gsub("%d+%.?%d*", function(s)
        i = i + 1
        local v, was = tonumber(s), olds[i]
        if not (v and was) or v == was then return s end
        changed = true
        local d = v - was
        local ds = (d == math.floor(d)) and string.format("%+d", d) or string.format("%+.1f", d)
        return string.format("%s |cff5fd38a(%s)|r", s, ds)
    end)
    if not changed then return end
    i = 0
    local oldOut = old:gsub("%d+%.?%d*", function(s)
        i = i + 1
        if tonumber(s) == news[i] then return s end
        return "|cffe06060" .. s .. "|r"
    end)
    return newOut, oldOut
end

-- ── Data ──────────────────────────────────────────────────────────────────
local function services()
    known = nil -- re-read the spellbook each refresh (you may just have learned something)
    local list, avail = {}, 0
    local n = call(_G.GetNumTrainerServices) or 0
    for i = 1, (num(n) and n or 0) do
        local name, rank, category, expanded = call(_G.GetTrainerServiceInfo, i)
        -- Two shapes exist: classic (name, rank, type, expanded) and modern
        -- (name, type, icon, levelReq). Detect by where the type word sits.
        local icon, levelReq
        local TYPES = { available = true, unavailable = true, used = true, header = true }
        if type(rank) == "string" and TYPES[rank] and not TYPES[category] then
            icon, levelReq = category, expanded
            category, rank, expanded = rank, nil, true
        end
        if name then
            if category == "header" then
                table.insert(list, { header = true, name = name, index = i, expanded = expanded })
            elseif category ~= "used" and (category == "available" or TR.db.showUnavailable) then
                if category == "available" then avail = avail + 1 end
                -- Profession trainers: the skill each recipe needs.
                local skillName, skillRank, skillMet = call(_G.GetTrainerServiceSkillReq, i)
                local spellID, scanRank = serviceSpell(i)
                if not (type(rank) == "string" and rank ~= "") then rank = scanRank end
                local have = knownSpells()[name]
                table.insert(list, { spellID = spellID, have = have, skillName = skillName, skillRank = skillRank, skillMet = (skillMet and skillMet ~= 0) or category == "available", name = name, rank = rank, index = i, available = category == "available",
                                     cost = call(_G.GetTrainerServiceCost, i),
                                     level = call(_G.GetTrainerServiceLevelReq, i) or levelReq,
                                     icon = call(_G.GetTrainerServiceIcon, i) or icon })
            end
        end
    end
    return list, avail
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, rows, offset, data = nil, {}, 0, {}
local closing = false
local trainingAll = false

local function makeRow(i)
    local r = CreateFrame("Button", nil, win)
    r:SetSize(W - 44, ROW_H - 6)
    r:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(LIST_TOP + (i - 1) * ROW_H))
    r.ring = ns.RoundedRect(r, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
    r.fill = ns.RoundedRect(r, -7, 1, 9, unpack(CARD))
    local box = CreateFrame("Frame", nil, r)
    box:SetSize(30, 30)
    box:SetPoint("LEFT", 5, 0)
    ns.RoundedRect(box, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    local mask = box:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2); mask:SetPoint("BOTTOMRIGHT", -2, 2)
    r.icon = box:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints(mask)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:AddMaskTexture(mask)
    r.box = box
    r.name = text(r, 12, true)
    r.name:SetPoint("TOPLEFT", box, "TOPRIGHT", 10, -2)
    r.name:SetJustifyH("LEFT")
    r.sub = text(r, 10, false, T.textDim)
    r.sub:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 10, 2)
    r.cost = text(r, 11, true)
    r.cost:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    r.chip = CreateFrame("Frame", nil, r)
    r.chip:SetSize(44, 16)
    r.chip:SetPoint("RIGHT", r.cost, "LEFT", -8, 0)
    ns.RoundedRect(r.chip, -6, 0, 8, 0.18, 0.18, 0.2, 1)
    r.chipText = text(r.chip, 10, true, T.textDim)
    r.chipText:SetPoint("CENTER")
    r.head = text(r, 11, true, T.textDim)
    r.head:SetPoint("LEFT", 6, 0)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e or e.header then return end
        self.ring(unpack(e.available and T.accent or T.border)); self.fill(0.13, 0.13, 0.15, 1)
        ns.TipAnchor(self)
        if not pcall(GameTooltip.SetTrainerService, GameTooltip, e.index) then GameTooltip:SetText(e.name) end
        -- Rank, and what changes from the rank you have.
        local have = e.have
        if e.rank and not secret(e.rank) then
            GameTooltip:AddLine(e.rank .. (have and have.n > 0 and ("  (you have Rank " .. have.n .. ")") or ""), 0.6, 0.6, 0.65)
        end
        if have and have.id and e.spellID and have.id ~= e.spellID then
            local GD = C_Spell and C_Spell.GetSpellDescription
            local newOut, oldOut = compareText(call(GD, have.id), call(GD, e.spellID))
            if newOut then
                -- The changes go into the tooltip's own (yellow) description
                -- line; the rank you have follows below, its old numbers red.
                local target = shape(call(GD, e.spellID))
                local placed = false
                for l = 1, GameTooltip:NumLines() do
                    local fs = _G["GameTooltipTextLeft" .. l]
                    local t = fs and fs:GetText()
                    if type(t) == "string" and not secret(t) and shape(t) == target then
                        fs:SetText(newOut)
                        placed = true
                        break
                    end
                end
                if not placed then GameTooltip:AddLine(newOut, 1, 0.82, 0, true) end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(have.n > 0 and ("Rank " .. have.n .. ":") or "What you know now:", 0.6, 0.6, 0.65)
                GameTooltip:AddLine(oldOut, 0.85, 0.85, 0.88, true)
            end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        local e = self.entry
        if e and not e.header then
            self.ring(T.border[1], T.border[2], T.border[3], 1); self.fill(unpack(CARD))
        end
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.header then
            call(e.expanded and _G.CollapseTrainerSkillLine or _G.ExpandTrainerSkillLine, e.index)
            return
        end
        if e.available then call(_G.BuyTrainerService, e.index) end
    end)
    return r
end

local function fillRow(r, e)
    r.entry = e
    if not e then r:Hide(); return end
    r:Show()
    if e.header then
        r.ring(0, 0, 0, 0); r.fill(0, 0, 0, 0)
        r.box:Hide(); r.name:Hide(); r.sub:Hide(); r.cost:Hide(); r.chip:Hide()
        r.head:SetText(e.name); r.head:Show()
        return
    end
    r.head:Hide()
    r.box:Show(); r.name:Show(); r.sub:Show(); r.cost:Show()
    r.ring(T.border[1], T.border[2], T.border[3], 1); r.fill(unpack(CARD))
    r.icon:SetTexture(e.icon)
    r.icon:SetDesaturated(not e.available)
    r.name:SetText(e.name)
    r.name:SetTextColor(unpack(e.available and T.text or T.textDim))
    local rank = (e.rank and not secret(e.rank) and e.rank ~= "") and e.rank or nil
    -- Say whether it's new or replaces a rank you have.
    if rank and e.have then
        rank = rank .. "  ·  upgrade" .. (e.have.n > 0 and (" from " .. e.have.n) or "")
    elseif rank and e.skillRank == nil and not e.have and e.spellID then
        rank = rank .. "  ·  new"
    end
    local needSkill = num(e.skillRank) and e.skillRank > 0
    if e.available then
        r.sub:SetText(rank and (rank .. "  ·  |cff5fd38aLearnable|r") or "|cff5fd38aLearnable|r")
    elseif needSkill and not e.skillMet then
        r.sub:SetText(string.format("Requires %s %d", type(e.skillName) == "string" and e.skillName or "skill", e.skillRank))
    else
        r.sub:SetText(rank or "")
    end
    r.icon:SetAlpha(e.available and 1 or 0.55)
    r.box:SetAlpha(e.available and 1 or 0.7)
    local myMoney = GetMoney()
    r.cost:SetText(money(e.cost, num(e.cost) and num(myMoney) and e.cost > myMoney))
    -- Chip: the skill a recipe needs (green when you have it), else the
    -- level a spell needs.
    if needSkill then
        r.chipText:SetText("Skill " .. e.skillRank)
        r.chipText:SetTextColor(unpack(e.skillMet and GREEN or { 0.95, 0.45, 0.42, 1 }))
        r.chip:SetWidth(r.chipText:GetStringWidth() + 16)
        r.chip:Show()
    elseif not e.available and num(e.level) and e.level > 0 then
        r.chipText:SetText("Lv " .. e.level)
        r.chipText:SetTextColor(unpack(T.textDim))
        r.chip:SetWidth(r.chipText:GetStringWidth() + 16)
        r.chip:Show()
    else
        r.chip:Hide()
    end
    r.name:SetPoint("RIGHT", r.chip:IsShown() and r.chip or r.cost, "LEFT", -8, 0)
end

local function scroll(delta)
    offset = math.max(0, math.min(offset - delta * 3, math.max(0, #data - ROWS)))
    for i, r in ipairs(rows) do fillRow(r, data[i + offset]) end
end

function TR:Refresh()
    if not win or not win:IsShown() then return end
    local avail
    data, avail = services()
    scroll(0)
    win.empty:SetShown(#data == 0)
    local sh = win.shell
    sh:SetTitle(UnitExists("npc") and UnitName("npc") or (TRAINER or "Trainer"))
    local greet = call(_G.GetTrainerGreetingText)
    local zone = GetSubZoneText and GetSubZoneText()
    if not zone or zone == "" then zone = GetZoneText and GetZoneText() end
    sh:SetSubtitle(zone or "")
    win.money:SetText(money(GetMoney()))
    -- The count lives on the button; the chip shows the trainer's attitude.
    win.trainAll:SetLabel(avail > 0 and string.format("Train all (%d)", avail) or "Train all")
    win.trainAll:SetEnabled(avail > 0)
    win.unavail.on = self.db.showUnavailable
    win.unavail:Repaint()
    -- Train all: keep learning the first affordable spell after each update.
    if trainingAll then
        local myMoney = GetMoney()
        for _, e in ipairs(data) do
            if not e.header and e.available and (not num(e.cost) or e.cost <= myMoney) then
                call(_G.BuyTrainerService, e.index)
                return
            end
        end
        trainingAll = false
    end
end

local function build()
    win = CreateFrame("Frame", "MinimalUITrainer", UIParent)
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
        TR.db.pos = { p, rp, x, y }
    end)
    local pos = TR.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -140) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUITrainer")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win)
    win.shell:SetRing({ 0.45, 0.85, 0.50 })
    -- Footer: what you have to spend on the left, the actions on the right
    -- (the header keeps to who the trainer is).
    local foot = ns:CreateFooter(win, FOOT_H)
    win.foot = foot
    local lbl = text(foot, 10, false, T.textDim)
    lbl:SetPoint("LEFT", foot, "LEFT", 20, 0)
    lbl:SetText("YOUR MONEY")
    win.money = text(foot, 12, true)
    win.money:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    win.trainAll = pill(foot, "Train all", function() trainingAll = true; TR:Refresh() end)
    win.trainAll:SetPoint("RIGHT", foot, "RIGHT", -14, 0)
    win.unavail = pill(foot, "Show unavailable", function(self)
        TR.db.showUnavailable = not TR.db.showUnavailable
        TR:Refresh()
    end)
    win.unavail:SetPoint("RIGHT", win.trainAll, "LEFT", -6, 0)

    for i = 1, ROWS do rows[i] = makeRow(i) end
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, d) scroll(d) end)
    win.empty = text(win, 11, false, T.textDim)
    win.empty:SetPoint("TOP", win, "TOP", 0, -(LIST_TOP + 40))
    win.empty:SetText("Nothing to learn here right now.")

    win:SetScript("OnHide", function()
        trainingAll = false
        win.shell:ClearModel()
        if not closing then call(_G.CloseTrainer) end
    end)
end

local function ghost(f)
    if not f or f.__muiGhost then return end
    f.__muiGhost = true
    local function apply(self) self:SetAlpha(0); self:SetScale(0.001); self:EnableMouse(false) end
    f:HookScript("OnShow", apply)
    if f:IsShown() then apply(f) end
end

local function open()
    if not win then build() end
    offset = 0
    ghost(_G.ClassTrainerFrame)
    win.shell:SetUnit("npc")
    win.shell:SetAttitude("npc")
    if not win:IsShown() then win:Show() end
    TR:Refresh()
end

local function close()
    if win and win:IsShown() then
        closing = true
        win:Hide()
        closing = false
    end
end

function TR:OnInit(db)
    self.db = db
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_CLOSED", "TRAINER_UPDATE", "PLAYER_MONEY", "ADDON_LOADED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e, arg)
        if e == "ADDON_LOADED" then
            if arg == "Blizzard_TrainerUI" then ghost(_G.ClassTrainerFrame) end
        elseif e == "TRAINER_SHOW" then
            -- Blizzard loads and shows its frame on this event too; ghost it next frame.
            C_Timer.After(0, function() ghost(_G.ClassTrainerFrame); open() end)
        elseif e == "TRAINER_CLOSED" then close()
        else TR:Refresh() end
    end)
end
