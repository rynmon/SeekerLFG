-- Seeker LFG: the People tab. Forever's group finder has no applications: players who want in
-- whisper the leader. So while you're listed, Seeker keeps the whispers you get in one list, each
-- with what it knows about the sender and Invite, Whisper and Dismiss buttons. The tab's other
-- list is everyone you've grouped with (for a few minutes or more), what for and when, so good
-- players are easy to find again; their cards and tooltips say so too.
local ADDON, ns = ...
local L = ns.L -- translations (Locale.lua)

local INBOX_TTL = 30 * 60     -- a whisper stays on the list for half an hour
local MAX_MESSAGES = 5        -- the last few whispers from each player
local GROUPED_AFTER = 3 * 60  -- in a group together this long before they're remembered
local GROUPED_MAX = 500       -- the oldest are forgotten past this many
local ROW_H = 38

local function Key(name) return ns.LocationKey and ns.LocationKey(name) end

-- A player's text, safe to show: links become their text, colours, textures and icons go, and a
-- lone escape character can't start a new one.
local function CleanText(t)
    t = t:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    t = t:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return (t:gsub("|", "||"))
end

local function InMyGroup(key)
    if not IsInGroup() then return false end
    for _, unit in ipairs(ns.MyGroupUnits()) do
        if UnitExists(unit) and Key(ns.UnitFullName(unit)) == key then return true end
    end
    return false
end

-- "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago".
local function Ago(when)
    local s = math.max(0, time() - (when or 0))
    if s < 120 then return L["just now"] end
    if s < 3600 then return (L["%d min ago"]):format(math.floor(s / 60)) end
    if s < 86400 then return (L["%d h ago"]):format(math.floor(s / 3600)) end
    if s < 2 * 86400 then return L["yesterday"] end
    return (L["%d days ago"]):format(math.floor(s / 86400))
end

local Refresh -- the page, below

---------------------------------------------------------------------------
-- Whispers while you're listed
---------------------------------------------------------------------------
local inbox = {} -- first-name key -> { key, name, classFile, messages = { { text, when } }, when, unread, replied }

local function PruneInbox()
    local now = time()
    for key, w in pairs(inbox) do
        if now - w.when > INBOX_TTL then inbox[key] = nil end
    end
end

-- Newest first.
function ns.InboxList()
    PruneInbox()
    local list = {}
    for _, w in pairs(inbox) do list[#list + 1] = w end
    table.sort(list, function(a, b) return a.when > b.when end)
    return list
end

function ns.InboxUnread()
    local n = 0
    for _, w in pairs(inbox) do if w.unread then n = n + 1 end end
    return n
end

function ns.InboxCount()
    PruneInbox()
    local n = 0
    for _ in pairs(inbox) do n = n + 1 end
    return n
end

function ns.DismissWhisper(key)
    inbox[key] = nil
    Refresh()
end

function ns.ClearInbox()
    wipe(inbox)
    Refresh()
end

local function MarkInboxRead()
    local any = false
    for _, w in pairs(inbox) do
        if w.unread then w.unread = false any = true end
    end
    if any and ns.UpdatePeopleBadge then ns.UpdatePeopleBadge() end
end

local function OnWhisper(text, sender, guid)
    if not (ns.db and ns.db.whisperInbox ~= false and ns.HasListing and ns.HasListing()) then return end
    if type(text) ~= "string" or type(sender) ~= "string" or text == "" then return end
    local key = Key(sender)
    if not key or key == Key(UnitName("player")) or InMyGroup(key) then return end
    local w = inbox[key]
    if not w then
        w = { key = key, messages = {} }
        inbox[key] = w
    end
    w.name = sender
    w.when = time()
    w.unread = true
    w.replied = false
    w.messages[#w.messages + 1] = { text = CleanText(text), when = time() }
    while #w.messages > MAX_MESSAGES do table.remove(w.messages, 1) end
    if guid and GetPlayerInfoByGUID then
        local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
        if ok and classFile then w.classFile = classFile end
    end
    Refresh()
end

local function OnWhisperSent(target)
    local w = type(target) == "string" and inbox[Key(target) or ""]
    if w then
        w.replied = true
        Refresh()
    end
end

---------------------------------------------------------------------------
-- Players you've grouped with
---------------------------------------------------------------------------
-- Remembered once they've been in your group for a few minutes (a quick invite and leave isn't
-- a run), with what the group was for: the dungeon or raid you went into together, else what
-- the group was listed for. Account-wide, like your notes.
local together = {}    -- key -> { since, name, classFile, level, counted } for this group
local groupWhat        -- the instance this group went into
local groupListedFor   -- what this group was listed for (kept after it delists)

local function PruneGrouped()
    local db = ns.db.grouped
    local keys = {}
    for key in pairs(db) do keys[#keys + 1] = key end
    if #keys <= GROUPED_MAX then return end
    table.sort(keys, function(a, b) return (db[a].time or 0) > (db[b].time or 0) end)
    for i = GROUPED_MAX + 1, #keys do db[keys[i]] = nil end
end

local function Commit(key, t)
    local db = ns.db.grouped
    local g = db[key]
    if not g then
        g = { count = 0 }
        db[key] = g
    end
    g.name = t.name
    g.classFile = t.classFile or g.classFile
    g.level = t.level or g.level
    g.time = time()
    local what = groupWhat or groupListedFor
    if what then g.what = what end
    if not t.counted then
        t.counted = true
        g.count = (g.count or 0) + 1
        PruneGrouped()
    end
end

local function ScanGroup()
    if not ns.db then return end
    if not IsInGroup() then
        wipe(together)
        groupWhat, groupListedFor = nil, nil
        return
    end
    local inInstance, kind = IsInInstance()
    if inInstance and (kind == "party" or kind == "raid") then
        local name = GetInstanceInfo()
        if type(name) == "string" and name ~= "" then groupWhat = name end
    end
    local listing = ns.HasListing() and ns.GetListing()
    if listing and #listing.activityIDs == 1 then groupListedFor = ns.GetActivityName(listing.activityIDs[1]) end

    local now, present = GetTime(), {}
    local me = Key(UnitName("player"))
    for _, unit in ipairs(ns.MyGroupUnits()) do
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local name = ns.UnitFullName(unit)
            local key = Key(name)
            if key and key ~= me and name ~= UNKNOWNOBJECT then
                present[key] = true
                local t = together[key]
                if not t then
                    t = { since = now }
                    together[key] = t
                end
                t.name = name
                local _, classFile = UnitClass(unit)
                t.classFile = classFile or t.classFile
                local level = UnitLevel(unit)
                if level and level > 0 then t.level = level end
                if now - t.since >= GROUPED_AFTER then Commit(key, t) end
            end
        end
    end
    for key in pairs(together) do
        if not present[key] then together[key] = nil end
    end
end

function ns.GroupedWith(name)
    local key = Key(name)
    return key and ns.db and ns.db.grouped[key] or nil
end

function ns.ForgetGrouped(key)
    ns.db.grouped[key] = nil
    Refresh()
    if ns.QueueRender then ns.QueueRender() end
end

-- "Grouped with you: Dire Maul, 2 days ago (3 times)", or nil.
function ns.GroupedText(name)
    local g = ns.GroupedWith(name)
    if not g then return nil end
    local text = L["Grouped with you: "] .. (g.what and (g.what .. ", ") or "") .. Ago(g.time)
    if (g.count or 1) > 1 then text = text .. (L[" (%d times)"]):format(g.count) end
    return text
end

-- The marker on cards: the game's group icon, or a word.
function ns.GroupedIcon(size)
    size = size or 12
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("socialqueuing-icon-group") then
        return ("|A:socialqueuing-icon-group:%d:%d|a"):format(size, size)
    end
    return "|cffb4a0ff" .. L["grouped"] .. "|r"
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "GROUP_ROSTER_UPDATE",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_LOGIN" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event, a1, a2, ...)
        if event == "CHAT_MSG_WHISPER" then
            local guid = select(10, ...) -- the event's 12th argument
            pcall(OnWhisper, a1, a2, guid)
        elseif event == "CHAT_MSG_WHISPER_INFORM" then
            pcall(OnWhisperSent, a2)
        else
            if event == "PLAYER_LOGIN" then
                C_Timer.NewTicker(30, function() pcall(ScanGroup) end)
            end
            pcall(ScanGroup)
            -- Whoever just joined your group is done with: their whisper comes off the list.
            if event == "GROUP_ROSTER_UPDATE" and next(inbox) then
                local changed = false
                for key in pairs(inbox) do
                    if InMyGroup(key) then inbox[key] = nil changed = true end
                end
                if changed then Refresh() end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local page, U
local rows, data, scroll = {}, {}, 0
local view = "whispers" -- or "grouped"

local function Listed(key) return ns.listedNow and ns.listedNow[key] end

-- What Seeker knows about a player: level, class file, zone (and how old), roles, and their
-- listing if they have one right now.
local function Known(key, name, classFile, level)
    local k = {}
    local e = Listed(key)
    local known = ns.GetKnownPlayer and ns.GetKnownPlayer(name)
    k.listing = e
    local p = e and e.leader
    k.classFile = (p and p.classFilename) or classFile or (known and known.classFile)
    k.level = (p and p.level) or (e and e.maxLevel) or level or (known and known.level)
    if p and p.areaName and p.areaName ~= "" then
        k.zone = p.areaName
    else
        k.zone, k.zoneAge = ns.GetKnownLocation(name)
    end
    if e and e.isSolo then k.roles = e.roles end
    return k
end

local function RoleIcons(roles)
    if not roles then return "" end
    local s = ""
    for _, key in ipairs(U.ROLE_KEYS) do
        if roles[key] then s = s .. U.RoleMarkup(key, 14) end
    end
    return s
end

-- Line 1 after the name: level, roles and where they are.
local function DetailsText(k, name)
    local bits = {}
    bits[#bits + 1] = "|cffb0b0b0" .. (LEVEL_ABBR or L["Lv"]) .. " " .. (k.level and tostring(k.level) or "?") .. "|r"
    local roles = RoleIcons(k.roles)
    if roles ~= "" then bits[#bits + 1] = roles end
    if k.zone then
        bits[#bits + 1] = "|cffd0d0d0" .. k.zone .. "|r"
    else
        local state = ns.LocateState and ns.LocateState(name)
        if state == "looking" or state == "queued" then
            bits[#bits + 1] = "|cffffd100" .. L["looking up..."] .. "|r"
        elseif state == "notfound" then
            bits[#bits + 1] = "|cff808080" .. L["not found (offline?)"] .. "|r"
        end
    end
    if k.listing then bits[#bits + 1] = "|cff55ff55" .. L["listed now"] .. "|r" end
    if ns.GetNote and ns.GetNote(name) then bits[#bits + 1] = ns.NoteIcon(12) end
    return table.concat(bits, "  ")
end

local function CanLocate(name, k)
    return not k.zone and not (ns.LocateState and ns.LocateState(name))
end

local function Locate(name)
    if not (ns.QueueLocate and ns.PumpLocate) then return end
    ns.QueueLocate({ { name = name } }, true)
    ns.PumpLocate(true) -- this click is the input the lookup needs
    Refresh()
end

local function ShowTooltip(row)
    local item = row.item
    if not item then return end
    U.AnchorBesideWindow(row, false)
    local name = item.name
    local k = Known(item.key, name, item.classFile, item.level)
    local r, g, b = U.ClassColor(k.classFile)
    GameTooltip:AddDoubleLine(U.ShortName(name) or name, (LEVEL_ABBR or L["Lv"]) .. " " .. (k.level and tostring(k.level) or "?"),
        r, g, b, 1, 1, 1)
    if k.classFile then GameTooltip:AddLine(U.ClassName(k.classFile), r, g, b) end
    GameTooltip:AddLine("|cffffd100" .. L["Where:"] .. "|r " .. (k.zone or ("|cff808080" .. L["unknown"] .. "|r")), 1, 1, 1, true)
    if k.roles and RoleIcons(k.roles) ~= "" then
        local named = {}
        for _, key in ipairs(U.ROLE_KEYS) do
            if k.roles[key] then named[#named + 1] = U.RoleMarkup(key, 14) .. " " .. U.ROLE_NAMES[key] end
        end
        GameTooltip:AddLine("|cffffd100" .. L["Roles:"] .. "|r " .. table.concat(named, "   "), 1, 1, 1)
    end
    if k.listing then
        local e = k.listing
        local first = e.activityIDs and e.activityIDs[1]
        local what = first and ns.GetActivityName(first) or "?"
        if e.activityIDs and #e.activityIDs > 1 then what = what .. (" +%d"):format(#e.activityIDs - 1) end
        GameTooltip:AddLine("|cffffd100" .. L["Listed for:"] .. "|r " .. what, 1, 1, 1, true)
    end
    if item.kind == "whisper" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Their whispers:"], 1, 0.82, 0)
        for _, m in ipairs(item.messages) do
            GameTooltip:AddLine("|cff808080" .. Ago(m.when) .. ":|r " .. m.text, 1, 0.5, 1, true)
        end
        if item.replied then GameTooltip:AddLine(L["You've replied."], 0.33, 1, 0.33) end
        local grouped = ns.GroupedText(name)
        if grouped then GameTooltip:AddLine(grouped, 0.7, 0.63, 1, true) end
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.GroupedText(name) or "", 0.7, 0.63, 1, true)
    end
    local note = ns.GetNote and ns.GetNote(name)
    if note then GameTooltip:AddLine(ns.NoteIcon(14) .. " |cffffd100" .. L["Your note:"] .. "|r " .. note, 1, 1, 1, true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Right-click for more options."], 0.5, 0.5, 0.5)
    GameTooltip:Show()
    if U.MakeTooltipSolid then U.MakeTooltipSolid() end
end

local function RowMenu(row)
    local item = row.item
    if not (item and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local name = item.name
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(U.ShortName(name) or name)
        root:CreateButton(SEND_MESSAGE or L["Whisper"], function() ns.Whisper(name) end)
        local invite = root:CreateButton(PARTY_INVITE or L["Invite"], function() ns.Invite(name, true) end)
        invite:SetEnabled(ns.InviteBlocker() == nil)
        root:CreateButton(ns.GetNote(name) and L["Edit note..."] or L["Add a note..."], function() ns.EditNote(name) end)
        root:CreateDivider()
        if item.kind == "whisper" then
            root:CreateButton(L["Dismiss"], function() ns.DismissWhisper(item.key) end)
        else
            root:CreateButton(L["Forget"], function() ns.ForgetGrouped(item.key) end)
        end
    end)
end

local function MakeRow(area, i)
    local row = CreateFrame("Button", nil, area)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -10, -(i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if i % 2 == 1 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if U.HasAtlas("UI-Character-Info-Line-Bounce") then
            bg:SetAtlas("UI-Character-Info-Line-Bounce")
            bg:SetAlpha(0.3)
        else
            bg:SetColorTexture(1, 1, 1, 0.04)
        end
    end
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = U.Text(row, "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 40, -5)
    row.name:SetWordWrap(false)
    row.details = U.Text(row, "GameFontHighlightSmall")
    row.details:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.details:SetJustifyH("LEFT")
    row.details:SetWordWrap(false)
    row.line2 = U.Text(row, "GameFontHighlightSmall")
    row.line2:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.line2:SetJustifyH("LEFT")
    row.line2:SetWordWrap(false)

    -- Right to left: dismiss (or forget), invite, whisper, note, find.
    row.dismiss = U.IconButton(row, "Interface\\Buttons\\UI-StopButton", 16, L["Dismiss"], function()
        if not row.item then return end
        if row.item.kind == "whisper" then ns.DismissWhisper(row.item.key) else ns.ForgetGrouped(row.item.key) end
    end)
    row.dismiss:SetPoint("RIGHT", -10, 0)
    row.dismiss:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if row.item and row.item.kind == "grouped" then
            GameTooltip:SetText(L["Forget"], 1, 1, 1)
            GameTooltip:AddLine(L["Take them off this list. Grouping with them again adds them back."], nil, nil, nil, true)
        else
            GameTooltip:SetText(L["Dismiss"], 1, 1, 1)
        end
        GameTooltip:Show()
    end)

    local SQUARE, ICON = "common-button-tertiary-square-normal", "friends-icon-friendsInGroup"
    if U.HasAtlas(SQUARE) and U.HasAtlas(ICON) then
        local b = CreateFrame("Button", nil, row)
        b:SetSize(22, 22)
        b:SetNormalAtlas(SQUARE)
        if U.HasAtlas("common-button-tertiary-square-pressed") then b:SetPushedAtlas("common-button-tertiary-square-pressed") end
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.Icon = b:CreateTexture(nil, "OVERLAY")
        b.Icon:SetAtlas(ICON)
        b.Icon:SetSize(16, 16)
        b.Icon:SetPoint("CENTER", 0, 1)
        row.invite = b
    else
        row.invite = U.RedButton(row, INVITE or L["Invite"], 60, 20, true)
    end
    row.invite:SetPoint("RIGHT", row.dismiss, "LEFT", -10, 0)
    row.invite:SetMotionScriptsWhileDisabled(true)
    row.invite:SetScript("OnClick", function()
        if not row.item then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.Invite(row.item.name, true)
    end)
    row.invite:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(INVITE or L["Invite"], 1, 1, 1)
        local blocker = ns.InviteBlocker()
        if blocker then GameTooltip:AddLine(blocker, 1, 0.3, 0.3, true) end
        GameTooltip:Show()
    end)
    row.invite:SetScript("OnLeave", GameTooltip_Hide)

    row.whisper = U.IconButton(row, "Interface\\GossipFrame\\GossipGossipIcon", 18, L["Whisper"], function()
        if row.item then ns.Whisper(row.item.name) end
    end)
    row.whisper:SetPoint("RIGHT", row.invite, "LEFT", -8, 0)
    row.note = U.IconButton(row, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", 18, L["Your note on them"], function()
        if row.item then ns.EditNote(row.item.name) end
    end)
    row.note:SetPoint("RIGHT", row.whisper, "LEFT", -8, 0)
    row.locate = U.IconButton(row, "Interface\\Icons\\INV_Misc_Map_01", 18, L["Find where they are"], function()
        if row.item then Locate(row.item.name) end
    end)
    row.locate:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.locate:SetPoint("RIGHT", row.note, "LEFT", -8, 0)
    row.locate.seekerPump = true

    row.line2:SetPoint("RIGHT", row.locate, "LEFT", -10, 0)
    row.details:SetPoint("RIGHT", row.locate, "LEFT", -10, 0)

    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then RowMenu(self) end
    end)
    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function SetIcon(tex, classFile)
    if not classFile then
        tex:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        tex:SetVertexColor(0.25, 0.25, 0.25, 0.8)
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end
    tex:SetVertexColor(1, 1, 1, 1)
    local atlas = "groupfinder-icon-class-" .. classFile:lower()
    if U.HasAtlas(atlas) then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(atlas)
    else
        U.SetClassIcon(tex, classFile)
    end
end

local function Collect()
    wipe(data)
    if view == "whispers" then
        for _, w in ipairs(ns.InboxList()) do
            w.kind = "whisper"
            data[#data + 1] = w
        end
    else
        local filter = page.search and strtrim(page.search:GetText() or ""):lower() or ""
        for key, g in pairs(ns.db.grouped) do
            local hay = ((g.name or key) .. " " .. (g.what or "")):lower()
            if filter == "" or hay:find(filter, 1, true) then
                data[#data + 1] = { kind = "grouped", key = key, name = g.name or key, classFile = g.classFile,
                    level = g.level, what = g.what, when = g.time or 0, count = g.count or 1 }
            end
        end
        table.sort(data, function(a, b) return a.when > b.when end)
    end
end

local function Render()
    if not page or not page:IsShown() then return end
    Collect()
    local area = page.area
    local visible = math.max(1, math.floor(area:GetHeight() / ROW_H))
    local maxScroll = math.max(0, #data - visible)
    if scroll > maxScroll then scroll = maxScroll end
    area.scrollbar:SetMinMaxValues(0, maxScroll)
    area.scrollbar:SetValue(scroll)
    area.scrollbar:SetShown(maxScroll > 0)
    local canInvite = ns.InviteBlocker() == nil
    for i = 1, visible do
        local row = rows[i] or MakeRow(area, i)
        rows[i] = row
        local item = data[scroll + i]
        row.item = item
        if item then
            local k = Known(item.key, item.name, item.classFile, item.level)
            SetIcon(row.icon, k.classFile)
            row.name:SetText(U.ShortName(item.name) or item.name)
            row.name:SetTextColor(U.ClassColor(k.classFile))
            row.details:SetText(DetailsText(k, item.name))
            if item.kind == "whisper" then
                local last = item.messages[#item.messages]
                local lead = item.replied and ("|cff55ff55" .. L["replied"] .. "|r  ") or (item.unread and ("|cffffd100" .. L["new"] .. "|r  ") or "")
                local more = #item.messages > 1 and ("|cff808080 (+%d)|r"):format(#item.messages - 1) or ""
                row.line2:SetText(lead .. "|cff808080" .. Ago(item.when) .. "|r  |cffff80ff" .. (last and last.text or "") .. "|r" .. more)
            else
                local bits = { item.what or L["Grouped"], Ago(item.when) }
                if item.count > 1 then bits[#bits + 1] = (L["%d times"]):format(item.count) end
                local note = ns.GetNote and ns.GetNote(item.name)
                local text = "|cffd0d0d0" .. table.concat(bits, "  ·  ") .. "|r"
                if note then text = text .. "  |cff808080\"" .. note .. "\"|r" end
                row.line2:SetText(text)
            end
            row.invite:SetEnabled(canInvite)
            if row.invite.Icon then row.invite.Icon:SetDesaturated(not canInvite) end
            row.locate:SetShown(CanLocate(item.name, k))
            row:Show()
        else
            row:Hide()
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end

    -- The empty list says what goes in it.
    if #data == 0 then
        if view == "whispers" then
            page.empty:SetText(ns.HasListing() and L["No whispers yet. Whispers you get while you're listed show up here, with Invite buttons."]
                or L["You're not listed. List yourself or your group, and whispers you get while listed show up here."])
        elseif page.search and strtrim(page.search:GetText() or "") ~= "" then
            page.empty:SetText(L["Nobody you've grouped with matches that."])
        else
            page.empty:SetText(L["Players you're in a group with for a few minutes are remembered here, with what you ran together."])
        end
    end
    page.empty:SetShown(#data == 0)

    local nWhispers = ns.InboxCount()
    page.whispersTab.text:SetText(nWhispers > 0 and (L["Whispers (%d)"]):format(nWhispers) or L["Whispers"])
    page.clear:SetShown(view == "whispers" and nWhispers > 0)
    if page.search then page.search:SetShown(view == "grouped") end
    if view == "whispers" then
        page.totals:SetText(ns.HasListing() and L["Listed: collecting whispers"] or L["Not listed"])
    else
        local n = 0
        for _ in pairs(ns.db.grouped) do n = n + 1 end
        page.totals:SetText((L["%d players remembered"]):format(n))
    end
    if view == "whispers" then MarkInboxRead() end
end

Refresh = function()
    if ns.UpdatePeopleBadge then ns.UpdatePeopleBadge() end
    if ns.RefreshListingPage then ns.RefreshListingPage() end -- its "N whispers" note
    if page and page:IsShown() then Render() end
end

function ns.ShowPeople(which)
    if which then view = which end
    ns.Show("people")
    Refresh()
end

function ns.BuildPeoplePage(f, p)
    page = p
    U = ns.UI

    local title = U.Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 72, -34)
    title:SetText(L["People"])

    local function SetView(v)
        view = v
        scroll = 0
        Render()
    end
    page.whispersTab = U.Chip(page, 130, 24, L["Whispers"], nil, function() return view == "whispers" end,
        function() SetView("whispers") end, L["Whispers"],
        L["Whispers you get while you're listed, newest first, with what Seeker knows about each player. Forever's group finder has no applications: players ask to join by whisper."])
    page.whispersTab:SetPoint("LEFT", title, "RIGHT", 18, -1)
    page.groupedTab = U.Chip(page, 130, 24, L["Grouped with"], nil, function() return view == "grouped" end,
        function() SetView("grouped") end, L["Grouped with"],
        L["Everyone you've been in a group with for a few minutes, with what you ran and when. Their cards and tooltips say so too."])
    page.groupedTab:SetPoint("LEFT", page.whispersTab, "RIGHT", 6, 0)

    local search = U.TryCreate("EditBox", "SeekerLFGPeopleSearch", page, "SearchBoxTemplate")
        or CreateFrame("EditBox", "SeekerLFGPeopleSearch", page, "InputBoxTemplate")
    search:SetSize(200, 24)
    search:SetAutoFocus(false)
    search:SetPoint("LEFT", page.groupedTab, "RIGHT", 16, 0)
    if search.Instructions then search.Instructions:SetText(L["Name or dungeon"]) end
    search:HookScript("OnTextChanged", function() scroll = 0 Render() end)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    page.search = search

    local inset = U.Inset(page)
    inset:SetPoint("TOPLEFT", 4, -62)
    inset:SetPoint("BOTTOMRIGHT", -6, 30)

    local area = CreateFrame("Frame", nil, inset)
    area:SetPoint("TOPLEFT", 6, -6)
    area:SetPoint("BOTTOMRIGHT", -6, 6)
    page.area = area
    local sb = CreateFrame("Slider", nil, area)
    sb:SetOrientation("VERTICAL")
    sb:SetPoint("TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", 0, 0)
    sb:SetWidth(6)
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.35)
    local thumb = sb:CreateTexture(nil, "OVERLAY")
    if U.HasAtlas("minimal-scrollbar-small-thumb-middle") then thumb:SetAtlas("minimal-scrollbar-small-thumb-middle")
    else thumb:SetColorTexture(1, 0.82, 0, 0.6) end
    thumb:SetSize(6, 40)
    sb:SetThumbTexture(thumb)
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    sb:SetMinMaxValues(0, 0)
    sb:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if v ~= scroll then scroll = v Render() end
    end)
    area.scrollbar = sb
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() then ns.StepScale(delta) else sb:SetValue(scroll - delta * 3) end
    end)
    area:SetScript("OnSizeChanged", Render)

    page.empty = U.Text(area, "GameFontDisable")
    page.empty:SetPoint("TOP", 0, -50)
    page.empty:SetWidth(460)

    page.totals = U.Text(page, "GameFontNormalSmall")
    page.totals:SetPoint("BOTTOMLEFT", 14, 10)

    page.clear = U.RedButton(page, L["Clear all"], 100, 22)
    page.clear:SetPoint("BOTTOMRIGHT", -24, 5)
    page.clear:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.ClearInbox()
    end)

    local hint = U.Text(page, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOM", 0, 10)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText(L["Right-click a player for more options"])

    -- Lookups answered, notes changed, who's listed: keep the rows current while the page is open.
    local ev = CreateFrame("Frame", nil, page)
    for _, e in ipairs({ "WHO_LIST_UPDATE", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function() C_Timer.After(0.1, Render) end)
    page:SetScript("OnShow", function()
        page.whispersTab:UpdateLook()
        page.groupedTab:UpdateLook()
        Render()
    end)
    page.Render = Render
end
