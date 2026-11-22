-- What the arrow points at.
--
-- The guide's own spot for the shown steps (their goto goals, in order) is
-- the "real" target. On top of that, in this order:
--   /oxp path to ...            a place you asked for (Nav/PathHints.lua)
--   a quest chain walk          the card's "Do the chain" (UI/Card.lua)
--   another zone                the next leg of the trip (Nav/Travel.lua)
--   a kill/loot area            "Here" inside it, else its edge (Nav/Areas.lua)
--   a baked walk                corners of SoupEngine's walk (Nav/WalkPaths.lua, needs OpenXP_Nav)
--   caves, ridges, mountains    stepping stones (Nav/PathHints.lua, Nav/Terrain.lua)
local _, OXP = ...

local Target = {}
OXP.Target = Target

local Places, Engine = OXP.Places, OXP.Engine

local REACHED = 12 -- yards: a waypoint of a step with several is passed

-- SoupEngine test build: the arrow only follows SoupEngine's baked walks
-- (Nav/WalkPaths.lua) and otherwise points straight at the step's spot. No
-- trips, kill areas, path hints or terrain stepping stones. Set to false
-- for the old arrow.
local BAKED_ONLY = true
Target.BAKED_ONLY = BAKED_ONLY
if BAKED_ONLY then
    -- the old arrow's own paths: /oxp path and /oxp wall do nothing here
    OXP.RemoveCommand("path")
    OXP.RemoveCommand("wall")
end

-- Title for a step's spot: while one of several objectives is left, what
-- to do for it ("Kill Gobbler for Gobbler's Head"); else the step's first
-- text goal, else its first goal with text.
local function StepTitle(step)
    local objectives, left = 0, nil
    for _, g in ipairs(step.goals) do
        if g[1] == "complete" and g.quest and g.obj then
            objectives = objectives + 1
            if not left and OXP.Goals.State(g, step.marks) == "todo" then left = g end
        end
    end
    if left and objectives > 1 then
        local action = OXP.QuestDB.ObjectiveAction(left.quest, left.obj)
        if action then return action end
    end
    for _, g in ipairs(step.goals) do
        if g[1] == "text" and g.text then return OXP.Text.Strip(g.text) end
    end
    for _, g in ipairs(step.goals) do
        if g.text then return OXP.Text.Strip(g.text) end
    end
end
Target.StepTitle = StepTitle

-- A step's waypoints, in order: { {goal, spot, owned = {goal, ...}}, ... }.
-- A goto or reach belongs to the goals that block the step after it, up to
-- the next goto or reach ("goto, accept, target" is where you accept); a
-- reach is also its own goal. A goto with no such goal is a waypoint on the
-- way (a door, a tunnel). Worked out once per step.
local function Waypoints(step)
    local list = step.waypoints
    if list then return list end
    list = {}
    local cur
    for _, g in ipairs(step.goals) do
        local k = g[1]
        if k == "goto" or k == "reach" then
            local s = Places.Spot(g)
            cur = s and { goal = g, spot = s, owned = {} } or nil
            if cur then
                list[#list + 1] = cur
                if k == "reach" then cur.owned[1] = g end
            end
        elseif cur and OXP.Goals.Blocks(k) then
            cur.owned[#cur.owned + 1] = g
        end
    end
    step.waypoints = list
    return list
end
Target.Waypoints = Waypoints

-- Is every goal this waypoint belongs to done (or skipped)? nil for a
-- waypoint with no goal of its own.
local function GoalsDone(w, marks)
    if #w.owned == 0 then return nil end
    for _, g in ipairs(w.owned) do
        if OXP.Goals.State(g, marks) == "todo" then return false end
    end
    return true
end

-- Are you past waypoint w on the way to the next one still to go to (n):
-- on the continent n is on while w isn't, or nearer n than w is?
local function Beyond(w, n, px, py, inst)
    if not (n and px) then return false end
    local a, b = w.spot, n.spot
    if b.instance ~= inst then return false end
    if a.instance ~= inst then return true end
    return Places.Distance(px, py, b.wx, b.wy) < Places.Distance(a.wx, a.wy, b.wx, b.wy)
end

--- The waypoint of `step` to go to now: (waypoint, index), or nil when the
--- step has none. One whose goals are all done or skipped is passed wherever
--- you are; one whose goal is still to do stays, even when you're next to
--- it. A waypoint with no goal of its own is passed once you've been within
--- REACHED yards of it or are past it (nearer the next waypoint still to go
--- to than it is), and stays passed. When every waypoint is passed, the last one.
--- With `live` false (a step ahead, not shown yet) only the goals count.
function Target.StepWaypoint(step, live)
    local list = Waypoints(step)
    if #list == 0 then return nil end
    local passed = live and step.marks.passed
    if live and not passed then
        passed = {}
        step.marks.passed = passed
    end
    local px, py, inst
    if live then px, py, inst = Places.Player() end
    for i, w in ipairs(list) do
        local done = GoalsDone(w, step.marks)
        if done == nil and live and not passed[w.goal] then
            local s = w.spot
            -- the next waypoint still to go to after this one
            local n
            for k = i + 1, #list do
                if GoalsDone(list[k], step.marks) ~= true then n = list[k] break end
            end
            if px and ((s.instance == inst and Places.Distance(px, py, s.wx, s.wy) <= REACHED)
                or Beyond(w, n, px, py, inst)) then
                passed[w.goal] = true
            end
        end
        if done == false or (done == nil and not (live and passed[w.goal])) then
            return w, i
        end
    end
    return list[#list], #list
end

local real = {}

--- The guide's spot for the shown steps: {wx, wy, instance, map, title, step,
--- pos, goal}, or nil when the shown steps have no spot.
function Target.Real()
    local order = Engine.GetActive()
    -- a later step's turn-in you're standing by comes first (UI/Card.lua)
    local here = OXP.Card and OXP.Card.here
    -- (only until the turn-ins are in: then back to your step)
    if here and not here.handed and Engine.GetSteps()[here.pos] then
        local o = { here.pos }
        for _, pos in ipairs(order) do o[#o + 1] = pos end
        order = o
    end
    for _, pos in ipairs(order) do
        local step = Engine.GetSteps()[pos]
        -- several waypoints: the first one not behind you (Target.StepWaypoint)
        local w, i = Target.StepWaypoint(step, true)
        if w then
            step.marks.waypoint = i
            local s = w.spot
            real.wx, real.wy, real.instance, real.map = s.wx, s.wy, s.instance, s.map
            real.x, real.y = s.x, s.y -- map %: finds the baked walk (Nav/WalkPaths.lua)
            real.title, real.step, real.pos, real.goal = StepTitle(step), step, pos, w.goal
            return real
        end
    end
    return nil
end

--- Set by the card while walking a quest chain: a spot to use instead of
--- the guide's ({wx, wy, instance, map, title}), or nil.
function Target.SetOverride(t)
    Target.override = t
    OXP.Send("ARROW_CHANGED")
end

local current

--- The point the arrow shows now (see the top of this file), or nil.
function Target.Current() return current end

--- Work the arrow's point out again. Returns it (or nil).
function Target.Update()
    if BAKED_ONLY then
        local base = Target.override or Target.Real()
        if not base or base.none then
            current = nil
            return nil
        end
        -- a kill/loot step once you're there: "In the area", or straight at
        -- the named mob or chest it needs (Nav/Areas.lua)
        local focus = not Target.override and base.step and OXP.Areas.Focus(base.step, base.title)
        if focus and focus.inside then
            current = focus
            current.real = base
            return current
        end
        local aim = focus or base
        current = OXP.WalkPaths.ForArrow(aim) or aim
        current.real = base
        -- where "Here" is: the pinpointed mob or chest, else the spot
        current.focus = focus or nil
        return current
    end
    local hint = OXP.PathHints.go
    local base = hint or Target.override or Target.Real()
    -- a chain walk with no spot for its quest: no arrow, rather than the
    -- guide's spot for a step the card isn't showing
    if not base or base.none then
        current = nil
        return nil
    end
    -- a chain quest in another zone gets the trip planned like a guide step
    local trav = not hint and OXP.Travel.ArrowTarget(base)
    local area = not hint and not trav and base.step and OXP.Areas.Target(base.step, base.title)
    local aim = trav or area or base
    -- a baked walk to the spot (OpenXP_Nav) first, else path hints and terrain
    local via = not (area and area.inside) and (OXP.WalkPaths.ForArrow(aim) or OXP.PathHints.ForArrow(aim))
    if via and trav then via.title = trav.title end
    current = via or aim
    current.real = base
    return current
end
Target.Update = OXP.Perf.Wrap("arrow target", Target.Update)
