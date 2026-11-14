local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Quick Buff: out of combat, finds the next buff your class can give that
-- someone in your group (or you) is missing or about to lose, and offers it
-- on one pill button above the action bar. Click it (or its keybind) to cast;
-- it then moves on to the next one. One cast per click is a Blizzard rule.
--
-- Rules: a buff counts as "low" with under db.refresh minutes left (never
-- before 75% of a short buff has run). A weaker rank than your best counts
-- as missing (unless they're 10+ levels below you). A stronger one, or a cast
-- the game bounced ("more powerful spell"), counts as covered. Out-of-range
-- targets are skipped for 20 s. Group versions (Prayer of Fortitude...) are
-- used when db.groupMin people in one party need it and you have the reagent.
-- Combat and boss encounters: hidden (buffs are hidden from addons then, and
-- secure buttons can't retarget).

local QB = ns:NewModule("QuickBuff", { enabled = true, refresh = 2, groupMin = 3 })
local MEDIA = "Interface/AddOns/Meniscus/Media/"

BINDING_HEADER_MINIMALUI = "Meniscus"
_G["BINDING_NAME_CLICK MinimalUIQuickBuff:LeftButton"] = "Quick Buff (cast next buff)"

-- self = only on you; any = alternatives (having any counts; best known is
-- cast); mana = mana users only; tank = tanks (or you when there's none);
-- group = the reagent version.
local CLASS_BUFFS = {
    PRIEST = {
        { name = "Power Word: Fortitude", group = "Prayer of Fortitude" },
        { name = "Divine Spirit", mana = true, group = "Prayer of Spirit" },
        { name = "Shadow Protection", group = "Prayer of Shadow Protection" },
        { name = "Inner Fire", self = true },
        { name = "Touch of Weakness", self = true },
        { name = "Shadowguard", self = true },
    },
    MAGE = {
        { name = "Arcane Intellect", mana = true, group = "Arcane Brilliance" },
        { name = "Armor", self = true, any = { "Mage Armor", "Ice Armor", "Frost Armor" } },
    },
    DRUID = {
        { name = "Mark of the Wild", group = "Gift of the Wild" },
        { name = "Thorns", tank = true },
    },
    SHAMAN = {
        { name = "Water Shield", self = true, any = { "Water Shield", "Lightning Shield" } },
    },
    WARLOCK = {
        { name = "Demon Armor", self = true, any = { "Demon Armor", "Demon Skin" } },
    },
    WARRIOR = { { name = "Battle Shout", self = true } },
    HUNTER = {
        { name = "Aspect of the Hawk", self = true,
          any = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Pack",
                  "Aspect of the Wild", "Aspect of the Beast", "Aspect of the Viper" } },
        { name = "Trueshot Aura", self = true },
    },
    PALADIN = {}, -- blessings: see blessingFor
}

-- Paladin blessings by role/class; the first one you know is used.
local BLESSINGS = {
    TANK = { "Blessing of Kings", "Blessing of Sanctuary", "Blessing of Might" },
    HEALER = { "Blessing of Wisdom", "Blessing of Kings" },
    WARRIOR = { "Blessing of Might" }, ROGUE = { "Blessing of Might" },
    DRUID = { "Blessing of Might", "Blessing of Wisdom" }, SHAMAN = { "Blessing of Might", "Blessing of Wisdom" },
    PALADIN = { "Blessing of Might", "Blessing of Wisdom" },
    HUNTER = { "Blessing of Wisdom", "Blessing of Might" },
}
local CASTER_BLESSINGS = { "Blessing of Wisdom", "Blessing of Might" }

-- ── Helpers ───────────────────────────────────────────────────────────────
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end -- never compare v itself
local function isTrue(v) return not secret(v) and v == true end
local function isFalse(v) return not secret(v) and v == false end

-- Spell info if you know it and it's castable (not passive); cached until
-- your spells change.
local knownCache = {}
local function known(name)
    if not name then return nil end
    local v = knownCache[name]
    if v == nil then
        v = false
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and info and info.spellID and not secret(info.spellID) then
            local k = C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(info.spellID)
            if k == nil and IsSpellKnown then k = IsSpellKnown(info.spellID) end
            local passive = C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(info.spellID)
            if k ~= false and passive ~= true then v = info end
        end
        knownCache[name] = v
    end
    return v or nil
end

local function rankOf(id)
    if not (C_Spell and C_Spell.GetSpellSubtext) then return nil end
    local ok, t = pcall(C_Spell.GetSpellSubtext, id)
    if ok and t and not secret(t) then return tonumber(t:match("%d+")) end
end

-- -1 = theirs is a weaker rank than your best, 1 = stronger, 0 = same/unknown
local function compareRank(theirID, name, u)
    if not theirID or secret(theirID) then return 0 end
    local mine = known(name)
    if not mine or mine.spellID == theirID then return 0 end
    local a, b = rankOf(theirID), rankOf(mine.spellID)
    if not a or not b or a == b then return 0 end
    if a < b then
        -- someone 10+ levels below you can't hold your best rank
        local tl, pl = UnitLevel(u), UnitLevel("player")
        if not secret(tl) and not secret(pl) and tl and pl and tl > 0 and tl < pl - 10 then return 0 end
        return -1
    end
    return 1
end

-- Rebuff threshold for a buff of duration d (seconds).
function QB:Threshold(d)
    local thr = (self.db and self.db.refresh or 2) * 60
    if d and d > 0 then thr = math.min(thr, d * 0.25) end
    return thr
end

local bounced, skipUntil = {}, {}

-- "ok" (has it, enough time left), "low", or "missing"
local function auraState(u, name)
    local b = bounced[u]
    if b and b[name] then
        if b[name] > GetTime() then return "ok" end
        b[name] = nil
    end
    local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, u, name, "HELPFUL")
    if not ok or not a then return "missing" end
    local e, d = a.expirationTime, a.duration
    if secret(e) or secret(d) then return "ok" end
    local cmp = compareRank(a.spellId, name, u)
    if cmp < 0 then return "missing" end
    if not e or e == 0 or cmp > 0 then return "ok" end
    return (e - GetTime() > QB:Threshold(d)) and "ok" or "low"
end

local function namesOf(buff)
    if buff.any then return buff.any end
    buff.own = buff.own or { buff.name }
    return buff.own
end

-- Covered if any alternative (or the group version) is fine.
local function covered(u, buff)
    for _, n in ipairs(namesOf(buff)) do
        if auraState(u, n) == "ok" then return true end
    end
    return buff.group and auraState(u, buff.group) == "ok" or false
end

local function bestSpell(buff)
    for _, n in ipairs(namesOf(buff)) do
        local info = known(n)
        if info then return n, info end
    end
end

local function canReceive(u)
    if not isTrue(UnitExists(u)) then return false end
    if skipUntil[u] and skipUntil[u] > GetTime() then return false end
    if u ~= "player" and isFalse(UnitIsVisible(u)) then return false end
    if isFalse(UnitIsConnected(u)) then return false end
    if isTrue(UnitIsDeadOrGhost(u)) then return false end
    -- someone fighting: their buffs are hidden, they'd all look missing
    if u ~= "player" and isTrue(UnitAffectingCombat(u)) then return false end
    if u ~= "player" then
        local inRange, checked = UnitInRange(u)
        if isTrue(checked) and isFalse(inRange) then return false end
    end
    return true
end

local rangeCache = {}
local function inSpellRange(spell, u)
    if u == "player" then return true end
    if UnitDistanceSquared then
        local d, checked = UnitDistanceSquared(u)
        if not secret(d) and isTrue(checked) and type(d) == "number" then
            local r = rangeCache[spell]
            if not r then
                local info = known(spell)
                r = info and not secret(info.maxRange) and info.maxRange
                if not r or r <= 0 then r = 30 end
                rangeCache[spell] = r
            end
            if d > r * r then return false end
        end
    end
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, r = pcall(C_Spell.IsSpellInRange, spell, u)
        if ok and isFalse(r) then return false end
    end
    return true
end

local PARTY, SELF = { "player", "party1", "party2", "party3", "party4" }, { "player" }
local raidList = {}
local function groupUnits()
    if not isTrue(IsInRaid()) then return PARTY end
    local n = GetNumGroupMembers()
    if secret(n) then n = 40 end
    wipe(raidList)
    for i = 1, math.min(n, 40) do raidList[i] = "raid" .. i end
    return raidList
end

local function subgroupOf(u)
    local i = u:match("^raid(%d+)$")
    if i then
        local _, _, sub = GetRaidRosterInfo(tonumber(i))
        if not secret(sub) and sub then return sub end
    end
    return 0
end

local function isYou(u)
    if u == "player" then return true end
    local ok, same = pcall(UnitIsUnit, u, "player")
    return ok and isTrue(same)
end

local function role(u)
    local r = UnitGroupRolesAssigned(u)
    return not secret(r) and r or nil
end

local tankCache
local function groupHasTank()
    if tankCache == nil then
        tankCache = false
        for _, u in ipairs(groupUnits()) do
            if role(u) == "TANK" then tankCache = true break end
        end
    end
    return tankCache
end

local function wants(buff, u)
    if buff.mana then
        local p = UnitPowerType(u)
        if not secret(p) and p ~= 0 then return false end
    end
    if buff.tank then
        if role(u) ~= "TANK" and not (isYou(u) and not groupHasTank()) then return false end
    end
    return true
end

-- Buffs you have said not to offer (db.skip[name], set on the Quick Buff
-- settings): the pill never asks for them, whoever is missing them.
local function skipped(name)
    local s = QB.db and QB.db.skip
    return s and s[name] or false
end
-- The buffs the pill can offer this character: for the settings list.
function QB.Offered()
    local out, seen = {}, {}
    local _, cls = UnitClass("player")
    local function add(n) if n and not seen[n] then seen[n] = true; out[#out + 1] = n end end
    for _, b in ipairs(CLASS_BUFFS[cls or ""] or {}) do add(b.name) end
    if cls == "PALADIN" then
        for _, list in pairs(BLESSINGS) do for _, n in ipairs(list) do add(n) end end
        for _, n in ipairs(CASTER_BLESSINGS) do add(n) end
    end
    return out
end

local function blessingFor(u)
    local r = role(u)
    local list
    if r == "TANK" or r == "HEALER" then
        list = BLESSINGS[r]
    else
        local _, cls = UnitClass(u)
        if secret(cls) then return nil end
        list = BLESSINGS[cls or ""] or CASTER_BLESSINGS
    end
    for _, n in ipairs(list) do if known(n) and not skipped(n) then return n end end
end

-- ── Scan ──────────────────────────────────────────────────────────────────
local nextCast, count = nil, 0
local slot = {}
local function offer(spell, unit, icon, isGroup)
    count = count + 1
    if nextCast then return end
    slot.spell, slot.unit, slot.icon, slot.group = spell, unit, icon, isGroup
    nextCast = slot
end

local byGroup = {}
local function scan()
    nextCast, count, tankCache = nil, 0, nil
    if isTrue(UnitIsDeadOrGhost("player")) then return end
    local _, cls = UnitClass("player")
    if cls == "PALADIN" then
        for _, u in ipairs(groupUnits()) do
            local b = canReceive(u) and blessingFor(u)
            if b and inSpellRange(b, u) and auraState(u, b) ~= "ok" then
                offer(b, u, known(b).iconID)
            end
        end
    end
    for _, buff in ipairs(CLASS_BUFFS[cls] or {}) do
        local spell, info = bestSpell(buff)
        if spell and not skipped(buff.name) then
            for k in pairs(byGroup) do wipe(byGroup[k]) end
            local need = {}
            for _, u in ipairs(buff.self and SELF or groupUnits()) do
                if canReceive(u) and inSpellRange(spell, u) and wants(buff, u) and not covered(u, buff) then
                    table.insert(need, u)
                    local g = subgroupOf(u)
                    byGroup[g] = byGroup[g] or {}
                    table.insert(byGroup[g], u)
                end
            end
            -- Group version when enough of one party needs it (and you have the reagent).
            local done = {}
            local gInfo = buff.group and known(buff.group)
            local usable = gInfo and (not C_Spell.IsSpellUsable or C_Spell.IsSpellUsable(buff.group) ~= false)
            if usable then
                for _, list in pairs(byGroup) do
                    if #list >= QB.db.groupMin then
                        offer(buff.group, list[1], gInfo.iconID, true)
                        for _, u in ipairs(list) do done[u] = true end
                    end
                end
            end
            for _, u in ipairs(need) do
                if not done[u] then offer(spell, u, info.iconID) end
            end
        end
    end
end

-- ── Button ────────────────────────────────────────────────────────────────
local btn
local W, H = 200, 25 -- starting size; width follows the content
local ARROW_W = 12

local function shortName(spell)
    return (spell or ""):gsub("^Blessing of ", ""):gsub("^Power Word: ", ""):gsub("^Prayer of ", "")
end

-- A pill of any width: two round caps (circle mask) joined by a flat band,
-- drawn as a hairline rim layer under a fill layer. Returns the layer frame.
local CIRCLE = "Interface/CharacterFrame/TempPortraitAlphaMask"
local function pillLayer(parent, level, inset, r, g, b, a)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:SetFrameLevel(level)
    local d = H - inset * 2
    -- Each cap texture covers only the outer half of its circle mask, so it
    -- never overlaps the band (overlaps drew the translucent fill twice).
    local function cap(point, x)
        local m = f:CreateMaskTexture()
        m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetSize(d, d)
        m:SetPoint(point, x, 0)
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetSize(d / 2, d)
        t:SetPoint(point, x, 0)
        t:SetColorTexture(r, g, b, a)
        t:AddMaskTexture(m)
        return t
    end
    f.parts = { cap("LEFT", inset), cap("RIGHT", -inset) }
    local band = f:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", H / 2, -inset)
    band:SetPoint("BOTTOMRIGHT", -H / 2, inset)
    band:SetColorTexture(r, g, b, a)
    table.insert(f.parts, band)
    function f:SetColor(nr, ng, nb, na) for _, t in ipairs(self.parts) do t:SetColorTexture(nr, ng, nb, na) end end
    return f
end

local function buildButton()
    btn = CreateFrame("Button", "MinimalUIQuickBuff", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(W, H)
    btn:RegisterForClicks("AnyDown", "AnyUp")
    -- HIGH: Blizzard's (invisible) pet/stance bar containers sit in MEDIUM
    -- around here and were swallowing the mouse over most of the pill.
    btn:SetFrameStrata("HIGH")
    local base = btn:GetFrameLevel()

    -- rim (accent, pulsing so it's noticed) under the fill: only its edge shows
    local rim = pillLayer(btn, base + 1, 0, T.accent[1], T.accent[2], T.accent[3], 1)
    local fill = pillLayer(btn, base + 2, 1.5, 0.06, 0.06, 0.07, 0.97)
    local ag = rim:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.9); a:SetSmoothing("IN_OUT")
    ag:SetLooping("BOUNCE")
    ag:Play()
    btn.fillLayer = fill

    -- content sits on its own layer above the pill
    local top = CreateFrame("Frame", nil, btn)
    top:SetAllPoints()
    top:SetFrameLevel(base + 3)

    -- round spell icon in the left cap
    local d = H - 6
    local iconMask = top:CreateMaskTexture()
    iconMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    iconMask:SetSize(d, d)
    iconMask:SetPoint("LEFT", 3, 0)
    btn.icon = top:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(d, d)
    btn.icon:SetPoint("LEFT", 3, 0)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:AddMaskTexture(iconMask)

    btn.more = top:CreateFontString(nil, "OVERLAY")
    ns:SetFont(btn.more, 11, "")
    btn.more:SetTextColor(unpack(T.textDim))
    btn.more:SetPoint("RIGHT", -H / 2 + 2, 0)
    -- "Spell  ->  Name": two single-anchor labels (they size to their text,
    -- so no truncation) with a drawn arrow between (the bundled Inter subset
    -- has no arrow glyph).
    local function label()
        local fs = top:CreateFontString(nil, "OVERLAY")
        ns:SetFont(fs, 11, "", true)
        fs:SetTextColor(unpack(T.text))
        fs:SetWordWrap(false)
        return fs
    end
    btn.spellText = label()
    btn.spellText:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
    local arrow = CreateFrame("Frame", nil, top)
    arrow:SetSize(ARROW_W, 8)
    arrow:SetPoint("LEFT", btn.spellText, "RIGHT", 6, 0)
    for _, s in ipairs({ { -5, 0, 5, 0 }, { 5, 0, 1.5, 3.5 }, { 5, 0, 1.5, -3.5 } }) do
        local l = arrow:CreateLine(nil, "OVERLAY")
        l:SetThickness(1.4)
        l:SetColorTexture(unpack(T.textDim))
        l:SetStartPoint("CENTER", arrow, s[1], s[2])
        l:SetEndPoint("CENTER", arrow, s[3], s[4])
    end
    btn.arrow = arrow
    btn.nameText = label()
    btn.nameText:SetPoint("LEFT", arrow, "RIGHT", 6, 0)

    btn:SetScript("OnEnter", function(self)
        self.fillLayer:SetColor(0.12, 0.12, 0.14, 0.97)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.spellName or "Quick Buff", 1, 1, 1)
        local key = GetBindingKey("CLICK MinimalUIQuickBuff:LeftButton")
        GameTooltip:AddLine(key and ("Click or press " .. GetBindingText(key) .. " to cast; then it moves on.")
            or "Click to cast; then it moves on. (Keybind: Options > Keybindings > AddOns > Meniscus)",
            0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.fillLayer:SetColor(0.06, 0.06, 0.07, 0.97)
        GameTooltip:Hide()
    end)
    btn:Hide()
end

local function place()
    local B = ns.modules.Bars
    btn:ClearAllPoints()
    if B and B.main then
        -- Above the pet/stance row that sits on top of the main bar.
        local s = B.db and B.db.small
        local row = (s and s.size or 26) + 8
        local dome = _G.MinimalUI_MinimapDome
        local char = B.charSlot
        if char then
            -- Console: on top of the character panel, where your buffs are
            -- (the name pill is on its bottom edge).
            local wl = char.well
            btn:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", wl.x + wl.w / 2, wl.y + wl.h + 3 + (B.stanceLift or 0))
        elseif B.split and dome then
            -- Minimap dome in the middle: sit right on top of it.
            btn:SetPoint("BOTTOM", dome, "TOP", 0, 6)
        elseif B.split then
            local m = B.db.main
            local blockW = 3 * m.size + 2 * m.gap
            btn:SetPoint("BOTTOM", B.main, "TOPLEFT", blockW / 2, row + 10)
        else
            btn:SetPoint("BOTTOM", B.main, "TOP", 0, row + 10)
        end
    else
        btn:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 110)
    end
end

QB.Place = place

local shown = {}
local inEncounter = false
function QB:Refresh()
    if not btn or InCombatLockdown() or inEncounter then return end
    scan()
    local c = nextCast
    if not c then
        if btn:IsShown() then btn:Hide() end
        btn:SetAttribute("type", nil)
        wipe(shown)
        return
    end
    if shown.spell == c.spell and shown.unit == c.unit and shown.count == count and btn:IsShown() then return end
    shown.spell, shown.unit, shown.count = c.spell, c.unit, count
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", c.spell)
    btn:SetAttribute("unit", c.unit)
    btn.icon:SetTexture(c.icon)
    btn.spellName = c.spell
    local ok, n = pcall(UnitName, c.unit)
    local name = (ok and n and not secret(n)) and n or c.unit
    local who
    if c.group then
        who = isTrue(IsInRaid()) and (name .. "'s group") or "your group"
    else
        who = name -- your own name too, not "you"
    end
    btn.spellText:SetText(shortName(c.spell))
    btn.nameText:SetText(who)
    btn.more:SetText(count > 1 and ("+" .. (count - 1)) or "")
    -- Grow to fit: icon cap + spell + arrow + name + "+n" + right cap (out of combat only).
    local sw, nw = btn.spellText:GetStringWidth() or 0, btn.nameText:GetStringWidth() or 0
    if sw < 1 or (nw < 1 and who ~= "") then
        -- The text hasn't been measured yet (right after a cold start the
        -- font isn't in, and the widths read as zero, which left the pill
        -- at its shortest with the name hanging outside). Fit again
        -- shortly instead of keeping this size.
        shown.spell = nil
        if not QB.refit then
            QB.refit = true
            C_Timer.After(0.5, function() QB.refit = nil; QB:Refresh() end)
        end
    end
    local textW = sw + 6 + ARROW_W + 6 + nw + 4
    local w = 3 + (H - 6) + 6 + textW
        + (count > 1 and (4 + btn.more:GetStringWidth()) or 0) + H / 2 + 2
    btn:SetWidth(math.max(math.floor(w + 0.5), H * 3))
    place()
    btn:Show()
end

-- Is this one of your class's buffs (that you know)? Used by the player
-- aura row to flag your own buffs running low.
function QB:IsRebuffable(name)
    if secret(name) or not name then return false end -- secret first: "not" on a hidden value errors
    local _, cls = UnitClass("player")
    for _, buff in ipairs(CLASS_BUFFS[cls] or {}) do
        for _, n in ipairs(namesOf(buff)) do if n == name then return known(n) ~= nil end end
        if buff.group == name then return known(name) ~= nil end
    end
    if cls == "PALADIN" and name:find("^Blessing of ") then return known(name) ~= nil end
    return false
end

function QB:OnInit(db)
    self.db = db
    buildButton()

    -- Remember each click's aim; react to "out of range" / "more powerful spell".
    local lastAim, lastSpell, lastAt
    btn:HookScript("PreClick", function(self)
        lastAim, lastSpell, lastAt = self:GetAttribute("unit"), self:GetAttribute("spell"), GetTime()
    end)
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("UI_ERROR_MESSAGE")
    watch:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    watch:SetScript("OnEvent", function(_, event, _, msg)
        if not (lastAim and lastAt and GetTime() - lastAt < 1) then return end
        if event == "UI_ERROR_MESSAGE" then
            if secret(msg) or type(msg) ~= "string" then return end
            if msg == ERR_SPELL_OUT_OF_RANGE or msg == ERR_OUT_OF_RANGE then
                skipUntil[lastAim] = GetTime() + 20
            elseif SPELL_FAILED_AURA_BOUNCED and msg:find(SPELL_FAILED_AURA_BOUNCED, 1, true) then
                bounced[lastAim] = bounced[lastAim] or {}
                bounced[lastAim][lastSpell] = GetTime() + 600
            else
                return
            end
            lastAim = nil
            QB:Refresh()
            return
        end
        -- Cast went out at someone else (target out of sight -> self-cast): skip them a while.
        local target, wanted = msg, UnitName(lastAim)
        if lastAim ~= "player" and not secret(target) and not secret(wanted) and target and target ~= ""
            and wanted and (target:match("^[^-]+") or target) ~= (wanted:match("^[^-]+") or wanted) then
            skipUntil[lastAim] = GetTime() + 20
        end
        lastAim = nil
    end)

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
                         "PLAYER_ENTERING_WORLD", "ENCOUNTER_START", "ENCOUNTER_END", "UNIT_AURA" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local dirty = true
    ev:SetScript("OnEvent", function(_, e, unit)
        if e == "UNIT_AURA" then
            if unit and (unit == "player" or unit:find("^party") or unit:find("^raid")) then dirty = true end
            return
        end
        if e == "SPELLS_CHANGED" then wipe(knownCache); wipe(rangeCache) end
        if e == "GROUP_ROSTER_UPDATE" then wipe(bounced); wipe(skipUntil) end
        if e == "ENCOUNTER_START" then inEncounter = true end
        if e == "ENCOUNTER_END" or e == "PLAYER_ENTERING_WORLD" then inEncounter = false end
        if e == "PLAYER_REGEN_DISABLED" or e == "ENCOUNTER_START" then
            -- step aside before combat lockdown (can't retarget mid-fight)
            if not InCombatLockdown() then btn:SetAttribute("type", nil); btn:Hide(); wipe(shown) end
            return
        end
        dirty = true
    end)
    -- Range and timers change without events: check on aura changes, else every 2 s.
    local ticks = 0
    C_Timer.NewTicker(0.5, function()
        ticks = ticks + 1
        if dirty or ticks % 4 == 0 then
            dirty = false
            local ok, err = pcall(QB.Refresh, QB)
            if not ok then QB.lastError = err end
        end
    end)
end

-- /men quickbuff : what it would cast now and why nothing shows.
ns.commands.quickbuff = function()
    if InCombatLockdown() then return ns:Print("Quick Buff is paused in combat.") end
    local ok, err = pcall(scan)
    if not ok then return ns:Print("scan error: " .. tostring(err)) end
    if nextCast then
        ns:Print(string.format("next: %s on %s (%d casts needed)", nextCast.spell, tostring(nextCast.unit), count))
    else
        ns:Print("Everyone's buffed (or nothing you know applies).")
    end
    if QB.lastError then ns:Print("last error: " .. tostring(QB.lastError)) end
end
