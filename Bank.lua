local _, ns = ...
local T = ns.Theme

-- Bank: Meniscus's bank window, in the bag window's style (shared header
-- with the banker's 3D head; search and Sort in the band). Works with either
-- bank system the client reports:
--   tabs     (C_Bank character tabs) one pill per purchased tab, its slots
--            in the grid
--   classic  the bank container plus bank bags in one grid; bank bag slots
--            in the footer (drag bags in/out), "Buy bag slot" beside them
-- On Forever the "tabs" are the main bank (tab 1, 48 slots) plus one tab per
-- bank bag slot you've bought; all of them show in one grid. Buying a slot
-- is reserved for Blizzard's own UI (an addon calling C_Bank.PurchaseBankTab
-- is blocked), so the footer holds Blizzard's own buttons, lifted out of its
-- hidden bank frame: the bank bag slots and the purchase button. They keep
-- Blizzard's behavior (drop a bag in, buy the next slot). The "Blizzard
-- bank" pill reveals the whole stock window beside ours as a fallback.
-- Left-click / drag picks up, shift-click links or splits, right-click moves
-- an item into your bags. While the bank is open, right-click in your bags
-- deposits (Bags.lua). Blizzard's bank frame stays open but invisible.

local BK = ns:NewModule("Bank", { enabled = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local TILE, GAP, PAD = 34, 4, 16
local COLS = 14
local HEADER = (ns.SHELL_H or 92) + 12
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local EMPTY = { 0.09, 0.09, 0.10, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local BANK_CONTAINER = _G.BANK_CONTAINER or -1

local CC = C_Container or {}
local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not secret(v) end

local function numSlots(bag)
    local n = call(CC.GetContainerNumSlots, bag)
    return num(n) and n or 0
end

local function itemInfo(bag, slot)
    local info = call(CC.GetContainerItemInfo, bag, slot)
    return type(info) == "table" and info or nil
end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local PILL_OPTS = { h = 22, pad = 24, minW = 44 }
local function pill(parent, label, onClick)
    return ns.Pill(parent, label, onClick, PILL_OPTS)
end

-- ── Which bank system ─────────────────────────────────────────────────────
-- Purchased character tabs (each tab is a container ID), or nil.
local function bankTabs()
    local CB = C_Bank
    local bt = Enum and Enum.BankType and Enum.BankType.Character
    if not (CB and CB.FetchPurchasedBankTabData and bt) then return nil end
    local tabs = call(CB.FetchPurchasedBankTabData, bt)
    if type(tabs) ~= "table" or #tabs == 0 then return nil end
    return tabs
end

-- Containers to show right now (in order).
local function classicBags()
    local list = { BANK_CONTAINER }
    local first = (_G.NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (_G.NUM_BANKBAGSLOTS or 7) - 1 do
        if numSlots(bag) > 0 then table.insert(list, bag) end
    end
    return list
end

function BK:BankBags()
    local tabs = bankTabs()
    if tabs then
        local list = {}
        for _, t in ipairs(tabs) do if t.ID then table.insert(list, t.ID) end end
        return list
    end
    return classicBags()
end

-- First free slot in a list of containers. anyType: also use containers
-- that report a special bag type (bank tabs report one; for player bags it
-- means herb/soul bags etc., which only take certain items).
local function freeSlotIn(bags, anyType)
    for _, bag in ipairs(bags) do
        local free, family = call(CC.GetContainerNumFreeSlots, bag)
        if num(free) and free > 0 and (anyType or not num(family) or family == 0) then
            for slot = 1, numSlots(bag) do
                if not itemInfo(bag, slot) then return bag, slot end
            end
        end
    end
end
BK.FreeSlotIn = freeSlotIn

local function playerBags()
    local list = {}
    for bag = 0, (_G.NUM_BAG_SLOTS or 4) do table.insert(list, bag) end
    return list
end

-- ── Buying space ──────────────────────────────────────────────────────────
local function money(c)
    if not num(c) then return "" end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "|cffe6c25a g|r") end
    if g > 0 or s > 0 then table.insert(parts, s .. "|cffb8bcc6 s|r") end
    table.insert(parts, cp .. "|cffc98a52 c|r")
    return table.concat(parts, " ")
end

local BANK_TYPE = Enum and Enum.BankType and Enum.BankType.Character

-- Next bank tab for sale: its cost (or true when the cost is unknown), or nil.
local function nextTabCost()
    local CB = C_Bank
    if not (CB and BANK_TYPE and CB.PurchaseBankTab) then return nil end
    if CB.CanPurchaseBankTab and call(CB.CanPurchaseBankTab, BANK_TYPE) ~= true then return nil end
    local d = CB.FetchNextPurchasableBankTabData and call(CB.FetchNextPurchasableBankTabData, BANK_TYPE)
    if type(d) ~= "table" then return nil end
    return num(d.tabCost) and d.tabCost or true
end

-- Next classic bank bag slot for sale: its cost (or true), or nil.
local function nextSlotCost()
    if not (_G.PurchaseSlot and _G.GetNumBankSlots) then return nil end
    local n, full = call(GetNumBankSlots)
    if not num(n) or full or n >= (_G.NUM_BANKBAGSLOTS or 7) then return nil end
    local cost = call(_G.GetBankSlotCost, n)
    return num(cost) and cost or true
end

if StaticPopupDialogs then
    StaticPopupDialogs["MINIMALUI_BANK_BUY"] = {
        text = "%s", button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function(_, fn) if fn then fn() end end,
        timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
    }
end
local function confirmBuy(what, cost, fn)
    if num(cost) and cost > (GetMoney() or 0) then
        UIErrorsFrame:AddMessage(ERR_NOT_ENOUGH_MONEY or "You don't have enough money.", 1, 0.1, 0.1)
        return
    end
    local msg = "Buy " .. what .. (num(cost) and (" for " .. money(cost)) or "") .. "?"
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs["MINIMALUI_BANK_BUY"] then
        StaticPopup_Show("MINIMALUI_BANK_BUY", msg, nil, fn)
    else
        fn()
    end
end
local unlift, adopt -- defined with the lifted Blizzard buttons, below

-- Blizzard's bank window: hidden behind ours, or shown beside it.
local function applyGhost(f)
    if not f then return end
    if BK.showBlizz then
        f:SetAlpha(1); f:SetScale(1); f:EnableMouse(true)
        local w = _G.MinimalUIBank
        if w and w:IsShown() then
            pcall(function()
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", w, "TOPRIGHT", 10, 0)
            end)
        end
    else
        f:SetAlpha(0); f:SetScale(0.001); f:EnableMouse(false)
    end
end
function BK:ShowBlizzard(on)
    self.showBlizz = on and true or false
    -- The stock window gets its bag slots and purchase button back while
    -- it's shown; ours borrows them again when it's hidden.
    if self.showBlizz then unlift() end
    applyGhost(_G.BankFrame)
    if not self.showBlizz then adopt() end
    self:Refresh()
end
local function buyTab()
    BK:ShowBlizzard(true)
    ns:Print("Buying a bank tab has to be done in Blizzard's bank window (shown beside this one). Click \"Hide Blizzard bank\" when you're done.")
end
local function buySlot()
    confirmBuy("a bank bag slot", nextSlotCost(), function() call(_G.PurchaseSlot) end)
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, tiles, tabBtns = nil, {}, {}
local closing = false

local function moveToBags(bag, slot)
    local tb, ts = freeSlotIn(playerBags())
    if not tb then
        UIErrorsFrame:AddMessage(ERR_INV_FULL or "Inventory is full.", 1, 0.1, 0.1)
        return
    end
    call(CC.PickupContainerItem, bag, slot)
    call(CC.PickupContainerItem, tb, ts)
end

local function splitStack(self, n) call(CC.SplitContainerItem, self.bag, self.slot, n) end

local function makeTile()
    local b = CreateFrame("Button", nil, win)
    b:SetSize(TILE, TILE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.ring = ns.RoundedRect(b, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    b.fill = ns.RoundedRect(b, -7, 1, 6, unpack(EMPTY))
    local mask = b:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2); mask:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(mask)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:AddMaskTexture(mask)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(mask); hl:SetColorTexture(1, 1, 1, 0.12); hl:AddMaskTexture(mask)
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(b:GetFrameLevel() + 2)
    b.over = over
    b.count = over:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.count, 10, "OUTLINE", true)
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.SplitStack = splitStack
    b:SetScript("OnClick", function(self, button)
        local info = itemInfo(self.bag, self.slot)
        if button == "RightButton" then
            if info and not CursorHasItem() then moveToBags(self.bag, self.slot) end
            return
        end
        if IsModifiedClick() and info then
            local link = info.hyperlink
            if link and not secret(link) and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
            if IsShiftKeyDown() and num(info.stackCount) and info.stackCount > 1 and not CursorHasItem() then
                if StackSplitFrame and StackSplitFrame.OpenStackSplitFrame then
                    StackSplitFrame:OpenStackSplitFrame(info.stackCount, self, "BOTTOMRIGHT", "TOPRIGHT")
                end
                return
            end
        end
        call(CC.PickupContainerItem, self.bag, self.slot)
    end)
    b:SetScript("OnDragStart", function(self) call(CC.PickupContainerItem, self.bag, self.slot) end)
    b:SetScript("OnReceiveDrag", function(self) call(CC.PickupContainerItem, self.bag, self.slot) end)
    b:SetScript("OnEnter", function(self)
        ns.TipAnchor(self)
        if itemInfo(self.bag, self.slot) then
            if not pcall(GameTooltip.SetBagItem, GameTooltip, self.bag, self.slot) and self.bag == BANK_CONTAINER
                and BankButtonIDToInvSlotID then
                pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", BankButtonIDToInvSlotID(self.slot))
            end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function matches(info)
    local q = BK.search
    if not q or q == "" then return true end
    local link = info.hyperlink
    local name = link and not secret(link) and link:match("%[(.-)%]")
    return name and name:lower():find(q, 1, true) ~= nil
end

local function fillTile(b)
    local info = itemInfo(b.bag, b.slot)
    if info and info.iconFileID then
        b.icon:SetTexture(info.iconFileID)
        b.icon:Show()
        b.icon:SetDesaturated(info.isLocked and true or false)
        b.fill(0.06, 0.06, 0.07, 0.97)
        b.count:SetText(num(info.stackCount) and info.stackCount > 1 and info.stackCount or "")
        local q = info.quality
        local c = num(q) and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then b.ring(c.r, c.g, c.b, 1) else b.ring(T.border[1], T.border[2], T.border[3], 1) end
        local m = matches(info)
        b.icon:SetAlpha(m and 1 or 0.2)
        b.over:SetAlpha(m and 1 or 0.3)
    else
        b.icon:Hide()
        b.fill(unpack(EMPTY))
        b.count:SetText("")
        b.ring(T.border[1] * 0.8, T.border[2] * 0.8, T.border[3] * 0.8, 1)
    end
end

-- Footer: classic bank bag slots (drag bags in/out; click an empty one to buy).
local function makeBagSlot(i)
    local s = CreateFrame("Button", nil, win)
    s:SetSize(26, 26)
    s.ring = ns.RoundedRect(s, -8, 0, 6, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(s, -7, 1, 5, unpack(FILL))
    local mask = s:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2); mask:SetPoint("BOTTOMRIGHT", -2, 2)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints(mask)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.icon:AddMaskTexture(mask)
    s.plus = text(s, 14, true)
    s.plus:SetPoint("CENTER", 0, 1)
    s.plus:SetText("+")
    s.plus:Hide()
    s.bagID = (_G.NUM_BAG_SLOTS or 4) + i
    s.inv = call(CC.ContainerIDToInventoryID, s.bagID)
    s:RegisterForDrag("LeftButton")
    local function swap()
        if not s.inv then return end
        if not s.owned then
            if s.next then (s.tabMode and buyTab or buySlot)() end
            return
        end
        if CursorHasItem() then call(PutItemInBag, s.inv) else call(PickupBagFromSlot, s.inv) end
    end
    s:SetScript("OnClick", swap)
    s:SetScript("OnDragStart", function() if s.inv and s.owned then call(PickupBagFromSlot, s.inv) end end)
    s:SetScript("OnReceiveDrag", swap)
    s:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not self.owned then
            local cost = self.tabMode and nextTabCost() or nextSlotCost()
            GameTooltip:SetText(self.next and (self.tabMode and "Buy another bank tab (in Blizzard's bank window)"
                or "Buy this bank bag slot") or "Bank bag slot (not bought yet)", 1, 1, 1)
            if self.next and num(cost) then GameTooltip:AddLine(money(cost), 1, 1, 1) end
        elseif not (self.inv and GameTooltip:SetInventoryItem("player", self.inv)) then
            GameTooltip:SetText(self.tabName or BANK_BAG or "Bank bag slot", 1, 1, 1)
            GameTooltip:AddLine("Empty. Drop a bag here.", 0.7, 0.7, 0.75, true)
        end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return s
end

function BK:Refresh()
    if not win or not win:IsShown() then return end
    local tabs = bankTabs()
    local bags
    for _, b in ipairs(tabBtns) do b:Hide() end
    if tabs then
        bags = {}
        for _, t in ipairs(tabs) do if t.ID then bags[#bags + 1] = t.ID end end
    else
        bags = classicBags()
    end
    win.buyTab:Hide()
    local tabCost = nextTabCost()
    local top = HEADER

    -- Grid.
    local i = 0
    local used = 0
    local free, total = 0, 0
    for _, bag in ipairs(bags) do
        local n = numSlots(bag)
        total = total + n
        for slot = 1, n do
            used = used + 1
            local b = tiles[used] or makeTile()
            tiles[used] = b
            b.bag, b.slot = bag, slot
            local row, col = math.floor(i / COLS), i % COLS
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + col * (TILE + GAP), -(top + row * (TILE + GAP)))
            fillTile(b)
            if not itemInfo(bag, slot) then free = free + 1 end
            b:Show()
            i = i + 1
        end
    end
    for k = used + 1, #tiles do tiles[k]:Hide() end
    local rows = math.max(1, math.ceil(i / COLS))

    -- Footer: classic bank bag slots + money.
    local footer = 44
    local numBought = call(_G.GetNumBankSlots)
    numBought = num(numBought) and numBought or 0
    local classic = not tabs and _G.GetNumBankSlots ~= nil
    local slotCost = classic and nextSlotCost()
    local lastSlot
    for idx, s in ipairs(win.bagSlots) do
        -- Owned slots, plus the next one for sale (with a "+").
        local show
        if tabs then
            show = false -- Blizzard's own slot buttons are used instead
        else
            s.tabMode = false
            s.owned = idx <= numBought
            s.next = slotCost and idx == numBought + 1 or false
            show = classic and (s.owned or s.next)
        end
        if show then
            local tex = s.owned and s.inv and GetInventoryItemTexture("player", s.inv)
            s.icon:SetTexture(tex or "Interface/PaperDoll/UI-PaperDoll-Slot-Bag")
            s.icon:SetDesaturated(not tex)
            s.icon:SetAlpha(tex and 1 or (s.owned and 0.45 or 0.2))
            s.plus:SetShown(s.next)
            s:Show()
            lastSlot = s
        else
            s:Hide()
        end
    end
    if BK.PaintSlots then BK:PaintSlots() end
    win.bagLabel:SetShown(lastSlot ~= nil or (BK.adopted and BK.adopted > 0) or false)
    win.buyCost:SetText((BK.buyX and num(tabCost)) and money(tabCost) or "")
    if BK.buyX then
        win.buyCost:ClearAllPoints()
        win.buyCost:SetPoint("LEFT", win, "BOTTOMLEFT", BK.buyX, 18)
    end
    if slotCost then
        win.buySlot:SetLabel(num(slotCost) and ("Buy bag slot  ·  " .. money(slotCost)) or "Buy bag slot")
        win.buySlot:ClearAllPoints()
        if lastSlot then win.buySlot:SetPoint("LEFT", lastSlot, "RIGHT", 10, 0)
        else win.buySlot:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, 9) end
        win.buySlot:Show()
    else
        win.buySlot:Hide()
    end
    win.blizz:SetLabel(self.showBlizz and "Hide Blizzard bank" or "Blizzard bank")
    win.blizz.on = self.showBlizz; win.blizz:Repaint()
    win.money:SetText(money(GetMoney()))
    win:SetSize(PAD * 2 + COLS * TILE + (COLS - 1) * GAP, top + rows * (TILE + GAP) - GAP + 12 + footer)

    local sh = win.shell
    sh:SetTitle(UnitExists("npc") and UnitName("npc") or (BANK or "Bank"))
    -- "Banker  ·  39 of 48 slots free" (the NPC's title line when it has one).
    local role
    if UnitExists("npc") and C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
        local line = ok and type(data) == "table" and data.lines and data.lines[2]
        local t = line and line.leftText
        if type(t) == "string" and not secret(t) and t ~= "" and not t:find("^Level") then role = t end
    end
    local slots = string.format("%d of %d slots free", free, total)
    sh:SetSubtitle(role and (role .. "   ·   " .. slots) or slots)
end

local function build()
    win = CreateFrame("Frame", "MinimalUIBank", UIParent)
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
        BK.db.pos = { p, rp, x, y }
    end)
    local pos = BK.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIBank")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win)
    win.shell:SetRing({ 0.95, 0.80, 0.35 })
    local band = win.shell.band

    local sort
    local sortFn = CC.SortBankBags or _G.SortBankBags
    if sortFn then
        sort = pill(win, "Sort", function() call(sortFn) end)
        sort:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 14)
    end
    local box = CreateFrame("EditBox", nil, win)
    box:SetAutoFocus(false)
    box:SetSize(130, 22)
    if sort then box:SetPoint("RIGHT", sort, "LEFT", -8, 0)
    else box:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 14) end
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
        BK.search = t:lower()
        BK:Refresh()
    end)
    box:SetScript("OnEditFocusGained", function() hint:Hide() end)
    box:SetScript("OnEditFocusLost", function(self) hint:SetShown((self:GetText() or "") == "") end)
    win.blizz = pill(win, "Blizzard bank", function() BK:ShowBlizzard(not BK.showBlizz) end)
    win.blizz:SetPoint("RIGHT", box, "LEFT", -8, 0)
    win.shell:Lift(box, sort, win.blizz)

    local line = win:CreateTexture(nil, "BORDER")
    line:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.8)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", PAD, 36)
    line:SetPoint("BOTTOMRIGHT", -PAD, 36)
    win.bagSlots = {}
    win.bagLabel = text(win, 9, true, T.textDim)
    win.bagLabel:SetPoint("LEFT", win, "BOTTOMLEFT", PAD, 18)
    win.bagLabel:SetText("BAGS")
    for i = 1, math.max(_G.NUM_BANKBAGSLOTS or 7, 10) do
        local s = makeBagSlot(i)
        s:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD + 36 + (i - 1) * 30, 5)
        win.bagSlots[i] = s
    end
    win.buySlot = pill(win, "Buy bag slot", buySlot)
    win.buySlot:Hide()
    win.buyTab = pill(win, "+  Buy tab", buyTab)
    win.buyTab:Hide()
    win.buyCost = text(win, 11, true, T.textDim)
    win.money = text(win, 12, true)
    win.money:SetPoint("RIGHT", win, "BOTTOMRIGHT", -PAD, 18)

    win:SetScript("OnHide", function()
        win.shell:ClearModel()
        box:ClearFocus()
        BK.showBlizz = false
        unlift()
        applyGhost(_G.BankFrame)
        if not closing then
            if C_Bank and C_Bank.CloseBankFrame then call(C_Bank.CloseBankFrame) else call(_G.CloseBankFrame) end
        end
    end)
end

-- Blizzard's bank bag slots (the item-sized buttons directly on BankFrame)
-- and its purchase button, shown in our footer. They stay children of the
-- hidden bank frame but ignore its alpha / scale, so they are visible and
-- clickable while the rest of it isn't, and they run Blizzard's own code.
local FOOT_MID = 18
local lifted = {}
local unclipped = {}
local function lift(b, x, y, k)
    -- A parent that clips its children would hide a button moved outside it.
    local p = b:GetParent()
    while p and p ~= UIParent do
        if p.DoesClipChildren and p:DoesClipChildren() then
            pcall(p.SetClipsChildren, p, false)
            unclipped[#unclipped + 1] = p
        end
        p = p:GetParent()
    end
    local ok = pcall(function()
        b:SetIgnoreParentAlpha(true)
        b:SetIgnoreParentScale(true)
        b:SetScale(UIParent:GetEffectiveScale() * k)
        b:SetFrameStrata("DIALOG")
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", x / k, y / k)
    end)
    if ok then lifted[#lifted + 1] = b end
    return ok
end
-- Our look over Blizzard's bag slot buttons: their own art is faded out and
-- a cover frame (a child of the button, so it moves and scales with it)
-- draws our tile instead. The button underneath still takes the clicks.
local skins = setmetatable({}, { __mode = "k" })
local LOCK = "Interface/PetBattles/PetBattle-LockIcon"
local function ringPaint(sk)
    local a = sk.locked and 0.55 or 1
    if sk.hover then sk.ring(0.42, 0.42, 0.47, 1)
    else sk.ring(T.border[1], T.border[2], T.border[3], a) end
end
-- Fade out whatever stock art is showing on the button (again after each
-- bank change: the game re-shows parts of it, e.g. the bag's own icon).
local function hideArt(b, sk)
    for _, r in ipairs({ b:GetRegions() }) do
        if r.SetAlpha and r:GetAlpha() > 0 then sk.hid[#sk.hid + 1] = r; r:SetAlpha(0) end
    end
    local top = b:GetFrameLevel()
    for _, c in ipairs({ b:GetChildren() }) do
        if c ~= sk then
            if c:GetAlpha() > 0 then sk.hid[#sk.hid + 1] = c; c:SetAlpha(0) end
            if c:GetFrameLevel() > top then top = c:GetFrameLevel() end
        end
    end
    sk:SetFrameLevel(top + 2)
end
local function skinSlot(b)
    local sk = skins[b]
    if not sk then
        sk = CreateFrame("Frame", nil, b)
        skins[b] = sk
        sk:SetAllPoints(b)
        sk:SetFrameLevel(b:GetFrameLevel() + 3)
        local u = (b:GetWidth() or 26) / 26 -- the button is shown at 26 wide
        sk.ring = ns.RoundedRect(sk, -8, 0, 6 * u, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(sk, -7, u, 5 * u, unpack(FILL))
        local mask = sk:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("TOPLEFT", 2 * u, -2 * u); mask:SetPoint("BOTTOMRIGHT", -2 * u, 2 * u)
        sk.icon = sk:CreateTexture(nil, "ARTWORK")
        sk.icon:SetAllPoints(mask)
        sk.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        sk.icon:AddMaskTexture(mask)
        sk.lock = sk:CreateTexture(nil, "ARTWORK")
        sk.lock:SetPoint("CENTER")
        sk.lock:SetSize(13 * u, 13 * u)
        sk.lock:SetTexture(LOCK)
        sk.lock:SetDesaturated(true)
        sk.lock:SetVertexColor(1, 1, 1, 0.3)
        sk.hid = {}
        b:HookScript("OnEnter", function() sk.hover = true; if sk:IsShown() then ringPaint(sk) end end)
        b:HookScript("OnLeave", function() sk.hover = false; if sk:IsShown() then ringPaint(sk) end end)
    end
    hideArt(b, sk)
    sk:Show()
end
-- The same for Blizzard's purchase button: our pill drawn over it.
local function buyPaint(sk)
    local b = sk:GetParent()
    if not b:IsEnabled() then
        sk.paint(0.11, 0.11, 0.12, 1); sk.fs:SetTextColor(0.38, 0.38, 0.42)
    elseif sk.hover then
        sk.paint(0.21, 0.21, 0.24, 1); sk.fs:SetTextColor(T.text[1], T.text[2], T.text[3])
    else
        sk.paint(0.15, 0.15, 0.17, 1); sk.fs:SetTextColor(T.text[1], T.text[2], T.text[3])
    end
end
local function skinBuy(b)
    local sk = skins[b]
    if not sk then
        sk = CreateFrame("Frame", nil, b)
        skins[b] = sk
        sk:SetPoint("TOPLEFT", 0, 1); sk:SetPoint("BOTTOMRIGHT", 0, -1)
        local h = (b:GetHeight() or 20) + 2
        sk.paint = ns.RoundedRect(sk, -6, 0, h / 2, 0.15, 0.15, 0.17, 1)
        sk.fs = sk:CreateFontString(nil, "OVERLAY")
        ns:SetFont(sk.fs, 11, "", true)
        sk.fs:SetPoint("CENTER")
        sk.fs:SetText("Purchase")
        sk.hid = {}
        b:HookScript("OnEnter", function() sk.hover = true; if sk:IsShown() then buyPaint(sk) end end)
        b:HookScript("OnLeave", function() sk.hover = false; if sk:IsShown() then buyPaint(sk) end end)
    end
    hideArt(b, sk)
    sk:Show()
    buyPaint(sk)
    BK.buySkin, BK.buyBtn = sk, b
end
local function unskin()
    BK.buySkin, BK.buyBtn = nil, nil
    for b, sk in pairs(skins) do
        for i = #sk.hid, 1, -1 do pcall(sk.hid[i].SetAlpha, sk.hid[i], 1); sk.hid[i] = nil end
        sk:Hide()
    end
    BK.slots = nil
end
-- Slot i is the bank's tab i + 1 (tab 1 is the main bank): bought slots show
-- the bag that's in them (or an empty tile), the rest a dim lock.
function BK:PaintSlots()
    if self.buySkin then
        pcall(hideArt, self.buyBtn, self.buySkin)
        buyPaint(self.buySkin)
    end
    local slots = self.slots
    if not slots then return end
    local tabs = bankTabs()
    for i, b in ipairs(slots) do
        local sk = skins[b]
        if sk then
            pcall(hideArt, b, sk)
            local t = tabs and tabs[i + 1]
            local inv = t and t.ID and call(CC.ContainerIDToInventoryID, t.ID)
            local tex = inv and GetInventoryItemTexture("player", inv)
            sk.locked = not t
            sk.icon:SetTexture(tex or nil)
            sk.icon:SetShown(tex and true or false)
            sk.lock:SetShown(sk.locked)
            ringPaint(sk)
        end
    end
end

function unlift()
    unskin()
    for i = #lifted, 1, -1 do
        local b = lifted[i]
        pcall(function() b:SetIgnoreParentAlpha(false); b:SetIgnoreParentScale(false); b:SetScale(1) end)
        lifted[i] = nil
    end
    for i = #unclipped, 1, -1 do
        pcall(unclipped[i].SetClipsChildren, unclipped[i], true)
        unclipped[i] = nil
    end
    BK.adopted, BK.buyX = 0, nil
    local bf = _G.BankFrame
    if bf and BK.bfStrata then
        pcall(bf.SetFrameStrata, bf, BK.bfStrata)
        if bf.SetFlattensRenderLayers then pcall(bf.SetFlattensRenderLayers, bf, true) end
        BK.bfStrata = nil
    end
end
local slotPos = setmetatable({}, { __mode = "k" })
local function bySlotPos(a, b) return slotPos[a] < slotPos[b] end
function adopt()
    if InCombatLockdown() or not win or not win:IsShown() then return end
    unlift()
    local bf = _G.BankFrame
    if not bf or not bankTabs() or BK.showBlizz then return end
    -- Blizzard's frame flattens its children into its own draw order, so a
    -- lifted button's strata is ignored and it drew underneath our window
    -- (right place, fully opaque, just behind). Put the whole invisible
    -- frame above ours while its buttons are on loan.
    if not BK.bfStrata then BK.bfStrata = bf:GetFrameStrata() end
    pcall(bf.SetFrameStrata, bf, "DIALOG")
    if bf.SetFlattensRenderLayers then pcall(bf.SetFlattensRenderLayers, bf, false) end
    -- Everything in the footer sits on one center line (FOOT_MID above the
    -- window's bottom edge). The frame lists its slot buttons last-to-first.
    local slots = {}
    for _, k in ipairs({ bf:GetChildren() }) do
        local w = k.GetWidth and k:GetWidth() or 0
        if k:GetObjectType() == "Button" and w >= 32 and w <= 44 then
            table.insert(slots, 1, k)
            -- Where Blizzard put it the first time we saw it (before any
            -- lift): that reading order is the real slot order.
            if slotPos[k] == nil then
                local l, t = k:GetLeft(), k:GetTop()
                slotPos[k] = (l and t) and (l - math.floor(t / 8 + 0.5) * 100000) or false
            end
        end
    end
    local sortable = #slots > 1
    for _, k in ipairs(slots) do if not slotPos[k] then sortable = false end end
    if sortable then table.sort(slots, bySlotPos) end
    local x, n = PAD + math.ceil(win.bagLabel:GetStringWidth() or 24) + 8, 0
    local shown = {}
    for _, k in ipairs(slots) do
        if lift(k, x, FOOT_MID - 13, 26 / k:GetWidth()) then
            n = n + 1; x = x + 30
            shown[n] = k
            pcall(skinSlot, k)
        end
    end
    BK.slots = shown
    BK.adopted = n
    local bp = bf.BankPanel or _G.BankPanel
    local buy = bp and bp.PurchaseButton
    if buy and buy:IsShown() then
        local k = 1 -- full size: with our cover it is a 22-high pill like the rest
        local bh = (buy:GetHeight() or 21) * k
        if lift(buy, x + 4, FOOT_MID - bh / 2, k) then
            BK.buyX = x + 4 + (buy:GetWidth() or 120) * k + 8
            pcall(skinBuy, buy)
        end
    end
    BK:Refresh()
    return true
end

local function open()
    if not win then build() end
    win.shell:SetUnit("npc")
    win.shell:SetAttitude("npc")
    if not win:IsShown() then win:Show() end
    BK:Refresh()
    -- After Blizzard's frame has laid itself out.
    C_Timer.After(0, adopt)
    C_Timer.After(0.5, adopt)
end

local function close()
    if win and win:IsShown() then
        closing = true
        win:Hide()
        closing = false
    end
end

local function ghost(f)
    if not f or f.__muiGhost then return end
    f.__muiGhost = true
    f:HookScript("OnShow", applyGhost)
    if f:IsShown() then applyGhost(f) end
end

function BK:OnInit(db)
    self.db = db
    if MinimalUIDB then MinimalUIDB.banklift, MinimalUIDB.bankprobe, MinimalUIDB.mailprobe = nil, nil, nil end -- old diagnostics
    ghost(_G.BankFrame)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE",
                         "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
                         "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "PLAYER_MONEY", "BAG_CONTAINER_UPDATE",
                         "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local dirty, acc = false, 0
    ev:SetScript("OnEvent", function(_, e)
        if e == "BANKFRAME_OPENED" then BK.open = true; open(); if ns.modules.Bags.SetInteract then ns.modules.Bags:SetInteract("bank") end
        elseif e == "BANKFRAME_CLOSED" then
            BK.open = false
            close()
            if ns.modules.Bags.SetInteract then ns.modules.Bags:SetInteract(nil) end
        elseif win and win:IsShown() then dirty = true end
    end)
    -- Blizzard puts its buttons back where they were whenever the bank
    -- changes (a slot bought, a bag placed): take them again after every
    -- change, and check twice a second that the first one is still ours.
    local watch = 0
    ev:SetScript("OnUpdate", function(_, dt)
        if win and win:IsShown() and lifted[1] then
            watch = watch + dt
            if watch > 0.5 then
                watch = 0
                for i = 1, #lifted do
                    local _, rel = lifted[i]:GetPoint(1)
                    if rel ~= win then dirty, BK.relift = true, true; break end
                end
            end
        end
        if not dirty then return end
        acc = acc + dt
        if acc < 0.08 then return end
        acc, dirty = 0, false
        -- Take the buttons again only when one was moved back (or none are
        -- held yet); otherwise a plain refresh avoids a flicker.
        local need = BK.relift or not lifted[1]
        if not need then
            for i = 1, #lifted do
                local _, rel = lifted[i]:GetPoint(1)
                if rel ~= win then need = true; break end
            end
        end
        BK.relift = nil
        if not (need and adopt()) then BK:Refresh() end
    end)
end
