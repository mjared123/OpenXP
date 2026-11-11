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
