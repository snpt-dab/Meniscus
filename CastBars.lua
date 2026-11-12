local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

local CB = ns:NewModule("CastBars", { enabled = true })

local EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
}
local CHANNEL = {
    UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true,
}
local STOP = {
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
}

local function stop(h)
    h:SetScript("OnUpdate", nil)
    h:Hide()
end

-- Preferred path: duration objects work with secret values via SetTimerDuration.
-- Fallback: raw start/end times, only usable when not secret.
local function start(h, channel)
    local unit = h.unit
    local getDur = channel and UnitChannelDuration or UnitCastingDuration
    local dur = getDur and getDur(unit)
    local info = channel and UnitChannelInfo or UnitCastingInfo

    if dur and h.bar.SetTimerDuration then
        local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
        local dirs = Enum and Enum.StatusBarTimerDirection
        local dir = dirs and (channel and dirs.RemainingTime or dirs.ElapsedTime)
        h.bar:SetTimerDuration(dur, interp, dir)
        h.name:SetText((info(unit)))
        h.path = "duration"
        h:Show()
        return
    end

    local name, _, _, st, et = info(unit)
    if name == nil or issecretvalue(st) or issecretvalue(et) then
        h.path = "unavailable"
        return stop(h)
    end
    h.bar:SetMinMaxValues(st, et)
    h.name:SetText(name)
    h:SetScript("OnUpdate", function(self)
        local now = GetTime() * 1000
        self.bar:SetValue(channel and (st + et - now) or now)
    end)
    h.path = "times"
    h:Show()
end

local function create(parent, unit, below)
    -- 16:1 pill to match the generated mask: parent width (224) x 14.
    local w = parent:GetWidth()
    local h = ns:CreatePillBar(parent, w, w / 16)
    h.unit = unit
    -- The small frame (pet / target-of-target) sits tight under the big
    -- one; while it's shown the cast bar drops below it instead.
    local function place()
        -- Player portrait on the health orb: there is no frame to hang
        -- under, so the bar sits above the orb.
        local UF = ns.modules.UnitFrames
        local O = ns.modules.Orbs
        if unit == "player" and UF and UF.orbStyleOn and O and O.health then
            h:ClearAllPoints()
            local dome, qb = _G.MinimalUI_MinimapDome, _G.MinimalUIQuickBuff
            local B = ns.modules.Bars
            if dome and B and B.charSlot then
                -- Quick Buff lives on the character panel and the target's
                -- portrait stands above the map: the cast bar sits just
                -- clear of the dome's top edge, between the two.
                h:SetPoint("BOTTOM", dome, "TOP", 0, 4)
            elseif dome and qb then
                -- Minimap dome layout: above the Quick Buff pill (which
                -- sits on the dome), whether or not the pill is showing.
                h:SetPoint("BOTTOM", qb, "TOP", 0, 8)
            elseif dome then
                h:SetPoint("BOTTOM", dome, "TOP", 0, 40)
            else
                h:SetPoint("BOTTOM", O.health, "TOP", 0, 14)
            end
            return
        end
        local y = -6
        -- (In the target strip its target sits beside it, not under it.)
        local beside = unit == "target" and UF and UF.targetStrip
        if below and below:IsShown() and not beside then y = y - (ns.SMALL_FRAME_GAP or 8) - below:GetHeight() end
        h:ClearAllPoints()
        if beside then
            -- Target strip: the portrait hangs under the frame, so the cast
            -- bar goes on top of it.
            -- (On the health pill itself: the strip shows no power pill
            -- above it.)
            h:SetPoint("BOTTOM", parent.healthPill or parent, "TOP", 0, 3)
        else
            h:SetPoint("TOP", parent, "BOTTOM", 0, y)
        end
    end
    place()
    h.place = place
    if below then
        below:HookScript("OnShow", place)
        below:HookScript("OnHide", place)
    end
    h:Hide()
    h.bar:SetStatusBarColor(T.accent[1], T.accent[2], T.accent[3], 0.95)

    -- Spell name in two layers, split at the fill's moving edge: light text
    -- where the dark track shows, dark text (like the unit frame names)
    -- where the fill has reached. Each copy is clipped to its own side.
    local fill = h.bar:GetStatusBarTexture()
    local clipFill = CreateFrame("Frame", nil, h.bar)
    clipFill:SetClipsChildren(true)
    clipFill:SetPoint("TOPLEFT", h.bar, "TOPLEFT")
    clipFill:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    local clipTrack = CreateFrame("Frame", nil, h.bar)
    clipTrack:SetClipsChildren(true)
    clipTrack:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    clipTrack:SetPoint("BOTTOMRIGHT", h.bar, "BOTTOMRIGHT")
    local x = (w / 16) / 2 + 2

    h.name = clipTrack:CreateFontString(nil, "OVERLAY")
    ns:SetFont(h.name, 10, "", true)
    h.name:SetTextColor(unpack(T.text))
    h.name:SetShadowOffset(1, -1)
    h.name:SetShadowColor(0, 0, 0, 0.8)
    h.name:SetPoint("LEFT", h, "LEFT", x, 0)

    local dark = clipFill:CreateFontString(nil, "OVERLAY")
    ns:SetFont(dark, 10, "", true)
    dark:SetTextColor(0.07, 0.07, 0.08, 1)
    dark:SetShadowOffset(1, -1)
    dark:SetShadowColor(1, 1, 1, 0.25)
    dark:SetPoint("LEFT", h, "LEFT", x, 0)
    hooksecurefunc(h.name, "SetText", function(_, t) dark:SetText(t) end)
    h.nameDark = dark

    local ev = CreateFrame("Frame")
    for _, e in ipairs(EVENTS) do ev:RegisterUnitEvent(e, unit) end
    ev:SetScript("OnEvent", function(_, event)
        local ok, err = pcall(function()
            if STOP[event] then return stop(h) end
            start(h, CHANNEL[event] or false)
        end)
        if not ok then h.path = "error: " .. tostring(err) end
    end)
    local change = ({ target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED" })[unit]
    if change then
        ev:RegisterEvent(change)
        local base = ev:GetScript("OnEvent")
        ev:SetScript("OnEvent", function(self, event, ...)
            if event == change then
                stop(h)
                pcall(function()
                    if UnitCastingInfo(unit) then start(h, false)
                    elseif UnitChannelInfo(unit) then start(h, true) end
                end)
                return
            end
            base(self, event, ...)
        end)
    end
    return h
end

function CB:OnInit()
    local UF = ns.modules.UnitFrames
    if not (UF and UF.player and UF.target) then return end
    self.player = create(UF.player, "player", UF.pet)
    self.target = create(UF.target, "target", UF.tot)
    if UF.focus then self.focus = create(UF.focus, "focus") end
end

ns.commands.cast = function()
    for _, k in ipairs({ "player", "target", "focus" }) do
        local h = CB[k]
        ns:Print(k, "cast bar path:", tostring(h and h.path))
    end
end
