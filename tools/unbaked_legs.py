"""List guide legs (one goto spot to the next) that OpenXP_Nav has no baked walk for.

    python3 tools/unbaked_legs.py [old rev]

Plays each 1-60 guide chain as every race and class of its faction (steps and
goals filtered like the game does), takes consecutive goto spots as legs keyed
like OpenXP_Nav ("map:x,y>map:x,y", two decimals) and prints the legs missing
from OpenXP_Nav/Paths-<Faction>.lua. With an old rev, legs that rev's guides
already had are left out, so only the legs a change added are listed.
"""
import os, re, subprocess, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RACES = {"Alliance": ["Human", "Dwarf", "NightElf", "Gnome", "Skyborne"],
         "Horde": ["Orc", "Scourge", "Tauren", "Troll", "Skyborne"]}
CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]


def load(src, faction):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("UnitFactionGroup = function() return 'Neutral' end")
    filters = lua.execute(open(os.path.join(ROOT, "OpenXP/Engine/Filters.lua")).read().replace(
        "local _, OXP = ...", "local OXP = {}") + "\nreturn OXP.Filters")
    got = []
    oxp = lua.table_from({})
    oxp.AddGuides = lambda t: got.append(t)
    lua.execute("return function(src, oxp) return load(src)(nil, oxp) end")(src, oxp)
    return lua, filters, got[0]


def legs_for(src, faction):
    lua, filters, data = load(src, faction)
    guides = {}
    for i in range(1, len(data) + 1):
        g = data[i]
        guides[g.name] = g
    out = {}  # key -> (guide, from text, to text)
    for race in RACES[faction]:
        for cls in CLASSES:
            player = lua.table_from({"faction": faction, "race": race, "class": cls, "level": 60})
            ok = lambda only: filters.Matches(only, player)
            prev = None
            for name, g in guides.items():
                if not ok(g.only):
                    continue
                for si in range(1, len(g.steps) + 1):
                    step = g.steps[si]
                    if not ok(step.only):
                        continue
                    title = None
                    for gi in range(1, len(step) + 1):
                        goal = step[gi]
                        if not ok(goal.only):
                            continue
                        if goal[1] == "text" and title is None:
                            title = goal.text
                        if goal[1] == "goto" and goal.zone:
                            spot = "%d:%.2f,%.2f" % (int(goal.zone), goal.x, goal.y)
                            if prev and prev[0] != spot:
                                key = prev[0] + ">" + spot
                                out.setdefault(key, (name, prev[1], "%s (step %d: %s)" % (name, si, title)))
                            prev = (spot, "%s (step %d: %s)" % (name, si, title))
    return out


def baked(faction):
    text = open(os.path.join(ROOT, "OpenXP_Nav/Paths-%s.lua" % faction)).read()
    return set(re.findall(r'^P\["([^"]+)"\]', text, re.M))


def main():
    old = sys.argv[1] if len(sys.argv) > 1 else None
    for faction in ("Alliance", "Horde"):
        path = "OpenXP/Guides/Leveling/%s/PoleStar-01-60.lua" % faction
        new = legs_for(open(os.path.join(ROOT, path)).read(), faction)
        before = set()
        if old:
            before = set(legs_for(subprocess.check_output(["git", "-C", ROOT, "show", "%s:%s" % (old, path)], text=True), faction))
        have = baked(faction)
        missing = [k for k in new if k not in have and k not in before]
        print("## %s: %d legs, %d without a baked walk%s" % (faction, len(new), len(missing),
              " that %s didn't have" % old if old else ""))
        for k in sorted(missing, key=lambda k: (new[k][0], k)):
            g, a, b = new[k]
            print("- `%s`\n  from %s\n  to   %s" % (k, a, b))
        print()


if __name__ == "__main__":
    main()
