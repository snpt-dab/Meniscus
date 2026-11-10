local _, ns = ...
local T = ns.Theme

-- Quest/objective tracker, light touch: section header art removed, header
-- titles in the theme font and accent color with a thin accent rule under
-- them. Quest lines and the tracker's behavior are untouched (the tracker is
-- taint-sensitive, so only textures/fonts are changed, via hooks).

local TR = ns:NewModule("Tracker", { enabled = true })

-- A "header" is any frame with a .Background texture and a .Text fontstring
-- (true for the tracker's main header and each module header).
local function styleHeader(h)
    if h.__mui then return end
    h.__mui = true
    h.Background:SetAlpha(0)
    hooksecurefunc(h.Background, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
    local _, size = h.Text:GetFont()
    ns:SetFont(h.Text, size or 13, "", true)
    h.Text:SetTextColor(unpack(T.accent))
    h.Text:SetShadowOffset(1, -1)
    h.Text:SetShadowColor(0, 0, 0, 0.9)
    hooksecurefunc(h.Text, "SetTextColor", function(self, r, g, b)
        if r ~= T.accent[1] or g ~= T.accent[2] or b ~= T.accent[3] then
            self:SetTextColor(unpack(T.accent))
        end
    end)
    local rule = h:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.35)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", h.Text, "BOTTOMLEFT", 0, -3)
    rule:SetPoint("RIGHT", h, "RIGHT", -8, 0)
end

-- Quest lines: Blizzard pools and re-fonts them, so every scan re-applies
-- the theme font (keeping each line's size and outline). A line is skipped
-- when it still has what we gave it.
local function fontRegions(f, depth)
    local regs, n = ns.Regs(f, depth)
    for i = 1, n do
        local r = regs[i]
        if r:IsObjectType("FontString") and not ns.fontStrings[r] then -- (headers: styled bold above)
            local path, size, flags = r:GetFont()
            if path and size and not (r.__muiFor == T.font and r.__muiGot == path) then
                r:SetFont(T.font, size, flags or "")
                r.__muiFor, r.__muiGot = T.font, (r:GetFont())
            end
        end
    end
end

local HEADER_KEYS = { "Header", "HeaderMenu", "QuestHeader", "AchievementHeader",
                      "ScenarioHeader", "BonusObjectiveHeader", "WorldQuestHeader" }
local function scan(f, depth)
    if f.Background and f.Text and f.Background.SetAlpha and f.Text.SetFont then
        pcall(styleHeader, f)
    end
    pcall(fontRegions, f, depth)
    if depth > 0 then
        -- Buffers are per depth (counting down here, so still unique per level).
        local kids, n = ns.Kids(f, depth)
        for i = 1, n do scan(kids[i], depth - 1) end
        -- Module headers are often stored as keys rather than direct children.
        for _, k in ipairs(HEADER_KEYS) do
            local v = rawget(f, k)
            if type(v) == "table" and v.GetObjectType then scan(v, 0) end
        end
    end
end

function TR:Restyle()
    local root = _G.ObjectiveTrackerFrame
    if root then scan(root, 7) end
    if _G.ObjectiveTrackerBlocksFrame then scan(_G.ObjectiveTrackerBlocksFrame, 2) end
end

function TR:OnInit(db)
    self.db = db
    self:Restyle()
    -- Headers are created lazily as quests/modules appear.
    local pending = false
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD",
                         "TRACKED_ACHIEVEMENT_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local function soon()
        if pending then return end
        pending = true
        C_Timer.After(0.2, function() pending = false; TR:Restyle() end)
    end
    ev:SetScript("OnEvent", soon)
    -- Blizzard's own tracker refreshes (expand/collapse, new lines) re-font lines.
    local root = _G.ObjectiveTrackerFrame
    if root then
        for _, m in ipairs({ "Update", "UpdateLayout", "MarkDirty" }) do
            if type(root[m]) == "function" then hooksecurefunc(root, m, soon) end
        end
    end
    if type(_G.ObjectiveTracker_Update) == "function" then hooksecurefunc("ObjectiveTracker_Update", soon) end
    -- Safety net for refreshes without an event, and for live font changes.
    -- (Events and Blizzard's own update hooks catch nearly everything.)
    C_Timer.NewTicker(5, function() TR:Restyle() end)
end
