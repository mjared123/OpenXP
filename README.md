# OpenXP

A free, community-made leveling guide addon for World of Warcraft, starting with **World of Warcraft: Forever**.

OpenXP is based on [RestedXP Guides](https://github.com/RestedXP/RXPGuides) by RestedXP, used under the
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0](LICENSE) license. OpenXP is not affiliated with or
endorsed by RestedXP. Like the original, OpenXP is free and non-commercial, and is shared under the same license.

## Install (for testing)

1. Download this repository (Code → Download ZIP) and unzip it.
2. Rename the unzipped folder to exactly `OpenXP`.
3. Move it into your WoW Forever AddOns folder, for example
   `World of Warcraft\_classic_era_\Interface\AddOns\OpenXP` (use the folder for the Forever client).
4. Disable **RestedXP Guides** if you have it installed. Both addons share some internal names, so they shouldn't run at the same time.
5. Start the game, enable OpenXP on the character select AddOns screen, and log in.

See [NOTICE.md](NOTICE.md) for attribution and the list of changes from RestedXP Guides.

## Features

- Step-by-step routes from level 1 for every Alliance and Horde starting zone, through to 60, plus dungeon guides.
- Quest auto-detection: pickups, turn-ins, kills, items, trainers and flight paths tick off on their own.
- Waypoint arrow with distance. It turns green when you arrive.
- Map and minimap pins with the ! and ? quest icons and step numbers.
- Quest tooltips: mobs show which quests they count for and your progress; quest NPCs show which guide step needs them.
- Pick any guide and start wherever you want; the route carries on to the next zone.
- Step list (click the step counter on the card) to jump to any step.
- Sell junk at vendors, plus optional nameplate range, auto loot and max camera distance.
- Levels 1-60 for WoW Forever and Classic Era. Questie is optional; with it, OpenXP also shows quest chains and levels.

## Build a release zip

`python3 tools/package.py OpenXP-1.0.0.zip` builds a zip with only the Forever and Classic Era files.

## Smart start

OpenXP works out where you are even if you install it halfway through leveling. On login it checks your level, zone, quest log and completed quests, then jumps to the right guide section and step. If you skipped a section, quest chains you can no longer start are skipped automatically.

- `/oxp where` runs Smart start again at any time.
- `/oxp catchup` lists the skipped chains and which guide section picks up the missing quest.

## Tests

`pip install lupa`, then `python3 tests/run_tests.py`. The tests run Smart start against the real Forever guides outside the game.
