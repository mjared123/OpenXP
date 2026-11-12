-- OpenXP 2.0 phase 5: bringing 1.x characters and settings over. The saves
-- below are made up, shaped like real 1.x saved variables (OXPCData per
-- character, OXPSettings / OXPData per account); no real names in them.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("import")

local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[deepcopy(k)] = deepcopy(x) end
    return out
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- A 1.x account and character, then a 2.0 login.
local function login(opts, char, account)
    local game = FakeWoW.New(ROOT, opts)
    GetRealmName = function() return "Test Realm" end
    OXPCData = char
    OXPSettings = account and account.settings
    OXPData = account and account.data
    local before = { deepcopy(OXPCData), deepcopy(OXPSettings), deepcopy(OXPData) }
    local OXP = game:LoadAddon()
    local note
    OXP.Listen("IMPORTED", function(_, r) note = r end)
    game:Login()
    game:Flush()
    t.ok(same(before[1], OXPCData) and same(before[2], OXPSettings) and same(before[3], OXPData),
        "1.x saved data left exactly as it was")
    return game, OXP, note
end

-- the n-th step that was in 1.x (2.0's added class steps not counted)
local function oldOrdinal(OXP)
    local E = OXP.Engine
    local step = E.GetSteps()[E.GetPosition()]
    if not step or step.data.source then return nil end
    local n = 0
    for i = 1, step.index do
        if not E.GetGuide().steps[i].source then n = n + 1 end
    end
    return n
end

local ACCOUNT = {
    settings = {
        profileKeys = { ["Tester - Test Realm"] = "Tester - Test Realm" },
        profiles = { ["Tester - Test Realm"] = {
            openxpCardWidth = 308, openxpCardHeight = 500, openxpCardPos = { "RIGHT", "RIGHT", -60, 100 },
            windowScale = 0.85, guideFontSize = 11, arrowScale = 1.15, arrowText = 15,
            openxpMapRoute = false, minimap = { minimapPos = 125, hide = false },
            activeTheme = "DarkMode", hardcore = false, -- 1.x-only settings: ignored
        } },
    },
    data = { openxpPaths = { areas = { { source = "learned", inst = 0, name = "the cave", circles = { { 1, 2, 30 } }, entrances = { { { 3, 4 } } } } }, passes = {} },
             release = "1.3.57" },
}

------------------------------------------------------------------------
print("-- mid 21-60 guide: same guide, same step, skips and flight paths")
do
    local char = {
        currentGuideGroup = "RestedXP Forever Guide (A)", currentGuideName = "21-22 Ashenvale", currentStep = 5,
        stepSkip = { [3] = true }, flightPaths = { [2] = "Stormwind, Elwynn", [28] = "Astranaar, Ashenvale" },
        openxpSteps = { ["21-22 Ashenvale"] = 5, ["22-23 Wetlands"] = 5 },
        openxpStepStatus = { ["21-22 Ashenvale"] = { [4] = "chain" } },
        questNameCache = { [1] = "x" }, guideProgress = {}, completedWaypoints = { [5] = {} },
    }
    for _, class in ipairs({ "WARRIOR", "MAGE" }) do
        local game, OXP, note = login({ faction = "Alliance", race = "Human", class = class, level = 22 }, char, ACCOUNT)
        local g = OXP.Engine.GetGuide()
        t.eq(g and g.name, "21-22 Ashenvale", class .. ": same guide")
        t.ok((oldOrdinal(OXP) or 0) >= 5, class .. ": at 1.x step 5 or past it (done steps passed): " .. tostring(oldOrdinal(OXP)))
        local save = OXP.char.guides[g.key]
        local skippedOld = 0
        for i in pairs(save.skipped) do
            if not g.steps[i].source then skippedOld = skippedOld + 1 end
        end
        t.eq(skippedOld, 2, class .. ": skipped and chain-missed steps carried over")
        t.ok(OXP.World.KnowsFlightPath("Astranaar"), class .. ": flight paths carried over")
        local wet = OXP.Import.FindGuide("RestedXP Forever Guide (A)", "22-23 Wetlands")
        t.ok(wet and OXP.char.guides[wet.key] and OXP.char.guides[wet.key].step >= 5, class .. ": place in another guide carried over")
        t.ok(note and note.guide == g and not note.smart, class .. ": the note says where")
        t.ok(OXP.ImportNote.Text(note):find("21-22 Ashenvale, step", 1, true), class .. ": note text")
        t.eq(#game.errors, 0, class .. ": no Lua errors: " .. table.concat(game.errors, " | "))
    end
end

------------------------------------------------------------------------
print("-- settings: what still exists comes over, once")
do
    local _, OXP = login({ faction = "Alliance", race = "Human", class = "WARRIOR", level = 22, name = "Tester" },
        { currentGuideGroup = "x" }, ACCOUNT)
    local s = OXP.settings
    t.eq(s.cardWidth, 308, "card width")
    t.eq(s.cardScale, 0.85, "card scale")
    t.eq(s.fontSize, 11, "font size")
    t.eq(s.arrowText, 15, "arrow text")
    t.ok(s.cardPos and s.cardPos[1] == "RIGHT" and s.cardPos[3] == -60, "card position")
    t.eq(s.mapRoute, false, "route line off, as it was")
    t.eq(s.minimap.angle, 125, "minimap button place")
    t.ok(#OXP.db.paths.areas == 1, "learned caves come over")
    t.eq(OXP.db.importedSettings, "test", "marked done")
    -- a second login doesn't import again
    s.fontSize = 14
    OXP.Import.Settings()
    t.eq(s.fontSize, 14, "only once per account")
end

------------------------------------------------------------------------
print("-- mid dungeon guide")
do
    local _, OXP, note = login({ faction = "Alliance", race = "Human", class = "PRIEST", level = 24 }, {
        currentGuideGroup = "OpenXP Dungeons", currentGuideName = "22-30 The Stockade", currentStep = 3,
    })
    local g = OXP.Engine.GetGuide()
    t.eq(g and g.name, "22-30 The Stockade", "same dungeon guide")
    t.ok(g and (oldOrdinal(OXP) or 0) >= 3, "at its step 3 or past it")
    t.ok(note and not note.smart, "no smart start needed")
end

------------------------------------------------------------------------
print("-- mid 1-20: the route is new, so smart start places you")
do
    local game, OXP, note = login({ faction = "Alliance", race = "Human", class = "WARRIOR", level = 8 }, {
        currentGuideGroup = "RestedXP Forever Guide (A)", currentGuideName = "6-11 Elwynn Forest", currentStep = 40,
        stepSkip = { [3] = true }, flightPaths = {},
    })
    local g = OXP.Engine.GetGuide()
    t.eq(g and g.name, "1-11 Elwynn Forest", "smart start picked the new 1-20 guide")
    t.ok(note and note.smart and note.placed == g, "the note says smart start placed you")
    t.ok(OXP.ImportNote.Text(note):find("new 1-20 route", 1, true), "and why")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- a fresh character, and broken data")
do
    local _, OXP, note = login({ faction = "Horde", race = "Orc", class = "SHAMAN", level = 1 }, nil)
    t.ok(note == nil, "no 1.x data: no note")
    t.eq(OXP.Engine.GetGuide() and OXP.Engine.GetGuide().name, "1-12 Durotar", "a fresh character starts at 1")
    t.ok(OXP.char.imported, "marked done")
    for _, bad in ipairs({
        "not a table",
        { currentGuideName = 5, currentStep = "x", flightPaths = 7, openxpSteps = "y", stepSkip = { a = "b" } },
        { currentGuideGroup = "RestedXP Forever Guide (H)", currentGuideName = "No Such Guide", currentStep = 999 },
        { currentGuideGroup = "RestedXP Forever Guide (A)", currentGuideName = "21-22 Ashenvale", currentStep = 99999 },
    }) do
        local game, OXP2 = login({ faction = "Alliance", race = "Human", class = "WARRIOR", level = 21 }, bad,
            { settings = { profiles = "broken" }, data = { openxpPaths = { areas = { 5, "x" } } } })
        t.eq(#game.errors, 0, "broken data doesn't break login: " .. table.concat(game.errors, " | "))
        t.ok(OXP2.Engine.GetGuide() ~= nil, "and you still get a guide")
    end
end

------------------------------------------------------------------------
print("-- the importer runs once per character")
do
    local game, OXP = login({ faction = "Alliance", race = "Human", class = "WARRIOR", level = 22 }, {
        currentGuideGroup = "RestedXP Forever Guide (A)", currentGuideName = "21-22 Ashenvale", currentStep = 5 })
    local saved = game:SavedVariables()
    local game2 = FakeWoW.New(ROOT, { faction = "Alliance", race = "Human", class = "WARRIOR", level = 22 }, saved)
    OXPCData = { currentGuideGroup = "RestedXP Forever Guide (A)", currentGuideName = "22-23 Wetlands", currentStep = 3 }
    local OXP2 = game2:LoadAddon()
    local again
    OXP2.Listen("IMPORTED", function() again = true end)
    game2:Login()
    t.ok(not again, "no second import")
    t.eq(OXP2.Engine.GetGuide() and OXP2.Engine.GetGuide().name, "21-22 Ashenvale", "2.0's own place is kept")
    local _ = OXP
end

return t.fails
