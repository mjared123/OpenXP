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

-- The map a flight to this flight master lands on (Data/Flights.lua and
-- Data/Travel.lua), or false when it isn't known.
local function flightZone(name)
    local nodes = OXP.flightData and OXP.flightData.nodes
    local travel = OXP.travelData or {}
    for _, n in pairs(nodes or {}) do
        if World.SameFlightPoint(n.name, name) then
            local first, second = n.name:match("^([^,]+),%s*(.+)$")
            return (travel.fpCity or {})[first or n.name] or (travel.fpZone or {})[second or ""] or false
        end
    end
    return false
end

-- Mark each "reach" checkpoint with how else it counts (Engine/Goals.lua):
-- `entry` when it leads into another zone (the place before it is in a
-- different zone, or the guide starts with "Into <that zone>"): done once
-- you're out in that zone; `past` when the next place is in another zone
-- (a dock, tram, portal or border): done once you're there. Worked out on
-- the steps your character gets, so class-only steps don't get in the way.
--
-- Only a way in you walk through is an `entry`: being in its zone says
-- nothing when a flight landed you in that zone, nor for a
-- place you leave the zone from (a dock, portal or border: `past`), where
-- you stand in its zone before you get to it. In game, landing in Darkshore
-- passed the Auberdine boat step at once (the step before it, the
-- Astranaar flight master, is in Ashenvale).
local function markEntries(steps)
    -- every place the guide sends you, in order; `flew`: the map a flight
    -- between the place before it and this one lands on (false: not known)
    local spots = {}
    local flew
    for si, step in ipairs(steps) do
        for _, goal in ipairs(step.goals) do
            local k = goal[1]
            if k == "fly" then
                flew = flightZone(goal.name)
            elseif (k == "goto" or k == "reach" or k == "area") and goal.zone then
                local zone = OXP.Places.MapID(goal.zone)
                if zone then
                    spots[#spots + 1] = { goal = goal, zone = zone, step = si, flew = flew }
                    flew = nil
                end
            end
        end
    end
    -- the places just before and after a step (class-only goals share one)
    local function Before(i)
        local j = i - 1
        while spots[j] and spots[j].step == spots[i].step do j = j - 1 end
        return spots[j], j
    end
    -- a flight since spot j landed you in spot i's zone (or somewhere unknown)
    local function FlewInto(j, i)
        for k = math.max(j + 1, 1), i do
            local f = spots[k].flew
            if f == false or f == spots[i].zone then return true end
        end
        return false
    end
    local function After(i)
        local j = i + 1
        while spots[j] and spots[j].step == spots[i].step do j = j + 1 end
        return spots[j]
    end
    for i, spot in ipairs(spots) do
        local goal = spot.goal
        if goal[1] == "reach" then
            local before, j = Before(i)
            local after = After(i)
            goal.entry, goal.past = nil, nil
            local text = OXP.Text.Strip(goal.text or ""):lower()
            -- a dock, tram, portal or border on the way to the next zone:
            -- done once you're in that zone
            if after and after.zone ~= spot.zone then goal.past = after.zone end
            -- the way into a new zone (a tunnel, a pass, a road in): done
            -- once you're out in that zone
            -- ("Into Mulgore" says so itself, even with the Barrens next)
            local into = text:match("^into (.+)")
            local zoneName = into and OXP.Places.ZoneName(spot.zone)
            local function key(s) return (OXP.Util.PlaceKey(s) or ""):gsub("^the ", "") end
            local named = zoneName and key(into) == key(zoneName)
            if not FlewInto(j, i) and ((named and (not before or before.zone ~= spot.zone))
                or (not goal.past and before and before.zone ~= spot.zone)) then
                goal.entry = true
            end
        end
    end
end

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
                -- "as you go": never holds the guide up; shown beside the
                -- current step until done or until step `untilIndex` is passed
                along = data.along and true or nil,
                untilIndex = data["until"],
                when = data.when,
                marks = {},                    -- one-off events seen while shown
            }
        end
    end
    markEntries(steps)
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
    save.status = save.status or {}
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
        if run.save.skipped[step.index] or step.along or not Goals.WhenHolds(step.when)
            or ownGoalsDone(step) then
            return true
        end
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
    -- "as you go" steps you've passed that are still open
    local here = run.steps[run.pos]
    local hereIndex = here and here.index or math.huge
    for p = 1, run.pos - 1 do
        local step = run.steps[p]
        if step.along and not run.save.skipped[step.index] and (step.untilIndex or 0) >= hereIndex
            and Goals.WhenHolds(step.when) and not ownGoalsDone(step) then
            out[#out + 1] = p
        end
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
    if run.pos > (run.furthest or 0) then run.furthest = run.pos end
end

local function finish()
    local guide = run.guide
    OXP.Send("GUIDE_FINISHED", guide)
    local nextGuide = Registry.Next(guide)
    if nextGuide and OXP.settings.autoNextGuide then
        Engine.Load(nextGuide)
    end
end

-- After a log in or /reload the character's saved step stays shown, even
-- when its goals look done: the game sends quest data a moment after login
-- (quests can look missing or unfinished, then done), and a goal can look
-- done from where you happen to stand. Until RESTORE_SETTLE seconds after
-- the last loading screen or quest log update (at most RESTORE_LIMIT
-- seconds after login) whatever the goals look like is taken as the
-- starting point; after that, the first change you make live (a goal of a
-- shown step changing) lets the guide move on as usual.
local RESTORE_SETTLE, RESTORE_LIMIT = 3, 20
Engine.RESTORE_SETTLE = RESTORE_SETTLE

local function now() return GetTime and GetTime() or 0 end

local function settleLonger()
    local r = run and run.restored
    if r and now() < r.settleAt then
        r.settleAt = math.min(now() + RESTORE_SETTLE, r.limit)
    end
end
OXP.On("PLAYER_ENTERING_WORLD", settleLonger)
OXP.On("QUEST_LOG_UPDATE", settleLonger)

-- True while the restored step is to stay where it is.
local function restoreHolds()
    local r = run.restored
    if not r then return false end
    if run.pos ~= r.pos then
        run.restored = nil
        return false
    end
    local sig = signature()
    if not r.sig or now() < r.settleAt then
        r.sig = sig
        return true
    end
    if sig ~= r.sig then
        run.restored = nil
        return false
    end
    return true
end

--- Re-check the shown steps and move past finished ones.
function Engine.Refresh()
    if not run then return end
    local before = run.pos
    while run.pos <= #run.steps do
        if run.held == run.pos then break end
        if run.restored and restoreHolds() then break end
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
--- character left it. With `restore` (logging in), that step stays shown
--- until something changes live (see restoreHolds). Returns true when the
--- guide was loaded.
function Engine.Load(guideOrKey, stepIndex, restore)
    local guide = type(guideOrKey) == "table" and guideOrKey or Registry.Get(guideOrKey)
    if not guide then return false end
    local save = saveFor(guide)
    if stepIndex then
        -- starting over from a chosen step: no skipped or jumped marks left
        -- from the last time through
        save.step = stepIndex
        save.skipped = {}
        save.status = {}
    end
    local steps = buildSteps(guide)
    local pos = #steps + 1
    for i, step in ipairs(steps) do
        if step.index >= save.step then
            pos = i
            break
        end
    end
    run = { guide = guide, steps = steps, pos = pos, save = save, furthest = pos }
    if restore and not stepIndex and pos <= #steps then
        local t = now()
        run.restored = { pos = pos, settleAt = t + RESTORE_SETTLE, limit = t + RESTORE_LIMIT }
    end
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

-- Leaving the current step without doing it. The step you went back to
-- gets back the mark it had before (skipped, chain missed); any other gets
-- `mark` ("jumped": passed over by going ahead, shown as skipped).
local function leaveUndone(mark)
    local step = run.steps[run.pos]
    if not step or stepDone(run.pos) then return end
    local was = run.revisit
    if was and was.pos == run.pos and (was.skipped or was.status) then
        run.save.skipped[step.index] = was.skipped
        run.save.status[step.index] = was.status
    elseif mark == "skipped" then
        run.save.skipped[step.index] = true
    else
        run.save.status[step.index] = mark
    end
end

--- Show step `pos` (a position in Engine.GetSteps()). Un-skips it.
--- A step that is already done when you go to it (looking back) stays shown
--- until you move on; a step still to do moves on by itself once you do it,
--- like any other. With noHold, never held.
--- Going ahead marks nothing done: the step you leave and the steps past the
--- furthest one reached that you jump over are marked "jumped" (shown as
--- skipped) unless they are done. Going back changes no marks.
function Engine.GoTo(pos, noHold)
    if not run or not run.steps[pos] then return false end
    if pos > run.pos and run.steps[run.pos] then
        leaveUndone("jumped")
        local from = math.max(run.pos + 1, run.furthest or 0)
        for p = from, pos - 1 do
            local step = run.steps[p]
            if not stepDone(p) and not run.save.status[step.index] then
                run.save.status[step.index] = "jumped"
            end
        end
    end
    local index = run.steps[pos].index
    run.revisit = { pos = pos, skipped = run.save.skipped[index], status = run.save.status[index] }
    run.pos = pos
    run.finished = nil
    run.restored = nil
    run.save.skipped[index] = nil
    run.save.status[index] = nil
    run.held = (not noHold and stepDone(pos)) and pos or nil
    savePosition()
    OXP.Send("STEP_CHANGED", pos)
    lastSignature = nil
    Engine.Refresh()
    return true
end

--- Move on from the current step, marking it skipped if it isn't done.
function Engine.Next()
    if not run or run.pos > #run.steps then return false end
    leaveUndone("skipped")
    if not stepDone(run.pos) then
        run.save.skipped[run.steps[run.pos].index] = true
    end
    run.held = nil
    run.restored = nil
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

--- Back to the furthest step reached before looking back. Returns the
--- position, or nil when you're already there.
function Engine.Resume()
    if not run or not run.furthest or run.furthest <= run.pos then return nil end
    local target = math.min(run.furthest, #run.steps)
    run.held = nil
    Engine.GoTo(target, true)
    return target
end

--- The furthest step reached in the loaded guide (a position).
function Engine.GetFurthest()
    return run and run.furthest
end

--- Is the current step held (picked by hand)?
function Engine.IsHeld()
    return run ~= nil and run.held == run.pos
end

--- Put this character at step `index` (a guide data index) of a guide, with
--- steps in `skipped` (data index -> true) marked skipped and `status` (data
--- index -> "chain" or "skipped") recorded for the card. Used by smart start.
function Engine.Place(guideOrKey, index, skipped, status)
    local guide = type(guideOrKey) == "table" and guideOrKey or Registry.Get(guideOrKey)
    if not guide then return false end
    local save = saveFor(guide)
    save.step = index or 1
    save.skipped = {}
    save.status = {}
    for i in pairs(skipped or {}) do save.skipped[i] = true end
    for i, s in pairs(status or {}) do save.status[i] = s end
    return Engine.Load(guide)
end

--- Mark a step (a guide data index) skipped, with an optional status
--- ("chain": its quest chain was missed).
function Engine.MarkSkipped(index, status)
    if not run then return end
    run.save.skipped[index] = true
    run.save.status[index] = status
    refreshSoon()
end

--- Position in GetSteps() of a guide data index (or the next shown step after it).
function Engine.PositionOf(index)
    if not run then return nil end
    for pos, step in ipairs(run.steps) do
        if step.index >= index then return pos end
    end
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

--- "done", "skipped", "chain" (skipped: its quest chain was missed),
--- "current" or "todo" for the step at `pos`. A step jumped over (Engine.GoTo)
--- is "skipped" until it is done.
function Engine.StepState(pos)
    if not run or not run.steps[pos] then return nil end
    local index = run.steps[pos].index
    if pos == run.pos then return "current" end
    local status = run.save.status[index]
    if status == "chain" then return "chain" end
    if pos < run.pos then
        if ownGoalsDone(run.steps[pos]) then return "done" end
        if run.save.skipped[index] then return "skipped" end
        if status == "jumped" and not stepDone(pos) then return "skipped" end
        return "done"
    end
    if run.save.skipped[index] then return "skipped" end
    if stepDone(pos) then return "done" end
    return status == "jumped" and "skipped" or "todo"
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

-- Taking off: a "fly to" step on screen is done now, not when you land, so
-- the card, arrow and route line move on to what's next at once. The way
-- to the flight master (its "reach" checkpoint) counts as done with it.
-- A flight whose destination isn't known counts for the fly step shown.
function Engine.TakeOff(dest)
    if not run then return end
    local changed = false
    for _, pos in ipairs(activePositions()) do
        local step = run.steps[pos]
        for _, goal in ipairs(step.goals) do
            if goal[1] == "fly" and not step.marks[goal]
                and (dest == nil or World.SameFlightPoint(dest, goal.name)) then
                step.marks[goal] = true
                for _, other in ipairs(step.goals) do
                    if other == goal then break end
                    if other[1] == "reach" then step.marks[other] = true end
                end
                changed = true
            end
        end
    end
    if changed then
        lastSignature = nil
        Engine.Refresh()
        OXP.Send("ARROW_CHANGED")
    end
end

OXP.Listen("TAXI_STARTED", function(_, dest) Engine.TakeOff(dest) end)

OXP.Listen("TRAINED", function()
    markShown("train", function() return true end)
    refreshSoon()
end)

for _, message in ipairs({ "QUESTS_CHANGED", "PLAYER_LEVEL", "ZONE_CHANGED", "BAGS_CHANGED", "FLIGHTPATHS_CHANGED" }) do
    OXP.Listen(message, refreshSoon)
end

-- Goals that depend on where you stand ("be here", "fly to") are looked at
-- again twice a second while one is shown; nothing else costs anything.
-- Everything else is looked at again every 2 seconds too, as a safety net:
-- the game doesn't always send an event when a quest's state settles (a
-- turn-in can show as done a moment after its event), and a step that is
-- done must never wait for an unrelated event to move on.
local positional = CreateFrame("Frame")
local wait, safety = 0, 0
positional:SetScript("OnUpdate", function(_, elapsed)
    wait = wait + elapsed
    safety = safety + elapsed
    if wait < 0.5 or not run then return end
    wait = 0
    if safety >= 2 then
        safety = 0
        OXP.Quests.Invalidate()
        Engine.Refresh()
        return
    end
    for _, pos in ipairs(activePositions()) do
        for _, goal in ipairs(run.steps[pos].goals) do
            if Goals.IsPositional(goal[1]) then
                Engine.Refresh()
                return
            end
        end
    end
end)

OXP.OnReady(function()
    local key = OXP.char.currentGuide
    if key and Registry.Get(key) then
        -- back on the step you were on, whatever the goals look like yet
        Engine.Load(key, nil, true)
    else
        OXP.Send("NO_GUIDE")
    end
end)
