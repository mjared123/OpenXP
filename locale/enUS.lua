local addonName, addon = ...

-- Return nil ('raw') for non-enUS entries
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true, 'raw')

for i = 1, 4 do
_G["BINDING_NAME_" .. format("CLICK RXPItemFrameButton%d:LeftButton",i)] =
    format("Active Item Button %d",i)

_G["BINDING_NAME_" .. format("CLICK RXPTargetFrame_FriendlyButton%d:LeftButton",i)] =
    format("Quest NPC %d (Quest Targets list)",i)

_G["BINDING_NAME_" .. format("CLICK RXPTargetFrame_EnemyButton%d:LeftButton",i)] =
    format("Quest mob %d (Quest Targets list)",i)
end

L.delimiter = ' '
-- Words
L.words = {}

-- enUS locale content not needed (yet), parsed guides already enUS
