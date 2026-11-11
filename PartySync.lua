local _, addon = ...

---------------------------------------------------------------------------
-- Party sync (work in progress, feature branch only)
---------------------------------------------------------------------------
-- When more than one person in a party runs OpenXP, each copy sends a
-- small hidden addon message to the party with:
--   * which guide and step it's on (and the guide length)
--   * level and class
--   * for the quests on its own step, and for the quests on every party
--     member's step, whether it has the quest, how far along it is, or
--     whether it already turned it in
-- So every copy knows, for the step you're on, who has the quest, who is
-- done with it and who still needs it.
--
-- The card shows that in a small party panel under it. A party member can
-- tick "Follow the party leader": then each time the leader moves to a new
-- step in the same guide, their card goes to that step too.
--
-- Messages go over the same addon channel as the rest of OpenXP
-- (Communications.lua, "OpenXPComms") with command = "SYNC". They're only
-- sent while in a party (not in raids or battlegrounds), at most once a
-- second, and only when something changed, plus a heartbeat every 15 s.
---------------------------------------------------------------------------

local ps = {}
addon.partySync = ps

local fmt, tinsert, tsort, pairs, ipairs, type, tonumber = string.format, table.insert, table.sort, pairs, ipairs,
                                                          type, tonumber

ps.VERSION = 1
ps.SEND_MIN_GAP = 1      -- seconds between two status messages
ps.HEARTBEAT = 15        -- resend unchanged status this often
ps.STALE = 45            -- a member we haven't heard from this long is greyed out
ps.MAX_QUESTS = 30       -- most quest states in one message
ps.members = ps.members or {}

local function Now() return (GetTime and GetTime()) or 0 end

local function Settings() return addon.settings and addon.settings.profile or {} end

function ps.Enabled()
    local p = Settings()
    return p.partySync ~= false
end

local function ShortName(name)
    if not name then return end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:gsub("%-.*$", ""))
end
ps.ShortName = ShortName

-- In a party of 2-5 (raids and battlegrounds are left out on purpose)
function ps.InParty()
    if UnitInBattleground and UnitInBattleground("player") ~= nil then return false end
    if IsInRaid and IsInRaid() then return false end
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 1
end

---------------------------------------------------------------------------
-- What this copy knows about itself
---------------------------------------------------------------------------

local function QuestIdOf(e)
    local id = tonumber(e and e.questId)
    if id and id > 0 then return id end
end

-- Quest ids on the steps currently on screen (current step first)
function ps.StepQuestIds(steps)
    local ids, seen = {}, {}
    for _, step in ipairs(steps or {}) do
        for _, e in ipairs(step.elements or {}) do
            if e.tag == "accept" or e.tag == "turnin" or e.tag == "complete" then
                local id = QuestIdOf(e)
                if id and not seen[id] then
                    seen[id] = true
                    tinsert(ids, id)
                end
            end
        end
    end
    return ids
end

-- Objective progress as "3/8" for the first objective that isn't done
local function Progress(id)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, id)
    if not ok or type(objectives) ~= "table" then return end
    for _, o in ipairs(objectives) do
        if not o.finished and o.numRequired and o.numRequired > 0 then
            return fmt("%d/%d", o.numFulfilled or 0, o.numRequired)
        end
    end
end

-- One quest's state, short so messages stay small:
--   "t" turned in, "c" in the log and ready to turn in,
--   "p" or "p3/8" in the log, "m" not in the log
function ps.QuestState(id)
    if addon.IsQuestTurnedIn and addon.IsQuestTurnedIn(id) then return "t" end
    if addon.IsOnQuest and addon.IsOnQuest(id) then
        if addon.IsQuestComplete and addon.IsQuestComplete(id) then return "c" end
        return "p" .. (Progress(id) or "")
    end
    return "m"
end

-- Quest ids we report on: ours first, then the ones on party members' steps
function ps.WantedQuestIds(mine, members)
    local ids, seen = {}, {}
    local function add(id)
        if id and not seen[id] and #ids < ps.MAX_QUESTS then
            seen[id] = true
            tinsert(ids, id)
        end
    end
    for _, id in ipairs(mine or {}) do add(id) end
    local names = {}
    for name in pairs(members or {}) do tinsert(names, name) end
    tsort(names)
    for _, name in ipairs(names) do
        for _, id in ipairs(members[name].ids or {}) do add(id) end
    end
    return ids
end

function ps.BuildStatus()
    local guide = addon.currentGuide
    local steps = addon.RXPFrame and addon.RXPFrame.activeSteps or {}
    local mine = ps.StepQuestIds(steps)
    local q = {}
    for _, id in ipairs(ps.WantedQuestIds(mine, ps.members)) do q[id] = ps.QuestState(id) end
    return {
        command = "SYNC",
        v = ps.VERSION,
        g = guide and guide.name or "",
        s = (addon.GetGuideProgress and addon.GetGuideProgress()) or 0,
        n = guide and guide.steps and #guide.steps or 0,
        lv = UnitLevel and UnitLevel("player") or 0,
        c = addon.player and addon.player.class or "",
        ids = mine,
        q = q,
    }
end

-- Stable text form of a status, to tell whether anything changed
function ps.Signature(status)
    local parts = {status.g, status.s, status.n, status.lv}
    local ids = {}
    for id in pairs(status.q or {}) do tinsert(ids, id) end
    tsort(ids)
    for _, id in ipairs(ids) do tinsert(parts, id .. "=" .. status.q[id]) end
    tinsert(parts, "|")
    for _, id in ipairs(status.ids or {}) do tinsert(parts, id) end
    return table.concat(parts, ",")
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

function ps.Send(status, force)
    local comms = addon.comms
    if not (comms and comms.Serialize and comms.SendCommMessage) then return end
    local sig = ps.Signature(status)
    local now = Now()
    if not force and sig == ps.lastSig and now - (ps.lastSent or 0) < ps.HEARTBEAT then return end
    if now - (ps.lastSent or 0) < ps.SEND_MIN_GAP then return end
    ps.lastSig, ps.lastSent = sig, now
    comms:SendCommMessage(comms._commPrefix, comms:Serialize(status), "PARTY")
    return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function ValidStatus(obj)
    return type(obj) == "table" and type(obj.g) == "string" and type(tonumber(obj.s)) == "number" and
               type(obj.q) == "table"
end

-- Called from Communications.lua for command == "SYNC"
function ps.OnStatus(sender, obj)
    if not ValidStatus(obj) then return end
    local name = ShortName(sender)
    if not name or (addon.player and name == addon.player.name) then return end
    local ids = {}
    for _, id in ipairs(type(obj.ids) == "table" and obj.ids or {}) do
        id = tonumber(id)
        if id then tinsert(ids, id) end
    end
    local q = {}
    for id, state in pairs(obj.q) do
        id = tonumber(id)
        if id and type(state) == "string" then q[id] = state end
    end
    local old = ps.members[name]
    local m = {
        name = name,
        guide = obj.g,
        step = tonumber(obj.s) or 0,
        total = tonumber(obj.n) or 0,
        level = tonumber(obj.lv) or 0,
        class = type(obj.c) == "string" and obj.c or nil,
        ids = ids,
        q = q,
        seen = Now(),
    }
    ps.members[name] = m

    -- A new member, or one that just moved on: they want our states for
    -- their quests, so answer soon instead of waiting for the heartbeat
    if not old or old.step ~= m.step or old.guide ~= m.guide then ps.dirty = true end

    if old and (old.step ~= m.step or old.guide ~= m.guide) then ps.OnMemberMoved(m, old) end
    if ps.Redraw then ps.Redraw() end
end

---------------------------------------------------------------------------
-- Follow the party leader
---------------------------------------------------------------------------

function ps.LeaderName()
    if not (UnitIsGroupLeader and GetNumGroupMembers) then return end
    for i = 1, (GetNumGroupMembers() or 0) - 1 do
        local unit = "party" .. i
        if UnitIsGroupLeader(unit) then return ShortName(UnitName(unit)) end
    end
end

function ps.Following()
    return Settings().partyFollowLeader and not (UnitIsGroupLeader and UnitIsGroupLeader("player"))
end

-- What following the leader would do right now: a step number to go to,
-- or nil and the reason it won't
function ps.FollowTarget(m)
    local guide = addon.currentGuide
    if not (guide and guide.steps) then return nil, "no guide" end
    if m.guide ~= guide.name then return nil, "other guide" end
    if m.step < 1 or m.step > #guide.steps then return nil, "bad step" end
    local cur = addon.GetGuideProgress and addon.GetGuideProgress() or 0
    if cur == m.step then return nil, "same step" end
    return m.step
end

-- Only moves when the leader moves, so you can still press Next or Back
-- yourself in between without being pulled straight back
function ps.OnMemberMoved(m)
    if not (ps.Following() and m.name == ps.LeaderName()) then return end
    local target, why = ps.FollowTarget(m)
    if not target then
        if why == "other guide" and ps.lastWarnedGuide ~= m.guide then
            ps.lastWarnedGuide = m.guide
            ps.Print(fmt("%s is on another guide (%s), so you can't follow their steps.", m.name, m.guide))
        end
        return
    end
    if addon.card and addon.card.JumpTo then
        pcall(addon.card.JumpTo, target)
    elseif addon.SetStep then
        pcall(addon.SetStep, target)
    end
end

-- Ticking "Follow" jumps to the leader's step straight away
function ps.SyncToLeader()
    local leader = ps.LeaderName()
    local m = leader and ps.members[leader]
    if not m then
        ps.Print("The party leader isn't using OpenXP (or hasn't synced yet).")
        return
    end
    local target, why = ps.FollowTarget(m)
    if target and addon.card and addon.card.JumpTo then
        pcall(addon.card.JumpTo, target)
    elseif why == "other guide" then
        ps.Print(fmt("%s is on another guide (%s).", m.name, m.guide))
    end
end

---------------------------------------------------------------------------
-- What the party looks like next to my step
---------------------------------------------------------------------------

-- Words for a member's state on one of my quests
function ps.Describe(state)
    if not state then return "?", "grey" end
    local c = state:sub(1, 1)
    if c == "t" then return "turned in", "grey" end
    if c == "c" then return "ready", "green" end
    if c == "p" then
        local prog = state:sub(2)
        return prog ~= "" and prog or "on it", "yellow"
    end
    return "needs quest", "red"
end

-- Where a member is compared to me
function ps.Where(m)
    local guide = addon.currentGuide
    if not guide or m.guide ~= guide.name then return "other guide" end
    local cur = addon.GetGuideProgress and addon.GetGuideProgress() or 0
    local d = m.step - cur
    if d == 0 then return "same step" end
    if d > 0 then return fmt("%d ahead", d) end
    return fmt("%d behind", -d)
end

-- Rows for the panel: one per member, sorted by name
function ps.Rows()
    local mine = ps.StepQuestIds(addon.RXPFrame and addon.RXPFrame.activeSteps or {})
    local names = {}
    for name in pairs(ps.members) do tinsert(names, name) end
    tsort(names)
    local rows = {}
    for _, name in ipairs(names) do
        local m = ps.members[name]
        local quests = {}
        for _, id in ipairs(mine) do
            local text, color = ps.Describe(m.q[id])
            tinsert(quests, {id = id, text = text, color = color, state = m.q[id]})
        end
        tinsert(rows, {
            name = name, class = m.class, level = m.level, where = ps.Where(m),
            stale = Now() - (m.seen or 0) > ps.STALE, quests = quests,
            leader = name == ps.LeaderName(),
        })
    end
    return rows
end

-- Party members who still need a quest on my step (for "Share quest")
function ps.NeedQuest(id)
    local out = {}
    for name, m in pairs(ps.members) do
        if m.q[id] == "m" then tinsert(out, name) end
    end
    tsort(out)
    return out
end

function ps.ShareQuest(id)
    if addon.GetLogIndexForQuestID then
        local index, pushable = addon.GetLogIndexForQuestID(id)
        if index and pushable and QuestLogPushQuest then
            if SelectQuestLogEntry then SelectQuestLogEntry(index) end
            QuestLogPushQuest(index)
            return true
        end
    end
end

---------------------------------------------------------------------------
-- Keeping the member list tidy
---------------------------------------------------------------------------

-- Drop people who left the party
function ps.Prune()
    if not ps.InParty() then
        if next(ps.members) then
            ps.members = {}
            if ps.Redraw then ps.Redraw() end
        end
        return
    end
    local inParty = {}
    for i = 1, (GetNumGroupMembers() or 0) - 1 do
        local name = ShortName(UnitName and UnitName("party" .. i))
        if name then inParty[name] = true end
    end
    local changed
    for name in pairs(ps.members) do
        if not inParty[name] then
            ps.members[name] = nil
            changed = true
        end
    end
    if changed and ps.Redraw then ps.Redraw() end
end

function ps.Print(msg)
    if addon.comms and addon.comms.PrettyPrint then
        addon.comms.PrettyPrint("%s", msg)
    elseif print then
        print("OpenXP: " .. msg)
    end
end

-- /oxp party: what sync sees right now
function ps.Report()
    if not ps.InParty() then return ps.Print("Party sync: you're not in a party.") end
    local rows = ps.Rows()
    if #rows == 0 then return ps.Print("Party sync: nobody else in the party has synced yet.") end
    for _, r in ipairs(rows) do
        local qs = {}
        for _, q in ipairs(r.quests) do tinsert(qs, fmt("%d %s", q.id, q.text)) end
        ps.Print(fmt("%s%s (%d): %s%s%s", r.name, r.leader and " [leader]" or "", r.level or 0, r.where,
                     #qs > 0 and " | " or "", table.concat(qs, ", ")))
    end
end

---------------------------------------------------------------------------
-- The loop: once a second, send if anything changed
---------------------------------------------------------------------------

function ps.Tick()
    if not ps.Enabled() then return end
    ps.Prune()
    if not ps.InParty() then return end
    local status = ps.BuildStatus()
    if ps.Send(status, ps.dirty) then ps.dirty = nil end
    if ps.Redraw then ps.Redraw() end
end

if CreateFrame then
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        local ok, err = pcall(ps.Tick)
        if not ok and addon.comms and addon.comms.PrettyDebug then addon.comms.PrettyDebug("party sync: %s", err) end
    end)
    ticker:RegisterEvent("GROUP_ROSTER_UPDATE")
    ticker:SetScript("OnEvent", function() ps.dirty = true end)
end

---------------------------------------------------------------------------
-- The party panel under the card
---------------------------------------------------------------------------
-- One line per party member who runs OpenXP:
--   Name (lvl)  same step / 3 ahead / other guide
--     quest states for the quests on your step: ready, 4/10, needs quest...
-- "Follow leader" in the panel's header ticks the setting, and "Share" sends
-- your step's quest to whoever still needs it.

local WHITE = "Interface/Buttons/WHITE8X8"
local COLORS = {
    green = "ff3dbb7a", yellow = "fff2c35c", red = "ffff7043", grey = "ff8a8e9b",
}
local ROW_H = 30

local panel

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr or "ffebedf2"
end

local function Colored(color, text) return fmt("|c%s%s|r", color, text) end

local function MakeTextButton(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    b.SetLabel = function(self, label)
        self.text:SetText(label)
        self:SetSize(self.text:GetStringWidth() + 10, 16)
    end
    b:SetLabel(text)
    return b
end

local function BuildPanel()
    local card = addon.card and addon.card.frame
    if not card then return end
    panel = CreateFrame("Frame", "OpenXPPartyPanel", card, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -4)
    panel:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -4)
    panel:SetHeight(40)
    if panel.SetBackdrop then
        panel:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                           insets = {left = 1, right = 1, top = 1, bottom = 1}})
        panel:SetBackdropColor(16 / 255, 17 / 255, 21 / 255, 0.9)
        panel:SetBackdropBorderColor(150 / 255, 160 / 255, 180 / 255, 0.35)
    end

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.title:SetPoint("TOPLEFT", 10, -7)
    panel.title:SetText("PARTY")
    panel.title:SetTextColor(0.62, 0.64, 0.70)

    panel.follow = MakeTextButton(panel, "", function()
        local p = Settings()
        p.partyFollowLeader = not p.partyFollowLeader
        if p.partyFollowLeader then ps.SyncToLeader() end
        ps.Redraw()
    end)
    panel.follow:SetPoint("TOPRIGHT", -6, -4)
    panel.follow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Follow the party leader")
        GameTooltip:AddLine("Your card goes to the leader's step each time they move on.", 1, 1, 1, true)
        GameTooltip:AddLine("You can still press Next or Back in between.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.follow:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel.share = MakeTextButton(panel, "Share quest", function(self)
        if self.questId then ps.ShareQuest(self.questId) end
    end)
    panel.share:SetPoint("RIGHT", panel.follow, "LEFT", -6, 0)
    panel.share:Hide()

    panel.rows = {}
    panel:Hide()
end

local function Row(i)
    local r = panel.rows[i]
    if r then return r end
    r = {}
    r.top = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.top:SetJustifyH("LEFT")
    r.bottom = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.bottom:SetJustifyH("LEFT")
    r.top:SetWordWrap(false)
    r.bottom:SetWordWrap(false)
    r.top:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -24 - (i - 1) * ROW_H)
    r.top:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    r.bottom:SetPoint("TOPLEFT", r.top, "BOTTOMLEFT", 8, -2)
    r.bottom:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    panel.rows[i] = r
    return r
end

local function QuestName(id)
    local name = addon.GetQuestName and addon.GetQuestName(id)
    if type(name) == "string" and name ~= "" then return name end
    return "#" .. id
end

function ps.Redraw()
    if not panel then BuildPanel() end
    if not panel then return end
    local card = addon.card
    local show = ps.Enabled() and ps.InParty() and next(ps.members) ~= nil and card and card.frame and
                     card.frame:IsShown()
    if not show then
        panel:Hide()
        return
    end

    local rows = ps.Rows()
    local p = Settings()
    local isLeader = UnitIsGroupLeader and UnitIsGroupLeader("player")
    panel.follow:SetShown(not isLeader)
    panel.follow:SetLabel(p.partyFollowLeader and "|cff3dbb7aFollowing leader|r" or "Follow leader")

    -- Share: the first quest on my step that someone needs and I can share
    panel.share.questId = nil
    for _, id in ipairs(ps.StepQuestIds(addon.RXPFrame and addon.RXPFrame.activeSteps or {})) do
        if #ps.NeedQuest(id) > 0 and addon.IsOnQuest and addon.IsOnQuest(id) then
            panel.share.questId = id
            break
        end
    end
    panel.share:SetShown(panel.share.questId ~= nil)

    for i, row in ipairs(rows) do
        local r = Row(i)
        local name = Colored(ClassColor(row.class), row.name)
        if row.leader then name = name .. " |cfff2c35c(leader)|r" end
        local where = row.where
        if row.stale then where = where .. ", not heard from lately" end
        r.top:SetText(fmt("%s  |cff9ea3b0lvl %d · %s|r", name, row.level or 0, where))
        local parts = {}
        for _, q in ipairs(row.quests) do
            tinsert(parts, fmt("%s: %s", QuestName(q.id), Colored(COLORS[q.color] or COLORS.grey, q.text)))
        end
        r.bottom:SetText(#parts > 0 and table.concat(parts, "   ") or "|cff8a8e9bno quests on your step|r")
        r.top:Show()
        r.bottom:Show()
    end
    for i = #rows + 1, #panel.rows do
        panel.rows[i].top:Hide()
        panel.rows[i].bottom:Hide()
    end
    panel:SetHeight(24 + #rows * ROW_H + 4)
    panel:Show()
end
