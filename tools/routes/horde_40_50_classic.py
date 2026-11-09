"""OpenXP Horde route, levels 40-50 (Classic). Zone plan lives in _horde.py."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _horde

GAME = "Classic"
FACTION = "Horde"
GROUP = "RestedXP Horde 20-30"
OUTPUT = "Guides/openxp-classic/Horde-40-50.lua"
NEXT = "50-51 Un'Goro Crater"
SKIP = _horde.SKIP
HEADER = _horde.header("40-50", GAME)
SECTIONS = _horde.sections_40_50()
