-- OpenXP 2.0 world map and minimap clutter: a thin route line, only the
-- current step's area (once, no label), only its mobs (thinned, capped),
-- a faint pulse and only the current and next step's numbers, each layer
-- switched off by its own setting (Nav/MapDraw.lua, Nav/Pins.lua); and the
-- pins looking and behaving like Questie's (dev7, docs/questie-map-parity.md):
-- sizes, draw order, glow, minimap edge and fading, grouped tooltips,
-- clicks, and Blizzard's own quest markers hidden while ours show.
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
    t.ok(#pins == 2 and pins[1].tag == "" and pins[2].tag == "", "quest icons are plain ! and ?, like Questie's (no number)")
    OXP.settings.mapPins = false
    t.eq(#pinsOf(OXP, "step"), 0, "step pins off: none")
    OXP.settings.mapPins = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
-- the Wetlands murlocs (quest 279: Bluegill Murlocs and Gobbler) as the
-- current step, the hand-in next
local function murlocs(opts)
    local game, OXP = newGame(opts or { level = 23, map = 1437, x = 10, y = 40 })
    OXP.settings.mapQuestIcons = "on"
    local g = addGuide(OXP, {
        { { "goto", zone = "Wetlands", x = 38.18, y = 50.89 }, { "accept", quest = 288 } },
        { { "goto", zone = "Wetlands", x = 15.26, y = 39.83 },
          { "complete", quest = 279, obj = 1 }, { "mob", name = "Bluegill Murloc" },
          { "complete", quest = 279, obj = 2 }, { "mob", name = "Gobbler" } },
        { { "goto", zone = "Wetlands", x = 38.18, y = 50.89 }, { "turnin", quest = 279 } },
    }, "Mob pins test")
    OXP.Engine.Load(g.key)
    game:Accept(279, 2)
    return game, OXP
end

print("-- objective pins: the current step's open objectives, thinned like Questie's, small, capped")
do
    local game, OXP = murlocs()
    t.eq(OXP.Engine.GetPosition(), 1, "on the first step")
    t.eq(#pinsOf(OXP, "mob"), 0, "the next step's mobs aren't shown yet")
    OXP.Engine.Next()
    local mobs = pinsOf(OXP, "mob")
    t.ok(#mobs > 0 and #mobs <= OXP.Pins.MAX_MOBS, "the current step's mobs, capped: " .. #mobs)
    local raw = #(OXP.QuestDB.ObjectiveSpawnsAll(279, 1) or {}) + #(OXP.QuestDB.ObjectiveSpawnsAll(279, 2) or {})
    t.ok(#mobs <= raw, "no more pins than spawns: " .. #mobs .. " for " .. raw)
    -- Questie's filter: no two pins of one objective closer than 2 map units
    local close = 0
    for i, a in ipairs(mobs) do
        for j, b in ipairs(mobs) do
            if j > i and a.entry.obj == b.entry.obj and a.at[1] == b.at[1]
                and OXP.Pins.MapDistance(a.at[2], a.at[3], b.at[2], b.at[3]) < OXP.Pins.FILTER then
                close = close + 1
            end
        end
    end
    t.eq(close, 0, "no two pins of the same objective piled on one spot")
    local labels, tags, boss = 0, 0, 0
    for _, p in ipairs(mobs) do
        if p.label ~= "" then labels = labels + 1 end
        if p.tag ~= "" then tags = tags + 1 end
        if tostring(p.icon):find("boss", 1, true) then boss = boss + 1 end
    end
    t.eq(labels + tags + boss, 0, "no names, counts or skull badges on the map (Questie has none)")
    local gobbler = 0
    for _, p in ipairs(mobs) do if p.entry.npc == "Gobbler" then gobbler = gobbler + 1 end end
    t.ok(gobbler > 0, "Gobbler's spawns are marked like any other objective")
    -- the murlocs are done: their pins go, Gobbler stays
    game:FinishObjective(279, 1)
    game.now = game.now + 1
    mobs = pinsOf(OXP, "mob")
    local murl
    gobbler, murl = 0, 0
    for _, p in ipairs(mobs) do
        if p.entry.npc == "Bluegill Murloc" then murl = murl + 1 end
        if p.entry.npc == "Gobbler" then gobbler = gobbler + 1 end
    end
    t.eq(murl, 0, "a finished objective's mobs are hidden")
    t.ok(gobbler > 0, "the open one's mob stays")
    OXP.settings.mapMobs = false
    t.eq(#pinsOf(OXP, "mob"), 0, "objective icons off: none")
    OXP.settings.mapMobs = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- Questie's sizes, draw order, glow and continent maps")
do
    local game, OXP = murlocs()
    OXP.Engine.Next()
    local P = OXP.Pins
    t.ok(math.abs(P.IconSize("quest") - 11.52) < 0.001, "! and ?: 16 x 1.2 x 0.6 on the map (Questie's)")
    t.ok(math.abs(P.IconSize("quest", true) - 13.44) < 0.001, "and 16 x 1.2 x 0.7 on the minimap")
    t.ok(math.abs(P.IconSize("objective") - 9.6) < 0.001, "objectives: 16 x 0.6")
    t.ok(math.abs(P.IconSize("objective", true) - 11.2) < 0.001, "and 16 x 0.7 on the minimap")
    local mobs = pinsOf(OXP, "mob")
    local steps = pinsOf(OXP, "step")
    local turnin
    for _, p in ipairs(steps) do if tostring(p.icon):find("quest_", 1, true) then turnin = p end end
    t.ok(turnin and math.abs(turnin.size - 11.52) < 0.001 and math.abs(turnin.miniSize - 13.44) < 0.001,
        "the hand-in's ? is Questie's size: " .. tostring(turnin and turnin.size))
    t.ok(mobs[1] and math.abs(mobs[1].size - 9.6) < 0.001 and math.abs(mobs[1].miniSize - 11.2) < 0.001, "objective pins too")
    -- draw order: objectives under quest icons
    t.eq(mobs[1].level, 2020, "objectives at Questie's frame level")
    t.ok(mobs[1].frame.fixedLevel == true and mobs[1].frame:GetFrameLevel() == 2020, "fixed, so HBD's re-parenting keeps it")
    t.ok(turnin and turnin.level > mobs[1].level, "the ? above the objectives")
    -- glow: one colour per objective
    local colours = {}
    for _, p in ipairs(mobs) do
        t.ok(p.halo ~= nil, "every objective icon has its glow")
        colours[p.entry.obj] = colours[p.entry.obj] or p.halo
        if colours[p.entry.obj] ~= p.halo then t.ok(false, "one colour per objective") end
    end
    t.ok(colours[1] and colours[2] and colours[1] ~= colours[2], "two objectives, two colours")
    t.ok(mobs[1].frame.tex.vertex == nil or mobs[1].frame.tex.vertex[2] == 1, "the icon itself untinted (Questie's default)")
    OXP.settings.mapObjectiveColors = true
    mobs = pinsOf(OXP, "mob")
    local c = mobs[1].frame.tex.vertex
    t.ok(c and c[1] == mobs[1].halo[1] and c[2] == mobs[1].halo[2], "Colour objective icons: tinted in the glow's colour")
    OXP.settings.mapObjectiveColors = false
    OXP.settings.mapObjectiveGlow = false
    mobs = pinsOf(OXP, "mob")
    t.ok(mobs[1].halo == nil and not mobs[1].frame.halo:IsShown(), "Objective glow off: none")
    OXP.settings.mapObjectiveGlow = true
    -- shown on zone, continent and world maps; Icons on continent maps off: zone only
    mobs = pinsOf(OXP, "mob")
    t.eq(game.pins.worldIcons[mobs[1].frame][4], 3, "on continent and world maps too (HBD show flag 3)")
    OXP.settings.mapContinentIcons = false
    mobs = pinsOf(OXP, "mob")
    t.eq(game.pins.worldIcons[mobs[1].frame][4], 0, "continent maps off: the zone map only")
    OXP.settings.mapContinentIcons = true
    -- smaller on a continent (0.9) and the world (0.85), like Questie's
    game.mapInfo[1415] = { mapType = 2 }
    game.mapInfo[947] = { mapType = 1 }
    game.mapInfo[1437] = { mapType = 3 }
    openWorldMap(game, 1415)
    mobs = pinsOf(OXP, "mob")
    LibStub("HereBeDragons-Pins-2.0").worldmapProvider:RefreshAllData()
    t.eq(mobs[1].frame:GetScale(), 0.9, "on a continent map: 0.9")
    openWorldMap(game, 947)
    LibStub("HereBeDragons-Pins-2.0").worldmapProvider:RefreshAllData()
    t.eq(mobs[1].frame:GetScale(), 0.85, "on the world map: 0.85")
    openWorldMap(game, 1437)
    LibStub("HereBeDragons-Pins-2.0").worldmapProvider:RefreshAllData()
    t.eq(mobs[1].frame:GetScale(), 1, "on the zone map: full size")
    -- the size settings multiply Questie's
    OXP.settings.mapIconScale, OXP.settings.minimapIconScale = 1.5, 0.5
    mobs = pinsOf(OXP, "mob")
    t.ok(math.abs(mobs[1].size - 14.4) < 0.001 and math.abs(mobs[1].miniSize - 5.6) < 0.001, "Map / Minimap icon size")
    OXP.settings.mapIconScale, OXP.settings.minimapIconScale = 1, 1
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- minimap: every icon, floating on the rim, fading with distance like Questie's")
do
    local game, OXP = murlocs()
    OXP.Engine.Next()
    local P = OXP.Pins
    t.eq(P.MinimapAlpha(100), 1, "100 yd: full")
    t.ok(math.abs(P.MinimapAlpha(250) - 0.5) < 1e-9, "250 yd: half (fading from 200 yd)")
    t.eq(P.MinimapAlpha(300), 0, "300 yd: gone")
    t.eq(P.MinimapAlpha(0), 0.5, "right under you: half")
    t.ok(math.abs(P.MinimapAlpha(25) - 0.75) < 1e-9, "25 yd: three quarters")
    OXP.settings.minimapFadeOverPlayer = false
    t.eq(P.MinimapAlpha(0), 1, "Fade icons under you off: full")
    OXP.settings.minimapFadeOverPlayer = true
    OXP.settings.minimapFadeLevel = 50
    t.eq(P.MinimapAlpha(400), 1, "Minimap fade distance 500 yd: 400 yd is full")
    OXP.settings.minimapFadeLevel = 20
    local mobs = pinsOf(OXP, "mob")
    local all = true
    for _, p in ipairs(mobs) do
        local m = game.pins.minimapIcons[p.frame.mini]
        if not (m and m[4] == true) then all = false end
    end
    t.ok(all, "every objective is on the minimap, floating on its rim")
    -- stand far from every spawn: the objectives fade out, the step you're on stays
    game:MoveTo(1437, 95, 95)
    game:Advance(0.2)
    local shown = 0
    for _, p in ipairs(OXP.Pins.Used()) do
        if p.kind == "mob" and p.frame.mini:GetAlpha() > 0 then shown = shown + 1 end
    end
    t.eq(shown, 0, "far away: the objectives faded out")
    t.ok(not mobs[1].frame.mini:IsMouseEnabled(), "and take no mouse")
    local stepMini
    for _, p in ipairs(OXP.Pins.Used()) do if p.kind == "step" and p.glow then stepMini = p.frame.mini end end
    t.ok(stepMini and stepMini:GetAlpha() == 1, "the step you're on stays on the rim")
    -- stand on a spawn: it's there, half faded under the arrow
    local m = mobs[1]
    game:MoveTo(m.at[1], m.at[2], m.at[3])
    game:Advance(0.2)
    t.eq(m.frame.mini:GetAlpha(), 0.5, "standing on it: half")
    OXP.settings.mapMinimapIcons = false
    mobs = pinsOf(OXP, "mob")
    t.eq(game.pins.minimap, 0, "Minimap icons off: none on the minimap")
    t.ok(#mobs > 0 and game.pins.world > 0, "but still on the world map")
    OXP.settings.mapMinimapIcons = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- tooltips: Questie's layout, every pin under the mouse in one")
do
    local game, OXP = murlocs()
    OXP.Engine.Next()
    local mobs = pinsOf(OXP, "mob")
    local m = mobs[1]
    local lines = OXP.Pins.TooltipLines(m.frame, false)
    t.ok(lines[1] and lines[1].text:find(OXP.QuestDB.QuestName(279), 1, true), "the quest first: " .. tostring(lines[1] and lines[1].text))
    t.ok(lines[2] and lines[2].text:find("^   0/1 ") ~= nil, "then the objective, have/need first: " .. tostring(lines[2] and lines[2].text))
    local shift = OXP.Pins.TooltipLines(m.frame, true)
    local named = false
    for _, l in ipairs(shift) do if l.text == "   " .. m.entry.npc then named = true end end
    t.ok(named, "with Shift: who to find for it (" .. m.entry.npc .. ")")
    -- a pin of the other objective right on top: one tooltip for both
    local other
    for _, p in ipairs(mobs) do if p.entry.obj ~= m.entry.obj then other = p break end end
    other.frame.at = { m.at[1], m.at[2] + 0.2, m.at[3] }
    lines = OXP.Pins.TooltipLines(m.frame, false)
    local objs = 0
    for _, l in ipairs(lines) do if l.text:find("^   0/1 ") then objs = objs + 1 end end
    t.eq(objs, 2, "two objectives on one spot: both in the tooltip, under one quest")
    -- the hand-in's ?: the giver in green, "(Hold Shift)", the quest tagged
    local turnin
    for _, p in ipairs(pinsOf(OXP, "step")) do if tostring(p.icon):find("quest_", 1, true) then turnin = p end end
    lines = OXP.Pins.TooltipLines(turnin.frame, false)
    t.ok(lines[1].color and lines[1].color[2] == 1 and lines[1].color[1] == 0.2, "the giver's name in green")
    t.eq(lines[1].right, "(Hold Shift)", "Questie's hint")
    t.eq(lines[2].right, "(Not done yet)", "the quest tagged: not done yet")
    game:FinishObjective(279, 1)
    game:FinishObjective(279, 2)
    for _, p in ipairs(pinsOf(OXP, "step")) do if tostring(p.icon):find("quest_", 1, true) then turnin = p end end
    lines = OXP.Pins.TooltipLines(turnin.frame, false)
    t.eq(lines[2] and lines[2].right, "(Complete)", "done: (Complete)")
    -- shown with the mouse: anchored at the cursor
    local anchor
    GameTooltip.SetOwner = function(_, _, a) anchor = a end
    turnin.frame.scripts.OnEnter(turnin.frame)
    t.eq(anchor, "ANCHOR_CURSOR", "the tooltip follows the cursor")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- clicks: open the pin's map, link the quest in chat")
do
    local game, OXP = murlocs()
    OXP.Engine.Next()
    local m = pinsOf(OXP, "mob")[1]
    openWorldMap(game, 1415)
    local opened
    _G.WorldMapFrame.SetMapID = function(_, id) opened = id end
    m.frame.scripts.OnMouseUp(m.frame, "LeftButton")
    t.eq(opened, 1437, "left-click on the continent map: opens the pin's zone")
    opened = nil
    m.frame.scripts.OnMouseUp(m.frame, "RightButton")
    t.eq(opened, nil, "right-click: left to the map (zoom out)")
    local link
    _G.ChatEdit_GetActiveWindow = function() return true end
    _G.ChatEdit_InsertLink = function(l) link = l end
    m.frame.mini.scripts.OnMouseUp(m.frame.mini, "LeftButton")
    t.ok(link and link:find("|Hquest:279:", 1, true), "minimap click with the chat box open: the quest's link")
    _G.ChatEdit_GetActiveWindow, _G.ChatEdit_InsertLink = nil, nil
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- Blizzard's quest markers (CVar questPOI): off while ours show, like Questie")
do
    local game, OXP = newGame({ level = 5 })
    t.eq(GetCVar("questPOI"), "0", "our icons on: Blizzard's round ? and ... markers off")
    t.eq(OXP.char.questPOIRestore, "1", "what it was is kept")
    OXP.settings.mapHideBlizzardPOI = false
    OXP.Send("SETTINGS_CHANGED")
    t.eq(GetCVar("questPOI"), "1", "setting off: they're back as they were")
    t.eq(OXP.char.questPOIRestore, nil, "and nothing left to put back")
    OXP.settings.mapHideBlizzardPOI = true
    OXP.settings.mapQuestIcons = "off"
    OXP.Send("SETTINGS_CHANGED")
    t.eq(GetCVar("questPOI"), "1", "our quest icons off: Blizzard's stay")
    OXP.settings.mapQuestIcons = "auto"
    OXP.Send("SETTINGS_CHANGED")
    t.eq(GetCVar("questPOI"), "0", "on again: hidden")
    -- the player turned them off themselves: we never turn them on
    OXP.Pins.SyncQuestPOI()
    OXP.char.questPOIRestore = nil
    OXP.settings.mapHideBlizzardPOI = false
    OXP.Send("SETTINGS_CHANGED")
    t.eq(GetCVar("questPOI"), "0", "off by the player: left off")
    OXP.settings.mapHideBlizzardPOI = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))

    -- with Questie loaded, Questie decides (its icon theme sets it)
    local game2 = FakeWoW.New(ROOT, { level = 5 })
    _G.QuestieLoader = {}
    local OXP2 = game2:LoadAddon()
    game2:Login()
    t.eq(GetCVar("questPOI"), "1", "Questie loaded: left to Questie")
    t.eq(OXP2.char.questPOIRestore, nil, "nothing kept")
    _G.QuestieLoader = nil

    -- a client without the markers: nothing to do, no errors
    local game3 = FakeWoW.New(ROOT, { level = 5, noQuestPOI = true })
    game3:LoadAddon()
    game3:Login()
    t.eq(GetCVar("questPOI"), nil, "no questPOI CVar: untouched")
    t.eq(#game3.errors, 0, "no Lua errors: " .. table.concat(game3.errors, " | "))

    -- markers off makes the client open the world map at log in: closed again
    local saved = game:SavedVariables()
    saved.OpenXPCharDB.questPOIRestore = "1" -- we turned them off last time
    local game4 = FakeWoW.New(ROOT, { level = 5 }, saved)
    game4.cvars.questPOI = "0"
    game4:LoadAddon()
    _G.WorldMapFrame = game4.Widget("Frame")
    _G.WorldMapFrame:Show()
    game4:Login()
    t.ok(not _G.WorldMapFrame:IsShown(), "the world map opened by the client at log in is closed")
    t.eq(#game4.errors, 0, "no Lua errors: " .. table.concat(game4.errors, " | "))
end

return t.fails
