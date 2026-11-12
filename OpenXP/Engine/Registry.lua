-- Every guide the addon knows. Guide data files call OXP.AddGuides({...});
-- the registry checks each guide, gives it a key and answers questions like
-- "which guides can this character use" and "what comes after this one".
--
-- A guide's key is "<group>/<name>", plus " <only>" when the guide is
-- limited to some players, so the Alliance and Horde guides of one dungeon
-- don't collide: "OpenXP Dungeons/17-24 Wailing Caverns <Horde>".
local _, OXP = ...

local Registry = {}
OXP.Registry = Registry

local Filters, Goals = OXP.Filters, OXP.Goals

local guides = {}     -- in load order
local byKey = {}
local problems = {}   -- data errors found while loading, for tests and /openxp debug

local function problem(where, msg)
    problems[#problems + 1] = where .. ": " .. msg
end

local function keyOf(g)
    return g.group .. "/" .. g.name .. (g.only and (" <" .. g.only .. ">") or "")
end

local function checkFilter(where, expr)
    if not expr then return end
    for _, w in ipairs(Filters.UnknownWords(expr)) do
        problem(where, "unknown filter word '" .. w .. "'")
    end
end

local function check(g, where)
    if type(g.name) ~= "string" or type(g.group) ~= "string" then
        problem(where, "guide needs a name and a group")
        return false
    end
    if type(g.steps) ~= "table" or #g.steps == 0 then
        problem(where, "guide has no steps")
        return false
    end
    checkFilter(where, g.only)
    for s, step in ipairs(g.steps) do
        local here = where .. " step " .. s
        checkFilter(here, step.only)
        if step.completewith and step.completewith ~= "next" then
            problem(here, "completewith must be \"next\"")
        end
        local blocks = false
        for n, goal in ipairs(step) do
            local kind = goal[1]
            if not Goals.IsKnown(kind) then
                problem(here, "unknown goal kind '" .. tostring(kind) .. "' (goal " .. n .. ")")
            else
                for _, f in ipairs(Goals.Fields(kind)) do
                    if goal[f] == nil then
                        problem(here, kind .. " goal " .. n .. " has no " .. f)
                    end
                end
                if Goals.Blocks(kind) then blocks = true end
            end
            checkFilter(here, goal.only)
        end
        if not blocks then
            problem(here, "step has nothing to finish it (only hints)")
        end
    end
    return true
end

--- Level range from a name like "21-22 Ashenvale".
local function levelsOf(name)
    local lo, hi = name:match("^(%d+)%-(%d+)")
    return tonumber(lo), tonumber(hi)
end

--- Called by every guide data file.
--- data = { file = "Alliance-21-30", faction = "Alliance", guide, guide, ... }
function OXP.AddGuides(data)
    for i, g in ipairs(data) do
        local where = (data.file or "?") .. " guide " .. i .. " (" .. tostring(g.name) .. ")"
        if check(g, where) then
            g.file = data.file
            g.faction = g.faction or data.faction
            g.key = keyOf(g)
            g.minLevel, g.maxLevel = levelsOf(g.name)
            if byKey[g.key] then
                problem(where, "another guide already has the key " .. g.key)
            else
                byKey[g.key] = g
                guides[#guides + 1] = g
            end
        end
    end
end

function Registry.Get(key)
    return byKey[key]
end

--- Every guide, in load order.
function Registry.All()
    return guides
end

--- Can this player (default: the current one) use the guide?
function Registry.IsAvailable(g, player)
    return Filters.Matches(g.only, player)
end

--- Guides this player can use, optionally only one group, in load order.
function Registry.ForPlayer(player, group)
    local out = {}
    for _, g in ipairs(guides) do
        if (not group or g.group == group) and Registry.IsAvailable(g, player) then
            out[#out + 1] = g
        end
    end
    return out
end

--- Find a guide by name for this player: the same group first, then any.
function Registry.Find(name, group, player)
    local fallback
    for _, g in ipairs(guides) do
        if g.name == name and Registry.IsAvailable(g, player) then
            if g.group == group then return g end
            fallback = fallback or g
        end
    end
    return fallback
end

--- The guide that follows `g` (its #next), for this player.
function Registry.Next(g, player)
    if not g.next then return nil end
    return Registry.Find(g.next, g.group, player)
end

--- Group names in load order, each once, with their guides for this player:
--- { { name = group, guides = {...} }, ... } (empty groups left out).
function Registry.Groups(player)
    local out, index = {}, {}
    for _, g in ipairs(Registry.ForPlayer(player)) do
        local entry = index[g.group]
        if not entry then
            entry = { name = g.group, guides = {} }
            index[g.group] = entry
            out[#out + 1] = entry
        end
        entry.guides[#entry.guides + 1] = g
    end
    return out
end

--- Data errors found while loading guides (empty when all is well).
function Registry.Problems()
    return problems
end
