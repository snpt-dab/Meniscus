local _, ns = ...
local CreateFrame = ns.CreateFrame
-- ── Window docks ──────────────────────────────────────────────────────────
-- One system for where windows go and how many are open. Two docks sit on
-- the console: a window opens in the left or the right one, its bottom edge
-- just above the wings. Each dock holds one window, so two can be open: a
-- window takes its usual side if free, else the other; a third replaces the
-- one open longest. The world map is too wide for a dock; it opens centered
-- and closes the docked windows (and a docked window closes it).
-- Dragging a window across the middle of the screen changes its side, which
-- is remembered; it then settles into that dock. Esc closes our windows one
-- at a time, newest first.
--
-- Windows are found by their global name, as they come to exist (ours are
-- built on first use, Blizzard's load on demand). Nothing is reparented and
-- no Blizzard function is replaced: we hook show / hide and set points.
-- Protected windows (the bags, Blizzard's panels) are left alone in combat
-- and caught up when it ends.
local W = ns:NewModule("Windows", { enabled = true, sides = {} })

local MANAGED = {
    MinimalUICharacter = "left", MinimalUISpellbook = "left", MinimalUIQuestLog = "left",
    MinimalUIDialog = "left", MinimalUIMerchant = "left", MinimalUITrainer = "left",
    MinimalUIProfessions = "left", MinimalUIProfessionsBook = "left",
    MinimalUIBank = "left", MinimalUIMail = "left",
    MinimalUIInspect = "right", MinimalUIBags = "right",
    -- Blizzard windows we restyle in place.
    CollectionsJournal = "left", SocialUIFrame = "left", FriendsFrame = "left", CharacterFrame = "left",
    CommunitiesFrame = "left", LFGParentFrame = "left", PlayerSpellsFrame = "left",
    WorldMapFrame = "center",
}
local MARGIN = 18          -- from the screen edge
local LIFT = 12            -- gap between the wings' top and a window's bottom
local MAP_FLOOR = 330      -- the map stays above the dome and the target strip

local hooked = {}          -- frame -> name
local waiting = {}         -- names not yet seen
local open = {}            -- frame -> side, while it is shown and docked
local stack = {}           -- our own open windows, oldest first (for Esc)
local pending = {}         -- frame -> "place" / "hide", owed after combat
local seating = {}         -- frame -> true while we are the one calling SetPoint
local proxy, proxySelf

local function isOurs(name) return name:sub(1, 9) == "MinimalUI" end
local function locked(f) return InCombatLockdown() and f:IsProtected() end

local function sideOf(name)
    local s = W.db and W.db.sides and W.db.sides[name]
    if MANAGED[name] == "center" then return "center" end
    return (s == "left" or s == "right") and s or MANAGED[name]
end

-- A frame that is shown but is really one of our "ghosts" (kept shown at
-- alpha 0 / tiny scale so its interaction stays alive) is not a window.
local function real(f)
    if not f:IsShown() then return false end
    local a, sc = f:GetAlpha(), f:GetScale()
    return a > 0.05 and sc > 0.05
end

local function dockBottom()
    local B = ns.modules.Bars
    if B and B.db and B.db.plate and B.db.wings and B.plate and B.plate:IsShown() then
        return 14 + 210 + LIFT   -- the wings' top (Bars:ApplyPlate: wy + WING_H)
    end
    return 150
end

local function place(f, side)
    if locked(f) then pending[f] = "place" return end
    local s = f:GetScale()
    if not s or s <= 0 then s = 1 end
    local sh = UIParent:GetHeight()
    local h = (f:GetHeight() or 0) * s
    seating[f] = true
    f:ClearAllPoints()
    if side == "center" then
        local y = MAP_FLOOR + math.max(0, (sh - 10 - MAP_FLOOR - h) / 2)
        if y + h > sh - 10 then y = math.max(10, sh - 10 - h) end
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, y / s)
    else
        local y = dockBottom()
        if y + h > sh - 10 then y = math.max(10, sh - 10 - h) end
        if side == "right" then
            f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -MARGIN / s, y / s)
        else
            f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", MARGIN / s, y / s)
        end
    end
    seating[f] = nil
end

local function close(f)
    local name = hooked[f]
    if locked(f) then pending[f] = "hide" return false end
    if name == "MinimalUIBags" and ns.modules.Bags and ns.modules.Bags.Close then
        ns.modules.Bags:Close()
    elseif not isOurs(name) and HideUIPanel and not InCombatLockdown() then
        HideUIPanel(f)
        if f:IsShown() then f:Hide() end
    else
        f:Hide()
    end
    return true
end

local function syncProxy()
    if not proxy then return end
    local any = false
    for i = 1, #stack do if stack[i]:IsShown() and not locked(stack[i]) then any = true break end end
    proxySelf = true
    proxy:SetShown(any)
    proxySelf = false
end

local function unstack(f)
    for i = #stack, 1, -1 do if stack[i] == f then table.remove(stack, i) end end
end

-- A window came up: settle it in a dock and clear what it replaces.
-- It takes its usual side if that dock is free, otherwise the other dock;
-- with both in use it replaces whichever window has been open longest.
-- "forced" is a side the user chose by dragging: the window there moves
-- across if the other dock is free, and closes otherwise.
local order, seq = {}, 0
local function occupant(side, except)
    for other, oside in pairs(open) do
        if other ~= except and oside == side and other:IsShown() and real(other) then return other end
    end
end
local function flip(side) return side == "left" and "right" or "left" end

local function opened(f, forced)
    local name = hooked[f]
    if not name or not real(f) then return end
    local side = sideOf(name)
    if side == "center" then
        for other in pairs(open) do
            if other ~= f and other:IsShown() and real(other) then close(other) end
        end
    else
        for other, oside in pairs(open) do
            if other ~= f and oside == "center" and other:IsShown() and real(other) then close(other) end
        end
        if forced then
            side = forced
            local occ = occupant(side, f)
            if occ then
                if occupant(flip(side), f) then close(occ)
                else open[occ] = flip(side); place(occ, flip(side)) end
            end
        elseif open[f] and open[f] ~= "center" then
            side = open[f]            -- already docked: stay put
        else
            local occ = occupant(side, f)
            if occ then
                local occ2 = occupant(flip(side), f)
                if not occ2 then
                    side = flip(side)
                else
                    local victim = ((order[occ] or 0) <= (order[occ2] or 0)) and occ or occ2
                    side = open[victim]
                    close(victim)
                end
            end
        end
    end
    if not open[f] then seq = seq + 1; order[f] = seq end
    open[f] = side
    place(f, side)
    if isOurs(name) then unstack(f); stack[#stack + 1] = f end
    syncProxy()
end

local function closed(f)
    open[f] = nil
    pending[f] = nil
    unstack(f)
    syncProxy()
end

-- Where a window would go if it opened now, without closing anything.
local function guessSide(f, name)
    if open[f] then return open[f] end
    local side = sideOf(name)
    if side ~= "center" and occupant(side, f) and not occupant(flip(side), f) then side = flip(side) end
    return side
end

local function dropSpecial(name)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
end

local function hook(name, f, building)
    hooked[f] = name
    waiting[name] = nil
    local ours = isOurs(name)
    local shown, hidden
    if ours then
        -- Our windows are hooked while their module is still building them,
        -- and the module then sets its own OnShow / OnHide scripts, which
        -- would replace script hooks made here. So the methods are hooked
        -- (they fire on every call, shown already or not), and the scripts
        -- are hooked once the build is over (below): a window can also be
        -- shown without any Show call (the bags, by their secure toggle).
        shown = function(self)
            if self:IsShown() then dropSpecial(name); opened(self) end
        end
        hidden = function(self)
            if not self:IsShown() and (open[self] or pending[self]) then closed(self) end
        end
        hooksecurefunc(f, "Show", shown)
        hooksecurefunc(f, "Hide", hidden)
        hooksecurefunc(f, "SetShown", function(self) if self:IsShown() then shown(self) else hidden(self) end end)
    end
    f:HookScript("OnShow", function(self)
        if ours then
            -- (Covered by the method hooks; kept for a window nobody re-scripts.)
            if not open[self] then dropSpecial(name); opened(self) end
        else
            -- Blizzard's panel code positions the window right after showing
            -- it, and a ghosted window is hidden again at once: decide one
            -- frame later what it replaces. It is put in its dock right
            -- away though, so it is never drawn in the wrong place.
            if real(self) then place(self, guessSide(self, name)) end
            C_Timer.After(0, function() opened(self) end)
        end
    end)
    f:HookScript("OnHide", closed)
    if ours then
        -- Esc goes through our proxy (one window per press) instead.
        dropSpecial(name)
        -- Dropped after a drag: the half of the screen it is in becomes its side.
        hooksecurefunc(f, "StopMovingOrSizing", function(self)
            if not self:IsShown() or sideOf(name) == "center" then return end
            local x = self:GetCenter()
            if not x then return end
            local side = (x * self:GetScale() < UIParent:GetWidth() / 2) and "left" or "right"
            W.db.sides[name] = side
            C_Timer.After(0, function() if self:IsShown() then opened(self, side) end end)
        end)
    else
        -- The panel manager re-centers its windows whenever another opens or
        -- closes: put ours back in its dock.
        hooksecurefunc(f, "SetPoint", function(self)
            if seating[self] or not open[self] then return end
            if locked(self) then pending[self] = "place" return end
            place(self, open[self])
        end)
    end
    if building then
        -- Still being put together by its module, which hides it and shows
        -- it when ready: the show hook docks it. (Not positioned here: the
        -- module may still be anchoring it, and two anchors would stretch
        -- it.) If it was simply left shown, settle it once the build is over.
        C_Timer.After(0, function()
            if shown then
                f:HookScript("OnShow", shown)
                f:HookScript("OnHide", hidden)
            end
            if f:IsShown() and not open[f] then dropSpecial(name); opened(f) end
        end)
    elseif f:IsShown() then
        if ours then opened(f) else C_Timer.After(0, function() opened(f) end) end
    end
end

-- Called by the window shell (Shell.lua) the moment one of our windows is
-- built, so it is docked before it is first drawn. (Finding windows by
-- polling left the first open of each one visible at its old position for
-- a moment.)
function ns.WindowBuilt(f)
    local name = f and f.GetName and f:GetName()
    if name and waiting[name] then
        local ok, err = pcall(hook, name, f, true)
        if not ok then waiting[name] = nil; ns:Print("Windows " .. name .. ": " .. tostring(err)) end
    end
end

-- Blizzard windows: hook every one that exists (at login, and again each
-- time a load-on-demand part of the UI arrives, which is before its window
-- is first shown).
local function sweep()
    for name in pairs(waiting) do
        local f = _G[name]
        if type(f) == "table" and f.HookScript and not (f.IsForbidden and f:IsForbidden()) then
            local ok, err = pcall(hook, name, f)
            if not ok then waiting[name] = nil; ns:Print("Windows " .. name .. ": " .. tostring(err)) end
            return sweep() -- the table changed: start over
        end
    end
end

function W:OnInit(db)
    self.db = db
    db.sides = db.sides or {}
    for name in pairs(MANAGED) do waiting[name] = true end

    proxy = CreateFrame("Frame", "MeniscusEscProxy", UIParent)
    proxy:Hide()
    table.insert(UISpecialFrames, "MeniscusEscProxy")
    proxy:SetScript("OnHide", function()
        if proxySelf then return end
        -- Esc: close the newest of our windows that can be closed now.
        for i = #stack, 1, -1 do
            local f = stack[i]
            if f:IsShown() and not locked(f) then close(f) break end
        end
        C_Timer.After(0, syncProxy)
    end)

    local driver = CreateFrame("Frame")
    local acc = 0
    sweep()
    -- A slow safety net for anything the two paths above miss.
    driver:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        if not next(waiting) then self:SetScript("OnUpdate", nil) return end
        sweep()
    end)
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    driver:RegisterEvent("ADDON_LOADED")
    driver:SetScript("OnEvent", function(_, e)
        if e == "ADDON_LOADED" then sweep() return end
        for f, what in pairs(pending) do
            pending[f] = nil
            if what == "hide" then close(f)
            elseif f:IsShown() and open[f] then place(f, open[f]) end
        end
        syncProxy()
    end)
end

-- /men windows : turn docking on / off (takes a reload).
ns.commands.windows = function()
    local mdb = W.db or (ns.db and ns.db.modules and ns.db.modules.Windows)
    if not mdb then return end
    mdb.enabled = mdb.enabled == false
    ns:Print("Window docking " .. (mdb.enabled and "on" or "off") .. ". /reload to apply.")
end
