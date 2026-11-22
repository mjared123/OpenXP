-- Pins on the world map and minimap, so the map alone says what to do and
-- where (icons in Media/Map, drawn by tools/make_icons.py):
--   steps   the step you're on (and the next one, Settings > Maps): a
--           numbered badge ringed in the step's colour (red kill, amber loot,
--           blue travel), a gold "!" where you pick a quest up and "?" where
--           you hand one in (grey until it's ready), with its step number
--           (Settings > Maps > Step numbers); the current one bigger, with a
--           faint slow pulse
--   mobs    what the current step's open objectives still need, spawns close
--           together merged into one small pin with a count (sword: kill
--           it; pouch: it drops what you need; cog: an object to loot or
--           use; a big boss badge and its name for a mob with only a spawn
--           or two, like Gobbler)
--   areas   no label: an invisible spot on each current kill/loot area's
--           middle with its name in a tooltip
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
    -- the quest icons players know: yellow "!" to pick up, grey for a low
    -- level quest, yellow "?" to hand in, grey while it isn't done
    available = MAP .. "quest_available", availableGrey = MAP .. "quest_available_grey",
    complete = MAP .. "quest_complete", incomplete = MAP .. "quest_incomplete",
}
-- objective marks (pfQuest's, MIT: Media/Map/pfQuest/README.md); one size,
-- tinted by what to do
local OBJ = {
    slay = { MAP .. "pfQuest\\slay_mono", { 1, 0.55, 0.50 } },
    loot = { MAP .. "pfQuest\\loot_mono", { 1, 0.84, 0.42 } },
    object = { MAP .. "pfQuest\\object_mono", { 0.52, 0.88, 1 } },
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
local MAX_MOBS = 40       -- mob pins at most (clusters, the nearest first)
local MOB_SIZE = 10
local MOB_CLUSTER = 45    -- yards: spawns this close to a pin join it
local FEW = 3 -- a mob with this many spawns or fewer gets its own big pin
-- the current step's pulse: small, faint and slow
local GLOW = { size = 1.4, alpha = 0.5, from = 0.15, to = 0.5, secs = 1.4 }

Pins.STEPS_AHEAD, Pins.MAX_MOBS, Pins.MOB_CLUSTER, Pins.GLOW = STEPS_AHEAD, MAX_MOBS, MOB_CLUSTER, GLOW

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
        if a.SetFromAlpha then a:SetFromAlpha(GLOW.from) a:SetToAlpha(GLOW.to) end
        if a.SetDuration then a:SetDuration(GLOW.secs) end
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
    f.glow:SetTexture(IconFile(ICON.glow, size * GLOW.size, f))
    local badge = o.ring ~= nil
    f.disc:SetShown(badge)
    f.ring:SetShown(badge)
    if badge then f.ring:SetVertexColor(o.ring[1], o.ring[2], o.ring[3], 1) end
    f.tex:SetShown(o.icon ~= nil)
    f.icon = o.icon
    if o.icon then
        f.tex:SetTexture(o.single and o.icon or IconFile(o.icon, size, f))
        local c = o.tint or { 1, 1, 1 }
        f.tex:SetVertexColor(c[1], c[2], c[3], o.alpha or 1)
    end
    local font, flags = OXP.Fonts.Path(), "OUTLINE"
    local n = o.num and tostring(o.num) or ""
    OXP.Fonts.Apply(f.num, font, math.max(7, floor(size * (#n >= 3 and 0.42 or 0.52))), flags)
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
    local size = (o.size or 16) * (OXP.settings.mapIconScale or 1)
    Style(p, o, size)
    Style(p.mini, o, size * 0.8)
    local font = OXP.Fonts.Path()
    OXP.Fonts.Apply(p.tag, font, 9, "OUTLINE")
    p.tag:SetText(o.tag and tostring(o.tag) or "")
    OXP.Fonts.Apply(p.label, font, 10, "OUTLINE")
    p.label:SetText(o.label or "")
    p.tip = o.tip
    p.kind, p.glowOn, p.count, p.at = o.kind, o.glow == true, o.count, nil
    return p
end

local function Place(p, map, x, y, showOn, minimap)
    local wx, wy, inst = Places.ToWorld(map, x, y)
    if not wx then return false end
    p.at = { map, x, y }
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

--- True while OpenXP draws its own quest "!"/"?" and objective icons:
--- Settings > Maps > Quest icons ("auto": not while Questie draws its own).
function Pins.QuestIconsOn()
    local mode = OXP.settings.mapQuestIcons or "auto"
    if mode == "off" then return false end
    if mode == "on" then return true end
    local questie = _G.QuestieLoader ~= nil or (IsAddOnLoaded and IsAddOnLoaded("Questie"))
        or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie"))
    return not questie
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

-- The quest icon for a step's open pick-ups and hand-ins, and its tooltip.
local function QuestIcon(step, pos, kind)
    local accepts, turnins = OpenGoals(step)
    if #turnins > 0 then
        local ready = 0
        for _, q in ipairs(turnins) do if OXP.Quests.IsComplete(q) then ready = ready + 1 end end
        local tip = {}
        for i, q in ipairs(turnins) do
            local done = OXP.Quests.IsComplete(q)
            tip[#tip + 1] = i == 1 and QuestHead(q) or QuestHead(q)
            tip[#tip + 1] = done and C(HEX.green, L("Ready to turn in")) or C(HEX.grey, L("Not done yet"))
            if not done then
                for o = 1, 8 do
                    local ob = OXP.Quests.GetObjective(q, o)
                    if not ob then break end
                    tip[#tip + 1] = { "  " .. Strip(ob.text or ""), ob.done and C(HEX.green, L("done")) or "" }
                end
            end
        end
        local info = OXP.QuestDB.Info(turnins[1]) or {}
        if info.f and info.f[1] then tip[#tip + 1] = C(HEX.grey, L("Turn in to") .. " " .. info.f[1]) end
        tip[#tip + 1] = C(HEX.grey, ("%s %d"):format(L("Step"), pos))
        return ready > 0 and ICON.complete or ICON.incomplete, tip
    end
    if #accepts > 0 then
        local grey = true
        local pl = OXP.Player.level or 1
        local tip = {}
        for _, q in ipairs(accepts) do
            local info = OXP.QuestDB.Info(q) or {}
            if not info.l or info.l <= 0 or info.l > Pins.GreyLevel(pl) then grey = false end
            tip[#tip + 1] = QuestHead(q)
            if info.r and info.r > pl then tip[#tip + 1] = C("FFFF6060", (L("Needs level %d")):format(info.r)) end
        end
        local info = OXP.QuestDB.Info(accepts[1]) or {}
        if info.s and info.s[1] then tip[#tip + 1] = C(HEX.grey, L("Started by") .. " " .. info.s[1]) end
        tip[#tip + 1] = C(HEX.grey, ("%s %d"):format(L("Step"), pos))
        return grey and ICON.availableGrey or ICON.available, tip
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
            local icon, qtip
            if quests then icon, qtip = QuestIcon(step, pos) end
            local p
            if icon then
                p = Take({ icon = icon, size = now and 22 or 17, tag = numbers and pos or nil, glow = glow,
                           alpha = now and 1 or 0.85, tip = qtip, kind = "step" })
            else
                local kind = LiveKind(step)
                local c = COLORS[kind] or COLORS.travel
                p = Take({ ring = c, num = numbers and pos or nil, size = now and 22 or 17, glow = glow,
                           alpha = now and 1 or 0.85, tip = StepTip(step, pos, kind), kind = "step" })
            end
            Place(p, spot.map, spot.x, spot.y, 3, now and "edge" or true) -- 3: zone and continent maps
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
        local p = Take({ size = AREA_SPOT, tip = tip, kind = "area" })
        if not Place(p, e.area.map, e.cx, e.cy, 0) then used = used - 1 end
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

-- A mob pin's tooltip like the quest addons': the quest, what to do, your
-- progress, and how many spawns the pin stands for.
local function MobTip(src, okind, g, pos, count)
    local o = OXP.Quests.GetObjective(g.quest, g.obj)
    local quest = OXP.QuestDB.QuestName(g.quest)
    local tip = { src.name or "?" }
    local obj
    if src.kind == "Object" then
        obj = OBJ.object
        tip[2] = src.item and C(HEX.loot, L("Has") .. " " .. src.item) or C(HEX.loot, L("Use it"))
    elseif src.item then
        obj = OBJ.loot
        tip[2] = C(HEX.loot, L("Drops") .. " " .. src.item)
    elseif okind == "talk" then
        obj = OBJ.object
        tip[2] = C(HEX.travel, L("Talk to them"))
    else
        obj = OBJ.slay
        tip[2] = C(HEX.kill, L("Kill it"))
    end
    tip[3] = QuestHead(g.quest)
    if o and o.need and o.need > 0 then
        tip[4] = { "  " .. Strip(o.text or quest):gsub(":%s*%d+%s*/%s*%d+%s*$", ""), (o.have or 0) .. "/" .. o.need }
    end
    if count > 1 then tip[#tip + 1] = C(HEX.grey, (L("%d spawns here")):format(count)) end
    tip[#tip + 1] = C(HEX.grey, ("%s %d"):format(L("Step"), pos))
    return tip, obj
end

--- The mob pins for the step(s) you're on (Engine.GetActive(), not the steps
--- ahead), before they're placed: spawns of the still-open objectives, those
--- close together merged into one, at most MAX_MOBS (named mobs, then the
--- nearest). { {map, x, y, wx, wy, src, g, okind, pos, count, few}, ... }
function Pins.MobClusters()
    local out = {}
    local steps = Engine.GetSteps()
    local seenGoal, seenSpawn, clusters = {}, {}, {}
    for _, pos in ipairs(Engine.GetActive()) do
        local step = steps[pos]
        local names = step and NeededNames(step) or {}
        for _, g in ipairs(step and step.goals or {}) do
            local gk = g.quest and g.obj and (g.quest .. ":" .. g.obj)
            if g[1] == "complete" and gk and not seenGoal[gk] and OXP.Goals.State(g, step.marks) == "todo" then
                seenGoal[gk] = true
                local _, okind = OXP.QuestDB.ObjectiveSources(g.quest, g.obj)
                local spawns = GoalSpawns(g, names)
                -- how many spawns each mob has: one with only a few gets its own pin
                local per = {}
                for _, s in ipairs(spawns) do per[s[4]] = (per[s[4]] or 0) + 1 end
                for _, s in ipairs(spawns) do
                    local map, x, y, src = s[1], s[2], s[3], s[4]
                    local key = map .. ":" .. floor(x) .. ":" .. floor(y) .. ":" .. tostring(src.id)
                    local wx, wy, inst = Places.ToWorld(map, x, y)
                    if wx and not seenSpawn[key] then
                        seenSpawn[key] = true
                        local few = (per[src] or 0) <= FEW and src.kind == "NPC"
                        -- a named mob keeps a pin per spawn; the rest merge with
                        -- spawns of the same objective and kind close by
                        local ck = few and ("few:" .. key)
                            or (gk .. ":" .. tostring(src.kind) .. ":" .. tostring(src.item ~= nil) .. ":" .. map)
                        local into
                        for _, c in ipairs(clusters[ck] or {}) do
                            if c.inst == inst and Places.Distance(c.wx, c.wy, wx, wy) <= MOB_CLUSTER then into = c break end
                        end
                        if into then
                            local n = into.count + 1
                            into.x, into.y = into.x + (x - into.x) / n, into.y + (y - into.y) / n
                            into.wx, into.wy = into.wx + (wx - into.wx) / n, into.wy + (wy - into.wy) / n
                            into.count = n
                        else
                            local c = { map = map, x = x, y = y, wx = wx, wy = wy, inst = inst, src = src, g = g,
                                        okind = okind, pos = pos, count = 1, few = few }
                            clusters[ck] = clusters[ck] or {}
                            table.insert(clusters[ck], c)
                            out[#out + 1] = c
                        end
                    end
                end
            end
        end
    end
    if #out > MAX_MOBS then
        local px, py = Places.Player()
        for _, c in ipairs(out) do c.d = px and Places.Distance(px, py, c.wx, c.wy) or 0 end
        table.sort(out, function(a, b)
            if a.few ~= b.few then return a.few end
            return a.d < b.d
        end)
        for i = #out, MAX_MOBS + 1, -1 do out[i] = nil end
    end
    return out
end

local function AddMobs()
    if OXP.settings.mapMobs == false or not Pins.QuestIconsOn() then return end
    for _, c in ipairs(Pins.MobClusters()) do
        local tip, obj = MobTip(c.src, c.okind, c.g, c.pos, c.count)
        local p
        if c.few then
            p = Take({ icon = ICON.boss, size = 18, label = c.src.name, alpha = 1, tip = tip, kind = "mob", count = 1 })
        else
            p = Take({ icon = obj[1], tint = obj[2], single = true, size = MOB_SIZE, alpha = 0.9, tip = tip,
                       tag = c.count > 1 and c.count or nil, count = c.count, kind = "mob" })
        end
        if not Place(p, c.map, c.x, c.y, 0, c.few and true or nil) then used = used - 1 end
    end
end

function Pins.Refresh()
    Pins.Clear()
    if not Engine.GetGuide() then return end
    if OXP.settings.mapPins ~= false then AddSteps() end
    AddAreas() -- Settings > Maps > Kill and loot areas (MapDraw.CurrentAreas)
    AddMobs()
end
Pins.Refresh = OXP.Perf.Wrap("map pins", Pins.Refresh)

--- Pins in use now (for tests and /oxp step): { {tip=..., num=..., label=...}, ... }
function Pins.Used()
    local out = {}
    for i = 1, used do
        local p = pool[i]
        out[#out + 1] = { tip = p.tip, num = p.num:GetText(), tag = p.tag:GetText(), label = p.label:GetText(),
                          size = p:GetWidth(), icon = p.icon, kind = p.kind, glow = p.glowOn, count = p.count,
                          at = p.at }
    end
    return out
end

local function Soon() OXP.Soon("PINS", Pins.Refresh) end
-- QUESTS_CHANGED: accepting, finishing or handing in a quest changes its
-- icon at once ("!" gone, objectives shown, "?" turning yellow), even while
-- the step itself stays put
for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "SETTINGS_CHANGED", "QUESTS_CHANGED" }) do
    OXP.Listen(m, Soon)
end
