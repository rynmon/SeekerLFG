-- Seeker: the "List yourself" page. Mirrors Forever's own listing page
-- (Blizzard_GroupFinder_VanillaStyle/Blizzard_LFGVanilla_Listing.lua): pick a category, tick
-- activities, playstyle (required), voice chat, description, roles, new player friendly,
-- then List / Update / Delist. Only the group leader can create or change a group's listing.
local ADDON, ns = ...

local L = {
    categoryID = nil,
    selected = {},      -- activityID -> true/false (every available activity has a key)
    dirty = false,
    playstyle = nil,    -- Enum.LFGEntryGeneralPlaystyle
    voiceMode = nil,    -- Enum.LFGEntryVoiceMode
    collapsed = {},     -- activity group -> collapsed
    roles = { tank = false, healer = false, dps = false },
    savedInstances = {},
}
ns.Listing = L

local LFG = C_LFGList or {}
local XPFor -- defined with the listing warnings
local BuildPreview, UpdatePreview -- the listing preview card
local ROW_H = 22 -- the game's own activity row spacing

-- A native font object with its own colour (a reused row may have been coloured before).
local function NativeFont(fs, name)
    local obj = _G[name] or GameFontNormal
    fs:SetFontObject(obj)
    local r, g, b = obj:GetTextColor()
    if r then fs:SetTextColor(r, g, b) end
end

-- The game's art for each category's button (LFGVanilla_Constants.lua).
local CATEGORY_ATLAS = {
    [2] = "groupfinder-button-dungeons",
    [114] = "groupfinder-button-raids-warlords",
    [116] = "groupfinder-button-questing",
    [118] = "groupfinder-button-battlegrounds",
    [120] = "groupfinder-button-custom-pve",
}

local function HasPlaystyles()
    return Enum.LFGEntryGeneralPlaystyle ~= nil and GetGeneralPlaystyleString ~= nil
end

local function HasVoiceModes()
    return Enum.LFGEntryVoiceMode ~= nil
end

local VOICE_LABELS
local function VoiceLabels()
    if not VOICE_LABELS and HasVoiceModes() then
        VOICE_LABELS = {
            [Enum.LFGEntryVoiceMode.None] = VOICE_CHAT_MODE_NONE or "None",
            [Enum.LFGEntryVoiceMode.Legacy] = VOICE_CHAT_MODE_LEGACY or "In-game voice",
            [Enum.LFGEntryVoiceMode.Discord] = VOICE_CHAT_MODE_DISCORD or "Discord",
            [Enum.LFGEntryVoiceMode.Custom] = VOICE_CHAT_MODE_CUSTOM or "Other",
        }
    end
    return VOICE_LABELS or {}
end

local function MaxActivities()
    return Constants and Constants.LFGConstsExposed and Constants.LFGConstsExposed.GROUP_FINDER_MAX_ACTIVITY_CAPACITY or 99
end

---------------------------------------------------------------------------
-- State (as LFGListingMixin keeps it)
---------------------------------------------------------------------------
local function AnySelected()
    for _, on in pairs(L.selected) do if on then return true end end
    return false
end

local function SelectedList()
    local list = {}
    for id, on in pairs(L.selected) do if on then list[#list + 1] = id end end
    return list
end

local function SetDirty(on)
    L.dirty = on
    if ns.RefreshListingPage then ns.RefreshListingPage() end
end

local function ResetActivities()
    wipe(L.selected)
    if not L.categoryID then return end
    for _, id in ipairs(ns.GetFilteredActivities(L.categoryID)) do L.selected[id] = false end
    local entry = ns.GetListing()
    if entry then
        for _, id in ipairs(entry.activityIDs) do L.selected[id] = true end
    else
        local info = ns.GetCategoryInfo(L.categoryID)
        if info and info.autoChooseActivity then
            for id in pairs(L.selected) do L.selected[id] = true end
        end
    end
end

function L.SetCategory(id)
    L.categoryID = id
    wipe(L.collapsed)
    ResetActivities()
    -- Collapse groups with nothing at your level, when there are several (as the game does).
    if id then
        local groups = ns.GetGroupedActivities(id)
        local named = 0
        for _, g in ipairs(groups) do if g.groupID ~= 0 then named = named + 1 end end
        if named > 1 then
            local level = UnitLevel("player")
            for _, g in ipairs(groups) do
                if g.groupID ~= 0 then
                    local suggested = false
                    for _, aid in ipairs(g.activities) do
                        local a = ns.GetActivity(aid)
                        if a and a.minLevelSuggestion <= level and level <= a.maxLevelSuggestion then suggested = true break end
                    end
                    L.collapsed[g.groupID] = not suggested
                end
            end
        end
    end
end

local function LoadRoles()
    local r = C_LFGListRoles and (ns.HasListing() and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
        or C_LFGListRoles.GetSavedRoles and C_LFGListRoles.GetSavedRoles())
    if r then
        L.roles.tank, L.roles.healer, L.roles.dps = r.tank and true or false, r.healer and true or false, r.dps and true or false
    end
end

local function SaveRoles()
    if C_LFGListRoles and C_LFGListRoles.SetRoles then
        pcall(C_LFGListRoles.SetRoles, { tank = L.roles.tank, healer = L.roles.healer, dps = L.roles.dps })
    end
end

-- Your current listing into the page (LoadActiveEntry).
function L.LoadActiveEntry()
    local entry = ns.GetListing()
    if not entry then return end
    local a = ns.GetActivity(entry.activityIDs[1])
    L.SetCategory(a and a.categoryID)
    if LFG.CopyActiveEntryInfoToCreationFields then pcall(LFG.CopyActiveEntryInfoToCreationFields) end
    L.newPlayerFriendly = entry.newPlayerFriendly and true or false
    if HasVoiceModes() then L.voiceMode = entry.voiceMode or Enum.LFGEntryVoiceMode.None end
    if entry.generalPlaystyle and entry.generalPlaystyle ~= 0 then L.playstyle = entry.generalPlaystyle end
    L.dirty = false
end

function L.ClearUI()
    L.categoryID = nil
    wipe(L.selected)
    if LFG.ClearCreationTextFields then pcall(LFG.ClearCreationTextFields) end
    if HasVoiceModes() then L.voiceMode = Enum.LFGEntryVoiceMode.None end
    L.dirty = false
end

local function CommentText()
    local sf = _G.LFGListingComment
    local eb = sf and sf.EditBox
    if eb then
        local ok, t = pcall(eb.GetText, eb)
        if ok then return t end
    end
    return ""
end

-- Why the List button is off, or nil when it's ready (UpdatePostButtonEnableState).
function L.PostBlocker()
    local listed = ns.HasListing()
    if not ns.CanEditListing() then
        return listed and (LFG_LIST_ONLY_LEADER_UPDATE or "Only your group leader can change the listing.")
            or (LFG_LIST_ONLY_LEADER_CREATE or "Only your group leader can list the group.")
    end
    local count = #SelectedList()
    if count > MaxActivities() then
        return LFG_LIST_TOO_MANY_ACTIVITIES_SELECTED or "Too many activities selected."
    end
    if HasPlaystyles() and not L.playstyle and not listed then
        return GROUP_FINDER_PLAYSTYLE_REQUIRED or "Pick a playstyle."
    end
    if not L.dirty or (not listed and count == 0) then
        return "" -- nothing to post yet; no error to show
    end
    local info = ns.GetCategoryInfo(L.categoryID)
    if info and info.autoChooseActivity and CommentText() == "" then
        return DESCRIPTION_OF_YOUR_GROUP_MANDATORY or "Add a description of your group."
    end
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
        local members = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)
        local smallest = 0
        for id, on in pairs(L.selected) do
            if on then
                local a = ns.GetActivity(id)
                local cap = a and a.maxNumPlayers or 0
                if cap ~= 0 then
                    if cap <= members then
                        if cap < smallest or smallest == 0 then smallest = cap end
                    end
                end
            end
        end
        if smallest > 0 then
            return (LFG_LIST_TOO_MANY_FOR_ACTIVITY or "Your group is too big for an activity (max %d)."):format(smallest)
        end
    end
    return nil
end

-- List / Update / Delist (CreateOrUpdateListing).
function L.Post()
    if L.PostBlocker() then return end
    local ids = SelectedList()
    local listed = ns.HasListing()

    -- The leader's voice provider follows the listing's voice choice, as the game does.
    if #ids > 0 and HasVoiceModes() and Enum.VoiceProviderID and (not IsInGroup() or UnitIsGroupLeader("player")) then
        local provider
        if L.voiceMode == Enum.LFGEntryVoiceMode.Discord then provider = Enum.VoiceProviderID.Discord
        elseif L.voiceMode == Enum.LFGEntryVoiceMode.Legacy then provider = Enum.VoiceProviderID.Legacy end
        if provider and tonumber(GetCVar("voiceProvider")) ~= provider then SetCVar("voiceProvider", provider) end
    end

    local ok, err
    if listed then
        ns.pendingListingUpdate = true
        if #ids > 0 then
            ok, err = pcall(LFG.UpdateListing, {
                activityIDs = ids,
                newPlayerFriendly = L.newPlayerFriendly and true or false,
                voiceMode = L.voiceMode,
            })
        else
            ok, err = pcall(LFG.RemoveListing)
        end
    elseif #ids > 0 then
        ns.pendingListingUpdate = true
        ok, err = pcall(LFG.CreateListing, {
            activityIDs = ids,
            newPlayerFriendly = L.newPlayerFriendly and true or false,
            generalPlaystyle = L.playstyle,
            voiceMode = L.voiceMode,
        })
    end
    if ok == false then
        ns.pendingListingUpdate = false
        ns.Print("Couldn't post the listing: " .. tostring(err))
        return
    end
    if ok then SaveRoles() end
end

function ns.RemoveListing()
    if not ns.HasListing() then return end
    ns.pendingListingUpdate = true
    local ok, err = pcall(LFG.RemoveListing)
    if not ok then
        ns.pendingListingUpdate = false
        ns.Print("Couldn't delist: " .. tostring(err))
    end
end

-- Saved instance locks, for the warning icon on activities you're part-way through.
local function FetchSavedInstances()
    wipe(L.savedInstances)
    for i = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
        local _, _, _, difficultyID, _, _, _, _, _, _, total, done, _, mapID = GetSavedInstanceInfo(i)
        L.savedInstances[i] = {
            mapID = mapID, difficultyID = difficultyID, total = total, done = done,
            redirected = C_RaidLocks and C_RaidLocks.GetRedirectedDifficultyID and C_RaidLocks.GetRedirectedDifficultyID(mapID, difficultyID),
        }
    end
end

local function InstanceLock(activityID)
    local a = ns.GetActivity(activityID)
    if not (a and a.mapID and a.difficultyID) then return end
    for _, inst in pairs(L.savedInstances) do
        if inst.mapID == a.mapID and inst.done and inst.done > 0 and inst.total and inst.total > 0 then
            if inst.difficultyID == a.difficultyID or inst.redirected == a.redirectedDifficultyID then
                return inst.done, inst.total
            end
        end
    end
end

-- What a dungeon would give you in XP at your level (the 12-level rule): "safe", "partial", "none".
XPFor = function(activityID)
    local lo, hi = ns.GetActivityRange(activityID)
    if not lo then return nil end
    local me = UnitLevel("player") or 0
    if me <= lo + ns.XP_GAP then return "safe" end
    if me <= hi + ns.XP_GAP then return "partial" end
    return "none"
end

-- Things worth knowing before you post (never blockers): activities you'd get no XP from, and
-- instances you're already saved to.
function L.Warnings()
    local noXP, saved = {}, {}
    for id, on in pairs(L.selected) do
        if on then
            if XPFor(id) == "none" then noXP[#noXP + 1] = ns.GetActivityName(id) end
            local done, total = InstanceLock(id)
            if done then saved[#saved + 1] = ("%s (%d/%d)"):format(ns.GetActivityName(id), done, total) end
        end
    end
    table.sort(noXP)
    table.sort(saved)
    local lines = {}
    local function List(t)
        if #t > 3 then return table.concat(t, ", ", 1, 3) .. (" and %d more"):format(#t - 3) end
        return table.concat(t, ", ")
    end
    if #noXP > 0 then lines[#lines + 1] = "No XP for you in: " .. List(noXP) end
    if #saved > 0 then lines[#lines + 1] = "You're saved to: " .. List(saved) end
    return table.concat(lines, ".  ")
end


---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local page, U
local catView, actView, lockedView, details
local rows, list, scroll = {}, {}, 0

local function Flatten()
    wipe(list)
    if not L.categoryID then return end
    local groups = ns.GetGroupedActivities(L.categoryID)
    local named = 0
    for _, g in ipairs(groups) do if g.groupID ~= 0 then named = named + 1 end end
    for _, g in ipairs(groups) do
        if g.groupID == 0 then
            for _, id in ipairs(g.activities) do list[#list + 1] = { activityID = id, indent = 0 } end
        else
            list[#list + 1] = { group = g, collapsible = named > 1 }
            if not (named > 1 and L.collapsed[g.groupID]) then
                for _, id in ipairs(g.activities) do list[#list + 1] = { activityID = id, indent = 1 } end
            end
        end
    end
end

local function GroupState(g)
    local any, all = false, true
    for _, id in ipairs(g.activities) do
        if L.selected[id] then any = true else all = false end
    end
    return any, all
end

local function ToggleActivity(id)
    if L.selected[id] == nil then return end
    L.selected[id] = not L.selected[id]
    SetDirty(ns.HasListing() or AnySelected())
end

local function ToggleGroup(g)
    local any = GroupState(g)
    for _, id in ipairs(g.activities) do
        if L.selected[id] ~= nil then L.selected[id] = not any end
    end
    SetDirty(ns.HasListing() or AnySelected())
end

local function MakeRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -12, -(i - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.expand = CreateFrame("Button", nil, row)
    row.expand:SetSize(16, 16)
    row.expand:SetPoint("LEFT", 4, 0)
    row.expand:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(24, 24)

    row.name = U.Text(row, "LFGActivityEntry")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.name:SetJustifyH("LEFT")

    row.level = U.Text(row, "LFGActivityEntry")
    row.level:SetPoint("RIGHT", -8, 0)
    row.level:SetJustifyH("RIGHT")

    row.lock = row:CreateTexture(nil, "OVERLAY")
    row.lock:SetTexture("Interface\\EncounterJournal\\UI-EJ-WarningTextIcon")
    row.lock:SetSize(16, 16)
    row.lock:SetPoint("LEFT", row.name, "RIGHT", 6, 0)

    local function Click()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        local item = row.item
        if not item then return end
        if item.group then ToggleGroup(item.group) else ToggleActivity(item.activityID) end
    end
    row.check:SetScript("OnClick", Click)
    row:SetScript("OnClick", Click)
    row.expand:SetScript("OnClick", function()
        local item = row.item
        if item and item.group then
            L.collapsed[item.group.groupID] = not L.collapsed[item.group.groupID]
            ns.RefreshListingPage()
        end
    end)
    row:SetScript("OnEnter", function(self)
        local item = self.item
        if not item or item.group then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local a = ns.GetActivity(item.activityID)
        GameTooltip:SetText(a and a.fullName or ns.GetActivityName(item.activityID), 1, 1, 1)
        local lo, hi = ns.GetActivityRange(item.activityID)
        if lo then
            GameTooltip:AddLine(("Mobs ~%d-%d. Full XP while nobody in the group is above %d."):format(lo, hi, lo + ns.XP_GAP),
                0.8, 0.8, 0.8, true)
        end
        local done, total = InstanceLock(item.activityID)
        if done then
            GameTooltip:AddLine((INSTANCE_LOCK_WARNING_PREVIOUSLY_SAVED or "You're saved to this instance: %d/%d bosses."):format(done, total),
                1, 0.3, 0.3, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function RenderActivities()
    Flatten()
    local area = actView.listArea
    local visible = math.max(1, math.floor(area:GetHeight() / ROW_H))
    local maxScroll = math.max(0, #list - visible)
    if scroll > maxScroll then scroll = maxScroll end
    area.scrollbar:SetMinMaxValues(0, maxScroll)
    area.scrollbar:SetValue(scroll)
    area.scrollbar:SetShown(maxScroll > 0)
    local level = UnitLevel("player")
    for i = 1, visible do
        local row = rows[i] or MakeRow(area, i)
        rows[i] = row
        local item = list[scroll + i]
        row.item = item
        if not item then
            row:Hide()
        else
            row:Show()
            row.lock:Hide()
            if item.group then
                local any, all = GroupState(item.group)
                row.expand:SetShown(item.collapsible)
                row.expand:SetNormalTexture(L.collapsed[item.group.groupID] and "Interface\\Buttons\\UI-PlusButton-Up"
                    or "Interface\\Buttons\\UI-MinusButton-Up")
                row.check:ClearAllPoints()
                row.check:SetPoint("LEFT", item.collapsible and 22 or 4, 0)
                row.check:SetChecked(any)
                row.check:SetCheckedTexture(all and "Interface\\Buttons\\UI-CheckBox-Check" or "Interface\\Buttons\\UI-MultiCheck-Up")
                row.name:SetText(item.group.name or "?")
                NativeFont(row.name, "LFGActivityHeader")
                row.level:SetText("")
            else
                local id = item.activityID
                local a = ns.GetActivity(id)
                row.expand:Hide()
                row.check:ClearAllPoints()
                row.check:SetPoint("LEFT", 22 + item.indent * 18, 0)
                row.check:SetChecked(L.selected[id] and true or false)
                row.check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
                row.name:SetText(ns.GetActivityName(id))
                -- The game's own fonts for these: trivial (below you), difficult (above you), normal.
                local fontName = "LFGActivityEntry"
                if a and a.maxLevelSuggestion ~= 0 and a.maxLevelSuggestion < level then
                    fontName = "LFGActivityEntryTrivial"
                elseif a and a.minLevelSuggestion ~= 0 and a.minLevelSuggestion > level then
                    fontName = "LFGActivityEntryDifficult"
                end
                NativeFont(row.name, fontName)
                NativeFont(row.level, fontName)
                local lo, hi = a and a.minLevelSuggestion or 0, a and a.maxLevelSuggestion or 0
                if lo == 0 then
                    row.level:SetText("")
                elseif lo == hi or hi == 0 then
                    row.level:SetText((LFD_LEVEL_FORMAT_SINGLE or "Level %d"):format(lo))
                else
                    row.level:SetText((LFD_LEVEL_FORMAT_RANGE or "Level %d - %d"):format(lo, hi))
                end
                row.lock:SetShown(InstanceLock(id) ~= nil)
                -- What it'd give you in XP, after the level range.
                local st = XPFor(id)
                if st == "none" then
                    row.level:SetText(row.level:GetText() .. "  |cffff5555No XP|r")
                elseif st == "partial" then
                    row.level:SetText(row.level:GetText() .. "  |cffffd133Some XP|r")
                end
            end
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end
end

---------------------------------------------------------------------------
-- The game's comment box, shown in our page. The game reads the listing's description from its
-- own box (and only accepts text you type there), so we borrow that box rather than copy it.
---------------------------------------------------------------------------
local commentHome
local function BorrowComment(holder)
    local sf = _G.LFGListingComment
    if not sf then return false end
    if not commentHome then commentHome = sf:GetParent() end
    sf:SetParent(holder)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    if sf.EditBox then
        sf.EditBox:SetWidth(math.max(200, (holder:GetWidth() or 0) - 50))
        local enabled = not L.categoryID or not LFG.IsPlayerAuthenticatedForLFG or LFG.IsPlayerAuthenticatedForLFG(L.categoryID)
        sf.EditBox:SetEnabled(enabled and ns.CanEditListing())
        if sf.EditBox.Instructions then
            local info = ns.GetCategoryInfo(L.categoryID)
            sf.EditBox.Instructions:SetText(not enabled and (LFG_AUTHENTICATOR_DESCRIPTION_BOX or "Requires an authenticator.")
                or (info and info.autoChooseActivity) and (DESCRIPTION_OF_YOUR_GROUP_MANDATORY or "Describe your group (required)")
                or (DESCRIPTION_OF_YOUR_GROUP or "Describe your group (optional)"))
        end
        if not sf.groupScopeHooked then
            sf.groupScopeHooked = true
            sf.EditBox:HookScript("OnTextChanged", function(_, userInput)
                if userInput and page and page:IsShown() then SetDirty(true) end
            end)
        end
    end
    sf:Show()
    return true
end

local function ReturnComment()
    local sf = _G.LFGListingComment
    if not (sf and commentHome) or sf:GetParent() == commentHome then return end
    sf:SetParent(commentHome)
    sf:ClearAllPoints()
    sf:SetPoint("BOTTOM", 0, 150) -- the game re-anchors it when its own page shows
    sf:SetSize(394, 47)
    if sf.EditBox then sf.EditBox:SetWidth(376) end
end

---------------------------------------------------------------------------
-- Preview: your listing as the Browse list shows it
---------------------------------------------------------------------------
local previewCard
BuildPreview = function(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(64)
    local card = c:CreateTexture(nil, "BACKGROUND")
    card:SetPoint("TOPLEFT", 3, -2)
    card:SetPoint("BOTTOMRIGHT", -3, 0)
    if U.HasAtlas("common-button-list-mid2") then card:SetAtlas("common-button-list-mid2") else card:SetColorTexture(1, 1, 1, 0.05) end
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 10, -11)
    c.icon:SetSize(16, 16)
    c.name = U.Text(c, "GameFontNormalLarge")
    c.name:SetPoint("TOPLEFT", 28, -11)
    c.name:SetJustifyH("LEFT")
    c.sub = U.Text(c, "GameFontDisableLeft")
    c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3)
    c.sub:SetPoint("RIGHT", c, "RIGHT", -96, 0)
    c.sub:SetJustifyH("LEFT")
    c.sub:SetWordWrap(false)
    c.line3 = U.Text(c, "GameFontDisableLeft")
    c.line3:SetPoint("TOPLEFT", c.sub, "BOTTOMLEFT", 0, -2)
    c.line3:SetJustifyH("LEFT")
    c.level = U.Text(c, "GameFontNormalLarge")
    c.level:SetPoint("RIGHT", c, "RIGHT", -84, 0)
    c.roles = {}
    for i = 1, 3 do
        local t = c:CreateTexture(nil, "ARTWORK")
        t:SetSize(22, 22)
        t:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8 - (3 - i) * 23, -8)
        c.roles[i] = t
    end
    c.group = U.Text(c, "GameFontHighlightSmall")
    c.group:SetPoint("TOPRIGHT", -10, -12)
    previewCard = c
    return c
end

UpdatePreview = function()
    local c = previewCard
    if not c then return end
    local _, classFile = UnitClass("player")
    local atlas = classFile and ("groupfinder-icon-class-" .. classFile:lower())
    if atlas and U.HasAtlas(atlas) then
        c.icon:SetAtlas(atlas)
        c.icon:Show()
    elseif classFile then
        U.SetClassIcon(c.icon, classFile)
        c.icon:Show()
    else
        c.icon:Hide()
    end
    c.name:SetText(UnitName("player") or "?")
    c.name:SetTextColor(U.ClassColor(classFile))
    c.level:SetText(tostring(UnitLevel("player") or ""))

    -- What you're listed for, and where you are (as Browse shows a player's zone).
    local ids = SelectedList()
    table.sort(ids, function(x, y) return (ns.GetActivityRange(x) or 0) < (ns.GetActivityRange(y) or 0) end)
    local what
    if #ids > 0 then
        what = ns.GetActivityName(ids[1]) .. (#ids > 1 and ("|cff999999 +%d|r"):format(#ids - 1) or "")
    elseif L.categoryID then
        what = "|cff808080Pick what you're listing for|r"
    else
        what = "|cff808080Pick a category|r"
    end
    local zone = GetRealZoneText and GetRealZoneText() or ""
    c.sub:SetText(what .. (zone ~= "" and ("  |cffd0d0d0" .. zone .. "|r") or ""))

    local extras = {}
    if L.playstyle and HasPlaystyles() then extras[#extras + 1] = "|cff19ff19" .. GetGeneralPlaystyleString(L.playstyle) .. "|r" end
    if L.newPlayerFriendly then
        extras[#extras + 1] = U.HasAtlas("newplayerchat-chaticon-newcomer") and "|A:newplayerchat-chaticon-newcomer:14:14|a" or "|cff80ff80New|r"
    end
    if HasVoiceModes() and L.voiceMode == Enum.LFGEntryVoiceMode.Discord then
        extras[#extras + 1] = "|cff8c9eff" .. (VOICE_CHAT_MODE_DISCORD or "Discord") .. "|r"
    end
    c.line3:SetText(table.concat(extras, "  "))

    -- Solo: the roles you'll play, right-aligned. In a group: its size.
    local inGroup = IsInGroup(LE_PARTY_CATEGORY_HOME)
    c.group:SetShown(inGroup)
    if inGroup then
        c.group:SetText(("Group of %d"):format(GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)))
        for i = 1, 3 do c.roles[i]:Hide() end
    else
        local shown = {}
        for _, key in ipairs(U.ROLE_KEYS) do
            if L.roles[key] then shown[#shown + 1] = key end
        end
        for i = 1, 3 do
            local key = shown[i - (3 - #shown)]
            if key then
                U.ApplyRole(c.roles[i], key)
                c.roles[i]:Show()
            else
                c.roles[i]:Hide()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function ns.RefreshListingPage(filtersChanged)
    if not page or not page:IsShown() then return end
    local listed = ns.HasListing()
    local canEdit = ns.CanEditListing()

    if filtersChanged and L.categoryID then
        local keep = {}
        for id, on in pairs(L.selected) do if on then keep[id] = true end end
        ResetActivities()
        for id in pairs(keep) do if L.selected[id] ~= nil then L.selected[id] = true end end
    end

    page.title:SetText(listed and (LFG_LIST_EDIT or "Your listing") or (LFG_LIST_TAB_1 or "List yourself"))
    if listed then
        local entry = ns.GetListing()
        local n = entry and #entry.activityIDs or 0
        page.subtitle:SetText(("|cff80ff80Listed|r for %s"):format(n == 1 and ns.GetActivityName(entry.activityIDs[1])
            or (LFGBROWSE_ACTIVITY_COUNT or "%d activities"):format(n)))
    else
        page.subtitle:SetText("Not listed")
    end

    -- Which view: locked (not the leader), categories, or activities.
    catView:Hide()
    actView:Hide()
    lockedView:Hide()
    if not canEdit then
        lockedView:Show()
        lockedView.message:SetText(listed and (LFG_LIST_ONLY_LEADER_UPDATE or "Only your group leader can change the listing.")
            or (LFG_LIST_ONLY_LEADER_CREATE or "Only your group leader can list the group."))
        local lines = {}
        local entry = ns.GetListing()
        if entry then
            for _, g in ipairs(ns.GetGroupedActivities(nil, entry.activityIDs)) do
                if g.name then lines[#lines + 1] = "|cffffd100" .. g.name .. "|r" end
                for _, id in ipairs(g.activities) do lines[#lines + 1] = (g.name and "    " or "") .. ns.GetActivityName(id) end
            end
        end
        lockedView.activities:SetText(table.concat(lines, "\n"))
    elseif not L.categoryID then
        catView:Show()
        local cats = {}
        for _, id in ipairs(LFG.GetAvailableCategories and LFG.GetAvailableCategories() or {}) do
            if #ns.GetFilteredActivities(id) > 0 then cats[#cats + 1] = id end
        end
        -- The game's buttons at their own size, stacked and centred in the column below the title.
        local n = math.max(1, #cats)
        local gap = 10
        local stack = n * catView.buttonH + (n - 1) * gap
        local area = (catView:GetHeight() or 400) - 56
        local top = -56 - math.max(0, math.floor((area - stack) / 2))
        for i, id in ipairs(cats) do
            local b = catView.buttons[i] or catView.MakeButton(i)
            b:ClearAllPoints()
            b:SetPoint("TOP", 0, top - (i - 1) * (catView.buttonH + gap))
            b.categoryID = id
            b.text:SetText(ns.GetCategoryName(id) or "?")
            -- What's in it for you: how many activities at your level, or that it's free-form.
            local info = ns.GetCategoryInfo(id)
            if info and info.autoChooseActivity then
                b.sub:SetText("Anything else: you describe it")
            else
                local acts = ns.GetFilteredActivities(id)
                local full = 0
                for _, aid in ipairs(acts) do
                    if ns.ActivityXPClass(aid) == "full" then full = full + 1 end
                end
                b.sub:SetText(("%d at your level%s"):format(#acts,
                    full > 0 and ("  |cff55ff55%d with full XP|r"):format(full) or ""))
            end
            local atlas = CATEGORY_ATLAS[id] or "groupfinder-button-questing"
            if U.HasAtlas(atlas) then b.art:SetAtlas(atlas) b.art:Show() else b.art:Hide() end
            b:Show()
        end
        for i = #cats + 1, #catView.buttons do catView.buttons[i]:Hide() end
    else
        actView:Show()
        actView.header.text:SetText(ns.GetCategoryName(L.categoryID) or "?")
        actView.change:SetShown(not listed)
        actView.allLevels:SetChecked(ns.IgnoringLevelRanges())
        RenderActivities()
    end

    -- Details column
    local hasComment = BorrowComment(details.commentHolder)
    details.commentMissing:SetShown(not hasComment)
    details.playstyleRow:SetShown(HasPlaystyles())
    details.voiceRow:SetShown(HasVoiceModes())
    if details.playstyleDD.Refresh then details.playstyleDD:Refresh() end
    if details.voiceDD.Refresh then details.voiceDD:Refresh() end
    local inGroup = IsInGroup(LE_PARTY_CATEGORY_HOME)
    details.soloRoles:SetShown(not inGroup)
    details.groupRoles:SetShown(inGroup)
    if inGroup then
        if details.roleDD.Refresh then details.roleDD:Refresh() end
        details.rolePoll:SetEnabled(UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
    end
    U.UpdateToggles()
    UpdatePreview()
    details.npf:SetChecked(L.newPlayerFriendly and true or false)
    details.npf:SetEnabled(canEdit)

    -- Buttons (Post / Back-or-Delist), as the game words them.
    local post = page.post
    if listed then
        post:SetText(LFG_POST_GROUP_UPDATE or "Update")
    elseif inGroup then
        post:SetText(LFG_POST_GROUP_PARTY or "List group")
    else
        post:SetText(LFG_POST_GROUP_SOLO or "List self")
    end
    local blocker = L.PostBlocker()
    post:SetEnabled(blocker == nil)
    if blocker and blocker ~= "" then
        page.error:SetTextColor(1, 0.4, 0.4)
        page.error:SetText(blocker)
    else
        -- Not a blocker, just worth knowing before you post: no XP, or already saved.
        page.error:SetTextColor(1, 0.82, 0.2)
        page.error:SetText(L.Warnings())
    end
    page.back:SetText(listed and (LFG_LIST_UNLIST or "Delist") or (BACK or "Back"))
    page.back:SetEnabled(listed and canEdit or (not listed and L.categoryID ~= nil))
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function ns.BuildListingPage(f, p)
    page = p
    U = ns.UI
    LoadRoles()
    L.newPlayerFriendly = GetCVarBool and GetCVarBool("lfgNewPlayerFriendly") or false
    if HasVoiceModes() then L.voiceMode = Enum.LFGEntryVoiceMode.None end

    page.title = U.Text(page, "GameFontNormalLarge")
    page.title:SetPoint("TOPLEFT", 72, -34)
    page.subtitle = U.Text(page, "GameFontHighlight", U.SIZE_LABEL)
    page.subtitle:SetPoint("LEFT", page.title, "RIGHT", 14, -1)

    local LEFT_W = 468
    local left = U.Inset(page)
    left:SetPoint("TOPLEFT", 4, -62)
    left:SetPoint("BOTTOMLEFT", 4, 34)
    left:SetWidth(LEFT_W)

    local right = U.Inset(page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
    right:SetPoint("BOTTOMRIGHT", -6, 34)

    -- Categories
    catView = CreateFrame("Frame", nil, left)
    catView:SetAllPoints()
    local catTitle = U.Text(catView, "GameFontNormalLarge", 16)
    catTitle:SetPoint("TOP", 0, -18)
    catTitle:SetText("What are you looking for?")
    catView.buttons = {}
    -- Built as the game's LFGListingCategoryTemplate: the button is the frame art's own size
    -- (groupfinder-button-cover), with the category's picture inset 5,-8,-5,5 inside it, and the
    -- game's pressed and hover art. Never stretched: the art only lines up at its own size.
    local COVER = "groupfinder-button-cover"
    local coverInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(COVER)
    catView.buttonW = coverInfo and coverInfo.width or 330
    catView.buttonH = coverInfo and coverInfo.height or 64
    function catView.MakeButton(i)
        local b = CreateFrame("Button", nil, catView)
        b:SetSize(catView.buttonW, catView.buttonH)
        b.art = b:CreateTexture(nil, "BACKGROUND")
        b.art:SetPoint("TOPLEFT", 5, -8)
        b.art:SetPoint("BOTTOMRIGHT", -5, 5)
        local cover = b:CreateTexture(nil, "ARTWORK")
        cover:SetAllPoints()
        if U.HasAtlas(COVER) then cover:SetAtlas(COVER) else cover:Hide() end
        if U.HasAtlas("groupfinder-button-cover-down") then
            b:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
            b:GetPushedTexture():SetAtlas("groupfinder-button-cover-down")
        end
        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        if U.HasAtlas("groupfinder-button-cover-hover") then hover:SetAtlas("groupfinder-button-cover-hover")
        else hover:SetColorTexture(1, 1, 1, 0.1) end
        b.text = U.Text(b, "GameFontNormalLarge")
        b.text:SetPoint("LEFT", 20, 7)
        b.sub = U.Text(b, "GameFontHighlightSmall")
        b.sub:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -4)
        b.sub:SetTextColor(0.85, 0.85, 0.85)
        b:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            L.SetCategory(self.categoryID)
            ns.RefreshListingPage()
        end)
        catView.buttons[i] = b
        return b
    end

    -- Activities
    actView = CreateFrame("Frame", nil, left)
    actView:SetAllPoints()
    actView.header = U.HeaderBar(actView)
    actView.header:SetPoint("TOPLEFT", 4, -4)
    actView.header:SetPoint("TOPRIGHT", -4, -4)
    actView.header.text = U.Text(actView.header, "GameFontNormal", U.SIZE_HEAD)
    actView.header.text:SetPoint("LEFT", 12, -4)
    actView.change = U.RedButton(actView.header, "Change category", 120, 20, true)
    actView.change:SetPoint("RIGHT", -10, -4)
    actView.change:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        L.ClearUI()
        ns.RefreshListingPage()
    end)

    actView.allLevels = U.Check(actView, LFG_LIST_IGNORE_SUGGESTED_LEVEL or "Show all level ranges",
        function() return ns.IgnoringLevelRanges() end,
        function(v) ns.SetIgnoreLevelRanges(v) end,
        LFG_LIST_IGNORE_SUGGESTED_LEVEL or "Show all level ranges",
        "Also list activities outside your level's suggested range. Shared with the game's own window.")
    actView.allLevels:SetPoint("BOTTOMLEFT", 10, 6)

    local area = CreateFrame("Frame", nil, actView)
    area:SetPoint("TOPLEFT", 4, -40)
    area:SetPoint("BOTTOMRIGHT", -4, 36)
    actView.listArea = area
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
        if v ~= scroll then scroll = v; RenderActivities() end
    end)
    area.scrollbar = sb
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() then ns.StepScale(delta) else sb:SetValue(scroll - delta * 3) end
    end)
    area:SetScript("OnSizeChanged", function() if actView:IsShown() then RenderActivities() end end)

    -- Locked (not the leader)
    lockedView = CreateFrame("Frame", nil, left)
    lockedView:SetAllPoints()
    lockedView.message = U.Text(lockedView, "GameFontNormalLarge", 16)
    lockedView.message:SetPoint("TOP", 0, -40)
    lockedView.message:SetWidth(LEFT_W - 40)
    local listedFor = U.Text(lockedView, "GameFontNormal", U.SIZE_LABEL + 1)
    listedFor:SetPoint("TOPLEFT", 40, -90)
    listedFor:SetText(LFG_LIST_MY_ACTIVITY_LIST_HEADER or "Listed for:")
    lockedView.activities = U.Text(lockedView, "GameFontHighlight", U.SIZE_LABEL + 1)
    lockedView.activities:SetPoint("TOPLEFT", listedFor, "BOTTOMLEFT", 12, -8)
    lockedView.activities:SetJustifyH("LEFT")

    -- Details column
    details = CreateFrame("Frame", nil, right)
    details:SetAllPoints()
    local DX, LBL_W = 14, 100
    local function Label(text, y, parent)
        local fs = U.Text(parent or details, "GameFontNormal", U.SIZE_LABEL + 1)
        fs:SetPoint("TOPLEFT", DX, y)
        fs:SetText(text)
        return fs
    end

    details.playstyleRow = CreateFrame("Frame", nil, details)
    details.playstyleRow:SetPoint("TOPLEFT", 0, 0)
    details.playstyleRow:SetPoint("TOPRIGHT", 0, 0)
    details.playstyleRow:SetHeight(44)
    Label(PLAYSTYLE or "Playstyle", -20, details.playstyleRow)
    details.playstyleDD = U.Dropdown(details.playstyleRow, 220, function(root)
        if not HasPlaystyles() then return end
        for _, key in ipairs({ "Learning", "FunRelaxed", "FunSerious", "Expert" }) do
            local value = Enum.LFGEntryGeneralPlaystyle[key]
            if value then
                U.Radio(root, GetGeneralPlaystyleString(value), function() return L.playstyle == value end, function()
                    L.playstyle = value
                    ns.RefreshListingPage()
                end)
            end
        end
    end, function()
        if L.playstyle and HasPlaystyles() then return GetGeneralPlaystyleString(L.playstyle) end
        return "|cff999999" .. (GROUP_FINDER_PLAYSTYLE_REQUIRED or "Pick a playstyle") .. "|r"
    end)
    details.playstyleDD:SetPoint("TOPLEFT", DX + LBL_W, -14)
    if details.playstyleDD.SetDefaultText then
        details.playstyleDD:SetDefaultText("|cff999999" .. (GROUP_FINDER_PLAYSTYLE_REQUIRED or "Pick a playstyle") .. "|r")
    end

    details.voiceRow = CreateFrame("Frame", nil, details)
    details.voiceRow:SetPoint("TOPLEFT", 0, -44)
    details.voiceRow:SetPoint("TOPRIGHT", 0, -44)
    details.voiceRow:SetHeight(44)
    Label(VOICE_CHAT or "Voice chat", -20, details.voiceRow)
    details.voiceDD = U.Dropdown(details.voiceRow, 220, function(root)
        if not HasVoiceModes() then return end
        local discord = C_Discord and C_Discord.IsVoiceEnabled and C_Discord.IsVoiceEnabled()
        for _, key in ipairs({ "None", "Discord", "Legacy", "Custom" }) do
            local value = Enum.LFGEntryVoiceMode[key]
            if value and (key ~= "Discord" or discord) then
                U.Radio(root, VoiceLabels()[value], function() return L.voiceMode == value end, function()
                    L.voiceMode = value
                    SetDirty(true)
                end)
            end
        end
    end, function() return VoiceLabels()[L.voiceMode] or (VOICE_CHAT_MODE_NONE or "None") end)
    details.voiceDD:SetPoint("TOPLEFT", DX + LBL_W, -14)

    Label(DESCRIPTION or "Description", -104)
    details.commentHolder = CreateFrame("Frame", nil, details)
    details.commentHolder:SetPoint("TOPLEFT", DX, -126)
    details.commentHolder:SetPoint("TOPRIGHT", -DX, -126)
    details.commentHolder:SetHeight(92)
    details.commentMissing = U.Text(details.commentHolder, "GameFontDisable", U.SIZE_LABEL)
    details.commentMissing:SetPoint("TOPLEFT", 4, -8)
    details.commentMissing:SetPoint("RIGHT", -4, 0)
    details.commentMissing:SetJustifyH("LEFT")
    details.commentMissing:SetText("The game's description box isn't loaded yet. Open the game's Looking for Group window once (hold Shift when opening it), then come back. You can list without a description meanwhile.")

    -- Roles: your own (solo), or your role in the group plus a role check (leader / assist).
    Label(LFG_LIST_YOUR_ROLES or "Your roles", -238)
    details.soloRoles = CreateFrame("Frame", nil, details)
    details.soloRoles:SetPoint("TOPLEFT", DX + LBL_W, -228)
    details.soloRoles:SetSize(330, 34)
    local prev
    for _, key in ipairs(U.ROLE_KEYS) do
        local chip = U.Chip(details.soloRoles, 92, 28, U.ROLE_NAMES[key], function(tex) U.ApplyRole(tex, key) end,
            function() return L.roles[key] end,
            function()
                L.roles[key] = not L.roles[key]
                if ns.HasListing() then SetDirty(true) else SaveRoles() end
            end, U.ROLE_NAMES[key], "Roles you're willing to play. Shown on your listing.")
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 4, 0) else chip:SetPoint("LEFT", 0, 0) end
        prev = chip
    end

    details.groupRoles = CreateFrame("Frame", nil, details)
    details.groupRoles:SetPoint("TOPLEFT", DX + LBL_W, -228)
    details.groupRoles:SetSize(330, 34)
    details.roleDD = U.Dropdown(details.groupRoles, 140, function(root)
        local function IsRole(v) return UnitGroupRolesAssigned("player") == v end
        for _, v in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            U.Radio(root, _G[v] or v, function() return IsRole(v) end, function()
                if UnitSetRole then pcall(UnitSetRole, "player", v) end
            end)
        end
    end, function()
        local r = UnitGroupRolesAssigned("player")
        return r ~= "NONE" and (_G[r] or r) or (NONE or "None")
    end)
    details.roleDD:SetPoint("LEFT", 0, 0)
    details.rolePoll = U.RedButton(details.groupRoles, ROLE_POLL or "Role check", 120, 24)
    details.rolePoll:SetPoint("LEFT", details.roleDD, "RIGHT", 10, 0)
    details.rolePoll:SetMotionScriptsWhileDisabled(true)
    details.rolePoll:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if InitiateRolePoll then InitiateRolePoll() end
    end)
    U.Tooltip(details.rolePoll, ROLE_POLL or "Role check", "Ask everyone in the group to pick their role. Leader or assistant only.")

    -- New player friendly (the game keeps this in a CVar between listings).
    local npfLabel = (U.HasAtlas("newplayerchat-chaticon-newcomer") and "|A:newplayerchat-chaticon-newcomer:16:16|a " or "")
        .. (LFG_LIST_NEW_PLAYER_FRIENDLY or "New player friendly")
    details.npf = U.Check(details, npfLabel, function() return L.newPlayerFriendly end, function(v)
        L.newPlayerFriendly = v
        SetCVar("lfgNewPlayerFriendly", v and "1" or "0")
        SetDirty(true)
    end, LFG_LIST_NEW_PLAYER_FRIENDLY or "New player friendly", "Mark your listing as welcoming to new players.")
    details.npf:SetPoint("TOPLEFT", DX - 4, -270)

    -- How other players will see your listing: the Browse list's own card, filled from this page.
    local previewLabel = U.Text(details, "GameFontNormal")
    previewLabel:SetPoint("TOPLEFT", DX, -312)
    previewLabel:SetText("How others will see you")
    details.preview = BuildPreview(details)
    details.preview:SetPoint("TOPLEFT", DX - 3, -330)
    details.preview:SetPoint("TOPRIGHT", -DX + 3, -330)
    local note = U.Text(details, "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", details.preview, "BOTTOMLEFT", 3, -6)
    note:SetPoint("RIGHT", -DX, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Listed through the game's own group finder: it shows in the game's window too.")

    -- Bottom: error / status, then Back-or-Delist and List
    page.post = U.RedButton(page, LFG_POST_GROUP_SOLO or "List self", 150, 24)
    page.post:SetPoint("BOTTOMRIGHT", -24, 5)
    page.post:SetMotionScriptsWhileDisabled(true)
    page.post:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        L.Post()
    end)
    page.back = U.RedButton(page, BACK or "Back", 120, 24)
    page.back:SetPoint("RIGHT", page.post, "LEFT", -8, 0)
    page.back:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if ns.HasListing() then
            ns.RemoveListing()
        else
            L.ClearUI()
            ns.RefreshListingPage()
        end
    end)
    page.error = U.Text(page, "GameFontNormal")
    page.error:SetPoint("BOTTOMLEFT", 14, 10)
    page.error:SetPoint("RIGHT", page.back, "LEFT", -16, 0)
    page.error:SetJustifyH("LEFT")
    page.error:SetTextColor(1, 0.4, 0.4)

    -- Events the game's listing page listens to.
    local ev = CreateFrame("Frame", nil, page)
    for _, e in ipairs({ "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_ROLE_UPDATE", "PLAYER_ROLES_ASSIGNED",
        "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "GROUP_LEFT", "UPDATE_INSTANCE_INFO", "LFG_LIST_AVAILABILITY_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event, arg1)
        if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
            if ns.HasListing() then L.LoadActiveEntry() else L.dirty = AnySelected() end
        elseif event == "LFG_LIST_ROLE_UPDATE" then
            LoadRoles()
        elseif event == "GROUP_LEFT" then
            if arg1 == LE_PARTY_CATEGORY_HOME and not ns.HasListing() then L.ClearUI() end
        elseif event == "UPDATE_INSTANCE_INFO" then
            FetchSavedInstances()
        elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
            L.ClearUI()
            L.LoadActiveEntry()
        end
        ns.RefreshListingPage()
    end)

    page:SetScript("OnShow", function()
        if ns.HasListing() then
            L.LoadActiveEntry()
            LoadRoles()
        elseif not L.dirty and HasVoiceModes() and C_VoiceChat and C_VoiceChat.GetActiveChannelID then
            -- Default voice choice from the voice channel you're in, as the game does.
            local inChannel = C_VoiceChat.GetActiveChannelID()
            if inChannel and Enum.VoiceProviderID and C_VoiceChat.GetActiveVoiceProviderID then
                L.voiceMode = C_VoiceChat.GetActiveVoiceProviderID() == Enum.VoiceProviderID.Discord
                    and Enum.LFGEntryVoiceMode.Discord or Enum.LFGEntryVoiceMode.Legacy
            else
                L.voiceMode = Enum.LFGEntryVoiceMode.None
            end
        end
        if RequestRaidInfo then RequestRaidInfo() end
        FetchSavedInstances()
        ns.RefreshListingPage()
    end)
    page:SetScript("OnHide", ReturnComment)
end
