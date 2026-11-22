-- Tests for OpenXPPortrait.lua and Targeting.lua 3D target portraits + full-body hover preview.
local ROOT = ...
unpack = unpack or table.unpack
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe

local timers = {}
local combat = false
local unitNames = { target = "Syndicate Highwayman", nameplate1 = "Syndicate Highwayman", nameplate2 = "Random Critter" }
local unitGuids = { target = "Creature-0-1-0-0-2586-0001", nameplate1 = "Creature-0-1-0-0-2586-0001", nameplate2 = "Creature-0-1-0-0-9999-0001" }

local function obj(kind, name, parent, template)
    local shown = true
    local scripts = {}
    local attrs = {}
    local o
    o = {
        __kind = kind,
        __name = name,
        _parent = parent,
        _template = template,
        _points = {},
        _camera = {},
        Show = function(self)
            local was = shown
            shown = true
            if not was and scripts.OnShow then scripts.OnShow(self) end
        end,
        Hide = function(self)
            local was = shown
            shown = false
            if was and scripts.OnHide then scripts.OnHide(self) end
        end,
        IsShown = function() return shown end,
        IsVisible = function(self)
            if not shown then return false end
            if self._parent and self._parent.IsVisible then return self._parent:IsVisible() end
            return true
        end,
        IsForbidden = function() return false end,
        GetParent = function(self) return self._parent end,
        SetScript = function(_, k, fn) scripts[k] = fn end,
        GetScript = function(_, k) return scripts[k] end,
        HookScript = function(_, k, fn)
            local prev = scripts[k]
            scripts[k] = function(...) if prev then prev(...) end fn(...) end
        end,
        SetAttribute = function(_, k, v) attrs[k] = v end,
        GetAttribute = function(_, k) return attrs[k] end,
        SetText = function(self, v) rawset(self, "_text", v) end,
        GetText = function(self) return rawget(self, "_text") end,
        GetStringWidth = function(self) return #(rawget(self, "_text") or "") * 6 end,
        GetStringHeight = function(self)
            local lines = 1
            for _ in (rawget(self, "_text") or ""):gmatch("\n") do lines = lines + 1 end
            return lines * 12
        end,
        GetWidth = function(self) return rawget(self, "_w") or 224 end,
        GetHeight = function(self) return rawget(self, "_h") or 34 end,
        SetWidth = function(self, v) rawset(self, "_w", v) end,
        SetHeight = function(self, v) rawset(self, "_h", v) end,
        SetSize = function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end,
        GetCenter = function() return 900, 500 end,
        SetPoint = function(self, ...) tinsert(self._points, { ... }) end,
        ClearAllPoints = function(self) self._points = {} end,
        GetFrameLevel = function() return 2 end,
        CreateTexture = function() return obj("Texture") end,
        CreateFontString = function() return obj("FontString") end,
        SetCreature = function(self, id) self._creatureId = id; self._cleared = false end,
        SetUnit = function(self, u) self._unit = u; self._cleared = false end,
        ClearModel = function(self) self._cleared = true; self._creatureId = nil; self._unit = nil end,
        GetModelFileID = function(self) return (self._creatureId or self._unit) and 12345 or 0 end,
        SetCamera = function(self, v) self._camera.camera = v end,
        SetPortraitZoom = function(self, v) self._camera.portraitZoom = v end,
        SetCamDistanceScale = function(self, v) self._camera.camDist = v end,
        ClearTransform = function(self) self._camera.clearedTransform = true end,
        SetPosition = function(self, x, y, z) self._camera.pos = { x, y, z } end,
        SetFacing = function(self, v) self._camera.facing = v end,
    }
    if name then _G[name] = o end
    return setmetatable(o, {
        __index = function(_, k)
            if type(k) == "string" and k:match("^[A-Z]") then return function() end end
            return nil
        end,
    })
end

function CreateFrame(kind, name, parent, template) return obj(kind, name, parent, template) end
UIParent = obj("Frame", "UIParent")
UIParent._w = 1920
GameTooltip = obj("GameTooltip", "GameTooltip")
BackdropTemplateMixin = {}
InCombatLockdown = function() return combat end
IsInRaid = function() return false end
IsInGroup = function() return false end
UnitOnTaxi = function() return false end
UnitIsPlayer = function() return false end
UnitIsDead = function() return false end
UnitIsUnit = function() return false end
UnitExists = function(u) return unitNames[u] ~= nil end
UnitName = function(u) return unitNames[u] end
UnitGUID = function(u) return unitGuids[u] end
UnitLevel = function(u) return u == "player" and 32 or 31 end
UnitClassification = function() return "elite" end
UnitCreatureType = function() return "Humanoid" end
GetRealZoneText = function() return "Arathi Highlands" end
GetSubZoneText = function() return "Northfold Manor" end
GetTime = function() return 100 end
GetNumMacros = function() return 0 end
GetMacroInfo = function() return nil end
DeleteMacro = function() end
GetBindingKey = function(b) if b == "CLICK RXPTargetFrame_EnemyButton1:LeftButton" then return "F1" end end
GetBindingText = function(k) return k end
GetQuestDifficultyColor = function() return { r = 1, g = 1, b = 0 } end
C_Timer = { After = function(d, fn) tinsert(timers, { d = d, fn = fn }) end }
C_NamePlate = {
    GetNamePlates = function()
        return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" } }
    end,
}
C_Map = { GetAreaInfo = function(id) if id == 45 then return "Arathi Highlands" end end }
LibStub = function() return { GetPlayerZone = function() return 1417 end } end

local npcDB = {
    [2586] = {
        name = "Syndicate Highwayman",
        subName = "Syndicate Assassin",
        minLevel = 30,
        maxLevel = 31,
        rank = 1,
        zoneID = 45,
        spawns = { [45] = { { 32.4, 31.8 } } },
        npcFlags = 0,
    },
    [2706] = {
        name = "Tor'gan",
        subName = "Quest Giver",
        minLevel = 35,
        maxLevel = 35,
        rank = 0,
        zoneID = 45,
        spawns = { [45] = { { 74.6, 36.4 } } },
        npcFlags = 0,
    },
}

QuestieLoader = {
    ImportModule = function(_, modName)
        if modName == "QuestieDB" then
            return {
                NPCPointers = { [2586] = true, [2706] = true },
                GetQuest = function() return nil end,
                QueryNPCSingle = function(id, field) return npcDB[id] and npcDB[id][field] or nil end,
                GetNPC = function(_, id) return npcDB[id] end,
            }
        end
    end,
}

local addon = {
    title = "OpenXP",
    game = "FOREVER",
    gameVersion = 16001,
    locale = { Get = function(s) return s end },
    GetUnitName = function(u) return unitNames[u] end,
    GetCreatureName = function(s) return s end,
    IsSecretValue = function() return false end,
    enabledFrames = {},
    generatedSteps = {},
    v2 = { IsGuideWindowEnabled = function() return false end },
    RXPFrame = {
        activeSteps = {
            {
                elements = {
                    { tag = "complete", title = "Foul Magics", mobs = { "Syndicate Highwayman" } },
                    { tag = "turnin", title = "The Broken Sigil", targets = { "Tor'gan" } },
                },
            },
        },
    },
    openxpTooltips = {
        KillLines = function(name)
            if name == "Syndicate Highwayman" then
                return { { title = "Foul Magics", have = 4, need = 10, done = false } }
            end
            return {}
        end,
        MobItemLines = function() return {} end,
    },
    settings = {
        profile = {
            enableTargetFrame = true,
            enableFriendlyTargeting = true,
            enableEnemyTargeting = true,
            enableTargetAutomation = false,
            enableEnemyMarking = true,
            showEnabled = true,
            activeTargetScale = 1,
        },
        SaveFramePositions = function() end,
    },
}
function addon:NewModule() return { RegisterEvent = function() end } end

assert(loadfile(ROOT .. "/OpenXPPortrait.lua"))("OpenXP", addon)
assert(loadfile(ROOT .. "/Targeting.lua"))("OpenXP", addon)

local fails = 0
local function try(label, fn)
    local ok, err = pcall(fn)
    if ok then print("ok   " .. label) else fails = fails + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end

try("resolves inline and prefixed NPC names", function()
    addon.portrait.RememberNpc("+Snow Leopard Prowler", 269075)
    assert(addon.portrait.ResolveNpcId("*Snow Leopard Prowler") == 269075)
    assert(addon.portrait.ResolveNpcId("Teo Hammerstorm::257446") == 257446)
end)

try("renders 3D portraits on quest target rows and reloads on show", function()
    addon.targeting:Setup()
    addon.targeting:UpdateEnemyList({}, { "Syndicate Highwayman" })
    addon.targeting:UpdateTargetList({ "Tor'gan" })
    local guard = 0
    while #timers > 0 and guard < 20 do
        guard = guard + 1
        tremove(timers, 1).fn()
    end
    local tf = addon.targeting.activeTargetFrame
    local enemyBtn = tf.enemyTargetButtons[1]
    local friendlyBtn = tf.friendlyTargetButtons[1]
    assert(enemyBtn.portrait.model._creatureId == 2586)
    assert(friendlyBtn.portrait.model._creatureId == 2706)
    tf:Hide()
    tf:Show()
    assert(enemyBtn.portrait.model._creatureId == 2586)
end)

try("hover opens full-body 3D model + description safely in combat and clears on leave", function()
    local tf = addon.targeting.activeTargetFrame
    local enemyBtn = tf.enemyTargetButtons[1]
    combat = true
    enemyBtn:GetScript("OnEnter")(enemyBtn)
    local pf = _G.OpenXPTargetPreview
    assert(pf and pf:IsShown())
    assert(pf.model._creatureId == 2586)
    assert(pf.model._camera.portraitZoom == 0)
    assert(pf._points[1][2] == tf)
    local desc = pf.desc:GetText()
    assert(desc:find("Syndicate Assassin", 1, true))
    assert(desc:find("Foul Magics", 1, true))
    assert(desc:find("4/10", 1, true))
    assert(desc:find("Arathi Highlands", 1, true))
    assert(desc:find("F1", 1, true))
    enemyBtn:GetScript("OnLeave")(enemyBtn)
    assert(not pf:IsShown())
    assert(pf.model._cleared == true)
    combat = false
end)

try("ignores irrelevant nameplates and coalesces burst portrait refreshes", function()
    local before = #timers
    addon.targeting:NAME_PLATE_UNIT_ADDED(nil, "nameplate2")
    assert(#timers == before)
    addon.targeting:NAME_PLATE_UNIT_ADDED(nil, "nameplate1")
    assert(#timers == before + 1)
    addon.targeting:NAME_PLATE_UNIT_ADDED(nil, "nameplate1")
    assert(#timers == before + 1)
end)

print(fails == 0 and "portrait tests passed" or (fails .. " failed"))
return fails
