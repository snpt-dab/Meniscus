local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Bags: Meniscus's bag window, replacing Blizzard's bag frames.
--   mode "combined": one window with every bag in a single grid
--   mode "separate": one card per bag, stacked above a slim control card
-- Tiles: quality ring, item level on gear, stack counts, cooldowns, a coin
-- mark on junk, an accent glow on new items. Control area: search (dims
-- non-matches), Sort, Keys (keyring), bag slots, free slots, money.
--
-- Using items from bags is a protected action on this client, so every tile
-- is a SecureActionButton: right-click uses the item through Blizzard's
-- secure "item" action ("bag slot"), which also sells at merchants. Left
-- click / drag / shift-click (link or split) are ordinary pickups.
-- Secure tiles make their windows protected, so in combat ordinary addon code
-- can't open, close or rearrange them. The bag keys click a secure handler
-- (MinimalUIBagsToggle) that is allowed to show / hide them mid-fight; the
-- layout stays as it was until combat ends. Only if our window was never
-- built before the fight do Blizzard's bags open instead. Closing from
-- other places (a bag-bar click) still waits for combat to end.

local B = ns:NewModule("Bags", { enabled = true, cols = 10, sepCols = 4, showKeys = false, mode = "separate" })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local TILE, GAP, PAD = 34, 4, 16
local HEADER, FOOTER = (ns.SHELL_H or 92) + 12, 44
local CARD_HEADER = 30
local FILL = { 0.06, 0.06, 0.07, 0.97 }
local EMPTY = { 0.09, 0.09, 0.10, 1 }
local PILL_OFF = { 0.13, 0.13, 0.15, 0.95 }
local PILL_HOVER = { 0.20, 0.20, 0.23, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local KEYRING = _G.KEYRING_CONTAINER or -2

local CC = C_Container or {}
local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not secret(v) end

local function numSlots(bag)
    local n = call(CC.GetContainerNumSlots or _G.GetContainerNumSlots, bag)
    return num(n) and n or 0
end

local function itemInfo(bag, slot)
    if CC.GetContainerItemInfo then
        local info = call(CC.GetContainerItemInfo, bag, slot)
        return type(info) == "table" and info or nil
    end
    local icon, count, locked, quality, _, _, link, _, noValue, id = call(_G.GetContainerItemInfo, bag, slot)
    if not icon then return nil end
    return { iconFileID = icon, stackCount = count, isLocked = locked, quality = quality,
             hyperlink = link, hasNoValue = noValue, itemID = id }
end

local function pickup(bag, slot) call(CC.PickupContainerItem or _G.PickupContainerItem, bag, slot) end

-- Inventory bags: backpack + bags, the reagent bag if the client has one,
-- the keyring when toggled on.
local function bagList()
    local list = {}
    local last = _G.NUM_BAG_SLOTS or 4
    for bag = 0, last do table.insert(list, bag) end
    local reagent = _G.NUM_REAGENTBAG_SLOTS and _G.NUM_REAGENTBAG_SLOTS > 0 and last + 1
    if reagent and numSlots(reagent) > 0 then table.insert(list, reagent) end
    return list
end

local function shownBags()
    local list = bagList()
    if B.db.showKeys and numSlots(KEYRING) > 0 then table.insert(list, KEYRING) end
    return list
end

local function isInventoryBag(bag)
    if bag == KEYRING then return true end
    for _, b in ipairs(bagList()) do if b == bag then return true end end
    return false
end

local function bagName(bag)
    if bag == 0 then return BACKPACK_TOOLTIP or "Backpack" end
    if bag == KEYRING then return KEYRING or "Keyring" end
    local name = call(CC.GetBagName or _G.GetBagName, bag)
    return (name and not secret(name)) and name or ("Bag " .. bag)
end

-- ── Small widgets ─────────────────────────────────────────────────────────
local win                         -- main window (combined) / control card (separate)
local cards = {}                  -- separate mode: cards[bag]
local holders, buttons = {}, {}   -- holders[bag] (ID = bag), buttons[bag][slot]
local pending = { layout = false, hide = false }

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local PILL_OPTS = { h = 22, pad = 24, minW = 44, dimIdle = true }
local function pill(parent, label, onClick)
    return ns.Pill(parent, label, onClick, PILL_OPTS)
end

local function closeButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local mask = b:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(20, 20)
    mask:SetPoint("CENTER")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    bg:SetColorTexture(0.16, 0.16, 0.18, 1)
    bg:AddMaskTexture(mask)
    local lines = {}
    for i, p in ipairs({ { -1, 1, 1, -1 }, { -1, -1, 1, 1 } }) do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetStartPoint("CENTER", b, p[1] * 4, p[2] * 4)
        l:SetEndPoint("CENTER", b, p[3] * 4, p[4] * 4)
        l:SetColorTexture(unpack(T.textDim))
        lines[i] = l
    end
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(unpack(T.accent))
        for _, l in ipairs(lines) do l:SetColorTexture(unpack(TEXT_DARK)) end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(0.16, 0.16, 0.18, 1)
        for _, l in ipairs(lines) do l:SetColorTexture(unpack(T.textDim)) end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A dark rounded card that drags the whole bag set around.
local function newCard(name)
    -- Explicitly protected: the in-combat toggle can only show / hide
    -- frames that are (a card with no item tiles is not protected on its
    -- own, and one such card stopped the toggle before it reached the rest).
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "SecureFrameTemplate")
    if not ok or not f then f = CreateFrame("Frame", name, UIParent) end
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        win:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local p, _, rp, x, y = win:GetPoint(1)
        B.db.pos = { p, rp, x, y }
    end)
    ns.RoundedRect(f, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(f, -7, 1, 13, unpack(FILL))
    f:Hide()
    return f
end

-- Show / hide a separate-mode card and tell the secure toggle about it
-- (out of combat only; in combat the toggle does the showing and hiding).
local function setCard(card, on)
    if InCombatLockdown() then return end
    card:SetShown(on)
    local tg = _G.MinimalUIBagsToggle
    if tg and card.ref then tg:SetAttribute("cardon" .. card.ref, on and true or false) end
end

-- ── Item tiles ────────────────────────────────────────────────────────────
local function holderFor(bag)
    if holders[bag] then return holders[bag] end
    local parent = (B.db.mode == "separate" and cards[bag]) or win
    local h = CreateFrame("Frame", nil, parent)
    h:SetAllPoints(parent)
    h:SetID(bag)
    holders[bag], buttons[bag] = h, {}
    return h
end

local function splitStack(self, n) call(CC.SplitContainerItem or _G.SplitContainerItem, self.bag, self.slot, n) end

-- Gear that goes into one of your equipment slots (not bags, ammo,
-- quivers or things you only use).
local NOT_EQUIP = { INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_NON_EQUIP_IGNORE = true }
local function equipsDirectly(bag, slot)
    local info = itemInfo(bag, slot)
    local link = info and info.hyperlink
    if not link or secret(link) then return false end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    local _, _, _, equipLoc = call(instant, link)
    if type(equipLoc) ~= "string" or equipLoc == "" or NOT_EQUIP[equipLoc] then return false end
    return true
end

local nameCount = 0
local function newButton(bag, slot)
    local h = holderFor(bag)
    nameCount = nameCount + 1
    local b = CreateFrame("Button", "MinimalUIBagItem" .. nameCount, h, "SecureActionButtonTemplate")
    b.bag, b.slot = bag, slot
    b:SetSize(TILE, TILE)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:RegisterForDrag("LeftButton")
    -- Right-click: secure use (the keyring has nothing to use). While a vendor
    -- is open the secure use is switched off and right-click sells instead
    -- (the secure path would equip gear rather than sell it).
    if bag >= 0 then
        if B.interact then b:SetAttribute("*type2", nil) else b:SetAttribute("*type2", "item") end
        b:SetAttribute("item", bag .. " " .. slot)
        if B.targeting then b:SetAttribute("type1", "item") end
    end
    b.SplitStack = splitStack
    -- A spell waiting for an item (Feed Pet, enchants): the secure use above
    -- hands it this item; nothing else should happen on that click.
    b:SetScript("PreClick", function(self, button, down)
        local now = button == "LeftButton" and B.targeting and SpellIsTargeting and SpellIsTargeting() or false
        -- The press may already have fed the spell, so on the release
        -- targeting is over: remember it from the press.
        if down then self.aimed = now else self.aimed = self.aimed or now end
        if now and ns.IsFeedingPet and ns.IsFeedingPet() then
            local fed = itemInfo(self.bag, self.slot)
            if fed and num(fed.itemID) then ns.lastFed, ns.lastFedAt = fed.itemID, GetTime() end
        end
        -- Right-clicking gear: Blizzard's secure "use item" equips gear BY
        -- NAME, so with two of the same item it put on the first one in
        -- your bags, not the one clicked. Out of combat the secure action
        -- is switched off for this click and the clicked piece itself is
        -- equipped (OnClick, below). In combat attributes can't change, so
        -- there the game's own (by-name) equip still happens.
        if button == "RightButton" and self.bag >= 0 and not B.interact and not InCombatLockdown() then
            if down then
                -- (A release outside the tile skips PostClick: put back what
                -- the last click switched off before deciding this one.)
                if self.savedType2 ~= nil then
                    self:SetAttribute("*type2", self.savedType2 or nil)
                    self.savedType2 = nil
                end
                self.equipThis = equipsDirectly(self.bag, self.slot)
            end
            if self.equipThis then
                self.savedType2 = self.savedType2 or self:GetAttribute("*type2") or false
                self:SetAttribute("*type2", nil)
            end
        end
    end)
    b:SetScript("PostClick", function(self, button, down)
        if self.savedType2 ~= nil and not down and not InCombatLockdown() then
            self:SetAttribute("*type2", self.savedType2 or nil)
            self.savedType2 = nil
        end
    end)
    b:HookScript("OnClick", function(self, button, down)
        if self.aimed then return end
        if down then return end
        if button == "RightButton" and self.equipThis then
            self.equipThis = nil
            if not CursorHasItem() and itemInfo(self.bag, self.slot) then
                pickup(self.bag, self.slot)
                if CursorHasItem() then call(_G.AutoEquipCursorItem) end
            end
            return
        end
        if button == "RightButton" then
            if B.interact == "mail" then
                local ML = ns.modules.Mail
                if not CursorHasItem() and itemInfo(self.bag, self.slot) and ML and ML.AttachFromBag then
                    ML:AttachFromBag(self.bag, self.slot)
                end
                return
            end
            if B.interact == "bank" and not CursorHasItem() and itemInfo(self.bag, self.slot) then
                -- Deposit into the first free bank slot.
                local BK = ns.modules.Bank
                local tb, ts
                if BK and BK.FreeSlotIn then tb, ts = BK.FreeSlotIn(BK:BankBags(), true) end
                if tb then
                    pickup(self.bag, self.slot)
                    pickup(tb, ts)
                else
                    UIErrorsFrame:AddMessage(ERR_BANK_FULL or "Your bank is full.", 1, 0.1, 0.1)
                end
                return
            end
            local info = B.sellMode and not CursorHasItem() and itemInfo(self.bag, self.slot)
            if info then
                if info.hasNoValue then
                    UIErrorsFrame:AddMessage(ERR_VENDOR_DOESNT_BUY or "The merchant doesn't want that item.", 1, 0.1, 0.1)
                    return
                end
                pickup(self.bag, self.slot)
                call(_G.PickupMerchantItem, 0)
            end
            return
        end
        if button ~= "LeftButton" then return end
        local info = itemInfo(self.bag, self.slot)
        if IsModifiedClick() and info then
            local link = info.hyperlink
            if link and not secret(link) and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
            local n = info.stackCount
            if IsShiftKeyDown() and num(n) and n > 1 and not CursorHasItem() then
                if StackSplitFrame and StackSplitFrame.OpenStackSplitFrame then
                    StackSplitFrame:OpenStackSplitFrame(n, self, "BOTTOMRIGHT", "TOPRIGHT")
                elseif OpenStackSplitFrame then
                    OpenStackSplitFrame(n, self, "BOTTOMRIGHT", "TOPRIGHT")
                end
                return
            end
        end
        pickup(self.bag, self.slot)
    end)
    b:SetScript("OnDragStart", function(self) pickup(self.bag, self.slot) end)
    b:SetScript("OnReceiveDrag", function(self) pickup(self.bag, self.slot) end)
    b:SetScript("OnEnter", function(self)
        -- Your tooltip placement setting (Edit Mode / default anchor), not
        -- pinned beside the tile.
        if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
        else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
        if itemInfo(self.bag, self.slot) then GameTooltip:SetBagItem(self.bag, self.slot) end
        GameTooltip:Show()
        if self.glow:IsShown() and C_NewItems and C_NewItems.RemoveNewItem then
            pcall(C_NewItems.RemoveNewItem, self.bag, self.slot)
            self.glow:Hide()
        end
        -- At a vendor: the coin "sell" cursor, like Blizzard's bags.
        if B.sellMode and itemInfo(self.bag, self.slot) then
            if ShowContainerSellCursor then pcall(ShowContainerSellCursor, self.bag, self.slot)
            elseif SetCursor then pcall(SetCursor, "BUY_CURSOR") end
        end
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if B.sellMode and ResetCursor then ResetCursor() end
    end)

    b.ring = ns.RoundedRect(b, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    b.fill = ns.RoundedRect(b, -7, 1, 6, unpack(EMPTY))
    local mask = b:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2)
    mask:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(mask)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:AddMaskTexture(mask)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(mask)
    hl:SetColorTexture(1, 1, 1, 0.12)
    hl:AddMaskTexture(mask)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(mask)
    pcall(b.cd.SetDrawEdge, b.cd, false)

    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(b.cd:GetFrameLevel() + 1)
    b.over = over
    b.count = over:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.count, 10, "OUTLINE", true)
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    b.ilvl = over:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.ilvl, 9, "OUTLINE", true)
    b.ilvl:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -3)
    b.junk = over:CreateTexture(nil, "OVERLAY")
    b.junk:SetSize(12, 12)
    b.junk:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    b.junk:SetTexture("Interface/Buttons/UI-GroupLoot-Coin-Up")
    b.junk:Hide()
    -- Better than what you're wearing: a green arrow in the bottom-left
    -- corner (a dark copy behind it keeps it readable on any picture).
    local upBack = over:CreateTexture(nil, "OVERLAY", nil, 1)
    upBack:SetTexture(MEDIA .. "micro_up.tga")
    upBack:SetVertexColor(0, 0, 0, 0.9)
    upBack:SetSize(15, 15)
    upBack:SetPoint("CENTER", b, "BOTTOMLEFT", 8.5, 8.5)
    b.up = over:CreateTexture(nil, "OVERLAY", nil, 2)
    b.up:SetTexture(MEDIA .. "micro_up.tga")
    b.up:SetVertexColor(0.42, 0.92, 0.50, 1)
    b.up:SetSize(12, 12)
    b.up:SetPoint("CENTER", upBack, "CENTER", 0, 0)
    b.upBack = upBack
    b.up:Hide(); upBack:Hide()
    -- Starts a quest you don't have yet: a gold disc with "!" in the top-left
    -- corner (and a gold ring). Items for a quest you're on get the ring only.
    -- A small badge sitting on the tile's corner (over the ring, not over
    -- the picture): a dark rim, a gold disc, and the drawn "!" from the
    -- micro menu's quest icon in dark.
    local bang = CreateFrame("Frame", nil, over)
    bang:SetSize(13, 13)
    bang:SetPoint("CENTER", b, "TOPLEFT", 3.5, -3.5)
    local rim = bang:CreateTexture(nil, "OVERLAY", nil, 0)
    rim:SetTexture(MEDIA .. "circle.tga")
    rim:SetVertexColor(0.04, 0.04, 0.05, 1)
    rim:SetAllPoints()
    local disc = bang:CreateTexture(nil, "OVERLAY", nil, 1)
    disc:SetTexture(MEDIA .. "circle.tga")
    disc:SetVertexColor(1.0, 0.80, 0.20, 1)
    disc:SetPoint("TOPLEFT", 1.5, -1.5)
    disc:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    local mark = bang:CreateTexture(nil, "OVERLAY", nil, 2)
    mark:SetTexture(MEDIA .. "micro_quest.tga")
    mark:SetVertexColor(0.10, 0.07, 0.02, 1)
    mark:SetPoint("TOPLEFT", 0.5, -0.5)
    mark:SetPoint("BOTTOMRIGHT", -0.5, 0.5)
    bang:Hide()
    b.bang = bang

    -- New-item glow: an accent halo one level BELOW the tile (only the rim
    -- around the tile shows), breathing until hovered.
    local glow = CreateFrame("Frame", nil, b)
    glow:SetAllPoints()
    glow:SetFrameLevel(math.max(b:GetFrameLevel() - 1, 0))
    ns.RoundedRect(glow, 0, -3, 9, T.accent[1], T.accent[2], T.accent[3], 0.95)
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.9); a:SetSmoothing("IN_OUT")
    glow:SetScript("OnShow", function() ag:Play() end)
    glow:SetScript("OnHide", function() ag:Stop() end)
    glow:Hide()
    b.glow = glow

    buttons[bag][slot] = b
    return b
end

local function itemLevel(link)
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
    local lvl = call(f, link)
    if num(lvl) and lvl > 1 then return lvl end
end

-- Item level only on real gear: weapons and armor, minus shirts/tabards.
-- (Ammo, quivers and bags are "equippable" too; ammo showed a stray "5".)
local NO_ILVL_SLOT = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_AMMO = true,
                       INVTYPE_BAG = true, INVTYPE_QUIVER = true }
local function isGear(link)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    local _, _, _, equipLoc, _, classID = call(instant, link)
    if num(classID) then
        return (classID == 2 or classID == 4) and not NO_ILVL_SLOT[equipLoc]
    end
    return call((C_Item and C_Item.IsEquippableItem) or _G.IsEquippableItem, link) == true
end

local function matches(info)
    local q = B.search
    if not q or q == "" then return true end
    local link = info.hyperlink
    local name = link and not secret(link) and link:match("%[(.-)%]")
    return name and name:lower():find(q, 1, true) ~= nil
end

-- Is it a quest item, and does it start a quest you haven't taken?
local function questInfo(bag, slot)
    local f = CC.GetContainerItemQuestInfo or _G.GetContainerItemQuestInfo
    if not f then return false, false end
    local ok, a, b2, c = pcall(f, bag, slot)
    if not ok then return false, false end
    local isQuest, qid, active
    if type(a) == "table" then isQuest, qid, active = a.isQuestItem, a.questID or a.questId, a.isActive
    else isQuest, qid, active = a, b2, c end
    if secret(isQuest) or secret(qid) or secret(active) then return false, false end
    local starts = qid ~= nil and qid ~= 0 and not active
    return (isQuest or starts) and true or false, starts and true or false
end

local function updateButton(b)
    local info = itemInfo(b.bag, b.slot)
    if info and info.iconFileID then
        b.icon:SetTexture(info.iconFileID)
        b.icon:Show()
        b.icon:SetDesaturated(info.isLocked and true or false)
        b.fill(unpack(FILL))
        local n = info.stackCount
        b.count:SetText((num(n) and n > 1) and n or "")
        local q = info.quality
        local c = num(q) and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        local isQuest, starts = questInfo(b.bag, b.slot)
        if isQuest then b.ring(1.0, 0.80, 0.20, 1)
        elseif c then b.ring(c.r, c.g, c.b, 1) else b.ring(T.border[1], T.border[2], T.border[3], 1) end
        b.bang:SetShown(starts)
        b.junk:SetShown(q == 0 and not info.hasNoValue and not starts)
        local link = info.hyperlink
        local lvl = link and not secret(link) and isGear(link) and itemLevel(link)
        b.ilvl:SetText(lvl and string.format("%d", lvl) or "")
        local up = lvl and ns.IsUpgrade and ns.IsUpgrade(link) or false
        b.up:SetShown(up); b.upBack:SetShown(up)
        b.glow:SetShown(C_NewItems and call(C_NewItems.IsNewItem, b.bag, b.slot) == true or false)
        local m = matches(info)
        b.icon:SetAlpha(m and 1 or 0.2)
        b.over:SetAlpha(m and 1 or 0.3)
    else
        b.icon:SetTexture(nil)
        b.icon:Hide()
        b.fill(unpack(EMPTY))
        b.count:SetText("")
        b.ring(T.border[1] * 0.8, T.border[2] * 0.8, T.border[3] * 0.8, 1)
        b.junk:Hide()
        b.bang:Hide()
        b.ilvl:SetText("")
        b.up:Hide(); b.upBack:Hide()
        b.glow:Hide()
    end
    local start, dur, enable = call(CC.GetContainerItemCooldown or _G.GetContainerItemCooldown, b.bag, b.slot)
    if info and num(start) and num(dur) and dur > 0 and enable ~= 0 and enable ~= false then
        b.cd:SetCooldown(start, dur)
    else
        b.cd:Clear()
    end
end

-- ── Layout ────────────────────────────────────────────────────────────────
-- Place a bag's tiles in a grid inside `frame`, starting at tile index i.
local function placeBag(frame, bag, cols, top, i)
    holderFor(bag)
    local n = numSlots(bag)
    for slot = 1, n do
        local b = buttons[bag][slot] or newButton(bag, slot)
        local row, col = math.floor(i / cols), i % cols
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * (TILE + GAP), -(top + row * (TILE + GAP)))
        b:Show()
        i = i + 1
    end
    for slot = n + 1, #buttons[bag] do buttons[bag][slot]:Hide() end
    return i
end

local function gridWidth(cols) return PAD * 2 + cols * TILE + (cols - 1) * GAP end
local function gridHeight(rows) return rows * (TILE + GAP) - GAP end

local function layoutCombined()
    local cols = B.db.cols
    local i, keysAt = 0, nil
    local bags = shownBags()
    for _, bag in ipairs(bags) do
        if bag == KEYRING then
            if i % cols ~= 0 then i = i + (cols - i % cols) end
            keysAt = i
        end
        -- Keys start on a fresh row, one label-height lower.
        i = placeBag(win, bag, cols, HEADER + (bag == KEYRING and 22 or 0), i)
    end
    local rows = math.max(1, math.ceil(i / cols))
    win:SetSize(gridWidth(cols), HEADER + gridHeight(rows) + (keysAt and 22 or 0) + FOOTER)
    if keysAt then
        win.keysLabel:ClearAllPoints()
        win.keysLabel:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 2,
            -(HEADER + math.floor(keysAt / cols) * (TILE + GAP) + 4))
        win.keysLabel:Show()
    else
        win.keysLabel:Hide()
    end
end

local function layoutSeparate()
    local cols = B.db.sepCols
    win:SetSize(math.max(gridWidth(cols) * 2 - PAD, 360), HEADER + FOOTER - 8)
    -- Cards stack upward from the control card, right-aligned, wrapping to a
    -- new column on the left when the screen runs out of height.
    local maxH = UIParent:GetHeight() - 40
    local anchor, colAnchor, used = win, win, win:GetHeight()
    for _, bag in ipairs(shownBags()) do
        local card = cards[bag]
        -- Empty bag slots get no card and take no space (they used to keep
        -- their spot in the stack, hidden, leaving a gap).
        if card and numSlots(bag) > 0 then
            local n = placeBag(card, bag, cols, CARD_HEADER, 0)
            local h = CARD_HEADER + gridHeight(math.max(1, math.ceil(n / cols))) + PAD
            card:SetSize(gridWidth(cols), h)
            card:ClearAllPoints()
            if used + h + 8 > maxH then
                card:SetPoint("BOTTOMRIGHT", colAnchor, "BOTTOMLEFT", -8, 0)
                colAnchor, used = card, h
            else
                card:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
                used = used + h + 8
            end
            anchor = card
            card.title:SetText(bagName(bag))
        end
    end
end

local function layout()
    if InCombatLockdown() then pending.layout = true; return end
    pending.layout = false
    if B.db.mode == "separate" then layoutSeparate() else layoutCombined() end
    -- Hide bags that are no longer listed (keyring toggled off, bag removed).
    local listed = {}
    for _, bag in ipairs(shownBags()) do listed[bag] = true end
    for bag, list in pairs(buttons) do
        if not listed[bag] then for _, b in pairs(list) do b:Hide() end end
    end
    if B.db.mode == "separate" and win:IsShown() then
        for bag, card in pairs(cards) do setCard(card, (listed[bag] and numSlots(bag) > 0) and true or false) end
    end
end

-- ── Footer / refresh ──────────────────────────────────────────────────────
local function moneyText(c)
    if not num(c) then return "" end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then table.insert(parts, string.format("%s|cffe6c25a g|r", BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g)) end
    if g > 0 or s > 0 then table.insert(parts, string.format("%d|cffb8bcc6 s|r", s)) end
    table.insert(parts, string.format("%d|cffc98a52 c|r", cp))
    return table.concat(parts, "  ")
end

local function updateFooter()
    local free, total = 0, 0
    for _, bag in ipairs(bagList()) do
        total = total + numSlots(bag)
        local f = call(CC.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots, bag)
        if num(f) then free = free + f end
    end
    win.shell:SetSubtitle(string.format("%d of %d slots free", free, total))
    win.shell:SetChip(free <= 2 and (free == 0 and "Full" or "Almost full") or nil, { 0.95, 0.45, 0.40 })
    win.money:SetText(moneyText(GetMoney()))
    for _, t in ipairs(win.bagTiles) do
        local tex = GetInventoryItemTexture("player", t.inv)
        t.icon:SetTexture(tex or t.empty)
        t.icon:SetDesaturated(not tex)
        t.icon:SetAlpha(tex and 1 or 0.35)
    end
end

function B:Refresh()
    if not win or not win:IsShown() then return end
    if pending.layout and not InCombatLockdown() then layout() end
    for _, list in pairs(buttons) do
        for _, b in pairs(list) do if b:IsShown() then pcall(updateButton, b) end end
    end
    pcall(updateFooter)
end

-- Footer bag slots: the equipped bags (drag bags in and out).
local function makeBagTile(parent, index)
    local inv = call(CC.ContainerIDToInventoryID or _G.ContainerIDToInventoryID, index)
    if not inv then return end
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(24, 24)
    t.inv = inv
    t.empty = select(2, call(GetInventorySlotInfo, "Bag" .. (index - 1) .. "Slot"))
    ns.RoundedRect(t, -8, 0, 6, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(t, -7, 1, 5, unpack(FILL))
    local mask = t:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 2, -2); mask:SetPoint("BOTTOMRIGHT", -2, 2)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetAllPoints(mask)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.icon:AddMaskTexture(mask)
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(mask); hl:SetColorTexture(1, 1, 1, 0.12); hl:AddMaskTexture(mask)
    t:RegisterForClicks("LeftButtonUp")
    t:RegisterForDrag("LeftButton")
    local function swap()
        if CursorHasItem() then call(PutItemInBag, inv) else call(PickupBagFromSlot, inv) end
    end
    t:SetScript("OnClick", swap)
    t:SetScript("OnDragStart", function() call(PickupBagFromSlot, inv) end)
    t:SetScript("OnReceiveDrag", swap)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not GameTooltip:SetInventoryItem("player", inv) then GameTooltip:SetText(BAGSLOT or "Bag slot") end
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return t
end

-- ── Build ─────────────────────────────────────────────────────────────────
local function build()
    win = newCard("MinimalUIBags")
    win:SetMovable(true)
    local pos = B.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 130) end
    table.insert(UISpecialFrames, "MinimalUIBags")

    win.shell = ns:CreateShell(win, { onClose = function() B:Close() end })
    win.shell:SetTitle("Bags")
    win.shell:SetIcon("Interface/Icons/INV_Misc_Bag_08")
    win.shell:SetRing({ 0.80, 0.62, 0.38 })
    local band = win.shell.band

    -- Search: rounded field with a placeholder (bottom-right of the band).
    local box = CreateFrame("EditBox", nil, win)
    box:SetAutoFocus(false)
    box:SetSize(130, 22)
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
        B.search = t:lower()
        B:Refresh()
    end)
    box:SetScript("OnEditFocusGained", function() hint:Hide() end)
    box:SetScript("OnEditFocusLost", function(self) hint:SetShown((self:GetText() or "") == "") end)
    win.search = box

    local sort
    if CC.SortBags or _G.SortBags then
        sort = pill(win, "Sort", function() call(CC.SortBags or _G.SortBags) end)
        sort:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 14)
    end
    local keys
    if numSlots(KEYRING) > 0 then
        keys = pill(win, "Keys", function(self)
            if InCombatLockdown() then return end
            B.db.showKeys = not B.db.showKeys
            self.on = B.db.showKeys; self:Repaint()
            layout(); B:Refresh()
        end)
        keys.on = B.db.showKeys; keys:Repaint()
        if sort then keys:SetPoint("RIGHT", sort, "LEFT", -6, 0)
        else keys:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 14) end
    end
    local left = keys or sort
    if left then box:SetPoint("RIGHT", left, "LEFT", -8, 0)
    else box:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", -14, 14) end
    win.shell:Lift(box, sort, keys)
    win.keysLabel = text(win, 10, true, T.textDim)
    win.keysLabel:SetText("Keys")
    win.keysLabel:Hide()

    local line = win:CreateTexture(nil, "BORDER")
    line:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.8)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", PAD, FOOTER - 8)
    line:SetPoint("BOTTOMRIGHT", -PAD, FOOTER - 8)
    win.bagTiles = {}
    local x = PAD
    for i = 1, (_G.NUM_BAG_SLOTS or 4) do
        local t = makeBagTile(win, i)
        if t then
            t:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", x, 10)
            x = x + 28
            table.insert(win.bagTiles, t)
        end
    end
    win.money = text(win, 12, true)
    win.money:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, 16)

    if B.db.mode == "separate" then
        for _, bag in ipairs(bagList()) do cards[bag] = newCard() end
        if numSlots(KEYRING) > 0 then cards[KEYRING] = newCard() end
        for _, card in pairs(cards) do
            card.title = text(card, 11, true, T.textDim)
            card.title:SetPoint("TOPLEFT", PAD + 2, -11)
        end
    end

    local tg = _G.MinimalUIBagsToggle
    if tg and SecureHandlerSetFrameRef then
        SecureHandlerSetFrameRef(tg, "win", win)
        local n = 0
        for _, card in pairs(cards) do
            n = n + 1
            card.ref = n
            SecureHandlerSetFrameRef(tg, "card" .. n, card)
        end
        tg:SetAttribute("cards", n)
    end

    win:SetScript("OnShow", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN)
        B.shownAt = GetTime()
        layout()
        if B.db.mode == "separate" then
            for bag, card in pairs(cards) do
                local want = numSlots(bag) > 0 and (bag ~= KEYRING or B.db.showKeys)
                setCard(card, want and true or false)
            end
        end
        B:Refresh()
    end)
    win:SetScript("OnHide", function()
        call(PlaySound, SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE)
        win.search:ClearFocus()
        if not InCombatLockdown() then
            for _, card in pairs(cards) do card:Hide() end
        end
        if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end
    end)
end

-- Our windows hold secure tiles, so they can only open/close out of combat.
function B:CanToggle() return not InCombatLockdown() end

function B:Open()
    if not win then
        if InCombatLockdown() then return false end
        build()
    end
    if win:IsShown() then return true end
    if InCombatLockdown() then return false end
    win:Show()
    return true
end

function B:Close()
    if not win or not win:IsShown() then return end
    if InCombatLockdown() then pending.hide = true; return end
    win:Hide()
end

function B:Toggle()
    if win and win:IsShown() then self:Close() else self:Open() end
end

-- ── Taking over Blizzard's bags ───────────────────────────────────────────
-- A Blizzard inventory bag frame that opens is closed at once and ours opens
-- instead — unless ours can't open (combat), then Blizzard's stays. Toggle
-- keys: if ours was already open before this frame, the toggle closes it.
local function blizzardContainers()
    local list = {}
    local i = 1
    while _G["ContainerFrame" .. i] do table.insert(list, _G["ContainerFrame" .. i]); i = i + 1 end
    if _G.ContainerFrameCombinedBags then table.insert(list, ContainerFrameCombinedBags) end
    return list
end

-- Hiding Blizzard's frame makes Blizzard report "bag closed" (CloseBackpack
-- etc.), which must not close ours: those reports are ignored while we hide.
local hidingBlizzard = false
-- What a toggle should do depends on whether ours was open BEFORE the key
-- press; Blizzard's frame showing during the toggle records that.
local blizzShownAt, wasOpenBefore = nil, nil

local function hookContainer(f)
    if f.__muiHooked then return end
    f.__muiHooked = true
    f:HookScript("OnShow", function(self)
        if self ~= _G.ContainerFrameCombinedBags and not isInventoryBag(self:GetID()) then return end -- bank
        -- Only the first Blizzard bag frame of a key press says what ours was
        -- before (later ones would see ours already open).
        if blizzShownAt ~= GetTime() then
            blizzShownAt, wasOpenBefore = GetTime(), (win and win:IsShown()) or false
        end
        if B:Open() then
            hidingBlizzard = true
            self:Hide()
            hidingBlizzard = false
        end
    end)
end

local function openedThisFrame() return B.shownAt == GetTime() end

local function toggleHook()
    if blizzShownAt == GetTime() then
        -- Blizzard opened its bags for this key press: close ours if it was
        -- already open, otherwise it just opened (keep it).
        if wasOpenBefore then B:Close() end
        blizzShownAt = nil
        return
    end
    if not win or not win:IsShown() then B:Open()
    elseif not openedThisFrame() then B:Close() end
end

-- Vendor or bank open: right-click sells / deposits instead of using
-- (see newButton). kind = "sell" | "bank" | "mail" | nil.
function B:SetInteract(kind)
    if InCombatLockdown() then return end
    self.interact = kind
    self.sellMode = kind == "sell"
    local on = kind ~= nil
    for bag, list in pairs(buttons) do
        if bag >= 0 then
            for _, b in pairs(list) do
                if on then b:SetAttribute("*type2", nil) else b:SetAttribute("*type2", "item") end
            end
        end
    end
end

-- While a spell is waiting for an item to be clicked, a left click on a
-- tile uses the item (securely), which is what gives it to the spell.
-- Normally left click picks the item up, and a plain pickup ignores the
-- spell (Feed Pet put the food on the cursor). Out of combat only; it is
-- cleared as combat starts (Feed Pet can't be cast in combat anyway).
function B:SetTargeting(on)
    on = on and true or false
    if self.targeting == on or InCombatLockdown() then return end
    self.targeting = on
    for bag, list in pairs(buttons) do
        if bag >= 0 then
            for _, b in pairs(list) do b:SetAttribute("type1", on and "item" or nil) end
        end
    end
end

local FEED_PET = 6991
function ns.IsFeedingPet()
    local f = (C_Spell and C_Spell.IsCurrentSpell) or _G.IsCurrentSpell
    if not f then return false end
    local ok, on = pcall(f, FEED_PET)
    return ok and on == true
end

function B:OnInit(db)
    self.db = db
    local aim = CreateFrame("Frame")
    for _, e in ipairs({ "CURRENT_SPELL_CAST_CHANGED", "CURSOR_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        pcall(aim.RegisterEvent, aim, e)
    end
    local queued = false
    aim:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_DISABLED" then B:SetTargeting(false) return end
        if queued then return end
        queued = true
        C_Timer.After(0, function()
            queued = false
            local ok, want = pcall(function() return SpellIsTargeting() and SpellCanTargetItem() end)
            want = ok and want and true or false
            B:SetTargeting(want)
            if want and ns.IsFeedingPet() and not InCombatLockdown() then B:Open() end
        end)
    end)
    db.cols, db.sepCols, db.mode = db.cols or 10, db.sepCols or 4, db.mode or "combined"
    for _, f in ipairs(blizzardContainers()) do hookContainer(f) end
    for _, fn in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
        if _G[fn] then hooksecurefunc(fn, toggleHook) end
    end
    for _, fn in ipairs({ "OpenAllBags", "OpenBackpack", "OpenBag" }) do
        if _G[fn] then hooksecurefunc(fn, function() B:Open() end) end
    end
    for _, fn in ipairs({ "CloseAllBags", "CloseBackpack" }) do
        if _G[fn] then
            hooksecurefunc(fn, function()
                if not hidingBlizzard and not openedThisFrame() then B:Close() end
            end)
        end
    end
    local vendor = CreateFrame("Frame")
    vendor:RegisterEvent("MERCHANT_SHOW")
    vendor:RegisterEvent("MERCHANT_CLOSED")
    vendor:SetScript("OnEvent", function(_, e) B:SetInteract(e == "MERCHANT_SHOW" and "sell" or nil) end)

    -- Bag keys: whatever you've bound to Open all bags, Toggle backpack or a
    -- single bag clicks our own toggle (Blizzard's routing for those differs
    -- per binding). In combat ours can't open, so Blizzard's bags open.
    -- A secure handler: in combat its snippet shows / hides our (protected)
    -- windows, which ordinary code may not. Out of combat the snippet does
    -- nothing and the normal toggle below runs.
    local toggle = CreateFrame("Button", "MinimalUIBagsToggle", UIParent, "SecureHandlerClickTemplate")
    toggle:SetAttribute("_onclick", [[
        if not PlayerInCombat() then return end
        local w = self:GetFrameRef("win")
        if not w then return end
        local show = not w:IsShown()
        if show then w:Show() else w:Hide() end
        for i = 1, (self:GetAttribute("cards") or 0) do
            -- Only cards that were showing (they hold item tiles, so they
            -- can be shown / hidden here); the others are hidden already.
            if self:GetAttribute("cardon" .. i) then
                local c = self:GetFrameRef("card" .. i)
                if c then
                    if show then c:Show() else c:Hide() end
                end
            end
        end
    ]])
    toggle:HookScript("OnClick", function()
        if InCombatLockdown() then
            -- Ours was never built: fall back to Blizzard's bags.
            if not win and _G.ToggleAllBags then ToggleAllBags() end
            return
        end
        B:Toggle()
    end)
    local owner = CreateFrame("Frame")
    local function bindKeys()
        if InCombatLockdown() then owner.pending = true; return end
        owner.pending = false
        ClearOverrideBindings(owner)
        local actions = { "OPENALLBAGS", "TOGGLEBACKPACK", "TOGGLEBAG1", "TOGGLEBAG2", "TOGGLEBAG3",
                          "TOGGLEBAG4", "TOGGLEBAG5", "TOGGLEREAGENTBAG", "TOGGLEKEYRING" }
        for _, action in ipairs(actions) do
            local keys = { GetBindingKey(action) }
            for _, key in ipairs(keys) do
                if key then SetOverrideBindingClick(owner, false, key, "MinimalUIBagsToggle") end
            end
        end
    end
    owner:RegisterEvent("PLAYER_ENTERING_WORLD")
    owner:RegisterEvent("UPDATE_BINDINGS")
    owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    owner:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_ENABLED" and not owner.pending then return end
        bindKeys()
    end)

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
                         "PLAYER_MONEY", "BAG_NEW_ITEMS_UPDATED", "BAG_CONTAINER_UPDATE",
                         "PLAYER_REGEN_ENABLED", "UNIT_INVENTORY_CHANGED", "GET_ITEM_INFO_RECEIVED",
                         "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local dirty, relayout, acc = false, false, 0
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and pending.hide then
            pending.hide = false
            if win then win:Hide() end
            return
        end
        if event == "BAG_CONTAINER_UPDATE" or event == "UNIT_INVENTORY_CHANGED" or event == "BAG_UPDATE" then
            relayout = true
        end
        if event == "PLAYER_REGEN_ENABLED" and pending.layout then relayout = true end
        if not win or not win:IsShown() then return end
        dirty = true
    end)
    ev:SetScript("OnUpdate", function(_, dt)
        if not dirty then return end
        acc = acc + dt
        if acc < 0.08 then return end
        acc, dirty = 0, false
        if relayout then relayout = false; layout() end
        B:Refresh()
    end)
end

-- Panel / slash: switch layout (applies on reload: secure tiles can't move
-- between windows once made).
function B:SetMode(mode)
    if self.db then self.db.mode = mode end
end

ns.commands.bags = function(rest)
    if rest == "combined" or rest == "separate" then
        B:SetMode(rest)
        return ns:Print("Bags: " .. rest .. " layout after /reload.")
    end
    if B.db then B:Toggle() end
end
