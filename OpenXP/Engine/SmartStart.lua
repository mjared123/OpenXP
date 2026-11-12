-- Smart start: where a character belongs in the leveling guides, from their
-- level, zone, quest log and turned-in quests, so players who install
-- OpenXP mid-leveling (or skipped a section) land on the right step.
--
-- It also finds quest chains the player can't start because an earlier
-- quest was skipped, and skips those steps instead of sending the player to
-- a quest giver who won't offer the quest.
--
-- Prerequisites come from Questie (when installed) and from OpenXP's own
-- guides: when a step turns in quest A and then accepts B at the same giver,
-- and every guide that accepts B does it right after turning in A, B is
-- treated as needing A.
local _, OXP = ...

local SS = {}
OXP.SmartStart = SS

local Filters, Registry = OXP.Filters, OXP.Registry
local QUEST_KINDS = { accept = true, turnin = true, complete = true }

-- The game, through one table, so tests can stand in for it.
SS.api = {
    IsTurnedIn = function(id) return OXP.Quests.IsTurnedIn(id) end,
    IsOnQuest = function(id) return OXP.Quests.IsOnQuest(id) end,
    IsComplete = function(id) return OXP.Quests.IsComplete(id) end,
    PlayerLevel = function() return OXP.Player.level or UnitLevel("player") end,
    ZoneName = function() return GetRealZoneText and GetRealZoneText() or "" end,
    QuestLevel = function(id)
        local q = OXP.QuestDB.Get("Quest", id)
        local l = q and (q.questLevel or q.level)
        if type(l) == "number" and l > 0 then return l end
    end,
    GreenRange = function()
        if GetQuestGreenRange then return GetQuestGreenRange() end
    end,
    NextInChain = function(id)
        local q = OXP.QuestDB.Get("Quest", id)
        local n = q and q.nextQuestInChain
        if type(n) == "number" and n > 0 then return n end
    end,
    QuestRow = function(id) return OXP.QuestDB.Get("Quest", id) end,
}

------------------------------------------------------------------------
-- Guide helpers
------------------------------------------------------------------------

function SS.LevelRange(guide)
    return guide.minLevel, guide.maxLevel
end

--- For each step this player sees (by data index), its quest goals: { {kind, id}, ... }.
function SS.QuestSteps(guide)
    local out = {}
    for i, step in ipairs(guide.steps or {}) do
        if Filters.Matches(step.only) then
            local quests
            for _, g in ipairs(step) do
                if QUEST_KINDS[g[1]] and g.quest and Filters.Matches(g.only) then
                    quests = quests or {}
                    quests[#quests + 1] = { tag = g[1], id = g.quest, optional = g.optional }
                end
            end
            out[i] = quests
        end
    end
    return out
end

--- The quest goal no longer needs doing.
function SS.IsSatisfied(tag, id)
    local api = SS.api
    if api.IsTurnedIn(id) then return true end
    if tag == "accept" then
        return api.IsOnQuest(id) and true or false
    elseif tag == "complete" then
        return api.IsOnQuest(id) and api.IsComplete(id) and true or false
    end
    return false
end

function SS.GuideAccepts(steps, id)
    for _, quests in pairs(steps) do
        for _, q in ipairs(quests) do
            if q.tag == "accept" and q.id == id then return true end
        end
    end
    return false
end

------------------------------------------------------------------------
-- Prerequisites
------------------------------------------------------------------------

--- {[questB] = {questA}} from turn-in -> accept pairs in the guides.
function SS.InferPrerequisites(guides)
    local seen, after = {}, {}
    for _, guide in ipairs(guides) do
        for _, step in ipairs(guide.steps or {}) do
            local turnedIn = {}
            for _, g in ipairs(step) do
                local id = g.quest
                if id and g[1] == "turnin" then
                    -- an optional turn-in means the next quest comes either way
                    if not g.optional then turnedIn[#turnedIn + 1] = id end
                elseif id and g[1] == "accept" then
                    seen[id] = (seen[id] or 0) + 1
                    for _, a in ipairs(turnedIn) do
                        if a ~= id then
                            after[id] = after[id] or {}
                            after[id][a] = (after[id][a] or 0) + 1
                        end
                    end
                end
            end
        end
    end
    local prereqs = {}
    for b, from in pairs(after) do
        -- trust a pair only when B is never accepted without A just before it,
        -- and only one quest was turned in there
        local only, count = nil, 0
        for a, n in pairs(from) do
            if n == seen[b] then
                count = count + 1
                only = a
            end
        end
        if count == 1 then prereqs[b] = { only } end
    end
    return prereqs
end

--- Quest ids this quest needs that the player hasn't done or picked up.
function SS.MissingPrerequisites(id, prereqs)
    local api = SS.api
    local needed = {}
    local function need(q)
        if not api.IsTurnedIn(q) and not api.IsOnQuest(q) then needed[#needed + 1] = q end
    end
    local quest = api.QuestRow and api.QuestRow(id)
    if quest then
        for _, q in pairs(quest.preQuestGroup or {}) do need(q) end
        if quest.preQuestSingle and #quest.preQuestSingle > 0 then
            local anyDone = false
            for _, q in pairs(quest.preQuestSingle) do
                if api.IsTurnedIn(q) or api.IsOnQuest(q) then anyDone = true end
            end
            if not anyDone then need(quest.preQuestSingle[1]) end
        end
    end
    for _, q in ipairs(prereqs and prereqs[id] or {}) do need(q) end
    return needed
end

------------------------------------------------------------------------
-- Picking a guide
------------------------------------------------------------------------

--- Score one guide for the player. Higher is better; nil means "don't pick".
function SS.ScoreGuide(guide, level, zone)
    local lo, hi = SS.LevelRange(guide)
    if not lo then return nil end
    -- a little outside the range is fine when you're in the middle of it
    local inRange = level >= lo - 1 and level <= hi
    local nearRange = level >= lo - 3 and level <= hi + 2
    if not nearRange then return nil end

    local total, done, started = 0, 0, 0
    local counted = {}
    for _, quests in pairs(SS.QuestSteps(guide)) do
        for _, q in ipairs(quests) do
            if not counted[q.id] then
                counted[q.id] = true
                total = total + 1
                if SS.api.IsTurnedIn(q.id) then
                    done = done + 1
                elseif SS.api.IsOnQuest(q.id) then
                    started = started + 1
                end
            end
        end
    end
    if total == 0 or done == total then return nil end
    if not inRange and started == 0 then return nil end

    local score = 0
    -- resume a section you're in the middle of: its quests are in your log
    if started > 0 then score = score + 100 + started * 5 end
    -- the section whose level range fits best
    score = score + 20 - math.abs(level - lo) * 2
    -- a small nudge toward the zone you're standing in
    local name = guide.name:lower()
    if zone and zone ~= "" and name:find(zone:lower(), 1, true) then score = score + 10 end
    return score, { total = total, done = done, started = started }
end

function SS.PickGuide(guides, level, zone)
    local best, bestScore, bestInfo
    for _, guide in ipairs(guides) do
        local score, info = SS.ScoreGuide(guide, level, zone)
        if score and (not bestScore or score > bestScore) then
            best, bestScore, bestInfo = guide, score, info
        end
    end
    return best, bestInfo
end

------------------------------------------------------------------------
-- Gray quests
------------------------------------------------------------------------

-- How many levels below you a quest can be before it turns gray.
function SS.GreenRange(level)
    local r = SS.api.GreenRange and SS.api.GreenRange()
    if r then return r end
    if level <= 5 then return 5 end
    if level <= 39 then return 5 + math.floor(level / 10) end
    return 1 + math.floor(level / 5)
end

function SS.IsGray(id, level)
    local ql = SS.api.QuestLevel and SS.api.QuestLevel(id)
    if not ql or not level then return false end
    return level - ql > SS.GreenRange(level)
end

-- Quests smart start may skip for being gray: not in your log, gray, not
-- class quests, and every later quest in their chain is gray too (a chain
-- ending in a green quest is kept).
function SS.GrayQuests(guide, steps, prereqs, level)
    local api = SS.api
    local inGuide, classQuest = {}, {}
    for i, quests in pairs(steps) do
        for _, q in ipairs(quests) do
            inGuide[q.id] = true
            if guide.steps[i] and guide.steps[i].class then classQuest[q.id] = true end
        end
    end
    local after = {}
    local function link(a, b)
        after[a] = after[a] or {}
        after[a][b] = true
    end
    for id in pairs(inGuide) do
        local n = api.NextInChain and api.NextInChain(id)
        if n then link(id, n) end
        for _, p in ipairs(prereqs and prereqs[id] or {}) do link(p, id) end
        local quest = api.QuestRow and api.QuestRow(id)
        if quest then
            for _, p in pairs(quest.preQuestGroup or {}) do link(p, id) end
            for _, p in pairs(quest.preQuestSingle or {}) do link(p, id) end
        end
    end
    local memo = {}
    local function chainGray(id, depth)
        if memo[id] ~= nil then return memo[id] end
        if depth > 30 or classQuest[id] then return false end
        if not api.IsTurnedIn(id) and not SS.IsGray(id, level) then
            memo[id] = false
            return false
        end
        memo[id] = true -- guards loops
        for b in pairs(after[id] or {}) do
            if not chainGray(b, depth + 1) then
                memo[id] = false
                return false
            end
        end
        return true
    end
    local gray = {}
    for id in pairs(inGuide) do
        if not classQuest[id] and not api.IsTurnedIn(id) and not api.IsOnQuest(id)
            and SS.IsGray(id, level) and chainGray(id, 0) then
            gray[id] = true
        end
    end
    return gray
end

------------------------------------------------------------------------
-- Where in the guide
------------------------------------------------------------------------

-- A finished step counts as where you are only when, of it and the quest
-- steps just before it, at most GUARD_OPEN are still open and at least
-- GUARD_QUESTS different quests are done: one quest done out of order
-- doesn't jump you past a whole zone.
SS.GUARD_STEPS = 6
SS.GUARD_OPEN = 2
SS.GUARD_QUESTS = 3

--- For a guide: the step to start on (data index), steps to skip because
--- their chain is broken, the blocked quests, and steps skipped for gray
--- quests. `level` turns on the gray check.
function SS.PlanSteps(guide, prereqs, skipped, minStart, level)
    local steps = SS.QuestSteps(guide)
    skipped = skipped or {}

    local blocked = {}
    local function IsBlocked(id)
        if blocked[id] ~= nil then return blocked[id] end
        local isBlocked = false
        if not SS.api.IsTurnedIn(id) and not SS.api.IsOnQuest(id) then
            for _, q in ipairs(SS.MissingPrerequisites(id, prereqs)) do
                if not SS.GuideAccepts(steps, q) or IsBlocked(q) then
                    isBlocked = true
                    break
                end
            end
        end
        blocked[id] = isBlocked
        return isBlocked
    end

    local gray = level and SS.GrayQuests(guide, steps, prereqs, level) or {}

    local skip, graySteps = {}, {}
    local state, order = {}, {}
    for i = 1, #(guide.steps or {}) do
        local quests = steps[i]
        if quests then
            local open, allBlocked, allGray = false, true, true
            for _, q in ipairs(quests) do
                if not SS.IsSatisfied(q.tag, q.id) then
                    open = true
                    -- turning in a quest you don't have and this section
                    -- never gives you: it came from a section you skipped
                    local orphan = q.tag ~= "accept" and not SS.api.IsOnQuest(q.id)
                        and not SS.GuideAccepts(steps, q.id)
                    if orphan then
                        blocked[q.id] = true
                    elseif not IsBlocked(q.id) then
                        allBlocked = false
                    end
                    if not gray[q.id] then allGray = false end
                end
            end
            if not open then
                state[i] = "done"
            elseif skipped[i] then
                state[i] = "skip"
            elseif allBlocked then
                state[i] = "skip"
                skip[i] = true
            elseif allGray then
                state[i] = "skip"
                graySteps[i] = true
            else
                state[i] = "todo"
            end
            order[#order + 1] = i
        end
    end

    -- where you are: the furthest finished step with its last few quest
    -- steps finished or skipped too
    local anchor = 0
    for k, i in ipairs(order) do
        if state[i] == "done" then
            local open, done, nDone = 0, {}, 0
            for m = math.max(1, k - SS.GUARD_STEPS), k do
                local j = order[m]
                if state[j] == "todo" then open = open + 1 end
                for _, q in ipairs(steps[j]) do
                    if not done[q.id] and SS.IsSatisfied(q.tag, q.id) then
                        done[q.id] = true
                        nDone = nDone + 1
                    end
                end
            end
            if open <= SS.GUARD_OPEN and nDone >= SS.GUARD_QUESTS then anchor = i end
        end
    end

    -- start just after the last finished quest step before the first open
    -- one, so travel, flight path and hearth steps in between aren't jumped
    -- (skipped quest steps in between are marked and passed over anyway)
    local start, startK
    local lastQuestStep, lastDone = 0, 0
    for k, i in ipairs(order) do
        if i > anchor and state[i] == "todo" then
            start, startK = math.max(lastDone, anchor) + 1, k
            break
        end
        lastQuestStep = i
        if state[i] == "done" then lastDone = i end
    end
    start = start or (anchor > 0 and math.min(lastQuestStep + 1, #guide.steps) or 1)

    -- a quest just ahead whose chain starts on an open pickup step just
    -- behind you: start on that pickup
    if startK and anchor > 0 then
        local anchorK
        for k, i in ipairs(order) do if i == anchor then anchorK = k end end
        local acceptAt = {}
        for k = math.max(1, (anchorK or 1) - SS.GUARD_STEPS), startK - 1 do
            local j = order[k]
            if state[j] == "todo" and not skipped[j] then
                for _, q in ipairs(steps[j]) do
                    if q.tag == "accept" and not acceptAt[q.id] and not SS.IsSatisfied(q.tag, q.id) then
                        acceptAt[q.id] = j
                    end
                end
            end
        end
        local back
        for k = startK, math.min(#order, startK + SS.GUARD_STEPS) do
            local i = order[k]
            if state[i] == "todo" then
                for _, q in ipairs(steps[i]) do
                    if not SS.IsSatisfied(q.tag, q.id) then
                        for _, p in ipairs(SS.MissingPrerequisites(q.id, prereqs)) do
                            local j = acceptAt[p]
                            if j and (not back or j < back) then back = j end
                        end
                    end
                end
            end
        end
        if back and back < start then start = back end
    end

    local blockedList = {}
    for id, b in pairs(blocked) do if b then blockedList[id] = true end end
    if minStart and minStart > start then start = minStart end
    return start, skip, blockedList, graySteps
end

------------------------------------------------------------------------
-- In the game
------------------------------------------------------------------------

--- The leveling guides this character can use.
function SS.Candidates()
    local faction = OXP.Player.faction
    if faction ~= "Alliance" and faction ~= "Horde" then return {} end
    return Registry.ForPlayer(nil, "OpenXP Leveling (" .. faction .. ")")
end

function SS.Prerequisites()
    if not SS.cachedPrereqs then SS.cachedPrereqs = SS.InferPrerequisites(SS.Candidates()) end
    return SS.cachedPrereqs
end

--- Find the right guide and step and load it. quiet: no chat summary.
function SS.Run(quiet)
    local level = SS.api.PlayerLevel()
    local guide, info = SS.PickGuide(SS.Candidates(), level, SS.api.ZoneName())
    if not guide then
        if not quiet then OXP.Print("Smart start couldn't find a guide section for your level.") end
        return false
    end
    local current = OXP.Engine.GetGuide()
    local same = current == guide
    local save = OXP.char.guides[guide.key]
    local skippedBefore = {}
    if same and save then
        for k, v in pairs(save.skipped or {}) do skippedBefore[k] = v end
    end
    local wasAt = same and save and save.step or nil

    local start, skip, blocked, graySteps = SS.PlanSteps(guide, SS.Prerequisites(), skippedBefore, wasAt, level)
    local skipped, status = {}, {}
    for i in pairs(skippedBefore) do skipped[i] = true end
    local nSkip, nGray, nBlocked = 0, 0, 0
    for i in pairs(skip) do skipped[i], status[i], nSkip = true, "chain", nSkip + 1 end
    for i in pairs(graySteps or {}) do skipped[i], status[i], nGray = true, "skipped", nGray + 1 end
    for _ in pairs(blocked) do nBlocked = nBlocked + 1 end
    OXP.Engine.Place(guide, start, skipped, status)
    SS.lastBlocked = blocked

    if not quiet then
        OXP.Print("Smart start: %s, step %d. %d of %d quests already done.",
            guide.name, OXP.Engine.PositionOf(start) or 1, info.done, info.total)
        if nGray > 0 then
            OXP.Print("Skipped %d steps with quests too low for you (gray). Type /oxp catchup to see them.", nGray)
        end
        if nBlocked > 0 then
            OXP.Print("Skipped %d steps for %d quests whose earlier chain quests you haven't done. Type /oxp catchup to see them.",
                nSkip, nBlocked)
        end
    end
    return true
end

-- Where a quest is picked up: the first guide that accepts it.
local pickup
local function PickupGuide(id)
    if not pickup then
        pickup = {}
        for _, g in ipairs(Registry.All()) do
            for _, step in ipairs(g.steps) do
                for _, goal in ipairs(step) do
                    if goal[1] == "accept" and goal.quest and not pickup[goal.quest] then
                        pickup[goal.quest] = g.name
                    end
                end
            end
        end
    end
    return pickup[id]
end

--- Quests in the loaded guide you skipped or whose chain was missed:
--- { {quest, pos, status, missing = {ids}} }.
function SS.SkippedChains()
    local out, seen = {}, {}
    local E = OXP.Engine
    for pos, step in ipairs(E.GetSteps()) do
        local state = E.StepState(pos)
        if state == "skipped" or state == "chain" then
            for _, g in ipairs(step.goals) do
                local id = g.quest
                if id and QUEST_KINDS[g[1]] and not seen[id] and not SS.api.IsTurnedIn(id) then
                    seen[id] = true
                    local missing
                    if OXP.QuestDB.Available() then
                        missing = OXP.QuestDB.MissingChain(id)
                    else
                        missing = SS.MissingPrerequisites(id, SS.Prerequisites())
                    end
                    out[#out + 1] = { quest = id, pos = pos, status = state, missing = missing }
                end
            end
        end
    end
    return out
end

function SS.ShowCatchUp()
    local list = SS.SkippedChains()
    if #list == 0 then
        return OXP.Print("No skipped quests or quest chains in your current guide section.")
    end
    OXP.Print("%d skipped quest(s) in this guide section:", #list)
    for _, e in ipairs(list) do
        local parts = {}
        for _, q in ipairs(e.missing or {}) do
            local where = PickupGuide(q)
            parts[#parts + 1] = OXP.QuestDB.QuestName(q) .. (where and (" (picked up in " .. where .. ")") or "")
        end
        local why = e.status == "chain" and "chain missed" or "skipped"
        if #parts > 0 then
            OXP.Print("Step %d, %s (%s). Needs first: %s", e.pos, OXP.QuestDB.QuestName(e.quest), why, table.concat(parts, ", "))
        else
            OXP.Print("Step %d, %s (%s). Click the step counter on the guide card to go back to it.",
                e.pos, OXP.QuestDB.QuestName(e.quest), why)
        end
    end
end

--- At login. With no guide: pick one. Far past your guide's levels with
--- none of its quests in your log: move you on; otherwise just say so.
function SS.OnLogin(hasGuide)
    local level = SS.api.PlayerLevel() or 1
    if not hasGuide then
        return SS.Run(true)
    end
    if OXP.settings.smartStartOnLogin == false then return end
    local guide = OXP.Engine.GetGuide()
    local _, hi = SS.LevelRange(guide)
    if not (hi and level > hi + 1) then return end
    local _, info = SS.ScoreGuide(guide, hi, "")
    local started = info and info.started or 0
    if level > hi + 4 and started == 0 then
        SS.Run(false)
    elseif not SS.hinted then
        SS.hinted = true
        OXP.Print("You're above this section's level. Type /oxp where to jump to the right section.")
    end
end

OXP.Listen("NO_GUIDE", function() SS.OnLogin(false) end)
OXP.Listen("READY", function()
    if OXP.Engine.GetGuide() then SS.OnLogin(true) end
end)

OXP.AddCommand("where", "find the right guide and step for your level and quests", function() SS.Run(false) end)
OXP.AddCommand("catchup", "list quests and chains you skipped in this guide", function() SS.ShowCatchUp() end)
