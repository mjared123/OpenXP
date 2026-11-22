-- Audit of every shipped guide (both factions, every race/class line):
--   a) every "use an item" line has an item to put on the quest item
--      button (an item id, or a "Use <item>" name OpenXP's item data knows)
--      and a window in which the button can show (a goal next to it that
--      is still to do while you carry the item)
--   b) quests in a chain with the same name get "(part N)" on the card, and
--      same-name quests that aren't a chain don't
--   c) "More" is part of the card itself, so every step gets its own row
-- Prints the counts, fails on anything that wouldn't work.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("audit")

local function load(faction, race)
    local game = FakeWoW.New(ROOT, { faction = faction, race = race, level = 1 })
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local totals = { items = 0, itemNoId = 0, useByName = 0, useNpcOrObject = 0, noWindow = 0,
                 chainLines = 0, chainLabelled = 0, sameNameNotChain = 0, sameNameLabelled = 0 }
local problems = {}

for _, side in ipairs({ { "Alliance", "Human" }, { "Horde", "Orc" } }) do
    local game, OXP = load(side[1], side[2])
    local Goals, QuestDB, Card = OXP.Goals, OXP.QuestDB, OXP.Card
    local itemNames = {}
    for id, row in pairs(OXP.questData and OXP.questData.item or {}) do itemNames[row[1]] = id end
    t.ok(next(itemNames) ~= nil, side[1] .. ": item names to look 'Use <item>' lines up in")
    for _, guide in ipairs(OXP.Registry.All()) do
        for si, data in ipairs(guide.steps) do
            local goals = {}
            for _, g in ipairs(data) do goals[#goals + 1] = g end
            local step = { goals = goals, marks = {} }
            local function Neighbour(i, dir)
                local j = i + dir
                while goals[j] do
                    local k = goals[j][1]
                    if Goals.Blocks(k) and k ~= "reach" then return goals[j] end
                    j = j + dir
                end
            end
            local anyBlocking = false
            for _, g in ipairs(goals) do if Goals.Blocks(g[1]) then anyBlocking = true end end
            for i, g in ipairs(goals) do
                local where = guide.name .. " step " .. si
                -- a) item lines
                if g[1] == "item" then
                    totals.items = totals.items + 1
                    if not g.item then
                        totals.itemNoId = totals.itemNoId + 1
                        problems[#problems + 1] = where .. ": item line without an item id"
                    end
                    -- the window: a neighbouring goal that can still be open
                    -- while the item is in your bags. A "collect" of that
                    -- same item is done the moment you have it, so it alone
                    -- is no window.
                    local before, after = Neighbour(i, -1), Neighbour(i, 1)
                    local function Window(n)
                        return n ~= nil and not (n[1] == "collect" and n.item == g.item)
                    end
                    if not (Window(before) or Window(after) or (not before and not after and anyBlocking)) then
                        if anyBlocking then
                            totals.noWindow = totals.noWindow + 1
                            problems[#problems + 1] = where .. ": no open goal around item " .. tostring(g.item)
                        end
                    end
                elseif g.text and (g[1] == "complete" or g[1] == "text") then
                    local plain = OXP.Text.Strip(g.text)
                    local name = plain:match("^Use (.-)%s*%(") or plain:match("^Use (.+)$")
                    if name then
                        name = name:gsub("%s+$", "")
                        if itemNames[name] then totals.useByName = totals.useByName + 1
                        else totals.useNpcOrObject = totals.useNpcOrObject + 1 end
                    end
                end
                -- b) chain parts
                if (g[1] == "accept" or g[1] == "turnin") and g.quest then
                    local name = QuestDB.QuestName(g.quest)
                    local part = QuestDB.ChainPart(g.quest)
                    local text = OXP.Text.Strip(Card.GoalText(g, step) or "")
                    if part and part > 1 then
                        totals.chainLines = totals.chainLines + 1
                        if text:find("(part " .. part .. ")", 1, true) then
                            totals.chainLabelled = totals.chainLabelled + 1
                        else
                            problems[#problems + 1] = where .. ": " .. g.quest .. " is part " .. part .. " but reads '" .. text .. "'"
                        end
                    else
                        -- part 1: labelled only next to a later part of its own chain
                        local mate, chain
                        for _, o in ipairs(goals) do
                            if o.quest and o.quest ~= g.quest and QuestDB.QuestName(o.quest) == name then
                                mate = o.quest
                                -- a quest can need any one of several before it
                                -- (Call of Earth 1517: 1516 or 1519)
                                if QuestDB.IsLaterPart(g.quest, o.quest) then chain = true end
                            end
                        end
                        if mate then
                            if not chain then
                                totals.sameNameNotChain = totals.sameNameNotChain + 1
                                if text:find("(part ", 1, true) then
                                    totals.sameNameLabelled = totals.sameNameLabelled + 1
                                    problems[#problems + 1] = where .. ": " .. g.quest .. " labelled as a part, but " .. mate .. " isn't its next part"
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    t.eq(#game.errors, 0, side[1] .. ": no Lua errors: " .. table.concat(game.errors, " | "))
end

print(("  item lines: %d (without an id: %d, with no window for the button: %d)"):format(
    totals.items, totals.itemNoId, totals.noWindow))
print(("  'Use <name>' lines: %d an item found by name, %d a person or object (no button needed)"):format(
    totals.useByName, totals.useNpcOrObject))
print(("  chain lines (part 2 or later): %d, labelled: %d"):format(totals.chainLines, totals.chainLabelled))
print(("  same-name quests in one step that aren't one chain: %d, wrongly labelled: %d"):format(
    totals.sameNameNotChain, totals.sameNameLabelled))
for i = 1, math.min(#problems, 20) do print("  PROBLEM " .. problems[i]) end
t.eq(totals.itemNoId, 0, "every item line has an item id")
t.eq(totals.noWindow, 0, "every item line can show its button")
t.eq(totals.chainLabelled, totals.chainLines, "every later part of a same-name chain is labelled")
t.eq(totals.sameNameLabelled, 0, "no same-name quest outside a chain is labelled")
t.ok(totals.items > 100 and totals.chainLines > 100, "the audit saw the guides")

-- c) More is the card's own button: one for every step, in its own row
do
    local game, OXP = load("Alliance", "Human")
    local more = OXP.Card.more
    t.ok(more and more.points[1] and more.points[1][1] == "TOPRIGHT" and more.points[1][3] == "BOTTOMRIGHT",
        "More is anchored under the step view (card-level, every step)")
end

return t.fails
