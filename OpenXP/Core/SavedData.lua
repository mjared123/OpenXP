-- Saved variables. 2.0 uses new names (OpenXPDB per account, OpenXPCharDB
-- per character) so it never reads or breaks 1.x data; the 1.x importer
-- (phase 5) copies what it needs across.
local _, OXP = ...

local SCHEMA = 1

local ACCOUNT_DEFAULTS = {
    schema = SCHEMA,
    settings = {
        autoNextGuide = true,      -- load a guide's #next when it is finished
        smartStartOnLogin = true,  -- move you to the right section when you log in far past yours
        debug = false,
        -- guide card
        cardShown = true,
        cardCollapsed = false,
        cardScale = 1,
        fontSize = 12,
        font = "default",
        fontOutline = "",
        lockFrames = false,
        -- arrow
        arrowShown = true,
        arrowScale = 1,
        arrowText = 12,
        -- maps
        mapRoute = true,           -- the route line on the world map and minimap
        mapAreas = true,           -- kill/loot areas
        mapPins = true,            -- pins for the step's waypoints
        mobPins = false,           -- a mark on every spawn of the mobs you need
        routeColor = { 0.72, 0.42, 1.0 },
        travel = true,             -- plan trips to other zones
        -- automation (hold Shift to pause it)
        autoAccept = true,         -- accept the quests the guide picks up
        autoTurnIn = true,         -- turn in the guide's quests once complete
        autoReward = true,         -- take the reward when there is no real choice
        autoBestReward = false,    -- with a choice, take the one that sells for most
        skipGossip = true,         -- pick the guide's quest, or the only option, in gossip
        -- buttons and timers
        itemButton = true,
        targetButton = true,
        flightTimer = true,
        hearthReminder = true,
        -- extras
        tooltips = true,
        nameplates = true,
        autoLoot = false,
        maxCamera = false,
        minimap = { hide = false, angle = 200 },
    },
    paths = { areas = {}, passes = {}, off = false }, -- learned and recorded arrow paths (Nav/PathHints.lua)
}

local CHAR_DEFAULTS = {
    schema = SCHEMA,
    currentGuide = nil,   -- registry key of the guide in use
    guides = {},          -- [guide key] = { step = n, skipped = { [n] = true }, status = { [n] = "chain" } }
    flightPaths = {},     -- [Util.PlaceKey(name)] = true, learned flight masters
    trainers = {},        -- [npc name or id] = level when last visited
}

OXP.OnLoaded(function()
    OpenXPDB = OXP.Util.ApplyDefaults(type(OpenXPDB) == "table" and OpenXPDB or {}, ACCOUNT_DEFAULTS)
    OpenXPCharDB = OXP.Util.ApplyDefaults(type(OpenXPCharDB) == "table" and OpenXPCharDB or {}, CHAR_DEFAULTS)
    OXP.db = OpenXPDB
    OXP.char = OpenXPCharDB
    OXP.settings = OpenXPDB.settings
end)
