-- OpenXP's look, shared by every window: colours, spacing, fonts, short
-- fades, and the widgets the windows are built from (windows, buttons,
-- toggles, sliders, dropdowns, search boxes, scrolling lists, status pills,
-- step badges). Dark and quiet: one accent colour, 1 px lines, hover and
-- pressed states on everything you can click.
local ADDON, OXP = ...

local Style = {}
OXP.Style = Style

Style.TEX = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Card\\"
Style.LOGO = "Interface\\AddOns\\" .. ADDON .. "\\Media\\openxp_logo-64"
Style.LOGO_BIG = "Interface\\AddOns\\" .. ADDON .. "\\Media\\openxp_logo-128"
Style.WHITE = "Interface\\Buttons\\WHITE8X8"
local TEX, WHITE = Style.TEX, Style.WHITE

Style.C = {
    bg = { 13 / 255, 15 / 255, 20 / 255, 0.92 },
    bgSolid = { 15 / 255, 17 / 255, 22 / 255, 0.98 },
    panel = { 21 / 255, 24 / 255, 31 / 255, 1 },
    raised = { 29 / 255, 33 / 255, 42 / 255, 1 },
    raisedHover = { 40 / 255, 45 / 255, 56 / 255, 1 },
    hover = { 1, 1, 1, 0.06 },
    border = { 1, 1, 1, 0.10 },
    borderStrong = { 1, 1, 1, 0.18 },
    line = { 1, 1, 1, 0.07 },
    text = { 0.93, 0.94, 0.96 },
    dim = { 0.63, 0.66, 0.72 },
    faint = { 0.47, 0.50, 0.56 },
    blue = { 90 / 255, 184 / 255, 1 },
    accentDark = { 32 / 255, 78 / 255, 120 / 255 },
    accentHover = { 42 / 255, 98 / 255, 148 / 255, 1 },
    gold = { 242 / 255, 195 / 255, 92 / 255 },
    orange = { 1, 112 / 255, 67 / 255 },
    red = { 235 / 255, 87 / 255, 87 / 255 },
    cyan = { 38 / 255, 198 / 255, 218 / 255 },
    purple = { 179 / 255, 157 / 255, 219 / 255 },
    green = { 61 / 255, 187 / 255, 122 / 255 },
}
local C = Style.C

-- Skins: the look of the card and every OpenXP window. Each one changes the
-- colours above in place (so everything built from them follows, see
-- Style.Paint) plus how strong the card's header band, lines and borders
-- are. Pick one under Settings > Guide card.
--   header   alpha of the white wash behind the card's title rows
--   line     alpha of the card's thin separator lines
--   frameless (Minimal) no background, border, bands or lines on the card:
--            just its text, icons and buttons, with outlined text
local function rgb(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end
local DEFAULT = {}
for k, v in pairs(C) do DEFAULT[k] = { v[1], v[2], v[3], v[4] } end
Style.SKIN_ORDER = { "midnight", "glass", "minimal", "classic", "ember", "forest" }
Style.SKINS = {
    midnight = { name = "Midnight", header = 0.035, line = 0.07 },
    minimal = { name = "Minimal (no background)", header = 0, line = 0, frameless = true, outline = true,
                bg = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 } },
    glass = { name = "Glass", header = 0.05, line = 0.09,
              bg = rgb(16, 24, 36, 0.66), bgSolid = rgb(18, 26, 38, 0.97), border = rgb(170, 210, 255, 0.20),
              borderStrong = rgb(170, 210, 255, 0.30), panel = rgb(25, 35, 50), raised = rgb(34, 47, 66),
              raisedHover = rgb(44, 60, 82), blue = rgb(120, 204, 255), accentDark = rgb(36, 86, 128),
              accentHover = rgb(48, 108, 158) },
    classic = { name = "Classic gold", header = 0.045, line = 0.09,
                bg = rgb(22, 17, 11, 0.95), bgSolid = rgb(24, 19, 12, 0.98), border = rgb(196, 160, 86, 0.55),
                borderStrong = rgb(214, 178, 100, 0.70), panel = rgb(34, 27, 17), raised = rgb(48, 38, 24),
                raisedHover = rgb(62, 50, 31),
                text = rgb(245, 236, 214), dim = rgb(196, 178, 142), faint = rgb(150, 134, 104),
                blue = rgb(242, 195, 92), accentDark = rgb(120, 88, 30), accentHover = rgb(146, 108, 38) },
    ember = { name = "Ember", header = 0.04, line = 0.08,
              bg = rgb(22, 13, 12, 0.94), bgSolid = rgb(24, 14, 13, 0.98), border = rgb(255, 112, 67, 0.28),
              borderStrong = rgb(255, 128, 86, 0.42), panel = rgb(36, 21, 18), raised = rgb(50, 29, 25),
              raisedHover = rgb(64, 38, 32), dim = rgb(186, 160, 152), faint = rgb(140, 116, 108),
              blue = rgb(255, 128, 76), accentDark = rgb(120, 46, 24), accentHover = rgb(148, 58, 30) },
    forest = { name = "Forest", header = 0.04, line = 0.08,
               bg = rgb(12, 20, 15, 0.94), bgSolid = rgb(13, 22, 16, 0.98), border = rgb(61, 187, 122, 0.28),
               borderStrong = rgb(84, 204, 140, 0.42), panel = rgb(19, 31, 23), raised = rgb(27, 42, 32),
               raisedHover = rgb(36, 54, 42), dim = rgb(154, 180, 162), faint = rgb(110, 134, 118),
               blue = rgb(84, 204, 140), accentDark = rgb(28, 92, 58), accentHover = rgb(36, 116, 74) },
}
local SKINNED = { "bg", "bgSolid", "panel", "raised", "raisedHover", "border", "borderStrong",
                  "text", "dim", "faint", "blue", "accentDark", "accentHover" }

--- The skin in use (its table); `Style.skin` after Style.ApplySkin.
Style.skin = Style.SKINS.midnight
Style.skinKey = "midnight"

--- Switches the colours to skin `key` (unknown keys: Midnight). The colour
--- tables change in place and everything painted with Style.Paint,
--- Style.Fill, Style.Tint, Style.TextColor or Style.Backdrop is repainted.
function Style.ApplySkin(key)
    if not Style.SKINS[key] then key = "midnight" end
    local skin = Style.SKINS[key]
    Style.skin, Style.skinKey = skin, key
    for _, k in ipairs(SKINNED) do
        local from = skin[k] or DEFAULT[k]
        if skin.frameless and (k == "bgSolid" or k == "panel" or k == "raised" or k == "raisedHover"
            or k == "borderStrong") then
            from = DEFAULT[k] -- windows (Settings, Pick a guide) keep a background
        end
        local to = C[k]
        to[1], to[2], to[3], to[4] = from[1], from[2], from[3], from[4]
    end
    if Style.Repaint then Style.Repaint() end
    return skin
end

-- first in line on a settings change, so every window repaints in the new one
OXP.Listen("SETTINGS_CHANGED", function()
    local s = OXP.settings
    local key = s and s.skin or "midnight"
    local alpha = s and s.cardOpacity or 1
    if Style.skinKey ~= key then
        Style.ApplySkin(key)
    elseif Style.paintedAlpha ~= alpha and Style.Repaint then
        Style.Repaint()
    end
end)

function Style.SkinChoices()
    local list = {}
    local L = OXP.L or function(t) return t end
    for _, k in ipairs(Style.SKIN_ORDER) do list[#list + 1] = { k, L(Style.SKINS[k].name) } end
    return list
end

--- How see-through the card's background is (Settings > Guide card >
--- Background): 0 (none) to 1 (the skin's own).
function Style.CardOpacity()
    local v = OXP.settings and OXP.settings.cardOpacity
    if type(v) ~= "number" then return 1 end
    return math.max(0, math.min(1, v))
end

--- True when the card draws no background, border or lines (Minimal skin,
--- or the background slider at 0).
function Style.Frameless()
    return Style.skin.frameless or Style.CardOpacity() <= 0.001
end

-- spacing: every window uses these, so margins line up everywhere
Style.S = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, header = 48, footer = 52, row = 52 }
local S = Style.S

-- Everything painted from one of the colour tables above is remembered
-- (weakly) with the table it was painted from, so a skin change can paint
-- it again: the tables change in place, the textures don't.
local tinted = setmetatable({}, { __mode = "k" })
local filled = setmetatable({}, { __mode = "k" })
local texts = setmetatable({}, { __mode = "k" })
local backdrops = setmetatable({}, { __mode = "k" })

--- Vertex colour from a colour table (alpha: its own, or the table's).
function Style.Tint(tex, color, alpha)
    tinted[tex] = { color, alpha }
    tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

--- A solid colour from a colour table.
local function Fill(tex, color, alpha)
    filled[tex] = { color, alpha }
    tex:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end
Style.Fill = Fill

--- Text colour from a colour table (follows skin changes).
function Style.TextColor(fs, color, alpha)
    texts[fs] = { color, alpha }
    fs:SetTextColor(color[1], color[2], color[3], alpha or 1)
end

--- A 1px-bordered backdrop. opts.card: the background follows the card's
--- Background slider (and vanishes in Minimal).
function Style.Backdrop(f, bg, border, opts)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    bg, border = bg or C.bg, border or C.border
    backdrops[f] = { bg, border, opts and opts.card }
    Style.PaintBackdrop(f)
end

function Style.PaintBackdrop(f)
    local spec = backdrops[f]
    if not spec then return end
    local bg, border = spec[1], spec[2]
    local a = bg[4] or 1
    local ba = border[4] or 1
    if spec[3] then
        a = a * Style.CardOpacity()
        -- the border fades out with the background, so 0% really is nothing
        ba = ba * math.min(1, Style.CardOpacity() * 1.5)
    end
    f:SetBackdropColor(bg[1], bg[2], bg[3], a)
    f:SetBackdropBorderColor(border[1], border[2], border[3], ba)
end

local repaintHooks = {}
--- fn() runs after every skin or background change (windows with pieces
--- painted some other way).
function Style.OnRepaint(fn) repaintHooks[#repaintHooks + 1] = fn end

--- Repaints everything in the current skin's colours.
function Style.Repaint()
    Style.paintedAlpha = OXP.settings and OXP.settings.cardOpacity or 1
    for f in pairs(backdrops) do Style.PaintBackdrop(f) end
    for tex, spec in pairs(tinted) do
        local c = spec[1]
        tex:SetVertexColor(c[1], c[2], c[3], spec[2] or c[4] or 1)
    end
    for tex, spec in pairs(filled) do
        local c = spec[1]
        tex:SetColorTexture(c[1], c[2], c[3], spec[2] or c[4] or 1)
    end
    for fs, spec in pairs(texts) do
        local c = spec[1]
        fs:SetTextColor(c[1], c[2], c[3], spec[2] or 1)
    end
    for _, fn in ipairs(repaintHooks) do pcall(fn) end
end
Style.RepaintBackdrops = Style.Repaint

function Style.FontSize(offset)
    return (OXP.settings and OXP.settings.fontSize or 12) + (offset or 0)
end

--- Set the chosen font at the card's size (+offset).
--- Set the chosen font at the card's size (+offset). Card text: in the
--- Minimal skin (or with no background) it gets an outline so it reads on
--- any ground, and always a soft shadow.
function Style.SetFont(fs, offset, flags)
    flags = OXP.Fonts.Flags(flags)
    local bare = Style.Frameless()
    if bare and flags == "" then flags = "OUTLINE" end
    OXP.Fonts.Apply(fs, OXP.Fonts.Path(), Style.FontSize(offset), flags)
    if fs.SetShadowOffset then
        fs:SetShadowColor(0, 0, 0, bare and 1 or 0.55)
        fs:SetShadowOffset(1, -1)
    end
end

-- text with a size of its own (window text, button labels): remembered so
-- a font change reaches it without a /reload
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

--- A font string in the chosen font at a fixed size and colour.
function Style.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlight")
    Style.FixedFont(fs, size or 12, "")
    Style.TextColor(fs, color or C.text)
    fs:SetJustifyH("LEFT")
    return fs
end

--- A 1 px line across a frame (horizontal unless `vertical`).
function Style.Divider(parent, vertical, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    Fill(t, color or C.line)
    if vertical then t:SetWidth(1) else t:SetHeight(1) end
    return t
end

local function Tooltip(self, title, body)
    if not title then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 1, 1, 1, true)
    if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end
Style.Tooltip = Tooltip

---------------------------------------------------------------------------
-- Motion: short fades and value glides, driven by one OnUpdate
---------------------------------------------------------------------------

local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, dt)
    local any = false
    for key, tw in pairs(tweens) do
        tw.t = math.min(tw.duration, tw.t + (dt or 0))
        local p = tw.duration > 0 and tw.t / tw.duration or 1
        p = 1 - (1 - p) ^ 3
        tw.apply(tw.from + (tw.to - tw.from) * p)
        if tw.t >= tw.duration then
            tweens[key] = nil
            if tw.done then tw.done() end
        else
            any = true
        end
    end
    if not any and next(tweens) == nil then self:Hide() end
end)
Style.driver = driver

--- Glide a value from `from` to `to` over `duration` seconds (ease-out),
--- calling apply(value) each frame. A new tween with the same key replaces
--- the running one.
function Style.Tween(key, from, to, duration, apply, done)
    if (duration or 0) <= 0 or (OXP.settings and OXP.settings.cardAnimations == false) then
        tweens[key] = nil
        apply(to)
        if done then done() end
        return
    end
    tweens[key] = { from = from, to = to, duration = duration, t = 0, apply = apply, done = done }
    apply(from)
    driver:Show()
end

--- Fade a frame in (shown) or out (then hidden).
function Style.Fade(frame, show, duration)
    local from = frame:GetAlpha() or 1
    if show then
        if not frame:IsShown() then from = 0 end
        frame:Show()
        Style.Tween(frame, from, 1, duration or 0.15, function(a) frame:SetAlpha(a) end)
    else
        Style.Tween(frame, from, 0, duration or 0.12, function(a) frame:SetAlpha(a) end, function()
            frame:Hide()
            frame:SetAlpha(1)
        end)
    end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

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
    local function Idle(b)
        if label then Style.Tint(b.bg, C.blue, 0.16) else b.bg:SetVertexColor(1, 1, 1, 0) end
    end
    Idle(btn)
    if label then
        btn.icon:SetPoint("LEFT", 10, 0)
        Style.Tint(btn.icon, C.blue)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        Style.FixedFont(btn.label, 13, "")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.label:SetText(label)
        Style.TextColor(btn.label, C.text)
    else
        btn.icon:SetPoint("CENTER")
        Style.Tint(btn.icon, { 0.80, 0.82, 0.88 })
    end
    btn:SetScript("OnEnter", function(self)
        if label then Style.Tint(self.bg, C.blue, 0.30) else self.bg:SetVertexColor(1, 1, 1, 0.08) end
        if not label then Style.Tint(self.icon, { 1, 1, 1 }) end
        Tooltip(self, tip)
    end)
    btn:SetScript("OnLeave", function(self)
        Idle(self)
        if not label then Style.Tint(self.icon, { 0.80, 0.82, 0.88 }) end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnMouseDown", function(self) self.icon:SetAlpha(0.7) end)
    btn:SetScript("OnMouseUp", function(self) self.icon:SetAlpha(1) end)
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
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.label:SetPoint("CENTER")
    Style.FixedFont(btn.label, 12, "")
    Style.TextColor(btn.label, C.text)
    function btn:SetLabel(t)
        self.label:SetText(t)
        self:SetWidth(math.max(70, (self.label:GetStringWidth() or 60) + 18))
    end
    btn:SetLabel(text)
    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.15)
        if tip then Tooltip(self, tip) end
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.08)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnMouseDown", function(self) self.bg:SetColorTexture(1, 1, 1, 0.04) end)
    btn:SetScript("OnMouseUp", function(self) self.bg:SetColorTexture(1, 1, 1, self:IsMouseOver() and 0.15 or 0.08) end)
    btn:SetScript("OnClick", onClick)
    return btn
end

local BUTTON_KINDS = {
    primary = { bg = C.accentDark, border = C.blue, hover = C.accentHover, text = { 1, 1, 1 } },
    secondary = { bg = C.raised, border = C.borderStrong, hover = C.raisedHover, text = C.text },
    ghost = { bg = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, hover = { 1, 1, 1, 0.06 }, text = C.dim },
    danger = { bg = { 70 / 255, 26 / 255, 26 / 255, 1 }, border = C.red, hover = { 96 / 255, 34 / 255, 34 / 255, 1 }, text = { 1, 0.9, 0.9 } },
}

--- A dialog button. kind: "primary" (accent), "secondary", "ghost" or
--- "danger". btn:SetEnabled(false) greys it out.
function Style.Button(parent, text, kind, width, onClick, tip)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local k = BUTTON_KINDS[kind or "secondary"] or BUTTON_KINDS.secondary
    b.kind = k
    b:SetSize(width or 140, 30)
    Style.Backdrop(b, k.bg, k.border)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style.FixedFont(b.label, 13, "")
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    Style.TextColor(b.label, k.text)
    b.enabled = true
    function b:SetLabel(t) self.label:SetText(t) end
    function b:SetEnabled(on)
        self.enabled = on and true or false
        self:SetAlpha(self.enabled and 1 or 0.45)
        if self.EnableMouse then self:EnableMouse(self.enabled) end
    end
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(k.hover))
        if kind == "ghost" then Style.TextColor(self.label, C.text) end
        Tooltip(self, tip and text, tip)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(k.bg))
        Style.TextColor(self.label, k.text)
        GameTooltip:Hide()
    end)
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    if onClick then
        b:SetScript("OnClick", function(self, ...) if self.enabled then onClick(self, ...) end end)
    end
    return b
end

--- A bigger bordered button for dialogs (primary: accent).
function Style.DialogButton(parent, text, primary, width)
    return Style.Button(parent, text, primary and "primary" or "secondary", width or 150)
end

---------------------------------------------------------------------------
-- Controls: toggle, slider, dropdown, search box
---------------------------------------------------------------------------

--- An on/off switch. get() -> bool, set(bool).
function Style.Toggle(parent, get, set)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(36, 20)
    t.track = t:CreateTexture(nil, "BACKGROUND")
    t.track:SetTexture(TEX .. "filledcircle") -- ends
    t.track:SetAllPoints()
    t.track:SetAlpha(0)
    t.bar = t:CreateTexture(nil, "BORDER")
    t.bar:SetPoint("TOPLEFT", 0, -3)
    t.bar:SetPoint("BOTTOMRIGHT", 0, 3)
    t.bar:SetTexture(WHITE)
    t.knob = t:CreateTexture(nil, "ARTWORK")
    t.knob:SetTexture(TEX .. "filledcircle")
    t.knob:SetSize(16, 16)
    local function Paint(on, animate)
        local x0, x1 = on and 2 or 18, on and 18 or 2
        Style.Tint(t.bar, on and C.blue or C.raised, on and 0.85 or 1)
        Style.Tint(t.knob, on and { 1, 1, 1 } or C.dim)
        if animate then
            Style.Tween(t, x0, x1, 0.12, function(x) t.knob:ClearAllPoints() t.knob:SetPoint("LEFT", x, 0) end)
        else
            t.knob:ClearAllPoints()
            t.knob:SetPoint("LEFT", x1, 0)
        end
    end
    function t:Update() Paint(get() and true or false, false) end
    t:SetScript("OnClick", function()
        local on = not get()
        set(on)
        Paint(on, true)
    end)
    t:SetScript("OnEnter", function(self) self.knob:SetAlpha(0.85) end)
    t:SetScript("OnLeave", function(self) self.knob:SetAlpha(1) end)
    t:Update()
    return t
end

--- A horizontal slider. opts: min, max, step, get() -> number, set(n),
--- format(n) -> text. Drag the thumb, click the track or use the wheel.
function Style.Slider(parent, width, opts)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width, 20)
    s:EnableMouse(true)
    s:EnableMouseWheel(true)
    s.value = Style.Text(s, 12, C.blue)
    s.value:SetPoint("RIGHT", 0, 0)
    s.value:SetJustifyH("RIGHT")
    s.value:SetWidth(46)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetHeight(4)
    s.track:SetPoint("LEFT", 0, 0)
    s.track:SetPoint("RIGHT", s.value, "LEFT", -10, 0)
    Fill(s.track, C.raised)
    s.fill = s:CreateTexture(nil, "BORDER")
    s.fill:SetHeight(4)
    s.fill:SetPoint("LEFT", s.track, "LEFT")
    Fill(s.fill, C.blue, 0.9)
    s.thumb = s:CreateTexture(nil, "ARTWORK")
    s.thumb:SetTexture(TEX .. "filledcircle")
    s.thumb:SetSize(14, 14)
    local lo, hi, step = opts.min, opts.max, opts.step or 1
    local function Snap(v)
        v = math.max(lo, math.min(hi, v))
        return math.floor((v - lo) / step + 0.5) * step + lo
    end
    local function TrackWidth() return math.max(1, (s.track:GetWidth() or (width - 56))) end
    function s:Update()
        local v = opts.get() or lo
        local frac = (hi > lo) and (v - lo) / (hi - lo) or 0
        local w = TrackWidth()
        self.fill:SetWidth(math.max(1, w * frac))
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("CENTER", self.track, "LEFT", w * frac, 0)
        self.value:SetText(opts.format and opts.format(v) or tostring(v))
    end
    function s:SetValue(v)
        v = Snap(v)
        if v ~= opts.get() then opts.set(v) end
        self:Update()
    end
    local function FromCursor()
        local x = GetCursorPosition()
        local scale = s:GetEffectiveScale() or 1
        local left = s.track:GetLeft() or 0
        s:SetValue(lo + (x / scale - left) / TrackWidth() * (hi - lo))
    end
    s:SetScript("OnMouseDown", function(self)
        self.dragging = true
        FromCursor()
        -- only while dragging; let go anywhere and it stops
        self:SetScript("OnUpdate", function(me)
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                me.dragging = false
                me:SetScript("OnUpdate", nil)
                return
            end
            FromCursor()
        end)
    end)
    s:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)
    s:SetScript("OnMouseWheel", function(self, delta) self:SetValue((opts.get() or lo) + delta * step) end)
    s:SetScript("OnEnter", function(self) Style.Tint(self.thumb, C.blue) end)
    s:SetScript("OnLeave", function(self) Style.Tint(self.thumb, { 1, 1, 1 }) end)
    s:Update()
    return s
end

-- one shared popup for every dropdown
local popup
local function Popup()
    if popup then return popup end
    popup = CreateFrame("Frame", "OpenXPDropdownList", UIParent, "BackdropTemplate")
    Style.Backdrop(popup, C.bgSolid, C.borderStrong)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:EnableMouse(true)
    popup:SetClampedToScreen(true)
    popup.rows = {}
    popup:Hide()
    if _G.UISpecialFrames then tinsert(_G.UISpecialFrames, "OpenXPDropdownList") end
    return popup
end

--- A dropdown. choices: { { value, text }, ... }, get() -> value, set(value).
function Style.Dropdown(parent, width, choices, get, set)
    local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
    d:SetSize(width, 26)
    Style.Backdrop(d, C.raised, C.borderStrong)
    d.text = Style.Text(d, 12, C.text)
    d.text:SetPoint("LEFT", 10, 0)
    d.text:SetPoint("RIGHT", -24, 0)
    d.text:SetWordWrap(false)
    d.arrow = d:CreateTexture(nil, "ARTWORK")
    d.arrow:SetTexture(TEX .. "down")
    d.arrow:SetSize(12, 12)
    d.arrow:SetPoint("RIGHT", -8, 0)
    Style.Tint(d.arrow, C.dim)
    d.choices = choices
    local function TextOf(v)
        for _, c in ipairs(type(d.choices) == "function" and d.choices() or d.choices) do
            if c[1] == v then return c[2] end
        end
        return tostring(v)
    end
    function d:Update() self.text:SetText(TextOf(get())) end
    function d:Open()
        local p = Popup()
        if p:IsShown() and p.owner == self then p:Hide() return end
        p.owner = self
        local list = type(self.choices) == "function" and self.choices() or self.choices
        local cur = get()
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        p:SetWidth(self:GetWidth() or width)
        for i, c in ipairs(list) do
            local row = p.rows[i]
            if not row then
                row = CreateFrame("Button", nil, p)
                row:SetHeight(24)
                row.hl = row:CreateTexture(nil, "BACKGROUND")
                row.hl:SetAllPoints()
                Fill(row.hl, C.hover, 0)
                row.check = row:CreateTexture(nil, "ARTWORK")
                row.check:SetTexture(TEX .. "check")
                row.check:SetSize(12, 12)
                row.check:SetPoint("RIGHT", -8, 0)
                Style.Tint(row.check, C.blue)
                row.text = Style.Text(row, 12, C.text)
                row.text:SetPoint("LEFT", 10, 0)
                row.text:SetPoint("RIGHT", -24, 0)
                row:SetScript("OnEnter", function(r) Fill(r.hl, { 1, 1, 1 }, 0.07) end)
                row:SetScript("OnLeave", function(r) Fill(r.hl, { 1, 1, 1 }, 0) end)
                row:SetScript("OnClick", function(r)
                    p:Hide()
                    if r.owner then r.owner.pick(r.value) end
                end)
                p.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 24)
            row:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 24)
            row.value, row.owner = c[1], self
            row.text:SetText(c[2])
            Style.TextColor(row.text, c[1] == cur and C.blue or C.text)
            row.check:SetShown(c[1] == cur)
            row:Show()
        end
        for i = #list + 1, #p.rows do p.rows[i]:Hide() end
        p:SetHeight(#list * 24 + 2)
        Style.Fade(p, true, 0.1)
    end
    function d.pick(v)
        set(v)
        d:Update()
    end
    d:SetScript("OnClick", function(self) self:Open() end)
    d:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.blue)) end)
    d:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.borderStrong)) end)
    d:SetScript("OnHide", function(self) if popup and popup.owner == self then popup:Hide() end end)
    d:Update()
    return d
end

--- A search box: onChange(text) on every key.
function Style.SearchBox(parent, width, placeholder, onChange)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 28)
    Style.Backdrop(box, C.panel, C.borderStrong)
    box:SetAutoFocus(false)
    box:SetTextInsets(28, 24, 0, 0)
    OXP.Fonts.Apply(box, OXP.Fonts.Path(), 12, "")
    Style.TextColor(box, C.text)
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    box.icon:SetSize(14, 14)
    box.icon:SetPoint("LEFT", 9, -1)
    Style.Tint(box.icon, C.dim)
    box.hint = Style.Text(box, 12, C.faint)
    box.hint:SetPoint("LEFT", 28, 0)
    box.hint:SetText(placeholder or "")
    box.clear = CreateFrame("Button", nil, box)
    box.clear:SetSize(16, 16)
    box.clear:SetPoint("RIGHT", -6, 0)
    box.clear.icon = box.clear:CreateTexture(nil, "ARTWORK")
    box.clear.icon:SetAllPoints()
    box.clear.icon:SetTexture(TEX .. "cross")
    Style.Tint(box.clear.icon, C.dim)
    box.clear:Hide()
    box.clear:SetScript("OnClick", function()
        box:SetText("")
        box:ClearFocus()
    end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        self.clear:SetShown(text ~= "")
        if onChange then onChange(text) end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.blue)) end)
    box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.borderStrong)) end)
    return box
end

---------------------------------------------------------------------------
-- Scrolling: a clipped area with wheel scrolling and a thin scrollbar
---------------------------------------------------------------------------

--- A scroll area: area.content is what you fill; call area:SetContentHeight(h).
--- Scroll with the wheel, drag the thumb, or click the track to jump a page.
function Style.ScrollArea(parent)
    local area = CreateFrame("ScrollFrame", nil, parent)
    if area.SetClipsChildren then area:SetClipsChildren(true) end
    local content = CreateFrame("Frame", nil, area)
    content:SetSize(10, 10)
    area:SetScrollChild(content)
    area.content = content
    area.offset = 0
    area:EnableMouseWheel(true)
    -- the track: a 12 px strip you can click, with a thin thumb in it that
    -- widens under the mouse and can be dragged
    local bar = CreateFrame("Button", nil, area)
    bar:SetWidth(12)
    bar:SetPoint("TOPRIGHT", 0, -2)
    bar:SetPoint("BOTTOMRIGHT", 0, 2)
    bar:SetFrameLevel(area:GetFrameLevel() + 20)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetPoint("TOPRIGHT", -3, 0)
    bar.track:SetPoint("BOTTOMRIGHT", -3, 0)
    bar.track:SetWidth(4)
    Fill(bar.track, { 1, 1, 1 }, 0.04)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(12)
    thumb:SetFrameLevel(bar:GetFrameLevel() + 1)
    thumb.tex = thumb:CreateTexture(nil, "OVERLAY")
    thumb.tex:SetPoint("TOPRIGHT", -3, 0)
    thumb.tex:SetPoint("BOTTOMRIGHT", -3, 0)
    thumb.tex:SetWidth(4)
    Fill(thumb.tex, { 1, 1, 1 }, 0.22)
    bar.thumb = thumb
    area.bar = bar
    local function Hot(on)
        thumb.tex:SetWidth(on and 6 or 4)
        Fill(thumb.tex, on and C.blue or { 1, 1, 1 }, on and 0.9 or 0.22)
    end
    function area:Max()
        return math.max(0, (self.contentHeight or 0) - (self:GetHeight() or 0))
    end
    function area:Paint()
        local max = self:Max()
        self.offset = math.max(0, math.min(max, self.offset))
        self:SetVerticalScroll(self.offset)
        local h = (self:GetHeight() or 0) - 4
        if max <= 0 or h <= 0 then bar:Hide() return end
        local th = math.min(h, math.max(24, h * h / math.max(1, self.contentHeight or 1)))
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(h - th) * self.offset / max)
        bar.travel = h - th
        bar:Show()
    end
    function area:SetContentHeight(hgt)
        self.contentHeight = hgt
        content:SetHeight(math.max(1, hgt))
        self:Paint()
    end
    function area:ScrollTo(y)
        self.offset = y
        self:Paint()
    end
    -- dragging the thumb: the content follows the mouse
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / (bar:GetEffectiveScale() or 1)
    end
    -- No RegisterForDrag: in the game a frame registered for dragging gets
    -- OnDragStart/OnDragStop instead of OnMouseUp once the mouse moves, so
    -- the thumb never let go. The drag ends when the button is up, checked
    -- every frame (the mouse can be released anywhere on screen).
    local function StopDrag(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        Hot(self:IsMouseOver())
    end
    local function Follow(self)
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopDrag(self)
            return
        end
        local travel = bar.travel or 0
        if travel <= 0 then return end
        local dy = self.startY - CursorY()
        area:ScrollTo(self.startOffset + dy / travel * area:Max())
    end
    thumb.Follow, thumb.StopDrag = Follow, StopDrag
    thumb:SetScript("OnMouseDown", function(self)
        self.startY, self.startOffset = CursorY(), area.offset
        self.dragging = true
        self:SetScript("OnUpdate", Follow) -- only while dragging
        Hot(true)
    end)
    thumb:SetScript("OnMouseUp", StopDrag)
    thumb:SetScript("OnDragStop", StopDrag)
    thumb:SetScript("OnHide", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)
    thumb:SetScript("OnEnter", function() Hot(true) end)
    thumb:SetScript("OnLeave", function(self) if not self.dragging then Hot(false) end end)
    -- clicking the track above or below the thumb: a page that way
    bar:SetScript("OnClick", function()
        local top = thumb:GetTop()
        local y = CursorY()
        local page = (area:GetHeight() or 100) * 0.9
        if top and y > top then area:ScrollTo(area.offset - page) else area:ScrollTo(area.offset + page) end
    end)
    area:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self.offset - delta * 40) end)
    area:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then content:SetWidth(w) end
        self:Paint()
    end)
    return area
end

---------------------------------------------------------------------------
-- Pills and badges
---------------------------------------------------------------------------

Style.STATUS = {
    done = { text = "DONE", color = C.green, tip = "You finished this step." },
    skipped = { text = "SKIPPED", color = C.faint, tip = "You moved past this step without finishing it." },
    chain = { text = "CHAIN MISSED", color = C.gold,
              tip = "An earlier quest in this chain was skipped, so this one can't be picked up yet." },
}

--- A small coloured tag. pill:SetStatus("done") for a step status, or
--- pill:SetTag(text, color).
function Style.Pill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(14)
    pill.bg = pill:CreateTexture(nil, "BACKGROUND")
    pill.bg:SetAllPoints()
    pill.bg:SetTexture(WHITE)
    pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pill.text:SetPoint("CENTER", 0, 0)
    function pill:SetTag(text, color, size)
        if size then Style.FixedFont(self.text, size, "") else Style.SetFont(self.text, -3) end
        self.text:SetText(text)
        self.text:SetTextColor(color[1], color[2], color[3], 1)
        self.bg:SetVertexColor(color[1], color[2], color[3], 0.16)
        self:SetWidth((self.text:GetStringWidth() or 30) + 12)
        self:SetHeight(math.max(14, (size or Style.FontSize(-3)) + 6))
        self:Show()
    end
    function pill:SetStatus(status)
        local st = status and Style.STATUS[status]
        if not st then self:Hide() return end
        self:SetTag(OXP.L(st.text), st.color)
    end
    pill:Hide()
    return pill
end

Style.BADGES = {
    accept = { glyph = "!", color = C.gold },
    turnin = { glyph = "?", color = C.gold },
    -- one flat glyph set (tools/make_ui_icons.py step_icons); kill wears the
    -- skin's accent, not alarm red
    kill = { icon = "step_kill", color = C.blue },
    loot = { icon = "step_loot", color = C.cyan },
    travel = { icon = "step_travel", color = C.green },
    town = { icon = "step_town", color = C.purple },
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
    b.glyph = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.glyph:SetPoint("CENTER", 0, 0)
    function b:SetKind(kind)
        local k = Style.BADGES[kind] or Style.BADGES.travel
        Style.Tint(self.fill, k.color, 0.16)
        Style.Tint(self.ring, k.color, 1)
        if k.glyph then
            self.icon:Hide()
            OXP.Fonts.Apply(self.glyph, OXP.Fonts.Path(), math.floor(size * 0.6), "")
            self.glyph:SetText(k.glyph)
            Style.TextColor(self.glyph, k.color)
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

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

--- A soft shadow under a frame (its own frame, so it never covers it).
function Style.Shadow(f)
    local sh = CreateFrame("Frame", nil, UIParent)
    sh:SetFrameStrata(f:GetFrameStrata() or "DIALOG")
    sh:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
    for i, spec in ipairs({ { 2, 0.30 }, { 5, 0.16 }, { 9, 0.07 } }) do
        local t = sh:CreateTexture(nil, "BACKGROUND", nil, -i)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", -spec[1], spec[1] - 2)
        t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", spec[1], -spec[1] - 3)
        t:SetColorTexture(0, 0, 0, spec[2])
    end
    sh:SetShown(f:IsShown())
    f:HookScript("OnShow", function() sh:Show() end)
    f:HookScript("OnHide", function() sh:Hide() end)
    f.shadow = sh
    return sh
end

--- A dark movable window with a header (logo, title, subtitle, close),
--- closed by Escape, fading in when shown. f.body is the area under the
--- header; add a footer with Style.Footer(f).
function Style.Window(name, width, height, title, subtitle)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Style.Backdrop(f, C.bgSolid, C.border)
    if name and _G.UISpecialFrames then tinsert(_G.UISpecialFrames, name) end
    -- header
    f.header = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.header:SetPoint("TOPLEFT", 1, -1)
    f.header:SetPoint("TOPRIGHT", -1, -1)
    f.header:SetHeight(S.header - 1)
    Fill(f.header, C.panel)
    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.accent:SetPoint("TOPLEFT", 1, -1)
    f.accent:SetPoint("TOPRIGHT", -1, -1)
    f.accent:SetHeight(2)
    Fill(f.accent, C.blue, 0.9)
    f.headerLine = Style.Divider(f)
    f.headerLine:SetPoint("TOPLEFT", 1, -S.header)
    f.headerLine:SetPoint("TOPRIGHT", -1, -S.header)
    f.logo = f:CreateTexture(nil, "OVERLAY")
    f.logo:SetTexture(Style.LOGO)
    f.logo:SetSize(26, 26)
    f.logo:SetPoint("LEFT", f, "TOPLEFT", S.lg, -S.header / 2)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Style.FixedFont(f.title, 15, "")
    f.title:SetText(title or "OpenXP")
    f.title:SetTextColor(1, 1, 1)
    f.subtitle = Style.Text(f, 11, C.dim)
    if subtitle then
        f.title:SetPoint("BOTTOMLEFT", f.logo, "RIGHT", 10, 0)
        f.subtitle:SetPoint("TOPLEFT", f.logo, "RIGHT", 10, -2)
        f.subtitle:SetText(subtitle)
    else
        f.title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
    end
    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(28, 28)
    f.close:SetPoint("RIGHT", f, "TOPRIGHT", -10, -S.header / 2)
    f.close.bg = f.close:CreateTexture(nil, "BACKGROUND")
    f.close.bg:SetAllPoints()
    Fill(f.close.bg, { 1, 1, 1 }, 0)
    f.close.icon = f.close:CreateTexture(nil, "ARTWORK")
    f.close.icon:SetTexture(TEX .. "cross")
    f.close.icon:SetSize(12, 12)
    f.close.icon:SetPoint("CENTER")
    Style.Tint(f.close.icon, C.dim)
    f.close:SetScript("OnEnter", function(self)
        Fill(self.bg, C.red, 0.25)
        Style.Tint(self.icon, { 1, 1, 1 })
    end)
    f.close:SetScript("OnLeave", function(self)
        Fill(self.bg, { 1, 1, 1 }, 0)
        Style.Tint(self.icon, C.dim)
    end)
    f.close:SetScript("OnClick", function() f:Hide() end)
    -- body: everything under the header
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 1, -S.header - 1)
    f.body:SetPoint("BOTTOMRIGHT", -1, 1)
    f:HookScript("OnShow", function(self)
        self:SetAlpha(0)
        Style.Tween(self, 0, 1, 0.15, function(a) self:SetAlpha(a) end)
    end)
    Style.Shadow(f)
    f:Hide()
    return f
end

--- A yes/no question in the skin's look, over everything (one at a time):
--- Style.Confirm(text, yesLabel, onYes, noLabel). Escape or "Cancel"
--- closes it without doing anything.
local confirm
function Style.Confirm(text, yesLabel, onYes, noLabel)
    if not confirm then
        confirm = CreateFrame("Frame", "OpenXPConfirm", UIParent, "BackdropTemplate")
        confirm:SetSize(380, 150)
        confirm:SetPoint("CENTER", 0, 120)
        confirm:SetFrameStrata("FULLSCREEN_DIALOG")
        confirm:SetToplevel(true)
        confirm:EnableMouse(true)
        confirm:SetClampedToScreen(true)
        Style.Backdrop(confirm, C.bgSolid, C.borderStrong)
        confirm.accent = confirm:CreateTexture(nil, "ARTWORK")
        confirm.accent:SetPoint("TOPLEFT", 1, -1)
        confirm.accent:SetPoint("TOPRIGHT", -1, -1)
        confirm.accent:SetHeight(2)
        Fill(confirm.accent, C.blue, 0.9)
        confirm.text = Style.Text(confirm, 13, C.text)
        confirm.text:SetPoint("TOPLEFT", S.lg, -S.lg - 2)
        confirm.text:SetPoint("TOPRIGHT", -S.lg, -S.lg - 2)
        confirm.text:SetJustifyH("CENTER")
        confirm.text:SetWordWrap(true)
        confirm.yes = Style.Button(confirm, "", "primary", 150, function()
            confirm:Hide()
            if confirm.onYes then confirm.onYes() end
        end)
        confirm.no = Style.Button(confirm, "", "secondary", 110, function() confirm:Hide() end)
        confirm.yes:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -4, S.lg)
        confirm.no:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 4, S.lg)
        Style.Shadow(confirm)
        if _G.UISpecialFrames then tinsert(_G.UISpecialFrames, "OpenXPConfirm") end
        confirm:Hide()
    end
    confirm.onYes = onYes
    confirm.text:SetText(text)
    confirm.yes:SetLabel(yesLabel or OXP.L("OK"))
    confirm.no:SetLabel(noLabel or OXP.L("Cancel"))
    confirm:SetHeight(math.max(120, (confirm.text:GetStringHeight() or 30) + 30 + S.lg * 3 + 8))
    confirm:Show()
    confirm:Raise()
    return confirm
end

--- A footer bar along the bottom of a window (for its buttons); the body
--- then ends above it.
function Style.Footer(f)
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(S.footer)
    foot.bg = foot:CreateTexture(nil, "BACKGROUND")
    foot.bg:SetAllPoints()
    Fill(foot.bg, C.panel)
    foot.line = Style.Divider(foot)
    foot.line:SetPoint("TOPLEFT")
    foot.line:SetPoint("TOPRIGHT")
    f.body:SetPoint("BOTTOMRIGHT", -1, S.footer + 1)
    f.footer = foot
    return foot
end
