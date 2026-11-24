-- Arrow walk simulation (not part of the suite: run with tools/run_arrowsim.py).
-- Real zone sizes (HereBeDragons' map rects), real guides, real OpenXP_Nav
-- walks. For every step whose spot is in the same zone as the step before:
--   follower: a player who always runs where the arrow points
--   straight: a player who runs in a straight line at the spot
-- and records where the arrow turns around, loops or never arrives.
local ROOT, OUT, FROM, TO, ONLY = ...
ONLY = tonumber(ONLY)
if ONLY then DEBUGWP = os.getenv("DEBUGWP") end
FROM, TO = tonumber(FROM) or 1, tonumber(TO) or math.huge
local FakeWoW = dofile(ROOT .. "/tests/lib/fakewow.lua")
local RECTS = dofile(OUT .. "/rects.lua")

local game = FakeWoW.New(ROOT, { faction = "Alliance", race = "Human", class = "WARRIOR", level = 60, map = 1429, x = 50, y = 50 })
local OXP = game:LoadAddon()
game:Login()

-- real map rects, the way HereBeDragons does it
local hbd = LibStub("HereBeDragons-2.0")
function hbd:GetWorldCoordinatesFromZone(x, y, map)
    local r = map and RECTS[map]
    if not (r and x and y) then return nil end
    return r.left + (r.right - r.left) * x, r.top + (r.bottom - r.top) * y, r.inst
end
function hbd:GetZoneCoordinatesFromWorld(wx, wy, map, allowOutside)
    local r = map and RECTS[map]
    if not (r and wx) then return nil end
    local x, y = (wx - r.left) / (r.right - r.left), (wy - r.top) / (r.bottom - r.top)
    if not allowOutside and (x < 0 or x > 1 or y < 0 or y > 1) then return nil end
    return x, y
end
function hbd:GetPlayerWorldPosition()
    local p = game.pos
    if p.wx then return p.wx, p.wy, p.inst end
    return self:GetWorldCoordinatesFromZone(p.x / 100, p.y / 100, p.map)
end
function hbd:GetPlayerZonePosition()
    local p = game.pos
    if p.wx then
        local x, y = self:GetZoneCoordinatesFromWorld(p.wx, p.wy, p.map, true)
        return x, y, p.map
    end
    return p.x / 100, p.y / 100, p.map
end

-- OpenXP_Nav, as the game would load it
local NAV = {}
local toc = io.open(ROOT .. "/OpenXP_Nav/OpenXP_Nav.toc"):read("*a")
for line in toc:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then
        assert(loadfile(ROOT .. "/OpenXP_Nav/" .. line:gsub("\\", "/")))("OpenXP_Nav", NAV)
    end
end
OpenXP_Nav = NAV
OXP.WalkPaths.Use(NAV)

local Places, Target = OXP.Places, OXP.Target
local DT, SPEED = 0.2, 7          -- seconds per tick, yards per second
local STEP = DT * SPEED
local ARRIVE = 8

local out = io.open(OUT .. "/arrowsim-" .. FROM .. ".tsv", "w")
out:write("guide\tstep\tmap\tfrom\tto\tstraight\tfollow_walked\tfollow_ratio\tfollow_turnarounds\tfollow_arrived\tstraight_back_secs\tstraight_flips\tstraight_max_dev\tstart\ttitle_flips\twalk_flips\n")

local function ang(dx, dy) return math.atan2(dy, dx) end
local function diff(a, b)
    local d = (a - b + math.pi) % (2 * math.pi) - math.pi
    return math.abs(d)
end

local function place(wx, wy, inst, map)
    game.pos = { map = map, x = 50, y = 50, wx = wx, wy = wy, inst = inst }
end

local function aim()
    game.now = game.now + DT
    local cur = Target.Update()
    if not cur or not cur.wx then return nil end
    return cur.wx, cur.wy, cur
end

-- run where the arrow points until "Here" (or give up)
local function follow(sx, sy, inst, map, real, dist)
    place(sx, sy, inst, map)
    local px, py = sx, sy
    local walked, turns, lastA = 0, 0, nil
    local lastGoal
    FLIPS = { title = 0, walk = 0, lastTitle = nil, lastWalk = nil }
    local cap = math.max(400, dist * 6 / STEP)
    for _ = 1, cap do
        if Places.Distance(px, py, real.wx, real.wy) <= ARRIVE then return walked, turns, true end
        local ax, ay, cur = aim()
        if not ax then return walked, turns, "noaim" end
        if cur.inside then return walked, turns, true end
        local goal = cur.focus or cur.real or cur
        if goal.wx and Places.Distance(px, py, goal.wx, goal.wy) <= (cur.focus and 25 or ARRIVE) then return walked, turns, true end
        -- a pinpoint reached: the arrow moves on to the next one
        if lastGoal and (lastGoal[1] ~= goal.wx or lastGoal[2] ~= goal.wy) and Places.Distance(px, py, lastGoal[1], lastGoal[2]) <= 30 then return walked, turns, true end
        lastGoal = { goal.wx, goal.wy }
        if FLIPS.lastTitle and FLIPS.lastTitle ~= cur.title then FLIPS.title = FLIPS.title + 1 end
        if FLIPS.lastWalk ~= nil and FLIPS.lastWalk ~= (cur.walkPath == true) then FLIPS.walk = FLIPS.walk + 1 end
        FLIPS.lastTitle, FLIPS.lastWalk = cur.title, cur.walkPath == true
        local dx, dy = ax - px, ay - py
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 0.01 then return walked, turns, "zero:" .. tostring(cur.title) .. ":" .. tostring(cur.walkPath) end
        local a = ang(dx, dy)
        if lastA and diff(a, lastA) > math.rad(135) then
            turns = turns + 1
            if ONLY and turns <= 6 then
                local zx, zy = Places.ToZone(px, py, map, true)
                local ax2, ay2 = Places.ToZone(ax, ay, map, true)
                io.stderr:write(("TURN t%d at %.2f,%.2f aim %.2f,%.2f walk=%s left=%s title=%s focus=%s\n"):format(_, zx, zy, ax2, ay2, tostring(cur.walkPath), tostring(cur.left), tostring(cur.title), tostring(cur.focus ~= nil)))
            end
        end
        lastA = a
        if ONLY and VERBOSE and _ % 5 == 0 then
            local zx, zy = Places.ToZone(px, py, map, true)
            local ax2, ay2 = Places.ToZone(ax, ay, map, true)
            io.stderr:write(("t%d at %.2f,%.2f aim %.2f,%.2f walk=%s left=%s title=%s\n"):format(_, zx, zy, ax2, ay2, tostring(cur.walkPath), tostring(cur.left), tostring(cur.title)))
        end
        local s = math.min(STEP, d)
        px, py = px + dx / d * s, py + dy / d * s
        walked = walked + s
        place(px, py, inst, map)
    end
    return walked, turns, false
end

-- run straight at the spot; how often does the arrow say "turn around"?
local function straight(sx, sy, inst, map, real)
    place(sx, sy, inst, map)
    local px, py = sx, sy
    local back, flips, maxDev, wasBack = 0, 0, 0, false
    local heading = ang(real.wx - px, real.wy - py)
    while Places.Distance(px, py, real.wx, real.wy) > 30 do
        local ax, ay, cur = aim()
        if not ax or cur.inside then break end
        local dev = diff(ang(ax - px, ay - py), heading)
        if dev > maxDev then maxDev = dev end
        local isBack = dev > math.rad(100)
        if isBack then back = back + DT end
        if isBack ~= wasBack then flips = flips + 1 end
        wasBack = isBack
        px, py = px + math.cos(heading) * STEP, py + math.sin(heading) * STEP
        place(px, py, inst, map)
    end
    return back, flips, math.deg(maxDev)
end

local legs = 0
local guides = {}
for _, g in ipairs(OXP.Registry.All()) do
    if (g.faction == nil or g.faction == "Alliance") and not (g.group or ""):lower():find("dungeon") then
        guides[#guides + 1] = g
    end
end
io.stderr:write(("%d guides\n"):format(#guides))
for gi, g in ipairs(guides) do if ONLY then io.stderr:write(gi .. " " .. g.name .. "\n") end end

for gi, g in ipairs(guides) do
    if gi >= FROM and gi <= TO then
        local prev
        for i = 1, #g.steps do
            local ok, err = pcall(OXP.Engine.Load, g.key, i)
            local real = ok and (not ONLY or i == ONLY) and Target.Real()
            if ONLY and i == ONLY - 1 then real = ok and Target.Real() end
            if real and real.wx then
                local spot = { wx = real.wx, wy = real.wy, instance = real.instance, map = real.map, x = real.x, y = real.y }
                if prev and prev.map == spot.map and prev.instance == spot.instance then
                    local dist = Places.Distance(prev.wx, prev.wy, spot.wx, spot.wy)
                    if dist > 40 then
                        -- start at the last spot, and 50 yards to its side (cutting a corner)
                        local nx, ny = -(spot.wy - prev.wy) / dist, (spot.wx - prev.wx) / dist
                        for _, s in ipairs({ { "prev", prev.wx, prev.wy }, { "side+50", prev.wx + nx * 50, prev.wy + ny * 50 }, { "side-50", prev.wx - nx * 50, prev.wy - ny * 50 } }) do
                            game.now = game.now + 10
                            OXP.WalkPaths.Reset()
                            local w, turns, arrived = follow(s[2], s[3], spot.instance, spot.map, spot, dist)
                            game.now = game.now + 10
                            OXP.WalkPaths.Reset()
                            local back, flips, dev = straight(s[2], s[3], spot.instance, spot.map, spot)
                            out:write(("%s\t%d\t%d\t%.2f,%.2f\t%.2f,%.2f\t%d\t%d\t%.2f\t%d\t%s\t%.1f\t%d\t%d\t%s\t%d\t%d\n"):format(
                                g.name, i, spot.map, prev.x or 0, prev.y or 0, spot.x or 0, spot.y or 0, dist, w, w / dist,
                                turns, tostring(arrived), back, flips, dev, s[1], FLIPS.title, FLIPS.walk))
                            legs = legs + 1
                        end
                        out:flush()
                    end
                end
                prev = spot
            end
        end
        io.stderr:write(("guide %d %s: %d legs so far\n"):format(gi, g.name, legs))
    end
end
out:close()
io.stderr:write("done " .. legs .. " legs, errors " .. #game.errors .. "\n")
for k = 1, math.min(5, #game.errors) do io.stderr:write(tostring(game.errors[k]) .. "\n") end
