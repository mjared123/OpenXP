-- Party sync with a stand-in WoW API: two copies of PartySync.lua (Anna,
-- the leader, and Bob) pass their status messages to each other.
local ROOT = ...
unpack = unpack or table.unpack
tinsert = table.insert

local function obj(name)
    local o = {__name = name, shown = false}
    return setmetatable(o, {__index = function(t, k)
        if type(k) ~= "string" or k:match("^[a-z_]") then return nil end
        if k == "SetScript" then return function(self, ev, fn) rawset(self, "_" .. ev, fn) end end
        if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
        if k == "GetText" then return function(self) return rawget(self, "_text") end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
        if k == "GetStringWidth" then return function() return 40 end end
        if k == "CreateTexture" or k == "CreateFontString" then return function() return obj(k) end end
        return function() end
    end})
end
function CreateFrame(kind) return obj(kind) end
GameTooltip = obj("GameTooltip")
local clock = 100
function GetTime() return clock end
function GetNumGroupMembers() return 2 end
function IsInRaid() return false end
function UnitInBattleground() return nil end
function Ambiguate(n) return (n:gsub("%-.*$", "")) end
RAID_CLASS_COLORS = {HUNTER = {colorStr = "ffaad372"}}

local src = assert(io.open(ROOT .. "/PartySync.lua")):read("*a")

-- The wire: messages a copy sends land in the other copy's inbox
local copies = {}
local function NewCopy(name, other, isLeader, opts)
    local guide = {name = "Alliance 21-30", steps = {}}
    for i = 1, 50 do guide.steps[i] = {index = i, elements = {}} end
    guide.steps[10].elements = {{tag = "complete", questId = 101}}
    guide.steps[11].elements = {{tag = "turnin", questId = 101}, {tag = "accept", questId = 102}}
    local addon = {
        player = {name = name, class = opts.class},
        currentGuide = guide,
        step = opts.step,
        log = opts.log or {},
        turnedIn = opts.turnedIn or {},
        settings = {profile = {}},
        printed = {},
    }
    addon.GetGuideProgress = function() return addon.step end
    addon.RXPFrame = {activeSteps = {}}
    addon.SetActive = function() addon.RXPFrame.activeSteps = {guide.steps[addon.step]} end
    addon.SetActive()
    addon.IsOnQuest = function(id) return addon.log[id] ~= nil end
    addon.IsQuestComplete = function(id) return addon.log[id] == "done" end
    addon.IsQuestTurnedIn = function(id) return addon.turnedIn[id] end
    addon.card = {frame = obj("card"), JumpTo = function(i) addon.step = i; addon.SetActive(); addon.jumped = i end}
    addon.card.frame.shown = true
    addon.comms = {
        _commPrefix = "OpenXPComms",
        Serialize = function(_, t) return t end,
        SendCommMessage = function(_, _, msg) tinsert(copies[other].inbox, {from = name, msg = msg}) end,
        PrettyPrint = function(_, a, b) tinsert(addon.printed, b or a) end,
    }
    local env = setmetatable({
        UnitLevel = function() return opts.level end,
        UnitName = function() return other end,
        UnitIsGroupLeader = function(unit) if unit == "player" then return isLeader end return not isLeader end,
    }, {__index = _G})
    local chunk = assert(loadstring(src))
    setfenv(chunk, env)
    chunk("OpenXP", addon)
    local c = {addon = addon, ps = addon.partySync, inbox = {}, env = env}
    copies[name] = c
    return c
end

local anna = NewCopy("Anna", "Bob", true, {step = 10, level = 24, class = "HUNTER", log = {[101] = "done"}})
local bob = NewCopy("Bob", "Anna", false, {step = 8, level = 23, class = "MAGE", log = {}})

local function Deliver()
    for _, c in pairs(copies) do
        local inbox = c.inbox
        c.inbox = {}
        for _, m in ipairs(inbox) do c.ps.OnStatus(m.from, m.msg) end
    end
end
local function Tick() clock = clock + 1.1; anna.ps.Tick(); bob.ps.Tick(); Deliver() end

local failures = 0
local function check(cond, msg)
    if not cond then failures = failures + 1; print("FAIL: " .. msg) else print("ok   " .. msg) end
end

Tick(); Tick()
check(anna.ps.members.Bob and bob.ps.members.Anna, "both copies see each other")
local rows = bob.ps.Rows()
check(rows[1] and rows[1].where == "2 ahead", "Bob sees Anna 2 steps ahead (got " .. tostring(rows[1] and rows[1].where) .. ")")
rows = anna.ps.Rows()
check(rows[1].quests[1] and rows[1].quests[1].text == "needs quest", "Anna sees Bob needs quest 101")
check(#anna.ps.NeedQuest(101) == 1, "NeedQuest lists Bob for 101")

-- Bob gets the quest: Anna sees it within a tick
bob.addon.log[101] = "on"
Tick()
check(anna.ps.Rows()[1].quests[1].text == "on it", "Anna sees Bob on the quest")
bob.addon.log[101] = "done"
Tick()
check(anna.ps.Rows()[1].quests[1].text == "ready", "Anna sees Bob ready to turn in")

-- Follow: off by default, so Bob stays put when Anna moves
anna.addon.step = 11; anna.addon.SetActive()
Tick()
check(bob.addon.step == 8, "Bob doesn't follow with the setting off")
-- Bob turns on follow; next time Anna moves Bob goes with her
bob.addon.settings.profile.partyFollowLeader = true
anna.addon.step = 12; anna.addon.SetActive()
Tick()
check(bob.addon.step == 12, "Bob follows Anna to step 12 (at " .. bob.addon.step .. ")")
-- Bob presses Next on his own: stays there until Anna moves
bob.addon.step = 13; bob.addon.SetActive()
Tick(); Tick()
check(bob.addon.step == 13, "Bob's own Next isn't undone while Anna stands still")
-- Anna on another guide: Bob isn't moved and is told once
anna.addon.currentGuide = {name = "Alliance 30-40", steps = {}}
anna.addon.step = 3
Tick(); Tick()
check(bob.addon.step == 13, "Bob isn't moved to another guide's step")
check(#bob.addon.printed == 1, "Bob is told once that Anna is on another guide")
check(bob.ps.Rows()[1].where == "other guide", "panel says other guide")

-- Leader never follows
anna.addon.settings.profile.partyFollowLeader = true
check(not anna.ps.Following(), "the leader doesn't follow anyone")

-- Quiet when nothing changes: no message until the heartbeat
local sent = 0
local orig = anna.addon.comms.SendCommMessage
anna.addon.comms.SendCommMessage = function(...) sent = sent + 1; return orig(...) end
for _ = 1, 5 do Tick() end
check(sent == 0, "no messages while nothing changes (" .. sent .. ")")
for _ = 1, 10 do Tick() end
check(sent == 1, "one heartbeat after 15 s (" .. sent .. ")")

-- Bad messages are ignored
anna.ps.OnStatus("Bob", {g = 5})
anna.ps.OnStatus("Bob", "junk")
check(anna.ps.members.Bob.level == 23, "bad messages are ignored")

-- Leaving the party clears the list
GetNumGroupMembers = function() return 1 end
Tick()
check(next(anna.ps.members) == nil, "members cleared after leaving the party")

return failures
