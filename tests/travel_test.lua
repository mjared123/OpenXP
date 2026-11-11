-- Getting to another zone (Travel.lua): flight paths you know, boats, the
-- tram, your Hearthstone and walking through zone borders.
local ROOT = ...
unpack = unpack or table.unpack
bit = bit or require("bit")

-- A made-up world: every zone is a 1000 x 1000 yard block. HereBeDragons
-- world x, y = block corner + zone x, y (0-1) * 1000.
local BLOCKS = {
    -- Eastern Kingdoms
    [1437] = {1, 0, 0}, [1432] = {2, 1, 0}, [1426] = {1, 1, 0}, [1455] = {0, 1, 0},
    [1453] = {-1, 2, 0}, [1429] = {0, 2, 0}, [1431] = {0, 3, 0}, [1436] = {-1, 3, 0},
    [1433] = {1, 3, 0}, [1434] = {0, 4, 0},
    -- Kalimdor
    [1439] = {0, 0, 1}, [1440] = {0, 1, 1}, [1442] = {-1, 1, 1}, [1438] = {0, -1, 1},
}
local function ZoneToWorld(x, y, map)
    local b = BLOCKS[map]
    if not b then return end
    return b[1] * 1000 + x * 1000, b[2] * 1000 + y * 1000, b[3]
end

local player = {x = 0, y = 0, inst = 0, map = 1431}
local function at(map, x, y)
    player.map = map
    player.x, player.y, player.inst = ZoneToWorld(x / 100, y / 100, map)
end

local now = 0
GetTime = function() now = now + 5; return now end
UnitLevel = function() return 25 end
UnitFactionGroup = function() return "Alliance" end
UnitOnTaxi = function() return false end
local hearth = {count = 0, cd = 0, bind = nil}
GetItemCount = function() return hearth.count end
GetItemCooldown = function() return hearth.cd, hearth.cd > 0 and 3600 or 0 end
GetBindLocation = function() return hearth.bind end
C_Map = {GetMapInfo = function(m)
    local names = {[1442] = "Stonetalon Mountains", [1437] = "Wetlands", [1455] = "Ironforge", [1440] = "Ashenvale"}
    return names[m] and {name = names[m]}
end}
CreateFrame = function() return {RegisterEvent = function() end, SetScript = function() end} end
OXPCData = {flightPaths = {}}

local HBD = {
    GetPlayerWorldPosition = function() return player.x, player.y, player.inst end,
    GetPlayerZonePosition = function()
        local b = BLOCKS[player.map]
        return (player.x - b[1] * 1000) / 1000, (player.y - b[2] * 1000) / 1000, player.map
    end,
    GetWorldCoordinatesFromZone = function(_, x, y, map)
        if map == 1414 then return 0, 0, 1 end
        if map == 1415 then return 0, 0, 0 end
        return ZoneToWorld(x, y, map)
    end,
    GetZoneCoordinatesFromWorld = function(_, wx, wy, map)
        if map == 1414 or map == 1415 then return wx / 5000 + 0.3, wy / 6000 + 0.2 end
        local b = BLOCKS[map]
        if not b then return end
        return (wx - b[1] * 1000) / 1000, (wy - b[2] * 1000) / 1000
    end,
}
LibStub = function() return HBD end

local addon = {locale = {Get = function(s) return s end}, settings = {profile = {}}}

-- Flight masters: taxiPos is stored in UnitPosition order (y, x)
local function Fp(map, x, y)
    local wx, wy, inst = ZoneToWorld(x / 100, y / 100, map)
    return {wx = wy, wy = wx, flag = 3}, inst
end
local FPS = {
    [12] = {"Darkshire, Duskwood", 1431, 77.5, 44.3},
    [2] = {"Stormwind, Elwynn", 1453, 66.3, 62.1},
    [6] = {"Ironforge, Dun Morogh", 1455, 55.5, 47.8},
    [7] = {"Menethil Harbor, Wetlands", 1437, 9.5, 59.7},
    [26] = {"Auberdine, Darkshore", 1439, 36.3, 45.6},
    [28] = {"Astranaar, Ashenvale", 1440, 34.4, 48.0},
}
addon.taxiPos = {[0] = {}, [1] = {}}
addon.FPDB = {Alliance = {}}
for id, f in pairs(FPS) do
    local t, inst = Fp(f[2], f[3], f[4])
    addon.taxiPos[inst][id] = t
    addon.FPDB.Alliance[id] = {name = f[1]}
end
local function Flight(a, b, secs) addon.FPDB.Alliance[a][b] = secs; addon.FPDB.Alliance[b][a] = secs end
Flight(12, 7, 300); Flight(12, 2, 120); Flight(2, 6, 180); Flight(6, 7, 150); Flight(26, 28, 150)

assert(loadfile(ROOT .. "/DB/travel.lua"))("OpenXP", addon)
assert(loadfile(ROOT .. "/Travel.lua"))("OpenXP", addon)
local tv = addon.travel

local fails = 0
local function try(label, fn)
    tv.Reset()
    OXPCData = {flightPaths = {}}
    hearth.count, hearth.cd, hearth.bind = 0, 0, nil
    now = now + 100
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end
local function know(...) for _, id in ipairs({...}) do OXPCData.flightPaths[id] = true end end
local function target(map, x, y, title)
    local wx, wy, inst = ZoneToWorld(x / 100, y / 100, map)
    return {wx = wx, wy = wy, instance = inst, zone = map, title = title or "Talk to someone", step = {}}
end
local function texts(plan)
    local out = {}
    for _, l in ipairs(plan and plan.legs or {}) do out[#out + 1] = l.text end
    return table.concat(out, " | ")
end

local albagorm = target(1442, 37.1, 8.1, "Talk to Keeper Albagorm")

try("Duskwood to Stonetalon: fly, boat, fly, then the Talondeep Path", function()
    know(12, 7, 26, 28)
    at(1431, 77.0, 44.0) -- by the Darkshire flight master
    local plan = tv.PlanFor(albagorm)
    local s = texts(plan)
    assert(s:find("Fly to Menethil Harbor", 1, true), s)
    assert(s:find("Take the boat to Auberdine", 1, true), s)
    assert(s:find("Fly to Astranaar", 1, true), s)
    assert(s:find("Talondeep Path", 1, true), s)
    -- the arrow: the flight master you're standing by, saying where to fly
    local a = tv.ArrowTarget(albagorm)
    assert(a and a.travel and a.title == "Fly to Menethil Harbor", a and a.title)
    assert(a.instance == 0)
    -- and the card lists the legs in order
    local lines = tv.Lines()
    assert(lines[1] == "1. Fly to Menethil Harbor", lines[1])
end)

try("flight paths you haven't learned aren't used", function()
    know(12, 26, 28) -- no Menethil
    at(1431, 77.0, 44.0)
    local s = texts(tv.PlanFor(albagorm))
    assert(not s:find("Fly to Menethil", 1, true), s)
    assert(s:find("Take the boat to Auberdine", 1, true), s)
end)

try("Stormwind to Ironforge: the Deeprun Tram", function()
    at(1453, 60.0, 40.0)
    local plan = tv.PlanFor(target(1455, 30.0, 60.0))
    local s = texts(plan)
    assert(s:find("Go to the Deeprun Tram", 1, true), s)
    assert(s:find("Take the Deeprun Tram to Ironforge", 1, true), s)
end)

try("Ironforge to the Wetlands on foot: through Dun Morogh, Loch Modan and Dun Algaz", function()
    at(1455, 30.0, 60.0)
    local s = texts(tv.PlanFor(target(1437, 10.0, 60.0)))
    assert(s:find("Dun Algaz", 1, true), s)
end)

try("your Hearthstone when it's ready and takes you closer", function()
    know(26, 28)
    hearth.count, hearth.bind = 1, "Astranaar"
    at(1431, 50.0, 50.0)
    local s = texts(tv.PlanFor(albagorm))
    assert(s:find("Use your Hearthstone (to Astranaar)", 1, true), s)
    hearth.cd = 100 -- on cooldown
    tv.Reset(); now = now + 100
    s = texts(tv.PlanFor(albagorm))
    assert(not s:find("Hearthstone", 1, true), s)
end)

try("same zone: nothing to plan, the arrow goes straight", function()
    at(1442, 70.0, 40.0)
    assert(tv.PlanFor(albagorm) == nil)
    assert(tv.ArrowTarget(albagorm) == nil)
end)

try("the setting turns it off", function()
    know(12, 7, 26, 28)
    at(1431, 77.0, 44.0)
    addon.settings.profile.openxpTravel = false
    local a = tv.ArrowTarget(albagorm)
    addon.settings.profile.openxpTravel = nil
    assert(a == nil)
end)

try("route line: on the continent map, from you to the step", function()
    know(12, 7, 26, 28)
    at(1431, 77.0, 44.0)
    tv.PlanFor(albagorm)
    local ek, kal = tv.Polylines(1415, 20), tv.Polylines(1414, 20)
    assert(ek and #ek >= 1, "the flight and the walk to the dock in the Eastern Kingdoms")
    assert(kal and #kal >= 2, "the rest in Kalimdor")
    for _, l in ipairs(kal) do assert(#l >= 2) end
end)

if fails > 0 then print(fails .. " failed") end
return fails
