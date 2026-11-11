#!/usr/bin/env python3
"""Add class quest chains to the 21-60 route without moving it.

The shared route in Guides/openxp is frozen (Matt, 2026-11-11: players follow
it live, and a route that reshuffles strands them). This tool only ADDS
steps tagged for one class (`step << Warlock`), placed where the route
already goes when it can:

- each quest's pickup, objectives and turn-in go into the first section, at
  or after the chain's last step, that's in the same zone (or town) and at a
  level where the quest is open, next to the route step closest to it;
- when no such section comes within a few levels, the step goes at the end
  of the first section that's at the right level, preferring one on the same
  continent: a detour, and the report says so.

Steps it wrote carry a `--oxp-class` line, and are taken out first on every
run, so running it again gives the same files, and the shared steps stay
byte for byte what they were.

Usage:
    python3 tools/class_steps.py --questiedb <QuestieDB> --dump <OpenXP.lua> \
        --facts facts.pkl [--report report.md] Alliance
"""
import argparse
import glob
import math
import os
import pickle
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_route as B  # noqa: E402

ROOT = B.ROOT
MARK = "    --oxp-class"
WINDOW = 4       # levels: how far ahead to look for a visit to the right zone
NEAR_STEP = 9.0  # map units: an NPC this close to a route step is "on the way"

K, E = "Kalimdor", "Eastern Kingdoms"
# AreaTable zone id -> (name RXP knows, continent)
AREAS = {
    331: ("Ashenvale", K), 406: ("Stonetalon Mountains", K), 405: ("Desolace", K),
    16651: ("Shen'dralas", K), 15: ("Dustwallow Marsh", K), 400: ("Thousand Needles", K),
    440: ("Tanaris", K), 357: ("Feralas", K), 16: ("Azshara", K), 490: ("Un'Goro Crater", K),
    361: ("Felwood", K), 618: ("Winterspring", K), 1377: ("Silithus", K), 1657: ("Darnassus", K),
    148: ("Darkshore", K), 141: ("Teldrassil", K), 17: ("The Barrens", K), 493: ("Moonglade", K),
    215: ("Mulgore", K), 14: ("Durotar", K),
    11: ("Wetlands", E), 44: ("Redridge Mountains", E), 10: ("Duskwood", E),
    267: ("Hillsbrad Foothills", E), 45: ("Arathi Highlands", E), 33: ("Stranglethorn Vale", E),
    8: ("Swamp of Sorrows", E), 3: ("Badlands", E), 47: ("The Hinterlands", E),
    51: ("Searing Gorge", E), 4: ("Blasted Lands", E), 46: ("Burning Steppes", E),
    28: ("Western Plaguelands", E), 139: ("Eastern Plaguelands", E), 1519: ("Stormwind City", E),
    1537: ("Ironforge", E), 12: ("Elwynn Forest", E), 40: ("Westfall", E), 38: ("Loch Modan", E),
    1: ("Dun Morogh", E), 36: ("Alterac Mountains", E), 41: ("Deadwind Pass", E),
    130: ("Silverpine Forest", E), 85: ("Tirisfal Glades", E),
    1637: ("Orgrimmar", K), 1638: ("Thunder Bluff", K), 1497: ("Undercity", E),
}
# Zones the other faction's players don't go to: quest objectives and
# givers there are ignored (an herb that also grows in Teldrassil is picked
# in the Barrens). Only used for Horde, so the Alliance steps stay as they are.
HOSTILE = {
    "Horde": {141, 1657, 12, 40, 1, 38, 1519, 1537},
    "Alliance": set(),
}
HOSTILE_NOW = set()
FACTION_LETTER = "A"
AREA_OF = {v[0]: k for k, v in AREAS.items()}
RACE_NAMES = [(1, "Human"), (4, "Dwarf"), (8, "NightElf"), (64, "Gnome")]
HORDE_RACE_NAMES = [(2, "Orc"), (16, "Undead"), (32, "Tauren"), (128, "Troll")]


# ---------------------------------------------------------------------------
# The frozen guides
# ---------------------------------------------------------------------------

class Section:
    def __init__(self, path, head, steps, tail):
        self.path, self.head, self.steps, self.tail = path, head, steps, tail
        m = re.search(r"^#name (\d+)-(\d+) (.+)$", head, re.M)
        self.name = m.group(0)[6:] if m else "?"
        self.level = int(m.group(1)) if m else 0
        zone = m.group(3) if m else ""
        zone = re.sub(r" \(part \d+\)$", "", zone)
        self.area = AREA_OF.get(zone)
        self.inserts = {}  # step index -> [step text], added after that step

    def points(self):
        """(index, area, (x, y)) of each step's .goto"""
        out = []
        for i, s in enumerate(self.steps):
            m = re.search(r"\.goto ([^,\n]+),([\d.]+),([\d.]+)", s)
            if m and AREA_OF.get(m.group(1)):
                out.append((i, AREA_OF[m.group(1)], (float(m.group(2)), float(m.group(3)))))
        return out

    def render(self):
        parts = [self.head]
        for i, s in enumerate(self.steps):
            parts.append(s)
            parts.extend(self.inserts.get(i, []))
        return "".join(parts) + self.tail


def load_sections(faction):
    files, sections = {}, []
    for path in sorted(glob.glob(os.path.join(ROOT, "Guides", "openxp", faction + "-*.lua"))):
        text = open(path, encoding="utf-8").read()
        files[path] = []
        pos = 0
        for m in re.finditer(r"RXPGuides\.RegisterGuide\(\[\[\n(.*?)\n\]\]\)", text, re.S):
            body = m.group(1) + "\n"
            first = body.find("\nstep")
            head = text[pos:m.start()] + "RXPGuides.RegisterGuide([[\n" + body[:first + 1]
            rest = body[first + 1:]
            steps = re.findall(r"step[^\n]*\n(?:(?!step\b)[^\n]*\n)*", rest)
            assert "".join(steps) == rest, path
            steps = [x for x in steps if MARK + "\n" not in x]  # ours, from a last run
            s = Section(path, head, steps, "]])")
            files[path].append(s)
            sections.append(s)
            pos = m.end()
        files[path].append(text[pos:])  # whatever follows the last section
    return files, sections


def write_files(files):
    for path, parts in files.items():
        out = "".join(p.render() if isinstance(p, Section) else p for p in parts)
        open(path, "w", encoding="utf-8").write(out)


# ---------------------------------------------------------------------------
# Where each part of a quest is done
# ---------------------------------------------------------------------------

def spawn_zones(entity, idx):
    sp = B.li(entity, idx)
    if isinstance(sp, list):
        sp = {i + 1: v for i, v in enumerate(sp)}
    if not isinstance(sp, dict):
        return {}
    return {z: [tuple(p) for p in B.as_list(v) if p and len(p) == 2 and p[0] >= 0]
            for z, v in sp.items() if z in AREAS and z not in HOSTILE_NOW}


def givers(db, ref):
    """[(kind, id, name, area, point)] for startedBy / finishedBy"""
    out = []
    for nid in B.as_list(B.li(ref, 1)):
        n = db["n"].get(nid)
        if not n:
            continue
        f = B.li(n, 13)
        if f is not None and FACTION_LETTER not in f:
            continue
        for z, pts in spawn_zones(n, 7).items():
            if pts:
                out.append(("npc", nid, B.li(n, 1), z, pts[0]))
    for oid in B.as_list(B.li(ref, 2)):
        o = db["o"].get(oid)
        if not o:
            continue
        for z, pts in spawn_zones(o, 4).items():
            if pts:
                out.append(("obj", oid, B.li(o, 1), z, pts[0]))
    return out


def objectives(db, q):
    """[(index, kind, label, mobs, area, point, elite)] for each objective"""
    out = []
    obj = q.objectives or {}
    idx = 0

    def best(zones):
        zones = {z: p for z, p in zones.items() if p}
        if not zones:
            return None, None
        z = max(zones, key=lambda k: len(zones[k]))
        return z, B.cluster_center(zones[z])

    for entry in B.as_list(B.li(obj, 1)):
        idx += 1
        n = db["n"].get(entry[0])
        if not n:
            continue
        z, p = best(spawn_zones(n, 7))
        if z:
            out.append((idx, "kill", B.li(n, 1), [B.li(n, 1)], z, p, (B.li(n, 6) or 0) in (1, 2, 3)))
    for entry in B.as_list(B.li(obj, 2)):
        idx += 1
        o = db["o"].get(entry[0])
        if not o:
            continue
        z, p = best(spawn_zones(o, 4))
        label = entry[1] if len(entry) > 1 and entry[1] else B.li(o, 1)
        if z:
            out.append((idx, "use", label, [], z, p, False))
    for entry in B.as_list(B.li(obj, 3)):
        idx += 1
        item = db["i"].get(entry[0])
        if not item:
            continue
        zones, names, elite = {}, {}, True
        for nid in B.as_list(B.li(item, 2)):
            n = db["n"].get(nid)
            if not n:
                continue
            e = (B.li(n, 6) or 0) in (1, 2, 3)
            for z, pts in spawn_zones(n, 7).items():
                zones.setdefault(z, []).extend(pts)
                names.setdefault(z, []).append(B.li(n, 1))
                elite = elite and e
        for oid in B.as_list(B.li(item, 3)):
            o = db["o"].get(oid)
            for z, pts in (spawn_zones(o, 4) if o else {}).items():
                zones.setdefault(z, []).extend(pts)
                elite = False
        z, p = best(zones)
        if z:
            out.append((idx, "loot", B.li(item, 1), names.get(z, [])[:3], z, p, elite and bool(names.get(z))))
    for entry in B.as_list(B.li(obj, 5)):
        idx += 1
        zones, names = {}, {}
        for nid in B.as_list(entry[0]):
            n = db["n"].get(nid)
            for z, pts in (spawn_zones(n, 7) if n else {}).items():
                zones.setdefault(z, []).extend(pts)
                names.setdefault(z, []).append(B.li(n, 1))
        z, p = best(zones)
        label = entry[2] if len(entry) > 2 and entry[2] else (names.get(z) or ["target"])[0]
        if z:
            out.append((idx, "credit", label, names.get(z, [])[:3], z, p, False))
    if q.triggerEnd:
        locs = B.li(q.triggerEnd, 2) or {}
        zones = {z: [tuple(x) for x in B.as_list(v) if x] for z, v in (locs.items() if isinstance(locs, dict) else []) if z in AREAS}
        z, p = best(zones)
        if z:
            idx += 1
            out.append((idx, "explore", B.li(q.triggerEnd, 1), [], z, p, False))
    return out


# ---------------------------------------------------------------------------
# Placing a chain
# ---------------------------------------------------------------------------

def class_tag(q, cls):
    """'Warlock', or 'Human Warrior/Dwarf Warrior' for a race's own quest
    (in a tag a space means and, a slash means or)"""
    names = [n for b, n in RACE_NAMES if q.races & b] if q.races else []
    if len(names) == len(RACE_NAMES) or not names:
        return cls
    return "/".join("%s %s" % (n, cls) for n in names)


class Placer:
    def __init__(self, sections):
        self.sections = sections

    def place(self, cursor, area, pt, level):
        """(section index, step index) for something done at area/pt once
        you're `level`, at or after `cursor`. Second value: True if it's a
        detour (the route doesn't go there then)."""
        si0, st0 = cursor
        cont = AREAS[area][1]
        first_ok = None
        for si in range(si0, len(self.sections)):
            s = self.sections[si]
            if s.level < level - 0.5:
                continue
            if s.level > max(level, self.sections[si0].level) + WINDOW:
                break
            if first_ok is None:
                first_ok = si
            best = None
            for i, a, p in s.points():
                if a != area or (si == si0 and i < st0):
                    continue
                d = math.dist(p, pt)
                if best is None or d < best[0]:
                    best = (d, i)
            if best and (best[0] <= NEAR_STEP or s.area == area):
                return (si, best[1]), False
        # nothing on the way: a detour at the end of a section at the right
        # level, on the same continent if one comes soon
        pick = None
        for si in range(max(si0, first_ok or si0), len(self.sections)):
            s = self.sections[si]
            if s.level < level - 0.5:
                continue
            if pick is None:
                pick = si
            if s.area and AREAS.get(s.area, ("", ""))[1] == cont:
                pick = si
                break
            if s.level > max(level, self.sections[si0].level) + WINDOW:
                break
        if pick is None:
            pick = len(self.sections) - 1
        st = len(self.sections[pick].steps) - 1
        if pick == si0:
            st = max(st, st0)
        return (pick, st), True


def chain_events(db, chain, skip=()):
    """The chain's quests in order. A tuple in the chain is one quest offered
    by different givers (Elune's Grace from the priest trainer in each
    capital): do whichever comes first. A quest (or any of its
    alternatives) in `skip` is left out."""
    out, alts = [], {}
    for item in chain["quests"]:
        ids = item if isinstance(item, tuple) else (item,)
        group = [B.Quest(i, db["q"][i]) for i in ids if i in db["q"]]
        if not group or any(i in skip for i in ids):
            continue
        out.append(group[0])
        alts[group[0].id] = group
    return out, alts


CLASSES = ["Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"]


def _applies(tag, cls):
    toks = re.split(r"[\s/,]+", tag.strip())
    if cls in [t[1:] for t in toks if t.startswith("!")]:
        return False
    pos = [t for t in toks if t in CLASSES]
    return not pos or cls in pos


def free_guide_state(faction, cls):
    """(picked up and still in the log, turned in) after the 1-20 guides,
    for this class"""
    acc, turned = set(), set()
    for path in glob.glob(os.path.join(ROOT, "Guides", "forever", faction + "*.lua")):
        for g in open(path, encoding="utf-8").read().split("RegisterGuide(")[1:]:
            h = re.search(r"^<<\s*([^\n]*)", g, re.M)
            if h and not _applies(h.group(1), cls):
                continue
            for ch in re.split(r"\n(?=step\b)", g):
                t = re.match(r"step\s*<<\s*([^\n]*)", ch)
                if t and not _applies(t.group(1), cls):
                    continue
                turned |= {int(x) for x in re.findall(r"\.turnin\s+-?(\d+)", ch)}
                if not re.search(r"\.(isOnQuest|isQuestTurnedIn)\b", ch):
                    acc |= {int(x) for x in re.findall(r"\.accept\s+(\d+)", ch)}
    return acc - turned, turned


def build(db, sections, chains, faction):
    placer = Placer(sections)
    report = []
    in_route = set()
    for sec in sections:
        for st in sec.steps:
            in_route |= {int(x) for x in re.findall(r"\.(?:accept|turnin|complete)\s+-?(\d+)", st)}
    ends = {}
    for chain in chains:
        carried, turned = free_guide_state(faction, chain["cls"])
        # from_start: the 1-20 guide does the first parts, but players often
        # haven't (Matt still had part 1 of the Prospector at 23), so the
        # chain starts at the beginning and parts you've done skip themselves
        done_before = turned if chain.get("from_start") else set()
        quests, alts = chain_events(db, chain, skip=(turned - done_before) | in_route)
        accepted_in = {}

        def sign(q, pos):
            # picked up in another file (or before 21), or maybe done
            # already: skip if not in the log
            if q.id in done_before:
                return -1
            return 1 if accepted_in.get(q.id) == sections[pos[0]].path else -1
        cursor = ends.get(chain.get("after"), (0, 0))
        added, detours, minutes = [], [], 0
        start_level = None
        for q in quests:
            options = alts[q.id]
            if chain.get("race"):
                tag = "step << " + "/".join("%s %s" % (r, chain["cls"]) for r in chain["race"].split("/"))
            else:
                tag = "step << " + class_tag(q, chain["cls"])
            level = max(q.reqLevel, q.level - 2)
            start_level = start_level or level
            group = q.id in chain.get("group", ())
            # pickup: the giver reached first
            gl = []
            for o in options:
                for g in givers(db, o.startedBy):
                    gl.append((o, g))
            if gl and not any(o.id in carried for o in options):
                best = None
                for o, g in gl:
                    pos, det = placer.place(cursor, g[3], g[4], level)
                    if best is None or (pos, det) < (best[0], best[1]):
                        best = (pos, det, o, g)
                pos, det, o, g = best
                q = o  # the one you'll have: its objectives and turn-in
                put(sections, pos, render_talk(tag, g, [("accept", o)]))
                accepted_in[o.id] = sections[pos[0]].path
                for alt in options:
                    accepted_in[alt.id] = sections[pos[0]].path
                cursor = pos
                if det:
                    detours.append("%s pickup in %s" % (o.name, AREAS[g[3]][0]))
            for idx, kind, label, mobs, z, p, elite in objectives(db, q):
                pos, det = placer.place(cursor, z, p, max(level, q.level - 1))
                put(sections, pos, render_obj(tag, q, idx, kind, label, mobs, z, p, elite or group,
                                              sign(q, pos)))
                cursor = pos
                if det:
                    detours.append("%s objective in %s" % (q.name, AREAS[z][0]))
            fl = givers(db, q.finishedBy)
            if fl:
                best = None
                for g in fl:
                    pos, det = placer.place(cursor, g[3], g[4], level)
                    if best is None or (pos, det) < (best[0], best[1]):
                        best = (pos, det, g)
                pos, det, g = best
                put(sections, pos, render_talk(tag, g, [("turnin", q)], sign(q, pos)))
                cursor = pos
                if det:
                    detours.append("%s turn-in in %s" % (q.name, AREAS[g[3]][0]))
        ends[chain["name"]] = cursor
        xp = sum(((B.FACTS or {}).get("quest", {}).get(q.id) or {}).get("xp") or 0 for q in quests)
        report.append((chain, start_level, cursor, [q.id for q in quests], detours, xp))
    return report


def put(sections, pos, text):
    si, st = pos
    steps = sections[si].steps
    # never between a "#completewith next" step and the step it waits for
    while st + 1 < len(steps) and "#completewith next" in steps[st]:
        st += 1
    lst = sections[si].inserts.setdefault(st, [])
    # the same person again right after (turn one in, pick up the next):
    # one step
    if lst and ".target " in text:
        head = text.split("\n")[:4]
        prev = lst[-1].split("\n")
        if prev[:4] == head and prev[-2].startswith("    .target"):
            body = [l for l in text.split("\n")[4:] if l.startswith(("    .accept", "    .turnin"))]
            lst[-1] = "\n".join(prev[:-2] + body + prev[-2:])
            return
    lst.append(text)


def render_talk(tag, g, acts, sign=1):
    kind, gid, name, area, p = g
    lines = [tag, MARK, "    .goto %s,%.2f,%.2f" % (AREAS[area][0], p[0], p[1])]
    if kind == "npc":
        lines.append("    >>Talk to |cRXP_FRIENDLY_%s|r" % name)
    else:
        lines.append("    >>Click the |cRXP_PICK_%s|r" % name)
    for verb, q in acts:
        if verb == "accept":
            lines.append("    .accept %d >>Accept %s" % (q.id, q.name))
        else:
            lines.append("    .turnin %d >>Turn in %s" % (sign * q.id, q.name))
    if kind == "npc":
        lines.append("    .target %s" % name)
    return "\n".join(lines) + "\n"


def render_obj(tag, q, idx, kind, label, mobs, area, p, hard, sign=1):
    lines = [tag, MARK, "    .goto %s,%.2f,%.2f" % (AREAS[area][0], p[0], p[1])]
    if kind == "kill":
        t = "Kill |cRXP_ENEMY_%s|r" % label
    elif kind == "loot" and mobs:
        t = "Kill |cRXP_ENEMY_%s|r. Loot them for |cRXP_LOOT_%s|r" % ("|r and |cRXP_ENEMY_".join(mobs), label)
    elif kind == "loot":
        t = "Loot the |cRXP_PICK_%s|r" % label
    else:
        t = label or "Explore the area"
    lines.append("    >>" + t)
    if hard:
        lines.append("    >>|cRXP_WARN_This is an elite or group part: bring help, or skip this step|r")
    lines.append("    .complete %d,%d --%s" % (sign * q.id, idx, q.name))
    for m in mobs:
        lines.append("    .mob %s" % m)
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    ap.add_argument("--dump")
    ap.add_argument("--facts")
    ap.add_argument("--report")
    ap.add_argument("faction", choices=["Alliance", "Horde"])
    args = ap.parse_args()
    B.GAME, B.FACTION = "Forever", args.faction
    global RACE_NAMES, HOSTILE_NOW, FACTION_LETTER
    HOSTILE_NOW = HOSTILE[args.faction]
    FACTION_LETTER = args.faction[0]
    if args.faction == "Horde":
        RACE_NAMES = HORDE_RACE_NAMES
    if args.facts:
        B.FACTS = pickle.load(open(args.facts, "rb"))
    db = B.load_db(args.questiedb)
    if args.dump:
        db = B.merge_db(db, B.load_dump_cached(args.dump, args.questiedb))
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "routes"))
    import class_chains
    chains = getattr(class_chains, args.faction.upper())
    files, sections = load_sections(args.faction)
    report = build(db, sections, chains, args.faction)
    write_files(files)
    lines = []
    for chain, lvl, cursor, added, detours, xp in report:
        end = sections[cursor[0]].name
        lines.append("%s: %s (%s), %d quests, about %d XP, from level %s, done by %s; %d detour(s)%s" % (
            chain["cls"], chain["name"], chain["why"], len(added), xp, lvl, end, len(detours),
            (": " + "; ".join(detours)) if detours else ""))
    text = "\n".join(lines)
    print(text)
    if args.report:
        open(args.report, "w").write(text + "\n")


if __name__ == "__main__":
    main()
