-- /oxp questdump: guide-making tool.
-- Copies what the installed Questie knows about quests (including WoW Forever
-- quests that aren't in Questie's public data files yet) into the
-- OXPQuestieDump saved variable, so tools/audit_guides.py and
-- tools/build_route.py can read it from WTF\Account\<name>\SavedVariables
-- after a /reload. It stays on your own PC: OpenXP never ships this data.
-- /oxp questdump clear empties it again.

local _, OXP = ...

local dump = {}
OXP.QuestDump = dump

local PER_TICK = 150 -- quests read per frame, so the game doesn't freeze

local function Say(msg)
    print("|cFF66BB6AOpenXP:|r " .. msg)
end

local function QDB()
    local loader = _G.QuestieLoader
    if not (loader and loader.ImportModule) then return end
    local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
    if ok and db and db.QueryQuest and db.QuestPointers then return db end
end

-- Questie's rows as int-keyed tables in its own key order
local function Row(db, kind, id)
    local query = db["Query" .. kind]
    local order = db["_" .. ({Quest = "quest", NPC = "npc", Object = "object", Item = "item"})[kind]
                      .. "AdapterQueryOrder"]
    if not (query and order) then return end
    local ok, row = pcall(query, id, order)
    if ok and type(row) == "table" then return row end
end

local function Each(list, fn)
    if type(list) ~= "table" then return end
    for _, v in pairs(list) do fn(v) end
end

-- NPCs, objects and items a quest row points at
local function Refs(db, row, want)
    local k = db.questKeys or {}
    local s, f, o = row[k.startedBy or 2], row[k.finishedBy or 3], row[k.objectives or 10]
    if type(s) == "table" then
        Each(s[1], function(id) want.npc[id] = true end)
        Each(s[2], function(id) want.object[id] = true end)
        Each(s[3], function(id) want.item[id] = true end)
    end
    if type(f) == "table" then
        Each(f[1], function(id) want.npc[id] = true end)
        Each(f[2], function(id) want.object[id] = true end)
    end
    if type(o) == "table" then
        Each(o[1], function(e) if type(e) == "table" then want.npc[e[1]] = true end end)
        Each(o[2], function(e) if type(e) == "table" then want.object[e[1]] = true end end)
        Each(o[3], function(e) if type(e) == "table" then want.item[e[1]] = true end end)
        Each(o[5], function(e)
            if type(e) == "table" then
                Each(e[1], function(id) want.npc[id] = true end)
                if e[2] then want.npc[e[2]] = true end
            end
        end)
    end
end

function dump.Clear()
    _G.OXPQuestieDump = nil
    Say("Quest data dump cleared. /reload to save.")
end

function dump.Run()
    if dump.running then return Say("Already dumping, hang on.") end
    local db = QDB()
    if not db then return Say("Questie isn't loaded (or still starting up). Try again in a few seconds.") end

    local out = {
        time = date and date("%Y-%m-%d %H:%M") or "",
        build = select(4, GetBuildInfo()),
        keys = {quest = db.questKeys, npc = db.npcKeys, object = db.objectKeys, item = db.itemKeys},
        quest = {}, npc = {}, object = {}, item = {},
    }
    local want = {npc = {}, object = {}, item = {}}
    local jobs = {}
    for id in pairs(db.QuestPointers) do tinsert(jobs, {"Quest", id}) end
    local total = #jobs
    Say(("Reading %d quests from Questie. Keep playing, this takes a minute."):format(total))
    dump.running = true

    local stage, i = "quests", 1
    C_Timer.NewTicker(0, function(ticker)
        local stop = math.min(#jobs, i + PER_TICK - 1)
        for n = i, stop do
            local kind, id = jobs[n][1], jobs[n][2]
            local row = Row(db, kind, id)
            if row then
                if kind == "Quest" then
                    out.quest[id] = row
                    pcall(Refs, db, row, want)
                elseif kind == "Item" then
                    out.item[id] = row
                    local ik = db.itemKeys or {}
                    Each(row[ik.npcDrops or 0], function(nid) if not out.npc[nid] then want.npc[nid] = true end end)
                    Each(row[ik.objectDrops or 0], function(oid) if not out.object[oid] then want.object[oid] = true end end)
                elseif kind == "NPC" then
                    out.npc[id] = row
                else
                    out.object[id] = row
                end
            end
        end
        i = stop + 1
        if i <= #jobs then return end

        if stage == "quests" then
            -- items first, since their drop lists add NPCs and objects
            stage, jobs, i = "items", {}, 1
            for id in pairs(want.item) do tinsert(jobs, {"Item", id}) end
            Say(("Quests done. Reading %d items."):format(#jobs))
        elseif stage == "items" then
            stage, jobs, i = "places", {}, 1
            for id in pairs(want.npc) do tinsert(jobs, {"NPC", id}) end
            for id in pairs(want.object) do tinsert(jobs, {"Object", id}) end
            Say(("Items done. Reading %d NPCs and objects."):format(#jobs))
        else
            ticker:Cancel()
            dump.running = false
            _G.OXPQuestieDump = out
            Say(("Done: %d quests. Type /reload to save it for the guide tools."):format(total))
        end
    end)
end

OXP.AddCommand("questdump", nil, function(rest)
    if rest == "clear" then dump.Clear() else dump.Run() end
end)
