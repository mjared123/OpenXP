# Questie map and minimap parity

Players asked for OpenXP's world map and minimap to look and behave like
Questie's, so it feels familiar. This page lists what Questie's map layer has
and what OpenXP does about each feature. Each Questie item gives a file:line
in the installed Questie v12.12.0 (`Questie_Forever.toc`), read only.

OpenXP's map layer is `OpenXP/Nav/Pins.lua` for the pins and
`OpenXP/Nav/MapDraw.lua` for drawn lines and areas. Questie's code is GPL-3
and the logic below was adapted with credit (`OpenXP/NOTICE.md`). Questie's
icon art is all rights reserved, so none of it is used: the icons are
OpenXP's own (`tools/make_icons.py`, `tools/make_objective_icons.py`).

OpenXP marks only the guide's quests: the current and next step, plus the
current step's open objectives. It does not mark every quest in the zone.

## The round "?" and "..." markers in Coldridge Valley

The client draws them, not OpenXP. WoW Forever has Blizzard's quest
objective markers, switched by the CVar `questPOI`. Evidence:

- **Questie's own first-run chooser** says "With WoW Forever Blizzard introduced their own quest objective system" (`Modules/Tutorial/ChooseObjectiveType.lua:53`).
- **Questie's "Questie" icon theme** calls `SetCVar("questPOI", "0")`, and its "Blizzard" theme sets it to "1" (`Modules/Options/NativeOptions/NativeOptionsIcons.lua:1158-1201`).
- **The login quirk:** with questPOI 0 the client opens the world map at log in, and Questie closes it again (`Modules/EventHandler/EventHandler.lua:79-90`).
- **OpenXP never touched that CVar.** It has no "?" or "..." on a dark disc. Its numbered badges are dark discs, but they carry step numbers.

On this PC only Babyturtle-Soup's config-cache has `SET questPOI "0"`, left over from Questie. The other characters use the default, so the markers show.

The "Snow Leopard Prowler" label was OpenXP's: the old big skull badge with a name, for a mob with three spawns or fewer. Questie has no labels, so dev7 removes it.

**dev7:** while OpenXP's quest icons show, OpenXP sets questPOI to "0" and keeps the old value per character, then puts it back when its icons go off. This is Settings > Maps > Hide Blizzard's quest markers, on by default like Questie's default theme. When Questie is loaded, Questie decides.

## Inventory

In the OpenXP column, "has" means it was already there, "dev7" means it was added in 2.0.0-dev7, and "not added" gives the reason.

| Feature | Questie (default, where) | OpenXP |
|---|---|---|
| Available "!" | type AVAILABLE; grey "!" for trivial or not-yet-level (`QuestieLib.lua:885-904`) | has: guide pick-ups only, grey "!" when trivial |
| Repeatable / event / PvP "!" | own icons (`QuestieLib.lua:885-904`) | not added: the guides don't mark these kinds |
| Turn-in "?" | COMPLETE, shown only when the quest is done (`QuestieQuest.lua:578-597`, `QuestFinisher.lua:187-196`) | has: yellow "?" when complete |
| In-progress turn-in | not drawn: INCOMPLETE is never placed on the map | kept, OpenXP extra: grey "?" for the guide's next hand-in, tagged "(Not done yet)" |
| Objective icons slay / loot / object / talk | per-objective type icon (`QuestieQuestPrivates.lua:14-26`) | has, own art (sword, sack, cog, bubble); the skull badge and name label are gone in dev7 |
| Icon size | 16 × type scale × global scale. Available and turn-in 1.2, objectives 1, event 1.35. Map 0.6, minimap 0.7 (`QuestieOptionsDefaults.lua:12-34`, `QuestieMapUtils.lua:126-130`) | dev7: the same numbers. "!"/"?" are 11.52 px on the map and 13.44 on the minimap; objectives are 9.6 and 11.2. Map and minimap size sliders multiply these |
| Smaller on continent and world maps | ×0.9 continent, ×0.85 world or cosmic (`QuestieMap.lua:255-269`), re-applied on map change (`HBDHooks.lua:40-47`) | dev7: the same, applied whenever HBD refreshes the map |
| Zoom scaling | HBD pins `SetScalingLimits(1, 1.0, 1.2)` | has: same HBD |
| Draw order | fixed frame levels: objectives 2020, available 2021, repeatable 2022, turn-ins 2024 (`QuestieMapUtils.lua:11-72`) | dev7: objectives 2020, "!" 2021, step badges 2022, "?" 2024, area spots 2016; levels fixed so re-parenting keeps them |
| Objective glow | a glow 1.13× the icon, in the objective's colour from a 16-colour wheel; `alwaysGlowMap` and `alwaysGlowMinimap` on (`QuestieFrame.lua:265-293`, `QuestieLib.lua:188-219`) | dev7: own soft-disc art at 1.13×, own 16-colour palette, one colour per objective. Settings > Maps > Objective glow |
| Tinted objective icons | `questObjectiveColors` off (`QuestieOptionsDefaults.lua:62`) | dev7: Colour objective icons, off |
| Objective spawn filter | spawns sorted from the zone middle (or the nearest giver across zones); one is kept only if ≥ `objectiveFilterDistance` 2 from every kept spawn, with x weighted 1.5 (`QuestieQuest.lua:1055-1097`, `QuestieLib.lua:872-881`) | dev7: the same filter (across zones, nearest to the player first). This replaces the old merged pins with counts. At most 400 pins, nearest first (Questie's limit is 1500) |
| Clustering into one pin with a count | none | removed in dev7 (was an OpenXP extra) |
| Completed objectives | their icons are removed at once (`QuestieQuest.lua:1046-1048`) | has |
| Focus-fade other quests (tracker focus) | `iconFadeLevel` 0.3 (`TrackerUtils.lua:621-629`) | not added: OpenXP shows only the current step's quests |
| Tooltip anchor | `ANCHOR_CURSOR`, none while the icon is at alpha 0 (`MapIconTooltip.lua:101-124`) | dev7: the same |
| Tooltip grouping | every pin on the same map within 1 map unit (zone map), 4 (continent) or 6 (world); on the minimap 0.5 / (1 + zoom) outdoors and 0.3 indoors (`MapIconTooltip.lua:126-146`) | dev7: the same radii |
| Tooltip: givers | giver name in green with "(Hold Shift)" in grey on the right. Then its quests by level, "[lvl] Name" in difficulty colour and a yellow tag such as "(Available)" or "(Complete)". Shift adds rewards, description and chain (`MapIconTooltip.lua:318-560`) | dev7: the same layout and tags, plus OpenXP's "(Not done yet)" with the missing objectives. Shift shows the guide step. Rewards and description are not added: not in OpenXP's quest data |
| Tooltip: objectives | the quest title, then "have/need text" lines (EEEEEE). Shift lists the NPC names, then the objective indented. Same text merged (`MapIconTooltip.lua:500-527`, `:705-829`) | dev7: the same, Shift shows NPC names and the guide step |
| Tooltip refresh on Shift | `MODIFIER_STATE_CHANGED` (`EventHandler.lua:107`) | dev7 |
| Hover highlight of the same quest's icons | tinted white (`MapIconTooltip.lua:189-201`) | not added: there are few objectives at once, and each has its own glow colour |
| Left-click on the world map | opens the icon's map when another is shown (`QuestieFrame.lua:216-257`) | dev7 |
| Click with the chat box open | inserts the quest link | dev7 (minimap, or any click with a modifier) |
| Shift-click "!" to hide the quest | confirmation popup | not added: the guide decides which quests to take (use Skip on the card) |
| Ctrl-click TomTom waypoint | toggles a waypoint | not added: OpenXP's arrow already points at the step; route and arrow code are out of scope |
| Right-click | passes through to the map (zoom out), via `SetPassThroughButtons` (`QuestieFrame.lua:193-207`) | dev7: the same, retried after combat |
| Objective-area polygons | none; Questie draws NPC patrol lines only (`QuestieMap.lua:747-751`, `Waypoints/*`) | OpenXP extra: kill and loot areas (Settings > Maps > Kill and loot areas) |
| NPC patrol path lines | `waypointMapEnabled` / `waypointMinimapEnabled` on (`QuestieOptionsDefaults.lua:16-27`) | not added: OpenXP's quest data has spawn points, not patrol paths |
| Minimap icons | all quest icons, `floatOnEdge` (`QuestieMap.lua:619-716`) | dev7: all objective icons too, floating on the rim (before, only the skull badges and step pins). Settings > Maps > Minimap icons |
| Minimap distance fade | past `fadeLevel` 20 (×10 yd) icons fade out over 100 yd; below 50 yd they fade to `fadeOverPlayerLevel` 0.5 (`QuestieMap.lua:761-803`) | dev7: the same formula, every 0.1 s. Settings > Maps > Minimap fade distance and Fade icons under you. The current step's pin stays, so the destination is always on the rim |
| Faded icons | alpha 0: not on the rim and no tooltip (Questie patched HBD) | dev7: alpha 0, no mouse and no tooltip; HBD itself is not changed |
| Minimap button "!" | LibDBIcon. Left: Journey; Shift-left: options; Ctrl-Shift-left: toggle icons (`MinimapIcon.lua:175-233`) | has its own (UI/MinimapButton.lua: card / menu); no icon toggle added |
| World map button | Krowi button: toggles all icons (`WorldMapButton.lua:63-70`) | not added: needs Krowi_WorldMapButtons; the Settings > Maps toggles cover it |
| Toggles | `enableMapIcons`, `enableMiniMapIcons`, `enableAvailable`, `enableTurnins`, `enableObjectives`, `hideIconsOnContinents` false, `hideUnexploredMapIcons` false (`QuestieOptionsDefaults.lua:64-85, 145-171`) | has: Step pins, Objective icons, Quest icons (Auto / Always / Off). dev7: Minimap icons, Icons on continent maps |
| Low-level filter | `lowLevelStyle` 1: trivial quests are hidden (`IsLevelRequirementFulfilled.lua:21-80`) | not added: a guide pick-up is always shown, grey when trivial |
| Repeatable / dungeon / PvP / event filters | all on (`QuestieOptionsDefaults.lua:167-171`) | not added: not relevant to guide pins |
| Keybinds | none for icons (Bindings.xml has Journey and tracker only) | nothing to match |
| Slash commands | `/questie toggle` toggles icons; `tomap` adds manual icons (`QuestieSlash.lua:93-160`) | not added (Settings > Maps) |
| Blizzard quest markers | the Questie theme sets questPOI 0 and closes the map the client opens at log in | dev7 (see above) |
| "Auto: hide ours when Questie is loaded" | n/a | has, kept: with Questie loaded and Quest icons on Auto, OpenXP's "!", "?" and objective icons step aside, and Questie owns questPOI |
