"""OpenXP Horde route, levels 30-40 (Classic). Zone plan lives in _horde.py."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _horde

GAME = "Classic"
FACTION = "Horde"
GROUP = "RestedXP Horde 20-30"
OUTPUT = "Guides/openxp-classic/Horde-30-40.lua"
NEXT = '40-42 Tanaris'
SKIP = _horde.SKIP
HEADER = _horde.header("30-40", GAME)
SECTIONS = _horde.sections_30_40()
