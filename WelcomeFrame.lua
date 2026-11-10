-- OpenXP welcome / what's new window
--
-- Shown the first time OpenXP loads on an account, and once after every
-- update, with the changes in that version. /oxp welcome opens it again.

local addonName, addon = ...

-- The version comes from the .toc (## Version), so it is only set in one place.
-- OpenXP is in beta, so versions look like 1.1.5-beta.
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
local OPENXP_VERSION = (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) or "dev"
addon.openxpVersion = OPENXP_VERSION

-- Newest first. Each entry: version, date, list of changes.
local CHANGELOG = {
    {
        version = "1.3.11",
        date = "November 2026",
        changes = {
            "New installs start right away: the guide card and arrow show up on login with the right guide for your race and level, no clicks or settings needed",
            "Clicking the minimap button before a guide is loaded now loads one instead of doing nothing",
            "This What's new window now also shows after you update and /reload, not only after restarting the game",
            "Fixed two file names that could stop parts of OpenXP loading on a Mac",
        },
    },
    {
        version = "1.3.10",
        date = "November 2026",
        changes = {
            "Duskwood steps rebuilt with walking distances around the mountains: quests are picked up before the areas they share (Eight-Legged Menaces before the wolves), objectives use the densest spot on your way, and Darkshire's quests are all grabbed before you leave",
            "About 7% less walking and much less time near mobs well above your level in 21-24 Duskwood, with the same quests",
        },
    },
    {
        version = "1.3.9",
        date = "November 2026",
        changes = {
            "Arrow walks around mountains, cliffs and rivers in Duskwood instead of pointing straight into them (more zones to come)",
            "Arrow steers around packs of mobs 3 or more levels above you, like the Brightwood worgen at level 22, and takes the direct way again once you've outleveled them",
        },
    },
    {
        version = "1.3.8",
        date = "November 2026",
        changes = {
            "New Feedback window: report a bug, suggest something, leave a comment or rate OpenXP. Open it with /oxp feedback or \"Feedback and bugs\" in the right-click menu",
            "The bug report link fills in your OpenXP version, guide and step for you, and \"Full bug details\" has everything else to paste in",
        },
    },
    {
        version = "1.3.7",
        date = "November 2026",
        changes = {
            "Guide picker is one click shorter: the level brackets (Levels 20-29, 30-39 ...) sit right in your faction's menu next to the 1-20 guides",
        },
    },
    {
        version = "1.3.6-beta",
        date = "November 2026",
        changes = {
            "The guide picker no longer runs off the screen: long guide lists (like OpenXP 21-60) are split into Levels 20-29, 30-39, 40-49 and 50-59, so every guide can be clicked",
        },
    },
    {
        version = "1.3.5-beta",
        date = "November 2026",
        changes = {
            "Fixed a Lua error when walking through a quest chain (\"attempt to index field 'step'\")",
            "Level-up announcements no longer try to /emote when you're solo: WoW Forever blocks addons from doing that",
        },
    },
    {
        version = "1.3.4-beta",
        date = "November 2026",
        changes = {
            "The arrow knows the way from Ashenvale into Stonetalon Mountains: through the Talondeep Path tunnel, instead of straight at the mountains on the border",
            "New /oxp path to <zone> (or /oxp path to <x> <y> on your map): the arrow leads you there, through any tunnels and passes it knows, then goes back to the guide. For example /oxp path to Stonetalon",
        },
    },
    {
        version = "1.3.3-beta",
        date = "November 2026",
        changes = {
            "Put back a few WoW Forever quests that 1.3.2 wrongly left out with the Season of Discovery ones (their quest givers have new NPC ids like Season of Discovery's). Alliance 21-60 has 498 quests, Horde 22-60 has 444",
        },
    },
    {
        version = "1.3.2-beta",
        date = "November 2026",
        changes = {
            "Removed Season of Discovery quests that aren't in WoW Forever from the 21-60 routes, like Alonso's Dragonslayer quests in Ashenvale and the scroll and book quests. They came in through Questie's data",
            "Routes rebuilt without them: Alliance 21-60 has 492 quests, Horde 22-60 has 444",
        },
    },
    {
        version = "1.3.1-beta",
        date = "November 2026",
        changes = {
            "The arrow now walks you around caves and cliffs. When a quest is inside a cave or up on a ridge, it first points at the entrance or the bottom of the ramp (\"Enter Jasperlode Mine\"), then at the quest. Leaving a cave works the same way",
            "OpenXP learns cave entrances by itself: walk into a cave once and the arrow uses that entrance from then on",
            "New /oxp path command: stand at a ramp, pass or cave mouth and type /oxp path add to save it as a stepping stone toward the arrow's target, then /oxp path done. /oxp path off turns all of this off",
        },
    },
    {
        version = "1.3.0-beta",
        date = "November 2026",
        changes = {
            "New 21-60 routes for both factions (WoW Forever). The route builder now plays the route in its head: it tracks your level as you go, picks the next zone by the most XP per minute, and comes back to zones as their higher quests open up, like the well-known leveling routes do",
            "Quests join the route only once they're at most 2 levels above you, quests above your level count as slower, and gray quests are left out",
            "About 60% more quests: Alliance 21-60 has 505 turn-ins (was 318), Horde 22-60 has 427 (was 221). New stops include the Swamp of Sorrows, Blasted Lands, Alterac, the Barrens and quick capital-city stops for chain quests",
            "Section names now show the levels you'll really be at. When the next quests are a bit high, a step tells you to kill mobs on the way or run a dungeon that fits your level",
        },
    },
    {
        version = "1.2.3-beta",
        date = "November 2026",
        changes = {
            "The 21-60 guides no longer send you to quests far above your level. A quest now has to be at most 2 levels above where its section ends (for example, the 21-23 Ashenvale section no longer has the level 27 Raene's Cleansing)",
            "The 40-60 guides were rebuilt with WoW Forever's quests included, like 21-40 were in 1.2.0",
        },
    },
    {
        version = "1.2.2-beta",
        date = "November 2026",
        changes = {
            "Hearth steps now check where your Hearthstone is set. If it's somewhere else (say you missed a \"set your Hearthstone\" step earlier), the step says so in red, with a heads-up in chat and on screen, so you know to travel there another way and skip the step",
        },
    },
    {
        version = "1.2.1-beta",
        date = "November 2026",
        changes = {
            "New section for Shen'dralas, Forever's new zone south of Desolace (Alliance 39-40, Horde 38-39). It's short for now: it has the quests whose givers are known so far, and will grow as more of the zone is mapped",
            "The arrow now knows the Shen'dralas, Riverglades and Darkspear Islands maps",
        },
    },
    {
        version = "1.2.0-beta",
        date = "November 2026",
        changes = {
            "Levels 21-40 guides rebuilt with WoW Forever's own quests included (from Questie). About 50 more quests across Wetlands, Duskwood, Stranglethorn, Desolace, Hillsbrad and Badlands, nothing taken out",
        },
    },
    {
        version = "1.1.9-beta",
        date = "November 2026",
        changes = {
            "New for guide makers: /oxp questdump saves what your installed Questie knows about quests (including WoW Forever's new quests) so the guide tools can find quests the guides are missing. It stays on your PC",
        },
    },
    {
        version = "1.1.8-beta",
        date = "November 2026",
        changes = {
            "The quest loot icon on enemy nameplates now sits centred above the enemy's name, bigger and with an outlined count, instead of hiding behind the level",
        },
    },
    {
        version = "1.1.7-beta",
        date = "November 2026",
        changes = {
            "Quest items stand out more: a QUEST ITEM - DON'T SELL banner with a quest icon, an orange tooltip border, and a quest marker on the bag slot",
            "Enemy tooltips now list the quest items they drop that you still need, with the item's icon and your count, even with Questie installed and even for quests you'll pick up later (like Gooey Spider Legs from spiders)",
            "Enemies that drop an item you need show its icon and your count beside their nameplate (turn it off under Extras: Quest loot on nameplates)",
        },
    },
    {
        version = "1.1.6-beta",
        date = "November 2026",
        changes = {
            "Bag items a quest needs now say so on their tooltip, with the quest and how many you have (like Gooey Spider Legs 2/6), so you don't sell them. This includes items the guide tells you to save for a quest you'll pick up later",
            "Enemy tooltips now show your progress on item drops they give (like Gooey Spider Legs from spiders), not just kills",
            "If Questie is installed with its tooltips turned off, OpenXP shows the quest progress on enemies instead",
        },
    },
    {
        version = "1.1.5-beta",
        date = "November 2026",
        changes = {
            "OpenXP is in beta testing, so version numbers now end in -beta",
            "The version shown on the guide footer and this window now matches the installed version (it was stuck on 0.9.9)",
        },
    },
    {
        version = "1.1.4",
        date = "November 2026",
        changes = {
            "Skipped quest chains now lists every quest you skipped or whose chain was missed in your current guide, with its step number and what it needs first. Before, it only remembered the last Find my place and forgot it on reload",
        },
    },
    {
        version = "1.1.3",
        date = "November 2026",
        changes = {
            "\"Go here\" steps (like heading up a ramp) count as done once you've run past them towards the next stop, so the arrow no longer sends you back",
        },
    },
    {
        version = "1.1.2",
        date = "November 2026",
        changes = {
            "Each step on the card shows its step number under the icon",
            "Trainer steps (class and pet) are done as soon as you talk to the trainer. You don't have to train everything, and a visit earlier at the same level counts too",
        },
    },
    {
        version = "1.1.1",
        date = "November 2026",
        changes = {
            "Fixed a Lua error when starting a quest chain walk-through (Do the chain, Get the quest)",
        },
    },
    {
        version = "1.1.0",
        date = "November 2026",
        changes = {
            "Scroll the mouse wheel up over the guide card to see earlier steps. Each one is tagged Done, Skipped or Chain missed. Click a step to go back to it",
            "Going back to a step now stays there, even if that step is already done. Press Next or Back to step N to carry on",
            "Next marks a step you didn't finish as Skipped",
            "The step list (click the step counter) shows the same tags",
            "New Quest Targets list in the card's style: a row per mob or NPC with its portrait, name and key binding",
            "Two new key bindings: Target a quest mob and Target a quest NPC (Key Bindings > OpenXP)",
            "Removed files for other WoW versions (Retail, TBC, Wrath, Cata, MoP, SoD) and unused guides and textures",
        },
    },
    {
        version = "1.0.0",
        date = "November 2026",
        changes = {
            "Horde routes from 22 to 60, so both factions now go 1 to 60",
            "Classic Era: 21 to 60 routes for Alliance and Horde",
            "Dungeon guides for both factions: pick up the dungeon quests, run it, turn them in",
            "Tooltips: mobs show which of your quests they count for and your progress, NPCs show the guide step that needs them",
            "Click the step counter on the card to see every step and jump to any of them",
            "Flight timers now show under the card",
            "Map and minimap pins show the ! and ? quest icons next to the step number",
            "Gold XP line along the bottom of the card. Hover it for XP per hour and time to level",
            "New options: auto loot and max camera distance (both off until you turn them on). Sell junk is on by default",
            "The card only redraws when something changes, and the download is smaller",
            "If Questie isn't installed you get a one-time tip about what it adds",
        },
    },
    {
        version = "0.9.9",
        date = "November 2026",
        changes = {
            "Your place in each guide is saved on the character, including steps you skipped ahead to, and kept through reloads and relogs",
            "Fixed the back button bouncing you forward again",
            "Party and guild announcements (level ups, quest progress, flight times) are on by default",
        },
    },
    {
        version = "0.9.8",
        date = "November 2026",
        changes = {
            "The guide card can go narrower still (down to 200)",
            "Active Targets, the quest item bar and Level splits now match the guide card's look",
        },
    },
    {
        version = "0.9.7",
        date = "November 2026",
        changes = {
            "The guide card can be made about 25% narrower; buttons slim down and wrap to fit",
        },
    },
    {
        version = "0.9.6",
        date = "November 2026",
        changes = {
            "Turn in steps for a quest you have but haven't finished now say so, list what's left, and offer Finish it or Skip this step",
            "Finish it walks you through the objectives with the arrow, then brings you back to turn it in",
        },
    },
    {
        version = "0.9.5",
        date = "November 2026",
        changes = {
            "Fixed steps for quests that aren't in your quest log (like Mathystra Relics) being treated as if you had them. The guide now checks the quest log itself",
        },
    },
    {
        version = "0.9.4",
        date = "November 2026",
        changes = {
            "If the guide card hits an error it now says so in chat instead of silently not updating",
        },
    },
    {
        version = "0.9.3",
        date = "November 2026",
        changes = {
            "The step you're on is always at the top of the card",
            "Background steps (like looting an item while you do other things) are labelled Along the way and dimmed",
            "Finished steps are marked Done and faded",
            "Pickup steps say You get this quest at this step",
        },
    },
    {
        version = "0.9.2",
        date = "November 2026",
        changes = {
            "New /oxp step command: prints what the guide card sees for the steps on screen, for bug reports",
            "Questie lookups work with both ways Questie exposes its quest data",
        },
    },
    {
        version = "0.9.1",
        date = "November 2026",
        changes = {
            "Quest chain info now comes from Questie while you play, so install Questie to get chains, levels and Do the chain. It stays current whenever Questie updates",
            "Without Questie, every step still checks your quest log and offers Skip this step or Get the quest",
        },
    },
    {
        version = "0.9.0",
        date = "November 2026",
        changes = {
            "Every step now checks your quest log. A step for a quest you don't have says so, with Skip this step or Get the quest",
            "Quest chains: when a step needs earlier quests, the card lists them with their levels and offers Do the chain",
            "Do the chain walks you through each earlier quest (pick up, objectives, turn in) with the arrow, then drops you back into the guide",
            "Pickup steps are no longer skipped behind your back; you choose",
        },
    },
    {
        version = "0.8.3",
        date = "November 2026",
        changes = {
            "Pickup steps for quests you can't get yet (you skipped the quest before it) are skipped automatically, like the Beached Sea Creature quests if you never did Washed Ashore",
        },
    },
    {
        version = "0.8.2",
        date = "November 2026",
        changes = {
            "Steps for a quest you don't have now say so, with buttons to skip the step or go back and get the quest. Once you have it, the guide brings you back",
        },
    },
    {
        version = "0.8.1",
        date = "November 2026",
        changes = {
            "Guide font size now changes right away, no reload needed",
        },
    },
    {
        version = "0.8.0",
        date = "November 2026",
        changes = {
            "Resize the guide card: drag the grip in its bottom right corner. A taller card shows more of the route under Up next",
            "Settings cleaned up: options that did nothing with the new card are gone",
            "Window scale, arrow scale, arrow text size and Lock frames now apply to the new card and arrow right away",
            "New Reset Guide Window button in settings puts the card back to its starting spot and size",
        },
    },
    {
        version = "0.7.0",
        date = "November 2026",
        changes = {
            "Brand new guide window: a compact card with a badge for each step, check marks, kill and loot bars and an Up next line",
            "Buttons on the card: back, skip, Find my place, guides menu, settings and collapse to one line",
            "New arrow: a pointer in a round dial with the distance in big text, and a green check when you arrive",
            "Drag the card anywhere; right-click it for the guides menu",
        },
    },
    {
        version = "0.6.0",
        date = "November 2026",
        changes = {
            "New minimal look by default: flat dark panels, thin borders, a clean font and OpenXP blue highlights",
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
        if addon.smartStart and addon.smartStart.HasGuide and not addon.smartStart.HasGuide() then
            addon.smartStart.EnsureGuide()
        elseif addon.smartStart and level > 1 then
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
