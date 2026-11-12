-- OpenXP 2.0 play-through: for every race and class of each faction, play
-- the whole 21-60 chain and every dungeon guide in the headless client,
-- doing exactly what each step asks (accept, kill, turn in, travel, learn a
-- flight path, ...). Checks that every step can be finished by doing what it
-- says, that the engine never gets stuck or throws, and that each guide hands
-- over to its #next until the end of the chain.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("playthrough")

local RACES = {
    Alliance = { "Human", "Dwarf", "NightElf", "Gnome", "Skyborne" },
    Horde = { "Orc", "Scourge", "Tauren", "Troll", "Skyborne" },
}
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Highest objective index each quest is asked for, so accepted quests get
-- that many objectives.
local function objectiveCounts(OXP)
    local counts = {}
    for _, g in ipairs(OXP.Registry.All()) do
        for _, step in ipairs(g.steps) do
            for _, goal in ipairs(step) do
                if goal[1] == "complete" then
                    counts[goal.quest] = math.max(counts[goal.quest] or 0, goal.obj)
                end
            end
        end
    end
    return counts
end

local binds = 0

-- Do what the goal asks in the fake world.
local function play(game, OXP, goal, objectives)
    local kind, q = goal[1], goal.quest
    local function have()
        if not OXP.Quests.IsOnQuest(q) and not OXP.Quests.IsTurnedIn(q) then
            game:Accept(q, objectives[q] or 0)
        end
    end
    if kind == "accept" then
        game:Accept(q, objectives[q] or 0)
    elseif kind == "complete" then
        have()
        game:FinishObjective(q, goal.obj)
    elseif kind == "turnin" then
        have()
        game:TurnIn(q)
    elseif kind == "xp" then
        game:SetLevel(goal.level)
    elseif kind == "zone" then
        game:EnterZone(goal.name)
    elseif kind == "fp" then
        game:OpenTaxi({ goal.name .. ", Somewhere" })
    elseif kind == "home" then
        binds = binds + 1
        game:Bind(OXP.Goals.HearthTarget(goal) or ("Inn " .. binds))
    elseif kind == "collect" then
        game:AddItem(goal.item, goal.count)
    else
        error("don't know how to play a " .. tostring(kind) .. " goal")
    end
end

-- Play the loaded guide (and the ones it hands over to) to the end.
-- Returns the names of the guides played, in order.
local function playToEnd(game, OXP, objectives, who)
    local E = OXP.Engine
    local played, guard = {}, 0
    local lastGuide
    while true do
        local guide = E.GetGuide()
        if guide ~= lastGuide then
            played[#played + 1] = guide.name
            lastGuide = guide
        end
        local pos = E.GetPosition()
        local steps = E.GetSteps()
        if pos > #steps then break end
        local step = steps[pos]
        for _, goal in ipairs(step.goals) do
            if E.GoalState(pos, goal) == "todo" then
                play(game, OXP, goal, objectives)
            end
        end
        if E.GetGuide() == guide and E.GetPosition() == pos then
            t.ok(false, who .. ": stuck at " .. guide.key .. " step " .. step.index)
            E.Next()
        end
        guard = guard + 1
        if guard > 5000 then
            t.ok(false, who .. ": runaway at " .. guide.key)
            break
        end
    end
    return played
end

local combos, stepsPlayed = 0, 0
for _, faction in ipairs({ "Alliance", "Horde" }) do
    for _, race in ipairs(RACES[faction]) do
        for _, class in ipairs(CLASSES) do
            local who = faction .. " " .. race .. " " .. class
            -- Leveling chain.
            local game = FakeWoW.New(ROOT, { faction = faction, race = race, class = class, level = 21 })
            local OXP = game:LoadAddon()
            game:Login()
            local objectives = objectiveCounts(OXP)
            local leveling = OXP.Registry.ForPlayer(nil, "OpenXP Leveling (" .. faction .. ")")
            local isNext = {}
            for _, g in ipairs(leveling) do
                if g.next then isNext[g.next] = true end
            end
            local first
            for _, g in ipairs(leveling) do
                if not isNext[g.name] then
                    t.ok(not first, who .. ": two chain starts, " .. (first and first.name or "") .. " and " .. g.name)
                    first = first or g
                end
            end
            local expected = {}
            local g = first
            while g and #expected <= #leveling do
                expected[#expected + 1] = g.name
                g = OXP.Registry.Next(g)
            end
            t.eq(#expected, #leveling, who .. ": guides in the #next chain vs leveling guides")
            OXP.Engine.Load(first)
            local played = playToEnd(game, OXP, objectives, who)
            t.eq(table.concat(played, " > "), table.concat(expected, " > "), who .. ": guide order")
            for _, name in ipairs(played) do
                local done, total = OXP.Engine.GetProgress(OXP.Registry.Find(name, first.group))
                t.ok(done == total, who .. ": " .. name .. " finished " .. done .. "/" .. total)
                stepsPlayed = stepsPlayed + total
            end
            t.eq(#game.errors, 0, who .. ": Lua errors: " .. table.concat(game.errors, " | "))

            -- Dungeons, each on its own.
            for _, d in ipairs(OXP.Registry.ForPlayer(nil, "OpenXP Dungeons")) do
                OXP.Engine.Load(d, 1)
                playToEnd(game, OXP, objectives, who .. " " .. d.name)
                local done, total = OXP.Engine.GetProgress()
                t.ok(done == total, who .. ": " .. d.name .. " finished " .. done .. "/" .. total)
                stepsPlayed = stepsPlayed + total
            end
            t.eq(#game.errors, 0, who .. ": Lua errors in dungeons: " .. table.concat(game.errors, " | "))
            combos = combos + 1
        end
    end
end
print(("   played %d characters, %d steps"):format(combos, stepsPlayed))

return t.fails
