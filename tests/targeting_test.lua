-- Smoke test for the Quest Targets list (Targeting.lua): builds the frame,
-- lays out enemy and friendly rows, and fills the quick-target macros.
local ROOT = ...
unpack = unpack or table.unpack
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
local frames = {}
local function obj(name)
    local o = {__name = name, shown = false, attrs = {}}
    return setmetatable(o, {__index = function(t, k)
        if type(k) ~= "string" or k:match("^[a-z_]") then return nil end
        if k == "GetStringWidth" or k == "GetWidth" then return function() return 60 end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "SetAttribute" then return function(self, a, v) self.attrs[a] = v end end
        if k == "GetAttribute" then return function(self, a) return self.attrs[a] end end
        if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
        if k == "GetText" then return function(self) return rawget(self, "_text") end end
        if k == "SetSize" then return function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end end
        if k == "SetHeight" then return function(self, h) rawset(self, "_h", h) end end
        if k == "SetWidth" then return function(self, w) rawset(self, "_w", w) end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "CreateTexture" or k == "CreateFontString" then return function() return obj(k) end end
        return function() end
    end})
end
function CreateFrame(kind, name)
    local o = obj(name or kind)
    if name then _G[name] = o end
    return o
end
UIParent = obj("UIParent")
GameTooltip = obj("GameTooltip")
C_NamePlate = {GetNamePlates = function() return {} end}
C_Timer = {After = function() end}
LibStub = function() return {GetPlayerZone = function() end} end
InCombatLockdown = function() return false end
IsInRaid = function() return false end
UnitOnTaxi = function() return false end
UnitName = function() return nil end
GetMacroInfo = function() return nil end
GetNumMacros = function() return 0 end
GetBindingKey = function(b) if b == "CLICK RXPTargetFrame_EnemyButton1:LeftButton" then return "F1" end end
GetBindingText = function(k) return k end
local addon = {
    locale = {Get = function(s) return s end},
    settings = {profile = {enableTargetFrame = true, enableTargetAutomation = true, showEnabled = true},
                SaveFramePositions = function() end},
    v2 = {IsGuideWindowEnabled = function() return false end},
    RXPFrame = {backdrop = {edge = {}}},
    colors = {background = {0, 0, 0, 1}},
    activeTheme = {textColor = {1, 1, 1}},
    font = "font", game = "FOREVER", gameVersion = 11509,
    GetUnitName = function() return nil end,
    enabledFrames = {},
    comms = {PrettyPrint = function() end},
}
function addon:NewModule() return {} end
assert(loadfile(ROOT .. "/Targeting.lua"))("OpenXP", addon)
local T = addon.targeting
local fails = 0
local function try(label, fn)
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end
try("build the frame", function() T:CreateTargetFrame() end)
try("enemy and friendly rows with key labels", function()
    T:UpdateEnemyList({}, {"Kobold Vermin", "Kobold Worker"})
    T:UpdateTargetList({"Marshal McBride"})
    local f = T.activeTargetFrame
    assert(#f.enemyTargetButtons == 2, "enemy rows " .. #f.enemyTargetButtons)
    assert(#f.friendlyTargetButtons == 1, "friendly rows")
    local labels = {}
    for _, b in ipairs(f.enemyTargetButtons) do labels[b.label:GetText()] = b.key:GetText() end
    assert(labels["Kobold Vermin"] ~= nil and labels["Kobold Worker"] ~= nil, "row names missing")
    assert(f.enemyTargetButtons[1].key:GetText() == "F1", "key label")
    assert(f._w == 200 and f._h > 80, "frame size " .. tostring(f._w) .. "x" .. tostring(f._h))
    local m = OpenXPTargetMobs:GetAttribute("macrotext")
    assert(m:find("/targetexact Kobold Vermin") and m:find("/targetexact Kobold Worker"), m)
    assert(OpenXPTargetNPCs:GetAttribute("macrotext") == "/targetexact Marshal McBride")
end)
print(fails == 0 and "targeting smoke test passed" or (fails .. " failed"))
return fails
