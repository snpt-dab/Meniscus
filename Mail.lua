local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Mailbox: Meniscus's mail window (shared header: mailbox icon, message
-- count, money, unread chip, "Open all" pill in the band).
--   Inbox: mail cards on the left (unread dot, sender, subject, days left,
--   money / item count), the selected letter on the right (body, money,
--   attachments, Reply / Return / Delete / Take all). Clicking an
--   attachment takes it (COD asks first).
--   Send: To, Subject, body, 12 attachment slots (right-click an item in the
--   bags, or drop it on the window), money or C.O.D., postage.
-- Blizzard's mail frame stays open but invisible (closing it ends the visit).

local ML = ns:NewModule("Mail", { enabled = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local W = 700
local LIST_W = 300
local CARD_H = 46
local PER = 8
local TABS_Y = (ns.SHELL_H or 92) + 12
local LIST_TOP = TABS_Y + 36
local PANE_H = PER * (CARD_H + 6) - 6
local H = LIST_TOP + PANE_H + 52
local PANE_X = 18 + LIST_W + 14
local PANE_W = W - PANE_X - 18
local MAX_RECV = _G.ATTACHMENTS_MAX_RECEIVE or 16
local MAX_SEND = _G.ATTACHMENTS_MAX_SEND or 12
local LETTER = "Interface/Icons/INV_Letter_15"
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local CARD = { 0.10, 0.10, 0.115, 1 }
local FIELD = { 0.05, 0.05, 0.06, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local RED = { 0.95, 0.42, 0.40 }

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
    if not num(c) then return "" end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    local col = red and "|cfff26b66" or "|cffeeeef2"
    if g > 0 then table.insert(parts, col .. g .. "|r|cffe6c25a g|r") end
    if s > 0 then table.insert(parts, col .. s .. "|r|cffb8bcc6 s|r") end
    if cp > 0 or #parts == 0 then table.insert(parts, col .. cp .. "|r|cffc98a52 c|r") end
    return table.concat(parts, " ")
end

-- Bordered field (edit box look shared with the guild registrar).
local function field(parent, w, h, multi)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetAutoFocus(false)
    e:SetSize(w, h)
    e:SetTextInsets(10, 10, 0, 0)
    ns:SetFont(e, 12, "")
    e:SetTextColor(unpack(T.text))
    if not multi then
        e.ring = ns.RoundedRect(e, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(e, -7, 1, 11, unpack(FIELD))
    end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self) if self.ring then self.ring(unpack(T.accent)) end end)
    e:SetScript("OnEditFocusLost", function(self)
        if self.ring then self.ring(T.border[1], T.border[2], T.border[3], 1) end
    end)
    return e
end

-- Item tile: rounded icon in a quality ring, stack count.
local function tile(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.ring = ns.RoundedRect(b, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    b.fill = ns.RoundedRect(b, -7, 1, 6, unpack(FIELD))
    local mask = b:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2); mask:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(mask)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:AddMaskTexture(mask)
    b.count = b:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.count, 10, "OUTLINE", true)
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    function b:SetItem(tex, count, quality)
        self.icon:SetTexture(tex)
        self.icon:SetShown(tex ~= nil)
        self.count:SetText(num(count) and count > 1 and count or "")
        local col = num(quality) and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        self.rr, self.rg, self.rb = col and col.r or T.border[1], col and col.g or T.border[2], col and col.b or T.border[3]
        self.ring(self.rr, self.rg, self.rb, 1)
    end
    b:HookScript("OnEnter", function(self) self.ring(unpack(T.accent)) end)
    b:HookScript("OnLeave", function(self)
        self.ring(self.rr or T.border[1], self.rg or T.border[2], self.rb or T.border[3], 1)
        GameTooltip:Hide()
    end)
    return b
end

-- ── Data ──────────────────────────────────────────────────────────────────
local function header(i)
    local pkg, stat, sender, subject, cash, cod, days, items, wasRead, returned, _, canReply, isGM =
        call(_G.GetInboxHeaderInfo, i)
    if items == true then items = 1 end
    return {
        icon = pkg or stat or LETTER, sender = sender or (UNKNOWN or "Unknown"), subject = subject or "",
        money = num(cash) and cash or 0, cod = num(cod) and cod or 0, days = num(days) and days or nil,
        items = num(items) and items or 0, read = wasRead and true or false, returned = returned and true or false,
        canReply = canReply and true or false, gm = isGM and true or false,
    }
end

local function counts()
    local shown, total = call(_G.GetInboxNumItems)
    shown = num(shown) and shown or 0
    return shown, num(total) and total or shown
end

local function firstAttachment(i)
    for a = 1, MAX_RECV do
        if call(_G.GetInboxItem, i, a) then return a end
    end
end

local function freeBagSlots()
    local n = 0
    local CC = C_Container
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local free = CC and CC.GetContainerNumFreeSlots and call(CC.GetContainerNumFreeSlots, bag)
            or call(_G.GetContainerNumFreeSlots, bag)
        if num(free) then n = n + free end
    end
    return n
end

local function daysText(d)
    if not d then return "", T.textDim end
    if d < 1 then return "< 1 day", RED end
    local n = math.floor(d)
    return n .. (n == 1 and " day" or " days"), d < 3 and RED or T.textDim
end

-- Auction house mail: turn the invoice into readable lines.
local function invoiceText(i)
    local kind, item, who, bid, buyout, deposit, cut = call(_G.GetInboxInvoiceInfo, i)
    if not kind then return nil end
    item, who = item or "?", who or "?"
    local lines = {}
    if kind == "buyer" then
        table.insert(lines, "You won " .. item .. " from " .. who .. ".")
        table.insert(lines, "Price paid: " .. money(bid))
    elseif kind == "seller" then
        table.insert(lines, "You sold " .. item .. " to " .. who .. ".")
        table.insert(lines, "Sale price: " .. money(bid))
        if num(deposit) and deposit > 0 then table.insert(lines, "Deposit returned: " .. money(deposit)) end
        if num(cut) and cut > 0 then table.insert(lines, "Auction house cut: " .. money(cut, true)) end
        if num(bid) then
            table.insert(lines, "Total: " .. money(bid + (num(deposit) and deposit or 0) - (num(cut) and cut or 0)))
        end
    elseif kind == "seller_temp_invoice" then
        table.insert(lines, "Sale pending: " .. item .. " to " .. who .. ".")
        table.insert(lines, "Your gold arrives within the hour.")
    end
    return table.concat(lines, "\n")
end

-- ── Taking mail, step by step ──────────────────────────────────────────────
-- One server action at a time (money, or one attachment), a short pause
-- between them; mail indexes shift as emptied letters vanish, so each step
-- looks again. mode "one" = the selected letter, "all" = every letter
-- without C.O.D.
local taker = CreateFrame("Frame")
taker:Hide()
local takeAcc = 0

local function stopTaking()
    ML.taking = nil
    taker:Hide()
    if ML.Refresh then ML:Refresh() end
end

local function takeStep()
    local job = ML.taking
    if not job then return stopTaking() end
    job.steps = job.steps + 1
    if job.steps > 200 then return stopTaking() end
    local shown = counts()
    local function stepOn(i)
        local h = header(i)
        if h.cod > 0 then return false end
        if h.money > 0 then call(_G.TakeInboxMoney, i); return true end
        local a = h.items > 0 and firstAttachment(i)
        if a then
            if freeBagSlots() < 1 then
                UIErrorsFrame:AddMessage(ERR_INV_FULL or "Inventory is full.", 1, 0.1, 0.1)
                stopTaking()
                return true
            end
            call(_G.TakeInboxItem, i, a)
            return true
        end
        return false
    end
    if job.mode == "one" then
        if job.index > shown or not stepOn(job.index) then stopTaking() end
        return
    end
    for i = 1, shown do
        if stepOn(i) then return end
    end
    stopTaking()
end

taker:SetScript("OnUpdate", function(self, dt)
    takeAcc = takeAcc + dt
    if takeAcc < 0.35 then return end
    takeAcc = 0
    takeStep()
end)

local function startTaking(mode, index)
    ML.taking = { mode = mode, index = index, steps = 0 }
    takeAcc = 0.35
    taker:Show()
    ML:Refresh()
end

local function openableCount()
    local n = 0
    local shown = counts()
    for i = 1, shown do
        local h = header(i)
        if h.cod == 0 and (h.money > 0 or h.items > 0) then n = n + 1 end
    end
    return n
end

StaticPopupDialogs["MINIMALUI_MAIL_COD"] = {
    text = "Pay %s C.O.D. to take this item?",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, data) if data then call(_G.TakeInboxItem, data.index, data.att) end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["MINIMALUI_MAIL_DELETE"] = {
    text = "Delete this letter? Its money and items will be lost.",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, data) if data then call(_G.DeleteInboxItem, data); ML.selected = nil end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

-- ── Window ────────────────────────────────────────────────────────────────
local win, cards, tabBtns, recvTiles, sendTiles = nil, {}, {}, {}, {}
local closing = false

local function setInteract()
    local B = ns.modules.Bags
    if not (B and B.SetInteract) then return end
    local want = win and win:IsShown() and ML.tab == "send" and "mail" or nil
    if B.interact ~= want then B:SetInteract(want) end
end

local function firstFreeSendSlot()
    for i = 1, MAX_SEND do
        if not call(_G.GetSendMailItem, i) then return i end
    end
end

local function attachCursor()
    if not CursorHasItem() then return end
    local slot = firstFreeSendSlot()
    if slot then call(_G.ClickSendMailItemButton, slot)
    else UIErrorsFrame:AddMessage("No free attachment slots.", 1, 0.1, 0.1) end
end

-- Bags call this on right-click while the Send tab is open.
function ML:AttachFromBag(bag, slot)
    local free = firstFreeSendSlot()
    if not free then UIErrorsFrame:AddMessage("No free attachment slots.", 1, 0.1, 0.1); return end
    if C_Container and C_Container.PickupContainerItem then call(C_Container.PickupContainerItem, bag, slot)
    else call(_G.PickupContainerItem, bag, slot) end
    if CursorHasItem() then call(_G.ClickSendMailItemButton, free) end
end

local function newCard(i)
    local c = CreateFrame("Button", nil, win.inbox)
    c:SetSize(LIST_W, CARD_H)
    c.ring = ns.RoundedRect(c, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
    c.fill = ns.RoundedRect(c, -7, 1, 9, unpack(CARD))
    c.tile = tile(c, 36)
    c.tile:SetPoint("LEFT", 5, 0)
    c.tile:EnableMouse(false)
    c.dot = c:CreateTexture(nil, "OVERLAY")
    c.dot:SetSize(7, 7)
    c.dot:SetPoint("TOPLEFT", 3, -3)
    c.dot:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask")
    c.dot:SetVertexColor(unpack(T.accent))
    c.sender = text(c, 12, true)
    c.sender:SetPoint("TOPLEFT", c.tile, "TOPRIGHT", 8, -2)
    c.sender:SetPoint("RIGHT", c, "RIGHT", -70, 0)
    c.sender:SetJustifyH("LEFT"); c.sender:SetWordWrap(false)
    c.subject = text(c, 11, false, T.textDim)
    c.subject:SetPoint("BOTTOMLEFT", c.tile, "BOTTOMRIGHT", 8, 2)
    c.subject:SetPoint("RIGHT", c, "RIGHT", -90, 0)
    c.subject:SetJustifyH("LEFT"); c.subject:SetWordWrap(false)
    c.days = text(c, 10, false, T.textDim)
    c.days:SetPoint("TOPRIGHT", -10, -8)
    c.extra = text(c, 10, true)
    c.extra:SetPoint("BOTTOMRIGHT", -10, 8)
    c:SetScript("OnEnter", function(self) if ML.selected ~= self.index then self.fill(0.13, 0.13, 0.15, 1) end end)
    c:SetScript("OnLeave", function(self) if ML.selected ~= self.index then self.fill(unpack(CARD)) end end)
    c:SetScript("OnClick", function(self)
        ML.selected = self.index
        ML:Refresh()
    end)
    c:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(LIST_TOP + (i - 1) * (CARD_H + 6)))
    return c
end

-- Selected letter: reading pane on the right.
local function buildPane()
    local p = CreateFrame("Frame", nil, win.inbox)
    p:SetPoint("TOPLEFT", win, "TOPLEFT", PANE_X, -LIST_TOP)
    p:SetSize(PANE_W, PANE_H)
    ns.RoundedRect(p, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(p, -7, 1, 11, unpack(CARD))
    p.subject = text(p, 14, true)
    p.subject:SetPoint("TOPLEFT", 14, -14)
    p.subject:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    p.subject:SetJustifyH("LEFT"); p.subject:SetWordWrap(false)
    p.from = text(p, 11, false, T.textDim)
    p.from:SetPoint("TOPLEFT", p.subject, "BOTTOMLEFT", 0, -5)
    p.from:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    p.from:SetJustifyH("LEFT"); p.from:SetWordWrap(false)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, -56); line:SetPoint("TOPRIGHT", -12, -56)

    -- Body: scrolls with the wheel when long.
    local sf = CreateFrame("ScrollFrame", nil, p)
    sf:SetPoint("TOPLEFT", 14, -66)
    sf:SetPoint("RIGHT", p, "RIGHT", -14, 0)
    sf:EnableMouseWheel(true)
    local body = CreateFrame("Frame", nil, sf)
    body:SetWidth(PANE_W - 28)
    body:SetHeight(1)
    sf:SetScrollChild(body)
    p.body = text(body, 12)
    p.body:SetPoint("TOPLEFT")
    p.body:SetWidth(PANE_W - 28)
    p.body:SetJustifyH("LEFT"); p.body:SetJustifyV("TOP")
    p.body:SetSpacing(3)
    sf:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, p.body:GetStringHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 30)))
    end)
    p.sf = sf

    p.moneyLine = text(p, 12, true)
    p.takeMoney = pill(p, "Take", function()
        if ML.selected then call(_G.TakeInboxMoney, ML.selected) end
    end)
    p.takeMoney:SetPoint("LEFT", p.moneyLine, "RIGHT", 10, 0)

    -- Attachments: 8 per row, two rows.
    p.attLabel = text(p, 10, true, T.textDim)
    p.attLabel:SetText("ATTACHMENTS")
    local TS, GAP = 34, 5
    for a = 1, MAX_RECV do
        local t = tile(p, TS)
        local col, row = (a - 1) % 8, math.floor((a - 1) / 8)
        t:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14 + col * (TS + GAP), 44 + (1 - row) * (TS + GAP))
        t.att = a
        t:SetScript("OnEnter", function(self)
            ns.TipAnchor(self)
            pcall(GameTooltip.SetInboxItem, GameTooltip, ML.selected, self.att)
            GameTooltip:Show()
        end)
        t:SetScript("OnClick", function(self)
            local i = ML.selected
            if not i then return end
            if IsModifiedClick() then
                local link = call(_G.GetInboxItemLink, i, self.att)
                if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
            end
            local h = header(i)
            if h.cod > 0 then
                StaticPopup_Show("MINIMALUI_MAIL_COD", money(h.cod), nil, { index = i, att = self.att })
                return
            end
            call(_G.TakeInboxItem, i, self.att)
        end)
        recvTiles[a] = t
    end
    p.attLabel:SetPoint("BOTTOMLEFT", recvTiles[1], "TOPLEFT", 0, 6)

    -- Actions.
    p.takeAll = pill(p, "Take all", function()
        if ML.taking then stopTaking() elseif ML.selected then startTaking("one", ML.selected) end
    end)
    p.takeAll.on = true
    p.takeAll:SetPoint("BOTTOMRIGHT", -12, 12)
    p.reply = pill(p, REPLY_MESSAGE or "Reply", function()
        local i = ML.selected
        if not i then return end
        local h = header(i)
        ML.tab = "send"
        ML:Refresh()
        win.to:SetText(h.sender or "")
        local subj = h.subject or ""
        if subj ~= "" and not subj:find("^[Rr][Ee]:") then subj = "RE: " .. subj end
        win.subj:SetText(subj)
        win.body:SetFocus()
    end)
    p.reply:SetPoint("BOTTOMLEFT", 12, 12)
    p.remove = pill(p, DELETE or "Delete", function()
        local i = ML.selected
        if not i then return end
        if call(_G.InboxItemCanDelete, i) then
            local h = header(i)
            if h.money > 0 or h.items > 0 then
                StaticPopup_Show("MINIMALUI_MAIL_DELETE", nil, nil, i)
            else
                call(_G.DeleteInboxItem, i)
                ML.selected = nil
            end
        else
            call(_G.ReturnInboxItem, i)
            ML.selected = nil
        end
    end)
    p.remove:SetPoint("LEFT", p.reply, "RIGHT", 6, 0)

    p.empty = text(p, 12, false, T.textDim)
    p.empty:SetPoint("CENTER")
    p.empty:SetText("Select a letter to read it.")
    win.pane = p
end

local function buildSend()
    local s = CreateFrame("Frame", nil, win)
    s:SetAllPoints()
    win.send = s
    local function label(t, x, y)
        local fs = text(s, 10, true, T.textDim)
        fs:SetText(t)
        fs:SetPoint("TOPLEFT", win, "TOPLEFT", x, -y)
        return fs
    end
    local y = LIST_TOP
    local half = (W - 36 - 12) / 2
    label("TO", 18, y)
    label("SUBJECT", 18 + half + 12, y)
    win.to = field(s, half, 30)
    win.to:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(y + 16))
    win.subj = field(s, half, 30)
    win.subj:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + half + 12, -(y + 16))
    win.subj:SetMaxLetters(64)
    y = y + 58

    -- Body: a bordered box holding a scrolling multi-line edit box.
    label("MESSAGE", 18, y)
    local box = CreateFrame("Frame", nil, s)
    box:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(y + 16))
    box:SetSize(W - 36, 180)
    local boxRing = ns.RoundedRect(box, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(box, -7, 1, 11, unpack(FIELD))
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 10, -8)
    sf:SetPoint("BOTTOMRIGHT", -10, 8)
    local body = field(sf, W - 56, 160, true)
    body:SetMultiLine(true)
    body:SetTextInsets(0, 0, 0, 0)
    body:SetMaxLetters(500)
    sf:SetScrollChild(body)
    body.ring = boxRing
    body:SetScript("OnCursorChanged", function(self, _, cy, _, ch)
        if _G.ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, 0, cy, 0, ch) end
    end)
    body:SetScript("OnUpdate", function(self, e)
        if _G.ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, e, sf) end
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() body:SetFocus() end)
    win.body = body
    y = y + 16 + 180 + 14

    -- Attachments.
    label("ATTACHMENTS", 18, y)
    local TS, GAP = 44, 8
    for i = 1, MAX_SEND do
        local t = tile(s, TS)
        t:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + (i - 1) * (TS + GAP), -(y + 16))
        t.slot = i
        t:RegisterForDrag("LeftButton")
        t:SetScript("OnEnter", function(self)
            if not call(_G.GetSendMailItem, self.slot) then return end
            ns.TipAnchor(self)
            pcall(GameTooltip.SetSendMailItem, GameTooltip, self.slot)
            GameTooltip:Show()
        end)
        t:SetScript("OnClick", function(self, button)
            if button == "RightButton" and not CursorHasItem() then
                call(_G.ClickSendMailItemButton, self.slot, true) -- back to the bags
            else
                call(_G.ClickSendMailItemButton, self.slot)
            end
        end)
        t:SetScript("OnDragStart", function(self) call(_G.ClickSendMailItemButton, self.slot) end)
        t:SetScript("OnReceiveDrag", function(self) call(_G.ClickSendMailItemButton, self.slot) end)
        sendTiles[i] = t
    end
    y = y + 16 + TS + 14

    -- Money: gold / silver / copper, sent or asked for (C.O.D.).
    label("MONEY", 18, y)
    local x = 18
    win.coin = {}
    for _, k in ipairs({ { "g", "|cffe6c25ag|r", 6 }, { "s", "|cffb8bcc6s|r", 2 }, { "c", "|cffc98a52c|r", 2 } }) do
        local e = field(s, k[3] == 6 and 90 or 56, 30)
        e:SetNumeric(true)
        e:SetMaxLetters(k[3])
        e:SetTextInsets(10, 20, 0, 0)
        e:SetPoint("TOPLEFT", win, "TOPLEFT", x, -(y + 16))
        local suf = text(e, 11, true)
        suf:SetPoint("RIGHT", -8, 0)
        suf:SetText(k[2])
        e:SetScript("OnTextChanged", function() ML:RefreshSend() end)
        win.coin[k[1]] = e
        x = x + e:GetWidth() + 6
    end
    ML.moneyMode = "send"
    win.modeBtns = {}
    x = x + 10
    for _, m in ipairs({ { "send", "Send money" }, { "cod", "C.O.D." } }) do
        local b = pill(s, m[2], function() ML.moneyMode = m[1]; ML:RefreshSend() end)
        b.key = m[1]
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -(y + 16 + 4))
        x = x + b:GetWidth() + 6
        table.insert(win.modeBtns, b)
    end

    -- Bottom row: postage, status, Send.
    win.postage = text(s, 11, false, T.textDim)
    win.postage:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 20, 22)
    win.status = text(s, 11, true)
    win.status:SetPoint("LEFT", win.postage, "RIGHT", 16, 0)
    win.sendBtn = pill(s, SEND_LABEL or "Send", function() ML:Send() end)
    win.sendBtn.on = true
    win.sendBtn:SetWidth(90)
    win.sendBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -18, 16)

    -- Tab order: To (1) -> Subject (2) -> Message (3) -> To; Shift+Tab goes
    -- back. Landing on To or Subject selects what's there, so typing
    -- replaces it; the message keeps its text and gets the cursor at the
    -- end. Enter in To / Subject moves on too. Money fields aren't in the
    -- order (Tab from one of them goes to To).
    local order = { win.to, win.subj, win.body }
    local function go(from, step)
        local i = 1
        for n, e in ipairs(order) do if e == from then i = n end end
        local e = order[(i - 1 + step) % #order + 1]
        e:SetFocus()
        if e == win.body then
            e:SetCursorPosition(#(e:GetText() or ""))
        else
            e:HighlightText()
            e.typed = "" -- so the first letter typed over the selection completes
        end
    end
    local function onTab(self) go(self, IsShiftKeyDown() and -1 or 1) end
    for _, e in ipairs(order) do e:SetScript("OnTabPressed", onTab) end
    win.to:SetScript("OnEnterPressed", function(self) go(self, 1) end)
    win.subj:SetScript("OnEnterPressed", function(self) go(self, 1) end)
    for _, e in pairs(win.coin) do
        e:SetScript("OnTabPressed", function() win.to:SetFocus(); win.to:HighlightText(); win.to.typed = "" end)
    end
    win.to:SetScript("OnTextChanged", function(self, userInput)
        ML.CompleteName(self, userInput)
        ML:RefreshSend()
    end)
    win.to:HookScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
end

-- ── Recipient auto-complete ───────────────────────────────────────────────
-- Type the start of a name and the rest is filled in, selected, so typing on
-- replaces it and Tab / Enter accepts it. Looked up in: your other
-- characters (remembered as you log into them), friends, guild members,
-- then whatever the client's own mail auto-complete offers.
local function myRealm()
    local r = call(_G.GetNormalizedRealmName)
    if type(r) ~= "string" or r == "" then r = (call(_G.GetRealmName) or ""):gsub("[%s%-]", "") end
    return r
end

local function startsWith(name, lq)
    return type(name) == "string" and not secret(name) and #name > #lq and name:lower():sub(1, #lq) == lq
end

local function suggestName(typed)
    local lq = typed:lower()
    local me, realm = UnitName("player"), myRealm()
    -- Alts: same realm by name, others as Name-Realm.
    local chars = MinimalUIDB and MinimalUIDB.chars
    if type(chars) == "table" then
        for r, names in pairs(chars) do
            for n in pairs(names) do
                local full = (r == realm) and n or (n .. "-" .. r)
                if not (r == realm and n == me) and startsWith(full, lq) then return full end
            end
        end
    end
    -- Friends.
    local FL = C_FriendList
    if FL and FL.GetNumFriends and FL.GetFriendInfoByIndex then
        local n = call(FL.GetNumFriends)
        for i = 1, num(n) and n or 0 do
            local info = call(FL.GetFriendInfoByIndex, i)
            local name = type(info) == "table" and info.name
            if startsWith(name, lq) then return name end
        end
    end
    -- Guild (names come as Name-Realm; drop our own realm).
    if _G.GetNumGuildMembers and _G.GetGuildRosterInfo and IsInGuild and IsInGuild() then
        local n = call(GetNumGuildMembers)
        for i = 1, num(n) and n or 0 do
            local name = call(GetGuildRosterInfo, i)
            if type(name) == "string" and not secret(name) then
                if _G.Ambiguate then name = call(Ambiguate, name, "mail") or name end
                if name ~= me and startsWith(name, lq) then return name end
            end
        end
    end
    -- The client's own list (recently seen players, etc.).
    local list = _G.AUTOCOMPLETE_LIST and AUTOCOMPLETE_LIST.MAIL
    if _G.GetAutoCompleteResults and type(list) == "table" then
        local res = call(GetAutoCompleteResults, typed, 1, #typed, true, list.include, list.exclude)
        local first = type(res) == "table" and res[1]
        local name = type(first) == "table" and first.name or first
        if startsWith(name, lq) then return name end
    end
end

-- Runs when the To text changes by typing. Completes only when the text got
-- longer than what was last typed, so deleting never re-completes.
function ML.CompleteName(self, userInput)
    ML.toChanges = (ML.toChanges or 0) + 1
    if not userInput then return end
    -- Complete unless this change was a deletion (the new text is just the
    -- start of what was typed before).
    local t = self:GetText() or ""
    local prev = self.typed or ""
    self.typed = t
    if t == "" or prev:sub(1, #t) == t then return end
    local name = suggestName(t)
    if not name then return end
    ML.toCompletions = (ML.toCompletions or 0) + 1
    self:SetText(name)
    self:HighlightText(#t, #name)
    self:SetCursorPosition(#t)
end

local function coinValue()
    local function v(k) return tonumber(win.coin[k]:GetText()) or 0 end
    return v("g") * 10000 + math.min(v("s"), 99) * 100 + math.min(v("c"), 99)
end

local function clearSend()
    win.to:SetText(""); win.subj:SetText(""); win.body:SetText("")
    for _, e in pairs(win.coin) do e:SetText("") end
    ML.moneyMode = "send"
    ML.autoSubj = nil
end

function ML:Send()
    local to = strtrim(win.to:GetText() or "")
    if to == "" then win.status:SetText("|cfff26b66Who is it for?|r"); return end
    local subject = strtrim(win.subj:GetText() or "")
    local firstItem
    for i = 1, MAX_SEND do
        local name = call(_G.GetSendMailItem, i)
        if name then firstItem = name; break end
    end
    if subject == "" then subject = firstItem or "" end
    if subject == "" then win.status:SetText("|cfff26b66Add a subject.|r"); return end
    local copper = coinValue()
    if self.moneyMode == "cod" then
        if copper > 0 and not firstItem then win.status:SetText("|cfff26b66C.O.D. needs an attachment.|r"); return end
        call(_G.SetSendMailMoney, 0)
        call(_G.SetSendMailCOD, copper)
    else
        call(_G.SetSendMailCOD, 0)
        if call(_G.SetSendMailMoney, copper) == false then
            win.status:SetText("|cfff26b66Not enough money.|r"); return
        end
    end
    win.status:SetText("Sending…")
    win.to:ClearFocus(); win.subj:ClearFocus(); win.body:ClearFocus()
    call(_G.SendMail, to, subject, win.body:GetText() or "")
end

function ML:RefreshSend()
    if not win or not win.send:IsShown() then return end
    for _, b in ipairs(win.modeBtns) do b.on = (b.key == self.moneyMode); b:Repaint() end
    local firstName, firstCount
    for i = 1, MAX_SEND do
        local name, _, tex, count, quality = call(_G.GetSendMailItem, i)
        sendTiles[i]:SetItem(name and tex or nil, count, quality)
        if name and not firstName then firstName, firstCount = name, count end
    end
    -- Subject follows the first attachment ("Linen Cloth (20)") until you
    -- type your own.
    local cur = win.subj:GetText() or ""
    if type(firstName) == "string" and not secret(firstName) then
        if cur == "" or cur == self.autoSubj then
            local auto = firstName
            if num(firstCount) and firstCount > 1 then auto = auto .. " (" .. firstCount .. ")" end
            if cur ~= auto then win.subj:SetText(auto) end
            self.autoSubj = auto
        end
    elseif self.autoSubj then
        if cur == self.autoSubj then win.subj:SetText("") end
        self.autoSubj = nil
    end
    local postage = call(_G.GetSendMailPrice)
    local copper = self.moneyMode == "send" and coinValue() or 0
    local myMoney = GetMoney()
    local cost = (num(postage) and postage or 0) + copper
    win.postage:SetText("Postage " .. money(postage) .. (copper > 0 and ("   ·   Total " .. money(cost, cost > myMoney)) or ""))
    win.sendBtn:SetEnabled(strtrim(win.to:GetText() or "") ~= "" and cost <= myMoney)
end

local function refreshPane()
    local p = win.pane
    local i = ML.selected
    local shown = counts()
    if not i or i > shown then
        ML.selected = nil
        for _, r in ipairs({ p.subject, p.from, p.sf, p.moneyLine, p.takeMoney, p.attLabel, p.takeAll, p.reply,
                             p.remove }) do r:Hide() end
        for _, t in ipairs(recvTiles) do t:Hide() end
        p.empty:SetShown(shown > 0)
        return
    end
    p.empty:Hide()
    local h = header(i)
    p.subject:SetText(h.subject ~= "" and h.subject or "(no subject)")
    local dt, dcol = daysText(h.days)
    p.from:SetText("From " .. h.sender .. (dt ~= "" and ("   ·   " .. (dcol == RED and "|cfff26b66" or "") .. dt
        .. " left" .. (dcol == RED and "|r" or "")) or "") .. (h.returned and "   ·   Returned" or ""))
    for _, r in ipairs({ p.subject, p.from, p.sf, p.reply, p.remove }) do r:Show() end

    local body, _, _, _, isInvoice = call(_G.GetInboxText, i)
    local txt = isInvoice and invoiceText(i) or body
    p.body:SetText((txt and txt ~= "") and txt or "|cff8c8c94(No message.)|r")
    p.sf:SetVerticalScroll(0)
    p.body:GetParent():SetHeight(math.max(1, p.body:GetStringHeight()))

    -- Money / C.O.D. line.
    local anchorY = 44 -- body's bottom edge rises above whatever is shown below it
    local atts = 0
    for a = 1, MAX_RECV do
        local name, _, tex, count, quality = call(_G.GetInboxItem, i, a)
        local t = recvTiles[a]
        if name then
            atts = atts + 1
            t:SetItem(tex, count, quality)
            t:Show()
        else
            t:Hide()
        end
    end
    if atts > 0 then
        p.attLabel:Show()
        anchorY = 44 + ((atts > 8) and 2 or 1) * 39 + 18
        -- One row: drop the tiles to the lower row so they sit above the actions.
        for a = 1, 8 do
            recvTiles[a]:ClearAllPoints()
            recvTiles[a]:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14 + (a - 1) * 39, 44 + (atts > 8 and 39 or 0))
        end
    else
        p.attLabel:Hide()
    end
    if h.money > 0 or h.cod > 0 then
        p.moneyLine:ClearAllPoints()
        p.moneyLine:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, anchorY + 10)
        if h.cod > 0 then
            p.moneyLine:SetText("|cfff26b66C.O.D.|r  " .. money(h.cod, h.cod > GetMoney()))
            p.takeMoney:Hide()
        else
            p.moneyLine:SetText(money(h.money))
            p.takeMoney:Show()
        end
        p.moneyLine:Show()
        anchorY = anchorY + 40
    else
        p.moneyLine:Hide(); p.takeMoney:Hide()
    end
    p.sf:ClearAllPoints()
    p.sf:SetPoint("TOPLEFT", 14, -66)
    p.sf:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, anchorY + 6)

    local canTake = h.cod == 0 and (h.money > 0 or atts > 0)
    p.takeAll:SetShown(canTake or (ML.taking and ML.taking.mode == "one"))
    p.takeAll:SetLabel(ML.taking and ML.taking.mode == "one" and "Stop" or "Take all")
    p.reply:SetEnabled(h.canReply and not h.gm)
    local canDelete = call(_G.InboxItemCanDelete, i)
    p.remove:SetLabel(canDelete and (DELETE or "Delete") or "Return")
    p.remove:SetEnabled(canDelete or (h.canReply and not h.returned))
end

function ML:Refresh()
    if not win or not win:IsShown() then return end
    for _, b in ipairs(tabBtns) do b.on = (b.key == self.tab); b:Repaint() end
    win.inbox:SetShown(self.tab == "inbox")
    win.send:SetShown(self.tab == "send")
    setInteract()

    local shown, total = counts()
    local unread = 0
    for i = 1, shown do if not header(i).read then unread = unread + 1 end end
    local sh = win.shell
    sh:SetTitle(MAIL_LABEL or "Mailbox")
    local countText = total == 1 and "1 letter" or (total .. " letters")
    if total > shown then countText = countText .. " (" .. shown .. " shown)" end
    sh:SetSubtitle(countText .. "   ·   " .. money(GetMoney()))
    if unread > 0 then sh:SetChip(unread .. " unread") else sh:SetChip(nil) end
    local openable = openableCount()
    if self.taking and self.taking.mode == "all" then
        win.openAll:SetLabel("Stop"); win.openAll:Show()
    elseif openable > 0 and self.tab == "inbox" then
        win.openAll:SetLabel(string.format("Open all (%d)", openable)); win.openAll:Show()
    else
        win.openAll:Hide()
    end

    if self.tab == "send" then self:RefreshSend(); return end

    local pages = math.max(1, math.ceil(shown / PER))
    self.page = math.max(1, math.min(self.page or 1, pages))
    for slot = 1, PER do
        local c = cards[slot]
        local i = (self.page - 1) * PER + slot
        if i > shown then
            c:Hide()
        else
            local h = header(i)
            c.index = i
            c.tile:SetItem(h.icon, nil, nil)
            c.dot:SetShown(not h.read)
            c.sender:SetText(h.sender)
            c.sender:SetTextColor(unpack(h.read and T.textDim or T.text))
            c.subject:SetText(h.subject)
            local dt, dcol = daysText(h.days)
            c.days:SetText(dt)
            c.days:SetTextColor(unpack(dcol))
            local extra = {}
            if h.cod > 0 then table.insert(extra, "|cfff26b66COD|r")
            elseif h.money > 0 then table.insert(extra, money(h.money)) end
            if h.items > 0 then table.insert(extra, h.items .. (h.items == 1 and " item" or " items")) end
            c.extra:SetText(table.concat(extra, "  "))
            local sel = self.selected == i
            if sel then c.ring(unpack(T.accent)); c.fill(0.13, 0.13, 0.15, 1)
            else c.ring(T.border[1], T.border[2], T.border[3], 1); c.fill(unpack(CARD)) end
            c:Show()
        end
    end
    win.pageText:SetText(pages > 1 and string.format("%d / %d", self.page, pages) or "")
    win.prev:SetShown(pages > 1); win.next:SetShown(pages > 1)
    win.prev:SetEnabled(self.page > 1); win.next:SetEnabled(self.page < pages)
    win.empty:SetShown(shown == 0)
    refreshPane()
end

local function build()
    win = CreateFrame("Frame", "MinimalUIMail", UIParent)
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
        ML.db.pos = { p, rp, x, y }
    end)
    local pos = ML.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -140) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIMail")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))
    -- Dropping an item anywhere on the window attaches it (switching to Send).
    local function drop()
        if not CursorHasItem() then return end
        if ML.tab ~= "send" then ML.tab = "send"; ML:Refresh() end
        attachCursor()
    end
    win:SetScript("OnReceiveDrag", drop)
    win:SetScript("OnMouseUp", drop)

    win.shell = ns:CreateShell(win)
    win.shell:SetIcon(LETTER)
    win.shell:SetRing({ 0.55, 0.70, 0.95 })
    win.openAll = pill(win, "Open all", function()
        if ML.taking then stopTaking() else startTaking("all") end
    end)
    win.openAll:SetPoint("BOTTOMRIGHT", win.shell.band, "BOTTOMRIGHT", -14, 14)
    win.shell:Lift(win.openAll)

    local x = 18
    for _, t in ipairs({ { "inbox", INBOX or "Inbox" }, { "send", SENDMAIL or "Send" } }) do
        local b = pill(win, t[2], function() ML.tab = t[1]; ML:Refresh() end)
        b.key = t[1]
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -TABS_Y)
        x = x + b:GetWidth() + 6
        table.insert(tabBtns, b)
    end

    win.inbox = CreateFrame("Frame", nil, win)
    win.inbox:SetAllPoints()
    for i = 1, PER do cards[i] = newCard(i) end
    win.empty = text(win.inbox, 12, false, T.textDim)
    win.empty:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(LIST_TOP + 20))
    win.empty:SetWidth(LIST_W)
    win.empty:SetText("Your mailbox is empty.")
    win.pageText = text(win.inbox, 11, true, T.textDim)
    win.pageText:SetPoint("BOTTOM", win, "BOTTOMLEFT", 18 + LIST_W / 2, 20)
    win.prev = pill(win.inbox, "Previous", function() ML.page = (ML.page or 1) - 1; ML:Refresh() end)
    win.prev:SetPoint("RIGHT", win.pageText, "LEFT", -12, 0)
    win.next = pill(win.inbox, "Next", function() ML.page = (ML.page or 1) + 1; ML:Refresh() end)
    win.next:SetPoint("LEFT", win.pageText, "RIGHT", 12, 0)
    buildPane()
    buildSend()

    win:SetScript("OnHide", function()
        if ML.taking then stopTaking() end
        local B = ns.modules.Bags
        if B and B.SetInteract then B:SetInteract(nil) end
        if not closing then call(_G.CloseMail) end
    end)
end

local function open()
    if not win then build() end
    ML.tab, ML.page, ML.selected = "inbox", 1, nil
    if not win:IsShown() then win:Show() end
    call(_G.CheckInbox)
    ML:Refresh()
end

local function close()
    if win and win:IsShown() then
        closing = true
        win:Hide()
        closing = false
    end
end

-- Blizzard's mail frame: open but invisible and unclickable.
local function ghost(f)
    if not f or f.__muiGhost then return end
    f.__muiGhost = true
    local function apply(self) self:SetAlpha(0); self:SetScale(0.001); self:EnableMouse(false) end
    f:HookScript("OnShow", apply)
    if f:IsShown() then apply(f) end
end

function ML:OnInit(db)
    local me, realm = UnitName("player"), myRealm()
    if MinimalUIDB and type(me) == "string" and not secret(me) and realm ~= "" then
        MinimalUIDB.chars = MinimalUIDB.chars or {}
        MinimalUIDB.chars[realm] = MinimalUIDB.chars[realm] or {}
        MinimalUIDB.chars[realm][me] = true
    end
    self.db = db
    ghost(_G.MailFrame)
    ghost(_G.OpenMailFrame)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_INFO_UPDATE", "MAIL_SEND_SUCCESS",
                         "MAIL_FAILED", "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "UPDATE_PENDING_MAIL" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local dirty, acc = false, 0
    ev:SetScript("OnEvent", function(_, e)
        if e == "MAIL_SHOW" then
            open()
            -- Ask for the guild roster so name completion can use it.
            call((C_GuildInfo and C_GuildInfo.GuildRoster) or _G.GuildRoster)
        elseif e == "MAIL_CLOSED" then close()
        elseif not win or not win:IsShown() then return
        elseif e == "MAIL_SEND_SUCCESS" then
            clearSend()
            win.status:SetText("|cff7fd98aSent.|r")
            dirty = true
        elseif e == "MAIL_FAILED" then
            win.status:SetText("|cfff26b66Couldn't send.|r")
            dirty = true
        else
            dirty = true
        end
    end)
    ev:SetScript("OnUpdate", function(_, dt)
        if not dirty then return end
        acc = acc + dt
        if acc < 0.1 then return end
        acc, dirty = 0, false
        ML:Refresh()
    end)
end
