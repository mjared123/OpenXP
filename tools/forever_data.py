#!/usr/bin/env python3
"""Load QuestieDB's Forever data with its Forever corrections applied.

QuestieDB's data/Forever files are the raw base. WoW Forever's new quests,
NPCs and objects (Riverglades, the new dungeons, the new quests in the old
zones) live in src/corrections/Forever as correction tables. This reads those
tables as data (only the returned tables are evaluated, against key and enum
stand-ins) and applies them in Questie's order: generated base, traces,
then the authored Forever fixes. `_add`/`_remove` fields merge into lists.

Build-time only: nothing from here is shipped in the addon.

    db = forever_data.load(questiedb)   # same {"q","n","o","i"} rows as build_route.load_db
"""
import os
import pickle
import re

from lupa import luajit21 as lupa

import build_route as br

FILES = [  # (entity, path) in the order Questie applies them
    ("q", "generated/foreverBaseQuest.lua"), ("n", "generated/foreverBaseNpc.lua"),
    ("o", "generated/foreverBaseObject.lua"), ("i", "generated/foreverBaseItem.lua"),
    ("q", "traces/foreverQuestTraces.lua"), ("n", "traces/foreverNpcTraces.lua"),
    ("o", "traces/foreverObjectTraces.lua"), ("i", "traces/foreverItemTraces.lua"),
    ("q", "foreverQuestFixes.lua"), ("n", "foreverNPCFixes.lua"),
    ("o", "foreverObjectFixes.lua"), ("i", "foreverItemFixes.lua"),
]
META = {"q": "questMeta.lua", "n": "npcMeta.lua", "o": "objectMeta.lua", "i": "itemMeta.lua"}


def _keys(questiedb, kind):
    text = open(os.path.join(questiedb, "src", "meta", META[kind]), encoding="utf-8").read()
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"\['(\w+)'\] = (\d+),", text)}


def _return_table(text, start):
    """The `{ ... }` after the first `return` at or after start, by brace count."""
    i = text.index("return {", start) + len("return ")
    depth, j, n = 0, i, len(text)
    while j < n:
        c = text[j]
        if c == "-" and text.startswith("--", j):
            if text.startswith("--[[", j):
                j = text.index("]]", j) + 2
            else:
                j = text.find("\n", j)
                j = n if j < 0 else j
            continue
        if c in "\"'":
            k = j + 1
            while text[k] != c:
                k += 2 if text[k] == "\\" else 1
            j = k + 1
            continue
        if c == "[" and text.startswith("[[", j):
            j = text.index("]]", j) + 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
        j += 1
    raise ValueError("unbalanced table")


ENV = r"""
local enumsrc = ...
local Enum = {}
local function keynames() return setmetatable({}, {__index = function(_, k) return k end}) end
local unknown = {}
local function lenient(name)
  return setmetatable({}, {__index = function(_, k) unknown[name .. "." .. k] = true; return 0 end})
end
local function withfallback(t, name)
  return setmetatable(t or {}, {__index = function(_, k) unknown[name .. "." .. k] = true; return 0 end})
end
return function(enums)
  local F = enums.byExpansion and enums.byExpansion.Forever or {}
  return {
    questKeys = keynames(), npcKeys = keynames(), objectKeys = keynames(), itemKeys = keynames(),
    zoneIDs = withfallback(enums.zoneIDs, "zoneIDs"),
    raceIDs = withfallback(F.raceKeys, "raceIDs"),
    classIDs = withfallback(F.classKeys or (enums.byExpansion.Classic or {}).classKeys, "classIDs"),
    sortKeys = withfallback(enums.sortKeys, "sortKeys"),
    specialFlags = withfallback(enums.specialFlags, "specialFlags"),
    factionIDs = withfallback(enums.factionIDs, "factionIDs"),
    npcFlags = withfallback(F.npcFlags, "npcFlags"),
    profKeys = lenient("profKeys"), specKeys = lenient("specKeys"), rankKeys = lenient("rankKeys"),
    waypointPresets = lenient("waypointPresets"), phases = lenient("phases"),
    Questie = setmetatable({}, {__index = function(_, k) return k end}),
    l10n = function(s) return s end,
    UnitClassBase = function() return nil end,
    lenient = lenient,
  }, unknown
end
"""


def _enums(rt, questiedb):
    lib = rt.eval("{Enum = {}}")
    d = os.path.join(questiedb, "src", "corrections", "enum")
    for f in sorted(os.listdir(d)):
        if f.endswith(".lua") and not f.endswith(".test.lua"):
            fn = rt.eval("function(s, name) return assert(loadstring(s, name)) end")(
                open(os.path.join(d, f), encoding="utf-8").read(), "@" + f)
            try:
                fn(None, lib)
            except Exception as e:  # an enum file we don't need
                print("  (skipped enum %s: %s)" % (f, str(e).splitlines()[0]))
    return lib.Enum


def _py(v):
    if lupa.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) and k > 0 for k in keys) and max(keys) <= 10:
            return [_py(v[k]) if k in v else None for k in range(1, max(keys) + 1)]
        return {k: _py(v[k]) for k in keys}
    return v


def _merge_list(old, new, add):
    """Questie's _add/_remove: positional groups ({npcs, objects, items})
    or a flat id list."""
    old = br.as_list(old) if old is not None else []
    new = br.as_list(new) if new is not None else []
    grouped = any(isinstance(x, list) or x is None for x in new) or any(isinstance(x, list) for x in old)
    if not grouped:
        if add:
            return old + [x for x in new if x not in old]
        return [x for x in old if x not in new]
    out = [list(br.as_list(g)) if g is not None else None for g in old]
    for i, g in enumerate(new):
        if g is None:
            continue
        while len(out) <= i:
            out.append(None)
        cur = out[i] or []
        g = br.as_list(g)
        out[i] = cur + [x for x in g if x not in cur] if add else [x for x in cur if x not in g]
    return out


def apply(db, kind, table, keys, report):
    rows = db[kind]
    for eid, fields in table.items():
        if not isinstance(eid, int) or not isinstance(fields, dict):
            continue
        row = list(rows.get(eid) or [])
        new = eid not in rows
        for name, val in fields.items():
            base, op = name, None
            for suf in ("_add", "_remove"):
                if isinstance(name, str) and name.endswith(suf):
                    base, op = name[: -len(suf)], suf
            idx = keys.get(base)
            if not idx:
                report.add("unknown field %s" % name)
                continue
            while len(row) < idx:
                row.append(None)
            if op:
                row[idx - 1] = _merge_list(row[idx - 1], val, op == "_add")
            else:
                row[idx - 1] = val
        rows[eid] = row
        if new:
            report.add("new")


def load(questiedb, base=None, quiet=False):
    cache = os.path.join(questiedb, ".openxp-forever-corrected.pkl")
    if base is None and os.path.exists(cache):
        return pickle.load(open(cache, "rb"))
    db = base or br.load_db(questiedb, "Forever")
    db = {k: dict(v) for k, v in db.items()}
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    enums = _enums(rt, questiedb)
    make_env = rt.execute(ENV, None)
    env, unknown = make_env(enums)
    names = [k for k in env.keys() if k != "lenient"]
    evalr = rt.eval("""function(src, names, env)
        local args = {}
        for i, n in ipairs(names) do args[i] = env[n] end
        local f = assert(loadstring("local " .. table.concat(names, ",") .. " = ... return " .. src))
        setfenv(f, setmetatable({}, {__index = function(_, k) return env.lenient(k) end}))
        return f(unpack(args))
    end""")
    lnames = rt.table_from(names)
    root = os.path.join(questiedb, "src", "corrections", "Forever")
    for kind, rel in FILES:
        text = open(os.path.join(root, rel), encoding="utf-8").read()
        keys = _keys(questiedb, kind)
        start = text.index(":Load()")
        tables = [_return_table(text, start)]
        dyn = text.find(":LoadDynamic()")
        if dyn >= 0:  # faction-split dynamic fixes: both halves are plain tables
            for m in re.finditer(r"local questFixes(Horde|Alliance) = \{", text[dyn:]):
                tables.append(_return_table("return " + text[dyn + m.end() - 1:], 0))
        report = set()
        n = 0
        for src in tables:
            t = _py(evalr(src, lnames, env))
            apply(db, kind, t, keys, report)
            n += len(t)
        if not quiet:
            print("  %-36s %5d rows%s" % (rel, n, " (+new)" if "new" in report else ""))
        for r in sorted(report - {"new"}):
            print("    ", r)
    if not quiet and len(list(unknown.keys())):
        print("  unknown enum names (read as 0):", ", ".join(sorted(unknown.keys()))[:400])
    _reverse_links(db)
    if base is None:
        pickle.dump(db, open(cache, "wb"))
    return db


def _reverse_links(db):
    """Fill quest starters/finishers from the NPC and object questStarts/
    questEnds lists where the quest row has none (the corrections often add
    only one side)."""
    for kind, si, ei, grp in (("n", 10, 11, 0), ("o", 2, 3, 1)):
        for eid, row in db[kind].items():
            for idx, qfield in ((si, 2), (ei, 3)):
                for qid in br.as_list(br.li(row, idx)):
                    q = db["q"].get(qid)
                    if not q:
                        continue
                    q = list(q)
                    while len(q) < qfield:
                        q.append(None)
                    cur = q[qfield - 1]
                    groups = [list(br.as_list(g)) if g is not None else None for g in br.as_list(cur)] if cur else []
                    while len(groups) <= grp:
                        groups.append(None)
                    have = groups[grp] or []
                    if eid not in have and not any(groups):
                        groups[grp] = have + [eid]
                        q[qfield - 1] = groups
                        db["q"][qid] = q


if __name__ == "__main__":
    import sys
    d = load(sys.argv[1])
    print({k: len(v) for k, v in d.items()})
