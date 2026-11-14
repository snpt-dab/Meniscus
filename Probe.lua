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

-- /men bars: inspect the default action bar structure on this build.
ns.commands.bars = function()
    local P = function(...) ns:Print(...) end
    local function has(n) return _G[n] ~= nil end

    local names = {
        "MainActionBar", "ActionButton1", "ActionButton12",
        "MultiBarBottomLeft", "MultiBarBottomLeftButton1",
        "MultiBarBottomRight", "MultiBarBottomRightButton1",
        "MultiBarRight", "MultiBarRightButton1", "MultiBarLeft", "MultiBarLeftButton1",
        "MultiBar5", "MultiBar5Button1", "MultiBar6", "MultiBar7",
        "StanceBar", "StanceButton1", "PetActionBar", "PetActionButton1",
        "OverrideActionBar", "PossessActionBar", "MainMenuBarVehicleLeaveButton",
        "ExtraActionBarFrame", "ActionBarController", "SpellFlyout",
    }
    local have, miss = {}, {}
    for _, n in ipairs(names) do table.insert(has(n) and have or miss, n) end
    P("|cff66ff66exist|r:", table.concat(have, ", "))
    P("|cffff6666absent|r:", table.concat(miss, ", "))

    local b = _G.ActionButton1
    if b then
        local parent = b:GetParent()
        P("ActionButton1: size", b:GetWidth(), "x", b:GetHeight(),
          "parent", parent and parent:GetName() or "?",
          "protected", tostring(b:IsProtected()),
          "action", tostring(b.action), "type", tostring(b:GetObjectType()))
        local parts = {}
        for _, k in ipairs({ "icon", "Icon", "cooldown", "Cooldown", "HotKey", "Count", "Name",
                             "Border", "NormalTexture", "FlyoutBorder", "SlotBackground",
                             "IconMask", "SlotArt", "checkedTexture" }) do
            if b[k] ~= nil then table.insert(parts, k) end
        end
        P("ActionButton1 fields:", table.concat(parts, ", "))
        P("ActionButton1 template mixin SetNormalTexture:", tostring(b.SetNormalTexture ~= nil),
          "GetNormalTexture:", tostring(b.GetNormalTexture ~= nil))
    end

    local bar = _G.MainActionBar
    if bar then
        P("MainActionBar: protected", tostring(bar:IsProtected()),
          "size", bar:GetWidth(), "x", bar:GetHeight(),
          "points", bar:GetNumPoints(),
          "children", select("#", bar:GetChildren()),
          "UpdateGridLayout", tostring(bar.UpdateGridLayout ~= nil),
          "system", tostring(bar.system))
    end

    -- Secure handler support (paging / state drivers / snippets).
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "SecureHandlerStateTemplate")
    P("SecureHandlerStateTemplate frame:", tostring(ok))
    if ok and f then
        P("RegisterStateDriver:", tostring(RegisterStateDriver ~= nil),
          "RegisterAttributeDriver:", tostring(RegisterAttributeDriver ~= nil))
        local ok2, err = pcall(function() f:Execute("local x = 1") end)
        P("secure snippet Execute:", tostring(ok2), ok2 and "" or tostring(err))
        local ok3, err3 = pcall(function()
            f:SetAttribute("_onstate-test", "return")
            f:SetAttribute("_onstate-page", [[ self:SetAttribute("seen", newstate) ]])
        end)
        P("secure state attribute set:", tostring(ok3), ok3 and "" or tostring(err3))
    end

    P("C_ActionBar:", tostring(C_ActionBar ~= nil),
      "GetBonusBarOffset:", tostring(GetBonusBarOffset and GetBonusBarOffset() or "n/a"),
      "InCombat:", tostring(InCombatLockdown()))
end

-- /men scales: show where button scaling comes from (diagnostic).
ns.commands.scales = function()
    for _, n in ipairs({ "ActionButton1", "MultiBarBottomLeftButton1", "MultiBarBottomRightButton1" }) do
        local b = _G[n]
        if b then
            local p = b:GetParent()
            ns:Print(n, "scale", string.format("%.3f", b:GetScale()),
                "parent", p and (p:GetName() or "?") or "none",
                "parentScale", p and string.format("%.3f", p:GetScale()) or "-",
                "effective", string.format("%.3f", b:GetEffectiveScale()),
                "UIParent", string.format("%.3f", UIParent:GetEffectiveScale()),
                "size", string.format("%.1f", b:GetWidth()))
        end
    end
end

-- /men auras: what aura data looks like on this build (run with a target that
-- has buffs/debuffs; try once out of combat and once in combat).
ns.commands.auras = function()
    local P = function(...) ns:Print(...) end
    local function show(v)
        local t = type(v)
        if t == "nil" then return "nil" end
        if issecretvalue(v) then return "SECRET(" .. t .. ")" end
        return tostring(v)
    end

    local U = C_UnitAuras or {}
    local apis = {}
    for _, k in ipairs({ "GetAuraDataByIndex", "GetAuraDataByAuraInstanceID", "GetAuraSlots",
                         "GetAuraDuration", "GetUnitAuras", "GetAuraApplicationDisplayCount",
                         "IsAuraFilteredOutByInstanceID", "GetBuffDataByIndex", "GetDebuffDataByIndex" }) do
        table.insert(apis, k .. "=" .. tostring(U[k] ~= nil))
    end
    P("C_UnitAuras:", table.concat(apis, " "))
    local cd = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    P("AuraUtil.ForEachAura:", tostring(AuraUtil and AuraUtil.ForEachAura ~= nil),
      "Cooldown:SetCooldownFromDurationObject:", tostring(cd.SetCooldownFromDurationObject ~= nil),
      "InCombat:", tostring(InCombatLockdown()))

    local fields = { "name", "icon", "applications", "duration", "expirationTime", "spellId",
                     "auraInstanceID", "sourceUnit", "isFromPlayerOrPlayerPet", "dispelName",
                     "isStealable", "canApplyAura", "isBossAura" }
    for _, unit in ipairs({ "player", "target" }) do
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            local ok, a = pcall(U.GetAuraDataByIndex, unit, 1, filter)
            if ok and a then
                local parts = {}
                for _, k in ipairs(fields) do table.insert(parts, k .. "=" .. show(a[k])) end
                P(unit, filter, table.concat(parts, " "))
                if U.GetAuraDuration and type(a.auraInstanceID) ~= "nil" then
                    local ok2, d = pcall(U.GetAuraDuration, unit, a.auraInstanceID)
                    P("  GetAuraDuration:", tostring(ok2), ok2 and type(d) or tostring(d))
                end
            else
                P(unit, filter, ok and "(no aura at index 1)" or ("error: " .. tostring(a)))
            end
        end
    end

    local bf = _G.BuffFrame
    if bf then
        local keys = {}
        for _, k in ipairs({ "AuraContainer", "auraFrames", "CollapseAndExpandButton", "UpdateAuraButtons",
                             "Update", "AuraFrame" }) do
            if bf[k] ~= nil then table.insert(keys, k) end
        end
        P("BuffFrame fields:", table.concat(keys, ", "),
          "| auraFrames:", bf.auraFrames and #bf.auraFrames or "n/a")
        local b = bf.auraFrames and bf.auraFrames[1]
        if b then
            local bk = {}
            for _, k in ipairs({ "Icon", "icon", "Duration", "duration", "Count", "count",
                                 "DebuffBorder", "Border", "TempEnchantBorder", "Symbol", "Cooldown" }) do
                if b[k] ~= nil then table.insert(bk, k) end
            end
            P("Aura button:", b:GetObjectType(), "size", string.format("%.0f", b:GetWidth()),
              "fields:", table.concat(bk, ", "))
        end
    end
    P("DebuffFrame:", tostring(_G.DebuffFrame ~= nil))
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

-- /men uiprobe: which map / bag / quest log / spellbook frames and APIs this
-- client has. Saved to MinimalUIDB.uiprobe (/reload to write it).
ns.commands.uiprobe = function()
    local out = {}
    local function add(s) table.insert(out, s) end
    local frames = { "WorldMapFrame", "QuestMapFrame", "QuestLogFrame", "QuestLogDetailFrame", "QuestScrollFrame",
        "QuestFrame", "SpellBookFrame", "PlayerSpellsFrame", "SpellBookSkillLineTab1", "TalentFrame",
        "ClassTalentFrame", "ContainerFrame1", "ContainerFrameCombinedBags", "BankFrame", "BagsBar",
        "MainMenuBarBackpackButton", "CharacterBag0Slot", "KeyRingButton", "GossipFrame", "MerchantFrame",
        "FriendsFrame", "GuildFrame", "CommunitiesFrame", "LFGParentFrame", "PVEFrame", "MailFrame",
        "TradeSkillFrame", "ProfessionsFrame", "AchievementFrame", "CollectionsJournal", "EncounterJournal",
        "GameMenuFrame", "SettingsPanel", "MacroFrame", "KeyBindingFrame", "DressUpFrame", "InspectFrame" }
    local have, miss = {}, {}
    for _, n in ipairs(frames) do table.insert(_G[n] and have or miss, n) end
    add("frames: " .. table.concat(have, ", "))
    add("missing: " .. table.concat(miss, ", "))
    for _, ns_ in ipairs({ "C_Container", "C_QuestLog", "C_SpellBook", "C_Map", "C_TaskQuest", "C_ClassTalents",
                           "C_Traits", "C_TradeSkillUI", "C_MerchantFrame", "C_Bank" }) do
        local t = _G[ns_]
        if type(t) == "table" then
            local fns = {}
            for k in pairs(t) do table.insert(fns, k) end
            table.sort(fns)
            add(ns_ .. " (" .. #fns .. "): " .. table.concat(fns, ", "))
        else
            add(ns_ .. ": none")
        end
    end
    local g = {}
    for _, n in ipairs({ "GetNumQuestLogEntries", "GetQuestLogTitle", "SelectQuestLogEntry", "GetNumSpellTabs",
                         "GetSpellTabInfo", "GetSpellBookItemName", "GetContainerNumSlots", "GetContainerItemInfo",
                         "ToggleWorldMap", "ToggleQuestLog", "ToggleSpellBook", "ToggleAllBags", "OpenAllBags",
                         "ToggleBackpack", "ToggleBag", "ToggleTalentFrame", "PlayerSpellsUtil" }) do
        table.insert(g, n .. "=" .. tostring(_G[n] ~= nil))
    end
    add("globals: " .. table.concat(g, ", "))
    local qm = _G.WorldMapFrame
    if qm then add("WorldMapFrame size " .. math.floor(qm:GetWidth()) .. "x" .. math.floor(qm:GetHeight())) end
    MinimalUIDB.uiprobe = out
    ns:Print("Recorded " .. #out .. " lines. /reload to save them.")
end

-- /men menuprobe: 5 seconds after typing it, records the menu under the
-- mouse (open a right-click menu and its submenu, keep the mouse on a
-- submenu row). Saved to MinimalUIDB.menuprobe (/reload to write it).
ns.commands.menuprobe = function()
    ns:Print("Menu probe in 5 seconds: right-click a frame, open a submenu, keep the mouse on a submenu row.")
    C_Timer.After(5, function()
        local out = {}
        local function keyOf(parent, child)
            if not parent then return nil end
            for k, v in pairs(parent) do if v == child and type(k) == "string" then return k end end
        end
        local function desc(o, parent)
            local n = (o.GetName and o:GetName()) or ("." .. (keyOf(parent, o) or "?"))
            local s = n .. " [" .. o:GetObjectType() .. "]"
            if o.IsShown then s = s .. (o:IsShown() and "" or " hidden") end
            if o.GetFrameLevel then s = s .. " lvl" .. o:GetFrameLevel() end
            if o.GetDrawLayer then s = s .. " " .. tostring(o:GetDrawLayer()) end
            if o.IsObjectType and o:IsObjectType("Line") then
                s = s .. " (line)"
            elseif o.IsObjectType and o:IsObjectType("Texture") then
                local a = o.GetAtlas and o:GetAtlas()
                s = s .. (a and (" atlas=" .. a) or (" tex=" .. tostring(o:GetTexture())))
                local r, g, b, al = o:GetVertexColor()
                s = s .. string.format(" vc=%.2f,%.2f,%.2f,%.2f a=%.2f", r or 0, g or 0, b or 0, al or 0, o:GetAlpha())
                s = s .. string.format(" size=%dx%d", o:GetWidth() or 0, o:GetHeight() or 0)
                local p, rel, rp, x, y = o:GetPoint(1)
                if p then
                    s = s .. string.format(" pt=%s>%s %s %.0f,%.0f", p,
                        rel and (rel.GetName and rel:GetName() or (rel == o:GetParent() and "parent" or "?")) or "nil",
                        tostring(rp), x or 0, y or 0)
                end
            end
            if o.IsObjectType and o:IsObjectType("FontString") then
                local r, g, b = o:GetTextColor()
                s = s .. string.format(" text=%s col=%.2f,%.2f,%.2f", tostring(o:GetText()), r or 0, g or 0, b or 0)
            end
            return s
        end
        local function walk(f, parent, ind, depth)
            table.insert(out, ind .. desc(f, parent))
            if depth >= 6 or #out > 400 then return end
            for _, r in ipairs({ f:GetRegions() }) do table.insert(out, ind .. "  - " .. desc(r, f)) end
            for _, c in ipairs({ f:GetChildren() }) do walk(c, f, ind .. "  ", depth + 1) end
        end
        local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        local f = foci[1]
        if not f then ns:Print("Menu probe: nothing under the mouse."); return end
        -- Climb to the menu's top frame (the last ancestor below UIParent).
        local chain, cur = {}, f
        while cur and cur ~= UIParent do
            table.insert(chain, desc(cur, cur:GetParent()))
            if cur:GetParent() == UIParent or not cur:GetParent() then break end
            cur = cur:GetParent()
        end
        table.insert(out, "CHAIN: " .. table.concat(chain, "  <  "))
        walk(cur, nil, "", 0)
        local M = Menu and Menu.GetManager and Menu.GetManager()
        local open = M and M.GetOpenMenu and M:GetOpenMenu()
        local openName = open and (open:GetName() or (open.GetDebugName and open:GetDebugName()))
        table.insert(out, "OpenMenu: " .. tostring(openName or open))
        table.insert(out, "top == OpenMenu: " .. tostring(open == cur))
        -- The main menu too (its rows have the submenu arrows and headers).
        if open and open ~= cur then
            table.insert(out, "=== MAIN MENU ===")
            walk(open, nil, "", 0)
        end
        MinimalUIDB.menuprobe = out
        ns:Print("Menu probe recorded " .. #out .. " lines. /reload to save.")
    end)
end

-- /men dmprobe: Blizzard's damage meter, frames / regions / bars (open it
-- with a fight's data showing first). Saved to MinimalUIDB.dmprobe.
ns.commands.dmprobe = function()
    local root = _G.DamageMeter
    if not root then ns:Print("No DamageMeter frame."); return end
    local out = {}
    local function keyOf(parent, child)
        if not parent then return "?" end
        for k, v in pairs(parent) do if v == child and type(k) == "string" then return k end end
        return "?"
    end
    local function line(o, parent, ind)
        local s = ind .. ((o.GetName and o:GetName()) or ("." .. keyOf(parent, o))) .. " [" .. o:GetObjectType() .. "]"
        if o.IsShown and not o:IsShown() then s = s .. " hidden" end
        if o.GetWidth then s = s .. string.format(" %dx%d", o:GetWidth() or 0, o:GetHeight() or 0) end
        if o.IsObjectType and o:IsObjectType("Texture") then
            local a = o.GetAtlas and o:GetAtlas()
            s = s .. " " .. tostring(o:GetDrawLayer()) .. (a and (" atlas=" .. a) or (" tex=" .. tostring(o:GetTexture())))
            s = s .. string.format(" a=%.2f", o:GetAlpha())
        elseif o.IsObjectType and o:IsObjectType("FontString") then
            local f, size = o:GetFont()
            local t = o:GetText()
            if issecretvalue and issecretvalue(t) then t = "<secret>" end
            s = s .. " text=" .. tostring(t) .. " font=" .. tostring(f) .. " " .. tostring(size)
        elseif o.IsObjectType and o:IsObjectType("StatusBar") then
            local t = o:GetStatusBarTexture()
            s = s .. " bartex=" .. tostring(t and (t:GetAtlas() or t:GetTexture()))
        end
        table.insert(out, s)
    end
    local function walk(f, parent, ind, depth)
        line(f, parent, ind)
        if depth >= 9 or #out > 700 then return end
        for _, r in ipairs({ f:GetRegions() }) do line(r, f, ind .. "  - ") end
        for _, c in ipairs({ f:GetChildren() }) do walk(c, f, ind .. "  ", depth + 1) end
    end
    walk(root, nil, "", 0)
    MinimalUIDB.dmprobe = out
    ns:Print("Damage meter probe recorded " .. #out .. " lines. /reload to save.")
end

-- /men guildprobe: the guild & communities window (open it on the Roster
-- page first): frames with key, shown/visible, alpha, level, size and first
-- anchor; textures and text. Saved to MinimalUIDB.guildprobe.
ns.commands.guildprobe = function()
    local root = _G.CommunitiesFrame
    if not root or not root:IsShown() then ns:Print("Open the guild window first."); return end
    local out = {}
    local function keyOf(parent, child)
        if not parent then return "?" end
        for k, v in pairs(parent) do if v == child and type(k) == "string" then return k end end
        return "?"
    end
    local function num(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v or -1 end
    local function line(o, parent, ind)
        local s = ind .. ((o.GetName and o:GetName()) or ("." .. keyOf(parent, o))) .. " [" .. o:GetObjectType() .. "]"
        if o.IsShown and not o:IsShown() then s = s .. " hidden"
        elseif o.IsVisible and not o:IsVisible() then s = s .. " invisible" end
        if o.__muiOurs or o.__muiDMOurs then s = s .. " OURS" end
        if o.GetAlpha then s = s .. string.format(" a=%.2f", num(o:GetAlpha())) end
        if o.GetFrameLevel then s = s .. " lvl" .. o:GetFrameLevel() end
        if o.GetWidth then s = s .. string.format(" %dx%d", num(o:GetWidth()), num(o:GetHeight())) end
        local isLine = o.IsObjectType and o:IsObjectType("Line")
        if not isLine and o.GetPoint and o.GetNumPoints and o:GetNumPoints() > 0 then
            local p, rel, rp, x, y = o:GetPoint(1)
            local rn = rel and ((rel.GetName and rel:GetName()) or (rel == parent and "parent") or ("." .. keyOf(rel:GetParent(), rel)))
            s = s .. string.format(" @%s>%s %s %d,%d", tostring(p), tostring(rn), tostring(rp), num(x), num(y))
        end
        if o.__muiFaded then s = s .. " FADED" end
        if o.IsObjectType and o:IsObjectType("Texture") and not o:IsObjectType("Line") then
            local a = o.GetAtlas and o:GetAtlas()
            s = s .. " " .. tostring(o:GetDrawLayer()) .. (a and (" atlas=" .. a) or (" tex=" .. tostring(o:GetTexture())))
        elseif o.IsObjectType and o:IsObjectType("FontString") then
            local t = o:GetText()
            if issecretvalue and issecretvalue(t) then t = "<secret>" end
            s = s .. " text=" .. tostring(t)
        end
        table.insert(out, s)
    end
    local function walk(f, parent, ind, depth)
        line(f, parent, ind)
        if depth >= 7 or #out > 1500 then return end
        for _, r in ipairs({ f:GetRegions() }) do line(r, f, ind .. "  - ") end
        for _, c in ipairs({ f:GetChildren() }) do walk(c, f, ind .. "  ", depth + 1) end
    end
    local ml = root.MemberList
    if ml and ml.ScrollBox and ml.ScrollBox.GetDataProviderSize then
        local ok, n = pcall(ml.ScrollBox.GetDataProviderSize, ml.ScrollBox)
        table.insert(out, "MemberList data size: " .. tostring(ok and n or "?"))
    end
    walk(root, nil, "", 0)
    MinimalUIDB.guildprobe = out
    ns:Print("Guild probe recorded " .. #out .. " lines. /reload to save.")
end

-- /men countprobe: every action button showing a count, with what each API
-- says the count should be (ammo / reagent counts). Printed to chat and
-- saved to MinimalUIDB.countprobe.
ns.commands.countprobe = function()
    local out = {}
    local function add(line) table.insert(out, line); ns:Print(line) end
    local function q(fn, ...)
        if type(fn) ~= "function" then return "n/a" end
        local ok, a, b, c = pcall(fn, ...)
        if not ok then return "err" end
        return tostring(a) .. (b ~= nil and ("," .. tostring(b)) or "") .. (c ~= nil and ("," .. tostring(c)) or "")
    end
    local prefixes = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
    add("ammo slot (inv 0): " .. q(GetInventoryItemCount, "player", 0) .. "  id " .. q(GetInventoryItemID, "player", 0))
    local n = 0
    for _, pre in ipairs(prefixes) do
        for i = 1, 12 do
            local b = _G[pre .. i]
            local c = b and b.Count
            local t = c and c:GetText()
            if t and t ~= "" then
                n = n + 1
                local slot = b.action or (b.GetAttribute and b:GetAttribute("action"))
                local kind, id = nil, nil
                if slot and GetActionInfo then kind, id = GetActionInfo(slot) end
                add(string.format("%s%d slot=%s text='%s' w=%.0f sw=%.0f shown=%s", pre, i, tostring(slot), t,
                    c:GetWidth(), c:GetStringWidth(), tostring(c:IsShown())))
                add(string.format("   action=%s:%s  GetActionCount=%s  consumable=%s  stackable=%s",
                    tostring(kind), tostring(id), q(GetActionCount, slot), q(IsConsumableAction, slot),
                    q(IsStackableAction, slot)))
                if kind == "item" and id then
                    add(string.format("   GetItemCount=%s  C_Item.GetItemCount=%s  incl. bank/uses=%s",
                        q(_G.GetItemCount, id), q(C_Item and C_Item.GetItemCount, id),
                        q(C_Item and C_Item.GetItemCount, id, true, true)))
                end
                local hk = b.HotKey and b.HotKey:GetText()
                add("   hotkey text='" .. tostring(hk) .. "'")
            end
        end
    end
    if n == 0 then add("No action buttons with a count found.") end
    MinimalUIDB.countprobe = out
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
        try("CheckInteractDistance target,4", CheckInteractDistance, "target", 4)
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

-- /men optprobe : what the game's Options window is made of on this client
-- (frames with their keys, and each one's art: atlas / file / layer), for
-- restyling it. Open Options first. Saved in MinimalUIDB.optprobe.
ns.commands.optprobe = function()
    local P = _G.SettingsPanel
    if not (MinimalUIDB and P) then return ns:Print("No SettingsPanel on this client.") end
    if not P:IsShown() then return ns:Print("Open the game's Options window first, then run this.") end
    local out = {}
    local function s(v) if issecretvalue and issecretvalue(v) then return "<secret>" end return tostring(v) end
    local function keysOf(f)
        local names = {}
        for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
        return names
    end
    local function walk(f, key, depth)
        if #out > 900 or depth > 7 or (f.IsForbidden and f:IsForbidden()) then return end
        local pad = string.rep("  ", depth)
        pcall(function()
            local txt = ""
            if f.GetText then
                local t = f:GetText()
                if type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) then txt = ' "' .. t:sub(1, 28) .. '"' end
            end
            out[#out + 1] = pad .. key .. " [" .. f:GetObjectType() .. "] " .. s(f:GetName() or "?")
                .. (f:IsShown() and "" or " hidden") .. string.format(" %.0fx%.0f", f:GetWidth(), f:GetHeight())
                .. " lvl " .. s(f:GetFrameLevel()) .. (f:IsMouseEnabled() and " mouse" or "") .. txt
        end)
        local names = keysOf(f)
        local nr = 0
        for _, r in ipairs({ f:GetRegions() }) do
            nr = nr + 1
            if nr > 14 then out[#out + 1] = pad .. "  ..more regions"; break end
            pcall(function()
                local ot = r:GetObjectType()
                local line = pad .. "  ~" .. (names[r] or "#") .. " " .. ot .. " " .. s(r:GetName() or "")
                    .. (r:IsShown() and "" or " hidden")
                if ot == "Texture" then
                    local layer, sub = r:GetDrawLayer()
                    line = line .. " " .. s(layer) .. "/" .. s(sub) .. " atlas=" .. s(r:GetAtlas()) .. " tex=" .. s(r:GetTexture())
                        .. string.format(" %.0fx%.0f a=%.2f", r:GetWidth(), r:GetHeight(), r:GetAlpha())
                elseif ot == "FontString" then
                    local t = r:GetText()
                    local _, size = r:GetFont()
                    line = line .. " size=" .. s(size) .. ' "' .. ((type(t) == "string" and not (issecretvalue and issecretvalue(t))) and t:sub(1, 28) or "") .. '"'
                end
                out[#out + 1] = line
            end)
        end
        if not f:IsShown() and depth > 1 then return end
        -- Recycled list rows: the first three of each list are enough.
        local isList = key == "ScrollTarget"
        local n = 0
        for _, c in ipairs({ f:GetChildren() }) do
            n = n + 1
            if isList and n > 3 then out[#out + 1] = pad .. "  ..more rows"; break end
            walk(c, names[c] or "#", depth + 1)
        end
    end
    out[#out + 1] = "at " .. date("%H:%M:%S") .. " strata " .. s(P:GetFrameStrata()) .. " scale " .. s(P:GetEffectiveScale())
    walk(P, "SettingsPanel", 0)
    MinimalUIDB.optprobe = out
    ns:Print("Options window recorded (" .. #out .. " lines). /reload to save it.")
end

-- Pet happiness: what this client gives for a hunter pet's mood. Recorded by
-- /men petprobe, and on its own a few seconds after you log in with a pet.
local function petProbe()
    if not MinimalUIDB then return end
    local out = {}
    local function add(...) out[#out + 1] = table.concat({ tostringall(...) }, "  ") end
    local function show(v) if issecretvalue and issecretvalue(v) then return "<secret>" end return tostring(v) end
    add("at", date("%H:%M:%S"), "pet", show(UnitExists("pet")), show(UnitName("pet")),
        "family", show(UnitCreatureFamily and UnitCreatureFamily("pet")))
    add("GetPetHappiness", type(_G.GetPetHappiness))
    if _G.GetPetHappiness then
        local r = { pcall(GetPetHappiness) }
        local t = {}
        for i = 1, #r do t[i] = show(r[i]) end
        add("  returns", table.concat(t, ", "))
    end
    if _G.HasPetUI then
        local ok, has, kind = pcall(HasPetUI)
        add("HasPetUI", show(ok), show(has), show(kind))
    end
    add("UnitPowerType", show(UnitPowerType("pet")))
    add("Enum.PowerType.Happiness", show(Enum and Enum.PowerType and Enum.PowerType.Happiness))
    for i = 0, 30 do
        local ok, cur = pcall(UnitPower, "pet", i)
        local ok2, max = pcall(UnitPowerMax, "pet", i)
        if (ok and cur and show(cur) ~= "0") or (ok2 and max and show(max) ~= "0") then
            add("  power", i, show(cur), "/", show(max))
        end
    end
    for _, fn in ipairs({ "GetPetLoyalty", "GetPetTrainingPoints", "GetPetFoodTypes", "GetPetExperience" }) do
        if _G[fn] then
            local r = { pcall(_G[fn]) }
            local t = {}
            for i = 1, #r do t[i] = show(r[i]) end
            add(fn, table.concat(t, ", "))
        else
            add(fn, "missing")
        end
    end
    -- Pet buffs / debuffs (some clients show mood as an aura).
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 20 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "pet", i, filter)
            if not ok or not a then break end
            add("  aura", filter, show(a.name), show(a.spellId), show(a.icon))
        end
    end
    MinimalUIDB.petprobe = out
    return out
end
ns.commands.petprobe = function()
    petProbe()
    ns:Print("Pet recorded. /reload so it can be read.")
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(5, function() if UnitExists("pet") then pcall(petProbe) end end)
    end)
end

-- /men barprobe: what the first main bar button and the bar itself are
-- drawn with (finds leftover Blizzard bar art). Read MinimalUIDB.barprobe.
ns.commands.barprobe = function()
    if not MinimalUIDB then return end
    local out = {}
    local function regs(f, indent)
        local names = {}
        for k, v in pairs(f) do if type(k) == "string" and type(v) == "table" then names[v] = k end end
        for _, r in ipairs({ f:GetRegions() }) do
            pcall(function()
                local what = r:GetObjectType()
                local art = what == "Texture" and (" atlas=" .. tostring(r.GetAtlas and r:GetAtlas()) .. " tex=" .. tostring(r:GetTexture())) or ""
                out[#out + 1] = string.format("%s%s <%s>%s %.0fx%.0f%s a=%.2f", indent, names[r] or "#", what, art,
                    r:GetWidth() or 0, r:GetHeight() or 0, r:IsShown() and "" or " hidden", r:GetAlpha() or 0)
            end)
        end
        for _, c in ipairs({ f:GetChildren() }) do
            pcall(function()
                out[#out + 1] = string.format("%s%s [%s] %s %.0fx%.0f%s a=%.2f", indent, names[c] or "#", c:GetObjectType(),
                    tostring(c:GetName()), c:GetWidth() or 0, c:GetHeight() or 0, c:IsShown() and "" or " hidden", c:GetAlpha() or 0)
            end)
        end
    end
    local b = _G.ActionButton1 or _G.ActionButton2
    if b then out[#out + 1] = "ActionButton1:"; regs(b, "  ") end
    local bar = _G.MainActionBar or _G.MainMenuBar
    if bar then
        out[#out + 1] = "Main bar " .. tostring(bar:GetName()) .. ":"
        local keys = {}
        for k, v in pairs(bar) do if type(k) == "string" and type(v) == "table" then keys[#keys + 1] = k end end
        table.sort(keys)
        out[#out + 1] = "  keys: " .. table.concat(keys, ", ")
        regs(bar, "  ")
    end
    MinimalUIDB.barprobe = out
    ns:Print("Action bar recorded. /reload so it can be read.")
end

-- /men navprobe : does this client have the game's own in-world waypoint
-- (the marker that sits over a tracked quest's objective)? Records which of
-- its functions exist, the setting that turns it on, and what its frame is
-- made of, into MinimalUIDB.navprobe. Best run with a quest tracked.
ns.commands.navprobe = function()
    if not MinimalUIDB then return end
    local out = {}
    local function s(v) if issecretvalue and issecretvalue(v) then return "<secret>" end return tostring(v) end
    local function api(tname)
        local t = _G[tname]
        if type(t) ~= "table" then out[#out + 1] = tname .. ": missing"; return end
        local names = {}
        for k, v in pairs(t) do if type(v) == "function" then names[#names + 1] = k end end
        table.sort(names)
        out[#out + 1] = tname .. ": " .. table.concat(names, ", ")
    end
    api("C_SuperTrack"); api("C_Navigation")
    local function call(label, fn, ...)
        if type(fn) ~= "function" then out[#out + 1] = label .. ": no function"; return end
        local r = { pcall(fn, ...) }
        local parts = {}
        for i = 2, math.min(#r, 6) do parts[#parts + 1] = s(r[i]) end
        out[#out + 1] = label .. ": " .. (r[1] and "ok " or "ERR ") .. table.concat(parts, " | ")
    end
    local getcv = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    call("cvar showInGameNavigation", getcv, "showInGameNavigation")
    local ST, NV = _G.C_SuperTrack or {}, _G.C_Navigation or {}
    call("IsSuperTrackingAnything", ST.IsSuperTrackingAnything)
    call("IsSuperTrackingQuest", ST.IsSuperTrackingQuest)
    call("GetSuperTrackedQuestID", ST.GetSuperTrackedQuestID)
    call("GetHighestPrioritySuperTrackingType", ST.GetHighestPrioritySuperTrackingType)
    call("Nav.GetDistance", NV.GetDistance)
    call("Nav.HasValidScreenPosition", NV.HasValidScreenPosition)
    call("Nav.WasClampedToScreen", NV.WasClampedToScreen)
    call("Nav.GetTargetState", NV.GetTargetState)
    call("Nav.GetFrame", NV.GetFrame)
    call("C_Map.HasUserWaypoint", C_Map and C_Map.HasUserWaypoint)
    call("C_Map.CanSetUserWaypointOnMap", C_Map and C_Map.CanSetUserWaypointOnMap, C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    call("C_QuestLog.GetNextWaypoint", C_QuestLog and C_QuestLog.GetNextWaypoint, ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() or 0)
    call("QuestPOIGetIconInfo", _G.QuestPOIGetIconInfo, ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() or 0)
    local watched = {}
    pcall(function()
        for i = 1, (C_QuestLog.GetNumQuestWatches() or 0) do
            watched[#watched + 1] = s(C_QuestLog.GetQuestIDForQuestWatchIndex(i))
        end
    end)
    out[#out + 1] = "watched quests: " .. table.concat(watched, ", ")
    local F = _G.SuperTrackedFrame
    if not F then
        out[#out + 1] = "SuperTrackedFrame: missing"
    else
        pcall(function()
            out[#out + 1] = "SuperTrackedFrame: " .. (F:IsShown() and "shown" or "hidden")
                .. string.format(" %.0fx%.0f alpha %.2f", F:GetWidth(), F:GetHeight(), F:GetAlpha())
                .. " parent " .. s(F:GetParent() and F:GetParent():GetName())
            for k, v in pairs(F) do
                if type(k) == "string" and type(v) == "table" and v.GetObjectType then
                    local extra = ""
                    if v.GetAtlas then extra = " atlas " .. s(v:GetAtlas()) end
                    if v.GetText then extra = extra .. " text " .. s(v:GetText()) end
                    out[#out + 1] = "  ." .. k .. " [" .. v:GetObjectType() .. "]"
                        .. (v:IsShown() and "" or " hidden") .. extra
                elseif type(k) == "string" and type(v) ~= "function" and type(v) ~= "table" then
                    out[#out + 1] = "  ." .. k .. " = " .. s(v)
                end
            end
        end)
    end
    MinimalUIDB.navprobe = out
    ns:Print("Waypoint facts recorded (" .. #out .. " lines). /reload to save them.")
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
-- recorded. The newest 100,000 lines are kept. It reaches the disk at the
-- next /reload or logout, like everything else.
do
    local J, t0, running = nil, 0, false
    local MAX, KEEP = 120000, 100000
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
        J = MinimalUIDB.journal[key]
        if not J then J = {}; MinimalUIDB.journal[key] = J end
        -- Keep the newest lines.
        if #J > MAX then
            local keep = {}
            for i = #J - KEEP + 1, #J do keep[#keep + 1] = J[i] end
            J = keep
            MinimalUIDB.journal[key] = J
        end
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
    boot:SetScript("OnEvent", function() if MinimalUIDB and MinimalUIDB.record then pcall(start) end end)

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
