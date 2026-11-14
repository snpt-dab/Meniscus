local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Extras: small helpers that surface what the game already knows.
--   notices    a row of round marks above the console's left wing that only
--              appear when there is something to say: gear wearing out, mail
--              waiting, a whisper you haven't answered
--   owned      "you own" counts on item tooltips: bags, bank, other characters
--   restock    per-item amounts to keep in your bags; one pill at a vendor
--              buys up to them (Alt-click a vendor item to set its amount)
--   pet food   hunters: how much food the pet will eat is in your bags, on a
--              button above the pet's pill that feeds the pet when clicked
-- Each part has its own switch in /men (Bags page).

local EX = ns:NewModule("Extras", { enabled = true, durability = true, owned = true, petFood = true })
local MEDIA = "Interface/AddOns/Meniscus/Media/"
local call = ns.Call
local CC = C_Container or {}

local function secret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not secret(v) end
local function itemCount(id, bank)
    local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    local n = f and call(f, id, bank or false)
    return num(n) and n or 0
end
local function itemName(id)
    local f = (C_Item and C_Item.GetItemNameByID) or nil
    local n = f and call(f, id)
    if type(n) == "string" and not secret(n) and n ~= "" then return n end
    return "item " .. tostring(id)
end

-- ── Notices ───────────────────────────────────────────────────────────────
-- Round marks in a row, left to right in the order they were made; a mark
-- takes no room while it has nothing to say.
local strip, chips = nil, {}

local function placeStrip()
    if not strip then return end
    local B = ns.modules.Bars
    local plate = B and B.plate
    local x, y
    if plate and plate:IsShown() then
        local well = plate.chatWell
        x = (well and well:IsShown() and well:GetRight()) or plate:GetLeft()
        y = plate:GetTop()
    end
    strip:ClearAllPoints()
    if num(x) and num(y) then
        strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 6, y + 6)
    else
        strip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 240)
    end
end

local function layoutChips()
    local x = 0
    for _, c in ipairs(chips) do
        if c.on then
            c:ClearAllPoints()
            c:SetPoint("LEFT", strip, "LEFT", x, 0)
            c:Show()
            x = x + 26
        else
            c:Hide()
        end
    end
    strip:SetWidth(math.max(x, 1))
end

local function ensureStrip()
    if strip then return end
    strip = CreateFrame("Frame", "MeniscusNotices", UIParent)
    strip:SetSize(1, 22)
    strip:SetFrameStrata("LOW")
    strip:SetFrameLevel(20)
    placeStrip()
    -- The console is laid out after login, and again when its layout changes.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:SetScript("OnEvent", function()
        C_Timer.After(1, placeStrip)
        C_Timer.After(4, placeStrip)
    end)
end

-- A mark: chip:Set(on, r, g, b, urgent). chip.tip(tooltip) fills its tooltip.
function EX:Chip(icon)
    ensureStrip()
    local c = CreateFrame("Button", nil, strip)
    c:SetSize(22, 22)
    c.ring = ns.RoundedRect(c, -8, 0, 11, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(c, -7, 1, 10, 0.06, 0.06, 0.07, 0.97)
    local holder = CreateFrame("Frame", nil, c)
    holder:SetAllPoints()
    c.icon = holder:CreateTexture(nil, "ARTWORK")
    c.icon:SetTexture(MEDIA .. icon)
    c.icon:SetSize(14, 14)
    c.icon:SetPoint("CENTER")
    local ag = holder:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.3); a:SetDuration(0.7); a:SetSmoothing("IN_OUT")
    c.on = false
    function c:Set(on, r, g, b, urgent)
        on = on and true or false
        if on then
            self.icon:SetVertexColor(r, g, b, 1)
            self.ring(r * 0.75, g * 0.75, b * 0.75, 1)
            if urgent then if not ag:IsPlaying() then ag:Play() end else ag:Stop(); holder:SetAlpha(1) end
        else
            ag:Stop()
        end
        if on ~= self.on then
            self.on = on
            layoutChips()
        end
    end
    c:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
        self.tip(GameTooltip)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnClick", function(self) if self.click then self.click() end end)
    c:Hide()
    chips[#chips + 1] = c
    return c
end

-- ── Durability ────────────────────────────────────────────────────────────
-- A wrench once any piece is at 30% or less: amber, then red and pulsing at
-- 10% or when something is broken. The tooltip lists the worn pieces.
local WORN, BAD = 0.30, 0.10
local function buildDurability()
    local chip = EX:Chip("micro_repair.tga")
    local function lowest()
        local low
        for slot = 1, 18 do
            local cur, max = call(GetInventoryItemDurability, slot)
            if num(cur) and num(max) and max > 0 then
                local p = cur / max
                if not low or p < low then low = p end
            end
        end
        return low
    end
    local function refresh()
        local low = lowest()
        if low and low <= BAD then chip:Set(true, 0.95, 0.38, 0.36, true)
        elseif low and low <= WORN then chip:Set(true, 0.95, 0.76, 0.32, false)
        else chip:Set(false) end
    end
    chip.tip = function(tip)
        tip:AddLine("Your gear needs repair", 1, 1, 1)
        for slot = 1, 18 do
            local cur, max = call(GetInventoryItemDurability, slot)
            if num(cur) and num(max) and max > 0 and cur / max <= 0.5 then
                local link = GetInventoryItemLink("player", slot)
                local name = type(link) == "string" and link:match("%[(.-)%]") or ("slot " .. slot)
                local p = cur / max
                local r, g, b = 0.95, 0.76, 0.32
                if p <= BAD then r, g, b = 0.95, 0.38, 0.36 end
                tip:AddDoubleLine(name, cur == 0 and "broken" or string.format("%d%%", p * 100 + 0.5), 0.86, 0.86, 0.89, r, g, b)
            end
        end
        tip:AddLine("Any vendor with an anvil can repair it.", 0.6, 0.6, 0.65)
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "UPDATE_INVENTORY_DURABILITY", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
                         "PLAYER_UNGHOST", "PLAYER_ALIVE", "MERCHANT_CLOSED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    local queued = false
    f:SetScript("OnEvent", function()
        if queued then return end
        queued = true
        C_Timer.After(0.5, function() queued = false; pcall(refresh) end)
    end)
end

-- ── What you own ──────────────────────────────────────────────────────────
-- Each character's bag and bank contents are remembered (the bank whenever
-- it is opened), so a tooltip can say what the others hold.
local function invRecord()
    local db = MinimalUIDB
    if not db then return nil end
    db.inv = db.inv or {}
    local key = ns:CharKey()
    local rec = db.inv[key]
    if not rec then
        rec = { bags = {}, bank = {} }
        db.inv[key] = rec
    end
    return rec
end

local function scanBag(t, bag)
    local n = call(CC.GetContainerNumSlots or _G.GetContainerNumSlots, bag)
    if not num(n) then return end
    for slot = 1, n do
        local id, count
        if CC.GetContainerItemInfo then
            local info = call(CC.GetContainerItemInfo, bag, slot)
            if type(info) == "table" then id, count = info.itemID, info.stackCount end
        else
            local _, c, _, _, _, _, _, _, _, i = call(_G.GetContainerItemInfo, bag, slot)
            id, count = i, c
        end
        if num(id) then t[id] = (t[id] or 0) + (num(count) and count or 1) end
    end
end

local function scanBags()
    local rec = invRecord()
    if not rec then return end
    wipe(rec.bags)
    for bag = 0, (_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or _G.NUM_BAG_SLOTS or 4) do scanBag(rec.bags, bag) end
end

local function scanBank()
    local rec = invRecord()
    if not rec then return end
    wipe(rec.bank)
    scanBag(rec.bank, _G.BANK_CONTAINER or -1)
    local first = (_G.NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (_G.NUM_BANKBAGSLOTS or 7) - 1 do scanBag(rec.bank, bag) end
    -- Bank tabs, on clients that have them.
    local CB, bt = C_Bank, Enum and Enum.BankType and Enum.BankType.Character
    if CB and CB.FetchPurchasedBankTabData and bt then
        local tabs = call(CB.FetchPurchasedBankTabData, bt)
        if type(tabs) == "table" then
            for _, tab in ipairs(tabs) do
                if type(tab) == "table" and num(tab.ID) then scanBag(rec.bank, tab.ID) end
            end
        end
    end
end

local madeLines -- defined further down ("Used in")
local function ownedLines(tip, id)
    local db = MinimalUIDB
    if not (db and db.inv) then return end
    local bags = itemCount(id)
    local bank = math.max(itemCount(id, true) - bags, 0)
    local spaced = false
    local function line(text)
        if not spaced then tip:AddLine(" "); spaced = true end
        tip:AddLine(text, 0.6, 0.6, 0.65)
    end
    if bags + bank >= 2 or bank > 0 then
        line("You have " .. bags .. " in bags" .. (bank > 0 and (", " .. bank .. " in the bank") or ""))
    end
    local me, shown = ns:CharKey(), 0
    for key, rec in pairs(db.inv) do
        if key ~= me and type(rec) == "table" and shown < 4 then
            local n = ((rec.bags and rec.bags[id]) or 0) + ((rec.bank and rec.bank[id]) or 0)
            if n > 0 then
                line((key:match("^(.-)%-") or key) .. " has " .. n)
                shown = shown + 1
            end
        end
    end
end

local function buildOwned()
    local bankOpen, dirty = false, false
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
                         "PLAYERBANKSLOTS_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, e)
        if e == "BANKFRAME_OPENED" then bankOpen = true
        elseif e == "BANKFRAME_CLOSED" then
            -- (One last look while its contents can still be read.)
            pcall(scanBank)
            bankOpen = false
            return
        end
        if dirty then return end
        dirty = true
        C_Timer.After(2, function()
            dirty = false
            ns.Timed("Extras owned scan", function()
                pcall(scanBags)
                if bankOpen then pcall(scanBank) end
            end)
        end)
    end)
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
            if tip ~= GameTooltip and tip ~= _G.ItemRefTooltip then return end
            local id = type(data) == "table" and data.id
            -- (Where the tooltip's data carries no plain id, take it from
            -- the item's link.)
            if not num(id) and tip.GetItem then
                local ok, _, link = pcall(tip.GetItem, tip)
                if ok and type(link) == "string" and not secret(link) then id = tonumber(link:match("item:(%d+)")) end
            end
            local diag = MinimalUIDB and { at = date("%H:%M:%S"), id = secret(id) and "secret" or tostring(id) }
            if num(id) then
                local ok1, e1 = pcall(ownedLines, tip, id)
                local ok2, e2 = true, nil
                if EX.db and EX.db.canMake ~= false then ok2, e2 = pcall(madeLines, tip, id) end
                if diag then diag.owned, diag.made = ok1 and "ok" or tostring(e1), ok2 and "ok" or tostring(e2) end
            end
            if diag then MinimalUIDB.tipdiag = diag end
        end)
    end
end

-- ── Restock ───────────────────────────────────────────────────────────────
-- Amounts to keep in your bags, per character: MinimalUIDB.restock[char][id].
local R = {}
ns.Restock = R

local function restockTable(create)
    local db = MinimalUIDB
    if not db then return nil end
    db.restock = db.restock or {}
    local key = ns:CharKey()
    if create and not db.restock[key] then db.restock[key] = {} end
    return db.restock[key]
end

local function merchantID(i)
    local id = _G.GetMerchantItemID and call(_G.GetMerchantItemID, i)
    if num(id) then return id end
    local link = _G.GetMerchantItemLink and call(_G.GetMerchantItemLink, i)
    if type(link) == "string" and not secret(link) then return tonumber(link:match("item:(%d+)")) end
end
R.MerchantID = merchantID

local function merchantInfo(i)
    local MF = C_MerchantFrame
    if MF and MF.GetItemInfo then
        local info = call(MF.GetItemInfo, i)
        if type(info) == "table" and info.name then return info.name, info.price, info.stackCount end
    end
    local name, _, price, qty = call(_G.GetMerchantItemInfo, i)
    return name, price, qty
end

function R.Get(id)
    local t = restockTable()
    return t and id and t[id] or nil
end

function R.Set(id, n)
    local t = restockTable(true)
    if not (t and id) then return end
    t[id] = (num(n) and n > 0) and math.floor(n) or nil
end

-- How many of this vendor's items are below their amount.
function R.Pending()
    local t = restockTable()
    if not t or next(t) == nil then return 0 end
    local n = 0
    for i = 1, (call(_G.GetMerchantNumItems) or 0) do
        local id = merchantID(i)
        if id and t[id] and itemCount(id) < t[id] then n = n + 1 end
    end
    return n
end

function R.Run()
    local t = restockTable()
    if not t then return end
    local money = call(GetMoney)
    money = num(money) and money or 0
    local done, short = {}, false
    for i = 1, (call(_G.GetMerchantNumItems) or 0) do
        local id = merchantID(i)
        local target = id and t[id]
        local need = target and (target - itemCount(id)) or 0
        if need > 0 then
            local name, price, lot = merchantInfo(i)
            price = num(price) and price or 0
            lot = (num(lot) and lot > 0) and lot or 1
            local got = 0
            if lot > 1 then
                -- Sold in lots (arrows, 200 at a time): whole lots until the
                -- amount is reached.
                for _ = 1, math.min(math.ceil(need / lot), 40) do
                    if price > money then short = true break end
                    call(_G.BuyMerchantItem, i)
                    money, got = money - price, got + lot
                end
            else
                local maxStack = call(_G.GetMerchantItemMaxStack, i)
                maxStack = (num(maxStack) and maxStack > 0) and maxStack or 1
                local left, guard = need, 0
                while left > 0 and guard < 40 do
                    guard = guard + 1
                    local q = math.min(left, maxStack)
                    if price * q > money then q = price > 0 and math.floor(money / price) or 0 end
                    if q <= 0 then short = true break end
                    call(_G.BuyMerchantItem, i, q)
                    money, got, left = money - price * q, got + q, left - q
                end
            end
            if got > 0 then done[#done + 1] = got .. " x " .. tostring(name or itemName(id)) end
        end
    end
    if #done > 0 then ns:Print("Restocked: " .. table.concat(done, ", ") .. ".") end
    if short then ns:Print("|cfff26b66Not enough money to restock everything.|r") end
    if #done == 0 and not short then ns:Print("Nothing to restock here.") end
end

if StaticPopupDialogs then
    local function boxOf(self) return self.EditBox or self.editBox or (self.GetEditBox and self:GetEditBox()) end
    local function accept(self, data)
        local eb = boxOf(self)
        local n = eb and tonumber(eb:GetText())
        if not (data and data.id and n) then return end
        R.Set(data.id, n)
        if n > 0 then ns:Print("Restock: keeping " .. math.floor(n) .. " x " .. tostring(data.name) .. " in your bags.")
        else ns:Print("Restock: no longer restocking " .. tostring(data.name) .. ".") end
        local M = ns.modules.Merchant
        if M and M.Refresh then pcall(M.Refresh, M) end
    end
    StaticPopupDialogs["MENISCUS_RESTOCK"] = {
        text = "Keep how many %s in your bags?\n(0 stops restocking it)",
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        hasEditBox = true, editBoxWidth = 80, maxLetters = 5,
        OnShow = function(self, data)
            local eb = boxOf(self)
            if not eb then return end
            if eb.SetNumeric then eb:SetNumeric(true) end
            local cur = data and R.Get(data.id)
            eb:SetText(cur and tostring(cur) or "")
            eb:SetFocus(); eb:HighlightText()
        end,
        OnAccept = accept,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            accept(parent, parent.data)
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

-- Ask for the amount to keep of the vendor's i-th item.
function R.Ask(i)
    local id = merchantID(i)
    if not id or not StaticPopup_Show then return end
    local name = merchantInfo(i)
    StaticPopup_Show("MENISCUS_RESTOCK", tostring(name or itemName(id)), nil, { id = id, name = name or itemName(id) })
end

-- ── Pet food ──────────────────────────────────────────────────────────────
-- Forever has no call for what a pet eats, so it is worked out two ways: a
-- starting list (the usual diets per family, and the common vendor foods of
-- each kind), and what actually happens when you feed the pet: food it took
-- is remembered as good, food it refused as bad, per family
-- (MinimalUIDB.petFood[family][itemID] = true / false / the pet's level when
-- the food was too low for it).
local DIET = {
    Bat = "FrFu", Bear = "BrChFiFrFuMe", Boar = "BrChFiFrFuMe", ["Carrion Bird"] = "FiMe", Cat = "FiMe",
    Crab = "BrFiFrFu", Crocolisk = "FiMe", Gorilla = "FrFu", Hyena = "FrMe", Owl = "Me", Raptor = "Me",
    Scorpid = "Me", Spider = "Me", Tallstrider = "ChFrFu", Turtle = "FiFrFu", ["Wind Serpent"] = "BrChFi",
    Wolf = "Me",
}
local SEED = {
    Me = { 117, 2287, 3770, 3771, 4599, 8952 },   -- jerky .. roasted quail
    Br = { 4540, 4541, 4542, 4544, 4601, 8950 },  -- bread
    Fi = { 787, 4592, 4593, 4594, 21552, 8957 },  -- fish
    Ch = { 2070, 414, 422, 1707, 3927, 8932 },    -- cheese
    Fr = { 4536, 4537, 4538, 4539, 4602, 8953 },  -- fruit
    Fu = { 4604, 4605, 4606, 4607, 4608, 8948 },  -- fungus
}
local SEED_KIND = {}
for kind, list in pairs(SEED) do for _, id in ipairs(list) do SEED_KIND[id] = kind end end
local FEED_PET = 6991

local function petFamily()
    local fam = UnitExists("pet") and UnitCreatureFamily and UnitCreatureFamily("pet")
    if type(fam) == "string" and not secret(fam) then return fam end
end
local function petLevel()
    local l = UnitLevel("pet")
    return num(l) and l or nil
end
local function learned(fam, create)
    local db = MinimalUIDB
    if not (db and fam) then return nil end
    db.petFood = db.petFood or {}
    if create and not db.petFood[fam] then db.petFood[fam] = {} end
    return db.petFood[fam]
end
-- true: the pet eats it. false: it doesn't. nil: not known yet.
local function verdict(fam, id)
    local t = learned(fam)
    local v = t and t[id]
    if v == true or v == false then return v end
    if type(v) == "number" then
        local l = petLevel()
        if not l or l >= v then return false end
    end
    local diet, kind = DIET[fam], SEED_KIND[id]
    if diet and kind then return diet:find(kind, 1, true) ~= nil end
    return nil
end
local function isFood(id)
    local f = C_Item and C_Item.GetItemInfoInstant
    if not f then return false end
    local ok, _, _, _, _, _, classID, subID = pcall(f, id)
    return ok and classID == 0 and subID == 5
end

-- Bags: feedings of good food, the food to use (lowest level first, so the
-- good stuff is kept), and how many foods are still unknown.
local foodSeen = {}
local function surveyFood()
    local fam = petFamily()
    wipe(foodSeen)
    local good, unknown, best, bestLevel = 0, 0, nil, nil
    if not fam then return 0, 0, nil end
    for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
        local n = call(CC.GetContainerNumSlots or _G.GetContainerNumSlots, bag)
        for slot = 1, (num(n) and n or 0) do
            local info = CC.GetContainerItemInfo and call(CC.GetContainerItemInfo, bag, slot)
            local id = type(info) == "table" and info.itemID
            if num(id) and isFood(id) then
                local v = verdict(fam, id)
                local count = num(info.stackCount) and info.stackCount or 1
                if v == true then
                    good = good + count
                    local _, _, _, _, minLevel = call((C_Item and C_Item.GetItemInfo) or _G.GetItemInfo, id)
                    minLevel = num(minLevel) and minLevel or 0
                    if not bestLevel or minLevel < bestLevel then best, bestLevel = id, minLevel end
                elseif v == nil and not foodSeen[id] then
                    foodSeen[id] = true
                    unknown = unknown + 1
                end
            end
        end
    end
    return good, unknown, best
end

local function buildPetFood()
    local _, class = UnitClass("player")
    if class ~= "HUNTER" then return end
    local btn = CreateFrame("Button", "MeniscusFeedPet", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(46, 16)
    btn:SetFrameStrata("LOW")
    btn:SetFrameLevel(30)
    btn:RegisterForClicks("AnyDown", "AnyUp")
    btn:SetAttribute("type", "macro")
    local ring = ns.RoundedRect(btn, -8, 0, 8, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(btn, -7, 1, 7, 0.06, 0.06, 0.07, 0.97)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "micro_food.tga")
    icon:SetSize(10, 10)
    icon:SetPoint("LEFT", 6, 0)
    local text = ns:CreateText(btn, 10, T.textDim)
    text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    text:SetPoint("RIGHT", -6, 0)
    text:SetJustifyH("CENTER")
    btn:Hide()

    local good, unknown, best = 0, 0, nil
    local placed, wantMacro = false, nil
    local function feedName()
        local f = C_Spell and C_Spell.GetSpellName
        local n = f and call(f, FEED_PET)
        return (type(n) == "string" and n ~= "") and n or "Feed Pet"
    end
    local function show()
        local r, g, b = T.textDim[1], T.textDim[2], T.textDim[3]
        if good == 0 then r, g, b = 0.95, 0.38, 0.36 elseif good < 5 then r, g, b = 0.95, 0.76, 0.32 end
        text:SetText((good == 0 and unknown > 0) and "?" or good)
        text:SetTextColor(r, g, b)
        icon:SetVertexColor(r, g, b, 1)
    end
    -- Attributes and placement only out of combat (it is a secure button).
    local function apply()
        if InCombatLockdown() then return end
        local B = ns.modules.Bars
        local w = B and B.petWell
        if w and w.on and w.pill then
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMRIGHT", w.pill, "TOPRIGHT", -6, 4)
            if not placed then
                placed = true
                RegisterStateDriver(btn, "visibility", "[pet,nodead] show; hide")
            end
        elseif placed then
            placed = false
            UnregisterStateDriver(btn, "visibility")
            btn:Hide()
        end
        local macro = best and ("/cast " .. feedName() .. "\n/use item:" .. best) or ""
        if macro ~= wantMacro then
            wantMacro = macro
            btn:SetAttribute("macrotext", macro)
        end
    end
    local function refresh()
        good, unknown, best = surveyFood()
        show()
        apply()
    end
    btn:SetScript("PreClick", function() if best then ns.lastFed, ns.lastFedAt = best, GetTime() end end)
    btn:SetScript("OnEnter", function(self)
        ring(unpack(T.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
        GameTooltip:AddLine("Feed your pet", 1, 1, 1)
        if best then
            GameTooltip:AddLine("Click: feeds it " .. itemName(best) .. ".", 0.86, 0.86, 0.89)
            GameTooltip:AddLine(good .. " feedings of food it eats in your bags.", 0.6, 0.6, 0.65)
        else
            GameTooltip:AddLine("No food it is known to eat in your bags.", 0.95, 0.38, 0.36)
        end
        if unknown > 0 then
            GameTooltip:AddLine(unknown .. " food(s) not tried on this kind of pet yet: use Feed Pet and click"
                .. " one, and it will be remembered either way.", 0.6, 0.6, 0.65, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        ring(T.border[1], T.border[2], T.border[3], 1)
        GameTooltip:Hide()
    end)

    local f = CreateFrame("Frame")
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE" }) do
        pcall(f.RegisterEvent, f, e)
    end
    pcall(f.RegisterUnitEvent, f, "UNIT_PET", "player")
    pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player")
    local queued = false
    local function soon(delay)
        if queued then return end
        queued = true
        C_Timer.After(delay or 0.5, function() queued = false; pcall(refresh) end)
    end
    -- What became of the food just handed to Feed Pet.
    local function learn(v)
        local id, at = ns.lastFed, ns.lastFedAt
        if not (id and at and GetTime() - at < 3) then return end
        ns.lastFed = nil
        local t = learned(petFamily(), true)
        if not t then return end
        if v == "low" then t[id] = petLevel() or false else t[id] = v end
        soon(0.2)
    end
    f:SetScript("OnEvent", function(_, e, a, b, c)
        if e == "UI_ERROR_MESSAGE" then
            if type(b) ~= "string" or secret(b) then return end
            if b == _G.SPELL_FAILED_WRONG_PET_FOOD then learn(false)
            elseif b == _G.SPELL_FAILED_FOOD_LOWLEVEL then learn("low") end
        elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
            if num(c) and c == FEED_PET then learn(true) end
        else
            soon(e == "PLAYER_ENTERING_WORLD" and 3 or 0.5)
        end
    end)
end

-- ── Mail waiting ──────────────────────────────────────────────────────────
local function buildMail()
    local chip = EX:Chip("micro_mail.tga")
    local function refresh()
        local has = _G.HasNewMail and call(_G.HasNewMail)
        chip:Set(has == true, 0.95, 0.80, 0.35, false)
    end
    chip.tip = function(tip)
        tip:AddLine("You have mail", 1, 1, 1)
        if _G.GetLatestThreeSenders then
            local a, b, c = call(_G.GetLatestThreeSenders)
            for _, who in ipairs({ a, b, c }) do
                if type(who) == "string" and not secret(who) then tip:AddLine("From " .. who, 0.86, 0.86, 0.89) end
            end
        end
        tip:AddLine("Collect it at any mailbox.", 0.6, 0.6, 0.65)
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "UPDATE_PENDING_MAIL", "PLAYER_ENTERING_WORLD", "MAIL_CLOSED", "MAIL_INBOX_UPDATE" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function() C_Timer.After(1, function() pcall(refresh) end) end)
end

-- ── Whispers you haven't answered ─────────────────────────────────────────
-- Lights up when someone whispers you; goes out when you whisper back (to
-- anyone) or click it, which also opens a reply.
local function buildWhisper()
    local chip = EX:Chip("micro_chat.tga")
    local from, count = {}, 0
    local function refresh() chip:Set(count > 0, T.accent[1], T.accent[2], T.accent[3], false) end
    local function clear() count = 0; wipe(from); refresh() end
    chip.tip = function(tip)
        tip:AddLine(count == 1 and "A whisper you haven't answered" or (count .. " whispers you haven't answered"), 1, 1, 1)
        for i = math.max(1, #from - 2), #from do tip:AddLine("From " .. from[i], 0.86, 0.86, 0.89) end
        tip:AddLine("Click to reply.", 0.6, 0.6, 0.65)
    end
    chip.click = function()
        local reply = (_G.ChatFrameUtil and _G.ChatFrameUtil.ReplyTell) or _G.ChatFrame_ReplyTell
        clear()
        GameTooltip:Hide()
        if reply then pcall(reply) end
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, e, _, sender)
        if e == "CHAT_MSG_WHISPER" or e == "CHAT_MSG_BN_WHISPER" then
            count = count + 1
            local who = (type(sender) == "string" and not secret(sender)) and (Ambiguate and Ambiguate(sender, "short") or sender) or "someone"
            if from[#from] ~= who then
                if #from >= 6 then table.remove(from, 1) end
                from[#from + 1] = who
            end
            refresh()
        else
            clear()
        end
    end)
end

-- ── Aggro ring ────────────────────────────────────────────────────────────
-- In a group, a thin ring just outside the health orb: amber when you are
-- close to pulling something off the tank, red and pulsing once it is on
-- you. Not shown solo (everything is on you then) or when you are the tank.
local function buildAggro()
    local O = ns.modules.Orbs
    local orb = O and O.health
    if not orb then return end
    local f = CreateFrame("Frame", nil, orb)
    local S = (orb:GetWidth() + 8) / 0.80 -- the ring's outer edge is at 0.80 of the texture (dist/crest.py)
    f:SetSize(S, S)
    f:SetPoint("CENTER")
    f:SetFrameLevel(math.max(orb:GetFrameLevel() - 1, 0))
    local ring = f:CreateTexture(nil, "ARTWORK")
    ring:SetAllPoints()
    ring:SetTexture(MEDIA .. "crest_ring.tga")
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.3); a:SetDuration(0.45); a:SetSmoothing("IN_OUT")
    f:Hide()
    local function refresh()
        local status = UnitThreatSituation and UnitThreatSituation("player")
        if not num(status) then status = 0 end
        local grouped = IsInGroup and IsInGroup()
        local tank = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") == "TANK"
        if not grouped or tank or status < 1 then
            ag:Stop(); f:Hide()
            return
        end
        f:Show()
        if status >= 2 then
            ring:SetVertexColor(0.95, 0.30, 0.28, 1)
            if not ag:IsPlaying() then ag:Play() end
        else
            ag:Stop(); f:SetAlpha(1)
            ring:SetVertexColor(0.95, 0.76, 0.32, 1)
        end
    end
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_THREAT_SITUATION_UPDATE", "player")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function() pcall(refresh) end)
end

-- ── What hits you, on the health orb ──────────────────────────────────────
-- Damage you take, heals you receive, and what you avoid (dodge, parry,
-- block, miss, resist, absorb) rise out of the health orb and fade: the
-- number or the word, where your health already is. Damage is red (magic
-- in its school's colour), heals green, avoidance pale blue; a critical
-- hit is larger. The amounts can be hidden values in combat: they go
-- straight into the text, unformatted when they are.
local ORB_WORDS = { DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", MISS = "Miss", RESIST = "Resist",
                    ABSORB = "Absorb", IMMUNE = "Immune", EVADE = "Evade", DEFLECT = "Deflect", REFLECT = "Reflect" }
local SCHOOL_TINT = { [2] = { 1.00, 0.90, 0.50 }, [4] = { 1.00, 0.55, 0.25 }, [8] = { 0.55, 0.90, 0.40 },
                      [16] = { 0.55, 0.80, 1.00 }, [32] = { 0.72, 0.55, 1.00 }, [64] = { 0.95, 0.70, 0.95 } }
local function buildOrbText()
    local O = ns.modules.Orbs
    local orb = O and O.health
    if not orb then return end
    local holder = CreateFrame("Frame", nil, orb)
    holder:SetAllPoints()
    holder:SetFrameLevel(orb:GetFrameLevel() + 30)
    holder:Hide()
    local LIFE, RISE = 1.1, 38
    local pool, turn = {}, 0
    for i = 1, 8 do
        local fs = holder:CreateFontString(nil, "OVERLAY")
        ns:SetFont(fs, 16, "OUTLINE", true)
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:Hide()
        pool[i] = fs
    end
    holder:SetScript("OnUpdate", function(self, dt)
        local any = false
        for i = 1, #pool do
            local fs = pool[i]
            if fs.age then
                fs.age = fs.age + dt
                local k = fs.age / LIFE
                if k >= 1 then
                    fs.age = nil
                    fs:Hide()
                else
                    any = true
                    -- Up quickly, then slowing; fading over the last 40%.
                    local e = 1 - (1 - k) ^ 2
                    fs:SetPoint("CENTER", orb, "CENTER", fs.x, fs.y + RISE * e)
                    fs:SetAlpha(k < 0.08 and k / 0.08 or (k > 0.6 and (1 - k) / 0.4) or 1)
                end
            end
        end
        if not any then self:Hide() end
    end)
    -- set(fs) writes the text; big = a critical.
    local function pop(set, r, g, b, big)
        turn = turn % #pool + 1
        local fs = pool[turn]
        ns:SetFont(fs, big and 22 or 16, "OUTLINE", true)
        set(fs)
        fs:SetTextColor(r, g, b)
        fs.age = 0
        -- Alternating sides of the middle, so quick hits don't overprint.
        fs.x = ((turn % 2 == 0) and 1 or -1) * (6 + math.random() * 16)
        fs.y = -4 + math.random() * 10
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", orb, "CENTER", fs.x, fs.y)
        fs:SetAlpha(0)
        fs:Show()
        holder:Show()
    end
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_COMBAT", "player")
    ev:SetScript("OnEvent", function(_, _, _, action, indicator, amount, school)
        if secret(action) then
            -- Nothing to go on but the number itself.
            if amount ~= nil then pop(function(fs) fs:SetText(amount) end, 1.0, 0.86, 0.84, false) end
            return
        end
        local big = not secret(indicator) and (indicator == "CRITICAL" or indicator == "CRUSHING")
        if action == "WOUND" then
            if num(amount) and amount <= 0 then
                -- A hit for nothing: what took it is in the indicator.
                local w = not secret(indicator) and ORB_WORDS[indicator]
                if w then pop(function(fs) fs:SetText(w) end, 0.80, 0.90, 1.00, false) end
                return
            end
            local c = num(school) and SCHOOL_TINT[school]
            local r, g, b = 1.0, 0.36, 0.32
            if c then r, g, b = c[1], c[2], c[3] end
            pop(function(fs)
                if not pcall(fs.SetFormattedText, fs, "-%d", amount) then fs:SetText(amount) end
            end, r, g, b, big)
        elseif action == "HEAL" then
            pop(function(fs)
                if not pcall(fs.SetFormattedText, fs, "+%d", amount) then fs:SetText(amount) end
            end, 0.45, 0.92, 0.52, big)
        else
            local w = ORB_WORDS[action]
            if w then pop(function(fs) fs:SetText(w) end, 0.80, 0.90, 1.00, false) end
        end
    end)
end

-- ── A dot over the quest objective ────────────────────────────────────────
-- An addon can't draw in the world, but the game can: its own waypoint sits
-- over the objective of the quest being followed, and slides to the edge of
-- the screen when that is behind you. It is off by default in this client
-- and nothing chooses a quest for it. So: the game setting is turned on,
-- the quest you focused is followed (a map pin you set yourself is left
-- alone), and the game's large marker is redrawn as a
-- small silver dot with the distance under it.
-- The focused quest: one quest per character, chosen by you (right-click a
-- quest in the objectives panel, or "Focus" in the quest log). It is what
-- the dot points at. MinimalUIDB.questFocus[character] = quest id.
local focusApply -- set once the waypoint is built
ns.QuestFocus = { listeners = {} }
function ns.QuestFocus.Get()
    local t = MinimalUIDB and MinimalUIDB.questFocus
    return t and t[ns:CharKey()] or nil
end
function ns.QuestFocus.Set(id)
    if not MinimalUIDB then return end
    MinimalUIDB.questFocus = MinimalUIDB.questFocus or {}
    MinimalUIDB.questFocus[ns:CharKey()] = id
    if focusApply then pcall(focusApply) end
    for _, fn in ipairs(ns.QuestFocus.listeners) do pcall(fn) end
end
function ns.QuestFocus.Toggle(id)
    ns.QuestFocus.Set(ns.QuestFocus.Get() ~= id and id or nil)
end
function ns.QuestFocus.Available() return focusApply ~= nil end
function ns.QuestFocus.Override() end
function ns.QuestFocus.EndOverride() end

local function buildWaypoint()
    local ST, NV, F = _G.C_SuperTrack, _G.C_Navigation, _G.SuperTrackedFrame
    if not (ST and NV and F and ST.SetSuperTrackedQuestID and C_QuestLog) then return end
    local setcv = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    if setcv then pcall(setcv, "showInGameNavigation", "1") end
    EX.db.waypointSet = true

    local GR, GG, GB = 0.86, 0.89, 0.94
    local halo = F:CreateTexture(nil, "ARTWORK")
    halo:SetTexture(MEDIA .. "spot.tga")
    halo:SetSize(30, 30)
    halo:SetPoint("CENTER")
    halo:SetVertexColor(GR, GG, GB)
    halo:SetAlpha(0.30)
    halo:SetBlendMode("ADD")
    local dot = F:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(MEDIA .. "circle.tga")
    dot:SetSize(9, 9)
    dot:SetPoint("CENTER")
    dot:SetVertexColor(GR, GG, GB)
    dot:SetAlpha(0.95)
    pcall(function()
        local ag = halo:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0.16); a:SetToAlpha(0.42); a:SetDuration(1.6); a:SetSmoothing("IN_OUT")
        ag:Play()
    end)
    local function restyle()
        if F.Icon then F.Icon:SetAlpha(0) end
        if F.IconBorder then F.IconBorder:SetAlpha(0) end
        if F.Arrow then
            pcall(F.Arrow.SetScale, F.Arrow, 0.55)
            -- The game's arrow art is gold itself: a tint only multiplies
            -- it, so the colour is taken out first.
            pcall(F.Arrow.SetDesaturated, F.Arrow, true)
            F.Arrow:SetVertexColor(GR, GG, GB)
            F.Arrow:SetAlpha(0.75)
        end
        local d = F.DistanceText
        if d then
            ns:SetFont(d, 11, "OUTLINE")
            d:SetTextColor(T.text[1], T.text[2], T.text[3])
            d:SetAlpha(0.65)
            d:ClearAllPoints()
            d:SetPoint("TOP", dot, "BOTTOM", 0, -6)
        end
    end
    restyle()
    if type(F.UpdateIcon) == "function" then pcall(hooksecurefunc, F, "UpdateIcon", restyle) end

    -- Where it waits when the objective is off screen. The game holds it on
    -- a small oval round the middle of the screen, close to your character.
    -- This puts it on a much larger one instead: out near the screen's
    -- sides, and at the bottom just above the console. Same direction from
    -- the centre as the game's, so its arrow still points the right way.
    local EDGE_X, EDGE_Y = 0.42, 0.34 -- the oval's half-width / half-height, as a share of the screen
    pcall(F.HookScript, F, "OnUpdate", function(self)
        if not (NV.WasClampedToScreen and NV.GetFrame) then return end
        local clamped = NV.WasClampedToScreen()
        if secret(clamped) or not clamped then return end
        local nav = NV.GetFrame()
        if not nav then return end
        local nx, ny = nav:GetCenter()
        local cx, cy = UIParent:GetCenter()
        if not (num(nx) and num(ny) and num(cx) and num(cy)) then return end
        local k = nav:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local dx, dy = nx * k - cx, ny * k - cy
        local a, b = UIParent:GetWidth() * EDGE_X, UIParent:GetHeight() * EDGE_Y
        local d = math.sqrt((dx / a) ^ 2 + (dy / b) ^ 2)
        if d < 0.0001 then return end
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", dx / d, dy / d)
    end)

    -- Which quest the dot is for: the one you focused (ns.QuestFocus), and
    -- nothing else. No focus, no dot. A map pin you set yourself is left
    -- alone, and a rare that has just appeared borrows the dot for a while
    -- (ns.QuestFocus.Override).
    local born = GetTime()
    local override, hadOverride
    local function apply()
        local rec = { at = date("%H:%M:%S") }
        if MinimalUIDB then MinimalUIDB.waypoint = rec end
        if override and GetTime() > override.till then override = nil end
        if override then
            hadOverride = true
            rec.override = true
            if ST.SetSuperTrackedVignette then pcall(ST.SetSuperTrackedVignette, override.guid) end
            return
        end
        if hadOverride then
            hadOverride = nil
            if ST.ClearAllSuperTracked then pcall(ST.ClearAllSuperTracked) end
        end
        if (ST.IsSuperTrackingMapPin and ST.IsSuperTrackingMapPin())
            or (ST.IsSuperTrackingUserWaypoint and ST.IsSuperTrackingUserWaypoint())
            or (ST.IsSuperTrackingCorpse and ST.IsSuperTrackingCorpse()) then rec.left = "pin"; return end
        local want = ns.QuestFocus.Get()
        -- The quest is no longer in your log: the focus goes with it. (Not
        -- in the first seconds after login, while the log is still empty.)
        if want and GetTime() - born > 15 and C_QuestLog.GetLogIndexForQuestID
            and not C_QuestLog.GetLogIndexForQuestID(want) then
            ns.QuestFocus.Set(nil)
            return
        end
        local cur = ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID()
        if secret(cur) then return end
        if cur == 0 then cur = nil end
        rec.want, rec.cur = want, cur
        if want then
            if cur ~= want then pcall(ST.SetSuperTrackedQuestID, want) end
        elseif cur then
            if ST.ClearAllSuperTracked then pcall(ST.ClearAllSuperTracked) else pcall(ST.SetSuperTrackedQuestID, 0) end
        end
        pcall(function()
            rec.frame = NV.GetFrame and NV.GetFrame() ~= nil
            local dist = NV.GetDistance and NV.GetDistance()
            rec.dist = secret(dist) and "secret" or dist
            rec.shown = F:IsShown()
        end)
    end
    local due = false
    local function soon()
        if due then return end
        due = true
        C_Timer.After(0.3, function() due = false; pcall(apply) end)
    end
    focusApply = soon
    function ns.QuestFocus.Override(guid, seconds)
        override = { guid = guid, till = GetTime() + (seconds or 60) }
        soon()
        C_Timer.After((seconds or 60) + 0.5, soon)
    end
    function ns.QuestFocus.EndOverride() if override then override.till = 0; soon() end end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE",
                         "ZONE_CHANGED_NEW_AREA", "QUEST_POI_UPDATE", "SUPER_TRACKING_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e)
        if e == "SUPER_TRACKING_CHANGED" then restyle() end
        soon()
    end)
    C_Timer.NewTicker(5, soon)
end

-- ── A profession at its cap ───────────────────────────────────────────────
-- A skill that has reached the most its training allows (75, 150, 225)
-- stops going up, and nothing says so: you can skin for an hour and gain
-- nothing. So every time you use a profession that is sitting at such a
-- cap (gathering, or making something), a warning pill says it is capped
-- and to see a trainer. A skill at its final cap (300 or more) says nothing.
local CAP_SPELL = { ["Skinning"] = 393, ["Mining"] = 186, ["Herb Gathering"] = 182, ["Herbalism"] = 182,
                    ["Fishing"] = 356, ["Disenchant"] = 333, ["Smelting"] = 186 }
local CAP_FINAL = 300
-- Professions only: the recipe lookup below also answers for ordinary
-- spells, with their class skill ("Shadow Magic"), which is no profession.
local CAP_PROF = { [164] = true, [165] = true, [171] = true, [182] = true, [185] = true, [186] = true,
                   [197] = true, [202] = true, [333] = true, [356] = true, [393] = true, [129] = true }
local function buildSkillCap()
    local S = _G.C_SkillInfo
    if not (S and S.GetSkillLineInfoByID) then return end
    local last = 0
    local function skillOf(spellID)
        local name = C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, spellID)
        if type(name) == "string" and not secret(name) and CAP_SPELL[name] then return CAP_SPELL[name] end
        -- Something being made: the recipe knows its profession.
        local f = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineForRecipe
        if f then
            local ok, id = pcall(f, spellID)
            if ok and num(id) and CAP_PROF[id] then return id end
        end
    end
    local function check(spellID)
        if not num(spellID) then return end
        local id = skillOf(spellID)
        if not id then return end
        local ok, info = pcall(S.GetSkillLineInfoByID, id)
        if not (ok and type(info) == "table") then return end
        local rank, max, name = info.rank, info.maxRank, info.name
        if not (num(rank) and num(max) and type(name) == "string") then return end
        if max < 75 or max >= CAP_FINAL or rank < max then return end
        local now = GetTime()
        if now - last < 1 then return end
        last = now
        local icon = C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, spellID)
        if secret(icon) then icon = nil end
        if ns.FloatWarning then
            ns.FloatWarning(icon or "Interface/Icons/INV_Misc_QuestionMark", name .. " capped at " .. max, "See a trainer")
        elseif UIErrorsFrame then
            UIErrorsFrame:AddMessage(name .. " is capped at " .. max .. ": see a trainer.", 1, 0.4, 0.35)
        end
    end
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:SetScript("OnEvent", function(_, _, _, _, spellID) pcall(check, spellID) end)
end

-- ── "Used in": what a reagent makes ───────────────────────────────────────
-- Your recipes and what they need are written down whenever a profession
-- window is open (Professions.lua calls ns.RecordRecipe), per character:
-- MinimalUIDB.recipes[char][recipeID] = { n = name, r = { [itemID] = need } }.
-- An item's tooltip then lists the recipes of yours that use it, and how
-- many of each you could make with what is in your bags.
local useIndex
function ns.RecordRecipe(id, name, list)
    local db = MinimalUIDB
    if not (db and num(id) and type(name) == "string" and type(list) == "table") then return end
    local r = {}
    for _, rg in ipairs(list) do
        if num(rg.itemID) then r[rg.itemID] = num(rg.need) and rg.need or 1 end
    end
    if not next(r) then return end
    db.recipes = db.recipes or {}
    local key = ns:CharKey()
    db.recipes[key] = db.recipes[key] or {}
    db.recipes[key][id] = { n = name, r = r }
    useIndex = nil
end
local madeBuf = {}
function madeLines(tip, id)
    local db = MinimalUIDB
    local mine = db and db.recipes and db.recipes[ns:CharKey()]
    if not mine then return end
    if not useIndex then
        useIndex = {}
        for _, rec in pairs(mine) do
            if type(rec) == "table" and type(rec.r) == "table" then
                for item in pairs(rec.r) do
                    useIndex[item] = useIndex[item] or {}
                    table.insert(useIndex[item], rec)
                end
            end
        end
    end
    local list = useIndex[id]
    if not list then return end
    wipe(madeBuf)
    for _, rec in ipairs(list) do
        local can
        for item, need in pairs(rec.r) do
            local k = math.floor(itemCount(item) / math.max(need, 1))
            can = can and math.min(can, k) or k
        end
        rec.can = can or 0
        madeBuf[#madeBuf + 1] = rec
    end
    table.sort(madeBuf, function(a, b)
        if a.can ~= b.can then return a.can > b.can end
        return tostring(a.n) < tostring(b.n)
    end)
    tip:AddLine(" ")
    tip:AddLine("Used in", 0.6, 0.6, 0.65)
    for i = 1, math.min(#madeBuf, 5) do
        local rec = madeBuf[i]
        if rec.can > 0 then
            tip:AddDoubleLine(rec.n, "can make " .. rec.can, 0.86, 0.89, 0.94, 0.40, 0.85, 0.45)
        else
            tip:AddDoubleLine(rec.n, " ", 0.55, 0.57, 0.63, 1, 1, 1)
        end
    end
    if #madeBuf > 5 then tip:AddLine("and " .. (#madeBuf - 5) .. " more", 0.5, 0.5, 0.55) end
end

-- ── Nearly at a profession's cap ──────────────────────────────────────────
-- A skill-up that leaves a profession within five points of the most its
-- training allows: one pill, once per cap, so you can train before the
-- points stop coming. MinimalUIDB.skillNudge[char][skill] = the cap told.
local PROFS = { 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393, 129 }
local function buildNudge()
    local S = _G.C_SkillInfo
    if not (S and S.GetSkillLineInfoByID) then return end
    local function look()
        local db = MinimalUIDB
        if not db then return end
        db.skillNudge = db.skillNudge or {}
        local key = ns:CharKey()
        db.skillNudge[key] = db.skillNudge[key] or {}
        local told = db.skillNudge[key]
        for _, id in ipairs(PROFS) do
            local ok, info = pcall(S.GetSkillLineInfoByID, id)
            if ok and type(info) == "table" and num(info.rank) and num(info.maxRank) and type(info.name) == "string" then
                local rank, max = info.rank, info.maxRank
                if max > 0 and max < 300 and rank < max and max - rank <= 5 and told[id] ~= max then
                    told[id] = max
                    local icon = C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, info.name)
                    if secret(icon) then icon = nil end
                    if ns.FloatWarning then
                        ns.FloatWarning(icon or "Interface/Icons/INV_Misc_Book_09", info.name .. " " .. rank .. " / " .. max, "Train soon")
                    end
                end
            end
        end
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_SKILL")
    f:SetScript("OnEvent", function() C_Timer.After(0.5, function() pcall(look) end) end)
end

-- ── Node memory ───────────────────────────────────────────────────────────
-- Where you have picked herbs and mined ore is remembered (the spot, what
-- it was), and shown on the minimap as faint dots: green for herbs, amber
-- for ore. They are places a node has been, not nodes that are up now.
-- MinimalUIDB.nodes[instance] = { { x, y, kind, name }, ... }; a node
-- within 15 yards of one already known is the same node.
local NODE_SPELL = { ["Mining"] = "ore", ["Herb Gathering"] = "herb", ["Herbalism"] = "herb" }
local NODE_TINT = { ore = { 0.95, 0.72, 0.32 }, herb = { 0.50, 0.85, 0.45 } }
local YARDS_OUT = { 466.67, 400, 333.33, 266.67, 200, 133.33 }
local YARDS_IN = { 300, 240, 180, 120, 80, 50 }
local function playerPos()
    if not UnitPosition then return end
    local ok, y, x, _, inst = pcall(UnitPosition, "player")
    if ok and num(x) and num(y) and num(inst) then return x, y, inst end
end
local function buildNodes()
    local db = MinimalUIDB
    if not (db and Minimap) then return end
    db.nodes = db.nodes or {}
    local sent = {}
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SENT", "player")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
    local dirty = true
    ev:SetScript("OnEvent", function(_, e, _, a2, a3, a4)
        if e == "UNIT_SPELLCAST_SENT" then
            -- (unit, target, castGUID, spellID): the target is the node's name.
            if not secret(a3) and type(a3) == "string" then
                sent.guid, sent.name = a3, (not secret(a2) and type(a2) == "string") and a2 or nil
            end
            return
        end
        -- (unit, castGUID, spellID)
        local spellID = a3
        if not num(spellID) then return end
        local sname = C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, spellID)
        local kind = type(sname) == "string" and not secret(sname) and NODE_SPELL[sname]
        if not kind then return end
        local x, y, inst = playerPos()
        if not x then return end
        local list = db.nodes[inst]
        if not list then list = {}; db.nodes[inst] = list end
        local name = (not secret(a2) and a2 == sent.guid) and sent.name or nil
        for _, n in ipairs(list) do
            if n[3] == kind and (n[1] - x) ^ 2 + (n[2] - y) ^ 2 < 15 * 15 then
                if name then n[4] = name end
                return
            end
        end
        list[#list + 1] = { math.floor(x * 10) / 10, math.floor(y * 10) / 10, kind, name }
        dirty = true
    end)

    -- The dots.
    local layer = CreateFrame("Frame", nil, Minimap)
    layer:SetAllPoints()
    layer:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    local pool = {}
    local function dotAt(i)
        local d = pool[i]
        if not d then
            d = layer:CreateTexture(nil, "OVERLAY")
            d:SetTexture(MEDIA .. "circle.tga")
            d:SetSize(5, 5)
            pool[i] = d
        end
        return d
    end
    local lx, ly, lz, lf
    local acc = 0
    layer:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.15 then return end
        acc = 0
        local x, y, inst = playerPos()
        local used = 0
        local list = x and db.nodes[inst]
        if list and #list > 0 then
            local zoom = Minimap:GetZoom()
            local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
            local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
            if secret(facing) or type(facing) ~= "number" then facing = 0 end
            if not dirty and x == lx and y == ly and zoom == lz and facing == lf then return end
            dirty, lx, ly, lz, lf = false, x, y, zoom, facing
            local indoors = IsIndoors and IsIndoors()
            local yards = ((indoors and YARDS_IN or YARDS_OUT)[(num(zoom) and zoom or 0) + 1] or 466.67) / 2
            local half = Minimap:GetWidth() / 2
            local sin, cos = math.sin(facing), math.cos(facing)
            local reach = (yards * 0.94) ^ 2
            for _, n in ipairs(list) do
                local dx, dy = x - n[1], y - n[2]
                if dx * dx + dy * dy < reach then
                    if rotate then dx, dy = dx * cos - dy * sin, dx * sin + dy * cos end
                    used = used + 1
                    local d = dotAt(used)
                    local c = NODE_TINT[n[3]] or NODE_TINT.ore
                    d:SetVertexColor(c[1], c[2], c[3], 0.55)
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", Minimap, "CENTER", dx / yards * half, -dy / yards * half)
                    d:Show()
                    if used >= 60 then break end
                end
            end
        else
            if lx == nil and not dirty then return end
            lx, dirty = nil, false
        end
        for i = used + 1, #pool do pool[i]:Hide() end
    end)
end

-- ── Flight timer ──────────────────────────────────────────────────────────
-- How long each flight takes is learned from your own flights (from where,
-- to where, seconds: MinimalUIDB.flights["From|To"]). On a flight you have
-- taken before, a thin bar at the top of the screen counts it down; on a
-- new one it shows the time flown so far.
local function buildFlight()
    local db = MinimalUIDB
    if not db then return end
    db.flights = db.flights or {}
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(180, 3)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -96)
    bar:Hide()
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.9)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(0.86, 0.89, 0.94, 0.9)
    local label = bar:CreateFontString(nil, "OVERLAY")
    ns:SetFont(label, 11, "OUTLINE")
    label:SetPoint("BOTTOM", bar, "TOP", 0, 5)
    label:SetTextColor(T.text[1], T.text[2], T.text[3])
    local src, dst, started, known, key
    local function clock(s)
        s = math.max(0, math.floor(s + 0.5))
        return string.format("%d:%02d", math.floor(s / 60), s % 60)
    end
    local onTaxi, finish
    local poll = 0
    bar:SetScript("OnUpdate", function(self, dt)
        if not started then self:Hide() return end
        local flown = GetTime() - started
        -- Landed? (Looked at twice a second; the game's "control gained"
        -- can come a moment before the flight is really over.)
        poll = poll + dt
        if poll > 0.5 then
            poll = 0
            if flown > 3 and not onTaxi() then finish() return end
        end
        if known then
            fill:SetWidth(math.max(0.01, math.min(1, flown / known)) * self:GetWidth())
            fill:Show()
            label:SetText((dst or "Flight") .. "   " .. clock(known - flown))
        else
            fill:Hide()
            label:SetText((dst or "Flight") .. "   " .. clock(flown))
        end
    end)
    if type(_G.TakeTaxiNode) == "function" then
        hooksecurefunc("TakeTaxiNode", function(i)
            src, dst = nil, nil
            pcall(function()
                dst = TaxiNodeName(i)
                for j = 1, NumTaxiNodes() do
                    if TaxiNodeGetType(j) == "CURRENT" then src = TaxiNodeName(j) end
                end
            end)
            if type(dst) ~= "string" or secret(dst) then dst = nil end
            if type(src) ~= "string" or secret(src) then src = nil end
        end)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_CONTROL_LOST")
    function onTaxi() local ok, v = pcall(UnitOnTaxi, "player"); return ok and not secret(v) and v == true end
    function finish()
        local took = started and (GetTime() - started) or 0
        if key and took > 8 then db.flights[key] = math.floor(took) end
        started, src, dst, known, key = nil, nil, nil, nil, nil
        bar:Hide()
    end
    ev:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_CONTROL_LOST" then
            -- (Control is also lost to fear and the like: wait and see
            -- whether this is a flight.)
            C_Timer.After(1.5, function()
                if started or not onTaxi() then return end
                started = GetTime() - 1.5
                key = src and dst and (src .. "|" .. dst) or nil
                known = key and db.flights[key] or nil
                -- Just the place, without ", Zone".
                if dst then dst = dst:match("^([^,]+)") or dst end
                bar:Show()
            end)
        end
    end)
end

-- ── Rare alert ────────────────────────────────────────────────────────────
-- A rare nearby: a pill above your head and a soft ping, once per rare
-- (not again for ten minutes). Two ways of noticing one: the game's own
-- minimap marks for rares (where this client has them), in which case the
-- quest dot is borrowed for a minute and a half to point at it; and any
-- rare whose nameplate appears, or that you target or point at.
local function buildRare()
    local seen = {}
    local function alert(key, name, guidForDot)
        local now = GetTime()
        if seen[key] and now - seen[key] < 600 then return end
        seen[key] = now
        if ns.FloatWarning then
            ns.FloatWarning(MEDIA .. "micro_achievement.tga", "Rare: " .. name, guidForDot and "follow the dot" or "nearby")
        end
        pcall(PlaySound, 3175)
        if guidForDot and ns.QuestFocus and ns.QuestFocus.Available() then ns.QuestFocus.Override(guidForDot, 90) end
    end
    local V = _G.C_VignetteInfo
    local function vignette(guid)
        if not (V and V.GetVignetteInfo) or secret(guid) or type(guid) ~= "string" then return end
        local ok, info = pcall(V.GetVignetteInfo, guid)
        if not (ok and type(info) == "table") then return end
        local name, atlas = info.name, info.atlasName
        if type(name) ~= "string" or secret(name) or name == "" then return end
        if MinimalUIDB and type(atlas) == "string" and not secret(atlas) then
            MinimalUIDB.vignettes = MinimalUIDB.vignettes or {}
            MinimalUIDB.vignettes[atlas] = name
        end
        if info.isDead then return end
        local a = type(atlas) == "string" and not secret(atlas) and atlas:lower() or ""
        if a:find("kill", 1, true) or a:find("rare", 1, true) or a:find("elite", 1, true) then
            alert("v:" .. name, name, guid)
        end
    end
    local function unit(u)
        local ok, c = pcall(UnitClassification, u)
        if not ok or secret(c) or (c ~= "rare" and c ~= "rareelite") then return end
        local dead = UnitIsDead(u)
        if secret(dead) or dead then return end
        local name = UnitName(u)
        if type(name) ~= "string" or secret(name) then return end
        if seen["v:" .. name] then seen[name] = seen["v:" .. name] end
        alert(name, name)
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED", "NAME_PLATE_UNIT_ADDED",
                         "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e, a1)
        if e == "VIGNETTE_MINIMAP_UPDATED" then pcall(vignette, a1)
        elseif e == "VIGNETTES_UPDATED" then
            if V and V.GetVignettes then
                local ok, list = pcall(V.GetVignettes)
                if ok and type(list) == "table" then for _, g in ipairs(list) do pcall(vignette, g) end end
            end
        elseif e == "NAME_PLATE_UNIT_ADDED" then pcall(unit, a1)
        elseif e == "PLAYER_TARGET_CHANGED" then pcall(unit, "target")
        else pcall(unit, "mouseover") end
    end)
end

-- ── Reactive spells ───────────────────────────────────────────────────────
-- Spells that can only be pressed now and then (Overpower after a dodge,
-- Execute on a dying target, Riposte after a parry...) don't need a place
-- on the bar: each has a button above the dome that is only there while
-- the spell can be used, and pops in when it becomes so. Click it, or bind
-- a key (Key Bindings > AddOns > Meniscus > Reactive spell 1-4).
-- The buttons are made out of combat, one fixed place per spell: a secure
-- button can't be made, moved or hidden in a fight, so what comes and goes
-- is only its picture (a plain child frame). Which spells: the class list
-- below plus your own (/men reactive add <spell>), those you know.
local REACTIVE = {
    WARRIOR = { "Overpower", "Revenge", "Execute", "Victory Rush" },
    ROGUE = { "Riposte" },
    HUNTER = { "Mongoose Bite", "Counterattack" },
    PALADIN = { "Hammer of Wrath" },
}
local RX_MAX, RX_SIZE, RX_GAP = 4, 30, 6
for i = 1, RX_MAX do _G["BINDING_NAME_CLICK MeniscusReactive" .. i .. ":LeftButton"] = "Reactive spell " .. i end
local function buildReactive()
    local dome = _G.MinimalUI_MinimapDome
    local anchor = dome or UIParent
    local btns = {}
    for i = 1, RX_MAX do
        local b = CreateFrame("Button", "MeniscusReactive" .. i, UIParent, "SecureActionButtonTemplate")
        b:SetSize(RX_SIZE, RX_SIZE)
        b:RegisterForClicks("AnyDown", "AnyUp")
        b:SetFrameStrata("MEDIUM")
        b:Hide()
        local vis = CreateFrame("Frame", nil, b)
        vis:SetAllPoints()
        vis:Hide()
        local mask = vis:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints()
        local ring = vis:CreateTexture(nil, "BACKGROUND")
        ring:SetAllPoints()
        ring:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        ring:AddMaskTexture(mask)
        local imask = vis:CreateMaskTexture()
        imask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        imask:SetPoint("TOPLEFT", 1.5, -1.5); imask:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
        local icon = vis:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(imask)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:AddMaskTexture(imask)
        local cd = CreateFrame("Cooldown", nil, vis, "CooldownFrameTemplate")
        cd:SetAllPoints(imask)
        pcall(cd.SetDrawEdge, cd, false)
        -- The pop: a little large and clear, settling to size.
        local ag = vis:CreateAnimationGroup()
        local sc = ag:CreateAnimation("Scale")
        sc:SetScaleFrom(1.35, 1.35); sc:SetScaleTo(1, 1); sc:SetDuration(0.18); sc:SetSmoothing("OUT")
        local al = ag:CreateAnimation("Alpha")
        al:SetFromAlpha(0); al:SetToAlpha(1); al:SetDuration(0.12)
        b.vis, b.icon, b.cd, b.pop = vis, icon, cd, ag
        b:SetScript("OnEnter", function(self)
            if not (self.spell and self.vis:IsShown()) then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local info = C_Spell.GetSpellInfo and call(C_Spell.GetSpellInfo, self.spell)
            if type(info) == "table" and num(info.spellID) and GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(info.spellID)
            else
                GameTooltip:SetText(self.spell, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btns[i] = b
    end

    local function knownInfo(name)
        local info = C_Spell.GetSpellInfo and call(C_Spell.GetSpellInfo, name)
        if type(info) ~= "table" or not num(info.spellID) then return end
        local k = C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(info.spellID)
        if k == nil and IsSpellKnown then k = IsSpellKnown(info.spellID) end
        if k == false then return end
        return info
    end
    -- Which spells, and where: out of combat only.
    local stale = false
    local function assign()
        if InCombatLockdown() then stale = true return end
        stale = false
        local _, cls = UnitClass("player")
        local names, seen = {}, {}
        local function add(n)
            if type(n) == "string" and not seen[n] and #names < RX_MAX then
                local info = knownInfo(n)
                if info then seen[n] = true; names[#names + 1] = { n, info.iconID } end
            end
        end
        for _, n in ipairs(REACTIVE[cls or ""] or {}) do add(n) end
        for _, n in ipairs(EX.db.reactiveExtra or {}) do add(n) end
        local total = #names
        local width = total * RX_SIZE + math.max(0, total - 1) * RX_GAP
        for i, b in ipairs(btns) do
            local e = names[i]
            if e then
                b.spell = e[1]
                b:SetAttribute("type", "spell")
                b:SetAttribute("spell", e[1])
                b.icon:SetTexture(e[2])
                b:ClearAllPoints()
                if dome then
                    b:SetPoint("BOTTOMLEFT", anchor, "TOP", -width / 2 + (i - 1) * (RX_SIZE + RX_GAP), 44)
                else
                    b:SetPoint("BOTTOMLEFT", anchor, "BOTTOM", -width / 2 + (i - 1) * (RX_SIZE + RX_GAP), 230)
                end
                b:Show()
            else
                b.spell = nil
                b:SetAttribute("type", nil)
                b.vis:Hide()
                b:Hide()
            end
        end
    end
    EX.AssignReactive = assign

    -- Whether each can be pressed right now.
    local function update()
        for _, b in ipairs(btns) do
            if b.spell then
                local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, b.spell)
                local show, dim = false, false
                if ok and not secret(usable) and not secret(noMana) then
                    if usable == true then show = true
                    elseif noMana == true then show, dim = true, true end
                end
                if show then
                    b.icon:SetDesaturated(dim)
                    b.vis:SetAlpha(dim and 0.45 or 1)
                    if not b.vis:IsShown() then
                        b.vis:Show()
                        b.pop:Stop(); b.pop:Play()
                    end
                    local okc, c = pcall(C_Spell.GetSpellCooldown, b.spell)
                    if okc and type(c) == "table" then pcall(b.cd.SetCooldown, b.cd, c.startTime, c.duration) end
                elseif b.vis:IsShown() then
                    b.vis:Hide()
                end
            end
        end
    end
    local due = false
    local function soon()
        if due then return end
        due = true
        C_Timer.After(0.05, function() due = false; ns.Timed("reactive spells", update) end)
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "PLAYER_TARGET_CHANGED",
                         "UPDATE_SHAPESHIFT_FORM", "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED",
                         "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e)
        if e == "SPELLS_CHANGED" or e == "PLAYER_ENTERING_WORLD" or (e == "PLAYER_REGEN_ENABLED" and stale) then
            pcall(assign)
        end
        soon()
    end)
    -- (The target's health, for Execute and the like, has no event of its
    -- own that is safe to read: look a few times a second in a fight.)
    C_Timer.NewTicker(0.3, function() if InCombatLockdown() then soon() end end)
    assign()
    soon()
end
ns.commands = ns.commands or {}
ns.commands.reactive = function(_, raw)
    local d = EX.db
    if not d then return end
    d.reactiveExtra = d.reactiveExtra or {}
    local verb, name = (raw or ""):match("^%s*(%S+)%s*(.-)%s*$")
    verb = verb and verb:lower()
    if verb == "add" and name ~= "" then
        table.insert(d.reactiveExtra, name)
        ns:Print("Reactive spells: added " .. name .. " (it shows above the dome while it can be used).")
    elseif verb == "remove" and name ~= "" then
        for i = #d.reactiveExtra, 1, -1 do
            if d.reactiveExtra[i]:lower() == name:lower() then table.remove(d.reactiveExtra, i) end
        end
        ns:Print("Reactive spells: removed " .. name .. ".")
    else
        ns:Print("Reactive spells you added: " .. (#d.reactiveExtra > 0 and table.concat(d.reactiveExtra, ", ") or "none")
            .. ".  /men reactive add <spell>  ·  /men reactive remove <spell>")
        return
    end
    if EX.AssignReactive then
        if InCombatLockdown() then ns:Print("It takes effect after the fight.") end
        pcall(EX.AssignReactive)
    end
end

-- ── What you actually press ───────────────────────────────────────────────
-- Every spell you cast is counted, per character, against the days you
-- have played (MinimalUIDB.usage[char] = { days, date, n = { [spell] =
-- casts }, last = { [spell] = play-day of the last cast } }). From that,
-- "/men tidy" lists the spells on your bars that you have not cast in the
-- last IDLE_DAYS days of play, each with a button that takes it off the
-- bar (it stays in your spellbook). Nothing is ever moved without a click.
local IDLE_DAYS = 4
local function usageTable()
    local db = MinimalUIDB
    if not db then return end
    db.usage = db.usage or {}
    local key = ns:CharKey()
    local u = db.usage[key]
    if not u then u = { days = 0, n = {}, last = {} }; db.usage[key] = u end
    u.n, u.last = u.n or {}, u.last or {}
    return u
end
local function idleButtons()
    local u = usageTable()
    local out = {}
    if not (u and GetActionInfo) or u.days <= IDLE_DAYS then return out, u end
    for slot = 1, 120 do
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and kind == "spell" and num(id) then
            local name = C_Spell.GetSpellName and call(C_Spell.GetSpellName, id)
            if type(name) == "string" and not secret(name) then
                local passive = C_Spell.IsSpellPassive and call(C_Spell.IsSpellPassive, id)
                local last = u.last[name] or 0
                if passive ~= true and u.days - last >= IDLE_DAYS then
                    out[#out + 1] = { slot = slot, name = name, id = id, idle = u.days - last, never = u.last[name] == nil,
                                      icon = C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, id) }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.idle ~= b.idle then return a.idle > b.idle end
        return a.slot < b.slot
    end)
    return out, u
end
local tidyWin
local function showTidy()
    local list, u = idleButtons()
    if not u then return end
    if u.days <= IDLE_DAYS then
        ns:Print("Still learning what you press: day " .. u.days .. " of " .. (IDLE_DAYS + 1)
            .. " played since it started counting. Try /men tidy again after that.")
        return
    end
    if #list == 0 then
        if tidyWin then tidyWin:Hide() end
        ns:Print("Every spell on your bars has been used in your last " .. IDLE_DAYS .. " days of play.")
        return
    end
    local ROWS, RH, W = 10, 26, 380
    if not tidyWin then
        local w = CreateFrame("Frame", "MeniscusTidy", UIParent)
        w:SetSize(W, 74 + ROWS * RH + 44)
        w:SetPoint("CENTER", 0, 60)
        w:SetFrameStrata("HIGH")
        w:EnableMouse(true)
        w:SetMovable(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", w.StartMoving)
        w:SetScript("OnDragStop", w.StopMovingOrSizing)
        ns.RoundedRect(w, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(w, -7, 1, 13, 0.06, 0.06, 0.07, 0.97)
        table.insert(UISpecialFrames, "MeniscusTidy")
        local title = w:CreateFontString(nil, "OVERLAY")
        ns:SetFont(title, 14, "", true)
        title:SetPoint("TOPLEFT", 18, -16)
        title:SetText("Unused buttons")
        title:SetTextColor(T.text[1], T.text[2], T.text[3])
        w.sub = w:CreateFontString(nil, "OVERLAY")
        ns:SetFont(w.sub, 10)
        w.sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
        w.sub:SetPoint("RIGHT", w, "RIGHT", -18, 0)
        w.sub:SetJustifyH("LEFT")
        w.sub:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
        w.rows = {}
        for i = 1, ROWS do
            local r = CreateFrame("Frame", nil, w)
            r:SetSize(W - 36, RH)
            r:SetPoint("TOPLEFT", 18, -66 - (i - 1) * RH)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(20, 20)
            r.icon:SetPoint("LEFT")
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.name = r:CreateFontString(nil, "OVERLAY")
            ns:SetFont(r.name, 11, "", true)
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
            r.name:SetTextColor(T.text[1], T.text[2], T.text[3])
            r.note = r:CreateFontString(nil, "OVERLAY")
            ns:SetFont(r.note, 10)
            r.note:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
            r.note:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
            r.off = ns.Pill(r, "Take off bar", function()
                if InCombatLockdown() then ns:Print("Not in combat.") return end
                if r.slot and PickupAction then
                    pcall(PickupAction, r.slot)
                    pcall(ClearCursor)
                end
                C_Timer.After(0.2, showTidy)
            end, { h = 20, font = 10 })
            r.off:SetPoint("RIGHT")
            w.rows[i] = r
        end
        w.close = ns.Pill(w, "Close", function() w:Hide() end, { h = 24 })
        w.close:SetPoint("BOTTOMLEFT", 18, 14)
        tidyWin = w
    end
    local w = tidyWin
    w.sub:SetText("On your bars, but not cast in your last " .. IDLE_DAYS .. " days of play"
        .. (#list > ROWS and ("  (" .. ROWS .. " of " .. #list .. ")") or "")
        .. ". Taking one off the bar leaves it in your spellbook.")
    for i, r in ipairs(w.rows) do
        local e = list[i]
        if e then
            r.slot = e.slot
            r.icon:SetTexture(e.icon)
            r.name:SetText(e.name)
            r.note:SetText(e.never and "never, since counting began" or (e.idle .. " play days ago"))
            r:Show()
        else
            r:Hide()
        end
    end
    w:Show()
end
ns.commands.tidy = function() pcall(showTidy) end
local function buildUsage()
    local u = usageTable()
    if not u then return end
    local today = date("%Y-%m-%d")
    if u.date ~= today then u.date = today; u.days = (u.days or 0) + 1 end
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:SetScript("OnEvent", function(_, _, _, _, spellID)
        if not num(spellID) then return end
        local name = C_Spell.GetSpellName and call(C_Spell.GetSpellName, spellID)
        if type(name) ~= "string" or secret(name) then return end
        u.n[name] = (u.n[name] or 0) + 1
        u.last[name] = u.days
    end)
    -- A word in chat, once per day of play, when a few have piled up.
    C_Timer.After(25, function()
        if u.toldDay == u.days or InCombatLockdown() then return end
        local ok, list = pcall(idleButtons)
        if ok and #list >= 3 then
            u.toldDay = u.days
            ns:Print(#list .. " spells on your bars haven't been cast in your last " .. IDLE_DAYS
                .. " days of play. /men tidy shows them.")
        end
    end)
end

function EX:OnInit(db)
    self.db = db
    if db.reactive ~= false then pcall(buildReactive) end
    if db.usage ~= false then pcall(buildUsage) end
    if db.skillNudge ~= false then pcall(buildNudge) end
    if db.nodes ~= false then pcall(buildNodes) end
    if db.flight ~= false then pcall(buildFlight) end
    if db.rare ~= false then pcall(buildRare) end
    if db.skillCap ~= false then pcall(buildSkillCap) end
    if db.waypoint ~= false then
        pcall(buildWaypoint)
    elseif db.waypointSet then
        -- Switched off: hand the game's setting back.
        db.waypointSet = nil
        local setcv = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
        if setcv then pcall(setcv, "showInGameNavigation", "0") end
    end
    if db.orbText ~= false then pcall(buildOrbText) end
    if db.aggro ~= false then pcall(buildAggro) end
    if db.durability ~= false then pcall(buildDurability) end
    if db.mail ~= false then pcall(buildMail) end
    if db.whisper ~= false then pcall(buildWhisper) end
    if db.owned ~= false then pcall(buildOwned) end
    if db.petFood ~= false then pcall(buildPetFood) end
end
