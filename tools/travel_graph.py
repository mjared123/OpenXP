"""Travel times between quest hubs, for the route planner.

The planner used to count every trip as 8 minutes (same continent) or 20
(across the sea), and the guide always said "Fly to X". Now trips are worked
out in minutes over the real network, the same one the in-game arrow uses:

- flights: DB/forever/flightData.lua (addon.FPDB, seconds per flight) plus
  FLY_EXTRA for talking to the flight master and landing; only flight paths
  you already have (from the 1-20 guides' .fp steps and hubs you've visited);
- boats, zeppelins and the tram: DB/travel.lua (seconds, waiting included);
- riding from a flight master to a hub that has none (the hub's `ride`
  minutes, from its `anchors`).

The cheapest way wins, by time, and the guide's travel step names its legs:
"Take the boat from Menethil Harbor to Theramore" instead of a flight and a
long run.
"""
import heapq
import math
import os
import re

from lupa import luajit21 as lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLY_EXTRA = 20 / 60.0     # minutes: talking to the flight master, landing
DOCK_WALK = 1.0           # minutes: from a town's flight master to its dock
CITY_WALK = 2.0           # minutes: from a capital's flight master to the tram
RUNNING, MOUNTED = 7.0, 11.2  # yards per second (mount at 40)
RIDE_FACTOR = 1.5         # roads wind; riding isn't a straight line
MAX_ZONES_RIDE = 1
MAX_RIDE = 6500           # yards (straight line): further than this, don't plan a ride between towns
# Towns you can't ride to: Feathermoon is on an island (boat from the coast).
NO_RIDE = {"Feathermoon"}


def _load_lua(path, game="FOREVER"):
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    addon = rt.eval("{}")
    addon.game = game
    rt.execute("function _run(f, a) return f('OpenXP', a) end")
    chunk = rt.eval("loadstring")(open(path, encoding="utf-8").read())
    rt.globals()._run(chunk, addon)
    return addon


def _py(v):
    if lupa.lua_type(v) == "table":
        return {k: _py(v[k]) for k in v.keys()}
    return v


# Docks named apart from their town's flight master.
HARBOR = {"Stormwind Harbor": "Stormwind"}
DOCK = {v: k for k, v in HARBOR.items()}


def short(name):
    """'Menethil Harbor, Wetlands' -> 'Menethil Harbor'; 'the Undercity' -> 'Undercity'."""
    n = name.split(",")[0].strip()
    return n[4:] if n.lower().startswith("the ") else n


class Network:
    def __init__(self, faction):
        self.faction = faction
        fp = _py(_load_lua(os.path.join(ROOT, "DB", "forever", "flightData.lua")).FPDB)[faction]
        self.fp_name = {}   # FPDB id -> short town name
        self.zone = {}      # short town name -> uiMap id
        self.flights = {}   # (town, town) -> minutes
        for a, row in fp.items():
            self.fp_name[a] = short(row["name"])
        for a, row in fp.items():
            for b, secs in row.items():
                if b == "name" or b not in self.fp_name:
                    continue
                key = (self.fp_name[a], self.fp_name[b])
                m = secs / 60.0 + FLY_EXTRA
                self.flights[key] = min(m, self.flights.get(key, m))
                rkey = key[::-1]
                if rkey not in self.flights:
                    self.flights[rkey] = m
        self.towns = set(self.fp_name.values())
        # Riding between flight masters, for towns you haven't got yet (you
        # fly to the closest one you have and ride the rest) and short hops
        # where riding beats waiting for a flight.
        self.pos = {}  # town -> (continent, wx, wy)
        text = open(os.path.join(ROOT, "DB", "forever", "db.lua"), encoding="utf-8").read()
        block = text[text.index("addon.taxiPos = {"):]
        block = block[:block.index("\n}\n") + 3]
        cont = None
        for line in block.split("\n"):
            m = re.match(r"\s*\[(\d+)\] = \{\s*$", line)
            if m:
                cont = int(m.group(1))
                continue
            m = re.match(r"\s*\[(\d+)\] = \{wx = (-?[\d.]+), wy = (-?[\d.]+)", line)
            if m and int(m.group(1)) in self.fp_name:
                self.pos[self.fp_name[int(m.group(1))]] = (cont, float(m.group(2)), float(m.group(3)))
        td = _py(_load_lua(os.path.join(ROOT, "DB", "travel.lua")).travelData)
        for row in fp.values():
            town, _, zone = row["name"].partition(",")
            m = td["fpZone"].get(zone.strip()) or td["fpCity"].get(town.strip())
            if m:
                self.zone[short(row["name"])] = m
        # Zones you can walk between (DB/travel.lua gates), for rides: a ride
        # may cross at most MAX_ZONES_RIDE borders, so it doesn't go straight
        # over the mountains between Ironforge and Searing Gorge.
        self.next_to = {}
        for g in td["gates"].values():
            z = list(g["zones"].values())
            self.next_to.setdefault(z[0], set()).add(z[1])
            self.next_to.setdefault(z[1], set()).add(z[0])
        self.transports = []  # (town a, town b, minutes, kind)
        for t in td["transports"].values():
            if t.get("faction") and t["faction"] != faction:
                continue
            a, b = short(t["an"]), short(t["bn"])
            walk = CITY_WALK if t["kind"] == "tram" else DOCK_WALK
            a, b = HARBOR.get(a, a), HARBOR.get(b, b)
            self.transports.append((a, b, t["secs"] / 60.0 + walk, t["kind"], bool(t.get("oneway"))))

    def borders(self, a, b):
        """Zone borders between two towns, walking (99 when unknown)."""
        za, zb = self.zone.get(a), self.zone.get(b)
        if za is None or zb is None:
            return 99
        seen, ring = {za}, {za}
        for n in range(0, MAX_ZONES_RIDE + 1):
            if zb in ring:
                return n
            ring = {y for x in ring for y in self.next_to.get(x, ())} - seen
            seen |= ring
        return 99

    def ride_minutes(self, a, b, level):
        """Minutes riding (or running) from town a to town b, or None when
        they're on different continents or too far apart to ride."""
        pa, pb = self.pos.get(a), self.pos.get(b)
        if not pa or not pb or pa[0] != pb[0] or a in NO_RIDE or b in NO_RIDE:
            return None
        d = math.hypot(pa[1] - pb[1], pa[2] - pb[2])
        if d > MAX_RIDE or self.borders(a, b) > MAX_ZONES_RIDE:
            return None
        d *= RIDE_FACTOR
        return d / (MOUNTED if level >= 40 else RUNNING) / 60.0

    def route(self, frm, to, known, level=30):
        """Cheapest way from town `frm` to town `to` using the flight paths in
        `known` (short town names). Returns (minutes, legs) or (None, None).
        legs: [(kind, from, to)], kind is fly / boat / zeppelin / tram."""
        if frm == to:
            return 0.0, []
        best = {frm: 0.0}
        prev = {}
        heap = [(0.0, frm)]
        while heap:
            d, cur = heapq.heappop(heap)
            if cur == to:
                break
            if d > best.get(cur, 1e9):
                continue
            edges = []
            if cur in known:
                for (a, b), m in self.flights.items():
                    if a == cur and b in known:
                        edges.append((b, m, "fly"))
            for b in self.towns:
                # ride only to a town whose flight path you don't have yet:
                # between two you have, flying is the plan
                if b != cur and b not in known:
                    m = self.ride_minutes(cur, b, level)
                    if m is not None:
                        edges.append((b, m, "ride"))
            for a, b, m, kind, oneway in self.transports:
                if a == cur:
                    edges.append((b, m, kind))
                elif b == cur and not oneway:
                    edges.append((a, m, kind))
            for b, m, kind in edges:
                nd = d + m
                if nd < best.get(b, 1e9) - 1e-9:
                    best[b] = nd
                    prev[b] = (cur, kind)
                    heapq.heappush(heap, (nd, b))
        if to not in best:
            return None, None
        legs = []
        n = to
        while n != frm:
            p, kind = prev[n]
            legs.append((kind, p, n))
            n = p
        legs.reverse()
        # one flight with stops is still one flight
        merged = []
        for leg in legs:
            if merged and merged[-1][0] == leg[0] and leg[0] in ("fly", "ride"):
                merged[-1] = (leg[0], merged[-1][1], leg[2])
            else:
                merged.append(leg)
        return best[to], merged


def describe(legs):
    """Plain text for a list of legs: 'Fly to Menethil Harbor, then take the
    boat to Theramore'."""
    parts = []
    for kind, a, b in legs:
        if kind == "fly":
            parts.append("fly to %s" % b)
        elif kind == "ride":
            parts.append("ride to %s" % b)
        elif kind == "tram":
            parts.append("take the Deeprun Tram to %s" % b)
        else:
            parts.append("take the %s from %s to %s" % (kind, DOCK.get(a, a), DOCK.get(b, b)))
    if not parts:
        return ""
    text = ", then ".join(parts)
    return text[0].upper() + text[1:]
