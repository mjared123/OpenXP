-- Quest automation, each part its own setting; hold Shift to pause it:
--   auto accept    quests the loaded guide picks up
--   auto turn in   quests the loaded guide turns in, once they're complete,
--                  and (on by default) any other completed quest in your log
--   auto reward    take the reward when there is no choice (or only one);
--                  with "best reward" on, pick the choice that sells for most
--   skip gossip    pick a quest-giver's guide quest in the gossip window, or
--                  the only option when there is just one (never the
--                  innkeeper's "make this inn your home")
local _, OXP = ...

local Auto = {}
OXP.Automation = Auto

local Engine = OXP.Engine
local LOOKAHEAD = 60

local function On(key)
    if IsShiftKeyDown and IsShiftKeyDown() then return false end
    return OXP.settings[key] ~= false
end

-- Quests the loaded guide accepts / turns in, from the current step on (and
-- the steps just before it, in case you're a little ahead).
local function GuideQuests(kind)
    local out = {}
    local steps = Engine.GetSteps()
    local cur = Engine.GetPosition() or 1
    for pos = math.max(1, cur - 5), math.min(#steps, cur + LOOKAHEAD) do
        for _, g in ipairs(steps[pos].goals) do
            if g[1] == kind and g.quest then out[g.quest] = true end
        end
    end
    return out
end
Auto.GuideQuests = GuideQuests

-- Turn in this quest? The guide's own, and (setting "any completed quest",
-- on by default) any other quest in your log: quests the guide picked up
-- somewhere it doesn't turn them in, quests you took yourself.
-- Quests outside the guide are only turned in when that is safe to do
-- without asking: not a daily or weekly, and nothing to pay (gold or
-- currency). The guide's own quests are turned in as the route says.
local function Call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and v or nil
end

local function WindowAsksToPay()
    if (Call("QuestIsDaily") or Call("QuestIsWeekly")) then return true end
    if (tonumber(Call("GetQuestMoneyToGet")) or 0) > 0 then return true end
    if (tonumber(Call("GetNumQuestCurrencies")) or 0) > 0 then return true end
    return false
end

local function TurnInOK(id, inWindow)
    if not id then return false end
    if GuideQuests("turnin")[id] then return true end
    if not On("autoTurnIn") or OXP.settings.autoTurnInAny == false then return false end
    if not OXP.Quests.IsOnQuest(id) then return false end
    return not (inWindow and WindowAsksToPay())
end
Auto.TurnInOK = TurnInOK

local function QuestIdHere()
    return GetQuestID and GetQuestID() or nil
end

-- The quest window: offered, asking for items, or the reward
OXP.On("QUEST_DETAIL", function()
    if not On("autoAccept") then return end
    local id = QuestIdHere()
    if id and GuideQuests("accept")[id] then
        AcceptQuest()
        Auto.last = "accept " .. id
    end
end)

OXP.On("QUEST_PROGRESS", function()
    if not On("autoTurnIn") then return end
    local id = QuestIdHere()
    if TurnInOK(id, true) and IsQuestCompletable and IsQuestCompletable() then
        CompleteQuest()
        Auto.last = "complete " .. id
    end
end)

--- Which reward to take: 1 (or nil with no choice) when there is no real
--- choice, the best-selling choice when "best reward" is on, else false.
function Auto.RewardChoice()
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n <= 1 then return n == 1 and 1 or nil end
    if OXP.settings.autoBestReward ~= true then return false end
    local best, bestPrice
    for i = 1, n do
        local link = GetQuestItemLink and GetQuestItemLink("choice", i)
        if not link then return false end -- item info not loaded yet: let the player choose
        local price = select(11, GetItemInfo(link))
        if price == nil then return false end
        if not bestPrice or price > bestPrice then best, bestPrice = i, price end
    end
    return best
end

OXP.On("QUEST_COMPLETE", function()
    if not On("autoTurnIn") or not On("autoReward") then return end
    local id = QuestIdHere()
    if not TurnInOK(id, true) then return end
    local choice = Auto.RewardChoice()
    if choice == false then
        -- a real choice: the window stays open for you
        if Auto.noted ~= id then
            Auto.noted = id
            OXP.Print(OXP.L("Pick your reward to turn in this quest."))
        end
        Auto.last = "choose " .. id
        return
    end
    GetQuestReward(choice or 1)
    Auto.last = "reward " .. id .. " " .. tostring(choice)
end)

------------------------------------------------------------------------
-- Gossip: the quest-giver's options
------------------------------------------------------------------------

local function Gossip() return C_GossipInfo end

local function Lists()
    local G = Gossip()
    local active, available = {}, {}
    if G and G.GetActiveQuests then
        for _, q in ipairs(G.GetActiveQuests() or {}) do active[#active + 1] = q end
        for _, q in ipairs(G.GetAvailableQuests() or {}) do available[#available + 1] = q end
    end
    return active, available
end

local function Options()
    local G = Gossip()
    if G and G.GetOptions then return G.GetOptions() or {} end
    return {}
end

OXP.On("GOSSIP_SHOW", function()
    if not On("skipGossip") then return end
    local G = Gossip()
    local active, available = Lists()
    local turnins, accepts = GuideQuests("turnin"), GuideQuests("accept")
    for _, q in ipairs(active) do
        local repeats = q.repeatable or (q.frequency and q.frequency ~= 0)
        if q.isComplete and (turnins[q.questID] or (not repeats and TurnInOK(q.questID))) then
            G.SelectActiveQuest(q.questID)
            Auto.last = "gossip turnin " .. q.questID
            return
        end
    end
    for _, q in ipairs(available) do
        if accepts[q.questID] then
            G.SelectAvailableQuest(q.questID)
            Auto.last = "gossip accept " .. q.questID
            return
        end
    end
    if #active == 0 and #available == 0 then
        local opts = Options()
        if #opts == 1 and opts[1].type ~= "binder" and G.SelectOption then
            G.SelectOption(opts[1].gossipOptionID or 1)
            Auto.last = "gossip option"
        end
    end
end)

-- A quest-giver with only quests to offer (no gossip): the old greeting window
OXP.On("QUEST_GREETING", function()
    if not On("skipGossip") then return end
    local turnins, accepts = GuideQuests("turnin"), GuideQuests("accept")
    -- the window only gives titles; the game's and our data's can differ in
    -- case and punctuation ("The Excavation Team" / "the Excavation Team")
    local function key(s) return s and s:lower():gsub("[%p%s]+", " "):gsub("^ ", ""):gsub(" $", "") end
    local function same(id, title)
        local k = key(title)
        return k ~= nil and (key(OXP.QuestDB.QuestName(id)) == k or key(OXP.Quests.GetTitle(id)) == k)
    end
    local function idOf(title)
        for id in pairs(turnins) do if same(id, title) then return id end end
        for id in pairs(accepts) do if same(id, title) then return id end end
    end
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
        local title, isComplete = GetActiveTitle(i)
        local id = idOf(title)
        if (id and turnins[id]) or (isComplete and On("autoTurnIn") and OXP.settings.autoTurnInAny ~= false) then
            SelectActiveQuest(i)
            return
        end
    end
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
        local id = idOf(GetAvailableTitle(i))
        if id and accepts[id] then
            SelectAvailableQuest(i)
            return
        end
    end
end)
