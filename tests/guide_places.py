#!/usr/bin/env python3
"""Catch guide steps that send you to the wrong place.

1. Every map point in world coordinates (".goto 1429/0,x,y") must be two
   numbers (a typo like "-623.92.00" breaks the step).
2. A point's map must match the maps of the points around it: a point
   tagged Felwood that sits among Darkshore points really is in Darkshore,
   and the "Getting there" directions would send players to the wrong zone.
3. In the 1-20 guides, a step on the other continent between two steps on
   this one is almost always a copy-paste from another race's guide (a Human
   Hunter sent from Goldshire to Teldrassil for arrows).

Known, correct cases go in ALLOWED as "file:step text" snippets.
"""
import collections
import glob
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KALIMDOR = {1411, 1412, 1413, 1414, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445,
            1446, 1447, 1448, 1449, 1450, 1451, 1452, 1454, 1456, 1457}
# Zones whose map also holds a city or a border town, so their points sit
# next to the city's points and that's fine.
PARENT = {(1438, 1457), (1420, 1458), (1426, 1455), (1429, 1436), (1414, 1454),
          (1411, 1454), (1429, 1453), (1412, 1456)}
WORLD = re.compile(r"\.(?:goto|waypoint)\s+(\d+)/(\d+),\s*([^,\s]+),\s*([^,\s-]+(?:-[^,\s]*)?|-[^,\s]+)")


def files(pattern):
    return sorted(glob.glob(os.path.join(ROOT, "Guides", pattern)))


def main():
    bad = []
    pts = []
    for f in files("forever/*.lua") + files("openxp/*.lua"):
        name = os.path.basename(f)
        for ln, line in enumerate(open(f, encoding="utf-8"), 1):
            if line.lstrip().startswith("--"):
                continue
            for m in WORLD.finditer(line):
                x, y = m.group(3), m.group(4).split("--")[0]
                try:
                    pts.append((int(m.group(1)), int(m.group(2)), float(x), float(y), name, ln))
                except ValueError:
                    bad.append(f"{name}:{ln}: map point isn't two numbers: {line.strip()[:80]}")

    by_inst = collections.defaultdict(list)
    for p in pts:
        by_inst[p[1]].append(p)
    for group in by_inst.values():
        for p in group:
            near = sorted(((q[2] - p[2]) ** 2 + (q[3] - p[3]) ** 2, q[0]) for q in group if q is not p)
            near = [n for n in near if n[0] > 0][:15]
            if not near:
                continue
            maps = collections.Counter(z for _, z in near)
            top, count = maps.most_common(1)[0]
            if maps.get(p[0], 0) == 0 and count >= 10 and math.sqrt(near[0][0]) < 150 \
                    and (p[0], top) not in PARENT and (top, p[0]) not in PARENT:
                bad.append(f"{p[4]}:{p[5]}: point is on map {p[0]} but sits among map {top} points")

    for f in files("forever/*.lua"):
        name = os.path.basename(f)
        text = open(f, encoding="utf-8").read()
        for guide in text.split("RegisterGuide(")[1:]:
            steps = []
            for s in guide.split("\nstep")[1:]:
                m = re.search(r"^\s*\.goto (\d+)", s, re.M)
                steps.append((s.split("\n", 1)[0].strip(), int(m.group(1)) if m else None, s))
            cont = [None if z is None else (z in KALIMDOR) for _, z, _ in steps]
            for i, (head, z, s) in enumerate(steps):
                # travel steps (flights, boats, hearth) cross on purpose
                if z is None or re.search(r"\.zone|\.fly|\.hs|[Bb]oat|[Pp]ortal|[Tt]ram", s):
                    continue
                before = next((c for c in reversed(cont[:i]) if c is not None), None)
                after = next((c for c in cont[i + 1:] if c is not None), None)
                if before is not None and before == after and cont[i] != before:
                    gname = re.search(r"#name (.*)", guide)
                    bad.append(f"{name} ({gname.group(1) if gname else '?'}): step {head!r} jumps to the other continent and straight back")

    for b in bad:
        print("FAIL " + b)
    if not bad:
        print("ok   guide map points are on the right map and continent")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
