-- Seeker LFG: /seeker selftest. Checks, in the game, everything the addon depends on: the game's
-- LFG functions, the templates, art and fonts it borrows, the game data it reads, and the add-ons it
-- works with. Prints a summary; "/seeker selftest all" lists every check.
local ADDON, ns = ...

local function Has(path)
    local t = _G
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return false end
        t = t[part]
    end
    return t ~= nil
end

local function HasAtlas(atlas)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local holder
local function CanCreate(frameType, template)
    holder = holder or CreateFrame("Frame")
    holder:Hide()
    local ok, f = pcall(CreateFrame, frameType, nil, holder, template)
    if ok and f then f:Hide() return true end
    return false
end

local FUNCTIONS = {
    "C_LFGList.Search", "C_LFGList.GetFilteredSearchResults", "C_LFGList.GetSearchResultInfo",
    "C_LFGList.GetSearchResultPlayerInfo", "C_LFGList.GetSearchResultLeaderInfo",
    "C_LFGList.GetSearchResultMemberCounts", "C_LFGList.GetSearchResultEncounterInfo",
    "C_LFGList.GetAvailableCategories", "C_LFGList.GetAvailableActivities", "C_LFGList.GetActivityGroupInfo",
    "C_LFGList.GetActivityInfoTable", "C_LFGList.GetLfgCategoryInfo",
    "C_LFGList.CreateListing", "C_LFGList.UpdateListing", "C_LFGList.RemoveListing",
    "C_LFGList.HasActiveEntryInfo", "C_LFGList.GetActiveEntryInfo",
    "C_LFGList.CopyActiveEntryInfoToCreationFields", "C_LFGList.ClearCreationTextFields",
    "C_LFGList.IsPlayerAuthenticatedForLFG",
    "C_LFGListRoles.GetRoles", "C_LFGListRoles.SetRoles", "C_LFGListRoles.GetSavedRoles",
    "C_FriendList.SendWho", "C_FriendList.GetWhoInfo", "C_FriendList.GetNumWhoResults", "C_FriendList.SetWhoToUi",
    "C_PartyInfo.InviteUnit", "C_Map.GetMapInfo", "C_Map.GetMapChildrenInfo",
    "MenuUtil.CreateContextMenu", "Settings.RegisterCanvasLayoutCategory", "GetGeneralPlaystyleString",
}

local TEMPLATES = {
    { "Frame", "ButtonFrameTemplate" }, { "Frame", "InsetFrameTemplate" },
    { "DropdownButton", "WowStyle1DropdownTemplate" }, { "Frame", "LargeSideTabButtonTemplate" },
    { "Button", "LFGEyeBigTemplate" }, { "Frame", "LFGEyeTemplate" }, { "EditBox", "SearchBoxTemplate" }, { "EditBox", "InputBoxTemplate" },
    { "CheckButton", "UICheckButtonTemplate" }, { "Button", "UIPanelButtonTemplate" },
}

local ATLASES = {
    "groupfinder-icon-role-large-tank", "groupfinder-icon-role-large-heal", "groupfinder-icon-role-large-dps",
    "groupfinder-icon-emptyslot", "groupfinder-icon-leader", "groupfinder-icon-friend", "groupfinder-icon-class-warrior",
    "common-button-list-mid2", "common-button-list-mid2-hover", "common-button-list-collapseExpand",
    "common-sidetab", "groupfinder-eye-frame", "groupfinder-button-dungeons", "newplayerchat-chaticon-newcomer",
    "minimal-scrollbar-small-thumb-middle", "questlog-icon-setting",
}

local FONTS = {
    "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontDisable", "GameFontDisableLeft", "GameFontDisableSmallLeft", "LFGActivityHeader", "LFGActivityEntry",
    "LFGActivityEntryTrivial", "LFGActivityEntryDifficult", "UserScaledFontGameNormalSmall",
}

function ns.SelfTest(arg)
    local verbose = arg == "all"
    local pass, fail, results = 0, 0, {}
    local function Check(group, name, ok, detail)
        if ok then pass = pass + 1 else fail = fail + 1 end
        results[#results + 1] = { group = group, name = name, ok = ok, detail = detail }
    end

    for _, fn in ipairs(FUNCTIONS) do Check("Game functions", fn, Has(fn)) end
    for _, t in ipairs(TEMPLATES) do Check("Templates", t[2], CanCreate(t[1], t[2])) end
    for _, a in ipairs(ATLASES) do Check("Art", a, HasAtlas(a)) end
    for _, f in ipairs(FONTS) do Check("Fonts", f, _G[f] ~= nil) end

    -- Game data
    local cats = ns.GetCategories()
    Check("Game data", "categories at your level", #cats > 0, #cats .. " found")
    local dungeons, placed = 0, 0
    for _, c in ipairs(cats) do
        for _, id in ipairs(C_LFGList.GetAvailableActivities(c.id) or {}) do
            local a = ns.GetActivity(id)
            if a and a.maxNumPlayers == 5 then
                dungeons = dungeons + 1
                if ns.GetActivityContinent(id) then placed = placed + 1 end
            end
        end
    end
    Check("Game data", "dungeons with a known continent", dungeons > 0 and placed == dungeons,
        ("%d of %d"):format(placed, dungeons))
    local here = GetRealZoneText and GetRealZoneText()
    Check("Game data", "your zone's continent", ns.GetZoneContinent(here) ~= nil,
        (here or "?") .. " -> " .. tostring(ns.GetZoneContinent(here)))

    -- What Seeker works with
    Check("Works with", "the game's group finder (for its description box)", _G.LFGListingComment ~= nil,
        _G.LFGListingComment and "loaded" or "not loaded: open the game's Looking for Group window once")
    Check("Works with", "Whisper Messenger (optional)", true, ns.HasWhisperMessenger() and "installed, connected" or "not installed")

    ns.Print(("Self-test: %d passed, %d failed."):format(pass, fail))
    local group
    for _, r in ipairs(results) do
        if verbose or not r.ok then
            if r.group ~= group then
                group = r.group
                print("  |cffffd100" .. group .. "|r")
            end
            print(("    %s %s%s"):format(r.ok and "|cff55ff55ok|r" or "|cffff5555FAILED|r", r.name,
                r.detail and ("  |cff999999" .. r.detail .. "|r") or ""))
        end
    end
    if not verbose then print("  |cff999999/seeker selftest all lists every check.|r") end
    return pass, fail
end
