# OpenXP

Free leveling guides for World of Warcraft: Forever.
Download: https://www.curseforge.com/projects/1792509

- `OpenXP/` is the addon, exactly what goes in `Interface/AddOns/OpenXP`.
- `OpenXP_Nav/` is the optional walking-path data for the arrow
  (`Interface/AddOns/OpenXP_Nav`).
- Leveling route: PoleStar's 1-60 guides
  (https://github.com/fitzforge/polestar, GPL-3.0), converted by
  `tools/import_polestar_route.py`.
- `tools/`: the data builders (route import, quest data, flights, terrain),
  `package_2.py` for the release zip and `curseforge_upload.py` for releases.
- `tests/`: run `python3 tests/run_tests.py` (needs `pip install lupa`).

Releases: push a tag `vX.Y.Z` that matches `## Version` in `OpenXP/OpenXP.toc`
and the newest entry in `OpenXP/UI/Welcome.lua`; `.github/workflows/release.yml`
uploads it to CurseForge.

OpenXP 1.x (the RestedXP-based addon, CC BY-NC-SA 4.0) ends at tag `v1.3.66`.
Licence: GPL-3.0 (LICENSE); credits in `OpenXP/NOTICE.md`.
