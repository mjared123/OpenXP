-- Goal kinds: what each line of a guide step means and when it is done.
--
-- A goal is { kind, field = value, ... } (see tools/convert_guides.py).
-- Goals.State(goal, marks) returns one of
--   "done"     finished
--   "todo"     still to do; the step waits for it
--   "skip"     doesn't apply to this player right now (an optional quest
--              they don't have); the step doesn't wait for it
--   "info"     a hint (text, waypoint, mob, target); never blocks a step
-- `marks` is the step's memory of one-off events (a flight path learned or
-- the hearthstone set while the step was shown), keyed by the goal table.
local _, OXP = ...

local Goals = {}
OXP.Goals = Goals

local Quests, World = OXP.Quests, OXP.World

local kinds = {}

--- Add or replace a goal kind. def.state(goal, marks) -> state;
--- def.fields lists the fields a goal of this kind must have.
function Goals.Define(kind, def)
    kinds[kind] = def
end

function Goals.IsKnown(kind)
    return kinds[kind] ~= nil
end

function Goals.Kind(goal)
    return goal[1]
end

function Goals.Fields(kind)
    return kinds[kind] and kinds[kind].fields or {}
end

function Goals.State(goal, marks)
    local def = kinds[goal[1]]
    if not def or not def.state then return "info" end
    return def.state(goal, marks or {})
end

--- Does this goal kind ever block a step?
function Goals.Blocks(kind)
    return kinds[kind] ~= nil and kinds[kind].state ~= nil
end

local function done(b) return b and "done" or "todo" end

-- A quest the guide marks optional ("-" in 1.x) only counts while the player
-- has it (or has turned it in).
local function haveQuest(q)
    return Quests.IsOnQuest(q) or Quests.IsTurnedIn(q)
end

Goals.Define("accept", {
    fields = { "quest" },
    state = function(g)
        return done(haveQuest(g.quest))
    end,
})

Goals.Define("complete", {
    fields = { "quest", "obj" },
    state = function(g)
        if Quests.IsTurnedIn(g.quest) then return "done" end
        if not Quests.IsOnQuest(g.quest) then
            return g.optional and "skip" or "todo"
        end
        return done(Quests.IsObjectiveDone(g.quest, g.obj))
    end,
})

Goals.Define("turnin", {
    fields = { "quest" },
    state = function(g)
        if Quests.IsTurnedIn(g.quest) then return "done" end
        if g.optional and not Quests.IsOnQuest(g.quest) then return "skip" end
        return "todo"
    end,
})

Goals.Define("collect", {
    fields = { "item", "count" },
    state = function(g)
        return done(World.ItemCount(g.item) >= (g.count or 1))
    end,
})

Goals.Define("xp", {
    fields = { "level" },
    state = function(g)
        return done((OXP.Player.level or 1) >= g.level)
    end,
})

Goals.Define("zone", {
    fields = { "name" },
    state = function(g)
        return done(World.InZone(g.name))
    end,
})

Goals.Define("fp", {
    fields = { "name" },
    state = function(g, marks)
        return done(marks[g] or World.KnowsFlightPath(g.name))
    end,
})

--- The town a "home" goal sets the hearthstone to: its name, or the end of
--- "Set your Hearthstone to Astranaar".
function Goals.HearthTarget(g)
    return g.name or (g.text and g.text:match("[Hh]earthstone to (.-)%.?$"))
end

Goals.Define("home", {
    fields = {},
    state = function(g, marks)
        return done(marks[g] or World.IsHearthAt(Goals.HearthTarget(g)))
    end,
})

-- Hints: shown, never block (no state function).
Goals.Define("text", { fields = { "text" } })
Goals.Define("goto", { fields = { "zone", "x", "y" } })
Goals.Define("area", { fields = { "zone", "points" } })
Goals.Define("target", { fields = { "name" } })
Goals.Define("mob", { fields = { "name" } })
