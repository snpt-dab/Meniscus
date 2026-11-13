local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Merchant: Meniscus's vendor window (shared header: the vendor's 3D head,
-- name, zone; Sell junk and Repair pills in the band). Buy / Buy back tabs,
-- items as cards in a 2-column grid with price (red when you can't afford
-- it), stack and stock. Click or right-click buys one lot (as listed, e.g.
-- 200 arrows); shift-click picks a
-- quantity; ctrl/shift-click with chat open links. Drop an item from your
-- bags onto the window to sell it (right-clicking it in the bags also sells).
-- Blizzard's merchant frame stays open but invisible (closing it would end
-- the visit).

local M = ns:NewModule("Merchant", { enabled = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local W = 560
local COLS, ROWS = 2, 6
local PER = COLS * ROWS
local CARD_W, CARD_H = (W - 36 - 8) / 2, 46
local TABS_Y = (ns.SHELL_H or 92) + 12
local GRID_TOP = TABS_Y + 36
local H = GRID_TOP + ROWS * (CARD_H + 6) + 48
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local CARD = { 0.10, 0.10, 0.115, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local RED = { 0.95, 0.42, 0.40, 1 }

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

-- ── Data ──────────────────────────────────────────────────────────────────
local function merchantItem(i)
    local MF = C_MerchantFrame
    if MF and MF.GetItemInfo then
        local info = call(MF.GetItemInfo, i)
        if type(info) == "table" and info.name then
            return info.name, info.texture, info.price, info.stackCount, info.numAvailable, info.isUsable,
                info.hasExtendedCost
        end
    end
    local name, tex, price, qty, avail, _, usable, ext = call(_G.GetMerchantItemInfo, i)
    return name, tex, price, qty, avail, usable, ext
end

local function costText(i)
    local n = call(_G.GetMerchantItemCostInfo, i) or 0
    local parts = {}
    for j = 1, (num(n) and n or 0) do
        local tex, value = call(_G.GetMerchantItemCostItem, i, j)
        if tex and num(value) then table.insert(parts, value .. " |T" .. tex .. ":14:14:0:0|t") end
    end
    return table.concat(parts, "  ")
end

local function qualityOf(link)
    if not link or secret(link) then return nil end
    return call(C_Item and C_Item.GetItemQualityByID, link)
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, cards, tabBtns = nil, {}, {}
local closing = false

local function newCard(i)
    local c = CreateFrame("Button", nil, win)
    c:SetSize(CARD_W, CARD_H)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.ring = ns.RoundedRect(c, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
    c.fill = ns.RoundedRect(c, -7, 1, 9, unpack(CARD))
    local box = CreateFrame("Frame", nil, c)
    box:SetSize(36, 36)
    box:SetPoint("LEFT", 5, 0)
    c.boxRing = ns.RoundedRect(box, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    local mask = box:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2); mask:SetPoint("BOTTOMRIGHT", -2, 2)
    c.icon = box:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints(mask)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.icon:AddMaskTexture(mask)
    c.count = box:CreateFontString(nil, "OVERLAY")
    ns:SetFont(c.count, 10, "OUTLINE", true)
    c.count:SetPoint("BOTTOMRIGHT", -2, 2)
    c.name = text(c, 12)
    c.name:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, -2)
    c.name:SetPoint("RIGHT", c, "RIGHT", -8, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.price = text(c, 11, true)
    c.price:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 8, 2)
    c.stock = text(c, 10, false, T.textDim)
    c.stock:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -10, 7)
    c:SetScript("OnEnter", function(self)
        self.ring(unpack(T.accent)); self.fill(0.13, 0.13, 0.15, 1)
        ns.TipAnchor(self)
        if M.tab == "buyback" then pcall(GameTooltip.SetBuybackItem, GameTooltip, self.index)
        else pcall(GameTooltip.SetMerchantItem, GameTooltip, self.index) end
        GameTooltip:Show()
        if M.tab ~= "buyback" and _G.GetMerchantItemLink then
            pcall(ns.AddCompare, GameTooltip, call(_G.GetMerchantItemLink, self.index))
        end
        if M.tab ~= "buyback" and ns.Restock then
            local keep = ns.Restock.Get(ns.Restock.MerchantID(self.index))
            GameTooltip:AddLine(keep and ("Restock: keeping " .. keep .. " in your bags (Alt-click to change)")
                or "Alt-click: keep a set amount of this in your bags", 0.6, 0.6, 0.65)
            GameTooltip:Show()
        end
        -- The coin "buy" pointer, as the game's own vendor window shows it
        -- (its functions pick the right one: buy, or greyed when unaffordable).
        if not CursorHasItem() then
            local show = (M.tab == "buyback") and _G.ShowBuybackSellCursor or _G.ShowMerchantSellCursor
            if not (show and pcall(show, self.index)) then pcall(SetCursor, "BUY_CURSOR") end
        end
    end)
    c:SetScript("OnLeave", function(self)
        self.ring(self.rr or T.border[1], self.rg or T.border[2], self.rb or T.border[3], 1)
        self.fill(unpack(CARD))
        GameTooltip:Hide()
        if ResetCursor then ResetCursor() end
    end)
    c.SplitStack = function(self, n) if n and n > 0 then call(_G.BuyMerchantItem, self.index, n) end end
    c:SetScript("OnClick", function(self, button)
        if CursorHasItem() then call(_G.PickupMerchantItem, 0); return end -- sell what's on the cursor
        local i = self.index
        if M.tab == "buyback" then call(_G.BuybackItem, i); return end
        if IsAltKeyDown() and ns.Restock then ns.Restock.Ask(i); return end
        if IsModifiedClick() then
            local link = call(_G.GetMerchantItemLink, i)
            if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
            if IsShiftKeyDown() then
                local maxStack = call(_G.GetMerchantItemMaxStack, i) or 1
                if num(maxStack) and maxStack > 1 then
                    if StackSplitFrame and StackSplitFrame.OpenStackSplitFrame then
                        StackSplitFrame:OpenStackSplitFrame(maxStack, self, "BOTTOMLEFT", "TOPLEFT")
                    elseif OpenStackSplitFrame then
                        OpenStackSplitFrame(maxStack, self, "BOTTOMLEFT", "TOPLEFT")
                    end
                    return
                end
            end
        end
        -- No quantity: buys one lot as listed (e.g. arrows come 200 at a
        -- time). Passing 1 bought a single arrow for the lot's display.
        call(_G.BuyMerchantItem, i)
    end)
    c:SetScript("OnReceiveDrag", function() if CursorHasItem() then call(_G.PickupMerchantItem, 0) end end)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    c:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + col * (CARD_W + 8), -(GRID_TOP + row * (CARD_H + 6)))
    return c
end

function M:Refresh()
    if not win or not win:IsShown() then return end
    for _, b in ipairs(tabBtns) do b.on = (b.key == self.tab); b:Repaint() end
    local myMoney = GetMoney()
    local total = self.tab == "buyback" and (call(_G.GetNumBuybackItems) or 0) or (call(_G.GetMerchantNumItems) or 0)
    local pages = math.max(1, math.ceil(total / PER))
    self.page = math.max(1, math.min(self.page or 1, pages))
    for slot = 1, PER do
        local c = cards[slot]
        local i = (self.page - 1) * PER + slot
        if i > total then
            c:Hide()
        else
            local name, tex, price, qty, avail, usable, ext, link
            if self.tab == "buyback" then
                name, tex, price, qty, avail, usable = call(_G.GetBuybackItemInfo, i)
                link = call(_G.GetBuybackItemLink, i)
            else
                name, tex, price, qty, avail, usable, ext = merchantItem(i)
                link = call(_G.GetMerchantItemLink, i)
            end
            c.index = i
            c.icon:SetTexture(tex)
            c.icon:SetDesaturated(usable == false)
            c.icon:SetVertexColor(1, usable == false and 0.5 or 1, usable == false and 0.5 or 1)
            c.count:SetText(num(qty) and qty > 1 and qty or "")
            local q = qualityOf(link)
            local col = num(q) and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            c.name:SetText(name or "")
            if col then c.name:SetTextColor(col.r, col.g, col.b) else c.name:SetTextColor(unpack(T.text)) end
            c.rr, c.rg, c.rb = col and col.r * 0.6 or T.border[1], col and col.g * 0.6 or T.border[2],
                col and col.b * 0.6 or T.border[3]
            c.ring(c.rr, c.rg, c.rb, 1)
            c.boxRing(col and col.r or T.border[1], col and col.g or T.border[2], col and col.b or T.border[3], 1)
            local priceText = ""
            if num(price) and price > 0 then priceText = money(price, num(myMoney) and price > myMoney) end
            if ext then
                local ct = costText(i)
                priceText = (priceText ~= "" and (priceText .. "  ") or "") .. ct
            end
            c.price:SetText(priceText)
            c.stock:SetText(num(avail) and avail >= 0 and (avail .. " left") or "")
            c:Show()
        end
    end
    win.pageText:SetText(pages > 1 and string.format("%d / %d", self.page, pages) or "")
    win.prev:SetShown(pages > 1); win.next:SetShown(pages > 1)
    win.empty:SetShown(total == 0)
    win.empty:SetText(self.tab == "buyback" and "Nothing to buy back." or "Nothing for sale.")

    -- Header: vendor, zone, money; Repair and Sell junk pills.
    local sh = win.shell
    local name = UnitExists("npc") and UnitName("npc") or (MERCHANT or "Merchant")
    sh:SetTitle(name)
    local zone = GetSubZoneText and GetSubZoneText()
    if not zone or zone == "" then zone = GetZoneText and GetZoneText() end
    sh:SetSubtitle(zone or "")
    win.money:SetText(money(myMoney))
    local canRepair = call(_G.CanMerchantRepair)
    local cost, need = call(_G.GetRepairAllCost)
    if canRepair and need and num(cost) and cost > 0 then
        win.repair:SetLabel("Repair  " .. money(cost, num(myMoney) and cost > myMoney))
        win.repair:SetEnabled(num(myMoney) and cost <= myMoney)
        win.repair:Show()
    else
        win.repair:Hide()
    end
    local MF = C_MerchantFrame
    local junk = MF and MF.GetNumJunkItems and call(MF.GetNumJunkItems)
    if num(junk) and junk > 0 and MF.SellAllJunkItems then
        win.junk:SetLabel(string.format("Sell junk (%d)", junk))
        win.junk:Show()
    else
        win.junk:Hide()
    end
    win.junk:ClearAllPoints()
    if win.repair:IsShown() then win.junk:SetPoint("RIGHT", win.repair, "LEFT", -6, 0)
    else win.junk:SetPoint("BOTTOMRIGHT", sh.band, "BOTTOMRIGHT", -14, 14) end
    -- Restock: only while this vendor sells something you are short of.
    local short = ns.Restock and ns.Restock.Pending() or 0
    win.restock:SetShown(short > 0)
    if short > 0 then
        win.restock:SetLabel(string.format("Restock (%d)", short))
        win.restock:ClearAllPoints()
        local left = (win.junk:IsShown() and win.junk) or (win.repair:IsShown() and win.repair) or nil
        if left then win.restock:SetPoint("RIGHT", left, "LEFT", -6, 0)
        else win.restock:SetPoint("BOTTOMRIGHT", sh.band, "BOTTOMRIGHT", -14, 14) end
    end
end

local function build()
    win = CreateFrame("Frame", "MinimalUIMerchant", UIParent)
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
        M.db.pos = { p, rp, x, y }
    end)
    local pos = M.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -140) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIMerchant")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))
    -- Dropping an item from the bags anywhere on the window sells it.
    win:SetScript("OnReceiveDrag", function() if CursorHasItem() then call(_G.PickupMerchantItem, 0) end end)
    win:SetScript("OnMouseUp", function() if CursorHasItem() then call(_G.PickupMerchantItem, 0) end end)

    win.shell = ns:CreateShell(win)
    win.shell:SetRing({ 0.95, 0.80, 0.35 })
    win.repair = pill(win, "Repair", function() call(_G.RepairAllItems); C_Timer.After(0.2, function() M:Refresh() end) end)
    win.repair:SetPoint("BOTTOMRIGHT", win.shell.band, "BOTTOMRIGHT", -14, 14)
    win.junk = pill(win, "Sell junk", function()
        local MF = C_MerchantFrame
        if MF and MF.SellAllJunkItems then pcall(MF.SellAllJunkItems) end
    end)
    win.restock = pill(win, "Restock", function()
        if ns.Restock then ns.Restock.Run() end
        C_Timer.After(0.5, function() M:Refresh() end)
    end)
    win.shell:Lift(win.repair, win.junk, win.restock)

    local x = 18
    for _, t in ipairs({ { "buy", MERCHANT or "Buy" }, { "buyback", BUYBACK or "Buy back" } }) do
        local b = pill(win, t[2], function() M.tab = t[1]; M.page = 1; M:Refresh() end)
        b.key = t[1]
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -TABS_Y)
        x = x + b:GetWidth() + 6
        table.insert(tabBtns, b)
    end
    for i = 1, PER do cards[i] = newCard(i) end
    win.empty = text(win, 11, false, T.textDim)
    win.empty:SetPoint("TOP", win, "TOP", 0, -(GRID_TOP + 40))

    win.pageText = text(win, 11, true, T.textDim)
    win.pageText:SetPoint("BOTTOM", win, "BOTTOM", 0, 20)
    -- What you have to spend: bottom left, level with the page controls.
    local lbl = text(win, 10, false, T.textDim)
    lbl:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 20, 21)
    lbl:SetText("YOUR MONEY")
    win.money = text(win, 12, true)
    win.money:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    win.prev = pill(win, "Previous", function() M.page = (M.page or 1) - 1; M:Refresh() end)
    win.prev:SetPoint("RIGHT", win.pageText, "LEFT", -14, 0)
    win.next = pill(win, "Next", function() M.page = (M.page or 1) + 1; M:Refresh() end)
    win.next:SetPoint("LEFT", win.pageText, "RIGHT", 14, 0)
    -- Mouse wheel turns pages (down = next). Refresh clamps to the range.
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, d)
        local before = M.page or 1
        M.page = before - d
        M:Refresh()
        if M.page ~= before then PlaySound(SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN or 836) end
    end)

    win:SetScript("OnHide", function()
        win.shell:ClearModel()
        if not closing then call(_G.CloseMerchant) end
    end)
end

local function open()
    if not win then build() end
    M.tab, M.page = "buy", 1
    win.shell:SetUnit("npc")
    win.shell:SetAttitude("npc")
    if not win:IsShown() then win:Show() end
    M:Refresh()
end

local function close()
    if win and win:IsShown() then
        closing = true
        win:Hide()
        closing = false
    end
end

-- Blizzard's merchant frame: open but invisible and unclickable.
local function ghost(f)
    if not f or f.__muiGhost then return end
    f.__muiGhost = true
    f:HookScript("OnShow", function(self)
        self:SetAlpha(0)
        self:SetScale(0.001)
        self:EnableMouse(false)
    end)
end

function M:OnInit(db)
    self.db = db
    ghost(_G.MerchantFrame)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "MERCHANT_FILTER_ITEM_UPDATE",
                         "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local dirty, acc = false, 0
    ev:SetScript("OnEvent", function(_, e)
        if e == "MERCHANT_SHOW" then open()
        elseif e == "MERCHANT_CLOSED" then close()
        elseif win and win:IsShown() then dirty = true end
    end)
    ev:SetScript("OnUpdate", function(_, dt)
        if not dirty then return end
        acc = acc + dt
        if acc < 0.1 then return end
        acc, dirty = 0, false
        M:Refresh()
    end)
end
