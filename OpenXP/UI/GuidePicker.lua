-- The menu (card's menu button, right-click on the card, minimap right-click):
-- pick a guide, find your place, skipped chains, feedback, what's new.
local _, OXP = ...

local Picker = {}
OXP.GuidePicker = Picker

local Style, L = OXP.Style, OXP.L
local C = Style.C

local ROW_H, MAX_ROWS = 20, 22
local f, rows = nil, {}

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, f)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 6, -8 - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -6, -8 - (i - 1) * ROW_H)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetPoint("RIGHT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.extra = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.extra:SetPoint("RIGHT", -8, 0)
    row.extra:SetTextColor(unpack(C.faint))
    row:SetScript("OnEnter", function(self) if self.fn then self.hl:SetColorTexture(1, 1, 1, 0.08) end end)
    row:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, 0) end)
    row:SetScript("OnClick", function(self)
        if self.fn then
            local keep = self.fn()
            if not keep then f:Hide() end
        end
    end)
    rows[i] = row
    return row
end

local function Build()
    f = CreateFrame("Frame", "OpenXPMenu", UIParent, "BackdropTemplate")
    Style.Backdrop(f, C.bgSolid, C.border)
    f:SetFrameStrata("DIALOG")
    f:SetWidth(280)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    tinsert(_G.UISpecialFrames, "OpenXPMenu")
    f:Hide()
end

-- entries: { text, fn, extra, header }
local function Fill(entries)
    for i = 1, math.max(#entries, #rows) do
        local e = entries[i]
        local row = e and Row(i) or rows[i]
        if e then
            Style.SetFont(row.text, e.header and -2 or 0)
            row.text:SetText(e.text)
            row.text:SetTextColor(unpack(e.header and C.dim or (e.current and C.blue or C.text)))
            Style.SetFont(row.extra, -2)
            row.extra:SetText(e.extra or "")
            row.fn = e.fn
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    f:SetHeight(16 + #entries * ROW_H)
end

local view = "main"

local function GuideEntries(group)
    local entries = { { text = group.name:upper(), header = true } }
    local current = OXP.Engine.GetGuide()
    for _, g in ipairs(group.guides) do
        local done, total = OXP.Engine.GetProgress(g)
        entries[#entries + 1] = {
            text = g.name, current = g == current,
            extra = total > 0 and done > 0 and ("%d%%"):format(math.floor(done / total * 100)) or nil,
            fn = function() OXP.Engine.Load(g) end,
        }
        if #entries >= MAX_ROWS - 1 then break end
    end
    entries[#entries + 1] = { text = "< " .. L("Back"), fn = function() view = "main"; Picker.Show(); return true end }
    return entries
end

local function MainEntries()
    local entries = {
        { text = L("OPENXP"), header = true },
        { text = L("Find my place"), fn = function() OXP.SmartStart.Run(false) end },
        { text = L("Skipped quest chains"), fn = function() OXP.SmartStart.ShowCatchUp() end },
    }
    for _, group in ipairs(OXP.Registry.Groups()) do
        entries[#entries + 1] = { text = group.name, extra = #group.guides .. " >", fn = function()
            view = group
            Picker.Show()
            return true
        end }
    end
    entries[#entries + 1] = { text = L("Settings"), fn = function() OXP.Settings.Toggle() end }
    entries[#entries + 1] = { text = L("Feedback and bugs"), fn = function() OXP.Feedback.Show() end }
    entries[#entries + 1] = { text = L("What's new"), fn = function() OXP.Welcome.Show("update") end }
    return entries
end

function Picker.Show(anchor)
    if not f then Build() end
    if anchor then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
    elseif not f:GetPoint() then
        f:SetPoint("CENTER")
    end
    Fill(view == "main" and MainEntries() or GuideEntries(view))
    f:Show()
end

function Picker.Toggle(anchor)
    if f and f:IsShown() then
        f:Hide()
        return
    end
    view = "main"
    Picker.Show(anchor)
end

OXP.AddCommand("menu", "open the OpenXP menu (pick a guide and more)", function() Picker.Toggle() end)
