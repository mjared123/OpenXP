-- OpenXP guide card and arrow
--
-- OpenXP's own guide window: a compact card that shows the steps you're on
-- with a type badge each, check marks for finished lines, small bars for
-- kill and loot counts, an "Up next" line and a row of buttons. The engine
-- still runs the RestedXP-style window underneath (it drives step logic);
-- in this layout that window is parked off screen and the card reads the
-- same step data.
--
-- The arrow gets the same treatment: a pointer in a round dial with the
-- distance in large text, turning into a green check on arrival.
--
-- This is OpenXP's only layout; the old window is never shown.

local addonName, addon = ...
local L = addon.locale.Get
local fmt = string.format

local TEX = "Interface/AddOns/" .. addonName .. "/Textures/Card/"
local WHITE = "Interface/Buttons/WHITE8X8"
local FONT = "Fonts\\ARIALN.TTF"
local WIDTH = 330 -- default; the card can be resized
local MIN_W, MIN_H, MAX_W, MAX_H = 290, 120, 640, 900
local MAX_UPNEXT = 12
local PAD = 12
local MAX_BLOCKS = 4
local MAX_LINES = 8

local C = {
    bg = {16 / 255, 17 / 255, 21 / 255, 0.9},
    border = {150 / 255, 160 / 255, 180 / 255, 0.35},
    text = {0.92, 0.93, 0.95},
    dim = {0.62, 0.64, 0.70},
    faint = {0.54, 0.56, 0.61},
    blue = {90 / 255, 184 / 255, 1},
    gold = {242 / 255, 195 / 255, 92 / 255},
    orange = {1, 112 / 255, 67 / 255},
    cyan = {38 / 255, 198 / 255, 218 / 255},
    purple = {179 / 255, 157 / 255, 219 / 255},
    green = {61 / 255, 187 / 255, 122 / 255},
}

local card = {}
addon.card = card

local function Profile()
    return addon.settings and addon.settings.profile
end

function card.IsEnabled()
    return Profile() ~= nil and not (addon.v2 and addon.v2:IsGuideWindowEnabled())
end

local function Width()
    return card.width or WIDTH
end

local function FontSize(offset)
    local p = Profile()
    return ((p and p.guideFontSize) or 12) + (offset or 0)
end

local function SetFont(fs, offset, flags)
    fs:SetFont(FONT, FontSize(offset), flags or "")
end

local function Tint(tex, color, alpha)
    tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function StripCodes(text)
    return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local f = CreateFrame("Frame", "OpenXPCard", UIParent, "BackdropTemplate")
card.frame = f
f:SetSize(WIDTH, 120)
f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
               insets = {left = 1, right = 1, top = 1, bottom = 1}})
f:SetBackdropColor(unpack(C.bg))
f:SetBackdropBorderColor(unpack(C.border))
f:Hide()

f:SetScript("OnDragStart", function(self)
    local p = Profile()
    if p and p.lockFrames then return end
    self:StartMoving()
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p = Profile()
    if p then
        local point, _, relPoint, x, y = self:GetPoint()
        p.openxpCardPos = {point, relPoint, x, y}
    end
end)
f:SetResizable(true)
if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
else
    if f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
    if f.SetMaxResize then f:SetMaxResize(MAX_W, MAX_H) end
end

-- Resize grip in the bottom right corner
local grip = CreateFrame("Button", nil, f)
card.grip = grip
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(f:GetFrameLevel() + 10)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local p = Profile()
    if p and p.lockFrames then return end
    card.sizing = true
    f:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    if not card.sizing then return end
    f:StopMovingOrSizing()
    card.sizing = false
    card.width = math.floor(math.max(MIN_W, math.min(MAX_W, f:GetWidth() or WIDTH)) + 0.5)
    local p = Profile()
    local collapsed = p and p.openxpCardCollapsed
    if not collapsed then
        card.height = math.floor(math.max(MIN_H, math.min(MAX_H, f:GetHeight() or MIN_H)) + 0.5)
    end
    if p then
        p.openxpCardWidth = card.width
        if not collapsed then p.openxpCardHeight = card.height end
        local point, _, relPoint, x, y = f:GetPoint()
        if point then p.openxpCardPos = {point, relPoint, x, y} end
    end
    card.Refresh(true)
end)
grip:SetScript("OnUpdate", function()
    if card.sizing then
        card.width = math.max(MIN_W, math.min(MAX_W, f:GetWidth() or WIDTH))
        card.Refresh(true)
    end
end)
grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L("Drag to resize"), 1, 1, 1)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

f:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and addon.RXPFrame and addon.RXPFrame.DropDownMenu then
        addon.RXPFrame.DropDownMenu()
    end
end)

-- Header: dot, ZONE, level range ............ Step 12 / 82
local header = CreateFrame("Frame", nil, f)
header:SetPoint("TOPLEFT", 1, -1)
header:SetPoint("TOPRIGHT", -1, -1)
header:SetHeight(28)

header.dot = header:CreateTexture(nil, "ARTWORK")
header.dot:SetTexture(TEX .. "filledcircle")
header.dot:SetSize(9, 9)
header.dot:SetPoint("LEFT", PAD - 1, 0)
Tint(header.dot, C.blue)

header.zone = header:CreateFontString(nil, "OVERLAY")
header.zone:SetPoint("LEFT", header.dot, "RIGHT", 7, 0)
header.zone:SetTextColor(unpack(C.text))

header.range = header:CreateFontString(nil, "OVERLAY")
header.range:SetPoint("LEFT", header.zone, "RIGHT", 6, 0)
header.range:SetTextColor(unpack(C.dim))

header.step = header:CreateFontString(nil, "OVERLAY")
header.step:SetPoint("RIGHT", -PAD + 1, 0)
header.step:SetTextColor(unpack(C.dim))
header.zone:SetJustifyH("LEFT")
header.zone:SetWordWrap(false)

local progressBg = f:CreateTexture(nil, "ARTWORK")
progressBg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
progressBg:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
progressBg:SetHeight(2)
progressBg:SetColorTexture(1, 1, 1, 0.08)

local progress = f:CreateTexture(nil, "OVERLAY")
progress:SetPoint("TOPLEFT", progressBg, "TOPLEFT")
progress:SetHeight(2)
progress:SetWidth(1)
progress:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 1)

local body = CreateFrame("Frame", nil, f)
body:SetPoint("TOPLEFT", progressBg, "BOTTOMLEFT", 0, 0)
body:SetPoint("TOPRIGHT", progressBg, "BOTTOMRIGHT", 0, 0)
body:SetHeight(10)

---------------------------------------------------------------------------
-- Step blocks
---------------------------------------------------------------------------

local BADGES = {
    accept = {glyph = "!", color = C.gold},
    turnin = {glyph = "?", color = C.gold},
    kill = {icon = "cross", color = C.orange},
    loot = {icon = "diamond", color = C.cyan},
    travel = {icon = "travel", color = C.blue},
    town = {icon = "house", color = C.purple},
}

local function MakeBadge(parent, size)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    b.fill = b:CreateTexture(nil, "BACKGROUND")
    b.fill:SetTexture(TEX .. "disc")
    b.fill:SetAllPoints()
    b.ring = b:CreateTexture(nil, "BORDER")
    b.ring:SetTexture(TEX .. "ring")
    b.ring:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(size * 0.55, size * 0.55)
    b.glyph = b:CreateFontString(nil, "OVERLAY")
    b.glyph:SetPoint("CENTER", 0, 0)
    function b:SetKind(kind)
        local k = BADGES[kind] or BADGES.travel
        Tint(self.fill, k.color, 0.16)
        Tint(self.ring, k.color, 1)
        if k.glyph then
            self.icon:Hide()
            self.glyph:SetFont(FONT, math.floor(size * 0.6), "")
            self.glyph:SetText(k.glyph)
            self.glyph:SetTextColor(unpack(k.color))
            self.glyph:Show()
        else
            self.glyph:Hide()
            self.icon:SetTexture(TEX .. k.icon)
            Tint(self.icon, k.color)
            self.icon:Show()
        end
    end
    return b
end

local blocks = {}
card.blocksForTest = blocks

local function NewLine(block)
    local line = CreateFrame("Frame", nil, block)
    line.mark = line:CreateTexture(nil, "ARTWORK")
    line.mark:SetSize(13, 13)
    line.mark:SetPoint("TOPLEFT", 0, -1)
    line.text = line:CreateFontString(nil, "OVERLAY")
    line.text:SetPoint("TOPLEFT", line.mark, "TOPRIGHT", 7, 1)
    line.text:SetJustifyH("LEFT")
    line.text:SetJustifyV("TOP")
    line.barBg = line:CreateTexture(nil, "ARTWORK")
    line.barBg:SetHeight(5)
    line.barBg:SetColorTexture(1, 1, 1, 0.1)
    line.bar = line:CreateTexture(nil, "OVERLAY")
    line.bar:SetHeight(5)
    line.bar:SetPoint("LEFT", line.barBg, "LEFT")
    line.count = line:CreateFontString(nil, "OVERLAY")
    line.count:SetTextColor(unpack(C.dim))
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
    b.sep:SetColorTexture(1, 1, 1, 0.07)
    b.badge = MakeBadge(b, 34)
    b.badge:SetPoint("TOPLEFT", PAD, -10)
    b.title = b:CreateFontString(nil, "OVERLAY")
    b.title:SetPoint("TOPLEFT", b.badge, "TOPRIGHT", 12, -1)
    b.title:SetJustifyH("LEFT")
    b.title:SetJustifyV("TOP")
    b.title:SetTextColor(unpack(C.text))
    b.lines = {}
    b:EnableMouse(false)
    blocks[i] = b
    return b
end

-- What kind of step is this, for the badge
local function StepKind(step)
    local has = {}
    local textAll = ""
    for _, e in ipairs(step.elements or {}) do
        if e.tag then has[e.tag] = true end
        if e.textOnly and e.text then textAll = textAll .. " " .. StripCodes(e.text):lower() end
    end
    if has.accept then return "accept" end
    if has.turnin then return "turnin" end
    if has.complete or has.collect or has.mob or has.unitscan then
        if textAll:find("loot") or textAll:find("collect") or textAll:find("click") or
            textAll:find("pick") or has.collect then
            return "loot"
        end
        return "kill"
    end
    if has.home or has.hs or has.trainer or has.train or has.vendor or has.bindlocation then
        return "town"
    end
    return "travel"
end

local function ElementText(e)
    local text = e.text
    if not text or text == "" or text == " " then return end
    if addon.ReplaceNpcIds then text = addon.ReplaceNpcIds(L(text), e) end
    return text
end

-- Title (the ">>" instruction) and checklist lines of a step
local function StepContent(step)
    local title, lines = nil, {}
    for _, e in ipairs(step.elements or {}) do
        local text = ElementText(e)
        if text then
            if e.textOnly and not title then
                title = text
            elseif not e.textOnly then
                tinsert(lines, {text = text, done = e.completed or e.skip, element = e})
            elseif e.textOnly then
                tinsert(lines, {text = text, done = false, plain = true, element = e})
            end
        end
    end
    if not title and lines[1] then
        title = lines[1].text
        table.remove(lines, 1)
    end
    return title or (step.title or fmt(L("Step %d"), step.index or 0)), lines
end

---------------------------------------------------------------------------
-- Steps for a quest that isn't in the log
---------------------------------------------------------------------------
-- A turn in or kill step for a quest you never picked up (skipped the
-- pickup step, Find my place jumped past it, the giver didn't offer it)
-- would send you somewhere for nothing. The card says so and offers to
-- skip the step or go back to where the quest is picked up.

local function QuestIdOf(e)
    local id = tonumber(e.questId)
    if id and id > 0 then return id end
end

-- Returns the quest id and its name when the step needs a quest you don't have
function card.MissingQuest(step)
    if not (step and step.elements and addon.IsOnQuest) then return end
    for _, e in ipairs(step.elements) do
        if (e.tag == "turnin" or e.tag == "complete") and not e.skipIfMissing and not e.completed then
            local id = QuestIdOf(e)
            if id and not addon.IsOnQuest(id) and
                not (addon.IsQuestTurnedIn and addon.IsQuestTurnedIn(id)) then
                local name = (e.title ~= "" and e.title) or
                                 (addon.GetQuestName and addon.GetQuestName(id)) or nil
                return id, name
            end
        end
    end
end

-- Pickup steps for quests you can't get yet (a pre-quest you skipped, or
-- one you did that locks this one out) send you to a giver who has nothing
-- for you. DB/forever/QuestPrereqs.lua lists what each guide quest needs.
local function TurnedIn(id)
    return addon.IsQuestTurnedIn and addon.IsQuestTurnedIn(math.abs(id))
end

-- Returns the quest that has to be done first, or nil when it can be picked up
function card.QuestBlocked(id)
    local pre = addon.openxpPrereqs and addon.openxpPrereqs[id]
    if not pre then return end
    if (addon.IsOnQuest and addon.IsOnQuest(id)) or TurnedIn(id) then return end
    if pre.any then
        local ok = false
        for _, q in ipairs(pre.any) do
            if TurnedIn(q) then ok = true; break end
        end
        if not ok then return pre.any[1] end
    end
    if pre.all then
        for _, q in ipairs(pre.all) do
            if not TurnedIn(q) then return q end
        end
    end
    if pre.excl then
        for _, q in ipairs(pre.excl) do
            q = math.abs(q)
            if TurnedIn(q) or (addon.IsOnQuest and addon.IsOnQuest(q)) then return q end
        end
    end
end

-- The step in this guide where the quest is picked up, nearest one before
-- `before` first
function card.FindAcceptStep(guide, questId, before)
    local steps = guide and guide.steps
    if not steps then return end
    local function accepts(step)
        for _, e in ipairs(step and step.elements or {}) do
            if e.tag == "accept" and QuestIdOf(e) == questId then return true end
        end
    end
    for i = math.min(before - 1, #steps), 1, -1 do
        if accepts(steps[i]) then return i end
    end
    for i = before + 1, #steps do
        if accepts(steps[i]) then return i end
    end
end

local function TextButton(parent, text, tip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(22)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(1, 1, 1, 0.08)
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetPoint("CENTER")
    btn.label:SetFont(FONT, 12, "")
    btn.label:SetTextColor(unpack(C.text))
    btn.label:SetText(text)
    btn:SetWidth(math.max(70, (btn.label:GetStringWidth() or 60) + 18))
    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.16)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.08)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

---------------------------------------------------------------------------
-- Quest chains: what a step needs first, and a walk through it
---------------------------------------------------------------------------

local function QuestInfo(id)
    return addon.openxpQuestInfo and addon.openxpQuestInfo[id]
end

local function QuestName(id)
    local info = QuestInfo(id)
    return (info and info.n) or (addon.GetQuestName and addon.GetQuestName(id)) or fmt("#%d", id)
end

-- Earlier quests in the chain that you still have to turn in, in order
function card.MissingChain(id)
    local out = {}
    for _, q in ipairs(addon.openxpChains and addon.openxpChains[id] or {}) do
        if not TurnedIn(q) then tinsert(out, q) end
    end
    return out
end

-- What's wrong with a step, if anything:
--   {kind = "missing", quest}  turn in / kill step for a quest not in the log
--   {kind = "chain", quest, chain, needAccept}  quests before this one aren't done
--   {kind = "locked", quest, by}  a quest you did locks this one out
function card.StepProblem(step)
    if not (step and step.elements) then return end
    for _, e in ipairs(step.elements) do
        local id = QuestIdOf(e)
        if id and not e.completed then
            local needAccept
            if e.tag == "accept" then
                needAccept = false
            elseif (e.tag == "turnin" or e.tag == "complete") and not e.skipIfMissing and
                not (addon.IsOnQuest and addon.IsOnQuest(id)) and not TurnedIn(id) then
                needAccept = true
            end
            if needAccept ~= nil then
                local blocker = card.QuestBlocked(id)
                if blocker then
                    local pre = addon.openxpPrereqs[id]
                    local isExcl = false
                    for _, q in ipairs(pre.excl or {}) do
                        if math.abs(q) == blocker then isExcl = true end
                    end
                    if isExcl then
                        return {kind = "locked", quest = id, by = blocker}
                    end
                    return {kind = "chain", quest = id, chain = card.MissingChain(id),
                            needAccept = needAccept}
                elseif needAccept then
                    return {kind = "missing", quest = id}
                end
            end
        end
    end
end

-- Start a walk through the quests a step needs. mode "have" ends once the
-- target quest is in your log, "available" once it can be picked up.
function card.StartDetour(target, ids, mode)
    local guide = addon.currentGuide
    card.detour = {target = target, ids = ids, mode = mode,
                   guide = guide and guide.name, step = addon.GetGuideProgress and addon.GetGuideProgress() or nil}
    local p = Profile()
    if p then p.openxpDetour = card.detour end
    card.Refresh(true)
end

function card.StopDetour()
    card.detour = nil
    card.detourTarget = nil
    local p = Profile()
    if p then p.openxpDetour = nil end
    if addon.UpdateGotoSteps then pcall(addon.UpdateGotoSteps) end
    card.Refresh(true)
end

local function DetourDone(d)
    if d.mode == "have" then
        return (addon.IsOnQuest and addon.IsOnQuest(d.target)) or TurnedIn(d.target)
    end
    return not card.QuestBlocked(d.target)
end

local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local function SpotElement(spot, title)
    if not (spot and HBD and spot[2] and spot[2] > 0) then return end
    local wx, wy, instance = HBD:GetWorldCoordinatesFromZone(spot[3] / 100, spot[4] / 100, spot[2])
    if not wx then return end
    return {wx = wx, wy = wy, instance = instance, title = title or spot[1], arrow = true}
end

local function ObjectivesOf(id)
    local list = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
    return list or {}
end

-- The quest of the walk you're on now, and the step the card shows for it
function card.DetourStep()
    local d = card.detour
    if not d then return end
    local index, id
    for i, q in ipairs(d.ids) do
        local onIt = addon.IsOnQuest and addon.IsOnQuest(q)
        if not TurnedIn(q) and not (q == d.target and onIt) then
            index, id = i, q
            break
        end
    end
    if not id then return end
    local info = QuestInfo(id) or {}
    local name = QuestName(id)
    local level = info.l and info.l > 0 and fmt(" |cFF9EA3B3(lvl %d)|r", info.l) or ""
    local elements, target
    if not (addon.IsOnQuest and addon.IsOnQuest(id)) then
        local who = info.s and info.s[1] or "?"
        local where = info.s and info.s[2] == 0 and L("Loot or use %s to start it") or L("Get it from %s")
        elements = {
            {textOnly = true, text = fmt(L("Pick up %s"), name) .. level},
            {tag = "accept", text = fmt(where, who)},
        }
        if UnitLevel and info.r and UnitLevel("player") < info.r then
            tinsert(elements, {textOnly = true, text = fmt(L("|cFFF2C35CYou need level %d for this quest|r"), info.r)})
        end
        target = SpotElement(info.s)
    else
        local objs = ObjectivesOf(id)
        local open = false
        for _, o in ipairs(objs) do if not o.finished then open = true end end
        if open then
            elements = {{textOnly = true, text = fmt(L("Do %s"), name) .. level}}
            for _, o in ipairs(objs) do
                tinsert(elements, {tag = "complete", text = o.text or "", completed = o.finished})
            end
            local spot = info.o and info.o[1]
            target = SpotElement(spot)
        else
            local who = info.f and info.f[1] or "?"
            elements = {
                {textOnly = true, text = fmt(L("Turn in %s"), name) .. level},
                {tag = "turnin", text = fmt(L("Talk to %s"), who)},
            }
            target = SpotElement(info.f)
        end
    end
    return {index = nil, detour = true, elements = elements}, index, target
end

local function GetWarn(b)
    if b.warn then return b.warn end
    local w = CreateFrame("Frame", nil, b)
    w.text = w:CreateFontString(nil, "OVERLAY")
    w.text:SetPoint("TOPLEFT")
    w.text:SetJustifyH("LEFT")
    w.text:SetTextColor(unpack(C.gold))
    w.list = w:CreateFontString(nil, "OVERLAY")
    w.list:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -4)
    w.list:SetJustifyH("LEFT")
    w.list:SetTextColor(unpack(C.dim))
    w.get = TextButton(w, L("Get the quest"),
        L("Go and pick this quest up. Once you have it the guide brings you back here."),
        function()
            local m = b.missing
            if not (m and addon.currentGuide) then return end
            if m.accept then
                card.returnTo = {guide = addon.currentGuide, step = m.step, quest = m.quest}
                addon.SetStep(m.accept)
            else
                card.StartDetour(m.quest, {m.quest}, "have")
            end
        end)
    w.chain = TextButton(w, L("Do the chain"),
        L("Walk through the earlier quests in this chain, with the arrow. When they're done the guide picks up here again."),
        function()
            local m = b.missing
            if not m then return end
            local ids = {}
            for _, q in ipairs(m.chain or {}) do tinsert(ids, q) end
            if m.needAccept then tinsert(ids, m.quest) end
            card.StartDetour(m.quest, ids, m.needAccept and "have" or "available")
        end)
    w.skip = TextButton(w, L("Skip this step"), L("Move on without this quest"), function()
        local m = b.missing
        if m and addon.currentGuide then addon.SetStep(m.step + 1) end
    end)
    b.warn = w
    return w
end

local function LayoutBlock(b, step, first)
    local textWidth = Width() - PAD * 2 - 34 - 12
    b.sep:SetShown(not first)
    b.badge:SetKind(StepKind(step))

    local title, lines = StepContent(step)
    SetFont(b.title, 3)
    b.title:SetWidth(textWidth)
    b.title:SetText(title)
    local y = 11 + b.title:GetStringHeight() + 7

    for i = 1, MAX_LINES do
        local line = b.lines[i]
        local data = lines[i]
        if data then
            line = line or NewLine(b)
            b.lines[i] = line
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", b.title, "TOPLEFT", 0, -(y - 11))
            line:SetPoint("RIGHT", b, "RIGHT", -PAD, 0)
            SetFont(line.text, 1)
            SetFont(line.count, 0)
            line.text:SetWidth(textWidth - 20)

            local plain = StripCodes(data.text)
            local have, need = plain:match("(%d+)%s*/%s*(%d+)%s*$")
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
            if data.done then
                line.text:SetTextColor(unpack(C.faint))
                line:SetAlpha(0.7)
            else
                line.text:SetTextColor(unpack(C.text))
                line:SetAlpha(1)
            end

            local h = line.text:GetStringHeight()
            if have and need and need > 1 and not data.done then
                -- kill/loot counts get a small bar under the text
                line.barBg:ClearAllPoints()
                line.barBg:SetPoint("TOPLEFT", line.text, "BOTTOMLEFT", 0, -5)
                line.barBg:SetPoint("RIGHT", line, "RIGHT", -44, 0)
                line.barBg:Show()
                local w = math.max(1, (textWidth - 64) * math.min(have / need, 1))
                line.bar:SetWidth(w)
                local kindColor = (BADGES[StepKind(step)] or BADGES.travel).color
                line.bar:SetColorTexture(kindColor[1], kindColor[2], kindColor[3], 1)
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

    local problem = step.index and not step.detour and card.StepProblem(step)
    if problem then
        local w = GetWarn(b)
        local id = problem.quest
        local m = {quest = id, step = step.index, chain = problem.chain, needAccept = problem.needAccept}
        local text, list, buttons = nil, nil, {}
        if problem.kind == "missing" then
            m.accept = card.FindAcceptStep(addon.currentGuide, id, step.index)
            if not m.accept and not (QuestInfo(id) and QuestInfo(id).s) then
                buttons = {w.skip}
            else
                buttons = {w.get, w.skip}
            end
            text = fmt(L("You don't have %s yet"), QuestName(id))
        elseif problem.kind == "locked" then
            text = fmt(L("You can't get %s: doing %s locked it out"), QuestName(id), QuestName(problem.by))
            buttons = {w.skip}
        else
            local chain = problem.chain or {}
            if #chain == 0 then
                text = fmt(L("You can't pick up %s yet"), QuestName(id))
                buttons = {w.skip}
            else
                text = fmt(#chain == 1 and L("%s is part of a quest chain: 1 quest to do first") or
                               L("%s is part of a quest chain: %d quests to do first"), QuestName(id), #chain)
                local rows = {}
                for i, q in ipairs(chain) do
                    if i > 5 then
                        tinsert(rows, fmt(L("+ %d more"), #chain - 5))
                        break
                    end
                    local info = QuestInfo(q)
                    local onIt = addon.IsOnQuest and addon.IsOnQuest(q)
                    tinsert(rows, fmt("%d. %s%s%s", i, QuestName(q),
                                      info and info.l and info.l > 0 and fmt(" (lvl %d)", info.l) or "",
                                      onIt and L(" - in your log") or ""))
                end
                list = table.concat(rows, "\n")
                buttons = {w.chain, w.skip}
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
        w.get:Hide(); w.chain:Hide(); w.skip:Hide()
        local anchor = list and w.list or w.text
        for i, btn in ipairs(buttons) do
            btn:ClearAllPoints()
            if i == 1 then
                btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
            else
                btn:SetPoint("LEFT", buttons[i - 1], "RIGHT", 6, 0)
            end
            btn:Show()
        end
        local h = w.text:GetStringHeight() + (list and (w.list:GetStringHeight() + 4) or 0) + 6 + 22
        w:SetHeight(h)
        w:Show()
        y = y + h + 8
    else
        b.missing = nil
        if b.warn then b.warn:Hide() end
    end

    local height = math.max(y + 4, 34 + 20)
    b:SetHeight(height)
    return height
end

---------------------------------------------------------------------------
-- Up next and the button bar
---------------------------------------------------------------------------

local upNext = CreateFrame("Frame", nil, f)
upNext.sep = upNext:CreateTexture(nil, "ARTWORK")
upNext.sep:SetPoint("TOPLEFT", PAD, 0)
upNext.sep:SetPoint("TOPRIGHT", -PAD, 0)
upNext.sep:SetHeight(1)
upNext.sep:SetColorTexture(1, 1, 1, 0.07)
upNext.label = upNext:CreateFontString(nil, "OVERLAY")
upNext.label:SetPoint("TOPLEFT", PAD, -10)
upNext.label:SetTextColor(unpack(C.dim))
upNext.text = upNext:CreateFontString(nil, "OVERLAY")
upNext.text:SetPoint("TOPLEFT", upNext.label, "TOPRIGHT", 8, 1)
upNext.text:SetJustifyH("LEFT")
upNext.text:SetTextColor(unpack(C.dim))
upNext.text:SetWordWrap(false)
upNext.lines = {upNext.text}
local function UpNextLine(i)
    local line = upNext.lines[i]
    if not line then
        line = upNext:CreateFontString(nil, "OVERLAY")
        line:SetJustifyH("LEFT")
        line:SetTextColor(unpack(C.dim))
        line:SetWordWrap(false)
        upNext.lines[i] = line
    end
    return line
end

local bar = CreateFrame("Frame", nil, f)
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

local function MakeButton(parent, icon, tip, onClick, label)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(label and 116 or 40, 30)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetTexture(WHITE)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetTexture(TEX .. icon)
    btn.icon:SetSize(16, 16)
    if label then
        btn.bg:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0.16)
        btn.icon:SetPoint("LEFT", 10, 0)
        Tint(btn.icon, {159 / 255, 212 / 255, 1})
        btn.label = btn:CreateFontString(nil, "OVERLAY")
        btn.label:SetFont(FONT, 13, "")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.label:SetText(label)
        btn.label:SetTextColor(159 / 255, 212 / 255, 1)
    else
        btn.bg:SetVertexColor(1, 1, 1, 0)
        btn.icon:SetPoint("CENTER")
        Tint(btn.icon, {0.87, 0.88, 0.92})
    end
    btn.baseAlpha = label and 0.16 or 0
    btn:SetScript("OnEnter", function(self)
        self.bg:SetAlpha(1)
        self.bg:SetVertexColor(1, 1, 1, 0.1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        if label then
            self.bg:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0.16)
        else
            self.bg:SetVertexColor(1, 1, 1, 0)
        end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function CurrentStep()
    return addon.GetGuideProgress and addon.GetGuideProgress() or 1
end

bar.prev = MakeButton(bar, "prev", L("Back one step"), function()
    if addon.currentGuide then addon.SetStep(math.max(1, CurrentStep() - 1)) end
end)
bar.prev:SetPoint("LEFT", 6, 0)
bar.next = MakeButton(bar, "next", L("Skip this step"), function()
    if addon.currentGuide then addon.SetStep(CurrentStep() + 1) end
end)
bar.next:SetPoint("LEFT", bar.prev, "RIGHT", 2, 0)
bar.find = MakeButton(bar, "target", L("Jump to the right guide and step for your level, zone and quests"),
                      function() if addon.smartStart then addon.smartStart.Run() end end, L("Find my place"))
bar.find:SetPoint("LEFT", bar.next, "RIGHT", 6, 0)
bar.stop = MakeButton(bar, "prev", L("Stop the quest chain and go back to the guide"),
                      function() card.StopDetour() end, L("Back to guide"))
bar.stop:SetPoint("LEFT", bar.next, "RIGHT", 6, 0)
bar.stop:Hide()
bar.collapse = MakeButton(bar, "up", L("Collapse to one line"), function() card.SetCollapsed(true) end)
bar.collapse:SetPoint("RIGHT", -20, 0)
bar.settings = MakeButton(bar, "gear", L("Settings"), function() addon.settings.OpenSettings() end)
bar.settings:SetPoint("RIGHT", bar.collapse, "LEFT", -2, 0)
bar.menu = MakeButton(bar, "menu", L("Pick a guide, skipped quest chains, what's new"), function()
    if addon.RXPFrame and addon.RXPFrame.DropDownMenu then addon.RXPFrame.DropDownMenu() end
end)
bar.menu:SetPoint("RIGHT", bar.settings, "LEFT", -2, 0)

-- Collapsed: one line with the badge, the step and an expand button
local mini = CreateFrame("Frame", nil, f)
mini:SetPoint("TOPLEFT", 1, -1)
mini:SetPoint("BOTTOMRIGHT", -1, 1)
mini.badge = MakeBadge(mini, 24)
mini.badge:SetPoint("LEFT", 10, 0)
mini.text = mini:CreateFontString(nil, "OVERLAY")
mini.text:SetPoint("LEFT", mini.badge, "RIGHT", 10, 0)
mini.text:SetJustifyH("LEFT")
mini.text:SetWordWrap(false)
mini.text:SetTextColor(unpack(C.text))
mini.expand = MakeButton(mini, "down", L("Show the full guide"), function() card.SetCollapsed(false) end)
mini.expand:SetPoint("RIGHT", -4, 0)
mini.count = mini:CreateFontString(nil, "OVERLAY")
mini.count:SetPoint("RIGHT", mini.expand, "LEFT", -4, 0)
mini.count:SetTextColor(unpack(C.dim))
mini.text:SetPoint("RIGHT", mini.count, "LEFT", -8, 0)
mini:Hide()

function card.SetCollapsed(value)
    local p = Profile()
    if p then p.openxpCardCollapsed = value and true or false end
    card.Refresh(true)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function SplitGuideName(guide)
    local name = (guide and (guide.displayname or guide.name)) or ""
    name = StripCodes(name):gsub("\\n", " "):gsub("\n", " ")
    local range, zone = name:match("^(%d+%s*%-%s*%d+)%s+(.+)$")
    if range then return zone, (range:gsub("%-", "–")) end
    return name, ""
end

local function NextStepTexts(guide, afterIndex, count)
    local out = {}
    local last = math.min(#guide.steps, afterIndex + 15 * count)
    for i = afterIndex + 1, last do
        local step = guide.steps[i]
        if step and not step.hidewindow and not (OXPCData and OXPCData.stepSkip and OXPCData.stepSkip[i]) then
            local title = StepContent(step)
            if title and title ~= "" then
                tinsert(out, (StripCodes(title)))
                if #out >= count then break end
            end
        end
    end
    return out
end

local function Visible()
    if not card.IsEnabled() or not addon.currentGuide then return false end
    if addon.isHidden then return false end
    local p = Profile()
    if p and p.hideGuideWindow then return false end
    -- the engine still hides its own window in raids, when no guide is
    -- enabled and so on; follow it
    local rxp = addon.RXPFrame
    if rxp and rxp.IsShown and not rxp:IsShown() then return false end
    return true
end

function card.Refresh(force)
    if not Visible() then
        f:Hide()
        return
    end
    f:Show()

    local guide = addon.currentGuide
    local p = Profile()
    local scale = (p and p.windowScale) or 1
    if f:GetScale() ~= scale then f:SetScale(scale) end
    if not card.sizing and f:GetWidth() ~= Width() then f:SetWidth(Width()) end
    grip:SetShown(not (p and p.lockFrames))
    local total = guide.steps and #guide.steps or 0
    local current = math.min(CurrentStep() or 1, math.max(total, 1))
    local active = addon.RXPFrame and addon.RXPFrame.activeSteps or {}

    local steps = {}
    local lastIndex = current
    for _, step in ipairs(active) do
        if #steps >= MAX_BLOCKS then break end
        if step and not step.hidewindow and not step.tip then
            tinsert(steps, step)
            if not step.sticky and step.index and step.index > lastIndex then lastIndex = step.index end
        end
    end

    -- Walking through a quest chain: the card shows that instead
    local detourStep, detourIndex
    if card.detour then
        local target
        detourStep, detourIndex, target = card.DetourStep()
        card.detourTarget = target
        if detourStep then
            steps = {detourStep}
        end
    end

    if p and p.openxpCardCollapsed then
        header:Hide(); progressBg:Hide(); progress:Hide(); body:Hide(); upNext:Hide(); bar:Hide()
        mini:Show()
        SetFont(mini.text, 2)
        SetFont(mini.count, 0)
        local first = steps[1]
        if first then
            mini.badge:SetKind(StepKind(first))
            mini.text:SetText(StripCodes((StepContent(first))))
        else
            mini.badge:SetKind("travel")
            mini.text:SetText(L("Guide finished"))
        end
        mini.count:SetText(fmt("%d/%d", current, total))
        if not card.sizing then f:SetHeight(42) end
        return
    end

    mini:Hide()
    local wide = Width() >= 360
    for _, btn in ipairs({bar.find, bar.stop}) do
        btn:SetWidth(wide and 116 or 40)
        btn.label:SetShown(wide)
        btn.icon:ClearAllPoints()
        if wide then btn.icon:SetPoint("LEFT", 10, 0) else btn.icon:SetPoint("CENTER") end
    end
    bar.find:SetShown(not detourStep)
    bar.stop:SetShown(detourStep ~= nil)
    header:Show(); progressBg:Show(); progress:Show(); body:Show(); upNext:Show(); bar:Show()

    local zone, range = SplitGuideName(guide)
    SetFont(header.zone, -1)
    SetFont(header.range, -1)
    SetFont(header.step, -1)
    header.zone:SetWidth(0)
    header.zone:SetText(zone:upper())
    if header.zone:GetStringWidth() > Width() - 150 then header.zone:SetWidth(Width() - 150) end
    header.range:SetText(range)
    header.step:SetText(fmt(L("Step %d / %d"), current, total))
    if detourStep then
        header.zone:SetText(L("QUEST CHAIN"))
        header.range:SetText("")
        header.step:SetText(fmt(L("%d / %d"), detourIndex, #card.detour.ids))
    end
    local frac = total > 0 and current / total or 0
    if detourStep then frac = detourIndex / math.max(#card.detour.ids, 1) end
    progress:SetWidth(math.max(1, (Width() - 2) * frac))

    local y = 0
    for i = 1, MAX_BLOCKS do
        local b = blocks[i]
        local step = steps[i]
        if step then
            b = GetBlock(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            b:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
            y = y + LayoutBlock(b, step, i == 1)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    if #steps == 0 then
        y = 8
    end
    body:SetHeight(math.max(y, 1))

    -- One "up next" line by default; a taller card shows more of the route
    local lineH = FontSize(0) + 6
    local baseHeight = 1 + 28 + 2 + y + 4 + 34 + 38 + 1
    local want = card.sizing and (f:GetHeight() or 0) or (card.height or 0)
    local extra = math.max(0, math.floor((want - baseHeight) / lineH))
    local count = math.min(MAX_UPNEXT, 1 + extra)
    local texts
    if detourStep then
        texts = {}
        local ids = card.detour.ids
        for i = detourIndex + 1, #ids do
            if #texts >= count then break end
            local info = QuestInfo(ids[i])
            tinsert(texts, QuestName(ids[i]) .. (info and info.l and info.l > 0 and fmt(" (lvl %d)", info.l) or ""))
        end
        if #texts < count then
            tinsert(texts, fmt(L("Back to the guide: %s"), QuestName(card.detour.target)))
        end
    else
        texts = NextStepTexts(guide, lastIndex, count)
    end

    upNext:ClearAllPoints()
    upNext:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -4)
    upNext:SetPoint("TOPRIGHT", body, "BOTTOMRIGHT", 0, -4)
    local upHeight = 0
    if #texts > 0 then
        SetFont(upNext.label, -2, "")
        upNext.label:SetText(L("UP NEXT"))
        local textW = Width() - PAD * 2 - upNext.label:GetStringWidth() - 10
        for i = 1, math.max(#texts, #upNext.lines) do
            local line = texts[i] and UpNextLine(i) or upNext.lines[i]
            if texts[i] then
                SetFont(line, 0)
                if i > 1 then
                    line:ClearAllPoints()
                    line:SetPoint("TOPLEFT", upNext.lines[i - 1], "BOTTOMLEFT", 0, -6)
                end
                line:SetWidth(textW)
                line:SetText(texts[i])
                line:Show()
            else
                line:Hide()
            end
        end
        upHeight = 34 + (#texts - 1) * lineH
        upNext:Show()
    else
        upNext:Hide()
    end
    upNext:SetHeight(math.max(upHeight, 1))

    if not card.sizing then
        local content = 1 + 28 + 2 + y + 4 + upHeight + 38 + 1
        f:SetHeight(math.max(content, card.height or 0))
    end
end

-- Throttled refresh while shown; quest progress changes all the time
local elapsed = 0
local ticker = CreateFrame("Frame")
local Tick
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    Tick()
end)
function Tick()
    if card.enabled then
        local d = card.detour
        if d then
            if (addon.currentGuide and addon.currentGuide.name ~= d.guide) or DetourDone(d) then
                card.StopDetour()
            elseif card.detourTarget and addon.arrowFrame and not addon.arrowFrame:IsShown() then
                local p = Profile()
                if not (p and p.disableArrow) then addon.arrowFrame:Show() end
            end
        end
        local r = card.returnTo
        if r then
            if addon.currentGuide ~= r.guide then
                card.returnTo = nil
            elseif addon.IsOnQuest and addon.IsOnQuest(r.quest) then
                card.returnTo = nil
                addon.SetStep(r.step)
            end
        end
        card.Refresh()
        card.ParkClassicWindow()
    end
end
card.TickForTest = Tick

---------------------------------------------------------------------------
-- The classic window is still the engine; park it off screen
---------------------------------------------------------------------------

function card.ParkClassicWindow()
    local rxp = addon.RXPFrame
    if not rxp then return end
    rxp.savePosition = false
    local left = rxp:GetLeft()
    if left and left > -1000 then
        rxp:SetClampedToScreen(false)
        rxp:ClearAllPoints()
        rxp:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -2000, 0)
    end
end

---------------------------------------------------------------------------
-- Arrow
---------------------------------------------------------------------------

local function StyleArrow()
    local af = addon.arrowFrame
    if not af or af.openxpStyled then return end
    af.openxpStyled = true
    local p = Profile()
    local scale = (p and p.arrowScale) or 1

    af.dialBg = af:CreateTexture(nil, "BACKGROUND")
    af.dialBg:SetTexture(TEX .. "dialdisc")
    af.dialBg:SetPoint("CENTER")
    af.dialBg:SetSize(76 * scale, 76 * scale)
    af.dialBg:SetVertexColor(16 / 255, 17 / 255, 21 / 255, 0.85)

    af.dialRing = af:CreateTexture(nil, "BORDER")
    af.dialRing:SetTexture(TEX .. "dialring")
    af.dialRing:SetPoint("CENTER")
    af.dialRing:SetSize(76 * scale, 76 * scale)

    af.arrived = af:CreateTexture(nil, "OVERLAY")
    af.arrived:SetTexture(TEX .. "check")
    af.arrived:SetPoint("CENTER")
    af.arrived:SetSize(36 * scale, 36 * scale)
    Tint(af.arrived, C.green)
    af.arrived:Hide()

    af.texture:ClearAllPoints()
    af.texture:SetPoint("CENTER")
    af.texture:SetSize(44 * scale, 44 * scale)

    af.text:SetAlpha(0)
    -- theme reloads call this; keep the OpenXP pointer
    af.UpdateVisuals = function(self) self.texture:SetTexture(TEX .. "pointer") end

    af.oxpDist = af:CreateFontString(nil, "OVERLAY")
    af.oxpDist:SetFont(FONT, 17, "OUTLINE")
    af.oxpDist:SetPoint("TOP", af.dialBg, "BOTTOM", 0, -6)
    af.oxpLabel = af:CreateFontString(nil, "OVERLAY")
    af.oxpLabel:SetFont(FONT, 12, "OUTLINE")
    af.oxpLabel:SetPoint("TOP", af.oxpDist, "BOTTOM", 0, -3)
    af.oxpLabel:SetTextColor(0.72, 0.74, 0.8)
    af:SetHitRectInsets(-22 * scale, -22 * scale, -22 * scale, -22 * scale)
end

local function ArrowVisuals(af)
    af.texture:SetTexture(TEX .. "pointer")
end

-- Follow the Arrow scale and Arrow text size settings live
local function ArrowSizes(af)
    local p = Profile()
    local scale = (p and p.arrowScale) or 1
    local textSize = (p and p.arrowText) or 12
    if af.oxpScale == scale and af.oxpText == textSize then return end
    af.oxpScale, af.oxpText = scale, textSize
    af.dialBg:SetSize(76 * scale, 76 * scale)
    af.dialRing:SetSize(76 * scale, 76 * scale)
    af.arrived:SetSize(36 * scale, 36 * scale)
    af.texture:SetSize(44 * scale, 44 * scale)
    af:SetHitRectInsets(-22 * scale, -22 * scale, -22 * scale, -22 * scale)
    af.oxpDist:SetFont(FONT, textSize + 5, "OUTLINE")
    af.oxpLabel:SetFont(FONT, textSize, "OUTLINE")
end

local function ArrowUpdate(self, ...)
    if card.detour and card.detourTarget then
        self.element = card.detourTarget
    end
    addon.DrawArrow(self, ...)
    local af = addon.arrowFrame
    if not af.oxpDist then return end
    ArrowSizes(af)
    local dist = af.distance or 0
    local element = af.element
    local here = element and dist <= 8
    if here then
        af.texture:Hide()
        af.arrived:Show()
        Tint(af.dialRing, C.green)
        af.oxpDist:SetText(L("Here"))
        af.oxpDist:SetTextColor(unpack(C.green))
    else
        af.texture:Show()
        af.arrived:Hide()
        Tint(af.dialRing, C.blue, 0.6)
        af.oxpDist:SetText(fmt("%d yd", dist))
        af.oxpDist:SetTextColor(0.96, 0.97, 0.98)
    end
    local label = element and (element.title or (element.step and element.step.arrowtext))
    af.oxpLabel:SetText(label and StripCodes(label) or "")
end

function card.SetupArrow()
    local af = addon.arrowFrame
    if not af then return end
    StyleArrow()
    ArrowVisuals(af)
    af:SetScript("OnUpdate", ArrowUpdate)
end

---------------------------------------------------------------------------
-- Turn on
---------------------------------------------------------------------------

function card.Enable()
    if not card.IsEnabled() then return end
    card.enabled = true
    local p = Profile()
    if p and p.openxpCardPos then
        local pos = p.openxpCardPos
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    if p and p.openxpDetour and p.openxpDetour.ids then card.detour = p.openxpDetour end
    card.width = p and p.openxpCardWidth or nil
    card.height = p and p.openxpCardHeight or nil
    f:SetScale((p and p.windowScale) or 1)
    card.ParkClassicWindow()
    card.SetupArrow()
    card.Refresh(true)
end

-- Settings > Reset guide card: default spot and size
function card.ResetPosition()
    local p = Profile()
    if p then
        p.openxpCardPos = nil
        p.openxpCardWidth = nil
        p.openxpCardHeight = nil
    end
    card.width, card.height = nil, nil
    f:ClearAllPoints()
    f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
    f:SetWidth(WIDTH)
    card.Refresh(true)
end

-- The engine redraws its arrow on theme reloads; keep ours on top
if addon.SetupArrow then
    local origSetupArrow = addon.SetupArrow
    addon.SetupArrow = function(...)
        origSetupArrow(...)
        if card.enabled then card.SetupArrow() end
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(2, function() card.Enable() end)
end)
