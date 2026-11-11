-- Terrain-aware arrow (Terrain.lua + DB/terrain.lua): ways around Duskwood's
-- cliffs and mountains, and around packs well above your level.
local ROOT = ...

local level = 22
UnitLevel = function() return level end
local clock = 0
GetTime = function() return clock end
-- Duskwood as a flat 1000x1000 world square so world <-> zone is easy
local HBD = {
    GetZoneCoordinatesFromWorld = function(_, x, y, map)
        if map ~= 1431 then return end
        return x / 1000, y / 1000
    end,
    GetWorldCoordinatesFromZone = function(_, x, y, map)
        if map ~= 1431 then return end
        return x * 1000, y * 1000, 0
    end,
}
LibStub = function() return HBD end

local addon = {}
assert(loadfile(ROOT .. "/DB/terrain.lua"))("OpenXP", addon)
assert(loadfile(ROOT .. "/Terrain.lua"))("OpenXP", addon)
local tr = addon.terrain
-- the route tests below are about where the line goes, not how its searches
-- are spread over frames (that has its own tests at the end)
tr.lazyPerFrame = math.huge

local fails = 0
local function try(label, fn)
    tr.Reset()
    level, clock = 22, 0
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end

local function show(pts)
    local s = {}
    for _, p in ipairs(pts or {}) do s[#s + 1] = string.format("(%.1f,%.1f)", p[1], p[2]) end
    return table.concat(s, " ")
end

local function crosses(pts, ax, ay, test)
    local px, py = ax, ay
    for _, p in ipairs(pts) do
        for s = 0, 20 do
            local x, y = px + (p[1] - px) * s / 20, py + (p[2] - py) * s / 20
            if test(x, y) then return true end
        end
        px, py = p[1], p[2]
    end
end

try("Darkshire to the northern spiders: up the road, not into the cliff", function()
    local pts = tr.FindPath(1431, 75.3, 48.7, 66.7, 17.9, 22)
    assert(pts, "should go around")
    -- the cliff runs along x 69-71 between y 30 and 55; never cross west of it there
    assert(not crosses(pts, 75.3, 48.7, function(x, y) return y > 30 and y < 55 and x < 70 end), show(pts))
    assert(pts[#pts][1] == 66.7 and pts[#pts][2] == 17.9, "ends on the target")
end)

try("open ground: straight there", function()
    assert(tr.FindPath(1431, 18.4, 56.4, 25.0, 50.0, 22) == nil)
end)

try("around the Twilight Grove mountains", function()
    local pts = tr.FindPath(1431, 30.0, 40.0, 65.0, 40.0, 30)
    assert(pts, "should go around")
    assert(not crosses(pts, 30, 40, function(x, y) return x > 37 and x < 57 and y > 25 and y < 55 end), show(pts))
end)

local function length(pts, ax, ay)
    local d, px, py = 0, ax, ay
    for _, p in ipairs(pts or {{0, 0}}) do
        d = d + math.sqrt((p[1] - px) ^ 2 + (p[2] - py) ^ 2)
        px, py = p[1], p[2]
    end
    return d
end

try("level 22 walks around the Raven Hill Cemetery undead, level 31 nearly through", function()
    local low = tr.FindPath(1431, 12.0, 45.0, 30.0, 30.0, 22)
    local high = tr.FindPath(1431, 12.0, 45.0, 30.0, 30.0, 31)
    assert(low, "level 22: a way around")
    assert(not high or #high <= 3, "level 31: at most a small bend: " .. show(high))
    local straight = math.sqrt(18 ^ 2 + 15 ^ 2)
    assert(not high or length(high, 12, 45) < straight * 1.1, "level 31: " .. show(high))
    assert(length(low, 12, 45) > length(high or {{30, 30}}, 12, 45), "level 22 goes further round")
end)

try("arrow points at the corners in order and then lets go", function()
    local t = {wx = 667, wy = 179, instance = 0}
    local ctx = {zone = 1431}
    local pt = tr.Route(t, 753, 487, 0, ctx)
    assert(pt, "points at a corner first")
    local pts = tr.FindPath(1431, 75.3, 48.7, 66.7, 17.9, 22)
    -- walk through every corner but the target
    for i = 1, #pts - 1 do
        clock = clock + 1
        pt = tr.Route(t, pts[i][1] * 10, pts[i][2] * 10, 0, ctx)
    end
    assert(pt == nil, "straight at the target after the last corner")
end)

try("other zones: no terrain, straight line", function()
    assert(tr.Route({wx = 1, wy = 1, instance = 0}, 2, 2, 0, {zone = 1429}) == nil)
end)

try("spawn marks: the mobs an item objective drops from, on this map", function()
    addon.card = {QGet = function(kind, id)
        if kind == "Quest" and id == 101 then
            return {objectives = {{{48}}, nil, {{1130}}}}
        elseif kind == "Item" and id == 1130 then
            return {npcDrops = {217, 539}}
        elseif kind == "NPC" and id == 217 then
            return {spawns = {[10] = {{10.5, 55.2}, {11.0, 52.3}}, [12] = {{1, 1}}}}
        elseif kind == "NPC" and id == 539 then
            return {spawns = {[10] = {{9.7, 51.1}}}}
        elseif kind == "NPC" and id == 48 then
            return {spawns = {[10] = {{79, 69}}}}
        end
    end}
    local pts = tr.ObjectiveSpawns(101, 2, 10)
    assert(#pts == 3, "three spiders in Duskwood: " .. #pts)
    local skel = tr.ObjectiveSpawns(101, 1, 10)
    assert(#skel == 1 and skel[1][1] == 79, "objective 1 is the creature")
    addon.card = nil
end)

try("kill area: Here inside it, the nearest edge from outside", function()
    local me = {x = 10, y = 55}
    HBD.GetPlayerZonePosition = function() return me.x / 100, me.y / 100, 1431 end
    HBD.GetPlayerWorldPosition = function() return me.x * 10, me.y * 10, 0 end
    local step = {}
    step.elements = {{area = {{8.85, 62.27}, {9.23, 48.18}, {12.47, 49.82}, {12.43, 60.62}}, areaZone = 1431}}
    local goto = {wx = 107.5, wy = 553.9, instance = 0, step = step}
    local t = tr.AreaTarget(goto)
    assert(t and t.inside, "inside the spiders' area")
    me.x, me.y = 20, 55
    t = tr.AreaTarget(goto)
    assert(t and not t.inside, "outside")
    local x, y = HBD:GetZoneCoordinatesFromWorld(t.wx, t.wy, 1431)
    assert(tr.InsidePoly(step.elements[1].area, x * 100, y * 100), "leads just inside the edge")
    assert(math.abs(x * 100 - 12) < 1, "the near (east) edge: " .. x * 100)
    assert(tr.AreaTarget({wx = 1, wy = 1, instance = 0, step = {elements = {}}}) == nil, "no area: nil")
end)

-- a stand-in for WoW frames: every method exists and does nothing
local function Fake(extra)
    local o = extra or {}
    return setmetatable(o, {__index = function(t, k)
        return function(self, ...)
            if k == "CreateLine" or k == "CreateTexture" then
                rawset(t, "made", (rawget(t, "made") or 0) + 1)
                return Fake()
            end
            if k == "GetWidth" or k == "GetHeight" then return 1000 end
            if k == "GetFrameLevel" or k == "GetZoom" then return 1 end
            if k == "IsShown" then return true end
        end
    end})
end

try("fill: rows of flat rectangles inside the shape, cut to a circle", function()
    local lines = {}
    local c = {frame = Fake(), lines = {}, tex = {}, nl = 0, nt = 0}
    c.frame.CreateTexture = function()
        local t = Fake()
        t.SetPoint = function(_, _, _, _, x, y) t.x1, t.y1 = x, -y end
        t.SetSize = function(_, w) t.x2 = t.x1 + w; lines[#lines + 1] = t end
        return t
    end
    tr.draw.Fill(c, {{0, 0}, {100, 0}, {100, 100}, {0, 100}}, {1, 1, 1, 1}, 10)
    assert(#lines == 10, "ten rows: " .. #lines)
    assert(lines[1].x1 == 0 and lines[1].x2 == 100)
    lines = {}
    c.nr = 0
    c.rects = {}
    tr.draw.Fill(c, {{0, 0}, {100, 0}, {100, 100}, {0, 100}}, {1, 1, 1, 1}, 10, {50, 50, 20})
    for _, l in ipairs(lines) do
        assert(l.x1 >= 29.9 and l.x2 <= 70.1, "inside the circle")
    end
    local ax, _, bx = tr.draw.ClipSegment(0, 50, 100, 50, {50, 50, 20})
    assert(math.abs(ax - 30) < 0.01 and math.abs(bx - 70) < 0.01)
    assert(tr.draw.ClipSegment(0, 0, 10, 0, {50, 50, 20}) == nil)
end)

try("world map and minimap draw without errors", function()
    local me = {x = 20, y = 55}
    HBD.GetPlayerZonePosition = function() return me.x / 100, me.y / 100, 1431 end
    HBD.GetPlayerWorldPosition = function() return me.x * 10, me.y * 10, 0 end
    CreateFrame = function() return Fake() end
    GetCVar = function() return "0" end
    wipe = function(t) for k in pairs(t) do t[k] = nil end end
    local area = {area = {{8.85, 62.27}, {9.23, 48.18}, {12.47, 49.82}, {12.43, 60.62}}, areaZone = 1431}
    local s1 = {elements = {{arrow = true, zone = 1431, x = 10.75, y = 55.39}, area}}
    local s2 = {elements = {{arrow = true, zone = 1431, x = 7.78, y = 34.07}}}
    addon.currentGuide = {steps = {s1, s2}}
    addon.GetGuideProgress = function() return 1 end
    addon.RXPFrame = {activeSteps = {s1}}
    local canvas = Fake()
    _G.WorldMapFrame = Fake({GetCanvas = function() return canvas end, GetMapID = function() return 1431 end})
    _G.Minimap = Fake()
    tr.DrawMap()
    tr.DrawMinimap()
    local route = tr.draw.RoutePoints(1431, 20, 55, tr.draw.Upcoming(), 22)
    assert(#route >= 3, "you, the area, then Sven: " .. #route)
    me.x, me.y = 10.5, 55
    route = tr.draw.RoutePoints(1431, 10.5, 55, tr.draw.Upcoming(), 22)
    assert(route[#route][2] == 34.07, "inside the area: straight on to the next step")
    _G.WorldMapFrame, _G.Minimap, addon.currentGuide, addon.RXPFrame = nil, nil, nil, nil
end)

try("route line: skips steps ahead for quests you don't have and won't pick up", function()
    local function at(x, y, ...)
        local el = {{arrow = true, zone = 1453, x = x, y = y}}
        for _, e in ipairs({...}) do el[#el + 1] = e end
        return {elements = el}
    end
    local steps = {
        at(50, 50, {tag = "accept", questId = 343}),          -- you're here
        at(80, 38, {tag = "turnin", questId = 98190}),        -- never picked up
        at(48, 50, {tag = "turnin", questId = 98191}),        -- follow-up of it
        at(77, 30, {tag = "turnin", questId = 343}),          -- picked up on the way
    }
    addon.currentGuide = {steps = steps}
    addon.GetGuideProgress = function() return 1 end
    addon.card = {MissingQuest = function(step)
        for _, e in ipairs(step.elements) do
            if e.tag == "turnin" then return e.questId end
        end
    end}
    local up = tr.draw.Upcoming()
    assert(#up == 2 and up[2][2] == 77, "you, then Milton: " .. #up)
    addon.currentGuide, addon.card = nil, nil
end)

try("every zone: a kill step without .area gets one from Questie's spawns", function()
    local spawns = {}
    for i = 0, 7 do spawns[#spawns + 1] = {30 + (i % 4) * 1.5, 70 + math.floor(i / 4) * 2} end
    spawns[#spawns + 1] = {80, 20} -- far away: not part of this spot's area
    addon.card = {QGet = function(kind, id)
        if kind == "Quest" and id == 202 then return {objectives = {{{900}}}} end
        if kind == "NPC" and id == 900 then return {spawns = {[10] = spawns}} end
    end}
    local step = {elements = {{arrow = true, zone = 1431, x = 32, y = 71},
                              {questId = 202, obj = 1}}}
    local a = tr.StepArea(step)
    assert(a and a.auto and a.areaZone == 1431, "an area")
    for _, p in ipairs(a.area) do
        assert(p[1] > 26 and p[1] < 38 and p[2] > 66 and p[2] < 76, "near the spot: " .. show(a.area))
    end
    assert(tr.InsidePoly(a.area, 32, 71), "the spot is inside")
    assert(tr.StepArea(step) == a, "worked out once")
    -- talking to someone first: no area
    local talk = {elements = {{arrow = true, zone = 1431, x = 32, y = 71}, {tag = "turnin"},
                              {questId = 202, obj = 1}}}
    assert(tr.StepArea(talk) == nil, "turn-in step keeps its spot")
    -- objective done: no area
    step.elements[2].completed = true
    assert(tr.StepArea(step) == nil, "done")
    -- too few spawns
    local few = {elements = {{arrow = true, zone = 1431, x = 80, y = 20}, {questId = 202, obj = 1}}}
    assert(tr.StepArea(few) == nil, "one mob is a spot, not an area")
    -- no Questie: nothing, and asked again later
    addon.card = nil
    local later = {elements = {{arrow = true, zone = 1431, x = 32, y = 71}, {questId = 203, obj = 1}}}
    assert(tr.StepArea(later) == nil)
    -- switched off in settings
    addon.card = {QGet = function(kind, id)
        if kind == "Quest" and id == 203 then return {objectives = {{{900}}}} end
        if kind == "NPC" and id == 900 then return {spawns = {[10] = spawns}} end
    end}
    addon.settings = {profile = {openxpMapAreas = false}}
    assert(tr.StepArea(later) == nil, "areas off")
    addon.settings = nil
    assert(tr.StepArea(later), "areas on")
    addon.card = nil
end)

try("roads: the way keeps to the road instead of cutting the corner", function()
    -- Duskwood's main road bends south-east from Raven Hill to the Stranglethorn
    -- turn-off and back up to Darkshire; check the route stays near it
    local pts = tr.FindPath(1431, 20, 60, 73, 57, 25)
    assert(pts, "a way")
    local g = tr.Grid(1431)
    local on, n = 0, 0
    local px, py = 20, 60
    for _, p in ipairs(pts) do
        for s = 1, 10 do
            local x, y = px + (p[1] - px) * s / 10, py + (p[2] - py) * s / 10
            n = n + 1
            local cx, cy = math.floor(x) + 1, math.floor(y) + 1
            local near = false
            for dy = -1, 1 do for dx = -1, 1 do
                if g.cells[(cy + dy - 1) * 100 + cx + dx] == 3 then near = true end
            end end
            if near then on = on + 1 end
        end
        px, py = p[1], p[2]
    end
    assert(on / n > 0.8, "mostly on the road: " .. on .. "/" .. n .. " " .. show(pts))
end)

---------------------------------------------------------------------------
-- Hitching: searches are remembered and spread over frames
---------------------------------------------------------------------------

-- searches started since the clock last moved
local function searches() return tr.SearchesThisFrame() end

try("a way is worked out once, then remembered", function()
    clock = 500
    local a = tr.FindPath(1431, 75.3, 48.7, 66.7, 17.9, 23)
    assert(searches() == 1, "first time searches")
    local b = tr.FindPath(1431, 75.6, 48.2, 66.9, 17.5, 23) -- same cells
    assert(searches() == 1, "same cells: no new search")
    assert(#a == #b and a[1][1] == b[1][1], "same corners")
    assert(b[#b][1] == 66.9 and b[#b][2] == 17.5, "still ends on the exact target")
end)

try("drawing starts one new search per frame, the rest next frame", function()
    tr.lazyPerFrame = 1
    clock = 600
    local p1, wait1 = tr.FindPath(1431, 75.3, 48.7, 66.7, 17.9, 24, true)
    assert(p1 and not wait1, "first one runs")
    local p2, wait2 = tr.FindPath(1431, 75.3, 48.7, 30.5, 40.5, 24, true)
    assert(not p2 and wait2, "second one waits")
    local p3 = tr.FindPath(1431, 75.3, 48.7, 30.5, 40.5, 24)
    assert(p3, "the arrow never waits")
    clock = 600.02
    local p4, wait4 = tr.FindPath(1431, 75.3, 48.7, 10.5, 70.5, 24, true)
    assert(not wait4, "next frame: runs")
    tr.lazyPerFrame = math.huge
end)

try("the line from you follows you without searching every step", function()
    clock = 700
    local first = tr.FollowPath("t", 1431, 75.3, 48.7, 66.7, 17.9, 25)
    assert(first and #first >= 2, "a way round")
    local n = 0
    -- walk the first stretch of the way in small steps
    local ax, ay = 75.3, 48.7
    local c = first[1]
    for i = 1, 10 do
        clock = 700 + i * 0.1
        local x, y = ax + (c[1] - ax) * i / 10, ay + (c[2] - ay) * i / 10
        local before = searches()
        tr.FollowPath("t", 1431, x, y, 66.7, 17.9, 25)
        n = n + searches() - before
    end
    assert(n == 0, "no new searches while following: " .. n)
end)

try("arrow: a target sliding along an area's edge doesn't redo the way", function()
    clock = 800
    local ctx = {zone = 1431}
    local t = {wx = 667, wy = 179, instance = 0}
    tr.Route(t, 753, 487, 0, ctx)
    local n = 0
    for i = 1, 20 do
        clock = 800 + i * 0.2
        t.wx = 667 + i * 0.5 -- the nearest edge point moves as you walk
        local before = searches()
        tr.Route(t, 753 - i, 487 - i, 0, ctx)
        n = n + searches() - before
    end
    assert(n == 0, "searches while the target slid: " .. n)
end)

return fails
