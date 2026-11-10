local _, ns = ...
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

local function selectedFrame()
    if FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
        local ok, f = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        if ok and f then return f end
    end
    return SELECTED_CHAT_FRAME
end

-- /mui chat : record ChatFrame1's state into MinimalUIDB.chatprobe (chat may
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

function CH:OnInit(db)
    self.db = db
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

    local alpha, acc = 0, 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.05 then return end
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
        alpha = alpha + (want - alpha) * step
        if math.abs(alpha - want) < 0.02 then alpha = want end
        for _, b in ipairs(buttons) do b:SetAlpha(alpha) end
    end)
end
