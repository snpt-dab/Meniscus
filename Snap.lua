local _, ns = ...
local T = ns.Theme

-- Snapping drag for move mode. Replaces StartMoving/StopMovingOrSizing:
-- while dragging, the frame's left/center/right and bottom/center/top edges
-- snap to the same edges of the other movable frames and to the screen's
-- center lines. Accent guide lines show what it snapped to.
-- Hold Shift while dragging to place freely.

local SNAP = 10 -- snap distance in UI units

ns.snapTargets = {}
local conditions = {}
-- condition (optional): returns false when the frame shouldn't be snapped to
-- (e.g. the party stack while it's attached to the player frame).
function ns:RegisterSnapTarget(frame, condition)
    conditions[frame] = condition
    for _, f in ipairs(self.snapTargets) do if f == frame then return end end
    table.insert(self.snapTargets, frame)
end

-- Guide lines, in UIParent units.
local guides = CreateFrame("Frame", nil, UIParent)
guides:SetAllPoints()
guides:SetFrameStrata("TOOLTIP")
local function guide()
    local t = guides:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.8)
    t:Hide()
    return t
end
local vLine, hLine = guide(), guide()

-- Edges of a frame in UIParent units: x = {left, center, right}, y = {bottom, center, top}.
local function edges(f)
    local l, b, w, h = f:GetRect()
    if not l then return end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    l, b, w, h = l * k, b * k, w * k, h * k
    return { l, l + w / 2, l + w }, { b, b + h / 2, b + h }
end

-- Best snap correction on one axis: mine/theirs are edge lists.
local function best(mine, lists, current)
    local bestD, bestAt = SNAP + 1, nil
    for _, theirs in ipairs(lists) do
        for _, m in ipairs(mine) do
            for _, t in ipairs(theirs) do
                local d = t - m
                if math.abs(d) < math.abs(bestD) then bestD, bestAt = d, t end
            end
        end
    end
    if bestAt then return bestD, bestAt end
    return 0, nil
end

local drag -- { frame, offX, offY }
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
    local f = drag and drag.frame
    if not f or InCombatLockdown() then ns:SnapDragStop() return end
    local uS = UIParent:GetEffectiveScale()
    local k = f:GetEffectiveScale() / uS -- frame units -> UIParent units
    local cx, cy = GetCursorPosition()
    cx, cy = cx / uS, cy / uS
    local w, h = f:GetWidth() * k, f:GetHeight() * k
    local left, bottom = cx + drag.offX, cy + drag.offY

    local sx, sy, atX, atY = 0, 0, nil, nil
    if not IsShiftKeyDown() then
        local xs, ys = {}, {}
        local W, H = UIParent:GetSize()
        table.insert(xs, { W / 2 })
        table.insert(ys, { H / 2 })
        for _, t in ipairs(ns.snapTargets) do
            local ok = not conditions[t] or conditions[t]()
            if t ~= f and ok and t:IsVisible() then
                local ex, ey = edges(t)
                if ex then table.insert(xs, ex); table.insert(ys, ey) end
            end
        end
        sx, atX = best({ left, left + w / 2, left + w }, xs)
        sy, atY = best({ bottom, bottom + h / 2, bottom + h }, ys)
    end
    left, bottom = left + sx, bottom + sy

    -- Keep it on screen.
    local W, H = UIParent:GetSize()
    left = math.max(0, math.min(left, W - w))
    bottom = math.max(0, math.min(bottom, H - h))

    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / k, bottom / k)

    if atX then
        vLine:ClearAllPoints()
        vLine:SetPoint("TOP", UIParent, "TOPLEFT", atX, 0)
        vLine:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", atX, 0)
        vLine:SetWidth(1)
        vLine:Show()
    else
        vLine:Hide()
    end
    if atY then
        hLine:ClearAllPoints()
        hLine:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, atY)
        hLine:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, atY)
        hLine:SetHeight(1)
        hLine:Show()
    else
        hLine:Hide()
    end
end)

function ns:SnapDragStart(frame)
    if InCombatLockdown() then return end
    local ex, ey = edges(frame)
    if not ex then return end
    local uS = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    drag = { frame = frame, offX = ex[1] - cx / uS, offY = ey[1] - cy / uS }
    driver:Show()
end

function ns:SnapDragStop()
    drag = nil
    driver:Hide()
    vLine:Hide()
    hLine:Hide()
end
