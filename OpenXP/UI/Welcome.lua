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
        version = "2.0.4", date = "2026-11",
        changes = {
            "Sell junk is back: at a vendor, OpenXP sells your grey items (never quest items or items the guide still needs). Settings > Automation > Sell junk.",
            "Hiding the guide with the minimap button (or /oxp card) now hides the arrow and the targets list too.",
            "New setting: Group quests (Settings > Guides). Off: elite group quests are never shown, even once you have one.",
            "New: distance under the arrow in meters (Settings > Arrow and travel > Distance in).",
            "New: Point straight at the spot (Settings > Arrow and travel): a straight line instead of following the walking path.",
            "The flight you need is circled on the flight master's map, including the first flight of Getting there.",
            "As a ghost, the arrow now leads you back to your corpse (Settings > Arrow and travel > Point at my corpse).",
            "Fixed item lookups on WoW Forever's client: the quest item button finds quest items in all your bags again (including a fifth bag).",
            "New: /oxp junk shows which grey items Sell junk would sell, and why it keeps the others.",
        },
    },
    {
        version = "2.0.3", date = "2026-11",
        changes = {
            "Fixed high CPU use and stutter in busy places like cities (from 2.0.2): the quest item button no longer refreshes every time the game loads another player's gear.",
        },
    },
    {
        version = "2.0.2", date = "2026-11",
        changes = {
            "/ginvite and other protected slash commands work again with OpenXP on.",
            "The quest tracker (Blizzard's and Questie's) is shown again by default, and Questie's tracker stays the way you set it. Hide them in Settings > Extras.",
            "Your 1.x quest, gossip, flight timer, targets and minimap button settings now come over too. Auto-flight is off by default (turn it on in Settings > Automation).",
            "Class quests now sit in the guide where you reach their level, instead of all at the start of the chain (no more level 36 quests in Hillsbrad at 29).",
            "The arrow plans trips again (flights, boats, hearth) when no walking path leads to the next zone.",
            "The quest item button finds quest items in your bags, updates as soon as the game knows the item, and keeps your 1.x key binding.",
            "Stormwind's flight master is marked in the right place. Horde Stranglethorn: the Bloodsail fight is on the second Booty Bay stop. Alliance Wetlands: no early Fiora Longears pickup.",
            "Settings: 'Target button' is now 'Targets list'. Quest chains pick the quest meant for your class. No more errors from units whose names the game hides.",
        },
    },
    {
        version = "2.0.1", date = "2026-11",
        changes = {
            "Map icons for Forever's new quests: loot piles, objects and mobs for about 220 quest objectives that had no icons before (Spoils of War's timber and iron in Menethil Harbor, for one).",
            "The route line no longer takes a long detour where no walking path was made for a leg (Whelgar's Excavation Site in the Wetlands went round by Thelgen Rock): it joins the walking path to that spot instead.",
            "The card's icons (the step list button, the buttons along the bottom and the step marks) now grow with Settings > Text size, and the step list button is as big as the others.",
            "/oxp feedback has a new Support OpenXP section with a link to the Patreon. OpenXP stays free, and every feature is for everyone.",
        },
    },
    {
        version = "2.0.0", date = "2026-11",
        changes = {
            "OpenXP 2.0: a rebuilt addon with a new engine, a new guide card and a new arrow. No RestedXP code or guides are left; OpenXP is now GPL-3.0.",
            "One leveling route from 1 to 60 for every race and both factions, adapted from PoleStar's guides, with your class quests merged in where you reach their level.",
            "Coming from 1.x: your card, font, arrow, map and automation settings, flight paths and dungeon guide progress come with you. The 1.x 21-60 guides are gone, so a character that was leveling is placed on the new route from its quest log (Find my place moves you again any time).",
            "Want to finish a character on the old route? OpenXP 1.3.66 stays under Files on CurseForge. Your 1.x settings and progress are kept, so going back finds them as you left them.",
            "A new guide card that keeps its size, with skins (Midnight, Minimal, Glass, Classic, Ember, Forest), a background slider and a step list to see and jump between steps.",
            "A new arrow (five styles) that follows walking paths when OpenXP Navigation is turned on, and never points back at a waypoint you've passed.",
            "Map and minimap quest icons and objective pins that work like Questie's, a Targets list with portraits, and a quest item button you can bind to a key.",
            "OpenXP has its own quest data, so it works without Questie. With Questie installed it also marks every spawn of the mobs you need.",
            "English only for now: translations come back in a later update.",
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
    Style.TextColor(f.body, C.text)
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
    -- a new version starts with the card on screen
    OXP.settings.cardShown = true
    C_Timer.After(3, function() Welcome.Show(seen and "update" or "welcome", seen) end)
end)

OXP.AddCommand("welcome", "show the welcome and what's new window", function() Welcome.Show("update") end)
