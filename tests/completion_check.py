"""Checks the zone completion guides (Guides/openxp/Completion-*.lua):
every guide has its header, names are unique, every #next points at a
guide that exists, every step does something, and no quest is picked up
twice in one guide."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    bad = 0
    for faction in ("Alliance", "Horde"):
        path = os.path.join(ROOT, "Guides", "openxp", "Completion-%s.lua" % faction)
        text = open(path, encoding="utf-8").read()
        blocks = re.findall(r"RegisterGuide\(\[\[(.*?)\]\]\)", text, re.S)
        names = [re.search(r"#name (.+)", b).group(1) for b in blocks]
        if len(set(names)) != len(names):
            print("FAIL %s: duplicate guide names" % faction)
            bad += 1
        for b, name in zip(blocks, names):
            for head in ("#forever", "#group OpenXP Zone Completion", "<< " + faction):
                if head not in b:
                    print("FAIL %s %s: missing %s" % (faction, name, head))
                    bad += 1
            for n in re.findall(r"#next (.+)", b):
                if n.split(" << ")[0] not in names:
                    print("FAIL %s %s: #next %s doesn't exist" % (faction, name, n))
                    bad += 1
            steps = b.split("\nstep")[1:]
            for s in steps:
                if not re.search(r"\n\s+(\.|>>)", s):
                    print("FAIL %s %s: empty step" % (faction, name))
                    bad += 1
                    break
            acc = re.findall(r"\.accept (\d+)", b)
            dup = {q for q in acc if acc.count(q) > 1}
            if dup:
                print("FAIL %s %s: quests picked up twice: %s" % (faction, name, sorted(dup)))
                bad += 1
        print("ok   %s zone completion guides: %d guides" % (faction, len(blocks)) if not bad else "")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
