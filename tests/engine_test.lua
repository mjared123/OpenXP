-- OpenXP 2.0 engine: filters, guide registry, quest state and the step runner,
-- on small made-up guides in the headless client (tests/lib/fakewow.lua).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("engine")

local function newGame(opts, saved)
    local game = FakeWoW.New(ROOT, opts, saved)
    game:LoadAddon()
    return game, game.ns
end

-- A guide made of the given steps, registered under a unique name.
local counter = 0
local function addGuide(OXP, steps, extra)
    counter = counter + 1
    local g = { name = "Test " .. counter, group = "Test", steps = steps }
    for k, v in pairs(extra or {}) do g[k] = v end
    OXP.AddGuides({ file = "test", g })
    return g
end

local function messages(OXP)
    local seen = {}
    for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "GUIDE_FINISHED", "NO_GUIDE" }) do
        OXP.Listen(m, function(name, arg) seen[#seen + 1] = name; seen[name] = (seen[name] or 0) + 1; seen.last = arg end)
    end
    return seen
end

------------------------------------------------------------------------
print("-- filters")
do
    local _, OXP = newGame()
    local F = OXP.Filters
    local human = { faction = "Alliance", race = "Human", class = "PALADIN", level = 30 }
    local undead = { faction = "Horde", race = "Scourge", class = "PALADIN", level = 30 }
    local neutral = { faction = "Neutral", race = "Skyborne", class = "MAGE", level = 5 }
    t.ok(F.Matches(nil, human) and F.Matches("", human), "empty filter passes")
    t.ok(F.Matches("Alliance", human), "faction")
    t.ok(not F.Matches("Horde", human), "other faction")
    t.ok(F.Matches("Human Paladin/Dwarf Paladin", human), "AND inside an OR")
    t.ok(not F.Matches("Dwarf Paladin/Human Warrior", human), "no choice matches")
    t.ok(F.Matches("Undead Paladin", undead), "Undead means Scourge")
    t.ok(F.Matches("paladin", human), "case-insensitive")
    t.ok(F.Matches("!Warrior", human) and not F.Matches("!Paladin", human), "negation")
    t.ok(F.Matches("30", human) and not F.Matches("31", human), "level")
    t.ok(F.Matches("Alliance", neutral) and F.Matches("Horde", neutral), "Neutral passes faction filters")
    t.ok(F.Matches("Skyborne Mage", neutral), "Skyborne race")
    t.eq(#F.UnknownWords("Human Paladni/Dwarf"), 1, "typo found")
end

------------------------------------------------------------------------
print("-- only your own faction's guides are loaded (memory)")
do
    local game, OXP = newGame({ faction = "Alliance" })
    game:Login()
    local horde = 0
    for _, g in ipairs(OXP.Registry.All()) do if g.faction == "Horde" then horde = horde + 1 end end
    t.eq(horde, 0, "an Alliance character loads no Horde guide data")
    t.ok(#OXP.Registry.All() >= 40, "but all of its own: " .. #OXP.Registry.All())
end

------------------------------------------------------------------------
print("-- shipped guide data")
do
    -- a character that hasn't picked a side loads both factions' guides
    -- (everyone else only their own: see the next test)
    local game, OXP = newGame({ faction = "Neutral" })
    game:Login()
    local problems = OXP.Registry.Problems()
    t.eq(#problems, 0, "guide data problems")
    for i = 1, math.min(#problems, 10) do print("    " .. problems[i]) end
    local all = OXP.Registry.All()
    t.ok(#all >= 90, "guides loaded: " .. #all)
    local wc = 0
    for _, g in ipairs(all) do
        if g.name == "17-24 Wailing Caverns" then wc = wc + 1 end
        if g.next then
            -- a player who can use this guide: the race it names, if any
            local races = g.faction == "Horde" and { "Orc", "Troll", "Scourge", "Tauren", "Skyborne" }
                or { "Human", "Dwarf", "Gnome", "NightElf", "Skyborne" }
            local p
            for _, race in ipairs(races) do
                local try = { faction = g.faction or "Alliance", race = race, class = "WARRIOR", level = 60 }
                if OXP.Registry.IsAvailable(g, try) then p = try break end
            end
            t.ok(p and OXP.Registry.Next(g, p), g.key .. ": #next '" .. g.next .. "' not found")
        end
    end
    t.eq(wc, 2, "Alliance and Horde Wailing Caverns both kept")
    local alliance = OXP.Registry.ForPlayer({ faction = "Alliance", race = "Human", class = "MAGE", level = 1 })
    for _, g in ipairs(alliance) do
        t.ok(g.faction ~= "Horde", "Alliance player offered " .. g.key)
    end
    local groups = OXP.Registry.Groups({ faction = "Horde", race = "Orc", class = "MAGE", level = 1 })
    t.ok(#groups >= 2, "Horde sees leveling and dungeon groups")
end

------------------------------------------------------------------------
print("-- bad guide data is reported, not loaded silently")
do
    local _, OXP = newGame()
    addGuide(OXP, { { { "accpet", quest = 1 } } })
    addGuide(OXP, { { { "text", text = "only words" } } })
    addGuide(OXP, { { only = "Humna", { "accept", quest = 1 } } })
    addGuide(OXP, { { { "complete", quest = 1 } } })
    local p = OXP.Registry.Problems()
    local all = table.concat(p, "\n")
    t.ok(all:find("unknown goal kind 'accpet'"), "unknown kind")
    t.ok(all:find("nothing to finish it"), "hint-only step")
    t.ok(all:find("unknown filter word 'Humna'"), "filter typo")
    t.ok(all:find("has no obj"), "missing field")
end

------------------------------------------------------------------------
print("-- quest steps advance as the player plays")
do
    local game, OXP = newGame({ level = 20 })
    game:Login()
    local seen = messages(OXP)
    local g = addGuide(OXP, {
        { { "goto", zone = "Elwynn Forest", x = 1, y = 2 }, { "accept", quest = 10 } },
        { { "complete", quest = 10, obj = 1 }, { "complete", quest = 10, obj = 2 } },
        { { "turnin", quest = 10 }, { "accept", quest = 11 } },
        { { "turnin", quest = 11 } },
    })
    local E = OXP.Engine
    t.ok(E.Load(g.key), "load")
    t.eq(E.GetPosition(), 1, "starts at step 1")
    t.eq(E.GoalState(1, g.steps[1][1]), "info", "goto is a hint")
    t.eq(E.GoalState(1, g.steps[1][2]), "todo", "accept todo")
    game:Accept(10, 2)
    t.eq(E.GetPosition(), 2, "accept -> step 2")
    game:FinishObjective(10, 1)
    t.eq(E.GetPosition(), 2, "one objective of two")
    t.eq(E.GoalState(2, g.steps[2][1]), "done", "objective 1 done")
    game:FinishObjective(10, 2)
    t.eq(E.GetPosition(), 3, "both objectives -> step 3")
    game:Accept(11, 0)
    t.eq(E.GetPosition(), 3, "turn in still needed")
    game:TurnIn(10)
    t.eq(E.GetPosition(), 4, "turn in + accept -> step 4")
    t.eq(OXP.char.guides[g.key].step, 4, "position saved")
    game:TurnIn(11)
    t.eq(E.GetPosition(), 5, "finished")
    t.eq(seen.GUIDE_FINISHED, 1, "GUIDE_FINISHED once")
    local done, total = E.GetProgress()
    t.ok(done == 4 and total == 4, "progress 4/4")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- objectives read from the quest log when the per-quest API is missing")
do
    local game, OXP = newGame({ noObjectiveAPI = true })
    game:Login()
    local g = addGuide(OXP, {
        { { "complete", quest = 20, obj = 2 } },
        { { "turnin", quest = 20 } },
    })
    game:Accept(20, 2)
    OXP.Engine.Load(g.key)
    t.eq(OXP.Engine.GetPosition(), 1, "objective 2 not done")
    game:FinishObjective(20, 2)
    t.eq(OXP.Engine.GetPosition(), 2, "objective 2 done (leaderboard)")
    local o = OXP.Quests.GetObjective(20, 2)
    t.ok(o and o.done and o.have == 1 and o.need == 1, "have/need parsed from the text")
end

------------------------------------------------------------------------
print("-- a quest whose details load late still moves the guide on (Wetlands step 8)")
do
    -- In game: accepting one of WoW Forever's own quests, the log entry had no
    -- quest id yet when the events came, no event followed when it loaded,
    -- and the step only moved on when an unrelated trainer window opened.
    local game, OXP = newGame({ level = 22 })
    game:Login()
    local g = addGuide(OXP, {
        { { "accept", quest = 98197 } },
        { { "complete", quest = 98197, obj = 1 } },
    })
    OXP.Engine.Load(g.key)
    game.unloaded[98197] = true
    game:Accept(98197, 1)
    t.eq(OXP.Engine.GetPosition(), 1, "not in the log yet as far as the game says")
    game.unloaded[98197] = nil -- loads, no event
    game:Advance(1)
    game:Advance(1)
    game:Advance(1)
    t.eq(OXP.Engine.GetPosition(), 2, "moves on within a few seconds without any event")
    t.eq(OXP.Engine.GoalState(2, g.steps[2][1]), "todo", "an objective isn't taken as done while details are missing")
end

------------------------------------------------------------------------
print("-- quests under a collapsed header still count")
do
    local game, OXP = newGame()
    game:Login()
    game:Accept(30, 1)
    game.collapsed[30] = true
    OXP.Quests.Invalidate()
    t.ok(OXP.Quests.IsOnQuest(30), "on quest though hidden")
    t.ok(not OXP.Quests.IsComplete(30), "not complete")
    game:FinishObjective(30, 1)
    t.ok(OXP.Quests.IsComplete(30), "complete through the per-quest API")
end

------------------------------------------------------------------------
print("-- done steps are passed over; optional quests don't block")
do
    local game, OXP = newGame()
    game:Login()
    game.completed[40] = true
    local g = addGuide(OXP, {
        { { "accept", quest = 40 } },                       -- already turned in
        { { "turnin", quest = 41, optional = true } },      -- not on it: skipped
        { { "complete", quest = 42, obj = 1, optional = true }, { "accept", quest = 43 } },
        { { "turnin", quest = 43 } },
    })
    OXP.Engine.Load(g.key)
    t.eq(OXP.Engine.GetPosition(), 3, "steps 1-2 passed over on load")
    t.eq(OXP.Engine.GoalState(3, g.steps[3][1]), "skip", "optional objective skipped")
    game:Accept(43, 0)
    t.eq(OXP.Engine.GetPosition(), 4, "optional goal didn't block")
    game:Accept(41, 0)
    t.eq(OXP.Engine.StepState(2), "done", "earlier step stays passed")
end

------------------------------------------------------------------------
print("-- completewith next: travel steps finish with the step after them")
do
    local game, OXP = newGame()
    game:Login()
    local g = addGuide(OXP, {
        { completewith = "next", { "zone", name = "Duskwood" } },
        { { "accept", quest = 50 } },
        { { "turnin", quest = 50 } },
    })
    local E = OXP.Engine
    E.Load(g.key)
    local active = E.GetActive()
    t.ok(#active == 2 and active[1] == 1 and active[2] == 2, "both steps shown")
    game:Accept(50, 0)
    t.eq(E.GetPosition(), 3, "travel step finished by the next one")
    local g2 = addGuide(OXP, {
        { completewith = "next", { "zone", name = "Duskwood" } },
        { { "accept", quest = 51 } },
    })
    E.Load(g2.key)
    game:EnterZone("Duskwood", "Darkshire")
    t.eq(E.GetPosition(), 2, "arriving finishes the travel step")
end

------------------------------------------------------------------------
print("-- level, zone, item, flight path and hearthstone goals")
do
    local game, OXP = newGame({ level = 20, bind = "Goldshire" })
    game:Login()
    local g = addGuide(OXP, {
        { { "xp", level = 21 } },
        { { "zone", name = "Darkshire" } },
        { { "collect", item = 900, count = 3 } },
        { { "fp", name = "Tarren Mill" } },
        { { "fp", name = "Astranaar" } },
        { { "home", text = "Set your Hearthstone to Astranaar" } },
        { { "home" } },
        { { "accept", quest = 60 } },
    })
    local E = OXP.Engine
    E.Load(g.key)
    game:SetLevel(21)
    t.eq(E.GetPosition(), 2, "level 21")
    game:EnterZone("Duskwood", "Darkshire")
    t.eq(E.GetPosition(), 3, "sub-zone counts as the zone")
    game:AddItem(900, 2)
    t.eq(E.GetPosition(), 3, "2 of 3 items")
    game:AddItem(900, 1)
    t.eq(E.GetPosition(), 4, "3 items")
    game:OpenTaxi({ "Tarren Mill, Hillsbrad", "Southshore, Hillsbrad" })
    t.eq(E.GetPosition(), 5, "flight path from the taxi map")
    t.ok(OXP.World.KnowsFlightPath("Southshore"), "other known paths remembered")
    game:DiscoverFlightPath()
    t.eq(E.GetPosition(), 6, "flight path from the discovery message")
    t.ok(OXP.World.KnowsFlightPath("Astranaar"), "discovered path remembered")
    game:Bind("Darkshire")
    t.eq(E.GetPosition(), 6, "wrong town doesn't count")
    game:Bind("Astranaar")
    t.eq(E.GetPosition(), 7, "hearth set to the named town")
    game:Bind("Menethil Harbor")
    t.eq(E.GetPosition(), 8, "unnamed hearth goal: any new bind while shown")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- step and goal filters")
do
    local game, OXP = newGame({ faction = "Horde", race = "Scourge", class = "WARLOCK" })
    game:Login()
    local g = addGuide(OXP, {
        { only = "Warrior", { "accept", quest = 70 } },
        { { "accept", quest = 71 }, { "accept", quest = 72, only = "Mage" } },
        { only = "Undead Warlock/Orc Warlock", { "accept", quest = 73 } },
    })
    local E = OXP.Engine
    E.Load(g.key)
    local steps = E.GetSteps()
    t.eq(#steps, 2, "warrior step left out")
    t.eq(steps[1].index, 2, "steps keep their guide index")
    t.eq(#steps[1].goals, 1, "mage goal left out")
    game:Accept(71, 0)
    t.eq(E.GetPosition(), 2, "only the warlock's goals count")
end

------------------------------------------------------------------------
print("-- going back, holding a step, skipping")
do
    local game, OXP = newGame()
    game:Login()
    local g = addGuide(OXP, {
        { { "accept", quest = 80 } },
        { { "accept", quest = 81 } },
        { { "accept", quest = 82 } },
    })
    local E = OXP.Engine
    E.Load(g.key)
    game:Accept(80, 0)
    t.eq(E.GetPosition(), 2, "step 1 done")
    E.Back()
    t.eq(E.GetPosition(), 1, "back to a done step and it stays")
    game:Accept(81, 0)
    t.eq(E.GetPosition(), 1, "still held after other progress")
    E.Next()
    t.eq(E.GetPosition(), 3, "next: step 2 is already done, lands on 3")
    E.Next()
    t.eq(E.GetPosition(), 4, "skip an unfinished step")
    t.eq(E.StepState(3), "skipped", "marked skipped")
    E.GoTo(3)
    t.eq(E.StepState(3), "current", "going to a skipped step un-skips it")
    t.ok(not E.IsHeld(), "a step still to do isn't held")
    game:Accept(82, 0)
    t.eq(E.GetPosition(), 4, "doing it moves on by itself (in game: Wetlands step 8 sat held)")
    t.eq(E.StepState(3), "done", "done, not skipped")
end

------------------------------------------------------------------------
print("-- progress survives a reload; finished guide hands over to #next")
do
    local game, OXP = newGame({ level = 22 })
    game:Login()
    local second = addGuide(OXP, { { { "accept", quest = 91 } }, { { "accept", quest = 92 } } }, { name = "Second" })
    local first = addGuide(OXP, { { { "accept", quest = 90 } } }, { name = "First", next = "Second" })
    OXP.Engine.Load(first.key)
    local seen = messages(OXP)
    game:Accept(90, 0)
    t.eq(OXP.Engine.GetGuide(), second, "next guide loaded")
    t.eq(seen.GUIDE_FINISHED, 1, "first guide finished")
    game:Accept(91, 0)
    t.eq(OXP.char.currentGuide, second.key, "current guide saved")

    -- Reload: same saved variables, same quest state, guides added again.
    local saved = game:SavedVariables()
    local game2, OXP2 = newGame({ level = 22 }, saved)
    game2.log, game2.completed = game.log, game.completed
    OXP2.AddGuides({ file = "test", { name = "Second", group = "Test", steps = second.steps } })
    game2:Login()
    t.eq(OXP2.Engine.GetGuide() and OXP2.Engine.GetGuide().key, second.key, "guide restored at login")
    t.eq(OXP2.Engine.GetPosition(), 2, "step restored at login")

    local game3, OXP3 = newGame()
    local seen3 = messages(OXP3)
    game3:Login()
    t.eq(seen3.NO_GUIDE, 1, "a new character gets NO_GUIDE")
end

------------------------------------------------------------------------
print("-- messages for the UI")
do
    local game, OXP = newGame()
    game:Login()
    local seen = messages(OXP)
    local g = addGuide(OXP, { { { "complete", quest = 95, obj = 1 }, { "complete", quest = 95, obj = 2 } }, { { "turnin", quest = 95 } } })
    game:Accept(95, 2)
    OXP.Engine.Load(g.key)
    t.eq(seen.GUIDE_LOADED, 1, "GUIDE_LOADED")
    local before = seen.STEPS_UPDATED or 0
    game:FinishObjective(95, 1)
    t.eq((seen.STEPS_UPDATED or 0) - before, 1, "STEPS_UPDATED when a goal changes")
    game:Fire("QUEST_LOG_UPDATE")
    game:Flush()
    t.eq((seen.STEPS_UPDATED or 0) - before, 1, "not again when nothing changed")
    game:FinishObjective(95, 2)
    t.eq(seen.STEP_CHANGED, 1, "STEP_CHANGED")
end

------------------------------------------------------------------------
print("-- every as-you-go step in the shipped guides ends (1.x: a Darkshore tip never did)")
do
    local _, OXP = newGame({ level = 20 })
    local n, bad = 0, {}
    for _, g in ipairs(OXP.Registry.All()) do
        for i, st in ipairs(g.steps) do
            if st.along then
                n = n + 1
                local u = st["until"]
                local finishes = false
                for _, goal in ipairs(st) do
                    if OXP.Goals.Blocks(goal[1]) then finishes = true end
                end
                if u and (u <= i or u > #g.steps) then
                    bad[#bad + 1] = g.name .. " step " .. i .. ": until " .. u .. " isn't a later step"
                elseif not u and not finishes then
                    bad[#bad + 1] = g.name .. " step " .. i .. ": no until and nothing finishes it"
                end
            end
        end
    end
    t.ok(n > 0, "the guides have as-you-go steps: " .. n)
    t.eq(#bad, 0, "each one ends: " .. table.concat(bad, " | "))
end

------------------------------------------------------------------------
print("-- travel steps aren't passed from where you've been before (Darkshore boat to Menethil)")
do
    -- In game (22-25 Ashenvale, Wetlands & Stonetalon): flying Astranaar ->
    -- Auberdine, the boat step was passed as soon as the flight crossed into
    -- Darkshore (its reach counted as "the way into Darkshore": the step
    -- before it is in Ashenvale), and "To Menethil Harbor" (only a flight
    -- path to learn) with it, as the character had been to the Wetlands.
    local game, OXP = newGame({ level = 24, race = "NightElf", map = 1440, x = 34.5, y = 48 })
    game:Login()
    OXP.char.flightPaths[OXP.Util.PlaceKey("Menethil Harbor")] = true -- been there before
    local g = addGuide(OXP, {
        { { "reach", text = "Astranaar flight master", x = 34.5, y = 48, zone = "1440" },
          { "fly", name = "Auberdine", text = "Fly to Auberdine" } },
        { { "reach", text = "Boat to Menethil Harbor", x = 32.4, y = 43.8, zone = "1439" } },
        { { "goto", x = 9.49, y = 59.69, zone = "1437" }, { "fp", name = "Menethil Harbor" } },
        { { "accept", quest = 279 } },
    })
    local E = OXP.Engine
    E.Load(g.key)
    t.eq(E.GetPosition(), 1, "at the Astranaar flight master")
    local dock = E.GetSteps()[2].goals[1]
    t.ok(not dock.entry, "the dock isn't a way into Darkshore (you fly in)")
    t.eq(dock.past, 1437, "it leads to the Wetlands")
    E.TakeOff()
    t.eq(E.GetPosition(), 2, "taking off: on the boat step")
    game:MoveTo(1439, 36, 45) -- over Darkshore, then landed at Auberdine
    game:Advance(1)
    game:Advance(1)
    game:Advance(1)
    t.eq(E.GetPosition(), 2, "in Darkshore, away from the dock: still the boat step")
    game:MoveTo(1439, 32.5, 43.9)
    game:Advance(1)
    t.eq(E.GetPosition(), 4, "at the dock: on to Menethil (its flight path is known)")
    -- and without the dock: arriving in the Wetlands passes the boat step
    game:MoveTo(1439, 40, 60)
    E.GetSteps()[2].marks[dock] = nil -- as on a fresh load of the guide
    E.GoTo(2, true)
    game:Advance(1)
    t.eq(E.GetPosition(), 2, "back on the boat step in Darkshore")
    game:MoveTo(1437, 5, 63)
    game:Advance(1)
    t.eq(E.GetPosition(), 4, "off the boat in the Wetlands: passed")
    t.eq(#game.errors, 0, "no Lua errors: " .. table.concat(game.errors, " | "))
end

------------------------------------------------------------------------
print("-- a relog or /reload keeps the step you were on")
do
    local steps = {
        { { "accept", quest = 300 } },
        { { "accept", quest = 301 } },
        { { "accept", quest = 302 } },
        { { "accept", quest = 303 } },
    }
    local game, OXP = newGame({ level = 22 })
    game:Login()
    local g = addGuide(OXP, steps, { name = "Relog" })
    OXP.Engine.Load(g.key)
    game:Accept(300, 0)
    t.eq(OXP.Engine.GetPosition(), 2, "on step 2")
    t.eq(OXP.char.guides[g.key].step, 2, "step 2 saved")
    -- quests 301-302 picked up while the guide wasn't looking: step 2 and 3 look done
    local log = {}
    for _, q in ipairs(game.log) do log[#log + 1] = q end
    log[#log + 1] = { id = 301, title = "Quest 301", objectives = {} }
    log[#log + 1] = { id = 302, title = "Quest 302", objectives = {} }

    local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = copy(x) end
        return out
    end
    local saved = copy(game:SavedVariables())
    local function relog()
        local g2, O2 = newGame({ level = 22 }, copy(saved))
        O2.AddGuides({ file = "test", { name = "Relog", group = "Test", steps = steps } })
        g2.completed = game.completed
        g2.log = {} -- at PLAYER_LOGIN the quest log isn't there yet
        g2:Login()
        return g2, O2
    end

    local game2, OXP2 = relog()
    t.eq(OXP2.Engine.GetGuide() and OXP2.Engine.GetGuide().key, g.key, "guide restored")
    t.eq(OXP2.Engine.GetPosition(), 2, "on step 2 at login")
    game2:Advance(1)
    game2.log = log -- the quest log arrives: step 2's quest is in it
    game2:Fire("QUEST_LOG_UPDATE")
    game2:Flush()
    for _ = 1, 8 do game2:Advance(1) end
    t.eq(OXP2.Engine.GetPosition(), 2, "still step 2 once the quest log has loaded and settled")
    t.eq(OXP2.char.guides[g.key].step, 2, "and still saved as step 2")
    t.ok(OXP2.Engine.GoalState(2, OXP2.Engine.GetSteps()[2].goals[1]) == "done", "though its goal looks done")
    OXP2.Engine.Next()
    t.eq(OXP2.Engine.GetPosition(), 4, "moving on by hand passes the done step 3")
    t.eq(#game2.errors, 0, "no Lua errors: " .. table.concat(game2.errors, " | "))

    -- live progress after login still moves the guide on
    log[#log] = nil -- 302 not taken
    table.remove(log, #log) -- nor 301
    local game3, OXP3 = relog()
    t.eq(OXP3.Engine.GetPosition(), 2, "step 2 again")
    game3.log = log
    game3:Fire("QUEST_LOG_UPDATE")
    game3:Flush()
    for _ = 1, 5 do game3:Advance(1) end
    t.eq(OXP3.Engine.GetPosition(), 2, "nothing done yet")
    game3:Accept(301, 0)
    t.eq(OXP3.Engine.GetPosition(), 3, "accepting it live moves on")
    game3:Accept(302, 0)
    t.eq(OXP3.Engine.GetPosition(), 4, "and on")
    t.eq(#game3.errors, 0, "no Lua errors: " .. table.concat(game3.errors, " | "))
end


do
    -- In game (2.0.0-dev7): WoW restarted on Auberdine's dock left the card on
    -- "DONE: Boat to Menethil Harbor" for the whole boat ride: the restored
    -- step was already done, so nothing could change live to let it go.
    local steps = {
        { { "accept", quest = 310 } },
        { { "text", text = "Boat to Menethil Harbor" },
          { "reach", text = "Boat to Menethil Harbor", x = 32.4, y = 43.8, zone = "1439" } },
        { { "goto", x = 9.49, y = 59.69, zone = "1437" }, { "accept", quest = 311 } },
    }
    local game, OXP = newGame({ level = 22, race = "NightElf", map = 1439, x = 40, y = 60 })
    game:Login()
    local g = addGuide(OXP, steps, { name = "Dock relog" })
    OXP.Engine.Load(g.key)
    game:Accept(310, 0)
    t.eq(OXP.Engine.GetPosition(), 2, "on the boat step")
    local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = copy(x) end
        return out
    end
    local saved = copy(game:SavedVariables())
    local function relog(x, y)
        local g2, O2 = newGame({ level = 22, race = "NightElf", map = 1439, x = x, y = y }, copy(saved))
        O2.AddGuides({ file = "test", { name = "Dock relog", group = "Test", steps = steps } })
        g2.completed = game.completed
        g2.log = game.log
        g2:Login()
        return g2, O2
    end
    local game2, OXP2 = relog(32.4, 43.8) -- logged in on the dock
    for _ = 1, 8 do game2:Advance(1) end
    t.eq(OXP2.Engine.GetPosition(), 2, "restored on the dock: the boat step stays shown")
    game2:MoveTo(1439, 32.45, 43.85) -- a few steps along the pier
    for _ = 1, 3 do game2:Advance(1) end
    t.eq(OXP2.Engine.GetPosition(), 2, "a few steps on the pier: still there")
    game2:MoveTo(1439, 31.0, 44.5) -- the boat pulls out
    for _ = 1, 2 do game2:Advance(1) end
    t.eq(OXP2.Engine.GetPosition(), 3, "the boat leaves: on to Menethil Harbor")
    t.eq(#game2.errors, 0, "no Lua errors: " .. table.concat(game2.errors, " | "))

    -- logged in away from the dock: walking there still moves on as before
    local game3, OXP3 = relog(40, 60)
    for _ = 1, 8 do game3:Advance(1) end
    t.eq(OXP3.Engine.GetPosition(), 2, "restored away from the dock: boat step")
    game3:MoveTo(1439, 32.4, 43.8)
    for _ = 1, 2 do game3:Advance(1) end
    t.eq(OXP3.Engine.GetPosition(), 3, "at the dock: on to Menethil Harbor")
end

return t.fails
