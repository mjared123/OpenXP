#!/usr/bin/env python3
"""Turn arrow paths saved in game into entries for DB/pathHints.lua.

OpenXP saves two kinds of paths in WTF/Account/<ACCOUNT>/SavedVariables/OpenXP.lua
(OXPData.openxpPaths):
  learned   cave and indoor entrances it noticed as you walked in and out
  recorded  stepping stones you saved with /oxp path add

    python3 tools/export_paths.py <path to OpenXP.lua> [--min-seen N]

prints Lua to paste into addon.pathHintData (areas) and its passes list.
--min-seen skips learned entrances walked through fewer than N times
(default 1). Check each one in game before shipping it.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import savedvars  # noqa: E402


def seq(t):
    """Positional entries of a parsed Lua table, in order."""
    if isinstance(t, list):
        return t
    if not isinstance(t, dict):
        return []
    out, i = [], 1
    while i in t:
        out.append(t[i])
        i += 1
    return out


def num(v):
    return "%.2f" % v


def point(p):
    vals = seq(p)
    s = "{%s, %s" % (num(vals[0]), num(vals[1]))
    if len(vals) > 2 and isinstance(vals[2], (int, float)):
        s += ", %d" % vals[2]
    return s + "}"


def zone_note(z):
    z = seq(z)
    return "map %s at %.1f, %.1f" % (z[0], z[1], z[2]) if len(z) >= 3 else ""


def lua_str(s):
    return '"%s"' % str(s).replace("\\", "\\\\").replace('"', '\\"')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("savedvars")
    ap.add_argument("--min-seen", type=int, default=1)
    args = ap.parse_args()

    data = savedvars.load(args.savedvars, only="OXPData").get("OXPData") or {}
    paths = data.get("openxpPaths") or {}
    areas = seq(paths.get("areas"))
    passes = seq(paths.get("passes"))
    if not areas and not passes:
        sys.exit("No saved arrow paths in that file yet.")

    print("    -- from %s areas saved in game" % len(areas))
    for a in areas:
        entrances = []
        for e in seq(a.get("entrances")):
            if a.get("source") == "learned" and (e.get("seen") or 1) < args.min_seen:
                continue
            pts = ", ".join(point(p) for p in seq(e))
            extra = ", oneWay = true" if e.get("oneWay") else ""
            note = ""
            first = seq(e)[0] if seq(e) else None
            if isinstance(first, dict) and first.get("zone"):
                note = "  -- " + zone_note(first["zone"])
            entrances.append("{%s%s},%s" % (pts, extra, note))
        if not entrances:
            continue
        circles = ", ".join("{%s, %s, %d}" % (num(seq(c)[0]), num(seq(c)[1]), round(seq(c)[2]))
                            for c in seq(a.get("circles")))
        print("    {")
        print("        -- %s%s" % (a.get("source", "?"),
                                   (", " + zone_note(a["zonePos"])) if a.get("zonePos") else ""))
        print("        name = %s, inst = %s,%s" % (lua_str(a.get("name") or "?"), a.get("inst"),
                                                  " indoor = true," if a.get("indoor") else ""))
        print("        circles = {%s}," % circles)
        print("        entrances = {")
        for e in entrances:
            print("            " + e)
        print("        },")
        print("    },")

    if passes:
        print("\n    -- passes (put these inside passes = {...})")
        for p in passes:
            pts = ", ".join(point(x) for x in seq(p.get("pts")))
            print("        {name = %s, inst = %s, from = %s, to = %s, pts = {%s}}," % (
                lua_str(p.get("name") or "the pass"), p.get("inst"), p.get("from"), p.get("to"), pts))


if __name__ == "__main__":
    main()
