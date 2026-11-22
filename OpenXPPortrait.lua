-- 3D creature/NPC portraits for OpenXP steps and Quest Targets, plus a pooled
-- full-body 3D + description preview on hover.

local _, addon = ...
local L = addon.locale and addon.locale.Get or function(s) return s end
local fmt, tinsert, tremove = string.format, table.insert, table.remove

local portrait = { size = 34 }
addon.portrait = portrait

local WHITE = "Interface/Buttons/WHITE8X8"
local DEFAULT_FONT = (addon.SafeFont and addon.SafeFont("Fonts\\ARIALN.TTF") or "Fonts\\ARIALN.TTF")
local CARD_BACKDROP = {
    bgFile = WHITE,
    edgeFile = WHITE,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local MODEL_TIMEOUT = 0.8
local INDEX_CHUNK = 400
local MAX_INDEX_RETRIES = 15
local DESC_CACHE_MAX = 500

local TONES = {
    hostile  = { 1, 112 / 255, 67 / 255, 0.85 },
    friendly = { 61 / 255, 187 / 255, 122 / 255, 0.85 },
    target   = { 90 / 255, 184 / 255, 1, 1 },
    rare     = { 179 / 255, 157 / 255, 219 / 255, 0.95 },
    neutral  = { 150 / 255, 160 / 255, 180 / 255, 0.45 },
}

local RANK_LABELS = {
    [1] = L("Elite"),
    [2] = L("Rare Elite"),
    [3] = L("Boss"),
    [4] = L("Rare"),
}

local function Revealed(value)
    if addon.IsSecretValue and addon.IsSecretValue(value) then return nil end
    return value
end

local function StripCodes(text)
    if type(text) ~= "string" then return "" end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
end

local function CleanText(name)
    if type(name) ~= "string" then return nil end
    local clean = StripCodes(name):gsub("^[%+%*]%s*", ""):match("^%s*(.-)%s*$")
    return clean ~= "" and clean or nil
end

local function StripName(name)
    local clean = CleanText(name)
    if not clean then return nil end
    local beforeId, inlineId = clean:match("^(.-)::(%d+)$")
    if beforeId and inlineId then
        return CleanText(beforeId), tonumber(inlineId)
    end
    local npcTagName, npcTagId = clean:match("^npc:(.-):(%d+)$")
    if npcTagName and npcTagId then
        return CleanText(npcTagName), tonumber(npcTagId)
    end
    local asNum = tonumber(clean)
    if asNum then return nil, asNum end
    return clean, nil
end

local function FontPath()
    if addon.fonts and addon.fonts.Path then
        local ok, path = pcall(addon.fonts.Path)
        if ok and path then return path end
    end
    return DEFAULT_FONT
end

local function SetFont(fs, size, flags)
    local ok, res = pcall(fs.SetFont, fs, FontPath(), size, flags or "")
    if not ok or res == false then
        pcall(fs.SetFont, fs, DEFAULT_FONT, size, flags or "")
    end
end

local function ApplyCardBox(frame, bgAlpha, borderAlpha)
    if not (frame and frame.SetBackdrop) then return end
    frame:SetBackdrop(CARD_BACKDROP)
    frame:SetBackdropColor(16 / 255, 17 / 255, 21 / 255, bgAlpha or 0.95)
    frame:SetBackdropBorderColor(150 / 255, 160 / 255, 180 / 255, borderAlpha or 0.45)
end

---------------------------------------------------------------------------
-- 3D model loading & camera framing (shared by portraits and hover preview)
---------------------------------------------------------------------------

local function ModelLoaded(model)
    if not model then return false end
    if not model.GetModelFileID then return true end
    local ok, file = pcall(model.GetModelFileID, model)
    return ok and type(file) == "number" and file > 0
end

local function FrameCamera(model, fullBody)
    if not model then return end
    if model.SetCamera then pcall(model.SetCamera, model, 0) end
    if fullBody then
        if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
        if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1.08) end
        if model.ClearTransform then pcall(model.ClearTransform, model) end
        if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
        if model.SetFacing then pcall(model.SetFacing, model, 0.32) end
    else
        if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0.82) end
        if model.SetFacing then pcall(model.SetFacing, model, 0.28) end
    end
end

local function LoadCreatureModel(owner, model, npcId, unit, fullBody, onReady, onMiss)
    local canCreature = npcId and npcId > 0 and model and model.SetCreature
    local canUnit = (not canCreature) and unit and _G.UnitExists and _G.UnitExists(unit) and model and model.SetUnit
    if not (canCreature or canUnit) then
        if model then model:Hide() end
        if onMiss then onMiss() end
        return false
    end

    local attempt = {}
    owner.attempt = attempt
    model:Show()
    if model.ClearModel then model:ClearModel() end
    if canCreature then
        model:SetCreature(npcId)
    else
        model:SetUnit(unit)
    end
    FrameCamera(model, fullBody)

    if ModelLoaded(model) and model.GetModelFileID then
        if onReady then onReady() end
        return true
    end
    if onMiss then onMiss(true) end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(MODEL_TIMEOUT, function()
            if owner.attempt == attempt and not ModelLoaded(model) then
                model:Hide()
                if onMiss then onMiss(false) end
            end
        end)
    end
    return false
end

---------------------------------------------------------------------------
-- NPC ID resolution (explicit guide IDs -> live units -> QuestieDB)
---------------------------------------------------------------------------

local explicitIds = {}    -- lower(name) -> npcId
local questieIndex = {}   -- lower(name) -> npcId
local missCache = {}      -- lower(name) -> true once indexState == "done"
local indexState = "idle" -- "idle" | "building" | "done"
local indexCursor
local indexRetries = 0
local indexCallbacks = {}

local cachedQuestieDB, cachedZoneDB
local function GetQuestieDB()
    if not cachedQuestieDB then
        local loader = _G.QuestieLoader
        if loader and loader.ImportModule then
            local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
            if ok and db and type(db.GetQuest) == "function" then cachedQuestieDB = db end
            local okZ, z = pcall(loader.ImportModule, loader, "ZoneDB")
            if okZ and z then cachedZoneDB = z end
        end
    end
    return cachedQuestieDB, cachedZoneDB
end

local function DBGet(kind, id)
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    if addon.card and addon.card.QGet then
        local obj = addon.card.QGet(kind, id)
        if type(obj) == "table" then return obj end
    end
    local db = GetQuestieDB()
    local fn = db and db["Get" .. kind]
    if type(fn) ~= "function" then return nil end
    local ok, obj
    if kind == "NPC" then
        ok, obj = pcall(fn, db, id)
        if ok and type(obj) == "table" then return obj end
    end
    ok, obj = pcall(fn, id)
    if ok and type(obj) == "table" then return obj end
    ok, obj = pcall(fn, db, id)
    if ok and type(obj) == "table" then return obj end
end

function portrait.NpcIdOfGuid(guid)
    guid = Revealed(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

function portrait.RememberNpc(name, npcId)
    name = CleanText(Revealed(name))
    npcId = tonumber(npcId)
    if not name or not npcId or npcId <= 0 then return end
    local key = name:lower()
    explicitIds[key] = npcId
    missCache[key] = nil
end

function portrait.RememberUnit(unit, expectedName)
    if not (unit and _G.UnitGUID) then return nil end
    local npcId = portrait.NpcIdOfGuid(_G.UnitGUID(unit))
    if not npcId then return nil end
    local name = (_G.UnitName and Revealed(_G.UnitName(unit))) or expectedName
    if name and name ~= "" then portrait.RememberNpc(name, npcId) end
    return npcId
end

local function QuestNpcCandidates(q)
    local out = {}
    if type(q) ~= "table" then return out end
    if type(q.startedBy) == "table" and type(q.startedBy[1]) == "table" then
        for _, id in ipairs(q.startedBy[1]) do tinsert(out, id) end
    end
    if type(q.finishedBy) == "table" and type(q.finishedBy[1]) == "table" then
        for _, id in ipairs(q.finishedBy[1]) do tinsert(out, id) end
    end
    local obj = q.objectives
    if type(obj) == "table" then
        for _, e in ipairs(type(obj[1]) == "table" and obj[1] or {}) do
            if type(e) == "table" and e[1] then tinsert(out, e[1]) end
        end
        for _, e in ipairs(type(obj[3]) == "table" and obj[3] or {}) do
            local item = type(e) == "table" and e[1] and DBGet("Item", e[1])
            for _, id in ipairs(item and type(item.npcDrops) == "table" and item.npcDrops or {}) do
                tinsert(out, id)
            end
        end
    end
    return out
end

local function NpcNameFromDB(db, id)
    if not (db and id) then return nil end
    if type(db.QueryNPCSingle) == "function" then
        local ok, n = pcall(db.QueryNPCSingle, id, "name")
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    local npc = DBGet("NPC", id)
    return npc and type(npc.name) == "string" and npc.name or nil
end

local function NpcHasSpawns(db, id)
    if not (db and id and type(db.QueryNPCSingle) == "function") then return false end
    local ok, sp = pcall(db.QueryNPCSingle, id, "spawns")
    return ok and type(sp) == "table" and next(sp) ~= nil
end

local function FinishIndex()
    indexState = "done"
    missCache = {}
    local cbs = indexCallbacks
    indexCallbacks = {}
    for _, cb in ipairs(cbs) do pcall(cb) end
end

local function StepIndex()
    local db = GetQuestieDB()
    local ptrs = db and db.NPCPointers
    if not (ptrs and type(db.QueryNPCSingle) == "function") then
        indexState = "idle"
        return
    end
    local count = 0
    while count < INDEX_CHUNK do
        local id = next(ptrs, indexCursor)
        indexCursor = id
        if not id then
            FinishIndex()
            return
        end
        local ok, name = pcall(db.QueryNPCSingle, id, "name")
        if ok and type(name) == "string" and name ~= "" and name:sub(1, 5) ~= "[DND]" then
            local key = name:lower()
            local existing = questieIndex[key]
            if not existing or (not NpcHasSpawns(db, existing) and NpcHasSpawns(db, id)) then
                questieIndex[key] = id
            end
        end
        count = count + 1
    end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, StepIndex)
    else
        StepIndex()
    end
end

function portrait.OnIndexReady(cb)
    if type(cb) ~= "function" then return end
    if indexState == "done" then pcall(cb); return end
    tinsert(indexCallbacks, cb)
end

local function EnsureNameIndex()
    if indexState ~= "idle" then return end
    local db = GetQuestieDB()
    if not (db and db.NPCPointers and next(db.NPCPointers) ~= nil) then
        if _G.QuestieLoader and _G.C_Timer and _G.C_Timer.After and indexRetries < MAX_INDEX_RETRIES then
            indexRetries = indexRetries + 1
            _G.C_Timer.After(1.0, EnsureNameIndex)
        end
        return
    end
    indexState = "building"
    indexCursor = nil
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, StepIndex)
    else
        StepIndex()
    end
end

function portrait.ResolveNpcId(name, steps)
    local clean, inlineId = StripName(name)
    if inlineId and inlineId > 0 then
        if clean then portrait.RememberNpc(clean, inlineId) end
        return inlineId
    end
    if not clean then return nil end

    local lname = clean:lower()
    if explicitIds[lname] then return explicitIds[lname] end
    if questieIndex[lname] then return questieIndex[lname] end
    if indexState == "done" and missCache[lname] then return nil end

    local db = GetQuestieDB()
    if db and steps then
        for _, step in ipairs(steps) do
            for _, e in ipairs(step and step.elements or {}) do
                local qid = tonumber(e.questId)
                local q = qid and qid > 0 and DBGet("Quest", qid)
                if q then
                    for _, nid in ipairs(QuestNpcCandidates(q)) do
                        local n = NpcNameFromDB(db, nid)
                        if n and n:lower() == lname then
                            explicitIds[lname] = nid
                            missCache[lname] = nil
                            return nid
                        end
                    end
                end
            end
        end
    end

    if indexState == "done" then
        missCache[lname] = true
    else
        EnsureNameIndex()
    end
    return nil
end

local function FirstQuestNpc(questId, mode)
    local q = DBGet("Quest", questId)
    if not q then return nil end
    if mode == "accept" then
        return type(q.startedBy) == "table" and type(q.startedBy[1]) == "table" and q.startedBy[1][1] or nil
    elseif mode == "turnin" then
        return type(q.finishedBy) == "table" and type(q.finishedBy[1]) == "table" and q.finishedBy[1][1] or nil
    elseif mode == "complete" and type(q.objectives) == "table" then
        if type(q.objectives[1]) == "table" and type(q.objectives[1][1]) == "table" then
            return q.objectives[1][1][1]
        end
        if type(q.objectives[3]) == "table" and type(q.objectives[3][1]) == "table" and q.objectives[3][1][1] then
            local item = DBGet("Item", q.objectives[3][1][1])
            return item and type(item.npcDrops) == "table" and item.npcDrops[1] or nil
        end
    end
end

local TAG_TONE = { accept = "friendly", turnin = "friendly", complete = "hostile" }

-- Returns { npcId = number, name = string?, tone = "friendly"|"hostile" } or nil
function portrait.StepTarget(step)
    if not step then return nil end
    if step.portraitNpcId then
        return { npcId = step.portraitNpcId, tone = step.portraitTone or "friendly" }
    end
    local steps = { step }
    local elements = step.elements or {}

    local function firstResolved(list, tone)
        if type(list) ~= "table" then return nil end
        for _, raw in ipairs(list) do
            local name = addon.GetCreatureName and addon.GetCreatureName(raw) or raw
            local id = portrait.ResolveNpcId(name, steps) or portrait.ResolveNpcId(raw, steps)
            if id then return { npcId = id, name = StripName(name), tone = tone } end
        end
    end

    local function questElementTarget(e)
        local qid = tonumber(e.questId)
        local tone = TAG_TONE[e.tag]
        local id = qid and qid > 0 and tone and FirstQuestNpc(qid, e.tag)
        if id then return { npcId = id, tone = tone } end
    end

    for _, e in ipairs(elements) do
        if not e.completed and not e.skip then
            local res = firstResolved(e.mobs, "hostile") or firstResolved(e.unitscan, "hostile")
            if res then return res end
        end
    end
    for _, e in ipairs(elements) do
        if not e.completed and not e.skip then
            local res = firstResolved(e.targets, "friendly") or questElementTarget(e)
            if res then return res end
        end
    end
    -- Fallback pass including completed elements so finished steps keep their portrait
    for _, e in ipairs(elements) do
        local res = firstResolved(e.mobs, "hostile")
            or firstResolved(e.unitscan, "hostile")
            or firstResolved(e.targets, "friendly")
            or questElementTarget(e)
        if res then return res end
    end
end

---------------------------------------------------------------------------
-- 3D portrait widget
---------------------------------------------------------------------------

function portrait.SetTone(p, tone)
    if not (p and p.SetBackdropBorderColor) then return end
    local c = type(tone) == "table" and tone or TONES[tone] or TONES.neutral
    p:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
end

function portrait.Create(parent, size)
    local dim = size or portrait.size
    local tpl = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local p = _G.CreateFrame("Frame", nil, parent, tpl)
    p:SetSize(dim, dim)
    p:EnableMouse(false)
    ApplyCardBox(p, 0.95, 0.45)
    portrait.SetTone(p, "neutral")

    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("TOPLEFT", 2, -2)
    p.icon:SetPoint("BOTTOMRIGHT", -2, 2)

    p.model = _G.CreateFrame("PlayerModel", nil, p)
    p.model:SetPoint("TOPLEFT", 1, -1)
    p.model:SetPoint("BOTTOMRIGHT", -1, 1)
    p.model:SetScript("OnModelLoaded", function(self)
        FrameCamera(self, false)
        if ModelLoaded(self) then
            p.modelLoaded = true
            p.icon:Hide()
            if p.onLoaded then p.onLoaded(p) end
        end
    end)

    -- WoW Forever resets PlayerModel camera/scene when a parent hides during refresh.
    p:SetScript("OnHide", function(self)
        self.needsReload = true
        self.attempt = nil
    end)
    p:SetScript("OnShow", function(self)
        if self.needsReload and self.lastOpts then
            portrait.Render(self, self.lastOpts)
        end
    end)

    p.nearbyDot = p:CreateTexture(nil, "OVERLAY")
    p.nearbyDot:SetSize(7, 7)
    p.nearbyDot:SetPoint("BOTTOMRIGHT", -2, 2)
    p.nearbyDot:SetColorTexture(0.30, 0.92, 0.44, 1)
    p.nearbyDot:Hide()

    return p
end

local function PaintFallback(tex, unit, fallbackTexture)
    if unit and _G.SetPortraitTexture then
        local ok = pcall(_G.SetPortraitTexture, tex, unit)
        if ok then
            tex:SetTexCoord(0, 1, 0, 1)
            tex:Show()
            return
        end
    end
    if fallbackTexture then
        tex:SetTexture(fallbackTexture)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:Show()
    else
        tex:SetTexture(nil)
        tex:Hide()
    end
end

function portrait.Render(p, opts)
    if not p then return end
    opts = opts or {}
    p.lastOpts = opts

    if p.nearbyDot then p.nearbyDot:SetShown(opts.nearby and true or false) end
    portrait.SetTone(p, opts.tone or "neutral")
    p.onLoaded = opts.onLoaded
    p.onFallback = opts.onFallback

    local npcId = tonumber(opts.npcId)
    local unit = opts.unit
    local fallbackTexture = opts.fallbackTexture

    local key
    if npcId and npcId > 0 then
        key = "npc:" .. npcId
    elseif unit then
        local guid = _G.UnitGUID and Revealed(_G.UnitGUID(unit))
        key = "unit:" .. tostring(guid or unit)
    else
        key = "tex:" .. tostring(fallbackTexture or "")
    end

    -- Defer 3D SetCreature while hidden so Forever's PlayerModel loads once visible.
    if p.IsVisible and not p:IsVisible() then
        p.renderKey = key
        p.needsReload = true
        p.modelLoaded = false
        if p.model then p.model:Hide() end
        if opts.hideFallbackIcon then p.icon:Hide() else PaintFallback(p.icon, unit, fallbackTexture) end
        if opts.onFallback then opts.onFallback(p) end
        return
    end

    if p.renderKey == key and not p.needsReload then
        if p.modelLoaded then
            p.icon:Hide()
            if p.onLoaded then p.onLoaded(p) end
        elseif not (npcId and npcId > 0) and not unit then
            if opts.onFallback then opts.onFallback(p) end
        end
        return
    end

    p.renderKey = key
    p.needsReload = false
    p.modelLoaded = false

    local function showFallback(streaming)
        if opts.hideFallbackIcon then
            p.icon:Hide()
        elseif not streaming then
            PaintFallback(p.icon, unit, fallbackTexture)
        end
        if not streaming then p.modelLoaded = false end
        if opts.onFallback then opts.onFallback(p) end
    end

    if opts.hideFallbackIcon then p.icon:Hide() else PaintFallback(p.icon, unit, fallbackTexture) end

    LoadCreatureModel(p, p.model, npcId, unit, false,
        function()
            p.modelLoaded = true
            p.icon:Hide()
            if p.onLoaded then p.onLoaded(p) end
        end,
        showFallback)
end

---------------------------------------------------------------------------
-- Target description builder (cached QuestieDB metadata + active step role)
---------------------------------------------------------------------------

local staticDescCache = {}
local staticDescOrder = {}

local function CacheStaticDesc(npcId, value)
    if #staticDescOrder >= DESC_CACHE_MAX then
        local oldest = tremove(staticDescOrder, 1)
        staticDescCache[oldest] = nil
    end
    tinsert(staticDescOrder, npcId)
    staticDescCache[npcId] = value
end

local function ZoneNameOf(zoneID)
    if not zoneID then return nil end
    if _G.C_Map and _G.C_Map.GetAreaInfo then
        local ok, area = pcall(_G.C_Map.GetAreaInfo, zoneID)
        area = ok and Revealed(area) or nil
        if type(area) == "string" and area ~= "" then return area end
    end
    local _, zdb = GetQuestieDB()
    if zdb and zdb.GetUiMapIdByAreaId and _G.C_Map and _G.C_Map.GetMapInfo then
        local ok, uiMap = pcall(zdb.GetUiMapIdByAreaId, zdb, zoneID)
        local ok2, info = ok and uiMap and uiMap > 0 and pcall(_G.C_Map.GetMapInfo, uiMap)
        if ok2 and type(info) == "table" and type(info.name) == "string" then
            return info.name
        end
    end
end

local function FirstSpawnSpot(spawns, preferZone)
    if type(spawns) ~= "table" then return nil end
    local bestPts, bestZone, bestScore
    for zoneID, pts in pairs(spawns) do
        if type(pts) == "table" and #pts > 0 then
            local score = #pts + (zoneID == preferZone and 10000 or 0)
            if not bestScore or score > bestScore then
                bestZone, bestPts, bestScore = zoneID, pts, score
            end
        end
    end
    if not bestPts then return nil end
    local sx, sy, n = 0, 0, 0
    for _, pt in ipairs(bestPts) do
        if type(pt) == "table" and type(pt[1]) == "number" and pt[1] >= 0 and type(pt[2]) == "number" then
            sx, sy, n = sx + pt[1], sy + pt[2], n + 1
        end
    end
    if n > 0 then return bestZone, sx / n, sy / n end
end

local FLAG_NAMES = {
    { key = "FLIGHTMASTER", label = L("Flight Master") },
    { key = "INNKEEPER", label = L("Innkeeper") },
    { key = "REPAIR", label = L("Repair") },
    { key = "VENDOR", label = L("Vendor") },
    { key = "TRAINER", label = L("Trainer") },
    { key = "CLASS_TRAINER", label = L("Class Trainer") },
    { key = "PROFESSION_TRAINER", label = L("Profession Trainer") },
    { key = "BANKER", label = L("Banker") },
    { key = "AUCTIONEER", label = L("Auctioneer") },
    { key = "STABLEMASTER", label = L("Stable Master") },
}

local function DecodeNpcFlags(flags)
    if type(flags) ~= "number" or flags <= 0 or not _G.bit then return nil end
    local db = GetQuestieDB()
    local enum = db and db.npcFlags
    if type(enum) ~= "table" then return nil end
    local labels = {}
    for _, entry in ipairs(FLAG_NAMES) do
        local mask = enum[entry.key]
        if type(mask) == "number" and mask > 0 and _G.bit.band(flags, mask) ~= 0 then
            tinsert(labels, entry.label)
            if #labels >= 3 then break end
        end
    end
    if #labels > 0 then return table.concat(labels, " · ") end
end

local function StaticNpcInfo(npcId)
    if not npcId or npcId <= 0 then return nil end
    if staticDescCache[npcId] ~= nil then return staticDescCache[npcId] or nil end

    local npc = DBGet("NPC", npcId)
    if not npc then
        local db = GetQuestieDB()
        if db and db.NPCPointers then CacheStaticDesc(npcId, false) end
        return nil
    end

    local zoneID, sx, sy = FirstSpawnSpot(npc.spawns, npc.zoneID)
    local zoneName = ZoneNameOf(zoneID or npc.zoneID)
    local locationText
    if zoneName and sx and sy then
        locationText = fmt("%s (%.1f, %.1f)", zoneName, sx, sy)
    elseif zoneName then
        locationText = zoneName
    end

    local info = {
        name = type(npc.name) == "string" and npc.name ~= "" and npc.name or nil,
        subName = type(npc.subName) == "string" and npc.subName ~= "" and npc.subName or nil,
        minLevel = tonumber(npc.minLevel),
        maxLevel = tonumber(npc.maxLevel),
        rank = tonumber(npc.rank),
        services = DecodeNpcFlags(npc.npcFlags),
        location = locationText,
        startsCount = type(npc.questStarts) == "table" and #npc.questStarts or 0,
        endsCount = type(npc.questEnds) == "table" and #npc.questEnds or 0,
    }
    CacheStaticDesc(npcId, info)
    return info
end

local function DifficultyHex(level)
    if not level or level <= 0 then return "|cFF9EA3B3" end
    if _G.GetQuestDifficultyColor then
        local ok, c = pcall(_G.GetQuestDifficultyColor, level)
        if ok and type(c) == "table" and c.r then
            return fmt("|cFF%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
        end
    end
    local pLevel = _G.UnitLevel and Revealed(_G.UnitLevel("player"))
    if type(pLevel) ~= "number" then return "|cFFEBECEF" end
    local diff = level - pLevel
    if diff >= 5 then return "|cFFFF4040"
    elseif diff >= 3 then return "|cFFFF8040"
    elseif diff >= -2 then return "|cFFFFFF00"
    elseif diff >= -6 then return "|cFF40C040"
    else return "|cFF808080" end
end

local function MatchesElementName(list, targetLower)
    if type(list) ~= "table" then return false end
    for _, raw in ipairs(list) do
        local name = addon.GetCreatureName and addon.GetCreatureName(raw) or raw
        local clean = StripName(name)
        if clean and clean:lower() == targetLower then return true end
    end
    return false
end

local ROLE_PREFIX = {
    accept   = "|cFFF2C35C" .. L("Pick up:") .. "|r ",
    turnin   = "|cFF3DBB7A" .. L("Turn in:") .. "|r ",
    complete = "|cFFFF7043" .. L("Objective:") .. "|r ",
}
local ROLE_FALLBACK = {
    accept   = "|cFFF2C35C" .. L("Quest Giver") .. "|r",
    turnin   = "|cFF3DBB7A" .. L("Quest Turn-in") .. "|r",
    complete = "|cFFFF7043" .. L("Quest Objective") .. "|r",
}

local function CollectStepContext(targetName, npcId, stepOverride)
    local roles, seen = {}, {}
    local function push(line)
        if line and line ~= "" and not seen[line] then
            seen[line] = true
            tinsert(roles, line)
        end
    end
    local targetLower = targetName and targetName:lower() or nil
    local steps = stepOverride and { stepOverride } or (addon.RXPFrame and addon.RXPFrame.activeSteps) or {}

    for _, step in ipairs(steps) do
        for _, e in ipairs(step and step.elements or {}) do
            local matched = targetLower and (MatchesElementName(e.mobs, targetLower)
                or MatchesElementName(e.targets, targetLower)
                or MatchesElementName(e.unitscan, targetLower))
            if not matched and npcId and tonumber(e.questId) and (e.tag == "accept" or e.tag == "turnin") then
                local q = DBGet("Quest", e.questId)
                local list = q and ((e.tag == "accept" and q.startedBy and q.startedBy[1]) or (e.tag == "turnin" and q.finishedBy and q.finishedBy[1]))
                for _, id in ipairs(type(list) == "table" and list or {}) do
                    if id == npcId then matched = true; break end
                end
            end

            if matched then
                local qName = (e.title and e.title ~= "" and StripCodes(e.title))
                    or (tonumber(e.questId) and addon.GetQuestName and addon.GetQuestName(tonumber(e.questId)))
                if ROLE_PREFIX[e.tag] then
                    push(qName and (ROLE_PREFIX[e.tag] .. qName) or ROLE_FALLBACK[e.tag])
                elseif e.text and e.text ~= "" then
                    push("|cFF9EA3B3" .. L("Step:") .. "|r " .. StripCodes(e.text):gsub("\n.*", ""))
                end
            end
        end
    end

    local tt = addon.openxpTooltips
    if tt and targetName then
        if tt.KillLines then
            local ok, kills = pcall(tt.KillLines, targetName)
            for _, k in ipairs(ok and type(kills) == "table" and kills or {}) do
                local c = k.done and "|cFF3DBB7A" or "|cFFEBECEF"
                push(fmt("|cFFFF7043%s|r %s (%s%d/%d|r)", L("Kill:"), k.title or targetName, c, k.have or 0, k.need or 0))
            end
        end
        if tt.MobItemLines then
            local ok, items = pcall(tt.MobItemLines, targetName, npcId)
            for _, it in ipairs(ok and type(items) == "table" and items or {}) do
                local c = it.done and "|cFF3DBB7A" or "|cFFEBECEF"
                push(fmt("|cFF26C6DA%s|r %s (%s%d/%d|r) - %s", L("Drops:"), it.name or L("Item"), c, it.have or 0, it.need or 0, it.title or L("Quest")))
            end
        end
    end

    return roles
end

local CLASS_RANK = { elite = 1, rareelite = 2, worldboss = 3, rare = 4 }

function portrait.BuildDescription(opts)
    opts = opts or {}
    local npcId = tonumber(opts.npcId)
    local static = StaticNpcInfo(npcId)
    local name = StripName(opts.name) or (static and static.name) or (npcId and ("NPC #" .. npcId)) or L("Target")
    local unit, kind = opts.unit, opts.kind

    local minL = static and static.minLevel
    local maxL = static and static.maxLevel
    local rank = static and static.rank
    local creatureType

    if unit and _G.UnitExists and _G.UnitExists(unit) then
        local ul = _G.UnitLevel and Revealed(_G.UnitLevel(unit))
        if type(ul) == "number" and ul > 0 and not minL then minL, maxL = ul, ul end
        if _G.UnitClassification and not rank then
            rank = CLASS_RANK[Revealed(_G.UnitClassification(unit))]
        end
        if _G.UnitCreatureType then creatureType = Revealed(_G.UnitCreatureType(unit)) end
    end

    local meta = {}
    if static and static.subName then tinsert(meta, "|cFF5AB8FF<" .. static.subName .. ">|r") end
    local levelStr = (minL and minL > 0)
        and (DifficultyHex(maxL or minL) .. "Lv " .. ((maxL and maxL > minL) and (minL .. "-" .. maxL) or tostring(minL)) .. "|r")
    local rankLabel = (rank and RANK_LABELS[rank]) or (kind == "rare" and L("Rare")) or (kind == "unitscan" and L("Special"))
    if levelStr and rankLabel then
        tinsert(meta, levelStr .. " |cFFF2C35C" .. rankLabel .. "|r")
    elseif levelStr then
        tinsert(meta, levelStr)
    elseif rankLabel then
        tinsert(meta, "|cFFF2C35C" .. rankLabel .. "|r")
    end
    if creatureType and creatureType ~= "" then tinsert(meta, "|cFF9EA3B3" .. creatureType .. "|r") end

    local lines = {}
    if #meta > 0 then tinsert(lines, table.concat(meta, "  ")) end
    if static and static.services then tinsert(lines, "|cFF9EA3B3" .. static.services .. "|r") end

    local roles = CollectStepContext(name, npcId, opts.step)
    local shownRoles = math.min(#roles, 4)
    for i = 1, shownRoles do tinsert(lines, roles[i]) end
    if #roles > shownRoles then
        tinsert(lines, fmt("|cFF8A8E99" .. L("+ %d more objectives") .. "|r", #roles - shownRoles))
    elseif shownRoles == 0 then
        if opts.isEnemy then
            tinsert(lines, "|cFFFF7043" .. L("Hostile Quest Target") .. "|r")
        elseif kind == "friendly" then
            tinsert(lines, "|cFF3DBB7A" .. L("Friendly Quest NPC") .. "|r")
        end
        if static and (static.startsCount > 0 or static.endsCount > 0) then
            local qbits = {}
            if static.startsCount > 0 then tinsert(qbits, fmt(L("Starts %d"), static.startsCount)) end
            if static.endsCount > 0 then tinsert(qbits, fmt(L("Ends %d"), static.endsCount)) end
            tinsert(lines, "|cFF9EA3B3" .. L("Quests:") .. " " .. table.concat(qbits, " · ") .. "|r")
        end
    end

    if static and static.location then
        tinsert(lines, "|cFF9EA3B3" .. L("Location:") .. "|r " .. static.location)
    end

    local status = {
        opts.isCurrentTarget and ("|cFF5AB8FF" .. L("Current Target") .. "|r")
            or (opts.nearby and ("|cFF3DBB7A" .. L("Nearby") .. "|r") or ("|cFF8A8E99" .. L("Not in view") .. "|r"))
    }
    if opts.keybind and opts.keybind ~= "" then tinsert(status, "|cFFF2C35C[" .. opts.keybind .. "]|r") end
    tinsert(lines, table.concat(status, "  "))

    if opts.clickable ~= false then
        local hint = "|cFF8A8E99" .. L("Click to target") .. "|r"
        if opts.marking then hint = hint .. " |cFFF2C35C(" .. L("Marks Skull") .. ")|r" end
        tinsert(lines, hint)
    end

    return name, table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Pooled full-body 3D hover preview
---------------------------------------------------------------------------

local previewFrame
local PREVIEW_W, MODEL_H, PREVIEW_PAD = 244, 200, 10

local function EnsurePreviewFrame()
    if previewFrame then return previewFrame end
    local tpl = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local pf = _G.CreateFrame("Frame", "OpenXPTargetPreview", _G.UIParent, tpl)
    pf:SetWidth(PREVIEW_W)
    pf:SetHeight(MODEL_H + 80)
    pf:SetFrameStrata("TOOLTIP")
    pf:SetClampedToScreen(true)
    pf:EnableMouse(false)
    ApplyCardBox(pf, 0.96, 0.45)

    pf.accent = pf:CreateTexture(nil, "ARTWORK")
    pf.accent:SetPoint("TOPLEFT", 1, -1)
    pf.accent:SetPoint("TOPRIGHT", -1, -1)
    pf.accent:SetHeight(2)

    pf.title = pf:CreateFontString(nil, "OVERLAY")
    pf.title:SetPoint("TOPLEFT", PREVIEW_PAD, -9)
    pf.title:SetPoint("TOPRIGHT", -PREVIEW_PAD, -9)
    pf.title:SetJustifyH("LEFT")
    pf.title:SetWordWrap(true)
    SetFont(pf.title, 13, "")

    pf.stage = _G.CreateFrame("Frame", nil, pf, tpl)
    pf.stage:SetPoint("TOPLEFT", pf.title, "BOTTOMLEFT", 0, -6)
    pf.stage:SetSize(PREVIEW_W - PREVIEW_PAD * 2, MODEL_H)
    pf.stage:EnableMouse(false)
    if pf.stage.SetBackdrop then
        pf.stage:SetBackdrop(CARD_BACKDROP)
        pf.stage:SetBackdropColor(8 / 255, 9 / 255, 13 / 255, 0.95)
        pf.stage:SetBackdropBorderColor(1, 1, 1, 0.08)
    end

    pf.stageGlow = pf.stage:CreateTexture(nil, "BACKGROUND", nil, 1)
    pf.stageGlow:SetPoint("BOTTOMLEFT", 1, 1)
    pf.stageGlow:SetPoint("BOTTOMRIGHT", -1, 1)
    pf.stageGlow:SetHeight(56)
    pf.stageGlow:SetColorTexture(1, 1, 1, 0.04)

    pf.fallback = pf.stage:CreateTexture(nil, "ARTWORK")
    pf.fallback:SetSize(42, 42)
    pf.fallback:SetPoint("CENTER")
    pf.fallback:SetAlpha(0.75)

    pf.noModelText = pf.stage:CreateFontString(nil, "OVERLAY")
    pf.noModelText:SetPoint("TOP", pf.fallback, "BOTTOM", 0, -6)
    SetFont(pf.noModelText, 10, "")
    pf.noModelText:SetTextColor(0.54, 0.56, 0.61)
    pf.noModelText:SetText(L("3D model unavailable"))
    pf.noModelText:Hide()

    pf.model = _G.CreateFrame("PlayerModel", nil, pf.stage)
    pf.model:SetPoint("TOPLEFT", 2, -2)
    pf.model:SetPoint("BOTTOMRIGHT", -2, 2)
    pf.model:EnableMouse(false)
    if pf.model.SetKeepModelOnHide then pcall(pf.model.SetKeepModelOnHide, pf.model, false) end
    pf.model:SetScript("OnModelLoaded", function(self)
        FrameCamera(self, true)
        if ModelLoaded(self) then
            pf.modelLoaded = true
            pf.fallback:Hide()
            pf.noModelText:Hide()
        end
    end)

    pf.sep = pf:CreateTexture(nil, "ARTWORK")
    pf.sep:SetPoint("TOPLEFT", pf.stage, "BOTTOMLEFT", 0, -8)
    pf.sep:SetPoint("TOPRIGHT", pf.stage, "BOTTOMRIGHT", 0, -8)
    pf.sep:SetHeight(1)
    pf.sep:SetColorTexture(1, 1, 1, 0.08)

    pf.desc = pf:CreateFontString(nil, "OVERLAY")
    pf.desc:SetPoint("TOPLEFT", pf.sep, "BOTTOMLEFT", 0, -7)
    pf.desc:SetWidth(PREVIEW_W - PREVIEW_PAD * 2)
    pf.desc:SetJustifyH("LEFT")
    pf.desc:SetJustifyV("TOP")
    pf.desc:SetWordWrap(true)
    pf.desc:SetSpacing(2)
    SetFont(pf.desc, 11, "")
    pf.desc:SetTextColor(0.86, 0.88, 0.92)

    pf:Hide()
    previewFrame = pf
    return pf
end

local function AnchorPreview(pf, anchorFrame)
    pf:ClearAllPoints()
    if not anchorFrame then
        pf:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
        return
    end
    local cx = anchorFrame.GetCenter and anchorFrame:GetCenter()
    local screenW = (_G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth())
        or (_G.GetScreenWidth and _G.GetScreenWidth()) or 1024
    if cx and cx > screenW * 0.5 then
        pf:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -8, 0)
    else
        pf:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 8, 0)
    end
end

function portrait.ShowPreview(hoverOwner, opts)
    opts = opts or {}
    if _G.GameTooltip and not (_G.GameTooltip.IsForbidden and _G.GameTooltip:IsForbidden()) then
        _G.GameTooltip:Hide()
    end

    local pf = EnsurePreviewFrame()
    pf.owner = hoverOwner

    -- Anchor to the enclosing insecure container (RXPTargetFrame / OpenXPCard) so hovering a
    -- SecureActionButtonTemplate row never anchors frames to a protected widget in combat.
    local anchor = opts.anchorFrame or (hoverOwner and hoverOwner.GetParent and hoverOwner:GetParent()) or hoverOwner
    AnchorPreview(pf, anchor)

    local toneKey = opts.tone or (opts.isCurrentTarget and "target") or (opts.kind == "rare" and "rare")
        or (opts.isEnemy and "hostile") or "friendly"
    local c = TONES[toneKey] or TONES.neutral
    if pf.SetBackdropBorderColor then pf:SetBackdropBorderColor(c[1], c[2], c[3], 0.85) end
    pf.accent:SetColorTexture(c[1], c[2], c[3], 0.95)
    pf.stageGlow:SetColorTexture(c[1], c[2], c[3], 0.07)

    local title, desc = portrait.BuildDescription(opts)
    SetFont(pf.title, 13, "")
    SetFont(pf.desc, 11, "")
    pf.title:SetText(title)
    pf.title:SetTextColor(c[1], c[2], c[3], 1)
    pf.desc:SetText(desc)

    pf.stage:ClearAllPoints()
    pf.stage:SetPoint("TOPLEFT", pf.title, "BOTTOMLEFT", 0, -6)

    local titleH = (pf.title.GetStringHeight and pf.title:GetStringHeight()) or 16
    local descH = (pf.desc.GetStringHeight and pf.desc:GetStringHeight()) or 40
    pf:SetHeight(9 + titleH + 6 + MODEL_H + 8 + 1 + 7 + descH + PREVIEW_PAD)

    local npcId, unit = tonumber(opts.npcId), opts.unit
    local modelKey = (npcId and npcId > 0 and ("npc:" .. npcId))
        or (unit and ("unit:" .. tostring(unit)))
        or ("none:" .. tostring(title))

    pf:Show()
    if pf.modelKey == modelKey and pf.modelLoaded then return end

    pf.modelKey = modelKey
    pf.modelLoaded = false
    pf.noModelText:Hide()
    PaintFallback(pf.fallback, unit, opts.fallbackTexture)

    LoadCreatureModel(pf, pf.model, npcId, unit, true,
        function()
            pf.modelLoaded = true
            pf.fallback:Hide()
            pf.noModelText:Hide()
        end,
        function(streaming)
            if not streaming then
                pf.modelLoaded = false
                if pf:IsShown() then pf.noModelText:Show() end
            end
        end)
end

function portrait.HidePreview(owner)
    if not previewFrame then return end
    if owner and previewFrame.owner and previewFrame.owner ~= owner then return end
    previewFrame.owner = nil
    previewFrame.attempt = nil
    previewFrame.modelKey = nil
    previewFrame.modelLoaded = false
    if previewFrame.model then
        if previewFrame.model.ClearModel then pcall(previewFrame.model.ClearModel, previewFrame.model) end
        previewFrame.model:Hide()
    end
    previewFrame:Hide()
end
