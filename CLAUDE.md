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
  - `/men probe`, `keyprobe [KEY]`, `under`, `artprobe`, `winprobe`, `deepprobe <Frame>`, `combatprobe`, the recorder. (0.1.713: the probes for settled questions were deleted, about 1,150 lines; tag `stage/before-probes-removed`.)
  - Read the game's source first; add a probe only for what the source cannot say (what the client does at run time, what is hidden in a fight).
- Paths in Lua strings use forward slashes, because bash heredocs eat backslashes.
- **Version control:** this folder is a git repository (branch `main`; first commit is the 2026-11-10 baseline) with a public GitHub remote, `origin` = github.com/snpt-dab/Meniscus (since 2026-11-12; history was rewritten that day to use the GitHub no-reply email and `<ACCOUNT>` for the WoW account folder, so keep personal details out of commits and this file). The GitHub CLI is at `/c/Program Files/GitHub CLI/gh.exe` (not on bash's PATH). Push after committing; if the push is blocked by the session's permission check, say so and give the user `git push` to run. Commit after every change, without asking (the user said to commit at will), with a message saying what changed for them. `git diff` / `git log -p <file>` answer "what changed", `git checkout <commit> -- <file>` brings an old version back. Tester zips are ignored (`dist/*.zip`); rebuild with `python dist/build.py`. **Run `python dist/build.py` before every commit:** it stamps the version (`0.1.<commit number>`) into Meniscus.toc and README.txt, which the double-click updater (`Update Meniscus.bat` / `Update.ps1`, downloads `main` from GitHub) and the in-game newer-version notice (Core.lua, addon messages) compare. Then commit and push; testers only get what is pushed.
- **Line endings are LF.** Patch scripts must write with `open(p, 'w', encoding='utf-8', newline='
')`; plain `open(p, 'w')` on Windows writes CRLF and makes every line show as changed.

## Patch notes (the user's rule, 2026-11-25)
- Every version gets an entry in `Notes.lua`: `ns.NOTES[<n>] = { "..." }` for version 0.1.<n> (the number `dist/build.py` is about to stamp: commits so far + 1), or `ns.NOTES_QUIET[<n>] = true` when a player would notice nothing (tests, notes, a tool of ours). `dist/build.py` refuses to build without one.
- Write for a tester: what is different on screen or in behaviour, one line each, plain words, no code names, no names of people. Say "Fixed" only for what was seen broken.
- The window (`MinimalUINotes`) shows, once after an update, every entry above `MinimalUIDB.notesSeen` (account-wide: the last version whose notes were closed) up to the running version, newest first; "Got it" moves the number up. A first install shows nothing. `/men notes [all]` looks back.
- Never renumber or delete an old entry: a tester may be updating across it. If a commit is amended or history changes the count, fix the numbers before pushing.

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
- Anything that casts, uses items or targets must be a SecureActionButton or SecureUnitButton. Use wildcard attributes (`*type1`, `*type2`) so modifiers and Click Casting work, plus `RegisterForClicks("AnyDown","AnyUp")`. Why (the game's `SecureTemplates.lua`, read 2026-11-25): an ACTION button acts on one edge only, the press if its `useOnKeyDown` attribute is true, the release if false, and with no attribute by the `ActionButtonUseKeyDown` setting (press by default, which is why `"AnyUp"` alone never fired). So both edges registered is safe on action buttons, and a button registered for ONE edge must pin `useOnKeyDown` to match (the Quick Cure pill and chips do, 0.1.712). A UNIT button (`SecureUnitButtonTemplate`) is different: it acts on every edge it hears and never reads the attribute, so it gets one edge only (both made Click Casting fire twice).

Escape (0.1.712): the game runs a list of handlers (`Blizzard_GameMenuEsc`); the one for windows is `CloseAllWindows`, which calls `CloseAllBags` BEFORE `CloseSpecialWindows`, and opens the game menu if neither reports a closed window. Our windows are closed through `MeniscusEscProxy` in `UISpecialFrames`; anything of ours hooked to `CloseAllBags` must not close at once or the proxy has nothing left to report (Bags.lua defers it). Quest reward cards (0.1.713): while an item is being fetched its tooltip is one red line, "Retrieving item information"; `ns.ItemUnusable` returns `nil, true` for that (no verdict, ask again) instead of taking it for the reason.

Edit Mode systems and taint (0.1.716): the game's chat frame, minimap cluster, bag bar, buff frames, damage meter, micro menu, tracker and bars are Edit Mode systems, whose `SetPoint` / `ClearAllPoints` / `SetScale` are Lua wrappers (`EditModeSystemTemplates.lua`; the real ones are `SetPointBase` etc.). The wrapper sets `EditModeManagerFrame.editModeSystemAnchorDirty = true`, so called from addon code the flag is tainted; the manager's OnUpdate reads it and runs every system's `OnAnyEditModeSystemAnchorChanged`, which writes `flyoutDirection` on the action bars tainted, and the bars' own layout is then blocked in a fight (`StanceBar:SetPointBase()`, `MultiBar...Button:SetShown()`, blamed on us). Core.lua hooks `OnEditModeSystemAnchorChanged` and sets the flag to nil when `issecurevariable` says it is not the game's. Counts in `MinimalUIDB.anchorflag`; `/men anchorflag old|new`. Never call `:Show()` / `:Hide()` on a game action bar either (their wrappers write `isShownExternal`). This was reasoned from the source and the two blocked stacks, not yet seen to cure it: check `MinimalUIDB.errors` (fresh each session) after a session with fights.

Do not `RegisterGameMenuEscHandler` from the addon: the list is sorted on each registration, which would taint the game's own entries (Escape also stops casting).
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
- **Heals from log lines (0.1.718):** a heal line of yours that no report claims (a heal on someone who is not you, your target or under a nameplate) is drawn as its own number in green at the rail spot (`healLineDraw`, Nameplates.lua; `db.numbersHealsOut`). A heal on yourself is reported and returns early from the handler, so its line is spent against `selfHeals` (reports within half a second) and not drawn again; heal lines wait 0.45 s for that. Only in a fight or within 15 s of a helping spell. Unseen in game: the order and gap of a self-heal's line and report are assumed.
- **Feed Pet keeps buff food (0.1.720):** `buffFood(id)` in Extras.lua reads the item's tooltip (`ns.ItemLines`, Theme.lua, 0.1.719) and calls it a buff food on the words "well fed", "increas", "you will" or " gain" (English wording, assumed from one item; unseen in game). Such food is never the button's pick, even when nothing else is left.
- **What a teaching item teaches (0.1.722):** `taught` in Tooltip.lua adds the taught spell's description to an item tooltip with a "teaches" line. Measured 2026-11-26: the tooltip line's `spellID`, `GetFirstTriggeredSpellForItem` and `GetItemSpell` all give the TEACHING spell (described "Teaches ..."), never the taught one. Since 0.1.723 the taught spell is found by name: spell numbers 1 to 40000 are walked for the name (and the name less its first word), then rank and description settle it; `MinimalUIDB.teachdiag` says what was found. Unseen in game. Bags red wash on usable items was the "Retrieving item information" line (fixed 0.1.721, confirmed by the player).
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

## Reworks from the source review (2026-11-25): how they are staged

The user's rule: carefully, with a way back flagged at every stage. So for each rework: (1) `git tag -a stage/before-<name>` first, pushed; (2) the new way is added BESIDE the old, used first, falling back to the old when the game gives nothing, with a count of what the game said in the saved record and a chat command that forces the old way (`/men petmood old|new`, `/men bestiary meter old|new`); (3) a tag per stage (`stage/<name>-<n>-<what>`); (4) the old code goes only in a last stage of its own, after the user has seen the new way work. The list and its state are in WAITING.md. A call listed in the game's docs may still be missing on this client (docs are shared between flavours): `MinimalUIDB.apicheck` says which exist.

Aura rows (stage 1, 0.1.705; Auras.lua "Rows drawn by the game"): the TARGET's row is our own `AuraContainer` (`MeniscusTargetAuras`, child of the target frame) with two groups, `AddAuraGroup("debuffs", "HARMFUL", ...)` then `("buffs", "HELPFUL", ...)`, eight of each, each button dressed once by `liveDress` in the look of `newIcon` (picture `SetIcon`, timer `SetDurationCooldown`, count `SetApplicationCount`, ring and emblem by kind through `AddDispelTypeTexture` with `customDispelColorMap` / `customDispelAssetMap`). `UF:SeatTargetAuras` seats it and leaves Blizzard's own target icons unseen. Group rules read in the source: options are `maxFrameCount, templateNames, initializeFrame, candidateFilters, sortMethod, sortDirection, layout`; layout is `elementSpacing, lineSpacing, groupSpacing, groupLineSpacing, forceNewLine, elementWidth, elementHeight, layoutIndex`; ten buttons are made up front; a container with a group sizes itself and nothing scripted of ours may be anchored TO it (anchor it to ours, never ours to it). `/men buffs old|live`; record `MinimalUIDB.liverows`; test `dist/tests/aura_rows.py`. Unseen in game. Next stages: focus and party the same way, then a true seal timer from an aura slot on yourself.

Bestiary and the damage meter (stage 1, 0.1.706; Bestiary.lua "Asked by view and by creature number"): after a fight `readEnemies` asks the meter's "enemy damage taken" view by its number (`C_DamageMeter.GetCombatSessionFromType(1, Enum.DamageMeterType.EnemyDamageTaken)`): one line per enemy with what it took from everybody, its creature number in `sourceCreatureID` (a creature's line has NO `sourceGUID`: the old search by GUID never matched, forty fights of forty) and `deathTimeSeconds`. A creature that died, with as many lines as kills noted, gives a health sample (same `healthSample` / `settle` as before), alone or in a group, whatever else was fought. It returns `"hidden"` while figures can't be read (asked again), `true` / `false` for learned or not; only where it learns nothing does the old reading in `readMeter` run. "What hit you" asks view `DamageTaken` by number first (`creditHits`). `ENCOUNTER_END`'s sixth value lists the fight's bosses (`creatureID`, `creatureName`, `remainingHealthPercent`): `noteEncounter` puts them in `MinimalUIDB.bossNames` / `bossIDs`. `/men bestiary meter old|new`; record `MinimalUIDB.metercheck` (counts in `n`, last 60 lines in `log`); test `dist/tests/bestiary_meter.py` (24 checks, an empty book, nothing of the player's read). Unseen in game. NOT yet done (stage 2, after reading what the view really says inside a dungeon): taking a dungeon creature's true number from the meter and folding its made-up record into it; a boss's health from a fight not won (written to the log only).

Roster figure (0.1.707; Inspect.lua): a new way "race", tried first for a character not of your race and sex: the model scene's actor made by `SetModelByUnit("player", false, false, false, true, false, raceID)` (the last value is `customRaceID`; the game's shop does this), then `Undress` / `TryOn`. Sex and face stay the player's (nothing takes a sex). If it brings nothing the class emblem stands; the older ways (display, scene, file: the user said they do not work) are reached only by the pill. `/men figure off|on`. Unseen in game: read `MinimalUIDB.dolldiag`.

Quest dot trial (0.1.707; Extras.lua `/men dotpin [force]`): the one map pin set on the focused quest's spot (`C_Map.SetUserWaypoint`) and followed (`C_SuperTrack.SetSuperTrackedUserWaypoint(true)`), our own hiding and placing switched off meanwhile; ten seconds of what the engine says in `MinimalUIDB.dotpin`. The marker's place is the engine's own (`Blizzard_QuestNavigation/SuperTrackedFrame.lua` only copies `C_Navigation.GetFrame()`), and its fade for an "invalid" target is settable (`SuperTrackedFrame:SetTargetAlphaForState`).

Alts: each character's side is kept as `fa` (0.1.707). Crafted upgrades look within one realm's book, keep bind-on-pickup to its maker, and (0.1.708, the user's rule: opposite sides can't send each other gear) keep to your side: `sameSide(ch)` goes by `fa`, else `C_CreatureInfo.GetFactionInfo(race).groupTag`, and lets an unknown through.

Cast bar "can't be interrupted" (0.1.709; CastBars.lua `byTheGame`): the eighth return of `UnitCastingInfo` (seventh of `UnitChannelInfo`), possibly hidden, handed to `fill:SetVertexColorFromBoolean(value, colorIfTrue, colorIfFalse)` (colour objects). The old look at the game's unseen bar's `BorderShield` stays as the fallback; `/men cast kick old|new`; counts in `MinimalUIDB.castkick`. Unseen in game.

Quick Buff and the world map (0.1.709): the pill is in the HIGH layer and drew over the map, so `QB:Refresh` offers nothing while `WorldMapFrame` is shown (hooks on its OnShow / OnHide); in a fight, where the button can't be hidden, its opacity is 0 until the map closes.

Polling to events (stage 1, 0.1.710): `UNIT_IN_RANGE_UPDATE` fades a group frame at once (UnitFrames.lua `StartRangeFade`), and `EventRegistry` "MenuProxy.OnShow" (payload: the menu frame, submenus too) styles a menu as it shows (Skins.lua `skinMenus`). Both BESIDE the existing looks, which are unchanged; `ns.PollNote` counts into `MinimalUIDB.pollcheck`; `/men poll old|new`. Stage 2 slows or drops the looks only after the counts are read. Measured cost of the whole addon: 0.12-0.24 ms a frame, so this is tidiness, not need.

Rings (0.1.710): any spell named "Seal of ..." gets the seals' ring (the user's rule: recast the seal last cast; the `RECAST` names are the classic game's and only one matched here). Length: `QB.db.ringSecs[name]`, learned from the buff out of a fight, else 30 s. `MinimalUIDB.ringdiag` lists seal casts by name and id.

Quest dot on a map pin: tried 2026-11-25, does not mend it (still "invalid", right bearing, wrong height). The dot stays hidden; details in WAITING.md.

Bestiary stage 2 (0.1.715; `readEnemies`): a meter line carries a creature's number AND name, so a record known by name alone (made-up number below zero) or by number alone is made one there (`setName`, which folds). Outdoors the meter always gives both; inside a dungeon it is unseen. Polling to events: stage 2 was judged not worth building (see WAITING.md item 6).

Pets (stages 1-2, 0.1.703-704): `ns.PetMoodNow()` (Bars.lua) asks `C_PetInfo.GetPetHappiness`; Extras.lua `gameSays(id)` asks `C_PetInfo.CanPetEatItem` (a "no" counts only after it has said "yes" to something this session). Both unseen in game.

## Quick Cure (UnitFrames.lua `BuildCure`)

The user's layout (2026-11-25): a small chip beside each PARTY member's bar (their auras start past it: `f.cureSlot`), and for YOU a pill left of the cast bar. Seen only while there is something curable.

The pill SAYS THE DEBUFF'S NAME, not the cure's (the user, 2026-11-25: what is on the unit is the helpful thing). The game writes it (`SetSpellName(fontString)`); it can't be measured and the pill can't be resized in a fight, so the pill has a fixed width (170, +52 when a second cure sits on the right button, marked by a small "right-click") and long names are cut.

**Since 0.1.693 what is SEEN is drawn by the game, not by us.** For you and each party member: an `AuraContainer` (`MeniscusCureAuras`, `MeniscusCureAuras<i>`) with one slot per kind you hold a cure for (`AddAuraSlot(kind, "HARMFUL|RAID", { candidateFilters = { includeDispelTypes = { [kind] = true } }, initializeFrame = dress })`). Each slot's aura button is dressed once as the whole face for that kind (`cureFace` ring / fill / words / picture, `cureFaceFx` light and motes as animation groups, `cureAdopt` hands picture and groups to the game). Over each lies the unseen secure casting button (`MeniscusQuickCure`, `MeniscusCure<i>`; left / right click = the two cures): there for the whole of every fight, and out of a fight only while you are afflicted (readable then). `/men cure show [kind]` plays the same faces on plain frames (a look without a debuff). The display before 0.1.693 (`BuildCureOld`, drawn by us, blind to what is caught in a fight) was removed in 0.1.711 after the user confirmed the new one ("good to go, working as expected", 2026-11-25); it is in the history at the tag `stage/before-cure-old-removed`. Where no container can be made there is no Quick Cure.

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
