-- Seeker LFG: a page in the game's own options (Options > AddOns > Seeker LFG), with every setting
-- the cog menu has, for players who never find the cog.
local ADDON, ns = ...

local category, panel
local refreshers = {}

local function Build()
    local U = ns.UI
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
    Note("Looking for Group with groups and players side by side, and filters that keep your dungeon runs earning XP. Type /seeker to open it.")

    Heading("General")
    Toggle("Replace the game's Looking for Group window", function() return ns.db.replaceNative end,
        function(v) ns.SetReplaceNative(v) end,
        "Open Seeker wherever the game would open its own window. Hold Shift for the game's.")
    Toggle("Show minimap button", function() return ns.db.minimapButton ~= false end,
        function(v) ns.SetMinimapButton(v) end)
    local wm = Toggle("Whisper with Whisper Messenger", function() return ns.db.useWhisperMessenger ~= false end,
        function(v) ns.db.useWhisperMessenger = v end,
        "When Whisper Messenger is installed, whispers open there.")
    refreshers[#refreshers + 1] = function() wm:SetEnabled(ns.HasWhisperMessenger()) end
    Toggle(LFG_LIST_IGNORE_SUGGESTED_LEVEL or "Show all level ranges", function() return ns.IgnoringLevelRanges() end,
        function(v) ns.SetIgnoreLevelRanges(v) end, "The game's own setting: also list activities outside your level.")

    Heading("Lists")
    local sortLabel = U.Text(panel, "GameFontHighlight")
    sortLabel:SetPoint("TOPLEFT", 20, y - 6)
    sortLabel:SetText("Sort")
    local sort = U.Dropdown(panel, 220, function(root)
        for _, m in ipairs(ns.SORT_MODES) do
            U.Radio(root, m.label, function() return ns.db.sortMode == m.key end, function()
                ns.db.sortMode = m.key
                if ns.Render then ns.Render() end
            end)
        end
    end, function()
        for _, m in ipairs(ns.SORT_MODES) do if m.key == ns.db.sortMode then return m.label end end
        return "Best XP first"
    end)
    sort:SetPoint("LEFT", sortLabel, "RIGHT", 16, 0)
    refreshers[#refreshers + 1] = function() if sort.Refresh then sort:Refresh() end end
    y = y - 36
    Note("Whatever the order, your own listing comes first, then listings for what you're listed for, then ones with friends or guildmates in them.")
    Toggle("Count my level in the XP check", function() return ns.db.filters.includeSelf end,
        function(v) ns.db.filters.includeSelf = v end)

    Heading("Alerts")
    local A = ns.db.alerts
    Toggle("Tell me about new matches", function() return A.enabled end, function(v) A.enabled = v end,
        "When new groups or players that pass your filters turn up in a search, they're listed in chat.")
    Toggle("Only ones with full XP", function() return A.fullXPOnly end, function(v) A.fullXPOnly = v end)
    Toggle("Play a sound", function() return A.sound end, function(v) A.sound = v end)
    Toggle("Flash the game's icon", function() return A.flash end, function(v) A.flash = v end,
        "Flash the game's taskbar icon when it's in the background.")
    Note("The game only lets a search run from a key press or click. Bind \"Search again\" (Options > Keybindings > Seeker LFG) to search with the window closed and hear about new matches.")

    -- Actions
    local open = U.RedButton(panel, "Open Seeker LFG", 150, 24)
    open:SetPoint("TOPLEFT", 16, y - 4)
    open:SetScript("OnClick", function() ns.Show() end)
    local msgs = U.RedButton(panel, "Messages...", 120, 24)
    msgs:SetPoint("LEFT", open, "RIGHT", 8, 0)
    msgs:SetScript("OnClick", function() ns.ShowMessages() end)
    local reset = U.RedButton(panel, "Reset window", 120, 24)
    reset:SetPoint("LEFT", msgs, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function() SlashCmdList.SEEKERLFG("reset") end)
    local test = U.RedButton(panel, "Run self-test", 120, 24)
    test:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    test:SetScript("OnClick", function() ns.SelfTest() end)
end

local function Register()
    if category or panel then return end
    panel = CreateFrame("Frame")
    panel.name = "Seeker LFG"
    panel:Hide()
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
