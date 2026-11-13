#!/usr/bin/env python3
"""Turn a Polestar release zip into the OpenXP addon folders.

OpenXP 2.0 is a fork of Polestar (https://github.com/fitzforge/polestar,
GPL-3.0 with a guide-pack exception). This script does the whole rename in
one pass, so a newer Polestar release can be taken again the same way:

    python3 tools/fork_polestar.py Polestar-0.3.7.2.zip addons

What it changes:
- folder names: Polestar -> OpenXP, Polestar_X -> OpenXP_X
- in .lua/.xml/.toc: Polestar/POLESTAR/polestar -> OpenXP/OPENXP/openxp,
  /pole -> /oxp, the issue/release/repository links -> OpenXP's
- the logo, wordmark and watermark textures -> OpenXP's (tools/fork_art)
- the version in every .toc -> VERSION below
- OpenXP 1.x's saved variables are listed in OpenXP.toc, so they are kept

What it keeps as it is (GPL section 5 and the credits Polestar carries):
- LICENSE, LICENSE-EXCEPTION, CREDITS, LICENSE-DATA and every other
  .md/.txt file
- any line that says "Copyright", and comment lines crediting Shortest Path
  Forever or Leffe's navigation maps

It also writes NOTICE.md into the OpenXP folder, saying where the code comes
from and that it was changed (GPL-3.0 section 5a).
"""
import datetime
import os
import re
import shutil
import sys
import zipfile

VERSION = "2.0.0-dev"
REPO = "https://github.com/mjared123/OpenXP"
CURSEFORGE = "https://www.curseforge.com/projects/1792509"
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fork_art")

TEXT = (".lua", ".xml", ".toc")

OLD_VARS = ["OXPData", "OXPDB", "OXPSettings", "OXPString", "OXPQuestieDump"]
OLD_CHAR_VARS = ["OXPCData", "OXPCTrackingData", "OXPCComms", "OXPCSettings"]

URLS = [
    ("https://github.com/fitzforge/polestar/issues/new", REPO + "/issues/new"),
    ("https://github.com/fitzforge/polestar/releases", REPO + "/releases"),
    ('ns.RepoURL = "https://github.com/fitzforge/polestar"', 'ns.RepoURL = "%s"' % REPO),
    ("https://discord.gg/polestar", CURSEFORGE),
]

KEEP_LINE = re.compile(r"Copyright|^\s*--.*(Shortest Path Forever|Leffe)")


def rename(text, binary=False):
    for a, b in URLS:
        text = text.replace(a, b)
    out = []
    for line in text.split("\n"):
        # The walking maps hold packed binary strings: leave those lines alone.
        if KEEP_LINE.search(line) or (binary and not line.isascii()):
            out.append(line)
            continue
        line = line.replace("POLESTAR", "OPENXP").replace("Polestar", "OpenXP").replace("polestar", "openxp")
        line = re.sub(r"/pole\b", "/oxp", line)
        out.append(line)
    return "\n".join(out)


def folder_name(name):
    return "OpenXP" + name[len("Polestar"):] if name.startswith("Polestar") else name


NOTICE = """# OpenXP and Polestar

OpenXP 2.0 is a modified version of Polestar, a leveling guide addon for
World of Warcraft: Forever: https://github.com/fitzforge/polestar

- Taken from: Polestar release %(src)s
- Changed on: %(date)s, by OpenXP (%(repo)s)
- What changed: the addon is renamed to OpenXP (folders, names, slash
  commands, saved variables), its links point to OpenXP, and its logo art is
  OpenXP's. tools/fork_polestar.py in OpenXP's repository makes every change.

Polestar is licensed under the GNU General Public License version 3 with the
additional permission in LICENSE-EXCEPTION.md; OpenXP 2.0 is under the same
terms. Polestar's copyright notices, CREDITS and LICENSE-DATA files are kept
as they were.

Credit and thanks to:
- Polestar and everyone in its credits (the Guiding Stars page in game).
- Shortest Path Forever by Cillian Berragan, where the arrow's walking
  router started (GPL-3.0-or-later).
- Leffe, for Leffe's navigation maps, which the walking lines are drawn on.
- Questie and QuestieDB (the Questie team): quest facts in the guides and
  quest data.
- pfQuest (Shagu, MIT), CMaNGOS classic-db, VMaNGOS, ForeverTDB, EG Link
  (Efficient Games, CC BY 4.0), Ding! and DingDB (Yendi), and the other
  sources Polestar lists in its THIRD_PARTY.md.
"""


def main(src_zip, out_dir):
    src = os.path.basename(src_zip)
    tmp = out_dir + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    with zipfile.ZipFile(src_zip) as z:
        z.extractall(tmp)
    root = tmp
    entries = os.listdir(root)
    if len(entries) == 1 and not entries[0].startswith("Polestar"):
        root = os.path.join(root, entries[0])
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    changed = 0
    for name in sorted(os.listdir(root)):
        dst = os.path.join(out_dir, folder_name(name))
        shutil.copytree(os.path.join(root, name), dst)
        for dirpath, _, files in os.walk(dst):
            for f in files:
                p = os.path.join(dirpath, f)
                if f.endswith(".toc") and f.startswith("Polestar"):
                    newp = os.path.join(dirpath, folder_name(f))
                    os.rename(p, newp)
                    p = newp
                if not p.endswith(TEXT):
                    continue
                with open(p, "rb") as fh:
                    raw = fh.read()
                try:
                    text, enc, binary = raw.decode("utf-8"), "utf-8", False
                except UnicodeDecodeError:
                    text, enc, binary = raw.decode("latin-1"), "latin-1", True
                new = rename(text, binary)
                if p.endswith(".toc"):
                    new = re.sub(r"(?m)^## Version: .*$", "## Version: " + VERSION, new)
                    new = re.sub(r"(?m)^## X-Website: .*$", "## X-Website: " + REPO, new)
                if new != text:
                    changed += 1
                    with open(p, "wb") as fh:
                        fh.write(new.encode(enc))
    shutil.rmtree(tmp)
    media = os.path.join(out_dir, "OpenXP", "Media", "UI")
    for f in os.listdir(ART):
        if f.endswith(".tga"):
            shutil.copy(os.path.join(ART, f), os.path.join(media, f))
        elif f.endswith(".md"):
            # Polestar's licence exception and its full credits list
            shutil.copy(os.path.join(ART, f), os.path.join(out_dir, "OpenXP", f))
    # Keep OpenXP 1.x's saved variables in the file, so going back to 1.x
    # after trying 2.0 loses nothing (the game drops undeclared ones).
    toc = os.path.join(out_dir, "OpenXP", "OpenXP.toc")
    with open(toc, encoding="utf-8") as fh:
        t = fh.read()
    t = t.replace("## SavedVariables: OpenXPDB\n", "## SavedVariables: OpenXPDB, " + ", ".join(OLD_VARS) + "\n")
    t = t.replace("## SavedVariablesPerCharacter: OpenXPCharDB\n",
                  "## SavedVariablesPerCharacter: OpenXPCharDB, " + ", ".join(OLD_CHAR_VARS) + "\n")
    with open(toc, "w", encoding="utf-8") as fh:
        fh.write(t)
    with open(os.path.join(out_dir, "OpenXP", "NOTICE.md"), "w") as fh:
        fh.write(NOTICE % {"src": src, "date": datetime.date.today().isoformat(), "repo": REPO})
    left = []
    for dirpath, _, files in os.walk(out_dir):
        for f in files:
            if f.endswith(TEXT):
                with open(os.path.join(dirpath, f), encoding="latin-1") as fh:
                    for i, line in enumerate(fh, 1):
                        if line.isascii() and re.search("polestar", line, re.I) and not KEEP_LINE.search(line):
                            left.append("%s:%d" % (os.path.join(dirpath, f), i))
    print("%d files changed; %d lines still say Polestar" % (changed, len(left)))
    for x in left[:20]:
        print("  " + x)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
