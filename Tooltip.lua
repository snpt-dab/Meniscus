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

local function onUnit(tip)
    if tip ~= GameTooltip then return end
    local _, unit = tip:GetUnit()
    if not unit then return end
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
