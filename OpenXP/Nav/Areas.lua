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
        if g[1] == "goto" or g[1] == "reach" then
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
    local area = d and d.area
    local key = spot.map .. ":" .. spot.x .. ":" .. spot.y
    for _, g in ipairs(objs) do key = key .. ":" .. g.quest .. "/" .. g.obj end
    if c and c.key == key then
        c.at = now
        return c.area or nil
    end
    local pts, ready = {}, false
    for _, g in ipairs(objs) do
        local sp = OXP.QuestDB.ObjectiveSpawns(g.quest, g.obj, spot.map, area)
        if sp then
            ready = true
            for _, p in ipairs(sp) do pts[#pts + 1] = p end
        end
    end
    if not ready then return nil end -- no quest data yet: ask again later
    local poly = Areas.KillArea(pts, spot.x, spot.y)
    local a = poly and { poly = poly, map = spot.map, auto = true } or false
    -- too few spawns for an area (a named mob like Gobbler): the arrow goes
    -- to them one by one instead
    local few
    if not poly then
        few = {}
        for _, p in ipairs(pts) do
            local dx, dy = p[1] - spot.x, p[2] - spot.y
            if dx * dx + dy * dy <= (REACH * 2) ^ 2 then few[#few + 1] = p end
        end
        if #few == 0 then few = nil end
    end
    auto[step] = { key = key, area = a, at = now, few = few, map = spot.map }
    return a or nil
end

--- The few spawn points of what a step still needs when they are too few
--- for an area: { {x, y}, ... }, map; or nil.
function Areas.Spawns(step)
    if not (step and Areas.On()) then return nil end
    for _, g in ipairs(step.goals) do
        if g[1] == "area" then return nil end
    end
    if AutoArea(step) then return nil end
    local c = auto[step]
    if c and c.few then return c.few, c.map end
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
local spawnT = {}
local AWAY = 25 -- yards: a spawn this close has been checked, try the next

-- The arrow for a step whose objective has only a few spawns: the nearest
-- one you aren't standing at (named mobs walk between them, or are dead).
local function SpawnTarget(step, title)
    local pts, map = Areas.Spawns(step)
    if not pts then return nil end
    local px, py, pmap = Places.PlayerZone()
    if not px or pmap ~= map then return nil end
    local wpx, wpy = Places.Player()
    local best, bestD, near, nearD
    for _, p in ipairs(pts) do
        local wx, wy, inst = Places.ToWorld(map, p[1], p[2])
        if wx then
            local d = Places.Distance(wpx or 0, wpy or 0, wx, wy)
            if not nearD or d < nearD then near, nearD = { wx, wy, inst }, d end
            if d > AWAY and (not bestD or d < bestD) then best, bestD = { wx, wy, inst }, d end
        end
    end
    local pick = (#pts > 1 and best) or near
    if not pick then return nil end
    spawnT.wx, spawnT.wy, spawnT.instance, spawnT.map = pick[1], pick[2], pick[3], map
    spawnT.title, spawnT.spawn = title, true
    return spawnT
end

function Areas.Target(step, title)
    local a = Areas.ForStep(step)
    if not a then return SpawnTarget(step, title) end
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

------------------------------------------------------------------------
-- SoupEngine arrow (Nav/Target.lua BAKED_ONLY): walk to the step's spot,
-- then "In the area" while you're inside its kill/loot area, or straight at
-- a named mob or chest the step needs when there are only one or two
------------------------------------------------------------------------

local FEW = 3 -- spawns: a mob or object with this many or fewer gets pinpointed
local KIND = { npc = "NPC", object = "Object" }

-- The name (and the item it drops, for loot) of a target SoupEngine baked,
-- from the objective's own sources, else the database.
local function TargetName(quest, obj, kind, id)
    for _, src in ipairs(OXP.QuestDB.ObjectiveSources(quest, obj) or {}) do
        if src.kind == kind and src.id == id then return src.name, src.item end
    end
    local o = OXP.QuestDB.Get(kind, id)
    return o and o.name
end

-- SoupEngine's own pinpoints for an objective (OpenXP_Nav's targets, on the
-- floor they're really on), on the spot's map: added to `out`. False when
-- OpenXP_Nav has none for it (then Questie's spawns are used).
local function BakedTargets(g, spot, out, seen)
    local list = OXP.WalkPaths and OXP.WalkPaths.Targets(g.quest, g.obj)
    if not list then return false end
    for _, e in ipairs(list) do
        local map, x, y, z, indoor, id, kind = e[1], e[2], e[3], e[4], e[5], e[6], KIND[e[7]] or e[7]
        local key = tostring(id) .. ":" .. floor(x * 10) .. ":" .. floor(y * 10)
        if map == spot.map and not seen[key] then
            seen[key] = true
            local name, item = TargetName(g.quest, g.obj, kind, id)
            out[#out + 1] = { x, y, name = name, id = id, kind = kind, item = item, z = z, indoor = indoor == 1, baked = true }
        end
    end
    return true
end

--- What a step still needs that has only a few spawns near its spot (a named
--- mob, a chest, a single object): { {x, y, name = s, id = n, kind = "NPC"|"Object"}, ... }, map; or nil.
--- SoupEngine's baked targets (OpenXP_Nav) come first and also carry z (yards)
--- and indoor; without them, Questie's spawns.
function Areas.Pinpoints(step)
    local spot = Areas.StepSpot(step)
    if not spot then return nil end
    local d = OXP.Terrain.Data(spot.map)
    local zoneArea = d and d.area
    local out, seen = {}, {}
    for _, g in ipairs(step.goals) do
        if g[1] == "complete" and g.quest and g.obj and OXP.Goals.State(g, step.marks) == "todo"
            and not BakedTargets(g, spot, out, seen) then
            local sp = OXP.QuestDB.ObjectiveSpawns(g.quest, g.obj, spot.map, zoneArea) or {}
            local per, near = {}, {}
            for _, p in ipairs(sp) do
                per[p.src] = (per[p.src] or 0) + 1
                local dx, dy = p[1] - spot.x, p[2] - spot.y
                if dx * dx + dy * dy <= (REACH * 2) ^ 2 then near[#near + 1] = p end
            end
            for _, p in ipairs(near) do
                local src = p.src
                local key = tostring(src.id) .. ":" .. floor(p[1] * 10) .. ":" .. floor(p[2] * 10)
                if per[src] <= FEW and not seen[key] then
                    seen[key] = true
                    out[#out + 1] = { p[1], p[2], name = src.name, id = src.id, kind = src.kind, item = src.item, quest = g.quest }
                end
            end
        end
    end
    if #out == 0 then return nil end
    return out, spot.map
end

local pin = {}

local UP = 6 -- yards: a pinpoint this far above or below the spot's floor is on another floor

--- Where a baked pinpoint is compared with its step's spot: "upstairs" (well
--- above its floor), "in a cave" (well below it), "inside" (indoors on about
--- the same level while the spot is outdoors) or nil.
function Areas.FloorNote(p, spot)
    if not (p and p.baked and p.z) then return nil end
    local sz, sIndoor
    if spot and OXP.WalkPaths then sz, sIndoor = OXP.WalkPaths.Floor(spot.map, spot.x, spot.y) end
    if sz and p.z >= sz + UP then return OXP.L("upstairs") end
    if sz and p.z <= sz - UP then return OXP.L("in a cave") end
    if p.indoor and not sIndoor then return OXP.L("inside") end
end

--- For the SoupEngine arrow: what to show for a kill/loot step once you're
--- there. A pinpointed mob or chest ({wx, wy, instance, map, x, y, title,
--- pin = true}) when the step needs one; "In the area" ({inside = true})
--- inside the step's area; nil while you're still on your way (the arrow
--- walks to the step's spot).
function Areas.Focus(step, title)
    if not (step and Areas.On()) then return nil end
    for _, g in ipairs(step.goals) do
        local state = OXP.Goals.State(g, step.marks)
        if (g[1] == "accept" or g[1] == "turnin") and state == "todo" then return nil end
    end
    local px, py, pmap = Places.PlayerZone()
    if not px then return nil end
    local a = Areas.ForStep(step)
    local inside = a and a.map == pmap and Terrain.InsidePoly(a.poly, px, py)
    local pts, map = Areas.Pinpoints(step)
    if pts and map == pmap then
        -- in the area, or close to the spot when there's no area (Gobbler)
        local spot = Areas.StepSpot(step)
        local sx, sy = Places.ToWorld(spot.map, spot.x, spot.y)
        local wpx, wpy = Places.Player()
        local close = inside or (sx and Places.Distance(wpx, wpy, sx, sy) <= 120)
        if close then
            local best, bestD, near, nearD
            for _, p in ipairs(pts) do
                local wx, wy = Places.ToWorld(map, p[1], p[2])
                if wx then
                    local d = Places.Distance(wpx, wpy, wx, wy)
                    if not nearD or d < nearD then near, nearD = p, d end
                    if d > AWAY and (not bestD or d < bestD) then best, bestD = p, d end
                end
            end
            -- several spawns: the nearest one you aren't standing at
            local p = (#pts > 1 and nearD and nearD <= AWAY and best) or near
            if p then
                local wx, wy, inst = Places.ToWorld(map, p[1], p[2])
                pin.wx, pin.wy, pin.instance, pin.map, pin.x, pin.y = wx, wy, inst, map, p[1], p[2]
                -- the step's words when they name it ("Kill Gobbler for
                -- Gobbler's Head"), else its name
                local name = p.name
                local says = title and name and OXP.Text.Strip(title):find(name, 1, true)
                pin.title, pin.name, pin.pin, pin.kind = (says or not name) and title or name, name, true, p.kind
                -- SoupEngine knows its floor: say when it's upstairs or in a cave
                local note = Areas.FloorNote(p, spot)
                if note and pin.title then pin.title = pin.title .. " (" .. note .. ")" end
                pin.floorNote = note
                return pin
            end
        end
    end
    if inside then
        here.title = title
        here.wx, here.wy, here.instance = Places.Player()
        here.map = pmap
        return here
    end
end
