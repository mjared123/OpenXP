-- /oxp and /openxp. Modules add their own words with OXP.AddCommand.
local _, OXP = ...

local commands, order = {}, {}

--- Add "/oxp <word> ..."; fn(rest) gets the text after the word.
function OXP.AddCommand(word, help, fn)
    if not commands[word] then order[#order + 1] = word end
    commands[word] = { help = help, fn = fn }
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
OXP.AddCommand("debug", "turn debug messages on or off", function()
    OXP.settings.debug = not OXP.settings.debug
    OXP.Print("Debug messages %s.", OXP.settings.debug and "on" or "off")
end)
OXP.AddCommand("version", "show the OpenXP version", function()
    OXP.Print("Version %s.", OXP.version)
end)
