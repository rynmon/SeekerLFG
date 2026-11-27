-- Seeker LFG: the people side. Who you've asked to join and who you've invited (and how they
-- answered), your notes on players, "Fill my group" for leaders, and the first-run message.
local ADDON, ns = ...
local L = ns.L -- translations (Locale.lua)

---------------------------------------------------------------------------
-- Requests and invites
---------------------------------------------------------------------------
-- For this session: whom you've asked to join (Request to join) or invited, and what came of it.
-- Cards show it ("Requested 2m ago", "Declined"), so you don't ask twice and can see whom you're
-- waiting on. Kept for a while, then forgotten.
local CONTACT_TTL = 20 * 60
local contacts = {} -- first-name key -> { state, time, name }

local STATES = {
    requested = { color = "|cffffd100", text = L["Requested %s ago"] },
    invited = { color = "|cffffd100", text = L["Invited %s ago"] },
    replied = { color = "|cff55ff55", text = L["Replied %s ago"] },
    declined = { color = "|cffff5555", text = L["Declined %s ago"] },
    busy = { color = "|cffff9933", text = L["Already in a group (%s ago)"] },
    joined = { color = "|cff55ff55", text = L["Joined your group %s ago"] },
}

local function Key(name) return ns.LocationKey and ns.LocationKey(name) end

local function Age(sec)
    if sec < 60 then return math.floor(sec) .. "s" end
    if sec < 3600 then return math.floor(sec / 60) .. "m" end
    return math.floor(sec / 3600) .. "h"
end

function ns.MarkContact(name, state)
    local key = Key(name)
    if not key or not STATES[state] then return end
    contacts[key] = { state = state, time = GetTime(), name = name }
    if ns.QueueRender then ns.QueueRender() end
end

-- state, seconds since, or nil.
function ns.ContactState(name)
    local c = contacts[Key(name) or ""]
    if not c then return nil end
    local age = GetTime() - c.time
    if age > CONTACT_TTL then return nil end
    return c.state, age
end

-- "Requested 2m ago", coloured, or "".
function ns.ContactText(name)
    local state, age = ns.ContactState(name)
    if not state then return "" end
    local s = STATES[state]
    return s.color .. s.text:format(Age(age)) .. "|r"
end

-- A game message with a %s in it, as a pattern that captures the %s (a name).
local function FormatToPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
    return "^" .. p .. "$"
end

-- A name out of a system message, without any player link around it.
local function CleanName(name)
    name = name:gsub("|H.-|h", ""):gsub("|h", ""):gsub("[%[%]]", "")
    return name
end

do
    local SYSTEM = {
        { ERR_DECLINE_GROUP_S, "declined" },
        { ERR_ALREADY_IN_GROUP_S, "busy" },
        { ERR_JOINED_GROUP_S, "joined" },
        { ERR_RAID_MEMBER_ADDED_S, "joined" },
    }
    local patterns = {}
    for _, s in ipairs(SYSTEM) do
        local p = FormatToPattern(s[1])
        if p then patterns[#patterns + 1] = { p, s[2] } end
    end

    local wasInGroup = false
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("CHAT_MSG_SYSTEM")
    ev:RegisterEvent("CHAT_MSG_WHISPER")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event, text, sender)
        if event == "CHAT_MSG_SYSTEM" and type(text) == "string" then
            for _, p in ipairs(patterns) do
                local name = text:match(p[1])
                if name then
                    name = CleanName(name)
                    -- Only people you asked or invited (declines and joins of anyone else are noise).
                    if ns.ContactState(name) or p[2] == "joined" then ns.MarkContact(name, p[2]) end
                    return
                end
            end
        elseif event == "CHAT_MSG_WHISPER" and sender then
            local state = ns.ContactState(sender)
            if state == "requested" or state == "invited" then ns.MarkContact(sender, "replied") end
        else
            -- You've just joined a group: the requests you sent are done with.
            local inGroup = IsInGroup()
            if inGroup and not wasInGroup and event == "GROUP_ROSTER_UPDATE" then
                for key, c in pairs(contacts) do
                    if c.state == "requested" or c.state == "replied" then contacts[key] = nil end
                end
                if ns.QueueRender then ns.QueueRender() end
            end
            wasInGroup = inGroup
        end
    end)
end

---------------------------------------------------------------------------
-- Notes on players
---------------------------------------------------------------------------
-- A line you keep about a player ("great tank"), on their cards and tooltips. Account-wide.
local NOTE_MAX = 120

function ns.GetNote(name)
    local n = ns.db.notes[Key(name) or ""]
    return n and n.text
end

function ns.SetNote(name, text)
    local key = Key(name)
    if not key then return end
    text = text and strtrim(text) or ""
    if text == "" then
        ns.db.notes[key] = nil
    else
        ns.db.notes[key] = { text = text:sub(1, NOTE_MAX), name = name, time = time() }
    end
    if ns.QueueRender then ns.QueueRender() end
end

-- The note marker for a card: a small note icon.
function ns.NoteIcon(size)
    size = size or 12
    return ("|TInterface\\Buttons\\UI-GuildButton-PublicNote-Up:%d:%d|t"):format(size, size)
end

StaticPopupDialogs.SEEKERLFG_NOTE = {
    text = L["Your note on %s (empty removes it):"],
    button1 = ACCEPT or OKAY or "OK",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1,
    maxLetters = NOTE_MAX,
    editBoxWidth = 260,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        if eb then
            eb:SetText(ns.GetNote(data) or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        if eb then ns.SetNote(data, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        ns.SetNote(popup.data, self:GetText())
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function ns.EditNote(name)
    if not name or not StaticPopup_Show then return end
    local short = ns.ShortName and ns.ShortName(name) or name
    StaticPopup_Show("SEEKERLFG_NOTE", short, nil, name)
end

---------------------------------------------------------------------------
-- Fill my group
---------------------------------------------------------------------------
-- For leaders: show the players who play a role your group is missing, with full XP for it, in
-- your listing's activities when you're listed. A dungeon party wants one tank, one healer and
-- three DPS; roles come from the group's assigned roles (a Role check sets them).
function ns.FillMyGroup()
    local blocker = ns.InviteBlocker and ns.InviteBlocker()
    if blocker then ns.Print(blocker) return end
    local units = ns.MyGroupUnits()
    local inRaid = IsInRaid and IsInRaid()
    if not inRaid and #units >= 5 then
        ns.Print(L["Your party is full."])
        return
    end
    local need, unassigned = ns.MyGroupNeeds()
    need = need or { tank = true, healer = true, dps = true } -- alone: anyone
    if not (need.tank or need.healer or need.dps) then need.dps = true end

    local F = ns.db.filters
    for k in pairs(F.playerRoles) do F.playerRoles[k] = need[k] and true or false end
    F.xpMode = "strict"
    F.includeSelf = true
    wipe(F.classes)
    if ns.HasListing() then ns.db.searchSelf = true end
    if ns.RefreshFilterPanel then ns.RefreshFilterPanel() end
    if ns.Show then ns.Show("browse") end
    if ns.ShowTab then ns.ShowTab("browse") end
    if ns.RefreshDropdowns then ns.RefreshDropdowns() end
    if ns.RequestSearch then ns.RequestSearch() end

    local wanted = {}
    if need.tank then wanted[#wanted + 1] = TANK or L["Tank"] end
    if need.healer then wanted[#wanted + 1] = HEALER or L["Healer"] end
    if need.dps then wanted[#wanted + 1] = DAMAGER or L["DPS"] end
    ns.Print((L["Showing players who can play %s, with full XP for your group. Click in the window to search."]):format(table.concat(wanted, " / ")))
    if unassigned and IsInGroup() then
        ns.Print(L["Not everyone has a role: a Role check (List yourself page) makes this more accurate."])
    end
end

---------------------------------------------------------------------------
-- First run
---------------------------------------------------------------------------
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        C_Timer.After(6, function()
            if not ns.db or ns.db.welcomed then return end
            ns.db.welcomed = true
            ns.Print(L["Thanks for installing! Type |cffffd100/seeker|r or click the minimap eye to open it."])
            ns.Print(L["To use it instead of the game's Looking for Group window, turn on |cffffd100Replace the game's window|r in the cog menu. |cffffd100/seeker help|r lists every command."])
        end)
    end)
end
