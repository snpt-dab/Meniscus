# Waiting for

What is built but not yet seen in game, and what each needs. Kept current as we work; newest state first in each line.

Last updated: 2026-11-25, version 0.1.688.

## Needs you, in game

| # | What | What to do | What to tell me |
|---|------|-----------|-----------------|
| 11 | Cure pill for something caught in a fight (0.1.688) | `/reload`. Get diseased while already in a fight, once or twice, then `/reload` | Whether the pill came up during the fight. Either way the record now says exactly what the game’s debuff buttons give up in a fight |
| 10 | The figure on another character’s full sheet (0.1.675) | `/reload`, Roster, another character, "Open the full sheet". A small "Figure 1 of N" pill sits over the figure: click through the ways. Then `/reload` | For each way: is there a figure, is it the right race and sex, and is it wearing that character’s gear (not yours, not nothing)? |
| 7 | Righteous Fury through Quick Buff (0.1.679) | `/reload`. With Righteous Fury off, out of a fight | Does the Quick Buff pill offer it (it should, since you have cast it before)? After clicking the buff off with time left, does it stop offering, with a line in chat? Do seals still get their ring, and Righteous Fury none? |
| 2 | Buff ring out of a fight (0.1.665) | Let a seal run out with no fight | Whether it glides to mid-screen for its last seconds |
| 6 | Crafted upgrades between characters | This character is on file now (8 gear recipes). Log in each alt once; on each crafter open each profession window | Whether slot discs, the Crafts tab, row arrows and the "For alts" pill show |
| 8 | Vendor value on loot rows (0.1.664) | Loot a corpse | Whether each sellable item shows its value at the right of its row |
| 3 | Boss health from the group's damage | Kill a dungeon boss in a group, with nothing else dying in that fight | Whether its health shows afterwards |
| 4 | Level-up card reasons | Nothing to test | For each level where something new opens up in this game (a talent point, a new skill rank, mounts, a dungeon): which level and what. The card shown at level-up has a line for it; only level 10 is filled in |

## Read from the saved record after your next reload (nothing for you to do)

- `alttrail`: how far the crafted-upgrades snapshot gets, and any failure's message (3).
- `cureways`, `curefight`, `cureprobe`, `cureerr` (fresh each session): which way of asking answered in a fight, whether the debuff border’s colour came plain or hidden, and what a shown debuff button’s fields hold (11).
- `dolldiag`: for each way of standing a figure up, whether a model came and what the game answered to each piece of gear (10).
- `figdiag`: the body number this character measured, to check the table of race bodies against (10).
- `altdiag`: whether each character's weapon skills can be read by skill number (3).
- `grouphp`: the group-damage sums behind a boss's health (5).
- `instdiag`, `bestiaryTip`: what the game says about creatures inside a dungeon.

## Offered, not built

- A "mail to this alt" hint at the mailbox for crafted pieces flagged for an alt.
- Level and rank of dungeon creatures from nameplates seen to die.
- Heal numbers from log lines.

## Settled recently

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
