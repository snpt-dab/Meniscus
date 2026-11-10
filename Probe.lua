local _, ns = ...

-- /mui probe: report what this Forever build actually provides.
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

-- /mui bars: inspect the default action bar structure on this build.
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

-- /mui scales: show where button scaling comes from (diagnostic).
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

-- /mui auras: what aura data looks like on this build (run with a target that
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

-- /mui clicks: toggle printing every click our secure unit buttons receive.
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

-- /mui uiprobe: which map / bag / quest log / spellbook frames and APIs this
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

-- /mui menuprobe: 5 seconds after typing it, records the menu under the
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

-- /mui dmprobe: Blizzard's damage meter, frames / regions / bars (open it
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

-- /mui guildprobe: the guild & communities window (open it on the Roster
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

-- /mui countprobe: every action button showing a count, with what each API
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

-- /mui keyprobe [KEY]: what a key is bound to, and which frames show up
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

-- /mui under: name the frame(s) under the mouse (hover a frame, then type it).
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
