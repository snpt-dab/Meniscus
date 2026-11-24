# Waiting for

What is built but not yet seen in game, and what each needs. Kept current as we work; newest state first in each line.

Last updated: 2026-11-24, version 0.1.652.

## Needs you, in game

| # | What | What to do | What to tell me |
|---|------|-----------|-----------------|
| 3 | Crafted upgrades between characters | After the restart the file loaded but put nothing on file, and left no reason. 0.1.652 records each step. `/reload`, wait 30 s, type `/men alts`, `/reload` again | What `/men alts` prints (it now says how far it got) |
| 4 | Item names in bestiary loot | Open a dungeon boss's page after a `/reload` | Whether any row still reads "Item 1234" |
| 5 | Boss health from the group's damage | Kill a dungeon boss in a group, with nothing else dying in that fight | Whether its health shows afterwards |
| 6 | The map's own buttons in full screen | Open the map in full screen, first open after a `/reload` | Whether the game's two buttons (close, make small) are there. If yes, the "Exit full screen" pill goes |
| 7 | Level-up card reasons | Nothing to test | What each level unlocks in this game (only level 10 is filled in) |

## Read from the saved record after your next reload (nothing for you to do)

- `alttrail`: how far the crafted-upgrades snapshot gets, and any failure's message (3).
- `altdiag`: whether each character's weapon skills can be read by skill number (3).
- `grouphp`: the group-damage sums behind a boss's health (5).
- `instdiag`, `bestiaryTip`: what the game says about creatures inside a dungeon.

## Offered, not built

- A "mail to this alt" hint at the mailbox for crafted pieces flagged for an alt.
- Level and rank of dungeon creatures from nameplates seen to die.
- Heal numbers from log lines.

## Settled recently

- Killing-blow numbers from log lines: confirmed by eye on 2026-11-24 (numbers show on the killing swing). Still not known: the crit look for those, and `/men logtext` can go with the old probes.
- A string holding a log line cannot be measured at all: 12 of 12 had no width in the ordinary typeface either. So the record can never say whether the numbers draw; the switch-off on width is harmless now and the question is items 1 and 2.
- The spellbook error ("cannot anchor protected frames") is not in the current session's record: old.
- Typeface check passes in game since 0.1.649 (the make with a speck of ink in the wide bracket).
- Red wash on bag items you can't use: confirmed.
- Dungeon headings and Boss rank in the bestiary: confirmed.
