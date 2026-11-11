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
local BUILTIN = {
    {key = "default", name = "Arial Narrow (OpenXP default)", path = "Fonts\\ARIALN.TTF"},
    {key = "friz", name = "Friz Quadrata (game text)", path = "Fonts\\FRIZQT__.TTF"},
    {key = "morpheus", name = "Morpheus", path = "Fonts\\MORPHEUS.TTF"},
    {key = "skurri", name = "Skurri", path = "Fonts\\SKURRI.TTF"},
}
local builtinByKey = {}
for _, f in ipairs(BUILTIN) do builtinByKey[f.key] = f end

local function NormPath(path)
    return tostring(path or ""):lower():gsub("/", "\\")
end

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- SetFont returns false for a path the client can't load; check once per
-- path so a missing or broken font file falls back to the default.
local probe, checked = nil, {}
local function Loads(path)
    if checked[path] ~= nil then return checked[path] end
    if not probe and CreateFrame then
        local ok, frame = pcall(CreateFrame, "Frame")
        probe = ok and frame and frame.CreateFontString and frame:CreateFontString()
    end
    local good = true
    if probe and probe.SetFont then
        local ok, res = pcall(probe.SetFont, probe, path, 12, "")
        good = ok and res ~= false
    end
    checked[path] = good
    return good
end

-- {value = label} for the settings dropdown, plus a sorted key list.
function fonts.Choices()
    local values, order, seen = {}, {}, {}
    for _, f in ipairs(BUILTIN) do
        values[f.key] = f.name
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
    if builtinByKey[key] then
        path = builtinByKey[key].path
    elseif type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lsm = LSM()
        path = lsm and lsm:Fetch("font", key:sub(5), true)
    end
    if not path or not Loads(path) then path = builtinByKey.default.path end
    return addon.SafeFont(path)
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

function addon.locale.AddGenericTranslation(source,translation)
    if source == getForeign(source) then
        lazyTranslationCache[source] = translation
    end
end
