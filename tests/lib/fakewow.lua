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
        delayed = {},
        tickers = {},
        now = 0,
        errors = {},
        -- where the player stands: a fake world (see FakeHBD below)
        pos = { map = opts.map or 1429, x = opts.x or 50, y = opts.y or 50 },
        noObjectiveAPI = opts.noObjectiveAPI,
        collapsed = {},    -- [questID] = true: hidden under a collapsed header
        unloaded = {},     -- [questID] = true: in the log, details not loaded by the client yet
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
    tinsert, tremove = table.insert, table.remove
    LibStub = nil -- a fresh LibStub per game, so the fake libraries can register again
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    geterrorhandler = function()
        return function(err)
            game.errors[#game.errors + 1] = tostring(err)
        end
    end

    -- Every frame, texture and font string is a widget that remembers what
    -- it was told (text, size, shown, scripts) and answers the rest with a
    -- do-nothing function, so UI code runs without drawing anything.
    local widgetMT
    local function Widget(kind, name)
        local w = setmetatable({ kind = kind, events = {}, scripts = {}, shown = kind ~= "Frame" and kind ~= "Button",
                                 w = 100, h = 20, points = {} }, widgetMT)
        if name then _G[name] = w end
        return w
    end
    game.Widget = Widget
    local methods = {
        RegisterEvent = function(self, e) self.events[e] = true end,
        UnregisterEvent = function(self, e) self.events[e] = nil end,
        UnregisterAllEvents = function(self) self.events = {} end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
        HookScript = function(self, name, fn)
            local old = self.scripts[name]
            self.scripts[name] = function(...) if old then old(...) end return fn(...) end
        end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, v) self.shown = v and true or false end,
        IsShown = function(self) return self.shown end,
        IsVisible = function(self) return self.shown end,
        SetText = function(self, t)
            -- like the game: a font string with no font can't take text
            if self.kind == "FontString" and not self.fontSet and t and t ~= "" then
                error("FontString:SetText(): Font not set", 2)
            end
            self.text = t
        end,
        SetFontObject = function(self) self.fontSet = true end,
        GetText = function(self) return self.text end,
        SetFormattedText = function(self, f, ...) self.text = f:format(...) end,
        SetSize = function(self, w, h) self.w, self.h = w, h end,
        SetWidth = function(self, w) self.w = w end,
        SetHeight = function(self, h) self.h = h end,
        GetWidth = function(self) return self.w end,
        GetHeight = function(self) return self.h end,
        GetSize = function(self) return self.w, self.h end,
        GetStringWidth = function(self) return #(self.text or "") * 6 end,
        GetStringHeight = function() return 14 end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        ClearAllPoints = function(self) self.points = {} end,
        GetPoint = function(self) local p = self.points[1] if p then return p[1], p[2], p[3], p[4], p[5] end end,
        GetCenter = function() return 500, 400 end,
        GetLeft = function() return 400 end,
        GetScale = function(self) return self.scale or 1 end,
        SetScale = function(self, s) self.scale = s end,
        GetEffectiveScale = function() return 1 end,
        GetFrameLevel = function() return 1 end,
        GetID = function(self) return self.id or 0 end,
        GetName = function(self) return self.name end,
        GetParent = function(self) return self.parent end,
        SetParent = function(self, p) self.parent = p end,
        GetFont = function() return "Fonts\\ARIALN.TTF", 12, "" end,
        SetFont = function(self) self.fontSet = true return true end,
        IsMouseOver = function() return false end,
        GetChecked = function(self) return self.checked end,
        SetChecked = function(self, v) self.checked = v end,
        GetObjectType = function(self) return self.kind end,
        SetAttribute = function(self, k, v) self.attrs = self.attrs or {}; self.attrs[k] = v end,
        GetAttribute = function(self, k) return self.attrs and self.attrs[k] end,
    }
    local function Creator(kind)
        return function(self, name)
            local w = Widget(kind, name)
            w.parent = self
            return w
        end
    end
    methods.CreateTexture = Creator("Texture")
    methods.CreateFontString = function(self, name, layer, template)
        local w = Widget("FontString", name)
        w.parent, w.fontSet = self, template ~= nil
        return w
    end
    methods.CreateLine = Creator("Line")
    methods.CreateAnimationGroup = Creator("AnimationGroup")
    methods.CreateAnimation = Creator("Animation")
    widgetMT = {
        __index = function(_, k)
            if methods[k] then return methods[k] end
            if type(k) == "string" and k:match("^%u") then return function() end end
            return nil
        end,
    }

    CreateFrame = function(kind, name, parent)
        local frame = Widget(kind or "Frame", name)
        frame.name, frame.parent = name, parent
        game.frames[#game.frames + 1] = frame
        return frame
    end
    UIParent = Widget("Frame")
    Minimap = Widget("Frame")
    Minimap.shown = true
    GameTooltip = Widget("Frame")
    UISpecialFrames = {}
    SlashCmdList = {}
    hooksecurefunc = function() end
    strsplit = function(sep, s)
        local out = {}
        for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
        return unpack(out)
    end
    GetLocale = function() return "enUS" end
    GetCVar = function() return "0" end
    SetCVar = function() end
    GetPlayerFacing = function() return 0 end
    UnitXP = function() return 0 end
    UnitXPMax = function() return 1000 end
    GetXPExhaustion = function() return 0 end
    UnitExists = function() return false end
    UnitOnTaxi = function() return false end
    IsIndoors = function() return false end
    IsResting = function() return false end
    IsInInstance = function() return false end
    UnitIsDeadOrGhost = function() return false end
    IsShiftKeyDown = function() return false end
    GetCursorPosition = function() return 0, 0 end
    debugprofilestop = function() return 0 end

    C_Timer = {
        After = function(delay, fn)
            -- only "next frame" timers run in Flush; delayed ones (tips,
            -- font reloads) are kept apart and run by RunDelayed
            if (delay or 0) <= 0 then
                game.timers[#game.timers + 1] = fn
            else
                game.delayed[#game.delayed + 1] = fn
            end
        end,
        NewTicker = function(_, fn)
            local t = { Cancel = function(self) self.cancelled = true end }
            game.tickers[#game.tickers + 1] = { fn = fn, t = t }
            return t
        end,
    }
    GetTime = function() return game.now end
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
        -- a quest whose details the client hasn't loaded yet shows no id
        return q.title, 20, nil, false, false, isComplete(q) and 1 or nil, 0, game.unloaded[q.id] and 0 or q.id
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
        IsOnQuest = function(id) return find(id) ~= nil and not game.unloaded[id] end,
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

------------------------------------------------------------------------
-- A fake HereBeDragons: every map is a 1000 x 1000 yard square in its own
-- spot of the world, on Kalimdor (instance 1) or the Eastern Kingdoms (0).
------------------------------------------------------------------------

local KALIMDOR = { [1411] = true, [1412] = true, [1413] = true, [1414] = true, [1454] = true, [1456] = true, [1457] = true }
for m = 1438, 1452 do KALIMDOR[m] = true end
local SIZE = 1000

local function MapRect(map)
    return (map % 1000) * 3 * SIZE, 0, KALIMDOR[map] and 1 or 0
end

function FakeWoW.InstallHBD(game)
    local hbd = LibStub:NewLibrary("HereBeDragons-2.0", 999)
    function hbd:GetWorldCoordinatesFromZone(x, y, map)
        if not (map and x and y) then return nil end
        local ox, oy, inst = MapRect(map)
        return ox + x * SIZE, oy + y * SIZE, inst
    end
    function hbd:GetZoneCoordinatesFromWorld(wx, wy, map, allowOutside)
        local ox, oy = MapRect(map)
        local x, y = (wx - ox) / SIZE, (wy - oy) / SIZE
        if not allowOutside and (x < 0 or x > 1 or y < 0 or y > 1) then return nil end
        return x, y
    end
    function hbd:GetPlayerWorldPosition()
        local p = game.pos
        if p.wx then return p.wx, p.wy, p.inst end
        return self:GetWorldCoordinatesFromZone(p.x / 100, p.y / 100, p.map)
    end
    function hbd:GetPlayerZonePosition()
        local p = game.pos
        return p.x / 100, p.y / 100, p.map
    end
    function hbd:GetPlayerZone() return game.pos.map end
    function hbd:GetWorldVector(_, ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        return math.atan2(-dx, dy), math.sqrt(dx * dx + dy * dy)
    end
    function hbd:GetWorldDistance(_, ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        return math.sqrt(dx * dx + dy * dy)
    end
    local pins = LibStub:NewLibrary("HereBeDragons-Pins-2.0", 999)
    game.pins = { world = 0, minimap = 0 }
    function pins:AddWorldMapIconWorld() game.pins.world = game.pins.world + 1 end
    function pins:AddMinimapIconWorld() game.pins.minimap = game.pins.minimap + 1 end
    function pins:RemoveAllWorldMapIcons() game.pins.world = 0 end
    function pins:RemoveAllMinimapIcons() game.pins.minimap = 0 end
end

--- Put the player on a map at x, y (0-100).
function Game:MoveTo(map, x, y)
    self.pos = { map = map, x = x, y = y }
end

--- Put the player at a world spot (real game coordinates, like a flight
--- master's), keeping the map they're on.
function Game:MoveToWorld(wx, wy, inst)
    self.pos = { map = self.pos.map, x = self.pos.x, y = self.pos.y, wx = wx, wy = wy, inst = inst }
end

--- Let `secs` of game time pass: OnUpdate scripts and tickers run once.
function Game:Advance(secs)
    self.now = self.now + (secs or 1)
    for _, frame in ipairs(self.frames) do
        local fn = frame.scripts.OnUpdate
        if fn then fn(frame, secs or 1) end
    end
    for _, tk in ipairs(self.tickers) do
        if not tk.t.cancelled then tk.fn(tk.t) end
    end
    self:Flush()
end

--- Load OpenXP/OpenXP.toc's files in order, the way the client does. The
--- HereBeDragons files are swapped for the fake above.
function Game:LoadAddon()
    local dir = self.root .. "/OpenXP"
    local toc = readFile(dir .. "/OpenXP.toc")
    if not toc then error("missing OpenXP/OpenXP.toc") end
    for line in toc:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local file = dir .. "/" .. line:gsub("\\", "/")
            if file:find("HereBeDragons", 1, true) then
                if not self.hbdInstalled then
                    self.hbdInstalled = true
                    FakeWoW.InstallHBD(self)
                end
            elseif file:lower():match("%.xml$") then
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
