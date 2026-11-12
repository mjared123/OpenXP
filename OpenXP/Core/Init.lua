-- OpenXP 2.0: the addon namespace, game events, internal messages and startup.
--
-- Every file gets the same namespace table through `local _, OXP = ...`.
-- Modules talk to each other through plain functions on OXP.<Module> and
-- through messages (OXP.Send / OXP.Listen), never through globals.
local ADDON, OXP = ...

OXP.name = ADDON
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
OXP.version = getMeta and getMeta(ADDON, "Version") or "dev"

-- Report an error without stopping the caller (one broken listener must not
-- break the others).
local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(err)
    else
        print(err)
    end
end

local function safeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then report(err) end
end

------------------------------------------------------------------------
-- Game events
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

--- Call fn(event, ...) whenever the game fires `event`.
function OXP.On(event, fn)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        eventFrame:RegisterEvent(event)
    end
    list[#list + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        safeCall(list[i], event, ...)
    end
end)

------------------------------------------------------------------------
-- Internal messages (engine -> UI and module -> module)
------------------------------------------------------------------------
local listeners = {}

--- Call fn(message, ...) whenever OXP.Send(message, ...) is called.
function OXP.Listen(message, fn)
    local list = listeners[message]
    if not list then
        list = {}
        listeners[message] = list
    end
    list[#list + 1] = fn
end

function OXP.Send(message, ...)
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        safeCall(list[i], message, ...)
    end
end

------------------------------------------------------------------------
-- Coalesced work: many events in one frame cause one run.
------------------------------------------------------------------------
local pending = {}

--- Run fn once on the next frame, however many times Soon(key, fn) is
--- called before then.
function OXP.Soon(key, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(0, function()
        pending[key] = nil
        safeCall(fn)
    end)
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------
local loadedCallbacks, readyCallbacks = {}, {}
OXP.isReady = false

--- fn() runs once the saved variables are loaded (ADDON_LOADED).
function OXP.OnLoaded(fn) loadedCallbacks[#loadedCallbacks + 1] = fn end

--- fn() runs once the player is in the world (PLAYER_LOGIN), after every
--- OnLoaded callback. Registered after login, it runs at once.
function OXP.OnReady(fn)
    if OXP.isReady then
        safeCall(fn)
    else
        readyCallbacks[#readyCallbacks + 1] = fn
    end
end

OXP.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    for i = 1, #loadedCallbacks do safeCall(loadedCallbacks[i]) end
end)

OXP.On("PLAYER_LOGIN", function()
    OXP.isReady = true
    for i = 1, #readyCallbacks do safeCall(readyCallbacks[i]) end
    OXP.Send("READY")
end)

OXP.report = report
