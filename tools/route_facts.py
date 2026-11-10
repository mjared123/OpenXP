#!/usr/bin/env python3
"""Extra quest facts for the route planner, from an open Classic world database.

Questie knows where quest givers, mobs and objects are, but not how many of
each a quest wants, how often an item drops or how fast mobs respawn. Those
numbers decide which of two camps is faster, so the planner reads them from
VMaNGOS's world database (github.com/brotalnia/database, a 1.12 dump).

Only plain numbers are taken (counts, drop chances, respawn seconds, quest XP),
and only at build time: nothing from the database ships with OpenXP.

WoW Forever is Classic+: its own new quests aren't in a 1.12 database, so the
planner falls back to its old estimates for them. Blizzard said Forever keeps
Classic's quest drop rates and adds bad luck protection when grouped.

Usage:
    python3 tools/route_facts.py world_full_14_june_2021.sql facts.pkl
    python3 tools/build_route.py --facts facts.pkl ...
"""
import pickle
import re
import sys

PATCH = 10  # 1.12


def _rows(path, table):
    """Yield every row of `table` as a dict, from a mysqldump file."""
    head = re.compile(r"INSERT INTO `%s` \(([^)]*)\) VALUES" % re.escape(table))
    cols = None
    buf = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if buf is None:
                m = head.match(line)
                if not m:
                    continue
                cols = [c.strip(" `") for c in m.group(1).split(",")]
                buf = [line[m.end():]]
                if line.rstrip().endswith(";"):
                    yield from _parse(cols, "".join(buf))
                    buf = None
                continue
            buf.append(line)
            if line.rstrip().endswith(";"):
                yield from _parse(cols, "".join(buf))
                buf = None


def _parse(cols, text):
    i, n = 0, len(text)
    while i < n:
        if text[i] != "(":
            i += 1
            continue
        i += 1
        vals, cur, in_str = [], [], False
        while i < n:
            ch = text[i]
            if in_str:
                if ch == "\\":
                    cur.append(text[i + 1])
                    i += 2
                    continue
                if ch == "'":
                    in_str = False
                else:
                    cur.append(ch)
            elif ch == "'":
                in_str = True
                cur.append("\0")  # mark as string
            elif ch == ",":
                vals.append(_val(cur))
                cur = []
            elif ch == ")":
                vals.append(_val(cur))
                i += 1
                break
            else:
                cur.append(ch)
            i += 1
        yield dict(zip(cols, vals))


def _val(chars):
    s = "".join(chars)
    if s.startswith("\0"):
        return s[1:]
    s = s.strip()
    if s == "NULL":
        return None
    try:
        return int(s)
    except ValueError:
        try:
            return float(s)
        except ValueError:
            return s


def _latest(rows, key="entry"):
    """Keep each entry's row for the newest patch up to 1.12."""
    out = {}
    for r in rows:
        p = r.get("patch", r.get("patch_min", 0)) or 0
        if p > PATCH:
            continue
        k = r[key]
        if k not in out or p >= (out[k].get("patch", out[k].get("patch_min", 0)) or 0):
            out[k] = r
    return out


def extract(sql):
    facts = {"quest": {}, "drop": {}, "obj_drop": {}, "respawn": {}, "obj_respawn": {}}

    quests = _latest(_rows(sql, "quest_template"))
    for qid, r in quests.items():
        items = {r["ReqItemId%d" % k]: r["ReqItemCount%d" % k] for k in range(1, 5) if r["ReqItemId%d" % k]}
        mobs = {abs(r["ReqCreatureOrGOId%d" % k]): r["ReqCreatureOrGOCount%d" % k]
                for k in range(1, 5) if r["ReqCreatureOrGOId%d" % k]}
        facts["quest"][qid] = dict(items=items, mobs=mobs, xp=r.get("RewXP") or 0,
                                   level=r["QuestLevel"])

    wanted = set()
    for q in facts["quest"].values():
        wanted |= set(q["items"])

    templates = _latest(_rows(sql, "creature_template"))
    loot_of = {}
    for cid, r in templates.items():
        if r.get("loot_id"):
            loot_of.setdefault(r["loot_id"], []).append(cid)

    def loot(table, owners, dest):
        for r in _rows(sql, table):
            if r["item"] not in wanted or (r.get("patch_min") or 0) > PATCH:
                continue
            if (r.get("mincountOrRef") or 0) < 0:
                continue  # reference to a shared table: never quest items
            chance = abs(r["ChanceOrQuestChance"] or 0) / 100.0
            per = max(1, r.get("mincountOrRef") or 1), max(1, r.get("maxcount") or 1)
            for owner in owners(r["entry"]):
                cur = dest.setdefault(r["item"], {}).get(owner)
                if cur is None or chance > cur[0]:
                    dest[r["item"]][owner] = (chance, (per[0] + per[1]) / 2.0)

    loot("creature_loot_template", lambda e: loot_of.get(e, ()), facts["drop"])
    gobj = _latest(_rows(sql, "gameobject_template"))
    gloot = {}
    for oid, r in gobj.items():
        lid = r.get("data1") if r.get("type") in (3,) else None  # chest: data1 is its loot id
        if lid:
            gloot.setdefault(lid, []).append(oid)
    loot("gameobject_loot_template", lambda e: gloot.get(e, ()), facts["obj_drop"])

    def respawns(table, dest):
        acc = {}
        for r in _rows(sql, table):
            if (r.get("patch_min") or 0) > PATCH:
                continue
            t = ((r.get("spawntimesecsmin") or 0) + (r.get("spawntimesecsmax") or 0)) / 2.0
            if t <= 0:
                continue
            for k in ("id", "id2", "id3", "id4"):
                if r.get(k):
                    acc.setdefault(r[k], []).append(t)
        for k, ts in acc.items():
            dest[k] = sorted(ts)[len(ts) // 2]  # median

    respawns("creature", facts["respawn"])
    respawns("gameobject", facts["obj_respawn"])
    return facts


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    facts = extract(sys.argv[1])
    pickle.dump(facts, open(sys.argv[2], "wb"))
    print("quests %d, quest items with drops %d (+%d from objects), mobs with respawn %d" % (
        len(facts["quest"]), len(facts["drop"]), len(facts["obj_drop"]), len(facts["respawn"])))


if __name__ == "__main__":
    main()
