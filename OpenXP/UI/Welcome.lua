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
        version = "2.0.0-dev7", date = "2026-11",
        changes = {
            "The arrow and the route line on the map and minimap no longer send you back to a waypoint you've passed. Once you've done what a waypoint was for (picked up the quest from across the room, turned it in, killed or looted what it asked), they go straight on to the next thing still to do, also after a /reload. A waypoint you still need stays until it's done.",
            "The card's header is clean again: the zone and levels line up with the step, and \"Step 13 / 116\" with a list icon opens the step list (it lights up in your skin's colour under the mouse). The bottom bar's menu button has three dots, and its first row is All steps.",
            "\"Finish it\", \"Get the quest\" and the other step buttons wear your skin's colour; Skip stays quiet. No more \"You haven't finished\" warning on the step that does the quest's objectives.",
            "The map and minimap look and work like Questie's: the same icon sizes (smaller on continent and world maps), a coloured glow per objective, every spawn marked (no merged pins or name labels), and objectives on the minimap too, waiting on its rim and fading with distance.",
            "The game's own round \"?\" and \"...\" quest markers are hidden while OpenXP's quest icons show, like Questie does (Settings > Maps > Hide Blizzard's quest markers).",
            "Map tooltips follow Questie's layout: everything under the mouse in one tooltip, (Available) and (Complete) tags, objective progress, Shift for more. Click a pin to open its map, or with the chat box open to link the quest.",
            "New map settings: minimap icons, their size and fade distance, icons on continent maps, objective glow and colours.",
        },
    },
    {
        version = "2.0.0-dev6", date = "2026-11",
        changes = {
            "The card shows just your step: the earlier-steps history (scrolling up on the card) and Up next are gone, and the step gets the room. The step list shows every other step.",
            "A real Steps button on the card: a list icon and \"Steps\" on a pill in your skin's colour, brighter under the mouse and while the list is open. \"Step 16 / 52\" opens it too. Also /oxp steps.",
            "The right-click menu closes when you click anywhere outside it (and on Escape).",
        },
    },
    {
        version = "2.0.0-dev5", date = "2026-11",
        changes = {
            "The old 1.x 21-60 guides (\"OpenXP Legacy\" in Pick a guide) are gone: the leveling route covers 1-60. A character that was on one is placed on the route by smart start, flight paths kept. About 1.3 MB less to load.",
            "The quest item button shows for every \"Use <item>\" line while the item is in your bags and what it's for is still open (the Earth Sapta in Call of Earth never got a button).",
            "Quests in a chain with the same name say which part they are: \"Accept Call of Earth (part 2)\". A line repeated in a step shows once. Checked over every guide: all 1,060 later-part lines get their part, and same-name quests that aren't one chain don't.",
            "\"More\" on the card has its own row under the step text and no longer covers the last line.",
        },
    },
    {
        version = "2.0.0-dev4", date = "2026-11",
        changes = {
            "Fly steps are done as you take off, and the arrow and map line move straight on to the next step (they kept pointing at the flight master until you landed).",
            "Auto-flight: on a \"fly to\" step, talking to a flight master takes that flight for you and says where in chat. Hold Shift while you talk to choose yourself; Settings > Automation > Fly to the step's flight master.",
            "Travel steps (boats, flights, roads into a zone) are only done when you are there now or have clearly gone past, never because you have been there before or know the flight path.",
            "A relog or /reload keeps you on the step you were on. Smart start only places a new character, or when you pick a guide.",
            "Step list: closing it no longer leaves a dark box beside the card, it wears the card's skin (background slider, Minimal, fonts), and jumping ahead marks the steps you jump over as skipped, not done. Going back changes nothing.",
            "The card shows a step's text once (no faded copy under the title).",
            "Settings: the scrollbar lets go when you release the mouse anywhere, and a Reset to defaults button (it asks first; your guide progress stays).",
            "Quest trackers: Blizzard's and Questie's quest trackers are hidden while you use OpenXP (Settings > Extras > Show quest tracker brings them back, as you had them).",
            "The quest item button: cooldown spiral, item count, your key, red when out of range, in your skin, and only while its objective is open.",
            "Targets list and target key: only the mobs of objectives still open for quests in your log, and the people the step still needs, nearest first.",
            "Nameplates: enemies are marked only for quests in your log with that objective open (not quests the guide picks up later). No second ! or ? over quest givers (the game shows its own) and no step numbers unless you turn them on (Settings > Extras).",
            "One icon set everywhere: plain silver map icons (sword, sack, cog, speech bubble, skull) with the yellow ! and ?, no circles, on the map, minimap, card and nameplates.",
            "A cleaner map: a thinner route line with a soft outline (Settings > Maps > Line width), kill areas only for the step you are on (soft fill, name on hover, no duplicates), mob pins only for objectives still open, close spawns merged into one pin with a count, a gentler glow, and step numbers only for this step and the next (all with Settings > Maps toggles).",
        },
    },
    {
        version = "2.0.0-dev3", date = "2026-11",
        changes = {
            "A step list on the card: click the clock button (or \"Step 12 / 80\") to see every step of the guide on a timeline: what you've done, skipped or missed, the step you're on and what's coming. Click any step to go there. Tabs for All, Earlier and Coming up. Also /oxp steps.",
            "Up next can be folded to one line (click UP NEXT) or hidden (Settings > Guide card > Up next).",
            "A Background slider under Settings > Guide card: from the skin's own background down to none at all, for the card and the Targets list.",
            "Skins reworked: each one now colours every OpenXP window, button and line, not just the card. Minimal has no background, border or lines at all: just the text (outlined), icons and buttons.",
            "A new arrow: pick Chevron, Classic, Needle, Solid triangle or Dot and pointer, and turn the circle, the distance and the step text on or off. Its colour follows your skin, or white, or red when far turning green as you get close. Arrow size and opacity too. It glows when you arrive.",
            "Map quest icons: a yellow ! where you pick a quest up (grey when it's low level for you), a yellow ? where you hand one in (grey until it's done), and kill, loot and use icons on objectives. Hover for the quest, its level and your progress. With Questie installed ours step aside so you don't see two of each (Settings > Maps > Quest icons).",
            "Fixed: a quest's ! stayed on the map after you picked the quest up.",
            "A new install starts with a slightly see-through card, a little bigger, and the new arrow. Your own settings aren't changed.",
        },
    },
    {
        version = "2.0.0-dev2", date = "2026-11",
        changes = {
            "The card starts unlocked and shown, and this What's New window opens after every update.",
            "Going through a tunnel or path into a new zone (like Talondeep Path into Stonetalon) now counts once you're out in that zone.",
            "The target button only targets mobs you still need, and nameplates stop marking mobs you've finished. It's now a movable Targets list with each mob's portrait: click a row to target that mob, or use your key for the nearest one. Shift-drag the quest item button to move it.",
            "Sharper map and minimap pins, quest icons and route line, with direction arrows along the route.",
            "The card's guide title has its own line, so it never runs into the level range or step count.",
            "Right-click opens the menu where you clicked.",
            "Pick a guide: a tab for each type of guide, and a scrollbar you can drag or click.",
            "Skins under Settings > Guide card: Midnight, Minimal (see-through), Glass, Classic gold, Ember and Forest.",
            "Less memory and smoother frames: only your faction's guides load, map data is let go when you leave a zone, and the minimap route does less work. /oxp mem shows how much memory OpenXP uses.",
        },
    },
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
