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
    local count = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    if count and count(HEARTHSTONE) == 0 then return nil end
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
bar:SetClampedToScreen(true)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetStatusBarColor(C.blue[1], C.blue[2], C.blue[3], 0.8)
bar.bg = bar:CreateTexture(nil, "BACKGROUND")
bar.bg:SetAllPoints()
bar.bg:SetColorTexture(0, 0, 0, 0.6)
bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bar.text:SetPoint("CENTER")
bar:Hide()

-- Where the bar goes: under the guide card (as in 1.x), or where you
-- Shift-dragged it (CurseForge 2026-11-25: 2.0 pinned it to the top of the
-- screen with no way to move it). Settings > Buttons and timers puts it
-- back under the card.
function Timers.PlaceBar()
    bar:ClearAllPoints()
    local s = OXP.settings or {}
    local pos = s.flightTimerDocked == false and s.flightTimerPos
    local card = OXP.Card and OXP.Card.frame
    if type(pos) == "table" and pos[1] then
        bar:SetWidth(240)
        bar:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    elseif card and card:IsShown() then
        bar:SetWidth(math.max(160, card:GetWidth() or 240))
        bar:SetPoint("TOP", card, "BOTTOM", 0, -6)
    else
        bar:SetWidth(240)
        bar:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

bar:SetMovable(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:SetScript("OnDragStart", function(self)
    if OXP.settings.lockFrames or not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    self:StartMoving()
end)
bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    OXP.settings.flightTimerPos = { point, rel, x, y }
    OXP.settings.flightTimerDocked = false
    OXP.Send("SETTINGS_CHANGED")
end)
bar:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L("Flight timer"))
    if not OXP.settings.lockFrames then GameTooltip:AddLine(L("Shift-drag to move it."), 0.6, 0.6, 0.6) end
    GameTooltip:AddLine(L("Settings > Buttons and timers puts it back under the card."), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

local preview = 0
--- Show the bar for a few seconds so you can see and move it (Settings).
function Timers.Preview()
    preview = (GetTime and GetTime() or 0) + 15
    Timers.PlaceBar()
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.6)
    bar.text:SetText(L("Flight timer") .. "  " .. L("Shift-drag to move it."))
    bar:Show()
end

local flight -- { from, to, start, estimate }

local function FlightKey(from, to) return (from or "?") .. ">" .. (to or "?") end

local function NodeIdByName(name)
    for id, n in pairs(OXP.flightData and OXP.flightData.nodes or {}) do
        if n.name == name then return id end
    end
end

-- One leg: what you flew before, else the game's own time.
local function LegTime(from, to)
    local db = OXP.db and OXP.db.flightTimes
    local known = db and db[FlightKey(from, to)]
    if known then return known end
    local a, b = NodeIdByName(from), NodeIdByName(to)
    local times = OXP.flightData and OXP.flightData.times
    return a and b and times and times[a] and times[a][b] or nil
end

-- A flight with stops on the way, when the taxi map didn't say which: the
-- quickest chain of single flights between the two (on your faction's
-- flight masters), which is the way the game flies.
function Timers.ChainEstimate(a, b)
    local data = OXP.flightData
    if not (data and data.times and a and b) then return nil end
    local mine = OXP.Player and OXP.Player.faction
    mine = mine and mine:sub(1, 1)
    local function ok(id)
        local n = data.nodes[id]
        return n and (not mine or n.faction == "B" or n.faction == mine)
    end
    local dist, done = { [a] = 0 }, {}
    while true do
        local cur, best
        for id, d in pairs(dist) do
            if not done[id] and (not best or d < best) then cur, best = id, d end
        end
        if not cur then return nil end
        if cur == b then return best end
        done[cur] = true
        for nb, secs in pairs(data.times[cur] or {}) do
            if (nb == b or ok(nb)) and not done[nb] and (not dist[nb] or best + secs < dist[nb]) then
                dist[nb] = best + secs
            end
        end
    end
end

--- Seconds a flight from `from` to `to` (flight master names) takes.
--- `stops`: the flight masters it lands at on the way, in order, ending
--- with `to` (from the taxi map), when known.
function Timers.FlightEstimate(from, to, stops)
    local db = OXP.db and OXP.db.flightTimes
    local known = db and db[FlightKey(from, to)]
    if known then return known end
    local a, b = NodeIdByName(from), NodeIdByName(to)
    local times = OXP.flightData and OXP.flightData.times
    local t = a and b and times and times[a] and times[a][b]
    if t then return t end
    -- with stops: add up the legs (2.0.0-2.0.6 guessed these from the
    -- straight line, minutes short: CurseForge 2026-11-25)
    if type(stops) == "table" and #stops > 1 and stops[#stops] == to then
        local sum, prev = 0, from
        for _, name in ipairs(stops) do
            local leg = LegTime(prev, name)
            if not leg then sum = nil break end
            sum, prev = sum + leg, name
        end
        if sum then return sum end
    end
    t = Timers.ChainEstimate(a, b)
    if t then return t end
    local na, nb = a and OXP.flightData.nodes[a], b and OXP.flightData.nodes[b]
    if na and nb and na.inst == nb.inst then
        return OXP.Places.Distance(na.wx, na.wy, nb.wx, nb.wy) / 30 + 15
    end
end

--- Call when a flight starts (tests call it directly).
function Timers.StartFlight(from, to, stops)
    flight = { from = from, to = to, start = Now(), estimate = Timers.FlightEstimate(from, to, stops) }
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
        -- the flight masters it stops at on the way
        local stops
        if GetNumRoutes and TaxiGetNodeSlot then
            pcall(function()
                local n = GetNumRoutes(index) or 0
                if n > 1 then
                    stops = {}
                    for hop = 1, n do
                        local slot = TaxiGetNodeSlot(index, hop, true)
                        stops[#stops + 1] = slot and TaxiNodeName(slot) or "?"
                    end
                end
            end)
        end
        Timers.StartFlight(from, TaxiNodeName(index), stops)
    end)
end

local onTaxi, wait = false, 0
bar:SetScript("OnUpdate", function(self, elapsed)
    wait = wait + elapsed
    if wait < 0.2 then return end
    wait = 0
    if not flight then
        if preview > 0 and (GetTime and GetTime() or 0) < preview then return end
        preview = 0
        self:Hide()
        return
    end
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
    if now and not onTaxi and flight and OXP.settings.flightTimer ~= false then
        Timers.PlaceBar()
        bar:Show()
    end
    if onTaxi and not now then Timers.EndFlight() end
    onTaxi = now
end)
