#!/usr/bin/env python3
"""Generate OpenXP leveling guides from quest data.

Reads Questie's quest data (github.com/Questie/QuestieDB, plus /oxp questdump
for WoW Forever's new quests) and a route file (tools/routes/*.py), and
writes guide files in the RestedXP/OpenXP guide format.

The route builder plays the route in its head. It tracks your XP as you go
(quest XP and kills, both estimated), so a quest only joins the route once
it's at most LEVELS_ABOVE over your level, gray quests are left out, and
objectives above your level count as slower. Inside a zone it always does the
cheapest next thing (accept, objective, or turn in), respecting quest chains
and the quest log limit; steps at the same spot are merged.

Route files come in two kinds:
- HUBS (alliance.py, horde.py): the places you can quest from. The builder
  picks the zone order itself, going where the next visit gives the most XP
  per minute (with a one-visit lookahead, so a boat trip counts what's on the
  other side), and comes back to zones as their higher quests open up.
- SECTIONS (the *_classic.py files): a fixed zone order.

The output is a draft meant to be played, then tuned.

Usage:
    python3 tools/build_route.py --questiedb PATH/TO/QuestieDB --dump OpenXP.lua tools/routes/alliance.py
    python3 tools/build_route.py --questiedb PATH/TO/QuestieDB tools/routes/alliance_21_30_classic.py
"""
import argparse
import copy
import glob
import importlib.util
import math
import os
import pickle
import re
import sys

from lupa import luajit21 as lupa

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import terrain as TERRAIN  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

ALLIANCE_RACES = 1 | 4 | 8 | 64  # Human, Dwarf, Night Elf, Gnome
HORDE_RACES = 2 | 16 | 32 | 128
CLASS_BITS = {
    "Warrior": 1, "Paladin": 2, "Hunter": 4, "Rogue": 8, "Priest": 16,
    "Shaman": 64, "Mage": 128, "Warlock": 256, "Druid": 1024,
}
ALL_CLASSES = sum(CLASS_BITS.values())
QUEST_LOG_LIMIT = 20
# Quests whose objectives are in another zone are picked up only when the
# route reaches that zone within this many sections.
CARRY_AHEAD = 6

# ---------------------------------------------------------------------------
# Level model
#
# The route builder plays the route in its head: it tracks the XP you'd have
# at every step, so a quest only joins the route once you're close enough to
# its level, gray quests are left out, and harder quests count as slower.
# Quest XP and kill XP are estimates (Questie's data has no XP rewards), good
# enough to tell a 3-quest zone from a 30-quest one and to name sections by
# the levels you'll really be.
# ---------------------------------------------------------------------------

# XP to go from level L to L+1 (Classic), index L.
XP_TO_NEXT = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800,
              10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
              25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300,
              47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800,
              85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200,
              129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900,
              180800, 187900, 195000, 202300, 209800]
MAX_LEVEL = 60
# Accept a quest only once it's at most this many levels above you.
LEVELS_ABOVE = 2
# Leave a quest out when it's this many levels below you or more (gray: about
# a tenth of the XP).
GRAY_BELOW = 6
# Each level a quest is above you makes its objectives this much slower:
# mobs hit harder, resist more and take longer to kill.
SLOWER_PER_LEVEL = 0.3
# A visit starts once at least this many of its quests are open to you;
# below that the guide asks you to level a little first.
MIN_OPEN = 3
# A zone visit with fewer quests than this isn't worth the trip; the route
# builder leaves it out and keeps its quests for a later visit.
MIN_VISIT = 4
# How many of the best next zones get a look one visit further ahead.
LOOKAHEAD = 8
# ...but never more than this many levels.
MAX_GRIND = 1.5
# Rough minutes, to compare zones by XP per minute: per map-percent walked
# (about 8 minutes across a zone on foot), per objective, per talk.
MINUTES_PER_UNIT = 0.08
MINUTES_PER_UNIT_MOUNTED = 0.05
MINUTES_WORK = {"kill": 5.0, "loot": 6.0, "credit": 2.0, "use": 1.0, "explore": 0.5}
MINUTES_TALK = 0.2
# Getting to the next zone: same continent (flight), other continent (boat
# and flights), plus a zone's own extra ride when it has no flight master.
MINUTES_HOP = 8.0
MINUTES_SEA = 20.0
# Stopping in a capital costs a flight in and out plus the walk inside.
MINUTES_CITY = 12.0
# Quest XP per minute below this share of what grinding mobs gives isn't
# worth the trip; the planner levels a little instead.
GRIND_KILLS_PER_MINUTE = 2.0
WORTH_IT = 0.6
# Rough kills per objective, for the kill XP estimate.
KILLS = {"kill": 10, "loot": 12, "credit": 4, "use": 3, "explore": 1}
# Mobs you kill on the way, per map-percent you travel inside a zone.
TRAVEL_KILLS = 0.15


def xp_at_level(level):
    """Total XP at the start of a level (can be fractional)."""
    whole = int(level)
    base = sum(XP_TO_NEXT[1:whole])
    if whole < MAX_LEVEL:
        base += (level - whole) * XP_TO_NEXT[whole]
    return base


def level_of(xp):
    """Level (with fraction) for a total XP."""
    lvl = 1
    while lvl < MAX_LEVEL and xp >= XP_TO_NEXT[lvl]:
        xp -= XP_TO_NEXT[lvl]
        lvl += 1
    return lvl + (xp / XP_TO_NEXT[lvl] if lvl < MAX_LEVEL else 0)


def quest_xp(qlevel, level):
    """Estimated XP for turning in a quest of qlevel at level."""
    base = max(150, 110 * qlevel - 1000) if qlevel >= 12 else 40 * qlevel + 100
    gap = int(level) - qlevel
    if gap <= 5:
        return base
    return base * {6: 0.8, 7: 0.6, 8: 0.4, 9: 0.2}.get(gap, 0.1)


def _zero_diff(level):
    for top, zd in ((7, 5), (9, 6), (11, 7), (15, 8), (19, 9), (29, 11), (39, 12),
                    (44, 13), (49, 14), (54, 15), (59, 16)):
        if level <= top:
            return zd
    return 17


def mob_xp(mob_level, level):
    """XP for one kill of a normal mob (Classic formula)."""
    level = int(level)
    base = 5 * level + 45
    if mob_level >= level:
        return base * (1 + 0.05 * min(mob_level - level, 4))
    zd = _zero_diff(level)
    return max(0.0, base * (1 - (level - mob_level) / zd))

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def _lua_to_py(v):
    if lupa.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [_lua_to_py(v[k]) for k in range(1, len(keys) + 1)]
        return {k: _lua_to_py(v[k]) for k in keys}
    return v


def _load_table(path, var):
    text = open(path, encoding="utf-8").read()
    body = re.search(r"QuestieDB\.%s = \[\[(.*)\]\]" % var, text, re.S).group(1)
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    parse = rt.eval('function(s) return assert(loadstring("return " .. s))() end')
    out = {}
    for line in body.split("\n"):
        m = re.match(r"^\[(\d+)\] = (\{.*\}),?\s*$", line)
        if m:
            row = parse(m.group(2))
            n = max(row.keys()) if len(list(row.keys())) else 0
            out[int(m.group(1))] = [_lua_to_py(row[i]) if i in row else None for i in range(1, n + 1)]
    return out


# Which game the route is for: "Forever" or "Classic" (Classic Era).
# Set from the route file's GAME; Forever by default.
GAME = "Forever"
# "Alliance" or "Horde"; set from the route file's FACTION.
FACTION = "Alliance"


def load_db(questiedb, game=None):
    game = game or GAME
    suffix = "" if game == "Forever" else "-" + game.lower()
    cache = os.path.join(questiedb, ".openxp-cache%s.pkl" % suffix)
    if os.path.exists(cache):
        return pickle.load(open(cache, "rb"))
    d = os.path.join(questiedb, "data", game)
    pre = game.lower()
    db = {
        "q": _load_table(os.path.join(d, pre + "QuestDB.lua"), "questData"),
        "n": _load_table(os.path.join(d, pre + "NpcDB.lua"), "npcData"),
        "o": _load_table(os.path.join(d, pre + "ObjectDB.lua"), "objectData"),
        "i": _load_table(os.path.join(d, pre + "ItemDB.lua"), "itemData"),
    }
    pickle.dump(db, open(cache, "wb"))
    return db


def load_dump(path):
    """Quest data saved in game by /oxp questdump (the OXPQuestieDump saved
    variable in WTF/Account/<name>/SavedVariables/OpenXP.lua). It has what the
    installed Questie knows, including WoW Forever quests that Questie's
    public data files don't have yet. Same row layout as load_db()."""
    import savedvars  # the file is too big for Lua's constant limit
    d = savedvars.load(path, only="OXPQuestieDump").get("OXPQuestieDump")
    if not d:
        raise SystemExit("no OXPQuestieDump in %s: run /oxp questdump in game, then /reload" % path)

    def py(v):
        if isinstance(v, dict):
            v = {k: x for k, x in v.items() if k != "n"}  # table.pack's count
            keys = list(v)
            if keys and all(isinstance(k, int) and k > 0 for k in keys):
                top = max(keys)
                # arrays, including ones with nil holes like {id, nil, 0};
                # tables keyed by zone id (spawns) start above 1 and stay dicts,
                # like load_db() leaves them
                if top == len(keys) or (1 in v and top <= 10):
                    return [py(v.get(k)) for k in range(1, top + 1)]
            return {k: py(x) for k, x in v.items()}
        return v

    out = {}
    for short, kind in (("q", "quest"), ("n", "npc"), ("o", "object"), ("i", "item")):
        keys = (d.get("keys") or {}).get(kind) or {}
        width = max(keys.values()) if keys else 0
        rows = {}
        for id_, row in (d.get(kind) or {}).items():
            row = {k: x for k, x in row.items() if isinstance(k, int)}
            n = width or (max(row) if row else 0)
            rows[int(id_)] = [py(row.get(i)) for i in range(1, n + 1)]
        out[short] = rows
    return out


def load_dump_cached(path, questiedb):
    """load_dump(), keeping a copy next to the QuestieDB data: the saved
    variable is gone after the addon clears it, and the copy still works."""
    cache = os.path.join(questiedb, ".openxp-dump.pkl")
    try:
        d = load_dump(path)
    except (SystemExit, OSError):
        if os.path.exists(cache):
            print("no /oxp questdump in %s: using the copy from %s" % (path, cache))
            return pickle.load(open(cache, "rb"))
        raise
    pickle.dump(d, open(cache, "wb"))
    return d


def merge_db(base, extra):
    """base with extra's rows on top (extra wins)."""
    if not extra:
        return base
    return {k: {**base.get(k, {}), **extra.get(k, {})} for k in ("q", "n", "o", "i")}


def li(v, i):
    """Lua-style 1-based index into a list or sparse dict."""
    if v is None:
        return None
    if isinstance(v, list):
        return v[i - 1] if 0 < i <= len(v) else None
    return v.get(i)


def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    return [v[k] for k in sorted(v)]

# ---------------------------------------------------------------------------
# Quest model
# ---------------------------------------------------------------------------

class Quest:
    def __init__(self, qid, row):
        self.id = qid
        self.name = li(row, 1)
        self.startedBy = li(row, 2)
        self.finishedBy = li(row, 3)
        self.reqLevel = li(row, 4) or 1
        self.level = li(row, 5) or self.reqLevel
        self.races = li(row, 6) or 0
        self.classes = li(row, 7) or 0
        self.triggerEnd = li(row, 9)
        self.objectives = li(row, 10)
        self.preGroup = as_list(li(row, 12))
        self.preSingle = as_list(li(row, 13))
        self.exclusiveTo = as_list(li(row, 16))
        self.zone = li(row, 17)
        self.reqSkill = li(row, 18)
        self.reqRep = li(row, 19)
        self.specialFlags = li(row, 24) or 0
        self.breadcrumbFor = li(row, 27)

    def alliance(self):
        return self.races == 0 or (self.races & ALLIANCE_RACES) != 0

    def for_faction(self):
        mask = ALLIANCE_RACES if FACTION == "Alliance" else HORDE_RACES
        return self.races == 0 or (self.races & mask) != 0

    def class_tag(self):
        if not self.classes or (self.classes & ALL_CLASSES) == ALL_CLASSES:
            return None
        names = [n for n, b in CLASS_BITS.items() if self.classes & b]
        return "/".join(names)


def spawns_in(entity, zone, spawn_index):
    sp = li(entity, spawn_index)
    if not sp or not isinstance(sp, dict):
        return []
    return [tuple(p) for p in as_list(sp.get(zone)) if p and len(p) == 2 and p[0] >= 0]


class Spawns(list):
    """Spawn points, with a weight for some (`w`: point -> weight). Mobs
    well below the quest's level count for less when looking for the best
    spot: they die fast but they're worth little."""
    def __init__(self, pts=(), w=None):
        super().__init__(pts)
        self.w = w or {}


def _weight(points):
    w = getattr(points, "w", None) or {}
    return lambda q: w.get(q, 1.0)


def cluster_center(points, radius=4.0):
    """Densest spot: the point with the most neighbours within radius, averaged."""
    if not points:
        return None
    wt = _weight(points)
    best, best_n = None, -1
    for p in points:
        n = [q for q in points if math.dist(p, q) <= radius]
        score = sum(wt(q) for q in n)
        if score > best_n:
            best, best_n = n, score
    x = sum(p[0] for p in best) / len(best)
    y = sum(p[1] for p in best) / len(best)
    # Snap to the closest real spawn so the arrow points at something real.
    return min(best, key=lambda p: math.dist(p, (x, y)))

def dense_clusters(points, radius=4.0, keep=4):
    """The densest spots among points, best first: [(point, count)]. Each
    spot is a real spawn near the middle of its group; groups don't overlap,
    and spots with under a third of the best one's mobs are left out."""
    wt = _weight(points)
    left = list(points)
    out = []
    while left and len(out) < keep:
        best, best_n, best_s = None, [], 0
        for p in left:
            n = [q for q in left if math.dist(p, q) <= radius]
            score = sum(wt(q) for q in n)
            if score > best_s:
                best, best_n, best_s = p, n, score
        # other spots only when they're nearly as good: a thin spot means
        # waiting for respawns
        if out and best_s < max(3, out[0][1] * 0.8):
            break
        x = sum(p[0] for p in best_n) / len(best_n)
        y = sum(p[1] for p in best_n) / len(best_n)
        out.append((min(best_n, key=lambda p: math.dist(p, (x, y))), best_s))
        left = [q for q in left if math.dist(q, (x, y)) > radius * 1.5]
    return out

# ---------------------------------------------------------------------------
# Route building
# ---------------------------------------------------------------------------

class Builder:
    def __init__(self, db, done_before, carried):
        self.db = db
        self.done = set(done_before)        # quests turned in before this route
        self.accepted_before = set(carried) # quests in the log from earlier guides
        self.used = set()                   # quests already placed by this route
        self.objectives_done = set()        # carried quests whose objectives are done
        self.carried_ready = set()
        self.xp = 0.0
        self.xp_from = {"quests": 0.0, "kills": 0.0}
        self.minutes = 0.0
        self._cache = {}
        self._quests = None
        self.alts = {}                      # (quest, zone, objective) -> dense spots
        self.site_pts = {}                  # (quest, zone, objective) -> spawn points
        self.rollouts = False               # look ahead when ordering steps (slow)

    file_accepted = set()

    def level(self):
        return level_of(self.xp)

    _STATE = ("done", "used", "accepted_before", "objectives_done", "carried_ready", "xp_from")

    def snapshot(self):
        return {k: copy.copy(getattr(self, k)) for k in self._STATE}, (self.xp, self.minutes)

    def restore(self, saved):
        state, (self.xp, self.minutes) = saved
        for k, v in state.items():
            setattr(self, k, v)

    def breadcrumb_blocked(self, q, cands, accepted, turned):
        """Breadcrumbs (a quest that only sends you to another quest's giver,
        like The Hermit to Abercrombie's Supplies from Darkshire) disappear
        once you've picked up or done the quest they lead to. And the quest
        they lead to waits until the breadcrumb is turned in, or picking it
        up would make the breadcrumb impossible to turn in."""
        to = q.breadcrumbFor
        if to and (to in accepted or to in turned or to in self.done or to in self.accepted_before):
            return True
        for b in self._breadcrumbs(cands).get(q.id, ()):
            if b in accepted and b not in turned:
                return True
        return False

    def _breadcrumbs(self, cands):
        key = id(cands)
        if getattr(self, "_bc_key", None) != key:
            m = {}
            for qid, c in cands.items():
                to = c["q"].breadcrumbFor
                if to:
                    m.setdefault(to, []).append(qid)
            self._bc_key, self._bc = key, m
        return self._bc

    def objective_xp(self, q, kind):
        if q.class_tag():
            return 0.0  # class quests: in the guide, but not in the level estimate
        x = KILLS.get(kind, 0) * mob_xp(max(1, q.level - 1), self.level())
        self.xp_from["kills"] += x
        return x

    def npc(self, nid):
        return self.db["n"].get(nid)

    def npc_name(self, nid):
        n = self.npc(nid)
        return li(n, 1) if n else "?"

    def friendly(self, nid):
        n = self.npc(nid)
        f = li(n, 13) if n else None
        return f is None or ("A" if FACTION == "Alliance" else "H") in f

    def starter(self, q, zone):
        return self._memo("s", q, zone, self._starter)

    def _starter(self, q, zone):
        sb = q.startedBy
        for nid in as_list(li(sb, 1)):
            pts = spawns_in(self.npc(nid), zone, 7)
            if pts and self.friendly(nid):
                return ("npc", nid, pts[0])
        for oid in as_list(li(sb, 2)):
            pts = spawns_in(self.db["o"].get(oid), zone, 4)
            if pts:
                return ("obj", oid, pts[0])
        return None

    def finisher(self, q, zone):
        return self._memo("f", q, zone, self._finisher)

    def _finisher(self, q, zone):
        fb = q.finishedBy
        for nid in as_list(li(fb, 1)):
            pts = spawns_in(self.npc(nid), zone, 7)
            if pts and self.friendly(nid):
                return ("npc", nid, pts[0])
        for oid in as_list(li(fb, 2)):
            pts = spawns_in(self.db["o"].get(oid), zone, 4)
            if pts:
                return ("obj", oid, pts[0])
        return None

    def objective_sites(self, q, zone, nearby=()):
        key = ("o", q.id, zone, tuple(nearby))
        if key not in self._cache:
            self._cache[key] = self._objective_sites(q, zone, nearby)
        return self._cache[key]

    def _memo(self, kind, q, zone, fn):
        key = (kind, q.id, zone)
        if key not in self._cache:
            self._cache[key] = fn(q, zone)
        return self._cache[key]

    def season_of_discovery(self, q):
        """Season of Discovery quests that the installed Questie also knows,
        so they show up in /oxp questdump, but aren't in WoW Forever (like
        Alonso's Dragonslayer quests in Ashenvale). SoD's quest ids sit in
        76000-85999. NPC ids aren't a safe test: Forever's own new NPCs
        (Skyborne, Undead paladins) use the same 200000+ range."""
        return 76000 <= q.id <= 85999 or q.name.startswith("Legacy Reward")

    def quests(self):
        if self._quests is None:
            self._quests = [Quest(qid, row) for qid, row in self.db["q"].items()]
        return self._quests

    def _objective_sites(self, q, zone, nearby=()):
        """List of (index, kind, label, mobs, point, place) for each objective,
        or None if an objective can't be done here (dungeon, far zone, elite).

        Objectives are looked for in the section's zone first, then in its
        `nearby` zones: (area, map name, (scale, dx, dy)). A nearby point is
        mapped into the section zone's frame for routing; place keeps the
        real (map name, x, y) for the .goto, or None for the home zone.
        """
        seq = []  # each located objective's spawn points in the home zone

        def locate(fn):
            pts = fn(zone)
            if pts:
                seq.append(pts)
                return cluster_center(pts), None
            for area, zname, (k, dx, dy) in nearby:
                pts = fn(area)
                if pts:
                    c = cluster_center(pts)
                    seq.append(None)
                    return (c[0] * k + dx, c[1] * k + dy), (zname, c[0], c[1])
            return None, None

        sites = []
        obj = q.objectives or {}
        idx = 0
        for entry in as_list(li(obj, 1)):  # creatures
            idx += 1
            n = self.npc(entry[0])
            if not n or (li(n, 6) or 0) in (1, 2, 3):  # elite / rare elite / boss
                return None
            pt, place = locate(lambda z: spawns_in(n, z, 7))
            if not pt:
                return None
            sites.append((idx, "kill", li(n, 1), [li(n, 1)], pt, place))
        for entry in as_list(li(obj, 2)):  # objects
            idx += 1
            o = self.db["o"].get(entry[0])
            pt, place = locate(lambda z: spawns_in(o, z, 4))
            if not pt:
                return None
            label = entry[1] if len(entry) > 1 and entry[1] else (li(o, 1) or "object")
            sites.append((idx, "use", label, [], pt, place))
        for entry in as_list(li(obj, 3)):  # items
            idx += 1
            item = self.db["i"].get(entry[0])
            if not item:
                return None
            droppers = [self.npc(nid) for nid in as_list(li(item, 2))]
            droppers = [n for n in droppers if n and (li(n, 6) or 0) not in (1, 2, 3)]
            # Leave out droppers more than 2 levels above the quest (the
            # Fetid Corpses for Ghoul Fangs), unless nothing else drops it.
            def top(n):
                return li(n, 5) or li(n, 4) or 0
            fair = [n for n in droppers if top(n) <= q.level + 2]
            droppers = fair or droppers
            objs = [self.db["o"].get(oid) for oid in as_list(li(item, 3))]

            def item_pts(z):
                pts = Spawns()
                for n in droppers:
                    low = top(n) < q.level - 3
                    for p in spawns_in(n, z, 7):
                        pts.append(p)
                        if low:
                            pts.w[p] = 0.5
                for o in objs:
                    pts += spawns_in(o, z, 4)
                return pts
            pt, place = locate(item_pts)
            if not pt:
                return None
            area = zone if place is None else next(a for a, zn, _ in nearby if zn == place[0])
            spot = pt if place is None else (place[1], place[2])
            # name the mobs that live at this spot, most first
            near = [(sum(1 for p in spawns_in(n, area, 7) if math.dist(p, spot) <= 7.0), li(n, 1)) for n in droppers]
            mobs = [nm for c, nm in sorted(near, key=lambda t: -t[0]) if c > 0]
            mobs = mobs or [li(n, 1) for n in droppers if spawns_in(n, area, 7)]
            sites.append((idx, "loot", li(item, 1), mobs[:3], pt, place))
        # reputation (4) objectives are never part of a leveling route
        if li(obj, 4):
            return None
        for entry in as_list(li(obj, 5)):  # kill credit
            idx += 1
            creditors = [self.npc(nid) for nid in as_list(entry[0])]
            creditors = [n for n in creditors if n]

            def credit_pts(z):
                pts = []
                for n in creditors:
                    pts += spawns_in(n, z, 7)
                return pts
            pt, place = locate(credit_pts)
            if not pt:
                return None
            area = zone if place is None else next(a for a, zn, _ in nearby if zn == place[0])
            mobs = [li(n, 1) for n in creditors if spawns_in(n, area, 7)]
            label = entry[2] if len(entry) > 2 and entry[2] else (mobs[0] if mobs else "target")
            sites.append((idx, "credit", label, mobs[:3], pt, place))
        if q.triggerEnd:
            text = li(q.triggerEnd, 1)
            locs = li(q.triggerEnd, 2) or {}

            def trig_pts(z):
                return [tuple(p) for p in as_list(locs.get(z) if isinstance(locs, dict) else None) if p]
            pt, place = locate(trig_pts)
            if not pt:
                return None
            idx += 1
            sites.append((idx, "explore", text, [], pt, place))
        # Other dense spots for each objective, for routes that pick the spot
        # that fits the way best (zones with terrain, see simulate_terrain).
        for site, pts in zip(sites, seq):
            if pts:
                self.alts[(q.id, zone, site[0])] = [c for c, _n in dense_clusters(pts)]
                self.site_pts[(q.id, zone, site[0])] = pts
        return sites

    def candidates(self, section, later_areas=(), carry_ahead=None):
        """Quests to do in this section.

        Includes quests started here and finished here, quests started here
        and finished in a later section's zone (accepted and done here, turned
        in there), and quests carried in from earlier guides or sections that
        finish here.
        """
        zone = section["area"]
        # Wide window around where you'll be; simulate() decides the rest
        # step by step from your level at that moment.
        lvl = int(self.level())
        lo, hi = lvl - GRAY_BELOW + 1, lvl + 10
        out = {}
        for q in self.quests():
            qid = q.id
            if not q.for_faction() or not q.name:
                continue
            if qid in self.done or qid in self.used:
                continue
            if q.specialFlags & 1 or q.reqSkill or q.reqRep:  # 1: repeatable
                continue
            if q.zone in EVENT_SORTS:
                continue  # holiday and world-event quests
            if q.name.startswith("[") or "<" in q.name:
                continue  # placeholder / unused quests in the data
            if self.season_of_discovery(q):
                continue
            carried = qid in self.accepted_before
            if not carried and (q.level < lo or q.level > hi or q.reqLevel > hi):
                continue
            start = None if carried else self.starter(q, zone)
            if not carried and not start:
                continue
            finish = self.finisher(q, zone)
            finish_later = None
            obj_later = None
            nearby = section.get("nearby", ())

            def first_finish(areas):
                return next((a for a in areas if self.finisher(q, a)), None)

            if carried:
                ready = qid in self.carried_ready or qid in self.objectives_done
                sites = [] if ready else self.objective_sites(q, zone, nearby)
                if sites is None:
                    continue  # its objectives are somewhere else: stays in the log
                if not finish:
                    if not sites:
                        continue  # nothing to do here: it rides on to its turn-in
                    finish_later = first_finish(later_areas)
                    if not finish_later:
                        continue
            else:
                sites = self.objective_sites(q, zone, nearby)
                if sites is not None:
                    if not finish:
                        finish_later = first_finish(later_areas)
                        if not finish_later:
                            continue
                else:
                    # Picked up here, done in a zone the route goes to soon,
                    # turned in there or later.
                    ahead = later_areas[:carry_ahead or CARRY_AHEAD] if carry_ahead != 0 else later_areas
                    for i, a in enumerate(ahead):
                        if a != zone and self.objective_sites(q, a) is not None \
                                and first_finish(later_areas[i:]):
                            obj_later = a
                            break
                    if not obj_later:
                        continue
                    sites, finish = [], None
            out[qid] = dict(q=q, start=start, finish=finish, sites=sites,
                            carried=carried, finish_later=finish_later, obj_later=obj_later)
        # Drop quests whose prerequisites we never do, repeatedly (chains).
        changed = True
        while changed:
            changed = False
            for qid, c in list(out.items()):
                q = c["q"]
                if c["carried"]:
                    continue
                ok_group = all(p in self.done or p in out or p in self.accepted_before for p in q.preGroup)
                ok_single = not q.preSingle or any(
                    p in self.done or p in out or p in self.accepted_before for p in q.preSingle)
                if not (ok_group and ok_single):
                    del out[qid]
                    changed = True
        # Mutually exclusive quests: keep the lowest id.
        for qid in sorted(out):
            if qid in out:
                for other in out[qid]["q"].exclusiveTo:
                    if other != qid and other in out:
                        del out[other]
        return out

    def simulate(self, section, cands, start_pos):
        """Greedy walk: always do the cheapest available thing next.

        Cost is the distance, plus the work of an objective, which grows with
        each level the quest is above you. Quests join once they're at most
        LEVELS_ABOVE over your level and are left out when gray. XP is added
        as you go, so later steps see your new level. Returns the actions.
        """
        t = None if os.environ.get("OXP_NO_TERRAIN") else TERRAIN.for_zone(section["zone"])
        if t is not None:
            return self.simulate_terrain(section, cands, start_pos, t)
        accepted = set(q for q in self.accepted_before if q in cands)
        objectives_left = {qid: [s[0] for s in c["sites"]] for qid, c in cands.items()}
        turned_in = set()
        pos = start_pos
        actions = []
        stop_at = section.get("until")  # stop taking new quests at this level

        def prereqs_ok(q):
            group_ok = all((p in self.done) or (p in turned_in) for p in q.preGroup)
            single_ok = (not q.preSingle) or any((p in self.done) or (p in turned_in) for p in q.preSingle)
            return group_ok and single_ok

        while True:
            lvl = self.level()
            options = []
            for qid, c in cands.items():
                q = c["q"]
                if qid in turned_in:
                    continue
                if qid not in accepted:
                    if not c["start"] or len(accepted) >= QUEST_LOG_LIMIT or not prereqs_ok(q):
                        continue
                    if self.breadcrumb_blocked(q, cands, accepted, turned_in):
                        continue
                    if q.reqLevel > int(lvl) or q.level > int(lvl) + LEVELS_ABOVE:
                        continue  # not yet: comes back once you've levelled
                    if q.level <= int(lvl) - GRAY_BELOW:
                        continue  # gray: not worth the walk
                    if stop_at and lvl >= stop_at:
                        continue
                    d = math.dist(pos, c["start"][2])
                    options.append((d - 0.5, "accept", qid, c["start"][2]))
                    continue
                left = objectives_left[qid]
                if left:
                    harder = 1 + SLOWER_PER_LEVEL * max(0, q.level - int(lvl))
                    for s in c["sites"]:
                        if s[0] in left:
                            work = 3.0 if s[1] in ("kill", "loot") else 1.0
                            cost = math.dist(pos, s[4]) + work * harder
                            options.append((cost, "obj", (qid, s[0]), s[4]))
                elif c["finish"]:
                    d = math.dist(pos, c["finish"][2])
                    options.append((d - 0.5, "turnin", qid, c["finish"][2]))
            if not options:
                break
            options.sort(key=lambda o: (o[0], 0 if o[1] != "obj" else 1))
            _, kind, ref, where = options[0]
            x = TRAVEL_KILLS * math.dist(pos, where) * mob_xp(int(lvl), lvl)
            self.xp += x
            self.xp_from["kills"] += x
            self.minutes += math.dist(pos, where) * (MINUTES_PER_UNIT_MOUNTED if lvl >= 40 else MINUTES_PER_UNIT)
            pos = where
            if kind != "obj":
                self.minutes += MINUTES_TALK
            if kind == "accept":
                accepted.add(ref)
            elif kind == "obj":
                qid, i = ref
                q = cands[qid]["q"]
                objectives_left[qid].remove(i)
                site = next(s for s in cands[qid]["sites"] if s[0] == i)
                self.xp += self.objective_xp(q, site[1])
                harder = 1 + SLOWER_PER_LEVEL * max(0, q.level - int(lvl))
                if q.class_tag():
                    harder = 0.0
                self.minutes += MINUTES_WORK.get(site[1], 1) * harder
                # Other objectives of the same quest at the same spot get done too.
                for s in cands[qid]["sites"]:
                    if s[0] in objectives_left[qid] and math.dist(s[4], where) < 2.5:
                        objectives_left[qid].remove(s[0])
                        self.xp += self.objective_xp(q, s[1])
                        self.minutes += MINUTES_WORK.get(s[1], 1) * harder
                        actions.append(("obj", (qid, s[0]), where))
            elif kind == "turnin":
                accepted.discard(ref)
                turned_in.add(ref)
                x = 0.0 if cands[ref]["q"].class_tag() else quest_xp(cands[ref]["q"].level, self.level())
                self.xp += x
                self.xp_from["quests"] += x
            actions.append((kind, ref, where))
        # Quests finished in a later zone travel on in the quest log.
        for qid in accepted:
            if cands[qid]["obj_later"]:
                self.accepted_before.add(qid)
            elif cands[qid]["finish_later"] and not objectives_left[qid]:
                self.accepted_before.add(qid)
                self.carried_ready.add(qid)
        self.used |= turned_in
        self.done |= turned_in
        return actions, turned_in

    SHARE = 3.0      # map units: other quests' objectives this close get done too
    ROLLOUT_TOP = 3  # options tried out to the end when ordering steps
    HERE = 4.0       # map units: quest givers this close count as "in town"

    def simulate_terrain(self, section, cands, start_pos, t):
        """simulate() for zones with walking terrain (tools/terrain.py).

        Differences from the straight-line greedy walk:
        - distances are walking distances around mountains and cliffs, with
          the arrow walks around packs well above your level;
        - each objective can be done at any of its dense spots, not just the
          densest one, so it's done where the route already goes;
        - at a spot, every quest in your log with an objective there gets it
          done (spiders that are also by the wolves);
        - with self.rollouts on, each step tries the best few next moves out
          to the end of the visit and keeps the one with the most XP per
          minute, so quests get picked up before the areas they share.
        """
        area = section["area"]
        unit = (t.kx + t.ky) / 2.0
        stop_at = section.get("until")

        spots = {}  # (qid, objective) -> [point, ...], best first
        for qid, c in cands.items():
            for site in c["sites"]:
                i, place = site[0], site[5]
                pts = [site[4]]
                if place is None:
                    pts += [p for p in self.alts.get((qid, area, i)) or [] if math.dist(p, site[4]) > 1.0]
                spots[(qid, i)] = pts

        def dist(a, b, lvl):
            # Walking distance around the terrain only. Packs above your
            # level are left to the arrow, which walks around them: counted
            # here they'd make every quest whose mobs live in a pack look far
            # away, and the route would criss-cross the zone to avoid them.
            return t.cost(a, b, None) / unit

        st = dict(pos=start_pos, xp=self.xp, minutes=self.minutes, kills=0.0, quests=0.0,
                  accepted=set(q for q in self.accepted_before if q in cands),
                  left={qid: set(s[0] for s in c["sites"]) for qid, c in cands.items()},
                  turned=set(), actions=[])

        def prereqs_ok(st, q):
            done = st["turned"]
            group_ok = all((p in self.done) or (p in done) for p in q.preGroup)
            single_ok = (not q.preSingle) or any((p in self.done) or (p in done) for p in q.preSingle)
            return group_ok and single_ok

        def options(st):
            lvl = level_of(st["xp"])
            il = int(lvl)
            pos = st["pos"]
            out = []
            for qid, c in cands.items():
                q = c["q"]
                if qid in st["turned"]:
                    continue
                if qid not in st["accepted"]:
                    if not c["start"] or len(st["accepted"]) >= QUEST_LOG_LIMIT or not prereqs_ok(st, q):
                        continue
                    if self.breadcrumb_blocked(q, cands, st["accepted"], st["turned"]):
                        continue
                    if q.reqLevel > il or q.level > il + LEVELS_ABOVE or q.level <= il - GRAY_BELOW:
                        continue
                    if stop_at and lvl >= stop_at:
                        continue
                    out.append((dist(pos, c["start"][2], il) - 0.5, "accept", qid, c["start"][2]))
                    continue
                left = st["left"][qid]
                if left:
                    harder = 1 + SLOWER_PER_LEVEL * max(0, q.level - il)
                    for s in c["sites"]:
                        if s[0] in left:
                            work = 3.0 if s[1] in ("kill", "loot") else 1.0
                            for p in spots[(qid, s[0])]:
                                out.append((dist(pos, p, il) + work * harder, "obj", (qid, s[0]), p))
                elif c["finish"]:
                    out.append((dist(pos, c["finish"][2], il) - 0.5, "turnin", qid, c["finish"][2]))
            out.sort(key=lambda o: (o[0], 0 if o[1] != "obj" else 1))
            return out

        def do_obj(st, qid, i, where, harder, record):
            q = cands[qid]["q"]
            st["left"][qid].discard(i)
            site = next(s for s in cands[qid]["sites"] if s[0] == i)
            x = 0.0 if q.class_tag() else KILLS.get(site[1], 0) * mob_xp(max(1, q.level - 1), level_of(st["xp"]))
            st["xp"] += x
            st["kills"] += x
            st["minutes"] += MINUTES_WORK.get(site[1], 1) * (0.0 if q.class_tag() else harder)
            if record:
                st["actions"].append(("obj", (qid, i), where))

        def apply(st, opt, record=True):
            _, kind, ref, where = opt
            lvl = level_of(st["xp"])
            # Walking distance around the terrain. Every zone on the routes
            # has terrain, so they're all judged on the same scale (a zone
            # without it, like Shen'dralas, still counts the straight line).
            d = dist(st["pos"], where, int(lvl))
            x = TRAVEL_KILLS * d * mob_xp(int(lvl), lvl)
            st["xp"] += x
            st["kills"] += x
            st["minutes"] += d * MINUTES_PER_UNIT
            st["pos"] = where
            if kind != "obj":
                st["minutes"] += MINUTES_TALK
            if kind == "accept":
                st["accepted"].add(ref)
                if record:
                    st["actions"].append((kind, ref, where))
            elif kind == "turnin":
                st["accepted"].discard(ref)
                st["turned"].add(ref)
                q = cands[ref]["q"]
                x = 0.0 if q.class_tag() else quest_xp(q.level, level_of(st["xp"]))
                st["xp"] += x
                st["quests"] += x
                if record:
                    st["actions"].append((kind, ref, where))
            else:
                qid, i = ref
                il = int(lvl)
                harder = 1 + SLOWER_PER_LEVEL * max(0, cands[qid]["q"].level - il)
                do_obj(st, qid, i, where, harder, record)
                # everything else in your log that can be done right here
                for q2 in sorted(st["accepted"]):
                    for i2 in sorted(st["left"][q2]):
                        if any(math.dist(p, where) <= self.SHARE for p in spots[(q2, i2)]):
                            h2 = 1 + SLOWER_PER_LEVEL * max(0, cands[q2]["q"].level - il)
                            do_obj(st, q2, i2, where, h2, record)

        def clone(st):
            return dict(pos=st["pos"], xp=st["xp"], minutes=st["minutes"], kills=st["kills"],
                        quests=st["quests"], accepted=set(st["accepted"]),
                        left={k: set(v) for k, v in st["left"].items()},
                        turned=set(st["turned"]), actions=None)

        def finish(st):
            while True:
                opts = options(st)
                if not opts:
                    return st
                apply(st, opts[0], record=False)

        xp0, min0 = st["xp"], st["minutes"]
        while True:
            opts = options(st)
            if not opts:
                break
            choice = opts[0]
            # Quest givers right where you stand: always talk to them before
            # leaving (you'd never walk off from a town without its quests).
            here = [o for o in opts if o[1] != "obj" and o[0] <= self.HERE]
            if here:
                choice = here[0]
            elif self.rollouts and len(opts) > 1:
                tried, best = set(), None
                for o in opts:
                    key = (o[1], o[2], o[3])
                    if key in tried:
                        continue
                    tried.add(key)
                    trial = clone(st)
                    apply(trial, o, record=False)
                    finish(trial)
                    spent = trial["minutes"] - min0
                    rate = (trial["xp"] - xp0) / spent if spent > 0 else 0
                    if best is None or rate > best[0] + 1e-9:
                        best = (rate, o)
                    if len(tried) >= self.ROLLOUT_TOP:
                        break
                choice = best[1]
            apply(st, choice)

        if self.rollouts:
            acts, _saved = self.improve_order(st["actions"], cands, spots, start_pos, xp0, t, level_of(xp0))
            st["actions"] = acts
        self.xp, self.minutes = st["xp"], st["minutes"]
        self.xp_from["kills"] += st["kills"]
        self.xp_from["quests"] += st["quests"]
        turned_in = st["turned"]
        for qid in st["accepted"]:
            if cands[qid]["obj_later"]:
                self.accepted_before.add(qid)
            elif cands[qid]["finish_later"] and not st["left"][qid]:
                self.accepted_before.add(qid)
                self.carried_ready.add(qid)
        self.used |= turned_in
        self.done |= turned_in
        return st["actions"], turned_in

    def improve_order(self, actions, cands, spots, start_pos, xp0, t, lvl0):
        """Shorten the walk of a visit by moving steps around (or-opt) and
        moving objectives to other dense spots, keeping every order rule:
        accept before objectives before turn-in, follow-ups after the quest
        before them, at most QUEST_LOG_LIMIT quests in the log, and no quest
        picked up before your level allows it. Returns the new actions and
        how many yards of walking that saved."""
        if len(actions) < 3:
            return actions, 0.0
        acts = list(actions)
        lvl_key = int(lvl0)

        def cost(a, b):
            return t.cost(a, b, None)

        def total(seq):
            pos, s = start_pos, 0.0
            for a in seq:
                s += cost(pos, a[2])
                pos = a[2]
            return s

        # XP each step gives, from the order the planner made (close enough
        # to check levels when steps move a little).
        gain = []
        for a in acts:
            if a[0] == "turnin":
                q = cands[a[1]]["q"]
                gain.append(0.0 if q.class_tag() else quest_xp(q.level, lvl0))
            elif a[0] == "obj":
                q = cands[a[1][0]]["q"]
                site = next(s for s in cands[a[1][0]]["sites"] if s[0] == a[1][1])
                gain.append(0.0 if q.class_tag() else KILLS.get(site[1], 0) * mob_xp(max(1, q.level - 1), lvl0))
            else:
                gain.append(0.0)
        gains = {id(a): g for a, g in zip(acts, gain)}
        in_log0 = set(q for q in self.accepted_before if q in cands)
        in_visit = set(a[1] for a in acts if a[0] == "turnin")

        def valid(seq):
            valid.why = None
            xp = xp0
            log = set(in_log0)
            accepted, turned, done_obj = set(), set(), set()
            for a in seq:
                kind, ref = a[0], a[1]
                if kind == "accept":
                    q = cands[ref]["q"]
                    il = int(level_of(xp))
                    if self.breadcrumb_blocked(q, cands, accepted, turned):
                        valid.why = "breadcrumb"; return False
                    if q.reqLevel > il or q.level > il + LEVELS_ABOVE:
                        valid.why = 'level'; return False
                    for p in q.preGroup:
                        if p in in_visit and p not in turned:
                            return False
                    if q.preSingle and not any(p in self.done or p in turned or p not in in_visit
                                               for p in q.preSingle):
                        return False
                    log.add(ref)
                    accepted.add(ref)
                    if len(log) > QUEST_LOG_LIMIT:
                        valid.why = 'log'; return False
                elif kind == "obj":
                    if ref[0] not in log:
                        valid.why = 'objlog'; return False
                    done_obj.add(ref)
                else:
                    if ref not in log:
                        valid.why = 'turnlog'; return False
                    for s in cands[ref]["sites"]:
                        if (ref, s[0]) not in done_obj and any(
                                b[0] == "obj" and b[1] == (ref, s[0]) for b in seq):
                            return False
                    log.discard(ref)
                    turned.add(ref)
                xp += gains.get(id(a), 0.0)
            return True

        best = total(acts)
        start = best
        improved = True
        rounds = 0
        while improved and rounds < 6:
            improved = False
            rounds += 1
            # another dense spot for an objective
            for i, a in enumerate(acts):
                if a[0] != "obj":
                    continue
                for p in spots.get(a[1], ()):
                    if p == a[2]:
                        continue
                    trial = acts[:i] + [(a[0], a[1], p)] + acts[i + 1:]
                    c = total(trial)
                    if c < best - 1.0:
                        gains[id(trial[i])] = gains.get(id(a), 0.0)
                        acts, best, improved = trial, c, True
                        a = acts[i]
            # move a block of 1-3 steps somewhere else
            n = len(acts)
            for size in (1, 2, 3):
                i = 0
                while i + size <= n:
                    block = acts[i:i + size]
                    rest = acts[:i] + acts[i + size:]
                    moved = False
                    for j in range(len(rest) + 1):
                        if j == i:
                            continue
                        trial = rest[:j] + block + rest[j:]
                        c = total(trial)
                        if c < best - 1.0 and valid(trial):
                            acts, best, improved, moved = trial, c, True, True
                            break
                        if c < best - 1.0 and os.environ.get("OXP_DEBUG_IMPROVE"):
                            print("rejected", size, i, j, round(best - c), block[0][:2], valid.why)
                    if not moved:
                        i += 1
        return acts, start - best

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

AREA_REACH = 7.0   # map units: spawns this close to the step's spot make its area
AREA_MARGIN = 1.5  # map units: the area reaches this far past the outer spawns


def kill_area(points, where, most=8):
    """The area to kill and loot in around `where`: the outline of the
    spawns near it, widened a little so mobs on the edge are inside, with at
    most `most` corners. None when there aren't enough spawns for an area."""
    near = sorted({(round(p[0], 2), round(p[1], 2)) for p in points if math.dist(p, where) <= AREA_REACH})
    if len(near) < 4:
        return None

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in near:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(near):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    if len(hull) < 3:
        return None
    while len(hull) > most:
        # drop the corner that changes the outline least
        def area(i):
            a, b, c = hull[i - 1], hull[i], hull[(i + 1) % len(hull)]
            return abs(cross(a, b, c))
        hull.pop(min(range(len(hull)), key=area))
    cx = sum(p[0] for p in hull) / len(hull)
    cy = sum(p[1] for p in hull) / len(hull)
    out = []
    for x, y in hull:
        d = math.dist((x, y), (cx, cy)) or 1.0
        out.append((min(100, max(0, x + (x - cx) / d * AREA_MARGIN)),
                    min(100, max(0, y + (y - cy) / d * AREA_MARGIN))))
    return out


def fmt_coord(zone_name, p):
    return "%s,%.2f,%.2f" % (zone_name, p[0], p[1])


def render_section(builder, section, cands, actions, group, nxt):
    zname = section["zone"]
    lines = []
    lines.append("RXPGuides.RegisterGuide([[")
    lines.append("#forever" if GAME == "Forever" else "#classic")
    lines.append("#disabledungeons")
    lines.append("#version 1")
    lines.append("<< " + FACTION)
    lines.append("#group %s" % group)
    lines.append("#subgroup %s" % section.get("subgroup", "OpenXP 21-60"))
    lines.append("#name %s" % section["name"])
    if nxt:
        lines.append("#next %s" % nxt)
    lines.append("")
    for t in section.get("intro", []):
        lines.append(t)
    grind_to = section.get("_grind_to")
    if grind_to:
        lines.append("step")
        dungeon = next((d for lo, hi, d in DUNGEONS if lo <= grind_to <= hi), None)
        lines.append("    .xp %d >>Kill mobs on the way%s until you're level %d: "
                     "the quests here are a bit high for you before that" % (
                         grind_to, (", or run " + dungeon + ",") if dungeon else "", grind_to))

    # Merge consecutive accept/turnin actions at the same spot into one step.
    i = 0
    while i < len(actions):
        kind, ref, where = actions[i]
        if kind in ("accept", "turnin"):
            group_actions = [actions[i]]
            j = i + 1
            while j < len(actions) and actions[j][0] in ("accept", "turnin") and math.dist(actions[j][2], where) < 0.6:
                group_actions.append(actions[j])
                j += 1
            # one step per NPC so the target name is right
            by_npc = []
            for a in group_actions:
                qid = a[1]
                c = cands[qid]
                who = c["start"] if a[0] == "accept" else c["finish"]
                if by_npc and by_npc[-1][0] == who[:2]:
                    by_npc[-1][1].append(a)
                else:
                    by_npc.append((who[:2], [a]))
            for (wkind, wid), acts in by_npc:
                classes = set(cands[a[1]]["q"].class_tag() for a in acts)
                tag = " << " + classes.pop() if len(classes) == 1 and None not in classes else ""
                lines.append("step" + tag)
                lines.append("    .goto %s" % fmt_coord(zname, acts[0][2]))
                if wkind == "npc":
                    nm = builder.npc_name(wid)
                    lines.append("    >>Talk to |cRXP_FRIENDLY_%s|r" % nm)
                else:
                    nm = li(builder.db["o"].get(wid), 1) or "object"
                    lines.append("    >>Click the |cRXP_PICK_%s|r" % nm)
                for a in acts:
                    q = cands[a[1]]["q"]
                    ctag = q.class_tag()
                    suffix = (" << " + ctag) if ctag and not tag else ""
                    verb = "accept" if a[0] == "accept" else "turnin"
                    word = "Accept" if verb == "accept" else "Turn in"
                    qid_txt = q.id
                    if verb == "accept":
                        builder.file_accepted.add(q.id)
                    elif q.id not in builder.file_accepted:
                        qid_txt = -q.id  # picked up in an earlier guide: skip if not in the log
                    lines.append("    .%s %d >>%s %s%s" % (verb, qid_txt, word, q.name, suffix))
                if wkind == "npc":
                    lines.append("    .target %s" % nm)
            i = j
            continue
        # Objectives: merge the ones done at the same spot into one step.
        def place_of(action):
            qid, oi = action[1]
            return next(s for s in cands[qid]["sites"] if s[0] == oi)[5]
        place0 = place_of(actions[i])
        group_objs = [actions[i]]
        j = i + 1
        while (j < len(actions) and actions[j][0] == "obj" and math.dist(actions[j][2], where) < 3.0
               and (place_of(actions[j]) or (None,))[0] == (place0 or (None,))[0]):
            group_objs.append(actions[j])
            j += 1
        texts, completes, mobs_all, tags = [], [], [], set()
        for _, (qid, oi), _w in group_objs:
            c = cands[qid]
            site = next(s for s in c["sites"] if s[0] == oi)
            q = c["q"]
            tags.add(q.class_tag())
            _, okind, label, mobs, _, place = site
            if okind == "kill":
                t = "Kill |cRXP_ENEMY_%s|r" % label
            elif okind == "loot":
                if mobs:
                    t = "Kill |cRXP_ENEMY_%s|r. Loot them for |cRXP_LOOT_%s|r" % (
                        "|r and |cRXP_ENEMY_".join(mobs), label)
                else:
                    t = "Loot the |cRXP_PICK_%s|r" % label
            else:
                t = label or "Explore the area"
            if t not in texts:
                texts.append(t)
            cid = q.id if q.id in builder.file_accepted else -q.id
            completes.append("    .complete %d,%d --%s" % (cid, oi, q.name))
            for m in mobs:
                if m not in mobs_all:
                    mobs_all.append(m)
        tag = tags.pop() if len(tags) == 1 else None
        lines.append("step" + (" << " + tag if tag else ""))
        area = None
        if section.get("areas") and not place0:
            pts = []
            for _, (qid, oi), _w in group_objs:
                pts += builder.site_pts.get((qid, section["area"], oi)) or []
            area = kill_area(pts, where)
        if area:
            # An area to work in, not a spot: it's drawn on the map and
            # minimap, and the arrow says you're there anywhere inside it.
            lines.append("    .goto %s" % fmt_coord(zname, where))
            lines.append("    .area %s,%s" % (zname, ",".join("%.2f,%.2f" % p for p in area)))
        elif place0:
            lines.append("    .goto %s,%.2f,%.2f" % place0)
        else:
            lines.append("    .goto %s" % fmt_coord(zname, where))
        for t in texts:
            lines.append("    >>" + t)
        lines.extend(completes)
        for m in mobs_all:
            lines.append("    .mob %s" % m)
        i = j

    for t in section.get("outro", []):
        lines.append(t)
    lines.append("]])")
    return "\n".join(lines)


# Dungeons worth suggesting when the route asks you to level a little.
DUNGEONS = [
    (24, 31, "the Scarlet Monastery Graveyard and Library"),
    (32, 40, "the Scarlet Monastery Armory and Cathedral"),
    (41, 44, "Uldaman"),
    (45, 48, "Zul'Farrak"),
    (49, 51, "Maraudon"),
    (52, 54, "the Sunken Temple"),
    (55, 58, "Blackrock Depths"),
    (59, 60, "Lower Blackrock Spire or Stratholme"),
]

# Quest sorts for holidays, world events and PvP, never part of a route.
EVENT_SORTS = {-22, -284, -364, -366, -369, -370, -376, -1002, -1003, -1005, -1006, -25, -41}

CLASS_GUIDE = r"Warrior|Paladin|Hunter|Rogue|Priest|Mage|Warlock|Druid|Shaman"


def free_guide_quests(skip=None, skip_all=()):
    """Quests accepted / turned in by the Alliance guides before this one:
    the free ones in Guides/forever and OpenXP's earlier level ranges."""
    accepted, turned = set(), set()
    if GAME == "Forever":
        out_dir = "openxp"
        paths = glob.glob(os.path.join(ROOT, "Guides", "forever", "*.lua"))
    else:
        out_dir = "openxp-classic"
        paths = [p for p in glob.glob(os.path.join(ROOT, "Guides", "Classic-*.lua"))]
    paths += glob.glob(os.path.join(ROOT, "Guides", out_dir, "*.lua"))
    for path in paths:
        base = os.path.basename(path)
        name = base[len("Classic-"):] if base.startswith("Classic-") else base
        if "dungeon" in path or not name.startswith(FACTION):
            continue
        if re.search(CLASS_GUIDE, base):
            continue  # class-only routes; most players never ran them
        if skip and os.path.abspath(path) == os.path.abspath(skip):
            continue
        if os.path.abspath(path) in skip_all:
            continue
        if skip and os.path.dirname(path).endswith(os.path.join("Guides", out_dir)) and base > os.path.basename(skip):
            continue  # later level ranges
        text = open(path, encoding="utf-8").read()
        accepted |= {int(x) for x in re.findall(r"\.accept\s+(\d+)", text)}
        turned |= {int(x) for x in re.findall(r"\.turnin\s+-?(\d+)", text)}
    return accepted, turned


def load_route(path):
    spec = importlib.util.spec_from_file_location(os.path.basename(path)[:-3], path)
    route = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(route)
    return route


def section_name(section, start, end):
    """"23-25 Wetlands": the levels you're really at, from the simulation."""
    if section.get("name"):
        return section["name"]
    a, b = int(start), int(end)
    if b <= a:
        b = a + 1
    return "%d-%d %s" % (a, b, section.get("label", section["zone"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    ap.add_argument("--dump", help="OpenXP.lua saved variables with /oxp questdump data")
    ap.add_argument("--log", help="write every zone choice and its numbers to this JSON file")
    ap.add_argument("routes", nargs="+",
                    help="route files, in level order; they're built as one run so "
                         "your level carries from one file into the next")
    args = ap.parse_args()

    routes = [load_route(p) for p in args.routes]
    first = routes[0]
    global GAME, FACTION
    GAME = getattr(first, "GAME", "Forever")
    FACTION = getattr(first, "FACTION", "Alliance")
    db = load_db(args.questiedb)
    if args.dump:
        db = merge_db(db, load_dump_cached(args.dump, args.questiedb))
    if hasattr(first, "HUBS"):
        return main_hubs(first, args, db)
    outputs = {os.path.abspath(os.path.join(ROOT, r.OUTPUT)) for r in routes}
    if len(routes) == 1:
        accepted, turned = free_guide_quests(os.path.join(ROOT, first.OUTPUT))
    else:
        accepted, turned = free_guide_quests(skip_all=outputs)
    builder = Builder(db, done_before=turned, carried=accepted - turned)
    for r in routes:
        # Quests a route leaves out on purpose (rare drops, page collections...)
        builder.used |= set(getattr(r, "SKIP", ()))
    start_level = getattr(first, "START_LEVEL", None) or first.SECTIONS[0]["levels"][0]
    builder.xp = xp_at_level(start_level)

    # Play every section in order first, so names and #next links can use the
    # levels you'll really be at.
    plan = []  # (route, section, cands, actions, done, start, end)
    all_sections = [(r, s) for r in routes for s in r.SECTIONS]
    report = []
    seen = set()
    for n, (r, section) in enumerate(all_sections):
        section = dict(section)
        later = [s["area"] for _, s in all_sections[n + 1:]]
        saved = builder.snapshot()
        at = section.get("at") or 0
        if not at and not section.get("city") and section.get("grind", True):
            # Too few of the zone's quests are open to you yet: kill mobs on
            # the way or run a dungeon first, as the big guides do, instead of
            # walking into a zone of orange and red quests.
            here = [c["q"] for c in builder.candidates(section, later).values()
                    if not c["carried"]]
            need = sorted(max(q.reqLevel, q.level - LEVELS_ABOVE) for q in here)
            now = builder.level()
            if need and sum(1 for x in need if x <= int(now)) < MIN_OPEN:
                at = min(need[min(MIN_OPEN, len(need)) - 1], now + MAX_GRIND)
                if not any(x <= int(at) for x in need):
                    at = 0  # nothing opens soon: do what's there and move on
        grind = 0.0
        if at and builder.level() < at - 0.25:
            grind = at - builder.level()
            section["_grind_to"] = int(at)
            builder.xp = xp_at_level(at)
            builder.xp_from["grind"] = builder.xp_from.get("grind", 0) + grind
        start = builder.level()
        cands = builder.candidates(section, later)
        actions, done = builder.simulate(section, cands, section["start"])
        end = builder.level()
        name = section_name(section, start, end)
        k = 2
        while name in seen:
            name = "%s (part %d)" % (section_name(section, start, end), k)
            k += 1
        if section.get("city") and not actions:
            continue  # nothing to do in town this time
        worth = len({a[1] if a[0] != "obj" else a[1][0] for a in actions if a[0] != "accept"})
        if plan and not section.get("city") and not section.get("keep") and worth < MIN_VISIT:
            # Not worth the trip: forget it, its quests wait for a later visit.
            builder.restore(saved)
            report.append("%-36s skipped: only %d quests at level %.1f" % (
                section.get("label", section["zone"]), worth, start - grind))
            continue
        seen.add(name)
        section["name"] = name
        plan.append([r, section, cands, actions])
        report.append("%-36s %3d quests %5.1f -> %5.1f%s" % (
            name, len(done), start, end, ("   grind %.1f lv" % grind) if grind else ""))
        # carried quests that got turned in are no longer carried
        builder.accepted_before -= done

    for r in routes:
        builder.file_accepted = set()
        out = [r.HEADER.rstrip(), ""]
        mine = [i for i, p in enumerate(plan) if p[0] is r]
        for i in mine:
            _, section, cands, actions = plan[i]
            if i + 1 < len(plan):
                nxt = plan[i + 1][1]["name"]
            else:
                nxt = getattr(r, "NEXT", None)
            out.append(render_section(builder, section, cands, actions, r.GROUP, nxt))
            out.append("")
        path = os.path.join(ROOT, r.OUTPUT)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8").write("\n".join(out))
        print("wrote", os.path.relpath(path, ROOT))
    print("\n".join(report))
    total = sum(1 for p in plan for a in p[3] if a[0] == "turnin")
    print("%d turn-ins, level %.1f -> %.1f; XP from quests %.0fk, kills %.0fk; %.1f levels of grinding" % (
        total, start_level, builder.level(), builder.xp_from["quests"] / 1000,
        builder.xp_from["kills"] / 1000, builder.xp_from.get("grind", 0)))


# ---------------------------------------------------------------------------
# Automatic zone order
#
# A route file with HUBS lists the places you can quest from (zone, hub
# town, how to get there) instead of a fixed order. The planner then plays
# the route: at every step it tries each hub, sees how much XP the visit
# would give and how long it would take (travel, walking, objectives,
# slower for quests above your level), and goes where the XP per minute is
# best. When no zone has enough quests open for you, it adds a short
# "kill mobs or run a dungeon to level N" step and tries again.
# ---------------------------------------------------------------------------

# Every zone choice the planner made, with the numbers for each option
# (written out with --log, for explaining the route).
DECISIONS = []


def plan_hubs(builder, route):
    hubs = route.HUBS
    areas = [h["area"] for h in hubs]
    visits = {}
    plan, report = [], []
    cur = None
    pending_grind = 0.0

    def visit(hub, commit, frm=None):
        frm = cur if frm is None else frm
        section = dict(hub)
        first = visits.get(hub["key"], 0) == 0
        section["intro"] = hub["first"] if first else hub["again"]
        section["grind"] = False
        builder.rollouts = commit  # the slow, careful ordering only for the visit you take
        before_xp, before_min = builder.xp, builder.minutes
        start = builder.level()
        cands = builder.candidates(section, areas, carry_ahead=0)
        actions, done = builder.simulate(section, cands, section["start"])
        worth = len({qid for qid in (a[1] if a[0] != "obj" else a[1][0] for a in actions if a[0] != "accept")
                     if not cands[qid]["q"].class_tag()})
        hop = 0.0 if frm is None or frm["key"] == hub["key"] else (
            MINUTES_HOP if frm["continent"] == hub["continent"] else MINUTES_SEA)
        hop += hub.get("ride", 0) if first else 0
        if hub.get("city") and hop:
            hop = max(hop, MINUTES_CITY)
        spent = hop + builder.minutes - before_min
        gain = builder.xp - before_xp
        rate = gain / spent if spent > 0 else 0
        visit.last = (gain, spent)
        return section, cands, actions, done, start, worth, rate

    first_hub = next(h for h in hubs if h["key"] == route.FIRST)
    steps = 0
    while builder.level() < MAX_LEVEL - 0.02 and steps < 200:
        steps += 1
        if cur is None:
            options = [first_hub]
        else:
            options = [h for h in hubs if h["key"] != cur["key"]]
        scored = []
        log = {"level": builder.level(), "from": cur["key"] if cur else None, "options": {}}
        for hub in options:
            saved = builder.snapshot()
            section, cands, actions, done, start, worth, rate = visit(hub, False)
            gain, spent = visit.last
            builder.restore(saved)
            need = 3 if hub.get("city") else MIN_VISIT
            later = sorted(c["q"].level for c in cands.values()
                           if not c["carried"] and c["q"].id not in done)
            log["options"][hub["key"]] = dict(
                worth=worth, gain=gain, spent=spent, rate=rate, need=need,
                quests=len(done), waiting=later[:6])
            if os.environ.get("OXP_DEBUG"):
                print("  try %-14s lv %.1f worth %2d rate %4.0f" % (hub["key"], builder.level(), worth, rate))
            if cur is not None and worth < need:
                continue
            scored.append((rate, hub))
        scored.sort(key=lambda x: -x[0])
        best = None
        # Look one visit ahead for the best few, so a trip across the sea
        # counts what you can do once you're there.
        for rate, hub in scored[:LOOKAHEAD]:
            saved = builder.snapshot()
            visit(hub, False)
            gain1, spent1 = visit.last
            w = visits.get(hub["key"], 0)
            visits[hub["key"]] = w + 1
            gain2 = spent2 = 0.0
            best2 = 0.0
            best_next = None
            for hub2 in hubs:
                if hub2["key"] == hub["key"]:
                    continue
                saved2 = builder.snapshot()
                _, _, _, _, _, worth2, rate2 = visit(hub2, False, frm=hub)
                g2, s2 = visit.last
                builder.restore(saved2)
                if worth2 >= (3 if hub2.get("city") else MIN_VISIT) and rate2 > best2:
                    best2, gain2, spent2 = rate2, g2, s2
                    best_next = hub2["key"]
            visits[hub["key"]] = w
            builder.restore(saved)
            combined = (gain1 + gain2) / (spent1 + spent2) if spent1 + spent2 else 0
            log["options"][hub["key"]].update(combined=combined, next=best_next)
            if best is None or combined > best[2]:
                best = (hub, rate, combined)
        lvl = builder.level()
        log["grind_rate"] = GRIND_KILLS_PER_MINUTE * mob_xp(int(lvl), lvl)
        if best is not None and cur is not None and \
                best[1] < WORTH_IT * GRIND_KILLS_PER_MINUTE * mob_xp(int(lvl), lvl):
            best = None
        log["chosen"] = best[0]["key"] if best else None
        DECISIONS.append(log)
        if best is None:
            if pending_grind >= 6:
                break
            # Nothing worth a trip at this level: level up a bit first.
            lvl = builder.level()
            target = xp_at_level(lvl + 0.5)
            builder.minutes += (target - builder.xp) / (GRIND_KILLS_PER_MINUTE * mob_xp(int(lvl), lvl))
            builder.xp = target
            pending_grind += 0.5
            builder.xp_from["grind"] = builder.xp_from.get("grind", 0) + 0.5
            continue
        hub = best[0]
        section, cands, actions, done, start, worth, rate = visit(hub, True)
        visits[hub["key"]] = visits.get(hub["key"], 0) + 1
        if pending_grind:
            section["_grind_to"] = int(start)
        plan.append(dict(section=section, cands=cands, actions=actions, done=done,
                         start=start, end=builder.level(), grind=pending_grind, rate=rate))
        log["quests"] = [(a[1], cands[a[1]]["q"].name, cands[a[1]]["q"].level)
                         for a in actions if a[0] == "turnin"]
        log["start"], log["end"] = start, builder.level()
        builder.accepted_before -= done
        pending_grind = 0.0
        cur = hub

    # Quests picked up but never finished on the route: leave them out.
    turned = set()
    for p in plan:
        turned |= p["done"]
    for p in plan:
        p["actions"] = [a for a in p["actions"]
                        if (a[1][0] if a[0] == "obj" else a[1]) in turned]
    # Names from the levels you're at; drop stops left empty.
    seen = set()
    out = []
    for p in plan:
        if not p["actions"] and not p["grind"]:
            continue
        sec = p["section"]
        base = section_name(sec, p["start"], p["end"])
        name, k = base, 2
        while name in seen:
            name, k = "%s (part %d)" % (base, k), k + 1
        seen.add(name)
        sec["name"] = name
        out.append(p)
        report.append("%-36s %3d quests %5.1f -> %5.1f  %4.0f xp/min%s" % (
            name, len(p["done"]), p["start"], p["end"], p["rate"],
            ("   grind %.1f lv" % p["grind"]) if p["grind"] else ""))
    return out, report


def main_hubs(route, args, db):
    accepted, turned = free_guide_quests(
        skip_all={os.path.abspath(os.path.join(ROOT, o[1])) for o in route.OUTPUTS})
    builder = Builder(db, done_before=turned, carried=accepted - turned)
    builder.used |= set(getattr(route, "SKIP", ()))
    builder.xp = xp_at_level(route.START_LEVEL)
    plan, report = plan_hubs(builder, route)
    if args.log:
        import json
        json.dump(DECISIONS, open(args.log, "w"), indent=1)
    # Split into files by the level each section starts at.
    files = []
    for top, path, header in route.OUTPUTS:
        files.append((path, header, [p for p in plan if p.get("_file") is None and p["start"] < top]))
        for p in files[-1][2]:
            p["_file"] = path
    order = [p for _, _, ps in files for p in ps]
    for path, header, ps in files:
        builder.file_accepted = set()
        out = [header.rstrip(), ""]
        for p in ps:
            i = order.index(p)
            nxt = order[i + 1]["section"]["name"] if i + 1 < len(order) else None
            out.append(render_section(builder, p["section"], p["cands"], p["actions"], route.GROUP, nxt))
            out.append("")
        full = os.path.join(ROOT, path)
        open(full, "w", encoding="utf-8").write("\n".join(out))
        print("wrote", path, "(%d sections)" % len(ps))
    print("\n".join(report))
    total = sum(len(p["done"]) for p in plan)
    print("%d turn-ins, level %.1f -> %.1f; XP from quests %.0fk, kills %.0fk; %.1f levels of grinding; %.0f hours" % (
        total, route.START_LEVEL, builder.level(), builder.xp_from["quests"] / 1000,
        builder.xp_from["kills"] / 1000, builder.xp_from.get("grind", 0), builder.minutes / 60))


if __name__ == "__main__":
    main()
