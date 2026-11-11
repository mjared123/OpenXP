-- Getting there from another zone
--
-- When the next step is in another zone (or on the other continent), the
-- arrow and the purple route line used to give up. This works out the way
-- there from the flight paths you know, boats, zeppelins, the tram, your
-- Hearthstone and walking from zone to zone (DB/travel.lua), and:
--   * the arrow points at the next leg (the flight master, the dock, the
--     road into the next zone) and says what to do there,
--   * the card lists the legs ("Fly to Menethil Harbor", "Take the boat to
--     Auberdine", ...),
--   * the route line on the world map, the continent map and the minimap
--     follows the whole way.

local _, addon = ...

local HBD = LibStub("HereBeDragons-2.0")
local floor, sqrt, min, max, huge = math.floor, math.sqrt, math.min, math.max, math.huge
local fmt = string.format

local function L(s)
    local get = addon.locale and addon.locale.Get
    return get and get(s) or s
end

local tv = {}
addon.travel = tv

local HEARTHSTONE = 6948
local WALK_FACTOR = 1.2     -- walking a zone isn't a straight line
local FAR_FACTOR = 5        -- walking between zones without a known way through (a last resort)
local FAR_EXTRA = 300       -- seconds on top of that
local FLY_EXTRA = 20        -- seconds: talking to the flight master, landing
local HEARTH_SECS = 25      -- casting and loading
local MIN_LEG = 25          -- yards: shorter walks aren't worth a line of their own
local REPLAN = 2            -- seconds between working the way out again

---------------------------------------------------------------------------
-- The network: flight masters, docks and zone borders
---------------------------------------------------------------------------

local nodes, links  -- nodes[i] = {wx, wy, inst, zones = {[map] = true}, name, kind, fp}
local function World(p)
    if not (p and HBD.GetWorldCoordinatesFromZone) then return end
    return HBD:GetWorldCoordinatesFromZone(p[2] / 100, p[3] / 100, p[1])
end

local function Faction()
    return (addon.player and addon.player.faction) or (UnitFactionGroup and UnitFactionGroup("player")) or "Alliance"
end

local function AddNode(n)
    nodes[#nodes + 1] = n
    n.i = #nodes
    links[n.i] = links[n.i] or {}
    return n
end

local function Link(a, b, kind, secs, text)
    links[a.i][#links[a.i] + 1] = {to = b, kind = kind, secs = secs, text = text}
end

local function FpName(full)
    return (full or ""):match("^([^,]+)") or full
end

local function Build()
    if nodes then return end
    nodes, links = {}, {}
    local D = addon.travelData or {}
    local faction = Faction()
    local factionBit = faction == "Horde" and 2 or 1

    -- flight masters
    tv.fps = {}
    local db = addon.FPDB and addon.FPDB[faction] or {}
    for inst, list in pairs(addon.taxiPos or {}) do
        for id, t in pairs(list) do
            local info = db[id]
            if info and bit.band(t.flag or 3, factionBit) ~= 0 then
                local first, second = (info.name or ""):match("^([^,]+),%s*(.+)$")
                local zone = (D.fpCity or {})[first or ""] or (D.fpZone or {})[second or ""]
                if zone then
                    -- taxiPos is in UnitPosition order (y, x); HereBeDragons uses x, y
                    local n = AddNode({wx = t.wy, wy = t.wx, inst = inst, zones = {[zone] = true},
                                       name = FpName(info.name), kind = "fp", fp = id})
                    tv.fps[id] = n
                end
            end
        end
    end

    -- boats, zeppelins, the tram
    for _, t in ipairs(D.transports or {}) do
        if not t.faction or t.faction == faction then
            local ax, ay, ai = World(t.a)
            local bx, by, bi = World(t.b)
            if ax and bx then
                local a = AddNode({wx = ax, wy = ay, inst = ai, zones = {[t.a[1]] = true}, name = t.an, kind = "dock"})
                local b = AddNode({wx = bx, wy = by, inst = bi, zones = {[t.b[1]] = true}, name = t.bn, kind = "dock"})
                Link(a, b, t.kind, t.secs, t.bn)
                if not t.oneway then Link(b, a, t.kind, t.secs, t.an) end
            end
        end
    end

    -- zone borders
    for _, g in ipairs(D.gates or {}) do
        local ax, ay, ai = World(g.a)
        if ax then
            if g.b then
                local bx, by, bi = World(g.b)
                if bx then
                    local a = AddNode({wx = ax, wy = ay, inst = ai, zones = {[g.zones[1]] = true}, name = g.name, kind = "gate"})
                    local b = AddNode({wx = bx, wy = by, inst = bi, zones = {[g.zones[2]] = true}, name = g.name, kind = "gate"})
                    a.pair, b.pair = b, a
                end
            else
                AddNode({wx = ax, wy = ay, inst = ai, zones = {[g.zones[1]] = true, [g.zones[2]] = true},
                         name = g.name, kind = "gate"})
            end
        end
    end
end
tv.Build = Build

function tv.Reset()
    nodes, links = nil, nil
    tv.plan = nil
end

local function Dist(a, b)
    if a.inst ~= b.inst then return end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return sqrt(dx * dx + dy * dy)
end

local function Speed()
    local level = UnitLevel and UnitLevel("player") or 1
    return level >= 40 and 10 or 7
end

local function KnownFp(id)
    local known = OXPCData and OXPCData.flightPaths
    return known and known[id] and true or false
end

local function ShareZone(a, b)
    for z in pairs(a.zones) do
        if b.zones[z] then return true end
    end
end

local function FlightSecs(a, b)
    local db = addon.FPDB and addon.FPDB[Faction()]
    local t = db and (db[a.fp] and db[a.fp][b.fp] or db[b.fp] and db[b.fp][a.fp])
    if t then return t + FLY_EXTRA end
    local d = Dist(a, b)
    return d and d / 25 + FLY_EXTRA * 2
end

-- Where your Hearthstone takes you: where you stood when you last set it,
-- else the flight master of the town it's set to
local function HearthNode()
    local saved = OXPCData and OXPCData.openxpHearth
    local name = GetBindLocation and GetBindLocation()
    if saved and saved.wx and (not name or saved.name == name) then
        return {wx = saved.wx, wy = saved.wy, inst = saved.inst, zones = {[saved.map or 0] = true},
                name = saved.name or name, kind = "inn"}
    end
    if not name then return end
    for _, n in ipairs(nodes) do
        if n.kind == "fp" and n.name and (n.name == name or n.name:find(name, 1, true)) then
            return {wx = n.wx, wy = n.wy, inst = n.inst, zones = n.zones, name = name, kind = "inn"}
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

---------------------------------------------------------------------------
-- The way: cheapest path through the network (Dijkstra; ~150 nodes)
---------------------------------------------------------------------------

local function Search(from, to)
    Build()
    local speed = Speed()
    local all = {from, to}
    for _, n in ipairs(nodes) do all[#all + 1] = n end
    local hearth = HearthReady() and HearthNode() or nil
    if hearth then all[#all + 1] = hearth end

    local best, prev, how, done = {[from] = 0}, {}, {}, {}
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
                if not best[n] or nd < best[n] then
                    best[n], prev[n], how[n] = nd, cur, edge
                end
            end
        end
        -- walking
        for _, n in ipairs(all) do
            if n ~= cur and n ~= hearth then
                local d = Dist(cur, n)
                if d then
                    if ShareZone(cur, n) then
                        relax(n, d * WALK_FACTOR / speed, {kind = "walk"})
                    else
                        relax(n, d * FAR_FACTOR / speed + FAR_EXTRA, {kind = "walk", far = true})
                    end
                end
            end
        end
        -- through a tunnel or pass
        if cur.pair then
            local d = Dist(cur, cur.pair)
            relax(cur.pair, d and d * WALK_FACTOR / speed or 60, {kind = "walk"})
        end
        -- boats, zeppelins, the tram
        for _, l in ipairs(cur.i and links[cur.i] or {}) do
            relax(l.to, l.secs, {kind = l.kind, text = l.text})
        end
        -- flying
        if cur.kind == "fp" and KnownFp(cur.fp) then
            for _, n in pairs(tv.fps) do
                if n ~= cur and n.inst == cur.inst and KnownFp(n.fp) then
                    relax(n, FlightSecs(cur, n), {kind = "fly"})
                end
            end
        end
        -- your Hearthstone, from wherever you start
        if hearth and cur == from then
            relax(hearth, HEARTH_SECS, {kind = "hearth"})
        end
    end
    if not best[to] then return end
    local path = {}
    local n = to
    while n do
        table.insert(path, 1, {node = n, how = how[n]})
        n = prev[n]
    end
    return path, best[to]
end

local function ZoneName(map)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name
end

local function NodeZone(n)
    local z = next(n.zones)
    return z
end

-- The path as legs: {kind, text, to = node, pts = {node, ...} (walking)}
local function Legs(path, target)
    local legs = {}
    local walk
    for k = 2, #path do
        local step, from = path[k], path[k - 1].node
        local n, how = step.node, step.how or {kind = "walk"}
        if how.kind == "walk" then
            walk = walk or {kind = "walk", pts = {from}}
            walk.pts[#walk.pts + 1] = n
            walk.to = n
        else
            if walk then legs[#legs + 1] = walk; walk = nil end
            legs[#legs + 1] = {kind = how.kind, from = from, to = n, pts = {from, n}}
        end
    end
    if walk then legs[#legs + 1] = walk end

    -- what each leg says
    local out = {}
    for k, leg in ipairs(legs) do
        local n = leg.to
        local nextLeg = legs[k + 1]
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
                    local zone = ZoneName(target.map)
                    leg.text = zone and fmt(L("Head into %s"), zone) or L("Walk the rest of the way")
                else
                    leg.text = fmt(L("Walk to %s"), n.name or "?")
                end
                if through and n ~= target or (through and n == target) then
                    leg.text = leg.text .. fmt(L(" (through %s)"), through)
                end
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

---------------------------------------------------------------------------
-- The plan for the arrow's target
---------------------------------------------------------------------------

local lastAt, lastKey = 0, nil

-- Works out (at most every REPLAN seconds) how to get to `target` (an arrow
-- element with wx, wy, instance, zone) when it's in another zone. Returns
-- the plan or nil when the arrow can go straight there.
function tv.PlanFor(target)
    if not (target and target.wx and target.zone) then tv.plan = nil return end
    local px, py, pinst = HBD:GetPlayerWorldPosition()
    local _, _, pmap = HBD:GetPlayerZonePosition()
    if not px then return tv.plan end
    if UnitOnTaxi and UnitOnTaxi("player") then return tv.plan end -- keep the plan while flying
    if pmap == target.zone then tv.plan = nil return end
    local now = GetTime and GetTime() or 0
    local key = fmt("%s:%d:%d", tostring(target.zone), floor(target.wx), floor(target.wy))
    if key == lastKey and now - lastAt < REPLAN then return tv.plan end
    lastKey, lastAt = key, now

    local from = {wx = px, wy = py, inst = pinst, zones = {[pmap or 0] = true}, name = L("you"), kind = "you"}
    local to = {wx = target.wx, wy = target.wy, inst = target.instance, zones = {[target.zone] = true},
                name = target.title, kind = "target", map = target.zone}
    local path = Search(from, to)
    if not path then tv.plan = nil return end
    local legs = Legs(path, to)
    -- just walking over the border with nothing in between: the arrow
    -- copes with that by itself
    if #legs == 0 or (#legs == 1 and legs[1].kind == "walk" and #legs[1].pts <= 2) then
        tv.plan = nil
        return
    end
    tv.plan = {legs = legs, target = target, at = now, from = from}
    return tv.plan
end

-- The first thing to head for: {wx, wy, instance, title}
local proxy = {}
function tv.ArrowTarget(real)
    if not (tv.IsOn() and real) then return end
    local plan = tv.PlanFor(real)
    local leg = plan and plan.legs[1]
    if not leg then return end
    local n
    if leg.kind == "walk" then
        -- the next border or stop along the walk
        n = leg.pts[2] or leg.to
        local px, py = HBD:GetPlayerWorldPosition()
        for i = 2, #leg.pts do
            local p = leg.pts[i]
            local dx, dy = (p.wx - (px or 0)), (p.wy - (py or 0))
            if dx * dx + dy * dy > 30 * 30 then n = p break end
        end
    else
        n = leg.from or leg.to -- stand at the flight master / dock
    end
    if not n or n.kind == "target" then return end
    proxy.wx, proxy.wy, proxy.instance = n.wx, n.wy, n.inst
    proxy.zone = NodeZone(n)
    proxy.title = leg.text
    proxy.step, proxy.real, proxy.travel = real.step, real, true
    return proxy
end

function tv.IsOn()
    local p = addon.settings and addon.settings.profile
    return not (p and p.openxpTravel == false)
end

-- The plan, while the arrow still uses it
function tv.Current()
    local plan = tv.plan
    if not plan or not tv.IsOn() then return end
    local now = GetTime and GetTime() or 0
    if now - (plan.at or 0) > 10 and not (UnitOnTaxi and UnitOnTaxi("player")) then return end
    return plan
end

-- Lines for the card: "1. Fly to Menethil Harbor", ...
function tv.Lines()
    local plan = tv.Current()
    if not plan then return end
    local out = {}
    for i, leg in ipairs(plan.legs) do
        out[#out + 1] = fmt("%d. %s", i, leg.text)
    end
    return out
end

-- The route on `map` as polylines of map points (0-100), or nil
local lineCache = {}
function tv.Polylines(map, level)
    local plan = tv.Current()
    if not (plan and map) then return end
    local px, py, pmap = HBD:GetPlayerZonePosition()
    local key = tostring(plan) .. ":" .. map .. ":" .. floor((px or 0) * 200) .. ":" .. floor((py or 0) * 200)
    if lineCache.key == key then return lineCache.lines end
    -- only what's on this map's continent
    local _, _, mapInst = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, map)
    local function P(n)
        if mapInst and n.inst ~= mapInst then return end
        local x, y = HBD:GetZoneCoordinatesFromWorld(n.wx, n.wy, map, true)
        if x then return {x * 100, y * 100} end
    end
    local lines = {}
    local wx, wy, winst = HBD:GetPlayerWorldPosition()
    local cur = {wx = wx, wy = wy, inst = winst}
    for k, leg in ipairs(plan.legs) do
        local line = {}
        local pts = leg.pts
        if k == 1 then
            local me = P(cur)
            if me then line[#line + 1] = me end
        end
        for i = (k == 1 and 2 or 1), #pts do
            local a = P(pts[i])
            if a then
                -- in your own zone, walk round mountains like the arrow does
                local last = line[#line]
                local tr = addon.terrain
                if leg.kind == "walk" and last and map == pmap and tr and tr.FindPath then
                    local way = tr.FindPath(map, last[1], last[2], a[1], a[2], level or 1)
                    for _, w in ipairs(way or {}) do line[#line + 1] = {w[1], w[2]} end
                    if not way then line[#line + 1] = a end
                else
                    line[#line + 1] = a
                end
            end
        end
        -- only what's on this map, give or take
        local keep = {}
        for _, p in ipairs(line) do
            if p[1] > -20 and p[1] < 120 and p[2] > -20 and p[2] < 120 then keep[#keep + 1] = p end
        end
        if #keep >= 2 then lines[#lines + 1] = keep end
    end
    lineCache.key, lineCache.lines = key, lines
    return lines
end

---------------------------------------------------------------------------
-- Keep the arrow up while the next step is on the other continent, and
-- remember where the Hearthstone was set
---------------------------------------------------------------------------

local origUpdate = addon.UpdateGotoSteps
if origUpdate then
    addon.UpdateGotoSteps = function(...)
        local r = origUpdate(...)
        local af = addon.arrowFrame
        if af and af.wrongContinent and af.element and tv.ArrowTarget(af.element) then
            addon.hideArrow = false
            if not (addon.settings and addon.settings.profile and addon.settings.profile.disableArrow) then
                af:Show()
            end
        end
        return r
    end
end

local events = CreateFrame and CreateFrame("Frame")
if events then
    events:RegisterEvent("HEARTHSTONE_BOUND")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function(_, event)
        if event == "HEARTHSTONE_BOUND" and OXPCData then
            local wx, wy, inst = HBD:GetPlayerWorldPosition()
            local _, _, map = HBD:GetPlayerZonePosition()
            if wx then
                OXPCData.openxpHearth = {wx = wx, wy = wy, inst = inst, map = map,
                                         name = GetBindLocation and GetBindLocation()}
            end
        end
        tv.plan = nil
        lastKey = nil
    end)
end
