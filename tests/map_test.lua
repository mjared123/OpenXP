-- OpenXP 2.0 world map and minimap clutter: a thin route line, only the
-- current step's area (once, no label), only its mobs (merged, capped),
-- a faint pulse and only the current and next step's numbers, each layer
-- switched off by its own setting (Nav/MapDraw.lua, Nav/Pins.lua).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("map")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local function addGuide(OXP, steps, name)
    local g = { name = name or "Map test", group = "Test", steps = steps }
    OXP.AddGuides({ file = "test", g })
    return g
end

local function pinsOf(OXP, kind)
    OXP.Pins.Refresh()
    local out = {}
    for _, p in ipairs(OXP.Pins.Used()) do
        if p.kind == kind then out[#out + 1] = p end
    end
    return out
end

-- a world map on `map` (1000 x 700 canvas)
local function openWorldMap(game, map)
    _G.WorldMapFrame = game.Widget("Frame")
    _G.WorldMapFrame.shown = true
    local canvas = game.Widget("Frame")
    canvas.w, canvas.h = 1000, 700
    _G.WorldMapFrame.GetCanvas = function() return canvas end
    _G.WorldMapFrame.GetMapID = function() return map end
end

-- the widths of the lines drawn now in the route's colour, and how many
local function routeWidths(OXP, which)
    local c = OXP.MapDraw.Canvas(which)
    local lo, hi, n = math.huge, 0, 0
    for i = 1, c and c.nl or 0 do
        local l = c.lines[i]
        if l.oxpColor and l.oxpColor[1] == 0.72 and l.oxpColor[3] == 1.0 then
            n = n + 1
            lo, hi = math.min(lo, l.oxpWidth), math.max(hi, l.oxpWidth)
        end
    end
    return lo, hi, n
end

local AREA = { 8.85, 62.27, 9.23, 48.18, 12.47, 49.82, 12.43, 60.62 }
local OTHER = { 30, 30, 34, 30, 34, 34, 30, 34 }

------------------------------------------------------------------------
print("-- areas: only the current step's, each once, no label; mapAreas hides them")
do
    local game, OXP = newGame({ level = 22, map = 1431, x = 60, y = 60 })
    local g = addGuide(OXP, {
        -- two steps on screen at once (completewith), the same area twice
        { completewith = "next", { "goto", zone = "Duskwood", x = 10.75, y = 55.39 },
          { "area", zone = "Duskwood", points = AREA }, { "complete", quest = 101, obj = 1 } },
        { { "goto", zone = "Duskwood", x = 10.8, y = 55.4 },
          { "area", zone = "Duskwood", points = { 8.9, 62.2, 9.2, 48.2, 12.5, 49.8, 12.4, 60.6 } },
          { "complete", quest = 101, obj = 2 } },
        -- a step ahead with its own area: not drawn yet
        { { "goto", zone = "Duskwood", x = 32, y = 32 },
          { "area", zone = "Duskwood", points = OTHER }, { "complete", quest = 102, obj = 1 } },
    })
    OXP.Engine.Load(g.key)
    local active = OXP.Engine.GetActive()
    t.eq(#active, 2, "two steps on screen")
    local areas = OXP.MapDraw.CurrentAreas()
    t.eq(#areas, 1, "the same area of two current steps is drawn once")
    t.ok(areas[1] and #areas[1].positions == 2, "and stands for both steps")
    for _, e in ipairs(areas) do
        t.ok(e.area.poly[1][1] < 20, "the step ahead's area isn't drawn")
    end
    t.ok(OXP.MapDraw.SameArea({ map = 1, poly = { { 0, 0 }, { 10, 0 }, { 10, 10 } } },
        { map = 1, poly = { { 0.3, 0.2 }, { 10.2, 0 }, { 10, 10.3 } } }), "nearly the same middle and size: the same area")
    t.ok(not OXP.MapDraw.SameArea({ map = 1, poly = { { 0, 0 }, { 10, 0 }, { 10, 10 } } },
        { map = 1, poly = { { 20, 20 }, { 30, 20 }, { 30, 30 } } }), "somewhere else: another area")
    t.ok(not OXP.MapDraw.SameArea({ map = 1, poly = { { 0, 0 }, { 10, 0 }, { 10, 10 } } },
        { map = 1, poly = { { 4, 4 }, { 6, 4 }, { 6, 6 } } }), "a small area inside a big one: another area")

    local spots = pinsOf(OXP, "area")
    t.eq(#spots, 1, "one tooltip spot for the area")
    t.ok(spots[1] and spots[1].label == "" and spots[1].icon == nil, "no text or icon on the map")
    t.ok(spots[1] and tostring(spots[1].tip[1]):find("area - step 1, 2", 1, true), "its tooltip names it: " .. tostring(spots[1] and spots[1].tip[1]))

    openWorldMap(game, 1431)
    OXP.MapDraw.WorldMap()
    local c = OXP.MapDraw.Canvas()
    t.ok(c.nr > 0, "the area is filled on the world map")
    local edge = 0
    for i = 1, c.nl do
        local l = c.lines[i]
        if l.oxpColor and l.oxpColor[1] == 0.35 then
            edge = edge + 1
            t.ok(l.oxpWidth <= 1.5, "a thin outline")
            t.ok(l.oxpColor[4] <= 0.6, "and a soft one")
            break
        end
    end
    t.ok(edge > 0, "the area has an outline")
    for i = 1, c.nr do t.ok(c.rects[i].vertex[4] <= 0.15, "a soft fill") break end

    OXP.settings.mapAreas = false
    OXP.Send("SETTINGS_CHANGED")
    t.eq(#OXP.MapDraw.CurrentAreas(), 0, "areas off: none")
    OXP.MapDraw.WorldMap()
    t.eq(OXP.MapDraw.Canvas().nr, 0, "areas off: nothing filled on the world map")
    t.eq(#pinsOf(OXP, "area"), 0, "areas off: no tooltip spot")
    OXP.settings.mapAreas = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- route line: half as wide as before, a setting for its width, mapRoute hides it")
do
    local game, OXP = newGame({ level = 22, map = 1431, x = 20, y = 20 })
    local g = addGuide(OXP, {
        { { "goto", zone = "Duskwood", x = 80, y = 20 }, { "accept", quest = 101 } },
    })
    OXP.Engine.Load(g.key)
    -- a trip line (Nav/Travel.lua) so there's something to draw on any build
    OXP.Travel.Polylines = function() return { { { 20, 20 }, { 50, 50 }, { 80, 20 } } } end
    openWorldMap(game, 1431)
    t.eq(OXP.settings.routeWidth, OXP.MapDraw.ROUTE_WIDTH, "the default width is the new thin one")
    t.ok(OXP.MapDraw.ROUTE_WIDTH <= 1.5, "about half the old 3 px")
    OXP.MapDraw.WorldMap()
    local lo, hi, n = routeWidths(OXP)
    t.ok(n > 0, "the route is drawn")
    t.eq(lo, 1.5, "the line is 1.5 px wide")
    t.eq(hi, lo, "all of it")
    local c = OXP.MapDraw.Canvas()
    local casing, cw
    for i = 1, c.nl do
        local col = c.lines[i].oxpColor
        if col and col[1] < 0.1 then casing = col cw = c.lines[i].oxpWidth end
    end
    t.ok(casing and casing[4] <= 0.45, "a faint dark casing")
    t.ok(cw and cw > lo and cw < 3, "a little wider than the line (" .. tostring(cw) .. ")")
    OXP.settings.routeWidth = 3
    OXP.MapDraw.WorldMap()
    lo = routeWidths(OXP)
    t.eq(lo, 3, "Settings > Maps > Route line width")
    OXP.settings.routeWidth = 1.5

    Minimap.GetZoom = function() return 0 end
    OXP.MapDraw.Minimap()
    lo, hi, n = routeWidths(OXP, "minimap")
    t.ok(n > 0 and lo < 1.5, "the minimap's line is thinner still (" .. tostring(lo) .. ")")

    OXP.settings.mapRoute = false
    OXP.MapDraw.WorldMap()
    lo, hi, n = routeWidths(OXP)
    t.eq(n, 0, "route off: no line")
    OXP.settings.mapRoute = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- step pins: the current step and the next, numbers and the pulse by setting")
do
    local game, OXP = newGame({ level = 22, map = 1431, x = 5, y = 5 })
    local steps = {}
    for i = 1, 6 do
        steps[i] = { { "goto", zone = "Duskwood", x = 10 + i * 10, y = 50 }, { "accept", quest = 200 + i } }
    end
    local g = addGuide(OXP, steps)
    OXP.Engine.Load(g.key)
    OXP.settings.mapQuestIcons = "off" -- numbered badges
    local pins = pinsOf(OXP, "step")
    t.eq(#pins, 2, "the current step and the next, not every step ahead")
    t.ok(pins[1] and pins[1].num == "1" and pins[2] and pins[2].num == "2", "numbered 1 and 2")
    local glow = 0
    for _, p in ipairs(pins) do if p.glow then glow = glow + 1 end end
    t.eq(glow, 1, "only the current step pulses")
    t.ok(OXP.Pins.GLOW.to <= 0.5 and OXP.Pins.GLOW.size <= 1.5, "and only faintly")
    OXP.settings.mapNextStep = false
    t.eq(#pinsOf(OXP, "step"), 1, "next step off: only the current one")
    OXP.settings.mapNextStep = true
    OXP.settings.mapStepNumbers = false
    pins = pinsOf(OXP, "step")
    t.ok(#pins == 2 and pins[1].num == "" and pins[1].tag == "" and pins[2].num == "", "step numbers off: none on the pins")
    OXP.settings.mapStepNumbers = true
    OXP.settings.mapQuestIcons = "on"
    pins = pinsOf(OXP, "step")
    t.ok(#pins == 2 and pins[1].tag == "1", "quest icons carry the number as a tag")
    OXP.settings.mapStepNumbers = false
    pins = pinsOf(OXP, "step")
    t.ok(pins[1] and pins[1].tag == "", "and lose it with step numbers off")
    OXP.settings.mapStepNumbers = true
    OXP.settings.mapPins = false
    t.eq(#pinsOf(OXP, "step"), 0, "step pins off: none")
    OXP.settings.mapPins = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- mob pins: the current step's open objectives, merged, small, capped")
do
    local game, OXP = newGame({ level = 23, map = 1437, x = 10, y = 40 })
    OXP.settings.mapQuestIcons = "on"
    local g = addGuide(OXP, {
        { { "goto", zone = "Wetlands", x = 38.18, y = 50.89 }, { "accept", quest = 288 } },
        { { "goto", zone = "Wetlands", x = 15.26, y = 39.83 },
          { "complete", quest = 279, obj = 1 }, { "mob", name = "Bluegill Murloc" },
          { "complete", quest = 279, obj = 2 }, { "mob", name = "Gobbler" } },
    }, "Mob pins test")
    OXP.Engine.Load(g.key)
    game:Accept(279, 2)
    t.eq(OXP.Engine.GetPosition(), 1, "on the first step")
    t.eq(#pinsOf(OXP, "mob"), 0, "the next step's mobs aren't shown yet")
    OXP.Engine.Next()
    local mobs = pinsOf(OXP, "mob")
    t.ok(#mobs > 0 and #mobs <= OXP.Pins.MAX_MOBS, "the current step's mobs, capped: " .. #mobs)
    local merged, small, spawns = 0, true, 0
    for _, p in ipairs(mobs) do
        if (p.count or 1) > 1 then
            merged = merged + 1
            t.ok(p.tag == tostring(p.count), "a merged pin shows its count")
        end
        if p.label ~= "Gobbler" and p.size > 10 then small = false end
        spawns = spawns + (p.count or 1)
    end
    t.ok(merged > 0, "spawns close together are merged into one pin (" .. merged .. ")")
    t.ok(small, "mob pins are small")
    t.ok(spawns > #mobs, "fewer pins than spawns: " .. #mobs .. " for " .. spawns)
    -- pins of one objective are never on top of each other
    local close = 0
    for i, a in ipairs(OXP.Pins.MobClusters()) do
        for j, b in ipairs(OXP.Pins.MobClusters()) do
            if j > i and not a.few and not b.few and a.g == b.g and a.inst == b.inst
                and OXP.Places.Distance(a.wx, a.wy, b.wx, b.wy) < OXP.Pins.MOB_CLUSTER / 3 then
                close = close + 1
            end
        end
    end
    t.eq(close, 0, "no two pins of the same mobs piled on one spot")
    -- the murlocs are done: their pins go, Gobbler stays
    game:FinishObjective(279, 1)
    game.now = game.now + 1
    mobs = pinsOf(OXP, "mob")
    local murlocs, gobbler = 0, 0
    for _, p in ipairs(mobs) do
        if p.tip[1] == "Bluegill Murloc" then murlocs = murlocs + 1 end
        if p.label == "Gobbler" then gobbler = gobbler + 1 end
    end
    t.eq(murlocs, 0, "a finished objective's mobs are hidden")
    t.ok(gobbler > 0, "the open one's mob stays")
    OXP.settings.mapMobs = false
    t.eq(#pinsOf(OXP, "mob"), 0, "mob icons off: none")
    OXP.settings.mapMobs = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
