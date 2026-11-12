-- Pins on the world map and minimap, so the map alone says what to do and
-- where:
--   steps   the step you're on and the next few, numbered like the card
--           (#11), as "!" where you pick a quest up and "?" where you hand
--           one in; the current one bigger
--   mobs    a mark on every spawn of what the shown steps still need
--           (skull: kill it; bag: it drops what you need; a big skull and
--           its name for a mob with only a spawn or two, like Gobbler)
--   areas   a label on each blue kill/loot area
-- Every pin has a tooltip. Pins are rebuilt only when the step or its
-- progress changes, from a reused pool.
local ADDON, OXP = ...

local Pins = {}
OXP.Pins = Pins

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local Engine, Places = OXP.Engine, OXP.Places
local L = OXP.L
local floor, min = math.floor, math.min

local CIRCLE = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Card\\filledcircle"
local ACCEPT = "Interface\\GossipFrame\\AvailableQuestIcon"
local TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local BIG_SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local BAG = "Interface\\GossipFrame\\VendorGossipIcon"
local COLORS = {
    kill = { 0.93, 0.36, 0.33 }, loot = { 0.95, 0.76, 0.36 }, travel = { 0.35, 0.72, 1 },
    town = { 0.35, 0.72, 1 }, accept = { 1, 0.82, 0 }, turnin = { 1, 0.82, 0 },
}
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
        else
            GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:Show()
end

local function OnLeave() GameTooltip:Hide() end

local function NewPin()
    local p = CreateFrame("Frame", nil, UIParent)
    p.tex = p:CreateTexture(nil, "OVERLAY")
    p.tex:SetAllPoints()
    p.num = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.num:SetPoint("CENTER", 0, 0)
    p.label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.label:SetPoint("TOP", p, "BOTTOM", 0, -1)
    p:EnableMouse(true)
    p:SetScript("OnEnter", OnEnter)
    p:SetScript("OnLeave", OnLeave)
    p.mini = CreateFrame("Frame", nil, UIParent)
    p.mini.tex = p.mini:CreateTexture(nil, "OVERLAY")
    p.mini.tex:SetAllPoints()
    p.mini:EnableMouse(true)
    p.mini:SetScript("OnEnter", function(self) OnEnter(p) end)
    p.mini:SetScript("OnLeave", OnLeave)
    return p
end

--- A pin from the pool, set up: texture (or nil for a text label), size,
--- colour {r, g, b, a}, number text, label under it, tooltip lines.
local function Take(texture, size, color, num, label, tip)
    used = used + 1
    local p = pool[used]
    if not p then
        p = NewPin()
        pool[used] = p
    end
    p:SetSize(size, size)
    p.tex:SetTexture(texture)
    p.tex:SetShown(texture ~= nil)
    p.tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    p.num:SetText(num or "")
    p.label:SetText(label or "")
    p.mini:SetSize(size * 0.75, size * 0.75)
    p.mini.tex:SetTexture(texture)
    p.mini.tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    p.tip = tip
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

local function StepTip(step, pos)
    local tip = {}
    local Card = OXP.Card
    if Card and Card.StepContent then
        local title, lines = Card.StepContent(step)
        tip[1] = ("%s %d: %s"):format(L("Step"), pos, Strip(title))
        for _, line in ipairs(lines) do
            tip[#tip + 1] = (line.done and "|cFF3DBB7A" .. L("Done") .. ":|r " or "- ") .. Strip(line.text)
        end
    else
        tip[1] = ("%s %d: %s"):format(L("Step"), pos, OXP.Target.StepTitle(step) or "")
    end
    return tip
end

local function StepKind(step)
    local Card = OXP.Card
    return Card and Card.StepKind and Card.StepKind(step) or "travel"
end

local function AddSteps()
    local current = Engine.GetPosition()
    for i, e in ipairs(Pins.Steps()) do
        local pos, step = e[1], e[2]
        local spot = OXP.Areas.StepSpot(step)
        if spot then
            local kind = StepKind(step)
            local now = i == 1 or pos == current
            local tip = StepTip(step, pos)
            local p
            if kind == "accept" or kind == "turnin" then
                p = Take(kind == "accept" and ACCEPT or TURNIN, now and 22 or 17, { 1, 1, 1, now and 1 or 0.85 },
                    nil, "#" .. pos, tip)
            else
                local c = COLORS[kind] or COLORS.travel
                p = Take(CIRCLE, now and 22 or 17, { c[1], c[2], c[3], now and 1 or 0.8 }, tostring(pos), nil, tip)
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
            local p = Take(nil, 12, { 1, 1, 1 }, nil, "|cFF8EC8FF" .. what .. " (#" .. pos .. ")|r", tip)
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
                        local tip = { src.name or "?" }
                        if src.item then
                            tip[2] = ("%s %s"):format(src.kind == "NPC" and L("Drops") or L("Has"), src.item)
                        elseif okind == "kill" then
                            tip[2] = L("Kill it")
                        end
                        tip[#tip + 1] = ("%s - %s %d"):format(quest, L("step"), pos)
                        local p
                        if few then
                            p = Take(BIG_SKULL, 16, { 1, 1, 1 }, nil, src.name, tip)
                        elseif src.kind == "NPC" and not src.item then
                            p = Take(SKULL, 11, { 1, 0.55, 0.5, 0.9 }, nil, nil, tip)
                        else
                            p = Take(BAG, 11, { 1, 0.85, 0.45, 0.9 }, nil, nil, tip)
                        end
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
        out[#out + 1] = { tip = p.tip, num = p.num:GetText(), label = p.label:GetText(), size = p:GetWidth() }
    end
    return out
end

local function Soon() OXP.Soon("PINS", Pins.Refresh) end
for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "SETTINGS_CHANGED" }) do
    OXP.Listen(m, Soon)
end
