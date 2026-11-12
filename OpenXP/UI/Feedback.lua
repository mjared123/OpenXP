-- The feedback window: report a bug, suggest something, leave a comment or
-- rate OpenXP. WoW can't open web pages, so it shows links to copy into a
-- browser; the bug link fills in the version, guide and step on GitHub's form.
local _, OXP = ...

local Feedback = {}
OXP.Feedback = Feedback

local Style, L = OXP.Style, OXP.L
local C = Style.C

local GITHUB = "https://github.com/mjared123/OpenXP"
local CURSEFORGE = "https://www.curseforge.com/projects/1792509"
Feedback.links = {
    bug = GITHUB .. "/issues/new?template=bug_report.yml",
    suggestion = GITHUB .. "/issues/new?template=suggestion.yml",
    comment = CURSEFORGE,
    rate = CURSEFORGE,
}

function Feedback.UrlEncode(s)
    s = OXP.Text.Strip(tostring(s or "")):gsub("\n", " ")
    return (s:gsub("[^%w%-%._~ ]", function(c) return ("%%%02X"):format(c:byte()) end):gsub(" ", "+"))
end

--- What the GitHub bug form is filled in with.
function Feedback.BugInfo()
    local g = OXP.Engine.GetGuide()
    local step = "N/A"
    if g then
        local _, total = OXP.Engine.GetProgress()
        step = ("%d of %d"):format(OXP.Engine.GetPosition() or 0, total)
    end
    local p = OXP.Player
    return {
        version = tostring(OXP.version),
        guide = g and (g.group .. ": " .. g.name) or "None",
        step = step,
        character = ("%s %s, level %s"):format(tostring(p.race), tostring(p.class), tostring(p.level)),
        zone = GetRealZoneText and GetRealZoneText() or "",
    }
end

function Feedback.BugLink()
    local info = Feedback.BugInfo()
    local E = Feedback.UrlEncode
    local zone = info.zone ~= "" and (" in " .. info.zone) or ""
    return ("%s&version=%s&guide=%s&step=%s&character=%s"):format(Feedback.links.bug, E(info.version),
        E(info.guide), E(info.step), E(info.character .. zone))
end

-- a one-line box holding a link: clicking selects it all, typing can't change it
local function LinkBox(parent)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    Style.Backdrop(box, { 10 / 255, 11 / 255, 14 / 255, 1 }, C.line)
    function box:SetLink(url)
        self.url = url
        self:SetText(url)
        self:SetCursorPosition(0)
    end
    box:SetScript("OnTextChanged", function(self, user)
        if user and self.url then
            self:SetText(self.url)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local SECTIONS = {
    { key = "bug", title = "Report a bug",
      text = "Something broken or wrong in a guide? This link opens a GitHub bug report with your version, guide and step filled in. Add the output of /oxp step if you can." },
    { key = "suggestion", title = "Suggest something", text = "An idea for a feature, a better route or a quest the guide should add." },
    { key = "comment", title = "Leave a comment", text = "Say hi, ask a question or tell other players how OpenXP worked for you, on CurseForge." },
    { key = "rate", title = "Rate OpenXP", text = "Enjoying OpenXP? A rating on CurseForge helps other players find it." },
}

local f
local function Build()
    f = Style.Window("OpenXPFeedback", 460, 470, L("Feedback"))
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -50)
    hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(unpack(C.dim))
    hint:SetText(L("WoW can't open web pages, so click a link, press Ctrl+C to copy it, and paste it into your web browser."))
    f.boxes = {}
    local anchor = hint
    for i, s in ipairs(SECTIONS) do
        local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -12 or -8)
        panel:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        panel:SetHeight(86)
        Style.Backdrop(panel, C.panel, C.line)
        local head = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        head:SetPoint("TOPLEFT", 10, -9)
        head:SetText(L(s.title))
        head:SetTextColor(unpack(C.blue))
        local body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
        body:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
        body:SetJustifyH("LEFT")
        body:SetTextColor(unpack(C.text))
        body:SetText(L(s.text))
        local box = LinkBox(panel)
        box:SetPoint("BOTTOMLEFT", 10, 9)
        box:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
        f.boxes[s.key] = box
        anchor = panel
    end
end

function Feedback.Show()
    if not f then Build() end
    for key, box in pairs(f.boxes) do box:SetLink(key == "bug" and Feedback.BugLink() or Feedback.links[key]) end
    f:Show()
end

OXP.AddCommand("feedback", "report a bug, suggest something or rate OpenXP", Feedback.Show)
OXP.AddCommand("bug", nil, Feedback.Show)
