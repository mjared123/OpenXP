#!/usr/bin/env python3
"""Build OpenXP/Data/QuestDB.lua from forever-db, the open quest database for
WoW Forever published in PoleStar's repository (forever-db/, GPL-3.0 for
the tables used here; credits in its NOTICE.md and in OpenXP/NOTICE.md).

    python3 tools/build_questdb.py [--src ../polestar-src/forever-db]

Kept, for every quest: title, levels, which races and classes can take it,
who starts and finishes it, its objectives, what must be done first and
which quest it is a breadcrumb for. For the NPCs and objects those name
(and whatever drops a quest's items): names and spawn points, turned into
zone map coordinates (0-100) with forever-db's ui_map frames. Items: names
and what drops them, for quest items only.

The file is read by Engine/ForeverDB.lua; Questie, when installed, is only
asked about what this data doesn't hold.
"""
import collections
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SRC = os.path.join(os.path.dirname(ROOT), "polestar-src", "forever-db")
OUT = os.path.join(ROOT, "OpenXP", "Data", "QuestDB.lua")


def rows(src, table):
    with open(os.path.join(src, "data", table + ".jsonl"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def bits(mask):
    """A client race/class mask -> the ids it allows (bit n-1 = id n)."""
    out, n = [], 1
    while mask:
        if mask & 1:
            out.append(n)
        mask >>= 1
        n += 1
    return out


def main(argv):
    src = DEFAULT_SRC
    if argv[:1] == ["--src"]:
        src = argv[1]
    index = json.load(open(os.path.join(src, "index.json"), encoding="utf-8"))
    repo = os.path.dirname(src)
    commit = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()

    quests = {r["id"]: r for r in rows(src, "quest")}
    start, finish = collections.defaultdict(list), collections.defaultdict(list)
    for r in rows(src, "quest_start"):
        start[r["quest"]].append((r["kind"], r["id"]))
    for r in rows(src, "quest_end"):
        finish[r["quest"]].append((r["kind"], r["id"]))
    objectives = collections.defaultdict(list)
    for r in rows(src, "quest_objective"):
        objectives[r["quest"]].append(r)
    pre_any, pre_all, breadcrumb_for = collections.defaultdict(list), collections.defaultdict(list), {}
    for r in rows(src, "quest_prereq"):
        if r.get("breadcrumb"):
            breadcrumb_for[r["pre"]] = r["quest"]  # r.pre leads to r.quest; not a real prerequisite
            continue
        (pre_any if r.get("mode") == "any" else pre_all)[r["quest"]].append(r["pre"])

    # the NPCs, objects and items the quests name
    want = {"npc": set(), "object": set(), "item": set()}
    for q in quests:
        for kind, ident in start[q] + finish[q]:
            want[kind].add(ident)
        for o in objectives[q]:
            k = {"kill": "npc", "talk": "npc", "item": "item", "object": "object"}.get(o["kind"])
            if k and o.get("target"):
                want[k].add(o["target"])
    drops = collections.defaultdict(lambda: {"npc": [], "object": []})
    for r in rows(src, "item_source"):
        if r["item"] in want["item"] and r["kind"] in ("npc", "object"):
            d = drops[r["item"]][r["kind"]]
            if r["id"] not in d and len(d) < 12:
                d.append(r["id"])
                want[r["kind"]].add(r["id"])

    names = {}
    for kind in ("npc", "object", "item"):
        names[kind] = {r["id"]: r["name"] for r in rows(src, kind) if r["id"] in want[kind] and r.get("name")}

    frames = list(rows(src, "ui_map"))

    def to_map(cmap, x, y):
        """World point (x north, y west) on continent map -> (ui_map, x%, y%), smallest frame holding it."""
        best = None
        for f in frames:
            if f["map"] != cmap:
                continue
            if not (f["right"] <= y <= f["left"] and f["bottom"] <= x <= f["top"]):
                continue
            area = (f["left"] - f["right"]) * (f["top"] - f["bottom"])
            if best is None or area < best[0]:
                best = (area, f)
        if not best:
            return None
        f = best[1]
        return f["ui_map"], (f["left"] - y) / (f["left"] - f["right"]) * 100, (f["top"] - x) / (f["top"] - f["bottom"]) * 100

    spawns = {"npc": collections.defaultdict(lambda: collections.defaultdict(list)),
              "object": collections.defaultdict(lambda: collections.defaultdict(list))}
    for r in rows(src, "spawn"):
        kind = r["kind"]
        if kind in spawns and r["id"] in want[kind]:
            m = to_map(r["map"], r["x"], r["y"])
            if m:
                pts = spawns[kind][r["id"]][m[0]]
                p = (round(m[1], 1), round(m[2], 1))
                if p not in pts and len(pts) < 60:
                    pts.append(p)

    out = [
        "local _, OXP = ...",
        "",
        "-- Quest facts for WoW Forever, generated by tools/build_questdb.py from forever-db",
        "-- (PoleStar repository commit %s, dataset %s, client %s)." % (commit[:12], index.get("version"), index.get("clientBuild")),
        "-- GPL-3.0; forever-db's sources are credited in NOTICE.md. Don't edit: rebuild.",
        "--",
        "-- q[id] = { title, level, minLevel, side (0 both, 1 Alliance, 2 Horde), races = {ids} or nil,",
        "--           classes = {ids} or nil, s = start, f = finish ({\"n\"|\"o\"|\"i\", id}, ...),",
        "--           o = objectives { {kind, target, count}, ... } in objective order,",
        "--           any = {ids}, all = {ids}, bc = quest this is a breadcrumb for }",
        "-- npc/obj[id] = { name, spawns = { [uiMap] = \"x,y;x,y\" } }; item[id] = { name, n = {npc drops}, o = {object drops} }",
        "OXP.questData = { q = {}, npc = {}, obj = {}, item = {} }",
        "local Q, N, O, I = OXP.questData.q, OXP.questData.npc, OXP.questData.obj, OXP.questData.item",
    ]
    K = {"npc": "n", "object": "o", "item": "i"}
    for qid in sorted(quests):
        q = quests[qid]
        parts = [lua_str(q.get("title", "")), str(q.get("level", 0)), str(q.get("min_level", 0)), str(q.get("side", 0))]
        extra = []
        races = bits(q.get("races") or 0)
        if races:
            extra.append("races = {%s}" % ",".join(map(str, races)))
        classes = bits(q.get("classes") or 0)
        if classes:
            extra.append("classes = {%s}" % ",".join(map(str, classes)))
        if start[qid]:
            extra.append("s = {%s}" % ",".join('{"%s",%d}' % (K[k], i) for k, i in start[qid]))
        if finish[qid]:
            extra.append("f = {%s}" % ",".join('{"%s",%d}' % (K[k], i) for k, i in finish[qid]))
        objs = sorted(objectives[qid], key=lambda o: o.get("n", 0))
        if objs:
            extra.append("o = {%s}" % ",".join('{"%s",%d,%d}' % (o["kind"], o.get("target") or 0, o.get("count") or 1) for o in objs))
        if pre_any[qid]:
            extra.append("any = {%s}" % ",".join(map(str, pre_any[qid])))
        if pre_all[qid]:
            extra.append("all = {%s}" % ",".join(map(str, pre_all[qid])))
        if qid in breadcrumb_for:
            extra.append("bc = %d" % breadcrumb_for[qid])
        out.append("Q[%d] = {%s}" % (qid, ",".join(parts + extra)))

    def spawn_str(sp):
        return "{%s}" % ",".join('[%d]="%s"' % (m, ";".join("%g,%g" % p for p in pts)) for m, pts in sorted(sp.items()))

    for nid in sorted(names["npc"]):
        sp = spawns["npc"].get(nid)
        out.append("N[%d] = {%s%s}" % (nid, lua_str(names["npc"][nid]), (", spawns = " + spawn_str(sp)) if sp else ""))
    for oid in sorted(names["object"]):
        sp = spawns["object"].get(oid)
        out.append("O[%d] = {%s%s}" % (oid, lua_str(names["object"][oid]), (", spawns = " + spawn_str(sp)) if sp else ""))
    for iid in sorted(names["item"]):
        d = drops.get(iid)
        extra = ""
        if d and d["npc"]:
            extra += ", n = {%s}" % ",".join(map(str, d["npc"]))
        if d and d["object"]:
            extra += ", o = {%s}" % ",".join(map(str, d["object"]))
        out.append("I[%d] = {%s%s}" % (iid, lua_str(names["item"][iid]), extra))
    # Lua keeps at most 2^18 constants per function: wrap the rows in
    # functions of 1000 rows each so the file loads however big it grows
    first = next(i for i, line in enumerate(out) if line.startswith("Q["))
    head, body = out[:first], out[first:]
    out = head
    for i in range(0, len(body), 1000):
        out.append(";(function()")
        out.extend(body[i:i + 1000])
        out.append("end)()")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("%d quests, %d NPCs, %d objects, %d items -> %s (%d KB)" % (
        len(quests), len(names["npc"]), len(names["object"]), len(names["item"]),
        os.path.relpath(OUT, ROOT), os.path.getsize(OUT) // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
