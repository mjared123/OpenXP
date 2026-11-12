# OpenXP 2.0

OpenXP 2.0 replaces every part that came from RestedXP (the engine, the 1-20
guides, the data files and textures) with OpenXP's own, so OpenXP can move
from CC BY-NC-SA 4.0 to GPL-3.0. Once it is GPL-3.0 it can use PoleStar's
code and the open forever-db quest database, with credit.

This work lives on the `openxp-2.0` branch. Nothing here is released until
it has been tested in game; 1.3.x fixes keep going to `main`.

## Phases

| Phase | What | State |
| --- | --- | --- |
| 0 | Branch, library licences, guide converter and its test | done |
| 1 | Core engine: guide data loader, step engine, quest state, guide list | next |
| 2 | Card UI, arrow, smart start, terrain, travel and map pins on the new engine | |
| 3 | 1-20 guides for every race and Skyborne | |
| 4 | Settings, automation, item and target buttons, timers, data from forever-db | |
| 5 | 1.3.x save importer, private test build | |
| 6 | CurseForge beta, then release | |

## Guide data

The 2.0 engine reads guides as Lua tables, not text. `tools/convert_guides.py`
turns the 1.x guide files in `Guides/openxp/` into `Guides/v2/`; the format is
described at the top of the script. Until the 2.0 engine replaces the old
one, `Guides/openxp/` stays the source: fix a guide there, then run

    python3 tools/convert_guides.py

`tests/convert_roundtrip.py` (part of `tests/run_tests.py`) loads every
converted file in Lua, writes it back out as 1.x guide text and checks it
matches the source line for line, so the 2.0 data always holds exactly the
same route. It also fails when `Guides/v2/` is out of date. The zone
completion and Forever dungeon guides on the `zone-completion` branch convert
the same way:

    python3 tests/convert_roundtrip.py path/to/Completion-Alliance.lua

The 1.x group names (`RestedXP Forever Guide (A)` and `(H)`) become
`OpenXP Leveling (Alliance)` and `(Horde)`; each guide keeps its old group as
`oldGroup` so the save importer can find a player's place.

## Libraries

Every library bundled in `libs/` was checked for whether a GPL-3.0 addon can
ship it (November 2026).

| Library | Licence | OK under GPL-3.0? | 2.0 plan |
| --- | --- | --- | --- |
| Ace3 (AceAddon, AceComm, AceConfig, AceConsole, AceDB, AceDBOptions, AceEvent, AceGUI, AceLocale, AceSerializer) and CallbackHandler | Ace3-style BSD ([wowace.com/projects/ace3](https://www.wowace.com/projects/ace3)); forbids redistributing it standalone, which embedding is not | Yes, embedded | Keep the parts 2.0 uses |
| LibStub | Public domain (its file header) | Yes | Keep |
| HereBeDragons | BSD (`X-License` in its .toc; no LICENSE file in its repo) | Yes | Keep for map and minimap pins |
| LibDeflate | zlib (LICENSE.txt also carries the LGPL text) | Yes | Keep if 2.0 still compresses data |
| plc base64 | MIT (its LICENSE) | Yes | Keep if needed |
| LibDBIcon-1.0 | Ace3-style BSD ([CurseForge](https://www.curseforge.com/wow/addons/libdbicon-1-0)) | Yes, but it needs LibDataBroker | Replace with our own minimap button |
| LibCandyBar-3.0 | Ace3-style BSD ([CurseForge](https://www.curseforge.com/wow/addons/libcandybar-3-0)) | Yes | Drop: only the RestedXP timers use it |
| LibDataBroker-1.1 | None stated ([repo](https://github.com/tekkub/libdatabroker-1-1) has no licence) | Unclear | Drop |
| LibUIDropDownMenu | GPLv2 ([CurseForge](https://www.curseforge.com/wow/addons/libuidropdownmenu)) | No, unless it is "v2 or later" | Drop: only the RestedXP settings, talents and tracker use it |
| `libs/compatibility.lua` | RestedXP's file | No | Rewrite the few helpers 2.0 needs |
