#!/usr/bin/env python3
"""Generate OpenXP dungeon quest guides from Questie's quest data.

One guide per dungeon: pick up every quest for that dungeon (with the arrow
to each quest giver), run the dungeon with the quest objectives listed, then
turn everything in. Quest objectives are ticked off by the engine.

Usage:
    python3 tools/build_dungeons.py --questiedb PATH --game Forever|Classic --faction Alliance|Horde
    python3 tools/build_dungeons.py --questiedb PATH --faction Alliance|Horde --new

--new builds the dungeons that are new in WoW Forever (FOREVER_DUNGEONS) into
Guides/openxp/Dungeons-Forever-<faction>.lua and leaves the classic dungeon
guides alone.
"""
import argparse, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_route as br

ROOT = br.ROOT

# name, dungeon area id(s), level range
DUNGEONS = [
    ("Ragefire Chasm", (2437,), (13, 18), "Horde"),
    ("Wailing Caverns", (718,), (17, 24), None),
    ("The Deadmines", (1581,), (17, 26), "Alliance"),
    ("Shadowfang Keep", (209,), (22, 30), None),
    ("Blackfathom Deeps", (719,), (22, 32), None),
    ("The Stockade", (717,), (22, 30), "Alliance"),
    ("Gnomeregan", (721, 133), (29, 38), None),
    ("Razorfen Kraul", (491,), (29, 38), None),
    ("Scarlet Monastery", (796,), (30, 45), None),
    ("Razorfen Downs", (722,), (35, 44), None),
    ("Uldaman", (1337,), (37, 50), None),
    ("Zul'Farrak", (1176, 978), (42, 52), None),
    ("Maraudon", (2100,), (44, 54), None),
    ("Sunken Temple", (1477, 1417), (47, 58), None),
    ("Blackrock Depths", (1584,), (51, 60), None),
    ("Lower Blackrock Spire", (1583,), (54, 60), None),
    ("Dire Maul", (2557,), (55, 60), None),
    ("Stratholme", (2017,), (56, 60), None),
    ("Scholomance", (2057,), (56, 60), None),
]

# Dungeons added in WoW Forever. name, dungeon area id(s), level range, faction,
# words that mark a quest for the dungeon in its objective text (Questie often
# has no zone for these quests yet).
FOREVER_DUNGEONS = [
    ("Hall of Thanes", (16919,), (13, 18), None, ("Hall of Thanes",)),
    ("Ruins of Lordaeron", (16611, 16612, 16614, 16615, 16617), (15, 20), None, ("Ruins of Lordaeron",)),
    ("Excavation Site: Wetlands", (16732, 16876, 16877), (24, 29), None, ("Excavation Site",)),
    ("City of Dalaran", (16544, 16558, 16559, 16560), (28, 33), None, ("City of Dalaran",)),
    ("The Drowned City", (), (35, 40), None, ("Drowned City",)),
    ("Krol'dok Stronghold", (17780,), (40, 45), None, ("Krol'dok",)),
    ("Alcaz Prison", (), (48, 53), None, ("Alcaz Prison",)),
    ("Blackmaw Hold", (), (55, 60), None, ("Blackmaw Hold",)),
    ("The Shaper's Terrace", (16985,), (58, 60), None, ("Shaper's Terrace",)),
]

# Quest ids from here up were added in WoW Forever. Only these are matched by
# the objective-text words, so old quests that name a place (Ormer's Revenge
# at Whelgar's Excavation Site) stay out.
NEW_QUEST_IDS = 90000

# Quest givers to visit first, because their quest unlocks the others
# (Modera only offers her quests after An Alarming Request).
FIRST = {92432}

# Breadcrumbs from far away that the dungeon guide leaves out.
SKIP = {
    95737,  # Seeking Caitlin, from Llana in Ashenvale; Caitlin offers her quest without it
    97289, 97290, 97291, 97292,  # Unending Torment follow-ups, done in the Undercity
}

# Quests given or started inside the dungeon, which Questie has no quest giver
# position for. (quest id, faction or None, text shown on the step)
INSIDE = {
    "Hall of Thanes": [
        (96395, None, "Talk to the |cRXP_FRIENDLY_Ghostly Attendant|r in the west room after the first pull"),
        (98423, "Alliance", "Click the |cRXP_PICK_Treaty of Understanding|r tablet behind the vault door in the last room, on the way to the lever out"),
    ],
}


def area_map(qdb):
    m = {}
    # Forever's own table first (it has Riverglades, Zephras Isle and the
    # new dungeons), then the shared one for the rest
    for path in (os.path.join(qdb, "support", "Forever", "Zones", "areaIdToUiMapId.lua"),
                 os.path.join(qdb, "support", "Zones", "areaIdToUiMapId.lua")):
        if os.path.exists(path):
            for a, u in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", open(path).read()):
                m.setdefault(int(a), int(u))
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questiedb", required=True)
    ap.add_argument("--game", default="Forever")
    ap.add_argument("--faction", default="Alliance")
    ap.add_argument("--new", action="store_true", help="only the dungeons new in WoW Forever")
    ap.add_argument("--dump", help="also read /oxp questdump from this OpenXP.lua")
    a = ap.parse_args()
    br.GAME, br.FACTION = a.game, a.faction
    db = br.load_db(a.questiedb)
    if a.game == "Forever":
        # Forever's own quests are corrections on top of the base data
        import forever_data
        if a.dump:
            db = br.merge_db(db, br.load_dump_cached(a.dump, a.questiedb))
        db = forever_data.load(a.questiedb, base=db, quiet=True)
    amap = area_map(a.questiedb)
    builder = br.Builder(db, set(), set())
    dungeon_list = [d + ((),) for d in DUNGEONS]
    if a.new:
        dungeon_list = FOREVER_DUNGEONS
    dungeon_areas = {x for d in DUNGEONS + FOREVER_DUNGEONS for x in d[1]}

    def where(entity, idx):
        sp = br.li(entity, idx)
        if isinstance(sp, list):
            # {[1] = {...}} (Dun Morogh is zone 1) comes out of Lua as a list
            sp = {i + 1: v for i, v in enumerate(sp) if v}
        if not isinstance(sp, dict):
            return None
        best = None
        home = br.li(entity, 9 if idx == 7 else 5)  # the entity's own zone wins
        for area, pts in sp.items():
            pts = [tuple(p) for p in br.as_list(pts) if p and len(p) == 2 and p[0] >= 0]
            if pts and area not in dungeon_areas and amap.get(area):
                if area == home:
                    best = (area, pts)
                    break
                if not best or len(pts) > len(best[1]):
                    best = (area, pts)
        if not best:
            return None
        return amap[best[0]], best[1][0]

    def giver(ref):
        for nid in br.as_list(br.li(ref, 1)):
            n = db["n"].get(nid)
            if n and builder.friendly(nid):
                w = where(n, 7)
                if w:
                    return br.li(n, 1), w
        for oid in br.as_list(br.li(ref, 2)):
            o = db["o"].get(oid)
            w = where(o, 4) if o else None
            if w:
                return br.li(o, 1), w
        return None

    def only_in(sp, areas):
        """True when every spawn of the entity is inside the dungeon."""
        return isinstance(sp, dict) and sp and all(k in areas for k in sp)

    def text_of(qid):
        return " ".join(x for x in br.as_list(br.li(db["q"].get(qid), 8)) if isinstance(x, str))

    def item_start(ref):
        """Quests started by looting an item: (item name, item id)."""
        for iid in br.as_list(br.li(ref, 3)):
            it = db["i"].get(iid)
            if it and br.li(it, 1):
                return br.li(it, 1), iid
        return None

    def in_dungeon(q, areas, words=()):
        if q.zone in areas:
            return True
        if words and q.id >= NEW_QUEST_IDS and any(w in text_of(q.id) for w in words):
            return True
        obj = q.objectives or {}
        found = False
        for e in br.as_list(br.li(obj, 1)):
            n = db["n"].get(e[0])
            if not (n and only_in(br.li(n, 7), areas)):
                return False
            found = True
        for e in br.as_list(br.li(obj, 3)):
            it = db["i"].get(e[0])
            drops = [db["n"].get(nid) for nid in br.as_list(br.li(it, 2))] if it else []
            drops = [n for n in drops if n]
            if not drops or not all(only_in(br.li(n, 7), areas) for n in drops):
                return False
            found = True
        return found

    tag = "#forever" if a.game == "Forever" else "#classic"
    out = ["-- OpenXP dungeon quests (%s, %s). Generated by tools/build_dungeons.py" % (a.faction, a.game),
           "-- from Questie's quest data; meant to be played and hand-tuned.",
           'local faction = UnitFactionGroup("player")',
           'if faction ~= "%s" then return end' % a.faction,
           "local L = GetLocale() if L and RXP.enabledLocale[L] then return end", ""]
    report = []
    for name, areas, (lo, hi), only, words in dungeon_list:
        if only and only != a.faction:
            continue
        quests, looted = [], []
        inside = [(qid, txt) for qid, fac, txt in INSIDE.get(name, ()) if fac in (None, a.faction)]
        inside_ids = {qid for qid, _ in inside}
        for qid, row in db["q"].items():
            q = br.Quest(qid, row)
            if not q.name or not q.for_faction() or q.name.startswith("[") or "<" in q.name:
                continue
            if q.classes and (q.classes & br.ALL_CLASSES) != br.ALL_CLASSES:
                continue  # class quests
            if q.reqSkill or q.reqRep or q.specialFlags & 1:
                continue
            if not (lo - 2 <= q.level <= hi + 2):
                continue
            if q.id in SKIP or not in_dungeon(q, areas, words):
                continue
            st, fi = giver(q.startedBy), giver(q.finishedBy)
            if q.id in inside_ids:
                quests.append((q, None, fi))
                continue
            if not st and fi and item_start(q.startedBy):
                looted.append((q, item_start(q.startedBy), fi))
                continue
            if not st:
                continue
            quests.append((q, st, fi))  # fi None: turned in inside, or not known yet
        # follow-ups of a quest in this guide are done after the run, in town
        ids = {q.id for q, _, _ in quests + looted}
        quests = [t for t in quests if not (set(t[0].preSingle) | set(t[0].preGroup)) & ids]
        # inside quests the data has no faction or level for yet
        for qid, _ in inside:
            if qid not in {q.id for q, _, _ in quests} and qid in db["q"]:
                q = br.Quest(qid, db["q"][qid])
                quests.append((q, None, giver(q.finishedBy)))
        if not quests and not looted:
            continue
        quests.sort(key=lambda t: (t[1] is None, t[0].id not in FIRST, t[1] and (t[1][1][0], t[1][1][1][0], t[1][1][1][1])))
        lines = ["RXPGuides.RegisterGuide([[", tag, "#version 1", "<< " + a.faction,
                 "#group OpenXP Dungeons", "#subgroup %d-%d" % (lo, hi),
                 "#name %d-%d %s" % (lo, hi, name), ""]
        def npc_step(who, w, verb, items):
            m, (x, y) = w
            lines.extend(["step", "    .goto %d,%.2f,%.2f" % (m, x, y),
                          "    >>Talk to |cRXP_FRIENDLY_%s|r" % who])
            for q in items:
                lines.append("    .%s %d >> %s %s" % (verb, q.id, "Accept" if verb == "accept" else "Turn in", q.name))
            lines.append("    .target %s" % who)
        # pickups, grouped by quest giver
        by = {}
        for q, st, fi in quests:
            if st:
                by.setdefault((st[0], st[1][0], st[1][1]), []).append(q)
        for (who, m, pt), qs in by.items():
            npc_step(who, (m, pt), "accept", qs)
        for qid, txt in inside:
            lines.extend(["step", "    >>Inside |cRXP_WARN_%s|r: %s" % (name, txt),
                          "    .accept %d >> Accept %s" % (qid, br.li(db["q"].get(qid), 1) or "quest %d" % qid)])
        for q, (iname, iid), _ in looted:
            lines.extend(["step",
                          "    >>Inside |cRXP_WARN_%s|r: loot |cRXP_LOOT_%s|r and use it to start the quest" % (name, iname),
                          "    .accept %d >> Accept %s" % (q.id, q.name)])
        lines.extend(["step", "    >>Run |cRXP_WARN_%s|r and finish these quests. Skip any you didn't pick up" % name])
        for q, _, _ in quests + looted:
            n = len(br.as_list(br.li(q.objectives or {}, 1))) + len(br.as_list(br.li(q.objectives or {}, 2))) + \
                len(br.as_list(br.li(q.objectives or {}, 3))) + len(br.as_list(br.li(q.objectives or {}, 5)))
            for i in range(1, max(n, 0) + 1):
                lines.append("    .complete -%d,%d" % (q.id, i))
        by = {}
        for q, st, fi in quests + looted:
            if fi:
                by.setdefault((fi[0], fi[1][0], fi[1][1]), []).append(q)
        for (who, m, pt), qs in by.items():
            lines.extend(["step", "    .goto %d,%.2f,%.2f" % (m, pt[0], pt[1]),
                          "    >>Talk to |cRXP_FRIENDLY_%s|r" % who])
            for q in qs:
                lines.append("    .turnin -%d >> Turn in %s" % (q.id, q.name))
            lines.append("    .target %s" % who)
        lines.append("]])")
        out.extend(lines + [""])
        report.append("%-26s %2d quests" % (name, len(quests) + len(looted)))
    d = "openxp" if a.game == "Forever" else "openxp-classic"
    path = os.path.join(ROOT, "Guides", d, "Dungeons-%s%s.lua" % ("Forever-" if a.new else "", a.faction))
    open(path, "w").write("\n".join(out))
    print("\n".join(report))
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
