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

try("level 22 walks around the Raven Hill Cemetery undead, level 31 goes through", function()
    local low = tr.FindPath(1431, 12.0, 45.0, 30.0, 30.0, 22)
    local high = tr.FindPath(1431, 12.0, 45.0, 30.0, 30.0, 31)
    assert(high == nil, "level 31: straight: " .. show(high))
    assert(low, "level 22: a way around")
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

return fails
