-- /oxp questdump (QuestDataDump.lua) against a tiny fake Questie: reads quests,
-- then the items, NPCs and objects they point at, into OXPQuestieDump.
local ROOT = ...
tinsert = table.insert
print = print
date = function() return "2026-11-10 00:00" end
GetBuildInfo = function() return "1.15", "1", "", 11509 end
local ticks = {}
C_Timer = {NewTicker = function(_, fn)
    local t = {cancelled = false}
    function t:Cancel() self.cancelled = true end
    tinsert(ticks, function() fn() end)
    -- run it like the game would, one frame at a time
    for _ = 1, 1000 do if t.cancelled then break end fn(t) end
    return t
end}

local quests = {
    -- {name, startedBy, finishedBy, ..., objectives at 10}
    [93] = {"Dusky Crab Cakes", {{100}}, {{100}}, 18, 20, nil, nil, nil, nil, {nil, nil, {{2251}}}},
    [94] = {"A Book", {nil, {500}, {600}}, {{101}}},
}
local items = {[2251] = {"Gooey Spider Legs", [3] = {217}}, [600] = {"Old Book"}}
local db = {
    QuestPointers = {[93] = 1, [94] = 1},
    questKeys = {name = 1, startedBy = 2, finishedBy = 3, objectives = 10},
    itemKeys = {name = 1, npcDrops = 3, objectDrops = 4},
    npcKeys = {name = 1}, objectKeys = {name = 1},
    _questAdapterQueryOrder = {}, _itemAdapterQueryOrder = {}, _npcAdapterQueryOrder = {}, _objectAdapterQueryOrder = {},
    QueryQuest = function(id) return quests[id] end,
    QueryItem = function(id) return items[id] end,
    QueryNPC = function(id) return {"NPC " .. id} end,
    QueryObject = function(id) return {"Object " .. id} end,
}
QuestieLoader = {ImportModule = function(_, name) if name == "QuestieDB" then return db end end}

local addon = {}
assert(loadfile(ROOT .. "/QuestDataDump.lua"))("OpenXP", addon)
local fails = 0
local function try(label, fn)
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end
try("dump reads quests, items, NPCs and objects", function()
    addon.questDump.Run()
    local d = OXPQuestieDump
    assert(d, "no dump")
    assert(d.quest[93] and d.quest[94], "quests")
    assert(d.item[2251] and d.item[600], "items")
    assert(d.npc[100] and d.npc[101] and d.npc[217], "npcs (incl. item drop)")
    assert(d.object[500], "objects")
    assert(not addon.questDump.running)
end)
try("clear", function()
    addon.questDump.Clear()
    assert(OXPQuestieDump == nil)
end)
print(fails == 0 and "questdump tests passed" or (fails .. " failed"))
return fails
