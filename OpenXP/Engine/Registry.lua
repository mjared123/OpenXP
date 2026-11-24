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

-- Another race's starting zone (GitHub #106: a Night Elf who wants the
-- Human start). A guide only for one race of your own faction ("Human",
-- "Alliance Skyborne") can be picked by the faction's other races too.
local RACE_SIDE = {
    human = "Alliance", dwarf = "Alliance", gnome = "Alliance", nightelf = "Alliance",
    orc = "Horde", scourge = "Horde", undead = "Horde", tauren = "Horde", troll = "Horde",
    skyborne = true, -- either side: the guide names it ("Horde Skyborne")
}

--- The race (as the guide writes it: "Human", "NightElf") when `g` is
--- another race's guide of the player's faction, else nil.
function Registry.OtherStart(g, player)
    player = player or OXP.Player
    local only = g and g.only
    if type(only) ~= "string" or only:find("[/!%d]") or Registry.IsAvailable(g, player) then return nil end
    local side, race
    for w in only:gmatch("%S+") do
        local k = w:lower()
        if k == "alliance" or k == "horde" then
            side = k == "alliance" and "Alliance" or "Horde"
        elseif RACE_SIDE[k] then
            race = w
            if RACE_SIDE[k] ~= true then side = side or RACE_SIDE[k] end
        else
            return nil
        end
    end
    if not race or side ~= player.faction then return nil end
    if g.faction and g.faction ~= player.faction then return nil end
    return race
end

--- Guides this player can use, optionally only one group, in load order.
--- With `others`, other races' starting zones too (Registry.OtherStart).
function Registry.ForPlayer(player, group, others)
    local out = {}
    for _, g in ipairs(guides) do
        if (not group or g.group == group)
            and (Registry.IsAvailable(g, player) or (others and Registry.OtherStart(g, player))) then
            out[#out + 1] = g
        end
    end
    return out
end

--- Find a guide by name for this player: the same group first, then any.
--- Another race's guide only when there's no other (Teldrassil's next,
--- Darkshore 12-14, is Night Elf only).
function Registry.Find(name, group, player)
    local fallback, other
    for _, g in ipairs(guides) do
        if g.name == name then
            if Registry.IsAvailable(g, player) then
                if g.group == group then return g end
                fallback = fallback or g
            elseif not other and g.group == group and Registry.OtherStart(g, player) then
                other = g
            end
        end
    end
    return fallback or other
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
