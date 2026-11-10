"""OpenXP Horde route for WoW Forever, levels 22-60.

Like alliance.py: HUBS lists the places you can quest from, and
tools/build_route.py picks the zone order itself, going where the next visit
gives the most XP per minute.

    python3 tools/build_route.py --questiedb PATH/TO/QuestieDB --dump OpenXP.lua tools/routes/horde.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _horde import fp, travel, home
import _horde

GAME = "Forever"
FACTION = "Horde"
GROUP = "RestedXP Forever Guide (H)"
START_LEVEL = 22
FIRST = "hillsbrad"
# Left out on purpose: see _horde.py, plus the Blasted Lands' repeatable
# Kum'isha and buff turn-ins.
SKIP = _horde.SKIP | {2521, 2522, 3501, 3502, 2582, 2584, 2586, 2602, 2604}
OUTPUTS = [
    (30, "Guides/openxp/Horde-22-30.lua", _horde.header("22-30", GAME)),
    (40, "Guides/openxp/Horde-30-40.lua", _horde.header("30-40", GAME)),
    (50, "Guides/openxp/Horde-40-50.lua", _horde.header("40-50", GAME)),
    (61, "Guides/openxp/Horde-50-60.lua", _horde.header("50-60", GAME)),
]


def hub(key, zone, area, start, continent, town, fpm=None, ride=0, first_text=None,
        extra=(), **kw):
    first = travel(zone, first_text or "Travel to %s in %s" % (town, zone))
    if fpm:
        first += fp(town, zone, start[0], start[1], fpm)
    first += list(extra)
    again = travel(zone, ("Fly to %s in %s" % (town, zone)) if fpm else
                   (first_text or "Travel to %s in %s" % (town, zone)))
    d = dict(key=key, zone=zone, area=area, start=start, continent=continent,
             first=first, again=again, ride=ride)
    d.update(kw)
    return d


def city(key, name, area, start, continent):
    t = travel(name, "Travel to %s" % name)
    return dict(key=key, zone=name, area=area, start=start, continent=continent,
                first=t, again=t, city=True)


K, E = "Kalimdor", "Eastern Kingdoms"
HUBS = [
    # Kalimdor
    hub("barrens", "The Barrens", 17, (51.5, 30.34), K, "the Crossroads", "Devrak"),
    hub("ashenvale", "Ashenvale", 331, (73.18, 61.59), K, "Splintertree Post", "Vhulgra"),
    hub("stonetalon", "Stonetalon Mountains", 406, (45.12, 59.84), K, "Sun Rock Retreat", "Tharm"),
    hub("needles", "Thousand Needles", 400, (45.14, 49.11), K, "Freewind Post", "Nyse",
        extra=home("Thousand Needles", 46.07, 51.52, "Innkeeper Abeqwa", "Freewind Post")),
    hub("flats", "Thousand Needles", 400, (78.0, 77.0), K, "the Shimmering Flats", ride=5,
        first_text="Fly to Freewind Post and ride east to the Shimmering Flats in Thousand Needles"),
    hub("desolace", "Desolace", 405, (21.6, 74.13), K, "Shadowprey Village", "Thalon"),
    # Forever's new zone, walked into from southern Desolace through the
    # Valley of Bones (no flight master).
    hub("shendralas", "Shen'dralas", 16651, (35.6, 12.0), K, "Shen'dralas", ride=5,
        first_text="Fly to Shadowprey Village in Desolace and head east through the Valley of Bones into Shen'dralas"),
    hub("dustwallow", "Dustwallow Marsh", 15, (35.56, 31.88), K, "Brackenwall Village", "Shardi"),
    hub("tanaris", "Tanaris", 440, (51.6, 25.44), K, "Gadgetzan", "Bulkrek Ragefist"),
    hub("feralas", "Feralas", 357, (75.45, 44.36), K, "Camp Mojache", "Shyn"),
    hub("azshara", "Azshara", 16, (21.96, 49.62), K, "Valormok", "Kroum"),
    hub("ungoro", "Un'Goro Crater", 490, (45.23, 5.83), K, "Marshal's Refuge", "Gryfe"),
    hub("felwood", "Felwood", 361, (34.44, 53.96), K, "Bloodvenom Post", "Brakkar"),
    hub("winterspring", "Winterspring", 618, (60.47, 36.3), K, "Everlook", "Yugrek"),
    hub("silithus", "Silithus", 1377, (48.68, 36.67), K, "Cenarion Hold", "Runk Windtamer"),
    city("orgrimmar", "Orgrimmar", 1637, (45.12, 63.89), K),
    city("thunderbluff", "Thunder Bluff", 1638, (47.0, 49.83), K),
    # Eastern Kingdoms
    hub("hillsbrad", "Hillsbrad Foothills", 267, (60.14, 18.62), E, "Tarren Mill", "Zarise",
        first_text="Take the zeppelin to Undercity, then ride south to Tarren Mill",
        extra=home("Hillsbrad Foothills", 62.78, 19.03, "Innkeeper Shay", "Tarren Mill"),
        label="Hillsbrad/Alterac",
        nearby=[(36, "Alterac Mountains", (0.6, 15.0, -25.0))]),
    hub("arathi", "Arathi Highlands", 45, (73.02, 32.7), E, "Hammerfall", "Urda"),
    hub("stv_north", "Stranglethorn Vale", 33, (32.54, 29.35), E, "Grom'gol", "Thysta"),
    hub("stv_south", "Stranglethorn Vale", 33, (26.87, 77.1), E, "Booty Bay", "Gringer"),
    hub("swamp", "Swamp of Sorrows", 8, (46.07, 54.83), E, "Stonard", "Breyk"),
    hub("badlands", "Badlands", 3, (3.99, 44.78), E, "Kargath", "Gorrik"),
    hub("hinterlands", "The Hinterlands", 47, (81.7, 81.76), E, "Revantusk Village", "Gorkas"),
    hub("searing", "Searing Gorge", 51, (34.84, 30.87), E, "Thorium Point", "Grisha"),
    hub("blasted", "Blasted Lands", 4, (50.55, 14.2), E, "the Blasted Lands", ride=4,
        first_text="Fly to Stonard in the Swamp of Sorrows and ride south into the Blasted Lands"),
    hub("steppes", "Burning Steppes", 46, (65.69, 24.22), E, "Flame Crest", "Vahgruk"),
    hub("wpl", "Western Plaguelands", 28, (83.0, 70.0), E, "the Bulwark", ride=3,
        first_text="Fly to Undercity and ride east to the Bulwark in the Western Plaguelands"),
    hub("epl", "Eastern Plaguelands", 139, (70.53, 47.55), E, "Light's Hope Chapel", "Georgia"),
    city("undercity", "Undercity", 1497, (63.25, 48.56), E),
]
