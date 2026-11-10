-- Arrow path hints (PathHints.lua): routing through cave entrances and ramps,
-- learning cave entrances, and recording paths with /oxp path.
local ROOT = ...
unpack = unpack or table.unpack

local player = {x = 0, y = 0, inst = 0, zone = 1429, indoors = false, subzone = ""}
local now = 0
GetTime = function() now = now + 1; return now end
IsIndoors = function() return player.indoors end
GetSubZoneText = function() return player.subzone end
IsInInstance = function() return false end
UnitOnTaxi = function() return false end
UnitIsDeadOrGhost = function() return false end
CreateFrame = function() return {SetScript = function() end} end
local HBD = {
    GetPlayerWorldPosition = function() return player.x, player.y, player.inst end,
    GetPlayerZone = function() return player.zone end,
    GetPlayerZonePosition = function() return 0.5, 0.5, player.zone end,
    GetZoneCoordinatesFromWorld = function() return 0.4, 0.4 end,
}
LibStub = function() return HBD end
OXPData = {}

local printed = {}
local drawn
local addon = {
    locale = {Get = function(s) return s end},
    comms = {PrettyPrint = function(msg, ...) printed[#printed + 1] = string.format(msg, ...) end},
}
addon.DrawArrow = function(self) drawn = self.element end
addon.arrowFrame = {}
assert(loadfile(ROOT .. "/DB/pathHints.lua"))("OpenXP", addon)
assert(loadfile(ROOT .. "/PathHints.lua"))("OpenXP", addon)
local ph = addon.pathHints

local fails = 0
local function try(label, fn)
    ph.Reset()
    OXPData = {}
    ph.Changed()
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end

local function at(x, y, indoors, subzone)
    player.x, player.y, player.indoors, player.subzone = x, y, indoors or false, subzone or ""
end
local function route(t)
    return ph.Route(t, player.x, player.y, player.inst, {indoors = player.indoors, subzone = player.subzone, zone = player.zone})
end
local function near(pt, x, y) return pt and math.abs(pt[1] - x) < 0.1 and math.abs(pt[2] - y) < 0.1 end

-- Jasperlode Mine: Geosculptor Yip inside, entrance at -610,-9186 then -604,-9180
local yip = {wx = -595.1, wy = -9072.2, instance = 0, zone = 1429}

try("outside a cave: arrow goes to the entrance first, in order", function()
    at(-700, -9300)
    local pt, label = route(yip)
    assert(near(pt, -610.25, -9186.47), "first stone")
    assert(label == "Enter Jasperlode Mine", label)
    at(-612, -9188) -- reached the first stone
    pt = route(yip)
    assert(near(pt, -604.49, -9180.39), "mouth")
    at(-604, -9181)
    assert(route(yip) == nil, "then straight at the target")
    at(-600, -9150) -- inside, but say the game doesn't flag this spot indoors
    assert(route(yip) == nil, "stays direct after going in")
end)

try("standing on the hill above the cave still goes to the entrance", function()
    at(-590, -9100, false)
    assert(near(route(yip), -610.25, -9186.47))
end)

try("inside the cave with a target inside: straight there", function()
    at(-580, -9120, true, "Jasperlode Mine")
    assert(route(yip) == nil)
end)

try("inside the cave with a target outside: out through the entrance", function()
    local wolves = {wx = -798.5, wy = -9418.1, instance = 0, zone = 1429}
    at(-580, -9120, true)
    local pt, label = route(wolves)
    assert(near(pt, -604.49, -9180.39), "mouth first")
    assert(label == "Leave Jasperlode Mine", label)
    at(-603, -9175, true)
    assert(near(route(wolves), -610.25, -9186.47))
    at(-611, -9187, false)
    assert(route(wolves) == nil)
end)

try("a jump-down entrance is never used to leave", function()
    local outside = {wx = 400, wy = -5400, instance = 0, zone = 1426}
    at(690, -5590, true) -- in Frostmane Hold
    assert(route(outside) == nil)
end)

try("ramp up a ridge: every stone, then the target", function()
    local braldir = {wx = -2880.9, wy = -5701.5, instance = 0, zone = 1432}
    at(-3000, -5500)
    assert(near(route(braldir), -2915.5, -5576.5))
    at(-2915, -5570) -- inside that stone's 15 yd
    assert(near(route(braldir), -2874.5, -5608.6))
    at(-2874, -5608)
    assert(near(route(braldir), -2846.1, -5657.6))
    at(-2846, -5657)
    assert(route(braldir) == nil)
end)

try("other continent or no area: no change", function()
    at(0, 0)
    assert(route({wx = 50, wy = 50, instance = 0}) == nil)
    assert(route({wx = 926, wy = 10900, instance = 1}) == nil)
end)

try("arrow hook swaps in the stone, then puts the real target back", function()
    local af = addon.arrowFrame
    af.element = yip
    at(-700, -9300)
    addon.DrawArrow(af)
    assert(drawn ~= yip and near({drawn.wx, drawn.wy}, -610.25, -9186.47), "drew the stone")
    assert(drawn.title == "Enter Jasperlode Mine")
    assert(af.element == yip and af.oxpVia == drawn)
    ph.Command("off")
    addon.DrawArrow(af)
    assert(drawn == yip and af.oxpVia == nil, "off: straight")
    ph.Command("on")
end)

local function walk(points, indoors, subzone)
    for _, p in ipairs(points) do
        at(p[1], p[2], indoors, subzone)
        ph.LearnTick(player.x, player.y, player.inst, player.indoors)
    end
end

try("learns a cave from walking in and out", function()
    walk({{1000, 1000}, {1005, 1000}, {1010, 1000}})
    walk({{1015, 1000}, {1020, 1000}, {1030, 1005}, {1045, 1010}, {1060, 1015}, {1070, 1030}}, true, "Test Cave")
    walk({{1060, 1015}, {1045, 1010}, {1030, 1005}}, true, "Test Cave")
    walk({{1018, 1000}, {1012, 1000}, {1005, 1000}})
    local areas = OXPData.openxpPaths.areas
    assert(#areas == 1, "areas " .. #areas)
    local a = areas[1]
    assert(a.name == "Test Cave" and a.indoor and a.source == "learned")
    assert(#a.entrances == 1, "doors in and out are the same spot: " .. #a.entrances)
    local target = {wx = 1065, wy = 1025, instance = 0}
    at(950, 950)
    local pt, label = route(target)
    assert(pt and math.abs(pt[1] - 1015) < 6 and label == "Enter Test Cave", "routes via the learned door")
end)

try("a house is too small to learn", function()
    walk({{2000, 2000}, {2005, 2000}})
    walk({{2008, 2000}, {2012, 2000}, {2020, 2005}}, true)
    walk({{2008, 2000}, {2004, 2000}})
    assert(#OXPData.openxpPaths.areas == 0)
end)

try("a one-tick indoor flicker isn't a door", function()
    walk({{3000, 3000}, {3005, 3000}})
    walk({{3010, 3000}}, true)
    walk({{3015, 3000}, {3020, 3000}})
    assert(#OXPData.openxpPaths.areas == 0)
end)

try("hearthing out of a cave doesn't learn a door", function()
    walk({{4000, 4000}, {4005, 4000}})
    walk({{4010, 4000}, {4015, 4000}, {4030, 4010}, {4060, 4020}}, true)
    walk({{9000, 9000}, {9001, 9000}, {9002, 9000}})
    assert(#OXPData.openxpPaths.areas == 0)
end)

try("/oxp path add + done records a path the arrow then uses", function()
    local camp = {wx = 5000, wy = 5000, instance = 0, zone = 1429, title = "Ogre camp"}
    addon.arrowFrame.element = camp
    at(5100, 5100); ph.Command("add Ogre ridge")
    at(5080, 5040); ph.Command("add")
    ph.Command("done")
    local a = OXPData.openxpPaths.areas[1]
    assert(a and a.source == "recorded" and a.name == "Ogre ridge" and #a.entrances[1] == 2)
    at(5300, 5300)
    local pt = route(camp)
    assert(near(pt, 5100, 5100), "first recorded stone")
    at(5300, 5300); ph.Command("clear")
    assert(#OXPData.openxpPaths.areas == 1, "clear only removes spots near you")
    at(5090, 5050); ph.Command("clear")
    assert(#OXPData.openxpPaths.areas == 0)
end)

try("a recorded path into another zone becomes a pass", function()
    local far = {wx = 7000, wy = 7000, instance = 0, zone = 1440}
    addon.arrowFrame.element = far
    player.zone = 1439
    at(6000, 6000); ph.Command("add Timbermaw tunnel")
    at(6200, 6100); ph.Command("add")
    ph.Command("done")
    local p = OXPData.openxpPaths.passes[1]
    assert(p and p.from == 1439 and p.to == 1440 and #p.pts == 2)
    at(5800, 5800)
    assert(near(route(far), 6000, 6000))
    at(6000, 6000)
    assert(near(route(far), 6200, 6100))
    at(6200, 6100)
    assert(route(far) == nil, "done with the pass")
    -- coming back the other way uses it reversed
    local back = {wx = 5800, wy = 5800, instance = 0, zone = 1439}
    player.zone = 1440
    at(7000, 7000)
    assert(near(route(back), 6200, 6100))
    player.zone = 1429
end)

try("saved data has no loops (SavedVariables can't write them)", function()
    walk({{1000, 1000}, {1005, 1000}})
    walk({{1015, 1000}, {1020, 1000}, {1060, 1015}, {1070, 1030}}, true, "Test Cave")
    walk({{1012, 1000}, {1005, 1000}})
    at(950, 950)
    route({wx = 1065, wy = 1025, instance = 0})
    local seen = {}
    local function check(t, depth)
        assert(not seen[t], "table appears twice")
        seen[t] = true
        for k, v in pairs(t) do
            assert(type(k) ~= "string" or k:sub(1, 1) ~= "_", "cache key saved: " .. k)
            if type(v) == "table" then check(v, depth + 1) end
        end
    end
    check(OXPData, 0)
end)

print(fails == 0 and "path hint tests passed" or (fails .. " failed"))
return fails
