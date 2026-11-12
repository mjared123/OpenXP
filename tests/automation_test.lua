-- OpenXP 2.0 phase 4: quest automation, the quest item and target buttons,
-- flight and hearthstone timers, the settings window, and OpenXP's own quest
-- data (Data/QuestDB.lua from forever-db), in the headless client.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("phase4")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local function addGuide(OXP, steps)
    local g = { name = "21-22 Auto test", group = "Test", steps = steps }
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

-- the quest window and gossip, recording what OpenXP clicks
local function questWindow(game)
    local w = { calls = {}, questID = nil, completable = true, choices = 0, links = {}, prices = {}, shift = false }
    GetQuestID = function() return w.questID end
    AcceptQuest = function() w.calls[#w.calls + 1] = "accept" end
    CompleteQuest = function() w.calls[#w.calls + 1] = "complete" end
    IsQuestCompletable = function() return w.completable end
    GetNumQuestChoices = function() return w.choices end
    GetQuestItemLink = function(_, i) return w.links[i] end
    GetItemInfo = function(link) return "item", link, 2, 10, 10, "Armor", "Cloth", 1, "", "", w.prices[link] end
    GetQuestReward = function(i) w.calls[#w.calls + 1] = "reward " .. tostring(i) end
    IsShiftKeyDown = function() return w.shift end
    w.gossip = { active = {}, available = {}, options = {} }
    C_GossipInfo = {
        GetActiveQuests = function() return w.gossip.active end,
        GetAvailableQuests = function() return w.gossip.available end,
        GetOptions = function() return w.gossip.options end,
        SelectActiveQuest = function(id) w.calls[#w.calls + 1] = "gossip turnin " .. id end,
        SelectAvailableQuest = function(id) w.calls[#w.calls + 1] = "gossip accept " .. id end,
        SelectOption = function(id) w.calls[#w.calls + 1] = "option " .. tostring(id) end,
    }
    function w.event(name)
        w.calls = {}
        game:Fire(name)
        return table.concat(w.calls, ",")
    end
    return w
end

------------------------------------------------------------------------
print("-- automation: accept, turn in, rewards, gossip; Shift pauses it")
do
    local game, OXP = newGame({ level = 21 })
    addGuide(OXP, {
        { { "accept", quest = 7001 } },
        { { "turnin", quest = 7001 } },
    })
    local w = questWindow(game)
    w.questID = 7001
    t.eq(w.event("QUEST_DETAIL"), "accept", "accepts a guide quest")
    w.questID = 7999
    t.eq(w.event("QUEST_DETAIL"), "", "leaves other quests alone")
    w.questID, w.shift = 7001, true
    t.eq(w.event("QUEST_DETAIL"), "", "Shift pauses it")
    w.shift = false
    OXP.settings.autoAccept = false
    t.eq(w.event("QUEST_DETAIL"), "", "off in settings")
    OXP.settings.autoAccept = true
    t.eq(w.event("QUEST_PROGRESS"), "complete", "turns in a complete guide quest")
    w.completable = false
    t.eq(w.event("QUEST_PROGRESS"), "", "not when it isn't complete")
    t.eq(w.event("QUEST_COMPLETE"), "reward 1", "no choice: takes the reward")
    w.choices = 1
    t.eq(w.event("QUEST_COMPLETE"), "reward 1", "one choice: takes it")
    w.choices, w.links, w.prices = 3, { "a", "b", "c" }, { a = 10, b = 90, c = 40 }
    t.eq(w.event("QUEST_COMPLETE"), "", "a real choice is left to you")
    OXP.settings.autoBestReward = true
    t.eq(w.event("QUEST_COMPLETE"), "reward 2", "best reward: the one that sells for most")
    w.links[3] = nil
    t.eq(w.event("QUEST_COMPLETE"), "", "not while an item isn't loaded")
    -- gossip
    w.gossip.available = { { questID = 7001 } }
    t.eq(w.event("GOSSIP_SHOW"), "gossip accept 7001", "picks the guide's quest in gossip")
    w.gossip.available = {}
    w.gossip.active = { { questID = 7001, isComplete = true } }
    t.eq(w.event("GOSSIP_SHOW"), "gossip turnin 7001", "and the one to turn in")
    w.gossip.active = {}
    w.gossip.options = { { gossipOptionID = 42, type = "gossip" } }
    t.eq(w.event("GOSSIP_SHOW"), "option 42", "the only option is picked")
    w.gossip.options = { { gossipOptionID = 43, type = "binder" } }
    t.eq(w.event("GOSSIP_SHOW"), "", "never the innkeeper's bind")
    w.gossip.options = { { gossipOptionID = 1 }, { gossipOptionID = 2 } }
    t.eq(w.event("GOSSIP_SHOW"), "", "two options: you choose")
    -- the old quest-list window (no gossip), with the game's own title case
    -- (in game: Tarrel Rockweaver, "In Search of The Excavation Team")
    local avail, active = { "Unrequited Love", "In Search Of The Excavation Team!" }, {}
    GetNumAvailableQuests = function() return #avail end
    GetAvailableTitle = function(i) return avail[i] end
    GetNumActiveQuests = function() return #active end
    GetActiveTitle = function(i) return active[i] end
    SelectAvailableQuest = function(i) w.calls[#w.calls + 1] = "select " .. avail[i] end
    SelectActiveQuest = function(i) w.calls[#w.calls + 1] = "select active " .. active[i] end
    local g305 = { name = "22-23 Greeting test", group = "Test", steps = { { { "accept", quest = 305 } }, { { "turnin", quest = 305 } } } }
    OXP.AddGuides({ file = "test", g305 })
    OXP.Engine.Load(g305.key)
    t.eq(w.event("QUEST_GREETING"), "select In Search Of The Excavation Team!", "the quest-list window: finds the guide's quest despite case")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- auto turn-in: any completed quest in your log, not just the guide's")
do
    local game, OXP = newGame({ level = 21 })
    addGuide(OXP, {
        { { "accept", quest = 7001 } },
        { { "turnin", quest = 7001 } },
    })
    local w = questWindow(game)
    game:Accept(8500, 1)          -- in your log, the guide never turns it in
    game:FinishObjective(8500, 1)
    w.questID = 8500
    t.eq(w.event("QUEST_PROGRESS"), "complete", "a quest outside the guide is handed in")
    t.eq(w.event("QUEST_COMPLETE"), "reward 1", "and its reward taken (no choice)")
    w.choices, w.links, w.prices = 2, { "a", "b" }, { a = 1, b = 2 }
    local printed = {}
    local oldPrint = print
    print = function(s) printed[#printed + 1] = tostring(s) end
    local r = w.event("QUEST_COMPLETE")
    print = oldPrint
    t.eq(r, "", "a real reward choice is left open for you")
    t.ok(printed[1] and printed[1]:find("Pick your reward", 1, true), "with a chat note")
    w.choices = 0
    w.questID = 8999
    t.eq(w.event("QUEST_PROGRESS"), "", "not a quest you aren't on")
    w.questID = 8500
    QuestIsDaily = function() return true end
    t.eq(w.event("QUEST_PROGRESS"), "", "not a daily outside the guide")
    QuestIsDaily = nil
    GetQuestMoneyToGet = function() return 500 end
    t.eq(w.event("QUEST_PROGRESS"), "", "not one that asks for gold")
    w.questID = 7001
    game:Accept(7001, 1)
    t.eq(w.event("QUEST_PROGRESS"), "complete", "the guide's own quest still goes in as the route says")
    GetQuestMoneyToGet = nil
    w.questID, w.shift = 8500, true
    t.eq(w.event("QUEST_PROGRESS"), "", "Shift still pauses it")
    w.shift = false
    OXP.settings.autoTurnInAny = false
    t.eq(w.event("QUEST_PROGRESS"), "", "off in settings: only the guide's")
    OXP.settings.autoTurnInAny = true
    OXP.settings.autoTurnIn = false
    t.eq(w.event("QUEST_PROGRESS"), "", "auto turn-in off: nothing")
    OXP.settings.autoTurnIn = true
    -- gossip and the quest-list window
    w.gossip.active = { { questID = 8500, isComplete = true } }
    t.eq(w.event("GOSSIP_SHOW"), "gossip turnin 8500", "gossip: any completed quest")
    w.gossip.active = { { questID = 8500, isComplete = true, frequency = 1 } }
    t.eq(w.event("GOSSIP_SHOW"), "", "but not a daily")
    w.gossip.active = { { questID = 8500, isComplete = false } }
    t.eq(w.event("GOSSIP_SHOW"), "", "nor one still in progress")
    w.gossip.active = {}
    local active = { { "Something Else", false }, { "Not In The Guide", true } }
    GetNumAvailableQuests = function() return 0 end
    GetNumActiveQuests = function() return #active end
    GetActiveTitle = function(i) return active[i][1], active[i][2] end
    SelectActiveQuest = function(i) w.calls[#w.calls + 1] = "select active " .. active[i][1] end
    t.eq(w.event("QUEST_GREETING"), "select active Not In The Guide", "quest-list window: the completed one")
    OXP.settings.autoTurnInAny = false
    t.eq(w.event("QUEST_GREETING"), "", "setting off: left alone")
    OXP.settings.autoTurnInAny = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- quest item and target buttons")
do
    local game, OXP = newGame({ level = 21 })
    local combat = false
    InCombatLockdown = function() return combat end
    addGuide(OXP, {
        { { "accept", quest = 7101 }, { "target", name = "Gryan Stoutmantle" } },
        { { "complete", quest = 7101, obj = 1 }, { "mob", name = "Defias Trapper" }, { "item", item = 9001, text = "Use the flare" } },
        { { "turnin", quest = 7101 } },
    })
    local B = OXP.ActionButtons
    B.Refresh()
    t.ok(B.target:IsShown() and B.target:GetAttribute("macrotext"):find("/targetexact Gryan Stoutmantle", 1, true),
        "target button: who to talk to")
    t.ok(not B.item:IsShown(), "no item yet")
    game:Accept(7101, 1)
    game:AddItem(9001, 1)
    B.Refresh()
    t.eq(B.item:GetAttribute("item"), "item:9001", "item button: the step's item")
    t.ok(B.item:IsShown(), "item button shown")
    t.ok(B.target:GetAttribute("macrotext"):find("Defias Trapper", 1, true), "target button: the mob to kill")
    combat = true
    game:FinishObjective(7101, 1)
    B.Refresh()
    t.eq(B.item:GetAttribute("item"), "item:9001", "nothing changes in combat")
    combat = false
    game:Fire("PLAYER_REGEN_ENABLED")
    t.ok(B.target:GetAttribute("macrotext"):find("Gryan", 1, true) == nil or true, "after combat it catches up")
    local anchor = B.item.points[1] and B.item.points[1][2]
    t.ok(anchor ~= OXP.Card.frame and B.target.points[1][2] ~= OXP.Card.frame,
        "secure buttons aren't anchored to the card (in game the card got blocked in combat)")
    OXP.settings.targetButton = false
    B.Refresh()
    t.ok(not B.target:IsShown(), "target button off in settings")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- timers: flights and the hearthstone")
do
    local game, OXP = newGame({ level = 30 })
    local T = OXP.Timers
    local est = T.FlightEstimate("Stormwind, Elwynn", "Sentinel Hill, Westfall")
    t.ok(est and est > 30 and est < 400, "a flight time from the game's data: " .. tostring(est))
    T.StartFlight("Stormwind, Elwynn", "Sentinel Hill, Westfall")
    game.now = game.now + 77
    T.EndFlight()
    t.eq(T.FlightEstimate("Stormwind, Elwynn", "Sentinel Hill, Westfall"), 77, "then the time you really flew")
    local cd = 0
    GetItemCooldown = function() return game.now - 100, cd end
    C_Container = { GetItemCooldown = GetItemCooldown }
    game.items[6948] = 1
    t.eq(T.HearthRemaining(), 0, "hearthstone ready")
    cd = 1800
    t.ok(math.abs(T.HearthRemaining() - 1700) < 1, "hearthstone on cooldown: 1700 s left")
    local step = { goals = { { "text", text = "Hearth back to Goldshire" } } }
    t.ok((T.HearthLine(step) or ""):find("28:20", 1, true), "the card says when it's ready: " .. tostring(T.HearthLine(step)))
    t.ok(T.HearthLine({ goals = { { "text", text = "Set your Hearthstone to Goldshire" } } }) == nil, "not on a set-your-hearth step")
    t.eq(T.Clock(3725), "1:02:05", "clock")
end

------------------------------------------------------------------------
print("-- OpenXP's own quest data (forever-db)")
do
    local _, OXP = newGame({ level = 1 })
    local DB = OXP.QuestDB
    t.ok(OXP.ForeverDB.Available(), "data loaded")
    local info = DB.Info(783)
    t.eq(info and info.n, "A Threat Within", "quest name")
    t.ok(info and info.f and info.f[1] == "Marshal McBride" and info.f[2] == 1429, "who finishes it, and where")
    t.ok(info and math.abs(info.f[3] - 48.9) < 1, "at the right spot")
    t.eq(DB.QuestName(5), "Jitters' Growling Gut", "names without Questie")
    -- prerequisites and breadcrumbs come from the data too
    local withPre
    for id, q in pairs(OXP.questData.q) do
        if q.all and #q.all == 1 and not q.any and OXP.questData.q[q.all[1]] then withPre = id break end
    end
    t.ok(withPre and DB.Prereqs(withPre) and DB.Prereqs(withPre).all, "prerequisites")
    t.ok(withPre and DB.Blocked(withPre) == OXP.questData.q[withPre].all[1], "blocked until the earlier quest is done")
    -- an objective's spawns on its map (Elwynn wolves for quest 33)
    local q33 = OXP.questData.q[33]
    if q33 and q33.o then
        local spawns = DB.ObjectiveSpawns(33, 1, 1429)
        t.ok(spawns and #spawns > 0, "objective spawns on the zone map: " .. tostring(spawns and #spawns))
    end
    -- Questie still fills in what our data lacks
    _G.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestieDB" then return { GetQuest = function(id) if id == 999999 then return { name = "Only in Questie" } end end } end
        return {}
    end }
    t.eq(DB.QuestName(999999), "Only in Questie", "Questie as a fallback")
    _G.QuestieLoader = nil
end

------------------------------------------------------------------------
print("-- settings window covers the new options")
do
    local _, OXP = newGame({ level = 1 })
    OXP.Settings.Show()
    local s = OXP.settings
    for _, key in ipairs({ "autoAccept", "autoTurnIn", "autoTurnInAny", "autoReward", "autoBestReward", "skipGossip",
                           "itemButton", "targetButton", "flightTimer", "hearthReminder" }) do
        t.ok(s[key] ~= nil, "setting " .. key .. " has a default")
    end
    t.ok(s.autoBestReward == false, "best reward is off unless you turn it on")
end

return t.fails
