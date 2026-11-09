-- OpenXP tooltips
--   Mobs: which of your quests they count for, with your progress.
--   NPCs: which guide step needs them (pick up, turn in, talk to, kill).
-- Questie already adds quest lines to mob tooltips, so when it's loaded we
-- only add the guide step line and leave the quest lines to Questie.

local _, addon = ...
local L = addon.locale.Get
local fmt = string.format

local tips = {}
addon.openxpTooltips = tips

local LOOKAHEAD = 40 -- guide steps checked past the current one
local GREEN, GREY, GOLD = "|cFF66BB6A", "|cFF9E9E9E", "|cFFFFC107"

local function Profile()
    return addon.settings and addon.settings.profile
end

function tips.Enabled()
    local p = Profile()
    return not (p and p.openxpTooltips == false)
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

-- Quest log objectives that name this mob ("Kobold Vermin slain: 3/8")
function tips.QuestLines(unitName)
    local lines = {}
    if not (unitName and GetNumQuestLogEntries and GetQuestLogLeaderBoard) then return lines end
    local lname = unitName:lower()
    local n = GetNumQuestLogEntries()
    for i = 1, n do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if title and not isHeader then
            for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
                local text, kind, finished = GetQuestLogLeaderBoard(j, i)
                if text and kind == "monster" then
                    local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
                    name = name and name:gsub("%s+slain$", "")
                    if name and (name:lower() == lname or name:lower():find(lname, 1, true)) then
                        tinsert(lines, {title = title, have = tonumber(have), need = tonumber(need),
                                        done = finished})
                    end
                end
            end
        end
    end
    return lines
end

local function InList(list, name, npcId)
    if not list then return end
    local lname = name and name:lower()
    for _, v in ipairs(list) do
        if npcId and tonumber(v) == npcId then return true end
        if lname and type(v) == "string" and v:lower() == lname then return true end
    end
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

function tips.AddLines(tooltip, unit)
    if not tips.Enabled() or not unit or not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    local npcId = tips.NpcIdOf(UnitGUID(unit))
    local added = false

    local questieLoaded = _G.QuestieLoader ~= nil
    if not questieLoaded and UnitCanAttack("player", unit) then
        for _, q in ipairs(tips.QuestLines(name)) do
            if not added then tooltip:AddLine(" "); added = true end
            local color = q.done and GREY or GOLD
            tooltip:AddDoubleLine(color .. q.title .. "|r",
                                  (q.done and GREEN or "|cFFFFFFFF") .. q.have .. "/" .. q.need .. "|r")
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

local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    unit = unit or (UnitExists("mouseover") and "mouseover")
    pcall(tips.AddLines, tooltip, unit)
end

if _G.TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    _G.TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
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
