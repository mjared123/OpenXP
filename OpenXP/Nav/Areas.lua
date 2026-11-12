-- Kill and loot areas. A step can name one (an "area" goal); a kill/loot
-- step without one gets one from Questie's spawn data, the same way
-- tools/build_route.py makes them: the outline of the objective's spawns near
-- the step's spot, widened a little, at most 8 corners. Without Questie such
-- steps keep their plain arrow.
--
-- Inside the area the arrow says "Here"; outside, it leads to the nearest edge.
local _, OXP = ...

local Areas = {}
OXP.Areas = Areas

local Places, Terrain = OXP.Places, OXP.Terrain
local floor, sqrt, min, max, abs = math.floor, math.sqrt, math.min, math.max, math.abs

local REACH = 7.0     -- map units: spawns this close to the step's spot make its area
local MARGIN = 1.5    -- map units: the area reaches this far past the outer spawns
local MIN_SPAWNS = 4
local CORNERS = 8

local function Cross(o, a, b)
    return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
end

--- The kill area around (x, y) from spawn points (map 0-100), or nil.
function Areas.KillArea(points, x, y)
    local near, seen = {}, {}
    for _, p in ipairs(points) do
        local dx, dy = p[1] - x, p[2] - y
        if dx * dx + dy * dy <= REACH * REACH then
            local px, py = floor(p[1] * 100 + 0.5) / 100, floor(p[2] * 100 + 0.5) / 100
            local key = px .. "," .. py
            if not seen[key] then
                seen[key] = true
                near[#near + 1] = { px, py }
            end
        end
    end
    if #near < MIN_SPAWNS then return nil end
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
    if #hull < 3 then return nil end
    while #hull > CORNERS do
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
        out[#out + 1] = { min(100, max(0, p[1] + dx / d * MARGIN)), min(100, max(0, p[2] + dy / d * MARGIN)) }
    end
    return out
end

function Areas.On()
    return OXP.settings.mapAreas ~= false
end

--- The first goto spot of an Engine step, or nil.
function Areas.StepSpot(step)
    for _, g in ipairs(step and step.goals or {}) do
        if g[1] == "goto" then
            local s = Places.Spot(g)
            if s then return s end
        end
    end
end

local auto = setmetatable({}, { __mode = "k" }) -- step -> { key, area or false, at }

local function AutoArea(step)
    local now = GetTime and GetTime() or 0
    local c = auto[step]
    if c and c.at and now - c.at < 0.5 and now >= c.at then return c.area or nil end
    local objs = {}
    for _, g in ipairs(step.goals) do
        local state = OXP.Goals.State(g, step.marks)
        if (g[1] == "accept" or g[1] == "turnin") and state == "todo" then
            return nil -- talking to someone first: their spot, not an area
        end
        if g[1] == "complete" and state == "todo" then objs[#objs + 1] = g end
    end
    local spot = Areas.StepSpot(step)
    if not spot or #objs == 0 then return nil end
    local d = OXP.Terrain.Data(spot.map)
    if not (d and d.area) then return nil end
    local key = spot.map .. ":" .. spot.x .. ":" .. spot.y
    for _, g in ipairs(objs) do key = key .. ":" .. g.quest .. "/" .. g.obj end
    if c and c.key == key then
        c.at = now
        return c.area or nil
    end
    local pts, ready = {}, false
    for _, g in ipairs(objs) do
        local sp = OXP.QuestDB.ObjectiveSpawns(g.quest, g.obj, d.area)
        if sp then
            ready = true
            for _, p in ipairs(sp) do pts[#pts + 1] = p end
        end
    end
    if not ready then return nil end -- Questie isn't ready: ask again later
    local poly = Areas.KillArea(pts, spot.x, spot.y)
    local a = poly and { poly = poly, map = spot.map, auto = true } or false
    auto[step] = { key = key, area = a, at = now }
    return a or nil
end

--- The area of an Engine step: { poly = {{x, y}...}, map } or nil.
function Areas.ForStep(step)
    if not step then return nil end
    for _, g in ipairs(step.goals) do
        if g[1] == "area" then
            return { poly = Places.AreaPolygon(g), map = Places.MapID(g.zone) }
        end
    end
    if Areas.On() then return AutoArea(step) end
end

local here, edge = { inside = true }, {}

--- The arrow's target for a step with an area: a stand-in at your feet while
--- you're inside ("Here"), or just inside the nearest edge while outside.
--- nil when the step has no area or you're in another zone.
function Areas.Target(step, title)
    local a = Areas.ForStep(step)
    if not a then return nil end
    local px, py, map = Places.PlayerZone()
    if not px or map ~= a.map then return nil end
    local t, wx, wy, inst
    if Terrain.InsidePoly(a.poly, px, py) then
        t = here
        wx, wy, inst = Places.Player()
        t.title = OXP.L("In the area")
    else
        t = edge
        local g = Terrain.Grid(map)
        local ex, ey = Terrain.NearestEdge(a.poly, px, py, g and g.kx or 1, g and g.ky or 1)
        local cx, cy = 0, 0
        for _, p in ipairs(a.poly) do cx, cy = cx + p[1], cy + p[2] end
        cx, cy = cx / #a.poly, cy / #a.poly
        local dx, dy = cx - ex, cy - ey
        local d = sqrt(dx * dx + dy * dy)
        if d > 0 then ex, ey = ex + dx / d * 0.6, ey + dy / d * 0.6 end
        wx, wy, inst = Places.ToWorld(map, ex, ey)
        t.title = title
    end
    if not wx then return nil end
    t.wx, t.wy, t.instance, t.map = wx, wy, inst, map
    return t
end
