-- Who is playing: faction, race, class and level, kept up to date.
local _, OXP = ...

local Player = {}
OXP.Player = Player

function Player.Refresh()
    Player.name = UnitName("player")
    Player.faction = UnitFactionGroup("player")       -- "Alliance", "Horde" or "Neutral"
    local _, raceFile = UnitRace("player")
    Player.race = raceFile                             -- "Human", "Scourge", "Skyborne", ...
    local _, classFile = UnitClass("player")
    Player.class = classFile                           -- "WARRIOR", "PALADIN", ...
    Player.level = UnitLevel("player") or 1
end

Player.Refresh()

OXP.OnLoaded(Player.Refresh) -- before any OnReady code asks
OXP.On("PLAYER_LOGIN", Player.Refresh)
OXP.On("PLAYER_LEVEL_UP", function(_, level)
    -- UnitLevel can still return the old level during this event.
    Player.level = tonumber(level) or UnitLevel("player")
    OXP.Send("PLAYER_LEVEL", Player.level)
end)
