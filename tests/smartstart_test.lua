-- Unit tests for SmartStart.lua, run outside the game.
-- Run with: python3 tests/run_tests.py
--
-- Uses the real Forever Alliance guide files, parsed with a tiny stand-in
-- for the engine's parser (steps plus .accept/.turnin/.complete lines).

local ROOT = ...

local function readfile(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

-- Minimal guide parser. Applies "<< Tag" filters for a Human Warrior.
local playerTags = {Alliance = true, Human = true, Warrior = true}
local function applies(tagText)
    for tag in tagText:gmatch("%S+") do
        local any = false
        for alt in tag:gmatch("[^/]+") do
            local neg = alt:sub(1, 1) == "!"
            local name = neg and alt:sub(2) or alt
            local has = playerTags[name] or false
            if neg then has = not has end
            if has then any = true end
        end
        if not any then return false end
    end
    return true
end

local function parseGuides(text)
    local guides = {}
    for body in text:gmatch("RegisterGuide%(%[%[(.-)%]%]") do
        local guide = {steps = {}}
        local header = body:match("^(.-)\nstep") or body
        local headerTag = header:match("\n<<%s*([^\n]+)")
        local ok = not headerTag or applies(headerTag)
        guide.name = header:match("#name%s+([^\n]+)")
        guide.defaultfor = header:match("#defaultfor%s+([^\n]+)")
        local step
        for line in body:gmatch("[^\n]+") do
            local stepTag = line:match("^step%s*<<%s*(.+)$")
            if line:match("^step") then
                if stepTag and not applies(stepTag) then
                    step = nil
                else
                    step = {elements = {}, tagText = stepTag}
                    table.insert(guide.steps, step)
                end
            elseif step then
                local trimmed = line:gsub("^%s+", "")
                local lineTag = trimmed:match("<<%s*(.+)$")
                if not lineTag or applies(lineTag) then
                    local tag, id = trimmed:match("^%.(%a+)%s+(%-?%d+)")
                    if tag == "accept" or tag == "turnin" or tag == "complete" then
                        table.insert(step.elements, {tag = tag, questId = math.abs(tonumber(id)),
                            skipIfMissing = tag == "turnin" and tonumber(id) < 0 or nil})
                    elseif trimmed:match("^%.goto") then
                        table.insert(step.elements, {tag = "goto"})
                    end
                end
            end
        end
        if ok and guide.name then table.insert(guides, guide) end
    end
    return guides
end

local guides = {}
for _, file in ipairs({"forever/Alliance-1-13_Human.lua", "forever/Alliance-11-20.lua",
                       "openxp/Alliance-21-30.lua", "openxp/Alliance-30-40.lua",
                       "openxp/Alliance-40-50.lua", "openxp/Alliance-50-60.lua"}) do
    for _, g in ipairs(parseGuides(readfile(ROOT .. "/Guides/" .. file))) do
        table.insert(guides, g)
    end
end

-- Load SmartStart with a fake addon table.
local addon = {}
local chunk = assert(loadstring(readfile(ROOT .. "/SmartStart.lua"), "SmartStart.lua"))
chunk("OpenXP", addon)
local SS = addon.smartStart

local state = {turnedIn = {}, onQuest = {}, complete = {}, level = 1, zone = ""}
SS.api = {
    IsTurnedIn = function(id) return state.turnedIn[id] == true end,
    IsOnQuest = function(id) return state.onQuest[id] == true end,
    IsComplete = function(id) return state.complete[id] == true end,
    PlayerLevel = function() return state.level end,
    ZoneName = function() return state.zone end,
    GuideName = function(g) return g.name end,
    Applies = function(tags) return tags ~= "None" and applies(tags) end,
    QuestieDB = function() return nil end,
}

local function byName(name)
    for _, g in ipairs(guides) do if g.name == name then return g end end
    error("no guide " .. name)
end

local function finishGuide(g)
    for _, step in ipairs(g.steps) do
        for _, e in ipairs(step.elements) do
            if e.questId then state.turnedIn[e.questId] = true end
        end
    end
end

local failures, passes = 0, 0
local function check(cond, msg)
    if cond then
        passes = passes + 1
    else
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

local function reset()
    state.turnedIn, state.onQuest, state.complete = {}, {}, {}
end

-- Sanity: guides parsed
check(#guides >= 6, "parsed at least 6 guide sections, got " .. #guides)
local prereqs = SS.InferPrerequisites(guides)
local nPre = 0
for _ in pairs(prereqs) do nPre = nPre + 1 end
check(nPre > 20, "inferred more than 20 chain links, got " .. nPre)
print(string.format("parsed %d sections, inferred %d chain links", #guides, nPre))

-- 1. Fresh level 1 character starts at step 1 of Northshire.
reset(); state.level = 1
local g = SS.PickGuide(guides, 1, "")
check(g and g.name == "1-6 Northshire", "level 1 picks Northshire, got " .. tostring(g and g.name))
local start = SS.PlanSteps(g, prereqs)
check(start == 1, "fresh character starts at step 1, got " .. start)

-- 2. Matt's case: did everything up to Westfall, skipped 14-16 Darkshore,
--    now level 16 in Darkshore -> should land in 16-19 Darkshore and skip
--    chains that start in 14-16 Darkshore.
reset(); state.level = 16; state.zone = "Darkshore"
for _, name in ipairs({"1-6 Northshire", "6-11 Elwynn Forest", "11-13 Loch Modan", "13-15 Westfall"}) do
    finishGuide(byName(name))
end
g = SS.PickGuide(guides, 16, "Darkshore")
check(g and g.name == "16-19 Darkshore", "skipped 14-16 picks 16-19 Darkshore, got " .. tostring(g and g.name))
local start2, skip2, blocked2 = SS.PlanSteps(g, prereqs)
local nSkip, nBlocked = 0, 0
for _ in pairs(skip2) do nSkip = nSkip + 1 end
for _ in pairs(blocked2) do nBlocked = nBlocked + 1 end
print(string.format("16-19 Darkshore after skipping 14-16: start step %d, %d steps skipped, %d quests blocked", start2, nSkip, nBlocked))
check(nBlocked > 0, "some 16-19 Darkshore quests are blocked by skipped 14-16 chains")
check(nSkip < #g.steps / 2, "most of 16-19 Darkshore is still playable")

-- 3. Same player who DID 14-16 Darkshore: nothing blocked.
finishGuide(byName("14-16 Darkshore"))
local _, skip3, blocked3 = SS.PlanSteps(g, prereqs)
local n3 = 0
for _ in pairs(blocked3) do n3 = n3 + 1 end
check(n3 == 0, "no blocked quests when 14-16 Darkshore was done, got " .. n3)

-- 4. Resume mid-section: half of Elwynn done, quest in log -> resumes Elwynn.
reset(); state.level = 8; state.zone = "Elwynn Forest"
finishGuide(byName("1-6 Northshire"))
local elwynn = byName("6-11 Elwynn Forest")
local steps = SS.QuestSteps(elwynn)
local half = math.floor(#elwynn.steps / 2)
local lastAccepted
for i = 1, half do
    for _, q in ipairs(steps[i] or {}) do
        if q.tag == "turnin" then state.turnedIn[q.id] = true; state.onQuest[q.id] = nil
        elseif q.tag == "accept" and not state.turnedIn[q.id] then state.onQuest[q.id] = true; lastAccepted = q.id end
    end
end
g = SS.PickGuide(guides, 8, "Elwynn Forest")
check(g and g.name == "6-11 Elwynn Forest", "mid-Elwynn resumes Elwynn, got " .. tostring(g and g.name))
local start4 = SS.PlanSteps(g, prereqs)
check(start4 > 1 and start4 <= half + 1, "mid-Elwynn start step is past the done part, got " .. start4 .. " (half " .. half .. ")")

-- 5. Overleveled: level 20 with nothing done in low sections doesn't pick 1-6.
reset(); state.level = 20; state.zone = ""
g = SS.PickGuide(guides, 20, "")
local lo = g and tonumber(g.name:match("^(%d+)"))
check(g and lo and lo >= 16, "level 20 picks a 16+ section, got " .. tostring(g and g.name))

-- 6. OpenXP 21-60: the section names come from the route builder's level
-- simulation, so read them from the files. Every section parses, the 1-20
-- guides chain into the first one, and a player in a zone at a level one of
-- its sections covers lands in that zone.
local names = {}
for _, gg in ipairs(guides) do names[gg.name] = true end
local zoneSections = {}
for _, file in ipairs({"Alliance-21-30.lua", "Alliance-30-40.lua", "Alliance-40-50.lua", "Alliance-50-60.lua"}) do
    local text = readfile(ROOT .. "/Guides/openxp/" .. file)
    for n in text:gmatch("#name ([^\n]+)") do
        check(names[n], file .. " section parsed: " .. n)
        local lo, hi, zone = n:match("^(%d+)%-(%d+) (.-)$")
        zone = zone and zone:gsub(" %(part %d+%)$", "")
        if zone and not zoneSections[zone] then
            zoneSections[zone] = {lo = tonumber(lo), hi = tonumber(hi), name = n}
        end
    end
end
for nxt in readfile(ROOT .. "/Guides/forever/Alliance-11-20.lua"):gmatch("#next RestedXP Forever Guide %(A%)\\([^\n]+)") do
    check(names[nxt], "the 1-20 guide chains into a 21-60 section that exists: " .. nxt)
end
for _, zone in ipairs({"Wetlands", "Western Plaguelands"}) do
    local z = zoneSections[zone]
    check(z, "the route has a " .. zone .. " section")
    if z then
        reset(); state.level = z.lo; state.zone = zone
        g = SS.PickGuide(guides, z.lo, zone)
        check(g and g.name:find(zone, 1, true), "level " .. z.lo .. " in " .. zone .. " picks a " .. zone .. " section, got " .. tostring(g and g.name))
    end
end

-- 7. Every quest an OpenXP file completes or turns in with a plain id is
-- accepted earlier in that file (carried quests use skip-if-missing ids),
-- and every #next names a section that exists.
for _, file in ipairs({"Alliance-21-30.lua", "Alliance-30-40.lua", "Alliance-40-50.lua", "Alliance-50-60.lua"}) do
    local text = readfile(ROOT .. "/Guides/openxp/" .. file)
    for nxt in text:gmatch("#next ([^\n]+)") do
        check(names[nxt:gsub("^.*\\", "")], file .. " #next points at a missing section: " .. nxt)
    end
    local accepted, bad = {}, {}
    for line in text:gmatch("[^\n]+") do
        local tag, id = line:match("^%s+%.(%a+)%s+(%d+)")
        if tag == "accept" then accepted[id] = true
        elseif (tag == "turnin" or tag == "complete") and not accepted[id] then table.insert(bad, id) end
    end
    check(#bad == 0, file .. " quests used before accepted: " .. table.concat(bad, ","))
end

-- 8. Same checks for the Horde 22-60 files, and the Barrens guide chains
-- into the first one.
local hnames = {}
local hfiles = {"Horde-22-30.lua", "Horde-30-40.lua", "Horde-40-50.lua", "Horde-50-60.lua"}
for _, file in ipairs(hfiles) do
    for n in readfile(ROOT .. "/Guides/openxp/" .. file):gmatch("#name ([^\n]+)") do hnames[n] = true end
end
local barrensNext
for n in readfile(ROOT .. "/Guides/forever/Horde-12-22_Barrens.lua"):gmatch("#next ([^\n]+)") do barrensNext = n end
check(hnames[barrensNext], "the Barrens guide chains into a 22-60 section that exists: " .. tostring(barrensNext))
for _, file in ipairs(hfiles) do
    local text = readfile(ROOT .. "/Guides/openxp/" .. file)
    for nxt in text:gmatch("#next ([^\n]+)") do
        check(hnames[nxt], file .. " #next points at a missing section: " .. nxt)
    end
    local accepted, bad = {}, {}
    for line in text:gmatch("[^\n]+") do
        local tag, id = line:match("^%s+%.(%a+)%s+(%d+)")
        if tag == "accept" then accepted[id] = true
        elseif (tag == "turnin" or tag == "complete") and not accepted[id] then table.insert(bad, id) end
    end
    check(#bad == 0, file .. " quests used before accepted: " .. table.concat(bad, ","))
end

-- Fresh install: no guide loaded, guides still loading at first, then the
-- login check loads the starter guide and switches the window on, with no
-- clicks. Also the minimap click before guides are ready.
do
    reset(); state.level = 1
    local timers = {}
    _G.C_Timer = {After = function(_, fn) table.insert(timers, fn) end}
    local ready = false
    local toggled = 0
    addon.defaultGroup = "RestedXP Forever Guide (A)"
    addon.GetActiveGuidesInGroup = function() return ready and guides or {} end
    addon.FetchGuide = function(_, g) return g end
    addon.LoadGuide = function(_, g) addon.currentGuide = g end
    addon.SetStep = function(n) addon.step = n end
    addon.settings = {profile = {showEnabled = false},
        ToggleActive = function()
            toggled = toggled + 1
            addon.settings.profile.showEnabled = not addon.settings.profile.showEnabled
        end}
    _G.OXPCData = {stepSkip = {}}
    addon.currentGuide = {empty = true, steps = {{}}}
    _G.print = _G.print
    SS.cachedPrereqs = nil

    check(not SS.HasGuide(), "fresh install: no guide yet")
    SS.OnLogin()
    check(not SS.HasGuide() and #timers == 1, "guides not ready: tries again later")
    ready = true
    table.remove(timers, 1)()
    check(SS.HasGuide() and addon.currentGuide.name == "1-6 Northshire",
        "fresh level 1 Human gets Northshire on login, got " .. tostring(addon.currentGuide.name))
    check(addon.settings.profile.showEnabled and toggled == 1, "guide window switched on")

    -- smartStartOnLogin off must not stop a fresh character getting a guide
    addon.currentGuide = {empty = true}
    addon.settings.profile.smartStartOnLogin = false
    SS.OnLogin()
    check(SS.HasGuide(), "fresh install gets a guide even with smart start on login off")
    addon.settings.profile.smartStartOnLogin = nil

    -- minimap click before the guides are ready, then once they are
    addon.currentGuide = nil
    ready = false; timers = {}
    check(SS.EnsureGuide() == false and #timers == 1, "click while loading waits for guides")
    ready = true
    timers[1]()
    check(SS.HasGuide(), "guide loads once guides are ready")

    -- a guide already loaded is left alone at level 1
    local before = addon.currentGuide
    SS.OnLogin()
    check(addon.currentGuide == before, "existing guide kept")
    _G.C_Timer = nil
end

-- Player comment (2026-11-11): installed at 16 and got sent to Auberdine,
-- then to quests they didn't have. A level 16 still doing Westfall (its
-- quests in the log) stays in Westfall, even one level past its range.
do
    reset(); state.level = 16; state.zone = "Westfall"
    for _, name in ipairs({"1-6 Northshire", "6-11 Elwynn Forest", "11-13 Loch Modan"}) do
        finishGuide(byName(name))
    end
    local west = byName("13-15 Westfall")
    local ws = SS.QuestSteps(west)
    local n = 0
    for i = 1, #west.steps do
        for _, q in ipairs(ws[i] or {}) do
            if q.tag == "accept" and n < 4 and not state.turnedIn[q.id] then state.onQuest[q.id] = true; n = n + 1 end
        end
    end
    local pick = SS.PickGuide(guides, 16, "Westfall")
    check(pick and pick.name == "13-15 Westfall", "level 16 with Westfall quests stays in Westfall, got " .. tostring(pick and pick.name))
    -- with nothing from Westfall in the log, 16 still goes on to Darkshore
    state.onQuest = {}
    pick = SS.PickGuide(guides, 16, "")
    check(pick and pick.name:find("Darkshore"), "level 16 with an empty log goes to Darkshore, got " .. tostring(pick and pick.name))
    -- in Darkshore, turn-ins for quests you never picked up are skipped,
    -- not the place you start
    local dark = byName("16-19 Darkshore")
    local start, skip = SS.PlanSteps(dark, prereqs)
    local ds = SS.QuestSteps(dark)
    for _, q in ipairs(ds[start] or {}) do
        if q.tag ~= "accept" then
            check(state.onQuest[q.id] or state.turnedIn[q.id] or SS.GuideAccepts(ds, q.id),
                "start step doesn't turn in a quest you don't have (" .. q.id .. ")")
        end
    end
end

-- Player comment (2026-11-11): progress reset on every login. Steps you
-- skipped by hand stay skipped, Smart start never moves you back in the
-- section you're in, and logging in a bit above a section's level only
-- prints a hint instead of moving you.
do
    reset(); state.level = 8; state.zone = "Elwynn Forest"
    finishGuide(byName("1-6 Northshire"))
    local elwynn = byName("6-11 Elwynn Forest")
    local es = SS.QuestSteps(elwynn)
    local first
    for i = 1, #elwynn.steps do if es[i] then first = i break end end
    local skipped = {[first] = true}
    local start = SS.PlanSteps(elwynn, prereqs, skipped)
    check(start ~= first, "a step skipped by hand isn't where you start, got " .. start)
    local start2 = SS.PlanSteps(elwynn, prereqs, nil, 40)
    check(start2 >= 40, "never moved back before your current step, got " .. start2)

    local printed = {}
    local oldPrint = _G.print
    _G.print = function(m) table.insert(printed, m) end
    local ran = false
    local realRun = SS.Run
    SS.Run = function() ran = true end
    addon.currentGuide = elwynn
    addon.settings = {profile = {}}
    state.level = 13 -- 2 above 6-11
    SS.hinted = nil
    SS.OnLogin()
    check(not ran, "2 levels above the section: login doesn't move you")
    check(#printed == 1 and printed[1]:find("/oxp where"), "and says how to jump ahead")
    state.level = 20 -- far past it, nothing from it in the log
    SS.OnLogin()
    check(ran, "far past the section with none of its quests: login moves you")
    SS.Run = realRun
    _G.print = oldPrint
end

-- The guide group names Smart start looks in must match the guides' own
-- #group lines exactly. They were run through the translation table, so a
-- German/Spanish/Chinese client looked in a group that doesn't exist.
do
    local db = readfile(ROOT .. "/DB/forever/db.lua")
    for fac in ("AH"):gmatch(".") do
        local want = "RestedXP Forever Guide (" .. fac .. ")"
        local found = false
        for line in db:gmatch("addon%.defaultGroup%s*=%s*([^\n]+)") do
            if line == '"' .. want .. '"' then found = true end
        end
        check(found, "default guide group for " .. fac .. " is the untranslated \"" .. want .. "\"")
    end
    check(not db:find("defaultGroup%s*=%s*L"), "default guide group is never translated")
end

-- Placing a player who skipped low quests (CurseForge, 2026-11-11: "had to
-- click through close to a hundred steps").
do
    -- the section with the most quest steps
    local g, steps, order
    for _, cand in ipairs(guides) do
        local st = SS.QuestSteps(cand)
        local o = {}
        for i = 1, #cand.steps do if st[i] then o[#o + 1] = i end end
        if not order or #o > #order then g, steps, order = cand, st, o end
    end
    check(#order > 20, "found a long section to test placement")
    local function doStep(i)
        for _, q in ipairs(steps[i]) do state.turnedIn[q.id] = true end
    end
    -- did a run of steps in the middle, skipped the first quests
    reset()
    local from, to = math.floor(#order / 2), math.floor(#order / 2) + 5
    for k = from, to do doStep(order[k]) end
    local start = SS.PlanSteps(g, prereqs)
    check(start > order[to], "starts after your furthest progress, got " .. start .. " want > " .. order[to])
    -- the open steps before it are behind you, not where you start
    check(start ~= 1, "doesn't start back at the first skipped quest")

    -- one quest done out of order far ahead doesn't jump you there
    reset()
    doStep(order[#order - 2])
    local start2 = SS.PlanSteps(g, prereqs)
    check(start2 < order[#order - 2], "a single out-of-order quest doesn't move you ahead, got " .. start2)

    -- gray quests: with Questie levels, quests far below you are skipped
    reset()
    local levels = {}
    local oldLevel, oldNext, oldRange = SS.api.QuestLevel, SS.api.NextInChain, SS.api.GreenRange
    SS.api.GreenRange = function() return 6 end
    SS.api.NextInChain = function() return nil end
    SS.api.QuestLevel = function(id) return levels[id] end
    -- every quest in the first three quest steps is level 10 (gray at 22),
    -- the rest level 22
    local early = {}
    for k = 1, #order do
        for _, q in ipairs(steps[order[k]]) do
            if k <= 3 then early[q.id] = true end
        end
    end
    for k = 1, #order do
        for _, q in ipairs(steps[order[k]]) do
            levels[q.id] = early[q.id] and 10 or 22
        end
    end
    local _, _, _, grayAt = SS.PlanSteps(g, prereqs, nil, nil, 22)
    local nGray = 0
    for _ in pairs(grayAt) do nGray = nGray + 1 end
    -- a quest gray at 22 whose chain goes on into a green quest is kept
    local keptForChain = false
    for id in pairs(early) do
        for b, pre in pairs(prereqs) do
            for _, a in ipairs(pre) do
                if a == id and not early[b] then keptForChain = true end
            end
        end
    end
    check(nGray > 0 or keptForChain, "gray quests at the start are skipped")
    local _, _, _, none = SS.PlanSteps(g, prereqs, nil, nil, 12)
    check(next(none) == nil, "nothing is gray when you're close to the quests' level")
    local _, _, _, off = SS.PlanSteps(g, prereqs)
    check(next(off) == nil, "no gray skipping without a level")

    -- a chain whose last quest is green keeps its gray start
    local a, b = 900001, 900002
    local fake = {name = "fake", steps = {
        {elements = {{tag = "accept", questId = a}}},
        {elements = {{tag = "turnin", questId = a}, {tag = "accept", questId = b}}},
        {elements = {{tag = "turnin", questId = b}}},
        {elements = {{tag = "accept", questId = 900003}}, tagText = "Warrior"},
    }}
    levels[a], levels[b], levels[900003] = 5, 20, 5
    local fp = SS.InferPrerequisites({fake})
    local s3, _, _, g3 = SS.PlanSteps(fake, fp, nil, nil, 22)
    check(not g3[1] and s3 == 1, "gray quest leading to a green one is kept")
    check(not g3[4], "class quests are never skipped for being gray")
    levels[b] = 5
    local _, _, _, g4 = SS.PlanSteps(fake, fp, nil, nil, 22)
    check(g4[1] and g4[2] and g4[3], "an all-gray chain is skipped whole")
    SS.api.QuestLevel, SS.api.NextInChain, SS.api.GreenRange = oldLevel, oldNext, oldRange
    reset()
end

print(string.format("%d passed, %d failed", passes, failures))
return failures
