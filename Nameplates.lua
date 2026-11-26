local _, ns = ...
local CreateFrame = ns.CreateFrame
local T = ns.Theme

-- Nameplates: Blizzard's plates restyled in place (they keep all their
-- logic: colors, threat, debuffs, secret-value handling). Health and cast
-- bars become the same pills as the unit frames: dark track, hairline ring,
-- a bright line riding the end of the fill and a soft sheen. Borders and
-- the selection glow go; instead the ring itself says what the plate is:
--   your target   bright ring
--   elite / rare  gold / silver ring (as on the target's portrait)
--   boss          ember ring
-- Names use the theme font, the cast icon is rounded.
-- Forbidden plates (some instanced enemy plates) can't be touched and are
-- left as Blizzard draws them.

local NP = ns:NewModule("Nameplates", { enabled = true })
local MEDIA = "Interface/AddOns/Meniscus/Media/"

local function zero(obj)
    if not obj or obj.__muiZero or not obj.SetAlpha then return end
    obj.__muiZero = true
    obj:SetAlpha(0)
    hooksecurefunc(obj, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
end

-- Pill-ify a StatusBar: mask its fill (and background), add a ring.
-- Re-picks the mask ratio when the bar is resized.
local function pillify(bar)
    if not bar or bar.__muiPill then return end
    bar.__muiPill = true
    local mask = bar:CreateMaskTexture()
    mask:SetAllPoints(bar)
    local ring = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    ring:SetAllPoints(bar)
    ring:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
    bar.__muiRing = ring
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    bg:AddMaskTexture(mask)
    -- Soft sheen toward the top, as on the unit frame pills.
    local sheen = bar:CreateTexture(nil, "OVERLAY", nil, 4)
    sheen:SetAllPoints(bar)
    sheen:SetColorTexture(1, 1, 1, 1)
    pcall(sheen.SetGradient, sheen, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.14))
    sheen:AddMaskTexture(mask)
    -- Bright line riding the end of the fill.
    local edge = bar:CreateTexture(nil, "OVERLAY", nil, 3)
    edge:SetWidth(1.5)
    edge:SetColorTexture(1, 1, 1, 0.45)
    edge:AddMaskTexture(mask)
    local function ride(fl)
        edge:ClearAllPoints()
        edge:SetPoint("TOPRIGHT", fl, "TOPRIGHT")
        edge:SetPoint("BOTTOMRIGHT", fl, "BOTTOMRIGHT")
    end

    local function fit()
        local w, h = bar:GetSize()
        if not w or not h or h <= 0 then return end
        local base = MEDIA .. "pill" .. ns.PillRatio(w, h)
        mask:SetTexture(base .. "_mask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ring:SetTexture(base .. "_ring.tga")
    end
    fit()
    bar:HookScript("OnSizeChanged", fit)

    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetTexture(T.bar)
        fill:AddMaskTexture(mask)
        ride(fill)
    end
    -- Blizzard swaps the fill texture now and then; keep it flat and masked.
    hooksecurefunc(bar, "SetStatusBarTexture", function(self)
        local f = self:GetStatusBarTexture()
        if f and not f.__muiMasked then f.__muiMasked = true; f:AddMaskTexture(mask) end
        if f then ride(f) end
    end)
    if fill then fill.__muiMasked = true end

    -- Hide Blizzard's own background/border pieces.
    for _, key in ipairs({ "border", "Border", "background", "Background", "bgTexture", "BorderShield" }) do
        if key ~= "BorderShield" then zero(bar[key]) end
    end
    for _, r in ipairs({ bar:GetRegions() }) do
        if r ~= fill and r ~= bg and r ~= ring and r ~= sheen and r ~= edge and r:IsObjectType("Texture") then
            local layer = r:GetDrawLayer()
            if layer == "BACKGROUND" or layer == "BORDER" then zero(r) end
        end
    end
end

local function roundIcon(icon)
    if not icon or icon.__muiRound then return end
    icon.__muiRound = true
    local m = icon:GetParent():CreateMaskTexture()
    m:SetTexture(MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:AddMaskTexture(m)
end

local function fontOf(fs)
    if not fs or fs.__muiFont then return end
    fs.__muiFont = true
    local _, size, flags = fs:GetFont()
    ns:SetFont(fs, size or 10, flags or "")
end

-- Ring colors by what the plate is (the same palette as the target strip).
local GOLD, SILVER, EMBER = { 0.90, 0.72, 0.30 }, { 0.70, 0.78, 0.92 }, { 0.80, 0.22, 0.14 }
local BRIGHT = { 0.92, 0.92, 0.96 }
local function secret(v) return issecretvalue and issecretvalue(v) end

local function healthBarOf(uf)
    return uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
end

-- unit is the plate's token ("nameplate3"). Anything hidden from addons
-- simply leaves the neutral ring.
local function ringFor(uf, unit)
    local hb = healthBarOf(uf)
    local ring = hb and hb.__muiRing
    if not ring or not unit then return end
    local c = T.border
    local kind = UnitClassification and UnitClassification(unit)
    if type(kind) == "string" and not secret(kind) then
        local lvl = UnitLevel(unit)
        if kind == "worldboss" or (type(lvl) == "number" and not secret(lvl) and lvl < 0) then c = EMBER
        elseif (kind == "elite" or kind == "rareelite") and ns.IsBossUnit and ns.IsBossUnit(unit) then c = EMBER
        elseif kind == "elite" or kind == "rareelite" then c = GOLD
        elseif kind == "rare" then c = SILVER end
    end
    local isTarget = UnitIsUnit(unit, "target")
    if not secret(isTarget) and isTarget then c = BRIGHT end
    ring:SetVertexColor(c[1], c[2], c[3], 1)
end

local function stylePlate(plate, unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local uf = plate.UnitFrame
    if not uf then return end
    if not uf.__mui then
        uf.__mui = true
        local hb = healthBarOf(uf)
        pcall(pillify, hb)
        if uf.HealthBarsContainer then
            zero(uf.HealthBarsContainer.border)
            zero(uf.HealthBarsContainer.background)
        end
        -- Blizzard's own "this is your target" glow and its elite dragon: the
        -- ring carries both now.
        zero(uf.selectionHighlight)
        zero(uf.SelectionHighlight)
        local cf = uf.ClassificationFrame
        if cf then zero(cf.classificationIndicator); zero(cf.ClassificationIndicator) end
        local cb = uf.castBar or uf.CastBar
        if cb then
            pcall(pillify, cb)
            pcall(roundIcon, cb.Icon)
            pcall(fontOf, cb.Text)
            zero(cb.Spark)
        end
        pcall(fontOf, uf.name)
        if uf.name and uf.name.SetShadowOffset then
            uf.name:SetShadowOffset(1, -1)
            uf.name:SetShadowColor(0, 0, 0, 0.9)
        end
    end
    pcall(ringFor, uf, unit or plate.namePlateUnitToken or uf.unit)
end

-- ── Combat numbers ────────────────────────────────────────────────────────
-- Our own floating numbers, in place of the game's world text (which can't
-- be had without its purple "XP: 1,650" as well). On unless switched off;
-- while on, the game's own numbers are turned down (see quietGame).
--   * Over a unit's nameplate: what it takes (damage in the spell school's
--     colour, heals in green, "Miss" / "Dodge" and the like, dim). A
--     critical is larger and lands with a small pop.
--   * By your character: what you take (red, to the left) and heals on you
--     (green, to the right).
-- What the game gives is "this unit took this much" (UNIT_COMBAT), not who
-- dealt it: in a group, a mob's numbers are everyone's.
-- Amounts are hidden values in combat: they are handed straight to the
-- text and never read, so there is no "+" in front and no adding up.
local NUM_POOL, NUM_LIFE, NUM_RISE = 40, 1.05, 44
local SCHOOL_TINT = ns.SCHOOL -- (Theme.lua: one list for the whole addon)
local PET_TINT = { 0.86, 0.74, 0.54 }
-- The kind of damage, as the character panel's resistance emblems (and a
-- blade for physical, a star for holy), drawn just left of the number in
-- the number's own colour. A pilot: the client names one school per hit,
-- so a bleed shows as physical and a poison as nature.
local SCHOOL_ICON = { [1] = "micro_stat_melee.tga", [2] = "micro_buff.tga", [4] = "micro_stat_fire.tga",
    [8] = "micro_stat_nature.tga", [16] = "micro_stat_frost.tga", [32] = "micro_stat_shadow.tga",
    [64] = "micro_stat_arcane.tga" }
local WORDS = { MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", RESIST = "Resist",
    IMMUNE = "Immune", ABSORB = "Absorb", EVADE = "Evade", DEFLECT = "Deflect", REFLECT = "Reflect" }
-- The game's own world text: its damage and healing numbers off, and the
-- rest (the XP line, which has no switch) scaled up so far that the game
-- no longer draws it. (Scaled down to nothing it was still there, tiny;
-- a very large scale is what other players report works.) What was there before is
-- kept, and put back when our numbers are switched off.
local QUIET = { floatingCombatTextCombatDamage_v2 = "0", floatingCombatTextCombatHealing_v2 = "0",
    floatingCombatTextPetMeleeDamage_v2 = "0", floatingCombatTextPetSpellDamage_v2 = "0", WorldTextScale_v2 = "1000", WorldTextScale = "1000" }
local function quietGame(on)
    local db = NP.db
    if on then
        db.cvarsWas = db.cvarsWas or {}
        for name, v in pairs(QUIET) do
            local ok, cur = pcall(GetCVar, name)
            if ok and cur ~= nil then
                if db.cvarsWas[name] == nil then db.cvarsWas[name] = cur end
                if cur ~= v then pcall(SetCVar, name, v) end
            end
        end
    elseif db.cvarsWas then
        for name, v in pairs(db.cvarsWas) do pcall(SetCVar, name, v) end
        db.cvarsWas = nil
    end
end
NP.QuietGame = quietGame

-- ── A combat log filter of our own ────────────────────────────────────────
-- The game will not tell an addon who dealt a hit. Its own Combat Log tab
-- knows, though, and each line it prints reaches us as one event with the
-- line's colour readable (the words are sealed). What the log prints, and
-- in what colour, is a filter. An addon may not hand the log one (tried: the
-- "blocked from an action" box), but the game keeps its filters in an
-- ordinary saved table: written out as you log out or reload, read back in
-- and applied by the game's own code as you come in. So ours is put into
-- that table at the very end of a session, and never during one (touching
-- it earlier would get the log's own buttons blocked). The game applies it
-- itself the next time. Nothing of the damage meter is touched.
--
-- The filter passes only what you and your pet do to others: hits, ticks
-- and misses, and heals once the colours are known to come through (a heal
-- line that could not be told from a hit's was the trouble before). Each
-- line is coloured by what it was, one colour a kind, so a line says: a
-- thing of yours, of this kind, happened now.
-- It is the log's first filter while "Meniscus numbers" is the choice, and
-- is taken out again, and the filter that was in use put back, when it is
-- not. (MinimalUIDB.logfilter says what was done and when.)
local LOGNAME = "Meniscus"
local LOG_KINDS = {
    { "SWING_DAMAGE",          0.92, 0.36, 0.30, "swing" },
    { "RANGE_DAMAGE",          0.92, 0.50, 0.26, "shot" },
    { "SPELL_DAMAGE",          0.92, 0.64, 0.22, "spell" },
    { "SPELL_PERIODIC_DAMAGE", 0.86, 0.46, 0.62, "tick" },
    { "DAMAGE_SHIELD",         0.80, 0.72, 0.46, "shield" },
    { "DAMAGE_SPLIT",          0.72, 0.66, 0.52, "split" },
    { "SWING_MISSED",          0.56, 0.60, 0.70, "swingmiss" },
    { "RANGE_MISSED",          0.56, 0.66, 0.74, "shotmiss" },
    { "SPELL_MISSED",          0.56, 0.72, 0.78, "spellmiss" },
    { "SPELL_PERIODIC_MISSED", 0.62, 0.56, 0.76, "tickmiss" },
    { "DAMAGE_SHIELD_MISSED",  0.68, 0.62, 0.80, "shieldmiss" },
    { "SPELL_HEAL",            0.42, 0.90, 0.50, "heal" },
    { "SPELL_PERIODIC_HEAL",   0.42, 0.80, 0.64, "healtick" },
    { "PARTY_KILL",            0.94, 0.88, 0.58, "kill" },
    -- (Seen: the log paints a spell that misses in a grey of its own,
    -- whatever colour its kind was given. Known by that grey.)
    { "",                      0.50, 0.50, 0.50, "miss" },
}
local LOG_HEALS = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
local FLAG_MINE = _G.COMBATLOG_FILTER_MINE or 17681
local FLAG_PET = _G.COMBATLOG_FILTER_MY_PET or 12561
-- What kind of line a colour stands for (nil: not one of ours).
local function logKind(r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" or secret(r) or secret(g) or secret(b) then return nil end
    for i = 1, #LOG_KINDS do
        local k = LOG_KINDS[i]
        if math.abs(r - k[2]) < 0.02 and math.abs(g - k[3]) < 0.02 and math.abs(b - k[4]) < 0.02 then return k[5] end
    end
    -- (The log brightens a line it means to stand out by half again.)
    for i = 1, #LOG_KINDS do
        local k = LOG_KINDS[i]
        if math.abs(r - math.min(1, k[2] * 1.5)) < 0.02 and math.abs(g - math.min(1, k[3] * 1.5)) < 0.02
           and math.abs(b - math.min(1, k[4] * 1.5)) < 0.02 then return k[5] end
    end
    return nil
end
local function copyTable(t, depth)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" and depth < 8 then out[k] = copyTable(v, depth + 1) else out[k] = v end
    end
    return out
end
-- At the end of a session: ours in (first, and in use), or out.
local function logFilterSync()
    local db = NP.db
    if not db or not MinimalUIDB then return end
    local rec = MinimalUIDB.logfilter
    if type(rec) ~= "table" then rec = {}; MinimalUIDB.logfilter = rec end
    local F = _G.Blizzard_CombatLog_Filters
    if type(F) ~= "table" or type(F.filters) ~= "table" then
        rec.note = date("%H:%M:%S") .. " the log has no list of filters to add to"
        return
    end
    local list = F.filters
    local function indexOf(name)
        if type(name) ~= "string" then return nil end
        for i = 1, #list do
            local f = list[i]
            if type(f) == "table" and f.name == name then return i end
        end
    end
    local cur = tonumber(F.currentFilter)
    local curName = cur and type(list[cur]) == "table" and list[cur].name or nil
    if type(curName) == "string" and curName ~= LOGNAME then rec.was = curName end
    -- Ours comes out first, wherever it is: it is built afresh each time.
    local had = false
    for i = #list, 1, -1 do
        local f = list[i]
        if type(f) == "table" and f.name == LOGNAME then table.remove(list, i); had = true end
    end
    local want = db.enabled ~= false and db.numbersMode == "ours" and db.numbersMine ~= false and db.numbersLog ~= false
    if not want then
        if had then
            F.currentFilter = indexOf(rec.was) or 1
            rec.on = false
            rec.note = date("%H:%M:%S") .. " taken out; the log is back on \"" .. tostring(rec.was or "its first filter") .. "\""
        end
        return
    end
    local base = list[1]
    if type(base) ~= "table" then
        if had then F.currentFilter = 1 end
        rec.note = date("%H:%M:%S") .. " the log has no filter to model ours on"
        return
    end
    local withHeals = rec.typed == true
    local mine = copyTable(base, 0)
    mine.name, mine.quickButtonName = LOGNAME, LOGNAME
    mine.tooltip = "Only your own hits, a colour for each kind. Meniscus reads these to tell which numbers are yours."
    mine.hasQuickButton, mine.onQuickBar = true, true
    mine.quickButtonDisplay = { solo = true, party = true, raid = true }
    if type(mine.settings) ~= "table" then mine.settings = {} end
    local st = mine.settings
    st.lineColoring, st.lineColorPriority, st.lineHighlighting, st.showHistory, st.timestamp = true, 3, true, false, false
    st.missColoring = false
    -- (Nothing but words and numbers in a line, and the short wording: no
    -- raid mark drawn before a name, no brackets round one. A line's own
    -- text is drawn as a number, in a typeface where only the numerals
    -- show: see "A number from a log line's own text".)
    st.unitIcons, st.braces, st.fullText = false, false, false
    -- (And the amount in the line's own colour, not picked out in white or
    -- in a colour of the log's: a number drawn from a line is then the
    -- colour it is given here, and a critical's two tinted copies are tinted.)
    st.amountHighlighting, st.amountColoring, st.amountActorColoring, st.amountSchoolColoring = false, false, false, false
    if type(mine.colors) ~= "table" then mine.colors = {} end
    local c = mine.colors
    -- (The kill notice stays a line the log brightens. Should the log colour
    -- by who acted after all, the notice still comes out white, which is how
    -- the older rules know it; in its own colour, brightened, it is still
    -- known here.)
    c.eventColoring, c.highlightedEvents = {}, { PARTY_KILL = true }
    -- (Should the log colour by who acted after all, you and your pet at
    -- least come apart: a hair off the grey it uses for both.)
    if type(c.unitColoring) ~= "table" then c.unitColoring = {} end
    c.unitColoring[FLAG_MINE] = { a = 1, r = 0.70, g = 0.70, b = 0.72 }
    c.unitColoring[FLAG_PET] = { a = 1, r = 0.70, g = 0.72, b = 0.70 }
    -- Every kind of line the log knows, off; then ours, on.
    local events = {}
    if type(base.filters) == "table" then
        for _, sub in pairs(base.filters) do
            if type(sub) == "table" and type(sub.eventList) == "table" then
                for ev in pairs(sub.eventList) do
                    if type(ev) == "string" then events[ev] = false end
                end
            end
        end
    end
    for i = 1, #LOG_KINDS do
        local k = LOG_KINDS[i]
        if k[1] ~= "" and (withHeals or not LOG_HEALS[k[1]]) then
            events[k[1]] = true
            c.eventColoring[k[1]] = { a = 1, r = k[2], g = k[3], b = k[4] }
        end
    end
    mine.filters = {
        { eventList = events, sourceFlags = { [FLAG_MINE] = true } },
        { eventList = copyTable(events, 0), sourceFlags = { [FLAG_PET] = true } },
    }
    table.insert(list, 1, mine)
    F.currentFilter = 1
    rec.on, rec.heals = true, withHeals
    rec.note = date("%H:%M:%S") .. " put in as the log's first filter" .. (withHeals and ", heals among its lines" or "")
end
do
    local lo = CreateFrame("Frame")
    lo:RegisterEvent("PLAYER_LOGOUT")
    lo:SetScript("OnEvent", function()
        local ok, err = pcall(logFilterSync)
        if not ok and MinimalUIDB then MinimalUIDB.logfilterErr = date("%H:%M:%S") .. " " .. tostring(err) end
    end)
end
-- A little after login: is the log on our filter? Said in chat when it is
-- not, with what to do about it.
local function logFilterTell()
    local db = NP.db
    if not db or db.numbersMode ~= "ours" or db.numbersMine == false or db.numbersLog == false then return end
    local state = "absent"
    local cur = _G.Blizzard_CombatLog_CurrentSettings
    local name = type(cur) == "table" and cur.name
    if type(name) == "string" and not secret(name) and name == LOGNAME then
        state = "in use"
    else
        local F = _G.Blizzard_CombatLog_Filters
        if type(F) == "table" and type(F.filters) == "table" then
            for i = 1, #F.filters do
                local f = F.filters[i]
                if type(f) == "table" and f.name == LOGNAME then state = "set aside" end
            end
        end
    end
    if MinimalUIDB then
        local rec = MinimalUIDB.logfilter
        if type(rec) ~= "table" then rec = {}; MinimalUIDB.logfilter = rec end
        rec.seen = date("%H:%M:%S") .. " after login our filter was " .. state
            .. "; the log's own: " .. tostring(type(name) == "string" and not secret(name) and name or "?")
    end
    if state == "absent" then
        ns:Print("Combat numbers: the Combat Log filter that tells your hits from everyone else's goes in as the game saves your settings. /reload once more to switch it on.")
    elseif state == "set aside" then
        ns:Print("Combat numbers: the Combat Log is on another filter, so the older rules are deciding whose hits are whose. Click \"" .. LOGNAME .. "\" in the Combat Log tab to go back.")
    end
end

-- ── The lab (/men lab, then reload) ───────────────────────────────────────
-- Trials that write down what they find and change nothing that is shown,
-- but for three small marks under each of your numbers. Off unless asked
-- for, and only with Meniscus numbers.
--
-- The one being tried: matching a hit to yours by its amount, with nothing
-- read. Amounts are hidden values in a fight; they can be handed to a bar
-- but not compared. The game's damage meter keeps your running total (also
-- hidden), and it is left alone here: only read, before and after a blow of
-- yours. A hit is that blow if
--     total before + the hit's amount = total after,
-- and bars can be made to say so by where they end. Three bars, a fixed
-- number of pixels to a point of damage: the "after" bar hangs down from a
-- spot; the "before" bar stands on the after bar's far end; the "amount"
-- bar stands on the before bar's end. If the sum holds, the amount bar ends
-- exactly at the spot; if it is off by even one, it ends a hundred pixels
-- away. A small window is hung on that end, and a mark sits at the spot,
-- drawn only through the window: seen when the sum holds, and not
-- otherwise. Nothing here ever learns a number.
--
-- Under each number, while the lab is on:
--   white  nothing + amount = amount: always true, so always seen if the
--          bars work with hidden amounts at all;
--   red    one + amount = amount: never true, so never seen if a wrong
--          sum really does hide the mark;
--   green  the meter's total before and after the blow of yours this hit
--          was paired with: seen when the hit's amount is exactly what the
--          meter added.
--   blue   the same, with your ticks since the blow before counted into
--          the sum (first trial: white always, red never, green only now
--          and then, which is what ticks reaching the meter late, along
--          with your next blow, would do).
-- Also written down: the same bars measured with plain numbers at login
-- (MinimalUIDB.labgeo), what the fill of a bar holding a hidden amount says
-- of itself (labfill), and the game's console settings to do with floating
-- text (labcvars; looking for a switch for its XP line).
local G_S, G_H, G_Y = 128, 56, -15 -- pixels to a point of damage; half the window's height; the mark, below the number's middle
local labM = 20000                 -- the most the bars can hold (kept above your total on the meter)
local function labOn()
    return MinimalUIDB and MinimalUIDB.lab == true and NP.db and NP.db.numbersMode == "ours" or false
end
local labFillN = {}
local function labFill(bar, when)
    if not bar then return end
    local okS, sh = pcall(function() return bar:GetStatusBarTexture():IsShown() end)
    local key = when .. ": " .. ((not okS and "error") or (secret(sh) and "hidden") or (sh and "shown" or "not shown"))
    labFillN[key] = (labFillN[key] or 0) + 1
    if MinimalUIDB then
        local parts = {}
        for k, n in pairs(labFillN) do parts[#parts + 1] = k .. " x" .. n end
        table.sort(parts)
        MinimalUIDB.labfill = table.concat(parts, "; ")
    end
end
local function newGauge(host, dx, r, g, b, extra)
    local G = { extra = extra or 0, more = {} }
    local function bar(reverse)
        local sb = CreateFrame("StatusBar", nil, host)
        sb:SetOrientation("VERTICAL")
        sb:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
        sb:SetStatusBarColor(0, 0, 0, 0)
        sb:SetSize(2, 10)
        sb:SetMinMaxValues(-1, 1)
        sb:SetValue(0)
        if reverse then sb:SetReverseFill(true) end
        return sb
    end
    G.now, G.before, G.amt = bar(true), bar(false), bar(false)
    G.now:SetPoint("TOP", host, "CENTER", dx, G_Y)
    G.before:SetPoint("BOTTOM", G.now:GetStatusBarTexture(), "BOTTOM")
    -- (More bars may stand between "before" and "amount": other amounts to
    -- be counted into the sum. One not in use holds 0, a pixel-step tall,
    -- which the window's place allows for.)
    local last = G.before
    for i = 1, G.extra do
        local sb = bar(false)
        sb:SetPoint("BOTTOM", last:GetStatusBarTexture(), "TOP")
        G.more[i] = sb
        last = sb
    end
    G.amt:SetPoint("BOTTOM", last:GetStatusBarTexture(), "TOP")
    G.win = CreateFrame("Frame", nil, host)
    G.win:SetClipsChildren(true)
    G.win:SetSize(12, G_H * 2)
    G.win:SetPoint("TOP", G.amt:GetStatusBarTexture(), "TOP", 0, G_H - G_S * (1 + G.extra))
    G.spot = CreateFrame("Frame", nil, G.win)
    G.spot:SetSize(7, 7)
    G.spot:SetPoint("CENTER", host, "CENTER", dx, G_Y)
    local t = G.spot:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture(MEDIA .. "circle.tga")
    t:SetVertexColor(r, g, b, 1)
    G.win:Hide()
    return G
end
-- (Every bar runs from -1, so none is ever empty: an empty fill has no
-- place for the next bar to stand on.)
local function setGauge(G, before, amount, now, also)
    local h = G_S * (labM + 1)
    G.now:SetHeight(h); G.before:SetHeight(h); G.amt:SetHeight(h)
    G.now:SetMinMaxValues(-1, labM); G.before:SetMinMaxValues(-1, labM); G.amt:SetMinMaxValues(-1, labM)
    local ok = pcall(G.now.SetValue, G.now, now)
    for i = 1, G.extra do
        local sb = G.more[i]
        sb:SetHeight(h); sb:SetMinMaxValues(-1, labM)
        if also and also[i] ~= nil then ok = pcall(sb.SetValue, sb, also[i]) and ok else sb:SetValue(0) end
    end
    ok = pcall(G.before.SetValue, G.before, before) and ok
    ok = pcall(G.amt.SetValue, G.amt, amount) and ok
    G.win:SetShown(ok)
    return ok
end
-- The bars measured with plain numbers, which can be read back: do they end
-- where the sum says, at small totals and at large ones?
local function labCalibrate()
    if not MinimalUIDB then return end
    local out = { date("%H:%M:%S") }
    MinimalUIDB.labgeo = out
    local okB, probe = pcall(CreateFrame, "StatusBar", nil, UIParent)
    if not okB or not probe then out[#out + 1] = "no bar to measure with: " .. tostring(probe) return end
    probe:SetSize(100, 4)
    probe:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -60)
    probe:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
    out[#out + 1] = "reverse fill " .. (type(probe.SetReverseFill) == "function" and "there" or "MISSING")
        .. ", fill style " .. (type(probe.SetFillStyle) == "function" and "there" or "missing")
    local steps = {}
    local function add(fn) steps[#steps + 1] = fn end
    local function plainCase(label, lo, hi, v)
        local function read(when)
            local okP, err = pcall(function()
                local fl = probe:GetStatusBarTexture()
                out[#out + 1] = string.format("plain bar, %s (%s to %s, at %s), %s: fill shown %s, %.1f wide of 100",
                    label, lo, hi, v, when, tostring(fl:IsShown()), fl:GetWidth())
            end)
            if not okP then out[#out + 1] = "plain bar, " .. label .. ", " .. when .. ": " .. tostring(err):sub(1, 110) end
        end
        add(function() pcall(function() probe:SetMinMaxValues(lo, hi); probe:SetValue(v) end); read("at once") end)
        add(function() read("a moment on") end)
    end
    plainCase("at its least", 0, 1, 0)
    plainCase("above its least", 0, 1, 1)
    plainCase("part way", 5, 9, 7)
    plainCase("least and most the same", 5, 5, 5)
    add(function() pcall(function() probe:SetReverseFill(true); probe:SetMinMaxValues(0, 10); probe:SetValue(3) end) end)
    add(function()
        local okP, err = pcall(function()
            local fl = probe:GetStatusBarTexture()
            out[#out + 1] = string.format("plain bar, filled from its far end, at 3 of 10: fill starts %.1f in from the left and is %.1f wide (70 and 30 if that works)",
                fl:GetLeft() - probe:GetLeft(), fl:GetWidth())
        end)
        if not okP then out[#out + 1] = "plain bar, filled from its far end: " .. tostring(err):sub(1, 110) end
        pcall(function() probe:SetReverseFill(false) end)
    end)
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(10, 10)
    host:SetPoint("CENTER")
    host:SetAlpha(0)
    local okG, G = pcall(newGauge, host, 0, 1, 1, 1)
    if not okG then out[#out + 1] = "the three bars could not be built: " .. tostring(G):sub(1, 160) end
    local function gaugeCase(label, m, before, amount, now)
        local function read(when)
            local okR, err = pcall(function()
                local _, cy = host:GetCenter()
                local top = G.amt:GetStatusBarTexture():GetTop()
                local nb = G.now:GetStatusBarTexture():GetBottom()
                local bt = G.before:GetStatusBarTexture():GetTop()
                out[#out + 1] = string.format("%s, %s: window off by %.2f (0 = lined up); bars %.0f tall, asked %.0f; after-bar runs %.1f down (should be %.0f); before-bar %.1f up (should be %.0f)",
                    label, when, top - (cy + G_Y + G_S), G.now:GetHeight(), G_S * (m + 1), (cy + G_Y) - nb, G_S * (now + 1), bt - nb, G_S * (before + 1))
            end)
            if not okR then out[#out + 1] = label .. ", " .. when .. ": " .. tostring(err):sub(1, 160) end
        end
        add(function()
            local keep = labM
            labM = m
            local ok = pcall(setGauge, G, before, amount, now)
            labM = keep
            if not ok then out[#out + 1] = label .. ": could not be set" end
            read("at once")
        end)
        add(function() read("a moment on") end)
    end
    if okG then
        gaugeCase("small, the sum holds", 20000, 1000, 57, 1057)
        gaugeCase("small, one too many", 20000, 1000, 58, 1057)
        gaugeCase("first blow of a fight", 20000, 0, 57, 57)
        gaugeCase("a hit for nothing", 20000, 1000, 0, 1000)
        gaugeCase("middling, the sum holds", 200000, 150000, 57, 150057)
        gaugeCase("large, the sum holds", 1000000, 800000, 300, 800300)
        gaugeCase("large, one too few", 1000000, 800000, 299, 800300)
    end
    local i = 0
    C_Timer.NewTicker(0.12, function()
        i = i + 1
        local fn = steps[i]
        if fn then pcall(fn) end
        if i >= #steps then pcall(function() host:Hide(); probe:Hide() end) end
    end, #steps)
end
-- The console's settings to do with floating text, once: is there a switch
-- for the game's XP line by itself?
local function labCensus()
    if not MinimalUIDB or (type(MinimalUIDB.labcvars) == "table" and MinimalUIDB.labcvars.v == 1) then return end
    local out = { v = 1 }
    MinimalUIDB.labcvars = out
    local get = (C_Console and C_Console.GetAllCommands) or _G.ConsoleGetAllCommands
    local ok, all = pcall(get)
    if not ok or type(all) ~= "table" then
        out[1] = "the list of console settings can't be had: " .. tostring(all):sub(1, 100)
        return
    end
    local n, total = 0, 0
    for _, c in pairs(all) do
        total = total + 1
        local name = type(c) == "table" and c.command
        if type(name) == "string" then
            local l = name:lower()
            if l:find("worldtext") or l:find("floating") or l:find("combattext") or l:find("damagetext") or l:find("scrolling")
               or l:find("experience") or (l:find("xp") and not l:find("expan") and not l:find("expl") and not l:find("expo")) then
                n = n + 1
                if n <= 140 then
                    local okV, v = pcall(GetCVar, name)
                    out[#out + 1] = name .. " = " .. tostring(okV and v or "?") .. "  | " .. tostring(c.help or ""):sub(1, 100)
                end
            end
        end
    end
    out[#out + 1] = n .. " matched, of " .. total
end
ns.commands.lab = function()
    if not MinimalUIDB then return end
    MinimalUIDB.lab = not MinimalUIDB.lab or nil
    ns:Print("Combat text lab: " .. (MinimalUIDB.lab and "on. With Meniscus numbers chosen, reload: your hits then carry small test marks under them."
        or "off (reload to be rid of the marks)."))
end

local function buildNumbers()
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetAllPoints()
    host:SetFrameStrata("HIGH")
    local items, spawned = {}, 0
    local driver = CreateFrame("Frame")
    driver:Hide()
    -- How a number looks and moves (larger than the first version, and
    -- dressed a little, in the addon's own way):
    --   * a soft dark patch behind it, so it reads over grass or snow
    --     without a hard outline box;
    --   * it opens small and settles to size in a tenth of a second, then
    --     drifts up and a little outward, like a spark leaving a fire;
    --   * a critical is larger, lands with a pop, and for a moment shows
    --     the lens fringe the Quick Buff pill has: a faint warm copy to one
    --     side and a cool one to the other, closing in to a narrow one
    --     that stays, and shifts a little, while the number rises and fades.
    local SIZE = 20
    -- Easier to see (0.1.515), two settings on the Combat page: how large
    -- the numbers are and how dark the patch behind them is. Both are a
    -- step up from what they were (size 1, shade 0.42) unless set back.
    local SIZES = { normal = 1, large = 1.2, huge = 1.4 }
    local SHADES = { soft = 0.42, medium = 0.62, strong = 0.80 }
    local function sizeMul() return SIZES[NP.db and NP.db.numbersSize or "large"] or 1.2 end
    local function shade() return SHADES[NP.db and NP.db.numbersShade or "medium"] or 0.62 end
    -- A critical is celebrated (0.1.523), two ways:
    --   * it lands white-hot and cools to its own colour in a third of a
    --     second;
    --   * a scatter of sparks is shaken out of it, as from the Quick Buff
    --     pill when it is cast: tiny, white and a pale tint of the number's
    --     colour, thrown out and falling, each mostly dim and catching the
    --     light in short glints (a few with a thin cross of light).
    -- The sparks are textures of the number's own frame, so a hit for
    -- nothing hides them with the rest.
    local SPARKS, GLINTS, SPARK_FALL = 8, 3, 80 -- (fewer than the first 16: asked for)
    local rnd = math.random
    local SPOT = "Interface/AddOns/Meniscus/Media/spot.tga"
    local function sparksOff(f)
        f.sparkOn = nil
        if not f.sparks then return end
        for n = 1, #f.sparks do
            local q = f.sparks[n]
            q.tx:SetAlpha(0)
            if q.h then q.h:SetAlpha(0); q.v:SetAlpha(0) end
        end
    end
    local function sparksGo(f, r, g, b)
        if not f.sparks then
            f.sparks = {}
            for n = 1, SPARKS do
                local q = { tx = f.body:CreateTexture(nil, "OVERLAY", nil, 2) }
                q.tx:SetTexture(SPOT)
                q.tx:SetBlendMode("ADD")
                if n <= GLINTS then
                    q.h = f.body:CreateTexture(nil, "OVERLAY", nil, 2)
                    q.v = f.body:CreateTexture(nil, "OVERLAY", nil, 2)
                    q.h:SetTexture(SPOT); q.v:SetTexture(SPOT)
                    q.h:SetBlendMode("ADD"); q.v:SetBlendMode("ADD")
                    q.h:SetPoint("CENTER", q.tx, "CENTER"); q.v:SetPoint("CENTER", q.tx, "CENTER")
                end
                f.sparks[n] = q
            end
        end
        for n = 1, SPARKS do
            local q = f.sparks[n]
            q.x, q.y = (rnd() - 0.5) * SIZE * 2.6, (rnd() - 0.5) * SIZE * 0.7
            q.vx, q.vy = (rnd() - 0.5) * 120, -6 + rnd() * 62 -- thrown out, most a little upward
            q.life = 0.55 + rnd() * 0.75
            q.size = q.h and (3 + rnd() * 2) or (1.6 + rnd() * 2.6)
            q.wink, q.at = 7 + rnd() * 10, rnd() * 6
            q.arm = 8 + rnd() * 9
            -- White, or a pale tint of the number's colour.
            local k = rnd() > 0.5 and 0.55 or 1
            local cr, cg, cb = r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
            q.tx:SetVertexColor(cr, cg, cb)
            q.tx:SetSize(q.size, q.size)
            q.tx:SetAlpha(0)
            if q.h then
                q.h:SetVertexColor(cr, cg, cb); q.v:SetVertexColor(cr, cg, cb)
                q.h:SetAlpha(0); q.v:SetAlpha(0)
            end
            q.done = false
        end
        f.sparkOn = true
    end
    local function sparksStep(f, sc)
        local t = f.age
        -- (The number is over its size as it lands; the sparks are kept to
        -- the size it settles at.)
        local inv = f.scale / sc
        local slow = (1 - math.exp(-2.2 * t)) / 2.2
        local any = false
        for n = 1, SPARKS do
            local q = f.sparks[n]
            if not q.done then
                local e = t / q.life
                if e >= 1 then
                    q.done = true
                    q.tx:SetAlpha(0)
                    if q.h then q.h:SetAlpha(0); q.v:SetAlpha(0) end
                else
                    any = true
                    q.tx:SetPoint("CENTER", f.body, "CENTER", (q.x + q.vx * slow) * inv,
                                  (q.y + q.vy * t - 0.5 * SPARK_FALL * t * t) * inv)
                    local s = 0.5 + 0.5 * math.sin(t * q.wink + q.at)
                    local flash = s ^ 8
                    local fade = 1 - e * e
                    q.tx:SetAlpha(fade * (0.30 + 0.70 * flash))
                    if q.h then
                        local arm = q.arm * (0.4 + 0.6 * flash)
                        q.h:SetSize(arm, 1.8); q.v:SetSize(1.8, arm)
                        q.h:SetAlpha(fade * flash); q.v:SetAlpha(fade * flash)
                    end
                end
            end
        end
        if not any then f.sparkOn = nil end
    end
    local function item()
        for i = 1, #items do if not items[i].live then return items[i] end end
        if #items >= NUM_POOL then return nil end
        local f = CreateFrame("Frame", nil, host)
        f:SetSize(10, 10)
        -- A hit for nothing hides itself, by a window that is only open
        -- when the amount is 1 or more. The amount is a hidden value in a
        -- fight: it can't be compared, and the game refused to run it
        -- through a curve. A bar will take it, though: this one runs from 0
        -- to 1, so an amount of 0 leaves its fill with no width and
        -- anything more fills it. The number, its patch, its emblem and its
        -- flash are all drawn inside a clipping frame laid over that fill:
        -- no fill, nothing seen. (This is how the "0" beside every Heroic
        -- Strike goes: the game reports that as two hits, the strike and an
        -- empty swing.)
        f.bar = CreateFrame("StatusBar", nil, f)
        f.bar:SetSize(300, 170)
        f.bar:SetPoint("CENTER")
        f.bar:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
        f.bar:SetStatusBarColor(0, 0, 0, 0)
        f.bar:SetMinMaxValues(0, 1)
        f.bar:SetValue(1)
        f.gate = CreateFrame("Frame", nil, f)
        f.gate:SetClipsChildren(true)
        f.gate:SetAllPoints(f.bar)
        f.clip = CreateFrame("Frame", nil, f.gate)
        f.clip:SetClipsChildren(true)
        local fill = f.bar:GetStatusBarTexture()
        local okClip = fill and pcall(function()
            f.clip:SetPoint("TOPLEFT", fill, "TOPLEFT")
            f.clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
        end)
        if not okClip then f.clip:ClearAllPoints(); f.clip:SetAllPoints(f.bar); f.bar = nil end
        if MinimalUIDB then MinimalUIDB.zeroclip = okClip and "window laid over the bar's fill" or "could not lay the window over the fill" end
        -- (What is clipped has to be a child frame of the clip, not a
        -- texture on the clip itself.)
        local outer = f
        f = CreateFrame("Frame", nil, outer.clip)
        f:SetSize(10, 10)
        f:SetPoint("CENTER", outer, "CENTER")
        outer.body = f
        -- A critical sits on a pill: dark, with a hairline ring in the
        -- number's own colour. Only criticals, so the shape turns up a few
        -- times a fight and not on every hit. It is a frame of its own under
        -- the number's (a child frame would draw over the text), hung on the
        -- text's two ends: the text is a hidden value in a fight and can't
        -- be measured, but it can be anchored to.
        local pf = CreateFrame("Frame", nil, outer.clip)
        pf:SetFrameLevel(f:GetFrameLevel())
        f:SetFrameLevel(pf:GetFrameLevel() + 1)
        pf:SetHeight(SIZE + 12)
        pf.ring = ns.RoundedRect(pf, -7, -1, (SIZE + 12) / 2 + 1, 1, 1, 1, 0.6)
        ns.RoundedRect(pf, -6, 0, (SIZE + 12) / 2, 0.05, 0.05, 0.06, 0.88)
        pf:Hide()
        outer.pill = pf
        f.back = f:CreateTexture(nil, "BACKGROUND")
        f.back:SetTexture("Interface/AddOns/Meniscus/Media/spot.tga")
        f.back:SetVertexColor(0, 0, 0, shade())
        f.back:SetSize(SIZE * 3.8, SIZE * 2.1)
        f.back:SetPoint("CENTER")
        local function line(layer, sub)
            local t = f:CreateFontString(nil, layer, nil)
            ns:SetFont(t, SIZE, "OUTLINE", true)
            t:SetPoint("CENTER")
            return t
        end
        f.warm, f.cool = line("ARTWORK"), line("ARTWORK")
        f.warm:SetTextColor(1.00, 0.45, 0.40)
        f.cool:SetTextColor(0.45, 0.62, 1.00)
        f.fs = line("OVERLAY")
        f.fs:SetShadowOffset(1, -1)
        f.fs:SetShadowColor(0, 0, 0, 0.9)
        f.burst = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.burst:SetTexture("Interface/AddOns/Meniscus/Media/spot.tga")
        f.burst:SetBlendMode("ADD")
        f.burst:SetPoint("CENTER")
        f.burst:SetAlpha(0)
        f.kind = f:CreateTexture(nil, "OVERLAY")
        f.kind:SetSize(SIZE * 0.78, SIZE * 0.78)
        f.kind:SetPoint("RIGHT", f.fs, "LEFT", -2, 0)
        f.kind:Hide()
        outer.back, outer.warm, outer.cool, outer.fs, outer.burst, outer.kind = f.back, f.warm, f.cool, f.fs, f.burst, f.kind
        -- (fs / warm / cool are whichever three strings the number in hand
        -- is drawn with: these, or a log line's own: see lineSet. pt, px:
        -- the point the two tinted copies are moved about, and its offset.)
        outer.numFs, outer.numWarm, outer.numCool, outer.pt, outer.px = f.fs, f.warm, f.cool, "CENTER", 0
        f = outer
        items[#items + 1] = f
        return f
    end
    driver:SetScript("OnUpdate", function(self, dt)
        local any = false
        for i = 1, #items do
            local f = items[i]
            if f.live then
                f.age = f.age + dt
                if f.fillLater then f.fillLater = nil; labFill(f.bar, "a frame on") end
                local k = f.age / (f.life or NUM_LIFE)
                if k >= 1 then
                    f.live = false
                    f:Hide()
                else
                    any = true
                    -- Up quickly, then easing off; clear until the last third.
                    -- (A critical first hangs where it landed for a third of
                    -- a second, at full size, and only then starts to rise.)
                    local kr = k
                    if f.crit then
                        local life = f.life or NUM_LIFE
                        kr = f.age < 0.34 and 0 or (f.age - 0.34) / (life - 0.34)
                    end
                    local e = 1 - (1 - kr) * (1 - kr)
                    -- Opening: small (a critical: large) to its own size.
                    -- (Positions are in the frame's own units, so the scale
                    -- is divided out.)
                    local sc = f.scale
                    if f.crit then
                        -- Lands at well over its size and snaps down to it.
                        if f.age < 0.20 then sc = f.scale * (1.7 - 0.7 * (f.age / 0.20) ^ 0.6) end
                    elseif f.age < 0.14 then
                        -- An ordinary hit lands a third over its size and
                        -- settles (it used to open small and grow, which
                        -- the eye passed over); a small one, a little.
                        sc = f.scale * (1 + (f.small and 0.15 or 0.35) * (1 - (f.age / 0.14) ^ 0.6))
                    end
                    f:SetScale(sc)
                    if not pcall(f.SetPoint, f, "CENTER", f.rel or UIParent, f.rel and "TOP" or "BOTTOMLEFT",
                                 (f.x + f.drift * e) / sc, (f.y + NUM_RISE * e) / sc) then
                        f.live = false
                        f:Hide()
                    end
                    f:SetAlpha(k < 0.66 and 1 or (1 - k) / 0.34)
                    if f.crit then
                        -- White-hot as it lands, cooling to its own colour.
                        -- (Longer and whiter than first made: fully white
                        -- for the first moment, half a second to cool.)
                        if f.age < 0.50 then
                            local h = 1 - f.age / 0.50
                            local mix = h < 0.84 and (h / 0.84) ^ 1.5 or 1
                            local r, g, b = f.cr + (1 - f.cr) * mix, f.cg + (1 - f.cg) * mix, f.cb + (1 - f.cb) * mix
                            if f.zeroSeen == nil or not pcall(f.fs.SetTextColor, f.fs, r, g, b, f.zeroSeen) then f.fs:SetTextColor(r, g, b, 1) end
                            f.hot = true
                        elseif f.hot then
                            f.hot = nil
                            if f.zeroSeen == nil or not pcall(f.fs.SetTextColor, f.fs, f.cr, f.cg, f.cb, f.zeroSeen) then f.fs:SetTextColor(f.cr, f.cg, f.cb, 1) end
                        end
                        if f.sparkOn then sparksStep(f, sc) end
                        -- The fringe: wide apart as it lands, closing in under a
                        -- second to a narrow one that it keeps for the rest of
                        -- its life (it used to close fully and leave a plain
                        -- number). At rest the split breathes a little, its
                        -- lean turns slowly, and the two tints wander (red
                        -- through amber and rose, blue through cyan and
                        -- violet), as light does through a turning glass. It
                        -- fades with the number.
                        local q = f.age < 0.9 and (1 - f.age / 0.9) or 0
                        local a = f.age
                        local pull = 5.5 * (0.36 + 0.64 * q) * (1 + 0.16 * (1 - q) * math.sin(a * 4.6))
                        local lean = 0.18 + 0.42 * (1 - q) * math.sin(a * 1.9)
                        local dx, dy = pull * math.cos(lean), pull * math.sin(lean)
                        f.warm:SetPoint(f.pt, f.px - dx, dy)
                        f.cool:SetPoint(f.pt, f.px + dx, -dy)
                        local w = (1 - q) * math.sin(a * 2.7)
                        f.warm:SetTextColor(1.00, 0.45 + 0.22 * w, 0.40 - 0.18 * w)
                        f.cool:SetTextColor(0.45 - 0.16 * w, 0.62 + 0.20 * w, 1.00)
                        local fa = 0.60 + 0.30 * q
                        f.warm:SetAlpha(fa); f.cool:SetAlpha(fa)
                        -- A burst of light behind it as it lands, gone in under half a second.
                        -- (Brighter than it was: full strength at the landing,
                        -- and paler, nearer white, than the number's colour.)
                        local bq = f.age < 0.60 and (1 - f.age / 0.60) or 0
                        f.burst:SetAlpha(bq ^ 1.5)
                        local bs = SIZE * (4.2 + 2.6 * (1 - bq))
                        f.burst:SetSize(bs * 1.5, bs)
                    end
                    if f.irid then
                        -- A heal on you (0.1.608): mother-of-pearl. The number
                        -- wanders between green, aqua and a pale yellow, and
                        -- two faint copies of it, one yellow, one blue, turn
                        -- slowly about it a pixel or two off, so the edges
                        -- shimmer as oil on water does.
                        -- (0.1.623, asked for more flash and colour: the three
                        -- colours at full strength and turning faster, a white
                        -- landing with a burst of light behind it, a glint of
                        -- white passing over it now and then, and the two
                        -- copies wide apart at first and bolder throughout.)
                        local a = f.age + f.phase
                        local v = math.sin(a * 1.7 + 1.3)
                        local p = (a * 2.0) % 3
                        local t = p % 1
                        t = t * t * (3 - 2 * t)
                        local r, g, b
                        if p < 1 then r, g, b = 0.25 - 0.15 * t, 1.00 - 0.12 * t, 0.45 + 0.55 * t      -- green to aqua
                        elseif p < 2 then r, g, b = 0.10 + 0.90 * t, 0.88 + 0.06 * t, 1.00 - 0.75 * t  -- aqua to yellow
                        else r, g, b = 1.00 - 0.75 * t, 0.94 + 0.06 * t, 0.25 + 0.20 * t end           -- yellow to green
                        if not (f.crit and f.age < 0.50) then
                            local land = f.age < 0.30 and (1 - f.age / 0.30) ^ 0.7 or 0
                            local glint = math.sin(a * 5.2)
                            glint = glint > 0 and glint ^ 6 * 0.55 or 0
                            local mix = land > glint and land or glint
                            r, g, b = r + (1 - r) * mix, g + (1 - g) * mix, b + (1 - b) * mix
                            if f.zeroSeen == nil or not pcall(f.fs.SetTextColor, f.fs, r, g, b, f.zeroSeen) then f.fs:SetTextColor(r, g, b, 1) end
                        end
                        if not f.crit then
                            local q = f.age < 0.60 and (1 - f.age / 0.60) or 0
                            local pull = 2.2 + 3.4 * q + 0.6 * v
                            local lean = a * 1.8
                            local dx, dy = pull * math.cos(lean), pull * math.sin(lean)
                            f.warm:SetPoint(f.pt, f.px - dx, dy)
                            f.cool:SetPoint(f.pt, f.px + dx, -dy)
                            f.warm:SetAlpha(0.78); f.cool:SetAlpha(0.78)
                            local bq = f.age < 0.50 and (1 - f.age / 0.50) or 0
                            f.burst:SetAlpha(bq ^ 1.5 * 0.9)
                            local bs = SIZE * (3.4 + 2.4 * (1 - bq))
                            f.burst:SetSize(bs * 1.5, bs)
                        end
                        f.warm:SetTextColor(1.00, 0.88 + 0.10 * v, 0.12)
                        f.cool:SetTextColor(0.22 + 0.25 * v, 0.42 - 0.14 * v, 1.00)
                    end
                end
            end
        end
        if not any then self:Hide() end
    end)
    -- ── A number from a log line's own text ───────────────────────────────
    -- The game's Combat Log hands each of its lines over as a ticket: put
    -- on the screen it reads "Your Melee hit Wretched Zombie 52 Physical.
    -- (16 Overkill)", but an addon can't read it. With our own filter in the
    -- log, though, every line is a thing of yours, and its amount is in it.
    -- So a line can be drawn as its number: in a typeface where only the
    -- numerals draw and every other character is blank and takes no room
    -- (Media/digits-*.ttf, made by dist/digitfont.py), the whole line shows
    -- as "52". An opening bracket is blank but very wide in that typeface,
    -- so what a line adds after the amount ("(16 Overkill)") lands far to
    -- the right, outside the small window the number is shown through.
    -- Nothing is read: the game draws its own line, in a typeface of ours.
    --
    -- What it is for: hits whose amount the game gives no other way.
    --   * The blow that kills. A swing's hit is only reported when the swing
    --     is seen to land, a quarter of a second or more after the blow; by
    --     then a dead enemy has no nameplate and is no longer your target,
    --     and most killing swings were never reported at all.
    --   * A swing in a group, or with a stranger on your enemy: whichever
    --     hit is taken for its report, the amount shown is the line's own.
    --   * Any other line of yours that no hit is reported for (an enemy with
    --     no nameplate that is not your target).
    -- Such a number starts at a fixed spot, a little left of the middle: how
    -- wide it is can't be measured, so it can't be centred.
    --
    -- Used only once the typeface has measured as it should, here in the
    -- game, on plain text (MinimalUIDB.digitface says how that went).
    --
    -- First measured in the game, 0.1.648: the blank characters do take
    -- next to no room (a whole line came out 3 pixels wider than its
    -- number), but the wide blank bracket came out a pixel or two wide, not
    -- 240: the game does not go by the width of a glyph with nothing drawn
    -- in it. So the file comes in several makes (dist/digitfont.py: a
    -- bracket with a speck of ink at its far end, one with the speck at its
    -- near end, a blank one of moderate width, and the first), each is
    -- measured, and the first that behaves is the one used.
    local LINE_W, LINE_PAD, LINE_DX = 88, 8, 23 -- the window's width; the number's start inside it; the window's start, left of the middle
    local DIGIT_MAKES = { "-r", "-q", "-p", "" }
    local DIGIT_A, DIGIT_B, DIGIT_C = "52", "Your Fireball hit Monster 52 Fire.", "Your Fireball hit Monster 52 Fire. (16 Overkill)"
    local digitPath, digitFlags, textOK = nil, "OUTLINE", false
    local loadedAt, lastFight = GetTime(), -99
    do
        -- (The log prints its old lines again as you come into the world:
        -- none of those is drawn. And a line with no hit to go by is only
        -- drawn in a fight, or just after one.)
        local wf = CreateFrame("Frame")
        wf:RegisterEvent("PLAYER_ENTERING_WORLD")
        wf:RegisterEvent("PLAYER_REGEN_ENABLED")
        wf:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then lastFight = GetTime() else loadedAt = GetTime() end
        end)
    end
    local function fighting(now)
        return InCombatLockdown() or now - lastFight < 3
    end
    -- Should no make of the typeface measure right, there is another way to
    -- leave only the amount showing, which can't be measured, only looked
    -- at: the log can be told to write the amount in a colour of its own,
    -- and a string whose own colour is fully clear may still draw the parts
    -- that carry a colour (or may not: the game's notes and addons disagree).
    -- A small card, once a session and only in that case, puts the question
    -- on the screen for the player to answer.
    local function colourTest()
        if host.colourCard then return end
        local card = CreateFrame("Frame", nil, UIParent)
        host.colourCard = card
        card:SetSize(360, 124)
        card:SetPoint("TOP", UIParent, "TOP", 0, -170)
        card:SetFrameStrata("DIALOG")
        ns.RoundedRect(card, -7, -1, 13, T.border[1], T.border[2], T.border[3], 1)
        ns.RoundedRect(card, -6, 0, 12, 0.06, 0.06, 0.07, 0.97)
        local function text(size, bold, y, str, r, g, b, a)
            local t = card:CreateFontString(nil, "OVERLAY")
            ns:SetFont(t, size, "", bold)
            t:SetPoint("TOPLEFT", 18, y)
            t:SetTextColor(r or T.text[1], g or T.text[2], b or T.text[3], a or 1)
            t:SetText(str)
            return t
        end
        text(12, true, -14, "Meniscus: a test for the combat numbers")
        text(11, false, -34, "Which numbers can you read on each line?", T.textDim[1], T.textDim[2], T.textDim[3])
        text(12, false, -58, "Line A:", T.textDim[1], T.textDim[2], T.textDim[3])
        text(12, false, -84, "Line B:", T.textDim[1], T.textDim[2], T.textDim[3])
        -- A: the string's own colour fully clear, the first number in a colour of its own.
        local a = card:CreateFontString(nil, "OVERLAY")
        ns:SetFont(a, 16, "OUTLINE", true)
        a:SetPoint("TOPLEFT", 80, -55)
        a:SetTextColor(1, 1, 1, 0)
        a:SetText("|cffffd24052|r   16")
        -- B: the same, in an ordinary colour, to compare.
        local bfs = card:CreateFontString(nil, "OVERLAY")
        ns:SetFont(bfs, 16, "OUTLINE", true)
        bfs:SetPoint("TOPLEFT", 80, -81)
        bfs:SetTextColor(1, 1, 1, 1)
        bfs:SetText("|cffffd24052|r   16")
        ns:Print("Combat numbers test: a small card is at the top of the screen for a minute. Please report what Line A reads: \"52\", \"52 16\", or nothing.")
        C_Timer.After(60, function() card:Hide() end)
    end
    local function digitCheck(tries)
        if textOK then return end
        local base = tostring(T.fontBold or T.font or ""):lower()
        local family = base:find("manrope", 1, true) and "manrope" or "inter"
        local probe, wrapProbe = host.digitProbe, host.digitWrap
        if not probe then
            probe = host:CreateFontString(nil, "BACKGROUND")
            probe:SetAlpha(0)
            probe:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -200)
            host.digitProbe = probe
            wrapProbe = host:CreateFontString(nil, "BACKGROUND")
            wrapProbe:SetAlpha(0)
            wrapProbe:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -300)
            host.digitWrap = wrapProbe
        end
        local function wide(path, text, flags)
            local ok = pcall(function()
                probe:SetFont(path, SIZE, flags)
                probe:SetWordWrap(false)
                probe:SetText(text)
            end)
            if not ok then return nil end
            local okW, w = pcall(probe.GetUnboundedStringWidth or probe.GetStringWidth, probe)
            if not okW or type(w) ~= "number" or secret(w) then return nil end
            return w
        end
        -- (How many lines the line with a bracket takes in a string 70
        -- wide: noted only, for a way of doing this by wrapping should no
        -- make of the bracket be wide enough.)
        local function wrapped(path)
            local n
            pcall(function()
                wrapProbe:SetFont(path, SIZE, "")
                wrapProbe:SetWidth(70)
                wrapProbe:SetWordWrap(true)
                wrapProbe:SetText(DIGIT_C)
                n = wrapProbe.GetNumLines and wrapProbe:GetNumLines() or nil
            end)
            return (type(n) == "number" and not secret(n)) and n or nil
        end
        local function f(v) return v and string.format("%.1f", v) or "?" end
        -- A line's number must start where the line does, give or take a
        -- few pixels (the blank characters before it); and what follows a
        -- bracket must start beyond the window's far edge.
        local need = LINE_W - LINE_PAD + 4
        local said, chosen = {}, nil
        for _, make in ipairs(DIGIT_MAKES) do
            local file = "digits-" .. family .. make .. ".ttf"
            local path = MEDIA .. file
            for _, flags in ipairs({ "OUTLINE", "" }) do
                local a, b, c = wide(path, DIGIT_A, flags), wide(path, DIGIT_B, flags), wide(path, DIGIT_C, flags)
                local p1, p2 = wide(path, "(", flags), wide(path, "((", flags)
                local good = a and b and c and a > 4 and b - a > -1 and b - a < 6 and c - b >= need
                said[#said + 1] = string.format("%s %s: %s / %s / %s, one bracket %s, two %s%s", make == "" and "first" or make,
                    flags == "" and "plain" or "outlined", f(a), f(b), f(c), f(p1), f(p2), good and " GOOD" or "")
                if good and not textOK then
                    digitPath, digitFlags, textOK, chosen = path, flags, true, file .. (flags == "" and " plain" or " outlined")
                end
            end
            said[#said] = said[#said] .. ", wraps to " .. tostring(wrapped(path) or "?") .. " lines"
        end
        pcall(probe.SetText, probe, "")
        pcall(wrapProbe.SetText, wrapProbe, "")
        if MinimalUIDB then
            MinimalUIDB.digitface = date("%H:%M:%S") .. " " .. family .. ", widths of \"52\" / a whole line / a line with a bracket (which must be "
                .. need .. " more than the whole line): " .. table.concat(said, " | ")
                .. (textOK and (". In use: " .. chosen .. ".") or (tries > 0 and ". None good yet: trying again." or ". None good: not in use."))
        end
        if not textOK and tries > 0 then C_Timer.After(3, function() pcall(digitCheck, tries - 1) end) end
        if not textOK and tries <= 0 then pcall(colourTest) end
    end
    -- The strings a line is drawn with, behind their window. (What is
    -- clipped has to sit on a child frame of the clip.)
    local function lineStrings(parent, three)
        local win = CreateFrame("Frame", nil, parent)
        win:SetClipsChildren(true)
        win:SetSize(LINE_W, SIZE * 2.4)
        win:SetPoint("LEFT", parent, "CENTER", -LINE_DX, 0)
        local hold = CreateFrame("Frame", nil, win)
        hold:SetAllPoints()
        local function one(layer)
            local t = hold:CreateFontString(nil, layer)
            if not pcall(t.SetFont, t, digitPath, SIZE, digitFlags) or not t:GetFont() then return nil end
            t:SetPoint("LEFT", LINE_PAD, 0)
            t:SetWordWrap(false)
            return t
        end
        local warm, cool
        if three then warm, cool = one("ARTWORK"), one("ARTWORK") end
        local fs = one("OVERLAY")
        if not fs or (three and not (warm and cool)) then
            win:Hide()
            return nil
        end
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
        return win, fs, warm, cool
    end
    -- An item's own set, made the first time it draws a line.
    local function lineSet(f)
        if f.lineFs == nil then
            f.lineFs = false
            if digitPath and f.body then
                local ok, win, fs, warm, cool = pcall(lineStrings, f.body, true)
                if ok and win then
                    warm:SetTextColor(1.00, 0.45, 0.40)
                    cool:SetTextColor(0.45, 0.62, 1.00)
                    f.lineWin, f.lineFs, f.lineWarm, f.lineCool = win, fs, warm, cool
                end
            end
        end
        return f.lineFs or nil
    end
    -- A line's number standing BEHIND an ordinary number, seen only if that
    -- number's amount is nothing at all. (The blow that kills has been
    -- drawn, by the record, and yet not seen: if the game reports it as a
    -- hit for 0, the window that hides a 0 hides it. This is the same
    -- window turned about: a bar from -1 to 1, twice the usual width, so
    -- its fill is never empty; an amount of 0 leaves the right-hand half
    -- unfilled, and that half is what this copy shows through. Anything
    -- more fills the bar, and there is nothing to show through.)
    local function zeroSet(f)
        if f.zfs == nil then
            f.zfs = false
            if digitPath then
                pcall(function()
                    local zb = CreateFrame("StatusBar", nil, f)
                    zb:SetSize(600, 170)
                    zb:SetPoint("RIGHT", f, "CENTER", 150, 0)
                    zb:SetStatusBarTexture("Interface/Buttons/WHITE8x8")
                    zb:SetStatusBarColor(0, 0, 0, 0)
                    zb:SetMinMaxValues(-1, 1)
                    zb:SetValue(1)
                    local z = CreateFrame("Frame", nil, f)
                    z:SetClipsChildren(true)
                    z:SetPoint("TOPLEFT", zb:GetStatusBarTexture(), "TOPRIGHT")
                    z:SetPoint("BOTTOMRIGHT", zb, "BOTTOMRIGHT")
                    local box = CreateFrame("Frame", nil, z)
                    box:SetSize(10, 10)
                    box:SetPoint("CENTER", f, "CENTER")
                    local back = box:CreateTexture(nil, "BACKGROUND")
                    back:SetTexture(SPOT)
                    back:SetSize(SIZE * 3.8, SIZE * 2.1)
                    back:SetPoint("CENTER")
                    local win, fs = lineStrings(box, false)
                    if win then
                        box:Hide()
                        f.zbar, f.zbox, f.zfs, f.zback = zb, box, fs, back
                    end
                end)
            end
        end
        return f.zfs or nil
    end
    -- rel: the frame the number rises from (a nameplate), or nil for a
    -- place on the screen. A nameplate may not be measured by an addon
    -- ("restricted region"), only anchored to: so the number is hung on it.
    local showUnit -- (the unit the hit being shown is on; set by the event below)
    local WIDE_ORDER = { 0, 2, -2, 1, -1, 3, -3 }
    local zeroCurve, zeroBack, zeroBackFor
    -- line: value is a log line's ticket, to be drawn as its number.
    local function show(rel, x, y, value, r, g, b, crit, small, kind, grim, line)
        local f = item()
        if not f then return end
        if line and not lineSet(f) then return end
        -- (Whichever three strings this number is not drawn with are emptied.)
        if f.lineOn then
            f.lineFs:SetText(""); f.lineWarm:SetText(""); f.lineCool:SetText("")
            f.lineWin:Hide()
        end
        if f.zbox then f.zbox:Hide() end
        if line then
            f.numFs:SetText(""); f.numWarm:SetText(""); f.numCool:SetText("")
            f.fs, f.warm, f.cool, f.pt, f.px = f.lineFs, f.lineWarm, f.lineCool, "LEFT", LINE_PAD
            f.lineWin:Show()
        else
            f.fs, f.warm, f.cool, f.pt, f.px = f.numFs, f.numWarm, f.numCool, "CENTER", 0
        end
        f.lineOn = line and true or nil
        f.kind:ClearAllPoints()
        f.kind:SetPoint("RIGHT", f.fs, "LEFT", -2, 0)
        if f.gauges then for i = 1, #f.gauges do f.gauges[i].win:Hide() end end
        if f.gated then
            f.gated = nil
            f.gate:ClearAllPoints()
            f.gate:SetAllPoints(f.bar)
        end
        f.unit = showUnit
        f.irid = nil
        f.onTarget = false
        if showUnit and showUnit ~= "player" then
            local okT, isT = pcall(UnitIsUnit, showUnit, "target")
            f.onTarget = okT and not secret(isT) and isT == true
        end
        if kind then
            f.kind:SetTexture("Interface/AddOns/Meniscus/Media/" .. kind)
            f.kind:SetVertexColor(r, g, b, 1)
            f.kind:Show()
        else
            f.kind:Hide()
        end
        -- A hit for nothing hides itself. In a fight the amounts are hidden
        -- values: they can be shown but not looked at, so "is it zero?"
        -- can't be asked here. The game can be asked to run the amount
        -- through a curve, though (0 gives 0, 1 or more gives 1), and what
        -- comes back, hidden too, is used as the opacity of the number's
        -- colour, its dark patch and its emblem. (Colour opacity is the one
        -- place a hidden opacity is known to be drawn: the pet's mood word
        -- works that way.) This is how the "0" beside every Heroic Strike
        -- goes: the game reports that as two hits at once, the strike and
        -- an empty swing.
        local seen = nil -- the opacity to draw with, when it could be had
        local SH = shade()
        local hidden = (not line) and secret(value) or false
        if hidden then
            if zeroCurve == nil then
                zeroCurve = false
                if C_CurveUtil and C_CurveUtil.CreateCurve then
                    local okC, c = pcall(C_CurveUtil.CreateCurve)
                    if okC and c and pcall(function() c:AddPoint(0, 0); c:AddPoint(0.5, 0); c:AddPoint(1, 1) end) then zeroCurve = c end
                end
            end
            -- (The patch's curve ends at the shade chosen: made again when
            -- that setting changes.)
            if zeroBackFor ~= SH then
                zeroBackFor, zeroBack = SH, false
                if C_CurveUtil and C_CurveUtil.CreateCurve then
                    local okB, cb = pcall(C_CurveUtil.CreateCurve)
                    if okB and cb and pcall(function() cb:AddPoint(0, 0); cb:AddPoint(0.5, 0); cb:AddPoint(1, SH) end) then zeroBack = cb end
                end
            end
            local how = "no curve"
            if zeroCurve then
                local okE, a = pcall(zeroCurve.Evaluate, zeroCurve, value)
                if okE and a ~= nil then
                    seen = a
                    how = "curve gave an opacity"
                    local okB, ab = false, nil
                    if zeroBack then okB, ab = pcall(zeroBack.Evaluate, zeroBack, value) end
                    if not (okB and ab ~= nil and pcall(f.back.SetVertexColor, f.back, 0, 0, 0, ab)) then f.back:SetVertexColor(0, 0, 0, SH) end
                    if kind and not pcall(f.kind.SetVertexColor, f.kind, r, g, b, a) then f.kind:SetVertexColor(r, g, b, 1) end
                else
                    how = "the curve would not take a hidden amount: " .. tostring(a):sub(1, 80)
                    f.back:SetVertexColor(0, 0, 0, SH)
                end
            end
            if MinimalUIDB and MinimalUIDB.zerodiag ~= how then MinimalUIDB.zerodiag = how end
        else
            f.back:SetVertexColor(0, 0, 0, SH)
        end
        f.zeroSeen = seen
        if f.bar and not pcall(f.bar.SetValue, f.bar, hidden and value or 1) then
            f.bar:SetValue(1)
            if MinimalUIDB then MinimalUIDB.zeroclip = "the bar would not take the amount" end
        end
        f.fillLater = nil
        if f.bar and hidden and labOn() then labFill(f.bar, "at once"); f.fillLater = true end
        -- (A hidden amount goes straight in; nothing is done with it here.)
        local ok = pcall(f.fs.SetText, f.fs, value)
        if MinimalUIDB and not MinimalUIDB.ctdiag then
            MinimalUIDB.ctdiag = "first number: hidden=" .. tostring(secret(value)) .. " type=" .. type(value) .. " shown=" .. tostring(ok)
        end
        if not ok then return end
        if crit then
            pcall(f.warm.SetText, f.warm, value)
            pcall(f.cool.SetText, f.cool, value)
        else
            f.warm:SetText(""); f.cool:SetText("")
        end
        f.warm:SetAlpha(0); f.cool:SetAlpha(0)
        -- (Off unless switched on: tried as the default and not liked.)
        local pillOn = crit and not line and NP.db and NP.db.numbersCritPill == true or false
        f.pill:SetShown(pillOn)
        if pillOn then
            f.pill:ClearAllPoints()
            f.pill:SetPoint("LEFT", kind and f.kind or f.fs, "LEFT", -13, 0)
            f.pill:SetPoint("RIGHT", f.fs, "RIGHT", 13, 0)
            f.pill.ring(r, g, b, 0.60)
        end
        f.back:SetShown(not small and not pillOn)
        spawned = spawned + 1
        f.serial = spawned
        -- (A critical: 1.55 times a hit's size. 2.3 was tried for one version, 0.1.682, and was "a bit too much".)
        local scale = (crit and 1.55 or (small and 0.85 or 1)) * sizeMul()
        f.small = small and true or false
        f.burst:SetVertexColor(r + (1 - r) * 0.70, g + (1 - g) * 0.70, b + (1 - b) * 0.70, 1)
        f.burst:SetAlpha(0)
        f.crit, f.scale = crit, scale
        f.cr, f.cg, f.cb, f.hot = r, g, b, nil
        -- (grim: a critical you took. Nothing to celebrate.)
        if crit and not grim and not (NP.db and NP.db.numbersCritSparks == false) then sparksGo(f, r, g, b) else sparksOff(f) end
        -- A critical stays up most of a second longer than an ordinary
        -- hit, and its colour fringe takes longer to close.
        f.life = crit and (NUM_LIFE + 0.9) or NUM_LIFE
        f:SetScale(scale)
        f.rel = rel
        -- Lanes side by side, so a burst doesn't stack; each drifts a little
        -- further out the way it already leans. Over a nameplate: five
        -- narrow ones. From the target frame or on the rails there is room,
        -- and every hit starts from the one spot, so: seven, well apart,
        -- taken in an order that puts each new number far from the last
        -- (middle, right, left, further right, ...) and on alternating
        -- heights, so two numbers a moment apart never share a line.
        if rel then
            local lane = (spawned % 5) - 2
            f.x = x + lane * 16
            f.drift = lane * 7
            f.y = y
        else
            local lane = WIDE_ORDER[(spawned % 7) + 1]
            f.x = x + lane * 38
            f.drift = lane * 9
            f.y = y + ((spawned % 2 == 0) and 0 or 16)
        end
        if f.zeroSeen == nil or not pcall(f.fs.SetTextColor, f.fs, r, g, b, f.zeroSeen) then f.fs:SetTextColor(r, g, b, 1) end
        f.age, f.live = 0, true
        f:SetAlpha(1)
        f:ClearAllPoints()
        local okP, errP = pcall(f.SetPoint, f, "CENTER", rel or UIParent, rel and "TOP" or "BOTTOMLEFT", f.x / scale, f.y / scale)
        if not okP then
            -- (Not allowed to hang on this plate either: give this one up.)
            f.live = false
            if MinimalUIDB then MinimalUIDB.ctdiag = "anchor refused: " .. tostring(errP) end
            return
        end
        f:Show()
        driver:Show()
        return f
    end
    -- Where a unit's numbers start: just above its nameplate.
    local function plateOf(unit)
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
        return plate
    end
    -- Whose hit was that? The client has no combat log: it says a unit took
    -- damage, never who dealt it. So, a best guess (db.numbersMine): a
    -- number over a nameplate is shown only if you did something that could
    -- have caused it:
    --   * a harmful spell or wand shot of yours has just gone off (within
    --     2.6 s; each one accounts for one hit) and the unit is your target;
    --   * or the unit carries a damage-over-time effect of yours and the
    --     hit falls on a tick (every 3 s from when you cast it);
    --   * a heal: you have just cast a helping spell.
    -- It misses melee swings (they announce nothing), and lets through
    -- someone else's hit that lands in the same instant as yours.
    local RAILKEY = {} -- stands for "your target, with no nameplate" where a nameplate would be the key
    -- The rails: three of them, their own, high on the screen (above where
    -- the loot and experience pills finish their climb). Your target's
    -- numbers rise on the middle one; other enemies you are hitting take
    -- the right and the left, each keeping its rail while the hits keep
    -- coming, so two enemies' numbers don't pile into one column.
    local RAIL_DX = { [0] = 0, 150, -150 }
    local RAIL_DY = { [0] = 0, -22, -22 }
    local RAIL_KEEP = 5 -- seconds an enemy keeps its rail after its last number
    local railOf = setmetatable({}, { __mode = "k" }) -- [key] = { rail, when }
    local sideUsed = { 0, 0 }
    -- Or, the usual place now: rising from the top of our target frame.
    -- The place is the frame's, but the numbers are not hung on it: the
    -- game drops your target the moment it dies and the frame hides, and a
    -- number hung on it went too. So where the frame is gets measured (it
    -- is ours, and can be) and remembered, and the number is put there on
    -- the screen itself.
    local frameX, frameY
    local function frameSpot()
        local UFm = ns.modules.UnitFrames
        local tf = UFm and UFm.target
        local at = tf and (tf.healthPill or tf)
        if at then
            local okC, cx = pcall(at.GetCenter, at)
            local okT, top = pcall(at.GetTop, at)
            if okC and okT and type(cx) == "number" and type(top) == "number" and not secret(cx) and not secret(top) then
                local k = at:GetEffectiveScale() / UIParent:GetEffectiveScale()
                frameX, frameY = cx * k, top * k + 36 -- (just clear of the frame; was 78 until 0.1.657: asked for closer)
            end
        end
        return frameX, frameY
    end
    local function railSpot(key, isTarget)
        if NP.db.numbersWhere ~= "rail" then
            local fx, fy = frameSpot()
            if fx then return fx, fy end
        end
        local now = GetTime()
        local idx = 0
        local had = key and railOf[key]
        if had and now - had[2] < RAIL_KEEP then
            idx = had[1]
            had[2] = now
        elseif key then
            if not isTarget then
                idx = (sideUsed[1] <= sideUsed[2]) and 1 or 2
            end
            if had then had[1], had[2] = idx, now else railOf[key] = { idx, now } end
        end
        if idx > 0 then sideUsed[idx] = now end
        return UIParent:GetWidth() / 2 + RAIL_DX[idx], UIParent:GetHeight() * 0.72 + RAIL_DY[idx]
    end
    local guess = NP.db.numbersMine ~= false
    local hits, heals, dots = {}, {}, {}   -- when each allowance runs out; plate -> when your effect went on
    local lastHelp = -99                   -- when you last cast a helping spell
    local selfHeals = {}                   -- when a heal on YOU was reported (the last few)
    local function helpful(spellID)
        local f = C_Spell and C_Spell.IsSpellHelpful
        local ok, h = pcall(f or _G.IsHelpfulSpell, spellID)
        return ok and not secret(h) and h == true
    end
    local function take(list, now)
        while list[1] and list[1] < now do table.remove(list, 1) end
        if list[1] then table.remove(list, 1) return true end
        return false
    end
    -- Melee swings announce nothing, so they are counted by rhythm: while
    -- you are auto-attacking your target, one hit (or miss, dodge, parry) on
    -- it is taken as yours each time a swing's worth of time has passed.
    -- (In a group someone else's blow can take that place; it evens out.)
    local lastSwing, why = 0, ""
    local swingSchools, swingExtra, hitSchool = {}, 0, nil
    local function swinging(now)
        local f = (C_Spell and C_Spell.IsCurrentSpell) or _G.IsCurrentSpell
        local okA, auto = pcall(f, 6603)
        if not okA or secret(auto) or not auto then
            why = "not auto-attacking: " .. (not okA and "error" or secret(auto) and "hidden" or "no")
            return false
        end
        local okS, speed = pcall(UnitAttackSpeed, "player")
        if not okS or secret(speed) or type(speed) ~= "number" or speed <= 0 then speed = 2 end
        local sch = hitSchool
        if secret(sch) or type(sch) ~= "number" then sch = 0 end
        if now - lastSwing >= speed * 0.8 then
            lastSwing = now
            wipe(swingSchools)
            swingSchools[sch] = true
            swingExtra = 0
            return true
        end
        -- One swing can land as two hits a moment apart: the blow and what
        -- rides on it (a paladin's seal struck holy first, and the weapon's
        -- own hit, half a second later, was thrown away). So for a second
        -- after a counted swing, up to two more hits of a kind not yet seen
        -- in it are taken as part of the same swing.
        if now - lastSwing <= 1.0 and swingExtra < 2 and not swingSchools[sch] then
            swingSchools[sch] = true
            swingExtra = swingExtra + 1
            why = "with the swing"
            return true
        end
        why = string.format("%.1f s after a swing", now - lastSwing)
        return false
    end
    -- Your pet's hits, by the same kind of guess (db.numbersPet): the unit
    -- is what your pet is attacking, and either the pet has just used an
    -- ability (one hit each) or a swing's worth of its time has passed.
    -- Asked only after your own rules have passed a hit up, so with both of
    -- you on one enemy a blow can now and then be given to the wrong one.
    local petHits, lastPetSwing, byPet = {}, 0, false
    local function pets(unit, now)
        if NP.db.numbersPet == false then return false end
        local okE, has = pcall(UnitExists, "pet")
        if not okE or secret(has) or not has then return false end
        local okT, on = pcall(UnitIsUnit, unit, "pettarget")
        if not okT or secret(on) or not on then return false end
        if take(petHits, now) then why = "pet cast"; return true end
        local okS, speed = pcall(UnitAttackSpeed, "pet")
        if not okS or secret(speed) or type(speed) ~= "number" or speed <= 0 then speed = 2 end
        if now - lastPetSwing >= speed * 0.8 then lastPetSwing = now; why = "pet swing"; return true end
        return false
    end
    local yoursOnly
    local function yours(unit, plate, action, now)
        byPet = false
        if yoursOnly(unit, plate, action, now) then return true end
        if action ~= "HEAL" and pets(unit, now) then byPet = true; return true end
        return false
    end
    yoursOnly = function(unit, plate, action, now)
        why = ""
        if action == "HEAL" then why = "heal"; return take(heals, now) end
        local okT, isTarget = pcall(UnitIsUnit, unit, "target")
        isTarget = okT and not secret(isTarget) and isTarget == true
        if isTarget and take(hits, now) then why = "cast"; return true end
        if isTarget and swinging(now) then if why == "" then why = "swing" end; return true end
        local list = plate and dots[plate]
        -- Your target's effects are also kept under the target itself: its
        -- nameplate goes when it leaves the screen (the camera turned away,
        -- or too far off) and comes back as a different one, and the ticks
        -- were lost with it.
        if isTarget and not (list and #list > 0) then list = dots[RAILKEY] end
        if list and #list > 0 then
            -- (Whether the unit still carries your effect was asked of the
            -- game here, and the answer could not be relied on: it is only
            -- noted now, and the timing alone decides.)
            local okA, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL|PLAYER")
            local hit = false
            for i = #list, 1, -1 do
                local age = now - list[i]
                if age > 31 then
                    table.remove(list, i)
                elseif age > 1 then
                    local ph = age % 3
                    -- (Measured: ticks arrive 2.91 to 2.99 s after the beat before.)
                    if ph < 0.3 or ph > 2.6 then hit = true; why = "tick" end
                    -- What was seen, for tuning (MinimalUIDB.dotdiag, the last 16).
                    if MinimalUIDB then
                        local d = MinimalUIDB.dotdiag
                        if type(d) ~= "table" then d = {}; MinimalUIDB.dotdiag = d end
                        d[#d + 1] = string.format("%s age %.2f beat %.2f aura %s/%s %s", action, age, ph, tostring(okA), tostring(a ~= nil), hit and "shown" or "dropped")
                        if #d > 16 then table.remove(d, 1) end
                    end
                end
            end
            if hit then return true end
        elseif MinimalUIDB and action == "WOUND" then
            MinimalUIDB.dotnote = "a hit with no cast of yours on record for that nameplate (plate " .. tostring(plate ~= nil) .. ")"
        end
        return false
    end
    if guess then
        local pcast = CreateFrame("Frame")
        pcall(pcast.RegisterUnitEvent, pcast, "UNIT_SPELLCAST_SUCCEEDED", "pet")
        pcast:SetScript("OnEvent", function(_, _, _, _, spellID)
            if secret(spellID) or type(spellID) ~= "number" or helpful(spellID) then return end
            petHits[#petHits + 1] = GetTime() + 1.6
            if #petHits > 4 then table.remove(petHits, 1) end
        end)
        local cast = CreateFrame("Frame")
        pcall(cast.RegisterUnitEvent, cast, "UNIT_SPELLCAST_SUCCEEDED", "player")
        cast:SetScript("OnEvent", function(_, _, _, _, spellID)
            if secret(spellID) or type(spellID) ~= "number" then return end
            local now = GetTime()
            if MinimalUIDB then
                local d = MinimalUIDB.ctlog
                if type(d) ~= "table" then d = {}; MinimalUIDB.ctlog = d end
                local okN, n = pcall(C_Spell.GetSpellName, spellID)
                d[#d + 1] = string.format("%.2f CAST %s", now % 1000, tostring(okN and not secret(n) and n or spellID))
                if #d > 700 then table.remove(d, 1) end
            end
            if helpful(spellID) then
                heals[#heals + 1] = now + 1.2
                lastHelp = now
                return
            end
            local ok, can = pcall(UnitCanAttack, "player", "target")
            if not ok or secret(can) or not can then return end
            hits[#hits + 1] = now + 2.6 -- (a bolt thrown from far off is in the air well over a second: 1.2 lost those)
            if #hits > 6 then table.remove(hits, 1) end
            -- When an effect of yours may have gone on (its ticks are counted
            -- from here). Not a wand or bow shot: those repeat every second
            -- or two, and each one was moving the count, so no tick ever
            -- fell on it.
            local auto = false
            local fa = C_Spell and C_Spell.IsAutoRepeatSpell
            if fa then
                local okR, r = pcall(fa, spellID)
                auto = okR and not secret(r) and r == true
            end
            if not auto then
                local okN, n = pcall(C_Spell.GetSpellName, spellID)
                auto = okN and not secret(n) and (n == "Shoot" or n == "Auto Shot")
            end
            if not auto then
                local function note(key)
                    local list = dots[key]
                    if not list then list = {}; dots[key] = list end
                    list[#list + 1] = now
                    if #list > 4 then table.remove(list, 1) end
                end
                local plate = plateOf("target")
                if plate then note(plate) end
                note(RAILKEY)
            end
        end)
        -- (A new target: what was kept under "your target" was the old one's.
        -- The old one's nameplate keeps its own list.)
        local tc = CreateFrame("Frame")
        tc:RegisterEvent("PLAYER_TARGET_CHANGED")
        tc:SetScript("OnEvent", function() dots[RAILKEY] = nil end)
        -- (And a nameplate is handed on to the next enemy that needs one,
        -- with the last one's record still on it: a mob you had only
        -- targeted, running past, showed a stranger's fire damage as a tick
        -- of yours. A nameplate starts clean each time it is given out.)
        local pa = CreateFrame("Frame")
        pcall(pa.RegisterEvent, pa, "NAME_PLATE_UNIT_ADDED")
        pa:SetScript("OnEvent", function(_, _, unit)
            if type(unit) ~= "string" or secret(unit) then return end
            local plate = plateOf(unit)
            if plate then dots[plate] = nil end
        end)
    end

    -- A nameplate going away with numbers still rising from it (the mob
    -- died a moment after the hit was shown): they move to where the target
    -- frame sits and finish there, instead of vanishing with the plate.
    -- (Shown or not: this client drops your target the moment it dies, so
    -- the frame has usually just gone too, which is why asking for it to be
    -- showing lost the killing blow every time. A hidden frame still has
    -- its place.)
    local gone = CreateFrame("Frame")
    pcall(gone.RegisterEvent, gone, "NAME_PLATE_UNIT_REMOVED")
    gone:SetScript("OnEvent", function(_, _, unit)
        if type(unit) ~= "string" or secret(unit) then return end
        local rx, ry = railSpot(plateOf(unit), false)
        local moved = 0
        for i = 1, #items do
            local f = items[i]
            if f.live and f.unit == unit and f.rel then
                -- (It keeps its lane, and goes on rising from where the
                -- rail starts.)
                f.rel, f.unit = nil, nil
                f.x, f.y = rx + (f.x or 0), ry
                moved = moved + 1
            end
        end
        if MinimalUIDB and moved > 0 then
            local d = MinimalUIDB.ctlog
            if type(d) == "table" then
                d[#d + 1] = string.format("%.2f PLATE GONE %s: %d moved to the rail", GetTime() % 1000, unit, moved)
            end
        end
    end)

    -- A number onto the screen: what kind it is decides its colour and mark.
    local function present(unit, rel, x, y, action, indicator, amount, school, mine, petShown)
        showUnit = unit
        local crit = not secret(indicator) and indicator == "CRITICAL"
        local kind = NP.db.numbersKind ~= false and not secret(school) and SCHOOL_ICON[school] or nil
        if action == "HEAL" then
            return show(rel, x, y, amount, 0.42, 0.92, 0.50, crit)
        elseif action == "WOUND" then
            if mine then
                return show(rel, x, y, amount, 0.96, 0.42, 0.38, crit, nil, kind, true)
            elseif petShown then
                -- Your pet's: its own kind, whatever the school. A paw, a
                -- sandy colour, and a size down so your own hits lead.
                return show(rel, x, y, amount, PET_TINT[1], PET_TINT[2], PET_TINT[3], crit, not crit,
                     NP.db.numbersKind ~= false and "micro_class_druid.tga" or nil)
            else
                local c = (not secret(school) and SCHOOL_TINT[school]) or SCHOOL_TINT[1]
                return show(rel, x, y, amount, c[1], c[2], c[3], crit, nil, kind)
            end
        elseif WORDS[action] then
            return show(rel, x, y, WORDS[action], 0.80, 0.80, 0.86, false, true)
        end
    end

    -- ── Whose hit: the combat log's word for it ──────────────────────────
    -- The client gives addons no combat log to read, and what its own
    -- Combat Log tab prints reaches us sealed (a ticket the screen can
    -- redeem and we can't). But it does say WHEN a line is printed: one
    -- event a line, in step with the hits (measured: the same instant, or
    -- up to a tenth of a second before, now and then a frame after). And
    -- the log's usual filter, "My actions", prints only what you and your
    -- pet do. So: a line arriving with a hit means the hit is yours. That
    -- replaces the guessing above whenever it can be used:
    --   * the log has to be sending its lines out. It does that by itself
    --     only while its tab is in front; asking it to keep on is allowed
    --     (tried: no objection), and is asked again whenever it has stopped,
    --     out of combat;
    --   * its filter has to be "My actions". On any other, and whenever the
    --     lines aren't coming, the guess is used as before.
    -- A line is good for one hit, for 0.8 s: both lines of a swing (the
    -- blow, and a seal's or a weapon's own extra) are printed together at
    -- the swing, while the second hit is only reported some half a second
    -- later (measured; at a third of a second the second hit of every
    -- swing was being thrown away). A hit that comes ahead of its line
    -- waits a quarter of a second for it.
    --
    -- The blow that kills. When it is that later, second hit that kills,
    -- the game never reports the hit at all (the enemy is gone before it
    -- would have): there is its log line, the log's white "You killed"
    -- notice, and nothing else, and the amount is inside the sealed line.
    -- That case is recognised (more lines printed with the kill notice than
    -- hits reported with it) so that its line is not left over for some
    -- later hit to use, and nothing is shown for it: there is no amount.
    local CL = C_CombatLog
    local logLines, held = {}, {}
    local logHeard = false
    local lastLine, lineCount = -99, 0
    local lineTimes, claimTimes = {}, {} -- when lines came, and when a hit took one (the last dozen of each)
    local twinKey, twinAt
    local threatWorks = false -- the game has answered "is it fighting you?" at least once
    -- ── A filter that prints only your hits ──────────────────────────────
    -- "My actions" as it comes prints your heals, their ticks and more
    -- beside your hits, and nothing for a miss. Each spare line could be
    -- spent on somebody else's hit (a healer in a group saw everyone's
    -- numbers), and misses had to be guessed. With the filter set to pass
    -- only damage and misses, a line means exactly one hit or miss of yours.
    --
    -- An addon may not set that: handing the log a filter was tried, and the
    -- game put up its "blocked from an action" box (the log's own code ends
    -- in calls only the game's interface may make). It may be READ, though,
    -- and the player can set it by hand in the log's own settings (Combat
    -- Log tab, right-click, Settings, "My actions", Message Types): heals
    -- off, misses on. So what the filter in use passes is looked at:
    --   ownSeen:   it passes nothing but damage, misses and deaths;
    --   missLines: it passes misses.
    -- and the rules below use whichever holds. (Looked at again every few
    -- seconds: it can be changed at any time.)
    local ownSeen, missLines = false, false
    local OWN_OK = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, DAMAGE_SPLIT = true,
                     DAMAGE_SHIELD = true, SWING_MISSED = true, RANGE_MISSED = true, SPELL_MISSED = true, SPELL_PERIODIC_MISSED = true,
                     DAMAGE_SHIELD_MISSED = true, PARTY_KILL = true, UNIT_DIED = true, UNIT_DESTROYED = true, UNIT_DISSIPATES = true }
    local filterAt = -99
    local function filterCheck(now)
        if now - filterAt < 3 then return end
        filterAt = now
        local own, miss = false, false
        local cur = _G.Blizzard_CombatLog_CurrentSettings
        local fl = type(cur) == "table" and cur.filters
        if type(fl) == "table" then
            own = true
            for _, f in pairs(fl) do
                -- (An entry that names no one, the second one of "My
                -- actions", passes nothing: not counted.)
                local live = false
                if type(f) == "table" then
                    for _, flags in pairs({ f.sourceFlags, f.destFlags }) do
                        if type(flags) == "table" then for _, on in pairs(flags) do if on then live = true end end end
                    end
                end
                if live and type(f.eventList) == "table" then
                    for k, on in pairs(f.eventList) do
                        if on and not OWN_OK[k] then own = false end
                    end
                    if f.eventList.SWING_MISSED and f.eventList.SPELL_MISSED then miss = true end
                end
            end
        end
        if MinimalUIDB and (own ~= ownSeen or miss ~= missLines or not MinimalUIDB.ownfilter) then
            MinimalUIDB.ownfilter = date("%H:%M:%S") .. " the log's filter passes " .. (own and "only your damage" or "more than your damage")
                .. (miss and ", with misses" or ", without misses")
        end
        ownSeen, missLines = own, miss
    end
    -- One line taken for a hit: the oldest still good.
    -- tight: only a line printed in this very moment will do (a hit with no
    -- other sign of being yours; a line is stamped 0.8 s ahead of its time).
    local function takeLine(now, tight)
        while logLines[1] and logLines[1] < now do table.remove(logLines, 1) end
        local got
        if tight then
            for i = 1, #logLines do
                if logLines[i] - 0.8 >= now - 0.12 then got = table.remove(logLines, i) break end
            end
        else
            got = table.remove(logLines, 1)
        end
        if not got then return false end
        claimTimes[#claimTimes + 1] = now
        if #claimTimes > 12 then table.remove(claimTimes, 1) end
        return true
    end
    local MY_ACTIONS = _G.QUICKBUTTON_NAME_MY_ACTIONS or "My actions"
    local function logOn()
        if not logHeard or NP.db.numbersLog == false then return false end
        if not (CL and CL.AreFilteredEventsEnabled) then return false end
        local okE, on = pcall(CL.AreFilteredEventsEnabled)
        if not okE or secret(on) or not on then return false end
        local cur = _G.Blizzard_CombatLog_CurrentSettings
        local name = type(cur) == "table" and cur.name
        -- (Our own filter too: if its colours turn out not to come through,
        -- these older rules are what is left, and it passes only your
        -- damage and misses, which suits them.)
        return type(name) == "string" and not secret(name) and (name == MY_ACTIONS or name == "My actions" or name == LOGNAME)
    end
    local function note(text)
        if not MinimalUIDB then return end
        local d = MinimalUIDB.ctlog
        if type(d) ~= "table" then d = {}; MinimalUIDB.ctlog = d end
        d[#d + 1] = string.format("%.2f %s", GetTime() % 1000, text)
        if #d > 700 then table.remove(d, 1) end
    end
    -- ── The game's damage meter as a ledger of YOUR hits (a measurement) ──
    -- The meter keeps your damage apart from everyone else's, by ability.
    -- Its totals are hidden in a fight, but how many abilities are listed is
    -- not, and the meter can be wiped. Wiped after every look, anything
    -- listed under you is damage you did since the last look: yours for
    -- certain, in a group too, and with its ability. (Another addon,
    -- MidnightBattleText, draws its numbers this way.) The cost: the game's
    -- own damage meter shows nothing while this runs.
    -- For now only written into the log beside the hits, to see how the
    -- two line up before any rule is hung on it.
    -- meterOn: the meter is the proof that a hit was yours. It moves, with
    -- something listed under you, in the very moment a blow of yours lands
    -- (seen: the same instant as the hit's own report, or up to a second
    -- before it; never after). So a hit reported on an enemy waits
    -- (pendingW) for the meter to move in that instant, and when the meter
    -- moves with no hit yet reported, the next one reported is the one
    -- (grantAt). The number, the place and the critical all come from the
    -- hit's own report, as before: the meter's amounts are per ability, and
    -- a thunder clap on three enemies is one sum there.
    -- Not for the ticks of an effect of yours: those reach the meter only
    -- together with your next blow, so they go by their own sign.
    -- (Only when "Meniscus (damage meter blanked)" is the choice: reading
    -- the meter this way wipes it, so it shows nothing.)
    local meterOn, pendingW = false, {}
    local grantAt, grantNow = nil, nil
    -- The same for heals, from the meter's "healing done" list: a heal on
    -- someone waits for that list to show something under you.
    local healT = Enum and Enum.DamageMeterType and Enum.DamageMeterType.HealingDone or nil
    local pendingH, grantHAt, grantHNow = {}, nil, nil
    do
        local DM = C_DamageMeter
        if DM and DM.ResetAllCombatSessions and DM.GetCombatSessionSourceFromType then
            local mf = CreateFrame("Frame")
            local heard = pcall(mf.RegisterEvent, mf, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
            if MinimalUIDB then MinimalUIDB.meterdiag = "the meter's update event " .. (heard and "can be listened for" or "cannot be listened for") end
            meterOn = heard and NP.db.numbersMode == "meter"
            local guid, quietAt = nil, -9
            local function show(v) if secret(v) then return "hidden" end return tostring(v) end
            local function look(how, kind)
                local now = GetTime()
                if not guid then local okG, g = pcall(UnitGUID, "player"); guid = okG and g or nil end
                local function listed(kindOf)
                    local ok, src = pcall(DM.GetCombatSessionSourceFromType, 0, kindOf, guid)
                    local l = ok and type(src) == "table" and not secret(src) and src.combatSpells
                    if type(l) == "table" and not secret(l) then return l, #l end
                    return nil, -1
                end
                local list, n = listed(0)
                local nH = -1
                if healT and not secret(healT) then local _; _, nH = listed(healT) end
                if n <= 0 and nH <= 0 then
                    if how == "told" and now - quietAt > 0.5 then
                        quietAt = now
                        note("    METER moved: nothing of yours listed" .. (n < 0 and " (could not be read)" or ""))
                    end
                    return
                end
                if nH > 0 then
                    local drawnH = 0
                    if meterOn then
                        for i = 1, #pendingH do
                            local rec = pendingH[i]
                            if now - rec.t <= 0.03 then
                                drawnH = drawnH + 1
                                present(rec.unit, rec.rel, rec.x, rec.y, "HEAL", rec.indicator, rec.amount, rec.school, false, false)
                            end
                        end
                        wipe(pendingH)
                        if drawnH > 0 then grantHNow, grantHAt = now, nil else grantHAt = now end
                    end
                    note(string.format("    METER heals: %d of yours, %d drawn", nH, drawnH))
                end
                if n <= 0 then pcall(DM.ResetAllCombatSessions) return end
                local parts = {}
                for i = 1, math.min(n, 4) do
                    local sp = list[i]
                    local okN, name = pcall(C_Spell.GetSpellName, sp.spellID)
                    local okI, icon = pcall(C_Spell.GetSpellTexture, sp.spellID)
                    parts[#parts + 1] = string.format("[name %s, icon %s, amount %s, by %s]", okN and show(name) or "refused", okI and show(icon) or "refused",
                        show(sp.totalAmount), show(sp.creatureName))
                end
                local drawn = 0
                if meterOn then
                    for i = 1, #pendingW do
                        local rec = pendingW[i]
                        if now - rec.t <= 0.03 then
                            drawn = drawn + 1
                            present(rec.unit, rec.rel, rec.x, rec.y, "WOUND", rec.indicator, rec.amount, rec.school, false, rec.pet)
                        end
                    end
                    wipe(pendingW)
                    if drawn > 0 then grantNow, grantAt = now, nil else grantAt = now end
                end
                local okR, err = pcall(DM.ResetAllCombatSessions)
                note(string.format("    METER (%s): %d of yours, %d drawn %s; wiped: %s", how, n, drawn, table.concat(parts, " "), okR and "yes" or ("refused: " .. tostring(err):sub(1, 80))))
            end
            -- (Some hits moved the meter without the game saying so: it is
            -- also looked at every frame of a fight, to see whether the
            -- damage was there all along.)
            -- (Only when the meter is the chosen proof: every look wipes it.
            -- Left listening under "damage meter kept", it was wiping the
            -- meter there too.)
            if meterOn then mf:SetScript("OnEvent", function(_, _, kind) look("told", kind) end) end
        elseif MinimalUIDB then
            MinimalUIDB.meterdiag = "no damage meter to ask"
        end
    end
    local function dropStale(now)
        while held[1] and now - held[1].t > 0.25 do
            table.remove(held, 1)
            note("  a held hit got no log line: not yours, dropped")
        end
    end
    -- ── Whose hit, with our own filter in the log ───────────────────────────
    -- With the filter at the top of this section in use, every line the log
    -- prints is a thing of yours, and its colour says what kind. How lines
    -- and hits arrive, as recorded:
    --   * a spell's or a special's line comes first and its hit right behind
    --     it, in the same moment (an area spell: line, hit, line, hit);
    --   * a tick's hit comes first, and its line right behind;
    --   * a swing's line comes when the blow is struck, but its hit is only
    --     reported when the swing is seen to land: 0.26, 0.58 or 1.3 s later
    --     in the fights looked at. That gap is where somebody else's blow
    --     can slip in. So a swing's hit has to be on the enemy you were
    --     attacking when the line came, physical, and (in a group, once
    --     enough of your own swings have been timed) one of your usual gaps
    --     after the line.
    -- A hit is yours if a line of the right kind is there for it, and each
    -- line is good for one hit.
    --
    -- On your own there is a surer sign (the enemy is fighting you), and
    -- that still decides what is shown. The pairing is worked out all the
    -- same and written beside it in the record ("engine #n"), so how often
    -- the two agree can be counted before the pairing is trusted in a
    -- group, where it is the only sign there is.
    local KCLASS = { swing = "wound", shot = "wound", spell = "wound", tick = "wound", shield = "wound", split = "wound",
                     swingmiss = "miss", shotmiss = "miss", spellmiss = "miss", tickmiss = "miss", shieldmiss = "miss", miss = "miss",
                     heal = "heal", healtick = "heal", kill = "kill" }
    local KSLOW = { swing = true, shot = true, swingmiss = true, shotmiss = true } -- the hit is reported later than the line
    local KAFTER = { tick = true, healtick = true, tickmiss = true }               -- the line comes just after the hit
    local eLines, eHits, eNext = {}, {}, 0
    -- Somebody else has been hitting what you are fighting (until this
    -- time): a swing's hit is then proved by its amount, in a group or not.
    local contested = 0
    -- Hits just ruled "not yours" that had a sign of being yours: kept a
    -- moment, in case their line is only late (see eRescue).
    local eLate = {}
    local labTicks = {} -- amounts of your ticks since the meter last took in a blow of yours
    local gateShow      -- (set further down: a swing's hit shown behind the gate)
    local typedSeen, typedOdd = 0, 0
    local lastSlow, lastPaired
    local lastKillAt, recent = -99, {} -- when you last killed; the last few hits paired with a line
    -- How the first few numbers drawn from lines measured (their width is
    -- asked for once each, and only "something" or "nothing" is kept): if
    -- they are never seen, this says whether the line drew as numerals.
    -- (0.1.651: the first three killing swings drawn this way, with a make
    -- of the typeface that measured right, all measured as nothing, and
    -- the feature switched itself off. But a width of nothing has two
    -- readings: the line drew as nothing, or the game will not measure a
    -- string that holds a log line at all, however it draws. So the same
    -- line is now also put in an unseen string in the ordinary typeface
    -- and measured there: only if THAT has a width and the numerals' string
    -- has none is it settled that the numerals are not drawing. Otherwise
    -- it stays on, and whether numbers show is for the player's eyes.)
    local seenN, seenKinds = 0, {}
    local function lineSeen(f, msg)
        if seenN >= 12 or not MinimalUIDB then return end
        seenN = seenN + 1
        local fs, serial = f.fs, f.serial
        local plainFs = host.lineProbe
        if not plainFs then
            plainFs = host:CreateFontString(nil, "BACKGROUND")
            ns:SetFont(plainFs, 13, "", true)
            plainFs:SetAlpha(0)
            plainFs:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -400)
            pcall(plainFs.SetWordWrap, plainFs, false)
            host.lineProbe = plainFs
        end
        pcall(plainFs.SetText, plainFs, msg)
        C_Timer.After(0.1, function()
            if f.serial ~= serial or not f.live then return end
            local function kindOf(str, some, none)
                local okW, w = pcall(str.GetUnboundedStringWidth or str.GetStringWidth, str)
                return (not okW and "could not be asked") or (secret(w) and "hidden") or (type(w) ~= "number" and "no answer")
                    or (w > 2 and some or none)
            end
            local k = kindOf(fs, "numerals there", "nothing drawn")
            local kp = kindOf(plainFs, "has a width", "no width")
            pcall(plainFs.SetText, plainFs, "")
            k = k .. " (the same line in the ordinary typeface: " .. kp .. ")"
            seenKinds[k] = (seenKinds[k] or 0) + 1
            local parts = {}
            for name, n in pairs(seenKinds) do parts[#parts + 1] = name .. " x" .. n end
            table.sort(parts)
            MinimalUIDB.linewide = table.concat(parts, "; ")
            local bad = seenKinds["nothing drawn (the same line in the ordinary typeface: has a width)"] or 0
            local good = false
            for name in pairs(seenKinds) do if name:find("^numerals there") then good = true end end
            if textOK and bad >= 3 and not good then
                textOK = false
                MinimalUIDB.digitface = tostring(MinimalUIDB.digitface) .. " Switched off again: log lines measured as nothing in it, though they have a width in the ordinary typeface."
                note("(numbers from log lines switched off: three drew as nothing)")
            end
        end)
    end
    -- A line's own text, drawn as its number (see "A number from a log
    -- line's own text"). h: the hit taken for its report, if there is one:
    -- where the number goes, and whether it is a critical, come from that.
    -- Without one it rises from where your target's numbers do (hang: or,
    -- with numbers set to show over the enemy, from the nameplate of the
    -- enemy you were attacking as the blow was struck).
    -- (0.1.718) A heal of yours with no report behind it: one on somebody
    -- who is neither you, your target, nor under a nameplate (a party
    -- member, mostly). Its line is drawn as its number too, in the heals'
    -- green, where your numbers go when they have no nameplate. A heal on
    -- yourself is reported, and already shown from that: its line is spent
    -- on the report, not drawn again. Not while idle: in a fight, or within
    -- a quarter of a minute of a helping spell of yours.
    local function healLineDraw(L, why)
        if NP.db.numbersHealsOut == false then return false end
        local now = GetTime()
        if now - loadedAt < 10 then return false end
        for i = #selfHeals, 1, -1 do
            if selfHeals[i] >= L.t - 0.5 then
                table.remove(selfHeals, i)
                L.drawn = true
                note(string.format("  engine: a %s line is the heal on you just reported: not drawn again", L.kind))
                return true
            end
        end
        if not (fighting(now) or now - lastHelp < 15) then return false end
        local x, y = railSpot(nil, false)
        if not x then return false end
        showUnit = nil
        local tick = L.kind == "healtick"
        local f = show(nil, x, y, L.msg, tick and 0.42 or 0.38, tick and 0.80 or 0.92, tick and 0.64 or 0.54, false, tick or nil, nil, nil, true)
        if not f then return false end
        L.drawn = true
        note(string.format("  engine: a %s line drawn as its own number (%s)", L.kind, why))
        lineSeen(f, L.msg)
        return true
    end
    local function lineDraw(L, h, why, hang)
        if L.drawn or not (textOK and L.msg) then return false end
        if KCLASS[L.kind] == "heal" then
            if h then return false end
            return healLineDraw(L, why)
        end
        if KCLASS[L.kind] ~= "wound" then return false end
        local now = GetTime()
        if now - loadedAt < 10 then return false end
        local rel, x, y, crit, school, pet, unit = nil, nil, nil, false, nil, false, nil
        if h then
            rel, x, y, unit, school, pet = h.rel, h.x, h.y, h.unit, h.school, h.pet and true or false
            crit = not secret(h.indicator) and h.indicator == "CRITICAL"
        else
            if not fighting(now) then return false end
            local plate = hang and NP.db.numbersWhere == "plate" and L.key ~= RAILKEY and L.key or nil
            if plate then
                rel, x, y = plate, 0, 4
                local token = plate.namePlateUnitToken
                if type(token) == "string" and not secret(token) then unit = token end
            else
                x, y = railSpot(L.key, true)
            end
        end
        if not x then return false end
        if not school and L.kind == "swing" then school = 1 end
        local c = (school and SCHOOL_TINT[school]) or SCHOOL_TINT[1]
        local kind = NP.db.numbersKind ~= false and school and SCHOOL_ICON[school] or nil
        local r, g, b, small = c[1], c[2], c[3], nil
        if pet then
            r, g, b, small = PET_TINT[1], PET_TINT[2], PET_TINT[3], not crit
            kind = NP.db.numbersKind ~= false and "micro_class_druid.tga" or nil
        end
        showUnit = unit
        local f = show(rel, x, y, L.msg, r, g, b, crit, small, kind, nil, true)
        if not f then return false end
        L.drawn = true
        note(string.format("  engine: a %s line drawn as its own number (%s)", L.kind, why))
        lineSeen(f, L.msg)
        return true
    end
    -- A hit shown in the moment of a kill: its line's number stands behind
    -- it, seen only if the game gave the hit's amount as nothing (zeroSet).
    local function lineUnder(h)
        local f = h.item
        if h.zdone or h.cls ~= "wound" or not (textOK and h.msg and f and f.live and f.serial == h.serial) then return end
        h.zdone = true
        local zfs = zeroSet(f)
        if not zfs then return end
        if not pcall(f.zbar.SetValue, f.zbar, h.amount) then return end
        if not pcall(zfs.SetText, zfs, h.msg) then return end
        zfs:SetTextColor(f.cr or 1, f.cg or 1, f.cb or 1, 1)
        f.zback:SetVertexColor(0, 0, 0, shade())
        f.zbox:Show()
        note(string.format("  engine #%d: at a kill: its line's own number stands behind it (seen only if the game gave the blow as nothing)", h.id))
    end
    local eDriver = CreateFrame("Frame")
    eDriver:Hide()
    local function oursCurrent()
        local cur = _G.Blizzard_CombatLog_CurrentSettings
        local name = type(cur) == "table" and cur.name
        return type(name) == "string" and not secret(name) and name == LOGNAME
    end
    -- Our filter is in use, its lines are coming, and their colours are ours.
    local function typedOn()
        if not logHeard or NP.db.numbersLog == false or NP.db.numbersMode ~= "ours" then return false end
        if typedOdd >= 6 and typedSeen == 0 then return false end
        if not oursCurrent() then return false end
        local okE, on = pcall(CL.AreFilteredEventsEnabled)
        return (okE and not secret(on) and on) and true or false
    end
    local function autoOn()
        local f = (C_Spell and C_Spell.IsCurrentSpell) or _G.IsCurrentSpell
        local okA, auto = pcall(f, 6603)
        return okA and not secret(auto) and auto == true
    end
    -- How long after its line a swing of yours is reported: learnt on your
    -- own, where there is no doubt which hit was the swing's
    -- (MinimalUIDB.swingd: each usual gap, and how often it was seen).
    local function delayLearn(dt)
        if not MinimalUIDB then return nil end
        local d = MinimalUIDB.swingd
        if type(d) ~= "table" then d = {}; MinimalUIDB.swingd = d end
        for i = 1, #d do
            local c = d[i]
            if math.abs(c.d - dt) <= 0.06 then
                c.d = (c.d * c.n + dt) / (c.n + 1)
                c.n = math.min(c.n + 1, 60)
                return c
            end
        end
        if #d < 8 then d[#d + 1] = { d = dt, n = 1 }; return d[#d] end
        return nil
    end
    local function delayKnown(dt)
        local d = MinimalUIDB and MinimalUIDB.swingd
        if type(d) ~= "table" then return true end
        local total = 0
        for i = 1, #d do total = total + d[i].n end
        if total < 8 then return true end
        for i = 1, #d do
            if d[i].n >= 2 and math.abs(d[i].d - dt) <= 0.07 then return true end
        end
        return false
    end
    local function ePair(L, h, how, now)
        L.used, h.done, h.mine = true, true, true
        local dt = h.t - L.t
        -- Yours or your pet's: a swing on the enemy you are swinging at is
        -- yours, one on what the pet is attacking is the pet's; a spell is
        -- yours unless only the pet had just cast.
        local pet = false
        if h.cls ~= "heal" then
            if KSLOW[L.kind] then
                pet = not (h.key == L.key and h.auto) and L.petKey ~= nil and h.key == L.petKey
            else
                pet = (not h.own) and h.petSign == true
            end
        end
        h.pet = pet
        h.how = string.format("%s line, %s (%+.2f s)%s", L.kind, how, dt, pet and ", pet's" or "")
        note(string.format("  engine #%d: yours: %s", h.id, h.how))
        lastPaired = h
        h.quick = not KSLOW[L.kind] and not KAFTER[L.kind]
        h.lineKind = L.kind
        if L.kind == "tick" and h.cls == "wound" and #labTicks < 6 then labTicks[#labTicks + 1] = h.amount end
        if KSLOW[L.kind] then
            local c
            if L.kind == "swing" and h.truth == true and dt >= 0 then c = delayLearn(dt) end
            lastSlow = { L = L, h = h, c = c }
        end
        h.msg = L.msg
        h.atKill = (L.killed or L.atKill or math.abs(h.t - lastKillAt) <= 0.05) and true or nil
        recent[#recent + 1] = h
        if #recent > 6 then table.remove(recent, 1) end
        if h.waiting and (h.show or (h.dead and L.killed)) then
            if L.drawn then
                -- (The line was drawn as its own number already: at the
                -- kill, or as its enemy's nameplate went. This is that
                -- blow's report, come after all: not a second number.)
                note(string.format("  engine #%d: its number is up already, drawn from its line", h.id))
            elseif textOK and L.msg and KSLOW[L.kind] and h.cls == "wound" and (h.grouped or h.t <= contested)
                   and lineDraw(L, h, "this hit is taken for its report: the amount is the line's own") then
                -- (In a group, or with a stranger on your enemy, the hit
                -- taken for a swing's report may be somebody else's. Its
                -- place and its "critical" are used; the amount drawn is
                -- your own line's, whoever's hit this was.)
            else
                h.item = present(h.unit, h.rel, h.x, h.y, h.action, h.indicator, h.amount, h.sch, false, pet)
                h.serial = h.item and h.item.serial or nil
                if h.atKill then lineUnder(h) end
            end
        elseif L.drawn then
            h.silent = true -- (paired as it arrived: the event below must not draw it again)
        end
    end
    -- A swing or a shot struck a moment ago, whose hit was still to be
    -- reported: is this hit that one? Asked only once the hit has waited its
    -- moment for a line of its own. (Asked at once, a tick landing while a
    -- swing's line waited took that line, its own line went spare, and the
    -- swing's real report was then thrown away: seen.)
    local function eSlow(h, now)
        -- (A line already drawn as its own number is only tried once no
        -- other fits: this hit is then that blow's late report, and is not
        -- drawn a second time.)
        for pass = 1, 2 do
            for i = 1, #eLines do
                local L = eLines[i]
                if not L.used and (pass == 2) == (L.drawn == true) and KSLOW[L.kind] and KCLASS[L.kind] == h.cls
                   and (h.key == L.key or (L.petKey ~= nil and h.key == L.petKey) or (L.killed and h.key == RAILKEY)) then
                    local dt = h.t - L.t
                    local fits = dt >= -0.05 and dt <= 1.6
                    if fits and L.kind == "swing" and h.school and h.school ~= 1 then fits = false end
                    -- (The gate: only where a line can't be drawn as its own
                    -- number. Where it can, the pairing below draws that.)
                    if fits and (h.grouped or h.t <= contested) and L.kind == "swing" and h.cls == "wound" and h.show and dt > 0.02
                       and not (textOK and L.msg) then
                        local pet = not (h.key == L.key and h.auto) and L.petKey ~= nil and h.key == L.petKey
                        if gateShow and gateShow(h, L, pet) then
                            h.done, h.mine = true, nil
                            note(string.format("  engine #%d: drawn behind the gate: shows only if it is exactly your swing of %.2f s ago", h.id, dt))
                            return true
                        end
                    end
                    if fits and h.grouped and L.kind == "swing" and dt > 0.1 and not delayKnown(dt) then fits = false end
                    if fits then
                        ePair(L, h, dt < 0.02 and "came with its hit" or "its report came later", now)
                        return true
                    end
                end
            end
        end
        return false
    end
    -- A spell's line with no hit behind it, a frame on: was its hit the one
    -- thrown out a moment before? Seen with Thunder Clap: both hits came
    -- first and their lines a quarter of a second later (the log runs
    -- behind now and then), and both numbers were lost.
    local function eRescue(L, now)
        for i = 1, #eLate do
            local h = eLate[i]
            if not h.rescued and KCLASS[L.kind] == h.cls and L.t - h.t >= 0 and L.t - h.t <= 0.6 then
                h.rescued, h.waiting = true, true
                ePair(L, h, "its line came late", now)
                return true
            end
        end
        return false
    end
    -- Lines and hits past their time.
    local function eSweep(now)
        for i = #eLate, 1, -1 do
            if now - eLate[i].t > 1 then table.remove(eLate, i) end
        end
        for i = #eLines, 1, -1 do
            local L = eLines[i]
            if L.used then
                table.remove(eLines, i)
            elseif not KSLOW[L.kind] and not KAFTER[L.kind] and now - L.t > 0.03 and #eLate > 0 and eRescue(L, now) then
                table.remove(eLines, i)
            elseif now - L.t > L.life then
                table.remove(eLines, i)
                if L.drawn then
                    -- (Its number went up from its own text: nothing is owed.)
                elseif lineDraw(L, nil, "no hit was reported for it") then
                    -- (noted there)
                elseif KCLASS[L.kind] ~= "heal" then
                    -- (Not noted for heals: yours on someone with no nameplate
                    -- have nowhere to be drawn, and filled the record.)
                    note(string.format("  engine: a %s line went unclaimed (no hit was reported for it)", L.kind))
                end
            end
        end
        for i = #eHits, 1, -1 do
            local h = eHits[i]
            if h.done then
                table.remove(eHits, i)
            elseif now - h.t > 0.07 then
                table.remove(eHits, i)
                -- (A line that came right behind this hit, and then found
                -- no hit behind itself: it was this hit's after all.)
                local got
                for j = 1, #eLines do
                    local L = eLines[j]
                    if not L.used and L.prev == h then got = L break end
                end
                if got then
                    ePair(got, h, "the line came just behind it", now)
                elseif h.cls == "wound" and lastPaired and lastPaired ~= h and lastPaired.quick and lastPaired.key == h.key
                       and lastPaired.t >= h.t and lastPaired.t - h.t <= 0.15 then
                    -- (Heroic Strike and its like: an empty swing reported
                    -- just ahead of the strike. It has no line, and must
                    -- not take a waiting swing's.)
                    h.done, h.mine = true, false
                    note(string.format("  engine #%d: not yours (the empty half of a strike)", h.id))
                elseif eSlow(h, now) then
                    -- (paired there)
                else
                    h.done, h.mine = true, false
                    note(string.format("  engine #%d: not yours (no line of yours for it)", h.id))
                    if h.own or h.truth == true then
                        if #eLate < 8 then eLate[#eLate + 1] = h end
                    end
                    -- (Somebody else's, as far as can be told: not the
                    -- empty half of a strike of your own.)
                    if h.cls ~= "heal" and not (h.own and h.school == 1) then contested = h.t + 30 end
                end
            end
        end
        if #eLines == 0 and #eHits == 0 then eDriver:Hide() end
    end
    eDriver:SetScript("OnUpdate", function() eSweep(GetTime()) end)
    local function eOnLine(kind, now, msg)
        eSweep(now)
        local cls = KCLASS[kind]
        if cls == "kill" then
            -- The blow that kills is often never reported as a hit (the
            -- enemy is gone before a swing is seen to land): a swing's line
            -- still waiting when you kill must not be spent on a later hit.
            -- (These lines were let go here at first, on the belief that
            -- the blow that kills is never reported. It is, now and then, a
            -- swing's usual gap after the kill: seen twice, 0.26 and 0.58 s
            -- on. More often it is not: three kills by a plain swing in one
            -- record, and no hit for any of them.)
            -- So the swing's line is drawn as its own number, here and now
            -- (0.1.644), where that can be done; it stays marked, and a
            -- report that does come after all is taken as that blow's (on
            -- the dead enemy's nameplate or, that gone, as your target's)
            -- and not drawn a second time. Where it can't be done the
            -- report, if one comes, is shown as before.
            -- A blow whose hit IS reported in the moment of the kill (a
            -- spell, a strike, a tick) keeps the number from its report,
            -- with its line's own number behind it: see lineUnder.
            lastKillAt = now
            -- (A swing's line has been seen to come a tenth of a second
            -- ahead of the notice, with a seal's own hit between them: one
            -- still unreported a third of a second on is drawn too. Whether
            -- it was the blow that killed or one on another enemy, it is a
            -- blow of yours with no number yet.)
            local function mark()
                for i = 1, #eLines do
                    local L = eLines[i]
                    local dt = now - L.t
                    if not L.used and KCLASS[L.kind] == "wound" then
                        if KSLOW[L.kind] then
                            if math.abs(dt) <= 0.05 then L.killed = true end
                            if dt >= -0.05 and dt <= 0.35 then lineDraw(L, nil, "the blow that killed") end
                        elseif math.abs(dt) <= 0.05 then
                            L.atKill = true
                        end
                    end
                end
                for i = 1, #recent do
                    local h = recent[i]
                    if math.abs(h.t - now) <= 0.05 then lineUnder(h) end
                end
            end
            mark()
            C_Timer.After(0.02, mark)
            return
        end
        -- (A heal's line waits longer: the report of a heal on yourself
        -- must have had time to come before the line is drawn by itself.)
        local L = { t = now, kind = kind, life = KSLOW[kind] and 1.6 or (KCLASS[kind] == "heal" and 0.45 or 0.15), msg = msg }
        -- (A line printed just behind the kill notice is of that moment too:
        -- the notice has been seen to come before the blow's own line.)
        local atKill = cls == "wound" and now - lastKillAt <= 0.05
        if atKill and not KSLOW[kind] then L.atKill = true end
        if KSLOW[kind] then
            -- (Whom you, and your pet, were attacking as the blow was struck.)
            L.key = plateOf("target") or RAILKEY
            local okP, has = pcall(UnitExists, "pettarget")
            if okP and not secret(has) and has then L.petKey = plateOf("pettarget") end
            -- (A swing reported at once, its line a frame behind it: seen.)
            for i = #eHits, 1, -1 do
                local h = eHits[i]
                if not h.done and h.cls == KCLASS[kind] and now - h.t <= 0.05 and (h.key == L.key or (L.petKey ~= nil and h.key == L.petKey))
                   and not (kind == "swing" and h.school and h.school ~= 1) then
                    ePair(L, h, "the line came just behind it", now)
                    return
                end
            end
        else
            local prev
            for i = #eHits, 1, -1 do
                local h = eHits[i]
                if not h.done and h.cls == cls and now - h.t <= 0.07 then prev = h break end
            end
            if prev and KAFTER[kind] then
                ePair(L, prev, "came with its hit", now)
                return
            end
            L.prev = prev
        end
        eLines[#eLines + 1] = L
        eDriver:Show()
        if atKill and KSLOW[kind] then
            L.killed = true
            lineDraw(L, nil, "the blow that killed")
        end
        -- In a group, a swing or a shot goes up now, as the blow is struck,
        -- from its line: which of the hits then reported on that enemy is
        -- its own can't be told, so none is waited for. (It has no
        -- "critical" look for the same reason: that is in the report.) The
        -- line stays on, so that a hit taken for its report is not drawn as
        -- well.
        if KSLOW[kind] and cls == "wound" and not L.drawn and textOK then
            local grouped = IsInGroup and IsInGroup()
            if grouped and not secret(grouped) then lineDraw(L, nil, "in a group: drawn as the blow is struck", true) end
        end
        return L
    end
    -- A hit reported on an enemy (or a heal on someone): true if a line of
    -- yours answers for it, false if not, nil if that is not known yet (a
    -- tick's line comes a moment after its hit).
    local function eOnHit(h, now, grouped)
        eSweep(now)
        -- 1. A line of this moment, of a kind whose hit comes with it: the
        --    oldest first.
        for i = 1, #eLines do
            local L = eLines[i]
            if not L.used and not KSLOW[L.kind] and KCLASS[L.kind] == h.cls and now - L.t <= (grouped and 0.05 or 0.15) then
                -- (Heroic Strike and its like are reported as two hits, an
                -- empty swing and then the strike. If the empty one took a
                -- swing's line a moment ago, that line goes back.)
                local sl = lastSlow
                if sl and sl.h.key == h.key and now - sl.h.t <= 0.15 and h.cls == "wound" and not KAFTER[L.kind] then
                    lastSlow = nil
                    if sl.c then sl.c.n = sl.c.n - 1 end
                    if now - sl.L.t <= sl.L.life then
                        sl.L.used = false
                        local there = false
                        for j = 1, #eLines do if eLines[j] == sl.L then there = true end end
                        if not there then eLines[#eLines + 1] = sl.L end
                        note("  engine: the swing line taken a moment ago goes back (that hit was the empty half of a strike)")
                    end
                end
                ePair(L, h, "came with its line", now)
                return true
            end
        end
        -- 2. (A swing struck a moment ago, whose hit was still to be
        --    reported, is tried last: see eSlow, at the end of the wait.)
        h.grouped = grouped
        -- 3. The other half of a blocked blow: the game reports one as two
        --    hits in the same moment, one line between them.
        local lp = lastPaired
        if lp and lp.key == h.key and lp.t == now and h.cls == "wound" and not secret(h.indicator) and not secret(lp.indicator)
           and ((h.indicator == "BLOCK" and lp.indicator == "BLOCK_REDUCED") or (h.indicator == "BLOCK_REDUCED" and lp.indicator == "BLOCK")) then
            h.done, h.mine, h.pet, h.how = true, true, lp.pet, "the other half of a blocked blow"
            note(string.format("  engine #%d: yours: %s", h.id, h.how))
            return true
        end
        -- 4. Not known yet: a tick's line comes just behind its hit.
        h.waiting = true
        eHits[#eHits + 1] = h
        eDriver:Show()
        return nil
    end

    -- An enemy's nameplate going away with a swing or a shot of yours on it
    -- still unreported (it died by someone else's hand, or left the screen):
    -- no report can come by that nameplate now, so the line is drawn as its
    -- own number here, and is done with. (Done with, too, if it was drawn
    -- already at your kill: the nameplate will be handed to another enemy,
    -- and that one's hits are not this line's.)
    do
        local pg = CreateFrame("Frame")
        pcall(pg.RegisterEvent, pg, "NAME_PLATE_UNIT_REMOVED")
        pg:SetScript("OnEvent", function(_, _, unit)
            if #eLines == 0 or type(unit) ~= "string" or secret(unit) then return end
            local plate = plateOf(unit)
            if not plate then return end
            for i = 1, #eLines do
                local L = eLines[i]
                if not L.used and KSLOW[L.kind] and L.key == plate then
                    if L.drawn or lineDraw(L, nil, "its enemy's nameplate went before the blow was reported") then L.used = true end
                end
            end
        end)
    end

    -- ── The lab's marks (see "The lab" near the top of this section) ───────
    local labGuid, labPrev, labHave, labNeed = nil, nil, false, false
    local labLines, labWait = {}, {}
    local labDriver = CreateFrame("Frame")
    labDriver:Hide()
    -- Your running total on the game's damage meter (read, never wiped). A
    -- hidden value in a fight: handed on to the bars as it is.
    local function labTotal()
        local got
        local ok = pcall(function()
            if not labGuid then labGuid = UnitGUID("player") end
            local src = C_DamageMeter.GetCombatSessionSourceFromType(0, 0, labGuid)
            got = 0
            if type(src) == "table" then
                local t = src.totalAmount
                if type(t) == "number" then got = t end
            end
        end)
        if not ok then return nil, false end
        return got, true
    end
    -- (Out of a fight the total can be read: the bars are kept big enough
    -- for three times it and some.)
    local function labSize()
        local t, ok = labTotal()
        if not ok then return end
        if type(t) == "number" and not secret(t) then labM = math.max(20000, t * 3 + 20000) end
        labPrev, labHave = t, true
    end
    local function labLine(now, kind)
        local r = { t = now, kind = kind }
        labLines[#labLines + 1] = r
        labNeed = true
        labDriver:Show()
        return r
    end
    -- ── A swing in a group, matched by its amount ───────────────────────────
    -- The one place the pairing above can be fooled is a swing in a group:
    -- its hit is reported up to 1.3 s after its line, and someone else's
    -- blow on the same enemy can land in between. There the hit is not
    -- judged at all. Every hit that could be the swing's is drawn, behind a
    -- gate that is only open if
    --     your total before the swing + (your ticks since) + this amount
    --         = your total after it
    -- (the lab's bars; tried on your own with marks: the true sum always
    -- showed, a sum off by one never did). Somebody else's hit stays behind
    -- a shut gate unless it is for exactly your swing's amount. Nothing is
    -- read, so the line is not used up: each hit in its time is tried.
    -- With ticks to count it is drawn twice, once for the sum without them
    -- and once with (which of the two the meter does was not settled); at
    -- most one of the two can be seen.
    local GATE_H = 70
    local function gateOne(h, L, also, pet)
        local f = present(h.unit, h.rel, h.x, h.y, h.action, h.indicator, h.amount, h.sch, false, pet)
        if not f then return end
        local extra = also and 4 or 0
        local key = also and "gateT" or "gateP"
        if f[key] == nil then
            local ok, G = pcall(newGauge, f, 0, 1, 1, 1, extra)
            f[key] = ok and G or false
            if ok then G.spot:Hide() end
        end
        local G = f[key]
        if not G or not setGauge(G, L.lab.b, h.amount, L.lab.a, also) then
            -- (No gate to be had: better not shown than shown unproven.)
            f.live = false
            f:Hide()
            return
        end
        G.win:Hide()
        f.gated = true
        f.gate:ClearAllPoints()
        f.gate:SetSize(300, GATE_H * 2)
        f.gate:SetPoint("TOP", G.amt:GetStatusBarTexture(), "TOP", 0, GATE_H - G_S * (1 + extra) - G_Y)
    end
    gateShow = function(h, L, pet)
        local lab = L.lab
        if not (lab and lab.set and lab.good) or lab.many or labM > 300000 then return false end
        local ticks = lab.ticks
        if ticks and #ticks > 4 then return false end
        gateOne(h, L, nil, pet)
        if ticks and #ticks > 0 then gateOne(h, L, ticks, pet) end
        return true
    end
    local function labMark(f, amount, now, h)
        if f.gauges == nil then
            local ok, err = pcall(function()
                f.gauges = { newGauge(f, -14, 1, 1, 1), newGauge(f, -5, 1, 0.25, 0.25), newGauge(f, 5, 0.3, 1, 0.4), newGauge(f, 14, 0.35, 0.6, 1, 4) }
            end)
            if not ok then
                f.gauges = false
                if MinimalUIDB then MinimalUIDB.labmarks = "the marks could not be built: " .. tostring(err):sub(1, 160) end
            end
        end
        -- A yellow mark, seen only where the amount is nothing at all: it
        -- sits in the part of the 0-to-1 bar its fill has NOT covered. (The
        -- blow that kills is drawn, by the record, and yet not seen: is the
        -- game reporting it as a hit for 0?)
        if f.zeroMark == nil and f.bar then
            f.zeroMark = false
            pcall(function()
                local z = CreateFrame("Frame", nil, f)
                z:SetClipsChildren(true)
                z:SetPoint("TOPLEFT", f.bar:GetStatusBarTexture(), "TOPRIGHT")
                z:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
                local d = CreateFrame("Frame", nil, z)
                d:SetSize(12, 12)
                d:SetPoint("CENTER", f, "CENTER", 0, 0)
                local t = d:CreateTexture(nil, "OVERLAY")
                t:SetAllPoints()
                t:SetTexture(MEDIA .. "circle.tga")
                t:SetVertexColor(1, 0.85, 0.2, 1)
                f.zeroMark = z
            end)
        end
        if not f.gauges then return end
        local okW = setGauge(f.gauges[1], 0, amount, amount)
        local okR = setGauge(f.gauges[2], 1, amount, amount)
        if MinimalUIDB and not MinimalUIDB.labmarks then
            MinimalUIDB.labmarks = "first marks set: white " .. tostring(okW) .. ", red " .. tostring(okR) .. "; the amount was "
                .. (secret(amount) and "hidden" or "plain") .. "; bars sized for " .. labM
        end
        f.gauges[3].win:Hide()
        f.gauges[4].win:Hide()
        labWait[#labWait + 1] = { f = f, amount = amount, t = now, serial = f.serial, h = h }
        labDriver:Show()
    end
    labDriver:SetScript("OnUpdate", function(self)
        local now = GetTime()
        if labNeed then
            -- A line of yours came since the last look: the total as it
            -- was before (the last reading) and as it is now.
            labNeed = false
            local t, ok = labTotal()
            local n = 0
            for i = 1, #labLines do if not labLines[i].set then n = n + 1 end end
            for i = 1, #labLines do
                local L = labLines[i]
                if not L.set then
                    L.set = true
                    L.good = ok and labHave
                    L.b, L.a, L.many = labPrev, t, n > 1
                    -- (A blow of yours: the ticks before it go with it, if
                    -- the meter only takes ticks in along with a blow.)
                    if L.kind ~= "tick" then
                        L.ticks = labTicks
                        labTicks = {}
                    end
                end
            end
            if ok then labPrev, labHave = t, true end
        end
        while labLines[1] and now - labLines[1].t > 2.5 do table.remove(labLines, 1) end
        for i = #labWait, 1, -1 do
            local w = labWait[i]
            if not w.f.live or w.f.serial ~= w.serial or not w.f.gauges then
                table.remove(labWait, i)
            elseif now > w.t then
                -- (A frame on from the hit, so a line of the same moment
                -- has its totals.)
                table.remove(labWait, i)
                -- Green: the plain sum, with the line the pairing gave
                -- this hit (or the latest line). Blue: the same sum with
                -- your ticks since the blow before counted in.
                local kind = w.h and w.h.lineKind
                local used, said = 0, ""
                for j = #labLines, 1, -1 do
                    local L = labLines[j]
                    if used < 1 and L.set and L.good and L.t <= w.t + 0.02 and w.t - L.t <= 1.7 and (kind == nil or L.kind == kind) then
                        used = 1
                        setGauge(w.f.gauges[3], L.b, w.amount, L.a)
                        local nt = L.ticks and #L.ticks or 0
                        if L.kind ~= "tick" and nt <= 4 then setGauge(w.f.gauges[4], L.b, w.amount, L.a, L.ticks) end
                        said = string.format(" %s %.2f s before%s; blue counts in %d tick(s)", L.kind, w.t - L.t, L.many and " (one of several in its moment)" or "", nt)
                    end
                end
                note(string.format("  marks #%s (%s): green from%s", tostring(w.h and w.h.id or "?"), tostring(kind or "unpaired"), said ~= "" and said or " no line"))
            end
        end
        if not labNeed and #labWait == 0 and #labLines == 0 then self:Hide() end
    end)
    if NP.db.numbersMode == "ours" then
        local lr = CreateFrame("Frame")
        lr:RegisterEvent("PLAYER_REGEN_ENABLED")
        lr:SetScript("OnEvent", function()
            C_Timer.After(1.5, function() if not InCombatLockdown() then pcall(labSize) end end)
        end)
        C_Timer.After(2, function() pcall(labSize) end)
        -- (And the "before" reading kept fresh while nothing of yours is
        -- landing.)
        C_Timer.NewTicker(2, function()
            if not labNeed and #labLines == 0 then
                local t, ok = labTotal()
                if ok then labPrev, labHave = t, true end
            end
        end)
    end

    if guess and CL and CL.SetFilteredEventsEnabled and CL.AreFilteredEventsEnabled then
        local lf = CreateFrame("Frame")
        if pcall(lf.RegisterEvent, lf, "COMBAT_LOG_MESSAGE") then
            logHeard = true
            -- The log refilling. At every login and reload (and whenever its
            -- filter is changed) the log prints its old lines again, a
            -- hundred or two of them a hundredth of a second apart. Those
            -- are not hits: taken as such they filled this record (a whole
            -- session's worth was written over by them) and set off the
            -- kill reckoning for every old kill. A run of more than six
            -- lines inside a quarter of a second, out of combat, is a
            -- refill: ignored until the lines have been quiet for half a
            -- second. (In combat a burst that size is an area spell.)
            local recent, refilling, lastAny = {}, false, 0
            local function isRefill(now)
                if refilling and now - lastAny > 0.5 then refilling = false; wipe(recent) end
                lastAny = now
                if refilling then return true end
                recent[#recent + 1] = now
                while recent[1] and now - recent[1] > 0.25 do table.remove(recent, 1) end
                if #recent > 6 then
                    local okC, fighting = pcall(UnitAffectingCombat, "player")
                    if okC and not secret(fighting) and not fighting then
                        refilling = true
                        wipe(logLines); wipe(lineTimes); wipe(held)
                        lastLine = -99
                        note("(the log is refilling with old lines: ignored)")
                        return true
                    end
                end
                return false
            end
            -- An experiment (/men logtext): the log's lines themselves, put
            -- on the screen as they arrive. Their text is sealed (it can be
            -- drawn, not read), but under "My actions" every line is yours,
            -- and the amount is in it. If the line can be made short enough
            -- by the log's own formatting settings, the line could BE the
            -- combat text, with nothing to guess. This shows what they look
            -- like; their colours go in the record (ctlog) with each LINE.
            local strip, stripAt = nil, 0
            local function stripShow(msg, r, g, b)
                if not (MinimalUIDB and MinimalUIDB.logtext) then
                    if strip then strip:Hide() end
                    return
                end
                if not strip then
                    strip = CreateFrame("Frame", nil, UIParent)
                    strip:SetSize(700, 150)
                    strip:SetPoint("TOP", UIParent, "TOP", 0, -120)
                    strip:SetFrameStrata("HIGH")
                    strip.rows, strip.nums = {}, {}
                    for i = 1, 8 do
                        local t = strip:CreateFontString(nil, "OVERLAY")
                        ns:SetFont(t, 13, "OUTLINE", true)
                        t:SetPoint("TOP", 0, -(i - 1) * 18)
                        strip.rows[i] = t
                        -- (0.1.651: and the same line in the numerals-only
                        -- typeface, in yellow at the strip's left: what the
                        -- combat numbers would draw for it.)
                        local n = strip:CreateFontString(nil, "OVERLAY")
                        local path = digitPath or (MEDIA .. "digits-manrope-r.ttf")
                        if not pcall(n.SetFont, n, path, 15, "OUTLINE") then ns:SetFont(n, 13, "OUTLINE", true) end
                        n:SetTextColor(1, 0.82, 0.25)
                        n:SetPoint("TOPLEFT", strip, "TOPLEFT", -150, -(i - 1) * 18)
                        pcall(n.SetWordWrap, n, false)
                        strip.nums[i] = n
                    end
                    local cap = strip:CreateFontString(nil, "OVERLAY")
                    ns:SetFont(cap, 11, "OUTLINE", false)
                    cap:SetTextColor(0.7, 0.7, 0.75)
                    cap:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", -150, 4)
                    cap:SetText("Yellow, left: each line's amount alone (if this works)      White: the log's line")
                end
                strip:Show()
                stripAt = stripAt % 8 + 1
                local t = strip.rows[stripAt]
                if not pcall(t.SetText, t, msg) then t:SetText("(a line that could not be drawn)") end
                if strip.nums and strip.nums[stripAt] then pcall(strip.nums[stripAt].SetText, strip.nums[stripAt], msg) end
                if not (type(r) == "number" and not secret(r) and pcall(t.SetTextColor, t, r, g, b)) then t:SetTextColor(1, 1, 1) end
                for i = 1, 8 do
                    strip.rows[i]:SetAlpha(i == stripAt and 1 or 0.55)
                    if strip.nums then strip.nums[i]:SetAlpha(i == stripAt and 1 or 0.55) end
                end
            end
            ns.commands.logtext = function()
                if not MinimalUIDB then return end
                MinimalUIDB.logtext = not MinimalUIDB.logtext or nil
                if strip and not MinimalUIDB.logtext then strip:Hide() end
                ns:Print("Combat log lines on screen: " .. (MinimalUIDB.logtext and "on (hit something)" or "off") .. ".")
            end
            local function rgbNote(r, g, b)
                if type(r) ~= "number" or secret(r) or secret(g) or secret(b) then return " (colour hidden)" end
                return string.format(" colour %.2f %.2f %.2f", r, g, b)
            end
            lf:SetScript("OnEvent", function(_, _, msg, r, g, b)
                if isRefill(GetTime()) then return end
                pcall(stripShow, msg, r, g, b)
                -- With our own filter in use, a line's colour says what it
                -- was, and the pairing above takes it from here. (Whether
                -- the colours come through as asked is counted: three seen
                -- and it is settled that they do, six lines in other
                -- colours first and that they don't. The filter gets its
                -- heal lines only once they are known to.)
                if NP.db.numbersMode == "ours" and oursCurrent() then
                    local kind = logKind(r, g, b)
                    local rec = MinimalUIDB and MinimalUIDB.logfilter
                    if kind then
                        typedSeen = typedSeen + 1
                        if typedSeen == 3 and type(rec) == "table" then rec.typed = true end
                    else
                        typedOdd = typedOdd + 1
                        if typedOdd == 6 and typedSeen == 0 and type(rec) == "table" then rec.typed = false end
                    end
                    if kind and typedOn() then
                        local now = GetTime()
                        lastLine = now
                        lineCount = lineCount + 1
                        if MinimalUIDB then MinimalUIDB.ctlines = lineCount .. " log lines heard this session, the last at " .. string.format("%.2f", now % 1000) end
                        note("LINE " .. kind)
                        local EL = eOnLine(kind, now, msg)
                        if KCLASS[kind] == "wound" then
                            local lr = labLine(now, kind)
                            if EL then EL.lab = lr end
                        end
                        return
                    end
                end
                -- (White lines are the log's notices, "You killed ..." and
                -- the like: not a hit.)
                if type(r) == "number" and not secret(r) and r > 0.95 and g > 0.95 and b > 0.95 then
                    -- The kill notice. It is printed among the lines of the
                    -- blow that killed, not always after them (seen: before
                    -- one of them), so the lines and the hits around it are
                    -- counted a moment later: more lines than hits means a
                    -- hit the game will never report.
                    local at = GetTime()
                    note("LINE (white: a notice)")
                    C_Timer.After(0.2, function()
                        local lines, claims = 0, 0
                        for i = 1, #lineTimes do if math.abs(lineTimes[i] - at) <= 0.15 then lines = lines + 1 end end
                        for i = 1, #claimTimes do if claimTimes[i] >= at - 0.15 and claimTimes[i] <= at + 0.2 then claims = claims + 1 end end
                        if lines > claims then
                            note(string.format("  at the kill: %d lines, %d hits reported: the unreported one has no number, nothing shown", lines, claims))
                            -- (Those lines are spent: nothing later may use them.)
                            for i = #logLines, 1, -1 do
                                if math.abs((logLines[i] - 0.8) - at) <= 0.15 then table.remove(logLines, i) end
                            end
                            -- (The words "Killing blow" were shown here for a
                            -- while. Taken out by request: with no amount to
                            -- give, better nothing than words.)
                        end
                    end)
                    return
                end
                local now = GetTime()
                filterCheck(now)
                lastLine = now
                lineCount = lineCount + 1
                lineTimes[#lineTimes + 1] = now
                if #lineTimes > 12 then table.remove(lineTimes, 1) end
                if MinimalUIDB then MinimalUIDB.ctlines = lineCount .. " log lines heard this session, the last at " .. string.format("%.2f", now % 1000) end
                note("LINE" .. rgbNote(r, g, b))
                dropStale(now)
                local h = table.remove(held, 1)
                if h then
                    claimTimes[#claimTimes + 1] = now
                    if #claimTimes > 12 then table.remove(claimTimes, 1) end
                    note("  its log line came: shown")
                    present(h.unit, h.rel, h.x, h.y, h.action, h.indicator, h.amount, h.school, false, h.pet)
                    -- (And its twin, if it had one waiting: see "twin".)
                    for i = #held, 1, -1 do
                        local o = held[i]
                        if o.t == h.t and o.key == h.key then
                            table.remove(held, i)
                            note("  and its twin")
                            present(o.unit, o.rel, o.x, o.y, o.action, o.indicator, o.amount, o.school, false, o.pet)
                        end
                    end
                    return
                end
                -- (Never two with the same stamp: the kill's line is known by it.)
                local stamp = now + 0.8
                local prev = logLines[#logLines]
                if prev and stamp <= prev then stamp = prev + 0.0001 end
                logLines[#logLines + 1] = stamp
                if #logLines > 12 then table.remove(logLines, 1) end
            end)
            -- Keep the log sending. (Out of combat only: whether the game
            -- would mind mid-fight hasn't been tried.)
            local wasOurs, toldAside = false, false
            local function keep()
                if NP.db.numbersMode == "ours" then
                    if oursCurrent() then
                        wasOurs, toldAside = true, false
                    elseif wasOurs and not toldAside then
                        toldAside = true
                        ns:Print("Combat numbers: the Combat Log has been moved to another filter, so the older rules are deciding whose hits are whose. Click \"" .. LOGNAME .. "\" in the Combat Log tab to go back.")
                    end
                end
                if InCombatLockdown() or NP.db.numbersLog == false then return end
                local okE, on = pcall(CL.AreFilteredEventsEnabled)
                if okE and not secret(on) and not on then pcall(CL.SetFilteredEventsEnabled, true) end
            end
            local kf = CreateFrame("Frame")
            kf:RegisterEvent("PLAYER_REGEN_ENABLED")
            kf:RegisterEvent("PLAYER_ENTERING_WORLD")
            kf:SetScript("OnEvent", function() C_Timer.After(1, keep) end)
            C_Timer.NewTicker(3, keep)
        end
    end

    -- (The numerals-only typeface, measured: a moment after login, so the
    -- game has the file; again a few times if it had not.)
    C_Timer.After(1.5, function() pcall(digitCheck, 4) end)

    local labHit -- (the pairing's record of the hit in hand, for the lab's marks)
    -- (Asked by the health orb's own text, Extras: are heals on you shown here?)
    ns.HealsInZone = function() return NP.db.numbersHealsIn ~= false end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_COMBAT")
    ev:SetScript("OnEvent", function(_, _, unit, action, indicator, amount, school)
        if type(unit) ~= "string" or secret(unit) or secret(action) or type(action) ~= "string" then return end
        showUnit = unit
        labHit = nil
        local mine = unit == "player"
        local x, y, rel
        local onRail, key = false, nil
        local petShown = false
        if mine then
            if action == "HEAL" then
                selfHeals[#selfHeals + 1] = GetTime()
                if #selfHeals > 8 then table.remove(selfHeals, 1) end
            end
            -- What you take already rises out of the health orb, when that
            -- is on (Extras: orbText): not shown a second time here.
            local EX = ns.modules.Extras
            local OR = ns.modules.Orbs
            -- A heal on you (0.1.608): up where your own hits are shown, in
            -- its own shimmering colour, and no longer on the health orb.
            if action == "HEAL" and NP.db.numbersHealsIn ~= false then
                local hx, hy = railSpot(nil, false)
                local crit = not secret(indicator) and indicator == "CRITICAL"
                local f = show(nil, hx, hy, amount, 0.38, 0.95, 0.56, crit)
                if f then
                    f.irid, f.phase = true, math.random() * 6.28
                    if not crit then f.scale = f.scale * 1.25 end -- (a quarter larger than a hit, 0.1.623)
                    pcall(f.fs.SetFormattedText, f.fs, "+%d", amount)
                    pcall(f.warm.SetFormattedText, f.warm, "+%d", amount)
                    pcall(f.cool.SetFormattedText, f.cool, "+%d", amount)
                end
                return
            end
            if EX and EX.db and EX.db.orbText ~= false and OR and OR.health and OR.health:IsShown() then return end
            -- Switched off there: off, not moved here. (Beside your
            -- character is only for when there is no health orb to use.)
            if EX and EX.db and EX.db.orbText == false then return end
            local w, h = UIParent:GetWidth(), UIParent:GetHeight()
            x, y = w / 2 + (action == "HEAL" and 80 or -80), h * 0.46
        elseif unit:find("^nameplate") or unit == "target" then
            -- Over the enemy's nameplate, or on the rail beside your
            -- character: a fixed place on the screen that is ours, used
            --   * for everything, if that is what the setting says;
            --   * when the target is too far off to have a nameplate;
            --   * for the blow that kills (the nameplate is already on its
            --     way out, and a number hung on it went with it).
            -- (The target frame was tried as that second place: the client
            -- drops your target at death, the frame hides, and the number
            -- was never seen there.)
            if unit == "target" then
                -- With a nameplate up, the nameplate's own report of the
                -- same hit is the one shown.
                if not plateOf("target") then onRail, key = true, RAILKEY end
            else
                rel = plateOf(unit)
                key = rel
                if rel then
                    local okD, dead = pcall(UnitIsDeadOrGhost, unit)
                    if (okD and not secret(dead) and dead) or NP.db.numbersWhere ~= "plate" then onRail = true end
                end
            end
            if onRail then
                local isT = key == RAILKEY
                if not isT then
                    local okT, t = pcall(UnitIsUnit, unit, "target")
                    isT = okT and not secret(t) and t == true
                end
                rel = nil
                x, y = railSpot(key, isT)
            elseif rel then
                x, y = 0, 4
            end
            -- A hit for nothing at all isn't worth a number (when the
            -- amount can be read; in a fight it usually can't).
            if action == "WOUND" and not secret(amount) and amount == 0 then return end
            hitSchool = school
            local now = GetTime()
            local mineHit
            local tag = ""
            labHit = nil
            if meterOn and healT and key and guess and action == "HEAL" then
                local own = yoursOnly(unit, key, action, now)
                if own then
                    mineHit, byPet, why = true, false, "heal, by your cast"
                elseif grantHNow == now then
                    mineHit, byPet, why = true, false, "the meter listed a heal of yours this instant"
                elseif grantHAt and now - grantHAt <= 1.4 then
                    grantHNow, grantHAt = now, nil
                    mineHit, byPet, why = true, false, "the meter listed a heal of yours a moment ago"
                else
                    if x then
                        pendingH[#pendingH + 1] = { t = now, unit = unit, rel = rel, x = x, y = y, indicator = indicator, amount = amount, school = school }
                        if #pendingH > 16 then table.remove(pendingH, 1) end
                    end
                    mineHit, why = false, "waits for the meter's heals"
                end
            elseif meterOn and key and guess and action == "WOUND" then
                local own = yoursOnly(unit, key, action, now)
                local tick = own and why == "tick"
                local pet = (not own) and pets(unit, now) or false
                if tick then
                    mineHit, byPet, why = true, false, "tick of your effect"
                elseif grantNow == now then
                    mineHit, byPet, why = true, pet, "the meter moved for you this instant"
                elseif grantAt and now - grantAt <= 1.4 then
                    grantNow, grantAt = now, nil
                    mineHit, byPet, why = true, pet, "the meter moved for you a moment ago"
                else
                    if x then
                        pendingW[#pendingW + 1] = { t = now, unit = unit, rel = rel, x = x, y = y, indicator = indicator, amount = amount, school = school, pet = pet }
                        if #pendingW > 16 then table.remove(pendingW, 1) end
                    end
                    mineHit, why = false, "waits for the meter"
                end
            elseif not (key and guess) then
                mineHit, byPet, why = true, false, ""
            elseif typedOn() then
                -- Our own filter is in the log: lines are paired with hits
                -- (see "Whose hit, with our own filter in the log").
                local own = yoursOnly(unit, key, action, now)
                local ownWhy = why
                local pet = (not own) and action ~= "HEAL" and pets(unit, now) or false
                local grouped = IsInGroup and IsInGroup()
                if secret(grouped) then grouped = false end
                -- On your own, the plain sign: an enemy that is fighting you
                -- is being hit by you (or your pet); one that is not, and
                -- has nothing of yours aimed at it, is somebody else's.
                local onMe = false
                if not grouped and action ~= "HEAL" and UnitThreatSituation then
                    local okT, t = pcall(UnitThreatSituation, "player", unit)
                    onMe = okT and t ~= nil and not secret(t)
                    if onMe then threatWorks = true end
                end
                local truth
                if not grouped and action ~= "HEAL" then
                    if onMe then
                        truth = true
                    elseif threatWorks and not ((own and ownWhy ~= "tick") or pet) then
                        truth = false
                    end
                end
                eNext = eNext + 1
                local h = { id = eNext, t = now, cls = (action == "WOUND" and "wound") or (action == "HEAL" and "heal") or "miss",
                            unit = unit, rel = rel, x = x, y = y, action = action, indicator = indicator, amount = amount, sch = school,
                            key = key, own = own, petSign = pet, truth = truth, show = x ~= nil, auto = autoOn(),
                            dead = truth == false and x ~= nil }
                labHit = h
                if type(school) == "number" and not secret(school) then h.school = school end
                -- (The plain sign is no longer what decides: out in the
                -- world other players hit what you are fighting, and by
                -- that sign all of theirs was drawn as yours. Seen: 22 of a
                -- stranger's spells shown, every one of which the pairing
                -- had right. It is kept in the record, for the score.)
                tag = " #" .. h.id .. (truth == true and " [fighting you]" or truth == false and " [not fighting you]" or "")
                local verdict = eOnHit(h, now, grouped)
                if action == "HEAL" and own then
                    -- (Shown now, by your cast: not a second time when its
                    -- line comes.)
                    h.show = false
                    mineHit, byPet, why = true, false, "heal, by your cast"
                elseif verdict == true and h.silent then
                    mineHit, byPet, why = false, false, "its number is up already, drawn from its line"
                elseif verdict == true then
                    mineHit, byPet, why = true, h.pet, h.how
                else
                    mineHit, byPet = false, false
                    why = verdict == nil and "waits a moment for its line" or "no line of yours for it"
                end
            elseif logOn() then
                -- Yours or your pet's, for how it is drawn: the old signs
                -- are still good for telling those two apart.
                local own = yoursOnly(unit, key, action, now)
                local ownWhy = why
                local pet = (not own) and action ~= "HEAL" and pets(unit, now) or false
                dropStale(now)
                -- In a group a log line alone is not enough. Your heals and
                -- their ticks write lines too, and each one was spent on the
                -- next blow anyone landed: a healer saw the whole party's
                -- numbers without attacking. There, a hit also has to look
                -- like yours by the old signs (a cast, your swing, your dot,
                -- your pet's).
                local grouped = IsInGroup and IsInGroup()
                if secret(grouped) then grouped = false end
                -- On your own there is a plainer sign than any of the
                -- timing: the enemy is fighting you (you are on its threat
                -- list). Nobody else is hitting it, as a rule, so whatever
                -- lands on it is yours or your pet's: hits, ticks, misses,
                -- all of it, with no line to wait for. (Its line, if one
                -- is there, is still used up, so it can't be spent on a
                -- stranger's hit a moment later.) Not in a group, where
                -- everyone is on that list. If the game won't say, the
                -- rules below decide as before.
                local onMe = false
                if not grouped and action ~= "HEAL" and UnitThreatSituation then
                    local okT, t = pcall(UnitThreatSituation, "player", unit)
                    onMe = okT and t ~= nil and not secret(t)
                    if onMe then threatWorks = true end
                    if MinimalUIDB and not MinimalUIDB.threatdiag then
                        MinimalUIDB.threatdiag = "first asked: ok=" .. tostring(okT) .. " hidden=" .. tostring(secret(t)) .. " value=" .. (secret(t) and "?" or tostring(t))
                    end
                end
                if grouped and not ownSeen and not (own or pet) then
                    mineHit = false
                    why = "in a group, and no sign it was yours"
                elseif ownSeen and action == "HEAL" then
                    -- (The filter prints no heals: a heal goes by your cast alone.)
                    mineHit, byPet = own and true or false, false
                    why = own and "heal, by your cast" or "a heal, and no cast of yours"
                elseif threatWorks and not grouped and action ~= "HEAL" and not onMe and not ((own and ownWhy ~= "tick") or pet) then
                    -- On your own, an enemy that is not fighting you, and
                    -- nothing of yours aimed at it: somebody else's fight.
                    -- (A mage's missiles on a mob nearby were shown: a log
                    -- line of yours, left over from a hit already shown by
                    -- another rule, was spent on them.) Your opening blow,
                    -- before the enemy has turned on you, still passes: it
                    -- is on your target and follows a cast or swing. (A
                    -- "tick of your effect" does not pass here: an enemy
                    -- carrying an effect of yours is fighting you.)
                    mineHit = false
                    why = "not fighting you, and no sign it was yours"
                elseif onMe then
                    if action == "WOUND" and not (twinKey == key and twinAt == now) then
                        takeLine(now)
                        twinKey, twinAt = key, now
                    end
                    mineHit, byPet = true, pet
                    why = "on your own, and it is fighting you" .. (pet and ": pet's" or "")
                elseif action ~= "WOUND" and action ~= "HEAL" and not missLines then
                    -- (Where the filter passes misses, a miss has a line
                    -- like any hit, and is matched to it below.)
                    -- A miss, dodge, parry or block: the log prints no line
                    -- for these under "My actions" (seen: none within
                    -- seconds of any of them), so waiting for one threw away
                    -- every miss that came within three seconds of a hit,
                    -- which in a steady fight is nearly all of them. They go
                    -- by the old signs alone (your swing, your cast, your
                    -- pet's), and use up no line.
                    mineHit, byPet = (own or pet) and true or false, pet
                    why = mineHit and ("no line is written for a miss: by the old signs" .. (pet and ", pet's" or "")) or "a miss, and no sign it was yours"
                elseif twinKey == key and twinAt == now then
                    -- The same enemy, the same instant as a hit just shown:
                    -- one blow reported as two (Heroic Strike and its empty
                    -- swing), with one log line between them.
                    mineHit, byPet = true, pet
                    why = "twin of the hit before"
                elseif takeLine(now, ownSeen and grouped and not (own or pet)) then
                    -- (In a group, a hit with no other sign of being yours
                    -- has to arrive with its line, not merely within the
                    -- line's 0.8 s: someone else's blow rarely does.)
                    mineHit, byPet = true, pet
                    twinKey, twinAt = key, now
                    why = pet and "log line, pet's" or "log line"
                elseif (own or pet) and now - lastLine > 3 then
                    -- No lines have come for a while (in the first test of
                    -- this they stopped coming altogether, and every hit
                    -- was thrown away): the old signs are believed.
                    mineHit, byPet = true, pet
                    why = "no lines lately: by the old signs" .. (pet and ", pet's" or "")
                else
                    -- No line yet: it may be a frame behind. Kept a moment.
                    local h = { t = now, unit = unit, rel = rel, x = x, y = y, action = action, indicator = indicator,
                                amount = amount, school = school, pet = pet, key = key }
                    held[#held + 1] = h
                    if #held > 8 then table.remove(held, 1) end
                    mineHit = false
                    why = "no log line yet: held"
                end
            else
                mineHit = yours(unit, key, action, now)
            end
            -- What arrives for nameplates, and what was done with it (the
            -- last 24, MinimalUIDB.ctlog): to find out why misses and dodges
            -- on a mob were not showing.
            if MinimalUIDB then
                local d = MinimalUIDB.ctlog
                if type(d) ~= "table" then d = {}; MinimalUIDB.ctlog = d end
                d[#d + 1] = string.format("%.2f %s %s / %s  amount %s  school %s  %s%s", GetTime() % 1000,
                    unit == "target" and (onRail and "target(rail)" or "target(skipped: has a plate)") or (onRail and "plate(rail)" or "plate"), action,
                    tostring(not secret(indicator) and indicator or "?"),
                    secret(amount) and "hidden" or tostring(amount),
                    secret(school) and "hidden" or tostring(school),
                    mineHit and "shown" or "dropped", (why ~= "" and (" (" .. why .. ")") or "") .. tag)
                if #d > 700 then table.remove(d, 1) end
            end
            if not mineHit then return end
            petShown = byPet
        end
        if not x then return end
        local made = present(unit, rel, x, y, action, indicator, amount, school, mine, petShown)
        if made and labHit and not mine then
            labHit.item, labHit.serial = made, made.serial
            if labHit.atKill then pcall(lineUnder, labHit) end
        end
        if made and not mine and action == "WOUND" and labOn() then pcall(labMark, made, amount, GetTime(), labHit) end
    end)
end

-- Which combat numbers (db.numbersMode):
--   "game": the game's own, in our typeface. The game knows whose each hit
--           is, so these are always right, and its damage meter is left
--           alone. All an addon may change of them is the typeface and the
--           size. The default.
--   "ours": our numbers, proven yours by the game's combat log, through a
--           filter of our own that is put into it (see "A combat log filter
--           of our own"). The damage meter is left alone.
--   "meter": our numbers, proven yours by the damage meter, which shows
--           nothing while they are on (it is wiped after every look). Kept
--           beside "ours" to compare the two.
--   "off":  neither of ours; the game's settings are put back as they were.
local function gameNumbers(db)
    pcall(quietGame, false)
    for _, name in ipairs({ "floatingCombatTextCombatDamage_v2", "floatingCombatTextCombatHealing_v2",
                            "floatingCombatTextPetMeleeDamage_v2", "floatingCombatTextPetSpellDamage_v2" }) do
        pcall(SetCVar, name, "1")
    end
    -- (Left at a size the game no longer draws by an earlier version: back
    -- to the game's own.)
    for _, name in ipairs({ "WorldTextScale_v2", "WorldTextScale" }) do
        local ok, cur = pcall(GetCVar, name)
        if ok and tonumber(cur) and tonumber(cur) > 20 then
            local okD, def = pcall(GetCVarDefault, name)
            pcall(SetCVar, name, okD and def or "1")
        end
    end
end

-- The typeface the game draws its world numbers in (DAMAGE_TEXT_FONT) is
-- read as the world loads. Named at login it was too late (the numbers
-- stayed in the game's own face): it is named as the addon's settings
-- arrive, the earliest they can be known. (This frame is made after
-- Theme.lua's, so the chosen typeface is already worked out.) The game may
-- still only pick it up on a fresh log-in, not a reload.
do
    local ff = CreateFrame("Frame")
    ff:RegisterEvent("ADDON_LOADED")
    ff:SetScript("OnEvent", function(self, _, name)
        if name ~= ns.name then return end
        self:UnregisterAllEvents()
        local mods = ns.db and ns.db.modules
        local db = type(mods) == "table" and mods.Nameplates or nil
        local mode = db and db.numbersMode
        if mode == nil then mode = (db and db.numbers == false) and "off" or "game" end
        local T = ns.Theme
        local face = T and (T.fontBold or T.font)
        if mode == "game" and type(face) == "string" then
            face = face:gsub("/", "\\")
            _G.DAMAGE_TEXT_FONT = face
        end
        if MinimalUIDB then
            MinimalUIDB.gamefont = date("%H:%M:%S") .. " numbers: " .. tostring(mode) .. "; the game's typeface named as " .. tostring(_G.DAMAGE_TEXT_FONT)
        end
    end)
end

function NP:OnInit(db)
    self.db = db
    if db.numbersMode == nil then db.numbersMode = (db.numbers == false) and "off" or "game" end
    db.numbers = db.numbersMode == "ours" or db.numbersMode == "meter"
    if db.numbersMode == "ours" then
        C_Timer.After(6, function() pcall(logFilterTell) end)
        if MinimalUIDB and MinimalUIDB.lab == true then
            C_Timer.After(3, function() pcall(labCensus); pcall(labCalibrate) end)
        end
    end
    if db.numbersMode == "game" then
        pcall(gameNumbers, db)
    elseif db.numbersMode == "off" then
        pcall(quietGame, false)
    end
    if db.numbers ~= false then
        pcall(quietGame, true)
        local ok, err = pcall(buildNumbers)
        if not ok and MinimalUIDB then MinimalUIDB.ctdiag = "build failed: " .. tostring(err) end
    end
    if not C_NamePlate then return end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            -- The bright ring moves to the new target's plate.
            for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do pcall(stylePlate, plate) end
            return
        end
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then pcall(stylePlate, plate, unit) end
    end)
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do pcall(stylePlate, plate) end
end
