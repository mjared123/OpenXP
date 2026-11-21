-- /oxp and /openxp. Modules add their own words with OXP.AddCommand.
local _, OXP = ...

local commands, order = {}, {}

--- Add "/oxp <word> ..."; fn(rest) gets the text after the word.
function OXP.AddCommand(word, help, fn)
    if not commands[word] then order[#order + 1] = word end
    commands[word] = { help = help, fn = fn }
end

function OXP.RemoveCommand(word)
    if not commands[word] then return end
    commands[word] = nil
    for i = #order, 1, -1 do if order[i] == word then table.remove(order, i) end end
end

function OXP.RunCommand(msg)
    msg = OXP.Util.Trim(msg or "")
    local word, rest = msg:match("^(%S*)%s*(.-)$")
    word = (word or ""):lower()
    local c = commands[word]
    if c then return c.fn(rest or "") end
    if word ~= "" and word ~= "help" then
        OXP.Print("Unknown command '%s'.", word)
    end
    OXP.Print("Commands:")
    for _, w in ipairs(order) do
        if commands[w].help then print(("  /oxp %s - %s"):format(w, commands[w].help)) end
    end
end

SLASH_OPENXP1 = "/oxp"
SLASH_OPENXP2 = "/openxp"
SlashCmdList = SlashCmdList or {}
SlashCmdList.OPENXP = function(msg) OXP.RunCommand(msg) end

OXP.AddCommand("perf", "time each part of OpenXP (/oxp perf, then /oxp perf again to see it)", function(rest)
    OXP.Perf.Command(rest:lower())
end)
OXP.AddCommand("mem", "show how much memory OpenXP and its maps use", function()
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return end
    UpdateAddOnMemoryUsage()
    local total = 0
    for _, name in ipairs({ "OpenXP", "OpenXP_Nav" }) do
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded or function() return true end)(name)
        if loaded then
            local kb = GetAddOnMemoryUsage(name) or 0
            total = total + kb
            OXP.Print("%s: %.1f MB", name, kb / 1024)
        end
    end
    OXP.Print("Total: %.1f MB (the game frees unused memory on its own over time).", total / 1024)
end)
OXP.AddCommand("debug", "turn debug messages on or off", function()
    OXP.settings.debug = not OXP.settings.debug
    OXP.Print("Debug messages %s.", OXP.settings.debug and "on" or "off")
end)
OXP.AddCommand("version", "show the OpenXP version", function()
    OXP.Print("Version %s.", OXP.version)
end)
