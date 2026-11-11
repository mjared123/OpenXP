"""The shared 21-60 route is frozen (players follow it live). This checks
that, with the class steps (--oxp-class) taken out, every route file is
byte for byte what it was when it was frozen. To change the shared route on
purpose (only with Matt's OK), update the hashes: python3 tests/route_frozen.py --update
"""
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
HASHES = os.path.join(ROOT, "tests", "route_frozen.json")


def shared_hashes():
    import class_steps as C
    out = {}
    for faction in ("Alliance", "Horde"):
        files, sections = C.load_sections(faction)
        for s in sections:
            s.inserts = {}
        for path, parts in files.items():
            text = "".join(x.render() if isinstance(x, C.Section) else x for x in parts)
            out[os.path.basename(path)] = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return out


def main():
    now = shared_hashes()
    if "--update" in sys.argv:
        json.dump(now, open(HASHES, "w"), indent=1, sort_keys=True)
        print("route hashes updated")
        return 0
    want = json.load(open(HASHES))
    bad = [k for k in sorted(set(want) | set(now)) if want.get(k) != now.get(k)]
    for k in bad:
        print("FAIL route changed: %s (shared steps differ from the frozen route)" % k)
    if not bad:
        print("ok   shared 21-60 route unchanged (%d files)" % len(now))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
