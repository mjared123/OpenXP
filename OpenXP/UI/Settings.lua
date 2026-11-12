-- The settings window: the card, the arrow, the maps and a few extras.
-- Every change is saved at once in OpenXPDB.settings and sent out as
-- SETTINGS_CHANGED so the card, arrow and maps follow it live.
local _, OXP = ...

local Settings = {}
OXP.Settings = Settings

local Style, L = OXP.Style, OXP.L
local C = Style.C

local f
local controls = {}

local function S() return OXP.settings end

local function Changed()
    OXP.Send("SETTINGS_CHANGED")
end

local function Section(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    fs:SetTextColor(unpack(C.blue))
    return y - 22
end

local function Check(parent, key, text, tip, y, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 14, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(text)
    label:SetTextColor(unpack(C.text))
    cb:SetScript("OnClick", function(self)
        S()[key] = self:GetChecked() and true or false
        if onChange then onChange() end
        Changed()
    end)
    if tip then
        cb:SetScript("OnEnter", function(self) Style.Tooltip(self, text, tip) end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    controls[#controls + 1] = function() cb:SetChecked(S()[key] ~= false and S()[key] ~= nil) end
    return y - 26
end

-- A value you step through with < and > buttons (no dropdown library needed).
local function Stepper(parent, text, y, values, get, set, show)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 20, y - 4)
    label:SetText(text)
    label:SetTextColor(unpack(C.text))
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("TOPRIGHT", -52, y - 4)
    value:SetJustifyH("RIGHT")
    value:SetTextColor(unpack(C.blue))
    local function Index()
        local v = get()
        for i, x in ipairs(values) do if x == v then return i end end
        return 1
    end
    local function Move(d)
        local i = Index() + d
        if i < 1 then i = #values elseif i > #values then i = 1 end
        set(values[i])
        Changed()
        value:SetText(show(values[i]))
    end
    local prev = Style.TextButton(parent, "<", nil, function() Move(-1) end)
    prev:SetWidth(22)
    prev:SetPoint("TOPRIGHT", -26, y)
    local nxt = Style.TextButton(parent, ">", nil, function() Move(1) end)
    nxt:SetWidth(22)
    nxt:SetPoint("TOPRIGHT", -2, y)
    value:SetPoint("RIGHT", prev, "LEFT", -6, 0)
    controls[#controls + 1] = function() value:SetText(show(get())) end
    return y - 26
end

local function Build()
    f = Style.Window("OpenXPSettings", 420, 560, L("OpenXP settings"))
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -48)
    scroll:SetPoint("BOTTOMRIGHT", -30, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(380, 10)
    scroll:SetScrollChild(content)

    local y = -4
    y = Section(content, L("Guide card"), y)
    y = Check(content, "cardShown", L("Show the guide card"), nil, y)
    y = Check(content, "lockFrames", L("Lock the card and arrow in place"), nil, y)
    local sizes = {}
    for i = 9, 20 do sizes[#sizes + 1] = i end
    y = Stepper(content, L("Text size"), y, sizes, function() return S().fontSize end,
        function(v) S().fontSize = v end, function(v) return tostring(v) end)
    local scales = { 0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.35, 1.5 }
    y = Stepper(content, L("Card size"), y, scales, function() return S().cardScale end,
        function(v) S().cardScale = v end, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
    local _, fontOrder = OXP.Fonts.Choices()
    y = Stepper(content, L("Font"), y, fontOrder, function() return S().font end,
        function(v) S().font = v; OXP.Fonts.Changed() end,
        function(v) local values = OXP.Fonts.Choices() return (values[v] or v):gsub(" %(.*", "") end)
    y = Stepper(content, L("Text outline"), y, { "", "OUTLINE", "THICKOUTLINE" }, function() return S().fontOutline end,
        function(v) S().fontOutline = v; OXP.Fonts.Changed() end,
        function(v) return v == "" and L("None") or v == "OUTLINE" and L("Thin") or L("Thick") end)
    y = Check(content, "autoNextGuide", L("Load the next guide when one is finished"), nil, y)
    y = Check(content, "smartStartOnLogin", L("Move me to the right section when I log in far past mine"), nil, y)

    y = y - 8
    y = Section(content, L("Arrow"), y)
    y = Check(content, "arrowShown", L("Show the arrow"), nil, y)
    y = Stepper(content, L("Arrow size"), y, scales, function() return S().arrowScale end,
        function(v) S().arrowScale = v end, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
    y = Stepper(content, L("Arrow text size"), y, sizes, function() return S().arrowText end,
        function(v) S().arrowText = v end, function(v) return tostring(v) end)
    y = Check(content, "travel", L("Plan trips to other zones (flights, boats, hearth)"), nil, y,
        function() OXP.Travel.Reset() end)

    y = y - 8
    y = Section(content, L("Maps"), y)
    y = Check(content, "mapRoute", L("Route line on the world map and minimap"), nil, y)
    y = Check(content, "mapAreas", L("Kill and loot areas"), L("Needs Questie for steps that don't name their own area."), y)
    y = Check(content, "mapPins", L("Numbered pins for the next steps, and area labels"), L("! where you pick a quest up, ? where you hand one in. Hover a pin to see the step."), y)
    y = Check(content, "mapMobs", L("Mob icons where the mobs you need spawn"), L("Skull: kill it. Bag: it drops what you need. A big skull and a name: a mob with only a spawn or two."), y)

    y = y - 8
    y = Section(content, L("Automation (hold Shift to pause)"), y)
    y = Check(content, "autoAccept", L("Accept the guide's quests"), L("Only quests the loaded guide picks up."), y)
    y = Check(content, "autoTurnIn", L("Turn in the guide's quests"), L("Only quests the loaded guide turns in, once they're complete."), y)
    y = Check(content, "autoTurnInAny", L("Turn in any completed quest, not just the guide's"),
        L("Quests the guide picked up but doesn't turn in, and quests you took yourself."), y)
    y = Check(content, "autoReward", L("Take the reward when there's no choice"), nil, y)
    y = Check(content, "autoBestReward", L("With a choice of rewards, take the one that sells for most"),
        L("Off: you pick the reward yourself when there's a choice."), y)
    y = Check(content, "skipGossip", L("Skip gossip: pick the guide's quest, or the only option"),
        L("Never picks the innkeeper's \"make this inn your home\"."), y)

    y = y - 8
    y = Section(content, L("Buttons and timers"), y)
    y = Check(content, "itemButton", L("Quest item button"), L("Bind a key: Key Bindings > AddOns > OpenXP. Shift-drag to move."), y,
        function() OXP.ActionButtons.Refresh() end)
    y = Check(content, "targetButton", L("Target button for the step's NPC or mob"), L("Bind a key: Key Bindings > AddOns > OpenXP."), y,
        function() OXP.ActionButtons.Refresh() end)
    y = Check(content, "flightTimer", L("Flight timer"), nil, y)
    y = Check(content, "hearthReminder", L("Say when the Hearthstone is ready on steps that use it"), nil, y)

    y = y - 8
    y = Section(content, L("Extras"), y)
    y = Check(content, "tooltips", L("Quest lines on item, mob and NPC tooltips"), nil, y)
    y = Check(content, "nameplates", L("Quest item icons on enemy nameplates"), nil, y)
    y = Check(content, "autoLoot", L("Auto loot"), nil, y, function() OXP.Tooltips.ApplyExtras(false) end)
    y = Check(content, "maxCamera", L("Zoom the camera out further"), nil, y, function() OXP.Tooltips.ApplyExtras(false) end)
    y = Check(content, "minimapShown", L("Minimap button"), nil, y, function() OXP.MinimapButton.Refresh() end)
    content:SetHeight(-y + 10)

    local reset = Style.DialogButton(f, L("Reset positions"), false, 140)
    reset:SetPoint("BOTTOMLEFT", 16, 12)
    reset:SetScript("OnClick", function()
        OXP.Card.ResetPosition()
        OXP.Arrow.ResetPosition()
    end)
    local close = Style.DialogButton(f, L("Done"), true, 120)
    close:SetPoint("BOTTOMRIGHT", -16, 12)
    close:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnShow", function() for _, update in ipairs(controls) do update() end end)
end

function Settings.Show()
    if not f then Build() end
    S().minimapShown = not (S().minimap and S().minimap.hide)
    f:Show()
end

function Settings.Toggle()
    if f and f:IsShown() then f:Hide() else Settings.Show() end
end

OXP.AddCommand("settings", "open the settings", Settings.Toggle)
OXP.AddCommand("options", nil, Settings.Toggle)
