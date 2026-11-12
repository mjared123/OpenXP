-- OpenXP's look, shared by every window: colours, fonts and small widgets
-- (icon buttons, text buttons, status pills, step badges).
local ADDON, OXP = ...

local Style = {}
OXP.Style = Style

Style.TEX = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Card\\"
Style.LOGO = "Interface\\AddOns\\" .. ADDON .. "\\Media\\openxp_logo-64"
Style.LOGO_BIG = "Interface\\AddOns\\" .. ADDON .. "\\Media\\openxp_logo-128"
Style.WHITE = "Interface\\Buttons\\WHITE8X8"
local TEX, WHITE = Style.TEX, Style.WHITE

Style.C = {
    bg = { 16 / 255, 17 / 255, 21 / 255, 0.9 },
    bgSolid = { 16 / 255, 17 / 255, 21 / 255, 0.96 },
    panel = { 22 / 255, 24 / 255, 29 / 255, 0.9 },
    border = { 150 / 255, 160 / 255, 180 / 255, 0.35 },
    line = { 60 / 255, 66 / 255, 78 / 255 },
    text = { 0.92, 0.93, 0.95 },
    dim = { 0.62, 0.64, 0.70 },
    faint = { 0.54, 0.56, 0.61 },
    blue = { 90 / 255, 184 / 255, 1 },
    gold = { 242 / 255, 195 / 255, 92 / 255 },
    orange = { 1, 112 / 255, 67 / 255 },
    cyan = { 38 / 255, 198 / 255, 218 / 255 },
    purple = { 179 / 255, 157 / 255, 219 / 255 },
    green = { 61 / 255, 187 / 255, 122 / 255 },
}
local C = Style.C

function Style.Tint(tex, color, alpha)
    tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

--- A 1px-bordered dark backdrop.
function Style.Backdrop(f, bg, border)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(unpack(bg or C.bg))
    f:SetBackdropBorderColor(unpack(border or C.border))
end

function Style.FontSize(offset)
    return (OXP.settings and OXP.settings.fontSize or 12) + (offset or 0)
end

--- Set the chosen font at the card's size (+offset).
function Style.SetFont(fs, offset, flags)
    OXP.Fonts.Apply(fs, OXP.Fonts.Path(), Style.FontSize(offset), OXP.Fonts.Flags(flags))
end

-- text with a size of its own (button labels): remembered so a font change
-- reaches it without a /reload
local fixed = setmetatable({}, { __mode = "k" })
function Style.FixedFont(fs, size, flags)
    fixed[fs] = { size, flags }
    OXP.Fonts.Apply(fs, OXP.Fonts.Path(), size, OXP.Fonts.Flags(flags))
end
OXP.Listen("SETTINGS_CHANGED", function()
    for fs, spec in pairs(fixed) do
        OXP.Fonts.Apply(fs, OXP.Fonts.Path(), spec[1], OXP.Fonts.Flags(spec[2]))
    end
end)

local function Tooltip(self, title, body)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 1, 1, 1, true)
    if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end
Style.Tooltip = Tooltip

--- A flat icon button (Media/Card/<icon>), or a wider one with a label.
function Style.IconButton(parent, icon, tip, onClick, label)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(label and 116 or 40, 30)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetTexture(WHITE)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetTexture(TEX .. icon)
    btn.icon:SetSize(16, 16)
    local light = { 159 / 255, 212 / 255, 1 }
    if label then
        btn.bg:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0.16)
        btn.icon:SetPoint("LEFT", 10, 0)
        Style.Tint(btn.icon, light)
        btn.label = btn:CreateFontString(nil, "OVERLAY")
        Style.FixedFont(btn.label, 13, "")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.label:SetText(label)
        btn.label:SetTextColor(light[1], light[2], light[3])
    else
        btn.bg:SetVertexColor(1, 1, 1, 0)
        btn.icon:SetPoint("CENTER")
        Style.Tint(btn.icon, { 0.87, 0.88, 0.92 })
    end
    btn:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(1, 1, 1, 0.1)
        Tooltip(self, tip)
    end)
    btn:SetScript("OnLeave", function(self)
        if label then
            self.bg:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0.16)
        else
            self.bg:SetVertexColor(1, 1, 1, 0)
        end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

--- A small grey button with words on it.
function Style.TextButton(parent, text, tip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(22)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(1, 1, 1, 0.08)
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetPoint("CENTER")
    Style.FixedFont(btn.label, 12, "")
    btn.label:SetTextColor(unpack(C.text))
    function btn:SetLabel(t)
        self.label:SetText(t)
        self:SetWidth(math.max(70, (self.label:GetStringWidth() or 60) + 18))
    end
    btn:SetLabel(text)
    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.16)
        if tip then Tooltip(self, tip) end
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.08)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

--- A bigger bordered button for dialogs (primary: blue).
function Style.DialogButton(parent, text, primary, width)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 150, 28)
    Style.Backdrop(b, primary and { 28 / 255, 70 / 255, 104 / 255, 1 } or C.panel, primary and C.blue or C.line)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b.label:SetTextColor(unpack(primary and { 1, 1, 1 } or C.text))
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 1, 1, 0.8) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(primary and C.blue or C.line)) end)
    return b
end

Style.STATUS = {
    done = { text = "DONE", color = C.green, tip = "You finished this step." },
    skipped = { text = "SKIPPED", color = C.faint, tip = "You moved past this step without finishing it." },
    chain = { text = "CHAIN MISSED", color = C.gold,
              tip = "An earlier quest in this chain was skipped, so this one can't be picked up yet." },
}

--- A small status tag ("DONE", "SKIPPED", "CHAIN MISSED").
function Style.Pill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(14)
    pill.bg = pill:CreateTexture(nil, "BACKGROUND")
    pill.bg:SetPoint("TOPLEFT", 1, 0)
    pill.bg:SetPoint("BOTTOMRIGHT", -1, 0)
    pill.bg:SetTexture(WHITE)
    pill.l = pill:CreateTexture(nil, "BACKGROUND")
    pill.l:SetPoint("TOPLEFT", 0, -1)
    pill.l:SetPoint("BOTTOMLEFT", 0, 1)
    pill.l:SetWidth(1)
    pill.l:SetTexture(WHITE)
    pill.r = pill:CreateTexture(nil, "BACKGROUND")
    pill.r:SetPoint("TOPRIGHT", 0, -1)
    pill.r:SetPoint("BOTTOMRIGHT", 0, 1)
    pill.r:SetWidth(1)
    pill.r:SetTexture(WHITE)
    pill.text = pill:CreateFontString(nil, "OVERLAY")
    pill.text:SetPoint("CENTER", 0, 0)
    function pill:SetStatus(status)
        local st = status and Style.STATUS[status]
        if not st then self:Hide() return end
        Style.SetFont(self.text, -3)
        self.text:SetText(OXP.L(st.text))
        self.text:SetTextColor(st.color[1], st.color[2], st.color[3], 1)
        for _, t in ipairs({ self.bg, self.l, self.r }) do t:SetVertexColor(st.color[1], st.color[2], st.color[3], 0.16) end
        self:SetWidth((self.text:GetStringWidth() or 30) + 12)
        self:SetHeight(math.max(14, Style.FontSize(-3) + 5))
        self:Show()
    end
    pill:Hide()
    return pill
end

Style.BADGES = {
    accept = { glyph = "!", color = C.gold },
    turnin = { glyph = "?", color = C.gold },
    kill = { icon = "cross", color = C.orange },
    loot = { icon = "diamond", color = C.cyan },
    travel = { icon = "travel", color = C.blue },
    town = { icon = "house", color = C.purple },
}

--- A round step badge: "!" pick up, "?" turn in, or an icon.
function Style.Badge(parent, size)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    b.fill = b:CreateTexture(nil, "BACKGROUND")
    b.fill:SetTexture(TEX .. "disc")
    b.fill:SetAllPoints()
    b.ring = b:CreateTexture(nil, "BORDER")
    b.ring:SetTexture(TEX .. "ring")
    b.ring:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(size * 0.55, size * 0.55)
    b.glyph = b:CreateFontString(nil, "OVERLAY")
    b.glyph:SetPoint("CENTER", 0, 0)
    function b:SetKind(kind)
        local k = Style.BADGES[kind] or Style.BADGES.travel
        Style.Tint(self.fill, k.color, 0.16)
        Style.Tint(self.ring, k.color, 1)
        if k.glyph then
            self.icon:Hide()
            OXP.Fonts.Apply(self.glyph, OXP.Fonts.Path(), math.floor(size * 0.6), "")
            self.glyph:SetText(k.glyph)
            self.glyph:SetTextColor(unpack(k.color))
            self.glyph:Show()
        else
            self.glyph:Hide()
            self.icon:SetTexture(TEX .. k.icon)
            Style.Tint(self.icon, k.color)
            self.icon:Show()
        end
    end
    return b
end

--- A dark movable dialog window with a title, closed by Escape.
function Style.Window(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Style.Backdrop(f, C.bgSolid, C.blue)
    if name and _G.UISpecialFrames then tinsert(_G.UISpecialFrames, name) end
    f.logo = f:CreateTexture(nil, "OVERLAY")
    f.logo:SetTexture(Style.LOGO)
    f.logo:SetSize(28, 28)
    f.logo:SetPoint("TOPLEFT", 12, -10)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("LEFT", f.logo, "RIGHT", 8, 0)
    f.title:SetText(title or "OpenXP")
    f.title:SetTextColor(1, 1, 1)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -2, -2)
    f:Hide()
    return f
end
