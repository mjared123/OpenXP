local _, addon = ...

-- Getting from one zone to another (Travel.lua): boats, zeppelins, the tram,
-- and the places where you walk from one zone into the next. Map points are
-- {uiMapId, x, y} in zone map coordinates (0-100). Flight paths come from
-- addon.taxiPos and addon.FPDB (DB/forever/), so they aren't listed here.
--
-- The points are hand-placed from the zone maps and are approximate; a few
-- dozen yards off doesn't matter for picking a way, and the arrow walks
-- around terrain on the way to each one.

addon.travelData = {
    -- Which map a flight master stands on, by the second half of its name
    -- in FPDB ("Darkshire, Duskwood"). Cities by the first half.
    fpZone = {
        ["Duskwood"] = 1431, ["Westfall"] = 1436, ["Redridge"] = 1433, ["Wetlands"] = 1437,
        ["Loch Modan"] = 1432, ["Arathi"] = 1417, ["Hillsbrad"] = 1424, ["Silverpine Forest"] = 1421,
        ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423, ["The Hinterlands"] = 1425,
        ["Stranglethorn"] = 1434, ["Badlands"] = 1418, ["Searing Gorge"] = 1427,
        ["Burning Steppes"] = 1428, ["Swamp of Sorrows"] = 1435, ["Blasted Lands"] = 1419,
        ["Darkshore"] = 1439, ["Ashenvale"] = 1440, ["Teldrassil"] = 1438, ["Felwood"] = 1448,
        ["Winterspring"] = 1452, ["Azshara"] = 1447, ["Moonglade"] = 1450, ["Stonetalon Mountains"] = 1442,
        ["Desolace"] = 1443, ["Feralas"] = 1444, ["The Barrens"] = 1413, ["Thousand Needles"] = 1441,
        ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446, ["Un'Goro Crater"] = 1449, ["Silithus"] = 1451,
        ["Durotar"] = 1411, ["Mulgore"] = 1412, ["Tirisfal"] = 1420, ["Elwynn"] = 1429, ["Dun Morogh"] = 1426,
    },
    fpCity = {
        ["Stormwind"] = 1453, ["Ironforge"] = 1455, ["Orgrimmar"] = 1454,
        ["Thunder Bluff"] = 1456, ["Undercity"] = 1458,
    },

    -- Boats, zeppelins and the tram: a and b are the two ends. secs: about
    -- how long the trip takes, waiting for it included. faction: who can use it.
    -- oneway = true: only a to b (a boat that runs a loop, one entry per stop).
    transports = {
        -- WoW Forever: the Menethil boat now runs a one-way loop, Menethil ->
        -- Southshore -> Auberdine -> Menethil (fan sites reading the 1.60.1
        -- client; Matt confirmed it in game 2026-11-11). secs: about 100 for
        -- waiting and docking plus the path length at ~13 yd/s.
        {kind = "boat", a = {1439, 32.4, 43.8}, an = "Auberdine", b = {1437, 4.6, 57.0}, bn = "Menethil Harbor",
         secs = 265, faction = "Alliance", oneway = true},
        {kind = "boat", a = {1437, 4.6, 57.0}, an = "Menethil Harbor", b = {1424, 46.4, 50.2}, bn = "Southshore",
         secs = 355, faction = "Alliance", oneway = true},
        {kind = "boat", a = {1424, 46.4, 50.2}, an = "Southshore", b = {1439, 32.4, 43.8}, bn = "Auberdine",
         secs = 250, faction = "Alliance", oneway = true},
        -- WoW Forever: Stormwind Harbor <-> Auberdine. Both docks from the
        -- free Forever guides' "Take the boat" steps (world coords
        -- 1330.1,-8645.4 in Stormwind and 929.1,6543.6 in Darkshore).
        {kind = "boat", a = {1453, 3.8, 40.9}, an = "Stormwind Harbor", b = {1439, 30.7, 41.0}, bn = "Auberdine",
         secs = 220, faction = "Alliance"},
        {kind = "boat", a = {1437, 5.0, 63.4}, an = "Menethil Harbor", b = {1445, 71.6, 56.4}, bn = "Theramore",
         secs = 240, faction = "Alliance"},
        {kind = "boat", a = {1439, 33.2, 40.0}, an = "Auberdine", b = {1438, 54.9, 96.8}, bn = "Rut'theran Village",
         secs = 150, faction = "Alliance"},
        {kind = "boat", a = {1434, 25.8, 73.1}, an = "Booty Bay", b = {1413, 63.7, 38.6}, bn = "Ratchet",
         secs = 240},
        {kind = "tram", a = {1453, 69.3, 31.0}, an = "Stormwind", b = {1455, 76.6, 51.2}, bn = "Ironforge",
         secs = 150, faction = "Alliance"},
        {kind = "zeppelin", a = {1411, 50.8, 13.6}, an = "Orgrimmar", b = {1420, 60.7, 58.8}, bn = "the Undercity",
         secs = 240, faction = "Horde"},
        {kind = "zeppelin", a = {1411, 50.6, 12.6}, an = "Orgrimmar", b = {1434, 31.4, 29.5}, bn = "Grom'gol",
         secs = 240, faction = "Horde"},
        {kind = "zeppelin", a = {1420, 61.9, 59.0}, an = "the Undercity", b = {1434, 31.6, 30.2}, bn = "Grom'gol",
         secs = 240, faction = "Horde"},
    },

    -- Where you walk from one zone into the next. One point when the border
    -- is a single spot; a and b when there's a tunnel or pass between them.
    -- zones: the two maps it joins.
    gates = {
        -- Eastern Kingdoms
        {a = {1429, 32.0, 50.0}, zones = {1429, 1453}, name = "the Stormwind gate"},
        {a = {1429, 20.6, 79.5}, zones = {1429, 1436}, name = "the bridge into Westfall"},
        {a = {1429, 94.5, 71.5}, zones = {1429, 1433}, name = "the road into Redridge"},
        {a = {1431, 92.0, 13.0}, zones = {1431, 1429}, name = "the road into Elwynn"},
        {a = {1431, 7.0, 63.0}, zones = {1431, 1436}, name = "the bridge into Westfall"},
        {a = {1431, 46.0, 96.0}, zones = {1431, 1434}, name = "the road into Stranglethorn"},
        {a = {1430, 36.0, 28.0}, zones = {1430, 1431}, name = "the road into Deadwind Pass"},
        {a = {1433, 1.5, 88.0}, zones = {1433, 1431}, name = "the road into Duskwood"},
        {a = {1433, 47.0, 21.0}, b = {1428, 79.0, 70.0}, zones = {1433, 1428}, name = "the pass into the Burning Steppes"},
        {a = {1435, 2.0, 50.0}, zones = {1435, 1430}, name = "the road into the Swamp of Sorrows"},
        {a = {1435, 33.5, 74.0}, b = {1419, 53.0, 5.0}, zones = {1435, 1419}, name = "the road into the Blasted Lands"},
        {a = {1426, 53.0, 35.0}, zones = {1426, 1455}, name = "the Ironforge gate"},
        {a = {1426, 86.0, 34.0}, b = {1432, 19.0, 84.0}, zones = {1426, 1432}, name = "the tunnel into Loch Modan"},
        {a = {1432, 24.0, 10.0}, b = {1437, 54.0, 73.0}, zones = {1432, 1437}, name = "Dun Algaz"},
        {a = {1432, 47.0, 77.0}, zones = {1432, 1418}, name = "the road into the Badlands"},
        {a = {1437, 51.0, 9.0}, zones = {1437, 1417}, name = "the Thandol Span"},
        {a = {1424, 83.0, 57.0}, zones = {1424, 1417}, name = "the gate into Arathi"},
        {a = {1424, 54.5, 8.0}, zones = {1424, 1416}, name = "the road into Alterac"},
        {a = {1424, 9.0, 43.0}, zones = {1424, 1421}, name = "the road into Silverpine"},
        {a = {1421, 66.0, 4.0}, zones = {1421, 1420}, name = "the road into Tirisfal"},
        {a = {1420, 62.0, 65.0}, zones = {1420, 1458}, name = "the Undercity entrance"},
        {a = {1422, 22.0, 57.0}, zones = {1422, 1420}, name = "the Bulwark"},
        {a = {1422, 70.0, 50.0}, zones = {1422, 1423}, name = "the road into the Eastern Plaguelands"},
        {a = {1425, 9.0, 47.0}, zones = {1425, 1424}, name = "the road into the Hinterlands"},
        {a = {1428, 20.0, 44.0}, b = {1427, 42.0, 78.0}, zones = {1428, 1427}, name = "Blackrock Mountain"},
        -- Kalimdor
        {a = {1411, 45.5, 12.0}, zones = {1411, 1454}, name = "the Orgrimmar gate"},
        {a = {1411, 34.0, 42.0}, zones = {1411, 1413}, name = "the bridge into the Barrens"},
        {a = {1413, 50.0, 4.0}, zones = {1413, 1440}, name = "the road into Ashenvale"},
        {a = {1413, 35.0, 27.0}, zones = {1413, 1442}, name = "the road into Stonetalon"},
        {a = {1412, 70.0, 61.0}, zones = {1412, 1413}, name = "the road into Mulgore"},
        {a = {1445, 25.0, 47.0}, zones = {1445, 1413}, name = "the road into Dustwallow Marsh"},
        {a = {1441, 31.0, 20.0}, zones = {1441, 1413}, name = "the Great Lift"},
        {a = {1412, 38.0, 32.0}, zones = {1412, 1456}, name = "the lifts up to Thunder Bluff"},
        {a = {1439, 44.0, 92.0}, zones = {1439, 1440}, name = "the road into Ashenvale"},
        {a = {1448, 52.0, 92.0}, zones = {1448, 1440}, name = "the road into Felwood"},
        {a = {1447, 8.0, 77.0}, zones = {1447, 1440}, name = "the road into Azshara"},
        {a = {1440, 40.5, 71.5}, b = {1442, 78.3, 42.5}, zones = {1440, 1442}, name = "the Talondeep Path"},
        {a = {1448, 62.0, 12.0}, b = {1452, 32.0, 41.0}, zones = {1448, 1452}, name = "Timbermaw Hold"},
        {a = {1443, 53.0, 4.0}, zones = {1443, 1442}, name = "the road into Desolace"},
        {a = {1444, 46.0, 4.0}, zones = {1444, 1443}, name = "the road into Feralas"},
        {a = {1444, 91.0, 40.0}, zones = {1444, 1441}, name = "the road into Thousand Needles"},
        {a = {1446, 51.0, 13.0}, zones = {1446, 1441}, name = "the road into Tanaris"},
        {a = {1446, 27.0, 57.0}, zones = {1446, 1449}, name = "the ramp into Un'Goro"},
        {a = {1451, 79.0, 21.0}, zones = {1451, 1449}, name = "the road into Silithus"},
        {a = {1438, 29.5, 55.0}, zones = {1438, 1457}, name = "the way into Darnassus"},
    },
}
