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

return fails
