"""First draft of a zone's walking terrain from its map picture.

    python tools/terrain_auto.py --questiedb PATH NAME AREA UIMAP WIDTH HEIGHT MAP.jpg

Writes tools/terrain_zones/<name>.py with an AUTO grid (100 rows of 100
cells, one per 1% of the map) guessed like this:
- green, grey and brown-green land on the map is walkable; the orange
  parchment drawn as mountains (and outside the zone) isn't;
- grey-blue areas are water;
- every cell with a creature or object spawn in it is walkable (and, on
  brown maps where colour doesn't tell land from mountain, the cells
  around it too);
- thin lines across walkable land (roads, labels) are closed up.

The draft is a starting point: look at it over the map (tools/terrain.py
--check) and add BLOCKED / OPEN / WALLS / WATER shapes by hand for cliffs
and passes the colours don't show. Hand shapes win over AUTO.

The map picture is the zone's world map (for example the one wowhead shows
for the zone). Needs Pillow.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
N = 100


def classify(path):
    from PIL import Image
    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    cnt = [[[0, 0, 0] for _ in range(N)] for _ in range(N)]
    for yy in range(H):
        y = min(N - 1, yy * N // H)
        for xx in range(W):
            x = min(N - 1, xx * N // W)
            r, g, b = px[xx, yy]
            c = cnt[y][x]
            c[2] += 1
            if b > 75 and max(r, g, b) < 170 and max(r, g, b) - min(r, g, b) < 55:
                c[1] += 1           # grey-blue, not as bright as snow or sand: water
            elif g > r - 14:
                c[0] += 1           # green land
    grid = []
    for row in cnt:
        out = []
        for land, water, n in row:
            if water / n > 0.5:
                out.append("~")
            elif (land + water) / n > 0.4:
                out.append(".")
            else:
                out.append("#")
        grid.append(out)
    return grid


def neighbours(x, y):
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if (dx or dy) and 0 <= x + dx < N and 0 <= y + dy < N:
                yield x + dx, y + dy


def close_gaps(grid):
    """Walkable cells grow by one and shrink back by one: roads and labels
    one or two cells wide stop cutting the land in two."""
    walk = [[grid[y][x] != "#" for x in range(N)] for y in range(N)]
    grown = [[walk[y][x] or any(walk[b][a] for a, b in neighbours(x, y)) for x in range(N)] for y in range(N)]
    shrunk = [[grown[y][x] and all(grown[b][a] for a, b in neighbours(x, y)) for x in range(N)] for y in range(N)]
    for y in range(N):
        for x in range(N):
            if grid[y][x] == "#" and shrunk[y][x]:
                grid[y][x] = "."


def drop_specks(grid, kind, keep, size):
    """Turn little islands of `kind` (under `size` cells) into `keep`."""
    seen = set()
    for y in range(N):
        for x in range(N):
            if grid[y][x] != kind or (x, y) in seen:
                continue
            comp, todo = [], [(x, y)]
            seen.add((x, y))
            while todo:
                c = todo.pop()
                comp.append(c)
                for n in neighbours(*c):
                    if n not in seen and grid[n[1]][n[0]] == kind:
                        seen.add(n)
                        todo.append(n)
            if len(comp) < size:
                for a, b in comp:
                    grid[b][a] = keep


def spawn_cells(db, area):
    import build_route as B
    cells = set()
    for n in db["n"].values():
        for x, y in B.spawns_in(n, area, 7):
            cells.add((int(x), int(y)))
    for o in db["o"].values():
        for x, y in B.spawns_in(o, area, 4):
            cells.add((int(x), int(y)))
    return {c for c in cells if 0 <= c[0] < N and 0 <= c[1] < N}


def draft(path, cells):
    grid = classify(path)
    # Desert, barrens and badlands maps are brown like the mountains, so the
    # colours say little there: walk wherever mobs and objects are, and a
    # little around them.
    green = sum(1 for x, y in cells if grid[y][x] != "#") / max(1, len(cells))
    reach = 0 if green >= 0.6 else 2
    for x, y in cells:
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                a, b = x + dx, y + dy
                if 0 <= a < N and 0 <= b < N and dx * dx + dy * dy <= reach * reach + 1 and grid[b][a] == "#":
                    grid[b][a] = "."
    close_gaps(grid)
    drop_specks(grid, "#", ".", 6)     # labels and icons in the middle of land
    drop_specks(grid, ".", "#", 4)     # specks of green in the mountains
    drop_specks(grid, "~", ".", 3)
    return ["".join(r) for r in grid]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    ap.add_argument("--dump", help="OpenXP.lua with /oxp questdump (or the cached copy is used)")
    ap.add_argument("name")
    ap.add_argument("area", type=int)
    ap.add_argument("uimap", type=int)
    ap.add_argument("width", type=float, help="zone width in yards")
    ap.add_argument("height", type=float, help="zone height in yards")
    ap.add_argument("image")
    ap.add_argument("--force", action="store_true", help="overwrite an existing zone file")
    a = ap.parse_args()
    sys.path.insert(0, HERE)
    import build_route as B
    db = B.load_db(a.questiedb)
    try:
        db = B.merge_db(db, B.load_dump_cached(a.dump or "-", a.questiedb))
    except SystemExit:
        pass
    rows = draft(a.image, spawn_cells(db, a.area))
    fn = os.path.join(HERE, "terrain_zones", a.name.lower().replace(" ", "_").replace("'", "") + ".py")
    if os.path.exists(fn) and not a.force:
        sys.exit("%s exists: --force to overwrite (hand shapes would be lost)" % fn)
    lines = ['"""%s walking terrain (see tools/terrain.py for the format)."""' % a.name, "",
             "NAME = %r" % a.name, "AREA = %d" % a.area, "UIMAP = %d" % a.uimap,
             "SIZE = (%g, %g)  # yards across, yards top to bottom" % (a.width, a.height), "",
             "# Hand-drawn fixes on top of AUTO (map coordinates 0-100).",
             "BLOCKED = []", "OPEN = []", "WALLS = []", "WATER = []", "LAND = []", "",
             "# Drafted by tools/terrain_auto.py from the map: . walkable  # blocked  ~ water",
             "AUTO = ["]
    lines += ['    "%s",' % r for r in rows]
    lines.append("]")
    with open(fn, "w", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", fn)


if __name__ == "__main__":
    main()
