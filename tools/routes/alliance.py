"""OpenXP Alliance route for WoW Forever, levels 21-60.

There's no fixed zone order here. HUBS lists the places you can quest from,
and tools/build_route.py plays the route in its head: at every step it goes
to the hub where the next visit gives the most XP per minute, counting the
trip there, walking, objectives (slower for quests above your level) and
leaving gray quests out. Zones get visited several times as their higher
quests open up, like the well-known Classic routes do.

Build all four files in one go:
    python3 tools/build_route.py --questiedb PATH/TO/QuestieDB --dump OpenXP.lua tools/routes/alliance.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _alliance import fp, travel, home, header, SKIP  # noqa: F401
import _alliance as A

GAME = "Forever"
FACTION = "Alliance"
GROUP = "RestedXP Forever Guide (A)"
START_LEVEL = 21
FIRST = "ashenvale"
OUTPUTS = [
    (30, "Guides/openxp/Alliance-21-30.lua", header("21-30")),
    (40, "Guides/openxp/Alliance-30-40.lua", header("30-40")),
    (50, "Guides/openxp/Alliance-40-50.lua", header("40-50")),
    (61, "Guides/openxp/Alliance-50-60.lua", header("50-60")),
]


def hub(key, zone, area, start, continent, town, fpm=None, ride=0, first_text=None,
        extra=(), **kw):
    """fpm: flight master name (None when the hub has none)."""
    first = travel(zone, first_text or "Travel to %s in %s" % (town, zone))
    if fpm:
        first += fp(town, zone, start[0], start[1], fpm)
    first += list(extra)
    again = travel(zone, ("Fly to %s in %s" % (town, zone)) if fpm else
                   (first_text or "Travel to %s in %s" % (town, zone)))
    # town: where the hub's flight master is (named like in the flight
    # data), for working out how long the trip there takes. Hubs without a
    # flight master list `anchors`: (flight master town, minutes riding).
    d = dict(key=key, zone=zone, area=area, start=start, continent=continent,
             first=first, again=again, ride=ride, town=town, has_fp=bool(fpm))
    d.update(kw)
    return d


def city(key, name, area, start, continent, **kw):
    t = travel(name, "Travel to %s" % name)
    return dict(key=key, zone=name, area=area, start=start, continent=continent,
                first=t, again=t, city=True, town=name.replace(" City", ""), has_fp=True, **kw)


K, E = "Kalimdor", "Eastern Kingdoms"
HUBS = [
    # Kalimdor
    hub("ashenvale", "Ashenvale", 331, A.ASTRANAAR, K, "Astranaar", "Daelyshia",
        extra=home("Ashenvale", 36.99, 49.22, "Innkeeper Kimlya", "Astranaar")),
    hub("stonetalon", "Stonetalon Mountains", 406, A.STONETALON_PEAK, K, "Stonetalon Peak", "Teloren"),
    hub("desolace", "Desolace", 405, A.NIJELS, K, "Nijel's Point", "Baritanas Skyriver"),
    # Forever's new zone, walked into from southern Desolace through the
    # Valley of Bones (no flight master).
    hub("shendralas", "Shen'dralas", 16651, A.SHENDRALAS, K, "Shen'dralas", ride=5,
        first_text="Fly to Nijel's Point and ride south through the Valley of Bones into Shen'dralas", anchors=[("Nijel's Point", 5)]),
    hub("dustwallow", "Dustwallow Marsh", 15, A.THERAMORE, K, "Theramore", "Baldruc"),
    hub("needles", "Thousand Needles", 400, A.SHIMMERING_FLATS, K, "the Shimmering Flats", ride=5,
        first_text="Fly to Gadgetzan or Theramore and ride to the Shimmering Flats in Thousand Needles", anchors=[("Gadgetzan", 4), ("Theramore", 6)]),
    hub("tanaris", "Tanaris", 440, A.GADGETZAN, K, "Gadgetzan", "Bera Stonehammer",
        first_anchors=[("Theramore", 9)], first_tail="ride south through Thousand Needles to Gadgetzan"),
    hub("feralas", "Feralas", 357, A.FEATHERMOON, K, "Feathermoon Stronghold", "Fyldren Moonfeather",
        first_text="Travel to Feathermoon Stronghold in Feralas (boat from the Forgotten Coast)", first_anchors=[("Nijel's Point", 9), ("Thalanaar", 8)],
        first_tail="ride to the Forgotten Coast and take the boat to Feathermoon Stronghold"),
    hub("azshara", "Azshara", 16, A.TALRENDIS, K, "Talrendis Point", "Jarrodenus"),
    hub("ungoro", "Un'Goro Crater", 490, A.MARSHALS_REFUGE, K, "Marshal's Refuge", "Gryfe"),
    hub("felwood", "Felwood", 361, A.TALONBRANCH, K, "Talonbranch Glade", "Mishellena"),
    hub("winterspring", "Winterspring", 618, A.EVERLOOK, K, "Everlook", "Maethrya",
        first_anchors=[("Talonbranch Glade", 7)], first_tail="ride north through Timbermaw Hold to Everlook"),
    hub("silithus", "Silithus", 1377, A.CENARION_HOLD, K, "Cenarion Hold", "Cloud Skydancer"),
    city("darnassus", "Darnassus", 1657, A.DARNASSUS, K, anchors=[("Rut'theran Village", 1)]),
    # Eastern Kingdoms
    hub("wetlands", "Wetlands", 11, A.MENETHIL, E, "Menethil Harbor", "Shellei Brondir"),
    hub("redridge", "Redridge Mountains", 44, A.LAKESHIRE, E, "Lakeshire", "Ariena Stormfeather"),
    # areas=True: kill and loot steps are areas drawn on the map (a test in
    # Duskwood before the other zones get it)
    hub("duskwood", "Duskwood", 10, A.DARKSHIRE, E, "Darkshire", "Felicia Maline", areas=True),
    hub("hillsbrad", "Hillsbrad Foothills", 267, A.SOUTHSHORE, E, "Southshore", "Darla Harris",
        label="Hillsbrad/Alterac",
        # Alterac sits north of Hillsbrad; scale/offset only steer the routing.
        nearby=[(36, "Alterac Mountains", (0.6, 15.0, -25.0))]),
    hub("arathi", "Arathi Highlands", 45, A.REFUGE_POINTE, E, "Refuge Pointe", "Cedrik Prose"),
    hub("stv_north", "Stranglethorn Vale", 33, A.REBEL_CAMP, E, "the Rebel Camp", ride=3,
        first_text="Fly to Darkshire and ride south to the Rebel Camp in Stranglethorn Vale", anchors=[("Darkshire", 3), ("Booty Bay", 6)]),
    hub("stv_south", "Stranglethorn Vale", 33, A.BOOTY_BAY, E, "Booty Bay", "Gyll"),
    hub("swamp", "Swamp of Sorrows", 8, A.SWAMP_WEST, E, "the Swamp of Sorrows", ride=4,
        first_text="Fly to Darkshire and ride east through Deadwind Pass into the Swamp of Sorrows", anchors=[("Darkshire", 4), ("Nethergarde Keep", 3)]),
    hub("badlands", "Badlands", 3, A.THELSAMAR_ROAD, E, "the Badlands", ride=4,
        first_text="Fly to Thelsamar in Loch Modan and ride south into the Badlands", anchors=[("Thelsamar", 4)]),
    hub("hinterlands", "The Hinterlands", 47, A.AERIE_PEAK, E, "Aerie Peak", "Guthrum Thunderfist"),
    hub("searing", "Searing Gorge", 51, A.THORIUM_POINT, E, "Thorium Point", "Lanie Reed",
        first_anchors=[("Lakeshire", 10), ("Morgan's Vigil", 5)], first_tail="ride through the Burning Steppes and Blackrock Mountain to Thorium Point"),
    hub("blasted", "Blasted Lands", 4, A.NETHERGARDE, E, "Nethergarde Keep", "Alexandra Constantine",
        first_anchors=[("Darkshire", 9)], first_tail="ride east through Deadwind Pass and the Swamp of Sorrows to Nethergarde Keep"),
    hub("steppes", "Burning Steppes", 46, A.MORGANS_VIGIL, E, "Morgan's Vigil", "Borgus Stoutarm"),
    hub("wpl", "Western Plaguelands", 28, A.CHILLWIND, E, "Chillwind Camp", "Bibilfaz Featherwhistle",
        first_anchors=[("Southshore", 6), ("Aerie Peak", 7)], first_tail="ride north through the Alterac Mountains to Chillwind Camp"),
    hub("epl", "Eastern Plaguelands", 139, A.LIGHTS_HOPE, E, "Light's Hope Chapel", "Khaelyn Steelwing",
        first_anchors=[("Chillwind Camp", 9), ("Aerie Peak", 9)], first_tail="ride east into the Eastern Plaguelands to Light's Hope Chapel"),
    city("stormwind", "Stormwind City", 1519, A.STORMWIND, E),
    city("ironforge", "Ironforge", 1537, A.IRONFORGE, E),
]
