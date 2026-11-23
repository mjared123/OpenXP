-- Taint: OpenXP must never assign one of Blizzard's own globals, not even to
-- the value it already has. That taints the variable, and Blizzard code that
-- reads it afterwards gets blocked from protected actions. 2.0.0 and 2.0.1
-- had "SlashCmdList = SlashCmdList or {}", which broke /ginvite (GitHub #99,
-- #100).
local ROOT = ...
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local t = FakeWoW.Checker("taint")

local BLIZZARD = {
    "SlashCmdList", "hash_SlashCmdList", "StaticPopupDialogs", "UISpecialFrames", "ChatTypeInfo",
    "DEFAULT_CHAT_FRAME", "SELECTED_CHAT_FRAME", "ChatFrame_OpenChat", "ChatEdit_ParseText",
    "ChatEdit_SendText", "QuestWatch_Update", "UIParent", "GameTooltip", "WorldMapFrame", "Minimap",
}

print("-- no file assigns a Blizzard global")
local files = 0
for _, addon in ipairs({ "OpenXP", "OpenXP_Nav" }) do
    local toc = io.open(ROOT .. "/" .. addon .. "/" .. addon .. ".toc")
    for line in toc:lines() do
        local path = line:match("^([^#%s][^\r]-%.lua)%s*$")
        if path then
            local f = io.open(ROOT .. "/" .. addon .. "/" .. path:gsub("\\", "/"))
            if f then
                files = files + 1
                local n = 0
                for src in f:lines() do
                    n = n + 1
                    local code = src:gsub("%-%-.*$", "")
                    for _, name in ipairs(BLIZZARD) do
                        local hit = code:match("^%s*" .. name .. "%s*=[^=]") or code:match("^%s*_G%.?%[?[\"']?" .. name .. "[\"']?%]?%s*=[^=]")
                        if hit then t.ok(false, ("%s/%s:%d assigns %s"):format(addon, path, n, name)) end
                    end
                end
                f:close()
            end
        end
    end
    toc:close()
end
t.ok(files > 20, "checked the add-on files: " .. files)

print("-- /oxp still registered on the game's own SlashCmdList")
do
    local game = FakeWoW.New(ROOT, { level = 5 })
    local list = SlashCmdList
    local OXP = game:LoadAddon()
    game:Login()
    t.ok(rawequal(SlashCmdList, list), "same table")
    t.eq(type(SlashCmdList.OPENXP), "function", "/oxp handler added")
    t.eq(SLASH_OPENXP1, "/oxp", "/oxp")
    local _ = OXP
end

return t.fails
