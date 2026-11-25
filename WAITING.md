# Waiting for

What is built but not yet seen in game, and what each needs. Kept current as we work; newest state first in each line.

Last updated: 2026-11-25, version 0.1.704.

## Needs you, in game

| # | What | What to do | What to tell me |
|---|------|-----------|-----------------|
| 11 | Quick Cure drawn by the game, so that it shows for what is caught IN a fight (0.1.693) | `/reload`. (a) `/men cure show`: two samples appear above the pill’s place for 12 seconds, each with a caption: the pill ("on you") and a small round chip ("on a party member"); no debuff needed. CONFIRMED 2026-11-25: both draw and the motion looks right. Since 0.1.699 the pill says the DEBUFF’s name (the game writes it), not the cure’s; the sample reads "The disease’s name". (The stronger flash, halo and static on the name of 0.1.700 looked janky and were taken out in 0.1.701: the light is as confirmed.) (b) Catch something curable out of a fight. (c) Catch something curable while already in a fight. Then `/reload` | (a) Does the sample look right: a flash every couple of seconds, faint dust coming off it in time with the flash? (b) Does the pill appear with the debuff’s own picture and NAME (cut short if very long), and does a click cure? (c) Does it appear during the fight, and go when cured? If nothing shows at all: `/men cure old`, `/reload` brings the previous display back |
| 12 | Pet mood and pet food asked of the game (0.1.703-704; needs a hunter with a pet out) | `/reload`. Look at the pet’s name pill and the feed button; feed the pet from Content to Happy; hover the feed button; open the character window’s pet page. Then `/reload` | Is the mood word right, and does it change at once when the pet becomes happy (it used to stick until a reload)? Does the feed button count the right foods, and does its tooltip say "Eats: ..."? Does the pet page show the mood? If anything is off: `/men petmood old` goes back to the old way at once |
| 10 | The figure on another character’s full sheet (0.1.675) | `/reload`, Roster, another character, "Open the full sheet". A small "Figure 1 of N" pill sits over the figure: click through the ways. Then `/reload` | For each way: is there a figure, is it the right race and sex, and is it wearing that character’s gear (not yours, not nothing)? |
| 7 | Righteous Fury through Quick Buff (0.1.679) | `/reload`. With Righteous Fury off, out of a fight | Does the Quick Buff pill offer it (it should, since you have cast it before)? After clicking the buff off with time left, does it stop offering, with a line in chat? Do seals still get their ring, and Righteous Fury none? |
| 2 | Buff ring out of a fight (0.1.665) | Let a seal run out with no fight | Whether it glides to mid-screen for its last seconds |
| 6 | Crafted upgrades between characters | This character is on file now (8 gear recipes). Log in each alt once; on each crafter open each profession window | Whether slot discs, the Crafts tab, row arrows and the "For alts" pill show |
| 8 | Vendor value on loot rows (0.1.664) | Loot a corpse | Whether each sellable item shows its value at the right of its row |
| 3 | Boss health from the group's damage | Kill a dungeon boss in a group, with nothing else dying in that fight | Whether its health shows afterwards |
| 4 | Level-up card reasons | Nothing to test | For each level where something new opens up in this game (a talent point, a new skill rank, mounts, a dungeon): which level and what. The card shown at level-up has a line for it; only level 10 is filled in |

## Read from the saved record after your next reload (nothing for you to do)

- `apicheck` (0.1.702): which of the calls the review below wants to build on really exist on this client (the game’s docs are shared between its flavours). Written four seconds after login; one `/reload` after that and it can be read.
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

**Way back at every stage.** Each rework keeps the old code beside the new until you have seen the new work, with a chat command that switches back at once, and a git tag before and after each stage (`git tag -l "stage/*"`). Tags so far: `stage/before-pet-rework` (0.1.702), `stage/pet-1-mood` (0.1.703), `stage/pet-2-food` (0.1.704). The old code is deleted only in a last stage of its own, after your word.

1. IN PROGRESS (stages 1 and 2 built, see item 12; stage 3, removing the curves, ticker, learned diets and probes, waits for your word). Pet mood and pet food from `C_PetInfo.GetPetHappiness` / `GetPetFoodTypes` / `CanPetEatItem` (Bars.lua mood curves and ticker, Extras.lua learned diets; the Character sheet’s pet row calls a global that is not there).
2. Party, focus and target aura rows on aura containers (`AddAuraGroup`), so they stay live in a fight; a true seal timer from an aura slot on yourself (`includeSpellIDs` is allowed for your own buffs).
3. Bestiary in dungeons: the damage meter’s views by number (`Enum.DamageMeterType`, enemy damage taken = 10), each enemy’s creature number from the meter (`sourceCreatureID`), bosses and their health from `ENCOUNTER_END` (`encounterUnitStatus`). Would answer boss health (item 3) without a clean one-kill fight.
4. The alt’s figure: `actor:SetModelByUnit("player", ..., customRaceID)` then `TryOn` per saved item: right race and gear, but your own sex.
5. Cast bar "can’t be interrupted" from `UnitCastingInfo`’s own return with `SetVertexColorFromBoolean`, not the hidden target frame’s shield.
6. Polling replaced by the game’s own signals: menus (`MenuProxy.OnShow`), action range (`ActionButton_UpdateRangeIndicator`, `ACTION_RANGE_CHECK_UPDATE`), group range (`UNIT_IN_RANGE_UPDATE`), list rows in skinned windows (`ScrollUtil.AddAcquiredFrameCallback`), window docking (`UIParentPanelManager.ShowUIPanel`).
7. Click edge pinned with the `useOnKeyDown` attribute; CLAUDE.md’s note on click edges corrected.
8. Probe.lua: about a thousand lines of probes whose questions the source answers can go.

Checked and already the right way (do not re-audit): combat log tickets, colours and the logout filter; crit from UNIT_COMBAT’s flag; health and power through percent curves; cast bar timing; the action bars riding the game’s own buttons; bags, merchant, mail, taxi, loot values, tooltips, map buttons; the floating XP line (engine text, no switch); Quick Cure’s slots.

## Offered, not built

- A "mail to this alt" hint at the mailbox for crafted pieces flagged for an alt.
- Level and rank of dungeon creatures from nameplates seen to die.
- Heal numbers from log lines.

## Settled recently

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
