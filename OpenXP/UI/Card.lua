-- The guide card: the steps you're on, each with a badge for its kind,
-- check marks for finished lines and small bars for kill and loot counts,
-- an "Up next" line and a row of buttons.
--
-- It also warns about steps that can't be done as they stand (a quest you
-- don't have, a quest chain you missed, a quest something locked out) and
-- offers a way out: go back for the quest, walk through the chain with the
-- arrow, or skip the step.
local _, OXP = ...

local Card = {}
OXP.Card = Card

local Style, Engine, Quests, QuestDB = OXP.Style, OXP.Engine, OXP.Quests, OXP.QuestDB
local Text, L = OXP.Text, OXP.L
local C, TEX, WHITE = Style.C, Style.TEX, Style.WHITE
local SetFont, Tint = Style.SetFont, Style.Tint
local fmt = string.format

-- The card keeps the size you give it (saved in the settings) and never
-- grows or shrinks with the step: a long step scrolls inside it instead,
-- so the buttons stay under your mouse while you click through steps.
local WIDTH, HEIGHT = 330, 300
local MIN_W, MIN_H, MAX_W, MAX_H = 200, 150, 640, 900
local HEADER_H = 44           -- two rows: the guide's name, then its levels and your step
-- (the header grows with big text, see LayoutHeader)
local BAR_H = 38 + 1          -- button bar, border
local COLLAPSED_H = 42
local PAD = 12
local MAX_BLOCKS = 4
local MAX_LINES = 8
local FADE = 0.28             -- seconds for the new-step slide and fade

local function Settings() return OXP.settings end
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function Width() return Card.width or WIDTH end
local function Height() return Card.height or HEIGHT end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local f = CreateFrame("Frame", "OpenXPCard", UIParent, "BackdropTemplate")
Card.frame = f
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
Style.Backdrop(f, C.bg, C.border, { card = true })
-- nothing inside is ever drawn past the card's edge, also while you drag
-- the grip (the step list and menus are parented elsewhere for that reason)
if f.SetClipsChildren then f:SetClipsChildren(true) end
f:Hide()

local function SavePosition()
    local point, _, relPoint, x, y = f:GetPoint()
    if point then Settings().cardPos = { point, relPoint, x, y } end
    if OXP.ActionButtons then OXP.ActionButtons.Place() end -- they sit beside the card
end

f:SetScript("OnDragStart", function(self)
    Card.dragged = true
    if Settings().lockFrames then return end
    self:StartMoving()
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)
f:SetResizable(true)
if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
else
    if f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
    if f.SetMaxResize then f:SetMaxResize(MAX_W, MAX_H) end
end
f:SetScript("OnMouseDown", function() Card.dragged = false end)
f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and OXP.GuidePicker then
        OXP.GuidePicker.Toggle("cursor")
    elseif button == "LeftButton" and not Card.dragged and not Engine.GetGuide() and OXP.GuidePicker then
        OXP.GuidePicker.ShowGuides() -- the "no guide yet" line
    end
end)

local grip = CreateFrame("Button", nil, f)
Card.grip = grip
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(f:GetFrameLevel() + 10)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
-- Take the frame's size while you drag the grip (live: the text wraps to
-- it as you go). Collapsed, only the width is yours to change.
function Card.TakeSize()
    local w = Clamp(f:GetWidth() or WIDTH, MIN_W, MAX_W)
    local changed = math.abs(w - Width()) >= 0.5
    Card.width = w
    if not Settings().cardCollapsed then
        local h = Clamp(f:GetHeight() or HEIGHT, MIN_H, MAX_H)
        changed = changed or math.abs(h - Height()) >= 0.5
        Card.height = h
    end
    return changed
end

function Card.StartSizing()
    if Settings().lockFrames then return end
    Card.sizing = true
    f:StartSizing("BOTTOMRIGHT")
    grip:SetScript("OnUpdate", Card.SizingUpdate)
end

function Card.StopSizing()
    if not Card.sizing then return end
    grip:SetScript("OnUpdate", nil)
    f:StopMovingOrSizing()
    Card.sizing = false
    Card.TakeSize()
    local s = Settings()
    Card.width = math.floor(Width() + 0.5)
    s.cardWidth = Card.width
    if not s.cardCollapsed then
        Card.height = math.floor(Height() + 0.5)
        s.cardHeight = Card.height
    end
    SavePosition()
    Card.Refresh(true)
end

-- the live re-wrap runs only while you drag the grip
local function SizingUpdate()
    if Card.sizing and Card.TakeSize() then Card.Refresh(true) end
end
Card.SizingUpdate = SizingUpdate
grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then Card.StartSizing() end
end)
grip:SetScript("OnMouseUp", function() Card.StopSizing() end)
grip:SetScript("OnHide", function() Card.StopSizing() end)
-- The size comes from you and nothing else: while you drag, the text
-- re-wraps to it at once; at any other time a size that isn't the saved
-- one is put back.
f:SetScript("OnSizeChanged", function()
    if Card.sizing then
        if Card.TakeSize() then Card.Refresh(true) end
    elseif not Card.settingSize and Settings() and not Settings().cardCollapsed then
        local w, h = f:GetWidth() or 0, f:GetHeight() or 0
        if math.abs(w - Width()) >= 1 or math.abs(h - Height()) >= 1 then
            Card.settingSize = true
            f:SetSize(Width(), Height())
            Card.settingSize = false
        end
    end
end)
grip:SetScript("OnEnter", function(self) Style.Tooltip(self, L("Drag to resize")) end)
grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Header, two rows so the name never runs into the numbers, both rows on
-- the same left edge as the step below (its badge):
--   ASHENVALE, WETLANDS & STONETALON MOUNTAINS
--   Levels 22-25 ................... [list] Step 16 / 52
-- "[list] Step 16 / 52" is the way into the step list (UI/StepNavigator.lua):
-- no box around it, the icon says it opens a list, and it lights up in the
-- skin's accent under the mouse and while the list is open.
local header = CreateFrame("Frame", nil, f)
Card.header = header
header:SetPoint("TOPLEFT", 1, -1)
header:SetPoint("TOPRIGHT", -1, -1)
header:SetHeight(HEADER_H)
header.bg = header:CreateTexture(nil, "BACKGROUND")
header.bg:SetAllPoints()
header.bg:SetColorTexture(1, 1, 1, 0.03)
header.zone = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
header.zone:SetPoint("TOPLEFT", header, "TOPLEFT", PAD - 1, -7)
header.zone:SetPoint("RIGHT", header, "RIGHT", -PAD + 1, 0)
Style.TextColor(header.zone, C.text)
header.zone:SetJustifyH("LEFT")
header.zone:SetWordWrap(false)
header.range = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
header.range:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", PAD - 1, 7)
header.range:SetJustifyH("LEFT")
header.range:SetWordWrap(false)
Style.TextColor(header.range, C.dim)
header.step = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
header.step:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -PAD + 1, 7)
header.step:SetJustifyH("RIGHT")
header.step:SetWordWrap(false)
Style.TextColor(header.step, C.dim)
-- the levels never run under the counter
header.range:SetPoint("RIGHT", header.step, "LEFT", -28, 0)
-- the button covers the icon and the counter (and a little round them)
header.nav = CreateFrame("Button", nil, header)
header.nav:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 1)
header.nav:SetHeight(22)
header.nav:SetWidth(110)
header.nav.icon = header.nav:CreateTexture(nil, "ARTWORK")
header.nav.icon:SetTexture(TEX .. "steps_32")
header.nav.icon:SetSize(12, 12)
header.nav.icon:SetPoint("RIGHT", header.step, "LEFT", -5, 0)
header.nav.label = header.step -- the counter is the button's text
header.stepBtn = header.nav -- older code and tests know it by these names
header.dot = header.nav.icon
--- Paint the step counter: dim at rest; the accent under the mouse and while
--- the list is open.
function Card.PaintNav()
    local nav = header.nav
    local lit = nav.hover or (OXP.StepNav and OXP.StepNav.IsShown())
    Style.Tint(nav.icon, lit and C.blue or C.dim, lit and 1 or 0.9)
    Style.TextColor(header.step, lit and C.blue or C.dim)
    nav.lit = lit and true or false
end
--- Size the button to the counter it covers (after the text or font changes).
function Card.SizeNav()
    local w = header.step:GetStringWidth() or 60
    header.nav:SetWidth(math.floor(w + 12 + 5 + (PAD - 1) + 6 + 0.5))
end
header.nav:SetScript("OnClick", function() Card.ToggleStepList() end)
header.nav:SetScript("OnEnter", function(self)
    self.hover = true
    Card.PaintNav()
    Style.Tooltip(self, L("Show all steps"), L("Every step of this guide: what you've done, skipped and what's coming. Click one to go there. Also /oxp steps."))
end)
header.nav:SetScript("OnLeave", function(self)
    self.hover = false
    Card.PaintNav()
    GameTooltip:Hide()
end)

local progressBg = f:CreateTexture(nil, "ARTWORK")
progressBg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
progressBg:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
progressBg:SetHeight(2)
progressBg:SetColorTexture(1, 1, 1, 0.06)
local progress = f:CreateTexture(nil, "OVERLAY")
progress:SetPoint("TOPLEFT", progressBg, "TOPLEFT")
progress:SetHeight(2)
progress:SetWidth(1)
Style.Fill(progress, C.blue, 1)

---------------------------------------------------------------------------
-- What a step says
---------------------------------------------------------------------------

local BLOCKING = { accept = true, turnin = true, complete = true, collect = true, xp = true, zone = true, fp = true, home = true,
                   finish = true, reach = true, train = true, fly = true }

--- The badge kind for a step.
function Card.StepKind(step)
    local has, words = {}, ""
    for _, g in ipairs(step.goals or {}) do
        has[g[1]] = true
        if g.text then words = words .. " " .. Text.Strip(g.text):lower() end
    end
    if has.accept then return "accept" end
    if has.turnin then return "turnin" end
    if has.complete or has.collect or has.mob then
        if has.collect or words:find("loot") or words:find("collect") or words:find("click") or words:find("pick") then
            return "loot"
        end
        return "kill"
    end
    if has.home or has.fp then return "town" end
    return "travel"
end

--- The text a goal shows on the card, made live where it can be (kill counts).
-- "Call of Earth" three times in a row reads like a repeat: quests of one
-- name that follow each other get "(part 2)" after the name. Part 1 too
-- when its next part is in the same step (`step` given).
local function WithPart(text, g, step)
    if not (text and g.quest) then return text end
    local name = QuestDB.QuestName(g.quest)
    if not name or name == "" then return text end
    local part = QuestDB.ChainPart(g.quest) or 1
    if part == 1 and step then
        -- only when a later part of this very chain is in the step: two
        -- unrelated quests that share a name (one per race or class) aren't
        local later = false
        for _, o in ipairs(step.goals or {}) do
            if o.quest and o.quest ~= g.quest and QuestDB.QuestName(o.quest) == name
                and QuestDB.IsLaterPart(g.quest, o.quest) then later = true break end
        end
        if not later then return text end
    elseif part == 1 then
        return text
    end
    local tag = name .. " " .. fmt(L("(part %d)"), part)
    local s, e = text:find(name, 1, true)
    if s then return text:sub(1, s - 1) .. tag .. text:sub(e + 1) end
    return text .. " " .. fmt(L("(part %d)"), part)
end
Card.WithPart = WithPart

function Card.GoalText(g, step)
    local kind = g[1]
    if kind == "complete" then
        local o = Quests.GetObjective(g.quest, g.obj)
        if o and o.text and o.text ~= "" then
            -- an item one or two named mobs drop: say who ("0/1 Gobbler's Head - from Gobbler")
            if not o.done then
                local list, okind = QuestDB.ObjectiveSources(g.quest, g.obj)
                if okind == "item" and list and #list > 0 and #list <= 2 then
                    local names = {}
                    for _, s in ipairs(list) do
                        if s.kind == "NPC" and s.name then names[#names + 1] = s.name end
                    end
                    if #names == #list then
                        return o.text .. " |cFF9EA3B3- " .. fmt(L("from %s"), table.concat(names, " " .. L("or") .. " ")) .. "|r"
                    end
                end
            end
            return o.text
        end
        return g.text or fmt(L("Objective %d of %s"), g.obj, QuestDB.QuestName(g.quest))
    elseif kind == "accept" then
        return WithPart(g.text or fmt(L("Accept %s"), QuestDB.QuestName(g.quest)), g, step)
    elseif kind == "turnin" then
        return WithPart(g.text or fmt(L("Turn in %s"), QuestDB.QuestName(g.quest)), g, step)
    elseif kind == "collect" then
        local have = OXP.World.ItemCount(g.item)
        return fmt("%s: %d/%d", g.text or (GetItemInfo and GetItemInfo(g.item)) or ("item " .. g.item),
            math.min(have, g.count or 1), g.count or 1)
    elseif kind == "xp" then
        return g.text or fmt(L("Reach level %d"), g.level)
    elseif kind == "zone" then
        return g.text or fmt(L("Go to %s"), g.name)
    elseif kind == "fp" then
        return g.text or fmt(L("Get the %s flight path"), g.name)
    elseif kind == "home" then
        return g.text or L("Set your Hearthstone here")
    elseif kind == "finish" then
        return g.text or fmt(L("Finish %s"), QuestDB.QuestName(g.quest))
    elseif kind == "reach" then
        return g.text or L("Go to the marked spot")
    elseif kind == "train" then
        return g.text or L("Train your new spells")
    elseif kind == "fly" then
        return g.text or fmt(L("Fly to %s"), g.name)
    end
    return g.text
end

--- The step's title (its first text) and checklist lines.
function Card.StepContent(step)
    local title, lines, seen = nil, {}, {}
    for _, g in ipairs(step.goals or {}) do
        local kind = g[1]
        if BLOCKING[kind] then
            local state = OXP.Goals.State(g, step.marks)
            if state ~= "skip" then
                local text = Card.GoalText(g, step)
                -- the same quest and action twice in a step: once
                local key = g[1] .. ":" .. tostring(g.quest or "") .. ":" .. tostring(g.obj or "")
                if text and not (g.quest and seen[key]) then
                    seen[key] = true
                    lines[#lines + 1] = { text = Text.Format(text), done = state == "done", goal = g }
                end
            end
        elseif kind == "text" or ((kind == "goto" or kind == "item") and g.text) then
            if not title then
                title = Text.Format(g.text)
            else
                lines[#lines + 1] = { text = Text.Format(g.text), plain = true }
            end
        end
    end
    if not title and lines[1] then
        title = lines[1].text
        table.remove(lines, 1)
    end
    -- a line saying just what the title says ("Boat to Menethil Harbor"
    -- over a "Boat to Menethil Harbor" checkpoint) read as the title
    -- twice, the second one faded: shown once
    if title then
        local key = Text.Strip(title):lower():gsub("[%p%s]+", " "):gsub("^ ", ""):gsub(" $", "")
        for i = #lines, 1, -1 do
            local k = Text.Strip(lines[i].text or ""):lower():gsub("[%p%s]+", " "):gsub("^ ", ""):gsub(" $", "")
            if k == key then table.remove(lines, i) end
        end
    end
    return title or fmt(L("Step %d"), step.index or 0), lines
end

--- "now" for the step to do, "side" for one that stays open while you do the
--- next (travel, "kill these on the way"), "done".
function Card.StepRole(step, pos)
    if step.detour then return "now" end
    local state = pos and Engine.StepState(pos)
    if state == "done" then return "done" end
    local open = false
    for _, g in ipairs(step.goals or {}) do
        if OXP.Goals.State(g, step.marks) == "todo" then open = true end
    end
    if not open and pos then return "done" end
    if step.completewith or step.along then return "side" end
    return "now"
end

---------------------------------------------------------------------------
-- Quest chain walks ("Do the chain", "Finish it", "Get the quest")
---------------------------------------------------------------------------

local function TurnedIn(id) return Quests.IsTurnedIn(id) end

--- Start walking through `ids` for `target`. mode "have" ends once the target
--- is in your log, "available" once it can be picked up, "complete" once its
--- objectives are done.
function Card.StartDetour(target, ids, mode)
    local g = Engine.GetGuide()
    Card.detour = { target = target, ids = ids, mode = mode, guide = g and g.key }
    OXP.char.detour = Card.detour
    Card.Refresh(true)
    if OXP.ActionButtons then OXP.ActionButtons.Soon() end -- the target button follows the walk
end

function Card.StopDetour()
    Card.detour = nil
    OXP.char.detour = nil
    OXP.Target.SetOverride(nil)
    Card.Refresh(true)
    if OXP.ActionButtons then OXP.ActionButtons.Soon() end
end

local function DetourDone(d)
    if d.mode == "complete" then
        return TurnedIn(d.target) or not Quests.IsOnQuest(d.target) or Quests.IsComplete(d.target)
    end
    if d.mode == "have" then return Quests.IsOnQuest(d.target) or TurnedIn(d.target) end
    return not QuestDB.Blocked(d.target)
end

local NO_SPOT, SameSpot

local function SpotTarget(spot, title)
    if not (spot and spot[2] and spot[2] > 0) then return nil end
    local wx, wy, inst = OXP.Places.ToWorld(spot[2], spot[3], spot[4])
    if not wx then return nil end
    return { wx = wx, wy = wy, instance = inst, map = spot[2], title = title or spot[1] }
end

local function QuestLevelText(info)
    return info and info.l and info.l > 0 and fmt(" |cFF9EA3B3(lvl %d)|r", info.l) or ""
end

--- The quest of the walk you're on, as a step the card can show, its place
--- in the walk, and the arrow's spot for it.
--- The quest of the walk you're on and its place in the walk, or nil.
function Card.DetourQuest()
    local d = Card.detour
    if not d then return nil end
    for i, q in ipairs(d.ids) do
        if not TurnedIn(q) and not (q == d.target and Quests.IsOnQuest(q) and d.mode ~= "complete") then
            return q, i
        end
    end
end

function Card.DetourStep()
    local id, index = Card.DetourQuest()
    if not id then return nil end
    local info = QuestDB.Info(id) or {}
    local name = QuestDB.QuestName(id)
    local title, lines, target
    if not Quests.IsOnQuest(id) then
        local who = info.s and info.s[1] or "?"
        title = fmt(L("Pick up %s"), name) .. QuestLevelText(info)
        local where = info.s and info.s[2] == 0 and L("Loot or use %s to start it") or L("Get it from %s")
        lines = { { text = fmt(where, who) } }
        if info.r and (OXP.Player.level or 1) < info.r then
            lines[#lines + 1] = { text = fmt(L("|cFFF2C35CYou need level %d for this quest|r"), info.r), plain = true }
        end
        target = SpotTarget(info.s)
    else
        local open, objs = false, {}
        for i = 1, 8 do
            local o = Quests.GetObjective(id, i)
            if not o then break end
            objs[#objs + 1] = { text = o.text or "", done = o.done }
            if not o.done then open = true end
        end
        if open then
            title = fmt(L("Do %s"), name) .. QuestLevelText(info)
            lines = objs
            target = SpotTarget(info.o and info.o[1])
        else
            title = fmt(L("Turn in %s"), name) .. QuestLevelText(info)
            lines = { { text = fmt(L("Talk to %s"), info.f and info.f[1] or "?") } }
            target = SpotTarget(info.f)
        end
    end
    if not target then
        lines[#lines + 1] = { text = L("|cFFF2C35CNo map spot for this one in the quest data: no arrow|r"), plain = true }
    end
    return { detour = true, goals = {}, marks = {}, title = title, lines = lines }, index, target
end

-- The arrow's spot for a chain-walk quest that has none (Nav/Target.lua).
NO_SPOT = { none = true }

function SameSpot(a, b)
    if a == b then return true end
    if not (a and b) then return false end
    if a.none or b.none then return a.none == b.none end
    return a.map == b.map and a.instance == b.instance
        and math.abs(a.wx - b.wx) < 0.5 and math.abs(a.wy - b.wy) < 0.5
end

---------------------------------------------------------------------------
-- Moving around by hand
---------------------------------------------------------------------------

--- Position of the step that picks up `quest`: the nearest one before
--- `before`, else the first after it.
function Card.FindAcceptPos(quest, before)
    local steps = Engine.GetSteps()
    local function accepts(step)
        for _, g in ipairs(step.goals) do
            if g[1] == "accept" and g.quest == quest then return true end
        end
    end
    for i = math.min(before - 1, #steps), 1, -1 do
        if accepts(steps[i]) then return i end
    end
    for i = before + 1, #steps do
        if accepts(steps[i]) then return i end
    end
end

--- Position of the earlier step that picks up the first open quest of a
--- missed chain, or nil.
function Card.ChainBackPos(chain, before)
    for _, q in ipairs(chain or {}) do
        if not TurnedIn(q) and not Quests.IsOnQuest(q) then
            local steps = Engine.GetSteps()
            for i = math.min(before - 1, #steps), 1, -1 do
                for _, g in ipairs(steps[i].goals) do
                    if g[1] == "accept" and g.quest == q then return i end
                end
            end
            return nil
        end
    end
end

function Card.JumpTo(pos)
    Card.here = nil
    Engine.GoTo(pos)
    if Card.FillStepList then Card.FillStepList() end
    Card.Refresh(true)
end

function Card.GoBack()
    if Engine.Back() then Card.Refresh(true) end
end

function Card.GoNext()
    Card.here = nil
    Engine.Next()
    Card.Refresh(true)
end

function Card.Resume()
    Engine.Resume()
    Card.Refresh(true)
end

---------------------------------------------------------------------------
-- Step blocks
---------------------------------------------------------------------------

-- The steps sit in a scroll frame between the header and "Up next": what
-- doesn't fit is cut off at its edge (never drawn over the buttons), and
-- "More" lets it take the room of "Up next" and scroll with the wheel.
local view = CreateFrame("ScrollFrame", nil, f)
Card.view = view
view:SetPoint("TOPLEFT", progressBg, "BOTTOMLEFT", 0, 0)
view:SetPoint("TOPRIGHT", progressBg, "BOTTOMRIGHT", 0, 0)
view:SetHeight(10)
if view.SetClipsChildren then view:SetClipsChildren(true) end
local content = CreateFrame("Frame", nil, view)
Card.content = content
content:SetSize(WIDTH - 2, 10)
view:SetScrollChild(content)

local body = CreateFrame("Frame", nil, content)
body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
body:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
body:SetHeight(10)

-- A new step slides in and fades up (Settings: "Animate step changes"):
-- from the right when you go forward, from the left when you go back, and
-- the progress line glides to its new length. Driven by hand on an
-- OnUpdate (an AnimationGroup on the scroll frame doesn't move what's
-- inside it), so a redraw half-way through keeps the motion going.
local SLIDE = 28              -- px the new step travels
local tween = CreateFrame("Frame")
Card.tween, Card.body = tween, body
tween:Hide()
tween.p, tween.dir = 1, 1

local function Ease(p) return 1 - (1 - p) ^ 3 end -- fast, then settles

--- Where the steps sit: at the top, sideways while the new step slides in.
function Card.PlaceBody()
    local x = tween:IsShown() and tween.dir * (1 - Ease(tween.p)) * SLIDE or 0
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", content, "TOPLEFT", x, 0)
    body:SetPoint("TOPRIGHT", content, "TOPRIGHT", x, 0)
end

--- The progress line's length; glides there while a step slides in.
function Card.SetProgress(w)
    tween.toW = w
    if not tween:IsShown() then progress:SetWidth(w) end
end

local function ApplyTween()
    local e = Ease(tween.p)
    body:SetAlpha(e)
    if tween.fromW and tween.toW then
        progress:SetWidth(math.max(1, tween.fromW + (tween.toW - tween.fromW) * e))
    end
    Card.PlaceBody()
end

tween:SetScript("OnUpdate", function(self, dt)
    self.p = math.min(1, self.p + (dt or 0) / FADE)
    if self.p >= 1 then self:Hide() end
    ApplyTween()
end)

--- dir 1: the new step comes in from the right (forward), -1 from the left.
function Card.PlayStepAnimation(dir)
    if Settings().cardAnimations == false then
        if tween:IsShown() then -- switched off mid-slide: finish it now
            tween.p = 1
            tween:Hide()
            ApplyTween()
        end
        return false
    end
    tween.dir = dir or 1
    tween.p = 0
    tween.fromW = progress:GetWidth() or 1
    tween:Show()
    ApplyTween() -- hidden at once, so the new text never flashes in first
    return true
end

local blocks = {}
Card.blocks = blocks

local function NewLine(block)
    local line = CreateFrame("Frame", nil, block)
    line.mark = line:CreateTexture(nil, "ARTWORK")
    line.mark:SetSize(13, 13)
    line.mark:SetPoint("TOPLEFT", 0, -1)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line.text:SetPoint("TOPLEFT", line.mark, "TOPRIGHT", 7, 1)
    line.text:SetJustifyH("LEFT")
    line.text:SetJustifyV("TOP")
    line.text:SetWordWrap(true) -- wraps to the card's width, never cut off at the side
    line.barBg = line:CreateTexture(nil, "ARTWORK")
    line.barBg:SetHeight(5)
    line.barBg:SetColorTexture(1, 1, 1, 0.1)
    line.bar = line:CreateTexture(nil, "OVERLAY")
    line.bar:SetHeight(5)
    line.bar:SetPoint("LEFT", line.barBg, "LEFT")
    line.count = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Style.TextColor(line.count, C.dim)
    return line
end

local function GetBlock(i)
    local b = blocks[i]
    if b then return b end
    b = CreateFrame("Frame", nil, body)
    b.sep = b:CreateTexture(nil, "ARTWORK")
    b.sep:SetPoint("TOPLEFT", PAD, 0)
    b.sep:SetPoint("TOPRIGHT", -PAD, 0)
    b.sep:SetHeight(1)
    b.sep:SetColorTexture(1, 1, 1, Card.lineAlpha or Style.skin.line)
    b.badge = Style.Badge(b, 34)
    b.badge:SetPoint("TOPLEFT", PAD, -10)
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.num:SetPoint("TOP", b.badge, "BOTTOM", 0, -4)
    b.num:SetJustifyH("CENTER")
    Style.TextColor(b.num, C.faint)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.title:SetPoint("TOPLEFT", b.badge, "TOPRIGHT", 12, -1)
    b.title:SetJustifyH("LEFT")
    b.title:SetJustifyV("TOP")
    b.title:SetWordWrap(true)
    Style.TextColor(b.title, C.text)
    b.lines = {}
    blocks[i] = b
    return b
end

-- The warning panel under a step that can't be done as it stands.
local function GetWarn(b)
    if b.warn then return b.warn end
    local w = CreateFrame("Frame", nil, b)
    w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.text:SetPoint("TOPLEFT")
    w.text:SetJustifyH("LEFT")
    Style.TextColor(w.text, C.gold)
    w.list = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.list:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -4)
    w.list:SetJustifyH("LEFT")
    Style.TextColor(w.list, C.dim)
    w.get = Style.TextButton(w, L("Get the quest"),
        L("Go and pick this quest up. Once you have it the guide brings you back here."), function()
            local m = b.missing
            if not m then return end
            if m.accept then
                Card.returnTo = { guide = Engine.GetGuide(), pos = m.pos, quest = m.quest }
                Engine.GoTo(m.accept)
                Card.Refresh(true)
            else
                Card.StartDetour(m.quest, { m.quest }, "have")
            end
        end)
    w.back = Style.TextButton(w, L("Go back to it"),
        L("Go back to the step where the guide picks up the first quest of this chain. Once the chain is done the guide brings you back here."),
        function()
            local m = b.missing
            if not (m and m.back) then return end
            Card.returnTo = { guide = Engine.GetGuide(), pos = m.pos, quest = m.quest, chain = true, needAccept = m.needAccept }
            Engine.GoTo(m.back)
            Card.Refresh(true)
        end)
    w.chain = Style.TextButton(w, L("Do the chain"),
        L("Walk through the earlier quests in this chain, with the arrow. When they're done the guide picks up here again."),
        function()
            local m = b.missing
            if not m then return end
            local ids = {}
            for _, q in ipairs(m.chain or {}) do ids[#ids + 1] = q end
            if m.needAccept then ids[#ids + 1] = m.quest end
            Card.StartDetour(m.quest, ids, m.needAccept and "have" or "available")
        end)
    w.finish = Style.TextButton(w, L("Finish it"),
        L("Do this quest's objectives now, with the arrow. When they're done the guide brings you back to turn it in."),
        function()
            local m = b.missing
            if m then Card.StartDetour(m.quest, { m.quest }, "complete") end
        end)
    w.skip = Style.TextButton(w, L("Skip this step"), L("Move on without this quest"), function()
        if b.missing then Card.GoNext() end
    end)
    b.warn = w
    return w
end

local function LayoutWarn(b, step, pos, problem, y, textWidth)
    local w = GetWarn(b)
    local id = problem.quest
    local m = { quest = id, pos = pos, chain = problem.chain, needAccept = problem.needAccept }
    local text, list, buttons
    if problem.kind == "unfinished" then
        text = fmt(L("You haven't finished %s yet"), QuestDB.QuestName(id))
        local rows = {}
        for i = 1, 8 do
            local o = Quests.GetObjective(id, i)
            if not o then break end
            rows[#rows + 1] = (o.done and "|cFF3DBB7A" .. L("Done") .. ":|r " or "- ") .. tostring(o.text or "")
        end
        if #rows > 0 then list = table.concat(rows, "\n") end
        buttons = { w.finish, w.skip }
    elseif problem.kind == "missing" then
        m.accept = Card.FindAcceptPos(id, pos)
        local info = QuestDB.Info(id)
        buttons = (m.accept or (info and info.s)) and { w.get, w.skip } or { w.skip }
        text = fmt(L("You don't have %s yet"), QuestDB.QuestName(id))
    elseif problem.kind == "locked" then
        text = fmt(L("You can't get %s: doing %s locked it out"), QuestDB.QuestName(id), QuestDB.QuestName(problem.by))
        buttons = { w.skip }
    else
        local chain = problem.chain or {}
        if #chain == 0 then
            text = fmt(L("You can't pick up %s yet"), QuestDB.QuestName(id))
            buttons = { w.skip }
        else
            text = fmt(#chain == 1 and L("%s is part of a quest chain: 1 quest to do first")
                or L("%s is part of a quest chain: %d quests to do first"), QuestDB.QuestName(id), #chain)
            local rows = {}
            for i, q in ipairs(chain) do
                if i > 5 then
                    rows[#rows + 1] = fmt(L("+ %d more"), #chain - 5)
                    break
                end
                local info = QuestDB.Info(q)
                rows[#rows + 1] = fmt("%d. %s%s%s", i, QuestDB.QuestName(q),
                    info and info.l and info.l > 0 and fmt(" (lvl %d)", info.l) or "",
                    Quests.IsOnQuest(q) and L(" - in your log") or "")
            end
            list = table.concat(rows, "\n")
            m.back = Card.ChainBackPos(chain, pos)
            if m.back then
                w.back:SetLabel(fmt(L("Go back to step %d"), m.back))
                buttons = { w.back, w.chain, w.skip }
            else
                buttons = { w.chain, w.skip }
            end
        end
    end
    b.missing = m
    SetFont(w.text, 0)
    w.text:SetWidth(textWidth)
    w.text:SetText(text)
    SetFont(w.list, 0)
    w.list:SetWidth(textWidth)
    w.list:SetText(list or "")
    w.list:SetShown(list ~= nil)
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", b.title, "TOPLEFT", 0, -(y - 11))
    w:SetPoint("RIGHT", b, "RIGHT", -PAD, 0)
    for _, btn in ipairs({ w.get, w.back, w.chain, w.finish, w.skip }) do btn:Hide() end
    local anchor = list and w.list or w.text
    -- side by side, wrapping to a new row on a narrow card
    local rows, x, rowStart = 1, 0, nil
    local bh = 22
    for i, btn in ipairs(buttons) do
        -- the first one is what to do (the skin's accent), Skip stays quiet;
        -- words in the card's font and size (outlined on Minimal)
        btn:SetKind((i == 1 and btn ~= w.skip) and "primary" or "quiet")
        SetFont(btn.label, -1)
        btn:SetLabel(btn.label:GetText() or "")
        bh = math.max(bh, btn:GetHeight() or 22)
    end
    for i, btn in ipairs(buttons) do
        btn:ClearAllPoints()
        local bw = btn:GetWidth() or 80
        if i == 1 then
            btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
            rowStart, x = btn, bw
        elseif x + 6 + bw > textWidth then
            btn:SetPoint("TOPLEFT", rowStart, "BOTTOMLEFT", 0, -6)
            rowStart, x, rows = btn, bw, rows + 1
        else
            btn:SetPoint("LEFT", buttons[i - 1], "RIGHT", 6, 0)
            x = x + 6 + bw
        end
        btn:Show()
    end
    local h = w.text:GetStringHeight() + (list and (w.list:GetStringHeight() + 4) or 0) + 6 + bh + (rows - 1) * (bh + 6)
    w:SetHeight(h)
    w:Show()
    return h + 8
end

local reported = {}
function Card.ReportError(err)
    err = tostring(err)
    Card.lastError = err
    if reported[err] then return end
    reported[err] = true
    print("|cFFFF4040OpenXP card error:|r " .. err)
end

local function LayoutBlock(b, step, pos, first)
    local textWidth = Width() - PAD * 2 - 34 - 12
    b.sep:SetShown(not first)
    b.badge:SetKind(step.detour and (Quests.IsOnQuest(Card.detour and Card.detour.target or 0) and "kill" or "accept")
        or Card.StepKind(step))
    SetFont(b.num, -2)
    b.num:SetText(pos and not step.detour and ("#" .. pos) or "")

    local title, lines
    if step.detour then
        title, lines = step.title, {}
        for _, l in ipairs(step.lines) do lines[#lines + 1] = l end
    else
        title, lines = Card.StepContent(step)
    end
    local role = Card.StepRole(step, pos)
    if role == "side" then
        title = "|cFF9EA3B3" .. L("ALONG THE WAY") .. ":|r " .. title
    elseif role == "done" then
        title = "|cFF3DBB7A" .. L("DONE") .. ":|r " .. Text.Strip(title)
    end
    b:SetAlpha(role == "done" and 0.45 or role == "side" and 0.8 or 1)

    if role == "now" and not step.detour then
        -- a pickup step: say so, since the quest isn't in your log yet
        for _, g in ipairs(step.goals) do
            if g[1] == "accept" and OXP.Goals.State(g, step.marks) == "todo" and not QuestDB.Blocked(g.quest) then
                lines[#lines + 1] = { text = "|cFF9EA3B3" .. L("You get this quest at this step") .. "|r", plain = true }
                break
            end
        end
        if step.here and Card.here then
            title = "|cFFF2C35C" .. L("WHILE YOU'RE HERE") .. ":|r " .. title
            table.insert(lines, 1, { text = "|cFFF2C35C" .. fmt(L("This is step %d. Do it now while you're here: the guide stays on step %d, nothing is skipped."), pos, Card.here.from) .. "|r", plain = true })
        end
        -- the step is in another zone: how to get there
        local plan = OXP.Travel.Current()
        local real = plan and plan.target and (plan.target.real or plan.target)
        local travel = plan and real and real.pos == pos and OXP.Travel.Lines()
        local hearth = OXP.Timers and OXP.Timers.HearthLine(step)
        if hearth then lines[#lines + 1] = { text = hearth, plain = true } end
        if travel and #travel > 0 then
            lines[#lines + 1] = { text = "|cFFB36BFF" .. L("Getting there:") .. "|r", plain = true }
            for _, t in ipairs(travel) do
                if #lines >= MAX_LINES then break end
                lines[#lines + 1] = { text = t, plain = true }
            end
        end
    end
    SetFont(b.title, 3)
    b.title:SetWidth(textWidth)
    b.title:SetText(title)
    local y = 11 + b.title:GetStringHeight() + 7

    for i = 1, MAX_LINES do
        local line, data = b.lines[i], lines[i]
        if data then
            line = line or NewLine(b)
            b.lines[i] = line
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", b.title, "TOPLEFT", 0, -(y - 11))
            line:SetPoint("RIGHT", b, "RIGHT", -PAD, 0)
            SetFont(line.text, 1)
            SetFont(line.count, 0)
            line.text:SetWidth(textWidth - 20)
            local have, need = Text.Strip(data.text):match("(%d+)%s*/%s*(%d+)%s*$")
            have, need = tonumber(have), tonumber(need)
            if data.plain then
                line.mark:Hide()
                line.text:SetPoint("TOPLEFT", line.mark, "TOPLEFT", 0, 1)
            else
                line.mark:Show()
                line.text:SetPoint("TOPLEFT", line.mark, "TOPRIGHT", 7, 1)
                if data.done then
                    line.mark:SetTexture(TEX .. "check")
                    Tint(line.mark, C.green)
                else
                    line.mark:SetTexture(TEX .. "opencircle")
                    Tint(line.mark, C.dim)
                end
            end
            line.text:SetText(data.text)
            Style.TextColor(line.text, data.done and C.faint or C.text)
            line:SetAlpha(data.done and 0.7 or 1)
            local h = line.text:GetStringHeight()
            if have and need and need > 1 and not data.done then
                line.barBg:ClearAllPoints()
                line.barBg:SetPoint("TOPLEFT", line.text, "BOTTOMLEFT", 0, -5)
                line.barBg:SetPoint("RIGHT", line, "RIGHT", -44, 0)
                line.barBg:Show()
                line.bar:SetWidth(math.max(1, (textWidth - 64) * math.min(have / need, 1)))
                local kc = (Style.BADGES[Card.StepKind(step)] or Style.BADGES.travel).color
                line.bar:SetColorTexture(kc[1], kc[2], kc[3], 1)
                line.bar:SetShown(have > 0)
                line.count:ClearAllPoints()
                line.count:SetPoint("LEFT", line.barBg, "RIGHT", 8, 0)
                line.count:SetText(fmt("%d / %d", have, need))
                line.count:Show()
                h = h + 12
            else
                line.barBg:Hide()
                line.bar:Hide()
                line.count:Hide()
            end
            line:SetHeight(h + 2)
            line:Show()
            y = y + h + 7
        elseif line then
            line:Hide()
        end
    end

    local problem
    if pos and not step.detour then
        local ok, res = pcall(QuestDB.StepProblem, step)
        if ok then problem = res else Card.ReportError(res) end
    end
    if problem then
        y = y + LayoutWarn(b, step, pos, problem, y, textWidth)
    else
        b.missing = nil
        if b.warn then b.warn:Hide() end
    end
    -- tall enough for the badge and the "#32" under it, at any text size
    local numH = b.num:GetText() ~= "" and ((b.num:GetStringHeight() or 0) > 0 and b.num:GetStringHeight() or 14) + 4 or 0
    local height = math.max(y + 4, 10 + 34 + numH + 8, 34 + 20 + (numH > 0 and 14 or 0))
    b:SetHeight(height)
    return height
end

--- With "More" open, the wheel scrolls the step's text; true if it did.
function Card.ScrollText(delta)
    if not (Card.expanded and (Card.maxScroll or 0) > 0) then return false end
    local by = (Style.FontSize(0) + 6) * 2
    Card.scroll = Clamp((Card.scroll or 0) - delta * by, 0, Card.maxScroll)
    view:SetVerticalScroll(Card.scroll)
    return true
end

f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function(_, delta) Card.ScrollText(delta) end)

---------------------------------------------------------------------------
-- The button bar, the XP strip
---------------------------------------------------------------------------

local bar = CreateFrame("Frame", nil, f)
Card.bar = bar
bar:SetHeight(38)
bar:SetPoint("BOTTOMLEFT", 1, 1)
bar:SetPoint("BOTTOMRIGHT", -1, 1)
bar.bg = bar:CreateTexture(nil, "BACKGROUND")
bar.bg:SetAllPoints()
bar.bg:SetColorTexture(1, 1, 1, 0.04)
bar.line = bar:CreateTexture(nil, "ARTWORK")
bar.line:SetPoint("TOPLEFT")
bar.line:SetPoint("TOPRIGHT")
bar.line:SetHeight(1)
bar.line:SetColorTexture(1, 1, 1, 0.07)

-- level progress along the bottom edge; hover for XP per hour this session
local xp = CreateFrame("Frame", nil, bar)
xp:SetPoint("BOTTOMLEFT", 0, 0)
xp:SetPoint("BOTTOMRIGHT", 0, 0)
xp:SetHeight(8)
xp:EnableMouse(true)
xp.bg = xp:CreateTexture(nil, "ARTWORK")
xp.bg:SetPoint("BOTTOMLEFT")
xp.bg:SetPoint("BOTTOMRIGHT")
xp.bg:SetHeight(3)
xp.bg:SetColorTexture(1, 1, 1, 0.06)
xp.rested = xp:CreateTexture(nil, "ARTWORK", nil, 1)
xp.rested:SetPoint("BOTTOMLEFT")
xp.rested:SetHeight(3)
Style.Fill(xp.rested, C.blue, 0.35)
xp.fill = xp:CreateTexture(nil, "ARTWORK", nil, 2)
xp.fill:SetPoint("BOTTOMLEFT")
xp.fill:SetHeight(3)
xp.fill:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)

local session = {}
function Card.XPStats()
    local cur, max = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
    local level = UnitLevel and UnitLevel("player") or 0
    local now = GetTime and GetTime() or 0
    if not session.start or (session.level ~= level and level < (session.level or 0)) then
        session.start, session.gained, session.level, session.last = now, 0, level, cur
    end
    if session.level ~= level then
        session.gained = session.gained + math.max(0, (session.lastMax or 0) - (session.last or 0)) + cur
        session.level = level
    elseif cur > (session.last or 0) then
        session.gained = session.gained + cur - session.last
    end
    session.last, session.lastMax = cur, max
    local elapsed = now - session.start
    local perHour = elapsed > 120 and session.gained / elapsed * 3600 or nil
    local minutes = perHour and perHour > 0 and (max - cur) / perHour * 60 or nil
    return { cur = cur, max = max, level = level, rested = GetXPExhaustion and GetXPExhaustion() or 0,
             perHour = perHour, minutes = minutes }
end

local function UpdateXP()
    local x = Card.XPStats()
    if x.max <= 0 or x.level >= 60 then xp:Hide() return end
    xp:Show()
    local w = xp:GetWidth() or 0
    if w <= 0 then w = Width() - 2 end
    xp.fill:SetWidth(math.max(1, w * x.cur / x.max))
    xp.rested:SetWidth(math.max(1, w * math.min(x.max, x.cur + (x.rested or 0)) / x.max))
end

xp:SetScript("OnEnter", function(self)
    local x = Card.XPStats()
    if x.max <= 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(fmt(L("Level %d: %d%%"), x.level, math.floor(x.cur / x.max * 100)), 1, 1, 1)
    GameTooltip:AddLine(fmt(L("%d / %d XP, %d to go"), x.cur, x.max, x.max - x.cur), 0.8, 0.8, 0.8)
    if (x.rested or 0) > 0 then GameTooltip:AddLine(fmt(L("Rested: %d XP"), x.rested), C.blue[1], C.blue[2], C.blue[3]) end
    if x.perHour then
        GameTooltip:AddLine(fmt(L("This session: %d XP/hour, about %d min to level"), math.floor(x.perHour),
            math.ceil(x.minutes or 0)), C.gold[1], C.gold[2], C.gold[3])
    else
        GameTooltip:AddLine(L("XP/hour shows after a couple of minutes of play"), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end)
xp:SetScript("OnLeave", function() GameTooltip:Hide() end)

local Btn = Style.IconButton
bar.prev = Btn(bar, "prev", L("Back one step"), function() Card.GoBack() end)
bar.prev:SetPoint("LEFT", 6, 0)
bar.next = Btn(bar, "next", L("Next step (an unfinished step is marked Skipped)"), function() Card.GoNext() end)
bar.next:SetPoint("LEFT", bar.prev, "RIGHT", 2, 0)
bar.find = Btn(bar, "target", L("Jump to the right guide and step for your level, zone and quests"),
    function() Card.here = nil; OXP.SmartStart.Run(false) end, L("Find my place"))
bar.find:SetPoint("LEFT", bar.next, "RIGHT", 6, 0)
bar.stop = Btn(bar, "prev", L("Stop the quest chain and go back to the guide"), function() Card.StopDetour() end, L("Back to guide"))
bar.stop:SetPoint("LEFT", bar.next, "RIGHT", 6, 0)
bar.stop:Hide()
bar.resume = Btn(bar, "next", L("Go back to the step you were on"), function() Card.Resume() end, L("Back to step"))
bar.resume:SetPoint("LEFT", bar.next, "RIGHT", 6, 0)
bar.resume:Hide()
bar.collapse = Btn(bar, "up", L("Collapse to one line"), function() Card.SetCollapsed(true) end)
bar.collapse:SetPoint("RIGHT", -20, 0)
bar.settings = Btn(bar, "gear", L("Settings"), function() OXP.Settings.Toggle() end)
bar.settings:SetPoint("RIGHT", bar.collapse, "LEFT", -2, 0)
-- the menu (UI/GuidePicker.lua): three dots, so it isn't taken for the
-- step list (that is "Step 16 / 52" in the header, and the menu's first row)
bar.menu = Btn(bar, "more", L("Menu: all steps, pick a guide, skipped quest chains, feedback"), function() OXP.GuidePicker.Toggle(bar.menu) end)
bar.menu:SetPoint("RIGHT", bar.settings, "LEFT", -2, 0)

-- "More" at the foot of the steps when they don't fit: the steps take the
-- room of "Up next" and scroll with the wheel. The card itself stays put.
local more = Style.TextButton(f, L("More"), L("Show all of this step. Mouse wheel scrolls; the card keeps its size."),
    function() Card.SetExpanded(not Card.expanded) end)
Card.more = more
more:SetHeight(18)
more:SetFrameLevel(f:GetFrameLevel() + 8)
more.back = more:CreateTexture(nil, "BACKGROUND", nil, -1) -- solid, so cut-off text doesn't show through
more.back:SetAllPoints()
more.back:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 1)
-- in a row of its own under the steps (the view is made that much
-- shorter), never on top of a line of text
local MORE_ROW = 22
more:SetPoint("TOPRIGHT", view, "BOTTOMRIGHT", -PAD, -2)
more:Hide()

function Card.SetExpanded(value)
    Card.expanded = value and true or false
    Card.scroll = 0
    Card.Refresh(true)
end

-- collapsed: one line with the badge, the step and an expand button
local mini = CreateFrame("Frame", nil, f)
mini:SetPoint("TOPLEFT", 1, -1)
mini:SetPoint("BOTTOMRIGHT", -1, 1)
mini.badge = Style.Badge(mini, 24)
mini.badge:SetPoint("LEFT", 10, 0)
mini.text = mini:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mini.text:SetPoint("LEFT", mini.badge, "RIGHT", 10, 0)
mini.text:SetJustifyH("LEFT")
mini.text:SetWordWrap(false)
Style.TextColor(mini.text, C.text)
mini.expand = Btn(mini, "down", L("Show the full guide"), function()
    if mini.empty then OXP.GuidePicker.ShowGuides() else Card.SetCollapsed(false) end
end)
mini:EnableMouse(false)
mini.expand:SetPoint("RIGHT", -4, 0)
mini.count = mini:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mini.count:SetPoint("RIGHT", mini.expand, "LEFT", -4, 0)
Style.TextColor(mini.count, C.dim)
mini.text:SetPoint("RIGHT", mini.count, "LEFT", -8, 0)
mini:Hide()

function Card.SetCollapsed(value)
    Settings().cardCollapsed = value and true or false
    Card.Refresh(true)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function SplitGuideName(guide)
    local name = Text.Strip(guide and guide.name or "")
    local range, zone = name:match("^(%d+%s*%-%s*%d+)%s+(.+)$")
    if range then return zone, (range:gsub("%-", "–")) end
    return name, ""
end

-- Shown whenever it's switched on: with no guide loaded yet it is one line
-- that opens Pick a guide, so it's never missing at login.
local function Visible()
    return Settings() ~= nil and Settings().cardShown and Card.enabled
end

-- a cheap fingerprint of what the card draws: it's only laid out again when
-- this changes (or every few seconds as a safety net)
Card.ticks = 0
function Card.Signature()
    local s = Settings()
    local parts = {
        tostring(Engine.GetGuide()), Engine.GetPosition() or 0, Card.ticks,
        Card.width or 0, Card.height or 0, s.cardScale or 1, s.fontSize or 0, s.font or "",
        s.cardCollapsed and 1 or 0, s.lockFrames and 1 or 0, Card.detour and 1 or 0,
        Card.sizing and 1 or 0, Engine.IsHeld() and 1 or 0,
        Card.here and Card.here.pos or 0, Card.expanded and 1 or 0,
        s.skin or "", s.cardOpacity or 1,
    }
    local travel = OXP.Travel.Lines()
    parts[#parts + 1] = travel and table.concat(travel, "|") or ""
    for _, pos in ipairs(Engine.GetActive()) do
        local step = Engine.GetSteps()[pos]
        parts[#parts + 1] = pos
        for _, g in ipairs(step.goals) do
            parts[#parts + 1] = OXP.Goals.State(g, step.marks)
            if g[1] == "complete" then
                local o = Quests.GetObjective(g.quest, g.obj)
                parts[#parts + 1] = o and o.text or ""
            end
        end
    end
    return table.concat(parts, "\031")
end

-- Run one part of the layout; an error in it is reported once and the rest
-- of the card is still laid out and sized.
local function Done(ok, ...)
    if ok then return true, ... end
    Card.ReportError((...))
    return false
end
local function Try(fn, ...) return Done(pcall(fn, ...)) end

-- Which steps the card shows: { { step, pos }, ... }, the chain walk's step
-- and its place in the walk, and the last guide position on screen.
local function PickSteps(current)
    local all = Engine.GetSteps()
    -- the step to do first, then those that stay open in the background
    local now_, side = {}, {}
    local lastPos = current
    for _, pos in ipairs(Engine.GetActive()) do
        local step = all[pos]
        if Card.StepRole(step, pos) == "now" then now_[#now_ + 1] = { step, pos } else side[#side + 1] = { step, pos } end
        if pos > lastPos then lastPos = pos end
    end
    local shown = now_
    for _, e in ipairs(side) do shown[#shown + 1] = e end
    -- a later step's turn-ins for the person you're standing by go on top
    local hereStep, herePos = Card.HereStep()
    if hereStep then table.insert(shown, 1, { hereStep, herePos }) end
    while #shown > MAX_BLOCKS do table.remove(shown) end

    -- walking through a quest chain: the card shows that instead
    local detourStep, detourIndex
    if Card.detour then
        local target
        detourStep, detourIndex, target = Card.DetourStep()
        if detourStep then
            shown = { { detourStep, nil } }
            -- a new table every refresh: only tell the arrow when the spot moves
            local want = target or NO_SPOT
            if not SameSpot(OXP.Target.override, want) then OXP.Target.SetOverride(want) end
        elseif OXP.Target.override then
            OXP.Target.SetOverride(nil) -- nothing left to show: back to the guide's arrow
        end
    end
    return shown, detourStep, detourIndex, lastPos
end

--- What the card has on top, as a key: a new key is a new step (the
--- fade plays, "More" closes and the text scrolls back to the top).
function Card.StepKey(shown, detourStep, detourIndex)
    if detourStep then return "chain:" .. tostring(Card.detour.target) .. ":" .. tostring(detourIndex) end
    local first = shown[1]
    if not first then return "none" end
    return tostring(Engine.GetGuide()) .. ":" .. tostring(first[2]) .. (first[1].here and ":here" or "")
end

local function LayoutCollapsed(shown, current, total)
    SetFont(mini.text, 2)
    SetFont(mini.count, 0)
    local first = shown[1]
    if first then
        mini.badge:SetKind(first[1].detour and "accept" or Card.StepKind(first[1]))
        mini.text:SetText(Text.Strip(first[1].detour and first[1].title or (Card.StepContent(first[1]))))
    else
        mini.badge:SetKind("travel")
        mini.text:SetText(L("Guide finished"))
    end
    mini.count:SetText(fmt("%d/%d", current, total))
end

local function LayoutBar(detourStep, current)
    local wide = Width() >= 360
    local slim = Width() < 300
    local bw = Width() < 250 and 26 or slim and 30 or 40
    for _, btn in ipairs({ bar.prev, bar.next, bar.menu, bar.settings, bar.collapse }) do btn:SetWidth(bw) end
    bar.collapse:ClearAllPoints()
    bar.collapse:SetPoint("RIGHT", slim and -18 or -20, 0)
    for _, btn in ipairs({ bar.find, bar.stop, bar.resume }) do
        btn:SetWidth(wide and 116 or bw)
        btn.label:SetShown(wide)
        btn.icon:ClearAllPoints()
        if wide then btn.icon:SetPoint("LEFT", 10, 0) else btn.icon:SetPoint("CENTER") end
    end
    local furthest = Engine.GetFurthest()
    local looking = not detourStep and Engine.IsHeld() and furthest and furthest > current
    if looking then bar.resume.label:SetText(fmt(L("Back to %d"), furthest)) end
    bar.find:SetShown(not detourStep and not looking)
    bar.stop:SetShown(detourStep ~= nil)
    bar.resume:SetShown(looking and true or false)
end

local function LayoutHeader(guide, current, total, detourStep, detourIndex)
    local zone, range = SplitGuideName(guide)
    SetFont(header.zone, -1)
    SetFont(header.range, -2)
    SetFont(header.step, -2)
    -- the name has the whole top row (cut with "..." only past the card's edge)
    header.zone:SetText(zone:upper())
    header.range:SetText(range ~= "" and fmt(L("Levels %s"), range) or "")
    header.range:SetShown(true)
    header.step:SetText(fmt(L("Step %d / %d"), current, total))
    local frac = total > 0 and current / total or 0
    if detourStep then
        header.zone:SetText(L("QUEST CHAIN"))
        header.range:SetText("")
        header.step:SetText(fmt("%d / %d", detourIndex, #Card.detour.ids))
        frac = detourIndex / math.max(#Card.detour.ids, 1)
    end
    -- big text: the header grows so its two rows never touch
    -- (a line is about 1.2x the font size; 7 px above, 7 below, 2 between)
    local need = math.ceil((Style.FontSize(-1) + Style.FontSize(-2)) * 1.2 + 16)
    header:SetHeight(math.max(HEADER_H, need))
    Card.SizeNav()
    Card.PaintNav()
    Card.SetProgress(math.max(1, (Width() - 2) * frac))
end

-- The blocks, one per step, top to bottom; returns their height.
local function LayoutBlocks(shown)
    local y = 0
    for i = 1, MAX_BLOCKS do
        local b, e = blocks[i], shown[i]
        if e then
            b = GetBlock(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            b:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
            local ok, h = Try(LayoutBlock, b, e[1], e[2], i == 1)
            if ok then
                y = y + h
                b:Show()
            else
                b:Hide()
            end
        elseif b then
            b:Hide()
        end
    end
    if #shown == 0 then y = 8 end
    return y
end

function Card.Refresh(force)
    if not Visible() then
        f:Hide()
        Card.lastSig = nil
        return
    end
    f:Show()
    local now = GetTime and GetTime() or 0
    local sig = Card.Signature()
    if not force and sig == Card.lastSig and now - (Card.lastFull or 0) < 3 then return end
    -- New text in a font (or size) the game hasn't drawn yet loads in the
    -- background and stays blank until it's set again (in game: the step's
    -- title missing until the card was resized). Once the step changes, set
    -- every text again a moment later and lay the card out again.
    -- (only for a new step or font, not every kill count: setting every
    -- text in OpenXP again costs a frame)
    local textKey = tostring(Engine.GetGuide()) .. ":" .. tostring(Engine.GetPosition()) .. ":" .. tostring(Card.detour)
        .. ":" .. tostring(Settings().font) .. ":" .. tostring(Settings().fontSize)
    if textKey ~= Card.textKey and Card.retexting then
        Card.textKey = textKey -- the re-text already on its way covers it
    elseif textKey ~= Card.textKey and C_Timer and C_Timer.After then
        Card.textKey = textKey
        Card.retexting = true
        -- twice: a slow disk can take longer than the first moment
        C_Timer.After(0.1, function()
            OXP.Fonts.Reapply()
            Card.Refresh(true)
        end)
        C_Timer.After(0.7, function()
            Card.retexting = false
            OXP.Fonts.Reapply()
            Card.Refresh(true)
        end)
    end
    Card.lastSig, Card.lastFull = sig, now
    if Card.FillStepList then Try(Card.FillStepList) end
    Try(UpdateXP)

    local s = Settings()
    local scale = s.cardScale or 1
    if f:GetScale() ~= scale then f:SetScale(scale) end
    -- the size is yours: set it back to what you chose (while you drag the
    -- grip the game sizes the frame and the layout follows)
    local guide = Engine.GetGuide()
    local collapsed = s.cardCollapsed or not guide
    grip:SetShown(not s.lockFrames and not collapsed)
    if not Card.sizing then
        Card.settingSize = true
        f:SetSize(Width(), collapsed and COLLAPSED_H or Height())
        Card.settingSize = false
    end

    local total = #Engine.GetSteps()
    local current = math.min(Engine.GetPosition() or 1, math.max(total, 1))

    local ok, shown, detourStep, detourIndex, lastPos = Try(PickSteps, current)
    if not ok then shown, detourStep, detourIndex, lastPos = {}, nil, nil, current end

    if collapsed then
        header:Hide(); progressBg:Hide(); progress:Hide(); view:Hide(); bar:Hide(); more:Hide()
        mini:Show()
        if guide then
            mini.empty = false
            Try(LayoutCollapsed, shown, current, total)
        else
            mini.empty = true
            SetFont(mini.text, 1)
            mini.badge:SetKind("travel")
            mini.text:SetText(L("No guide yet: click to pick one"))
            mini.count:SetText("")
        end
        return
    end

    -- a new step on top: fade it in, close "More", back to the top
    local key = Card.StepKey(shown, detourStep, detourIndex)
    if key ~= Card.stepKey then
        if Card.stepKey ~= nil and not Card.sizing then
            Card.PlayStepAnimation((current < (Card.keyPos or current)) and -1 or 1)
        end
        Card.keyPos = current
        Card.stepKey = key
        Card.expanded, Card.scroll = false, 0
    end

    mini:Hide()
    header:Show(); progressBg:Show(); progress:Show(); view:Show(); bar:Show()
    Try(LayoutBar, detourStep, current)
    Try(LayoutHeader, guide, current, total, detourStep, detourIndex)

    content:SetWidth(Width() - 2)
    Card.PlaceBody()
    local y = LayoutBlocks(shown)
    body:SetHeight(math.max(y, 1))
    local contentH = y + 4
    content:SetHeight(math.max(contentH, 1))

    -- all the room between the header and the buttons is the step's (the
    -- step list shows the other steps)
    local room = (Card.sizing and (f:GetHeight() or Height()) or Height()) - (1 + (header:GetHeight() or HEADER_H) + 2) - BAR_H
    local viewH = math.max(1, room)
    Card.overflow = contentH > viewH + 0.5
    -- cut off (or "More" open): the steps give up a row for the button
    if Card.overflow or Card.expanded then viewH = math.max(1, viewH - MORE_ROW) end
    view:SetHeight(viewH)
    Card.viewHeight, Card.contentHeight = viewH, contentH
    Card.maxScroll = math.max(0, contentH - viewH)
    if not Card.expanded then Card.scroll = 0 end
    Card.scroll = Clamp(Card.scroll or 0, 0, Card.maxScroll)
    view:SetVerticalScroll(Card.scroll)
    if Card.overflow or Card.expanded then
        more:SetLabel(Card.expanded and L("Less") or L("More"))
        more:SetWidth(math.max(48, (more.label:GetStringWidth() or 30) + 16))
        more:Show()
    else
        more:Hide()
    end
end
Card.Refresh = OXP.Perf.Wrap("card redraw", Card.Refresh)

---------------------------------------------------------------------------
-- Here first: a later step you're standing next to
---------------------------------------------------------------------------
-- The guide sends you across the zone for the next step while a later
-- turn-in is right where you stand (you finished its quest early). Do that
-- one first, then go back to the step you were on.

local HERE_RADIUS = 40  -- yards: that close to a later turn-in
local HERE_FAR = 120    -- yards: and the step you're on is at least this far
local HERE_AWAY = 90    -- yards: walked off from it, back to the guide
local HERE_AHEAD = 40   -- steps ahead to look
local HERE_GRACE = 30   -- seconds: after the turn-ins, how long pickups are still offered

--- A step that only turns in finished quests (and picks up what the same
--- person hands out next).
function Card.ReadyHere(step)
    local ready = false
    for _, g in ipairs(step.goals) do
        local kind = g[1]
        if kind == "turnin" then
            if not TurnedIn(g.quest) then
                if Quests.IsOnQuest(g.quest) and Quests.IsComplete(g.quest) then
                    ready = true
                else
                    return false
                end
            end
        elseif OXP.Goals.Blocks(kind) and kind ~= "accept" then
            return false
        end
    end
    return ready
end

local function HereTurnedIn(step)
    for _, g in ipairs(step.goals) do
        if g[1] == "turnin" and not TurnedIn(g.quest) then return false end
    end
    return true
end

-- Done once the turn-ins are in and either every pickup is taken, or you've
-- talked to them since (what they didn't offer isn't ready yet: it waits for
-- its step), or a little while has passed.
local function HereDone(step, h)
    if not HereTurnedIn(step) then return false end
    local now = GetTime and GetTime() or 0
    if h and (h.talked or (h.turnedAt and now - h.turnedAt > HERE_GRACE)) then return true end
    for _, g in ipairs(step.goals) do
        if g[1] == "accept" and not g.optional and OXP.Goals.State(g, step.marks) == "todo"
            and not QuestDB.Blocked(g.quest) and (Quests.FreeSlots() or 1) > 0 then return false end
    end
    return true
end

-- px, py, inst: player world position (tests pass it in)
--
-- Standing by the person a later step hands a finished quest in to: the
-- card shows that step on top ("While you're here": its turn-ins and the
-- quests the same person hands out) and the arrow points there, while the
-- guide stays on your step: nothing between is skipped. Gone once it's
-- done, you walk away or you move on.
function Card.CheckHere(px, py, inst)
    if not Engine.GetGuide() then Card.here = nil return end
    if not px then px, py, inst = OXP.Places.Player() end
    local steps = Engine.GetSteps()
    local cur = Engine.GetPosition()
    local h = Card.here
    local Dist = OXP.Places.Distance
    if h then
        local spot = steps[h.pos] and OXP.Areas.StepSpot(steps[h.pos])
        local away = spot and px and (inst ~= spot.instance or Dist(px, py, spot.wx, spot.wy) > HERE_AWAY)
        if steps[h.pos] and not h.handed and HereTurnedIn(steps[h.pos]) then
            h.handed, h.turnedAt = true, GetTime and GetTime() or 0
        end
        if h.guide ~= Engine.GetGuide() or cur ~= h.from or not steps[h.pos] or HereDone(steps[h.pos], h) or away then
            Card.here = nil
            Card.Refresh(true)
            return true
        end
        return
    end
    if Engine.IsHeld() or Card.detour or Card.returnTo or not px then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local spot = steps[cur] and OXP.Areas.StepSpot(steps[cur])
    if not spot then return end
    if spot.instance == inst and Dist(px, py, spot.wx, spot.wy) < HERE_FAR then return end
    for pos = cur + 1, math.min(#steps, cur + HERE_AHEAD) do
        local s = steps[pos]
        if Engine.StepState(pos) == "todo" and Card.ReadyHere(s) then
            local sp = OXP.Areas.StepSpot(s)
            if sp and sp.instance == inst and Dist(px, py, sp.wx, sp.wy) <= HERE_RADIUS then
                Card.here = { guide = Engine.GetGuide(), from = cur, pos = pos }
                Card.Refresh(true)
                return true
            end
        end
    end
end

--- The "while you're here" block: the later step's spot, its turn-ins for
--- finished quests and its pickups. nil when there's none.
function Card.HereStep()
    local h = Card.here
    local step = h and Engine.GetSteps()[h.pos]
    if not step then return nil end
    local goals = {}
    local free = Quests.FreeSlots()
    for _, g in ipairs(step.goals) do
        if g[1] == "goto" or g[1] == "target" then
            goals[#goals + 1] = g
        elseif g[1] == "turnin" and not TurnedIn(g.quest) and Quests.IsOnQuest(g.quest) and Quests.IsComplete(g.quest) then
            goals[#goals + 1] = g
        elseif g[1] == "accept" and OXP.Goals.State(g, step.marks) == "todo" and not QuestDB.Blocked(g.quest)
            and (OXP.Player.level or 1) >= ((QuestDB.Info(g.quest) or {}).r or 0) then
            -- only what fits in your quest log; the rest waits for that step
            if not free or free > 0 then
                goals[#goals + 1] = g
                if free then free = free - 1 end
            end
        end
    end
    return { here = true, goals = goals, marks = step.marks, index = step.index, data = step.data }, h.pos
end

---------------------------------------------------------------------------
-- The tick: chain walks, going back after "Get the quest", standing-by
-- steps, and the redraw
---------------------------------------------------------------------------

function Card.Tick()
    if not Card.enabled then return end
    local d = Card.detour
    if d then
        local g = Engine.GetGuide()
        if (g and g.key ~= d.guide) or DetourDone(d) then Card.StopDetour() end
    end
    local r = Card.returnTo
    if r then
        local cur = Engine.GetPosition()
        if Engine.GetGuide() ~= r.guide then
            Card.returnTo = nil
        elseif r.chain then
            if cur and cur >= r.pos then
                Card.returnTo = nil
            elseif not QuestDB.Blocked(r.quest) and (not r.needAccept or Quests.IsOnQuest(r.quest) or TurnedIn(r.quest)) then
                Card.returnTo = nil
                Engine.GoTo(r.pos, true)
            end
        elseif Quests.IsOnQuest(r.quest) then
            Card.returnTo = nil
            Engine.GoTo(r.pos, true)
        end
    end
    local ok, err = pcall(Card.CheckHere)
    if not ok then Card.ReportError(err) end
    ok, err = pcall(Card.Refresh)
    if not ok then Card.ReportError(err) end
end
Card.Tick = OXP.Perf.Wrap("card update", Card.Tick)

local elapsed = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    Card.Tick()
end)

OXP.Listen("SETTINGS_CHANGED", function() if Card.enabled then Card.ApplySkin() end end)
for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "QUESTS_CHANGED", "SETTINGS_CHANGED" }) do
    OXP.Listen(m, function()
        Card.ticks = Card.ticks + 1
        OXP.Soon("CARD", function() Card.Refresh() end)
    end)
end
OXP.On("PLAYER_XP_UPDATE", function() Card.ticks = Card.ticks + 1 end)

-- talking to the "while you're here" person ends once their window closes
local function TalkedHere()
    local h = Card.here
    if h and h.handed then h.talked = true end
end
OXP.On("GOSSIP_CLOSED", TalkedHere)
OXP.On("QUEST_FINISHED", TalkedHere)

---------------------------------------------------------------------------
-- Step list: every step of the guide, click one to jump there
-- (UI/StepNavigator.lua draws it)
---------------------------------------------------------------------------

Card.StepSummary = StepSummary

function Card.FillStepList()
    if OXP.StepNav and OXP.StepNav.IsShown() then OXP.StepNav.Refresh() end
end

function Card.ToggleStepList()
    if OXP.StepNav then OXP.StepNav.Toggle() end
    Card.PaintNav()
end

---------------------------------------------------------------------------
-- Turning on, and the settings window's buttons
---------------------------------------------------------------------------

--- Paints the card's own pieces in the chosen skin and background
--- (Settings > Guide card): the header band, the bar under the buttons and
--- the thin lines. Minimal, or the background at 0%, draws none of them.
function Card.ApplySkin()
    local s = Settings()
    local key = (s.skin or "midnight") .. ":" .. tostring(s.cardOpacity or 1)
    if Card.skinKey == key then return end
    Card.skinKey = key
    local skin = Style.skinKey == (s.skin or "midnight") and Style.skin or Style.ApplySkin(s.skin or "midnight")
    local o = Style.CardOpacity()
    local bare = Style.Frameless()
    local line = bare and 0 or skin.line * math.min(1, o * 1.4)
    Style.PaintBackdrop(f)
    header.bg:SetColorTexture(1, 1, 1, bare and 0 or skin.header * o)
    Card.PaintNav()
    Style.Fill(progress, C.blue, 1)
    progressBg:SetColorTexture(1, 1, 1, bare and 0.10 or (skin.header > 0 and 0.06 or 0.04))
    more.back:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], bare and 0.55 or math.min(1, C.bg[4] * o + 0.5))
    bar.bg:SetColorTexture(1, 1, 1, bare and 0 or (skin.header > 0 and 0.04 or 0) * o)
    bar.line:SetColorTexture(1, 1, 1, line)
    for _, b in pairs(blocks) do b.sep:SetColorTexture(1, 1, 1, line) end
    xp.bg:SetColorTexture(1, 1, 1, bare and 0.10 or 0.06)
    Style.Fill(xp.rested, C.blue, 0.35)
    Card.lineAlpha = line
    if OXP.ActionButtons and OXP.ActionButtons.ApplySkin then OXP.ActionButtons.ApplySkin() end
    if OXP.StepNav and OXP.StepNav.ApplySkin then OXP.StepNav.ApplySkin() end
    -- card text gets an outline when there's no background behind it
    Card.ticks = (Card.ticks or 0) + 1
end

function Card.Enable()
    Card.enabled = true
    local s = Settings()
    Card.ApplySkin()
    if s.cardPos then
        f:ClearAllPoints()
        f:SetPoint(s.cardPos[1], UIParent, s.cardPos[2], s.cardPos[3], s.cardPos[4])
    end
    if OXP.char.detour and OXP.char.detour.ids then Card.detour = OXP.char.detour end
    Card.width = s.cardWidth and Clamp(s.cardWidth, MIN_W, MAX_W) or nil
    Card.height = s.cardHeight and Clamp(s.cardHeight, MIN_H, MAX_H) or nil
    f:SetScale(s.cardScale or 1)
    Card.Refresh(true)
    -- once per character: Questie adds chains and levels
    if C_Timer and C_Timer.After then
        C_Timer.After(20, function()
            if _G.QuestieLoader or OXP.char.questieHint then return end
            OXP.char.questieHint = true
            OXP.Print("Tip: install the free Questie addon and OpenXP will show quest chains, quest levels and \"Do the chain\" on steps you're missing. Everything else works without it.")
        end)
    end
end

function Card.ResetPosition()
    local s = Settings()
    s.cardPos, s.cardWidth, s.cardHeight = nil, nil, nil
    Card.width, Card.height = nil, nil
    f:ClearAllPoints()
    f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
    f:SetSize(WIDTH, HEIGHT)
    Card.Refresh(true)
end

function Card.Toggle()
    Settings().cardShown = not Settings().cardShown
    Card.Refresh(true)
end

OXP.OnReady(Card.Enable)

---------------------------------------------------------------------------
-- /oxp step: what the card knows about the steps on screen
---------------------------------------------------------------------------

function Card.DebugStep()
    local out = {}
    local function say(...) out[#out + 1] = table.concat({ ... }, " ") end
    local guide = Engine.GetGuide()
    say("OpenXP", tostring(OXP.version), "guide:", guide and guide.key or "none", "step:", tostring(Engine.GetPosition()),
        "held:", tostring(Engine.IsHeld()))
    say("Questie:", tostring(QuestDB.Questie() ~= nil), "last card error:", tostring(Card.lastError))
    say("chain walk:", Card.detour and ("on, target " .. tostring(Card.detour.target)) or "off")
    for _, pos in ipairs(Engine.GetActive()) do
        local step = Engine.GetSteps()[pos]
        say("-- step", pos, "(guide step " .. step.index .. ")", step.completewith and "(along the way)" or "")
        for _, g in ipairs(step.goals) do
            if OXP.Goals.Blocks(g[1]) then
                local line = "   " .. g[1] .. (g.quest and (" q" .. g.quest) or "") .. " " .. OXP.Goals.State(g, step.marks)
                if g.quest then
                    line = line .. " inLog=" .. tostring(Quests.IsOnQuest(g.quest)) .. " done=" .. tostring(TurnedIn(g.quest))
                        .. " blockedBy=" .. tostring(QuestDB.Blocked(g.quest))
                end
                say(line .. (g.optional and " optional" or ""))
            end
        end
        local pr = QuestDB.StepProblem(step)
        say("   problem:", pr and (pr.kind .. " q" .. tostring(pr.quest)) or "none")
    end
    local text = table.concat(out, "\n")
    print(text)
    return text
end

OXP.AddCommand("step", "print what OpenXP knows about the steps on screen (for bug reports)", function() Card.DebugStep() end)
OXP.AddCommand("card", "hide or show the guide card", function() Card.Toggle() end)

--- /oxp uidebug: the card's size against the saved size, and how tall its
--- content is (to check in game that the card keeps its size).
function Card.UIDebug()
    local s = Settings()
    local text = fmt("OpenXP %s card: %dx%d (scale %.2f), saved %sx%s, content %d in a %d view, %s%s%s",
        tostring(OXP.version), math.floor((f:GetWidth() or 0) + 0.5), math.floor((f:GetHeight() or 0) + 0.5),
        f:GetScale() or 1, tostring(s.cardWidth or "default " .. WIDTH), tostring(s.cardHeight or "default " .. HEIGHT),
        math.floor((Card.contentHeight or 0) + 0.5), math.floor((Card.viewHeight or 0) + 0.5),
        Card.overflow and "cut off (More)" or "fits", Card.expanded and ", More open" or "",
        f.DoesClipChildren and (f:DoesClipChildren() and ", clips" or ", NOT clipping") or "")
    OXP.Print(text)
    return text
end
OXP.AddCommand("uidebug", "print the guide card's size, saved size and content height", function() Card.UIDebug() end)
OXP.AddCommand("reset", "put the guide card and arrow back in their default spots", function()
    Card.ResetPosition()
    OXP.Arrow.ResetPosition()
end)
