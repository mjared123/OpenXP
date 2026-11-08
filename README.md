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

## Smart start

OpenXP works out where you are even if you install it halfway through leveling. On login it checks your level, zone, quest log and completed quests, then jumps to the right guide section and step. If you skipped a section, quest chains you can no longer start are skipped automatically.

- `/oxp where` runs Smart start again at any time.
- `/oxp catchup` lists the skipped chains and which guide section picks up the missing quest.

## Tests

`pip install lupa`, then `python3 tests/run_tests.py`. The tests run Smart start against the real Forever guides outside the game.
