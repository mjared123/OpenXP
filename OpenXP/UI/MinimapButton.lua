-- OpenXP's minimap button: left-click shows or hides the guide card (and
-- loads a guide when there is none), right-click opens the menu, drag moves
-- it around the minimap's edge.
local _, OXP = ...

local MB = {}
OXP.MinimapButton = MB

local Style, L = OXP.Style, OXP.L

local b = CreateFrame("Button", "OpenXPMinimapButton", Minimap)
MB.button = b
b:SetSize(31, 31)
b:SetFrameStrata("MEDIUM")
b:SetFrameLevel(8)
b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
b:RegisterForDrag("LeftButton")
b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
b.bg = b:CreateTexture(nil, "BACKGROUND")
b.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
b.bg:SetSize(20, 20)
b.bg:SetPoint("CENTER")
b.icon = b:CreateTexture(nil, "ARTWORK")
b.icon:SetTexture(Style.LOGO)
b.icon:SetSize(20, 20)
b.icon:SetPoint("CENTER")
b.border = b:CreateTexture(nil, "OVERLAY")
b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
b.border:SetSize(53, 53)
b.border:SetPoint("TOPLEFT")
b:Hide()

local function Place()
    local angle = math.rad(OXP.settings.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        OXP.settings.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        Place()
    end)
end)
b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        OXP.GuidePicker.Toggle(self)
    elseif not OXP.Engine.GetGuide() then
        OXP.SmartStart.Run(false)
        OXP.settings.cardShown = true
        OXP.Card.Refresh(true)
    else
        OXP.Card.Toggle()
    end
end)
b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("OpenXP", 1, 1, 1)
    local g = OXP.Engine.GetGuide()
    if g then
        local done, total = OXP.Engine.GetProgress()
        GameTooltip:AddLine(("%s  (%d/%d)"):format(g.name, done, total), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(L("Left-click: show or hide the guide"), 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L("Right-click: menu"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
b:SetScript("OnLeave", function() GameTooltip:Hide() end)

function MB.Refresh()
    local s = OXP.settings
    if s.minimapShown ~= nil then s.minimap.hide = not s.minimapShown end
    if s.minimap.hide then
        b:Hide()
    else
        Place()
        b:Show()
    end
end

OXP.OnReady(MB.Refresh)
OXP.AddCommand("minimap", "hide or show the minimap button", function()
    OXP.settings.minimap.hide = not OXP.settings.minimap.hide
    OXP.settings.minimapShown = not OXP.settings.minimap.hide
    MB.Refresh()
end)
