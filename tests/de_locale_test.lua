-- German display text must preserve the guide's IDs and executable arguments.
local ROOT = ...
local function read(file)
    local f = assert(io.open(ROOT .. "/" .. file, "r"))
    local source = f:read("*a")
    f:close()
    return source
end
local function section(source, first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a + #first, true), last)
    return source:sub(a, b - 1)
end

local currentLocale, ui = "enUS", {}
local addon = {
    game = "FOREVER", locale = {}, separators = {}, icons = {fly = ""},
    minGuideVersion = 999, maxGuideVersion = 0,
    settings = {ReplaceColors = function(s) return s end},
    GetCreatureName = function(s) return s end,
    ReplaceNpcIds = function(s) return s end,
    RegisterGroup = function() end, GroupOverride = function() end,
    A32 = function() return 123 end, error = error,
    affix = function(a, b) return a .. "-" .. b end,
    BuildGuideKey = function(g) return g.group .. "|" .. g.name end,
}
addon.functions = setmetatable({}, {__index = function(_, tag)
    return function(_, text, id, reward)
        if tag == "collect" then return {rawtext = text, dynamicText = true} end
        return {text = text, questId = tonumber(id), reward = tonumber(reward)}
    end
end})
local function L(s) return ui[s] or s end
local env = setmetatable({
    GetLocale = function() return currentLocale end,
    UnitLevel = function() return 25 end,
    LibStub = function() return {NewLocale = function() return ui end} end,
    C_QuestLog = {GetTitleForQuestID = function(id) if id == 1013 then return "Das Buch von Ur" end end},
}, {__index = _G})
local function run(source, ...)
    local fn = assert(loadstring(source))
    setfenv(fn, env)
    return fn(...)
end
local catalog = read("locale/deDE_guide.lua")
run(catalog, "OpenXP", addon)
assert(addon.deGuideLocale == nil, "German catalog loaded for an English client")
currentLocale = "deDE"
run(catalog, "OpenXP", addon)
run(read("locale/deDE.lua"), "OpenXP", addon)

local localeCode = section(read("Locale.lua"), "local guideTextCache =", "function addon.locale.AddGenericTranslation")
local parseCode = section(read("GuideLoader.lua"), "local function parseLine(", "addon.groupAlias = {}")
local cardCode = section(read("OpenXPCard.lua"), "local function QuestStepText(", "-- Title (the")
local prefix = [[
local addon, L, applies = ...
local strlower, strupper = string.lower, string.upper
local tinsert, unpack, fmt = table.insert, unpack or table.unpack, string.format
]]
local elementText = run(prefix .. localeCode .. parseCode .. cardCode .. "\nreturn ElementText", addon, L, function() return true end)
local flyCode = section(read("functions.lua"), "function addon.functions.fly(self, ...)", "\n--")
run(prefix .. flyCode, addon, L)

local raw = [[
#forever
#group OpenXP Dungeons
#name 22-30 Shadowfang Keep
#next 22-32 Blackfathom Deeps
step
.fly Undercity >>Fly to the Undercity
.turnin 1013,2 >>Turn in The Book of Ur
]]
local guide = assert(addon.ParseGuide(raw))
assert(guide.name == "22-30 Shadowfang Keep")
assert(guide.next == "22-32 Blackfathom Deeps")
assert(addon.locale.GuideTitle(guide) == "22-30 Burg Schattenfang")
assert(not addon.locale.ForGuide({group = "other", name = guide.name}))
local flight, turnin = guide.steps[1].elements[1], guide.steps[1].elements[2]
assert(flight.location == "UNDERCITY" and flight.text == "Fly to the Undercity")
assert(elementText(flight):find("Unterstadt", 1, true))
assert(turnin.questId == 1013 and turnin.reward == 2)
assert(elementText(turnin) == string.format(L("Turn in %s"), "Das Buch von Ur"))

-- The [item] slot contains an earlier colored-name slot.
local scope = {
    phrases = {["Store {B}{C}"] = "Lagere {B}{C}"}, literals = {}, cache = {},
    names = addon.deGuideLocale.names,
}
local item = "|T133734:20|t[|cRXP_LOOT_Shredder Operating Manual Pages|r]"
local translated = addon.locale.GuideText("Store " .. item, scope)
assert(translated == "Lagere |T133734:20|t[|cRXP_LOOT_Seiten der Schredderanleitung|r]")
assert(not translated:find("{%u}"))
local element = {text = "Store " .. item .. "\n1/1", localizedTextSource = "Store " .. item,
    localizedText = translated, step = {guideLocale = scope}}
assert(elementText(element) == translated .. "\n1/1")
print("German localization preserves guide links, flight IDs, reward choices and nested item text")
