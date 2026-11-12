-- A headless stand-in for the WoW client, enough to run OpenXP 2.0's engine
-- outside the game: frames and events, timers, the player, a quest log,
-- zones, flight masters, the hearthstone and bags.
--
--   local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
--   local game = FakeWoW.New(ROOT, { faction = "Alliance", race = "Human", class = "WARRIOR", level = 21 })
--   game:LoadAddon()          -- loads OpenXP/OpenXP.toc, files in order
--   game:Login()              -- ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD
--   game:Accept(123, 2) ; game:FinishObjective(123, 1) ; game:TurnIn(123)
--   local OXP = game.ns
--
-- Each New() replaces the WoW globals, so make one game per test case.
-- Saved variables survive a "reload" when passed in: FakeWoW.New(ROOT, opts, game:SavedVariables()).
local FakeWoW = {}

local Game = {}
Game.__index = Game

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

function FakeWoW.New(root, opts, saved)
    opts = opts or {}
    local game = setmetatable({
        root = root,
        ns = {},
        player = {
            name = opts.name or "Tester",
            faction = opts.faction or "Alliance",
            race = opts.race or "Human",
            class = opts.class or "WARRIOR",
            level = opts.level or 1,
        },
        log = {},          -- ordered quest log: { id=, title=, objectives = { {done=, text=} } }
        completed = {},    -- [questID] = true
        zone = opts.zone or "Elwynn Forest",
        subzone = opts.subzone or "",
        bind = opts.bind or "Goldshire",
        items = {},
        taxi = {},         -- nodes shown on the open taxi map: { {name=, type=} }
        frames = {},
        timers = {},
        errors = {},
        noObjectiveAPI = opts.noObjectiveAPI,
        collapsed = {},    -- [questID] = true: hidden under a collapsed header
    }, Game)
    game:InstallGlobals()
    saved = saved or {}
    OpenXPDB = saved.OpenXPDB
    OpenXPCharDB = saved.OpenXPCharDB
    return game
end

------------------------------------------------------------------------
-- Globals
------------------------------------------------------------------------

function Game:InstallGlobals()
    local game = self
    unpack = unpack or table.unpack
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    geterrorhandler = function()
        return function(err)
            game.errors[#game.errors + 1] = tostring(err)
        end
    end

    CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(e) self.events[e] = true end
        function frame:UnregisterEvent(e) self.events[e] = nil end
        function frame:SetScript(name, fn) self.scripts[name] = fn end
        game.frames[#game.frames + 1] = frame
        return frame
    end

    C_Timer = {
        After = function(_, fn) game.timers[#game.timers + 1] = fn end,
    }
    GetTime = function() return 0 end
    C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "test" or nil end }

    UnitName = function() return game.player.name end
    UnitFactionGroup = function() return game.player.faction, game.player.faction end
    UnitRace = function() return game.player.race, game.player.race end
    UnitClass = function() return game.player.class, game.player.class end
    UnitLevel = function() return game.player.level end

    -- Quest log
    local function visible()
        local rows = { { header = true, title = "Quests" } }
        for _, q in ipairs(game.log) do
            if not game.collapsed[q.id] then rows[#rows + 1] = q end
        end
        return rows
    end
    local function find(id)
        for _, q in ipairs(game.log) do
            if q.id == id then return q end
        end
    end
    local function isComplete(q)
        for _, o in ipairs(q.objectives) do
            if not o.done then return false end
        end
        return true
    end
    game.findQuest = find
    GetNumQuestLogEntries = function() return #visible() end
    GetQuestLogTitle = function(i)
        local q = visible()[i]
        if not q then return nil end
        if q.header then return q.title, 0, nil, true, false, nil, 0, 0 end
        return q.title, 20, nil, false, false, isComplete(q) and 1 or nil, 0, q.id
    end
    GetNumQuestLeaderBoards = function(i)
        local q = visible()[i]
        return q and q.objectives and #q.objectives or 0
    end
    GetQuestLogLeaderBoard = function(o, i)
        local q = visible()[i]
        local obj = q and q.objectives[o]
        if not obj then return nil end
        return obj.text, "monster", obj.done
    end
    C_QuestLog = {
        IsOnQuest = function(id) return find(id) ~= nil end,
        IsQuestFlaggedCompleted = function(id) return game.completed[id] == true end,
        GetTitleForQuestID = function(id) local q = find(id) return q and q.title end,
    }
    if not game.noObjectiveAPI then
        C_QuestLog.GetQuestObjectives = function(id)
            local q = find(id)
            if not q then return {} end
            local out = {}
            for i, o in ipairs(q.objectives) do
                out[i] = { text = o.text, type = "monster", finished = o.done,
                           numFulfilled = o.done and 1 or 0, numRequired = 1 }
            end
            return out
        end
    end

    -- World
    GetRealZoneText = function() return game.zone end
    GetZoneText = function() return game.zone end
    GetSubZoneText = function() return game.subzone end
    C_Map = {
        GetBestMapForUnit = function() return nil end,
        GetMapInfo = function() return nil end,
    }
    GetBindLocation = function() return game.bind end
    GetItemCount = function(id) return game.items[id] or 0 end
    NumTaxiNodes = function() return #game.taxi end
    TaxiNodeName = function(i) return game.taxi[i] and game.taxi[i].name end
    TaxiNodeGetType = function(i) return game.taxi[i] and game.taxi[i].type or "NONE" end
    ERR_NEWTAXIPATH = "New flight path discovered!"
end

------------------------------------------------------------------------
-- Loading the addon
------------------------------------------------------------------------

function Game:LoadFile(path)
    local src = readFile(path)
    if not src then error("missing file " .. path) end
    local chunk, err = loadstring(src, "@" .. path:sub(#self.root + 2))
    if not chunk then error(err) end
    chunk("OpenXP", self.ns)
end

function Game:LoadXml(path)
    local src = readFile(path)
    if not src then error("missing file " .. path) end
    local dir = path:match("^(.*)/[^/]*$")
    for tag, file in src:gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
        local full = dir .. "/" .. file:gsub("\\", "/")
        if tag == "Include" then
            self:LoadXml(full)
        elseif tag == "Script" then
            self:LoadFile(full)
        end
    end
end

--- Load OpenXP/OpenXP.toc's files in order, the way the client does.
function Game:LoadAddon()
    local dir = self.root .. "/OpenXP"
    local toc = readFile(dir .. "/OpenXP.toc")
    if not toc then error("missing OpenXP/OpenXP.toc") end
    for line in toc:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local file = dir .. "/" .. line:gsub("\\", "/")
            if file:lower():match("%.xml$") then
                self:LoadXml(file)
            else
                self:LoadFile(file)
            end
        end
    end
    return self.ns
end

------------------------------------------------------------------------
-- Events and time
------------------------------------------------------------------------

function Game:Fire(event, ...)
    for _, frame in ipairs(self.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

--- Run timers until none are left (a few rounds, as timers can add timers).
function Game:Flush()
    for _ = 1, 20 do
        if #self.timers == 0 then return end
        local now = self.timers
        self.timers = {}
        for _, fn in ipairs(now) do fn() end
    end
    error("timers keep adding timers")
end

function Game:Login()
    self:Fire("ADDON_LOADED", "OpenXP")
    self:Fire("PLAYER_LOGIN")
    self:Fire("PLAYER_ENTERING_WORLD", true, false)
    self:Flush()
end

function Game:SavedVariables()
    return { OpenXPDB = OpenXPDB, OpenXPCharDB = OpenXPCharDB }
end

------------------------------------------------------------------------
-- Things the player does
------------------------------------------------------------------------

function Game:Accept(id, objectives)
    if self.findQuest(id) then return end
    local q = { id = id, title = "Quest " .. id, objectives = {} }
    for i = 1, objectives or 0 do
        q.objectives[i] = { text = "Objective " .. i .. ": 0/1", done = false }
    end
    self.log[#self.log + 1] = q
    self:Fire("QUEST_ACCEPTED", #self.log, id)
    self:Fire("QUEST_LOG_UPDATE")
    self:Flush()
end

function Game:FinishObjective(id, obj)
    local q = self.findQuest(id)
    if not q then error("FinishObjective: not on quest " .. id) end
    for i = #q.objectives + 1, obj do
        q.objectives[i] = { text = "Objective " .. i .. ": 0/1", done = false }
    end
    q.objectives[obj].done = true
    q.objectives[obj].text = "Objective " .. obj .. ": 1/1"
    self:Fire("UNIT_QUEST_LOG_CHANGED", "player")
    self:Fire("QUEST_LOG_UPDATE")
    self:Flush()
end

function Game:TurnIn(id)
    for i, q in ipairs(self.log) do
        if q.id == id then
            table.remove(self.log, i)
            break
        end
    end
    self.completed[id] = true
    self:Fire("QUEST_TURNED_IN", id, 0, 0)
    self:Fire("QUEST_REMOVED", id)
    self:Fire("QUEST_LOG_UPDATE")
    self:Flush()
end

function Game:Abandon(id)
    for i, q in ipairs(self.log) do
        if q.id == id then
            table.remove(self.log, i)
            break
        end
    end
    self:Fire("QUEST_REMOVED", id)
    self:Fire("QUEST_LOG_UPDATE")
    self:Flush()
end

function Game:SetLevel(level)
    if level <= self.player.level then return end
    self.player.level = level
    self:Fire("PLAYER_LEVEL_UP", level)
    self:Flush()
end

function Game:EnterZone(zone, subzone)
    self.zone = zone
    self.subzone = subzone or ""
    self:Fire("ZONE_CHANGED_NEW_AREA")
    self:Flush()
end

--- Talk to a flight master: the taxi map opens showing `nodes`
--- ({ "Name, Zone", ... }; the first is where the player stands).
function Game:OpenTaxi(nodes)
    self.taxi = {}
    for i, name in ipairs(nodes) do
        self.taxi[i] = { name = name, type = i == 1 and "CURRENT" or "REACHABLE" }
    end
    self:Fire("TAXIMAP_OPENED")
    self:Flush()
end

--- The "New flight path discovered!" message, without opening the map.
function Game:DiscoverFlightPath()
    self:Fire("UI_INFO_MESSAGE", 0, ERR_NEWTAXIPATH)
    self:Flush()
end

function Game:Bind(place)
    self.bind = place
    self:Fire("HEARTHSTONE_BOUND")
    self:Flush()
end

function Game:AddItem(id, count)
    self.items[id] = (self.items[id] or 0) + (count or 1)
    self:Fire("BAG_UPDATE_DELAYED")
    self:Flush()
end

------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------

--- A tiny assertion counter: t.ok(v, msg), t.eq(got, want, msg); t.fails.
function FakeWoW.Checker(prefix)
    local t = { fails = 0 }
    function t.ok(v, msg)
        if not v then
            t.fails = t.fails + 1
            print("  FAIL " .. (prefix and prefix .. ": " or "") .. tostring(msg))
        end
        return v
    end
    function t.eq(got, want, msg)
        return t.ok(got == want, tostring(msg) .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
    return t
end

return FakeWoW
