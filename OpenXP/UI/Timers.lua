-- Timers: how long the flight you're on still takes, and when your
-- Hearthstone is ready again (the card says so on steps that tell you to
-- use it).
--
-- Flight times: what you flew before (saved per route in OpenXPDB), else the
-- game's own flight times (Data/Flights.lua), else the distance.
local _, OXP = ...

local Timers = {}
OXP.Timers = Timers

local Style, L = OXP.Style, OXP.L
local C = Style.C

local HEARTHSTONE = 6948
local function GetItemCooldown(id)
    local fn = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
    if fn then return fn(id) end
end

local function Now() return GetTime and GetTime() or 0 end

------------------------------------------------------------------------
-- Hearthstone
------------------------------------------------------------------------

--- Seconds until the Hearthstone is ready (0 when ready, nil without one).
function Timers.HearthRemaining()
    if GetItemCount and GetItemCount(HEARTHSTONE) == 0 then return nil end
    local start, duration = GetItemCooldown(HEARTHSTONE)
    if not start or start == 0 or (duration or 0) <= 1.5 then return 0 end
    return math.max(0, start + duration - Now())
end

function Timers.Clock(secs)
    secs = math.floor(secs + 0.5)
    if secs >= 3600 then return ("%d:%02d:%02d"):format(secs / 3600, (secs % 3600) / 60, secs % 60) end
    return ("%d:%02d"):format(secs / 60, secs % 60)
end

--- A card line for a step that tells you to use your Hearthstone while it's
--- on cooldown, else nil.
function Timers.HearthLine(step)
    if OXP.settings.hearthReminder == false then return nil end
    local mentions = false
    for _, g in ipairs(step.goals or {}) do
        local t = g.text and g.text:lower()
        if t and (t:find("hearthstone", 1, true) or t:find("hearth to", 1, true) or t:find("hearth back", 1, true))
            and not t:find("set your hearthstone", 1, true) then
            mentions = true
        end
    end
    if not mentions then return nil end
    local left = Timers.HearthRemaining()
    if not left or left <= 0 then return nil end
    return "|cFFF2C35C" .. L("Hearthstone ready in") .. " " .. Timers.Clock(left) .. "|r"
end

------------------------------------------------------------------------
-- Flights
------------------------------------------------------------------------

local bar = CreateFrame("StatusBar", "OpenXPFlightBar", UIParent)
Timers.bar = bar
bar:SetSize(240, 16)
bar:SetPoint("TOP", UIParent, "TOP", 0, -120)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetStatusBarColor(C.blue[1], C.blue[2], C.blue[3], 0.8)
bar.bg = bar:CreateTexture(nil, "BACKGROUND")
bar.bg:SetAllPoints()
bar.bg:SetColorTexture(0, 0, 0, 0.6)
bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bar.text:SetPoint("CENTER")
bar:Hide()

local flight -- { from, to, start, estimate }

local function FlightKey(from, to) return (from or "?") .. ">" .. (to or "?") end

local function NodeIdByName(name)
    for id, n in pairs(OXP.flightData and OXP.flightData.nodes or {}) do
        if n.name == name then return id end
    end
end

--- Seconds a flight from `from` to `to` (flight master names) takes.
function Timers.FlightEstimate(from, to)
    local db = OXP.db and OXP.db.flightTimes
    local known = db and db[FlightKey(from, to)]
    if known then return known end
    local a, b = NodeIdByName(from), NodeIdByName(to)
    local times = OXP.flightData and OXP.flightData.times
    local t = a and b and times and times[a] and times[a][b]
    if t then return t end
    local na, nb = a and OXP.flightData.nodes[a], b and OXP.flightData.nodes[b]
    if na and nb and na.inst == nb.inst then
        return OXP.Places.Distance(na.wx, na.wy, nb.wx, nb.wy) / 30 + 15
    end
end

--- Call when a flight starts (tests call it directly).
function Timers.StartFlight(from, to)
    flight = { from = from, to = to, start = Now(), estimate = Timers.FlightEstimate(from, to) }
    Timers.flight = flight
end

--- Call when you land: the real time is kept for next time.
function Timers.EndFlight()
    if not flight then return end
    local took = Now() - flight.start
    if took > 5 and OXP.db then
        OXP.db.flightTimes = OXP.db.flightTimes or {}
        OXP.db.flightTimes[FlightKey(flight.from, flight.to)] = math.floor(took + 0.5)
    end
    flight, Timers.flight = nil, nil
    bar:Hide()
end

if hooksecurefunc and _G.TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(index)
        local from
        for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
            if TaxiNodeGetType(i) == "CURRENT" then from = TaxiNodeName(i) end
        end
        Timers.StartFlight(from, TaxiNodeName(index))
    end)
end

local onTaxi, wait = false, 0
bar:SetScript("OnUpdate", function(self, elapsed)
    wait = wait + elapsed
    if wait < 0.2 then return end
    wait = 0
    if not flight then self:Hide() return end
    local left = (flight.estimate or 0) - (Now() - flight.start)
    if flight.estimate then
        self:SetMinMaxValues(0, flight.estimate)
        self:SetValue(math.max(0, left))
    end
    self.text:SetText(("%s %s  %s"):format(L("Flying to"), (flight.to or "?"):match("^[^,]+") or "?",
        flight.estimate and Timers.Clock(math.max(0, left)) or "..."))
end)

-- watch for landing (and for being on a flight at all, after a /reload)
local watcher = CreateFrame("Frame")
local tick = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    tick = tick + elapsed
    if tick < 0.5 then return end
    tick = 0
    local now = UnitOnTaxi and UnitOnTaxi("player") or false
    if now and not onTaxi and flight and OXP.settings.flightTimer ~= false then bar:Show() end
    if onTaxi and not now then Timers.EndFlight() end
    onTaxi = now
end)
