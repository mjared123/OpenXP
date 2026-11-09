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
print(fails == 0 and "card smoke test passed" or (fails .. " failed"))
return fails
