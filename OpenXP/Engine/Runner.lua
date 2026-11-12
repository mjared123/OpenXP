-- The step engine: runs one guide for the current character.
--
-- A loaded guide keeps only the steps and goals whose `only` filter matches
-- the player. The current step is the first one not finished. A step is
-- finished when none of its goals is "todo" (see Goals.lua), when the player
-- skipped it, or, for a `completewith = "next"` step, when the step after it
-- is finished. Steps after the current one that are already done are passed
-- over when the guide reaches them.
--
-- Messages sent (for the UI):
--   GUIDE_LOADED (guide)      a guide was loaded
--   STEP_CHANGED (pos)        the current step moved
--   STEPS_UPDATED             a goal on a shown step changed state
--   GUIDE_FINISHED (guide)    the last step is done
--   NO_GUIDE                  at login, the character has no guide yet
local _, OXP = ...

local Engine = {}
OXP.Engine = Engine

local Filters, Goals, Registry, World = OXP.Filters, OXP.Goals, OXP.Registry, OXP.World

local run          -- the loaded guide: { guide, steps, pos, held, save }
local lastSignature

------------------------------------------------------------------------
-- Building a run
------------------------------------------------------------------------

local function buildSteps(guide)
    local steps = {}
    for index, data in ipairs(guide.steps) do
        if Filters.Matches(data.only) then
            local goals = {}
            for _, goal in ipairs(data) do
                if Filters.Matches(goal.only) then goals[#goals + 1] = goal end
            end
            steps[#steps + 1] = {
                index = index,                 -- position in the guide data
                data = data,
                goals = goals,
                completewith = data.completewith == "next",
                marks = {},                    -- one-off events seen while shown
            }
        end
    end
    return steps
end

local function saveFor(guide)
    local all = OXP.char.guides
    local save = all[guide.key]
    if not save then
        save = { step = 1, skipped = {} }
        all[guide.key] = save
    end
    save.skipped = save.skipped or {}
    return save
end

------------------------------------------------------------------------
-- Step state
------------------------------------------------------------------------

local function ownGoalsDone(step)
    for _, goal in ipairs(step.goals) do
        if Goals.State(goal, step.marks) == "todo" then return false end
    end
    return true
end

local function stepDone(pos)
    -- Iterative so a long chain of completewith steps can't overflow.
    local steps = run.steps
    while true do
        local step = steps[pos]
        if not step then return false end
        if run.save.skipped[step.index] or ownGoalsDone(step) then return true end
        if not step.completewith then return false end
        pos = pos + 1
    end
end

--- Positions of the steps shown now: the current one, plus the ones after
--- it while the shown step is a completewith step.
local function activePositions()
    local out = {}
    if not run then return out end
    local pos = run.pos
    while run.steps[pos] do
        out[#out + 1] = pos
        if not run.steps[pos].completewith then break end
        pos = pos + 1
    end
    return out
end

local function signature()
    local parts = { run.guide.key, run.pos }
    for _, pos in ipairs(activePositions()) do
        local step = run.steps[pos]
        for _, goal in ipairs(step.goals) do
            parts[#parts + 1] = Goals.State(goal, step.marks)
        end
    end
    return table.concat(parts, ",")
end

------------------------------------------------------------------------
-- Moving through the guide
------------------------------------------------------------------------

local function savePosition()
    local step = run.steps[run.pos]
    run.save.step = step and step.index or (#run.guide.steps + 1)
end

local function finish()
    local guide = run.guide
    OXP.Send("GUIDE_FINISHED", guide)
    local nextGuide = Registry.Next(guide)
    if nextGuide and OXP.settings.autoNextGuide then
        Engine.Load(nextGuide)
    end
end

--- Re-check the shown steps and move past finished ones.
function Engine.Refresh()
    if not run then return end
    local before = run.pos
    while run.pos <= #run.steps do
        if run.held == run.pos then break end
        if not stepDone(run.pos) then break end
        run.pos = run.pos + 1
    end
    if run.pos ~= before then
        run.held = nil
        savePosition()
        OXP.Send("STEP_CHANGED", run.pos)
    end
    if run.pos > #run.steps then
        if not run.finished then
            run.finished = true
            finish()
        end
        return
    end
    local sig = signature()
    if sig ~= lastSignature then
        lastSignature = sig
        OXP.Send("STEPS_UPDATED")
    end
end

local function refreshSoon()
    OXP.Soon("ENGINE_REFRESH", Engine.Refresh)
end

--- Load a guide (a guide table or its key). With `stepIndex` (a step number
--- in the guide data) start there; otherwise carry on from where this
--- character left it. Returns true when the guide was loaded.
function Engine.Load(guideOrKey, stepIndex)
    local guide = type(guideOrKey) == "table" and guideOrKey or Registry.Get(guideOrKey)
    if not guide then return false end
    local save = saveFor(guide)
    if stepIndex then
        save.step = stepIndex
        save.skipped = {}
    end
    local steps = buildSteps(guide)
    local pos = #steps + 1
    for i, step in ipairs(steps) do
        if step.index >= save.step then
            pos = i
            break
        end
    end
    run = { guide = guide, steps = steps, pos = pos, save = save }
    lastSignature = nil
    OXP.char.currentGuide = guide.key
    OXP.Send("GUIDE_LOADED", guide)
    Engine.Refresh()
    return true
end

--- Stop following any guide.
function Engine.Unload()
    run = nil
    lastSignature = nil
    OXP.char.currentGuide = nil
    OXP.Send("GUIDE_LOADED", nil)
end

--- Show step `pos` (a position in Engine.GetSteps()) and stay there until
--- the player moves on, even if it is already done. Un-skips it.
function Engine.GoTo(pos)
    if not run or not run.steps[pos] then return false end
    run.pos = pos
    run.held = pos
    run.finished = nil
    run.save.skipped[run.steps[pos].index] = nil
    savePosition()
    OXP.Send("STEP_CHANGED", pos)
    lastSignature = nil
    Engine.Refresh()
    return true
end

--- Move on from the current step, marking it skipped if it isn't done.
function Engine.Next()
    if not run or run.pos > #run.steps then return false end
    if not stepDone(run.pos) then
        run.save.skipped[run.steps[run.pos].index] = true
    end
    run.held = nil
    run.pos = run.pos + 1
    savePosition()
    OXP.Send("STEP_CHANGED", run.pos)
    Engine.Refresh()
    return true
end

--- Go back one step (it stays shown until the player moves on).
function Engine.Back()
    if not run or run.pos <= 1 then return false end
    return Engine.GoTo(run.pos - 1)
end

------------------------------------------------------------------------
-- Questions the UI asks
------------------------------------------------------------------------

function Engine.GetGuide()
    return run and run.guide
end

--- The loaded guide's steps for this player: { {index, data, goals, completewith}, ... }
function Engine.GetSteps()
    return run and run.steps or {}
end

--- Position of the current step in GetSteps() (past the end when finished).
function Engine.GetPosition()
    return run and run.pos
end

--- Positions of the steps shown right now (see activePositions).
function Engine.GetActive()
    return activePositions()
end

--- "done", "todo", "skip" or "info" for a goal of the step at `pos`.
function Engine.GoalState(pos, goal)
    local step = run and run.steps[pos]
    return Goals.State(goal, step and step.marks)
end

--- "done", "skipped", "current" or "todo" for the step at `pos`.
function Engine.StepState(pos)
    if not run or not run.steps[pos] then return nil end
    if pos < run.pos then
        return run.save.skipped[run.steps[pos].index] and "skipped" or "done"
    elseif pos == run.pos then
        return "current"
    end
    return stepDone(pos) and "done" or "todo"
end

--- Steps finished and steps in total for a guide (default: the loaded one),
--- counting only the steps this player sees.
function Engine.GetProgress(guide)
    guide = guide or (run and run.guide)
    if not guide then return 0, 0 end
    if run and guide == run.guide then
        return math.min(run.pos - 1, #run.steps), #run.steps
    end
    local save = OXP.char.guides[guide.key]
    local reached = save and save.step or 1
    local done, total = 0, 0
    for index, data in ipairs(guide.steps) do
        if Filters.Matches(data.only) then
            total = total + 1
            if index < reached then done = done + 1 end
        end
    end
    return done, total
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------

-- One-off events only count for the goals shown when they happen.
local function markShown(kind, accept)
    if not run then return end
    for _, pos in ipairs(activePositions()) do
        local step = run.steps[pos]
        for _, goal in ipairs(step.goals) do
            if goal[1] == kind and Goals.State(goal, step.marks) == "todo" and accept(goal) then
                step.marks[goal] = true
            end
        end
    end
end

OXP.Listen("FLIGHTPATH_DISCOVERED", function()
    markShown("fp", function(goal)
        World.LearnFlightPath(goal.name)
        return true
    end)
    refreshSoon()
end)

OXP.Listen("HEARTH_CHANGED", function()
    -- With a known town, the bind location decides; otherwise any new bind
    -- while the step is shown counts.
    markShown("home", function(goal) return Goals.HearthTarget(goal) == nil end)
    refreshSoon()
end)

for _, message in ipairs({ "QUESTS_CHANGED", "PLAYER_LEVEL", "ZONE_CHANGED", "BAGS_CHANGED", "FLIGHTPATHS_CHANGED" }) do
    OXP.Listen(message, refreshSoon)
end

OXP.OnReady(function()
    local key = OXP.char.currentGuide
    if key and Registry.Get(key) then
        Engine.Load(key)
    else
        OXP.Send("NO_GUIDE")
    end
end)
