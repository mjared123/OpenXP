-- OpenXP's own quest facts (Data/QuestDB.lua, built from forever-db by
-- tools/build_questdb.py), handed out in the same shape as Questie's rows
-- so Engine/QuestDB.lua can use either. Rows are built when first asked for
-- and kept.
local _, OXP = ...

local FDB = {}
OXP.ForeverDB = FDB

local made = { Quest = {}, NPC = {}, Object = {}, Item = {} }

local function Data() return OXP.questData end

function FDB.Available()
    return Data() ~= nil
end

local function Spawns(packed)
    if not packed then return nil end
    local out = {}
    for map, s in pairs(packed) do
        local pts = {}
        for x, y in s:gmatch("([%d%.]+),([%d%.]+)") do pts[#pts + 1] = { tonumber(x), tonumber(y) } end
        out[map] = pts
    end
    return out
end

local function Refs(list)
    local npcs, objs, items = {}, {}, {}
    for _, r in ipairs(list or {}) do
        if r[1] == "n" then npcs[#npcs + 1] = r[2]
        elseif r[1] == "o" then objs[#objs + 1] = r[2]
        else items[#items + 1] = r[2] end
    end
    return { npcs, objs, items }
end

local build = {}

function build.Quest(id)
    local r = Data().q[id]
    if not r then return nil end
    local creatures, objects, items, list = {}, {}, {}, {}
    for _, o in ipairs(r.o or {}) do
        local kind, target, count = o[1], o[2], o[3]
        list[#list + 1] = { kind = kind, target = target, count = count }
        if kind == "kill" or kind == "talk" then
            creatures[#creatures + 1] = { target, count }
        elseif kind == "object" then
            objects[#objects + 1] = { target, count }
        elseif kind == "item" then
            items[#items + 1] = { target, count }
        end
    end
    return {
        name = r[1], level = r[2], questLevel = r[2], requiredLevel = r[3], side = r[4],
        requiredRaceIds = r.races, requiredClassIds = r.classes,
        startedBy = Refs(r.s), finishedBy = Refs(r.f),
        objectives = { creatures, objects, items }, objectiveList = list,
        preQuestSingle = r.any, preQuestGroup = r.all, breadcrumbForQuestId = r.bc,
        fdb = true,
    }
end

local function Place(tbl, id)
    local r = Data()[tbl][id]
    if not r then return nil end
    return { name = r[1], spawns = Spawns(r.spawns), spawnsByMap = true, fdb = true }
end

function build.NPC(id) return Place("npc", id) end
function build.Object(id) return Place("obj", id) end

function build.Item(id)
    local r = Data().item[id]
    if not r then return nil end
    return { name = r[1], npcDrops = r.n, objectDrops = r.o, fdb = true }
end

--- A row like Questie's for kind ("Quest", "NPC", "Object", "Item") and id, or nil.
function FDB.Get(kind, id)
    if not (Data() and id and build[kind]) then return nil end
    local cache = made[kind]
    local hit = cache[id]
    if hit ~= nil then return hit or nil end
    local row = build[kind](id)
    cache[id] = row or false
    return row
end
