-- Fonts for the card and arrow (Settings > Font).
--
-- OpenXP ships a few fonts picked for easy reading (Media/Fonts, all under
-- the SIL Open Font License, see Media/Fonts/licenses), plus the game's own
-- and any font another addon shares through LibSharedMedia-3.0.
--
-- On the Forever client a test SetFont on a hidden font string reports
-- failure for every font, so a font is never judged by a probe: Apply checks
-- the real SetFont result and falls back to the default only then.
local ADDON, OXP = ...

local Fonts = {}
OXP.Fonts = Fonts

local OWN = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Fonts\\"
local DEFAULT_PATH = "Fonts\\ARIALN.TTF"

Fonts.LIST = {
    { key = "default", name = "Arial Narrow (OpenXP default)", path = DEFAULT_PATH },
    { key = "atkinson", name = "Atkinson Hyperlegible (made for low vision)", path = OWN .. "AtkinsonHyperlegible-Regular.ttf" },
    { key = "atkinsonbold", name = "Atkinson Hyperlegible Bold", path = OWN .. "AtkinsonHyperlegible-Bold.ttf" },
    { key = "lexend", name = "Lexend (wide, easy reading)", path = OWN .. "Lexend-Regular.ttf" },
    { key = "opensans", cyrillic = true, name = "Open Sans", path = OWN .. "OpenSans-Regular.ttf" },
    { key = "roboto", cyrillic = true, name = "Roboto", path = OWN .. "Roboto-Regular.ttf" },
    { key = "notosans", cyrillic = true, name = "Noto Sans", path = OWN .. "NotoSans-Regular.ttf" },
    { key = "firasans", cyrillic = true, name = "Fira Sans", path = OWN .. "FiraSans-Regular.ttf" },
    { key = "friz", name = "Friz Quadrata (game text)", path = "Fonts\\FRIZQT__.TTF" },
    { key = "morpheus", name = "Morpheus (game, decorative)", path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri", name = "Skurri (game, decorative)", path = "Fonts\\SKURRI.TTF" },
}
local byKey = {}
for _, f in ipairs(Fonts.LIST) do byKey[f.key] = f end

local locale = GetLocale and GetLocale() or "enUS"
local LATIN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, itIT = true, ptBR = true }

-- A font that can draw this client's language: Latin fonts only on Latin
-- clients (Open Sans and friends also draw Cyrillic).
local function ClientFont()
    local obj = _G.GameFontNormal
    local path = obj and obj.GetFont and obj:GetFont()
    return path or "Fonts\\FRIZQT__.TTF"
end

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

--- { key = label } for the settings list, plus the keys in order.
function Fonts.Choices()
    local values, order, seen = {}, {}, {}
    for _, f in ipairs(Fonts.LIST) do
        values[f.key] = f.name
        order[#order + 1] = f.key
        seen[f.path:lower()] = true
    end
    local lsm = LSM()
    if lsm then
        local shared = {}
        for _, name in ipairs(lsm:List("font") or {}) do
            local path = lsm:Fetch("font", name, true)
            if path and not seen[path:lower()] then
                seen[path:lower()] = true
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

--- Path of the chosen font, safe for this client's language.
function Fonts.Path()
    local key = OXP.settings and OXP.settings.font or "default"
    local f = byKey[key]
    if f then
        if not LATIN[locale] and not (locale == "ruRU" and f.cyrillic) then return ClientFont() end
        return f.path
    end
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lsm = LSM()
        local path = lsm and lsm:Fetch("font", key:sub(5), true)
        if path then return path end
    end
    return LATIN[locale] and DEFAULT_PATH or ClientFont()
end

--- "", "OUTLINE" or "THICKOUTLINE" from the Text outline setting. Text that
--- has its own outline (the arrow) only changes for a thick one.
function Fonts.Flags(own)
    local chosen = OXP.settings and OXP.settings.fontOutline or ""
    if chosen ~= "OUTLINE" and chosen ~= "THICKOUTLINE" then return own or "" end
    if own and own ~= "" and chosen ~= "THICKOUTLINE" then return own end
    return chosen
end

local strings = setmetatable({}, { __mode = "k" })

--- Set a font on a font string; if the game refuses it, use the default so
--- the text never goes blank.
function Fonts.Apply(fs, font, size, flags)
    strings[fs] = true
    local ok, res = pcall(fs.SetFont, fs, font, size, flags or "")
    if (not ok or res == false) and font ~= DEFAULT_PATH then
        pcall(fs.SetFont, fs, DEFAULT_PATH, size, flags or "")
    end
end

--- A font file the game hasn't drawn yet loads in the background: text set
--- right after the switch stays blank until it is set again.
function Fonts.Reapply()
    for fs in pairs(strings) do
        local ok, text = pcall(fs.GetText, fs)
        if ok and text and text ~= "" then
            pcall(fs.SetText, fs, "")
            pcall(fs.SetText, fs, text)
        end
    end
end

function Fonts.Changed()
    OXP.Send("SETTINGS_CHANGED")
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function() Fonts.Reapply(); OXP.Send("SETTINGS_CHANGED") end)
        C_Timer.After(0.6, function() Fonts.Reapply(); OXP.Send("SETTINGS_CHANGED") end)
    end
end

OXP.AddCommand("fonts", "list the fonts OpenXP can use", function()
    local values, order = Fonts.Choices()
    OXP.Print("Fonts (using %s):", Fonts.Path())
    for _, key in ipairs(order) do print("  " .. key .. " - " .. values[key]) end
end)
