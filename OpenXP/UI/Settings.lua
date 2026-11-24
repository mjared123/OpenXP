-- The settings window: categories down the left, one page each on the
-- right. Every row says what it does in one line, and every change is
-- saved at once in OpenXPDB.settings and sent out as SETTINGS_CHANGED, so
-- the card, arrow and maps (and the preview on the Guide card page)
-- follow it live.
local _, OXP = ...

local Settings = {}
OXP.Settings = Settings

local Style, L = OXP.Style, OXP.L
local C, S = Style.C, Style.S

local WIDTH, HEIGHT, SIDEBAR = 780, 560, 184
local f
local controls = {}   -- every control's Update, run when the window opens
local pages, navs = {}, {}

local function DB() return OXP.settings end

local function Changed()
    OXP.Send("SETTINGS_CHANGED")
end

---------------------------------------------------------------------------
-- Page building blocks
---------------------------------------------------------------------------

-- A page is a scroll area; rows go down it from `page.y`.
local function Heading(page, text)
    local fs = Style.Text(page.content, 11, C.faint)
    fs:SetPoint("TOPLEFT", S.xl, -page.y - 14)
    fs:SetText(text:upper())
    page.y = page.y + 34
end

local function Row(page, label, desc, control, controlWidth)
    local row = CreateFrame("Frame", nil, page.content)
    row:SetPoint("TOPLEFT", 0, -page.y)
    row:SetPoint("RIGHT", page.content, "RIGHT", 0, 0)
    row.label = Style.Text(row, 13, C.text)
    row.label:SetPoint("TOPLEFT", S.xl, -10)
    row.label:SetPoint("RIGHT", row, "RIGHT", -(controlWidth + S.xl + S.lg), 0)
    row.label:SetText(label)
    local h = 44
    if desc then
        row.desc = Style.Text(row, 11, C.dim)
        row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
        row.desc:SetPoint("RIGHT", row, "RIGHT", -(controlWidth + S.xl + S.lg), 0)
        row.desc:SetWordWrap(true)
        row.desc:SetText(desc)
        local width = WIDTH - SIDEBAR - controlWidth - S.xl * 2 - S.lg - 12
        row.desc:SetWidth(width)
        h = 10 + (row.label:GetStringHeight() or 14) + 3 + (row.desc:GetStringHeight() or 13) + 10
    end
    h = math.max(h, 44)
    row:SetHeight(h)
    row.line = Style.Divider(row)
    row.line:SetPoint("BOTTOMLEFT", S.xl, 0)
    row.line:SetPoint("BOTTOMRIGHT", -S.xl, 0)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    Style.Fill(row.hl, { 1, 1, 1 }, 0)
    if control then
        control:SetParent(row)
        control:ClearAllPoints()
        control:SetPoint("RIGHT", row, "RIGHT", -S.xl, 0)
        controls[#controls + 1] = function() if control.Update then control:Update() end end
    end
    page.y = page.y + h
    page.rows[#page.rows + 1] = row
    return row
end

local function Toggle(page, key, label, desc, onChange)
    local t = Style.Toggle(page.content, function() local v = DB()[key] return v ~= false and v ~= nil end,
        function(v)
            DB()[key] = v
            if onChange then onChange(v) end
            Changed()
        end)
    t.key = key
    page.toggles[key] = t
    return Row(page, label, desc, t, 36)
end

local function Slider(page, key, label, desc, min, max, step, show, onChange)
    local s = Style.Slider(page.content, 220, {
        min = min, max = max, step = step,
        get = function() return DB()[key] or min end,
        set = function(v)
            DB()[key] = v
            if onChange then onChange(v) end
            Changed()
        end,
        format = show,
    })
    page.sliders[key] = s
    return Row(page, label, desc, s, 220)
end

local function Dropdown(page, key, label, desc, choices, default, onChange)
    local d = Style.Dropdown(page.content, 200, choices, function() return DB()[key] or default end, function(v)
        DB()[key] = v
        if onChange then onChange(v) end
        Changed()
    end)
    page.dropdowns[key] = d
    return Row(page, label, desc, d, 200)
end

local function ButtonRow(page, label, desc, text, onClick)
    local b = Style.Button(page.content, text, "secondary", 160, onClick)
    return Row(page, label, desc, b, 160)
end

local function Pct(v) return math.floor(v * 100 + 0.5) .. "%" end

---------------------------------------------------------------------------
-- Live preview of the card (Guide card page)
---------------------------------------------------------------------------

local function Preview(page)
    local box = CreateFrame("Frame", nil, page.content, "BackdropTemplate")
    box:SetPoint("TOPLEFT", S.xl, -page.y - 8)
    box:SetPoint("RIGHT", page.content, "RIGHT", -S.xl, 0)
    box:SetHeight(150)
    Style.Backdrop(box, { 0, 0, 0, 0.25 }, C.line)
    if box.SetClipsChildren then box:SetClipsChildren(true) end
    local tag = Style.Text(box, 10, C.faint)
    tag:SetPoint("TOPLEFT", 10, -8)
    tag:SetText(L("PREVIEW"))

    local card = CreateFrame("Frame", nil, box, "BackdropTemplate")
    card:SetSize(300, 112)
    card:SetPoint("TOP", box, "TOP", 0, -24)
    Style.Backdrop(card, C.bg, C.border, { card = true })
    card.zone = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.zone:SetPoint("TOPLEFT", 12, -9)
    card.step = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.step:SetPoint("TOPRIGHT", -12, -9)
    card.line = Style.Divider(card, false, { 1, 1, 1, 0.08 })
    card.line:SetPoint("TOPLEFT", 1, -28)
    card.line:SetPoint("TOPRIGHT", -1, -28)
    card.badge = Style.Badge(card, 30)
    card.badge:SetPoint("TOPLEFT", 12, -38)
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.title:SetPoint("TOPLEFT", card.badge, "TOPRIGHT", 12, -1)
    card.title:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    card.title:SetJustifyH("LEFT")
    card.title:SetWordWrap(false)
    card.obj = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.obj:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    card.obj:SetJustifyH("LEFT")
    card.barBg = card:CreateTexture(nil, "ARTWORK")
    card.barBg:SetPoint("TOPLEFT", card.obj, "BOTTOMLEFT", 0, -5)
    card.barBg:SetSize(170, 5)
    card.barBg:SetColorTexture(1, 1, 1, 0.1)
    card.bar = card:CreateTexture(nil, "OVERLAY")
    card.bar:SetPoint("LEFT", card.barBg, "LEFT")
    card.bar:SetSize(85, 5)
    card.bar:SetColorTexture(C.orange[1], C.orange[2], C.orange[3], 1)
    function card:Update()
        Style.PaintBackdrop(self)
        self.line:SetColorTexture(1, 1, 1, Style.Frameless() and 0 or Style.skin.line + 0.01)
        Style.SetFont(self.zone, -1)
        Style.SetFont(self.step, -1)
        Style.SetFont(self.title, 3)
        Style.SetFont(self.obj, 1)
        self.zone:SetText(L("ELWYNN FOREST") .. "  |cFF9EA3B31–11|r")
        Style.TextColor(self.zone, C.text)
        self.step:SetText(L("Step 4 / 82"))
        Style.TextColor(self.step, C.dim)
        self.badge:SetKind("kill")
        self.title:SetText(L("Kill Kobold Vermin"))
        Style.TextColor(self.title, C.text)
        self.obj:SetText(L("Kobold Vermin slain: 4/8"))
        Style.TextColor(self.obj, C.text)
        self:SetScale(math.min(DB().cardScale or 1, 1.15))
    end
    page.preview = card
    controls[#controls + 1] = function() card:Update() end
    OXP.Listen("SETTINGS_CHANGED", function() if f and f:IsShown() then card:Update() end end)
    -- the fonts load a moment later the first time they're used
    OXP.Listen("SETTINGS_CHANGED", function()
        if C_Timer and C_Timer.After then C_Timer.After(0.2, function() if f and f:IsShown() then card:Update() end end) end
    end)
    card:Update()
    page.y = page.y + 150 + 16
end

---------------------------------------------------------------------------
-- The pages
---------------------------------------------------------------------------

local SIZES = {}
for i = 9, 20 do SIZES[#SIZES + 1] = i end

local PAGES = {
    { key = "card", title = L("Guide card"), sub = L("How the step card looks and behaves"), build = function(p)
        Preview(p)
        Heading(p, L("Look"))
        Dropdown(p, "skin", L("Skin"), L("The colours of the card and every OpenXP window. Minimal has no background at all: just the text, outlined."),
            Style.SkinChoices(), "midnight")
        Slider(p, "cardOpacity", L("Background"), L("How solid the card's and Targets list's background is. 0% shows no background at all."),
            0, 1, 0.05, Pct)
        Slider(p, "fontSize", L("Text size"), L("The size of the step text on the card."), 9, 20, 1,
            function(v) return tostring(v) end)
        Slider(p, "cardScale", L("Card scale"), L("Makes the whole card, buttons and all, bigger or smaller."), 0.7, 1.5, 0.05, Pct)
        local _, order = OXP.Fonts.Choices()
        Dropdown(p, "font", L("Font"), L("Bundled fonts work for every language the game shows."), function()
            local values, list = OXP.Fonts.Choices(), {}
            for _, k in ipairs(order) do list[#list + 1] = { k, ((values[k] or k):gsub(" %(.*", "")) } end
            return list
        end, "default", function() OXP.Fonts.Changed() end)
        Dropdown(p, "fontOutline", L("Text outline"), L("An outline helps on bright backgrounds like snow."),
            { { "", L("None") }, { "OUTLINE", L("Thin") }, { "THICKOUTLINE", L("Thick") } }, "", function() OXP.Fonts.Changed() end)
        Heading(p, L("Behaviour"))
        Toggle(p, "cardShown", L("Show the guide card"), L("Hiding it also hides the arrow and the targets list. Also: /oxp card, or click the minimap button"))
        Toggle(p, "cardAnimations", L("Animate step changes"), L("The new step slides in and fades up when you move to it."))
        Toggle(p, "lockFrames", L("Lock the card and arrow"), L("Stops them being dragged or resized by accident."))
        ButtonRow(p, L("Position and size"), L("Put the card and arrow back where they started, at their first size."),
            L("Reset"), function()
                OXP.Card.ResetPosition()
                OXP.Arrow.ResetPosition()
            end)
    end },
    { key = "guides", title = L("Guides"), sub = L("Which guide you follow and when it changes"), build = function(p)
        Heading(p, L("Guides"))
        ButtonRow(p, L("Pick a guide"), L("Browse every guide for your character, by level."), L("Open guides"),
            function() OXP.GuidePicker.ShowGuides() end)
        Toggle(p, "autoNextGuide", L("Load the next guide when one is finished"), L("You go straight on to the next zone."))
        Toggle(p, "smartStartOnLogin", L("Move me to the right section at log in"),
            L("When you log in far past the step you're on, the guide jumps to where you are."))
    end },
    -- SoupEngine test build (Nav/Target.lua BAKED_ONLY): the arrow and the
    -- route line only follow SoupEngine's baked walks, so the trip and route
    -- style settings are hidden.
    { key = "arrow", title = L("Arrow and travel"),
        sub = L("The arrow and the trips it plans"), build = function(p)
        Heading(p, L("Arrow"))
        Toggle(p, "arrowShown", L("Show the arrow"), L("Points at the step's next spot."))
        Dropdown(p, "arrowStyle", L("Arrow style"), L("The pointer's shape."), OXP.ArrowView.StyleChoices(), "chevron")
        Dropdown(p, "arrowColor", L("Arrow colour"), L("The skin's colour, white, or red when far turning green as you get close."),
            { { "skin", L("Skin colour") }, { "distance", L("By distance") }, { "white", L("White") } }, "skin")
        Toggle(p, "arrowShowRing", L("Circle"), L("The ring and dark disc around the pointer."))
        Toggle(p, "arrowShowDistance", L("Distance"), L("How far it is, under the arrow."))
        Toggle(p, "arrowShowLabel", L("Step text"), L("What to do there, under the distance."))
        Slider(p, "arrowScale", L("Arrow size"), nil, 0.6, 2, 0.05, Pct)
        Slider(p, "arrowAlpha", L("Arrow opacity"), nil, 0.2, 1, 0.05, Pct)
        Slider(p, "arrowText", L("Arrow text size"), nil, 9, 20, 1, function(v) return tostring(v) end)
        Heading(p, L("Travel"))
        Toggle(p, "travel", L("Plan trips to other zones"), L("Flights, boats, trams and your Hearthstone, when the step is in another zone and no SoupEngine walk leads there."),
            function() OXP.Travel.Reset() end)
        if OXP.Target.BAKED_ONLY then return end
        Dropdown(p, "routeStyle", L("Route"), L("Follow roads keeps you off cliffs and out of mob camps."),
            { { "roads", L("Follow roads") }, { "direct", L("Shortest way") } }, "roads", function() OXP.Terrain.Reset() end)
    end },
    { key = "maps", title = L("Maps"), sub = L("What the world map and minimap show"), build = function(p)
        Heading(p, L("World map and minimap"))
        Toggle(p, "mapRoute", L("Route line"), OXP.Target.BAKED_ONLY and L("SoupEngine's walk to the step's spots.") or L("The way to the step's spots."))
        Slider(p, "routeWidth", L("Route line width"), nil, 0.75, 4, 0.25, function(v) return ("%.2f"):format(v) end)
        Toggle(p, "mapAreas", L("Kill and loot areas"), L("The current step's area. Needs Questie for steps that don't name their own area."))
        Toggle(p, "mapPins", L("Step pins"), L("! where you pick a quest up, ? where you hand one in."))
        Toggle(p, "mapStepNumbers", L("Step numbers"), L("The step's number on its pin."))
        Toggle(p, "mapNextStep", L("Next step pin"), L("A pin for the step after the current one too."))
        Toggle(p, "mapMobs", L("Objective icons"), L("Where the current step's mobs and objects are, like Questie's. Sword: kill it. Sack: it drops what you need. Cog: use or loot it. Bubble: talk."))
        Dropdown(p, "mapQuestIcons", L("Quest icons"), L("Yellow ! to pick up, grey ! for low level, yellow ? to turn in, grey ? not done yet. Auto: off while Questie shows its own."),
            { { "auto", L("Auto") }, { "on", L("Always") }, { "off", L("Off") } }, "auto")
        Toggle(p, "mapHideBlizzardPOI", L("Hide Blizzard's quest markers"), L("The game's own round ? and ... quest markers on the world map, while OpenXP's quest icons show (Questie does the same)."))
        Toggle(p, "mapObjectiveGlow", L("Objective glow"), L("A glow behind each objective's icons, a colour per objective."))
        Toggle(p, "mapObjectiveColors", L("Colour objective icons"), L("The icons themselves in their objective's colour."))
        Toggle(p, "mapContinentIcons", L("Icons on continent maps"), L("Off: only on zone maps."))
        Slider(p, "mapIconScale", L("Map icon size"), nil, 0.6, 1.6, 0.05, Pct)
        Heading(p, L("Minimap"))
        Toggle(p, "mapMinimapIcons", L("Minimap icons"), L("Quest and objective icons on the minimap; out of range they wait on its rim."))
        Slider(p, "minimapIconScale", L("Minimap icon size"), nil, 0.6, 1.6, 0.05, Pct)
        Slider(p, "minimapFadeLevel", L("Minimap fade distance"), nil, 10, 100, 5, function(v) return (v * 10) .. " yd" end)
        Toggle(p, "minimapFadeOverPlayer", L("Fade icons under you"), L("Icons right under your arrow fade to half, so you can see it."))
    end },
    { key = "auto", title = L("Automation"), sub = L("Things done for you (hold Shift to pause)"), build = function(p)
        Heading(p, L("Quests"))
        Toggle(p, "autoAccept", L("Accept the guide's quests"), L("Only quests the loaded guide picks up."))
        Toggle(p, "autoTurnIn", L("Turn in the guide's quests"), L("Only quests the loaded guide turns in, once they're complete."))
        Toggle(p, "autoTurnInAny", L("Turn in any completed quest"), L("Also quests the guide doesn't turn in, and ones you took yourself."))
        Heading(p, L("Rewards and talking"))
        Toggle(p, "autoReward", L("Take the reward when there's no choice"))
        Toggle(p, "autoBestReward", L("With a choice, take the one that sells for most"), L("Off: you pick the reward yourself."))
        Toggle(p, "skipGossip", L("Skip gossip"), L("Picks the guide's quest or the only option. Never sets your Hearthstone by itself."))
        Heading(p, L("Vendors"))
        Toggle(p, "autoSellJunk", L("Sell junk"), L("At a vendor, sells your grey items. Never quest items or items the guide still needs."))
        Heading(p, L("Travel"))
        Toggle(p, "autoFlight", L("Fly to the step's flight master"),
            L("On a \"fly to\" step, talking to a flight master takes that flight. Hold Shift while you talk to choose yourself."))
    end },
    { key = "buttons", title = L("Buttons and timers"), sub = L("Quest item and target buttons, timers"), build = function(p)
        Heading(p, L("Buttons"))
        Toggle(p, "itemButton", L("Quest item button"), L("Bind a key: Key Bindings > AddOns > OpenXP. Shift-drag to move."),
            function() OXP.ActionButtons.Refresh() end)
        Toggle(p, "targetButton", L("Targets list"), L("The mobs and NPCs the step needs, with portraits: click one to target it, or bind a key (Key Bindings > AddOns > OpenXP). Off: hidden, and that key does nothing."),
            function() OXP.ActionButtons.Refresh() end)
        Heading(p, L("Timers"))
        Toggle(p, "flightTimer", L("Flight timer"), L("How long until you land."))
        Toggle(p, "hearthReminder", L("Hearthstone reminder"), L("Says when the Hearthstone is ready on steps that use it."))
    end },
    { key = "extras", title = L("Extras"), sub = L("Small helpers around the game"), build = function(p)
        Heading(p, L("Extras"))
        Toggle(p, "tooltips", L("Quest lines on tooltips"), L("Item, mob and NPC tooltips say which quest wants them."))
        Toggle(p, "nameplates", L("Quest markers on nameplates"), L("A sword or bag over enemies an open objective of a quest in your log needs (and its count), and a speech bubble over people the step says to talk to."))
        Toggle(p, "nameplateGivers", L("! and ? on quest givers' nameplates"),
            L("Off: the game's own ! and ? over their heads are enough."))
        Toggle(p, "nameplateStepNumbers", L("Step numbers on nameplates"), L("The guide's step number beside a nameplate marker."))
        Toggle(p, "autoLoot", L("Auto loot"), nil, function() OXP.Tooltips.ApplyExtras(false) end)
        Toggle(p, "maxCamera", L("Zoom the camera out further"), nil, function() OXP.Tooltips.ApplyExtras(false) end)
        Toggle(p, "showQuestTracker", L("Show quest tracker"),
            L("Blizzard's quest tracker, and Questie's if you use it. Off: both hidden, the card shows the step."),
            function() OXP.settings.questieTrackerMine = nil end) -- turned off here: Questie's goes too
        Toggle(p, "minimapShown", L("Minimap button"), L("Left-click: the card. Right-click: the menu."),
            function() OXP.MinimapButton.Refresh() end)
    end },
    { key = "about", title = L("About"), sub = L("Version, licence and help"), build = function(p)
        Heading(p, L("OpenXP"))
        local text = Style.Text(p.content, 12, C.dim)
        text:SetPoint("TOPLEFT", S.xl, -p.y)
        text:SetPoint("RIGHT", p.content, "RIGHT", -S.xl, 0)
        text:SetWordWrap(true)
        text:SetText(L("Free, community-made leveling guides for WoW Forever. Free software under the GPL-3.0; the 1-20 guides are adapted from PoleStar (see NOTICE.md).")
            .. "\n\n" .. L("Version") .. " |cFFFFFFFF" .. tostring(OXP.version) .. "|r")
        p.y = p.y + 80
        ButtonRow(p, L("Feedback and bugs"), L("A link to report a problem or suggest something."), L("Feedback"),
            function() OXP.Feedback.Show() end)
        ButtonRow(p, L("What's new"), L("The changes in this version."), L("What's new"), function() OXP.Welcome.Show("update") end)
    end },
}
Settings.PAGES = PAGES

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function BuildPage(def)
    local area = Style.ScrollArea(f.body)
    area:SetPoint("TOPLEFT", SIDEBAR + 1, 0)
    area:SetPoint("BOTTOMRIGHT", 0, 0)
    area.content:SetWidth(WIDTH - SIDEBAR - 3)
    local page = { def = def, area = area, content = area.content, y = 0, rows = {},
                   toggles = {}, sliders = {}, dropdowns = {} }
    -- page title
    local title = Style.Text(page.content, 17, { 1, 1, 1 })
    title:SetPoint("TOPLEFT", S.xl, -S.xl)
    title:SetText(def.title)
    local sub = Style.Text(page.content, 12, C.dim)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(def.sub or "")
    page.y = S.xl + 46
    def.build(page)
    area:SetContentHeight(page.y + S.xl)
    area:Hide()
    pages[def.key] = page
    return page
end

function Settings.Select(key)
    if not f then return end
    for k, page in pairs(pages) do page.area:Hide() end
    local def
    for _, d in ipairs(PAGES) do if d.key == key then def = d end end
    def = def or PAGES[1]
    local page = pages[def.key] or BuildPage(def)
    page.area:ScrollTo(0)
    for _, update in ipairs(controls) do update() end
    Style.Fade(page.area, true, 0.12)
    for k, nav in pairs(navs) do nav:SetSelected(k == def.key) end
    Settings.current = def.key
    return page
end

function Settings.Page(key) return pages[key] end

local function NavButton(def, i)
    local b = CreateFrame("Button", nil, f.body)
    b:SetHeight(34)
    b:SetPoint("TOPLEFT", 8, -S.md - (i - 1) * 36)
    b:SetPoint("RIGHT", f.body, "LEFT", SIDEBAR - 8, 0)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    Style.Fill(b.bg, { 1, 1, 1 }, 0)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT", 0, -7)
    b.bar:SetPoint("BOTTOMLEFT", 0, 7)
    b.bar:SetWidth(3)
    Style.Fill(b.bar, C.blue)
    b.text = Style.Text(b, 13, C.dim)
    b.text:SetPoint("LEFT", 14, 0)
    b.text:SetText(def.title)
    function b:SetSelected(on)
        self.selected = on
        Style.Fill(self.bg, on and C.raised or { 1, 1, 1, 0 })
        self.bar:SetShown(on)
        Style.TextColor(self.text, on and { 1, 1, 1 } or C.dim)
    end
    b:SetScript("OnEnter", function(self)
        if not self.selected then
            Style.Fill(self.bg, { 1, 1, 1 }, 0.05)
            Style.TextColor(self.text, C.text)
        end
    end)
    b:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    b:SetScript("OnClick", function() Settings.Select(def.key) end)
    b:SetSelected(false)
    navs[def.key] = b
    return b
end

local function Build()
    f = Style.Window("OpenXPSettings", WIDTH, HEIGHT, L("Settings"), "OpenXP " .. tostring(OXP.version))
    -- sidebar
    local side = f.body:CreateTexture(nil, "BACKGROUND")
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDEBAR)
    Style.Fill(side, C.panel)
    local sideLine = Style.Divider(f.body, true)
    sideLine:SetPoint("TOPLEFT", SIDEBAR, 0)
    sideLine:SetPoint("BOTTOMLEFT", SIDEBAR, 0)
    for i, def in ipairs(PAGES) do NavButton(def, i) end

    local foot = Style.Footer(f)
    local note = Style.Text(foot, 11, C.faint)
    note:SetPoint("LEFT", S.lg, 0)
    note:SetText(L("Changes apply at once and are saved for all your characters."))
    local done = Style.Button(foot, L("Done"), "primary", 110, function() f:Hide() end)
    done:SetPoint("RIGHT", -S.lg, 0)
    f.done = done
    local reset = Style.Button(foot, L("Reset to defaults"), "ghost", 150, function() Settings.AskReset() end,
        L("Every OpenXP setting back to how it started. Your guide progress stays."))
    reset:SetPoint("RIGHT", done, "LEFT", -S.sm, 0)
    f.reset = reset
    note:SetPoint("RIGHT", reset, "LEFT", -S.sm, 0)
    note:SetWordWrap(false)
    f:HookScript("OnShow", function()
        DB().minimapShown = not (DB().minimap and DB().minimap.hide)
        for _, update in ipairs(controls) do update() end
    end)
    Settings.frame = f
end

--- Every setting back to its default (guide progress stays), then the
--- card, arrow, buttons, maps and this window repaint in the new look.
function Settings.ResetAll()
    OXP.ResetSettings()
    if OXP.Card then
        OXP.Card.skinKey = nil
        OXP.Card.ResetPosition()
    end
    if OXP.Arrow then
        OXP.Arrow.ResetPosition()
        if OXP.Arrow.ApplySizes then OXP.Arrow.ApplySizes() end
    end
    if OXP.ActionButtons and OXP.ActionButtons.Place then OXP.ActionButtons.Place() end
    if OXP.MinimapButton and OXP.MinimapButton.Refresh then OXP.MinimapButton.Refresh() end
    DB().minimapShown = not (DB().minimap and DB().minimap.hide)
    if OXP.Fonts and OXP.Fonts.Changed then OXP.Fonts.Changed() else Changed() end
    if OXP.Card then OXP.Card.Refresh(true) end
    for _, update in ipairs(controls) do update() end
    OXP.Print(L("Settings reset to their defaults."))
end

function Settings.AskReset()
    return Style.Confirm(L("Reset every OpenXP setting to its default?\n\nThe look, positions, sizes and automation go back to how they started. Your guide progress stays."),
        L("Reset to defaults"), Settings.ResetAll)
end

function Settings.Show(key)
    if not f then Build() end
    DB().minimapShown = not (DB().minimap and DB().minimap.hide)
    Settings.Select(key or Settings.current or "card")
    f:Show()
end

function Settings.Toggle()
    if f and f:IsShown() then f:Hide() else Settings.Show() end
end

OXP.AddCommand("settings", "open the settings", Settings.Toggle)
OXP.AddCommand("options", nil, Settings.Toggle)
