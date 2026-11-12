-- /oxp perf: how much time each part of OpenXP takes.
--
-- Perf.Wrap(name, fn) returns fn timed under `name`. While measuring is off
-- (the default) the wrapper only adds one table lookup per call.
local _, OXP = ...

local Perf = { on = false, stats = {} }
OXP.Perf = Perf

local clock = debugprofilestop or function() return (os and os.clock and os.clock() or 0) * 1000 end

function Perf.Wrap(name, fn)
    return function(...)
        if not Perf.on then return fn(...) end
        local t0 = clock()
        local a, b, c, d = fn(...)
        local ms = clock() - t0
        local s = Perf.stats[name]
        if not s then
            s = { calls = 0, total = 0, max = 0 }
            Perf.stats[name] = s
        end
        s.calls = s.calls + 1
        s.total = s.total + ms
        if ms > s.max then s.max = ms end
        return a, b, c, d
    end
end

function Perf.Start()
    Perf.stats = {}
    Perf.on = true
    Perf.started = GetTime and GetTime() or 0
end

--- Lines describing what was measured, slowest total first.
function Perf.Report()
    local rows = {}
    for name, s in pairs(Perf.stats) do rows[#rows + 1] = { name = name, s = s } end
    table.sort(rows, function(a, b) return a.s.total > b.s.total end)
    local secs = math.max(0.001, (GetTime and GetTime() or 0) - (Perf.started or 0))
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = ("%-34s %6d calls %8.1f ms (%.2f ms/s) max %.2f ms"):format(
            r.name, r.s.calls, r.s.total, r.s.total / secs, r.s.max)
    end
    return out
end

function Perf.Command(arg)
    if arg == "stop" or arg == "off" then
        Perf.on = false
        OXP.Print("Timing stopped.")
    elseif arg == "show" or (arg == "" and Perf.on) then
        local lines = Perf.Report()
        if #lines == 0 then return OXP.Print("Nothing timed yet.") end
        OXP.Print("Time spent since /oxp perf:")
        for _, l in ipairs(lines) do print("  " .. l) end
    else
        Perf.Start()
        OXP.Print("Timing every part of OpenXP. Play a minute, then type /oxp perf again to see it (/oxp perf stop to end).")
    end
end
