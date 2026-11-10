"""OpenXP Horde route, levels 30-40 (Forever). Zone plan lives in _horde.py."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _horde

GAME = "Forever"
FACTION = "Horde"
GROUP = "RestedXP Forever Guide (H)"
OUTPUT = "Guides/openxp/Horde-30-40.lua"
NEXT = '40-42 Tanaris'
SKIP = _horde.SKIP
HEADER = _horde.header("30-40", GAME)
SECTIONS = _horde.sections_30_40()
# Forever's new zone Shen'dralas, walked into from southern Desolace through
# the Valley of Bones (no flight master). Before Badlands.
SECTIONS.insert(len(SECTIONS) - 1, dict(
    name="38-39 Shen'dralas", zone="Shen'dralas", area=16651, levels=(36, 43), start=(35.6, 12.0),
    intro=_horde.travel("Shen'dralas", "Fly to Shadowprey Village in Desolace and head east through the Valley of Bones into Shen'dralas"),
))
