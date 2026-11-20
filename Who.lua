-- Seeker: the Who page. Mirrors the third tab of Forever's own group finder
-- (Blizzard_GroupFinder_VanillaStyle/Mainline/WhoList.lua): a /who search with class, race and
-- zone filters and sorting, an invite button per player, and the game's player menu on right-click.
local ADDON, ns = ...

local MAX_FROM_SERVER = 50
local ROW_H = 20

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
    ns.KeepWhoInUI()
    -- The game shows /who results in its own window; for the next few seconds, they come to ours.
    ns.whoUntil = GetTime() + 8
    local origin = Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
    local ok = pcall(C_FriendList.SendWho, text or "", origin, Filters())
    if not ok then pcall(C_FriendList.SendWho, text or "") end
    page.totals:SetText(SEARCHING or "Searching...")
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
    local classMenu = root:CreateButton(CLASS or "Class")
    classMenu:CreateButton(CHECK_ALL or "Check all", function()
        wipe(W.classesFiltered)
        return MenuResponse and MenuResponse.Refresh
    end)
    classMenu:CreateButton(UNCHECK_ALL or "Uncheck all", function()
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
        local raceMenu = root:CreateButton(RACE or "Race")
        local races = C_FriendList.GetWhoRaceFilters() or {}
        raceMenu:CreateButton(CHECK_ALL or "Check all", function()
            wipe(W.racesFiltered)
            return MenuResponse and MenuResponse.Refresh
        end)
        raceMenu:CreateButton(UNCHECK_ALL or "Uncheck all", function()
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
        local zoneMenu = root:CreateButton(ZONE or "Zone")
        zoneMenu:CreateButton(CHECK_ALL or "Check all", function() return SetAllMaps(true) end)
        zoneMenu:CreateButton(UNCHECK_ALL or "Uncheck all", function() return SetAllMaps(false) end)
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

    -- Sort
    if C_FriendList.SortWho then
        local sortMenu = root:CreateButton(WHO_SORT_LABEL or "Sort")
        for _, s in ipairs({ { "name", NAME or "Name" }, { "class", CLASS or "Class" }, { "level", LEVEL or "Level" } }) do
            sortMenu:CreateRadio(s[2], function() return W.sortMode == s[1] end, function()
                W.sortMode = s[1]
                C_FriendList.SortWho(W.sortMode)
                return MenuResponse and MenuResponse.Refresh
            end)
        end
        sortMenu:CreateDivider()
        sortMenu:CreateRadio(WHO_SORT_ASCENDING_LABEL or "Ascending", function() return W.ascending end, function()
            W.ascending = true
            C_FriendList.SortWho(W.sortMode, true)
            return MenuResponse and MenuResponse.Refresh
        end)
        sortMenu:CreateRadio(WHO_SORT_DESCENDING_LABEL or "Descending", function() return not W.ascending end, function()
            W.ascending = false
            C_FriendList.SortWho(W.sortMode, false)
            return MenuResponse and MenuResponse.Refresh
        end)
    end
end

---------------------------------------------------------------------------
-- List
---------------------------------------------------------------------------
local COLUMNS = {
    { key = "name", label = NAME or "Name", x = 10, width = 160 },
    { key = "level", label = LEVEL or "Level", x = 174, width = 40, justify = "CENTER" },
    { key = "race", label = RACE or "Race", x = 220, width = 100 },
    { key = "class", label = CLASS or "Class", x = 324, width = 90 },
    { key = "zone", label = ZONE or "Zone", x = 418, width = 190 },
    { key = "guild", label = GUILD or "Guild", x = 612, width = 170 },
}

local function PlayerMenu(owner, info)
    local name = info.fullName
    if FriendsFrame_ShowDropdown then
        local ok = pcall(FriendsFrame_ShowDropdown, name, 1)
        if ok then return end
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(name)
        root:CreateButton(WHISPER or "Whisper", function() ns.Whisper(name) end)
        root:CreateButton(PARTY_INVITE or "Invite", function() ns.Invite(name) end)
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
    row.invite = U.RedButton(row, GROUP_INVITE or "Invite", 70, 18, true)
    row.invite:SetPoint("RIGHT", -6, 0)
    row.invite:SetScript("OnClick", function()
        if row.info then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            ns.Invite(row.info.fullName)
        end
    end)
    row:SetScript("OnClick", function(self, button)
        if self.info and button == "RightButton" then PlayerMenu(self, self.info) end
    end)
    return row
end

local function Render()
    if not page or not page:IsShown() then return end
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
            row.cols.class:SetText(info.classStr or "")
            row.cols.class:SetTextColor(r, g, b)
            row.cols.zone:SetText(info.area or "")
            if myZone and info.area == myZone then row.cols.zone:SetTextColor(0.35, 1, 0.35) else row.cols.zone:SetTextColor(1, 1, 1) end
            row.cols.guild:SetText(info.fullGuildName or "")
            row.cols.guild:SetTextColor(0.75, 0.75, 0.75)
            row.invite:SetShown(info.fullName ~= me and info.fullName ~= GetUnitName("player"))
            row:Show()
        else
            row:Hide()
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end
    page.empty:SetShown(#data == 0)
end

local function Update()
    wipe(data)
    if not C_FriendList or not C_FriendList.GetNumWhoResults then return end
    local num, total = C_FriendList.GetNumWhoResults()
    for i = 1, num or 0 do
        local info = C_FriendList.GetWhoInfo(i)
        if info then data[#data + 1] = info end
    end
    local text = (WHO_FRAME_TOTAL_TEMPLATE or "%d players total"):format(total or 0)
    if (total or 0) > MAX_FROM_SERVER then
        text = text .. "  " .. (WHO_FRAME_SHOWN_TEMPLATE or "(%d shown)"):format(MAX_FROM_SERVER)
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

    local title = U.Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 72, -34)
    title:SetText(WHO or "Who")

    local box = U.TryCreate("EditBox", "SeekerLFGWhoBox", page, "SearchBoxTemplate")
        or CreateFrame("EditBox", "SeekerLFGWhoBox", page, "InputBoxTemplate")
    box:SetSize(280, 24)
    box:SetAutoFocus(false)
    box:SetPoint("LEFT", title, "RIGHT", 18, -1)
    if box.Instructions then
        box.Instructions:SetText("Name, zone, guild, class or level")
        box.Instructions:SetWordWrap(false)
        box.Instructions:SetMaxLines(1)
    end
    U.Tooltip(box, WHO or "Who", "Search like /who: a name, zone, guild, class, race or a level range such as 20-30.")
    box:SetScript("OnEnterPressed", function(self)
        SendWho(self:GetText())
        self:ClearFocus()
    end)
    page.box = box

    local search = U.RedButton(page, SEARCH or "Search", 86, 24)
    search:SetPoint("LEFT", box, "RIGHT", 10, 0)
    search:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        SendWho(box:GetText())
        box:ClearFocus()
    end)

    local filter = U.TryCreate("DropdownButton", nil, page, "WowStyle1FilterDropdownTemplate")
    if filter and filter.SetupMenu then
        filter:SetWidth(96)
        if filter.Text then filter.Text:SetText(FILTER or "Filter") end
        filter:SetupMenu(function(_, root) BuildFilterMenu(root) end)
    else
        filter = U.RedButton(page, FILTER or "Filter", 96, 24)
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
    for _, c in ipairs(COLUMNS) do
        local fs = U.Text(header, "GameFontNormal", U.SIZE_LABEL)
        fs:SetPoint("LEFT", c.x, -4)
        fs:SetWidth(c.width)
        fs:SetJustifyH(c.justify or "LEFT")
        fs:SetText(c.label)
    end

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

    page.empty = U.Text(area, "GameFontDisable", U.SIZE_NAME)
    page.empty:SetPoint("TOP", 0, -50)
    page.empty:SetText("Search for players: a name, zone, guild, class, race or level range.")

    page.totals = U.Text(page, "GameFontNormalSmall")
    page.totals:SetPoint("BOTTOMLEFT", 14, 10)

    local hint = U.Text(page, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMRIGHT", -26, 10)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText("Right-click a player for more options")

    local ev = CreateFrame("Frame", nil, page)
    ev:RegisterEvent("WHO_LIST_UPDATE")
    ev:SetScript("OnEvent", function()
        if page:IsShown() then Update() end
    end)

    page:SetScript("OnShow", function()
        ns.KeepWhoInUI()
        Update()
    end)
    page:SetScript("OnHide", function()
        if C_FriendList and C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(false) end
    end)
end
