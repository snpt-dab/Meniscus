local ADDON, ns = ...
_G.MinimalUI = ns
_G.Meniscus = ns

ns.name = ADDON
ns.modules = {}
ns.order = {}

local defaults = { profiles = {}, chars = {} }

-- ── Profiles ──────────────────────────────────────────────────────────────
-- Module settings live in MinimalUIDB.profiles[name]; each character picks
-- one (MinimalUIDB.chars[Name-Realm], default "Default"). ns.db is a view of
-- MinimalUIDB whose .modules is the active profile, so modules don't care.
local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepcopy(v) end
    return c
end
ns.deepcopy = deepcopy

function ns:CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function activateProfile()
    local db = MinimalUIDB
    -- Older versions kept settings in MinimalUIDB.modules: that becomes "Default".
    if db.modules then
        db.profiles.Default = db.profiles.Default or db.modules
        db.modules = nil
    end
    db.profiles.Default = db.profiles.Default or {}
    local name = db.chars[ns:CharKey()] or "Default"
    if not db.profiles[name] then name = "Default" end
    ns.profile = name
    ns.db = setmetatable({ modules = db.profiles[name] }, { __index = db, __newindex = db })
end

function ns:ProfileNames()
    local list = {}
    for name in pairs(MinimalUIDB.profiles) do table.insert(list, name) end
    table.sort(list, function(a, b)
        if a == "Default" then return true elseif b == "Default" then return false end
        return a < b
    end)
    return list
end

-- Switch this character to profile `name` (copying the current one into it
-- when it doesn't exist yet). Needs a reload; done right away.
function ns:UseProfile(name, copy)
    local db = MinimalUIDB
    if not db.profiles[name] then
        db.profiles[name] = copy and deepcopy(db.profiles[ns.profile]) or {}
    end
    db.chars[ns:CharKey()] = name
    ReloadUI()
end

local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Register a module. mod.OnInit(db) runs at PLAYER_LOGIN if enabled.
function ns:NewModule(name, moduleDefaults)
    local mod = { name = name, defaults = moduleDefaults or {} }
    self.modules[name] = mod
    table.insert(self.order, name)
    return mod
end

function ns:Print(...)
    print("|cff4fc3f7Meniscus|r", ...)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        MinimalUIDB = MinimalUIDB or {}
        merge(MinimalUIDB, defaults)
        activateProfile()
    elseif event == "PLAYER_LOGIN" then
        for _, name in ipairs(ns.order) do
            local mod = ns.modules[name]
            ns.db.modules[name] = ns.db.modules[name] or {}
            merge(ns.db.modules[name], mod.defaults)
            local mdb = ns.db.modules[name]
            if mdb.enabled ~= false and mod.OnInit then
                local ok, err = pcall(mod.OnInit, mod, mdb)
                if not ok then ns:Print("module", name, "failed:", err) end
            end
        end
    end
end)

ns.commands = {}

-- ── Error recorder ────────────────────────────────────────────────────────
-- Records unique Lua errors (message + stack + count) into MinimalUIDB.errors
-- so they can be read from the SavedVariables file after a /reload.
-- Chains to the previous handler, so Blizzard's error display still works.
do
    local pending = {}
    local prev = geterrorhandler()
    seterrorhandler(function(msg, ...)
        local ok = pcall(function()
            local store = (MinimalUIDB and MinimalUIDB.errors) or pending
            local key = tostring(msg)
            local e = store[key]
            if e then
                e.count = e.count + 1
            else
                local n = 0
                for _ in pairs(store) do n = n + 1 end
                if n < 25 then
                    store[key] = { count = 1, stack = debugstack(3, 12, 0), time = date("%H:%M:%S") }
                end
            end
        end)
        if prev then return prev(msg, ...) end
    end)
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, name)
        if name ~= ns.name then return end
        MinimalUIDB = MinimalUIDB or {}
        MinimalUIDB.errors = {} -- fresh log each session
        for k, v in pairs(pending) do MinimalUIDB.errors[k] = v end
    end)

    -- Blocked/forbidden secure actions (taint) aren't Lua errors; record them too.
    local blocked = CreateFrame("Frame")
    blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
    blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    blocked:SetScript("OnEvent", function(_, event, addon, func)
        local store = MinimalUIDB and MinimalUIDB.errors
        if not store then return end
        local key = event .. ": " .. tostring(addon) .. " -> " .. tostring(func)
        local e = store[key]
        if e then
            e.count = e.count + 1
        else
            store[key] = { count = 1, stack = debugstack(2, 12, 0), time = date("%H:%M:%S") }
        end
    end)
end

-- /men profile                 list profiles (current marked)
-- /men profile use <name>      switch this character (reloads)
-- /men profile copy <name>     copy the current profile to <name> and use it
-- /men profile delete <name>   remove a profile (not the one in use / Default)
ns.commands.profile = function(_, raw)
    local verb, name = (raw or ""):match("^(%S*)%s*(.-)%s*$")
    verb = verb:lower()
    local db = MinimalUIDB
    if verb == "use" and name ~= "" then
        if not db.profiles[name] then return ns:Print("No profile '" .. name .. "'.") end
        ns:UseProfile(name)
    elseif verb == "copy" and name ~= "" then
        ns:UseProfile(name, true)
    elseif verb == "delete" and name ~= "" then
        if name == "Default" or name == ns.profile then return ns:Print("Can't delete that profile.") end
        db.profiles[name] = nil
        for k, v in pairs(db.chars) do if v == name then db.chars[k] = nil end end
        ns:Print("Deleted profile '" .. name .. "'.")
    else
        for _, n in ipairs(ns:ProfileNames()) do
            ns:Print((n == ns.profile and "> " or "  ") .. n)
        end
    end
end

ns.commands.errors = function()
    local n = 0
    for msg, e in pairs((MinimalUIDB and MinimalUIDB.errors) or {}) do
        n = n + 1
        ns:Print(string.format("x%d %s", e.count, msg))
    end
    if n == 0 then ns:Print("No Lua errors recorded this session.") end
end

SLASH_MINIMALUI1 = "/mui"
SLASH_MINIMALUI2 = "/men"
SLASH_MINIMALUI3 = "/meniscus"
SlashCmdList.MINIMALUI = function(msg)
    local rawCmd, raw = (msg or ""):match("^(%S*)%s*(.*)$")
    local cmd, rest = rawCmd:lower(), raw:lower()
    if cmd == "" and ns.TogglePanel then
        ns:TogglePanel()
    elseif cmd == "probe" and ns.RunProbe then
        ns:RunProbe()
    elseif ns.commands[cmd] then
        -- Catch errors so the chat box always closes and the error is visible.
        local ok, err = pcall(ns.commands[cmd], rest, raw) -- raw keeps case (profile names)
        if not ok then
            ns:Print("|cffff6666/men " .. cmd .. " failed:|r " .. tostring(err))
            local handler = geterrorhandler()
            if handler then pcall(handler, err) end -- also lands in /men errors
        end
    else
        ns:Print("Unknown command. /men opens the panel, /men help lists commands.")
    end
end
