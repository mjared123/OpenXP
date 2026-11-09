"""OpenXP Horde route, levels 22-30 (Classic). Zone plan lives in _horde.py."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _horde

GAME = "Classic"
FACTION = "Horde"
GROUP = "RestedXP Horde 20-30"
OUTPUT = "Guides/openxp-classic/Horde-22-30.lua"
NEXT = '30-32 Arathi Highlands'
SKIP = _horde.SKIP
HEADER = _horde.header("22-30", GAME)
SECTIONS = _horde.sections_22_30()
