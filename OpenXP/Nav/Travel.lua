-- Getting there from another zone.
--
-- When the arrow's target is in another zone (or on the other continent),
-- this works out the way from the flight paths you know, boats, zeppelins,
-- the tram, your Hearthstone and walking from zone to zone (Data/Travel.lua):
--   * the arrow points at the next leg (flight master, dock, road into the
--     next zone) and says what to do there,
--   * the card lists the legs ("Fly to Menethil Harbor", ...),
--   * the route line on the maps follows the whole way.
--
-- Flight masters and flight times come from the game's client data
-- (Data/Flights.lua, built by tools/build_flights.py). Opening a flight
-- master's map also records every flight master on it (account-wide,
-- OpenXPDB.flightMasters), which adds WoW Forever's own ones; the paths you
-- know come from the same map.
local _, OXP = ...

local Travel = {}
OXP.Travel = Travel

local Places, PlaceKey = OXP.Places, OXP.Util.PlaceKey
local floor, sqrt = math.floor, math.sqrt
local fmt = string.format
local L = OXP.L

local HEARTHSTONE = 6948
local WALK_FACTOR = 1.2     -- walking a zone isn't a straight line
local FAR_FACTOR = 5        -- walking between zones without a known way (a last resort)
local FAR_EXTRA = 300       -- seconds on top of that
local FLY_SPEED = 25        -- yards per second on a flight path, roughly
local FLY_EXTRA = 20        -- seconds: talking to the flight master, landing
local HEARTH_SECS = 25
local MIN_LEG = 25          -- yards: shorter walks aren't worth a line of their own
local REPLAN = 2            -- seconds between working the way out again

function Travel.IsOn()
    return OXP.settings.travel ~= false
end

------------------------------------------------------------------------
-- Flight masters, learned from the taxi map
------------------------------------------------------------------------

local function Masters()
    local db = OXP.db
    if not db then return {} end
    db.flightMasters = db.flightMasters or {}
    local faction = OXP.Player.faction or "Alliance"
    db.flightMasters[faction] = db.flightMasters[faction] or {}
    return db.flightMasters[faction]
end
Travel.Masters = Masters

local nodes, links -- the network, built on demand

--- Record a flight master: name "Place, Zone", world spot.
function Travel.RecordMaster(name, wx, wy, inst)
    if not (name and wx and wy) then return end
    local m = Masters()
    local old = m[name]
    if old and old.exact then return end
    m[name] = { wx = wx, wy = wy, inst = inst }
    nodes = nil
end

OXP.On("TAXIMAP_OPENED", function()
    -- where you stand is the flight master you're talking to
    local n = NumTaxiNodes and NumTaxiNodes() or 0
    local wx, wy, inst = Places.Player()
    for i = 1, n do
        if TaxiNodeGetType(i) == "CURRENT" and wx then
            local name = TaxiNodeName(i)
            Masters()[name] = { wx = wx, wy = wy, inst = inst, exact = true }
            nodes = nil
        end
    end
    -- every other flight master on this map, from the map itself
    local mapID = GetTaxiMapID and GetTaxiMapID()
    if mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
        for _, node in ipairs(ok and list or {}) do
            local pos = node.position
            if node.name and pos then
                local x, y = pos.x or pos[1], pos.y or pos[2]
                local nwx, nwy, ninst = Places.ToWorld(mapID, x * 100, y * 100)
                Travel.RecordMaster(node.name, nwx, nwy, ninst)
            end
        end
    end
    Travel.Reset()
end)

------------------------------------------------------------------------
-- The network: flight masters, docks and zone borders
------------------------------------------------------------------------

local function World(p)
    return Places.ToWorld(p[1], p[2], p[3])
end

local function AddNode(n)
    nodes[#nodes + 1] = n
    n.i = #nodes
    links[n.i] = links[n.i] or {}
    return n
end

local function Link(a, b, kind, secs, text)
    links[a.i][#links[a.i] + 1] = { to = b, kind = kind, secs = secs, text = text }
end

local function Build()
    if nodes then return end
    nodes, links = {}, {}
    local D = OXP.travelData or {}
    local faction = OXP.Player.faction

    Travel.fps = {}
    local seen = {}
    local function AddMaster(full, spot, id)
        if seen[full] then return end
        seen[full] = true
        local first, second = full:match("^([^,]+),%s*(.+)$")
        local zone = (D.fpCity or {})[first or full] or (D.fpZone or {})[second or ""]
        local n = AddNode({ wx = spot.wx, wy = spot.wy, inst = spot.inst, zones = { [zone or 0] = true },
                            name = first or full, kind = "fp", fp = id })
        Travel.fps[#Travel.fps + 1] = n
    end
    -- the game's own flight masters (Data/Flights.lua), then any learned in
    -- game that the table doesn't have (WoW Forever's new ones)
    local mine = faction == "Horde" and "H" or "A"
    for id, n in pairs(OXP.flightData and OXP.flightData.nodes or {}) do
        if n.faction == mine or n.faction == "B" then AddMaster(n.name, n, id) end
    end
    for full, spot in pairs(Masters()) do AddMaster(full, spot) end

    for _, t in ipairs(D.transports or {}) do
        if not t.faction or t.faction == faction then
            local ax, ay, ai = World(t.a)
            local bx, by, bi = World(t.b)
            if ax and bx then
                local a = AddNode({ wx = ax, wy = ay, inst = ai, zones = { [t.a[1]] = true }, name = t.an, kind = "dock" })
                local b = AddNode({ wx = bx, wy = by, inst = bi, zones = { [t.b[1]] = true }, name = t.bn, kind = "dock" })
                Link(a, b, t.kind, t.secs, t.bn)
                if not t.oneway then Link(b, a, t.kind, t.secs, t.an) end
            end
        end
    end

    for _, g in ipairs(D.gates or {}) do
        local ax, ay, ai = World(g.a)
        if ax then
            if g.b then
                local bx, by, bi = World(g.b)
                if bx then
                    local a = AddNode({ wx = ax, wy = ay, inst = ai, zones = { [g.zones[1]] = true }, name = g.name, kind = "gate" })
                    local b = AddNode({ wx = bx, wy = by, inst = bi, zones = { [g.zones[2]] = true }, name = g.name, kind = "gate" })
                    a.pair, b.pair = b, a
                end
            else
                AddNode({ wx = ax, wy = ay, inst = ai, zones = { [g.zones[1]] = true, [g.zones[2]] = true },
                          name = g.name, kind = "gate" })
            end
        end
    end
end
Travel.Build = Build

function Travel.Reset()
    nodes, links = nil, nil
    Travel.plan = nil
end

local function Dist(a, b)
    if a.inst ~= b.inst then return nil end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return sqrt(dx * dx + dy * dy)
end

local function Speed()
    return (OXP.Player.level or 1) >= 40 and 10 or 7
end

local function ShareZone(a, b)
    for z in pairs(a.zones) do
        if b.zones[z] then return true end
    end
end

-- Where your Hearthstone takes you: where you stood when you set it, else
-- the flight master of that town.
local function HearthNode()
    local saved = OXP.char.hearth
    local name = GetBindLocation and GetBindLocation()
    if saved and saved.wx and (not name or saved.name == name) then
        return { wx = saved.wx, wy = saved.wy, inst = saved.inst, zones = { [saved.map or 0] = true },
                 name = saved.name or name, kind = "inn" }
    end
    if not name then return nil end
    for _, n in ipairs(nodes) do
        if n.kind == "fp" and n.name and (n.name == name or n.name:find(name, 1, true)) then
            return { wx = n.wx, wy = n.wy, inst = n.inst, zones = n.zones, name = name, kind = "inn" }
        end
    end
end

local function HearthReady()
    if not GetItemCount or GetItemCount(HEARTHSTONE) == 0 then return false end
    local getCd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not getCd then return false end
    local start, duration = getCd(HEARTHSTONE)
    return not start or start == 0 or (duration or 0) <= 1.5
end

------------------------------------------------------------------------
-- The cheapest way (Dijkstra over ~150 nodes)
------------------------------------------------------------------------

local function Search(from, to)
    Build()
    local speed = Speed()
    local all = { from, to }
    for _, n in ipairs(nodes) do all[#all + 1] = n end
    local hearth = HearthReady() and HearthNode() or nil
    if hearth then all[#all + 1] = hearth end

    local best, prev, how, done = { [from] = 0 }, {}, {}, {}
    while true do
        local cur, cd
        for _, n in ipairs(all) do
            local d = best[n]
            if d and not done[n] and (not cd or d < cd) then cur, cd = n, d end
        end
        if not cur or cur == to then break end
        done[cur] = true
        local function relax(n, cost, edge)
            if cost and not done[n] then
                local nd = cd + cost
                if not best[n] or nd < best[n] then best[n], prev[n], how[n] = nd, cur, edge end
            end
        end
        for _, n in ipairs(all) do
            if n ~= cur and n ~= hearth then
                local d = Dist(cur, n)
                if d then
                    if ShareZone(cur, n) then
                        relax(n, d * WALK_FACTOR / speed, { kind = "walk" })
                    else
                        relax(n, d * FAR_FACTOR / speed + FAR_EXTRA, { kind = "walk", far = true })
                    end
                end
            end
        end
        if cur.pair then
            local d = Dist(cur, cur.pair)
            relax(cur.pair, d and d * WALK_FACTOR / speed or 60, { kind = "walk" })
        end
        for _, l in ipairs(cur.i and links[cur.i] or {}) do
            relax(l.to, l.secs, { kind = l.kind, text = l.text })
        end
        if cur.kind == "fp" and OXP.World.KnowsFlightPath(cur.name) then
            for _, n in ipairs(Travel.fps) do
                if n ~= cur and n.inst == cur.inst and OXP.World.KnowsFlightPath(n.name) then
                    local times = OXP.flightData and OXP.flightData.times
                    local t = cur.fp and n.fp and times and (times[cur.fp] and times[cur.fp][n.fp])
                    if t then
                        relax(n, t + FLY_EXTRA, { kind = "fly" })
                    else
                        local d = Dist(cur, n)
                        relax(n, d and d / FLY_SPEED + FLY_EXTRA * 2, { kind = "fly" })
                    end
                end
            end
        end
        if hearth and cur == from then relax(hearth, HEARTH_SECS, { kind = "hearth" }) end
    end
    if not best[to] then return nil end
    local path = {}
    local n = to
    while n do
        table.insert(path, 1, { node = n, how = how[n] })
        n = prev[n]
    end
    return path, best[to]
end

-- The path as legs, each with what it says: { kind, text, to, pts }.
local function Legs(path, target)
    local legs, walk = {}, nil
    for k = 2, #path do
        local from = path[k - 1].node
        local n, how = path[k].node, path[k].how or { kind = "walk" }
        if how.kind == "walk" then
            walk = walk or { kind = "walk", pts = { from } }
            walk.pts[#walk.pts + 1] = n
            walk.to = n
        else
            if walk then legs[#legs + 1] = walk; walk = nil end
            legs[#legs + 1] = { kind = how.kind, from = from, to = n, pts = { from, n } }
        end
    end
    if walk then legs[#legs + 1] = walk end

    local out = {}
    for k, leg in ipairs(legs) do
        local n, nextLeg = leg.to, legs[k + 1]
        if leg.kind == "walk" then
            local len = 0
            for i = 2, #leg.pts do len = len + (Dist(leg.pts[i - 1], leg.pts[i]) or 0) end
            if len >= MIN_LEG or not nextLeg then
                local through
                for i = 2, #leg.pts - 1 do
                    if leg.pts[i].kind == "gate" then through = leg.pts[i].name end
                end
                if nextLeg and nextLeg.kind == "fly" then
                    leg.text = fmt(L("Go to the %s flight master"), n.name or "?")
                elseif nextLeg and (nextLeg.kind == "boat" or nextLeg.kind == "zeppelin") then
                    leg.text = fmt(L("Go to the %s at %s"), L(nextLeg.kind), n.name or "?")
                elseif nextLeg and nextLeg.kind == "tram" then
                    leg.text = L("Go to the Deeprun Tram")
                elseif n == target then
                    local zone = Places.ZoneName(target.map)
                    leg.text = zone and fmt(L("Head into %s"), zone) or L("Walk the rest of the way")
                else
                    leg.text = fmt(L("Walk to %s"), n.name or "?")
                end
                if through then leg.text = leg.text .. fmt(L(" (through %s)"), through) end
                leg.len = len
                out[#out + 1] = leg
            end
        elseif leg.kind == "fly" then
            leg.text = fmt(L("Fly to %s"), n.name or "?")
            out[#out + 1] = leg
        elseif leg.kind == "hearth" then
            leg.text = fmt(L("Use your Hearthstone (to %s)"), n.name or "?")
            out[#out + 1] = leg
        elseif leg.kind == "tram" then
            leg.text = fmt(L("Take the Deeprun Tram to %s"), n.name or "?")
            out[#out + 1] = leg
        else
            leg.text = fmt(L("Take the %s to %s"), L(leg.kind), n.name or "?")
            out[#out + 1] = leg
        end
    end
    return out
end
Travel.Legs = Legs

------------------------------------------------------------------------
-- The plan for the arrow's target
------------------------------------------------------------------------

local lastAt, lastKey = 0, nil

--- How to get to `target` ({wx, wy, instance, map, title}) when it's in
--- another zone (worked out at most every REPLAN seconds). nil when the
--- arrow can go straight there.
function Travel.PlanFor(target)
    if not (target and target.wx and target.map) then Travel.plan = nil return nil end
    local px, py, pinst = Places.Player()
    local _, _, pmap = Places.PlayerZone()
    if not px then return Travel.plan end
    if UnitOnTaxi and UnitOnTaxi("player") then return Travel.plan end
    if pmap == target.map then Travel.plan = nil return nil end
    local now = GetTime and GetTime() or 0
    local key = fmt("%s:%d:%d", tostring(target.map), floor(target.wx), floor(target.wy))
    if key == lastKey and now - lastAt < REPLAN then return Travel.plan end
    lastKey, lastAt = key, now

    local from = { wx = px, wy = py, inst = pinst, zones = { [pmap or 0] = true }, name = L("you"), kind = "you" }
    local to = { wx = target.wx, wy = target.wy, inst = target.instance, zones = { [target.map] = true },
                 name = target.title, kind = "target", map = target.map }
    local path = Search(from, to)
    if not path then Travel.plan = nil return nil end
    local legs = Legs(path, to)
    -- only walking over the border: the arrow copes with that by itself
    if #legs == 0 or (#legs == 1 and legs[1].kind == "walk" and #legs[1].pts <= 2) then
        Travel.plan = nil
        return nil
    end
    Travel.plan = { legs = legs, target = target, at = now, from = from }
    return Travel.plan
end
Travel.PlanFor = OXP.Perf.Wrap("travel plan", Travel.PlanFor)

local proxy = {}

--- The first place to head for on the way to `real`: {wx, wy, instance, map, title}.
function Travel.ArrowTarget(real)
    if not (Travel.IsOn() and real) then return nil end
    local plan = Travel.PlanFor(real)
    local leg = plan and plan.legs[1]
    if not leg then return nil end
    local n
    if leg.kind == "walk" then
        n = leg.pts[2] or leg.to
        local px, py = Places.Player()
        for i = 2, #leg.pts do
            local p = leg.pts[i]
            local dx, dy = p.wx - (px or 0), p.wy - (py or 0)
            if dx * dx + dy * dy > 30 * 30 then n = p break end
        end
    else
        n = leg.from or leg.to -- stand at the flight master or dock
    end
    if not n or n.kind == "target" then return nil end
    proxy.wx, proxy.wy, proxy.instance = n.wx, n.wy, n.inst
    proxy.map = next(n.zones)
    proxy.title = leg.text
    proxy.real, proxy.travel = real, true
    return proxy
end

--- The plan while the arrow still uses it.
function Travel.Current()
    local plan = Travel.plan
    if not plan or not Travel.IsOn() then return nil end
    local now = GetTime and GetTime() or 0
    if now - (plan.at or 0) > 10 and not (UnitOnTaxi and UnitOnTaxi("player")) then return nil end
    return plan
end

--- Lines for the card: "1. Fly to Menethil Harbor", ...
function Travel.Lines()
    local plan = Travel.Current()
    if not plan then return nil end
    local out = {}
    for i, leg in ipairs(plan.legs) do out[#out + 1] = fmt("%d. %s", i, leg.text) end
    if not next(OXP.char.flightPaths or {}) then
        out[#out + 1] = L("Tip: open any flight master's map once so OpenXP knows your flight paths")
    end
    return out
end

-- The route on `map` as polylines of map points (0-100), kept per map so the
-- world map and minimap don't throw each other's lines away. Walks within a
-- zone follow that zone's terrain.
local lineCache = {}
function Travel.Polylines(map, level)
    local plan = Travel.Current()
    if not (plan and map) then return nil end
    local px, py, pmap = Places.PlayerZone()
    local key = tostring(plan) .. ":" .. floor((px or 0) * 2) .. ":" .. floor((py or 0) * 2)
    local cached = lineCache[map]
    if cached and cached.key == key then return cached.lines end
    local complete = true
    local _, _, mapInst = Places.ToWorld(map, 50, 50)
    local function P(n)
        if mapInst and n.inst ~= mapInst then return nil end
        local x, y = Places.ToZone(n.wx, n.wy, map, true)
        if x then return { x, y } end
    end
    local lines = {}
    local wx, wy, winst = Places.Player()
    local cur = { wx = wx, wy = wy, inst = winst, zones = { [pmap or 0] = true } }
    local Terrain = OXP.Terrain
    local function Shared(a, b)
        for z in pairs(a.zones or {}) do
            if b.zones and b.zones[z] and z ~= 0 then return z end
        end
    end
    local function Walk(line, a, b)
        if not complete then return end
        local z = Shared(a, b)
        if z then
            local ax, ay = Places.ToZone(a.wx, a.wy, z, true)
            local bx, by = Places.ToZone(b.wx, b.wy, z, true)
            local way, pending
            if ax and bx then
                if a == cur then
                    way, pending = Terrain.FollowPath("travel", z, ax, ay, bx, by, level or 1, true)
                else
                    way, pending = Terrain.FindPath(z, ax, ay, bx, by, level or 1, true)
                end
            end
            if pending then complete = false return end
            for _, w in ipairs(way or {}) do
                local wwx, wwy, inst = Places.ToWorld(z, w[1], w[2])
                local q = wwx and P({ wx = wwx, wy = wwy, inst = inst })
                if q then line[#line + 1] = q end
            end
            if way then return end
        end
        local q = P(b)
        if q then line[#line + 1] = q end
    end
    for k, leg in ipairs(plan.legs) do
        local line, pts = {}, leg.pts
        local prev = pts[1]
        if k == 1 then
            prev = cur
            local me = P(cur)
            if me then line[#line + 1] = me end
        else
            local a = P(pts[1])
            if a then line[#line + 1] = a end
        end
        for i = 2, #pts do
            if leg.kind == "walk" then
                Walk(line, prev, pts[i])
            else
                local a = P(pts[i])
                if a then line[#line + 1] = a end
            end
            prev = pts[i]
        end
        local keep = {}
        for _, p in ipairs(line) do
            if p[1] > -20 and p[1] < 120 and p[2] > -20 and p[2] < 120 then keep[#keep + 1] = p end
        end
        if #keep >= 2 then lines[#lines + 1] = keep end
        if not complete then break end
    end
    if complete then lineCache[map] = { key = key, lines = lines } end
    return lines
end
Travel.Polylines = OXP.Perf.Wrap("travel line", Travel.Polylines)

OXP.On("HEARTHSTONE_BOUND", function()
    local wx, wy, inst = Places.Player()
    local _, _, map = Places.PlayerZone()
    if wx and OXP.char then
        OXP.char.hearth = { wx = wx, wy = wy, inst = inst, map = map, name = GetBindLocation and GetBindLocation() }
    end
    Travel.plan, lastKey = nil, nil
end)
OXP.On("PLAYER_ENTERING_WORLD", function() Travel.plan, lastKey = nil, nil end)
