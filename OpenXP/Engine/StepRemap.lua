-- Saved places after a guide rebuild moves steps (2.0.2: class quest chains
-- split by level, GitHub #90). A character's place in a guide is a step
-- index (Runner.lua); when steps move, Data/StepRemap.lua (made by
-- tools/step_remap.py) says where each old step is now, and this moves the
-- saved step, skips and statuses once, before the guide is restored. A step
-- that moved to another guide counts as the next one that stayed.
local _, OXP = ...

local Remap = {}
OXP.StepRemapper = Remap

local function Move(list, map)
    if type(list) ~= "table" then return list end
    local out = {}
    for i, v in pairs(list) do
        local j = type(i) == "number" and map[i] or nil
        if j then
            if out[j] == nil then out[j] = v end
        elseif type(i) ~= "number" then
            out[i] = v
        end
    end
    return out
end

--- Move this character's saved places. Returns how many guides moved.
function Remap.Apply(data, char)
    data, char = data or OXP.StepRemap, char or OXP.char
    if type(data) ~= "table" or type(char) ~= "table" then return 0 end
    if (char.stepRemap or 0) >= (data.version or 0) then return 0 end
    char.stepRemap = data.version
    local n = 0
    for key, save in pairs(type(char.guides) == "table" and char.guides or {}) do
        local map = data.guides[key]
        if map and type(save) == "table" then
            local was = save.step
            if type(save.step) == "number" then
                save.step = map[save.step] or map[#map] or save.step
            end
            save.skipped = Move(save.skipped, map)
            save.status = Move(save.status, map)
            -- steps that moved in behind your place (a class step now at its
            -- level): marked jumped, so /oxp catchup lists them
            if type(was) == "number" and type(save.step) == "number" then
                local old = {}
                for i = 1, #map - 1 do old[map[i]] = true end
                for j = 1, save.step - 1 do
                    if not old[j] and save.status[j] == nil then save.status[j] = "jumped" end
                end
            end
            n = n + 1
        end
    end
    return n
end

OXP.OnLoaded(function()
    local ok, err = pcall(Remap.Apply)
    if not ok then OXP.report(err) end
end)
