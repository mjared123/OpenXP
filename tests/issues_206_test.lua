-- GitHub issues fixed for 2.0.6: no stutter when the step's spot has no
-- walk from where you are (#122, Undercity).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("issues206")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local counter = 0
local function addGuide(OXP, steps, extra)
    counter = counter + 1
    local g = { name = "22-25 Issues 206 test " .. counter, group = "Test", steps = steps }
    for k, v in pairs(extra or {}) do g[k] = v end
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

------------------------------------------------------------------------
print("-- #122: no way on the zone graph: the search isn't run again every second")
if io.open(ROOT .. "/OpenXP_Nav/Graphs/stonetalon_mountains.lua") then
    local game, OXP = newGame({ level = 23 })
    local NAV = { packed = {}, paths = {}, spots = {} }
    assert(loadfile(ROOT .. "/OpenXP_Nav/Unpack.lua"))("OpenXP_Nav", NAV)
    assert(loadfile(ROOT .. "/OpenXP_Nav/Graphs/stonetalon_mountains.lua"))("OpenXP_Nav", NAV)
    OXP.WalkPaths.Use(NAV)
    local G = OXP.WalkGraph
    local realRoute, calls, none = G.Route, 0, false
    G.Route = function(...)
        calls = calls + 1
        if none then return nil end
        return realRoute(...)
    end
    addGuide(OXP, { { { "goto", zone = "Stonetalon Mountains", x = 76.5, y = 45.5 }, { "accept", quest = 500 } } })
    game:MoveTo(1442, 80.4, 33.7)
    -- a way exists: OnWalk (which ignores graph walks) doesn't search for one
    local target = { map = 1442, x = 76.5, y = 45.5 }
    for _ = 1, 10 do
        game.now = game.now + 1.5
        OXP.WalkPaths.OnWalk(target)
    end
    t.eq(calls, 0, "asking whether you're on a baked walk runs no graph search")
    -- no way at all: the arrow ticks for 10 seconds
    none, calls = true, 0
    OXP.WalkPaths.Reset()
    for _ = 1, 200 do
        game.now = game.now + 0.05
        OXP.Target.Update()
    end
    t.ok(calls <= 4, "no way: searched at most twice per spot in 10 s, not every second (" .. calls .. " searches)")
    -- once there's a way again (after a while) it's found
    none = false
    for _ = 1, 300 do
        game.now = game.now + 0.05
        OXP.Target.Update()
    end
    local a = OXP.Target.Update()
    t.ok(a and a.walkPath, "later the graph walk is found again")
    G.Route = realRoute
    OXP.WalkPaths.Use(nil)
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #116: picking a guide you haven't started puts you past what you've done")
do
    local game, OXP = newGame({ level = 28 })
    local steps = {}
    for q = 990101, 990106 do
        steps[#steps + 1] = { { "accept", quest = q } }
        steps[#steps + 1] = { { "goto", zone = "Ashenvale", x = 40, y = 50 }, { "turnin", quest = q } }
        steps[#steps + 1] = { { "reach", zone = "Ashenvale", x = 40, y = 50, text = "The road" } }
    end
    local g = { name = "20-23 Issues 206 place", group = "Test", steps = steps }
    OXP.AddGuides({ file = "test", g })
    for q = 990101, 990104 do game:Accept(q) game:TurnIn(q) end
    OXP.SmartStart.cachedPrereqs = nil
    OXP.GuidePicker.ShowGuides()
    OXP.GuidePicker.Select(g)
    OXP.GuidePicker.Start(false)
    t.eq(OXP.Engine.GetGuide(), g, "the picked guide is loaded")
    local step = OXP.Engine.GetSteps()[OXP.Engine.GetPosition() or 0]
    t.eq(step and step.index, 12, "just after the last quest you turned in (not back at the start)")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #120: a group quest step says so in its title")
do
    local game, OXP = newGame({ level = 22 })
    game:Accept(1090, 1)
    addGuide(OXP, { { when = { { "group", quest = 1090 } }, { "text", text = "Piznik" },
                      { "finish", quest = 1090, text = "Finish Gerenzo's Orders" } },
                    { { "text", text = "Next" }, { "accept", quest = 990201 } } })
    OXP.Card.Refresh(true)
    local b = OXP.Card.blocks and OXP.Card.blocks[1]
    local title = b and b.title:GetText() or ""
    t.ok(title:find("GROUP QUEST", 1, true) ~= nil, "GROUP QUEST in the title (" .. title .. ")")
    t.ok(OXP.Card.IsGroupStep(OXP.Engine.GetSteps()[2]) == false, "a plain step isn't one")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
