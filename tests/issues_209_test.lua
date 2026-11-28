-- GitHub issues fixed for 2.0.9: flight paths the taxi map only lists as
-- DISTANT aren't yours (#154), a flight path learned away from its step (#148).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("issues209")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

------------------------------------------------------------------------
print("-- #154: a DISTANT node on the taxi map isn't a known flight path")
do
    local game, OXP = newGame({ faction = "Alliance", race = "Human", level = 20, map = 1437, x = 9.5, y = 59.7 })
    OXP.World.LearnFlightPath("Thelsamar, Loch Modan") -- counted by an older version
    game.taxi = {
        { name = "Menethil Harbor, Wetlands", type = "CURRENT" },
        { name = "Ironforge, Dun Morogh", type = "REACHABLE" },
        { name = "Thelsamar, Loch Modan", type = "DISTANT" },
    }
    game:Fire("TAXIMAP_OPENED")
    game:Flush()
    local W = OXP.World
    t.ok(W.KnowsFlightPath("Menethil Harbor") and W.KnowsFlightPath("Ironforge"), "current and reachable count")
    t.ok(not W.KnowsFlightPath("Thelsamar"), "a DISTANT node doesn't, and an old wrong one is dropped")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #148: 'New flight path discovered' away from the guide's step")
do
    local game, OXP = newGame({ faction = "Horde", race = "Orc", level = 36 })
    local n = OXP.flightData.nodes[38]
    t.ok(n and n.name:find("Shadowprey", 1, true), "Shadowprey Village is in the flight data")
    game:MoveToWorld(n.wx + 10, n.wy - 5, n.inst)
    OXP.World.LearnFlightPath("Orgrimmar, Durotar")
    t.ok(not OXP.World.KnowsFlightPath("Shadowprey Village"), "not known yet")
    game:DiscoverFlightPath()
    t.ok(OXP.World.KnowsFlightPath("Shadowprey Village"), "the flight master beside you is learned")
    game:MoveToWorld(n.wx + 500, n.wy, n.inst)
    OXP.World.LearnFlightPath("Orgrimmar, Durotar")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #139/#151/#152/#121: a border spot you've reached isn't pointed back at")
do
    local game, OXP = newGame({ faction = "Alliance", race = "Human", level = 20, map = 1432, x = 50, y = 50 })
    local P, T = OXP.Places, OXP.Travel
    local function node(map, x, y, kind)
        local wx, wy, inst = P.ToWorld(map, x, y)
        return { wx = wx, wy = wy, inst = inst, zones = { [map] = true }, kind = kind, name = kind }
    end
    local gate = node(1432, 20, 80, "gate")
    local target = node(1426, 80, 50, "target")
    local real = { wx = target.wx, wy = target.wy, instance = target.inst, map = 1426, title = "Into Dun Morogh" }
    local savedPlan, savedOn = T.PlanFor, T.IsOn
    T.IsOn = function() return true end
    T.PlanFor = function()
        local px, py, pinst = P.Player()
        local you = { wx = px, wy = py, inst = pinst, zones = { [1432] = true }, kind = "you" }
        return { legs = { { kind = "walk", text = "Head into Dun Morogh", pts = { you, gate, target }, to = target } } }
    end
    game:MoveTo(1432, 50, 50)
    local a = T.ArrowTarget(real)
    t.ok(a and math.abs(a.wx - gate.wx) < 1, "first the border spot")
    game:MoveTo(1432, 20.5, 80)
    t.ok(T.ArrowTarget(real) == nil, "there: on to the spot itself")
    game:MoveTo(1432, 25, 80)
    t.ok(T.ArrowTarget(real) == nil, "a few steps off it: not turned back to it")
    T.PlanFor, T.IsOn = savedPlan, savedOn
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- guide ideas: #146 Feralas yetis, #134 snouts, #138 isosprings, #140 fly to Ironforge")
do
    local game, OXP = newGame({ faction = "Alliance", race = "Human", level = 44 })
    local function guide(name)
        for _, g in ipairs(OXP.Registry.All()) do if g.name == name and g.only == "Alliance" then return g end end
    end
    local fer, ok = guide("43-45 Feralas"), true
    local pristine
    for _, st in ipairs(fer.steps) do
        for _, x in ipairs(st) do
            if x.quest == 7733 and (x[1] == "complete" or x[1] == "turnin") and not x.optional then ok = false end
            if x[1] == "collect" and x.item == 18969 then pristine = st end
        end
    end
    t.ok(ok, "Improved Quality's hides and hand-in are optional")
    t.ok(pristine and pristine.when and pristine.when[1][1] == "has", "the Pristine Yeti Hide step only once it dropped")
    local wf = guide("11-17 Westfall")
    local snout, molsen, wardrobe
    for _, st in ipairs(wf.steps) do
        for _, x in ipairs(st) do
            if x[1] == "complete" and x.quest == 38 and x.obj == 3 and st.along then snout = st end
            if x[1] == "complete" and x.quest == 9 then molsen = st end
            if x[1] == "complete" and x.quest == 64 then wardrobe = st end
        end
    end
    t.ok(snout ~= nil, "the snouts are an as-you-go step")
    local held = false
    for _, x in ipairs(molsen or {}) do if x.quest == 92909 and x[1] == "complete" then held = true end end
    local later = false
    for _, x in ipairs(wardrobe or {}) do if x.quest == 92909 and x[1] == "complete" then later = true end end
    t.ok(molsen and not held and later, "Molsen Farm doesn't wait for the isosprings; Furlbrow's farm finishes them")
    local lm, walks = guide("17-21 Loch Modan, Redridge Mountains & Westfall"), 0
    for _, st in ipairs(lm.steps) do
        for _, c in ipairs(st.when or {}) do
            if c[1] == "flightpath" and c.name == "Ironforge" and c.neg then walks = walks + 1 end
        end
    end
    t.eq(walks, 2, "the walk to Ironforge drops with its flight path")
    t.ok(OXP.Goals.CONDITIONS.flightpath({ name = "Ironforge" }) == false, "no Ironforge flight path yet")
    OXP.World.LearnFlightPath("Ironforge, Dun Morogh")
    t.ok(OXP.Goals.CONDITIONS.flightpath({ name = "Ironforge" }), "and then known")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
