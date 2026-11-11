local _, ns = ...
local T = ns.Theme

-- Professions: Meniscus's crafting window, replacing the look of Blizzard's
-- professions frame (which stays open but invisible; this drives the same
-- C_TradeSkillUI calls).
--
--   header   shared band: profession icon ring, name, "N recipes · M
--            craftable" line, skill chip; search + Have materials / Skill-ups
--   list     recipes grouped by category (click a heading to fold it); a
--            dot in the skill-up color, craftable count on the right
--   detail   the selected recipe: icon (tooltip), skill-up odds, tools,
--            cooldown, description, reagent tiles (have / need)
--   footer   Close bottom-left; quantity stepper, Create all (N), Create
-- /men prof blizz   use Blizzard's window instead (reloads); again to undo.

local P = ns:NewModule("Professions", { enabled = true, haveMats = false, skillUps = false, collapsed = {} })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local W, LIST_W = 760, 300
local ROW_H, ROWS = 30, 13
local LIST_TOP = (ns.SHELL_H or 92) + 14
local LIST_H = ROWS * ROW_H
local FOOTER_H = 52
local H = LIST_TOP + LIST_H + 12 + FOOTER_H
local DETAIL_X = 18 + LIST_W + 16
local DETAIL_W = W - DETAIL_X - 18
local TILES = 10
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local CARD = { 0.10, 0.10, 0.115, 1 }
local CARD_HOVER = { 0.13, 0.13, 0.15, 1 }
local CARD_SEL = { 0.15, 0.15, 0.18, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local GREEN = { 0.45, 0.85, 0.50, 1 }
local RED = { 0.95, 0.42, 0.40, 1 }

-- Enum.TradeskillRelativeDifficulty: 0 optimal, 1 medium, 2 easy, 3 trivial.
local DIFF = {
    [0] = { c = { 1.00, 0.56, 0.25 }, label = "Skill-up" },
    [1] = { c = { 1.00, 0.86, 0.30 }, label = "Likely skill-up" },
    [2] = { c = { 0.42, 0.80, 0.46 }, label = "Unlikely skill-up" },
    [3] = { c = { 0.50, 0.50, 0.54 }, label = "No skill-up" },
}

local TU = _G.C_TradeSkillUI or {}

local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not secret(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local PILL_OPTS = { h = 24, ring = true, pad = 26, minW = 54 }
local PILL_PRIMARY = { h = 24, ring = true, pad = 26, minW = 54, primary = true }
local function pill(parent, label, onClick, primary)
    return ns.Pill(parent, label, onClick, primary and PILL_PRIMARY or PILL_OPTS)
end

local function iconBox(parent, size, radius)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(size, size)
    ns.RoundedRect(box, -8, 0, radius, T.border[1], T.border[2], T.border[3], 1)
    local mask = box:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 1, -1); mask:SetPoint("BOTTOMRIGHT", -1, 1)
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetAllPoints(mask)
    box.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.icon:AddMaskTexture(mask)
    return box
end

-- ── Data ──────────────────────────────────────────────────────────────────
local function profInfo()
    local info = call(TU.GetChildProfessionInfo)
    if type(info) ~= "table" or not str(info.professionName) then info = call(TU.GetBaseProfessionInfo) end
    return type(info) == "table" and info or {}
end

local function profIcon(info)
    local tex = num(info.professionID) and call(TU.GetTradeSkillTexture, info.professionID)
    if tex then return tex end
    if _G.GetProfessions then
        local list = { call(GetProfessions) }
        for i = 1, 6 do
            local idx = list[i]
            if idx then
                local name, icon = call(GetProfessionInfo, idx)
                if name and (name == info.professionName or name == info.parentProfessionName) then return icon end
            end
        end
    end
    return "Interface/Icons/INV_Misc_Gear_01"
end

local catCache = {}
local function catName(id)
    if not num(id) then return "Other" end
    if catCache[id] == nil then
        local c = call(TU.GetCategoryInfo, id)
        catCache[id] = (type(c) == "table" and str(c.name)) or false
    end
    return catCache[id] or "Other"
end

-- Bag counts, looked up once per item per refresh (wiped in recipes()).
local counts = {}
local function itemCount(id)
    local c = counts[id]
    if c then return c end
    local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, id, false, false, true)
    c = (ok and num(n)) and n or 0
    counts[id] = c
    return c
end

local function itemNameIcon(id)
    local name = C_Item and C_Item.GetItemNameByID and call(C_Item.GetItemNameByID, id)
    local icon = C_Item and C_Item.GetItemIconByID and call(C_Item.GetItemIconByID, id)
    if not name and _G.GetItemInfo then
        local n, _, _, _, _, _, _, _, _, ic = call(GetItemInfo, id)
        name, icon = n, icon or ic
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID, id) end
    return name, icon
end

local craftableCount -- defined after reagents()

-- The recipe list is read from the client only when it can have changed
-- (opened, learned a recipe, skill changed): that read makes a table per
-- recipe. Bag changes and casts only recount what's craftable from it.
-- baseDirty: true = re-read; "maybe" = the client said the list updated
-- (it does after every craft), which only matters if the number of recipes
-- or the skill level (the difficulty colours) changed since the last read.
local base, baseDirty, baseAt, total = {}, true, 0, 0
local byId, baseSig = {}, nil
local function buildBase()
    local ids = call(TU.GetAllRecipeIDs)
    if type(ids) ~= "table" then wipe(base); total = 0; baseSig = nil return end
    local info = call(TU.GetChildProfessionInfo)
    local lvl = type(info) == "table" and num(info.skillLevel) and info.skillLevel or -1
    local sig = #ids .. ":" .. lvl
    if baseDirty == "maybe" and sig == baseSig and total > 0 then return end
    baseSig = sig
    wipe(base)
    total = 0
    for _, id in ipairs(ids) do
        local r = call(TU.GetRecipeInfo, id)
        if type(r) == "table" and r.learned and str(r.name) and not r.isDummyRecipe and not r.isRecraft then
            total = total + 1
            -- One entry per recipe, kept and updated in place.
            local e = byId[id]
            if not e then e = { id = id, n = 0 }; byId[id] = e end
            if e.name ~= r.name then e.name, e.lname = r.name, r.name:lower() end
            e.icon = r.icon
            e.diff = num(r.relativeDifficulty) and r.relativeDifficulty or 3
            e.cat = catName(r.categoryID)
            e.info = r
            base[total] = e
        end
    end
end

-- Best skill-ups first, then by name.
local function byDiffName(a, b)
    if a.diff ~= b.diff then return a.diff < b.diff end
    return a.name < b.name
end

local groups, order = {}, {}
local function recipes()
    if baseDirty then
        buildBase()
        baseDirty, baseAt = false, GetTime()
    end
    wipe(counts)
    for _, g in pairs(groups) do wipe(g) end
    wipe(order)
    local craftable = 0
    local q = P.search
    if q == "" then q = nil end
    for _, e in ipairs(base) do
        local n = craftableCount(e.id)
        e.n = n
        if n > 0 then craftable = craftable + 1 end
        if (not q or e.lname:find(q, 1, true))
                and (not P.db.haveMats or n > 0) and (not P.db.skillUps or e.diff < 3) then
            local g = groups[e.cat]
            if not g then g = {}; groups[e.cat] = g end
            if #g == 0 then order[#order + 1] = e.cat end
            g[#g + 1] = e
        end
    end
    -- The list and its header entries are reused from one refresh to the next.
    local list = P.__list or {}
    P.__list = list
    local heads = P.__heads or {}
    P.__heads = heads
    wipe(list)
    for ci, cat in ipairs(order) do
        local g = groups[cat]
        table.sort(g, byDiffName)
        local folded = P.db.collapsed[cat] and not q
        local h = heads[ci]
        if not h then h = { header = true }; heads[ci] = h end
        h.name, h.count, h.folded = cat, #g, folded
        list[#list + 1] = h
        if not folded then for _, e in ipairs(g) do list[#list + 1] = e end end
    end
    return list, total, craftable
end

-- What a recipe needs never changes, so its schematic (a large table from
-- the client) is read once and kept; only the "have" counts are refreshed.
local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
local schemCache = {}
local NO_SCHEM = { list = {} }
local function schematic(id)
    local c = schemCache[id]
    if c then return c end
    local s = call(TU.GetRecipeSchematic, id, false)
    if type(s) ~= "table" then return NO_SCHEM end -- not kept: try again next time
    c = { list = {}, quantityMin = s.quantityMin, quantityMax = s.quantityMax }
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local basic = slot.required or slot.reagentType == nil or (BASIC and slot.reagentType == BASIC)
        local first = slot.reagents and slot.reagents[1]
        if basic and first and first.itemID then
            -- Quality tiers are separate items; any of them counts.
            local ids = {}
            for _, rg in ipairs(slot.reagents) do if rg.itemID then ids[#ids + 1] = rg.itemID end end
            c.list[#c.list + 1] = { itemID = first.itemID, ids = ids,
                need = num(slot.quantityRequired) and slot.quantityRequired or 1, have = 0 }
        end
    end
    schemCache[id] = c
    return c
end

local function reagents(id)
    local c = schematic(id)
    for _, rg in ipairs(c.list) do
        local have = 0
        for _, iid in ipairs(rg.ids) do have = have + itemCount(iid) end
        rg.have = have
    end
    return c.list, c
end

-- How many you can make now. Forever leaves numAvailable at 0 (it showed
-- "0 craftable" with 31 / 3 reagents), so take the best of: the recipe's
-- own count, GetCraftableCount, and what the reagents in your bags allow.
function craftableCount(id, r)
    local n = (r and num(r.numAvailable)) and r.numAvailable or 0
    local api = call(TU.GetCraftableCount, id)
    if num(api) and api > n then n = api end
    if n > 0 then return n end
    local list = reagents(id)
    if #list == 0 then return 0 end
    local best
    for _, rg in ipairs(list) do
        local k = math.floor(rg.have / math.max(rg.need, 1))
        best = best and math.min(best, k) or k
    end
    return best or 0
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, rows, offset, data = nil, {}, 0, {}
local closing = false
local current -- selected list entry

local function crafting()
    local left = call(TU.GetRemainingRecasts)
    return (num(left) and left > 0) or call(TU.IsRecipeRepeating) == true, num(left) and left or 0
end

local function paintRow(r)
    local e = r.entry
    if not e or e.header then return end
    if current and current.id == e.id then
        r.ring(unpack(T.accent)); r.fill(unpack(CARD_SEL))
    elseif r.hover then
        r.ring(T.border[1] + 0.08, T.border[2] + 0.08, T.border[3] + 0.08, 1); r.fill(unpack(CARD_HOVER))
    else
        r.ring(T.border[1], T.border[2], T.border[3], 1); r.fill(unpack(CARD))
    end
end

local showDetail -- defined below

local function makeRow(i)
    local r = CreateFrame("Button", nil, win)
    r:SetSize(LIST_W, ROW_H - 4)
    r:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(LIST_TOP + (i - 1) * ROW_H))
    r.ring = ns.RoundedRect(r, -8, 0, 8, T.border[1], T.border[2], T.border[3], 1)
    r.fill = ns.RoundedRect(r, -7, 1, 7, unpack(CARD))
    r.box = iconBox(r, 20, 6)
    r.box:SetPoint("LEFT", 4, 0)
    r.dot = r:CreateTexture(nil, "OVERLAY")
    r.dot:SetTexture(CIRCLE)
    r.dot:SetSize(7, 7)
    r.dot:SetPoint("LEFT", r.box, "RIGHT", 8, 0)
    r.count = text(r, 10, true, GREEN)
    r.count:SetPoint("RIGHT", -10, 0)
    r.name = text(r, 11, true)
    r.name:SetPoint("LEFT", r.dot, "RIGHT", 7, 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.head = text(r, 11, true, T.textDim)
    r.head:SetPoint("LEFT", 6, 0)
    r.headCount = text(r, 10, false, T.textDim)
    r.headCount:SetPoint("RIGHT", -10, 0)
    r:SetScript("OnEnter", function(self) self.hover = true; paintRow(self) end)
    r:SetScript("OnLeave", function(self) self.hover = false; paintRow(self) end)
    r:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.header then
            P.db.collapsed[e.name] = not P.db.collapsed[e.name] or nil
            P:Refresh()
        else
            current = e
            P.selected = e.id
            P.qty = 1
            for _, o in ipairs(rows) do paintRow(o) end
            showDetail()
        end
    end)
    return r
end

local function fillRow(r, e)
    r.entry = e
    if not e then r:Hide(); return end
    r:Show()
    if e.header then
        r.ring(0, 0, 0, 0); r.fill(0, 0, 0, 0)
        r.box:Hide(); r.dot:Hide(); r.name:Hide(); r.count:Hide()
        r.head:SetText((e.folded and "+  " or "–  ") .. e.name)
        r.headCount:SetText(e.count)
        r.head:Show(); r.headCount:Show()
        return
    end
    r.head:Hide(); r.headCount:Hide()
    r.box:Show(); r.dot:Show(); r.name:Show(); r.count:Show()
    r.box.icon:SetTexture(e.icon)
    local d = DIFF[e.diff] or DIFF[3]
    r.dot:SetVertexColor(d.c[1], d.c[2], d.c[3], 1)
    r.name:SetText(e.name)
    -- Always white: the gray dot (and the detail panel) say "no skill-up";
    -- dimmed names read as "can't make this".
    r.name:SetTextColor(unpack(T.text))
    r.count:SetText(e.n > 0 and ("×" .. e.n) or "")
    paintRow(r)
end

local function updateThumb()
    local th = win.thumb
    local maxOff = math.max(0, #data - ROWS)
    if maxOff == 0 then th:Hide(); return end
    th:Show()
    local size = math.max(24, LIST_H * ROWS / #data)
    th:SetHeight(size)
    th:ClearAllPoints()
    th:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + LIST_W + 6, -(LIST_TOP + (LIST_H - size - 4) * offset / maxOff))
end

local function scroll(delta)
    offset = math.max(0, math.min(offset - delta * 3, math.max(0, #data - ROWS)))
    for i, r in ipairs(rows) do fillRow(r, data[i + offset]) end
    updateThumb()
end

-- ── Detail ────────────────────────────────────────────────────────────────
local function buildDetail()
    local d = CreateFrame("Frame", nil, win)
    d:SetPoint("TOPLEFT", win, "TOPLEFT", DETAIL_X, -LIST_TOP)
    d:SetSize(DETAIL_W, LIST_H - 4)
    ns.RoundedRect(d, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(d, -7, 1, 11, unpack(CARD))
    win.detail = d

    d.box = iconBox(d, 46, 10)
    d.box:SetPoint("TOPLEFT", 16, -16)
    d.box:EnableMouse(true)
    d.box:SetScript("OnEnter", function(self)
        if not current then return end
        ns.TipAnchor(self)
        local ok = pcall(GameTooltip.SetRecipeResultItem, GameTooltip, current.id)
        if not ok then
            local out = call(TU.GetRecipeOutputItemData, current.id)
            if type(out) == "table" and out.hyperlink then ok = pcall(GameTooltip.SetHyperlink, GameTooltip, out.hyperlink)
            elseif type(out) == "table" and out.itemID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, out.itemID) end
        end
        if not ok then GameTooltip:SetText(current.name) end
        GameTooltip:Show()
    end)
    d.box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.makes = text(d.box, 10, true)
    d.makes:SetPoint("BOTTOMRIGHT", -3, 3)

    d.name = text(d, 15, true)
    d.name:SetPoint("TOPLEFT", d.box, "TOPRIGHT", 12, -4)
    d.name:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    d.sub = text(d, 11, false, T.textDim)
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)
    d.sub:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    d.sub:SetJustifyH("LEFT")

    d.info = text(d, 11, false, T.textDim)
    d.info:SetWidth(DETAIL_W - 32)
    d.info:SetJustifyH("LEFT")
    d.info:SetSpacing(3)
    d.desc = text(d, 11, false, T.textDim)
    d.desc:SetWidth(DETAIL_W - 32)
    d.desc:SetJustifyH("LEFT")
    d.desc:SetSpacing(2)
    pcall(d.desc.SetMaxLines, d.desc, 4)
    d.section = text(d, 10, true, T.textDim)
    d.section:SetText("REAGENTS")

    local tw = math.floor((DETAIL_W - 32 - 8) / 2)
    d.tiles = {}
    for i = 1, TILES do
        local t = CreateFrame("Frame", nil, d)
        t:SetSize(tw, 38)
        t.ring = ns.RoundedRect(t, -8, 0, 9, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(t, -7, 1, 8, 0.075, 0.075, 0.085, 1)
        t.box = iconBox(t, 28, 7)
        t.box:SetPoint("LEFT", 5, 0)
        t.count = text(t, 11, true)
        t.count:SetPoint("RIGHT", -10, 0)
        t.name = text(t, 11, false)
        t.name:SetPoint("LEFT", t.box, "RIGHT", 8, 0)
        t.name:SetPoint("RIGHT", t.count, "LEFT", -6, 0)
        t.name:SetJustifyH("LEFT")
        t.name:SetWordWrap(false)
        t:EnableMouse(true)
        t:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            ns.TipAnchor(self)
            if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then GameTooltip:SetText(self.name:GetText() or "") end
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t:SetScript("OnMouseUp", function(self)
            -- Shift-click links the reagent, like everywhere else.
            if self.itemID and IsModifiedClick and IsModifiedClick("CHATLINK") then
                local _, link = call(GetItemInfo, self.itemID)
                if link then ChatEdit_InsertLink(link) end
            end
        end)
        t:Hide()
        d.tiles[i] = t
    end
    d.empty = text(d, 12, false, T.textDim)
    d.empty:SetPoint("CENTER")
end

local missingNames = false
local DETAIL_PARTS = { "box", "name", "sub", "info", "desc", "section" }
local RING_SHORT = { 0.42, 0.20, 0.20, 1 }
function showDetail()
    if not win or not win:IsShown() then return end
    local d = win.detail
    local e = current
    local linked = call(TU.IsTradeSkillLinked) or call(TU.IsTradeSkillGuild) or call(TU.IsNPCCrafting)
    if not e then
        for _, k in ipairs(DETAIL_PARTS) do d[k]:Hide() end
        for _, t in ipairs(d.tiles) do t:Hide() end
        d.empty:SetText(#data == 0 and "No recipes match." or "Pick a recipe.")
        d.empty:Show()
        win.create:SetEnabled(false); win.createAll:SetEnabled(false)
        win.minus:SetEnabled(false); win.plus:SetEnabled(false)
        return
    end
    d.empty:Hide()
    for _, k in ipairs(DETAIL_PARTS) do d[k]:Show() end
    -- Fresh info: counts change as you craft and loot.
    wipe(counts)
    local r = call(TU.GetRecipeInfo, e.id) or e.info
    local n = craftableCount(e.id, r)
    local diff = num(r.relativeDifficulty) and r.relativeDifficulty or e.diff
    local dd = DIFF[diff] or DIFF[3]

    d.box.icon:SetTexture(r.icon or e.icon)
    d.name:SetText(r.name or e.name)
    local ups = num(r.numSkillUps) and r.numSkillUps > 1 and diff == 0 and (" ×" .. r.numSkillUps) or ""
    d.sub:SetText(string.format("|cff%02x%02x%02x%s%s|r   ·   %s", math.floor(dd.c[1] * 255), math.floor(dd.c[2] * 255), math.floor(dd.c[3] * 255),
        dd.label, ups, catName(r.categoryID)))

    local list, s = reagents(e.id)
    local qmin, qmax = s.quantityMin, s.quantityMax
    if num(qmin) and num(qmax) and qmax > 1 then
        d.makes:SetText(qmin == qmax and qmin or (qmin .. "-" .. qmax))
    else
        d.makes:SetText("")
    end

    -- Tools / places, cooldown: one quiet line each.
    local lines = {}
    local req = call(TU.GetRecipeRequirements, e.id)
    if type(req) == "table" and #req > 0 then
        local parts = {}
        for _, q in ipairs(req) do
            if str(q.name) then table.insert(parts, (q.met and "|cff8fd19e" or "|cfff26b66") .. q.name .. "|r") end
        end
        if #parts > 0 then table.insert(lines, "Requires  " .. table.concat(parts, ", ")) end
    end
    local cd = call(TU.GetRecipeCooldown, e.id)
    if num(cd) and cd > 0 then
        table.insert(lines, "|cfff26b66Cooldown  " .. (SecondsToTime and SecondsToTime(cd) or (math.ceil(cd / 60) .. " min")) .. "|r")
    end
    d.info:SetText(table.concat(lines, "\n"))
    local y = -78
    d.info:ClearAllPoints()
    d.info:SetPoint("TOPLEFT", d, "TOPLEFT", 16, y)
    if #lines > 0 then y = y - d.info:GetStringHeight() - 10 end

    local desc = str(call(TU.GetRecipeDescription, e.id, {}))
    d.desc:SetText(desc or "")
    d.desc:ClearAllPoints()
    d.desc:SetPoint("TOPLEFT", d, "TOPLEFT", 16, y)
    if desc then y = y - d.desc:GetStringHeight() - 14 end

    d.section:ClearAllPoints()
    d.section:SetPoint("TOPLEFT", d, "TOPLEFT", 16, y)
    d.section:SetShown(#list > 0)
    y = y - 18
    missingNames = false
    for i, t in ipairs(d.tiles) do
        local rg = list[i]
        if rg then
            local name, icon = itemNameIcon(rg.itemID)
            if not name then missingNames = true end
            t.itemID = rg.itemID
            t.box.icon:SetTexture(icon or 134400)
            t.name:SetText(name or "…")
            local enough = rg.have >= rg.need
            t.count:SetText(rg.have .. " / " .. rg.need)
            t.count:SetTextColor(unpack(enough and GREEN or RED))
            t.name:SetTextColor(unpack(enough and T.text or T.textDim))
            t.ring(unpack(enough and T.border or RING_SHORT))
            t:ClearAllPoints()
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            t:SetPoint("TOPLEFT", d, "TOPLEFT", 16 + col * (t:GetWidth() + 8), y - row * 44)
            t:Show()
        else
            t.itemID = nil
            t:Hide()
        end
    end

    -- Footer: quantity, Create all, Create (or Stop while repeating).
    local busy, left = crafting()
    local can = not linked and n > 0
    P.qty = math.max(1, math.min(P.qty or 1, math.max(n, 1)))
    win.qty:SetText(P.qty)
    win.minus:SetEnabled(can and P.qty > 1)
    win.plus:SetEnabled(can and P.qty < n)
    win.createAll:SetLabel(n > 0 and string.format("Create all (%d)", n) or "Create all")
    win.createAll:SetEnabled(can and not busy)
    if busy then
        win.create:SetLabel("Stop", 84)
        win.create:SetEnabled(true)
        win.status:SetText(left > 0 and string.format("Crafting…  %d left", left) or "Crafting…")
    else
        win.create:SetLabel(CREATE_PROFESSION or "Create", 84)
        win.create:SetEnabled(can)
        win.status:SetText(linked and "Viewing only" or "")
    end
end

local function craft(count)
    if not current then return end
    local busy = crafting()
    if busy then call(TU.StopRecipeRepeat); return end
    call(TU.CraftRecipe, current.id, count)
    C_Timer.After(0.2, showDetail)
end

-- ── Refresh ───────────────────────────────────────────────────────────────
local function refresh()
    local total, craftable
    data, total, craftable = recipes()
    -- Keep the selection when it's still listed; otherwise the first recipe.
    current = nil
    for _, e in ipairs(data) do
        if not e.header and e.id == P.selected then current = e; break end
    end
    if not current then
        for _, e in ipairs(data) do if not e.header then current = e; P.selected = e.id; break end end
    end
    offset = math.min(offset, math.max(0, #data - ROWS))
    scroll(0)

    local info = profInfo()
    local sh = win.shell
    sh:SetTitle(str(info.professionName) or str(call(TU.GetTradeSkillDisplayName, info.professionID)) or (TRADE_SKILLS or "Professions"))
    sh:SetIcon(profIcon(info))
    if num(info.skillLevel) and num(info.maxSkillLevel) and info.maxSkillLevel > 0 then
        local done = info.skillLevel >= info.maxSkillLevel
        sh:SetChip(info.skillLevel .. " / " .. info.maxSkillLevel, done and GREEN or T.accent)
    else
        sh:SetChip(nil)
    end
    sh:SetSubtitle(string.format("%d recipes   ·   %d craftable now", total, craftable))
    win.haveMats.on = P.db.haveMats; win.haveMats:Repaint()
    win.skillUps.on = P.db.skillUps; win.skillUps:Repaint()
    showDetail()
end

function P:Refresh()
    if not win or not win:IsShown() then return end
    ns.Timed("professions", refresh)
end

local queued, detailQueued = false, false
local function runQueued() queued = false; P:Refresh() end
local function runDetail()
    detailQueued = false
    if not queued then showDetail() end
end
-- structural: the recipe list itself may have changed (not just counts).
-- The client can fire list updates in bursts, so the list is re-read at
-- most once a second.
function P:QueueRefresh(structural)
    if structural == true then baseDirty = true
    elseif structural and not baseDirty then baseDirty = "maybe" end
    if queued or not win or not win:IsShown() then return end
    queued = true
    local wait = 0.15
    if baseDirty then wait = math.max(wait, 1 - (GetTime() - baseAt)) end
    C_Timer.After(wait, runQueued)
end
-- Casting starts/stops only change the footer (Create / Stop, "N left").
function P:QueueDetail()
    if detailQueued or not win or not win:IsShown() then return end
    detailQueued = true
    C_Timer.After(0.1, runDetail)
end
function P:ResetData()
    wipe(schemCache); wipe(catCache); wipe(base); wipe(byId)
    baseDirty, baseAt, baseSig = true, 0, nil
end

-- ── Build ─────────────────────────────────────────────────────────────────
local function build()
    win = CreateFrame("Frame", "MinimalUIProfessions", UIParent)
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
        P.db.pos = { p, rp, x, y }
    end)
    local pos = P.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIProfessions")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win)
    win.shell:SetRing(T.accent)
    win.shell:SetSubtitleWidth(300)

    -- Header controls: search, Have materials, Skill-ups.
    win.skillUps = pill(win, "Skill-ups", function()
        P.db.skillUps = not P.db.skillUps; offset = 0; P:Refresh()
    end)
    win.skillUps:SetPoint("BOTTOMRIGHT", win.shell.band, "BOTTOMRIGHT", -14, 14)
    win.haveMats = pill(win, "Have materials", function()
        P.db.haveMats = not P.db.haveMats; offset = 0; P:Refresh()
    end)
    win.haveMats:SetPoint("RIGHT", win.skillUps, "LEFT", -6, 0)
    local box = CreateFrame("EditBox", nil, win)
    box:SetAutoFocus(false)
    box:SetSize(170, 24)
    box:SetPoint("RIGHT", win.haveMats, "LEFT", -10, 0)
    box:SetTextInsets(10, 10, 0, 0)
    ns:SetFont(box, 11, "")
    box:SetTextColor(unpack(T.text))
    local ring = ns.RoundedRect(box, -8, 0, 12, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(box, -7, 1, 11, 0.05, 0.05, 0.06, 1)
    local hint = text(box, 11, false, T.textDim)
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText("Search recipes")
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        hint:SetShown(t == "" and not self:HasFocus())
        P.search = t:lower()
        offset = 0
        P:QueueRefresh()
    end)
    box:SetScript("OnEditFocusGained", function() hint:Hide(); ring(unpack(T.accent)) end)
    box:SetScript("OnEditFocusLost", function(self)
        hint:SetShown((self:GetText() or "") == "")
        ring(T.border[1], T.border[2], T.border[3], 1)
    end)
    win.search = box
    win.shell:Lift(box, win.haveMats, win.skillUps)

    for i = 1, ROWS do rows[i] = makeRow(i) end
    win.thumb = win:CreateTexture(nil, "OVERLAY")
    win.thumb:SetWidth(3)
    win.thumb:SetColorTexture(0.32, 0.32, 0.36, 1)
    local wheel = CreateFrame("Frame", nil, win)
    wheel:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -LIST_TOP)
    wheel:SetSize(LIST_W + 10, LIST_H)
    wheel:EnableMouseWheel(true)
    wheel:SetScript("OnMouseWheel", function(_, dl) scroll(dl) end)

    buildDetail()

    -- Footer band.
    win.footer = ns:CreateFooter(win, FOOTER_H)
    local f = win.footer
    win.close = pill(f, CLOSE or "Close", function() win:Hide() end)
    win.close:SetPoint("LEFT", f, "LEFT", 14, 0)
    win.create = pill(f, CREATE_PROFESSION or "Create", function() craft(P.qty or 1) end, true)
    win.create:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    win.createAll = pill(f, "Create all", function()
        local r = current and call(TU.GetRecipeInfo, current.id)
        local n = r and craftableCount(current.id, r) or 0
        if n > 0 then craft(n) end
    end)
    win.createAll:SetPoint("RIGHT", win.create, "LEFT", -8, 0)
    win.plus = pill(f, "+", function() P.qty = (P.qty or 1) + 1; showDetail() end)
    win.plus:SetLabel("+", 26)
    win.plus:SetPoint("RIGHT", win.createAll, "LEFT", -14, 0)
    win.qty = text(f, 12, true)
    win.qty:SetWidth(30)
    win.qty:SetPoint("RIGHT", win.plus, "LEFT", -2, 0)
    win.minus = pill(f, "–", function() P.qty = math.max(1, (P.qty or 1) - 1); showDetail() end)
    win.minus:SetLabel("–", 26)
    win.minus:SetPoint("RIGHT", win.qty, "LEFT", -2, 0)
    win.status = text(f, 11, false, T.textDim)
    win.status:SetPoint("LEFT", win.close, "RIGHT", 14, 0)

    win:SetScript("OnHide", function()
        GameTooltip:Hide()
        if not closing then call(TU.CloseTradeSkill) end
    end)
end

-- ── Blizzard's frame: open but invisible ─────────────────────────────────
-- Only while a profession is open (TRADE_SKILL_SHOW .. CLOSE). The same
-- frame is also Forever's professions book (K, ToggleProfessionsBook) with
-- no profession open: that stays Blizzard's and visible.
local BLIZZ = { "ProfessionsFrame", "TradeSkillFrame" }
local tradeOpen = false
local function apply(f)
    if not f then return end
    if tradeOpen and P.db.enabled ~= false then
        f:SetAlpha(0); f:SetScale(0.001); f:EnableMouse(false)
        f.__muiHidden = true
    elseif f.__muiHidden then
        f.__muiHidden = nil
        f:SetAlpha(1); f:SetScale(1); f:EnableMouse(true)
    end
end
local function ghost(f)
    if not f or f.__muiGhost then return end
    f.__muiGhost = true
    -- Blizzard can show the frame before our TRADE_SKILL_SHOW handler runs,
    -- so tradeOpen may still be false here: hide it now regardless, and
    -- give it back next frame if no profession turned out to be open.
    f:HookScript("OnShow", function(self)
        if P.db.enabled == false then return end
        self:SetAlpha(0); self:SetScale(0.001); self:EnableMouse(false)
        self.__muiHidden = true
        C_Timer.After(0, function() apply(self) end)
    end)
    if f:IsShown() then apply(f) end
end
local function ghostAll()
    for _, n in ipairs(BLIZZ) do
        local f = _G[n]
        ghost(f)
        if f then apply(f) end
    end
end

local function open()
    if not win then build() end
    ghostAll()
    if not win:IsShown() then
        offset = 0
        win:Show()
    end
    baseDirty = true
    P:Refresh()
end

local function close()
    if win and win:IsShown() then
        closing = true
        win:Hide()
        closing = false
    end
end

-- Close a trade skill that Blizzard opened on its own (K reopening the last
-- profession) and put its frame away, without flashing our crafting window.
function ns.ProfSuppressTrade()
    call(TU.CloseTradeSkill)
    tradeOpen = false
    ns.profTradeOpen = false
    close()
    for _, n in ipairs(BLIZZ) do
        local f = _G[n]
        if f and f:IsShown() then
            if HideUIPanel then HideUIPanel(f) else f:Hide() end
        end
        apply(f)
    end
end

ns.commands.prof = function(rest)
    if rest == "blizz" then
        local db = ns.db.modules.Professions
        db.enabled = db.enabled == false
        ns:Print(db.enabled and "Professions: Meniscus window (reloading)." or "Professions: Blizzard's window (reloading).")
        ReloadUI()
    elseif win then
        if win:IsShown() then win:Hide() else open() end
    end
end

function P:OnInit(db)
    self.db = db
    db.collapsed = db.collapsed or {}
    if MinimalUIDB then MinimalUIDB.proftrace = nil end -- old debug trail
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
                         "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED", "BAG_UPDATE_DELAYED",
                         "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED", "TRADE_SKILL_ITEM_CRAFTED_RESULT",
                         "ADDON_LOADED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
                         "UNIT_SPELLCAST_INTERRUPTED" }) do
        pcall(ev.RegisterUnitEvent, ev, e, "player")
    end
    ev:SetScript("OnEvent", function(_, e, arg)
        if e == "ADDON_LOADED" then
            if arg == "Blizzard_Professions" or arg == "Blizzard_TradeSkillUI" then ghostAll() end
        elseif e == "TRADE_SKILL_SHOW" then
            -- Blizzard shows its frame on this event too; ghost it next frame.
            tradeOpen = true
            ns.profTradeOpen = true
            ns.profTradeShownAt = GetTime()
            P:ResetData()
            -- K (ToggleProfessionsBook) makes Blizzard reopen the last
            -- profession. If this show came from a K press, it's that
            -- auto-reopen, not the player opening a profession: undo it.
            local kAt = ns.profBookKeyAt
            if kAt and GetTime() - kAt < 0.5 then
                ns.ProfSuppressTrade()
                return
            end
            C_Timer.After(0, function() if tradeOpen then open() end end)
        elseif e == "TRADE_SKILL_CLOSE" then
            tradeOpen = false
            ns.profTradeOpen = false
            ns.profTradeClosedAt = GetTime()
            close()
            ghostAll() -- un-hide, in case Blizzard's book stays up
        elseif e == "GET_ITEM_INFO_RECEIVED" then
            if missingNames then P:QueueDetail() end
        elseif e == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
            P:ResetData()
            P:QueueRefresh(true)
        elseif e == "NEW_RECIPE_LEARNED" or e == "SKILL_LINES_CHANGED" then
            P:QueueRefresh(true)
        elseif e == "TRADE_SKILL_LIST_UPDATE" then
            P:QueueRefresh("maybe")
        elseif e == "BAG_UPDATE_DELAYED" or e == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
            P:QueueRefresh()
        else
            P:QueueDetail() -- spell cast start / stop
        end
    end)
end
