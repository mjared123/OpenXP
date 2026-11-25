-- 2.0.7 fixes from CurseForge comments (2026-11-25): no "You don't have X
-- yet" on a step that picks X up, no chain prompt for a chain the route never
-- does (its step is passed over once the giver doesn't offer the quest),
-- Find my place doesn't jump to a section above your level, flights with
-- stops add up their legs, and the flight timer sits under the card.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("fixes207")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local counter = 0
local function addGuide(OXP, steps, extra)
    counter = counter + 1
    local g = { name = "21-22 Fixes 207 " .. counter, group = "Test", steps = steps }
    for k, v in pairs(extra or {}) do g[k] = v end
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

------------------------------------------------------------------------
print("-- a step that accepts a quest and turns it in: no warning")
do
    local game, OXP = newGame({ level = 21 })
    OXP.QuestDB.data = { prereqs = {}, info = {} }
    addGuide(OXP, {
        { { "accept", quest = 707001 }, { "turnin", quest = 707001 }, { "accept", quest = 707002 } },
        { { "complete", quest = 707002, obj = 1 } },
        { { "turnin", quest = 707003, text = "A bounty: taken and handed in at once" } },
    })
    local step = OXP.Engine.GetSteps()[1]
    t.eq(OXP.QuestDB.StepProblem(step), nil, "accept-then-turn-in step: nothing to warn about")
    game:Accept(707001, 0)
    game:TurnIn(707001)
    game:Accept(707002, 1)
    game:FinishObjective(707002, 1)
    OXP.Engine.Refresh()
    t.eq(OXP.Engine.GetPosition(), 3, "on the bounty step")
    t.eq(OXP.QuestDB.StepProblem(OXP.Engine.GetSteps()[3]), nil, "a turn-in the route never picks up: no warning")
    -- one the route does pick up still warns
    local p = OXP.QuestDB.StepProblem({ goals = { { "turnin", quest = 707002 } }, marks = {} })
    t.eq(p, nil, "on the quest: fine")
    game:Abandon(707002)
    p = OXP.QuestDB.StepProblem({ goals = { { "turnin", quest = 707002 } }, marks = {} })
    t.ok(p and p.kind == "missing", "a quest the route picks up that you don't have still warns")
    OXP.QuestDB.data = {}
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- turn in A, then take B that needs A, in one step: no chain prompt")
do
    local game, OXP = newGame({ level = 21 })
    OXP.QuestDB.data = { prereqs = { [707012] = { any = { 707011, 707019 } } }, info = {}, chains = { [707012] = { 707019 } } }
    addGuide(OXP, {
        { { "accept", quest = 707011 } },
        { { "turnin", quest = 707011 }, { "accept", quest = 707012 } },
    })
    game:Accept(707011, 0)
    OXP.Engine.Refresh()
    t.eq(OXP.QuestDB.StepProblem(OXP.Engine.GetSteps()[2]), nil, "the step's own turn-in opens the next quest")
    OXP.QuestDB.data = {}
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- a chain the route never does: no prompt; passed over once the giver doesn't offer it")
do
    local game, OXP = newGame({ level = 21 })
    OXP.QuestDB.data = { prereqs = { [707022] = { all = { 707021 } } }, info = {}, chains = { [707022] = { 707021 } } }
    local g = addGuide(OXP, {
        { { "accept", quest = 707022, text = "Accept Part Two" }, { "target", name = "Giver" } },
        { { "turnin", quest = 707022 } },
        { { "accept", quest = 707030 } },
    })
    local C = OXP.Card
    C.Refresh(true)
    t.ok(OXP.QuestDB.OutOfReach(707022), "by our data it's out of reach")
    t.eq(OXP.QuestDB.StepProblem(OXP.Engine.GetSteps()[1]), nil, "but the card doesn't ask about the chain")
    t.eq(OXP.Engine.GetPosition(), 1, "and the step waits: our data alone isn't proof")
    -- talking to the giver: it offers something else
    local realGet = OXP.QuestDB.Get
    OXP.QuestDB.Get = function(kind, id)
        if kind == "Quest" and id == 707022 then return { name = "Part Two", startedBy = { { 4242 } } } end
        return realGet(kind, id)
    end
    local realGUID = UnitGUID
    UnitGUID = function(unit) if unit == "npc" then return "Creature-0-0-0-0-4242-0000" end return realGUID and realGUID(unit) end
    C_GossipInfo = {
        GetActiveQuests = function() return {} end,
        GetAvailableQuests = function() return { { questID = 707099, title = "Something Else" } } end,
        GetOptions = function() return {} end,
        SelectAvailableQuest = function() end,
        SelectActiveQuest = function() end,
    }
    game:Fire("GOSSIP_SHOW")
    game:Flush()
    OXP.Engine.Refresh()
    t.ok(OXP.char.notOffered[707022], "noted: the giver didn't offer it")
    t.eq(OXP.Engine.GetPosition(), 3, "the pickup and its turn-in are passed over")
    t.eq(OXP.Engine.StepState(1), "chain", "marked like a missed chain")
    local list = OXP.SmartStart.SkippedChains()
    t.ok(#list >= 1 and list[1].quest == 707022, "and /oxp catchup lists it")
    -- a quest that IS offered is never noted
    OXP.char.notOffered = {}
    OXP.Engine.Place(g, 1)
    C_GossipInfo.GetAvailableQuests = function() return { { questID = 707022, title = "Part Two" } } end
    game:Fire("GOSSIP_SHOW")
    t.eq(OXP.char.notOffered[707022], nil, "offered: not noted")
    UnitGUID = realGUID
    OXP.QuestDB.Get = realGet
    OXP.QuestDB.data = {}
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- a chain the route does elsewhere still gets the prompt")
do
    local game, OXP = newGame({ level = 21 })
    OXP.QuestDB.data = { prereqs = { [707042] = { all = { 707041 } } }, info = {}, chains = { [707042] = { 707041 } } }
    addGuide(OXP, { { { "accept", quest = 707041 } } })
    addGuide(OXP, { { { "accept", quest = 707042 } }, { { "turnin", quest = 707042 } } })
    local p = OXP.QuestDB.StepProblem(OXP.Engine.GetSteps()[1])
    t.ok(p and p.kind == "chain", "prompt kept: the route picks up the earlier quest")
    OXP.QuestDB.data = {}
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- Find my place: a section above your level needs a lot more of its quests in your log")
do
    local game, OXP = newGame({ level = 19 })
    local SS = OXP.SmartStart
    local low = { name = "17-21 Low", minLevel = 17, maxLevel = 21, steps = {} }
    local high = { name = "21-23 High", minLevel = 21, maxLevel = 23, steps = {} }
    for q = 1, 10 do
        low.steps[#low.steps + 1] = { { "accept", quest = 707100 + q } }
        high.steps[#high.steps + 1] = { { "accept", quest = 707200 + q } }
    end
    for q = 1, 3 do game:Accept(707100 + q, 0) end
    for q = 1, 4 do game:Accept(707200 + q, 0) end
    local g = SS.PickGuide({ low, high }, 19, "")
    t.eq(g and g.name, "17-21 Low", "level 19 with a few more 21-23 quests in the log stays in 17-21")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- flights with stops add up their legs")
do
    local game, OXP = newGame({ level = 21, faction = "Alliance" })
    local T = OXP.Timers
    -- Sentinel Hill > Stormwind > Ironforge: no single flight in the data
    local direct = T.FlightEstimate("Sentinel Hill, Westfall", "Ironforge, Dun Morogh")
    local legs = OXP.flightData.times[4][2] + OXP.flightData.times[2][6]
    t.eq(direct, legs, "quickest chain of flights: " .. tostring(direct) .. " s")
    local viaStops = T.FlightEstimate("Sentinel Hill, Westfall", "Ironforge, Dun Morogh",
        { "Stormwind, Elwynn", "Ironforge, Dun Morogh" })
    t.eq(viaStops, legs, "the taxi map's stops: the same")
    t.ok(OXP.flightData.times[2][6] >= 250, "Stormwind to Ironforge about 4:20, as timed on Forever")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- the flight timer sits under the card; Shift-drag moves it; the setting puts it back")
do
    local game, OXP = newGame({ level = 21 })
    local T, bar = OXP.Timers, OXP.Timers.bar
    OXP.Card.frame:Show()
    T.PlaceBar()
    local point, rel = bar:GetPoint()
    t.eq(point, "TOP", "anchored by its top")
    t.ok(rel == OXP.Card.frame, "to the card")
    OXP.settings.flightTimerDocked = false
    OXP.settings.flightTimerPos = { "CENTER", "CENTER", 10, 20 }
    T.PlaceBar()
    point, rel = bar:GetPoint()
    t.ok(point == "CENTER" and rel ~= OXP.Card.frame, "where you dragged it")
    OXP.settings.flightTimerDocked = true
    T.PlaceBar()
    point, rel = bar:GetPoint()
    t.ok(rel == OXP.Card.frame, "the setting puts it back under the card")
    T.Preview()
    t.ok(bar:IsShown(), "the setting shows it so you can move it")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
