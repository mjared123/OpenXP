#!/usr/bin/env python3
"""Import PoleStar's 1-20 leveling guides into OpenXP 2.0's guide format.

    python3 tools/import_polestar.py [--src ../polestar-src] [--any-commit]

PoleStar (https://github.com/fitzforge/polestar, GPL-3.0) is read from a
local clone at the pinned commit below. Only its compiled guide data
(addon/Polestar_Guides*/Guides.lua) is read, as data: the files are parsed
with tools/lua_data.py, never run. Its walking legs (Legs.lua) are not used;
OpenXP's own terrain does that job.

What it builds, per faction, into OpenXP/Guides/Leveling/<Faction>/01-20.lua:
  * each race's starting guide (only that race), then the shared zones up to
    the hand-off into OpenXP's own 21-60 guides (HANDOFF below);
  * class quests: PoleStar's class guides that start before level 20 and
    whose quests the race's route doesn't already do are merged into the
    route where the player reaches their level (only that class sees them);
  * every PoleStar goal mapped to an OpenXP goal (see convert_goal), names and
    colours filled in for {npc:..}, {item:..} and the like.

Each output file starts with a header naming PoleStar, the commit and the
licence. tests/playthrough_test.lua plays the result for every race and
class from level 1 to 60.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import lua_data  # noqa: E402
from lua_data import as_list  # noqa: E402

PIN = "c0c99712a7b907455dd49cc928484aa0114765d8"
DEFAULT_SRC = os.path.join(os.path.dirname(ROOT), "polestar-src")
OUT_DIR = os.path.join(ROOT, "OpenXP", "Guides", "Leveling")

GROUP = {"Alliance": "OpenXP Leveling (Alliance)", "Horde": "OpenXP Leveling (Horde)"}
HANDOFF = {"Alliance": "21-22 Ashenvale", "Horde": "22-23 Hillsbrad/Alterac"}

# race starting guide -> the race filter it gets
STARTS = {
    "Alliance": [
        ("forever/alliance/human/01-elwynn-forest", "Human"),
        ("forever/alliance/dwarf/01-dun-morogh", "Dwarf"),
        ("forever/alliance/gnome/01-dun-morogh", "Gnome"),
        ("forever/alliance/nightelf/01-teldrassil", "NightElf"),
        ("forever/alliance/skyborne/01-zephras-isle", "Alliance Skyborne"),
    ],
    "Horde": [
        ("forever/horde/orc/01-durotar", "Orc"),
        ("forever/horde/troll/01-durotar", "Troll"),
        ("forever/horde/undead/01-tirisfal-glades", "Scourge"),
        ("forever/horde/tauren/01-mulgore", "Tauren"),
        ("forever/horde/skyborne/01-zephras-isle", "Horde Skyborne"),
    ],
}
# the last PoleStar guide of each faction's route: it hands over to HANDOFF
LAST = {"Alliance": "forever/alliance/03-darkshore-return", "Horde": "forever/horde/05-stonetalon-mountains"}
CLASS_BEFORE = 20     # class guides starting below this level are merged in
RACES = {"Alliance": ["Human", "Dwarf", "Gnome", "NightElf", "Skyborne"],
         "Horde": ["Orc", "Troll", "Scourge", "Tauren", "Skyborne"]}
CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]
CLASS_WORD = {c: c.capitalize() for c in CLASSES}

BLOCKING = {"accept", "turnin", "complete", "finish", "collect", "xp", "zone", "fp", "home", "reach", "train", "fly"}


class ImportError_(Exception):
    pass


# ---------------------------------------------------------------------------
# Reading PoleStar
# ---------------------------------------------------------------------------

def read_guides(src):
    addon = os.path.join(src, "addon")
    guides = []
    for pack in sorted(os.listdir(addon)):
        f = os.path.join(addon, pack, "Guides.lua")
        if pack.startswith("Polestar_Guides") and os.path.exists(f):
            for g in lua_data.find_calls(open(f, encoding="utf-8").read(), "Polestar.RegisterGuide"):
                guides.append(g)
    return {g["id"]: g for g in guides}


def read_flights():
    text = open(os.path.join(ROOT, "OpenXP", "Data", "Flights.lua"), encoding="utf-8").read()
    t, _ = lua_data.parse_table(text, text.index("{", text.index("OXP.flightData")))
    return t["nodes"]


def lst(x):
    return as_list(x) if isinstance(x, dict) else list(x or [])


# ---------------------------------------------------------------------------
# Filters and text
# ---------------------------------------------------------------------------

def filter_string(only, extra_class=None, extra=None):
    """PoleStar {races = {...}, classes = {...}} -> OpenXP "Human Paladin/Dwarf Paladin"."""
    races = lst(only.get("races")) if only else []
    classes = lst(only.get("classes")) if only else []
    if extra_class:
        if classes and extra_class not in classes:
            return False  # can never match
        classes = [extra_class]
    words_r = races or [None]
    words_c = [CLASS_WORD[c] for c in classes] or [None]
    choices = []
    for r in words_r:
        for c in words_c:
            parts = [w for w in (extra, r, c) if w]
            choices.append(" ".join(parts))
    choices = [c for c in choices if c]
    return "/".join(choices) if choices else None


class Names:
    """{kind:id} placeholders -> names, with OpenXP colour tags."""

    def __init__(self, guides):
        self.quest, self.npc, self.enemy = {}, {}, set()
        for g in guides.values():
            for st in lst(g.get("steps")):
                for goal in lst(st.get("goals")):
                    if goal.get("quest") and goal.get("title"):
                        self.quest[goal["quest"]] = goal["title"]
                    if goal.get("npc") and goal.get("npcName"):
                        self.npc[goal["npc"]] = goal["npcName"]
                    if goal.get("t") == "kill" and goal.get("npc"):
                        self.enemy.add(goal["npc"])
                    for f in lst(goal.get("fromNpcs")):
                        if isinstance(f, dict) and f.get("npc"):
                            self.enemy.add(f["npc"])
                            self.npc.setdefault(f["npc"], f.get("npcName"))

    def resolve(self, text, names):
        if not text:
            return text

        def sub(m):
            kind, ident = m.group(1), m.group(2)
            name = names.get("%s:%s" % (kind, ident)) if names else None
            num = int(ident) if ident.isdigit() else None
            if kind == "npc":
                name = name or self.npc.get(num) or "?"
                tag = "ENEMY" if num in self.enemy else "FRIENDLY"
                return "|cOXP_%s_%s|r" % (tag, name)
            if kind == "item":
                return "|cOXP_LOOT_%s|r" % (name or "item")
            if kind == "object":
                return "|cOXP_PICK_%s|r" % (name or "object")
            if kind == "quest":
                return name or self.quest.get(num) or ("quest %s" % ident)
            return name or kind
        return re.sub(r"\{(\w+):([^}]+)\}", sub, text)


# ---------------------------------------------------------------------------
# Goals
# ---------------------------------------------------------------------------

def spot(goal):
    if goal.get("map") is not None and goal.get("x") is not None:
        return {"zone": str(goal["map"]), "x": round(goal["x"], 2), "y": round(goal["y"], 2)}


class Converter:
    def __init__(self, guides, flights):
        self.guides = guides
        self.flights = flights
        self.names = Names(guides)
        self.dropped = []      # (guide, step title, why)
        self.unknown = {}

    def text(self, s, names):
        return self.names.resolve(s, names)

    def convert_goal(self, goal, names):
        """One PoleStar goal -> a list of OpenXP goals (dicts with kind under 1)."""
        t = goal.get("t")
        out = []
        only = filter_string(goal.get("only")) if goal.get("only") else None
        note = self.text(goal.get("note"), names)
        where = spot(goal)

        def add(kind, **fields):
            g = {1: kind}
            g.update({k: v for k, v in fields.items() if v is not None})
            if only and "only" not in g:
                g["only"] = only
            out.append(g)
            return g

        def at():
            if where:
                add("goto", **where)

        quest, title = goal.get("quest"), goal.get("title")
        optional = True if goal.get("optional") else None
        if t in ("accept", "turnin"):
            verb = "Accept" if t == "accept" else "Turn in"
            text = "%s %s" % (verb, title)
            if note:
                text += " (" + note + ")"
            at()
            add(t, quest=quest, optional=optional, text=text)
            who = goal.get("npcName") or goal.get("objName")
            if goal.get("npcName"):
                add("target", name=goal["npcName"])
            elif goal.get("itemName"):
                add("item", item=goal.get("item"), text="Starts from |cOXP_LOOT_%s|r" % goal["itemName"])
            del who
        elif t in ("collect", "kill", "interact", "use", "talk") and quest and goal.get("oi"):
            if t == "collect":
                text = "%s: %s" % (goal.get("itemName"), goal.get("count") or 1)
            elif t == "kill":
                text = "Kill %s: %s" % (goal.get("target"), goal.get("count") or 1)
            elif t == "interact":
                text = "Use |cOXP_PICK_%s|r" % goal.get("objName")
            elif t == "use":
                text = "Use |cOXP_LOOT_%s|r" % goal.get("itemName")
            else:
                text = "Talk to |cOXP_FRIENDLY_%s|r" % goal.get("npcName")
            if note:
                text += " (" + note + ")"
            at()
            add("complete", quest=quest, obj=goal["oi"], optional=optional, text=text)
            if t == "kill" and goal.get("target"):
                add("mob", name=goal["target"])
            for f in lst(goal.get("fromNpcs"))[:3]:
                if isinstance(f, dict) and f.get("npcName"):
                    add("mob", name=f["npcName"])
            if t == "talk" and goal.get("npcName"):
                add("target", name=goal["npcName"])
        elif t == "collect":
            text = "%s: %s" % (goal.get("itemName"), goal.get("count") or 1)
            if note:
                text += " (" + note + ")"
            at()
            add("collect", item=goal.get("item"), count=goal.get("count") or 1, text=text,
                optional=optional)
        elif t == "complete":
            objs = [o.get("text") for o in lst(goal.get("objs")) if isinstance(o, dict) and o.get("text")]
            text = "Finish %s" % title + ((": " + ", ".join(objs)) if objs else "")
            if note:
                text += " (" + note + ")"
            at()
            add("finish", quest=quest, optional=optional, text=text)
        elif t in ("use", "interact", "talk"):
            name = goal.get("itemName") or goal.get("objName") or goal.get("npcName") or ""
            text = (goal.get("text") and self.text(goal["text"], names)) or ("Use " + name)
            if note:
                text += " (" + note + ")"
            at()
            add("item" if goal.get("item") else "text", item=goal.get("item"), text=text)
        elif t == "goto":
            text = self.text(goal.get("text"), names) or "Go here"
            if note:
                text += " (" + note + ")"
            add("reach", radius=goal.get("r"), text=text, **where)
        elif t == "getfp":
            at()
            add("fp", name=goal.get("location"), text="Get the %s flight path" % goal.get("location"))
            if goal.get("npcName"):
                add("target", name=goal["npcName"])
        elif t == "sethome":
            at()
            add("home", name=goal.get("location"), text="Set your Hearthstone to %s" % goal.get("location"))
            if goal.get("npcName"):
                add("target", name=goal["npcName"])
        elif t == "fly":
            node = self.flights.get(goal.get("node"))
            text = "Fly to %s" % goal.get("location")
            if note:
                text += " (" + note + ")"
            if node:
                add("fly", name=goal.get("location"), wx=node["wx"], wy=node["wy"], inst=node["inst"], text=text)
            else:
                add("fly", name=goal.get("location"), text=text)
        elif t == "train":
            text = note or "Train your new spells"
            if goal.get("npcName"):
                at()
                add("train", text="Train at |cOXP_FRIENDLY_%s|r" % goal["npcName"] + (" (" + note + ")" if note else ""))
                add("target", name=goal["npcName"])
            else:
                seen = set()
                for c in lst(goal.get("candidates")):
                    if not isinstance(c, dict):
                        continue  # a shared record PoleStar's addon looks up at run time
                    for cls in lst(c.get("classes")):
                        if cls in seen:
                            continue
                        seen.add(cls)
                        cls_only = filter_string(goal.get("only"), cls) if goal.get("only") else CLASS_WORD[cls]
                        if cls_only is False:
                            continue
                        s = spot(c)
                        if s:
                            g = {1: "goto", "only": cls_only}
                            g.update(s)
                            out.append(g)
                        who = c.get("npcName")
                        out.append({1: "train", "only": cls_only,
                                    "text": ("Train at |cOXP_FRIENDLY_%s|r" % who) if who else "Train at your class trainer"})
                        if who:
                            out.append({1: "target", "only": cls_only, "name": who})
                if not seen:
                    add("train", text=text)
        elif t == "buy":
            text = "Buy %s %s from |cOXP_FRIENDLY_%s|r" % (goal.get("count") or 1, goal.get("itemName"), goal.get("npcName"))
            if note:
                text += " (" + note + ")"
            at()
            if optional:
                add("item", item=goal.get("item"), text=text)
            else:
                add("collect", item=goal.get("item"), count=goal.get("count") or 1, text=text)
            if goal.get("npcName"):
                add("target", name=goal["npcName"])
        elif t == "vendor":
            first = next((c for c in lst(goal.get("candidates")) if isinstance(c, dict)), None)
            if first:
                add("text", text="Sell junk and repair at |cOXP_FRIENDLY_%s|r" % first.get("npcName"))
        elif t == "level":
            add("xp", level=int(goal["level"]), text="Reach level %d" % int(goal["level"]) + (" (" + note + ")" if note else ""))
            if where:
                at()
        elif t == "note":
            add("text", text=self.text(goal.get("text"), names))
        elif t == "die":
            add("text", text="Die and release your spirit: you come back at the %s graveyard" % goal.get("location"))
            add("reach", radius=60, text="At %s" % goal.get("location"), **where)
        elif t == "kill":
            # a kill no quest counts (a rare, or "kill these on the way"): shown only
            at()
            if goal.get("target"):
                add("mob", name=goal["target"])
                add("text", text="Kill |cOXP_ENEMY_%s|r" % goal["target"] + (" (" + note + ")" if note else ""))
        elif t == "task":
            add("text", text=self.text(goal.get("text") or goal.get("title") or "", names) + (" (" + note + ")" if note else ""))
        elif t == "enter":
            add("zone", name=goal.get("location"), text="Go into %s" % goal.get("location") + (" (" + note + ")" if note else ""))
        else:
            self.unknown[t] = self.unknown.get(t, 0) + 1
        return out

    def convert_when(self, when):
        out = []
        for c in lst(when):
            k = c.get("k")
            cond = None
            if k == "turnedin":
                cond = {1: "turnedin", "quest": c["q"]}
            elif k == "onquest":
                cond = {1: "onquest", "quests": lst(c["q"]) if isinstance(c["q"], dict) else [c["q"]]}
            elif k == "complete":
                cond = {1: "complete", "quest": c["q"]}
            elif k == "money":
                cond = {1: "money", "n": c.get("n")}
            elif k == "skill":
                cond = {1: "skill", "name": c.get("name")}
            elif k == "zone":
                cond = {1: "zone", "name": c.get("name")}
            elif k == "group":
                cond = {1: "group", "quest": c.get("q")}
            elif k == "has":
                cond = {1: "has", "item": c.get("item"), "n": c.get("n") or 1}
            elif k == "level":
                op, n = c.get("op"), c.get("n")
                if op in (None, ">="):
                    cond = {1: "level", "n": n}
                elif op == ">":
                    cond = {1: "level", "n": n + 1}
                elif op == "<":
                    cond = {1: "level", "n": n, "neg": True}
                elif op == "<=":
                    cond = {1: "level", "n": n + 1, "neg": True}
                else:
                    raise ImportError_("level condition with op %r" % op)
            else:
                raise ImportError_("unknown step condition %r" % k)
            if c.get("neg"):
                cond["neg"] = True
            out.append(cond)
        return out or None

    def convert_step(self, st, names, gid, class_word=None):
        only = st.get("only")
        f = filter_string(only, class_word.upper() if class_word else None) if (only or class_word) else None
        if f is False:
            return None
        goals = []
        title = self.text(st.get("title"), names)
        if title:
            goals.append({1: "text", "text": title})
        if st.get("note"):
            goals.append({1: "text", "text": self.text(st["note"], names)})
        for goal in lst(st.get("goals")):
            goals.extend(self.convert_goal(goal, names))
        # a quest-less item to collect next to quest goals: it gets used up in
        # the step (a bauble you carry to a shrine), so it only shows
        blocking = [g for g in goals if g[1] in BLOCKING]
        if any(g[1] != "collect" for g in blocking):
            for g in goals:
                if g[1] == "collect" and g.get("optional"):
                    g[1] = "item"
            if any(g[1] == "collect" and not g.get("quest") for g in goals) and any(g[1] in ("complete", "finish", "turnin") for g in goals):
                for g in goals:
                    if g[1] == "collect":
                        g[1] = "item"
                        g.pop("count", None)
        for g in goals:
            g.pop("optional", None) if g[1] == "item" else None
        if not any(g[1] in BLOCKING for g in goals):
            gt = next((g for g in goals if g[1] == "goto"), None)
            if gt:
                gt[1] = "reach"
                gt["radius"] = 25
            else:
                self.dropped.append((gid, title, "nothing to do or reach"))
                return None
        step = {"goals": goals}
        if f:
            step["only"] = f
        when = self.convert_when(st.get("when"))
        if when:
            step["when"] = when
        if st.get("along"):
            step["along"] = st["along"]
        if st.get("label"):
            step["label"] = st["label"]
        return step


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

def guide_name(g, names):
    title = names.resolve(g.get("title"), g.get("names")) if g.get("title") else None
    return "%d-%d %s" % (g["minLevel"], g["maxLevel"], title or g.get("zoneName"))


def chain_after(guides, gid, last):
    out = []
    while gid:
        out.append(gid)
        if gid == last:
            return out
        gid = guides[gid].get("next")
    raise ImportError_("route from %s never reaches %s" % (out[0], last))


def quests_for(g, race, cls):
    q = set()
    for st in lst(g.get("steps")):
        if not st_matches(st.get("only"), race, cls):
            continue
        for goal in lst(st.get("goals")):
            if goal.get("quest") and goal.get("t") in ("accept", "turnin") and st_matches(goal.get("only"), race, cls):
                q.add(goal["quest"])
    return q


def st_matches(only, race, cls):
    if not only:
        return True
    rs, cs = lst(only.get("races")), lst(only.get("classes"))
    return (not rs or race in rs) and (not cs or cls in cs)


def build_faction(conv, guides, faction):
    """Our guides (dicts) for one faction, in route order."""
    starts = STARTS[faction]
    shared = None
    route_of = {}
    for gid, race_only in starts:
        route = chain_after(guides, gid, LAST[faction])
        route_of[gid] = route
        # the shared part starts at the first guide no race guide owns
        first_shared = next(r for r in route if race_tag(r) is None)
        tail = route[route.index(first_shared):]
        if shared is None:
            shared = tail
        elif shared != tail:
            raise ImportError_("races of %s don't share one route: %s vs %s" % (faction, shared, tail))
    race_guides = []
    for gid, race_only in starts:
        for r in route_of[gid]:
            if r in shared:
                break
            race_guides.append((r, race_only))

    out = {}
    order = [r for r, _ in race_guides] + shared
    for gid in order:
        g = guides[gid]
        race_only = dict(race_guides).get(gid)
        steps = []
        for st in lst(g.get("steps")):
            s = conv.convert_step(st, g.get("names"), gid)
            if s:
                steps.append(s)
        out[gid] = {
            "pid": gid, "name": guide_name(g, conv.names), "group": GROUP[faction], "subgroup": "OpenXP 1-20",
            "only": race_only or faction, "minLevel": g["minLevel"], "maxLevel": g["maxLevel"],
            "steps": steps, "next": None,
        }
    for gid in order:
        nxt = guides[gid].get("next")
        out[gid]["next"] = out[nxt]["name"] if gid != LAST[faction] and nxt in out else HANDOFF[faction]

    merge_class_quests(conv, guides, faction, out, race_guides, shared)
    for gid in order:
        resolve_along(out[gid])
    return [out[gid] for gid in order]


def race_tag(gid):
    parts = gid.split("/")
    return parts[2] if len(parts) > 3 else None


def merge_class_quests(conv, guides, faction, out, race_guides, shared):
    """Class guides starting below CLASS_BEFORE whose quests a race's route
    doesn't already do: merged where that race reaches the level."""
    class_guides = sorted(
        (g for g in guides.values() if g.get("category") == "Class" and (g.get("minLevel") or 99) < CLASS_BEFORE
         and g.get("faction") in (None, faction)),
        key=lambda g: (g["minLevel"], g["id"]))
    conv.class_merged = getattr(conv, "class_merged", [])
    conv.class_covered = getattr(conv, "class_covered", [])
    for cg in class_guides:
        cls = cg["id"].split("/")[2].upper()
        if cls not in CLASSES:
            continue
        placed = set()
        for race in RACES[faction]:
            start = next(r for r, o in race_guides if race in o)
            route = [r for r, o in race_guides if o == dict(race_guides)[start]] + shared
            have = set()
            for gid in route:
                have |= quests_for(guides[gid], race, cls)
            want = quests_for(cg, race, cls)
            if not want:
                continue
            if not (want - have):
                conv.class_covered.append((faction, race, cg["id"]))
                continue
            target = cg["minLevel"] + 1
            where = next((gid for gid in route if out[gid]["maxLevel"] >= target), route[-1])
            if where in placed:
                continue
            placed.add(where)
            g = out[where]
            n = len(g["steps"])
            span = max(1, g["maxLevel"] - g["minLevel"])
            at = n if target > g["maxLevel"] else max(1, min(n, round((target - g["minLevel"]) / span * n)))
            new = []
            title_step = {"goals": [{1: "text", "text": "Class quest: %s" % cg["title"]}], "only": CLASS_WORD[cls]}
            for st in lst(cg.get("steps")):
                s = conv.convert_step(st, cg.get("names"), cg["id"], CLASS_WORD[cls])
                if s:
                    new.append(s)
            if new:
                new[0]["goals"] = title_step["goals"] + new[0]["goals"]
                g["steps"][at:at] = new
                conv.class_merged.append((faction, cg["id"], g["name"]))


CLASS_UNTIL = 55      # class guides from level 20 up to (not including) this go into 21-60


def old_filter(expr, race, cls):
    """A 1.x / 2.0 guide filter ("Human Paladin/!Warrior") for one race and class."""
    if not expr:
        return True
    words_race = {"undead": "Scourge"}
    for choice in expr.split("/"):
        ok = True
        for w in choice.split():
            neg = w.startswith("!")
            w = w.lstrip("!")
            lw = w.lower()
            if lw in ("alliance", "horde"):
                hit = True  # the route is one faction's already
            elif lw.upper() in CLASSES:
                hit = lw.upper() == cls
            elif w.isdigit():
                hit = True
            else:
                hit = words_race.get(lw, w) == race
            if hit == neg:
                ok = False
                break
        if ok:
            return True
    return False


def our_route(faction):
    """Our 21-60 guides (parsed 1.x sources) in route order from the hand-off."""
    import convert_guides
    src = os.path.join(ROOT, "Guides", "openxp")
    by = {}
    for f in sorted(os.listdir(src)):
        if f.startswith(faction + "-"):
            text = open(os.path.join(src, f), encoding="utf-8").read()
            for i, body in enumerate(convert_guides.GUIDE_RE.findall(text)):
                g = convert_guides.parse_guide(body, "%s guide %d" % (f, i + 1))
                by[g["name"]] = g
    route, name = [], HANDOFF[faction]
    while name and name in by and name not in [r["name"] for r in route]:
        route.append(by[name])
        name = by[name].get("next")
    return route


def class_inserts(conv, guides, faction):
    """Class guides from level 20 that the 21-60 route doesn't already do,
    as insertions into our 21-60 guides."""
    route = our_route(faction)
    levels = []
    for g in route:
        lo, hi = re.match(r"(\d+)-(\d+)", g["name"]).groups()
        levels.append((int(lo), int(hi)))
    out, placed = [], set()
    class_guides = sorted(
        (g for g in guides.values() if g.get("category") == "Class" and CLASS_BEFORE <= (g.get("minLevel") or 0) < CLASS_UNTIL
         and g.get("faction") in (None, faction)),
        key=lambda g: (g["minLevel"], g["id"]))
    for cg in class_guides:
        cls = cg["id"].split("/")[2].upper()
        if cls not in CLASSES:
            continue  # class guides filed by topic (mounts and so on)
        for race in RACES[faction]:
            want = quests_for(cg, race, cls)
            if not want:
                continue
            have = set()
            for g in route:
                for st in g["steps"]:
                    if not old_filter(st.get("only"), race, cls):
                        continue
                    for goal in st["goals"]:
                        if goal.get("kind") in ("accept", "turnin") and goal.get("quest") and old_filter(goal.get("only"), race, cls):
                            have.add(goal["quest"])
            if not (want - have):
                conv.class_covered.append((faction, race, cg["id"]))
                continue
            target = cg["minLevel"] + 1
            k = next((i for i, (lo, hi) in enumerate(levels) if hi >= target), len(route) - 1)
            if (k, cg["id"]) in placed:
                continue
            placed.add((k, cg["id"]))
            g, (lo, hi) = route[k], levels[k]
            n = len(g["steps"])
            at = n if target > hi else max(1, min(n, round((target - lo) / max(1, hi - lo) * n)))
            steps = []
            for st in lst(cg.get("steps")):
                s = conv.convert_step(st, cg.get("names"), cg["id"], CLASS_WORD[cls])
                if s:
                    steps.append(s)
            if not steps:
                continue
            steps[0]["goals"] = [{1: "text", "text": "Class quest: %s" % cg["title"]}] + steps[0]["goals"]
            resolve_along({"steps": steps}, relative=True)
            out.append({"guide": g["name"], "at": at, "source": "polestar:" + cg["id"],
                        "steps": [json_step(s) for s in steps]})
            conv.class_merged.append((faction, cg["id"], g["name"]))
    return out


def quest_enders():
    """quest id -> name of the NPC who takes it (OpenXP's quest data)."""
    path = os.path.join(ROOT, "OpenXP", "Data", "QuestDB.lua")
    text = open(path, encoding="utf-8").read()
    npc = {int(m.group(1)): m.group(2) for m in re.finditer(r'^N\[(\d+)\] = \{"((?:[^"\\]|\\.)*)"', text, re.M)}
    out = {}
    for m in re.finditer(r'^Q\[(\d+)\] = \{.*?f = \{\{"n",(\d+)\}', text, re.M):
        name = npc.get(int(m.group(2)))
        if name:
            out[int(m.group(1))] = name.replace('\\"', '"')
    return out


def carried_turnins(conv, faction, built):
    """Quests the 1-20 guides pick up but don't turn in (PoleStar turns them
    in later in its own route): an optional turn-in step right after the
    first 21-60 step that talks to whoever takes the quest. Optional, so
    players who don't have the quest never see it."""
    accepted, turned = {}, set()
    for g in built:
        for st in g["steps"]:
            for goal in st["goals"]:
                if goal[1] == "accept" and goal.get("quest"):
                    accepted.setdefault(goal["quest"], goal.get("text", "").replace("Accept ", "", 1))
                elif goal[1] == "turnin" and goal.get("quest"):
                    turned.add(goal["quest"])
    enders = quest_enders()
    route = our_route(faction)
    out, missing = [], []
    for q, title in sorted(accepted.items()):
        if q in turned:
            continue
        who = enders.get(q)
        placed = False
        for g in route if who else []:
            for i, st in enumerate(g["steps"], 1):
                if any(goal.get("kind") == "target" and goal.get("name") == who for goal in st["goals"]):
                    if any(goal.get("kind") == "turnin" and goal.get("quest") == q for goal in st["goals"]):
                        placed = True  # the 21-60 guide turns it in already
                        break
                    spot = next((goal for goal in st["goals"] if goal.get("kind") == "goto"), None)
                    goals = []
                    if spot:
                        goals.append(["goto", {"zone": spot["zone"], "x": spot["x"], "y": spot["y"]}])
                    goals.append(["turnin", {"quest": q, "optional": True,
                                             "text": "Turn in %s (picked up earlier)" % title.split(" (")[0]}])
                    goals.append(["target", {"name": who}])
                    out.append({"guide": g["name"], "at": i, "source": "carry:%d" % q, "carry": True,
                                "steps": [{"only": faction, "goals": goals}]})
                    placed = True
                    break
            if placed:
                break
        if not placed:
            missing.append(q)
    conv.carry_missing = getattr(conv, "carry_missing", []) + [(faction, q) for q in missing]
    conv.carry_added = getattr(conv, "carry_added", 0) + len(out)
    return out


def json_step(st):
    out = {k: v for k, v in st.items() if k != "goals"}
    if "when" in out:
        out["when"] = [json_goal(c) for c in out["when"]]
    out["goals"] = [[g[1], {k: v for k, v in g.items() if k != 1}] for g in st["goals"]]
    return out


def json_goal(c):
    # a when-condition { 1 = kind, ... } -> { "1": kind, ... } in Lua as { kind, ... }
    return [c[1], {k: v for k, v in c.items() if k != 1}]


def resolve_along(g, relative=False):
    """'as you go' steps run until the step with their label: an index."""
    labels = {}
    for i, st in enumerate(g["steps"], 1):
        if st.get("label"):
            labels.setdefault(st["label"], i)
    for i, st in enumerate(g["steps"], 1):
        if st.get("along"):
            until = labels.get(st["along"])
            until = until if until and until > i else len(g["steps"])
            st["until_rel" if relative else "until"] = until
            st["along"] = True
    for st in g["steps"]:
        st.pop("label", None)


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        r = repr(round(v, 2)) if isinstance(v, float) else str(v)
        return r[:-2] if r.endswith(".0") else r
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }"
    if isinstance(v, dict):
        parts = []
        if 1 in v:
            parts.append(lua_val(v[1]))
        for k in sorted(k for k in v if k != 1):
            key = k if re.match(r"^[A-Za-z_]\w*$", str(k)) and k not in ("until",) else "[%s]" % lua_str(k)
            parts.append("%s = %s" % (key, lua_val(v[k])))
        return "{ " + ", ".join(parts) + " }"
    raise ImportError_("can't write %r" % (v,))


def render(faction, guides_out, commit):
    out = [
        "-- OpenXP 2.0 guide data: %s levels 1-20." % faction,
        "-- Generated by tools/import_polestar.py; edit the generator, not this file.",
        "--",
        "-- Adapted from PoleStar's guides (https://github.com/fitzforge/polestar,",
        "-- commit %s), GPL-3.0. Quest titles, names and" % commit,
        "-- coordinates in them come from PoleStar's reference data; see NOTICE.md",
        "-- for those sources. This file is part of OpenXP and is licensed under the",
        "-- GNU General Public License, version 3 (see LICENSE in this folder).",
        "local _, OXP = ...",
        "OXP.AddGuides({",
        "  file = %s," % lua_str(faction + "-01-20"),
        "  faction = %s," % lua_str(faction),
    ]
    for g in guides_out:
        out.append("  {")
        out.append("    name = %s," % lua_str(g["name"]))
        out.append("    group = %s," % lua_str(g["group"]))
        out.append("    subgroup = %s," % lua_str(g["subgroup"]))
        if g["next"]:
            out.append("    next = %s," % lua_str(g["next"]))
        out.append("    only = %s," % lua_str(g["only"]))
        out.append("    source = %s," % lua_str("polestar:" + g["pid"]))
        out.append("    tags = { \"forever\" },")
        out.append("    steps = {")
        for st in g["steps"]:
            head = []
            for k in ("only", "along", "until", "when"):
                if k in st:
                    key = "[\"until\"]" if k == "until" else k
                    head.append("%s = %s" % (key, lua_val(st[k])))
            out.append("      {" + (" " + ", ".join(head) + "," if head else ""))
            for goal in st["goals"]:
                out.append("        " + lua_val(goal) + ",")
            out.append("      },")
        out.append("    },")
        out.append("  },")
    out.append("})")
    return "\n".join(out) + "\n"


def main(argv):
    src, any_commit = DEFAULT_SRC, False
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
    guides = read_guides(src)
    conv = Converter(guides, read_flights())
    import convert_guides
    built = {}
    for faction in ("Alliance", "Horde"):
        out = build_faction(conv, guides, faction)
        built[faction] = out
        dest = os.path.join(OUT_DIR, faction, "01-20.lua")
        with open(dest, "w", encoding="utf-8", newline="\n") as f:
            f.write(render(faction, out, commit))
        print("%s: %d guides, %d steps -> %s" % (faction, len(out), sum(len(g["steps"]) for g in out),
                                                os.path.relpath(dest, ROOT)))
        for g in out:
            print("   %-28s %-22s next %s" % (g["name"], g["only"], g["next"]))
    # class quests from level 20 go into our 21-60 guides through the converter
    import json
    inserts = {"commit": commit}
    for faction in ("Alliance", "Horde"):
        inserts[faction] = class_inserts(conv, guides, faction) + carried_turnins(conv, faction, built[faction])
    with open(convert_guides.INSERTS, "w", encoding="utf-8", newline="\n") as f:
        json.dump(inserts, f, indent=1, sort_keys=True)
        f.write("\n")
    convert_guides.main([])
    with open(os.path.join(convert_guides.GUIDES_DIR, "Guides.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write(convert_guides.guide_list_xml())
    print("class quest guides merged: %d; already in the route: %d" % (len(conv.class_merged), len(conv.class_covered)))
    print("quests carried over from 1-20, turn-ins added in 21-60: %d; no NPC found in 21-60: %s" % (
        conv.carry_added, ", ".join("%s %d" % m for m in conv.carry_missing) or "none"))
    for faction, cid, where in conv.class_merged:
        print("   %s %-55s -> %s" % (faction, cid, where))
    print("steps dropped: %d" % len(conv.dropped))
    for gid, title, why in conv.dropped[:20]:
        print("   %s: %s (%s)" % (gid, title, why))
    if conv.unknown:
        print("goal kinds not imported: %s" % conv.unknown)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
