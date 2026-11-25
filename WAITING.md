# Waiting for

What is built but not yet seen in game, and what each needs. Kept current as we work; newest state first in each line.

Last updated: 2026-11-25, version 0.1.714.

## Needs you, in game

| # | What | What to do | What to tell me |
|---|------|-----------|-----------------|
| 13 | The target’s buffs and debuffs drawn by the game in our look (0.1.705) | `/reload`. Target something with buffs or debuffs, out of a fight and in one (your own debuffs on an enemy will do). Hover an icon. Then `/reload` | Are the icons round with our ring (red for a plain debuff, the kind’s colour with a small emblem for magic, curse, disease, poison), debuffs first then buffs? Do they sit where the target’s icons sat? Do new ones appear and old ones go DURING a fight? Is there a dark sweep for the time left, and a stack number? Does the tooltip show? Can you still click the target frame through them? If anything is off: `/men buffs old`, `/reload` |
| 12 | Pet mood and pet food asked of the game (0.1.703-704; needs a hunter with a pet out) | `/reload`. Look at the pet’s name pill and the feed button; feed the pet from Content to Happy; hover the feed button; open the character window’s pet page. Then `/reload` | Is the mood word right, and does it change at once when the pet becomes happy (it used to stick until a reload)? Does the feed button count the right foods, and does its tooltip say "Eats: ..."? Does the pet page show the mood? If anything is off: `/men petmood old` goes back to the old way at once |
| 10 | The figure on another character’s sheet, made from your own figure given its race (0.1.707) | `/reload`, Roster, a character of ANOTHER race, open its sheet. Then one of your own race but the other sex. Then `/reload` | Is there a figure of the right race in that character’s gear (it will have your character’s build and face: the game takes a race, not a sex)? If there is only the class emblem, the game refused, and that is where it stays for now. `/men figure off` shows the emblem always |
| 15 | Cast bar: "can’t be interrupted" asked of the game (0.1.709) | `/reload`. Target enemies that cast: ordinary ones, and one whose cast can’t be interrupted if you meet one. `/men cast kick` says in chat what the game answered | Is an enemy’s cast amber the moment it starts (no flicker of another colour first), and grey for one that can’t be interrupted? A friendly target’s cast stays the accent colour. If colours go wrong: `/men cast kick old` |
| 2 | A ring for whichever seal you last cast (0.1.710) | `/reload`. Cast each of your seals in turn, in a fight and out of one; let one run out. Then `/reload` | Does every seal get the ring now, with the right length (the first cast of a seal assumes 30 s until its buff has said how long, out of a fight), and glide to mid-screen as it runs out? |
| 18 | Escape with the bags open (0.1.712) | `/reload`. Open the bags, press Escape once. Then with the bags and another window open; then at a merchant | Do the bags close with no game menu? With two windows up, each Escape closes the newest one. Do the bags still close by themselves when you walk away from a merchant, bank or mailbox? |
| 19 | Quest reward that is still loading (0.1.713) | Open quests you have not seen before, with item rewards | No more "(Can’t use · Retrieving item information)"; a true "Can’t use" with its reason still shows, within half a second |
| 20 | A whisper in its own tab (0.1.714) | `/reload`, then have a whisper open as its own tab (as in your picture) | No black block hanging over the left edge; the tab plain with the underline when selected; the typing field like the others, inside the wing. Also a whisper tab opened DURING a fight: is its typing field in place once the fight ends? |
| 17 | Menus and group range told by the game (0.1.710) | Nothing special: open some right-click menus with submenus; be in a group with someone going in and out of range. `/men poll` says how often the game spoke | Any menu that flashes in the game’s own look before ours, or a group frame that fades late or not at all. `/men poll old` if anything is off |
| 6 | Crafted upgrades between characters | (1) Log in every character once, so each one’s gear is on file. (2) On each character that has a crafting profession, open that profession’s window once (and scroll nowhere: opening is enough), so its recipes are on file. (3) Then on any character open the character window, and on a crafter the profession window | On the character window: a small disc on a gear slot when one of your OTHER characters can craft something better for it, and a "Crafts" tab listing those. On a crafter’s profession window: an arrow on a recipe that would be an upgrade for one of your other characters, and a "For alts" pill that filters to them. Tell me which of the four you see, and whether what they suggest makes sense |
| 8 | Vendor value on loot rows (0.1.664) | Loot a corpse | Whether each sellable item shows its value at the right of its row |
| 3 | A dungeon boss’s health from the game’s meter (0.1.706) | A dungeon boss in a group (adds may die too). Then `/reload` | A health for it in the bestiary, and rank Boss |
| 4 | Level-up card reasons (level 10: talents; hunters also "Pet quest available", 0.1.710) | Nothing to test | For each level where something new opens up in this game (a talent point, a new skill rank, mounts, a dungeon): which level and what. The card shown at level-up has a line for it; only level 10 is filled in |

## Read from the saved record after your next reload (nothing for you to do)

- `apicheck` (0.1.702): which of the calls the review below wants to build on really exist on this client (the game’s docs are shared between its flavours). Written four seconds after login; one `/reload` after that and it can be read.
- `pollcheck`: how often the game’s own signals spoke for menus and group range, and what our watcher still found first (17).
- `ringdiag`: each seal cast, by name and number, and whether it got a ring (2).
- `castkick`: how each cast’s "can it be interrupted" was answered (15).
- `dotpin`: what the game’s engine said of the marker during the trial, four times a second (14).
- `dolldiag`: whether the game made your figure of another race, and what each piece of gear answered (10).
- `metercheck`: what the game’s meter said of each enemy after each fight, what health was taken from it, and what the old way would have said (3).
- `liverows`: how many of the target’s icons the game let us dress, and the first thing it refused, if anything (13).
- `petcheck`: what the game’s pet calls said (mood 1-3, hidden, missing), and how its word on each food sits with what feeding had taught us (12).
- `alttrail`: how far the crafted-upgrades snapshot gets, and any failure's message (3).
- `curecontainer` (fresh each session): for you and each party member, how many faces the game let be made and dressed, any refusal’s words, whether auras were secret in the fight, and each kind of curable debuff that was read on you out of a fight (so that “nothing appeared” can be held against what was there) (11).
- `dolldiag`: for each way of standing a figure up, whether a model came and what the game answered to each piece of gear (10).
- `figdiag`: the body number this character measured, to check the table of race bodies against (10).
- `altdiag`: whether each character's weapon skills can be read by skill number (3).
- `grouphp`: the group-damage sums behind a boss's health (5).
- `instdiag`, `bestiaryTip`: what the game says about creatures inside a dungeon.

## Review against the game’s own source (2026-11-25): rework candidates, not started

Read in the source for this build; each still wants `apicheck` or one look in game before it is built on. In the order I would do them:

**Way back at every stage.** Each rework keeps the old code beside the new until you have seen the new work, with a chat command that switches back at once, and a git tag before and after each stage (`git tag -l "stage/*"`). Tags so far: `stage/before-pet-rework` (0.1.702), `stage/pet-1-mood` (0.1.703), `stage/pet-2-food` (0.1.704), `stage/before-aura-rows` (0.1.704), `stage/aura-1-target` (0.1.705), `stage/before-bestiary-meter` (0.1.705), `stage/bestiary-1-enemy-view` (0.1.706). The old code is deleted only in a last stage of its own, after your word.

1. IN PROGRESS (stages 1 and 2 built, see item 12; stage 3, removing the curves, ticker, learned diets and probes, waits for your word). Pet mood and pet food from `C_PetInfo.GetPetHappiness` / `GetPetFoodTypes` / `CanPetEatItem` (Bars.lua mood curves and ticker, Extras.lua learned diets; the Character sheet’s pet row calls a global that is not there).
2. IN PROGRESS (stage 1, the target, built: item 13; then focus and party, then the seal timer, each its own stage). Party, focus and target aura rows on aura containers (`AddAuraGroup`), so they stay live in a fight; a true seal timer from an aura slot on yourself (`includeSpellIDs` is allowed for your own buffs).
3. IN PROGRESS (stage 1 built: item 3. Stage 2, a dungeon creature’s true number from the meter, waits for what `metercheck` says inside a dungeon). Bestiary in dungeons: the damage meter’s views by number (`Enum.DamageMeterType`, enemy damage taken = 10), each enemy’s creature number from the meter (`sourceCreatureID`), bosses and their health from `ENCOUNTER_END` (`encounterUnitStatus`). Would answer boss health (item 3) without a clean one-kill fight.
4. IN PROGRESS (built 0.1.707: item 10; tags `stage/before-figure-by-race`, `stage/figure-1-by-race`). The alt’s figure: `actor:SetModelByUnit("player", ..., customRaceID)` then `TryOn` per saved item: right race and gear, but your own sex.
5. IN PROGRESS (built 0.1.709: item 15; tags `stage/before-cast-kick`, `stage/cast-kick-1`). Cast bar "can’t be interrupted" from `UnitCastingInfo`’s own return with `SetVertexColorFromBoolean`, not the hidden target frame’s shield.
6. IN PROGRESS (stage 1, 0.1.710: menus and group range told by the game, BESIDE the looking, which is unchanged; item 17. Tags `stage/before-poll-events`, `stage/poll-1-signals`. Stage 2, after `pollcheck` is read: slow or drop the looking those two replace. Not started: action range, list rows in skinned windows, window docking. Measured 2026-11-25: the whole addon costs 0.12 to 0.24 ms a frame at 120 frames a second, so none of this is urgent). Polling replaced by the game’s own signals: menus (`MenuProxy.OnShow`), action range (`ActionButton_UpdateRangeIndicator`, `ACTION_RANGE_CHECK_UPDATE`), group range (`UNIT_IN_RANGE_UPDATE`), list rows in skinned windows (`ScrollUtil.AddAcquiredFrameCallback`), window docking (`UIParentPanelManager.ShowUIPanel`).
7. DONE (0.1.712; tags `stage/before-click-edge`, `stage/click-edge-pinned`): the source shows the attribute only matters on action buttons registered for one edge, which is the Quick Cure pill and chips; pinned there. Unit frames never read it. Nothing to delete later. Click edge pinned with the `useOnKeyDown` attribute; CLAUDE.md’s note on click edges corrected.
8. DONE (0.1.713; tags `stage/before-probes-removed`, `stage/probes-removed`): about 1,150 lines gone from Probe.lua. Kept: `/men probe`, clicks, keyprobe, under, artprobe, winprobe, combatprobe, bug, deepprobe, the recorder, the level-by-level attributes, the buff values, the call check. Probe.lua: about a thousand lines of probes whose questions the source answers can go.

Checked and already the right way (do not re-audit): combat log tickets, colours and the logout filter; crit from UNIT_COMBAT’s flag; health and power through percent curves; cast bar timing; the action bars riding the game’s own buttons; bags, merchant, mail, taxi, loot values, tooltips, map buttons; the floating XP line (engine text, no switch); Quick Cure’s slots.

## Offered, not built

- A "mail to this alt" hint at the mailbox for crafted pieces flagged for an alt.
- Level and rank of dungeon creatures from nameplates seen to die.
- Heal numbers from log lines.

## The quest dot (hidden since 0.1.604): what the game’s source shows

Read 2026-11-25 (`Blizzard_QuestNavigation/SuperTrackedFrame.lua`). Nothing in it mends the dot as built, but there are two leads, neither tried in game:

1. The marker’s place is the game engine’s, not its interface code’s: the code only copies where the engine’s own unseen frame is. So the leaping about was the engine having no true place for a QUEST here (it also rates every quest “invalid”). The engine can be given an exact place instead: a map pin (`C_Map.SetUserWaypoint` at the quest’s spot on the map, which we already work out, then `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`). `C_Map.CanSetUserWaypointOnMap` answered yes on this client. Whether the engine then rates the target valid and holds the marker steady is the open question: one short trial would say. Cost: it uses the one map pin a player has.
2. The marker’s fading to nothing for an “invalid” target is a table in that file with a setter (`SuperTrackedFrame:SetTargetAlphaForState(state, alpha)`): the sanctioned way to keep it seen, in place of our holding its opacity every frame (which shimmered). It does nothing for where the marker is put.

Built 0.1.707 as a trial: `/men dotpin` (item 14); `/men dotpin force` adds lead 2.

**The trial’s result (2026-11-25, your report and `dotpin`): lead 1 does not mend it.** With the marker following a map pin the engine still rates the place “invalid” every time (state 0 in all forty readings), so the dot shows only when forced. Its place across the screen is right and follows your turning; its height is not (the marker sat near the top of the screen for a place 164 yards off): a pin has no height, and nor, evidently, does a quest’s spot any more. That is the same half-answer the dot had before it was hidden (right bearing, wrong height, which 0.1.5xx papered over by lifting it to the horizon). What worked before the game’s patch was the engine placing the marker itself; nothing in the game’s interface code brings that back. The dot stays hidden; the trial command stays for when the game changes.

## Settled recently

- Quick Cure drawn by the game: “good to go, working as expected” (your word, 2026-11-25). The display before 0.1.693 was removed in 0.1.711 (tags `stage/before-cure-old-removed`, `stage/cure-old-removed`).
- Quick Buff pill no longer over the world map (0.1.709): good.
- Health from the game’s meter (0.1.706): works on ordinary creatures (your word; `metercheck` shows ten taken, each agreeing with the old way where that had an answer, and two fights the old way could not read). A dungeon boss is still to see.

- Crafted upgrades keep to one side (0.1.708): your word, 2026-11-25, that opposite sides can’t send each other gear. A character not played since 0.1.707 is placed by its race, as the game says.

- Righteous Fury through Quick Buff: "working as intended" (your word, 2026-11-25).
- Pets, seen in your screenshot (2026-11-25): the feed button’s tooltip says "Eats: Meat, Fish" in the game’s words, so the game’s pet calls are alive on this client; the mood word read Happy. Still to see: the word changing at once on feeding.

- CONFIRMED by your eyes (2026-11-25, on 0.1.692): the game’s aura button appeared during a fight the moment the debuff landed. The road works. (What you saw was the first try’s bare square; the rebuilt pill of 0.1.693 onward needs a `/reload` to be seen.)
- "Interface action failed because of an AddOn" at about 09:11 on 2026-11-25: its details are written at the next reload; read `errors` then.
- The aura container works on this client (record of 0.1.692): made, given a unit, a slot added for "what you can dispel", its button dressed: every step accepted. The survey it wrote, and then the game’s own source for this build (public: Gethe/wow-ui-source, branch `forever`), gave the rest: slots can be narrowed to a kind of debuff, a button is dressed once as it is made and may not be touched in a fight, and nothing can ask it whether it is shown.
- CORRECTION (2026-11-25, on re-reading the evidence): "no road is left" was wrong. Every road tried was a way of READING a debuff in a fight, and all of those are closed on purpose (the game’s notes for its 12.1 line, which Forever 1.60 carries). The same change added a way to have auras SHOWN without reading them: an `AuraContainer` given a unit and a filter, drawn by the game itself; the filter `HARMFUL|RAID` is "debuffs you can dispel". Under test from 0.1.692 (item 11). Not yet known to work here.
- Client fact (record of 0.1.690): asking the game whether a hidden aura passes the dispel filter (`IsAuraFilteredOutByInstanceID`) is refused in a fight with the same words as every other aura call.
- Client fact (record of 0.1.689): in a fight the game’s own debuff button holds its list place in the clear and everything else hidden (kind, picture, aura number); the border is not coloured but given a hidden atlas. A debuff’s kind cannot be read in a fight by any road.
- Disease smoke as a small faint waft: "looks good now" (it was drawn solid by a fault of mine: alpha set to 1 after the colour).
- Client fact (record of 0.1.682): in a fight every addon look at an aura gained in it is refused ("Auras cannot be accessed when secret while tainted"): by index, by slot, any filter.
- Quick Cure in a fight: the pill stays and the cure click works (your word, 2026-11-25).
- Critical hit numbers: 2.3 times was too much; back to 1.55.
- The rule for buffs (yours, 2026-11-25): under five minutes a ring, five minutes or more the Quick Buff pill. Righteous Fury moved to Quick Buff (offered once you have cast it; click the buff off to stop). Battle Shout is a ring only.
- Roster and the full sheet open and show (tiles, card). The emblem was shown because that character had no race or sex on file yet (not logged in since 0.1.672).
- Upgrade arrows for armour-only gains (0.1.668): confirmed.
- A character listed twice in item tooltips (0.1.666): fixed, confirmed.
- Map buttons in full screen: fine now.
- Why a character showed twice in a tooltip: the realm name comes back empty on some logins, so per-character records were kept under two keys. One remembered realm name now; doubled records folded at load (`keymerge` in the record says how many).
- Combat numbers 36 above the target frame: good. Professions window icons: good for now, may be refined later. Buff ring glides to mid-screen in a fight: seen.
- Seal ring runs through Judgement: confirmed ("looks good").
- In Forever, Judgement does NOT take the seal off (your word): the ring no longer ends on Judgement.
- Seals: asking for the buff by name is blind in a fight ("not there" right after the cast, 3 of 3). Out of a fight it answers, and a seal lasts 30 s.
- Why nothing was on file for crafted upgrades: `GetRealmName()` answers "" on this client. Fixed in 0.1.654 (realm asked three ways, else one book).
- Bestiary loot rows: the name does arrive (300-400 ms); the "Item 1234" placeholder is now a dim "...".
- The game's two map buttons do show in full screen: the "Exit full screen" pill is removed.
- Killing-blow numbers from log lines: confirmed by eye on 2026-11-24 (numbers show on the killing swing). Still not known: the crit look for those, and `/men logtext` can go with the old probes.
- A string holding a log line cannot be measured at all: 12 of 12 had no width in the ordinary typeface either. So the record can never say whether the numbers draw; the switch-off on width is harmless now and the question is items 1 and 2.
- The spellbook error ("cannot anchor protected frames") is not in the current session's record: old.
- Typeface check passes in game since 0.1.649 (the make with a speck of ink in the wide bracket).
- Red wash on bag items you can't use: confirmed.
- Dungeon headings and Boss rank in the bestiary: confirmed.
