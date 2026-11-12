local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Death recap: Meniscus's version of Blizzard's "what killed me" list.
--   header   band with the killing blow's icon (red ring), "Death Recap",
--            "Killed by <source> · <ability>", chip with damage taken
--   list     hits as cards, killing blow first: amount (crits larger), icon,
--            ability, source + "1.2s before", health left on the right
--   footer   Close bottom-left; Link (to chat) on the right
-- Opened by the release popup's Recap button (OpenDeathRecapUI) or
-- Blizzard's frame, which we hide.

local DR = ns:NewModule("DeathRecap", { enabled = true })

local MEDIA = "Interface/AddOns/Meniscus/Media/"
local W = 420
local ROW_H = 46
local ROWS = 7
local TOP = (ns.SHELL_H or 92) + 14
local FOOTER_H = 52
local H = TOP + ROWS * ROW_H + 10 + FOOTER_H
local FILL = { 0.06, 0.06, 0.07, 0.98 }
local CARD = { 0.10, 0.10, 0.115, 1 }
local PILL_OFF = { 0.15, 0.15, 0.17, 1 }
local PILL_HOVER = { 0.21, 0.21, 0.24, 1 }
local PILL_ON = { 0.86, 0.86, 0.89, 1 }
local TEXT_DARK = { 0.08, 0.08, 0.09, 1 }
local RED = { 0.95, 0.42, 0.40, 1 }
local MELEE_ICON = "Interface/Icons/INV_Sword_04"

local call = ns.Call
local function secret(v) return issecretvalue and issecretvalue(v) end
local function num(v) return type(v) == "number" and not secret(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end

local function text(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns:SetFont(fs, size, "", bold)
    fs:SetTextColor(unpack(color or T.text))
    return fs
end

local PILL_OPTS = { h = 24, ring = true, pad = 26, minW = 64 }
local function pill(parent, label, onClick)
    return ns.Pill(parent, label, onClick, PILL_OPTS)
end

-- ── Data ──────────────────────────────────────────────────────────────────
local function spellIcon(id)
    if not num(id) or id <= 0 then return nil end
    if C_Spell and C_Spell.GetSpellTexture then return call(C_Spell.GetSpellTexture, id) end
    return call(_G.GetSpellTexture, id)
end

local ENV = {
    Drowning = "Drowning", Falling = "Falling", Fatigue = "Fatigue",
    Fire = "Fire", Lava = "Lava", Slime = "Slime",
}

local function events(recapID)
    local get = (C_DeathInfo and C_DeathInfo.GetDeathRecapEvents) or _G.GetDeathRecapEvents
    local list = get and call(get, recapID)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        local name, icon = str(e.spellName), spellIcon(e.spellId)
        local ev = str(e.event) or ""
        if ev == "SWING_DAMAGE" then
            name, icon = ACTION_SWING or "Melee", MELEE_ICON
        elseif ev == "ENVIRONMENTAL_DAMAGE" then
            local t = str(e.environmentalType)
            name = (t and (_G["STRING_ENVIRONMENTAL_DAMAGE_" .. t:upper()] or ENV[t] or t)) or "Environment"
            icon = icon or "Interface/Icons/Spell_Fire_Fire"
        end
        local amount = num(e.amount) and e.amount or 0
        table.insert(out, {
            name = name or "Unknown",
            icon = icon or "Interface/Icons/INV_Misc_QuestionMark",
            source = (not e.hideCaster and str(e.sourceName)) or nil,
            amount = amount,
            overkill = num(e.overkill) and e.overkill > 0 and e.overkill or nil,
            crit = e.critical and true or false,
            absorbed = num(e.absorbed) and e.absorbed > 0 and e.absorbed or nil,
            hp = num(e.currentHP) and e.currentHP or nil,
            time = num(e.timestamp) and e.timestamp or nil,
            spellId = num(e.spellId) and e.spellId or nil,
        })
    end
    return out
end

-- ── Window ────────────────────────────────────────────────────────────────
local win, rows, offset, data = nil, {}, 0, {}
local recap

local function makeRow(i)
    local r = CreateFrame("Frame", nil, win)
    r:SetSize(W - 40, ROW_H - 6)
    r:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -(TOP + (i - 1) * ROW_H))
    r.ring = ns.RoundedRect(r, -8, 0, 10, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(r, -7, 1, 9, unpack(CARD))
    r.amount = text(r, 14, true, RED)
    r.amount:SetPoint("RIGHT", r, "LEFT", 62, 0)
    r.amount:SetJustifyH("RIGHT")
    local box = CreateFrame("Frame", nil, r)
    box:SetSize(30, 30)
    box:SetPoint("LEFT", 70, 0)
    ns.RoundedRect(box, -8, 0, 7, T.border[1], T.border[2], T.border[3], 1)
    local mask = box:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", 1, -1); mask:SetPoint("BOTTOMRIGHT", -1, 1)
    r.icon = box:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints(mask)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:AddMaskTexture(mask)
    r.hp = text(r, 10, false, T.textDim)
    r.hp:SetPoint("RIGHT", -12, 0)
    r.hp:SetJustifyH("RIGHT")
    r.name = text(r, 12, true)
    r.name:SetPoint("TOPLEFT", box, "TOPRIGHT", 10, -1)
    r.name:SetPoint("RIGHT", r.hp, "LEFT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sub = text(r, 10, false, T.textDim)
    r.sub:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 10, 1)
    r.sub:SetPoint("RIGHT", r.hp, "LEFT", -8, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        self.ring(unpack(e.first and RED or T.accent))
        ns.TipAnchor(self)
        if not (e.spellId and pcall(GameTooltip.SetSpellByID, GameTooltip, e.spellId)) then
            GameTooltip:SetText(e.name)
        end
        if e.absorbed then GameTooltip:AddLine(e.absorbed .. " absorbed", 0.7, 0.7, 0.75) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        local e = self.entry
        if e and e.first then self.ring(0.45, 0.18, 0.18, 1) else self.ring(T.border[1], T.border[2], T.border[3], 1) end
        GameTooltip:Hide()
    end)
    return r
end

local function fillRow(r, e)
    r.entry = e
    if not e then r:Hide(); return end
    r:Show()
    ns:SetFont(r.amount, e.crit and 17 or 14, "", true)
    r.amount:SetText("-" .. e.amount)
    r.icon:SetTexture(e.icon)
    r.name:SetText(e.name .. (e.crit and "  |cffe6c26bcrit|r" or ""))
    local parts = {}
    if e.source then table.insert(parts, e.source) end
    if e.first then
        table.insert(parts, "|cfff26b66killing blow|r" .. (e.overkill and string.format(" (%d overkill)", e.overkill) or ""))
    elseif e.ago then
        table.insert(parts, string.format("%.1fs before", e.ago))
    end
    r.sub:SetText(table.concat(parts, "   ·   "))
    r.hp:SetText(e.hp and (e.hp .. " HP") or "")
    if e.first then r.ring(0.45, 0.18, 0.18, 1) else r.ring(T.border[1], T.border[2], T.border[3], 1) end
end

local function scroll(delta)
    offset = math.max(0, math.min(offset - delta, math.max(0, #data - ROWS)))
    for i, r in ipairs(rows) do fillRow(r, data[i + offset]) end
    local th = win.thumb
    local maxOff = #data - ROWS
    if maxOff <= 0 then th:Hide(); return end
    th:Show()
    local listH = ROWS * ROW_H - 6
    local size = math.max(24, listH * ROWS / #data)
    th:SetHeight(size)
    th:ClearAllPoints()
    th:SetPoint("TOPRIGHT", win, "TOPRIGHT", -10, -(TOP + (listH - size) * offset / maxOff))
end

local function build()
    win = CreateFrame("Frame", "MinimalUIDeathRecap", UIParent)
    win:SetSize(W, H)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        DR.db.pos = { p, rp, x, y }
    end)
    local pos = DR.db.pos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else win:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
    win:Hide()
    table.insert(UISpecialFrames, "MinimalUIDeathRecap")
    ns.RoundedRect(win, -8, 0, 14, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(win, -7, 1, 13, unpack(FILL))

    win.shell = ns:CreateShell(win)
    win.shell:SetRing(RED)
    win.shell:SetSubtitleWidth(W - 160)

    for i = 1, ROWS do rows[i] = makeRow(i) end
    win.thumb = win:CreateTexture(nil, "OVERLAY")
    win.thumb:SetWidth(3)
    win.thumb:SetColorTexture(0.32, 0.32, 0.36, 1)
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, d) scroll(d) end)
    win.empty = text(win, 11, false, T.textDim)
    win.empty:SetPoint("TOP", win, "TOP", 0, -(TOP + 40))
    win.empty:SetText("No recap for this death.")

    win.footer = ns:CreateFooter(win, FOOTER_H)
    local close = pill(win.footer, CLOSE or "Close", function() win:Hide() end)
    close:SetPoint("LEFT", win.footer, "LEFT", 14, 0)
    win.link = pill(win.footer, "Link to chat", function()
        local link = recap and call(_G.GetDeathRecapLink, recap)
        if not link then return end
        if not ChatEdit_GetActiveWindow() then ChatFrame_OpenChat("") end
        ChatEdit_InsertLink(link)
    end)
    win.link:SetPoint("RIGHT", win.footer, "RIGHT", -14, 0)
end

function DR:Open(recapID)
    if not win then build() end
    recap = recapID
    data = events(recapID)
    -- Killing blow first (Blizzard's order); time as seconds before it.
    local t0 = data[1] and data[1].time
    for i, e in ipairs(data) do
        e.first = i == 1
        e.ago = (t0 and e.time) and math.abs(t0 - e.time) or nil
    end
    offset = 0
    local kb = data[1]
    local sh = win.shell
    sh:SetTitle(DEATH_RECAP_TITLE or "Death Recap")
    if kb then
        sh:SetIcon(kb.icon)
        sh:SetSubtitle("Killed by " .. (kb.source or kb.name) .. (kb.source and ("   ·   " .. kb.name) or ""))
        local total = 0
        for _, e in ipairs(data) do total = total + e.amount end
        sh:SetChip(#data .. (#data == 1 and " hit" or " hits") .. "  ·  -" .. total, RED)
    else
        sh:SetIcon("Interface/Icons/Ability_Rogue_FeignDeath")
        sh:SetSubtitle("")
        sh:SetChip(nil)
    end
    win.empty:SetShown(#data == 0)
    win.link:SetEnabled(_G.GetDeathRecapLink ~= nil and recapID ~= nil)
    scroll(0)
    win:Show()
end

-- ── Blizzard's frame: replaced ────────────────────────────────────────────
local function hookBlizz()
    local f = _G.DeathRecapFrame
    if not f or f.__muiHooked then return end
    f.__muiHooked = true
    if f.OpenRecap then
        hooksecurefunc(f, "OpenRecap", function(self, id) DR:Open(id or self.recapID) end)
    end
    f:HookScript("OnShow", function(self)
        self:Hide()
        if not (win and win:IsShown()) then DR:Open(self.recapID) end
    end)
end

function DR:OnInit(db)
    self.db = db
    if _G.OpenDeathRecapUI then
        hooksecurefunc("OpenDeathRecapUI", function(id)
            hookBlizz()
            DR:Open(id)
            local f = _G.DeathRecapFrame
            if f and f:IsShown() then f:Hide() end
        end)
    end
    hookBlizz()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    ev:RegisterEvent("PLAYER_ALIVE")
    ev:RegisterEvent("PLAYER_UNGHOST")
    ev:SetScript("OnEvent", function(_, e, arg)
        if e == "ADDON_LOADED" then
            if arg == "Blizzard_DeathRecap" then hookBlizz() end
        elseif win and win:IsShown() and not UnitIsGhost("player") then
            win:Hide() -- back on your feet (not just released): the recap is done
        end
    end)
end
