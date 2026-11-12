-- Saved variables. 2.0 uses new names (OpenXPDB per account, OpenXPCharDB
-- per character) so it never reads or breaks 1.x data; the 1.x importer
-- (phase 5) copies what it needs across.
local _, OXP = ...

local SCHEMA = 1

local ACCOUNT_DEFAULTS = {
    schema = SCHEMA,
    settings = {
        autoNextGuide = true, -- load a guide's #next when it is finished
    },
}

local CHAR_DEFAULTS = {
    schema = SCHEMA,
    currentGuide = nil,   -- registry key of the guide in use
    guides = {},          -- [guide key] = { step = n, skipped = { [n] = true } }
    flightPaths = {},     -- [Util.PlaceKey(name)] = true, learned flight masters
}

OXP.OnLoaded(function()
    OpenXPDB = OXP.Util.ApplyDefaults(type(OpenXPDB) == "table" and OpenXPDB or {}, ACCOUNT_DEFAULTS)
    OpenXPCharDB = OXP.Util.ApplyDefaults(type(OpenXPCharDB) == "table" and OpenXPCharDB or {}, CHAR_DEFAULTS)
    OXP.db = OpenXPDB
    OXP.char = OpenXPCharDB
    OXP.settings = OpenXPDB.settings
end)
