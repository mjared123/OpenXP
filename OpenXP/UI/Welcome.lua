-- The welcome / what's new window: shown the first time OpenXP loads on an
-- account and once after each update. /oxp welcome opens it again.
local _, OXP = ...

local Welcome = {}
OXP.Welcome = Welcome

local Style, L = OXP.Style, OXP.L
local C = Style.C
local BLUE = "|cFF5AB8FF"

-- Newest first.
Welcome.CHANGELOG = {
    {
        version = "2.0.0-dev", date = "2026-11",
        changes = {
            "OpenXP 2.0 test build: a new engine and a new home for every part of OpenXP, written by OpenXP's own contributors.",
            "Guides from level 1 to 60 and the dungeons for both factions. Levels 1-20 are adapted from PoleStar's guides (GPL-3.0), with every class quest up to level 20 for every race.",
            "The guide card, arrow, smart start, route line, kill areas, travel planner, tooltips and settings all run on the new engine.",
            "Flight paths come from the game's own data; flight masters only WoW Forever has are learned when you open their flight map.",
            "Quest item and target buttons you can bind to keys; auto accept and gossip skipping for the guide's quests, and auto turn-in for any completed quest (hold Shift to pause).",
            "A flight timer, and the card tells you when your Hearthstone is ready on steps that use it.",
            "Class quests from level 20 to 54 are in the 21-60 guides, for your class only.",
            "OpenXP now has its own quest data (from the open forever-db), so chain checks, quest names and kill areas work without Questie.",
            "Settings and progress are saved fresh for 2.0 and don't touch your 1.x settings.",
        },
    },
}

local f

local function Body(mode, lastSeen)
    local lines = {}
    if mode == "welcome" then
        lines[#lines + 1] = BLUE .. L("Welcome, adventurer!") .. "|r"
        lines[#lines + 1] = ""
        lines[#lines + 1] = L("OpenXP is a free, community-made leveling guide for WoW Forever. Follow the arrow and the steps, and it takes you from quest to quest by the fastest route.")
        lines[#lines + 1] = ""
        lines[#lines + 1] = BLUE .. "•|r  " .. L("Already leveling? Find my place works out where you are from your level, zone and quests.")
        lines[#lines + 1] = BLUE .. "•|r  " .. L("Right-click the guide card or the minimap button for the menu.")
        lines[#lines + 1] = BLUE .. "•|r  " .. L("/oxp lists every command.")
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = BLUE .. L("What's new") .. "|r"
    for _, entry in ipairs(Welcome.CHANGELOG) do
        if lastSeen and entry.version == lastSeen then break end
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("%s%s %s|r  |cFF9EA0B2%s|r"):format(BLUE, L("Version"), entry.version, entry.date)
        for _, change in ipairs(entry.changes) do lines[#lines + 1] = BLUE .. "•|r  " .. change end
    end
    return table.concat(lines, "\n")
end

local function Build()
    f = Style.Window("OpenXPWelcome", 480, 460, "OpenXP " .. tostring(OXP.version))
    f.logo:SetTexture(Style.LOGO_BIG)
    local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 16, -50)
    panel:SetPoint("BOTTOMRIGHT", -16, 90)
    Style.Backdrop(panel, C.panel, C.line)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 10)
    scroll:SetScrollChild(content)
    f.body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT")
    f.body:SetWidth(400)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetSpacing(3)
    f.body:SetTextColor(unpack(C.text))
    f.content = content

    f.questie = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.questie:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 4, -8)
    f.questie:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.questie:SetJustifyH("LEFT")

    -- With no guide loaded (a new install or character) this picks one for
    -- you. With a guide already loaded it only closes the window and shows
    -- the card: an update never moves you off the step you were on (Find my
    -- place / /oxp where still re-place you on purpose).
    local start = Style.DialogButton(f, L("Start leveling"), true)
    start:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 14)
    start:SetScript("OnClick", function()
        f:Hide()
        if OXP.Engine.GetGuide() then
            if not OXP.settings.cardShown then OXP.Card.Toggle() end
        else
            OXP.SmartStart.Run(false)
        end
    end)
    f.start = start
    local later = Style.DialogButton(f, L("Close"), false)
    later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 14)
    later:SetScript("OnClick", function() f:Hide() end)
end

--- mode: "welcome" (first run) or "update"; lastSeen: the version seen last.
function Welcome.Show(mode, lastSeen)
    if not f then Build() end
    f.body:SetText(Body(mode or "welcome", lastSeen))
    f.content:SetHeight(f.body:GetStringHeight() + 10)
    f.start.label:SetText(OXP.Engine.GetGuide() and L("Continue leveling") or L("Start leveling"))
    if _G.QuestieLoader then
        f.questie:SetText(BLUE .. L("Questie is installed.") .. "|r " .. L("OpenXP adds its spawn marks for the mobs you need."))
    else
        f.questie:SetText(BLUE .. L("Questie is optional.") .. "|r " .. L("OpenXP has its own quest data; with Questie it can also mark every spawn of the mobs you need."))
    end
    f:Show()
end

OXP.OnReady(function()
    local seen = OXP.db.welcomeSeen
    if seen == OXP.version then return end
    OXP.db.welcomeSeen = OXP.version
    C_Timer.After(3, function() Welcome.Show(seen and "update" or "welcome", seen) end)
end)

OXP.AddCommand("welcome", "show the welcome and what's new window", function() Welcome.Show("update") end)
