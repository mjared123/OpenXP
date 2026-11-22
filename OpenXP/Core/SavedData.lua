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
        cardAnimations = true,     -- a short fade and slide when the step changes
        -- cardWidth, cardHeight: the size you dragged the card to (nil: default)
        fontSize = 12,
        font = "default",
        fontOutline = "",
        skin = "midnight",         -- Settings > Guide card > Skin (UI/Style.lua)
        cardOpacity = 1,           -- the card's background: 0 (none) to 1 (the skin's own)
        upNextMode = "show",       -- "show", "folded" (one line, click to open) or "hide"
        lockFrames = false,
        -- arrow
        arrowShown = true,
        arrowScale = 1,
        arrowText = 12,
        arrowStyle = "chevron",    -- Nav/ArrowView.lua STYLES
        arrowShowRing = true,      -- the circle around the pointer
        arrowShowDistance = true,  -- "123 yd" under it
        arrowShowLabel = true,     -- what to do there, under that
        arrowColor = "skin",       -- "skin" (the skin's accent), "distance" (red far, green close), "white"
        arrowAlpha = 1,
        mapQuestIcons = "auto",    -- "auto": our ! ? and objective icons off while Questie draws its own; "on"; "off"
        mapIconScale = 1,
        -- maps
        mapRoute = true,           -- the route line on the world map and minimap
        mapAreas = true,           -- kill/loot areas
        mapPins = true,            -- pins for the step's waypoints
        routeStyle = "roads",      -- "roads": keep to roads; "direct": the shortest way
        mapMobs = true,            -- a mark on every spawn of the mobs you need
        routeColor = { 0.72, 0.42, 1.0 },
        travel = true,             -- plan trips to other zones
        -- automation (hold Shift to pause it)
        autoAccept = true,         -- accept the quests the guide picks up
        autoTurnIn = true,         -- turn in the guide's quests once complete
        autoTurnInAny = true,      -- and any other completed quest in your log
        autoReward = true,         -- take the reward when there is no real choice
        autoBestReward = false,    -- with a choice, take the one that sells for most
        skipGossip = true,         -- pick the guide's quest, or the only option, in gossip
        autoFlight = true,         -- take the step's flight when the flight master's map opens
        -- buttons and timers
        itemButton = true,
        targetButton = true,
        flightTimer = true,
        hearthReminder = true,
        -- extras
        tooltips = true,
        nameplates = true,
        nameplateGivers = false,      -- OpenXP's ! ? over quest givers (the game shows its own)
        nameplateStepNumbers = false, -- "#12" beside nameplate markers
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

-- The look a brand-new install starts with (never applied over settings
-- someone already has).
local FIRST_LOAD = {
    skin = "midnight",
    cardOpacity = 0.9,
    arrowStyle = "chevron",
    arrowShowRing = true,
    cardWidth = 340,
    cardHeight = 310,
}
OXP.FIRST_LOAD = FIRST_LOAD
OXP.DEFAULT_SETTINGS = ACCOUNT_DEFAULTS.settings

--- Every OpenXP setting back to how a new install starts (Settings >
--- Reset to defaults): the look, positions and sizes, automation, all of
--- it. Guide progress, learned flight paths and recorded paths are not
--- settings and stay. The table is emptied and filled in place, so
--- everything holding OXP.settings sees the new values.
function OXP.ResetSettings()
    local s = OXP.settings
    if not s then return end
    for k in pairs(s) do s[k] = nil end
    OXP.Util.ApplyDefaults(s, ACCOUNT_DEFAULTS.settings) -- copies the tables (minimap, routeColor)
    for k, v in pairs(FIRST_LOAD) do s[k] = v end
end

OXP.OnLoaded(function()
    local fresh = type(OpenXPDB) ~= "table" or next(OpenXPDB) == nil
    OpenXPDB = OXP.Util.ApplyDefaults(type(OpenXPDB) == "table" and OpenXPDB or {}, ACCOUNT_DEFAULTS)
    OpenXPCharDB = OXP.Util.ApplyDefaults(type(OpenXPCharDB) == "table" and OpenXPCharDB or {}, CHAR_DEFAULTS)
    OXP.db = OpenXPDB
    OXP.char = OpenXPCharDB
    OXP.settings = OpenXPDB.settings
    if fresh then
        for k, v in pairs(FIRST_LOAD) do OXP.settings[k] = v end
        OpenXPDB.firstLook = 1
    end
    -- Test builds up to 2.0.0-dev could start with the card hidden and
    -- locked (1.x's "lock frames" and "hide the guide window" were copied
    -- over). Once: shown and unlocked; your own choices after that stay.
    if (OpenXPDB.uiFixed or 0) < 1 then
        OpenXPDB.uiFixed = 1
        OXP.settings.lockFrames = false
        OXP.settings.cardShown = true
    end
end)
