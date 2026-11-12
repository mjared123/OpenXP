-- Two buttons beside the guide card, both keybindable (Key Bindings >
-- AddOns > OpenXP):
--   item button    uses the quest item the shown steps need (a step's
--                  "item" goal you carry, or the item a quest in the step
--                  gives you to use)
--   target button  targets the NPC or mob the shown steps name
-- They are secure buttons, so the game only lets them change outside
-- combat; a change asked for in combat waits until combat ends.
local _, OXP = ...

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

local function Make(name, size)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
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
local target = Make("OpenXPTargetButton", 30)
Buttons.item, Buttons.target = item, target
target.icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")

local function Tip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self == item and self.itemID then
        GameTooltip:SetItemByID(self.itemID)
    elseif self == target and self.unitName then
        GameTooltip:SetText(L("Target") .. " " .. self.unitName, 1, 1, 1)
    end
    GameTooltip:AddLine(L("Bind a key: Key Bindings > AddOns > OpenXP"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
for _, b in ipairs({ item, target }) do
    b:SetScript("OnEnter", Tip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- What the buttons should do now
------------------------------------------------------------------------

local function ActiveSteps()
    local out = {}
    for _, pos in ipairs(Engine.GetActive()) do out[#out + 1] = Engine.GetSteps()[pos] end
    return out
end

--- The item to put on the item button: id or nil.
function Buttons.WantedItem()
    for _, step in ipairs(ActiveSteps()) do
        for _, g in ipairs(step.goals) do
            if g[1] == "item" and g.item and (GetItemCount(g.item) or 0) > 0 then return g.item end
        end
    end
    -- a quest in the step that hands you an item to use
    if GetQuestLogSpecialItemInfo and GetNumQuestLogEntries then
        local quests = {}
        for _, step in ipairs(ActiveSteps()) do
            for _, g in ipairs(step.goals) do
                if g.quest and OXP.Goals.State(g, step.marks) == "todo" then quests[g.quest] = true end
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

--- The NPC or mob to put on the target button: name or nil. A step's
--- mobs while it still has things to kill, otherwise who to talk to.
function Buttons.WantedTarget()
    for _, step in ipairs(ActiveSteps()) do
        local killing, mob, talk = false, nil, nil
        for _, g in ipairs(step.goals) do
            local state = OXP.Goals.State(g, step.marks)
            if g[1] == "complete" and state == "todo" then killing = true end
            if g[1] == "mob" and not mob then mob = g.name end
            if g[1] == "target" and not talk then talk = g.name end
        end
        if killing and mob then return mob end
        if talk then return talk end
        if mob then return mob end
    end
end

local pending = false

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
    local name = s.targetButton ~= false and Engine.GetGuide() and Buttons.WantedTarget() or nil
    if name ~= target.unitName then
        target.unitName = name
        if name then
            target:SetAttribute("type", "macro")
            target:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. name)
        else
            target:SetAttribute("type", nil)
        end
    end
    target.label:SetText(name or "")
    target:SetShown(name ~= nil)
end

local function UpdateCooldown()
    if item.itemID and GetItemCooldown then
        local start, duration = GetItemCooldown(item.itemID)
        if start and duration and duration > 0 then item.cooldown:SetCooldown(start, duration) end
    end
end

function Buttons.Place()
    if InCombatLockdown and InCombatLockdown() then return end
    local card = OXP.Card and OXP.Card.frame
    item:ClearAllPoints()
    target:ClearAllPoints()
    local pos = OXP.settings.itemButtonPos
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
    target:SetPoint("TOP", item, "BOTTOM", 0, -18)
end

-- Shift-drag moves the pair (unless frames are locked)
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
    target:ClearAllPoints()
    target:SetPoint("TOP", self, "BOTTOM", 0, -18)
end)

local function Soon() OXP.Soon("ACTION_BUTTONS", Buttons.Refresh) end
for _, m in ipairs({ "GUIDE_LOADED", "STEP_CHANGED", "STEPS_UPDATED", "SETTINGS_CHANGED", "BAGS_CHANGED", "QUESTS_CHANGED" }) do
    OXP.Listen(m, Soon)
end
OXP.On("PLAYER_REGEN_ENABLED", function() if pending then Buttons.Refresh() end end)
OXP.On("BAG_UPDATE_COOLDOWN", UpdateCooldown)
OXP.OnReady(function()
    Buttons.Place()
    Buttons.Refresh()
end)
