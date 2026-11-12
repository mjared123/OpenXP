local _, OXP = ...

-- Arrow path hints: stepping stones for places the straight-line arrow can't
-- reach, like caves under a hill or a camp on top of a ridge (Nav/PathHints.lua).
-- When the arrow's target is inside an area and you're not, the arrow first
-- walks you through the area's entrance points, in order, and only then
-- points at the target. Leaving works the same way in reverse.
--
-- Coordinates are world coordinates (HereBeDragons: x is the game's Y, y the
-- game's X). inst is the continent: 0 Eastern Kingdoms, 1 Kalimdor.
--
--   name      shown on the arrow ("Enter <name>")
--   indoor    true for caves and mines: you only count as inside while the
--             game says you're indoors
--   circles   {x, y, radius in yards}: what counts as inside the area
--   entrances each one is a list of points from the outside in; the last one
--             is the mouth. oneWay = true for paths you can't walk back up
--   passes    zone to zone passes: from/to map ids, pts, twoWay
--
-- The list starts empty in 2.0: the 1-20 guides lead you to cave entrances
-- with their own steps, and OpenXP learns the caves you walk into (saved in
-- OpenXPDB.paths). Spots recorded in game with /oxp path can be added here
-- with tools/export_paths.py.
OXP.pathHintData = {
    passes = {},
}
