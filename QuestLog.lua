local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Quest log: a standalone two-column window (on this client Blizzard's log
-- lives inside the world map). L opens it; the map's own quest panel stays.
--   left    quests grouped by zone (headers fold), level chip in difficulty
--           color, "Done" when complete, accent dot when tracked
--   right   title, level and zone, objectives with check circles,
--           description, reward tiles + money/XP
--   footer  Track, Share, Show on map, Abandon
-- Click selects; shift-click links into chat (or toggles tracking when no
-- chat box is open). Nothing here is secure, so it works in combat.

local Q = ns:NewModule("QuestLog", { enabled = true, collapsed = {} })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local LIST_TOP = (ns.SHELL_H or 92) + 14 -- below the header band
local W, H = 800, 540 - 66 + LIST_TOP
local LIST_W = 300
local ROW_H = 26
local FILL = { 0.06, 0.06, 0.07, 0.97 }
local CARD = { 0.10, 0.10, 0.115, 0.9 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local GREEN = { 0.40, 0.85, 0.45, 1 }

local QL = C_QuestLog or {}

local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local PILL_OPTS = { h = 24, pad = 28, minW = 0 }
local function pill(parent, label, onClick)
    return ns.Pill(parent, label, onClick, PILL_OPTS)
end

local function diffColor(level)
    if type(level) ~= "number" or secret(level) then return 1, 1, 1 end
    local fn = _G.GetQuestDifficultyColor or _G.GetDifficultyColor
    local c = fn and call(fn, level)
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function isTracked(id)
    local wt = call(QL.GetQuestWatchType, id)
    if wt ~= nil then return true end
    return call(_G.IsQuestWatched, call(QL.GetLogIndexForQuestID, id)) == true
end

-- ── Data ──────────────────────────────────────────────────────────────────
local function entries()
    local list = {}
    local n = call(QL.GetNumQuestLogEntries) or 0
    local header
    for i = 1, (type(n) == "number" and n or 0) do
        local info = call(QL.GetInfo, i)
        if type(info) == "table" and info.title and not info.isHidden then
            if info.isHeader then
                header = { header = true, title = info.title, index = i }
                table.insert(list, header)
            elseif not (header and Q.db.collapsed[header.title]) then
                table.insert(list, { title = info.title, level = info.level, questID = info.questID, index = i,
                                     zone = header and header.title, complete = call(QL.IsComplete, info.questID),
                                     failed = info.isFailed or (QL.IsFailed and call(QL.IsFailed, info.questID)) })
            end
        end
    end
    return list
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, rows, offset, data = nil, {}, 0, {}
local detail

local function chevron(row)
    local lines = {}
    for i = 1, 2 do
        local l = row:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetColorTexture(unpack(T.textDim))
        lines[i] = l
    end
    function row:SetChevron(collapsed)
        local x = 12
        if collapsed then
            lines[1]:SetStartPoint("LEFT", row, x - 2, 4); lines[1]:SetEndPoint("LEFT", row, x + 2, 0)
            lines[2]:SetStartPoint("LEFT", row, x + 2, 0); lines[2]:SetEndPoint("LEFT", row, x - 2, -4)
        else
            lines[1]:SetStartPoint("LEFT", row, x - 4, 2); lines[1]:SetEndPoint("LEFT", row, x, -2)
            lines[2]:SetStartPoint("LEFT", row, x, -2); lines[2]:SetEndPoint("LEFT", row, x + 4, 2)
        end
        for _, l in ipairs(lines) do l:Show() end
    end
    function row:HideChevron() for _, l in ipairs(lines) do l:Hide() end end
end

local function makeRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -(i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    r.bg = ns.RoundedRect(r, -8, 0, 8, 1, 1, 1, 0)
    chevron(r)
    r.chip = CreateFrame("Frame", nil, r)
    r.chip:SetSize(26, 16)
    r.chip:SetPoint("LEFT", 8, 0)
    r.chipBg = ns.RoundedRect(r.chip, -6, 0, 8, 0.15, 0.15, 0.17, 1)
    r.chipText = text(r.chip, 10, true)
    r.chipText:SetPoint("CENTER")
    r.title = text(r, 11)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.status = text(r, 10, true, GREEN)
    r.status:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    r.dot = r:CreateTexture(nil, "OVERLAY")
    r.dot:SetSize(6, 6)
    r.dot:SetTexture(MEDIA .. "rounded.tga")
    r.dot:SetVertexColor(unpack(T.accent))
    r:SetScript("OnEnter", function(self) if not self.selected then self.bg(1, 1, 1, 0.05) end end)
    r:SetScript("OnLeave", function(self) if not self.selected then self.bg(1, 1, 1, 0) end end)
    r:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.header then
            Q.db.collapsed[e.title] = not Q.db.collapsed[e.title] or nil
            Q:Refresh()
            return
        end
        if IsModifiedClick("CHATLINK") or IsShiftKeyDown() then
            local link = call(_G.GetQuestLink, e.questID)
            local chat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
            if link and chat and ChatEdit_InsertLink then ChatEdit_InsertLink(link); return end
            if isTracked(e.questID) then call(QL.RemoveQuestWatch, e.questID) else call(QL.AddQuestWatch, e.questID) end
            Q:Refresh()
            return
        end
        Q.selected = e.questID
        Q:Refresh()
    end)
    return r
end

local function fillRow(r, e)
    r.entry = e
    if not e then r:Hide(); return end
    r:Show()
    r.selected = false
    r.title:ClearAllPoints()
    if e.header then
        r:SetChevron(Q.db.collapsed[e.title])
        r.chip:Hide()
        ns:SetFont(r.title, 11, "", true)
        r.title:SetTextColor(unpack(T.textDim))
        r.title:SetPoint("LEFT", r, "LEFT", 22, 0)
        r.title:SetPoint("RIGHT", r, "RIGHT", -10, 0)
        r.title:SetText(e.title)
        r.status:SetText("")
        r.dot:Hide()
        r.bg(1, 1, 1, 0)
        return
    end
    r:HideChevron()
    r.chip:Show()
    local cr, cg, cb = diffColor(e.level)
    r.chipBg(cr * 0.28, cg * 0.28, cb * 0.28, 1)
    r.chipText:SetTextColor(cr, cg, cb)
    r.chipText:SetText(e.level or "")
    ns:SetFont(r.title, 11, "")
    r.title:SetTextColor(unpack(T.text))
    r.title:SetPoint("LEFT", r.chip, "RIGHT", 8, 0)
    r.title:SetPoint("RIGHT", r, "RIGHT", -52, 0)
    r.title:SetText(e.title)
    if e.failed then
        r.status:SetText("Failed"); r.status:SetTextColor(0.95, 0.4, 0.4)
    elseif e.complete then
        r.status:SetText("Done"); r.status:SetTextColor(unpack(GREEN))
    else
        r.status:SetText("")
    end
    r.dot:ClearAllPoints()
    r.dot:SetPoint("RIGHT", r, "RIGHT", -10 - (r.status:GetText() ~= "" and r.status:GetStringWidth() + 6 or 0), 0)
    r.dot:SetShown(isTracked(e.questID))
    r.selected = (e.questID == Q.selected)
    r.bg(1, 1, 1, r.selected and 0.10 or 0)
end

local function scrollList(delta)
    offset = math.max(0, math.min(offset - delta * 3, math.max(0, #data - #rows)))
    for i, r in ipairs(rows) do fillRow(r, data[i + offset]) end
    local track = win.thumb
    if #data > #rows then
        local h = win.list:GetHeight()
        local th = h * #rows / #data
        track:SetHeight(th)
        track:ClearAllPoints()
        track:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", 0, -(h - th) * offset / (#data - #rows))
        track:Show()
    else
        track:Hide()
    end
end

-- ── Detail pane ───────────────────────────────────────────────────────────
-- Pooled widgets laid out top-down in a scroll child.
local pool = { fs = {}, check = {}, tile = {} }
local used = { fs = 0, check = 0, tile = 0 }

local function takeFS(size, bold, color)
    used.fs = used.fs + 1
    local fs = pool.fs[used.fs]
    if not fs then fs = detail.content:CreateFontString(nil, "OVERLAY"); pool.fs[used.fs] = fs end
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetSpacing(0)
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

local function takeCheck(done)
    used.check = used.check + 1
    local c = pool.check[used.check]
    if not c then
        c = CreateFrame("Frame", nil, detail.content)
        c:SetSize(12, 12)
        local ring = c:CreateTexture(nil, "ARTWORK", nil, 1)
        ring:SetAllPoints()
        local m1 = c:CreateMaskTexture(); m1:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m1:SetAllPoints()
        ring:AddMaskTexture(m1)
        local inner = c:CreateTexture(nil, "ARTWORK", nil, 2)
        inner:SetSize(8, 8); inner:SetPoint("CENTER")
        local m2 = c:CreateMaskTexture(); m2:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m2:SetAllPoints(inner)
        inner:AddMaskTexture(m2)
        c.ring, c.inner = ring, inner
        pool.check[used.check] = c
    end
    if done then
        c.ring:SetColorTexture(unpack(GREEN)); c.inner:SetColorTexture(unpack(GREEN))
    else
        c.ring:SetColorTexture(0.35, 0.35, 0.4, 1); c.inner:SetColorTexture(unpack(FILL))
    end
    c:ClearAllPoints()
    c:Show()
    return c
end

local function takeTile()
    used.tile = used.tile + 1
    local t = pool.tile[used.tile]
    if not t then
        t = CreateFrame("Button", nil, detail.content)
        t:SetSize(180, 40)
        t.bg = ns.RoundedRect(t, -8, 0, 10, unpack(CARD))
        local box = CreateFrame("Frame", nil, t)
        box:SetSize(32, 32)
        box:SetPoint("LEFT", 4, 0)
        t.ring = ns.RoundedRect(box, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
        local mask = box:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("TOPLEFT", 2, -2); mask:SetPoint("BOTTOMRIGHT", -2, 2)
        t.icon = box:CreateTexture(nil, "ARTWORK")
        t.icon:SetAllPoints(mask)
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.icon:AddMaskTexture(mask)
        t.count = box:CreateFontString(nil, "OVERLAY")
        ns:SetFont(t.count, 10, "OUTLINE", true)
        t.count:SetPoint("BOTTOMRIGHT", -2, 2)
        t.name = text(t, 11)
        t.name:SetPoint("LEFT", box, "RIGHT", 8, 0)
        t.name:SetPoint("RIGHT", t, "RIGHT", -6, 0)
        t.name:SetJustifyH("LEFT")
        t.name:SetWordWrap(true)
        t:SetScript("OnEnter", function(self)
            ns.TipAnchor(self)
            if not pcall(GameTooltip.SetQuestLogItem, GameTooltip, self.kind, self.index, self.questID) then
                GameTooltip:SetText(self.name:GetText() or "")
            end
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t:SetScript("OnClick", function(self)
            if IsModifiedClick() and self.link and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
        end)
        pool.tile[used.tile] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function resetPool()
    for k, list in pairs(pool) do
        for i = 1, #list do list[i]:Hide() end
        used[k] = 0
    end
end

local function moneyText(c)
    if type(c) ~= "number" or secret(c) or c <= 0 then return nil end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "|cffe6c25a g|r") end
    if s > 0 then table.insert(parts, s .. "|cffb8bcc6 s|r") end
    if cp > 0 then table.insert(parts, cp .. "|cffc98a52 c|r") end
    return table.concat(parts, "  ")
end

local function showDetail(e)
    resetPool()
    local content = detail.content
    local w = content:GetWidth()
    local y = -4
    local function place(fs, gap)
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        fs:SetWidth(w)
        y = y - fs:GetStringHeight() - (gap or 8)
    end
    if not e then
        local fs = takeFS(12, false, T.textDim)
        fs:SetText("Pick a quest on the left.")
        place(fs)
        content:SetHeight(-y)
        win.track:Hide(); win.share:Hide(); win.map:Hide(); win.abandon:Hide()
        return
    end
    local id = e.questID
    call(QL.SetSelectedQuest, id)

    local title = takeFS(17, true)
    title:SetText(e.title)
    place(title, 4)
    local meta = takeFS(11, false, T.textDim)
    local cr, cg, cb = diffColor(e.level)
    meta:SetText(string.format("|cff%02x%02x%02xLevel %s|r%s", cr * 255, cg * 255, cb * 255, tostring(e.level or "?"),
        e.zone and ("   ·   " .. e.zone) or ""))
    place(meta, 16)

    local function section(label)
        local h = takeFS(10, true, T.textDim)
        h:SetText(label)
        place(h, 6)
    end

    local objectives = call(QL.GetQuestObjectives, id)
    local desc, objText = call(_G.GetQuestLogQuestText, e.index)
    section("Objectives")
    if type(objectives) == "table" and #objectives > 0 then
        for _, o in ipairs(objectives) do
            if o.text and not secret(o.text) then
                local c = takeCheck(o.finished)
                c:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y - 1)
                local fs = takeFS(12, false, o.finished and T.textDim or T.text)
                fs:SetText(o.text)
                fs:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)
                fs:SetWidth(w - 20)
                y = y - fs:GetStringHeight() - 6
            end
        end
    elseif objText and not secret(objText) and objText ~= "" then
        local fs = takeFS(12)
        fs:SetText(objText)
        place(fs, 6)
    end
    if e.complete then
        local fs = takeFS(11, true, GREEN)
        fs:SetText("Ready to turn in")
        place(fs, 6)
    end
    y = y - 10

    if desc and not secret(desc) and desc ~= "" then
        section("Description")
        local fs = takeFS(12, false, { 0.80, 0.80, 0.84, 1 })
        fs:SetSpacing(3)
        fs:SetText(desc)
        place(fs, 16)
    end

    -- Rewards.
    local tiles = {}
    local nChoice = call(_G.GetNumQuestLogChoices, id, true) or 0
    for i = 1, (type(nChoice) == "number" and nChoice or 0) do
        local name, tex, count, quality = call(_G.GetQuestLogChoiceInfo, i)
        if name then table.insert(tiles, { kind = "choice", index = i, name = name, tex = tex, count = count, quality = quality }) end
    end
    local nReward = call(_G.GetNumQuestLogRewards, id) or 0
    for i = 1, (type(nReward) == "number" and nReward or 0) do
        local name, tex, count, quality = call(_G.GetQuestLogRewardInfo, i, id)
        if name then table.insert(tiles, { kind = "reward", index = i, name = name, tex = tex, count = count, quality = quality }) end
    end
    local money = moneyText(call(_G.GetQuestLogRewardMoney, id))
    local xp = call(_G.GetQuestLogRewardXP, id)
    if #tiles > 0 or money or (type(xp) == "number" and xp > 0) then
        section(nChoice and nChoice > 1 and "Rewards (choose one of the first " .. nChoice .. ")" or "Rewards")
        local col = 0
        for _, r in ipairs(tiles) do
            local t = takeTile()
            t.kind, t.index, t.questID = r.kind, r.index, id
            t.link = call(_G.GetQuestLogItemLink, r.kind, r.index, id)
            t.icon:SetTexture(r.tex)
            t.name:SetText(r.name)
            t.count:SetText(type(r.count) == "number" and r.count > 1 and r.count or "")
            local q = r.quality
            local c = type(q) == "number" and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            if c then t.ring(c.r, c.g, c.b, 1); t.name:SetTextColor(c.r, c.g, c.b)
            else t.ring(T.border[1], T.border[2], T.border[3], 1); t.name:SetTextColor(unpack(T.text)) end
            t:SetWidth((w - 8) / 2)
            t:SetPoint("TOPLEFT", content, "TOPLEFT", col * ((w - 8) / 2 + 8), y)
            col = col + 1
            if col == 2 then col = 0; y = y - 46 end
        end
        if col == 1 then y = y - 46 end
        local extras = {}
        if money then table.insert(extras, money) end
        if type(xp) == "number" and xp > 0 then table.insert(extras, BreakUpLargeNumbers and BreakUpLargeNumbers(xp) .. " XP" or (xp .. " XP")) end
        if #extras > 0 then
            local fs = takeFS(12, true)
            fs:SetText(table.concat(extras, "     "))
            place(fs, 8)
        end
    end
    content:SetHeight(math.max(-y + 8, 10))
    detail:SetVerticalScroll(0)

    -- Footer actions.
    win.track:SetLabel(isTracked(id) and "Untrack" or "Track")
    win.track:Show(); win.map:Show(); win.abandon:Show()
    local canShare = call(QL.IsPushableQuest, id) and (IsInGroup and IsInGroup())
    win.share:SetShown(canShare and true or false)
    local canAbandon = call(QL.CanAbandonQuest, id) ~= false
    win.abandon:SetEnabled(canAbandon)
    if canAbandon then win.abandon.fs:SetTextColor(0.95, 0.5, 0.5) end
end

-- ── Refresh / build ───────────────────────────────────────────────────────
function Q:Refresh()
    if not win or not win:IsShown() then return end
    data = entries()
    local selected
    for _, e in ipairs(data) do if not e.header and e.questID == self.selected then selected = e end end
    if not selected then
        for _, e in ipairs(data) do if not e.header then selected = e; break end end
        self.selected = selected and selected.questID
    end
    scrollList(0)
    -- Header: quest count (all quests, folded zones included) + ready chip.
    local _, n = call(QL.GetNumQuestLogEntries)
    local ready = 0
    local total = call(QL.GetNumQuestLogEntries) or 0
    local counted = 0
    for i = 1, (type(total) == "number" and total or 0) do
        local info = call(QL.GetInfo, i)
        if type(info) == "table" and not info.isHeader and not info.isHidden then
            counted = counted + 1
            if call(QL.IsComplete, info.questID) then ready = ready + 1 end
        end
    end
    n = type(n) == "number" and n or counted
    local max = call(QL.GetMaxNumQuestsCanAccept) or call(QL.GetMaxNumQuests)
    win.shell:SetSubtitle(type(max) == "number" and string.format("%d of %d quests", n, max) or (n .. " quests"))
    win.shell:SetChip(ready > 0 and (ready .. " ready to turn in") or nil, GREEN)
    pcall(showDetail, selected)
end

local function build()
    win = CreateFrame("Frame", "MinimalUIQuestLog", UIParent)
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
        Q.db.pos = { p, rp, x, y }
    end)
    local pos = Q.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER", 0, 30) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIQuestLog")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win)
    win.shell:SetTitle(QUEST_LOG or "Quest log")
    win.shell:SetIcon("Interface/Icons/INV_Misc_Note_01")
    win.shell:SetRing({ 0.95, 0.80, 0.35 })

    -- Left: quest list card.
    local listCard = CreateFrame("Frame", nil, win)
    listCard:SetPoint("TOPLEFT", 20, -LIST_TOP)
    listCard:SetPoint("BOTTOMLEFT", 20, 18)
    listCard:SetWidth(LIST_W)
    ns.RoundedRect(listCard, -6, 0, 10, unpack(CARD))
    local list = CreateFrame("Frame", nil, listCard)
    list:SetPoint("TOPLEFT", 6, -6)
    list:SetPoint("BOTTOMRIGHT", -6, 6)
    win.list = list
    local nRows = math.floor((H - LIST_TOP - 18 - 12) / ROW_H)
    for i = 1, nRows do rows[i] = makeRow(list, i) end
    win.thumb = list:CreateTexture(nil, "OVERLAY")
    win.thumb:SetWidth(3)
    win.thumb:SetColorTexture(0.32, 0.32, 0.36, 1)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) scrollList(d) end)

    -- Right: detail (scrolls), footer actions.
    detail =CreateFrame("ScrollFrame", nil, win)
    detail:SetPoint("TOPLEFT", listCard, "TOPRIGHT", 22, -6)
    detail:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -22, 56)
    detail.content = CreateFrame("Frame", nil, detail)
    detail.content:SetSize(W - 20 - LIST_W - 22 - 22, 10)
    detail:SetScrollChild(detail.content)
    detail:EnableMouseWheel(true)
    detail:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, self.content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 40)))
    end)

    win.track = pill(win, "Track", function()
        local id = Q.selected
        if not id then return end
        if isTracked(id) then call(QL.RemoveQuestWatch, id) else call(QL.AddQuestWatch, id) end
        Q:Refresh()
    end)
    win.track:SetPoint("BOTTOMLEFT", listCard, "BOTTOMRIGHT", 22, 0)
    win.share = pill(win, "Share", function()
        if not Q.selected then return end
        call(QL.SetSelectedQuest, Q.selected)
        call(_G.QuestLogPushQuest)
    end)
    win.share:SetPoint("LEFT", win.track, "RIGHT", 8, 0)
    win.map = pill(win, "Show on map", function()
        local id = Q.selected
        if not id then return end
        win:Hide()
        Q.bypass = true
        if _G.QuestMapFrame_OpenToQuestDetails then call(QuestMapFrame_OpenToQuestDetails, id)
        elseif _G.OpenQuestLog then call(OpenQuestLog) end
        C_Timer.After(0.3, function() Q.bypass = false end)
    end)
    win.map:SetPoint("LEFT", win.share, "RIGHT", 8, 0)
    win.abandon = pill(win, "Abandon", function()
        local id = Q.selected
        if not id then return end
        call(QL.SetSelectedQuest, id)
        call(QL.SetAbandonQuest)
        local name = call(QL.GetTitleForQuestID, id) or ""
        if StaticPopup_Show then StaticPopup_Show("ABANDON_QUEST", name) end
    end)
    win.abandon:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -22, 18)

    -- Keep Share's position stable when it's hidden.
    hooksecurefunc(win.share, "SetShown", function(self, shown)
        win.map:ClearAllPoints()
        win.map:SetPoint("LEFT", shown and self or win.track, "RIGHT", 8, 0)
    end)

    win:SetScript("OnShow", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN)
        Q.shownAt = GetTime()
        Q:Refresh()
    end)
    win:SetScript("OnHide", function() call(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_CLOSE) end)
end

function Q:Open()
    if not win then build() end
    win:Show()
end

function Q:Toggle()
    if win and win:IsShown() then win:Hide() else self:Open() end
end

function Q:OnInit(db)
    self.db = db
    db.collapsed = db.collapsed or {}
    if _G.ToggleQuestLog then
        hooksecurefunc("ToggleQuestLog", function()
            if Q.bypass then return end
            local wm = _G.WorldMapFrame
            local wasOpen = win and win:IsShown() and Q.shownAt ~= GetTime()
            if wm and wm:IsShown() then HideUIPanel(wm) end
            if wasOpen then win:Hide() else Q:Open() end
        end)
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
                         "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local dirty, acc = false, 0
    ev:SetScript("OnEvent", function() if win and win:IsShown() then dirty = true end end)
    ev:SetScript("OnUpdate", function(_, dt)
        if not dirty then return end
        acc = acc + dt
        if acc < 0.2 then return end
        acc, dirty = 0, false
        Q:Refresh()
    end)
end

ns.commands.quests = function() if Q.db then Q:Toggle() end end
