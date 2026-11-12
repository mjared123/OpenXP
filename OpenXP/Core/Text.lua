-- Text helpers: translation hook, guide colour tags, printing to chat.
--
-- Guide text marks names with tags like |cOXP_FRIENDLY_Llana|r. The game only
-- understands |cAARRGGBB colours, so Text.Format swaps each tag for a real
-- colour before the text is shown.
local ADDON, OXP = ...

local Text = {}
OXP.Text = Text

--- Translate a UI string. 2.0 ships English only for now; this is the one
--- place a locale table plugs in later.
function OXP.L(s)
    local t = OXP.locale
    return (t and t[s]) or s
end

Text.COLORS = {
    FRIENDLY = "FF66BB6A", -- people to talk to
    ENEMY = "FFFF7043",    -- things to kill
    LOOT = "FF26C6DA",     -- items to loot
    PICK = "FFF2C35C",     -- things to click or pick up
    WARN = "FFFF5252",     -- warnings
}

--- Guide text with its colour tags turned into game colours.
function Text.Format(s)
    if not s then return s end
    return (s:gsub("|cOXP_(%u+)_", function(kind)
        return "|c" .. (Text.COLORS[kind] or "FFFFFFFF")
    end))
end

--- Text with every colour and texture code removed (for measuring, tooltips
--- and comparisons).
function Text.Strip(s)
    if not s then return "" end
    s = s:gsub("|cOXP_%u+_", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return s
end

local PREFIX = "|cFF5AB8FFOpenXP:|r "

--- Print to chat with the OpenXP prefix. Extra arguments go through format.
function OXP.Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    print(PREFIX .. tostring(msg))
end

--- Same, but only when debug output is switched on (/oxp debug).
function OXP.Debug(msg, ...)
    if OXP.settings and OXP.settings.debug then OXP.Print("|cFF9E9E9E" .. tostring(msg) .. "|r", ...) end
end

Text.ADDON_PATH = "Interface\\AddOns\\" .. ADDON .. "\\"
