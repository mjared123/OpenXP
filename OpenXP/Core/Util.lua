-- Small helpers shared by every module.
local _, OXP = ...

local Util = {}
OXP.Util = Util

function Util.Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Split `s` on the literal separator `sep`, trimming each piece and
--- dropping empty ones.
function Util.Split(s, sep)
    local out, start = {}, 1
    while true do
        local i, j = s:find(sep, start, true)
        local piece = Util.Trim(s:sub(start, (i or 0) - 1))
        if piece ~= "" then out[#out + 1] = piece end
        if not i then break end
        start = j + 1
    end
    return out
end

--- Fill missing keys of `t` from `defaults`, recursing into tables.
function Util.ApplyDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            Util.ApplyDefaults(t[k], v)
        elseif t[k] == nil then
            t[k] = v
        end
    end
    return t
end

--- Lower-case a place name and drop punctuation and extra spaces, so
--- "Tarren Mill, Hillsbrad" and "tarren mill" compare by their words.
function Util.PlaceKey(s)
    if not s then return nil end
    s = s:lower():gsub("[%p]", " "):gsub("%s+", " ")
    return Util.Trim(s)
end

-- Map icons come in 128, 64 and 32 px (Media/Map/name, name_64, name_32):
-- the game draws addon textures without mipmaps, so a big file shrunk to a
-- few pixels comes out jagged. Pick the smallest file at least as big as the
-- icon on screen (in real pixels: Retina and UI scale counted).
local pixelRatio
function Util.PixelsPerPoint()
    if pixelRatio then return pixelRatio end
    local h = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize())
    pixelRatio = (h and h > 0) and h / 768 or 1
    return pixelRatio
end

--- The file of a map icon for `size` points on `region` (its scale counted).
function Util.IconFile(base, size, region)
    local scale = region and region.GetEffectiveScale and region:GetEffectiveScale() or 1
    local px = (size or 16) * (scale or 1) * Util.PixelsPerPoint()
    if px <= 36 then return base .. "_32" end
    if px <= 72 then return base .. "_64" end
    return base
end
