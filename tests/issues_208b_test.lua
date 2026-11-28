-- GitHub issues #132-#159, fixed for 2.0.8: "as you go" steps you passed
-- (#135, #157), optional follow-ups (#137), event quests (#136, #145),
-- hearthstone on other clients (#158), /oxp lock (#159), people markers (#141).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("issues208b")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local counter = 0
local function addGuide(OXP, steps)
    counter = counter + 1
    local g = { name = "1-11 Issues 208b test " .. counter, group = "Test", steps = steps }
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

------------------------------------------------------------------------
print("-- #135/#157: an 'as you go' step you've passed isn't shown as done")
do
    local game, OXP = newGame({ level = 13 })
    game:Accept(990801, 1)
    addGuide(OXP, {
        { { "text", text = "Start" }, { "accept", quest = 990801 } },
        { along = true, ["until"] = 4, { "text", text = "Livers as you go" }, { "complete", quest = 990801, obj = 1 } },
        { { "text", text = "Molsen Farm" }, { "accept", quest = 990802 } },
        { { "text", text = "Back" }, { "accept", quest = 990803 } },
    })
    local E = OXP.Engine
    t.eq(E.GetPosition(), 3, "on the step after the 'as you go' one")
    t.eq(E.StepState(2), "todo", "the livers step is still open")
    local shown = false
    for _, p in ipairs(E.GetActive()) do if p == 2 then shown = true end end
    t.ok(shown, "and shown beside the current step")
    t.eq(OXP.Card.StepRole(E.GetSteps()[2], 2), "side", "the card shows it as a side step, not a done one")
    game:FinishObjective(990801, 1)
    t.eq(E.StepState(2), "done", "done once the livers are in")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #137: a hand-in of an optional pickup doesn't hold the step")
do
    local guide
    for _, g in ipairs((function()
        local game, OXP = newGame({ level = 14 })
        return OXP.Registry.All()
    end)()) do
        if g.name == "11-17 Westfall" and g.only == "Alliance" then guide = g end
    end
    local ok = guide ~= nil
    for _, st in ipairs(guide and guide.steps or {}) do
        for _, x in ipairs(st) do
            if x.quest == 92910 and x[1] == "turnin" and not x.optional then ok = false end
        end
    end
    t.ok(ok, "Westfall's second Harvesting the Harvesters hand-in is optional")
end

------------------------------------------------------------------------
print("-- #136/#145: an event quest the game calls complete counts")
do
    local game, OXP = newGame({ level = 7 })
    game:Accept(990811, 1)
    local saved = C_QuestLog.IsComplete
    C_QuestLog.IsComplete = function(id) return id == 990811 end
    addGuide(OXP, {
        { { "complete", quest = 990811, obj = 1, text = "Use the cleansing totem" } },
        { { "turnin", quest = 990811 } },
    })
    game:Fire("QUEST_LOG_UPDATE")
    game:Flush()
    t.ok(OXP.Quests.IsComplete(990811), "complete although its objective isn't ticked")
    t.eq(OXP.Engine.GetPosition(), 2, "the step moves on")
    C_QuestLog.IsComplete = saved
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #158: hearthstone on a non-English client")
do
    local game, OXP = newGame({ level = 29 })
    local savedLocale = GetLocale
    GetLocale = function() return "ruRU" end
    addGuide(OXP, {
        { { "home", text = "Set your Hearthstone to Deepwater Tavern" } },
        { { "accept", quest = 990821 } },
    })
    game:Bind("Таверна \"Глубоководье\"")
    t.eq(OXP.Engine.GetPosition(), 2, "binding while the step is shown counts")
    GetLocale = savedLocale
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

do
    local game, OXP = newGame({ level = 29 })
    addGuide(OXP, {
        { { "home", text = "Set your Hearthstone to Deepwater Tavern" } },
        { { "accept", quest = 990822 } },
    })
    game:Bind("Thelsamar")
    t.eq(OXP.Engine.GetPosition(), 1, "an English client still wants the named inn")
end

------------------------------------------------------------------------
print("-- #159: /oxp lock")
do
    local game, OXP = newGame({ level = 10 })
    OXP.settings.lockFrames = false
    OXP.RunCommand("lock")
    t.ok(OXP.settings.lockFrames, "locks")
    OXP.RunCommand("lock")
    t.ok(not OXP.settings.lockFrames, "and unlocks")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #141: raid markers on mobs only")
do
    local game, OXP = newGame({ level = 21 })
    addGuide(OXP, {
        { { "accept", quest = 7401 }, { "target", name = "Gryan Stoutmantle" },
          { "accept", quest = 7402 }, { "target", name = "Scout Riell" } },
    })
    local B = OXP.ActionButtons
    OXP.settings.raidMarkersPeople = false
    B.Refresh()
    local first = B.target:GetAttribute("macrotext") or ""
    t.ok(first:find("/tm [harm,nodead] !8", 1, true) and not first:find("[help,nodead]", 1, true),
        "first row: a mob's skull, no star for people")
    local second = B.rows[2] and B.rows[2]:GetAttribute("macrotext") or ""
    t.ok(not second:find("/tm", 1, true), "a person's row: no marker")
    OXP.settings.raidMarkersPeople = true
    B.Refresh()
    t.ok((B.target:GetAttribute("macrotext") or ""):find("[help,nodead] 1", 1, true), "setting on: the star is back")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
