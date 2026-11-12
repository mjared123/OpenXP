-- The one-time note after a 1.x character's first 2.0 login: where OpenXP
-- put you, with "Find my place" (smart start) and "Go back" (to the step the
-- import picked, after trying Find my place).
local _, OXP = ...

local Note = {}
OXP.ImportNote = Note

local Style, L = OXP.Style, OXP.L
local C = Style.C

local f

local function Build()
    f = Style.Window("OpenXPImportNote", 420, 190, L("OpenXP 2.0"))
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", 18, -50)
    f.body:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.body:SetJustifyH("LEFT")
    f.body:SetTextColor(unpack(C.text))
    f.find = Style.DialogButton(f, L("Find my place"), false, 120)
    f.find:SetPoint("BOTTOMLEFT", 16, 14)
    f.find:SetScript("OnClick", function()
        OXP.SmartStart.Run(false)
        f.back:Show()
    end)
    f.back = Style.DialogButton(f, L("Go back"), false, 100)
    f.back:SetPoint("LEFT", f.find, "RIGHT", 8, 0)
    f.back:SetScript("OnClick", function()
        local r = Note.result
        if r and r.placed then
            OXP.Engine.Load(r.placed)
            local pos = r.step and r.step <= #OXP.Engine.GetSteps() and r.step
            if pos then OXP.Engine.GoTo(pos, true) end
        end
        f:Hide()
    end)
    f.ok = Style.DialogButton(f, L("OK"), true, 100)
    f.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    f.ok:SetScript("OnClick", function() f:Hide() end)
end

--- The note's text for an import result.
function Note.Text(r)
    local where
    if r.placed then
        where = ("%s, step %d"):format(r.placed.name, r.step or 1)
    else
        where = L("no guide yet")
    end
    local lines = { ("OpenXP 2.0: we moved you to %s."):format(where) }
    if r.smart then
        lines[#lines + 1] = L("2.0 has a new 1-20 route, so OpenXP picked your place from your quest log and finished quests.")
    else
        lines[#lines + 1] = L("Same guide and step as in 1.x.")
    end
    if (r.flights or 0) > 0 then
        lines[#lines + 1] = ("%d %s"):format(r.flights, L("flight paths carried over."))
    end
    return table.concat(lines, "\n")
end

OXP.Listen("IMPORTED", function(_, r)
    Note.result = r
    if not f then Build() end
    f.body:SetText(Note.Text(r))
    f.back:Hide()
    if C_Timer and C_Timer.After then
        C_Timer.After(4, function() f:Show() end)
    else
        f:Show()
    end
end)
