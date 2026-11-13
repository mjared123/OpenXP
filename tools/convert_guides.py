"""Convert OpenXP's 1.x guide files (Guides/openxp/*.lua, RXP-style text inside
RegisterGuide([[...]])) into OpenXP 2.0 guide data: plain Lua tables that the
2.0 engine reads, with no text to parse in game.

    python3 tools/convert_guides.py                 # every file in Guides/openxp
    python3 tools/convert_guides.py FILE... --out DIR

Each source file goes into the 2.0 addon's guide folder (see out_path):
Alliance-21-30.lua -> OpenXP/Guides/Leveling/Alliance/21-30.lua and
Dungeons-Horde.lua -> OpenXP/Guides/Dungeons/Horde.lua. OpenXP/Guides/Guides.xml,
which the .toc loads, is rewritten to list every file. tests/convert_roundtrip.py
loads the output and checks it says exactly what the source said, step by step.

2.0 guide data (one table per guide):

    {
      name = "21-22 Ashenvale", group = "OpenXP Legacy (Alliance)",
      oldGroup = "RestedXP Forever Guide (A)",   -- 1.x group, for the save importer
      subgroup = "OpenXP 21-60", next = "...", version = 1,
      only = "Alliance", tags = { "forever", "disabledungeons" },
      steps = {
        { only = "Warlock", class = true, completewith = "next",
          { "goto", zone = "Ashenvale", x = 34.98, y = 48.46 },
          { "text", text = "Talk to |cOXP_FRIENDLY_Llana|r" },
          { "accept", quest = 95737, text = "Accept Seeking Caitlin" },
          { "target", name = "Llana" },
        },
      },
    }

Every goal is { kind, fields... }. Fields: quest, obj (objective index),
optional (the 1.x "-" before a quest id), zone, x, y, radius, points (area),
name, item, count, level, text, only, note (a "--" comment).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GROUP_RENAME = {
    "RestedXP Forever Guide (A)": "OpenXP Legacy (Alliance)",
    "RestedXP Forever Guide (H)": "OpenXP Legacy (Horde)",
}

GUIDE_RE = re.compile(r"RXPGuides\.RegisterGuide\(\[\[(.*?)\]\]\)", re.S)


class ConvertError(Exception):
    pass


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_num(v):
    if isinstance(v, int):
        return str(v)
    r = repr(v)
    return r[:-2] if r.endswith(".0") else r


def num(s, where):
    try:
        return int(s) if re.fullmatch(r"-?\d+", s) else float(s)
    except ValueError:
        raise ConvertError("not a number %r in %s" % (s, where))


def split_line(s):
    """'.cmd args >>text << Filter --note' -> (cmd, args, text, only, note)."""
    note = None
    m = re.search(r"\s--(?!-)(.*)$", s)
    if m and ">>" not in s[m.start():]:
        note = m.group(1).strip()
        s = s[: m.start()]
    only = None
    m = re.search(r"\s<<\s*(.+)$", s)
    if m:
        only = m.group(1).strip()
        s = s[: m.start()]
    text = None
    if ">>" in s:
        s, text = s.split(">>", 1)
        text = text.strip()
    parts = s.strip().split(None, 1)
    cmd = parts[0][1:] if parts and parts[0].startswith(".") else None
    args = parts[1].strip() if len(parts) > 1 else ""
    return cmd, args, text, only, note


def parse_goal(cmd, args, where):
    g = {"kind": cmd}
    if cmd in ("accept", "turnin"):
        q = args
        if q.startswith("-"):
            g["optional"] = True
            q = q[1:]
        g["quest"] = num(q, where)
    elif cmd == "complete":
        q, o = [a.strip() for a in args.split(",")]
        if q.startswith("-"):
            g["optional"] = True
            q = q[1:]
        g["quest"] = num(q, where)
        g["obj"] = num(o, where)
    elif cmd == "goto":
        p = [a.strip() for a in args.split(",")]
        g["zone"] = p[0]
        g["x"], g["y"] = num(p[1], where), num(p[2], where)
        if len(p) > 3:
            g["radius"] = num(p[3], where)
        if len(p) > 4:
            raise ConvertError(".goto with %d parts in %s" % (len(p), where))
    elif cmd == "area":
        p = [a.strip() for a in args.split(",")]
        g["zone"] = p[0]
        g["points"] = [num(v, where) for v in p[1:]]
        if len(g["points"]) % 2:
            raise ConvertError(".area with odd coordinates in %s" % where)
    elif cmd == "collect":
        i, c = [a.strip() for a in args.split(",")]
        g["item"], g["count"] = num(i, where), num(c, where)
    elif cmd == "xp":
        g["level"] = num(args, where)
    elif cmd in ("target", "mob", "zone", "fp"):
        g["name"] = args
    elif cmd == "home":
        if args:
            g["name"] = args
    else:
        raise ConvertError("unknown command .%s in %s" % (cmd, where))
    return g


def parse_guide(body, where):
    guide = {"tags": [], "steps": []}
    step = None
    for n, raw in enumerate(body.splitlines(), 1):
        s = raw.strip()
        here = "%s line %d" % (where, n)
        if not s:
            continue
        if s == "step" or s.startswith("step "):
            step = {"goals": []}
            rest = s[4:].strip()
            if rest:
                if not rest.startswith("<<"):
                    raise ConvertError("odd step line %r in %s" % (s, here))
                step["only"] = rest[2:].strip()
            guide["steps"].append(step)
            continue
        if step is None:
            if s.startswith("<<"):
                guide["only"] = s[2:].strip()
            elif s.startswith("#"):
                key, _, val = s[1:].partition(" ")
                val = val.strip()
                if key in ("group", "subgroup", "name", "next"):
                    guide[key] = val
                elif key == "version":
                    guide["version"] = num(val, here)
                elif not val:
                    guide["tags"].append(key)
                else:
                    raise ConvertError("unknown header #%s in %s" % (key, here))
            else:
                raise ConvertError("odd header line %r in %s" % (s, here))
            continue
        if s == "--oxp-class":
            step["class"] = True
        elif s.startswith("#completewith"):
            step["completewith"] = s.split(None, 1)[1]
        elif s.startswith(">>"):
            step["goals"].append({"kind": "text", "text": s[2:].strip()})
        elif s.startswith("."):
            cmd, args, text, only, note = split_line(s)
            g = parse_goal(cmd, args, here)
            for k, v in (("text", text), ("only", only), ("note", note)):
                if v is not None:
                    g[k] = v
            step["goals"].append(g)
        else:
            raise ConvertError("odd step line %r in %s" % (s, here))
    if "group" in guide:
        guide["oldGroup"] = guide["group"]
        guide["group"] = GROUP_RENAME.get(guide["group"], guide["group"])
    return guide


FIELD_ORDER = ["quest", "obj", "optional", "zone", "x", "y", "radius", "points",
               "name", "item", "count", "level", "text", "only", "note"]


def render_goal(g):
    parts = [lua_str(g["kind"])]
    for k in FIELD_ORDER:
        if k not in g:
            continue
        v = g[k]
        if isinstance(v, bool):
            parts.append("%s = true" % k)
        elif isinstance(v, list):
            parts.append("%s = { %s }" % (k, ", ".join(lua_num(x) for x in v)))
        elif isinstance(v, str):
            # 1.x colour tags name RestedXP; 2.0 uses its own.
            parts.append("%s = %s" % (k, lua_str(v.replace("|cRXP_", "|cOXP_"))))
        else:
            parts.append("%s = %s" % (k, lua_num(v)))
    return "{ " + ", ".join(parts) + " }"


def render_value(v):
    """Any JSON-like value as a Lua literal (inserted class steps)."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return lua_num(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{ " + ", ".join(render_value(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join("%s = %s" % (k if re.match(r"^[A-Za-z_]\w*$", k) and k != "until" else "[%s]" % lua_str(k),
                                             render_value(v[k])) for k in sorted(v)) + " }"
    raise ConvertError("can't write %r" % (v,))


def render_inserted_goal(goal):
    kind, fields = goal
    parts = [lua_str(kind)]
    for k in sorted(fields):
        parts.append("%s = %s" % (k, render_value(fields[k])))
    return "{ " + ", ".join(parts) + " }"


# Class quest steps added to the 21-60 guides (tools/import_polestar.py
# writes this file): { faction: [ {guide, at, source, steps}, ... ] }. The
# shared steps never change; tests/convert_roundtrip.py checks that, and that
# every added step is for one class only.
INSERTS = os.path.join(ROOT, "tools", "class_inserts.json")


def load_inserts():
    if not os.path.exists(INSERTS):
        return {}
    import json
    return json.load(open(INSERTS, encoding="utf-8"))


def apply_inserts(guides, faction, inserts):
    by_guide = {}
    for ins in inserts.get(faction or "", []):
        by_guide.setdefault(ins["guide"], []).append(ins)
    for g in guides:
        blocks = sorted(by_guide.get(g.get("name"), []), key=lambda b: b["at"])
        if not blocks:
            continue
        out, k = [], 0
        source = g["steps"]
        for i in range(len(source) + 1):
            while k < len(blocks) and min(blocks[k]["at"], len(source)) == i:
                start = len(out) + 1
                for s in blocks[k]["steps"]:
                    st = dict(s)
                    st["inserted"] = True
                    st["source"] = blocks[k]["source"]
                    if "until_rel" in st:
                        st["until"] = start + st.pop("until_rel") - 1
                    out.append(st)
                k += 1
            if i < len(source):
                out.append(source[i])
        g["steps"] = out


def render_guide(g):
    out = ["  {"]
    for k in ("name", "group", "oldGroup", "subgroup", "next", "version", "only"):
        if k in g:
            v = g[k]
            out.append("    %s = %s," % (k, lua_num(v) if isinstance(v, (int, float)) else lua_str(v)))
    out.append("    tags = { %s }," % ", ".join(lua_str(t) for t in g["tags"]))
    out.append("    steps = {")
    for st in g["steps"]:
        if st.get("inserted"):
            head = ["only = %s" % lua_str(st["only"]), "source = %s" % lua_str(st["source"])]
            for k in ("along", "until"):
                if k in st:
                    head.append("%s = %s" % ('["until"]' if k == "until" else k, render_value(st[k])))
            if st.get("when"):
                head.append("when = { %s }" % ", ".join(render_inserted_goal(c) for c in st["when"]))
            out.append("      { " + ", ".join(head) + ",")
            for goal in st["goals"]:
                out.append("        " + render_inserted_goal(goal) + ",")
            out.append("      },")
            continue
        head = []
        if "only" in st:
            head.append("only = %s" % lua_str(st["only"]))
        if st.get("class"):
            head.append("class = true")
        if "completewith" in st:
            head.append("completewith = %s" % lua_str(st["completewith"]))
        out.append("      {" + (" " + ", ".join(head) + "," if head else ""))
        for goal in st["goals"]:
            out.append("        " + render_goal(goal) + ",")
        out.append("      },")
    out.append("    },")
    out.append("  },")
    return "\n".join(out)


def faction_of(text):
    if re.search(r'if faction == "Horde" then return end|if faction ~= "Alliance" then return end', text):
        return "Alliance"
    if re.search(r'if faction == "Alliance" then return end|if faction ~= "Horde" then return end', text):
        return "Horde"
    return None


def convert_file(path):
    text = open(path, encoding="utf-8").read()
    name = os.path.basename(path)
    bodies = GUIDE_RE.findall(text)
    if not bodies:
        raise ConvertError("no guides in %s" % name)
    guides = [parse_guide(b, "%s guide %d" % (name, i + 1)) for i, b in enumerate(bodies)]
    faction = faction_of(text)
    inserts = load_inserts()
    apply_inserts(guides, faction, inserts)
    out = [
        "-- OpenXP 2.0 guide data. Generated by tools/convert_guides.py from the",
        "-- 1.x file %s; edit the source or the generator, not this file." % name,
    ]
    if any(st.get("inserted") for g in guides for st in g["steps"]):
        out += [
            "-- Steps with a `source` are class quest steps adapted from PoleStar",
            "-- (https://github.com/fitzforge/polestar, commit %s, GPL-3.0)," % inserts.get("commit", "?"),
            "-- added by tools/import_polestar.py; see NOTICE.md.",
        ]
    out += [
        "local _, OXP = ...",
        "OXP.AddGuides({",
        "  file = %s," % lua_str(os.path.splitext(name)[0]),
    ]
    if faction:
        out.append("  faction = %s," % lua_str(faction))
    out += [render_guide(g) for g in guides]
    out.append("})")
    return "\n".join(out) + "\n", guides


GUIDES_DIR = os.path.join(ROOT, "OpenXP", "Guides")


def out_path(source_name, out_dir=GUIDES_DIR):
    """Where a 1.x file's 2.0 data goes, relative to the addon's Guides folder:
    Alliance-21-30.lua -> Leveling/Alliance/21-30.lua,
    Dungeons-Horde.lua -> Dungeons/Horde.lua."""
    stem = os.path.splitext(os.path.basename(source_name))[0]
    head, _, rest = stem.partition("-")
    if not rest:
        return os.path.join(out_dir, stem + ".lua")
    if head in ("Alliance", "Horde"):
        return os.path.join(out_dir, "Leveling", head, rest + ".lua")
    return os.path.join(out_dir, head, rest + ".lua")


def guide_list_xml(out_dir=GUIDES_DIR):
    """Guides.xml: every guide data file under out_dir, leveling first."""
    files = []
    for base, _, names in os.walk(out_dir):
        for n in names:
            if n.endswith(".lua"):
                files.append(os.path.relpath(os.path.join(base, n), out_dir).replace(os.sep, "\\"))
    files.sort(key=lambda f: (not f.startswith("Leveling"), f.lower()))
    lines = ['<Ui xmlns="http://www.blizzard.com/wow/ui/">',
             "  <!-- Generated by tools/convert_guides.py. -->"]
    lines += ['  <Script file="%s"/>' % f for f in files]
    lines.append("</Ui>")
    return "\n".join(lines) + "\n"


def main(argv):
    out_dir = GUIDES_DIR
    files = []
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out_dir = argv[i + 1]
            i += 2
            continue
        files.append(argv[i])
        i += 1
    if not files:
        src = os.path.join(ROOT, "Guides", "openxp")
        files = sorted(os.path.join(src, f) for f in os.listdir(src) if f.endswith(".lua"))
    total = 0
    for f in files:
        lua, guides = convert_file(f)
        dest = out_path(f, out_dir)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(lua)
        steps = sum(len(g["steps"]) for g in guides)
        total += steps
        print("%-32s -> %-28s %3d guides %5d steps" % (
            os.path.basename(f), os.path.relpath(dest, out_dir), len(guides), steps))
    with open(os.path.join(out_dir, "Guides.xml"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(guide_list_xml(out_dir))
    print("converted %d files, %d steps -> %s" % (len(files), total, os.path.relpath(out_dir, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
