#!/usr/bin/env python3
"""Write DB/forever/QuestPrereqs.lua from QuestieDB's Forever data.

For every quest the Forever guides pick up or turn in:
  addon.openxpPrereqs[id] = {any=..., all=..., excl=...}  what it needs first
  addon.openxpChains[id]  = {ids...}  every earlier quest in its chain, in order
  addon.openxpQuestInfo[id] = {n=name, l=level, r=min level, s=start, f=finish,
                               o={objective spots}}  for every chain quest
A spot is {"Name", uiMapId, x, y}. The guide card uses this to explain a
step you can't do yet and to walk you through the quests before it.

Usage: python3 tools/build_prereqs.py --questiedb <QuestieDB checkout>
"""
import argparse, os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
import build_route as br

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def guide_files():
    xml = open(os.path.join(ROOT, "Guides", "GuideList-forever.xml")).read()
    return [os.path.join(ROOT, f) for f in re.findall(r'file="([^"]+\.lua)"', xml)]


def area_map(qdb):
    m = {}
    path = os.path.join(qdb, "support", "Zones", "areaIdToUiMapId.lua")
    for a, u in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", open(path).read()):
        m.setdefault(int(a), int(u))
    return m


def lua_str(s):
    return '"%s"' % (s or "").replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    a = ap.parse_args()
    db = br.load_db(a.questiedb)
    amap = area_map(a.questiedb)

    in_guides, alliance_guide = set(), set()
    for f in guide_files():
        text = open(f).read()
        ids = {abs(int(x)) for x in re.findall(r"^\s*\.(?:accept|turnin)\s+(-?\d+)", text, re.M)}
        in_guides |= ids
        if "Alliance" in os.path.basename(f):
            alliance_guide |= ids

    def quest(qid):
        row = db["q"].get(qid)
        return br.Quest(qid, row) if row else None

    def spot(entity, idx, prefer_area=None):
        sp = br.li(entity, idx)
        if not isinstance(sp, dict):
            return None
        best = None
        for area, pts in sp.items():
            pts = [tuple(p) for p in br.as_list(pts) if p and len(p) == 2 and p[0] >= 0]
            if not pts or not amap.get(area):
                continue
            score = (area == prefer_area, len(pts))
            if not best or score > best[0]:
                best = (score, area, pts)
        if not best:
            return None
        c = br.cluster_center(best[2])
        return amap[best[1]], c[0], c[1]

    def ender(q, which):
        ref = q.startedBy if which == "s" else q.finishedBy
        for nid in br.as_list(br.li(ref, 1)):
            n = db["n"].get(nid)
            fac = br.li(n, 13) if n else None
            if n and (fac is None or "A" in fac):
                s = spot(n, 7, q.zone)
                if s:
                    return (br.li(n, 1),) + s
        for oid in br.as_list(br.li(ref, 2)):
            o = db["o"].get(oid)
            s = spot(o, 4, q.zone) if o else None
            if s:
                return (br.li(o, 1),) + s
        for iid in br.as_list(br.li(ref, 3)):
            it = db["i"].get(iid)
            if it:
                return (br.li(it, 1), 0, 0, 0)
        return None

    def objectives(q):
        out = []
        obj = q.objectives or {}
        for entry in br.as_list(br.li(obj, 1)):
            n = db["n"].get(entry[0])
            s = spot(n, 7, q.zone) if n else None
            if s:
                out.append((br.li(n, 1),) + s)
        for entry in br.as_list(br.li(obj, 2)):
            o = db["o"].get(entry[0])
            s = spot(o, 4, q.zone) if o else None
            if s:
                out.append((br.li(o, 1),) + s)
        for entry in br.as_list(br.li(obj, 3)):
            it = db["i"].get(entry[0])
            if not it:
                continue
            for nid in br.as_list(br.li(it, 2))[:3]:
                n = db["n"].get(nid)
                s = spot(n, 7, q.zone) if n else None
                if s:
                    out.append((br.li(n, 1),) + s)
                    break
            else:
                for oid in br.as_list(br.li(it, 3))[:3]:
                    o = db["o"].get(oid)
                    s = spot(o, 4, q.zone) if o else None
                    if s:
                        out.append((br.li(o, 1),) + s)
                        break
        if q.triggerEnd:
            locs = br.li(q.triggerEnd, 2) or {}
            if isinstance(locs, dict):
                for area, pts in locs.items():
                    pts = [tuple(p) for p in br.as_list(pts) if p]
                    if pts and amap.get(area):
                        c = br.cluster_center(pts)
                        out.append((br.li(q.triggerEnd, 1),) + (amap[area], c[0], c[1]))
                        break
        return out[:4]

    def pick_single(ids):
        ids = [abs(x) for x in ids]
        qs = [quest(x) for x in ids]
        ok = [q for q in qs if q and q.alliance()]
        for q in ok:
            if q.id in alliance_guide:
                return q.id
        return ok[0].id if ok else None

    def parents(q):
        out = []
        if q.preSingle:
            p = pick_single(q.preSingle)
            if p:
                out.append(p)
        for p in q.preGroup:
            pq = quest(abs(p))
            if pq and pq.alliance():
                out.append(abs(p))
        return out

    def chain(qid):
        order, seen = [], set()

        def visit(x, depth):
            if x in seen or depth > 25:
                return
            seen.add(x)
            q = quest(x)
            if not q:
                return
            for p in parents(q):
                visit(p, depth + 1)
            order.append(x)
        visit(qid, 0)
        return order[:-1]

    prereqs, chains, info_ids = [], [], set()
    for qid in sorted(in_guides):
        q = quest(qid)
        if not q:
            continue
        parts = []
        if q.preSingle:
            parts.append("any={%s}" % ",".join(str(abs(x)) for x in q.preSingle))
        if q.preGroup:
            parts.append("all={%s}" % ",".join(str(abs(x)) for x in q.preGroup))
        if q.exclusiveTo:
            parts.append("excl={%s}" % ",".join(str(abs(x)) for x in q.exclusiveTo))
        if parts:
            prereqs.append("    [%d] = {%s}, -- %s" % (qid, ", ".join(parts), (q.name or "").replace("\n", " ")))
        if q.alliance():
            info_ids.add(qid)
            c = chain(qid)
            if c:
                chains.append("    [%d] = {%s}," % (qid, ",".join(map(str, c))))
                info_ids |= set(c)

    def spot_lua(s):
        return "{%s,%d,%.1f,%.1f}" % (lua_str(s[0]), s[1], s[2], s[3]) if s else "nil"

    infos = []
    for qid in sorted(info_ids):
        q = quest(qid)
        if not q:
            continue
        st, fi = ender(q, "s"), ender(q, "f")
        objs = ",".join(spot_lua(o) for o in objectives(q))
        infos.append("    [%d] = {n=%s, l=%d, r=%d, s=%s, f=%s, o={%s}}," % (
            qid, lua_str(q.name), q.level or 0, q.reqLevel or 0, spot_lua(st), spot_lua(fi), objs))

    out = os.path.join(ROOT, "DB", "forever", "QuestPrereqs.lua")
    with open(out, "w") as fh:
        fh.write("-- Generated by tools/build_prereqs.py from QuestieDB Forever data. Do not edit.\n")
        fh.write("-- Prereqs: any = one of these turned in, all = every one, excl = none of these done.\n")
        fh.write("-- Spots are {name, uiMapId, x, y}; uiMapId 0 means an item starts the quest.\n")
        fh.write("local _, addon = ...\n\naddon.openxpPrereqs = {\n")
        fh.write("\n".join(prereqs))
        fh.write("\n}\n\naddon.openxpChains = {\n")
        fh.write("\n".join(chains))
        fh.write("\n}\n\naddon.openxpQuestInfo = {\n")
        fh.write("\n".join(infos))
        fh.write("\n}\n")
    print("prereqs %d, chains %d, quest info %d -> %s" % (len(prereqs), len(chains), len(infos), out))


if __name__ == "__main__":
    main()
