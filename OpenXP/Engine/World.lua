-- Where the player is and what they have set up in the world: current zone,
-- learned flight paths, hearthstone location, items in bags.
local _, OXP = ...

local World = {}
OXP.World = World

local PlaceKey = OXP.Util.PlaceKey

------------------------------------------------------------------------
-- Zones
------------------------------------------------------------------------

--- Names of every place the player is in right now, as PlaceKeys:
--- sub-zone, zone, and the map and its parent maps.
function World.CurrentPlaces()
    local places = {}
    local function add(name)
        local key = PlaceKey(name)
        if key and key ~= "" then places[key] = true end
    end
    add(GetSubZoneText and GetSubZoneText())
    add(GetZoneText and GetZoneText())
    add(GetRealZoneText and GetRealZoneText())
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        local guard = 0
        while mapID and mapID > 0 and guard < 10 do
            local info = C_Map.GetMapInfo(mapID)
            if not info then break end
            add(info.name)
            mapID = info.parentMapID
            guard = guard + 1
        end
    end
    return places
end

--- The player is in (or inside) the named zone, sub-zone or city.
function World.InZone(name)
    return World.CurrentPlaces()[PlaceKey(name) or ""] == true
end

------------------------------------------------------------------------
-- Flight paths
------------------------------------------------------------------------
-- Flight masters are named "Place, Zone" in the taxi map ("Tarren Mill,
-- Hillsbrad"); guides name just the place. We remember both forms.

local function remember(name)
    if not (name and OXP.char) then return end
    OXP.char.flightPaths[PlaceKey(name)] = true
    local place = name:match("^([^,]+),")
    if place then OXP.char.flightPaths[PlaceKey(place)] = true end
end

function World.KnowsFlightPath(name)
    return OXP.char ~= nil and OXP.char.flightPaths[PlaceKey(name) or ""] == true
end

--- Record a flight path as learned (also called by the engine when the
--- game says "New flight path discovered" while a guide asks for one).
function World.LearnFlightPath(name)
    remember(name)
    OXP.Send("FLIGHTPATHS_CHANGED")
end

local function forget(name)
    if not (name and OXP.char) then return end
    OXP.char.flightPaths[PlaceKey(name)] = nil
    local place = name:match("^([^,]+),")
    if place then OXP.char.flightPaths[PlaceKey(place)] = nil end
end

-- The taxi map lists this continent's flight masters. CURRENT and REACHABLE
-- ones are yours; DISTANT (and NONE) ones are listed too but not proven
-- discovered (a Human was sent to fly to Thelsamar it had never visited,
-- GitHub #154), so they don't count, and one counted before is dropped.
OXP.On("TAXIMAP_OPENED", function()
    local n = NumTaxiNodes and NumTaxiNodes() or 0
    for i = 1, n do
        local kind = TaxiNodeGetType(i)
        if kind == "CURRENT" or kind == "REACHABLE" then
            remember(TaxiNodeName(i))
        end
    end
    for i = 1, n do
        local kind = TaxiNodeGetType(i)
        if kind == "DISTANT" or kind == "NONE" then forget(TaxiNodeName(i)) end
    end
    OXP.Send("FLIGHTPATHS_CHANGED")
end)

--- Does a taxi map node ("Auberdine, Darkshore") stand for this place
--- ("Auberdine")?
function World.SameFlightPoint(node, name)
    if not (node and name) then return false end
    local want = PlaceKey(name)
    if not want or want == "" then return false end
    return PlaceKey(node) == want or PlaceKey(node:match("^([^,]+),") or "") == want
end

-- Taking a flight: TakeTaxiNode(i) says where to (hooked, so a flight
-- taken by hand, by the auto-flight or by another addon is all seen); the
-- game takes control away a moment later and UnitOnTaxi turns true. Then
-- TAXI_STARTED (destination or nil) goes out, so a "fly to" step is done
-- as you take off, not when you land.
World.taxi = { dest = nil, at = nil, started = false }

function World.OnTaxi()
    return UnitOnTaxi ~= nil and UnitOnTaxi("player") == true
end

--- The flight master you're flying to ("Auberdine, Darkshore"), or nil
--- when you're not flying or it isn't known.
function World.TaxiDestination()
    if not World.OnTaxi() then return nil end
    return World.taxi.dest
end

--- On a flight to `name` right now (false when the destination isn't
--- known: a flight taken before a /reload; Engine/Runner.lua then counts
--- it for the step on screen).
function World.FlyingTo(name)
    if not World.OnTaxi() then return false end
    return World.SameFlightPoint(World.taxi.dest, name)
end

local function CheckTakeoff()
    local t = World.taxi
    if World.OnTaxi() then
        if not t.started then
            t.started = true
            OXP.Send("TAXI_STARTED", t.dest)
        end
        return true
    end
    return false
end

if hooksecurefunc and _G.TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(index)
        World.taxi.dest = TaxiNodeName and TaxiNodeName(index) or nil
        World.taxi.at = GetTime and GetTime() or 0
        World.taxi.started = false
        -- usually already on the taxi by the next frame; checked again
        -- on PLAYER_CONTROL_LOST and a little later in case it isn't
        if C_Timer and C_Timer.After then
            C_Timer.After(0, CheckTakeoff)
            C_Timer.After(0.5, CheckTakeoff)
            C_Timer.After(1.5, CheckTakeoff)
        end
    end)
end

OXP.On("PLAYER_CONTROL_LOST", function()
    if not CheckTakeoff() and C_Timer and C_Timer.After then C_Timer.After(0.3, CheckTakeoff) end
end)

OXP.On("PLAYER_CONTROL_GAINED", function()
    if World.OnTaxi() then return end
    local t = World.taxi
    if t.started then
        t.started, t.dest = false, nil
        OXP.Send("TAXI_ENDED")
    end
end)

OXP.On("UI_INFO_MESSAGE", function(_, a, b)
    -- Classic passes (messageType, text); older clients pass (text).
    local text = b or a
    if ERR_NEWTAXIPATH and text == ERR_NEWTAXIPATH then
        OXP.Send("FLIGHTPATH_DISCOVERED")
    end
end)

------------------------------------------------------------------------
-- Hearthstone
------------------------------------------------------------------------

function World.BindLocation()
    return GetBindLocation and GetBindLocation() or nil
end

function World.IsHearthAt(name)
    local bind = World.BindLocation()
    return bind ~= nil and name ~= nil and PlaceKey(bind) == PlaceKey(name)
end

OXP.On("HEARTHSTONE_BOUND", function() OXP.Send("HEARTH_CHANGED") end)

------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------

function World.ItemCount(itemID)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and count(itemID) or 0
end

local function bagsChanged()
    OXP.Soon("BAGS_CHANGED", function() OXP.Send("BAGS_CHANGED") end)
end
OXP.On("BAG_UPDATE_DELAYED", bagsChanged)

local function zoneChanged()
    OXP.Soon("ZONE_CHANGED", function() OXP.Send("ZONE_CHANGED") end)
end
OXP.On("ZONE_CHANGED", zoneChanged)
OXP.On("ZONE_CHANGED_NEW_AREA", zoneChanged)
OXP.On("ZONE_CHANGED_INDOORS", zoneChanged)
OXP.On("PLAYER_ENTERING_WORLD", zoneChanged)
