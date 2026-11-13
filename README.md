# OpenXP 2.0

Free leveling guides for World of Warcraft: Forever.

This branch is the clean 2.0 slate: only what 2.0 uses today.

- `OpenXP/` is the addon, exactly what goes in `Interface/AddOns/OpenXP`.
- Default route: PoleStar's 1-60 leveling guides
  (https://github.com/fitzforge/polestar, GPL-3.0), converted by
  `tools/import_polestar_route.py`. Our older 21-60 route is kept as the
  "OpenXP Legacy" tab, frozen as it is.
- `tools/`: the data builders (route import, quest data, flights, terrain)
  and `package_2.py` for the release zip.
- `tests/`: run `python3 tests/run_tests.py` (needs `pip install lupa`).

Everything 1.x (the RestedXP-based addon, its guide sources and route
planner) is on `main`. Licence: GPL-3.0 (LICENSE); credits in
`OpenXP/NOTICE.md`.
