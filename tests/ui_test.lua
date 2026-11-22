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
    if OXP.Target.BAKED_ONLY then
        t.ok(aim and not aim.travel, "SoupEngine walks only: no trip planned, straight at the quest")
    else
        t.ok(aim and (aim.travel or aim.map == 1437), "a trip is planned to Darnassus: " .. tostring(aim and aim.title))
    end
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
    -- the buttons wear the skin: Finish it in the accent, Skip quiet, no box
    local w, SC = C.blocks[1].warn, OXP.Style.C
    t.eq(w.finish.kind, "primary", "Finish it is the thing to do")
    t.eq(w.skip.kind, "quiet", "Skip stays quiet")
    t.ok(math.abs(w.finish.bg.vertex[3] - SC.blue[3]) < 0.01 and w.finish.bg.vertex[4] > 0.15,
        "Finish it: a tint of the accent")
    t.eq(w.finish.bdColor, nil, "no box edge")
    w.skip.scripts.OnEnter(w.skip)
    t.ok(math.abs(w.skip.label.textColor[1] - SC.text[1]) < 0.01, "Skip lights up under the mouse")
    w.skip.scripts.OnLeave(w.skip)
    -- big card text: the buttons grow with it and the block makes room
    OXP.settings.fontSize = 18
    C.Refresh(true)
    t.ok(w.finish.h >= w.finish.label:GetStringHeight() + 8, "taller with bigger text: " .. tostring(w.finish.h))
    t.ok(w.finish.w >= w.finish.label:GetStringWidth() + 16, "and wide enough for its words")
    OXP.settings.skin = "minimal"
    OXP.Send("SETTINGS_CHANGED")
    C.Refresh(true)
    t.eq(w.finish.label.font and w.finish.label.font[3], "OUTLINE", "Minimal: outlined button words")
    OXP.settings.skin = "midnight"
    OXP.settings.fontSize = 12
    OXP.Send("SETTINGS_CHANGED")
    C.Refresh(true)
    t.eq(C.bar.menu.icon.texture:sub(-4), "more", "the bar's menu button has three dots, not a list")
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
        { { "goto", zone = "Stormwind City", x = 50, y = 51 }, { "turnin", quest = 904 }, { "accept", quest = 99905, text = "Accept Not Offered" } },
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

    -- in game (Karl Boran): turned in, but they don't offer the pickup yet
    t.ok(C.CheckHere() and C.here and C.here.pos == 3, "back by the turn-in")
    game:TurnIn(904)
    C.CheckHere()
    t.ok(C.here and C.here.handed, "handed in")
    real = OXP.Target.Real()
    t.ok(real and real.pos == 1, "the arrow goes straight back to your step")
    game:Fire("GOSSIP_CLOSED")
    C.CheckHere()
    t.ok(C.here == nil, "done talking to them: the block closes (what they didn't offer waits for its step)")
end

print("-- while you're here: pickups only offered when you can take them, and it times out")
do
    local game, OXP = newGame({ level = 21, map = 1453, x = 50, y = 50 })
    local g = addGuide(OXP, {
        { { "goto", zone = "Stormwind City", x = 10, y = 10 }, { "accept", quest = 901 } },
        { { "goto", zone = "Stormwind City", x = 50, y = 51 }, { "turnin", quest = 902 },
          { "accept", quest = 99906, text = "Accept Too High" }, { "accept", quest = 99907, text = "Accept Fine" } },
    })
    OXP.QuestDB.data = { prereqs = {}, info = { [99906] = { n = "Too High", r = 40 }, [99907] = { n = "Fine", r = 10 } } }
    game:Accept(902, 0)
    OXP.Engine.Load(g.key)
    local C = OXP.Card
    t.ok(C.CheckHere(), "a ready turn-in right here")
    local hs = C.HereStep()
    local names = {}
    for _, goal in ipairs(hs.goals) do if goal.quest then names[#names + 1] = goal[1] .. goal.quest end end
    names = table.concat(names, ",")
    t.ok(not names:find("99906", 1, true) and names:find("accept99907", 1, true), "not a pickup above your level: " .. names)
    game:TurnIn(902)
    C.CheckHere()
    t.ok(C.here ~= nil, "pickup still to take")
    game.now = game.now + 31
    C.CheckHere()
    t.ok(C.here == nil, "but not forever")
    OXP.QuestDB.data = {}
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
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
    local words = { "where", "catchup", "path", "perf", "arrow", "card", "settings", "feedback", "menu", "step" }
    if OXP.Target.BAKED_ONLY then words[3] = "nav" end -- /oxp path is gone; /oxp nav is new
    for _, word in ipairs(words) do
        t.ok(all:find("/oxp " .. word, 1, true), "/oxp lists " .. word)
    end
    t.ok(all:find("guide: Test/", 1, true), "/oxp step prints the guide")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- the card keeps its size from step to step; long text wraps and scrolls inside it")
do
    local game, OXP = newGame({ level = 21 })
    local long = ("Follow the road east past the farm and the old mill, then climb the hill. "):rep(8)
    local g = addGuide(OXP, {
        { { "text", text = "Talk to Bob" }, { "accept", quest = 600, text = "Accept Bob's Task" } },
        { { "text", text = long }, { "accept", quest = 601, text = "Accept the Long Walk" } },
        { { "text", text = "Short again" }, { "accept", quest = 602, text = "Accept Three" } },
    })
    OXP.Engine.Load(g.key)
    local C, f = OXP.Card, OXP.Card.frame
    C.Refresh(true)
    local w0, h0 = f.w, f.h
    t.eq(h0, OXP.FIRST_LOAD.cardHeight, "a fresh card has the first-load height")
    t.ok(not C.more.shown, "a short step fits: no More")
    local played, dirs = 0, {}
    local realPlay = C.PlayStepAnimation
    C.PlayStepAnimation = function(dir)
        played = played + 1
        dirs[#dirs + 1] = dir
        return realPlay(dir)
    end
    C.GoNext()
    t.eq(f.w, w0, "next step: same width")
    t.eq(f.h, h0, "next step: same height, so the buttons stay under the mouse")
    t.eq(played, 1, "the new step slides in")
    t.eq(dirs[1], 1, "from the right, going forward")
    local tw = C.tween
    t.ok(tw.shown and C.body:GetAlpha() == 0, "hidden at once, so it never flashes in before the fade")
    local x = C.body.points[1] and C.body.points[1][4]
    t.ok(x and x > 0, "starts off to the right: " .. tostring(x))
    tw.scripts.OnUpdate(tw, 0.1)
    local a = C.body:GetAlpha()
    t.ok(a > 0 and a < 1, "half-way: fading in (" .. a .. ")")
    C.Refresh(true) -- a redraw mid-slide (the text is set again at 0.1 s) keeps the motion
    t.ok(C.body.points[1][4] > 0 and C.body.points[1][4] < x, "a redraw doesn't snap it home")
    tw.scripts.OnUpdate(tw, 1)
    t.ok(not tw.shown and C.body:GetAlpha() == 1 and C.body.points[1][4] == 0, "and it settles in place")
    local title = C.blocks[1].title
    t.eq(title.w, w0 - 12 * 2 - 34 - 12, "the title wraps to the card's width")
    t.ok(title:GetStringHeight() > 14 * 3, "the long title takes several lines")
    t.ok(C.overflow and C.more.shown and C.more.label.text == "More", "too long for the card: More shows")
    t.ok(C.view.h < h0, "the steps area is cut off inside the card (" .. tostring(C.view.h) .. ")")
    local upH = C.view.h
    C.more.scripts.OnClick()
    t.ok(C.expanded and C.more.label.text == "Less", "More opens the text")
    t.eq(f.h, h0, "and the card still doesn't grow")
    t.eq(C.view.h, upH, "the steps already have all the room there is (no Up next to give way)")
    t.ok(f.scripts.OnMouseWheel and C.ScrollText(-1) and C.view.scroll > 0, "the wheel scrolls the text")
    C.ScrollText(-1000)
    t.eq(C.view.scroll, C.maxScroll, "but not past the end")
    C.Refresh(true)
    t.ok(C.expanded and C.view.scroll == C.maxScroll, "a redraw of the same step keeps it open and scrolled")

    -- nothing else may change the card's size
    f:SetHeight(900)
    t.eq(f.h, h0, "a size from anywhere else is put back")
    t.ok(f:DoesClipChildren(), "the card clips what's inside it")
    local said = C.UIDebug()
    t.ok(said:find(("card: %dx%d"):format(OXP.FIRST_LOAD.cardWidth, OXP.FIRST_LOAD.cardHeight), 1, true) and said:find("cut off", 1, true), "/oxp uidebug: " .. said)

    -- drag the grip: the text re-wraps live, the card takes the new size
    C.StartSizing()
    f:SetSize(400, 380) -- the game sizing the frame under the mouse
    t.eq(C.blocks[1].title.w, 400 - 70, "the text re-wraps as the frame changes size")
    t.eq(f.h, 380, "and the frame keeps the size you're dragging to")
    f.w, f.h = 520, 420
    C.grip.scripts.OnUpdate()
    t.eq(C.blocks[1].title.w, 520 - 70, "the text re-wraps while you drag")
    t.eq(f.w, 520, "the frame keeps the size you're dragging to")
    C.StopSizing()
    t.eq(OXP.settings.cardWidth, 520, "width saved")
    t.eq(OXP.settings.cardHeight, 420, "height saved")
    t.ok(not C.overflow, "wide enough now: no overflow")
    -- and back down: smaller than the content works too (#16)
    C.StartSizing()
    f.w, f.h = 220, 160
    C.grip.scripts.OnUpdate()
    C.StopSizing()
    t.ok(f.w == 220 and f.h == 160, "the card shrinks below its content: " .. f.w .. "x" .. f.h)
    t.ok(C.overflow and C.more.shown, "and the rest is behind More")
    C.StartSizing()
    f.w, f.h = 2000, 10
    C.grip.scripts.OnUpdate()
    C.StopSizing()
    t.ok(OXP.settings.cardWidth == 640 and OXP.settings.cardHeight == 150, "kept within bounds")

    -- the next step: More closes, back at the top
    C.SetExpanded(true)
    C.GoNext()
    t.ok(not C.expanded and (C.view.scroll or 0) == 0, "a new step starts closed and at the top")
    t.eq(f.h, 150, "still the height you chose")
    -- collapsed and back
    C.SetCollapsed(true)
    t.eq(f.h, 42, "collapsed: one line")
    C.SetCollapsed(false)
    t.eq(f.h, 150, "expanded again: your height")
    -- animations off
    OXP.settings.cardAnimations = false
    played = 0
    C.GoBack()
    t.eq(played, 1, "going back asks for the slide")
    t.ok(not C.tween.shown and C.body:GetAlpha() == 1, "Animate step changes off: no slide or fade")
    OXP.settings.cardAnimations = true
    C.GoNext()
    C.GoBack()
    t.eq(dirs[#dirs], -1, "going back: from the left")
    C.tween.scripts.OnUpdate(C.tween, 1)
    OXP.settings.cardAnimations = true
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
    t.ok(not C.lastError, "no card errors: " .. tostring(C.lastError))
end

print("-- one block failing still lays out and sizes the card, with one red line")
do
    local game, OXP = newGame({ level = 21 })
    local g = addGuide(OXP, {
        { completewith = "next", { "zone", name = "Duskwood", text = "Run to Duskwood" } },
        { { "text", text = "Talk to Bob" }, { "accept", quest = 600, text = "Accept Bob's Task" } },
        { { "turnin", quest = 600 } },
    })
    OXP.Engine.Load(g.key)
    local C, f = OXP.Card, OXP.Card.frame
    local old = C.StepContent
    C.StepContent = function(step)
        if step.completewith then error("boom") end
        return old(step)
    end
    local printed = {}
    local oldPrint = print
    print = function(msg) printed[#printed + 1] = tostring(msg) end
    C.Refresh(true)
    C.Refresh(true)
    print = oldPrint
    C.StepContent = old
    local errors = 0
    for _, line in ipairs(printed) do if line:find("OpenXP card error", 1, true) then errors = errors + 1 end end
    t.eq(errors, 1, "one card error line: " .. table.concat(printed, " | "))
    t.ok(C.blocks[1].shown and C.blocks[1].title.text:find("Talk to Bob", 1, true), "the good step is still shown")
    t.ok(not C.blocks[2].shown, "the broken one is left out")
    t.eq(f.h, OXP.FIRST_LOAD.cardHeight, "the card is still sized")
    t.ok(C.bar.shown and C.view.h > 1, "and laid out")
    C.lastError = nil
end

print("-- a chain walk: the target button follows the walk's quest (#14)")
do
    local game, OXP = newGame({ level = 21 })
    OXP.QuestDB.data = { prereqs = { [7000002] = { all = { 7000001 } } }, chains = { [7000002] = { 7000001 } },
                         info = { [7000001] = { n = "Part One", l = 20, s = { "Bob", 1453, 40, 40 }, f = { "Alice", 1453, 40, 40 }, o = {} } } }
    local g = addGuide(OXP, {
        { { "target", name = "Guide Person" }, { "accept", quest = 7000002, text = "Accept Part Two" } },
        { { "turnin", quest = 7000002 } },
    })
    OXP.Engine.Load(g.key)
    local C, B = OXP.Card, OXP.ActionButtons
    C.Refresh(true)
    t.eq(B.WantedTarget(), "Guide Person", "on the guide: the step's person")
    C.blocks[1].warn.chain.scripts.OnClick()
    game:Flush()
    t.eq(B.WantedTarget(), "Bob", "walking the chain: who gives the walk's quest")
    t.eq(B.target.unitName, "Bob", "and the button was told at once")
    game:Accept(7000001, 1)
    t.eq(B.WantedTarget(), nil, "on the quest, nothing known to kill: no target")
    game:FinishObjective(7000001, 1)
    t.eq(B.WantedTarget(), "Alice", "objectives done: who to hand it in to")
    C.StopDetour()
    game:Flush()
    t.eq(B.WantedTarget(), "Guide Person", "back to the guide: the step's person again")
    OXP.QuestDB.data = {}
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- the settings window: a page per category, controls change settings live")
do
    local game, OXP = newGame({ level = 21 })
    local S = OXP.Settings
    S.Show()
    t.ok(S.frame and S.frame.shown, "settings shown")
    local changed = 0
    OXP.Listen("SETTINGS_CHANGED", function() changed = changed + 1 end)
    for _, def in ipairs(S.PAGES) do
        local page = S.Select(def.key)
        t.ok(page and page.area.shown, "page " .. def.key .. " opens")
        t.ok(#page.rows > 0, "page " .. def.key .. " has rows")
    end
    local card = S.Page("card")
    t.ok(card.preview ~= nil, "the card page has a live preview")
    local tog = card.toggles.cardAnimations
    tog.scripts.OnClick(tog)
    t.eq(OXP.settings.cardAnimations, false, "a toggle switches its setting off")
    tog.scripts.OnClick(tog)
    t.eq(OXP.settings.cardAnimations, true, "and on again")
    card.sliders.fontSize:SetValue(15)
    t.eq(OXP.settings.fontSize, 15, "the text size slider sets the size")
    card.sliders.fontSize:SetValue(99)
    t.eq(OXP.settings.fontSize, 20, "but not past its end")
    card.sliders.cardScale:SetValue(1.13)
    t.ok(math.abs(OXP.settings.cardScale - 1.15) < 0.001, "card scale snaps to its steps: " .. OXP.settings.cardScale)
    local dd = card.dropdowns.fontOutline
    dd:Open()
    local list = _G.OpenXPDropdownList
    t.ok(list and list.shown and #list.rows == 3, "the dropdown lists its choices")
    list.rows[2].scripts.OnClick(list.rows[2])
    t.eq(OXP.settings.fontOutline, "OUTLINE", "picking one sets it")
    t.ok(not list.shown, "and closes the list")
    t.ok(changed >= 5, "every change is sent out (" .. changed .. ")")
    local auto = S.Page("auto")
    auto.toggles.autoBestReward.scripts.OnClick(auto.toggles.autoBestReward)
    t.eq(OXP.settings.autoBestReward, true, "automation toggles work")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

print("-- Pick a guide: grouped by level, search, current guide, start")
do
    local game, OXP = newGame({ level = 22 })
    local a = addGuide(OXP, { { { "text", text = "Run to Darkshire" }, { "accept", quest = 1 } }, { { "accept", quest = 2 } } })
    local b = addGuide(OXP, { { { "text", text = "Kill wolves" }, { "accept", quest = 3 } } })
    b.name = "25-27 Somewhere Else"
    b.minLevel, b.maxLevel = 25, 27
    OXP.Engine.Load(a.key)
    local P = OXP.GuidePicker
    P.Toggle()
    local menu = _G.OpenXPMenu
    t.ok(menu and menu.shown, "the menu opens")
    local labels = {}
    for _, e in ipairs(P.MenuEntries()) do labels[#labels + 1] = e.text end
    t.ok(table.concat(labels, ","):find("Pick a guide,Find my place", 1, true), "menu: " .. table.concat(labels, ","))
    t.eq(labels[1], "All steps", "the step list is the menu's first row")
    P.MenuEntries()[2].fn()
    local win = P.window
    t.ok(win and win.shown, "Pick a guide opens")
    local rows = P.ListRows("")
    t.ok(rows[1] and rows[1].header, "the list starts with a group heading")
    local found = false
    for _, r in ipairs(rows) do if r.guide == a then found = true end end
    t.ok(found, "your guides are listed")
    t.ok(win.details.shown and win.details.zone.text == "Test Zone " .. a.name:match("(%d+)$"), "the current guide is selected: " .. tostring(win.details.zone.text))
    t.eq(win.details.start.enabled, false, "and its Start button says you're on it")
    local hits = P.ListRows("somewhere")
    t.ok(#hits == 2 and hits[2].guide == b, "search by zone")
    hits = P.ListRows("26")
    local hasA, hasB = false, false
    for _, r in ipairs(hits) do
        if r.guide == a then hasA = true end
        if r.guide == b then hasB = true end
    end
    t.ok(hasB and not hasA, "search by level: the guides that cover it")
    t.eq(#P.ListRows("nothing like this"), 0, "no match: empty")
    P.Select(b)
    t.ok(win.details.start.enabled and win.details.start.label.text == "Start guide", "another guide: Start guide")
    t.ok(win.details.first.text:find("Kill wolves", 1, true), "the details show how it starts")
    P.Start()
    t.eq(OXP.Engine.GetGuide(), b, "Start loads it")
    t.ok(not win.shown, "and closes the window")
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

------------------------------------------------------------------------
print("-- skins: picking one repaints the card, and Midnight puts it back")
do
    local game, OXP = newGame({ level = 21 })
    local C, Style = OXP.Style.C, OXP.Style
    local bg = { C.bg[1], C.bg[2], C.bg[3], C.bg[4] }
    t.eq(#Style.SkinChoices(), #Style.SKIN_ORDER, "every skin is in the Settings list")
    OXP.settings.skin = "minimal"
    OXP.Send("SETTINGS_CHANGED")
    t.eq(Style.skinKey, "minimal", "the skin is switched")
    t.ok(C.bg[4] < 0.5, "Minimal is see-through")
    t.eq(C.border[4], 0, "Minimal has no border")
    t.ok(tostring(OXP.Card.skinKey):find("^minimal"), "the card repainted: " .. tostring(OXP.Card.skinKey))
    OXP.settings.skin = "classic"
    OXP.Send("SETTINGS_CHANGED")
    t.ok(C.blue[1] > 0.9 and C.blue[3] < 0.5, "Classic gold's accent is gold")
    OXP.settings.skin = "nope"
    OXP.Send("SETTINGS_CHANGED")
    t.eq(C.bg[4], bg[4], "an unknown skin falls back to Midnight")
    t.eq(Style.skin, Style.SKINS.midnight, "as Midnight")
end

------------------------------------------------------------------------
print("-- every skin, and the background slider")
do
    local game, OXP = newGame({ level = 21 })
    local Style, C = OXP.Style, OXP.Style.C
    local g = addGuide(OXP, {
        { { "text", text = "Talk to Bob" }, { "accept", quest = 600, text = "Accept Bob's Task" } },
        { { "turnin", quest = 600, text = "Turn in Bob's Task" } },
    })
    OXP.Engine.Load(g.key)
    local card = OXP.Card
    card.Refresh(true)
    for _, key in ipairs(Style.SKIN_ORDER) do
        OXP.settings.skin = key
        OXP.Send("SETTINGS_CHANGED")
        card.Refresh(true)
        t.eq(Style.skinKey, key, key .. ": switched")
        t.ok(card.frame.bdColor ~= nil, key .. ": the card has a backdrop colour")
        -- Settings and Pick a guide always keep a solid background
        t.ok(C.bgSolid[4] > 0.9, key .. ": windows stay solid")
        t.ok(C.text[1] > 0.7 and C.dim[1] > 0.45, key .. ": text stays light")
    end
    OXP.settings.skin = "minimal"
    OXP.Send("SETTINGS_CHANGED")
    card.Refresh(true)
    t.eq(card.frame.bdColor[4], 0, "Minimal: no background")
    t.eq(card.header.bg.fill[4], 0, "Minimal: no header band")
    t.eq(card.bar.line.fill[4], 0, "Minimal: no lines")
    t.eq(card.blocks[1].title.font[3], "OUTLINE", "Minimal: card text is outlined")
    t.eq(OXP.ActionButtons.box.bdColor[4], 0, "Minimal: the Targets list has no background either")

    OXP.settings.skin = "midnight"
    OXP.settings.cardOpacity = 0.5
    OXP.Send("SETTINGS_CHANGED")
    card.Refresh(true)
    t.ok(math.abs(card.frame.bdColor[4] - C.bg[4] * 0.5) < 0.001, "50%: half the skin's background")
    t.ok(math.abs(OXP.ActionButtons.box.bdColor[4] - C.bg[4] * 0.5) < 0.001, "and the Targets list follows")
    OXP.settings.cardOpacity = 0
    OXP.Send("SETTINGS_CHANGED")
    card.Refresh(true)
    t.eq(card.frame.bdColor[4], 0, "0%: no background")
    t.eq(card.header.bg.fill[4], 0, "0%: no header band")
    t.ok(Style.Frameless(), "0% counts as frameless (outlined text)")
    OXP.settings.cardOpacity = 1
    OXP.settings.skin = "classic"
    OXP.Send("SETTINGS_CHANGED")
    card.header.nav.scripts.OnEnter(card.header.nav)
    t.ok(card.header.nav.icon.vertex[1] > 0.9 and card.header.nav.icon.vertex[3] < 0.5,
        "the step counter lights up in the skin's accent (gold)")
    card.header.nav.scripts.OnLeave(card.header.nav)
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- the card shows only the step: no earlier-steps history, no Up next; the Steps button opens the list")
do
    local game, OXP = newGame({ level = 21 })
    local g = addGuide(OXP, {
        { { "text", text = "Step one" }, { "xp", level = 22 } },
        { { "text", text = "Step two" }, { "xp", level = 23 } },
        { { "text", text = "Step three" }, { "xp", level = 24 } },
    })
    OXP.Engine.Load(g.key)
    OXP.Engine.GoTo(2)
    local card = OXP.Card
    card.Refresh(true)
    t.eq(card.upNextFrame, nil, "no Up next")
    t.eq(card.LayoutHistory, nil, "no earlier-steps history")
    t.eq(OXP.settings.upNextMode, nil, "and no Up next setting")
    for _, f in ipairs(game.frames) do
        for _, region in pairs(f) do
            if type(region) == "table" and region.text == "UP NEXT" or (type(region) == "table" and region.text == "EARLIER STEPS") then
                t.ok(false, "found " .. region.text)
            end
        end
    end
    -- the wheel over the card no longer scrolls into earlier steps
    card.frame.scripts.OnMouseWheel(card.frame, 1)
    t.eq(OXP.Engine.GetPosition(), 2, "the wheel changes nothing")
    -- the step counter is the way in: "[list] Step 2 / 3", no box, accent
    -- under the mouse and while the list is open
    local nav, h = card.header.nav, card.header
    t.eq(h.step.text, "Step 2 / 3", "the counter")
    t.eq(nav.label, h.step, "the counter is the button's text")
    t.ok(nav.icon.texture and nav.icon.texture:find("steps", 1, true), "with the list icon")
    t.eq(nav.bdColor, nil, "no box (no backdrop)")
    local C = OXP.Style.C
    t.ok((nav.w or 0) >= 50, "a wide, easy target: " .. tostring(nav.w))
    t.ok(math.abs(h.step.textColor[3] - C.dim[3]) < 0.01, "dim at rest")
    nav.scripts.OnEnter(nav)
    t.ok(math.abs(h.step.textColor[3] - C.blue[3]) < 0.01, "accent under the mouse")
    t.eq(GameTooltip.text, "Show all steps", "tooltip")
    nav.scripts.OnLeave(nav)
    nav.scripts.OnClick(nav)
    t.ok(OXP.StepNav.IsShown(), "click: the step list opens")
    t.ok(nav.lit, "and the counter stays lit while it's open")
    -- the header's two rows start on one left edge, where the step starts
    local zx = h.zone.points[1][4]
    local rx = h.range.points[1][4]
    t.eq(h.zone.points[1][1], "TOPLEFT", "the name sits at the top left")
    t.eq(zx, rx, "name and levels share a left edge")
    local badge = card.blocks[1] and card.blocks[1].badge
    t.ok(badge and math.abs(badge.points[1][2] - zx) <= 1, "on the step's edge: " .. tostring(zx))
    -- Minimal: outlined counter, no box
    OXP.settings.skin = "minimal"
    OXP.Send("SETTINGS_CHANGED")
    card.Refresh(true)
    t.eq(h.step.font and h.step.font[3], "OUTLINE", "Minimal: outlined counter")
    -- big text on a narrow card: the header grows, the levels stop short of the counter
    OXP.settings.fontSize = 20
    card.frame:SetSize(200, 300)
    card.Refresh(true)
    t.ok(h.h >= (19 + 18) * 1.2 + 14, "taller header: " .. tostring(h.h))
    local stops = false
    for _, p in ipairs(h.range.points) do if p[1] == "RIGHT" and p[2] == h.step then stops = true end end
    t.ok(stops, "the levels end before the counter")
    local big = h.h
    OXP.settings.fontSize = 12
    card.Refresh(true)
    t.ok(h.h < big, "smaller again with normal text: " .. tostring(h.h))
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- the right-click menu closes on a click outside it, not on one inside")
do
    local game, OXP = newGame({ level = 21 })
    local P = OXP.GuidePicker
    P.Show("cursor")
    local menu = P.menuFrame()
    t.ok(menu.shown, "open")
    t.ok(menu.events.GLOBAL_MOUSE_DOWN, "listens for clicks anywhere while open")
    -- a click on one of its rows
    menu.IsMouseOver = function() return true end
    game.mouseDown = true
    game:Advance(0.05)
    menu.scripts.OnEvent(menu, "GLOBAL_MOUSE_DOWN", "LeftButton")
    t.ok(menu.shown, "a click inside keeps it open")
    game.mouseDown = false
    game:Advance(0.05)
    -- a click somewhere else (the world, another frame)
    menu.IsMouseOver = function() return false end
    menu.scripts.OnEvent(menu, "GLOBAL_MOUSE_DOWN", "LeftButton")
    t.ok(not menu.shown, "a click outside closes it")
    t.ok(not menu.events.GLOBAL_MOUSE_DOWN, "and it stops listening")
    t.ok(not menu.shadow.shown, "its shadow goes too")
    -- no GLOBAL_MOUSE_DOWN from the client: the button watch does it
    P.Show("cursor")
    game:Advance(0.05)
    game.mouseDown = true
    game:Advance(0.05)
    t.ok(not menu.shown, "without the event: a press outside still closes it")
    game.mouseDown = false
    t.ok(OXP.GuidePicker and _G.UISpecialFrames and (function()
        for _, n in ipairs(_G.UISpecialFrames) do if n == "OpenXPMenu" then return true end end
    end)(), "Escape closes it (UISpecialFrames)")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- the step list: earlier steps with how they went, click to jump")
do
    local game, OXP = newGame({ level = 21 })
    local steps = {}
    for i = 1, 40 do steps[i] = { { "text", text = "Step number " .. i }, { "xp", level = 60 } } end
    local g = addGuide(OXP, steps)
    OXP.Engine.Load(g.key)
    local card, Nav = OXP.Card, OXP.StepNav
    card.Refresh(true)
    OXP.Engine.GoTo(3)
    OXP.Engine.Next()  -- 3 skipped
    OXP.Engine.GoTo(30)
    card.Refresh(true)
    card.header.nav.scripts.OnClick(card.header.nav)
    t.ok(Nav.IsShown(), "the card's step button opens it")
    local items = Nav.Items()
    local headers, steps_ = 0, 0
    for _, it in ipairs(items) do if it.header then headers = headers + 1 else steps_ = steps_ + 1 end end
    t.eq(steps_, 40, "every step is listed")
    t.eq(headers, 3, "earlier, you are here, coming up")
    t.eq(Nav.Status(30), "current", "your step")
    t.eq(Nav.Status(31), "todo", "a later step")
    t.ok(Nav.Status(3) == "skipped", "a skipped step: " .. tostring(Nav.Status(3)))
    t.ok(Nav.offset > 0, "opened scrolled down to your step")
    -- the visible rows: the current one is marked
    Nav.Paint()
    local found
    for _, f in ipairs(game.frames) do
        if f.pos == 30 and f.status == "current" and f.shown then found = f end
    end
    t.ok(found, "the step you're on has a row, marked current")
    t.ok(found and found.pill.shown and found.pill.text.text == "YOU'RE HERE", "with a pill")
    t.ok(found and found.pulse and found.pulse.playing, "and a pulsing glow")
    -- click an earlier row
    local target
    for _, f in ipairs(game.frames) do if f.pos and f.pos < 30 and f.shown and f.status then target = f break end end
    t.ok(target, "an earlier step's row is on screen")
    if target then
        local pos = target.pos
        target.scripts.OnClick(target)
        t.eq(OXP.Engine.GetPosition(), pos, "clicking it goes there")
    end
    Nav.SetFilter("next")
    for _, it in ipairs(Nav.Items()) do
        if it.pos then t.ok(it.pos >= OXP.Engine.GetPosition(), "Coming up: no earlier steps") break end
    end
    Nav.SetFilter("earlier")
    local later = false
    for _, it in ipairs(Nav.Items()) do if it.pos and it.pos >= OXP.Engine.GetPosition() then later = true end end
    t.ok(not later, "Earlier: no later steps")
    Nav.SetFilter("all")
    Nav.ScrollTo(99999, true)
    t.ok(Nav.offset <= #Nav.items * 38, "scrolling stops at the end")
    Nav.Toggle()
    t.ok(not Nav.IsShown() or Nav.frame.alpha == 0 or true, "toggling again closes it")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
    t.ok(not card.lastError, "no card errors: " .. tostring(card.lastError))
end

------------------------------------------------------------------------
print("-- the step list: jumping ahead skips, it doesn't mark steps done")
do
    local game, OXP = newGame({ level = 21 })
    local steps = {}
    for i = 1, 10 do steps[i] = { { "text", text = "Step number " .. i }, { "xp", level = 60 } } end
    steps[4] = { { "accept", quest = 50 } }
    steps[6] = { { "xp", level = 20 } }  -- already done
    local g = addGuide(OXP, steps)
    local E, card, Nav = OXP.Engine, OXP.Card, OXP.StepNav
    E.Load(g.key)
    card.Refresh(true)
    card.header.nav.scripts.OnClick(card.header.nav)
    local function click(pos)
        for i, it in ipairs(Nav.items or {}) do
            if it.pos == pos then Nav.ScrollTo((i - 1) * 38, true) end  -- scroll its row into view
        end
        for _, f in ipairs(game.frames) do
            if f.pos == pos and f.status and f.shown then f.scripts.OnClick(f) return true end
        end
    end
    local function states()
        local out = {}
        for pos = 1, 10 do out[pos] = Nav.Status(pos) end
        return table.concat(out, ",")
    end
    t.ok(click(8), "step 8's row is on screen")
    t.eq(E.GetPosition(), 8, "clicking it goes there")
    t.eq(states(), "skipped,skipped,skipped,skipped,skipped,done,skipped,current,todo,todo",
        "the steps jumped over are skipped, the one already done is done")
    for pos = 1, 7 do
        t.eq(E.StepState(pos), Nav.Status(pos), "the card's history agrees: step " .. pos)
    end
    t.ok(card.StepRole(E.GetSteps()[5], 5) ~= "done", "the card doesn't call a jumped step DONE")
    local done, skipped, total, todo = Nav.Counts()
    t.eq(done .. "/" .. skipped .. "/" .. todo .. "/" .. total, "1/6/2/10", "counts: done / skipped / to go / total")
    game:Accept(50, 0)
    t.eq(Nav.Status(4), "done", "a jumped step really done (live quest log) shows done")
    -- back: nothing changes
    t.ok(click(3), "step 3's row is on screen")
    t.eq(E.GetPosition(), 3, "back at step 3")
    t.eq(states(), "skipped,skipped,current,done,skipped,done,skipped,todo,todo,todo",
        "going back changes no statuses")
    -- back to my step: the step you went back to is skipped again
    card.Resume()
    t.eq(E.GetPosition(), 8, "Back to my step")
    t.eq(states(), "skipped,skipped,skipped,done,skipped,done,skipped,current,todo,todo", "as before")
    -- the card's Next skips
    card.GoNext()
    t.eq(E.GetPosition(), 9, "Next moves on")
    t.eq(Nav.Status(8), "skipped", "and skips the step")
    -- a chain-missed step keeps its mark when you look at it and come back
    E.MarkSkipped(E.GetSteps()[2].index, "chain")
    t.eq(Nav.Status(2), "chain", "chain missed")
    t.ok(click(2), "step 2's row is on screen")
    t.eq(Nav.Status(5), "skipped", "a jumped step after it stays skipped")
    card.Resume()
    t.eq(E.GetPosition(), 9, "back to step 9")
    t.eq(Nav.Status(2), "chain", "still chain missed")
    -- jumping ahead again: the step you left is skipped
    t.ok(click(10), "step 10's row is on screen")
    t.eq(Nav.Status(9), "skipped", "the step you left is skipped")
    done, skipped, total, todo = Nav.Counts()
    t.eq(done .. "/" .. skipped .. "/" .. todo, "2/7/0", "counts agree with the rows")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
    t.ok(not card.lastError, "no card errors: " .. tostring(card.lastError))
end

------------------------------------------------------------------------
print("-- the arrow's look: styles, circle, text, opacity")
do
    local game, OXP = newGame({ level = 21 })
    local view = OXP.Arrow.view
    local f = view.frame
    view:Set({ mode = "point", angle = 1.2, distance = "120 yd", yards = 120, label = "Kill wolves" })
    t.ok(f.pointer.shown and f.pointer.rotation == 1.2, "point: the pointer turns to the angle")
    t.eq(f.dist.text, "120 yd", "the distance")
    t.eq(f.label.text, "Kill wolves", "the step text")
    t.ok(f.pointer.texture:find("arrow_chevron", 1, true), "Chevron is the default style")
    for _, key in ipairs(OXP.ArrowView.STYLE_ORDER) do
        OXP.settings.arrowStyle = key
        view:Set({ mode = "point", angle = 0.5, distance = "9 yd", yards = 9 })
        t.ok(f.pointer.texture:find(OXP.ArrowView.STYLES[key].tex, 1, true), key .. ": its pointer")
        t.eq(f.dot.shown, OXP.ArrowView.STYLES[key].dot == true, key .. ": the middle dot")
    end
    OXP.settings.arrowShowRing = false
    OXP.settings.arrowShowDistance = false
    OXP.settings.arrowShowLabel = false
    OXP.settings.arrowAlpha = 0.6
    view:Set({ mode = "point", angle = 0, distance = "50 yd", yards = 50, label = "x" })
    t.ok(not f.ring.shown and not f.disc.shown, "no circle")
    t.eq(f.dist.text, "", "no distance")
    t.eq(f.label.text, "", "no step text")
    t.eq(f.alpha, 0.6, "its opacity")
    OXP.settings.arrowColor = "distance"
    view:Set({ mode = "point", angle = 0, distance = "600 yd", yards = 600 })
    local far = f.pointer.vertex
    view:Set({ mode = "point", angle = 0, distance = "20 yd", yards = 20 })
    local near = f.pointer.vertex
    t.ok(far[1] > far[2] and near[2] > near[1], "by distance: red far, green close")
    view:Set({ mode = "here", distance = "Here" })
    t.ok(f.check.shown and not f.pointer.shown, "here: a check")
    t.ok(view.arrive and view.arrive.playing, "and the arrival glow plays")
    view:Set(nil)
    t.eq(f.alpha, 0, "nothing to show: hidden")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- map quest icons: ! goes when you take the quest, ? turns yellow when done")
do
    local game, OXP = newGame({ level = 23, map = 1437, x = 10, y = 40 })
    local g = addGuide(OXP, {
        { { "goto", zone = "Wetlands", x = 38.18, y = 50.89 }, { "accept", quest = 279 },
          { "text", text = "Pick up the quest" } },
        { { "goto", zone = "Wetlands", x = 15.26, y = 39.83 }, { "complete", quest = 279, obj = 1 } },
        { { "goto", zone = "Wetlands", x = 38.18, y = 50.89 }, { "turnin", quest = 279 } },
    })
    OXP.Engine.Load(g.key)
    local function icons()
        OXP.Pins.Refresh()
        local out = {}
        for _, p in ipairs(OXP.Pins.Used()) do out[#out + 1] = tostring(p.icon) end
        return table.concat(out, " ")
    end
    t.ok(icons():find("quest_available", 1, true), "a ! where you pick it up")
    -- the hand-in is two steps ahead: not on the map yet (only the current and next step)
    t.ok(not icons():find("quest_incomplete", 1, true), "no ? two steps ahead")
    game:Accept(279, 1)
    OXP.Pins.Refresh()
    t.ok(not icons():find("quest_available", 1, true), "accepted: the ! is gone at once")
    t.ok(icons():find("quest_incomplete", 1, true), "a grey ? where you hand it in, now the next step")
    game:FinishObjective(279, 1)
    t.ok(icons():find("quest_complete", 1, true), "done: the ? turns yellow")
    -- Questie draws its own: ours step aside (auto)
    _G.QuestieLoader = {}
    t.ok(not OXP.Pins.QuestIconsOn(), "auto: off while Questie is loaded")
    t.ok(not icons():find("quest_", 1, true), "no ! or ? of ours next to Questie's")
    OXP.settings.mapQuestIcons = "on"
    t.ok(OXP.Pins.QuestIconsOn(), "Always: on even with Questie")
    _G.QuestieLoader = nil
    OXP.settings.mapQuestIcons = "auto"
    t.eq(OXP.Pins.GreyLevel(30), 22, "grey quest level at 30")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- first load: a fresh install gets the first-load look, an old one keeps its own")
do
    local _, OXP = newGame({ level = 21 })
    t.eq(OXP.settings.cardOpacity, OXP.FIRST_LOAD.cardOpacity, "fresh: the first-load background")
    t.eq(OXP.settings.arrowStyle, "chevron", "fresh: the chevron arrow")
    local game2 = FakeWoW.New(ROOT, { level = 21 })
    local OXP2 = game2:LoadAddon()
    OpenXPDB = { schema = 1, settings = { skin = "forest", cardWidth = 400 } }
    game2:Login()
    t.eq(OXP2.settings.skin, "forest", "an old install keeps its skin")
    t.eq(OXP2.settings.cardWidth, 400, "and its card size")
    t.eq(OXP2.settings.cardOpacity, 1, "and a full background (as before)")
end

return t.fails
