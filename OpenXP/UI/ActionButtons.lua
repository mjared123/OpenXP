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

local GetItemCount = C_Item and C_Item.GetItemCount or _G.GetItemCount
local GetItemIcon = C_Item and C_Item.GetItemIconByID or _G.GetItemIcon
local function GetItemCooldown(id)
    local fn = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
    if fn then return fn(id) end
end

local function Make(name, size, parent)
    local b = CreateFrame("Button", name, parent or UIParent, "SecureActionButtonTemplate")
    b:SetSize(size, size)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 0.6)
    b.border:SetDrawLayer("BACKGROUND")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()
    b:Hide()
    return b
end

local item = Make("OpenXPItemButton", 36)
Buttons.item = item

--- The skin's accent on the button edges (Settings > Guide card > Skin).
function Buttons.ApplySkin()
    item.border:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 0.6)
end

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
    local name = UnitName(unit)
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
-- What the buttons should do now------------------------------------------------------------------------
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

--- The item to put on the item button: id or nil.
function Buttons.WantedItem()
    for _, step in ipairs(WalkQuest() and {} or ActiveSteps()) do
        for _, g in ipairs(step.goals) do
            if g[1] == "item" and g.item and (GetItemCount(g.item) or 0) > 0 then return g.item end
        end
    end
    -- a quest in the step that hands you an item to use
    if GetQuestLogSpecialItemInfo and GetNumQuestLogEntries then
        local quests = {}
        local walk = WalkQuest()
        if walk then
            quests[walk] = true
        else
            for _, step in ipairs(ActiveSteps()) do
                for _, g in ipairs(step.goals) do
                    if g.quest and OXP.Goals.State(g, step.marks) == "todo" then quests[g.quest] = true end
                end
            end
        end
        for i = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if not isHeader and quests[questID] then
                local link = GetQuestLogSpecialItemInfo(i)
                local id = link and tonumber(link:match("item:(%d+)"))
                if id then return id end
            end
        end
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

function Buttons.Refresh()
    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local s = OXP.settings
    local id = s.itemButton ~= false and Engine.GetGuide() and Buttons.WantedItem() or nil
    if id ~= item.itemID then
        item.itemID = id
        if id then
            item:SetAttribute("type", "item")
            item:SetAttribute("item", "item:" .. id)
        else
            item:SetAttribute("type", nil)
        end
    end
    if id then
        item.icon:SetTexture(GetItemIcon and GetItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local n = GetItemCount(id) or 0
        item.count:SetText(n > 1 and n or "")
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

local function UpdateCooldown()
    if item.itemID and GetItemCooldown then
        local start, duration = GetItemCooldown(item.itemID)
        if start and duration and duration > 0 then item.cooldown:SetCooldown(start, duration) end
    end
end

local function Saved(pos)
    return type(pos) == "table" and type(pos[1]) == "string" and type(pos[3]) == "number" and pos or nil
end

function Buttons.Place()
    if InCombatLockdown and InCombatLockdown() then return end
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
    GameTooltip:AddLine(L("Bind a key: Key Bindings > AddOns > OpenXP"), 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L("Shift-drag to move it."), 0.6, 0.6, 0.6)
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
OXP.On("PLAYER_REGEN_ENABLED", function() if pending then Buttons.Refresh() end end)
-- in combat: grey out what's done (the list itself waits for combat to end)
for _, m in ipairs({ "STEPS_UPDATED", "QUESTS_CHANGED" }) do
    OXP.Listen(m, function() if InCombatLockdown and InCombatLockdown() then Buttons.Dim() end end)
end
-- portraits: from your target, the unit under the mouse, nameplates
OXP.On("PLAYER_TARGET_CHANGED", function() Buttons.SeeUnit("target") end)
OXP.On("UPDATE_MOUSEOVER_UNIT", function() Buttons.SeeUnit("mouseover") end)
OXP.On("NAME_PLATE_UNIT_ADDED", function(_, unit) Buttons.SeeUnit(unit) end)
OXP.On("UPDATE_BINDINGS", function() Buttons.PaintRows() end)
OXP.On("BAG_UPDATE_COOLDOWN", UpdateCooldown)
OXP.OnReady(function()
    Buttons.Place()
    Buttons.Refresh()
end)
