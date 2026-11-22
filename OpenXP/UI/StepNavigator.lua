-- The step list: every step of the guide in one panel beside the card,
-- opened with the card's step button (or by clicking "Step 12 / 80").
--
--   header    back arrow (closes it), "Steps", the guide's name, close
--   summary   done / skipped / to go, and a bar showing how far you are
--   tabs      All, Earlier, Coming up
--   list      a timeline: earlier steps with how they went (done, skipped,
--             chain missed), the step you're on, and what's coming; click a
--             step to go there, hover for what it says
--   footer    "Back to my step"
--
-- The list is virtual (a few rows reused while you scroll), so a 400-step
-- guide costs the same as a short one. It opens scrolled to your step.
local _, OXP = ...

local Nav = {}
OXP.StepNav = Nav

local Style, Engine, L, Text = OXP.Style, OXP.Engine, OXP.L, OXP.Text
local C, TEX, S = Style.C, Style.TEX, Style.S
local Tint, Fill, TextColor = Style.Tint, Style.Fill, Style.TextColor
local fmt = string.format

local WIDTH, MIN_H, MAX_H = 340, 420, 640
local HEAD_H, SUM_H, TABS_H, FOOT_H = 50, 46, 30, 42
local ITEM_H = 38
local LINE_X = 24 -- the timeline's x in a row

local f, rows = nil, {}
Nav.filter = "all"
Nav.offset = 0

local KIND_NAMES = { accept = "Pick up", turnin = "Turn in", kill = "Kill", loot = "Collect",
                     travel = "Travel", town = "Town" }

-- Step titles don't change while a guide is loaded: worked out once each.
local cache = { guide = nil, titles = {}, kinds = {} }
local function Summary(pos)
    local guide = Engine.GetGuide()
    if cache.guide ~= guide then cache = { guide = guide, titles = {}, kinds = {} } end
    local t = cache.titles[pos]
    if not t then
        local step = Engine.GetSteps()[pos]
        if not step then return "", "travel" end
        local ok, text = pcall(OXP.Card.StepSummary, step)
        t = ok and text or fmt(L("Step %d"), pos)
        if t == "" then t = fmt(L("Step %d"), pos) end
        cache.titles[pos] = t
        local okK, kind = pcall(OXP.Card.StepKind, step)
        cache.kinds[pos] = okK and kind or "travel"
    end
    return t, cache.kinds[pos]
end
OXP.Listen("GUIDE_LOADED", function() cache = { titles = {}, kinds = {} } end)

--- "current", "done", "skipped", "chain" or "todo" for a step.
function Nav.Status(pos)
    if pos == Engine.GetPosition() then return "current" end
    local st = Engine.StepState(pos)
    if st == "done" or st == "skipped" or st == "chain" then return st end
    return "todo"
end

---------------------------------------------------------------------------
-- Items: section headers and steps, by filter
---------------------------------------------------------------------------

function Nav.Items()
    local items = {}
    local total = #Engine.GetSteps()
    local cur = Engine.GetPosition() or 1
    local filter = Nav.filter
    if filter ~= "next" and cur > 1 then
        items[#items + 1] = { header = fmt(L("EARLIER STEPS  (%d)"), cur - 1) }
        for pos = 1, cur - 1 do items[#items + 1] = { pos = pos } end
    end
    if filter ~= "earlier" and total > 0 then
        items[#items + 1] = { header = L("YOU ARE HERE") }
        items[#items + 1] = { pos = cur }
        if cur < total then
            items[#items + 1] = { header = fmt(L("COMING UP  (%d)"), total - cur) }
            for pos = cur + 1, total do items[#items + 1] = { pos = pos } end
        end
    end
    if filter == "earlier" and cur <= 1 then
        items[#items + 1] = { header = L("NOTHING BEFORE THIS STEP YET") }
    end
    return items
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function Pill(row, status)
    local tags = {
        current = { L("YOU'RE HERE"), C.blue }, done = { L("DONE"), C.green },
        skipped = { L("SKIPPED"), C.faint }, chain = { L("CHAIN MISSED"), C.gold },
    }
    local t = tags[status]
    if t then row.pill:SetTag(t[1], t[2], 9) else row.pill:Hide() end
end

local function NewRow(i)
    local row = CreateFrame("Button", nil, f.list)
    row:SetHeight(ITEM_H)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetPoint("TOPLEFT", 6, -1)
    row.hl:SetPoint("BOTTOMRIGHT", -14, 1)
    row.hl:SetTexture(Style.WHITE)
    row.hl:SetVertexColor(1, 1, 1, 0)
    row.accent = row:CreateTexture(nil, "BORDER")
    row.accent:SetPoint("TOPLEFT", 6, -1)
    row.accent:SetPoint("BOTTOMLEFT", 6, 1)
    row.accent:SetWidth(2)
    -- timeline: a line through every row, a node on it for this step
    row.lineUp = row:CreateTexture(nil, "BORDER")
    row.lineUp:SetWidth(2)
    row.lineUp:SetPoint("TOP", row, "TOPLEFT", LINE_X, 0)
    row.lineUp:SetPoint("BOTTOM", row, "LEFT", LINE_X, 0)
    row.lineDown = row:CreateTexture(nil, "BORDER")
    row.lineDown:SetWidth(2)
    row.lineDown:SetPoint("TOP", row, "LEFT", LINE_X, 0)
    row.lineDown:SetPoint("BOTTOM", row, "BOTTOMLEFT", LINE_X, 0)
    row.glow = row:CreateTexture(nil, "ARTWORK")
    row.glow:SetTexture(TEX .. "glow")
    row.glow:SetSize(30, 30)
    row.glow:SetPoint("CENTER", row, "LEFT", LINE_X, 0)
    row.node = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.node:SetSize(14, 14)
    row.node:SetPoint("CENTER", row, "LEFT", LINE_X, 0)
    row.mark = row:CreateTexture(nil, "ARTWORK", nil, 2)
    row.mark:SetSize(9, 9)
    row.mark:SetPoint("CENTER", row.node, "CENTER")
    if row.glow.CreateAnimationGroup then
        local ag = row.glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        if a.SetFromAlpha then a:SetFromAlpha(0.25) a:SetToAlpha(0.8) end
        if a.SetDuration then a:SetDuration(1.1) end
        if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
        row.pulse = ag
    end
    row.pill = Style.Pill(row)
    row.pill:SetPoint("TOPRIGHT", -20, -6)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", LINE_X + 16, -5)
    row.title:SetPoint("RIGHT", row.pill, "LEFT", -6, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("RIGHT", -20, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.header:SetPoint("BOTTOMLEFT", 14, 7)
    row.headerLine = row:CreateTexture(nil, "BORDER")
    row.headerLine:SetHeight(1)
    row.headerLine:SetPoint("LEFT", row.header, "RIGHT", 8, 0)
    row.headerLine:SetPoint("RIGHT", -20, 0)
    row:SetScript("OnEnter", function(self)
        if not self.pos then return end
        self.hl:SetVertexColor(1, 1, 1, 0.06)
        local step = Engine.GetSteps()[self.pos]
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint(f.side == "left" and "TOPRIGHT" or "TOPLEFT", self, f.side == "left" and "TOPLEFT" or "TOPRIGHT", f.side == "left" and -8 or 8, 0)
        local title, lines = "", {}
        if step then
            local ok, t, l = pcall(OXP.Card.StepContent, step)
            if ok then title, lines = Text.Strip(t), l end
        end
        GameTooltip:SetText(title ~= "" and title or fmt(L("Step %d"), self.pos), 1, 1, 1, 1, true)
        for _, line in ipairs(lines or {}) do
            local text = Text.Strip(line.text or "")
            if line.done then
                GameTooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " .. text, 0.4, 0.8, 0.55, true)
            else
                GameTooltip:AddLine((line.plain and "" or "- ") .. text, 0.82, 0.83, 0.86, true)
            end
        end
        local st = self.status and Style.STATUS[self.status]
        if st then GameTooltip:AddLine(L(st.tip), st.color[1], st.color[2], st.color[3], true) end
        GameTooltip:AddLine(self.status == "current" and L("The step you're on") or L("Click to go to this step"), 0.55, 0.57, 0.62)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:SetVertexColor(1, 1, 1, self.status == "current" and 0.05 or 0)
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseDown", function(self) if self.pos then self.title:SetPoint("TOPLEFT", LINE_X + 17, -6) end end)
    row:SetScript("OnMouseUp", function(self) self.title:SetPoint("TOPLEFT", LINE_X + 16, -5) end)
    row:SetScript("OnClick", function(self)
        if self.pos and self.status ~= "current" then
            OXP.Card.JumpTo(self.pos)
            Nav.Refresh()
        end
    end)
    rows[i] = row
    return row
end

local NODE = {
    current = { "filledcircle", nil, "blue" },
    done = { "filledcircle", "check", "green" },
    skipped = { "opencircle", "skip", "faint" },
    chain = { "filledcircle", "cross", "gold" },
    todo = { "opencircle", nil, "faint" },
}

local function PaintRow(row, item, index, count)
    local frameH = ITEM_H
    row:SetHeight(frameH)
    if item.header then
        row.pos, row.status = nil, nil
        for _, r in ipairs({ row.node, row.mark, row.glow, row.title, row.sub, row.lineUp, row.lineDown, row.accent }) do r:Hide() end
        row.pill:Hide()
        if row.pulse and row.pulse:IsPlaying() then row.pulse:Stop() end
        row.hl:SetVertexColor(1, 1, 1, 0)
        Style.FixedFont(row.header, 10, "")
        row.header:SetText(item.header)
        TextColor(row.header, item.header == L("YOU ARE HERE") and C.blue or C.faint)
        row.header:Show()
        Fill(row.headerLine, C.line)
        row.headerLine:Show()
        row:EnableMouse(false)
        return
    end
    row:EnableMouse(true)
    row.header:Hide()
    row.headerLine:Hide()
    local pos = item.pos
    local status = Nav.Status(pos)
    row.pos, row.status = pos, status
    local title, kind = Summary(pos)
    local node = NODE[status]
    local color = C[node[3]]
    row.node:SetTexture(TEX .. node[1])
    row.node:SetSize(status == "current" and 16 or 14, status == "current" and 16 or 14)
    Tint(row.node, color, (status == "todo") and 0.7 or 1)
    if node[2] then
        row.mark:SetTexture(TEX .. node[2])
        if status == "skipped" then Tint(row.mark, C.faint) else row.mark:SetVertexColor(0.05, 0.06, 0.08, 1) end
        row.mark:Show()
    else
        row.mark:Hide()
    end
    row.node:Show()
    row.glow:SetShown(status == "current")
    if status == "current" then
        Tint(row.glow, C.blue, 0.6)
        if row.pulse and not row.pulse:IsPlaying() then row.pulse:Play() end
    elseif row.pulse and row.pulse:IsPlaying() then
        row.pulse:Stop()
    end
    -- the line runs between steps, not into the section headers
    local prev, nxt = Nav.items[index - 1], Nav.items[index + 1]
    row.lineUp:SetShown(prev ~= nil and prev.pos ~= nil)
    row.lineDown:SetShown(nxt ~= nil and nxt.pos ~= nil)
    local before = pos < (Engine.GetPosition() or 1)
    Fill(row.lineUp, before and C.green or C.line, before and 0.45 or nil)
    Fill(row.lineDown, (before and pos + 1 < (Engine.GetPosition() or 1)) and C.green or C.line,
        (before and pos + 1 < (Engine.GetPosition() or 1)) and 0.45 or nil)
    Style.SetFont(row.title, 0)
    Style.SetFont(row.sub, -2)
    if row.title.SetShadowOffset then row.title:SetShadowColor(0, 0, 0, 0.6) end
    row.title:SetText(title)
    TextColor(row.title, status == "current" and { 1, 1, 1 } or (status == "todo" and C.text) or C.dim)
    local kc = (Style.BADGES[kind] or Style.BADGES.travel).color
    local hex = fmt("|cFF%02X%02X%02X", kc[1] * 255, kc[2] * 255, kc[3] * 255)
    row.sub:SetText(fmt("%s %d  %s\194\183|r  %s%s|r", L("Step"), pos, hex, hex, L(KIND_NAMES[kind] or "Travel")))
    TextColor(row.sub, C.faint)
    row.title:Show()
    row.sub:Show()
    Pill(row, status)
    row.accent:SetShown(status == "current")
    Fill(row.accent, C.blue)
    row.hl:SetVertexColor(1, 1, 1, status == "current" and 0.05 or 0)
    row:SetAlpha((status == "done" or status == "skipped") and 0.82 or 1)
end

---------------------------------------------------------------------------
-- Scrolling (virtual: the rows stay, what they show moves)
---------------------------------------------------------------------------

-- the list's height from the panel's own (the panel is sized by hand, so
-- this never waits on the game's layout pass)
local function ListH()
    return math.max(60, (f:GetHeight() or 480) - HEAD_H - SUM_H - TABS_H - 4 - FOOT_H - 2)
end
Nav.ListH = function() return f and ListH() or 0 end

local function MaxOffset()
    return math.max(0, #(Nav.items or {}) * ITEM_H - ListH())
end

function Nav.Paint()
    if not f then return end
    local items = Nav.items or {}
    Nav.offset = math.max(0, math.min(MaxOffset(), Nav.offset or 0))
    local viewH = ListH()
    local first = math.floor(Nav.offset / ITEM_H) + 1
    local shift = Nav.offset % ITEM_H
    local need = math.ceil(viewH / ITEM_H) + 1
    for i = 1, math.max(need, #rows) do
        local item = items[first + i - 1]
        local row = rows[i]
        if item and i <= need then
            row = row or NewRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -((i - 1) * ITEM_H - shift))
            row:SetPoint("RIGHT", f.list, "RIGHT", 0, 0)
            PaintRow(row, item, first + i - 1, #items)
            row:Show()
        elseif row then
            row:Hide()
            if row.pulse and row.pulse:IsPlaying() then row.pulse:Stop() end
        end
    end
    -- scrollbar
    local max = MaxOffset()
    local bar = f.bar
    if max <= 0 then bar:Hide() return end
    local h = viewH - 8
    local th = math.max(28, h * viewH / (#items * ITEM_H))
    bar.thumb:SetHeight(th)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("TOP", bar, "TOP", 0, -(h - th) * Nav.offset / max)
    bar.travel = h - th
    bar:Show()
end

--- Scroll to `y` px, gliding there unless `now`.
function Nav.ScrollTo(y, now)
    y = math.max(0, math.min(MaxOffset(), y))
    Nav.target = y
    if now then
        Nav.offset = y
        Nav.Paint()
        return
    end
    Style.Tween("OXPStepNavScroll", Nav.offset or 0, y, 0.18, function(v)
        Nav.offset = v
        Nav.Paint()
    end)
end

--- Scroll so your step sits a third of the way down.
function Nav.ScrollToCurrent(now)
    local cur = Engine.GetPosition() or 1
    for i, item in ipairs(Nav.items or {}) do
        if item.pos == cur then
            Nav.ScrollTo((i - 1) * ITEM_H - ListH() / 3, now)
            return
        end
    end
    Nav.ScrollTo(0, now)
end

---------------------------------------------------------------------------
-- Header, summary, tabs, footer
---------------------------------------------------------------------------

local function Counts()
    local done, skipped, total = 0, 0, #Engine.GetSteps()
    for pos = 1, total do
        local st = Engine.StepState(pos)
        if st == "done" then done = done + 1 elseif st == "skipped" or st == "chain" then skipped = skipped + 1 end
    end
    return done, skipped, total
end

local function PaintSummary()
    local done, skipped, total = Counts()
    local cur = Engine.GetPosition() or 1
    f.count:SetText(fmt(L("Step %d of %d"), math.min(cur, math.max(total, 1)), total))
    f.stats:SetText(fmt("|cFF3DBB7A%d %s|r   |cFF9EA3AD%d %s|r   %d %s", done, L("done"), skipped, L("skipped"),
        math.max(0, total - cur), L("to go")))
    local w = WIDTH - 2 - S.lg * 2
    local dw = total > 0 and w * done / total or 0
    local sw = total > 0 and w * skipped / total or 0
    f.doneBar:SetWidth(math.max(1, dw))
    f.doneBar:SetShown(dw >= 1)
    f.skipBar:SetWidth(math.max(1, sw))
    f.skipBar:SetShown(sw >= 1)
    f.skipBar:ClearAllPoints()
    f.skipBar:SetPoint("LEFT", f.track, "LEFT", dw, 0)
    f.here:ClearAllPoints()
    f.here:SetPoint("CENTER", f.track, "LEFT", total > 0 and w * (cur - 0.5) / total or 0, 0)
end

local TABS = { { "all", "All" }, { "earlier", "Earlier" }, { "next", "Coming up" } }

local function PaintTabs(animate)
    for _, tab in ipairs(f.tabs) do
        local on = tab.key == Nav.filter
        TextColor(tab.label, on and { 1, 1, 1 } or C.dim)
        if on then
            local x, w = tab.x or 0, tab:GetWidth() or 60
            local from = f.underline.x or x
            f.underline.x = x
            f.underline:SetWidth(w - 16)
            Style.Tween("OXPStepNavTab", animate and from or x, x, 0.16, function(v)
                f.underline:ClearAllPoints()
                f.underline:SetPoint("BOTTOMLEFT", f.tabBar, "BOTTOMLEFT", v + 8, 0)
            end)
        end
    end
end

function Nav.SetFilter(key)
    Nav.filter = key
    PaintTabs(true)
    Nav.Refresh(true)
    Nav.ScrollToCurrent(true)
end

-- The panel's own text: the card's font, size and outline (Style.SetFont),
-- set again by Nav.ApplySkin whenever the look changes.
local navFonts = {}
local function NavText(parent, offset, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    navFonts[#navFonts + 1] = { fs, offset }
    Style.SetFont(fs, offset)
    TextColor(fs, color or C.text)
    return fs
end

-- a 1 px line whose alpha Nav.ApplySkin sets (the card's lines fade with
-- its background and vanish in Minimal)
local function PlainLine(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(1, 1, 1, 0.07)
    return t
end

local function Build()
    f = CreateFrame("Frame", "OpenXPSteps", UIParent, "BackdropTemplate")
    Nav.frame = f
    f:SetSize(WIDTH, 480)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    -- the card's own background, border and Background slider (and none
    -- at all in Minimal)
    Style.Backdrop(f, C.bg, C.border, { card = true })
    Style.Shadow(f)
    if _G.UISpecialFrames then tinsert(_G.UISpecialFrames, "OpenXPSteps") end

    -- header: back arrow, title and guide, close
    f.head = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.head:SetPoint("TOPLEFT", 1, -1)
    f.head:SetPoint("TOPRIGHT", -1, -1)
    f.head:SetHeight(HEAD_H - 1)
    -- painted by Nav.ApplySkin, like the card's header band
    f.accentLine = f:CreateTexture(nil, "ARTWORK")
    f.accentLine:SetPoint("TOPLEFT", 1, -1)
    f.accentLine:SetPoint("TOPRIGHT", -1, -1)
    f.accentLine:SetHeight(2)
    Fill(f.accentLine, C.blue, 0.9)
    f.back = Style.IconButton(f, "prev", L("Back to the card"), function() Nav.Hide() end)
    f.back:SetSize(30, 30)
    f.back:SetPoint("LEFT", f, "TOPLEFT", 8, -HEAD_H / 2)
    f.title = NavText(f, 3, { 1, 1, 1 })
    f.title:SetPoint("TOPLEFT", f.back, "TOPRIGHT", 6, -1)
    f.title:SetText(L("Steps"))
    f.guide = NavText(f, -1, C.dim)
    f.guide:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.guide:SetPoint("RIGHT", f, "RIGHT", -44, 0)
    f.guide:SetWordWrap(false)
    f.close = Style.IconButton(f, "cross", L("Close"), function() Nav.Hide() end)
    f.close:SetSize(30, 30)
    f.close:SetPoint("RIGHT", f, "TOPRIGHT", -8, -HEAD_H / 2)
    f.headLine = PlainLine(f)
    f.headLine:SetPoint("TOPLEFT", 1, -HEAD_H)
    f.headLine:SetPoint("TOPRIGHT", -1, -HEAD_H)

    -- summary: counts and a progress track (done green, skipped grey, a
    -- marker where you are)
    f.count = NavText(f, 0, C.text)
    f.count:SetPoint("TOPLEFT", S.lg, -HEAD_H - 10)
    f.stats = NavText(f, -1, C.dim)
    f.stats:SetPoint("TOPRIGHT", -S.lg, -HEAD_H - 11)
    f.stats:SetJustifyH("RIGHT")
    f.track = f:CreateTexture(nil, "ARTWORK")
    f.track:SetPoint("TOPLEFT", S.lg, -HEAD_H - 32)
    f.track:SetPoint("TOPRIGHT", -S.lg, -HEAD_H - 32)
    f.track:SetHeight(4)
    Fill(f.track, { 1, 1, 1 }, 0.07)
    f.doneBar = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.doneBar:SetPoint("LEFT", f.track, "LEFT")
    f.doneBar:SetHeight(4)
    Fill(f.doneBar, C.green, 0.9)
    f.skipBar = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.skipBar:SetHeight(4)
    Fill(f.skipBar, C.faint, 0.7)
    f.here = f:CreateTexture(nil, "OVERLAY")
    f.here:SetTexture(TEX .. "filledcircle")
    f.here:SetSize(10, 10)
    Tint(f.here, C.blue)

    -- tabs
    f.tabBar = CreateFrame("Frame", nil, f)
    f.tabBar:SetPoint("TOPLEFT", 1, -HEAD_H - SUM_H)
    f.tabBar:SetPoint("TOPRIGHT", -1, -HEAD_H - SUM_H)
    f.tabBar:SetHeight(TABS_H)
    f.tabLine = PlainLine(f.tabBar)
    f.tabLine:SetPoint("BOTTOMLEFT")
    f.tabLine:SetPoint("BOTTOMRIGHT")
    f.tabs = {}
    local x = S.sm
    for _, def in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, f.tabBar)
        tab.key = def[1]
        tab.label = NavText(tab, 0, C.dim)
        tab.label:SetPoint("CENTER", 0, 1)
        tab.label:SetText(L(def[2]))
        local w = math.max(56, (tab.label:GetStringWidth() or 40) + 20)
        tab:SetSize(w, TABS_H)
        tab:SetPoint("BOTTOMLEFT", x, 0)
        tab.x = x
        x = x + w
        tab:SetScript("OnClick", function(self) Nav.SetFilter(self.key) end)
        tab:SetScript("OnEnter", function(self) if self.key ~= Nav.filter then TextColor(self.label, C.text) end end)
        tab:SetScript("OnLeave", function() PaintTabs(false) end)
        f.tabs[#f.tabs + 1] = tab
    end
    f.underline = f.tabBar:CreateTexture(nil, "OVERLAY")
    f.underline:SetHeight(2)
    Fill(f.underline, C.blue)

    -- the list, clipped to its area
    f.list = CreateFrame("Frame", nil, f)
    f.list:SetPoint("TOPLEFT", 1, -HEAD_H - SUM_H - TABS_H - 4)
    f.list:SetPoint("BOTTOMRIGHT", -1, FOOT_H + 2)
    if f.list.SetClipsChildren then f.list:SetClipsChildren(true) end
    f.list:SetScript("OnSizeChanged", function() Nav.Paint() end)

    -- scrollbar: a thin thumb on the right, drag it or click the track
    local bar = CreateFrame("Button", nil, f)
    bar:SetWidth(12)
    bar:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", -2, -4)
    bar:SetPoint("BOTTOMRIGHT", f.list, "BOTTOMRIGHT", -2, 4)
    bar:SetFrameLevel(f:GetFrameLevel() + 20)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetPoint("TOPRIGHT", -4, 0)
    bar.track:SetPoint("BOTTOMRIGHT", -4, 0)
    bar.track:SetWidth(3)
    Fill(bar.track, { 1, 1, 1 }, 0.04)
    bar.thumb = CreateFrame("Button", nil, bar)
    bar.thumb:SetWidth(12)
    bar.thumb.tex = bar.thumb:CreateTexture(nil, "OVERLAY")
    bar.thumb.tex:SetPoint("TOPRIGHT", -4, 0)
    bar.thumb.tex:SetPoint("BOTTOMRIGHT", -4, 0)
    bar.thumb.tex:SetWidth(3)
    Fill(bar.thumb.tex, { 1, 1, 1 }, 0.25)
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / (bar:GetEffectiveScale() or 1)
    end
    local function Follow(self)
        -- released anywhere (OnMouseUp only comes when it's over the thumb)
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            self:SetScript("OnUpdate", nil)
            Fill(self.tex, { 1, 1, 1 }, 0.25)
            return
        end
        if (bar.travel or 0) <= 0 then return end
        Nav.ScrollTo(self.startOffset + (self.startY - CursorY()) / bar.travel * MaxOffset(), true)
    end
    bar.thumb:SetScript("OnMouseDown", function(self)
        self.startY, self.startOffset = CursorY(), Nav.offset
        self:SetScript("OnUpdate", Follow)
        Fill(self.tex, C.blue, 0.9)
    end)
    bar.thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        Fill(self.tex, { 1, 1, 1 }, 0.25)
    end)
    bar.thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    bar:SetScript("OnClick", function()
        local top = bar.thumb:GetTop()
        local page = ListH() * 0.85
        Nav.ScrollTo(Nav.offset + ((top and CursorY() > top) and -page or page))
    end)
    f.bar = bar

    f:SetScript("OnMouseWheel", function(_, delta)
        local by = (IsShiftKeyDown and IsShiftKeyDown()) and ITEM_H * 8 or ITEM_H * 2
        Nav.ScrollTo((Nav.target or Nav.offset) - delta * by)
    end)

    -- footer
    f.foot = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.foot:SetPoint("BOTTOMLEFT", 1, 1)
    f.foot:SetPoint("BOTTOMRIGHT", -1, 1)
    f.foot:SetHeight(FOOT_H)
    f.footLine = PlainLine(f)
    f.footLine:SetPoint("BOTTOMLEFT", 1, FOOT_H + 1)
    f.footLine:SetPoint("BOTTOMRIGHT", -1, FOOT_H + 1)
    f.hint = NavText(f, -1, C.faint)
    f.hint:SetPoint("BOTTOMLEFT", S.lg, FOOT_H / 2 - 5)
    f.hint:SetText(L("Click a step to go there"))
    f.mine = Style.Button(f, L("Back to my step"), "secondary", 130, function()
        if Engine.IsHeld() then OXP.Card.Resume() end
        Nav.Refresh(true)
        Nav.ScrollToCurrent()
    end)
    f.mine:SetHeight(26)
    f.mine:SetPoint("BOTTOMRIGHT", -S.sm, (FOOT_H - 26) / 2 + 1)

    -- HookScript, not SetScript: Style.Shadow already hooked OnHide to hide
    -- the shadow frame (a SetScript here wiped that and left the shadow, a
    -- big dark box, on screen after closing)
    f:HookScript("OnHide", function()
        f:SetAlpha(1)
        for _, row in ipairs(rows) do if row.pulse then row.pulse:Stop() end end
        if OXP.Card and OXP.Card.header and OXP.Card.header.nav then
            Tint(OXP.Card.header.nav.bg, C.blue, 0)
        end
    end)
    f:Hide()
    PaintTabs(false)
    Nav.ApplySkin()
end

---------------------------------------------------------------------------
-- Open, close, refresh
---------------------------------------------------------------------------

--- Places the panel beside the card, on the side with room, as tall as
--- the card (at least MIN_H).
function Nav.Place()
    local card = OXP.Card and OXP.Card.frame
    f:ClearAllPoints()
    local h = math.max(MIN_H, math.min(MAX_H, (card and card:GetHeight() or 0) * (card and card:GetScale() or 1)))
    f:SetHeight(h)
    if not card then f:SetPoint("CENTER") return end
    local left = (card:GetLeft() or 0) * (card:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    if left > WIDTH + 20 then
        f.side = "left"
        f:SetPoint("TOPRIGHT", card, "TOPLEFT", -6, 0)
    else
        f.side = "right"
        f:SetPoint("TOPLEFT", card, "TOPRIGHT", 6, 0)
    end
end

function Nav.IsShown() return f ~= nil and f:IsShown() end

--- Rebuilds the list (a new step, filter or guide); `force`: even when
--- nothing moved.
function Nav.Refresh(force)
    if not (f and f:IsShown()) then return end
    local guide = Engine.GetGuide()
    f.guide:SetText(guide and Text.Strip(guide.name or "") or L("No guide loaded"))
    local key = tostring(guide) .. ":" .. tostring(Engine.GetPosition()) .. ":" .. Nav.filter .. ":" .. #Engine.GetSteps()
    if force or key ~= Nav.itemsKey then
        local moved = Nav.itemsKey ~= nil and key ~= Nav.itemsKey
        Nav.items = Nav.Items()
        Nav.itemsKey = key
        if moved and not force then Nav.ScrollToCurrent() end
    end
    f.mine:SetEnabled(Engine.IsHeld())
    PaintSummary()
    Nav.Paint()
end

function Nav.Show()
    if not f then Build() end
    -- opened again while it was fading out: stop the fade (its end would
    -- hide the panel again)
    Style.Tween(f, 1, 1, 0, function(a) f:SetAlpha(a) end)
    Nav.ApplySkin()
    Nav.Place()
    Nav.items, Nav.itemsKey = nil, nil
    f:Show()
    Nav.Refresh(true)
    Nav.ScrollToCurrent(true)
    -- in: a short fade and a slide out from the card's side
    local dx = f.side == "left" and 14 or -14
    local p1, rel, p2, x, y = f:GetPoint()
    Style.Tween("OXPStepNavOpen", 0, 1, 0.18, function(v)
        f:SetAlpha(v)
        if p1 then
            f:ClearAllPoints()
            f:SetPoint(p1, rel, p2, (x or 0) + dx * (1 - v), y or 0)
        end
    end)
end

function Nav.Hide()
    if not (f and f:IsShown()) then return end
    Style.Fade(f, false, 0.12)
end

function Nav.Toggle()
    if Nav.IsShown() then Nav.Hide() else Nav.Show() end
end

--- Paints the panel like the card (UI/Card.lua Card.ApplySkin): the
--- skin's background at the card's Background opacity, the header and
--- footer bands and thin lines the same way, no background, lines or
--- shadow in Minimal (or at 0%), and the card's font, size and outline.
function Nav.ApplySkin()
    if not f then return end
    local o = Style.CardOpacity()
    local bare = Style.Frameless()
    local skin = Style.skin
    local line = bare and 0 or skin.line * math.min(1, o * 1.4)
    Style.PaintBackdrop(f)
    local band = bare and 0 or math.max(skin.header or 0, 0.03) * o
    f.head:SetColorTexture(1, 1, 1, band)
    f.foot:SetColorTexture(1, 1, 1, band)
    for _, t in ipairs({ f.headLine, f.footLine, f.tabLine }) do t:SetColorTexture(1, 1, 1, line) end
    f.track:SetColorTexture(1, 1, 1, bare and 0.12 or 0.07)
    if f.shadow then f.shadow:SetAlpha(bare and 0 or o) end
    for _, spec in ipairs(navFonts) do Style.SetFont(spec[1], spec[2]) end
    for _, row in ipairs(rows) do row.headerLine:SetAlpha(bare and 0 or 1) end
    Nav.lineAlpha = line
    if f:IsShown() then
        PaintTabs(false)
        Nav.Paint()
    end
end
OXP.Listen("SETTINGS_CHANGED", function() Nav.ApplySkin() end)

for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED" }) do
    OXP.Listen(m, function() OXP.Soon("STEPNAV", function() Nav.Refresh() end) end)
end
OXP.AddCommand("steps", "open the step list", function() Nav.Toggle() end)
