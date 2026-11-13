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
            if num(id) then pcall(ownedLines, tip, id) end
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

function EX:OnInit(db)
    self.db = db
    if db.aggro ~= false then pcall(buildAggro) end
    if db.durability ~= false then pcall(buildDurability) end
    if db.mail ~= false then pcall(buildMail) end
    if db.whisper ~= false then pcall(buildWhisper) end
    if db.owned ~= false then pcall(buildOwned) end
    if db.petFood ~= false then pcall(buildPetFood) end
end
