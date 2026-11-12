-- Places on the map: zone names to map ids, guide coordinates to world
-- coordinates, and where the player stands.
--
-- Guides give a spot as zone + x, y (0-100 on that zone's map). The arrow,
-- the route line and the travel planner work in world coordinates (yards on
-- a continent), which HereBeDragons converts to and from.
local _, OXP = ...

local Places = {}
OXP.Places = Places

local HBD = LibStub("HereBeDragons-2.0")
Places.HBD = HBD

-- Classic and WoW Forever map ids by zone name.
local MAP_IDS = {
    ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Kalimdor"] = 1414,
    ["Eastern Kingdoms"] = 1415, ["Alterac Mountains"] = 1416, ["Arathi Highlands"] = 1417,
    ["Badlands"] = 1418, ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420,
    ["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423,
    ["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426,
    ["Searing Gorge"] = 1427, ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429,
    ["Deadwind Pass"] = 1430, ["Duskwood"] = 1431, ["Loch Modan"] = 1432,
    ["Redridge Mountains"] = 1433, ["Stranglethorn Vale"] = 1434, ["Swamp of Sorrows"] = 1435,
    ["Westfall"] = 1436, ["Wetlands"] = 1437, ["Teldrassil"] = 1438, ["Darkshore"] = 1439,
    ["Ashenvale"] = 1440, ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442,
    ["Desolace"] = 1443, ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446,
    ["Azshara"] = 1447, ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450,
    ["Silithus"] = 1451, ["Winterspring"] = 1452, ["Stormwind City"] = 1453, ["Orgrimmar"] = 1454,
    ["Ironforge"] = 1455, ["Thunder Bluff"] = 1456, ["Darnassus"] = 1457, ["Undercity"] = 1458,
    -- WoW Forever's new zones
    ["Darkspear Islands"] = 2524, ["Riverglades"] = 2548, ["Shen'dralas"] = 2652,
}
Places.MAP_IDS = MAP_IDS

local byKey = {}
for name, id in pairs(MAP_IDS) do byKey[OXP.Util.PlaceKey(name)] = id end

--- Map id for a guide's zone field: a number, "1453", or a zone name.
function Places.MapID(zone)
    if type(zone) == "number" then return zone end
    if not zone then return nil end
    local n = tonumber(zone)
    if n then return n end
    local id = byKey[OXP.Util.PlaceKey(zone)]
    if id then return id end
    -- a zone the table doesn't know: ask the game once per name
    if C_Map and C_Map.GetMapChildrenInfo and not Places.asked then
        Places.asked = true
        for _, continent in ipairs({ 1414, 1415 }) do
            local ok, list = pcall(C_Map.GetMapChildrenInfo, continent, nil, true)
            for _, info in ipairs(ok and list or {}) do
                local key = OXP.Util.PlaceKey(info.name)
                if key and not byKey[key] then byKey[key] = info.mapID end
            end
        end
        return byKey[OXP.Util.PlaceKey(zone)]
    end
end

function Places.ZoneName(map)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    if info and info.name then return info.name end
    for name, id in pairs(MAP_IDS) do
        if id == map then return name end
    end
end

--- World coordinates of a spot on a zone map (x, y 0-100).
function Places.ToWorld(map, x, y)
    if not (map and x and y) then return nil end
    return HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, map)
end

--- Zone map coordinates (0-100) of a world spot, on `map`.
function Places.ToZone(wx, wy, map, allowOutside)
    local x, y = HBD:GetZoneCoordinatesFromWorld(wx, wy, map, allowOutside)
    if not x then return nil end
    return x * 100, y * 100
end

--- The player's world position: wx, wy, instance (continent).
function Places.Player()
    return HBD:GetPlayerWorldPosition()
end

--- The player's spot on their zone map: x, y (0-100), map id.
function Places.PlayerZone()
    local x, y, map = HBD:GetPlayerZonePosition()
    if not x then return nil, nil, map end
    return x * 100, y * 100, map
end

function Places.Distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

--- A spot the arrow and maps can use, from a goto or area goal (cached on
--- the goal): { map, x, y, wx, wy, instance }. nil when it can't be placed.
function Places.Spot(goal)
    local s = goal._spot
    if s ~= nil then return s or nil end
    local map = Places.MapID(goal.zone)
    local x, y = goal.x, goal.y
    if goal[1] == "area" and goal.points then
        local pts = goal.points
        local sx, sy, n = 0, 0, 0
        for i = 1, #pts - 1, 2 do sx, sy, n = sx + pts[i], sy + pts[i + 1], n + 1 end
        if n > 0 then x, y = sx / n, sy / n end
    end
    local wx, wy, inst = Places.ToWorld(map, x, y)
    if wx then
        s = { map = map, x = x, y = y, wx = wx, wy = wy, instance = inst, goal = goal }
    end
    goal._spot = s or false
    return s
end

--- An area goal's outline as { {x, y}, ... } on its map.
function Places.AreaPolygon(goal)
    local poly = goal._poly
    if poly then return poly end
    poly = {}
    local pts = goal.points or {}
    for i = 1, #pts - 1, 2 do poly[#poly + 1] = { pts[i], pts[i + 1] } end
    goal._poly = poly
    return poly
end
