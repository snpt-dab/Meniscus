local _, ns = ...
local T = ns.Theme

-- Dialogs: Meniscus's NPC conversation window, replacing the look of
-- Blizzard's gossip and quest dialogs. Blizzard's frames stay open (closing
-- them would end the conversation) but are made invisible and unclickable;
-- this window drives the same C_GossipInfo / quest functions they use.
--
--   header   noise-textured band: 3D talking head (pops out the top, ring
--            in the NPC's attitude color), name, title line + zone, chip
--   bubble   greeting / quest text in a speech bubble pointing at the head;
--            types itself out while the NPC talks (click to skip)
--   body     gossip: quest cards (level chip, title, status) + talk pills
--            quest:  objectives, required items, reward tiles (click a
--                    choice to pick it), money / XP
--   footer   context actions (Accept / Decline / Continue / Complete /
--            Goodbye), primary one light
-- The window fits its content (long text scrolls).

local D = ns:NewModule("Dialogs", { enabled = true, typewriter = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local W = 380
local HEADER_H = ns.SHELL_H or 92
local FOOTER_H = 52
local MAX_BODY = 540
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local BAND = { 0.095, 0.10, 0.11, 1 }
local BUBBLE = { 0.12, 0.12, 0.14, 1 }
local CARD = { 0.10, 0.10, 0.115, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local GOLD = { 1.0, 0.82, 0.25, 1 }
local GREEN = { 0.45, 0.85, 0.50, 1 }
local TALK_ANIM = 60

local G = C_GossipInfo or {}
local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local function diffColor(level)
    if type(level) ~= "number" or secret(level) or level <= 0 then return 0.75, 0.75, 0.8 end
    local fn = _G.GetQuestDifficultyColor or _G.GetDifficultyColor
    local c = fn and call(fn, level)
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 1, 1, 1
end

local PILL_OPTS = { h = 26, font = 12, ring = true, pad = 32, minW = 70 }
local function pill(parent, label, onClick, primary)
    local b = ns.Pill(parent, "", onClick, PILL_OPTS)
    function b:Set(label2, fn, prim)
        self:SetLabel(label2)
        self:SetScript("OnClick", fn)
        self.primary = prim
        self:SetEnabled(true)
        self:Repaint()
        self:Show()
    end
    if label then b:Set(label, onClick, primary) end
    return b
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, body, content
local mode -- "gossip" | "quest"
local unit = "npc"
local closingFromEvent = false

local function npcInfo(u)
    local title
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, u)
        if ok and type(data) == "table" and data.lines and data.lines[2] then
            local t = str(data.lines[2].leftText)
            if t and not t:find("^" .. (LEVEL or "Level")) and not t:find("^Level") then title = t end
        end
    end
    local zone = str(GetSubZoneText and GetSubZoneText()) or str(GetZoneText and GetZoneText())
    return title, zone
end

local function attitude(u)
    local ok, r = pcall(UnitReaction, u, "player")
    if not ok or type(r) ~= "number" or secret(r) then return nil end
    if r <= 3 then return "Hostile", { 0.92, 0.38, 0.35 } end
    if r == 4 then return "Neutral", { 0.95, 0.80, 0.35 } end
    return "Friendly", { 0.45, 0.85, 0.50 }
end

-- Header: band, head, name, subtitle, chip.
-- Header: the shared window shell (Shell.lua) with the NPC's talking head.
local function buildHeader()
    win.shell = ns:CreateShell(win)
end

local function updateHeader(nameOverride)
    local sh = win.shell
    local exists = UnitExists(unit)
    local name = nameOverride or (exists and UnitName(unit)) or ""
    sh:SetTitle(name)
    local title, zone = npcInfo(unit)
    local parts = {}
    if exists and title then table.insert(parts, title) end
    if zone then table.insert(parts, zone) end
    sh:SetSubtitle(table.concat(parts, "   ·   "))
    sh:SetAttitude(unit)
    if exists then sh:SetUnit(unit, true) else sh:SetIcon("Interface/Icons/INV_Misc_Note_01") end
end

-- ── Body building (pooled, laid out top-down) ─────────────────────────────
local pools, used = {}, {}
-- Everything taken for the current page, in the order it was laid out, so
-- that when something changes height after the fact (the speech bubble
-- being shortened to fit, a reward card whose data arrived late) all that
-- comes below it can be moved by the difference.
local placed, bubbles = {}, {}
local function take(kind, make)
    pools[kind] = pools[kind] or {}
    used[kind] = (used[kind] or 0) + 1
    local o = pools[kind][used[kind]]
    if not o then o = make(); pools[kind][used[kind]] = o end
    if o.ClearAllPoints then o:ClearAllPoints() end
    o:Show()
    placed[#placed + 1] = o
    return o
end
local function resetPools()
    for k, list in pairs(pools) do for i = 1, #list do list[i]:Hide() end; used[k] = 0 end
    wipe(placed); wipe(bubbles)
end

local y, CW
-- Move everything laid out after the idx-th object up by dy (down if negative).
local ptBuf = {}
local function shiftAfter(idx, dy)
    if dy == 0 then return end
    for i = idx + 1, #placed do
        local o = placed[i]
        local n = o:GetNumPoints()
        local hit = false
        for p = 1, n do
            local a, rel, b, x, yy = o:GetPoint(p)
            local e = ptBuf[p]
            if not e then e = {}; ptBuf[p] = e end
            e[1], e[2], e[3], e[4], e[5] = a, rel, b, x, yy
            if rel == content then hit = true end
        end
        if hit then
            o:ClearAllPoints()
            for p = 1, n do
                local e = ptBuf[p]
                o:SetPoint(e[1], e[2], e[3], e[4], e[5] + (e[2] == content and dy or 0))
            end
        end
    end
    y = y + dy
end
local function fs(size, bold, color)
    local f = take("fs", function() return content:CreateFontString(nil, "OVERLAY") end)
    ns:SetFont(f, size, "", bold)
    f:SetTextColor(unpack(color or T.text))
    f:SetJustifyH("LEFT")
    f:SetWordWrap(true)
    f:SetSpacing(0)
    f:SetAlphaGradient(100000, 1)
    return f
end

local function section(label, count)
    local h = fs(11, true, T.textDim)
    h:SetText(count and (label .. "  ·  " .. count) or label)
    h:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y)
    y = y - h:GetStringHeight() - 8
end

local function paragraph(s, color)
    local f = fs(12, false, color or { 0.84, 0.84, 0.88, 1 })
    f:SetSpacing(3)
    f:SetWidth(CW)
    f:SetText(s)
    f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - f:GetStringHeight() - 14
end

-- Speech bubble with a tail toward the head; the text types itself out.
local typer
-- The bubble is as tall as its text. If the whole page would then be taller
-- than the screen allows, finish() shortens the bubble and its text scrolls
-- inside it, so everything below (objectives, rewards, buttons) stays in
-- view without scrolling the window.
local BUBBLE_MIN = 96
local function bubble(s)
    if not str(s) then return end
    local b = take("bubble", function()
        local f = CreateFrame("Button", nil, content)
        ns.RoundedRect(f, -6, 0, 12, unpack(BUBBLE))
        local tail = f:CreateTexture(nil, "BACKGROUND", nil, -5)
        tail:SetSize(12, 12)
        tail:SetPoint("CENTER", f, "TOPLEFT", 38, 0)
        tail:SetColorTexture(unpack(BUBBLE))
        tail:SetRotation(math.rad(45))
        local sf = CreateFrame("ScrollFrame", nil, f)
        sf:SetPoint("TOPLEFT", 14, -12)
        sf:SetPoint("BOTTOMRIGHT", -14, 12)
        local inner = CreateFrame("Frame", nil, sf)
        inner:SetSize(10, 10)
        sf:SetScrollChild(inner)
        f.text = inner:CreateFontString(nil, "OVERLAY")
        f.text:SetPoint("TOPLEFT")
        f.text:SetJustifyH("LEFT")
        f.text:SetSpacing(3)
        f.thumb = f:CreateTexture(nil, "OVERLAY")
        f.thumb:SetWidth(3)
        f.thumb:SetColorTexture(0.36, 0.36, 0.40, 1)
        local function placeThumb()
            local max = sf:GetVerticalScrollRange()
            -- (A pixel or two of range is rounding, not content.)
            if max <= 3 then f.thumb:Hide(); return end
            local h = sf:GetHeight()
            local size = math.max(16, h * h / (h + max))
            f.thumb:SetHeight(size)
            f.thumb:ClearAllPoints()
            f.thumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -12 - (h - size) * (sf:GetVerticalScroll() / max))
            f.thumb:Show()
        end
        f.placeThumb = placeThumb
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, d)
            local max = self:GetVerticalScrollRange()
            if max <= 3 then max = 0 end
            self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 36)))
            placeThumb()
        end)
        f.sf, f.inner = sf, inner
        f:SetScript("OnClick", function(self) if typer then typer.done = true end end)
        return f
    end)
    ns:SetFont(b.text, 13, "")
    b.text:SetTextColor(0.92, 0.92, 0.95)
    b.text:SetWidth(CW - 34)
    b.text:SetText(s)
    local textH = b.text:GetStringHeight()
    b.inner:SetSize(CW - 34, textH + 2)
    -- The scroll area is the bubble minus 24 of padding: it has to be as
    -- tall as the text's holder (textH + 2), or short text scrolls by the
    -- difference and always shows a sliver of scroll bar.
    local h = textH + 26
    bubbles[#bubbles + 1] = { b = b, idx = #placed, h = h }
    b:SetSize(CW, h)
    b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - 6)
    b.sf:SetVerticalScroll(0)
    C_Timer.After(0, b.placeThumb)
    y = y - h - 22
    -- Typewriter: reveal characters progressively with an alpha gradient.
    if D.db.typewriter then
        local len = strlenutf8 and strlenutf8(s) or #s
        typer = { fs = b.text, pos = 0, len = len, done = false }
        b.text:SetAlphaGradient(0, 12)
    else
        typer = nil
        b.text:SetAlphaGradient(100000, 1)
    end
end

-- Quest card row: level chip, title, status glyph.
local function questCard(title, level, status, onClick, trivial)
    local c = take("card", function()
        local f = CreateFrame("Button", nil, content)
        f:SetHeight(34)
        f.ring = ns.RoundedRect(f, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
        f.fill = ns.RoundedRect(f, -7, 1, 9, unpack(CARD))
        f.chip = CreateFrame("Frame", nil, f)
        f.chip:SetSize(28, 18)
        f.chip:SetPoint("LEFT", 10, 0)
        f.chipPaint = ns.RoundedRect(f.chip, -6, 0, 8, 0.2, 0.2, 0.2, 1)
        f.chipText = text(f.chip, 10, true)
        f.chipText:SetPoint("CENTER")
        f.title = text(f, 12)
        f.title:SetPoint("LEFT", f.chip, "RIGHT", 10, 0)
        f.title:SetPoint("RIGHT", f, "RIGHT", -32, 0)
        f.title:SetJustifyH("LEFT")
        f.title:SetWordWrap(false)
        f.glyph = text(f, 15, true)
        f.glyph:SetPoint("RIGHT", f, "RIGHT", -12, 0)
        f:SetScript("OnEnter", function(self) self.ring(unpack(T.accent)); self.fill(0.13, 0.13, 0.15, 1) end)
        f:SetScript("OnLeave", function(self) self.ring(T.border[1], T.border[2], T.border[3], 1); self.fill(unpack(CARD)) end)
        return f
    end)
    c:SetWidth(CW)
    c:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    local r, g, b = diffColor(level)
    if trivial then r, g, b = 0.6, 0.6, 0.62 end
    c.chipPaint(r * 0.25, g * 0.25, b * 0.25, 1)
    c.chipText:SetTextColor(r, g, b)
    c.chipText:SetText(type(level) == "number" and level > 0 and level or "")
    c.chip:SetShown(type(level) == "number" and level > 0)
    c.title:SetText(title)
    c.title:SetTextColor(unpack(trivial and T.textDim or T.text))
    if status == "available" then c.glyph:SetText("!"); c.glyph:SetTextColor(unpack(GOLD))
    elseif status == "complete" then c.glyph:SetText("?"); c.glyph:SetTextColor(unpack(GOLD))
    else c.glyph:SetText("?"); c.glyph:SetTextColor(0.55, 0.55, 0.6) end
    c:SetScript("OnClick", onClick)
    c.ring(T.border[1], T.border[2], T.border[3], 1); c.fill(unpack(CARD))
    y = y - 40
end

-- Talk options as pills that wrap.
local function talkPills(options)
    local x, rowH = 0, 30
    for _, o in ipairs(options) do
        local p = take("talk", function()
            local f = pill(content)
            f.icon = f:CreateTexture(nil, "OVERLAY")
            f.icon:SetSize(14, 14)
            f.icon:SetPoint("LEFT", 10, 0)
            return f
        end)
        p:Set(o.name, o.onClick)
        if o.icon then
            p.icon:SetTexture(o.icon); p.icon:Show()
            p.fs:ClearAllPoints(); p.fs:SetPoint("LEFT", p.icon, "RIGHT", 6, 0)
            p:SetWidth(p.fs:GetStringWidth() + 46)
        else
            p.icon:Hide()
            p.fs:ClearAllPoints(); p.fs:SetPoint("CENTER")
        end
        if p:GetWidth() > CW then p:SetWidth(CW); p.fs:SetWidth(CW - 46); p.fs:SetWordWrap(false) end
        if x > 0 and x + p:GetWidth() > CW then x = 0; y = y - rowH end
        p:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        x = x + p:GetWidth() + 6
    end
    y = y - rowH - 8
end

-- Item tiles (rewards / required items). Choices are selectable.
local selectedChoice
local function itemTiles(list)
    local col = 0
    local tw = (CW - 8) / 2
    for _, it in ipairs(list) do
        local t = take("tile", function()
            local f = CreateFrame("Button", nil, content)
            f:SetHeight(42)
            f.ring = ns.RoundedRect(f, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
            f.fill = ns.RoundedRect(f, -7, 1, 9, unpack(CARD))
            local box = CreateFrame("Frame", nil, f)
            box:SetSize(32, 32)
            box:SetPoint("LEFT", 5, 0)
            local mask = box:CreateMaskTexture()
            mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints()
            f.icon = box:CreateTexture(nil, "ARTWORK")
            f.icon:SetAllPoints()
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            f.icon:AddMaskTexture(mask)
            f.count = box:CreateFontString(nil, "OVERLAY")
            ns:SetFont(f.count, 10, "OUTLINE", true)
            f.count:SetPoint("BOTTOMRIGHT", -1, 1)
            f.name = text(f, 11)
            f.name:SetPoint("LEFT", box, "RIGHT", 8, 0)
            f.name:SetPoint("RIGHT", f, "RIGHT", -6, 0)
            f.name:SetJustifyH("LEFT")
            f.name:SetWordWrap(true)
            f:SetScript("OnEnter", function(self)
                ns.TipAnchor(self)
                pcall(GameTooltip.SetQuestItem, GameTooltip, self.kind, self.index)
                GameTooltip:Show()
                pcall(ns.AddCompare, GameTooltip, call(_G.GetQuestItemLink, self.kind, self.index))
            end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return f
        end)
        t.kind, t.index = it.kind, it.index
        t:SetWidth(tw)
        t:SetPoint("TOPLEFT", content, "TOPLEFT", col * (tw + 8), y)
        t.icon:SetTexture(it.tex)
        t.icon:SetDesaturated(it.usable == false)
        t.count:SetText(type(it.count) == "number" and it.count > 1 and it.count or "")
        t.name:SetText(it.name)
        local q = it.quality
        local c = type(q) == "number" and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        t.name:SetTextColor(unpack(c and { c.r, c.g, c.b, 1 } or T.text))
        local function paintSel()
            if it.kind == "choice" and selectedChoice == it.index then
                t.ring(unpack(T.accent)); t.fill(0.10, 0.16, 0.20, 1)
            elseif c then
                t.ring(c.r * 0.7, c.g * 0.7, c.b * 0.7, 1); t.fill(unpack(CARD))
            else
                t.ring(T.border[1], T.border[2], T.border[3], 1); t.fill(unpack(CARD))
            end
        end
        t.paintSel = paintSel
        paintSel()
        t:SetScript("OnClick", function(self)
            if IsModifiedClick() then
                local link = call(_G.GetQuestItemLink, self.kind, self.index)
                if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
                return
            end
            if it.kind == "choice" then
                selectedChoice = it.index
                for _, other in ipairs(pools.tile or {}) do if other:IsShown() and other.paintSel then other.paintSel() end end
                if win.onChoice then win.onChoice() end
            end
        end)
        col = col + 1
        if col == 2 then col = 0; y = y - 48 end
    end
    if col == 1 then y = y - 48 end
    y = y - 6
end

-- Reward cards: one full-width card per reward, stacked, each as tall as
-- what it has to say:
--   icon | name (quality colour)                      vendor value
--        | what it is ("Wrist · Mail"), or in red why you can't use it
--        | how it differs from what you wear (green gains, red losses)
-- A choice is picked by clicking its card.
local function rewardCards(list)
    for _, it in ipairs(list) do
        it.link = call(_G.GetQuestItemLink, it.kind, it.index)
        if it.link and C_Item and C_Item.GetItemInfoInstant then
            local _, typ, sub, loc, _, classID, subID = call(C_Item.GetItemInfoInstant, it.link)
            it.typ, it.sub = typ, sub
            -- Body armor (cloth / leather / mail / plate; cloaks are cloth
            -- for everyone and don't count): its weight, 1 to 4.
            it.weight = (classID == 4 and type(subID) == "number" and subID >= 1 and subID <= 4
                and loc ~= "INVTYPE_CLOAK") and subID or nil
            -- Only real equipment slots count (things you can't equip carry
            -- a placeholder slot whose name is an empty string).
            local sn = type(loc) == "string" and loc ~= "" and _G[loc]
            it.slotName = (type(sn) == "string" and sn ~= "") and sn or nil
        end
    end

    local function coins(v)
        local g, s, c = math.floor(v / 10000), math.floor(v / 100) % 100, v % 100
        local out = ""
        if g > 0 then out = out .. g .. "|cffe6c25ag|r " end
        if s > 0 then out = out .. s .. "|cffb8bcc6s|r " end
        if c > 0 then out = out .. c .. "|cffc98a52c|r" end
        return out
    end

    local cards = {}
    for _, it in ipairs(list) do
        local t = take("rcard2", function()
            local f = CreateFrame("Button", nil, content)
            f.ring = ns.RoundedRect(f, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
            f.fill = ns.RoundedRect(f, -7, 1, 11, unpack(CARD))
            local box = CreateFrame("Frame", nil, f)
            box:SetSize(36, 36)
            box:SetPoint("TOPLEFT", 10, -10)
            local mask = box:CreateMaskTexture()
            mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints()
            f.icon = box:CreateTexture(nil, "ARTWORK")
            f.icon:SetAllPoints()
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            f.icon:AddMaskTexture(mask)
            f.count = box:CreateFontString(nil, "OVERLAY")
            ns:SetFont(f.count, 10, "OUTLINE", true)
            f.count:SetPoint("BOTTOMRIGHT", -1, 1)
            f.sell = text(f, 10, false, T.textDim)
            f.sell:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
            f.sell:SetJustifyH("RIGHT")
            f.name = text(f, 12, true)
            f.name:SetPoint("TOPLEFT", box, "TOPRIGHT", 10, 0)
            f.name:SetJustifyH("LEFT"); f.name:SetJustifyV("TOP")
            f.name:SetWordWrap(true)
            f.what = text(f, 10, false, T.textDim)
            f.what:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
            f.what:SetJustifyH("LEFT")
            f.what:SetWordWrap(true)
            f.rows = text(f, 11)
            f.rows:SetPoint("TOPLEFT", f.what, "BOTTOMLEFT", 0, -6)
            f.rows:SetJustifyH("LEFT"); f.rows:SetJustifyV("TOP")
            f.rows:SetSpacing(3)
            f.rows:SetWordWrap(true)
            f:SetScript("OnEnter", function(self)
                ns.TipAnchor(self)
                pcall(GameTooltip.SetQuestItem, GameTooltip, self.kind, self.index)
                GameTooltip:Show()
            end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return f
        end)
        cards[#cards + 1] = t
        t.kind, t.index, t.it, t.idx = it.kind, it.index, it, #placed
        t.h = 56
        t:SetSize(CW, t.h)
        t:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        y = y - (t.h + 8)
        t.icon:SetTexture(it.tex)
        t.count:SetText(type(it.count) == "number" and it.count > 1 and it.count or "")
        t.name:SetText(it.name)
        local q = it.quality
        local c = type(q) == "number" and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        t.qc = c
        local function paintSel()
            if it.kind == "choice" and selectedChoice == it.index then
                t.ring(unpack(T.accent)); t.fill(0.10, 0.16, 0.20, 1)
            elseif c then
                t.ring(c.r * 0.7, c.g * 0.7, c.b * 0.7, 1); t.fill(unpack(CARD))
            else
                t.ring(T.border[1], T.border[2], T.border[3], 1); t.fill(unpack(CARD))
            end
        end
        t.paintSel = paintSel
        paintSel()
        t:SetScript("OnClick", function(self)
            if IsModifiedClick() then
                local link = call(_G.GetQuestItemLink, self.kind, self.index)
                if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
                return
            end
            if it.kind == "choice" then
                selectedChoice = it.index
                for _, other in ipairs(pools.rcard2 or {}) do if other:IsShown() and other.paintSel then other.paintSel() end end
                if win.onChoice then win.onChoice() end
            end
        end)
    end
    y = y - 4

    -- Fill in what needs the item's full data, then give each card the
    -- height its text needs (moving what's below it). Data for an item
    -- never seen before can arrive a moment late, so this runs again then.
    local function details()
        local best, missing = 0, false
        local bestArmor = ns.BestArmor and call(ns.BestArmor)
        for _, t in ipairs(cards) do
            local it = t.it
            local link = it.link or call(_G.GetQuestItemLink, t.kind, t.index)
            it.link = link
            local price
            if link and C_Item and C_Item.GetItemInfo then price = select(11, call(C_Item.GetItemInfo, link)) end
            if type(price) == "number" and not secret(price) then
                if type(it.count) == "number" and not secret(it.count) and it.count > 1 then price = price * it.count end
                t.price = price
                if t.kind == "choice" and price > best then best = price end
            else
                t.price = nil
                missing = true
            end
        end
        for _, t in ipairs(cards) do
            local it = t.it
            local why = it.link and ns.ItemUnusable and call(ns.ItemUnusable, it.link)
            local cant = type(why) == "string" or it.usable == false
            -- Armor weight is shown by colouring the armor type's own word,
            -- with no verdict in words: green for the heaviest kind you can
            -- wear, blue for a lighter one. Whether the piece is better is
            -- for the comparison rows to say.
            local RED = "|cffe57373"
            local tint
            if cant then
                -- Red on the type word when the type itself is the reason.
                if why == it.sub or (it.weight and bestArmor and it.weight > bestArmor) then tint = RED end
            elseif it.weight and bestArmor then
                if it.weight == bestArmor then tint = "|cff73d980"
                elseif it.weight < bestArmor then tint = "|cff73b3f2" end
            end
            local what
            if it.slotName then
                what = it.slotName
                if type(it.sub) == "string" and it.sub ~= "" and it.sub ~= it.slotName then
                    what = what .. "  \194\183  " .. (tint and (tint .. it.sub .. "|r") or it.sub)
                end
            else
                what = type(it.typ) == "string" and it.typ or ""
            end
            if cant then
                -- Gear you can't wear, or anything else you can't use.
                -- Same line as any other card, with the verdict last in
                -- parentheses; the reason follows unless it is just the
                -- armor type already shown.
                local note = it.slotName and "Can't equip" or "Can't use"
                if type(why) == "string" and why ~= "" and why ~= it.sub then note = note .. "  \194\183  " .. why end
                what = what .. (what ~= "" and "  " or "") .. RED .. "(" .. note .. ")|r"
            end
            t.what:SetText(what)
            t.what:SetTextColor(unpack(T.textDim))
            t.icon:SetDesaturated(cant)
            local c = t.qc
            if cant then t.name:SetTextColor(0.55, 0.55, 0.60)
            elseif c then t.name:SetTextColor(c.r, c.g, c.b)
            else t.name:SetTextColor(unpack(T.text)) end
            local rows = (not cant) and it.link and ns.CompareRows and call(ns.CompareRows, it.link, 6)
            local rowText = type(rows) == "table" and table.concat(rows, "     ") or ""
            t.rows:SetText(rowText)
            local v = t.price
            if v and v > 0 then
                t.sell:SetText(coins(v))
                t.sell:SetAlpha((t.kind ~= "choice" or v == best) and 1 or 0.55)
            elseif v == 0 then
                t.sell:SetText("No sell value"); t.sell:SetAlpha(0.55)
            else
                t.sell:SetText("")
            end
            -- Height: name, the line under it, the comparison, padding.
            -- (Explicit widths: a string's height can't be measured from
            -- anchors that haven't been resolved yet.)
            local textW = CW - 56 - 12
            t.name:SetWidth(math.max(80, textW - t.sell:GetStringWidth() - 10))
            t.what:SetWidth(textW)
            t.rows:SetWidth(textW)
            local whatText = t.what:GetText()
            local h = 10 + t.name:GetStringHeight()
                + ((whatText and whatText ~= "") and (3 + t.what:GetStringHeight()) or 0)
                + (rowText ~= "" and (6 + t.rows:GetStringHeight()) or 0) + 12
            h = math.max(56, math.ceil(h))
            if h ~= t.h then
                local dy = t.h - h
                t.h = h
                t:SetHeight(h)
                shiftAfter(t.idx, dy)
            end
        end
        return missing
    end
    if details() then
        local stamp = {}
        win.__sellStamp = stamp
        C_Timer.After(0.5, function()
            if win.__sellStamp == stamp and win:IsShown() then
                details()
                if D._finish then D._finish() end
            end
        end)
    end
end

local function moneyLine(copper, xp)
    local parts = {}
    if type(copper) == "number" and not secret(copper) and copper > 0 then
        local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
        local m = {}
        if g > 0 then table.insert(m, g .. "|cffe6c25a g|r") end
        if s > 0 then table.insert(m, s .. "|cffb8bcc6 s|r") end
        if c > 0 then table.insert(m, c .. "|cffc98a52 c|r") end
        table.insert(parts, table.concat(m, "  "))
    end
    if type(xp) == "number" and not secret(xp) and xp > 0 then
        table.insert(parts, (BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp) .. " XP")
    end
    if #parts == 0 then return end
    local f = fs(12, true)
    f:SetText(table.concat(parts, "     "))
    f:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y)
    y = y - f:GetStringHeight() - 12
end

-- Footer buttons, on the footer band. Ways out (Goodbye / Decline / Back,
-- marked leave = true) always sit bottom-left, so the exit is in the same
-- spot on every page; the rest go right, primary first from the right.
local function setActions(list)
    for _, b in ipairs(win.actions) do b:Hide() end
    local prev, prevLeft
    for i = #list, 1, -1 do
        local a = list[i]
        local b = win.actions[i]
        b:Set(a.label, a.onClick, a.primary)
        if a.disabled then b:SetEnabled(false); b:Repaint() end
        b:ClearAllPoints()
        if a.leave then
            if prevLeft then b:SetPoint("LEFT", prevLeft, "RIGHT", 8, 0) else b:SetPoint("LEFT", win.footer, "LEFT", 14, 0) end
            prevLeft = b
        else
            if prev then b:SetPoint("RIGHT", prev, "LEFT", -8, 0) else b:SetPoint("RIGHT", win.footer, "RIGHT", -14, 0) end
            prev = b
        end
    end
end

local function begin()
    resetPools()
    CW = W - 36
    y = -4
    selectedChoice = nil
    win.onChoice = nil
    win.__sellStamp = nil -- a late reward-card refill from the previous page no longer applies
end

local function finish()
    -- The window grows with its content, up to what fits between the
    -- console and the top of the screen. Past that, the speech text gives
    -- way first (it scrolls in its bubble); only if that isn't enough does
    -- the page itself scroll.
    local maxBody = math.max(MAX_BODY, UIParent:GetHeight() - 270 - (HEADER_H + 24 + FOOTER_H))
    local h = -y + 4
    if h > maxBody then
        local big
        for _, e in ipairs(bubbles) do if not big or e.h > big.h then big = e end end
        if big and big.h > BUBBLE_MIN then
            local cut = math.min(h - maxBody, big.h - BUBBLE_MIN)
            big.h = big.h - cut
            big.b:SetHeight(big.h)
            shiftAfter(big.idx, cut)
            h = -y + 4
            C_Timer.After(0, big.b.placeThumb)
        end
    end
    content:SetHeight(h)
    local bodyH = math.min(h, maxBody)
    body:SetHeight(bodyH)
    body:SetVerticalScroll(0)
    win:SetHeight(HEADER_H + 14 + bodyH + 10 + FOOTER_H)
    body.thumb:SetShown(h > maxBody)
end
D._finish = finish

-- ── Selecting (adaptive) ──────────────────────────────────────────────────
-- Clients differ on whether gossip selections take a quest/option ID or a
-- list position. Try the remembered (or first) way; if the NPC doesn't react
-- within a moment, try the next, and remember whichever worked per kind.
local responded = 0
local function trySelect(kind, variants)
    D.db.selectWay = D.db.selectWay or {}
    local order = {}
    local pref = D.db.selectWay[kind]
    if pref and variants[pref] then table.insert(order, pref) end
    for i = 1, #variants do if i ~= pref then table.insert(order, i) end end
    local function attempt(n)
        local way = order[n]
        if not way then
            ns:Print("That option didn't respond. Try Blizzard's dialog: Windows > NPC dialogs off.")
            return
        end
        local mark = responded
        pcall(variants[way])
        C_Timer.After(0.35, function()
            if responded ~= mark then
                D.db.selectWay[kind] = way
            elseif mode == "gossip" or mode == "quest" then
                attempt(n + 1)
            end
        end)
    end
    attempt(1)
end

local function selectQuest(active, q, pos)
    local byID = active and G.SelectActiveQuest or G.SelectAvailableQuest
    local old = active and _G.SelectGossipActiveQuest or _G.SelectGossipAvailableQuest
    trySelect(active and "active" or "available", {
        function() if q.questID and byID then byID(q.questID) else error("no id") end end,
        function() if byID then byID(pos) else error("no fn") end end,
        function() if old then old(pos) else error("no old") end end,
    })
end

local function selectOption(o, pos)
    trySelect("option", {
        function() if o.gossipOptionID and G.SelectOption then G.SelectOption(o.gossipOptionID) else error("no id") end end,
        function() if G.SelectOptionByIndex and o.orderIndex then G.SelectOptionByIndex(o.orderIndex) else error("x") end end,
        function() if G.SelectOption then G.SelectOption(pos) else error("x") end end,
        function() if _G.SelectGossipOption then SelectGossipOption(pos) else error("x") end end,
    })
end

-- ── Pages ─────────────────────────────────────────────────────────────────
local function gossipPage()
    unit = "npc"
    begin()
    updateHeader()
    bubble(call(G.GetText))
    local avail = call(G.GetAvailableQuests) or {}
    local active = call(G.GetActiveQuests) or {}
    if #avail > 0 then
        section("Available quests", #avail)
        for i, q in ipairs(avail) do
            questCard(q.title, q.questLevel, "available", function() selectQuest(false, q, i) end, q.isTrivial)
        end
        y = y - 6
    end
    if #active > 0 then
        section("In progress", #active)
        for i, q in ipairs(active) do
            questCard(q.title, q.questLevel, q.isComplete and "complete" or "active",
                function() selectQuest(true, q, i) end, q.isTrivial)
        end
        y = y - 6
    end
    local opts = call(G.GetOptions) or {}
    if #opts > 0 then
        section("Talk")
        local list = {}
        table.sort(opts, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
        for i, o in ipairs(opts) do
            table.insert(list, { name = o.name, icon = o.icon, onClick = function() selectOption(o, i) end })
        end
        talkPills(list)
    end
    finish()
    setActions({ { label = GOODBYE or "Goodbye", leave = true, onClick = function() win:Hide() end } })
end

local function greetingPage()
    unit = "questnpc"
    begin()
    updateHeader()
    bubble(call(_G.GetGreetingText))
    local na = call(_G.GetNumAvailableQuests) or 0
    if na > 0 then
        section("Available quests", na)
        for i = 1, na do
            local title = call(_G.GetAvailableTitle, i)
            local lvl = call(_G.GetAvailableLevel, i)
            questCard(title or "?", lvl, "available", function() call(_G.SelectAvailableQuest, i) end)
        end
        y = y - 6
    end
    local nact = call(_G.GetNumActiveQuests) or 0
    if nact > 0 then
        section("In progress", nact)
        for i = 1, nact do
            local title, complete = call(_G.GetActiveTitle, i)
            local lvl = call(_G.GetActiveLevel, i)
            questCard(title or "?", lvl, complete and "complete" or "active", function() call(_G.SelectActiveQuest, i) end)
        end
    end
    finish()
    setActions({ { label = GOODBYE or "Goodbye", leave = true, onClick = function() win:Hide() end } })
end

local function rewardList(includeChoices)
    local list = {}
    if includeChoices then
        for i = 1, (call(_G.GetNumQuestChoices) or 0) do
            local name, tex, count, quality, usable = call(_G.GetQuestItemInfo, "choice", i)
            if name then table.insert(list, { kind = "choice", index = i, name = name, tex = tex, count = count,
                                              quality = quality, usable = usable }) end
        end
    end
    local choices = #list
    for i = 1, (call(_G.GetNumQuestRewards) or 0) do
        local name, tex, count, quality, usable = call(_G.GetQuestItemInfo, "reward", i)
        if name then table.insert(list, { kind = "reward", index = i, name = name, tex = tex, count = count,
                                          quality = quality, usable = usable }) end
    end
    return list, choices
end

local function rewardsSection(includeChoices)
    local list, choices = rewardList(includeChoices)
    local money, xp = call(_G.GetRewardMoney), call(_G.GetRewardXP)
    if #list == 0 and not (money and money > 0) and not (xp and xp > 0) then return 0 end
    section(choices > 1 and "Rewards  ·  choose one" or "Rewards")
    if #list > 0 then rewardCards(list) end
    moneyLine(money, xp)
    return choices
end

-- Quest pages: with an NPC, the header is the NPC and the quest title sits
-- above the bubble; with none (wanted posters, items), the quest title is
-- the header.
local function questHeading()
    local qt = call(_G.GetTitleText) or ""
    if UnitExists(unit) then
        updateHeader()
        local title = fs(15, true)
        title:SetWidth(CW)
        title:SetText(qt)
        title:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y)
        y = y - title:GetStringHeight() - 2
    else
        updateHeader(qt)
    end
end

local function detailPage()
    unit = "questnpc"
    begin()
    questHeading()
    bubble(call(_G.GetQuestText))
    local obj = str(call(_G.GetObjectiveText))
    if obj then section("Objectives"); paragraph(obj, T.text) end
    rewardsSection(true)
    finish()
    setActions({
        { label = DECLINE or "Decline", leave = true, onClick = function() call(_G.DeclineQuest) end },
        { label = ACCEPT or "Accept", primary = true, onClick = function() call(_G.AcceptQuest) end },
    })
end

local function progressPage()
    unit = "questnpc"
    begin()
    questHeading()
    bubble(call(_G.GetProgressText))
    local need = {}
    for i = 1, (call(_G.GetNumQuestItems) or 0) do
        local name, tex, count = call(_G.GetQuestItemInfo, "required", i)
        if name then table.insert(need, { kind = "required", index = i, name = name, tex = tex, count = count }) end
    end
    if #need > 0 then section("Required items"); itemTiles(need) end
    finish()
    local can = call(_G.IsQuestCompletable)
    setActions({
        { label = GOODBYE or "Goodbye", leave = true, onClick = function() win:Hide() end },
        { label = CONTINUE or "Continue", primary = true, disabled = not can, onClick = function() call(_G.CompleteQuest) end },
    })
end

local function completePage()
    unit = "questnpc"
    begin()
    questHeading()
    bubble(call(_G.GetRewardText))
    local choices = rewardsSection(true)
    finish()
    local function complete()
        if choices > 1 and not selectedChoice then
            UIErrorsFrame:AddMessage("Pick a reward first.", 1, 0.82, 0)
            return
        end
        call(_G.GetQuestReward, choices > 0 and (selectedChoice or 1) or 0)
    end
    local function actions()
        setActions({ { label = COMPLETE_QUEST or "Complete quest", primary = true,
                       disabled = choices > 1 and not selectedChoice, onClick = complete } })
    end
    win.onChoice = actions
    actions()
end

-- ── Build / show ──────────────────────────────────────────────────────────
local function build()
    win = CreateFrame("Frame", "MinimalUIDialog", UIParent)
    win:SetWidth(W)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, yy = self:GetPoint(1)
        D.db.pos = { p, rp, x, yy }
    end)
    local pos = D.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -140) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIDialog")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    buildHeader()

    body = CreateFrame("ScrollFrame", nil, win)
    body:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(HEADER_H + 14))
    body:SetPoint("RIGHT", win, "RIGHT", -18, 0)
    body:SetHeight(100)
    content = CreateFrame("Frame", nil, body)
    content:SetSize(W - 36, 10)
    body:SetScrollChild(content)
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 40)))
        local th = self.thumb
        if th:IsShown() then
            local h = self:GetHeight()
            local size = h * h / content:GetHeight()
            th:SetHeight(size)
            th:ClearAllPoints()
            th:SetPoint("TOPRIGHT", self, "TOPRIGHT", 10, -(h - size) * (self:GetVerticalScroll() / max))
        end
    end)
    body.thumb = body:CreateTexture(nil, "OVERLAY")
    body.thumb:SetWidth(3)
    body.thumb:SetHeight(40)
    body.thumb:SetPoint("TOPRIGHT", body, "TOPRIGHT", 10, 0)
    body.thumb:SetColorTexture(0.32, 0.32, 0.36, 1)
    body.thumb:Hide()

    win.footer = ns:CreateFooter(win, FOOTER_H)
    win.actions = {}
    for i = 1, 3 do win.actions[i] = pill(win.footer) ; win.actions[i]:Hide() end

    -- Typewriter driver (~120 characters a second; click the bubble to skip).
    win:SetScript("OnUpdate", function(_, dt)
        local t = typer
        if not t then return end
        if t.done then t.pos = t.len + 20 else t.pos = t.pos + dt * 120 end
        t.fs:SetAlphaGradient(math.floor(t.pos), 12)
        if t.pos >= t.len + 12 then t.fs:SetAlphaGradient(100000, 1); typer = nil end
    end)

    win:SetScript("OnHide", function()
        typer = nil
        win.shell:ClearModel()
        if closingFromEvent then return end
        -- Closed by the player: end whatever conversation is open.
        local qf, gf = _G.QuestFrame, _G.GossipFrame
        if qf and qf:IsShown() then call(_G.CloseQuest) end
        if gf and gf:IsShown() then call(G.CloseGossip) end
        local rf = _G.GuildRegistrarFrame
        if rf and rf:IsShown() then call(_G.CloseGuildRegistrar) end
        mode = nil
    end)
end

-- ── Guild registrar ("How do I form a guild?") ────────────────────────────
-- Services as cards; buying a charter swaps in a name field.
local render -- defined below (forward declaration)
local regBuying = false
local function coinText(c)
    if type(c) ~= "number" or secret(c) or c <= 0 then return "" end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "|cffe6c25a g|r") end
    if s > 0 then table.insert(parts, s .. "|cffb8bcc6 s|r") end
    if cp > 0 then table.insert(parts, cp .. "|cffc98a52 c|r") end
    return table.concat(parts, "  ")
end

local function serviceCard(title, sub, onClick, enabled)
    local c = take("svc", function()
        local f = CreateFrame("Button", nil, content)
        f:SetHeight(44)
        f.ring = ns.RoundedRect(f, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
        f.fill = ns.RoundedRect(f, -7, 1, 9, unpack(CARD))
        f.title = text(f, 12, true)
        f.title:SetPoint("TOPLEFT", 14, -8)
        f.sub = text(f, 11, false, T.textDim)
        f.sub:SetPoint("BOTTOMLEFT", 14, 8)
        f.chev = {}
        for k = 1, 2 do
            local l = f:CreateLine(nil, "ARTWORK")
            l:SetThickness(1.5)
            l:SetColorTexture(unpack(T.textDim))
            f.chev[k] = l
        end
        f.chev[1]:SetStartPoint("RIGHT", f, -18, 4); f.chev[1]:SetEndPoint("RIGHT", f, -14, 0)
        f.chev[2]:SetStartPoint("RIGHT", f, -14, 0); f.chev[2]:SetEndPoint("RIGHT", f, -18, -4)
        f:SetScript("OnEnter", function(self)
            if self:IsEnabled() then self.ring(unpack(T.accent)); self.fill(0.13, 0.13, 0.15, 1) end
        end)
        f:SetScript("OnLeave", function(self)
            self.ring(T.border[1], T.border[2], T.border[3], 1); self.fill(unpack(CARD))
        end)
        return f
    end)
    c:SetWidth(CW)
    c:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    c.title:SetText(title)
    c.sub:SetText(sub or "")
    c:SetEnabled(enabled ~= false)
    c.title:SetTextColor(unpack(enabled ~= false and T.text or T.textDim))
    c:SetScript("OnClick", onClick)
    c.ring(T.border[1], T.border[2], T.border[3], 1); c.fill(unpack(CARD))
    y = y - 50
end

local registrarPage
registrarPage = function()
    unit = "npc"
    begin()
    updateHeader()
    local cost = call(_G.GetGuildCharterCost)
    if regBuying then
        section("Name your guild")
        local eb = take("edit", function()
            local e = CreateFrame("EditBox", nil, content)
            e:SetAutoFocus(false)
            e:SetHeight(30)
            e:SetTextInsets(12, 12, 0, 0)
            ns:SetFont(e, 12, "")
            e:SetTextColor(unpack(T.text))
            e:SetMaxLetters(24)
            ns.RoundedRect(e, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
            ns.RoundedRect(e, -7, 1, 13, 0.05, 0.05, 0.06, 1)
            e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            return e
        end)
        eb:SetWidth(CW)
        eb:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        eb:SetText("")
        eb:SetFocus()
        y = y - 42
        moneyLine(cost)
        finish()
        local function buy()
            local n = eb:GetText()
            if n and n ~= "" then
                call(_G.BuyGuildCharter, n)
                eb:ClearFocus()
                regBuying = false
            end
        end
        eb:SetScript("OnEnterPressed", buy)
        setActions({
            { label = BACK or "Back", leave = true, onClick = function() regBuying = false; render("registrar", registrarPage) end },
            { label = PURCHASE or "Purchase", primary = true, onClick = buy },
        })
        return
    end
    section("Services")
    serviceCard("Purchase a guild charter", coinText(cost),
        function() regBuying = true; render("registrar", registrarPage) end)
    local canTurnIn = true
    if _G.HasFilledPetition then canTurnIn = call(_G.HasFilledPetition) and true or false end
    serviceCard("Register a guild charter",
        canTurnIn and "Turn in your signed charter" or "Needs a charter with enough signatures",
        function() call(_G.TurnInGuildCharter) end, canTurnIn)
    finish()
    setActions({ { label = GOODBYE or "Goodbye", leave = true, onClick = function() win:Hide() end } })
end

-- Which page to draw for the quest frame (set by the quest events).
local questPage

render = function(newMode, page)
    if not win then build() end
    mode = newMode
    local ok, err = pcall(page)
    if not ok then ns:Print("Dialog: " .. tostring(err)) end
    if not win:IsShown() then win:Show() end
end

local function hideOurs()
    if win and win:IsShown() then
        closingFromEvent = true
        win:Hide()
        closingFromEvent = false
    end
    mode = nil
end

-- Blizzard's (invisible) frames are the source of truth: whichever one is
-- open decides what we show; when neither is, we close. Checked a frame
-- after any event or show/hide, so the order the game fires things in
-- (gossip -> quest hand-offs) doesn't matter.
local syncQueued, lastDrawn, pendingForce = false, nil, false
local function sync(f)
    if f then pendingForce = true end
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, function()
        syncQueued = false
        local force = pendingForce
        pendingForce = false
        local qf, gf, rf = _G.QuestFrame, _G.GossipFrame, _G.GuildRegistrarFrame
        if qf and qf:IsShown() and questPage then
            if force or lastDrawn ~= questPage or mode ~= "quest" then render("quest", questPage) end
            lastDrawn = questPage
        elseif rf and rf:IsShown() then
            if force or lastDrawn ~= registrarPage or mode ~= "registrar" then render("registrar", registrarPage) end
            lastDrawn = registrarPage
        elseif gf and gf:IsShown() then
            if force or lastDrawn ~= gossipPage or mode ~= "gossip" then render("gossip", gossipPage) end
            lastDrawn = gossipPage
        else
            lastDrawn = nil
            hideOurs()
        end
    end)
end

-- Blizzard's frames: open but invisible and unclickable.
local function ghost(f)
    if not f or f.__muiGhost then return end
    f.__muiGhost = true
    local function apply(self)
        self:SetAlpha(0)
        self:SetScale(0.001)
        self:EnableMouse(false)
    end
    f:HookScript("OnShow", function(self) apply(self); sync() end)
    f:HookScript("OnHide", function() sync() end)
    if f:IsShown() then apply(f) end
end

function D:OnInit(db)
    self.db = db
    ghost(_G.GossipFrame)
    ghost(_G.QuestFrame)
    ghost(_G.GuildRegistrarFrame)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GUILD_REGISTRAR_SHOW", "GUILD_REGISTRAR_CLOSED", "GUILDREGISTRAR_SHOW", "GUILDREGISTRAR_CLOSED",
                         "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
                         "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_ITEM_UPDATE", "MERCHANT_SHOW", "TRAINER_SHOW",
                         "TAXIMAP_OPENED", "BANKFRAME_OPENED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
                         "GOSSIP_CONFIRM", "GOSSIP_ENTER_CODE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e)
        responded = responded + 1 -- any reaction confirms a selection worked
        if e == "QUEST_GREETING" then questPage = greetingPage
        elseif e == "QUEST_DETAIL" then questPage = detailPage
        elseif e == "QUEST_PROGRESS" then questPage = progressPage
        elseif e == "QUEST_COMPLETE" then questPage = completePage
        elseif e == "QUEST_FINISHED" then questPage = nil
        elseif e == "GUILD_REGISTRAR_SHOW" or e == "GUILDREGISTRAR_SHOW" then
            regBuying = false
            ghost(_G.GuildRegistrarFrame) -- in case it loaded late
        end
        -- New page content (same frame still open) needs a redraw.
        local force = e == "GOSSIP_SHOW" or e == "QUEST_GREETING" or e == "QUEST_DETAIL"
            or e == "QUEST_PROGRESS" or e == "QUEST_COMPLETE" or e == "GUILD_REGISTRAR_SHOW"
            or e == "GUILDREGISTRAR_SHOW"
        sync(force)
    end)
end

-- /men typewriter : toggle the typing effect.
ns.commands.typewriter = function()
    if not D.db then return end
    D.db.typewriter = not D.db.typewriter
    ns:Print("Dialog typing effect " .. (D.db.typewriter and "on" or "off"))
end
