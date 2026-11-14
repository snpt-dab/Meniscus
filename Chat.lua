local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Chat: tab art removed (selected tab gets an accent underline), edit box
-- becomes a dark rounded field, and the chat side buttons (menu, channels,
-- social, voice) fade out until the mouse is over the chat area.
-- Chat text, colors and window backgrounds remain Blizzard settings.

local CH = ns:NewModule("Chat", { enabled = true })

local SIDE_BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
                       "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
                       "TextToSpeechButton" }

local function hideTextures(f)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") then
            r:SetAlpha(0)
            hooksecurefunc(r, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
        end
    end
end

local function styleTab(i)
    local tab = _G["ChatFrame" .. i .. "Tab"]
    if not tab or tab.__mui then return end
    tab.__mui = true
    hideTextures(tab)
    local text = tab.Text or _G["ChatFrame" .. i .. "TabText"]
    if text then
        local _, size = text:GetFont()
        ns:SetFont(text, size or 12, "")
    end
    local line = tab:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(unpack(T.accent))
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, 2)
    line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 2)
    line:Hide()
    tab.__muiLine = line
end

local function styleEditBox(i)
    local eb = _G["ChatFrame" .. i .. "EditBox"]
    if not eb or eb.__mui then return end
    eb.__mui = true
    hideTextures(eb)
    -- Drawn on the edit box itself (BACKGROUND), so it stays under its text.
    local inset = 4
    ns.RoundedRect(eb, 0, inset, 8, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(eb, 1, inset + 1, 7, 0.06, 0.06, 0.07, 0.95)
end

-- Seated in the console's wing (Bars.lua): the wing draws the background, so
-- Blizzard's chat background and border go, and with them the shaded strip
-- its button column draws beside the window when you hover the chat.
function CH:Seated()
    if self.seated then return end
    self.seated = true
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf, bf = _G["ChatFrame" .. i], _G["ChatFrame" .. i .. "ButtonFrame"]
        if cf then pcall(hideTextures, cf) end
        if bf then pcall(hideTextures, bf) end
    end
end

local function selectedFrame()
    if FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
        local ok, f = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        if ok and f then return f end
    end
    return SELECTED_CHAT_FRAME
end

-- /men chat : record ChatFrame1's state into MinimalUIDB.chatprobe (chat may
-- be invisible, so it's saved, not just printed), then force it back on screen.
ns.commands = ns.commands or {}
ns.commands.chat = function()
    local cf, out = _G.ChatFrame1, {}
    if not cf then return end
    local function add(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
        table.insert(out, table.concat(t, " ")) end
    local function state(f, label)
        if not f then return add(label, "missing") end
        local p = f:GetParent()
        add(label, "shown", f:IsShown(), "visible", f:IsVisible(), "alpha", f:GetAlpha(),
            "effAlpha", f:GetEffectiveAlpha(), "scale", f:GetEffectiveScale(),
            "left", f:GetLeft(), "bottom", f:GetBottom(), "w", f:GetWidth(), "h", f:GetHeight(),
            "strata", f:GetFrameStrata(), "level", f:GetFrameLevel(),
            "parent", p and (p:GetName() or "?") or "nil", "points", f:GetNumPoints())
        for i = 1, f:GetNumPoints() do
            local pt, rel, rp, x, y = f:GetPoint(i)
            add("   point", pt, rel and (rel.GetName and rel:GetName() or "?"), rp, x, y)
        end
    end
    state(cf, "ChatFrame1")
    state(_G.ChatFrame1Tab, "Tab1")
    state(_G.ChatFrame1EditBox, "EditBox1")
    state(_G.GeneralDockManager, "Dock")
    state(_G.ChatFrame1ButtonFrame, "ButtonFrame1")
    state(cf:GetParent(), "Parent")
    add("DEFAULT_CHAT_FRAME", DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME:GetName())
    MinimalUIDB.chatprobe = out

    -- Bring it back: visible, opaque, and on screen.
    cf:Show()
    cf:SetAlpha(1)
    local l, b = cf:GetLeft(), cf:GetBottom()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not l or l < -cf:GetWidth() + 20 or l > sw - 20 or b < -cf:GetHeight() + 20 or b > sh - 20
        or cf:GetWidth() < 50 or cf:GetHeight() < 30 then
        cf:ClearAllPoints()
        cf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 140)
        if cf:GetWidth() < 50 or cf:GetHeight() < 30 then cf:SetSize(430, 180) end
        if FCF_SavePositionAndDimensions then pcall(FCF_SavePositionAndDimensions, cf) end
    end
    if _G.GeneralDockManager then GeneralDockManager:Show(); GeneralDockManager:SetAlpha(1) end
    ns:Print("Chat state saved; ChatFrame1 forced visible. /reload to save the report.")
end

-- Chat text at 12 by default: set once per character (the size is the
-- game's own chat setting, so a change you make afterwards sticks).
local function defaultFontSize()
    if not (MinimalUIDB and FCF_SetChatWindowFontSize) then return end
    local key = ns.CharKey and ns:CharKey() or "?"
    MinimalUIDB.chatSize12 = MinimalUIDB.chatSize12 or {}
    if MinimalUIDB.chatSize12[key] then return end
    MinimalUIDB.chatSize12[key] = true
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then pcall(FCF_SetChatWindowFontSize, nil, cf, 12) end
    end
end

-- Less of other people in the chat window:
--   * crafting: "So-and-so creates X." from everyone near you (thousands of
--     lines an evening in a city). Your own stay.
--   * group loot: what each member chose on a roll ("has selected Greed
--     for..."), their dice, and the grey and white things other people pick
--     up. Who won each roll stays, and so does anything green or better.
-- A line that can't be read (hidden in combat) is always let through.
local function toPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%d?%$?s", ".+"):gsub("%%%d?%$?d", "%%d+")
    return p
end
local function readable(msg) return type(msg) == "string" and not (issecretvalue and issecretvalue(msg)) end
local function addFilters(db)
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
    if type(add) ~= "function" then return end
    if db.hideCrafting ~= false then
        local mine = type(_G.TRADESKILL_LOG_FIRSTPERSON) == "string" and _G.TRADESKILL_LOG_FIRSTPERSON:match("^(.-)%%") or "You create"
        if mine == "" then mine = "You create" end
        pcall(add, "CHAT_MSG_TRADESKILLS", function(_, _, msg)
            if not readable(msg) then return false end
            return msg:sub(1, #mine) ~= mine
        end)
    end
    if db.quietLoot ~= false then
        local picks, others = {}, {}
        for _, g in ipairs({ "LOOT_ROLL_GREED", "LOOT_ROLL_NEED", "LOOT_ROLL_PASSED", "LOOT_ROLL_DISENCHANT",
                             "LOOT_ROLL_GREED_SELF", "LOOT_ROLL_NEED_SELF", "LOOT_ROLL_PASSED_SELF", "LOOT_ROLL_DISENCHANT_SELF",
                             "LOOT_ROLL_PASSED_AUTO", "LOOT_ROLL_PASSED_AUTO_FEMALE", "LOOT_ROLL_PASSED_SELF_AUTO",
                             "LOOT_ROLL_ROLLED_GREED", "LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_DE",
                             "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS" }) do
            local p = toPattern(_G[g])
            if p then picks[#picks + 1] = p end
        end
        for _, g in ipairs({ "LOOT_ITEM", "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_PUSHED", "LOOT_ITEM_PUSHED_MULTIPLE" }) do
            local p = toPattern(_G[g])
            if p then others[#others + 1] = "^" .. p end
        end
        pcall(add, "CHAT_MSG_LOOT", function(_, _, msg)
            if not readable(msg) then return false end
            for i = 1, #picks do if msg:find(picks[i]) then return true end end
            for i = 1, #others do
                if msg:find(others[i]) then
                    -- The item's quality, from its link's colour.
                    local q = tonumber(msg:match("|cnIQ(%d+):"))
                    if not q then
                        local hex = msg:match("|c%x%x(%x%x%x%x%x%x)|Hitem")
                        hex = hex and hex:lower()
                        q = (hex == "9d9d9d" and 0) or (hex == "ffffff" and 1) or nil
                    end
                    return q ~= nil and q <= 1
                end
            end
            return false
        end)
    end
end

function CH:OnInit(db)
    self.db = db
    pcall(addFilters, db)
    -- (After the game has loaded its own chat settings.)
    local fe = CreateFrame("Frame")
    fe:RegisterEvent("PLAYER_ENTERING_WORLD")
    fe:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(1, defaultFontSize)
    end)
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        pcall(styleTab, i)
        pcall(styleEditBox, i)
    end

    local buttons = {}
    for _, name in ipairs(SIDE_BUTTONS) do
        if _G[name] then table.insert(buttons, _G[name]) end
    end
    for i = 1, n do
        local bf = _G["ChatFrame" .. i .. "ButtonFrame"]
        if bf then table.insert(buttons, bf) end
    end

    -- 20 Hz while the side buttons are fading, 6 Hz at rest.
    local alpha, acc, busy = 0, 0, true
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < (busy and 0.05 or 0.16) then return end
        local step = math.min(acc * 10, 1)
        acc = 0
        -- Underline the selected tab (new windows get styled as they appear).
        local sel = selectedFrame()
        for i = 1, n do
            local tab = _G["ChatFrame" .. i .. "Tab"]
            if tab and not tab.__mui then pcall(styleTab, i); pcall(styleEditBox, i) end
            if tab and tab.__muiLine then
                tab.__muiLine:SetShown(sel == _G["ChatFrame" .. i] and tab:IsShown())
            end
        end
        -- Side buttons fade in while hovering the chat area or the buttons.
        local over = ChatFrame1 and ChatFrame1:IsMouseOver(20, -20, -40, 20)
        for _, b in ipairs(buttons) do over = over or (b:IsShown() and b:IsMouseOver()) end
        local want = over and 1 or 0
        busy = alpha ~= want
        if busy then
            alpha = alpha + (want - alpha) * step
            if math.abs(alpha - want) < 0.02 then alpha = want end
        end
        for _, b in ipairs(buttons) do b:SetAlpha(alpha) end
    end)
end
