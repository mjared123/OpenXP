-- Hearthstone state for the UI: cooldown and bind location. The button that
-- casts it lives in Buttons.lua (shown while a `hearth` goal is active).
--
--   OpenXP.QoL.GetHearth() -> { item, have, bind, ready, remaining, start, duration }
--     (one reused table: read it, do not keep it)
--   message QOL_HEARTH_CHANGED (fired on bind and cooldown changes)

local ADDON, ns = ...
local QoL = ns.QoL
local Client = QoL.Client

local GCD = 1.5 -- a cooldown this short is the global cooldown, not the Hearthstone's

local info = { item = Client.HEARTHSTONE }

function QoL.GetHearth()
	local id = Client.HEARTHSTONE
	local start, duration = Client.ItemCooldown(id)
	local remaining = 0
	if duration > GCD then
		remaining = start + duration - GetTime()
		if remaining < 0 then remaining = 0 end
	end
	info.have = Client.ItemCount(id) > 0
	info.bind = ns.Compat and ns.Compat.GetBindLocation and ns.Compat.GetBindLocation() or nil
	info.start, info.duration = start, duration
	info.remaining = remaining
	info.ready = info.have and remaining == 0
	return info
end

local lastRemaining
local function changed()
	ns.Fire("QOL_HEARTH_CHANGED", QoL.GetHearth())
end

ns.RegisterEvent("HEARTHSTONE_BOUND", changed)
ns.RegisterEvent("BAG_UPDATE_COOLDOWN", function()
	-- Fire only when the Hearthstone's own cooldown moved.
	local start, duration = Client.ItemCooldown(Client.HEARTHSTONE)
	local key = duration > GCD and start or 0
	if key ~= lastRemaining then
		lastRemaining = key
		changed()
	end
end)
