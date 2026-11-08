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
                    step = {elements = {}}
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
for _, file in ipairs({"Alliance-1-13_Human.lua", "Alliance-11-20.lua"}) do
    for _, g in ipairs(parseGuides(readfile(ROOT .. "/Guides/forever/" .. file))) do
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

print(string.format("%d passed, %d failed", passes, failures))
return failures
