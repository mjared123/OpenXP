-- Beside the guide card, both keybindable (Key Bindings > AddOns > OpenXP):
--   item button    uses the quest item the shown steps need (a step's
--                  "item" goal you carry, or the item a quest in the step
--                  gives you to use); Shift-drag moves it
--   targets        a small movable list of the mobs and NPCs the shown steps
--                  still need, each with its portrait; click one to target
--                  it, or bind a key to the first row
-- They are secure buttons, so the game only lets them change outside
-- combat; a change asked for in combat waits until combat ends.
local ADDON, OXP = ...

local Buttons = {}
OXP.ActionButtons = Buttons

local Engine, Style, L = OXP.Engine, OXP.Style, OXP.L
local C = Style.C

BINDING_HEADER_OPENXP = "OpenXP"
_G["BINDING_NAME_CLICK OpenXPItemButton:LeftButton"] = "Use the quest item"
_G["BINDING_NAME_CLICK OpenXPTargetButton:LeftButton"] = "Target the step's NPC or mob"

-- Bag and item calls: Classic Era 1.15 has both C_Container / C_Item and the
-- old globals, other clients one or the other. Looked up on each call.
-- Forever has retail-style combat restrictions: some calls can hand back a
-- "secret" value, and comparing one throws, so those read as unknown here.
local function Readable(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function GetItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    local n = fn and Readable(fn(id))
    return type(n) == "number" and n or 0
end
local function GetItemIcon(id)
    local fn = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon
    return fn and Readable(fn(id)) or nil
end
-- start, duration in seconds (0, 0: none, or the game won't say)
local function GetItemCooldown(id)
    local fn = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
    if not fn then return 0, 0 end
    local ok, start, duration = pcall(fn, id)
    if not ok then return 0, 0 end
    start, duration = Readable(start), Readable(duration)
    if type(start) ~= "number" or type(duration) ~= "number" then return 0, 0 end
    return start, duration
end
local function InCombat() return InCombatLockdown and InCombatLockdown() or false end

------------------------------------------------------------------------
-- The item button: a secure action button (type "item") parented to and
-- anchored on UIParent only, so it never makes another frame protected.
-- Its attributes, shown state and spot only change outside combat; the
-- look (icon, count, cooldown, range tint, key) changes any time.
------------------------------------------------------------------------

local ITEM_SIZE = 36
local item = CreateFrame("Button", "OpenXPItemButton", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
Buttons.item = item
item:SetSize(ITEM_SIZE, ITEM_SIZE)
item:RegisterForClicks("AnyUp", "AnyDown")
item:SetMovable(true)
item:SetClampedToScreen(true)
item:SetFrameStrata("MEDIUM")
-- the skin's panel with an accent edge (Style.Repaint repaints it)
Style.Backdrop(item, C.bgSolid, C.blue)
item.icon = item:CreateTexture(nil, "ARTWORK")
item.icon:SetPoint("TOPLEFT", 2, -2)
item.icon:SetPoint("BOTTOMRIGHT", -2, 2)
item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
item.hl = item:CreateTexture(nil, "HIGHLIGHT")
item.hl:SetAllPoints(item.icon)
item.hl:SetColorTexture(1, 1, 1, 0.15)
item.cooldown = CreateFrame("Cooldown", nil, item, "CooldownFrameTemplate")
item.cooldown:SetAllPoints(item.icon)
-- count and key sit above the cooldown spiral
item.over = CreateFrame("Frame", nil, item)
item.over:SetAllPoints()
item.over:SetFrameLevel((item:GetFrameLevel() or 1) + 3)
item.count = item.over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
item.count:SetPoint("BOTTOMRIGHT", -3, 3)
item.hotkey = item.over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
item.hotkey:SetPoint("TOPRIGHT", -3, -3)
item.hotkey:SetJustifyH("RIGHT")
Style.TextColor(item.hotkey, C.dim)
item:Hide()

local ITEM_BINDING = "CLICK OpenXPItemButton:LeftButton"

-- "SHIFT-F" -> "s-F", "BUTTON4" -> "M4", like the action bars: the
-- modifiers by hand, the key itself by GetBindingText(key, abbreviate)
local MOD_SHORT = { SHIFT = "s-", CTRL = "c-", ALT = "a-", META = "m-" }
local function ShortKey(key)
    if type(key) ~= "string" or key == "" then return "" end
    local mods, base = "", key
    while true do
        local mod, rest = base:match("^(%u+)%-(.+)$")
        if not (mod and MOD_SHORT[mod]) then break end
        mods, base = mods .. MOD_SHORT[mod], rest
    end
    local n = base:match("^BUTTON(%d+)$")
    local text
    if n then
        text = "M" .. n
    else
        text = GetBindingText and GetBindingText(base, true)
        if type(text) ~= "string" or text == "" then text = base end
    end
    return mods .. text
end

--- The bound key, drawn on the button's corner.
function Buttons.PaintKey()
    local key = GetBindingKey and GetBindingKey(ITEM_BINDING)
    item.hotkey:SetText(ShortKey(key))
end

local RANGE_RED = { 0.9, 0.25, 0.25 }

--- Icon tint: red when the target is out of the item's range, grey when
--- you no longer carry it (used up in combat, the button waits to hide).
local function PaintIcon()
    local id = item.itemID
    if not id then return end
    local n = GetItemCount(id) or 0
    item.icon:SetDesaturated(n == 0 or item.stale == true)
    if n == 0 or item.stale then
        item.icon:SetVertexColor(0.5, 0.5, 0.5)
    elseif item.outOfRange then
        item.icon:SetVertexColor(RANGE_RED[1], RANGE_RED[2], RANGE_RED[3])
    else
        item.icon:SetVertexColor(1, 1, 1)
    end
end

-- Is the item in range of your target? true / false, or nil when the game
-- can't say (no target, an item with no range, in combat). Forever blocks
-- addons' range checks in combat (on friendly targets too), so it isn't
-- asked then and the tint clears.
local function InRange(id)
    if not (UnitExists and UnitExists("target")) then return nil end
    if InCombat() then return nil end
    local fn = (C_Item and C_Item.IsItemInRange) or _G.IsItemInRange
    if not fn then return nil end
    local ok, r = pcall(fn, id, "target")
    if not ok then return nil end
    r = Readable(r)
    if r == 1 then r = true elseif r == 0 then r = false end
    return r
end

function Buttons.UpdateRange()
    local out = false
    if item.itemID and item:IsShown() then out = InRange(item.itemID) == false end
    if out ~= item.outOfRange then
        item.outOfRange = out
        PaintIcon()
    end
end

-- a few times a second, only while there's a target to measure to
local RANGE_EVERY = 0.2
item:SetScript("OnUpdate", function(self, elapsed)
    if not (self.itemID and self:IsShown()) then return end
    self.rangeWait = (self.rangeWait or 0) - (elapsed or 0)
    if self.rangeWait > 0 then return end
    self.rangeWait = RANGE_EVERY
    if self.outOfRange or (UnitExists and UnitExists("target")) then Buttons.UpdateRange() end
end)

local function UpdateCooldown()
    local cd = item.cooldown
    local start, duration = 0, 0
    if item.itemID then start, duration = GetItemCooldown(item.itemID) end
    if duration > 0 then cd:SetCooldown(start, duration) else cd:Clear() end
end
Buttons.UpdateCooldown = UpdateCooldown

--- Draw what the item button shows (safe in combat: no attributes).
function Buttons.PaintItem()
    local id = item.itemID
    if not id then return end
    item.icon:SetTexture(GetItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    local n = GetItemCount(id) or 0
    item.count:SetText(n > 1 and tostring(n) or "")
    PaintIcon()
    UpdateCooldown()
    Buttons.PaintKey()
end

--- The skin's accent on the button edges (Settings > Guide card > Skin).
function Buttons.ApplySkin()
    Style.PaintBackdrop(item)
    Style.TextColor(item.hotkey, C.dim)
end
Style.OnRepaint(Buttons.ApplySkin)

------------------------------------------------------------------------
-- The targets frame: a small movable list of who the shown steps need,
-- one row each (the mob's portrait once you've seen it, its name), click
-- a row to target that one. The first row is OpenXPTargetButton, the one
-- you can bind a key to: it targets the first of them that's near you.
-- Mobs whose objective is done drop off the list (Goals.NeededMobs).
------------------------------------------------------------------------

local MAX_ROWS, ROW_H, ROW_W = 5, 26, 190
local ENEMY, FRIEND = { 1, 112 / 255, 67 / 255 }, { 61 / 255, 187 / 255, 122 / 255 }
local MAPICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Map\\"

local box = CreateFrame("Frame", "OpenXPTargets", UIParent, "BackdropTemplate")
Buttons.box = box
box:SetSize(ROW_W, 20 + ROW_H)
box:SetClampedToScreen(true)
box:SetMovable(true)
box:EnableMouse(true)
box:RegisterForDrag("LeftButton")
box:SetFrameStrata("MEDIUM")
Style.Backdrop(box, C.bg, C.border, { card = true })
box.title = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
box.title:SetPoint("TOPLEFT", 8, -5)
Style.TextColor(box.title, C.dim)
box.key = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
box.key:SetPoint("TOPRIGHT", -8, -5)
Style.TextColor(box.key, C.faint)
box:Hide()

local rows = {}
local function Row(i)
    if rows[i] then return rows[i] end
    local name = i == 1 and "OpenXPTargetButton" or ("OpenXPTargetRow" .. i)
    local b = CreateFrame("Button", name, box, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -18 - (i - 1) * ROW_H)
    b:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -18 - (i - 1) * ROW_H)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT", 0, -4)
    b.bar:SetPoint("BOTTOMLEFT", 0, 4)
    b.bar:SetWidth(2)
    b.slot = CreateFrame("Frame", nil, b)
    b.slot:SetSize(20, 20)
    b.slot:SetPoint("LEFT", 8, 0)
    b.placeholder = b.slot:CreateTexture(nil, "ARTWORK")
    b.placeholder:SetAllPoints()
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT", b.slot, "RIGHT", 8, 0)
    b.text:SetPoint("RIGHT", -8, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        self.hl:SetColorTexture(1, 1, 1, 0.08)
        if not self.unitName then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L("Target") .. " " .. self.unitName, 1, 1, 1)
        if self == rows[1] and Buttons.count and Buttons.count > 1 then
            GameTooltip:AddLine(L("Or the next one on the list, when this one isn't near."), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(L("Bind a key: Key Bindings > AddOns > OpenXP"), 0.6, 0.6, 0.6)
        if not OXP.settings.lockFrames then GameTooltip:AddLine(L("Drag the title to move this."), 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.hl:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    b:Hide()
    rows[i] = b
    return b
end

-- the first row is the bindable button (the tests and older code call it `target`)
local target = Row(1)
Buttons.target, Buttons.rows = target, rows

-- Portraits: the game only draws one from a unit you can see, so each mob's
-- is drawn when it is your target, under your mouse or on a nameplate, and
-- kept (one texture per name, the oldest reused past PORTRAITS).
local PORTRAITS = 24
local portraits, nPortraits = {}, 0

local function Portrait(name)
    return name and portraits[name]
end

function Buttons.SeeUnit(unit)
    if not (unit and UnitExists and UnitExists(unit)) or (UnitIsPlayer and UnitIsPlayer(unit)) then return end
    local name = OXP.Util.UnitName(unit) -- secret in dungeons (GitHub #98)
    if not name or not SetPortraitTexture then return end
    local listed = false
    for _, r in ipairs(rows) do if r.unitName == name then listed = true end end
    if not listed then return end
    local t = portraits[name]
    if not t then
        if nPortraits >= PORTRAITS then
            local oldest, oldName
            for n, tex in pairs(portraits) do
                if not oldest or tex.seen < oldest.seen then oldest, oldName = tex, n end
            end
            portraits[oldName] = nil
            t = oldest
        else
            t = box:CreateTexture(nil, "ARTWORK", nil, 1)
            nPortraits = nPortraits + 1
        end
        portraits[name] = t
    end
    t.seen = GetTime and GetTime() or 0
    SetPortraitTexture(t, unit)
    Buttons.PaintRows()
end

------------------------------------------------------------------------
-- What the buttons should do now
------------------------------------------------------------------------

local function ActiveSteps()
    local out = {}
    for _, pos in ipairs(Engine.GetActive()) do out[#out + 1] = Engine.GetSteps()[pos] end
    return out
end

-- Walking a quest chain ("Do the chain", "Finish it", "Get the quest"):
-- the card shows the walk's quest, so the buttons follow that quest, not
-- the guide step underneath (GitHub #14: targets stuck during a chain).
local function WalkQuest()
    local card = OXP.Card
    if not (card and card.detour and card.DetourQuest) then return nil end
    return card.DetourQuest()
end

-- who to talk to or what to kill for the walk's quest
local function WalkTarget(id)
    local Quests, QuestDB = OXP.Quests, OXP.QuestDB
    local info = QuestDB.Info(id) or {}
    if not Quests.IsOnQuest(id) then
        -- picked up from a person (an item or object start has no one to target)
        return info.s and info.s[2] ~= 0 and info.s[1] or nil
    end
    for i = 1, 8 do
        local o = Quests.GetObjective(id, i)
        if not o then break end
        if not o.done then
            local list = QuestDB.ObjectiveSources(id, i)
            for _, src in ipairs(list or {}) do
                if src.kind == "NPC" and src.name then return src.name end
            end
            return nil
        end
    end
    return info.f and info.f[1] or nil
end

-- A step's "item" lines ("Use the flare on ...") belong to the goal line
-- just before them (like its "mob" lines, Goals.NeededMobs): the item is
-- wanted only while that goal is still to do. One before any goal counts
-- while the step has anything left to do.
-- An item in your bags by its name (a "Use <item>" line with no item id):
-- id or nil. Bags 0-4.
local function BagItemByName(name)
    if not name or name == "" then return nil end
    local slots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    local idAt = (C_Container and C_Container.GetContainerItemID) or _G.GetContainerItemID
    if not (slots and idAt and GetItemInfo) then return nil end
    local want = name:lower()
    for bag = 0, 4 do
        for slot = 1, (slots(bag) or 0) do
            local id = idAt(bag, slot)
            local n = id and GetItemInfo(id)
            if type(n) == "string" and n:lower() == want then return id end
        end
    end
end
Buttons.BagItemByName = BagItemByName

-- "Use Earth Sapta (beside the Spirit Stone)" -> "Earth Sapta"
local function UseName(text)
    local plain = text and OXP.Text.Strip(text)
    local name = plain and plain:match("^Use (.-)%s*%(") or (plain and plain:match("^Use (.+)$"))
    return name and name:gsub("%s+$", "") or nil
end

-- The items the step says to use, while what they're for is open. An
-- "item" line sits between the goal it follows and the one it leads to
-- (Call of Earth: accept part 2, use the Earth Sapta, turn in part 2), so
-- it counts while either of those is still to do (before 2.0.0-dev5 only
-- the goal before it counted: once part 2 was accepted the Sapta button
-- never showed). A "Use <item>" line without an item id is looked up in
-- your bags by name.
local function StepItems(step, out)
    local Goals = OXP.Goals
    local goals = step.goals or {}
    local function Open(g) return g and Goals.State(g, step.marks) == "todo" end
    local function Around(i)
        local before, after
        for j = i - 1, 1, -1 do
            local k = goals[j][1]
            if Goals.Blocks(k) and k ~= "reach" then before = goals[j] break end
        end
        for j = i + 1, #goals do
            local k = goals[j][1]
            if Goals.Blocks(k) and k ~= "reach" then after = goals[j] break end
        end
        return before, after
    end
    local anyOpen = false
    for _, g in ipairs(goals) do
        if Goals.Blocks(g[1]) and Open(g) then anyOpen = true end
    end
    if not anyOpen then return end
    for i, g in ipairs(goals) do
        if g[1] == "item" and g.item then
            local before, after = Around(i)
            if (not before and not after) or Open(before) or Open(after) then
                local owner = Open(after) and after or before
                out[#out + 1] = { id = g.item, quest = owner and owner.quest }
            end
        elseif g.text and (g[1] == "complete" or g[1] == "text") and Open(g[1] == "text" and select(2, Around(i)) or g) then
            local id = BagItemByName(UseName(g.text))
            if id then out[#out + 1] = { id = id, quest = g.quest } end
        end
    end
end

-- A usable quest item in your bags for one of `quests` (the game says which
-- quest an item is for): id, quest or nil. Like 1.x's item buttons, for
-- quests whose step doesn't name the item (2.0.2, CurseForge).
local function BagQuestItem(quests)
    local info = C_Container and C_Container.GetContainerItemQuestInfo or _G.GetContainerItemQuestInfo
    local slots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    local idAt = (C_Container and C_Container.GetContainerItemID) or _G.GetContainerItemID
    local spell = (C_Item and C_Item.GetItemSpell) or _G.GetItemSpell
    if not (info and slots and idAt and spell) then return nil end
    for bag = 0, 4 do
        for slot = 1, (slots(bag) or 0) do
            local id = idAt(bag, slot)
            if id then
                local a, b = info(bag, slot)
                local questID
                if type(a) == "table" then questID = a.questID else questID = b end -- C_Container: a table
                questID = Readable(questID)
                if questID and quests[questID] and spell(id) then return id, questID end
            end
        end
    end
end
Buttons.BagQuestItem = BagQuestItem

--- The item to put on the item button: id (and the quest it's for) or nil.
--- Only an item you carry, and only while what it's for is still open.
function Buttons.WantedItem()
    local walk = WalkQuest()
    if not walk then
        local found = {}
        for _, step in ipairs(ActiveSteps()) do StepItems(step, found) end
        for _, e in ipairs(found) do
            if (GetItemCount(e.id) or 0) > 0 then return e.id, e.quest end
        end
    end
    -- a quest in the step that hands you an item to use (the quest log's
    -- special item), while its objectives are still open
    if GetQuestLogSpecialItemInfo and GetNumQuestLogEntries and GetQuestLogTitle then
        local quests = {}
        if walk then
            quests[walk] = true
        else
            for _, step in ipairs(ActiveSteps()) do
                for _, g in ipairs(step.goals) do
                    if g.quest and OXP.Goals.State(g, step.marks) == "todo" then quests[g.quest] = true end
                end
            end
        end
        for i = 1, GetNumQuestLogEntries() or 0 do
            local _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if not isHeader and questID and quests[questID] then
                local link, _, _, showWhenComplete = GetQuestLogSpecialItemInfo(i)
                local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
                local done = isComplete == 1 or isComplete == true
                if id and (not done or showWhenComplete) and (GetItemCount(id) or 0) > 0 then return id, questID end
            end
        end
        local open = {}
        for q in pairs(quests) do
            if not (OXP.Quests.IsComplete and OXP.Quests.IsComplete(q)) then open[q] = true end
        end
        local id, q = BagQuestItem(open)
        if id then return id, q end
    end
end

--- Who the targets list shows: { { name = n, enemy = bool }, ... }, the
--- mobs still needed first (in the guide's order), then who to talk to.
function Buttons.WantedTargets()
    local walk = WalkQuest()
    if walk then
        local name = WalkTarget(walk)
        return name and { { name = name, enemy = OXP.Quests.IsOnQuest(walk) and not OXP.Quests.IsComplete(walk) } } or {}
    end
    -- Only what the shown steps need right now (like 1.x): the mobs of
    -- objectives still open, and the people of goals still to do (a
    -- "target" line counts for the accept/turn-in line just before it).
    -- Nothing for finished objectives or later steps. Nearest first, by
    -- the spot the guide gives for each (the /targetexact macro takes the
    -- nearest of each name itself).
    local cand = {}
    local px, py, inst = OXP.Places.Player()
    local function Dist(spotGoal)
        local s = spotGoal and OXP.Places.Spot(spotGoal)
        if not (s and px and s.instance == inst) then return math.huge end
        return OXP.Places.Distance(px, py, s.wx, s.wy)
    end
    local order = 0
    for _, step in ipairs(ActiveSteps()) do
        for _, m in ipairs(OXP.Goals.NeededMobs(step)) do
            order = order + 1
            cand[#cand + 1] = { name = m.name, enemy = true, d = Dist(m.spot), order = order }
        end
        for _, t in ipairs(OXP.Goals.TalkTargets(step)) do
            order = order + 1
            cand[#cand + 1] = { name = t.name, enemy = false, d = Dist(t.spot), order = order }
        end
    end
    -- spots within 40 yards of each other count as the same place (the
    -- guide's order decides there)
    table.sort(cand, function(a, b)
        local da, db = math.floor(a.d / 40), math.floor(b.d / 40)
        if da ~= db then return da < db end
        return a.order < b.order
    end)
    local out, seen = {}, {}
    for _, c in ipairs(cand) do
        if not seen[c.name] and #out < MAX_ROWS then
            seen[c.name] = true
            out[#out + 1] = { name = c.name, enemy = c.enemy }
        end
    end
    return out
end

--- The first of them (the bindable button's): name or nil.
function Buttons.WantedTarget()
    local list = Buttons.WantedTargets()
    return list[1] and list[1].name or nil
end

local pending = false

-- the first row's macro tries every name, the most wanted last (the last
-- /targetexact that finds someone wins)
local function AllMacro(list)
    local lines = { "/cleartarget" }
    for i = #list, 1, -1 do lines[#lines + 1] = "/targetexact " .. list[i].name end
    return table.concat(lines, "\n")
end

--- Draw the rows' look (portraits, colours, names): safe in combat.
function Buttons.PaintRows()
    local fontPath = OXP.Fonts and OXP.Fonts.Path()
    for i, r in ipairs(rows) do
        if r.unitName then
            local col = r.enemy and ENEMY or FRIEND
            r.bar:SetColorTexture(col[1], col[2], col[3], 1)
            local p = Portrait(r.unitName)
            if p then
                p:SetParent(r.slot)
                p:ClearAllPoints()
                p:SetAllPoints(r.slot)
                p:SetDrawLayer("ARTWORK", 1)
                p:Show()
                r.placeholder:Hide()
            else
                r.placeholder:SetTexture(MAPICON .. (r.enemy and "kill_32" or "talk_32"))
                r.placeholder:Show()
            end
            -- a portrait drawn for another row's old name: not ours
            for n, tex in pairs(portraits) do
                if n ~= r.unitName and tex:GetParent() == r.slot then tex:Hide() end
            end
            if fontPath then OXP.Fonts.Apply(r.text, fontPath, 12, "") end
            r.text:SetText(r.unitName)
            Style.TextColor(r.text, r.done and C.faint or C.text)
        end
    end
    local key = GetBindingKey and GetBindingKey("CLICK OpenXPTargetButton:LeftButton")
    box.key:SetText(key and (GetBindingText and GetBindingText(key, "KEY_") or key) or "")
end

-- In combat the item button can't change: it keeps its item (count,
-- cooldown and range still update) and greys out once it's no longer
-- wanted; the change itself waits for combat to end.
local function ItemInCombat()
    if not item.itemID then return end
    local s = OXP.settings
    local id = s.itemButton ~= false and Engine.GetGuide() and Buttons.WantedItem() or nil
    item.stale = id ~= item.itemID
    Buttons.PaintItem()
end

function Buttons.Refresh()
    if InCombat() then
        pending = true
        ItemInCombat()
        return
    end
    pending = false
    local s = OXP.settings
    local id, quest = nil, nil
    if s.itemButton ~= false and Engine.GetGuide() then id, quest = Buttons.WantedItem() end
    item.quest, item.stale = quest, nil
    if id ~= item.itemID then
        item.itemID = id
        item.outOfRange, item.rangeWait = false, 0
        if id then
            item:SetAttribute("type", "item")
            item:SetAttribute("item", "item:" .. id)
        else
            item:SetAttribute("type", nil)
            item:SetAttribute("item", nil)
        end
    end
    if id then
        Buttons.PaintItem()
        item:Show()
    else
        item:Hide()
    end

    local list = (s.targetButton ~= false and Engine.GetGuide()) and Buttons.WantedTargets() or {}
    Buttons.count = #list
    for i = 1, MAX_ROWS do
        local e = list[i]
        local r = e and Row(i) or rows[i]
        if r then
            local name = e and e.name or nil
            local macro = e and (i == 1 and AllMacro(list) or ("/cleartarget\n/targetexact " .. name)) or nil
            if macro ~= r.macro then
                r.macro = macro
                if macro then
                    r:SetAttribute("type", "macro")
                    r:SetAttribute("macrotext", macro)
                else
                    r:SetAttribute("type", nil)
                    r:SetAttribute("macrotext", nil)
                end
            end
            r.unitName, r.enemy, r.done = name, e and e.enemy, nil
            r:SetShown(e ~= nil)
        end
    end
    target.unitName = list[1] and list[1].name or nil
    box.title:SetText(#list > 0 and list[1].enemy and L("TARGETS") or L("TALK TO"))
    if OXP.Fonts then
        OXP.Fonts.Apply(box.title, OXP.Fonts.Path(), 10, "")
        OXP.Fonts.Apply(box.key, OXP.Fonts.Path(), 10, "")
    end
    box:SetHeight(20 + math.max(1, #list) * ROW_H)
    Buttons.PaintRows()
    box:SetShown(#list > 0)
end

-- In combat the list can't change, but a row whose mob is done greys out.
function Buttons.Dim()
    if not (InCombatLockdown and InCombatLockdown()) then return end
    local still = {}
    for _, e in ipairs((OXP.settings.targetButton ~= false and Engine.GetGuide()) and Buttons.WantedTargets() or {}) do
        still[e.name] = true
    end
    for _, r in ipairs(rows) do
        if r.unitName then r.done = not still[r.unitName] end
    end
    Buttons.PaintRows()
end

local function Saved(pos)
    return type(pos) == "table" and type(pos[1]) == "string" and type(pos[3]) == "number" and pos or nil
end

local placePending = false

function Buttons.Place()
    if InCombat() then
        placePending = true -- secure buttons only move outside combat
        return
    end
    placePending = false
    local card = OXP.Card and OXP.Card.frame
    item:ClearAllPoints()
    local pos = Saved(OXP.settings.itemButtonPos)
    if pos then
        item:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif card and card:GetLeft() and card:GetTop() then
        -- next to the card, but never anchored to it: a secure button anchored
        -- to a frame makes the game protect that frame, and the card could
        -- then no longer show or hide during combat
        local scale = card:GetEffectiveScale() / UIParent:GetEffectiveScale()
        item:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", card:GetLeft() * scale - 8, card:GetTop() * scale)
    else
        item:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
    box:ClearAllPoints()
    local tpos = Saved(OXP.settings.targetsPos)
    if tpos then
        box:SetPoint(tpos[1], UIParent, tpos[2], tpos[3], tpos[4])
    elseif card and card:GetLeft() and card:GetTop() then
        local scale = card:GetEffectiveScale() / UIParent:GetEffectiveScale()
        box:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", card:GetLeft() * scale - 8, card:GetTop() * scale - 52)
    else
        box:SetPoint("CENTER", UIParent, "CENTER", -200, -60)
    end
end

-- Shift-drag moves the item button; the targets list moves by its title
-- (any drag on it). Neither while frames are locked, nor in combat.
item:RegisterForDrag("LeftButton")
item:SetScript("OnDragStart", function(self)
    if OXP.settings.lockFrames or not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    self:StartMoving()
end)
item:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    OXP.settings.itemButtonPos = { point, rel, x, y }
end)
item:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self.itemID then GameTooltip:SetItemByID(self.itemID) end
    local quest = self.quest and OXP.QuestDB and OXP.QuestDB.QuestName(self.quest)
    if quest then GameTooltip:AddLine(L("For") .. ": " .. quest, C.gold[1], C.gold[2], C.gold[3]) end
    local key = GetBindingKey and GetBindingKey(ITEM_BINDING)
    if key then
        GameTooltip:AddLine(L("Key") .. ": " .. ((GetBindingText and GetBindingText(key)) or key), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(L("Bind a key: Key Bindings > AddOns > OpenXP"), 0.6, 0.6, 0.6)
    end
    if not OXP.settings.lockFrames then GameTooltip:AddLine(L("Shift-drag to move it."), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end)
item:SetScript("OnLeave", function() GameTooltip:Hide() end)

box:SetScript("OnDragStart", function(self)
    if OXP.settings.lockFrames and not (IsAltKeyDown and IsAltKeyDown()) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    self:StartMoving()
end)
box:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    OXP.settings.targetsPos = { point, rel, x, y }
end)

local function Soon() OXP.Soon("ACTION_BUTTONS", Buttons.Refresh) end
Buttons.Soon = Soon
for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "SETTINGS_CHANGED", "BAGS_CHANGED", "QUESTS_CHANGED" }) do
    OXP.Listen(m, Soon)
end
OXP.On("PLAYER_REGEN_ENABLED", function()
    if placePending then Buttons.Place() end
    if pending then Buttons.Refresh() end
end)
-- in combat: grey out what's done (the list itself waits for combat to end)
for _, m in ipairs({ "STEPS_UPDATED", "QUESTS_CHANGED" }) do
    OXP.Listen(m, function() if InCombatLockdown and InCombatLockdown() then Buttons.Dim() end end)
end
-- portraits: from your target, the unit under the mouse, nameplates
OXP.On("PLAYER_TARGET_CHANGED", function() Buttons.SeeUnit("target") end)
OXP.On("UPDATE_MOUSEOVER_UNIT", function() Buttons.SeeUnit("mouseover") end)
OXP.On("NAME_PLATE_UNIT_ADDED", function(_, unit) Buttons.SeeUnit(unit) end)
OXP.On("UPDATE_BINDINGS", function()
    Buttons.PaintRows()
    Buttons.PaintKey()
end)
-- the item button's look: cooldown, count (also in combat), range
OXP.On("BAG_UPDATE_COOLDOWN", UpdateCooldown)
OXP.On("BAG_UPDATE_DELAYED", function() Buttons.PaintItem() end)
OXP.On("PLAYER_TARGET_CHANGED", function()
    item.rangeWait = 0
    Buttons.UpdateRange()
end)
-- an item's name arrives: a "Use <item>" line found by name can match now
-- (before 2.0.2 the button only showed once something else refreshed it)
OXP.On("GET_ITEM_INFO_RECEIVED", function(_, id)
    if id and id == item.itemID then Buttons.PaintItem() end
    Soon()
end)

-- 1.x's key binds (its item and target buttons had other names): moved to
-- these buttons once, when they have no key of their own yet.
local OLD_BINDS = {
    ["CLICK RXPItemFrameButton1:LeftButton"] = ITEM_BINDING,
    ["CLICK OpenXPTargetMobs:LeftButton"] = "CLICK OpenXPTargetButton:LeftButton",
}
Buttons.OLD_BINDS = OLD_BINDS
function Buttons.CarryOldBindings()
    if not (GetBindingKey and SetBinding and SaveBindings) or InCombat() then return false end
    local db = OXP.db
    if not db or db.oldBindsMoved then return false end
    db.oldBindsMoved = true
    local moved = false
    for old, new in pairs(OLD_BINDS) do
        if not GetBindingKey(new) then
            local keys = { GetBindingKey(old) }
            for _, key in ipairs(keys) do
                if type(key) == "string" and SetBinding(key, new) then moved = true end
            end
        end
    end
    if moved then
        SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
        Buttons.PaintKey()
    end
    return moved
end
OXP.OnReady(function()
    Buttons.Place()
    Buttons.Refresh()
    pcall(Buttons.CarryOldBindings)
end)
