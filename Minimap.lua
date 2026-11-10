local _, ns = ...
local T = ns.Theme

-- Minimap: rounded-square map with a hairline rounded border, Blizzard's
-- ring/compass/zoom buttons and calendar button removed, mouse-wheel zoom,
-- zone name in the theme font. The addon compartment, tracking, clock and
-- mail/queue indicators are left alone.

local MM = ns:NewModule("Minimap", { enabled = true })
local MEDIA = "Interface/AddOns/MinimalUI/Media/"

-- Blizzard art to remove. Names differ between client generations, so each
-- is optional.
local function clutter()
    local C = MinimapCluster
    return {
        _G.MinimapBorder, _G.MinimapBorderTop, _G.MinimapCompassTexture, _G.MinimapNorthTag,
        _G.MinimapBackdrop, _G.MinimapZoomIn, _G.MinimapZoomOut, _G.MiniMapWorldMapButton,
        _G.MinimapToggleButton, _G.GameTimeFrame,
        Minimap.ZoomIn, Minimap.ZoomOut, Minimap.ZoomHitArea,
        C and C.BorderTop,
    }
end

function MM:OnInit(db)
    self.db = db
    if not Minimap then return end

    -- Square shape (rounded corners via the mask). Addons that place minimap
    -- buttons ask GetMinimapShape().
    Minimap:SetMaskTexture(MEDIA .. "rounded.tga")
    _G.GetMinimapShape = function() return "SQUARE" end

    -- Border: drawn on a frame behind the map, sharing the map's parent so it
    -- can sit one level below it.
    local border = CreateFrame("Frame", nil, Minimap:GetParent())
    border:SetFrameStrata(Minimap:GetFrameStrata())
    border:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
    border:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 2, -2)
    ns.RoundedRect(border, 0, 0, 16, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(border, 1, 1, 15, 0.05, 0.05, 0.06, 1)
    self.border = border

    for _, obj in pairs(clutter()) do
        if obj then pcall(ns.Kill, obj) end
    end

    -- Mouse-wheel zoom.
    Minimap:EnableMouseWheel(true)
    Minimap:HookScript("OnMouseWheel", function(self, delta)
        local z = self:GetZoom()
        if delta > 0 and z < self:GetZoomLevels() - 1 then
            self:SetZoom(z + 1)
        elseif delta < 0 and z > 0 then
            self:SetZoom(z - 1)
        end
    end)

    -- Zone text: restyle Blizzard's (it keeps its click/tooltip behavior).
    local zoneText = _G.MinimapZoneText or (MinimapCluster and MinimapCluster.ZoneTextButton
        and MinimapCluster.ZoneTextButton.Text)
    if zoneText and zoneText.SetFont then
        local _, size = zoneText:GetFont()
        ns:SetFont(zoneText, size or 12, "")
        zoneText:SetShadowOffset(1, -1)
        zoneText:SetShadowColor(0, 0, 0, 0.8)
    end
end

-- /mui minimap : list what was found/removed (for tuning on this client).
ns.commands.minimap = function()
    if not Minimap then return ns:Print("No Minimap frame.") end
    local n = 0
    for _, obj in pairs(clutter()) do
        if obj then
            n = n + 1
            ns:Print(string.format("%s killed=%s shown=%s", obj:GetName() or obj:GetDebugName() or "?",
                tostring(obj.__muiKilled), tostring(obj:IsShown())))
        end
    end
    ns:Print(n .. " clutter pieces found. Parent:", Minimap:GetParent() and Minimap:GetParent():GetName())
end
