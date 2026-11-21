-- Routes on SoupNav's zone walking graphs (shipped in the optional OpenXP_Nav
-- add-on as NAV.packed[map], unpacked by NAV.Unpack), for walks SoupEngine
-- didn't bake: the first spot in a new zone, or when you're far off every
-- baked walk. Nav/WalkPaths.lua asks for these and treats them like baked
-- walks. Without OpenXP_Nav nothing here runs.
--
-- Graph nodes are in world yards (x = game X, north; y = game Y, west); a
-- zone's frame (SoupNav's data/frames.json) turns them into map %.
local _, OXP = ...

local G = {}
OXP.WalkGraph = G

local floor, sqrt, huge, abs = math.floor, math.sqrt, math.huge, math.abs

-- [uiMap] = { top, bottom, left, right } in world yards (SoupNav frames.json)
local FRAMES = {
    [1411] = { 1808.333, -1716.667, -1962.5, -7250 }, -- Durotar
    [1412] = { 266.666, -3835.416, 2479.167, -3675 }, -- Mulgore
    [1413] = { 1612.5, -5143.75, 2622.917, -7510.417 }, -- The Barrens
    [1416] = { 1500, -366.667, 783.333, -2016.667 }, -- Alterac Mountains
    [1417] = { -133.333, -2533.333, -866.667, -4466.667 }, -- Arathi Highlands
    [1418] = { -5889.583, -7547.917, -2079.167, -4566.667 }, -- Badlands
    [1419] = { -10566.666, -12800, -1241.667, -4591.667 }, -- Blasted Lands
    [1420] = { 3837.5, 825, 3033.333, -1485.417 }, -- Tirisfal Glades
    [1421] = { 1666.667, -1133.333, 3450, -750 }, -- Silverpine Forest
    [1422] = { 3366.667, 500, 416.667, -3883.333 }, -- Western Plaguelands
    [1423] = { 3691.667, 825, -2256.25, -6558.334 }, -- Eastern Plaguelands
    [1424] = { 400, -1733.333, 1066.667, -2133.333 }, -- Hillsbrad Foothills
    [1425] = { 1466.667, -1100, -1575, -5425 }, -- The Hinterlands
    [1426] = { -3877.083, -7160.417, 1802.083, -3122.917 }, -- Dun Morogh
    [1427] = { -6100, -7587.5, -322.917, -2554.167 }, -- Searing Gorge
    [1428] = { -7031.25, -8983.333, -266.667, -3195.833 }, -- Burning Steppes
    [1429] = { -7939.583, -10254.166, 1535.417, -1935.417 }, -- Elwynn Forest
    [1430] = { -9866.666, -11533.333, -833.333, -3333.333 }, -- Deadwind Pass
    [1431] = { -9716.666, -11516.666, 833.333, -1866.667 }, -- Duskwood
    [1432] = { -4487.5, -6327.083, -1993.75, -4752.083 }, -- Loch Modan
    [1433] = { -8575, -10022.916, -1681.25, -3852.084 }, -- Redridge Mountains
    [1434] = { -11168.75, -15422.916, 2220.833, -4160.417 }, -- Stranglethorn Vale
    [1435] = { -9620.833, -11150, -2222.917, -4516.667 }, -- Swamp of Sorrows
    [1436] = { -9400, -11733.333, 3016.667, -483.333 }, -- Westfall
    [1437] = { -2147.917, -4904.167, -389.583, -4525 }, -- Wetlands
    [1438] = { 11831.25, 8437.5, 3814.583, -1277.083 }, -- Teldrassil
    [1439] = { 8333.333, 3966.667, 2941.667, -3608.333 }, -- Darkshore
    [1440] = { 4672.917, 829.167, 1700, -4066.667 }, -- Ashenvale
    [1441] = { -3966.667, -6900, -433.333, -4833.333 }, -- Thousand Needles
    [1442] = { 2916.667, -339.583, 3245.833, -1637.5 }, -- Stonetalon Mountains
    [1443] = { 452.083, -2545.833, 4233.333, -262.5 }, -- Desolace
    [1444] = { -2366.667, -7000, 5441.667, -1508.333 }, -- Feralas
    [1445] = { -2033.333, -5533.333, -975, -6225 }, -- Dustwallow Marsh
    [1446] = { -5875, -10475, -218.75, -7118.75 }, -- Tanaris
    [1447] = { 5341.667, 1960.417, -3277.083, -8347.916 }, -- Azshara
    [1448] = { 7133.333, 3300, 1641.667, -4108.333 }, -- Felwood
    [1449] = { -5966.667, -8433.333, 533.333, -3166.667 }, -- Un'Goro Crater
    [1450] = { 8491.666, 6952.083, -1381.25, -3689.583 }, -- Moonglade
    [1451] = { -5958.334, -8281.25, 2537.5, -945.834 }, -- Silithus
    [1452] = { 8533.333, 3800, -316.667, -7416.667 }, -- Winterspring
    [1453] = { -7995.83, -9154.17, 1722.92, -14.584 }, -- Stormwind City
    [1454] = { 2273.877, 1338.461, -3680.601, -5083.206 }, -- Orgrimmar
    [1455] = { -4569.241, -5096.846, -713.591, -1504.216 }, -- Ironforge
    [1456] = { -850, -1545.833, 516.667, -527.083 }, -- Thunder Bluff
    [1457] = { 10238.316, 9532.587, 2938.363, 1880.03 }, -- Darnassus
    [1458] = { 1877.945, 1237.841, 873.193, -86.182 }, -- Undercity
    [2521] = { 4956.25, 1247.917, 4231.25, -1331.25 }, -- Zephras Isle
    [2524] = { 447.916, -835.416, 2918.75, 993.75 }, -- Darkspear Islands
    [2548] = { -6466.666, -9700, -1891.666, -6741.666 }, -- Riverglades
    [2652] = { -1900, -3266.666, 2025, -25 }, -- Shen'dralas
}
G.FRAMES = FRAMES

local RUN = 7          -- yards per second, as SoupNav packs link times
local MAX_EXPAND = 80000
local TOLERANCE = 3    -- yards: corners closer than this to a straight line are dropped
local SEARCH = 4       -- map cells (1%) around a point to look for a graph node

local graphs = {}      -- [map] = unpacked graph, or false
-- An unpacked zone graph is big (The Barrens: tens of thousands of nodes
-- and links), so only the last KEEP zones stay unpacked; going back to an
-- older one unpacks it again (a few milliseconds, once).
local KEEP = 2
local recent = {}      -- maps unpacked, most recent last

--- The unpacked graph for a zone (with node map % in g.px, g.py), or nil.
function G.Graph(nav, map)
    if graphs[map] ~= nil then
        if graphs[map] and recent[#recent] ~= map then
            for i = #recent, 1, -1 do if recent[i] == map then table.remove(recent, i) end end
            recent[#recent + 1] = map
        end
        return graphs[map] or nil
    end
    local packed = nav and nav.packed and nav.packed[map]
    local f = FRAMES[map]
    if not (packed and f and nav.Unpack) then graphs[map] = false return nil end
    local ok, g = pcall(nav.Unpack, packed)
    if not ok or type(g) ~= "table" or g.grid then graphs[map] = false return nil end
    local top, bottom, left, right = f[1], f[2], f[3], f[4]
    g.px, g.py = {}, {}
    for i = 1, g.n do
        g.px[i] = (left - g.y[i]) / (left - right) * 100
        g.py[i] = (top - g.x[i]) / (top - bottom) * 100
    end
    g.ydx = abs(left - right) / 100   -- yards per 1% across
    g.ydy = abs(top - bottom) / 100   -- yards per 1% down
    graphs[map] = g
    recent[#recent + 1] = map
    while #recent > KEEP do
        local old = table.remove(recent, 1)
        graphs[old] = nil -- unpacked again if it's needed
    end
    return g
end

function G.Reset() graphs, recent = {}, {} end

-- Yards between two map % points on graph g's zone.
local function Yards(g, ax, ay, bx, by)
    local dx, dy = (ax - bx) * g.ydx, (ay - by) * g.ydy
    return sqrt(dx * dx + dy * dy)
end

--- The graph node nearest a map % point (searching nearby cells), or nil.
function G.Nearest(g, x, y)
    local col, row = floor(x), floor(y)
    local best, bestD = nil, huge
    for r = 0, SEARCH do
        for dr = -r, r do
            for dc = -r, r do
                if abs(dr) == r or abs(dc) == r then
                    local cell = (row + dr) * 100 + (col + dc)
                    for ind = 0, 1 do
                        local list = g.starts[cell * 2 + ind]
                        if list then
                            for _, n in ipairs(list) do
                                local d = Yards(g, x, y, g.px[n], g.py[n])
                                if d < bestD then best, bestD = n, d end
                            end
                        end
                    end
                end
            end
        end
        if best and r >= 1 then break end
    end
    return best, bestD
end

-- binary heap of nodes by f score
local function Push(h, f, n, score)
    local i = #h + 1
    h[i], f[i] = n, score
    while i > 1 do
        local p = floor(i / 2)
        if f[p] <= f[i] then break end
        h[p], h[i], f[p], f[i] = h[i], h[p], f[i], f[p]
        i = p
    end
end

local function Pop(h, f)
    local top = h[1]
    local n = #h
    h[1], f[1] = h[n], f[n]
    h[n], f[n] = nil, nil
    n = n - 1
    local i = 1
    while true do
        local l, r, m = i * 2, i * 2 + 1, i
        if l <= n and f[l] < f[m] then m = l end
        if r <= n and f[r] < f[m] then m = r end
        if m == i then break end
        h[m], h[i], f[m], f[i] = h[i], h[m], f[i], f[m]
        i = m
    end
    return top
end

-- Drop corners within TOLERANCE yards of the line between their neighbours
-- (Douglas-Peucker on map %, measured in yards).
local function Simplify(g, pts)
    if #pts <= 2 then return pts end
    local keep = { [1] = true, [#pts] = true }
    local function Run(a, b)
        local ax, ay, bx, by = pts[a][1], pts[a][2], pts[b][1], pts[b][2]
        local dx, dy = (bx - ax) * g.ydx, (by - ay) * g.ydy
        local len = sqrt(dx * dx + dy * dy)
        local far, at = 0, nil
        for i = a + 1, b - 1 do
            local px, py = (pts[i][1] - ax) * g.ydx, (pts[i][2] - ay) * g.ydy
            local d
            if len < 0.01 then d = sqrt(px * px + py * py) else d = abs(px * dy - py * dx) / len end
            if d > far then far, at = d, i end
        end
        if at and far > TOLERANCE then
            keep[at] = true
            Run(a, at)
            Run(at, b)
        end
    end
    Run(1, #pts)
    local out = {}
    for i = 1, #pts do if keep[i] then out[#out + 1] = pts[i] end end
    return out
end

--- A walk on zone `map` from (ax, ay) to (bx, by), map %: { {x, y}, ... }
--- starting at a and ending on b, or nil when there's no graph or no way.
function G.Route(nav, map, ax, ay, bx, by)
    local g = G.Graph(nav, map)
    if not g then return nil end
    local s = G.Nearest(g, ax, ay)
    local e = G.Nearest(g, bx, by)
    if not (s and e) then return nil end
    local ex, ey = g.x[e], g.y[e]
    local function H(n)
        local dx, dy = g.x[n] - ex, g.y[n] - ey
        return sqrt(dx * dx + dy * dy) / RUN
    end
    local cost, from, done = { [s] = 0 }, {}, {}
    local h, f = {}, {}
    Push(h, f, s, H(s))
    local expanded, found = 0, s == e
    while #h > 0 and not found do
        local n = Pop(h, f)
        if not done[n] then
            done[n] = true
            if n == e then found = true break end
            expanded = expanded + 1
            if expanded > MAX_EXPAND then return nil end
            local links, c = g.links[n], cost[n]
            for i = 1, #links, 2 do
                local m = links[i]
                local nc = c + links[i + 1]
                if not done[m] and (not cost[m] or nc < cost[m]) then
                    cost[m], from[m] = nc, n
                    Push(h, f, m, nc + H(m))
                end
            end
        end
    end
    if not found then return nil end
    local rev = {}
    local n = e
    while n do
        rev[#rev + 1] = n
        n = from[n]
    end
    local pts = { { ax, ay } }
    for i = #rev, 1, -1 do pts[#pts + 1] = { g.px[rev[i]], g.py[rev[i]] } end
    pts[#pts + 1] = { bx, by }
    return Simplify(g, pts)
end
