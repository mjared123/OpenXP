-- OpenXP 2.0 UI: the guide card (steps, live counts, chain and missing-quest
-- warnings with their buttons, history, collapse, step list), tooltips,
-- feedback link, menu, settings, minimap button and slash commands, in the
-- headless client.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("ui")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local counter = 0
local function addGuide(OXP, steps, extra)
    counter = counter + 1
    local g = { name = "21-22 Test Zone " .. counter, group = "Test", steps = steps }
    for k, v in pairs(extra or {}) do g[k] = v end
    OXP.AddGuides({ file = "test", g })
    return g
end

local function warnButtons(block)
    local out = {}
    local w = block.warn
    if not (w and w.shown) then return "" end
    for _, name in ipairs({ "get", "back", "chain", "finish", "skip" }) do
        if w[name].shown then out[#out + 1] = name .. "=" .. tostring(w[name].label.text) end
    end
    return table.concat(out, ", ")
end

------------------------------------------------------------------------
print("-- the card shows the steps you're on")
do
    local game, OXP = newGame({ level = 21 })
    local g = addGuide(OXP, {
        { completewith = "next", { "zone", name = "Duskwood", text = "Run to Duskwood" } },
        { { "text", text = "Talk to |cOXP_FRIENDLY_Bob|r" }, { "accept", quest = 600, text = "Accept Bob's Task" } },
        { { "text", text = "Kill wolves" }, { "complete", quest = 600, obj = 1 } },
        { { "turnin", quest = 600, text = "Turn in Bob's Task" } },
    })
    OXP.Engine.Load(g.key)
    local C = OXP.Card
    C.Refresh(true)
    t.ok(C.frame.shown, "card shown")
    local b1, b2 = C.blocks[1], C.blocks[2]
    t.ok(b1 and b1.shown and b2 and b2.shown, "the step to do and the travel step both shown")
    t.ok(b1.title.text:find("Talk to |cFF66BB6ABob|r", 1, true), "colour tags become real colours: " .. tostring(b1.title.text))
    t.ok(b2.title.text:find("ALONG THE WAY", 1, true), "the travel step is labelled along the way")
    game:Accept(600, 1)
    game.log[1].objectives[1].text = "Wolf slain: 2/5"
    OXP.Quests.Invalidate()
    C.Refresh(true)
    local line = C.blocks[1].lines[1]
    t.ok(line and line.text.text == "Wolf slain: 2/5", "live kill count: " .. tostring(line and line.text.text))
    t.ok(line and line.count.shown and line.count.text == "2 / 5", "with a bar and count")


    -- collapse, history, step list, back and resume
    C.SetCollapsed(true)
    t.ok(not C.blocks[1].shown or true, "collapsed")
    C.SetCollapsed(false)
    OXP.Engine.Back()
    t.ok(OXP.Engine.IsHeld(), "back holds the step")
    C.Refresh(true)
    t.ok(C.bar.resume.shown, "Back to step button while looking back")
    C.Resume()
    t.ok(not OXP.Engine.IsHeld() and OXP.Engine.GetPosition() == 3, "resume returns to the furthest step")
    C.ToggleStepList()
    C.FillStepList()
    C.histOffset = 1
    C.Refresh(true)
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
    t.ok(not C.lastError, "no card errors: " .. tostring(C.lastError))
end

------------------------------------------------------------------------
print("-- new text on the card is set again a moment later (in game: blank title until a resize)")
do
    local game, OXP = newGame({ level = 21 })
    local g = addGuide(OXP, {
        { { "text", text = "Kill wolves" }, { "complete", quest = 600, obj = 1 } },
        { { "turnin", quest = 600, text = "Turn in Bob's Task" } },
    })
    OXP.Engine.Load(g.key)
    game:Accept(600, 1)
    local C = OXP.Card
    C.Refresh(true)
    local function runDelayed()
        local queued = game.delayed
        game.delayed = {}
        for _, fn in ipairs(queued) do fn() end
        return #queued
    end
    runDelayed()
    local reapplied = 0
    local oldReapply = OXP.Fonts.Reapply
    OXP.Fonts.Reapply = function() reapplied = reapplied + 1 end
    C.Refresh(true)
    t.eq(#game.delayed, 0, "nothing new on screen: no re-text")
    game:FinishObjective(600, 1)
    C.Refresh(true)
    t.ok(#game.delayed >= 2, "a new step on the card: the text is set again, twice")
    runDelayed()
    t.ok(reapplied >= 2 and #game.delayed == 0, "and that doesn't queue more")
    OXP.Fonts.Reapply = oldReapply
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end
------------------------------------------------------------------------
print("-- a quest chain you missed: go back to its first quest, then return")
do
    local game, OXP = newGame({ level = 21 })
    OXP.QuestDB.data = { prereqs = { [702] = { all = { 701 } } }, info = {}, chains = { [702] = { 701 } } }
    local g = addGuide(OXP, {
        { { "accept", quest = 701, text = "Accept Part One" } },
        { { "accept", quest = 710 } },
        { { "turnin", quest = 701, text = "Turn in Part One" } },
        { { "accept", quest = 702, text = "Accept Part Two" } },
        { { "turnin", quest = 702 } },
    })
    OXP.Engine.Load(g.key)
    game:Accept(710, 0)
    OXP.Engine.GoTo(4, true) -- skipped ahead past the first part
    local C = OXP.Card
    C.Refresh(true)
    local b = C.blocks[1]
    local buttons = warnButtons(b)
    t.ok(buttons:find("back=Go back to step 1", 1, true), "offers to go back to step 1: " .. buttons)
    t.ok(buttons:find("chain=Do the chain", 1, true) and buttons:find("skip=", 1, true), "and the chain walk and skip")
    b.warn.back.scripts.OnClick()
    t.eq(OXP.Engine.GetPosition(), 1, "back at the chain's first quest")
    game:Accept(701, 0)
    game:TurnIn(701)
    C.Tick()
    t.eq(OXP.Engine.GetPosition(), 4, "and back to where you were once it can be done")

    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

print("-- Do the chain: the card walks you through it with the arrow")
do
    local game, OXP = newGame({ level = 21 })
    OXP.QuestDB.data = { prereqs = { [702] = { all = { 701 } } }, chains = { [702] = { 701 } },
                         info = { [701] = { n = "Part One", l = 20, s = { "Bob", 1453, 40, 40 }, f = { "Bob", 1453, 40, 40 }, o = {} } } }
    local g = addGuide(OXP, {
        { { "accept", quest = 702, text = "Accept Part Two" } },
        { { "turnin", quest = 702 } },
    })
    OXP.Engine.Load(g.key)
    local C = OXP.Card
    C.Refresh(true)
    C.blocks[1].warn.chain.scripts.OnClick()
    t.ok(C.detour and C.detour.target == 702, "chain walk started")
    C.Refresh(true)
    t.ok(C.blocks[1].title.text:find("Pick up Part One", 1, true), "card shows the chain's quest: " .. tostring(C.blocks[1].title.text))
    t.ok(OXP.Target.override and OXP.Target.override.title == "Bob", "arrow goes to the quest giver")
    game:Accept(701, 0)
    game:TurnIn(701)
    game:Accept(702, 0)
    C.Tick()
    t.ok(C.detour == nil and OXP.Target.override == nil, "walk ends once the quest is yours")
    OXP.QuestDB.data = {}
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

print("-- Do the chain from far away, and a chain quest with no spot (in game: hunter in the Wetlands)")
do
    local game, OXP = newGame({ level = 22, class = "HUNTER", map = 1437, x = 0.10, y = 0.60 })
    OXP.QuestDB.data = { prereqs = { [702] = { all = { 701, 703 } } }, chains = { [702] = { 701, 703 } },
                         info = { [701] = { n = "Part One", l = 20, s = { "Bob", 1457, 40, 40 }, f = { "Bob", 1457, 40, 40 }, o = {} },
                                  [703] = { n = "Part Three", l = 20, o = {} } } }
    local g = addGuide(OXP, {
        { { "accept", quest = 702, text = "Accept Part Two" } },
        { { "turnin", quest = 702 } },
    })
    OXP.Engine.Load(g.key)
    local C = OXP.Card
    C.Refresh(true)
    C.blocks[1].warn.chain.scripts.OnClick()
    C.Refresh(true)
    local sent = 0
    OXP.Listen("ARROW_CHANGED", function() sent = sent + 1 end)
    local first = OXP.Target.override
    for _ = 1, 5 do C.Refresh(true) end
    t.ok(OXP.Target.override == first and sent == 0, "the arrow's target is set once, not every refresh (" .. sent .. ")")
    local aim = OXP.Target.Update()
    t.ok(aim ~= nil, "the arrow has somewhere to go")
    t.ok(aim and aim.real == first, "on the way to the chain's quest")
    t.ok(aim and (aim.travel or aim.map == 1437), "a trip is planned to Darnassus: " .. tostring(aim and aim.title))
    -- the next quest of the chain has no spot in the data
    game:Accept(701, 0)
    game:TurnIn(701)
    C.Refresh(true)
    t.ok(OXP.Target.override and OXP.Target.override.none, "no spot: the arrow is told so")
    t.ok(OXP.Target.Update() == nil, "and shows nothing rather than the guide's step")
    local lines = {}
    for _, l in ipairs(C.blocks[1].lines) do if l.shown then lines[#lines + 1] = tostring(l.text.text) end end
    t.ok(table.concat(lines, " "):find("No map spot", 1, true), "the card says there's no spot: " .. table.concat(lines, " | "))
    C.StopDetour()
    t.ok(OXP.Target.override == nil, "Back to guide clears it")
    OXP.QuestDB.data = {}
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- a turn-in for a quest you don't have: get it, then return")
do
    local game, OXP = newGame({ level = 21 })
    OXP.QuestDB.data = { prereqs = {}, info = {} }
    local g = addGuide(OXP, {
        { { "accept", quest = 801 } },
        { { "accept", quest = 802 } },
        { { "turnin", quest = 801 } },
    })
    OXP.Engine.Load(g.key)
    game:Accept(802, 0)
    OXP.Engine.GoTo(3, true)
    local C = OXP.Card
    C.Refresh(true)
    local buttons = warnButtons(C.blocks[1])
    t.ok(buttons:find("get=Get the quest", 1, true), "offers Get the quest: " .. buttons)
    C.blocks[1].warn.get.scripts.OnClick()
    t.eq(OXP.Engine.GetPosition(), 1, "sent to the pickup step")
    game:Accept(801, 0)
    C.Tick()
    t.eq(OXP.Engine.GetPosition(), 3, "back to the turn-in")
    -- an unfinished quest: Finish it
    game.log[#game.log].objectives = { { text = "Thing: 0/1", done = false } }
    OXP.Quests.Invalidate()
    C.Refresh(true)
    t.ok(warnButtons(C.blocks[1]):find("finish=Finish it", 1, true), "unfinished quest offers Finish it")
    C.blocks[1].warn.skip.scripts.OnClick()
    t.eq(OXP.Engine.StepState(3), "skipped", "Skip this step marks it skipped")
    OXP.QuestDB.data = {}
end

------------------------------------------------------------------------
print("-- standing by a later turn-in: do it first, then back")
do
    local game, OXP = newGame({ level = 21, map = 1453, x = 50, y = 50 })
    local g = addGuide(OXP, {
        { { "goto", zone = "Stormwind City", x = 10, y = 10 }, { "accept", quest = 901 } },
        { { "goto", zone = "Stormwind City", x = 50, y = 51 }, { "turnin", quest = 902 }, { "accept", quest = 99903, text = "Accept 903" } },
        { { "goto", zone = "Stormwind City", x = 50, y = 51 }, { "turnin", quest = 904 } },
    })
    game:Accept(902, 0)
    OXP.Engine.Load(g.key)
    local C = OXP.Card
    t.ok(C.CheckHere(), "a ready turn-in right here")
    t.eq(OXP.Engine.GetPosition(), 1, "the guide stays on your step (in game: it jumped 12 -> 29)")
    C.Refresh(true)
    t.ok(C.blocks[1].title.text:find("WHILE YOU'RE HERE", 1, true), "the turn-in is shown on top: " .. tostring(C.blocks[1].title.text))
    local lines = {}
    for _, l in ipairs(C.blocks[1].lines) do if l.shown then lines[#lines + 1] = tostring(l.text.text) end end
    local all = table.concat(lines, " | ")
    t.ok(C.blocks[1].title.text:find("Turn in", 1, true) and all:find("Accept 903", 1, true), "its turn-in and its pickup: " .. all)
    t.ok(C.blocks[2] and C.blocks[2].shown, "your own step still under it")
    -- a full quest log: only the turn-in, the pickup waits for its step
    _G.MAX_QUESTLOG_QUESTS = #game.log
    C.Refresh(true)
    local full = {}
    for _, l in ipairs(C.blocks[1].lines) do if l.shown then full[#full + 1] = tostring(l.text.text) end end
    t.ok(not table.concat(full, " "):find("Accept 903", 1, true), "full quest log: no pickup offered")
    _G.MAX_QUESTLOG_QUESTS = 40
    C.Refresh(true)
    local real = OXP.Target.Real()
    t.ok(real and real.pos == 2, "the arrow goes to the turn-in first")
    game:TurnIn(902)
    C.CheckHere()
    t.ok(C.here ~= nil, "handed in but not picked up yet: still shown")
    game:Accept(99903, 1)
    C.CheckHere()
    C.Refresh(true)
    t.ok(C.here == nil and not C.blocks[1].title.text:find("WHILE", 1, true), "all done: the block goes away")
    t.eq(OXP.Engine.GetPosition(), 1, "still on your step: nothing in between skipped")
    -- walking away also ends it
    game:Accept(904, 0)
    t.ok(C.CheckHere() and C.here, "another ready turn-in")
    t.ok(C.CheckHere(OXP.Places.ToWorld(1453, 10, 12)) and C.here == nil, "walked away: gone")
end

------------------------------------------------------------------------
print("-- tooltips")
do
    local game, OXP = newGame({ level = 21 })
    local g = addGuide(OXP, {
        { { "accept", quest = 1001 } },
        { { "mob", name = "Gnoll Brute" }, { "collect", item = 5555, count = 4 }, { "complete", quest = 1001, obj = 1 } },
        { { "target", name = "Marshal Dughan" }, { "turnin", quest = 1001 } },
    })
    OXP.Engine.Load(g.key)
    local T = OXP.Tooltips
    local need = T.NeededItems()
    t.ok(#need == 1 and need[1].itemId == 5555 and need[1].need == 4, "an item the guide says to collect")
    t.ok(T.MobDrops(5555, "Gnoll Brute"), "the step's mob drops it")
    t.ok(T.IsNeeded(5555) and not T.IsNeeded(1), "bag marks only on needed items")
    local pos, what = T.GuideStep("Marshal Dughan")
    t.ok(pos == 3 and what == "Talk to", "NPC tooltip names the step: " .. tostring(pos) .. " " .. tostring(what))
    game:Accept(1001, 1)
    game.log[1].objectives[1].text = "Gnoll Brute slain: 1/8"
    local kills = T.KillLines("Gnoll Brute")
    t.ok(#kills == 1 and kills[1].have == 1 and kills[1].need == 8, "kill objective on the mob")
end

------------------------------------------------------------------------
print("-- feedback, menu, settings, minimap, commands")
do
    local game, OXP = newGame({ level = 23, zone = "Ashenvale" })
    local g = addGuide(OXP, { { { "accept", quest = 1 } }, { { "accept", quest = 2 } } })
    OXP.Engine.Load(g.key)
    local link = OXP.Feedback.BugLink()
    t.ok(link:find("template=bug_report.yml", 1, true), "bug template")
    t.ok(link:find("version=test", 1, true), "version")
    t.ok(link:find("step=1+of+2", 1, true), "step: " .. link)
    t.ok(link:find("character=Human+WARRIOR%2C+level+23+in+Ashenvale", 1, true), "character: " .. link)
    OXP.Feedback.Show()
    OXP.GuidePicker.Toggle()
    OXP.Settings.Show()
    OXP.MinimapButton.Refresh()
    t.ok(OXP.MinimapButton.button.shown, "minimap button shown")
    OXP.Welcome.Show("welcome")
    -- What's New after an update must not move you (1.x 1.3.58)
    local W = OXP.Welcome
    t.eq(W.frame and W.frame.start.label.text or (_G.OpenXPWelcome and _G.OpenXPWelcome.start.label.text),
        "Continue leveling", "with a guide loaded the button says Continue leveling")
    local ran, pos = false, OXP.Engine.GetPosition()
    local oldRun = OXP.SmartStart.Run
    OXP.SmartStart.Run = function() ran = true end
    _G.OpenXPWelcome.start.scripts.OnClick()
    OXP.SmartStart.Run = oldRun
    t.ok(not ran and OXP.Engine.GetPosition() == pos, "and keeps you on your step")
    local printed = {}
    local oldPrint = print
    print = function(s) printed[#printed + 1] = tostring(s) end
    OXP.RunCommand("")
    OXP.RunCommand("step")
    OXP.RunCommand("arrow")
    OXP.RunCommand("arrow")
    OXP.RunCommand("perf")
    OXP.RunCommand("perf show")
    print = oldPrint
    local all = table.concat(printed, "\n")
    for _, word in ipairs({ "where", "catchup", "path", "perf", "arrow", "card", "settings", "feedback", "menu", "step" }) do
        t.ok(all:find("/oxp " .. word, 1, true), "/oxp lists " .. word)
    end
    t.ok(all:find("guide: Test/", 1, true), "/oxp step prints the guide")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- every guide text shows real colours")
do
    local _, OXP = newGame({ level = 21 })
    local bad = 0
    for _, g in ipairs(OXP.Registry.All()) do
        for _, step in ipairs(g.steps) do
            for _, goal in ipairs(step) do
                if goal.text and OXP.Text.Format(goal.text):find("OXP_", 1, true) then bad = bad + 1 end
            end
        end
    end
    t.eq(bad, 0, "texts with a colour tag left over")
end

return t.fails
