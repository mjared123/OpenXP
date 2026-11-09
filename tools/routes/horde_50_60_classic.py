"""OpenXP Horde route, levels 50-60 (Classic). Zone plan lives in _horde.py."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _horde

GAME = "Classic"
FACTION = "Horde"
GROUP = "RestedXP Horde 20-30"
OUTPUT = "Guides/openxp-classic/Horde-50-60.lua"
NEXT = None
SKIP = _horde.SKIP
HEADER = _horde.header("50-60", GAME)
SECTIONS = _horde.sections_50_60()
