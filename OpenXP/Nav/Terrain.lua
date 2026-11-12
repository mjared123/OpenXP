-- Walking terrain: finds a way around mountains, cliffs, water and packs of
-- high-level mobs on a grid of each zone map (one cell per 1% of the map),
-- from Data/Terrain.lua (built by tools/terrain.py).
--
-- The arrow (Nav/Target.lua), the route line (Nav/MapDraw.lua) and the
-- travel planner (Nav/Travel.lua) all ask FindPath / FollowPath, which
-- remember every way they work out.
local _, OXP = ...

local Terrain = {}
OXP.Terrain = Terrain

local floor, sqrt, max, min, abs = math.floor, math.sqrt, math.max, math.min, math.abs

local N = 100           -- grid cells per side
local WATER = 3.0       -- swimming costs this much more than running
local ROAD = 0.65       -- a road counts as this much of the same distance off it
local SLACK = 1.02      -- a straight cut may cost this much more than the cells it replaces
-- extra cost per cell near a pack, by levels above you
local DANGER = { [-2] = 1.0, [-1] = 1.0, [0] = 1.0, [1] = 1.5, [2] = 2.0, [3] = 3.0, [4] = 10.0 }
local DANGER_MAX = 40.0 -- 5+ levels above you
local MILD = 3          -- danger under this is a pack near your level: roads ignore it
local ROAD_DANGER = 1.0 -- and the mobs by a road are this much trouble at most
local NEAR = 1.6        -- cells: a corner counts as reached
local STRAY = 4         -- cells off the way before it's worked out again
local REPLAN = 15       -- seconds: work a followed way out again at most this often
local MOVED = 2         -- cells: a target that moved less than this keeps its way

local grids = {}        -- map -> { cells, kx, ky, packs, danger } or false

function Terrain.Data(map)
    return OXP.terrainData and OXP.terrainData[map]
end

------------------------------------------------------------------------
-- Walls you record in game (/oxp wall): town walls and the like the
-- terrain data doesn't have. Kept in OpenXPDB.walls[map] as lines of map
-- points; every cell a line crosses is blocked.
------------------------------------------------------------------------

local function SavedWalls()
    local db = OXP.db
    if not db then return nil end
    db.walls = db.walls or {}
    return db.walls
end
Terrain.SavedWalls = SavedWalls

function Terrain.ApplyWalls(map, cells)
    local saved = SavedWalls()
    for _, line in ipairs(saved and saved[map] or {}) do
        for k = 1, #line - 1 do
            local a, b = line[k], line[k + 1]
            local steps = floor(max(abs(b[1] - a[1]), abs(b[2] - a[2])) * 10) + 1
            local lx, ly
            for s = 0, steps do
                local x = floor(a[1] + (b[1] - a[1]) * s / steps) + 1
                local y = floor(a[2] + (b[2] - a[2]) * s / steps) + 1
                if x >= 1 and y >= 1 and x <= N and y <= N then
                    cells[(y - 1) * N + x] = 0
                    -- a diagonal step: close the corner so the way can't slip through
                    if lx and lx ~= x and ly ~= y and ly >= 1 and ly <= N then cells[(ly - 1) * N + x] = 0 end
                end
                lx, ly = x, y
            end
        end
    end
end
local function Grid(map)
    local g = grids[map]
    if g ~= nil then return g or nil end
    local d = Terrain.Data(map)
    if not d or not d.rows then
        grids[map] = false
        return nil
    end
    local cells = {}
    for y = 1, N do
        local row = d.rows[y] or ""
        for x = 1, N do
            local c = row:sub(x, x)
            cells[(y - 1) * N + x] = (c == "#" and 0) or (c == "~" and 2) or (c == "=" and 3) or 1
        end
    end
    Terrain.ApplyWalls(map, cells)
    g = { cells = cells, kx = d.yards and d.yards[1] or 1, ky = d.yards and d.yards[2] or 1,
          packs = d.packs or {}, danger = {} }
    grids[map] = g
    return g
end
Terrain.Grid = Grid

local FACTOR = { [1] = 1, [2] = WATER, [3] = ROAD }

-- Route style (setting "routeStyle"):
--   roads   follow roads: a road counts as much less than open ground and
--           swimming as a lot more, so the way goes to the nearest road and
--           keeps to it (safer, and what 1.x felt like)
--   direct  the shortest way: roads only a little cheaper, swimming at its
--           real speed (about two thirds of running)
local STYLES = {
    roads = { water = 4.0, road = 0.4 },
    direct = { water = 1.5, road = 0.9 },
}
local style

local function Style()
    local s = OXP.settings and OXP.settings.routeStyle
    if not STYLES[s] then s = "roads" end
    if s ~= style then
        style = s
        FACTOR[2], FACTOR[3] = STYLES[s].water, STYLES[s].road
    end
    return s
end
Terrain.Style = Style

local function CellCost(k, d)
    d = d or 0
    if k == 3 then d = d < MILD and 0 or min(d, ROAD_DANGER) end
    return FACTOR[k] + d
end

local function Kind(g, x, y)
    if x < 1 or y < 1 or x > N or y > N then return 0 end
    return g.cells[(y - 1) * N + x]
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

-- binary heap in two arrays (f values, cell indexes): no table per cell
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

-- Cost of the straight line between two cell middles, or nil when blocked.
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
        if k == 0 then return nil end
        if s > 0 then total = total + each * CellCost(k, danger[(y - 1) * N + x]) end
    end
    return total
end

-- A run of cells becomes one straight line only when the line costs no more
-- than the run, so the way doesn't leave a road to cut through mobs.
local function SmoothCells(g, danger, cells, cost)
    local out = { cells[1] }
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

-- A* from cell (sx, sy) to (tx, ty). Returns the corners between them as
-- map points, or false when the straight line is fine or there's no way.
local function Search(g, level, sx, sy, tx, ty)
    local danger = Danger(g, level)
    sx, sy = NearestOpen(g, sx, sy)
    tx, ty = NearestOpen(g, tx, ty)
    if sx == tx and sy == ty then return false end
    local cells = g.cells
    local kx, ky = g.kx, g.ky
    local diag = sqrt(kx * kx + ky * ky)
    local SX = { 1, -1, 0, 0, 1, 1, -1, -1 }
    local SY = { 0, 0, 1, -1, 1, -1, 1, -1 }
    local SC = { kx, kx, ky, ky, diag, diag, diag, diag }
    -- the cheapest a cell can cost (a road): keeps the estimate from ever
    -- overshooting, so the search really finds the road
    local hk = min(1, FACTOR[3])
    local function H(x, y)
        local dx, dy = (x - tx) * kx, (y - ty) * ky
        return sqrt(dx * dx + dy * dy) * hk
    end
    local function K(x, y)
        if x < 1 or y < 1 or x > N or y > N then return 0 end
        return cells[(y - 1) * N + x]
    end
    local start, goal = (sy - 1) * N + sx, (ty - 1) * N + tx
    local best, came = { [start] = 0 }, {}
    local hf, hi = {}, {}
    Push(hf, hi, 0, H(sx, sy), start)
    local n = 1
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
        rev[#rev + 1] = { (i - 1) % N + 1, floor((i - 1) / N) + 1 }
        rcost[#rcost + 1] = best[i]
        i = came[i]
    end
    local list, cost = {}, {}
    for k = #rev, 1, -1 do
        list[#list + 1] = rev[k]
        cost[#cost + 1] = rcost[k]
    end
    list = SmoothCells(g, danger, list, cost)
    if #list <= 2 then return false end
    local pts = {}
    for k = 2, #list - 1 do pts[#pts + 1] = { list[k][1] - 0.5, list[k][2] - 0.5 } end
    return pts
end

local TimedSearch = OXP.Perf.Wrap("terrain path search", Search)
local found, foundCount = {}, 0
local FOUND_MAX = 600

-- Searches cost a few milliseconds each, so drawing code (lazy) starts at
-- most this many per frame and draws the rest of the route a frame later.
Terrain.lazyPerFrame = 1
local frameAt, frameSearches = nil, 0

function Terrain.SearchesThisFrame()
    local now = GetTime and GetTime() or 0
    if now ~= frameAt then frameAt, frameSearches = now, 0 end
    return frameSearches
end

--- The way from (ax, ay) to (bx, by) on a zone map (0-100) for a character
--- of this level: corners after the start, ending at the target; nil when
--- the straight line is fine or the map has no terrain. lazy: returns nil,
--- true ("not yet") when this frame already had its searches.
function Terrain.FindPath(map, ax, ay, bx, by, level, lazy)
    local g = Grid(map)
    if not g then return nil end
    level = floor(level or 0)
    local sx, sy, tx, ty = floor(ax) + 1, floor(ay) + 1, floor(bx) + 1, floor(by) + 1
    local key = map .. ":" .. sx .. ":" .. sy .. ":" .. tx .. ":" .. ty .. ":" .. level .. ":" .. Style()
    local corners = found[key]
    if corners == nil then
        local used = Terrain.SearchesThisFrame()
        if lazy and used >= Terrain.lazyPerFrame then
            Terrain.waited = true
            return nil, true
        end
        frameSearches = used + 1
        corners = TimedSearch(g, level, sx, sy, tx, ty)
        if foundCount >= FOUND_MAX then found, foundCount = {}, 0 end
        found[key] = corners
        foundCount = foundCount + 1
    end
    if not corners then return nil end
    local pts = {}
    for k = 1, #corners do pts[k] = { corners[k][1], corners[k][2] } end
    pts[#pts + 1] = { bx, by }
    return pts
end

-- A way from where you stand, kept in `slot` between calls: while you follow
-- it, it's only trimmed as you pass corners and worked out again at most
-- every REPLAN seconds.
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
    for k = f.idx, #pts - 1 do out[#out + 1] = { pts[k][1], pts[k][2] } end
    out[#out + 1] = { bx, by }
    return out
end

local function Strayed(pts, idx, from, ax, ay)
    local p = pts[idx]
    local prev = pts[idx - 1] or from
    if not (p and prev) then return true end
    local vx, vy = p[1] - prev[1], p[2] - prev[2]
    local len2 = vx * vx + vy * vy
    local t = len2 > 0 and max(0, min(1, ((ax - prev[1]) * vx + (ay - prev[2]) * vy) / len2)) or 0
    local qx, qy = prev[1] + vx * t - ax, prev[2] + vy * t - ay
    return qx * qx + qy * qy > STRAY * STRAY
end

function Terrain.FollowPath(slot, map, ax, ay, bx, by, level, lazy)
    if not Grid(map) then return nil end
    level = floor(level or 0)
    local now = GetTime and GetTime() or 0
    local f = follows[slot]
    local same = f and f.map == map and f.level == level and f.style == Style()
    if same then
        local mx, my = f.bx - bx, f.by - by
        same = mx * mx + my * my <= MOVED * MOVED
    end
    if same and now - f.at < REPLAN and not Strayed(f.pts, f.idx, f.from, ax, ay) then
        return Remaining(f, ax, ay, bx, by)
    end
    local pts, pending = Terrain.FindPath(map, ax, ay, bx, by, level, lazy)
    if pending then
        if same then return Remaining(f, ax, ay, bx, by) end
        return nil, true
    end
    f = { map = map, level = level, style = Style(), bx = bx, by = by, at = now, from = { ax, ay }, idx = 1,
          pts = pts or { { bx, by } } }
    follows[slot] = f
    return Remaining(f, ax, ay, bx, by)
end

------------------------------------------------------------------------
-- For the arrow: the next corner on the way to a world spot
------------------------------------------------------------------------

local state = {}
function Terrain.Reset() state = {} end

--- Where the arrow should point on the way to `target` ({wx, wy, instance}):
--- {wx, wy}, or nil for straight at it. map: the player's zone map.
function Terrain.Route(target, px, py, inst, map)
    if not (map and target and target.wx and px) or target.instance ~= inst then return nil end
    if not Grid(map) then return nil end
    local ax, ay = OXP.Places.ToZone(px, py, map)
    local bx, by = OXP.Places.ToZone(target.wx, target.wy, map)
    if not (ax and bx) or bx < 0 or by < 0 or bx > 100 or by > 100 then return nil end
    local level = OXP.Player.level or 1
    local now = GetTime and GetTime() or 0

    local pts = state.pts
    local mx, my = (state.bx or bx) - bx, (state.by or by) - by
    local fresh = state.target ~= target or state.map ~= map or state.level ~= level
        or mx * mx + my * my > MOVED * MOVED
    if not fresh and pts then
        while state.idx <= #pts do
            local p = pts[state.idx]
            local dx, dy = p[1] - ax, p[2] - ay
            if dx * dx + dy * dy > NEAR * NEAR then break end
            state.idx = state.idx + 1
        end
        if now - (state.at or 0) >= 2 and Strayed(pts, state.idx, state.from, ax, ay) then fresh = true end
        if now - (state.at or 0) >= REPLAN and state.idx > 1 then fresh = true end
    end
    if fresh or (not pts and now - (state.at or 0) >= REPLAN) then
        state = { target = target, bx = bx, by = by, map = map, level = level, at = now, from = { ax, ay }, idx = 1 }
        state.pts = Terrain.FindPath(map, ax, ay, bx, by, level)
        pts = state.pts
    end
    if not pts or state.idx >= #pts then return nil end
    local p = pts[state.idx]
    local wx, wy = OXP.Places.ToWorld(map, p[1], p[2])
    if not wx then return nil end
    return { wx, wy }
end

------------------------------------------------------------------------
-- Polygon helpers (kill/loot areas)
------------------------------------------------------------------------

function Terrain.InsidePoly(poly, x, y)
    local c, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then c = not c end
        j = i
    end
    return c
end

--- Nearest point on the polygon's edge to (x, y); kx, ky: yards per map unit.
function Terrain.NearestEdge(poly, x, y, kx, ky)
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

------------------------------------------------------------------------
-- /oxp wall
------------------------------------------------------------------------

local recording

local function WallsChanged(map)
    grids[map] = nil
    found, foundCount = {}, 0
    follows = {}
    Terrain.Reset()
    OXP.Send("ARROW_CHANGED")
end

local function WallCommand(args)
    local cmd = (OXP.Util.Trim(args or ""):match("^(%S*)") or ""):lower()
    local px, py, map = OXP.Places.PlayerZone()
    if cmd == "" or cmd == "add" then
        if not px then return OXP.Print("Can't tell where you are right now.") end
        if not Terrain.Data(map) then return OXP.Print("This map has no terrain data (cities are left to the arrow).") end
        if recording and recording.map ~= map then recording = nil end
        recording = recording or { map = map, pts = {} }
        recording.pts[#recording.pts + 1] = { floor(px * 100 + 0.5) / 100, floor(py * 100 + 0.5) / 100 }
        if #recording.pts == 1 then
            OXP.Print("Wall started at %.1f, %.1f. Walk along the wall and type /oxp wall at each corner, then /oxp wall done at its end. Leave gates out.", px, py)
        else
            OXP.Print("Corner %d at %.1f, %.1f. /oxp wall for the next, /oxp wall done to finish.", #recording.pts, px, py)
        end
    elseif cmd == "done" or cmd == "save" then
        if not recording or #recording.pts < 2 then
            return OXP.Print("A wall needs at least two spots: stand at one end and type /oxp wall, then at the other.")
        end
        local saved = SavedWalls()
        saved[recording.map] = saved[recording.map] or {}
        table.insert(saved[recording.map], recording.pts)
        OXP.Print("Saved a wall with %d spots. The arrow and the route line go around it from now on.", #recording.pts)
        local m = recording.map
        recording = nil
        WallsChanged(m)
    elseif cmd == "undo" then
        if recording and #recording.pts > 0 then
            table.remove(recording.pts)
            return OXP.Print("Removed the last spot (%d left).", #recording.pts)
        end
        OXP.Print("Nothing to undo.")
    elseif cmd == "clear" then
        local saved = SavedWalls()
        local list = saved and map and saved[map]
        local n = 0
        -- any wall passing within 3 map units of you
        local function near(line)
            for k = 1, #line - 1 do
                local a, b = line[k], line[k + 1]
                local vx, vy = b[1] - a[1], b[2] - a[2]
                local len2 = vx * vx + vy * vy
                local s = len2 > 0 and max(0, min(1, ((px - a[1]) * vx + (py - a[2]) * vy) / len2)) or 0
                local dx, dy = a[1] + vx * s - px, a[2] + vy * s - py
                if dx * dx + dy * dy <= 9 then return true end
            end
        end
        for i = #(list or {}), 1, -1 do
            if near(list[i]) then
                table.remove(list, i)
                n = n + 1
            end
        end
        recording = nil
        WallsChanged(map)
        OXP.Print("Removed %d wall(s) near you.", n)
    else
        OXP.Print("/oxp wall: mark a wall the arrow tries to walk through. Stand at one end and type /oxp wall, again at each corner, /oxp wall done at the end. /oxp wall undo, /oxp wall clear (walls near you).")
    end
end
Terrain.WallCommand = WallCommand
OXP.AddCommand("wall", "mark a wall the arrow walks through: /oxp wall, /oxp wall done, clear", WallCommand)
