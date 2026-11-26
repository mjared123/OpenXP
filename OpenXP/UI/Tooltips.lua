-- Tooltips, bag marks and nameplates:
--   Items: which of your quests need them, with your count, so you don't sell
--          them; also items the guide says to save for a later quest. Bag
--          slots holding them get a quest mark.
--   Mobs:  which quest items they drop that you still need, and (when
--          Questie's own tooltips are off) the kill objectives they count for.
--          Their nameplates get the item's icon and your count.
--   NPCs:  which guide step needs them (pick up, turn in, talk to, kill).
-- Questie's database is only read while the game runs, never copied.
local ADDON, OXP = ...

local Tips = {}
OXP.Tooltips = Tips

local Engine, QuestDB, Quests, L = OXP.Engine, OXP.QuestDB, OXP.Quests, OXP.L
local fmt = string.format

local LOOKAHEAD = 40
local GREEN, GREY, GOLD, WHITE, ORANGE = "|cFF66BB6A", "|cFF9E9E9E", "|cFFFFC107", "|cFFFFFFFF", "|cFFFF8C1A"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local GetItemCount = C_Item and C_Item.GetItemCount or _G.GetItemCount
local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
local GetItemIcon = C_Item and C_Item.GetItemIconByID or _G.GetItemIcon
local GetContainerItemID = C_Container and C_Container.GetContainerItemID or _G.GetContainerItemID

function Tips.Enabled() return OXP.settings.tooltips ~= false end
function Tips.NameplatesEnabled() return Tips.Enabled() and OXP.settings.nameplates ~= false end

-- Questie draws its own quest lines on mob tooltips unless turned off
function Tips.QuestieShowsMobLines()
    if not _G.QuestieLoader then return false end
    local prof = _G.Questie and _G.Questie.db and _G.Questie.db.profile
    return not (prof and prof.enableTooltips == false)
end

function Tips.NpcIdOf(guid)
    if not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function ItemName(id)
    local name = GetItemInfo and GetItemInfo(id)
    if not name then
        local item = QuestDB.Get("Item", id)
        name = item and item.name
    end
    return name
end

-- "Kobold Vermin slain: 3/8" -> "Kobold Vermin", 3, 8
local function ParseObjective(text)
    local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
    if not name then return nil end
    return (name:gsub("%s+slain$", "")), tonumber(have), tonumber(need)
end

--- Every quest in the log with its objectives.
function Tips.LogQuests()
    local quests = {}
    if not (GetNumQuestLogEntries and GetQuestLogLeaderBoard) then return quests end
    for i = 1, (GetNumQuestLogEntries() or 0) do
        local title, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(i)
        if title and not isHeader then
            local q = { title = title, id = questId, objectives = {} }
            for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
                local text, kind, finished = GetQuestLogLeaderBoard(j, i)
                local name, have, need
                if text then name, have, need = ParseObjective(text) end
                if name then
                    q.objectives[#q.objectives + 1] = { kind = kind, name = name, have = have, need = need, done = finished and true or false }
                end
            end
            quests[#quests + 1] = q
        end
    end
    return quests
end

local function SameName(a, b) return a and b and a:lower() == b:lower() end

------------------------------------------------------------------------
-- What the loaded guide wants collected: itemId -> { {quest, qty, pos, mobs} }
------------------------------------------------------------------------

local collectIndex, collectGuide
function Tips.CollectIndex()
    local guide = Engine.GetGuide()
    if not guide then return {} end
    if collectGuide == guide and collectIndex then return collectIndex end
    collectIndex, collectGuide = {}, guide
    for pos, step in ipairs(Engine.GetSteps()) do
        local mobs, quest
        for _, g in ipairs(step.goals) do
            if g[1] == "mob" then
                mobs = mobs or {}
                mobs[#mobs + 1] = g.name
            elseif g.quest and not quest then
                quest = g.quest
            end
        end
        for _, g in ipairs(step.goals) do
            if g[1] == "collect" then
                local list = collectIndex[g.item] or {}
                collectIndex[g.item] = list
                -- forquest: the quest the items are for when it isn't on this
                -- step (Elwynn's apples for the Applejack Still, GitHub #129)
                list[#list + 1] = { quest = g.forquest or quest, qty = g.count or 1, pos = pos, mobs = mobs }
            end
        end
    end
    return collectIndex
end

local function QuestItemIds(questId)
    local ids = {}
    local q = questId and QuestDB.Get("Quest", questId)
    local objs = q and q.objectives
    for _, e in ipairs(type(objs) == "table" and type(objs[3]) == "table" and objs[3] or {}) do
        if type(e) == "table" and e[1] then ids[e[1]] = true end
    end
    for itemId, list in pairs(Tips.CollectIndex()) do
        for _, c in ipairs(list) do
            if c.quest == questId then ids[itemId] = true end
        end
    end
    return ids
end

local dropCache = {}
local function DropSet(itemId)
    local set = dropCache[itemId]
    if set then return set end
    local item = QuestDB.Get("Item", itemId)
    if not item then return {} end
    set = {}
    for _, id in pairs(type(item.npcDrops) == "table" and item.npcDrops or {}) do set[id] = true end
    dropCache[itemId] = set
    return set
end

local function InList(list, name, npcId)
    if not list then return false end
    local lname = name and name:lower()
    for _, v in ipairs(list) do
        if npcId and tonumber(v) == npcId then return true end
        if lname and type(v) == "string" and v:lower() == lname then return true end
    end
    return false
end

function Tips.MobDrops(itemId, unitName, npcId)
    if npcId and DropSet(itemId)[npcId] then return true end
    for _, c in ipairs(Tips.CollectIndex()[itemId] or {}) do
        if InList(c.mobs, unitName, npcId) then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Every quest item you still want (cached until the log, bags or step change)
------------------------------------------------------------------------

local needCache, needKey
local dirty = true
function Tips.Invalidate() dirty = true end

function Tips.NeededItems()
    local key = tostring(Engine.GetGuide()) .. ":" .. tostring(Engine.GetPosition())
    if not dirty and needCache and needKey == key then return needCache end
    local list, seen = {}, {}
    for _, q in ipairs(Tips.LogQuests()) do
        local itemIds
        for _, o in ipairs(q.objectives) do
            if o.kind == "item" then
                itemIds = itemIds or QuestItemIds(q.id)
                local itemId
                for id in pairs(itemIds) do
                    if SameName(ItemName(id), o.name) then itemId = id break end
                end
                list[#list + 1] = { itemId = itemId, name = o.name, title = q.title, questId = q.id,
                                    have = o.have, need = o.need, done = o.done }
            end
        end
        if q.id then seen[q.id] = true end
    end
    local cur = Engine.GetPosition() or 1
    for itemId, entries in pairs(Tips.CollectIndex()) do
        for _, c in ipairs(entries) do
            local qid = c.quest
            local state = Engine.StepState(c.pos)
            if c.pos >= cur and state ~= "done" and not (qid and seen[qid]) and not (qid and Quests.IsTurnedIn(qid)) then
                if qid then seen[qid] = true end
                local cnt = (C_Item and C_Item.GetItemCount) or GetItemCount
                local have = cnt and cnt(itemId, true) or 0
                list[#list + 1] = { itemId = itemId, name = ItemName(itemId), questId = qid,
                                    title = qid and QuestDB.QuestName(qid) or L("Later in the guide"),
                                    have = have, need = c.qty, done = have >= c.qty, later = c.pos }
            end
        end
    end
    table.sort(list, function(a, b) return (a.later or 0) < (b.later or 0) end)
    needCache, needKey, dirty = list, key, false
    return list
end

function Tips.MobItemLines(unitName, npcId)
    local lines = {}
    for _, n in ipairs(Tips.NeededItems()) do
        if n.itemId and not n.done and Tips.MobDrops(n.itemId, unitName, npcId) then lines[#lines + 1] = n end
    end
    return lines
end

function Tips.KillLines(unitName)
    local lines = {}
    if not unitName then return lines end
    local lname = unitName:lower()
    for _, q in ipairs(Tips.LogQuests()) do
        for _, o in ipairs(q.objectives) do
            if o.kind == "monster" then
                local oname = o.name:lower()
                if oname == lname or oname:find(lname, 1, true) then
                    lines[#lines + 1] = { title = q.title, have = o.have, need = o.need, done = o.done }
                end
            end
        end
    end
    return lines
end

local ROLE = { accept = "Pick up", turnin = "Turn in", mob = "Kill", target = "Talk to" }

--- First guide step (from the current one on) that needs this NPC: pos, what.
function Tips.GuideStep(unitName, npcId)
    if not Engine.GetGuide() then return nil end
    local steps = Engine.GetSteps()
    local cur = Engine.GetPosition() or 1
    for pos = cur, math.min(#steps, cur + LOOKAHEAD) do
        local step = steps[pos]
        local state = Engine.StepState(pos)
        if state == "current" or state == "todo" then
            -- a mob whose objective is done no longer counts (Goals.NeededMobs)
            local needed
            for _, g in ipairs(step.goals) do
                local role
                if g[1] == "mob" and g.name and SameName(g.name, unitName) then
                    if not needed then
                        needed = {}
                        for _, m in ipairs(OXP.Goals.NeededMobs(step)) do needed[m.name:lower()] = true end
                    end
                    if needed[g.name:lower()] then role = "mob" end
                elseif g[1] == "target" and g.name and SameName(g.name, unitName) then
                    role = g[1]
                elseif npcId and (g[1] == "accept" or g[1] == "turnin") and g.quest then
                    local info = QuestDB.Info(g.quest)
                    local by = info and info.q and info.q[g[1] == "accept" and "startedBy" or "finishedBy"]
                    if by and InList(by[1], nil, npcId) then role = g[1] end
                end
                if role then
                    local what = L(ROLE[role])
                    if (role == "accept" or role == "turnin") then what = what .. ": " .. QuestDB.QuestName(g.quest) end
                    return pos, what, role
                end
            end
        end
    end
end

local function Progress(have, need, done)
    return ((done or have >= need) and GREEN or WHITE) .. have .. "/" .. need .. "|r"
end

local function Icon(texture, size)
    return "|T" .. tostring(texture) .. ":" .. (size or 14) .. "|t "
end

function Tips.AddLines(tooltip, unit)
    if not Tips.Enabled() or not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    -- secret in dungeons (GitHub #98): no quest lines then
    local name = OXP.Util.UnitName(unit)
    if not name then return end
    local npcId = Tips.NpcIdOf(OXP.Util.UnitGUID(unit))
    local added = false
    if UnitCanAttack("player", unit) then
        local loot = Tips.MobItemLines(name, npcId)
        if #loot > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine(Icon(QUEST_ICON, 16) .. ORANGE .. L("Loot for your quests") .. "|r")
            for _, n in ipairs(loot) do
                local left = Icon(((C_Item and C_Item.GetItemIconByID) or GetItemIcon or function() end)(n.itemId) or QUEST_ICON) .. GOLD .. (n.name or "?") .. "|r"
                tooltip:AddDoubleLine(left, Progress(n.have, n.need, n.done))
                local sub = "    " .. GREY .. n.title
                if n.later then sub = sub .. " " .. fmt(L("(pick up at step %d)"), n.later) end
                tooltip:AddLine(sub .. "|r")
            end
            added = true
        end
        if not Tips.QuestieShowsMobLines() then
            for _, q in ipairs(Tips.KillLines(name)) do
                if not added then tooltip:AddLine(" ") added = true end
                tooltip:AddDoubleLine((q.done and GREY or GOLD) .. q.title .. "|r", Progress(q.have, q.need, q.done))
            end
        end
    end
    local pos, what = Tips.GuideStep(name, npcId)
    if pos then
        if not added then tooltip:AddLine(" ") end
        tooltip:AddLine(GREEN .. "OpenXP|r " .. fmt(L("step %d"), pos) .. GREY .. " - " .. what .. "|r")
        added = true
    end
    if added then tooltip:Show() end
end

------------------------------------------------------------------------
-- Items: "keep this, a quest needs it"
------------------------------------------------------------------------

function Tips.ItemLines(itemId, itemName)
    local lines = {}
    if not itemId then return lines end
    itemName = itemName or ItemName(itemId)
    for _, n in ipairs(Tips.NeededItems()) do
        if n.itemId == itemId or (not n.itemId and SameName(n.name, itemName)) then lines[#lines + 1] = n end
    end
    return lines
end

function Tips.IsNeeded(itemId)
    if not (itemId and Tips.Enabled()) then return false end
    for _, n in ipairs(Tips.NeededItems()) do
        if n.itemId == itemId then return true end
    end
    return false
end

function Tips.SetBorder(tooltip, r, g, b)
    local ns = tooltip.NineSlice
    if ns and ns.SetBorderColor then
        pcall(ns.SetBorderColor, ns, r, g, b)
    elseif tooltip.SetBackdropBorderColor then
        pcall(tooltip.SetBackdropBorderColor, tooltip, r, g, b)
    end
end

function Tips.AddItemLines(tooltip, itemId, itemName)
    if not Tips.Enabled() or not itemId then return end
    local lines = Tips.ItemLines(itemId, itemName)
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(Icon(QUEST_ICON, 20) .. ORANGE .. L("QUEST ITEM - DON'T SELL") .. "|r")
    for _, q in ipairs(lines) do
        local left = (q.done and GREY or GOLD) .. q.title .. "|r"
        if q.later then left = left .. GREY .. " " .. fmt(L("(pick up at step %d)"), q.later) .. "|r" end
        tooltip:AddDoubleLine(left, Progress(q.have, q.need, q.done))
    end
    Tips.SetBorder(tooltip, 1, 0.55, 0.1)
    tooltip.openxpBorder = true
    tooltip:Show()
end

local function ResetBorder(tooltip)
    if tooltip.openxpBorder then
        tooltip.openxpBorder = nil
        local c = _G.TOOLTIP_DEFAULT_COLOR
        Tips.SetBorder(tooltip, c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end
end

local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    unit = unit or (UnitExists("mouseover") and "mouseover")
    ResetBorder(tooltip)
    pcall(Tips.AddLines, tooltip, unit)
end

local function OnItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip then return end
    local itemId = type(data) == "table" and data.id or nil
    local name, link = tooltip:GetItem()
    if not itemId and link then itemId = tonumber(link:match("item:(%d+)")) end
    ResetBorder(tooltip)
    pcall(Tips.AddItemLines, tooltip, itemId, name)
end

if _G.TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    _G.TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    _G.TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
else
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
        GameTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
    end
    if _G.ItemRefTooltip and _G.ItemRefTooltip.HookScript then
        _G.ItemRefTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
    end
end
for _, tt in ipairs({ GameTooltip, _G.ItemRefTooltip }) do
    if tt and tt.HookScript then tt:HookScript("OnHide", ResetBorder) end
end

------------------------------------------------------------------------
-- Bag slots: a quest mark on items you need
------------------------------------------------------------------------

function Tips.MarkBagButton(button, bag, slot)
    if not button then return end
    local id = GetContainerItemID and bag and slot and GetContainerItemID(bag, slot)
    local need = Tips.IsNeeded(id)
    if need and not button.openxpQuestMark then
        local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSize(18, 18)
        t:SetPoint("TOPLEFT", -2, 2)
        t:SetTexture(QUEST_ICON)
        button.openxpQuestMark = t
    end
    if button.openxpQuestMark then button.openxpQuestMark:SetShown(need) end
end

local function MarkContainer(frame)
    if not (frame and frame.GetName and frame:GetName()) then return end
    local bag = frame:GetID()
    for i = 1, frame.size or 0 do
        local button = _G[frame:GetName() .. "Item" .. i]
        if button then pcall(Tips.MarkBagButton, button, bag, button:GetID()) end
    end
end

if hooksecurefunc and _G.ContainerFrame_Update then
    hooksecurefunc("ContainerFrame_Update", MarkContainer)
end

local function RefreshBags()
    for i = 1, (NUM_CONTAINER_FRAMES or 0) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then MarkContainer(frame) end
    end
end

------------------------------------------------------------------------
-- Nameplates: the needed item's icon and your count above enemies that drop it
------------------------------------------------------------------------

local plates = {}
local MAP = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Map\\"
-- the one icon set (map, minimap, card): silver sword, sack, skull, speech
-- bubble and the yellow ! ?, no circle behind them
local PLATE_ICON = { accept = "quest_available", turnin = "quest_complete", target = "talk",
                     kill = "kill", mob = "kill", loot = "loot", boss = "boss" }

--- Does a step on the card (not a later one) want this mob for an
--- objective of a quest in your log that is still open?
function Tips.ActiveMobNeeded(unitName)
    if not (unitName and Engine.GetGuide()) then return false end
    for _, pos in ipairs(Engine.GetActive()) do
        for _, m in ipairs(OXP.Goals.NeededMobs(Engine.GetSteps()[pos])) do
            if SameName(m.name, unitName) then return true end
        end
    end
    return false
end

--- What a mob's or NPC's nameplate shows: { kind, text, item = itemId,
--- step = pos } or nil. kind: "loot" (drops an item a quest needs), "kill"
--- (counts for a kill objective), "boss" (a named mob the step needs, with
--- only a spawn or two), "accept", "turnin", "target" (the guide's next
--- steps need this NPC).
function Tips.PlateInfo(unit)
    if not (unit and UnitExists(unit)) or UnitIsPlayer(unit) then return nil end
    local name = OXP.Util.UnitName(unit) -- secret in dungeons (GitHub #98)
    if not name then return nil end
    local npcId = Tips.NpcIdOf(OXP.Util.UnitGUID(unit))
    if UnitCanAttack("player", unit) then
        -- Enemies are marked only for quests in your log right now with
        -- that objective still open. Before 2.0.0-dev4 the guide's later
        -- steps marked them too (NeededItems' "later" items, GuideStep's
        -- 40-step look-ahead), before you had the quest.
        local loot = {}
        for _, n in ipairs(Tips.MobItemLines(name, npcId)) do
            if not n.later and n.questId and Quests.IsOnQuest(n.questId) then loot[#loot + 1] = n end
        end
        local boss = Tips.IsPinpointed(npcId)
        local n = loot[1]
        if n then
            return { kind = boss and "boss" or "loot", item = n.itemId,
                     text = n.have .. "/" .. n.need .. (#loot > 1 and " +" or "") }
        end
        for _, q in ipairs(Tips.KillLines(name)) do
            if not q.done then return { kind = boss and "boss" or "kill", text = q.have .. "/" .. q.need } end
        end
        -- the step on the card names it for an open objective of a quest you
        -- have (an item the quest data doesn't tie to this mob)
        if boss then return { kind = "boss", text = "" } end
        if Tips.ActiveMobNeeded(name) then return { kind = "mob", text = "" } end
        return nil
    end
    local pos, _, role = Tips.GuideStep(name, npcId)
    -- People: the game already floats a ! or ? over a quest giver, so
    -- OpenXP's own ! ? marker is off unless you ask for it (it made two
    -- markers per NPC); "talk to" has no marker of the game's, so it shows.
    -- Step numbers only with their setting.
    if not pos then return nil end
    local s = OXP.settings
    if (role == "accept" or role == "turnin") and s.nameplateGivers ~= true then return nil end
    if role == "accept" or role == "turnin" or role == "target" then
        return { kind = role, text = s.nameplateStepNumbers == true and ("#" .. pos) or "", step = pos }
    end
end

--- Is npcId a named mob the current step needs (it has only a spawn or two)?
function Tips.IsPinpointed(npcId)
    if not npcId or not Engine.GetGuide() then return false end
    for _, pos in ipairs(Engine.GetActive()) do
        local step = Engine.GetSteps()[pos]
        for _, p in ipairs(step and OXP.Areas.Pinpoints(step) or {}) do
            -- only for a quest in your log (not one the step picks up later)
            if p.kind == "NPC" and p.id == npcId and (not p.quest or Quests.IsOnQuest(p.quest)) then return true end
        end
    end
    return false
end

-- Where a plate's marker goes: above the name of whichever nameplate add-on
-- draws it (KuiNameplates for Forever, Kesava's KuiNameplates, Plater), else
-- the game's own plate. The marker is parented to that add-on's frame so it
-- fades with it.
local function PlateHost(plate)
    local function T(v) return type(v) == "table" and v or nil end
    local function Bar(f) return f and (T(f.HealthBar) or T(f.healthBar) or T(f.health) or T(f.Health)) end
    local kf = T(plate.KuiForeverPlate)
    if kf then return kf, T(kf.name) or kf, Bar(kf) end
    local kui = T(plate.kui)
    if kui then return kui, T(kui.NameText) or T(kui.HealthBar) or kui, Bar(kui) end
    local plater = T(plate.unitFrame)
    if plater then return plater, T(plater.healthBar) or plater, Bar(plater) end
    local uf = T(plate.UnitFrame)
    return plate, uf and (T(uf.name) or uf) or plate, Bar(uf)
end

-- The marker sits to the right of the health bar, like Questie's icon sits
-- to its left (Matt, 2026-11-25): above the name it collided with raid
-- markers, and nameplate add-ons move those up and down (KuiNameplates
-- raises them over your DoTs), so no spot above the name stays clear.
local SIDE_GAP = 16
-- KuiNameplates draws arrows beside your target's bar: there the marker
-- goes past the right arrow; on other plates it stays close to the bar
local KUI_GAP = 20   -- clear of Kui's DoT skull (4 to 16 right of the bar)
local ARROW_GAP = 3
local hookedArrows = setmetatable({}, { __mode = "k" })
local LEVEL_GAP = 8

local PlateFrame

local function PlateFrameNow(plate)
    local host, above, bar = PlateHost(plate)
    local kui = type(plate.KuiForeverPlate) == "table" or type(plate.kui) == "table"
    -- a name-only plate (friendly, in KuiNameplates) hides its bar: then beside the name
    if bar and bar.IsShown and not bar:IsShown() then bar = nil end
    -- the game's own plate (no add-on) on Forever has a level box right of
    -- the bar: past that one
    local uf = plate.UnitFrame
    local level = host == plate and type(uf) == "table" and uf.PlayerLevelDiffFrame
    if type(level) ~= "table" then level = nil end
    if level and level.IsShown and level:IsShown() then bar = level end
    local f = plates[plate]
    if not f then
        f = CreateFrame("Frame", nil, host)
        f.badge = f:CreateTexture(nil, "ARTWORK")
        f.badge:SetSize(22, 22)
        f.badge:SetPoint("LEFT")
        f.item = f:CreateTexture(nil, "OVERLAY")
        f.item:SetSize(14, 14)
        f.item:SetPoint("BOTTOMRIGHT", f.badge, "BOTTOMRIGHT", 5, -3)
        f.item:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.text:SetPoint("LEFT", f.badge, "RIGHT", 4, 0)
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetShadowOffset(1, -1)
        plates[plate] = f
    end
    f:SetParent(host)
    f.host = host
    f:SetSize(60, 24)
    f:ClearAllPoints()
    local arrows = kui and type(plate.KuiForeverPlate) == "table" and plate.KuiForeverPlate.arrows
    local arrow = type(arrows) == "table" and type(arrows.right) == "table" and arrows.right or nil
    -- Kui shows and hides the arrow as your target changes (SetShown, in
    -- either order with our events): the marker moves with it
    if arrow and not hookedArrows[arrow] and hooksecurefunc and arrow.SetShown then
        hookedArrows[arrow] = true
        hooksecurefunc(arrow, "SetShown", function()
            local mine = plates[plate]
            if mine and mine:IsShown() then pcall(PlateFrame, plate) end
        end)
    end
    if arrow and arrow.IsShown and arrow:IsShown() and bar then
        f:SetPoint("LEFT", arrow, "RIGHT", ARROW_GAP, 0)
    elseif not bar and above.GetStringWidth and above.GetJustifyH then
        -- beside the name itself: a name text is often as wide as the
        -- plate with the name centred in it, so its right edge sat far off
        -- in the air, by nobody (Matt's "? #46" in a Darkshire doorway)
        local w = above:GetStringWidth() or 0
        local just = above:GetJustifyH()
        if just == "LEFT" then
            f:SetPoint("LEFT", above, "LEFT", w + SIDE_GAP / 2, 0)
        elseif just == "RIGHT" then
            f:SetPoint("LEFT", above, "RIGHT", SIDE_GAP / 2, 0)
        else
            f:SetPoint("LEFT", above, "CENTER", w / 2 + SIDE_GAP / 2, 0)
        end
    else
        f:SetPoint("LEFT", bar or above, "RIGHT", (bar and kui) and KUI_GAP or (bar and bar == level) and LEVEL_GAP or SIDE_GAP, 0)
    end
    f:SetFrameStrata("HIGH")
    return f
end
PlateFrame = PlateFrameNow

--- The marker on a nameplate (tests): its frame, or nil.
function Tips.PlateMarker(plate) return plates[plate] end

local TEXT_COLOR = { kill = { 1, 0.62, 0.56 }, boss = { 1, 0.82, 0.38 }, loot = { 1, 0.86, 0.5 },
                     accept = { 1, 0.86, 0.3 }, turnin = { 1, 0.86, 0.3 }, target = { 0.6, 0.82, 1 },
                     mob = { 1, 0.62, 0.56 } }

function Tips.UpdatePlate(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local info
    if Tips.NameplatesEnabled() then info = Tips.PlateInfo(unit) end
    if not info then
        if plates[plate] then plates[plate]:Hide() end
        return
    end
    local f = PlateFrame(plate)
    local big = info.kind == "boss"
    local size = big and 22 or 18
    f.badge:SetSize(size, size)
    f.badge:SetVertexColor(1, 1, 1, 1)
    f.badge:SetTexture(OXP.Util.IconFile(MAP .. (PLATE_ICON[info.kind] or "kill"), size, f))
    local icon = info.item and ((C_Item and C_Item.GetItemIconByID) or GetItemIcon or function() end)(info.item)
    f.item:SetTexture(icon)
    f.item:SetShown(icon ~= nil)
    OXP.Fonts.Apply(f.text, OXP.Fonts.Path(), 13, "OUTLINE")
    local c = TEXT_COLOR[info.kind] or TEXT_COLOR.kill
    f.text:SetTextColor(c[1], c[2], c[3])
    f.text:SetText(info.text or "")
    f:SetWidth((big and 30 or 26) + (f.text:GetStringWidth() or 30))
    f.info = info
    f:Show()
end

local function RefreshPlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then pcall(Tips.UpdatePlate, unit) end
    end
end

local pending
local function RefreshSoon()
    Tips.Invalidate()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        RefreshPlates()
        RefreshBags()
    end)
end

OXP.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    pcall(Tips.UpdatePlate, unit)
    -- a nameplate add-on may build its plate after us: move onto it next frame
    if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(Tips.UpdatePlate, unit) end) end
end)
OXP.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plates[plate] then plates[plate]:Hide() end
end)
for _, m in ipairs({ "QUESTS_CHANGED", "BAGS_CHANGED", "STEP_CHANGED", "GUIDE_LOADED" }) do
    OXP.Listen(m, function()
        if m == "GUIDE_LOADED" then collectIndex = nil end
        RefreshSoon()
    end)
end

------------------------------------------------------------------------
-- Extras: auto loot and max camera distance (both off unless you turn them on)
------------------------------------------------------------------------

local function CVarDefault(name, fallback)
    local ok, v = pcall(GetCVarDefault or function() end, name)
    return ok and v or fallback
end

function Tips.ApplyExtras(login)
    local s = OXP.settings
    if not SetCVar then return end
    if s.autoLoot then
        SetCVar("autoLootDefault", "1")
    elseif not login then
        SetCVar("autoLootDefault", CVarDefault("autoLootDefault", "0"))
    end
    if s.maxCamera then
        SetCVar("cameraDistanceMaxZoomFactor", "2.6")
    elseif not login then
        SetCVar("cameraDistanceMaxZoomFactor", CVarDefault("cameraDistanceMaxZoomFactor", "1.9"))
    end
end

OXP.OnReady(function() pcall(Tips.ApplyExtras, true) end)
