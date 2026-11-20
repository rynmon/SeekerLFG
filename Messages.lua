-- Seeker LFG: the Messages window. Your own Request to join message, and an optional whisper sent
-- when you invite someone, with [placeholders] filled in for each listing.
local ADDON, ns = ...

local W, H = 540, 360
local frame, lastBox

-- A listing to preview with: a dungeon you've picked (or one at your level) and a sample name.
local function SampleEntry()
    local id = ns.SelectedActivities and ns.SelectedActivities() and ns.SelectedActivities()[1]
    if not id and ns.db.categoryID then id = ns.GetFilteredActivities(ns.db.categoryID)[1] end
    return { leaderName = "Skeron", activityIDs = { id }, xpActivity = id }
end

local function UpdatePreviews()
    if not frame then return end
    local sample = SampleEntry()
    for _, box in ipairs(frame.boxes) do
        local text = ns.RenderMessage(box.get(), sample)
        if text == "" then
            box.preview:SetText("|cff808080" .. box.emptyText .. "|r")
        else
            box.preview:SetText(text)
        end
        box.count:SetText(("%d/%d"):format(#text, ns.MAX_WHISPER))
    end
end

local function InsertToken(token)
    local box = lastBox or frame.boxes[1].edit
    box:SetFocus()
    box:Insert("[" .. token .. "]")
end

local function Build()
    local U = ns.UI
    frame = U.TryCreate("Frame", "SeekerLFGMessagesFrame", UIParent, "ButtonFrameTemplate")
    if frame then
        if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(frame) end
        if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end
        frame.onCloseCallback = function() frame:Hide() return false end
        if frame.SetTitle then frame:SetTitle("Messages") elseif frame.TitleText then frame.TitleText:SetText("Messages") end
        if frame.Inset then
            frame.Inset:ClearAllPoints()
            frame.Inset:SetPoint("TOPLEFT", 4, -24)
            frame.Inset:SetPoint("BOTTOMRIGHT", -6, 36)
        end
    else
        frame = CreateFrame("Frame", "SeekerLFGMessagesFrame", UIParent, "BackdropTemplate")
        frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
    end
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "SeekerLFGMessagesFrame")

    frame.boxes = {}
    local y = -38
    local function MessageBox(label, help, get, set, emptyText)
        local title = U.Text(frame, "GameFontNormal")
        title:SetPoint("TOPLEFT", 18, y)
        title:SetText(label)
        local note = U.Text(frame, "GameFontHighlightSmall")
        note:SetPoint("LEFT", title, "RIGHT", 8, 0)
        note:SetTextColor(0.65, 0.65, 0.65)
        note:SetText(help)

        local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        edit:SetSize(W - 46, 24)
        edit:SetPoint("TOPLEFT", 24, y - 18)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(400) -- placeholders grow or shrink; the result is kept to one whisper
        edit:SetText(get() or "")
        edit:SetCursorPosition(0)
        edit:SetScript("OnTextChanged", function(self, user)
            if user then set(self:GetText()) end
            UpdatePreviews()
        end)
        edit:SetScript("OnEditFocusGained", function(self) lastBox = self end)
        edit:SetScript("OnEnterPressed", edit.ClearFocus)
        edit:SetScript("OnEscapePressed", edit.ClearFocus)

        local preview = U.Text(frame, "GameFontHighlightSmall")
        preview:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -4, -4)
        preview:SetPoint("RIGHT", frame, "RIGHT", -70, 0)
        preview:SetJustifyH("LEFT")
        preview:SetWordWrap(true)
        preview:SetMaxLines(2)
        local count = U.Text(frame, "GameFontDisableSmall")
        count:SetPoint("TOPRIGHT", edit, "BOTTOMRIGHT", 0, -4)

        local box = { edit = edit, preview = preview, count = count, get = get, emptyText = emptyText }
        frame.boxes[#frame.boxes + 1] = box
        y = y - 90
        return box
    end

    MessageBox("Request to join", "opens in a whisper to the leader; you press Enter to send",
        function() return ns.db.requestMessage or ns.DEFAULT_REQUEST_MESSAGE end,
        function(t) ns.db.requestMessage = t end,
        "Empty: the default message is used.")
    MessageBox("Invite", "whispered to the player when you click Invite",
        function() return ns.InviteMessage() end,
        function(t) ns.db.inviteMessage = t end,
        "Empty: inviting sends no whisper.")

    -- Placeholders: click one to put it where you're typing.
    local tokensLabel = U.Text(frame, "GameFontNormal")
    tokensLabel:SetPoint("TOPLEFT", 18, y + 2)
    tokensLabel:SetText("Placeholders")
    local hint = U.Text(frame, "GameFontHighlightSmall")
    hint:SetPoint("LEFT", tokensLabel, "RIGHT", 8, 0)
    hint:SetTextColor(0.65, 0.65, 0.65)
    hint:SetText("click to add, or type them")
    local x, row = 22, 0
    for _, t in ipairs(ns.MESSAGE_TOKENS) do
        local b = U.RedButton(frame, "[" .. t[1] .. "]", 82, 22, true)
        if x + 82 > W - 18 then x, row = 22, row + 1 end
        b:SetPoint("TOPLEFT", x, y - 18 - row * 26)
        b:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            InsertToken(t[1])
        end)
        U.Tooltip(b, "[" .. t[1] .. "]", t[2])
        x = x + 86
    end

    local reset = U.RedButton(frame, RESET_TO_DEFAULT or "Reset to defaults", 150, 22)
    reset:SetPoint("BOTTOMLEFT", 14, 8)
    reset:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.db.requestMessage, ns.db.inviteMessage = nil, nil
        frame.boxes[1].edit:SetText(ns.DEFAULT_REQUEST_MESSAGE)
        frame.boxes[2].edit:SetText(ns.DEFAULT_INVITE_MESSAGE)
        UpdatePreviews()
    end)
    local done = U.RedButton(frame, DONE or "Done", 110, 22)
    done:SetPoint("BOTTOMRIGHT", -14, 8)
    done:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        frame:Hide()
    end)

    frame:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        UpdatePreviews()
    end)
end

function ns.ShowMessages()
    if not frame then Build() end
    frame:Show()
    frame:Raise()
end
