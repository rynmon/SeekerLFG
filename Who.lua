-- Seeker: the Who page. Mirrors the third tab of Forever's own group finder
-- (Blizzard_GroupFinder_VanillaStyle/Mainline/WhoList.lua): a /who search with class, race and
-- zone filters and sorting, an invite button per player, and the game's player menu on right-click.
local ADDON, ns = ...
local L = ns.L -- translations (Locale.lua)

local MAX_FROM_SERVER = 50
local ROW_H = 20

-- Filters and sort, kept in the saved variables (ns.db.who) once the page is built.
local W = {
    classesFiltered = {}, -- classID -> true: left out
    racesFiltered = {},   -- raceID -> true: left out
    mapsIncluded = {},    -- uiMapID -> true: only these zones
    sortMode = "name",
    ascending = true,
}
ns.Who = W

local page, U, rows, data, scroll = nil, nil, {}, {}, 0

local function Filters()
    local f = { classIDs = {}, raceIDs = {}, uiMapIDs = {} }
    for id in pairs(W.classesFiltered) do f.classIDs[#f.classIDs + 1] = id end
    for id in pairs(W.racesFiltered) do f.raceIDs[#f.raceIDs + 1] = id end
    for id in pairs(W.mapsIncluded) do f.uiMapIDs[#f.uiMapIDs + 1] = id end
    return f
end

function ns.IsWhoPageShown()
    return page and page:IsShown() or false
end

function ns.KeepWhoInUI()
    if page and page:IsShown() and C_FriendList and C_FriendList.SetWhoToUi then
        C_FriendList.SetWhoToUi(true)
    end
end

local function SendWho(text)
    if not (C_FriendList and C_FriendList.SendWho) then return end
    -- A member lookup still waiting for its answer gives way: this search's answer is yours.
    if ns.EndQuietLookup and ns.silentWhoUntil then ns.EndQuietLookup() end
    ns.KeepWhoInUI()
    -- The game shows /who results in its own window; for the next few seconds, they come to ours.
    ns.whoUntil = GetTime() + 8
    local origin = Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
    local ok = pcall(C_FriendList.SendWho, text or "", origin, Filters())
    if not ok then pcall(C_FriendList.SendWho, text or "") end
    page.totals:SetText(SEARCHING or L["Searching..."])
end

---------------------------------------------------------------------------
-- Filter menu (class, race, zone, sort), as the game's
---------------------------------------------------------------------------
local function TopMapID()
    if not (C_Map and MapUtil and MapUtil.GetMapParentInfo) then return end
    local current = C_Map.GetBestMapForUnit("player") or (C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID())
    if not current then return end
    local top = MapUtil.GetMapParentInfo(current, Enum.UIMapType.World, true)
    return top and top.mapID
end

local function Selectable(mapID)
    return not C_Map.IsMapValidForNavBarDropdown or C_Map.IsMapValidForNavBarDropdown(mapID)
end

local function HasSelectableChildren(mapID)
    for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
        if Selectable(child.mapID) then return true end
    end
    return false
end

local function SetAllMaps(include)
    local function Walk(mapID)
        if HasSelectableChildren(mapID) then
            for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
                if Selectable(child.mapID) then Walk(child.mapID) end
            end
        else
            W.mapsIncluded[mapID] = include or nil
        end
    end
    local top = TopMapID()
    if top then Walk(top) end
    return MenuResponse and MenuResponse.Refresh
end

local function BuildFilterMenu(root)
    -- Class
    local classMenu = root:CreateButton(CLASS or L["Class"])
    classMenu:CreateButton(CHECK_ALL or L["Check all"], function()
        wipe(W.classesFiltered)
        return MenuResponse and MenuResponse.Refresh
    end)
    classMenu:CreateButton(UNCHECK_ALL or L["Uncheck all"], function()
        for i = 1, (GetNumClasses and GetNumClasses() or 0) do
            local _, _, id = GetClassInfo(i)
            if id then W.classesFiltered[id] = true end
        end
        return MenuResponse and MenuResponse.Refresh
    end)
    local classes = {}
    local ids = C_SpecializationInfo and C_SpecializationInfo.GetAllClassIDs and C_SpecializationInfo.GetAllClassIDs()
    if ids then
        for _, id in ipairs(ids) do
            local name = GetClassInfo(id)
            if name then classes[#classes + 1] = { id = id, name = name } end
        end
    else
        for i = 1, (GetNumClasses and GetNumClasses() or 0) do
            local name, _, id = GetClassInfo(i)
            if name then classes[#classes + 1] = { id = id, name = name } end
        end
    end
    table.sort(classes, function(a, b) return a.name < b.name end)
    for _, c in ipairs(classes) do
        classMenu:CreateCheckbox(c.name, function() return not W.classesFiltered[c.id] end, function()
            W.classesFiltered[c.id] = not W.classesFiltered[c.id] or nil
        end)
    end

    -- Race
    if C_FriendList.GetWhoRaceFilters then
        local raceMenu = root:CreateButton(RACE or L["Race"])
        local races = C_FriendList.GetWhoRaceFilters() or {}
        raceMenu:CreateButton(CHECK_ALL or L["Check all"], function()
            wipe(W.racesFiltered)
            return MenuResponse and MenuResponse.Refresh
        end)
        raceMenu:CreateButton(UNCHECK_ALL or L["Uncheck all"], function()
            for _, r in ipairs(races) do if r.ID then W.racesFiltered[r.ID] = true end end
            return MenuResponse and MenuResponse.Refresh
        end)
        table.sort(races, function(a, b) return (a.name or "") < (b.name or "") end)
        for _, r in ipairs(races) do
            raceMenu:CreateCheckbox(r.name, function() return not W.racesFiltered[r.ID] end, function()
                W.racesFiltered[r.ID] = not W.racesFiltered[r.ID] or nil
            end)
        end
    end

    -- Zone
    local top = TopMapID()
    if top then
        local zoneMenu = root:CreateButton(ZONE or L["Zone"])
        zoneMenu:CreateButton(CHECK_ALL or L["Check all"], function() return SetAllMaps(true) end)
        zoneMenu:CreateButton(UNCHECK_ALL or L["Uncheck all"], function() return SetAllMaps(false) end)
        local function AddChildren(menu, mapID)
            local children = C_Map.GetMapChildrenInfo(mapID) or {}
            table.sort(children, function(a, b) return a.name < b.name end)
            for _, child in ipairs(children) do
                if Selectable(child.mapID) then
                    if HasSelectableChildren(child.mapID) then
                        AddChildren(menu:CreateButton(child.name), child.mapID)
                    else
                        menu:CreateCheckbox(child.name, function() return W.mapsIncluded[child.mapID] end, function()
                            W.mapsIncluded[child.mapID] = not W.mapsIncluded[child.mapID] or nil
                        end)
                    end
                end
            end
        end
        AddChildren(zoneMenu, top)
    end

    -- Sort: done here, on the results Seeker keeps, so the direction is always the one picked
    -- (the game's SortWho only flips direction on a repeat call). Column headers sort too.
    local sortMenu = root:CreateButton(WHO_SORT_LABEL or L["Sort"])
    for _, c in ipairs(ns.WHO_COLUMNS) do
        sortMenu:CreateRadio(c.label, function() return W.sortMode == c.key end, function()
            ns.SetWhoSort(c.key, W.ascending)
            return MenuResponse and MenuResponse.Refresh
        end)
    end
    sortMenu:CreateDivider()
    sortMenu:CreateRadio(WHO_SORT_ASCENDING_LABEL or L["Ascending"], function() return W.ascending end, function()
        ns.SetWhoSort(W.sortMode, true)
        return MenuResponse and MenuResponse.Refresh
    end)
    sortMenu:CreateRadio(WHO_SORT_DESCENDING_LABEL or L["Descending"], function() return not W.ascending end, function()
        ns.SetWhoSort(W.sortMode, false)
        return MenuResponse and MenuResponse.Refresh
    end)

    root:CreateDivider()
    root:CreateButton(L["Clear all filters"], function()
        wipe(W.classesFiltered)
        wipe(W.racesFiltered)
        wipe(W.mapsIncluded)
        return MenuResponse and MenuResponse.Refresh
    end)
end

---------------------------------------------------------------------------
-- List
---------------------------------------------------------------------------
-- field: what each column shows and sorts by, from C_FriendList.GetWhoInfo.
local COLUMNS = {
    { key = "name", field = "fullName", label = NAME or L["Name"], x = 10, width = 160 },
    { key = "level", field = "level", label = LEVEL or L["Level"], x = 174, width = 40, justify = "CENTER" },
    { key = "race", field = "raceStr", label = RACE or L["Race"], x = 220, width = 100 },
    { key = "class", field = "classStr", label = CLASS or L["Class"], x = 324, width = 90 },
    { key = "zone", field = "area", label = ZONE or L["Zone"], x = 418, width = 190 },
    { key = "guild", field = "fullGuildName", label = GUILD or L["Guild"], x = 612, width = 170 },
}
ns.WHO_COLUMNS = COLUMNS

local Render -- below

-- Sort the kept results by a column, then by name, in the chosen direction.
local function SortData()
    local field = "fullName"
    for _, c in ipairs(COLUMNS) do if c.key == W.sortMode then field = c.field end end
    local asc = W.ascending ~= false
    table.sort(data, function(a, b)
        local x, y = a[field], b[field]
        if type(x) == "string" then x = x:lower() end
        if type(y) == "string" then y = y:lower() end
        if x == nil then x = type(y) == "number" and -1 or "" end
        if y == nil then y = type(x) == "number" and -1 or "" end
        if x ~= y then
            if asc then return x < y end
            return x > y
        end
        return (a.fullName or "") < (b.fullName or "")
    end)
end

function ns.SetWhoSort(key, ascending)
    W.sortMode, W.ascending = key, ascending and true or false
    SortData()
    if page and page.UpdateHeaders then page.UpdateHeaders() end
    if Render then Render() end
end

local function PlayerMenu(owner, info)
    local name = info.fullName
    if FriendsFrame_ShowDropdown then
        local ok = pcall(FriendsFrame_ShowDropdown, name, 1)
        if ok then return end
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(name)
        root:CreateButton(WHISPER or L["Whisper"], function() ns.Whisper(name) end)
        root:CreateButton(PARTY_INVITE or L["Invite"], function() ns.Invite(name, true) end)
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
    row.cols = {}
    for _, c in ipairs(COLUMNS) do
        local fs = U.Text(row, "UserScaledFontGameNormalSmall") -- the game's Who list font
        fs:SetPoint("LEFT", c.x, 0)
        fs:SetWidth(c.width)
        fs:SetJustifyH(c.justify or "LEFT")
        fs:SetWordWrap(false)
        row.cols[c.key] = fs
    end
    -- The game's own Who invite button: a small square button with the "invite to group" icon
    -- (its tertiary square button art), not a row of red text buttons. Falls back to a text
    -- button if the art isn't there.
    local SQUARE, ICON = "common-button-tertiary-square-normal", "friends-icon-friendsInGroup"
    if U.HasAtlas(SQUARE) and U.HasAtlas(ICON) then
        local b = CreateFrame("Button", nil, row)
        b:SetSize(ROW_H, ROW_H)
        b:SetNormalAtlas(SQUARE)
        if U.HasAtlas("common-button-tertiary-square-pressed") then b:SetPushedAtlas("common-button-tertiary-square-pressed") end
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.Icon = b:CreateTexture(nil, "OVERLAY")
        b.Icon:SetAtlas(ICON)
        b.Icon:SetSize(ROW_H - 6, ROW_H - 6)
        b.Icon:SetPoint("CENTER", 0, 1)
        row.invite = b
    else
        row.invite = U.RedButton(row, GROUP_INVITE or L["Invite"], 70, 18, true)
    end
    row.invite:SetPoint("RIGHT", -12, 0)
    row.invite:SetScript("OnClick", function()
        if row.info then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            ns.Invite(row.info.fullName, true) -- as the game's Who list invites (TryInvite)
        end
    end)
    row.invite:SetMotionScriptsWhileDisabled(true)
    row.invite:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(WHO_PARTY_BUTTON_TOOLTIP or L["Invite to your party"], 1, 1, 1, 1, true)
        local blocker = ns.InviteBlocker()
        if blocker then GameTooltip:AddLine(blocker, 1, 0.3, 0.3, true) end
        GameTooltip:Show()
    end)
    row.invite:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self, button)
        if self.info and button == "RightButton" then PlayerMenu(self, self.info) end
    end)
    -- Text cut off to fit its column: the whole of it on hover, as the game's Who list does.
    row:SetScript("OnEnter", function(self)
        local info = self.info
        if not info then return end
        local cut = false
        for _, fs in pairs(self.cols) do
            if fs.IsTruncated and fs:IsTruncated() then cut = true break end
        end
        if not cut then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(info.fullName or "?", U.ClassColor(info.filename))
        GameTooltip:AddLine((WHO_LIST_LEVEL_TOOLTIP or L["Level %d"]):format(info.level or 0), 1, 1, 1)
        for _, line in ipairs({ info.raceStr, info.classStr, info.area, info.fullGuildName }) do
            if type(line) == "string" and line ~= "" then GameTooltip:AddLine(line, 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

Render = function()
    if not page or not page:IsShown() then return end
    local canInvite = ns.InviteBlocker() == nil
    local area = page.area
    local visible = math.max(1, math.floor(area:GetHeight() / ROW_H))
    local maxScroll = math.max(0, #data - visible)
    if scroll > maxScroll then scroll = maxScroll end
    area.scrollbar:SetMinMaxValues(0, maxScroll)
    area.scrollbar:SetValue(scroll)
    area.scrollbar:SetShown(maxScroll > 0)
    local myZone = GetRealZoneText and GetRealZoneText()
    local me = UnitName("player")
    for i = 1, visible do
        local row = rows[i] or MakeRow(area, i)
        rows[i] = row
        local info = data[scroll + i]
        row.info = info
        if info then
            local r, g, b = U.ClassColor(info.filename)
            row.cols.name:SetText(info.fullName or "?")
            row.cols.name:SetTextColor(r, g, b)
            row.cols.level:SetText(info.level and tostring(info.level) or "?")
            row.cols.race:SetText(info.raceStr or "")
            row.cols.race:SetTextColor(0.9, 0.9, 0.9) -- white like Zone; class colour is for Class
            row.cols.class:SetText(info.classStr or "")
            row.cols.class:SetTextColor(r, g, b)
            row.cols.zone:SetText(info.area or "")
            if myZone and info.area == myZone then row.cols.zone:SetTextColor(0.35, 1, 0.35) else row.cols.zone:SetTextColor(1, 1, 1) end
            row.cols.guild:SetText(info.fullGuildName or "")
            row.cols.guild:SetTextColor(0.75, 0.75, 0.75)
            row.invite:SetShown(info.fullName ~= me and info.fullName ~= GetUnitName("player"))
            row.invite:SetEnabled(canInvite)
            if row.invite.Icon then row.invite.Icon:SetDesaturated(not canInvite) end
            row:Show()
        else
            row:Hide()
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end
    page.empty:SetShown(#data == 0)
end

-- Copy the game's latest /who answer into the page. The page keeps its own copy, because Seeker's
-- quiet member lookups replace the game's list in the background, and coming back to the tab
-- would otherwise show a lookup's single result instead of your search.
local function Update()
    if not C_FriendList or not C_FriendList.GetNumWhoResults then return end
    wipe(data)
    local num, total = C_FriendList.GetNumWhoResults()
    for i = 1, num or 0 do
        local info = C_FriendList.GetWhoInfo(i)
        if info then data[#data + 1] = info end
    end
    SortData()
    local text = (WHO_FRAME_TOTAL_TEMPLATE or L["%d players total"]):format(total or 0)
    if (total or 0) > MAX_FROM_SERVER then
        text = text .. "  " .. (WHO_FRAME_SHOWN_TEMPLATE or L["(%d shown)"]):format(MAX_FROM_SERVER)
    end
    page.totals:SetText(text)
    Render()
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function ns.BuildWhoPage(f, p)
    page = p
    U = ns.UI
    -- From here on the filters and sort live in the saved variables.
    if ns.db and ns.db.who then
        W = ns.db.who
        ns.Who = W
    end

    local title = U.Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 72, -34)
    title:SetText(WHO or L["Who"])

    local box = U.TryCreate("EditBox", "SeekerLFGWhoBox", page, "SearchBoxTemplate")
        or CreateFrame("EditBox", "SeekerLFGWhoBox", page, "InputBoxTemplate")
    box:SetSize(280, 24)
    box:SetAutoFocus(false)
    box:SetPoint("LEFT", title, "RIGHT", 18, -1)
    if box.Instructions then
        box.Instructions:SetText(L["Name, zone, guild, class or level"])
        box.Instructions:SetWordWrap(false)
        box.Instructions:SetMaxLines(1)
    end
    U.Tooltip(box, WHO or L["Who"], L["Search like /who: a name, zone, guild, class, race or a level range such as 20-30."])
    box:SetScript("OnEnterPressed", function(self)
        SendWho(self:GetText())
        self:ClearFocus()
    end)
    page.box = box

    local search = U.RedButton(page, SEARCH or L["Search"], 86, 24)
    search:SetPoint("LEFT", box, "RIGHT", 10, 0)
    search:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        SendWho(box:GetText())
        box:ClearFocus()
    end)

    local filter = U.TryCreate("DropdownButton", nil, page, "WowStyle1FilterDropdownTemplate")
    if filter and filter.SetupMenu then
        filter:SetWidth(96)
        if filter.Text then filter.Text:SetText(FILTER or L["Filter"]) end
        filter:SetupMenu(function(_, root) BuildFilterMenu(root) end)
    else
        filter = U.RedButton(page, FILTER or L["Filter"], 96, 24)
        filter:SetScript("OnClick", function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, function(_, root) BuildFilterMenu(root) end)
            end
        end)
    end
    filter:SetPoint("LEFT", search, "RIGHT", 10, 0)

    local inset = U.Inset(page)
    inset:SetPoint("TOPLEFT", 4, -62)
    inset:SetPoint("BOTTOMRIGHT", -6, 30)

    local header = U.HeaderBar(inset)
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    -- Column headers sort: click once for that column, again to flip the direction.
    -- The sorted column shows the game's own sort arrow (as its Who list headers do), up for
    -- ascending, down for descending, just after the heading's text.
    header.labels, header.arrows = {}, {}
    local function UpdateHeaders()
        for _, c in ipairs(COLUMNS) do
            local fs, arrow = header.labels[c.key], header.arrows[c.key]
            fs:SetText(c.label)
            if W.sortMode == c.key then
                if W.ascending ~= false then arrow:SetTexCoord(0, 0.5625, 1, 0) else arrow:SetTexCoord(0, 0.5625, 0, 1) end
                local textW = fs:GetStringWidth() or 0
                local x = (c.justify == "CENTER") and ((c.width + textW) / 2 + 3) or (textW + 3)
                arrow:ClearAllPoints()
                arrow:SetPoint("LEFT", fs:GetParent(), "LEFT", x, 0)
                arrow:Show()
            else
                arrow:Hide()
            end
        end
    end
    for _, c in ipairs(COLUMNS) do
        local b = CreateFrame("Button", nil, header)
        b:SetPoint("LEFT", c.x, -4)
        b:SetSize(c.width, 20)
        local fs = U.Text(b, "GameFontNormal")
        fs:SetAllPoints()
        fs:SetJustifyH(c.justify or "LEFT")
        header.labels[c.key] = fs
        local arrow = b:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        arrow:SetSize(9, 8)
        arrow:Hide()
        header.arrows[c.key] = arrow
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            if W.sortMode == c.key then
                ns.SetWhoSort(c.key, W.ascending == false)
            else
                ns.SetWhoSort(c.key, true)
            end
            UpdateHeaders()
        end)
        U.Tooltip(b, c.label, L["Click to sort by this column; click again to reverse."])
    end
    UpdateHeaders()
    page.UpdateHeaders = UpdateHeaders

    local area = CreateFrame("Frame", nil, inset)
    area:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
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
        if v ~= scroll then scroll = v; Render() end
    end)
    area.scrollbar = sb
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() then ns.StepScale(delta) else sb:SetValue(scroll - delta * 3) end
    end)
    area:SetScript("OnSizeChanged", Render)

    page.empty = U.Text(area, "GameFontDisable")
    page.empty:SetPoint("TOP", 0, -50)
    page.empty:SetText(L["Search for players: a name, zone, guild, class, race or level range."])

    page.totals = U.Text(page, "GameFontNormalSmall")
    page.totals:SetPoint("BOTTOMLEFT", 14, 10)

    local hint = U.Text(page, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMRIGHT", -26, 10)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText(L["Right-click a player for more options"])

    local ev = CreateFrame("Frame", nil, page)
    ev:RegisterEvent("WHO_LIST_UPDATE")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function(_, event)
        if event ~= "WHO_LIST_UPDATE" then Render() return end -- who can invite changed
        -- Answers to your own searches only: never a quiet member lookup's.
        if ns.IsQuietLookup and ns.IsQuietLookup() then return end
        if page:IsShown() or (ns.whoUntil and GetTime() < ns.whoUntil) then Update() end
    end)

    page:SetScript("OnShow", function()
        ns.KeepWhoInUI()
        if page.UpdateHeaders then page.UpdateHeaders() end
        Render() -- the results you last searched for, kept by the page
    end)
    page:SetScript("OnHide", function()
        if C_FriendList and C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(false) end
    end)
end
