-- Quest tracker: the card and the arrow already say what to do, so by
-- default Blizzard's quest watch frame and Questie's tracker are hidden.
-- Settings > Extras > "Show quest tracker" puts back whatever was there.
--
-- Blizzard's frame is never reparented or replaced: it is faded out and
-- hidden, and an OnShow hook hides it again when Blizzard's own code shows
-- it. A protected frame (Forever's ObjectiveTrackerFrame can be) is only
-- faded in combat and hidden or shown once combat ends.
--
-- Questie's tracker is turned off with Questie's own setting
-- (Questie.db.profile.trackerEnabled) and QuestieTracker:Update(), the way
-- its "/questie tracker" toggle does it, never by touching its frames. The
-- player's own setting is remembered and written back at logout, so
-- Questie's saved settings keep what the player chose.
local _, OXP = ...

local QT = {}
OXP.QuestTracker = QT

local FRAMES = { "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" }
local QUESTIE_WAIT, QUESTIE_TRIES = 2, 150 -- Questie can take minutes to start on a first login

local held = {}           -- [frame] = { held =, alpha =, wantShown =, hooked = }
local afterCombat = false -- something waits for combat to end
local questie = { held = false, was = nil, tries = 0, waiting = false, needUpdate = false, hooked = false }

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

--- True while the trackers should be hidden (the default).
function QT.HideWanted()
    return not (OXP.settings and OXP.settings.showQuestTracker == true)
end

------------------------------------------------------------------------
-- Blizzard's quest watch frame
------------------------------------------------------------------------

local function Blocked(frame)
    return InCombat() and frame.IsProtected and frame:IsProtected() and true or false
end

local function Suppress(frame)
    frame:SetAlpha(0) -- alpha isn't protected: a frame shown in combat stays invisible
    if frame:IsShown() then
        if Blocked(frame) then afterCombat = true else frame:Hide() end
    end
end

local function HoldFrame(frame)
    local st = held[frame]
    if not st then
        st = {}
        held[frame] = st
    end
    if not st.held then
        st.held = true
        st.alpha = frame.GetAlpha and frame:GetAlpha() or 1
        st.wantShown = frame:IsShown() and true or false
    end
    if not st.hooked and frame.HookScript then
        st.hooked = true
        frame:HookScript("OnShow", function(self)
            local s = held[self]
            if s and s.held then
                s.wantShown = true -- Blizzard wants it up; shown again on release
                Suppress(self)
            end
        end)
    end
    Suppress(frame)
end

-- keepHidden: Questie's tracker is on and replaces Blizzard's, which Questie
-- hid itself, so it stays hidden (only its alpha comes back).
local function ReleaseFrame(frame, keepHidden)
    local st = held[frame]
    if not st or not st.held then return end
    if not keepHidden and st.wantShown and Blocked(frame) then
        afterCombat = true -- a protected frame can't be shown in combat
        return
    end
    st.held = false
    frame:SetAlpha(st.alpha or 1)
    if keepHidden then return end
    if st.wantShown then frame:Show() end
    -- Classic's watch frame shows itself only with quests watched: let it decide
    if frame == _G.QuestWatchFrame and type(_G.QuestWatch_Update) == "function"
        and not (frame.IsProtected and frame:IsProtected()) then
        pcall(_G.QuestWatch_Update)
    end
end

local function EachFrame(fn, ...)
    for _, name in ipairs(FRAMES) do
        local frame = _G[name]
        if type(frame) == "table" and frame.Hide and frame.SetAlpha then fn(frame, ...) end
    end
end

------------------------------------------------------------------------
-- Questie's tracker
------------------------------------------------------------------------

--- Questie's profile settings and its tracker module once Questie has
--- started, else nil.
local function QuestieParts()
    local Q, loader = _G.Questie, _G.QuestieLoader
    if type(Q) ~= "table" or type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return end
    local db = Q.db
    local profile = type(db) == "table" and db.profile
    if type(profile) ~= "table" then return end
    local ok, tracker = pcall(loader.ImportModule, loader, "QuestieTracker")
    if not ok or type(tracker) ~= "table" then return end
    if not (tracker.started or Q.started) then return end
    return profile, tracker
end

local function QuestieUpdate(tracker)
    if InCombat() then
        -- QuestieTracker:Update does nothing in combat
        questie.needUpdate = true
        afterCombat = true
        return
    end
    questie.needUpdate = false
    if tracker and type(tracker.Update) == "function" then pcall(tracker.Update, tracker) end
end

-- The player changing Questie's tracker themselves (its options or
-- "/questie tracker") wins: OpenXP lets go of it.
local function HookQuestie(tracker)
    if questie.hooked or type(hooksecurefunc) ~= "function" then return end
    questie.hooked = true
    for _, name in ipairs({ "Enable", "Disable", "Toggle" }) do
        if type(tracker[name]) == "function" then
            hooksecurefunc(tracker, name, function() questie.held = false end)
        end
    end
end

local function RetryQuestie()
    if questie.waiting or questie.tries >= QUESTIE_TRIES then return end
    if type(_G.QuestieLoader) ~= "table" and type(_G.Questie) ~= "table" then return end -- no Questie
    if not (C_Timer and C_Timer.After) then return end
    questie.waiting = true
    questie.tries = questie.tries + 1
    C_Timer.After(QUESTIE_WAIT, function()
        questie.waiting = false
        QT.ApplyQuestie()
    end)
end

function QT.ApplyQuestie()
    local profile, tracker = QuestieParts()
    if not profile then
        if QT.HideWanted() then RetryQuestie() end
        return
    end
    HookQuestie(tracker)
    if QT.HideWanted() then
        if not questie.held then
            questie.held = true
            questie.was = profile.trackerEnabled
        end
        if profile.trackerEnabled ~= false then
            profile.trackerEnabled = false
            QuestieUpdate(tracker)
        end
    elseif questie.held then
        questie.held = false
        profile.trackerEnabled = questie.was
        if questie.was ~= false then QuestieUpdate(tracker) end
    end
end

--- True when Questie's tracker is on (it then hides Blizzard's itself).
local function QuestieTrackerOn()
    local Q = _G.Questie
    local profile = type(Q) == "table" and type(Q.db) == "table" and Q.db.profile
    return type(profile) == "table" and profile.trackerEnabled == true
end

------------------------------------------------------------------------
-- Applying
------------------------------------------------------------------------

function QT.Apply()
    if QT.HideWanted() then
        EachFrame(HoldFrame)
        QT.ApplyQuestie()
    else
        QT.ApplyQuestie()
        EachFrame(ReleaseFrame, QuestieTrackerOn())
    end
end

OXP.OnReady(QT.Apply)
-- Forever's ObjectiveTrackerFrame comes from the Blizzard_ObjectiveTracker
-- addon: should it load after login, hide it then.
OXP.On("ADDON_LOADED", function(_, name)
    if OXP.isReady and name == "Blizzard_ObjectiveTracker" then QT.Apply() end
end)
OXP.Listen("SETTINGS_CHANGED", function() QT.Apply() end)

OXP.On("PLAYER_REGEN_ENABLED", function()
    if not afterCombat then return end
    afterCombat = false
    QT.Apply()
    if questie.needUpdate then
        local _, tracker = QuestieParts()
        QuestieUpdate(tracker)
    end
end)

-- Questie's saved settings keep the player's choice: OpenXP only turns its
-- tracker off for the session.
OXP.On("PLAYER_LOGOUT", function()
    if not questie.held then return end
    local Q = _G.Questie
    local profile = type(Q) == "table" and type(Q.db) == "table" and Q.db.profile
    if type(profile) == "table" then profile.trackerEnabled = questie.was end
end)
