-- OpenXP 2.0.0-dev4 fixes from in-game testing: fly steps done on take-off
-- (and the arrow moving on), auto-flight, the step list leaving no box
-- behind and wearing the card's skin, one step text on the card, scrollbar
-- drags that let go, the targets list, and Reset to defaults.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("dev4")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local counter = 0
local function addGuide(OXP, steps)
    counter = counter + 1
    local g = { name = "22-25 Dev4 test " .. counter, group = "Test", steps = steps }
    OXP.AddGuides({ file = "test", g })
    OXP.Engine.Load(g.key)
    return g
end

-- Step 31 of the 22-25 guide: to the Astranaar flight master, fly to
-- Auberdine, then the boat (the arrow must go to the dock as you take off)
local FLY_GUIDE = {
    { { "text", text = "Fly to Auberdine" },
      { "reach", text = "Astranaar flight master", x = 34.5, y = 48, zone = "1440" },
      { "fly", inst = 1, name = "Auberdine", text = "Fly to Auberdine", wx = 557.7, wy = 6341.4 } },
    { { "text", text = "Boat to Menethil Harbor" },
      { "reach", text = "Boat to Menethil Harbor", x = 32.4, y = 43.8, zone = "1439" } },
}
local NODES = { "Astranaar, Ashenvale", "Auberdine, Darkshore", "Talrendis Point, Azshara" }

------------------------------------------------------------------------
print("-- a fly step is done as you take off, and the arrow moves on")
do
    local game, OXP = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    OXP.settings.autoFlight = false
    addGuide(OXP, FLY_GUIDE)
    game:Advance(1)
    t.eq(OXP.Engine.GetPosition(), 1, "at the flight master: still the fly step")
    local real = OXP.Target.Real()
    t.eq(real and real.pos, 1, "the arrow points at the flight master")
    game:OpenTaxi(NODES)
    t.eq(game.tookTaxi, nil, "auto-flight off: nothing taken for you")
    game:FlyTo(2)
    t.eq(OXP.Engine.GetPosition(), 2, "taking off to Auberdine: on to the boat step")
    real = OXP.Target.Real()
    t.eq(real and real.pos, 2, "the arrow now points at the dock, not the flight master")
    t.eq(real and real.map, 1439, "in Darkshore")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

print("-- a flight somewhere else doesn't count")
do
    local game, OXP = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    OXP.settings.autoFlight = false
    addGuide(OXP, FLY_GUIDE)
    game:OpenTaxi(NODES)
    game:FlyTo(3)
    game:Advance(1)
    t.eq(OXP.Engine.GetPosition(), 1, "flying to Talrendis Point: the Auberdine step stays")
end

print("-- a flight whose destination wasn't seen (after a /reload) counts for the fly step shown")
do
    local game, OXP = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    addGuide(OXP, FLY_GUIDE)
    game:TakeOff()
    game:Advance(1)
    t.eq(OXP.Engine.GetPosition(), 2, "on a taxi with no known destination: the fly step is done")
end

print("-- landing near the flight master still counts (you got there another way)")
do
    local game, OXP = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    addGuide(OXP, FLY_GUIDE)
    game:MoveToWorld(560, 6330, 1)
    game:Advance(1)
    t.eq(OXP.Engine.GetPosition(), 2, "standing at Auberdine's flight master")
end

------------------------------------------------------------------------
print("-- auto-flight: the step's flight is taken when the map opens")
do
    local game, OXP = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    addGuide(OXP, FLY_GUIDE)
    t.eq(OXP.settings.autoFlight, false, "off by default (Matt, 2.0.2)")
    OXP.settings.autoFlight = true
    local said = {}
    local oldPrint = print
    print = function(msg) said[#said + 1] = tostring(msg) end
    game:OpenTaxi(NODES)
    print = oldPrint
    t.eq(game.tookTaxi, 2, "takes the Auberdine node")
    t.ok(table.concat(said, "\n"):find("Flying to Auberdine", 1, true), "says where it's flying")
    t.eq(#said, 1, "one chat line")
    game:TakeOff()
    t.eq(OXP.Engine.GetPosition(), 2, "and the step moves on as it takes off")

    -- Shift held while talking: you choose
    local game2, OXP2 = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    OXP2.settings.autoFlight = true
    addGuide(OXP2, FLY_GUIDE)
    IsShiftKeyDown = function() return true end
    game2:OpenTaxi(NODES)
    IsShiftKeyDown = function() return false end
    t.eq(game2.tookTaxi, nil, "Shift: nothing taken")

    -- the destination isn't on this map (not learned yet): nothing
    local game3, OXP3 = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    OXP3.settings.autoFlight = true
    addGuide(OXP3, FLY_GUIDE)
    game3:OpenTaxi({ "Astranaar, Ashenvale", "Talrendis Point, Azshara" })
    t.eq(game3.tookTaxi, nil, "unknown destination: nothing taken")

    -- no fly step shown: nothing
    local game4, OXP4 = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    OXP4.settings.autoFlight = true
    addGuide(OXP4, { { { "goto", zone = "1440", x = 34, y = 48 }, { "accept", quest = 1010 } } })
    game4:OpenTaxi(NODES)
    t.eq(game4.tookTaxi, nil, "a step without a flight: the map is yours")

    -- setting off
    local game5, OXP5 = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    addGuide(OXP5, FLY_GUIDE)
    OXP5.settings.autoFlight = false
    game5:OpenTaxi(NODES)
    t.eq(game5.tookTaxi, nil, "off in settings")
    t.eq(#game.errors + #game2.errors + #game3.errors, 0, "no Lua errors")

    -- a 2.0.0/2.0.1 player with auto-flight on: off once, then their choice
    local old = FakeWoW.New(ROOT, { level = 23 }, { OpenXPDB = { settings = { autoFlight = true } } })
    local OXPo = old:LoadAddon()
    old:Login()
    t.eq(OXPo.settings.autoFlight, false, "2.0.1's auto-flight is turned off once")
    OXPo.settings.autoFlight = true
    local again = FakeWoW.New(ROOT, { level = 23 }, old:SavedVariables())
    local OXPa = again:LoadAddon()
    again:Login()
    t.eq(OXPa.settings.autoFlight, true, "turned on again by the player: stays on")
end

------------------------------------------------------------------------
print("-- the step list: closing it leaves nothing on screen; it wears the card's skin")
do
    local game, OXP = newGame({ level = 21 })
    local steps = {}
    for i = 1, 20 do steps[i] = { { "text", text = "Step number " .. i }, { "xp", level = 60 } } end
    addGuide(OXP, steps)
    OXP.Card.Refresh(true)
    local Nav = OXP.StepNav
    Nav.Show()
    local f = Nav.frame
    t.ok(f.shown and f.shadow and f.shadow.shown, "open: panel and its shadow")
    Nav.Hide()
    for _ = 1, 5 do game:Advance(0.1) end
    t.ok(not f.shown, "closed after the fade")
    t.ok(not f.shadow.shown, "and its shadow (the dark box) is gone too")
    t.eq(f:GetAlpha(), 1, "alpha back to 1 for next time")
    -- open again while it's fading out: stays open
    Nav.Show()
    Nav.Hide()
    game:Advance(0.05)
    Nav.Show()
    for _ = 1, 5 do game:Advance(0.1) end
    t.ok(f.shown and f.shadow.shown, "reopened mid-fade: stays open")
    -- the card's look
    local s = OXP.settings
    s.skin, s.cardOpacity = "midnight", 0.5
    OXP.Send("SETTINGS_CHANGED")
    local C = OXP.Style.C
    t.ok(math.abs(f.bdColor[4] - (C.bg[4] or 1) * 0.5) < 0.01, "background follows the card's Background slider: " .. tostring(f.bdColor[4]))
    s.skin = "minimal"
    OXP.Send("SETTINGS_CHANGED")
    t.ok(f.bdColor[4] < 0.01, "Minimal: no background")
    t.ok(f.head.fill[4] < 0.001 and f.foot.fill[4] < 0.001, "Minimal: no header or footer band")
    t.ok(f.shadow.alpha == 0, "Minimal: no shadow")
    t.eq(f.title.font and f.title.font[3], "OUTLINE", "Minimal: outlined text like the card")
    s.skin, s.cardOpacity, s.fontSize = "glass", 1, 15
    OXP.Send("SETTINGS_CHANGED")
    t.ok(f.bdColor[4] > 0.5, "Glass: a background again")
    t.eq(f.title.font and f.title.font[2], 18, "the card's text size (+3 for the title)")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- the card shows a step's text once")
do
    local game, OXP = newGame({ level = 23 })
    addGuide(OXP, FLY_GUIDE)
    local step = OXP.Engine.GetSteps()[2]
    local title, lines = OXP.Card.StepContent(step)
    t.eq(OXP.Text.Strip(title), "Boat to Menethil Harbor", "the title")
    t.eq(#lines, 0, "no second line saying the same thing")
    title, lines = OXP.Card.StepContent(OXP.Engine.GetSteps()[1])
    t.eq(#lines, 1, "fly step: the flight master line stays, the repeated 'Fly to Auberdine' goes")
    t.eq(OXP.Text.Strip(lines[1].text), "Astranaar flight master", "the line left")
end

------------------------------------------------------------------------
print("-- settings scrollbar: letting go anywhere ends the drag")
do
    local game, OXP = newGame({ level = 21 })
    OXP.Settings.Show("card")
    local page = OXP.Settings.Page("card")
    local thumb = page.area.bar.thumb
    t.ok(thumb.scripts.OnMouseDown ~= nil, "the thumb can be grabbed")
    game.mouseDown = true
    thumb.scripts.OnMouseDown(thumb)
    t.ok(thumb.scripts.OnUpdate ~= nil, "dragging follows the mouse")
    game:Advance(0.1)
    t.ok(thumb.scripts.OnUpdate ~= nil, "still dragging while the button is down")
    game.mouseDown = false -- released away from the thumb: no OnMouseUp for it
    game:Advance(0.1)
    t.ok(thumb.scripts.OnUpdate == nil and not thumb.dragging, "button up: the drag ends")
    t.ok(thumb.scripts.OnDragStop ~= nil, "OnDragStop ends it too")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- targets: only people still needed")
do
    local game, OXP = newGame({ level = 23 })
    InCombatLockdown = function() return false end
    addGuide(OXP, {
        { { "goto", zone = "1440", x = 26.44, y = 38.59 },
          { "turnin", quest = 1010 }, { "target", name = "Orendil Broadleaf" },
          { "goto", zone = "1440", x = 26.44, y = 38.59 },
          { "accept", quest = 1020 }, { "target", name = "Orendil Broadleaf" },
          { "goto", zone = "1440", x = 26.2, y = 38.7 },
          { "accept", quest = 1033 }, { "target", name = "Sentinel Velene Starstrike" },
          { "goto", zone = "1440", x = 36, y = 49 },
          { "accept", quest = 1034 }, { "target", name = "Raene Wolfrunner" } },
    })
    game:Accept(1010, 1)
    game:FinishObjective(1010, 1)
    game:MoveTo(1440, 36, 49)
    local B = OXP.ActionButtons
    local function names()
        local out = {}
        for _, e in ipairs(B.WantedTargets()) do out[#out + 1] = e.name end
        return table.concat(out, ",")
    end
    t.eq(names(), "Raene Wolfrunner,Orendil Broadleaf,Sentinel Velene Starstrike", "nearest first")
    game:Accept(1034, 1)
    t.eq(names(), "Orendil Broadleaf,Sentinel Velene Starstrike", "Raene's quest taken: she's off the list")
    game:TurnIn(1010)
    game:Accept(1020, 1)
    t.eq(names(), "Sentinel Velene Starstrike", "Orendil done (turn-in and pickup): off the list")

    -- hiding the guide card (minimap button) hides the arrow and this list too
    game:Flush()
    t.eq(B.box:IsShown(), true, "list shown with the card")
    t.eq(OXP.Arrow.frame:IsShown(), true, "arrow shown with the card")
    OXP.Card.Toggle()
    game:Flush()
    t.eq(OXP.settings.cardShown, false, "card hidden")
    t.eq(B.box:IsShown(), false, "the targets list hides with it")
    t.eq(OXP.Arrow.frame:IsShown(), false, "and the arrow")
    OXP.Card.Toggle()
    game:Flush()
    t.eq(B.box:IsShown(), true, "card back: the list comes back")
    t.eq(OXP.Arrow.frame:IsShown(), true, "and the arrow")
end

------------------------------------------------------------------------
print("-- 2.0.4: the step's flight circled on the flight master's map (GitHub #87)")
do
    local game, OXP = newGame({ level = 23, map = 1440, x = 34.5, y = 48 })
    for i = 1, 3 do
        local b = game.Widget("Button", "TaxiButton" .. i)
        b:SetSize(16, 16)
    end
    addGuide(OXP, FLY_GUIDE)
    game:OpenTaxi(NODES)
    t.eq(OXP.Automation.marked, 2, "Auberdine's node is marked (auto-flight off)")
    game:Fire("TAXIMAP_CLOSED")
    t.eq(OXP.Automation.marked, nil, "gone when the map closes")
    addGuide(OXP, { { { "goto", zone = "1440", x = 34, y = 48 }, { "accept", quest = 1010 } } })
    game:OpenTaxi(NODES)
    t.eq(OXP.Automation.marked, nil, "no flight in the step: nothing marked")
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
end

------------------------------------------------------------------------
print("-- 2.0.4: distance in meters (GitHub #85)")
do
    local _, OXP = newGame({ level = 5 })
    t.eq(OXP.Arrow.Distance(100), "100 yd", "yards by default")
    OXP.settings.distanceUnit = "meters"
    t.eq(OXP.Arrow.Distance(100), "91 m", "meters")
end

------------------------------------------------------------------------
print("-- 2.0.4: group quests off: never shown, not even once you have one (GitHub #101)")
do
    local game, OXP = newGame({ level = 30 })
    IsInGroup = function() return true end
    addGuide(OXP, {
        { { "accept", quest = 1010 } },
        { when = { { "group", quest = 517 } }, { "accept", quest = 517 } },
        { when = { { "onquest", quests = { 517 } } }, { "complete", quest = 517, obj = 1 } },
        { { "accept", quest = 1020 } },
    })
    OXP.Goals.ResetGroupQuests()
    local W = OXP.Goals.WhenHolds
    local steps = OXP.Engine.GetSteps()
    t.eq(W(steps[2].when), true, "in a group: the group quest shows")
    game:Accept(517, 1)
    t.eq(W(steps[3].when), true, "and its steps once you have it")
    OXP.settings.groupQuests = false
    t.eq(W(steps[2].when), false, "setting off: not shown")
    t.eq(W(steps[3].when), false, "nor the steps for it, even with the quest")
    OXP.settings.groupQuests = true
    IsInGroup = nil
end

------------------------------------------------------------------------
print("-- 2.0.4: 'Point straight at the spot' skips the walking path (GitHub #88)")
do
    local _, OXP = newGame({ level = 5 })
    local base = { wx = 10, wy = 10, map = 1429, x = 50, y = 50 }
    local walk = { wx = 1, wy = 1, map = 1429 }
    local real = OXP.WalkPaths.ForArrow
    OXP.WalkPaths.ForArrow = function() return walk end
    OXP.Target.override = base
    if OXP.Target.BAKED_ONLY then
        local tr = OXP.Target.TripLeg
        OXP.Target.TripLeg = function() return nil end
        t.ok(OXP.Target.Update() == walk, "normally: along the walk")
        OXP.settings.arrowStraight = true
        t.ok(OXP.Target.Update() == base, "straight: at the spot itself")
        OXP.settings.arrowStraight = false
        OXP.Target.TripLeg = tr
    end
    OXP.Target.override = nil
    OXP.WalkPaths.ForArrow = real
end

------------------------------------------------------------------------
print("-- Reset to defaults asks first, then puts every setting back")
do
    local game, OXP = newGame({ level = 21 })
    local s = OXP.settings
    s.skin, s.cardOpacity, s.autoAccept, s.fontSize = "ember", 0.3, false, 18
    s.cardPos = { "CENTER", "CENTER", 10, 10 }
    s.minimap.angle = 45
    OXP.char.guides.keep = { step = 7, skipped = {} }
    OXP.Settings.Show("about")
    local frame = OXP.Settings.frame
    t.ok(frame.reset ~= nil and frame.reset.label.text == "Reset to defaults", "a Reset to defaults button in the footer")
    local dialog = OXP.Settings.AskReset()
    t.ok(dialog and dialog.shown, "it asks first")
    t.eq(s.skin, "ember", "nothing changed yet")
    dialog.no.scripts.OnClick(dialog.no)
    t.ok(not dialog.shown and s.skin == "ember", "Cancel: nothing changes")
    dialog = OXP.Settings.AskReset()
    dialog.yes.scripts.OnClick(dialog.yes)
    t.eq(s.skin, OXP.FIRST_LOAD.skin, "skin back to the start")
    t.eq(s.cardOpacity, OXP.FIRST_LOAD.cardOpacity, "background back")
    t.eq(s.autoAccept, true, "automation back")
    t.eq(s.fontSize, 12, "text size back")
    t.eq(s.cardPos, nil, "card position back")
    t.eq(s.minimap.angle, 200, "minimap button back")
    t.ok(OXP.settings == s, "the same settings table (everything holding it sees the change)")
    t.eq(OXP.char.guides.keep and OXP.char.guides.keep.step, 7, "guide progress stays")
    t.eq(OXP.Style.skinKey, OXP.FIRST_LOAD.skin, "repainted in the new look")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- nameplates: enemies only for quests in your log with the objective open")
do
    local game, OXP = newGame({ level = 23, map = 1442, x = 61.48, y = 55.34 })
    addGuide(OXP, {
        { { "goto", zone = "1442", x = 61.48, y = 55.34 },
          { "complete", obj = 1, quest = 1071, text = "Kill Venture Co. Logger: 10" },
          { "mob", name = "Venture Co. Logger" } },
        { { "goto", zone = "1442", x = 62.5, y = 53.8 },
          { "complete", obj = 1, quest = 1093, text = "Super Reaper 6000 Blueprints: 1" },
          { "mob", name = "Venture Co. Operator" } },
    })
    local saved = { UnitExists = _G.UnitExists, UnitName = _G.UnitName, UnitGUID = _G.UnitGUID,
                    UnitCanAttack = _G.UnitCanAttack, UnitIsPlayer = _G.UnitIsPlayer, C_NamePlate = _G.C_NamePlate }
    local unitName = "Venture Co. Logger"
    local plate = CreateFrame("Frame")
    plate.UnitFrame = CreateFrame("Frame", nil, plate)
    _G.UnitExists = function() return true end
    _G.UnitName = function() return unitName end
    _G.UnitGUID = function() return "Creature-0-0-0-0-4567-0" end
    _G.UnitCanAttack = function() return true end
    _G.UnitIsPlayer = function() return false end
    _G.C_NamePlate = { GetNamePlateForUnit = function() return plate end, GetNamePlates = function() return { plate } end }
    local T = OXP.Tooltips
    t.eq(T.PlateInfo("nameplate1"), nil, "quest not taken yet: no marker on its mob")
    unitName = "Venture Co. Operator"
    t.eq(T.PlateInfo("nameplate1"), nil, "a later step's mob: no marker")
    t.eq(#OXP.ActionButtons.WantedTargets(), 0, "and nothing to target before you have the quest")
    game:Accept(1071, 1)
    unitName = "Venture Co. Logger"
    local info = T.PlateInfo("nameplate1")
    t.ok(info and (info.kind == "mob" or info.kind == "kill"), "quest taken: its mob is marked (" .. tostring(info and info.kind) .. ")")
    T.UpdatePlate("nameplate1")
    local m = T.PlateMarker(plate)
    t.ok(m and m.badge.texture and m.badge.texture:find("Map.kill"), "with the map's silver sword: " .. tostring(m and m.badge.texture))
    -- GitHub #98: in dungeons the game hands back secret unit names and
    -- GUIDs; comparing or indexing with one throws
    local SECRET = setmetatable({}, { __eq = function() error("compared a secret") end,
                                      __index = function() error("indexed a secret") end,
                                      __concat = function() error("joined a secret") end })
    local savedName, savedGUID = _G.UnitName, _G.UnitGUID
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    _G.UnitName = function() return SECRET end
    _G.UnitGUID = function() return SECRET end
    local ok, err = pcall(T.PlateInfo, "nameplate1")
    t.ok(ok, "secret name: no nameplate error (" .. tostring(err) .. ")")
    t.eq(err, nil, "and no marker")
    local tip = { AddLine = function() error("tooltip line for a secret unit") end, Show = function() end }
    ok, err = pcall(T.AddLines, tip, "mouseover")
    t.ok(ok, "secret name: no tooltip error (" .. tostring(err) .. ")")
    ok, err = pcall(OXP.ActionButtons.SeeUnit, "target")
    t.ok(ok, "secret name: no targets-list portrait error (" .. tostring(err) .. ")")
    _G.UnitName, _G.UnitGUID, _G.issecretvalue = savedName, savedGUID, nil
    unitName = "Venture Co. Operator"
    t.eq(T.PlateInfo("nameplate1"), nil, "the later step's mob still isn't marked")
    game:FinishObjective(1071, 1)
    unitName = "Venture Co. Logger"
    t.eq(T.PlateInfo("nameplate1"), nil, "objective done: marker gone")
    OXP.settings.nameplates = false
    game:Abandon(1071)
    game:Accept(1071, 1)
    T.UpdatePlate("nameplate1")
    t.ok(not T.PlateMarker(plate):IsShown(), "setting off: no markers")
    OXP.settings.nameplates = true
    for k, v in pairs(saved) do _G[k] = v end
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- nameplates over people: one marker, no step number unless asked")
do
    local game, OXP = newGame({ level = 5, map = 1426, x = 46, y = 52 })
    addGuide(OXP, {
        { { "goto", zone = "1426", x = 46.8, y = 52.4 },
          { "accept", quest = 7001, text = "Accept Test" }, { "target", name = "Nori Pridedrift" },
          { "goto", zone = "1426", x = 46.8, y = 52.5 },
          { "accept", quest = 7002, text = "Accept Talk" }, { "talk", name = "x" }, { "target", name = "Grelin Whitebeard" } },
    })
    local saved = { UnitExists = _G.UnitExists, UnitName = _G.UnitName, UnitGUID = _G.UnitGUID,
                    UnitCanAttack = _G.UnitCanAttack, UnitIsPlayer = _G.UnitIsPlayer }
    local unitName = "Nori Pridedrift"
    _G.UnitExists = function() return true end
    _G.UnitName = function() return unitName end
    _G.UnitGUID = function() return "Creature-0-0-0-0-1234-0" end
    _G.UnitCanAttack = function() return false end
    _G.UnitIsPlayer = function() return false end
    local T = OXP.Tooltips
    local info = T.PlateInfo("nameplate1")
    t.ok(info and info.kind == "target", "the person to talk to: the talk marker (" .. tostring(info and info.kind) .. ")")
    t.eq(info and info.text, "", "no step number by default")
    OXP.settings.nameplateStepNumbers = true
    info = T.PlateInfo("nameplate1")
    t.eq(info and info.text, "#1", "step number when asked for")
    t.eq(OXP.settings.nameplateGivers, false, "OpenXP's own ! ? over quest givers is off by default (the game shows its own)")
    for k, v in pairs(saved) do _G[k] = v end
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- a character saved on a removed guide (the 1.x 21-60 'OpenXP Legacy' ones) gets the leveling route")
do
    local KEY = "OpenXP Legacy (Alliance)/21-22 Ashenvale <Alliance>"
    local saved = {
        OpenXPDB = nil,
        OpenXPCharDB = { schema = 1, currentGuide = KEY, guides = { [KEY] = { step = 12, skipped = {}, status = {} } },
                         flightPaths = { astranaar = true }, trainers = {} },
    }
    local game = FakeWoW.New(ROOT, { level = 22, faction = "Alliance", race = "Human", class = "WARRIOR",
                                    map = 1440, x = 36, y = 49 }, saved)
    local OXP = game:LoadAddon()
    game:Login()
    game:Advance(1)
    local g = OXP.Engine.GetGuide()
    t.ok(g ~= nil, "a guide is loaded")
    t.eq(g and g.group, "OpenXP Leveling (Alliance)", "the leveling route (smart start): " .. tostring(g and g.name))
    t.ok(OXP.char.currentGuide ~= KEY, "the removed guide is forgotten")
    t.eq(OXP.Engine.lostGuide, KEY, "and noted")
    t.ok(OXP.World.KnowsFlightPath("Astranaar"), "flight paths stay")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- Call of Earth (Dwarf Shaman): the Earth Sapta button, the chain's parts, More below the text")
do
    local game, OXP = newGame({ level = 5, race = "Dwarf", class = "SHAMAN", map = 1426, x = 28.79, y = 66.18 })
    InCombatLockdown = function() return false end
    addGuide(OXP, {
        { { "text", text = "Call of Earth" },
          { "goto", x = 28.79, y = 66.18, zone = "1426" },
          { "turnin", quest = 94373, text = "Turn in Call of Earth" }, { "target", name = "Teo Hammerstorm" },
          { "goto", x = 28.79, y = 66.18, zone = "1426" },
          { "accept", quest = 94374, text = "Accept Call of Earth" }, { "target", name = "Teo Hammerstorm" },
          { "goto", x = 25, y = 62.4, zone = "1426" },
          { "item", item = 6635, text = "Use Earth Sapta (|cOXP_LOOT_Earth Sapta|r, beside the Spirit Stone)" },
          { "goto", x = 24.8, y = 61.8, zone = "1426" },
          { "turnin", quest = 94374, text = "Turn in Call of Earth" }, { "target", name = "Minor Manifestation of Earth" },
          { "goto", x = 24.8, y = 61.8, zone = "1426" },
          { "accept", quest = 94375, text = "Accept Call of Earth" }, { "target", name = "Minor Manifestation of Earth" },
          { "goto", x = 28.79, y = 66.18, zone = "1426" },
          { "turnin", quest = 94375, text = "Turn in Call of Earth (|cOXP_FRIENDLY_Teo Hammerstorm|r: Stoneskin Totem)" },
          { "target", name = "Teo Hammerstorm" } },
    })
    game:Accept(94373, 0)
    game:TurnIn(94373)
    game:Accept(94374, 0)
    local B = OXP.ActionButtons
    t.eq(B.WantedItem(), nil, "no Sapta in the bags yet: no button")
    game:AddItem(6635, 1)
    t.eq(B.WantedItem(), 6635, "part 2 accepted, Sapta in the bags: the button offers it")
    game:TurnIn(94374)
    t.eq(B.WantedItem(), nil, "part 2 handed in: the button goes")

    local _, lines = OXP.Card.StepContent(OXP.Engine.GetSteps()[1])
    local texts = {}
    for _, l in ipairs(lines) do texts[#texts + 1] = OXP.Text.Strip(l.text) end
    local all = table.concat(texts, " | ")
    t.ok(all:find("Turn in Call of Earth (part 1)", 1, true), "part 1 named: " .. all)
    t.ok(all:find("Accept Call of Earth (part 2)", 1, true), "part 2 named")
    t.ok(all:find("Turn in Call of Earth (part 3) (Teo Hammerstorm", 1, true), "part 3 named, before its note")
    t.eq(#lines, 6, "every line once (no true duplicates here)")

    -- the same quest and action twice in a step: shown once
    local step = { goals = { { "accept", quest = 94374, text = "Accept Call of Earth" },
                             { "accept", quest = 94374, text = "Accept Call of Earth" } }, marks = {} }
    local _, two = OXP.Card.StepContent(step)
    t.ok(#two <= 1, "a real duplicate line is dropped")

    -- More: its own row under the steps, never over a line
    OXP.settings.cardHeight = 180
    OXP.Card.height = 180
    OXP.Card.Refresh(true)
    local more = OXP.Card.more
    t.ok(OXP.Card.overflow, "a long step on a short card: cut off")
    t.ok(more:IsShown(), "More shown")
    local p = more.points[#more.points]
    t.ok(p and p[1] == "TOPRIGHT" and p[3] == "BOTTOMRIGHT", "More sits under the step text, not on it")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

return t.fails
