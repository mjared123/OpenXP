# OpenXP 2.0 and SoupEngine

SoupEngine (Matt's own route builder, in its own repo) turns quest data and
SoupNav's walking maps into leveling routes. It writes two things for OpenXP 2.0:

1. **Guide files**: normal OpenXP 2.0 guide Lua (`OXP.AddGuides({...})`).
2. **OpenXP_Nav**: a separate, load-on-demand addon folder with baked walking
   paths and floor heights for the arrow.

This note says what OpenXP needs to know about both, what changed in this repo
for it, and what is still open.

## What changed in this repo

Made on branch `soupengine-test` from `68049d0` ("Clean slate: keep only what
OpenXP 2.0 uses") and merged into `polestar-guides` (2.0) on 2026-11-18, after
the UI overhaul. Since then 2.0 uses SoupEngine for all of its navigation:
see "SoupEngine walks only" below.

- `Nav/WalkPaths.lua` (new, listed in `OpenXP.toc` after `Nav\PathHints.lua`):
  loads the optional OpenXP_Nav add-on at login if it's installed and
  enabled, and gives the arrow the next corner of the baked walk to the
  guide's spot. Without OpenXP_Nav it does nothing.
- `Nav/Target.lua`: `Target.Real()` also keeps the spot's map `x`, `y`
  (to find its baked walk), and `Target.Update()` asks
  `WalkPaths.ForArrow(aim)` before `PathHints.ForArrow(aim)`.
- `tools/package_2.py`: the zip holds `OpenXP/` and, when it's there,
  `OpenXP_Nav/` next to it: one download, two add-on folders (like DBM), and
  players can turn OpenXP_Nav off in the AddOns list. Both folders get the
  same "every listed file exists, nothing unlisted" checks.
- `tests/nav_test.lua`: a baked-walk case with a small fake OpenXP_Nav.
- `tests/playthrough_test.lua`: also plays the guide group
  `SoupEngine Test (<Faction>)` for every race and class when SoupEngine
  guide files are listed in `Guides.xml`; skipped otherwise.
- `docs/2.0/SOUPENGINE.md`: this note.

## SoupEngine guides in OpenXP

The guide files need **no OpenXP code changes**. They use the same format as
`Guides/Leveling/<Faction>/PoleStar-01-60.lua`; SoupEngine reads them back
and compares every step and goal before it finishes ("round trip").

They live in their own guide group so they never replace the default:

| | Default (live) | SoupEngine test |
|---|---|---|
| group | `OpenXP Leveling (<Faction>)` | `SoupEngine Test (<Faction>)` |
| file id | `<Faction>-PoleStar-01-60` | `<Faction>-SoupEngine-Test-PoleStar-01-60` (or `<Faction>-SoupTest-<lo>-<hi>`) |
| file | `PoleStar-01-60.lua` | `SoupEngine-Test-PoleStar-01-60.lua` (or `SoupTest-<lo>-<hi>.lua`) |

Why this is safe with the current engine:

- `Registry` keys guides by group + name + only, so the same guide names in
  two groups don't collide.
- `Registry.Next` looks for a guide's `next` in its own group first, so a
  SoupEngine chain stays in the SoupEngine group.
- `SmartStart` only ever picks from `OpenXP Leveling (<Faction>)`, so new
  characters never land on a test guide by accident.
- The guide picker lists every group, so the test group shows up as its own
  entry and players pick it on purpose.

### Loading them for a test

SoupEngine side (in the SoupEngine repo):

```
python -m soup write --faction Alliance --route build/seed_route-Alliance.json \
    --group "SoupEngine Test (Alliance)" --out <OpenXP>/OpenXP/Guides/Leveling/Alliance --check
```

Then add one line per faction to `OpenXP/Guides/Guides.xml`, right after that
faction's `PoleStar-01-60.lua` line:

```
<Script file="Leveling\Alliance\SoupEngine-Test-PoleStar-01-60.lua"/>
```

(`python -m soup build ... --openxp <checkout>` writes a one-band file,
`SoupTest-<lo>-<hi>.lua`, and adds the `Guides.xml` line itself.)

Checked on 2026-11-17: both factions' files (from the seed route, so the same
steps as PoleStar's) loaded with no registry problems, and the play-through
finished every guide for all 90 race/class combos in the test group, 0 failures.

Since 2026-11-18 (Matt's call) both factions' `SoupEngine-Test-PoleStar-01-60.lua`
files and their `Guides.xml` lines are committed on 2.0, as is `OpenXP_Nav/`
(SoupEngine's export from 2026-11-17 23:56, `Graphs-*.json` included). Until
SoupEngine has an optimized route they're the same steps as the default.

Since 2026-11-21 (Matt's call) they're dropped from the build again: they were
exact copies of the default guides and doubled guide memory. Add the
`Guides.xml` lines back when SoupEngine has a route of its own to test.

## OpenXP_Nav (walking paths)

`python -m soup navexport --faction X` (also step 7 of `soup build`) writes
`build/OpenXP_Nav/` in SoupEngine; `--openxp <checkout>` copies it next to this
repo's `OpenXP/` folder, where `tools/package_2.py` picks it up. Decided by
Matt (2026-11-18): ship it whole, maps included, in the same download as
OpenXP, as its own add-on folder players can turn off.

| File | What | Size |
|---|---|---|
| `OpenXP_Nav.toc` | `## LoadOnDemand: 1`, `## Dependencies: OpenXP` | tiny |
| `README.txt` | what's in it, for players and add-on site reviewers | tiny |
| `Init.lua` | tables `paths`, `spots`, `targets`, `graveyards`, `packed`; sets the global `OpenXP_Nav` | tiny |
| `Paths-Alliance.lua`, `Paths-Horde.lua` | baked walks, guide-spot floors, pinpointed targets and graveyards; each only runs for its own faction | ~2.5 MB each |
| `Unpack.lua` | SoupNav's readable graph unpacker (sets `NAV.Unpack`) | tiny |
| `Graphs/<zone>.lua` (48 zones) | SoupNav's packed walking network per zone | ~10.5 MB |

About 16 MB unpacked (export of 2026-11-20, from SoupNav's navmeshes and the
zone graphs rebuilt on 2026-11-19).

Formats:

- `OpenXP_Nav.paths["map:x,y>map:x,y"] = { x1, y1, z1, i1, x2, ... }`: one
  walking leg inside one zone, as corners in map % with height in yards and
  1 = indoors. Keys use two decimals. Most legs
  end exactly on a guide `goto` (`zone`, `x`, `y`); the rest end at other
  points of a trip.
- `OpenXP_Nav.spots["map:x,y"] = { z, indoor }`: the floor of a guide spot
  (addons can't read height on Forever, `UnitPosition`'s z is always 0).
  Every `goto` spot has one. `WalkPaths.Floor(map, x, y)` reads it.
- `OpenXP_Nav.targets["questId:objectiveIndex"] = { {map, x, y, z, indoor, id, kind}, ... }`
  (new 2026-11-20): named mobs, rares and single objects a quest objective
  needs, on the floor they're really on. `map` is the step's uiMap, `x`, `y`
  map % (two decimals), `z` the floor in yards, `indoor` 1/0, `id` the NPC or
  object id, `kind` `"npc"` or `"object"`. Same rule as `Areas.Pinpoints`
  (3 or fewer spawns in the zone, within 14 map % of the step's spot). Walks
  to them: `paths["<step spot>><target>"]` (none when the target is within 3
  yards of the spot). 325 for Alliance.
- `OpenXP_Nav.graveyards["map:x,y"] = { z, indoor }` (new 2026-11-20): spirit
  healers. Walks from the two nearest graveyards of each spot's zone are
  `paths["<graveyard>><spot>"]`. 79 for Alliance.
- Walks across zone borders keep the same key, corners in the end spot's
  map % (below 0 or above 100 while still in the zone before); since
  2026-11-20 they're continuous at the border (no jump at gates). Walks are
  smoother too: fewer corners, about 3 yards off walls, real switchbacks and
  doorway turns kept.

Counts in the 2026-11-20 export: Alliance 7254 walks, 2076 spot floors;
Horde about the same size. Older exports without `targets` or `graveyards`
still work: OpenXP falls back to Questie's spawns and the guide's walks.

It holds only points derived from SoupNav's walking map and SoupNav's packed
graphs: no terrain, meshes, models or anything else copied from the game.
The packed strings could look like hidden code to a reviewer, so README.txt
says what they are and `Unpack.lua` stays plain Lua. If an add-on site
objects anyway, the fallback is shipping only the paths and floors (~2.6 MB).

### SoupEngine walks only (2.0, since 2026-11-18)

Decided by Matt: SoupEngine is the new way, and the arrow and the map lines
use nothing else. One switch, `BAKED_ONLY` near the top of `Nav/Target.lua`,
turns this on (`false` gives back the old arrow, trips and terrain ways).

- **Arrow** (`Target.Update`): the guide's spot (or the card's chain walk),
  followed along a walk from `WalkPaths.ForArrow`; with no walk, straight at
  the spot. No trips between zones (`Nav/Travel.lua`), kill-area edges, path
  hints or terrain stepping stones.
- **Walks** (`Nav/WalkPaths.lua`): SoupEngine's baked legs that end on the
  spot, the one passing nearest you. Within 40 yards: the next corner ahead
  (corners within 8 yards count as passed). Further off: the nearest point
  on the walk, to lead you back.
- **SoupNav's zone graphs** (`Nav/WalkGraph.lua`, new): when nothing is baked
  to the spot (the first spot in a new zone, the gap SoupEngine leaves at
  zone borders) or you're more than 40 yards off every baked walk, A* on the
  zone's graph from `OpenXP_Nav/Graphs` (`NAV.packed` + `NAV.Unpack`) from
  where you stand to the spot, simplified to corners 3 yards off a straight
  line, kept while you stay on it and worked out again (at most once a
  second) when you leave it. Graph nodes are world yards; SoupNav's
  `data/frames.json` frames (copied into `WalkGraph.lua`) turn them into map %.
  A few ms per walk, even in the Barrens.
- **Route line** (`Nav/MapDraw.lua`, world map and minimap): you, along the
  walk to the first stop, then the baked walk (or a graph walk) between each
  pair of the next few stops. Where there's no walk the line stops: no
  straight lines and no terrain pathing.
- **Arrival** (2026-11-19): on a walk the arrow aims 18 yards further along
  it (`WalkPaths.Carrot`), so it swings round each corner smoothly instead of
  snapping, and shows how much of the walk is left. "Here" is only about the
  real spot (or the pinpointed mob below), never a corner on the way, and
  stays on until you're 13 yards off again, so it can't flicker. The pointer
  eases to new headings.
- **Kill and loot steps** (`Areas.Focus`): you walk to the step's spot; inside
  its kill/loot area the arrow says "In the area" with a check. When the step
  needs a mob or object with only one to three spawns near its spot (a named
  mob like Gobbler, a chest), the arrow goes straight to the nearest one
  instead, and its nameplate gets the boss marker.
- **Route line**: tidied before it's drawn (dropped spikes where a walk steps
  out and straight back, wiggles too small to matter), joined to the walk
  where it passes nearest you without skipping corners, on a dark casing.
  Since 2026-11-20 a spike is a turn back shorter than 3 yards on the ground
  (scaled to the map or minimap), so the switchbacks and doorway turns the
  smoother walks keep (sharp turns with legs of 10 yards and more) stay.
- **Pinpoints from OpenXP_Nav** (2026-11-20): `Areas.Pinpoints` uses
  SoupEngine's `targets` for a goal's `quest:obj` when there are any, else
  Questie's spawns as before. The arrow follows the baked walk from the
  step's spot to the target, the route line goes there too, and the arrow
  says "(upstairs)" (6+ yards above the spot's floor), "(in a cave)" (6+
  yards below) or "(inside)" (indoors at about the spot's level while the
  spot is outdoors).
- **After a death** (2026-11-20): while you're a ghost and for 2 minutes
  after you're back, walks starting at a key in `graveyards` come first;
  otherwise the guide's own walks do (the graveyard walks are the fallback).
  `/oxp nav` says which kind of walk the arrow has.
- **Removed** while it's on: `/oxp path`, `/oxp wall`, and the "Plan trips to
  other zones" and "Route style" settings. New: `/oxp nav` says whether
  OpenXP_Nav loaded and what walk the arrow has to this step's spot.

Checked in the headless client with the real Alliance export and Elwynn's
graph: standing on each Elwynn 1-11 spot facing the next one, 80 of 82 got a
route line and 73 an arrow corner, no Lua errors. Still missing: walks between
zones (the arrow points straight until you're in the step's zone).

### Ideas for later (not approved, not built)

- Floors for the guide's own spots (only pinpointed targets say "upstairs"
  or "in a cave" so far).

## For SoupEngine / SoupNav (asked for by Matt, not OpenXP's to build)

- The shape of the walks: wall hugging, detours and wiggles come from the
  corners SoupEngine bakes (and SoupNav's graph). OpenXP only tidies tiny
  spikes when it draws them.
- Done 2026-11-20: exact boss, rare and chest spots with their floors
  (`targets`), walks from graveyards, and continuous walks across zone borders.

## Known issues (SoupNav side, not fixed here)

SoupNav is being fixed separately; these were open when this was written.


- Zone meshes used to stop at zone edges; since the 2026-11-20 export the walks are continuous across borders.
- Floors pick the ground above mines (Goldtooth, Fargodeep), because guide
  spots have no height.
- Since SoupNav's latest `Unpack.lua` (it now sets `NAV.Unpack` itself),
  SoupEngine copies it as is (SoupEngine branch `openxp-nav-readme`).
- The 2026-11-20 export still has a few walks SoupNav can't finish (Zephras
  Isle, Wetlands 36.6,52.3, Eastern Plaguelands 81.5,44.0, Blasted Lands
  63.9,40.9) and no walk between Loch Modan / Redridge and the Wetlands;
  see SoupEngine's `build/release-export*.log`.
