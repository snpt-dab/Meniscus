"""Aura rows drawn by the game, tried outside the game.

The "Rows drawn by the game" part of Auras.lua is run against a stand-in for
the game's aura containers with GROUPS. The stand-in keeps the rules read in
the game's own code (Blizzard_AuraContainer, build 1.60.1 71091):

  * AddAuraGroup(key, filter, options): the key is a non-empty string and new;
    options may hold only maxFrameCount, templateNames, initializeFrame,
    candidateFilters, sortMethod, sortDirection, layout; layout only
    elementSpacing, lineSpacing, groupSpacing, groupLineSpacing, forceNewLine,
    elementWidth, elementHeight, layoutIndex, each of its type; ten buttons are
    made at once and each is handed to initializeFrame;
  * what is handed to a button (picture, timer, count, kind textures) must be
    that button's child, however deep, and of the right type;
  * a kind texture shows for a harmful aura that has a kind, or for any
    harmful aura with showWithoutDispelType; its colour comes from the map by
    the kind's name or "None", and the colours must answer GetRGBA;
  * groups are laid out by layoutIndex, each up to maxFrameCount;
  * in a fight, any call of ours on a button or under one is refused.

    PYTHONPATH=<folder with lupa> python dist/tests/aura_rows.py [-v]
"""
import io, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
from lupa import lua51 as L

args = [a for a in sys.argv[1:] if a != '-v']
VERBOSE = '-v' in sys.argv[1:]
ADDON = args[0] if args else os.path.join(HERE, '..', '..')
SRC = io.open(os.path.join(ADDON, 'Auras.lua'), encoding='utf-8').read()
A = SRC.index('-- ── Rows drawn by the game')
B = SRC.index('function A:OnInit(db)', A)
B = SRC.rindex('\n', 0, B - 1) + 1
CHUNK = SRC[A:B]

HEAD = r'''
MinimalUIDB = {}
combat = false
function InCombatLockdown() return combat end
denied = 0
INSIDE = false
local KIND = { Frame = { Frame = 1 }, AuraButton = { Frame = 1, Button = 1 }, AuraContainer = { Frame = 1 },
  Cooldown = { Frame = 1, Cooldown = 1 }, Texture = { Texture = 1 }, MaskTexture = { MaskTexture = 1 },
  FontString = { FontString = 1 } }
GAMES = { SetIcon = 1, SetDurationCooldown = 1, SetApplicationCount = 1, AddDispelTypeTexture = 1, SetTooltipAnchorPoint = 1,
  AddAuraGroup = 1, SetUnit = 1, SetFlowLayoutAnchorPoint = 1 }
local function owner(w)
  while w do if w.kind == "AuraButton" then return w end w = w.parent end
end
local function widget(kind, name, parent)
  local w = { kind = kind, name = name, parent = parent, calls = {} }
  return setmetatable(w, { __index = function(t, k)
    if k == "GetParent" then return function(self) return self.parent end end
    if k == "GetFrameLevel" then return function(self) return self.level or 1 end end
    if k == "CreateTexture" then return function(self) return widget("Texture", nil, self) end end
    if k == "CreateMaskTexture" then return function(self) return widget("MaskTexture", nil, self) end end
    if k == "CreateFontString" then return function(self) return widget("FontString", nil, self) end end
    local x = rawget(t, "extra")
    if x and x[k] then
      return function(self, ...)
        if combat and not INSIDE and owner(self) then denied = denied + 1 error("denied: auras are secret") end
        return x[k](self, ...)
      end
    end
    if GAMES[k] then return nil end -- (one of the game's own ways, and this object does not have it)
    if type(k) == "string" and (k:find("^Set") or k:find("^Add") or k:find("^Clear") or k == "Hide" or k == "Show") then
      return function(self, ...)
        if combat and not INSIDE and owner(self) then denied = denied + 1 error("denied: auras are secret") end
        if k == "SetFrameLevel" then self.level = ... end
        if k == "SetSize" then self.w, self.h = ... end
        if k == "SetVertexColor" then self.vc = { ... } end
        if k == "SetTexture" then self.texture = ... end
        self.calls[k] = { ... }
      end
    end
    return nil
  end })
end
local function validate(obj, btn, kind)
  assert(type(obj) == "table" and KIND[obj.kind] and KIND[obj.kind][kind], "wrong kind of thing: wanted a " .. kind)
  local w = obj.parent
  while w and w ~= btn do w = w.parent end
  assert(w == btn, "not a descendant of the aura button")
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGBA = function(s) return s.r, s.g, s.b, s.a end } end
Enum = { CustomAuraButtonDispelTypeTextureStyle = { Border = 0, BorderWithIcon = 1, Icon = 2, PreserveAsset = 3, CustomAsset = 4 } }
NOCOUNT, NOCONTAINER, NOGROUPS = false, false, false
containers = {}
local OPT = { maxFrameCount = "number", templateNames = "table", initializeFrame = "function", candidateFilters = "table",
  sortMethod = "number", sortDirection = "number", layout = "table" }
local LAY = { elementSpacing = "number", lineSpacing = "number", groupSpacing = "number", groupLineSpacing = "number",
  forceNewLine = "boolean", elementWidth = "number", elementHeight = "number", layoutIndex = "number" }
local DOPT = { style = "number", showAlways = "boolean", showWhenHarmful = "boolean", showWhenHelpful = "boolean",
  showWithoutDispelType = "boolean", customDispelAssetMap = "table", customDispelColorMap = "table" }
local function button(c)
  local b = widget("AuraButton", nil, c)
  b.kinds = {}
  local x = {}
  function x:SetIcon(t) validate(t, self, "Texture") self.iconTex = t end
  function x:SetDurationCooldown(cd) validate(cd, self, "Cooldown") self.cd = cd end
  if not NOCOUNT then function x:SetApplicationCount(fs) validate(fs, self, "FontString") self.countFs = fs end end
  function x:AddDispelTypeTexture(t, o)
    validate(t, self, "Texture")
    o = o or {}
    for k, v in pairs(o) do assert(DOPT[k], "unknown option " .. tostring(k)) assert(type(v) == DOPT[k], k .. " of the wrong type") end
    for _, col in pairs(o.customDispelColorMap or {}) do assert(type(col.GetRGBA) == "function", "a colour must be a colour") end
    for _, as in pairs(o.customDispelAssetMap or {}) do assert(type(as.asset) == "string", "an asset must name a file or atlas") end
    for _, d in ipairs(self.kinds) do assert(d.tex ~= t, "Display element has already been added.") end
    table.insert(self.kinds, { tex = t, o = o })
  end
  function x:SetTooltipAnchorPoint(p) assert(type(p) == "string" and p:find("^ANCHOR_"), "bad anchor") self.tip = p end
  b.extra = x
  return b
end
function CreateFrame(kind, name, parent, template)
  if kind == "AuraContainer" then
    if NOCONTAINER then error("Unknown frame type: AuraContainer") end
    assert(template == "CustomAuraContainerTemplate")
    local c = widget("AuraContainer", name, parent)
    c.groups = {}
    local x = {}
    function x:SetUnit(u) assert(type(u) == "string") self.unit = u end
    function x:SetFlowLayoutAnchorPoint(p) assert(type(p) == "string") self.flowAnchor = p end
    if not NOGROUPS then
      function x:AddAuraGroup(key, filter, o)
        assert(type(key) == "string" and key ~= "", "groupKey must be a non-empty string.")
        assert(filter == "HARMFUL" or filter == "HELPFUL", "unknown filter in this stand-in")
        for _, g in ipairs(self.groups) do assert(g.key ~= key, "aura group already exists with this key.") end
        o = o or {}
        for k, v in pairs(o) do assert(OPT[k], "unknown option " .. tostring(k)) assert(type(v) == OPT[k], k .. " of the wrong type") end
        for k, v in pairs(o.layout or {}) do assert(LAY[k], "unknown layout option " .. tostring(k)) assert(type(v) == LAY[k], k .. " of the wrong type") end
        local max = o.maxFrameCount or math.huge
        assert(max == math.huge or (max >= 0 and max == math.floor(max)), "maxFrameCount must be a non-negative integer or infinity.")
        local g = { key = key, harmful = filter == "HARMFUL", max = max, index = (o.layout or {}).layoutIndex or (#self.groups + 1), frames = {} }
        for i = 1, 10 do
          local b = button(self)
          if o.initializeFrame then o.initializeFrame(b) end
          g.frames[i] = b
        end
        table.insert(self.groups, g)
      end
    end
    c.extra = x
    containers[name] = c
    return c
  end
  return widget(kind, name, parent)
end
-- What the game would draw: a list of "kind/ring colour/emblem" in order.
function draw(name, auras)
  INSIDE = true
  local c = containers[name]
  local gs = {}
  for _, g in ipairs(c.groups) do gs[#gs + 1] = g end
  table.sort(gs, function(a, b) return a.index < b.index end)
  local out = {}
  for _, g in ipairs(gs) do
    local n = 0
    for _, a in ipairs(auras) do
      if a.harmful == g.harmful and n < g.max then
        n = n + 1
        local b = g.frames[n]
        local bits = { a.harmful and "debuff" or "buff", b.iconTex and "pic" or "NOPIC", b.cd and "timer" or "NOTIMER",
                       b.countFs and "count" or "NOCOUNT" }
        for _, d in ipairs(b.kinds) do
          local o = d.o
          local show = o.showAlways or (a.harmful and o.showWhenHarmful ~= false and (a.dispelName ~= nil or o.showWithoutDispelType))
          if show then
            local col = o.customDispelColorMap and o.customDispelColorMap[a.dispelName or "None"]
            local as = o.customDispelAssetMap and o.customDispelAssetMap[a.dispelName or "None"]
            bits[#bits + 1] = (as and as.asset:match("([%w_]+)%.tga$") or "tex") .. (col and string.format("@%.2f", (col:GetRGBA())) or "")
          end
        end
        out[#out + 1] = table.concat(bits, " ")
      end
    end
  end
  INSIDE = false
  return table.concat(out, " | ")
end
local T = { border = { 0.2, 0.2, 0.2, 1 } }
ns = { Theme = T, modules = { UnitFrames = { target = widget("Frame", "target") } },
       SetFont = function() end }
ns.modules.UnitFrames.SeatTargetAuras = function(self) seated = (seated or 0) + 1 end
local A = { db = {} }
AM = A
local MEDIA = "Interface/AddOns/Meniscus/Media/"
local ROUND = MEDIA .. "rounded.tga"
local DISPEL = { Magic = { 0.25, 0.55, 1.00 }, Curse = { 0.65, 0.30, 0.95 }, Disease = { 0.75, 0.52, 0.22 }, Poison = { 0.30, 0.80, 0.30 } }
local DEBUFF = { 0.80, 0.26, 0.26 }
local function mask(owner) return owner:CreateMaskTexture() end
'''

passed, failed = 0, []


def check(case, what, got, want):
    global passed
    if got == want:
        passed += 1
    else:
        failed.append("%s: %s: got %r, wanted %r" % (case, what, got, want))
    if VERBOSE or got != want:
        print("  %s %-60s %r" % ("ok  " if got == want else "FAIL", what, got))


def start(setup=''):
    rt = L.LuaRuntime()
    rt.execute(HEAD + setup + "\n" + CHUNK + "\nA:BuildLiveTarget()\n")
    return rt


def notes(rt):
    t = rt.eval("MinimalUIDB.liverows")
    return [t[i] for i in range(1, len(t) + 1)] if t else []


AURAS = """{ { harmful = false }, { harmful = true, dispelName = 'Magic' }, { harmful = true }, { harmful = false },
  { harmful = true, dispelName = 'Poison' } }"""

case = "target"
rt = start()
check(case, "a container on the target, seated by the unit frames", (rt.eval("AM.liveTarget ~= nil"), rt.eval("seated")), (True, 1))
check(case, "20 icons dressed, nothing refused", notes(rt), ["[calm] target: 20 icons dressed"])
check(case, "debuffs first, ring by kind, emblem only with a kind; then buffs", rt.eval("draw('MeniscusTargetAuras', %s)" % AURAS),
      "debuff pic timer count tex@0.25 tex@0.05 micro_dispel_magic@0.25 | debuff pic timer count tex@0.80 | "
      "debuff pic timer count tex@0.30 tex@0.05 micro_dispel_poison@0.30 | buff pic timer count | buff pic timer count")
many = "{ " + ", ".join(["{ harmful = true }"] * 12 + ["{ harmful = false }"] * 12) + " }"
check(case, "no more than eight of each", rt.eval("draw('MeniscusTargetAuras', %s)" % many).count("|") + 1, 16)
rt.execute("combat = true")
check(case, "in a fight a button is closed to us",
      rt.eval("(function() local b = containers.MeniscusTargetAuras.groups[1].frames[1]; return (pcall(b.SetSize, b, 5, 5)) end)()"), False)
check(case, "and the game still draws", rt.eval("draw('MeniscusTargetAuras', %s)" % AURAS).count("|") + 1, 5)

case = "a way is missing"
rt = start("NOCOUNT = true")
check(case, "the refusal is noted once, the row stands", (rt.eval("AM.liveTarget ~= nil"), notes(rt)),
      (True, ["[calm] target: 20 icons dressed; REFUSED count: no such way"]))
check(case, "and draws without the count", rt.eval("draw('MeniscusTargetAuras', '{ { harmful = false } }')".replace("'{", "{").replace("}'", "}")),
      "buff pic timer NOCOUNT")

case = "no container"
rt = start("NOCONTAINER = true")
check(case, "the old way stands", (rt.eval("AM.liveTarget"), len(notes(rt)), notes(rt)[0].endswith(": the old way")), (None, 1, True))
rt = start("NOGROUPS = true")
check(case, "a container without groups: the old way", (rt.eval("AM.liveTarget"), notes(rt)[0].endswith(": the old way")), (None, True))

case = "by choice"
rt = start("A.db.liveOld = true")
check(case, "/men buffs old: nothing made", (rt.eval("AM.liveTarget"), rt.eval("containers.MeniscusTargetAuras")), (None, None))

print("%d of %d checks passed" % (passed, passed + len(failed)))
for f in failed:
    print("FAILED " + f)
sys.exit(1 if failed else 0)
