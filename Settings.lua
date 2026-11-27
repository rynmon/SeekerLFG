-- Seeker LFG: a page in the game's own options (Options > AddOns > Seeker LFG), with every setting
-- the cog menu has, for players who never find the cog.
local ADDON, ns = ...
local L = ns.L -- translations (Locale.lua)

local category, panel
local refreshers = {}

local content -- the scrolling area everything is built in (the page is taller than the window)

local function Build()
    local U = ns.UI
    local panel = content
    local y = -16
    local function Heading(text)
        local fs = U.Text(panel, "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", 16, y)
        fs:SetText(text)
        y = y - 28
    end
    local function Note(text)
        local fs = U.Text(panel, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 20, y)
        fs:SetWidth(560) -- a fixed width, so the wrapped height is known straight away
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(0.7, 0.7, 0.7)
        fs:SetText(text)
        y = y - (fs:GetStringHeight() + 10)
    end
    local function Toggle(label, get, set, tip)
        local c = U.Check(panel, label, get, function(v) set(v) if ns.Render then ns.Render() end end, label, tip)
        c:SetPoint("TOPLEFT", 16, y)
        refreshers[#refreshers + 1] = function() c:SetChecked(get() and true or false) end
        y = y - 28
        return c
    end

    local title = U.Text(panel, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, y)
    title:SetText("Seeker LFG")
    local version = U.Text(panel, "GameFontDisable")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
    version:SetText(ns.VERSION and ("v" .. ns.VERSION) or "")
    y = y - 40
    Note(L["Looking for Group with groups and players side by side, and filters that keep your dungeon runs earning XP. Type /seeker to open it."])

    Heading(L["General"])
    Toggle(L["Replace the game's Looking for Group window"], function() return ns.db.replaceNative end,
        function(v) ns.SetReplaceNative(v) end,
        L["Open Seeker wherever the game would open its own window. Hold Shift for the game's."])
    Toggle(L["Show minimap button"], function() return ns.db.minimapButton ~= false end,
        function(v) ns.SetMinimapButton(v) end)
    local wm = Toggle(L["Whisper with Whisper Messenger"], function() return ns.db.useWhisperMessenger ~= false end,
        function(v) ns.db.useWhisperMessenger = v end,
        L["When Whisper Messenger is installed, whispers open there."])
    refreshers[#refreshers + 1] = function() wm:SetEnabled(ns.HasWhisperMessenger()) end
    Toggle(LFG_LIST_IGNORE_SUGGESTED_LEVEL or L["Show all level ranges"], function() return ns.IgnoringLevelRanges() end,
        function(v) ns.SetIgnoreLevelRanges(v) end, L["The game's own setting: also list activities outside your level."])
    Toggle(L["Collect whispers while I'm listed"], function() return ns.db.whisperInbox ~= false end,
        function(v) ns.db.whisperInbox = v end,
        L["Whispers you get while you're listed are kept on the People tab, with Invite buttons. Forever's group finder has no applications: players ask to join by whisper."])

    Heading(L["Lists"])
    local sortLabel = U.Text(panel, "GameFontHighlight")
    sortLabel:SetPoint("TOPLEFT", 20, y - 6)
    sortLabel:SetText(L["Sort"])
    local sort = U.Dropdown(panel, 290, function(root)
        for _, m in ipairs(ns.SORT_MODES) do
            U.Radio(root, m.label, function() return ns.db.sortMode == m.key end, function()
                ns.db.sortMode = m.key
                if ns.Render then ns.Render() end
            end)
        end
    end, function()
        for _, m in ipairs(ns.SORT_MODES) do if m.key == ns.db.sortMode then return m.label end end
        return L["Best XP first"]
    end)
    sort:SetPoint("LEFT", sortLabel, "RIGHT", 16, 0)
    refreshers[#refreshers + 1] = function() if sort.Refresh then sort:Refresh() end end
    y = y - 36
    Note(L["Whatever the order, your own listing comes first, then listings for what you're listed for, then ones with friends or guildmates in them."])
    Toggle(L["Count my level in the XP check"], function() return ns.db.filters.includeSelf end,
        function(v) ns.db.filters.includeSelf = v end)
    Toggle(L["Show XP as symbols too"], function() return ns.db.xpMarks end, function(v) ns.db.xpMarks = v end,
        L["A tick, question mark or cross beside each level and in the colour key, for when green, yellow and red are hard to tell apart."])
    Toggle(L["Grey out listings outside the picked activities"], function() return ns.db.filters.greyOutsidePick end,
        function(v) ns.db.filters.greyOutsidePick = v end,
        L["As the game does: listings for activities you haven't picked stay in the list, greyed out at the bottom, instead of being hidden."])
    Toggle(L["Grey out groups for raids I'm saved to"], function() return ns.db.filters.greySaved end,
        function(v) ns.db.filters.greySaved = v end,
        L["Groups listed only for raids or dungeons you're saved to (a boss down) are greyed out at the bottom. Either way they're marked with the game's lockout icon."])
    Toggle(L["Light up the seat I'd fill"], function() return ns.db.markMySeat ~= false end,
        function(v) ns.db.markMySeat = v end,
        L["On a group's card, the first open seat shows one of your roles they still need, lit green. Your roles are the ones on the List yourself page."])
    Toggle(L["Show how many zones away"], function() return ns.db.zoneHops ~= false end,
        function(v) ns.db.zoneHops = v end,
        L["After where a player or group leader is: how many zones they are from their dungeon's entrance, green in its zone through yellow to orange far off. Sort > Closest to the dungeon first puts the nearest at the top."])
    Toggle(L["Compact cards"], function() return ns.db.compactCards end,
        function(v) ns.db.compactCards = v end,
        L["Browse's cards on two lines instead of three: the playstyle and description move to the end of the second line. More cards fit, and their tooltips still show everything."])

    -- How activity lists are grouped (Browse's activity menu and the List yourself page).
    local groupLabel = U.Text(panel, "GameFontHighlight")
    groupLabel:SetPoint("TOPLEFT", 20, y - 6)
    groupLabel:SetText(L["Group activities by"])
    local GROUPINGS = { { "xp", L["What they'd give you in XP"] }, { "game", L["The game's own groups"] } }
    local grouping = U.Dropdown(panel, 220, function(root)
        for _, mode in ipairs(GROUPINGS) do
            U.Radio(root, mode[2], function() return ns.db.activityGrouping == mode[1] end, function()
                ns.SetActivityGrouping(mode[1])
            end)
        end
    end, function()
        return ns.db.activityGrouping == "game" and GROUPINGS[2][2] or GROUPINGS[1][2]
    end)
    grouping:SetPoint("LEFT", groupLabel, "RIGHT", 16, 0)
    refreshers[#refreshers + 1] = function() if grouping.Refresh then grouping:Refresh() end end
    y = y - 36

    Toggle(L["Keep results fresh"], function() return ns.db.autoRefresh end, function(v) ns.db.autoRefresh = v end,
        L["Once results are 30 seconds old, your next click or key press with the window open searches again (the game only allows a search on input)."])

    Heading(L["Chat posts"])
    local C = ns.db.chat
    Toggle(L["Show groups and players looking in chat"], function() return C.enabled end, function(v) C.enabled = v end,
        L["Groups (LFM) and players (LFG) posting in chat channels for a dungeon appear beside the group finder's, marked chat. English messages only."])
    Toggle(L["Only the LookingForGroup channel"], function() return C.lfgChannelOnly end, function(v) C.lfgChannelOnly = v end,
        L["Leave General, world and other channels out."])
    Toggle(L["Tell me about new ones"], function() return C.alerts end, function(v) C.alerts = v end,
        L["New chat posts that pass your filters are announced in chat."])

    Heading(L["Hiding"])
    local F = ns.db.filters
    Toggle(L["Hide players on my ignore list"], function() return F.hideIgnored end, function(v) F.hideIgnored = v end,
        L["Listings led by anyone on the game's ignore list don't show."])
    local wordsLabel = U.Text(panel, "GameFontHighlight")
    wordsLabel:SetPoint("TOPLEFT", 20, y - 6)
    wordsLabel:SetText(L["Hide listings mentioning"])
    local words = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    words:SetSize(320, 24)
    words:SetAutoFocus(false)
    words:SetMaxLetters(200)
    words:SetPoint("LEFT", wordsLabel, "RIGHT", 14, 0)
    words:SetScript("OnTextChanged", function(self, user)
        if user then
            F.hideWords = self:GetText()
            if ns.Render then ns.Render() end
        end
    end)
    words:SetScript("OnEnterPressed", words.ClearFocus)
    words:SetScript("OnEscapePressed", words.ClearFocus)
    U.Tooltip(words, L["Hide listings mentioning"],
        L["Words or phrases, separated by commas, e.g. \"wts, boost, gdkp\". A listing whose title or note has any of them doesn't show."])
    refreshers[#refreshers + 1] = function() words:SetText(F.hideWords or "") words:SetCursorPosition(0) end
    y = y - 34
    local unhide = U.RedButton(panel, L["Show hidden players again"], 200, 22)
    unhide:SetPoint("TOPLEFT", 20, y)
    local hiddenNote = U.Text(panel, "GameFontHighlightSmall")
    hiddenNote:SetPoint("LEFT", unhide, "RIGHT", 10, 0)
    hiddenNote:SetTextColor(0.7, 0.7, 0.7)
    local function RefreshHidden()
        local n = #ns.IgnoredLeaders()
        hiddenNote:SetText(n > 0 and (L["%d hidden. Right-click a listing > Hide to hide a player."]):format(n)
            or L["Nobody hidden. Right-click a listing > Hide to hide a player."])
        unhide:SetEnabled(n > 0)
    end
    unhide:SetScript("OnClick", function()
        wipe(F.ignoredLeaders)
        RefreshHidden()
        if ns.Render then ns.Render() end
    end)
    refreshers[#refreshers + 1] = RefreshHidden
    y = y - 34

    Heading(L["Alerts"])
    local A = ns.db.alerts
    Toggle(L["Tell me about new matches"], function() return A.enabled end, function(v) A.enabled = v end,
        L["When new groups or players that pass your filters turn up in a search, they're listed in chat."])
    Toggle(L["Only roles I need"], function() return A.mode ~= "all" end, function(v) A.mode = v and "roles" or "all" end,
        L["In a party: only players who can play a role it still needs (\"Healer listed: Bob\"). On your own: only groups with room for one of your roles. Off: anything new that passes your filters."])
    Toggle(L["Only ones with full XP"], function() return A.fullXPOnly end, function(v) A.fullXPOnly = v end)
    Toggle(L["Play a sound"], function() return A.sound end, function(v) A.sound = v end)
    Toggle(L["Flash the game's icon"], function() return A.flash end, function(v) A.flash = v end,
        L["Flash the game's taskbar icon when it's in the background."])
    Note(L["The game only lets a search run from a key press or click. Bind \"Search again\" (Options > Keybindings > Seeker LFG) to search with the window closed and hear about new matches."])

    -- Actions
    local open = U.RedButton(panel, L["Open Seeker LFG"], 150, 24)
    open:SetPoint("TOPLEFT", 16, y - 4)
    open:SetScript("OnClick", function() ns.Show() end)
    local msgs = U.RedButton(panel, L["Messages..."], 120, 24)
    msgs:SetPoint("LEFT", open, "RIGHT", 8, 0)
    msgs:SetScript("OnClick", function() ns.ShowMessages() end)
    local reset = U.RedButton(panel, L["Reset window"], 120, 24)
    reset:SetPoint("LEFT", msgs, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function() SlashCmdList.SEEKERLFG("reset") end)
    local test = U.RedButton(panel, L["Run self-test"], 120, 24)
    test:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    test:SetScript("OnClick", function() ns.SelfTest() end)
    content:SetHeight(-y + 40) -- everything built: scroll as far as the last row
end

local function Register()
    if category or panel then return end
    panel = CreateFrame("Frame")
    panel.name = "Seeker LFG"
    panel:Hide()
    -- The page scrolls: it has more settings than fit in the options window.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 800)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then content:SetWidth(w) end end)
    panel:SetScript("OnShow", function(self)
        if not self.built then
            self.built = true
            Build()
        end
        for _, fn in ipairs(refreshers) do pcall(fn) end
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "Seeker LFG")
        category.ID = category.ID or "Seeker LFG"
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function ns.OpenSettings()
    Register()
    if Settings and Settings.OpenToCategory and category then
        local id = category.GetID and category:GetID() or category.ID
        local ok = pcall(Settings.OpenToCategory, id)
        if ok then return end
    end
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() pcall(Register) end)
