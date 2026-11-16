local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Tooltips: dark rounded card with a hairline border (item tooltips tint the
-- border by quality), class/reaction-colored unit names, theme font, and the
-- health bar as a thin flat line inside the card's bottom edge.
-- Blizzard's NineSlice frame stays but is invisible.

local TT = ns:NewModule("Tooltip", { enabled = true })

local TIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
               "EmbeddedItemTooltip", "WorldMapTooltip", "QuestScrollFrameTooltip" }

local function zero(obj)
    if not obj or obj.__muiZero then return end
    obj.__muiZero = true
    obj:SetAlpha(0)
    hooksecurefunc(obj, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
end

local function style(tip)
    if not tip or tip.__mui then return end
    tip.__mui = true
    zero(tip.NineSlice)
    -- Some tooltips draw a plain backdrop instead of a NineSlice.
    if tip.SetBackdrop and not tip.NineSlice then pcall(tip.SetBackdrop, tip, nil) end
    tip.__muiBorder = ns.RoundedRect(tip, -8, 0, 8, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(tip, -7, 1, 7, 0.06, 0.06, 0.07, 0.96)
end

local function setBorder(tip, r, g, b)
    if tip.__muiBorder then tip.__muiBorder(r, g, b, 1) end
end

local function styleFonts()
    for _, name in ipairs({ "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }) do
        local fo = _G[name]
        if fo and fo.GetFont then
            local _, size, flags = fo:GetFont()
            pcall(fo.SetFont, fo, T.font, size or 12, flags or "")
        end
    end
end

local function styleHealthBar()
    local bar = _G.GameTooltipStatusBar
    if not bar or bar.__mui then return end
    bar.__mui = true
    bar:SetStatusBarTexture(T.bar)
    bar:SetHeight(3)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", 8, 4)
    bar:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -8, 4)
    -- Keep it inside the card: Blizzard re-anchors it below the tooltip.
    hooksecurefunc(bar, "SetPoint", function(self)
        if self.__muiAnchoring then return end
        self.__muiAnchoring = true
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", 8, 4)
        self:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -8, 4)
        self.__muiAnchoring = false
    end)
    for _, r in ipairs({ bar:GetRegions() }) do
        if r ~= bar:GetStatusBarTexture() and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    if bar.Border then zero(bar.Border) end
end

local function unitColor(unit)
    if UnitIsPlayer(unit) then
        local ok, _, token = pcall(UnitClass, unit)
        if ok and token and not issecretvalue(token) and RAID_CLASS_COLORS[token] then
            local c = RAID_CLASS_COLORS[token]
            return c.r, c.g, c.b
        end
    end
    local reaction = UnitReaction(unit, "player")
    if reaction and not issecretvalue(reaction) then
        if reaction <= 2 then return 0.85, 0.30, 0.30 end
        if reaction <= 4 then return 0.92, 0.78, 0.32 end
        return 0.40, 0.80, 0.50
    end
end

-- Another player's tooltip, with pictures for words. The game writes
--     Torinth Nightslayer / Legends of War / Level 22 Dwarf (Player) / Rogue / Alliance
-- which becomes
--     Torinth Nightslayer / Legends of War / 22 [dwarf] [rogue] [alliance]
-- The name keeps its colour, the guild its line; level, race, class and
-- faction share one line as a number and three small icons. A picture the
-- client doesn't have falls back to the word. Nothing is touched when the
-- tooltip's text can't be read (hidden in combat).
local function atlasOK(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end
local ICON = 16
local function atlasMark(name) return string.format("|A:%s:%d:%d|a", name, ICON, ICON) end
local RACE_ATLAS = { Scourge = "undead", HighmountainTauren = "highmountain", LightforgedDraenei = "lightforged",
                     ZandalariTroll = "zandalari", KulTiran = "kultiran", DarkIronDwarf = "darkirondwarf",
                     MagharOrc = "magharorc" }
local FACTION_ATLAS = {
    Alliance = { "MountJournalIcons-Alliance", "AllianceEmblem", "bfa-landingbutton-alliance-up", "poi-alliance" },
    Horde = { "MountJournalIcons-Horde", "HordeEmblem", "bfa-landingbutton-horde-up", "poi-horde" },
}
local markCache = {}
local function raceMark(unit)
    local ok, name, token = pcall(UnitRace, unit)
    if not ok or type(token) ~= "string" or issecretvalue(token) then return nil end
    local okS, sex = pcall(UnitSex, unit)
    local gender = (okS and not issecretvalue(sex) and sex == 3) and "female" or "male"
    local key = "race:" .. token .. gender
    if markCache[key] == nil then
        local base = (RACE_ATLAS[token] or token):lower()
        local found = false
        for _, a in ipairs({ "raceicon-" .. base .. "-" .. gender, "raceicon128-" .. base .. "-" .. gender }) do
            if atlasOK(a) then found = atlasMark(a) break end
        end
        markCache[key] = found
    end
    return markCache[key] or (type(name) == "string" and not issecretvalue(name) and name) or nil
end
local function classMark(unit)
    local ok, name, token = pcall(UnitClass, unit)
    if not ok or type(token) ~= "string" or issecretvalue(token) then return nil, nil end
    local key = "class:" .. token
    if markCache[key] == nil then
        local a = "classicon-" .. token:lower()
        local found = false
        if atlasOK(a) then
            found = atlasMark(a)
        elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token] then
            local c = CLASS_ICON_TCOORDS[token]
            found = string.format("|TInterface/Glues/CharacterCreate/UI-CharacterCreate-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t",
                ICON, ICON, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
        end
        markCache[key] = found
    end
    local word = type(name) == "string" and not issecretvalue(name) and name or nil
    return markCache[key] or word, word
end
local function factionMark(unit)
    local ok, token, name = pcall(UnitFactionGroup, unit)
    if not ok or type(token) ~= "string" or issecretvalue(token) then return nil, nil end
    local key = "faction:" .. token
    if markCache[key] == nil then
        local found = false
        for _, a in ipairs(FACTION_ATLAS[token] or {}) do
            if atlasOK(a) then found = atlasMark(a) break end
        end
        if not found and (token == "Alliance" or token == "Horde") then
            found = string.format("|TInterface/PVPFrame/PVP-Currency-%s:%d:%d|t", token, ICON, ICON)
        end
        markCache[key] = found
    end
    local word = type(name) == "string" and not issecretvalue(name) and name or nil
    return markCache[key] or word, word
end
-- Our own emblems (dist/icons.py: one flat sign per class, faction and
-- race, in the stroke of the rest of the set), tinted: the class in its
-- class colour, the faction blue or red, the race plain.
local OUR_CLASS = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, ROGUE = 1, PRIEST = 1, SHAMAN = 1, MAGE = 1, WARLOCK = 1, DRUID = 1 }
local OUR_RACE = { Human = 1, Dwarf = 1, NightElf = 1, Gnome = 1, Orc = 1, Scourge = 1, Tauren = 1, Troll = 1,
                   BloodElf = 1, Draenei = 1 }
local FACTION_TINT = { Alliance = { 0.40, 0.62, 1.00 }, Horde = { 0.92, 0.32, 0.26 } }
local function ourMark(file, r, g, b, size)
    size = size or 15
    return string.format("|TInterface/AddOns/Meniscus/Media/micro_%s.tga:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t",
        file, size, size, math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end
local function ourMarks(unit)
    local okC, _, ctoken = pcall(UnitClass, unit)
    local okR, rname, rtoken = pcall(UnitRace, unit)
    local okF, ftoken = pcall(UnitFactionGroup, unit)
    if not (okC and okR) or issecretvalue(ctoken) or issecretvalue(rtoken) then return nil end
    if type(ctoken) ~= "string" or type(rtoken) ~= "string" then return nil end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[ctoken]
    local class = ourMark(OUR_CLASS[ctoken] and ("class_" .. ctoken:lower()) or "class_other",
        cc and cc.r or 0.9, cc and cc.g or 0.9, cc and cc.b or 0.9)
    -- Forever's own races are not in the list by name (what the client
    -- calls them inside isn't known ahead of time): the sky elves are found
    -- by "sky" in either name, and every race met is noted with both its
    -- names (MinimalUIDB.raceSeen), so the next new one can be given a sign.
    local rfile = OUR_RACE[rtoken] and ("race_" .. rtoken:lower()) or "race_other"
    if not OUR_RACE[rtoken] then
        local shown = (type(rname) == "string" and not issecretvalue(rname)) and rname or ""
        if rtoken:lower():find("sky", 1, true) or shown:lower():find("sky", 1, true) then rfile = "race_skyelf" end
    end
    if MinimalUIDB then
        local seen = MinimalUIDB.raceSeen
        if type(seen) ~= "table" then seen = {}; MinimalUIDB.raceSeen = seen end
        if seen[rtoken] == nil then seen[rtoken] = (type(rname) == "string" and not issecretvalue(rname)) and rname or "?" end
    end
    local race = ourMark(rfile, 0.86, 0.86, 0.90)
    local faction
    if okF and type(ftoken) == "string" and not issecretvalue(ftoken) and FACTION_TINT[ftoken] then
        local t = FACTION_TINT[ftoken]
        faction = ourMark("faction_" .. ftoken:lower(), t[1], t[2], t[3])
    end
    return race, class, faction
end
-- The level, as the same bubble the portraits carry on their lower edge:
-- a dark grey disc in a hairline ring, the number inside, coloured by how
-- the level stands against yours. (A frame of ours laid over the line; the
-- line leaves room for it.)
local ORB = 19
local function levelOrb(tip)
    local o = tip.__muiLevel
    if o then return o end
    o = CreateFrame("Frame", nil, tip)
    o:SetSize(ORB, ORB)
    o:SetFrameLevel(tip:GetFrameLevel() + 5)
    o.ring = o:CreateTexture(nil, "ARTWORK", nil, 0)
    o.ring:SetTexture("Interface/AddOns/Meniscus/Media/circle.tga")
    o.ring:SetAllPoints()
    o.fill = o:CreateTexture(nil, "ARTWORK", nil, 1)
    o.fill:SetTexture("Interface/AddOns/Meniscus/Media/circle.tga")
    o.fill:SetPoint("TOPLEFT", 1.5, -1.5)
    o.fill:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    o.ring:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
    o.fill:SetVertexColor(0.17, 0.17, 0.19, 1)
    o.text = o:CreateFontString(nil, "OVERLAY")
    ns:SetFont(o.text, 10, "", true) -- (bold)
    o.text:SetPoint("CENTER", 0, 0)
    o.text:SetShadowOffset(1, -1)
    o.text:SetShadowColor(0, 0, 0, 0.9)
    o:Hide()
    tip.__muiLevel = o
    local function away(self) if self.__muiLevel then self.__muiLevel:Hide() end end
    tip:HookScript("OnHide", away)
    if tip:HasScript("OnTooltipCleared") then tip:HookScript("OnTooltipCleared", away) end
    return o
end
local function compactPlayer(tip, unit)
    if tip.__muiLevel then tip.__muiLevel:Hide() end
    local style = TT.db and TT.db.tipIcons or (TT.db and TT.db.icons == false and "off") or "ours"
    if style == "off" then return end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or issecretvalue(isPlayer) or not isPlayer then return end
    local okL, level = pcall(UnitLevel, unit)
    if not okL or issecretvalue(level) or type(level) ~= "number" then return end
    local race = raceMark(unit)
    local class, classWord = classMark(unit)
    local faction, factionWord = factionMark(unit)
    if style == "ours" then
        local r2, c2, f2 = ourMarks(unit)
        if r2 then race, class, faction = r2, c2, f2 or faction end
    end
    if not (race and class) then return end
    -- The lines the game wrote: the level line, and those that are just
    -- the class and the faction.
    local n = tip:NumLines()
    local levelLine, drop = nil, {}
    local wantLevel = level > 0 and tostring(level) or "??"
    for i = 2, n do
        local fs = _G["GameTooltipTextLeft" .. i]
        local t = fs and fs:GetText()
        if issecretvalue(t) then return end
        if type(t) == "string" and t ~= "" then
            if not levelLine and (t:find("(", 1, true) and t:find(wantLevel, 1, true)) then
                levelLine = fs
            elseif levelLine and (t == classWord or t == factionWord) then
                drop[#drop + 1] = fs
            end
        end
    end
    if not levelLine then return end
    -- Room for the orb (a dark disc of its size, which it then covers),
    -- then the three emblems.
    local row = ourMark("up", 0.06, 0.06, 0.07, ORB):gsub("micro_up", "circle") .. "  " .. race .. "  " .. class
    if faction then row = row .. "  " .. faction end
    levelLine:SetText(row)
    levelLine:SetTextColor(T.text[1], T.text[2], T.text[3])
    local orb = levelOrb(tip)
    local dc
    if level > 0 then
        local fn = _G.GetCreatureDifficultyColor or _G.GetQuestDifficultyColor
        local okD, c = pcall(fn, level)
        if okD and type(c) == "table" and c.r then dc = c end
    end
    local dr, dg, db2 = dc and dc.r or 0.90, dc and dc.g or 0.30, dc and dc.b or 0.28
    orb.text:SetText(wantLevel)
    orb.text:SetTextColor(dr, dg, db2)
    orb:ClearAllPoints()
    orb:SetPoint("LEFT", levelLine, "LEFT", 0, 0)
    orb:Show()
    for _, fs in ipairs(drop) do
        fs:SetText(nil)
        fs:Hide()
    end
    -- Wide enough for the name: with the long "Level 22 Dwarf (Player)"
    -- line gone, the tooltip shrank to the icon row and cut the name short.
    local nameFS = _G.GameTooltipTextLeft1
    local okW, w = pcall(function() return nameFS and nameFS:GetUnboundedStringWidth() end)
    if okW and type(w) == "number" and not issecretvalue(w) and tip.SetMinimumWidth then
        tip:SetMinimumWidth(math.ceil(w) + 24)
        if not tip.__muiMinHook then
            tip.__muiMinHook = true
            tip:HookScript("OnHide", function(self)
                if self.__muiMinW then self.__muiMinW = nil; pcall(self.SetMinimumWidth, self, 0) end
            end)
            if tip:HasScript("OnTooltipCleared") then
                tip:HookScript("OnTooltipCleared", function(self)
                    if self.__muiMinW then self.__muiMinW = nil; pcall(self.SetMinimumWidth, self, 0) end
                end)
            end
        end
        tip.__muiMinW = true
    end
    tip:Show() -- (fits the tooltip to its fewer lines)
end

local function onUnit(tip)
    if tip ~= GameTooltip then return end
    local _, unit = tip:GetUnit()
    if not unit then return end
    pcall(compactPlayer, tip, unit)
    local r, g, b = unitColor(unit)
    if r then
        local line = _G.GameTooltipTextLeft1
        if line then line:SetTextColor(r, g, b) end
        setBorder(tip, r * 0.6, g * 0.6, b * 0.6)
    end
end

-- The game's own stat lines get our emblems in front, as our comparisons
-- have: "+1 Stamina", "65 Armor", and the gains and losses the game lists
-- under "If you replace this item..." (which is shortened to "If
-- equipped:"). Only the text of lines it has already written is changed.
-- Returns true if anything was.
local function markStats(tip)
    if not (TT.db and TT.db.statMarks == true) then return false end -- (off unless asked for: words by default)
    local name = tip.GetName and tip:GetName()
    if not name or not ns.StatMarkByName then return false end
    local changed = false
    local n = tip:NumLines() or 0
    for i = 2, n do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if type(text) == "string" and not issecretvalue(text) and text ~= "" and not text:find("|T", 1, true) then
            if _G.ITEM_DELTA_DESCRIPTION and text == _G.ITEM_DELTA_DESCRIPTION then
                fs:SetText("If equipped:")
                changed = true
            else
                -- "+47 Armor", "-2 Stamina", "65 Armor" (colour codes kept).
                local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local stat = plain:match("^[+-]?[%d,%.]+%s+(.+)$")
                -- (No drop: beside tooltip text the usual two pixels down sat it low.)
                local mark = stat and ns.StatMarkByName(stat, 14, 2)
                if mark then
                    -- The emblem stands for the word: "65 Armor" becomes
                    -- the shield and "65". (Cut from the game's own text,
                    -- so its colours stay.)
                    local at = text:find(stat, 1, true)
                    if at then text = (text:sub(1, at - 1):gsub("%s+$", "")) .. text:sub(at + #stat) end
                    fs:SetText(mark .. " " .. text)
                    changed = true
                end
            end
        end
    end
    return changed
end

local function onItem(tip)
    -- (First, and whatever follows: the "Equipped" comparison tooltips
    -- can't say which item they hold, and gave up below before this ran.)
    pcall(markStats, tip)
    -- (The comparison's gains and losses are written after this: once more
    -- on the next frame, and the tooltip laid out again if that changed it.)
    C_Timer.After(0, function()
        if not tip:IsShown() then return end
        local okM, did = pcall(markStats, tip)
        if okM and did then pcall(tip.Show, tip) end
    end)
    local ok, _, link = pcall(tip.GetItem, tip)
    if not ok or not link or issecretvalue(link) then return end
    local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and q > 1 then setBorder(tip, c.r, c.g, c.b) end
end

-- Default tooltip position: with the console's wings up, tucked into the
-- corner where the plate's top edge meets the right wing (the damage meter /
-- objectives panel), instead of the screen's bottom-right corner. Only the
-- default anchor: tooltips that follow the cursor or that a window places
-- itself are left alone.
local function consoleCorner(tip)
    if tip ~= GameTooltip or tip:GetAnchorType() ~= "ANCHOR_NONE" then return end
    local B = ns.modules.Bars
    local plate = B and B.plate
    local wing = plate and plate.meterWell
    if not (plate and plate:IsShown() and wing and wing:IsShown()) then return end
    local x, y = wing:GetLeft(), plate:GetTop()
    if not (x and y) then return end
    local k = UIParent:GetEffectiveScale() / tip:GetEffectiveScale()
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", (x - 2) * k, (y + 2) * k)
end

function TT:OnInit(db)
    self.db = db
    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip) pcall(consoleCorner, tip) end)
    end
    for _, name in ipairs(TIPS) do pcall(style, _G[name]) end
    styleFonts()
    pcall(styleHealthBar)

    -- Border resets when a tooltip is cleared (before it's filled); the
    -- unit/item handlers tint it while it's being filled.
    for _, name in ipairs(TIPS) do
        local tip = _G[name]
        if tip then
            tip:HookScript("OnShow", function(self)
                style(self); zero(self.NineSlice)
                if name:find("^ShoppingTooltip") and not self.__menMarking then
                    C_Timer.After(0, function()
                        if not self:IsShown() then return end
                        local okM, did = pcall(markStats, self)
                        if okM and did then
                            self.__menMarking = true
                            pcall(self.Show, self)
                            self.__menMarking = nil
                        end
                    end)
                end
            end)
            pcall(tip.HookScript, tip, "OnTooltipCleared", function(self)
                setBorder(self, unpack(T.border))
            end)
        end
    end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip) pcall(onUnit, tip) end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip) pcall(onItem, tip) end)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", function(tip) pcall(onUnit, tip) end)
        GameTooltip:HookScript("OnTooltipSetItem", function(tip) pcall(onItem, tip) end)
    end
end
