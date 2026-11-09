"""OpenXP Horde route, levels 22-30 (Forever). Zone plan lives in _horde.py."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _horde

GAME = "Forever"
FACTION = "Horde"
GROUP = "RestedXP Forever Guide (H)"
OUTPUT = "Guides/openxp/Horde-22-30.lua"
NEXT = '30-32 Arathi Highlands'
SKIP = _horde.SKIP
HEADER = _horde.header("22-30", GAME)
SECTIONS = _horde.sections_22_30()
