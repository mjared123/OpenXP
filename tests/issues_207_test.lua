-- GitHub issues fixed for 2.0.7: the arrow leads to your class trainer on a
-- "train your new spells" step (#127), flights you don't know (#125).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("issues207")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local counter = 0
local function addGuide(OXP, steps, extra)
    counter = counter + 1
    local g = { name = "1-11 Issues 207 test " .. counter, group = "Test", steps = steps }
    for k, v in pairs(extra or {}) do g[k] = v end
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

------------------------------------------------------------------------
print("-- #127: a train goal leads to your class's trainer")
do
    local game, OXP = newGame({ level = 2, class = "PRIEST", race = "Human", faction = "Alliance" })
    game:MoveTo(1429, 48.2, 43.5)
    game:Accept(18)
    addGuide(OXP, { { { "text", text = "Deputy Willem" },
                      { "goto", x = 48.17, y = 42.94, zone = "1429" },
                      { "accept", quest = 18, text = "Accept Brotherhood of Thieves" },
                      { "target", name = "Deputy Willem" },
                      { "train", text = "Train your new spells" } },
                    { { "text", text = "Next" }, { "accept", quest = 990301 } } })
    game.now = game.now + 1
    OXP.Target.Update()
    local r = OXP.Target.Real()
    t.ok(r and math.abs(r.x - 49.81) < 0.01 and math.abs(r.y - 39.49) < 0.01,
        "the arrow leads to Priestess Anetta (" .. tostring(r and r.x) .. "," .. tostring(r and r.y) .. ")")
    local _, lines = OXP.Card.StepContent(OXP.Engine.GetSteps()[1])
    local found = false
    for _, l in ipairs(lines) do if l.text:find("Priestess Anetta", 1, true) then found = true end end
    t.ok(found, "the card names her")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

print("-- #127: a mage gets Khelden Bremen; a step that goes to the trainer itself keeps its spot")
do
    local game, OXP = newGame({ level = 2, class = "MAGE", race = "Human", faction = "Alliance" })
    game:MoveTo(1429, 48.2, 43.5)
    game:Accept(18)
    addGuide(OXP, { { { "goto", x = 48.17, y = 42.94, zone = "1429" },
                      { "accept", quest = 18 },
                      { "train" } },
                    { { "goto", x = 40, y = 40, zone = "1429" }, { "train" } } })
    game.now = game.now + 1
    OXP.Target.Update()
    local r = OXP.Target.Real()
    t.ok(r and math.abs(r.x - 49.65) < 0.01, "Khelden Bremen (" .. tostring(r and r.x) .. ")")
    local w = OXP.Target.Waypoints(OXP.Engine.GetSteps()[2])
    t.ok(#w == 1 and w[1].spot.x == 40, "the guide's own goto to a trainer is kept")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #125: a flight to a place whose flight path you don't have says so")
do
    local game, OXP = newGame({ level = 20, class = "SHAMAN", race = "Tauren", faction = "Horde" })
    game:MoveTo(1413, 51.5, 30.3)
    addGuide(OXP, { { { "text", text = "Fly to Thunder Bluff" },
                      { "fly", inst = 1, name = "Thunder Bluff", text = "Fly to Thunder Bluff", wx = 29.7, wy = -1197.2 } } })
    local function note()
        OXP.Card.Refresh(true)
        local step = OXP.Engine.GetSteps()[1]
        for _, g in ipairs(step.goals) do
            local n = OXP.Card.UnknownFlight(g, step)
            if n then return n end
        end
    end
    t.eq(note(), nil, "flight paths not known yet (no flight map opened): no note")
    OXP.World.LearnFlightPath("Crossroads, The Barrens")
    t.ok((note() or ""):find("Thunder Bluff flight path", 1, true) ~= nil, "knows Crossroads only: says Thunder Bluff isn't learned")
    OXP.World.LearnFlightPath("Thunder Bluff, Mulgore")
    t.eq(note(), nil, "learned: no note")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
