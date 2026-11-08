# Attribution and changes

OpenXP is a modified version of **RestedXP Guides** by RestedXP.

- Original: https://github.com/RestedXP/RXPGuides
- Upstream commit this fork starts from: `b9f2e254c1604f70fd6ddca1dae61dd84156cd13` (2026-11-07)
- License: Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (see `LICENSE`).
  OpenXP must stay free and non-commercial and be shared under the same license.

OpenXP is not affiliated with or endorsed by RestedXP. Guide groups and guides that still carry the
RestedXP name were written by RestedXP and are kept here with credit.

## Changes from the original

- Renamed the addon to OpenXP (`OpenXP.toc`, `OpenXP_TBC.toc`, `OpenXP_Vanilla.toc`) and changed the title, notes and author.
- Removed the CurseForge and Wago project IDs so OpenXP never updates through RestedXP's listings.
- Renamed saved variables from `RXP*` to `OXP*` so OpenXP's settings and progress don't overwrite RestedXP's.
- Removed the `lang/` folder of translated guides for now, and turned off the translated-guide switch so every client language loads the English guides.
- Fixed a texture path that pointed at the `RXPGuides` folder.
- Dropped RestedXP's packaging and CI files.
- Added Smart start (`SmartStart.lua`): picks the right guide section and step from the player's level, zone, quest log and completed quests, and skips quest chains whose earlier quests were skipped (`/oxp where`, `/oxp catchup`).
- Added `/oxp` and `/openxp` slash commands, and pointed bug reports at OpenXP's GitHub issues instead of RestedXP's Discord.
