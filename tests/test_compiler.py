"""Tests for tools/compile_foreverdb.py, which builds the OpenXP_ForeverData
addon from ForeverDB's addon data files.

Run with pytest, or: python3 tests/test_compiler.py
The fixture is a cut-down copy of the shapes in ForeverDB 0.60.5's
Data/QuestClassic.lua, Data/QuestForever.lua and Data/Meta.lua.
"""
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import compile_foreverdb as C  # noqa: E402

CREDIT = ("-- Data: ForeverDB.net (https://foreverdb.net), build 1.60.1.70938. "
          "Reuse requires this credit: see NOTICE.txt (GPL-3.0 section 7(b)).")

META = CREDIT + '''
local _, ns = ...
ns.meta = {version="2026-11-15.d2e4316c",built=1794754840,build="1.60.1.70938",cap=60,site="https://foreverdb.net",addon="0.60.5"}
'''

CLASSIC = CREDIT + '''
local _, ns = ...
ns.qcQuests = {
[1063]="The Elder Crone|18|13|h|0|178|1062||0|n4049|n4046|||",
[1064]="Forsaken Aid|18|13|h|0|178|1063||0|n4046|n3419|||",
[1065]="Journey to Tarren Mill|18|13|h|0|178|1064||0|n3419|n2216|i5628:1||",
[1066]="Blood of Innocents|23|13|h|0|178|1065||0|n2216|n2216|i5620:5||",
[1067]="Return to Thunder Bluff|23|13|h|0|178|1066||0|n2216|n3419|i5588:1||",
[990]="Trek to Ashenvale|19|15|a|0|77||994 995|990|n3694|n3691|||",
[994]="Escape Through Force|20|15|a|0|77|||994|n3692|n3693|||",
[995]="Escape Through Stealth|20|15|a|0|77|||994|n3692|n3693|||",
[500]="Too High|30|28|h|0|178|||0|n10|n10|||",
[501]="Said \\"No\\"|30|20|h|0|178|||0|o77|n10|||",
[9999]="Not In Any Guide|30|20|h|0|178|1066||0|n10|n10|||",
}

ns.qcNpc = {
[1065]="Riverpaw Shaman|nr7du8",
[2216]="Apothecary Lydon|nk6g48 nk6g49",
[3419]="Apothecary Zamah|o300vl",
[10]="Said \\"Ten\\"|nr7du8",
}

ns.qcObj = {
[77]="Wanted Poster|nk6g49",
}

ns.qcExcl = {
[994]="994 995",
}
'''

FOREVER = CREDIT + '''
local _, ns = ...
ns.qfQuests = {
[1064]="Forsaken Aid|18|0|Speak with Apothecary Zamah.|n4046|n3419|4|0|0|23|",
[1065]="Journey to Tarren Mill|18|0|Bring Zamah's Note to Apothecary Lydon in Tarren Mill.|n3419|n2216|9|0|1064|22|",
[1066]="|23|0||n2216|n2216|4|0|0|23|",
[500]="Too High|30|0||||3|0|0|25|",
[501]="Said \\"No\\"|30|22||||3|0|0|25|",
[92479]="A Scribbled Letter|1|0|Read it.|n197|n197|12|1|783|1|a",
}

ns.qfPoi = {
[1065]={s="nk6g40",e="nk6g40"},
[1066]={s="nk6g48",e="nk6g48"},
}

ns.qfSeen = {
[1065]={s="o3036y",e="nk6g47",o={[1]="nk6g40 nk6g41",[2]="nk6g49"}},
}

ns.qfNpcSpots = {
[10]="nk6g41",
}

ns.qfNpcNames = {
[3419]="Zamah the Apothecary",
}
'''

GUIDE = '''
RXPGuides.RegisterGuide([[
#name 22-23 Hillsbrad/Alterac
step
    .accept 496 >>Accept Elixir of Suffering
    .turnin -1065 >>Turn in Journey to Tarren Mill
    .accept 1066 >>Accept Blood of Innocents
step
    .complete 1066,1 --Blood of Innocents
    .goto 1438/1,1067.77,10673.98
step
    .turnin 1066 >>Turn in Blood of Innocents
    .accept 1067 >>Accept Return to Thunder Bluff
    .accept 990 >>Accept Trek to Ashenvale
    .accept 500
    .accept 501
    .accept 92479
]])
'''


def make_inputs(tmp):
    src = os.path.join(tmp, "ForeverDB")
    os.makedirs(os.path.join(src, "Data"))
    for name, text in (("Meta.lua", META), ("QuestClassic.lua", CLASSIC), ("QuestForever.lua", FOREVER)):
        with open(os.path.join(src, "Data", name), "w", encoding="utf-8") as f:
            f.write(text)
    for name in ("LICENSE.txt", "COPYING.txt"):
        with open(os.path.join(src, name), "w", encoding="utf-8") as f:
            f.write(name + " text\n")
    guides = os.path.join(tmp, "Guides", "openxp")
    os.makedirs(guides)
    with open(os.path.join(guides, "Horde-22-30.lua"), "w", encoding="utf-8") as f:
        f.write(GUIDE)
    return src, os.path.join(tmp, "Guides")


def build(tmp):
    src, guides = make_inputs(tmp)
    out = os.path.join(tmp, "out")
    C.main(["--foreverdb", src, "--guides", guides, "--out", out])
    return os.path.join(out, "OpenXP_ForeverData")


def compiled(tmp):
    src, guides = make_inputs(tmp)
    return C.compile_quests(C.load_foreverdb(src), C.guide_quest_ids(guides))


def test_guide_quest_ids():
    with tempfile.TemporaryDirectory() as tmp:
        _, guides = make_inputs(tmp)
        ids = C.guide_quest_ids(guides)
        # .goto coordinates and objective indexes aren't quest ids
        assert ids == {496, 1065, 1066, 1067, 990, 500, 501, 92479}


def test_blood_of_innocents_needs_journey_to_tarren_mill():
    with tempfile.TemporaryDirectory() as tmp:
        quests = compiled(tmp)
        q = quests[1066]
        assert q["all"] == [1065]
        # Classic says so and no Forever player data confirms it
        assert q["preSrc"] == "cmangos_classic"
        assert q["min"] == 13 and q["minSrc"] == "cmangos_classic"
        assert q["giver"] == 2216 and q["giverType"] == "n"
        # players saw Lydon give it in Forever
        assert q["giverSrc"] == "foreverdb_verified"
        assert quests[1067]["all"] == [1066] and quests[1067]["preSrc"] == "cmangos_classic"
        assert quests[1067]["giverSrc"] == "cmangos_classic"


def test_rule_seen_in_forever_is_labelled_verified():
    with tempfile.TemporaryDirectory() as tmp:
        q = compiled(tmp)[1065]
        # Classic needs 1064 and Forever players were offered it right after 1064
        assert q["all"] == [1064] and q["preSrc"] == "foreverdb_verified"


def test_order_seen_without_a_classic_rule_is_not_a_rule():
    with tempfile.TemporaryDirectory() as tmp:
        q = compiled(tmp)[92479]
        assert "all" not in q and "preSrc" not in q
        assert q["after"] == 783


def test_prerequisite_chain_is_included():
    with tempfile.TemporaryDirectory() as tmp:
        quests = compiled(tmp)
        # 1064 and 1063 are in no guide, but the chain walk for 1066 needs them
        assert 1064 in quests and 1063 in quests
        assert 9999 not in quests
        # 496 is in a guide but ForeverDB has no data for it
        assert 496 not in quests


def test_one_of_and_exclusive_groups():
    with tempfile.TemporaryDirectory() as tmp:
        quests = compiled(tmp)
        assert quests[990]["any"] == [994, 995] and quests[990]["preSrc"] == "cmangos_classic"
        assert "excl" not in quests[990]  # a group of one locks nothing out
        assert quests[994]["excl"] == [995] and quests[995]["excl"] == [994]
        assert quests[994]["preSrc"] == "cmangos_classic"


def test_min_level_sources():
    with tempfile.TemporaryDirectory() as tmp:
        quests = compiled(tmp)
        # Classic says 28, but players finished it at 25 in Forever: not a rule
        assert "min" not in quests[500] and "minSrc" not in quests[500]
        # Forever's own value wins
        assert quests[501]["min"] == 22 and quests[501]["minSrc"] == "foreverdb_verified"
        assert quests[501]["giver"] == 77 and quests[501]["giverType"] == "o"


def test_givers_and_where_they_are():
    with tempfile.TemporaryDirectory() as tmp:
        quests = compiled(tmp)
        q = quests[1065]
        assert q["level"] == 18
        # where players were offered it and handed it in, in Forever; Forever's name for the giver
        assert q["start"] == ["Zamah the Apothecary", 1456, 23.1, 21.0] and q["startSrc"] == "foreverdb_verified"
        assert q["finish"] == ["Apothecary Lydon", 1424, 61.5, 19.1] and q["finishSrc"] == "foreverdb_verified"
        assert q["objs"] == [[1424, 61.5, 18.4], [1424, 61.5, 19.3]]
        # the Forever client's own quest map point
        assert quests[1066]["start"] == ["Apothecary Lydon", 1424, 61.5, 19.2]
        assert quests[1066]["startSrc"] == "foreverdb_verified"
        # Classic only: where they stand comes from Classic data; the name Forever showed still wins
        q = quests[1067]
        assert q["start"] == ["Apothecary Lydon", 1424, 61.5, 19.2] and q["startSrc"] == "cmangos_classic"
        assert q["finish"] == ["Zamah the Apothecary", 1456, 22.8, 20.9] and q["finishSrc"] == "cmangos_classic"
        assert "objs" not in q
        # an object gives it; the creature that takes it was seen in Forever
        q = quests[501]
        assert q["start"] == ["Wanted Poster", 1424, 61.5, 19.3] and q["startSrc"] == "cmangos_classic"
        assert q["finish"] == ['Said "Ten"', 1424, 61.5, 18.5] and q["finishSrc"] == "foreverdb_verified"
        # nobody known to give it: no spot
        assert "start" not in quests[92479] or quests[92479]["start"][1] == 0


def test_addon_files():
    with tempfile.TemporaryDirectory() as tmp:
        addon = build(tmp)
        assert sorted(os.listdir(addon)) == ["COPYING.txt", "Data.lua", "LICENSE.txt", "NOTICE.txt",
                                             "OpenXP_ForeverData.toc"]
        data = open(os.path.join(addon, "Data.lua"), encoding="utf-8").read()
        # ForeverDB's licence asks for this line to stay at the top of files with its data
        assert data.splitlines()[0] == CREDIT
        assert ("[1066]={level=23,min=13,minSrc=C,all={1065},preSrc=C,giver=2216,giverType=\"n\",giverSrc=V,"
                "start={\"Apothecary Lydon\",1424,61.5,19.2},startSrc=V,"
                "finish={\"Apothecary Lydon\",1424,61.5,19.2},finishSrc=V},") in data
        assert 'finish={"Said \\"Ten\\"",1424,61.5,18.5}' in data
        assert data.index("[990]=") < data.index("[1063]=") < data.index("[92479]=")
        toc = open(os.path.join(addon, "OpenXP_ForeverData.toc"), encoding="utf-8").read()
        assert "## Version: 2026-11-15.d2e4316c" in toc and "Data.lua" in toc
        assert "ForeverDB.net" in toc and "GPL-3.0" in toc
        # the icon file itself is kept with the addon, not written by the build
        assert "## IconTexture: Interface\\AddOns\\OpenXP_ForeverData\\icon\n" in toc
        notice = open(os.path.join(addon, "NOTICE.txt"), encoding="utf-8").read()
        assert "Data from ForeverDB.net (https://foreverdb.net)" in notice
        assert "cmangos/classic-db" in notice
        assert open(os.path.join(addon, "LICENSE.txt"), encoding="utf-8").read() == "LICENSE.txt text\n"


def test_output_is_the_same_every_time():
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        one = open(os.path.join(build(a), "Data.lua"), encoding="utf-8").read()
        two = open(os.path.join(build(b), "Data.lua"), encoding="utf-8").read()
        assert one == two


def test_emitted_lua_loads():
    try:
        from lupa import luajit21 as lupa_mod
    except ImportError:
        try:
            import lupa as lupa_mod
        except ImportError:
            return
    with tempfile.TemporaryDirectory() as tmp:
        addon = build(tmp)
        rt = lupa_mod.LuaRuntime()
        rt.execute(open(os.path.join(addon, "Data.lua"), encoding="utf-8").read())
        data = rt.globals().OpenXP_ForeverData
        assert data.quests[501].finish[1] == 'Said "Ten"' and data.quests[1065].objs[2][3] == 19.3
        assert data.format == 1 and data.build == "1.60.1.70938"
        assert data.quests[1066].all[1] == 1065
        assert data.quests[1066].preSrc == "cmangos_classic"
        assert data.quests[1065].preSrc == "foreverdb_verified"


def test_missing_licence_files_stop_the_build():
    with tempfile.TemporaryDirectory() as tmp:
        src, guides = make_inputs(tmp)
        os.remove(os.path.join(src, "LICENSE.txt"))
        try:
            C.main(["--foreverdb", src, "--guides", guides, "--out", os.path.join(tmp, "out")])
        except SystemExit as e:
            assert e.code not in (0, None)
        else:
            raise AssertionError("built an addon without ForeverDB's licence file")
        assert not os.path.exists(os.path.join(tmp, "out", "OpenXP_ForeverData", "Data.lua"))


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("ok   " + name)
            except Exception as e:  # noqa: BLE001
                failures += 1
                print("FAIL %s: %r" % (name, e))
    sys.exit(1 if failures else 0)
