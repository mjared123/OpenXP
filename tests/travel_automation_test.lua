-- Plan-driven flights use taxi IDs and the same opt-out as authored .fly steps.
local ROOT = ...
local function read(file)
    local f = assert(io.open(ROOT .. "/" .. file, "r"))
    local source = f:read("*a")
    f:close()
    return source
end
local timers = read("Timers.lua")
local first = assert(timers:find("local flightInfo = {}", 1, true))
local last = assert(timers:find("function addon:PLAYER_CONTROL_LOST()", first, true))
local loadTimers = assert(loadstring("local addon = ...\n" .. timers:sub(first, last - 1)))
local loadTravel = assert(loadfile(ROOT .. "/Travel.lua"))
local loadFlightData = assert(loadfile(ROOT .. "/DB/forever/flightData.lua"))
local now, shift, flying, currentID, reachable, chosen, addon
local HBD = {
    GetPlayerWorldPosition = function() return 4499, 4200, 0 end,
    GetPlayerZonePosition = function() return 0, 0, 1421 end,
}
LibStub = function() return HBD end
GetTime = function() return now end
IsShiftKeyDown = function() return shift end
UnitOnTaxi = function() return flying end
NumTaxiNodes = function() return 3 end
TaxiNodeGetType = function(slot)
    if slot == 1 then return "CURRENT" end
    return slot == 2 and not reachable and "DISTANT" or "REACHABLE"
end
TakeTaxiNode = function(slot) chosen[#chosen + 1] = slot end
bit = bit or require("bit")
table.wipe = table.wipe or function(t) for k in pairs(t) do t[k] = nil end end
Enum = {FlightPathState = {Current = 0, Reachable = 1, Unreachable = 2}}
C_Map = {GetBestMapForUnit = function() return 1421 end}
C_TaxiMap = {GetAllTaxiNodes = function() return {
    {slotIndex = 1, nodeID = currentID, state = 0, name = "Das Grabmal, Silberwald"},
    {slotIndex = 2, nodeID = 11, state = reachable and 1 or 2, name = "Unterstadt"},
    {slotIndex = 3, nodeID = 13, state = 1, name = "Tarrens Muehle"},
} end}

local function start()
    now, shift, flying, currentID, reachable, chosen = 100, false, false, 10, true, {}
    OXPCData = {flightPaths = {[10] = "Das Grabmal", [11] = "Unterstadt"}}
    local step = {active = true, elements = {{tag = "goto"}, {tag = "turnin", questId = 1013}}}
    local target = {wx = 6260, wy = 6650, instance = 0, zone = 1458, step = step}
    addon = {
        game = "FOREVER", locale = {}, player = {faction = "Horde"},
        settings = {profile = {enableFPAutomation = true}},
        arrowFrame = {element = target}, RXPFrame = {activeSteps = {step}},
        pathHints = {IsOn = function() return true end},
        GetFlightHash = function(slot) return slot end,
        travelData = {fpZone = {["Silverpine Forest"] = 1421}, fpCity = {Undercity = 1458}},
        taxiPos = {[0] = {[10] = {wy = 4500, wx = 4200}, [11] = {wy = 6200, wx = 6550}}},
    }
    loadFlightData("OpenXP", addon)
    loadTravel("OpenXP", addon)
    loadTimers(addon)
    return step
end
local function open() addon:TAXIMAP_OPENED("TAXIMAP_OPENED") end
local failures = 0
local function try(label, fn)
    start()
    local ok, err = pcall(fn)
    print((ok and "ok   " or "FAIL ") .. label .. (ok and "" or ": " .. tostring(err)))
    if not ok then failures = failures + 1 end
end
local function prevents(label, change)
    try(label, function()
        change()
        open()
        assert(#chosen == 0, "unexpected automatic flight")
    end)
end

try("opening the map selects Undercity ID 11 with German taxi labels", function()
    open()
    assert(#chosen == 1 and chosen[1] == 2)
    assert(addon.flightInfo[2] == 11 and addon.FPDB.Horde[11].name == "Undercity, Tirisfal")
    open()
    assert(#chosen == 1, "duplicate map event booked another flight")
end)
try("opening the map makes newly discovered flight paths usable", function()
    OXPCData.flightPaths[11] = nil
    for _, leg in ipairs((addon.travel.Current() or {}).legs or {}) do
        assert(leg.kind ~= "fly", "unknown destination was used for flying")
    end
    open()
    assert(#chosen == 1 and chosen[1] == 2)
end)
try("a .fly handler's map-data refresh does not book another flight", function()
    addon:TAXIMAP_OPENED()
    assert(#chosen == 0)
end)
prevents("flight automation disabled", function() addon.settings.profile.enableFPAutomation = false end)
prevents("travel planner disabled", function() addon.settings.profile.openxpTravel = false end)
prevents("Shift override", function() shift = true end)
prevents("already flying", function() flying = true end)
prevents("guide hidden", function() addon.isHidden = true end)
prevents("manual navigation target", function() addon.pathHints.go = {} end)
prevents("path hints disabled", function() addon.pathHints.IsOn = function() return false end end)
prevents("wrong departure flight master", function() currentID = 12 end)
prevents("destination unreachable", function() reachable = false end)
prevents("inactive guide step", function() addon.arrowFrame.element.step.active = false end)
prevents("authored .fly takes priority", function()
    table.insert(addon.RXPFrame.activeSteps[1].elements, {tag = "fly"})
end)
return failures
