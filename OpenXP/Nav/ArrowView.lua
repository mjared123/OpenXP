-- How the arrow looks, and nothing else: a small renderer the arrow's
-- direction logic (Nav/Arrow.lua) feeds a state to. It never asks where
-- anything is, so the logic behind it can be swapped (SoupNav) without
-- touching the look.
--
--   view:Set({ mode = "point", angle = radians, distance = "123 yd", label = "Kill wolves" })
--   modes: "point" (turn to angle; 0 is straight ahead, like SetRotation),
--          "here" (you're there: a check), "area" (inside the kill area),
--          "lost" (no way to point: another continent), "none" (hidden)
--
-- Settings (Settings > Arrow): arrowStyle, arrowShowRing, arrowShowDistance,
-- arrowShowLabel, arrowColor ("skin", "distance", "white"), arrowScale,
-- arrowAlpha, arrowText (text size). Colours follow the card's skin.
local ADDON, OXP = ...

local View = {}
OXP.ArrowView = View

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Card\\"
local GREEN = { 61 / 255, 187 / 255, 122 / 255 }

-- Each style: the pointer texture, its size on the 80 px dial, the ring
-- texture under it, and whether a dot sits in the middle (orbit).
View.STYLES = {
    chevron = { name = "Chevron", tex = "arrow_chevron", size = 46, ring = "ring_thin" },
    classic = { name = "Classic", tex = "pointer", size = 44, ring = "dialring" },
    needle = { name = "Needle", tex = "arrow_needle", size = 60, ring = "ring_thin" },
    triangle = { name = "Solid triangle", tex = "arrow_triangle", size = 40, ring = "ring_thin" },
    orbit = { name = "Dot and pointer", tex = "arrow_orbit", size = 76, ring = "ring_thin", dot = true },
}
View.STYLE_ORDER = { "chevron", "classic", "needle", "triangle", "orbit" }

function View.StyleChoices()
    local L = OXP.L or function(t) return t end
    local list = {}
    for _, k in ipairs(View.STYLE_ORDER) do list[#list + 1] = { k, L(View.STYLES[k].name) } end
    return list
end

local function S() return OXP.settings or {} end
local function On(v) return v ~= false end

local function Accent()
    local C = OXP.Style and OXP.Style.C
    return C and C.blue or { 90 / 255, 184 / 255, 1 }
end

-- far (red) to close (green), for the "by distance" colour
local function DistanceColour(yards)
    if not yards then return Accent() end
    local t = math.max(0, math.min(1, (yards - 30) / 470)) -- 30 yd: green, 500+: red
    local r = t < 0.5 and (0.25 + t * 1.5) or 1
    local g = t < 0.5 and 0.85 or (0.85 - (t - 0.5) * 1.3)
    return { r, math.max(0.2, g), 0.35 }
end

--- A new arrow view drawn on `f` (a frame you own and place).
function View.New(f)
    local v = { frame = f }
    f.disc = f:CreateTexture(nil, "BACKGROUND")
    f.disc:SetTexture(TEX .. "dialdisc")
    f.disc:SetPoint("CENTER")
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.glow:SetTexture(TEX .. "glow")
    f.glow:SetPoint("CENTER")
    f.glow:SetAlpha(0)
    f.ring = f:CreateTexture(nil, "BORDER")
    f.ring:SetPoint("CENTER")
    f.pointer = f:CreateTexture(nil, "ARTWORK")
    f.pointer:SetPoint("CENTER")
    f.dot = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.dot:SetTexture(TEX .. "filledcircle")
    f.dot:SetPoint("CENTER")
    f.check = f:CreateTexture(nil, "OVERLAY")
    f.check:SetTexture(TEX .. "check")
    f.check:SetPoint("CENTER")
    f.check:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
    f.check:Hide()
    f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.label:SetTextColor(0.78, 0.80, 0.86)
    -- arriving: the glow swells once (a real AnimationGroup, played on arrival)
    if f.glow.CreateAnimationGroup then
        local ag = f.glow:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        if a.SetFromAlpha then a:SetFromAlpha(0) a:SetToAlpha(0.8) end
        if a.SetDuration then a:SetDuration(0.25) end
        local b = ag:CreateAnimation("Alpha")
        if b.SetFromAlpha then b:SetFromAlpha(0.8) b:SetToAlpha(0.25) end
        if b.SetDuration then b:SetDuration(0.6) end
        if b.SetStartDelay then b:SetStartDelay(0.25) end
        if b.SetOrder then a:SetOrder(1) b:SetOrder(2) end
        ag:SetScript("OnFinished", function() f.glow:SetAlpha(0.25) end)
        v.arrive = ag
    end
    setmetatable(v, { __index = View })
    v:Restyle()
    return v
end

--- Applies the size, style, ring and text settings (cheap when nothing
--- changed; call it every draw).
function View:Restyle()
    local f, s = self.frame, S()
    local scale, text = s.arrowScale or 1, s.arrowText or 12
    local style = View.STYLES[s.arrowStyle] or View.STYLES.chevron
    local Fonts = OXP.Fonts
    local font = Fonts and Fonts.Path() or "Fonts\\FRIZQT__.TTF"
    local flags = Fonts and Fonts.Flags("OUTLINE") or "OUTLINE"
    local skin = OXP.Style and OXP.Style.skinKey or ""
    local key = table.concat({ scale, text, font, flags, tostring(s.arrowStyle), tostring(s.arrowShowRing),
        tostring(s.arrowShowDistance), tostring(s.arrowShowLabel), tostring(s.arrowColor), skin,
        tostring(s.arrowAlpha) }, ":")
    if self.key == key then return end
    self.key, self.style = key, style
    local dial = 76 * scale
    f:SetSize(80 * scale, 80 * scale)
    f.disc:SetSize(dial, dial)
    f.glow:SetSize(dial * 1.5, dial * 1.5)
    f.ring:SetSize(dial, dial)
    f.ring:SetTexture(TEX .. style.ring)
    f.pointer:SetTexture(TEX .. style.tex)
    f.pointer:SetSize(style.size * scale, style.size * scale)
    f.dot:SetSize(12 * scale, 12 * scale)
    f.check:SetSize(36 * scale, 36 * scale)
    local ring = On(s.arrowShowRing)
    -- the dark disc only with the ring; Minimal never draws one
    local frameless = OXP.Style and OXP.Style.skin and OXP.Style.skin.frameless
    f.disc:SetShown(ring and not frameless)
    f.ring:SetShown(ring)
    if Fonts then
        Fonts.Apply(f.dist, font, text + 5, flags)
        Fonts.Apply(f.label, font, text, flags)
    end
    for _, fs in ipairs({ f.dist, f.label }) do
        if fs.SetShadowOffset then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end
    end
    f.dist:ClearAllPoints()
    f.dist:SetPoint("TOP", f, "BOTTOM", 0, ring and -2 or 6)
    f.label:ClearAllPoints()
    if On(s.arrowShowDistance) then
        f.label:SetPoint("TOP", f.dist, "BOTTOM", 0, -3)
    else
        f.label:SetPoint("TOP", f, "BOTTOM", 0, ring and -2 or 6)
    end
    local bg = OXP.Style and OXP.Style.C and OXP.Style.C.bgSolid or { 0.06, 0.07, 0.08 }
    f.disc:SetVertexColor(bg[1], bg[2], bg[3], 0.78)
    self.last = nil -- paint the state again in the new look
end

local function Tint(tex, c, a) tex:SetVertexColor(c[1], c[2], c[3], a or 1) end

--- Draws `state` (see the top of this file).
function View:Set(state)
    local f, s = self.frame, S()
    self:Restyle()
    local mode = state and state.mode or "none"
    if mode == "none" then
        f.pointer:Hide()
        f.dot:Hide()
        f.check:Hide()
        f.dist:SetText("")
        f.label:SetText("")
        f:SetAlpha(0)
        self.mode = mode
        return
    end
    f:SetAlpha(s.arrowAlpha or 1)
    local accent = Accent()
    if s.arrowColor == "white" then accent = { 0.96, 0.97, 0.98 }
    elseif s.arrowColor == "distance" then accent = DistanceColour(state.yards) end
    local arrived = mode == "here" or mode == "area"
    if arrived and self.mode ~= mode and self.arrive then
        self.arrive:Stop()
        self.arrive:Play()
    elseif not arrived then
        if self.arrive and self.arrive:IsPlaying() then self.arrive:Stop() end
        f.glow:SetAlpha(0)
    end
    self.mode = mode
    if arrived then
        f.pointer:Hide()
        f.dot:Hide()
        f.check:Show()
        Tint(f.ring, GREEN, 1)
        Tint(f.glow, GREEN, 1)
        f.dist:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    elseif mode == "point" then
        f.check:Hide()
        f.pointer:Show()
        f.dot:SetShown(self.style.dot == true)
        if state.angle then f.pointer:SetRotation(state.angle) end
        Tint(f.pointer, accent, 1)
        Tint(f.dot, accent, 1)
        Tint(f.ring, accent, 0.55)
        f.dist:SetTextColor(0.96, 0.97, 0.98)
    else -- lost
        f.check:Hide()
        f.pointer:Hide()
        f.dot:SetShown(self.style.dot == true)
        Tint(f.dot, accent, 0.4)
        Tint(f.ring, accent, 0.3)
        f.dist:SetTextColor(0.7, 0.72, 0.78)
    end
    f.dist:SetText(On(s.arrowShowDistance) and (state.distance or "") or "")
    f.label:SetText(On(s.arrowShowLabel) and (state.label or "") or "")
end
