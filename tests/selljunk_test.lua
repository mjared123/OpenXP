-- 2.0.4: selling junk at a vendor (1.x did it, 2.0 had lost it; CurseForge
-- 2026-11-24), and 1.x's setting carried over once.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("selljunk")

-- one bag: slot -> { id, quality, count, price, questID }
local function bags(list)
    C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and #list or 0 end,
        GetContainerItemID = function(bag, slot) return bag == 0 and list[slot] and list[slot][1] or nil end,
        GetContainerItemInfo = function(bag, slot)
            local e = bag == 0 and list[slot]
            if not e then return nil end
            return { itemID = e[1], quality = e[2], stackCount = e[3], hasNoValue = e[4] == 0 }
        end,
        GetContainerItemQuestInfo = function(bag, slot)
            local e = bag == 0 and list[slot]
            return { isQuestItem = e and e[5] ~= nil, questID = e and e[5] }
        end,
        UseContainerItem = function(bag, slot)
            sold[#sold + 1] = list[slot][1]
            list[slot] = nil
        end,
    }
    GetItemInfo = function(id)
        for _, e in ipairs(list) do
            if e[1] == id then return "Item " .. id, nil, e[2], nil, nil, nil, nil, nil, nil, nil, e[4] end
        end
    end
end

local function runDelayed(game)
    for _ = 1, 50 do
        local queued = game.delayed
        if #queued == 0 then return end
        game.delayed = {}
        for _, fn in ipairs(queued) do fn() end
        game:Flush()
    end
end

print("-- at a vendor: grey items are sold, nothing else")
do
    local game = FakeWoW.New(ROOT, { level = 10 })
    local OXP = game:LoadAddon()
    game:Login()
    sold = {}
    bags({
        { 100, 0, 3, 5 },          -- grey, 3 x 5c: sold
        { 101, 1, 1, 20 },         -- white: kept
        { 102, 0, 1, 0 },          -- grey with no sell price: kept
        { 103, 0, 1, 7, 555 },     -- grey quest item: kept
        { 104, 0, 1, 9 },          -- grey the guide needs: kept
        { 105, 0, 1, 2 },          -- grey: sold
    })
    local g = { name = "10-11 Junk test", group = "Test",
        steps = { { { "collect", item = 104, count = 1, text = "Keep it" } } } }
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    local said = {}
    local oldPrint = print
    print = function(msg) said[#said + 1] = tostring(msg) end
    game:Fire("MERCHANT_SHOW")
    runDelayed(game)
    print = oldPrint
    t.eq(table.concat(sold, ","), "100,105", "only the two sellable greys")
    t.ok(table.concat(said, "\n"):find("sold 2 junk items", 1, true), "says what it sold: " .. tostring(said[1]))
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
end

print("-- closing the vendor stops it; Shift or the setting off: nothing sold")
do
    local game = FakeWoW.New(ROOT, { level = 10 })
    local OXP = game:LoadAddon()
    game:Login()
    sold = {}
    bags({ { 100, 0, 1, 5 }, { 105, 0, 1, 2 } })
    game:Fire("MERCHANT_SHOW")
    game:Fire("MERCHANT_CLOSED")
    runDelayed(game)
    t.eq(#sold, 1, "one sold, then the vendor closed")

    sold = {}
    bags({ { 100, 0, 1, 5 } })
    OXP.settings.autoSellJunk = false
    game:Fire("MERCHANT_SHOW")
    runDelayed(game)
    t.eq(#sold, 0, "setting off: nothing")
    OXP.settings.autoSellJunk = true
    IsShiftKeyDown = function() return true end
    game:Fire("MERCHANT_SHOW")
    runDelayed(game)
    IsShiftKeyDown = function() return false end
    t.eq(#sold, 0, "Shift held: nothing")
end

print("-- 1.x had it off: off once in 2.0")
do
    local game = FakeWoW.New(ROOT, { level = 10, name = "Tester" })
    GetRealmName = function() return "Test Realm" end
    OXPSettings = { profileKeys = { ["Tester - Test Realm"] = "Default" }, profiles = { Default = { autoSellJunk = false } } }
    local OXP = game:LoadAddon()
    game:Login()
    t.eq(OXP.settings.autoSellJunk, false, "off, as in 1.x")
    OXPSettings = nil
    local game2 = FakeWoW.New(ROOT, { level = 10 })
    local OXP2 = game2:LoadAddon()
    game2:Login()
    t.eq(OXP2.settings.autoSellJunk, true, "on by default")
end

C_Container, GetItemInfo = nil, nil
return t.fails
