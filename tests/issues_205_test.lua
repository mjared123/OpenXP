-- GitHub issues fixed for 2.0.5: every line of a long step on the card
-- (#107), optional pickups not holding a step (#110), the map's tooltip
-- closing with the map (#111), other races' starting zones (#106) and
-- raid markers from the targets list (#113).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("issues205")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local counter = 0
local function addGuide(OXP, steps, extra)
    counter = counter + 1
    local g = { name = "22-25 Issues test " .. counter, group = "Test", steps = steps }
    for k, v in pairs(extra or {}) do g[k] = v end
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

------------------------------------------------------------------------
print("-- #107: a step with more than 8 lines shows them all (Dangerous! in Hillsbrad)")
do
    local game, OXP = newGame({ level = 24, faction = "Horde", race = "Troll", class = "MAGE" })
    local step = { { "text", text = "Tarren Mill" } }
    for i = 1, 10 do
        step[#step + 1] = { "accept", quest = 7300 + i, text = "Accept Quest number " .. i }
    end
    addGuide(OXP, { step, { { "turnin", quest = 7301 } } })
    OXP.Card.Refresh(true)
    local _, lines = OXP.Card.StepContent(OXP.Engine.GetSteps()[1])
    t.eq(#lines, 10, "ten lines in the step")
    local shown = 0
    for _, b in ipairs(OXP.Card.blocks or {}) do
        for _, l in ipairs(b.lines or {}) do
            if l:IsShown() and (l.text:GetText() or ""):find("Quest number", 1, true) then shown = shown + 1 end
        end
    end
    t.eq(shown, 10, "all ten drawn on the card, the 9th and 10th too")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #110: an optional pickup doesn't hold a step once the rest is done")
do
    local game, OXP = newGame({ level = 33 })
    addGuide(OXP, {
        { { "text", text = "Panthers" },
          { "complete", quest = 7191, obj = 1, text = "Kill Panther: 10" },
          { "accept", optional = true, quest = 7635, text = "Accept Crystal in the Mountains" } },
        { { "text", text = "Only optional" },
          { "accept", optional = true, quest = 7636, text = "Accept Maybe" } },
        { { "turnin", quest = 7191 } },
    })
    game:Accept(7191, 1)
    game:Advance(1)
    t.eq(OXP.Engine.GetPosition(), 1, "panthers still to kill: the step stays")
    game:FinishObjective(7191, 1)
    game:Advance(1)
    t.eq(OXP.Engine.GetPosition(), 2, "panthers done, no pendant: on to the next step")
    t.eq(OXP.Engine.GetPosition(), 2, "a step of only optional pickups waits for you")
    game:Accept(7636)
    game:Advance(1)
    t.eq(OXP.Engine.GetPosition(), 3, "and moves on once you have it")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #111: closing the map closes a pin's tooltip")
do
    local game, OXP = newGame({ level = 21 })
    t.ok(type(OXP.Pins.MapClosed) == "function", "the map closing has a handler")
    GameTooltip:Show()
    local ok, err = pcall(OXP.Pins.MapClosed)
    t.ok(ok, "runs: " .. tostring(err))
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #106: other races' starting zones, for your own faction only")
do
    local game, OXP = newGame({ level = 5, faction = "Alliance", race = "NightElf", class = "HUNTER" })
    local R = OXP.Registry
    local human = R.Find("1-11 Elwynn Forest", "OpenXP Leveling (Alliance)")
    t.ok(human ~= nil, "a Night Elf can find the Human start")
    t.eq(human and R.OtherStart(human), "Human", "as another race's start")
    t.ok(not R.IsAvailable(human), "but not as their own")
    local own
    for _, g in ipairs(R.All()) do
        if g.name == "1-12 Teldrassil" then own = g end
    end
    t.eq(own and R.OtherStart(own), nil, "their own start isn't 'other'")
    local westfall
    for _, g in ipairs(R.All()) do if g.name == "11-17 Westfall" then westfall = g end end
    t.eq(westfall and R.OtherStart(westfall), nil, "a faction guide isn't a start")
    local plain = #R.ForPlayer(nil, "OpenXP Leveling (Alliance)")
    local with = #R.ForPlayer(nil, "OpenXP Leveling (Alliance)", true)
    t.ok(with > plain, "the picker list can add them")
    -- the picker: a section at the end of the Leveling tab
    local rows = OXP.GuidePicker.ListRows("", "Leveling")
    local header, found
    for _, r in ipairs(rows) do
        if r.header then header = r.header end
        if r.guide == human then found = header end
    end
    t.eq(found, "Other races' starting zones", "the Human start is under its own heading")
    -- smart start: not without quests there; yes with Elwynn progress
    t.eq(OXP.SmartStart.ScoreGuide(human, 5, "Elwynn Forest"), nil, "no Elwynn quests: never picked")
    game:Accept(7) -- Kobold Camp Cleanup
    t.ok(OXP.SmartStart.ScoreGuide(human, 5, "Elwynn Forest") ~= nil, "on an Elwynn quest: it can be")
    local picked = OXP.SmartStart.PickGuide(OXP.SmartStart.Candidates(), 5, "Elwynn Forest")
    t.eq(picked and picked.name, "1-11 Elwynn Forest", "smart start picks Elwynn for the Night Elf there")
    -- loading it works and its next guide is found
    OXP.Engine.Load(human.key)
    t.eq(OXP.Engine.GetGuide(), human, "loaded")
    t.eq(R.Next(human) and R.Next(human).name, "11-17 Westfall", "then Westfall")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

do
    local game, OXP = newGame({ level = 5, faction = "Alliance", race = "Gnome", class = "MAGE" })
    local R = OXP.Registry
    local picked = OXP.SmartStart.PickGuide(OXP.SmartStart.Candidates(), 1, "Dun Morogh")
    t.eq(picked and picked.only, "Gnome", "a Gnome still gets the Gnome Dun Morogh, not the Dwarf one")
    local horde = 0
    for _, g in ipairs(R.ForPlayer(nil, nil, true)) do
        if g.faction == "Horde" then horde = horde + 1 end
    end
    t.eq(horde, 0, "never the other faction's starts")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #113: the targets list marks who it targets")
do
    local game, OXP = newGame({ level = 21 })
    addGuide(OXP, {
        { { "accept", quest = 7401 }, { "target", name = "Gryan Stoutmantle" },
          { "accept", quest = 7402 }, { "target", name = "Scout Riell" } },
        { { "complete", quest = 7401, obj = 1 }, { "mob", name = "Defias Trapper" }, { "mob", name = "Defias Smuggler" } },
    })
    local B = OXP.ActionButtons
    B.Refresh()
    local first = B.target:GetAttribute("macrotext")
    t.ok(first:find("/tm [harm,nodead] !8; [help,nodead] 1", 1, true), "first row: skull for a mob, star for a person")
    local second = B.rows[2]:GetAttribute("macrotext")
    t.ok(second:find("/targetexact Scout Riell", 1, true) and second:find("/tm [nodead] 2", 1, true),
        "second person: a circle")
    OXP.settings.raidMarkers = false
    B.Refresh()
    t.ok(not B.target:GetAttribute("macrotext"):find("/tm", 1, true), "setting off: no marker")
    OXP.settings.raidMarkers = true
    IsInRaid = function() return true end
    UnitIsGroupLeader = function() return false end
    UnitIsGroupAssistant = function() return false end
    B.Refresh()
    t.ok(not B.target:GetAttribute("macrotext"):find("/tm", 1, true), "in a raid, not leading: no marker")
    UnitIsGroupAssistant = function() return true end
    B.Refresh()
    t.ok(B.target:GetAttribute("macrotext"):find("/tm", 1, true), "assist: marks again")
    IsInRaid = nil
    game:Accept(7401, 1)
    game:Accept(7402)
    game:Advance(1)
    B.Refresh()
    local m2 = B.rows[2] and B.rows[2]:GetAttribute("macrotext") or ""
    t.ok(m2:find("/tm [nodead] !7", 1, true), "second mob: a cross that stays")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- #113: a raid marker on a mob lifts OpenXP's sword above it")
do
    local game, OXP = newGame({ level = 23, map = 1442, x = 61.48, y = 55.34 })
    addGuide(OXP, {
        { { "goto", zone = "1442", x = 61.48, y = 55.34 },
          { "complete", obj = 1, quest = 1071, text = "Kill Venture Co. Logger: 10" },
          { "mob", name = "Venture Co. Logger" } },
    })
    local saved = { UnitExists = _G.UnitExists, UnitName = _G.UnitName, UnitGUID = _G.UnitGUID,
                    UnitCanAttack = _G.UnitCanAttack, UnitIsPlayer = _G.UnitIsPlayer, C_NamePlate = _G.C_NamePlate,
                    GetRaidTargetIndex = _G.GetRaidTargetIndex }
    local plate = CreateFrame("Frame")
    plate.UnitFrame = CreateFrame("Frame", nil, plate)
    _G.UnitExists = function() return true end
    _G.UnitName = function() return "Venture Co. Logger" end
    _G.UnitGUID = function() return "Creature-0-0-0-0-4567-0" end
    _G.UnitCanAttack = function() return true end
    _G.UnitIsPlayer = function() return false end
    _G.C_NamePlate = { GetNamePlateForUnit = function() return plate end, GetNamePlates = function() return { plate } end }
    local mark
    _G.GetRaidTargetIndex = function() return mark end
    game:Accept(1071, 1)
    local T = OXP.Tooltips
    local function lift()
        local m = T.PlateMarker(plate)
        local p = m and m.points and m.points[#m.points]
        return p and p[5]
    end
    T.UpdatePlate("nameplate1")
    local low = lift()
    t.ok(low ~= nil, "the sword is placed")
    mark = 8
    T.UpdatePlate("nameplate1")
    t.ok(lift() and low and lift() > low, "skull on it: the sword goes up above the skull")
    mark = nil
    T.UpdatePlate("nameplate1")
    t.eq(lift(), low, "skull gone: back down")
    for k, v in pairs(saved) do _G[k] = v end
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
