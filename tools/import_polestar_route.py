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
        fix_optional_followups(out)
        fix_race_locked(out, faction)
        fix_other_start_class(out, faction, conv, guides)
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


def fix_snapjaw(out):
    """GitHub #119 (2026-11-25): Horde 39-43 Stranglethorn turns in Some
    Assembly Required (577) with skins gathered in 34-36 Stranglethorn. A
    player who moved on before finishing them arrived at Drizzlik without
    them (and Excelsior needs that turn-in): say where the crocolisks are."""
    for g in out:
        for st in g["steps"]:
            for x in st["goals"]:
                if x.get(1) == "turnin" and x.get("quest") == 577 and "gathered earlier" in x.get("text", ""):
                    x["text"] = ("Turn in Some Assembly Required (|cOXP_FRIENDLY_Drizzlik|r: the Snapjaw skins gathered earlier; inside). "
                                 "No skins yet? |cOXP_ENEMY_Snapjaw Crocolisk|rs line the river around 39.9, 28.4, east of |cOXP_PICK_Grom'gol|r")


def fix_rest_relaxation(out):
    """GitHub #128 (Matt OK'd the reorder, 2026-11-25): Human 1-11 Elwynn
    sent you to Falkhaan Isenstrider by the stables south of the Abbey for
    Rest and Relaxation (2158), then back past the Abbey to turn in Follow
    That Kobold! and (without The Big Picture) north to grind at the mine.
    Falkhaan is on the road south to Goldshire: he's now the first stop of
    the Goldshire step, so you pick it up on the way."""
    g = next((g for g in out if g["name"] == "1-11 Elwynn Forest"), None)
    if not g:
        return
    steps = g["steps"]
    for i, st in enumerate(steps):
        goals = st["goals"]
        k = next((k for k, x in enumerate(goals) if x.get(1) == "accept" and x.get("quest") == 2158), None)
        if k is None:
            continue
        start = k - 1 if k > 0 and goals[k - 1].get(1) == "goto" else k
        end = k + 2 if k + 1 < len(goals) and goals[k + 1].get(1) == "target" else k + 1
        moved = goals[start:end]
        del goals[start:end]
        gold = next(j for j, s2 in enumerate(steps) if j > i and first_text(s2) == "Goldshire"
                    and any(x.get(1) == "turnin" and x.get("quest") == 54 for x in s2["goals"]))
        # first thing on the Goldshire step (no new step: saved places don't move)
        goals2 = steps[gold]["goals"]
        k2 = next(k for k, x in enumerate(goals2) if x.get(1) != "text")
        moved[1] = dict(moved[1], text="Accept Rest and Relaxation (|cOXP_FRIENDLY_Falkhaan Isenstrider|r, by the stables on your way south)")
        goals2[k2:k2] = moved
        return

def fix_apples(out):
    """GitHub #129 (2026-11-26): Elwynn's "Buy 4 Shiny Red Apple" was only a
    reminder, so a player reached the Applejack Still with none. It's a
    collect goal now: the step waits for four apples (bought or looted), and
    the item tooltip says to keep them for the still."""
    g = next((g for g in out if g["name"] == "1-11 Elwynn Forest"), None)
    if not g:
        return
    for st in g["steps"]:
        for k, x in enumerate(st["goals"]):
            if x.get(1) == "item" and x.get("item") == 4536:
                st["goals"][k] = {1: "collect", "item": 4536, "count": 4, "forquest": 91736,
                                  "text": "Shiny Red Apple: 4 (buy from |cOXP_FRIENDLY_Homer Stonefield|r or loot them; "
                                          "keep them for the Applejack Still)"}
                return


def fix_betrayed(out):
    """GitHub #130 (2026-11-26): Belgrom Rockmaul in Orgrimmar didn't offer
    Betrayed (3504) to a level 50 shaman (the player read that it starts at
    Ag'tor Bloodfist in Azshara now). Its pickup and hand-in are optional,
    so the Orgrimmar step no longer waits; Ag'tor's own Betrayed (3505)
    follows as before."""
    for g in out:
        for st in g["steps"]:
            for x in st["goals"]:
                if x.get(1) in ("accept", "turnin") and x.get("quest") == 3504:
                    x["optional"] = True


def fix_optional_followups(out):
    """GitHub #137 (2026-11-26): Westfall's second Harvesting the Harvesters
    (92910, from a drop) is an optional pickup, but its hand-in wasn't: a
    player without the drop was told "you don't have this quest" and the
    step never ended. A quest whose every pickup in the route is optional now
    has optional objectives and hand-ins too (they still count when you have
    the quest)."""
    accepts = {}
    for g in out:
        for st in g["steps"]:
            for x in st["goals"]:
                if x.get(1) == "accept" and x.get("quest"):
                    accepts.setdefault(x["quest"], []).append(bool(x.get("optional")))
    n = 0
    for g in out:
        for st in g["steps"]:
            for x in st["goals"]:
                q = x.get("quest")
                if x.get(1) in ("turnin", "complete", "finish") and q in accepts and all(accepts[q]) \
                        and not x.get("optional"):
                    x["optional"] = True
                    n += 1
    print("   optional follow-ups: %d goals" % n)


def fix_thistle_bear(out):
    """GitHub #149 (2026-11-27): Darkshore 15-19's Plagued Lands step (capture
    a Rabid Thistle Bear) named no mob, so the bears weren't highlighted."""
    g = next((g for g in out if g["name"] == "15-19 Darkshore"), None)
    if not g:
        return
    for st in g["steps"]:
        goals = st["goals"]
        for k, x in enumerate(goals):
            if x.get(1) == "finish" and x.get("quest") == 2118:
                mob = {1: "mob", "name": "Rabid Thistle Bear"}
                if x.get("only"):
                    mob["only"] = x["only"]
                goals.insert(k + 1, mob)
                return


def fix_james_hyal(out):
    """GitHub #155 (2026-11-27): Connor Rivers in Stormwind had no James Hyal
    (1301) for a level 32 Dwarf paladin, and the step waited for it. It's
    only a breadcrumb to James Hyal himself in Theramore (1302), so the
    pickup is optional (its hand-in follows, fix_optional_followups)."""
    for g in out:
        for st in g["steps"]:
            for x in st["goals"]:
                if x.get(1) == "accept" and x.get("quest") == 1301:
                    x["optional"] = True


RACE_IDS = {1: "Human", 2: "Orc", 3: "Dwarf", 4: "NightElf", 5: "Scourge", 6: "Tauren", 7: "Gnome",
            8: "Troll", 33: "Skyborne", 34: "Skyborne"}
QUEST_GOALS = ("accept", "turnin", "complete", "finish")


def quest_races():
    """{quest id: set of race names} from OpenXP/Data/QuestDB.lua (only quests with a race list)."""
    import re
    out = {}
    with open(os.path.join(ROOT, "OpenXP", "Data", "QuestDB.lua"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"Q\[(\d+)\] = \{.*?races = \{([\d,]+)\}", line)
            if m:
                out[int(m.group(1))] = {RACE_IDS[int(r)] for r in m.group(2).split(",") if int(r) in RACE_IDS}
    return out


def has_race(expr, faction=None):
    """Does the filter already name a race (of either faction)?"""
    words = {w.lstrip("!").lower() for choice in expr.split("/") for w in choice.split()}
    return any(r.lower() in words for r in set(RACE_IDS.values()) | {"Undead"})


def race_only(expr, races, faction):
    """"Priest" + {Gnome} -> "Gnome Priest" (every choice of expr, for each race)."""
    keep = [r for r in ip.RACES[faction] if r in races]
    assert keep, "no %s race can take quests of %s" % (faction, expr)
    return "/".join("%s %s" % (r, choice.strip()) for choice in expr.split("/") for r in keep)


def fix_race_locked(out, faction):
    """GitHub #131 (2026-11-26): PoleStar's start guides carry every race's
    racial priest quests (and other race-only class quests) under a class-only
    filter ("Priest"), so a Human priest in Elwynn was sent to Ironforge for
    the Gnomes' Confounding Flash. A class-only step or goal whose quests are
    all limited to some races now names those races too ("Gnome Priest").
    Steps keep their place, so saved positions don't move."""
    races = quest_races()

    def limit(quests):
        if not quests or any(q not in races for q in quests):
            return None
        u = set().union(*(races[q] for q in quests))
        if not any(r in u for r in ip.RACES[faction]):
            return None  # another faction's quests: leave the step as PoleStar wrote it
        return u if any(r not in u for r in ip.RACES[faction]) else None

    for g in out:
        for st in g["steps"]:
            o = st.get("only")
            if o and not has_race(o, faction):
                qs = {x["quest"] for x in st["goals"] if x.get(1) in QUEST_GOALS and x.get("quest")}
                for w in st.get("when") or []:
                    if isinstance(w, dict) and w.get(1) == "onquest":
                        qs |= set(w.get("quests") or [])
                u = limit(qs)
                if u:
                    st["only"] = race_only(o, u, faction)
                    continue
            for x in st["goals"]:
                xo = x.get("only")
                if xo and x.get(1) in QUEST_GOALS and x.get("quest") and not has_race(xo, faction):
                    u = limit({x["quest"]})
                    if u:
                        x["only"] = race_only(xo, u, faction)



ABILITY_CLASSES = ("Druid", "Hunter", "Shaman", "Warlock")
CLASS_IDS = {1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest", 7: "Shaman", 8: "Mage",
             9: "Warlock", 11: "Druid"}


def quest_facts():
    """{quest id: (title, min level, set of class names or None)} from OpenXP/Data/QuestDB.lua."""
    import re
    out = {}
    with open(os.path.join(ROOT, "OpenXP", "Data", "QuestDB.lua"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r'Q\[(\d+)\] = \{"((?:[^"\\]|\\.)*)",(\d+),(\d+)', line)
            if m:
                c = re.search(r"classes = \{([\d,]+)\}", line)
                cls = {CLASS_IDS.get(int(x)) for x in c.group(1).split(",")} if c else None
                out[int(m.group(1))] = (m.group(2), int(m.group(4)), cls)
    return out


def step_quests(st):
    qs = {x["quest"] for x in st["goals"] if x.get(1) in QUEST_GOALS and x.get("quest")}
    for w in st.get("when") or []:
        if isinstance(w, dict) and w.get(1) == "onquest":
            qs |= set(w.get("quests") or [])
    return qs


def fix_other_start_class(out, faction, conv, guides):
    """Matt (2026-11-26): a Night Elf druid who starts in Elwynn (another
    race's starting zone, GitHub #106) never got the druid quests, which
    only happen around Darnassus and Moonglade; the same for Horde hunters'
    first pet, shamans' Call of Earth and warlocks' Voidwalker outside their
    home zone. PoleStar's class guide for such a chain now follows the other
    starting zone's last step, only for that race and class (appended, so no
    saved step moves and no one else's route changes)."""
    races = quest_races()
    chains = {}
    for g in out:
        o = (g.get("only") or "").replace("Alliance ", "").replace("Horde ", "")
        if o in ip.RACES[faction]:
            chains.setdefault(o, []).append(g)
    later = [g for g in out if not any(g in c for c in chains.values())]

    def visible(expr, race, cls):
        if not expr:
            return True
        for choice in expr.split("/"):
            ok = True
            for w in choice.split():
                neg, k = w.startswith("!"), w.lstrip("!").lower()
                if k.isdigit() or k in ("alliance", "horde"):
                    v = k.isdigit() or k == faction.lower()
                elif k in ("undead", "scourge"):
                    v = race == "Scourge"
                elif k in {r.lower() for r in RACE_IDS.values()}:
                    v = k == race.lower()
                else:
                    v = k == cls.lower()
                if v == neg:
                    ok = False
                    break
            if ok:
                return True
        return False

    def have(gs, race, cls):
        q = set()
        for g in gs:
            for st in g["steps"]:
                if visible(st.get("only"), race, cls):
                    q |= {x["quest"] for x in st["goals"] if x.get(1) in ("accept", "turnin") and x.get("quest")
                          and visible(x.get("only"), race, cls)}
        return q

    facts = quest_facts()

    def title(q):
        return facts.get(q, (str(q),))[0]

    class_guides = sorted(
        (g for g in guides.values() if g.get("category") == "Class" and (g.get("minLevel") or 99) < 20
         and g.get("faction") in (None, faction)),
        key=lambda g: (g["minLevel"], g["id"]))
    plan = {}  # (guide name, guide only, class guide id) -> races, in order
    for race in ip.RACES[faction]:
        for other, gs in chains.items():
            if other == race:
                continue
            for cls in ABILITY_CLASSES:
                done = have(gs + later, race, cls)
                for cg in class_guides:
                    if cg["id"].split("/")[2].upper() != cls.upper():
                        continue
                    want = {q for q in ip.quests_for(cg, race, cls.upper()) if q not in races or race in races[q]}
                    # by title: each race has its own Taming the Beast, any one does
                    if not want or not ({title(q) for q in want} - {title(q) for q in done}):
                        continue
                    done |= want
                    plan.setdefault((id(gs[-1]), cg["id"]), (gs[-1], cg, cls, []))[3].append(race)
    for last, cg, cls, rs in plan.values():
        new = []
        for st in ip.lst(cg.get("steps")):
            s2 = conv.convert_step(st, cg.get("names"), cg["id"], cls)
            if s2:
                new.append(s2)
        if not new:
            continue
        new[0]["goals"] = [{1: "text", "text": "Class quest: %s" % cg["title"]}] + new[0]["goals"]
        ip.resolve_along({"steps": new})
        n = len(last["steps"])
        for s2 in new:
            s2["only"] = "/".join("%s %s" % (r, cls) for r in rs)
            if s2.get("until"):
                s2["until"] += n
        last["steps"].extend(new)
        print("   %s %s (%s): +%d steps, %s for %s" % (faction, last["name"], last["only"], len(new), cg["id"],
                                                     "/".join(rs)))

ROUTE_FIXES = {"Horde": [fix_bloodsail, fix_snapjaw, fix_betrayed],
               "Alliance": [fix_fiora, fix_malin, fix_rest_relaxation, fix_apples, fix_thistle_bear, fix_james_hyal]}


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
