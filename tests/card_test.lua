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
    ReplaceNpcIds = function(t) return t end,
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
try("pickup for a quest you can't get yet is skipped once", function()
    addon.openxpPrereqs = {[4733] = {any = {4681}}, [600] = {excl = {601}}}
    local done = {}
    addon.IsQuestTurnedIn = function(id) return done[id] end
    addon.IsOnQuest = function() return false end
    steps[12] = {index = 12, elements = {el{tag = "accept", questId = 4733, text = "Accept Beached Sea Creature"},
                                          el{tag = "goto"}}}
    addon.currentGuide = {name = "19-21 Darkshore/Ashenvale", steps = steps}
    assert(card.QuestBlocked(4733) == 4681, "should need Washed Ashore")
    assert(card.StepUnavailable(steps[12]), "step should be unavailable")
    addon.GetGuideProgress = function() return 12 end
    calls.setStep = nil
    card.TickForTest()
    assert(calls.setStep == 13, "not skipped")
    calls.setStep = nil
    card.TickForTest()
    assert(calls.setStep == nil, "skipped twice")
    done[4681] = true
    assert(not card.QuestBlocked(4733), "blocked after the pre-quest")
    done[601] = true
    assert(card.QuestBlocked(600) == 601, "exclusive quest not honoured")
    -- a step that also turns something in is never auto-skipped
    steps[13] = {index = 13, elements = {el{tag = "accept", questId = 600}, el{tag = "turnin", questId = 4681}}}
    assert(not card.StepUnavailable(steps[13]), "mixed step skipped")
    addon.GetGuideProgress = function() return 1 end
end)
print(fails == 0 and "card smoke test passed" or (fails .. " failed"))
return fails
