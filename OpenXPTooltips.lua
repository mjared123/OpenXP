-- OpenXP tooltips
--   Items: which of your quests need them, with your count, so you don't sell
--          them. Also items the current guide says to save for a later quest.
--          Bag slots holding them get a quest marker.
--   Mobs:  which quest items they drop that you still need, and (when
--          Questie's own tooltips are off) the kill objectives they count for.
--          Their nameplates get the item's icon and your count.
--   NPCs:  which guide step needs them (pick up, turn in, talk to, kill).
-- Questie's database is only read while the game runs, never copied.

local _, addon = ...
local L = addon.locale.Get
local fmt = string.format

local tips = {}
addon.openxpTooltips = tips

local LOOKAHEAD = 40 -- guide steps checked past the current one
local GREEN, GREY, GOLD, WHITE = "|cFF66BB6A", "|cFF9E9E9E", "|cFFFFC107", "|cFFFFFFFF"
local ORANGE = "|cFFFF8C1A"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local GetItemCount = C_Item and C_Item.GetItemCount or _G.GetItemCount
local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
local GetItemIcon = C_Item and C_Item.GetItemIconByID or _G.GetItemIcon
local IsTurnedIn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or _G.IsQuestFlaggedCompleted
local GetContainerItemID = C_Container and C_Container.GetContainerItemID or _G.GetContainerItemID

local function Profile()
    return addon.settings and addon.settings.profile
end

function tips.Enabled()
    local p = Profile()
    return not (p and p.openxpTooltips == false)
end

function tips.NameplatesEnabled()
    local p = Profile()
    return tips.Enabled() and not (p and p.openxpNameplates == false)
end

-- Questie draws its own quest lines on mob tooltips unless you turned them off
function tips.QuestieShowsMobLines()
    if not _G.QuestieLoader then return false end
    local q = _G.Questie
    local prof = q and q.db and q.db.profile
    return not (prof and prof.enableTooltips == false)
end

function tips.NpcIdOf(guid)
    if not guid then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function Strip(text)
    if not text then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return text
end

local function QGet(kind, id)
    local card = addon.card
    return card and card.QGet and card.QGet(kind, id)
end

local function ItemName(id)
    local name = GetItemInfo and GetItemInfo(id)
    if not name and addon.GetItemName then
        local ok, n = pcall(addon.GetItemName, id)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    if not name then
        local item = QGet("Item", id)
        name = item and item.name
    end
    return name
end

local function QuestName(id)
    if addon.GetQuestName then
        local ok, n = pcall(addon.GetQuestName, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    local q = QGet("Quest", id)
    return q and q.name or fmt(L("Quest %d"), id)
end

-- "Kobold Vermin slain: 3/8" -> "Kobold Vermin", 3, 8
local function ParseObjective(text)
    local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
    if not name then return end
    name = name:gsub("%s+slain$", "")
    return name, tonumber(have), tonumber(need)
end

-- Quest log: every quest with its id and objectives
function tips.LogQuests()
    local quests = {}
    if not (GetNumQuestLogEntries and GetQuestLogLeaderBoard) then return quests end
    for i = 1, (GetNumQuestLogEntries() or 0) do
        local title, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(i)
        if title and not isHeader then
            local q = {title = title, id = questId, objectives = {}}
            for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
                local text, kind, finished = GetQuestLogLeaderBoard(j, i)
                local name, have, need
                if text then name, have, need = ParseObjective(text) end
                if name then
                    tinsert(q.objectives, {kind = kind, name = name, have = have, need = need,
                                           done = finished and true or false})
                end
            end
            tinsert(quests, q)
        end
    end
    return quests
end

local function SameName(a, b)
    return a and b and a:lower() == b:lower()
end

local function InList(list, name, npcId)
    if not list then return end
    local lname = name and name:lower()
    for _, v in ipairs(list) do
        if npcId and tonumber(v) == npcId then return true end
        if lname and type(v) == "string" and v:lower() == lname then return true end
    end
end

---------------------------------------------------------------------------
-- What the current guide wants collected: itemId -> {{questId, qty, step, mobs}}
-- Built once per guide; mobs are the .mob lines in the same step.
---------------------------------------------------------------------------
local collectIndex, collectGuide
function tips.CollectIndex()
    local guide = addon.currentGuide
    if not (guide and guide.steps) then return {} end
    if collectGuide == guide and collectIndex then return collectIndex end
    collectIndex, collectGuide = {}, guide
    for i, step in ipairs(guide.steps) do
        local mobs
        for _, e in ipairs(step.elements or {}) do
            if e.mobs then
                mobs = mobs or {}
                for _, m in ipairs(e.mobs) do tinsert(mobs, m) end
            end
        end
        for _, e in ipairs(step.elements or {}) do
            if e.tag == "collect" and e.id then
                local list = collectIndex[e.id] or {}
                collectIndex[e.id] = list
                tinsert(list, {questId = e.questId, qty = e.qty or 1, step = i, mobs = mobs})
            end
        end
    end
    return collectIndex
end

-- Item ids that could be behind one quest's objectives (Questie, then guide)
local function QuestItemIds(questId)
    local ids = {}
    local q = questId and QGet("Quest", questId)
    local objs = q and q.objectives
    for _, e in ipairs(type(objs) == "table" and type(objs[3]) == "table" and objs[3] or {}) do
        if type(e) == "table" and e[1] then ids[e[1]] = true end
    end
    for itemId, list in pairs(tips.CollectIndex()) do
        for _, c in ipairs(list) do
            if c.questId == questId then ids[itemId] = true end
        end
    end
    return ids
end

-- Which NPCs drop an item, from Questie (looked up once per item)
local dropCache = {}
local function DropSet(itemId)
    local set = dropCache[itemId]
    if set then return set end
    local item = QGet("Item", itemId)
    if not item then return {} end -- Questie missing or not ready: ask again later
    set = {}
    if type(item.npcDrops) == "table" then
        for _, id in pairs(item.npcDrops) do set[id] = true end
    end
    dropCache[itemId] = set
    return set
end

-- Does this mob drop the item? Questie's drop list, or a guide step that
-- collects it from this mob
function tips.MobDrops(itemId, unitName, npcId)
    if npcId and DropSet(itemId)[npcId] then return true end
    for _, c in ipairs(tips.CollectIndex()[itemId] or {}) do
        if InList(c.mobs, unitName, npcId) then return true end
    end
end

---------------------------------------------------------------------------
-- Every quest item you still want: {itemId, name, title, have, need, done, later}
-- From your quest log's item objectives, then items the guide says to save
-- for quests you haven't picked up yet. Cached until the log, bags or guide
-- step change.
---------------------------------------------------------------------------
local needCache, needKey
local dirty = true

function tips.Invalidate()
    dirty = true
end

local LazyTitle = {__index = function(t, k)
    if k ~= "title" then return end
    local v = t.questId and QuestName(t.questId) or L("Later in the guide")
    rawset(t, "title", v)
    return v
end}

function tips.NeededItems()
    local guide = addon.currentGuide
    local cur = addon.GetGuideProgress and addon.GetGuideProgress() or 1
    local key = tostring(guide) .. ":" .. tostring(cur)
    if not dirty and needCache and needKey == key then return needCache end

    local list, seen = {}, {}
    for _, q in ipairs(tips.LogQuests()) do
        local itemIds
        for _, o in ipairs(q.objectives) do
            if o.kind == "item" then
                itemIds = itemIds or QuestItemIds(q.id)
                local itemId
                for id in pairs(itemIds) do
                    if SameName(ItemName(id), o.name) then itemId = id; break end
                end
                tinsert(list, {itemId = itemId, name = o.name, title = q.title, questId = q.id,
                               have = o.have, need = o.need, done = o.done})
            end
        end
        -- a quest you already have is covered by its own objectives
        if q.id then seen[q.id] = true end
    end

    for itemId, entries in pairs(tips.CollectIndex()) do
        for _, c in ipairs(entries) do
            local qid = c.questId
            local step = guide and guide.steps and guide.steps[c.step]
            if c.step >= cur and not (step and step.completed) and not (qid and seen[qid])
                    and not (qid and IsTurnedIn and IsTurnedIn(qid)) then
                if qid then seen[qid] = true end
                local have = GetItemCount and GetItemCount(itemId, true) or 0
                -- the quest's name is looked up only when a tooltip shows it
                tinsert(list, setmetatable({itemId = itemId, name = ItemName(itemId), questId = qid,
                               have = have, need = c.qty, done = have >= c.qty, later = c.step},
                               LazyTitle))
            end
        end
    end
    table.sort(list, function(a, b) return (a.later or 0) < (b.later or 0) end)

    needCache, needKey, dirty = list, key, false
    return list
end

-- Quest items this mob drops that you still need
function tips.MobItemLines(unitName, npcId)
    local lines = {}
    for _, n in ipairs(tips.NeededItems()) do
        if n.itemId and not n.done and tips.MobDrops(n.itemId, unitName, npcId) then
            tinsert(lines, n)
        end
    end
    return lines
end

---------------------------------------------------------------------------
-- Mob lines
---------------------------------------------------------------------------

-- Kill objectives in your quest log that name this mob
function tips.KillLines(unitName)
    local lines = {}
    if not unitName then return lines end
    local lname = unitName:lower()
    for _, q in ipairs(tips.LogQuests()) do
        for _, o in ipairs(q.objectives) do
            if o.kind == "monster" then
                local oname = o.name:lower()
                if oname == lname or oname:find(lname, 1, true) then
                    tinsert(lines, {title = q.title, have = o.have, need = o.need, done = o.done})
                end
            end
        end
    end
    return lines
end

-- Kills and item drops together (kept for callers and tests)
function tips.QuestLines(unitName, npcId)
    local lines = tips.KillLines(unitName)
    for _, n in ipairs(tips.MobItemLines(unitName, npcId)) do
        tinsert(lines, {title = n.title, what = n.name, have = n.have, need = n.need,
                        done = n.done, later = n.later})
    end
    return lines
end

local function QuestNpcs(questId, field)
    local card = addon.card
    local info = card and card.QuestInfoOf and card.QuestInfoOf(questId)
    local by = info and info.q and info.q[field]
    return by and by[1]
end

local ROLE = {accept = "Pick up", turnin = "Turn in", complete = "Kill", mobs = "Kill",
              targets = "Talk to", unitscan = "Find"}

-- First guide step (from the current one on) that needs this NPC
function tips.GuideStep(unitName, npcId)
    local guide = addon.currentGuide
    if not (guide and guide.steps and addon.GetGuideProgress) then return end
    local cur = addon.GetGuideProgress() or 1
    for i = cur, math.min(#guide.steps, cur + LOOKAHEAD) do
        local step = guide.steps[i]
        if step and not step.completed and not step.hidewindow then
            for _, e in ipairs(step.elements or {}) do
                local role
                if e.mobs and InList(e.mobs, unitName, npcId) then
                    role = "mobs"
                elseif e.targets and InList(e.targets, unitName, npcId) then
                    role = "targets"
                elseif e.unitscan and InList(e.unitscan, unitName, npcId) then
                    role = "unitscan"
                elseif npcId and (e.tag == "accept" or e.tag == "turnin") and e.questId then
                    local npcs = QuestNpcs(tonumber(e.questId), e.tag == "accept" and "startedBy" or "finishedBy")
                    if npcs and InList(npcs, nil, npcId) then role = e.tag end
                end
                if role then
                    local what = ROLE[role]
                    if (role == "accept" or role == "turnin") and e.title then
                        what = what .. ": " .. Strip(e.title)
                    end
                    return i, what
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

function tips.AddLines(tooltip, unit)
    if not tips.Enabled() or not unit or not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    local npcId = tips.NpcIdOf(UnitGUID(unit))
    local added = false

    if UnitCanAttack("player", unit) then
        -- Loot you still need: always shown, Questie doesn't cover items
        -- for quests you haven't picked up yet
        local loot = tips.MobItemLines(name, npcId)
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
        if not tips.QuestieShowsMobLines() then
            for _, q in ipairs(tips.KillLines(name)) do
                if not added then tooltip:AddLine(" "); added = true end
                tooltip:AddDoubleLine((q.done and GREY or GOLD) .. q.title .. "|r",
                                      Progress(q.have, q.need, q.done))
            end
        end
    end

    local index, what = tips.GuideStep(name, npcId)
    if index then
        if not added then tooltip:AddLine(" ") end
        tooltip:AddLine(GREEN .. "OpenXP|r " .. fmt(L("step %d"), index) .. GREY .. " - " .. what .. "|r")
        added = true
    end
    if added then tooltip:Show() end
end

---------------------------------------------------------------------------
-- Item lines: "keep this, a quest needs it"
---------------------------------------------------------------------------

-- {title, have, need, done, later = step} for each quest that wants this item
function tips.ItemLines(itemId, itemName)
    local lines = {}
    if not itemId then return lines end
    itemName = itemName or ItemName(itemId)
    for _, n in ipairs(tips.NeededItems()) do
        if n.itemId == itemId or (not n.itemId and SameName(n.name, itemName)) then
            tinsert(lines, n)
        end
    end
    return lines
end

function tips.IsNeeded(itemId)
    if not (itemId and tips.Enabled()) then return false end
    for _, n in ipairs(tips.NeededItems()) do
        if n.itemId == itemId then return true end
    end
    return false
end

function tips.AddItemLines(tooltip, itemId, itemName)
    if not tips.Enabled() or not itemId then return end
    local lines = tips.ItemLines(itemId, itemName)
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(Icon(QUEST_ICON, 20) .. ORANGE .. L("QUEST ITEM - DON'T SELL") .. "|r")
    for _, q in ipairs(lines) do
        local left = (q.done and GREY or GOLD) .. q.title .. "|r"
        if q.later then left = left .. GREY .. " " .. fmt(L("(pick up at step %d)"), q.later) .. "|r" end
        tooltip:AddDoubleLine(left, Progress(q.have, q.need, q.done))
    end
    -- gold border so it stands out
    tips.SetBorder(tooltip, 1, 0.55, 0.1)
    tooltip.openxpBorder = true
    tooltip:Show()
end

function tips.SetBorder(tooltip, r, g, b)
    local ns = tooltip.NineSlice
    if ns and ns.SetBorderColor then
        pcall(ns.SetBorderColor, ns, r, g, b)
    elseif tooltip.SetBackdropBorderColor then
        pcall(tooltip.SetBackdropBorderColor, tooltip, r, g, b)
    end
end

local function ResetBorder(tooltip)
    if tooltip.openxpBorder then
        tooltip.openxpBorder = nil
        local c = _G.TOOLTIP_DEFAULT_COLOR
        tips.SetBorder(tooltip, c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end
end

local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    unit = unit or (UnitExists("mouseover") and "mouseover")
    ResetBorder(tooltip)
    pcall(tips.AddLines, tooltip, unit)
end

local function OnItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip then return end
    local itemId = type(data) == "table" and data.id or nil
    local name, link = tooltip:GetItem()
    if not itemId and link then itemId = tonumber(link:match("item:(%d+)")) end
    ResetBorder(tooltip) -- moving between bag slots reuses the tooltip without hiding it
    pcall(tips.AddItemLines, tooltip, itemId, name)
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
for _, tt in ipairs({GameTooltip, _G.ItemRefTooltip}) do
    if tt and tt.HookScript then tt:HookScript("OnHide", ResetBorder) end
end

---------------------------------------------------------------------------
-- Bag slots: a quest marker on items you need (uses the bag hooks the
-- inventory manager already has for its junk icons)
---------------------------------------------------------------------------

function tips.MarkBagButton(button, bag, slot)
    if not button then return end
    local id = GetContainerItemID and bag and slot and GetContainerItemID(bag, slot)
    local need = tips.IsNeeded(id)
    if need and not button.openxpQuestMark then
        local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSize(18, 18)
        t:SetPoint("TOPLEFT", -2, 2)
        t:SetTexture(QUEST_ICON)
        button.openxpQuestMark = t
    end
    if button.openxpQuestMark then button.openxpQuestMark:SetShown(need) end
end

local im = addon.inventoryManager
if im and im.UpdateBagButton then
    local orig = im.UpdateBagButton
    im.UpdateBagButton = function(self, button, bag, slot, ...)
        local r = orig(self, button, bag, slot, ...)
        pcall(tips.MarkBagButton, button, bag, slot)
        return r
    end
end

local function RefreshBags()
    local bm = im and im.bagManager
    if bm and bm.UpdateAllBags and im.IsFeatureEnabled and im:IsFeatureEnabled() then
        pcall(bm.UpdateAllBags, bm)
    end
end

---------------------------------------------------------------------------
-- Nameplates: the needed item's icon and your count beside enemies that
-- drop it. Sits on the right so it doesn't cover Questie's icon on the left.
---------------------------------------------------------------------------

local plates = {}

function tips.PlateInfo(unit)
    if not (unit and UnitExists(unit)) or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
    local loot = tips.MobItemLines(UnitName(unit), tips.NpcIdOf(UnitGUID(unit)))
    return loot[1], #loot
end

local function PlateFrame(plate)
    local f = plates[plate]
    if f then return f end
    f = CreateFrame("Frame", nil, plate)
    f:SetSize(22, 22)
    f:SetPoint("LEFT", plate, "RIGHT", -6, 0)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.mark = f:CreateTexture(nil, "OVERLAY")
    f.mark:SetSize(12, 12)
    f.mark:SetPoint("TOPLEFT", -4, 4)
    f.mark:SetTexture(QUEST_ICON)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("LEFT", f, "RIGHT", 2, 0)
    plates[plate] = f
    return f
end

function tips.UpdatePlate(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local n, count
    if tips.NameplatesEnabled() then n, count = tips.PlateInfo(unit) end
    if not n then
        if plates[plate] then plates[plate]:Hide() end
        return
    end
    local f = PlateFrame(plate)
    f.icon:SetTexture(GetItemIcon and GetItemIcon(n.itemId) or QUEST_ICON)
    f.text:SetText(n.have .. "/" .. n.need .. (count > 1 and " +" or ""))
    f:Show()
end

local function RefreshPlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then pcall(tips.UpdatePlate, unit) end
    end
end
tips.RefreshPlates = RefreshPlates

local pending
local function RefreshSoon()
    tips.Invalidate()
    if pending then return end
    pending = true
    local after = C_Timer and C_Timer.After or function(_, fn) fn() end
    after(0.3, function()
        pending = false
        RefreshPlates()
        RefreshBags()
    end)
end

local events = CreateFrame("Frame")
for _, ev in ipairs({"QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "NAME_PLATE_UNIT_ADDED",
                     "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD"}) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        pcall(tips.UpdatePlate, unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
        if plate and plates[plate] then plates[plate]:Hide() end
    else
        RefreshSoon()
    end
end)

---------------------------------------------------------------------------
-- Extras: auto loot and max camera distance (both off unless you turn them on)
---------------------------------------------------------------------------

local extras = {}
addon.openxpExtras = extras

local function CVarDefault(name, fallback)
    local ok, v = pcall(GetCVarDefault or function() end, name)
    return ok and v or fallback
end

function extras.Apply(login)
    local p = Profile()
    if not (p and SetCVar) then return end
    if p.openxpAutoLoot then
        SetCVar("autoLootDefault", "1")
    elseif not login then
        SetCVar("autoLootDefault", CVarDefault("autoLootDefault", "0"))
    end
    if p.openxpMaxCamera then
        SetCVar("cameraDistanceMaxZoomFactor", "2.6")
    elseif not login then
        SetCVar("cameraDistanceMaxZoomFactor", CVarDefault("cameraDistanceMaxZoomFactor", "1.9"))
    end
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    pcall(extras.Apply, true)
end)
