-- Tests for quest tooltips (OpenXPTooltips.lua): bag items needed for quests
-- you have or that the guide saves for later, and mob progress for kill and
-- item-drop objectives. Runs without Questie.
local ROOT = ...
unpack = unpack or table.unpack
tinsert = table.insert
strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do tinsert(out, part) end
    return unpack(out)
end
local frame = setmetatable({}, {__index = function() return function() end end})
CreateFrame = function() return frame end
GameTooltip = {HookScript = function() end}

-- One quest in the log: Kill 3/8 Kobold Vermin, and 2/6 Gooey Spider Legs
local log = {
    {title = "Kobold Camp Cleanup", id = 7, objectives = {{"Kobold Vermin slain: 3/8", "monster", false}}},
    {title = "Spider Legs", id = 93, objectives = {{"Gooey Spider Legs: 2/6", "item", false}}},
}
GetNumQuestLogEntries = function() return #log end
GetQuestLogTitle = function(i) local q = log[i]; return q.title, 1, nil, false, nil, nil, nil, q.id end
GetNumQuestLeaderBoards = function(i) return #log[i].objectives end
GetQuestLogLeaderBoard = function(j, i) return unpack(log[i].objectives[j]) end
local items = {[2251] = "Gooey Spider Legs", [1475] = "Small Venom Sac", [5000] = "Something Else"}
GetItemInfo = function(id) return items[id] end
local bags = {[2251] = 2, [1475] = 0}
GetItemCount = function(id) return bags[id] or 0 end
IsQuestFlaggedCompleted = function() return false end

local addon = {
    locale = {Get = function(s) return s end},
    settings = {profile = {}},
    GetGuideProgress = function() return 2 end,
    GetQuestName = function(id) return id == 2359 and "Elixir of Agony" or nil end,
    currentGuide = {steps = {
        {elements = {{tag = "collect", id = 5000, qty = 1, questId = 1}}}, -- already behind you
        {elements = {
            {tag = "collect", id = 1475, qty = 1, questId = 2359},
            {tag = "collect", id = 2251, qty = 6, questId = 93},
            {mobs = {"Venom Web Spider"}},
        }},
    }},
}
assert(loadfile(ROOT .. "/OpenXPTooltips.lua"))("OpenXP", addon)
local T = addon.openxpTooltips
local fails = 0
local function try(label, fn)
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end

try("item for a quest you have shows its count", function()
    local lines = T.ItemLines(2251, "Gooey Spider Legs")
    assert(#lines == 1, "lines " .. #lines)
    assert(lines[1].title == "Spider Legs" and lines[1].have == 2 and lines[1].need == 6)
end)
try("item the guide saves for a later quest", function()
    local lines = T.ItemLines(1475, "Small Venom Sac")
    assert(#lines == 1, "lines " .. #lines)
    assert(lines[1].title == "Elixir of Agony" and lines[1].later == 2 and lines[1].need == 1)
end)
try("items for steps you're past show nothing", function()
    assert(#T.ItemLines(5000, "Something Else") == 0)
end)
try("tooltip gets the don't-sell header", function()
    local added = {}
    local tt = {AddLine = function(_, t) tinsert(added, t) end,
                AddDoubleLine = function(_, a, b) tinsert(added, a .. " " .. b) end, Show = function() end}
    T.AddItemLines(tt, 2251, "Gooey Spider Legs")
    assert(#added == 3 and added[2]:find("don't sell"), table.concat(added, " | "))
end)
try("mob: kill objective", function()
    local lines = T.QuestLines("Kobold Vermin", 6)
    assert(#lines == 1 and lines[1].have == 3 and lines[1].need == 8)
end)
try("mob: item it drops (from the guide's .mob lines)", function()
    local lines = T.QuestLines("Venom Web Spider", 217)
    assert(#lines == 1 and lines[1].what == "Gooey Spider Legs" and lines[1].have == 2, "lines " .. #lines)
end)
try("mob that drops nothing you need", function()
    assert(#T.QuestLines("Forest Wolf", 69) == 0)
end)
print(fails == 0 and "tooltip tests passed" or (fails .. " failed"))
return fails
