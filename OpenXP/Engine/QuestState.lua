-- What the player's quests look like right now: which quests are in the log,
-- which objectives are done, which quests are turned in.
--
-- The quest log is read once after it changes and cached; every question
-- after that is a table lookup. Sends "QUESTS_CHANGED" (once per frame) when
-- anything may have changed.
local _, OXP = ...

local Quests = {}
OXP.Quests = Quests

local log = {}            -- [questID] = { title=, complete=, failed=, objectives = { {text=, done=, have=, need=} } }
local dirty = true
local turnedInNow = {}    -- turned in this session (the server flag can lag behind QUEST_TURNED_IN)
local abandoned = {}      -- removed from the log this session without being turned in

local C_QuestLog = C_QuestLog or {}

local function objectivesFromAPI(questID)
    if not C_QuestLog.GetQuestObjectives then return nil end
    local list = C_QuestLog.GetQuestObjectives(questID)
    if type(list) ~= "table" then return nil end
    local out = {}
    for i, o in ipairs(list) do
        out[i] = {
            text = o.text, done = o.finished and true or false,
            have = o.numFulfilled, need = o.numRequired,
        }
    end
    return out
end

local function objectivesFromLog(index)
    local out = {}
    local n = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(index) or 0
    for i = 1, n do
        local text, _, finished = GetQuestLogLeaderBoard(i, index)
        local have, need = (text or ""):match("(%d+)%s*/%s*(%d+)")
        out[i] = { text = text, done = finished and true or false, have = tonumber(have), need = tonumber(need) }
    end
    return out
end

local function scan()
    dirty = false
    log = {}
    local n = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for index = 1, n do
        local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(index)
        if not isHeader and questID and questID > 0 then
            log[questID] = {
                title = title,
                complete = isComplete == 1 or isComplete == true,
                failed = isComplete == -1,
                objectives = objectivesFromAPI(questID) or objectivesFromLog(index),
            }
        end
    end
end

-- A quest the client knows about but our scan missed (its header is
-- collapsed): build its entry from the per-quest API.
local function lookup(questID)
    if dirty then scan() end
    local q = log[questID]
    if q then return q end
    if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID) then
        local objectives = objectivesFromAPI(questID) or {}
        local complete = true
        for _, o in ipairs(objectives) do
            if not o.done then complete = false end
        end
        q = { title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID),
              complete = complete, failed = false, objectives = objectives }
        log[questID] = q
        return q
    end
    return nil
end

--- The quest is in the log.
function Quests.IsOnQuest(questID)
    return lookup(questID) ~= nil
end

--- The quest has been turned in (on this character, ever).
function Quests.IsTurnedIn(questID)
    if turnedInNow[questID] then return true end
    if C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
    elseif IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(questID) and true or false
    end
    return false
end

--- The quest is in the log and ready to turn in.
function Quests.IsComplete(questID)
    local q = lookup(questID)
    return q ~= nil and q.complete
end

--- Objective `obj` of a quest in the log is finished (or the whole quest is).
function Quests.IsObjectiveDone(questID, obj)
    local q = lookup(questID)
    if not q then return false end
    if q.complete then return true end
    local o = q.objectives[obj]
    return o ~= nil and o.done
end

--- { text=, done=, have=, need= } for an objective of a quest in the log.
function Quests.GetObjective(questID, obj)
    local q = lookup(questID)
    return q and q.objectives[obj]
end

function Quests.GetTitle(questID)
    local q = lookup(questID)
    if q and q.title then return q.title end
    return C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or nil
end

--- The player dropped this quest this session (to tell "skipped" from "not yet").
function Quests.WasAbandoned(questID)
    return abandoned[questID] == true
end

local function changed()
    dirty = true
    OXP.Soon("QUESTS_CHANGED", function() OXP.Send("QUESTS_CHANGED") end)
end

OXP.On("QUEST_LOG_UPDATE", changed)
OXP.On("QUEST_ACCEPTED", function(_, a, b)
    -- Classic passes (logIndex, questID); later clients pass (questID).
    abandoned[tonumber(b or a) or 0] = nil
    changed()
end)
OXP.On("QUEST_TURNED_IN", function(_, questID)
    if questID then turnedInNow[questID] = true end
    changed()
end)
OXP.On("QUEST_REMOVED", function(_, questID)
    if questID and not turnedInNow[questID] then abandoned[questID] = true end
    changed()
end)
OXP.On("UNIT_QUEST_LOG_CHANGED", function(_, unit)
    if unit == "player" then changed() end
end)
OXP.On("PLAYER_ENTERING_WORLD", changed)

-- For tests and debugging: forget the cached log.
function Quests.Invalidate() dirty = true end
