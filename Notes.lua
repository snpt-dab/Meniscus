local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Patch notes: what changed between the version you last ran and this one,
-- shown once after an update.
--
-- THE RULE (CLAUDE.md, "Patch notes"): every version a player could notice
-- gets an entry in NOTES below, under its number (the last part of the
-- version: 0.1.717 is 717), written for a player: what is different on
-- screen, not how. dist/build.py refuses to build a version that has
-- neither an entry nor a place in QUIET (versions with nothing to notice:
-- tests, notes, a tool of ours).
--
-- How the window picks: MinimalUIDB.notesSeen is the last version whose
-- notes you closed (one for the whole account). After an update it shows
-- every entry above that number, up to the version you now run, newest
-- first; "Got it" moves the number up. A first install shows nothing.
-- "/men notes" shows the last ten versions' notes at any time;
-- "/men notes all" shows every one there is.

ns.NOTES = {
    [717] = {
        "New: this window. After an update it lists what changed since the version you had.",
        "Bestiary: a creature's attacks on you are now learned from the game's damage meter (they were not being picked up).",
    },
    [716] = {
        "Fixed a cause of the game refusing to move its stance bar or show bar buttons during a fight.",
    },
    [715] = {
        "Bestiary: a dungeon creature known only by name, or only from its loot, is joined into one entry as soon as you fight it.",
    },
    [714] = {
        "Chat: a whisper opened as its own tab no longer has a black block hanging over the left edge; its tab and typing field match the others.",
    },
    [713] = {
        "Quest rewards no longer say \"Can't use: Retrieving item information\" while an item is still loading.",
        "Settings: old diagnostic buttons removed.",
    },
    [712] = {
        "Escape with the bags open closes the bags without also opening the game menu.",
    },
    [711] = {
        "Quick Cure: the old display was removed; the one drawn by the game (which works during a fight) is the only one.",
    },
    [710] = {
        "Paladins: whichever seal you last cast gets the recast ring, not only Seal of Righteousness.",
        "Level-up card: hunters are told about the pet quest at level 10.",
        "Right-click menus are restyled the moment they open; group frames fade at once when someone goes out of range.",
    },
    [709] = {
        "Cast bars: an enemy's cast is coloured from the first moment, and grey when it can't be interrupted.",
        "The Quick Buff pill no longer draws over the world map.",
    },
    [708] = {
        "Crafted upgrades for your other characters only suggest crafters of the same faction.",
    },
    [707] = {
        "Roster: another character's sheet shows a figure of its race in its gear where the game allows it. \"/men figure off\" shows the class emblem instead.",
    },
    [706] = {
        "Bestiary: a creature's health is learned from the game's damage meter, in a group as well as alone.",
    },
    [705] = {
        "Target frame: buffs and debuffs are drawn by the game in our look, so they keep updating during a fight.",
    },
    [704] = {
        "Hunter pets: what your pet eats comes from the game itself, not from what feeding had taught the addon.",
    },
    [703] = {
        "Hunter pets: the mood word comes from the game itself and changes at once.",
    },
}
-- Versions with nothing a player would notice: [number] = true.
ns.NOTES_QUIET = {
}

local W, FOOTER_H, MAX_LIST = 480, 52, 380
local TOP = (ns.SHELL_H or 92) + 14
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local win
local freshInstall = false

local function current()
    return ns.build or 0
end

-- The versions to show: above `from`, up to this one, newest first.
local function pick(from, most)
    local list = {}
    for n in pairs(ns.NOTES) do
        if n > from and n <= math.max(current(), from) then list[#list + 1] = n end
    end
    table.sort(list, function(a, b) return a > b end)
    if most then for i = #list, most + 1, -1 do list[i] = nil end end
    return list
end
ns.NotesPick = pick

local function build()
    win = CreateFrame("Frame", "MinimalUINotes", UIParent)
    win:SetSize(W, TOP + 100 + FOOTER_H)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUINotes")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win)
    win.shell:SetTitle("What's new")
    win.shell:SetIcon("Interface/Icons/INV_Misc_Note_01")
    win.shell:SetRing(T.accent)

    local sf = CreateFrame("ScrollFrame", nil, win)
    sf:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -TOP)
    sf:SetPoint("TOPRIGHT", win, "TOPRIGHT", -22, -TOP)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(W - 40, 10)
    sf:SetScrollChild(child)
    win.sf, win.child, win.lines = sf, child, {}
    win.thumb = win:CreateTexture(nil, "OVERLAY")
    win.thumb:SetWidth(3)
    win.thumb:SetColorTexture(0.32, 0.32, 0.36, 1)
    local function place()
        local range = math.max(0, win.contentH - sf:GetHeight())
        local at = math.max(0, math.min(win.at or 0, range))
        win.at = at
        sf:SetVerticalScroll(at)
        if range <= 0 then win.thumb:Hide() return end
        local h = sf:GetHeight()
        local size = math.max(24, h * h / win.contentH)
        win.thumb:Show()
        win.thumb:SetHeight(size)
        win.thumb:ClearAllPoints()
        win.thumb:SetPoint("TOPRIGHT", win, "TOPRIGHT", -10, -(TOP + (h - size) * at / range))
    end
    win.place = place
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, d) win.at = (win.at or 0) - d * 40; place() end)

    win.footer = ns:CreateFooter(win, FOOTER_H)
    win.ok = ns.Pill(win.footer, "Got it", function()
        if MinimalUIDB and win.upTo then MinimalUIDB.notesSeen = math.max(MinimalUIDB.notesSeen or 0, win.upTo) end
        win:Hide()
    end, { h = 26, primary = true, minW = 90 })
    win.ok:SetPoint("RIGHT", win.footer, "RIGHT", -14, 0)
    win.hint = win.footer:CreateFontString(nil, "OVERLAY")
    ns:SetFont(win.hint, 10, "")
    win.hint:SetTextColor(unpack(T.textDim))
    win.hint:SetPoint("LEFT", win.footer, "LEFT", 16, 0)
    win.hint:SetText("/men notes shows these again")
end

local function line(i)
    local fs = win.lines[i]
    if not fs then
        fs = win.child:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        win.lines[i] = fs
    end
    fs:Show()
    return fs
end

-- list: version numbers, newest first. upTo: what "Got it" records (nil for a look back).
local function show(list, subtitle, upTo)
    if InCombatLockdown() then return false end
    if not win then build() end
    win.upTo = upTo
    win.shell:SetSubtitle(subtitle)
    local cw = W - 40
    local y, i = 0, 0
    for _, n in ipairs(list) do
        i = i + 1
        local head = line(i)
        ns:SetFont(head, 12, "", true)
        head:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        head:SetWidth(cw)
        head:SetText("0.1." .. n)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", win.child, "TOPLEFT", 0, -y)
        y = y + 18
        for _, text in ipairs(ns.NOTES[n]) do
            i = i + 1
            local fs = line(i)
            ns:SetFont(fs, 11, "")
            fs:SetTextColor(unpack(T.text))
            fs:SetWidth(cw - 14)
            fs:SetText("\194\183  " .. text)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", win.child, "TOPLEFT", 8, -y)
            y = y + math.max(14, (fs:GetStringHeight() or 14)) + 5
        end
        y = y + 9
    end
    for k = i + 1, #win.lines do win.lines[k]:Hide() end
    win.contentH = math.max(20, y - 9)
    win.child:SetHeight(win.contentH)
    local listH = math.min(win.contentH, MAX_LIST)
    win.sf:SetHeight(listH)
    win:SetHeight(TOP + listH + 12 + FOOTER_H)
    win.at = 0
    win:Show()
    win.place()
    return true
end

-- After an update: everything since the notes last closed.
local function afterUpdate()
    local db = MinimalUIDB
    if not db then return end
    local cur, seen = current(), db.notesSeen
    if cur <= 0 then return end
    if type(seen) ~= "number" then
        -- Never shown here. A first install has nothing to catch up on; a
        -- copy that was already in use gets what there is.
        if freshInstall then db.notesSeen = cur return end
        seen = 0
    end
    if seen >= cur then db.notesSeen = cur return end -- (also a step back to an older copy)
    local list = pick(seen)
    if #list == 0 then db.notesSeen = cur return end
    local from = seen > 0 and ("since 0.1." .. seen) or "the latest changes"
    if not show(list, "Meniscus " .. tostring(ns.version) .. "   \194\183   " .. from, cur) then
        return false
    end
end

ns.commands = ns.commands or {}
ns.commands.notes = function(rest)
    local all = type(rest) == "string" and rest:find("all")
    local list = pick(0, (not all) and 10 or nil)
    if #list == 0 then return ns:Print("No patch notes in this version.") end
    if not show(list, all and "every version with notes" or "the last ten versions with notes", nil) then
        ns:Print("Patch notes can't be opened in a fight.")
    end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    local owed, done = false, false
    f:SetScript("OnEvent", function(_, e, name)
        if e == "ADDON_LOADED" then
            if name ~= ns.name then return end
            -- (A saved table with none of what play leaves in it has never
            -- been played.)
            local db = MinimalUIDB
            freshInstall = type(db) ~= "table" or (db.chatSize12 == nil and db.perf == nil and db.bestiary == nil and db.roster == nil)
        elseif e == "PLAYER_ENTERING_WORLD" then
            if done then return end
            done = true
            C_Timer.After(4, function()
                local ok, res = pcall(afterUpdate)
                if ok and res == false then owed = true end
            end)
        elseif owed then
            owed = false
            C_Timer.After(1, function()
                local ok, res = pcall(afterUpdate)
                if ok and res == false then owed = true end
            end)
        end
    end)
end
