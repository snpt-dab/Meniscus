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
local function compactPlayer(tip, unit)
    if not (TT.db and TT.db.icons ~= false) then return end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or issecretvalue(isPlayer) or not isPlayer then return end
    local okL, level = pcall(UnitLevel, unit)
    if not okL or issecretvalue(level) or type(level) ~= "number" then return end
    local race = raceMark(unit)
    local class, classWord = classMark(unit)
    local faction, factionWord = factionMark(unit)
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
    local row = wantLevel .. "   " .. race .. "  " .. class
    if faction then row = row .. "  " .. faction end
    levelLine:SetText(row)
    levelLine:SetTextColor(T.text[1], T.text[2], T.text[3])
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

local function onItem(tip)
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
            tip:HookScript("OnShow", function(self) style(self); zero(self.NineSlice) end)
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
