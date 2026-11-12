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

local WIDTH = 330
local MIN_W, MIN_H, MAX_W, MAX_H = 200, 120, 640, 900
local MAX_UPNEXT = 12
local PAD = 12
local MAX_BLOCKS = 4
local MAX_LINES = 8

local function Settings() return OXP.settings end
local function Width() return Card.width or WIDTH end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local f = CreateFrame("Frame", "OpenXPCard", UIParent, "BackdropTemplate")
Card.frame = f
f:SetSize(WIDTH, 120)
f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
Style.Backdrop(f, C.bg, C.border)
f:Hide()

local function SavePosition()
    local point, _, relPoint, x, y = f:GetPoint()
    if point then Settings().cardPos = { point, relPoint, x, y } end
    if OXP.ActionButtons then OXP.ActionButtons.Place() end -- they sit beside the card
end

f:SetScript("OnDragStart", function(self)
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
f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and OXP.GuidePicker then OXP.GuidePicker.Toggle(f) end
end)

local grip = CreateFrame("Button", nil, f)
Card.grip = grip
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(f:GetFrameLevel() + 10)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or Settings().lockFrames then return end
    Card.sizing = true
    f:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    if not Card.sizing then return end
    f:StopMovingOrSizing()
    Card.sizing = false
    local s = Settings()
    Card.width = math.floor(math.max(MIN_W, math.min(MAX_W, f:GetWidth() or WIDTH)) + 0.5)
    s.cardWidth = Card.width
    if not s.cardCollapsed then
        Card.height = math.floor(math.max(MIN_H, math.min(MAX_H, f:GetHeight() or MIN_H)) + 0.5)
        s.cardHeight = Card.height
    end
    SavePosition()
    Card.Refresh(true)
end)
grip:SetScript("OnUpdate", function()
    if Card.sizing then
        Card.width = math.max(MIN_W, math.min(MAX_W, f:GetWidth() or WIDTH))
        Card.Refresh(true)
    end
end)
grip:SetScript("OnEnter", function(self) Style.Tooltip(self, L("Drag to resize")) end)
grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
header.zone = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
header.zone:SetPoint("LEFT", header.dot, "RIGHT", 7, 0)
header.zone:SetTextColor(unpack(C.text))
header.zone:SetJustifyH("LEFT")
header.zone:SetWordWrap(false)
header.range = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
header.range:SetPoint("LEFT", header.zone, "RIGHT", 6, 0)
header.range:SetTextColor(unpack(C.dim))
header.step = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
header.step:SetPoint("RIGHT", -PAD + 1, 0)
header.step:SetTextColor(unpack(C.dim))
header.stepBtn = CreateFrame("Button", nil, header)
header.stepBtn:SetPoint("TOPRIGHT", 0, 0)
header.stepBtn:SetPoint("BOTTOMRIGHT", 0, 0)
header.stepBtn:SetWidth(80)
header.stepBtn:SetScript("OnClick", function() Card.ToggleStepList() end)
header.stepBtn:SetScript("OnEnter", function(self)
    Style.Tooltip(self, L("Show every step in this guide"), L("Click a step to jump to it. Mouse wheel scrolls."))
end)
header.stepBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
function Card.GoalText(g)
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
        return g.text or fmt(L("Accept %s"), QuestDB.QuestName(g.quest))
    elseif kind == "turnin" then
        return g.text or fmt(L("Turn in %s"), QuestDB.QuestName(g.quest))
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
    local title, lines = nil, {}
    for _, g in ipairs(step.goals or {}) do
        local kind = g[1]
        if BLOCKING[kind] then
            local state = OXP.Goals.State(g, step.marks)
            if state ~= "skip" then
                local text = Card.GoalText(g)
                if text then
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
end

function Card.StopDetour()
    Card.detour = nil
    OXP.char.detour = nil
    OXP.Target.SetOverride(nil)
    Card.Refresh(true)
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
function Card.DetourStep()
    local d = Card.detour
    if not d then return nil end
    local index, id
    for i, q in ipairs(d.ids) do
        if not TurnedIn(q) and not (q == d.target and Quests.IsOnQuest(q) and d.mode ~= "complete") then
            index, id = i, q
            break
        end
    end
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
    Card.histOffset = 0
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

local body = CreateFrame("Frame", nil, f)
body:SetPoint("TOPLEFT", progressBg, "BOTTOMLEFT", 0, 0)
body:SetPoint("TOPRIGHT", progressBg, "BOTTOMRIGHT", 0, 0)
body:SetHeight(10)

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
    line.barBg = line:CreateTexture(nil, "ARTWORK")
    line.barBg:SetHeight(5)
    line.barBg:SetColorTexture(1, 1, 1, 0.1)
    line.bar = line:CreateTexture(nil, "OVERLAY")
    line.bar:SetHeight(5)
    line.bar:SetPoint("LEFT", line.barBg, "LEFT")
    line.count = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
    b.badge = Style.Badge(b, 34)
    b.badge:SetPoint("TOPLEFT", PAD, -10)
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.num:SetPoint("TOP", b.badge, "BOTTOM", 0, -4)
    b.num:SetJustifyH("CENTER")
    b.num:SetTextColor(unpack(C.faint))
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.title:SetPoint("TOPLEFT", b.badge, "TOPRIGHT", 12, -1)
    b.title:SetJustifyH("LEFT")
    b.title:SetJustifyV("TOP")
    b.title:SetTextColor(unpack(C.text))
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
    w.text:SetTextColor(unpack(C.gold))
    w.list = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.list:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -4)
    w.list:SetJustifyH("LEFT")
    w.list:SetTextColor(unpack(C.dim))
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
    local h = w.text:GetStringHeight() + (list and (w.list:GetStringHeight() + 4) or 0) + 6 + 22 + (rows - 1) * 28
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
    OXP.Print("|cFFFF7043card error|r (please send this to the OpenXP author): " .. err)
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
        local here = Card.here
        if here and pos == here.pos then
            table.insert(lines, 1, { text = "|cFFF2C35C" .. fmt(L("You're right here, so do this first. Then back to step %d."), here.from) .. "|r", plain = true })
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
            line.text:SetTextColor(unpack(data.done and C.faint or C.text))
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
    local height = math.max(y + 4, 34 + 20 + (b.num:GetText() ~= "" and 14 or 0))
    b:SetHeight(height)
    return height
end

---------------------------------------------------------------------------
-- History: wheel up over the card for the steps you've passed
---------------------------------------------------------------------------

local HIST_ROWS, HIST_ROW_H = 6, 20
local hist = CreateFrame("Frame", nil, f)
hist:SetPoint("TOPLEFT", progressBg, "BOTTOMLEFT", 0, 0)
hist:SetPoint("TOPRIGHT", progressBg, "BOTTOMRIGHT", 0, 0)
hist:SetHeight(1)
hist.bg = hist:CreateTexture(nil, "BACKGROUND")
hist.bg:SetAllPoints()
hist.bg:SetColorTexture(0, 0, 0, 0.18)
hist.label = hist:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
hist.label:SetPoint("TOPLEFT", PAD, -8)
hist.label:SetTextColor(unpack(C.dim))
hist.hint = hist:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
hist.hint:SetPoint("TOPRIGHT", -PAD, -8)
hist.hint:SetTextColor(unpack(C.faint))
hist.rows = {}
hist:Hide()
Card.histOffset = 0

local function HistRow(i)
    local row = hist.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, hist)
    row:SetHeight(HIST_ROW_H)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0)
    row.num = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.num:SetPoint("LEFT", PAD - 2, 0)
    row.num:SetWidth(26)
    row.num:SetJustifyH("RIGHT")
    row.pill = Style.Pill(row)
    row.pill:SetPoint("RIGHT", -PAD + 2, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.num, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", row.pill, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self.hl:SetColorTexture(1, 1, 1, 0.07)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(fmt(L("Step %d"), self.pos or 0), 1, 1, 1)
        if self.full then GameTooltip:AddLine(self.full, 0.85, 0.85, 0.85, true) end
        local st = self.status and Style.STATUS[self.status]
        if st then GameTooltip:AddLine(L(st.tip), st.color[1], st.color[2], st.color[3], true) end
        GameTooltip:AddLine(L("Click to go back to this step"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self) if self.pos then Card.JumpTo(self.pos) end end)
    hist.rows[i] = row
    return row
end

function Card.ScrollHistory(delta)
    if not Engine.GetGuide() or Card.detour then return end
    local before = (Engine.GetPosition() or 1) - 1
    local stepBy = (IsShiftKeyDown and IsShiftKeyDown()) and HIST_ROWS or 1
    Card.histOffset = math.max(0, math.min(before, (Card.histOffset or 0) + (delta > 0 and 1 or -1) * stepBy))
    Card.Refresh(true)
end

local function StepSummary(step)
    local title = Card.StepContent(step)
    return (Text.Strip(title):gsub("\n.*", ""))
end

function Card.LayoutHistory(current)
    local offset = Card.histOffset or 0
    if offset <= 0 or Card.detour then hist:Hide() return 0 end
    offset = math.min(offset, current - 1)
    Card.histOffset = offset
    if offset == 0 then hist:Hide() return 0 end
    local first = current - offset
    local last = math.min(current - 1, first + HIST_ROWS - 1)
    SetFont(hist.label, -2)
    SetFont(hist.hint, -2)
    hist.label:SetText(L("EARLIER STEPS"))
    hist.hint:SetText(Width() >= 280 and L("scroll down to return") or "")
    local y, n = 26, 0
    local steps = Engine.GetSteps()
    for pos = first, last do
        n = n + 1
        local row = HistRow(n)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", hist, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", hist, "TOPRIGHT", 0, -y)
        local text = StepSummary(steps[pos])
        row.pos, row.full = pos, text
        row.status = Engine.StepState(pos)
        SetFont(row.num, -2)
        SetFont(row.text, -1)
        row.num:SetText(pos)
        row.num:SetTextColor(unpack(C.faint))
        row.text:SetText(text)
        row.text:SetTextColor(unpack((row.status == "done" or row.status == "skipped") and C.dim or C.text))
        row.pill:SetStatus(row.status)
        row:Show()
        y = y + HIST_ROW_H
    end
    for k = n + 1, #hist.rows do hist.rows[k]:Hide() end
    y = y + 6
    hist:SetHeight(y)
    hist:Show()
    return y
end

f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function(_, delta) Card.ScrollHistory(delta) end)

---------------------------------------------------------------------------
-- Up next, the button bar, the XP strip
---------------------------------------------------------------------------

local upNext = CreateFrame("Frame", nil, f)
upNext.sep = upNext:CreateTexture(nil, "ARTWORK")
upNext.sep:SetPoint("TOPLEFT", PAD, 0)
upNext.sep:SetPoint("TOPRIGHT", -PAD, 0)
upNext.sep:SetHeight(1)
upNext.sep:SetColorTexture(1, 1, 1, 0.07)
upNext.label = upNext:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
upNext.label:SetPoint("TOPLEFT", PAD, -10)
upNext.label:SetTextColor(unpack(C.dim))
upNext.lines = {}
local function UpNextLine(i)
    local line = upNext.lines[i]
    if not line then
        line = upNext:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetJustifyH("LEFT")
        line:SetTextColor(unpack(C.dim))
        line:SetWordWrap(false)
        if i == 1 then line:SetPoint("TOPLEFT", upNext.label, "TOPRIGHT", 8, 1) end
        upNext.lines[i] = line
    end
    return line
end

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
xp.rested:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 0.35)
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
bar.menu = Btn(bar, "menu", L("Pick a guide, skipped quest chains, feedback"), function() OXP.GuidePicker.Toggle(bar.menu) end)
bar.menu:SetPoint("RIGHT", bar.settings, "LEFT", -2, 0)

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
mini.text:SetTextColor(unpack(C.text))
mini.expand = Btn(mini, "down", L("Show the full guide"), function() Card.SetCollapsed(false) end)
mini.expand:SetPoint("RIGHT", -4, 0)
mini.count = mini:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mini.count:SetPoint("RIGHT", mini.expand, "LEFT", -4, 0)
mini.count:SetTextColor(unpack(C.dim))
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

local function NextStepTexts(after, count)
    local out = {}
    local steps = Engine.GetSteps()
    for pos = after + 1, math.min(#steps, after + 15 * count) do
        local state = Engine.StepState(pos)
        if state ~= "done" and state ~= "skipped" and state ~= "chain" then
            local text = StepSummary(steps[pos])
            if text ~= "" then
                out[#out + 1] = text
                if #out >= count then break end
            end
        end
    end
    return out
end

local function Visible()
    return Settings() ~= nil and Settings().cardShown and Engine.GetGuide() ~= nil
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
        Card.sizing and 1 or 0, Card.histOffset or 0, Engine.IsHeld() and 1 or 0,
        Card.here and Card.here.pos or 0,
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
    if sig ~= Card.lastSig and not Card.retexting and C_Timer and C_Timer.After then
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
    if Card.FillStepList then pcall(Card.FillStepList) end
    pcall(UpdateXP)

    local s = Settings()
    local scale = s.cardScale or 1
    if f:GetScale() ~= scale then f:SetScale(scale) end
    if not Card.sizing and f:GetWidth() ~= Width() then f:SetWidth(Width()) end
    grip:SetShown(not s.lockFrames)

    local guide = Engine.GetGuide()
    local all = Engine.GetSteps()
    local total = #all
    local current = math.min(Engine.GetPosition() or 1, math.max(total, 1))

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

    if s.cardCollapsed then
        header:Hide(); progressBg:Hide(); progress:Hide(); body:Hide(); upNext:Hide(); bar:Hide(); hist:Hide()
        mini:Show()
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
        if not Card.sizing then f:SetHeight(42) end
        return
    end

    mini:Hide()
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
    header:Show(); progressBg:Show(); progress:Show(); body:Show(); upNext:Show(); bar:Show()

    local zone, range = SplitGuideName(guide)
    SetFont(header.zone, -1)
    SetFont(header.range, -1)
    SetFont(header.step, -1)
    header.zone:SetWidth(0)
    header.zone:SetText(zone:upper())
    local zoneMax = math.max(50, Width() - 150)
    if header.zone:GetStringWidth() > zoneMax then header.zone:SetWidth(zoneMax) end
    header.range:SetText(range)
    header.range:SetShown(Width() >= 300)
    header.step:SetText(fmt(L("Step %d / %d"), current, total))
    local frac = total > 0 and current / total or 0
    if detourStep then
        header.zone:SetText(L("QUEST CHAIN"))
        header.range:SetText("")
        header.step:SetText(fmt("%d / %d", detourIndex, #Card.detour.ids))
        frac = detourIndex / math.max(#Card.detour.ids, 1)
    end
    progress:SetWidth(math.max(1, (Width() - 2) * frac))

    local histH = Card.LayoutHistory(current)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", histH > 0 and hist or progressBg, "BOTTOMLEFT", 0, 0)
    body:SetPoint("TOPRIGHT", histH > 0 and hist or progressBg, "BOTTOMRIGHT", 0, 0)

    local y = 0
    for i = 1, MAX_BLOCKS do
        local b, e = blocks[i], shown[i]
        if e then
            b = GetBlock(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            b:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
            y = y + LayoutBlock(b, e[1], e[2], i == 1)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    if #shown == 0 then y = 8 end
    body:SetHeight(math.max(y, 1))

    -- one "up next" line; a taller card shows more of the route
    local lineH = Style.FontSize(0) + 6
    local baseHeight = 1 + 28 + 2 + histH + y + 4 + 34 + 38 + 1
    local want = Card.sizing and (f:GetHeight() or 0) or (Card.height or 0)
    local count = math.min(MAX_UPNEXT, 1 + math.max(0, math.floor((want - baseHeight) / lineH)))
    local texts
    if detourStep then
        texts = {}
        local ids = Card.detour.ids
        for i = detourIndex + 1, #ids do
            if #texts >= count then break end
            local info = QuestDB.Info(ids[i])
            texts[#texts + 1] = QuestDB.QuestName(ids[i]) .. (info and info.l and info.l > 0 and fmt(" (lvl %d)", info.l) or "")
        end
        if #texts < count then texts[#texts + 1] = fmt(L("Back to the guide: %s"), QuestDB.QuestName(Card.detour.target)) end
    else
        texts = NextStepTexts(lastPos, count)
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

    if not Card.sizing then
        local content = 1 + 28 + 2 + histH + y + 4 + upHeight + 38 + 1
        f:SetHeight(math.max(content, Card.height or 0))
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

local function HereDone(step)
    for _, g in ipairs(step.goals) do
        if g[1] == "turnin" and not TurnedIn(g.quest) then return false end
    end
    return true
end

-- px, py, inst: player world position (tests pass it in)
function Card.CheckHere(px, py, inst)
    if not Engine.GetGuide() then Card.here = nil return end
    if not px then px, py, inst = OXP.Places.Player() end
    local steps = Engine.GetSteps()
    local cur = Engine.GetPosition()
    local h = Card.here
    local Dist = OXP.Places.Distance
    if h then
        if h.guide ~= Engine.GetGuide() then
            Card.here = nil
            return
        end
        local spot = OXP.Areas.StepSpot(steps[h.pos])
        local away = cur == h.pos and spot and px and (inst ~= spot.instance or Dist(px, py, spot.wx, spot.wy) > HERE_AWAY)
        if cur ~= h.pos and not HereDone(steps[h.pos]) then
            Card.here = nil -- you moved on by hand
            return
        end
        if HereDone(steps[h.pos]) or away then
            Card.here = nil
            Engine.GoTo(h.from, true)
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
                Engine.GoTo(pos, true)
                Card.Refresh(true)
                return true
            end
        end
    end
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

for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "QUESTS_CHANGED", "SETTINGS_CHANGED" }) do
    OXP.Listen(m, function()
        Card.ticks = Card.ticks + 1
        OXP.Soon("CARD", function() Card.Refresh() end)
    end)
end
OXP.On("PLAYER_XP_UPDATE", function() Card.ticks = Card.ticks + 1 end)

---------------------------------------------------------------------------
-- Step list: every step of the guide, click one to jump there
---------------------------------------------------------------------------

local LIST_ROWS = 18
local list

function Card.BuildStepList()
    if list then return list end
    list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    Style.Backdrop(list, C.bg, C.border)
    list:SetFrameStrata("DIALOG")
    list:SetWidth(340)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list.offset = 0
    list.title = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    list.title:SetPoint("TOPLEFT", PAD, -9)
    list.title:SetTextColor(unpack(C.dim))
    list.close = Style.IconButton(list, "cross", L("Close"), function() list:Hide() end)
    list.close:SetPoint("TOPRIGHT", -4, -4)
    list.rows = {}
    for r = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(18)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0)
        row.num = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.num:SetPoint("LEFT", 6, 0)
        row.num:SetWidth(30)
        row.num:SetJustifyH("RIGHT")
        row.pill = Style.Pill(row)
        row.pill:SetPoint("RIGHT", -6, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.num, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row.pill, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.hl:SetColorTexture(1, 1, 1, 0.08) end)
        row:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, self.current and 0.05 or 0) end)
        row:SetScript("OnClick", function(self) Card.JumpTo(self.pos) end)
        list.rows[r] = row
    end
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, math.min((self.count or 0) - LIST_ROWS, self.offset - delta * 3))
        Card.FillStepList()
    end)
    list:Hide()
    return list
end

function Card.FillStepList()
    if not (list and list:IsShown()) then return end
    local steps = Engine.GetSteps()
    list.count = #steps
    local guide = Engine.GetGuide()
    list.title:SetText(guide and Text.Strip(guide.name) or "")
    SetFont(list.title, -1)
    local rowH = math.max(18, Style.FontSize(-1) + 6)
    if list.rowH ~= rowH then
        list.rowH = rowH
        for r, row in ipairs(list.rows) do
            row:SetHeight(rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -28 - (r - 1) * rowH)
            row:SetPoint("TOPRIGHT", -4, -28 - (r - 1) * rowH)
        end
        list:SetHeight(28 + LIST_ROWS * rowH + 8)
    end
    local cur = Engine.GetPosition()
    for r, row in ipairs(list.rows) do
        local pos = list.offset + r
        local step = steps[pos]
        if step then
            row.pos = pos
            row.current = pos == cur
            SetFont(row.num, -1)
            SetFont(row.text, -1)
            row.num:SetText(pos)
            row.text:SetText(StepSummary(step))
            local status = not row.current and Engine.StepState(pos) or nil
            if status == "todo" then status = nil end
            row.pill:SetStatus(status)
            local done = status == "done" or status == "skipped"
            row.text:SetTextColor(unpack(row.current and C.blue or done and C.faint or C.text))
            row.num:SetTextColor(unpack(row.current and C.blue or C.dim))
            row.hl:SetColorTexture(1, 1, 1, row.current and 0.05 or 0)
            row:Show()
        else
            row:Hide()
        end
    end
end

function Card.ToggleStepList()
    Card.BuildStepList()
    if list:IsShown() then list:Hide() return end
    list:ClearAllPoints()
    if (f:GetLeft() or 0) > 320 then
        list:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
    else
        list:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
    end
    list:Show()
    list.offset = math.max(0, math.min(#Engine.GetSteps() - LIST_ROWS, (Engine.GetPosition() or 1) - 4))
    Card.FillStepList()
end

---------------------------------------------------------------------------
-- Turning on, and the settings window's buttons
---------------------------------------------------------------------------

function Card.Enable()
    Card.enabled = true
    local s = Settings()
    if s.cardPos then
        f:ClearAllPoints()
        f:SetPoint(s.cardPos[1], UIParent, s.cardPos[2], s.cardPos[3], s.cardPos[4])
    end
    if OXP.char.detour and OXP.char.detour.ids then Card.detour = OXP.char.detour end
    Card.width, Card.height = s.cardWidth, s.cardHeight
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
    f:SetWidth(WIDTH)
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
OXP.AddCommand("reset", "put the guide card and arrow back in their default spots", function()
    Card.ResetPosition()
    OXP.Arrow.ResetPosition()
end)
