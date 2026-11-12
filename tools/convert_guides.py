"""Convert OpenXP's 1.x guide files (Guides/openxp/*.lua, RXP-style text inside
RegisterGuide([[...]])) into OpenXP 2.0 guide data: plain Lua tables that the
2.0 engine reads, with no text to parse in game.

    python3 tools/convert_guides.py                 # every file in Guides/openxp
    python3 tools/convert_guides.py FILE... --out DIR

Each source file becomes Guides/v2/<same name>.lua. tests/convert_roundtrip.py
loads the output and checks it says exactly what the source said, step by step.

2.0 guide data (one table per guide):

    {
      name = "21-22 Ashenvale", group = "OpenXP Leveling (Alliance)",
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
    "RestedXP Forever Guide (A)": "OpenXP Leveling (Alliance)",
    "RestedXP Forever Guide (H)": "OpenXP Leveling (Horde)",
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


def render_guide(g):
    out = ["  {"]
    for k in ("name", "group", "oldGroup", "subgroup", "next", "version", "only"):
        if k in g:
            v = g[k]
            out.append("    %s = %s," % (k, lua_num(v) if isinstance(v, (int, float)) else lua_str(v)))
    out.append("    tags = { %s }," % ", ".join(lua_str(t) for t in g["tags"]))
    out.append("    steps = {")
    for st in g["steps"]:
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
    out = [
        "-- OpenXP 2.0 guide data. Generated by tools/convert_guides.py from the",
        "-- 1.x file %s; edit the source or the generator, not this file." % name,
        "local _, OXP = ...",
        "OXP.AddGuides({",
        "  file = %s," % lua_str(os.path.splitext(name)[0]),
    ]
    if faction:
        out.append("  faction = %s," % lua_str(faction))
    out += [render_guide(g) for g in guides]
    out.append("})")
    return "\n".join(out) + "\n", guides


def main(argv):
    out_dir = os.path.join(ROOT, "Guides", "v2")
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
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for f in files:
        lua, guides = convert_file(f)
        with open(os.path.join(out_dir, os.path.basename(f)), "w", encoding="utf-8") as fh:
            fh.write(lua)
        steps = sum(len(g["steps"]) for g in guides)
        total += steps
        print("%-32s %3d guides %5d steps" % (os.path.basename(f), len(guides), steps))
    print("converted %d files, %d steps -> %s" % (len(files), total, os.path.relpath(out_dir, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
