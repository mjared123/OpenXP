-- 2.0.2 quest item button fixes (CurseForge, 2026-11-23): the button showed
-- only after the item was clicked (its name wasn't cached yet), usable quest
-- items the step doesn't name, and 1.x key binds carried over once.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("itembutton")

local function newGame()
    local game = FakeWoW.New(ROOT, { level = 20 })
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local function addGuide(OXP, steps)
    local g = { name = "20-21 Item test", group = "Test", steps = steps }
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

-- one bag: slot -> { id, questID }
local function bags(list)
    C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and #list or 0 end,
        GetContainerItemID = function(bag, slot) return bag == 0 and list[slot] and list[slot][1] or nil end,
        GetContainerItemQuestInfo = function(bag, slot)
            local e = bag == 0 and list[slot]
            return { isQuestItem = e and e[2] ~= nil, questID = e and e[2], isActive = false }
        end,
    }
end

print("-- a 'Use <item>' line shows once the game knows the item's name")
do
    local game, OXP = newGame()
    local known = false
    GetItemInfo = function(id) return known and id == 5000 and "Flare Gun" or nil end
    bags({ { 5000 } })
    game:AddItem(5000, 1)
    game:Accept(700, 1)
    addGuide(OXP, { { { "complete", quest = 700, obj = 1, text = "Use Flare Gun (on the tower)" } } })
    game:Flush()
    local item = OXP.ActionButtons.item
    t.eq(item:IsShown(), false, "name not cached yet: no button")
    known = true
    game:Fire("GET_ITEM_INFO_RECEIVED", 5000, true)
    game:Flush()
    t.eq(item:IsShown(), true, "name arrives: the button shows without clicking the item")
    t.eq(item.itemID, 5000, "with that item")
    GetItemInfo, C_Container = nil, nil
end

print("-- a usable quest item for the step's quest, even when the step doesn't name it")
do
    local game, OXP = newGame()
    bags({ { 6000 }, { 6001, 701 } }) -- 6001 is for quest 701
    GetItemSpell = function(id) return id == 6001 and "Use" or nil end
    game:AddItem(6001, 1)
    game:Accept(701, 1)
    addGuide(OXP, { { { "complete", quest = 701, obj = 1, text = "Kill the spirits" } } })
    game:Flush()
    local item = OXP.ActionButtons.item
    t.eq(item:IsShown(), true, "shown")
    t.eq(item.itemID, 6001, "the quest's usable item")
    GetItemSpell = function() return nil end
    OXP.ActionButtons.Refresh()
    t.eq(item:IsShown(), false, "not usable: no button")
    GetItemSpell, C_Container = nil, nil
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

print("-- 1.x key binds move to the new buttons once")
do
    local binds = { ["CLICK RXPItemFrameButton1:LeftButton"] = { "F" }, ["CLICK OpenXPTargetMobs:LeftButton"] = { "G" } }
    local saved = 0
    GetBindingKey = function(b) return unpack(binds[b] or {}) end
    SetBinding = function(key, b) binds[b] = binds[b] or {} table.insert(binds[b], key) return true end
    SaveBindings = function() saved = saved + 1 end
    GetCurrentBindingSet = function() return 2 end
    local game, OXP = newGame()
    t.eq(binds["CLICK OpenXPItemButton:LeftButton"] and binds["CLICK OpenXPItemButton:LeftButton"][1], "F", "item key carried over")
    t.eq(binds["CLICK OpenXPTargetButton:LeftButton"] and binds["CLICK OpenXPTargetButton:LeftButton"][1], "G", "target key carried over")
    t.eq(saved, 1, "saved once")
    t.eq(OXP.ActionButtons.CarryOldBindings(), false, "only once")
    GetBindingKey, SetBinding, SaveBindings, GetCurrentBindingSet = nil, nil, nil, nil
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
