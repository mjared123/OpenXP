#!/usr/bin/env python3
"""Import PoleStar's whole 1-60 leveling route as its own guide group.

    python3 tools/import_polestar_route.py [--src ../polestar-src] [--any-commit]

This is OpenXP's default leveling route (group "OpenXP Leveling (<Faction>)"),
Matt's choice on 2026-11-13. Our own 21-60 route stays in the guide menu as
"OpenXP Legacy (<Faction>)" (tools/convert_guides.py), so 1.x players carry on
where they were. This script writes PoleStar's route from each race's start
to level 60:

  * each race's starting guide (only that race), then the faction's shared
    zones in PoleStar's order up to its last 60 guide;
  * PoleStar's class guides below level 60 whose quests the route doesn't
    already do, merged where the player reaches their level (only that class
    sees them);
  * every goal mapped the same way as tools/import_polestar.py does
    (it reuses that script's Converter).

Output: OpenXP/Guides/Leveling/<Faction>/PoleStar-01-60.lua, plus Guides.xml.
tests/playthrough_test.lua plays it and the legacy group for every race and class.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import import_polestar as ip  # noqa: E402
import convert_guides  # noqa: E402

# PoleStar v0.3.7.2
PIN = "19bd636e7d6f33231770f6029c76d2d4dfc63798"
GROUP = {"Alliance": "OpenXP Leveling (Alliance)", "Horde": "OpenXP Leveling (Horde)"}
LAST = {"Alliance": "forever/alliance/50-60/06-silithus", "Horde": "forever/horde/50-60/07-felwood"}


def subgroup(g):
    lo = g["minLevel"]
    return "1-20" if lo < 20 else "%d-%d" % (lo // 10 * 10, lo // 10 * 10 + 10)


def build(conv, guides, faction):
    # build_faction reads these module settings; point them at the full route
    saved = (dict(ip.LAST), dict(ip.HANDOFF), dict(ip.GROUP), ip.CLASS_BEFORE)
    ip.LAST[faction] = LAST[faction]
    ip.HANDOFF[faction] = None
    ip.GROUP[faction] = GROUP[faction]
    ip.CLASS_BEFORE = 60
    try:
        out = ip.build_faction(conv, guides, faction)
        for fix in ROUTE_FIXES.get(faction, []):
            fix(out)
    finally:
        ip.LAST.clear(); ip.LAST.update(saved[0])
        ip.HANDOFF.clear(); ip.HANDOFF.update(saved[1])
        ip.GROUP.clear(); ip.GROUP.update(saved[2])
        ip.CLASS_BEFORE = saved[3]
    for g in out:
        g["subgroup"] = "OpenXP " + subgroup(g)
    names = [(g["name"], g["only"]) for g in out]
    dup = {n for n in names if names.count(n) > 1}
    if dup:
        raise ip.ImportError_("two guides named %s" % ", ".join(sorted("%s <%s>" % d for d in dup)))
    return out


def first_text(step):
    for g in step["goals"]:
        if g.get(1) == "text":
            return g.get("text")


def fix_bloodsail(out):
    """GitHub #96 (Matt, 2026-11-23): in Horde 39-43 Stranglethorn the Wild
    Shore fight (Bloodsail quests 41-43) came at step 6, at level 39. It and
    its Booty Bay turn-ins move to the guide's second Booty Bay stop (after
    the Mistvale / Nesingwary / Zul'Kunda loop, about 41-42); the quests are
    still picked up on the first visit."""
    g = next((g for g in out if g["name"] == "39-43 Stranglethorn Vale & Swamp of Sorrows"), None)
    if not g:
        return
    steps = g["steps"]
    shore = next(i for i, st in enumerate(steps) if first_text(st) == "The Wild Shore")
    bay = shore + 1
    assert first_text(steps[bay]) == "Booty Bay"
    moved_quests = {587, 604, 576}
    goals = steps[bay]["goals"]
    keep, take = [goals[0]], [{1: "text", "text": "Booty Bay"},
                              {1: "text", "text": "Back to Booty Bay with the Bloodsail charts, orders, snuff and Dizzy's Eye."}]
    k = 1
    while k < len(goals):
        # a goto, its goal and its target travel together
        group = [goals[k]]
        while k + len(group) < len(goals) and goals[k + len(group)].get(1) not in ("goto",):
            group.append(goals[k + len(group)])
        q = next((x.get("quest") for x in group if x.get("quest")), None)
        (take if q in moved_quests else keep).extend(group)
        k += len(group)
    steps[bay] = dict(steps[bay], goals=keep)
    wild = steps.pop(shore)
    later = next(i for i, st in enumerate(steps) if i > shore and any(
        x.get("text", "").startswith("Head south to Booty Bay. Shaky") for x in st["goals"]))
    turnins = {"goals": take}
    steps[later:later] = [wild, turnins]


def fix_fiora(out):
    """GitHub #89 (Matt, 2026-11-23): Fiora Longears (1132) needs level 30;
    30-33 Wetlands offered it on its first Menethil stop, where a level 29
    player can't take it. The 32-33 guide's own Menethil stop picks it up."""
    g = next((g for g in out if g["name"] == "30-33 Wetlands & Hillsbrad Foothills"), None)
    if not g:
        return
    for st in g["steps"]:
        goals = st["goals"]
        for k, x in enumerate(goals):
            if x.get(1) == "accept" and x.get("quest") == 1132:
                start = k - 1 if k > 0 and goals[k - 1].get(1) == "goto" else k
                end = k + 2 if k + 1 < len(goals) and goals[k + 1].get(1) == "target" else k + 1
                del goals[start:end]
                return


def fix_malin(out):
    """GitHub #105 (Matt, 2026-11-24): Archmage Malin in Stormwind didn't offer
    Malin's Request (690) to a level 34 player, and the Mage Quarter step
    waited for it. It is optional now, its Refuge Pointe turn-in too; the
    next quest there, Worth Its Weight in Gold, doesn't need it."""
    for g in out:
        for st in g["steps"]:
            for x in st["goals"]:
                if x.get(1) in ("accept", "turnin") and x.get("quest") == 690:
                    x["optional"] = True


ROUTE_FIXES = {"Horde": [fix_bloodsail], "Alliance": [fix_fiora, fix_malin]}


def render(faction, guides_out, commit):
    text = ip.render(faction, guides_out, commit)
    text = text.replace("-- OpenXP 2.0 guide data: %s levels 1-20." % faction,
                        "-- OpenXP 2.0 guide data: PoleStar's %s route, levels 1-60." % faction)
    text = text.replace("-- Generated by tools/import_polestar.py;", "-- Generated by tools/import_polestar_route.py;")
    text = text.replace('file = "%s-01-20"' % faction, 'file = "%s-PoleStar-01-60"' % faction)
    return text


def main(argv):
    src, any_commit = ip.DEFAULT_SRC, False
    i = 0
    while i < len(argv):
        if argv[i] == "--src":
            src = argv[i + 1]
            i += 2
        elif argv[i] == "--any-commit":
            any_commit = True
            i += 1
        else:
            raise SystemExit("unknown argument " + argv[i])
    commit = subprocess.run(["git", "-C", src, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    if commit != PIN and not any_commit:
        raise SystemExit("PoleStar clone is at %s, not the pinned %s (check it out, or --any-commit)" % (commit, PIN))
    guides = ip.read_guides(src)
    conv = ip.Converter(guides, ip.read_flights())
    for faction in ("Alliance", "Horde"):
        out = build(conv, guides, faction)
        dest = os.path.join(ip.OUT_DIR, faction, "PoleStar-01-60.lua")
        with open(dest, "w", encoding="utf-8", newline="\n") as f:
            f.write(render(faction, out, commit))
        print("%s: %d guides, %d steps -> %s" % (faction, len(out), sum(len(g["steps"]) for g in out),
                                                os.path.relpath(dest, ROOT)))
        for g in out:
            print("   %-34s %-20s next %s" % (g["name"], g["only"], g["next"]))
    with open(os.path.join(convert_guides.GUIDES_DIR, "Guides.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write(convert_guides.guide_list_xml())
    print("class quest guides merged: %d; already in the route: %d" % (
        len(getattr(conv, "class_merged", [])), len(getattr(conv, "class_covered", []))))
    for faction, cid, where in getattr(conv, "class_merged", []):
        print("   %s %-55s -> %s" % (faction, cid, where))
    print("steps dropped: %d" % len(conv.dropped))
    for gid, title, why in conv.dropped[:40]:
        print("   %s: %s (%s)" % (gid, title, why))
    if conv.unknown:
        print("goal kinds not imported: %s" % conv.unknown)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
