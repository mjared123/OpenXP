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

-- The whole quest ready to turn in (all objectives).
Goals.Define("finish", {
    fields = { "quest" },
    state = function(g)
        if Quests.IsTurnedIn(g.quest) then return "done" end
        if not Quests.IsOnQuest(g.quest) then return g.optional and "skip" or "todo" end
        return done(Quests.IsComplete(g.quest))
    end,
})

-- Being at a spot (within `radius` yards, default 15). Once reached, it
-- stays done for the step.
local function near(g, yards)
    local s = OXP.Places.Spot(g)
    if not s then return false end
    local px, py, inst = OXP.Places.Player()
    return px ~= nil and inst == s.instance and OXP.Places.Distance(px, py, s.wx, s.wy) <= yards
end

Goals.Define("reach", {
    fields = { "zone", "x", "y" },
    position = true,
    state = function(g, marks)
        if marks[g] then return "done" end
        if near(g, g.radius or 15) then
            marks[g] = true
            return "done"
        end
        return "todo"
    end,
})

-- Training at your class trainer: done once you open a trainer's window at
-- your current level (while the step is shown, or before it at this level).
Goals.Define("train", {
    fields = {},
    state = function(g, marks)
        local at = OXP.char and OXP.char.trainedAt
        return done(marks[g] or (at ~= nil and at >= (OXP.Player.level or 1)))
    end,
})

-- A flight to a flight master: done once you land near it (wx, wy, inst are
-- its world spot).
Goals.Define("fly", {
    fields = { "name" },
    position = true,
    state = function(g, marks)
        if marks[g] then return "done" end
        if not g.wx then return "todo" end
        local px, py, inst = OXP.Places.Player()
        if px and inst == g.inst and OXP.Places.Distance(px, py, g.wx, g.wy) <= 250 then
            marks[g] = true
            return "done"
        end
        return "todo"
    end,
})

--- Does any goal of these kinds depend on where you stand (so the engine
--- has to look again as you move)?
function Goals.IsPositional(kind)
    return kinds[kind] ~= nil and kinds[kind].position == true
end

------------------------------------------------------------------------
-- Step conditions ("when"): a step whose conditions don't hold is passed
-- over. Each condition is { kind, field = value, neg = true to invert }.
------------------------------------------------------------------------

local function HasSkill(name)
    if not (GetNumSkillLines and GetSkillLineInfo) then return false end
    for i = 1, GetNumSkillLines() do
        local skill = GetSkillLineInfo(i)
        if skill == name then return true end
    end
    return false
end

local CONDITIONS = {
    turnedin = function(c) return Quests.IsTurnedIn(c.quest) end,
    onquest = function(c)
        for _, q in ipairs(c.quests or { c.quest }) do
            if Quests.IsOnQuest(q) then return true end
        end
        return false
    end,
    complete = function(c) return Quests.IsComplete(c.quest) or Quests.IsTurnedIn(c.quest) end,
    money = function(c) return (GetMoney and GetMoney() or 0) >= (c.n or 0) end,
    skill = function(c) return HasSkill(c.name) end,
    zone = function(c) return World.InZone(c.name) end,
    -- a group (elite) quest: only when you're in a group, or already on it
    group = function(c) return (IsInGroup and IsInGroup()) or Quests.IsOnQuest(c.quest) or Quests.IsTurnedIn(c.quest) end,
    level = function(c) return (OXP.Player.level or 1) >= (c.n or 0) end,
    has = function(c) return World.ItemCount(c.item) >= (c.n or 1) end,
}
Goals.CONDITIONS = CONDITIONS

--- True when every condition of a step's `when` list holds (or it has none).
function Goals.WhenHolds(when)
    if not when then return true end
    for _, c in ipairs(when) do
        local test = CONDITIONS[c[1]]
        local ok = test and test(c) or false
        if c.neg then ok = not ok end
        if not ok then return false end
    end
    return true
end

-- Hints: shown, never block (no state function).
Goals.Define("text", { fields = { "text" } })
Goals.Define("goto", { fields = { "zone", "x", "y" } })
Goals.Define("area", { fields = { "zone", "points" } })
Goals.Define("target", { fields = { "name" } })
Goals.Define("mob", { fields = { "name" } })
Goals.Define("item", { fields = { "item" } }) -- an item to use or keep (shown with its name)

OXP.On("TRAINER_SHOW", function()
    if OXP.char then OXP.char.trainedAt = OXP.Player.level or 1 end
    OXP.Send("TRAINED")
end)
