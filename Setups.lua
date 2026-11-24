-- Seeker LFG: saved filter setups. Save the filters you've set ("Tanking on my warrior",
-- "Healing, any XP") and switch back to them in one click: cog menu > Filter setups, or
-- /seeker setup. Account-wide, so any character can use any setup.
local ADDON, ns = ...
local L = ns.L -- translations (Locale.lua)

-- What a setup keeps: the filters (not your hidden players or words, which always apply), what
-- you browse (category and activities) and the sort.
local FILTER_KEYS = {
    "xpMode", "includeSelf", "levelMin", "levelMax", "playerRoles", "groupNeeds", "classes",
    "hideFull", "hideUnknown", "hideFar", "greyOutsidePick",
}

function ns.SetupNames()
    local names = {}
    for name in pairs(ns.db.presets) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function ns.SaveSetup(name)
    name = strtrim(name or "")
    if name == "" then return end
    local db = ns.db
    local s = { filters = {}, categoryID = db.categoryID, activityIDs = ns.DeepCopy(db.activityIDs), sortMode = db.sortMode }
    for _, k in ipairs(FILTER_KEYS) do s.filters[k] = ns.DeepCopy(db.filters[k]) end
    db.presets[name] = s
    ns.Print((L["Saved your filters as \"%s\". Switch to it from the cog menu > Filter setups, or /seeker setup %s."]):format(name, name))
end

function ns.ApplySetup(name)
    local s = ns.db.presets[name]
    if not s then
        ns.Print((L["There's no filter setup called \"%s\". /seeker setup lists them."]):format(tostring(name)))
        return
    end
    local db = ns.db
    for _, k in ipairs(FILTER_KEYS) do
        local v = s.filters and s.filters[k]
        -- Level limits may be empty on purpose; a missing table (a setup from before it existed) is left alone.
        if v ~= nil or k == "levelMin" or k == "levelMax" then ns.SetDBPath({ "filters", k }, v) end
    end
    if s.categoryID then
        db.categoryID, db.searchSelf = s.categoryID, false
        ns.SetDBPath({ "activityIDs" }, s.activityIDs or {})
    end
    if s.sortMode then db.sortMode = s.sortMode end
    if ns.RefreshFilterPanel then ns.RefreshFilterPanel() end
    if ns.RefreshDropdowns then ns.RefreshDropdowns() end
    if ns.RequestSearch then ns.RequestSearch() end
    ns.Print((L["Filters set to \"%s\"."]):format(name))
end

function ns.DeleteSetup(name)
    if ns.db.presets[name] then
        ns.db.presets[name] = nil
        ns.Print((L["Deleted the filter setup \"%s\"."]):format(name))
    end
end

StaticPopupDialogs.SEEKERLFG_SAVE_SETUP = {
    text = L["Save your current filters as:"],
    button1 = SAVE or "Save",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1,
    maxLetters = 40,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        if eb then eb:SetText("") eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox
        if eb then ns.SaveSetup(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        ns.SaveSetup(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function ns.PromptSaveSetup()
    if StaticPopup_Show then StaticPopup_Show("SEEKERLFG_SAVE_SETUP") end
end

-- The cog menu's Filter setups submenu: each setup (click to use it), save, delete.
function ns.AddSetupsMenu(root)
    local menu = root:CreateButton(L["Filter setups"])
    local names = ns.SetupNames()
    for _, name in ipairs(names) do
        menu:CreateButton(name, function() ns.ApplySetup(name) end)
    end
    if #names > 0 then menu:CreateDivider() end
    menu:CreateButton(L["Save current filters..."], function() ns.PromptSaveSetup() end)
    if #names > 0 then
        local del = menu:CreateButton(L["Delete"])
        for _, name in ipairs(names) do
            del:CreateButton(name, function() ns.DeleteSetup(name) end)
        end
    end
end
