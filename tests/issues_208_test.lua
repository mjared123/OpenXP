-- GitHub issues fixed for 2.0.8: another race's priest spell quest (#131),
-- class quests in another race's starting zone (Matt, 2026-11-26), Elwynn's
-- Shiny Red Apples (#129), Betrayed in Orgrimmar (#130).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("issues208")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local function guide(OXP, name, only)
    for _, g in ipairs(OXP.Registry.All()) do
        if g.name == name and (not only or g.only == only) then return g end
    end
end

-- quest ids on the loaded guide's steps (as this character sees them)
local function stepQuests(OXP)
    local q = {}
    for _, step in ipairs(OXP.Engine.GetSteps()) do
        for _, g in ipairs(step.goals) do
            if g.quest then q[g.quest] = true end
        end
    end
    return q
end

local function stepTexts(OXP, needle)
    local n = 0
    for _, step in ipairs(OXP.Engine.GetSteps()) do
        for _, g in ipairs(step.goals) do
            if g.text and g.text:find(needle, 1, true) then n = n + 1 break end
        end
    end
    return n
end

------------------------------------------------------------------------
print("-- #131: a Human priest in Elwynn gets Divine Grace, not the Gnomes' Confounding Flash")
do
    local game, OXP = newGame({ level = 10, faction = "Alliance", race = "Human", class = "PRIEST" })
    OXP.Engine.Load(guide(OXP, "1-11 Elwynn Forest").key)
    local q = stepQuests(OXP)
    t.ok(not q[94817], "no Confounding Flash (Gnome)")
    t.eq(stepTexts(OXP, "Confounding Flash"), 0, "no Confounding Flash letter steps either")
    t.eq(stepTexts(OXP, "Desperate Prayer:"), 0, "no Desperate Prayer (Dwarf)")
    t.eq(stepTexts(OXP, "Starshards:"), 0, "no Starshards (Night Elf)")
    t.ok(q[94774] or q[94773], "Divine Grace is there")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

do
    local game, OXP = newGame({ level = 10, faction = "Alliance", race = "Gnome", class = "PRIEST" })
    OXP.Engine.Load(guide(OXP, "1-11 Elwynn Forest").key)
    t.ok(stepTexts(OXP, "Confounding Flash") > 0, "a Gnome priest in Elwynn still gets Confounding Flash")
    t.eq(stepTexts(OXP, "Divine Grace:"), 0, "and not Divine Grace")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- class quests in another race's starting zone")
do
    local game, OXP = newGame({ level = 10, faction = "Alliance", race = "NightElf", class = "DRUID" })
    OXP.Engine.Load(guide(OXP, "1-11 Elwynn Forest").key)
    local q = stepQuests(OXP)
    t.ok(q[5921] and q[5929] and q[6001], "a Night Elf druid in Elwynn gets Moonglade, Great Bear Spirit, Body and Heart")
    local steps = OXP.Engine.GetSteps()
    local last = steps[#steps]
    t.ok(last.index > 150, "they come after Elwynn's own steps (nothing else moves)")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

do
    local game, OXP = newGame({ level = 10, faction = "Alliance", race = "Human", class = "DRUID" })
    local n = #guide(OXP, "1-11 Elwynn Forest").steps
    OXP.Engine.Load(guide(OXP, "1-11 Elwynn Forest").key)
    t.ok(not stepQuests(OXP)[6001], "nobody else gets the added druid steps")
    t.ok(n > 0, "guide loads")
end

do
    local game, OXP = newGame({ level = 10, faction = "Horde", race = "Orc", class = "HUNTER" })
    OXP.Engine.Load(guide(OXP, "1-13 Tirisfal Glades").key)
    local q = stepQuests(OXP)
    t.ok(q[6062] or q[6083] or q[6082], "an Orc hunter in Tirisfal gets Taming the Beast")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

do
    local game, OXP = newGame({ level = 10, faction = "Horde", race = "Scourge", class = "WARLOCK" })
    OXP.Engine.Load(guide(OXP, "1-13 Tirisfal Glades").key)
    t.ok(not stepQuests(OXP)[1506], "an Undead warlock at home doesn't get the Orc Voidwalker steps")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #129: the Applejack Still's apples")
do
    local game, OXP = newGame({ level = 8, faction = "Alliance", race = "Human", class = "PRIEST" })
    local g = guide(OXP, "1-11 Elwynn Forest")
    local pos
    for i, st in ipairs(g.steps) do
        for _, x in ipairs(st) do
            if x[1] == "collect" and x.item == 4536 then pos = i end
        end
    end
    t.ok(pos ~= nil, "Homer Stonefield's step collects 4 Shiny Red Apples")
    OXP.Engine.Load(g.key)
    local T = OXP.Tooltips
    local found
    for _, n in ipairs(T.NeededItems()) do
        if n.itemId == 4536 then found = n end
    end
    t.ok(found and found.need == 4 and found.questId == 91736, "the tooltip keeps them for the Applejack Still")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #130: Betrayed in Orgrimmar doesn't hold the step")
do
    local game, OXP = newGame({ level = 50, faction = "Horde", race = "Orc", class = "SHAMAN" })
    local g = guide(OXP, "50-51 Azshara, Feralas & Stranglethorn Vale")
    local all = true
    for _, st in ipairs(g.steps) do
        for _, x in ipairs(st) do
            if x.quest == 3504 and (x[1] == "accept" or x[1] == "turnin") and not x.optional then all = false end
        end
    end
    t.ok(all, "Betrayed (3504) pickup and hand-in are optional")
end

------------------------------------------------------------------------
print("-- a name-only plate's marker sits by the name, not off in the air")
do
    local game = FakeWoW.New(ROOT, { level = 23, map = 1442, x = 61.48, y = 55.34 })
    local OXP = game:LoadAddon()
    game:Login()
    local g = { name = "1-11 Issues 208 plate", group = "Test", steps = {
        { { "goto", zone = "1442", x = 61.48, y = 55.34 },
          { "complete", obj = 1, quest = 1071, text = "Kill Venture Co. Logger: 10" },
          { "mob", name = "Venture Co. Logger" } } } }
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    local saved = { UnitExists = _G.UnitExists, UnitName = _G.UnitName, UnitGUID = _G.UnitGUID,
                    UnitCanAttack = _G.UnitCanAttack, UnitIsPlayer = _G.UnitIsPlayer, C_NamePlate = _G.C_NamePlate }
    local plate = CreateFrame("Frame")
    local kp = CreateFrame("Frame", nil, plate)
    kp.name = kp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kp.name:SetText("Venture Co. Logger")
    kp.health = CreateFrame("Frame", nil, kp)
    kp.health:Hide()
    plate.KuiForeverPlate = kp
    _G.UnitExists = function() return true end
    _G.UnitName = function() return "Venture Co. Logger" end
    _G.UnitGUID = function() return "Creature-0-0-0-0-4567-0" end
    _G.UnitCanAttack = function() return true end
    _G.UnitIsPlayer = function() return false end
    _G.C_NamePlate = { GetNamePlateForUnit = function() return plate end, GetNamePlates = function() return { plate } end }
    game:Accept(1071, 1)
    local T = OXP.Tooltips
    T.UpdatePlate("nameplate1")
    local m = T.PlateMarker(plate)
    local p = m and m.points and m.points[#m.points]
    local w = kp.name:GetStringWidth()
    t.ok(p and p[2] == kp.name and p[3] == "CENTER" and p[4] == w / 2 + 8,
        "just past the end of the centred name (" .. tostring(p and p[3]) .. " " .. tostring(p and p[4]) .. ")")
    for k, v in pairs(saved) do _G[k] = v end
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
