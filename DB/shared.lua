local addonName, addon = ...

addon.mapConversion = {}

addon.skipPreReq = {
    [9573] = 1,
    [533] = 1,
    [5096] = 1,
    [5092] = 1,
    [1114] = 1,
    [10000] = 1,
    [10008] = 1
}

addon.repStandingID = {
    ["hated"] = 1,
    ["hostile"] = 2,
    ["unfriendly"] = 3,
    ["neutral"] = 4,
    ["friendly"] = 5,
    ["honored"] = 6,
    ["revered"] = 7,
    ["exalted"] = 8
}

addon.repStartValue = {
    -42000, -- hated
    -6000, -- hostile
    -3000, -- unfriendly
    0, -- neutral
    3000, -- friendly
    9000, -- honored
    21000, -- revered
    42000 -- exalted
}

addon.base = {66,78,71,101,116,73,110,102,111}

function addon.GetSubZones(map)
    if addon.subzoneList then
        return addon.subzoneList[map]
    end
end

local L = addon.locale.Get
addon.GuideNames =
{
    [L"RXP MoP 1-80 (A)"] = L"RXP MoP 1-60 (A)",
    [L"RXP MoP 1-80 (H)"] = L"RXP MoP 1-60 (H)",
    -- OpenXP: friendlier names in the guide menu. The group ids stay the
    -- same so saved progress and #next links keep working.
    ["RestedXP Forever Guide (A)"] = "OpenXP Alliance",
    ["RestedXP Forever Guide (H)"] = "OpenXP Horde",
    ["Speedrun Guide 1-20"] = "Levels 1-20",
    ["Speedrun Guide 1-22"] = "Levels 1-22",
    ["OpenXP 21-60"] = "Levels 21-60",
    ["RestedXP Alliance 1-20"] = "OpenXP Alliance 1-20",
    ["RestedXP Horde 1-22"] = "OpenXP Horde 1-22",
    ["RestedXP Alliance 20-30"] = "OpenXP Alliance 21-60",
    ["RestedXP Horde 20-30"] = "OpenXP Horde 22-60",
}
