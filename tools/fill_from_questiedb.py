#!/usr/bin/env python3
"""Fill the gaps in OpenXP/Data/QuestDB.lua from QuestieDB's Forever data.

forever-db (tools/build_questdb.py) has no drop or loot source for many
quest items, above all Forever's own new quests (Spoils of War's timber and
iron piles, for one). Without a source OpenXP can't put the objective icons
on the map or draw the kill/loot area. QuestieDB (the database Questie reads,
GPL-3.0 with the Questie team's permission, see OpenXP/NOTICE.md) does know
most of them, so for every quest item in QuestDB.lua with no source this
takes QuestieDB's drop lists, and for each NPC or object they name that
QuestDB.lua doesn't hold, its name and spawn points.

    python3 tools/fill_from_questiedb.py <QuestieDB folder>

<QuestieDB folder> is an installed QuestieDB add-on built for Forever
(QuestieDB_Forever.toc, "baked mode": every row is CBOR in the TOC's ## X-
lines). Writes OpenXP/Data/QuestDB_Fill.lua, which adds to OXP.questData
after Data/QuestDB.lua loads. Only data is copied: no Questie code or art.
"""
import base64
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUESTDB = os.path.join(ROOT, "OpenXP", "Data", "QuestDB.lua")
OUT = os.path.join(ROOT, "OpenXP", "Data", "QuestDB_Fill.lua")

# QuestieDB's field numbers (src/meta/*Meta.lua)
ITEM_NPC_DROPS, ITEM_OBJECT_DROPS = 2, 3
NPC_NAME, NPC_SPAWNS = 1, 7
OBJECT_NAME, OBJECT_SPAWNS = 1, 4


def cbor(b, i=0):
    """A small CBOR reader: what QuestieDB's codec writes (ints, floats,
    strings, arrays, maps)."""
    ib = b[i]
    major, info = ib >> 5, ib & 31
    i += 1
    if major == 7:
        if info == 27:
            return struct.unpack(">d", b[i:i + 8])[0], i + 8
        if info == 26:
            return struct.unpack(">f", b[i:i + 4])[0], i + 4
        if info == 25:
            return struct.unpack(">e", b[i:i + 2])[0], i + 2
        if info == 20:
            return False, i
        if info == 21:
            return True, i
        if info in (22, 23):
            return None, i
        raise ValueError("cbor simple %d" % info)
    if info < 24:
        n = info
    elif info == 24:
        n = b[i]
        i += 1
    elif info == 25:
        n = struct.unpack(">H", b[i:i + 2])[0]
        i += 2
    elif info == 26:
        n = struct.unpack(">I", b[i:i + 4])[0]
        i += 4
    elif info == 27:
        n = struct.unpack(">Q", b[i:i + 8])[0]
        i += 8
    else:
        raise ValueError("cbor length %d" % info)
    if major == 0:
        return n, i
    if major == 1:
        return -1 - n, i
    if major == 2:  # QuestieDB writes its strings as byte strings
        try:
            return b[i:i + n].decode("utf-8"), i + n
        except UnicodeDecodeError:
            return b[i:i + n], i + n
    if major == 3:
        return b[i:i + n].decode("utf-8"), i + n
    if major == 4:
        out = []
        for _ in range(n):
            v, i = cbor(b, i)
            out.append(v)
        return out, i
    if major == 5:
        out = {}
        for _ in range(n):
            k, i = cbor(b, i)
            v, i = cbor(b, i)
            out[k] = v
        return out, i
    raise ValueError("cbor major %d" % major)


def decode(s):
    s = s.strip()
    return cbor(base64.b64decode(s + "=" * (-len(s) % 4)))[0]


def read_toc(folder):
    """{(entity, id): {field: value}}; "S" rows hold the small fields as a map.
    A long value is split: "~N~" on its own line, then N parts "-1".."-N"."""
    raw, parts = {}, {}
    line_re = re.compile(r"^## X-(Item|Npc|Object)-(\d+)-(\w+?)(?:-(\d+))?: (.*)$")
    with open(os.path.join(folder, "QuestieDB_Forever.toc"), encoding="utf-8") as f:
        for line in f:
            m = line_re.match(line.rstrip("\n"))
            if not m:
                continue
            key = (m.group(1), int(m.group(2)), m.group(3))
            if m.group(4):
                parts.setdefault(key, {})[int(m.group(4))] = m.group(5).strip()
            else:
                raw[key] = m.group(5).strip()
    rows = {}
    for key, data in raw.items():
        chunked = re.match(r"^~(\d+)~$", data)
        if chunked:
            got = parts.get(key, {})
            n = int(chunked.group(1))
            if any(k not in got for k in range(1, n + 1)):
                continue
            data = "".join(got[k] for k in range(1, n + 1))
        entity, ident, field = key
        row = rows.setdefault((entity, ident), {})
        value = decode(data)
        if field == "S":
            if isinstance(value, dict):
                row.update(value)
        else:
            row[int(field)] = value
    return rows


def area_maps(folder):
    """Questie area id -> uiMap, for areas that are a zone map themselves
    (coordinates are on that map; "A -> B" entries only pick a map to show)."""
    path = os.path.join(folder, "support", "Forever", "Zones", "areaIdToUiMapId.lua")
    text = open(path, encoding="utf-8").read()
    block = text.split("ZoneDB.private.areaIdToUiMapId =", 1)[1]
    out = {}
    for m in re.finditer(r"^\s*\[(\d+)\] = (\d+),\s*--\s*(.*)$", block, re.M):
        if "->" not in m.group(3):
            out[int(m.group(1))] = int(m.group(2))
    return out


def num(v):
    s = ("%.1f" % v).rstrip("0").rstrip(".")
    return s


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def spawns_lua(spawns, maps):
    parts = []
    if isinstance(spawns, list):  # a Lua table keyed 1..n (Dun Morogh is area 1) comes as an array
        spawns = {i + 1: v for i, v in enumerate(spawns)}
    for area, pts in sorted((spawns or {}).items()):
        ui = maps.get(area)
        if not ui or not isinstance(pts, list):
            continue
        seen, coords = set(), []
        for p in pts:
            if not (isinstance(p, list) and len(p) >= 2) or p[0] is None or p[0] < 0:
                continue
            c = num(p[0]) + "," + num(p[1])
            if c not in seen:
                seen.add(c)
                coords.append(c)
        if coords:
            parts.append("[%d]=%s" % (ui, lua_str(";".join(coords))))
    return "{" + ",".join(parts) + "}" if parts else None


def main(argv):
    if len(argv) != 1:
        print(__doc__)
        return 2
    folder = argv[0]
    src = open(QUESTDB, encoding="utf-8").read()
    have_npc = set(int(x) for x in re.findall(r"^N\[(\d+)\]", src, re.M))
    have_obj = set(int(x) for x in re.findall(r"^O\[(\d+)\]", src, re.M))
    empty = [int(m.group(1)) for m in re.finditer(r"^I\[(\d+)\] = \{\"(?:[^\"\\]|\\.)*\"\}$", src, re.M)]
    rows = read_toc(folder)
    maps = area_maps(folder)

    items, npcs, objs = [], {}, {}
    for ident in empty:
        row = rows.get(("Item", ident), {})
        n = sorted(set(x for x in row.get(ITEM_NPC_DROPS) or [] if isinstance(x, int)))
        o = sorted(set(x for x in row.get(ITEM_OBJECT_DROPS) or [] if isinstance(x, int)))
        if not (n or o):
            continue
        items.append((ident, n, o))
        for x in n:
            if x not in have_npc:
                npcs[x] = rows.get(("Npc", x), {})
        for x in o:
            if x not in have_obj:
                objs[x] = rows.get(("Object", x), {})

    lines = [
        "local _, OXP = ...",
        "",
        "-- Drop and loot sources for quest items that Data/QuestDB.lua has none for,",
        "-- and the NPCs and objects they name, from QuestieDB's Forever data",
        "-- (GPL-3.0 with the Questie team's permission, see NOTICE.md). Generated by",
        "-- tools/fill_from_questiedb.py: don't edit, rebuild.",
        "local D = OXP.questData",
        "if not D then return end",
        "local N, O, I = D.npc, D.obj, D.item",
        ";(function()",
    ]
    added_npc = added_obj = 0
    for x in sorted(npcs):
        row = npcs[x]
        name = row.get(NPC_NAME)
        sp = spawns_lua(row.get(NPC_SPAWNS), maps)
        if isinstance(name, str):
            lines.append("N[%d] = {%s%s}" % (x, lua_str(name), ", spawns = " + sp if sp else ""))
            added_npc += 1
    for x in sorted(objs):
        row = objs[x]
        name = row.get(OBJECT_NAME)
        sp = spawns_lua(row.get(OBJECT_SPAWNS), maps)
        if isinstance(name, str):
            lines.append("O[%d] = {%s%s}" % (x, lua_str(name), ", spawns = " + sp if sp else ""))
            added_obj += 1
    for ident, n, o in items:
        parts = []
        if n:
            parts.append("n = {%s}" % ",".join(map(str, n)))
        if o:
            parts.append("o = {%s}" % ",".join(map(str, o)))
        lines.append("if I[%d] then I[%d].n, I[%d].o = %s, %s end" % (
            ident, ident, ident,
            "{%s}" % ",".join(map(str, n)) if n else "nil",
            "{%s}" % ",".join(map(str, o)) if o else "nil"))
    lines += ["end)()", ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("items without a source: %d, filled: %d; NPCs added: %d, objects added: %d -> %s" % (
        len(empty), len(items), added_npc, added_obj, os.path.relpath(OUT, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
