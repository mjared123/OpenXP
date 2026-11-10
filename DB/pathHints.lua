local _, addon = ...

-- Arrow path hints: stepping stones for places the straight-line arrow can't
-- reach, like caves under a hill or a camp on top of a ridge. PathHints.lua
-- reads this table. When the arrow's target is inside an area and you're
-- not, the arrow first walks you through the area's entrance points, in
-- order, and only then points at the target. Leaving works the same way in
-- reverse.
--
-- Coordinates are world coordinates (the same numbers as a guide's
-- ".goto <map>/<continent>,x,y" line). inst is the continent: 0 Eastern
-- Kingdoms, 1 Kalimdor.
--
--   name      shown on the arrow ("Enter <name>")
--   indoor    true for caves and mines: you only count as inside while the
--             game says you're indoors, so standing on the hill above the
--             cave still sends you to the entrance
--   circles   {x, y, radius in yards}: what counts as inside the area
--   entrances each one is a list of points from the outside in; the last one
--             is the mouth. oneWay = true for paths you can't walk back up
--             (a jump down), so they're never used to leave
--
-- The first entries come from the entrance and ramp waypoints in the free
-- RestedXP 1-20 guides bundled with OpenXP. More get added from spots
-- recorded in game (/oxp path, and the entrances OpenXP learns by itself);
-- tools/export_paths.py turns those into entries for this file.

addon.pathHintData = {
    -- Elwynn Forest
    {
        name = "Echo Ridge Mine", inst = 0, indoor = true,
        circles = {{-170, -8605, 75}},
        entrances = {{{-117.74, -8681.87}}},
    },
    {
        name = "Jasperlode Mine", inst = 0, indoor = true,
        circles = {{-590, -9100, 60}},
        entrances = {{{-610.25, -9186.47}, {-604.49, -9180.39}}},
    },

    -- Dun Morogh
    {
        name = "Frostmane cave", inst = 0, indoor = true,
        circles = {{370, -6540, 85}},
        entrances = {{{479.72, -6498.17}, {467.51, -6526.96}}},
    },
    {
        name = "Frostmane Hold", inst = 0, indoor = true,
        circles = {{690, -5590, 85}},
        -- over the top of the entrance and jump down; can't walk back up
        entrances = {{{572.06, -5534.28}, {586.49, -5546.20}, oneWay = true}},
    },
    {
        name = "the hills in northern Coldridge Valley", inst = 0,
        circles = {{453, -5941, 50}},
        entrances = {{{497.30, -6118.50}, {467.70, -6012.80}}},
    },
    {
        name = "Grizzled Den", inst = 0, indoor = true,
        circles = {{-265, -5530, 60}},
        entrances = {{{-275.00, -5623.20}}},
    },
    {
        name = "Shimmer Ridge", inst = 0,
        circles = {
            {-212.24, -5364.43, 45}, {-241.79, -5308.62, 45},
            {-153.14, -5190.42, 50}, {-271.34, -5003.27, 50},
        },
        entrances = {{{-312.47, -5361.68}, {-278.93, -5364.47}}},
    },
    {
        name = "Gol'Bolar Quarry Mine", inst = 0, indoor = true,
        circles = {{-1720, -5600, 75}},
        entrances = {{{-1682.35, -5722.94}}},
    },
    {
        name = "the cave atop the mountain", inst = 0,
        circles = {{-2510.10, -5310.30, 60}},
        entrances = {{{-2473.10, -5418.60, 20}, {-2542.40, -5401.40}}},
    },

    -- Loch Modan
    {
        name = "the mountain trail", inst = 0,
        circles = {{-2880.90, -5701.50, 45}},
        entrances = {{{-2915.50, -5576.50, 15}, {-2874.50, -5608.60}, {-2846.10, -5657.60}}},
    },
    {
        name = "the bunker", inst = 0,
        circles = {{-2620, -5840, 35}},
        -- up the dirt path, then drop down into it
        entrances = {{{-2677.26, -5778.34}, {-2648.30, -5876.75}, oneWay = true}},
    },
    {
        name = "Silver Stream Mine", inst = 0, indoor = true,
        circles = {{-2990, -4905, 45}},
        entrances = {{{-2972.96, -4835.19}}},
    },

    -- Teldrassil
    {
        name = "Shadowthread Cave", inst = 1, indoor = true,
        circles = {{918, 10860, 80}},
        entrances = {{{926.08, 10773.42}}},
    },

    -- Zone to zone passes (a mountain range between two zones). from/to are
    -- map ids; twoWay uses the points in reverse for the other direction.
    passes = {},
}
