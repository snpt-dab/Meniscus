local _, ns = ...
local T = ns.Theme

-- Settings panel: a sidebar of categories on the left, the chosen page on
-- the right. Pages are rounded group cards of rows: label on the left,
-- control on the right (switch, dropdown pill showing the current value, or
-- an action pill). Settings that need a reload say so under their label, and
-- the sidebar's Reload UI pill lights up once one has changed.
-- Open with /men, the minimap addon compartment, or Esc > Options > AddOns.

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local roundedRect = ns.RoundedRect

local W, H = 660, 470
local SIDE_W = 176
local PAD = 18
local CONTENT_X = SIDE_W + 20
local CONTENT_W = W - CONTENT_X - PAD
local ROW_H = 36
local CTRL_W = 200

local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local CARD = { 0.105, 0.105, 0.12, 1 }

local controls = {}

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local function UF() return ns.modules.UnitFrames end
local function cmd(name, arg) local f = ns.commands[name]; if f then f(arg) end end
local function flagReload() ns.needsReload = true end

-- ── Dropdown menu (shared) ────────────────────────────────────────────────
local menu, catcher
local MENU_ROW = 22

local function closeMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end

local function buildMenu()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints()
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetScript("OnClick", closeMenu)
    catcher:Hide()
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    roundedRect(menu, 0, 0, 10, T.border[1], T.border[2], T.border[3], 1)
    roundedRect(menu, 1, 1, 9, 0.09, 0.09, 0.10, 0.98)
    menu.rows = {}
    menu:Hide()
end

local function menuRow(i)
    local r = menu.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, menu)
    r:SetHeight(MENU_ROW)
    r.hl = roundedRect(r, 2, 0, 6, 1, 1, 1, 0)
    r.dot = r:CreateTexture(nil, "OVERLAY")
    r.dot:SetSize(6, 6)
    r.dot:SetPoint("LEFT", 10, 0)
    r.dot:SetTexture(MEDIA .. "rounded.tga")
    r.dot:SetVertexColor(unpack(T.accent))
    r.text = text(r, 11)
    r.text:SetPoint("LEFT", 24, 0)
    r:SetScript("OnEnter", function(self) self.hl(1, 1, 1, 0.07) end)
    r:SetScript("OnLeave", function(self) self.hl(1, 1, 1, 0) end)
    menu.rows[i] = r
    return r
end

local function openMenu(owner)
    if not menu then buildMenu() end
    if menu:IsShown() and menu.owner == owner then return closeMenu() end
    menu.owner = owner
    local opts = owner.opts.options()
    local ok, cur = pcall(owner.opts.get)
    local level = owner:GetParent():GetFrameLevel() + 40
    catcher:SetFrameLevel(level)
    menu:SetFrameLevel(level + 1)
    for i, o in ipairs(opts) do
        local r = menuRow(i)
        r:SetFrameLevel(level + 2)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * MENU_ROW)
        r:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * MENU_ROW)
        r.text:SetText(o.label)
        local selected = ok and o.key == cur
        r.dot:SetShown(selected)
        r.text:SetTextColor(unpack(selected and T.accent or T.text))
        r:SetScript("OnClick", function()
            closeMenu()
            owner.opts.set(o.key)
            if owner.opts.reload then flagReload() end
            ns:RefreshPanel()
        end)
        r:Show()
    end
    for i = #opts + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    menu:SetSize(math.max(owner:GetWidth(), 200), #opts * MENU_ROW + 8)
    catcher:Show()
    menu:Show()
end

-- ── Controls ──────────────────────────────────────────────────────────────
-- Pill button (actions, dropdowns, sidebar).
local function pill(parent, w, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 24)
    b.paint = ns.EasePaint(b, roundedRect(b, -6, 0, 12, unpack(PILL_OFF)))
    b.text = text(b, 11, true, T.text)
    b.text:SetPoint("CENTER")
    b.text:SetText(label or "")
    function b:Repaint()
        if self.on then self.paint(unpack(PILL_ON)); self.text:SetTextColor(unpack(TEXT_DARK))
        elseif self.accent then self.paint(unpack(T.accent)); self.text:SetTextColor(unpack(TEXT_DARK))
        elseif self.hover then self.paint(unpack(PILL_HOVER)); self.text:SetTextColor(unpack(T.text))
        else self.paint(unpack(PILL_OFF)); self.text:SetTextColor(unpack(self.dim and T.textDim or T.text)) end
    end
    b:HookScript("OnEnter", function(self) self.hover = true; self:Repaint() end)
    b:HookScript("OnLeave", function(self) self.hover = false; self:Repaint() end)
    b:Repaint()
    return b
end

-- On/off switch: accent track with a dark knob on the right when on.
local function switch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(36, 20)
    s.track = roundedRect(s, -6, 0, 10, 0.25, 0.25, 0.28, 1)
    local mask = s:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(14, 14)
    s.knob = s:CreateTexture(nil, "ARTWORK")
    s.knob:SetSize(14, 14)
    s.knob:AddMaskTexture(mask)
    mask:SetPoint("CENTER", s.knob, "CENTER")
    function s:SetOn(on)
        self.knob:ClearAllPoints()
        if on then
            self.track(unpack(T.accent))
            self.knob:SetColorTexture(unpack(TEXT_DARK))
            self.knob:SetPoint("RIGHT", self, "RIGHT", -3, 0)
        else
            self.track(0.25, 0.25, 0.28, 1)
            self.knob:SetColorTexture(0.62, 0.62, 0.67, 1)
            self.knob:SetPoint("LEFT", self, "LEFT", 3, 0)
        end
    end
    return s
end

local function chevron(parent, color)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(10, 6)
    for _, p in ipairs({ { -4, 2, 0, -2 }, { 0, -2, 4, 2 } }) do
        local l = c:CreateLine(nil, "OVERLAY")
        l:SetThickness(1.4)
        l:SetColorTexture(unpack(color))
        l:SetStartPoint("CENTER", c, p[1], p[2])
        l:SetEndPoint("CENTER", c, p[3], p[4])
    end
    return c
end

-- One settings row inside a group card.
--   item = { label, kind = "switch"|"dropdown"|"action", note = "…",
--            get = fn, set = fn (switch: toggles), options = fn,
--            run = fn (action), action = "button text", reload = bool }
local function makeRow(card, item, y, last)
    local row = CreateFrame("Button", nil, card)
    row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, y)
    row:SetHeight(ROW_H)
    row.label = text(row, 12)
    row.label:SetText(item[1])
    if item.note or item.reload then
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -6)
        row.note = text(row, 10, false, T.textDim)
        row.note:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        row.note:SetText(item.note or "Applies after a reload")
    else
        row.label:SetPoint("LEFT", row, "LEFT", 14, 0)
    end
    if not last then
        local line = row:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 1, 1, 0.06)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", 14, 0)
        line:SetPoint("BOTTOMRIGHT", -14, 0)
    end

    local kind = item.kind
    if kind == "switch" then
        local s = switch(row)
        s:SetPoint("RIGHT", row, "RIGHT", -14, 0)
        local function toggle()
            item.set()
            if item.reload then flagReload() end
            ns:RefreshPanel()
        end
        s:SetScript("OnClick", toggle)
        row:SetScript("OnClick", toggle)
        function row:Refresh() local ok, on = pcall(item.get); s:SetOn(ok and on) end
    elseif kind == "dropdown" then
        local d = pill(row, CTRL_W)
        d:SetPoint("RIGHT", row, "RIGHT", -14, 0)
        d.opts = { options = item.options, get = item.get, set = item.set, reload = item.reload }
        d.text:ClearAllPoints()
        d.text:SetPoint("LEFT", 12, 0)
        d.text:SetPoint("RIGHT", -26, 0)
        d.text:SetJustifyH("LEFT")
        d.text:SetWordWrap(false)
        ns:SetFont(d.text, 11, "")
        local chev = chevron(d, T.textDim)
        chev:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        d:SetScript("OnClick", function(self) openMenu(self) end)
        function row:Refresh()
            local ok, cur = pcall(item.get)
            local label = ""
            for _, o in ipairs(item.options()) do if ok and o.key == cur then label = o.label end end
            d.text:SetText(label)
        end
    elseif kind == "action" then
        local a = pill(row, 10, item.action or "Go")
        a:SetWidth(math.max(a.text:GetStringWidth() + 28, 64))
        a:SetPoint("RIGHT", row, "RIGHT", -14, 0)
        a:SetScript("OnClick", function()
            item.run()
            if item.reload then flagReload() end
            ns:RefreshPanel()
        end)
        function row:Refresh()
            if item.actionLabel then
                local ok, l = pcall(item.actionLabel)
                if ok and l then a.text:SetText(l); a:SetWidth(math.max(a.text:GetStringWidth() + 28, 64)) end
            end
        end
    end
    table.insert(controls, row)
    return row
end

-- ── Settings ──────────────────────────────────────────────────────────────
local function moduleSwitch(label, name, note)
    return { label, kind = "switch", reload = true, note = note,
        get = function() return ns.db.modules[name].enabled ~= false end,
        set = function() local m = ns.db.modules[name]; m.enabled = m.enabled == false end }
end

local PAGES = {
    { key = "appearance", title = "Appearance", groups = {
        { title = "Text", items = {
            { "Font", kind = "dropdown",
              options = function() return T.fonts or ns:BuildFontList() end,
              get = function() return ns.db.font or "default" end,
              set = function(k) ns:ApplyFont(k) end },
        } },
        { title = "Screen", items = {
            { "Health and power orbs", kind = "switch",
              get = function() local O = ns.modules.Orbs; return O.health and O.health:IsShown() end,
              set = function() cmd("orbs") end },
            { "XP bar width", kind = "dropdown",
              options = function() return { { key = "orbs", label = "Between the orbs" },
                                            { key = "bars", label = "Across all bars" } } end,
              get = function() return ns.modules.XP.db.span end,
              set = function(k) ns.modules.XP:SetSpan(k) end },
            { "Fade menu and bag buttons", kind = "switch", note = "They show again on mouseover. Not used with the console's pills",
              get = function() return ns.modules.Declutter.db.fadeMenus end,
              set = function() local D = ns.modules.Declutter; D.db.fadeMenus = not D.db.fadeMenus; D:Refresh() end },
            { "Keep backpack and menu icon visible", kind = "switch",
              get = function() return ns.modules.Declutter.db.keepIcons end,
              set = function() local D = ns.modules.Declutter; D.db.keepIcons = not D.db.keepIcons; D:Refresh() end },
        } },
    } },
    { key = "console", title = "Console", groups = {
        { title = "Layout", items = {
            { "Plate behind the bottom row", kind = "switch",
              get = function() return ns.modules.Bars.db.plate end,
              set = function() cmd("console") end },
            { "Chat and context panel in the plate", kind = "switch", note = "Turning it off needs a reload",
              get = function() return ns.modules.Bars.db.wings end,
              set = function() cmd("console", "wings") end },
            { "Minimap between the action bars", kind = "switch", note = "Splits the main bar. Turning it off needs a reload",
              get = function() return ns.modules.Minimap.db.dome end,
              set = function() cmd("dome") end },
            { "Pin the game's buff frames into the layout", kind = "switch", note = "Turning it off needs a reload",
              get = function() return ns.modules.Auras.db.attachBlizz end,
              set = function() cmd("buffs", "attach") end },
            { "Player frame", kind = "dropdown",
              options = function() return { { key = "frame", label = "Normal frame" },
                                            { key = "none", label = "Character panel (no frame)" } } end,
              get = function() return UF().db.playerStyle or "frame" end,
              set = function(k) UF():SetPlayerStyle(k) end },
        } },
        { title = "Right panel", items = {
            { "Shows", kind = "dropdown",
              options = function() return { { key = "auto", label = "Damage in combat, objectives otherwise" },
                                            { key = "damage", label = "Damage meter" },
                                            { key = "quests", label = "Objectives" } } end,
              get = function() local TRK = ns.modules.Tracker; return TRK.db and TRK.db.wingTab or "auto" end,
              set = function(k)
                  local TRK = ns.modules.Tracker
                  if TRK.db then TRK.db.wingTab = k end
                  if TRK.ApplyConsole then TRK:ApplyConsole() end
              end },
        } },
        { title = "Pet", items = {
            { "Pet orbs instead of the pet frame", kind = "switch",
              get = function() return ns.modules.Orbs.db.petOrbs ~= false end,
              set = function() cmd("petorbs") end },
            { "Show empty pet action slots", kind = "switch",
              get = function() return ns.modules.Bars.db.petGrid ~= false end,
              set = function() cmd("petgrid") end },
        } },
    } },
    { key = "unitframes", title = "Unit frames", groups = {
        { title = "Frames", items = {
            { "Hide Blizzard's unit frames", kind = "switch", note = "Turning this off needs a reload",
              get = function() return UF().db.hideBlizzard end,
              set = function() cmd("blizz") end },
            { "Frame positions", kind = "action", action = "Reset", run = function() cmd("reset") end },
        } },
        { title = "Party", items = {
            { "Party frames", kind = "dropdown",
              options = function() return { { key = "attach", label = "Stacked above player" },
                                            { key = "detach", label = "Free (move in move mode)" } } end,
              get = function() return UF().db.party.attach and "attach" or "detach" end,
              set = function(k) cmd("party", k) end },
            { "Preview a test party", kind = "switch",
              get = function() return UF().partyTest end,
              set = function() cmd("party", "test") end },
        } },
        { title = "Portraits", items = {
            { "Idle fidgets", kind = "switch",
              get = function() return UF().db.portrait.fidget == 1 end,
              set = function() cmd("portrait", "fidget " .. (UF().db.portrait.fidget == 1 and 0 or 1)) end },
            { "Camera", kind = "action", action = "Reset", run = function() cmd("portrait", "reset") end },
        } },
    } },
    { key = "auras", title = "Buffs", groups = {
        { title = "Your buffs", items = {
            { "Pin the game's buff frames into the layout", kind = "switch", note = "Turning it off needs a reload",
              get = function() return ns.modules.Auras.db.attachBlizz end,
              set = function() cmd("buffs", "attach") end },
            { "Buffs beside the player frame (they freeze during combat)", kind = "switch", reload = true,
              get = function() return ns.modules.Auras.db.playerRows end,
              set = function() local A = ns.modules.Auras; A.db.playerRows = not A.db.playerRows end },
            { "Buff rows", kind = "dropdown",
              options = function() return { { key = "left", label = "Left of the avatar" },
                                            { key = "right", label = "Right of the health bar" } } end,
              get = function() return ns.modules.Auras.db.playerSide end,
              set = function(k) ns.modules.Auras:SetPlayerSide(k) end },
        } },
        { title = "Quick Buff", items = {
            moduleSwitch("Quick Buff reminder", "QuickBuff"),
            { "Rebuff when under", kind = "dropdown",
              options = function() return { { key = 1, label = "1 minute left" }, { key = 2, label = "2 minutes left" },
                                            { key = 3, label = "3 minutes left" }, { key = 5, label = "5 minutes left" } } end,
              get = function() return ns.modules.QuickBuff.db.refresh end,
              set = function(k) ns.modules.QuickBuff.db.refresh = k end },
            { "Quick Buff key", kind = "action", action = "Set key", run = function()
                if SettingsPanel and Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
                    pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID)
                else
                    ns:Print("Options > Keybindings > AddOns > Meniscus > Quick Buff")
                end
            end },
        } },
    } },
    { key = "bars", title = "Action bars", groups = {
        { title = "Bars", items = {
            { "Meniscus action bars", kind = "switch", reload = true,
              get = function() return ns.db.modules.Bars.enabled ~= false end,
              set = function() cmd("actionbars") end },
        } },
    } },
    { key = "bags", title = "Bags", groups = {
        { title = "Bags", items = {
            moduleSwitch("Meniscus bags", "Bags"),
            moduleSwitch("Meniscus bank", "Bank"),
            { "Layout", kind = "dropdown", reload = true,
              options = function() return { { key = "combined", label = "One combined bag" },
                                            { key = "separate", label = "Separate bags" } } end,
              get = function() return ns.modules.Bags.db and ns.modules.Bags.db.mode or "combined" end,
              set = function(k) ns.modules.Bags:SetMode(k) end },
        } },
    } },
    { key = "windows", title = "Windows", groups = {
        { title = "Replacement windows", items = {
            moduleSwitch("Character window", "Character"),
            moduleSwitch("Spellbook", "Spellbook"),
            moduleSwitch("Quest log", "QuestLog"),
            moduleSwitch("NPC dialogs", "Dialogs"),
            moduleSwitch("Loot window and rolls", "Loot"),
            moduleSwitch("Merchant", "Merchant"),
            moduleSwitch("Trainer", "Trainer"),
            moduleSwitch("Mailbox", "Mail"),
            moduleSwitch("Inspect", "Inspect"),
            { "Dialog text types itself out", kind = "switch",
              get = function() return ns.modules.Dialogs.db and ns.modules.Dialogs.db.typewriter end,
              set = function() local d = ns.modules.Dialogs.db; if d then d.typewriter = not d.typewriter end end },
        } },
    } },
    { key = "styling", title = "Styling", groups = {
        { title = "Restyled Blizzard parts", items = {
            moduleSwitch("Minimap", "Minimap"),
            moduleSwitch("Chat", "Chat"),
            moduleSwitch("Quest tracker", "Tracker"),
            moduleSwitch("Tooltips", "Tooltip"),
            moduleSwitch("Nameplates", "Nameplates"),
            moduleSwitch("Menus, popups, map and other windows", "Skins"),
            { "Map coordinates", kind = "switch", reload = true,
              get = function() return ns.modules.Skins.db and ns.modules.Skins.db.coords end,
              set = function() local d = ns.modules.Skins.db; if d then d.coords = not d.coords end end },
            { "Damage meter", kind = "switch", reload = true,
              get = function() return ns.modules.Skins.db and ns.modules.Skins.db.damageMeter ~= false end,
              set = function()
                  local d = ns.modules.Skins.db
                  if d then d.damageMeter = d.damageMeter == false end
              end },
        } },
    } },
    { key = "profiles", title = "Profiles", groups = {
        { title = "Profile", items = {
            { "Active profile", kind = "dropdown", note = "Switching reloads the UI",
              options = function()
                  local list = {}
                  for _, n in ipairs(ns:ProfileNames()) do table.insert(list, { key = n, label = n }) end
                  local me = ns:CharKey()
                  if not MinimalUIDB.profiles[me] then
                      table.insert(list, { key = "\001copy", label = "+ Copy for " .. me })
                  end
                  return list
              end,
              get = function() return ns.profile end,
              set = function(k)
                  if k == ns.profile then return end
                  if k == "\001copy" then ns:UseProfile(ns:CharKey(), true) else ns:UseProfile(k) end
              end },
        } },
    } },
}

-- ── Panel ─────────────────────────────────────────────────────────────────
local panel
local pageFrames, navButtons = {}, {}

local function showPage(key)
    closeMenu()
    for k, f in pairs(pageFrames) do f:SetShown(k == key) end
    for _, b in ipairs(navButtons) do b.on = (b.key == key); b:Repaint() end
    MinimalUIDB.panelPage = key
end

-- A page is a clipped viewport with its content inside; when the content is
-- taller than the window it scrolls with the mouse wheel, and a slim thumb
-- on the right shows where you are.
local function buildPage(parent, page)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_X, -PAD - 34)
    local viewH = H - PAD * 2 - 34
    view:SetSize(CONTENT_W + 10, viewH)
    view:SetClipsChildren(true)
    local f = CreateFrame("Frame", nil, view)
    f:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
    f:SetSize(CONTENT_W, viewH)
    local y = 0
    for _, g in ipairs(page.groups) do
        local h = text(f, 10, true, T.textDim)
        h:SetPoint("TOPLEFT", f, "TOPLEFT", 4, y)
        h:SetText(g.title)
        y = y - 16
        local card = CreateFrame("Frame", nil, f)
        card:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
        card:SetWidth(CONTENT_W)
        roundedRect(card, -6, 0, 12, unpack(CARD))
        local ry = 0
        for i, item in ipairs(g.items) do
            local row = makeRow(card, item, ry, i == #g.items)
            ry = ry - row:GetHeight()
        end
        card:SetHeight(-ry)
        y = y + ry - 16
    end
    local total = -y
    f:SetHeight(math.max(total, viewH))
    local over = math.max(0, total - viewH)
    if over > 0 then
        local thumb = view:CreateTexture(nil, "OVERLAY")
        thumb:SetWidth(3)
        thumb:SetColorTexture(T.textDim[1], T.textDim[2], T.textDim[3], 0.55)
        local th = math.max(24, viewH * viewH / total)
        thumb:SetHeight(th)
        local offset = 0
        local function place()
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", view, "TOPLEFT", 0, offset)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", view, "TOPRIGHT", -1, -(viewH - th) * (offset / over))
        end
        view:EnableMouseWheel(true)
        view:SetScript("OnMouseWheel", function(_, d)
            closeMenu()
            offset = math.max(0, math.min(over, offset - d * 40))
            place()
        end)
        place()
    end
    view:Hide()
    return view
end

local function build()
    local p = CreateFrame("Frame", "MinimalUIPanel", UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetSize(W, H)
    p:SetPoint("CENTER")
    p:EnableMouse(true)
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    table.insert(UISpecialFrames, "MinimalUIPanel")

    roundedRect(p, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    roundedRect(p, -7, 1, 13, 0.07, 0.07, 0.08, 0.98)

    -- Sidebar: slightly darker column with its own rounded left edge.
    local side = CreateFrame("Frame", nil, p)
    side:SetPoint("TOPLEFT", 1, -1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDE_W)
    roundedRect(side, -6, 0, 13, 0.05, 0.05, 0.06, 1)
    local sep = p:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.9)
    sep:SetWidth(1)
    sep:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    sep:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", 0, 0)

    local title = text(side, 16, true)
    title:SetPoint("TOPLEFT", 18, -PAD)
    title:SetText("Meniscus")
    local dot = side:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    dot:SetPoint("LEFT", title, "RIGHT", 6, 0)
    dot:SetTexture(MEDIA .. "rounded.tga")
    dot:SetVertexColor(unpack(T.accent))

    for i, page in ipairs(PAGES) do
        local b = pill(side, SIDE_W - 24, page.title)
        b.key = page.key
        b.dim = true
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 14, 0)
        b:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -PAD - 34 - (i - 1) * 30)
        b:SetScript("OnClick", function(self) showPage(self.key) end)
        b:Repaint()
        table.insert(navButtons, b)
        pageFrames[page.key] = buildPage(p, page)
    end

    -- Sidebar foot: frame unlock + reload (lights up when a change needs it).
    local reload = pill(side, SIDE_W - 24, "Reload UI")
    reload:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 12, PAD)
    reload:SetScript("OnClick", function() ReloadUI() end)
    local unlock = pill(side, SIDE_W - 24, "Unlock frames")
    unlock:SetPoint("BOTTOMLEFT", reload, "TOPLEFT", 0, 8)
    unlock:SetScript("OnClick", function()
        cmd(UF().unlocked and "lock" or "unlock")
        ns:RefreshPanel()
    end)
    p.reload, p.unlock = reload, unlock

    -- Page title + close.
    local pageTitle = text(p, 15, true)
    pageTitle:SetPoint("TOPLEFT", CONTENT_X + 4, -PAD)
    p.pageTitle = pageTitle
    local close = CreateFrame("Button", nil, p)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -12, -12)
    local cmask = close:CreateMaskTexture()
    cmask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    cmask:SetSize(20, 20); cmask:SetPoint("CENTER")
    local cbg = close:CreateTexture(nil, "BACKGROUND")
    cbg:SetSize(20, 20); cbg:SetPoint("CENTER")
    cbg:SetColorTexture(0.16, 0.16, 0.18, 1)
    cbg:AddMaskTexture(cmask)
    local xs = {}
    for i, q in ipairs({ { -1, 1, 1, -1 }, { -1, -1, 1, 1 } }) do
        local l = close:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetStartPoint("CENTER", close, q[1] * 4, q[2] * 4)
        l:SetEndPoint("CENTER", close, q[3] * 4, q[4] * 4)
        l:SetColorTexture(unpack(T.textDim))
        xs[i] = l
    end
    close:SetScript("OnEnter", function()
        cbg:SetColorTexture(unpack(T.accent))
        for _, l in ipairs(xs) do l:SetColorTexture(unpack(TEXT_DARK)) end
    end)
    close:SetScript("OnLeave", function()
        cbg:SetColorTexture(0.16, 0.16, 0.18, 1)
        for _, l in ipairs(xs) do l:SetColorTexture(unpack(T.textDim)) end
    end)
    close:SetScript("OnClick", function() p:Hide() end)

    local foot = text(p, 10, false, T.textDim)
    foot:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", CONTENT_X + 4, 12)
    foot:SetText("Shift while dragging skips snapping   ·   /men help lists commands")

    p:SetScript("OnShow", function()
        local key = MinimalUIDB.panelPage
        local found = false
        for _, pg in ipairs(PAGES) do if pg.key == key then found = true end end
        showPage(found and key or PAGES[1].key)
        ns:RefreshPanel()
    end)
    p:SetScript("OnHide", closeMenu)
    p:Hide()
    return p
end

function ns:RefreshPanel()
    if not panel then return end
    for _, c in ipairs(controls) do if c.Refresh then pcall(c.Refresh, c) end end
    for _, pg in ipairs(PAGES) do
        if pageFrames[pg.key] and pageFrames[pg.key]:IsShown() then panel.pageTitle:SetText(pg.title) end
    end
    local u = UF()
    panel.unlock.text:SetText(u and u.unlocked and "Lock frames" or "Unlock frames")
    panel.unlock.on = u and u.unlocked or false
    panel.unlock:Repaint()
    panel.reload.accent = ns.needsReload or false
    panel.reload:Repaint()
end

local origShowPage = showPage
showPage = function(key)
    origShowPage(key)
    ns:RefreshPanel()
end

function ns:TogglePanel(show)
    panel = panel or build()
    if show == nil then show = not panel:IsShown() end
    panel:SetShown(show)
end

-- Minimap addon compartment (see AddonCompartmentFunc in the TOC).
function MinimalUI_OnAddonCompartmentClick()
    ns:TogglePanel()
end

-- Esc > Options > AddOns > Meniscus: a stub page with an "Open panel" pill.
local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_LOGIN")
reg:SetScript("OnEvent", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    pcall(function()
        local c = CreateFrame("Frame")
        local t = text(c, 16, true)
        t:SetPoint("TOPLEFT", 16, -16)
        t:SetText("Meniscus")
        local open = pill(c, 140, "Open panel")
        open:SetPoint("TOPLEFT", 16, -48)
        open:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            ns:TogglePanel(true)
        end)
        local cat = Settings.RegisterCanvasLayoutCategory(c, "Meniscus")
        Settings.RegisterAddOnCategory(cat)
    end)
end)

-- /men help
ns.commands.help = function()
    local lines = {
        "/men  open the settings panel",
        "/men unlock | lock | reset  move frames / restore positions",
        "/men party attach | detach | test",
        "/men blizz  toggle Blizzard unit frames",
        "/men petorbs | petgrid  pet orbs instead of the pet frame / show empty pet action slots",
        "/men winprobe [clear]  record the Blizzard window that is open, for restyling",
        "/men console [wings]  dark plate behind the bottom row; wings = seat chat and damage meter in it",
        "/men dome [move | reset]  round minimap on the action bar; move = drag it",
        "/men noportrait  no player frame: your portrait moves to the console's character panel",
        "/men orbs  toggle orbs      /men actionbars  toggle bar styling (reload)",
        "/men char | bags [combined|separate] | spells | quests  open windows / bag layout",
        "/men portrait [reset | <zoom|dist|x|z|facing|pop|fidget> <n>]",
        "/men profile [use | copy | delete <name>]  layouts per character",
        "/men font | orbcolor | rage | energy [drip] | mana [fsr|burst] | combo | reloadbtn | minimap | keyring | errors | chat",
        "/men probe | uiprobe | charprobe | bars | scales  diagnostics",
        "/men perf [report | reset | gc]  resource monitor",
        "/men prof blizz  switch between Meniscus and Blizzard professions windows",
    }
    for _, l in ipairs(lines) do ns:Print(l) end
end
