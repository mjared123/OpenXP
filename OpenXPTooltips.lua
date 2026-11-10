-- OpenXP tooltips
--   Items: which of your quests need them, with your count, so you don't sell
--          them. Also items the current guide says to save for a later quest.
--   Mobs:  which of your quests they count for (kills and item drops), with
--          your progress.
--   NPCs:  which guide step needs them (pick up, turn in, talk to, kill).
-- Questie already adds quest lines to mob tooltips, so while its tooltips are
-- on we only add the guide step line to mobs and leave the quest lines to it.
-- Questie's database is only read while the game runs, never copied.

local _, addon = ...
local L = addon.locale.Get
local fmt = string.format

local tips = {}
addon.openxpTooltips = tips

local LOOKAHEAD = 40 -- guide steps checked past the current one
local GREEN, GREY, GOLD, WHITE = "|cFF66BB6A", "|cFF9E9E9E", "|cFFFFC107", "|cFFFFFFFF"
local GetItemCount = C_Item and C_Item.GetItemCount or _G.GetItemCount
local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
local IsTurnedIn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or _G.IsQuestFlaggedCompleted

local function Profile()
    return addon.settings and addon.settings.profile
end

function tips.Enabled()
    local p = Profile()
    return not (p and p.openxpTooltips == false)
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

-- Does this mob drop the item? Questie's drop list, or a guide step that
-- collects it from this mob
local function MobDrops(itemId, unitName, npcId)
    local item = QGet("Item", itemId)
    if item and npcId and type(item.npcDrops) == "table" then
        for _, id in ipairs(item.npcDrops) do
            if id == npcId then return true end
        end
    end
    for _, c in ipairs(tips.CollectIndex()[itemId] or {}) do
        if InList(c.mobs, unitName, npcId) then return true end
    end
end

---------------------------------------------------------------------------
-- Mob lines
---------------------------------------------------------------------------

-- Quest log objectives this mob counts for: kills that name it, and items it drops
function tips.QuestLines(unitName, npcId)
    local lines = {}
    if not unitName then return lines end
    local lname = unitName:lower()
    for _, q in ipairs(tips.LogQuests()) do
        local itemIds
        for _, o in ipairs(q.objectives) do
            local hit
            if o.kind == "monster" then
                local oname = o.name:lower()
                hit = oname == lname or oname:find(lname, 1, true)
            elseif o.kind == "item" then
                itemIds = itemIds or QuestItemIds(q.id)
                for itemId in pairs(itemIds) do
                    if SameName(ItemName(itemId), o.name) and MobDrops(itemId, unitName, npcId) then
                        hit = true
                        break
                    end
                end
            end
            if hit then
                tinsert(lines, {title = q.title, what = o.kind == "item" and o.name or nil,
                                have = o.have, need = o.need, done = o.done})
            end
        end
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

function tips.AddLines(tooltip, unit)
    if not tips.Enabled() or not unit or not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    local npcId = tips.NpcIdOf(UnitGUID(unit))
    local added = false

    if not tips.QuestieShowsMobLines() and UnitCanAttack("player", unit) then
        for _, q in ipairs(tips.QuestLines(name, npcId)) do
            if not added then tooltip:AddLine(" "); added = true end
            local left = (q.done and GREY or GOLD) .. q.title .. "|r"
            if q.what then left = left .. GREY .. " - " .. q.what .. "|r" end
            tooltip:AddDoubleLine(left, Progress(q.have, q.need, q.done))
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
    local lines, seen = {}, {}
    if not itemId then return lines end
    itemName = itemName or ItemName(itemId)

    -- Quests you have: their item objectives
    for _, q in ipairs(tips.LogQuests()) do
        for _, o in ipairs(q.objectives) do
            if o.kind == "item" and SameName(o.name, itemName) then
                tinsert(lines, {title = q.title, have = o.have, need = o.need, done = o.done})
            end
        end
        -- a quest you already have is covered by its own objectives
        if q.id then seen[q.id] = true end
    end

    -- Quests further on in the guide that you haven't picked up yet
    local cur = addon.GetGuideProgress and addon.GetGuideProgress() or 1
    local have = GetItemCount and GetItemCount(itemId, true) or 0
    local guide = addon.currentGuide
    for _, c in ipairs(tips.CollectIndex()[itemId] or {}) do
        local qid = c.questId
        local step = guide and guide.steps and guide.steps[c.step]
        if c.step >= cur and not (step and step.completed) and not (qid and seen[qid])
                and not (qid and IsTurnedIn and IsTurnedIn(qid)) then
            if qid then seen[qid] = true end
            tinsert(lines, {title = qid and QuestName(qid) or L("Later in the guide"),
                            have = have, need = c.qty, later = c.step})
        end
    end
    return lines
end

function tips.AddItemLines(tooltip, itemId, itemName)
    if not tips.Enabled() or not itemId then return end
    local lines = tips.ItemLines(itemId, itemName)
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(GREEN .. "OpenXP|r " .. GOLD .. L("Quest item, don't sell") .. "|r")
    for _, q in ipairs(lines) do
        local left = (q.done and GREY or GOLD) .. q.title .. "|r"
        if q.later then left = left .. GREY .. " " .. fmt(L("(step %d)"), q.later) .. "|r" end
        tooltip:AddDoubleLine(left, Progress(q.have, q.need, q.done))
    end
    tooltip:Show()
end

local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    unit = unit or (UnitExists("mouseover") and "mouseover")
    pcall(tips.AddLines, tooltip, unit)
end

local function OnItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip then return end
    local itemId = type(data) == "table" and data.id or nil
    local name, link = tooltip:GetItem()
    if not itemId and link then itemId = tonumber(link:match("item:(%d+)")) end
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
