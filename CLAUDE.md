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
- **Version control:** this folder is a git repository (branch `main`; first commit is the 2026-11-10 baseline) with a public GitHub remote, `origin` = github.com/snpt-dab/Meniscus (since 2026-11-12; history was rewritten that day to use the GitHub no-reply email and `<ACCOUNT>` for the WoW account folder, so keep personal details out of commits and this file). The GitHub CLI is at `/c/Program Files/GitHub CLI/gh.exe` (not on bash's PATH). Push after committing; if the push is blocked by the session's permission check, say so and give the user `git push` to run. Commit after every change, without asking (the user said to commit at will), with a message saying what changed for them. `git diff` / `git log -p <file>` answer "what changed", `git checkout <commit> -- <file>` brings an old version back. Tester zips are ignored (`dist/*.zip`); rebuild with `python dist/build.py`. **Run `python dist/build.py` before every commit:** it stamps the version (`0.1.<commit number>`) into Meniscus.toc and README.txt, which the double-click updater (`Update Meniscus.bat` / `Update.ps1`, downloads `main` from GitHub) and the in-game newer-version notice (Core.lua, addon messages) compare. Then commit and push; testers only get what is pushed.
- **Line endings are LF.** Patch scripts must write with `open(p, 'w', encoding='utf-8', newline='
')`; plain `open(p, 'w')` on Windows writes CRLF and makes every line show as changed.

## When to ask for the bigger model
The user runs day-to-day sessions on Opus and switches to Fable for harder work. You cannot switch models yourself. If you are not Fable and one of these is true, stop and say so in one or two lines ("This is one for Fable: <reason>"), before doing the work, and let the user decide:
- The request is a performance pass, a cleanup / refactor pass across files, or a new module or Blizzard-window takeover.
- The fix touches secure frames, taint, or combat-lockdown behaviour beyond following an existing pattern in this file.
- A bug has no logged error and no obvious cause after one round of looking (a probe is fine to add first).
- Two attempts at the same fix have failed. Do not make a third guess; say what was tried and ask.
- You would have to guess at how more than one module interacts and cannot settle it by reading the code.

Small, well-specified changes (move, restyle, reword, fix a visible glitch with a clear cause) do not need it. Don't ask out of caution.

## Module skeleton
```lua
local _, ns = ...
local T = ns.Theme
local M = ns:NewModule("Name", { enabled = true, ... })  -- defaults -> per-profile db
function M:OnInit(db) ... end                              -- runs at PLAYER_LOGIN, pcall'd
ns.commands.name = function(lowerRest, rawRest) ... end    -- /men name
```
- Settings go into `PAGES` in Panel.lua; set `reload = true` if the setting needs a reload.
  - Pages are by what the player is thinking about (General, Console, Frames, Buffs, Bars, Combat, Bags and loot, Quests and map, Professions, Chat and notices, Windows, Debug), not by which module holds the code. Put a new switch where someone would look for it; twelve pages is what the sidebar holds.
  - Keep a note to one short line (about 60 characters): it is cut off before the control.
  - The panel's search matches a setting's label, note, group, page, and its entry in `KEYS` (Panel.lua): give a new setting a `KEYS` line with the other words people would type for it. `ALSO` is the thesaurus (a typed word also stands for these).
- Add a help line in Panel.lua for each new slash command.

## Shared building blocks (use these, don't re-roll)
- **Theme.lua**
  - `ns:SetFont(fs, size, flags, bold)` registers the font string for live font switching, so all text goes through it.
  - `ns:CreateText(parent, size, color)`.
  - `ns.RoundedRect(f, sublevel, inset, radius, r,g,b,a, layer)` returns a paint function `(r,g,b,a)`.
  - `ns:CreatePillBar(parent, w, h)`: the w:h ratio must be 8:1, 16:1 or 32:1, or the caps distort.
  - `ns.TweenColor(key, paint, r,g,b,a, dur)` and `ns.EasePaint(b, paint)`. Pills use `b.paint = ns.EasePaint(b, ns.RoundedRect(...))` and set `b.hover` in OnEnter/OnLeave.
  - `ns.TipAnchor(owner)`: every tooltip in our windows uses it. It puts the tooltip beside the window the owner is in (right side, or left when there is more room), level with the owner; outside our windows it falls back to the player's default anchor.
  - `ns.AddCompare(tip, itemLink)`: appends stat gains / losses against the equipped piece (quest rewards, merchant).
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
- Pinned windows (`PINNED`, the bags on the right): one fixed dock, never moved across, never closed to make room, not closed by the map; other windows keep out of that dock while one is open.
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
- **Minimap mask:** `Minimap:SetMaskTexture` drew nothing with the game's own round masks (`TempPortraitAlphaMask`, `Textures/MinimapMask`); only our own TGA works (white, shape in the alpha: `Media/rounded.tga`, `Media/circle.tga`). New media files show up after a plain /reload (confirmed 2026-11-22 with a new emblem); only new .lua files need the client restarted.
- **Small icons:** draw them as vectors in `dist/icons.py` and render to `Media/*.tga` (white, shape in alpha, tinted with SetVertexColor). In-game Lines and masked discs look rough below ~16 px. Check the result by rendering a contact sheet and looking at it. Re-rendered and brand-new textures both show up after a plain /reload (confirmed).
- **Syntax trap:** `obj:Method and x` without parentheses is a syntax error that kills the file.
- **Combat log lines:** each line reaches an addon as a ticket (`|Ky435|k`) that SetText draws but nothing can read. `Media/digits-*.ttf` (made by `dist/digitfont.py`, by hand, no font library) draws only the numerals of whatever it is given, so a line shows as its amount: combat numbers use that for hits the game reports no amount for (Nameplates.lua, "A number from a log line's own text"). `MinimalUIDB.digitface` says how each make of the typeface measured in game and which is in use, `linewide` whether lines drew as numerals. Measured in game 0.1.648: blank characters cost about a tenth of a pixel each (fine), but a BLANK glyph's wide advance is ignored (12 em came out as a pixel or two), so 0.1.649 ships makes whose wide bracket carries a speck of ink (`-r`, `-q`) and picks the first that measures right; if none does, a one-time card asks the player whether a clear-coloured string still draws its coloured part (the other way to hide what follows the amount). Not yet confirmed in game.
- **Combat numbers outside the game:** `dist/tests/fct_scenarios.py` plays kill and group cases at Nameplates.lua inside a stand-in for the game (`dist/tests/mock.lua`). Run it after touching the pairing code: a runtime error in the UNIT_COMBAT handler costs every number.
- **Instances hide what a creature is** (name, GUID, kind), but not: the experience line's name, a looted corpse's GUID, a target's level and rank, a boss's name at ENCOUNTER_START. The bestiary keeps a dungeon creature under a made-up id below zero until its real one is learned from a corpse and named outside (Bestiary.lua, "In a dungeon"). `dist/tests/bestiary_book.py` runs the bestiary's start-up tidy-ups and a short dungeon visit on a copy of the local saved book; run it before shipping a change to how the book is written.

## Crafted upgrades between characters (Alts.lua)

- Full sheet of another character of yours (0.1.672): `Inspect:OpenSnapshot(who, ch)` shows a saved record in the inspection window (`I.snap`; tiles from saved links, card through `FillOtherCard` with unit "none"). The figure: this client has NO SetCustomRace (neither on DressUpModel nor on a ModelScene actor; measured 0.1.674). Since 0.1.675 it is stood up by one of several ways (your own unit when race and sex match; `SetDisplayInfo(body)`; a ModelScene actor by display id; the model file), the body number being the character’s measured `di` (Alts.lua `measureFigure`) or the classic table `RACE_BODY` (a guess here). Show the window BEFORE setting a model up, and dress after it loads. `MinimalUIDB.dolldiag` records each way; a pill over the figure steps through them (`db.figurePick`). Which way really dresses is not settled yet. Resistances saved as `rs`.
- Roster tab (Character.lua `rosterData`, 0.1.670): every character on file with its snapshot sheet. The record also holds r race, z zone, m money, hp, mp, pt power token, ar armour, xp percent, rx rested, s = five attributes, pr = { name, rank, max, ... }. `A.Roster()` lists them; `A.ReadNow()` re-reads this character. Realm comes from `ns:RealmName()` only.
- Each character leaves its gear (at logout and on gear changes) and its gear recipes (while a profession window is open) in `MinimalUIDB.roster[realm][name]`. `ns.Alts.ForMe()` answers "what could any of my characters craft that beats what I wear" (character window: a disc on the slot, the Crafts tab); `ns.Alts.ForAlts(item)` answers "which other character is this an upgrade for" (professions window: arrow on the row, the "For alts" pill). Both judge with `ns.JudgeUpgrade(link, who)` in Theme.lua, the same code as the bag arrows (`who` nil = you now, or a roster entry).
- Character names live only in the saved file: never copy roster names into commits, notes or replies. `/men alts` lists who is on file; `MinimalUIDB.altdiag` says how many weapon skills could be read.

## Performance
- Never build tables in recurring code. `{ f:GetChildren() }` in a polled walk was the main source of memory churn. Use `ns.Kids(f, depth)` / `ns.Regs(f, depth)` (Theme.lua: reusable buffers, one per recursion depth) and hoist constant lists out of loops.
- Prefer events over polling. Polling loops (deep skin 1s, damage meter 0.5s) are the known hot spots for the optimization pass. The menu watcher only runs while a menu is open (0.1s, no tables).
- For UIParent (hundreds of children) neither `{ GetChildren() }` nor `select(i, ...)` per child: take the varargs eight at a time with a tail call (Skins.lua `checkTop`).
- Hidden frames should stop their OnUpdate. TweenColor already snaps when its frame is hidden.
- Check new recurring work with `/men perf`.

## Buffs: ring or Quick Buff (QuickBuff.lua)

The user's rule (2026-11-25): a buff goes in ONE of the two, by how long it lasts. Under `LONG_BUFF` (300 s): a recast ring (`RECAST`; seals, Slice and Dice, shields, Battle Shout). `LONG_BUFF` or more: the Quick Buff pill (`CLASS_BUFFS`, blessings). Role-only buffs (Righteous Fury) are `optin = true` in `CLASS_BUFFS`: offered only once the character has cast it (`MinimalUIDB.keepBuff[CharKey]`), and no longer after the buff is clicked off with time left. In Forever a seal lasts its full 30 s whatever is judged; nothing ends a ring early.

## Quick Cure (UnitFrames.lua `BuildCure`)

The user's layout (2026-11-25): a small chip beside each PARTY member's bar (their auras start past it: `f.cureSlot`), and for YOU a pill left of the cast bar. Seen only while there is something curable.

The pill SAYS THE DEBUFF'S NAME, not the cure's (the user, 2026-11-25: what is on the unit is the helpful thing). The game writes it (`SetSpellName(fontString)`); it can't be measured and the pill can't be resized in a fight, so the pill has a fixed width (170, +52 when a second cure sits on the right button, marked by a small "right-click") and long names are cut.

**Since 0.1.693 what is SEEN is drawn by the game, not by us.** For you and each party member: an `AuraContainer` (`MeniscusCureAuras`, `MeniscusCureAuras<i>`) with one slot per kind you hold a cure for (`AddAuraSlot(kind, "HARMFUL|RAID", { candidateFilters = { includeDispelTypes = { [kind] = true } }, initializeFrame = dress })`). Each slot's aura button is dressed once as the whole face for that kind (`cureFace` ring / fill / words / picture, `cureFaceFx` light and motes as animation groups, `cureAdopt` hands picture and groups to the game). Over each lies the unseen secure casting button (`MeniscusQuickCure`, `MeniscusCure<i>`; left / right click = the two cures): there for the whole of every fight, and out of a fight only while you are afflicted (readable then). `/men cure show [kind]` plays the same faces on plain frames (a look without a debuff); `/men cure old | new` switches to `BuildCureOld`, the display before 0.1.693 (drawn by us, blind to what is caught in a fight), which is also the fallback where no container can be made. Delete `BuildCureOld`, `cureLook` and `cureMotes` once the new one is confirmed in game.

**The game's rules for aura buttons** (from its own source, see below; not from trying):
- A slot shows the first aura passing its filter string and candidate filters (`includeDispelTypes` / `excludeDispelTypes`: maps keyed by "Magic", "Curse", "Disease", "Poison"; also `includeSpellIDs`, `maxDuration`, `isBossAura`, ...). Slots are independent; they are anchored by hand. Groups (`AddAuraGroup`) lay out many buttons themselves.
- What is handed to a button must be the button's child, however deep, and of the right type: `SetIcon(texture)`, `AddDispelTypeTexture(texture, options)` (maps `customDispelColorMap` / `customDispelAssetMap` keyed by kind name or "None"; styles in `Enum.CustomAuraButtonDispelTypeTextureStyle`), `SetDispelTypeText`, `SetSpellName`, `SetDurationCooldown` / `SetDurationText` / `SetDurationBar`, `SetApplicationCount`, `SetCasterName`, `AddAuraShownAnimation(group)` (played when shown, stopped when hidden), `AddAuraAssignedAnimation(group)` (replayed for each new aura). An animation's target must be the button or its child; nothing can be added to a group after it is handed over.
- The button is shown with a hidden yes-or-no: `IsShown()` is hidden always, so nothing can be driven from it. While auras are secret (a fight) EVERY addon call on an aura button is refused (`DenyTaintedAccessWhenAurasAreSecret`): dress it in `initializeFrame`, which runs before that; touch it later only out of a fight, under pcall. No script of ours runs on it or its children.
- The game colours a dispel texture with `SetVertexColor(r, g, b, a)`, which resets its alpha: anything it colours that must fade goes in a child frame whose alpha is animated.
- Aura buttons and their children always pass mouse and key input on (`AlwaysPropagateInput`); our casting button lies over them anyway, with `SetPropagateMouseMotion(true)` (settable out of a fight only) so the button under it still shows its own tooltip.
- Anything ANCHORED TO an aura button takes on its "no layout scripts" aspect, and its children take on "no scripts at all". So the aura button is anchored to our casting button, never the other way round, and nothing of ours that needs a script is parented or anchored to one.
- The game documents every forbidden aspect and secret aspect in its own files (`Blizzard_APIDocumentationGenerated/ForbiddenAspectConstantsDocumentation.lua`, `SecretAspectConstantsDocumentation.lua`, `Simple*APIDocumentation.lua` for which widget methods exist on this build).
- Animations here: every animated thing has ONE fade, ending at its strength at rest (no reliance on what a finished or not-yet-started animation does); every looped group is padded to `CURE_PERIOD` with an end delay so light and motes keep one clock.
- `dist/tests/cure_container.py` runs the cure code against a stand-in for the game that keeps these same rules (what may be handed over, refusal in a fight, casting buttons locked in a fight). Run it after touching the cure code.

**Auras in a fight (measured 0.1.682-690, and the game's own notes).** Forever 1.60 carries the 12.1 aura lockdown: while auras are secret, every call that hands aura data to addon code raises "Auras cannot be accessed when secret while tainted" (by index, slot or instance id, any filter; the tooltip calls too), the UNIT_AURA payload is wholly hidden, and the game's own aura buttons are forbidden to addon code. A debuff's kind can NOT be read in a fight: do not look for another way to read it. Have it SHOWN (above). The same road is the answer for the aura rows that go blind in a fight (Auras.lua) and for a true seal timer.

**Where the client's own code is.** The game's interface source for this exact build is public: github.com/Gethe/wow-ui-source, branch `forever` (commit messages carry the build, e.g. "1.60.1 (71091)"; compare with `GetBuildInfo()`). Read a file with `curl -s https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/<addon>/<file>`; list files through `https://api.github.com/repos/Gethe/wow-ui-source/git/trees/forever?recursive=1`. warcraft.wiki.gg documents the same flavour (`Patch_1.60.1/API_changes`, `Secret_Values`). READ THE SOURCE before probing in game or concluding the game cannot do something: five probe rounds on the cure pill, each costing the user a fight, found less than ten minutes of reading did.
