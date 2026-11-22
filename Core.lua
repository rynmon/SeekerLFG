-- Seeker: data layer (search results, XP rule, filters, actions).
-- Behaviour mirrors Forever's own group finder (Blizzard_GroupFinder_VanillaStyle) where it has one.
local ADDON, ns = ...

ns.NAME = "Seeker LFG"

-- WoW Forever hotfix (Nov 2026): kill XP is nullified when the highest-level
-- party member is MORE than 12 levels above the enemy.
ns.XP_GAP = 12

local defaults = {
    categoryID = nil,
    activityIDs = {},      -- set: activityID -> true (none = the whole category, as the game does)
    searchSelf = false,    -- "Your listing" picked in the category dropdown
    minimapButton = true,
    replaceNative = false, -- open Seeker in place of the game's Looking for Group window
    useWhisperMessenger = true, -- whisper through Whisper Messenger when it's installed
    minimapAngle = 200,
    tab = "browse",
    sortMode = "xp",       -- see ns.SORT_MODES
    alerts = {
        enabled = true,    -- tell me about new listings that match my filters
        fullXPOnly = false,
        sound = true,
        flash = true,      -- flash the game's taskbar icon when it's in the background
    },
    filters = {
        text = "",
        xpMode = "strict",   -- "off" | "strict" | "lenient"
        includeSelf = true,  -- count my own level as a party member for the XP check
        levelMin = nil,
        levelMax = nil,
        -- Toggles: none on means no filter.
        playerRoles = { tank = false, healer = false, dps = false }, -- player is willing to...
        groupNeeds = { tank = false, healer = false, dps = false },  -- group still has room for...
        classes = {},                                                -- players of these classes only
        hideFull = false,
        hideUnknown = false,
        hideFar = false,     -- hide solo players standing on another continent from their dungeon
    },
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.InitDB()
    SeekerLFGDB = SeekerLFGDB or {}
    -- 0.6 kept one activity; carry it over.
    if SeekerLFGDB.activityID then
        SeekerLFGDB.activityIDs = { [SeekerLFGDB.activityID] = true }
        SeekerLFGDB.activityID = nil
    end
    -- 0.8 opens at the game's own window height: forget sizes saved for the old, larger window.
    if (SeekerLFGDB.layout or 0) < 2 then
        SeekerLFGDB.scale, SeekerLFGDB.pos = nil, nil
        SeekerLFGDB.layout = 2
    end
    ApplyDefaults(SeekerLFGDB, defaults)
    ns.db = SeekerLFGDB
end

function ns.Print(...)
    print("|cff66ccffSeeker LFG|r:", ...)
end

local LFG = C_LFGList or {}
ns.LFG = LFG

---------------------------------------------------------------------------
-- Categories / activities (as the game lists them)
---------------------------------------------------------------------------
function ns.GetCategoryName(id)
    if not id then return nil end
    if LFG.GetLfgCategoryInfo then
        local ci = LFG.GetLfgCategoryInfo(id)
        return ci and ci.name
    end
end

function ns.GetCategoryInfo(id)
    return id and LFG.GetLfgCategoryInfo and LFG.GetLfgCategoryInfo(id)
end

local activityCache = {}
function ns.GetActivity(id)
    if not id then return nil end
    local a = activityCache[id]
    if a == nil then
        a = (LFG.GetActivityInfoTable and LFG.GetActivityInfoTable(id)) or false
        activityCache[id] = a
    end
    return a or nil
end

function ns.GetActivityName(id, short)
    local a = ns.GetActivity(id)
    if not a then return "?" end
    -- The game prefers the short name for consistency.
    if a.shortName and a.shortName ~= "" then return a.shortName end
    return a.fullName or "?"
end

-- Approximate enemy level range for an activity: the suggested range, else the entry range.
function ns.GetActivityRange(id)
    local a = ns.GetActivity(id)
    if not a then return nil end
    local lo = a.minLevelSuggestion
    if not lo or lo == 0 then lo = a.minLevel end
    local hi = a.maxLevelSuggestion
    if not hi or hi == 0 then hi = a.maxLevel end
    if not lo or lo == 0 then return nil end
    if not hi or hi < lo then hi = lo end
    return lo, hi
end

function ns.IgnoringLevelRanges()
    return GetCVarBool and GetCVarBool("disableSuggestedLevelActivityFilter")
end

function ns.SetIgnoreLevelRanges(on)
    SetCVar("disableSuggestedLevelActivityFilter", on and "1" or "0")
end

-- LFGUtil_GetFilteredActivities: the category's activities, minus those outside your level's
-- suggested range unless "show all level ranges" is on (your own listing's are always kept).
function ns.GetFilteredActivities(categoryID, groupID)
    if not categoryID or not LFG.GetAvailableActivities then return {} end
    local activities = LFG.GetAvailableActivities(categoryID, groupID) or {}
    if not ns.IgnoringLevelRanges() then
        local active = LFG.GetActiveEntryInfo and LFG.GetActiveEntryInfo()
        local level = UnitLevel("player")
        for i = #activities, 1, -1 do
            local id = activities[i]
            if not (active and tContains(active.activityIDs, id)) then
                local a = ns.GetActivity(id)
                if a and ((a.minLevelSuggestion > 0 and a.minLevelSuggestion > level)
                    or (a.maxLevelSuggestion > 0 and a.maxLevelSuggestion < level)) then
                    table.remove(activities, i)
                end
            end
        end
    end
    return activities
end

function ns.GetActivityGroupName(groupID)
    if groupID and groupID ~= 0 and LFG.GetActivityGroupInfo then
        return (LFG.GetActivityGroupInfo(groupID))
    end
end

local function SortActivities(list)
    table.sort(list, function(x, y)
        local a, b = ns.GetActivity(x), ns.GetActivity(y)
        if a and b and a.orderIndex ~= b.orderIndex then return (a.orderIndex or 0) < (b.orderIndex or 0) end
        local na, nb = ns.GetActivityName(x), ns.GetActivityName(y)
        if na ~= nb then return na < nb end
        return x < y
    end)
end

-- Activities grouped as the game groups them: { {groupID, name, activities = {...}}, ... },
-- free-floating activities (group 0) first.
function ns.GetGroupedActivities(categoryID, activities)
    activities = activities or ns.GetFilteredActivities(categoryID)
    local byGroup = {}
    for _, id in ipairs(activities) do
        local a = ns.GetActivity(id)
        if a then
            local g = a.groupFinderActivityGroupID or 0
            byGroup[g] = byGroup[g] or {}
            table.insert(byGroup[g], id)
        end
    end
    local out = {}
    for g, list in pairs(byGroup) do
        SortActivities(list)
        local name, order = nil, 0
        if g ~= 0 and LFG.GetActivityGroupInfo then name, order = LFG.GetActivityGroupInfo(g) end
        out[#out + 1] = { groupID = g, name = name, order = order or 0, activities = list }
    end
    table.sort(out, function(a, b)
        if (a.groupID == 0) ~= (b.groupID == 0) then return a.groupID == 0 end
        if a.order ~= b.order then return a.order < b.order end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

-- Categories that have anything to show at your level (as the game's dropdown does).
function ns.GetCategories()
    local out = {}
    for _, id in ipairs(LFG.GetAvailableCategories and LFG.GetAvailableCategories() or {}) do
        if #ns.GetFilteredActivities(id) > 0 then
            out[#out + 1] = { id = id, name = ns.GetCategoryName(id) or ("Category " .. id) }
        end
    end
    return out
end

-- What each activity would give you in XP at your level, for the activity menu's sections.
ns.ACTIVITY_SECTIONS = {
    { key = "full", title = "Full XP for you", color = "|cff55ff55" },
    { key = "above", title = "Above your level", color = "|cffff9933" },
    { key = "some", title = "Some XP (only the tougher mobs)", color = "|cffffd133" },
    { key = "none", title = "No XP for you", color = "|cff8a8a8a" },
    { key = "other", title = "Other", color = "|cff999999" },
}

function ns.ActivityXPClass(id)
    local lo, hi = ns.GetActivityRange(id)
    if not lo then return "other" end
    local me = UnitLevel("player") or 0
    if me > hi + ns.XP_GAP then return "none" end
    if me > lo + ns.XP_GAP then return "some" end
    if lo > me then return "above" end
    return "full"
end

-- The category's activities in those sections, lowest level first in each.
function ns.ActivitySections(categoryID)
    local out = {}
    for _, sec in ipairs(ns.ACTIVITY_SECTIONS) do out[sec.key] = {} end
    for _, id in ipairs(ns.GetFilteredActivities(categoryID)) do
        local list = out[ns.ActivityXPClass(id)]
        list[#list + 1] = id
    end
    for _, list in pairs(out) do
        table.sort(list, function(x, y)
            local lx, hx = ns.GetActivityRange(x)
            local ly, hy = ns.GetActivityRange(y)
            lx, ly = lx or 999, ly or 999
            if lx ~= ly then return lx < ly end
            if (hx or 999) ~= (hy or 999) then return (hx or 999) < (hy or 999) end
            return ns.GetActivityName(x) < ns.GetActivityName(y)
        end)
    end
    return out
end

-- Browse selection
function ns.SelectedActivities()
    local list = {}
    for id, on in pairs(ns.db.activityIDs) do
        if on then list[#list + 1] = id end
    end
    if #list == 0 then return nil end
    SortActivities(list)
    return list
end

function ns.IsActivitySelected(id)
    return ns.db.activityIDs[id] and true or false
end

function ns.SetActivitySelected(id, on)
    ns.db.activityIDs[id] = on and true or nil
end

function ns.ClearActivitySelection()
    wipe(ns.db.activityIDs)
end

---------------------------------------------------------------------------
-- Your own listing
---------------------------------------------------------------------------
function ns.HasListing()
    return LFG.HasActiveEntryInfo and LFG.HasActiveEntryInfo() or false
end

function ns.GetListing()
    return LFG.GetActiveEntryInfo and LFG.GetActiveEntryInfo()
end

function ns.CanEditListing()
    return not IsInGroup(LE_PARTY_CATEGORY_HOME) or UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
end

---------------------------------------------------------------------------
-- Continents: where a dungeon is, and where a player is standing
---------------------------------------------------------------------------
-- Which continent each dungeon's entrance is on, by the instance's map ID (the activity's mapID),
-- so it works in every client language. Continent names come from the game's own map data,
-- in your language, so they match the zone-to-continent lookup below.
local KALIMDOR_MAP, EASTERN_MAP = 1414, 1415
local KALIMDOR, EASTERN = "KALIMDOR", "EASTERN"
local INSTANCE_CONTINENT = {
    [389] = KALIMDOR, -- Ragefire Chasm
    [43] = KALIMDOR,  -- Wailing Caverns
    [48] = KALIMDOR,  -- Blackfathom Deeps
    [47] = KALIMDOR,  -- Razorfen Kraul
    [129] = KALIMDOR, -- Razorfen Downs
    [209] = KALIMDOR, -- Zul'Farrak
    [349] = KALIMDOR, -- Maraudon
    [429] = KALIMDOR, -- Dire Maul
    [249] = KALIMDOR, -- Onyxia's Lair
    [509] = KALIMDOR, -- Ruins of Ahn'Qiraj
    [531] = KALIMDOR, -- Temple of Ahn'Qiraj
    [36] = EASTERN,   -- The Deadmines
    [33] = EASTERN,   -- Shadowfang Keep
    [34] = EASTERN,   -- The Stockade
    [90] = EASTERN,   -- Gnomeregan
    [189] = EASTERN,  -- Scarlet Monastery
    [70] = EASTERN,   -- Uldaman
    [109] = EASTERN,  -- Sunken Temple
    [230] = EASTERN,  -- Blackrock Depths
    [229] = EASTERN,  -- Blackrock Spire
    [289] = EASTERN,  -- Scholomance
    [329] = EASTERN,  -- Stratholme
    [409] = EASTERN,  -- Molten Core
    [469] = EASTERN,  -- Blackwing Lair
    [309] = EASTERN,  -- Zul'Gurub
    [533] = EASTERN,  -- Naxxramas
}

-- Fallback for activities without a known map ID: English names (lowercase, substring).
local DUNGEON_NAMES = {
    { "ragefire", KALIMDOR }, { "wailing caverns", KALIMDOR }, { "blackfathom", KALIMDOR },
    { "razorfen", KALIMDOR }, { "zul'farrak", KALIMDOR }, { "maraudon", KALIMDOR },
    { "dire maul", KALIMDOR }, { "onyxia", KALIMDOR }, { "ahn'qiraj", KALIMDOR },
    { "deadmines", EASTERN }, { "shadowfang", EASTERN }, { "stockade", EASTERN },
    { "gnomeregan", EASTERN }, { "scarlet", EASTERN }, { "uldaman", EASTERN },
    { "sunken temple", EASTERN }, { "atal'hakkar", EASTERN }, { "blackrock", EASTERN },
    { "scholomance", EASTERN }, { "stratholme", EASTERN }, { "molten core", EASTERN },
    { "blackwing", EASTERN }, { "zul'gurub", EASTERN }, { "naxxramas", EASTERN },
}

local continentNames
local function ContinentName(key)
    if not continentNames then
        continentNames = { [KALIMDOR] = "Kalimdor", [EASTERN] = "Eastern Kingdoms" }
        if C_Map and C_Map.GetMapInfo then
            local k, e = C_Map.GetMapInfo(KALIMDOR_MAP), C_Map.GetMapInfo(EASTERN_MAP)
            if k and k.name then continentNames[KALIMDOR] = k.name end
            if e and e.name then continentNames[EASTERN] = e.name end
        end
    end
    return continentNames[key]
end

local activityContinent = {}
function ns.GetActivityContinent(id)
    if not id then return nil end
    local c = activityContinent[id]
    if c == nil then
        c = false
        local a = ns.GetActivity(id)
        local key = a and a.mapID and INSTANCE_CONTINENT[a.mapID]
        if not key then
            local name = ((a and a.fullName) or ns.GetActivityName(id)):lower()
            for _, pair in ipairs(DUNGEON_NAMES) do
                if name:find(pair[1], 1, true) then key = pair[2] break end
            end
        end
        c = key and ContinentName(key) or false
        activityContinent[id] = c
    end
    return c or nil
end

-- The instance's own name in your language (for "already at the dungeon").
function ns.GetActivityInstanceName(id)
    local a = ns.GetActivity(id)
    if a and a.mapID and GetRealZoneText then
        local ok, name = pcall(GetRealZoneText, a.mapID)
        if ok and name and name ~= "" then return name end
    end
end

-- Zone name -> continent name, from the game's own map tree.
local zoneContinent
local function AddContinent(mapID)
    local info = C_Map.GetMapInfo(mapID)
    if not info or not info.name then return end
    local cname = info.name
    zoneContinent[cname] = cname
    for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, nil, true) or {}) do
        if child.name and not zoneContinent[child.name] then
            zoneContinent[child.name] = cname
        end
    end
end

local function BuildZoneMap()
    zoneContinent = {}
    if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then return end
    local id = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local top
    while id do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        top = id
        if not info.parentMapID or info.parentMapID == 0 then break end
        id = info.parentMapID
    end
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    if top then
        for _, c in ipairs(C_Map.GetMapChildrenInfo(top, continentType, true) or {}) do
            AddContinent(c.mapID)
        end
    end
    if not next(zoneContinent) then
        pcall(AddContinent, 1414)
        pcall(AddContinent, 1415)
    end
end

-- Every dungeon and raid, by its name in your language (from the game's own instance names),
-- with its continent and whether it's a raid, so a zone can be told to be an instance even when
-- nobody listed for it.
local RAID_MAPS = { [249] = true, [509] = true, [531] = true, [409] = true, [469] = true, [309] = true, [533] = true }
local function BareName(s) return ((s or ""):lower():gsub("^the ", ""):gsub("%s*%b()", "")) end
local instances
local function BuildInstances()
    instances = {}
    if not GetRealZoneText then return end
    for mapID, key in pairs(INSTANCE_CONTINENT) do
        local ok, name = pcall(GetRealZoneText, mapID)
        if ok and name and name ~= "" then
            instances[BareName(name)] = { name = name, continent = key, raid = RAID_MAPS[mapID] or false }
        end
    end
end

-- The instance this zone is, if it's a dungeon or raid: { name, continent key, raid }.
function ns.InstanceAt(zone)
    if not zone or zone == "" then return nil end
    if not instances or not next(instances) then BuildInstances() end
    return instances[BareName(zone)]
end

function ns.GetZoneContinent(areaName)
    if not areaName or areaName == "" then return nil end
    if not zoneContinent or not next(zoneContinent) then BuildZoneMap() end
    local c = zoneContinent[areaName]
    if c then return c end
    -- Inside a dungeon: the continent its entrance is on.
    local inst = ns.InstanceAt(areaName)
    return inst and ContinentName(inst.continent) or nil
end

-- Which of an entry's activities matter: the ones you picked (if it has any), else all of them.
local function RelevantActivities(e)
    local sel = ns.SelectedActivities()
    if sel then
        local out = {}
        for _, id in ipairs(sel) do
            if tContains(e.activityIDs, id) then out[#out + 1] = id end
        end
        if #out > 0 then return out end
    end
    return e.activityIDs
end
ns.RelevantActivities = RelevantActivities

-- Where someone standing in this zone is, for these dungeons: "in" (inside or at one of them),
-- "near" (same continent), "far" (another continent), or nil when it can't be told. Also returns
-- the dungeon's activity ID when they're in it.
function ns.ZoneStatus(zone, activityIDs)
    if not zone or zone == "" or not activityIDs or #activityIDs == 0 then return nil end
    local function Bare(s) return ((s or ""):lower():gsub("^the ", ""):gsub("%s*%b()", "")) end
    local here = Bare(zone)
    for _, id in ipairs(activityIDs) do
        local a = ns.GetActivity(id)
        local dungeon = Bare(a and a.fullName or ns.GetActivityName(id))
        local instance = Bare(ns.GetActivityInstanceName(id))
        if (instance ~= "" and here == instance)
            or (dungeon ~= "" and (here == dungeon or dungeon:find(here, 1, true) or here:find(dungeon, 1, true))) then
            return "in", id
        end
    end
    local cont = ns.GetZoneContinent(zone)
    if not cont then return nil end
    local status
    for _, id in ipairs(activityIDs) do
        local dc = ns.GetActivityContinent(id)
        if dc then
            if dc == cont then return "near" end
            status = "far"
        end
    end
    return status
end

-- For a solo player: "near" (same continent as one of their dungeons), "far", or "unknown".
function ns.EvaluateDistance(e)
    local p = e.leader
    e.continent = p and ns.GetZoneContinent(p.areaName)
    e.dungeonContinent = nil
    e.distance = "unknown"
    e.inDungeon = false
    local acts = RelevantActivities(e)

    -- Already inside (or at) the dungeon they listed for: "The Deadmines" vs "Deadmines".
    local function Bare(s) return ((s or ""):lower():gsub("^the ", ""):gsub("%s*%b()", "")) end
    local here = p and Bare(p.areaName)
    if here and here ~= "" then
        for _, id in ipairs(acts) do
            local a = ns.GetActivity(id)
            local dungeon = Bare(a and a.fullName or ns.GetActivityName(id))
            -- The instance's own name, in your language, as the game reports where they are.
            local instance = Bare(ns.GetActivityInstanceName(id))
            if (instance ~= "" and here == instance)
                or (dungeon ~= "" and (here == dungeon or dungeon:find(here, 1, true) or here:find(dungeon, 1, true))) then
                e.distance, e.inDungeon = "near", true
                e.dungeonContinent = ns.GetActivityContinent(id)
                e.continent = e.continent or e.dungeonContinent
                return
            end
        end
    end

    if not e.continent then return end
    for _, id in ipairs(acts) do
        local dc = ns.GetActivityContinent(id)
        if dc then
            e.dungeonContinent = e.dungeonContinent or dc
            if dc == e.continent then
                e.distance, e.dungeonContinent = "near", dc
                return
            end
            e.distance = "far"
        end
    end
end

---------------------------------------------------------------------------
-- Search (LFGBrowse_DoSearch)
---------------------------------------------------------------------------
-- Category and activities to search: your listing's when "Your listing" is picked, else the
-- picked ones, else everything in the category you can see at your level.
function ns.SearchTarget()
    local db = ns.db
    if db.searchSelf then
        local entry = ns.GetListing()
        if entry and entry.activityIDs[1] then
            local a = ns.GetActivity(entry.activityIDs[1])
            return a and a.categoryID, entry.activityIDs
        end
        db.searchSelf = false
    end
    local cat = db.categoryID
    if not cat then return nil end
    local acts = ns.SelectedActivities() or ns.GetFilteredActivities(cat)
    return cat, acts
end

function ns.DoSearch()
    if not LFG.Search then
        ns.Print("Searching isn't available on this client.")
        return false
    end
    local cat, acts = ns.SearchTarget()
    if not cat or cat == 0 then
        ns.Print("Pick a category first.")
        return false
    end
    if ns.ClearPendingSearch then ns.ClearPendingSearch() end
    local ok, err = pcall(LFG.Search, cat, 0, 0, nil, false, nil, acts)
    if not ok then
        ns.Print("Search failed: " .. tostring(err))
        return false
    end
    ns.searching, ns.searchFailed = true, false
    local started = GetTime()
    ns.searchStarted = started
    -- If no answer comes (throttled or blocked), don't leave Search greyed out.
    C_Timer.After(6, function()
        if ns.searching and ns.searchStarted == started then
            ns.searching = false
            if ns.Render then ns.Render() end
        end
    end)
    return true
end

---------------------------------------------------------------------------
-- Result collection
---------------------------------------------------------------------------
local function BuildEntry(id, myActivities)
    local info = LFG.GetSearchResultInfo(id)
    if not info or info.isDelisted then return nil end

    local e = {
        id = id,
        info = info,
        members = {},
        activityIDs = info.activityIDs or {},
        age = info.age or 0,
        isSelf = info.hasSelf and true or false,
        -- Friends and guildmates in the listing, as the game counts them.
        friends = (info.numBNetFriends or 0) + (info.numCharFriends or 0),
        guildmates = info.numGuildMates or 0,
    }
    local n = info.numMembers or 1
    for i = 1, n do
        local p = LFG.GetSearchResultPlayerInfo and LFG.GetSearchResultPlayerInfo(id, i)
        if p then
            e.members[#e.members + 1] = p
            if p.isLeader then e.leader = p end
            if p.level and (not e.maxLevel or p.level > e.maxLevel) then e.maxLevel = p.level end
            if p.level and (not e.minLevel or p.level < e.minLevel) then e.minLevel = p.level end
        end
    end
    if #e.members == 0 and LFG.GetSearchResultLeaderInfo then
        local p = LFG.GetSearchResultLeaderInfo(id)
        if p then
            e.members[1] = p
            e.leader = p
            e.maxLevel, e.minLevel = p.level, p.level
        end
    end
    e.leader = e.leader or e.members[1]
    e.leaderName = info.leaderName or (e.leader and e.leader.name)
    -- Remember where everyone the game does tell us about is (usually just the lister).
    for _, p in ipairs(e.members) do
        if p.areaName and p.areaName ~= "" and ns.RememberLocation then ns.RememberLocation(p.name, p.areaName, "listing") end
    end
    e.numMembers = n
    e.isSolo = n <= 1

    local t, h, d = 0, 0, 0
    for _, p in ipairs(e.members) do
        local r = p.assignedRole
        if r == "TANK" then t = t + 1
        elseif r == "HEALER" then h = h + 1
        elseif r == "DAMAGER" then d = d + 1 end
    end
    e.tanks, e.healers, e.dps = t, h, d
    e.roles = e.leader and e.leader.lfgRoles
    if LFG.GetSearchResultMemberCounts then
        local ok, counts = pcall(LFG.GetSearchResultMemberCounts, id)
        if ok then e.counts = counts end
    end

    local maxPlayers = 0
    for _, aid in ipairs(e.activityIDs) do
        local a = ns.GetActivity(aid)
        if a and a.maxNumPlayers and a.maxNumPlayers > maxPlayers then maxPlayers = a.maxNumPlayers end
    end
    e.maxPlayers = maxPlayers > 0 and maxPlayers or 5

    -- Listings for one of your own listed activities (the game puts these first, in blue).
    if myActivities then
        for _, aid in ipairs(e.activityIDs) do
            if tContains(myActivities, aid) then e.matchesMine = true break end
        end
    end
    return e
end

function ns.Collect()
    local groups, players = {}, {}
    local getter = LFG.GetFilteredSearchResults or LFG.GetSearchResults
    if not getter then return groups, players end
    local _, results = getter()
    if type(results) ~= "table" then return groups, players end
    local mine = ns.GetListing()
    mine = mine and mine.activityIDs
    for _, id in ipairs(results) do
        local ok, e = pcall(BuildEntry, id, mine)
        if ok and e then
            if e.isSolo then players[#players + 1] = e else groups[#groups + 1] = e end
        end
    end
    return groups, players
end

---------------------------------------------------------------------------
-- XP evaluation
---------------------------------------------------------------------------
local XP_RANK = { safe = 3, partial = 2, none = 1, unknown = 0 }
ns.XP_RANK = XP_RANK

-- status: "safe"    = highest level <= lowest mobs + 12  (full XP whole instance)
--         "partial" = highest level <= highest mobs + 12 (XP from the tougher mobs only)
--         "none"    = above every mob + 12 (no kill XP at all)
--         "unknown"
function ns.EvaluateXP(e)
    local level = e.maxLevel
    e.selfIsHighest = false
    if ns.db.filters.includeSelf and not e.isSelf then
        -- In a party, the level that counts is your party's highest (you join together).
        local me = (ns.MyGroupMaxLevel and ns.MyGroupMaxLevel()) or UnitLevel("player")
        if me and me > 0 and (not level or me > level) then
            level = me
            e.selfIsHighest = true
        end
    end
    e.effectiveLevel = level
    e.xpStatus, e.xpLo, e.xpHi, e.xpActivity = "unknown", nil, nil, nil
    if not level then return end

    for _, id in ipairs(RelevantActivities(e)) do
        local lo, hi = ns.GetActivityRange(id)
        if lo then
            local st
            if level <= lo + ns.XP_GAP then st = "safe"
            elseif level <= hi + ns.XP_GAP then st = "partial"
            else st = "none" end
            if XP_RANK[st] > XP_RANK[e.xpStatus] then
                e.xpStatus, e.xpLo, e.xpHi, e.xpActivity = st, lo, hi, id
            end
        end
    end
end

---------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------
local function SafeLower(s)
    if type(s) ~= "string" then return "" end
    local ok, r = pcall(string.lower, s)
    return ok and r or ""
end

local function MatchesText(e, needle)
    local parts = { e.leaderName, e.info.name, e.info.comment }
    for _, id in ipairs(e.activityIDs) do parts[#parts + 1] = ns.GetActivityName(id) end
    for _, p in ipairs(e.members) do
        parts[#parts + 1] = p.name
        parts[#parts + 1] = p.className
        parts[#parts + 1] = p.areaName
    end
    for _, s in ipairs(parts) do
        local hay = SafeLower(s)
        if hay ~= "" and hay:find(needle, 1, true) then return true end
    end
    return false
end

-- Open seats by role, from the game's own counts when it gives them.
function ns.Remaining(e, role)
    local c = e.counts
    if c then
        local key = ({ tank = "TANK_REMAINING", healer = "HEALER_REMAINING", dps = "DAMAGER_REMAINING" })[role]
        if c[key] then return c[key] end
    end
    if e.maxPlayers - e.numMembers <= 0 then return 0 end
    if role == "tank" then return e.tanks == 0 and 1 or 0 end
    if role == "healer" then return e.healers == 0 and 1 or 0 end
    return math.max(0, e.maxPlayers - 2 - e.dps)
end

local function Passes(e, f)
    if e.isSelf then
        ns.EvaluateXP(e)
        if e.isSolo then pcall(ns.EvaluateDistance, e) end
        return true -- your own listing always shows, at the top
    end

    local sel = ns.SelectedActivities()
    if sel and not ns.db.searchSelf then
        local found = false
        for _, id in ipairs(e.activityIDs) do if ns.db.activityIDs[id] then found = true break end end
        if not found then return false end
    end

    if f.text and f.text ~= "" and not MatchesText(e, SafeLower(f.text)) then return false end

    if e.maxLevel then
        if f.levelMin and e.minLevel and e.minLevel < f.levelMin then return false end
        if f.levelMax and e.maxLevel > f.levelMax then return false end
    elseif f.hideUnknown then
        return false
    end

    ns.EvaluateXP(e)
    if e.xpStatus == "unknown" then
        if f.hideUnknown and f.xpMode ~= "off" then return false end
    elseif f.xpMode == "strict" and e.xpStatus ~= "safe" then
        return false
    elseif f.xpMode == "lenient" and e.xpStatus == "none" then
        return false
    end

    if e.isSolo then
        e.distance = "unknown"
        pcall(ns.EvaluateDistance, e)
        if f.hideFar and e.distance == "far" then return false end
        local want = f.playerRoles
        if want.tank or want.healer or want.dps then
            local r = e.roles
            if not (r and ((want.tank and r.tank) or (want.healer and r.healer) or (want.dps and r.dps))) then
                return false
            end
        end
        if next(f.classes) then
            local cls = e.leader and e.leader.classFilename
            if not (cls and f.classes[cls]) then return false end
        end
    else
        local open = e.maxPlayers - e.numMembers
        if f.hideFull and open <= 0 then return false end
        local need = f.groupNeeds
        if need.tank or need.healer or need.dps then
            local ok = (need.tank and ns.Remaining(e, "tank") > 0) or (need.healer and ns.Remaining(e, "healer") > 0)
                or (need.dps and ns.Remaining(e, "dps") > 0)
            if not ok then return false end
        end
    end
    return true
end

function ns.AnyOn(t)
    for _, v in pairs(t) do if v then return true end end
    return false
end

-- How the lists can be sorted. Whatever the choice, your own listing comes first, then listings
-- for your listed activities (as the game sorts), then ones with friends or guildmates in them.
ns.SORT_MODES = {
    { key = "xp", label = "Best XP first" },
    { key = "newest", label = "Newest first" },
    { key = "oldest", label = "Oldest first" },
    { key = "levelLow", label = "Level, low to high" },
    { key = "levelHigh", label = "Level, high to low" },
    { key = "size", label = "Biggest groups first" },
}

local function Social(e) return (e.friends or 0) + (e.guildmates or 0) end

local function SortEntries(a, b)
    if a.isSelf ~= b.isSelf then return a.isSelf end
    if (a.matchesMine or false) ~= (b.matchesMine or false) then return a.matchesMine or false end
    local sa, sb = Social(a) > 0, Social(b) > 0
    if sa ~= sb then return sa end
    local mode = ns.db.sortMode
    local la, lb = a.maxLevel or 0, b.maxLevel or 0
    if mode == "newest" or mode == "oldest" then
        if (a.age or 0) ~= (b.age or 0) then
            if mode == "newest" then return (a.age or 0) < (b.age or 0) end
            return (a.age or 0) > (b.age or 0)
        end
    elseif mode == "levelLow" or mode == "levelHigh" then
        if la ~= lb then
            if mode == "levelLow" then return la < lb end
            return la > lb
        end
    elseif mode == "size" then
        if a.numMembers ~= b.numMembers then return a.numMembers > b.numMembers end
    end
    local ra, rb = XP_RANK[a.xpStatus] or 0, XP_RANK[b.xpStatus] or 0
    if ra ~= rb then return ra > rb end
    if (a.age or 0) ~= (b.age or 0) then return (a.age or 0) < (b.age or 0) end
    return a.id < b.id
end

-- Returns filtered+sorted groups, players and the unfiltered totals.
-- Your party (or you, when you're listed alone), as a card: built from your group's own units, so
-- it shows even when you're not listed or your search doesn't cover your listing, and is always
-- current. The game's own result for your listing is replaced by it.
-- Where a member of your group is: the game's group roster says, wherever they are (in another
-- zone, a dungeon, out of range), as its raid frames show it. The map is a fallback.
local function RosterZone(unit)
    if not (GetRaidRosterInfo and GetNumGroupMembers) then return nil end
    local idx = unit:match("^raid(%d+)$")
    if idx then
        local zone = select(7, GetRaidRosterInfo(tonumber(idx)))
        return zone
    end
    local first = UnitName(unit)
    local full = ns.UnitFullName and ns.UnitFullName(unit)
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, _, zone = GetRaidRosterInfo(i)
        if name then
            local bare = name:match("^[^-]+") or name
            if bare == first or bare == full or (bare:match("^%S+") == first) then return zone end
        end
    end
end

local function UnitZone(unit)
    if UnitIsUnit(unit, "player") then
        local z = GetRealZoneText and GetRealZoneText()
        if z and z ~= "" then return z end
        z = GetZoneText and GetZoneText()
        if z and z ~= "" then return z end
    end
    local ok, zone = pcall(RosterZone, unit)
    if ok and zone and zone ~= "" and zone ~= UNKNOWN then return zone end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit(unit)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name
end

-- A unit's name as the game's own frames show it. In Forever a character's name is a first name
-- and a surname, and UnitName returns them separately (where retail returns name and realm), so
-- the game's own formatter is used, which joins them the way the party frames do.
function ns.UnitFullName(unit)
    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        local ok, name = pcall(NameUtil.FormatUnitNameForDisplay, unit, true)
        if ok and name and name ~= "" then return name end
    end
    if GetUnitName then
        local ok, name = pcall(GetUnitName, unit, true)
        if ok and name and name ~= "" then return name end
    end
    return (UnitName(unit))
end

local ROLE_OF = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DAMAGER" }

function ns.MyGroupUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        units = {}
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

-- The highest level in your party (just you when you're alone).
function ns.MyGroupMaxLevel()
    local best = 0
    for _, unit in ipairs(ns.MyGroupUnits()) do
        local l = UnitLevel(unit)
        if l and l > best then best = l end
    end
    return best > 0 and best or nil
end

function ns.BuildMyGroupEntry()
    local listing = ns.HasListing() and ns.GetListing()
    if not (IsInGroup() or listing) then return nil end
    local members, t, h, d = {}, 0, 0, 0
    local maxL, minL, leader
    for _, unit in ipairs(ns.MyGroupUnits()) do
        if UnitExists(unit) then
            local _, classFile = UnitClass(unit)
            local role = ROLE_OF[UnitGroupRolesAssigned(unit)] or "NONE"
            local p = {
                name = ns.UnitFullName(unit),
                level = UnitLevel(unit),
                classFilename = classFile,
                className = UnitClass(unit),
                assignedRole = role,
                areaName = UnitZone(unit),
                isLeader = (IsInGroup() and UnitIsGroupLeader(unit)) or (not IsInGroup()),
            }
            if role == "TANK" then t = t + 1 elseif role == "HEALER" then h = h + 1 elseif role == "DAMAGER" then d = d + 1 end
            if p.level and (not maxL or p.level > maxL) then maxL = p.level end
            if p.level and (not minL or p.level < minL) then minL = p.level end
            if p.isLeader then leader = p end
            members[#members + 1] = p
        end
    end
    leader = leader or members[1]
    local activityIDs = listing and listing.activityIDs or {}
    local maxPlayers = 0
    for _, aid in ipairs(activityIDs) do
        local a = ns.GetActivity(aid)
        if a and a.maxNumPlayers and a.maxNumPlayers > maxPlayers then maxPlayers = a.maxNumPlayers end
    end
    if maxPlayers == 0 then maxPlayers = (IsInRaid and IsInRaid()) and 40 or 5 end
    local e = {
        id = -1,
        isSelf = true,
        isMyGroup = true,
        listed = listing and true or false,
        info = {
            name = "", comment = listing and listing.comment or "", hasSelf = true,
            generalPlaystyle = listing and listing.generalPlaystyle, newPlayerFriendly = listing and listing.newPlayerFriendly,
            voiceMode = listing and listing.voiceMode,
        },
        members = members,
        activityIDs = activityIDs,
        age = 0,
        leader = leader,
        leaderName = leader and leader.name,
        numMembers = #members,
        isSolo = #members <= 1,
        tanks = t, healers = h, dps = d,
        maxPlayers = maxPlayers,
        maxLevel = maxL, minLevel = minL,
        friends = 0, guildmates = 0,
    }
    local okR, roles = pcall(function() return C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles() end)
    e.roles = okR and roles or nil
    return e
end

function ns.GetFiltered()
    local groups, players = ns.Collect()
    -- Your party card replaces the game's result for your own listing.
    local mine = ns.BuildMyGroupEntry()
    if mine then
        for _, list in ipairs({ groups, players }) do
            for i = #list, 1, -1 do
                if list[i].isSelf then table.remove(list, i) end
            end
        end
        if mine.isSolo then table.insert(players, 1, mine) else table.insert(groups, 1, mine) end
    end
    local f = ns.db.filters
    local fg, fp = {}, {}
    for _, e in ipairs(groups) do if Passes(e, f) then fg[#fg + 1] = e end end
    for _, e in ipairs(players) do if Passes(e, f) then fp[#fp + 1] = e end end
    table.sort(fg, SortEntries)
    table.sort(fp, SortEntries)
    return fg, fp, #groups, #players
end

---------------------------------------------------------------------------
-- Where players are
---------------------------------------------------------------------------
-- The game shares only the lister's zone in search results, never the other members'. So Seeker
-- remembers every zone it learns, from listings, your friends list, your guild roster and any /who
-- (Seeker's Who tab, Whisper Messenger's lookups, or your own), for a while.
local LOCATION_TTL = 15 * 60
local locations = {}

local function LocationKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    return (name:match("^[^-]+") or name):lower()
end

function ns.RememberLocation(name, zone, source)
    local key = LocationKey(name)
    if not key or type(zone) ~= "string" or zone == "" then return end
    locations[key] = { zone = zone, time = GetTime(), source = source }
end

-- zone, seconds since it was learned, and where from; nil when unknown or too old.
function ns.GetKnownLocation(name)
    local l = locations[LocationKey(name) or ""]
    if not l then return nil end
    local age = GetTime() - l.time
    if age > LOCATION_TTL then return nil end
    return l.zone, age, l.source
end

-- Online friends and guildmates: the game tells you where they are.
function ns.RefreshSocialLocations()
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local f = C_FriendList.GetFriendInfoByIndex(i)
            if f and f.connected and f.area then ns.RememberLocation(f.name, f.area, "friend") end
        end
    end
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, GetNumGuildMembers() or 0 do
            local name, _, _, _, _, zone, _, _, online = GetGuildRosterInfo(i)
            if online and zone then ns.RememberLocation(name, zone, "guild") end
        end
    end
end

-- Every /who result, wherever it came from.
function ns.RememberWhoResults()
    if not (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo) then return end
    for i = 1, C_FriendList.GetNumWhoResults() or 0 do
        local info = C_FriendList.GetWhoInfo(i)
        if info then ns.RememberLocation(info.fullName, info.area, "who") end
    end
end

-- During one of Seeker's quiet lookups, the game's own /who listeners (its group finder's Who list,
-- which opens the Looking for Group window to show results, and the Friends window's, if any) are
-- told nothing, so no window opens or flashes and no sound plays. They hear /who again as soon as
-- the answer arrives, or after a few seconds if none does.
local WHO_LISTENERS = { "LFGWhoListFrame", "FriendsFrame", "WhoFrame" }
local muted = {}

local function MuteGameWho()
    for _, name in ipairs(WHO_LISTENERS) do
        local f = _G[name]
        if f and not muted[f] and f.IsEventRegistered and f:IsEventRegistered("WHO_LIST_UPDATE") then
            f:UnregisterEvent("WHO_LIST_UPDATE")
            muted[f] = true
        end
    end
end

local function UnmuteGameWho()
    for f in pairs(muted) do
        pcall(f.RegisterEvent, f, "WHO_LIST_UPDATE")
    end
    wipe(muted)
end

-- A quiet lookup is over (answered or not): give /who back to the game and to chat.
local function EndQuietLookup()
    ns.silentWhoUntil = nil
    UnmuteGameWho()
    if not (ns.IsWhoPageShown and ns.IsWhoPageShown()) and C_FriendList.SetWhoToUi then
        C_FriendList.SetWhoToUi(false)
    end
end

-- Finding where group members are, automatically. The game only runs /who from a click or key
-- press, and allows about one every five seconds. So Seeker keeps a queue of members whose
-- location isn't known (filled from every search, and moved to the front for groups you hover),
-- and each click, scroll or key press in Seeker's window quietly looks up the next one. Answers
-- come back without a window or chat line, and an open tooltip updates itself.
local WHO_GAP = 5.5
local ASKED_AGAIN_AFTER = 120 -- don't ask about the same name again for two minutes
local lastLookup = 0
local queue, queued, asked = {}, {}, {}

local function ShortKey(name)
    return name and (name:match("^[^-]+") or name):lower()
end

local function NeedsLookup(p)
    if not p.name or (p.areaName and p.areaName ~= "") or ns.GetKnownLocation(p.name) then return false end
    local t = asked[ShortKey(p.name)]
    return not t or GetTime() - t > ASKED_AGAIN_AFTER
end

-- Queue these players' lookups; first = true puts them at the front (a group you're looking at).
function ns.QueueLocate(members, first)
    for i = #(members or {}), 1, -1 do
        local p = members[i]
        local key = ShortKey(p.name)
        if key and NeedsLookup(p) then
            if queued[key] then
                if first then
                    for j, n in ipairs(queue) do
                        if ShortKey(n) == key then table.remove(queue, j) break end
                    end
                    table.insert(queue, 1, p.name)
                end
            else
                queued[key] = true
                if first then table.insert(queue, 1, p.name) else queue[#queue + 1] = p.name end
            end
        end
    end
end

-- Members of every group in the results, for the queue (the game sends only each lister's zone).
function ns.QueueLocateResults(groups)
    for _, e in ipairs(groups or {}) do
        if not e.isSolo and not e.isSelf then
            local members = {}
            for i = 1, e.numMembers or 0 do
                local ok, p = pcall(C_LFGList.GetSearchResultPlayerInfo, e.id, i)
                if ok and p then members[#members + 1] = p end
            end
            ns.QueueLocate(members)
        end
    end
end

-- Run the next lookup, if one's waiting and the game would allow it. Called from clicks, scrolls
-- and key presses (a /who needs one); harmless to call often.
function ns.PumpLocate()
    if #queue == 0 or not (C_FriendList and C_FriendList.SendWho) then return end
    if GetTime() - lastLookup < WHO_GAP then return end
    if ns.IsWhoPageShown and ns.IsWhoPageShown() then return end -- the Who tab is yours
    -- The game allows one search or /who per click: a click that opens or picks from a menu (the
    -- category and activity menus search), or one on the List yourself page (posting), keeps it.
    local okM, menuOpen = pcall(function() return Menu and Menu.GetManager and Menu.GetManager():GetOpenMenu() end)
    if okM and menuOpen then return end
    local win = _G.SeekerLFGFrame
    if win and win.pages and win.pages.listing and win.pages.listing:IsShown() then return end
    if ns.whoUntil and GetTime() < ns.whoUntil then return end
    while #queue > 0 do
        local name = table.remove(queue, 1)
        local key = ShortKey(name)
        queued[key] = nil
        if not ns.GetKnownLocation(name) and not (asked[key] and GetTime() - asked[key] <= ASKED_AGAIN_AFTER) then
            asked[key] = GetTime()
            lastLookup = GetTime()
            local started = GetTime()
            ns.silentWhoUntil = started + 6
            MuteGameWho()
            if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end -- results to Seeker, not chat
            local ok = pcall(C_FriendList.SendWho, 'n-"' .. (name:match("^[^-]+") or name) .. '"')
            if not ok then
                EndQuietLookup()
                return
            end
            -- If no answer comes (they logged off), end it anyway.
            C_Timer.After(6.5, function()
                if ns.silentWhoUntil == started + 6 then EndQuietLookup() end
            end)
            return
        end
    end
end

function ns.LocatePending()
    return #queue
end

-- Is this player waiting for a lookup (queued, or asked and not answered yet)?
function ns.IsLocating(name)
    local key = ShortKey(name)
    if not key then return false end
    if queued[key] then return true end
    return asked[key] and GetTime() - asked[key] < 7 or false
end

-- A /who answer arrived. Remember it, and if it was one of Seeker's quiet lookups, send /who
-- results back to chat (unless the Who tab is open) and refresh the tooltip on show.
function ns.OnWhoListUpdate()
    ns.RememberWhoResults()
    if ns.silentWhoUntil and GetTime() < ns.silentWhoUntil then
        -- Seeker hears /who answers before the game does, so the quiet lookup is only ended on the
        -- next frame, after the game's own listeners have (not) seen this one.
        C_Timer.After(0, function()
            EndQuietLookup()
            local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
            if owner and owner.item and ns.ShowEntryTooltip then ns.ShowEntryTooltip(owner, owner.item) end
        end)
    end
end

do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "WHO_LIST_UPDATE", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local pending = false
    ev:SetScript("OnEvent", function(_, event)
        if event == "WHO_LIST_UPDATE" then
            ns.OnWhoListUpdate()
        elseif not pending then
            pending = true
            C_Timer.After(1, function()
                pending = false
                pcall(ns.RefreshSocialLocations)
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- New-match alerts
---------------------------------------------------------------------------
-- Every listing seen this session. The first results after logging in are only remembered,
-- so you're told about what's new from then on, not about everything already listed.
local seen, primed = {}, false

local function AlertSound()
    local kit = SOUNDKIT and (SOUNDKIT.UI_GROUP_FINDER_RECEIVE_APPLICATION or SOUNDKIT.RAID_WARNING or SOUNDKIT.READY_CHECK)
    if kit then PlaySound(kit, "Master") end
end

-- Called whenever search results arrive (from Seeker's search, a keybinding, or the game's own).
function ns.CheckNewMatches()
    local a = ns.db.alerts
    local ok, groups, players = pcall(ns.GetFiltered)
    if not ok then return end
    local fresh = {}
    for _, list in ipairs({ groups, players }) do
        for _, e in ipairs(list) do
            if not seen[e.id] then
                seen[e.id] = true
                if primed and not e.isSelf and (not a.fullXPOnly or e.xpStatus == "safe") then
                    fresh[#fresh + 1] = e
                end
            end
        end
    end
    primed = true
    if not a.enabled or #fresh == 0 then return end

    local parts = {}
    for i = 1, math.min(3, #fresh) do
        local e = fresh[i]
        local act = e.xpActivity or RelevantActivities(e)[1]
        local kind = e.isSolo and "player" or ("group %d/%d"):format(e.numMembers, e.maxPlayers)
        parts[#parts + 1] = ("%s (%s, %s, lvl %s)"):format(ns.ShortName and ns.ShortName(e.leaderName) or e.leaderName or "?",
            kind, act and ns.GetActivityName(act) or "?", e.maxLevel and tostring(e.maxLevel) or "?")
    end
    local more = #fresh > 3 and (" and %d more"):format(#fresh - 3) or ""
    ns.Print(("%d new: %s%s. |cff999999/seeker to open|r"):format(#fresh, table.concat(parts, ", "), more))
    if a.sound then AlertSound() end
    if a.flash and FlashClientIcon then FlashClientIcon() end
end

---------------------------------------------------------------------------
-- Actions (as the game's own finder offers them)
---------------------------------------------------------------------------
local function ActiveChatEditBox()
    if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then return ChatFrameUtil.GetActiveWindow() end
    if ChatEdit_GetActiveWindow then return ChatEdit_GetActiveWindow() end
end

-- Whisper Messenger (if installed): its public API, connected under our name so it can be allowed
-- or blocked from Whisper Messenger's own settings.
local wmClient
local function WhisperMessenger()
    local api = _G.WhisperMessengerAPI
    if type(api) ~= "table" then return nil end
    if not wmClient and type(api.Connect) == "function" then
        local ok, client = pcall(api.Connect, "Seeker LFG")
        if ok and type(client) == "table" then wmClient = client end
    end
    return wmClient or api
end

function ns.HasWhisperMessenger()
    local wm = WhisperMessenger()
    return wm ~= nil and type(wm.OpenConversation) == "function"
end

function ns.Whisper(name, text)
    if not name then return end
    -- Whisper Messenger first, when it's installed and switched on here: the conversation opens in
    -- its window, with any request text ready in its composer. If it declines (in combat with its
    -- window closed, competitive content, or Seeker blocked in its settings), the game's whisper.
    if ns.db.useWhisperMessenger ~= false and ns.HasWhisperMessenger() then
        local ok, opened = pcall(WhisperMessenger().OpenConversation, name, text)
        if ok and opened then return end
    end
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(name)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(name)
    end
    if text then
        local eb = ActiveChatEditBox()
        if eb and eb.Insert then eb:Insert(text) end
    end
end

-- The game only lets you invite solo players, and only when you can invite (solo, leader or assist).
function ns.CanInvite(e)
    if not e or not e.isSolo or e.isSelf then return false end
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function ns.Invite(name)
    if not name then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

-- Forever has no applications: you ask the leader. This opens a whisper with a request ready to
-- send (your level, class, roles and the dungeon); you press Enter to send it.
---------------------------------------------------------------------------
-- Message templates (Request to join, and the optional whisper sent with an invite)
---------------------------------------------------------------------------
ns.DEFAULT_REQUEST_MESSAGE = "Hi! Could I join you for [dungeon]? I'm a level [level] [class] ([roles])."
ns.DEFAULT_INVITE_MESSAGE = "" -- empty: inviting sends no whisper, as the game's Invite
ns.MAX_WHISPER = 255

-- The placeholders, in the order the Messages window lists them.
ns.MESSAGE_TOKENS = {
    { "level", "your level" },
    { "class", "your class" },
    { "roles", "the roles you've ticked, e.g. Tank/Healer" },
    { "dungeon", "the dungeon they're listed for" },
    { "name", "your name" },
    { "target", "their name" },
    { "zone", "the zone you're in" },
}

local function MyRoles()
    local roles = {}
    local r = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
    if r then
        if r.tank then roles[#roles + 1] = TANK or "Tank" end
        if r.healer then roles[#roles + 1] = HEALER or "Healer" end
        if r.dps then roles[#roles + 1] = DAMAGER or "DPS" end
    end
    return table.concat(roles, "/")
end

-- Fills a template's [placeholders] (any case) for a listing, then tidies up whatever an empty
-- placeholder leaves behind ("()", doubled spaces), and keeps it to one whisper.
function ns.RenderMessage(template, e)
    template = template or ""
    local act = e and (e.xpActivity or RelevantActivities(e)[1])
    local values = {
        level = tostring(UnitLevel("player") or ""),
        class = UnitClass("player") or "",
        roles = MyRoles(),
        dungeon = act and ns.GetActivityName(act) or "",
        name = UnitName("player") or "",
        target = e and ns.ShortName and ns.ShortName(e.leaderName) or (e and e.leaderName) or "",
        zone = GetRealZoneText and GetRealZoneText() or "",
    }
    local text = template:gsub("%[(%a+)%]", function(key)
        local v = values[key:lower()]
        return v -- unknown [words] are left as typed
    end)
    text = text:gsub("%(%s*%)", ""):gsub("%[%s*%]", ""):gsub("  +", " "):gsub("%s+([%.,!?])", "%1")
    text = strtrim(text)
    if #text > ns.MAX_WHISPER then text = text:sub(1, ns.MAX_WHISPER) end
    return text
end

function ns.RequestMessage()
    local t = ns.db.requestMessage
    if t == nil or strtrim(t) == "" then return ns.DEFAULT_REQUEST_MESSAGE end
    return t
end

function ns.InviteMessage()
    return ns.db.inviteMessage or ns.DEFAULT_INVITE_MESSAGE
end

-- Request to join: a whisper to the leader with your message ready; you press Enter to send it.
function ns.RequestToJoin(e)
    if not e or not e.leaderName then return end
    ns.Whisper(e.leaderName, ns.RenderMessage(ns.RequestMessage(), e))
end

-- Invite a listed player, and whisper them your invite message if you've set one. The click is
-- what sends it, as the invite itself.
function ns.InviteListed(e)
    if not e or not e.leaderName then return end
    ns.Invite(e.leaderName)
    local msg = ns.RenderMessage(ns.InviteMessage(), e)
    if msg ~= "" and SendChatMessage then
        local ok, err = pcall(SendChatMessage, msg, "WHISPER", nil, e.leaderName)
        if not ok then ns.Print("Couldn't send your invite message: " .. tostring(err)) end
    end
end

function ns.ReportListing(e, advertisement)
    if not (ReportInfo and ReportFrame and Enum.ReportType and Enum.ReportType.GroupFinderPosting) then
        ns.Print("Reporting isn't available here.")
        return
    end
    local ok, err = pcall(function()
        local info = ReportInfo:CreateReportInfoFromType(Enum.ReportType.GroupFinderPosting)
        info:SetGroupFinderSearchResultID(e.id)
        if advertisement then
            ReportFrame:Hide()
            ReportFrame:SetMinorCategoryFlag(Enum.ReportMinorCategory.Advertisement, true)
            ReportFrame:SetMajorType(Enum.ReportMajorCategory.InappropriateCommunication)
            ReportFrame:InitiateReport(info, e.leaderName, nil, nil, true)
        else
            ReportFrame:InitiateReport(info, e.leaderName)
        end
    end)
    if not ok then ns.Print("Couldn't open the report: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- Debug dump to help adapt to client API differences
---------------------------------------------------------------------------
function ns.DebugDump()
    local function has(fn) return LFG[fn] and "yes" or "NO" end
    ns.Print("Interface:", select(4, GetBuildInfo()))
    for _, fn in ipairs({ "Search", "GetFilteredSearchResults", "GetSearchResultInfo", "GetSearchResultPlayerInfo",
        "GetSearchResultMemberCounts", "CreateListing", "UpdateListing", "RemoveListing", "GetActiveEntryInfo" }) do
        ns.Print("  C_LFGList." .. fn .. ":", has(fn))
    end
    ns.Print("  Comment box:", _G.LFGListingComment and "found" or "not loaded")
    ns.Print("  Game LFG windows found:", #(ns.nativeFound or {}) > 0 and table.concat(ns.nativeFound, ", ") or "none yet")
    ns.Print("  Replace mode:", ns.db.replaceNative and "on" or "off")
    ns.Print("  Listed:", ns.HasListing() and "yes" or "no")
    local getter = LFG.GetFilteredSearchResults or LFG.GetSearchResults
    if not getter then return end
    local total, results = getter()
    ns.Print("Results:", tostring(total))
    local id = results and results[1]
    if not id then return end
    local info = LFG.GetSearchResultInfo(id)
    if info then
        for k, v in pairs(info) do ns.Print("  info." .. tostring(k), tostring(v)) end
    end
end
