local ADDON, ns = ...
local T = ns.Theme

-- Resource monitor: how heavy is Meniscus?
--   /men perf          toggle a small live readout (memory, churn, CPU, FPS)
--   /men perf report   print a summary + the slowest timed jobs
--   /men perf reset    clear the timed-job stats
--   /men perf gc       full garbage collect, then show retained memory
-- A sample is logged every 60s into MinimalUIDB.perf (readable from the
-- SavedVariables file after /reload or logout), with peaks and job timings.
--
-- ns.Timed(label, fn, ...) wraps periodic work (skin passes, menu watchers)
-- so their cost shows up per job. debugprofilestop is cheap; always on.

local now = debugprofilestop
local stats = {}
ns.perfStats = stats

-- Also counts what the job allocated (the Lua heap's growth across the
-- call; a collection running in the middle shows as a drop and is skipped).
local gcCount = collectgarbage
function ns.Timed(label, fn, ...)
    local k0 = gcCount("count")
    local t0 = now()
    local a, b, c = fn(...)
    local dt = now() - t0
    local dk = gcCount("count") - k0
    local s = stats[label]
    if not s then s = { n = 0, ms = 0, max = 0, kb = 0 }; stats[label] = s end
    s.n = s.n + 1
    s.ms = s.ms + dt
    if dt > s.max then s.max = dt end
    if dk > 0 then s.kb = s.kb + dk end
    return a, b, c
end

-- ── Trace mode ────────────────────────────────────────────────────────────
-- /men perf trace (then /reload): every OnUpdate and OnEvent handler the
-- addon sets from then on is wrapped in ns.Timed, labelled with the file
-- and line that set it ("Orbs.lua:1164 OnUpdate"). The job list then shows
-- time and memory for each handler, which is how a cost that isn't in any
-- hand-timed job gets found. It adds a little overhead to everything, so it
-- is off unless asked for; run it again to turn it off.
-- (How: a post-hook on SetScript for each kind of frame. It only acts when
-- the call came from one of our files; everyone else's are left alone.)
local function installTrace()
    local wrapping, seen = false, {}
    local function hook(self, script, handler)
        if wrapping or type(handler) ~= "function" or (script ~= "OnUpdate" and script ~= "OnEvent") then return end
        local stack = debugstack(2, 6, 0)
        if type(stack) ~= "string" then return end
        local label
        for file, line in stack:gmatch("Meniscus[/\\]([%w_]+%.lua)[^:]*:(%d+)") do
            if file ~= "Perf.lua" then label = file .. ":" .. line .. " " .. script break end
        end
        if not label then return end
        wrapping = true
        pcall(self.SetScript, self, script, function(...) return ns.Timed(label, handler, ...) end)
        wrapping = false
    end
    for _, kind in ipairs({ "Frame", "Button", "StatusBar", "ScrollFrame", "CheckButton", "EditBox", "Slider",
                            "PlayerModel", "Cooldown" }) do
        local ok, f = pcall(CreateFrame, kind)
        local mt = ok and f and getmetatable(f)
        local idx = mt and mt.__index
        if type(idx) == "table" and not seen[idx] then
            seen[idx] = true
            pcall(hooksecurefunc, idx, "SetScript", hook)
        end
    end
    ns.perfTracing = true
end
local traceBoot = CreateFrame("Frame")
traceBoot:RegisterEvent("ADDON_LOADED")
traceBoot:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterAllEvents()
    if MinimalUIDB and MinimalUIDB.perfTrace then
        local ok, err = pcall(installTrace)
        if not ok then ns:Print("Perf trace could not start: " .. tostring(err)) end
    end
end)

-- ── Measurements ──────────────────────────────────────────────────────────
local updateMem = _G.UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
local getMem = _G.GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)

local function memKB()
    if not (updateMem and getMem) then return nil end
    pcall(updateMem)
    local ok, kb = pcall(getMem, ADDON)
    if ok and type(kb) == "number" then return kb end
end

-- CPU, ms per frame. Modern clients have an always-on profiler; older ones
-- need the scriptProfile CVar (which slows everything, so off by default).
local P = _G.C_AddOnProfiler
local M = _G.Enum and _G.Enum.AddOnProfilerMetric
local function cpu()
    if P and M and P.GetAddOnMetric and (not P.IsEnabled or P.IsEnabled()) then
        local ok1, recent = pcall(P.GetAddOnMetric, ADDON, M.RecentAverageTime)
        local ok2, peak = pcall(P.GetAddOnMetric, ADDON, M.PeakTime)
        local ok3, all = pcall(P.GetOverallMetric, M.RecentAverageTime)
        if ok1 and type(recent) == "number" then
            return recent, ok2 and peak or nil, ok3 and all or nil, "profiler"
        end
    end
    if _G.GetCVar and GetCVar("scriptProfile") == "1" and _G.GetAddOnCPUUsage then
        pcall(UpdateAddOnCPUUsage)
        local ok, total = pcall(GetAddOnCPUUsage, ADDON) -- ms since reload
        if ok and type(total) == "number" then return nil, nil, nil, "scriptProfile", total end
    end
    return nil, nil, nil, "none"
end

local function fmtKB(kb)
    if not kb then return "?" end
    if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
    return string.format("%d KB", kb)
end

-- Colors: fine / worth a look / heavy.
local OK, WARN, BAD = "|cff8fd19e", "|cffe6c26b", "|cffe57373"
local function grade(v, warn, bad) return (v >= bad and BAD) or (v >= warn and WARN) or OK end

-- ── Log ───────────────────────────────────────────────────────────────────
local session = { start = GetTime and GetTime() or 0 }
local lastMem, lastT, churn = nil, nil, 0
-- Per logged minute: memory grown, the highest one-interval rate, seconds
-- in combat, and which of our windows were seen open.
local minute = { grown = 0, peak = 0, t0 = nil, combat = 0, n = 0, wins = {} }
local WATCH = { "MinimalUIBags", "MinimalUICharacter", "MinimalUISpellbook", "MinimalUIQuestLog", "MinimalUIDialog",
                "MinimalUIMerchant", "MinimalUITrainer", "MinimalUIProfessions", "MinimalUIProfessionsBook",
                "MinimalUIBank", "MinimalUIMail", "MinimalUIInspect", "MinimalUILoot", "MinimalUIPanel",
                "WorldMapFrame", "CollectionsJournal", "SocialUIFrame", "CharacterFrame", "CommunitiesFrame" }

local function db()
    if not MinimalUIDB then return end
    local p = MinimalUIDB.perf
    if type(p) ~= "table" or p.session ~= session.id then
        p = { session = session.id, started = date("%Y-%m-%d %H:%M"), samples = {}, peakMem = 0, peakCPU = 0,
              traced = ns.perfTracing or false }
        MinimalUIDB.perf = p
    end
    return p
end

local function sample()
    local kb = memKB()
    local t = GetTime()
    if kb and lastMem and t > lastT then
        local d = (kb - lastMem) / (t - lastT)
        if d >= 0 then
            churn = d -- a drop is the GC; keep the last growth rate
            minute.grown = minute.grown + (kb - lastMem)
            if d > minute.peak then minute.peak = d end
        end
    end
    lastMem, lastT = kb, t
    minute.t0 = minute.t0 or t
    minute.n = minute.n + 1
    if InCombatLockdown() then minute.combat = minute.combat + 1 end
    for i = 1, #WATCH do
        local f = _G[WATCH[i]]
        if f and f.IsShown and f:IsShown() and f:GetAlpha() > 0.05 then minute.wins[WATCH[i]] = true end
    end
    local recent, peak = cpu()
    return kb, recent, peak
end

local function snapshotJobs(p)
    p.jobs = {}
    for label, s in pairs(stats) do
        p.jobs[label] = string.format("%d runs, %.2f ms avg, %.2f ms max, %.0f ms total, %.0f KB allocated (%.1f per run)",
            s.n, s.ms / math.max(s.n, 1), s.max, s.ms, s.kb or 0, (s.kb or 0) / math.max(s.n, 1))
    end
end

local function logSample()
    local p = db()
    if not p then return end
    local kb, recent, peak = sample()
    -- Churn: the average over the logged minute and the worst single
    -- interval in it (1 s while the readout is open, else the whole minute).
    local span = math.max(1, GetTime() - (minute.t0 or GetTime()))
    local tags = ""
    if minute.n > 0 and minute.combat > 0 then
        tags = tags .. string.format("  combat %.0f%%", minute.combat / minute.n * 100)
    end
    for name in pairs(minute.wins) do tags = tags .. "  " .. name:gsub("^MinimalUI", "") end
    table.insert(p.samples, string.format("%s  mem %s  churn avg %.1f peak %.1f KB/s  cpu %s ms/frame  fps %.0f%s",
        date("%H:%M"), fmtKB(kb), minute.grown / span, minute.peak,
        recent and string.format("%.3f", recent) or "n/a", GetFramerate(), tags))
    minute.grown, minute.peak, minute.t0, minute.combat, minute.n = 0, 0, GetTime(), 0, 0
    wipe(minute.wins)
    while #p.samples > 120 do table.remove(p.samples, 1) end
    if kb and kb > p.peakMem then p.peakMem = math.floor(kb) end
    if peak and peak > p.peakCPU then p.peakCPU = peak end
    snapshotJobs(p)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_LOGOUT")
boot:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        session.id = tostring(time())
        db()
        C_Timer.After(5, logSample)
        C_Timer.NewTicker(60, logSample)
    else
        local p = db()
        if p then snapshotJobs(p) end
    end
end)

-- ── Readout ───────────────────────────────────────────────────────────────
local box
local function buildBox()
    box = CreateFrame("Frame", "MinimalUIPerf", UIParent)
    box:Hide() -- new frames start shown; the toggle below would hide it at once
    box:SetSize(210, 92)
    box:SetFrameStrata("HIGH")
    box:SetClampedToScreen(true)
    box:SetMovable(true)
    box:EnableMouse(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving)
    box:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        MinimalUIDB.perfPos = { p, rp, x, y }
    end)
    local pos = MinimalUIDB.perfPos
    if pos then box:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else box:SetPoint("TOPLEFT", 20, -200) end
    ns.RoundedRect(box, -8, 0, 8, T.border[1], T.border[2], T.border[3], 1)
    ns.RoundedRect(box, -7, 1, 7, 0.06, 0.06, 0.07, 0.95)
    local title = box:CreateFontString(nil, "OVERLAY")
    ns:SetFont(title, 11, "", true)
    title:SetTextColor(unpack(T.textDim))
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Meniscus resources")
    box.body = box:CreateFontString(nil, "OVERLAY")
    ns:SetFont(box.body, 11)
    box.body:SetTextColor(unpack(T.text))
    box.body:SetPoint("TOPLEFT", 10, -24)
    box.body:SetJustifyH("LEFT")
    box.body:SetSpacing(2)
    local acc = 1
    box:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        local kb, recent, peak = sample()
        local _, _, all, src, total = cpu()
        local lines = {}
        lines[1] = "Memory  " .. (kb and grade(kb, 8192, 16384) or "") .. fmtKB(kb) .. "|r"
        lines[2] = "Churn   " .. grade(churn, 50, 200) .. string.format("%.1f KB/s", churn) .. "|r"
        if recent then
            local share = (all and all > 0) and string.format("  (%.0f%% of addons)", recent / all * 100) or ""
            lines[3] = "CPU     " .. grade(recent, 0.5, 2) .. string.format("%.3f ms/frame", recent) .. "|r" .. share
            lines[4] = "Peak    " .. (peak and string.format("%.1f ms", peak) or "?")
        elseif src == "scriptProfile" then
            lines[3] = string.format("CPU     %.0f ms since reload", total or 0)
        else
            lines[3] = "CPU     n/a on this client"
        end
        local fps = GetFramerate()
        table.insert(lines, "FPS     " .. grade(-fps, -50, -25) .. string.format("%.0f", fps) .. "|r")
        self.body:SetText(table.concat(lines, "\n"))
        self:SetHeight(32 + #lines * 13)
        -- Fit the widest line (the CPU line grows with its addon share).
        self:SetWidth(math.max(210, math.ceil(self.body:GetStringWidth()) + 24))
    end)
end

local function report()
    local kb = memKB()
    local recent, peak, all, src = cpu()
    local p = db()
    ns:Print(string.format("Memory %s (peak %s), churn %.1f KB/s", fmtKB(kb), fmtKB(p and p.peakMem), churn))
    if recent then
        ns:Print(string.format("CPU %.3f ms/frame recent, %.1f ms peak%s", recent, peak or 0,
            (all and all > 0) and string.format(", %.0f%% of all addons", recent / all * 100) or ""))
    else
        ns:Print("CPU: " .. (src == "scriptProfile" and "scriptProfile on (see readout)" or "no profiler on this client"))
    end
    local list = {}
    for label, s in pairs(stats) do table.insert(list, { label = label, s = s }) end
    table.sort(list, function(a, b) return a.s.ms > b.s.ms end)
    for i = 1, math.min(#list, 8) do
        local e = list[i]
        ns:Print(string.format("  %-22s %5d runs  %.2f ms avg  %.2f max  %.1f KB/run", e.label, e.s.n, e.s.ms / e.s.n, e.s.max,
            (e.s.kb or 0) / math.max(e.s.n, 1)))
    end
    if #list == 0 then ns:Print("  (no timed jobs have run yet)") end
end

ns.commands.perf = function(rest)
    rest = rest or ""
    if rest == "report" then
        report()
    elseif rest == "trace" then
        MinimalUIDB.perfTrace = not MinimalUIDB.perfTrace or nil
        ns:Print("Handler tracing " .. (MinimalUIDB.perfTrace and "ON" or "off") .. ". /reload to apply.")
    elseif rest == "reset" then
        wipe(stats)
        ns:Print("Timed-job stats cleared.")
    elseif rest == "gc" then
        local before = memKB()
        pcall(collectgarbage, "collect")
        local after = memKB()
        ns:Print(string.format("After a full collect: %s (was %s).", fmtKB(after), fmtKB(before)))
    else
        if not box then buildBox() end
        box:SetShown(not box:IsShown())
        MinimalUIDB.perfShown = box:IsShown()
    end
end

-- Keep the readout open across reloads if it was open.
local restore = CreateFrame("Frame")
restore:RegisterEvent("PLAYER_LOGIN")
restore:SetScript("OnEvent", function()
    if MinimalUIDB and MinimalUIDB.perfShown then buildBox(); box:Show() end
end)

-- ── Dev reload pill ───────────────────────────────────────────────────────
-- Always-on Reload button in the top-left corner while Meniscus is in
-- development. /men reloadbtn hides or shows it (remembered).
local reloadBtn
local function buildReload()
    local b = CreateFrame("Button", "MinimalUIReload", UIParent)
    b:SetSize(64, 22)
    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -8)
    b:SetFrameStrata("DIALOG")
    b:SetClampedToScreen(true)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    ns:SetFont(b.fs, 11, "", true)
    b.fs:SetPoint("CENTER")
    b.fs:SetText("Reload")
    b.paint = ns.EasePaint(b, ns.RoundedRect(b, -6, 0, 11, 0.13, 0.13, 0.15, 0.95))
    local function repaint(self)
        if self.hover then
            self.paint(0.20, 0.20, 0.23, 1)
            self.fs:SetTextColor(unpack(T.text))
        else
            self.paint(0.13, 0.13, 0.15, 0.95)
            self.fs:SetTextColor(unpack(T.textDim))
        end
    end
    b:SetScript("OnEnter", function(self) self.hover = true; repaint(self) end)
    b:SetScript("OnLeave", function(self) self.hover = false; repaint(self) end)
    b:SetScript("OnClick", function() ReloadUI() end)
    repaint(b)
    reloadBtn = b
end

local reloadBoot = CreateFrame("Frame")
reloadBoot:RegisterEvent("PLAYER_LOGIN")
reloadBoot:SetScript("OnEvent", function()
    buildReload()
    reloadBtn:SetShown(not (MinimalUIDB and MinimalUIDB.hideReloadBtn))
end)

ns.commands.reloadbtn = function()
    if not reloadBtn then return end
    local show = not reloadBtn:IsShown()
    reloadBtn:SetShown(show)
    MinimalUIDB.hideReloadBtn = not show
    ns:Print("Reload button " .. (show and "shown." or "hidden."))
end
