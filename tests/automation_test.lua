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
    -- an NPC with several quests: one taken (not done yet) that the guide
    -- turns in here later, and the next one to take. The one in progress
    -- must not be picked (it opened its "not done" page every time).
    game:Accept(305, 1)
    avail, active = { "The Second One" }, { "In Search Of The Excavation Team!" }
    local g306 = { name = "22-23 Greeting test 2", group = "Test",
                   steps = { { { "accept", quest = 306, text = "Accept The Second One" }, { "turnin", quest = 305 } } } }
    OXP.AddGuides({ file = "test", g306 })
    OXP.Engine.Load(g306.key)
    local savedName = OXP.QuestDB.QuestName
    OXP.QuestDB.QuestName = function(id) if id == 306 then return "The Second One" end return savedName(id) end
    t.eq(w.event("QUEST_GREETING"), "select The Second One", "a quest still in progress isn't picked: the next one is")
    -- a finished quest outside the guide (a daily, say) doesn't hide it either
    local savedTitle = GetActiveTitle
    active = { "Some Daily", "In Search Of The Excavation Team!" }
    GetActiveTitle = function(i) return active[i], i == 1 end
    t.eq(w.event("QUEST_GREETING"), "select The Second One", "a finished quest outside the guide waits behind the guide's next quest")
    GetActiveTitle = savedTitle
    active = { "In Search Of The Excavation Team!" }
    -- the guide's quest finished: it goes in first, unless auto turn-in is off
    game:FinishObjective(305, 1)
    t.eq(w.event("QUEST_GREETING"), "select active In Search Of The Excavation Team!", "a finished guide quest is turned in first")
    OXP.settings.autoTurnIn = false
    t.eq(w.event("QUEST_GREETING"), "select The Second One", "auto turn-in off: the finished one is left for you, the next is taken")
    OXP.settings.autoTurnIn = true
    OXP.QuestDB.QuestName = savedName
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
    OXP.settings.autoTurnIn = false
    w.gossip.active = { { questID = 8500, isComplete = true } }
    t.eq(w.event("GOSSIP_SHOW"), "", "auto turn-in off: gossip leaves finished quests to you")
    OXP.settings.autoTurnIn = true
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
    t.ok(not B.target:IsShown(), "after combat it catches up: the objective is done, nothing left to target")
    t.ok(not B.item:IsShown() and B.item:GetAttribute("type") == nil, "and the item button goes: its objective is done")
    local anchor = B.item.points[1] and B.item.points[1][2]
    t.ok(anchor ~= OXP.Card.frame and B.target.points[1][2] ~= OXP.Card.frame,
        "secure buttons aren't anchored to the card (in game the card got blocked in combat)")
    OXP.settings.targetButton = false
    B.Refresh()
    t.ok(not B.target:IsShown(), "target button off in settings")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- the quest item button: quest log item, cooldown, range, key, combat")
do
    local game, OXP = newGame({ level = 21 })
    local combat = false
    InCombatLockdown = function() return combat end
    local B, item = OXP.ActionButtons, OXP.ActionButtons.item
    t.ok(B.UpdateCooldown and pcall(B.UpdateCooldown), "no cooldown API at all: no error")
    addGuide(OXP, {
        { { "accept", quest = 7200 } },
        { { "complete", quest = 7200, obj = 1 }, { "complete", quest = 7201, obj = 1 },
          { "item", item = 9101, text = "Use the totem on the Bristleback" } },
        { { "turnin", quest = 7200 } },
    })
    game:Accept(7200, 1)
    game.specialItems[7200] = 9100
    B.Refresh()
    t.ok(not item:IsShown(), "the quest's item isn't in the bags yet: no button")
    game:AddItem(9100, 3)
    game:Accept(7201, 1)
    B.Refresh()
    t.ok(item:IsShown(), "the quest log's special item: shown")
    t.eq(item:GetAttribute("type"), "item", "a secure item button")
    t.eq(item:GetAttribute("item"), "item:9100", "using the quest log's item")
    t.eq(item.count:GetText(), "3", "with how many you carry")
    t.eq(item.points[1] and item.points[1][2], UIParent, "anchored to UIParent only")
    -- skin: the panel and accent edge follow the skin's colours
    t.ok(item.backdrop ~= nil and item.bdBorder ~= nil, "styled with the skin's backdrop")
    OXP.Style.ApplySkin("ember")
    OXP.Style.Repaint()
    local C = OXP.Style.C
    t.ok(math.abs(item.bdBorder[1] - C.blue[1]) < 1e-6 and math.abs(item.bdBorder[2] - C.blue[2]) < 1e-6,
        "repainted with the new skin's accent")
    OXP.Style.ApplySkin("midnight")
    -- cooldown spiral (C_Container first, then the old global)
    local cd = 30
    C_Container = { GetItemCooldown = function(id) return id == 9100 and game.now or 0, id == 9100 and cd or 0, 1 end }
    game:Fire("BAG_UPDATE_COOLDOWN")
    t.ok(item.cooldown.cd and item.cooldown.cd[2] == 30, "cooldown spiral from C_Container.GetItemCooldown")
    cd = 0
    game:Fire("BAG_UPDATE_COOLDOWN")
    t.eq(item.cooldown.cd, nil, "spiral cleared once it's ready")
    C_Container = nil
    GetItemCooldown = function() return game.now, 10, 1 end
    game:Fire("BAG_UPDATE_COOLDOWN")
    t.ok(item.cooldown.cd and item.cooldown.cd[2] == 10, "or the old GetItemCooldown")
    -- Forever: in combat some calls hand back secret values (comparing one throws)
    local SECRET = setmetatable({}, { __lt = function() error("compared a secret") end,
                                      __le = function() error("compared a secret") end })
    issecretvalue = function(v) return v == SECRET end
    GetItemCooldown = function() return SECRET, SECRET, 1 end
    game:Fire("BAG_UPDATE_COOLDOWN")
    t.eq(item.cooldown.cd, nil, "a secret cooldown reads as none, no error")
    issecretvalue, GetItemCooldown = nil, nil
    -- range: polled a few times a second, only with a target
    local hasTarget, inRange, asked = false, false, 0
    UnitExists = function(u) return u == "target" and hasTarget end
    IsItemInRange = function() asked = asked + 1 return inRange end
    game:Advance(0.3)
    t.eq(asked, 0, "no target: range isn't asked")
    hasTarget = true
    game:Advance(0.3)
    t.ok(asked > 0 and item.outOfRange == true, "target out of range: flagged")
    local r, g = item.icon:GetVertexColor()
    t.ok(r > 0.8 and g < 0.4, "and the icon goes red")
    inRange = true
    game:Advance(0.3)
    r, g = item.icon:GetVertexColor()
    t.ok(not item.outOfRange and r == 1 and g == 1, "in range: normal colour")
    inRange = false
    combat = true
    local before = asked
    game:Advance(0.3)
    t.ok(asked == before and not item.outOfRange, "in combat range isn't asked (Forever blocks it): no tint")
    combat = false
    game:Advance(0.3)
    t.ok(item.outOfRange == true, "out of combat again: asked")
    hasTarget = false
    game:Fire("PLAYER_TARGET_CHANGED")
    t.ok(not item.outOfRange, "no target: no tint")
    -- the bound key on the button
    GetBindingKey = function(b) return b == "CLICK OpenXPItemButton:LeftButton" and "SHIFT-F" or nil end
    game:Fire("UPDATE_BINDINGS")
    t.eq(item.hotkey:GetText(), "s-F", "the bound key, short, on the button")
    GetBindingKey = function() return "CTRL-SHIFT-BUTTON4" end
    game:Fire("UPDATE_BINDINGS")
    t.eq(item.hotkey:GetText(), "c-s-M4", "mouse buttons and two modifiers")
    GetBindingKey = nil
    -- combat: nothing secure changes, the look still does
    combat = true
    local before = item.points[1]
    OXP.settings.itemButtonPos = { "CENTER", "CENTER", 40, 30 }
    B.Place()
    t.eq(item.points[1], before, "not moved in combat")
    game.items[9100] = 0
    game:FinishObjective(7200, 1)
    B.Refresh()
    t.ok(item:IsShown() and item:GetAttribute("item") == "item:9100", "in combat it stays (secure)")
    t.ok(item.icon:IsDesaturated(), "but greys out: used up and its objective done")
    t.eq(item.count:GetText(), "", "count follows the bags in combat")
    combat = false
    game:Fire("PLAYER_REGEN_ENABLED")
    t.eq(item.points[1] and item.points[1][1], "CENTER", "after combat: moved to the saved spot")
    t.eq(item.points[1] and item.points[1][2], UIParent, "still on UIParent")
    t.ok(not item:IsShown(), "after combat: nothing carried for what's left, hidden")
    -- the step's "item" line belongs to 7201's objective
    game:AddItem(9101, 1)
    B.Refresh()
    t.eq(item:GetAttribute("item"), "item:9101", "the guide's item line, for the objective still open")
    game:FinishObjective(7201, 1)
    B.Refresh()
    t.ok(not item:IsShown(), "its objective done: hidden though you still carry it")
    -- 7200 is complete (to turn in): its quest log item isn't offered
    game.items[9100] = 1
    B.Refresh()
    t.ok(not item:IsShown(), "complete quest: its quest log item isn't offered")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- targets: only the mobs still needed (Loggers done, Deforesters left)")
do
    local game, OXP = newGame({ level = 23 })
    InCombatLockdown = function() return false end
    addGuide(OXP, {
        { { "text", text = "Windshear Crag: kill these as you meet them" },
          { "complete", quest = 1071, obj = 1 }, { "mob", name = "Venture Co. Logger" },
          { "complete", quest = 1071, obj = 2 }, { "mob", name = "Venture Co. Deforester" },
          { "complete", quest = 1093, obj = 1 }, { "mob", name = "Venture Co. Operator" } },
        { { "turnin", quest = 1071 }, { "target", name = "Gaxim Rustfizzle" } },
    })
    game:Accept(1071, 2)
    game:Accept(1093, 1)
    local B = OXP.ActionButtons
    B.Refresh()
    local names = {}
    for _, e in ipairs(B.WantedTargets()) do names[#names + 1] = e.name end
    t.eq(table.concat(names, ","), "Venture Co. Logger,Venture Co. Deforester,Venture Co. Operator", "all three to start")
    game:FinishObjective(1071, 1)
    B.Refresh()
    names = {}
    for _, e in ipairs(B.WantedTargets()) do names[#names + 1] = e.name end
    t.eq(table.concat(names, ","), "Venture Co. Deforester,Venture Co. Operator", "Loggers done: off the list")
    t.eq(B.target.unitName, "Venture Co. Deforester", "the bindable button: the first still needed")
    local macro = B.target:GetAttribute("macrotext")
    t.ok(macro and not macro:find("Logger", 1, true), "its macro no longer targets Loggers")
    t.ok(macro:find("Deforester", 1, true) and macro:find("Operator", 1, true), "but the others")
    t.ok(B.rows[2]:IsShown() and B.rows[2]:GetAttribute("macrotext"):find("Operator", 1, true), "a row per mob")
    t.ok(B.box:IsShown(), "the list is shown")
    local OnDragStart = B.box.scripts.OnDragStart
    t.ok(OnDragStart ~= nil, "and can be dragged")
    -- the nameplate/tooltip side: a Logger no longer counts for the step
    t.eq(OXP.Tooltips and OXP.Tooltips.GuideStep and select(3, OXP.Tooltips.GuideStep("Venture Co. Logger")) or nil, nil,
        "nameplates: Loggers aren't marked any more")
    t.eq(OXP.Tooltips and select(3, OXP.Tooltips.GuideStep("Venture Co. Deforester")), "mob", "Deforesters still are")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

print("-- a checkpoint into another zone counts once you're out in that zone")
do
    local game, OXP = newGame({ level = 23, map = 1440, x = 40, y = 61 })
    addGuide(OXP, {
        { { "goto", zone = "1440", x = 37, y = 51 }, { "accept", quest = 1034 } },
        { { "text", text = "Stonetalon Mountains" }, { "reach", text = "Windshear Crag", x = 76.5, y = 45.5, zone = "1442" } },
        { { "goto", zone = "1442", x = 61, y = 55 }, { "accept", quest = 1071 } },
    })
    game:Accept(1034, 0)
    local E = OXP.Engine
    game:Flush()
    t.eq(E.GetPosition(), 2, "on the checkpoint step")
    local reach = E.GetSteps()[2].goals[2]
    t.ok(reach.entry, "a reach into another zone is marked as an entry")
    t.eq(OXP.Goals.State(reach, E.GetSteps()[2].marks), "todo", "still in Ashenvale: not yet")
    game.pos = { map = 1442, x = 70, y = 52 } -- out of the tunnel, far from the spot
    t.eq(OXP.Goals.State(reach, E.GetSteps()[2].marks), "done", "out in Stonetalon: passed")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- a border, dock or tram checkpoint counts once you're in the zone it leads to")
do
    local game, OXP = newGame({ level = 33, map = 1441, x = 70, y = 80 })
    addGuide(OXP, {
        { { "reach", text = "Into Tanaris", x = 74.2, y = 93.6, zone = "1441" } },
        { { "goto", zone = "1446", x = 51, y = 28 }, { "accept", quest = 1034 } },
    })
    local E = OXP.Engine
    game:Flush()
    local reach = E.GetSteps()[1].goals[1]
    t.eq(reach.past, 1446, "it leads to Tanaris")
    t.eq(OXP.Goals.State(reach, E.GetSteps()[1].marks), "todo", "still in Thousand Needles: not yet")
    game.pos = { map = 1446, x = 52, y = 20 } -- crossed somewhere else
    t.eq(OXP.Goals.State(reach, E.GetSteps()[1].marks), "done", "in Tanaris: passed")
    E.Refresh()
    t.eq(E.GetPosition(), 2, "and the guide moves on")
end

------------------------------------------------------------------------
print("-- a guide that starts with \"Into <zone>\" counts it once you're out in that zone")
do
    local game, OXP = newGame({ level = 55, map = 1448, x = 60, y = 10 })
    addGuide(OXP, {
        { { "reach", text = "Into Winterspring", x = 28, y = 34.6, zone = "1452" } },
        { { "goto", zone = "1452", x = 61, y = 38 }, { "accept", quest = 1034 } },
    })
    local E = OXP.Engine
    game:Flush()
    local reach = E.GetSteps()[1].goals[1]
    t.ok(reach.entry, "marked as the way in")
    game.pos = { map = 1452, x = 40, y = 40 }
    t.eq(OXP.Goals.State(reach, E.GetSteps()[1].marks), "done", "out in Winterspring: passed")
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
print("-- a quest after one of several class versions: your class's version")
do
    -- Burning Blade Medallion (794) follows either Vile Familiars: 792
    -- (every class but Warlock) or 1499 (Warlock)
    local _, OXPh = newGame({ level = 10, faction = "Horde", race = "Orc", class = "HUNTER" })
    t.eq(OXPh.QuestDB.Blocked(794), 792, "hunter: blocked by the everyone-else Vile Familiars")
    local hc = OXPh.QuestDB.Chain(794)
    t.eq(hc[#hc], 792, "and that's the chain")
    local _, OXP = newGame({ level = 10, faction = "Horde", race = "Orc", class = "WARLOCK" })
    local DB = OXP.QuestDB
    t.eq(DB.Blocked(794), 1499, "warlock: blocked by the Warlock Vile Familiars")
    local chain = DB.Chain(794)
    t.eq(chain[#chain], 1499, "and the chain leads through that one")
    -- Boughs in the Wind (93797) needs a Mage-only quest: a warlock can't, still blocked
    t.eq(DB.Blocked(93797), 93791, "no version for your class: still blocked")
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
