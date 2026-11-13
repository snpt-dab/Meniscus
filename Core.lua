local ADDON, ns = ...

-- Every file makes its frames through this (each starts with
-- "local CreateFrame = ns.CreateFrame"), so trace mode (Perf.lua) can time
-- the handlers set on our own frames without touching anyone else's.
-- Frames made before the saved settings have loaded are kept in a list with
-- where they were made; Perf.lua picks the list up and clears it. With
-- tracing off this only passes through.
local rawCreateFrame = CreateFrame
ns.madeFrames, ns.madeSites = {}, {}
function ns.CreateFrame(...)
    local f = rawCreateFrame(...)
    local list = ns.madeFrames
    if list then
        list[#list + 1] = f
        ns.madeSites[#list] = debugstack(2, 1, 0)
    elseif ns.traceFrame then
        ns.traceFrame(f)
    end
    return f
end
local CreateFrame = ns.CreateFrame
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
                -- (With where it happened, kept in MinimalUIDB.moduleFail.)
                local ok, err = xpcall(mod.OnInit, function(e)
                    return tostring(e) .. "\n" .. (debugstack and debugstack(2, 12, 0) or "")
                end, mod, mdb)
                if not ok then
                    ns:Print("module", name, "failed:", (tostring(err):match("^[^\n]*")))
                    MinimalUIDB.moduleFail = MinimalUIDB.moduleFail or {}
                    MinimalUIDB.moduleFail[name] = { at = date("%Y-%m-%d %H:%M:%S"), err = tostring(err) }
                end
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
-- Put the active profile back to the built-in settings: every module's
-- options, window and frame positions, and the font. What the addon has
-- learned or been told is kept (what your characters own, restock amounts,
-- what your pet eats, bug reports). Reloads at once; the modules fill the
-- emptied profile with their defaults as they start.
function ns:ResetProfile()
    local db = MinimalUIDB
    if not db or not ns.profile then return end
    db.profiles[ns.profile] = {}
    db.font, db.fontPath, db.fontBold, db.fontInterMigrated = nil, nil, nil, nil
    db.panelPage = nil
    ReloadUI()
end
if StaticPopupDialogs then
    StaticPopupDialogs["MENISCUS_RESET"] = {
        text = "Reset Meniscus to its default settings?\n\nEvery option, frame position and the font go back to how a new install starts, for every character using the profile \"%s\". The interface reloads.",
        button1 = "Reset",
        button2 = CANCEL or "Cancel",
        OnAccept = function() ns:ResetProfile() end,
        timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    }
end
ns.commands.defaults = function()
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs["MENISCUS_RESET"] then
        StaticPopup_Show("MENISCUS_RESET", tostring(ns.profile))
    else
        ns:ResetProfile()
    end
end

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

-- ── Version, and noticing a newer one ─────────────────────────────────────
-- An addon can't reach the internet, so it can't look for updates itself.
-- What it can do is tell other players' copies which version it is (hidden
-- addon messages to party / raid / guild) and listen for theirs. Hearing a
-- higher one is remembered (MinimalUIDB.newer*) and said in chat once per
-- session, until this copy has caught up. Updating itself happens outside
-- the game: "Update Meniscus.bat" in the addon folder.
do
    local PREFIX = "Meniscus"
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata
    local okv, v = pcall(function() return meta and meta(ns.name, "Version") end)
    ns.version = (okv and type(v) == "string" and v) or "?"
    -- The last number of the version counts changes ("0.1.172" -> 172).
    ns.build = tonumber(ns.version:match("(%d+)$")) or 0

    local HOW = "To update: close the game and double-click \"Update Meniscus\" in the Meniscus addon folder."
    function ns.NewerVersion()
        local db = MinimalUIDB
        if db and (db.newerBuild or 0) > ns.build then return db.newerVersion or "?", db.newerFrom end
    end
    local function say()
        local nv, from = ns.NewerVersion()
        if nv then
            ns:Print("|cffffd36bA newer version is out:|r " .. nv .. " (you have " .. ns.version .. ")"
                .. (from and (", seen on " .. from) or "") .. ". " .. HOW)
        else
            ns:Print("Version " .. ns.version .. ". No newer version seen from other players. " .. HOW)
        end
    end
    ns.commands = ns.commands or {}
    ns.commands.version = say

    local lastSend = {}
    local function send(channel, target)
        if ns.build == 0 or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
        local key, now = channel .. (target or ""), GetTime()
        if lastSend[key] and now - lastSend[key] < 60 then return end
        lastSend[key] = now
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. ns.build .. ":" .. ns.version, channel, target)
    end
    local function announce()
        if IsInRaid and IsInRaid() then send("RAID") elseif IsInGroup and IsInGroup() then send("PARTY") end
        if IsInGuild and IsInGuild() then send("GUILD") end
    end

    local told = false
    local function heard(msg, sender)
        if type(msg) ~= "string" or (issecretvalue and (issecretvalue(msg) or issecretvalue(sender))) then return end
        local b, ver = msg:match("^V:(%d+):(%S+)")
        b = tonumber(b)
        if not b or not MinimalUIDB then return end
        local who = type(sender) == "string" and (Ambiguate and Ambiguate(sender, "short") or sender) or nil
        if who and who == UnitName("player") then return end
        if b > ns.build then
            if b > (MinimalUIDB.newerBuild or 0) then
                MinimalUIDB.newerBuild, MinimalUIDB.newerVersion, MinimalUIDB.newerFrom = b, ver:sub(1, 20), who
            end
            if not told then told = true; say() end
        elseif b < ns.build and type(sender) == "string" then
            -- Theirs is older: tell them directly, so they hear about it
            -- even if they joined after our last announcement.
            send("WHISPER", sender)
        end
    end

    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("GROUP_ROSTER_UPDATE")
    ef:RegisterEvent("CHAT_MSG_ADDON")
    local first = true
    ef:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
        if event == "CHAT_MSG_ADDON" then
            if prefix == PREFIX then pcall(heard, msg, sender) end
        elseif event == "PLAYER_ENTERING_WORLD" then
            if first then
                first = false
                if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
                    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
                end
                local db = MinimalUIDB
                if db and db.newerBuild and db.newerBuild <= ns.build then
                    db.newerBuild, db.newerVersion, db.newerFrom = nil, nil, nil
                end
                -- A reminder at login while this copy is still behind.
                C_Timer.After(10, function()
                    if ns.NewerVersion() and not told then told = true; say() end
                end)
            end
            C_Timer.After(8, announce)
        else
            C_Timer.After(2, announce)
        end
    end)
end
