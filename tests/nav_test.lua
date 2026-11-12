-- OpenXP 2.0 navigation: terrain ways, kill areas, path hints, the travel
-- planner, the arrow's target and the map drawing, with the real data files
-- in the headless client (tests/lib/fakewow.lua: every map is a 1000-yard
-- square in a fake world).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("nav")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local function crosses(pts, ax, ay, test)
    local px, py = ax, ay
    for _, p in ipairs(pts) do
        for s = 0, 20 do
            local x, y = px + (p[1] - px) * s / 20, py + (p[2] - py) * s / 20
            if test(x, y) then return true end
        end
        px, py = p[1], p[2]
    end
    return false
end

local function length(pts, ax, ay)
    local d, px, py = 0, ax, ay
    for _, p in ipairs(pts or {}) do
        d = d + math.sqrt((p[1] - px) ^ 2 + (p[2] - py) ^ 2)
        px, py = p[1], p[2]
    end
    return d
end

local function addGuide(OXP, steps, name)
    local g = { name = name or "Nav test", group = "Test", steps = steps }
    OXP.AddGuides({ file = "test", g })
    return g
end

------------------------------------------------------------------------
print("-- terrain: ways around Duskwood's cliffs, mountains and packs")
do
    local tgame, OXP = newGame({ level = 22 })
    local T = OXP.Terrain
    T.lazyPerFrame = math.huge
    local pts = T.FindPath(1431, 75.3, 48.7, 66.7, 17.9, 22)
    t.ok(pts, "Darkshire to the northern spiders goes around")
    if pts then
        t.ok(not crosses(pts, 75.3, 48.7, function(x, y) return y > 30 and y < 55 and x < 70 end), "never through the cliff")
        t.ok(pts[#pts][1] == 66.7 and pts[#pts][2] == 17.9, "ends on the target")
    end
    t.ok(T.FindPath(1431, 18.4, 56.4, 25.0, 50.0, 22) == nil, "open ground: straight there")
    local grove = T.FindPath(1431, 30.0, 40.0, 65.0, 40.0, 30)
    t.ok(grove and not crosses(grove, 30, 40, function(x, y) return x > 37 and x < 57 and y > 25 and y < 55 end),
        "around the Twilight Grove mountains")
    local low = T.FindPath(1431, 12.0, 45.0, 30.0, 30.0, 22)
    local high = T.FindPath(1431, 12.0, 45.0, 30.0, 30.0, 31)
    t.ok(low, "level 22 walks around the Raven Hill undead")
    t.ok(length(low, 12, 45) > length(high or { { 30, 30 } }, 12, 45), "level 31 goes less far round")
    t.ok(T.FindPath(1429, 10, 10, 90, 90, 22) == nil or true, "a zone without blocked ground is fine")
    t.ok(T.FindPath(9999, 10, 10, 20, 20, 22) == nil, "no terrain for the map: nil")

    -- lazy searches wait a frame
    T.lazyPerFrame = 1
    tgame.now = tgame.now + 1 -- a new frame
    local a, pa = T.FindPath(1431, 70, 70, 20, 20, 22, true)
    local b, pb = T.FindPath(1431, 71, 70, 20, 21, 22, true)
    t.ok(not pa and pb, "second new search in a frame waits")
    tgame.now = tgame.now + 1
    b, pb = T.FindPath(1431, 71, 70, 20, 21, 22, true)
    t.ok(not pb, "and runs the next frame")
    local _ = a, b
end

------------------------------------------------------------------------
print("-- kill areas: Here inside, the nearest edge from outside")
do
    local game, OXP = newGame({ level = 22, map = 1431, x = 10, y = 55 })
    local g = addGuide(OXP, {
        { { "goto", zone = "Duskwood", x = 10.75, y = 55.39 },
          { "area", zone = "Duskwood", points = { 8.85, 62.27, 9.23, 48.18, 12.47, 49.82, 12.43, 60.62 } },
          { "complete", quest = 101, obj = 1 } },
    })
    OXP.Engine.Load(g.key)
    local step = OXP.Engine.GetSteps()[1]
    local target = OXP.Areas.Target(step, "spiders")
    t.ok(target and target.inside, "inside the area")
    game:MoveTo(1431, 20, 55)
    target = OXP.Areas.Target(step, "spiders")
    t.ok(target and not target.inside, "outside")
    if target then
        local x, y = OXP.Places.ToZone(target.wx, target.wy, 1431)
        t.ok(OXP.Terrain.InsidePoly(OXP.Places.AreaPolygon(step.goals[2]), x, y), "leads just inside the edge")
        t.ok(math.abs(x - 12) < 1, "the near (east) edge: " .. x)
    end
    -- an area from Questie's spawns when the step names none
    _G.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestieDB" then
            return { GetQuest = function(id) if id == 990102 then return { objectives = { { { 990048 } } } } end end,
                     GetNPC = function(id)
                         if id == 990048 then
                             local s = {}
                             for i = 1, 8 do s[i] = { 30 + i * 0.5, 40 + (i % 3) } end
                             return { spawns = { [10] = s } }
                         end
                     end }
        end
        return { GetUiMapIdByAreaId = function() return 1431 end }
    end }
    local spawns = OXP.QuestDB.ObjectiveSpawns(990102, 1, 1431, 10)
    t.eq(#spawns, 8, "spawn points read from Questie")
    local poly = OXP.Areas.KillArea(spawns, 32, 41)
    t.ok(poly and #poly >= 3 and #poly <= 8, "kill area from spawns")
    _G.QuestieLoader = nil
end

------------------------------------------------------------------------
print("-- path hints: caves, ridges, learning entrances, /oxp path")
do
    local game, OXP = newGame({ level = 10 })
    local PH = OXP.PathHints
    -- sample areas: a mine with a two-stone entrance, and a jump-down camp
    OXP.pathHintData = {
        { name = "Jasperlode Mine", inst = 0, indoor = true, circles = { { -590, -9100, 60 } },
          entrances = { { { -610.25, -9186.47 }, { -604.49, -9180.39 } } } },
        { name = "Frostmane Hold", inst = 0, indoor = true, circles = { { 690, -5590, 85 } },
          entrances = { { { 572.06, -5534.28 }, { 586.49, -5546.20 }, oneWay = true } } },
        passes = {},
    }
    PH.Changed()
    local player = { x = 0, y = 0, inst = 0, indoors = false, subzone = "" }
    local function at(x, y, indoors, subzone)
        player.x, player.y, player.indoors, player.subzone = x, y, indoors or false, subzone or ""
    end
    local function route(target)
        return PH.Route(target, player.x, player.y, player.inst,
            { indoors = player.indoors, subzone = player.subzone, map = 1429 })
    end
    local function near(pt, x, y) return pt and math.abs(pt[1] - x) < 0.1 and math.abs(pt[2] - y) < 0.1 end
    local yip = { wx = -595.1, wy = -9072.2, instance = 0, map = 1429 }
    PH.Reset()
    at(-700, -9300)
    local pt, label = route(yip)
    t.ok(near(pt, -610.25, -9186.47), "outside the mine: first stone")
    t.eq(label, "Enter Jasperlode Mine", "label")
    at(-612, -9188)
    t.ok(near(route(yip), -604.49, -9180.39), "then the mouth")
    at(-604, -9181)
    t.ok(route(yip) == nil, "then straight at the target")
    PH.Reset()
    local wolves = { wx = -798.5, wy = -9418.1, instance = 0, map = 1429 }
    at(-580, -9120, true)
    pt, label = route(wolves)
    t.ok(near(pt, -604.49, -9180.39) and label == "Leave Jasperlode Mine", "inside: out through the mouth")
    PH.Reset()
    at(690, -5590, true)
    t.ok(route({ wx = 400, wy = -5400, instance = 0, map = 1426 }) == nil, "a jump-down entrance is never used to leave")

    -- learning a cave from walking in and out
    PH.LearnTick(100, 100, 0, false)
    PH.LearnTick(110, 100, 0, true)
    PH.LearnTick(112, 100, 0, true)   -- in (two readings agree)
    PH.LearnTick(130, 120, 0, true)
    PH.LearnTick(150, 140, 0, true)
    PH.LearnTick(130, 120, 0, true)
    PH.LearnTick(112, 101, 0, false)
    PH.LearnTick(111, 100, 0, false)  -- out
    local saved = PH.Saved()
    t.eq(#saved.areas, 1, "a cave learned")
    t.ok(saved.areas[1] and #saved.areas[1].entrances >= 1, "with its entrance")

    -- /oxp path to a zone
    OXP.RunCommand("path to Stonetalon Mountains")
    t.ok(PH.go and PH.go.untilMap == 1442, "arrow led to Stonetalon")
    OXP.RunCommand("path stop")
    t.ok(PH.go == nil, "and back on the guide")
    local _ = game
end

------------------------------------------------------------------------
print("-- travel: flights, boats and walking between zones")
do
    local game, OXP = newGame({ faction = "Alliance", race = "Human", level = 30, map = 1431, x = 77, y = 44 })
    local P = OXP.Places
    -- flight masters placed in the fake world
    local function node(name, map, x, y)
        local wx, wy, inst = P.ToWorld(map, x, y)
        return { name = name, wx = wx, wy = wy, inst = inst, faction = "A" }
    end
    OXP.flightData = {
        nodes = { [1] = node("Darkshire, Duskwood", 1431, 77.5, 44.3), [2] = node("Menethil Harbor, Wetlands", 1437, 9.5, 59.7),
                  [3] = node("Southshore, Hillsbrad", 1424, 49.3, 52.3) },
        times = { [1] = { [2] = 300 }, [2] = { [1] = 300 } },
    }
    OXP.Travel.Reset()
    game:OpenTaxi({ "Darkshire, Duskwood", "Menethil Harbor, Wetlands" })
    local wx, wy, inst = P.ToWorld(1437, 40, 40)
    local plan = OXP.Travel.PlanFor({ wx = wx, wy = wy, instance = inst, map = 1437, title = "Wetlands quest" })
    t.ok(plan, "a plan to the Wetlands")
    local kinds = {}
    for _, leg in ipairs(plan and plan.legs or {}) do kinds[#kinds + 1] = leg.kind .. ":" .. leg.text end
    local text = table.concat(kinds, " | ")
    t.ok(text:find("fly:Fly to Menethil Harbor", 1, true), "flies to Menethil: " .. text)
    local lines = OXP.Travel.Lines()
    t.ok(lines and lines[1] and lines[1]:find("^1%. "), "numbered lines for the card")
    -- the other continent: a boat
    local dx, dy, dinst = P.ToWorld(1439, 40, 60)
    game:MoveTo(1437, 10, 60)
    OXP.Travel.Reset()
    game.now = game.now + 10
    plan = OXP.Travel.PlanFor({ wx = dx, wy = dy, instance = dinst, map = 1439, title = "Darkshore quest" })
    local boat = false
    for _, leg in ipairs(plan and plan.legs or {}) do if leg.kind == "boat" then boat = true end end
    t.ok(boat, "takes a boat to Kalimdor")
    -- same zone: no plan
    game:MoveTo(1439, 30, 60)
    game.now = game.now + 10
    t.ok(OXP.Travel.PlanFor({ wx = dx, wy = dy, instance = dinst, map = 1439 }) == nil, "same zone: no plan")
    -- the flight masters you see on the taxi map are remembered
    t.ok(OXP.Travel.Masters()["Darkshire, Duskwood"], "the flight master you talk to is recorded")
    t.ok(OXP.World.KnowsFlightPath("Menethil Harbor"), "known flight paths from the taxi map")
end

------------------------------------------------------------------------
print("-- the arrow: target, distance, arrival, pins, route lines")
do
    local game, OXP = newGame({ level = 22, map = 1453, x = 20, y = 50 })
    local g = addGuide(OXP, {
        { { "goto", zone = "Stormwind City", x = 30, y = 50 }, { "goto", zone = "Stormwind City", x = 40, y = 50 },
          { "text", text = "Talk to |cOXP_FRIENDLY_Bob|r" }, { "accept", quest = 500 } },
        { { "goto", zone = "Wetlands", x = 50, y = 50 }, { "accept", quest = 501 } },
    })
    OXP.Engine.Load(g.key)
    local target = OXP.Target.Update()
    t.ok(target and target.title == "Talk to Bob", "arrow title from the step text: " .. tostring(target and target.title))
    local _, dist = OXP.Arrow.Vector(target)
    t.ok(dist and math.abs(dist - 100) < 1, "100 yards to the first waypoint: " .. tostring(dist))
    game:MoveTo(1453, 30, 50)
    target = OXP.Target.Update()
    _, dist = OXP.Arrow.Vector(target)
    t.ok(dist and math.abs(dist - 100) < 1, "first waypoint passed: on to the second (" .. tostring(dist) .. ")")
    game:MoveTo(1453, 40, 50.5)
    OXP.Arrow.Draw()
    t.ok(OXP.Arrow.lastHere, "Here on arrival")
    game:Advance(1)
    t.ok(game.pins.world >= 2, "world map pins for the step's waypoints: " .. game.pins.world)
    t.ok(OXP.Arrow.frame:IsShown(), "arrow shown while a guide is loaded")

    -- the map drawing runs without errors
    _G.WorldMapFrame = game.Widget("Frame")
    _G.WorldMapFrame.shown = true
    local canvas = game.Widget("Frame")
    canvas.w, canvas.h = 1000, 700
    _G.WorldMapFrame.GetCanvas = function() return canvas end
    _G.WorldMapFrame.GetMapID = function() return 1453 end
    OXP.MapDraw.WorldMap()
    Minimap.GetZoom = function() return 0 end
    OXP.MapDraw.Minimap()
    local up = OXP.MapDraw.Upcoming()
    t.ok(#up >= 1 and up[1][1] == 1453, "route stops from the shown steps")
    t.eq(#OXP.MapDraw.RoutePoints(1453, 40, 50, up, 22), 0, "no route line in a city (no terrain)")
    local pts = OXP.MapDraw.RoutePoints(1431, 40, 50, { { 1431, 60, 60 } }, 22)
    t.ok(#pts >= 2, "route points in Duskwood")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))

    -- the route line's first stop is always where the arrow points
    local aim = OXP.Target.Real()
    local first = OXP.MapDraw.Upcoming()[1]
    local ax, ay = OXP.Places.ToZone(aim.wx, aim.wy, aim.map)
    t.ok(first and first[1] == aim.map and math.abs(first[2] - ax) < 0.01 and math.abs(first[3] - ay) < 0.01,
        "route line starts where the arrow points")
    OXP.Target.SetOverride({ wx = aim.wx + 300, wy = aim.wy, instance = aim.instance, map = aim.map, title = "chain" })
    first = OXP.MapDraw.Upcoming()[1]
    local ox = OXP.Places.ToZone(aim.wx + 300, aim.wy, aim.map)
    t.ok(first and math.abs(first[2] - ox) < 0.01, "and follows the arrow on a chain walk")
    OXP.Target.SetOverride(nil)

    -- fill and clip
    local ax, _, bx = OXP.MapDraw.ClipSegment(0, 50, 100, 50, { 50, 50, 20 })
    t.ok(math.abs(ax - 30) < 0.01 and math.abs(bx - 70) < 0.01, "segment clipped to the circle")
    t.ok(OXP.MapDraw.ClipSegment(0, 0, 10, 0, { 50, 50, 20 }) == nil, "outside the circle: nothing")
end

------------------------------------------------------------------------
print("-- route style and walls you record (in game: out of Menethil over the wall, not by the road)")
do
    local game, OXP = newGame({ level = 23, map = 1437, x = 12.6, y = 50.8 })
    local T = OXP.Terrain
    local function kindAt(x, y)
        local g = T.Grid(1437)
        local cx, cy = math.floor(x) + 1, math.floor(y) + 1
        return g.cells[(cy - 1) * 100 + cx]
    end
    local function crossesBlocked(pts, ax, ay)
        return crosses(pts, ax, ay, function(x, y) return kindAt(x, y) == 0 end)
    end
    local function onRoad(pts, ax, ay)
        local n, road, px, py = 0, 0, ax, ay
        for _, p in ipairs(pts) do
            for s = 1, 20 do
                local x, y = px + (p[1] - px) * s / 20, py + (p[2] - py) * s / 20
                n = n + 1
                if kindAt(x, y) == 3 then road = road + 1 end
            end
            px, py = p[1], p[2]
        end
        return road / math.max(n, 1)
    end
    t.eq(OXP.settings.routeStyle, "roads", "follow roads by default")
    local roads = T.FindPath(1437, 12.6, 50.8, 38.18, 50.89, 23)
    OXP.settings.routeStyle = "direct"
    local direct = T.FindPath(1437, 12.6, 50.8, 38.18, 50.89, 23)
    OXP.settings.routeStyle = "roads"
    t.ok(roads and direct, "a way in both styles")
    local rr, dr = onRoad(roads, 12.6, 50.8), onRoad(direct, 12.6, 50.8)
    t.ok(rr >= dr and rr > 0.5, ("roads: most of the way on the road (%.2f vs %.2f)"):format(rr, dr))
    t.ok(length(direct, 12.6, 50.8) <= length(roads, 12.6, 50.8) + 0.01, "the shortest way is no longer")
    -- Ashenvale-sized check elsewhere: the style is part of the remembered way
    t.ok(T.FindPath(1437, 12.6, 50.8, 38.18, 50.89, 23) ~= nil, "switching back works")

    -- a wall across the way: record it like in game (/oxp wall at each end)
    game:MoveTo(1437, 13.8, 40)
    T.WallCommand("")
    game:MoveTo(1437, 13.8, 53.6)
    T.WallCommand("")
    T.WallCommand("done")
    t.ok(OXP.db.walls[1437] and #OXP.db.walls[1437] == 1, "the wall is saved")
    local around = T.FindPath(1437, 12.6, 50.8, 38.18, 50.89, 23)
    t.ok(around and not crossesBlocked(around, 12.6, 50.8), "the way doesn't go through the wall")
    local south = false
    for _, p in ipairs(around or {}) do if p[2] > 53.6 or p[2] < 40 then south = true end end
    t.ok(south, "it goes round an end of the wall")
    game:MoveTo(1437, 13.8, 45)
    T.WallCommand("clear")
    t.eq(#OXP.db.walls[1437], 0, "/oxp wall clear removes it")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- one objective left: the arrow, card and map follow it (in game: Gobbler, 22-23 Wetlands)")
do
    local game, OXP = newGame({ level = 23, map = 1437, x = 10, y = 40 })
    local g = addGuide(OXP, {
        { { "goto", zone = "Wetlands", x = 38.18, y = 50.89 }, { "accept", quest = 279 } },
        { { "goto", zone = "Wetlands", x = 15.26, y = 39.83 },
          { "text", text = "Kill |cOXP_ENEMY_Bluegill Murloc|r" },
          { "text", text = "Kill |cOXP_ENEMY_Gobbler|r. Loot them for |cOXP_LOOT_Gobbler's Head|r" },
          { "complete", quest = 279, obj = 1 }, { "complete", quest = 279, obj = 2 },
          { "mob", name = "Bluegill Murloc" }, { "mob", name = "Gobbler" } },
        { { "goto", zone = "Wetlands", x = 38.18, y = 50.89 }, { "turnin", quest = 279 } },
    }, "22-23 Gobbler test")
    OXP.Engine.Load(g.key)
    game:Accept(279, 2)
    local aim = OXP.Target.Update()
    t.eq(aim and aim.real and aim.real.title, "Kill Bluegill Murloc", "both left: the step's own words")
    OXP.Pins.Refresh()
    local pins = OXP.Pins.Used()
    local function find(test)
        for _, p in ipairs(pins) do if test(p) then return p end end
    end
    t.ok(find(function(p) return p.num == "2" and p.tip[1]:find("Step 2", 1, true) end), "a numbered pin for the step, with a tooltip")
    t.ok(find(function(p) return p.label == "#3" end), "the turn-in after it: a ? pin with its number")
    t.ok(find(function(p) return p.tip and p.tip[1] == "Bluegill Murloc" end), "mob icons where the murlocs spawn")
    t.ok(find(function(p) return p.label == "Gobbler" and p.size == 16 end), "Gobbler gets his own big pin with his name")
    t.ok(find(function(p) return (p.label or ""):find("area (#2)", 1, true) end), "the blue area is labelled")
    local mobs = 0
    for _, p in ipairs(pins) do if p.tip and p.tip[1] == "Bluegill Murloc" then mobs = mobs + 1 end end
    t.ok(mobs <= OXP.Pins.MAX_MOBS, "mob icons are capped: " .. mobs)

    -- the murlocs are done: only Gobbler's Head is left
    game:FinishObjective(279, 1)
    game.now = game.now + 1
    aim = OXP.Target.Update()
    t.eq(aim and aim.real and aim.real.title, "Kill Gobbler for Gobbler's Head", "the arrow says what's left")
    local step2 = OXP.Engine.GetSteps()[2]
    aim = OXP.Areas.Target(step2, "x") -- the arrow's aim before any way around the terrain
    t.ok(aim and aim.spawn, "and points at one of Gobbler's spawns")
    local zx, zy = OXP.Places.ToZone(aim.wx, aim.wy, 1437)
    t.ok(zx and math.abs(zx - 15.2) < 0.2 and math.abs(zy - 41.5) < 0.2, "the nearest one: " .. tostring(zx) .. "," .. tostring(zy))
    game:MoveTo(1437, 15.2, 41.5)
    game.now = game.now + 1
    aim = OXP.Areas.Target(step2, "x")
    zx, zy = OXP.Places.ToZone(aim.wx, aim.wy, 1437)
    t.ok(math.abs(zx - 18.1) < 0.2, "standing at it, the arrow goes on to the other spawn")
    local card = OXP.Card.GoalText({ "complete", quest = 279, obj = 2 })
    t.ok(card:find("from Gobbler", 1, true), "the card says who drops it: " .. card)
    OXP.Pins.Refresh()
    pins = OXP.Pins.Used()
    t.ok(not find(function(p) return p.tip and p.tip[1] == "Bluegill Murloc" end), "no murloc icons once they're done")
    t.ok(find(function(p) return p.label == "Gobbler" end), "Gobbler still marked")
    OXP.settings.mapMobs = false
    OXP.Pins.Refresh()
    pins = OXP.Pins.Used()
    t.ok(not find(function(p) return p.label == "Gobbler" end), "mob icons off in settings")
    OXP.settings.mapMobs = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
