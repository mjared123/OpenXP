#!/usr/bin/env python3
"""Build the release zip for WoW Forever and Classic Era.

Copies the committed tree (git archive), drops dev files and everything that
only loads on other game versions (Retail, TBC, Wrath, Cata, MoP, SoD), checks
that every file the Forever/Classic load path references is still there, and
zips it.

    python3 tools/package.py [out.zip | out-dir] [git-ref]

With no name (or a folder), the zip is called OpenXP-<version>.zip, using the
## Version line from OpenXP.toc (for example OpenXP-1.1.5-beta.zip). The build
stops if the .toc version and the newest WelcomeFrame.lua changelog entry
don't match, so a release can't ship with the wrong number.
"""
import os, re, shutil, subprocess, sys, tempfile, zipfile

KEEP_TYPES = {"vanilla", "camelot"}
DROP = [
    "tests", "tools", "Scripts", ".github", ".vscode", ".editorconfig", ".gitignore", ".gitattributes", ".pkgmeta",
    "Textures/OpenXP-source", "OpenXP_TBC.toc",
    "Guides/Retail", "Guides/tbc", "Guides/cata", "Guides/mop", "Guides/SoD",
    "Guides/SurvivalGuide", "Guides/Dailies", "Guides/GuideList.xml",
    "Guides/GuideList-mainline.xml", "Guides/GuideList-cata.xml",
    "Guides/GuideList-mop.xml", "Guides/GuideList-tbc.xml",
    "Guides/Talents/cata.xml", "Guides/Talents/tbc.xml",
    "DB/mainline", "DB/mainline.xml", "DB/mop", "DB/mop.xml", "DB/cata", "DB/cata.xml",
    "DB/wotlk", "DB/wotlk.xml", "DB/tbc", "DB/tbc.xml",
]


def loads_here(line):
    m = re.search(r"\[AllowLoadGameType ([^\]]+)\]", line)
    if not m:
        return True
    return bool(KEEP_TYPES & {t.strip() for t in m.group(1).split(",")})


def exists(path):
    """Case-insensitive, like the Windows and Mac clients."""
    if os.path.exists(path):
        return True
    parent, name = os.path.split(path)
    if not parent or not exists(parent):
        return False
    real = _real(parent)
    return any(n.lower() == name.lower() for n in os.listdir(real))


def _real(path):
    if os.path.exists(path):
        return path
    parent, name = os.path.split(path)
    real = _real(parent)
    for n in os.listdir(real):
        if n.lower() == name.lower():
            return os.path.join(real, n)
    return path


def exact_case(path, root):
    """False when the path only exists with different upper/lower case
    (Windows doesn't care, case-sensitive Mac and Linux disks do)."""
    cur = root
    for part in os.path.relpath(path, root).split(os.sep):
        if part in ("", "."):
            continue
        if part not in os.listdir(cur):
            return False
        cur = os.path.join(cur, part)
    return True


def check(root):
    missing, seen = [], set()

    def visit(path):
        path = os.path.normpath(path)
        if path in seen:
            return
        seen.add(path)
        if not exists(path):
            missing.append(os.path.relpath(path, root))
            return
        if not exact_case(path, root):
            missing.append("%s  (wrong upper/lower case, the file is %s)"
                           % (os.path.relpath(path, root), os.path.relpath(_real(path), root)))
        path = _real(path)
        if path.endswith(".xml"):
            text = open(path, encoding="utf-8", errors="replace").read()
            text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
            for ref in re.findall(r'<(?:Script|Include)\s+file="([^"]+)"', text):
                ref = ref.replace("\\", "/")
                base = os.path.dirname(path)
                cand = os.path.join(base, ref)
                if not exists(cand) and exists(os.path.join(root, ref)):
                    cand = os.path.join(root, ref)
                visit(cand)

    for toc in ("OpenXP.toc", "OpenXP_Vanilla.toc"):
        tp = os.path.join(root, toc)
        if not os.path.exists(tp):
            continue
        for line in open(tp, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or not loads_here(line):
                continue
            visit(os.path.join(root, line.split(" [")[0].replace("\\", "/")))
    return missing, {os.path.normcase(p).lower() for p in seen}


def drop_unloaded(root, seen):
    """Guide and DB scripts no Forever/Classic list loads are dead weight."""
    dropped = 0
    for sub in ("Guides", "DB"):
        for dp, _, files in os.walk(os.path.join(root, sub)):
            for fn in files:
                full = os.path.join(dp, fn)
                if fn.endswith(".lua") and os.path.normpath(full).lower() not in seen:
                    os.remove(full)
                    dropped += 1
    return dropped


def check_version(root):
    """Return the .toc version; exit if the .toc files or changelog disagree."""
    versions = set()
    for toc in ("OpenXP.toc", "OpenXP_Vanilla.toc"):
        tp = os.path.join(root, toc)
        if os.path.exists(tp):
            m = re.search(r"^## Version:\s*(\S+)", open(tp, encoding="utf-8").read(), re.M)
            if m:
                versions.add(m.group(1))
    if len(versions) != 1:
        sys.exit("the .toc files disagree on ## Version: %s" % sorted(versions))
    version = versions.pop()
    wf = os.path.join(root, "WelcomeFrame.lua")
    if os.path.exists(wf):
        m = re.search(r'version\s*=\s*"([^"]+)"', open(wf, encoding="utf-8").read())
        if m and m.group(1) != version:
            sys.exit("OpenXP.toc says %s but the newest WelcomeFrame.lua changelog entry is %s"
                     % (version, m.group(1)))
    return version


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "."
    ref = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tmp = tempfile.mkdtemp()
    root = os.path.join(tmp, "OpenXP")
    os.makedirs(root)
    tar = subprocess.run(["git", "-C", repo, "archive", ref], check=True, capture_output=True).stdout
    # Python's tarfile instead of the tar command, which on Windows tries to
    # read a tape drive when given no -f.
    import io, tarfile
    with tarfile.open(fileobj=io.BytesIO(tar)) as t:
        t.extractall(root)
    version = check_version(root)
    out = os.path.abspath(arg)
    if os.path.isdir(out):
        out = os.path.join(out, "OpenXP-%s.zip" % version)
    for d in DROP:
        p = os.path.join(root, d)
        if os.path.isdir(p):
            shutil.rmtree(p)
        elif os.path.exists(p):
            os.remove(p)
    missing, seen = check(root)
    if not missing:
        print("dropped", drop_unloaded(root, seen), "unused guide/DB scripts")
        missing, seen = check(root)
    if missing:
        print("missing files on the Forever/Classic load path:")
        for m in missing:
            print("  ", m)
        sys.exit(1)
    if os.path.exists(out):
        os.remove(out)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for dp, _, files in os.walk(root):
            for fn in sorted(files):
                full = os.path.join(dp, fn)
                z.write(full, os.path.relpath(full, tmp))
    shutil.rmtree(tmp)
    print("wrote", out, os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    main()
