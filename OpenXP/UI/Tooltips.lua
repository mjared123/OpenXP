-- Tooltips, bag marks and nameplates:
--   Items: which of your quests need them, with your count, so you don't sell
--          them; also items the guide says to save for a later quest. Bag
--          slots holding them get a quest mark.
--   Mobs:  which quest items they drop that you still need, and (when
--          Questie's own tooltips are off) the kill objectives they count for.
--          Their nameplates get the item's icon and your count.
--   NPCs:  which guide step needs them (pick up, turn in, talk to, kill).
-- Questie's database is only read while the game runs, never copied.
local _, OXP = ...

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
                list[#list + 1] = { quest = quest, qty = g.count or 1, pos = pos, mobs = mobs }
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
                local have = GetItemCount and GetItemCount(itemId, true) or 0
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
            for _, g in ipairs(step.goals) do
                local role
                if (g[1] == "mob" or g[1] == "target") and g.name and SameName(g.name, unitName) then
                    role = g[1]
                elseif npcId and (g[1] == "accept" or g[1] == "turnin") and g.quest then
                    local info = QuestDB.Info(g.quest)
                    local by = info and info.q and info.q[g[1] == "accept" and "startedBy" or "finishedBy"]
                    if by and InList(by[1], nil, npcId) then role = g[1] end
                end
                if role then
                    local what = L(ROLE[role])
                    if (role == "accept" or role == "turnin") then what = what .. ": " .. QuestDB.QuestName(g.quest) end
                    return pos, what
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
    local name = UnitName(unit)
    local npcId = Tips.NpcIdOf(UnitGUID(unit))
    local added = false
    if UnitCanAttack("player", unit) then
        local loot = Tips.MobItemLines(name, npcId)
        if #loot > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine(Icon(QUEST_ICON, 16) .. ORANGE .. L("Loot for your quests") .. "|r")
            for _, n in ipairs(loot) do
                local left = Icon(GetItemIcon and GetItemIcon(n.itemId) or QUEST_ICON) .. GOLD .. (n.name or "?") .. "|r"
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

function Tips.PlateInfo(unit)
    if not (unit and UnitExists(unit)) or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return nil end
    local loot = Tips.MobItemLines(UnitName(unit), Tips.NpcIdOf(UnitGUID(unit)))
    return loot[1], #loot
end

local function PlateFrame(plate)
    local f = plates[plate]
    if f then return f end
    local uf = plate.UnitFrame
    local above = uf and uf.name or uf or plate
    f = CreateFrame("Frame", nil, plate)
    f:SetSize(60, 24)
    f:SetPoint("BOTTOM", above, "TOP", 0, 4)
    f:SetFrameStrata("HIGH")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(24, 24)
    f.icon:SetPoint("LEFT")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.mark = f:CreateTexture(nil, "OVERLAY")
    f.mark:SetSize(14, 14)
    f.mark:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -5, 5)
    f.mark:SetTexture(QUEST_ICON)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local font, size = f.text:GetFont()
    if font then f.text:SetFont(font, (size or 12) + 1, "OUTLINE") end
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    plates[plate] = f
    return f
end

function Tips.UpdatePlate(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local n, count
    if Tips.NameplatesEnabled() then n, count = Tips.PlateInfo(unit) end
    if not n then
        if plates[plate] then plates[plate]:Hide() end
        return
    end
    local f = PlateFrame(plate)
    f.icon:SetTexture(GetItemIcon and GetItemIcon(n.itemId) or QUEST_ICON)
    f.text:SetText(n.have .. "/" .. n.need .. (count > 1 and " +" or ""))
    f:SetWidth(28 + (f.text:GetStringWidth() or 30))
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

OXP.On("NAME_PLATE_UNIT_ADDED", function(_, unit) pcall(Tips.UpdatePlate, unit) end)
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
