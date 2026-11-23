-- 2.0.2: class quest chains split by level (GitHub #90) moved steps in the
-- leveling guides; saved places follow their steps (Engine/StepRemap.lua,
-- Data/StepRemap.lua from tools/step_remap.py).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("remap")

print("-- moving a save: step, skips and statuses, once")
do
    local game = FakeWoW.New(ROOT, { faction = "Horde", race = "Tauren", class = "SHAMAN", level = 32 })
    local OXP = game:LoadAddon()
    game:Login()
    local R = OXP.StepRemapper
    local data = { version = 99, guides = { G = { 1, 2, 2, 3, 5, 6 } } } -- old 3 went elsewhere, new 4 added
    local char = { guides = { G = { step = 4, skipped = { [2] = true, [3] = true }, status = { [4] = "chain", [5] = "jumped" } },
                              Other = { step = 7, skipped = {} } } }
    t.eq(R.Apply(data, char), 1, "one guide moved")
    local s = char.guides.G
    t.eq(s.step, 3, "the saved step follows its step")
    t.ok(s.skipped[2] == true and s.skipped[3] == nil, "skips follow (a gone step folds into the next)")
    t.eq(s.status[3], "chain", "statuses follow")
    local d2 = { version = 99, guides = { H = { 1, 3, 4, 5 } } } -- a step added at 2
    local c2 = { guides = { H = { step = 3, skipped = {}, status = {} } } }
    R.Apply(d2, c2)
    t.eq(c2.guides.H.step, 4, "place moves past the new step")
    t.eq(c2.guides.H.status[2], "jumped", "a new step behind you is marked jumped (shows in /oxp catchup)")
    t.eq(s.status[5], "jumped", "and later ones")
    t.eq(char.guides.Other.step, 7, "guides that didn't move are left alone")
    t.eq(s.status[4], nil, "a new step ahead of you isn't marked")
    s.step = 6
    t.eq(R.Apply(data, char), 0, "only once")
    t.eq(s.step, 6, "not moved twice")
    char.guides.G.step = 6 -- finished (old end) -> new end
    char.stepRemap = nil
    R.Apply(data, char)
    t.eq(char.guides.G.step, 6, "a finished guide stays finished")
    t.eq(#game.errors, 0, "no Lua errors")
end

print("-- the shipped remap fits the shipped guides")
for _, who in ipairs({ { faction = "Horde", race = "Tauren", class = "SHAMAN" }, { faction = "Alliance", race = "Human", class = "PRIEST" } }) do
    local game = FakeWoW.New(ROOT, { faction = who.faction, race = who.race, class = who.class, level = 32 })
    local OXP = game:LoadAddon()
    game:Login()
    local n = 0
    for key, map in pairs(OXP.StepRemap.guides) do
        local g = OXP.Registry.Get(key)
        if g then
            n = n + 1
            local ok = map[#map] == #g.steps + 1
            for i = 2, #map do if map[i] < map[i - 1] or map[i] > #g.steps + 1 then ok = false end end
            t.ok(ok, key .. ": in order, inside the guide, end maps to end")
        end
    end
    t.ok(n > 0, who.faction .. ": remapped guides found (" .. n .. ")")
    t.eq(OXP.char.stepRemap, OXP.StepRemap.version, "a new character is marked done")
end

print("-- Storm, Earth, and Fire is no longer in Hillsbrad 29-33 (GitHub #90)")
do
    local game = FakeWoW.New(ROOT, { faction = "Horde", race = "Tauren", class = "SHAMAN", level = 32 })
    local OXP = game:LoadAddon()
    game:Login()
    local where = {}
    for _, g in ipairs(OXP.Registry.All()) do
        local lo, hi = g.name:match("^(%d+)%-(%d+)")
        for _, step in ipairs(g.steps) do
            for _, goal in ipairs(step) do
                if goal[1] == "xp" and hi and goal.level > tonumber(hi) + 2 then
                    where[#where + 1] = g.name .. " step needs " .. goal.level
                end
            end
        end
    end
    t.eq(#where, 0, "no step needs a level well above its guide: " .. table.concat(where, "; "))
end

return t.fails
