-- `only` filters on guides, steps and goals.
--
--   "Warlock"                       one word: faction, race, class or level
--   "Human Paladin/Dwarf Paladin"   "/" separates choices (OR); words inside
--                                   a choice must all match (AND)
--   "!Warrior", "!Alliance"         "!" matches when the word does NOT
--   "Druid 20"                      a number means "level 20 or higher"
--
-- Words are case-insensitive. "Undead" means the Scourge race, as the game
-- calls it internally.
local _, OXP = ...

local Filters = {}
OXP.Filters = Filters

local FACTIONS = { alliance = "Alliance", horde = "Horde", neutral = "Neutral" }
local RACES = {
    human = "Human", dwarf = "Dwarf", nightelf = "NightElf", gnome = "Gnome",
    orc = "Orc", undead = "Scourge", scourge = "Scourge", tauren = "Tauren",
    troll = "Troll", skyborne = "Skyborne",
}
local CLASSES = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE",
    priest = "PRIEST", shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK",
    druid = "DRUID",
}

local function wordMatches(word, player)
    local level = tonumber(word)
    if level then
        return (player.level or 1) >= level
    end
    local key = word:lower()
    if FACTIONS[key] then
        -- Before a Neutral race picks a side, faction filters don't hide anything.
        return player.faction == FACTIONS[key] or player.faction == "Neutral"
    elseif RACES[key] then
        return player.race == RACES[key]
    elseif CLASSES[key] then
        return player.class == CLASSES[key]
    end
    return false
end

--- Parse a filter into { { {word=, negate=}, ... }, ... } (choices of words).
local function parse(expr)
    local choices = {}
    for choice in expr:gmatch("[^/]+") do
        local words = {}
        for raw in choice:gmatch("%S+") do
            local negate = raw:sub(1, 1) == "!"
            words[#words + 1] = { word = negate and raw:sub(2) or raw, negate = negate }
        end
        if #words > 0 then choices[#choices + 1] = words end
    end
    return choices
end

local parsed = {}

--- True when `player` (default OXP.Player) passes the filter. nil or "" passes.
function Filters.Matches(expr, player)
    if not expr or expr == "" then return true end
    player = player or OXP.Player
    local choices = parsed[expr]
    if not choices then
        choices = parse(expr)
        parsed[expr] = choices
    end
    for i = 1, #choices do
        local ok = true
        for _, w in ipairs(choices[i]) do
            if wordMatches(w.word, player) == w.negate then
                ok = false
                break
            end
        end
        if ok then return true end
    end
    return false
end

--- Words in `expr` that the filter doesn't know (typos in guide data).
function Filters.UnknownWords(expr)
    local bad = {}
    for _, choice in ipairs(parse(expr or "")) do
        for _, w in ipairs(choice) do
            local key = w.word:lower()
            if not (tonumber(w.word) or FACTIONS[key] or RACES[key] or CLASSES[key]) then
                bad[#bad + 1] = w.word
            end
        end
    end
    return bad
end

Filters.RACES, Filters.CLASSES = RACES, CLASSES
