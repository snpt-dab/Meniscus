-- A stand-in for the game, enough to run Nameplates.lua's combat numbers
-- outside it: frames that accept anything, a clock, timers, events.
clock = 1000
local timers, frames, events = {}, {}, {}
LOG = {}          -- what was put on the screen: { t, what, font, text }
BROKEN_FONT = false   -- the numerals-only typeface gives its blank characters some width
KBLANK = false        -- a log line's ticket measures as nothing in the numerals typeface (and has a width in the ordinary one)

local function logdraw(what, o, text)
    if o.__unseen then return end
    LOG[#LOG + 1] = { t = clock, what = what, font = o.__font or "?", text = text, o = o }
end

function issecretvalue(v) return type(v) == "table" and rawget(v, "__secret") == true end
function SECRET(n) return { __secret = true, v = n } end

local NOOP = function() end
local W = {}
local METHODS = {}
W.__index = function(t, k)
    local m = METHODS[k]
    if m then return m end
    -- (a method of the game's, by its capital letter: accepted and ignored; a field of ours not set: nil, as in the game)
    if type(k) == "string" and k:match("^[A-Z]") then return NOOP end
    return nil
end
local function widget(kind, parent)
    local o = { __kind = kind, __parent = parent, __shown = true, __scripts = {} }
    setmetatable(o, W)
    if kind == "Frame" or kind == "StatusBar" or kind == "Button" then frames[#frames + 1] = o end
    return o
end
function METHODS:SetScript(n, fn) self.__scripts[n] = fn end
function METHODS:GetScript(n) return self.__scripts[n] end
function METHODS:HookScript(n, fn)
    local old = self.__scripts[n]
    self.__scripts[n] = old and function(...) old(...) fn(...) end or fn
end
function METHODS:RegisterEvent(e) events[e] = events[e] or {}; events[e][self] = true; return true end
function METHODS:RegisterUnitEvent(e) events[e] = events[e] or {}; events[e][self] = true; return true end
function METHODS:UnregisterAllEvents() for _, set in pairs(events) do set[self] = nil end end
function METHODS:Show() self.__shown = true end
function METHODS:Hide() self.__shown = false end
function METHODS:SetShown(v) self.__shown = v and true or false end
function METHODS:IsShown() return self.__shown end
function METHODS:IsVisible() return self.__shown end
-- (A string on the BACKGROUND layer is one of the addon's unseen measuring
-- strings: what it is given is not a number on the screen.)
function METHODS:CreateFontString(_, layer)
    local w = widget("FontString", self)
    if layer == "BACKGROUND" then w.__unseen = true end
    return w
end
function METHODS:CreateTexture() return widget("Texture", self) end
function METHODS:CreateMaskTexture() return widget("MaskTexture", self) end
function METHODS:CreateLine() return widget("Line", self) end
function METHODS:GetStatusBarTexture()
    if not self.__fill then self.__fill = widget("Texture", self) end
    return self.__fill
end
function METHODS:SetFont(path, size, flags)
    if type(path) ~= "string" then error("bad font") end
    self.__font, self.__size, self.__flags = path, size, flags
    return true
end
function METHODS:GetFont() return self.__font, self.__size, self.__flags end
function METHODS:SetText(t)
    if not self.__font then error("Font not set") end
    self.__text = t
    if t ~= nil and t ~= "" then logdraw("text", self, t) end
end
function METHODS:SetFormattedText(fmt, v)
    self.__text = fmt
    logdraw("ftext", self, v)
end
function METHODS:GetText() return self.__text end
local function width(self)
    local t = self.__text
    if type(t) ~= "string" then return 0 end
    if (self.__font or ""):find("digits", 1, true) then
        if KBLANK and t:find("^|K") then return 0 end
        local w = 0
        for ch in t:gmatch(".") do
            if ch:match("%d") then w = w + 12
            elseif ch == "(" then w = w + 240
            elseif BROKEN_FONT then w = w + 1 end
        end
        return w
    end
    return #t * 8
end
METHODS.GetStringWidth = width
METHODS.GetUnboundedStringWidth = width
function METHODS:SetValue(v) self.__value = v; if self.__watch then logdraw("bar", self, v) end end
function METHODS:GetValue() return self.__value end
function METHODS:GetWidth() return 100 end
function METHODS:GetHeight() return 10 end
function METHODS:GetSize() return 100, 10 end
function METHODS:GetCenter() return 500, 400 end
function METHODS:GetTop() return 420 end
function METHODS:GetLeft() return 450 end
function METHODS:GetRight() return 550 end
function METHODS:GetBottom() return 380 end
function METHODS:GetEffectiveScale() return 1 end
function METHODS:GetFrameLevel() return 1 end
function METHODS:GetParent() return self.__parent end
function METHODS:IsForbidden() return false end
function METHODS:IsObjectType(k) return self.__kind == k end
function METHODS:GetNumPoints() return 0 end
function METHODS:GetDrawLayer() return "ARTWORK" end
function METHODS:CreateAnimationGroup() return widget("AnimationGroup", self) end

function CreateFrame(kind, name, parent)
    local o = widget(kind or "Frame", parent)
    if name then _G[name] = o end
    return o
end
UIParent = CreateFrame("Frame")
function UIParent:GetWidth() return 2100 end
function UIParent:GetHeight() return 1181 end

function GetTime() return clock end
date = os.date
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc(a, b, c)
    if type(a) == "table" then
        local old = a[b]
        rawset(a, b, function(...) local r = old(...) c(...) return r end)
    end
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function debugstack() return "" end
C_Timer = {
    After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end,
    NewTicker = function(d, fn, n) timers[#timers + 1] = { at = clock + d, fn = fn, every = d, left = n } end,
}
-- the world
WORLD = { units = {}, plates = {}, dead = {}, threat = {}, grouped = false, combat = true, auto = true }
C_NamePlate = {
    GetNamePlateForUnit = function(u)
        local id = WORLD.units[u]
        if not id or not u:find("^nameplate") and not WORLD.plateOf then return WORLD.plates[u] end
        return WORLD.plates[u]
    end,
    GetNamePlates = function() return {} end,
}
function UnitIsUnit(a, b) local x, y = WORLD.units[a], WORLD.units[b]; return x ~= nil and x == y end
function UnitIsDeadOrGhost(u) return WORLD.dead[WORLD.units[u] or ""] == true end
function UnitExists(u) return WORLD.units[u] ~= nil end
function UnitGUID(u) return "guid-" .. tostring(WORLD.units[u] or u) end
function UnitCanAttack() return true end
function UnitThreatSituation(_, u)
    local id = WORLD.units[u]
    if id and WORLD.threat[id] and not WORLD.dead[id] then return 3 end
    return nil
end
function UnitAffectingCombat() return WORLD.combat end
function InCombatLockdown() return WORLD.combat end
function UnitAttackSpeed() return SECRET(2) end
function UnitClassification() return "normal" end
function UnitLevel() return 20 end
function IsInGroup() return WORLD.grouped end
function GetCVar() return "1" end
function SetCVar() end
function GetCVarDefault() return "1" end
C_Spell = {
    IsSpellHelpful = function() return false end,
    IsCurrentSpell = function() return WORLD.auto end,
    GetSpellName = function(id) return "Spell" .. tostring(id) end,
    IsAutoRepeatSpell = function() return false end,
    GetSpellTexture = function() return 1 end,
}
C_CombatLog = { AreFilteredEventsEnabled = function() return true end, SetFilteredEventsEnabled = function() end }
C_DamageMeter = { GetCombatSessionSourceFromType = function() return { totalAmount = SECRET(100) } end, ResetAllCombatSessions = function() end }
C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
Enum = { DamageMeterType = { HealingDone = 1 } }
Blizzard_CombatLog_CurrentSettings = { name = "Meniscus", filters = {} }
MinimalUIDB = {}
QUICKBUTTON_NAME_MY_ACTIONS = "My actions"

-- the addon's own shell
ns = { modules = {}, commands = {}, name = "Meniscus", CreateFrame = CreateFrame }
ns.Theme = { border = { 0.2, 0.2, 0.23, 1 }, bar = "x", font = "Interface/AddOns/Meniscus/Media/manrope-500.ttf",
             fontBold = "Interface/AddOns/Meniscus/Media/manrope-700.ttf", text = { 1, 1, 1, 1 } }
ns.SCHOOL = { [1] = { 0.94, 0.94, 0.96 }, [2] = { 1, 0.9, 0.5 }, [4] = { 1, 0.56, 0.28 }, [8] = { 0.55, 0.9, 0.45 },
              [16] = { 0.55, 0.82, 1 }, [32] = { 0.74, 0.6, 1 }, [64] = { 1, 0.62, 0.9 } }
function ns:NewModule(name, defaults) local m = { defaults = defaults }; ns.modules[name] = m; return m end
function ns:SetFont(fs, size, flags, bold) fs:SetFont(bold and ns.Theme.fontBold or ns.Theme.font, size, flags) end
function ns.RoundedRect() return function() end end
function ns.PillRatio() return 8 end
function ns:Print() end

-- driving it
function fire(event, ...)
    local set = events[event]
    if not set then return end
    local list = {}
    for f in pairs(set) do list[#list + 1] = f end
    for _, f in ipairs(list) do
        local fn = f.__scripts.OnEvent
        if fn then fn(f, event, ...) end
    end
end
-- time moves on in steps of a hundredth of a second: timers, then every shown frame's OnUpdate
function run(seconds)
    local steps = math.floor(seconds / 0.01 + 0.5)
    for _ = 1, steps do
        clock = clock + 0.01
        local due = {}
        for i = #timers, 1, -1 do
            local t = timers[i]
            if t.at <= clock + 1e-9 then
                due[#due + 1] = t
                if t.every and (not t.left or t.left > 1) then
                    t.at = t.at + t.every
                    if t.left then t.left = t.left - 1 end
                else
                    table.remove(timers, i)
                end
            end
        end
        table.sort(due, function(a, b) return a.at < b.at end)
        for _, t in ipairs(due) do t.fn() end
        for i = 1, #frames do
            local f = frames[i]
            local fn = f.__scripts.OnUpdate
            if fn and f.__shown then fn(f, 0.01) end
        end
    end
end
-- a line of the log, by its kind (the colours the filter gives them)
local KIND_RGB = { swing = { 0.92, 0.36, 0.30 }, shot = { 0.92, 0.50, 0.26 }, spell = { 0.92, 0.64, 0.22 }, tick = { 0.86, 0.46, 0.62 },
                   swingmiss = { 0.56, 0.60, 0.70 }, heal = { 0.42, 0.90, 0.50 }, kill = { 0.94, 0.88, 0.58 } }
local ticket = 0
function line(kind)
    ticket = ticket + 1
    local c = KIND_RGB[kind]
    local msg = "|Ky" .. ticket .. "|k"
    local k = kind == "kill" and 1.5 or 1
    fire("COMBAT_LOG_MESSAGE", msg, math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k))
    return msg
end
function hit(unit, amount, school, indicator, action)
    fire("UNIT_COMBAT", unit, action or "WOUND", indicator or "", SECRET(amount), school or 1)
end
function notes(from)
    local d = MinimalUIDB.ctlog or {}
    local out = {}
    for i = (from or 0) + 1, #d do out[#out + 1] = d[i] end
    return out
end
function draws(from)
    local out = {}
    for i = (from or 0) + 1, #LOG do
        local e = LOG[i]
        local t = e.text
        if issecretvalue(t) then t = "amount(" .. tostring(t.v) .. ")" end
        out[#out + 1] = string.format("%.2f %s %s %s", e.t - 1000, e.what, ((e.font or "?"):match("([^/]+)$") or "?"), tostring(t))
    end
    return out
end
