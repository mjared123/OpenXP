-- OpenXP Smart Start
--
-- Works out where a player belongs in the leveling guide from their level,
-- zone, quest log and completed quests, so players who install OpenXP
-- mid-leveling (or skipped a section) land on the right step.
--
-- It also finds quest chains the player can't start because an earlier
-- quest in the chain was skipped, and skips those steps instead of sending
-- the player to a quest giver that won't offer the quest.
--
-- Prerequisite data comes from two places:
--   1. Questie's quest database, when Questie is installed.
--   2. Chains inferred from OpenXP's own guides: when a step turns in quest A
--      and then accepts quest B at the same quest giver, and every guide that
--      accepts B does it right after turning in A, B is treated as needing A.

local addonName, addon = ...

local SS = {}
addon.smartStart = SS

local QUEST_TAGS = {accept = true, turnin = true, complete = true}

-- Injectable game API so the logic can be unit tested outside the game.
SS.api = {
    IsTurnedIn = function(id) return addon.IsQuestTurnedIn(id) end,
    IsOnQuest = function(id) return addon.IsOnQuest(id) end,
    IsComplete = function(id) return addon.IsQuestComplete(id) end,
    PlayerLevel = function() return UnitLevel("player") end,
    ZoneName = function() return GetRealZoneText and GetRealZoneText() or "" end,
    Applies = function(tags) return addon.applies(tags) end,
    GuideName = function(guide)
        return addon.GetGuideName and addon.GetGuideName(guide) or guide.name
    end,
    QuestieDB = function()
        if _G.QuestieLoader then
            local ok, db = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, "QuestieDB")
            if ok then return db end
        end
    end,
}

---------------------------------------------------------------------------
-- Guide helpers
---------------------------------------------------------------------------

function SS.LevelRange(guide)
    local name = SS.api.GuideName(guide) or ""
    local lo, hi = name:match("(%d+)%s*%-%s*(%d+)")
    return tonumber(lo), tonumber(hi)
end

-- Returns, for each step, the quest elements it holds.
function SS.QuestSteps(guide)
    local out = {}
    for i, step in ipairs(guide.steps or {}) do
        local quests
        for _, element in ipairs(step.elements or {}) do
            if QUEST_TAGS[element.tag] and element.questId then
                quests = quests or {}
                table.insert(quests, {tag = element.tag, id = element.questId})
            end
        end
        out[i] = quests
    end
    return out
end

-- True when the quest element no longer needs doing.
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

---------------------------------------------------------------------------
-- Prerequisites
---------------------------------------------------------------------------

-- Builds {[questB] = {questA, ...}} from turn-in -> accept pairs in guides.
function SS.InferPrerequisites(guides)
    local seen = {}   -- seen[B] = number of times B is accepted
    local after = {}  -- after[B][A] = times B was accepted right after turning in A
    for _, guide in ipairs(guides) do
        for _, step in ipairs(guide.steps or {}) do
            local turnedIn = {}
            for _, element in ipairs(step.elements or {}) do
                local id = element.questId
                if id and element.tag == "turnin" then
                    -- An optional turn-in (".turnin -id") means the next
                    -- quest is offered either way, so it isn't a prerequisite.
                    if not element.skipIfMissing then
                        table.insert(turnedIn, id)
                    end
                elseif id and element.tag == "accept" then
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
        -- Only trust a pair when B is never accepted without A just before it,
        -- and only one quest was turned in (otherwise we can't tell which).
        local only, count = nil, 0
        for a, n in pairs(from) do
            if n == seen[b] then
                count = count + 1
                only = a
            end
        end
        if count == 1 then prereqs[b] = {only} end
    end
    return prereqs
end

-- Quest ids this quest needs that the player hasn't turned in.
-- `prereqs` is the inferred table; Questie data is added when available.
function SS.MissingPrerequisites(id, prereqs, visited)
    local api = SS.api
    visited = visited or {}
    if visited[id] then return {} end
    visited[id] = true

    local needed = {}
    local function need(q)
        if not api.IsTurnedIn(q) and not api.IsOnQuest(q) then
            table.insert(needed, q)
        end
    end

    local db = api.QuestieDB()
    local quest = db and db.GetQuest and db:GetQuest(id)
    if quest then
        if quest.preQuestGroup then
            for _, q in pairs(quest.preQuestGroup) do need(q) end
        end
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

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------

-- Scores one guide for the player. Higher is better; nil means "don't pick".
function SS.ScoreGuide(guide, level, zone)
    local lo, hi = SS.LevelRange(guide)
    if not lo then return nil end
    if level < lo - 1 or level > hi then return nil end

    local steps = SS.QuestSteps(guide)
    local total, done, started = 0, 0, 0
    local counted = {}
    for _, quests in pairs(steps) do
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

    local score = 0
    -- Resume a section the player is in the middle of: quests from it are
    -- in their quest log. (Turned-in quests alone aren't a good signal,
    -- because sections share quests with each other.)
    if started > 0 then score = score + 100 + started * 5 end
    -- Prefer the section whose level range fits best: lower bound closest
    -- to the player's level.
    score = score + 20 - math.abs(level - lo) * 2
    -- Sections that aren't in this character's default route (e.g. another
    -- race's detour) only win when nothing else fits.
    if guide.defaultfor and SS.api.Applies and not SS.api.Applies(guide.defaultfor) then
        score = score - 50
    end
    -- Small nudge toward the zone the player is standing in.
    local name = (SS.api.GuideName(guide) or ""):lower()
    if zone and zone ~= "" and name:find(zone:lower(), 1, true) then
        score = score + 10
    end
    return score, {total = total, done = done, started = started}
end

-- Picks the best guide from a list. Returns guide, info.
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

-- Works out, for a loaded guide, which step to start on and which steps to
-- skip because their quest chain is broken.
-- Returns startStep, skipSteps (set of step indexes), blocked (set of quest ids).
function SS.PlanSteps(guide, prereqs)
    local steps = SS.QuestSteps(guide)

    -- Quests whose chain can't be started.
    local blocked = {}
    local function IsBlocked(id)
        if blocked[id] ~= nil then return blocked[id] end
        local isBlocked = false
        if not SS.api.IsTurnedIn(id) and not SS.api.IsOnQuest(id) then
            local missing = SS.MissingPrerequisites(id, prereqs)
            for _, q in ipairs(missing) do
                -- Missing prerequisite that this guide doesn't pick up itself.
                if not SS.GuideAccepts(steps, q) or IsBlocked(q) then
                    isBlocked = true
                    break
                end
            end
        end
        blocked[id] = isBlocked
        return isBlocked
    end

    local skip = {}
    local start
    local lastDoneQuestStep = 0
    for i = 1, #(guide.steps or {}) do
        local quests = steps[i]
        if quests then
            local open, allBlocked = false, true
            for _, q in ipairs(quests) do
                if not SS.IsSatisfied(q.tag, q.id) then
                    open = true
                    if not IsBlocked(q.id) then allBlocked = false end
                end
            end
            if open and allBlocked then
                skip[i] = true
            elseif open and not start then
                start = lastDoneQuestStep + 1
            elseif not open and not start then
                lastDoneQuestStep = i
            end
        end
    end
    local blockedList = {}
    for id, b in pairs(blocked) do if b then blockedList[id] = true end end
    return start or 1, skip, blockedList
end

function SS.GuideAccepts(steps, id)
    for _, quests in pairs(steps) do
        for _, q in ipairs(quests) do
            if q.tag == "accept" and q.id == id then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- In-game glue
---------------------------------------------------------------------------

local function CandidateGuides()
    local list = {}
    local group = addon.defaultGroup
    if not group or not addon.GetActiveGuidesInGroup then return list end
    for _, guide in ipairs(addon.GetActiveGuidesInGroup(group)) do
        local fetched = addon:FetchGuide(guide)
        if fetched and fetched.steps then
            table.insert(list, fetched)
        end
    end
    return list
end

function SS.Prerequisites()
    if not SS.cachedPrereqs then
        SS.cachedPrereqs = SS.InferPrerequisites(CandidateGuides())
    end
    return SS.cachedPrereqs
end

local function Print(msg)
    if addon.comms and addon.comms.PrettyPrint then
        addon.comms.PrettyPrint(msg)
    else
        print("OpenXP: " .. msg)
    end
end

-- Finds the right guide and step for the player and loads it.
-- quiet = true suppresses the chat summary.
function SS.Run(quiet)
    local level = SS.api.PlayerLevel()
    local guide, info = SS.PickGuide(CandidateGuides(), level, SS.api.ZoneName())
    if not guide then
        if not quiet then
            Print("Smart start couldn't find a guide section for your level.")
        end
        return
    end

    addon:LoadGuide(guide)
    local current = addon.currentGuide
    if not current or not current.steps then return end

    local start, skip, blocked = SS.PlanSteps(current, SS.Prerequisites())
    for index in pairs(skip) do
        OXPCData.stepSkip[index] = true
        -- every step Smart start skips is one whose quest chain was missed
        if addon.card and addon.card.MarkStatus then addon.card.MarkStatus(current, index, "chain") end
    end
    if addon.card then addon.card.hold = nil end
    addon.SetStep(start)

    if not quiet then
        local nBlocked = 0
        for _ in pairs(blocked) do nBlocked = nBlocked + 1 end
        local skipped = 0
        for _ in pairs(skip) do skipped = skipped + 1 end
        Print(string.format("Smart start: %s, step %d. %d of %d quests already done.",
            SS.api.GuideName(current) or "?", start, info.done, info.total))
        if nBlocked > 0 then
            Print(string.format(
                "Skipped %d steps for %d quests whose earlier chain quests you haven't done. Type /oxp catchup to see them.",
                skipped, nBlocked))
        end
    end
    SS.lastBlocked = blocked
end

-- Quests in the current guide that you skipped or whose chain was missed,
-- worked out from the guide itself (step tags, skips, quest log), so it
-- covers steps you skipped by hand and survives reloads. Returns a list of
-- {quest, step, status, missing = {questIds}}.
local tinsert = table.insert
function SS.SkippedChains(guide)
    guide = guide or addon.currentGuide
    local out = {}
    local card = addon.card
    if not (guide and guide.steps and card and card.StepStatus) then return out end
    local current = addon.GetGuideProgress and addon.GetGuideProgress() or 1
    local seen = {}
    local skips = OXPCData and OXPCData.stepSkip or {}
    for i, step in ipairs(guide.steps) do
        if i < current or skips[i] then
            local status = card.StepStatus(guide, i, current)
            if status == "skipped" or status == "chain" then
                for _, e in ipairs(step.elements or {}) do
                    local id = tonumber(e.questId)
                    if id and id > 0 and not seen[id] and
                        (e.tag == "accept" or e.tag == "turnin" or e.tag == "complete") and
                        not SS.api.IsTurnedIn(id) then
                        seen[id] = true
                        local missing = {}
                        if card.MissingChain and card.HasQuestData and card.HasQuestData() then
                            missing = card.MissingChain(id)
                        else
                            missing = SS.MissingPrerequisites(id, SS.Prerequisites())
                        end
                        tinsert(out, {quest = id, step = i, status = status, missing = missing})
                    end
                end
            end
        end
    end
    return out
end

local function QName(id)
    return (addon.GetQuestName and addon.GetQuestName(id)) or ("Quest " .. id)
end

-- Lists skipped chains and where OpenXP picks up the missing quest.
function SS.ShowCatchUp()
    local list = SS.SkippedChains()
    if #list == 0 then
        Print("No skipped quests or quest chains in your current guide section.")
        return
    end
    Print(string.format("%d skipped quest(s) in this guide section:", #list))
    for _, entry in ipairs(list) do
        local parts = {}
        for _, q in ipairs(entry.missing or {}) do
            local where = ""
            local entries = addon.pickUpList and addon.pickUpList[q]
            if entries and entries[1] then
                where = string.format(" (picked up in %s)", entries[1].name or "?")
            end
            table.insert(parts, QName(q) .. where)
        end
        local why = entry.status == "chain" and "chain missed" or "skipped"
        if #parts > 0 then
            Print(string.format("Step %d, %s (%s). Needs first: %s", entry.step, QName(entry.quest), why,
                table.concat(parts, ", ")))
        else
            Print(string.format("Step %d, %s (%s). Click the step counter on the guide card to go back to it.",
                entry.step, QName(entry.quest), why))
        end
    end
end

-- Offer smart start on login when the player has no guide, or their guide is
-- far below their level (e.g. they installed OpenXP at level 16).
--
-- A fresh install has no guide at all, and the guide window stays hidden
-- until one is loaded, so this also runs at level 1 (where it picks the
-- starter guide for the player's race). Guides can still be loading a few
-- seconds after login, so it tries again a few times before giving up.
-- Players who switch it off in settings (smartStartOnLogin) still get a
-- guide when they have none; it only stops moving them between sections.
local function HasGuide()
    local current = addon.currentGuide
    return current and not current.empty and current.steps and true or false
end
SS.HasGuide = HasGuide

-- Makes sure the guide window is switched on once a guide is loaded, since
-- a click on the minimap button before then may have switched it off.
local function ShowGuide()
    local profile = addon.settings and addon.settings.profile
    if HasGuide() and profile and not profile.showEnabled and addon.settings.ToggleActive then
        addon.settings.ToggleActive()
    end
end

local RETRIES, RETRY_DELAY = 6, 2
function SS.OnLogin(attempt)
    attempt = attempt or 1
    local settings = addon.settings and addon.settings.profile
    local level = SS.api.PlayerLevel() or 1
    local current = addon.currentGuide
    local noGuide = not HasGuide()
    if not noGuide then
        if settings and settings.smartStartOnLogin == false then return end
        if level <= 1 then return end
        local _, hi = SS.LevelRange(current)
        if not (hi and level > hi + 1) then return end
        SS.Run(false)
        return
    end
    -- No guide: pick one for the character's race, faction and level so the
    -- guide card and arrow are there without any clicks.
    if #CandidateGuides() == 0 then
        if attempt < RETRIES and C_Timer then
            C_Timer.After(RETRY_DELAY, function() SS.OnLogin(attempt + 1) end)
        end
        return
    end
    SS.Run(level <= 1)
    if not HasGuide() and level <= 1 and addon.SelectDefaultGuide then
        addon.SelectDefaultGuide(true)
    end
    ShowGuide()
end

-- Minimap button / welcome button with no guide loaded: load one now
-- instead of toggling an empty, hidden window. Returns true if a guide is
-- loaded afterwards.
function SS.EnsureGuide()
    if HasGuide() then return true end
    if #CandidateGuides() == 0 then
        Print("Guides are still loading, one moment...")
        if C_Timer then
            C_Timer.After(RETRY_DELAY, function()
                if #CandidateGuides() > 0 then SS.EnsureGuide() end
            end)
        end
        return false
    end
    local level = SS.api.PlayerLevel() or 1
    if level <= 1 and addon.SelectDefaultGuide then
        addon.SelectDefaultGuide(true)
    end
    if not HasGuide() then SS.Run(level <= 1) end
    ShowGuide()
    if not HasGuide() and addon.ui and addon.ui.v2 and addon.ui.v2.configurator then
        addon.ui.v2.configurator:Open()
    end
    return HasGuide()
end
