local _, ns = ...
local CreateFrame = ns.CreateFrame

-- /men probe: report what this Forever build actually provides.
function ns:RunProbe()
    local P = function(...) ns:Print(...) end
    local version, build, date, toc = GetBuildInfo()
    P("build", version, build, date, "TOC", toc)
    P("WOW_PROJECT_ID", tostring(WOW_PROJECT_ID))

    local apis = {
        "GetSpellInfo", "C_Spell", "GetItemInfo", "C_Item", "C_Traits",
        "C_Timer", "C_AddOns", "Settings", "issecretvalue", "C_GameRules",
        "CombatLogGetCurrentEventInfo", "BackdropTemplateMixin", "EditModeManagerFrame",
        "AddonCompartmentFrame", "LibStub", "C_NamePlate", "C_CooldownViewer", "UnitCastingDuration", "UnitChannelDuration", "UnitHealthPercent", "AbbreviateNumbers", "CurveConstants",
    }
    local have, miss = {}, {}
    for _, n in ipairs(apis) do
        table.insert(_G[n] ~= nil and have or miss, n)
    end
    P("|cff66ff66present|r:", table.concat(have, ", "))
    P("|cffff6666missing|r:", table.concat(miss, ", "))

    local frames = {
        "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "PartyFrame",
        "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "StanceBar",
        "ChatFrame1", "Minimap", "MinimapCluster", "BuffFrame", "CastingBarFrame",
        "PlayerCastingBarFrame", "ObjectiveTrackerFrame", "MicroMenu", "BagsBar",
    }
    local f2, m2 = {}, {}
    for _, n in ipairs(frames) do
        table.insert(_G[n] ~= nil and f2 or m2, n)
    end
    P("|cff66ff66frames|r:", table.concat(f2, ", "))
    P("|cffff6666no frame|r:", table.concat(m2, ", "))
end

-- (0.1.713) Gone from here, about 1,150 lines: the probes whose questions
-- are settled or are answered by the game's own interface source (see
-- CLAUDE.md): bars, scales, auras, uiprobe, menuprobe, dmprobe, friendprobe,
-- guildprobe, countprobe, optprobe, petprobe, barprobe, xpprobe, navprobe,
-- and the ones that ran by themselves at login (the combat log window, the
-- three ping probes). They are in the history at the tag
-- stage/before-probes-removed. What they had saved is dropped once:
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not MinimalUIDB then return end
        for _, k in ipairs({ "uiprobe", "menuprobe", "dmprobe", "friendprobe", "guildprobe", "countprobe", "optprobe",
                             "petprobe", "barprobe", "xpprobe", "navprobe", "allcvars", "clprobe", "pingprobe",
                             "pingprobe2", "pinglog" }) do
            MinimalUIDB[k] = nil
        end
    end)
end

-- /men clicks: toggle printing every click our secure unit buttons receive.
-- If clicking prints nothing, something above the frame is eating the mouse.
ns.commands.clicks = function()
    ns.clickDebug = not ns.clickDebug
    if not ns.__clickHooked then
        ns.__clickHooked = true
        local list = {}
        for _, f in ipairs((ns.modules.UnitFrames or {}).frames or {}) do table.insert(list, f) end
        local O = ns.modules.Orbs
        if O and O.health then table.insert(list, O.health); table.insert(list, O.power) end
        for _, f in ipairs(list) do
            f:HookScript("PreClick", function(self, button, down)
                if not ns.clickDebug then return end
                local mods = (IsShiftKeyDown() and "shift-" or "") .. (IsControlKeyDown() and "ctrl-" or "")
                    .. (IsAltKeyDown() and "alt-" or "")
                ns:Print("click", self:GetName() or "?", mods .. tostring(button), down and "down" or "up",
                    "unit=" .. tostring(self:GetAttribute("unit")),
                    "*type1=" .. tostring(self:GetAttribute("*type1")))
            end)
        end
    end
    ns:Print("Click debug", ns.clickDebug and "on: click your frames" or "off")
end

-- /men keyprobe [KEY]: what a key is bound to, and which frames show up
-- after pressing it. Run it, press the key within 4 seconds; the frames
-- that appeared are printed (alpha, scale, size, strata) and saved to
-- MinimalUIDB.keyprobe.
ns.commands.keyprobe = function(rest)
    local key = (rest and rest ~= "") and rest:upper() or "K"
    local out = {}
    local function add(line) table.insert(out, line); ns:Print(line) end
    local action = GetBindingAction and GetBindingAction(key) or "?"
    add(key .. " is bound to: " .. tostring(action))
    for _, fn in ipairs({ "ToggleProfessionsBook", "ToggleSkillFrame", "ToggleCharacter", "ToggleSpellBook",
                          "ToggleTradeSkill", "ToggleProfessionFrame" }) do
        if _G[fn] then add("  global " .. fn .. " exists") end
    end
    local before = {}
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if not (c.IsForbidden and c:IsForbidden()) and c:IsShown() then before[c] = true end
    end
    local seen = {}
    for name, v in pairs(_G) do
        if type(v) == "table" and type(name) == "string" and name:find("Frame$") and v.IsObjectType
                and not (v.IsForbidden and v:IsForbidden()) then
            local ok, shown = pcall(v.IsShown, v)
            if ok then seen[name] = shown end
        end
    end
    add("Press " .. key .. " now (4 seconds)...")
    C_Timer.After(4, function()
        local n = 0
        local function describe(f, label)
            local p, rel, rp, x, y = f:GetPoint(1)
            local relName = rel and rel.GetName and rel:GetName() or tostring(rel)
            add(string.format("  %s  a=%.2f eff=%.2f scale=%.3f %dx%d strata=%s @%s %s %s %.0f,%.0f",
                label, f:GetAlpha(), f.GetEffectiveAlpha and f:GetEffectiveAlpha() or -1, f:GetScale(),
                f:GetWidth(), f:GetHeight(), f:GetFrameStrata(), tostring(p), tostring(relName), tostring(rp),
                x or 0, y or 0))
        end
        for _, c in ipairs({ UIParent:GetChildren() }) do
            if not (c.IsForbidden and c:IsForbidden()) and c:IsShown() and not before[c] then
                n = n + 1
                describe(c, c:GetName() or "(unnamed)")
            end
        end
        for name, was in pairs(seen) do
            local v = _G[name]
            local ok, shown = pcall(v.IsShown, v)
            if ok and shown ~= was then
                n = n + 1
                add("  " .. name .. (shown and " SHOWED" or " HID"))
                if shown then pcall(describe, v, name) end
            end
        end
        if n == 0 then add("  nothing new appeared") end
        MinimalUIDB.keyprobe = out
    end)
end

-- /men under: name the frame(s) under the mouse (hover a frame, then type it).
ns.commands.under = function()
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    if #foci == 0 then return ns:Print("Nothing under the mouse.") end
    for _, f in ipairs(foci) do
        local chain, cur = {}, f
        for _ = 1, 5 do
            if not cur then break end
            table.insert(chain, (cur.GetName and cur:GetName()) or ("<" .. (cur.GetObjectType and cur:GetObjectType() or "?") .. ">"))
            cur = cur.GetParent and cur:GetParent()
        end
        ns:Print("under mouse:", table.concat(chain, " < "),
            "| mouse enabled:", tostring(f.IsMouseEnabled and f:IsMouseEnabled()))
    end
end

-- /men artprobe : what the thing under the mouse is drawn with. Hover a
-- piece of stock art that survived restyling, type it, and the frame, its
-- regions (atlas / texture, layer, size) and its parents are added to
-- MinimalUIDB.artprobe (read after a reload). "/men artprobe clear" empties it.
ns.commands.artprobe = function(rest)
    if not MinimalUIDB then return end
    if rest and rest:find("clear") then MinimalUIDB.artprobe = nil; return ns:Print("Art recordings cleared.") end
    local store = MinimalUIDB.artprobe or {}
    MinimalUIDB.artprobe = store
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    if #foci == 0 then return ns:Print("Nothing under the mouse.") end
    local function num(v) return (type(v) == "number" and not (issecretvalue and issecretvalue(v))) and string.format("%.0f", v) or "?" end
    local function frameLine(f, tag)
        local keys = {}
        local par = f.GetParent and f:GetParent()
        if par then for k, v in pairs(par) do if v == f and type(k) == "string" then keys[#keys + 1] = k end end end
        return tag .. " [" .. f:GetObjectType() .. "] " .. tostring(f:GetName() or "?") .. " key=" .. table.concat(keys, ",")
            .. " " .. num(f:GetWidth()) .. "x" .. num(f:GetHeight()) .. " lvl " .. tostring(f:GetFrameLevel())
            .. (f:IsShown() and "" or " hidden")
            .. ((f.__muiSkin or f.__muiRow or f.__muiDeepSB or f.__muiDeepArt) and " (seen by skin)" or "")
            .. (f.__muiOurs and " (ours)" or "")
    end
    local function regions(f, out, indent)
        local names = {}
        for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
        for _, r in ipairs({ f:GetRegions() }) do
            pcall(function()
                local what = r:GetObjectType()
                local art = ""
                if what == "Texture" then
                    art = " atlas=" .. tostring(r.GetAtlas and r:GetAtlas()) .. " tex=" .. tostring(r:GetTexture())
                        .. " layer=" .. tostring(r:GetDrawLayer())
                elseif what == "FontString" then
                    local t = r:GetText()
                    art = (type(t) == "string" and not (issecretvalue and issecretvalue(t))) and (' "' .. t:sub(1, 24) .. '"') or ""
                end
                out[#out + 1] = indent .. (names[r] or "#") .. " <" .. what .. ">" .. art .. " " .. num(r:GetWidth()) .. "x"
                    .. num(r:GetHeight()) .. (r:IsShown() and "" or " hidden") .. " a=" .. num((r:GetAlpha() or 0) * 100)
            end)
        end
    end
    for _, f in ipairs(foci) do
        local out = {}
        pcall(function()
            local cur, tag = f, "FOCUS"
            for up = 0, 3 do
                if not cur or cur == UIParent or (cur.IsForbidden and cur:IsForbidden()) then break end
                out[#out + 1] = frameLine(cur, tag)
                regions(cur, out, "    ")
                if up == 0 then
                    for _, c in ipairs({ cur:GetChildren() }) do
                        out[#out + 1] = "  " .. frameLine(c, "child")
                        regions(c, out, "      ")
                    end
                end
                cur = cur.GetParent and cur:GetParent()
                tag = "PARENT" .. (up + 1)
            end
        end)
        store[#store + 1] = out
    end
    ns:Print("Recorded " .. #foci .. " (" .. #store .. " in all). /reload when done.")
end

-- /men winprobe : which Blizzard windows are open right now, and what they
-- are made of. Open a window that needs restyling, run this, and it is
-- added to MinimalUIDB.winprobe (read after a reload). Run it once per
-- window / tab; entries accumulate. "/men winprobe clear" empties the list.
ns.commands.winprobe = function(rest)
    if not MinimalUIDB then return end
    if rest and rest:find("clear") then
        MinimalUIDB.winprobe = nil
        return ns:Print("Window recordings cleared.")
    end
    local store = MinimalUIDB.winprobe or {}
    MinimalUIDB.winprobe = store
    local skip = { WorldFrame = true, UIParent = true }
    local found = {}
    local function describe(f, key, depth, out)
        local ok, line = pcall(function()
            local txt = ""
            if f.GetText then
                local t = f:GetText()
                if type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) then txt = ' "' .. t:sub(1, 30) .. '"' end
            end
            return string.rep("  ", depth) .. key .. " [" .. f:GetObjectType() .. "] " .. tostring(f:GetName() or "?")
                .. (f:IsShown() and "" or " hidden")
                .. string.format(" %.0fx%.0f", f:GetWidth(), f:GetHeight()) .. txt
        end)
        out[#out + 1] = ok and line or (key .. " error")
    end
    local function walk(f, depth, out)
        if depth > 3 or #out > 140 or (f.IsForbidden and f:IsForbidden()) then return end
        local names = {}
        for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
        for _, c in ipairs({ f:GetChildren() }) do
            if c:IsShown() or depth < 2 then
                describe(c, names[c] or "#", depth, out)
                if c:IsShown() then walk(c, depth + 1, out) end
            end
        end
    end
    for _, f in ipairs({ UIParent:GetChildren() }) do
        local ok = pcall(function()
            if f.IsForbidden and f:IsForbidden() then return end
            local name = f:GetName()
            if not name or skip[name] or name:find("^MinimalUI") or name:find("^ChatFrame") then return end
            if not (f:IsShown() and f:IsVisible() and f:IsMouseEnabled()) then return end
            if f:GetWidth() < 280 or f:GetHeight() < 200 or f:GetEffectiveAlpha() < 0.05 then return end
            local strata = f:GetFrameStrata()
            if strata ~= "MEDIUM" and strata ~= "HIGH" and strata ~= "DIALOG" then return end
            local out = {}
            describe(f, "WINDOW", 0, out)
            out[#out + 1] = "  strata=" .. strata .. " at " .. date("%H:%M:%S")
            walk(f, 1, out)
            -- One entry per window + what is selected in it, so tabs don't overwrite each other.
            local n = 1
            while store[name .. " #" .. n] do n = n + 1 end
            store[name .. " #" .. n] = out
            found[#found + 1] = name
        end)
        local _ = ok
    end
    if #found == 0 then
        ns:Print("No Blizzard window found open. Open the one you mean first.")
    else
        ns:Print("Recorded: " .. table.concat(found, ", ") .. ". /reload when you've done them all.")
    end
end

-- Combat facts, for the helpers still to be built (range / mana tint,
-- interruptible casts, aggro ring, swing timer, corpse arrow, mail mark):
-- which of the values they need this client gives plainly, and which are
-- hidden. Recorded on its own into MinimalUIDB.combatprobe, once per
-- session each: a couple of seconds into a fight, the first time your
-- target casts, and when you die. "/men combatprobe" records right now.
do
    local function show(v)
        if issecretvalue and issecretvalue(v) then return "<secret>" end
        return tostring(v)
    end
    local function rec(tag, fn)
        if not MinimalUIDB then return end
        local out = { "at " .. date("%H:%M:%S") }
        local function add(label, ...)
            local t = { ... }
            for i = 1, select("#", ...) do t[i] = show((select(i, ...))) end
            out[#out + 1] = label .. ": " .. table.concat(t, ", ")
        end
        local function try(label, f, ...)
            if type(f) ~= "function" then out[#out + 1] = label .. ": missing"; return end
            local r = { pcall(f, ...) }
            if not r[1] then out[#out + 1] = label .. ": error " .. tostring(r[2]); return end
            local t = {}
            for i = 2, math.min(#r, 12) do t[#t + 1] = show(r[i]) end
            out[#out + 1] = label .. ": " .. (#t > 0 and table.concat(t, ", ") or "(nothing)")
        end
        pcall(fn, add, try)
        MinimalUIDB.combatprobe = MinimalUIDB.combatprobe or {}
        MinimalUIDB.combatprobe[tag] = out
    end
    local function fight(add, try)
        try("UnitThreatSituation player", UnitThreatSituation, "player")
        try("UnitThreatSituation player,target", UnitThreatSituation, "player", "target")
        try("UnitDetailedThreatSituation", UnitDetailedThreatSituation, "player", "target")
        try("UnitIsUnit targettarget,player", UnitIsUnit, "targettarget", "player")
        try("UnitClassification target", UnitClassification, "target")
        try("UnitAttackSpeed player", UnitAttackSpeed, "player")
        try("UnitRangedDamage player", UnitRangedDamage, "player")
        try("UnitPower player", UnitPower, "player")
        try("IsCurrentSpell autoshot 75", C_Spell and C_Spell.IsCurrentSpell, 75)
        try("IsAutoRepeatSpell 75", C_Spell and C_Spell.IsAutoRepeatSpell, 75)
        for slot = 1, 12 do
            local kind, id = GetActionInfo(slot)
            if kind then
                try("slot " .. slot .. " " .. tostring(kind) .. " " .. tostring(id) .. " IsActionInRange", IsActionInRange, slot)
                try("  IsUsableAction", IsUsableAction, slot)
                try("  C_ActionBar.IsUsableAction", C_ActionBar and C_ActionBar.IsUsableAction, slot)
                try("  ActionHasRange", ActionHasRange, slot)
            end
        end
        try("C_Spell.IsSpellInRange 75,target", C_Spell and C_Spell.IsSpellInRange, 75, "target")
    end
    local function cast(add, try)
        try("UnitCastingInfo target", UnitCastingInfo, "target")
        try("UnitChannelInfo target", UnitChannelInfo, "target")
        local nb = _G.TargetFrameSpellBar or (_G.TargetFrame and _G.TargetFrame.spellbar)
        add("TargetFrame spellbar", nb and "exists" or "none", nb and nb.notInterruptible, nb and nb.BorderShield and nb.BorderShield:IsShown())
    end
    local function dead(add, try)
        try("C_DeathInfo.GetCorpseMapPosition", C_DeathInfo and C_DeathInfo.GetCorpseMapPosition, C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
        try("C_Map.GetBestMapForUnit", C_Map and C_Map.GetBestMapForUnit, "player")
        try("C_Map.GetPlayerMapPosition", C_Map and C_Map.GetPlayerMapPosition, C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"), "player")
        try("GetPlayerFacing", GetPlayerFacing)
        try("UnitPosition player", UnitPosition, "player")
        try("C_Map.GetMapWorldSize", C_Map and C_Map.GetMapWorldSize, C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
        try("UnitIsGhost", UnitIsGhost, "player")
    end
    local function misc(add, try)
        try("HasNewMail", HasNewMail)
        try("GetLatestThreeSenders", GetLatestThreeSenders)
        try("GetWeaponEnchantInfo", GetWeaponEnchantInfo)
        try("GetShapeshiftForm", GetShapeshiftForm)
        try("GetNumShapeshiftForms", GetNumShapeshiftForms)
        for i = 1, 8 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not a then break end
            add("  aura", a.name, a.spellId, a.isFromPlayerOrPlayerPet)
        end
    end
    local seen = {}
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_DEAD")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_START", "target")
    pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_CHANNEL_START", "target")
    f:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_DISABLED" then
            if seen.fight then return end
            seen.fight = true
            C_Timer.After(2.5, function() rec("fight", fight) end)
        elseif e == "PLAYER_DEAD" then
            if seen.dead then return end
            seen.dead = true
            C_Timer.After(2, function() rec("dead", dead) end)
            C_Timer.After(12, function() rec("ghost", dead) end)
        elseif e == "PLAYER_ENTERING_WORLD" then
            if seen.misc then return end
            seen.misc = true
            C_Timer.After(6, function() rec("misc", misc) end)
        else
            if seen.cast then return end
            seen.cast = true
            rec("cast", cast)
        end
    end)
    ns.commands = ns.commands or {}
    ns.commands.combatprobe = function()
        rec("fight", fight); rec("cast", cast); rec("dead", dead); rec("misc", misc)
        ns:Print("Combat facts recorded. /reload to save them.")
    end
end

-- /men bug <what went wrong> : a bug report. The note is saved in
-- MinimalUIDB.bugs together with what would otherwise have to be asked for:
-- who and where you are, what is under the mouse, which windows are open,
-- and the Lua errors logged so far this session (the error log itself starts
-- fresh every session, so they are copied in). Reports are kept until
-- "/men bug clear". "/men bug" on its own opens a box to type into.
local function bugContext()
    local c = {}
    local function plain(v)
        if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
        return v
    end
    local function try(fn, ...)
        local ok, a, b = pcall(fn, ...)
        if ok then return plain(a), plain(b) end
    end
    c.at = date("%Y-%m-%d %H:%M:%S")
    c.char = ns.CharKey and ns:CharKey() or "?"
    c.version = (C_AddOns and C_AddOns.GetAddOnMetadata and try(C_AddOns.GetAddOnMetadata, ns.name, "Version")) or "?"
    local _, class = try(UnitClass, "player")
    local _, race = try(UnitRace, "player")
    c.who = table.concat({ tostring(race), tostring(class), "level " .. tostring(try(UnitLevel, "player")) }, " ")
    c.zone = tostring(try(GetRealZoneText)) .. " / " .. tostring(try(GetSubZoneText))
    c.combat = InCombatLockdown() and true or false
    c.group = (IsInRaid and IsInRaid() and "raid") or (IsInGroup and IsInGroup() and "party") or "solo"
    c.pet = UnitExists("pet") and true or false
    c.screen = string.format("%.0fx%.0f scale %.2f", UIParent:GetWidth(), UIParent:GetHeight(), UIParent:GetEffectiveScale())
    local db = MinimalUIDB
    c.profile = db and db.chars and db.chars[c.char] or "Default"
    if UnitExists("target") then
        c.target = tostring(try(UnitName, "target")) .. (UnitIsPlayer("target") == true and " (player)" or " (npc)")
    end
    -- What the mouse is over (and its parents).
    local foci = (GetMouseFoci and GetMouseFoci()) or { GetMouseFocus and GetMouseFocus() }
    local mouse = {}
    for i = 1, math.min(#foci, 3) do
        local chain, cur = {}, foci[i]
        for _ = 1, 5 do
            if not cur then break end
            chain[#chain + 1] = (cur.GetName and cur:GetName()) or ("<" .. (cur.GetObjectType and cur:GetObjectType() or "?") .. ">")
            cur = cur.GetParent and cur:GetParent()
        end
        mouse[#mouse + 1] = table.concat(chain, " < ")
    end
    c.mouse = mouse
    -- Open windows (named, window-sized, taking the mouse).
    local open = {}
    for _, f in ipairs({ UIParent:GetChildren() }) do
        pcall(function()
            if f.IsForbidden and f:IsForbidden() then return end
            local name = f:GetName()
            if not name or name:find("^ChatFrame") or #open >= 12 then return end
            if f:IsShown() and f:IsMouseEnabled() and f:GetWidth() >= 280 and f:GetHeight() >= 200
                and f:GetWidth() < UIParent:GetWidth() * 0.95 and f:GetEffectiveAlpha() > 0.05 then
                open[#open + 1] = name
            end
        end)
    end
    c.windows = open
    -- Errors logged so far this session.
    local errs = {}
    for msg, e in pairs((db and db.errors) or {}) do
        if #errs >= 10 then break end
        errs[#errs + 1] = { msg = tostring(msg):sub(1, 400), count = e.count, time = e.time,
                            stack = type(e.stack) == "string" and e.stack:sub(1, 900) or nil }
    end
    c.errors = errs
    return c
end

local function bugSave(text)
    if not MinimalUIDB then return end
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return ns:Print("Nothing written, so nothing was saved.") end
    local store = MinimalUIDB.bugs or {}
    MinimalUIDB.bugs = store
    if #store >= 100 then table.remove(store, 1) end
    local ok, ctx = pcall(bugContext)
    store[#store + 1] = { text = text:sub(1, 1000), context = ok and ctx or { at = date("%Y-%m-%d %H:%M:%S"), failed = tostring(ctx) } }
    ns:Print("Bug report " .. #store .. " saved. Thanks! It is written to disk at your next /reload or logout.")
end

if StaticPopupDialogs then
    local function boxOf(self)
        return self.EditBox or self.editBox or (self.GetEditBox and self:GetEditBox())
    end
    StaticPopupDialogs["MENISCUS_BUG"] = {
        text = "What went wrong? Say what you were doing and what you expected.",
        button1 = "Save report",
        button2 = CANCEL or "Cancel",
        hasEditBox = true, editBoxWidth = 320, maxLetters = 1000,
        OnShow = function(self) local eb = boxOf(self); if eb then eb:SetText(""); eb:SetFocus() end end,
        OnAccept = function(self) local eb = boxOf(self); if eb then bugSave(eb:GetText()) end end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            bugSave(self:GetText())
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

ns.commands.bug = function(rest, raw)
    if not MinimalUIDB then return end
    local text = raw or rest or ""
    local word = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if word == "clear" then
        MinimalUIDB.bugs = nil
        return ns:Print("Bug reports cleared.")
    elseif word == "list" then
        local store = MinimalUIDB.bugs or {}
        if #store == 0 then return ns:Print("No bug reports saved.") end
        for i, b in ipairs(store) do
            ns:Print(i .. ". " .. tostring(b.context and b.context.at) .. "  " .. tostring(b.text):sub(1, 120))
        end
        return
    elseif word == "" then
        if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs["MENISCUS_BUG"] then
            StaticPopup_Show("MENISCUS_BUG")
        else
            ns:Print("usage: /men bug <what went wrong>")
        end
        return
    end
    bugSave(text)
end

-- /men deepprobe <FrameName> : everything inside one window, to the bottom:
-- child frames and their regions (textures with their atlas, text with what
-- it says and how wide it is), each with the key its parent knows it by.
-- Saved in MinimalUIDB.deepprobe[name]. For restyling a Blizzard window
-- whose parts aren't known. Open the window first.
ns.commands.deepprobe = function(_, raw)
    local name = (raw or ""):match("^%s*(%S+)")
    local root = name and _G[name]
    if not (MinimalUIDB and type(root) == "table" and root.GetObjectType) then
        return ns:Print("/men deepprobe <FrameName>, with the window open. No frame called " .. tostring(name) .. ".")
    end
    local out = {}
    local function s(v) if issecretvalue and issecretvalue(v) then return "<secret>" end return tostring(v) end
    local function keysOf(f)
        local names = {}
        for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
        return names
    end
    local function walk(f, key, depth)
        if #out > 1400 or depth > 9 or (f.IsForbidden and f:IsForbidden()) then return end
        local pad = string.rep("  ", depth)
        pcall(function()
            out[#out + 1] = pad .. key .. " [" .. f:GetObjectType() .. "] " .. s(f:GetName() or "?")
                .. (f:IsShown() and "" or " hidden") .. string.format(" %.0fx%.0f", f:GetWidth(), f:GetHeight())
                .. (f:IsMouseEnabled() and " mouse" or "")
        end)
        local names = keysOf(f)
        pcall(function()
            for _, r in ipairs({ f:GetRegions() }) do
                local line = pad .. "  ~" .. (names[r] or "#") .. " [" .. r:GetObjectType() .. "]"
                    .. (r:IsShown() and "" or " hidden") .. string.format(" %.0fx%.0f", r:GetWidth(), r:GetHeight())
                if r.GetAtlas then line = line .. " atlas=" .. s(r:GetAtlas()) end
                if r.GetTexture and not (r.GetAtlas and r:GetAtlas()) then line = line .. " tex=" .. s(r:GetTexture()) end
                if r.GetText then
                    local t = r:GetText()
                    if issecretvalue and issecretvalue(t) then t = "<secret>" end
                    line = line .. ' text="' .. tostring(t):sub(1, 30) .. '"'
                    if r.GetStringWidth then line = line .. string.format(" strw=%.0f", r:GetStringWidth() or 0) end
                    if r.GetNumPoints and r:GetNumPoints() > 0 then
                        local p, rel, rp, x, y = r:GetPoint(1)
                        line = line .. " at " .. s(p) .. ">" .. s(rel and (names[rel] or (rel.GetName and rel:GetName()) or "?")) .. ":" .. s(rp)
                            .. string.format(" %.0f,%.0f", x or 0, y or 0) .. " pts=" .. r:GetNumPoints()
                    end
                end
                out[#out + 1] = line
            end
        end)
        local shownKids = 0
        for _, c in ipairs({ f:GetChildren() }) do
            -- Lists: a few rows are enough to see what a row is made of.
            if depth >= 3 and not names[c] then
                shownKids = shownKids + 1
                if shownKids <= 4 then walk(c, "#", depth + 1) end
            else
                walk(c, names[c] or "#", depth + 1)
            end
        end
    end
    walk(root, name, 0)
    MinimalUIDB.deepprobe = MinimalUIDB.deepprobe or {}
    MinimalUIDB.deepprobe[name] = out
    ns:Print(name .. ": " .. #out .. " lines recorded. /reload to save them.")
end

-- ── The recorder (a development tool, off unless switched on) ─────────────
-- "/men record on" writes down what happens while you play, as one short
-- line per event in MinimalUIDB.journal[character], to be read between
-- sessions for what the addon could make easier: every cast and failed
-- cast, every red error message, quest steps, where you are and what you
-- are doing every few seconds, fights, deaths, loot, money, bags filling,
-- gear wearing out, and which windows are open for how long.
--   /men record on | off | status | clear
--   /men record mark <words>     a note of your own at this moment
-- A line is "<seconds since the session began>|<what>|<details...>"; each
-- session starts with an "S" line carrying the date and time. Hidden
-- values (health in a fight, some names) are written as "?". Chat is not
-- recorded. The newest 15,000 lines or so are kept, for every character
-- (0.1.527: it was 100,000, and the record had grown to five of the saved
-- file's six megabytes, read and written at every reload). It reaches the
-- disk at the next /reload or logout, like everything else.
do
    local J, t0, running = nil, 0, false
    local MAX, KEEP = 20000, 15000
    -- The newest KEEP lines of a list longer than MAX, starting at a
    -- session's first line where there is one near the cut.
    local function trimmed(list)
        local n = #list
        if n <= MAX then return list end
        local from = n - KEEP + 1
        for i = from, math.min(n, from + 3000) do
            local l = list[i]
            if type(l) == "string" and l:find("^[%d%.]+|S|") then from = i break end
        end
        local keep = {}
        for i = from, n do keep[#keep + 1] = list[i] end
        return keep
    end
    local function hidden(v) return issecretvalue and issecretvalue(v) end
    local function sv(x)
        if x == nil then return "" end
        if hidden(x) then return "?" end
        return tostring(x)
    end
    local function log(kind, ...)
        if not J then return end
        local s = string.format("%.1f", GetTime() - t0) .. "|" .. kind
        for i = 1, select("#", ...) do s = s .. "|" .. sv((select(i, ...))) end
        J[#J + 1] = s
    end
    local function plainNum(v) return type(v) == "number" and not hidden(v) end
    local function try(fn, ...)
        if type(fn) ~= "function" then return end
        local ok, a, b, c, d = pcall(fn, ...)
        if ok then return a, b, c, d end
    end
    local function where()
        local m = C_Map and try(C_Map.GetBestMapForUnit, "player")
        if plainNum(m) then
            local p = try(C_Map.GetPlayerMapPosition, m, "player")
            if p and p.GetXY then
                local x, y = p:GetXY()
                if plainNum(x) and plainNum(y) then
                    return m, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
                end
            end
            return m, "", ""
        end
        return "", "", ""
    end
    local function spell(id)
        local n = plainNum(id) and C_Spell and try(C_Spell.GetSpellName, id)
        return (type(n) == "string" and not hidden(n)) and n or sv(id)
    end
    local function flag(v) return (not hidden(v)) and v and true or false end

    -- What you are doing, as letters: c in combat, m mounted, t on a
    -- flight, d dead or ghost, r resting, i indoors, s stealthed,
    -- w swimming, e eating, k drinking, v moving.
    local function state()
        local s = ""
        if InCombatLockdown() then s = s .. "c" end
        if flag(try(IsMounted)) then s = s .. "m" end
        if flag(try(UnitOnTaxi, "player")) then s = s .. "t" end
        if flag(try(UnitIsDeadOrGhost, "player")) then s = s .. "d" end
        if flag(try(IsResting)) then s = s .. "r" end
        if flag(try(IsIndoors)) then s = s .. "i" end
        if flag(try(IsStealthed)) then s = s .. "s" end
        if flag(try(IsSwimming)) then s = s .. "w" end
        local speed = try(GetUnitSpeed, "player")
        if plainNum(speed) and speed > 0 then s = s .. "v" end
        if not InCombatLockdown() and AuraUtil and AuraUtil.FindAuraByName then
            if try(AuraUtil.FindAuraByName, "Food", "player") then s = s .. "e" end
            if try(AuraUtil.FindAuraByName, "Drink", "player") then s = s .. "k" end
        end
        return s
    end
    local function pct(cur, max)
        if plainNum(cur) and plainNum(max) and max > 0 then return math.floor(cur / max * 100 + 0.5) end
        return "?"
    end

    -- Quest objectives: what moved since last time.
    local objSeen = {}
    local function questSteps()
        local QL = C_QuestLog
        if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.GetQuestObjectives) then return end
        local n = try(QL.GetNumQuestLogEntries)
        if not plainNum(n) then return end
        for i = 1, n do
            local info = try(QL.GetInfo, i)
            if type(info) == "table" and not info.isHeader and plainNum(info.questID) then
                local objs = try(QL.GetQuestObjectives, info.questID)
                if type(objs) == "table" then
                    for k, o in ipairs(objs) do
                        local f = type(o) == "table" and o.numFulfilled
                        if plainNum(f) then
                            local key = info.questID .. ":" .. k
                            local was = objSeen[key]
                            if was ~= nil and was ~= f then
                                local m, x, y = where()
                                log("QP", info.questID, k, f, o.numRequired, o.finished and 1 or 0, o.text, m, x, y)
                            end
                            objSeen[key] = f
                        end
                    end
                end
            end
        end
    end

    -- Windows: ours and the game's main ones, opened and closed.
    local watch, shownNow = nil, {}
    local GAME_WINDOWS = { "WorldMapFrame", "SocialUIFrame", "FriendsFrame", "CharacterFrame", "PlayerSpellsFrame",
        "SettingsPanel", "GameMenuFrame", "CommunitiesFrame", "LFGParentFrame", "CollectionsJournal", "MailFrame",
        "MerchantFrame", "BankFrame", "TaxiFrame", "FlightMapFrame", "AuctionHouseFrame", "TradeFrame",
        "ProfessionsFrame", "ClassTrainerFrame", "QuestFrame", "GossipFrame", "LootFrame", "HelpFrame",
        "AchievementFrame", "EncounterJournal", "ChatConfigFrame", "MacroFrame", "KeyBindingFrame", "AddonList" }
    local function buildWatch()
        watch = {}
        local seen = {}
        for _, n in ipairs(GAME_WINDOWS) do seen[n] = true; watch[#watch + 1] = n end
        -- Our own: the ones the window manager knows (anything else of ours
        -- with a name is a frame on the screen, not a window: the target
        -- frame, the Quick Buff pill...), plus the settings panel.
        if ns.ManagedWindows then
            for n in pairs(ns.ManagedWindows) do
                if not seen[n] then seen[n] = true; watch[#watch + 1] = n end
            end
            for _, n in ipairs({ "MinimalUIPanel", "MinimalUILoot", "MeniscusTidy", "MinimalUIQuickBuff" }) do
                if not seen[n] then seen[n] = true; watch[#watch + 1] = n end
            end
            return
        end
        pcall(function()
            for k, v in pairs(_G) do
                if type(k) == "string" and (k:find("^MinimalUI") or k:find("^Meniscus")) and not seen[k]
                    and type(v) == "table" and type(v.IsShown) == "function" and type(v.GetParent) == "function" then
                    local ok, parent = pcall(v.GetParent, v)
                    if ok and parent == UIParent and not k:find("QuestItem") and not k:find("Reactive") then
                        seen[k] = true
                        watch[#watch + 1] = k
                    end
                end
            end
        end)
    end
    local function windows()
        if not watch then return end
        for _, n in ipairs(watch) do
            local f = _G[n]
            local up = false
            if type(f) == "table" and f.IsShown then
                local ok, v = pcall(f.IsShown, f)
                -- (Blizzard windows we keep open but invisible don't count.)
                up = ok and v and (not f.GetAlpha or f:GetAlpha() > 0.01) or false
            end
            if up ~= (shownNow[n] or false) then
                shownNow[n] = up
                log(up and "W+" or "W-", n)
            end
        end
    end

    local lastP, lastFree, lastDur, tick, ticks = "", nil, nil, 0, 0
    local function sample()
        ticks = ticks + 1
        local m, x, y = where()
        local st = state()
        local hp = pct(try(UnitHealth, "player"), try(UnitHealthMax, "player"))
        local mp = pct(try(UnitPower, "player"), try(UnitPowerMax, "player"))
        local line = sv(m) .. "|" .. sv(x) .. "|" .. sv(y) .. "|" .. st .. "|" .. sv(hp) .. "|" .. sv(mp)
        if line ~= lastP then
            lastP = line
            if ticks % 10 == 0 then
                local fps = try(GetFramerate)
                log("P", m, x, y, st, hp, mp, plainNum(fps) and math.floor(fps) or "")
            else
                log("P", m, x, y, st, hp, mp)
            end
        end
    end
    local function bags()
        if not (C_Container and C_Container.GetContainerNumFreeSlots) then return end
        local free = 0
        for bag = 0, 4 do
            local n = try(C_Container.GetContainerNumFreeSlots, bag)
            if plainNum(n) then free = free + n end
        end
        if free ~= lastFree then lastFree = free; log("BAGS", free) end
    end
    local function durability()
        local low
        for slot = 1, 18 do
            local cur, max = try(GetInventoryItemDurability, slot)
            if plainNum(cur) and plainNum(max) and max > 0 then
                local p = math.floor(cur / max * 100)
                if not low or p < low then low = p end
            end
        end
        if low and low ~= lastDur then lastDur = low; log("DUR", low) end
    end

    local ev = CreateFrame("Frame")
    local GENERIC = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "CORPSE_IN_RANGE", "RESURRECT_REQUEST", "PLAYER_LEVEL_UP",
        "QUEST_REMOVED", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_GREETING",
        "GOSSIP_SHOW", "GOSSIP_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
        "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TRAINER_SHOW", "TRAINER_CLOSED",
        "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TRADE_SHOW",
        "TRADE_CLOSED", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
        "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_EQUIPMENT_CHANGED", "ACTIONBAR_SLOT_CHANGED",
        "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB", "CHARACTER_POINTS_CHANGED", "HEARTHSTONE_BOUND",
        "PLAYER_UPDATE_RESTING", "UNIT_PET", "PET_ATTACK_START", "PET_ATTACK_STOP", "READY_CHECK",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "CONFIRM_XP_LOSS",
        "START_LOOT_ROLL", "CINEMATIC_START", "CINEMATIC_STOP", "PLAYER_FLAGS_CHANGED", "UPDATE_SHAPESHIFT_FORM",
        "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "BAG_NEW_ITEMS_UPDATED", "AUTOEQUIP_BIND_CONFIRM",
        "EQUIP_BIND_CONFIRM", "DELETE_ITEM_CONFIRM", "MIRROR_TIMER_START", "PLAYER_PVP_KILLS_CHANGED" }
    local CHAT = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_SKILL", "CHAT_MSG_COMBAT_XP_GAIN",
        "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_SYSTEM", "CHAT_MSG_OPENING",
        "CHAT_MSG_TRADESKILLS", "CHAT_MSG_PET_INFO" }
    local SPECIAL = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "UI_ERROR_MESSAGE",
        "UI_INFO_MESSAGE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE",
        "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "GROUP_ROSTER_UPDATE", "PLAYER_LOGOUT" }
    local CASTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_DELAYED" }
    local isChat, isCast = {}, {}
    for _, e in ipairs(CHAT) do isChat[e] = true end
    for _, e in ipairs(CASTS) do isCast[e] = true end
    local questDue = false

    local function header()
        local _, class = UnitClass("player")
        log("S", date("%Y-%m-%d %H:%M:%S"), ns.version or "?", ns.CharKey and ns:CharKey() or "?", class,
            try(UnitLevel, "player"), try(GetRealZoneText), try(GetSubZoneText))
    end
    ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4, a5)
        if not running then return end
        if isCast[e] then
            if e == "UNIT_SPELLCAST_SENT" then log("CS", spell(a4), a2)        -- spell, target
            else log(e:sub(16), a1, spell(a3)) end                            -- START / SUCCEEDED / FAILED ... unit, spell
        elseif isChat[e] then
            -- (Other players' "creates X" lines were 60% of a recording.)
            if e == "CHAT_MSG_TRADESKILLS" and not (type(a1) == "string" and not hidden(a1) and a1:find("^You ")) then return end
            log(e:sub(10), a1)
        elseif e == "UI_ERROR_MESSAGE" or e == "UI_INFO_MESSAGE" then
            log(e == "UI_ERROR_MESSAGE" and "ERR" or "INFO", a2, a1)
        elseif e == "UNIT_COMBAT" then
            log("HIT", a2, a3, a4, a5)                                        -- action, indicator, amount, school
        elseif e == "PLAYER_TARGET_CHANGED" then
            if try(UnitExists, "target") then
                log("TGT", try(UnitName, "target"), try(UnitLevel, "target"), try(UnitClassification, "target"),
                    try(UnitReaction, "target", "player"), flag(try(UnitIsPlayer, "target")) and "player" or "npc",
                    flag(try(UnitIsDead, "target")) and "dead" or "")
            else
                log("TGT")
            end
        elseif e == "QUEST_ACCEPTED" then
            local id = plainNum(a2) and a2 or a1
            local m, x, y = where()
            log("QA", id, C_QuestLog and try(C_QuestLog.GetTitleForQuestID, id), m, x, y)
        elseif e == "QUEST_TURNED_IN" then
            local m, x, y = where()
            log("QT", a1, a2, a3, m, x, y)                                    -- quest, xp, money
        elseif e == "QUEST_LOG_UPDATE" then
            if not questDue then
                questDue = true
                C_Timer.After(0.5, function() questDue = false; if running then pcall(questSteps) end end)
            end
        elseif e == "PLAYER_XP_UPDATE" then
            log("XP", try(UnitXP, "player"), try(UnitXPMax, "player"), try(GetXPExhaustion))
        elseif e == "PLAYER_MONEY" then
            log("MONEY", try(GetMoney))
        elseif e == "BAG_UPDATE_DELAYED" then
            pcall(bags)
        elseif e == "UPDATE_INVENTORY_DURABILITY" then
            pcall(durability)
        elseif e == "GROUP_ROSTER_UPDATE" then
            log("GROUP", try(GetNumGroupMembers), flag(try(IsInRaid)) and "raid" or "party")
        elseif e == "ZONE_CHANGED_NEW_AREA" or e == "PLAYER_ENTERING_WORLD" then
            local m, x, y = where()
            local inInst, kind = try(IsInInstance)
            log(e == "PLAYER_ENTERING_WORLD" and "WORLD" or "ZONE", try(GetRealZoneText), try(GetSubZoneText), m, x, y,
                flag(inInst) and sv(kind) or "")
        elseif e == "PLAYER_LOGOUT" then
            log("END", date("%H:%M:%S"))
        else
            log(e, a1, a2, a3, a4)
        end
    end)

    local ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(_, dt)
        tick = tick + dt
        if tick < 1 then return end
        tick = 0
        pcall(windows)
        ticks = ticks + 0
        if math.floor(GetTime()) % 3 == 0 then pcall(sample) end
    end)

    local wrapped = false
    local function start()
        if running or not MinimalUIDB then return end
        MinimalUIDB.journal = MinimalUIDB.journal or {}
        local key = ns.CharKey and ns:CharKey() or "?"
        -- Keep the newest lines, of every character's record.
        for k, list in pairs(MinimalUIDB.journal) do
            if type(list) == "table" then MinimalUIDB.journal[k] = trimmed(list) end
        end
        J = MinimalUIDB.journal[key]
        if not J then J = {}; MinimalUIDB.journal[key] = J end
        t0 = GetTime()
        running = true
        header()
        for _, list in ipairs({ GENERIC, CHAT, SPECIAL }) do
            for _, e in ipairs(list) do pcall(ev.RegisterEvent, ev, e) end
        end
        for _, e in ipairs(CASTS) do pcall(ev.RegisterUnitEvent, ev, e, "player", "pet") end
        pcall(ev.RegisterUnitEvent, ev, "UNIT_COMBAT", "player")
        -- The addon's own warnings (low ammunition, capped skill, rare...).
        if not wrapped and type(ns.FloatWarning) == "function" then
            wrapped = true
            local orig = ns.FloatWarning
            ns.FloatWarning = function(tex, label, note, ...)
                if running then log("WARN", label, note) end
                return orig(tex, label, note, ...)
            end
        end
        -- Action buttons, where the client tells us (which slot, what's on it).
        if not ev.hookedAct and type(_G.UseAction) == "function" then
            ev.hookedAct = true
            hooksecurefunc("UseAction", function(slot)
                if running and plainNum(slot) then log("ACT", slot, try(GetActionInfo, slot)) end
            end)
        end
        C_Timer.After(8, function() if running then pcall(buildWatch); pcall(questSteps); pcall(bags); pcall(durability) end end)
        ticker:Show()
    end
    local function stop()
        if not running then return end
        log("END", date("%H:%M:%S"))
        running = false
        ev:UnregisterAllEvents()
        ticker:Hide()
    end
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function()
        if not MinimalUIDB then return end
        if MinimalUIDB.record then pcall(start)
        elseif type(MinimalUIDB.journal) == "table" then -- (not recording: an old long record is still cut down)
            for k, list in pairs(MinimalUIDB.journal) do
                if type(list) == "table" then MinimalUIDB.journal[k] = trimmed(list) end
            end
        end
    end)

    ns.commands = ns.commands or {}
    ns.commands.record = function(rest, raw)
        if not MinimalUIDB then return end
        local verb, words = (raw or rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
        verb = (verb or ""):lower()
        if verb == "on" then
            MinimalUIDB.record = true
            start()
            ns:Print("Recording. It keeps going across sessions until /men record off; /reload writes it to disk.")
        elseif verb == "off" then
            MinimalUIDB.record = nil
            stop()
            ns:Print("Recording stopped. What was recorded is kept (/men record clear empties it).")
        elseif verb == "clear" then
            local was = running
            stop()
            MinimalUIDB.journal = nil
            J = nil
            if was then start() end
            ns:Print("Recording emptied" .. (was and ", and started afresh." or "."))
        elseif verb == "mark" then
            if not running then return ns:Print("Not recording: /men record on first.") end
            local m, x, y = where()
            log("MARK", words, m, x, y)
            ns:Print("Noted: " .. (words ~= "" and words or "(a mark)"))
        else
            local n = 0
            for _, list in pairs(MinimalUIDB.journal or {}) do n = n + #list end
            ns:Print("Recorder: " .. (running and "on" or "off") .. ", " .. n .. " lines kept.  /men record on | off | clear | mark <words>")
        end
    end
end

-- ── What a class and race start from, level by level ─────────────────────
-- For the inspect window's estimate of someone else's attributes (their
-- gear's bonuses on top of what their class and race have at that level,
-- which the game tells nobody but them). The published tables are for the
-- classic game and may not hold here, so your own are written down as you
-- level, to check a table against:
--   MinimalUIDB.baseStats["CLASS|Race"][level] = "str,agi,sta,int,spi"
-- (the first number UnitStat gives: without gear or buffs). It also notes,
-- once, whether the game answers UnitStat for another player (statdiag:
-- kinds of answer only, nobody's name).
do
    local function hidden(v) return issecretvalue and issecretvalue(v) end
    local function note()
        if not (MinimalUIDB and UnitStat) then return end
        local _, class = UnitClass("player")
        local _, race = UnitRace("player")
        local level = UnitLevel("player")
        if type(class) ~= "string" or type(race) ~= "string" or type(level) ~= "number" or hidden(level) then return end
        local parts = {}
        for i = 1, 5 do
            -- (The first number is the total here, not the base: Orc
            -- warrior 18 read 62 Strength, gear and all. What is left when
            -- the bonuses are taken off is the base.)
            local ok, _, eff, pos, neg = pcall(UnitStat, "player", i)
            if not ok or type(eff) ~= "number" or hidden(eff) or type(pos) ~= "number" or hidden(pos)
                or type(neg) ~= "number" or hidden(neg) then return end
            parts[i] = tostring(eff - pos - neg)
        end
        MinimalUIDB.baseStats = MinimalUIDB.baseStats or {}
        local key = class .. "|" .. race
        MinimalUIDB.baseStats[key] = MinimalUIDB.baseStats[key] or {}
        MinimalUIDB.baseStats[key][level] = table.concat(parts, ",")
        -- What the race has of each resistance before gear and buffs (fire,
        -- nature, frost, shadow, arcane), for the same estimate.
        if UnitResistance then
            local r = {}
            for school = 2, 6 do
                local ok, rb = pcall(UnitResistance, "player", school)
                if not ok or type(rb) ~= "number" or hidden(rb) then r = nil break end
                r[#r + 1] = tostring(rb)
            end
            if r then
                MinimalUIDB.baseResists = MinimalUIDB.baseResists or {}
                MinimalUIDB.baseResists[race] = table.concat(r, ",")
            end
        end
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    local asked = false
    f:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_TARGET_CHANGED" then
            if asked or not MinimalUIDB or not UnitStat then return end
            local okP, isP = pcall(UnitIsPlayer, "target")
            if not (okP and isP and not hidden(isP)) or UnitIsUnit("target", "player") then return end
            asked = true
            local ok, a, b = pcall(UnitStat, "target", 1)
            MinimalUIDB.statdiag = "ok " .. tostring(ok) .. ", " .. (hidden(a) and "hidden" or type(a))
                .. (type(a) == "number" and not hidden(a) and (a > 0 and " >0" or " 0") or "")
                .. ", " .. (hidden(b) and "hidden" or type(b))
            return
        end
        -- (A moment after: the new level's numbers are not there at once.)
        C_Timer.After(e == "PLAYER_LOGIN" and 5 or 2, function() pcall(note) end)
    end)
end

-- ── Do buffs say how much they give? ─────────────────────────────────────
-- For the inspect window (someone's resistances and attributes from their
-- buffs): what the game hands over for a buff besides its name. Written
-- once a session for you, and once for the first other player you target
-- out of a fight: MinimalUIDB.auravals[who] = lines of
--   "<spell id> <name> | points: ... | tip: <the tooltip's own words>"
-- (spells only: nobody's name is kept).
do
    local function hidden(v) return issecretvalue and issecretvalue(v) end
    local function show(v)
        if v == nil then return "nil" end
        if hidden(v) then return "hidden" end
        return tostring(v)
    end
    local function dump(unit, who)
        local U = C_UnitAuras
        if not (MinimalUIDB and U and U.GetAuraDataByIndex) then return end
        local out = {}
        for i = 1, 16 do
            local ok, a = pcall(U.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or type(a) ~= "table" then break end
            local pts = "none"
            if hidden(a.points) then pts = "hidden"
            elseif type(a.points) == "table" then
                local p = {}
                for n = 1, math.min(#a.points, 6) do p[n] = show(a.points[n]) end
                pts = #p > 0 and table.concat(p, ",") or "empty"
            end
            local tip = "no tooltip call"
            local T = C_TooltipInfo
            if T and T.GetUnitBuffByAuraInstanceID and a.auraInstanceID ~= nil then
                local ok2, d = pcall(T.GetUnitBuffByAuraInstanceID, unit, a.auraInstanceID)
                if not ok2 then tip = "error"
                elseif type(d) ~= "table" or type(d.lines) ~= "table" then tip = "nothing"
                else
                    local words = {}
                    for n = 2, math.min(#d.lines, 4) do
                        local l = d.lines[n]
                        words[#words + 1] = show(l and l.leftText)
                    end
                    tip = table.concat(words, " / ")
                end
            end
            out[#out + 1] = show(a.spellId) .. " " .. show(a.name) .. " | points: " .. pts .. " | tip: " .. tip
        end
        MinimalUIDB.auravals = MinimalUIDB.auravals or {}
        MinimalUIDB.auravals[who] = out
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    local did = false
    f:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_LOGIN" then
            C_Timer.After(8, function() pcall(dump, "player", "you") end)
        elseif not did and not InCombatLockdown() then
            local ok, isP = pcall(UnitIsPlayer, "target")
            if ok and not hidden(isP) and isP and not UnitIsUnit("target", "player") then
                did = true
                pcall(dump, "target", "another player")
            end
        end
    end)
end

-- ── Is it really there? ───────────────────────────────────────────────────
-- The game's source and generated docs (see CLAUDE.md) are shared between
-- its flavours: a call listed there may still be missing on this client.
-- Once per session, a few seconds in: which of the calls that the review of
-- 2026-11-25 wants to build on exist here. MinimalUIDB.apicheck.
do
    local names = {
        "C_PetInfo.GetPetHappiness", "C_PetInfo.GetPetFoodTypes", "C_PetInfo.CanPetEatItem",
        "Enum.DamageMeterType", "Enum.DamageMeterType.EnemyDamageTaken", "Enum.DamageMeterType.DamageTaken",
        "C_DamageMeter.GetCombatSessionFromType", "C_DamageMeter.GetCombatSessionSourceFromType",
        "C_DeathRecap.GetRecapEvents", "C_Secrets.ShouldUnitIdentityBeSecret", "C_Secrets.HasSecretRestrictions",
        "C_Secrets.ShouldCooldownsBeSecret", "C_Secrets.GetSpellAuraSecrecy", "C_Secrets.ShouldUnitPowerBeSecret",
        "C_RestrictedActions.IsAddOnRestrictionActive", "Enum.AddOnRestrictionType", "C_CombatLog.IsCombatLogRestricted",
        "C_SwingTimer", "C_SkillInfo.GetNumSkillLines", "C_SkillInfo.GetSkillLineInfo",
        "C_Spell.GetSpellCooldownDuration", "C_ActionBar.GetActionCooldownDuration",
        "C_SpellBook.GetSpellBookItemCooldownDuration", "C_CurveUtil.EvaluateColorFromBoolean",
        "C_TooltipInfo.GetTrainerService", "C_TradeSkillUI.GetSkillLineForGear", "C_Item.RequestLoadItemDataByID",
        "ScrollUtil.AddAcquiredFrameCallback", "EventRegistry.RegisterCallback", "ActionButton_UpdateRangeIndicator",
        "scrubsecretvalues", "canaccessvalue", "hasanysecretvalues", "GetRealmID", "GetNormalizedRealmName",
        "C_Ping.SendMacroPing", "PingUtil.SendMacroPing", "C_UnitAuras.GetRefreshCarryOverDuration",
    }
    local function find(path)
        local v = _G
        for part in path:gmatch("[^.]+") do
            if type(v) ~= "table" then return nil end
            v = v[part]
        end
        return v
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        C_Timer.After(4, function()
            if not MinimalUIDB then return end
            local out = {}
            for _, n in ipairs(names) do
                local v = find(n)
                out[#out + 1] = n .. ": " .. (v == nil and "MISSING" or (type(v) == "number" and tostring(v) or type(v)))
            end
            local function widget(label, obj, methods)
                for _, m in ipairs(methods) do
                    out[#out + 1] = label .. ":" .. m .. ": " .. (type(obj[m]) == "function" and "function" or "MISSING")
                end
            end
            local tex = f:CreateTexture()
            widget("Texture", tex, { "SetVertexColorFromBoolean", "SetAlphaFromBoolean", "SetRadialProgressBarPercent" })
            local okC, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
            if okC and cd then widget("Cooldown", cd, { "SetCooldownFromDurationObject" }) end
            local okM, scene = pcall(CreateFrame, "ModelScene", nil, f)
            if okM and scene and scene.CreateActor then
                local okA, actor = pcall(scene.CreateActor, scene)
                if okA and actor then widget("Actor", actor, { "SetModelByUnit", "SetModelByCreatureDisplayID", "TryOn", "SetCustomRace" }) end
            end
            local function ask(label, fn, ...)
                if type(fn) ~= "function" then return end
                local r = { pcall(fn, ...) }
                for i = 1, #r do
                    if issecretvalue and issecretvalue(r[i]) then r[i] = "<secret>" else r[i] = tostring(r[i]) end
                end
                out[#out + 1] = label .. " -> " .. table.concat(r, ", ")
            end
            ask("C_PetInfo.GetPetHappiness()", find("C_PetInfo.GetPetHappiness"))
            ask("C_PetInfo.GetPetFoodTypes()", find("C_PetInfo.GetPetFoodTypes"))
            ask("C_Secrets.ShouldCooldownsBeSecret()", find("C_Secrets.ShouldCooldownsBeSecret"))
            ask("GetRealmName() is empty", function() return (GetRealmName() or "") == "" end)
            ask("GetRealmID() is a number above 0", function() local id = GetRealmID and GetRealmID() return type(id) == "number" and id > 0 end)
            MinimalUIDB.apicheck = out
        end)
    end)
end
