-- Bringing a 1.x character over, once.
--
-- 2.0 lists the 1.x saved variables in its .toc so the game loads them (and
-- writes them back unchanged: an addon's saved variables the .toc doesn't
-- list are dropped from the file, which would break going back to 1.3.x).
-- This file only reads them; nothing in them is ever changed.
--
-- Per character, on the first 2.0 login:
--   * the guide you were on: 21-60 and dungeon guides have the same steps in
--     2.0 (class quest steps added in 2.0 are skipped when counting), so the
--     same step; your saved place in every other guide too, and steps you
--     skipped or whose chain was missed
--   * flight paths you know
--   * a 1-20 guide (2.0 has a new 1-20 route) or anything that doesn't match:
--     smart start places you from your quest log and finished quests
-- Per account, once: the settings that still exist (card place and size,
-- font, arrow, maps, extras) and arrow paths you recorded or OpenXP learned.
local _, OXP = ...

local Import = {}
OXP.Import = Import

local Registry = OXP.Registry

local function Table(v) return type(v) == "table" and v or nil end

------------------------------------------------------------------------
-- Settings (account)
------------------------------------------------------------------------

-- 1.x profile key -> function(old value, new settings)
local SETTINGS = {
    openxpCardWidth = function(v, s) if type(v) == "number" then s.cardWidth = v end end,
    openxpCardHeight = function(v, s) if type(v) == "number" then s.cardHeight = v end end,
    openxpCardPos = function(v, s)
        if Table(v) and type(v[1]) == "string" and type(v[3]) == "number" then s.cardPos = { v[1], v[2] or v[1], v[3], v[4] or 0 } end
    end,
    openxpCardCollapsed = function(v, s) s.cardCollapsed = v == true end,
    windowScale = function(v, s) if type(v) == "number" then s.cardScale = v end end,
    guideFontSize = function(v, s) if type(v) == "number" then s.fontSize = math.floor(v + 0.5) end end,
    guideFont = function(v, s) if type(v) == "string" then s.font = v end end,
    guideFontOutline = function(v, s) if v == "" or v == "OUTLINE" or v == "THICKOUTLINE" then s.fontOutline = v end end,
    arrowScale = function(v, s) if type(v) == "number" then s.arrowScale = v end end,
    arrowText = function(v, s) if type(v) == "number" then s.arrowText = math.floor(v + 0.5) end end,
    lockFrames = function(v, s) s.lockFrames = v == true end,
    disableArrow = function(v, s) s.arrowShown = v ~= true end,
    hideGuideWindow = function(v, s) s.cardShown = v ~= true end,
    openxpMapRoute = function(v, s) s.mapRoute = v ~= false end,
    openxpMapAreas = function(v, s) s.mapAreas = v ~= false end,
    openxpMobPins = function(v, s) s.mobPins = v == true end,
    openxpRouteColor = function(v, s)
        if Table(v) and type(v[1]) == "number" then s.routeColor = { v[1], v[2], v[3] } end
    end,
    openxpTravel = function(v, s) s.travel = v ~= false end,
    openxpTooltips = function(v, s) s.tooltips = v ~= false end,
    openxpNameplates = function(v, s) s.nameplates = v ~= false end,
    openxpAutoLoot = function(v, s) s.autoLoot = v == true end,
    openxpMaxCamera = function(v, s) s.maxCamera = v == true end,
    smartStartOnLogin = function(v, s) s.smartStartOnLogin = v ~= false end,
    disableQuestAutomation = function(v, s)
        if v == true then s.autoAccept, s.autoTurnIn, s.skipGossip = false, false, false end
    end,
    minimap = function(v, s)
        if not Table(v) then return end
        if v.hide ~= nil then s.minimap.hide = v.hide == true end
        if type(v.minimapPos) == "number" then s.minimap.angle = v.minimapPos end
    end,
}
Import.SETTINGS = SETTINGS

--- The 1.x settings profile this character used, or nil.
function Import.OldProfile()
    local db = Table(_G.OXPSettings)
    local profiles = db and Table(db.profiles)
    if not profiles then return nil end
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    local key = Table(db.profileKeys) and db.profileKeys[name .. " - " .. realm]
    return Table(profiles[key or (name .. " - " .. realm)]) or Table(profiles.Default)
end

function Import.Settings()
    local db = OXP.db
    if db.importedSettings then return false end
    db.importedSettings = OXP.version
    local old = Import.OldProfile()
    local n = 0
    if old then
        for key, apply in pairs(SETTINGS) do
            if old[key] ~= nil then
                local ok = pcall(apply, old[key], OXP.settings)
                if ok then n = n + 1 end
            end
        end
    end
    -- arrow paths you recorded, and caves OpenXP learned (copied, not moved)
    local paths = Table(_G.OXPData) and Table(_G.OXPData.openxpPaths)
    if paths then
        local mine = OXP.db.paths
        for _, list in ipairs({ "areas", "passes" }) do
            for _, a in ipairs(Table(paths[list]) or {}) do
                if Table(a) then
                    local copy = {}
                    for k, v in pairs(a) do copy[k] = v end
                    mine[list][#mine[list] + 1] = copy
                end
            end
        end
    end
    return n > 0
end

------------------------------------------------------------------------
-- The character
------------------------------------------------------------------------

--- The 2.0 guide that a 1.x guide (group, name) is, for this player.
function Import.FindGuide(group, name)
    if type(name) ~= "string" then return nil end
    for _, g in ipairs(Registry.All()) do
        if g.name == name and (g.oldGroup == group or g.group == group) and Registry.IsAvailable(g) then
            return g
        end
    end
end

--- 2.0 data index of the n-th step that was in 1.x (class quest steps
--- added in 2.0 carry a `source` and aren't counted).
function Import.StepIndex(guide, n)
    if type(n) ~= "number" then return nil end
    local count = 0
    for index, step in ipairs(guide.steps) do
        if not step.source then
            count = count + 1
            if count == n then return index end
        end
    end
end

-- One guide's 1.x place, skips and statuses -> its 2.0 save.
local function CarryGuide(guide, step, skipped, status)
    local save = OXP.char.guides[guide.key] or { step = 1, skipped = {}, status = {} }
    OXP.char.guides[guide.key] = save
    save.skipped, save.status = save.skipped or {}, save.status or {}
    local index = Import.StepIndex(guide, step)
    if index then save.step = index end
    for n, on in pairs(Table(skipped) or {}) do
        local i = on and Import.StepIndex(guide, n)
        if i then save.skipped[i] = true end
    end
    for n, s in pairs(Table(status) or {}) do
        local i = (s == "skipped" or s == "chain") and Import.StepIndex(guide, n)
        if i then
            save.status[i] = s
            save.skipped[i] = true
        end
    end
    return index
end

--- What happened, for the note: { guide = 2.0 guide or nil, step = position or nil,
--- smart = true when smart start places you, flights = n }.
function Import.Character()
    local char = OXP.char
    if char.imported then return nil end
    char.imported = OXP.version
    local old = Table(_G.OXPCData)
    if not old then return nil end
    local result = { flights = 0 }

    for _, name in pairs(Table(old.flightPaths) or {}) do
        if type(name) == "string" then
            OXP.World.LearnFlightPath(name)
            result.flights = result.flights + 1
        end
    end

    -- your place in every guide you had started (the card kept it by name)
    local group = type(old.currentGuideGroup) == "string" and old.currentGuideGroup or nil
    local statuses = Table(old.openxpStepStatus) or {}
    for name, step in pairs(Table(old.openxpSteps) or {}) do
        local g = Import.FindGuide(group, name) or Import.FindGuide("OpenXP Dungeons", name)
        if g and type(step) == "number" then CarryGuide(g, step, nil, statuses[name]) end
    end

    local guide = Import.FindGuide(group, old.currentGuideName)
    if guide and type(old.currentStep) == "number" then
        CarryGuide(guide, old.currentStep, old.stepSkip, statuses[old.currentGuideName])
        char.currentGuide = guide.key
        result.guide = guide
    else
        -- a 1-20 guide (new route in 2.0) or no guide: smart start at login
        result.smart = true
    end
    return result
end

OXP.OnLoaded(function()
    local ok, err = pcall(Import.Settings)
    if not ok then OXP.report(err) end
end)

-- before the step engine restores the character's guide (Runner.lua)
OXP.OnReady(function()
    local ok, res = pcall(Import.Character)
    if not ok then
        OXP.report(res)
        return
    end
    Import.result = res
end)

-- after login has placed you: tell the player where they are now
OXP.Listen("READY", function()
    local res = Import.result
    if not res then return end
    local g = OXP.Engine.GetGuide()
    res.placed = g
    res.step = OXP.Engine.GetPosition()
    OXP.Send("IMPORTED", res)
end)
