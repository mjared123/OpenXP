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
-- The font comes from Settings > Guide Window > Font (Locale.lua, addon.fonts)
local DEFAULT_FONT = (addon.SafeFont and addon.SafeFont("Fonts\\ARIALN.TTF") or "Fonts\\ARIALN.TTF")
-- Never let a font problem stop this file from loading: if it did, the card
-- would never start and the engine's old window would show instead.
local function Font()
    if not addon.fonts then return DEFAULT_FONT end
    local ok, path = pcall(addon.fonts.Path)
    return (ok and path) or DEFAULT_FONT
end
-- Set the chosen font on a font string; if the game refuses it (missing or
-- broken file), use the default so the text never goes blank.
local fontStrings = setmetatable({}, {__mode = "k"})
local function ApplyFont(fs, font, size, flags)
    fontStrings[fs] = true
    local ok, res = pcall(fs.SetFont, fs, font, size, flags or "")
    if (not ok or res == false) and font ~= DEFAULT_FONT then
        pcall(fs.SetFont, fs, DEFAULT_FONT, size, flags or "")
    end
end
local WIDTH = 330 -- default; the card can be resized
local MIN_W, MIN_H, MAX_W, MAX_H = 200, 120, 640, 900
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

-- The Text outline setting; text that already has an outline (the arrow)
-- only changes when a thick outline is picked.
local function Flags(flags)
    local chosen = addon.fonts and addon.fonts.Outline() or ""
    if chosen == "" then return flags or "" end
    if flags and flags ~= "" and chosen ~= "THICKOUTLINE" then return flags end
    return chosen
end

local function SetFont(fs, offset, flags)
    ApplyFont(fs, Font(), FontSize(offset), Flags(flags))
end

-- Text with a size of its own (button labels): remembered so a font change
-- reaches it without a /reload.
local fixedText = {}
local function FixedFont(fs, size, flags)
    fixedText[fs] = {size, flags}
    ApplyFont(fs, Font(), size, Flags(flags))
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

-- "Step 12 / 82" opens the step list
header.stepBtn = CreateFrame("Button", nil, header)
header.stepBtn:SetPoint("TOPRIGHT", 0, 0)
header.stepBtn:SetPoint("BOTTOMRIGHT", 0, 0)
header.stepBtn:SetWidth(80)
header.stepBtn:SetScript("OnClick", function() card.ToggleStepList() end)
header.stepBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L("Show every step in this guide"), 1, 1, 1)
    GameTooltip:AddLine(L("Click a step to jump to it. Mouse wheel scrolls."), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
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
-- Status tags: a small rounded-looking pill on steps you're past
---------------------------------------------------------------------------

local STATUS = {
    done = {text = "DONE", color = C.green, tip = "You finished this step."},
    skipped = {text = "SKIPPED", color = C.faint, tip = "You moved past this step without finishing it."},
    chain = {text = "CHAIN MISSED", color = C.gold,
             tip = "An earlier quest in this chain was skipped, so this one can't be picked up yet."},
}
card.STATUS = STATUS

local function MakePill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(14)
    pill.bg = pill:CreateTexture(nil, "BACKGROUND")
    pill.bg:SetPoint("TOPLEFT", 1, 0)
    pill.bg:SetPoint("BOTTOMRIGHT", -1, 0)
    pill.bg:SetTexture(WHITE)
    -- 1px end caps, inset vertically, fake the rounded ends
    pill.l = pill:CreateTexture(nil, "BACKGROUND")
    pill.l:SetPoint("TOPLEFT", 0, -1)
    pill.l:SetPoint("BOTTOMLEFT", 0, 1)
    pill.l:SetWidth(1)
    pill.l:SetTexture(WHITE)
    pill.r = pill:CreateTexture(nil, "BACKGROUND")
    pill.r:SetPoint("TOPRIGHT", 0, -1)
    pill.r:SetPoint("BOTTOMRIGHT", 0, 1)
    pill.r:SetWidth(1)
    pill.r:SetTexture(WHITE)
    pill.text = pill:CreateFontString(nil, "OVERLAY")
    pill.text:SetPoint("CENTER", 0, 0)
    function pill:SetStatus(status)
        local st = status and STATUS[status]
        if not st then self:Hide(); return end
        ApplyFont(self.text, Font(), FontSize(-3), Flags(""))
        self.text:SetText(L(st.text))
        self.text:SetTextColor(st.color[1], st.color[2], st.color[3], 1)
        for _, t in ipairs({self.bg, self.l, self.r}) do
            t:SetVertexColor(st.color[1], st.color[2], st.color[3], 0.16)
        end
        self:SetWidth((self.text:GetStringWidth() or 30) + 12)
        self:SetHeight(math.max(14, FontSize(-3) + 5))
        self:Show()
    end
    pill:Hide()
    return pill
end
card.MakePill = MakePill

---------------------------------------------------------------------------
-- History: scroll the mouse wheel up over the card to see the steps you've
-- passed, each tagged Done, Skipped or Chain missed. Click one to go back.
---------------------------------------------------------------------------

local HIST_ROWS = 6
local HIST_ROW_H = 20
local hist = CreateFrame("Frame", nil, f)
hist:SetPoint("TOPLEFT", progressBg, "BOTTOMLEFT", 0, 0)
hist:SetPoint("TOPRIGHT", progressBg, "BOTTOMRIGHT", 0, 0)
hist:SetHeight(1)
hist.bg = hist:CreateTexture(nil, "BACKGROUND")
hist.bg:SetAllPoints()
hist.bg:SetColorTexture(0, 0, 0, 0.18)
hist.label = hist:CreateFontString(nil, "OVERLAY")
hist.label:SetPoint("TOPLEFT", PAD, -8)
hist.label:SetTextColor(unpack(C.dim))
hist.hint = hist:CreateFontString(nil, "OVERLAY")
hist.hint:SetPoint("TOPRIGHT", -PAD, -8)
hist.hint:SetTextColor(unpack(C.faint))
hist.sep = hist:CreateTexture(nil, "ARTWORK")
hist.sep:SetPoint("BOTTOMLEFT")
hist.sep:SetPoint("BOTTOMRIGHT")
hist.sep:SetHeight(1)
hist.sep:SetColorTexture(1, 1, 1, 0.07)
hist.rows = {}
hist:Hide()
card.hist = hist
card.histOffset = 0

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
            ApplyFont(self.glyph, Font(), math.floor(size * 0.6), "")
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
    -- step number under the badge, so stacked steps are easy to tell apart
    b.num = b:CreateFontString(nil, "OVERLAY")
    b.num:SetPoint("TOP", b.badge, "BOTTOM", 0, -4)
    b.num:SetJustifyH("CENTER")
    b.num:SetTextColor(unpack(C.faint))
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
    if addon.ReplaceNpcIds then text = addon.ReplaceNpcIds(L(text), e and e.step and e or nil) end
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

---------------------------------------------------------------------------
-- Quest data: read from Questie while the game runs, when it's installed.
-- OpenXP ships no quest database of its own, so nothing goes out of date
-- and nothing of Questie's is copied into OpenXP.
-- card.Prereqs(id) -> {any=, all=, excl=}; card.QuestInfoOf(id) -> {n, l, r, s, f, o}
-- A spot is {name, uiMapId, x, y}. Tests can fill card.data instead.
---------------------------------------------------------------------------

card.data = card.data or {}
local questie, zoneDB
-- Questie may load after OpenXP and builds its database after login, so
-- keep asking until it's there
local function Questie()
    if not questie then
        local loader = _G.QuestieLoader
        if loader and loader.ImportModule then
            local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
            if ok and db and type(db.GetQuest) == "function" then questie = db end
            local okZ, z = pcall(loader.ImportModule, loader, "ZoneDB")
            if okZ then zoneDB = z end
        end
    end
    return questie or nil
end
function card.HasQuestData()
    return Questie() ~= nil or card.data.prereqs ~= nil
end

-- Questie builds a fresh table on every lookup, and the card, the map and
-- the tooltips ask for the same few quests and NPCs many times a second,
-- so keep what it returned (its data doesn't change while you play)
local qcache, qcount = {}, 0
local QCACHE_MAX = 3000
local function QGet(kind, id)
    local db = Questie()
    if not (db and id) then return end
    local key = kind .. ":" .. tostring(id)
    local hit = qcache[key]
    if hit then return hit end
    local fn = db["Get" .. kind]
    if type(fn) ~= "function" then return end
    if qcount >= QCACHE_MAX then qcache, qcount = {}, 0 end
    -- Questie defines some of these as QuestieDB.GetX(id), others as
    -- QuestieDB:GetX(id); try both
    local ok, obj = pcall(fn, id)
    if ok and type(obj) == "table" then card.questieStyle = "dot"; qcache[key] = obj; qcount = qcount + 1; return obj end
    ok, obj = pcall(fn, db, id)
    if ok and type(obj) == "table" then card.questieStyle = "colon"; qcache[key] = obj; qcount = qcount + 1; return obj end
    -- nothing yet: Questie may still be building its database, ask again later
end
card.QGet = QGet -- also used by the tooltips (OpenXPTooltips.lua)

local function UiMap(areaId)
    if zoneDB and zoneDB.GetUiMapIdByAreaId then
        local ok, m = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
        if ok and m and m > 0 then return m end
    end
end

-- Densest spawn area, and the spawn nearest its middle
local function SpotOf(obj, preferArea)
    local spawns = obj and obj.spawns
    if type(spawns) ~= "table" then return end
    local bestArea, bestPts, bestScore
    for area, pts in pairs(spawns) do
        if type(pts) == "table" and #pts > 0 and UiMap(area) then
            local score = #pts + (area == preferArea and 10000 or 0)
            if not bestScore or score > bestScore then
                bestArea, bestPts, bestScore = area, pts, score
            end
        end
    end
    if not bestArea then return end
    local sx, sy, n = 0, 0, 0
    for _, pt in ipairs(bestPts) do
        if pt[1] and pt[1] >= 0 then sx, sy, n = sx + pt[1], sy + pt[2], n + 1 end
    end
    if n == 0 then return end
    sx, sy = sx / n, sy / n
    local best, bestD
    for _, pt in ipairs(bestPts) do
        if pt[1] and pt[1] >= 0 then
            local d = (pt[1] - sx) ^ 2 + (pt[2] - sy) ^ 2
            if not bestD or d < bestD then best, bestD = pt, d end
        end
    end
    return {obj.name or "?", UiMap(bestArea), best[1], best[2]}
end

local function Ender(ref, zone)
    if type(ref) ~= "table" then return end
    for _, nid in ipairs(ref[1] or {}) do
        local s = SpotOf(QGet("NPC", nid), zone)
        if s then return s end
    end
    for _, oid in ipairs(ref[2] or {}) do
        local s = SpotOf(QGet("Object", oid), zone)
        if s then return s end
    end
    for _, iid in ipairs(ref[3] or {}) do
        local item = QGet("Item", iid)
        if item then return {item.name or "?", 0, 0, 0} end
    end
end

local playerRaceBit
local function ForPlayer(q)
    local races = q and (q.requiredRaces or 0) or 0
    if races == 0 then return true end
    if not playerRaceBit then
        local id = UnitRace and select(3, UnitRace("player"))
        playerRaceBit = id and 2 ^ (id - 1) or 0
    end
    if playerRaceBit == 0 or not bit then return true end
    return bit.band(races, playerRaceBit) ~= 0
end

local prereqCache, infoCache = {}, {}
function card.Prereqs(id)
    if card.data.prereqs then return card.data.prereqs[id] end
    if prereqCache[id] ~= nil then return prereqCache[id] or nil end
    local q = QGet("Quest", id)
    if not q then return end -- unknown, or Questie not ready yet: ask again later
    local pre = false
    if q and (q.preQuestSingle or q.preQuestGroup or q.exclusiveTo) then
        local function abs(list)
            if type(list) ~= "table" or #list == 0 then return end
            local out = {}
            for i, v in ipairs(list) do out[i] = math.abs(v) end
            return out
        end
        pre = {any = abs(q.preQuestSingle), all = abs(q.preQuestGroup), excl = abs(q.exclusiveTo)}
        if not (pre.any or pre.all or pre.excl) then pre = false end
    end
    prereqCache[id] = pre
    return pre or nil
end

function card.QuestInfoOf(id)
    if card.data.info then return card.data.info[id] end
    if infoCache[id] ~= nil then return infoCache[id] or nil end
    local q = QGet("Quest", id)
    if not q then return end
    local info = false
    if q then
        local zone = q.zoneOrSort
        local objs = {}
        local o = q.objectives
        if type(o) == "table" then
            for _, e in ipairs(o[1] or {}) do tinsert(objs, SpotOf(QGet("NPC", e[1]), zone)) end
            for _, e in ipairs(o[2] or {}) do tinsert(objs, SpotOf(QGet("Object", e[1]), zone)) end
            for _, e in ipairs(o[3] or {}) do
                local item = QGet("Item", e[1])
                local src = item and (item.npcDrops and item.npcDrops[1] and SpotOf(QGet("NPC", item.npcDrops[1]), zone) or
                                      item.objectDrops and item.objectDrops[1] and SpotOf(QGet("Object", item.objectDrops[1]), zone))
                if src then tinsert(objs, src) end
            end
        end
        info = {n = q.name, l = q.level or q.questLevel or 0, r = q.requiredLevel or 0,
                s = Ender(q.startedBy, zone), f = Ender(q.finishedBy, zone), o = objs, q = q}
    end
    infoCache[id] = info
    return info or nil
end

-- Earlier quests in the chain, in the order you do them
function card.Chain(id)
    if card.data.chains then return card.data.chains[id] or {} end
    local order, seen = {}, {}
    local function visit(x, depth)
        if seen[x] or depth > 25 then return end
        seen[x] = true
        local pre = card.Prereqs(x)
        if pre then
            if pre.any then
                local pick
                for _, p in ipairs(pre.any) do
                    if addon.IsQuestTurnedIn and addon.IsQuestTurnedIn(p) then pick = nil; break end
                    local info = card.QuestInfoOf(p)
                    if not pick and (not info or ForPlayer(info.q)) then pick = p end
                end
                if pick then visit(pick, depth + 1) end
            end
            for _, p in ipairs(pre.all or {}) do
                local info = card.QuestInfoOf(p)
                if not info or ForPlayer(info.q) then visit(p, depth + 1) end
            end
        end
        tinsert(order, x)
    end
    visit(id, 0)
    table.remove(order)
    return order
end

-- Pickup steps for quests you can't get yet (a pre-quest you skipped, or
-- one you did that locks this one out) send you to a giver who has nothing
-- for you. DB/forever/QuestPrereqs.lua lists what each guide quest needs.
local function TurnedIn(id)
    return addon.IsQuestTurnedIn and addon.IsQuestTurnedIn(math.abs(id))
end

-- A breadcrumb only sends you to another quest's giver (The Hermit sends you
-- to Abercrombie for Supplies from Darkshire). Once you have, or have done,
-- the quest it leads to, the game stops offering the breadcrumb. Returns
-- that quest's id when this quest is such a breadcrumb, else nil.
function card.BreadcrumbFor(id)
    if card.data.breadcrumbs then return card.data.breadcrumbs[id] end
    local q = QGet("Quest", id)
    local to = q and tonumber(q.breadcrumbForQuestId)
    if to and to ~= 0 then return math.abs(to) end
end

-- The quest a breadcrumb leads to, when you have it or did it already (so
-- the breadcrumb can't be picked up or turned in any more), else nil
function card.BreadcrumbClosed(id)
    if (addon.IsOnQuest and addon.IsOnQuest(id)) or TurnedIn(id) then return end
    local to = card.BreadcrumbFor(id)
    if to and ((addon.IsOnQuest and addon.IsOnQuest(to)) or TurnedIn(to)) then return to end
end

-- Returns the quest that has to be done first, or nil when it can be picked up
function card.QuestBlocked(id)
    local pre = card.Prereqs(id)
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

-- The earlier step in this guide where the first quest of a missed chain
-- is picked up (one you don't have yet), or nil when the guide doesn't
-- pick it up before this step
function card.ChainBackStep(guide, chain, index)
    if not (guide and guide.steps and index) then return end
    for _, q in ipairs(chain or {}) do
        if not TurnedIn(q) and not (addon.IsOnQuest and addon.IsOnQuest(q)) then
            local steps = guide.steps
            for i = math.min(index - 1, #steps), 1, -1 do
                for _, e in ipairs(steps[i] and steps[i].elements or {}) do
                    if e.tag == "accept" and QuestIdOf(e) == q then return i end
                end
            end
            return
        end
    end
end

-- Go back to where the chain starts. The step there may be marked skipped
-- from when you passed it; it isn't any more. Once the quest you came from
-- can be done the guide brings you back to it (see Tick).
function card.ChainBack(m)
    local guide = addon.currentGuide
    if not (guide and m and m.back and m.step) then return end
    if OXPCData and OXPCData.stepSkip then OXPCData.stepSkip[m.back] = nil end
    card.MarkStatus(guide, m.back, nil)
    if guide.steps[m.back] then guide.steps[m.back].completed = nil end
    card.returnTo = {guide = guide, step = m.step, quest = m.quest, chain = true,
                     needAccept = m.needAccept}
    card.hold = nil
    card.ManualSetStep(m.back)
    card.Refresh(true)
end

local function TextButton(parent, text, tip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(22)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(1, 1, 1, 0.08)
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetPoint("CENTER")
    FixedFont(btn.label, 12, "")
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
    return card.QuestInfoOf(id)
end

local function QuestName(id)
    local info = QuestInfo(id)
    return (info and info.n) or (addon.GetQuestName and addon.GetQuestName(id)) or fmt("#%d", id)
end

-- Earlier quests in the chain that you still have to turn in, in order
function card.MissingChain(id)
    local out = {}
    for _, q in ipairs(card.Chain(id)) do
        if not TurnedIn(q) then tinsert(out, q) end
    end
    return out
end

-- Only ask about a chain when you really missed part of it: a quest before
-- this one that's neither done nor in your log, and that this step doesn't
-- take care of itself. While you're working through the chain (the quest
-- before is in your log, or this very step turns it in) there's nothing to ask.
-- A turn in or kill step is different: it needs the quest itself, so an
-- earlier part that's only in your log (not turned in) still has to be done
-- first, and the card asks.
function card.ChainMissed(step, id, blocker, chain, needAccept)
    local here = {}
    for _, e in ipairs(step and step.elements or {}) do
        local q = QuestIdOf(e)
        if q and (e.tag == "turnin" or e.tag == "accept" or e.tag == "complete") then here[q] = true end
    end
    local function missed(q)
        if not q or q == id or here[q] or TurnedIn(q) then return false end
        if needAccept then return true end
        return not (addon.IsOnQuest and addon.IsOnQuest(q))
    end
    for _, q in ipairs(chain or {}) do
        if missed(q) then return true end
    end
    -- no chain known: ask only when what's in the way isn't in hand
    return #(chain or {}) == 0 and missed(blocker)
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
            -- a turn in for a quest you have but haven't finished (you skipped
            -- the part of the route where its objectives were done)
            if e.tag == "turnin" and addon.IsOnQuest and addon.IsOnQuest(id) and
                addon.IsQuestComplete and not addon.IsQuestComplete(id) then
                return {kind = "unfinished", quest = id}
            end
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
                    local pre = card.Prereqs(id)
                    local isExcl = false
                    for _, q in ipairs(pre.excl or {}) do
                        if math.abs(q) == blocker then isExcl = true end
                    end
                    if isExcl then
                        return {kind = "locked", quest = id, by = blocker}
                    end
                    local chain = card.MissingChain(id)
                    if card.ChainMissed(step, id, blocker, chain, needAccept) then
                        return {kind = "chain", quest = id, chain = chain,
                                needAccept = needAccept}
                    end
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
    if d.mode == "complete" then
        return TurnedIn(d.target) or not (addon.IsOnQuest and addon.IsOnQuest(d.target)) or
                   (addon.IsQuestComplete and addon.IsQuestComplete(d.target))
    end
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
        if not TurnedIn(q) and not (q == d.target and onIt and d.mode ~= "complete") then
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
                card.hold = nil
                card.ManualSetStep(m.accept)
            else
                card.StartDetour(m.quest, {m.quest}, "have")
            end
        end)
    w.back = TextButton(w, L("Go back to it"),
        L("Go back to the step where the guide picks up the first quest of this chain. Once the chain is done the guide brings you back here."),
        function()
            local m = b.missing
            if m and m.back then card.ChainBack(m) end
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
    w.finish = TextButton(w, L("Finish it"),
        L("Do this quest's objectives now, with the arrow. When they're done the guide brings you back to turn it in."),
        function()
            local m = b.missing
            if m then card.StartDetour(m.quest, {m.quest}, "complete") end
        end)
    w.skip = TextButton(w, L("Skip this step"), L("Move on without this quest"), function()
        local m = b.missing
        if m and addon.currentGuide then
            card.MarkStatus(addon.currentGuide, m.step, "skipped")
            card.hold = nil
            card.ManualSetStep(m.step + 1)
        end
    end)
    b.warn = w
    return w
end

-- "now" for the step you're on, "side" for a background step that stays
-- open while you do others, "done" for a finished one
function card.StepRole(step, current)
    if step.detour then return "now" end
    if step.completed then return "done" end
    local any, open = false, false
    for _, e in ipairs(step.elements or {}) do
        if e.tag and e.tag ~= "goto" and e.tag ~= "target" and not e.textOnly then
            any = true
            if not (e.completed or e.skip) then open = true end
        end
    end
    if any and not open then return "done" end
    if step.sticky or step.completewith or (current and step.index and step.index < current) then
        return "side"
    end
    return "now"
end

-- Show the first error of a session in chat so it can be reported, instead
-- of the card silently stopping
local reported = {}
function card.ReportError(err)
    err = tostring(err)
    card.lastError = err
    if reported[err] then return end
    reported[err] = true
    print("|cFFFF7043OpenXP card error|r (please send this to the OpenXP author): " .. err)
end

local function LayoutBlock(b, step, first)
    local textWidth = Width() - PAD * 2 - 34 - 12
    b.sep:SetShown(not first)
    b.badge:SetKind(StepKind(step))
    SetFont(b.num, -2)
    b.num:SetText(step.index and not step.detour and ("#" .. step.index) or "")

    local title, lines = StepContent(step)
    local role = card.StepRole(step, addon.GetGuideProgress and addon.GetGuideProgress())
    if role == "side" then
        title = "|cFF9EA3B3" .. L("ALONG THE WAY") .. ":|r " .. title
    elseif role == "done" then
        title = "|cFF3DBB7A" .. L("DONE") .. ":|r " .. StripCodes(title)
    end
    b:SetAlpha(role == "done" and 0.45 or role == "side" and 0.8 or 1)
    -- a pickup step is where you get the quest; say so, since it isn't in your log yet
    if role == "now" and not step.detour then
        for _, e in ipairs(step.elements or {}) do
            local id = tonumber(e.questId)
            if e.tag == "accept" and id and id > 0 and not e.completed and
                not (addon.IsOnQuest and addon.IsOnQuest(id)) and not card.QuestBlocked(id) then
                tinsert(lines, {text = "|cFF9EA3B3" .. L("You get this quest at this step") .. "|r", plain = true})
                break
            end
        end
        -- a later step you're standing next to, done first
        local here = card.here
        if here and step.index == here.index then
            tinsert(lines, 1, {text = "|cFFF2C35C" .. fmt(L("You're right here, so do this first. Then back to step %d."), here.from) .. "|r", plain = true})
        end
        -- the step is in another zone: how to get there
        local tv = addon.travel
        local plan = tv and tv.Current and tv.Current()
        local travel = plan and plan.target and plan.target.step == step and tv.Lines()
        if travel and #travel > 0 then
            tinsert(lines, {text = "|cFFB36BFF" .. L("Getting there:") .. "|r", plain = true})
            for _, t in ipairs(travel) do
                if #lines >= MAX_LINES then break end
                tinsert(lines, {text = t, plain = true})
            end
        end
    end
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

    local problem
    if step.index and not step.detour then
        local ok, res = pcall(card.StepProblem, step)
        if ok then problem = res else card.ReportError(res) end
    end
    if problem then
        local w = GetWarn(b)
        local id = problem.quest
        local m = {quest = id, step = step.index, chain = problem.chain, needAccept = problem.needAccept}
        local text, list, buttons = nil, nil, {}
        if problem.kind == "unfinished" then
            text = fmt(L("You haven't finished %s yet"), QuestName(id))
            local rows = {}
            for _, o in ipairs(ObjectivesOf(id)) do
                tinsert(rows, (o.finished and "|cFF3DBB7A" .. L("Done") .. ":|r " or "- ") .. tostring(o.text or ""))
            end
            if #rows > 0 then list = table.concat(rows, "\n") end
            buttons = {w.finish, w.skip}
        elseif problem.kind == "missing" then
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
                m.back = card.ChainBackStep(addon.currentGuide, chain, step.index)
                if m.back then
                    w.back.label:SetText(fmt(L("Go back to step %d"), m.back))
                    w.back:SetWidth(math.max(70, (w.back.label:GetStringWidth() or 60) + 18))
                    buttons = {w.back, w.chain, w.skip}
                else
                    buttons = {w.chain, w.skip}
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
        w.get:Hide(); w.back:Hide(); w.chain:Hide(); w.finish:Hide(); w.skip:Hide()
        local anchor = list and w.list or w.text
        -- buttons go side by side, and wrap to a new row on a narrow card
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
        y = y + h + 8
    else
        b.missing = nil
        if b.warn then b.warn:Hide() end
    end

    local height = math.max(y + 4, 34 + 20 + (b.num:GetText() ~= "" and 14 or 0))
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

-- Level progress along the bottom edge: gold for XP, faint blue for rested.
-- Hover it for XP per hour and time to level this session.
local xpStrip = CreateFrame("Frame", nil, bar)
xpStrip:SetPoint("BOTTOMLEFT", 0, 0)
xpStrip:SetPoint("BOTTOMRIGHT", 0, 0)
xpStrip:SetHeight(8)
xpStrip:EnableMouse(true)
xpStrip.bg = xpStrip:CreateTexture(nil, "ARTWORK")
xpStrip.bg:SetPoint("BOTTOMLEFT")
xpStrip.bg:SetPoint("BOTTOMRIGHT")
xpStrip.bg:SetHeight(3)
xpStrip.bg:SetColorTexture(1, 1, 1, 0.06)
xpStrip.rested = xpStrip:CreateTexture(nil, "ARTWORK", nil, 1)
xpStrip.rested:SetPoint("BOTTOMLEFT")
xpStrip.rested:SetHeight(3)
xpStrip.rested:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 0.35)
xpStrip.fill = xpStrip:CreateTexture(nil, "ARTWORK", nil, 2)
xpStrip.fill:SetPoint("BOTTOMLEFT")
xpStrip.fill:SetHeight(3)
xpStrip.fill:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.9)
card.xpStrip = xpStrip

local xpSession = {}
function card.ResetXPSession() xpSession = {} end
function card.XPStats()
    local cur, max = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
    local level = UnitLevel and UnitLevel("player") or 0
    local now = GetTime and GetTime() or 0
    if not xpSession.start or xpSession.level ~= level and level < (xpSession.level or 0) then
        xpSession.start, xpSession.gained, xpSession.level, xpSession.last = now, 0, level, cur
    end
    if xpSession.level ~= level then
        -- dinged: the rest of the old level counts too
        xpSession.gained = xpSession.gained + math.max(0, (xpSession.lastMax or 0) - (xpSession.last or 0)) + cur
        xpSession.level = level
    elseif cur > (xpSession.last or 0) then
        xpSession.gained = xpSession.gained + cur - xpSession.last
    end
    xpSession.last, xpSession.lastMax = cur, max
    local elapsed = now - xpSession.start
    local perHour = elapsed > 120 and xpSession.gained / elapsed * 3600 or nil
    local toLevel = perHour and perHour > 0 and (max - cur) / perHour * 60 or nil
    return {cur = cur, max = max, level = level, rested = GetXPExhaustion and GetXPExhaustion() or 0,
            perHour = perHour, minutes = toLevel}
end

function card.UpdateXP()
    local x = card.XPStats()
    local maxLevel = addon.player and addon.player.maxlevel or 60
    if x.max <= 0 or x.level >= maxLevel then xpStrip:Hide(); return end
    xpStrip:Show()
    local w = xpStrip:GetWidth() or 0
    if w <= 0 then w = Width() - 2 end
    xpStrip.fill:SetWidth(math.max(1, w * x.cur / x.max))
    local restedTo = math.min(x.max, x.cur + (x.rested or 0))
    xpStrip.rested:SetWidth(math.max(1, w * restedTo / x.max))
end

xpStrip:SetScript("OnEnter", function(self)
    local x = card.XPStats()
    if x.max <= 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(fmt(L("Level %d: %d%%"), x.level, math.floor(x.cur / x.max * 100)), 1, 1, 1)
    GameTooltip:AddLine(fmt(L("%d / %d XP, %d to go"), x.cur, x.max, x.max - x.cur), 0.8, 0.8, 0.8)
    if (x.rested or 0) > 0 then
        GameTooltip:AddLine(fmt(L("Rested: %d XP"), x.rested), C.blue[1], C.blue[2], C.blue[3])
    end
    if x.perHour then
        GameTooltip:AddLine(fmt(L("This session: %d XP/hour, about %d min to level"),
                                math.floor(x.perHour), math.ceil(x.minutes or 0)), C.gold[1], C.gold[2], C.gold[3])
    else
        GameTooltip:AddLine(L("XP/hour shows after a couple of minutes of play"), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end)
xpStrip:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
        FixedFont(btn.label, 13, "")
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

---------------------------------------------------------------------------
-- Moving around the guide by hand
---------------------------------------------------------------------------
-- The engine moves you forward on its own whenever the step you're on is
-- done, or its quest chain can't be done. That's right while you play, but
-- it means "go back to step 10" bounced straight forward again whenever
-- step 10 was already finished. A step you pick by hand now holds: the
-- engine can't move you past it until you press Next, pick another step,
-- or (for a step that wasn't done yet) a few seconds have passed.

local MISSING_PREREQ = "Step skipped: Missing pre-requisites"
local HOLD_SECONDS = 3

local function Now() return GetTime and GetTime() or 0 end

local function StatusRecords(guide)
    if not (guide and guide.name and OXPCData) then return {} end
    OXPCData.openxpStepStatus = OXPCData.openxpStepStatus or {}
    local t = OXPCData.openxpStepStatus[guide.name]
    if not t then
        t = {}
        OXPCData.openxpStepStatus[guide.name] = t
    end
    return t
end

local function QuestElementDone(e)
    local id = tonumber(e.questId)
    if not id or id <= 0 then return nil end
    local turnedIn = addon.IsQuestTurnedIn and addon.IsQuestTurnedIn(id)
    if e.tag == "accept" then
        return turnedIn or (addon.IsOnQuest and addon.IsOnQuest(id)) or false
    elseif e.tag == "turnin" then
        return turnedIn or false
    elseif e.tag == "complete" then
        return turnedIn or (addon.IsQuestComplete and addon.IsQuestComplete(id)) or e.completed or false
    end
end

-- A step ahead of you whose quests are all done already (you did them out
-- of order): nothing to go there for
function card.DoneAhead(step)
    local any = false
    for _, e in ipairs(step and step.elements or {}) do
        local d = QuestElementDone(e)
        if d == false then return false end
        if d then any = true end
    end
    return any
end

-- What happened to a step you're past: "done", "skipped" (you skipped it)
-- or "chain" (an earlier quest in its chain was missed, so it can't be done).
-- Steps ahead of you only get a status when they're already marked.
function card.StepStatus(guide, index, current)
    local step = guide and guide.steps and guide.steps[index]
    if not step then return end
    current = current or CurrentStep()
    local rec = StatusRecords(guide)[index]
    for _, e in ipairs(step.elements or {}) do
        if e.tooltipText == L(MISSING_PREREQ) or e.tooltipText == MISSING_PREREQ then return "chain" end
    end
    local anyQuest, allDone, blocked = false, true, false
    for _, e in ipairs(step.elements or {}) do
        local d = QuestElementDone(e)
        if d ~= nil then
            anyQuest = true
            if not d then
                allDone = false
                local id = tonumber(e.questId)
                if card.QuestBlocked and (card.QuestBlocked(id)) then blocked = true end
            end
        end
    end
    if anyQuest and allDone then return "done" end
    if rec == "chain" or blocked then return "chain" end
    if rec == "skipped" then return "skipped" end
    if step.completed then return "done" end
    local skipped = OXPCData and OXPCData.stepSkip and OXPCData.stepSkip[index]
    if skipped then return "skipped" end
    if index < current then
        return anyQuest and "skipped" or "done"
    end
end

function card.MarkStatus(guide, index, status)
    if guide and index then StatusRecords(guide)[index] = status end
end

-- Should the engine be allowed to move to step n right now?
function card.AllowStep(n)
    local here = card.here
    if here and not card.manual and n and n ~= here.index then
        -- done with the step you were standing by: the tick takes you back
        return false
    end
    local hold = card.hold
    if not hold or card.manual then return true end
    local guide = addon.currentGuide
    if not guide or guide.name ~= hold.guide then
        card.hold = nil
        return true
    end
    if not n or n <= hold.index then return true end
    if not hold.done and Now() - hold.t > HOLD_SECONDS then
        card.hold = nil
        return true
    end
    -- Nothing would be on screen (step above your level and so on): let go
    local active = addon.RXPFrame and addon.RXPFrame.activeSteps
    if CurrentStep() ~= hold.index or not active or #active == 0 then
        card.hold = nil
        return true
    end
    return false
end

function card.GuardSetStep()
    if not addon.SetStep or addon.SetStep == card.guardedSetStep then return end
    local orig = addon.SetStep
    card.guardedSetStep = function(n, n2, ...)
        local target = type(n) == "table" and n2 or n
        if not card.AllowStep(target) then return end
        return orig(n, n2, ...)
    end
    addon.SetStep = card.guardedSetStep
end

local function ManualSetStep(n)
    card.manual = true
    local ok, err = pcall(addon.SetStep, n)
    card.manual = false
    if not ok then error(err, 0) end
end
card.ManualSetStep = ManualSetStep

-- Go to any step and stay there
function card.JumpTo(index)
    local guide = addon.currentGuide
    if not (guide and guide.steps and index) then return end
    -- a background (#sticky) step can't be the current one; land on the next real step
    while guide.steps[index] and (guide.steps[index].sticky or guide.steps[index].hidewindow) and index < #guide.steps do
        index = index + 1
    end
    local step = guide.steps[index]
    if not step then return end
    local from = CurrentStep()
    local status = card.StepStatus(guide, index, from)
    step.completed = nil
    if OXPCData and OXPCData.stepSkip then OXPCData.stepSkip[index] = nil end
    card.hold = {guide = guide.name, index = index, t = Now(), from = math.max(from, (card.hold and card.hold.from) or 0),
                 done = status ~= nil}
    if card.histOffset then card.histOffset = 0 end
    ManualSetStep(index)
    if card.FillStepList then card.FillStepList() end
    card.Refresh(true)
    return CurrentStep() == index
end

-- Back one step: the nearest earlier step that can be shown
function card.GoBack()
    local guide = addon.currentGuide
    if not (guide and guide.steps) then return end
    local from = CurrentStep()
    local level = UnitLevel and UnitLevel("player") or 60
    for target = from - 1, math.max(1, from - 60), -1 do
        local step = guide.steps[target]
        if step and not step.sticky and not step.hidewindow and (step.level or 0) <= level then
            return card.JumpTo(target)
        end
    end
end

-- Next: move on. A step you never finished is remembered as skipped.
function card.GoNext()
    local guide = addon.currentGuide
    if not guide then return end
    local cur = CurrentStep()
    local status = card.StepStatus(guide, cur, cur)
    if status ~= "done" and status ~= "chain" then card.MarkStatus(guide, cur, "skipped") end
    card.hold = nil
    ManualSetStep(cur + 1)
    card.Refresh(true)
end

-- Back to the furthest step you'd reached before looking back
function card.Resume()
    local hold = card.hold
    card.hold = nil
    if hold and hold.from and hold.from > CurrentStep() then
        ManualSetStep(hold.from)
    end
    card.Refresh(true)
end

bar.prev = MakeButton(bar, "prev", L("Back one step"), function() card.GoBack() end)
bar.prev:SetPoint("LEFT", 6, 0)
bar.next = MakeButton(bar, "next", L("Next step (an unfinished step is marked Skipped)"), function() card.GoNext() end)
bar.next:SetPoint("LEFT", bar.prev, "RIGHT", 2, 0)
bar.find = MakeButton(bar, "target", L("Jump to the right guide and step for your level, zone and quests"),
                      function()
                          card.hold = nil
                          if addon.smartStart then addon.smartStart.Run() end
                      end, L("Find my place"))
bar.find:SetPoint("LEFT", bar.next, "RIGHT", 6, 0)
bar.stop = MakeButton(bar, "prev", L("Stop the quest chain and go back to the guide"),
                      function() card.StopDetour() end, L("Back to guide"))
bar.stop:SetPoint("LEFT", bar.next, "RIGHT", 6, 0)
bar.stop:Hide()
bar.resume = MakeButton(bar, "next", L("Go back to the step you were on"), function() card.Resume() end, L("Back to step"))
bar.resume:SetPoint("LEFT", bar.next, "RIGHT", 6, 0)
bar.resume:Hide()
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

local function HistRow(i)
    local row = hist.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, hist)
    row:SetHeight(HIST_ROW_H)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0)
    row.num = row:CreateFontString(nil, "OVERLAY")
    row.num:SetPoint("LEFT", PAD - 2, 0)
    row.num:SetWidth(26)
    row.num:SetJustifyH("RIGHT")
    row.pill = MakePill(row)
    row.pill:SetPoint("RIGHT", -PAD + 2, 0)
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetPoint("LEFT", row.num, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", row.pill, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        self.hl:SetColorTexture(1, 1, 1, 0.07)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(fmt(L("Step %d"), self.index or 0), 1, 1, 1)
        if self.full then GameTooltip:AddLine(self.full, 0.85, 0.85, 0.85, true) end
        local st = self.status and STATUS[self.status]
        if st then GameTooltip:AddLine(L(st.tip), st.color[1], st.color[2], st.color[3], true) end
        GameTooltip:AddLine(L("Click to go back to this step"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self) if self.index then card.JumpTo(self.index) end end)
    hist.rows[i] = row
    return row
end

-- Steps before the current one that the card can show
function card.PreviousSteps(guide, current)
    local out = {}
    for i = 1, math.min((current or 1) - 1, guide and guide.steps and #guide.steps or 0) do
        local step = guide.steps[i]
        if step and not step.hidewindow and not step.sticky then tinsert(out, i) end
    end
    return out
end

function card.ScrollHistory(delta)
    local guide = addon.currentGuide
    if not guide or card.detour then return end
    local prev = card.PreviousSteps(guide, CurrentStep())
    card.histOffset = math.max(0, math.min(#prev, (card.histOffset or 0) + (delta > 0 and 1 or -1) * (IsShiftKeyDown and IsShiftKeyDown() and HIST_ROWS or 1)))
    card.Refresh(true)
end

-- Lays out the history rows; returns their height (0 when hidden)
function card.LayoutHistory(guide, current)
    local offset = card.histOffset or 0
    if offset <= 0 or card.detour then hist:Hide(); return 0 end
    local prev = card.PreviousSteps(guide, current)
    offset = math.min(offset, #prev)
    card.histOffset = offset
    if offset == 0 then hist:Hide(); return 0 end
    local first = #prev - offset + 1
    local last = math.min(#prev, first + HIST_ROWS - 1)
    SetFont(hist.label, -2)
    SetFont(hist.hint, -2)
    hist.label:SetText(L("EARLIER STEPS"))
    hist.hint:SetText(Width() >= 280 and L("scroll down to return") or "")
    local y = 26
    local n = 0
    for k = first, last do
        n = n + 1
        local index = prev[k]
        local step = guide.steps[index]
        local row = HistRow(n)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", hist, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", hist, "TOPRIGHT", 0, -y)
        local title = StepContent(step)
        local text = StripCodes(title or "")
        text = (text:gsub("\n.*", ""))
        row.index, row.full = index, text
        row.status = card.StepStatus(guide, index, current)
        SetFont(row.num, -2)
        SetFont(row.text, -1)
        row.num:SetText(index)
        row.num:SetTextColor(unpack(C.faint))
        row.text:SetText(text)
        local dim = row.status == "done" or row.status == "skipped"
        row.text:SetTextColor(unpack(dim and C.dim or C.text))
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
f:SetScript("OnMouseWheel", function(_, delta) card.ScrollHistory(delta) end)

-- A cheap fingerprint of everything the card draws. Refresh only lays the
-- card out again when it changes (or every few seconds as a safety net),
-- so an idle card costs a string build four times a second.
card.questLogTick = 0
function card.Signature()
    local guide = addon.currentGuide
    local p = Profile() or {}
    local parts = {
        guide and guide.name or "", CurrentStep() or 0, card.questLogTick,
        card.width or 0, card.height or 0, p.windowScale or 1, p.guideFontSize or 0,
        p.openxpCardCollapsed and 1 or 0, p.lockFrames and 1 or 0,
        card.detour and (card.detour.index or 0) or -1, card.sizing and 1 or 0,
        card.histOffset or 0, card.hold and card.hold.index or 0,
        card.here and card.here.index or 0,
    }
    local travel = addon.travel and addon.travel.Lines and addon.travel.Lines()
    tinsert(parts, travel and table.concat(travel, "|") or "")
    local active = addon.RXPFrame and addon.RXPFrame.activeSteps or {}
    for _, step in ipairs(active) do
        tinsert(parts, step.index or 0)
        tinsert(parts, step.completed and 1 or 0)
        for _, e in ipairs(step.elements or {}) do
            tinsert(parts, e.text or "")
            tinsert(parts, (e.completed or e.skip) and 1 or 0)
        end
    end
    return table.concat(parts, "\031")
end

-- Called when the Font or Text outline setting changes
-- A font file the game hasn't drawn yet loads in the background: text set
-- right after the switch stays blank and measures 0 high until something
-- re-lays it out (resizing the card did). So set every text again once
-- the font is in, then lay the card out again.
local function Relayout()
    for fs in pairs(fontStrings) do
        local ok, text = pcall(fs.GetText, fs)
        if ok and text and text ~= "" then
            pcall(fs.SetText, fs, "")
            pcall(fs.SetText, fs, text)
        end
    end
    card.Refresh(true)
end

function card.ApplyFonts()
    for fs, spec in pairs(fixedText) do
        ApplyFont(fs, Font(), spec[1], Flags(spec[2]))
    end
    if card.SkinPanels then pcall(card.SkinPanels) end
    card.Refresh(true)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, Relayout)
        C_Timer.After(0.6, Relayout)
    end
end

function card.Refresh(force)
    if not Visible() then
        f:Hide()
        card.lastSig = nil
        return
    end
    f:Show()
    local now = GetTime and GetTime() or 0
    local sig = card.Signature()
    if not force and sig == card.lastSig and now - (card.lastFull or 0) < 3 then
        return
    end
    card.lastSig, card.lastFull = sig, now
    if card.FillStepList then pcall(card.FillStepList) end
    if card.UpdateXP then pcall(card.UpdateXP) end

    local guide = addon.currentGuide
    local p = Profile()
    local scale = (p and p.windowScale) or 1
    if f:GetScale() ~= scale then f:SetScale(scale) end
    if not card.sizing and f:GetWidth() ~= Width() then f:SetWidth(Width()) end
    grip:SetShown(not (p and p.lockFrames))
    local total = guide.steps and #guide.steps or 0
    local current = math.min(CurrentStep() or 1, math.max(total, 1))
    local active = addon.RXPFrame and addon.RXPFrame.activeSteps or {}

    -- The step you're on goes first. Steps that stay open in the background
    -- (#sticky / #completewith, like "loot this book while you're here") go
    -- under it, labelled, so they never look like the current step.
    local steps, side = {}, {}
    local lastIndex = current
    for _, step in ipairs(active) do
        if step and not step.hidewindow and not step.tip then
            if card.StepRole(step, current) == "now" then
                tinsert(steps, step)
            else
                tinsert(side, step)
            end
            if not step.sticky and step.index and step.index > lastIndex then lastIndex = step.index end
        end
    end
    for _, step in ipairs(side) do tinsert(steps, step) end
    while #steps > MAX_BLOCKS do table.remove(steps) end

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
        header:Hide(); progressBg:Hide(); progress:Hide(); body:Hide(); upNext:Hide(); bar:Hide(); hist:Hide()
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
    -- a narrow card gets slimmer icon buttons so all six still fit
    local slim = Width() < 300
    local bw = Width() < 250 and 26 or slim and 30 or 40
    for _, btn in ipairs({bar.prev, bar.next, bar.menu, bar.settings, bar.collapse}) do
        btn:SetWidth(bw)
    end
    bar.collapse:ClearAllPoints()
    bar.collapse:SetPoint("RIGHT", slim and -18 or -20, 0)
    for _, btn in ipairs({bar.find, bar.stop, bar.resume}) do
        btn:SetWidth(wide and 116 or bw)
        btn.label:SetShown(wide)
        btn.icon:ClearAllPoints()
        if wide then btn.icon:SetPoint("LEFT", 10, 0) else btn.icon:SetPoint("CENTER") end
    end
    local hold = card.hold
    local looking = not detourStep and hold and hold.from and hold.from > current
    if looking then bar.resume.label:SetText(fmt(L("Back to %d"), hold.from)) end
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
    header.range:SetShown(Width() >= 300) -- no room for the level range on a narrow card
    header.step:SetText(fmt(L("Step %d / %d"), current, total))
    if detourStep then
        header.zone:SetText(L("QUEST CHAIN"))
        header.range:SetText("")
        header.step:SetText(fmt(L("%d / %d"), detourIndex, #card.detour.ids))
    end
    local frac = total > 0 and current / total or 0
    if detourStep then frac = detourIndex / math.max(#card.detour.ids, 1) end
    progress:SetWidth(math.max(1, (Width() - 2) * frac))

    local histH = card.LayoutHistory(guide, current)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", histH > 0 and hist or progressBg, "BOTTOMLEFT", 0, 0)
    body:SetPoint("TOPRIGHT", histH > 0 and hist or progressBg, "BOTTOMRIGHT", 0, 0)

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
    local baseHeight = 1 + 28 + 2 + histH + y + 4 + 34 + 38 + 1
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
        local content = 1 + 28 + 2 + histH + y + 4 + upHeight + 38 + 1
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
    card.TimedTick()
end)
-- Remember where you are in each guide on this character, including steps
-- you skipped forward to, and put you back there after a reload or relog
function card.RememberStep()
    local guide = addon.currentGuide
    if not (card.restored and guide and guide.name and OXPCData) then return end
    local cur = addon.GetGuideProgress and addon.GetGuideProgress()
    if not cur then return end
    if card.here and card.here.guide == guide.name then cur = card.here.from end
    OXPCData.openxpSteps = OXPCData.openxpSteps or {}
    OXPCData.openxpSteps[guide.name] = cur
end

function card.RestoreStep()
    card.restored = true
    local guide = addon.currentGuide
    local saved = guide and guide.name and OXPCData and OXPCData.openxpSteps and OXPCData.openxpSteps[guide.name]
    local cur = addon.GetGuideProgress and addon.GetGuideProgress()
    if saved and cur and saved > cur and guide.steps and saved <= #guide.steps then
        addon.SetStep(saved)
    end
end

function Tick()
    if card.enabled then
        card.RememberStep()
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
            local cur = addon.GetGuideProgress and addon.GetGuideProgress()
            if addon.currentGuide ~= r.guide then
                card.returnTo = nil
            elseif r.chain then
                -- back from the start of a chain: once the quest you came
                -- from can be done, unless the guide got you there already
                if cur and cur >= r.step then
                    card.returnTo = nil
                elseif not card.QuestBlocked(r.quest) and (not r.needAccept or
                        (addon.IsOnQuest and addon.IsOnQuest(r.quest)) or TurnedIn(r.quest)) then
                    card.returnTo = nil
                    card.hold = nil
                    card.ManualSetStep(r.step)
                end
            elseif addon.IsOnQuest and addon.IsOnQuest(r.quest) then
                card.returnTo = nil
                card.hold = nil
                card.ManualSetStep(r.step)
            end
        end
        pcall(card.CheckTrainerSteps)
        pcall(card.CheckTravelSteps)
        pcall(card.CheckHereSteps)
        local ok, err = pcall(card.Refresh)
        if not ok then card.ReportError(err) end
        card.SkinPanels()
        card.ParkClassicWindow()
    end
end
card.TickForTest = Tick
card.TimedTick = (addon.perf and addon.perf.Wrap or function(_, f) return f end)("card update", function() return Tick() end)

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
    ApplyFont(af.oxpDist, Font(), 17, Flags("OUTLINE"))
    af.oxpDist:SetPoint("TOP", af.dialBg, "BOTTOM", 0, -6)
    af.oxpLabel = af:CreateFontString(nil, "OVERLAY")
    ApplyFont(af.oxpLabel, Font(), 12, Flags("OUTLINE"))
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
    local font, flags = Font(), Flags("OUTLINE")
    if af.oxpScale == scale and af.oxpText == textSize and af.oxpFont == font
        and af.oxpFlags == flags then return end
    af.oxpScale, af.oxpText, af.oxpFont, af.oxpFlags = scale, textSize, font, flags
    af.dialBg:SetSize(76 * scale, 76 * scale)
    af.dialRing:SetSize(76 * scale, 76 * scale)
    af.arrived:SetSize(36 * scale, 36 * scale)
    af.texture:SetSize(44 * scale, 44 * scale)
    af:SetHitRectInsets(-22 * scale, -22 * scale, -22 * scale, -22 * scale)
    ApplyFont(af.oxpDist, font, textSize + 5, flags)
    ApplyFont(af.oxpLabel, font, textSize, flags)
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
    -- a stepping stone from PathHints.lua (cave entrance, ramp) when there is one
    local element = af.oxpVia or af.element
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

card.TimedArrow = (addon.perf and addon.perf.Wrap or function(_, f) return f end)("arrow", ArrowUpdate)

function card.SetupArrow()
    local af = addon.arrowFrame
    if not af then return end
    StyleArrow()
    ArrowVisuals(af)
    af:SetScript("OnUpdate", card.TimedArrow)
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
    card.GuardSetStep()
    pcall(card.RestoreStep)
    card.Refresh(true)
    -- Once per character: point out that Questie adds chains and levels
    C_Timer.After(20, function()
        if _G.QuestieLoader or not OXPCData or OXPCData.openxpQuestieHint then return end
        OXPCData.openxpQuestieHint = true
        print("|cFF66BB6AOpenXP:|r " .. L("Tip: install the free Questie addon and OpenXP will show quest chains, quest levels and \"Do the chain\" on steps you're missing. Everything else works without it."))
    end)
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

---------------------------------------------------------------------------
-- Step list: every step of the guide, click one to jump there
---------------------------------------------------------------------------

local LIST_ROWS = 18
local list

local function StepSummary(step)
    for _, e in ipairs(step.elements or {}) do
        local text = e.text
        if text and text ~= "" and text ~= " " then
            if addon.ReplaceNpcIds then text = addon.ReplaceNpcIds(L(text), e and e.step and e or nil) end
            return (StripCodes(text):gsub("\n.*", ""))
        end
    end
    return step.title or ""
end

local function VisibleSteps()
    local out = {}
    local guide = addon.currentGuide
    for i, step in ipairs(guide and guide.steps or {}) do
        if not step.hidewindow then tinsert(out, i) end
    end
    return out
end

function card.BuildStepList()
    if list then return list end
    list = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    list:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                      insets = {left = 1, right = 1, top = 1, bottom = 1}})
    list:SetBackdropColor(unpack(C.bg))
    list:SetBackdropBorderColor(unpack(C.border))
    list:SetFrameStrata("DIALOG")
    list:SetWidth(340)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list.offset = 0
    list.title = list:CreateFontString(nil, "OVERLAY")
    list.title:SetPoint("TOPLEFT", PAD, -9)
    list.title:SetTextColor(unpack(C.dim))
    list.close = MakeButton(list, "cross", L("Close"), function() list:Hide() end)
    list.close:SetPoint("TOPRIGHT", -4, -4)
    list.rows = {}
    for r = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", 4, -28 - (r - 1) * 18)
        row:SetPoint("TOPRIGHT", -4, -28 - (r - 1) * 18)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0)
        row.num = row:CreateFontString(nil, "OVERLAY")
        row.num:SetPoint("LEFT", 6, 0)
        row.num:SetWidth(30)
        row.num:SetJustifyH("RIGHT")
        row.pill = MakePill(row)
        row.pill:SetPoint("RIGHT", -6, 0)
        row.text = row:CreateFontString(nil, "OVERLAY")
        row.text:SetPoint("LEFT", row.num, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row.pill, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.hl:SetColorTexture(1, 1, 1, 0.08) end)
        row:SetScript("OnLeave", function(self)
            self.hl:SetColorTexture(1, 1, 1, self.current and 0.05 or 0)
        end)
        row:SetScript("OnClick", function(self) card.JumpTo(self.index) end)
        list.rows[r] = row
    end
    list:SetHeight(28 + LIST_ROWS * 18 + 8)
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, math.min((self.count or 0) - LIST_ROWS, self.offset - delta * 3))
        card.FillStepList()
    end)
    list:Hide()
    return list
end

function card.FillStepList()
    if not (list and list:IsShown()) then return end
    local guide = addon.currentGuide
    local steps = VisibleSteps()
    list.count = #steps
    list.title:SetText((StripCodes((guide and (guide.displayname or guide.name)) or ""):gsub("\n", " ")))
    SetFont(list.title, -1)
    -- rows grow with the font size so big text doesn't overlap
    local rowH = math.max(18, FontSize(-1) + 6)
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
    local cur = CurrentStep()
    for r, row in ipairs(list.rows) do
        local i = steps[list.offset + r]
        local step = i and guide.steps[i]
        if step then
            row.index = i
            row.current = i == cur
            SetFont(row.num, -1)
            SetFont(row.text, -1)
            row.num:SetText(i)
            row.text:SetText(StepSummary(step))
            local status = not row.current and card.StepStatus(guide, i, cur) or nil
            row.pill:SetStatus(status)
            local done = status == "done" or status == "skipped"
            local color = row.current and C.blue or done and C.faint or C.text
            row.text:SetTextColor(unpack(color))
            row.num:SetTextColor(unpack(row.current and C.blue or C.dim))
            row.hl:SetColorTexture(1, 1, 1, row.current and 0.05 or 0)
            row:Show()
        else
            row:Hide()
        end
    end
end

function card.ToggleStepList()
    card.BuildStepList()
    if list:IsShown() then list:Hide(); return end
    list:ClearAllPoints()
    local left = f:GetLeft() or 0
    if left > 320 then
        list:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
    else
        list:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
    end
    list:Show()
    -- open with the current step near the top
    local steps, cur = VisibleSteps(), CurrentStep()
    list.offset = 0
    for n, i in ipairs(steps) do
        if i >= cur then list.offset = math.max(0, math.min(#steps - LIST_ROWS, n - 4)); break end
    end
    card.FillStepList()
end

-- Timer bars (flight timers, step timers) live in the classic window's
-- footer, which is parked off screen. Dock them under the card instead.
function card.DockTimers()
    local bc = addon.RXPFrame and addon.RXPFrame.BarContainer
    if not bc then return end
    local n = 0
    for _ in pairs(bc.bars or {}) do n = n + 1 end
    if bc:GetParent() ~= f then bc:SetParent(f) end
    bc:ClearAllPoints()
    bc:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
    bc:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
    bc:SetHeight((bc.height or 16) * math.max(n, 1))
end
if addon.SortTimers then
    local origSortTimers = addon.SortTimers
    addon.SortTimers = function(...)
        origSortTimers(...)
        if card.enabled then pcall(card.DockTimers) end
    end
end

-- The engine redraws its arrow on theme reloads; keep ours on top
if addon.SetupArrow then
    local origSetupArrow = addon.SetupArrow
    addon.SetupArrow = function(...)
        origSetupArrow(...)
        if card.enabled then card.SetupArrow() end
    end
end

---------------------------------------------------------------------------
-- Trainer steps: done once you've talked to the trainer at this level,
-- even if that was before the step came up. Training everything isn't
-- required; in Classic you rarely can or want to.
---------------------------------------------------------------------------

local function TrainerVisits()
    if not OXPCData then return {} end
    OXPCData.openxpTrainers = OXPCData.openxpTrainers or {}
    return OXPCData.openxpTrainers
end

function card.RecordTrainerVisit()
    local level = UnitLevel and UnitLevel("player") or 0
    local visits = TrainerVisits()
    local id = addon.GetNpcId and (addon.GetNpcId("npc") or addon.GetNpcId())
    local name = UnitName and (UnitName("npc") or UnitName("target"))
    if id then visits[id] = level end
    if name then visits[name:lower()] = level end
end

local function StepTrainerNames(step, e)
    local out = {}
    if e.id then tinsert(out, e.id) end
    for _, x in ipairs(step.elements or {}) do
        for _, n in ipairs(x.targets or {}) do tinsert(out, tonumber(n) or tostring(n):lower()) end
    end
    return out
end

function card.CheckTrainerSteps()
    local active = addon.RXPFrame and addon.RXPFrame.activeSteps
    if not active or not addon.SetElementComplete then return end
    local level = UnitLevel and UnitLevel("player") or 0
    local visits = TrainerVisits()
    for _, step in ipairs(active) do
        for _, e in ipairs(step.elements or {}) do
            if e.tag == "trainer" and not e.completed then
                for _, key in ipairs(StepTrainerNames(step, e)) do
                    if (visits[key] or -1) >= level then
                        addon.SetElementComplete(e)
                        break
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- "Go here" steps you've already gone past. A step that is only a
-- waypoint (no quest, item or NPC on it) used to wait until you stood
-- within its radius, even if you'd already run past it towards the next
-- stop, so the arrow sent you back. It now counts as done once you're
-- clearly closer to the next step's waypoint than this waypoint is.
---------------------------------------------------------------------------

local PAST_MIN, PAST_SHARE, PAST_MIN_LEG = 20, 0.15, 40

local function Dist(instance, ax, ay, bx, by)
    if HBD and HBD.GetWorldDistance then
        return HBD:GetWorldDistance(instance, ax, ay, bx, by)
    end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- The waypoint of a travel-only step, or nil
function card.TravelWaypoint(step)
    if not step or step.sticky or step.hidewindow then return end
    local wp
    for _, e in ipairs(step.elements or {}) do
        if e.tag == "goto" then
            if e.wx and e.wy and (e.radius or 0) > 0 and not e.completed and not wp then wp = e end
        elseif e.tag and not e.textOnly then
            return -- has something to do besides travel
        end
    end
    return wp
end

local function NextWaypoint(guide, from)
    for i = from + 1, math.min(#guide.steps, from + 6) do
        local s = guide.steps[i]
        if s and not s.sticky and not s.hidewindow then
            for _, e in ipairs(s.elements or {}) do
                if e.tag == "goto" and e.wx and e.wy then return e end
            end
        end
    end
end

-- px, py, pinst: player world position (passed in by tests)
function card.CheckTravelSteps(px, py, pinst)
    local guide = addon.currentGuide
    if not (guide and guide.steps) or card.hold or card.detour then return end
    local cur = CurrentStep()
    local wp = card.TravelWaypoint(guide.steps[cur])
    if not wp then return end
    local nxt = NextWaypoint(guide, cur)
    if not nxt or nxt.instance ~= wp.instance then return end
    if not px then
        if not (HBD and HBD.GetPlayerWorldPosition) then return end
        px, py, pinst = HBD:GetPlayerWorldPosition()
    end
    if not px or pinst ~= wp.instance then return end
    local leg = Dist(wp.instance, wp.wx, wp.wy, nxt.wx, nxt.wy)
    if not leg or leg < PAST_MIN_LEG then return end
    local toNext = Dist(wp.instance, px, py, nxt.wx, nxt.wy)
    if toNext and toNext < leg - math.max(PAST_MIN, leg * PAST_SHARE) then
        wp.skip = true
        if addon.SetElementComplete then addon.SetElementComplete(wp) end
        return true
    end
end

---------------------------------------------------------------------------
-- Here first: a later step you're standing next to
---------------------------------------------------------------------------
-- The guide sends you across the zone for the next step while a later
-- turn-in is right where you stand (you finished its quest early). Do that
-- one first, then go back to the step you were on: the guide skips it
-- later because it's done.

local HERE_RADIUS = 40   -- yards: that close to a later turn-in
local HERE_FAR = 120     -- yards: and the step you're on is at least this far
local HERE_AWAY = 90     -- yards: walked off from it, back to the guide
local HERE_AHEAD = 40    -- steps ahead to look

local function StepSpot(step)
    for _, e in ipairs(step and step.elements or {}) do
        if e.tag == "goto" and e.wx and e.wy then return e end
    end
end

-- A step that's only turning in quests that are finished (and picking up
-- what the same person hands out next)
function card.ReadyHere(step)
    if not step or step.sticky or step.hidewindow or step.completed or step.active then return false end
    local ready = false
    for _, e in ipairs(step.elements or {}) do
        local id = tonumber(e.questId)
        if e.tag == "turnin" then
            if id and id > 0 and not TurnedIn(id) then
                if addon.IsOnQuest and addon.IsOnQuest(id) and addon.IsQuestComplete and addon.IsQuestComplete(id) then
                    ready = true
                else
                    return false
                end
            end
        elseif e.tag and e.tag ~= "accept" and e.tag ~= "goto" and e.tag ~= "target" and not e.textOnly then
            return false
        end
    end
    return ready
end

local function HereDone(step)
    for _, e in ipairs(step and step.elements or {}) do
        local id = tonumber(e.questId)
        if e.tag == "turnin" and id and id > 0 and not TurnedIn(id) then return false end
    end
    return true
end

function card.CheckHereSteps(px, py, pinst)
    local guide = addon.currentGuide
    if not (guide and guide.steps) then card.here = nil return end
    if not px then
        if not (HBD and HBD.GetPlayerWorldPosition) then return end
        px, py, pinst = HBD:GetPlayerWorldPosition()
    end
    local cur = CurrentStep()
    local h = card.here
    if h then
        if guide.name ~= h.guide or cur ~= h.index then
            card.here = nil -- you moved on by hand
            return
        end
        local step = guide.steps[h.index]
        local spot = StepSpot(step)
        local away = spot and px and (pinst ~= spot.instance or
                                      (Dist(pinst, px, py, spot.wx, spot.wy) or 0) > HERE_AWAY)
        if HereDone(step) or away then
            card.here = nil
            ManualSetStep(h.from)
            card.Refresh(true)
            return true
        end
        return
    end
    if card.hold or card.detour or card.returnTo or not px then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local spot = StepSpot(guide.steps[cur])
    if not spot then return end
    if spot.instance == pinst and (Dist(pinst, px, py, spot.wx, spot.wy) or 0) < HERE_FAR then return end
    local level = UnitLevel and UnitLevel("player") or 60
    for i = cur + 1, math.min(#guide.steps, cur + HERE_AHEAD) do
        local s = guide.steps[i]
        if s and (s.level or 0) <= level and card.ReadyHere(s) then
            local sp = StepSpot(s)
            if sp and sp.instance == pinst and (Dist(pinst, px, py, sp.wx, sp.wy) or math.huge) <= HERE_RADIUS then
                card.here = {guide = guide.name, from = cur, index = i}
                ManualSetStep(i)
                if CurrentStep() ~= i then
                    card.here = nil
                    return
                end
                card.Refresh(true)
                return true
            end
        end
    end
end

local trainerWatch = CreateFrame("Frame")
for _, ev in ipairs({"TRAINER_SHOW", "GOSSIP_SHOW"}) do pcall(trainerWatch.RegisterEvent, trainerWatch, ev) end
trainerWatch:SetScript("OnEvent", function(_, ev)
    -- gossip counts only for NPCs that a trainer step names
    pcall(card.RecordTrainerVisit)
    pcall(card.CheckTrainerSteps)
end)

-- Anything quest or level related bumps the counter, so the card redraws
local watcher = CreateFrame("Frame")
for _, ev in ipairs({"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
                     "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED"}) do
    pcall(watcher.RegisterEvent, watcher, ev)
end
watcher:SetScript("OnEvent", function()
    card.questLogTick = (card.questLogTick or 0) + 1
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(2, function() card.Enable() end)
    -- a bundled font can still be loading at login; paint everything again
    -- once it's surely in, so button labels don't keep the fallback
    C_Timer.After(6, function()
        if card.enabled and card.ApplyFonts then pcall(card.ApplyFonts) end
    end)
end)

---------------------------------------------------------------------------
-- The engine's other panels (Active Targets, quest items, level splits)
-- get the card's look: dark body, 1px border, a slim title tab
---------------------------------------------------------------------------

local PANELS = {"RXPItemFrame", "RXPLevelSplits"} -- the target list styles itself (Targeting.lua)
local PANEL_BACKDROP = {bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                        insets = {left = 1, right = 1, top = 1, bottom = 1}}

local function Skinned(frame)
    local bd = frame.GetBackdrop and frame:GetBackdrop()
    return bd and bd.edgeFile == WHITE and bd.edgeSize == 1
end

function card.SkinPanel(frame)
    if not (frame and frame.SetBackdrop) then return end
    if not Skinned(frame) then
        frame:SetBackdrop(PANEL_BACKDROP)
        frame:SetBackdropColor(unpack(C.bg))
        frame:SetBackdropBorderColor(unpack(C.border))
    end
    local title = frame.title
    if title and title.SetBackdrop and not Skinned(title) then
        title:SetBackdrop(PANEL_BACKDROP)
        title:SetBackdropColor(0.10, 0.11, 0.14, 0.95)
        title:SetBackdropBorderColor(unpack(C.border))
    end
    local text = title and title.text
    if text and text.GetFont then
        local font = text:GetFont()
        if font ~= Font() then
            ApplyFont(text, Font(), 11, "")
            text:SetTextColor(unpack(C.dim))
            local raw = text:GetText()
            if raw then text:SetText(raw:upper()) end
            if title.SetSize and text.GetStringWidth then
                title:SetSize((text:GetStringWidth() or 60) + 16, 18)
            end
        end
    end
    -- level splits text
    for _, key in ipairs({"history", "current", "total"}) do
        local fs = frame[key]
        if fs and fs.GetFont then
            local font, size = fs:GetFont()
            if font ~= Font() then ApplyFont(fs, Font(), size or 12, "") end
        end
    end
end

function card.SkinPanels()
    for _, name in ipairs(PANELS) do
        local frame = _G[name]
        if frame then pcall(card.SkinPanel, frame) end
    end
end

---------------------------------------------------------------------------
-- /oxp step: print what the card knows about the steps on screen
---------------------------------------------------------------------------

function card.DebugStep()
    local out = {}
    local function say(...) tinsert(out, table.concat({...}, " ")) end
    local guide = addon.currentGuide
    say("OpenXP", tostring(addon.openxpVersion), "guide:", guide and tostring(guide.name) or "none",
        "step:", tostring(addon.GetGuideProgress and addon.GetGuideProgress()))
    say("QuestieLoader:", tostring(_G.QuestieLoader ~= nil), "QuestieDB:", tostring(Questie() ~= nil),
        "ZoneDB:", tostring(zoneDB ~= nil))
    local probe = QGet("Quest", 945)
    say("Questie GetQuest(945):", probe and tostring(probe.name) or "nil", "style:", tostring(card.questieStyle))
    say("last card error:", tostring(card.lastError))
    say("auto skip off:", tostring(addon.settings and addon.settings.profile.disableAutoSkip), "isHidden:", tostring(addon.isHidden))
    local log = addon.QuestLogIDs and addon.QuestLogIDs()
    if log then
        local list = {}
        for id, title in pairs(log) do tinsert(list, id .. "=" .. tostring(title)) end
        table.sort(list)
        say("quest log:", table.concat(list, ", "))
    else
        say("quest log: unreadable (expand all headers in the quest log)")
    end
    say("saved step for this guide:", tostring(guide and OXPCData and OXPCData.openxpSteps and OXPCData.openxpSteps[guide.name]))
    say("chain walk:", card.detour and ("on, target " .. tostring(card.detour.target)) or "off")
    local active = addon.RXPFrame and addon.RXPFrame.activeSteps or {}
    for _, step in ipairs(active) do
        say("-- step", tostring(step.index), step.sticky and "(sticky)" or "", step.hidewindow and "(hidden)" or "")
        for _, e in ipairs(step.elements or {}) do
            local id = tonumber(e.questId)
            if e.tag and e.tag ~= "goto" and e.tag ~= "target" then
                local line = "   " .. e.tag .. (id and (" q" .. id) or "")
                if id then
                    local qid = math.abs(id)
                    local log = addon.QuestLogIDs and addon.QuestLogIDs()
                    line = line .. " api=" .. tostring(C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(qid) or false) ..
                               " questLog=" .. (log and tostring(log[qid] ~= nil) or "unreadable") ..
                               " inLog=" .. tostring(addon.IsOnQuest and addon.IsOnQuest(qid) or false) ..
                               " done=" .. tostring(addon.IsQuestTurnedIn and addon.IsQuestTurnedIn(qid) or false) ..
                               " blockedBy=" .. tostring((card.QuestBlocked(qid)))
                    local pre = card.Prereqs(qid)
                    if pre then
                        line = line .. " pre=" .. table.concat(pre.any or pre.all or {}, ",")
                    end
                end
                line = line .. (e.completed and " completed" or "") .. (e.skipIfMissing and " skipIfMissing" or "")
                say(line)
            end
        end
        local pr = card.StepProblem(step)
        say("   problem:", pr and (pr.kind .. " q" .. tostring(pr.quest) ..
                                       (pr.chain and (" chain=" .. table.concat(pr.chain, ",")) or "")) or "none")
    end
    local text = table.concat(out, "\n")
    print(text)
    return text
end

-- timed by /oxp perf, so a slow part of the card update shows by name
do
    local Wrap = addon.perf and addon.perf.Wrap
    if Wrap then
        card.Refresh = Wrap("card redraw", card.Refresh)
        card.CheckHereSteps = Wrap("card: steps you're standing by", card.CheckHereSteps)
        card.CheckTravelSteps = Wrap("card: travel steps", card.CheckTravelSteps)
        card.CheckTrainerSteps = Wrap("card: trainer steps", card.CheckTrainerSteps)
    end
end
