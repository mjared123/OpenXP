#!/usr/bin/env python3
"""Compare OpenXP's guides against Questie's quest data and list the gaps.

For each faction it lists, zone by zone, the quests your faction can do that
no OpenXP guide picks up, plus guide quest IDs that Questie doesn't know.
Questie's data is only read from your own copies of QuestieDB and Questie,
never copied into OpenXP; the report goes to a file outside the guides.

Usage:
    python tools/audit_guides.py --questiedb PATH/TO/QuestieDB-repo \
        --questie "PATH/TO/AddOns/Questie" [--game Forever] [--out report.md]
"""
import argparse
import glob
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import build_route as br  # noqa: E402

DUNGEON_CONTINENT = 9


def zone_names(questie):
    """{areaId: (name, continentKey)} from Questie's zone lookup."""
    path = os.path.join(questie, "Localization", "lookups", "lookupZones.lua")
    text = open(path, encoding="utf-8").read()
    body = text.split("l10n.zoneLookup = {", 1)[1]
    names, cont = {}, None
    for line in body.split("\n"):
        m = re.match(r"^\s*\[(\d+)\]\s*=\s*\{\s*$", line)
        if m:
            cont = int(m.group(1))
            continue
        for zid, name in re.findall(r"\[(\d+)\]\s*=\s*\"([^\"]+)\"", line):
            names.setdefault(int(zid), (name, cont))
        if line.startswith("}"):
            break
    return names


def blacklist(questie):
    path = os.path.join(questie, "Database", "Corrections", "QuestieQuestBlacklist.lua")
    if not os.path.exists(path):
        return set()
    text = open(path, encoding="utf-8").read()
    return {int(x) for x in re.findall(r"^\s*\[(\d+)\]\s*=\s*true", text, re.M)}


def guide_quests(game, faction):
    """Quest IDs any of this faction's guides accept or turn in."""
    if game == "Forever":
        paths = glob.glob(os.path.join(ROOT, "Guides", "forever", "*.lua"))
        paths += glob.glob(os.path.join(ROOT, "Guides", "openxp", "*.lua"))
    else:
        paths = glob.glob(os.path.join(ROOT, "Guides", "Classic-*.lua"))
        paths += glob.glob(os.path.join(ROOT, "Guides", "openxp-classic", "*.lua"))
    other = "Horde" if faction == "Alliance" else "Alliance"
    seen, by_file = set(), {}
    for path in paths:
        base = os.path.basename(path).replace("Classic-", "")
        if base.startswith(other):
            continue
        text = open(path, encoding="utf-8").read()
        ids = {int(x) for x in re.findall(r"\.(?:accept|turnin|complete)\s+-?(\d+)", text)}
        by_file[os.path.relpath(path, ROOT)] = ids
        seen |= ids
    return seen, by_file


def tags(q, zones):
    t = []
    if q.class_tag():
        t.append(q.class_tag())
    if q.reqSkill:
        t.append("profession")
    if q.reqRep:
        t.append("reputation")
    z = zones.get(q.zone or 0)
    if z and z[1] == DUNGEON_CONTINENT:
        t.append("dungeon")
    if q.zone is not None and q.zone < 0:
        t.append("category %d" % q.zone)
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True, help="QuestieDB repo checkout (has data/Forever)")
    ap.add_argument("--questie", required=True, help="Questie addon folder (zone names, blacklist)")
    ap.add_argument("--game", default="Forever")
    ap.add_argument("--dump", help="OpenXP.lua saved variables with /oxp questdump data")
    ap.add_argument("--out", help="report file (default: openxp-audit.md in the QuestieDB folder)")
    args = ap.parse_args()

    br.GAME = args.game
    db = br.load_db(args.questiedb, args.game)
    if args.dump:
        db = br.merge_db(db, br.load_dump(args.dump))
    zones = zone_names(args.questie)
    banned = blacklist(args.questie)

    out = ["# OpenXP guide audit (%s)" % args.game, "",
           "Quests your faction can do that no OpenXP guide picks up, by zone.",
           "Tags: class-only, profession, reputation, dungeon. Untagged quests are",
           "the ones to look at first for the leveling routes.", ""]
    for faction in ("Alliance", "Horde"):
        br.FACTION = faction
        in_guides, _ = guide_quests(args.game, faction)
        missing = defaultdict(list)
        total = defaultdict(int)
        known = set()
        for qid, row in db["q"].items():
            if qid in banned:
                continue
            q = br.Quest(qid, row)
            if not q.for_faction():
                continue
            known.add(qid)
            key = q.zone if q.zone is not None else 0
            total[key] += 1
            if qid not in in_guides:
                missing[key].append(q)
        unknown = sorted(in_guides - set(db["q"]))

        def zone_label(z):
            if z in zones:
                return zones[z][0]
            return "Zone %d" % z if z >= 0 else "Category %d" % z

        def sort_key(z):
            qs = missing[z]
            lv = sorted(q.level for q in qs)
            return (zones.get(z, ("", 99))[1] == DUNGEON_CONTINENT, lv[len(lv) // 2] if lv else 0)

        plain = sum(1 for z in missing for q in missing[z] if not tags(q, zones))
        out += ["## %s" % faction, "",
                "%d quests in Questie for %s, %d in the guides, %d missing (%d untagged)."
                % (len(known), faction, len(in_guides & known),
                   sum(len(v) for v in missing.values()), plain), ""]
        out += ["| Zone | Missing | In zone | Levels |", "|---|---|---|---|"]
        for z in sorted(missing, key=sort_key):
            lv = sorted(q.level for q in missing[z])
            out.append("| %s | %d | %d | %d-%d |" % (zone_label(z), len(missing[z]), total[z], lv[0], lv[-1]))
        out.append("")
        for z in sorted(missing, key=sort_key):
            out.append("### %s (%s)" % (zone_label(z), faction))
            for q in sorted(missing[z], key=lambda q: (q.level, q.id)):
                t = tags(q, zones)
                out.append("- %d %s (lvl %d, min %d)%s" % (q.id, q.name, q.level, q.reqLevel,
                                                         " [" + ", ".join(t) + "]" if t else ""))
            out.append("")
        if unknown:
            out += ["### Guide quest IDs Questie doesn't know (%s)" % faction, "",
                    ", ".join(str(i) for i in unknown), ""]
    args.out = args.out or os.path.join(args.questiedb, "openxp-audit-%s.md" % args.game.lower())
    open(args.out, "w", encoding="utf-8").write("\n".join(out))
    print("wrote", args.out)


if __name__ == "__main__":
    main()
