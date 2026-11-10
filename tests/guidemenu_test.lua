-- Guide menu layout (GuideWindow.lua addon.BuildLevelMenu): every race's
-- starting zones are listed (your race first), then Levels 10-19, 20-29 ...
-- in level order. Uses the real guide names from the Forever guide files.
local ROOT = ...

local function readfile(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

-- pull just the menu block out of GuideWindow.lua
local src = readfile(ROOT .. "/GuideWindow.lua")
local first = src:find("local STARTER_RACES = {", 1, true)
local last = src:find("local function SwapNames(name)", 1, true)
assert(first and last, "menu block not found")
local block = src:sub(first, last - 1)

local failures = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then failures = failures + 1 end
end

local function run(faction, playerTags, guideFiles)
    local addon = {}
    addon.applies = function(text)
        for tag in text:gmatch("%S+") do
            local any = false
            for alt in tag:gmatch("[^/]+") do
                local neg = alt:sub(1, 1) == "!"
                local has = playerTags[neg and alt:sub(2) or alt] or false
                if neg then has = not has end
                if has then any = true end
            end
            if not any then return false end
        end
        return true
    end
    local env = setmetatable({addon = addon, L = function(s) return s end,
                              fmt = string.format, tinsert = table.insert},
                             {__index = _G})
    local chunk = assert(loadstring(block))
    setfenv(chunk, env)
    chunk()

    -- guides as the engine would hand them over: zero padded names,
    -- shown under each guide's display text, in file (load) order
    local entries, order = {}, 0
    for _, file in ipairs(guideFiles) do
        local text = readfile(ROOT .. "/Guides/" .. file)
        for header in text:gmatch("RegisterGuide%(%[%[(.-)\nstep") do
            local name = header:match("#name%s+([^\n]+)")
            local enabled = header:match("\n<<%s*([^\n]+)")
            local default = header:match("#defaultfor%s+([^\n]+)")
            -- "None" guides are internal side routes the engine never lists
            if name and default ~= "None" and (not enabled or addon.applies(enabled)) then
                order = order + 1
                local stored = name:gsub("^(%d)-(%d%d?)", function(a, b)
                    if #b == 1 then b = "0" .. b end
                    return "0" .. a .. "-" .. b
                end)
                table.insert(entries, {item = {text = name}, guide = {name = stored},
                                       order = order})
            end
        end
    end
    return addon.BuildLevelMenu(entries, faction)
end

local function texts(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.text end
    return table.concat(out, " | ")
end

local function isSorted(list)
    local prev = 0
    for _, e in ipairs(list) do
        local n = tonumber(e.text:match("^(%d+)"))
        if n < prev then return false end
        prev = n
    end
    return true
end

-- Human warrior
local menu = run("Alliance", {Alliance = true, Human = true, Warrior = true}, {
    "forever/Alliance-1-10_NightElf.lua", "forever/Alliance-1-13_Human.lua",
    "forever/Alliance-1-14_DwarfGnome.lua", "forever/Alliance-11-20.lua",
    "forever/RestedXP-Skyborne.lua", "openxp/Alliance-21-30.lua",
    "openxp/Alliance-30-40.lua", "openxp/Alliance-40-50.lua",
    "openxp/Alliance-50-60.lua",
})
print("  " .. texts(menu))
check(menu[1].text == "Starting zones", "Starting zones comes first")
local races = menu[1].menuList
print("  " .. texts(races))
check(#races == 4, "all four Alliance starting areas listed")
check(races[1].text:find("^Human"), "your own race is first")
check(texts(races[1].menuList) == "1-6 Northshire | 6-11 Elwynn Forest | 11-13 Loch Modan",
      "Human starter guides in route order")
check(texts(menu[2].menuList):find("^13%-15 Westfall"), "Levels 10-19 starts with Westfall")
local ne
for _, r in ipairs(races) do if r.text:find("Night Elf") then ne = r end end
check(ne and texts(ne.menuList) == "1-6 Shadowglen | 6-11 Teldrassil",
      "Night Elf starter guides listed for a Human")
local want = {"Levels 10-19", "Levels 20-29", "Levels 30-39", "Levels 40-49", "Levels 50-59"}
local ok = true
for i, w in ipairs(want) do if not menu[i + 1] or menu[i + 1].text ~= w then ok = false end end
check(ok and #menu == 6, "level brackets in order: " .. texts(menu))
for i = 2, #menu do
    check(isSorted(menu[i].menuList), menu[i].text .. " sorted by level: " .. texts(menu[i].menuList))
end

-- Undead mage
menu = run("Horde", {Horde = true, Undead = true, Mage = true}, {
    "forever/Horde-01-12_Durotar.lua", "forever/Horde-01-14_Undead.lua",
    "forever/Horde-1-12_Mulgore.lua", "forever/Horde-12-22_Barrens.lua",
    "forever/RestedXP-Skyborne.lua", "openxp/Horde-22-30.lua",
    "openxp/Horde-30-40.lua", "openxp/Horde-40-50.lua", "openxp/Horde-50-60.lua",
})
print("  " .. texts(menu))
races = menu[1].menuList
print("  " .. texts(races))
check(menu[1].text == "Starting zones" and #races == 4, "all four Horde starting areas listed")
check(races[1].text:find("^Undead"), "Undead player sees Undead first")
for i = 2, #menu do
    check(isSorted(menu[i].menuList), menu[i].text .. " sorted by level: " .. texts(menu[i].menuList))
end

print(failures == 0 and "guide menu tests passed" or (failures .. " guide menu tests FAILED"))
return failures
