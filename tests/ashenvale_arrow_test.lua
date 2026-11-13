-- The whole arrow (Terrain.lua, PathHints.lua, Travel.lua and their data) on
-- real Ashenvale and Stonetalon map geometry, replaying player reports:
-- Astranaar, the Talondeep Path mouth, and /oxp path off.
local ROOT = ...
unpack = unpack or table.unpack
bit = bit or require("bit")

-- real zone rects (HereBeDragons world frame used by this addon)
local RECT = {
    [1440] = {left = 1700, w = 5766.67, top = 4672.92, h = 3843.75, name = "Ashenvale"},
    [1442] = {left = 3245.83, w = 4883.33, top = 2916.67, h = 3256.25, name = "Stonetalon Mountains"},
}
local function ZW(x, y, map) -- zone 0-1 -> world
    local r = RECT[map]; if not r then return end
    return r.left - x * r.w, r.top - y * r.h, 1
end
local function WZ(wx, wy, map) -- world -> zone 0-1
    local r = RECT[map]; if not r then return end
    return (r.left - wx) / r.w, (r.top - wy) / r.h
end

local P = {x = 0, y = 0, map = 1440, indoors = false, level = 21}
local now = 0
GetTime = function() now = now + 0.5; return now end
UnitLevel = function() return P.level end
UnitFactionGroup = function() return "Alliance" end
UnitOnTaxi = function() return false end
UnitIsDeadOrGhost = function() return false end
IsIndoors = function() return P.indoors end
IsInInstance = function() return false end
GetSubZoneText = function() return "" end
GetItemCount = function() return 0 end
GetItemCooldown = function() return 0, 0 end
GetBindLocation = function() return nil end
C_Map = {GetMapInfo = function(m) return RECT[m] and {name = RECT[m].name} end}
CreateFrame = function() return {SetScript = function() end, RegisterEvent = function() end} end
OXPData, OXPCData = {}, {flightPaths = {}}

local HBD = {
    GetPlayerWorldPosition = function() return P.x, P.y, 1 end,
    GetPlayerZone = function() return P.map end,
    GetPlayerZonePosition = function() local x, y = WZ(P.x, P.y, P.map); return x, y, P.map end,
    GetWorldCoordinatesFromZone = function(_, x, y, map) return ZW(x, y, map) end,
    GetZoneCoordinatesFromWorld = function(_, wx, wy, map) return WZ(wx, wy, map) end,
}
LibStub = function() return HBD end

local drawn
local addon = {
    mapId = {["Ashenvale"] = 1440, ["Stonetalon Mountains"] = 1442},
    locale = {Get = function(s) return s end},
    comms = {PrettyPrint = function() end},
    settings = {profile = {}},
    player = {faction = "Alliance"},
}
addon.DrawArrow = function(self) drawn = self.element end
addon.arrowFrame = {IsShown = function() return true end, Show = function() end}
-- flight masters: Astranaar (28) and Stonetalon Peak (33); taxiPos is (y, x)
addon.taxiPos = {[1] = {}}
addon.FPDB = {Alliance = {[28] = {name = "Astranaar, Ashenvale"}, [33] = {name = "Stonetalon Peak, Stonetalon Mountains"}}}
do
    local ax, ay = ZW(0.344, 0.480, 1440); addon.taxiPos[1][28] = {wx = ay, wy = ax, flag = 3}
    local sx, sy = ZW(0.364, 0.072, 1442); addon.taxiPos[1][33] = {wx = sy, wy = sx, flag = 3}
end
for _, f in ipairs({"DB/pathHints.lua", "DB/terrain.lua", "DB/travel.lua", "Terrain.lua", "PathHints.lua", "Travel.lua"}) do
    local text = assert(io.open(ROOT .. "/" .. f)):read("*a"):gsub("\r", "")
    assert(loadstring(text, f))("OpenXP", addon)
end
addon.terrain.lazyPerFrame = math.huge
local ph = addon.pathHints

local function at(map, x, y) P.map = map; P.x, P.y = ZW(x / 100, y / 100, map) end
local function target(map, x, y, title)
    local wx, wy = ZW(x / 100, y / 100, map)
    return {wx = wx, wy = wy, instance = 1, zone = map, title = title, step = {}}
end
local function arrow(t)
    local af = addon.arrowFrame
    af.element = t
    -- a few frames, like the game (throttles, lazy searches)
    for _ = 1, 6 do drawn = nil; addon.DrawArrow(af) end
    local d = drawn
    local dx, dy = d.wx - P.x, d.wy - P.y
    local yd = math.sqrt(dx * dx + dy * dy)
    local zx, zy = WZ(d.wx, d.wy, P.map)
    -- compass: world x grows west, world y grows north
    local ang = math.deg(math.atan2(-dx, dy)) % 360
    local dirs = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
    local dir = dirs[math.floor((ang + 22.5) / 45) % 8 + 1]
    return string.format("%-45s %5.0f yd %-2s (to %s %.1f, %.1f)", tostring(d.title), yd, dir,
                         RECT[P.map].name, zx * 100, zy * 100), d, yd
end
local function reset() ph.Reset(); addon.travel.Reset(); OXPData = {}; ph.Saved().off = nil end


local fails = 0
local function try(label, fn)
    reset()
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end
local function zone(d) local x, y = WZ(d.wx, d.wy, P.map); return x * 100, y * 100 end

local teloren = target(1442, 36.4, 7.2, "Talk to Teloren")

try("at the Talondeep mouth: into the tunnel, not back north to the camp", function()
    at(1440, 40.4, 71.5) -- where the player's screenshot was (389 yd from the camp)
    local s, d, yd = arrow(teloren)
    local x, y = zone(d)
    assert(y > 75, s)
end)

try("at the Talondeep mouth with paths off: straight at the NPC", function()
    at(1440, 40.4, 71.5)
    ph.Command("off")
    local s, d = arrow(teloren)
    assert(d == teloren, s)
end)

try("from the camp north of the tunnel: to the tunnel mouth", function()
    at(1440, 40.4, 61.4)
    local s, d = arrow(teloren)
    local x, y = zone(d)
    assert(math.abs(x - 40.5) < 1 and math.abs(y - 71.5) < 1, s)
end)

try("walking Astranaar to Stonetalon Peak by the arrow gets there", function()
    at(1440, 36.6, 49.6)
    local north = 0
    for i = 1, 400 do
        local s, d, yd = arrow(teloren)
        if yd < 1 then break end
        if P.map == 1440 and select(2, WZ(P.x, P.y, 1440)) > 0.80 then at(1442, 78.3, 42.5) end
        local before = select(2, WZ(P.x, P.y, P.map))
        local step = math.min(25, yd)
        P.x, P.y = P.x + (d.wx - P.x) / yd * step, P.y + (d.wy - P.y) / yd * step
        if P.map == 1440 and select(2, WZ(P.x, P.y, 1440)) > 0.70 and select(2, WZ(P.x, P.y, 1440)) < before then
            north = north + 1 -- turned back north at the tunnel
        end
        local zx, zy = WZ(P.x, P.y, P.map)
        local tx, ty = WZ(teloren.wx, teloren.wy, 1442)
        if P.map == 1442 and math.abs(zx - tx) < 0.004 and math.abs(zy - ty) < 0.004 then
            assert(north == 0, "turned back at the tunnel " .. north .. " times")
            return
        end
    end
    error("never got to Teloren")
end)

try("in Astranaar the arrow points straight at the town's NPCs", function()
    local npcs = {{36.62, 49.58}, {34.67, 48.84}, {36.99, 49.22}, {34.98, 48.46}, {37.37, 51.79}}
    local spots = {{37.0, 49.3}, {33.4, 48.0}, {35.8, 49.8}}
    for _, s in ipairs(spots) do
        for _, n in ipairs(npcs) do
            reset(); at(1440, s[1], s[2])
            local t = target(1440, n[1], n[2], "npc")
            local str, d = arrow(t)
            assert(d == t, string.format("from %.1f,%.1f to %.2f,%.2f: %s", s[1], s[2], n[1], n[2], str))
        end
    end
end)

print(fails == 0 and "ashenvale arrow tests passed" or (fails .. " failed"))
return fails
