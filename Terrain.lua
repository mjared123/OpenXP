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
-- The area is shaded on the world map and the minimap.
--
-- The way to the arrow's target is drawn on the world map as a glowing
-- purple line, round mountains and packs the same way the arrow goes.
-- The spawns of what the current step needs get a small mark too (from
-- Questie's data when it's installed).

local MAP_TICK = 0.25
local ROUTE_GLOW = {0.62, 0.18, 1.0, 0.35}
local ROUTE_CORE = {0.85, 0.45, 1.0, 1.0}
local AREA_FILL = {0.25, 0.6, 1.0, 0.22}
local AREA_EDGE = {0.35, 0.75, 1.0, 0.9}
local PIN_SIZE = 12
local PIN_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local WHITE = "Interface\\Buttons\\WHITE8X8"

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
-- Drawing
---------------------------------------------------------------------------

local function Canvas()
    local wm = _G.WorldMapFrame
    if not (wm and wm:IsShown() and wm.GetCanvas) then return end
    local ok, canvas = pcall(wm.GetCanvas, wm)
    if ok and canvas then return canvas, wm:GetMapID() end
end

local overlay
local pool = {lines = {}, glows = {}, fills = {}, pins = {}, dots = {}}
local used = {}

local function Overlay(canvas)
    if not overlay then
        overlay = CreateFrame("Frame", nil, canvas)
        overlay:SetAllPoints(canvas)
        overlay:SetFrameLevel((canvas:GetFrameLevel() or 1) + 20)
    elseif overlay:GetParent() ~= canvas then
        overlay:SetParent(canvas)
        overlay:SetAllPoints(canvas)
    end
    return overlay
end

local function Take(kind, make)
    used[kind] = (used[kind] or 0) + 1
    local list = pool[kind]
    local o = list[used[kind]]
    if not o then
        o = make()
        list[used[kind]] = o
    end
    o:Show()
    return o
end

local function HideAll()
    for kind, list in pairs(pool) do
        for i = 1, #list do list[i]:Hide() end
        used[kind] = 0
    end
end

local function DrawLine(kind, color, thickness, x1, y1, x2, y2, w, h)
    local l = Take(kind, function()
        local line = overlay:CreateLine(nil, kind == "glows" and "ARTWORK" or "OVERLAY")
        line:SetTexture(WHITE)
        return line
    end)
    l:SetVertexColor(unpack(color))
    l:SetThickness(thickness)
    l:SetStartPoint("TOPLEFT", overlay, x1 / 100 * w, -y1 / 100 * h)
    l:SetEndPoint("TOPLEFT", overlay, x2 / 100 * w, -y2 / 100 * h)
end

local function DrawDot(kind, color, size, x, y, w, h, texture)
    local t = Take(kind, function() return overlay:CreateTexture(nil, "OVERLAY") end)
    t:SetTexture(texture or WHITE)
    t:SetVertexColor(unpack(color))
    t:SetSize(size, size)
    t:ClearAllPoints()
    t:SetPoint("CENTER", overlay, "TOPLEFT", x / 100 * w, -y / 100 * h)
end

local function DrawArea(a, w, h, scale)
    local poly = a.area
    -- shade: one square per 1% cell inside the outline
    local x0, y0, x1, y1 = 100, 100, 0, 0
    for _, p in ipairs(poly) do
        x0, y0, x1, y1 = min(x0, p[1]), min(y0, p[2]), max(x1, p[1]), max(y1, p[2])
    end
    for y = floor(y0), floor(y1) do
        for x = floor(x0), floor(x1) do
            if InsidePoly(poly, x + 0.5, y + 0.5) then
                local f = Take("fills", function() return overlay:CreateTexture(nil, "ARTWORK") end)
                f:SetTexture(WHITE)
                f:SetVertexColor(unpack(AREA_FILL))
                f:SetSize(w / 100 + 0.5, h / 100 + 0.5)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", overlay, "TOPLEFT", x / 100 * w, -y / 100 * h)
            end
        end
    end
    local j = #poly
    for i = 1, #poly do
        DrawLine("lines", AREA_EDGE, 3 / scale, poly[j][1], poly[j][2], poly[i][1], poly[i][2], w, h)
        j = i
    end
end

-- the way from (ax, ay) to (bx, by): corners after the start, ending at the target
local routeCache = {}
local function Route(map, ax, ay, bx, by, level)
    local key = map .. ":" .. floor(ax) .. ":" .. floor(ay) .. ":" .. floor(bx * 10) .. ":" .. floor(by * 10) .. ":" .. level
    if routeCache.key ~= key then
        routeCache.key = key
        routeCache.pts = tr.FindPath(map, ax, ay, bx, by, level) or {{bx, by}}
    end
    return routeCache.pts
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

local function ActiveSteps()
    local frame = addon.RXPFrame
    return frame and frame.activeSteps or {}
end

function tr.DrawMap()
    local canvas, map = Canvas()
    if not canvas then return end
    Overlay(canvas)
    HideAll()
    local d = addon.terrainData and addon.terrainData[map]
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = _G.WorldMapFrame.GetCanvasScale and _G.WorldMapFrame:GetCanvasScale() or 1

    -- kill/loot areas of the active steps
    for _, step in pairs(ActiveSteps()) do
        local a = StepArea(step)
        if a and a.areaZone == map then DrawArea(a, w, h, scale) end
    end

    -- the spawns the active steps need
    if d and d.area then
        local seen = {}
        for _, step in pairs(ActiveSteps()) do
            for _, e in ipairs(step.elements or {}) do
                if e.questId and e.obj and not e.completed and not e.skip then
                    for _, pt in ipairs(ObjectiveSpawns(e.questId, e.obj, d.area)) do
                        local key = floor(pt[1] * 10) .. "," .. floor(pt[2] * 10)
                        if not seen[key] then
                            seen[key] = true
                            DrawDot("pins", {1, 1, 1, 0.9}, PIN_SIZE / scale, pt[1], pt[2], w, h, PIN_TEXTURE)
                        end
                    end
                end
            end
        end
    end

    -- the way to where the arrow points, from where you stand
    local af = addon.arrowFrame
    local real = af and af.element
    local px, py, pmap = HBD:GetPlayerZonePosition()
    if not (real and px and pmap == map) or (af.IsShown and not af:IsShown()) then return end
    local target = tr.AreaTarget and tr.AreaTarget(real) or real
    if target.inside or not target.wx then return end
    local bx, by = HBD:GetZoneCoordinatesFromWorld(target.wx, target.wy, map)
    if not bx then return end
    px, py, bx, by = px * 100, py * 100, bx * 100, by * 100
    local pts = d and d.rows and Route(map, px, py, bx, by, PlayerLevel()) or {{bx, by}}
    local ax, ay = px, py
    for _, p in ipairs(pts) do
        DrawLine("glows", ROUTE_GLOW, 12 / scale, ax, ay, p[1], p[2], w, h)
        DrawLine("lines", ROUTE_CORE, 4 / scale, ax, ay, p[1], p[2], w, h)
        DrawDot("dots", ROUTE_CORE, 8 / scale, p[1], p[2], w, h)
        ax, ay = p[1], p[2]
    end
end

---------------------------------------------------------------------------
-- Minimap: the area, shaded
---------------------------------------------------------------------------

local HBDPins = LibStub("HereBeDragons-Pins-2.0", true)
local MINI_OWNER = "OpenXPAreas"
local miniDots, miniShown = {}, nil

local function MiniDot(i)
    local f = miniDots[i]
    if not f then
        f = CreateFrame("Frame")
        f:SetSize(9, 9)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetTexture(WHITE)
        t:SetVertexColor(AREA_FILL[1], AREA_FILL[2], AREA_FILL[3], 0.45)
        miniDots[i] = f
    end
    return f
end

function tr.DrawMinimap()
    if not HBDPins then return end
    local a
    for _, step in pairs(ActiveSteps()) do
        a = StepArea(step)
        if a then break end
    end
    if a == miniShown then return end
    HBDPins:RemoveAllMinimapIcons(MINI_OWNER)
    miniShown = a
    if not a then return end
    local poly = a.area
    local x0, y0, x1, y1 = 100, 100, 0, 0
    for _, p in ipairs(poly) do
        x0, y0, x1, y1 = min(x0, p[1]), min(y0, p[2]), max(x1, p[1]), max(y1, p[2])
    end
    local n = 0
    for y = floor(y0), floor(y1) do
        for x = floor(x0), floor(x1) do
            if InsidePoly(poly, x + 0.5, y + 0.5) then
                n = n + 1
                HBDPins:AddMinimapIconMap(MINI_OWNER, MiniDot(n), a.areaZone, (x + 0.5) / 100, (y + 0.5) / 100, false, false)
            end
        end
    end
end

if CreateFrame and C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(MAP_TICK, function()
        local wm = _G.WorldMapFrame
        if wm and wm:IsShown() then
            local ok, err = pcall(tr.DrawMap)
            if not ok and addon.comms and addon.comms.PrettyDebug then addon.comms.PrettyDebug(tostring(err)) end
        elseif overlay then
            HideAll()
        end
        local ok, err = pcall(tr.DrawMinimap)
        if not ok and addon.comms and addon.comms.PrettyDebug then addon.comms.PrettyDebug(tostring(err)) end
    end)
end
