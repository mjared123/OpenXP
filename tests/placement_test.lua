-- OpenXP 2.0 smart start: picking the right guide and step for a character
-- from their level, zone and quests, skipping chains they missed and quests
-- gone gray, with the real 21-60 guides in the headless client.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("placement")

local function newGame(opts)
    local game = FakeWoW.New(ROOT, opts)
    local OXP = game:LoadAddon()
    return game, OXP
end

-- All quest ids a guide accepts / turns in, for this player.
local function questsOf(OXP, guide, kind)
    local out = {}
    for _, steps in pairs(OXP.SmartStart.QuestSteps(guide)) do
        for _, q in ipairs(steps) do
            if not kind or q.tag == kind then out[#out + 1] = q.id end
        end
    end
    return out
end

------------------------------------------------------------------------
print("-- a fresh level 21 character in Ashenvale gets PoleStar's Ashenvale section near its start")
do
    local game, OXP = newGame({ faction = "Alliance", race = "Human", class = "WARRIOR", level = 21, zone = "Ashenvale" })
    game:Login() -- no guide yet: NO_GUIDE -> smart start
    local g = OXP.Engine.GetGuide()
    t.ok(g and g.group == "OpenXP Leveling (Alliance)" and g.name:find("Ashenvale", 1, true),
        "picked " .. tostring(g and g.name))
    t.ok(OXP.Engine.GetPosition() <= 3, "near the start of the section: step " .. tostring(OXP.Engine.GetPosition()))
end

------------------------------------------------------------------------
print("-- in the middle of a section: resume it past the done part")
do
    local game, OXP = newGame({ faction = "Horde", race = "Orc", class = "SHAMAN", level = 25 })
    local guide = OXP.Registry.Find("24-26 The Barrens & Stonetalon Mountains", "OpenXP Leveling (Horde)")
    t.ok(guide, "Horde 24-26 The Barrens & Stonetalon Mountains exists")
    if guide then
        -- the first half of its quests done, one in the log
        local all = questsOf(OXP, guide)
        local seen, n = {}, 0
        for _, id in ipairs(all) do
            if not seen[id] then
                seen[id] = true
                n = n + 1
            end
        end
        local half, k, inLog = math.floor(n / 2), 0, nil
        seen = {}
        for _, id in ipairs(all) do
            if not seen[id] then
                seen[id] = true
                k = k + 1
                if k <= half then game.completed[id] = true elseif not inLog then inLog = id end
            end
        end
        game:Accept(inLog, 0)
        game:Login()
        OXP.SmartStart.Run(true)
        t.eq(OXP.Engine.GetGuide(), guide, "resumed the section with its quest in your log")
        t.ok((OXP.Engine.GetPosition() or 1) > 3, "past the done part: step " .. tostring(OXP.Engine.GetPosition()))
    end
end

------------------------------------------------------------------------
print("-- a chain you missed: its steps are skipped and marked")
do
    local _, OXP = newGame({ level = 21 })
    local SS = OXP.SmartStart
    -- made-up section: 1 turns in A and accepts B (B needs A), A comes from
    -- a section you skipped
    local guide = { name = "21-22 Somewhere", group = "Test", minLevel = 21, maxLevel = 22, steps = {
        { { "accept", quest = 993001 } },
        { { "turnin", quest = 993001 } },
        { { "turnin", quest = 992000 }, { "accept", quest = 992001 } },
        { { "turnin", quest = 992001 } },
        { { "accept", quest = 993002 } },
    } }
    SS.api.IsTurnedIn = function() return false end
    SS.api.IsOnQuest = function() return false end
    local prereqs = { [992001] = { 992000 } }
    local start, skip, blocked = SS.PlanSteps(guide, prereqs, {}, nil, nil)
    t.eq(start, 1, "starts at the first open step")
    t.ok(skip[3] and skip[4], "the chain's steps are skipped")
    t.ok(blocked[992000] and blocked[992001], "and their quests listed")
    t.ok(not skip[1] and not skip[5], "the rest stays")
end

------------------------------------------------------------------------
print("-- inferred prerequisites from the guides")
do
    local _, OXP = newGame({ level = 21 })
    local guides = OXP.SmartStart.Candidates()
    local pre = OXP.SmartStart.InferPrerequisites(guides)
    local n = 0
    for _ in pairs(pre) do n = n + 1 end
    t.ok(n > 20, "more than 20 chain links from the Alliance guides: " .. n)
end

------------------------------------------------------------------------
print("-- gray quests are skipped, class quests kept")
do
    local _, OXP = newGame({ level = 30 })
    local SS = OXP.SmartStart
    SS.api.IsTurnedIn = function() return false end
    SS.api.IsOnQuest = function() return false end
    SS.api.QuestLevel = function(id) return id < 994100 and 18 or 29 end
    SS.api.GreenRange = function() return 8 end
    SS.api.NextInChain = function() return nil end
    SS.api.QuestRow = function() return nil end
    local guide = { name = "29-30 Somewhere", group = "Test", minLevel = 29, maxLevel = 30, steps = {
        { { "accept", quest = 994001 } },
        { class = true, { "accept", quest = 994002 } },
        { { "accept", quest = 994101 } },
    } }
    local _, _, _, gray = SS.PlanSteps(guide, {}, {}, nil, 30)
    t.ok(gray[1], "a gray quest's step is skipped")
    t.ok(not gray[2], "a gray class quest is kept")
    t.ok(not gray[3], "a green quest is kept")
end

------------------------------------------------------------------------
print("-- logging in far past your section moves you on")
do
    local game, OXP = newGame({ faction = "Alliance", race = "Human", class = "WARRIOR", level = 21 })
    game:Login()
    local first = OXP.Engine.GetGuide()
    t.ok(first and first.minLevel == 21, "starts in a section for level 21: " .. tostring(first and first.name))
    local saved = game:SavedVariables()
    local game2, OXP2 = newGame({ faction = "Alliance", race = "Human", class = "WARRIOR", level = 30 })
    OpenXPDB, OpenXPCharDB = saved.OpenXPDB, saved.OpenXPCharDB
    game2:Login()
    local g = OXP2.Engine.GetGuide()
    t.ok(g and g.minLevel and g.minLevel >= 28, "moved to a section for level 30: " .. tostring(g and g.name))
    t.eq(#game2.errors, 0, "no Lua errors: " .. table.concat(game2.errors, " | "))
end

------------------------------------------------------------------------
print("-- a new level 1 character starts at the top of their race's guide")
do
    for _, c in ipairs({ { "Alliance", "Human", "1-11 Elwynn Forest" }, { "Alliance", "NightElf", "1-12 Teldrassil" },
                         { "Alliance", "Skyborne", "1-14 Zephras Isle" }, { "Horde", "Scourge", "1-13 Tirisfal Glades" },
                         { "Horde", "Tauren", "1-12 Mulgore" }, { "Horde", "Skyborne", "1-14 Zephras Isle" } }) do
        local game, OXP = newGame({ faction = c[1], race = c[2], class = "WARRIOR", level = 1 })
        game:Login()
        local g = OXP.Engine.GetGuide()
        t.eq(g and g.name, c[3], c[1] .. " " .. c[2] .. " starts in")
        t.ok(g and g.faction == c[1], c[2] .. " gets their own faction's guide")
        t.eq(OXP.Engine.GetPosition(), 1, c[2] .. " at step 1")
    end
end

return t.fails