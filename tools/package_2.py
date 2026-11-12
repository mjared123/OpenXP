#!/usr/bin/env python3
"""Build the OpenXP 2.0 test zip from the OpenXP/ folder.

    python3 tools/package_2.py [out.zip]

The zip holds one folder, OpenXP/, exactly what goes in
World of Warcraft/_forever_/Interface/AddOns. Before zipping it checks that
every file the .toc and .xml files list exists with exactly that upper and
lower case (Windows doesn't care, Mac and Linux disks do), and that no file
in the folder is left unlisted by mistake (Lua files only).
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "OpenXP")


def exact(path):
    cur = ADDON
    for part in os.path.relpath(path, ADDON).split(os.sep):
        if part not in os.listdir(cur):
            return False
        cur = os.path.join(cur, part)
    return True


def listed():
    """Every file the .toc loads, following .xml includes."""
    out, missing = [], []

    def visit(path):
        if not os.path.exists(path) or not exact(path):
            missing.append(os.path.relpath(path, ADDON))
            return
        out.append(path)
        if path.lower().endswith(".xml"):
            text = open(path, encoding="utf-8").read()
            for f in re.findall(r'<(?:Script|Include)\s+file="([^"]+)"', text):
                visit(os.path.join(os.path.dirname(path), *f.split("\\")))

    toc = os.path.join(ADDON, "OpenXP.toc")
    out.append(toc)
    for line in open(toc, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            visit(os.path.join(ADDON, *line.split("\\")))
    return out, missing


def main(argv):
    toc = open(os.path.join(ADDON, "OpenXP.toc"), encoding="utf-8").read()
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    out = argv[0] if argv else os.path.join(ROOT, "dist", "OpenXP-%s.zip" % version)
    files, missing = listed()
    if missing:
        print("missing (or wrong case): " + ", ".join(missing))
        return 1
    loaded = {os.path.normcase(f) for f in files}
    stray = []
    for base, _, names in os.walk(ADDON):
        for n in names:
            p = os.path.join(base, n)
            if n.endswith(".lua") and os.path.normcase(p) not in loaded:
                stray.append(os.path.relpath(p, ADDON))
    if stray:
        print("Lua files the .toc never loads: " + ", ".join(stray))
        return 1
    os.makedirs(os.path.dirname(out), exist_ok=True)
    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, names in os.walk(ADDON):
            for name in sorted(names):
                p = os.path.join(base, name)
                z.write(p, os.path.join("OpenXP", os.path.relpath(p, ADDON)))
                n += 1
    print("%s: %d files, version %s" % (os.path.relpath(out, ROOT), n, version))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
