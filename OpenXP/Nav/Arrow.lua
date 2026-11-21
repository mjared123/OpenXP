-- The arrow: where to point, how far, and whether you're there. How it
-- looks (styles, ring, text) is Nav/ArrowView.lua's job.
local ADDON, OXP = ...

local Arrow = {}
OXP.Arrow = Arrow

local Places = OXP.Places
local HBD = Places.HBD
local L = OXP.L

local ARRIVED = 8      -- yards: "Here"
local TICK = 0.05      -- seconds between redraws while shown

local f = CreateFrame("Button", "OpenXPArrow", UIParent)
Arrow.frame = f
f:SetSize(80, 80)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:Hide()

-- the look lives in Nav/ArrowView.lua; this file only works out where to point
local view = OXP.ArrowView.New(f)
Arrow.view = view
Arrow.ApplySizes = function() view.key = nil; view:Restyle() end

f:SetScript("OnDragStart", function(self)
    if OXP.settings.lockFrames then return end
    self:StartMoving()
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    OXP.settings.arrowPos = { point, rel, x, y }
end)
f:SetScript("OnEnter", function(self)
    local t = OXP.Target.Current()
    if not t then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(t.title or L("Next stop"), 1, 1, 1, 1, true)
    if t.real and t.real ~= t and t.real.title then
        GameTooltip:AddLine(L("On the way to: ") .. t.real.title, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(L("Drag to move. /oxp arrow hides or shows it."), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)

--- Angle (radians, like GetPlayerFacing) and yards from the player to t.
function Arrow.Vector(t)
    local px, py, inst = Places.Player()
    if not px or inst ~= t.instance then return nil end
    local angle, dist = HBD:GetWorldVector(inst, px, py, t.wx, t.wy)
    return angle, dist
end

local elapsed = 0
local LEAVE = ARRIVED + 5 -- yards: "Here" stays until you're this far off again
local TURN = 12           -- how fast the pointer swings to a new heading (per second)
local shownAngle, wasHere, lastReal
local pi2 = math.pi * 2

-- Swing the pointer toward `want` instead of snapping (the look-ahead point
-- on a walk moves on as you go, and a snap reads as a flicker).
local function Turn(want, dt)
    if not shownAngle then shownAngle = want return want end
    local diff = (want - shownAngle + math.pi) % pi2 - math.pi
    local k = math.min(1, (dt or TICK) * TURN)
    shownAngle = (shownAngle + diff * k) % pi2
    return shownAngle
end

local function Draw(dt)
    local t = OXP.Target.Update()
    if not t then
        view:Set(nil)
        shownAngle, wasHere, lastReal = nil, false, nil
        return
    end
    local angle, dist = Arrow.Vector(t)
    -- "Here" is about the real spot only, never a corner of the walk on the
    -- way, so the arrow doesn't flash "Here" and turn away again
    local real = t.focus or t.real or t
    if real ~= lastReal then wasHere, lastReal = false, real end
    local realDist = dist
    if real ~= t then
        local _, d = Arrow.Vector(real)
        realDist = d
    end
    local here = realDist and realDist <= (wasHere and LEAVE or ARRIVED) or false
    wasHere = here
    local label = t.title and OXP.Text.Strip(t.title) or ""
    local state
    if t.inside then
        state = { mode = "area", distance = L("In the area"), label = label }
        shownAngle = nil
    elseif here then
        state = { mode = "here", distance = L("Here"), label = label }
        shownAngle = nil
    elseif angle then
        local facing = GetPlayerFacing and GetPlayerFacing()
        -- along a walk: what's left of it, not the straight line to its next bend
        local yards = t.left or realDist or dist
        state = { mode = "point", angle = facing and Turn(angle - facing, dt) or nil,
                  distance = ("%d yd"):format(yards), yards = yards, label = label }
    else
        -- another continent and no plan to get there
        state = { mode = "lost", distance = "...", label = label }
    end
    view:Set(state)
    Arrow.lastDistance, Arrow.lastHere = realDist or dist, here or t.inside or false
    Arrow.lastState = state
end
Arrow.Draw = OXP.Perf.Wrap("arrow", Draw)

f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < TICK then return end
    local spent = elapsed
    elapsed = 0
    Arrow.Draw(spent)
end)

function Arrow.Refresh()
    local s = OXP.settings
    local show = (s.arrowShown and OXP.Engine.GetGuide() ~= nil) or OXP.PathHints.go ~= nil
    if show then
        f:Show()
        Arrow.Draw()
    else
        f:Hide()
    end
end

function Arrow.Toggle()
    OXP.settings.arrowShown = not OXP.settings.arrowShown
    Arrow.Refresh()
end

function Arrow.ResetPosition()
    OXP.settings.arrowPos = nil
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
end

OXP.OnReady(function()
    local pos = OXP.settings.arrowPos
    if pos then
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    Arrow.Refresh()
end)
for _, m in ipairs({ "GUIDE_LOADED", "ARROW_CHANGED", "SETTINGS_CHANGED" }) do
    OXP.Listen(m, function() Arrow.Refresh() end)
end

OXP.AddCommand("arrow", "hide or show the arrow", function() Arrow.Toggle() end)
