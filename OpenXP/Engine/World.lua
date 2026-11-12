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

OXP.On("TAXIMAP_OPENED", function()
    local n = NumTaxiNodes and NumTaxiNodes() or 0
    for i = 1, n do
        local kind = TaxiNodeGetType(i)
        if kind == "CURRENT" or kind == "REACHABLE" or kind == "DISTANT" then
            remember(TaxiNodeName(i))
        end
    end
    OXP.Send("FLIGHTPATHS_CHANGED")
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
    return GetItemCount and GetItemCount(itemID) or 0
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
