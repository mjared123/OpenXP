-- What the arrow points at.
--
-- The guide's own spot for the shown steps (their goto goals, in order) is
-- the "real" target. On top of that, in this order:
--   /oxp path to ...            a place you asked for (Nav/PathHints.lua)
--   a quest chain walk          the card's "Do the chain" (UI/Card.lua)
--   another zone                the next leg of the trip (Nav/Travel.lua)
--   a kill/loot area            "Here" inside it, else its edge (Nav/Areas.lua)
--   caves, ridges, mountains    stepping stones (Nav/PathHints.lua, Nav/Terrain.lua)
local _, OXP = ...

local Target = {}
OXP.Target = Target

local Places, Engine = OXP.Places, OXP.Engine

local REACHED = 12 -- yards: a waypoint of a step with several is passed

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

local real = {}

--- The guide's spot for the shown steps: {wx, wy, instance, map, title, step,
--- pos}, or nil when the shown steps have no spot.
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
        local spots = {}
        for _, g in ipairs(step.goals) do
            if g[1] == "goto" or g[1] == "reach" then
                local s = Places.Spot(g)
                if s then spots[#spots + 1] = s end
            end
        end
        if #spots > 0 then
            -- several waypoints: walk them in order
            local i = step.marks.waypoint or 1
            local px, py, inst = Places.Player()
            while i < #spots and px and spots[i].instance == inst
                and Places.Distance(px, py, spots[i].wx, spots[i].wy) <= REACHED do
                i = i + 1
            end
            step.marks.waypoint = i
            local s = spots[i]
            real.wx, real.wy, real.instance, real.map = s.wx, s.wy, s.instance, s.map
            real.title, real.step, real.pos = StepTitle(step), step, pos
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
    local via = not (area and area.inside) and OXP.PathHints.ForArrow(aim)
    if via and trav then via.title = trav.title end
    current = via or aim
    current.real = base
    return current
end
Target.Update = OXP.Perf.Wrap("arrow target", Target.Update)
