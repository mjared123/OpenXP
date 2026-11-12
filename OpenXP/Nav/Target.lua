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

-- Title for a step's spot: its first text goal, else its first goal with text.
local function StepTitle(step)
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
    for _, pos in ipairs(Engine.GetActive()) do
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
    local go = OXP.PathHints.go or Target.override
    local base = go or Target.Real()
    if not base then
        current = nil
        return nil
    end
    local trav = not go and OXP.Travel.ArrowTarget(base)
    local area = not go and not trav and base.step and OXP.Areas.Target(base.step, base.title)
    local aim = trav or area or base
    local via = not (area and area.inside) and OXP.PathHints.ForArrow(aim)
    if via and trav then via.title = trav.title end
    current = via or aim
    current.real = base
    return current
end
Target.Update = OXP.Perf.Wrap("arrow target", Target.Update)
