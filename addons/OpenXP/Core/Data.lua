-- OpenXP.Data: load-on-demand data packs (OpenXP_Codex and friends).
-- Contract: docs/ARCHITECTURE.md, "Core services: Data, Hooks, Search".
--
--   Data.Pack(name) -> loaded, reason|nil
--     Loads the pack once per session through C_AddOns.LoadAddOn. Never in
--     combat (returns false, "combat"; a later call out of combat tries
--     again). Any other failure is final for the session; reason is
--     LoadAddOn's second return in lower case ("missing", "disabled",
--     "interface_version", "dep_missing", ...), "unavailable" without the
--     API, "error" when the load itself raised.
--   Data.Info(name) -> { loaded, reason, memoryKB }
--     memoryKB from UpdateAddOnMemoryUsage/GetAddOnMemoryUsage (nil when the
--     client hides it).
--   Data.CheckInstall() -> missing, stale, retired
--     The release zip's folders beside OpenXP: names of the required ones
--     (OpenXP_Guides, OpenXP_Codex, the player's faction part) that are
--     not installed, and "name version" for every OpenXP_* folder in the
--     AddOns list, loaded or not, whose TOC version differs from OpenXP's
--     (OpenXP_Recorder, released on its own, left out; a folder or a
--     OpenXP without a version is unknown, never a mismatch).
--     retired: the locale codes whose old folders, OpenXP_Guides_<locale>
--     or OpenXP_Names_<locale> (before 0.3.0; the language folder
--     OpenXP_<locale> replaced both), are still installed. OpenXP never
--     loads them.
--     At login a non-empty result prints one line saying to reinstall: a
--     player who copied only some folders, or an old zip over a new one,
--     finds out; the old folders get a line of their own saying to delete
--     them.
--   Data.InstallLine() -> string|nil
--     A mixed install (stale non-empty) in one English line for the report
--     (UI/Report.lua).

local ADDON, ns = ...

local Data = {}
ns.Data = Data

local type, pcall, tostring = type, pcall, tostring
local lower = string.lower

local state = {} -- name -> { loaded = bool, reason = string|nil }

local readable = ns.Compat.Readable

local function alreadyLoaded(name)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
	if not isLoaded then return false end
	local ok, loading, loaded = pcall(isLoaded, name)
	if not ok then return false end
	if loaded == nil then loaded = loading end
	return readable(loaded) == true
end

function Data.Pack(name)
	if type(name) ~= "string" or name == "" then return false, "missing" end
	local s = state[name]
	if s then
		if s.loaded then return true end
		if s.reason ~= "combat" then return false, s.reason end
	end
	if alreadyLoaded(name) then
		state[name] = { loaded = true }
		return true
	end
	if InCombatLockdown and InCombatLockdown() then
		state[name] = { loaded = false, reason = "combat" }
		return false, "combat"
	end
	local load = C_AddOns and C_AddOns.LoadAddOn
	if not load then
		state[name] = { loaded = false, reason = "unavailable" }
		return false, "unavailable"
	end
	local ok, loaded, reason = pcall(load, name)
	if not ok then
		ns.Debug("Data.Pack:", name, tostring(loaded))
		state[name] = { loaded = false, reason = "error" }
		return false, "error"
	end
	loaded = readable(loaded)
	if loaded then
		state[name] = { loaded = true }
		return true
	end
	reason = readable(reason)
	reason = type(reason) == "string" and reason ~= "" and lower(reason) or "unknown"
	state[name] = { loaded = false, reason = reason }
	return false, reason
end

function Data.Info(name)
	local s = state[name]
	local info = { loaded = (s and s.loaded) or alreadyLoaded(name), reason = s and s.reason or nil }
	if info.loaded and UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		local ok = pcall(UpdateAddOnMemoryUsage)
		if ok then
			local got, kb = pcall(GetAddOnMemoryUsage, name)
			kb = got and readable(kb) or nil
			if type(kb) == "number" then info.memoryKB = kb end
		end
	end
	return info
end

-- Folders the release zip puts beside OpenXP. The first two must be there;
-- the walking routes (OpenXP_Nav), quest and item packs and the language
-- folder of the client's language (Names.PackName(), none in English) are optional
-- (the arrow falls back to straight lines, the interface, names and guide texts to English; a source
-- install may not build the packs), but when present they must be the same
-- version.
local COMPANIONS = { "OpenXP_Guides", "OpenXP_Codex", "OpenXP_Nav", "OpenXP_QuestDB", "OpenXP_ItemDB" }
local REQUIRED = { OpenXP_Guides = true, OpenXP_Codex = true }

local function installed(name)
	local A = C_AddOns
	if not A then return true end
	if alreadyLoaded(name) then return true end
	if A.DoesAddOnExist then
		local ok, exists = pcall(A.DoesAddOnExist, name)
		if ok then return readable(exists) == true end
	end
	if not A.GetAddOnInfo then return true end
	local ok, _, _, _, _, reason = pcall(A.GetAddOnInfo, name)
	return ok and readable(reason) ~= "MISSING"
end

local function versionOf(name)
	local get = C_AddOns and C_AddOns.GetAddOnMetadata
	if not get then return nil end
	local ok, v = pcall(get, name, "Version")
	v = ok and readable(v) or nil
	return type(v) == "string" and v ~= "" and v or nil
end

-- A version OpenXP can compare: a TOC without one, or a source checkout's
-- "dev", is unknown.
local function known(v)
	return type(v) == "string" and v ~= "" and v ~= "dev"
end

-- One folder of ours: not installed (and required) goes to missing; a known
-- version other than OpenXP's to stale as "name version". Each folder once.
local function check(name, s)
	if s.seen[name] then return end
	s.seen[name] = true
	if not installed(name) then
		if REQUIRED[name] then s.missing[#s.missing + 1] = name end
	else
		local v = versionOf(name)
		if known(v) and known(s.mine) and v ~= s.mine then s.stale[#s.stale + 1] = name .. " " .. v end
	end
end

-- Every client language's folder before 0.3.0 had two: its guide texts and
-- its names. OpenXP_<locale> holds both now.
local LOCALES = { "deDE", "esES", "esMX", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local function retiredLocales()
	local out = {}
	if not (C_AddOns and (C_AddOns.DoesAddOnExist or C_AddOns.GetAddOnInfo)) then return out end
	for _, l in ipairs(LOCALES) do
		if installed("OpenXP_Guides_" .. l) or installed("OpenXP_Names_" .. l) then out[#out + 1] = l end
	end
	return out
end

-- Not ours to compare: the Recorder ships in a zip of its own and is updated
-- on its own.
local SEPARATE = { OpenXP_Recorder = true }

-- Every other OpenXP_* folder in the AddOns list, loaded or not: the parts
-- for the other races and faction, the other languages, the walking maps'
-- continents. Community addons are never named OpenXP_* (pack.json refuses
-- the prefix); the old language folders have a line of their own.
local function listed()
	local out = {}
	local A = C_AddOns or {}
	local count, info = A.GetNumAddOns or GetNumAddOns, A.GetAddOnInfo or GetAddOnInfo
	if not (count and info) then return out end
	local ok, n = pcall(count)
	n = ok and readable(n) or nil
	if type(n) ~= "number" then return out end
	local retired = {}
	for _, l in ipairs(LOCALES) do
		retired["OpenXP_Guides_" .. l], retired["OpenXP_Names_" .. l] = true, true
	end
	for i = 1, n do
		local got, name = pcall(info, i)
		name = got and readable(name) or nil
		if type(name) == "string" and name:find("^OpenXP_") and not SEPARATE[name] and not retired[name] then out[#out + 1] = name end
	end
	return out
end

function Data.CheckInstall()
	local s = { missing = {}, stale = {}, seen = {}, mine = ns.version }
	for _, name in ipairs(COMPANIONS) do check(name, s) end
	-- The language folder of the client's language (our guides' texts and
	-- the game's names, Core/Names.lua and Core/GuideTexts.lua load it): never
	-- missing either.
	local language = ns.Names and ns.Names.PackName()
	if language then check(language, s) end
	-- Our guide pack's race part for the player's race, when the release has
	-- one (Core/Guides.lua loads it): never missing either.
	local race = UnitRace and readable((select(2, UnitRace("player")))) or nil
	if type(race) == "string" and race ~= "" then check("OpenXP_Guides_" .. race, s) end
	-- Our guide pack's part for the player's faction (format 8; Core/Guides.lua
	-- loads it): every release has it, and without it the player has no
	-- leveling guides.
	local faction = ns.Compat.GetPlayerFaction and ns.Compat.GetPlayerFaction()
	if faction and installed("OpenXP_Guides") then
		local part = "OpenXP_Guides_" .. faction
		if installed(part) then
			check(part, s)
		else
			s.seen[part] = true
			s.missing[#s.missing + 1] = part
		end
	end
	for _, name in ipairs(listed()) do check(name, s) end
	return s.missing, s.stale, retiredLocales()
end

-- A mixed install in one English line for the report (UI/Report.lua), or nil
-- when every folder is OpenXP's version: "mixed: OpenXP 0.3.5,
-- OpenXP_Guides 0.3.4".
function Data.InstallLine()
	local _, stale = Data.CheckInstall()
	if #stale == 0 then return nil end
	return "mixed: OpenXP " .. tostring(ns.version) .. ", " .. table.concat(stale, ", ")
end

ns.OnLogin(function()
	local missing, stale, retired = Data.CheckInstall()
	if #retired > 0 then
		ns.Print(string.format(ns.L["OpenXP no longer uses the old folders OpenXP_Guides_<language> and OpenXP_Names_<language> (%s): OpenXP_<language> holds both now. Close the game and delete them from Interface/AddOns."],
			table.concat(retired, ", ")))
	end
	if #missing == 0 and #stale == 0 then return end
	local list = { "OpenXP " .. tostring(ns.version) }
	for _, v in ipairs(stale) do list[#list + 1] = v end
	if #missing > 0 then list[#list + 1] = string.format(ns.L["%s not installed"], table.concat(missing, ", ")) end
	ns.Print(string.format(ns.L["Your install is mixed or incomplete (%s). Close the game, delete every OpenXP folder in Interface/AddOns and install OpenXP again: with the OpenXP Client, the CurseForge app, or the latest zip from GitHub Releases (not \"Source code\")."],
		table.concat(list, ", ")))
end)
