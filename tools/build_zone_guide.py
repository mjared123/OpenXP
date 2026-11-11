#!/usr/bin/env python3
"""Generate an optional stand-alone zone guide (Riverglades) from Questie's data.

This is not part of the 21-60 route: the guide sits in its own group, so adding
or rebuilding it never moves anyone on the main route.

The order is simple and greedy, in rounds from the faction's hub:
pick up every quest that is open, do the objectives nearest first, turn in,
then repeat for the quests the turn-ins opened. Quests whose giver Questie
doesn't know yet are listed in the report, not guessed.

Usage:
    python3 tools/build_zone_guide.py --questiedb PATH --faction Alliance|Horde
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_route as br

ROOT = br.ROOT

ZONES = {
    "Riverglades": dict(
        area=16591, map="Riverglades", levels=(36, 45),
        hub={"Alliance": ("Farholde Keep", (60.6, 81.6)), "Horde": ("Rog'mar", (59.6, 45.1))},
        how={"Alliance": "Fly to Farholde Keep (from Lakeshire, Morgan's Vigil or Thelsamar), "
                         "or take the road north from Redridge Mountains",
             "Horde": "Fly to Rog'mar (from Stonard, Kargath, Flame Crest or Hammerfall), "
                      "or take the road in from the Badlands or the Swamp of Sorrows"},
    ),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    ap.add_argument("--faction", default="Alliance")
    ap.add_argument("--zone", default="Riverglades")
    a = ap.parse_args()
    br.FACTION = a.faction
    z = ZONES[a.zone]
    area, mapname = z["area"], z["map"]
    lo, hi = z["levels"]
    db = br.load_db(a.questiedb)
    b = br.Builder(db, set(), set())

    usable, missing = {}, []
    for q in b.quests():
        if not q.name or not q.for_faction() or q.name.startswith("[") or "<" in q.name:
            continue
        if b.season_of_discovery(q) or q.specialFlags & 1 or q.reqSkill or q.reqRep:
            continue
        if q.classes and (q.classes & br.ALL_CLASSES) != br.ALL_CLASSES:
            continue
        if not (lo - 2 <= q.level <= hi + 2):
            continue
        st, fi = b.starter(q, area), b.finisher(q, area)
        in_zone = q.zone == area or st or fi
        if not in_zone:
            continue
        text = " ".join(x for x in br.as_list(br.li(db["q"][q.id], 8)) if isinstance(x, str))
        if "Stronghold" in text and "Krol'dok" in text:
            continue  # dungeon quests: in the Krol'dok dungeon guide
        if not st:
            missing.append(q)
            continue
        sites = b.objective_sites(q, area) if q.objectives else []
        if sites is None:
            # Questie doesn't know where the mobs or items are yet: show the
            # quest's own objective text, with no arrow
            obj = q.objectives or {}
            n = sum(len(br.as_list(br.li(obj, k))) for k in (1, 2, 3, 5))
            sites = [(i, "text", text, [], st[2], None) for i in range(1, n + 1)]
        usable[q.id] = (q, st, fi, sites)

    def prereqs(q):
        return [p for p in set(q.preSingle) | set(q.preGroup) if p]

    # a quest whose zone prerequisite we can't place stays out too
    changed = True
    while changed:
        changed = False
        for qid, (q, *_r) in list(usable.items()):
            for p in prereqs(q):
                if p >= 90000 and p not in usable:
                    missing.append(q)
                    del usable[qid]
                    changed = True
                    break

    def npc_name(kind, eid):
        e = db["n" if kind == "npc" else "o"].get(eid)
        return br.li(e, 1) or "?"

    lines = []
    pos = z["hub"][a.faction][1]
    done, inlog = set(), set()

    def near_first(items, key):
        nonlocal pos
        out = []
        items = list(items)
        while items:
            items.sort(key=lambda t: math.dist(pos, key(t)))
            t = items.pop(0)
            pos = key(t)
            out.append(t)
        return out

    def talk(where, kind, eid, accepts=(), turnins=()):
        who = npc_name(kind, eid)
        lines.extend(["step", "    .goto %s,%.2f,%.2f" % (mapname, where[0], where[1])])
        if kind == "npc":
            lines.append("    >>Talk to |cRXP_FRIENDLY_%s|r" % who)
        else:
            lines.append("    >>Click the |cRXP_PICK_%s|r" % who)
        for q in turnins:
            lines.append("    .turnin %d >>Turn in %s" % (q.id, q.name))
        for q in accepts:
            lines.append("    .accept %d >>Accept %s" % (q.id, q.name))
        if kind == "npc":
            lines.append("    .target %s" % who)

    lines.extend(["step", "    #completewith next",
                  "    .zone %s >>Get to %s: %s" % (mapname, z["hub"][a.faction][0], z["how"][a.faction])])
    rounds = 0
    tiers = sorted({max(lo, t[0].reqLevel) for t in usable.values()})
    cap = tiers.pop(0) if tiers else lo
    while True:
        open_q = [t for qid, t in usable.items() if qid not in done and qid not in inlog
                  and t[0].reqLevel <= cap
                  and not any(p in usable and p not in done for p in prereqs(t[0]))]
        if not open_q:
            if not tiers:
                break
            cap = tiers.pop(0)
            lines.extend(["step", "    .xp %d >>Kill mobs on the way until you're level %d: "
                                  "the next quests open then" % (cap, cap)])
            continue
        rounds += 1
        # pick-ups, grouped by giver
        givers = {}
        for t in open_q:
            st = t[1]
            givers.setdefault((st[0], st[1]), (st[2], []))[1].append(t[0])
        for (kind, eid), (pt, qs) in near_first(givers.items(), lambda kv: kv[1][0]):
            talk(pt, kind, eid, accepts=sorted(qs, key=lambda q: q.id))
            inlog.update(q.id for q in qs)
        # objectives, nearest first
        sites = []
        for t in open_q:
            q, _st, _fi, ss = t
            for (idx, kind, label, mobs, pt, place) in ss:
                sites.append((q, idx, kind, label, mobs, pt))
        textq = {}
        for q, idx, kind, label, mobs, pt in sites:
            if kind == "text":
                textq.setdefault(q.id, (q, label, []))[2].append(idx)
        sites = [s for s in sites if s[2] != "text"]
        for q, idx, kind, label, mobs, pt in near_first(sites, lambda s: s[5]):
            lines.extend(["step", "    .goto %s,%.2f,%.2f" % (mapname, pt[0], pt[1])])
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
                lines.append("    >>Explore %s" % label)
            lines.append("    .complete %d,%d --%s" % (q.id, idx, q.name))
            for m in mobs[:2] if kind in ("kill", "loot", "credit") else ():
                lines.append("    .mob %s" % m)
        for q, label, idxs in textq.values():
            lines.extend(["step", "    >>%s |cRXP_WARN_(no map spot for this yet: use your quest log and map)|r" % label])
            for i in idxs:
                lines.append("    .complete %d,%d --%s" % (q.id, i, q.name))
        # turn-ins, grouped by finisher
        enders, unknown = {}, []
        for t in open_q:
            q, _st, fi, _ss = t
            if fi:
                enders.setdefault((fi[0], fi[1]), (fi[2], []))[1].append(q)
            else:
                unknown.append(q)
        for (kind, eid), (pt, qs) in near_first(enders.items(), lambda kv: kv[1][0]):
            talk(pt, kind, eid, turnins=sorted(qs, key=lambda q: q.id))
        for q in unknown:
            lines.extend(["step", "    >>Turn in |cRXP_WARN_%s|r. Questie doesn't know who takes it yet, "
                                  "so follow the quest log" % q.name,
                          "    .turnin %d >>Turn in %s" % (q.id, q.name)])
        done.update(t[0].id for t in open_q)

    tag = "A" if a.faction == "Alliance" else "H"
    head = ["-- OpenXP %s %d-%d (%s), an optional zone guide for WoW Forever." % (a.zone, lo, hi, a.faction),
            "-- Generated by tools/build_zone_guide.py from Questie's Forever data. Not part",
            "-- of the 21-60 route, so it never changes where the main route sends you.",
            'local faction = UnitFactionGroup("player")',
            'if faction ~= "%s" then return end' % a.faction,
            "local L = GetLocale() if L and RXP.enabledLocale[L] then return end", "",
            "RXPGuides.RegisterGuide([[", "#forever", "#version 1", "<< " + a.faction,
            "#group OpenXP Zones", "#subgroup %d-%d" % (lo, hi),
            "#name %d-%d %s" % (lo, hi, a.zone), ""]
    path = os.path.join(ROOT, "Guides", "openxp", "%s-%s.lua" % (a.zone, a.faction))
    open(path, "w").write("\n".join(head + lines + ["]])", ""]))
    print("%s %s: %d quests in %d rounds, %d left out (no giver/objective data yet)"
          % (a.zone, tag, len(done), rounds, len(missing)))
    for q in sorted(missing, key=lambda q: (q.level, q.id)):
        print("   missing %d %s (L%d)" % (q.id, q.name, q.level))
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
