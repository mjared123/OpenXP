-- Arrow path hints: stepping stones for places a straight arrow can't reach,
-- like a cave under a hill or a camp on a ridge. The arrow walks you through
-- the entrance points first and only then points at the real target.
--
-- Areas come from three places:
--   Data/PathHints.lua  built-in list (OXP.pathHintData)
--   learned             OpenXP notices when you walk into a cave or other big
--                       indoor place and saves where you went in and out
--   recorded            /oxp path add saves where you stand as a stepping
--                       stone toward the arrow's current target
-- The last two are saved account-wide in OpenXPDB.paths.
local _, OXP = ...

local PH = {}
OXP.PathHints = PH

local Places = OXP.Places
local L = OXP.L
local fmt = string.format
local sqrt, max, min = math.sqrt, math.max, math.min

local REACH = 10        -- yards: a stepping stone counts as reached
local LEARN_MIN = 35    -- yards: smallest indoor place worth learning (skips houses)
local SAME_DOOR = 20    -- yards: entrances closer than this are the same one
local CLEAR_RANGE = 100 -- yards: /oxp path clear removes spots this close
local THROTTLE = 0.2    -- seconds between route updates

local function Dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end

function PH.Saved()
    local db = OXP.db
    if not db then return nil end
    db.paths = db.paths or {}
    db.paths.areas = db.paths.areas or {}
    db.paths.passes = db.paths.passes or {}
    return db.paths
end

function PH.IsOn()
    local s = PH.Saved()
    return not (s and s.off)
end

------------------------------------------------------------------------
-- Areas
------------------------------------------------------------------------

local version = 0
local cache = {}

function PH.Changed() version = version + 1 end

-- each entrance's two walking orders (in, out) and length, built once and
-- kept out of the saved variables
local built = setmetatable({}, { __mode = "k" })

local function Paths(area, e)
    local b = built[e]
    if b and b[1].area == area then return b[1], b[2] end
    local pts, len = {}, 0
    for i = 1, #e do
        pts[i] = e[i]
        if i > 1 then len = len + Dist(e[i - 1][1], e[i - 1][2], e[i][1], e[i][2]) end
    end
    local name = area.name
    local enter = { pts = pts, len = len, area = area, enter = true,
                    label = area.indoor and fmt(L("Enter %s"), name) or fmt(L("Path to %s"), name) }
    local exit
    if not e.oneWay then
        local rev = {}
        for i = #pts, 1, -1 do rev[#rev + 1] = pts[i] end
        exit = { pts = rev, len = len, area = area, label = fmt(L("Leave %s"), name) }
    end
    built[e] = { enter, exit }
    return enter, exit
end

local function PassPaths(pass)
    local b = built[pass]
    if b then return b[1], b[2] end
    local pts, rev, len = {}, {}, 0
    for i = 1, #pass.pts do
        pts[i] = pass.pts[i]
        rev[#pass.pts - i + 1] = pass.pts[i]
        if i > 1 then len = len + Dist(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]) end
    end
    local label = fmt(L("Go through %s"), pass.name or L("the pass"))
    local fwd = { pts = pts, len = len, label = label }
    local back = pass.twoWay ~= false and { pts = rev, len = len, label = label } or nil
    built[pass] = { fwd, back }
    return fwd, back
end

local function Lists(inst)
    local c = cache[inst]
    if c and c.version == version then return c.areas, c.passes end
    local areas, passes = {}, {}
    local data = OXP.pathHintData or {}
    for _, a in ipairs(data) do
        if a.inst == inst then areas[#areas + 1] = a end
    end
    for _, p in ipairs(data.passes or {}) do
        if p.inst == inst then passes[#passes + 1] = p end
    end
    local s = PH.Saved()
    if s then
        for _, a in ipairs(s.areas) do
            if a.inst == inst and #a.entrances > 0 then areas[#areas + 1] = a end
        end
        for _, p in ipairs(s.passes) do
            if p.inst == inst then passes[#passes + 1] = p end
        end
    end
    cache[inst] = { version = version, areas = areas, passes = passes }
    return areas, passes
end

-- How deep inside the area a point is: nil outside, else the radius of the
-- smallest circle holding it (smaller wins between areas).
local function Inside(area, x, y)
    local best
    for _, c in ipairs(area.circles) do
        if Dist(x, y, c[1], c[2]) <= c[3] and (not best or c[3] < best) then best = c[3] end
    end
    return best
end
PH.Inside = Inside

local function PlayerInside(area, x, y, ctx)
    local r = Inside(area, x, y)
    if not r then return nil end
    if area.indoor and not ctx.indoors and not (area.name and ctx.subzone == area.name) then return nil end
    return r
end

------------------------------------------------------------------------
-- Routing
------------------------------------------------------------------------

local state = {}

local function Best(paths, px, py, tx, ty)
    local best, bestCost
    for _, path in ipairs(paths) do
        if not state.finished[path] then
            local first, last = path.pts[1], path.pts[#path.pts]
            local cost = Dist(px, py, first[1], first[2]) + path.len + Dist(last[1], last[2], tx, ty)
            if not bestCost or cost < bestCost then best, bestCost = path, cost end
        end
    end
    return best
end

--- Where the arrow should point right now on the way to `target`, or nil to
--- point straight at it: the point ({x, y}) and a label.
--- ctx: { indoors = bool, subzone = string, map = the player's map id }
function PH.Route(target, px, py, inst, ctx)
    if not (target and target.wx and target.wy and px and py) then return nil end
    if target.instance ~= inst then return nil end
    local tx, ty = target.wx, target.wy

    if state.target ~= target or state.tx ~= tx or state.ty ~= ty then
        state.target, state.tx, state.ty = target, tx, ty
        state.done, state.left, state.finished = {}, {}, {}
        state.path, state.idx = nil, 1
    end

    local areas, passes = Lists(inst)
    local aP, aT, rP, rT
    for _, a in ipairs(areas) do
        local r = Inside(a, tx, ty)
        if r and (not rT or r < rT) then aT, rT = a, r end
        r = not state.left[a] and PlayerInside(a, px, py, ctx)
        if r and (not rP or r < rP) then aP, rP = a, r end
    end
    if aT and state.done[aT] then aP = aT end
    local cur = state.path
    if not aP and cur and cur.area and not cur.enter and ctx.indoors and not state.left[cur.area] then
        aP = cur.area
    end
    if aP and aP == aT then return nil end

    local path
    if aP then
        local list = {}
        for _, e in ipairs(aP.entrances) do
            local _, exit = Paths(aP, e)
            if exit then list[#list + 1] = exit end
        end
        path = Best(list, px, py, tx, ty)
    end
    if not path and aT then
        local list = {}
        for _, e in ipairs(aT.entrances) do list[#list + 1] = (Paths(aT, e)) end
        path = Best(list, px, py, tx, ty)
    end
    if not path and not aP and target.map and ctx.map and target.map ~= ctx.map then
        local list = {}
        for _, p in ipairs(passes) do
            local fwd, back = PassPaths(p)
            if p.from == ctx.map and p.to == target.map then list[#list + 1] = fwd end
            if back and p.to == ctx.map and p.from == target.map then list[#list + 1] = back end
        end
        path = Best(list, px, py, tx, ty)
    end
    if not path then
        -- nothing hand-made: go around mountains and high-level packs
        local pt = not aP and not aT and OXP.Terrain.Route(target, px, py, inst, ctx.map)
        if pt then return pt, L("Way around") end
        return nil
    end

    local pts = path.pts
    if state.path ~= path then
        state.path, state.idx = path, 1
        for i = #pts, 1, -1 do
            if Dist(px, py, pts[i][1], pts[i][2]) <= (pts[i][3] or REACH) then
                state.idx = i + 1
                break
            end
        end
    end
    while state.idx <= #pts and Dist(px, py, pts[state.idx][1], pts[state.idx][2]) <= (pts[state.idx][3] or REACH) do
        state.idx = state.idx + 1
    end
    if state.idx > #pts then
        state.finished[path] = true
        if path.area then
            if path.enter then state.done[path.area] = true else state.left[path.area] = true end
        end
        state.path = nil
        return PH.Route(target, px, py, inst, ctx)
    end
    local pt = pts[state.idx]
    return pt, pt[4] or path.label
end

function PH.Reset()
    state = {}
    OXP.Terrain.Reset()
end

local proxy = {}
local lastCheck, lastTarget, lastPt, lastLabel = 0, nil, nil, nil

local function Context()
    local _, _, map = Places.PlayerZone()
    return {
        indoors = IsIndoors and IsIndoors() or false,
        subzone = GetSubZoneText and GetSubZoneText() or "",
        map = map,
    }
end

--- The stepping stone to show instead of `target`, or nil.
function PH.ForArrow(target)
    if not target or target == proxy or not PH.IsOn() then return nil end
    local now = GetTime and GetTime() or 0
    if target ~= lastTarget or now - lastCheck >= THROTTLE then
        lastCheck, lastTarget = now, target
        local px, py, inst = Places.Player()
        lastPt, lastLabel = PH.Route(target, px, py, inst, Context())
    end
    if not lastPt then return nil end
    proxy.wx, proxy.wy, proxy.instance, proxy.map = lastPt[1], lastPt[2], target.instance, target.map
    proxy.title, proxy.real = lastLabel, target
    return proxy
end

------------------------------------------------------------------------
-- /oxp path to <zone | x y>: lead the arrow somewhere the guide isn't
------------------------------------------------------------------------

local function FindZone(name)
    name = name:lower()
    local best
    for zoneName, id in pairs(Places.MAP_IDS) do
        local z = zoneName:lower()
        if z == name then return zoneName, id end
        if not best and z:find(name, 1, true) == 1 then best = { zoneName, id } end
    end
    if best then return best[1], best[2] end
end

function PH.GoTo(args)
    local x, y = args:match("^(%d+%.?%d*)[,%s]+(%d+%.?%d*)$")
    local go
    if x then
        local _, _, map = Places.PlayerZone()
        local wx, wy, inst = Places.ToWorld(map, tonumber(x), tonumber(y))
        if not wx then return OXP.Print("Couldn't place %s, %s on this map.", x, y) end
        go = { wx = wx, wy = wy, instance = inst, map = map, title = fmt("%s, %s", x, y) }
    else
        local name, id = FindZone(args)
        if not id then return OXP.Print("No zone called \"%s\". Try the full name, like /oxp path to Stonetalon Mountains.", args) end
        local _, _, map = Places.PlayerZone()
        if map == id then return OXP.Print("You're already in %s.", name) end
        local wx, wy, inst = Places.ToWorld(id, 50, 50)
        if not wx then return OXP.Print("Couldn't find %s on the map.", name) end
        go = { wx = wx, wy = wy, instance = inst, map = id, untilMap = id, title = name }
    end
    PH.go = go
    PH.Reset()
    OXP.Send("ARROW_CHANGED")
    OXP.Print("The arrow now leads to %s, through any passes and tunnels it knows. /oxp path stop puts it back on the guide.", go.title)
end

function PH.StopGo(arrived)
    if not PH.go then return end
    local title = PH.go.title
    PH.go = nil
    PH.Reset()
    OXP.Send("ARROW_CHANGED")
    if arrived then OXP.Print("You've reached %s. The arrow is back on the guide.", title) end
end

local function GoTick()
    local go = PH.go
    if not go then return end
    if go.untilMap then
        local _, _, map = Places.PlayerZone()
        if map == go.untilMap then return PH.StopGo(true) end
    else
        local x, y, inst = Places.Player()
        if x and inst == go.instance and Dist(x, y, go.wx, go.wy) <= REACH then return PH.StopGo(true) end
    end
end

------------------------------------------------------------------------
-- Learning cave entrances
------------------------------------------------------------------------

local learn = {}

local function AddDoor(area, x, y)
    for _, e in ipairs(area.entrances) do
        local p = e[#e]
        if #e == 1 and Dist(p[1], p[2], x, y) <= SAME_DOOR then
            e.seen = (e.seen or 1) + 1
            return
        end
    end
    area.entrances[#area.entrances + 1] = { { x, y }, seen = 1 }
end

local function Fit(area)
    local b = area.box
    local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
    local r = max(b[3] - b[1], b[4] - b[2]) / 2 + 10
    area.circles = { { cx, cy, r } }
end

--- s: an indoor visit { inst, box = {minx, miny, maxx, maxy}, name, door }
function PH.Learn(s, exitX, exitY)
    local saved = PH.Saved()
    if not saved then return nil end
    local b = s.box
    if s.resting then return nil end -- inns and city buildings aren't caves
    if max(b[3] - b[1], b[4] - b[2]) < LEARN_MIN then return nil end
    local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
    for _, a in ipairs(OXP.pathHintData or {}) do
        if a.inst == s.inst and Inside(a, cx, cy) then return nil end
    end
    local area
    for _, a in ipairs(saved.areas) do
        if a.source == "learned" and a.inst == s.inst then
            local c = a.circles[1]
            if Dist(c[1], c[2], cx, cy) <= c[3] + max(b[3] - b[1], b[4] - b[2]) / 2 then
                area = a
                break
            end
        end
    end
    if area then
        local ab = area.box
        ab[1], ab[2] = min(ab[1], b[1]), min(ab[2], b[2])
        ab[3], ab[4] = max(ab[3], b[3]), max(ab[4], b[4])
        if (not area.name or area.name == "") and s.name ~= "" then area.name = s.name end
    else
        area = { source = "learned", inst = s.inst, indoor = true,
                 name = (s.name and s.name ~= "") and s.name or L("the cave"),
                 box = { b[1], b[2], b[3], b[4] }, entrances = {} }
        saved.areas[#saved.areas + 1] = area
    end
    Fit(area)
    if s.door then AddDoor(area, s.door[1], s.door[2]) end
    if exitX then AddDoor(area, exitX, exitY) end
    PH.Changed()
    return area
end

--- Called twice a second. Indoors/outdoors only counts as changed after
--- two readings agree, so a flicker at a cave mouth doesn't make a door.
function PH.LearnTick(x, y, inst, indoors)
    if not PH.IsOn() then return end
    if not x then
        learn = {}
        return
    end
    local prev = learn.prev
    if prev and (prev[3] ~= inst or Dist(prev[1], prev[2], x, y) > 60) then learn = {} end
    learn.prev = { x, y, inst }
    if learn.indoors == nil then
        learn.indoors = indoors
        if indoors then learn.visit = { inst = inst, box = { x, y, x, y }, name = GetSubZoneText() or "" } end
        return
    end
    if indoors ~= learn.indoors then
        if not learn.flip then
            learn.flip = { x, y }
            return
        end
        local door = learn.flip
        learn.flip = nil
        learn.indoors = indoors
        if indoors then
            learn.visit = { inst = inst, box = { door[1], door[2], door[1], door[2] },
                            name = GetSubZoneText() or "", door = door }
        elseif learn.visit then
            local visit = learn.visit
            learn.visit = nil
            PH.Learn(visit, door[1], door[2])
        end
    else
        learn.flip = nil
    end
    local v = learn.visit
    if v and learn.indoors then
        if IsResting and IsResting() then v.resting = true end
        local b = v.box
        b[1], b[2] = min(b[1], x), min(b[2], y)
        b[3], b[4] = max(b[3], x), max(b[4], y)
        if v.name == "" then v.name = GetSubZoneText() or "" end
    end
end

local ticker = CreateFrame("Frame")
local wait = 0
ticker:SetScript("OnUpdate", OXP.Perf.Wrap("path learning", function(_, elapsed)
    wait = wait + elapsed
    if wait < 0.5 then return end
    wait = 0
    if not OXP.db then return end
    GoTick()
    if (IsInInstance and IsInInstance()) or (UnitOnTaxi and UnitOnTaxi("player"))
        or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        return PH.LearnTick(nil)
    end
    local x, y, inst = Places.Player()
    PH.LearnTick(x, y, inst, IsIndoors and IsIndoors() and true or false)
end))

------------------------------------------------------------------------
-- /oxp path
------------------------------------------------------------------------

local recording

local function Finish()
    local rec = recording
    recording = nil
    if not rec or #rec.pts == 0 then return end
    local saved = PH.Saved()
    if not saved then return end
    local t = rec.target
    if t.map and rec.map and t.map ~= rec.map then
        saved.passes[#saved.passes + 1] = { source = "recorded", inst = t.inst, from = rec.map, to = t.map,
                                            name = rec.label, pts = rec.pts, twoWay = true }
        PH.Changed()
        return OXP.Print("Saved a %d-point pass toward the next zone.", #rec.pts)
    end
    local last = rec.pts[#rec.pts]
    local r = max(15, min(120, 0.6 * Dist(last[1], last[2], t.x, t.y)))
    for _, a in ipairs(saved.areas) do
        if a.source == "recorded" and a.inst == t.inst and Inside(a, t.x, t.y) then
            a.entrances[#a.entrances + 1] = rec.pts
            PH.Changed()
            return OXP.Print("Added another way into %s (%d points).", a.name, #rec.pts)
        end
    end
    local name = rec.label or (t.title and OXP.Text.Strip(t.title)) or L("this spot")
    saved.areas[#saved.areas + 1] = { source = "recorded", inst = t.inst, indoor = rec.indoor, name = name,
                                      circles = { { t.x, t.y, r } }, entrances = { rec.pts } }
    PH.Changed()
    OXP.Print("Saved a %d-point path to %s. The arrow uses it from now on.", #rec.pts, name)
end

local function Add(label)
    local t = OXP.Target and OXP.Target.Current()
    if not (t and t.wx) then
        return OXP.Print("There's no arrow target right now. Start the step you need a path for, then try again.")
    end
    local px, py, inst = Places.Player()
    if not px then return end
    if t.instance ~= inst then return OXP.Print("The arrow's target is on another continent.") end
    if recording and (recording.target.x ~= t.wx or recording.target.y ~= t.wy) then Finish() end
    if not recording then
        local _, _, map = Places.PlayerZone()
        recording = { target = { x = t.wx, y = t.wy, inst = inst, map = t.map, title = t.title }, pts = {}, map = map }
    end
    if label and label ~= "" then recording.label = recording.label or label end
    recording.indoor = IsIndoors and IsIndoors() and true or false
    recording.pts[#recording.pts + 1] = { px, py }
    OXP.Print("Stepping stone %d saved. Walk to the next one and type /oxp path add again, or /oxp path done when you're there.",
        #recording.pts)
end

local function Clear()
    local saved = PH.Saved()
    local px, py, inst = Places.Player()
    if not (saved and px) then return end
    local n = 0
    local function Near(pts)
        for _, p in ipairs(pts) do
            if Dist(px, py, p[1], p[2]) <= CLEAR_RANGE then return true end
        end
    end
    for i = #saved.areas, 1, -1 do
        local a = saved.areas[i]
        local near = a.inst == inst and Inside(a, px, py)
        for _, e in ipairs(a.entrances) do near = near or (a.inst == inst and Near(e)) end
        if near then
            table.remove(saved.areas, i)
            n = n + 1
        end
    end
    for i = #saved.passes, 1, -1 do
        local p = saved.passes[i]
        if p.inst == inst and Near(p.pts) then
            table.remove(saved.passes, i)
            n = n + 1
        end
    end
    PH.Changed()
    PH.Reset()
    OXP.Print("Removed %d saved path(s) near you.", n)
end

function PH.Command(args)
    local cmd, rest = OXP.Util.Trim(args or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local saved = PH.Saved()
    if cmd == "add" then
        Add(rest)
    elseif cmd == "done" or cmd == "save" then
        if not recording then return OXP.Print("Nothing recorded yet. Use /oxp path add first.") end
        Finish()
    elseif cmd == "undo" then
        if recording and #recording.pts > 0 then
            table.remove(recording.pts)
            return OXP.Print("Removed the last stepping stone (%d left).", #recording.pts)
        end
        OXP.Print("Nothing to undo.")
    elseif cmd == "clear" then
        Clear()
    elseif cmd == "to" or cmd == "go" then
        if rest == "" then
            return OXP.Print("Where to? For example /oxp path to Stonetalon Mountains, or /oxp path to 36.4 7.2 on this map.")
        end
        PH.GoTo(rest)
    elseif cmd == "stop" then
        if not PH.go then return OXP.Print("The arrow is already following the guide.") end
        PH.StopGo()
        OXP.Print("The arrow is back on the guide.")
    elseif cmd == "off" or cmd == "on" then
        if saved then saved.off = cmd == "off" end
        PH.Reset()
        OXP.Print(cmd == "off" and "Arrow paths are off: the arrow points straight at the target." or "Arrow paths are on.")
    else
        local learned, recorded = 0, 0
        for _, a in ipairs(saved and saved.areas or {}) do
            if a.source == "learned" then learned = learned + 1 else recorded = recorded + 1 end
        end
        recorded = recorded + #(saved and saved.passes or {})
        OXP.Print("Arrow paths are %s. Built in: %d, learned: %d, recorded by you: %d.",
            PH.IsOn() and "on" or "off", #(OXP.pathHintData or {}), learned, recorded)
        print("  /oxp path add [name] - save where you stand as a stepping stone toward the arrow's target")
        print("  /oxp path done - finish the path   /oxp path undo - drop the last stone")
        print("  /oxp path to <zone> or <x y> - lead the arrow there (/oxp path stop to go back to the guide)")
        print("  /oxp path clear - forget saved paths near you   /oxp path off|on")
    end
end

OXP.AddCommand("path", "arrow paths: add, done, undo, to <zone>, stop, clear, on/off", PH.Command)
