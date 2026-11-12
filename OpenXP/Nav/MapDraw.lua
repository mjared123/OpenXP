-- Lines on the world map and the minimap: smooth blue kill/loot areas and the
-- purple route from you through the next few steps (each leg bending round
-- mountains and high-level packs the way the arrow goes), or the whole trip
-- when the next step is in another zone (Nav/Travel.lua).
--
-- Areas are smoothed outlines filled with thin horizontal strips (WoW has no
-- polygon fill); on the minimap everything is clipped to its round edge.
local _, OXP = ...

local Draw = {}
OXP.MapDraw = Draw

local Places, Terrain, Areas, Engine = OXP.Places, OXP.Terrain, OXP.Areas, OXP.Engine
local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max

local AREA_FILL = { 0.20, 0.55, 1.0, 0.30 }
local AREA_EDGE = { 0.35, 0.70, 1.0, 0.95 }
local PIN_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local STEPS_AHEAD = 4
local MAP_TICK, MINI_TICK = 0.25, 0.05

local function RouteOn() return OXP.settings.mapRoute ~= false end

local routeColor = { 0.72, 0.42, 1.0, 0.92 }
local function RouteColor()
    local c = OXP.settings.routeColor
    if c and c[1] then routeColor[1], routeColor[2], routeColor[3] = c[1], c[2], c[3] end
    return routeColor
end

------------------------------------------------------------------------
-- Geometry
------------------------------------------------------------------------

-- Chaikin corner cutting: a rounder closed outline
local function SmoothClosed(poly, rounds)
    for _ = 1, rounds do
        local out = {}
        for i = 1, #poly do
            local a, b = poly[i], poly[i % #poly + 1]
            out[#out + 1] = { a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25 }
            out[#out + 1] = { a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75 }
        end
        poly = out
    end
    return poly
end
Draw.SmoothClosed = SmoothClosed

-- the same for an open line, keeping both ends
local function SmoothOpen(pts, rounds)
    for _ = 1, rounds do
        if #pts < 3 then return pts end
        local out = { pts[1] }
        for i = 1, #pts - 1 do
            local a, b = pts[i], pts[i + 1]
            if i > 1 then out[#out + 1] = { a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25 } end
            if i < #pts - 1 then out[#out + 1] = { a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75 } end
        end
        out[#out + 1] = pts[#pts]
        pts = out
    end
    return pts
end

local rounded = setmetatable({}, { __mode = "k" })
local function Rounded(a)
    local s = rounded[a.poly]
    if not s then
        s = SmoothClosed(a.poly, 3)
        rounded[a.poly] = s
    end
    return s
end

--- The part of segment a-b inside circle {cx, cy, r}, or nil.
function Draw.ClipSegment(ax, ay, bx, by, clip)
    if not clip then return ax, ay, bx, by end
    local dx, dy = bx - ax, by - ay
    local fx, fy = ax - clip[1], ay - clip[2]
    local A = dx * dx + dy * dy
    if A == 0 then return nil end
    local B = 2 * (fx * dx + fy * dy)
    local C = fx * fx + fy * fy - clip[3] * clip[3]
    local disc = B * B - 4 * A * C
    if disc < 0 then return nil end
    disc = sqrt(disc)
    local t0, t1 = max(0, (-B - disc) / (2 * A)), min(1, (-B + disc) / (2 * A))
    if t1 <= t0 then return nil end
    return ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
end
local ClipSegment = Draw.ClipSegment

------------------------------------------------------------------------
-- A canvas: a frame with pools of lines, strips and textures
------------------------------------------------------------------------

local function NewCanvas(parent, level)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(level)
    return { frame = f, lines = {}, tex = {}, rects = {}, nl = 0, nt = 0, nr = 0 }
end

local function Clear(c)
    for i = 1, #c.lines do c.lines[i]:Hide() end
    for i = 1, #c.tex do c.tex[i]:Hide() end
    for i = 1, #c.rects do c.rects[i]:Hide() end
    c.nl, c.nt, c.nr = 0, 0, 0
end

-- x, y in pixels from the frame's top left (y down)
local function Line(c, color, thickness, x1, y1, x2, y2)
    c.nl = c.nl + 1
    local l = c.lines[c.nl]
    if not l then
        l = c.frame:CreateLine(nil, "OVERLAY")
        l:SetTexture(WHITE)
        c.lines[c.nl] = l
    end
    l:SetVertexColor(color[1], color[2], color[3], color[4])
    l:SetThickness(thickness)
    l:SetStartPoint("TOPLEFT", c.frame, x1, -y1)
    l:SetEndPoint("TOPLEFT", c.frame, x2, -y2)
    l:Show()
end

-- not snapped to the pixel grid, so strips laid edge to edge blend into one fill
local function Rect(c, color, x, y, w, h)
    c.nr = c.nr + 1
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

--- Fill a polygon (pixel points) with strips `step` pixels high, optionally
--- clipped to a circle {cx, cy, r}.
function Draw.Fill(c, pts, color, step, clip)
    local y0, y1 = math.huge, -math.huge
    for _, p in ipairs(pts) do y0, y1 = min(y0, p[2]), max(y1, p[2]) end
    if clip then y0, y1 = max(y0, clip[2] - clip[3]), min(y1, clip[2] + clip[3]) end
    local top = y0
    local y = y0 + step / 2
    local xs = {}
    while top < y1 do
        for k = #xs, 1, -1 do xs[k] = nil end
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

local function Outline(c, pts, color, thickness, clip)
    local j = #pts
    for i = 1, #pts do
        local ax, ay, bx, by = ClipSegment(pts[j][1], pts[j][2], pts[i][1], pts[i][2], clip)
        if ax then Line(c, color, thickness, ax, ay, bx, by) end
        j = i
    end
end

-- One clean line with rounded corners, round joints, a small chevron now
-- and then for the direction, and a dot where it ends.
local function RouteLeg(c, pts, thickness, clip)
    if #pts < 2 or not RouteOn() then return end
    local color = RouteColor()
    pts = SmoothOpen(pts, 2)
    local travelled, nextMark = 0, thickness * 40
    for i = 1, #pts - 1 do
        local ax, ay, bx, by = ClipSegment(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], clip)
        if ax then
            Line(c, color, thickness, ax, ay, bx, by)
            Tex(c, ROUND, color, thickness, bx, by)
            local dx, dy = bx - ax, by - ay
            local len = sqrt(dx * dx + dy * dy)
            if len > 0 then
                local ux, uy = dx / len, dy / len
                local size = thickness * 2.5
                while nextMark < travelled + len do
                    local d = nextMark - travelled
                    local mx, my = ax + ux * d, ay + uy * d
                    local tx, ty = mx - ux * size, my - uy * size
                    Line(c, color, thickness * 0.75, tx - uy * size, ty + ux * size, mx, my)
                    Line(c, color, thickness * 0.75, tx + uy * size, ty - ux * size, mx, my)
                    nextMark = nextMark + thickness * 60
                end
                travelled = travelled + len
            end
        end
    end
    local last = pts[#pts]
    if not clip or ClipSegment(last[1], last[2], last[1] + 0.01, last[2], clip) then
        Tex(c, ROUND, color, thickness * 2.6, last[1], last[2])
    end
end

------------------------------------------------------------------------
-- What to draw
------------------------------------------------------------------------

local function StepStop(step)
    local a = Areas.ForStep(step)
    local s = Areas.StepSpot(step)
    if s then return { s.map, s.x, s.y, a } end
    if a then
        local cx, cy = 0, 0
        for _, p in ipairs(a.poly) do cx, cy = cx + p[1], cy + p[2] end
        return { a.map, cx / #a.poly, cy / #a.poly, a }
    end
end

--- { {map, x, y, area}, ... } for the shown steps and the next few, in order.
--- Steps ahead whose quests are done, or that need a quest you don't have and
--- won't pick up on the way, aren't stops.
function Draw.Upcoming()
    local out = {}
    local steps = Engine.GetSteps()
    local first = Engine.GetPosition()
    if not first then return out end
    local willHave = {}
    for pos = first, min(#steps, first + STEPS_AHEAD) do
        local step = steps[pos]
        local state = Engine.StepState(pos)
        local missing = pos > first and OXP.QuestDB.MissingQuest(step)
        if state ~= "done" and state ~= "skipped" and state ~= "chain" and not (missing and not willHave[missing]) then
            local stop = StepStop(step)
            if stop then out[#out + 1] = stop end
            for _, g in ipairs(step.goals) do
                if g[1] == "accept" and g.quest then willHave[g.quest] = true end
            end
        end
    end
    return out
end

-- Map points (0-100) of the route on `map` from (px, py), or {}. Legs between
-- steps are worked out once; the leg from you follows you.
local legCache = {}
local function RoutePoints(map, px, py, stops, level)
    if not Terrain.Grid(map) then return {} end -- a city: leave it to the arrow
    local key = map .. ":" .. floor(px * 4) .. ":" .. floor(py * 4) .. ":" .. level
    for _, s in ipairs(stops) do key = key .. ":" .. s[1] .. "/" .. floor(s[2] * 10) .. "/" .. floor(s[3] * 10) end
    if legCache.key == key then return legCache.pts end
    local pts = { { px, py } }
    local ax, ay = px, py
    local fromYou, complete = true, true
    for k, s in ipairs(stops) do
        if s[1] ~= map then break end
        local inside = s[4] and Terrain.InsidePoly(s[4].poly, ax, ay)
        if not (k == 1 and inside) then
            local path, pending
            if fromYou then
                path, pending = Terrain.FollowPath("route", map, ax, ay, s[2], s[3], level, true)
            else
                path, pending = Terrain.FindPath(map, ax, ay, s[2], s[3], level, true)
            end
            if pending then complete = false break end
            for _, p in ipairs(path or { { s[2], s[3] } }) do pts[#pts + 1] = { p[1], p[2] } end
            ax, ay = s[2], s[3]
            fromYou = false
        end
    end
    if complete then legCache.key, legCache.pts = key, pts end
    return pts
end
Draw.RoutePoints = RoutePoints

------------------------------------------------------------------------
-- World map
------------------------------------------------------------------------

local wmc, wmp

function Draw.WorldMap()
    local wm = _G.WorldMapFrame
    if not (wm and wm:IsShown() and wm.GetCanvas) then return end
    local canvas = wm:GetCanvas()
    local map = wm:GetMapID()
    wmc = wmc or NewCanvas(canvas, min(9000, (canvas:GetFrameLevel() or 1) + 3000))
    Clear(wmc)
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = wm.GetCanvasScale and wm:GetCanvasScale() or 1
    local function P(x, y) return x / 100 * w, y / 100 * h end
    local stops = Draw.Upcoming()

    for _, s in ipairs(stops) do
        if s[4] and s[4].map == map then
            local px = {}
            for _, p in ipairs(Rounded(s[4])) do px[#px + 1] = { P(p[1], p[2]) } end
            Draw.Fill(wmc, px, AREA_FILL, max(1, 2 / scale))
            Outline(wmc, px, AREA_EDGE, 2.5 / scale)
        end
    end

    -- spawn marks for the mobs you need (off by default), on their own low canvas
    wmp = wmp or NewCanvas(canvas, (canvas:GetFrameLevel() or 1) + 1)
    Clear(wmp)
    local d = OXP.settings.mobPins and Terrain.Data(map)
    if d and d.area then
        local seen = {}
        for _, pos in ipairs(Engine.GetActive()) do
            local step = Engine.GetSteps()[pos]
            for _, g in ipairs(step.goals) do
                if g[1] == "complete" and OXP.Goals.State(g, step.marks) == "todo" then
                    for _, pt in ipairs(OXP.QuestDB.ObjectiveSpawns(g.quest, g.obj, d.area) or {}) do
                        local key = floor(pt[1] * 10) .. "," .. floor(pt[2] * 10)
                        if not seen[key] then
                            seen[key] = true
                            local x, y = P(pt[1], pt[2])
                            Tex(wmp, PIN_TEXTURE, { 1, 1, 1, 0.6 }, 9 / scale, x, y)
                        end
                    end
                end
            end
        end
    end

    if not RouteOn() then return end
    local px, py, pmap = Places.PlayerZone()
    local level = OXP.Player.level or 1
    local tlines = OXP.Travel.Polylines(map, level)
    if tlines and #tlines > 0 then
        for _, line in ipairs(tlines) do
            local pts = {}
            for _, p in ipairs(line) do pts[#pts + 1] = { P(p[1], p[2]) } end
            RouteLeg(wmc, pts, 2 / scale)
        end
    elseif px and pmap == map and #stops > 0 then
        local pts = {}
        for _, p in ipairs(RoutePoints(map, px, py, stops, level)) do pts[#pts + 1] = { P(p[1], p[2]) } end
        RouteLeg(wmc, pts, 2 / scale)
    end
end

------------------------------------------------------------------------
-- Minimap
------------------------------------------------------------------------

-- yards across the minimap per zoom level (0-5)
local MINI_SIZE = {
    indoor = { 300, 240, 180, 120, 80, 50 },
    outdoor = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
}

local function MinimapRadius()
    local mm = _G.Minimap
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, r = pcall(C_Minimap.GetViewRadius)
        if ok and r and r > 0 then return r end
    end
    local zoom = mm:GetZoom()
    local kind = (tonumber(GetCVar("minimapZoom")) or 0) == zoom and "outdoor" or "indoor"
    return MINI_SIZE[kind][zoom + 1] / 2
end

local mmc, lastMini

local function DrawMinimap()
    local mm = _G.Minimap
    if not (mm and mm:IsShown()) then return end
    mmc = mmc or NewCanvas(mm, mm:GetFrameLevel() + 2)
    local stops = Draw.Upcoming()
    local plan = OXP.Travel.Current()
    if #stops == 0 and not plan then lastMini = nil return Clear(mmc) end
    local wx, wy = Places.Player()
    local px, py, pmap = Places.PlayerZone()
    if not (wx and px) then lastMini = nil return Clear(mmc) end
    local radius = MinimapRadius()
    local size = mm:GetWidth() / 2
    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    if rotate and not facing then lastMini = nil return Clear(mmc) end
    -- nothing you could see changed since the last frame: keep what's drawn
    local col = RouteColor()
    local ppy = size / radius
    local sig = { pmap, floor(wx * ppy), floor(wy * ppy), floor(facing * size), radius, size, tostring(plan),
                  RouteOn() and 1 or 0, Areas.On() and 1 or 0, col[1], col[2], col[3] }
    for _, st in ipairs(stops) do
        sig[#sig + 1] = st[1] .. "/" .. floor(st[2] * 10) .. "/" .. floor(st[3] * 10) .. "/" .. tostring(st[4])
    end
    sig = table.concat(sig, ":")
    if sig == lastMini then return end
    Clear(mmc)
    lastMini = sig
    local sin, cos = math.sin(facing or 0), math.cos(facing or 0)
    local clip = { size, size, size - 2 }
    local function P(x, y)
        local ox, oy = Places.ToWorld(pmap, x, y)
        if not ox then return nil end
        local dx, dy = wx - ox, wy - oy
        if rotate then dx, dy = dx * cos - dy * sin, dx * sin + dy * cos end
        return size + dx / radius * size, size + dy / radius * size
    end
    for _, s in ipairs(stops) do
        if s[4] and s[4].map == pmap then
            local pts = {}
            for _, p in ipairs(Rounded(s[4])) do
                local x, y = P(p[1], p[2])
                if not x then pts = nil break end
                pts[#pts + 1] = { x, y }
            end
            if pts then
                Draw.Fill(mmc, pts, AREA_FILL, 2, clip)
                Outline(mmc, pts, AREA_EDGE, 2, clip)
            end
        end
    end
    if not RouteOn() then return end
    local level = OXP.Player.level or 1
    local tlines = OXP.Travel.Polylines(pmap, level)
    if tlines and #tlines > 0 then
        for _, line in ipairs(tlines) do
            local route = {}
            for _, p in ipairs(line) do
                local x, y = P(p[1], p[2])
                if x then route[#route + 1] = { x, y } end
            end
            RouteLeg(mmc, route, 1.5, clip)
        end
        return
    end
    local route = {}
    for _, p in ipairs(RoutePoints(pmap, px, py, stops, level)) do
        local x, y = P(p[1], p[2])
        if x then route[#route + 1] = { x, y } end
    end
    RouteLeg(mmc, route, 1.5, clip)
end

function Draw.Minimap()
    Terrain.waited = false
    DrawMinimap()
    if Terrain.waited then lastMini = nil end -- part of the route waited: again next frame
end

local function Safe(fn)
    local ok, err = pcall(fn)
    if not ok then OXP.Debug(tostring(err)) end
end

OXP.OnReady(function()
    if not (C_Timer and C_Timer.NewTicker) then return end
    C_Timer.NewTicker(MAP_TICK, OXP.Perf.Wrap("world map lines", function()
        local wm = _G.WorldMapFrame
        if wm and wm:IsShown() then
            Safe(Draw.WorldMap)
        elseif wmc then
            Clear(wmc)
            if wmp then Clear(wmp) end
        end
    end))
    C_Timer.NewTicker(MINI_TICK, OXP.Perf.Wrap("minimap lines", function() Safe(Draw.Minimap) end))
end)
