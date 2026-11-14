local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Buffs/debuffs.
--  * Target / focus: a row of small rounded icons above the health pill
--    (debuffs first, then buffs).
--  * Party: debuffs then buffs, to the right of each party pill.
--  * Player: Blizzard's own BuffFrame/DebuffFrame are kept (right-click cancel,
--    weapon enchants, Edit Mode placement) and restyled to match.
-- Everything that might be secret in combat goes straight into widgets:
-- icon -> SetTexture, duration -> duration object -> Cooldown swipe,
-- stacks -> GetAuraApplicationDisplayCount when the count is secret.

-- playerRows = false (default): Blizzard's BuffFrame/DebuffFrame, restyled.
-- This client blocks addon code from reading any auras in combat, so only
-- Blizzard's own frames can show a buff gained (or cancelled) mid-fight.
-- playerRows = true: our rows beside the player frame, Blizzard's hidden;
-- they freeze for the length of a fight.
-- attachBlizz: Blizzard's buff / debuff frames are pinned into our layout
-- (A:SeatBlizzard) instead of staying where Edit Mode has them.
local A = ns:NewModule("Auras", { enabled = true, skinBlizzard = true, playerRows = false, playerSide = "left",
    attachBlizz = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local ROUND = MEDIA .. "rounded.tga"
local U = C_UnitAuras

local DISPEL = {
    Magic   = { 0.25, 0.55, 1.00 },
    Curse   = { 0.65, 0.30, 0.95 },
    Disease = { 0.75, 0.52, 0.22 },
    Poison  = { 0.30, 0.80, 0.30 },
}
local DEBUFF = { 0.80, 0.26, 0.26 }

local HARMFUL = { filter = "HARMFUL", harmful = true }
local HELPFUL = { filter = "HELPFUL", harmful = false }

local function mask(owner)
    local m = owner:CreateMaskTexture()
    m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return m
end

-- ── Icon ──────────────────────────────────────────────────────────────────
-- secureIndex: make the icon a secure button that cancels HELPFUL aura #index
-- on right-click (player buffs). Its attributes never change, so the row must
-- show buffs strictly in index order, and it is never shown/hidden in combat
-- (protected); empty slots just go transparent.
local function newIcon(parent, size, secureIndex)
    local b
    if secureIndex then
        b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
        b:SetAttribute("unit", "player")
        b:SetAttribute("*type2", "cancelaura")
        b:SetAttribute("index", secureIndex)
        b:SetAttribute("filter", "HELPFUL")
        b:RegisterForClicks("RightButtonDown", "RightButtonUp")
        b.secure = true
    else
        b = CreateFrame("Frame", nil, parent)
    end
    b:SetSize(size, size)
    b:SetFrameLevel(parent:GetFrameLevel() + 8)
    local inset = 1.5

    local outer = mask(b)
    outer:SetAllPoints()
    local inner = mask(b)
    inner:SetPoint("TOPLEFT", inset, -inset)
    inner:SetPoint("BOTTOMRIGHT", -inset, inset)

    b.ring = b:CreateTexture(nil, "BACKGROUND")
    b.ring:SetAllPoints()
    b.ring:SetColorTexture(unpack(T.border))
    b.ring:AddMaskTexture(outer)

    -- Player buffs: a gold ring that pulses when one of YOUR buffs is about
    -- to run out (Quick Buff will offer it; see A:CheckExpiring).
    if secureIndex then
        b.warn = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        b.warn:SetAllPoints()
        b.warn:SetColorTexture(1.0, 0.80, 0.30, 1)
        b.warn:AddMaskTexture(outer)
        b.warn:Hide()
        local ag = b.warn:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.6); a:SetSmoothing("IN_OUT")
        ag:SetLooping("BOUNCE")
        b.warnAnim = ag
    end

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", inset, -inset)
    b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:AddMaskTexture(inner)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetPoint("TOPLEFT", inset, -inset)
    b.cd:SetPoint("BOTTOMRIGHT", -inset, inset)
    pcall(b.cd.SetSwipeTexture, b.cd, ROUND) -- rounded swipe to match the icon
    b.cd:SetSwipeColor(0, 0, 0, 0.6)
    b.cd:SetDrawEdge(false)
    b.cd:SetHideCountdownNumbers(true)
    -- Aura convention: start bright, darken as time runs out (the default
    -- cooldown draws the remaining time dark, so fresh buffs looked grayed).
    b.cd:SetReverse(true)

    -- Stack count must draw above the cooldown swipe.
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(b.cd:GetFrameLevel() + 1)
    b.count = top:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.count, math.max(8, math.floor(size * 0.42)), "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", 1, -1)

    -- Hover for the tooltip; clicks pass through (except secure cancel buttons).
    b:EnableMouse(true)
    if not b.secure and b.SetMouseClickEnabled then b:SetMouseClickEnabled(false) end
    b:SetScript("OnEnter", function(self)
        if not issecretvalue(self.auraID) and not self.auraID then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self.unit, self.auraID)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    if b.secure then
        b:Show()
        b:SetAlpha(0)
    else
        b:Hide()
    end
    return b
end

local function setVisible(b, on)
    if b.secure then b:SetAlpha(on and 1 or 0) else b:SetShown(on) end
end

local function setIcon(b, unit, a, harmful)
    b.unit, b.auraID = unit, a.auraInstanceID
    b.harmful = harmful
    b.icon:SetTexture(a.icon)

    local apps = a.applications
    if not issecretvalue(apps) then
        b.count:SetText((apps and apps > 1) and apps or "")
    elseif U.GetAuraApplicationDisplayCount then
        local ok, s = pcall(U.GetAuraApplicationDisplayCount, unit, a.auraInstanceID)
        b.count:SetText(ok and s or "")
    else
        b.count:SetText("")
    end

    if harmful then
        local d = a.dispelName
        local c = (type(d) == "string" and not issecretvalue(d) and DISPEL[d]) or DEBUFF
        b.ring:SetColorTexture(c[1], c[2], c[3], 1)
    else
        b.ring:SetColorTexture(unpack(T.border))
    end

    -- Readable timing: permanent auras (duration 0) get no swipe at all;
    -- otherwise a normal cooldown. Only fall back to the duration object when
    -- the values are secret (it filled the whole icon for permanent auras).
    local d, e = a.duration, a.expirationTime
    -- Remember what the expiry check needs (player buff icons only).
    if b.warn then
        local QB = ns.modules.QuickBuff
        local mine = QB and QB.db and QB.db.enabled ~= false and QB.IsRebuffable and QB:IsRebuffable(a.name)
        local readable = not issecretvalue(d) and not issecretvalue(e)
        b.expiresAt = (mine and readable and d and d > 0) and e or nil
        b.auraDur = readable and d or nil
    end
    if not issecretvalue(d) and not issecretvalue(e) then
        if d and e and d > 0 then
            b.cd:SetCooldown(e - d, d)
        else
            b.cd:Clear()
        end
    else
        local ok, dur = false, nil
        if U.GetAuraDuration then ok, dur = pcall(U.GetAuraDuration, unit, a.auraInstanceID) end
        if ok and dur and b.cd.SetCooldownFromDurationObject then
            b.cd:SetCooldownFromDurationObject(dur)
        else
            b.cd:Clear()
        end
    end
end

-- ── Rows ──────────────────────────────────────────────────────────────────
-- Reading auras. In combat this client refuses GetAuraDataByIndex from addon
-- code for auras it treats as secret ("Auras cannot be accessed when secret
-- while tainted"), e.g. a buff gained mid-fight, and the error used to abort
-- the whole refresh so nothing changed until combat ended. Now every read is
-- protected and there are fallbacks, tried in order:
--   1. by index (the normal way)
--   2. by slot (GetAuraSlots + GetAuraDataBySlot)
--   3. GetUnitAuras
--   4. whatever by-index could read, plus auras announced by UNIT_AURA
--      itself (the event hands over the new aura data)
-- Which one worked, and each distinct failure, is noted in
-- MinimalUIDB.auralog (first 40 notes of the session).
local function note(key, text)
    if not MinimalUIDB then return end
    A.noted = A.noted or {}
    if A.noted[key] then return end
    A.noted[key] = true
    local log = MinimalUIDB.auralog
    if not log then log = {}; MinimalUIDB.auralog = log end
    if #log < 40 then log[#log + 1] = date("%H:%M:%S") .. (InCombatLockdown() and " [combat] " or " ") .. text end
end

local slotBuf = {}
local function packSlots(ok, token, ...)
    local n = ok and select("#", ...) or 0
    for i = 1, n do slotBuf[i] = (select(i, ...)) end
    for i = n + 1, #slotBuf do slotBuf[i] = nil end
    return ok, n, (not ok) and token or nil
end

-- Auras the UNIT_AURA event announced, by unit and instance id: used when
-- nothing else can read them. Dropped when the event says they are gone, and
-- wiped out of combat (by then the normal reads work again).
local announced = {}
local function remember(unit, info)
    if type(info) ~= "table" then return end
    local t = announced[unit]
    if type(info.addedAuras) == "table" then
        for _, a in ipairs(info.addedAuras) do
            local id = type(a) == "table" and a.auraInstanceID
            if not issecretvalue(id) and id then
                if not t then t = {}; announced[unit] = t end
                t[id] = a
            end
        end
    end
    if t and type(info.removedAuraInstanceIDs) == "table" then
        for _, id in ipairs(info.removedAuraInstanceIDs) do
            if not issecretvalue(id) then t[id] = nil end
        end
    end
end

local function isHarmful(a)
    local h = a.isHarmful
    if issecretvalue(h) then return nil end
    return h and true or false
end

-- Fills buf with the auras of one filter on the unit; returns how many.
local function listAuras(buf, unit, filter)
    local tag = unit .. " " .. filter
    local n, failedAt, failMsg = 0, nil, nil
    for idx = 1, 40 do
        local ok, a = pcall(U.GetAuraDataByIndex, unit, idx, filter)
        if not ok then failedAt, failMsg = idx, a break end
        if not a then break end
        n = n + 1; buf[n] = a
    end
    if not failedAt then
        for i = n + 1, #buf do buf[i] = nil end
        return n
    end
    note(tag .. " index", tag .. ": by-index failed at #" .. failedAt .. ": " .. tostring(failMsg))
    local partial = n

    -- 2. slots
    if U.GetAuraSlots and U.GetAuraDataBySlot then
        local ok, count, err = packSlots(pcall(U.GetAuraSlots, unit, filter))
        if ok then
            local m, bad = 0, 0
            for i = 1, count do
                local ok2, a = pcall(U.GetAuraDataBySlot, unit, slotBuf[i])
                if ok2 and a then
                    m = m + 1; buf[m] = a
                else
                    bad = bad + 1
                    if not ok2 then note(tag .. " slotdata", tag .. ": GetAuraDataBySlot failed: " .. tostring(a)) end
                end
            end
            note(tag .. " slots", tag .. ": slots gave " .. m .. " of " .. count .. " (by-index gave " .. partial .. ")")
            if bad == 0 and m >= math.max(partial, 1) then
                for i = m + 1, #buf do buf[i] = nil end
                return m
            end
        else
            note(tag .. " slotserr", tag .. ": GetAuraSlots failed: " .. tostring(err))
        end
    end

    -- 3. GetUnitAuras
    if U.GetUnitAuras then
        local ok, list = pcall(U.GetUnitAuras, unit, filter)
        if ok and type(list) == "table" then
            note(tag .. " unitauras", tag .. ": GetUnitAuras gave " .. #list .. " (by-index gave " .. partial .. ")")
            if #list >= math.max(partial, 1) then
                for i = 1, #list do buf[i] = list[i] end
                for i = #list + 1, #buf do buf[i] = nil end
                return #list
            end
        else
            note(tag .. " unitauraserr", tag .. ": GetUnitAuras failed: " .. tostring(list))
        end
    end

    -- Nothing could list the auras: the caller keeps what it shows.
    note(tag .. " blind", tag .. ": no way to list auras right now (by-index gave " .. partial .. " before failing)")
    return 0, true
end

local function rowAllows(row, harmful)
    for _, f in ipairs(row.filters) do if f.harmful == harmful then return true end end
    return false
end

-- The auras can't be listed (combat): never blank the row because of that.
-- Keep what is showing, refresh / drop each icon by its aura's own id where
-- the game allows that, and add auras the UNIT_AURA event announced.
local function fillBlind(row, unit)
    local tag = unit .. " blind"
    for i = 1, #row.icons do
        local b = row.icons[i]
        local id = b.auraID
        if (issecretvalue(id) or id ~= nil) and U.GetAuraDataByAuraInstanceID then
            local ok, a = pcall(U.GetAuraDataByAuraInstanceID, unit, id)
            if ok and a == nil then
                note(tag .. " gone", unit .. ": by-id read works; an aura was dropped that way")
                setVisible(b, false)
                b.auraID, b.expiresAt = nil, nil
            elseif ok then
                note(tag .. " byid", unit .. ": by-id read works for known auras")
                pcall(setIcon, b, unit, a, b.harmful and true or false)
            else
                note(tag .. " byiderr", unit .. ": by-id read failed: " .. tostring(a))
            end
        end
    end
    local t = announced[unit]
    if t then
        for id, a in pairs(t) do
            local showing = false
            for i = 1, #row.icons do
                local bid = row.icons[i].auraID
                if not issecretvalue(bid) and bid == id then showing = true break end
            end
            if not showing then
                local h = isHarmful(a)
                if h == nil then h = false end -- hidden flag: assume a buff
                local fresh = a
                if U.GetAuraDataByAuraInstanceID then
                    local ok, d = pcall(U.GetAuraDataByAuraInstanceID, unit, id)
                    if ok and d == nil then fresh = nil; t[id] = nil elseif ok then fresh = d end
                end
                if fresh and rowAllows(row, h) then
                    for i = 1, #row.icons do
                        local b = row.icons[i]
                        if not issecretvalue(b.auraID) and b.auraID == nil then
                            pcall(setIcon, b, unit, fresh, h)
                            setVisible(b, true)
                            note(tag .. " added", unit .. ": showed an announced aura")
                            break
                        end
                    end
                end
            end
        end
    end
    local last = 0
    for i = 1, #row.icons do local id = row.icons[i].auraID
        if issecretvalue(id) or id ~= nil then last = i end end
    row.shown = last
end

local function hideFrom(row, i)
    for j = i, #row.icons do
        setVisible(row.icons[j], false)
        row.icons[j].auraID = nil
        row.icons[j].expiresAt = nil
    end
end

-- reset: the unit itself changed (new target, roster change), so icons
-- showing now belong to someone else and can't be kept.
local function fill(row, reset)
    local unit = row.frame.unit
    local i = 1
    -- The target's icons are Blizzard's own once its aura container is seated
    -- on our strip (UnitFrames.lua): ours would be a frozen duplicate.
    local UFm = ns.modules.UnitFrames
    if UFm and UFm.liveTargetCont and row.frame == UFm.target then
        hideFrom(row, 1)
        row.shown = 0
        return
    end
    if UnitExists(unit) then
        row.buf = row.buf or {}
        for _, f in ipairs(row.filters) do
            local n, blind = listAuras(row.buf, unit, f.filter)
            if blind then
                if reset then hideFrom(row, 1) end
                fillBlind(row, unit)
                return
            end
            for k = 1, n do
                if i > #row.icons then break end
                -- Protected: a hidden (secret) field tripping one icon must
                -- not stop the rest of the row from updating.
                local ok, err = pcall(setIcon, row.icons[i], unit, row.buf[k], f.harmful)
                if not ok and A.lastError ~= err then
                    A.lastError = err
                    note("icon " .. tostring(err), "icon error: " .. tostring(err))
                    local handler = geterrorhandler()
                    if handler then handler("Auras icon: " .. tostring(err)) end
                end
                setVisible(row.icons[i], true)
                i = i + 1
            end
        end
    end
    hideFrom(row, i)
    row.shown = i - 1
end

-- Fill a row; failures go to the error recorder (/men errors) instead of vanishing.
function A:Fill(row, reset)
    local ok, err = pcall(fill, row, reset)
    if not ok then
        self.lastError = err
        note("fill " .. tostring(err), "fill error (" .. tostring(row.frame.key) .. "): " .. tostring(err))
        local handler = geterrorhandler()
        if handler then handler("Auras fill (" .. tostring(row.frame.key) .. "): " .. tostring(err)) end
    end
    if row.onFill then row.onFill(row) end
end

-- placement(icon, index, size, gap) anchors one icon.
local function newRow(frame, n, size, gap, filters, placement, events, secure)
    local row = { frame = frame, icons = {}, filters = filters }
    for i = 1, n do
        local b = newIcon(frame, size, secure and i or nil)
        placement(b, i, size, gap)
        row.icons[i] = b
    end
    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_AURA", frame.realUnit or frame.unit)
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    for _, e in ipairs(events or {}) do ev:RegisterEvent(e) end
    ev:SetScript("OnEvent", function(_, e, unit, info)
        if e == "UNIT_AURA" then
            -- Everything in the event's payload can be secret in combat
            -- (even isFullUpdate), so it is only looked at under pcall and
            -- never allowed to stop the refresh below.
            local u = row.frame.unit
            local ok, err = pcall(function()
                if type(info) ~= "table" then return end
                local full = info.isFullUpdate
                if issecretvalue(full) then
                    note("secretfull " .. u, u .. ": UNIT_AURA isFullUpdate is secret")
                elseif full then
                    announced[u] = nil
                end
                remember(u, info)
                local list = info.addedAuras
                if type(list) == "table" and not issecretvalue(list) then
                    local a = list[1]
                    if type(a) == "table" then
                        note("announce " .. u, u .. ": UNIT_AURA announces new auras; icon secret="
                            .. tostring(issecretvalue(a.icon)) .. " id secret=" .. tostring(issecretvalue(a.auraInstanceID)))
                    end
                else
                    note("noadded " .. u .. tostring(issecretvalue(list)), u .. ": UNIT_AURA addedAuras type="
                        .. type(list) .. " secret=" .. tostring(issecretvalue(list)))
                end
            end)
            if not ok then note("payload " .. tostring(err), u .. ": UNIT_AURA payload error: " .. tostring(err)) end
        else
            -- Target / focus / roster change, zoning: the announced list and
            -- the icons belong to the old situation.
            announced[row.frame.unit] = nil
            A:Fill(row, e ~= "PLAYER_REGEN_ENABLED" and e ~= "PLAYER_REGEN_DISABLED")
            return
        end
        A:Fill(row)
    end)
    row.ev = ev
    A:Fill(row)
    return row
end

-- ── Blizzard player buffs ─────────────────────────────────────────────────
local BLIZZ_ICON = 22 -- our own rows' icon size
-- In the character panel there is room for two rows of buffs at that size.
-- With more buffs than that, they are drawn smaller (and more to a row), so
-- they still fit above the debuffs instead of running into them.
local SMALL_ICON = 17
local fitBuffs -- (defined with the seating code, below)
local function skinAuraButton(b)
    local icon = b.Icon
    if not icon then return end
    if not b.__mui then
        b.__mui = true
        local back = CreateFrame("Frame", nil, b)
        back:SetPoint("TOPLEFT", icon, "TOPLEFT", -1.5, 1.5)
        back:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1.5, -1.5)
        back:SetFrameLevel(math.max(b:GetFrameLevel() - 1, 0))
        local outer = mask(back)
        outer:SetAllPoints(back)
        local ring = back:CreateTexture(nil, "BACKGROUND")
        ring:SetAllPoints()
        ring:SetColorTexture(unpack(T.border))
        ring:AddMaskTexture(outer)
        b.__muiRing = ring
        b.__muiBack = back

        local inner = mask(b)
        inner:SetAllPoints(icon)
        icon:AddMaskTexture(inner)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Debuff type color moves from Blizzard's square border to our ring.
        if b.DebuffBorder then
            b.DebuffBorder:SetAlpha(0)
            hooksecurefunc(b.DebuffBorder, "SetVertexColor", function(_, r, g, bl)
                ring:SetColorTexture(r, g, bl, 1)
            end)
        end
        if b.TempEnchantBorder then b.TempEnchantBorder:SetAlpha(0) end

        -- Same icon size as our own rows (22), whatever Edit Mode's icon
        -- size slider says: Blizzard sets each button's scale from that
        -- slider, so ours is put back whenever it does. The buttons' grid
        -- offsets are in their own scale, so the whole grid scales with it.
        local w = b:GetWidth()
        if type(w) == "number" and w > 0 then
            local setting = false
            local function fix(self)
                if setting then return end
                local want = (self.__muiSmall and SMALL_ICON or BLIZZ_ICON) / w
                if math.abs(self:GetScale() - want) > 0.005 then
                    setting = true
                    self:SetScale(want)
                    setting = false
                end
            end
            hooksecurefunc(b, "SetScale", fix)
            b.__muiFix = fix
            fix(b)
        end
    end
    -- Timer inside the icon's bottom edge and the stack count in its top
    -- right corner, like a compact version of our own icons (Blizzard hangs
    -- the timer under the icon and re-anchors it on updates).
    if b.Duration and b.Duration.ClearAllPoints then
        b.Duration:ClearAllPoints()
        b.Duration:SetPoint("BOTTOM", icon, "BOTTOM", 0, 1)
    end
    if b.Count and b.Count.ClearAllPoints then
        b.Count:ClearAllPoints()
        b.Count:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 1, 0)
    end
    -- Our ring is a filled rounded plate behind the icon, so an empty slot
    -- (shown button, no icon) would read as a solid gray square. Only show it
    -- when there is actually an icon.
    local hasIcon = false
    pcall(function()
        hasIcon = icon:IsShown() and type(icon:GetTexture()) ~= "nil"
    end)
    b.__muiBack:SetShown(hasIcon)

    -- Blizzard may reset fonts on update: put ours back, but only when it
    -- actually changed (this runs on every aura event).
    local function font(fs, size)
        if fs and fs.GetFont and fs:GetFont() ~= T.font then ns:SetFont(fs, size, "OUTLINE") end
    end
    font(b.Duration, 11)
    font(b.Count, 12)
end

-- The frame builds its buttons the first time it has auras to show, which
-- is after we start: at login there is often no button list yet. (Giving up
-- when it was missing meant the skin never applied at all.) So: hook the
-- frame's own refresh if it has one, and also re-check on every aura change
-- and a few times after login.
local function skinBlizzardFrame(frame)
    if not frame then return end
    -- The gold collapse / expand arrow beside the icons.
    local arrow = frame.CollapseAndExpandButton
    if arrow then
        pcall(function() arrow:SetAlpha(0); arrow:EnableMouse(false) end)
    end
    local function run()
        local list = frame.auraFrames
        if type(list) ~= "table" then return end
        for _, b in ipairs(list) do pcall(skinAuraButton, b) end
        if frame == BuffFrame and fitBuffs then pcall(fitBuffs) end
    end
    run()
    for _, method in ipairs({ "UpdateAuraButtons", "Update", "UpdateAuras" }) do
        if type(frame[method]) == "function" then pcall(hooksecurefunc, frame, method, run) end
    end
    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_AURA", "player")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() C_Timer.After(0, run) end)
    for _, t in ipairs({ 0.5, 2, 5 }) do C_Timer.After(t, run) end
end

-- ── Init ──────────────────────────────────────────────────────────────────
function A:OnInit(db)
    self.db = db
    if MinimalUIDB then MinimalUIDB.auralog = nil end
    -- One-time switch for settings saved while our own rows were the default.
    if not db.blizzBuffsDefault then
        db.blizzBuffsDefault = true
        db.playerRows = false
    end
    local UF = ns.modules.UnitFrames
    if not (UF and UF.target) then return end
    self.rows = {}

    local function above(frame)
        return function(b, i, size, gap)
            b:SetPoint("BOTTOMLEFT", frame.healthPill, "TOPLEFT", (i - 1) * (size + gap), 5)
        end
    end
    local function rightOf(frame)
        -- (Past the power orb, where the frame has one on that end.)
        local skip = frame.orbSide == "RIGHT" and (frame.healthPill:GetHeight() + 4) or 0
        return function(b, i, size, gap)
            b:SetPoint("LEFT", frame.healthPill, "RIGHT", 6 + skip + (i - 1) * (size + gap), 0)
        end
    end

    -- Target: 7 icons stop short of the avatar on the pill's right end.
    -- (A:PlaceTargetRow moves them under the bar in the console's strip.)
    table.insert(self.rows, newRow(UF.target, 7, 22, 3, { HARMFUL, HELPFUL }, above(UF.target),
        { "PLAYER_TARGET_CHANGED" }))
    if UF.focus then
        table.insert(self.rows, newRow(UF.focus, 6, 18, 3, { HARMFUL, HELPFUL }, above(UF.focus),
            { "PLAYER_FOCUS_CHANGED" }))
    end
    for _, pf in ipairs(UF.party or {}) do
        -- Debuffs first (they are what needs acting on), then buffs.
        table.insert(self.rows, newRow(pf, 8, 18, 1, { HARMFUL, HELPFUL }, rightOf(pf), { "GROUP_ROSTER_UPDATE" }))
    end

    if db.playerRows and UF.player then
        local pf = UF.player
        local noop = function() end
        -- Buffs: secure, right-click cancels. Debuffs: a second row below.
        self.playerBuffs = newRow(pf, 12, 22, 3, { HELPFUL }, noop, { "PLAYER_REGEN_ENABLED" }, true)
        self.playerDebuffs = newRow(pf, 8, 22, 3, { HARMFUL }, noop)
        table.insert(self.rows, self.playerBuffs)
        table.insert(self.rows, self.playerDebuffs)
        local relayout = function() A:LayoutPlayerRows() end
        self.playerBuffs.onFill, self.playerDebuffs.onFill = relayout, relayout
        self:LayoutPlayerRows()
        self:HideBlizzardAuras()
        -- Time runs out without aura events: check the warning rings each second.
        C_Timer.NewTicker(1, function() A:CheckExpiring() end)
    elseif db.skinBlizzard then
        skinBlizzardFrame(BuffFrame)
        skinBlizzardFrame(DebuffFrame)
    end
    -- After the bars, orbs and minimap have settled where they are.
    C_Timer.After(0.5, function() A:SeatBlizzard() end)
    C_Timer.After(4, function() pcall(A.ProbeBlizzard, A) end)
end

-- The target's icon row. Normally above its health pill. In the console's
-- target strip the portrait hangs under the middle of the bar, so the icons
-- go under the bar too, either side of it: the first three to the left of
-- the portrait, the rest to the right.
function A:PlaceTargetRow(strip)
    local row = self.rows and self.rows[1]
    local UF = ns.modules.UnitFrames
    local t = UF and UF.target
    if not (row and t and row.frame == t) then return end
    local size, gap = 22, 3
    local step = size + gap
    local pillW, D = t.healthPill:GetWidth(), t.avatar.D
    local leftN = math.max(1, math.floor((pillW / 2 - D / 2 - 4) / step))
    for i, b in ipairs(row.icons) do
        b:ClearAllPoints()
        if strip then
            if i <= leftN then
                -- Counting outward from the portrait, so the first debuff is
                -- the one nearest it.
                b:SetPoint("TOPRIGHT", t.healthPill, "BOTTOM", -(D / 2 + 4) - (i - 1) * step, -4)
            else
                b:SetPoint("TOPLEFT", t.healthPill, "BOTTOM", (D / 2 + 4) + (i - leftN - 1) * step, -4)
            end
        else
            b:SetPoint("BOTTOMLEFT", t.healthPill, "TOPLEFT", (i - 1) * step, 5)
        end
    end
end

-- ── Blizzard's buff frames, pinned into our layout ────────────────────────
-- Only Blizzard's own frames can show auras in combat here, and they belong
-- to Edit Mode. They are not reparented or resized: each is re-anchored to
-- a spot in our layout, and re-anchored again whenever Edit Mode's own
-- layout moves it back (a SetPoint hook, as with the minimap dome). No
-- fields are written on them, so their own (secure) aura code stays clean.
--   player frame shown:  left of the avatar, debuffs under the buffs
--   no player frame:     buffs above the left half of the main action bar,
--                        debuffs above the right half
-- /men buffs attach toggles it (off needs a reload to hand them back).
local seats, seating, hooked = {}, false, {}
local function reseat(frame)
    local s = seats[frame]
    if not s or seating then return end
    seating = true
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint(s[1], s[2], s[3], s[4], s[5])
    end)
    seating = false
end
local function seat(frame, point, rel, rp, x, y)
    if not frame or not rel then return end
    seats[frame] = { point, rel, rp, x, y }
    -- Blizzard keeps these frames wholly on screen. The buff frame is 189
    -- tall and the panel's top is 112 above the screen's bottom edge, so a
    -- frame hung from there was pushed 77 up to fit: that is how far above
    -- the panel the buffs sat. Seated frames may hang off the screen.
    if frame.SetClampedToScreen then
        pcall(frame.SetClampedToScreen, frame, false)
        if not hooked[frame] then
            hooksecurefunc(frame, "SetClampedToScreen", function(self, on)
                if on and seats[self] then pcall(self.SetClampedToScreen, self, false) end
            end)
        end
    end
    if not hooked[frame] then
        hooked[frame] = true
        hooksecurefunc(frame, "SetPoint", function(self, _, r)
            local s = seats[self]
            if s and not seating and r ~= s[2] then reseat(self) end
        end)
    end
    reseat(frame)
end

-- Which corner of its frame Blizzard fills icons from (an Edit Mode choice):
-- the frame has to be pinned by that corner, or the icons land a frame's
-- height / width away from where they were meant to be. (Pinned by the top
-- on a bottom-filling frame, the buffs sat behind the action bar.)
local function fillCorner(frame)
    local c = frame.AuraContainer
    local v, h = "TOP", "RIGHT"
    -- The frame says which way it grows; that is the answer when it is
    -- there. (Working it out from where the container sits went wrong right
    -- after the direction was changed in Edit Mode: the buffs were pinned
    -- by the bottom while filling from the top, and hung in the air above
    -- the panel.)
    if c and type(c.addIconsToTop) == "boolean" and type(c.addIconsToRight) == "boolean" then
        return c.addIconsToTop and "BOTTOM" or "TOP", c.addIconsToRight and "LEFT" or "RIGHT"
    end
    pcall(function()
        if not c then return end
        local cy, cx = (c:GetTop() + c:GetBottom()) / 2, (c:GetLeft() + c:GetRight()) / 2
        local s = c:GetEffectiveScale() / frame:GetEffectiveScale()
        cy, cx = cy * s, cx * s
        if cy - frame:GetBottom() < frame:GetTop() - cy then v = "BOTTOM" end
        if cx - frame:GetLeft() < frame:GetRight() - cx then h = "LEFT" end
    end)
    return v, h
end

-- Icons per row. Blizzard wraps its buff rows at an Edit Mode setting made
-- for the top of the screen (a dozen or so); in the character panel only
-- about half that fits, and the row ran out of the panel over the action
-- bar. So the wrap is set from the room there is: the container's own
-- "icons per row" value, and Blizzard's layout is run again. Whenever
-- Blizzard lays the frame out afresh (which puts its own value back) ours
-- is restored. What the frame offers is noted in MinimalUIDB.buffwrap.
local wraps, rooms, wrapping = {}, {}, false
local wrapTo
local targets, alignSoon -- filled in and defined further down (alignment)
local function applyWrap(fr)
    local n = wraps[fr]
    local c = fr and fr.AuraContainer
    if not (n and c) or wrapping then return end
    local changed = false
    if type(c.iconStride) == "number" and c.iconStride ~= n then c.iconStride = n; changed = true end
    -- Buffs in the panel start at its top and fill downward, whatever Edit
    -- Mode's direction setting says (growing up, they left the panel).
    if fr == BuffFrame and type(c.addIconsToTop) == "boolean" and c.addIconsToTop then
        c.addIconsToTop = false
        changed = true
    end
    if not changed then return end
    wrapping = true
    if fr.UpdateAuraContainerAnchor then pcall(fr.UpdateAuraContainerAnchor, fr) end
    if fr.UpdateGridLayout then pcall(fr.UpdateGridLayout, fr) end
    wrapping = false
end
wrapTo = function(fr, room)
    local c = fr and fr.AuraContainer
    if not c or type(room) ~= "number" then return end
    -- A protected frame is left alone: a value of ours in its layout would
    -- get its icons blocked in combat.
    local prot = fr.IsProtected and fr:IsProtected()
    if prot then
        if MinimalUIDB then
            MinimalUIDB.buffwrap = MinimalUIDB.buffwrap or {}
            MinimalUIDB.buffwrap[fr:GetName() or "?"] = "protected: left alone"
        end
        return
    end
    rooms[fr] = room
    if not hooked[c] and fr.UpdateGridLayout then
        hooked[c] = true
        -- (Also the moment to measure, if no icon was showing before.)
        hooksecurefunc(fr, "UpdateGridLayout", function(self)
            if targets[self] then alignSoon(self) end
            if wrapping then return end
            -- Growing a different way than when it was seated (an Edit Mode
            -- change): seat it again by the new corner.
            local s = seats[self]
            if s then
                local v, h = fillCorner(self)
                if s[1] ~= v .. h and not A.reseating then
                    A.reseating = true
                    C_Timer.After(0.1, function() A.reseating = false; A:SeatBlizzard() end)
                end
            end
            if wraps[self] then applyWrap(self) elseif rooms[self] then pcall(wrapTo, self, rooms[self]) end
        end)
    end
    local ui = UIParent:GetEffectiveScale()
    -- The distance from one icon to the next, measured off two that are
    -- showing; failing that, from the icon size and the container's padding.
    local pitch, width
    local first
    for _, b in ipairs(fr.auraFrames or {}) do
        if b:IsShown() and b:GetLeft() then
            local k = b:GetEffectiveScale() / ui
            width = b:GetWidth() * k
            if first then
                local d = math.abs(b:GetLeft() - first:GetLeft()) * k
                if d > 1 then pitch = d break end
            else
                first = b
            end
        end
    end
    if not width then return end -- nothing showing yet: next time
    if not pitch then
        local pad = type(c.iconPadding) == "number" and c.iconPadding or 5
        pitch = width * (30 + pad) / 30
    end
    local n = math.max(3, math.floor((room + (pitch - width)) / pitch))
    if MinimalUIDB then
        MinimalUIDB.buffwrap = MinimalUIDB.buffwrap or {}
        MinimalUIDB.buffwrap[fr:GetName() or "?"] = string.format(
            "room %.0f width %.1f pitch %.1f -> %d per row; iconStride=%s iconPadding=%s isHorizontal=%s UpdateGridLayout=%s",
            room, width, pitch, n, tostring(c.iconStride), tostring(c.iconPadding), tostring(c.isHorizontal),
            type(fr.UpdateGridLayout))
    end
    wraps[fr] = n
    applyWrap(fr)
end

-- Where the icons really are. Pinning Blizzard's frame by a corner depends
-- on how the frame arranges things inside itself (its height, where it puts
-- the container the icons hang from), and that came out wrong more than
-- once: the buffs ended up a row or three above the panel. So after the
-- frame is seated, the block of icons that is actually showing is measured
-- and the frame is moved by whatever the difference is: the block's top (or
-- bottom) edge onto the wanted line, and its left or right edge, whichever
-- one the icons start from, onto the wanted side. Done again after every
-- layout Blizzard runs, so it also follows rows being added and removed.
targets = {}
local aligning = false
local function alignNow(fr)
    local t = targets[fr]
    local s = seats[fr]
    if not (t and s) or aligning then return end
    local ui = UIParent:GetEffectiveScale()
    local l, r, top, bot
    for _, b in ipairs(fr.auraFrames or {}) do
        if b:IsShown() and b:GetLeft() then
            local k = b:GetEffectiveScale() / ui
            local bl, br, bt, bb = b:GetLeft() * k, b:GetRight() * k, b:GetTop() * k, b:GetBottom() * k
            if not l or bl < l then l = bl end
            if not r or br > r then r = br end
            if not top or bt > top then top = bt end
            if not bot or bb < bot then bot = bb end
        end
    end
    if not l then return end
    local c = fr.AuraContainer
    local toRight = not (c and c.addIconsToRight == false)
    local dx = toRight and (t.x0 - l) or (t.x1 - r)
    local dy = t.top and (t.top - top) or (t.bottom - bot)
    if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then return end
    aligning = true
    s[4], s[5] = s[4] + dx, s[5] + dy
    reseat(fr)
    aligning = false
    if MinimalUIDB then
        MinimalUIDB.buffalign = MinimalUIDB.buffalign or {}
        MinimalUIDB.buffalign[fr:GetName() or "?"] = string.format("moved %.0f, %.0f at %s (point %s)", dx, dy, date("%H:%M:%S"), tostring(s[1]))
    end
end
function alignSoon(fr)
    C_Timer.After(0, function() pcall(alignNow, fr) end)
    C_Timer.After(0.3, function() pcall(alignNow, fr) end)
end

-- Buffs in the character panel: full size up to twelve, small beyond that
-- (back to full size at ten or fewer, so it doesn't flicker at the line).
fitBuffs = function()
    local fr = BuffFrame
    local room = fr and rooms[fr]
    if not room then return end -- not seated in the panel
    local list = fr.auraFrames
    if type(list) ~= "table" then return end
    local n = 0
    for _, b in ipairs(list) do if b:IsShown() then n = n + 1 end end
    local small = A.buffSmall or false
    if n > 12 then small = true elseif n <= 10 then small = false end
    for _, b in ipairs(list) do
        if b.__muiSmall ~= small then
            b.__muiSmall = small
            if b.__muiFix then b.__muiFix(b) end
        end
    end
    if small == A.buffSmall and wraps[fr] then return end
    A.buffSmall = small
    -- Icons per row for that size (an icon and its gap are 35 to 30).
    local size = small and SMALL_ICON or BLIZZ_ICON
    wraps[fr] = math.max(3, math.floor((room + size * 5 / 30) / (size * 35 / 30)))
    applyWrap(fr)
end

function A:SeatBlizzard()
    if not self.db or not self.db.attachBlizz or self.db.playerRows then return end
    local UF, B = ns.modules.UnitFrames, ns.modules.Bars
    local pf = UF and UF.player
    local ROW = 46 -- one row of Blizzard's icons with its timer text
    local slots = B and B.Slots and B:Slots()
    local char = B and B.charSlot
    for k in pairs(targets) do targets[k] = nil end -- (set again below, in the panel layout only)
    if char then
        -- Character panel: to the right of the portrait, buffs from the top
        -- of the well, debuffs along its bottom. Each frame is pinned by the
        -- corner it fills from.
        for i, fr in ipairs({ BuffFrame, DebuffFrame }) do
            if fr then
                -- (First: this can change which way the frame fills.)
                pcall(wrapTo, fr, char.auraX1 - char.auraX0)
                local v, h = fillCorner(fr)
                local x = (h == "RIGHT") and char.auraX1 or char.auraX0
                -- Blizzard's frame has a margin between its own edge and
                -- the first icon. Taken off here, so it's the icons that
                -- start at the edge (tucked up to the portrait), not the
                -- frame: that margin was most of a wasted icon's width.
                local c = fr.AuraContainer
                local l0, l1, r0, r1 = fr:GetLeft(), c and c:GetLeft(), fr:GetRight(), c and c:GetRight()
                if l0 and l1 and r0 and r1 then
                    local k = c:GetEffectiveScale() / fr:GetEffectiveScale()
                    local pad = (h == "RIGHT") and (r0 - r1 * k) or (l1 * k - l0)
                    pad = math.max(0, math.min(24, pad))
                    x = x + ((h == "RIGHT") and pad or -pad)
                end
                local y
                if i == 1 then y = (v == "TOP") and char.auraTop or (char.auraTop - 30)
                else y = (v == "TOP") and (char.auraBottom + 30) or char.auraBottom end
                seat(fr, v .. h, UIParent, "BOTTOMLEFT", x, y)
                -- Buffs hang from the top of the room beside the portrait,
                -- debuffs stand on its bottom.
                targets[fr] = { x0 = char.auraX0, x1 = char.auraX1,
                                top = (i == 1) and char.auraTop or nil, bottom = (i == 2) and char.auraBottom or nil }
                alignSoon(fr)
                C_Timer.After(1.5, function() pcall(alignNow, fr) end)
            end
        end
    elseif slots and (slots.left.x1 - slots.left.x0) >= 100 then
        -- Console layout: seated in the plate's left slot (between the chat
        -- panel and the side bar), buffs in the upper part, debuffs along
        -- the bottom. Each frame is pinned by the corner it fills from.
        local R = slots.left
        local mid = slots.y0 + 34
        for i, fr in ipairs({ BuffFrame, DebuffFrame }) do
            if fr then
                local v, h = fillCorner(fr)
                local x = (h == "RIGHT") and R.x1 or R.x0
                local y
                if i == 1 then y = (v == "TOP") and (slots.y1 - 4) or (mid + 2)
                else y = (v == "TOP") and (mid - 2) or (slots.y0 + 2) end
                seat(fr, v .. h, UIParent, "BOTTOMLEFT", x, y)
            end
        end
    elseif pf and not UF.orbStyleOn and pf.avatar then
        -- Left of the avatar: buffs level with it, debuffs a row below.
        for i, fr in ipairs({ BuffFrame, DebuffFrame }) do
            if fr then
                local v = fillCorner(fr)
                local y = (v == "BOTTOM" and -10 or 16) - (i - 1) * 2 * ROW
                seat(fr, v .. "RIGHT", pf.avatar, "LEFT", -8, y)
            end
        end
    elseif B and B.main and B.db then
        -- No player frame: buffs over the left half of the main bar,
        -- debuffs over the right half, just above the stance / pet row.
        local m, s = B.db.main, B.db.small
        local base = 8 + (s and s.size or 26) + 8
        local blockW = B.split and (3 * m.size + 2 * m.gap) or (B.main:GetWidth() / 2 - 110)
        for i, fr in ipairs({ BuffFrame, DebuffFrame }) do
            if fr then
                local v, h = fillCorner(fr)
                local y = base + (v == "TOP" and ROW or 0)
                if i == 1 then
                    seat(fr, v .. h, B.main, "TOPLEFT", h == "RIGHT" and blockW or 0, y)
                else
                    seat(fr, v .. h, B.main, "TOPRIGHT", h == "RIGHT" and 0 or -blockW, y)
                end
            end
        end
    end
end

-- State of Blizzard's buff frames (MinimalUIDB.buffprobe, and a short
-- version in chat): for when they are pinned but can't be seen.
function A:ProbeBlizzard(toChat)
    local out = {}
    local function f2(v) return type(v) == "number" and string.format("%.0f", v) or tostring(v) end
    local function describe(tag, fr)
        if not fr then out[#out + 1] = tag .. ": missing" return end
        local ok, line = pcall(function()
            local p, rel, rp, x, y = fr:GetPoint(1)
            return tag .. ": shown=" .. tostring(fr:IsShown()) .. " visible=" .. tostring(fr:IsVisible())
                .. " alpha=" .. string.format("%.2f", fr:GetEffectiveAlpha())
                .. " scale=" .. string.format("%.2f", fr:GetEffectiveScale())
                .. " size=" .. f2(fr:GetWidth()) .. "x" .. f2(fr:GetHeight())
                .. " left=" .. f2(fr:GetLeft()) .. " right=" .. f2(fr:GetRight())
                .. " bottom=" .. f2(fr:GetBottom()) .. " top=" .. f2(fr:GetTop())
                .. " strata=" .. tostring(fr:GetFrameStrata())
                .. " anchor=" .. tostring(p) .. ">" .. tostring(rel and (rel.GetName and rel:GetName() or "?"))
                .. " " .. tostring(rp) .. " " .. f2(x) .. "," .. f2(y) .. " points=" .. tostring(fr:GetNumPoints())
        end)
        out[#out + 1] = ok and line or (tag .. " error: " .. tostring(line))
    end
    for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
        local fr = _G[name]
        describe(name, fr)
        if fr then
            describe(name .. ".AuraContainer", fr.AuraContainer)
            local n, shown = 0, 0
            for i, b in ipairs(fr.auraFrames or {}) do
                n = n + 1
                if b:IsShown() then
                    shown = shown + 1
                    if shown <= 2 then describe(name .. " aura" .. i, b) end
                end
            end
            out[#out + 1] = name .. " aura buttons: " .. n .. ", shown: " .. shown
                .. "  seated=" .. tostring(seats[fr] ~= nil)
        end
    end
    out[#out + 1] = "screen " .. f2(UIParent:GetWidth()) .. "x" .. f2(UIParent:GetHeight())
        .. " scale " .. string.format("%.2f", UIParent:GetEffectiveScale())
    if MinimalUIDB then MinimalUIDB.buffprobe = out end
    if toChat then for _, l in ipairs(out) do ns:Print(l) end end
end

ns.commands.buffs = function(rest)
    if rest and rest:find("probe") then
        A:ProbeBlizzard(true)
        return
    end
    if rest and rest:find("attach") then
        A.db.attachBlizz = not A.db.attachBlizz
        if A.db.attachBlizz then
            A:SeatBlizzard()
            ns:Print("Buff frames pinned into the layout.")
        else
            ns.needsReload = true
            ns:Print("Buff frames released: /reload to hand them back to Edit Mode.")
        end
        return
    end
    ns:Print("/men buffs attach  pin the game's buff frames into the layout (toggle)   /men buffs probe  where they are")
end

-- Player rows sit right of the health pill, or left of the avatar growing
-- leftward (db.playerSide). 6 icons per row; once a block wraps, its icons
-- shrink. Buff icons are secure, so they only re-layout out of combat (their
-- grid slots are fixed, so a 7th buff gained in combat still lands in row 2).
local PER_ROW, BIG, SMALL, GAP = 6, 22, 18, 1.5

local function placeBlock(row, anchor, left, size, y0)
    for i, b in ipairs(row.icons) do
        local col, r = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
        local x = 8 + col * (size + GAP)
        local y = y0 - r * (size + GAP)
        b:ClearAllPoints()
        b:SetSize(size, size)
        if left then
            b:SetPoint("TOPRIGHT", anchor, "LEFT", -x, y)
        else
            b:SetPoint("TOPLEFT", anchor, "RIGHT", x, y)
        end
    end
end

function A:LayoutPlayerRows()
    if not self.playerBuffs then return end
    local pf = ns.modules.UnitFrames.player
    local left = self.db.playerSide == "left"
    local anchor = left and (pf.avatar or pf) or pf.healthPill

    if not InCombatLockdown() then
        local n = self.playerBuffs.shown or 0
        local size = n > PER_ROW and SMALL or BIG
        local key = (left and "L" or "R") .. size
        if self.buffKey ~= key then
            placeBlock(self.playerBuffs, anchor, left, size, size / 2)
            self.buffKey, self.buffSize = key, size
            self.buffRows = math.ceil(#self.playerBuffs.icons / PER_ROW)
        end
        self.buffUsedRows = math.max(1, math.ceil(n / PER_ROW))
    end

    -- Debuffs aren't secure: always free to move. They sit under the buff rows in use.
    local bs = self.buffSize or BIG
    local top = bs / 2 - (self.buffUsedRows or 1) * (bs + GAP)
    local dn = self.playerDebuffs.shown or 0
    local dsize = dn > PER_ROW and SMALL or BIG
    local dkey = (left and "L" or "R") .. dsize .. ":" .. top
    if self.debuffKey ~= dkey then
        placeBlock(self.playerDebuffs, anchor, left, dsize, top)
        self.debuffKey = dkey
    end
end

-- Gold pulsing ring on your own buffs that are inside the rebuff window.
function A:CheckExpiring()
    local row = self.playerBuffs
    if not row then return end
    local QB = ns.modules.QuickBuff
    local now = GetTime()
    for _, b in ipairs(row.icons) do
        local low = false
        if b.expiresAt and b.auraID and QB and QB.Threshold then
            low = b.expiresAt - now <= QB:Threshold(b.auraDur)
        end
        if low ~= (b.warn:IsShown()) then
            b.warn:SetShown(low)
            if low then b.warnAnim:Play() else b.warnAnim:Stop() end
        end
    end
end

function A:SetPlayerSide(side)
    if InCombatLockdown() then ns:Print("Can't move buff rows in combat.") return end
    self.db.playerSide = side
    self.buffKey, self.debuffKey = nil, nil
    self:LayoutPlayerRows()
end

-- Blizzard's player aura frames stay in place (Edit Mode owns them) but are
-- invisible and ignore the mouse. Re-checked twice a second because Blizzard
-- refreshes them often.
-- The roots' alpha hides everything under them (alpha multiplies down), so
-- only the roots need alpha 0; the walk is for the mouse (invisible aura
-- buttons would still catch it), and runs less often since new buttons
-- only appear now and then.
local function quiet(f, depth)
    if f.EnableMouse then pcall(f.EnableMouse, f, false) end
    local kids, n = ns.Kids(f, depth)
    for i = 1, n do quiet(kids[i], depth + 1) end
end

function A:HideBlizzardAuras()
    local frames = { BuffFrame, DebuffFrame }
    local function run(walk)
        for _, f in ipairs(frames) do
            if f then
                f:SetAlpha(0)
                if walk then pcall(quiet, f, 0) end
            end
        end
    end
    run(true)
    local acc, walkAcc = 0, 0
    local d = CreateFrame("Frame")
    -- A new buff may mean a new (mouse-catching) button: walk on the next tick.
    d:RegisterUnitEvent("UNIT_AURA", "player")
    d:SetScript("OnEvent", function() walkAcc = 3 end)
    d:SetScript("OnUpdate", function(_, dt)
        acc, walkAcc = acc + dt, walkAcc + dt
        if acc < 0.5 then return end
        acc = 0
        local walk = walkAcc >= 3
        if walk then walkAcc = 0 end
        run(walk)
    end)
end

-- Refresh rows now (e.g. after party test mode swaps units).
function A:RefreshAll()
    for _, row in ipairs(self.rows or {}) do self:Fill(row) end
end

-- /men auralist: what the aura code sees right now, and how many icons each row shows.
ns.commands.auralist = function()
    for _, unit in ipairs({ "player", "target", "focus" }) do
        if UnitExists(unit) then
            for _, f in ipairs({ HARMFUL, HELPFUL }) do
                local names = {}
                for i = 1, 10 do
                    local a = U.GetAuraDataByIndex(unit, i, f.filter)
                    if not a then break end
                    local n = a.name
                    table.insert(names, issecretvalue(n) and "<secret>" or tostring(n))
                end
                ns:Print(unit, f.filter .. ":", #names > 0 and table.concat(names, ", ") or "(none)")
            end
        end
    end
    for _, row in ipairs(A.rows or {}) do
        local shown = 0
        for _, b in ipairs(row.icons) do if b:IsShown() then shown = shown + 1 end end
        ns:Print("row", tostring(row.frame.key), "unit=" .. tostring(row.frame.unit),
            "frame shown=" .. tostring(row.frame:IsShown()), "icons shown=" .. shown)
    end
    for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
        local fr = _G[name]
        if fr and fr.auraFrames then
            local shown, empty = 0, 0
            for _, b in ipairs(fr.auraFrames) do
                if b:IsShown() then
                    shown = shown + 1
                    local ok, has = pcall(function() return type(b.Icon:GetTexture()) ~= "nil" end)
                    if not (ok and has) then empty = empty + 1 end
                end
            end
            ns:Print(name, "buttons:", #fr.auraFrames, "shown:", shown, "shown but empty:", empty)
        end
    end
    ns:Print("last aura error:", tostring(A.lastError))
end
