-- Baked walking paths from the optional OpenXP_Nav add-on.
--
-- SoupEngine walks every leg of the guide route on SoupNav's walking map
-- ahead of time and writes the corners of each walk into OpenXP_Nav
-- (a separate, load-on-demand add-on folder next to OpenXP). When it is
-- installed, the arrow points at the next corner of the baked walk to the
-- guide's spot instead of straight at the spot, the same way it follows
-- path hints (Nav/PathHints.lua). Without it nothing changes.
--
-- OpenXP_Nav's data (see docs/2.0/SOUPENGINE.md):
--   paths["map:x,y>map:x,y"] = { x1, y1, z1, indoor1, x2, ... }  one walk, map %
--   spots["map:x,y"]         = { z, indoor }                     a guide spot's floor
--   targets["quest:obj"]     = { {map, x, y, z, indoor, id, kind}, ... }  named mobs, chests
--   graveyards["map:x,y"]    = { z, indoor }                     spirit healers
--   packed[map]              = SoupNav's packed zone graph (Nav/WalkGraph.lua)
-- Keys have two decimals, like the guide's own goto x and y. Walks to a
-- target are keyed "<spot>><target>", walks from a graveyard
-- "<graveyard>><spot>". targets and graveyards are newer: an older
-- OpenXP_Nav without them still works.
local _, OXP = ...

local WP = {}
OXP.WalkPaths = WP

local Places = OXP.Places
local fmt, sqrt, huge, floor = string.format, math.sqrt, math.huge, math.floor

local NEAR = 40       -- yards: further than this from every baked walk, the arrow doesn't use them
local REACH = 8       -- yards: a corner this close is passed
local THROTTLE = 0.2  -- seconds between corner updates
local TIE = 3         -- yards: see Nearest

local nav             -- OpenXP_Nav's table, once loaded
local byEnd = {}      -- ["map:x,y"] = { leg, ... }; leg = { map = n, key = s, flat = {...} }
local tried = false

local function SpotKey(map, x, y)
    return fmt("%d:%.2f,%.2f", map, x, y)
end
WP.SpotKey = SpotKey

local byMap = {}       -- [map] = { leg, ... }: every leg, by the map of the spot it ends on
local passing = {}     -- ["map:x,y"] = { leg, ... } or false: walks through a spot, cut there

local function Index(data)
    byEnd, byMap, passing = {}, {}, {}
    local legs, gy = 0, type(data.graveyards) == "table" and data.graveyards or {}
    for key, flat in pairs(data.paths) do
        local from, to = key:match("^(.-)>(.+)$")
        local map = to and tonumber(to:match("^(%d+):"))
        if map and type(flat) == "table" and #flat >= 8 then
            local list = byEnd[to]
            if not list then
                list = {}
                byEnd[to] = list
            end
            local leg = { map = map, key = key, flat = flat, graveyard = gy[from] ~= nil }
            list[#list + 1] = leg
            byMap[map] = byMap[map] or {}
            byMap[map][#byMap[map] + 1] = leg
            legs = legs + 1
        end
    end
    WP.legs = legs
end

--- Use this OpenXP_Nav table (tests hand one in; nil turns paths off).
function WP.Use(data)
    if type(data) == "table" and type(data.paths) == "table" then
        nav = data
        Index(data)
    else
        nav, byEnd, byMap, passing, WP.legs = nil, {}, {}, {}, 0
    end
    if OXP.WalkGraph then OXP.WalkGraph.Reset() end
    WP.Reset()
end

--- Load OpenXP_Nav if it is installed and enabled. Returns its table or nil.
function WP.Load()
    if nav or tried then return nav end
    tried = true
    local data = rawget(_G, "OpenXP_Nav")
    if not data then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or rawget(_G, "LoadAddOn")
        if load then pcall(load, "OpenXP_Nav") end
        data = rawget(_G, "OpenXP_Nav")
    end
    WP.Use(data)
    return nav
end

function WP.IsLoaded() return nav ~= nil end

--- SoupEngine's pinpoints for a quest objective: { {map, x, y, z, indoor, id,
--- kind ("npc"|"object")}, ... }, or nil (none baked, or an older OpenXP_Nav).
function WP.Targets(quest, obj)
    local t = nav and type(nav.targets) == "table" and nav.targets[quest .. ":" .. obj]
    if type(t) == "table" and #t > 0 then return t end
end

-- After a death (a ghost, or for a while after you're back) walks from a
-- spirit healer come first.
local AFTER_DEATH = 120 -- seconds after you're alive again
local deadAt = -huge

function WP.AfterDeath()
    local now = GetTime and GetTime() or 0
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        deadAt = now
        return true
    end
    return now - deadAt <= AFTER_DEATH
end

--- A guide spot's floor from OpenXP_Nav: z (yards), indoor (true/false); nil if unknown.
function WP.Floor(map, x, y)
    local s = nav and nav.spots and nav.spots[SpotKey(map, x, y)]
    if s then return s[1], s[2] == 1 end
end

-- The leg's corners in world coordinates (worked out once per leg).
local function Corners(leg)
    if leg.wx then return leg end
    local wx, wy, inst = {}, {}, nil
    local flat = leg.flat
    for i = 1, #flat - 3, 4 do
        local x, y, ins = Places.ToWorld(leg.map, flat[i], flat[i + 1])
        if not x then return nil end
        wx[#wx + 1], wy[#wy + 1], inst = x, y, ins
    end
    leg.wx, leg.wy, leg.instance = wx, wy, inst
    return leg
end

-- Distance from (px, py) to the segment a-b, and the nearest point on it.
local function SegDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local f = 0
    if len2 > 0 then
        f = ((px - ax) * dx + (py - ay) * dy) / len2
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
    end
    local cx, cy = ax + f * dx, ay + f * dy
    return sqrt((px - cx) ^ 2 + (py - cy) ^ 2), cx, cy
end

-- Of `legs`, the one passing nearest (px, py): leg, segment, distance and
-- the nearest point on it (world).
local function Nearest(legs, px, py, inst)
    local best, bestSeg, bestD, bx, by = nil, nil, huge, nil, nil
    for _, leg in ipairs(legs or {}) do
        local c = Corners(leg)
        if c and c.instance == inst then
            for i = 1, #c.wx - 1 do
                local d, cx, cy = SegDist(px, py, c.wx[i], c.wy[i], c.wx[i + 1], c.wy[i + 1])
                -- on a walk that comes back past itself, the later part wins a
                -- near tie: you're on your way, not at the start again
                if d < bestD or (c == best and d <= bestD + TIE) then
                    best, bestSeg, bestD, bx, by = c, i, math.min(d, bestD), cx, cy
                end
            end
        end
    end
    return best, bestSeg, bestD, bx, by
end

-- Walks to a spot. SoupEngine keys each walk by the guide spot it ends on
-- (corners in that spot's map %, below 0 or above 100 where the walk is
-- still in the zone before, e.g. through a tunnel from the next zone). A spot
-- some walk only passes through on its way on (a "reach" waypoint like the
-- Talondeep Path's exit) gets that walk cut where it passes nearest the spot.
local PASS = 30 -- yards: a walk this close to a spot passes through it

local function LegsTo(map, x, y)
    local key = SpotKey(map, x, y)
    if byEnd[key] then return byEnd[key] end
    if passing[key] ~= nil then return passing[key] or nil end
    local tx, ty, tinst = Places.ToWorld(map, x, y)
    local found = {}
    if tx then
        for _, leg in ipairs(byMap[map] or {}) do
            local c = Corners(leg)
            if c and c.instance == tinst then
                local bestD, bestSeg = huge, nil
                for i = 1, #c.wx - 1 do
                    local d = SegDist(tx, ty, c.wx[i], c.wy[i], c.wx[i + 1], c.wy[i + 1])
                    if d < bestD then bestD, bestSeg = d, i end
                end
                if bestSeg and bestD <= PASS then
                    local flat = {}
                    for k = 1, bestSeg * 4 do flat[k] = leg.flat[k] end
                    flat[#flat + 1], flat[#flat + 2], flat[#flat + 3], flat[#flat + 4] = x, y, 0, 0
                    found[#found + 1] = { map = map, key = leg.key .. "|" .. key, flat = flat, through = true, graveyard = leg.graveyard }
                end
            end
        end
    end
    passing[key] = #found > 0 and found or false
    return passing[key] or nil
end

-- A walk worked out on SoupNav's zone graph (Nav/WalkGraph.lua) from the
-- player to `target`, as a leg like the baked ones; kept while you stay on
-- it, worked out again (at most once a second) when you leave it.
local GRAPH_AGAIN = 1
local graphLeg = { key = nil, leg = nil, at = -huge }

local function FlatLeg(map, pts, key)
    local flat = {}
    for _, p in ipairs(pts) do
        flat[#flat + 1], flat[#flat + 2], flat[#flat + 3], flat[#flat + 4] = p[1], p[2], 0, 0
    end
    if #flat < 8 then return nil end
    return { map = map, key = key, flat = flat, graph = true }
end

-- Of the walks to a spot, the ones that fit now: from a graveyard after a
-- death, else the guide's own (the others are the fallback).
local function Preferred(legs)
    if not legs then return nil, nil end
    local want = WP.AfterDeath()
    local pick, any = {}, false
    for _, leg in ipairs(legs) do
        if leg.graveyard then any = true end
        if (leg.graveyard or false) == want then pick[#pick + 1] = leg end
    end
    if not any and not want then return legs, nil end
    return pick, legs
end

-- The walk length of map points on `map`, in yards.
local function Length(map, pts)
    local d, lx, ly = 0, nil, nil
    for _, p in ipairs(pts) do
        local x, y = Places.ToWorld(map, p[1], p[2])
        if not x then return huge end
        if lx then d = d + Places.Distance(lx, ly, x, y) end
        lx, ly = x, y
    end
    return d
end

-- A way from (ax, ay) to the spot (bx, by) on `map` (map %) that nothing is
-- baked for, as points from a to b. SoupNav's graph alone can miss a ramp
-- or a gap a baked walk to the same spot takes (Whelgar's Excavation Site
-- from the Wetlands road: the graph went round by Thelgen Rock), so this
-- also tries joining a baked walk to the spot where it passes nearest a
-- (straight onto it when it's within NEAR yards, else along the graph to
-- that point) and takes the shorter of the two.
local function Unbaked(map, ax, ay, bx, by)
    local graph = OXP.WalkGraph and nav and nav.packed and OXP.WalkGraph.Route(nav, map, ax, ay, bx, by) or nil
    local joined
    local legs = Preferred(LegsTo(map, bx, by))
    local wx, wy, inst = Places.ToWorld(map, ax, ay)
    if legs and wx then
        local best, seg, d, jx, jy = Nearest(legs, wx, wy, inst)
        local zx, zy
        if best then zx, zy = Places.ToZone(jx, jy, map, true) end
        if zx then
            local head
            if d <= NEAR then
                head = { { ax, ay }, { zx, zy } }
            elseif OXP.WalkGraph and nav.packed then
                head = OXP.WalkGraph.Route(nav, map, ax, ay, zx, zy)
            end
            if head then
                joined = {}
                for _, p in ipairs(head) do joined[#joined + 1] = { p[1], p[2] } end
                local flat = best.flat
                for k = seg + 1, #best.wx do joined[#joined + 1] = { flat[k * 4 - 3], flat[k * 4 - 2] } end
            end
        end
    end
    if joined and graph then
        return Length(map, joined) < Length(map, graph) and joined or graph
    end
    return joined or graph
end
WP.Unbaked = Unbaked

local function GraphLeg(target, key, px, py, inst)
    if not (nav and nav.packed and OXP.WalkGraph) then return nil end
    local cached = graphLeg.key == key and graphLeg.leg
    if cached then
        local _, _, d = Nearest({ cached }, px, py, inst)
        if d <= NEAR then return cached end
    end
    local now = GetTime and GetTime() or 0
    if graphLeg.key == key and now - graphLeg.at < GRAPH_AGAIN then return cached or nil end
    graphLeg.key, graphLeg.at, graphLeg.leg = key, now, nil
    local zx, zy = Places.ToZone(px, py, target.map)
    if not zx then return nil end
    local pts = Unbaked(target.map, zx, zy, target.x, target.y)
    graphLeg.leg = pts and FlatLeg(target.map, pts, "graph>" .. key) or nil
    return graphLeg.leg
end

-- The walk to `target` passing nearest (px, py): SoupEngine's baked walks
-- first; when none is baked to the spot or you're more than NEAR yards off
-- them, one worked out on SoupNav's graph from where you stand. Returns the
-- leg, the index of the next corner ahead on it, the distance to the walk
-- and the nearest point on it (world); nil when there's no walk at all.
local function Ahead(target, px, py, inst)
    if not (target and target.map and target.x and target.y and px) then return nil end
    local key = SpotKey(target.map, target.x, target.y)
    local first, all = Preferred(LegsTo(target.map, target.x, target.y))
    local best, bestSeg, bestD, bx, by = Nearest(first, px, py, inst)
    if all and (not best or bestD > NEAR) then
        local b2, s2, d2, x2, y2 = Nearest(all, px, py, inst)
        if b2 and d2 < bestD then best, bestSeg, bestD, bx, by = b2, s2, d2, x2, y2 end
    end
    if not best or bestD > NEAR then
        local gl = GraphLeg(target, key, px, py, inst)
        if gl then
            local b2, s2, d2, x2, y2 = Nearest({ gl }, px, py, inst)
            if b2 and d2 < bestD then best, bestSeg, bestD, bx, by = b2, s2, d2, x2, y2 end
        end
    end
    if not best then return nil end
    local n = #best.wx
    local j = bestSeg + 1
    while j < n and Places.Distance(px, py, best.wx[j], best.wy[j]) <= REACH do j = j + 1 end
    return best, j, bestD, bx, by, bestSeg
end

--- Where the arrow should point on the baked walk to `target` for a player
--- at px, py: wx, wy. Off the walk (more than NEAR yards): the nearest point
--- on it, to lead you back. On it: the next corner ahead. nil when nothing is
--- baked to the spot, or the spot itself is next.
function WP.NextCorner(target, px, py, inst)
    local best, j, d, bx, by = Ahead(target, px, py, inst)
    if not best then return nil end
    local n = #best.wx
    if d > NEAR then
        if Places.Distance(bx, by, best.wx[n], best.wy[n]) <= REACH then return nil end
        return bx, by
    end
    if j >= n then return nil end -- the last corner is the spot: the arrow's own target
    return best.wx[j], best.wy[j]
end

--- For the map's route line: the points (map %, on target.map) from a
--- player at world px, py along the baked walk to `target`, ending on the
--- spot: first the nearest point on the walk when you're off it. nil when
--- nothing is baked to the spot.
function WP.RouteFrom(target, px, py, inst)
    local best, _, d, bx, by, seg = Ahead(target, px, py, inst)
    if not best then return nil end
    local out, flat = {}, best.flat
    -- from you onto the walk where it passes nearest, then on along every
    -- corner after that (none skipped, so the line never cuts a corner)
    if d > 1 then
        local x, y = Places.ToZone(bx, by, target.map, true)
        if x then out[1] = { x, y } end
    end
    for k = seg + 1, #best.wx do out[#out + 1] = { flat[k * 4 - 3], flat[k * 4 - 2] } end
    return out
end

--- The corners (map %, on b's map) of the walk from one guide spot to the
--- next, ending on b: SoupEngine's baked walk, else (same map only) one on
--- SoupNav's graph; nil when there's neither.
local between = {}   -- graph walks between spots, worked out once: [key] = pts or false

function WP.Between(amap, ax, ay, bmap, bx, by)
    if not nav then return nil end
    local key = SpotKey(amap, ax, ay) .. ">" .. SpotKey(bmap, bx, by)
    local flat = nav.paths[key]
    local out = {}
    if flat then
        for i = 5, #flat - 3, 4 do out[#out + 1] = { flat[i], flat[i + 1] } end
        return out
    end
    if amap ~= bmap then return nil end
    -- not baked: SoupNav's graph (Nav/WalkGraph.lua), or onto a baked walk
    -- to b (Unbaked)
    if between[key] == nil then
        between[key] = Unbaked(amap, ax, ay, bx, by) or false
    end
    local pts = between[key]
    if not pts then return nil end
    for i = 2, #pts do out[#out + 1] = pts[i] end
    return out
end

--- Where the arrow aims on the walk to `target` for a player at px, py, and
--- how far there is still to walk: wx, wy, yards. On the walk, a point LOOK
--- yards further along it from where you are (so the arrow turns smoothly
--- before each corner instead of snapping, and never "arrives" at a
--- corner); off it (more than NEAR yards), the nearest point on it. nil when
--- there's no walk or the spot itself is within LOOK yards along it.
local LOOK = 18 -- yards along the walk ahead of you

--- Are you on (within NEAR yards of) a baked SoupEngine walk to `target`?
--- A walk worked out on SoupNav's zone graph doesn't count.
function WP.OnWalk(target)
    if not nav then return false end
    local px, py, inst = Places.Player()
    local best, _, d = Ahead(target, px, py, inst)
    return best ~= nil and not best.graph and (d or huge) <= NEAR
end

function WP.Carrot(target, px, py, inst)
    local best, _, d, bx, by, seg = Ahead(target, px, py, inst)
    if not best then return nil end
    local wx, wy, n = best.wx, best.wy, #best.wx
    -- what's left of the walk from the nearest point on it to the spot
    local left = Places.Distance(bx, by, wx[seg + 1], wy[seg + 1])
    for k = seg + 1, n - 1 do left = left + Places.Distance(wx[k], wy[k], wx[k + 1], wy[k + 1]) end
    if d > NEAR then
        if Places.Distance(bx, by, wx[n], wy[n]) <= REACH then return nil end
        return bx, by, d + left
    end
    local need, ax, ay = LOOK, bx, by
    for k = seg + 1, n do
        local step = Places.Distance(ax, ay, wx[k], wy[k])
        if step >= need then
            if k == n and step - need < REACH then return nil end
            local f = need / step
            return ax + (wx[k] - ax) * f, ay + (wy[k] - ay) * f, d + left
        end
        need = need - step
        ax, ay = wx[k], wy[k]
    end
    return nil -- the spot is just ahead: the arrow's own target
end

local proxy = {}
local lastTarget, lastCheck, lastX, lastY, lastTX, lastTY, lastLeft = nil, -huge, nil, nil, nil, nil, nil

function WP.Reset()
    graphLeg.key, graphLeg.leg, graphLeg.at = nil, nil, -huge
    between = {}
    lastTarget, lastCheck, lastX, lastY, lastTX, lastTY, lastLeft = nil, -huge, nil, nil, nil, nil, nil
end

--- A stepping stone for the arrow toward `target` ({wx, wy, instance, map,
--- x, y, title}), or nil.
function WP.ForArrow(target)
    if not nav or not target or target == proxy then return nil end
    local now = GetTime and GetTime() or 0
    if target ~= lastTarget or target.x ~= lastTX or target.y ~= lastTY or now - lastCheck >= THROTTLE then
        lastTarget, lastCheck, lastTX, lastTY = target, now, target.x, target.y
        local px, py, inst = Places.Player()
        lastX, lastY, lastLeft = WP.Carrot(target, px, py, inst)
    end
    if not lastX then return nil end
    proxy.wx, proxy.wy, proxy.instance, proxy.map = lastX, lastY, target.instance, target.map
    proxy.title, proxy.real, proxy.walkPath, proxy.left = target.title, target, true, lastLeft
    return proxy
end

--- /oxp nav: is OpenXP_Nav loaded, and is there a baked walk to the arrow's spot?
function WP.Command()
    if not nav then
        OXP.Print("OpenXP_Nav isn't loaded: no SoupEngine walks. Check it's enabled in the AddOns list, then restart the game.")
        return
    end
    local function Count(t)
        local n = 0
        for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
        return n
    end
    OXP.Print(("OpenXP_Nav loaded: %d SoupEngine walks, %d pinpointed targets, %d graveyards."):format(
        WP.legs or 0, Count(nav.targets), Count(nav.graveyards)))
    local real = OXP.Target.Real and OXP.Target.Real()
    if not (real and real.x) then OXP.Print("No guide spot to walk to right now.") return end
    local px, py, inst = Places.Player()
    local best, _, d = Ahead(real, px, py, inst)
    local key = SpotKey(real.map, real.x, real.y)
    if not best then
        OXP.Print(("No walk to this step's spot (%s): nothing baked and no graph way from here."):format(key))
    else
        OXP.Print(("Walk to this step's spot (%s): %s; you're %d yards from it%s."):format(key,
            best.graph and "worked out on SoupNav's zone graph"
                or best.graveyard and "SoupEngine's walk from the graveyard" or "SoupEngine's baked walk", floor(d + 0.5),
            d > NEAR and " (the arrow leads you back onto it)" or ""))
    end
end
OXP.AddCommand("nav", "SoupEngine walks: loaded? one to this step?", function() WP.Command() end)

OXP.OnReady(function() WP.Load() end)
