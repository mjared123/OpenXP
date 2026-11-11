-- Smoke test for OpenXPCard.lua with a stand-in WoW API: builds the card,
-- lays out a few steps, collapses it and draws the arrow. Catches nil
-- errors and bad calls; it doesn't check how things look.
local ROOT = ...
unpack = unpack or table.unpack
tinsert = table.insert
local calls = {}
local function obj(name)
    local o = {__name = name, shown = true}
    return setmetatable(o, {__index = function(t, k)
        if type(k) ~= "string" or k:match("^[a-z_]") then return nil end -- fields, not methods
        if k == "GetStringHeight" then return function() return 14 end end
        if k == "GetStringWidth" then return function() return 60 end end
        if k == "GetLeft" then return function() return 100 end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
        if k == "GetWidth" or k == "GetHeight" then return function() return 100 end end
        if k == "SetScript" then return function(self, ev, fn) rawset(self, "_" .. ev, fn) end end
        if k == "GetScript" then return function(self, ev) return rawget(self, "_" .. ev) end end
        if k == "SetText" then return function(self, t) rawset(self, "_text", t) end end
        if k == "GetText" then return function(self) return rawget(self, "_text") end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateAnimationGroup" then
            return function() return obj(k) end
        end
        return function() end
    end})
end
function CreateFrame(kind, name) return obj(kind) end
UIParent = obj("UIParent")
GameTooltip = obj("GameTooltip")
C_Timer = {After = function(_, fn) fn() end}

local stepSkip = {}
OXPCData = {stepSkip = stepSkip}
local function el(t) return t end
local steps = {
    {index = 1, elements = {el{textOnly = true, text = "Talk to |cFF00FF25Lord Ello|r"},
                            el{tag = "turnin", text = "Turn in Worgen in the Woods", completed = true},
                            el{tag = "accept", text = "Accept The Night Watch"}}},
    {index = 2, elements = {el{textOnly = true, text = "Kill Nightbane Shadow Weavers"},
                            el{tag = "complete", text = "Nightbane Shadow Weaver slain: 4/8"},
                            el{tag = "goto"}}},
    {index = 3, elements = {el{tag = "fp", text = "Get the Darkshire flight path"}}},
}
for i = 4, 20 do
    steps[i] = {index = i, elements = {el{textOnly = true, text = "Step text " .. i}}}
end
local addon = {
    locale = {Get = function(s) return s end},
    settings = {profile = {guideFontSize = 12, arrowScale = 1, windowScale = 1},
                OpenSettings = function() end},
    currentGuide = {name = "28-30 Duskwood", steps = steps},
    RXPFrame = obj("RXPFrame"),
    GetGuideProgress = function() return 1 end,
    SetStep = function(n) calls.setStep = n end,
    -- like the engine: indexes element.step whenever an element is passed
    ReplaceNpcIds = function(t, e) if e then local _ = e.step.active end return t end,
    arrowFrame = obj("arrow"),
    v2 = {IsGuideWindowEnabled = function() return false end},
}
addon.RXPFrame.activeSteps = {steps[1], steps[2]}
addon.arrowFrame.texture = obj("tex")
addon.arrowFrame.text = obj("fs")
addon.DrawArrow = function(self) self.distance = 142; self.element = {title = "Lord Ello"} end
addon.SetupArrow = function() end

local chunk = assert(loadfile(ROOT .. "/OpenXPCard.lua"))
chunk("OpenXP", addon)
local card = addon.card
local fails = 0
local function try(label, fn)
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end
try("enable and lay out two steps", function() card.Enable() end)
try("refresh again", function() card.Refresh() end)
try("collapse", function() card.SetCollapsed(true) end)
try("expand", function() card.SetCollapsed(false) end)
try("arrow update", function()
    local af = addon.arrowFrame
    local fn = assert(af:GetScript("OnUpdate"), "no arrow OnUpdate")
    fn(af)
    af.distance = 3
    addon.DrawArrow = function(self) end
    fn(af)
end)
try("arrow draw", function()
    -- call the installed update directly
    local af = addon.arrowFrame
    assert(type(af.oxpDist) == "table", "arrow not styled")
end)
try("finished guide (no active steps)", function()
    addon.RXPFrame.activeSteps = {}
    card.Refresh()
end)
try("guide with no range in its name", function()
    addon.currentGuide = {name = "Zephras Isle", steps = steps}
    card.Refresh()
end)
try("resize with the corner grip (wide and tall)", function()
    addon.RXPFrame.activeSteps = {steps[1], steps[2]}
    addon.currentGuide = {name = "28-30 Duskwood", steps = steps}
    local f, grip = card.frame, card.grip
    assert(grip, "no grip")
    local sized
    f.StartSizing = function() sized = true end
    f.GetWidth = function() return 420 end
    f.GetHeight = function() return 520 end
    local heights = {}
    f.SetHeight = function(_, h) heights[#heights + 1] = h end
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    assert(sized and card.sizing, "sizing did not start")
    grip:GetScript("OnUpdate")(grip)
    grip:GetScript("OnMouseUp")(grip)
    assert(not card.sizing, "still sizing")
    local p = addon.settings.profile
    assert(p.openxpCardWidth == 420 and p.openxpCardHeight == 520, "size not saved")
    assert(heights[#heights] >= 520, "height not kept: " .. tostring(heights[#heights]))
end)
try("locked frames ignore the grip", function()
    addon.settings.profile.lockFrames = true
    card.sizing = false
    card.grip:GetScript("OnMouseDown")(card.grip, "LeftButton")
    assert(not card.sizing, "resized while locked")
    addon.settings.profile.lockFrames = nil
end)
try("narrow card hides the Find my place label", function()
    card.width = 290
    card.Refresh()
end)
try("reset position and size", function()
    card.ResetPosition()
    local p = addon.settings.profile
    assert(p.openxpCardWidth == nil and p.openxpCardPos == nil and card.width == nil, "not reset")
end)
try("hidden when the engine hides its window", function()
    addon.RXPFrame.shown = false
    card.Refresh()
    assert(not card.frame.shown, "card still shown")
    addon.RXPFrame.shown = true
end)
try("font size change applies on the next redraw", function()
    addon.settings.profile.guideFontSize = 16
    card.Refresh(true)
    addon.settings.profile.guideFontSize = 12
end)
try("turn in for a quest not in the log offers skip / get", function()
    steps[5] = {index = 5, elements = {el{tag = "accept", questId = 581, text = "Accept The Night Watch"}}}
    steps[9] = {index = 9, elements = {el{tag = "turnin", questId = 581, title = "The Night Watch",
                                         text = "Turn in The Night Watch"}}}
    addon.currentGuide = {name = "28-30 Duskwood", steps = steps}
    local log = {}
    addon.IsOnQuest = function(id) return log[id] end
    addon.IsQuestTurnedIn = function() return false end
    addon.RXPFrame.activeSteps = {steps[9]}
    card.Refresh(true)
    local b = card.blocksForTest and card.blocksForTest[1]
    local id = card.MissingQuest(steps[9])
    assert(id == 581, "missing quest not found")
    assert(card.FindAcceptStep(addon.currentGuide, 581, 9) == 5, "accept step not found")
    assert(b and b.missing and b.missing.accept == 5, "no warning on the block")
    b.warn.get:GetScript("OnClick")()
    assert(calls.setStep == 5, "did not go to the pickup step")
    log[581] = true
    card.frame.shown = true
    -- ticker brings us back once the quest is in the log
    card.TickForTest()
    assert(calls.setStep == 9, "did not return after pickup: " .. tostring(calls.setStep))
    log[581] = nil
    card.Refresh(true)
    b.warn.skip:GetScript("OnClick")()
    assert(calls.setStep == 10, "skip did not move on")
    log[581] = true
    assert(card.MissingQuest(steps[9]) == nil, "warned with the quest in the log")
end)
try("pickup behind a quest chain offers the chain, then walks it", function()
    card.data.prereqs = {[4733] = {any = {4681}}, [4681] = {any = {3524}}, [600] = {excl = {601}}}
    card.data.chains = {[4733] = {3524, 4681}, [4681] = {3524}}
    card.data.info = {
        [3524] = {n = "Washed Ashore", l = 13, r = 11, s = {"Gwennyth", 1439, 36.6, 45.6}, f = {"Gwennyth", 1439, 36.6, 45.6}, o = {{"Beached Sea Creature", 1439, 36.4, 50.9}}},
        [4681] = {n = "Washed Ashore", l = 14, r = 11, s = {"Gwennyth", 1439, 36.6, 45.6}, f = {"Gwennyth", 1439, 36.6, 45.6}, o = {}},
        [4733] = {n = "Beached Sea Creature", l = 19, r = 13, s = {"Beached Sea Creature", 1439, 31.3, 87.4}, f = {"Gwennyth", 1439, 36.6, 45.6}, o = {}},
    }
    local done, log = {}, {}
    addon.IsQuestTurnedIn = function(id) return done[id] end
    addon.IsOnQuest = function(id) return log[id] end
    C_QuestLog = {GetQuestObjectives = function() return {{text = "Sea Turtle Remains: 0/1", finished = false}} end}
    UnitLevel = function() return 19 end
    steps[12] = {index = 12, elements = {el{tag = "accept", questId = 4733, text = "Accept Beached Sea Creature"}}}
    addon.currentGuide = {name = "19-21 Darkshore/Ashenvale", steps = steps}
    addon.GetGuideProgress = function() return 12 end
    addon.RXPFrame.activeSteps = {steps[12]}

    local pr = card.StepProblem(steps[12])
    assert(pr and pr.kind == "chain" and #pr.chain == 2, "chain not found")
    card.Refresh(true)
    local b = card.blocksForTest[1]
    assert(b.missing and b.warn.chain.shown and b.warn.skip.shown, "chain buttons not shown")
    calls.setStep = nil
    card.TickForTest()
    assert(calls.setStep == nil, "pickup step was auto-skipped")

    b.warn.chain:GetScript("OnClick")()
    assert(card.detour and #card.detour.ids == 2 and card.detour.mode == "available", "chain walk not started")
    local st, idx = card.DetourStep()
    assert(idx == 1 and st.elements[2].tag == "accept", "should pick up the first chain quest")
    log[3524] = true
    st, idx = card.DetourStep()
    assert(st.elements[1].text:find("Do Washed Ashore"), "should do the objectives")
    C_QuestLog = {GetQuestObjectives = function() return {{text = "done", finished = true}} end}
    st = card.DetourStep()
    assert(st.elements[2].tag == "turnin", "should turn in")
    log[3524] = nil; done[3524] = true
    st, idx = card.DetourStep()
    assert(idx == 2, "should move on to quest 2")
    card.TickForTest()
    assert(card.detour, "walk ended too early")
    done[4681] = true
    card.TickForTest()
    assert(not card.detour, "walk did not end once the quest could be picked up")
    assert(not card.StepProblem(steps[12]), "still a problem after the chain")

    done[601] = true
    steps[13] = {index = 13, elements = {el{tag = "accept", questId = 600}}}
    assert(card.StepProblem(steps[13]).kind == "locked", "exclusive quest not honoured")
    -- turn in for a chain quest you never got: the walk ends with picking it up
    done[4681] = nil
    steps[14] = {index = 14, elements = {el{tag = "turnin", questId = 4733}}}
    pr = card.StepProblem(steps[14])
    assert(pr.kind == "chain" and pr.needAccept, "turn in behind a chain")
    addon.GetGuideProgress = function() return 1 end
end)
try("reads quest chains from Questie when it's installed", function()
    card.data = {}
    local quests = {
        [3524] = {name = "Washed Ashore", level = 13, requiredLevel = 11, startedBy = {{10219}}, finishedBy = {{10219}},
                  objectives = {nil, {{175226}}}, zoneOrSort = 148},
        [4681] = {name = "Washed Ashore", level = 14, requiredLevel = 11, preQuestSingle = {3524},
                  startedBy = {{10219}}, finishedBy = {{10219}}, zoneOrSort = 148},
        [4733] = {name = "Beached Sea Creature", level = 19, requiredLevel = 13, preQuestSingle = {4681},
                  startedBy = {nil, {175230}}, finishedBy = {{10219}}, zoneOrSort = 148},
    }
    local npcs = {[10219] = {name = "Gwennyth", spawns = {[148] = {{36.6, 45.6}}}}}
    local objs = {[175230] = {name = "Beached Sea Creature", spawns = {[148] = {{31.3, 87.4}}}},
                  [175226] = {name = "Beached Sea Creature", spawns = {[148] = {{36.4, 50.9}, {36.5, 51}}}}}
    local db = {GetQuest = function(_, id) return quests[id] end, GetNPC = function(_, id) return npcs[id] end,
                GetObject = function(_, id) return objs[id] end, GetItem = function() end}
    QuestieLoader = {ImportModule = function(_, name)
        if name == "QuestieDB" then return db end
        return {GetUiMapIdByAreaId = function(_, a) return a == 148 and 1439 or nil end}
    end}
    local done = {}
    addon.IsQuestTurnedIn = function(id) return done[id] end
    addon.IsOnQuest = function() return false end
    local chain = card.Chain(4733)
    assert(#chain == 2 and chain[1] == 3524 and chain[2] == 4681, "chain from Questie: " .. table.concat(chain, ","))
    local info = card.QuestInfoOf(4733)
    assert(info.n == "Beached Sea Creature" and info.l == 19 and info.s[2] == 1439, "info from Questie")
    assert(info.f[1] == "Gwennyth", "turn in NPC")
    assert(card.QuestBlocked(4733) == 4681, "blocked by Questie prereq")
    done[3524], done[4681] = true, true
    assert(not card.QuestBlocked(4733), "not blocked once done")
    QuestieLoader = nil
end)
try("/oxp step debug output", function()
    addon.RXPFrame.activeSteps = {steps[1], steps[9]}
    print = print or function() end
    local text = card.DebugStep()
    assert(text:find("step:") and text:find("problem:"), "debug output")
end)
try("current step first, background steps labelled, finished steps marked done", function()
    local bookStep = {index = 7, completewith = "TheryluneEnd", elements = {el{textOnly = true, text = "Loot the book"}, el{tag = "collect", questId = 968, text = "Book: 0/1"}}}
    local now = {index = 8, elements = {el{textOnly = true, text = "Talk to Therylune"}, el{tag = "accept", questId = 945, text = "Accept Therylune's Escape"}}}
    local doneStep = {index = 6, elements = {el{tag = "turnin", questId = 729, text = "Turn in", completed = true}}}
    addon.GetGuideProgress = function() return 8 end
    assert(card.StepRole(bookStep, 8) == "side", "book step should be side")
    assert(card.StepRole(now, 8) == "now", "Therylune is now")
    assert(card.StepRole(doneStep, 8) == "done", "finished step is done")
    addon.RXPFrame.activeSteps = {bookStep, now}
    card.data = {prereqs = {}, chains = {}, info = {}}
    card.Refresh(true)
    local t1, t2 = card.blocksForTest[1].title:GetText(), card.blocksForTest[2].title:GetText()
    assert(t1:find("Therylune") and not t1:find("ALONG"), "current step not first: " .. tostring(t1))
    assert(t2:find("ALONG THE WAY") and t2:find("book"), "book step not labelled: " .. tostring(t2))
    addon.GetGuideProgress = function() return 1 end
end)
try("turn in for a quest you have but haven't finished offers Finish it", function()
    card.data = {prereqs = {}, chains = {}, info = {[951] = {n = "Mathystra Relics", l = 17, r = 12, o = {{"Relic", 1439, 50, 20}}}}}
    local complete = false
    addon.IsOnQuest = function(id) return id == 951 end
    addon.IsQuestTurnedIn = function() return false end
    addon.IsQuestComplete = function() return complete end
    C_QuestLog = {GetQuestObjectives = function() return {{text = "Mathystra Relic: 2/6", finished = false}} end}
    steps[19] = {index = 19, elements = {el{tag = "turnin", questId = 951, text = "Turn in Mathystra Relics"}}}
    addon.currentGuide = {name = "19-21 Darkshore/Ashenvale", steps = steps}
    addon.GetGuideProgress = function() return 19 end
    addon.RXPFrame.activeSteps = {steps[19]}
    local pr = card.StepProblem(steps[19])
    assert(pr and pr.kind == "unfinished", "unfinished not detected")
    card.Refresh(true)
    local b = card.blocksForTest[1]
    assert(b.warn.finish.shown and b.warn.skip.shown, "Finish it / Skip not shown")
    b.warn.finish:GetScript("OnClick")()
    assert(card.detour and card.detour.mode == "complete", "finish walk not started")
    local st = card.DetourStep()
    assert(st and st.elements[1].text:find("Do Mathystra Relics"), "walk should show the objectives")
    card.TickForTest()
    assert(card.detour, "ended early")
    complete = true
    card.TickForTest()
    assert(not card.detour, "walk did not end when the quest was complete")
    assert(not card.StepProblem(steps[19]), "still a problem once complete")
    addon.GetGuideProgress = function() return 1 end
end)
try("narrowest card (220) lays out with slim buttons", function()
    card.width = 220
    addon.RXPFrame.activeSteps = {steps[1], steps[2]}
    card.Refresh(true)
    card.width = nil
end)
try("other panels get the card look", function()
    local panel = obj("RXPItemFrame")
    panel.title = obj("title")
    panel.title.text = obj("fs")
    panel.title.text.GetFont = function() return "Fonts\\FRIZQT__.TTF", 9 end
    panel.title.text:SetText("Active Items")
    RXPItemFrame = panel
    card.SkinPanels()
    assert(panel.title.text:GetText() == "ACTIVE ITEMS", "title not restyled")
    RXPItemFrame = nil
    card.width = 200
    card.Refresh(true)
    card.width = nil
end)
try("going back to a finished step holds there until you press Next", function()
    addon.currentGuide = {name = "19-21 Darkshore/Ashenvale", steps = steps}
    local cur = 42
    for i = 21, 45 do steps[i] = steps[i] or {index = i, elements = {}} end
    steps[41].sticky = true
    steps[40].completed = true
    addon.GetGuideProgress = function() return cur end
    addon.RXPFrame.activeSteps = {steps[40]}
    addon.SetStep = function(n) calls.setStep = n; cur = n end
    card.guardedSetStep = nil
    card.GuardSetStep()
    OXPCData.stepSkip = {}
    assert(card.GoBack(), "could not go back")
    assert(cur == 40, "should land on 40, got " .. cur)
    -- the engine sees the step is done and tries to move on: held
    addon.SetStep(41)
    assert(cur == 40, "engine bounced forward to " .. cur)
    assert(card.hold and card.hold.from == 42, "should remember step 42")
    card.Refresh(true)
    -- Back to 42
    card.Resume()
    assert(cur == 42, "resume went to " .. cur)
    -- Next marks an unfinished step as skipped
    card.JumpTo(43)
    card.GoNext()
    assert(cur == 44 and card.StepStatus(addon.currentGuide, 43, 44) == "skipped", "not marked skipped")
    steps[41].sticky = nil
    card.hold = nil
    addon.SetStep = function(n) calls.setStep = n end
end)
try("history rows show done, skipped and chain missed", function()
    addon.currentGuide = {name = "hist", steps = steps}
    addon.GetGuideProgress = function() return 6 end
    steps[2].completed = true
    OXPCData.stepSkip = {[3] = true}
    card.MarkStatus(addon.currentGuide, 4, "chain")
    assert(card.StepStatus(addon.currentGuide, 2, 6) == "done")
    assert(card.StepStatus(addon.currentGuide, 3, 6) == "skipped")
    assert(card.StepStatus(addon.currentGuide, 4, 6) == "chain")
    card.ScrollHistory(1); card.ScrollHistory(1); card.ScrollHistory(1)
    assert(card.histOffset == 3, "offset " .. tostring(card.histOffset))
    assert(card.hist.rows[1] and card.hist.rows[1].status ~= nil, "no rows")
    card.ScrollHistory(-1); card.ScrollHistory(-1); card.ScrollHistory(-1)
    assert(card.histOffset == 0)
    steps[2].completed = nil
    OXPCData.stepSkip = {}
    addon.GetGuideProgress = function() return 1 end
end)
try("skipped-to step survives a reload", function()
    addon.currentGuide = {name = "19-21 Darkshore/Ashenvale", steps = steps}
    local cur = 42
    addon.GetGuideProgress = function() return cur end
    card.restored = true
    card.RememberStep()
    assert(OXPCData.openxpSteps["19-21 Darkshore/Ashenvale"] == 42, "not saved")
    -- reload: engine comes back on an earlier step
    card.restored = false
    cur = 20
    calls.setStep = nil
    card.RestoreStep()
    assert(calls.setStep == 42, "not restored")
    addon.GetGuideProgress = function() return 1 end
end)
try("mob and NPC tooltips", function()
    strsplit = function(sep, str)
        local out = {}
        for part in (str .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
        return unpack(out)
    end
    UnitExists = function() return true end
    UnitIsPlayer = function() return false end
    UnitCanAttack = function() return true end
    UnitName = function() return "Nightbane Shadow Weaver" end
    UnitGUID = function() return "Creature-0-1-2-3-940-0000" end
    GetNumQuestLogEntries = function() return 2 end
    GetQuestLogTitle = function(i) if i == 1 then return "Duskwood", 0, nil, true end return "The Night Watch", 25 end
    GetNumQuestLeaderBoards = function() return 1 end
    GetQuestLogLeaderBoard = function() return "Nightbane Shadow Weaver slain: 4/8", "monster", false end
    steps[2].elements[4] = {mobs = {"Nightbane Shadow Weaver"}}
    assert(loadfile(ROOT .. "/OpenXPTooltips.lua"))("OpenXP", addon)
    local tips = addon.openxpTooltips
    local q = tips.QuestLines("Nightbane Shadow Weaver")
    assert(#q == 1 and q[1].have == 4 and q[1].need == 8, "quest progress not found")
    local idx, what = tips.GuideStep("Nightbane Shadow Weaver", 940)
    assert(idx == 2 and what == "Kill", "guide step not found: " .. tostring(idx))
    local lines = {}
    local tt = {AddLine = function(_, l) lines[#lines + 1] = l end,
                AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. b end, Show = function() end}
    tips.AddLines(tt, "mouseover")
    local all = table.concat(lines, "\n")
    assert(all:find("The Night Watch") and all:find("4/8") and all:find("step 2"), all)
    steps[2].elements[4] = nil
end)
try("step list opens, scrolls and jumps", function()
    card.ToggleStepList()
    card.FillStepList()
    card.JumpTo(3)
    assert(calls.setStep == 3, "did not jump")
    card.ToggleStepList()
end)
try("timer bars dock under the card", function()
    addon.RXPFrame.BarContainer = obj("bars")
    addon.RXPFrame.BarContainer.bars = {a = 1}
    card.DockTimers()
end)
try("xp strip and time to level", function()
    local xp, t = 1000, 0
    UnitXP = function() return xp end
    UnitXPMax = function() return 4000 end
    UnitLevel = function() return 20 end
    GetXPExhaustion = function() return 500 end
    GetTime = function() return t end
    card.ResetXPSession()
    card.UpdateXP()
    t, xp = 600, 2000
    local x = card.XPStats()
    assert(x.perHour and math.floor(x.perHour) == 6000, "xp/hour " .. tostring(x.perHour))
    assert(math.floor(x.minutes) == 20, "minutes " .. tostring(x.minutes))
    card.xpStrip:GetScript("OnEnter")(card.xpStrip)
    GetTime = nil
end)
try("trainer step is done once you've talked to the trainer", function()
    local done
    addon.SetElementComplete = function(e) done = e; e.completed = true end
    addon.GetNpcId = function() return 4205 end
    UnitLevel = function() return 20 end
    UnitName = function() return "Karrina Mekenda" end
    local tr = {tag = "trainer", text = "Train your pet skills"}
    local step = {index = 43, elements = {tr, {targets = {"Karrina Mekenda"}}}}
    addon.RXPFrame.activeSteps = {}
    card.RecordTrainerVisit()          -- talked to her before the step came up
    addon.RXPFrame.activeSteps = {step}
    card.CheckTrainerSteps()
    assert(done == tr, "trainer step not completed")
    -- a visit at a lower level doesn't count after you level up
    tr.completed, done = nil, nil
    UnitLevel = function() return 22 end
    card.CheckTrainerSteps()
    assert(not done, "old visit counted")
    addon.RXPFrame.activeSteps = {}
end)
try("a go-here step you've run past counts as done", function()
    local done
    addon.SetElementComplete = function(e) done = e; e.completed = true end
    local wp = {tag = "goto", wx = 0, wy = 0, radius = 30, instance = 1}
    local s = {
        {index = 1, elements = {{textOnly = true, text = "Head up the ramp"}, wp}},
        {index = 2, elements = {{tag = "goto", wx = 400, wy = 0, instance = 1}, {tag = "trainer"}}},
    }
    addon.currentGuide = {name = "ramp", steps = s}
    addon.GetGuideProgress = function() return 1 end
    card.hold = nil
    assert(not card.CheckTravelSteps(-50, 0, 1) and not done, "completed before getting there")
    assert(not card.CheckTravelSteps(300, 0, 2) and not done, "completed on another continent")
    assert(card.CheckTravelSteps(300, 0, 1) and done == wp, "not completed after running past")
    -- a step with something else to do is left alone
    done = nil
    wp.completed = nil
    s[1].elements[3] = {tag = "accept", questId = 5}
    assert(not card.CheckTravelSteps(300, 0, 1) and not done, "completed a quest step")
    addon.currentGuide = {name = "28-30 Duskwood", steps = steps}
end)
try("skipped quest chains list reads the guide, not just the last Smart start", function()
    assert(loadfile(ROOT .. "/SmartStart.lua"))("OpenXP", addon)
    local SS = addon.smartStart
    SS.api.IsTurnedIn = function() return false end
    SS.cachedPrereqs = {}
    addon.IsOnQuest = function() return false end
    addon.IsQuestTurnedIn = function() return false end
    local s = {
        {index = 1, elements = {{tag = "accept", questId = 101}}},
        {index = 2, elements = {{tag = "accept", questId = 102}}},
        {index = 3, elements = {{tag = "accept", questId = 103}}},
        {index = 4, elements = {{textOnly = true, text = "now"}}},
    }
    addon.currentGuide = {name = "chains", steps = s}
    addon.GetGuideProgress = function() return 4 end
    card.MarkStatus(addon.currentGuide, 1, "skipped")
    card.MarkStatus(addon.currentGuide, 2, "chain")
    local list = SS.SkippedChains()
    assert(#list >= 2, "found " .. #list)
    local printed = {}
    addon.comms = {PrettyPrint = function(m) printed[#printed + 1] = m end}
    SS.ShowCatchUp()
    assert(printed[1] and printed[1]:find("skipped quest"), tostring(printed[1]))
    addon.comms = nil
    addon.currentGuide = {name = "28-30 Duskwood", steps = steps}
    addon.GetGuideProgress = function() return 1 end
end)
try("breadcrumb: closed once you have or did the quest it leads to", function()
    card.data.breadcrumbs = {[165] = 148}
    local done, log = {}, {}
    addon.IsQuestTurnedIn = function(id) return done[id] end
    addon.IsOnQuest = function(id) return log[id] end
    assert(card.BreadcrumbFor(165) == 148 and card.BreadcrumbFor(148) == nil)
    assert(card.BreadcrumbClosed(165) == nil, "nothing yet: The Hermit is open")
    log[148] = true
    assert(card.BreadcrumbClosed(165) == 148, "Supplies from Darkshire in the log closes it")
    log[148], done[148] = nil, true
    assert(card.BreadcrumbClosed(165) == 148, "and so does having done it")
    log[165] = true
    assert(card.BreadcrumbClosed(165) == nil, "but not when you already have The Hermit")
    card.data.breadcrumbs = nil
end)
print(fails == 0 and "card smoke test passed" or (fails .. " failed"))
return fails
