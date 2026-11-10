"""Walking terrain for the arrow and the route builder.

Addons can't see the game's terrain, so the arrow points in a straight line
and walks you into cliffs. This file describes, per zone, where you can't
walk (mountains, cliffs), where you'd have to swim, and where the packs of
mobs are, so both the route builder (walking times) and the arrow (which
way to point) can go around them.

Everything is in zone map coordinates (0-100, like a .goto line). Shapes are
drawn by hand from the zone map; mob packs are summarised from spawn data
(a handful of circles, not the spawns themselves).

    blocked   polygons you can't walk through (mountains, outside the zone)
    open      polygons carved back out of blocked ones (a valley, a road)
    walls     polylines you can't cross (cliff edges drawn as a line)
    land      polygons where the map's grey-blue isn't water (snow, dark forest)
    water     polygons you have to swim through (slow)
    roads     polylines of roads and bridges: always walkable, and the arrow
              and the map's route line keep to them rather than cut corners
    packs     (x, y, radius, level, name): groups of hostile mobs

`python tools/terrain.py --lua` writes DB/terrain.lua for the addon.
"""
import heapq
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

GRID = 100          # cells per side; a cell is 1% of the map
WATER_COST = 3.0    # swimming is about three times slower than running
# Extra cost per cell for walking near a pack, by how many levels the pack
# is above you. Killing on the way is fine for packs at your level.
DANGER = {3: 3.0, 4: 10.0}   # levels above you -> extra cost per cell
DANGER_MAX = 40.0                     # 5+ levels above: go almost any way around
# The in-game arrow's costs (Terrain.lua), for path(..., arrow=True): roads
# count for less than their length so the way keeps to them, and packs near
# your level cost a little so the way doesn't walk through them either.
ROAD_COST = 0.65
DANGER_ARROW = {-2: 1.0, -1: 1.0, 0: 1.0, 1: 1.5, 2: 2.0, 3: 3.0, 4: 10.0}

def _load_zones():
    """Each file in tools/terrain_zones/ describes one zone."""
    import importlib.util
    zones = {}
    d = os.path.join(HERE, "terrain_zones")
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".py") or fn.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location("terrain_zone_" + fn[:-3], os.path.join(d, fn))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        zones[m.NAME] = dict(
            area=m.AREA, uimap=m.UIMAP,
            # yards per 1% of the map, for turning grid steps into walking time
            yards=(m.SIZE[0] / 100.0, m.SIZE[1] / 100.0),
            blocked=getattr(m, "BLOCKED", []), open=getattr(m, "OPEN", []),
            walls=getattr(m, "WALLS", []), water=getattr(m, "WATER", []),
            auto=getattr(m, "AUTO", None), land=getattr(m, "LAND", []),
            roads=getattr(m, "ROADS", []),
            pack_min_level=getattr(m, "PACK_MIN_LEVEL", 20),
            packs=[])
    return zones


ZONES = _load_zones()

# Mob packs per zone, summarised from spawn data by --packs (tools/terrain_packs.py).
try:
    from terrain_packs import PACKS
except ImportError:  # imported from elsewhere
    sys.path.insert(0, HERE)
    from terrain_packs import PACKS
for _name, _packs in PACKS.items():
    if _name in ZONES:
        ZONES[_name]["packs"] = _packs


# ---------------------------------------------------------------------------
# Grid
# ---------------------------------------------------------------------------

def _inside(poly, x, y):
    n, c = len(poly), False
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def _seg_cells(a, b):
    """Grid cells a segment passes through (sampled finely)."""
    n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 4) + 1
    out = set()
    for i in range(n + 1):
        t = i / n
        out.add((int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t)))
    return out


ROAD_HALF = 0.75    # cells: a road covers the cells whose middle is this close to it


def road_cells(roads):
    """Cells a list of road polylines covers."""
    out = set()
    for road in roads:
        for a, b in zip(road, road[1:]):
            for x in range(int(min(a[0], b[0]) - 2), int(max(a[0], b[0]) + 3)):
                for y in range(int(min(a[1], b[1]) - 2), int(max(a[1], b[1]) + 3)):
                    if 0 <= x < GRID and 0 <= y < GRID and \
                            _seg_dist((x + 0.5, y + 0.5), a, b) <= ROAD_HALF:
                        out.add((x, y))
    return out


def _seg_dist(p, a, b):
    vx, vy = b[0] - a[0], b[1] - a[1]
    l2 = vx * vx + vy * vy
    t = 0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * vx + (p[1] - a[1]) * vy) / l2))
    return math.hypot(a[0] + vx * t - p[0], a[1] + vy * t - p[1])


def build_grid(z):
    """Cell kinds: '.' open, '#' blocked, '~' water, '=' road or bridge.
    grid[y][x]. The route builder walks '=' like '.'; the addon prefers it."""
    auto = z.get("auto")
    g = [list(auto[y]) if auto else ["." for _ in range(GRID)] for y in range(GRID)]
    for y in range(GRID):
        for x in range(GRID):
            cx, cy = x + 0.5, y + 0.5
            inside_open = any(_inside(p, cx, cy) for p in z.get("open", ()))
            if any(_inside(p, cx, cy) for p in z.get("blocked", ())) and not inside_open:
                g[y][x] = "#"
            elif any(_inside(p, cx, cy) for p in z.get("water", ())):
                g[y][x] = "~"
            elif inside_open:
                g[y][x] = "."

            elif g[y][x] == "~" and any(_inside(p, cx, cy) for p in z.get("land", ())):
                g[y][x] = "."
    for wall in z.get("walls", ()):
        for a, b in zip(wall, wall[1:]):
            for x, y in _seg_cells(a, b):
                if 0 <= x < GRID and 0 <= y < GRID:
                    g[y][x] = "#"
    for x, y in road_cells(z.get("roads", ())):
        g[y][x] = "="
    return g


def danger_grid(z, level, arrow=False):
    """Extra cost per cell for a character of this level."""
    d = {}
    if level is None:
        return d
    ky = z["yards"][0] / z["yards"][1]
    table = DANGER_ARROW if arrow else DANGER
    for (px, py, r, lvl, _name) in z.get("packs", ()):
        over = lvl - level
        if over < min(table):
            continue
        cost = DANGER_MAX if over >= 5 else table[over]
        for y in range(int(py - r * ky) - 1, int(py + r * ky) + 2):
            for x in range(int(px - r) - 1, int(px + r) + 2):
                if 0 <= x < GRID and 0 <= y < GRID:
                    if math.hypot(x + 0.5 - px, (y + 0.5 - py) / ky) <= r:
                        d[(x, y)] = max(d.get((x, y), 0), cost)
    return d


class Terrain:
    def __init__(self, zone):
        self.zone = zone
        self.z = ZONES[zone]
        self.grid = build_grid(self.z)
        self.kx, self.ky = self.z["yards"]
        self._danger = {}
        self._cache = {}

    def kind(self, x, y):
        if 0 <= x < GRID and 0 <= y < GRID:
            return self.grid[y][x]
        return "#"

    def danger(self, level, arrow=False):
        key = (None if level is None else int(level), arrow)
        if key not in self._danger:
            self._danger[key] = danger_grid(self.z, key[0], arrow)
        return self._danger[key]

    def cell_cost(self, k, d, arrow=False):
        """Cost per yard of a cell of kind k with danger d. With the arrow's
        costs a road ignores packs near your level (danger under 3) and
        counts the ones well above you as 1 at most."""
        if arrow and k == "=":
            d = 0 if d < 3 else min(d, 1.0)  # Terrain.lua's ROAD_DANGER
        return self.factor(k, arrow) + d

    def factor(self, k, arrow=False):
        """Cost per yard of a cell kind (not counting danger)."""
        if k == "~":
            return WATER_COST
        if k == "=" and arrow:
            return ROAD_COST
        return 1.0

    def is_road(self, x, y):
        return self.kind(x, y) == "="

    def _nearest_open(self, c):
        if self.kind(*c) != "#":
            return c
        best = None
        for r in range(1, 8):
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    p = (c[0] + dx, c[1] + dy)
                    if self.kind(*p) != "#":
                        dd = dx * dx + dy * dy
                        if best is None or dd < best[0]:
                            best = (dd, p)
            if best:
                return best[1]
        return c

    def path(self, a, b, level=None, arrow=False):
        """(yards, [points]) walking from a to b (map coords) around blocked
        cells and, for this level, around dangerous packs. yards counts the
        detour and swimming, plus the danger cost (as extra yards).
        arrow=True: the in-game arrow's costs (keeps to roads, steers clear
        of packs near your level); the cost is then effort, not yards."""
        ca = self._nearest_open((int(a[0]), int(a[1])))
        cb = self._nearest_open((int(b[0]), int(b[1])))
        key = (ca, cb, None if level is None else int(level), arrow)
        if key in self._cache:
            return self._cache[key]
        danger = self.danger(level, arrow)
        kx, ky = self.kx, self.ky
        diag = math.hypot(kx, ky)
        steps = [(1, 0, kx), (-1, 0, kx), (0, 1, ky), (0, -1, ky),
                 (1, 1, diag), (1, -1, diag), (-1, 1, diag), (-1, -1, diag)]

        def h(c):
            return math.hypot((c[0] - cb[0]) * kx, (c[1] - cb[1]) * ky)
        best = {ca: 0.0}
        came = {}
        heap = [(h(ca), 0.0, ca)]
        while heap:
            _, g, c = heapq.heappop(heap)
            if c == cb:
                break
            if g > best.get(c, 1e18):
                continue
            for dx, dy, step in steps:
                n = (c[0] + dx, c[1] + dy)
                k = self.kind(*n)
                if k == "#":
                    continue
                if dx and dy and (self.kind(c[0] + dx, c[1]) == "#" or self.kind(c[0], c[1] + dy) == "#"):
                    continue  # no cutting corners through a wall
                cost = step * self.cell_cost(k, danger.get(n, 0), arrow)
                ng = g + cost
                if ng < best.get(n, 1e18):
                    best[n] = ng
                    came[n] = c
                    heapq.heappush(heap, (ng + h(n), ng, n))
        if cb not in best:
            d = math.hypot((b[0] - a[0]) * kx, (b[1] - a[1]) * ky)
            res = (d, [a, b])
        else:
            cells = [cb]
            while cells[-1] != ca:
                cells.append(came[cells[-1]])
            cells.reverse()
            pts = [a] + [(x + 0.5, y + 0.5) for x, y in self._smooth(cells, danger, best, arrow)][1:-1] + [b]
            res = (best[cb], pts)
        self._cache[key] = res
        return res

    def line_cost(self, a, b, danger, arrow=False):
        """Cost of the straight line between cell middles a and b, sampled
        like the addon does; None when it crosses a blocked cell."""
        steps = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 4) + 1
        each = math.hypot((b[0] - a[0]) * self.kx, (b[1] - a[1]) * self.ky) / steps
        total = 0.0
        for i in range(steps + 1):
            t = i / steps
            x = int(a[0] + 0.5 + (b[0] - a[0]) * t)
            y = int(a[1] + 0.5 + (b[1] - a[1]) * t)
            k = self.kind(x, y)
            if k == "#":
                return None
            if i:
                total += each * self.cell_cost(k, danger.get((x, y), 0), arrow)
        return total

    def _smooth(self, cells, danger, best, arrow=False):
        """Straight lines over runs of cells that cost no more than the run
        (2% slack): never through walls, and no cutting off a road through
        the woods when that's dearer."""
        out = [cells[0]]
        i = 0
        while i < len(cells) - 1:
            j = len(cells) - 1
            while j > i + 1:
                lc = self.line_cost(cells[i], cells[j], danger, arrow)
                if lc is not None and lc <= (best[cells[j]] - best[cells[i]]) * 1.02 + 0.01:
                    break
                j -= 1
            out.append(cells[j])
            i = j
        return out

    def distances(self, a, level=None, arrow=False):
        """Walking cost in yards from map point a to every cell (Dijkstra,
        same costs as path()). Cached per start cell and level."""
        ca = self._nearest_open((int(a[0]), int(a[1])))
        key = ("d", ca, None if level is None else int(level), arrow)
        if key in self._cache:
            return self._cache[key]
        danger = self.danger(level, arrow)
        kx, ky = self.kx, self.ky
        diag = math.hypot(kx, ky)
        steps = [(1, 0, kx), (-1, 0, kx), (0, 1, ky), (0, -1, ky),
                 (1, 1, diag), (1, -1, diag), (-1, 1, diag), (-1, -1, diag)]
        best = {ca: 0.0}
        heap = [(0.0, ca)]
        while heap:
            g, c = heapq.heappop(heap)
            if g > best[c]:
                continue
            for dx, dy, step in steps:
                n = (c[0] + dx, c[1] + dy)
                k = self.kind(*n)
                if k == "#":
                    continue
                if dx and dy and (self.kind(c[0] + dx, c[1]) == "#" or self.kind(c[0], c[1] + dy) == "#"):
                    continue
                ng = g + step * self.cell_cost(k, danger.get(n, 0), arrow)
                if ng < best.get(n, 1e18):
                    best[n] = ng
                    heapq.heappush(heap, (ng, n))
        self._cache[key] = best
        return best

    def cost(self, a, b, level=None, arrow=False):
        """Walking cost in yards from a to b; the straight line if b can't
        be reached on the grid."""
        d = self.distances(a, level, arrow)
        cb = self._nearest_open((int(b[0]), int(b[1])))
        if cb in d:
            return d[cb]
        return self.walk_yards(a, b)

    def walk_yards(self, a, b):
        return math.hypot((b[0] - a[0]) * self.kx, (b[1] - a[1]) * self.ky)


_terrains = {}


def for_zone(zone):
    if zone not in ZONES:
        return None
    if zone not in _terrains:
        _terrains[zone] = Terrain(zone)
    return _terrains[zone]


# ---------------------------------------------------------------------------
# Mob packs from spawn data
# ---------------------------------------------------------------------------

def packs_from_db(db, area, min_level=20, radius=2.0, min_size=3):
    """Group hostile, non-rare mobs into circles: (x, y, r, max level, name).
    Only the summary goes into the addon, never the spawns."""
    import build_route as B
    pts = []
    for nid, n in db["n"].items():
        sp = B.spawns_in(n, area, 7)
        if not sp:
            continue
        react = B.li(n, 13)
        if react and ("A" in str(react) or "H" in str(react)):
            continue
        if (B.li(n, 6) or 0) in (2, 3, 4):  # rare, boss, rare: alone, not a pack
            continue
        lo, hi = B.li(n, 4) or 0, B.li(n, 5) or B.li(n, 4) or 0
        lvl = (lo + hi + 1) // 2
        if lvl < min_level:
            continue
        for p in sp:
            pts.append((p[0], p[1], lvl, B.li(n, 1)))
    # simple greedy clustering on the highest levels first
    pts.sort(key=lambda p: -p[2])
    used = [False] * len(pts)
    packs = []
    for i, p in enumerate(pts):
        if used[i]:
            continue
        group = [j for j, q in enumerate(pts) if not used[j] and math.dist(p[:2], q[:2]) <= radius * 2
                 and q[2] >= p[2] - 1]
        if len(group) < min_size:
            continue
        for j in group:
            used[j] = True
        xs = [pts[j][0] for j in group]
        ys = [pts[j][1] for j in group]
        cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
        r = max(math.dist((cx, cy), pts[j][:2]) for j in group) + 1.0
        names = {}
        for j in group:
            names[pts[j][3]] = names.get(pts[j][3], 0) + 1
        name = max(names, key=names.get)
        lv = sorted(pts[j][2] for j in group)
        packs.append((round(cx, 1), round(cy, 1), round(r, 1), lv[len(lv) // 2], name))
    return packs


# ---------------------------------------------------------------------------
# Lua output
# ---------------------------------------------------------------------------

def to_lua():
    out = ["local _, addon = ...", "",
           "-- Walking terrain for the arrow: built by tools/terrain.py, don't edit.",
           "-- grid rows (y = 1..%d), one character per 1%% of the map:" % GRID,
           "--   . open   # blocked (mountain, cliff, outside the zone)   ~ water   = road",
           "-- packs: {x, y, radius, level} groups of hostile mobs, for going around",
           "-- the ones well above your level.",
           "", "addon.terrainData = {"]
    for name, z in ZONES.items():
        g = build_grid(z)
        out.append("    [%d] = { -- %s" % (z["uimap"], name))
        out.append("        area = %d," % z["area"])
        out.append("        yards = {%.1f, %.1f}," % z["yards"])
        out.append("        rows = {")
        for row in g:
            out.append('            "%s",' % "".join(row))
        out.append("        },")
        out.append("        packs = {")
        for (x, y, r, lvl, pname) in z.get("packs", ()):
            out.append("            {%.1f, %.1f, %.1f, %d}, -- %s" % (x, y, r, lvl, pname))
        out.append("        },")
        out.append("    },")
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--lua", action="store_true", help="write DB/terrain.lua")
    ap.add_argument("--packs", help="QuestieDB path: print pack circles for each zone")
    args = ap.parse_args()
    if args.packs:
        sys.path.insert(0, HERE)
        import build_route as B
        db = B.load_db(args.packs)
        lines = ['"""Mob packs per zone for tools/terrain.py: written by',
                 '`python tools/terrain.py --packs QUESTIEDB`, do not edit. Circles of',
                 '(x, y, radius, highest level, most common mob), not the spawns."""',
                 "", "PACKS = {"]
        for name, z in ZONES.items():
            lines.append("    %r: [" % name)
            for p in packs_from_db(db, z["area"], min_level=z["pack_min_level"]):
                lines.append("        %r," % (p,))
            lines.append("    ],")
        lines.append("}")
        with open(os.path.join(HERE, "terrain_packs.py"), "w") as f:
            f.write("\n".join(lines) + "\n")
        print("wrote tools/terrain_packs.py")
    if args.lua:
        path = os.path.join(ROOT, "DB", "terrain.lua")
        with open(path, "w", newline="\r\n") as f:
            f.write(to_lua())
        print("wrote", path)


if __name__ == "__main__":
    main()
