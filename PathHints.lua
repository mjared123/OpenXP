-- Arrow path hints
--
-- Addons can't see the game's walkable terrain, so the arrow can only point
-- in a straight line. That breaks for a quest inside a cave (it points into
-- the hill) or on top of a ridge (it points at a cliff). This module gives
-- the arrow stepping stones instead: entrances and ramps to walk through
-- before it points at the real target.
--
-- Areas come from three places:
--   DB/pathHints.lua   built-in list (addon.pathHintData)
--   learned            OpenXP notices when you walk into a cave or other big
--                      indoor place, and saves where you went in and out
--   recorded           /oxp path add saves where you're standing as a
--                      stepping stone toward the arrow's current target
-- The last two are saved account-wide in OXPData.openxpPaths.

local _, addon = ...
local L = addon.locale.Get
local fmt = string.format
local sqrt, max, min = math.sqrt, math.max, math.min

local HBD = LibStub("HereBeDragons-2.0")

local ph = {}
addon.pathHints = ph

local REACH = 10        -- yards: a stepping stone counts as reached
local LEARN_MIN = 35    -- yards: smallest indoor place worth learning (skips houses)
local SAME_DOOR = 20    -- yards: entrances closer than this are the same one
local CLEAR_RANGE = 100 -- yards: /oxp path clear removes spots this close
local THROTTLE = 0.2    -- seconds between route updates

local function Dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end

local function Print(msg, ...)
    if addon.comms and addon.comms.PrettyPrint then
        addon.comms.PrettyPrint(msg, ...)
    end
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

function ph.Saved()
    if type(OXPData) ~= "table" then return end
    local s = OXPData.openxpPaths
    if type(s) ~= "table" then
        s = {}
        OXPData.openxpPaths = s
    end
    s.areas = s.areas or {}
    s.passes = s.passes or {}
    return s
end

function ph.IsOn()
    local s = ph.Saved()
    return not (s and s.off)
end

---------------------------------------------------------------------------
-- Areas
---------------------------------------------------------------------------

local version = 0      -- bumped whenever learned or recorded data changes
local cache = {}       -- inst -> {version, areas, passes}

function ph.Changed()
    version = version + 1
end

-- Each entrance's two walking orders (in and out) and length, built once.
-- Kept in a side table so none of it ends up in SavedVariables.
local built = setmetatable({}, {__mode = "k"})

local function Paths(area, e)
    local b = built[e]
    if b and b[1].area == area then return b[1], b[2] end
    local pts, len = {}, 0
    for i = 1, #e do
        pts[i] = e[i]
        if i > 1 then len = len + Dist(e[i - 1][1], e[i - 1][2], e[i][1], e[i][2]) end
    end
    local name = area.name
    local enterLabel = area.indoor and fmt(L("Enter %s"), name) or fmt(L("Path to %s"), name)
    local enter = {pts = pts, len = len, area = area, label = enterLabel, enter = true}
    local exit
    if not e.oneWay then
        local rev = {}
        for i = #pts, 1, -1 do rev[#rev + 1] = pts[i] end
        exit = {pts = rev, len = len, area = area, label = fmt(L("Leave %s"), name)}
    end
    built[e] = {enter, exit}
    return enter, exit
end

local function PassPaths(pass)
    local b = built[pass]
    if b then return b[1], b[2] end
    local pts, rev, len = {}, {}, 0
    for i = 1, #pass.pts do
        pts[i] = pass.pts[i]
        rev[#pass.pts - i + 1] = pass.pts[i]
        if i > 1 then
            len = len + Dist(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
        end
    end
    local label = fmt(L("Go through %s"), pass.name or L("the pass"))
    local fwd = {pts = pts, len = len, label = label}
    local back = pass.twoWay ~= false and {pts = rev, len = len, label = label} or nil
    built[pass] = {fwd, back}
    return fwd, back
end

local function Lists(inst)
    local c = cache[inst]
    if c and c.version == version then return c.areas, c.passes end
    local areas, passes = {}, {}
    local data = addon.pathHintData or {}
    for _, a in ipairs(data) do
        if a.inst == inst then areas[#areas + 1] = a end
    end
    for _, p in ipairs(data.passes or {}) do
        if p.inst == inst then passes[#passes + 1] = p end
    end
    local s = ph.Saved()
    if s then
        for _, a in ipairs(s.areas) do
            if a.inst == inst and #a.entrances > 0 then areas[#areas + 1] = a end
        end
        for _, p in ipairs(s.passes) do
            if p.inst == inst then passes[#passes + 1] = p end
        end
    end
    cache[inst] = {version = version, areas = areas, passes = passes}
    return areas, passes
end

-- How far inside the area a point is: nil when outside, otherwise the
-- radius of the smallest circle holding it (smaller wins between areas).
local function Inside(area, x, y)
    local best
    for _, c in ipairs(area.circles) do
        if Dist(x, y, c[1], c[2]) <= c[3] and (not best or c[3] < best) then best = c[3] end
    end
    return best
end

local function PlayerInside(area, x, y, ctx)
    local r = Inside(area, x, y)
    if not r then return end
    if area.indoor and not ctx.indoors and not (area.name and ctx.subzone == area.name) then
        return
    end
    return r
end

---------------------------------------------------------------------------
-- Routing
---------------------------------------------------------------------------

local state = {}

local function Best(paths, px, py, tx, ty)
    local best, bestCost
    for _, path in ipairs(paths) do
        if not state.finished[path] then
            local pts = path.pts
            local first, last = pts[1], pts[#pts]
            local cost = Dist(px, py, first[1], first[2]) + path.len + Dist(last[1], last[2], tx, ty)
            if not bestCost or cost < bestCost then best, bestCost = path, cost end
        end
    end
    return best
end

-- Where the arrow should point right now on the way to target, or nil to
-- point straight at it. Returns the point ({x, y}) and a label.
-- ctx: {indoors = bool, subzone = string, zone = map id of the player}
function ph.Route(target, px, py, inst, ctx)
    if not (target and target.wx and target.wy and px and py) then return end
    if target.instance ~= inst then return end
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
    -- went in on this target already: you're inside even where the game
    -- doesn't flag the spot as indoors
    if aT and state.done[aT] then aP = aT end
    -- on the way out: still inside until the last stone, even past the
    -- edge of the area's circle (the tunnel to the mouth)
    local cur = state.path
    if not aP and cur and cur.area and not cur.enter and ctx.indoors and not state.left[cur.area] then
        aP = cur.area
    end
    if aP and aP == aT then return end

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
    if not path and not aP and target.zone and ctx.zone and target.zone ~= ctx.zone then
        local list = {}
        for _, p in ipairs(passes) do
            local fwd, back = PassPaths(p)
            if p.from == ctx.zone and p.to == target.zone then list[#list + 1] = fwd end
            if back and p.to == ctx.zone and p.from == target.zone then list[#list + 1] = back end
        end
        path = Best(list, px, py, tx, ty)
    end
    if not path then
        -- nothing hand-made applies: go around mountains and high-level packs
        local tr = addon.terrain
        local pt = tr and not aP and not aT and tr.Route(target, px, py, inst, ctx)
        if pt then return pt, L("Way around") end
        return
    end

    local pts = path.pts
    if state.path ~= path then
        state.path, state.idx = path, 1
        -- already standing on a later stone (picked the route up midway)
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
        return ph.Route(target, px, py, inst, ctx)
    end
    local pt = pts[state.idx]
    return pt, pt[4] or path.label
end

function ph.Reset()
    state = {}
    if addon.terrain then addon.terrain.Reset() end
end

---------------------------------------------------------------------------
-- Arrow hook
---------------------------------------------------------------------------

local proxy = {}
local lastCheck, lastTarget, lastPt, lastLabel = 0, nil, nil, nil

local function Context()
    local ctx = {
        indoors = IsIndoors and IsIndoors() or false,
        subzone = GetSubZoneText and GetSubZoneText() or "",
        zone = HBD:GetPlayerZone(),
    }
    return ctx
end

-- The stepping stone to show instead of target, as an arrow element, or nil
function ph.ForArrow(target)
    if not target or target == proxy or not ph.IsOn() then return end
    local now = GetTime()
    if target ~= lastTarget or now - lastCheck >= THROTTLE then
        lastCheck, lastTarget = now, target
        local px, py, inst = HBD:GetPlayerWorldPosition()
        lastPt, lastLabel = ph.Route(target, px, py, inst, Context())
    end
    if not lastPt then return end
    proxy.wx, proxy.wy, proxy.instance = lastPt[1], lastPt[2], target.instance
    proxy.title, proxy.step, proxy.real = lastLabel, target.step, target
    return proxy
end

local origDraw = addon.DrawArrow
if origDraw then
    addon.DrawArrow = function(self, ...)
        self = self or addon.arrowFrame
        if not self then return origDraw(self, ...) end
        local real = self.element
        local go = ph.go
        local target = go or real
        local via = target and ph.ForArrow(target)
        self.oxpVia = via or go
        local draw = via or go
        if not draw then return origDraw(self, ...) end
        local wrong = self.wrongContinent
        if go then self.wrongContinent = false end
        self.element = draw
        local ok, err = pcall(origDraw, self, ...)
        self.element = real
        self.wrongContinent = wrong
        if not ok then error(err, 0) end
    end
end

---------------------------------------------------------------------------
-- /oxp path to <zone | x y>: point the arrow somewhere the guide isn't
---------------------------------------------------------------------------

local function FindZone(name)
    name = name:lower()
    local best
    for zoneName, id in pairs(addon.mapId or {}) do
        if type(zoneName) == "string" and type(id) == "number" then
            local z = zoneName:lower()
            if z == name then return zoneName, id end
            if not best and z:find(name, 1, true) == 1 then best = {zoneName, id} end
        end
    end
    if best then return best[1], best[2] end
end

function ph.GoTo(args)
    local x, y = args:match("^(%d+%.?%d*)[,%s]+(%d+%.?%d*)$")
    local go
    if x then
        local zone = HBD:GetPlayerZone()
        local wx, wy, inst = zone and HBD:GetWorldCoordinatesFromZone(tonumber(x) / 100, tonumber(y) / 100, zone)
        if not wx then return Print(L("Couldn't place %s, %s on this map."), x, y) end
        go = {wx = wx, wy = wy, instance = inst, zone = zone, arrow = true,
              title = fmt("%s, %s", x, y)}
    else
        local name, id = FindZone(args)
        if not id then return Print(L("No zone called \"%s\". Try the full name, like /oxp path to Stonetalon Mountains."), args) end
        if HBD:GetPlayerZone() == id then return Print(L("You're already in %s."), name) end
        local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, id)
        if not wx then return Print(L("Couldn't find %s on the map."), name) end
        go = {wx = wx, wy = wy, instance = inst, zone = id, untilZone = id, arrow = true, title = name}
    end
    ph.go = go
    ph.Reset()
    local af = addon.arrowFrame
    if af and not af:IsShown() then af:Show() end
    Print(L("The arrow now leads to %s, through any passes and tunnels it knows. /oxp path stop puts it back on the guide."),
          go.title)
end

function ph.StopGo(arrived)
    if not ph.go then return end
    local title = ph.go.title
    ph.go = nil
    ph.Reset()
    if arrived then Print(L("You've reached %s. The arrow is back on the guide."), title) end
    if addon.UpdateGotoSteps then pcall(addon.UpdateGotoSteps) end
end

local function GoTick()
    local go = ph.go
    if not go then return end
    if go.untilZone then
        if HBD:GetPlayerZone() == go.untilZone then return ph.StopGo(true) end
    else
        local x, y, inst = HBD:GetPlayerWorldPosition()
        if x and inst == go.instance and Dist(x, y, go.wx, go.wy) <= REACH then return ph.StopGo(true) end
    end
    local af = addon.arrowFrame
    if af and not af:IsShown() and ph.IsOn() and not (addon.settings and addon.settings.profile
                                                      and addon.settings.profile.disableArrow) then
        af:Show()
    end
end

---------------------------------------------------------------------------
-- Learning cave entrances
---------------------------------------------------------------------------

local learn = {}

local function AddDoor(area, x, y)
    for _, e in ipairs(area.entrances) do
        local p = e[#e]
        if #e == 1 and Dist(p[1], p[2], x, y) <= SAME_DOOR then
            e.seen = (e.seen or 1) + 1
            return
        end
    end
    area.entrances[#area.entrances + 1] = {{x, y}, seen = 1}
end

local function Fit(area)
    local b = area.box
    local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
    local r = max(b[3] - b[1], b[4] - b[2]) / 2 + 10
    area.circles = {{cx, cy, r}}
end

-- s: an indoor visit {inst, box = {minx, miny, maxx, maxy}, name, door}
function ph.Learn(s, exitX, exitY)
    local saved = ph.Saved()
    if not saved then return end
    local b = s.box
    if max(b[3] - b[1], b[4] - b[2]) < LEARN_MIN then return end
    local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
    for _, a in ipairs(addon.pathHintData or {}) do
        if a.inst == s.inst and Inside(a, cx, cy) then return end -- built-in already
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
        area = {
            source = "learned", inst = s.inst, indoor = true,
            name = (s.name and s.name ~= "") and s.name or L("the cave"),
            box = {b[1], b[2], b[3], b[4]}, entrances = {},
        }
        saved.areas[#saved.areas + 1] = area
    end
    Fit(area)
    if s.door then AddDoor(area, s.door[1], s.door[2]) end
    if exitX then AddDoor(area, exitX, exitY) end
    ph.Changed()
    return area
end

-- Called twice a second. Indoors/outdoors only counts as changed after two
-- readings agree, so a flicker at a cave mouth doesn't make a fake door.
function ph.LearnTick(x, y, inst, indoors)
    if not ph.IsOn() then return end
    if not x then
        learn = {}
        return
    end
    local prev = learn.prev
    if prev and (prev[3] ~= inst or Dist(prev[1], prev[2], x, y) > 60) then
        learn = {} -- hearth, portal or loading screen
    end
    learn.prev = {x, y, inst}

    if learn.indoors == nil then
        learn.indoors = indoors
        if indoors then learn.visit = {inst = inst, box = {x, y, x, y}, name = GetSubZoneText() or ""} end
        return
    end

    if indoors ~= learn.indoors then
        if not learn.flip then
            learn.flip = {x, y}
            return
        end
        local door = learn.flip
        learn.flip = nil
        learn.indoors = indoors
        if indoors then
            learn.visit = {inst = inst, box = {door[1], door[2], door[1], door[2]},
                           name = GetSubZoneText() or "", door = door}
        elseif learn.visit then
            local visit = learn.visit
            learn.visit = nil
            ph.Learn(visit, door[1], door[2])
        end
    else
        learn.flip = nil
    end

    local v = learn.visit
    if v and learn.indoors then
        local b = v.box
        b[1], b[2] = min(b[1], x), min(b[2], y)
        b[3], b[4] = max(b[3], x), max(b[4], y)
        if v.name == "" then v.name = GetSubZoneText() or "" end
    end
end

local ticker = CreateFrame("Frame")
local tickWait = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    tickWait = tickWait + elapsed
    if tickWait < 0.5 then return end
    tickWait = 0
    if type(OXPData) ~= "table" then return end
    GoTick()
    if (IsInInstance and IsInInstance()) or (UnitOnTaxi and UnitOnTaxi("player"))
        or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        return ph.LearnTick(nil)
    end
    local x, y, inst = HBD:GetPlayerWorldPosition()
    ph.LearnTick(x, y, inst, IsIndoors() and true or false)
end)

---------------------------------------------------------------------------
-- /oxp path
---------------------------------------------------------------------------

local recording

local function TargetName(t)
    local step = t.step
    local s = t.title or (step and (step.arrowtext or step.title))
    if s then s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|c%u+_[%w_]-_", "") end
    return s
end

local function Finish()
    local rec = recording
    recording = nil
    if not rec or #rec.pts == 0 then return end
    local saved = ph.Saved()
    if not saved then return end
    local t = rec.target
    if t.zone and rec.zone and t.zone ~= rec.zone then
        saved.passes[#saved.passes + 1] = {
            source = "recorded", inst = t.inst, from = rec.zone, to = t.zone,
            name = rec.label, pts = rec.pts, twoWay = true,
            fromZ = rec.zonePos, toZ = t.zonePos,
        }
        ph.Changed()
        return Print(L("Saved a %d-point pass toward the next zone."), #rec.pts)
    end
    local last = rec.pts[#rec.pts]
    local r = max(15, min(120, 0.6 * Dist(last[1], last[2], t.x, t.y)))
    for _, a in ipairs(saved.areas) do
        if a.source == "recorded" and a.inst == t.inst and Inside(a, t.x, t.y) then
            a.entrances[#a.entrances + 1] = rec.pts
            ph.Changed()
            return Print(L("Added another way into %s (%d points)."), a.name, #rec.pts)
        end
    end
    local name = rec.label or TargetName(rec.target) or L("this spot")
    saved.areas[#saved.areas + 1] = {
        source = "recorded", inst = t.inst, indoor = rec.indoor, name = name,
        circles = {{t.x, t.y, r}}, entrances = {rec.pts}, zonePos = t.zonePos,
    }
    ph.Changed()
    Print(L("Saved a %d-point path to %s. The arrow uses it from now on."), #rec.pts, name)
end

local function ZonePos()
    local x, y, zone = HBD:GetPlayerZonePosition()
    if x then return {zone, x * 100, y * 100} end
end

local function Add(label)
    local af = addon.arrowFrame
    local t = af and af.element
    if not (t and t.wx) then
        return Print(L("There's no arrow target right now. Start the step you need a path for, then try again."))
    end
    local px, py, inst = HBD:GetPlayerWorldPosition()
    if not px then return end
    if t.instance ~= inst then return Print(L("The arrow's target is on another continent.")) end
    if recording and (recording.target.x ~= t.wx or recording.target.y ~= t.wy) then Finish() end
    if not recording then
        local tz
        if t.zone and HBD.GetZoneCoordinatesFromWorld then
            local zx, zy = HBD:GetZoneCoordinatesFromWorld(t.wx, t.wy, t.zone)
            if zx then tz = {t.zone, zx * 100, zy * 100} end
        end
        recording = {
            target = {x = t.wx, y = t.wy, inst = inst, zone = t.zone, zonePos = tz, step = t.step, title = t.title},
            pts = {}, zone = HBD:GetPlayerZone(), zonePos = ZonePos(),
        }
    end
    if label and label ~= "" then recording.label = recording.label or label end
    recording.indoor = IsIndoors() and true or false
    local zp = ZonePos()
    recording.pts[#recording.pts + 1] = {px, py, zone = zp}
    Print(L("Stepping stone %d saved. Walk to the next one and type /oxp path add again, or /oxp path done when you're there."),
          #recording.pts)
end

local function Undo()
    if recording and #recording.pts > 0 then
        table.remove(recording.pts)
        return Print(L("Removed the last stepping stone (%d left)."), #recording.pts)
    end
    Print(L("Nothing to undo."))
end

local function Clear()
    local saved = ph.Saved()
    local px, py, inst = HBD:GetPlayerWorldPosition()
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
        if near then table.remove(saved.areas, i); n = n + 1 end
    end
    for i = #saved.passes, 1, -1 do
        local p = saved.passes[i]
        if p.inst == inst and Near(p.pts) then table.remove(saved.passes, i); n = n + 1 end
    end
    ph.Changed()
    ph.Reset()
    Print(L("Removed %d saved path(s) near you."), n)
end

function ph.Command(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = args:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local saved = ph.Saved()
    if cmd == "add" then
        Add(rest)
    elseif cmd == "done" or cmd == "save" then
        if not recording then return Print(L("Nothing recorded yet. Use /oxp path add first.")) end
        Finish()
    elseif cmd == "undo" then
        Undo()
    elseif cmd == "clear" then
        Clear()
    elseif cmd == "to" or cmd == "go" then
        if rest == "" then return Print(L("Where to? For example /oxp path to Stonetalon Mountains, or /oxp path to 36.4 7.2 on this map.")) end
        ph.GoTo(rest)
    elseif cmd == "stop" then
        if not ph.go then return Print(L("The arrow is already following the guide.")) end
        ph.StopGo()
        Print(L("The arrow is back on the guide."))
    elseif cmd == "off" or cmd == "on" then
        if saved then saved.off = cmd == "off" end
        ph.Reset()
        Print(cmd == "off" and L("Arrow paths are off: the arrow points straight at the target.")
              or L("Arrow paths are on."))
    else
        local learned, recorded = 0, 0
        for _, a in ipairs(saved and saved.areas or {}) do
            if a.source == "learned" then learned = learned + 1 else recorded = recorded + 1 end
        end
        recorded = recorded + #(saved and saved.passes or {})
        Print(L("Arrow paths are %s. Built in: %d, learned: %d, recorded by you: %d."),
              ph.IsOn() and L("on") or L("off"), #(addon.pathHintData or {}), learned, recorded)
        Print(L("/oxp path add [name] - save where you stand as a stepping stone toward the arrow's target"))
        Print(L("/oxp path done - finish the path   /oxp path undo - drop the last stone"))
        Print(L("/oxp path to <zone> or <x y> - lead the arrow there (/oxp path stop to go back to the guide)"))
        Print(L("/oxp path clear - forget saved paths near you   /oxp path off|on"))
    end
end
