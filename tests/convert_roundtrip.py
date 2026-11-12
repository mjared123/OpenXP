"""OpenXP 2.0 guide conversion check.

Converts every 1.x guide file (Guides/openxp/*.lua, plus any files given on
the command line), loads the 2.0 output in Lua the way the game would, writes
it back out as 1.x guide text and checks that it matches the source line for
line. A pass means the 2.0 data holds every guide, step, goal, coordinate,
filter and note of the source, in the same order, so the route is unchanged.

Needs `pip install lupa`.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import convert_guides as C  # noqa: E402

try:
    from lupa import luajit21 as lupa_mod
except ImportError:
    import lupa as lupa_mod


def norm(line):
    s = line.strip()
    s = re.sub(r"\s+", " ", s)
    s = s.replace(">> ", ">>").replace(" >>", " >>")
    return s


def source_lines(path):
    text = open(path, encoding="utf-8").read()
    out = []
    for body in C.GUIDE_RE.findall(text):
        out.append("<guide>")
        out += [norm(l) for l in body.splitlines() if l.strip()]
    return out


def num(v):
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)]


CLASSES = {"warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"}
INSERTED = [0]


def class_only(only):
    """Every choice of the filter names a class (so no other class sees it)."""
    if not only:
        return False
    return all(any(w.lower() in CLASSES for w in choice.split()) for choice in only.split("/"))


def back_to_text(lua_guides):
    """2.0 tables -> 1.x lines, using only what the Lua side holds."""
    out = []
    for g in lua_list(lua_guides):
        out.append("<guide>")
        if g["only"]:
            out.append("<< " + g["only"])
        for t in lua_list(g["tags"]):
            if t == "forever":
                out.append("#forever")
        if g["version"] is not None:
            out.append("#version %s" % num(g["version"]))
        for t in lua_list(g["tags"]):
            if t != "forever":
                out.append("#" + t)
        out.append("#group " + g["oldGroup"])
        out.append("#subgroup " + g["subgroup"])
        out.append("#name " + g["name"])
        if g["next"]:
            out.append("#next " + g["next"])
        for st in lua_list(g["steps"]):
            if st["source"]:
                # a class quest step added by tools/import_polestar.py: not in
                # the 1.x source, and it must be for one class only
                if not class_only(st["only"]):
                    raise ValueError("added step from %s is not class-only: %r" % (st["source"], st["only"]))
                INSERTED[0] += 1
                continue
            out.append("step" + (" << " + st["only"] if st["only"] else ""))
            if st["class"]:
                out.append("--oxp-class")
            if st["completewith"]:
                out.append("#completewith " + st["completewith"])
            for goal in lua_list(st):
                kind = goal[1]
                if kind == "text":
                    out.append(">>" + goal["text"].replace("|cOXP_", "|cRXP_"))
                    continue
                opt = "-" if goal["optional"] else ""
                if kind in ("accept", "turnin"):
                    args = opt + num(goal["quest"])
                elif kind == "complete":
                    args = "%s%s,%s" % (opt, num(goal["quest"]), num(goal["obj"]))
                elif kind == "goto":
                    args = "%s,%s,%s" % (goal["zone"], num(goal["x"]), num(goal["y"]))
                    if goal["radius"] is not None:
                        args += "," + num(goal["radius"])
                elif kind == "area":
                    args = ",".join([goal["zone"]] + [num(v) for v in lua_list(goal["points"])])
                elif kind == "collect":
                    args = "%s,%s" % (num(goal["item"]), num(goal["count"]))
                elif kind == "xp":
                    args = num(goal["level"])
                else:
                    args = goal["name"] or ""
                s = "." + kind + (" " + args if args else "")
                if goal["text"] is not None:
                    s += " >>" + goal["text"].replace("|cOXP_", "|cRXP_")
                if goal["only"]:
                    s += " << " + goal["only"]
                if goal["note"]:
                    s += " --" + goal["note"]
                out.append(norm(s))
    return out


def coord_text(line):
    # 34.40 and 34.4 are the same number: compare goto/area coordinates by value.
    m = re.match(r"^(\.(?:goto|area) )([^,]+)((?:,[-\d.]+)+)(.*)$", line)
    if not m:
        return line
    nums = ",".join(num(float(v)) if "." in v else v for v in m.group(3)[1:].split(","))
    return m.group(1) + m.group(2) + "," + nums + m.group(4)


def header_sorted(lines):
    """Header lines (before a guide's first step) may come in any order."""
    out, head, in_head = [], [], False
    for l in lines:
        if l == "<guide>" or l.startswith("step"):
            out += sorted(head)
            head = []
            in_head = l == "<guide>"
            out.append(l)
        elif in_head:
            head.append(l)
        else:
            out.append(l)
    return out + sorted(head)


def check(path):
    lua_src, guides = C.convert_file(path)
    rt = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    loaded = []
    rt.globals().OXP_capture = lambda t: loaded.append(t)
    chunk = rt.execute("return function(src) return loadstring(src) end")(lua_src)
    if chunk is None:
        return ["output is not valid Lua"]
    rt.execute("OXP = { AddGuides = function(t) OXP_capture(t) end }")
    chunk("OpenXP", rt.globals().OXP)
    if len(loaded) != 1:
        return ["AddGuides called %d times" % len(loaded)]
    data = loaded[0]
    want = header_sorted([coord_text(l) for l in source_lines(path)])
    got = header_sorted([coord_text(l) for l in back_to_text(data)])
    errs = []
    for i, (a, b) in enumerate(zip(want, got)):
        if a != b:
            errs.append("line %d differs:\n      source: %s\n      2.0:    %s" % (i + 1, a, b))
            if len(errs) >= 5:
                break
    if len(want) != len(got) and not errs:
        errs.append("source has %d lines, 2.0 gives back %d" % (len(want), len(got)))
    steps = sum(1 for l in want if l.startswith("step"))
    return errs, steps, len(lua_list(data))


def main(argv):
    src = os.path.join(ROOT, "Guides", "openxp")
    files = sorted(os.path.join(src, f) for f in os.listdir(src) if f.endswith(".lua")) + argv
    failures = 0
    for f in files:
        res = check(f)
        if isinstance(res, list):
            errs, steps, n = res, 0, 0
        else:
            errs, steps, n = res
        name = os.path.basename(f)
        committed = C.out_path(f)
        if f.startswith(src) and (not os.path.exists(committed)
                                  or open(committed, encoding="utf-8").read() != C.convert_file(f)[0]):
            errs = errs + ["%s is out of date: run python3 tools/convert_guides.py"
                           % os.path.relpath(committed, ROOT)]
        if errs:
            failures += 1
            print("FAIL %s" % name)
            for e in errs:
                print("    " + e)
        else:
            print("ok   %s: %d guides, %d steps unchanged in 2.0 data" % (name, n, steps))
    if INSERTED[0]:
        print("ok   %d class quest steps added, all class-only" % INSERTED[0])
    xml = os.path.join(C.GUIDES_DIR, "Guides.xml")
    if not os.path.exists(xml) or open(xml, encoding="utf-8").read() != C.guide_list_xml():
        failures += 1
        print("FAIL OpenXP/Guides/Guides.xml is out of date: run python3 tools/convert_guides.py")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
