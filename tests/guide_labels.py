#!/usr/bin/env python3
"""Catch "#completewith <label>" steps whose label doesn't exist.

A "#completewith X" step stays on screen (and keeps the arrow) until the
guide reaches the step labelled X. When no step has that label, the step
never ends: a Night Elf Druid's Ironforge auction house reminder in the
Loch Modan part of 14-16 Darkshore kept pointing the arrow at Ironforge for
the rest of Darkshore (1.3.58).

Labels from guides pulled in with "#include" count for the guide that
includes them. "next" is always fine.

ALLOWED holds dangling labels inherited from RestedXP's free guides that
don't strand the arrow: the step has no map point, or its point ends on
arrival / entering a zone, so it finishes by itself. Fix them when touching
those guides; don't add new ones.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOWED = {
    ("Alliance-1-10_NightElf.lua", "darnSoD"),          # Season of Discovery only
    ("Alliance-11-20.lua", "MeatFangEgg1"),             # abandon step, no map point
    ("Alliance-11-20.lua", "DeerComplete"),             # Druid crab chunks, ends on completion
    ("Horde-01-12_Durotar.lua", "HorrorsandSpirits"),   # Priest linen, no map point
    ("Horde-01-12_Durotar.lua", "Toolboxes"),           # "equip this" reminders
    ("Horde-01-12_Durotar.lua", "RazorTurnins2"),       # hearth / enter Razor Hill
    ("Horde-01-14_Undead.lua", "FinishRings"),          # Priest linen, no map point
    ("Horde-01-14_Undead.lua", "CaptainMelrache"),      # "equip this" reminders
    ("Horde-01-14_Undead.lua", "RotHideCluesTurnIn"),   # Rogue letter, no map point
    ("Horde-01-14_Undead.lua", "HiddenEnemiesPickup"),  # ends on entering Orgrimmar
    ("Horde-1-12_Mulgore.lua", "CallofEarth"),          # point ends on arrival (30 yd)
    ("Horde-1-12_Mulgore.lua", "ReturntoJahan"),        # pet skills tip, no map point
    ("Horde-12-22_Barrens.lua", "ElderCroneTurnin"),    # "<< skip" step, never shown
}
GUIDE = re.compile(r"RegisterGuide\(\s*\[\[(.*?)\]\]", re.S)


def strip(v):
    return v.split("--")[0].split("<<")[0].strip()


def guides():
    out = []
    for f in sorted(glob.glob(os.path.join(ROOT, "Guides", "forever", "*.lua")) +
                    glob.glob(os.path.join(ROOT, "Guides", "openxp", "*.lua"))):
        text = open(f, encoding="utf-8").read()
        for m in GUIDE.finditer(text):
            body = m.group(1)
            start = text.count("\n", 0, m.start(1)) + 1
            g = {"file": os.path.basename(f), "name": None, "labels": set(), "uses": [], "includes": []}
            for i, line in enumerate(body.split("\n")):
                s = line.strip()
                if s.startswith("--"):
                    continue
                if s.startswith("#name ") and g["name"] is None:
                    g["name"] = strip(s[6:])
                elif s.startswith("#label "):
                    g["labels"].add(strip(s[7:]))
                elif s.startswith("#completewith "):
                    g["uses"].append((strip(s[14:]), start + i))
                elif s.startswith("#include "):
                    g["includes"].append(strip(s[9:]))
            out.append(g)
    return out


def main():
    gs = guides()
    by_name = {}
    for g in gs:
        by_name.setdefault((g["file"], g["name"]), g)
        by_name.setdefault((None, g["name"]), g)

    def labels(g, seen):
        got = set(g["labels"])
        for inc in g["includes"]:
            name = inc.split("\\")[-1]
            sub = by_name.get((g["file"], name)) or by_name.get((None, name))
            if sub and id(sub) not in seen:
                seen.add(id(sub))
                got |= labels(sub, seen)
        return got

    bad = []
    for g in gs:
        have = labels(g, {id(g)})
        for target, ln in g["uses"]:
            if target and target != "next" and target not in have and (g["file"], target) not in ALLOWED:
                bad.append(f"{g['file']}:{ln}: #completewith {target} has no matching #label in {g['name']}")
    for b in bad:
        print(b)
    print(f"guide_labels: {len(bad)} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
