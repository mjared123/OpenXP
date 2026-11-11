-- Terrain-aware arrow
--
-- For zones with walking terrain in DB/terrain.lua (built by
-- tools/terrain.py), the arrow doesn't point straight at the target when a
-- mountain, a cliff or a river is in the way, or when the straight line goes
-- through a pack of mobs well above your level. It finds a way around on a
-- grid of the zone map (one cell per 1% of the map) and points at the next
-- corner of that way instead.
--
-- PathHints.lua asks this module only when no cave entrance or recorded path
-- applies, so hand-made stepping stones always win.

local _, addon = ...

local HBD = LibStub("HereBeDragons-2.0")
local floor, sqrt, max, min, abs = math.floor, math.sqrt, math.max, math.min, math.abs

local L = addon.locale and addon.locale.Get
local tr = {}
addon.terrain = tr

local N = 100           -- grid cells per side
local WATER = 3.0       -- swimming costs this much more than running
local ROAD = 0.65       -- a road counts as this much of the same distance off it:
                        -- stay on the road unless leaving it saves a lot
local SLACK = 1.02      -- a straight cut may cost this much more than the cells it replaces
-- extra cost per cell near a pack of mobs, by levels above you: well above
-- you go far around; at your level just don't walk through them on the way
local DANGER = {[-2] = 1.0, [-1] = 1.0, [0] = 1.0, [1] = 1.5, [2] = 2.0, [3] = 3.0, [4] = 10.0}
local DANGER_MAX = 40.0 -- 5+ levels above you
local NEAR = 1.6        -- cells: a corner counts as reached
local STRAY = 4         -- cells off the way before it's worked out again
local REPLAN = 15       -- seconds: work the way out again at most this often
local MOVED = 2         -- cells: a target that moved less than this keeps its way

local grids = {}        -- uiMap -> {cells (byte per cell), kx, ky}

local function Grid(map)
    local g = grids[map]
    if g ~= nil then return g or nil end
    local d = addon.terrainData and addon.terrainData[map]
    if not d or not d.rows then
        grids[map] = false
        return
    end
    local cells = {}
    for y = 1, N do
        local row = d.rows[y] or ""
        for x = 1, N do
            local c = row:sub(x, x)
            cells[(y - 1) * N + x] = (c == "#" and 0) or (c == "~" and 2) or (c == "=" and 3) or 1
        end
    end
    g = {cells = cells, kx = d.yards and d.yards[1] or 1, ky = d.yards and d.yards[2] or 1,
         packs = d.packs or {}, danger = {}}
    grids[map] = g
    return g
end
tr.Grid = Grid

-- 0 blocked, 1 open, 2 water, 3 road (or a bridge)
local function Kind(g, x, y)
    if x < 1 or y < 1 or x > N or y > N then return 0 end
    return g.cells[(y - 1) * N + x]
end

local FACTOR = {[1] = 1, [2] = WATER, [3] = ROAD}
local MILD = 3          -- danger under this is a pack near your level: roads ignore it
local ROAD_DANGER = 1.0 -- and the mobs by a road are this much trouble at most: the
                        -- road stays the way through a zone a little above you

-- cost per yard of walking a cell of kind k with danger d
local function CellCost(k, d)
    d = d or 0
    if k == 3 then d = d < MILD and 0 or min(d, ROAD_DANGER) end
    return FACTOR[k] + d
end

local function Danger(g, level)
    level = floor(level or 0)
    local d = g.danger[level]
    if d then return d end
    d = {}
    local ratio = g.kx / g.ky
    for _, p in ipairs(g.packs) do
        local over = (p[4] or 0) - level
        if over >= -2 then
            local cost = DANGER[over] or DANGER_MAX
            local px, py, r = p[1], p[2], p[3]
            for y = floor(py - r * ratio) - 1, floor(py + r * ratio) + 1 do
                for x = floor(px - r) - 1, floor(px + r) + 1 do
                    if x >= 0 and y >= 0 and x < N and y < N then
                        local dx, dy = x + 0.5 - px, (y + 0.5 - py) / ratio
                        if dx * dx + dy * dy <= r * r then
                            local i = y * N + x + 1
                            if (d[i] or 0) < cost then d[i] = cost end
                        end
                    end
                end
            end
        end
    end
    g.danger[level] = d
    return d
end

local function NearestOpen(g, x, y)
    if Kind(g, x, y) ~= 0 then return x, y end
    for r = 1, 8 do
        local best, bx, by
        for dy = -r, r do
            for dx = -r, r do
                if Kind(g, x + dx, y + dy) ~= 0 then
                    local dd = dx * dx + dy * dy
                    if not best or dd < best then best, bx, by = dd, x + dx, y + dy end
                end
            end
        end
        if best then return bx, by end
    end
    return x, y
end

-- Binary heap kept in two arrays (f values, cell indexes), so a search
-- doesn't make a table for every cell it looks at
local function Push(hf, hi, n, f, i)
    n = n + 1
    while n > 1 do
        local p = floor(n / 2)
        local pf = hf[p]
        if pf <= f then break end
        hf[n], hi[n] = pf, hi[p]
        n = p
    end
    hf[n], hi[n] = f, i
end

local function Pop(hf, hi, n)
    local topf, topi = hf[1], hi[1]
    local lf, li = hf[n], hi[n]
    hf[n], hi[n] = nil, nil
    n = n - 1
    if n > 0 then
        local i = 1
        while true do
            local l, s, sf = i * 2, i, lf
            if l <= n and hf[l] < sf then s, sf = l, hf[l] end
            if l + 1 <= n and hf[l + 1] < sf then s, sf = l + 1, hf[l + 1] end
            if s == i then break end
            hf[i], hi[i] = sf, hi[s]
            i = s
        end
        hf[i], hi[i] = lf, li
    end
    return topf, topi, n
end

-- Cost of walking the straight line from cell a to cell b (cell middles),
-- or nil when it crosses a blocked cell. Same costs as the grid search.
local function LineCost(g, danger, ax, ay, bx, by)
    local steps = floor(max(abs(bx - ax), abs(by - ay)) * 4) + 1
    local dx, dy = (bx - ax) * g.kx, (by - ay) * g.ky
    local each = sqrt(dx * dx + dy * dy) / steps
    local total = 0
    for s = 0, steps do
        local t = s / steps
        local x = floor(ax + 0.5 + (bx - ax) * t)
        local y = floor(ay + 0.5 + (by - ay) * t)
        local k = Kind(g, x, y)
        if k == 0 then return end
        if s > 0 then total = total + each * CellCost(k, danger[(y - 1) * N + x]) end
    end
    return total
end

-- Cells are 1-based {x, y}; map coordinates of a cell's middle are x - 0.5.
-- cost[i] is the way's cost up to cells[i]. A run of cells becomes one
-- straight line only when the line costs no more than the run: so the way
-- doesn't leave a road to cut a corner through the woods and its mobs.
local function Smooth(g, danger, cells, cost)
    local out = {cells[1]}
    local i = 1
    while i < #cells do
        local j = #cells
        while j > i + 1 do
            local lc = LineCost(g, danger, cells[i][1], cells[i][2], cells[j][1], cells[j][2])
            if lc and lc <= (cost[j] - cost[i]) * SLACK + 0.01 then break end
            j = j - 1
        end
        out[#out + 1] = cells[j]
        i = j
    end
    return out
end

-- The grid search itself, from cell (sx, sy) to cell (tx, ty) (1-based,
-- before NearestOpen). Returns the corners between them as map points, or
-- false when the straight line is fine or there's no way.
local function Search(g, level, sx, sy, tx, ty)
    local danger = Danger(g, level)
    sx, sy = NearestOpen(g, sx, sy)
    tx, ty = NearestOpen(g, tx, ty)
    if sx == tx and sy == ty then return false end
    local cells = g.cells
    local kx, ky = g.kx, g.ky
    local diag = sqrt(kx * kx + ky * ky)
    local SX = {1, -1, 0, 0, 1, 1, -1, -1}
    local SY = {0, 0, 1, -1, 1, -1, 1, -1}
    local SC = {kx, kx, ky, ky, diag, diag, diag, diag}
    local function H(x, y)
        local dx, dy = (x - tx) * kx, (y - ty) * ky
        return sqrt(dx * dx + dy * dy)
    end
    local function K(x, y)
        if x < 1 or y < 1 or x > N or y > N then return 0 end
        return cells[(y - 1) * N + x]
    end
    local start, goal = (sy - 1) * N + sx, (ty - 1) * N + tx
    local best, came = {[start] = 0}, {}
    local hf, hi, n = {}, {}, 0
    Push(hf, hi, n, H(sx, sy), start)
    n = 1
    local found
    while n > 0 do
        local f, i
        f, i, n = Pop(hf, hi, n)
        if i == goal then found = true break end
        local gi = best[i]
        local x, y = (i - 1) % N + 1, floor((i - 1) / N) + 1
        if f - H(x, y) <= gi + 0.001 then
            for s = 1, 8 do
                local dx, dy = SX[s], SY[s]
                local nx, ny = x + dx, y + dy
                local k = K(nx, ny)
                if k ~= 0 and not (s > 4 and (K(x + dx, y) == 0 or K(x, y + dy) == 0)) then
                    local ni = (ny - 1) * N + nx
                    local ng = gi + SC[s] * CellCost(k, danger[ni])
                    local bn = best[ni]
                    if not bn or ng < bn then
                        best[ni] = ng
                        came[ni] = i
                        Push(hf, hi, n, ng + H(nx, ny), ni)
                        n = n + 1
                    end
                end
            end
        end
    end
    if not found then return false end
    local rev, rcost = {}, {}
    local i = goal
    while i do
        rev[#rev + 1] = {(i - 1) % N + 1, floor((i - 1) / N) + 1}
        rcost[#rcost + 1] = best[i]
        i = came[i]
    end
    local cellList, cost = {}, {}
    for k = #rev, 1, -1 do
        cellList[#cellList + 1] = rev[k]
        cost[#cost + 1] = rcost[k]
    end
    cellList = Smooth(g, danger, cellList, cost)
    if #cellList <= 2 then return false end -- straight there
    local pts = {}
    for k = 2, #cellList - 1 do
        pts[#pts + 1] = {cellList[k][1] - 0.5, cellList[k][2] - 0.5}
    end
    return pts
end

-- Ways already worked out. The answer only depends on the map, the start
-- and target cells and your level, so a way is never worked out twice: the
-- route line, the arrow and the travel line all share these.
local found, foundCount = {}, 0
local FOUND_MAX = 600

-- Searches cost a few milliseconds each (a lot more on a slow PC), so the
-- drawing code (lazy) starts at most this many new ones per frame and
-- draws the rest of the route a frame or two later. The arrow always gets
-- its way at once.
tr.lazyPerFrame = 1
local frameAt, frameSearches = nil, 0

function tr.SearchesThisFrame()
    local now = GetTime and GetTime() or 0
    if now ~= frameAt then frameAt, frameSearches = now, 0 end
    return frameSearches
end

-- The way from (ax, ay) to (bx, by), zone map coordinates 0-100, for a
-- character of this level. Returns a list of corners {x, y} (map
-- coordinates) after the start, ending at the target, or nil when the
-- straight line is fine or there's no terrain for the map.
-- lazy: when this frame already had its searches, return nil, true
-- ("not yet") instead of searching now.
function tr.FindPath(map, ax, ay, bx, by, level, lazy)
    local g = Grid(map)
    if not g then return end
    level = floor(level or 0)
    local sx, sy, tx, ty = floor(ax) + 1, floor(ay) + 1, floor(bx) + 1, floor(by) + 1
    local key = map .. ":" .. sx .. ":" .. sy .. ":" .. tx .. ":" .. ty .. ":" .. level
    local corners = found[key]
    if corners == nil then
        local used = tr.SearchesThisFrame()
        if lazy and used >= tr.lazyPerFrame then tr.waited = true return nil, true end
        frameSearches = used + 1
        corners = Search(g, level, sx, sy, tx, ty)
        if foundCount >= FOUND_MAX then found, foundCount = {}, 0 end
        found[key] = corners
        foundCount = foundCount + 1
    end
    if not corners then return end
    local pts = {}
    for k = 1, #corners do pts[k] = {corners[k][1], corners[k][2]} end
    pts[#pts + 1] = {bx, by}
    return pts
end

-- The way from where you stand (ax, ay) to (bx, by) for a line drawn from
-- you, kept between calls in `slot`: while you follow it (or stray less than
-- STRAY cells) it's only trimmed as you pass corners, and worked out again
-- at most every REPLAN seconds. Without this every step you took into a new
-- grid cell meant a new search. Returns the corners after you, ending at
-- the target; nil, true while a lazy search has to wait a frame.
local follows = {}
local function Remaining(f, ax, ay, bx, by)
    local pts = f.pts
    while f.idx < #pts do
        local p = pts[f.idx]
        local dx, dy = p[1] - ax, p[2] - ay
        if dx * dx + dy * dy > NEAR * NEAR then break end
        f.idx = f.idx + 1
    end
    local out = {}
    for k = f.idx, #pts - 1 do out[#out + 1] = {pts[k][1], pts[k][2]} end
    out[#out + 1] = {bx, by}
    return out
end

local function Strayed(f, ax, ay)
    local p = f.pts[f.idx]
    local prev = f.pts[f.idx - 1] or f.from
    if not (p and prev) then return true end
    local vx, vy = p[1] - prev[1], p[2] - prev[2]
    local len2 = vx * vx + vy * vy
    local t = len2 > 0 and max(0, min(1, ((ax - prev[1]) * vx + (ay - prev[2]) * vy) / len2)) or 0
    local qx, qy = prev[1] + vx * t - ax, prev[2] + vy * t - ay
    return qx * qx + qy * qy > STRAY * STRAY
end

function tr.FollowPath(slot, map, ax, ay, bx, by, level, lazy)
    if not Grid(map) then return end
    level = floor(level or 0)
    local now = GetTime and GetTime() or 0
    local f = follows[slot]
    local same = f and f.map == map and f.level == level
    if same then
        local mx, my = f.bx - bx, f.by - by
        same = mx * mx + my * my <= MOVED * MOVED
    end
    if same and now - f.at < REPLAN and not Strayed(f, ax, ay) then
        return Remaining(f, ax, ay, bx, by)
    end
    local pts, pending = tr.FindPath(map, ax, ay, bx, by, level, lazy)
    if pending then
        if same then return Remaining(f, ax, ay, bx, by) end -- the old way, one more frame
        return nil, true
    end
    f = {map = map, level = level, bx = bx, by = by, at = now, from = {ax, ay}, idx = 1,
         pts = pts or {{bx, by}}}
    follows[slot] = f
    return Remaining(f, ax, ay, bx, by)
end

---------------------------------------------------------------------------
-- Arrow
---------------------------------------------------------------------------

local state = {}

function tr.Reset()
    state = {}
end

local function PlayerLevel()
    return UnitLevel and UnitLevel("player") or 60
end

-- Where the arrow should point on the way to target: {wx, wy}, or nil for
-- straight at it. px, py: player world position. ctx.zone: player's map.
function tr.Route(target, px, py, inst, ctx)
    local map = ctx and ctx.zone
    if not (map and target and target.wx and px) or target.instance ~= inst then return end
    if not Grid(map) or not HBD.GetZoneCoordinatesFromWorld then return end
    local ax, ay = HBD:GetZoneCoordinatesFromWorld(px, py, map)
    local bx, by = HBD:GetZoneCoordinatesFromWorld(target.wx, target.wy, map)
    if not (ax and bx) or bx < 0 or by < 0 or bx > 1 or by > 1 then return end
    ax, ay, bx, by = ax * 100, ay * 100, bx * 100, by * 100
    local level = PlayerLevel()
    local now = GetTime and GetTime() or 0

    local pts = state.pts
    -- a target that slides along as you walk (the nearest edge of a kill
    -- area) keeps its way until it has moved a fair bit: working the way
    -- out again 5 times a second made the game stutter
    local mx, my = (state.bx or bx) - bx, (state.by or by) - by
    local fresh = state.target ~= target or state.map ~= map or state.level ~= level
        or mx * mx + my * my > MOVED * MOVED
    if not fresh and pts then
        -- drop corners you've reached
        while state.idx <= #pts do
            local p = pts[state.idx]
            local dx, dy = p[1] - ax, p[2] - ay
            if dx * dx + dy * dy > NEAR * NEAR then break end
            state.idx = state.idx + 1
        end
        -- wandered off the way: work it out again
        local p = pts[state.idx]
        local prev = pts[state.idx - 1] or state.from
        if p and prev and now - (state.at or 0) >= 1 then
            local vx, vy = p[1] - prev[1], p[2] - prev[2]
            local len2 = vx * vx + vy * vy
            local t = len2 > 0 and max(0, min(1, ((ax - prev[1]) * vx + (ay - prev[2]) * vy) / len2)) or 0
            local qx, qy = prev[1] + vx * t - ax, prev[2] + vy * t - ay
            if qx * qx + qy * qy > STRAY * STRAY and now - (state.at or 0) >= 2 then fresh = true end
        end
        if now - (state.at or 0) >= REPLAN and state.idx > 1 then fresh = true end
    end
    if fresh or (not pts and now - (state.at or 0) >= REPLAN) then
        state = {target = target, bx = bx, by = by, map = map, level = level,
                 at = now, from = {ax, ay}, idx = 1}
        state.pts = tr.FindPath(map, ax, ay, bx, by, level)
        pts = state.pts
    end
    if not pts or state.idx >= #pts then return end -- last corner is the target itself
    local p = pts[state.idx]
    local wx, wy = HBD:GetWorldCoordinatesFromZone(p[1] / 100, p[2] / 100, map)
    if not wx then return end
    return {wx, wy}
end

---------------------------------------------------------------------------
-- Kill/loot areas, and the route drawn on the maps
---------------------------------------------------------------------------
-- (Kept in this file rather than a new one: WoW only loads new addon files
-- after a full restart, and this way a /reload is enough.)
--
-- A step can carry an area (.area in the guide): the place to kill and loot
-- in. Inside it the arrow says "Here"; outside, it leads to the nearest edge.
-- Areas and the route through the next steps are drawn on the world map
-- and the minimap (see Drawing below).


local function InsidePoly(poly, x, y)
    local c, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then c = not c end
        j = i
    end
    return c
end
tr.InsidePoly = InsidePoly

-- nearest point on the polygon's edge to (x, y), in map coordinates
local function NearestEdge(poly, x, y, kx, ky)
    local best, bx, by
    local j = #poly
    for i = 1, #poly do
        local ax, ay, cx, cy = poly[j][1], poly[j][2], poly[i][1], poly[i][2]
        local vx, vy = (cx - ax) * kx, (cy - ay) * ky
        local len2 = vx * vx + vy * vy
        local t = len2 > 0 and max(0, min(1, ((x - ax) * kx * vx + (y - ay) * ky * vy) / len2)) or 0
        local px, py = ax + (cx - ax) * t, ay + (cy - ay) * t
        local dx, dy = (px - x) * kx, (py - y) * ky
        local d = dx * dx + dy * dy
        if not best or d < best then best, bx, by = d, px, py end
        j = i
    end
    return bx, by
end

---------------------------------------------------------------------------
-- Areas for every zone: a kill/loot step without an .area line gets one
-- from Questie's spawn data, the same way tools/build_route.py makes them:
-- the outline of the objective's spawns near the step's spot, widened a
-- little so the mobs on the edge are inside, at most 8 corners. Needs
-- Questie; without it such steps just keep their arrow.
---------------------------------------------------------------------------

local AREA_REACH = 7.0  -- map units: spawns this close to the step's spot make its area
local AREA_MARGIN = 1.5 -- map units: the area reaches this far past the outer spawns
local AREA_MIN = 4      -- spawns needed for an area
local AREA_CORNERS = 8

local ObjectiveSpawns   -- defined with the drawing below

local function Cross(o, a, b)
    return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
end

-- The kill area around (wx, wy) from spawn points, or nil
local function KillArea(points, wx, wy)
    local near, seen = {}, {}
    for _, p in ipairs(points) do
        local dx, dy = p[1] - wx, p[2] - wy
        if dx * dx + dy * dy <= AREA_REACH * AREA_REACH then
            local key = floor(p[1] * 100 + 0.5) .. "," .. floor(p[2] * 100 + 0.5)
            if not seen[key] then
                seen[key] = true
                near[#near + 1] = {floor(p[1] * 100 + 0.5) / 100, floor(p[2] * 100 + 0.5) / 100}
            end
        end
    end
    if #near < AREA_MIN then return end
    table.sort(near, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
    local lower, upper = {}, {}
    for i = 1, #near do
        local p = near[i]
        while #lower >= 2 and Cross(lower[#lower - 1], lower[#lower], p) <= 0 do lower[#lower] = nil end
        lower[#lower + 1] = p
    end
    for i = #near, 1, -1 do
        local p = near[i]
        while #upper >= 2 and Cross(upper[#upper - 1], upper[#upper], p) <= 0 do upper[#upper] = nil end
        upper[#upper + 1] = p
    end
    local hull = {}
    for i = 1, #lower - 1 do hull[#hull + 1] = lower[i] end
    for i = 1, #upper - 1 do hull[#hull + 1] = upper[i] end
    if #hull < 3 then return end
    while #hull > AREA_CORNERS do
        -- drop the corner that changes the outline least
        local bi, bv
        for i = 1, #hull do
            local a, b, c = hull[(i - 2) % #hull + 1], hull[i], hull[i % #hull + 1]
            local v = abs(Cross(a, b, c))
            if not bv or v < bv then bi, bv = i, v end
        end
        table.remove(hull, bi)
    end
    local cx, cy = 0, 0
    for _, p in ipairs(hull) do cx, cy = cx + p[1], cy + p[2] end
    cx, cy = cx / #hull, cy / #hull
    local out = {}
    for _, p in ipairs(hull) do
        local dx, dy = p[1] - cx, p[2] - cy
        local d = sqrt(dx * dx + dy * dy)
        if d == 0 then d = 1 end
        out[#out + 1] = {min(100, max(0, p[1] + dx / d * AREA_MARGIN)),
                         min(100, max(0, p[2] + dy / d * AREA_MARGIN))}
    end
    return out
end
tr.KillArea = KillArea

local autoAreas = setmetatable({}, {__mode = "k"}) -- step -> {key, area element or false}

local function AutoArea(step)
    if not (step and step.elements and ObjectiveSpawns) then return end
    local spot, objs = nil, {}
    for _, e in ipairs(step.elements) do
        if (e.tag == "accept" or e.tag == "turnin") and not e.completed and not e.skip then
            return -- talking to someone first: their spot, not an area
        end
        if e.arrow and e.zone and e.x and e.y and not e.skip and not spot then spot = e end
        if e.questId and e.obj and not e.completed and not e.skip then objs[#objs + 1] = e end
    end
    if not spot or #objs == 0 then return end
    local d = addon.terrainData and addon.terrainData[spot.zone]
    if not (d and d.area) then return end
    local key = spot.zone .. ":" .. spot.x .. ":" .. spot.y
    for _, e in ipairs(objs) do key = key .. ":" .. e.questId .. "/" .. e.obj end
    local c = autoAreas[step]
    if c and c.key == key then return c.area or nil end
    local pts, ready = {}, false
    for _, e in ipairs(objs) do
        local sp = ObjectiveSpawns(e.questId, e.obj, d.area)
        if sp then
            ready = true
            for _, p in ipairs(sp) do pts[#pts + 1] = p end
        end
    end
    if not ready then return end -- Questie isn't loaded (yet): ask again later
    local area = KillArea(pts, spot.x, spot.y)
    local a = area and {area = area, areaZone = spot.zone, auto = true} or false
    autoAreas[step] = {key = key, area = a}
    return a or nil
end
tr.AutoArea = AutoArea

local function AreasOn()
    local p = addon.settings and addon.settings.profile
    return not (p and p.openxpMapAreas == false)
end
tr.AreasOn = AreasOn

local function StepArea(step)
    for _, e in ipairs(step and step.elements or {}) do
        if e.area and e.areaZone then return e end
    end
    if AreasOn() then return AutoArea(step) end
end
tr.StepArea = StepArea

-- The arrow's target for a step with an area: a stand-in at your feet while
-- you're inside ("Here"), or at the nearest edge while you're outside. nil
-- when the step has no area or you're in another zone.
local here, edge = {inside = true}, {}
function tr.AreaTarget(element)
    local a = element and StepArea(element.step)
    if not a then return end
    local px, py, map = HBD:GetPlayerZonePosition()
    if not px or map ~= a.areaZone then return end
    px, py = px * 100, py * 100
    local wx, wy, inst
    local t
    if InsidePoly(a.area, px, py) then
        t = here
        wx, wy, inst = HBD:GetPlayerWorldPosition()
        t.title = L and L("In the area") or "In the area"
    else
        t = edge
        local g = Grid(map)
        local ex, ey = NearestEdge(a.area, px, py, g and g.kx or 1, g and g.ky or 1)
        -- a step inside the edge, so arriving counts as being in the area
        local cx, cy = 0, 0
        for _, p in ipairs(a.area) do cx, cy = cx + p[1], cy + p[2] end
        cx, cy = cx / #a.area, cy / #a.area
        local dx, dy = cx - ex, cy - ey
        local d = sqrt(dx * dx + dy * dy)
        if d > 0 then ex, ey = ex + dx / d * 0.6, ey + dy / d * 0.6 end
        wx, wy, inst = HBD:GetWorldCoordinatesFromZone(ex / 100, ey / 100, map)
        t.title = element.title
    end
    if not wx then return end
    t.wx, t.wy, t.instance, t.zone, t.step, t.real = wx, wy, inst, map, element.step, element
    return t
end

---------------------------------------------------------------------------
-- Drawing: smooth blue areas and the purple route, on the world map and
-- the minimap
---------------------------------------------------------------------------
-- Areas are smoothed outlines filled with thin horizontal lines (WoW has no
-- polygon fill); on the minimap they're clipped to its round edge. The route
-- runs from you through the next few steps of the guide, each leg bending
-- round mountains and high-level packs the way the arrow goes, with small
-- chevrons showing the direction.

local AREA_FILL = {0.20, 0.55, 1.0, 0.30}
local AREA_EDGE = {0.35, 0.70, 1.0, 0.95}
local ROUTE_CORE = {0.72, 0.42, 1.0, 0.92}
local PIN_SIZE = 12
local PIN_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STEPS_AHEAD = 4      -- route and areas for this many steps after the current one
local MAP_TICK = 0.25
local MINI_TICK = 0.05

-- Chaikin corner cutting: a rounder outline from a few corners
local function Smooth(poly, rounds)
    for _ = 1, rounds do
        local out = {}
        for i = 1, #poly do
            local a, b = poly[i], poly[i % #poly + 1]
            out[#out + 1] = {a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25}
            out[#out + 1] = {a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75}
        end
        poly = out
    end
    return poly
end

local smoothCache = setmetatable({}, {__mode = "k"})
local function Rounded(a)
    local s = smoothCache[a]
    if not s then
        s = Smooth(a.area, 3)
        smoothCache[a] = s
    end
    return s
end

---------------------------------------------------------------------------
-- A canvas: a frame plus pools of lines and textures drawn on it
---------------------------------------------------------------------------

local function NewCanvas(parent, level)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(level)
    return {frame = f, lines = {}, tex = {}, nl = 0, nt = 0}
end

local function Clear(c)
    for i = 1, #c.lines do c.lines[i]:Hide() end
    for i = 1, #c.tex do c.tex[i]:Hide() end
    for i = 1, #(c.rects or {}) do c.rects[i]:Hide() end
    c.nl, c.nt, c.nr = 0, 0, 0
end

-- x, y in pixels from the frame's top left (y down)
local function Line(c, color, thickness, x1, y1, x2, y2, layer)
    c.nl = c.nl + 1
    local l = c.lines[c.nl]
    if not l then
        l = c.frame:CreateLine(nil, "OVERLAY")
        l:SetTexture(WHITE)
        c.lines[c.nl] = l
    end
    l:SetDrawLayer(layer or "OVERLAY")
    l:SetVertexColor(color[1], color[2], color[3], color[4])
    l:SetThickness(thickness)
    l:SetStartPoint("TOPLEFT", c.frame, x1, -y1)
    l:SetEndPoint("TOPLEFT", c.frame, x2, -y2)
    l:Show()
end

-- a flat rectangle: x, y its top left, in pixels. Not snapped to the pixel
-- grid, so rows laid edge to edge blend into one even fill with no seams.
local function Rect(c, color, x, y, w, h)
    c.nr = (c.nr or 0) + 1
    c.rects = c.rects or {}
    local t = c.rects[c.nr]
    if not t then
        t = c.frame:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        c.rects[c.nr] = t
    end
    t:SetVertexColor(color[1], color[2], color[3], color[4])
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", c.frame, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    t:Show()
end

local function Tex(c, texture, color, size, x, y)
    c.nt = c.nt + 1
    local t = c.tex[c.nt]
    if not t then
        t = c.frame:CreateTexture(nil, "OVERLAY")
        c.tex[c.nt] = t
    end
    t:SetTexture(texture)
    t:SetVertexColor(color[1], color[2], color[3], color[4])
    t:SetSize(size, size)
    t:ClearAllPoints()
    t:SetPoint("CENTER", c.frame, "TOPLEFT", x, -y)
    t:Show()
end

-- Fill a polygon (pixel points) with horizontal lines `step` pixels apart,
-- optionally clipped to a circle {cx, cy, r}.
local function Fill(c, pts, color, step, clip)
    local y0, y1 = math.huge, -math.huge
    for _, p in ipairs(pts) do y0, y1 = min(y0, p[2]), max(y1, p[2]) end
    if clip then y0, y1 = max(y0, clip[2] - clip[3]), min(y1, clip[2] + clip[3]) end
    local top = y0
    local y = y0 + step / 2
    local xs = {}
    while top < y1 do
        xs = {}
        local j = #pts
        for i = 1, #pts do
            local a, b = pts[j], pts[i]
            if (a[2] > y) ~= (b[2] > y) then
                xs[#xs + 1] = a[1] + (y - a[2]) * (b[1] - a[1]) / (b[2] - a[2])
            end
            j = i
        end
        table.sort(xs)
        local lo, hi = -math.huge, math.huge
        if clip then
            local dy = y - clip[2]
            local half = sqrt(max(0, clip[3] * clip[3] - dy * dy))
            lo, hi = clip[1] - half, clip[1] + half
        end
        for k = 1, #xs - 1, 2 do
            local a, b = max(xs[k], lo), min(xs[k + 1], hi)
            if b > a then Rect(c, color, a, top, b - a, min(step, y1 - top)) end
        end
        top = top + step
        y = top + step / 2
    end
end

-- the part of segment a-b inside circle {cx, cy, r}, or nil
local function ClipSegment(ax, ay, bx, by, clip)
    if not clip then return ax, ay, bx, by end
    local dx, dy = bx - ax, by - ay
    local fx, fy = ax - clip[1], ay - clip[2]
    local A = dx * dx + dy * dy
    if A == 0 then return end
    local B = 2 * (fx * dx + fy * dy)
    local C = fx * fx + fy * fy - clip[3] * clip[3]
    local disc = B * B - 4 * A * C
    if disc < 0 then return end
    disc = sqrt(disc)
    local t0, t1 = max(0, (-B - disc) / (2 * A)), min(1, (-B + disc) / (2 * A))
    if t1 <= t0 then return end
    return ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
end

local function Outline(c, pts, color, thickness, clip)
    local j = #pts
    for i = 1, #pts do
        local ax, ay, bx, by = ClipSegment(pts[j][1], pts[j][2], pts[i][1], pts[i][2], clip)
        if ax then Line(c, color, thickness, ax, ay, bx, by) end
        j = i
    end
end

-- Round off a polyline's corners (Chaikin), keeping both ends where they are
local function SmoothOpen(pts, rounds)
    for _ = 1, rounds do
        if #pts < 3 then return pts end
        local out = {pts[1]}
        for i = 1, #pts - 1 do
            local a, b = pts[i], pts[i + 1]
            if i > 1 then out[#out + 1] = {a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25} end
            if i < #pts - 1 then out[#out + 1] = {a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75} end
        end
        out[#out + 1] = pts[#pts]
        pts = out
    end
    return pts
end

local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- One clean line: rounded corners, round joints so the pieces meet without
-- gaps, a small open chevron now and then for the direction, and a dot
-- where it ends.
local function RouteOn()
    local p = addon.settings and addon.settings.profile
    return not (p and p.openxpMapRoute == false)
end
tr.RouteOn = RouteOn

local routeColor = {0.72, 0.42, 1.0, 0.92}
local function RouteColor()
    local p = addon.settings and addon.settings.profile
    local c = p and p.openxpRouteColor
    if c and c[1] then
        routeColor[1], routeColor[2], routeColor[3] = c[1], c[2], c[3]
    end
    return routeColor
end

local function RouteLeg(c, pts, thickness, clip)
    if #pts < 2 or not RouteOn() then return end
    local ROUTE_CORE = RouteColor()
    pts = SmoothOpen(pts, 2)
    local travelled, nextMark = 0, thickness * 40
    for i = 1, #pts - 1 do
        local ax, ay, bx, by = ClipSegment(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], clip)
        if ax then
            Line(c, ROUTE_CORE, thickness, ax, ay, bx, by)
            Tex(c, ROUND, ROUTE_CORE, thickness, bx, by) -- joint
            local dx, dy = bx - ax, by - ay
            local len = sqrt(dx * dx + dy * dy)
            if len > 0 then
                local ux, uy = dx / len, dy / len
                local size = thickness * 2.5
                while nextMark < travelled + len do
                    local d = nextMark - travelled
                    local mx, my = ax + ux * d, ay + uy * d
                    local tx, ty = mx - ux * size, my - uy * size
                    Line(c, ROUTE_CORE, thickness * 0.75, tx - uy * size, ty + ux * size, mx, my)
                    Line(c, ROUTE_CORE, thickness * 0.75, tx + uy * size, ty - ux * size, mx, my)
                    nextMark = nextMark + thickness * 60
                end
                travelled = travelled + len
            end
        end
    end
    local last = pts[#pts]
    if not clip or ClipSegment(last[1], last[2], last[1] + 0.01, last[2], clip) then
        Tex(c, ROUND, ROUTE_CORE, thickness * 2.6, last[1], last[2])
    end
end

---------------------------------------------------------------------------
-- What to draw: areas and the route through the next few steps
---------------------------------------------------------------------------

local function StepTarget(step)
    local a = StepArea(step)
    for _, e in ipairs(step and step.elements or {}) do
        if e.arrow and e.zone and e.x and e.y and not e.skip then
            return e.zone, e.x, e.y, a
        end
    end
    if a then
        local cx, cy = 0, 0
        for _, p in ipairs(a.area) do cx, cy = cx + p[1], cy + p[2] end
        return a.areaZone, cx / #a.area, cy / #a.area, a
    end
end

-- {map, x, y, area} for the current step and the next few, in order
local function Upcoming()
    local guide = addon.currentGuide
    local out = {}
    if not (guide and guide.steps and addon.GetGuideProgress) then return out end
    local first = addon.GetGuideProgress()
    local card = addon.card
    local order = {}
    -- doing a later step first because you're standing by it: that one,
    -- then back where you were
    local here = card and card.here
    if here and here.index == first then
        order[1] = first
        first = here.from
    end
    for i = first, min(#guide.steps, first + STEPS_AHEAD) do
        if i ~= order[1] then order[#order + 1] = i end
    end
    -- quests you'll pick up on the way, so a turn-in ahead for one of them
    -- still counts
    local willHave = {}
    for k, i in ipairs(order) do
        local step = guide.steps[i]
        -- steps ahead whose quests you've already done aren't stops, and
        -- neither are ones for a quest you don't have and won't get on the
        -- way (you skipped its pickup): the card will offer to skip them
        local missing = k > 1 and card and card.MissingQuest and card.MissingQuest(step)
        if step and not step.completed and not step.skip and
            not (k > 1 and card and card.DoneAhead and card.DoneAhead(step)) and
            not (missing and not willHave[missing]) then
            local map, x, y, a = StepTarget(step)
            if map then out[#out + 1] = {map, x, y, a} end
            for _, e in ipairs(step.elements or {}) do
                local id = tonumber(e.questId)
                if e.tag == "accept" and id then willHave[id] = true end
            end
        end
    end
    return out
end

-- Map points (0-100) of the route on `map` starting at (px, py), or {}.
-- Legs between steps are worked out once (tr.FindPath remembers them); the
-- leg from you follows you (tr.FollowPath). A leg that has to wait for its
-- search ends the line there for a frame or two.
local legCache = {}
local function RoutePoints(map, px, py, stops, level)
    -- no terrain for this map (the capitals): a straight line would go
    -- through walls and water, so leave it to the arrow
    if not Grid(map) then return {} end
    local key = map .. ":" .. floor(px * 4) .. ":" .. floor(py * 4) .. ":" .. level
    for _, s in ipairs(stops) do key = key .. ":" .. s[1] .. "/" .. floor(s[2] * 10) .. "/" .. floor(s[3] * 10) end
    if legCache.key == key then return legCache.pts end
    local pts = {{px, py}}
    local ax, ay = px, py
    local fromYou, complete = true, true
    for k, s in ipairs(stops) do
        if s[1] ~= map then break end
        local inside = s[4] and InsidePoly(s[4].area, ax, ay)
        if not (k == 1 and inside) then
            local path, pending
            if fromYou then
                path, pending = tr.FollowPath("route", map, ax, ay, s[2], s[3], level, true)
            else
                path, pending = tr.FindPath(map, ax, ay, s[2], s[3], level, true)
            end
            if pending then complete = false break end
            for _, p in ipairs(path or {{s[2], s[3]}}) do pts[#pts + 1] = {p[1], p[2]} end
            ax, ay = s[2], s[3]
            fromYou = false
        end
    end
    if complete then legCache.key, legCache.pts = key, pts end
    return pts
end

-- Spawn points (map 0-100) of whatever counts for this objective in `area`
-- (a zone id): {} when there are none, nil while Questie isn't loaded.
local spawnCache = {}
function ObjectiveSpawns(questId, objIndex, area)
    local key = questId .. ":" .. objIndex .. ":" .. area
    if spawnCache[key] ~= nil then return spawnCache[key] end
    local QGet = addon.card and addon.card.QGet
    local q = QGet and QGet("Quest", questId)
    if not q then return end -- Questie not ready yet: try again later
    local o = type(q.objectives) == "table" and q.objectives or {}
    local sources = {}
    local i = 0
    for _, e in ipairs(o[1] or {}) do -- creatures
        i = i + 1
        if i == objIndex then sources[#sources + 1] = {"NPC", e[1]} end
    end
    for _, e in ipairs(o[2] or {}) do -- objects
        i = i + 1
        if i == objIndex then sources[#sources + 1] = {"Object", e[1]} end
    end
    for _, e in ipairs(o[3] or {}) do -- items: whoever drops them
        i = i + 1
        if i == objIndex then
            local item = QGet("Item", e[1])
            for _, nid in ipairs(item and item.npcDrops or {}) do sources[#sources + 1] = {"NPC", nid} end
            for _, oid in ipairs(item and item.objectDrops or {}) do sources[#sources + 1] = {"Object", oid} end
        end
    end
    local pts = {}
    for _, src in ipairs(sources) do
        local obj = QGet(src[1], src[2])
        local spots = obj and type(obj.spawns) == "table" and obj.spawns[area]
        for _, pt in ipairs(spots or {}) do
            if pt[1] and pt[1] >= 0 then pts[#pts + 1] = {pt[1], pt[2]} end
        end
    end
    spawnCache[key] = pts
    return pts
end
tr.ObjectiveSpawns = ObjectiveSpawns

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

local wmc
function tr.DrawMap()
    local wm = _G.WorldMapFrame
    if not (wm and wm:IsShown() and wm.GetCanvas) then return end
    local canvas = wm:GetCanvas()
    local map = wm:GetMapID()
    if not wmc then
        -- above the map's own pins and textures
        wmc = NewCanvas(canvas, min(9000, (canvas:GetFrameLevel() or 1) + 3000))
    end
    Clear(wmc)
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = wm.GetCanvasScale and wm:GetCanvasScale() or 1
    local function P(x, y) return x / 100 * w, y / 100 * h end
    local stops = Upcoming()

    for _, s in ipairs(stops) do
        if s[4] and s[4].areaZone == map then
            local px = {}
            for _, p in ipairs(Rounded(s[4])) do px[#px + 1] = {P(p[1], p[2])} end
            Fill(wmc, px, AREA_FILL, max(1, 2 / scale))
            Outline(wmc, px, AREA_EDGE, 2.5 / scale)
        end
    end

    local d = addon.terrainData and addon.terrainData[map]
    if d and d.area and addon.RXPFrame then
        local seen = {}
        for _, step in pairs(addon.RXPFrame.activeSteps or {}) do
            for _, e in ipairs(step.elements or {}) do
                if e.questId and e.obj and not e.completed and not e.skip then
                    for _, pt in ipairs(ObjectiveSpawns(e.questId, e.obj, d.area) or {}) do
                        local key = floor(pt[1] * 10) .. "," .. floor(pt[2] * 10)
                        if not seen[key] then
                            seen[key] = true
                            local x, y = P(pt[1], pt[2])
                            Tex(wmc, PIN_TEXTURE, {1, 1, 1, 0.9}, PIN_SIZE / scale, x, y)
                        end
                    end
                end
            end
        end
    end

    local px, py, pmap = HBD:GetPlayerZonePosition()
    -- the next step is in another zone: the whole way there (Travel.lua),
    -- on this zone's map or the continent map
    local tv = addon.travel
    if not RouteOn() then return end
    local tlines = tv and tv.Polylines(map, PlayerLevel())
    if tlines and #tlines > 0 then
        for _, line in ipairs(tlines) do
            local pts = {}
            for _, p in ipairs(line) do pts[#pts + 1] = {P(p[1], p[2])} end
            RouteLeg(wmc, pts, 2 / scale)
        end
    elseif px and pmap == map and #stops > 0 then
        local pts = {}
        for _, p in ipairs(RoutePoints(map, px * 100, py * 100, stops, PlayerLevel())) do
            pts[#pts + 1] = {P(p[1], p[2])}
        end
        RouteLeg(wmc, pts, 2 / scale)
    end
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

-- yards across the minimap per zoom level (0-5), as HereBeDragons-Pins has them
local MINI_SIZE = {
    indoor = {300, 240, 180, 120, 80, 50},
    outdoor = {466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3},
}

local mmc
local function MinimapRadius()
    local mm = _G.Minimap
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, r = pcall(C_Minimap.GetViewRadius)
        if ok and r and r > 0 then return r end
    end
    local zoom = mm:GetZoom()
    local indoors = (tonumber(GetCVar("minimapZoom")) or 0) == zoom and "outdoor" or "indoor"
    return MINI_SIZE[indoors][zoom + 1] / 2
end

local lastMini
local function DrawMinimap()
    local mm = _G.Minimap
    if not (mm and mm:IsShown()) then return end
    if not mmc then mmc = NewCanvas(mm, mm:GetFrameLevel() + 2) end
    local stops = Upcoming()
    local tv = addon.travel
    local plan = tv and tv.Current and tv.Current()
    if #stops == 0 and not plan then lastMini = nil return Clear(mmc) end
    local wx, wy, inst = HBD:GetPlayerWorldPosition()
    local px, py, pmap = HBD:GetPlayerZonePosition()
    if not (wx and px) then lastMini = nil return Clear(mmc) end
    local radius = MinimapRadius()
    local size = mm:GetWidth() / 2
    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    if rotate and not facing then lastMini = nil return Clear(mmc) end
    -- nothing moved since the last frame (standing, fighting, looting):
    -- keep what's drawn instead of laying out hundreds of lines again
    local col = RouteColor()
    local sig = {pmap, floor(wx * 2), floor(wy * 2), floor(facing * 200), radius, size, tostring(plan),
                 RouteOn() and 1 or 0, AreasOn() and 1 or 0, col[1], col[2], col[3]}
    for _, st in ipairs(stops) do
        sig[#sig + 1] = st[1] .. "/" .. floor(st[2] * 10) .. "/" .. floor(st[3] * 10) .. "/" .. tostring(st[4])
    end
    sig = table.concat(sig, ":")
    if sig == lastMini then return end
    Clear(mmc)
    lastMini = sig
    local sin, cos = math.sin(facing or 0), math.cos(facing or 0)
    local clip = {size, size, size - 2}
    -- map point (0-100 on pmap) to minimap pixels from its top left
    local function P(x, y)
        local ox, oy = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, pmap)
        if not ox then return end
        -- the same sums HereBeDragons-Pins uses for minimap icons
        local dx, dy = wx - ox, wy - oy
        if rotate then dx, dy = dx * cos - dy * sin, dx * sin + dy * cos end
        return size + dx / radius * size, size + dy / radius * size
    end
    for _, s in ipairs(stops) do
        if s[4] and s[4].areaZone == pmap then
            local pts = {}
            for _, p in ipairs(Rounded(s[4])) do
                local x, y = P(p[1], p[2])
                if not x then pts = nil break end
                pts[#pts + 1] = {x, y}
            end
            if pts then
                Fill(mmc, pts, AREA_FILL, 2, clip)
                Outline(mmc, pts, AREA_EDGE, 2, clip)
            end
        end
    end
    if not RouteOn() then return end
    local tlines = tv and tv.Polylines(pmap, PlayerLevel())
    if tlines and #tlines > 0 then
        for _, line in ipairs(tlines) do
            local route = {}
            for _, p in ipairs(line) do
                local x, y = P(p[1], p[2])
                if x then route[#route + 1] = {x, y} end
            end
            RouteLeg(mmc, route, 1.5, clip)
        end
        return
    end
    local route = {}
    for _, p in ipairs(RoutePoints(pmap, px * 100, py * 100, stops, PlayerLevel())) do
        local x, y = P(p[1], p[2])
        if x then route[#route + 1] = {x, y} end
    end
    RouteLeg(mmc, route, 1.5, clip)
end

function tr.DrawMinimap()
    tr.waited = false
    DrawMinimap()
    -- part of the route waited for its search: draw again next frame
    if tr.waited then lastMini = nil end
end

tr.draw = {Fill = Fill, ClipSegment = ClipSegment, Smooth = Smooth, Upcoming = Upcoming, RoutePoints = RoutePoints}

if CreateFrame and C_Timer and C_Timer.NewTicker then
    local function Safe(fn)
        local ok, err = pcall(fn)
        if not ok and addon.comms and addon.comms.PrettyDebug then addon.comms.PrettyDebug(tostring(err)) end
    end
    C_Timer.NewTicker(MAP_TICK, function()
        local wm = _G.WorldMapFrame
        if wm and wm:IsShown() then Safe(tr.DrawMap) elseif wmc then Clear(wmc) end
    end)
    C_Timer.NewTicker(MINI_TICK, function() Safe(tr.DrawMinimap) end)
end
