#!/usr/bin/env python3
"""Generate OpenXP's zone completion guides (one guide per zone, per faction).

These are a separate guide set from the 21-60 speed route: they sit in their
own group ("OpenXP Zone Completion"), so building or changing them never moves
anyone on the main route.

A completion guide does every quest a zone has for your faction in one stay,
instead of only the ones worth the most XP per minute: side quests, the whole
story chains, Forever's new quests in the old zones, and the new zones
(Riverglades, Shen'dralas, Zephras Isle). Dungeon quests a zone hands out are
picked up and pointed at the dungeon guides; elite group quests are left out.

How a zone guide is ordered:
- Each quest belongs to the zone where its objectives are (a delivery quest
  to the zone where it's turned in), so the quests a zone guide does are the
  ones you'd see on that zone's map.
- The builder plays the zone in its head from the zone's starting level:
  it always does the nearest thing it can (pick up, objective or turn in),
  respecting quest chains, breadcrumbs and the quest log limit, and tracks
  your XP. Quests open once you're at their required level and at most
  LEVELS_ABOVE under their quest level. When only higher quests are left,
  the guide says which level they need.
- Pick-ups and turn-ins in other zones (a capital, or a delivery that leads
  to the next zone) are batched, since each one is a trip.
- Each guide points to a suggested next zone (#next), and players can pick
  any zone from the list.

Data: QuestieDB's Forever data with the Forever corrections applied
(tools/forever_data.py), plus /oxp questdump when given. Facts only (ids,
levels, coordinates), like the route builder.

Usage:
    python3 tools/build_completion.py --questiedb PATH --dump OpenXP.lua --faction Alliance
    python3 tools/build_completion.py --questiedb PATH --dump OpenXP.lua --faction Horde
"""
import argparse
import collections
import math
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_route as br  # noqa: E402
import forever_data  # noqa: E402

ROOT = br.ROOT
GROUP = "OpenXP Zone Completion"
LEVELS_ABOVE = 3       # take a quest when you're at most this many levels under it
LOG_LIMIT = 20
OTHER_AREA = 200.0     # cost of a step in another zone: batch them
MIN_QUESTS = 5         # zones with fewer quests for a faction get no guide
SKYBORNE = 4294967296 | 8589934592

# (name, area id, kind). kind: "start" (race starting zone), "zone", "city".
ZONES = [
    ("Elwynn Forest", 12, "start"), ("Dun Morogh", 1, "start"), ("Teldrassil", 141, "start"),
    ("Durotar", 14, "start"), ("Mulgore", 215, "start"), ("Tirisfal Glades", 85, "start"),
    ("Zephras Isle", 16593, "start"),
    ("Westfall", 40, "zone"), ("Loch Modan", 38, "zone"), ("Darkshore", 148, "zone"),
    ("Silverpine Forest", 130, "zone"), ("The Barrens", 17, "zone"),
    ("Redridge Mountains", 44, "zone"), ("Duskwood", 10, "zone"), ("Wetlands", 11, "zone"),
    ("Ashenvale", 331, "zone"), ("Stonetalon Mountains", 406, "zone"),
    ("Hillsbrad Foothills", 267, "zone"), ("Alterac Mountains", 36, "zone"),
    ("Arathi Highlands", 45, "zone"), ("Thousand Needles", 400, "zone"), ("Desolace", 405, "zone"),
    ("Shen'dralas", 16651, "zone"), ("Stranglethorn Vale", 33, "zone"), ("Dustwallow Marsh", 15, "zone"),
    ("Riverglades", 16591, "zone"), ("Swamp of Sorrows", 8, "zone"), ("Badlands", 3, "zone"),
    ("Tanaris", 440, "zone"), ("Feralas", 357, "zone"), ("The Hinterlands", 47, "zone"),
    ("Searing Gorge", 51, "zone"), ("Azshara", 16, "zone"), ("Un'Goro Crater", 490, "zone"),
    ("Felwood", 361, "zone"), ("Blasted Lands", 4, "zone"), ("Burning Steppes", 46, "zone"),
    ("Western Plaguelands", 28, "zone"), ("Eastern Plaguelands", 139, "zone"),
    ("Winterspring", 618, "zone"), ("Silithus", 1377, "zone"), ("Deadwind Pass", 41, "zone"),
    ("Moonglade", 493, "zone"),
    ("Stormwind City", 1519, "city"), ("Ironforge", 1537, "city"), ("Darnassus", 1657, "city"),
    ("Orgrimmar", 1637, "city"), ("Thunder Bluff", 1638, "city"), ("Undercity", 1497, "city"),
]
NAME = {a: n for n, a, _k in ZONES}
KIND = {a: k for _n, a, k in ZONES}

# The other faction's home zones: no guide there, even when a few neutral
# quests would qualify.
NOT_FOR = {
    "Horde": {"Elwynn Forest", "Dun Morogh", "Teldrassil", "Westfall", "Loch Modan", "Darkshore",
              "Redridge Mountains", "Duskwood", "Wetlands"},
    "Alliance": {"Durotar", "Mulgore", "Tirisfal Glades", "Silverpine Forest"},
}

# The suggested order (#next). The 1-20 part depends on where your race
# starts; from there everyone follows the main list. A zone that isn't in a
# list (Alliance in the Barrens) still gets a guide, just no #next.
CHAINS = {
    "Alliance": {
        "lead": [["Elwynn Forest", "Westfall", "Redridge Mountains"],
                 ["Dun Morogh", "Loch Modan", "Redridge Mountains"],
                 ["Teldrassil", "Darkshore", "Ashenvale"],
                 ["Zephras Isle", "Darkshore"]],
        "main": ["Redridge Mountains", "Duskwood", "Wetlands", "Ashenvale", "Stonetalon Mountains",
                 "Hillsbrad Foothills", "Alterac Mountains", "Arathi Highlands", "Stranglethorn Vale",
                 "Thousand Needles", "Desolace", "Shen'dralas", "Dustwallow Marsh", "Swamp of Sorrows",
                 "Badlands", "Riverglades", "The Hinterlands", "Feralas", "Tanaris", "Searing Gorge",
                 "Blasted Lands", "Azshara", "Felwood", "Un'Goro Crater", "Burning Steppes",
                 "Western Plaguelands", "Eastern Plaguelands", "Winterspring", "Silithus", "Moonglade"],
    },
    "Horde": {
        "lead": [["Durotar", "The Barrens"], ["Mulgore", "The Barrens"], ["Zephras Isle", "The Barrens"],
                 ["Tirisfal Glades", "Silverpine Forest", "The Barrens"]],
        "main": ["The Barrens", "Stonetalon Mountains", "Ashenvale", "Hillsbrad Foothills",
                 "Thousand Needles", "Desolace", "Shen'dralas", "Alterac Mountains", "Arathi Highlands",
                 "Stranglethorn Vale", "Dustwallow Marsh", "Swamp of Sorrows", "Badlands", "Riverglades",
                 "Feralas", "Tanaris", "The Hinterlands", "Searing Gorge", "Blasted Lands", "Azshara",
                 "Felwood", "Un'Goro Crater", "Burning Steppes", "Western Plaguelands",
                 "Eastern Plaguelands", "Winterspring", "Silithus", "Moonglade"],
    },
}

# Forever's dungeons with the zone whose guide points at them
# (the guides themselves are in Guides/openxp/Dungeons-*.lua).
DUNGEON_AREAS = {
    # instance area -> (dungeon guide name, levels)
    1581: "The Deadmines", 717: "The Stockade", 718: "Wailing Caverns", 719: "Blackfathom Deeps",
    721: "Gnomeregan", 209: "Shadowfang Keep", 491: "Razorfen Kraul", 796: "Scarlet Monastery",
    722: "Razorfen Downs", 1337: "Uldaman", 2100: "Maraudon", 1176: "Zul'Farrak",
    1477: "Sunken Temple", 1584: "Blackrock Depths", 1583: "Blackrock Spire", 2557: "Dire Maul",
    2057: "Scholomance", 2017: "Stratholme", 2437: "Ragefire Chasm",
    16544: "City of Dalaran", 16611: "Ruins of Lordaeron", 16732: "Excavation Site: Wetlands",
    16985: "Shaper's Terrace", 17780: "Krol'dok Stronghold",
}
RACE_TAGS = [(1, "Human"), (4, "Dwarf"), (8, "NightElf"), (64, "Gnome"), (2, "Orc"),
             (16, "Undead"), (32, "Tauren"), (128, "Troll"), (4294967296, "Skyborne"),
             (8589934592, "Skyborne")]


def dungeon_guides(faction):
    """{quest id: dungeon guide name} for the quests the OpenXP dungeon guides
    pick up, read from Guides/openxp/Dungeons-*.lua."""
    import glob
    import re
    out = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "Guides", "openxp", "Dungeons-*%s.lua" % faction))):
        name = None
        for line in open(path, encoding="utf-8"):
            m = re.match(r"#name (.+)", line.strip())
            if m:
                name = m.group(1)
            m = re.match(r"\s*\.accept (\d+)", line)
            if m and name:
                out.setdefault(int(m.group(1)), name)
    return out


def faction_mask(faction):
    return (br.ALLIANCE_RACES | 4294967296) if faction == "Alliance" else (br.HORDE_RACES | 8589934592)


class Q:
    """A quest as the completion builder sees it."""
    def __init__(self, quest):
        self.q = quest
        self.id = quest.id
        self.home = None        # area id where it's done
        self.start = None       # (kind, id, area, point)
        self.finish = None
        self.sites = []         # (idx, kind, label, mobs, area, point)
        self.tags = []          # class / race restrictions for the step
        self.dungeon = None     # instance area, for dungeon quests


class World:
    def __init__(self, db, faction):
        self.db = db
        self.faction = faction
        br.FACTION = faction
        self.b = br.Builder(db, set(), set())
        self.mask = faction_mask(faction)

    # where things are --------------------------------------------------
    def spawn_areas(self, ent, idx):
        sp = br.li(ent, idx)
        if isinstance(sp, list):
            sp = {i + 1: v for i, v in enumerate(sp)}
        return [a for a, pts in (sp or {}).items() if pts] if isinstance(sp, dict) else []

    def place(self, group, q):
        """(kind, id, area, point) for a quest starter/finisher list."""
        best = None
        for nid in br.as_list(br.li(group, 1)):
            n = self.b.npc(nid)
            if not n or not self.b.friendly(nid):
                continue
            for a in self.spawn_areas(n, 7):
                if a in NAME:
                    pts = br.spawns_in(n, a, 7)
                    if pts:
                        cand = ("npc", nid, a, pts[0])
                        # prefer the quest's own zone, then non-capitals
                        rank = (a != q.zone, KIND.get(a) == "city")
                        if best is None or rank < best[0]:
                            best = (rank, cand)
        if best:
            return best[1]
        for oid in br.as_list(br.li(group, 2)):
            o = self.db["o"].get(oid)
            for a in self.spawn_areas(o, 4):
                if a in NAME:
                    pts = br.spawns_in(o, a, 4)
                    if pts:
                        return ("obj", oid, a, pts[0])
        for iid in br.as_list(br.li(group, 3)):
            # a quest started by an item that drops from mobs (or lies on
            # the ground): go to where it drops
            it = self.db["i"].get(iid)
            if not it:
                continue
            spots = collections.defaultdict(list)
            mob = {}
            for nid in br.as_list(br.li(it, 2)):
                n = self.b.npc(nid)
                if not n or (br.li(n, 6) or 0) in (1, 2, 3):
                    continue
                for a in self.spawn_areas(n, 7):
                    if a in NAME and KIND.get(a) != "city":
                        pts = br.spawns_in(n, a, 7)
                        spots[a] += pts
                        mob.setdefault(a, br.li(n, 1))
            for oid in br.as_list(br.li(it, 3)):
                o = self.db["o"].get(oid)
                for a in self.spawn_areas(o, 4):
                    if a in NAME and KIND.get(a) != "city":
                        spots[a] += br.spawns_in(o, a, 4)
                        mob.setdefault(a, None)
            if spots:
                a = q.zone if q.zone in spots else max(spots, key=lambda k: len(spots[k]))
                if len(spots) <= 3:  # a world drop isn't a zone quest
                    return ("item", iid, a, br.cluster_center(spots[a]), mob.get(a), br.li(it, 1))
        return None

    def objective_areas(self, q):
        """Counter of area -> objectives that can be done there, and the set
        of instance areas the objectives are in."""
        c = collections.Counter()
        inst = set()
        obj = q.objectives or {}

        def add(areas):
            areas = set(areas)
            for a in areas:
                if a in NAME:
                    c[a] += 1
                elif a in DUNGEON_AREAS:
                    inst.add(a)
        for e in br.as_list(br.li(obj, 1)):
            add(self.spawn_areas(self.b.npc(e[0]), 7))
        for e in br.as_list(br.li(obj, 2)):
            add(self.spawn_areas(self.db["o"].get(e[0]), 4))
        for e in br.as_list(br.li(obj, 3)):
            it = self.db["i"].get(e[0])
            areas = set()
            for nid in br.as_list(br.li(it, 2)):
                areas |= set(self.spawn_areas(self.b.npc(nid), 7))
            for oid in br.as_list(br.li(it, 3)):
                areas |= set(self.spawn_areas(self.db["o"].get(oid), 4))
            add(areas)
        for e in br.as_list(br.li(obj, 5)):
            areas = set()
            for nid in br.as_list(e[0]):
                areas |= set(self.spawn_areas(self.b.npc(nid), 7))
            add(areas)
        if q.triggerEnd:
            locs = br.li(q.triggerEnd, 2) or {}
            add(locs.keys() if isinstance(locs, dict) else [])
        return c, inst

    # which quests ---------------------------------------------------------
    def candidates(self, dungeon_quests=None):
        dungeon_quests = dungeon_quests or {}
        out = {}
        dungeon = {}
        dropped = collections.Counter()
        for quest in self.b.quests():
            q = quest
            if not q.name or q.name.startswith("[") or "<" in q.name:
                continue
            if q.races and not (q.races & self.mask):
                continue
            if self.b.season_of_discovery(q) or q.specialFlags & 1 or q.reqSkill or q.reqRep:
                continue
            if q.zone in br.EVENT_SORTS or q.zone in (16941, 16606, 2597, 3277, 3358):
                continue  # holidays, crafting writs, battlegrounds, Darkspear Islands PvP
            if br.li(q.objectives, 4):
                continue  # reputation grinds
            if q.level >= 61 or q.level <= 0:
                continue
            start = self.place(q.startedBy, q)
            if not start:
                if br.as_list(br.li(q.startedBy, 3)):
                    dropped["started by an item"] += 1
                else:
                    dropped["no quest giver in the data yet"] += 1
                continue
            finish = self.place(q.finishedBy, q)
            if q.id in dungeon_quests:
                x = Q(q)
                x.start, x.finish, x.dungeon = start, finish, dungeon_quests[q.id]
                x.tags = self.tags(q)
                dungeon[q.id] = x
                continue
            areas, inst = self.objective_areas(q)
            has_obj = bool(q.objectives and any(br.as_list(br.li(q.objectives, k)) for k in (1, 2, 3, 5))) \
                or bool(q.triggerEnd)
            if not has_obj and finish and finish[:2] == start[:2]:
                # Given and taken by the same NPC with nothing to do in the
                # data: the objectives just aren't in the data yet (a new
                # Forever quest). Use the quest's own text.
                text = " ".join(t for t in br.as_list(br.li(self.db["q"][q.id], 8)) if isinstance(t, str))
                if text and q.id >= 90000 and q.zone in NAME and KIND.get(q.zone) != "city":
                    has_obj, areas = True, collections.Counter({q.zone: 1})
            x = Q(q)
            x.start, x.finish = start, finish
            if has_obj and len(areas) >= 6:
                dropped["can be done anywhere (cloth, war effort)"] += 1
                continue
            if has_obj and not areas:
                if inst or q.zone not in NAME or KIND.get(q.zone) == "city" or self.elite(q):
                    dropped["in a dungeon" if inst else "objectives not on any zone map"] += 1
                    continue
                # Forever's new quests: the data often doesn't have the
                # objective spots yet. Do them in the quest's zone from the
                # quest log, like the Riverglades guide does.
                areas = collections.Counter({q.zone: 1})
            if has_obj:
                top = max(areas.values())
                tied = [a for a, n in areas.items() if n == top]
                home = q.zone if q.zone in tied else (start[2] if start[2] in tied else
                                                      sorted(tied, key=lambda a: KIND.get(a) == "city")[0])
            else:
                home = start[2]
                if KIND.get(home) == "city" or (finish and KIND.get(finish[2]) != "city" and finish[2] != home):
                    home = finish[2] if finish else home
            if KIND.get(home) == "city":
                dropped["done inside a capital"] += 1
                continue
            x.home = home
            if has_obj:
                nearby = [(a, NAME[a], (1.0, 0.0, 0.0)) for a in areas if a != home]
                sites = self.b.objective_sites(q, home, nearby)
                if not sites:
                    if self.elite(q):
                        dropped["elite / group objectives"] += 1
                        continue
                    if q.id < 90000:
                        dropped["objectives not on any zone map"] += 1
                        continue
                    # a new quest with objectives the data can't place yet
                    text = " ".join(t for t in br.as_list(br.li(self.db["q"][q.id], 8)) if isinstance(t, str))
                    n = sum(len(br.as_list(br.li(q.objectives or {}, k))) for k in (1, 2, 3, 5)) or 1
                    sites = [(i, "text", text or q.name, [], None, None) for i in range(1, n + 1)]
                x.sites = []
                for (idx, kind, label, mobs, pt, place) in sites:
                    if place:
                        a = next(a for a in areas if NAME[a] == place[0])
                        x.sites.append((idx, kind, label, mobs, a, (place[1], place[2])))
                    else:
                        x.sites.append((idx, kind, label, mobs, home, pt))
            x.tags = self.tags(q)
            out[q.id] = x
        return out, dungeon, dropped

    def elite(self, q):
        for e in br.as_list(br.li(q.objectives, 1)):
            n = self.b.npc(e[0])
            if n and (br.li(n, 6) or 0) in (1, 2, 3):
                return True
        return False

    def tags(self, q):
        t = []
        c = q.class_tag()
        if c:
            t.append(c)
        if q.races and (q.races & self.mask) != self.mask:
            names = []
            for bit, nm in RACE_TAGS:
                if q.races & bit & self.mask and nm not in names:
                    names.append(nm)
            if names:
                t.append("/".join(names))
        return t


# ---------------------------------------------------------------------------
# One zone
# ---------------------------------------------------------------------------

def zone_levels(qs, area=None):
    """The zone's level band, from the zone's own quests for everyone (class
    and race quests, and chain steps from other zones, can be far off the
    zone's level)."""
    plain = [x for x in qs if not x.tags and x.q.zone == area]
    if len(plain) < MIN_QUESTS:
        plain = [x for x in qs if not x.tags] or qs
    lv = sorted(x.q.level for x in plain)
    rq = sorted(max(1, x.q.reqLevel) for x in plain)
    lo = rq[len(rq) // 10]
    hi = lv[min(len(lv) - 1, (len(lv) * 85) // 100)]
    return max(1, lo), max(lo + 1, hi)


# A quest more than this many levels over the zone's band is left to the
# zone or guide where you'd be that level (a late chain step that walks you
# back to a low zone, a level 40 mount quest in a starting zone).
OUTLIER = 4


def zone_quests(qs, area):
    """(lo, hi, kept, outliers) for one zone's quests."""
    qs = list(qs)
    lo, hi = zone_levels(qs, area)
    keep = [x for x in qs if x.q.level <= hi + OUTLIER and x.q.reqLevel <= hi + OUTLIER - 2
            and not (x.tags and x.q.level < lo - 6)]
    out = [x for x in qs if x not in keep]
    if out:
        lo, hi = zone_levels(keep, area)
    return lo, hi, keep, out


class ZoneSim:
    def __init__(self, world, area, quests, leadouts, all_homes):
        self.w = world
        self.area = area
        self.qs = quests            # qid -> Q (home here)
        self.leadouts = leadouts    # qid -> Q (accepted here, done elsewhere)
        self.all_homes = all_homes  # qid -> home area for every candidate
        self.steps = []

    def prereqs(self, x):
        q = x.q
        group = [p for p in q.preGroup if p]
        single = [p for p in q.preSingle if p]
        return group, single

    def run(self, lo, hi):
        w = self.w
        qs = dict(self.qs)
        # exclusive quests: keep the first one
        taken = set()
        for qid in sorted(qs):
            ex = set(qs[qid].q.exclusiveTo)
            if ex & taken:
                del qs[qid]
                continue
            taken.add(qid)
        # start at the level you'd normally walk in at: the first level
        # where a good share of the zone's quests are open
        level = float(lo)
        for L in ([] if KIND.get(self.area) == "start" else range(lo, hi + 1)):
            n = sum(1 for x in qs.values() if x.q.reqLevel <= L and x.q.level <= L + LEVELS_ABOVE)
            if n >= 0.35 * len(qs):
                level = float(L)
                break
        self.start_level = level
        self.grind = 0.0
        xp = br.xp_at_level(level)
        done, inlog, objdone = set(), set(), set()
        # deliveries from another zone arrive in your log
        for qid, x in qs.items():
            if x.start[2] != self.area and KIND.get(x.start[2]) != "city" and x.start[0] != "item":
                inlog.add(qid)  # picked up at the end of that zone's guide
        accepted_leadouts = set()
        first = min(qs.values(), key=lambda x: (x.q.reqLevel, x.q.level, x.id))
        pos = (first.start[2], first.start[3]) if first.start[2] == self.area else (self.area, (50.0, 50.0))
        breadcrumb_of = collections.defaultdict(list)
        for qid, x in qs.items():
            if x.q.breadcrumbFor and x.q.breadcrumbFor in qs:
                breadcrumb_of[x.q.breadcrumbFor].append(qid)

        def ok_prereqs(x):
            group, single = self.prereqs(x)
            for p in group:
                if p in qs and p not in done:
                    return False
            here = [p for p in single if p in qs]
            if here and len(here) == len(single) and not any(p in done for p in here):
                return False
            for b in breadcrumb_of.get(x.id, ()):
                if b in inlog:
                    return False   # turn the breadcrumb in first
            return True

        skipped = set()

        def acceptable(x):
            """Could be picked up now, apart from your level."""
            if x.id in done or x.id in inlog or x.id in skipped:
                return False
            if x.q.breadcrumbFor and x.q.breadcrumbFor in done | inlog:
                skipped.add(x.id)  # the quest it leads to is already taken
                return False
            return ok_prereqs(x)

        def can_open(x, lvl):
            return x.q.reqLevel <= lvl and x.q.level <= lvl + LEVELS_ABOVE

        def cost(a_pt):
            a, pt = a_pt
            if pt is None:
                return 1.0
            if a != pos[0]:
                return OTHER_AREA + math.dist((50, 50), pt) * 0.1
            return math.dist(pos[1], pt)

        lvl = level
        stalls = 0
        while True:
            lvl = br.level_of(xp)
            acts = []
            # pick-ups
            if len(inlog) < LOG_LIMIT:
                for qid, x in qs.items():
                    if acceptable(x) and can_open(x, lvl):
                        acts.append(("accept", x, None, (x.start[2], x.start[3])))
                for qid, x in self.leadouts.items():
                    if qid in accepted_leadouts or not can_open(x, lvl):
                        continue
                    group, _single = self.prereqs(x)
                    if any(p in qs and p not in done for p in group):
                        continue
                    if any(p in qs and p not in done for p in _single) and not any(p in done for p in _single):
                        continue
                    acts.append(("leadout", x, None, (x.start[2], x.start[3])))
            for qid in inlog:
                x = qs[qid]
                left = [s for s in x.sites if (qid, s[0]) not in objdone]
                for s in left:
                    acts.append(("obj", x, s, (s[4], s[5]) if s[1] != "text" else (pos[0], None)))
                if not left:
                    acts.append(("turnin", x, None, (x.finish[2], x.finish[3]) if x.finish else (pos[0], None)))
            if acts and not any(apt[0] == self.area or apt[1] is None for _k, _x, _s, apt in acts):
                # Only trips to other zones are left for now. Make the trip
                # if it's needed to go on here (a pick-up for this zone, or a
                # turn-in that opens the next quest); otherwise keep the
                # turn-ins for one trip at the end.
                waiting = [x for qid, x in qs.items() if acceptable(x)]
                if waiting:
                    unlocks = {p for x in waiting for p in list(x.q.preGroup) + list(x.q.preSingle)}
                    urgent = [t for t in acts if t[0] == "accept" or t[1].id in unlocks
                              or t[3][0] == pos[0]]  # already there: do it now
                    acts = urgent
            if not acts:
                rest = [x for qid, x in qs.items() if acceptable(x)]
                if not rest:
                    break
                need = min(max(x.q.reqLevel, x.q.level - LEVELS_ABOVE) for x in rest)
                if need <= int(lvl):
                    break  # can't happen, but don't loop
                n_open = sum(1 for x in rest if max(x.q.reqLevel, x.q.level - LEVELS_ABOVE) <= need)
                self.steps.append(dict(kind="xp", level=need, count=n_open))
                self.grind += need - lvl
                xp = max(xp, br.xp_at_level(need))
                stalls += 1
                if stalls > 40:
                    break
                continue

            def pref(a):
                kind, x, s, apt = a
                c = cost(apt)
                if kind == "turnin":
                    c *= 0.9
                if kind == "leadout":
                    c += 120  # leads to another zone: pick it up near the end
                return c
            kind, x, s, apt = min(acts, key=pref)
            if apt[1] is not None:
                pos = (apt[0], apt[1])
            if kind == "accept":
                inlog.add(x.id)
                self.steps.append(dict(kind="accept", x=x, where=x.start))
            elif kind == "leadout":
                accepted_leadouts.add(x.id)
                self.steps.append(dict(kind="accept", x=x, where=x.start, leadout=True))
            elif kind == "obj":
                objdone.add((x.id, s[0]))
                self.steps.append(dict(kind="obj", x=x, site=s))
                if not x.q.class_tag():
                    xp += br.KILLS.get(s[1], 0) * br.mob_xp(max(1, x.q.level - 1), lvl)
            else:
                inlog.discard(x.id)
                done.add(x.id)
                self.steps.append(dict(kind="turnin", x=x, where=x.finish))
                if not x.q.class_tag():
                    xp += br.quest_xp(x.q.level, lvl, x.id)
        self.done = done
        self.left = [x for qid, x in qs.items() if qid not in done and qid not in skipped]
        self.end_level = br.level_of(xp)
        return self.steps


# ---------------------------------------------------------------------------
# Writing guides
# ---------------------------------------------------------------------------

def merge_talks(steps):
    """Turn-ins and pick-ups at the same NPC become one step."""
    out = []
    for st in steps:
        if st["kind"] in ("accept", "turnin") and st.get("where"):
            key = st["where"][:2]
            prev = out[-1] if out else None
            if prev and prev["kind"] == "talk" and prev["key"] == key and \
                    not (st["kind"] == "turnin" and prev["accept"]):
                prev[st["kind"]].append(st)
                continue
            out.append(dict(kind="talk", key=key, where=st["where"], accept=[], turnin=[]))
            out[-1][st["kind"]].append(st)
            continue
        out.append(st)
    return out


def step_line(x):
    return "step << " + " ".join(x.tags) if x.tags else "step"


def render(world, area, steps, dungeon_pickups, lo, hi, nxt, faction):
    db = world.db
    zname = NAME[area]

    def who(kind, eid):
        e = db["n" if kind == "npc" else "o"].get(eid)
        return br.li(e, 1) or "?"

    def goto(a, pt):
        return "    .goto %s,%.2f,%.2f" % (NAME[a], pt[0], pt[1])

    lines = ["step", "    #completewith next",
             "    .zone %s >>Get to %s" % (zname, zname)]
    cur_area = area
    for st in merge_talks(steps):
        if st["kind"] == "talk":
            kind, eid, a, pt = st["where"][:4]
            if a != cur_area and a != area:
                lines.extend(["step", "    #completewith next",
                              "    .zone %s >>Travel to %s" % (NAME[a], NAME[a])])
            elif a == area and cur_area != area:
                lines.extend(["step", "    #completewith next",
                              "    .zone %s >>Head back to %s" % (zname, zname)])
            cur_area = a
            # a step with a class/race-only quest gets its own step so the
            # tag can hide it
            groups = collections.OrderedDict()
            for s in st["turnin"] + st["accept"]:
                groups.setdefault(tuple(s["x"].tags), {"turnin": [], "accept": []})
            for s in st["turnin"]:
                groups[tuple(s["x"].tags)]["turnin"].append(s)
            for s in st["accept"]:
                groups[tuple(s["x"].tags)]["accept"].append(s)
            for tags, g in groups.items():
                lines.append("step << " + " ".join(tags) if tags else "step")
                lines.append(goto(a, pt))
                if kind == "item":
                    mob, item = st["where"][4], st["where"][5]
                    if mob:
                        lines.append("    >>Kill |cRXP_ENEMY_%s|r. Loot |cRXP_LOOT_%s|r and click it to start the quest" % (mob, item))
                    else:
                        lines.append("    >>Find |cRXP_LOOT_%s|r and click it to start the quest" % item)
                    lines.append("    .collect %d,1" % eid)
                    for s in g["accept"]:
                        lines.append("    .accept %d >>Accept %s" % (s["x"].id, s["x"].q.name))
                    if mob:
                        lines.append("    .mob %s" % mob)
                    continue
                nm = who(kind, eid)
                if kind == "npc":
                    lines.append("    >>Talk to |cRXP_FRIENDLY_%s|r" % nm)
                else:
                    lines.append("    >>Click the |cRXP_PICK_%s|r" % nm)
                for s in g["turnin"]:
                    lines.append("    .turnin %d >>Turn in %s" % (s["x"].id, s["x"].q.name))
                for s in g["accept"]:
                    extra = ""
                    if s.get("leadout"):
                        extra = " (%s %s)" % ("it's done in" if s["x"].sites else "it leads to", NAME[s["x"].home])
                    lines.append("    .accept %d >>Accept %s%s" % (s["x"].id, s["x"].q.name, extra))
                if kind == "npc":
                    lines.append("    .target %s" % nm)
        elif st["kind"] == "turnin":   # finisher not known
            x = st["x"]
            lines.extend([step_line(x)] + [
                "    >>Turn in |cRXP_WARN_%s|r. The quest data doesn't say who takes it yet, so follow your quest log" % x.q.name,
                "    .turnin %d >>Turn in %s" % (x.id, x.q.name)])
        elif st["kind"] == "obj":
            x, s = st["x"], st["site"]
            idx, kind, label, mobs, a, pt = s
            if a != cur_area:
                lines.extend(["step", "    #completewith next",
                              "    .zone %s >>%s %s" % (NAME[a], "Head back to" if a == area else "Travel to", NAME[a])])
                cur_area = a
            lines.append(step_line(x))
            if kind == "text":
                lines.append("    >>%s |cRXP_WARN_(no map spot for this yet: use your quest log and map)|r" % label)
            else:
                lines.append(goto(a, pt))
                if kind == "kill":
                    lines.append("    >>Kill |cRXP_ENEMY_%s|r" % label)
                elif kind == "loot":
                    if mobs:
                        lines.append("    >>Kill |cRXP_ENEMY_%s|r. Loot them for |cRXP_LOOT_%s|r" % (mobs[0], label))
                    else:
                        lines.append("    >>Collect |cRXP_LOOT_%s|r" % label)
                elif kind == "use":
                    lines.append("    >>Click |cRXP_PICK_%s|r" % label)
                elif kind == "credit":
                    lines.append("    >>%s" % label)
                else:
                    lines.append("    >>Explore %s" % (label or "the area"))
            lines.append("    .complete %d,%d --%s" % (x.id, idx, x.q.name))
            if kind in ("kill", "loot", "credit"):
                for m in mobs[:2]:
                    lines.append("    .mob %s" % m)
        elif st["kind"] == "xp":
            lines.extend(["step",
                          "    .xp %d >>%d more quest%s here open at level %d. Kill mobs on the way until then, "
                          "or do another zone and come back"
                          % (st["level"], st["count"], "" if st["count"] == 1 else "s", st["level"])])
    if dungeon_pickups:
        names = sorted({x.dungeon for x in dungeon_pickups})
        lines.extend(["step",
                      "    #completewith next",
                      "    >>|cRXP_WARN_Dungeon quests: %s hands out quests for %s. Pick them up now if you plan to run "
                      "the dungeon; the OpenXP Dungeons guide (%s) does the rest. Skip these steps if you don't.|r"
                      % (zname, " and ".join(n.split(" ", 1)[1] for n in names), ", ".join(names))])
        byg = collections.OrderedDict()
        for x in sorted(dungeon_pickups, key=lambda x: (x.start[2] != area, x.start[3], x.id)):
            byg.setdefault(x.start[:2], (x.start, []))[1].append(x)
        for _k, (where, xs) in byg.items():
            kind, eid, a, pt = where[:4]
            if kind == "item":
                continue
            lines.append(step_line(xs[0]) if all(x.tags == xs[0].tags for x in xs) else "step")
            lines.append(goto(a, pt))
            nm = who(kind, eid)
            lines.append("    >>%s |cRXP_FRIENDLY_%s|r" % ("Talk to" if kind == "npc" else "Click the", nm))
            for x in xs:
                lines.append("    .accept %d >>Accept %s (%s)" % (x.id, x.q.name, x.dungeon.split(" ", 1)[1]))
            if kind == "npc":
                lines.append("    .target %s" % nm)
    tag = faction
    head = ["RXPGuides.RegisterGuide([[", "#forever", "#version 1", "<< " + tag,
            "#group " + GROUP, "#subgroup Zone by zone", "#name %d-%d %s" % (lo, hi, zname)]
    for cond, n in nxt:
        head.append("#next %s%s" % (n, (" << " + cond) if cond else ""))
    return head + [""] + lines + ["]])", ""]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    ap.add_argument("--dump", help="WTF/.../SavedVariables/OpenXP.lua with /oxp questdump")
    ap.add_argument("--faction", default="Alliance")
    ap.add_argument("--zone", help="build only this zone (for testing)")
    ap.add_argument("--report", help="write a per-zone report here (markdown)")
    a = ap.parse_args()
    br.FACTION = a.faction
    base = br.load_db(a.questiedb)
    if a.dump:
        base = br.merge_db(base, br.load_dump_cached(a.dump, a.questiedb))
    db = forever_data.load(a.questiedb, base=base, quiet=True)
    w = World(db, a.faction)
    cands, dungeon, dropped = w.candidates(dungeon_guides(a.faction))

    by_home = collections.defaultdict(dict)
    leadouts = collections.defaultdict(dict)
    for qid, x in cands.items():
        by_home[x.home][qid] = x
        if not x.sites and x.start[2] != x.home and KIND.get(x.start[2]) != "city":
            leadouts[x.start[2]][qid] = x
    dungeon_from = collections.defaultdict(list)
    for x in dungeon.values():
        if KIND.get(x.start[2]) != "city" and x.start[0] != "item":
            dungeon_from[x.start[2]].append(x)

    zones = []
    outliers = []
    for name, area, kind in ZONES:
        if kind == "city" or name in NOT_FOR[a.faction] or len(by_home.get(area, {})) < MIN_QUESTS:
            continue
        lo, hi, keep, out = zone_quests(by_home[area].values(), area)
        for x in out:
            outliers.append((name, x))
        by_home[area] = {x.id: x for x in keep}
        if len(keep) < MIN_QUESTS:
            continue
        zones.append((lo, hi, name, area, kind))
    # A quest picked up in one zone and done in another (not a capital):
    # the zone that hands it out picks it up at the end of its guide when
    # the level fits, and the zone where it's done starts with it in your
    # log. When the level doesn't fit, it's left out rather than sending you
    # across the world for one quest.
    bands = {z[3]: (z[0], z[1]) for z in zones}
    far = 0
    for home, qs in by_home.items():
        for qid, x in list(qs.items()):
            st = x.start[2]
            if st == home or KIND.get(st) == "city" or x.start[0] == "item" or not x.sites:
                continue
            if st in bands and bands[st][0] - 2 <= x.q.level <= bands[st][1] + 3:
                leadouts[st][qid] = x
            else:
                del qs[qid]
                far += 1
    dropped["picked up far from where it's done"] += far
    zones.sort(key=lambda z: (z[4] != "start", z[0], z[1], z[2]))
    order = [z for z in zones if z[4] != "start"]

    built = {z[2]: z for z in zones}

    def nxt(name):
        """The next zone in the faction's chains that has a guide."""
        ch = CHAINS[a.faction]
        for seq in ch["lead"]:
            if name in seq[:-1]:
                for n in seq[seq.index(name) + 1:]:
                    if n in built:
                        return n
                return nxt_main(seq[-1])
        return nxt_main(name) if name in ch["main"] else None

    def nxt_main(name):
        seq = CHAINS[a.faction]["main"]
        for n in seq[seq.index(name) + 1:] if name in seq else seq:
            if n in built:
                return n
        return None

    def next_of(z):
        n = nxt(z[2])
        if not n:
            return []
        o = built[n]
        return [(None, "%d-%d %s" % (o[0], o[1], o[2]))]

    out_lines = ["-- OpenXP zone completion guides (%s) for WoW Forever." % a.faction,
                 "-- Generated by tools/build_completion.py from Questie's Forever data.",
                 "-- A separate guide set: it never changes the 21-60 speed route.",
                 'local faction = UnitFactionGroup("player")',
                 'if faction ~= "%s" then return end' % a.faction,
                 "local L = GetLocale() if L and RXP.enabledLocale[L] then return end", ""]
    report = ["# Zone completion: %s" % a.faction, "",
              "| Zone | Levels | Quests in guide | Starts at | Ends at | Levels to grind |", "|---|---|---|---|---|---|"]
    total = 0
    for z in zones:
        lo, hi, name, area, kind = z
        if a.zone and a.zone != name:
            continue
        sim = ZoneSim(w, area, by_home[area], leadouts.get(area, {}), None)
        steps = sim.run(lo, hi)
        total += len(sim.done)
        dq = [x for x in dungeon_from.get(area, []) if lo - 3 <= x.q.level <= hi + 6]
        out_lines += render(w, area, steps, dq, lo, hi, next_of(z), a.faction)
        report.append("| %s | %d-%d | %d | %d | %.1f | %.1f |" % (name, lo, hi, len(sim.done), sim.start_level, sim.end_level, sim.grind))
        print("%-22s %2d-%2d  %3d quests, %2d left out, %2d -> %.1f, grind %.1f"
              % (name, lo, hi, len(sim.done), len(sim.left), sim.start_level, sim.end_level, sim.grind))
        for x in sim.left:
            print("     left: %d %s (L%d req %d)" % (x.id, x.q.name, x.q.level, x.q.reqLevel))
    report += ["", "Quests not in any zone guide: " + ", ".join("%s %d" % (k, v) for k, v in dropped.most_common()),
               "", "Dungeon quests pointed at the dungeon guides: %d" % len(dungeon)]
    report += ["", "Left out as far above their zone's level (%d):" % len(outliers), ""]
    report += ["- %s: %s (level %d)" % (n, x.q.name, x.q.level) for n, x in outliers]
    print("total %d quests in %d zone guides; not used: %s" % (total, len(zones), dict(dropped)))
    if not a.zone:
        path = os.path.join(ROOT, "Guides", "openxp", "Completion-%s.lua" % a.faction)
        open(path, "w").write("\n".join(out_lines))
        print("wrote", os.path.relpath(path, ROOT))
    if a.report:
        open(a.report, "w").write("\n".join(report) + "\n")


if __name__ == "__main__":
    main()
