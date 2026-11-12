-- Quest facts (who gives a quest, what comes before it, where its mobs are)
-- read from Questie while the game runs, when it is installed. OpenXP ships
-- no quest database of its own and copies nothing of Questie's: every answer
-- is asked for at run time and only kept in memory.
--
-- On top of that: quest chains and what is wrong with a step (a quest you
-- don't have, a chain you missed, a quest something else locked out).
local _, OXP = ...

local DB = {}
OXP.QuestDB = DB

local Quests = OXP.Quests

-- Tests (and anyone without Questie) can fill these instead:
--   DB.data.prereqs[id] = { any = {..}, all = {..}, excl = {..} }
--   DB.data.info[id] = { n = name, l = level, r = required level, s = start spot, f = finish spot, o = {spots} }
--   DB.data.chains[id] = { earlier quest ids in order }
--   DB.data.breadcrumbs[id] = quest it leads to
-- A spot is { name, uiMapId, x, y }.
DB.data = {}

------------------------------------------------------------------------
-- Questie
------------------------------------------------------------------------

local questie, zoneDB
local function Questie()
    if not questie then
        local loader = _G.QuestieLoader
        if loader and loader.ImportModule then
            local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
            if ok and db and type(db.GetQuest) == "function" then questie = db end
            local okZ, z = pcall(loader.ImportModule, loader, "ZoneDB")
            if okZ then zoneDB = z end
        end
    end
    return questie
end
DB.Questie = Questie

function DB.Available()
    return OXP.ForeverDB.Available() or Questie() ~= nil or DB.data.prereqs ~= nil
end

-- Questie builds a new table on every lookup and the card, map and tooltips
-- ask for the same few things many times a second, so keep the answers.
local cache, cached = {}, 0
local CACHE_MAX = 3000

--- A row for kind ("Quest", "NPC", "Object", "Item") and id, or nil: OpenXP's
--- own data (Engine/ForeverDB.lua) first, then Questie's when it's installed.
function DB.Get(kind, id)
    local own = OXP.ForeverDB.Get(kind, id)
    if own then return own end
    local db = Questie()
    if not (db and id) then return nil end
    local key = kind .. ":" .. tostring(id)
    local hit = cache[key]
    if hit then return hit end
    local fn = db["Get" .. kind]
    if type(fn) ~= "function" then return nil end
    if cached >= CACHE_MAX then cache, cached = {}, 0 end
    -- Questie defines some of these as db.GetX(id) and others as db:GetX(id)
    local ok, obj = pcall(fn, id)
    if not (ok and type(obj) == "table") then ok, obj = pcall(fn, db, id) end
    if ok and type(obj) == "table" then
        cache[key] = obj
        cached = cached + 1
        return obj
    end
end

local function UiMap(areaId)
    if zoneDB and zoneDB.GetUiMapIdByAreaId then
        local ok, m = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
        if ok and m and m > 0 then return m end
    end
end
DB.UiMap = UiMap

-- The densest spawn area of an NPC or object, and the spawn nearest its middle.
local function SpotOf(obj, preferArea)
    local spawns = obj and obj.spawns
    if type(spawns) ~= "table" then return nil end
    local bestArea, bestPts, bestScore
    -- our own data keys spawns by map, Questie's by area
    local mapOf = obj.spawnsByMap and function(m) return m end or UiMap
    for area, pts in pairs(spawns) do
        if type(pts) == "table" and #pts > 0 and mapOf(area) then
            local score = #pts + (area == preferArea and 10000 or 0)
            if not bestScore or score > bestScore then bestArea, bestPts, bestScore = area, pts, score end
        end
    end
    if not bestArea then return nil end
    local sx, sy, n = 0, 0, 0
    for _, p in ipairs(bestPts) do
        if p[1] and p[1] >= 0 then sx, sy, n = sx + p[1], sy + p[2], n + 1 end
    end
    if n == 0 then return nil end
    sx, sy = sx / n, sy / n
    local best, bestD
    for _, p in ipairs(bestPts) do
        if p[1] and p[1] >= 0 then
            local d = (p[1] - sx) ^ 2 + (p[2] - sy) ^ 2
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    return { obj.name or "?", mapOf(bestArea), best[1], best[2] }
end

local function Ender(ref, zone)
    if type(ref) ~= "table" then return nil end
    for _, id in ipairs(ref[1] or {}) do
        local s = SpotOf(DB.Get("NPC", id), zone)
        if s then return s end
    end
    for _, id in ipairs(ref[2] or {}) do
        local s = SpotOf(DB.Get("Object", id), zone)
        if s then return s end
    end
    for _, id in ipairs(ref[3] or {}) do
        local item = DB.Get("Item", id)
        if item then return { item.name or "?", 0, 0, 0 } end
    end
end

local raceBit
local function ForPlayer(q)
    if q and q.requiredRaceIds then
        local id = UnitRace and select(3, UnitRace("player"))
        if not id then return true end
        for _, r in ipairs(q.requiredRaceIds) do
            if r == id then return true end
        end
        return false
    end
    local races = q and (q.requiredRaces or 0) or 0
    if races == 0 then return true end
    if not raceBit then
        local id = UnitRace and select(3, UnitRace("player"))
        raceBit = id and 2 ^ (id - 1) or 0
    end
    if raceBit == 0 or not bit then return true end
    return bit.band(races, raceBit) ~= 0
end

local prereqCache, infoCache = {}, {}

--- What a quest needs first: { any = {...}, all = {...}, excl = {...} } or nil.
function DB.Prereqs(id)
    if DB.data.prereqs then return DB.data.prereqs[id] end
    if prereqCache[id] ~= nil then return prereqCache[id] or nil end
    local q = DB.Get("Quest", id)
    if not q then return nil end -- unknown, or Questie still loading: ask again later
    local pre = false
    if q.preQuestSingle or q.preQuestGroup or q.exclusiveTo then
        local function abs(list)
            if type(list) ~= "table" or #list == 0 then return nil end
            local out = {}
            for i, v in ipairs(list) do out[i] = math.abs(v) end
            return out
        end
        pre = { any = abs(q.preQuestSingle), all = abs(q.preQuestGroup), excl = abs(q.exclusiveTo) }
        if not (pre.any or pre.all or pre.excl) then pre = false end
    end
    prereqCache[id] = pre
    return pre or nil
end

--- { n = name, l = level, r = required level, s = start spot, f = finish spot, o = objective spots, q = row }
function DB.Info(id)
    if DB.data.info then return DB.data.info[id] end
    if infoCache[id] ~= nil then return infoCache[id] or nil end
    local q = DB.Get("Quest", id)
    if not q then return nil end
    local zone = q.zoneOrSort
    local objs = {}
    local o = q.objectives
    if type(o) == "table" then
        for _, e in ipairs(o[1] or {}) do objs[#objs + 1] = SpotOf(DB.Get("NPC", e[1]), zone) end
        for _, e in ipairs(o[2] or {}) do objs[#objs + 1] = SpotOf(DB.Get("Object", e[1]), zone) end
        for _, e in ipairs(o[3] or {}) do
            local item = DB.Get("Item", e[1])
            local src = item and (item.npcDrops and item.npcDrops[1] and SpotOf(DB.Get("NPC", item.npcDrops[1]), zone)
                or item.objectDrops and item.objectDrops[1] and SpotOf(DB.Get("Object", item.objectDrops[1]), zone))
            if src then objs[#objs + 1] = src end
        end
    end
    local info = { n = q.name, l = q.level or q.questLevel or 0, r = q.requiredLevel or 0,
                   s = Ender(q.startedBy, zone), f = Ender(q.finishedBy, zone), o = objs, q = q }
    infoCache[id] = info
    return info
end

function DB.QuestName(id)
    local info = DB.Info(id)
    return (info and info.n) or Quests.GetTitle(id) or ("#" .. id)
end

local function TurnedIn(id) return Quests.IsTurnedIn(math.abs(id)) end
local function OnQuest(id) return Quests.IsOnQuest(id) end

--- Earlier quests in the chain, in the order you do them.
function DB.Chain(id)
    if DB.data.chains then return DB.data.chains[id] or {} end
    local order, seen = {}, {}
    local function visit(x, depth)
        if seen[x] or depth > 25 then return end
        seen[x] = true
        local pre = DB.Prereqs(x)
        if pre then
            if pre.any then
                local pick
                for _, p in ipairs(pre.any) do
                    if TurnedIn(p) then pick = nil break end
                    local info = DB.Info(p)
                    if not pick and (not info or ForPlayer(info.q)) then pick = p end
                end
                if pick then visit(pick, depth + 1) end
            end
            for _, p in ipairs(pre.all or {}) do
                local info = DB.Info(p)
                if not info or ForPlayer(info.q) then visit(p, depth + 1) end
            end
        end
        order[#order + 1] = x
    end
    visit(id, 0)
    table.remove(order)
    return order
end

--- Earlier chain quests not turned in yet.
function DB.MissingChain(id)
    local out = {}
    for _, q in ipairs(DB.Chain(id)) do
        if not TurnedIn(q) then out[#out + 1] = q end
    end
    return out
end

--- The quest a breadcrumb sends you to, or nil.
function DB.BreadcrumbFor(id)
    if DB.data.breadcrumbs then return DB.data.breadcrumbs[id] end
    local q = DB.Get("Quest", id)
    local to = q and tonumber(q.breadcrumbForQuestId)
    if to and to ~= 0 then return math.abs(to) end
end

--- The quest that has to be done first, or nil when this one can be picked up.
function DB.Blocked(id)
    local pre = DB.Prereqs(id)
    if not pre then return nil end
    if OnQuest(id) or TurnedIn(id) then return nil end
    if pre.any then
        local ok = false
        for _, q in ipairs(pre.any) do
            if TurnedIn(q) then ok = true break end
        end
        if not ok then return pre.any[1] end
    end
    for _, q in ipairs(pre.all or {}) do
        if not TurnedIn(q) then return q end
    end
    for _, q in ipairs(pre.excl or {}) do
        q = math.abs(q)
        if TurnedIn(q) or OnQuest(q) then return q end
    end
end

------------------------------------------------------------------------
-- What's wrong with a step
------------------------------------------------------------------------

local QUEST_KINDS = { accept = true, turnin = true, complete = true }

-- Only ask about a chain when part of it is really missed: an earlier quest
-- that's neither done nor in your log, and that this step doesn't handle
-- itself. A turn-in or kill step needs the quest itself, so an earlier part
-- that is only in your log still has to be done first.
local function chainMissed(step, id, blocker, chain, needAccept)
    local here = {}
    for _, g in ipairs(step.goals) do
        if QUEST_KINDS[g[1]] then here[g.quest] = true end
    end
    local function missed(q)
        if not q or q == id or here[q] or TurnedIn(q) then return false end
        if needAccept then return true end
        return not OnQuest(q)
    end
    for _, q in ipairs(chain or {}) do
        if missed(q) then return true end
    end
    return #(chain or {}) == 0 and missed(blocker)
end

--- What's wrong with a step (an Engine step: { goals = {...} }), if anything:
---   { kind = "unfinished", quest }        turn in a quest whose objectives aren't done
---   { kind = "missing", quest }           turn in / kill for a quest not in the log
---   { kind = "chain", quest, chain, needAccept }  earlier chain quests aren't done
---   { kind = "locked", quest, by }        a quest you did locks this one out
function DB.StepProblem(step)
    if not (step and step.goals) then return nil end
    for _, g in ipairs(step.goals) do
        local kind, id = g[1], g.quest
        if QUEST_KINDS[kind] and id and OXP.Goals.State(g, step.marks) == "todo" then
            if kind == "turnin" and OnQuest(id) and not Quests.IsComplete(id) then
                return { kind = "unfinished", quest = id }
            end
            local needAccept
            if kind == "accept" then
                needAccept = false
            elseif not g.optional and not OnQuest(id) and not TurnedIn(id) then
                needAccept = true
            end
            if needAccept ~= nil then
                local blocker = DB.Blocked(id)
                if blocker then
                    local pre = DB.Prereqs(id)
                    for _, q in ipairs(pre and pre.excl or {}) do
                        if math.abs(q) == blocker then
                            return { kind = "locked", quest = id, by = blocker }
                        end
                    end
                    local chain = DB.MissingChain(id)
                    if chainMissed(step, id, blocker, chain, needAccept) then
                        return { kind = "chain", quest = id, chain = chain, needAccept = needAccept }
                    end
                elseif needAccept then
                    return { kind = "missing", quest = id }
                end
            end
        end
    end
end

--- The quest id and name when a step needs a quest you don't have, else nil.
function DB.MissingQuest(step)
    for _, g in ipairs(step and step.goals or {}) do
        if (g[1] == "turnin" or g[1] == "complete") and not g.optional and g.quest
            and not OnQuest(g.quest) and not TurnedIn(g.quest) then
            return g.quest, DB.QuestName(g.quest)
        end
    end
end

--- What counts for a quest objective: a list of { kind = "NPC" | "Object",
--- id, name, item = item name when it drops or is looted }, the objective's
--- own kind ("kill", "item", "object", ...), or nil while no data is ready.
local sourceCache = {}
function DB.ObjectiveSources(questId, objIndex)
    local key = questId .. ":" .. objIndex
    if sourceCache[key] then return sourceCache[key].list, sourceCache[key].kind end
    local q = DB.Get("Quest", questId)
    if not q then return nil end
    local list, kind = {}, nil
    local function add(k, id, item)
        local obj = DB.Get(k, id)
        list[#list + 1] = { kind = k, id = id, name = obj and obj.name, item = item, obj = obj }
    end
    local function fromItem(itemId)
        local item = DB.Get("Item", itemId)
        local name = item and item.name
        for _, id in ipairs(item and item.npcDrops or {}) do add("NPC", id, name) end
        for _, id in ipairs(item and item.objectDrops or {}) do add("Object", id, name) end
    end
    local entry = q.objectiveList and q.objectiveList[objIndex]
    if entry then
        -- our own data: the objective by its number
        kind = entry.kind
        if entry.kind == "kill" or entry.kind == "talk" then add("NPC", entry.target)
        elseif entry.kind == "object" then add("Object", entry.target)
        elseif entry.kind == "item" then fromItem(entry.target) end
    else
        local o = type(q.objectives) == "table" and q.objectives or {}
        local i = 0
        for _, e in ipairs(o[1] or {}) do
            i = i + 1
            if i == objIndex then kind = "kill" add("NPC", e[1]) end
        end
        for _, e in ipairs(o[2] or {}) do
            i = i + 1
            if i == objIndex then kind = "object" add("Object", e[1]) end
        end
        for _, e in ipairs(o[3] or {}) do
            i = i + 1
            if i == objIndex then kind = "item" fromItem(e[1]) end
        end
    end
    sourceCache[key] = { list = list, kind = kind }
    return list, kind
end

--- What to do for an objective, in words: "Kill Gobbler for Gobbler's Head",
--- "Kill Bluegill Murloc", "Loot Gobbler's Head from ...", or nil.
function DB.ObjectiveAction(questId, objIndex)
    local list, kind = DB.ObjectiveSources(questId, objIndex)
    if not list or #list == 0 then return nil end
    local npcs, objects = {}, {}
    for _, s in ipairs(list) do
        if s.name then
            if s.kind == "NPC" then npcs[#npcs + 1] = s.name else objects[#objects + 1] = s.name end
        end
    end
    local L = OXP.L
    local function names(t)
        if #t > 2 then return t[1] .. ", " .. t[2] .. " " .. L("and others") end
        return table.concat(t, " " .. L("or") .. " ")
    end
    local item = list[1].item
    if kind == "item" and item then
        if #npcs > 0 then return (L("Kill %s for %s")):format(names(npcs), item) end
        if #objects > 0 then return (L("Loot %s from %s")):format(item, names(objects)) end
    elseif kind == "kill" and #npcs > 0 then
        return (L("Kill %s")):format(names(npcs))
    elseif kind == "talk" and #npcs > 0 then
        return (L("Talk to %s")):format(names(npcs))
    elseif kind == "object" and #objects > 0 then
        return (L("Use %s")):format(names(objects))
    end
end

--- Spawn points (0-100 on `map`) of whatever counts for a quest objective
--- in a zone (`map` its map id, `area` its Questie area id): {} when none,
--- nil while no quest data is ready.
local spawnCache = {}
function DB.ObjectiveSpawns(questId, objIndex, map, area)
    local key = questId .. ":" .. objIndex .. ":" .. tostring(map) .. ":" .. tostring(area)
    if spawnCache[key] ~= nil then return spawnCache[key] end
    local list = DB.ObjectiveSources(questId, objIndex)
    if not list then return nil end
    local pts = {}
    for _, src in ipairs(list) do
        local obj = src.obj
        local spots = obj and type(obj.spawns) == "table" and obj.spawns[obj.spawnsByMap and map or area]
        for _, p in ipairs(spots or {}) do
            if p[1] and p[1] >= 0 then pts[#pts + 1] = { p[1], p[2], src = src } end
        end
    end
    spawnCache[key] = pts
    return pts
end

--- Every spawn of an objective's mobs/objects on every map:
--- { { map, x, y, src }, ... } (only our own data and Questie's keyed by area).
function DB.ObjectiveSpawnsAll(questId, objIndex)
    local list = DB.ObjectiveSources(questId, objIndex)
    if not list then return nil end
    local out = {}
    for _, src in ipairs(list) do
        local obj = src.obj
        for k, pts in pairs(obj and type(obj.spawns) == "table" and obj.spawns or {}) do
            local map = obj.spawnsByMap and k or DB.UiMap(k)
            if map and type(pts) == "table" then
                for _, p in ipairs(pts) do
                    if p[1] and p[1] >= 0 then out[#out + 1] = { map, p[1], p[2], src } end
                end
            end
        end
    end
    return out
end
