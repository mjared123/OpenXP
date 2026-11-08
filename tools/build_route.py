#!/usr/bin/env python3
"""Generate OpenXP leveling guide sections from quest data.

Reads Questie's WoW Forever data (github.com/Questie/QuestieDB, data/Forever)
and a route plan (tools/routes/*.py), and writes guide files in the
RestedXP/OpenXP guide format.

For each section of the plan it picks the zone's Alliance quests that fit the
level range, drops ones that need a dungeon, elites, professions, reputation or
quests we never pick up, and then walks the zone greedily: always do the
nearest available thing (accept, quest objective, or turn in), respecting
quest chains and the quest log limit. Steps at the same spot are merged.

The output is a first draft. It's meant to be played, then hand-tuned.

Usage:
    python3 tools/build_route.py --questiedb PATH/TO/QuestieDB tools/routes/alliance_21_30.py
"""
import argparse
import glob
import importlib.util
import math
import os
import pickle
import re
import sys

from lupa import luajit21 as lupa

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


def load_db(questiedb):
    cache = os.path.join(questiedb, ".openxp-cache.pkl")
    if os.path.exists(cache):
        return pickle.load(open(cache, "rb"))
    d = os.path.join(questiedb, "data", "Forever")
    db = {
        "q": _load_table(os.path.join(d, "foreverQuestDB.lua"), "questData"),
        "n": _load_table(os.path.join(d, "foreverNpcDB.lua"), "npcData"),
        "o": _load_table(os.path.join(d, "foreverObjectDB.lua"), "objectData"),
        "i": _load_table(os.path.join(d, "foreverItemDB.lua"), "itemData"),
    }
    pickle.dump(db, open(cache, "wb"))
    return db


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


def cluster_center(points, radius=4.0):
    """Densest spot: the point with the most neighbours within radius, averaged."""
    if not points:
        return None
    best, best_n = None, -1
    for p in points:
        n = [q for q in points if math.dist(p, q) <= radius]
        if len(n) > best_n:
            best, best_n = n, len(n)
    x = sum(p[0] for p in best) / len(best)
    y = sum(p[1] for p in best) / len(best)
    # Snap to the closest real spawn so the arrow points at something real.
    return min(best, key=lambda p: math.dist(p, (x, y)))

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

    file_accepted = set()

    def npc(self, nid):
        return self.db["n"].get(nid)

    def npc_name(self, nid):
        n = self.npc(nid)
        return li(n, 1) if n else "?"

    def friendly(self, nid):
        n = self.npc(nid)
        f = li(n, 13) if n else None
        return f is None or "A" in f

    def starter(self, q, zone):
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

    def objective_sites(self, q, zone):
        """List of (index, kind, label, mobs, point) for each objective, or None if
        an objective can't be done in this zone (dungeon, other zone, elite)."""
        sites = []
        obj = q.objectives or {}
        idx = 0
        for entry in as_list(li(obj, 1)):  # creatures
            idx += 1
            nid = entry[0]
            n = self.npc(nid)
            if not n or (li(n, 6) or 0) in (1, 2, 3):  # elite / rare elite / boss
                return None
            pts = spawns_in(n, zone, 7)
            if not pts:
                return None
            sites.append((idx, "kill", li(n, 1), [li(n, 1)], cluster_center(pts)))
        for entry in as_list(li(obj, 2)):  # objects
            idx += 1
            oid = entry[0]
            o = self.db["o"].get(oid)
            pts = spawns_in(o, zone, 4)
            if not pts:
                return None
            label = entry[1] if len(entry) > 1 and entry[1] else (li(o, 1) or "object")
            sites.append((idx, "use", label, [], cluster_center(pts)))
        for entry in as_list(li(obj, 3)):  # items
            idx += 1
            iid = entry[0]
            item = self.db["i"].get(iid)
            if not item:
                return None
            pts, mobs = [], []
            for nid in as_list(li(item, 2)):
                n = self.npc(nid)
                if n and (li(n, 6) or 0) not in (1, 2, 3):
                    p = spawns_in(n, zone, 7)
                    if p:
                        pts += p
                        mobs.append(li(n, 1))
            for oid in as_list(li(item, 3)):
                pts += spawns_in(self.db["o"].get(oid), zone, 4)
            if not pts:
                return None
            sites.append((idx, "loot", li(item, 1), mobs[:3], cluster_center(pts)))
        # reputation (4) objectives are never part of a leveling route
        if li(obj, 4):
            return None
        for entry in as_list(li(obj, 5)):  # kill credit
            idx += 1
            ids = as_list(entry[0])
            pts, mobs = [], []
            for nid in ids:
                n = self.npc(nid)
                if n:
                    p = spawns_in(n, zone, 7)
                    if p:
                        pts += p
                        mobs.append(li(n, 1))
            if not pts:
                return None
            label = entry[2] if len(entry) > 2 and entry[2] else (mobs[0] if mobs else "target")
            sites.append((idx, "credit", label, mobs[:3], cluster_center(pts)))
        if q.triggerEnd:
            text = li(q.triggerEnd, 1)
            locs = li(q.triggerEnd, 2) or {}
            pts = [tuple(p) for p in as_list(locs.get(zone) if isinstance(locs, dict) else None) if p]
            if not pts:
                return None
            idx += 1
            sites.append((idx, "explore", text, [], pts[0]))
        return sites

    def candidates(self, section, later_areas=()):
        """Quests to do in this section.

        Includes quests started here and finished here, quests started here
        and finished in a later section's zone (accepted and done here, turned
        in there), and quests carried in from earlier guides or sections that
        finish here.
        """
        zone = section["area"]
        lo, hi = section["levels"]
        out = {}
        for qid, row in self.db["q"].items():
            q = Quest(qid, row)
            if not q.alliance() or not q.name:
                continue
            if qid in self.done or qid in self.used:
                continue
            if q.specialFlags & 3 or q.reqSkill or q.reqRep:
                continue
            if q.name.startswith("[") or "<" in q.name:
                continue  # placeholder / unused quests in the data
            carried = qid in self.accepted_before
            if not carried:
                if q.level < lo - 3 or q.level > hi + 3 or q.reqLevel > hi:
                    continue
            start = None if carried else self.starter(q, zone)
            if not carried and not start:
                continue
            finish = self.finisher(q, zone)
            finish_later = None
            if not finish:
                if carried:
                    continue  # turned in somewhere else
                for later in later_areas:
                    if self.finisher(q, later):
                        finish_later = later
                        break
                if not finish_later:
                    continue
            if qid in self.objectives_done or (carried and qid in self.carried_ready):
                sites = []
            else:
                sites = self.objective_sites(q, zone)
                if sites is None:
                    continue
            out[qid] = dict(q=q, start=start, finish=finish, sites=sites,
                            carried=carried, finish_later=finish_later)
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
        """Greedy nearest-action walk. Returns list of actions."""
        zone = section["area"]
        accepted = set(q for q in self.accepted_before if q in cands)
        objectives_left = {qid: [s[0] for s in c["sites"]] for qid, c in cands.items()}
        turned_in = set()
        pos = start_pos
        actions = []

        def prereqs_ok(q):
            group_ok = all(p in self.done or p in turned_in for p in q.preGroup if p in cands or p not in self.done) \
                if q.preGroup else True
            if q.preGroup:
                group_ok = all((p in self.done) or (p in turned_in) for p in q.preGroup)
            single_ok = (not q.preSingle) or any((p in self.done) or (p in turned_in) for p in q.preSingle)
            return group_ok and single_ok

        while True:
            options = []
            for qid, c in cands.items():
                q = c["q"]
                if qid in turned_in:
                    continue
                if qid not in accepted:
                    if c["start"] and prereqs_ok(q) and len(accepted) < QUEST_LOG_LIMIT:
                        d = math.dist(pos, c["start"][2])
                        options.append((d - 0.5, "accept", qid, c["start"][2]))
                    continue
                left = objectives_left[qid]
                if left:
                    for s in c["sites"]:
                        if s[0] in left:
                            options.append((math.dist(pos, s[4]), "obj", (qid, s[0]), s[4]))
                elif c["finish"]:
                    d = math.dist(pos, c["finish"][2])
                    options.append((d - 0.5, "turnin", qid, c["finish"][2]))
            if not options:
                break
            options.sort(key=lambda o: (o[0], 0 if o[1] != "obj" else 1))
            _, kind, ref, where = options[0]
            pos = where
            if kind == "accept":
                accepted.add(ref)
            elif kind == "obj":
                qid, i = ref
                objectives_left[qid].remove(i)
                # Other objectives of the same quest at the same spot get done too.
                for s in cands[qid]["sites"]:
                    if s[0] in objectives_left[qid] and math.dist(s[4], where) < 2.5:
                        objectives_left[qid].remove(s[0])
                        actions.append(("obj", (qid, s[0]), where))
            elif kind == "turnin":
                accepted.discard(ref)
                turned_in.add(ref)
            actions.append((kind, ref, where))
        # Quests finished in a later zone travel on in the quest log.
        for qid in accepted:
            if cands[qid]["finish_later"] and not objectives_left[qid]:
                self.accepted_before.add(qid)
                self.carried_ready.add(qid)
        self.used |= turned_in
        self.done |= turned_in
        return actions, turned_in

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def fmt_coord(zone_name, p):
    return "%s,%.2f,%.2f" % (zone_name, p[0], p[1])


def render_section(builder, section, cands, actions, group, nxt):
    zname = section["zone"]
    lines = []
    lines.append("RXPGuides.RegisterGuide([[")
    lines.append("#forever")
    lines.append("#disabledungeons")
    lines.append("#version 1")
    lines.append("<< Alliance")
    lines.append("#group %s" % group)
    lines.append("#subgroup %s" % section.get("subgroup", "OpenXP 21-60"))
    lines.append("#name %s" % section["name"])
    if nxt:
        lines.append("#next %s" % nxt)
    lines.append("")
    for t in section.get("intro", []):
        lines.append(t)

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
        group_objs = [actions[i]]
        j = i + 1
        while j < len(actions) and actions[j][0] == "obj" and math.dist(actions[j][2], where) < 3.0:
            group_objs.append(actions[j])
            j += 1
        texts, completes, mobs_all, tags = [], [], [], set()
        for _, (qid, oi), _w in group_objs:
            c = cands[qid]
            site = next(s for s in c["sites"] if s[0] == oi)
            q = c["q"]
            tags.add(q.class_tag())
            _, okind, label, mobs, _ = site
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


def free_guide_quests():
    """Quests accepted / turned in by the guides already in Guides/forever."""
    accepted, turned = set(), set()
    for path in glob.glob(os.path.join(ROOT, "Guides", "forever", "*.lua")):
        if "dungeon" in path or not os.path.basename(path).startswith("Alliance"):
            continue
        text = open(path, encoding="utf-8").read()
        accepted |= {int(x) for x in re.findall(r"\.accept\s+(\d+)", text)}
        turned |= {int(x) for x in re.findall(r"\.turnin\s+-?(\d+)", text)}
    return accepted, turned


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    ap.add_argument("route")
    args = ap.parse_args()

    spec = importlib.util.spec_from_file_location("route", args.route)
    route = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(route)

    db = load_db(args.questiedb)
    accepted, turned = free_guide_quests()
    builder = Builder(db, done_before=turned, carried=accepted - turned)

    sections = route.SECTIONS
    out = [route.HEADER.rstrip(), ""]
    report = []
    for n, section in enumerate(sections):
        later = [s["area"] for s in sections[n + 1:]]
        cands = builder.candidates(section, later)
        actions, done = builder.simulate(section, cands, section["start"])
        nxt = sections[n + 1]["name"] if n + 1 < len(sections) else getattr(route, "NEXT", None)
        out.append(render_section(builder, section, cands, actions, route.GROUP, nxt))
        out.append("")
        report.append("%-36s %3d quests, %4d actions" % (section["name"], len(done), len(actions)))
        # carried quests that got turned in are no longer carried
        builder.accepted_before -= done
    path = os.path.join(ROOT, route.OUTPUT)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write("\n".join(out))
    print("\n".join(report))
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
