-- OpenXP welcome / what's new window
--
-- Shown the first time OpenXP loads on an account, and once after every
-- update, with the changes in that version. /oxp welcome opens it again.

local addonName, addon = ...

local OPENXP_VERSION = "0.6.0"
addon.openxpVersion = OPENXP_VERSION

-- Newest first. Each entry: version, date, list of changes.
local CHANGELOG = {
    {
        version = "0.6.0",
        date = "November 2026",
        changes = {
            "New minimal look by default: flat dark panels, thin borders, a clean font and OpenXP blue highlights",
            "Prefer the old style? Pick OpenXP Gold or RestedXP Classic under Settings > Look and Feel > Choose Theme",
            "This window has the new look too",
        },
    },
    {
        version = "0.5.0",
        date = "November 2026",
        changes = {
            "Bigger, easier to read guide text and arrow distance",
            "The step you're on now has a gold bar, and finished steps fade back",
            "Progress bar along the bottom of the guide window: Step 12 of 148",
            "Right-click the guide window for Find my place, Skipped quest chains and What's new, no commands needed",
            "The same buttons are at the top of the OpenXP settings",
            "Removed the guide menus OpenXP doesn't use (dungeon, mage, survival and endgame lists)",
        },
    },
    {
        version = "0.4.0",
        date = "November 2026",
        changes = {
            "Alliance guides now go all the way to 60",
            "30-40: Hillsbrad and Alterac, Arathi, Stranglethorn, Dustwallow, Thousand Needles and Desolace",
            "40-50: Badlands, Tanaris, Feralas, Hinterlands, Searing Gorge and Azshara",
            "50-60: Un'Goro, Felwood, Winterspring, Burning Steppes, the Plaguelands and Silithus",
            "21-30 now gives you the Redridge quests if you didn't pick them up earlier",
        },
    },
    {
        version = "0.3.0",
        date = "November 2026",
        changes = {
            "New Alliance 21-30 route: Ashenvale, Stonetalon, Wetlands, Redridge and Duskwood",
            "The 20-21 guides now carry straight on into 21-30, for Hunters too",
            "Smart start knows the new sections, so it can place you anywhere from 1 to 30",
        },
    },
    {
        version = "0.2.0",
        date = "November 2026",
        changes = {
            "New OpenXP look: navy and gold guide window, gold borders and a glowing guide arrow",
            "New OpenXP icon in the AddOns list, minimap button and guide window",
            "Smart start: OpenXP finds your place in the guide from your level, zone and quests",
            "Skipped a section? Quest chains you can't start anymore are skipped for you",
            "This welcome window, which also shows what's new after each update",
        },
    },
    {
        version = "0.1.0",
        date = "November 2026",
        changes = {
            "First release: free leveling guides for WoW Forever",
            "Alliance 1-21 for every starting race, with class quests built in",
        },
    },
}

-- Same palette as the minimal guide window theme. "gold" is the accent
-- (OpenXP blue) and "goldDark" the hairline border; names kept for history.
local COLORS = {
    bg = {16 / 255, 17 / 255, 21 / 255, 0.96},
    panel = {22 / 255, 24 / 255, 29 / 255, 0.9},
    gold = {90 / 255, 184 / 255, 255 / 255},
    goldDark = {60 / 255, 66 / 255, 78 / 255},
    blue = {90 / 255, 184 / 255, 255 / 255},
    text = {0.86, 0.86, 0.9},
    muted = {0.6, 0.62, 0.7},
}

local GOLD_HEX = "|cFF5AB8FF"
local BLUE_HEX = "|cFF5AB8FF"
local LOGO = "Interface/AddOns/" .. addonName .. "/Textures/openxp_logo-128"

local frame

local function Backdrop(f, bg, border)
    f:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(border))
end

local function MakeButton(parent, text, primary)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(150, 30)
    Backdrop(b, primary and {28 / 255, 70 / 255, 104 / 255, 1} or COLORS.panel,
             primary and COLORS.gold or COLORS.goldDark)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(unpack(primary and {1, 1, 1} or COLORS.text))
    b.label = label
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 0.8)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(primary and COLORS.gold or COLORS.goldDark))
    end)
    return b
end

local function BuildBody(mode, lastSeen)
    local lines = {}
    if mode == "welcome" then
        table.insert(lines, GOLD_HEX .. "Welcome, adventurer!|r")
        table.insert(lines, "")
        table.insert(lines, "OpenXP is a free, community-made leveling guide for WoW Forever. " ..
            "Follow the arrow and the steps, and it takes you from quest to quest by the fastest route.")
        table.insert(lines, "")
        table.insert(lines, BLUE_HEX .. "•|r  Already leveling? Smart start finds where you are from your level, zone and quests.")
        table.insert(lines, BLUE_HEX .. "•|r  " .. GOLD_HEX .. "Right-click the guide window|r for Find my place, Skipped quest chains and What's new.")
        table.insert(lines, BLUE_HEX .. "•|r  The same buttons are at the top of the settings (" .. GOLD_HEX .. "/oxp|r or the minimap button).")
    else
        table.insert(lines, GOLD_HEX .. "What's new|r")
        for _, entry in ipairs(CHANGELOG) do
            if lastSeen and entry.version == lastSeen then break end
            table.insert(lines, "")
            table.insert(lines, string.format("%sVersion %s|r  |cFF9EA0B2%s|r", BLUE_HEX, entry.version, entry.date))
            for _, change in ipairs(entry.changes) do
                table.insert(lines, BLUE_HEX .. "•|r  " .. change)
            end
        end
    end
    return table.concat(lines, "\n")
end

local function CreateWelcomeFrame()
    local f = CreateFrame("Frame", "OpenXPWelcomeFrame", UIParent, "BackdropTemplate")
    f:SetSize(480, 420)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Backdrop(f, COLORS.bg, COLORS.gold)
    tinsert(_G.UISpecialFrames, "OpenXPWelcomeFrame") -- Escape closes it

    -- Header band
    local header = f:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4, -4)
    header:SetHeight(110)
    header:SetColorTexture(1, 1, 1, 0.03)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.6)

    -- Glowing logo
    local glow = f:CreateTexture(nil, "ARTWORK")
    glow:SetTexture("Interface/Cooldown/star4")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(COLORS.blue[1], COLORS.blue[2], COLORS.blue[3], 0.35)
    glow:SetSize(150, 150)
    glow:SetPoint("LEFT", f, "TOPLEFT", -8, -58)

    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.35)
    a:SetToAlpha(0.9)
    a:SetDuration(1.6)
    a:SetSmoothing("IN_OUT")
    pulse:Play()

    local logo = f:CreateTexture(nil, "OVERLAY")
    logo:SetTexture(LOGO)
    logo:SetSize(84, 84)
    logo:SetPoint("CENTER", glow, "CENTER")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 128, -30)
    title:SetText("OpenXP")
    title:SetTextColor(1, 1, 1)
    title:SetShadowOffset(2, -2)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("Free leveling guides for WoW Forever")
    subtitle:SetTextColor(unpack(COLORS.text))

    local badge = CreateFrame("Frame", nil, f, "BackdropTemplate")
    badge:SetSize(70, 20)
    badge:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    Backdrop(badge, {16 / 255, 40 / 255, 70 / 255, 1}, COLORS.blue)
    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeText:SetPoint("CENTER")
    badgeText:SetText("v" .. OPENXP_VERSION)
    badgeText:SetTextColor(unpack(COLORS.blue))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Scrolling body
    local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -128)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 58)
    Backdrop(panel, COLORS.panel, COLORS.goldDark)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 10)
    scroll:SetScrollChild(content)

    local body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT")
    body:SetWidth(400)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(3)
    body:SetTextColor(unpack(COLORS.text))
    f.body, f.content = body, content

    -- Buttons
    local start = MakeButton(f, "Start leveling", true)
    start:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
    start:SetScript("OnClick", function()
        f:Hide()
        local level = UnitLevel("player") or 1
        if addon.smartStart and level > 1 then
            addon.smartStart.Run()
        elseif addon.SelectDefaultGuide then
            addon.SelectDefaultGuide()
        end
    end)

    local later = MakeButton(f, "Close", false)
    later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
    later:SetScript("OnClick", function() f:Hide() end)

    -- Fade in
    local fade = f:CreateAnimationGroup()
    local fa = fade:CreateAnimation("Alpha")
    fa:SetFromAlpha(0)
    fa:SetToAlpha(1)
    fa:SetDuration(0.35)
    f:SetScript("OnShow", function()
        fade:Play()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then
            PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN)
        end
    end)

    f:Hide()
    return f
end

local welcome = {}
addon.welcome = welcome
welcome.changelog = CHANGELOG

-- mode: "welcome" (first run) or "update"; lastSeen: version the player saw last
function welcome.Show(mode, lastSeen)
    frame = frame or CreateWelcomeFrame()
    frame.body:SetText(BuildBody(mode or "welcome", lastSeen))
    frame.content:SetHeight(frame.body:GetStringHeight() + 10)
    frame:Show()
end

-- Decide whether to show on login. Returns the mode shown, or nil.
function welcome.CheckOnLogin()
    if not OXPData then return end
    local lastSeen = OXPData.openxpLastSeenVersion
    local mode
    if not lastSeen then
        mode = "welcome"
    elseif lastSeen ~= OPENXP_VERSION then
        mode = "update"
    end
    OXPData.openxpLastSeenVersion = OPENXP_VERSION
    -- 0.5.0 made the guide text bigger. Testers who still have the old
    -- small default get the new one once; a size they picked is kept.
    local profile = addon.settings and addon.settings.profile
    if mode == "update" and profile and lastSeen < "0.5.0" then
        local changed
        if profile.guideFontSize == 9 then profile.guideFontSize = 12; changed = true end
        if profile.arrowText == 9 then profile.arrowText = 12 end
        if changed and addon.UpdateGuideFontSize then addon.UpdateGuideFontSize() end
        if changed and addon.ReloadGuide and addon.currentGuide then addon:ReloadGuide(true) end
    end
    if mode then welcome.Show(mode, lastSeen) end
    return mode
end
