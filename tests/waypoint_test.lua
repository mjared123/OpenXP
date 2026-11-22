-- The arrow and the map's route line never send you back to a waypoint you
-- already passed or whose goals are done (Nav/Target.lua). A goto belongs
-- to the goals after it, up to the next goto or reach: it is dropped once
-- they're all done or skipped. A goto with no goal of its own (a waypoint on
-- the way) is dropped once you've been at it or are past it. A goto whose
-- goal is still to do stays, even when you stand next to it.
--
-- Reported in game: Dun Morogh "Grund and Gozwin". Grund Drokda's quest was
-- accepted inside Anvilmar more than 12 yards from the step's first goto,
-- and once outside the line and the arrow still led back into the inn.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("waypoint")

-- The fake world is 1000 yards across every map: 1% of a map is 10 yards.
local YD = 0.1

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local function at(real, x, y)
    return real ~= nil and real.x ~= nil and math.abs(real.x - x) < 0.001 and math.abs(real.y - y) < 0.001
end

local function where(real)
    if not real then return "nothing" end
    return ("%s:%.2f,%.2f"):format(tostring(real.map), real.x or -1, real.y or -1)
end

------------------------------------------------------------------------
print("-- Dun Morogh, Grund and Gozwin: accepted inside Anvilmar, then out of the inn")
do
    local game, OXP = newGame({ faction = "Alliance", race = "Dwarf", class = "WARRIOR", level = 4,
                                map = 1426, x = 28.55, y = 67.64 })
    local guide, index
    for _, g in ipairs(OXP.Registry.All()) do
        if g.name == "1-14 Dun Morogh" and (g.source or ""):find("dwarf", 1, true) then
            for i, data in ipairs(g.steps) do
                if data[1] and data[1].text == "Grund and Gozwin" then guide, index = g, i end
            end
        end
    end
    t.ok(guide ~= nil, "the real Dun Morogh guide has the Grund and Gozwin step")
    if guide then
        OXP.Engine.Load(guide.key, index)
        game:Advance(1)
        local step = OXP.Engine.GetSteps()[OXP.Engine.GetPosition()]
        t.eq(step and step.index, index, "on the Grund and Gozwin step")
        local Real = OXP.Target.Real

        -- Grund is inside, 15 yards from the step's goto (the arrow passes a
        -- waypoint within 12)
        game:MoveTo(1426, 28.6, 67.6 + 15 * YD)
        game:Advance(1)
        t.ok(at(Real(), 28.6, 67.6), "before accepting: the arrow is on Grund (" .. where(Real()) .. ")")
        game:MoveTo(1426, 28.6, 67.6)
        game:Advance(1)
        t.ok(at(Real(), 28.6, 67.6), "standing at Grund, not accepted yet: the arrow stays on him (" .. where(Real()) .. ")")
        game:MoveTo(1426, 28.6, 67.6 + 15 * YD)
        game:Advance(1)
        step.marks.waypoint, step.marks.passed = nil, nil -- as after a /reload
        game:Accept(97277, 2)
        game:Advance(1)
        t.eq(OXP.Engine.GoalState(OXP.Engine.GetPosition(), step.goals[4]), "done", "the accept is checked")
        t.ok(at(Real(), 27.27, 62.86), "accepted: the arrow goes on to Gozwin's camp (" .. where(Real()) .. ")")
        -- out of the inn the way SoupEngine walks it (OpenXP_Nav: 28.60,67.60>27.27,62.86),
        -- from its first corner outdoors (the fake world is smaller than Dun Morogh)
        for _, p in ipairs({ { 28.72, 69.76 }, { 27.5, 69.56 }, { 26.48, 68.41 }, { 26.47, 66.91 } }) do
            game:MoveTo(1426, p[1], p[2])
            game:Advance(1)
            local real = Real()
            t.ok(at(real, 27.27, 62.86), ("outside at %.2f,%.2f: the arrow is on the camp (%s)"):format(p[1], p[2], where(real)))
            local cur = OXP.Target.Update()
            t.ok(cur and cur.real == real, "the arrow's spot is the guide's spot")
            local stops = OXP.MapDraw.WorkOutUpcoming()
            local first = stops[1]
            t.ok(first and first[1] == 1426 and math.abs(first[2] - 27.27) < 0.001 and math.abs(first[3] - 62.86) < 0.001,
                ("the route line's first stop is the camp (%s)"):format(first and ("%s:%.2f,%.2f"):format(first[1], first[2], first[3]) or "none"))
        end
        game:MoveTo(1426, 27.27, 62.86)
        game:FinishObjective(97277, 1)
        game:Advance(1)
        t.ok(at(Real(), 27.37, 62.86), "log found: on to the prowler (" .. where(Real()) .. ")")
        game:FinishObjective(97277, 2)
        game:Advance(1)
        t.ok(at(Real(), 28.6, 67.4), "both done: back to Grund to turn in, a goal still to do (" .. where(Real()) .. ")")
        game:MoveTo(1426, 28.6, 67.4 + 15 * YD)
        game:TurnIn(97277)
        game:Advance(1)
        t.ok(at(Real(), 26.93, 80.03), "turned in: on to the troll cave (" .. where(Real()) .. ")")
    end
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

print("-- the same with SoupEngine's baked walks (OpenXP_Nav): the arrow and line follow the walk to the camp")
do
    local game, OXP = newGame({ faction = "Alliance", race = "Dwarf", class = "WARRIOR", level = 4,
                                map = 1426, x = 28.6, y = 67.6 + 15 * YD })
    local NAV = { paths = {}, spots = {}, targets = {}, graveyards = {} }
    assert(loadfile(ROOT .. "/OpenXP_Nav/Paths-Alliance.lua"))("OpenXP_Nav", NAV)
    OXP.WalkPaths.Use(NAV)
    local guide, index
    for _, g in ipairs(OXP.Registry.All()) do
        if g.name == "1-14 Dun Morogh" and (g.source or ""):find("dwarf", 1, true) then
            for i, data in ipairs(g.steps) do
                if data[1] and data[1].text == "Grund and Gozwin" then guide, index = g, i end
            end
        end
    end
    OXP.Engine.Load(guide.key, index)
    game:Advance(1)
    game:Accept(97277, 2)
    game:Advance(1)
    local innX, innY = OXP.Places.ToWorld(1426, 28.6, 67.6)
    local lastLeft = math.huge
    for _, p in ipairs({ { 28.72, 69.76 }, { 28.57, 69.91 }, { 27.5, 69.56 }, { 26.48, 68.41 }, { 26.47, 66.91 }, { 27, 64.95 } }) do
        game:MoveTo(1426, p[1], p[2])
        game:Advance(1)
        local cur = OXP.Target.Update()
        local real = cur and cur.real
        local label = ("at %.2f,%.2f"):format(p[1], p[2])
        t.ok(at(real, 27.27, 62.86), label .. ": the arrow is on its way to the camp (" .. where(real) .. ")")
        -- along the walk, never more of it left than a moment ago (or the camp itself, just ahead)
        t.ok(cur and (cur == real or (cur.walkPath and cur.left and cur.left <= lastLeft)),
            label .. ": on the baked walk, no more of it left than before (" .. tostring(cur and cur.left) .. ")")
        lastLeft = cur and cur.left or lastLeft
        local wx, wy, inst = OXP.Places.Player()
        local line = OXP.WalkPaths.RouteFrom(real, wx, wy, inst) or {}
        t.ok(#line > 0, label .. ": the route line follows the walk")
        for _, q in ipairs(line) do
            local qx, qy = OXP.Places.ToWorld(1426, q[1], q[2])
            t.ok(OXP.Places.Distance(qx, qy, innX, innY) > 5,
                ("%s: no corner of the line back at the inn (%.2f,%.2f)"):format(label, q[1], q[2]))
        end
    end
    OXP.WalkPaths.Use(nil)
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
-- Test guides for the waypoint rules on their own.
local counter = 0
local function addGuide(OXP, steps)
    counter = counter + 1
    local g = { name = "1-5 Waypoint test " .. counter, group = "Test", steps = steps }
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

print("-- a waypoint on the way is dropped once you're past it, never pulling you back")
do
    local game, OXP = newGame({ level = 5, map = 1429, x = 40, y = 50 })
    addGuide(OXP, {
        { { "text", text = "Through the gate" },
          { "goto", x = 45, y = 50, zone = "1429" },
          { "goto", x = 50, y = 50, zone = "1429" },
          { "accept", quest = 901, text = "Accept A" } },
    })
    game:Advance(1)
    t.ok(at(OXP.Target.Real(), 45, 50), "first the gate")
    game:MoveTo(1429, 46, 52) -- 22 yards off it, but past it
    game:Advance(1)
    t.ok(at(OXP.Target.Real(), 50, 50), "past the gate (not within 12 yards): on to the quest giver")
    game:MoveTo(1429, 44, 50) -- stepped back a little: still nearer the quest giver than the gate is? no
    game:Advance(1)
    t.ok(at(OXP.Target.Real(), 50, 50), "a waypoint once passed stays passed")
end

print("-- a goto whose goals are done is dropped wherever you are; one still to do stays")
do
    local game, OXP = newGame({ level = 5, map = 1429, x = 40, y = 50 })
    addGuide(OXP, {
        { { "text", text = "Two quests" },
          { "goto", x = 45, y = 50, zone = "1429" },
          { "accept", quest = 911, text = "Accept A" },
          { "goto", x = 60, y = 50, zone = "1429" },
          { "accept", quest = 912, text = "Accept B" },
          { "goto", x = 70, y = 50, zone = "1429" },
          { "accept", quest = 913, text = "Accept C" } },
    })
    game:Advance(1)
    game:MoveTo(1429, 45, 50)
    game:Advance(1)
    t.ok(at(OXP.Target.Real(), 45, 50), "at A's giver, not accepted: the arrow stays (Here)")
    game:Accept(912, 0) -- B first, from far away
    game:Advance(1)
    t.ok(at(OXP.Target.Real(), 45, 50), "B done out of order: A still to do, so A")
    game:Accept(911, 0)
    game:Advance(1)
    t.ok(at(OXP.Target.Real(), 70, 50), "A and B done: straight on to C")
end

print("-- out of a building into another zone: the indoor waypoint is behind you")
do
    local game, OXP = newGame({ level = 5, map = 1429, x = 30, y = 50 })
    addGuide(OXP, {
        { { "text", text = "Out the back" },
          { "goto", x = 41, y = 50, zone = "1429" },
          { "goto", x = 50, y = 50, zone = "1431" },
          { "accept", quest = 921, text = "Accept A" } },
    })
    game:Advance(1)
    t.ok(at(OXP.Target.Real(), 41, 50), "first the door")
    game:MoveTo(1431, 30, 50) -- out in the next zone, still far from the quest giver
    game:Advance(1)
    t.ok(at(OXP.Target.Real(), 50, 50), "in the zone the next point is in: the door is behind you")
end

------------------------------------------------------------------------
-- Every leveling guide, both factions: walk each step's waypoints in order,
-- doing its goals, and look where the arrow points all along the way.
print("-- audit: every leveling step, the arrow never points at a waypoint behind you")

local PLAYERS = {
    { "Alliance", "Human", "PALADIN" }, { "Alliance", "Dwarf", "SHAMAN" }, { "Alliance", "NightElf", "DRUID" },
    { "Alliance", "Gnome", "WARLOCK" }, { "Alliance", "Skyborne", "HUNTER" },
    { "Horde", "Orc", "WARLOCK" }, { "Horde", "Scourge", "PRIEST" }, { "Horde", "Tauren", "DRUID" },
    { "Horde", "Troll", "SHAMAN" }, { "Horde", "Skyborne", "MAGE" },
}

local function objectiveCounts(OXP)
    local counts = {}
    for _, g in ipairs(OXP.Registry.All()) do
        for _, step in ipairs(g.steps) do
            for _, goal in ipairs(step) do
                if goal[1] == "complete" then counts[goal.quest] = math.max(counts[goal.quest] or 0, goal.obj) end
            end
        end
    end
    return counts
end

local binds = 0
local function play(game, OXP, goal, objectives)
    local kind, q = goal[1], goal.quest
    local function have()
        if not OXP.Quests.IsOnQuest(q) and not OXP.Quests.IsTurnedIn(q) then game:Accept(q, objectives[q] or 0) end
    end
    if kind == "accept" then game:Accept(q, objectives[q] or 0)
    elseif kind == "complete" then have() game:FinishObjective(q, goal.obj)
    elseif kind == "turnin" then have() game:TurnIn(q)
    elseif kind == "xp" then game:SetLevel(goal.level)
    elseif kind == "zone" then game:EnterZone(goal.name)
    elseif kind == "fp" then game:OpenTaxi({ goal.name .. ", Somewhere" })
    elseif kind == "home" then binds = binds + 1 game:Bind(OXP.Goals.HearthTarget(goal) or ("Inn " .. binds))
    elseif kind == "collect" then game:AddItem(goal.item, goal.count)
    elseif kind == "finish" then have() for i = 1, objectives[q] or 0 do game:FinishObjective(q, i) end
    elseif kind == "reach" then game:MoveTo(OXP.Places.MapID(goal.zone), goal.x, goal.y) game:Advance(1)
    elseif kind == "fly" then
        if goal.wx then game:MoveToWorld(goal.wx, goal.wy, goal.inst) else game:EnterZone(goal.name) end
        game:Advance(1)
    elseif kind == "train" then game:Fire("TRAINER_SHOW") game:Flush()
    end
end

-- The step's waypoints: { goal, spot, owned = { blocking goals after it } }
local function entriesOf(OXP, step)
    local out, cur = {}, nil
    for _, g in ipairs(step.goals) do
        if g[1] == "goto" or g[1] == "reach" then
            local s = OXP.Places.Spot(g)
            cur = s and { goal = g, spot = s, owned = {} } or nil
            if cur then
                out[#out + 1] = cur
                if g[1] == "reach" then cur.owned[1] = g end
            end
        elseif cur and OXP.Goals.Blocks(g[1]) then
            cur.owned[#cur.owned + 1] = g
        end
    end
    return out
end

local function ownedTodo(OXP, e, step)
    for _, g in ipairs(e.owned) do
        if OXP.Goals.State(g, step.marks) == "todo" then return true end
    end
    return false
end

local audit = { steps = 0, multi = 0, looks = 0, violations = 0, chains = 0, stays = 0, early = 0 }
local shown = 0

-- Where the arrow points when the player walks to entry j (or has just
-- finished entry j's goals: `after`): a waypoint at or after j, or one whose
-- goals are still to do. Anything else is behind the player.
local function look(OXP, step, pos, entries, j, after, who, what)
    local real = OXP.Target.Real()
    if not real or real.step ~= step or real.pos ~= pos then return end -- an "as you go" step or a turn-in nearby
    audit.looks = audit.looks + 1
    local from = after and j + 1 or j
    local okay = false
    for k, e in ipairs(entries) do
        if e.spot.wx == real.wx and e.spot.wy == real.wy and e.spot.instance == real.instance then
            if k >= from or ownedTodo(OXP, e, step) then okay = true break end
            -- the very last waypoint, all done: nothing ahead to point at
            if from > #entries and k == #entries then okay = true break end
        end
    end
    if not okay then
        audit.violations = audit.violations + 1
        if shown < 12 then
            shown = shown + 1
            print(("   behind you: %s, %s step %d (%s), %s waypoint %d: arrow on %s"):format(who,
                OXP.Engine.GetGuide().name, step.index, OXP.Target.StepTitle(step) or "?", what, j, where(real)))
        end
    end
end

-- Arrived by waypoint j with its goals still to do: the arrow stays on it
-- (or on an earlier one whose goals are still to do).
local function stays(OXP, step, pos, entries, j, who)
    local real = OXP.Target.Real()
    if not real or real.step ~= step or real.pos ~= pos then return end
    audit.stays = audit.stays + 1
    for k = 1, j do
        local e = entries[k]
        if e.spot.wx == real.wx and e.spot.wy == real.wy and e.spot.instance == real.instance
            and (k == j or ownedTodo(OXP, e, step)) then
            return
        end
    end
    audit.early = audit.early + 1
    if shown < 12 then
        shown = shown + 1
        print(("   moved on too early: %s, %s step %d (%s), waypoint %d still to do: arrow on %s"):format(who,
            OXP.Engine.GetGuide().name, step.index, OXP.Target.StepTitle(step) or "?", j, where(real)))
    end
end

local function walkTo(game, OXP, map, x, y, step, pos, entries, j, who)
    local wx, wy = game.pos.wx, game.pos.wy
    local fromMap, fx, fy = game.pos.map, game.pos.x, game.pos.y
    if wx or fromMap ~= map then
        -- after a flight or in another zone: straight there
        game:MoveTo(map, x, y)
        look(OXP, step, pos, entries, j, false, who, "into")
        return
    end
    for _, f in ipairs({ 0.25, 0.5, 0.75, 1 }) do
        game:MoveTo(map, fx + (x - fx) * f, fy + (y - fy) * f)
        look(OXP, step, pos, entries, j, false, who, "walking to")
    end
end

local function auditChain(faction, race, class)
    local who = race .. " " .. class
    local game, OXP = newGame({ faction = faction, race = race, class = class, level = 1 })
    local E = OXP.Engine
    local objectives = objectiveCounts(OXP)
    local leveling = OXP.Registry.ForPlayer(nil, "OpenXP Leveling (" .. faction .. ")")
    local isNext, first = {}, nil
    for _, g in ipairs(leveling) do if g.next then isNext[g.next] = true end end
    for _, g in ipairs(leveling) do if not isNext[g.name] then first = first or g end end
    if not first then t.ok(false, who .. ": no leveling chain") return end
    E.Load(first)
    audit.chains = audit.chains + 1
    local guard = 0
    while true do
        local pos, steps = E.GetPosition(), E.GetSteps()
        if pos > #steps then break end
        local guide = E.GetGuide()
        local step = steps[pos]
        local entries = entriesOf(OXP, step)
        audit.steps = audit.steps + 1
        if #entries > 1 then audit.multi = audit.multi + 1 end
        local j = 0
        for _, goal in ipairs(step.goals) do
            if E.GetGuide() ~= guide or E.GetPosition() ~= pos then break end
            local k = goal[1]
            if (k == "goto" or k == "reach") and entries[j + 1] and entries[j + 1].goal == goal then
                j = j + 1
                local e = entries[j]
                local s = e.spot
                if k == "reach" or #e.owned == 0 then
                    walkTo(game, OXP, s.map, s.x, s.y, step, pos, entries, j, who)
                else
                    -- someone to talk to or something to do here: done from 15
                    -- yards off the spot (inside, behind a counter, ...)
                    walkTo(game, OXP, s.map, s.x + 15 * YD, s.y, step, pos, entries, j, who)
                end
                game:Advance(1)
                if #e.owned > 0 and ownedTodo(OXP, e, step) and E.GetGuide() == guide and E.GetPosition() == pos then
                    stays(OXP, step, pos, entries, j, who)
                end
            elseif E.GoalState(pos, goal) == "todo" then
                play(game, OXP, goal, objectives)
                -- the last of this waypoint's goals just done: look again
                local e = entries[j]
                if e and #e.owned > 0 and e.owned[#e.owned] == goal and not ownedTodo(OXP, e, step)
                    and E.GetGuide() == guide and E.GetPosition() == pos then
                    look(OXP, step, pos, entries, j, true, who, "done at")
                end
            end
        end
        if E.GetGuide() == guide and E.GetPosition() == pos then
            for _, goal in ipairs(step.goals) do
                if E.GoalState(pos, goal) == "todo" then play(game, OXP, goal, objectives) end
            end
            if E.GetGuide() == guide and E.GetPosition() == pos then E.Next() end
        end
        guard = guard + 1
        if guard > 20000 then t.ok(false, who .. ": runaway") break end
    end
    t.eq(#game.errors, 0, who .. ": Lua errors: " .. table.concat(game.errors, " | "))
end

for _, p in ipairs(PLAYERS) do auditChain(p[1], p[2], p[3]) end
print(("   %d chains, %d steps checked, %d with several waypoints, %d arrow checks, %d pointing behind you")
    :format(audit.chains, audit.steps, audit.multi, audit.looks, audit.violations))
print(("   %d arrivals at a waypoint with its goals still to do, %d where the arrow had already moved on")
    :format(audit.stays, audit.early))
t.ok(audit.steps > 1000, "the audit walked the leveling guides")
t.eq(audit.violations, 0, "the arrow never points at a waypoint behind you")
t.eq(audit.early, 0, "the arrow stays on a waypoint whose goals are still to do")

return t.fails
