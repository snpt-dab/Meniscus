local _, ns = ...
local CreateFrame = ns.CreateFrame
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
local HEAD_H = 26                 -- a heading's share of the list (a row's is ROW_H)
local AREA = ROWS * ROW_H         -- the list's height
local FRAMES = ROWS + 6           -- row frames: headings are slim, so more than ROWS can be in view
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
    if g > 0 then table.insert(parts, col .. g .. "|r|TInterface/AddOns/Meniscus/Media/circle.tga:9:9:2:0:32:32:0:32:0:32:230:194:90|t") end
    if s > 0 then table.insert(parts, col .. s .. "|r|TInterface/AddOns/Meniscus/Media/circle.tga:9:9:2:0:32:32:0:32:0:32:184:188:198|t") end
    if cp > 0 then table.insert(parts, col .. cp .. "|r|TInterface/AddOns/Meniscus/Media/circle.tga:9:9:2:0:32:32:0:32:0:32:201:138:82|t") end
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
-- A profession's own next level ("Expert Mining") is not one more recipe:
-- those are lifted out into a section of their own at the top of the list.
-- Known by its name: a level's word, then the profession the trainer's
-- other entries ask for.
local TIERS = { "Apprentice", "Journeyman", "Expert", "Artisan", "Master", "Grand Master", "Illustrious", "Zen Master" }
local function isTier(name, skills)
    if type(name) ~= "string" or secret(name) then return false end
    for i = 1, #TIERS do
        local t = TIERS[i]
        if name:sub(1, #t + 1) == t .. " " then
            local rest = name:sub(#t + 2)
            if skills[rest] or next(skills) == nil then return true end
        end
    end
    return false
end
local function sectioned(list)
    local skills = {}
    for _, e in ipairs(list) do
        if type(e.skillName) == "string" and not secret(e.skillName) then skills[e.skillName] = true end
    end
    local top, rest = {}, {}
    for _, e in ipairs(list) do
        if not e.header and isTier(e.name, skills) then top[#top + 1] = e else rest[#rest + 1] = e end
    end
    if #top == 0 then return list end
    local out = { { header = true, section = true, name = "Skill level" } }
    for _, e in ipairs(top) do out[#out + 1] = e end
    if #rest > 0 and not rest[1].header then
        out[#out + 1] = { header = true, section = true, name = next(skills) and "Recipes" or "Everything else" }
    end
    for _, e in ipairs(rest) do out[#out + 1] = e end
    return out
end
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
    return sectioned(list), avail
end

-- Your own level in a skill, by its name (0.1.630: shown on the header at a
-- profession trainer, where every row says what it needs and nothing said
-- what you have). The skill list first, then the professions.
local PROF_EMBLEM = {
    ["Alchemy"] = "potion", ["Blacksmithing"] = "profession", ["Cooking"] = "food", ["Enchanting"] = "stat_spell",
    ["Engineering"] = "prof_gear", ["First Aid"] = "prof_aid", ["Fishing"] = "prof_hook", ["Herbalism"] = "prof_herb",
    ["Leatherworking"] = "prof_hide", ["Mining"] = "prof_pick", ["Skinning"] = "skin", ["Tailoring"] = "prof_needle",
}
local function mySkill(want)
    local S = C_SkillInfo
    local getNum = (S and S.GetNumSkillLines) or _G.GetNumSkillLines
    local getInfo = (S and S.GetSkillLineInfo) or _G.GetSkillLineInfo
    if getNum and getInfo then
        local n = call(getNum)
        for i = 1, (num(n) and n or 0) do
            local name, _, _, rank, _, _, max = call(getInfo, i)
            if type(name) == "table" then
                local t = name
                name, rank, max = t.skillName or t.name, t.skillRank or t.rank or t.currentRank, t.skillMaxRank or t.maxRank
            end
            if name == want and num(rank) then
                local SP = C_Spell
                local icon = SP and SP.GetSpellTexture and call(SP.GetSpellTexture, want)
                return rank, num(max) and max or nil, icon
            end
        end
    end
    if _G.GetProfessions and _G.GetProfessionInfo then
        local a, b, c, d, e, f = call(GetProfessions)
        for _, idx in ipairs({ a or false, b or false, c or false, d or false, e or false, f or false }) do
            if idx then
                local name, icon, rank, max = call(GetProfessionInfo, idx)
                if name == want and num(rank) then return rank, num(max) and max or nil, icon end
            end
        end
    end
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
    r.head = text(r, 10, true, T.textDim)
    r.head:SetPoint("LEFT", 4, -2)
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetHeight(1)
    r.rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    r.rule:SetPoint("LEFT", r.head, "RIGHT", 10, 0)
    r.rule:SetPoint("RIGHT", r, "RIGHT", -2, -2)
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
            if not e.section then call(e.expanded and _G.CollapseTrainerSkillLine or _G.ExpandTrainerSkillLine, e.index) end
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
        r:SetHeight(HEAD_H - 6)
        r.ring(0, 0, 0, 0); r.fill(0, 0, 0, 0)
        r.box:Hide(); r.name:Hide(); r.sub:Hide(); r.cost:Hide(); r.chip:Hide()
        r.head:SetText(e.name); r.head:Show(); r.rule:Show()
        return
    end
    r:SetHeight(ROW_H - 6)
    r.head:Hide(); r.rule:Hide()
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

-- Headings take less room than rows, so the list is laid out from the top
-- by each entry's own height, and how far it can be scrolled is found by
-- walking up from the end until the window is full.
local function tall(e) return e.header and HEAD_H or ROW_H end
local function lastOffset()
    local sum, first = 0, #data + 1
    for i = #data, 1, -1 do
        sum = sum + tall(data[i])
        if sum > AREA + 0.5 then break end
        first = i
    end
    return math.max(0, first - 1)
end
local barDrag
local function scroll(delta, to)
    local maxOff = lastOffset()
    offset = math.max(0, math.min(to or (offset - delta * 2), maxOff))
    local y, idx, shown = 0, offset, 0
    for _, r in ipairs(rows) do
        local e = data[idx + 1]
        if e and y + tall(e) <= AREA + 0.5 then
            idx = idx + 1
            shown = shown + 1
            r:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(LIST_TOP + y))
            fillRow(r, e)
            y = y + tall(e)
        else
            idx = #data -- (nothing after the first that does not fit)
            fillRow(r, nil)
        end
    end
    -- The scroll bar: there only when there is more than fits.
    local track = win.track
    if maxOff > 0 then
        local th = math.max(28, AREA * shown / #data)
        win.thumb:SetHeight(th)
        win.thumb:SetPoint("TOP", track, "TOP", 0, -(AREA - 6 - th) * (offset / maxOff))
        track.maxOff, track.th = maxOff, th
        track:Show()
    else
        track:Hide()
    end
    if barDrag then return end
    -- The rows have new contents under a mouse that hasn't moved (you just
    -- learned the one it was on, or turned the wheel): show the tooltip of
    -- what is under it now, or none.
    for _, r in ipairs(rows) do
        if r:IsShown() and r:IsMouseOver() then
            local enter = r:GetScript("OnEnter")
            if enter then pcall(enter, r) end
            return
        end
    end
    for _, r in ipairs(rows) do
        if GameTooltip:IsOwned(r) then GameTooltip:Hide() end
    end
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
    -- Your level in what is taught here (up to two skills), on the band:
    -- the skill's icon and the numbers, its name on hover (0.1.632).
    local seen, shown = {}, 0
    for _, e in ipairs(data) do
        local sn = e.skillName
        if type(sn) == "string" and sn ~= "" and not seen[sn] and shown < 2 then
            seen[sn] = true
            local rank, max, icon = mySkill(sn)
            if rank then
                shown = shown + 1
                local b = win.skills[shown]
                b.name, b.rank, b.max = sn, rank, max
                b.fs:SetText(max and (rank .. " / " .. max) or tostring(rank))
                b.icon:SetTexture(MEDIA .. "micro_" .. (PROF_EMBLEM[sn] or "profession") .. ".tga")
                -- (First aid: a little white case with a red cross on it, in
                -- the same ring as the rest. A bare white cross read as a
                -- "plus" button: 0.1.636.)
                if sn == "First Aid" then
                    b.icon:SetTexture(MEDIA .. "micro_prof_kit.tga")
                    b.icon:SetSize(16, 16)
                    b.over:SetTexture(MEDIA .. "micro_prof_aid.tga")
                    b.over:SetVertexColor(0.86, 0.18, 0.16)
                    b.over:Show()
                    b.rim:SetVertexColor(0.86, 0.86, 0.89, 1)
                else
                    b.icon:SetSize(13, 13)
                    b.over:Hide()
                    b.rim:SetVertexColor(0.42, 0.42, 0.47, 1)
                end
                b.fill:SetVertexColor(0.06, 0.06, 0.07, 1)
                b.icon:SetVertexColor(T.text[1], T.text[2], T.text[3])
                b:SetWidth(22 + 6 + b.fs:GetStringWidth())
                b:Show()
            end
        end
    end
    for i = shown + 1, #win.skills do win.skills[i]:Hide() end
    -- The count lives on the button; the chip shows the trainer's attitude.
    win.trainAll:SetLabel(avail > 0 and string.format("Train all (%d)", avail) or "Train all")
    win.trainAll:SetEnabled(avail > 0)
    win.unavail.on = self.db.showUnavailable
    win.unavail:Repaint()
    -- Train all: every one you can afford, asked for there and then, inside
    -- the click itself. (It used to learn one, wait for the list to come
    -- back, and learn the next from there: but buying is something the game
    -- only lets an addon do as part of a click, and every one after the
    -- first raised its "blocked from an action" box.) From the bottom of
    -- the list up, so one being learned can't shift those still to come.
    if trainingAll then
        trainingAll = false
        local left = GetMoney()
        if not num(left) then left = math.huge end
        for i = #data, 1, -1 do
            local e = data[i]
            if not e.header and e.available then
                local cost = num(e.cost) and e.cost or 0
                if cost <= left then
                    left = left - cost
                    call(_G.BuyTrainerService, e.index)
                end
            end
        end
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
    win.skills = {}
    for i = 1, 2 do
        local b = CreateFrame("Frame", nil, win)
        b:SetSize(80, 22)
        if i == 1 then b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -20, -58)
        else b:SetPoint("RIGHT", win.skills[1], "LEFT", -14, 0) end
        -- (Our own emblem in a ring, as on the inspection panel: 0.1.633.)
        local box = CreateFrame("Frame", nil, b)
        box:SetSize(22, 22)
        box:SetPoint("LEFT")
        local rim = box:CreateTexture(nil, "ARTWORK", nil, 0)
        rim:SetTexture(MEDIA .. "circle.tga")
        rim:SetAllPoints()
        rim:SetVertexColor(0.42, 0.42, 0.47, 1)
        local fill = box:CreateTexture(nil, "ARTWORK", nil, 1)
        b.rim, b.fill = rim, fill
        fill:SetTexture(MEDIA .. "circle.tga")
        fill:SetPoint("TOPLEFT", 1.5, -1.5)
        fill:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
        fill:SetVertexColor(0.06, 0.06, 0.07, 1)
        b.icon = box:CreateTexture(nil, "OVERLAY")
        b.icon:SetSize(13, 13)
        b.icon:SetPoint("CENTER")
        b.icon:SetVertexColor(T.text[1], T.text[2], T.text[3])
        b.over = box:CreateTexture(nil, "OVERLAY", nil, 1) -- (a second colour laid on the emblem)
        b.over:SetAllPoints(b.icon)
        b.over:Hide()
        b.fs = text(b, 12, true)
        b.fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            ns.TipAnchor(self)
            GameTooltip:SetText(self.name or "", 1, 1, 1)
            GameTooltip:AddLine(self.max and string.format("Your skill: %d of %d", self.rank, self.max)
                or ("Your skill: " .. tostring(self.rank)), 0.7, 0.7, 0.75)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if win.shell.Lift then win.shell:Lift(b) end
        box:SetFrameLevel(b:GetFrameLevel() + 1)
        b:Hide()
        win.skills[i] = b
    end
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

    for i = 1, FRAMES do rows[i] = makeRow(i) end
    -- The scroll bar, down the right of the list: a rail with a lighter
    -- thumb. Click or drag anywhere on the rail.
    local track = CreateFrame("Frame", nil, win)
    track:SetSize(12, AREA - 6)
    track:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -LIST_TOP)
    track:EnableMouse(true)
    track:Hide()
    local rail = track:CreateTexture(nil, "BACKGROUND")
    rail:SetWidth(4)
    rail:SetPoint("TOP"); rail:SetPoint("BOTTOM")
    rail:SetColorTexture(0.13, 0.13, 0.15, 1)
    win.thumb = track:CreateTexture(nil, "ARTWORK")
    win.thumb:SetWidth(4)
    win.thumb:SetColorTexture(0.42, 0.42, 0.47, 1)
    win.thumb:SetPoint("TOP")
    local function follow(self)
        local _, cy = GetCursorPosition()
        local top = self:GetTop()
        if not (cy and top and self.maxOff) then return end
        cy = cy / self:GetEffectiveScale()
        local room = (AREA - 6) - self.th
        local frac = room > 0 and (top - cy - self.th / 2) / room or 0
        frac = math.max(0, math.min(1, frac))
        local to = math.floor(frac * self.maxOff + 0.5)
        if to ~= offset then scroll(0, to) end
    end
    track:SetScript("OnMouseDown", function(self)
        barDrag = true
        win.thumb:SetColorTexture(0.62, 0.62, 0.68, 1)
        follow(self)
        self:SetScript("OnUpdate", follow)
    end)
    local function drop(self)
        barDrag = nil
        win.thumb:SetColorTexture(0.42, 0.42, 0.47, 1)
        self:SetScript("OnUpdate", nil)
    end
    track:SetScript("OnMouseUp", drop)
    track:SetScript("OnHide", drop)
    win.track = track
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

-- TR.pass: this is not an NPC's list but one a spell of yours opened (a
-- hunter's Beast Training, out in the world): the game's own window is left
-- in charge. Teaching a pet from our window raised the game's "blocked from
-- an action" box: what the game's window does there is evidently more than
-- the plain "buy" an addon may make from a click.
-- (0.1.746, asked for) The game's window in our look, for as long as it is
-- the one in charge. Recolouring only: nothing of the game's is replaced
-- or moved, and teaching stays the game's own click. The rows are made
-- anew as the list scrolls, so they are gone over a few times a second
-- while the window shows.
local function petDressRow(b)
    if b.__muiPetRow then return end
    b.__muiPetRow = true
    local function grey(t, r, g, bl, a)
        if t and t.SetDesaturated then
            pcall(t.SetDesaturated, t, true)
            pcall(t.SetVertexColor, t, r, g, bl, a or 1)
        end
    end
    if b.GetNormalTexture then grey(b:GetNormalTexture(), 0.30, 0.30, 0.34) end
    if b.GetHighlightTexture then grey(b:GetHighlightTexture(), 0.55, 0.55, 0.60, 0.6) end
    grey(b.selectedTex, T.accent[1], T.accent[2], T.accent[3])
    for _, k in ipairs({ "LeftPiece", "RightPiece", "CenterPiece" }) do grey(b[k], 0.32, 0.32, 0.36) end
    for _, k in ipairs({ "name", "Label" }) do
        local fs = b[k]
        if fs and fs.SetTextColor then
            pcall(fs.SetTextColor, fs, T.text[1], T.text[2], T.text[3])
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0)
        end
    end
    for _, k in ipairs({ "subText", "nameSubText" }) do
        local fs = b[k]
        if fs and fs.SetTextColor then pcall(fs.SetTextColor, fs, T.textDim[1], T.textDim[2], T.textDim[3]) end
    end
    if b.icon and b.icon.SetTexCoord then pcall(b.icon.SetTexCoord, b.icon, 0.08, 0.92, 0.08, 0.92) end
end
local function petDress(f)
    if not f.__muiPetOnce then
        f.__muiPetOnce = true
        for _, o in ipairs({ f.BG, _G.ClassTrainerFrameMoneyBg }) do
            if o and o.SetAlpha then pcall(o.SetAlpha, o, 0) end
        end
        local tp = f.trainingPoints and f.trainingPoints.text
        if tp and tp.SetTextColor then pcall(tp.SetTextColor, tp, T.textDim[1], T.textDim[2], T.textDim[3]) end
    end
    local sb = f.ScrollBox
    if sb and sb.ForEachFrame then pcall(sb.ForEachFrame, sb, petDressRow) end
    if f.skillStepButton then pcall(petDressRow, f.skillStepButton) end
end
local function petTicker(f)
    if f.__muiPetTick then return end
    local t = CreateFrame("Frame", nil, f)
    f.__muiPetTick = t
    local acc = 1
    t:SetScript("OnUpdate", function(_, dt)
        if not TR.pass then return end
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        ns.Timed("pet training look", petDress, f)
    end)
end

-- Is this list one a spell of yours opened (no NPC in front of you)?
local function passNow()
    local okN, npc = pcall(UnitExists, "npc")
    if issecretvalue and issecretvalue(npc) then npc = true end
    return (okN and not npc and TR.db and TR.db.petBlizz ~= false) and true or false
end
local function ghostApply(self)
    -- (0.1.747, seen in game: the first Beast Training after a reload came
    -- up as an empty window; closed and cast again, it was full. The
    -- game's trainer window is loaded on that first use, and it was put
    -- away (shrunk to nothing) the moment it loaded, because "is this a
    -- pet's list" was only decided a frame later; it was then brought
    -- back, but its list had been laid out while it was nothing wide and
    -- stayed empty. Whose list it is is now decided right here, so a
    -- pet's list is never shrunk at all.)
    TR.pass = passNow()
    if TR.pass then
        pcall(petTicker, self)
        pcall(petDress, self)
        self:SetAlpha(1); self:SetScale(1); self:EnableMouse(true)
        -- (0.1.745, seen in game: it opened BEHIND our spell book, which
        -- is where Beast Training is cast from. It is lifted over our
        -- windows while it is the one in charge.)
        if not self.__muiStrata then self.__muiStrata = self:GetFrameStrata() end
        pcall(self.SetFrameStrata, self, "HIGH")
        pcall(self.Raise, self)
    else
        if self.__muiStrata then pcall(self.SetFrameStrata, self, self.__muiStrata) end
        self:SetAlpha(0); self:SetScale(0.001); self:EnableMouse(false)
    end
end
local function ghost(f)
    if not f then return end
    if not f.__muiGhost then
        f.__muiGhost = true
        f:HookScript("OnShow", ghostApply)
    end
    if f:IsShown() then ghostApply(f) end
end

local function open()
    local okN, npc = pcall(UnitExists, "npc")
    if issecretvalue and issecretvalue(npc) then npc = true end
    TR.pass = okN and not npc and TR.db.petBlizz ~= false
    if MinimalUIDB then MinimalUIDB.trainerdiag = date("%H:%M:%S") .. (TR.pass and " no NPC: the game's own window" or " an NPC: our window") end
    if TR.pass then
        ghost(_G.ClassTrainerFrame)
        if win and win:IsShown() then
            closing = true
            win:Hide()
            closing = false
        end
        return
    end
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
