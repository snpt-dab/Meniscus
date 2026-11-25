"""Quick Cure drawn by the game, tried outside the game.

The cure code in UnitFrames.lua (from `local CURES` to the party section) is
run against a stand-in for the game's aura containers. The stand-in follows
the rules of the game's own code (Blizzard_AuraContainer, build 1.60.1 71091):

  * what is handed to an aura button (its picture, animation groups) must be
    that button's child, however deep, and of the right type; an animation's
    target must be the button or its child; nothing can be added to a group
    once it is handed over; no script may be set on a button or under one;
  * a slot shows the first aura that passes "HARMFUL|RAID" and its candidate
    filters; asking a button whether it is shown gives a hidden value;
  * while auras are secret (a fight) every call from the addon on an aura
    button, or on anything under one, is refused ("denied" below);
  * casting buttons can't be shown, hidden, moved or given spells in a fight
    ("blocked" below).

Each case plays a paladin, a priest or a mage through a fight or two and
checks what would be seen. Run it after touching the cure code:

    PYTHONPATH=<folder with lupa> python dist/tests/cure_container.py [-v]

(lupa is the Lua 5.1 used for the syntax check: see CLAUDE.md. Run from the
addon's folder, or give the addon's folder as the last argument.)
"""
import io, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
from lupa import lua51 as L

args = [a for a in sys.argv[1:] if a != '-v']
VERBOSE = '-v' in sys.argv[1:]
ADDON = args[0] if args else os.path.join(HERE, '..', '..')
SRC = io.open(os.path.join(ADDON, 'UnitFrames.lua'), encoding='utf-8').read()
A = SRC.index('local CURES = {')
B = SRC.index('-- ── Party ─', A)
CHUNK = SRC[A:B]

HEAD = r'''
MinimalUIDB = {}
now = 0
function GetTime() return now end
combat = false
function InCombatLockdown() return combat end
SECRET = {}
function issecretvalue(v) return v == SECRET end
timers = {}
C_Timer = { After = function(t, fn) timers[#timers + 1] = fn end }
function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
blocked, denied = 0, 0
counts = {}
unknown = {}
ANIM = { SetFromAlpha = 1, SetToAlpha = 1, SetDuration = 1, SetStartDelay = 1, SetEndDelay = 1, SetSmoothing = 1,
         SetScaleFrom = 1, SetScaleTo = 1, SetOffset = 1, SetOrder = 1, GetTarget = 1, GetParent = 1, IsObjectType = 1,
         IsForbidden = 1, GetDebugName = 1, GetObjectType = 1 }
GROUP = { SetLooping = 1, CreateAnimation = 1, GetAnimations = 1, Play = 1, Stop = 1, GetParent = 1, IsObjectType = 1,
          IsForbidden = 1, GetDebugName = 1, IsPlaying = 1, GetObjectType = 1 }
local TYPES = { Frame = { Region = 1, Frame = 1 }, Button = { Region = 1, Frame = 1, Button = 1 },
  AuraButton = { Region = 1, Frame = 1, Button = 1, AuraButton = 1 }, AuraContainer = { Region = 1, Frame = 1 },
  Texture = { Region = 1, Texture = 1 }, Mask = { Region = 1, MaskTexture = 1 }, FontString = { Region = 1, FontString = 1 },
  AnimationGroup = { AnimationGroup = 1 }, Animation = { Animation = 1 } }
-- Is `w` one of the game's aura buttons, or anything under one?
local function auraOwner(w)
  local p = w
  while p do
    if rawget(p, "kind") == "AuraButton" then return p end
    p = rawget(p, "parent")
  end
end
local function guard(w, k)
  local o = auraOwner(w)
  if o and rawget(o, "restricted") and combat and not INSIDE_GAME then
    denied = denied + 1
    error("Access denied: an aura button touched while auras are secret (" .. tostring(k) .. ")", 3)
  end
end
function widget(kind, name, parent)
  counts[kind] = (counts[kind] or 0) + 1
  local w = { kind = kind, name = name, parent = parent, shown = true, attr = {}, scripts = {}, width = 20, height = 20,
              secure = false, alpha = 1, level = parent and ((rawget(parent, "level") or 0) + 1) or 1, points = {} }
  local methods = {}
  local mt = {}
  mt.__index = function(t, k)
    local m = methods[k]
    if m then
      return function(self, ...)
        guard(self, k)
        return m(self, ...)
      end
    end
    -- (methods only, as in the game: a field that was never set is nil)
    if type(k) == "string" and k:match("^%u") then
      if kind == "Animation" or kind == "AnimationGroup" then error("no such method on a " .. kind .. ": " .. k, 2) end
      unknown[kind .. ":" .. k] = true
      return function(self) guard(self, k) return nil end
    end
    return nil
  end
  setmetatable(w, mt)
  local function prot(self) if rawget(self, "secure") and combat then blocked = blocked + 1 return true end end
  function methods:Show() if prot(self) then return end self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
  function methods:Hide() if prot(self) then return end self.shown = false end
  function methods:IsShown() return self.shown end
  function methods:SetShown(v) if v then self:Show() else self:Hide() end end
  function methods:SetScript(n, fn)
    if auraOwner(self) then error("no script may be set on an aura button or under one") end
    self.scripts[n] = fn
  end
  function methods:HookScript(n, fn) self.scripts[n] = fn end
  function methods:SetAttribute(k, v) if prot(self) then return end self.attr[k] = v end
  function methods:SetSize(x, y) if prot(self) then return end self.width, self.height = x, y end
  function methods:SetWidth(x) if prot(self) then return end self.width = x end
  function methods:GetWidth() return self.width end
  function methods:GetHeight() return self.height end
  function methods:GetFrameLevel() return self.level end
  function methods:SetFrameLevel(n) if prot(self) then return end assert(type(n) == "number") self.level = n end
  function methods:SetFrameStrata(s) if prot(self) then return end self.strata = s end
  function methods:SetPoint(...) if prot(self) then return end self.points[#self.points + 1] = { ... } end
  function methods:SetAllPoints(to) if prot(self) then return end self.points = { { "ALL", to } } end
  function methods:ClearAllPoints() if prot(self) then return end self.points = {} end
  function methods:GetPoint(i) return nil end
  function methods:GetParent() return self.parent end
  function methods:IsObjectType(t) return TYPES[kind] and TYPES[kind][t] ~= nil end
  function methods:GetObjectType() return kind end
  function methods:IsForbidden() return false end
  function methods:IsProtected() return self.secure, self.secure end
  function methods:GetDebugName() return kind .. (name and (":" .. name) or "") end
  function methods:SetAlpha(v) assert(type(v) == "number") self.alpha = v end
  function methods:GetAlpha() return self.alpha end
  function methods:SetText(t) self.text = t end
  function methods:GetText() return self.text end
  function methods:GetStringWidth() return self.text and #self.text * 6 or 0 end
  function methods:SetTexture(t) self.texture = t end
  function methods:GetEffectiveScale() return 1 end
  if kind ~= "Texture" and kind ~= "FontString" and kind ~= "Mask" and kind ~= "Animation" and kind ~= "AnimationGroup" then
    function methods:CreateTexture() return widget("Texture", nil, self) end
    function methods:CreateMaskTexture() return widget("Mask", nil, self) end
    function methods:CreateFontString()
      local fs = widget("FontString", nil, self)
      self.words = self.words or {}
      table.insert(self.words, fs)
      return fs
    end
  end
  if kind ~= "Animation" and kind ~= "AnimationGroup" then
    function methods:CreateAnimationGroup()
      local g = widget("AnimationGroup", nil, self)
      g.anims = {}
      return g
    end
  end
  if kind == "AnimationGroup" then
    for k in pairs(methods) do if not GROUP[k] then methods[k] = nil end end
    function methods:SetLooping(v) assert(v == "REPEAT" or v == "BOUNCE" or v == "NONE") self.looping = v end
    function methods:CreateAnimation(what)
      assert(what == "Alpha" or what == "Scale" or what == "Translation" or what == "Rotation", "animation type " .. tostring(what))
      if self.frozen then error("nothing may be added to a group that was handed over") end
      local an = widget("Animation", nil, self)
      an.what = what
      self.anims[#self.anims + 1] = an
      return an
    end
    function methods:GetAnimations() return unpack(self.anims) end
    function methods:Play() self.playing = true; self.plays = (self.plays or 0) + 1 end
    function methods:Stop() self.playing = false end
    function methods:IsPlaying() return self.playing end
  end
  if kind == "Animation" then
    for k in pairs(methods) do if not ANIM[k] then methods[k] = nil end end
    function methods:SetFromAlpha(v) assert(self.what == "Alpha" and type(v) == "number") self.from = v end
    function methods:SetToAlpha(v) assert(self.what == "Alpha" and type(v) == "number") self.to = v end
    function methods:SetDuration(v) assert(type(v) == "number" and v > 0, "duration " .. tostring(v)) self.dur = v end
    function methods:SetStartDelay(v) assert(type(v) == "number" and v >= 0) self.delay = v end
    function methods:SetEndDelay(v) assert(type(v) == "number" and v >= 0) self.rest = v end
    function methods:SetSmoothing(v) assert(v == "IN" or v == "OUT" or v == "IN_OUT" or v == "OUT_IN" or v == "NONE", "smoothing " .. tostring(v)) end
    function methods:SetScaleFrom(x, y) assert(self.what == "Scale" and type(x) == "number" and type(y) == "number") end
    function methods:SetScaleTo(x, y) assert(self.what == "Scale" and type(x) == "number" and type(y) == "number") self.to = x end
    function methods:SetOffset(x, y) assert(self.what == "Translation" and type(x) == "number" and type(y) == "number") self.dx, self.dy = x, y end
    function methods:SetOrder(n) self.order = n end
    function methods:GetTarget() return self.parent.parent end
  end
  return w
end
frames = {}
containersByUnit = {}
local FILTERS = { HARMFUL = 1, HELPFUL = 1, RAID = 1, PLAYER = 1, DISPELLABLE = 1, RAID_PLAYER_DISPELLABLE = 1 }
-- The game's rule for anything handed to an aura button.
local function descends(obj, owner)
  local p = rawget(obj, "parent")
  while p do
    if p == owner then return true end
    p = rawget(p, "parent")
  end
  return false
end
local function validate(obj, owner, kindWanted, allowOwner)
  if type(obj) ~= "table" then error("bad object in function call") end
  if rawget(obj, "secure") then error("bad object (must not be an explicitly protected object)") end
  if not (allowOwner and obj == owner) and not descends(obj, owner) then
    error("bad object '" .. tostring(rawget(obj, "kind")) .. "' in function call (must be the owner or a direct or indirect descendant of owner)")
  end
  if not obj:IsObjectType(kindWanted) then
    error("bad object in function call (expected object type '" .. kindWanted .. "', got '" .. obj:GetObjectType() .. "')")
  end
end
local function adoptGroup(btn, g, list)
  validate(g, btn, "AnimationGroup")
  for _, an in ipairs(g.anims) do
    validate(an, btn, "Animation")
    validate(an:GetTarget(), btn, "Region", true)
  end
  for _, d in ipairs(list) do if d == g then error("Display element has already been added.") end end
  g.frozen = true
  list[#list + 1] = g
end
local function auraButton(container)
  local f = widget("AuraButton", nil, container)
  f.shownAnims, f.assignedAnims = {}, {}
  local mt = getmetatable(f)
  local idx = mt.__index
  local extra = {}
  function extra:SetIcon(tex) validate(tex, self, "Texture") self.iconTex = tex end
  function extra:SetSpellName(fs) validate(fs, self, "FontString") self.nameFs = fs end
  function extra:AddAuraShownAnimation(g) adoptGroup(self, g, self.shownAnims) end
  function extra:AddAuraAssignedAnimation(g) adoptGroup(self, g, self.assignedAnims) end
  function extra:SetTooltipAnchorPoint(point, x, y) assert(point:find("^ANCHOR_")) self.tipAnchor = point end
  mt.__index = function(t, k)
    local m = extra[k]
    if m then return function(self, ...) guard(self, k) return m(self, ...) end end
    if k == "IsShown" then return function(self) guard(self, k) return SECRET end end
    return idx(t, k)
  end
  return f
end
local function passes(slot, aura)
  if not aura.canDispel then return false end -- "HARMFUL|RAID"
  local cf = slot.filters
  if cf then
    if cf.excludeDispelTypes and aura.dispelName and cf.excludeDispelTypes[aura.dispelName] then return false end
    if cf.includeDispelTypes and not (aura.dispelName and cf.includeDispelTypes[aura.dispelName]) then return false end
  end
  return true
end
auras = {}
local function refresh(c)
  INSIDE_GAME = true
  local list = auras[c.unit] or {}
  for _, slot in ipairs(c.slots) do
    local pick
    for _, a in ipairs(list) do if not slot.off and passes(slot, a) then pick = a break end end
    local f = slot.frame
    local was = f.shown
    if pick ~= slot.assigned then
      for _, g in ipairs(f.assignedAnims) do g:Stop() end
      if pick then for _, g in ipairs(f.assignedAnims) do g:Play() end end
      slot.assigned = pick
    end
    if f.iconTex then f.iconTex.texture = pick and pick.icon or nil end
    if f.nameFs and pick then f.nameFs.text = pick.name end
    f.shown = pick ~= nil
    if f.shown and not was then for _, g in ipairs(f.shownAnims) do g:Play() end
    elseif not f.shown then for _, g in ipairs(f.shownAnims) do g:Stop() end end
  end
  INSIDE_GAME = false
end
function gameAuras(unit, list)
  auras[unit] = list
  for _, c in ipairs(containersByUnit[unit] or {}) do refresh(c) end
end
containerFails, NOINIT = false, false
function CreateFrame(kind, name, parent, template)
  if kind == "AuraContainer" then
    if containerFails then error("Unknown frame type: AuraContainer") end
    assert(template == "CustomAuraContainerTemplate")
    local c = widget("AuraContainer", name, parent)
    c.slots, c.unit = {}, "none"
    local mt = getmetatable(c)
    local idx = mt.__index
    local extra = {}
    function extra:SetUnit(u)
      assert(type(u) == "string")
      self.unit = u
      containersByUnit[u] = containersByUnit[u] or {}
      table.insert(containersByUnit[u], self)
    end
    function extra:SetEditModePreviewEnabled(v) assert(type(v) == "boolean") self.preview = v end
    function extra:UpdateAllAuras() refresh(self) end
    function extra:SetAuraSlotEnabled(key, enabled)
      assert(type(enabled) == "boolean", "enabled must be a boolean.")
      for _, s in ipairs(self.slots) do
        if s.key == key then s.off = not enabled; refresh(self) return end
      end
      error("aura slot '" .. tostring(key) .. "' was not found with this key.")
    end
    function extra:AddAuraSlot(key, filter, options)
      assert(type(key) == "string" and key ~= "", "slotKey must be a non-empty string.")
      for comp in filter:gmatch("[^| ]+") do assert(FILTERS[comp], "Unknown aura filter component: " .. comp) end
      for _, s in ipairs(self.slots) do assert(s.key ~= key, "aura slot already exists with this key.") end
      options = options or {}
      local cf = options.candidateFilters
      assert(cf == nil or type(cf) == "table", "candidateFilters must be a table or nil.")
      if cf then
        for k, v in pairs(cf) do
          assert(k == "includeDispelTypes" or k == "excludeDispelTypes", "a candidate filter this stand-in does not know: " .. tostring(k))
          assert(type(v) == "table")
        end
      end
      assert(options.initializeFrame == nil or type(options.initializeFrame) == "function")
      local f = auraButton(self)
      if options.initializeFrame and not NOINIT then
        local ok, e = pcall(options.initializeFrame, f)
        if not ok then swallowed = tostring(e) end
      end
      f.restricted = true
      f.shown = false
      self.slots[#self.slots + 1] = { key = key, frame = f, filters = cf }
      refresh(self)
      return f
    end
    mt.__index = function(t, k)
      local m = extra[k]
      if m then return m end
      return idx(t, k)
    end
    if name then frames[name] = c end
    return c
  end
  local w = widget(kind, name, parent)
  if template and template:find("Secure") then w.secure = true end
  if name then frames[name] = w end
  return w
end
UIParent = widget("Frame")
function hooksecurefunc(obj, name, fn) local old = obj[name]; obj[name] = function(...) old(...); fn(...) end end
DebuffFrame = { auraFrames = {} }
GameTooltip = widget("Frame")
function GetBuildInfo() return "1.60.1", "71091", "Nov 24 2026", 16001 end
C_Secrets = { ShouldAurasBeSecret = function() return combat end }
KNOWN, SPELLID = {}, {}
C_Spell = { GetSpellName = function() return "Other" end,
  GetSpellInfo = function(n) local id = 0; for i = 1, #n do id = id + n:byte(i) * i end; SPELLID[id] = n; return { spellID = id, iconID = 5, name = n } end }
C_SpellBook = { IsSpellKnown = function(id) return KNOWN[SPELLID[id]] == true end }
function GetCVarBool() return true end
CLASS = "PALADIN"
function UnitClass() return CLASS, CLASS end
function UnitExists(u) return u == "player" or u == "party1" end
function GetBindingKey() return nil end
C_UnitAuras = { GetAuraDataByIndex = function(unit, idx, filter)
  if combat then error("Auras cannot be accessed when secret while tainted by 'Meniscus'") end
  local n = 0
  for _, a in ipairs(auras[unit] or {}) do
    if a.canDispel or not filter:find("RAID") then
      n = n + 1
      if n == idx then return a end
    end
  end
end }
printed = {}
local T = { border = { 0.2, 0.2, 0.2 }, textDim = { 0.6, 0.6, 0.6 } }
local MEDIA = "m/"
local GOLD = { 0.9, 0.72, 0.3 }
local ns = { version = "test", modules = {}, commands = {},
  RoundedRect = function(f, sub, inset, radius, r, g, b, a, layer)
    for i = 1, 7 do f:CreateTexture() end
    return function() end
  end,
  CreateText = function(self, parent, size) return parent:CreateFontString() end,
  Print = function(self, ...) printed[#printed + 1] = table.concat({ ... }, " ") end }
NS = ns
local pf = widget("Frame"); pf.healthPill = widget("Frame", nil, pf); pf.unit = "party1"; rawset(pf, "realUnit", false); rawset(pf, "orbSide", false)
local UF = { db = {}, party = { pf } }
UFX = UF
'''

TAIL = r'''
-- What would be seen: for a unit, the slots whose button is shown ("Disease+Poison"), or "".
function seen(unit)
  local out = {}
  for _, c in ipairs(containersByUnit[unit] or {}) do
    for _, s in ipairs(c.slots) do if s.frame.shown then out[#out + 1] = s.key end end
  end
  return table.concat(out, "+")
end
function playing(unit)
  local n = 0
  for _, c in ipairs(containersByUnit[unit] or {}) do
    for _, s in ipairs(c.slots) do
      if s.frame.shown then for _, g in ipairs(s.frame.shownAnims) do if g.playing then n = n + 1 end end end
    end
  end
  return n
end
function slotKeys(unit)
  local out = {}
  for _, c in ipairs(containersByUnit[unit] or {}) do
    for _, s in ipairs(c.slots) do out[#out + 1] = s.key end
  end
  return table.concat(out, ",")
end
-- The words on a slot's face (the first font string made on its button).
function wordsOf(unit, key)
  for _, c in ipairs(containersByUnit[unit] or {}) do
    for _, s in ipairs(c.slots) do
      if s.key == key then
        local w = rawget(s.frame, "words")
        return w and w[1] and rawget(w[1], "text") or nil
      end
    end
  end
end
-- The name the game wrote on a slot's face (the string handed over with SetSpellName).
function nameOf(unit, key)
  for _, c in ipairs(containersByUnit[unit] or {}) do
    for _, s in ipairs(c.slots) do
      if s.key == key then
        local fs = rawget(s.frame, "nameFs")
        return fs and rawget(fs, "text") or nil
      end
    end
  end
end
function pillThere() local p = frames.MeniscusQuickCure; return p ~= nil and p.shown end
function fire(e, unit) EV.scripts.OnEvent(EV, e, unit) runTimers() end
'''

HOOK_NEW = '''    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED",'''
assert CHUNK.count(HOOK_NEW) == 1, 'the events frame was not found: the test needs a look'
CHUNK2 = CHUNK.replace(HOOK_NEW, HOOK_NEW.replace('local ev = CreateFrame("Frame")', 'local ev = CreateFrame("Frame")\n    EV = ev'))

passed, failed = 0, []


def check(case, what, got, want):
    global passed
    ok = (got == want)
    if ok:
        passed += 1
    else:
        failed.append("%s: %s: got %r, wanted %r" % (case, what, got, want))
    if VERBOSE or not ok:
        print("  %s %-58s %r" % ("ok  " if ok else "FAIL", what, got))


def start(cls, spells, setup=''):
    rt = L.LuaRuntime()
    pre = "CLASS = %r\n" % cls + "".join("KNOWN[%r] = true\n" % k for k in spells) + setup + "\n"
    rt.execute(HEAD + CHUNK2 + "\n" + pre + "UF:BuildCure()\nrunTimers()\n" + TAIL)
    return rt


def record(rt):
    t = rt.eval("MinimalUIDB.curecontainer")
    return list(t.values()) if t is not None else []


def aura(kind, can=True):
    return "{ dispelName = %s, icon = 9, name = 'Bad %s', canDispel = %s }" % (("'%s'" % kind) if kind else 'nil', kind or 'Thing', 'true' if can else 'false')


def fight(rt, case, mine, other, words):
    """mine: a kind this character cures; other: one it does not; words: what the pill says beside the debuff's name for `mine`."""
    e = rt.eval
    x = rt.execute
    x("fire('PLAYER_ENTERING_WORLD')")
    check(case, "clean, out of a fight: no casting pill, nothing seen", (e("pillThere()"), e("seen('player')")), (False, ""))
    x("gameAuras('player', { %s }) fire('UNIT_AURA', 'player')" % aura(mine))
    check(case, "afflicted out of a fight: casting pill there, the face seen", (e("pillThere()"), e("seen('player')")), (True, mine))
    check(case, "its light and motes are playing", e("playing('player')") > 0, True)
    check(case, "the face says the debuff's name, and which button", (e("nameOf('player', '%s')" % mine), e("wordsOf('player', '%s')" % mine)), ("Bad " + mine, words))
    x("gameAuras('player', {}) fire('UNIT_AURA', 'player')")
    check(case, "cured: both gone", (e("pillThere()"), e("seen('player')")), (False, ""))
    x("fire('PLAYER_REGEN_DISABLED') combat = true")
    check(case, "a fight starts, clean: casting pill there, nothing seen", (e("pillThere()"), e("seen('player')")), (True, ""))
    x("gameAuras('player', { %s }) fire('UNIT_AURA', 'player')" % aura(mine))
    check(case, "CAUGHT IN THE FIGHT: the face is seen", e("seen('player')"), mine)
    x("gameAuras('player', {}) fire('UNIT_AURA', 'player')")
    check(case, "cured in the fight: gone, casting pill stays", (e("pillThere()"), e("seen('player')")), (True, ""))
    x("gameAuras('player', { %s }) fire('UNIT_AURA', 'player')" % aura(other, False))
    check(case, "a kind it has no cure for: nothing seen", e("seen('player')"), "")
    x("gameAuras('player', { %s }) fire('UNIT_AURA', 'player')" % aura(None, True))
    check(case, "a nameless thing the game calls dispellable: nothing seen", e("seen('player')"), "")
    x("gameAuras('player', {}) gameAuras('party1', { %s })" % aura(mine))
    check(case, "the same on a party member, in the fight: their chip seen", e("seen('party1')"), mine)
    x("gameAuras('party1', {}) fire('SPELLS_CHANGED') fire('GROUP_ROSTER_UPDATE')")
    x("combat = false fire('PLAYER_REGEN_ENABLED')")
    check(case, "the fight ends, clean: no casting pill", (e("pillThere()"), e("seen('player')"), e("seen('party1')")), (False, "", ""))
    x("gameAuras('player', { %s }) fire('UNIT_AURA', 'player') fire('PLAYER_REGEN_DISABLED') combat = true" % aura(mine))
    x("gameAuras('player', {}) fire('UNIT_AURA', 'player')")
    check(case, "one from before a fight runs out in it: gone", (e("pillThere()"), e("seen('player')")), (True, ""))
    x("combat = false fire('PLAYER_REGEN_ENABLED')")
    check(case, "no casting button touched in a fight, no aura button touched in one", (e("blocked"), e("denied")), (0, 0))
    check(case, "nothing swallowed by the game while dressing", e("swallowed"), None)


# 1. A paladin with Purify alone.
case = "paladin, Purify"
rt = start('PALADIN', ['Purify'])
check(case, "the record", record(rt), ["[calm] player: 2 of 2 faces", "[calm] party1: 2 of 2 faces"])
check(case, "slots, for you and for the party member", (rt.eval("slotKeys('player')"), rt.eval("slotKeys('party1')")), ("Poison,Disease", "Poison,Disease"))
check(case, "the casting buttons", tuple(rt.eval(k) for k in ("frames.MeniscusQuickCure.attr.spell1", "frames.MeniscusQuickCure.attr.unit",
      "frames.MeniscusCure1.attr.spell1", "frames.MeniscusCure1.attr.unit")), ("Purify", "player", "Purify", "party1"))
fight(rt, case, "Disease", "Magic", "")
# ... who learns Cleanse in mid-fight: the new slot waits for the fight's end.
rt.execute("fire('PLAYER_REGEN_DISABLED') combat = true KNOWN['Cleanse'] = true fire('SPELLS_CHANGED')")
check(case, "Cleanse learned in a fight: no new slot yet", rt.eval("slotKeys('player')"), "Poison,Disease")
rt.execute("combat = false fire('PLAYER_REGEN_ENABLED')")
check(case, "after the fight: a slot for magic, and Cleanse on the buttons",
      (rt.eval("slotKeys('player')"), rt.eval("frames.MeniscusQuickCure.attr.spell1"), rt.eval("wordsOf('player', 'Disease')")),
      ("Poison,Disease,Magic", "Cleanse", ""))
rt.execute("gameAuras('player', { %s }) fire('UNIT_AURA', 'player')" % aura('Magic'))
check(case, "magic on you now: seen", rt.eval("seen('player')"), "Magic")
rt.execute("gameAuras('player', {}) fire('UNIT_AURA', 'player')")
check(case, "still nothing touched in a fight", (rt.eval("blocked"), rt.eval("denied")), (0, 0))
# ... and the sample.
rt.execute("NS.commands.cure('show disease') NS.commands.cure('show') NS.commands.cure('poison')")
said = list(rt.eval("printed").values())
check(case, "/men cure show: three samples announced", [s.split(',')[0] for s in said[-3:]],
      ["Quick Cure sample (disease)", "Quick Cure sample (disease)", "Quick Cure sample (poison)"])
rt.execute("runTimers() NS.commands.cure('old')")
check(case, "/men cure old: gone, and it says so", (rt.eval("UFX.db.cureOld"), "removed" in list(rt.eval("printed").values())[-1]), (None, True))
check(case, "methods used that this stand-in has no rule for (each must be the game's)", sorted(rt.eval("unknown").keys()),
      ['Button:RegisterForClicks', 'Button:SetPropagateMouseMotion', 'FontString:SetJustifyH', 'FontString:SetShadowColor', 'FontString:SetShadowOffset', 'FontString:SetTextColor',
       'FontString:SetWordWrap', 'Frame:RegisterEvent', 'Frame:RegisterUnitEvent', 'Texture:AddMaskTexture', 'Texture:SetBlendMode',
       'Texture:SetRotation', 'Texture:SetTexCoord', 'Texture:SetVertexColor'])

# 2. A priest: two cures, on the two mouse buttons.
case = "priest, Dispel Magic and Cure Disease"
rt = start('PRIEST', ['Dispel Magic', 'Cure Disease'])
check(case, "the record", record(rt), ["[calm] player: 2 of 2 faces", "[calm] party1: 2 of 2 faces"])
check(case, "left and right", (rt.eval("frames.MeniscusQuickCure.attr.spell1"), rt.eval("frames.MeniscusQuickCure.attr.spell2")), ("Dispel Magic", "Cure Disease"))
check(case, "the chip marks the right-button kind", (rt.eval("wordsOf('party1', 'Disease')"), rt.eval("wordsOf('party1', 'Magic')")), ("R", ""))
fight(rt, case, "Disease", "Poison", "right-click")

# 3. A mage.
case = "mage, Remove Lesser Curse"
rt = start('MAGE', ['Remove Lesser Curse'])
fight(rt, case, "Curse", "Disease", "")

# 4. A paladin with nothing learned yet: nothing made, nothing shown, no errors.
case = "paladin, no cure yet"
rt = start('PALADIN', [])
check(case, "no slots, no record of trouble", (rt.eval("slotKeys('player')"), record(rt), rt.eval("MinimalUIDB.cureErr")), ("", [], None))
rt.execute("fire('PLAYER_REGEN_DISABLED') combat = true")
check(case, "a fight: no casting pill", rt.eval("pillThere()"), False)
rt.execute("combat = false fire('PLAYER_REGEN_ENABLED')")

# 5. Should the game not run the dressing as it makes a button: dressed on the frame it hands back.
case = "the dressing callback not run"
rt = start('PALADIN', ['Purify'], "NOINIT = true")
check(case, "faces made all the same", record(rt)[-1], "[calm] party1: 2 of 2 faces")
rt.execute("gameAuras('player', { %s }) fire('UNIT_AURA', 'player')" % aura('Poison'))
check(case, "and seen", (rt.eval("seen('player')"), rt.eval("playing('player')") > 0), ("Poison", True))

# 6. The display before 0.1.693 is gone (0.1.711): a saved choice of it is dropped, and
#    where no container can be made there is no Quick Cure, said in the record.
case = "the old display chosen in a saved profile"
rt = start('PALADIN', ['Purify'], "UFX.db.cureOld = true")
check(case, "the new one is built all the same, the choice dropped", (rt.eval("EV ~= nil"), rt.eval("UFX.db.cureOld")), (True, None))
case = "a client with no aura containers"
rt = start('PALADIN', ['Purify'], "containerFails = true")
check(case, "nothing built, and said so", (rt.eval("EV ~= nil"), rt.eval("frames.MeniscusQuickCure ~= nil"), len(record(rt)), "no Quick Cure" in record(rt)[-1]), (False, False, 1, True))

print("%d of %d checks passed" % (passed, passed + len(failed)))
for f in failed:
    print("FAILED", f)
sys.exit(1 if failed else 0)
