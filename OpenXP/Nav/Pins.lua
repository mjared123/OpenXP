-- Pins on the world map and minimap, so the map alone says what to do and
-- where (icons in Media/Map, drawn by tools/make_icons.py):
--   steps   the step you're on and the next few: a numbered badge ringed in
--           the step's colour (red kill, amber loot, blue travel), a gold "!"
--           where you pick a quest up and "?" where you hand one in (grey
--           until it's ready), each with its step number; the current one
--           bigger, with a soft pulsing glow
--   mobs    a mark on every spawn of what the shown steps still need (skull:
--           kill it; pouch: it drops what you need; chest or sparkle: an
--           object to loot or use; a big boss badge and its name for a mob
--           with only a spawn or two, like Gobbler)
--   areas   a label on each blue kill/loot area
-- Every pin has a tooltip (what, the step, your progress). Pins are rebuilt
-- only when the step or its progress changes, from a reused pool.
local ADDON, OXP = ...

local Pins = {}
OXP.Pins = Pins

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local Engine, Places = OXP.Engine, OXP.Places
local L = OXP.L
local floor, min = math.floor, math.min

local MAP = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Map\\"
local ICON = {
    disc = MAP .. "step_disc", ring = MAP .. "step_ring", glow = MAP .. "step_glow",
    accept = MAP .. "accept", turnin = MAP .. "turnin", turninGrey = MAP .. "turnin_grey",
    kill = MAP .. "kill", loot = MAP .. "loot", chest = MAP .. "chest", object = MAP .. "object",
    talk = MAP .. "talk", boss = MAP .. "boss",
}
Pins.ICON = ICON
-- ring colours of the numbered step badges, by what the step is
local COLORS = {
    kill = { 1, 0.42, 0.38 }, loot = { 1, 0.78, 0.36 }, travel = { 0.42, 0.76, 1 },
    town = { 0.42, 0.76, 1 }, accept = { 1, 0.82, 0.2 }, turnin = { 1, 0.82, 0.2 },
}
local HEX = { kill = "FFFF7A6E", loot = "FFFFC861", travel = "FF6CC2FF", town = "FF6CC2FF",
              accept = "FFFFD23A", turnin = "FFFFD23A", grey = "FF9EA3AD", green = "FF3DBB7A" }
local STEPS_AHEAD = 6
local MAX_MOBS = 160
local FEW = 3 -- a mob with this many spawns or fewer gets its own big pin

Pins.STEPS_AHEAD, Pins.MAX_MOBS = STEPS_AHEAD, MAX_MOBS

------------------------------------------------------------------------
-- The pool: one frame per pin, each with a twin for the minimap
------------------------------------------------------------------------

local pool, used = {}, 0

local function OnEnter(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for i, line in ipairs(self.tip) do
        if i == 1 then
            GameTooltip:SetText(line, 1, 1, 1, 1, true)
        elseif type(line) == "table" then
            GameTooltip:AddDoubleLine(line[1], line[2], 0.85, 0.85, 0.85, 1, 1, 1)
        else
            GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:Show()
end

local function OnLeave() GameTooltip:Hide() end

-- One pin's look: a glow (the step you're on, pulsing), a badge (disc and
-- coloured ring with the step number on it) or a single icon, a small step
-- number tag on the icon's corner, and a label under it.
local function Build(f, mini)
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture(ICON.glow)
    f.glow:SetPoint("CENTER")
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
        if a.SetFromAlpha then a:SetFromAlpha(0.35) a:SetToAlpha(0.95) end
        if a.SetDuration then a:SetDuration(0.9) end
        if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
        f.pulse = ag
    end
end

local function NewPin()
    local p = CreateFrame("Frame", nil, UIParent)
    Build(p)
    p:EnableMouse(true)
    p:SetScript("OnEnter", OnEnter)
    p:SetScript("OnLeave", OnLeave)
    p.mini = CreateFrame("Frame", nil, UIParent)
    Build(p.mini, true)
    p.mini:EnableMouse(true)
    p.mini:SetScript("OnEnter", function() OnEnter(p) end)
    p.mini:SetScript("OnLeave", OnLeave)
    return p
end

local IconFile = OXP.Util.IconFile

local function Style(f, o, size)
    f:SetSize(size, size)
    -- the file nearest the size on screen (crisp, not shrunk from 128 px)
    f.disc:SetTexture(IconFile(ICON.disc, size, f))
    f.ring:SetTexture(IconFile(ICON.ring, size, f))
    f.glow:SetTexture(IconFile(ICON.glow, size * 1.9, f))
    local badge = o.ring ~= nil
    f.disc:SetShown(badge)
    f.ring:SetShown(badge)
    if badge then f.ring:SetVertexColor(o.ring[1], o.ring[2], o.ring[3], 1) end
    f.tex:SetShown(o.icon ~= nil)
    f.icon = o.icon
    if o.icon then
        f.tex:SetTexture(IconFile(o.icon, size, f))
        f.tex:SetVertexColor(1, 1, 1, o.alpha or 1)
    end
    local font, flags = OXP.Fonts.Path(), "OUTLINE"
    local n = o.num and tostring(o.num) or ""
    OXP.Fonts.Apply(f.num, font, math.max(7, floor(size * (#n >= 3 and 0.42 or 0.52))), flags)
    f.num:SetText(n)
    f.glow:SetSize(size * 1.9, size * 1.9)
    f.glow:SetShown(o.glow == true)
    if o.glow then
        local c = o.ring or { 1, 0.82, 0.2 }
        f.glow:SetVertexColor(c[1], c[2], c[3], 0.9)
        if f.pulse and not f.pulse:IsPlaying() then f.pulse:Play() end
    elseif f.pulse and f.pulse:IsPlaying() then
        f.pulse:Stop()
    end
    f:SetAlpha(o.alpha or 1)
end

--- A pin from the pool, set up from `o`: { icon = texture, ring = {r, g, b}
--- (a numbered badge), num, tag (small number on the icon's corner), label
--- (under it), size, glow, alpha, tip = {lines} }.
local function Take(o)
    used = used + 1
    local p = pool[used]
    if not p then
        p = NewPin()
        pool[used] = p
    end
    local size = o.size or 16
    Style(p, o, size)
    Style(p.mini, o, size * 0.8)
    local font = OXP.Fonts.Path()
    OXP.Fonts.Apply(p.tag, font, 9, "OUTLINE")
    p.tag:SetText(o.tag and tostring(o.tag) or "")
    OXP.Fonts.Apply(p.label, font, 10, "OUTLINE")
    p.label:SetText(o.label or "")
    p.tip = o.tip
    return p
end

local function Place(p, map, x, y, showOn, minimap)
    local wx, wy, inst = Places.ToWorld(map, x, y)
    if not wx then return false end
    HBDPins:AddWorldMapIconWorld(Pins, p, inst, wx, wy, showOn)
    if minimap then HBDPins:AddMinimapIconWorld(Pins, p.mini, inst, wx, wy, minimap == "edge") end
    return true
end

function Pins.Clear()
    HBDPins:RemoveAllWorldMapIcons(Pins)
    HBDPins:RemoveAllMinimapIcons(Pins)
    for i = 1, used do
        local p = pool[i]
        if p.pulse then p.pulse:Stop() end
        if p.mini.pulse then p.mini.pulse:Stop() end
    end
    used = 0
end

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

-- a turn-in step whose quests aren't all ready yet
local function NotReady(step)
    for _, g in ipairs(step.goals) do
        if g[1] == "turnin" and g.quest and not OXP.Quests.IsComplete(g.quest) then return true end
    end
    return false
end

local function AddSteps()
    local current = Engine.GetPosition()
    for i, e in ipairs(Pins.Steps()) do
        local pos, step = e[1], e[2]
        local spot = OXP.Areas.StepSpot(step)
        if spot then
            local kind = StepKind(step)
            local now = i == 1 or pos == current
            local tip = StepTip(step, pos, kind)
            local p
            if kind == "accept" or kind == "turnin" then
                local icon = kind == "accept" and ICON.accept or (NotReady(step) and ICON.turninGrey or ICON.turnin)
                p = Take({ icon = icon, size = now and 26 or 20, tag = pos, glow = now,
                           alpha = now and 1 or 0.92, tip = tip })
            else
                local c = COLORS[kind] or COLORS.travel
                p = Take({ ring = c, num = pos, size = now and 26 or 20, glow = now,
                           alpha = now and 1 or 0.92, tip = tip })
            end
            Place(p, spot.map, spot.x, spot.y, 3, now and "edge" or true) -- 3: zone and continent maps
        end
    end
end

local function AddAreas()
    for _, e in ipairs(Pins.Steps()) do
        local pos, step = e[1], e[2]
        local a = OXP.Areas.ForStep(step)
        if a and a.poly and #a.poly > 0 then
            local cx, cy = 0, 0
            for _, pt in ipairs(a.poly) do cx, cy = cx + pt[1], cy + pt[2] end
            cx, cy = cx / #a.poly, cy / #a.poly
            local kind = StepKind(step)
            local what = kind == "loot" and L("Loot area") or L("Kill area")
            local tip = { ("%s - %s %d"):format(what, L("step"), pos),
                          OXP.Target.StepTitle(step) or "",
                          L("The blue area is where the mobs for this step are. Inside it the arrow says \"In the area\".") }
            local p = Take({ size = 2, label = "|cFF8EC8FF" .. what .. " (#" .. pos .. ")|r", tip = tip })
            Place(p, a.map, cx, cy, 0)
        end
    end
end

local function AddMobs()
    if OXP.settings.mapMobs == false then return end
    local seen, count = {}, 0
    for _, pos in ipairs(Engine.GetActive()) do
        local step = Engine.GetSteps()[pos]
        for _, g in ipairs(step.goals) do
            if g[1] == "complete" and g.quest and g.obj and OXP.Goals.State(g, step.marks) == "todo" then
                local list, okind = OXP.QuestDB.ObjectiveSources(g.quest, g.obj)
                local spawns = OXP.QuestDB.ObjectiveSpawnsAll(g.quest, g.obj) or {}
                -- how many spawns each mob has: a mob with only one or two gets its own pin
                local per = {}
                for _, s in ipairs(spawns) do per[s[4]] = (per[s[4]] or 0) + 1 end
                local quest = OXP.QuestDB.QuestName(g.quest)
                for _, s in ipairs(spawns) do
                    if count >= MAX_MOBS then return end
                    local map, x, y, src = s[1], s[2], s[3], s[4]
                    local key = map .. ":" .. floor(x) .. ":" .. floor(y) .. ":" .. tostring(src.id)
                    if not seen[key] then
                        seen[key] = true
                        local few = (per[src] or 0) <= FEW and src.kind == "NPC"
                        local o = OXP.Quests.GetObjective(g.quest, g.obj)
                        local tip = { src.name or "?" }
                        local icon
                        if src.kind == "Object" then
                            icon = src.item and ICON.chest or ICON.object
                            tip[2] = src.item and C(HEX.loot, L("Has") .. " " .. src.item) or C(HEX.loot, L("Use it"))
                        elseif src.item then
                            icon = ICON.loot
                            tip[2] = C(HEX.loot, L("Drops") .. " " .. src.item)
                        elseif okind == "talk" then
                            icon = ICON.talk
                            tip[2] = C(HEX.travel, L("Talk to them"))
                        else
                            icon = ICON.kill
                            tip[2] = C(HEX.kill, L("Kill it"))
                        end
                        if few then icon = ICON.boss end
                        local line = quest
                        if o and o.need and o.need > 0 then line = { quest, (o.have or 0) .. "/" .. o.need } end
                        tip[3] = line
                        tip[4] = C(HEX.grey, ("%s %d"):format(L("Step"), pos))
                        local p = Take({ icon = icon, size = few and 20 or 13, label = few and src.name or nil,
                                         alpha = few and 1 or 0.95, tip = tip })
                        if Place(p, map, x, y, 0, few and true or nil) then
                            count = count + 1
                        else
                            used = used - 1
                        end
                    end
                end
            end
        end
    end
end

function Pins.Refresh()
    Pins.Clear()
    if not Engine.GetGuide() then return end
    if OXP.settings.mapPins ~= false then
        AddSteps()
        AddAreas()
    end
    AddMobs()
end
Pins.Refresh = OXP.Perf.Wrap("map pins", Pins.Refresh)

--- Pins in use now (for tests and /oxp step): { {tip=..., num=..., label=...}, ... }
function Pins.Used()
    local out = {}
    for i = 1, used do
        local p = pool[i]
        out[#out + 1] = { tip = p.tip, num = p.num:GetText(), tag = p.tag:GetText(), label = p.label:GetText(),
                          size = p:GetWidth(), icon = p.icon }
    end
    return out
end

local function Soon() OXP.Soon("PINS", Pins.Refresh) end
for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "SETTINGS_CHANGED" }) do
    OXP.Listen(m, Soon)
end
