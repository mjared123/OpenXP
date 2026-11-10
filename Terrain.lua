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

local function StepArea(step)
    for _, e in ipairs(step and step.elements or {}) do
        if e.area and e.areaZone then return e end
    end
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
    c.nl, c.nt = 0, 0
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
    local y = y0 + step / 2
    local xs = {}
    while y < y1 do
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
            if b > a then Line(c, color, step + 0.5, a, y, b, y, "ARTWORK") end
        end
        y = y + step
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
local function RouteLeg(c, pts, thickness, clip)
    if #pts < 2 then return end
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
    for i = first, min(#guide.steps, first + STEPS_AHEAD) do
        local step = guide.steps[i]
        if step and not step.completed and not step.skip then
            local map, x, y, a = StepTarget(step)
            if map then out[#out + 1] = {map, x, y, a} end
        end
    end
    return out
end

-- Map points (0-100) of the route on `map` starting at (px, py), or {}
local legCache = {}
local function RoutePoints(map, px, py, stops, level)
    local key = map .. ":" .. floor(px) .. ":" .. floor(py) .. ":" .. level
    for _, s in ipairs(stops) do key = key .. ":" .. s[1] .. "/" .. floor(s[2] * 10) .. "/" .. floor(s[3] * 10) end
    if legCache.key == key then return legCache.pts end
    local pts = {{px, py}}
    local ax, ay = px, py
    for k, s in ipairs(stops) do
        if s[1] ~= map then break end
        local inside = s[4] and InsidePoly(s[4].area, ax, ay)
        if not (k == 1 and inside) then
            local path = Grid(map) and tr.FindPath(map, ax, ay, s[2], s[3], level) or nil
            for _, p in ipairs(path or {{s[2], s[3]}}) do pts[#pts + 1] = {p[1], p[2]} end
            ax, ay = s[2], s[3]
        end
    end
    legCache.key, legCache.pts = key, pts
    return pts
end

local spawnCache = {}
local function ObjectiveSpawns(questId, objIndex, area)
    local key = questId .. ":" .. objIndex .. ":" .. area
    if spawnCache[key] ~= nil then return spawnCache[key] end
    local QGet = addon.card and addon.card.QGet
    local q = QGet and QGet("Quest", questId)
    if not q then return {} end -- Questie not ready yet: try again later
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
                    for _, pt in ipairs(ObjectiveSpawns(e.questId, e.obj, d.area)) do
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
    if px and pmap == map and #stops > 0 then
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

function tr.DrawMinimap()
    local mm = _G.Minimap
    if not (mm and mm:IsShown()) then return end
    if not mmc then mmc = NewCanvas(mm, mm:GetFrameLevel() + 2) end
    Clear(mmc)
    local stops = Upcoming()
    if #stops == 0 then return end
    local wx, wy, inst = HBD:GetPlayerWorldPosition()
    local px, py, pmap = HBD:GetPlayerZonePosition()
    if not (wx and px) then return end
    local radius = MinimapRadius()
    local size = mm:GetWidth() / 2
    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    if rotate and not facing then return end
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
    local route = {}
    for _, p in ipairs(RoutePoints(pmap, px * 100, py * 100, stops, PlayerLevel())) do
        local x, y = P(p[1], p[2])
        if x then route[#route + 1] = {x, y} end
    end
    RouteLeg(mmc, route, 1.5, clip)
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
