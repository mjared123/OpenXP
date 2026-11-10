-- Smoke test for Feedback.lua with a stand-in WoW API: builds the window,
-- fills in the links and checks the bug link carries version, guide and step.
local ROOT = ...
unpack = unpack or table.unpack
tinsert = table.insert
local function obj(name)
    local o = {__name = name, shown = true}
    return setmetatable(o, {__index = function(t, k)
        if type(k) ~= "string" or k:match("^[a-z_]") then return nil end
        if k == "SetScript" then return function(self, ev, fn) rawset(self, "_" .. ev, fn) end end
        if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
        if k == "GetText" then return function(self) return rawget(self, "_text") end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "CreateTexture" or k == "CreateFontString" then return function() return obj(k) end end
        return function() end
    end})
end
function CreateFrame(kind) return obj(kind) end
UIParent, GameTooltip = obj("UIParent"), obj("GameTooltip")
_G.UISpecialFrames = {}
function UnitLevel() return 23 end
function GetRealZoneText() return "Ashenvale" end

local opened = 0
local addon = {
    openxpVersion = "1.3.8",
    player = {race = "Human", class = "Warrior", level = 23},
    currentGuide = {group = "OpenXP 21-60", displayname = "Alliance 21-30", steps = {1, 2, 3, 4, 5}},
    GetGuideProgress = function() return 4 end,
    comms = {OpenBugReport = function() opened = opened + 1 end},
}
local f = io.open(ROOT .. "/Feedback.lua", "r")
local chunk = assert(loadstring(f:read("*a")))
f:close()
chunk("OpenXP", addon)

local failures = 0
local function check(cond, msg)
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local link = addon.feedback.BugLink()
print(link)
check(link:find("template=bug_report.yml", 1, true), "bug template")
check(link:find("version=1.3.8", 1, true), "version")
check(link:find("guide=OpenXP+21-60%3A+Alliance+21-30", 1, true), "guide")
check(link:find("step=4+of+5", 1, true), "step")
check(link:find("character=Human+Warrior%2C+level+23+in+Ashenvale", 1, true), "character")

addon.feedback.Show()
check(_G.UISpecialFrames[1] == "OpenXPFeedbackFrame", "escape closes it")
addon.feedback.Toggle()
addon.feedback.Toggle()

addon.currentGuide = nil
check(addon.feedback.BugLink():find("guide=None", 1, true), "no guide")
print(failures == 0 and "ok" or (failures .. " failed"))
return failures
