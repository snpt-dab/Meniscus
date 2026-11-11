# Meniscus — working notes

Flat-dark, single-accent, pill/rounded UI overhaul for **WoW: Forever** (retail-style API, TOC 16001, Lua 5.1).
SavedVariables: `_forever_/WTF/Account/<ACCOUNT>/SavedVariables/Meniscus.lua` (MinimalUIDB).

## Workflow
- The user tests in game and reports only problems. Don't send "testing now" turns; say what to check.
- Suggest a better approach when there is one (performance, taint, API limits, UX). Keep it to a sentence or two.
- **Syntax-check every edited file.** A load error kills the whole file silently, and the user sees "unknown command" or a dead feature. Lupa (Lua 5.1) is installed in the session scratchpad `pylib`. If that folder is gone, reinstall with `pip install --target <dir> lupa`.
  ```
  PYTHONPATH=<pylib> python -c "from lupa import lua51 as L; rt=L.LuaRuntime(); f=rt.eval('function(s,n) local f,e=loadstring(s,n) return f and \"ok\" or e end'); print(f(open('X.lua',encoding='utf-8').read(),'X.lua'))"
  ```
- **New .lua files** must be added to `Meniscus.toc` in dependency order (Core, Theme, Perf, Shell first). They need a full client restart, not just /reload.
- **Runtime errors:** Core.lua logs unique errors and ADDON_ACTION_BLOCKED/FORBIDDEN into `MinimalUIDB.errors`. Read the SavedVariables file after the user reloads, or use `/men errors` in game.
- **Probes** (Probe.lua and others) dump client state when an API or frame is unknown, so we don't have to guess:
  - `/men probe`, `uiprobe`, `menuprobe`, `keyprobe [KEY]`, `countprobe`, `guildprobe`, `dmprobe`
  - Add a probe instead of guessing at Forever's API.
- Paths in Lua strings use forward slashes, because bash heredocs eat backslashes.
- **Version control:** this folder is a git repository (local only, branch `main`; first commit is the 2026-11-10 baseline). Commit after every change, without asking (the user said to commit at will), with a message saying what changed for them. `git diff` / `git log -p <file>` answer "what changed", `git checkout <commit> -- <file>` brings an old version back. Tester zips are ignored (`dist/*.zip`); rebuild with `python dist/build.py`.
- **Line endings are LF.** Patch scripts must write with `open(p, 'w', encoding='utf-8', newline='
')`; plain `open(p, 'w')` on Windows writes CRLF and makes every line show as changed.

## Module skeleton
```lua
local _, ns = ...
local T = ns.Theme
local M = ns:NewModule("Name", { enabled = true, ... })  -- defaults -> per-profile db
function M:OnInit(db) ... end                              -- runs at PLAYER_LOGIN, pcall'd
ns.commands.name = function(lowerRest, rawRest) ... end    -- /men name
```
- Settings go into `PAGES` in Panel.lua; set `reload = true` if the setting needs a reload.
- Add a help line in Panel.lua for each new slash command.

## Shared building blocks (use these, don't re-roll)
- **Theme.lua**
  - `ns:SetFont(fs, size, flags, bold)` registers the font string for live font switching, so all text goes through it.
  - `ns:CreateText(parent, size, color)`.
  - `ns.RoundedRect(f, sublevel, inset, radius, r,g,b,a, layer)` returns a paint function `(r,g,b,a)`.
  - `ns:CreatePillBar(parent, w, h)`: the w:h ratio must be 8:1, 16:1 or 32:1, or the caps distort.
  - `ns.TweenColor(key, paint, r,g,b,a, dur)` and `ns.EasePaint(b, paint)`. Pills use `b.paint = ns.EasePaint(b, ns.RoundedRect(...))` and set `b.hover` in OnEnter/OnLeave.
  - `ns.TipAnchor(owner)`: every tooltip in our windows uses it, never a pinned anchor.
  - `ns.Kill(obj)`, `ns.Pixel()`.
  - `ns.Pill(parent, label, onClick, opts)`: the one pill button (opts: h, font, pad, minW, ring, dimIdle, primary; state `b.on`/`b.selected`/`b.primary`; `b:SetLabel`, `b:Repaint`). Each window keeps a thin local `pill()` wrapper with its own opts.
  - `ns.Call(fn, ...)`: pcall that returns the results and allocates nothing. Use `local call = ns.Call`; never `{ pcall(...) }`.
- **Shell.lua**
  - `ns:CreateShell(win, {onClose})`: the header band (noise texture, ring/avatar, title, subtitle, chip). `ns.SHELL_H` = 92.
  - Shell methods:
    - SetTitle, SetSubtitle, SetChip, SetRing, SetIcon, SetUnit(unit, talk), SetAttitude(unit), SetSubtitleWidth.
    - `Lift(...)`: controls on the band must call it, or the band paints over them.
  - `ns:CreateFooter(win, h)`: a footer band (hairline on top).
- **Skins.lua:** `ns.SkinWindow(f, opts)` (opts.deep for deep passes), `ns.SkinButton`, `ns.SetButtonPrimary(b, on)`.
- **Perf.lua:** wrap recurring jobs in `ns.Timed("label", fn, ...)` so `/men perf report` attributes their cost.

## Window recipe (Dialogs.lua is the reference)
- Header shell, then content in rounded cards, then a footer band with pills.
- Leave/back actions (Goodbye, Decline, Back, Close) go on the footer's left. Primary actions go on the right; the main one is light, the others dark.
- NPC windows color the ring/chip by attitude (`SetAttitude`). Our own windows use an identity color.
- Pills: hairline ring, eased hover, dark text on light pills. A stateful button names the action it will perform. No accent-fill "on" state.
- Unit frame names are dark over the bar's fill and light over its empty track (split at the fill edge, like the value).
- Effects: no glow bleed or halos, and no hard edges (taper or fade instead).

## Taking over Blizzard windows
- **Ghost pattern:** use it when hiding Blizzard's frame would end the interaction (Gossip, Quest, Merchant, Trainer, Inspect, Mail, Bank, ProfessionsFrame while a trade skill is open). Keep the frame shown with alpha 0, scale 0.001 and no mouse; our window drives the API. Sync visibility from the ghost frame's OnShow/OnHide, not from event order.
- **Plain windows:** post-hook the toggle function (`hooksecurefunc`). Add an OnShow fallback on Blizzard's frame that hides it and opens ours. Offer a bypass command (`/men blizzchar`, `/men prof blizz`, ...).
- Never reparent Blizzard containers that Edit Mode manages; set alpha 0 and turn the mouse off instead.
- Before hiding a Blizzard unit frame, call UnregisterAllEvents on it recursively.
- Restyle in place only by recoloring. Never replace atlas art that Blizzard reads back: SetColorTexture on a MinimalScrollBar thumb broke the guild roster.

## Window docks (Windows.lua)
- Every window, ours or Blizzard's, is listed by global name in `MANAGED` with a side (left / right / center). The manager hooks show / hide, seats the window in its usual dock if free (else the other one; with both full it replaces the window open longest), and owns Esc for our windows (one per press, through `MeniscusEscProxy`; our names are taken out of UISpecialFrames).
- A new window: add its name to `MANAGED`. Don't position it yourself beyond a first-time default; the dock overrides it on show.
- Protected windows (bags, Blizzard panels) are not moved or hidden in combat; the work is queued until PLAYER_REGEN_ENABLED.

## Secure code and combat
- Anything that casts, uses items or targets must be a SecureActionButton or SecureUnitButton. Use wildcard attributes (`*type1`, `*type2`) so modifiers and Click Casting work, plus `RegisterForClicks("AnyDown","AnyUp")`. Keep both edges: with only `"AnyUp"`, the click never fired on Forever.
- In combat, don't Show/Hide, change attributes on, or lay out protected frames. Use alpha instead, or defer to `PLAYER_REGEN_ENABLED`. Build secure buttons at init.
- Bag tiles are secure because using items from addon buttons is blocked.

## Forever API pitfalls
- **Secret values** (health, names, some sizes): pass them straight to StatusBar, SetText or SetTimerDuration. Do no math or comparisons on them. Guard with `issecretvalue`. Use C_CurveUtil curves for colors.
- **Missing APIs:** GetSpellInfo, GetItemInfo, MouseIsOver and global container functions. Use C_Spell, C_Item, `frame:IsMouseOver()` and C_Container.
- **OnUpdate hooks:** Blizzard wipes `HookScript("OnUpdate")` on some frames (GameMenuFrame, menus). Tick from a child frame of ours with SetScript.
- **Visibility checks:** `Texture:GetAlpha()` includes vertex alpha. Check `IsForbidden()` before touching UIParent children.
- **Menus:** the Menu compositor recycles row textures, so re-decide styling on every open. Never call SetFont on menu rows.
- **Recoloring:** to recolor a texture whose alpha you animate, use SetVertexColor. Re-calling SetColorTexture left the XP flash stuck fully lit.
- **Fading a texture:** `tex:SetAlpha()` on the orb swirl texture did nothing visible (GetAlpha still read the vertex alpha). Fade through the vertex color's alpha, or put the texture in a holder frame and set the frame's alpha.
- **Clipping:** `SetClipsChildren` reliably clips child frames. A texture reparented onto the clip frame itself stayed unclipped, so put clipped textures on a child frame of the clip.
- **Minimap mask:** `Minimap:SetMaskTexture` drew nothing with the game's own round masks (`TempPortraitAlphaMask`, `Textures/MinimapMask`); only our own TGA works (white, shape in the alpha: `Media/rounded.tga`, `Media/circle.tga`). New media files need a full client restart, like new .lua files.
- **Small icons:** draw them as vectors in `dist/icons.py` and render to `Media/*.tga` (white, shape in alpha, tinted with SetVertexColor). In-game Lines and masked discs look rough below ~16 px. Check the result by rendering a contact sheet and looking at it. Re-rendering an existing texture shows up after a plain /reload (confirmed); only a brand-new file needs the client restarted.
- **Syntax trap:** `obj:Method and x` without parentheses is a syntax error that kills the file.

## Performance
- Never build tables in recurring code. `{ f:GetChildren() }` in a polled walk was the main source of memory churn. Use `ns.Kids(f, depth)` / `ns.Regs(f, depth)` (Theme.lua: reusable buffers, one per recursion depth) and hoist constant lists out of loops.
- Prefer events over polling. Polling loops (deep skin 1s, damage meter 0.5s) are the known hot spots for the optimization pass. The menu watcher only runs while a menu is open (0.1s, no tables).
- For UIParent (hundreds of children) neither `{ GetChildren() }` nor `select(i, ...)` per child: take the varargs eight at a time with a tail call (Skins.lua `checkTop`).
- Hidden frames should stop their OnUpdate. TweenColor already snaps when its frame is hidden.
- Check new recurring work with `/men perf`.
