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

local tr = {}
addon.terrain = tr

local N = 100           -- grid cells per side
local WATER = 3.0       -- swimming costs this much more than running
local DANGER = {[3] = 3.0, [4] = 10.0}
local DANGER_MAX = 40.0 -- 5+ levels above you
local NEAR = 1.6        -- cells: a corner counts as reached
local STRAY = 4         -- cells off the way before it's worked out again
local REPLAN = 15       -- seconds: work the way out again at most this often

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
            cells[(y - 1) * N + x] = (c == "#" and 0) or (c == "~" and 2) or 1
        end
    end
    g = {cells = cells, kx = d.yards and d.yards[1] or 1, ky = d.yards and d.yards[2] or 1,
         packs = d.packs or {}, danger = {}}
    grids[map] = g
    return g
end
tr.Grid = Grid

-- 0 blocked, 1 open, 2 water
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
        if over >= 3 then
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

-- Binary heap of {f, index}
local function Push(h, f, i)
    local n = #h + 1
    h[n] = {f, i}
    while n > 1 do
        local p = floor(n / 2)
        if h[p][1] <= h[n][1] then break end
        h[p], h[n] = h[n], h[p]
        n = p
    end
end

local function Pop(h)
    local top = h[1]
    local n = #h
    h[1] = h[n]
    h[n] = nil
    n = n - 1
    local i = 1
    while true do
        local l, r, s = i * 2, i * 2 + 1, i
        if l <= n and h[l][1] < h[s][1] then s = l end
        if r <= n and h[r][1] < h[s][1] then s = r end
        if s == i then break end
        h[i], h[s] = h[s], h[i]
        i = s
    end
    return top
end

-- Straight line from cell a to cell b no worse than the cells it replaces.
local function Clear(g, danger, ax, ay, bx, by, water, limit)
    local steps = floor(max(abs(bx - ax), abs(by - ay)) * 4) + 1
    for s = 0, steps do
        local t = s / steps
        local x = floor(ax + 0.5 + (bx - ax) * t)
        local y = floor(ay + 0.5 + (by - ay) * t)
        local k = Kind(g, x, y)
        if k == 0 or (k == 2 and not water) then return false end
        if (danger[(y - 1) * N + x] or 0) > limit then return false end
    end
    return true
end

-- Cells are 1-based {x, y}; map coordinates of a cell's middle are x - 0.5.
local function Smooth(g, danger, cells)
    local out = {cells[1]}
    local i = 1
    while i < #cells do
        local j = #cells
        while j > i + 1 do
            local water, limit = false, 0
            for k = i, j do
                local c = cells[k]
                if Kind(g, c[1], c[2]) == 2 then water = true end
                local dv = danger[(c[2] - 1) * N + c[1]] or 0
                if dv > limit then limit = dv end
            end
            if Clear(g, danger, cells[i][1], cells[i][2], cells[j][1], cells[j][2], water, limit) then break end
            j = j - 1
        end
        out[#out + 1] = cells[j]
        i = j
    end
    return out
end

-- The way from (ax, ay) to (bx, by), zone map coordinates 0-100, for a
-- character of this level. Returns a list of corners {x, y} (map
-- coordinates) after the start, ending at the target, or nil when the
-- straight line is fine or there's no terrain for the map.
function tr.FindPath(map, ax, ay, bx, by, level)
    local g = Grid(map)
    if not g then return end
    local danger = Danger(g, level)
    local sx, sy = NearestOpen(g, floor(ax) + 1, floor(ay) + 1)
    local tx, ty = NearestOpen(g, floor(bx) + 1, floor(by) + 1)
    if sx == tx and sy == ty then return end
    local kx, ky = g.kx, g.ky
    local diag = sqrt(kx * kx + ky * ky)
    local steps = {{1, 0, kx}, {-1, 0, kx}, {0, 1, ky}, {0, -1, ky},
                   {1, 1, diag}, {1, -1, diag}, {-1, 1, diag}, {-1, -1, diag}}
    local function H(x, y)
        local dx, dy = (x - tx) * kx, (y - ty) * ky
        return sqrt(dx * dx + dy * dy)
    end
    local start, goal = (sy - 1) * N + sx, (ty - 1) * N + tx
    local best, came = {[start] = 0}, {}
    local heap = {}
    Push(heap, H(sx, sy), start)
    local found
    while #heap > 0 do
        local top = Pop(heap)
        local i = top[2]
        if i == goal then found = true break end
        local gi = best[i]
        local x, y = (i - 1) % N + 1, floor((i - 1) / N) + 1
        if top[1] - H(x, y) <= gi + 0.001 then
            for _, s in ipairs(steps) do
                local nx, ny = x + s[1], y + s[2]
                local k = Kind(g, nx, ny)
                if k ~= 0 and not (s[1] ~= 0 and s[2] ~= 0 and
                        (Kind(g, x + s[1], y) == 0 or Kind(g, x, y + s[2]) == 0)) then
                    local ni = (ny - 1) * N + nx
                    local cost = s[3] * (k == 2 and WATER or 1) + (danger[ni] or 0) * s[3]
                    local ng = gi + cost
                    if not best[ni] or ng < best[ni] then
                        best[ni] = ng
                        came[ni] = i
                        Push(heap, ng + H(nx, ny), ni)
                    end
                end
            end
        end
    end
    if not found then return end
    local cells = {}
    local i = goal
    while i do
        table.insert(cells, 1, {(i - 1) % N + 1, floor((i - 1) / N) + 1})
        i = came[i]
    end
    cells = Smooth(g, danger, cells)
    if #cells <= 2 then return end -- straight there
    local pts = {}
    for k = 2, #cells - 1 do
        pts[#pts + 1] = {cells[k][1] - 0.5, cells[k][2] - 0.5}
    end
    pts[#pts + 1] = {bx, by}
    return pts
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
    local fresh = state.target ~= target or state.tx ~= target.wx or state.ty ~= target.wy
        or state.map ~= map or state.level ~= level
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
        state = {target = target, tx = target.wx, ty = target.wy, map = map, level = level,
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
