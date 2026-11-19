local addonName, addon = ...

local ssplit, strjoin, ipairs, unpack, next = strsplittable, strjoin, ipairs, unpack, next

addon = LibStub("AceAddon-3.0"):NewAddon(addon, addonName, "AceEvent-3.0")

addon.locale = {}

-- OpenXP's look uses Fonts\ARIALN.TTF, which only has Latin letters on
-- most clients. On Chinese, Korean and Russian clients those glyphs are
-- missing and names show as squares, so use the client's own text font
-- there (STANDARD_TEXT_FONT is the localized font Blizzard's UI uses).
local LATIN_LOCALES = {enUS = true, enGB = true, deDE = true, frFR = true,
                       esES = true, esMX = true, ptBR = true, itIT = true}
local clientLocale = GetLocale and GetLocale() or "enUS"
addon.latinFontsOk = LATIN_LOCALES[clientLocale] == true

local function ClientFont()
    if _G.STANDARD_TEXT_FONT then return _G.STANDARD_TEXT_FONT end
    local obj = _G.GameFontNormal or _G.GameFontHighlight
    local path = obj and obj.GetFont and obj:GetFont()
    return path or "Fonts\\FRIZQT__.TTF"
end

-- Blizzard's Latin-only fonts; any other path (e.g. a font a user picked
-- from SharedMedia) is kept as is.
local LATIN_ONLY_FONTS = {["fonts\\arialn.ttf"] = true, ["fonts\\frizqt__.ttf"] = true,
                          ["fonts\\morpheus.ttf"] = true, ["fonts\\skurri.ttf"] = true}

-- Returns a font path that can draw this client's language.
function addon.SafeFont(path)
    if addon.latinFontsOk then return path or "Fonts\\ARIALN.TTF" end
    if not path or path == "" then return ClientFont() end
    local key = tostring(path):lower():gsub("/", "\\")
    if LATIN_ONLY_FONTS[key] then return ClientFont() end
    return path
end

-- Font choice (Settings > Guide Window > Font). Players can pick one of the
-- game's own fonts, or any font another addon has shared through
-- LibSharedMedia-3.0 (ElvUI, Details, SharedMedia and many others ship it).
-- The setting stores the font's name; the path is looked up each time, so
-- a SharedMedia font that registers late still gets picked up.
local fonts = {}
addon.fonts = fonts

fonts.DEFAULT = "default"
-- OpenXP ships a few fonts picked for easy reading (Fonts/, all under the
-- SIL Open Font License, see Fonts/licenses). They're listed first.
local OWN = "Interface\\AddOns\\" .. addonName .. "\\Fonts\\"
local BUILTIN = {
    {key = "default", name = "Arial Narrow (OpenXP default)", path = "Fonts\\ARIALN.TTF"},
    {key = "atkinson", name = "Atkinson Hyperlegible (made for low vision)",
     path = OWN .. "AtkinsonHyperlegible-Regular.ttf"},
    {key = "atkinsonbold", name = "Atkinson Hyperlegible Bold",
     path = OWN .. "AtkinsonHyperlegible-Bold.ttf"},
    {key = "lexend", name = "Lexend (wide, easy reading)", path = OWN .. "Lexend-Regular.ttf"},
    {key = "opensans", cyrillic = true, name = "Open Sans", path = OWN .. "OpenSans-Regular.ttf"},
    {key = "roboto", cyrillic = true, name = "Roboto", path = OWN .. "Roboto-Regular.ttf"},
    {key = "notosans", cyrillic = true, name = "Noto Sans", path = OWN .. "NotoSans-Regular.ttf"},
    {key = "firasans", cyrillic = true, name = "Fira Sans", path = OWN .. "FiraSans-Regular.ttf"},
    {key = "friz", name = "Friz Quadrata (game text)", path = "Fonts\\FRIZQT__.TTF"},
    {key = "morpheus", name = "Morpheus (game, decorative)", path = "Fonts\\MORPHEUS.TTF"},
    {key = "skurri", name = "Skurri (game, decorative)", path = "Fonts\\SKURRI.TTF"},
}
local builtinByKey = {}
for _, f in ipairs(BUILTIN) do builtinByKey[f.key] = f end

local function NormPath(path)
    return tostring(path or ""):lower():gsub("/", "\\")
end

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- SetFont returns false for a path the client can't load. A good result
-- is kept; a failed one is tried again after a few seconds, because a font
-- file can fail while the game is still loading it, and a font that failed
-- once must not stay on the fallback for the whole session.
local probe, good, lastTry = nil, {}, {}
local function Probe()
    if not probe and CreateFrame then
        local ok, frame = pcall(CreateFrame, "Frame", nil, UIParent)
        -- no SetText here: text on a font string with no font yet is a Lua
        -- error, and this runs while OpenXPCard.lua is still loading (1.3.42)
        probe = ok and frame and frame.CreateFontString and frame:CreateFontString(nil, "OVERLAY")
    end
    return probe
end
local function Loads(path)
    if good[path] then return true end
    local now = GetTime and GetTime() or 0
    if lastTry[path] and now - lastTry[path] < 3 then return false end
    lastTry[path] = now
    local fs = Probe()
    local result = true
    if fs and fs.SetFont then
        local ok, res = pcall(fs.SetFont, fs, path, 12, "")
        result = ok and res ~= false
    end
    if result then good[path] = true end
    return result
end
fonts.Loads = Loads

-- {value = label} for the settings dropdown, plus a sorted key list.
function fonts.Choices()
    local values, order, seen = {}, {}, {}
    for _, f in ipairs(BUILTIN) do
        values[f.key] = addon.locale.Get(f.name)
        order[#order + 1] = f.key
        seen[NormPath(f.path)] = true
    end
    local lsm = LSM()
    if lsm then
        local list = lsm:List("font") or {}
        local shared = {}
        for _, name in ipairs(list) do
            local path = lsm:Fetch("font", name, true)
            if path and not seen[NormPath(path)] then
                seen[NormPath(path)] = true
                shared[#shared + 1] = name
            end
        end
        table.sort(shared, function(a, b) return a:lower() < b:lower() end)
        for _, name in ipairs(shared) do
            values["lsm:" .. name] = name
            order[#order + 1] = "lsm:" .. name
        end
    end
    return values, order
end

-- Path of the chosen font, made safe for this client's language.
function fonts.Path()
    local p = addon.settings and addon.settings.profile
    local key = (p and p.guideFont) or fonts.DEFAULT
    local path
    local own = builtinByKey[key]
    if own then
        path = own.path
        -- OpenXP's own fonts only draw Latin (and some Cyrillic) letters;
        -- other clients keep their own text font
        if own.path:find("AddOns", 1, true) and not addon.latinFontsOk
            and not (clientLocale == "ruRU" and own.cyrillic) then
            return addon.SafeFont(nil)
        end
    elseif type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lsm = LSM()
        path = lsm and lsm:Fetch("font", key:sub(5), true)
    end
    -- No load check here: a test font string can report a failure for a
    -- font that works (1.3.40-1.3.42 fell back to Arial for every choice).
    -- The card checks the real SetFont result instead (OpenXPCard ApplyFont).
    if not path then path = builtinByKey.default.path end
    return addon.SafeFont(path)
end

-- /oxp fonts: what each font in the list resolves to and whether it loads
function fonts.Report()
    local values, order = fonts.Choices()
    local p = addon.settings and addon.settings.profile
    local fmt = string.format
    local L = addon.locale.Get
    print(fmt(L("|cFF66BB6AOpenXP fonts|r (chosen: %s, using %s)"), tostring(p and p.guideFont), fonts.Path()))
    for _, key in ipairs(order) do
        local path
        if builtinByKey[key] then
            path = builtinByKey[key].path
        else
            local lsm = LSM()
            path = lsm and lsm:Fetch("font", key:sub(5), true)
        end
        local ok = path and Loads(path)
        print(fmt("  %s %s: %s", ok and "|cFF3DBB7Aok|r" or "|cFFFF7043" .. L("FAILED") .. "|r",
                            values[key], tostring(path)))
    end
end

-- "", "OUTLINE" or "THICKOUTLINE": an outline makes text easier to pick out
-- against busy backgrounds.
function fonts.Outline()
    local p = addon.settings and addon.settings.profile
    local o = p and p.guideFontOutline
    if o == "OUTLINE" or o == "THICKOUTLINE" then return o end
    return ""
end

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local delim = L.delimiter

local DEBUG = false -- One of the first files loaded, so no settings
local lazyTranslationCache = {}

if DEBUG then print(addonName .. ": Processing locale: " .. GetLocale()) end

local function getForeign(text)
    if not text then return end
    if L[text] then return L[text] end

    if lazyTranslationCache[text] then return lazyTranslationCache[text] end

    if next(L.words) == nil then
        -- No custom words added
        lazyTranslationCache[text] = text
        return text
    end

    if DEBUG then print("Phrase not found, looking for words") end

    -- Direct text doesn't match, so iterate over phrase and lazy translate
    local words = ssplit(delim, text)

    -- TODO string insensitive lookups
    for i, w in ipairs(words) do if L.words[w] then words[i] = L.words[w] end end

    local lazyPhrase = strjoin(delim, unpack(words))
    lazyTranslationCache[text] = lazyPhrase

    return lazyPhrase
end

local function noop(text) return text end

local locale = GetLocale()

-- TODO check if L returned language, remove explicit list
-- Explicitly check supported languages, default to enUS
if locale == 'zhCN' or locale == 'zhTW' or locale == 'frFR' or locale == 'koKR' or locale == 'esES' or locale == 'esMX' or locale == 'ruRU' or
    locale == 'deDE' or locale == 'ptBR' then
    addon.locale.Get = getForeign
else
    addon.locale.Get = noop
end

---------------------------------------------------------------------------
-- Guide step text in the player's language
---------------------------------------------------------------------------
-- The guides are written in English. A language's locale\<loc>_guide.lua
-- sets addon.guidePhrases: English step text -> translation, keyed by a
-- "skeleton" where names, icons, [item] links and numbers are {A}, {B}, ...
-- so one sentence covers every step that only differs in those. Friendly
-- and enemy names use the realm's NPC data when available (NPCnames.lua).
-- Text with no translation stays English. tools/locale/guide_skeleton.py
-- builds the same keys: change both together.

local guideTextCache = {}
local NAME_KINDS = {FRIENDLY = true, ENEMY = true, LOOT = true, PICK = true}

function addon.locale.GuideLabel(text)
    if not text then return end
    if not addon.guideTitles then return text end
    return addon.guideTitles[text] or addon.locale.Get(text)
end

-- Prefer the name shown in the journal when the client has loaded it.
function addon.locale.GuideQuestName(id)
    if not (addon.guideQuestNames and id) then return end
    local getTitle = C_QuestLog and (C_QuestLog.GetTitleForQuestID or C_QuestLog.GetQuestInfo)
    local title = getTitle and getTitle(id)
    if type(title) == "string" and title ~= "" then return title end
    local db = addon.game == "FOREVER" and _G.LibQuestieDB
    local quests = db and db.Quest
    title = quests and quests.name and quests.name(id)
    if type(title) == "string" and title ~= "" then return title end
    return addon.guideQuestNames[id]
end

local function FrenchGuideName(name, kind)
    local names = addon.guideNamesFr
    if not names then return end
    local base, suffix = name:match("^(.-)(::%d+)$")
    base = base or name
    local db = addon.game == "FOREVER" and _G.LibQuestieDB
    local objects = db and db.Object
    local translated
    if kind == "PICK" and addon.game == "FOREVER" then
        local id = addon.guideObjectIdsFr and addon.guideObjectIdsFr[base]
        translated = id and objects and objects.name and objects.name(id)
        if not translated or translated == "" then
            translated = addon.guideObjectNamesFr and addon.guideObjectNamesFr[base]
        end
    end
    local creature = kind == "FRIENDLY" or kind == "ENEMY"
    local ref = not translated and not creature and addon.guideNameIds and addon.guideNameIds[base]
    if ref and ref[1] == "spell" then
        local getSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
        translated = getSpellName and getSpellName(ref[2])
    elseif ref and ref[1] == "item" then
        local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        translated = getItemInfo and getItemInfo(ref[2])
        if not translated or translated == "" then
            local items = db and db.Item
            translated = items and items.name and items.name(ref[2])
        end
    elseif ref and ref[1] == "object" then
        translated = objects and objects.name and objects.name(ref[2])
    end
    if not translated or translated == "" then translated = names[base] end
    if translated then return translated .. (suffix or "") end
end

function addon.locale.GuideTerm(name)
    if not name then return end
    return FrenchGuideName(name) or addon.locale.GuideLabel(name)
end

local function LocalName(raw)
    local localized = raw:gsub("|cRXP_(%u+)_([^|]*)|r", function(kind, name)
        if not NAME_KINDS[kind] then return end
        local creature = kind == "FRIENDLY" or kind == "ENEMY"
        local translated = creature and addon.GetForeverCreatureName and addon.GetForeverCreatureName(name)
        translated = translated or FrenchGuideName(name, kind)
        if not translated and creature and addon.GetCreatureName then translated = addon.GetCreatureName(name) end
        if translated then return "|cRXP_" .. kind .. "_" .. translated .. "|r" end
    end)
    if addon.guideNamesFr then
        localized = localized:gsub("%[([^|%[%]]+)%]", function(name)
            local translated = FrenchGuideName(name)
            if translated then return "[" .. translated .. "]" end
        end)
    end
    return localized
end

function addon.locale.GuideText(text)
    local phrases = addon.guidePhrases
    if not phrases or type(text) ~= "string" or text == "" then return text end
    local cached = guideTextCache[text]
    if cached then return cached end
    local result = text
    local body, suffix = text:match("^(.-)(%s*<<.*)$")
    if not body then body, suffix = text, "" end
    body = body:gsub("%s+$", "")
    if addon.guideNamesFr then body = body:gsub("^%s+", "") end
    local slots, n = {}, 0
    local function slot(s)
        n = n + 1
        slots[n] = s
        if n > 26 then return s end
        return "{" .. string.char(64 + n) .. "}"
    end
    local key = body:gsub("(|cRXP_(%u+)_.-|r)", function(all, kind)
        if NAME_KINDS[kind] then return slot(all) end
    end)
    key = key:gsub("|T.-|t", slot)
    key = key:gsub("%[.-%]", slot)
    key = key:gsub("%d+%.%d+", slot)
    key = key:gsub("%d+", slot)
    local tr = n <= 26 and phrases[key] or phrases[body]
    if tr then
        -- Names inside a coloured warning are literal in its template.
        if addon.guideNamesFr then tr = LocalName(tr) end
        local function expand(c)
            local index = c:byte() - 64
            local s = slots[index]
            if s then
                return LocalName((s:gsub("{(%u)}", function(inner)
                    if inner < c then return expand(inner) end
                end)))
            end
        end
        result = tr:gsub("{(%u)}", expand) .. suffix
    elseif addon.guideNamesFr then
        result = LocalName(text)
    end
    guideTextCache[text] = result
    return result
end

function addon.locale.AddGenericTranslation(source,translation)
    if source == getForeign(source) then
        lazyTranslationCache[source] = translation
    end
end

---------------------------------------------------------------------------
-- /oxp perf: how long OpenXP's own work takes while you play
---------------------------------------------------------------------------
-- (Kept in this file, which loads first, rather than a new one: WoW only
-- loads new addon files after a full restart, and every other file wraps
-- its timers and frame updates with perf.Wrap as it loads.)
--
-- /oxp perf records for 30 seconds: for each part of OpenXP, how often it
-- ran, its average and slowest time, and how many runs took 5 ms or more;
-- plus frames that took 50 ms or more (hitches) and how fast Lua memory
-- grew (lots of garbage makes the game pause to clean it up). Costs
-- nothing while it isn't recording.

local perf = {on = false, stats = {}}
addon.perf = perf
local clock = debugprofilestop or function() return 0 end

local function Done(name, t0, ...)
    local ms = clock() - t0
    local s = perf.stats[name]
    if not s then
        s = {n = 0, total = 0, max = 0, slow = 0}
        perf.stats[name] = s
    end
    s.n = s.n + 1
    s.total = s.total + ms
    if ms > s.max then s.max = ms end
    if ms >= 5 then s.slow = s.slow + 1 end
    return ...
end

-- fn, timed as `name` while recording
function perf.Wrap(name, fn)
    if type(fn) ~= "function" then return fn end
    return function(...)
        if not perf.on then return fn(...) end
        return Done(name, clock(), fn(...))
    end
end

local SECONDS = 30
local frame
local function Say(s) print("|cFF66BB6AOpenXP:|r " .. s) end

local function Report()
    perf.on = false
    if frame then frame:SetScript("OnUpdate", nil) end
    local secs = math.max(perf.elapsed or 0, 0.001)
    local rows = {}
    local total = 0
    for name, s in pairs(perf.stats) do
        rows[#rows + 1] = {name = name, s = s}
        total = total + s.total
    end
    table.sort(rows, function(a, b) return a.s.total > b.s.total end)
    local L = addon.locale.Get
    Say(string.format(L("perf: %.0f s, %d frames, %d hitches (frames of 50 ms or more), slowest frame %.0f ms"),
        secs, perf.frames or 0, perf.hitches or 0, perf.worstFrame or 0))
    Say(string.format(L("OpenXP total: %.2f ms per second; Lua memory grew %.0f KB per second"),
        total / secs, (perf.grew or 0) / secs))
    for i = 1, math.min(#rows, 12) do
        local r, s = rows[i], rows[i].s
        Say(string.format(L("  %s: %d runs, avg %.2f ms, slowest %.1f ms, %d of 5 ms or more"),
            r.name, s.n, s.total / math.max(s.n, 1), s.max, s.slow))
    end
    if #rows == 0 then Say(L("  nothing of OpenXP's ran")) end
end

function perf.Start()
    if perf.on then return Report() end
    perf.stats = {}
    perf.elapsed, perf.frames, perf.hitches, perf.worstFrame, perf.grew = 0, 0, 0, 0, 0
    perf.on = true
    frame = frame or CreateFrame("Frame")
    local lastMem = collectgarbage("count")
    frame:SetScript("OnUpdate", function(_, dt)
        perf.elapsed = perf.elapsed + dt
        perf.frames = perf.frames + 1
        local ms = dt * 1000
        if ms >= 50 then perf.hitches = perf.hitches + 1 end
        if ms > perf.worstFrame then perf.worstFrame = ms end
        local mem = collectgarbage("count")
        if mem > lastMem then perf.grew = perf.grew + mem - lastMem end
        lastMem = mem
        if perf.elapsed >= SECONDS then Report() end
    end)
    Say(string.format(addon.locale.Get("recording for %d seconds: run around like you normally would (/oxp perf again stops early)"), SECONDS))
end
