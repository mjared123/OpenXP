-- Pins on the world map and minimap for the shown steps' waypoints: the
-- next one bright, the rest of the step's waypoints dimmer.
local ADDON, OXP = ...

local Pins = {}
OXP.Pins = Pins

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local Engine, Places = OXP.Engine, OXP.Places

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Card\\filledcircle"
local BLUE = { 90 / 255, 184 / 255, 1 }

local pool, used = {}, 0

local function Pin(i)
    local p = pool[i]
    if p then return p end
    p = CreateFrame("Frame", nil, UIParent)
    p:SetSize(14, 14)
    p.tex = p:CreateTexture(nil, "OVERLAY")
    p.tex:SetAllPoints()
    p.tex:SetTexture(ICON)
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        if not self.title then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.title, 1, 1, 1, 1, true)
        if self.pos then GameTooltip:AddLine(OXP.L("Step") .. " " .. self.pos, 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- the minimap needs its own frame
    p.mini = CreateFrame("Frame", nil, UIParent)
    p.mini:SetSize(10, 10)
    p.mini.tex = p.mini:CreateTexture(nil, "OVERLAY")
    p.mini.tex:SetAllPoints()
    p.mini.tex:SetTexture(ICON)
    pool[i] = p
    return p
end

function Pins.Clear()
    HBDPins:RemoveAllWorldMapIcons(Pins)
    HBDPins:RemoveAllMinimapIcons(Pins)
    used = 0
end

function Pins.Refresh()
    Pins.Clear()
    if OXP.settings.mapPins == false or not Engine.GetGuide() then return end
    local real = OXP.Target.Real()
    for _, pos in ipairs(Engine.GetActive()) do
        local step = Engine.GetSteps()[pos]
        local title = OXP.Target.StepTitle(step)
        for _, g in ipairs(step.goals) do
            if g[1] == "goto" then
                local s = Places.Spot(g)
                if s then
                    used = used + 1
                    local p = Pin(used)
                    local next = real and real.wx == s.wx and real.wy == s.wy
                    local a = next and 1 or 0.55
                    p.tex:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], a)
                    p.mini.tex:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], a)
                    p.title, p.pos = title, pos
                    HBDPins:AddWorldMapIconWorld(Pins, p, s.instance, s.wx, s.wy, 3) -- 3: show on zone and continent maps
                    HBDPins:AddMinimapIconWorld(Pins, p.mini, s.instance, s.wx, s.wy, true)
                end
            end
        end
    end
end

local function Soon() OXP.Soon("PINS", Pins.Refresh) end
for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "SETTINGS_CHANGED" }) do
    OXP.Listen(m, Soon)
end
