-- Pins on the world map and minimap, so the map alone says what to do and
-- where. They look and behave like Questie's, so a Questie player feels at
-- home (docs/questie-map-parity.md); the icons are OpenXP's own
-- (Media/Map, tools/make_icons.py and tools/make_objective_icons.py):
--   steps   the step you're on and the next one (Settings > Maps): a
--           yellow "!" where you pick a quest up (grey for a low level one)
--           and "?" where you hand one in (grey until it's ready), or a
--           numbered badge ringed in the step's colour (red kill, amber loot,
--           blue travel) for a step with no quest to take or hand in; the
--           current one with a faint slow pulse
--   mobs    every spawn of what the current step's open objectives still
--           need, thinned like Questie's (sword: kill it; sack: it drops
--           what you need; cog: an object to loot or use; bubble: talk),
--           each on a soft glow in its objective's own colour
--   areas   no label: an invisible spot on each current kill/loot area's
--           middle with its name in a tooltip
-- Sizes, draw order, the minimap's fading and edge icons, the grouped
-- tooltip and the clicks follow Questie (GPL-3, see NOTICE.md). Pins are
-- rebuilt only when the step or its progress changes, from a reused pool.
local ADDON, OXP = ...

local Pins = {}
OXP.Pins = Pins

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local Engine, Places = OXP.Engine, OXP.Places
local L = OXP.L
local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt

local MAP = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Map\\"
local ICON = {
    disc = MAP .. "step_disc", ring = MAP .. "step_ring", glow = MAP .. "step_glow",
    halo = MAP .. "objective_glow",
    accept = MAP .. "accept", turnin = MAP .. "turnin", turninGrey = MAP .. "turnin_grey",
    kill = MAP .. "kill", loot = MAP .. "loot", chest = MAP .. "chest", object = MAP .. "object",
    talk = MAP .. "talk", boss = MAP .. "boss",
    -- the quest icons players know: yellow "!" to pick up, grey for a low
    -- level quest, yellow "?" to hand in, grey while it isn't done
    available = MAP .. "quest_available", availableGrey = MAP .. "quest_available_grey",
    complete = MAP .. "quest_complete", incomplete = MAP .. "quest_incomplete",
}
-- objective marks: OpenXP's own silver icons (tools/make_objective_icons.py),
-- the same set as the card and nameplates
local WHITE = { 1, 1, 1 }
local OBJ = {
    slay = { MAP .. "kill", WHITE },
    loot = { MAP .. "loot", WHITE },
    object = { MAP .. "object", WHITE },
    talk = { MAP .. "talk", WHITE },
}
Pins.OBJ = OBJ
Pins.ICON = ICON
-- ring colours of the numbered step badges, by what the step is
local COLORS = {
    kill = { 1, 0.42, 0.38 }, loot = { 1, 0.78, 0.36 }, travel = { 0.42, 0.76, 1 },
    town = { 0.42, 0.76, 1 }, accept = { 1, 0.82, 0.2 }, turnin = { 1, 0.82, 0.2 },
}
local HEX = { kill = "FFFF7A6E", loot = "FFFFC861", travel = "FF6CC2FF", town = "FF6CC2FF",
              accept = "FFFFD23A", turnin = "FFFFD23A", grey = "FF9EA3AD", green = "FF3DBB7A" }
local STEPS_AHEAD = 6
local MAX_MOBS = 400      -- objective pins at most (the nearest first)

-- Questie's sizes (Modules/Options/QuestieOptionsDefaults.lua, QuestieMap.lua):
-- 16 px x the icon type's scale (1.2 for ! and ?, 1 for objectives) x the
-- global scale (0.6 on the world map, 0.7 on the minimap); our Settings >
-- Maps sizes multiply that.
local SIZE = {
    base = 16, quest = 1.2, objective = 1, map = 0.6, minimap = 0.7,
    badge = 18, badgeNext = 15, -- OpenXP's numbered step badges (no Questie twin)
}
-- smaller on continent and world maps (Questie's QuestieMap.GetScaleValue);
-- by Enum.UIMapType: 0 cosmic, 1 world, 2 continent
local MAP_TYPE_SCALE = { [0] = 0.85, [1] = 0.85, [2] = 0.9 }
-- Questie's draw order (QuestieMapUtils.lua): objectives under the ! of
-- available quests, those under turn-ins
local LEVEL = { area = 2016, objective = 2020, available = 2021, step = 2022, complete = 2024 }
-- Questie's objective filter: a spawn is drawn only this far (map units of
-- 0-100, x counted 1.5 times) from every one already drawn for the objective
local FILTER = 2
-- the glow behind objective icons, a little bigger than the icon
local HALO = 1.13
-- the minimap's fading (Questie's fadeLevel / fadeOverPlayer): distances in
-- tens of yards; past `level` an icon fades out over `over`, closer than
-- `near` it fades down to `nearAlpha` under the player arrow
local FADE = { level = 20, over = 10, near = 5, nearAlpha = 0.5, every = 0.1 }
-- the current step's pulse: small, faint and slow
local GLOW = { size = 1.4, alpha = 0.5, from = 0.15, to = 0.5, secs = 1.4 }
-- tooltip grouping radius in map units (0-100), by the map shown
-- (Questie's MapIconTooltip): zone 1, continent 4, world 6; on the minimap
-- 0.5 outdoors (0.3 indoors) divided by 1 + its zoom
local GROUP = { zone = 1, continent = 4, world = 6, outdoor = 0.5, indoor = 0.3 }
-- the objective glow colours (our own pick of 16 clear hues), handed out
-- in turn to each objective, like Questie's colour wheel
local PALETTE = {
    { 1.00, 0.36, 0.36 }, { 0.36, 0.72, 1.00 }, { 0.55, 0.90, 0.35 }, { 1.00, 0.75, 0.25 },
    { 0.78, 0.45, 1.00 }, { 0.30, 0.90, 0.85 }, { 1.00, 0.50, 0.80 }, { 0.95, 0.95, 0.40 },
    { 0.45, 0.55, 1.00 }, { 1.00, 0.60, 0.35 }, { 0.40, 1.00, 0.60 }, { 0.90, 0.40, 0.60 },
    { 0.60, 0.85, 1.00 }, { 0.85, 0.70, 0.45 }, { 0.70, 1.00, 0.40 }, { 0.65, 0.60, 0.95 },
}

Pins.STEPS_AHEAD, Pins.MAX_MOBS, Pins.GLOW = STEPS_AHEAD, MAX_MOBS, GLOW
Pins.SIZE, Pins.LEVEL, Pins.FILTER, Pins.FADE, Pins.GROUP, Pins.HALO = SIZE, LEVEL, FILTER, FADE, GROUP, HALO
Pins.MAP_TYPE_SCALE, Pins.PALETTE = MAP_TYPE_SCALE, PALETTE

--- Questie's icon size: 16 x the type's scale x the global scale, then our
--- own size setting. `what`: "quest" or "objective"; `mini` for the minimap.
function Pins.IconSize(what, mini)
    local s = OXP.settings
    local user = mini and (s.minimapIconScale or 1) or (s.mapIconScale or 1)
    return SIZE.base * (SIZE[what] or 1) * (mini and SIZE.minimap or SIZE.map) * user
end

local function QuestieLoaded()
    return _G.QuestieLoader ~= nil or (IsAddOnLoaded and IsAddOnLoaded("Questie"))
        or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie")) or false
end

------------------------------------------------------------------------
-- The pool: one frame per pin, each with a twin for the minimap
------------------------------------------------------------------------

local pool, used = {}, 0
local tipOwner -- the pin frame the tooltip is showing for

-- colours handed to objectives as they first show, kept for the session
local colorOf, colorsUsed = {}, 0
local function ObjectiveColor(key)
    if not colorOf[key] then
        colorsUsed = colorsUsed + 1
        colorOf[key] = PALETTE[(colorsUsed - 1) % #PALETTE + 1]
    end
    return colorOf[key]
end
Pins.ObjectiveColor = ObjectiveColor

local function Owner(f) return f.owner or f end

local function ShowTip(self)
    local lines = Pins.TooltipLines(self)
    if #lines == 0 then return end
    tipOwner = self
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    for _, l in ipairs(lines) do
        local c = l.color or { 1, 1, 1 }
        if l.right then
            local rc = l.rightColor or { 1, 1, 1 }
            GameTooltip:AddDoubleLine(l.text, l.right, c[1], c[2], c[3], rc[1], rc[2], rc[3])
        else
            GameTooltip:AddLine(l.text, c[1], c[2], c[3], l.wrap == true)
        end
    end
    GameTooltip:Show()
end

local function OnEnter(self)
    -- a minimap icon faded out isn't there (Questie: no tooltip at alpha 0)
    if self.GetAlpha and self:GetAlpha() <= 0 then return end
    ShowTip(self)
end

local function OnLeave()
    tipOwner = nil
    GameTooltip:Hide()
end

-- Questie's clicks: on the world map a left-click opens the pin's own map;
-- on the minimap, or with a modifier, a left-click with the chat box open
-- puts the quest's link in it. Right-clicks fall through to the map (zoom
-- out), set up in PassThrough.
local function OnClick(self, button)
    local p = Owner(self)
    if button ~= "LeftButton" or not p.at then return end
    local mod = (IsModifierKeyDown and IsModifierKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown())
    local wm = _G.WorldMapFrame
    if not self.isMini and not mod and wm and wm:IsShown() then
        local map = p.at[1]
        if wm.GetMapID and wm:GetMapID() ~= map and wm.SetMapID then wm:SetMapID(map) end
        return
    end
    local q = p.quests and p.quests[1]
    if q and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() and ChatEdit_InsertLink then
        ChatEdit_InsertLink(Pins.QuestLink(q))
    end
end

-- Right-clicks go through the pin to the map; not allowed in combat, so
-- tried again on the pin's next use.
local function PassThrough(f)
    if f.passThrough or not f.SetPassThroughButtons then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if pcall(f.SetPassThroughButtons, f, "RightButton") then f.passThrough = true end
end

-- One pin's look: a pulse (the step you're on), a coloured glow (an
-- objective), a badge (disc and coloured ring with the step number on it)
-- or a single icon, and a small number tag on the icon's corner.
local function Build(f, mini)
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture(ICON.glow)
    f.glow:SetPoint("CENTER")
    f.halo = f:CreateTexture(nil, "BORDER")
    f.halo:SetTexture(ICON.halo)
    f.halo:SetPoint("CENTER")
    f.disc = f:CreateTexture(nil, "ARTWORK")
    f.disc:SetTexture(ICON.disc)
    f.disc:SetAllPoints()
    f.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.ring:SetTexture(ICON.ring)
    f.ring:SetAllPoints()
    f.tex = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.tex:SetAllPoints()
    f.num = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.num:SetPoint("CENTER", 0, 0)
    f.num:SetShadowColor(0, 0, 0, 1)
    f.num:SetShadowOffset(1, -1)
    if not mini then
        f.tag = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.tag:SetPoint("CENTER", f, "BOTTOMRIGHT", -1, 2)
        f.tag:SetShadowColor(0, 0, 0, 1)
        f.tag:SetShadowOffset(1, -1)
        f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.label:SetPoint("TOP", f, "BOTTOM", 0, -1)
        f.label:SetShadowColor(0, 0, 0, 1)
        f.label:SetShadowOffset(1, -1)
    end
    if f.CreateAnimationGroup then
        local ag = f.glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        if a.SetFromAlpha then a:SetFromAlpha(GLOW.from) a:SetToAlpha(GLOW.to) end
        if a.SetDuration then a:SetDuration(GLOW.secs) end
        if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
        f.pulse = ag
    end
    f:EnableMouse(true)
    f:SetScript("OnEnter", OnEnter)
    f:SetScript("OnLeave", OnLeave)
    f:SetScript("OnMouseUp", OnClick)
end

local function NewPin()
    local p = CreateFrame("Frame", nil, UIParent)
    Build(p)
    p.mini = CreateFrame("Frame", nil, UIParent)
    p.mini.owner, p.mini.isMini = p, true
    Build(p.mini, true)
    return p
end

local IconFile = OXP.Util.IconFile

local function Style(f, o, size)
    f:SetSize(size, size)
    -- the file nearest the size on screen (crisp, not shrunk from 128 px)
    f.disc:SetTexture(IconFile(ICON.disc, size, f))
    f.ring:SetTexture(IconFile(ICON.ring, size, f))
    f.glow:SetTexture(IconFile(ICON.glow, size * GLOW.size, f))
    local badge = o.ring ~= nil
    f.disc:SetShown(badge)
    f.ring:SetShown(badge)
    if badge then f.ring:SetVertexColor(o.ring[1], o.ring[2], o.ring[3], 1) end
    f.tex:SetShown(o.icon ~= nil)
    f.icon = o.icon
    if o.icon then
        f.tex:SetTexture(o.single and o.icon or IconFile(o.icon, size, f))
        local c = o.tint or WHITE
        f.tex:SetVertexColor(c[1], c[2], c[3], 1)
    end
    -- an objective's glow, in its colour
    f.halo:SetShown(o.halo ~= nil)
    f.haloColor = o.halo
    if o.halo then
        f.halo:SetTexture(IconFile(ICON.halo, size * HALO, f))
        f.halo:SetSize(size * HALO, size * HALO)
        f.halo:SetVertexColor(o.halo[1], o.halo[2], o.halo[3], 1)
    end
    local font, flags = OXP.Fonts.Path(), "OUTLINE"
    local n = o.num and tostring(o.num) or ""
    OXP.Fonts.Apply(f.num, font, max(7, floor(size * (#n >= 3 and 0.42 or 0.52))), flags)
    f.num:SetText(n)
    f.glow:SetSize(size * GLOW.size, size * GLOW.size)
    f.glow:SetShown(o.glow == true)
    if o.glow then
        local c = o.ring or { 1, 0.82, 0.2 }
        f.glow:SetVertexColor(c[1], c[2], c[3], GLOW.alpha)
        if f.pulse and not f.pulse:IsPlaying() then f.pulse:Play() end
    elseif f.pulse and f.pulse:IsPlaying() then
        f.pulse:Stop()
    end
    f:SetAlpha(o.alpha or 1)
    f:EnableMouse(true)
    PassThrough(f)
end

--- A pin from the pool, set up from `o`: { icon = texture, ring = {r, g, b}
--- (a numbered badge), num, tag (small number on the icon's corner), label
--- (under it), size, miniSize, glow, halo = {r, g, b}, alpha, level, kind,
--- entry (what its tooltip says, Pins.TooltipLines) }.
local function Take(o)
    used = used + 1
    local p = pool[used]
    if not p then
        p = NewPin()
        pool[used] = p
    end
    local size = o.size or Pins.IconSize("quest")
    Style(p, o, size)
    Style(p.mini, o, o.miniSize or size * 0.8)
    local font = OXP.Fonts.Path()
    OXP.Fonts.Apply(p.tag, font, 9, "OUTLINE")
    p.tag:SetText(o.tag and tostring(o.tag) or "")
    OXP.Fonts.Apply(p.label, font, 10, "OUTLINE")
    p.label:SetText(o.label or "")
    p.entry, p.quests = o.entry, o.quests
    p.kind, p.glowOn, p.count, p.at = o.kind, o.glow == true, o.count, nil
    p.baseAlpha, p.noFade, p.onMini, p.edge = o.alpha or 1, o.noFade == true, false, false
    p.level = o.level
    -- Questie's draw order: a fixed frame level, kept when HBD re-parents
    if o.level and p.SetFrameLevel then
        if p.SetFixedFrameLevel then p:SetFixedFrameLevel(false) end
        p:SetFrameLevel(o.level)
        if p.SetFixedFrameLevel then p:SetFixedFrameLevel(true) end
    end
    return p
end

-- On the world map (zone, continent and world maps like Questie's; zone
-- only with Settings > Maps > Icons on continent maps off) and, with
-- `minimap`, the minimap ("edge": floats on its rim when out of range).
local function Place(p, map, x, y, minimap, zoneOnly)
    local wx, wy, inst = Places.ToWorld(map, x, y)
    if not wx then return false end
    p.at, p.wx, p.wy, p.inst = { map, x, y }, wx, wy, inst
    local showOn = (zoneOnly or OXP.settings.mapContinentIcons == false) and 0 or 3
    HBDPins:AddWorldMapIconWorld(Pins, p, inst, wx, wy, showOn)
    if minimap and OXP.settings.mapMinimapIcons ~= false then
        p.onMini, p.edge = true, minimap == "edge"
        HBDPins:AddMinimapIconWorld(Pins, p.mini, inst, wx, wy, minimap == "edge")
    end
    return true
end

function Pins.Clear()
    HBDPins:RemoveAllWorldMapIcons(Pins)
    HBDPins:RemoveAllMinimapIcons(Pins)
    for i = 1, used do
        local p = pool[i]
        if p.pulse then p.pulse:Stop() end
        if p.mini.pulse then p.mini.pulse:Stop() end
        p.onMini = false
    end
    used = 0
end

------------------------------------------------------------------------
-- Size by map, and the minimap's fading
------------------------------------------------------------------------

--- How much smaller pins are on the map shown now: 0.9 on a continent,
--- 0.85 on the world map, 1 on a zone (Questie's).
function Pins.MapTypeScale()
    local wm = _G.WorldMapFrame
    local map = wm and wm.GetMapID and wm:GetMapID()
    local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.mapType and MAP_TYPE_SCALE[info.mapType] or 1
end

function Pins.Rescale()
    local s = Pins.MapTypeScale()
    for i = 1, used do pool[i]:SetScale(s) end
end

-- the world map changing maps refreshes HBD's pins: size ours for it
if HBDPins.worldmapProvider and HBDPins.worldmapProvider.RefreshAllData and hooksecurefunc then
    hooksecurefunc(HBDPins.worldmapProvider, "RefreshAllData", function() Pins.Rescale() end)
end

--- A minimap icon's opacity `yards` from you (Questie's fade): full near,
--- fading out from Settings > Maps > Minimap fade distance over 100 yards
--- more, and down to half right under you.
function Pins.MinimapAlpha(yards)
    local s = OXP.settings
    local d = yards / 10
    local level = s.minimapFadeLevel or FADE.level
    if d > level then
        return max(0, 1 - min(FADE.over, d - level) / FADE.over)
    elseif s.minimapFadeOverPlayer ~= false and d < FADE.near then
        return FADE.nearAlpha + d * (1 - FADE.nearAlpha) / FADE.near
    end
    return 1
end

--- Fade the minimap icons by how far they are (the current step's stays).
function Pins.UpdateFade()
    local px, py, pinst = Places.Player()
    for i = 1, used do
        local p = pool[i]
        if p.onMini then
            local a = 1
            if not p.noFade and px and p.wx then
                a = (pinst ~= nil and p.inst ~= nil and pinst ~= p.inst) and 0
                    or Pins.MinimapAlpha(Places.Distance(px, py, p.wx, p.wy))
            end
            a = a * (p.baseAlpha or 1)
            p.mini:SetAlpha(a)
            p.mini:EnableMouse(a > 0)
        end
    end
end

local fader = CreateFrame("Frame")
local fadeWait = 0
fader:SetScript("OnUpdate", function(_, elapsed)
    fadeWait = fadeWait - (elapsed or 0)
    if fadeWait > 0 or used == 0 then return end
    fadeWait = FADE.every
    Pins.UpdateFade()
end)

------------------------------------------------------------------------
-- What goes on the map
------------------------------------------------------------------------

local function Strip(s) return OXP.Text.Strip(s or "") end

--- The steps the map shows: the current one and the next few you'll really
--- do (the same ones the route line goes through). { {pos, step}, ... }
function Pins.Steps()
    local out = {}
    local steps = Engine.GetSteps()
    local first = Engine.GetPosition()
    if not first then return out end
    local willHave = {}
    for pos = first, #steps do
        if #out >= STEPS_AHEAD then break end
        local step = steps[pos]
        local state = Engine.StepState(pos)
        local missing = pos > first and OXP.QuestDB.MissingQuest(step)
        if state ~= "done" and state ~= "skipped" and state ~= "chain" and not (missing and not willHave[missing]) then
            out[#out + 1] = { pos, step }
            for _, g in ipairs(step.goals) do
                if g[1] == "accept" and g.quest then willHave[g.quest] = true end
            end
        end
    end
    return out
end

local WHAT = { accept = "Pick up", turnin = "Turn in", kill = "Kill", loot = "Collect", travel = "Go to", town = "In town" }

local function C(hex, text) return "|c" .. hex .. text .. "|r" end

local function StepTip(step, pos, kind)
    local tip = {}
    local Card = OXP.Card
    local head = C(HEX[kind] or HEX.travel, ("%s %d"):format(L("Step"), pos)) .. C(HEX.grey, "  " .. L(WHAT[kind] or "Go to"))
    if Card and Card.StepContent then
        local title, lines = Card.StepContent(step)
        tip[1] = Strip(title)
        tip[2] = head
        for _, line in ipairs(lines) do
            tip[#tip + 1] = line.done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " .. C(HEX.green, Strip(line.text)) or ("- " .. Strip(line.text))
        end
    else
        tip[1] = OXP.Target.StepTitle(step) or ""
        tip[2] = head
    end
    return tip
end

local function StepKind(step)
    local Card = OXP.Card
    return Card and Card.StepKind and Card.StepKind(step) or "travel"
end

--- True while OpenXP draws its own quest "!"/"?" and objective icons:
--- Settings > Maps > Quest icons ("auto": not while Questie draws its own).
function Pins.QuestIconsOn()
    local mode = OXP.settings.mapQuestIcons or "auto"
    if mode == "off" then return false end
    if mode == "on" then return true end
    return not QuestieLoaded()
end

--- The highest quest level that's grey (trivial) for a player of `level`.
function Pins.GreyLevel(level)
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    return level - 1 - math.floor(level / 5)
end

local function Difficulty(ql)
    local pl = OXP.Player.level or 1
    if not ql or ql <= 0 then return "FFFFD100" end
    local d = ql - pl
    if d >= 5 then return "FFFF1A1A" end
    if d >= 3 then return "FFFF8040" end
    if d >= -2 then return "FFFFFF00" end
    if ql > Pins.GreyLevel(pl) then return "FF40C040" end
    return "FF808080"
end
Pins.Difficulty = Difficulty

-- "[24] The Missing Diplomat", coloured by how hard it is for you
local function QuestHead(id)
    local info = OXP.QuestDB.Info(id) or {}
    local lvl = info.l and info.l > 0 and ("[" .. info.l .. "] ") or ""
    return C(Difficulty(info.l), lvl .. OXP.QuestDB.QuestName(id))
end
Pins.QuestHead = QuestHead

--- A quest's chat link (Classic's quest:id:level form).
function Pins.QuestLink(id)
    local info = OXP.QuestDB.Info(id) or {}
    return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, info.l or 0, OXP.QuestDB.QuestName(id))
end

-- What a step still asks for, right now (not what it asked for when the
-- guide was written): the quests to pick up that aren't in your log, the
-- quests to hand in, and whether those are done.
local function OpenGoals(step)
    local accepts, turnins = {}, {}
    for _, g in ipairs(step.goals) do
        if g.quest and OXP.Goals.State(g, step.marks) == "todo" then
            if g[1] == "accept" and not OXP.Quests.IsOnQuest(g.quest) and not OXP.Quests.IsTurnedIn(g.quest) then
                accepts[#accepts + 1] = g.quest
            elseif g[1] == "turnin" and not OXP.Quests.IsTurnedIn(g.quest) then
                turnins[#turnins + 1] = g.quest
            end
        end
    end
    return accepts, turnins
end
Pins.OpenGoals = OpenGoals

-- The quest icon for a step's open pick-ups and hand-ins, and what its
-- tooltip says: { giver = name, quests = { {id, tag}... } } (Questie's
-- "(Available)" / "(Complete)", and ours "(Not done yet)" for a hand-in
-- you're still working on).
local function QuestIcon(step, pos)
    local accepts, turnins = OpenGoals(step)
    if #turnins > 0 then
        local ready = 0
        local entry = { quests = {}, pos = pos }
        for _, q in ipairs(turnins) do
            local done = OXP.Quests.IsComplete(q)
            if done then ready = ready + 1 end
            entry.quests[#entry.quests + 1] = { id = q, tag = done and "complete" or "incomplete" }
        end
        local info = OXP.QuestDB.Info(turnins[1]) or {}
        entry.giver = info.f and info.f[1] or Strip(OXP.Target.StepTitle(step) or "")
        return ready > 0 and ICON.complete or ICON.incomplete, entry, turnins, ready > 0
    end
    if #accepts > 0 then
        local grey = true
        local pl = OXP.Player.level or 1
        local entry = { quests = {}, pos = pos }
        for _, q in ipairs(accepts) do
            local info = OXP.QuestDB.Info(q) or {}
            if not info.l or info.l <= 0 or info.l > Pins.GreyLevel(pl) then grey = false end
            entry.quests[#entry.quests + 1] = { id = q, tag = "available" }
        end
        local info = OXP.QuestDB.Info(accepts[1]) or {}
        entry.giver = info.s and info.s[1] or Strip(OXP.Target.StepTitle(step) or "")
        return grey and ICON.availableGrey or ICON.available, entry, accepts, false
    end
end
Pins.QuestIcon = QuestIcon

-- The step's kind from what it still asks for: a pickup step whose quests
-- are all in your log is now about its other goals.
local function LiveKind(step)
    local accepts, turnins = OpenGoals(step)
    if #accepts > 0 then return "accept" end
    if #turnins > 0 then return "turnin" end
    local open = { goals = {} }
    for _, g in ipairs(step.goals) do
        if not ((g[1] == "accept" or g[1] == "turnin") and g.quest) then open.goals[#open.goals + 1] = g end
    end
    return StepKind(open)
end
Pins.LiveKind = LiveKind

-- The step(s) you're on and, with Settings > Maps > Next step, the next one
-- with a spot: not every step ahead (their numbers piled up on the map).
local function AddSteps()
    local current = Engine.GetPosition()
    local quests = Pins.QuestIconsOn()
    local numbers = OXP.settings.mapStepNumbers ~= false
    local wantNext = OXP.settings.mapNextStep ~= false
    local active = {}
    for _, pos in ipairs(Engine.GetActive()) do active[pos] = true end
    local nextDone = false
    for i, e in ipairs(Pins.Steps()) do
        local pos, step = e[1], e[2]
        local spot = OXP.Areas.StepSpot(step)
        local now = i == 1 or pos == current or active[pos] == true
        if spot and (now or (wantNext and not nextDone)) then
            if not now then nextDone = true end
            -- only the step you're on pulses, and faintly
            local glow = now and (i == 1 or pos == current)
            local icon, entry, ids, complete
            if quests then icon, entry, ids, complete = QuestIcon(step, pos) end
            local p
            if icon then
                -- Questie's ! and ?: one size for every quest icon
                p = Take({ icon = icon, size = Pins.IconSize("quest"), miniSize = Pins.IconSize("quest", true),
                           glow = glow, alpha = 1, entry = entry, quests = ids, kind = "step",
                           level = complete and LEVEL.complete or LEVEL.available, noFade = glow })
            else
                local kind = LiveKind(step)
                local c = COLORS[kind] or COLORS.travel
                local size = (now and SIZE.badge or SIZE.badgeNext) * (OXP.settings.mapIconScale or 1)
                p = Take({ ring = c, num = numbers and pos or nil, size = size, glow = glow,
                           alpha = now and 1 or 0.85, entry = { lines = StepTip(step, pos, kind), pos = pos },
                           kind = "step", level = LEVEL.step, noFade = glow })
            end
            if not Place(p, spot.map, spot.x, spot.y, now and "edge" or true) then used = used - 1 end
        end
    end
end

-- The current step's areas (Nav/MapDraw.lua CurrentAreas: drawn once
-- each, none for the steps ahead) get no text on the map, only an invisible
-- spot on their middle that names them in a tooltip.
local AREA_SPOT = 18
local function AddAreas()
    local MapDraw = OXP.MapDraw
    if not (MapDraw and MapDraw.CurrentAreas) then return end
    for _, e in ipairs(MapDraw.CurrentAreas()) do
        local step = e.step
        local kind = StepKind(step)
        local what = kind == "loot" and L("Loot area") or L("Kill area")
        local nums = {}
        for _, n in ipairs(e.positions) do nums[#nums + 1] = tostring(n) end
        local tip = { ("%s - %s %s"):format(what, L("step"), table.concat(nums, ", ")),
                      OXP.Target.StepTitle(step) or "",
                      L("The blue area is where the mobs for this step are. Inside it the arrow says \"In the area\".") }
        local p = Take({ size = AREA_SPOT, entry = { lines = tip, area = true }, kind = "area", level = LEVEL.area })
        if not Place(p, e.area.map, e.cx, e.cy, nil, true) then used = used - 1 end
    end
end

-- The mob names a step's "mob" lines give for each open objective (from
-- OXP.Goals.NeededMobs: a finished objective's mobs are gone), lower case:
-- { [goal] = { [name] = true } }; `any` for mob lines with no objective.
local function NeededNames(step)
    local by = {}
    for _, m in ipairs(OXP.Goals.NeededMobs(step)) do
        local key = m.goal or "any"
        by[key] = by[key] or {}
        by[key][m.name:lower()] = true
    end
    return by
end

-- The spawns to mark for one open objective: NPCs the step's mob lines
-- don't name for it are left out (unless that leaves none).
local function GoalSpawns(g, names)
    local spawns = OXP.QuestDB.ObjectiveSpawnsAll(g.quest, g.obj) or {}
    local want = names[g] or names.any
    if not want then return spawns end
    local out = {}
    for _, s in ipairs(spawns) do
        local src = s[4]
        if src.kind ~= "NPC" or (src.name and want[src.name:lower()]) then out[#out + 1] = s end
    end
    return #out > 0 and out or spawns
end

--- Questie's distance between two map spots (0-100), x counted 1.5 times.
function Pins.MapDistance(ax, ay, bx, by)
    local dx, dy = (ax - bx) * 1.5, ay - by
    return sqrt(dx * dx + dy * dy)
end

-- Questie's objective filter: spawns from the middle of the zone outwards
-- (all on one map; otherwise the nearest to you first), each kept only
-- FILTER map units from every one already kept on its map.
local function Thin(spawns)
    local one, map = true, spawns[1] and spawns[1][1]
    for _, s in ipairs(spawns) do if s[1] ~= map then one = false break end end
    local px, py = Places.Player()
    local order = {}
    for i, s in ipairs(spawns) do
        local d
        if one or not px then
            d = Pins.MapDistance(s[2], s[3], 50, 50)
        else
            local wx, wy = Places.ToWorld(s[1], s[2], s[3])
            d = wx and Places.Distance(px, py, wx, wy) or math.huge
        end
        order[i] = { s = s, d = d, i = i }
    end
    table.sort(order, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.i < b.i
    end)
    local kept, byMap = {}, {}
    for _, e in ipairs(order) do
        local s = e.s
        local list = byMap[s[1]] or {}
        byMap[s[1]] = list
        local ok = true
        for _, k in ipairs(list) do
            if Pins.MapDistance(s[2], s[3], k[2], k[3]) < FILTER then ok = false break end
        end
        if ok then
            list[#list + 1] = s
            kept[#kept + 1] = s
        end
    end
    return kept
end

--- The objective pins for the step(s) you're on (Engine.GetActive(), not
--- the steps ahead), before they're placed: spawns of the still-open
--- objectives, thinned like Questie's, at most MAX_MOBS (the nearest).
--- { {map, x, y, wx, wy, inst, src, g, okind, pos, count}, ... }
function Pins.MobClusters()
    local out = {}
    local steps = Engine.GetSteps()
    local seenGoal, seenSpawn = {}, {}
    for _, pos in ipairs(Engine.GetActive()) do
        local step = steps[pos]
        local names = step and NeededNames(step) or {}
        for _, g in ipairs(step and step.goals or {}) do
            local gk = g.quest and g.obj and (g.quest .. ":" .. g.obj)
            if g[1] == "complete" and gk and not seenGoal[gk] and OXP.Goals.State(g, step.marks) == "todo" then
                seenGoal[gk] = true
                local _, okind = OXP.QuestDB.ObjectiveSources(g.quest, g.obj)
                for _, s in ipairs(Thin(GoalSpawns(g, names))) do
                    local map, x, y, src = s[1], s[2], s[3], s[4]
                    local key = gk .. ":" .. map .. ":" .. floor(x * 10) .. ":" .. floor(y * 10)
                    local wx, wy, inst = Places.ToWorld(map, x, y)
                    if wx and not seenSpawn[key] then
                        seenSpawn[key] = true
                        out[#out + 1] = { map = map, x = x, y = y, wx = wx, wy = wy, inst = inst, src = src, g = g,
                                          gk = gk, okind = okind, pos = pos, count = 1 }
                    end
                end
            end
        end
    end
    if #out > MAX_MOBS then
        local px, py = Places.Player()
        for _, c in ipairs(out) do c.d = px and Places.Distance(px, py, c.wx, c.wy) or 0 end
        table.sort(out, function(a, b) return a.d < b.d end)
        for i = #out, MAX_MOBS + 1, -1 do out[i] = nil end
    end
    return out
end

-- which icon an objective's spawn gets: a cog for an object, a sack for a
-- drop, a bubble to talk, a sword to kill
local function ObjIcon(src, okind)
    if src.kind == "Object" then return OBJ.object end
    if src.item then return OBJ.loot end
    if okind == "talk" then return OBJ.talk end
    return OBJ.slay
end
Pins.ObjIcon = ObjIcon

local function AddMobs()
    if OXP.settings.mapMobs == false or not Pins.QuestIconsOn() then return end
    local s = OXP.settings
    for _, c in ipairs(Pins.MobClusters()) do
        local obj = ObjIcon(c.src, c.okind)
        local color = ObjectiveColor(c.gk)
        local p = Take({
            icon = obj[1], tint = s.mapObjectiveColors == true and color or obj[2],
            halo = s.mapObjectiveGlow ~= false and color or nil,
            size = Pins.IconSize("objective"), miniSize = Pins.IconSize("objective", true),
            alpha = 1, kind = "mob", count = 1, level = LEVEL.objective, quests = { c.g.quest },
            entry = { quest = c.g.quest, obj = c.g.obj, npc = c.src.name, src = c.src, okind = c.okind, pos = c.pos },
        })
        if not Place(p, c.map, c.x, c.y, "edge") then used = used - 1 end
    end
end

function Pins.Refresh()
    Pins.Clear()
    if tipOwner then OnLeave() end
    if not Engine.GetGuide() then return end
    if OXP.settings.mapPins ~= false then AddSteps() end
    AddAreas() -- Settings > Maps > Kill and loot areas (MapDraw.CurrentAreas)
    AddMobs()
    Pins.Rescale()
    Pins.UpdateFade()
end
Pins.Refresh = OXP.Perf.Wrap("map pins", Pins.Refresh)

------------------------------------------------------------------------
-- Tooltips: every pin under the mouse in one, laid out like Questie's
------------------------------------------------------------------------

local GREEN, GREY, YELLOW, OBJ_TEXT = { 0.2, 1, 0.2 }, { 0.43, 0.43, 0.43 }, { 1, 1, 0 }, { 0.93, 0.93, 0.93 }
local TAGS = { available = "(Available)", complete = "(Complete)", incomplete = "(Not done yet)" }

-- How close (map units, 0-100) another pin must be to share the tooltip.
local function GroupRadius(f)
    if f.isMini then
        local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
        local base = (IsIndoors and IsIndoors()) and GROUP.indoor or GROUP.outdoor
        return base / (1 + zoom)
    end
    local wm = _G.WorldMapFrame
    local map = wm and wm.GetMapID and wm:GetMapID()
    local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    local t = info and info.mapType
    if t == 2 then return GROUP.continent end
    if t == 0 or t == 1 then return GROUP.world end
    return GROUP.zone
end

--- The pins sharing `f`'s tooltip: those on the same map within the
--- grouping radius (Questie's), shown ones only; `f`'s own first.
function Pins.Group(f)
    local p = Owner(f)
    local out = { p }
    if not p.at then return out end
    local r = GroupRadius(f)
    for i = 1, used do
        local o = pool[i]
        if o ~= p and o.at and o.at[1] == p.at[1] and o.entry
            and max(math.abs(o.at[2] - p.at[2]), math.abs(o.at[3] - p.at[3])) < r
            and (not f.isMini or (o.onMini and o.mini:GetAlpha() > 0)) then
            out[#out + 1] = o
        end
    end
    return out
end

local function Level(id)
    local info = OXP.QuestDB.Info(id) or {}
    return info.l or 0
end

local function ByLevel(a, b)
    local la, lb = Level(a), Level(b)
    if la ~= lb then return la < lb end
    return a < b
end

-- "3/10 Bluegill Murloc slain" (Questie's order), or the plain text
local function ObjectiveLine(q, o)
    local ob = OXP.Quests.GetObjective(q, o)
    if not ob then return nil end
    local text = Strip(ob.text or ""):gsub(":%s*%d+%s*/%s*%d+%s*$", "")
    if ob.need and ob.need > 0 then return ("%d/%d %s"):format(ob.have or 0, ob.need, text), ob.done end
    return text, ob.done
end

--- The tooltip of `f` and the pins near it, Questie's layout: the givers
--- (green name, "(Hold Shift)", then their quests by level, each tagged
--- "(Available)" or "(Complete)"); then the quests whose objectives are
--- here, each objective as "have/need text" (with Shift, who to find for
--- it); then OpenXP's step badges and areas. With Shift, the guide step.
--- `alone`: only `f`'s own lines. { {text, color, right, rightColor}, ... }
function Pins.TooltipLines(f, shift, alone)
    if shift == nil then shift = IsShiftKeyDown and IsShiftKeyDown() or false end
    local lines = {}
    local function Add(text, color, right, rightColor, wrap)
        lines[#lines + 1] = { text = text, color = color, right = right, rightColor = rightColor, wrap = wrap }
    end
    local givers, giverNames, objectives, questOrder, others = {}, {}, {}, {}, {}
    for _, p in ipairs(alone and { Owner(f) } or Pins.Group(f)) do
        local e = p.entry
        if e and e.giver then
            if not givers[e.giver] then
                givers[e.giver] = {}
                giverNames[#giverNames + 1] = e.giver
            end
            for _, q in ipairs(e.quests) do
                givers[e.giver][q.id] = givers[e.giver][q.id] or { tag = q.tag, pos = e.pos }
            end
        elseif e and e.quest then
            local by = objectives[e.quest]
            if not by then
                by = { objs = {}, order = {}, pos = e.pos }
                objectives[e.quest] = by
                questOrder[#questOrder + 1] = e.quest
            end
            if not by.objs[e.obj] then
                by.objs[e.obj] = { npcs = {}, names = {} }
                by.order[#by.order + 1] = e.obj
            end
            local o = by.objs[e.obj]
            if e.npc and not o.names[e.npc] then
                o.names[e.npc] = true
                o.npcs[#o.npcs + 1] = e.npc
            end
        elseif e and e.lines then
            others[#others + 1] = e
        end
    end
    table.sort(giverNames)
    for i, name in ipairs(giverNames) do
        if i == 1 and not shift then
            Add(name, GREEN, "(" .. L("Hold Shift") .. ")", GREY)
        else
            if shift and i > 1 then Add(" ") end
            Add(name, GREEN)
        end
        local ids = {}
        for id in pairs(givers[name]) do ids[#ids + 1] = id end
        table.sort(ids, ByLevel)
        for _, id in ipairs(ids) do
            local q = givers[name][id]
            Add("   " .. QuestHead(id), nil, L(TAGS[q.tag] or ""), q.tag == "incomplete" and GREY or YELLOW)
            local info = OXP.QuestDB.Info(id) or {}
            if q.tag == "available" and info.r and info.r > (OXP.Player.level or 1) then
                Add("      " .. (L("Needs level %d")):format(info.r), { 1, 0.38, 0.38 })
            end
            if q.tag == "incomplete" then
                for o = 1, 8 do
                    local text, done = ObjectiveLine(id, o)
                    if not text then break end
                    if not done then Add("      " .. text, OBJ_TEXT) end
                end
            end
            if shift and q.pos then Add("      " .. ("%s %d"):format(L("Step"), q.pos), GREY) end
        end
    end
    table.sort(questOrder, ByLevel)
    for _, q in ipairs(questOrder) do
        local by = objectives[q]
        if #giverNames > 0 then Add(" ") end
        local done = OXP.Quests.IsComplete(q)
        Add(QuestHead(q), nil, done and L("(Complete)") or (#giverNames > 0 and L("(Active)") or nil),
            done and GREEN or YELLOW)
        table.sort(by.order)
        for _, o in ipairs(by.order) do
            local text = ObjectiveLine(q, o) or OXP.QuestDB.QuestName(q)
            if shift then
                for _, npc in ipairs(by.objs[o].npcs) do Add("   " .. npc, { 1, 1, 1 }) end
                Add("      " .. text, OBJ_TEXT)
            else
                Add("   " .. text, OBJ_TEXT)
            end
        end
        if shift and by.pos then Add("   " .. ("%s %d"):format(L("Step"), by.pos), GREY) end
    end
    for _, e in ipairs(others) do
        if #lines > 0 then Add(" ") end
        for i, line in ipairs(e.lines) do
            if i == 1 then Add(line, { 1, 1, 1 }, nil, nil, true) else Add(line, { 0.8, 0.8, 0.8 }, nil, nil, true) end
        end
    end
    return lines
end

-- Shift pressed or let go over a pin: the tooltip shows more or less
OXP.On("MODIFIER_STATE_CHANGED", function()
    if tipOwner and GameTooltip:IsShown() then ShowTip(tipOwner) end
end)

------------------------------------------------------------------------
-- Blizzard's own quest markers (the round ? and ... on the world map)
------------------------------------------------------------------------

-- WoW Forever's client has Blizzard's quest objective markers (CVar
-- questPOI). Questie turns them off when it shows its own icons (its
-- "Questie" icon theme, NativeOptionsIcons.lua ExecuteTheme); so do we,
-- while our quest icons are on, and put them back as they were after.

--- True while Blizzard's quest markers should be hidden: Settings > Maps >
--- Hide Blizzard's quest markers, while our quest icons show. With Questie
--- loaded we leave it to Questie.
function Pins.HideBlizzardPOI()
    return OXP.settings.mapHideBlizzardPOI ~= false and Pins.QuestIconsOn() and not QuestieLoaded()
end

function Pins.SyncQuestPOI()
    if not (GetCVar and SetCVar) or QuestieLoaded() then return end
    local cur = GetCVar("questPOI")
    if cur == nil then return end -- a client without Blizzard's markers
    local char = OXP.char
    if not char then return end
    if Pins.HideBlizzardPOI() then
        if cur ~= "0" then
            char.questPOIRestore = cur
            SetCVar("questPOI", "0")
            local box = _G.WorldMapQuestShowObjectives
            if box and box.SetChecked then box:SetChecked(false) end
        end
    elseif char.questPOIRestore then
        if cur == "0" then SetCVar("questPOI", char.questPOIRestore) end
        char.questPOIRestore = nil
    end
end

OXP.OnReady(Pins.SyncQuestPOI)
-- like Questie: with the markers off, the client opens the world map at
-- log in; close it again (once)
local loginMapChecked = false
OXP.On("PLAYER_ENTERING_WORLD", function()
    if loginMapChecked then return end
    loginMapChecked = true
    local wm = _G.WorldMapFrame
    if OXP.char and OXP.char.questPOIRestore and GetCVar and GetCVar("questPOI") == "0"
        and wm and wm:IsShown() and HideUIPanel then
        HideUIPanel(wm)
        if UISpecialFrames then table.insert(UISpecialFrames, "WorldMapFrame") end
    end
end)

------------------------------------------------------------------------

--- Pins in use now (for tests and /oxp step): { {tip=..., num=..., label=...}, ... }
function Pins.Used()
    local out = {}
    for i = 1, used do
        local p = pool[i]
        local tip = {}
        for _, l in ipairs(Pins.TooltipLines(p, false, true)) do tip[#tip + 1] = l.text end
        out[#out + 1] = { tip = tip, num = p.num:GetText(), tag = p.tag:GetText(), label = p.label:GetText(),
                          size = p:GetWidth(), miniSize = p.mini:GetWidth(), icon = p.icon, kind = p.kind,
                          glow = p.glowOn, count = p.count, at = p.at, level = p.level, halo = p.haloColor,
                          onMini = p.onMini, edge = p.edge, miniAlpha = p.mini:GetAlpha(), frame = p,
                          entry = p.entry }
    end
    return out
end

local function Soon() OXP.Soon("PINS", Pins.Refresh) end
local function Settings()
    Soon()
    Pins.SyncQuestPOI()
end
-- QUESTS_CHANGED: accepting, finishing or handing in a quest changes its
-- icon at once ("!" gone, objectives shown, "?" turning yellow), even while
-- the step itself stays put
for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "QUESTS_CHANGED" }) do
    OXP.Listen(m, Soon)
end
OXP.Listen("SETTINGS_CHANGED", Settings)
