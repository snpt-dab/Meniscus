local _, ns = ...
local T = ns.Theme

-- Quest/objective tracker, light touch: section header art removed, header
-- titles in the theme font and accent color with a thin accent rule under
-- them. Quest lines and the tracker's behavior are untouched (the tracker is
-- taint-sensitive, so only textures/fonts are changed, via hooks).

-- wingTab: what the console's right wing shows (TR:Console below):
-- "auto" (damage meter in combat, objectives otherwise), "damage", "quests".
local TR = ns:NewModule("Tracker", { enabled = true, wingTab = "auto" })

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


-- ── Console panel ─────────────────────────────────────────────────────────
-- The console's right wing (Bars.lua) is a context panel with two tabs:
--   Damage      Blizzard's damage meter, seated there by Bars.lua
--   Objectives  a quest list of our own (below)
-- "auto" shows Damage in combat and Objectives out of it; clicking a tab
-- pins it, clicking "auto" hands the choice back.
--
-- The objectives list is ours, not Blizzard's tracker: that one is an Edit
-- Mode frame that lays itself out to its own stored height (it can't be
-- made to fit a 180 px panel without writing its fields, which taints it),
-- so while the console is on it is parked off screen and this list reads
-- the quest log directly. It shows your tracked quests (all of them if none
-- are tracked), this zone's first; the wheel scrolls; clicking a title opens
-- our quest log on that quest. No quest-item buttons (those must be
-- Blizzard's secure ones).
local QL = C_QuestLog or {}
local call = ns.Call
local TAB_H = 22
local GREEN = { 0.45, 0.80, 0.45 }

local function secretv(v) return issecretvalue and issecretvalue(v) end

local function watched(id)
    if QL.GetQuestWatchType then return call(QL.GetQuestWatchType, id) ~= nil end
    return false
end

local function gather()
    local tracked, all = {}, {}
    local n = call(QL.GetNumQuestLogEntries) or 0
    local zone = GetRealZoneText and GetRealZoneText()
    local header
    for i = 1, (type(n) == "number" and n or 0) do
        local info = call(QL.GetInfo, i)
        if type(info) == "table" and info.title and not info.isHidden then
            if info.isHeader then
                header = info.title
            elseif info.questID then
                local e = { id = info.questID, title = info.title, level = info.level,
                            here = (header ~= nil and header == zone) or info.isOnMap == true,
                            complete = call(QL.IsComplete, info.questID) == true }
                all[#all + 1] = e
                if watched(e.id) then tracked[#tracked + 1] = e end
            end
        end
    end
    local list = #tracked > 0 and tracked or all
    table.sort(list, function(a, b)
        if a.here ~= b.here then return a.here end
        local la, lb = type(a.level) == "number" and a.level or 0, type(b.level) == "number" and b.level or 0
        if la ~= lb then return la < lb end
        return tostring(a.title) < tostring(b.title)
    end)
    return list
end

local function diffColor(level)
    if type(level) ~= "number" or secretv(level) then return T.text[1], T.text[2], T.text[3] end
    local fn = _G.GetQuestDifficultyColor or _G.GetDifficultyColor
    local c = fn and call(fn, level)
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return T.text[1], T.text[2], T.text[3]
end

function TR:Console(x, y, w, h)
    if not self.db then return end
    local P = self.panel
    if not P then
        P = CreateFrame("Frame", "MinimalUI_ConsolePanel", UIParent)
        P:SetFrameStrata("HIGH") -- above the (possibly invisible) damage meter
        P:SetFrameLevel(1)
        self.panel = P

        -- Tabs.
        local function tab(label, key)
            local b = CreateFrame("Button", nil, P)
            b.fs = ns:CreateText(b, 11, T.textDim)
            b.fs:SetPoint("CENTER")
            b.fs:SetText(label)
            b:SetSize(b.fs:GetStringWidth() + 14, TAB_H)
            b.line = b:CreateTexture(nil, "OVERLAY")
            b.line:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
            b.line:SetHeight(2)
            b.line:SetPoint("BOTTOMLEFT", 6, 2); b.line:SetPoint("BOTTOMRIGHT", -6, 2)
            b:SetScript("OnClick", function() TR.db.wingTab = key; TR:ApplyConsole() end)
            return b
        end
        P.tabDamage = tab("Damage", "damage")
        P.tabQuests = tab("Objectives", "quests")
        P.tabAuto = tab("auto", "auto")
        P.tabAuto.line:Hide()
        P.tabDamage:SetPoint("TOPLEFT", P, "TOPLEFT", 2, 0)
        P.tabQuests:SetPoint("LEFT", P.tabDamage, "RIGHT", 2, 0)
        P.tabAuto:SetPoint("TOPRIGHT", P, "TOPRIGHT", -2, 0)

        -- Objectives list: a clipped holder with a taller content frame
        -- that slides under it.
        local holder = CreateFrame("Frame", nil, P)
        holder:SetPoint("TOPLEFT", P, "TOPLEFT", 0, -TAB_H - 2)
        holder:SetPoint("BOTTOMRIGHT", P, "BOTTOMRIGHT", 0, 0)
        holder:SetClipsChildren(true)
        holder:EnableMouse(true)
        holder:EnableMouseWheel(true)
        local content = CreateFrame("Frame", nil, holder)
        content:SetPoint("TOPLEFT")
        content:SetSize(10, 10)
        P.holder, P.content = holder, content
        P.offset, P.total = 0, 0
        local function place()
            local max = math.max(0, P.total - holder:GetHeight())
            if P.offset > max then P.offset = max end
            if P.offset < 0 then P.offset = 0 end
            content:ClearAllPoints()
            content:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, P.offset)
        end
        P.place = place
        holder:SetScript("OnMouseWheel", function(_, d) P.offset = P.offset - d * 34; place() end)

        P.lines, P.used, P.btns, P.usedBtns = {}, 0, {}, 0
        function P.take(size, bold)
            P.used = P.used + 1
            local fs = P.lines[P.used]
            if not fs then
                fs = content:CreateFontString(nil, "OVERLAY")
                fs:SetJustifyH("LEFT")
                fs:SetJustifyV("TOP")
                fs:SetWordWrap(true)
                fs:SetShadowOffset(1, -1)
                fs:SetShadowColor(0, 0, 0, 0.8)
                P.lines[P.used] = fs
            end
            ns:SetFont(fs, size, "", bold)
            fs:Show()
            return fs
        end
        function P.takeBtn()
            P.usedBtns = P.usedBtns + 1
            local b = P.btns[P.usedBtns]
            if not b then
                b = CreateFrame("Button", nil, content)
                b:SetScript("OnClick", function(self)
                    local Q = ns.modules.QuestLog
                    if Q and Q.Open and Q.db then
                        Q.selected = self.questID
                        Q:Open()
                        if Q.Refresh then pcall(Q.Refresh, Q) end
                    elseif ToggleQuestLog then
                        ToggleQuestLog()
                    end
                end)
                b:SetScript("OnEnter", function(self) if self.fs then self.fs:SetAlpha(0.75) end end)
                b:SetScript("OnLeave", function(self) if self.fs then self.fs:SetAlpha(1) end end)
                P.btns[P.usedBtns] = b
            end
            b:Show()
            return b
        end

        function P.fill()
            for i = 1, #P.lines do P.lines[i]:Hide() end
            for i = 1, #P.btns do P.btns[i]:Hide() end
            P.used, P.usedBtns = 0, 0
            local width = math.max(60, holder:GetWidth() - 10)
            content:SetWidth(width + 10)
            local yy = 4
            local function put(fs, indent, gap)
                fs:ClearAllPoints()
                fs:SetWidth(width - indent)
                fs:SetPoint("TOPLEFT", content, "TOPLEFT", 5 + indent, -yy)
                yy = yy + (fs:GetStringHeight() or 12) + gap
            end
            local list = gather()
            if #list == 0 then
                local fs = P.take(11)
                fs:SetText("No quests.")
                fs:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
                put(fs, 0, 4)
            end
            local section
            for _, e in ipairs(list) do
                if e.here ~= section then
                    section = e.here
                    if yy > 4 then yy = yy + 4 end
                    local hs = P.take(9, true)
                    hs:SetText(section and "THIS ZONE" or "ELSEWHERE")
                    hs:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
                    put(hs, 0, 3)
                end
                local fs = P.take(11, true)
                local lvl = (type(e.level) == "number" and not secretv(e.level) and e.level > 0) and ("[" .. e.level .. "] ") or ""
                fs:SetText(lvl .. tostring(e.title))
                if e.complete then fs:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
                else fs:SetTextColor(diffColor(e.level)) end
                fs:SetAlpha(1)
                local top = yy
                put(fs, 0, 1)
                local b = P.takeBtn()
                b.questID, b.fs = e.id, fs
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
                b:SetSize(width + 10, yy - top)
                local objs = QL.GetQuestObjectives and call(QL.GetQuestObjectives, e.id)
                local any = false
                if type(objs) == "table" then
                    for _, o in ipairs(objs) do
                        if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
                            any = true
                            local os = P.take(10)
                            os:SetText(o.text)
                            if o.finished then os:SetTextColor(GREEN[1] * 0.8, GREEN[2] * 0.8, GREEN[3] * 0.8)
                            else os:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3]) end
                            put(os, 10, 1)
                        end
                    end
                end
                if e.complete and not any then
                    local os = P.take(10)
                    os:SetText("Ready to turn in")
                    os:SetTextColor(GREEN[1] * 0.8, GREEN[2] * 0.8, GREEN[3] * 0.8)
                    put(os, 10, 1)
                end
                yy = yy + 5
            end
            P.total = yy + 2
            content:SetHeight(P.total)
            place()
        end

        local pending = false
        local function soon()
            if pending then return end
            pending = true
            C_Timer.After(0.25, function()
                pending = false
                if P.holder:IsShown() then pcall(P.fill) else P.stale = true end
            end)
        end
        local ev = CreateFrame("Frame")
        for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "ZONE_CHANGED_NEW_AREA",
                             "ZONE_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_QUEST_LOG_CHANGED" }) do
            pcall(ev.RegisterEvent, ev, e)
        end
        ev:SetScript("OnEvent", soon)
        local cv = CreateFrame("Frame")
        cv:RegisterEvent("PLAYER_REGEN_DISABLED")
        cv:RegisterEvent("PLAYER_REGEN_ENABLED")
        cv:SetScript("OnEvent", function(_, e) TR:ApplyConsole(e == "PLAYER_REGEN_DISABLED") end)

        -- Blizzard's tracker: invisible and parked off screen while ours is up.
        local tr = _G.ObjectiveTrackerFrame
        if tr then
            local parking = false
            local function park()
                if parking then return end
                parking = true
                pcall(function()
                    tr:SetAlpha(0)
                    tr:ClearAllPoints()
                    tr:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 3000, 0)
                end)
                parking = false
            end
            pcall(tr.SetClampedToScreen, tr, false)
            hooksecurefunc(tr, "SetPoint", function() if not parking then park() end end)
            hooksecurefunc(tr, "SetAlpha", function(_, a) if not parking and a ~= 0 then park() end end)
            park()
        end
    end
    P:ClearAllPoints()
    P:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    P:SetSize(w, h)
    P:Show()
    self:ApplyConsole()
end

-- Which tab is showing; combatStarting covers the moment the fight begins
-- (the lockdown flag isn't set yet during that event).
function TR:ApplyConsole(combatStarting)
    local P = self.panel
    if not P then return end
    local mode = self.db.wingTab or "auto"
    local show = mode
    if mode == "auto" then
        local fighting = combatStarting or InCombatLockdown() or UnitAffectingCombat("player")
        if secretv(fighting) then fighting = true end
        show = fighting and "damage" or "quests"
    end
    local quests = show == "quests"
    P.holder:SetShown(quests)
    if quests and (P.stale or P.total == 0) then P.stale = false; pcall(P.fill) end
    local dm = _G.DamageMeter
    if dm then pcall(dm.SetAlpha, dm, quests and 0 or 1) end
    local function paint(tab, on)
        tab.line:SetShown(on)
        local c = on and T.text or T.textDim
        tab.fs:SetTextColor(c[1], c[2], c[3])
    end
    paint(P.tabDamage, not quests)
    paint(P.tabQuests, quests)
    P.tabAuto.line:Hide()
    local c = mode == "auto" and T.accent or T.textDim
    P.tabAuto.fs:SetTextColor(c[1], c[2], c[3])
end
