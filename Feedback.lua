-- OpenXP feedback window: report a bug, suggest something, leave a comment
-- or rate OpenXP.
--
-- WoW addons can't open web pages or send anything out of the game, so this
-- window shows links the player copies into their browser. The bug report
-- link fills in the OpenXP version, guide and step on GitHub's form, and the
-- full bug form (addon.comms.OpenBugReport) has the rest of the details.
--
-- Open it with /oxp feedback, /oxp bug, or "Feedback and bugs" in the menus.

local addonName, addon = ...

local GITHUB = "https://github.com/mjared123/OpenXP"
local CURSEFORGE = "https://www.curseforge.com/wow/addons/openxp"

local feedback = {
    links = {
        bug = GITHUB .. "/issues/new?template=bug_report.yml",
        suggestion = GITHUB .. "/issues/new?template=suggestion.yml",
        comment = CURSEFORGE .. "/comments",
        rate = CURSEFORGE,
    },
}
addon.feedback = feedback

-- Same palette as the welcome window and guide card.
local COLORS = {
    bg = {16 / 255, 17 / 255, 21 / 255, 0.96},
    panel = {22 / 255, 24 / 255, 29 / 255, 0.9},
    accent = {90 / 255, 184 / 255, 255 / 255},
    border = {60 / 255, 66 / 255, 78 / 255},
    text = {0.86, 0.86, 0.9},
    muted = {0.6, 0.62, 0.7},
}
local ACCENT_HEX = "|cFF5AB8FF"

local function UrlEncode(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")
    return (s:gsub("[^%w%-%._~ ]", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+"))
end
feedback.UrlEncode = UrlEncode

-- What the bug report form on GitHub gets filled in with.
function feedback.BugInfo()
    local guide = addon.currentGuide
    local guideName = "None"
    if guide and (guide.displayname or guide.name) then
        guideName = tostring(guide.displayname or guide.name):gsub("\n", " ")
        if guide.group then guideName = guide.group .. ": " .. guideName end
    end

    local step = "N/A"
    if guide and addon.GetGuideProgress then
        local ok, n = pcall(addon.GetGuideProgress)
        if ok and n then
            local total = guide.steps and #guide.steps
            step = total and total > 0 and string.format("%d of %d", n, total) or tostring(n)
        end
    end

    local character = "Unknown"
    local p = addon.player
    if p and p.race and p.class then
        character = string.format("%s %s, level %s", p.race, p.class, tostring(p.level or UnitLevel("player")))
    end

    return {
        version = addon.openxpVersion or addon.release or "unknown",
        guide = guideName,
        step = step,
        character = character,
        zone = (GetRealZoneText and GetRealZoneText()) or "",
    }
end

-- GitHub fills issue form fields from query parameters named after their ids
-- (see .github/ISSUE_TEMPLATE/bug_report.yml).
function feedback.BugLink()
    local info = feedback.BugInfo()
    local zone = info.zone ~= "" and (" in " .. info.zone) or ""
    return string.format("%s&version=%s&guide=%s&step=%s&character=%s", feedback.links.bug,
                         UrlEncode(info.version), UrlEncode(info.guide), UrlEncode(info.step),
                         UrlEncode(info.character .. zone))
end

local function Backdrop(f, bg, border)
    f:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(border))
end

local function MakeButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 120, 22)
    Backdrop(b, {28 / 255, 70 / 255, 104 / 255, 1}, COLORS.accent)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(1, 1, 1)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 1, 1, 0.8) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(COLORS.accent)) end)
    return b
end

-- A one-line box holding a link. Clicking it selects the whole link so
-- Ctrl+C copies it; typing can't change it.
local function MakeLinkBox(parent)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    Backdrop(box, {10 / 255, 11 / 255, 14 / 255, 1}, COLORS.border)
    box.SetLink = function(self, url)
        self.url = url
        self:SetText(url)
        self:SetCursorPosition(0)
    end
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self.url then
            self:SetText(self.url)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        self:SetBackdropBorderColor(unpack(COLORS.accent))
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        self:SetBackdropBorderColor(unpack(COLORS.border))
    end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnKeyUp", function(self, key)
        if key == "C" and IsControlKeyDown and IsControlKeyDown() then
            if addon.comms and addon.comms.PrettyPrint then
                addon.comms.PrettyPrint("Link copied. Paste it into your web browser.")
            end
            self:ClearFocus()
        end
    end)
    return box
end

local SECTIONS = {
    {
        key = "bug",
        title = "Report a bug",
        text = "Something broken or wrong in a guide? This link opens a GitHub bug report with your OpenXP version, guide and step already filled in.",
        button = "Full bug details",
        tip = "Opens a form with everything about your character, step and arrow. Paste it into the bug report.",
        onClick = function() if addon.comms and addon.comms.OpenBugReport then addon.comms.OpenBugReport() end end,
    },
    {
        key = "suggestion",
        title = "Suggest something",
        text = "An idea for a feature, a better route or a quest the guide should add.",
    },
    {
        key = "comment",
        title = "Leave a comment",
        text = "Say hi, ask a question or tell other players how OpenXP worked for you, on CurseForge.",
    },
    {
        key = "rate",
        title = "Rate OpenXP",
        text = "Enjoying OpenXP? A rating on CurseForge helps other players find it.",
    },
}

local frame

local function CreateFeedbackFrame()
    local f = CreateFrame("Frame", "OpenXPFeedbackFrame", UIParent, "BackdropTemplate")
    f:SetSize(460, 470)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Backdrop(f, COLORS.bg, COLORS.accent)
    tinsert(_G.UISpecialFrames, "OpenXPFeedbackFrame") -- Escape closes it

    local logo = f:CreateTexture(nil, "OVERLAY")
    logo:SetTexture("Interface/AddOns/" .. addonName .. "/Textures/openxp_logo-64")
    logo:SetSize(32, 32)
    logo:SetPoint("TOPLEFT", 14, -12)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    title:SetText("Feedback")
    title:SetTextColor(1, 1, 1)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -54)
    hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(unpack(COLORS.muted))
    hint:SetText("WoW can't open web pages, so click a link, press " .. ACCENT_HEX ..
                     "Ctrl+C|r to copy it, and paste it into your web browser.")

    f.boxes = {}
    local anchor = hint
    for i, s in ipairs(SECTIONS) do
        local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -12 or -8)
        panel:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        panel:SetHeight(86)
        Backdrop(panel, COLORS.panel, COLORS.border)

        local head = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        head:SetPoint("TOPLEFT", 10, -9)
        head:SetText(s.title)
        head:SetTextColor(unpack(COLORS.accent))

        local body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
        body:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
        body:SetJustifyH("LEFT")
        body:SetTextColor(unpack(COLORS.text))
        body:SetText(s.text)

        local box = MakeLinkBox(panel)
        box:SetPoint("BOTTOMLEFT", 10, 9)
        if s.button then
            local b = MakeButton(panel, s.button, 110)
            b:SetPoint("BOTTOMRIGHT", -10, 9)
            b:SetScript("OnClick", s.onClick)
            b:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(s.button, 1, 1, 1)
                GameTooltip:AddLine(s.tip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
            box:SetPoint("RIGHT", b, "LEFT", -6, 0)
        else
            box:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
        end
        f.boxes[s.key] = box
        anchor = panel
    end

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOM", 0, 12)
    footer:SetText("Thanks for helping make OpenXP better!")

    f:Hide()
    return f
end

function feedback.Show()
    frame = frame or CreateFeedbackFrame()
    for key, box in pairs(frame.boxes) do
        box:SetLink(key == "bug" and feedback.BugLink() or feedback.links[key])
    end
    frame:Show()
end

function feedback.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        feedback.Show()
    end
end
