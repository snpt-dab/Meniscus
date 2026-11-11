local _, ns = ...

-- Micro menu and bag bar fade out entirely (buttons and their background
-- panels) until the mouse is over them. Optionally one anchor button stays
-- visible in each (game menu, backpack).
-- Frames stay where Edit Mode puts them and keep working; only alpha changes,
-- so this is safe in combat. Keybinds (C, P, B, Esc...) are unaffected.

local DC = ns:NewModule("Declutter", { enabled = true, fadeMenus = true, keepIcons = true })

local SPEED = 10 -- fade speed (higher = snappier)

-- Never fade these: they carry live status you need to see.
local ALWAYS = { QueueStatusButton = true }

local function groups()
    local list = {}
    local micro = MicroMenuContainer or MicroMenu
    if micro then
        table.insert(list, { hover = micro, holder = MicroMenu or micro, keep = MainMenuMicroButton })
    end
    if BagsBar then
        -- The keyring isn't a child of the bag bar, so name it explicitly.
        table.insert(list, { hover = BagsBar, holder = BagsBar, keep = MainMenuBarBackpackButton,
                             extras = { "KeyRingButton", "MainMenuBarKeyRingButton" } })
    end
    return list
end

local function signature(g)
    return select("#", g.holder:GetChildren()) + select("#", g.hover:GetChildren())
end

local EMPTY = {} -- (shared: no new table every tick)
local busy = false -- guards our SetAlpha hook against re-entry

-- The engine's own SetAlpha, bypassing any Lua override a button mixin adds.
local rawSetAlpha = getmetatable(CreateFrame("Button")).__index.SetAlpha
local function setA(o, a)
    if o:IsObjectType("Button") or o:IsObjectType("Frame") then rawSetAlpha(o, a) else o:SetAlpha(a) end
end

local function collect(g)
    for _, old in ipairs(g.items or {}) do old.__muiGroup = nil end
    g.items, g.art, g.sig = {}, {}, signature(g)
    local seen = {}
    local function addChildren(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            local name = child.GetName and child:GetName()
            if child ~= g.keep and child ~= g.holder and not seen[child] and not (name and ALWAYS[name]) then
                seen[child] = true
                table.insert(g.items, child)
            end
        end
    end
    addChildren(g.holder)
    if g.hover ~= g.holder then addChildren(g.hover) end
    for _, name in ipairs(g.extras or {}) do
        local f = _G[name]
        if f and not seen[f] then
            seen[f] = true
            table.insert(g.items, f)
            g.extraHover = g.extraHover or {}
            table.insert(g.extraHover, f)
        end
    end
    -- Blizzard sets some of these back to full alpha every frame (the keyring
    -- did), faster than our fade loop. Catch those calls and put our alpha back.
    for _, item in ipairs(g.items) do
        item.__muiGroup = g
        if not item.__muiHooked then
            item.__muiOwnSetAlpha = rawget(item, "SetAlpha") ~= nil -- diagnostic
            item.__muiHooked = true
            hooksecurefunc(item, "SetAlpha", function(self, a)
                local grp = self.__muiGroup
                if busy or not grp or grp.alpha < 0 then return end
                if type(a) == "number" and math.abs(a - grp.alpha) > 0.01 then
                    busy = true
                    setA(self, grp.alpha)
                    busy = false
                end
            end)
        end
    end
    -- Background panels / borders drawn directly on the containers.
    for _, frame in ipairs({ g.hover, g.holder }) do
        for _, r in ipairs({ frame:GetRegions() }) do table.insert(g.art, r) end
    end
end

local function apply(g, a)
    busy = true
    for _, item in ipairs(g.items) do setA(item, a) end
    busy = false
    -- Seated in the console's pill, the menu keeps its buttons but not the
    -- ornate box Blizzard draws around them.
    local artA = (ns.consoleMenus and g.holder ~= BagsBar) and 0 or a
    for _, r in ipairs(g.art) do r:SetAlpha(artA) end
    if g.keep then g.keep:SetAlpha((DC.db.keepIcons and not ns.consoleMenus) and 1 or a) end
end

function DC:OnInit(db)
    self.db = db
    local list = groups()
    for _, g in ipairs(list) do
        g.hover:SetAlpha(1) -- earlier versions faded the whole container
        collect(g)
        g.alpha = -1 -- force the first apply
    end
    self.groups = list

    local acc, rescan = 0, 0
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc, rescan = acc + dt, rescan + dt
        if acc < 0.03 then return end
        local step = math.min(acc * SPEED, 1)
        acc = 0
        local doRescan = rescan > 1
        if doRescan then rescan = 0 end
        for _, g in ipairs(list) do
            -- Bags can be added/removed (and the expand toggle shown); rescan now and then.
            if doRescan and signature(g) ~= g.sig then collect(g); g.alpha = -1 end
            local over = g.hover:IsMouseOver()
            for _, f in ipairs(g.extraHover or EMPTY) do over = over or f:IsMouseOver() end
            local want = (not DC.db.fadeMenus or over) and 1 or 0
            -- In the console (Bars.lua) the micro menu sits in a pill and is
            -- always visible; the bag bar is replaced by the bag pill.
            if ns.consoleMenus then want = (g.holder == BagsBar) and 0 or 1 end
            if g.alpha ~= want then
                local a = g.alpha < 0 and want or g.alpha + (want - g.alpha) * step
                if math.abs(a - want) < 0.02 then a = want end
                g.alpha = a
            end
            -- Apply every tick: Blizzard resets some of these (e.g. the keyring)
            -- to full alpha on its own updates.
            apply(g, g.alpha)
        end
    end)
end

-- /men keyring: list everything drawn by the keyring button, with alphas.
ns.commands.keyring = function()
    local k = _G.KeyRingButton or _G.MainMenuBarKeyRingButton
    if not k then ns:Print("No keyring button found.") return end
    local function info(o)
        local ign = o.IsIgnoringParentAlpha and o:IsIgnoringParentAlpha()
        local tex = o.GetTexture and o:GetTexture()
        return string.format("%s %s shown=%s a=%.2f eff=%.2f ignoreParent=%s %s",
            o:GetObjectType(), o:GetName() or "?", tostring(o:IsShown()), o:GetAlpha(),
            o.GetEffectiveAlpha and o:GetEffectiveAlpha() or -1, tostring(ign), tostring(tex or ""))
    end
    ns:Print(info(k), "parent:", k:GetParent() and (k:GetParent():GetName() or "?"))
    -- Declutter's view of it.
    local inItems, grp = false, k.__muiGroup
    for _, g in ipairs(DC.groups or {}) do
        for _, it in ipairs(g.items) do if it == k then inItems, grp = true, g end end
    end
    ns:Print(string.format("tracked=%s hooked=%s groupAlpha=%s over=%s ownSetAlpha=%s",
        tostring(inItems), tostring(k.__muiHooked), grp and string.format("%.2f", grp.alpha) or "nil",
        grp and tostring(grp.hover:IsMouseOver()) or "nil",
        tostring(k.__muiOwnSetAlpha)))
    rawSetAlpha(k, 0)
    ns:Print("after raw SetAlpha(0): a=" .. string.format("%.2f", k:GetAlpha()))
    for _, r in ipairs({ k:GetRegions() }) do ns:Print("  " .. info(r)) end
    for _, c in ipairs({ k:GetChildren() }) do
        ns:Print("  child " .. info(c))
        for _, r in ipairs({ c:GetRegions() }) do ns:Print("    " .. info(r)) end
    end
end

-- Force a re-apply (after toggling options in the panel).
function DC:Refresh()
    for _, g in ipairs(self.groups or {}) do g.alpha = -1 end
end
