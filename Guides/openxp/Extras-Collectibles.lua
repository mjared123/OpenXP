-- OpenXP extras: optional one-time side trips that aren't part of the leveling
-- route. Pick them from the guide list whenever you want; they never change
-- where the leveling guide sends you.
local L = GetLocale() if L and RXP.enabledLocale[L] then return end

-- Night Watchman's Torch (Forever-only, item 280612).
-- Given by the dead Night Watch Guard (npc 271866, quest "An Unfortunate End")
-- who only shows up in Duskwood at night. He lies at one of several spots;
-- the seven below are the recorded spawn points from forever-db, ordered as a
-- loop from where each faction enters the zone.
RXPGuides.RegisterGuide([[
#forever
#version 1
#group OpenXP Extras
#subgroup Collectibles
#name Night Watchman's Torch

step << Alliance
    .zone Duskwood >>Get to Darkshire in Duskwood: Fly to Darkshire (or ride south from Goldshire)
step << Horde
    .zone Duskwood >>Get to Duskwood: Take the zeppelin from Orgrimmar to Grom'gol, then ride north through Stranglethorn Vale into Duskwood. Stay off the roads near Darkshire, its guards attack Horde
step
    #completewith next
    +The |cRXP_FRIENDLY_Night Watch Guard|r only appears at night (after about 8 PM game time). If it's daytime, come back later.
step << Alliance
    .goto 1431,66.1,34.0,30,0
    .goto 1431,68.8,69.4,30,0
    .goto 1431,45.5,79.2,30,0
    .goto 1431,47.6,59.4,30,0
    .goto 1431,30.1,67.3,30,0
    .goto 1431,17.0,54.9,30,0
    .goto 1431,23.6,33.4,30,0
    .goto 1431,66.1,34.0
    >>Find the dead |cRXP_FRIENDLY_Night Watch Guard::271866|r. He lies at one of these spots, so check each one until you see the yellow "!" over his body. Typing /tar Night Watch Guard helps
    >>Accept and complete |cRXP_FRIENDLY_An Unfortunate End|r to get the [Night Watchman's Torch]
    .collect 280612,1
    .target Night Watch Guard::271866
step << Horde
    .goto 1431,45.5,79.2,30,0
    .goto 1431,30.1,67.3,30,0
    .goto 1431,17.0,54.9,30,0
    .goto 1431,23.6,33.4,30,0
    .goto 1431,47.6,59.4,30,0
    .goto 1431,68.8,69.4,30,0
    .goto 1431,66.1,34.0,30,0
    .goto 1431,45.5,79.2
    >>Find the dead |cRXP_FRIENDLY_Night Watch Guard::271866|r. He lies at one of these spots, so check each one until you see the yellow "!" over his body. Typing /tar Night Watch Guard helps
    >>Accept and complete |cRXP_FRIENDLY_An Unfortunate End|r to get the [Night Watchman's Torch]
    .collect 280612,1
    .target Night Watch Guard::271866
step
    +Done! Put the [Night Watchman's Torch] on your action bars. It lights up the area around you for 5 minutes and goes out when you fight, swim or enter a capital city. If you ever delete it, you can come back for another.
]])
