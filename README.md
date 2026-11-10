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

## Work on the code locally (Windows)

Keep one copy of the repo on your PC and point the game at it, so edits show up in game after a `/reload`.

1. Install [Git for Windows](https://git-scm.com/download/win) (or GitHub Desktop) and sign in to GitHub when it asks.
2. Clone the repo, in PowerShell:
   ```powershell
   cd $HOME\Documents
   git clone https://github.com/mjared123/openxp.git OpenXP
   cd OpenXP
   git config user.name "mjared123"
   git config user.email "158239791+mjared123@users.noreply.github.com"
   ```
3. Close the game. In your Forever client's `Interface\AddOns` folder, delete (or move out) any `OpenXP` folder from a test zip.
4. Link the repo into AddOns. In a Command Prompt (not PowerShell), with your own AddOns path:
   ```bat
   mklink /J "C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\OpenXP" "%USERPROFILE%\Documents\OpenXP"
   ```
   This is a junction: the game sees `AddOns\OpenXP`, but the files live in `Documents\OpenXP`. Deleting the junction does not delete the repo.
5. Start the game. After editing a file, type `/reload`. To get the latest changes, run `git pull` in the repo folder.

## Versions

OpenXP is in beta, so versions end in `-beta` (for example `1.1.5-beta`). The version lives in one place, the
`## Version:` line of `OpenXP.toc` and `OpenXP_Vanilla.toc`. For a new version, change both, and add a matching entry at the
top of the changelog in `WelcomeFrame.lua`.

## Build a release zip

`python3 tools/package.py` builds `OpenXP-<version>.zip` (for example `OpenXP-1.1.5-beta.zip`) with only the Forever and
Classic Era files. It stops if the `.toc` versions and the newest changelog entry don't match.

## Smart start

OpenXP works out where you are even if you install it halfway through leveling. On login it checks your level, zone, quest log and completed quests, then jumps to the right guide section and step. If you skipped a section, quest chains you can no longer start are skipped automatically.

- `/oxp where` runs Smart start again at any time.
- `/oxp catchup` lists the skipped chains and which guide section picks up the missing quest.

## Guide tools (Questie data)

Questie's data is GPLv3, so it is never copied into OpenXP. The tools below read your own copies at build time, and
OpenXP reads the installed Questie while you play.

1. Get Questie's public data: `git clone --depth 1 https://github.com/Questie/QuestieDB` (outside this repo).
2. WoW Forever quests that aren't in those files yet come from the installed Questie: in game, type `/oxp questdump`,
   wait for "Done", then `/reload`. That saves them in `WTF\Account\<name>\SavedVariables\OpenXP.lua`
   (`/oxp questdump clear` removes it again).
3. `python tools/audit_guides.py --questiedb PATH\QuestieDB --questie "PATH\AddOns\Questie" --dump PATH\OpenXP.lua`
   lists, zone by zone, the quests each faction can do that no guide picks up.
4. `python tools/build_route.py --questiedb PATH\QuestieDB --dump PATH\OpenXP.lua tools/routes/<route>.py` drafts a route.

## Tests

`pip install lupa`, then `python3 tests/run_tests.py`. The tests run Smart start against the real Forever guides outside the game.
