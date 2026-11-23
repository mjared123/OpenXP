-- Item 9: Blizzard's quest watch frame and Questie's tracker are hidden by
-- default; Settings > Extras > "Show quest tracker" restores what was there.
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("tracker")

-- Blizzard's frames exist before any addon loads, like in the game
local function newGame(setup, keepDefault)
    -- these tests are about hiding: start as a player who turned it off
    local saved = not keepDefault and { OpenXPDB = { trackerFixed = 1, settings = { showQuestTracker = false } } } or nil
    local game = FakeWoW.New(ROOT, { level = 5 }, saved)
    if setup then setup(game) end
    local OXP = game:LoadAddon()
    game:Login()
    return game, OXP
end

local function setShow(OXP, v)
    OXP.settings.showQuestTracker = v
    OXP.Send("SETTINGS_CHANGED")
end

-- C_Timer.After with a delay: run what's queued now
local function runDelayed(game)
    local queued = game.delayed
    game.delayed = {}
    for _, fn in ipairs(queued) do fn() end
    game:Flush()
end

-- a stand-in for Questie: its global, AceDB profile and tracker module
local function fakeQuestie(trackerEnabled, started)
    local tracker = { started = started, updates = 0, userCalls = {} }
    function tracker:Update() self.updates = self.updates + 1 end
    function tracker:Toggle()
        _G.Questie.db.profile.trackerEnabled = not _G.Questie.db.profile.trackerEnabled
    end
    _G.Questie = { db = { profile = { trackerEnabled = trackerEnabled } } }
    _G.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestieTracker" then return tracker end
        return {}
    end }
    return tracker, _G.Questie.db.profile
end

local function noQuestie() _G.Questie, _G.QuestieLoader = nil, nil end

------------------------------------------------------------------------
print("-- 2.0.2: shown by default, and turned back on once (GitHub #83, #92-#95)")
do
    noQuestie()
    local game, OXP = newGame(function(game)
        local w = game.Widget("Frame", "QuestWatchFrame")
        w.shown = true
    end, true)
    t.eq(OXP.settings.showQuestTracker, true, "on by default")
    t.eq(QuestWatchFrame:IsShown(), true, "Blizzard's tracker stays up")
    t.eq(OpenXPDB.trackerFixed, 1, "the one-time fix is marked done")
end
do
    noQuestie()
    -- hidden by 2.0.1's default
    local game = FakeWoW.New(ROOT, { level = 5 }, { OpenXPDB = { settings = { showQuestTracker = false } } })
    local OXP = game:LoadAddon()
    game:Login()
    t.eq(OXP.settings.showQuestTracker, true, "2.0.1's hidden tracker is turned back on once")
    OXP.settings.showQuestTracker = false
    local game2 = FakeWoW.New(ROOT, { level = 5 }, game:SavedVariables())
    local OXP2 = game2:LoadAddon()
    game2:Login()
    t.eq(OXP2.settings.showQuestTracker, false, "hidden again by the player: stays hidden")
end

------------------------------------------------------------------------
print("-- Classic's QuestWatchFrame: hidden by default, kept hidden, restored")
do
    noQuestie()
    local updates = 0
    local game, OXP = newGame(function(game)
        local w = game.Widget("Frame", "QuestWatchFrame")
        w.shown = true
        QuestWatch_Update = function() updates = updates + 1 end
    end)
    local w = QuestWatchFrame
    t.eq(OXP.settings.showQuestTracker, false, "turned off")
    t.eq(w:IsShown(), false, "hidden at login")
    t.eq(w.alpha, 0, "and faded")
    w:Show() -- QuestWatch_Update showing it again
    t.eq(w:IsShown(), false, "Blizzard showing it again is undone")
    t.eq(w.parent, nil, "never reparented")

    setShow(OXP, true)
    t.eq(w:IsShown(), true, "the toggle on shows it again")
    t.eq(w.alpha, 1, "at full alpha")
    t.eq(updates, 1, "and lets Blizzard's QuestWatch_Update decide")
    w:Hide()
    w:Show()
    t.eq(w:IsShown(), true, "left alone while the setting is on")

    setShow(OXP, false)
    t.eq(w:IsShown(), false, "off again: hidden")
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
    QuestWatch_Update = nil
end

------------------------------------------------------------------------
print("-- a frame that was hidden stays hidden when restored")
do
    noQuestie()
    local game, OXP = newGame(function(game) game.Widget("Frame", "QuestWatchFrame") end)
    local w = QuestWatchFrame
    t.eq(w:IsShown(), false, "hidden (nothing watched)")
    setShow(OXP, true)
    t.eq(w:IsShown(), false, "restoring doesn't show an empty watch frame")
    t.eq(w.alpha, 1, "but its alpha is back")
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
end

------------------------------------------------------------------------
print("-- a protected tracker in combat: faded now, hidden after combat")
do
    noQuestie()
    local combat = true
    local game, OXP = newGame(function(game)
        local w = game.Widget("Frame", "ObjectiveTrackerFrame")
        w.shown = true
        w.IsProtected = function() return true end
        InCombatLockdown = function() return combat end
    end)
    local w = ObjectiveTrackerFrame
    t.eq(w.alpha, 0, "faded in combat")
    t.eq(w:IsShown(), true, "not hidden in combat (protected)")
    combat = false
    game:Fire("PLAYER_REGEN_ENABLED")
    t.eq(w:IsShown(), false, "hidden once combat ends")

    combat = true
    setShow(OXP, true)
    t.eq(w:IsShown(), false, "not shown in combat")
    t.eq(w.alpha, 0, "still faded until it can be shown")
    combat = false
    game:Fire("PLAYER_REGEN_ENABLED")
    t.eq(w:IsShown(), true, "shown after combat")
    t.eq(w.alpha, 1, "at full alpha")
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
    InCombatLockdown = nil
end

------------------------------------------------------------------------
print("-- Forever's ObjectiveTrackerFrame loading after login is hidden too")
do
    noQuestie()
    local game = newGame()
    local w = game.Widget("Frame", "ObjectiveTrackerFrame")
    w.shown = true
    game:Fire("ADDON_LOADED", "Blizzard_ObjectiveTracker")
    t.eq(w:IsShown(), false, "hidden once Blizzard_ObjectiveTracker loads")
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
    ObjectiveTrackerFrame = nil
end

------------------------------------------------------------------------
print("-- Questie: waits for it to start, turns its tracker off, puts back the player's setting")
do
    local tracker, profile = fakeQuestie(true, false)
    local game, OXP = newGame()
    t.eq(profile.trackerEnabled, true, "Questie still starting: not touched yet")
    t.ok(#game.delayed > 0, "a retry is queued")
    runDelayed(game)
    t.eq(profile.trackerEnabled, true, "still starting after a retry")
    tracker.started = true
    runDelayed(game)
    t.eq(profile.trackerEnabled, false, "Questie started: its tracker is off")
    t.eq(tracker.updates, 1, "and QuestieTracker:Update hid it")

    setShow(OXP, true)
    t.eq(profile.trackerEnabled, true, "toggle on: the player's setting is back")
    t.eq(tracker.updates, 2, "and Update shows the tracker again")

    setShow(OXP, false)
    t.eq(profile.trackerEnabled, false, "off again")
    game:Fire("PLAYER_LOGOUT")
    t.eq(profile.trackerEnabled, true, "logout writes back the player's own setting")
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
    noQuestie()
end

------------------------------------------------------------------------
print("-- Questie's tracker that the player had off stays off")
do
    local tracker, profile = fakeQuestie(false, true)
    local game, OXP = newGame()
    t.eq(profile.trackerEnabled, false, "off")
    t.eq(tracker.updates, 0, "nothing to update")
    setShow(OXP, true)
    t.eq(profile.trackerEnabled, false, "not force-enabled by the toggle")
    game:Fire("PLAYER_LOGOUT")
    t.eq(profile.trackerEnabled, false, "nor at logout")
    noQuestie()
end

------------------------------------------------------------------------
print("-- the player toggling Questie's tracker themselves wins")
do
    local tracker, profile = fakeQuestie(true, true)
    local game = newGame()
    t.eq(profile.trackerEnabled, false, "hidden at login")
    tracker:Toggle() -- "/questie tracker"
    t.eq(profile.trackerEnabled, true, "the player turned it on")
    game:Fire("PLAYER_LOGOUT")
    t.eq(profile.trackerEnabled, true, "kept")
    -- and after a reload too (GitHub #93, #95: it went off again every login)
    local saved = game:SavedVariables()
    local tracker2, profile2 = fakeQuestie(true, true)
    local game2 = FakeWoW.New(ROOT, { level = 5 }, saved)
    local OXP2 = game2:LoadAddon()
    game2:Login()
    runDelayed(game2)
    t.eq(profile2.trackerEnabled, true, "Questie's tracker left on after a reload")
    t.eq(OXP2.settings.questieTrackerMine, true, "OpenXP remembers it's the player's")
    noQuestie()
end

------------------------------------------------------------------------
print("-- Questie's tracker on: Blizzard's (which Questie replaces) stays hidden on restore")
do
    local tracker, profile = fakeQuestie(true, true)
    local game, OXP = newGame(function(game)
        local w = game.Widget("Frame", "QuestWatchFrame")
        w.shown = true
    end)
    setShow(OXP, true)
    t.eq(profile.trackerEnabled, true, "Questie's tracker back")
    t.eq(QuestWatchFrame:IsShown(), false, "Blizzard's not shown next to it")
    t.eq(QuestWatchFrame.alpha, 1, "but its alpha is back")
    noQuestie()
end

------------------------------------------------------------------------
print("-- without Questie or any tracker frame: nothing queued, no errors")
do
    noQuestie()
    local game = newGame()
    local queued = #game.delayed
    runDelayed(game)
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
    t.ok(queued == 0 or #game.delayed == 0, "no Questie retries keep coming")
end

------------------------------------------------------------------------
print("-- the setting is on the Extras page")
do
    noQuestie()
    local game, OXP = newGame()
    local found = false
    for _, page in ipairs(OXP.Settings.PAGES) do
        if page.key == "extras" then
            local p = { content = UIParent, y = 0, rows = {}, toggles = {}, sliders = {}, dropdowns = {} }
            local ok, err = pcall(page.build, p)
            t.ok(ok, "Extras page builds: " .. tostring(err))
            found = p.toggles.showQuestTracker ~= nil
        end
    end
    t.ok(found, "Show quest tracker toggle on Extras")
    t.eq(#game.errors, 0, "no errors: " .. tostring(game.errors[1]))
end

return t.fails
