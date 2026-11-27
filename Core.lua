-- Seeker: data layer (search results, XP rule, filters, actions).
-- Behaviour mirrors Forever's own group finder (Blizzard_GroupFinder_VanillaStyle) where it has one.
local ADDON, ns = ...
local L = ns.L -- translations (Locale.lua)

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
    minimap = {},          -- LibDBIcon's: the minimap button's position (minimapPos) and hidden state
    tab = "browse",
    sortMode = "xp",       -- see ns.SORT_MODES
    activityGrouping = "xp", -- activity lists: "xp" (by what they'd give you) or "game" (the game's groups)
    xpMarks = false,       -- show XP as a symbol (tick, question mark, cross) as well as a colour
    autoRefresh = true,    -- search again on your next click or key press once results are 30s old
    notes = {},            -- first-name key -> { text, name, time }: your notes on players
    grouped = {},          -- first-name key -> { name, classFile, level, time, what, count }: players you've grouped with
    markMySeat = true,     -- on group cards, show the open seat you'd fill (one of your roles they still need)
    compactCards = false,  -- Browse's cards on two lines instead of three, so more fit
    zoneHops = true,       -- after where someone is: how many zones from their dungeon, coloured
    whisperInbox = true,   -- collect whispers you get while listed on the People tab
    presets = {},          -- name -> saved filter setup (Setups.lua)
    chat = {               -- groups and players looking in chat (Chat.lua)
        enabled = true,
        lfgChannelOnly = false, -- only the LookingForGroup channel, not General, world and the rest
        alerts = false,         -- announce new chat posts that pass your filters
    },
    alerts = {
        enabled = true,    -- tell me about new listings that match my filters
        mode = "roles",    -- "roles": players for the roles your party needs, or groups with room for
                           -- you; "all": anything new that passes your filters
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
        ignoredLeaders = {}, -- lowercased name -> name as shown: never show their listings
        hideIgnored = true,  -- also hide leaders on the game's own ignore list
        hideWords = "",      -- comma-separated: hide listings whose title or note has any of these
        greyOutsidePick = false, -- keep listings outside the picked activities, greyed (as the game does)
        greySaved = true,    -- grey out groups for raids and dungeons you're already saved to
    },
    who = {                  -- the Who page's filters and sort, kept between sessions
        classesFiltered = {}, -- classID -> true: left out
        racesFiltered = {},   -- raceID -> true: left out
        mapsIncluded = {},    -- uiMapID -> true: only these zones
        sortMode = "name",
        ascending = true,
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
    ns.LoadCharacterState()
end

-- Per character: what you browse (category, activities, your listing) and the filters that depend
-- on the character (levels and roles), so an alt doesn't open on your main's dungeons. They're
-- kept in SeekerLFGCharDB and copied into ns.db while you play, so the rest of Seeker reads them
-- as before; everything else (messages, hidden players, the window) stays account-wide.
local CHAR_KEYS = {
    { "categoryID" }, { "activityIDs" }, { "searchSelf" },
    { "filters", "levelMin" }, { "filters", "levelMax" },
    { "filters", "playerRoles" }, { "filters", "groupNeeds" },
}

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end
ns.DeepCopy = DeepCopy

local function GetPath(t, path)
    for _, k in ipairs(path) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    return t
end

-- Set a value at a path in ns.db. A table is copied into the table already there, which the
-- window's controls hold on to, rather than replacing it.
local function SetPath(t, path, value)
    for i = 1, #path - 1 do t = t[path[i]] end
    local key = path[#path]
    if type(value) == "table" and type(t[key]) == "table" then
        wipe(t[key])
        for k, v in pairs(value) do t[key][k] = DeepCopy(v) end
    else
        t[key] = DeepCopy(value)
    end
end
ns.SetDBPath = function(path, value) SetPath(ns.db, path, value) end

function ns.LoadCharacterState()
    SeekerLFGCharDB = SeekerLFGCharDB or {}
    local saved = SeekerLFGCharDB.state
    for _, path in ipairs(CHAR_KEYS) do
        -- This character's, or the default (never another character's).
        local value
        if saved then value = saved[table.concat(path, ".")] else value = GetPath(defaults, path) end
        if value == nil and type(GetPath(defaults, path)) == "table" then value = GetPath(defaults, path) end
        SetPath(ns.db, path, value)
    end
end

function ns.SaveCharacterState()
    if not ns.db then return end
    SeekerLFGCharDB = SeekerLFGCharDB or {}
    local state = {}
    for _, path in ipairs(CHAR_KEYS) do state[table.concat(path, ".")] = DeepCopy(GetPath(ns.db, path)) end
    SeekerLFGCharDB.state = state
end

do -- saved on the way out (logging out, or /reload)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGOUT")
    ev:SetScript("OnEvent", function() ns.SaveCharacterState() end)
end

function ns.Print(...)
    print("|cff66ccffSeeker LFG|r:", ...)
end

local LFG = C_LFGList or {}

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
    { key = "full", title = L["Full XP for you"], color = "|cff55ff55" },
    { key = "above", title = L["Above your level"], color = "|cffff9933" },
    { key = "some", title = L["Some XP (only the tougher mobs)"], color = "|cffffd133" },
    { key = "none", title = L["No XP for you"], color = "|cff8a8a8a" },
    { key = "other", title = L["Other"], color = "|cff999999" },
}

-- The level the 12-level rule is judged by for you: your party's highest (you'd join together),
-- or yours when you're alone.
function ns.MyXPLevel()
    return (ns.MyGroupMaxLevel and ns.MyGroupMaxLevel()) or UnitLevel("player") or 0
end

function ns.ActivityXPClass(id)
    local lo, hi = ns.GetActivityRange(id)
    if not lo then return "other" end
    local me = ns.MyXPLevel()
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
    -- Forever's own dungeons (instance map IDs from its group finder's activities).
    [2994] = KALIMDOR, -- Alcaz Prison
    [2974] = KALIMDOR, -- Blackmaw Hold
    [3001] = KALIMDOR, -- Shaper's Terrace
    [2999] = EASTERN,  -- Ruins of Lordaeron
    [2959] = EASTERN,  -- City of Dalaran
    [2970] = EASTERN,  -- The Drowned City
    [3039] = EASTERN,  -- Krol'dok Stronghold
    [2998] = EASTERN,  -- Excavation Site: Wetlands
    [3065] = EASTERN,  -- Hall of Thanes
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
local instanceNames = {} -- activityID -> the instance's name, or false (cached: it never changes)
function ns.GetActivityInstanceName(id)
    local name = instanceNames[id]
    if name == nil then
        name = false
        local a = ns.GetActivity(id)
        if a and a.mapID and GetRealZoneText then
            local ok, n = pcall(GetRealZoneText, a.mapID)
            if ok and n and n ~= "" then name = n end
        end
        instanceNames[id] = name
    end
    return name or nil
end

-- Zone name -> continent name, from the game's own map tree.
local zoneContinent
local zoneMapID = {}   -- zone name (your language) -> its map ID, for counting zones between places
local zoneOnContinent = {} -- zone map ID -> its continent's map ID
local ZONE_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local function AddContinent(mapID)
    local info = C_Map.GetMapInfo(mapID)
    if not info or not info.name then return end
    local cname = info.name
    zoneContinent[cname] = cname
    for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, nil, true) or {}) do
        if child.name and not zoneContinent[child.name] then
            zoneContinent[child.name] = cname
        end
        if child.name and child.mapID and (child.mapType == nil or child.mapType == ZONE_TYPE) and not zoneMapID[child.name] then
            zoneMapID[child.name] = child.mapID
            zoneOnContinent[child.mapID] = mapID
        end
    end
end

local function BuildZoneMap()
    zoneContinent = {}
    wipe(zoneMapID)
    wipe(zoneOnContinent)
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
            instances[BareName(name)] = { name = name, continent = key, raid = RAID_MAPS[mapID] or false, mapID = mapID }
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
-- An activity's dungeon name and instance name, bare (lowercase, no "The", no "(East)"), for
-- comparing with where someone is. Cached: worked out once per activity, not on every redraw.
local placeNames = {}
local function PlaceNames(id)
    local p = placeNames[id]
    if not p then
        local a = ns.GetActivity(id)
        p = { dungeon = BareName(a and a.fullName or ns.GetActivityName(id)), instance = BareName(ns.GetActivityInstanceName(id)) }
        placeNames[id] = p
    end
    return p.dungeon, p.instance
end

function ns.ZoneStatus(zone, activityIDs)
    if not zone or zone == "" or not activityIDs or #activityIDs == 0 then return nil end
    local here = BareName(zone)
    for _, id in ipairs(activityIDs) do
        local dungeon, instance = PlaceNames(id)
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

---------------------------------------------------------------------------
-- Zones away: how many zone borders between someone and their dungeon's entrance
---------------------------------------------------------------------------
-- The zone each dungeon's entrance is in (map IDs, so it works in every language). Blackrock
-- Mountain counts from both of its zones.
local ENTRANCE_ZONES = {
    [389] = { 1454 }, [43] = { 1413 }, [48] = { 1440 }, [47] = { 1413 }, [129] = { 1413 },
    [209] = { 1446 }, [349] = { 1443 }, [429] = { 1444 }, [249] = { 1445 }, [509] = { 1451 },
    [531] = { 1451 }, [36] = { 1436 }, [33] = { 1421 }, [34] = { 1453 }, [90] = { 1426 },
    [189] = { 1420 }, [70] = { 1418 }, [109] = { 1435 }, [230] = { 1427, 1428 },
    [229] = { 1427, 1428 }, [289] = { 1422 }, [329] = { 1423 }, [409] = { 1427, 1428 },
    [469] = { 1427, 1428 }, [309] = { 1434 }, [533] = { 1423 },
    -- Forever's own dungeons.
    [2994] = { 1445 }, -- Alcaz Prison: Dustwallow Marsh
    [2974] = { 1447 }, -- Blackmaw Hold: Azshara
    [3001] = { 1449 }, -- Shaper's Terrace: Un'Goro Crater
    [2999] = { 1420 }, -- Ruins of Lordaeron: Tirisfal Glades
    [2959] = { 1416 }, -- City of Dalaran: Alterac Mountains
    [2970] = { 1434 }, -- The Drowned City: Stranglethorn Vale
    [3039] = { 2548 }, -- Krol'dok Stronghold: Riverglades
    [2998] = { 1437 }, -- Excavation Site: Wetlands
    [3065] = { 1455 }, -- Hall of Thanes: Ironforge
}

-- Which zones border which, by the ways players walk between them (and Teldrassil's boat).
local ZONE_LINKS = {
    -- Kalimdor
    { 1411, 1454 }, { 1411, 1413 }, { 1454, 1413 }, { 1412, 1456 }, { 1412, 1413 },
    { 1413, 1440 }, { 1413, 1442 }, { 1413, 1441 }, { 1413, 1445 }, { 1438, 1457 },
    { 1438, 1439 }, { 1439, 1440 }, { 1440, 1442 }, { 1440, 1448 }, { 1440, 1447 },
    { 1441, 1444 }, { 1441, 1446 }, { 1442, 1443 }, { 1443, 1444 }, { 1446, 1449 },
    { 1449, 1451 }, { 1448, 1452 }, { 1448, 1450 }, { 1450, 1452 },
    -- Eastern Kingdoms
    { 1429, 1453 }, { 1429, 1436 }, { 1429, 1433 }, { 1429, 1431 }, { 1436, 1431 },
    { 1431, 1433 }, { 1431, 1434 }, { 1431, 1430 }, { 1430, 1435 }, { 1435, 1419 },
    { 1433, 1428 }, { 1428, 1427 }, { 1426, 1455 }, { 1426, 1432 }, { 1432, 1437 },
    { 1432, 1418 }, { 1437, 1417 }, { 1417, 1424 }, { 1417, 1425 }, { 1424, 1425 },
    { 1424, 1416 }, { 1424, 1421 }, { 1424, 1422 }, { 1416, 1422 }, { 1421, 1420 },
    { 1420, 1458 }, { 1420, 1422 }, { 1422, 1423 },
}

local adjacency
local function Link(a, b)
    adjacency[a] = adjacency[a] or {}
    adjacency[b] = adjacency[b] or {}
    adjacency[a][b], adjacency[b][a] = true, true
end

-- A zone the table doesn't know (one of Forever's new ones): bordering whatever zones its map
-- overlaps on the continent's map, when the game can tell.
local function LinkByMap(id)
    adjacency[id] = adjacency[id] or {}
    local cont = zoneOnContinent[id]
    if not (cont and C_Map.GetMapRectOnMap) then return end
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, id, cont)
    if not (ok and l and r and t and b) then return end
    for other, oc in pairs(zoneOnContinent) do
        if other ~= id and oc == cont and adjacency[other] and next(adjacency[other]) then
            local ok2, l2, r2, t2, b2 = pcall(C_Map.GetMapRectOnMap, other, cont)
            if ok2 and l2 and l < r2 and l2 < r and t < b2 and t2 < b then Link(id, other) end
        end
    end
end

local function Neighbours(id)
    if not adjacency then
        adjacency = {}
        for _, pair in ipairs(ZONE_LINKS) do Link(pair[1], pair[2]) end
        -- Zones the table doesn't know, linked both ways now, so they can be walked into too.
        local unknown = {}
        for z in pairs(zoneOnContinent) do
            if not adjacency[z] then unknown[#unknown + 1] = z end
        end
        for _, z in ipairs(unknown) do pcall(LinkByMap, z) end
    end
    return adjacency[id] or {}
end

-- The zone (map ID) someone in this place is in: inside a dungeon counts as its entrance's zone.
local function ZoneMapID(zone)
    if not zone or zone == "" then return nil end
    if not zoneContinent or not next(zoneContinent) then BuildZoneMap() end
    local id = zoneMapID[zone]
    if id then return id end
    local inst = ns.InstanceAt(zone)
    local entrance = inst and inst.mapID and ENTRANCE_ZONES[inst.mapID]
    return entrance and entrance[1] or nil
end

local hopsCache = {}
-- How many zones someone standing in this zone is from the nearest of these dungeons' entrances:
-- 0 in its zone, 1 next door, and so on. Nil when it can't be told (an unknown zone or dungeon,
-- or the dungeon's on another continent).
function ns.ZoneHops(zone, activityIDs)
    if not zone or zone == "" or not activityIDs or #activityIDs == 0 then return nil end
    local key = zone .. "|" .. table.concat(activityIDs, ",")
    local cached = hopsCache[key]
    if cached ~= nil then return cached or nil end
    local start = ZoneMapID(zone)
    local goals, any = {}, false
    for _, aid in ipairs(activityIDs) do
        local a = ns.GetActivity(aid)
        for _, z in ipairs(a and a.mapID and ENTRANCE_ZONES[a.mapID] or {}) do goals[z], any = true, true end
    end
    local hops
    if start and any then
        -- Breadth first: the fewest borders to cross.
        local seen, frontier, depth = { [start] = true }, { start }, 0
        while #frontier > 0 and depth <= 15 do
            for _, z in ipairs(frontier) do
                if goals[z] then hops = depth break end
            end
            if hops then break end
            local nextFrontier = {}
            for _, z in ipairs(frontier) do
                for n in pairs(Neighbours(z)) do
                    if not seen[n] then
                        seen[n] = true
                        nextFrontier[#nextFrontier + 1] = n
                    end
                end
            end
            frontier, depth = nextFrontier, depth + 1
        end
    end
    hopsCache[key] = hops or false
    return hops
end

-- For a solo player: "near" (same continent as one of their dungeons), "far", or "unknown".
-- Sets e.distance ("near", "far" or "unknown"), e.inDungeon, and the continents for the tooltip
-- ("On Kalimdor, but the dungeon is in the Eastern Kingdoms"), from ns.ZoneStatus.
function ns.EvaluateDistance(e)
    local zone = e.leader and e.leader.areaName
    e.continent = ns.GetZoneContinent(zone)
    e.dungeonContinent, e.distance, e.inDungeon = nil, "unknown", false
    local acts = RelevantActivities(e)
    local status, id = ns.ZoneStatus(zone, acts)
    if status == "in" then
        -- Already inside (or at) the dungeon they listed for.
        e.distance, e.inDungeon = "near", true
        e.dungeonContinent = ns.GetActivityContinent(id)
        e.continent = e.continent or e.dungeonContinent
    elseif status then
        e.distance = status
        for _, aid in ipairs(acts) do
            local dc = ns.GetActivityContinent(aid)
            if dc then
                e.dungeonContinent = e.dungeonContinent or dc
                if dc == e.continent then e.dungeonContinent = dc break end
            end
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

-- What a search covered, as a key: alerts compare results only with earlier ones for the same
-- search, so switching category doesn't announce everything in the new one as new.
function ns.SearchKey(cat, acts)
    local ids = {}
    for _, id in ipairs(acts or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return tostring(cat) .. ":" .. table.concat(ids, ",")
end

function ns.DoSearch()
    if not LFG.Search then
        ns.Print(L["Searching isn't available on this client."])
        return false
    end
    local cat, acts = ns.SearchTarget()
    if not cat or cat == 0 then
        ns.Print(L["Pick a category first."])
        return false
    end
    if ns.ClearPendingSearch then ns.ClearPendingSearch() end
    local ok, err = pcall(LFG.Search, cat, 0, 0, nil, false, nil, acts)
    if not ok then
        ns.Print(L["Search failed: "] .. tostring(err))
        return false
    end
    ns.searching, ns.searchFailed = true, false
    ns.lastSearchKey = ns.SearchKey(cat, acts)
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
-- How the game shows a listing's party, from its activities' display types: the note (Comment),
-- role counts, a player count, role seats, class icons or nothing. With several activities the
-- most informative wins, as in the game's LFGBrowseUtil_GetBestDisplayTypeForActivityIDs.
local DISPLAY_PRIORITY
function ns.BestDisplayType(activityIDs)
    local T = Enum and Enum.LFGListDisplayType
    if not T then return nil end
    DISPLAY_PRIORITY = DISPLAY_PRIORITY or {
        [T.Comment or -1] = 6, [T.RoleCount or -2] = 5, [T.PlayerCount or -3] = 4,
        [T.RoleEnumerate or -4] = 3, [T.ClassEnumerate or -5] = 2, [T.HideAll or -6] = 1,
    }
    local best, bestPriority = nil, 0
    for _, id in ipairs(activityIDs or {}) do
        local a = ns.GetActivity(id)
        local p = a and a.displayType and DISPLAY_PRIORITY[a.displayType]
        if p and p > bestPriority then best, bestPriority = a.displayType, p end
    end
    return best
end

local function BuildEntry(id, myActivities)
    local info = LFG.GetSearchResultInfo(id)
    if not info then return nil end

    local e = {
        id = id,
        info = info,
        members = {},
        activityIDs = info.activityIDs or {},
        age = info.age or 0,
        isSelf = info.hasSelf and true or false,
        -- Delisted since the search: kept, greyed out, as the game keeps them until the next search.
        isDelisted = info.isDelisted and true or false,
        displayType = ns.BestDisplayType(info.activityIDs),
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

    -- Listings for one of your own listed activities (the game puts these first, in blue, and
    -- names only the activities you share).
    if myActivities then
        e.matching = {}
        for _, aid in ipairs(e.activityIDs) do
            if tContains(myActivities, aid) then e.matching[#e.matching + 1] = aid end
        end
        e.matchesMine = #e.matching > 0
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

---------------------------------------------------------------------------
-- Hidden leaders and words
---------------------------------------------------------------------------
local function LeaderKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    return SafeLower(name)
end

function ns.IsLeaderIgnored(name)
    local key = LeaderKey(name)
    return key and ns.db.filters.ignoredLeaders[key] and true or false
end

function ns.IgnoreLeader(name)
    local key = LeaderKey(name)
    if not key then return end
    ns.db.filters.ignoredLeaders[key] = name -- the name as shown, for the list
    ns.Print((L["%s's listings are hidden. /seeker unignore %s shows them again."]):format(name, name))
    if ns.Render then ns.Render() end
end

-- True if they were hidden.
function ns.UnignoreLeader(name)
    local key = LeaderKey(name)
    if not key or not ns.db.filters.ignoredLeaders[key] then return false end
    ns.db.filters.ignoredLeaders[key] = nil
    if ns.Render then ns.Render() end
    return true
end

function ns.IgnoredLeaders()
    local list = {}
    for key, name in pairs(ns.db.filters.ignoredLeaders) do
        list[#list + 1] = type(name) == "string" and name or key
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

-- Hidden by you in Seeker, or (when that option is on) on the game's own ignore list.
function ns.IsHiddenLeader(name)
    if not name then return false end
    if ns.IsLeaderIgnored(name) then return true end
    if ns.db.filters.hideIgnored and C_FriendList and C_FriendList.IsIgnored then
        local ok, ignored = pcall(C_FriendList.IsIgnored, name)
        if ok and ignored then return true end
    end
    return false
end

-- The hide-words list, lowercased, parsed once per change.
local wordsCache, wordsSource
function ns.HiddenWords()
    local src = ns.db.filters.hideWords or ""
    if src ~= wordsSource then
        wordsSource, wordsCache = src, {}
        for word in src:gmatch("[^,]+") do
            word = SafeLower(strtrim(word))
            if word ~= "" then wordsCache[#wordsCache + 1] = word end
        end
    end
    return wordsCache
end

function ns.HasHiddenWord(e)
    local words = ns.HiddenWords()
    if #words == 0 then return false end
    local title, note = SafeLower(e.info and e.info.name), SafeLower(e.info and e.info.comment)
    for _, w in ipairs(words) do
        if title:find(w, 1, true) or note:find(w, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Instance lockouts
---------------------------------------------------------------------------
-- The raids (and dungeons) you're saved to, from the game's raid info: Browse marks groups for
-- them, and the List yourself page warns before you list for one. Only a lockout with a boss
-- down counts (an expired one stays listed until the reset, unlocked).
local savedInstances = {}

function ns.FetchSavedInstances()
    wipe(savedInstances)
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return end
    for i = 1, GetNumSavedInstances() or 0 do
        local ok, _, _, _, difficultyID, locked, _, _, _, _, _, total, done, _, mapID = pcall(GetSavedInstanceInfo, i)
        if ok and locked and mapID and (done or 0) > 0 and (total or 0) > 0 then
            savedInstances[#savedInstances + 1] = {
                mapID = mapID, difficultyID = difficultyID, total = total, done = done,
                redirected = C_RaidLocks and C_RaidLocks.GetRedirectedDifficultyID and C_RaidLocks.GetRedirectedDifficultyID(mapID, difficultyID),
            }
        end
    end
end

-- Bosses down and bosses in all, when you're saved to this activity's instance; else nil.
function ns.InstanceLock(activityID)
    if #savedInstances == 0 then return nil end
    local a = ns.GetActivity(activityID)
    if not (a and a.mapID and a.difficultyID) then return nil end
    for _, inst in ipairs(savedInstances) do
        if inst.mapID == a.mapID and (inst.difficultyID == a.difficultyID
            or (inst.redirected ~= nil and inst.redirected == a.redirectedDifficultyID)) then
            return inst.done, inst.total
        end
    end
end

-- A group's activities you're saved to: { { id, done, total }, ... }, and whether that's all of them.
function ns.EntryLocks(e)
    local locks = {}
    for _, id in ipairs(e.activityIDs or {}) do
        local done, total = ns.InstanceLock(id)
        if done then locks[#locks + 1] = { id = id, done = done, total = total } end
    end
    return locks, #locks > 0 and #locks == #(e.activityIDs or {})
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("UPDATE_INSTANCE_INFO")
    pcall(ev.RegisterEvent, ev, "BOSS_KILL")
    ev:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_INSTANCE_INFO" then
            ns.FetchSavedInstances()
            if ns.QueueRender then ns.QueueRender() end
        elseif RequestRaidInfo then
            RequestRaidInfo() -- answered with UPDATE_INSTANCE_INFO
        end
    end)
end

-- Open seats by role, from the game's own counts when it gives them.
function ns.Remaining(e, role)
    -- A group from chat: the roles its message asked for (none named, so it could be anything).
    if e.fromChat then
        if not e.chatNeeds then return 1 end
        return e.chatNeeds[role] and 1 or 0
    end
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

    if ns.IsHiddenLeader(e.leaderName) then return false end
    if ns.HasHiddenWord(e) then return false end

    -- Outside the activities you picked: hidden, or (with that option on) kept greyed out at the
    -- bottom, as the game greys them until the next search.
    local sel = ns.SelectedActivities()
    if sel and not ns.db.searchSelf then
        local found = false
        for _, id in ipairs(e.activityIDs) do if ns.db.activityIDs[id] then found = true break end end
        if not found then
            if not f.greyOutsidePick then return false end
            e.outsidePick = true
        end
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

    -- Zones between the leader and the dungeon's entrance (cards, tooltips, the Closest sort).
    local okH, hops = pcall(ns.ZoneHops, e.leader and e.leader.areaName, RelevantActivities(e))
    e.hops = okH and hops or nil
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
        -- Saved to every activity it's listed for: you couldn't go in with them. Marked, and with
        -- that option on, greyed out at the bottom.
        e.savedLocks, e.savedAll = ns.EntryLocks(e)
        if e.savedAll and f.greySaved then e.lockedOut = true end
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
    { key = "xp", label = L["Best XP first"] },
    { key = "newest", label = L["Newest first"] },
    { key = "oldest", label = L["Oldest first"] },
    { key = "levelLow", label = L["Level, low to high"] },
    { key = "levelHigh", label = L["Level, high to low"] },
    { key = "size", label = L["Biggest groups first"] },
    { key = "closest", label = L["Closest to the dungeon first"] },
    { key = "fit", label = L["Best fit for my roles (the game's order)"] },
}

local function Social(e) return (e.friends or 0) + (e.guildmates or 0) end

-- The game's own order (LFGBrowseUtil_SortSearchResults), worked out once per redraw. Groups: one
-- with a seat for a role you play first, then bigger groups, then ones needing a tank, then a
-- healer. Solo players: whoever can play the role your party most lacks first (tank, healer,
-- DPS, with roles your party already has moved to the end when you're listed for a dungeon).
local DUNGEON_EXPECTED = { TANK = 1, HEALER = 1, DAMAGER = 3 }
function ns.FitContext()
    local ctx = { order = { "TANK", "HEALER", "DAMAGER" } }
    ctx.roles = ns.MyListedRoles() or {}
    local listing = ns.HasListing() and ns.GetListing()
    local dungeonRoles = false
    for _, id in ipairs(listing and listing.activityIDs or {}) do
        local a = ns.GetActivity(id)
        if a and a.useDungeonRoleExpectations then dungeonRoles = true break end
    end
    local counts = dungeonRoles and GetGroupMemberCounts and GetGroupMemberCounts()
    if counts then
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            if (counts[role] or 0) >= DUNGEON_EXPECTED[role] then
                tDeleteItem(ctx.order, role)
                tinsert(ctx.order, role)
            end
        end
    end
    return ctx
end

local LEADER_ROLE_KEY = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
function ns.ComputeFit(e, ctx)
    local c = e.counts or {}
    if e.isSolo then
        e.fitRank = 99
        for i, role in ipairs(ctx.order) do
            local can = c["LEADER_ROLE_" .. role]
            if can == nil then can = e.roles and e.roles[LEADER_ROLE_KEY[role]] end
            if can then e.fitRank = i break end
        end
    else
        local my = ctx.roles
        e.fitTank = (c.TANK_REMAINING or 0) > 0 and my.tank and true or false
        e.fitHeal = (c.HEALER_REMAINING or 0) > 0 and my.healer and true or false
        local fitDPS = (c.DAMAGER_REMAINING or 0) > 0 and my.dps and true or false
        e.fitSlot = e.fitTank or e.fitHeal or fitDPS
        -- For the card and tooltip: which of your roles they still have a seat for (chat groups by
        -- the roles their message asked for).
        e.myFit = nil
        if not e.isSelf and not e.isDelisted then
            for _, role in ipairs({ "tank", "healer", "dps" }) do
                if my[role] and ns.Remaining(e, role) > 0 then
                    e.myFit = e.myFit or {}
                    e.myFit[#e.myFit + 1] = role
                end
            end
        end
    end
end

-- nil when the two are equal in the game's order.
local function FitBefore(a, b)
    if a.isSolo then
        if (a.fitRank or 99) ~= (b.fitRank or 99) then return (a.fitRank or 99) < (b.fitRank or 99) end
        return nil
    end
    if (a.fitSlot or false) ~= (b.fitSlot or false) then return a.fitSlot or false end
    if a.numMembers ~= b.numMembers then return a.numMembers > b.numMembers end
    if (a.fitTank or false) ~= (b.fitTank or false) then return a.fitTank or false end
    if (a.fitHeal or false) ~= (b.fitHeal or false) then return a.fitHeal or false end
    return nil
end

-- Closeness to the dungeon, for the Closest sort: inside it -1, then zones away, unknown 50,
-- another continent 99.
local function Closeness(e)
    if e.inDungeon then return -1 end
    if e.hops then return e.hops end
    if e.distance == "far" then return 99 end
    return 50
end

local function SortEntries(a, b)
    if a.isSelf ~= b.isSelf then return a.isSelf end
    -- Delisted, or outside your picked activities: greyed out, at the bottom.
    local da = (a.isDelisted or a.outsidePick or a.lockedOut) and true or false
    local db = (b.isDelisted or b.outsidePick or b.lockedOut) and true or false
    if da ~= db then return db end
    -- Group finder listings before chat posts (which say less, and may be stale).
    if (a.fromChat or false) ~= (b.fromChat or false) then return b.fromChat or false end
    if (a.matchesMine or false) ~= (b.matchesMine or false) then return a.matchesMine or false end
    local sa, sb = Social(a) > 0, Social(b) > 0
    if sa ~= sb then return sa end
    local mode = ns.db.sortMode
    local la, lb = a.maxLevel or 0, b.maxLevel or 0
    if mode == "fit" then
        local before = FitBefore(a, b)
        if before ~= nil then return before end
        if (a.age or 0) ~= (b.age or 0) then return (a.age or 0) > (b.age or 0) end -- older first, as the game
        return a.id < b.id
    end
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
    elseif mode == "closest" then
        -- Inside the dungeon, then by zones away; another continent and unknown last.
        local ha, hb = Closeness(a), Closeness(b)
        if ha ~= hb then return ha < hb end
    end
    local ra, rb = XP_RANK[a.xpStatus] or 0, XP_RANK[b.xpStatus] or 0
    if ra ~= rb then return ra > rb end
    -- Equal on XP: the game's own order (a seat for your role, then size), then newest.
    local before = FitBefore(a, b)
    if before ~= nil then return before end
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

-- The roles your party still needs: { tank, healer, dps }, all false when it's full; nil when
-- you're not in one. A dungeon party wants a tank, a healer and three DPS; a raid always takes
-- DPS. You count as the role you're listed as when you haven't been given one. Also returns
-- whether anyone has no role (a role check makes it more accurate).
function ns.MyGroupNeeds()
    if not IsInGroup() then return nil end
    local units = ns.MyGroupUnits()
    local inRaid = IsInRaid and IsInRaid()
    if not inRaid and #units >= 5 then return { tank = false, healer = false, dps = false }, false end
    local t, h, d, unassigned = 0, 0, 0, false
    for _, unit in ipairs(units) do
        local r = UnitGroupRolesAssigned(unit)
        if (not r or r == "NONE") and UnitIsUnit(unit, "player") then
            local mine = ns.MyListedRoles()
            local n = mine and ((mine.tank and 1 or 0) + (mine.healer and 1 or 0) + (mine.dps and 1 or 0)) or 0
            if n == 1 then r = mine.tank and "TANK" or mine.healer and "HEALER" or "DAMAGER" end
        end
        if r == "TANK" then t = t + 1 elseif r == "HEALER" then h = h + 1 elseif r == "DAMAGER" then d = d + 1
        else unassigned = true end
    end
    if inRaid then return { tank = t < 2, healer = h < 5, dps = true }, unassigned end
    return { tank = t == 0, healer = h == 0, dps = d < 3 }, unassigned
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
    e.roles = ns.MyListedRoles()
    return e
end

-- The roles you're listed (or about to list) as: the game's, else your saved ones, else the List
-- yourself page's ticks. A table with none ticked counts as none (the game can answer with one).
local function AnyRole(r)
    return type(r) == "table" and (r.tank or r.healer or r.dps) and r or nil
end

function ns.MyListedRoles()
    local api = C_LFGListRoles or {}
    for _, fn in ipairs({ api.GetRoles, api.GetSavedRoles }) do
        local ok, r = pcall(fn)
        if ok and AnyRole(r) then return r end
    end
    local page = ns.Listing and ns.Listing.roles
    return AnyRole(page) and { tank = page.tank, healer = page.healer, dps = page.dps } or nil
end

function ns.GetFiltered()
    local groups, players = ns.Collect()
    -- Your party card replaces the game's result for your own listing.
    local mine = ns.BuildMyGroupEntry()
    if mine then
        for _, list in ipairs({ groups, players }) do
            for i = #list, 1, -1 do
                if list[i].isSelf then
                    -- The game's own result knows the roles you listed as, if nothing else did.
                    if not AnyRole(mine.roles) and AnyRole(list[i].roles) then mine.roles = list[i].roles end
                    table.remove(list, i)
                end
            end
        end
        if mine.isSolo then table.insert(players, 1, mine) else table.insert(groups, 1, mine) end
    end
    -- Groups and players looking in chat (Chat.lua), unless they also have a listing here.
    if ns.ChatEntries then
        local listed = {}
        for _, list in ipairs({ groups, players }) do
            for _, e in ipairs(list) do
                local key = e.leaderName and ns.LocationKey(e.leaderName)
                if key then listed[key] = true end
            end
        end
        local cg, cp = ns.ChatEntries(listed)
        for _, e in ipairs(cg) do groups[#groups + 1] = e end
        for _, e in ipairs(cp) do players[#players + 1] = e end
    end
    -- Everyone with a listing or chat post right now, filtered or not, by first name.
    local listedNow = {}
    for _, list in ipairs({ groups, players }) do
        for _, e in ipairs(list) do
            local key = not e.isSelf and e.leaderName and ns.LocationKey(e.leaderName)
            if key then listedNow[key] = e end
        end
    end
    ns.listedNow = listedNow
    local f = ns.db.filters
    local fg, fp = {}, {}
    local ctx = ns.FitContext()
    for _, e in ipairs(groups) do if Passes(e, f) then ns.ComputeFit(e, ctx) fg[#fg + 1] = e end end
    for _, e in ipairs(players) do if Passes(e, f) then ns.ComputeFit(e, ctx) fp[#fp + 1] = e end end
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

-- Kept by first name. In Forever a character's name is a first name and a surname ("Albis
-- Frost"); the first name alone is the character's own, unique name. /who finds people by it,
-- and some sources (the game's /who answers, your friends list) may give only it, so "Albis" and
-- "Albis Frost" must be the same person here.
local function LocationKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    name = name:match("^[^-]+") or name        -- no realm
    return (name:match("^%S+") or name):lower() -- the first name
end
ns.LocationKey = LocationKey

-- level and classFile when the source says (a /who answer does): chat posts don't, so a lookup
-- for a poster also tells Seeker their level and class.
-- Older than this, a remembered player is dropped (about once a minute): their zone is long out
-- of date, and the guild roster and /who answers would otherwise pile up all session.
local FORGET_AFTER = 60 * 60
local lastForget = 0

function ns.RememberLocation(name, zone, source, level, classFile)
    local key = LocationKey(name)
    if not key or type(zone) ~= "string" or zone == "" then return end
    local now = GetTime()
    if now - lastForget > 60 then
        lastForget = now
        for k, l in pairs(locations) do
            if now - l.time > FORGET_AFTER then locations[k] = nil end
        end
    end
    local old = locations[key]
    locations[key] = {
        zone = zone, time = GetTime(), source = source,
        level = level or (old and old.level), classFile = classFile or (old and old.classFile),
    }
end

-- What Seeker knows about a player from any source, recent or not: { zone, time, level, classFile }.
function ns.GetKnownPlayer(name)
    return locations[LocationKey(name) or ""]
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
        if info then ns.RememberLocation(info.fullName, info.area, "who", info.level, info.filename) end
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
ns.EndQuietLookup = EndQuietLookup

function ns.IsQuietLookup()
    return ns.silentWhoUntil ~= nil and GetTime() < ns.silentWhoUntil
end

-- A /who that isn't one of Seeker's quiet lookups (typed in chat, another addon's, or the Who tab)
-- ends any lookup in progress at once, so its answer goes where it was meant to and isn't swallowed.
local quietSending = false
if C_FriendList and C_FriendList.SendWho and hooksecurefunc then
    hooksecurefunc(C_FriendList, "SendWho", function()
        if not quietSending and ns.silentWhoUntil then EndQuietLookup() end
    end)
end

-- Finding where a listing's members are, when you ask: the map button on a card scans that one
-- group (or chat poster), so only the few players you're interested in are looked up, never the
-- whole result list. The game only runs /who from a click or key press, and allows about one every
-- five seconds: the button's click runs the first lookup, and each click, scroll or key press in
-- Seeker's window after it runs the next. Answers come back without a window or chat line, and
-- an open tooltip updates itself.
-- Two kinds of lookup:
--   a zone sweep, /who z-"<zone>" <levels>: everyone in the group's lister's zone within the
--     group's level range. Groups usually gather in one place, so one sweep often finds them all.
--   a name, /who n-"<first name>": one member the sweep (if any) didn't find.
local WHO_GAP = 5.5           -- the game answers about one /who every five seconds
local ANSWER_WAIT = 6         -- no answer by then: the game dropped it (throttled); try again once
local ASKED_AGAIN_AFTER = 120 -- don't ask about the same name (or sweep the same zone) again for two minutes
local lastLookup = 0
local queue = {}     -- entries, next first: { kind = "name"|"zone", key, name | zone, lo, hi, members, prio, tries }
local queued = {}    -- entry key -> entry
local asked = {}     -- name key -> when last asked
local notFound = {}  -- name key -> when a lookup came back without them (offline, or hidden from /who)
local swept = {}     -- zone entry key -> when swept
local inFlight       -- the entry waiting for its answer

local ShortKey = LocationKey

local function NeedsLookup(p)
    if not p.name or (p.areaName and p.areaName ~= "") or ns.GetKnownLocation(p.name) then return false end
    local key = ShortKey(p.name)
    local t = asked[key]
    if t and GetTime() - t <= ASKED_AGAIN_AFTER then return false end
    return true
end

local function Enqueue(entry, front)
    local old = queued[entry.key]
    if old then
        if not front then return end
        for i, q in ipairs(queue) do if q == old then table.remove(queue, i) break end end
        entry.tries = old.tries
    end
    queued[entry.key] = entry
    if front then table.insert(queue, 1, entry) else queue[#queue + 1] = entry end
end

-- Queue lookups for these members of a group (e, when given, for its lister's zone): a zone sweep
-- first when two or more are unknown, then each by name. first = true puts them at the front (a
-- group you're looking at).
function ns.QueueLocate(members, first, e)
    local unknown = {}
    for _, p in ipairs(members or {}) do
        if ShortKey(p.name) and NeedsLookup(p) then unknown[#unknown + 1] = p end
    end
    if #unknown == 0 then return end
    local entries = {}
    local leader = e and e.leader
    local zone = leader and ((leader.areaName ~= "" and leader.areaName) or ns.GetKnownLocation(leader.name))
    if zone and #unknown >= 2 then
        local lo, hi, inSweep = 999, 0, {}
        for _, p in ipairs(unknown) do
            if p.level then lo, hi = math.min(lo, p.level), math.max(hi, p.level) end
            inSweep[ShortKey(p.name)] = true
        end
        if hi == 0 then lo, hi = 1, 99 end
        local key = ("zone:%s:%d-%d"):format(zone:lower(), lo, hi)
        local t = swept[key]
        if not t or GetTime() - t > ASKED_AGAIN_AFTER then
            entries[#entries + 1] = { kind = "zone", key = key, zone = zone, lo = lo, hi = hi, members = inSweep }
        end
    end
    for _, p in ipairs(unknown) do
        entries[#entries + 1] = { kind = "name", key = "name:" .. ShortKey(p.name), name = p.name, nameKey = ShortKey(p.name) }
    end
    -- To the front in order (sweep first), or to the back.
    if first then
        for i = #entries, 1, -1 do entries[i].prio = true Enqueue(entries[i], true) end
    else
        for _, entry in ipairs(entries) do Enqueue(entry, false) end
    end
end


-- Still worth sending? A name already found (by a sweep, say), or a zone swept a moment ago, isn't.
local function StillNeeded(entry)
    if entry.kind == "zone" then
        local t = swept[entry.key]
        if t and GetTime() - t <= ASKED_AGAIN_AFTER then return false end
        for key in pairs(entry.members) do
            if not ns.GetKnownLocation(key) then return true end
        end
        return false
    end
    if ns.GetKnownLocation(entry.name) then return false end
    local t = asked[entry.nameKey]
    return not (t and GetTime() - t <= ASKED_AGAIN_AFTER)
end

local function RefreshOpenTooltip()
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner and owner.item and ns.ShowEntryTooltip then ns.ShowEntryTooltip(owner, owner.item) end
end

-- Run the next lookup, if one's waiting and the game would allow it. Called from clicks, scrolls
-- and key presses (a /who needs one); harmless to call often. fromKey: a key press anywhere while
-- Seeker's window is open, which no search or post is waiting on.
function ns.PumpLocate(fromKey)
    if #queue == 0 or not (C_FriendList and C_FriendList.SendWho) then return end
    if GetTime() - lastLookup < WHO_GAP or inFlight then return end
    if ns.IsWhoPageShown and ns.IsWhoPageShown() then return end -- the Who tab is yours
    if ns.whoUntil and GetTime() < ns.whoUntil then return end
    if not fromKey then
        -- The game allows one search or /who per click: a click that opens or picks from a menu
        -- (the category and activity menus search), or one on the List yourself page (posting),
        -- keeps it.
        local okM, menuOpen = pcall(function() return Menu and Menu.GetManager and Menu.GetManager():GetOpenMenu() end)
        if okM and menuOpen then return end
        local win = _G.SeekerLFGFrame
        if win and win.pages and win.pages.listing and win.pages.listing:IsShown() then return end
    end
    while #queue > 0 do
        local entry = table.remove(queue, 1)
        queued[entry.key] = nil
        if StillNeeded(entry) then
            local query
            if entry.kind == "zone" then
                swept[entry.key] = GetTime()
                query = ('z-"%s" %d-%d'):format(entry.zone, entry.lo, entry.hi)
            else
                asked[entry.nameKey] = GetTime()
                -- By first name: the character's own name, which /who matches.
                query = ('n-"%s"'):format((entry.name:match("^[^-]+") or entry.name):match("^%S+") or entry.name)
            end
            lastLookup = GetTime()
            inFlight = entry
            local started = GetTime()
            ns.silentWhoUntil = started + ANSWER_WAIT
            MuteGameWho()
            if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end -- results to Seeker, not chat
            quietSending = true
            local ok = pcall(C_FriendList.SendWho, query)
            quietSending = false
            if not ok then
                inFlight = nil
                EndQuietLookup()
                return
            end
            -- No answer: the game dropped it (another /who just before, most likely). Ask once more.
            C_Timer.After(ANSWER_WAIT + 0.5, function()
                if inFlight ~= entry then return end
                inFlight = nil
                EndQuietLookup()
                if (entry.tries or 0) < 1 then
                    entry.tries = (entry.tries or 0) + 1
                    if entry.kind == "zone" then swept[entry.key] = nil else asked[entry.nameKey] = nil end
                    Enqueue(entry, true)
                end
                RefreshOpenTooltip()
            end)
            return
        end
    end
end

-- Where a lookup for this player stands: "looking" (asked, waiting for the answer), "queued",
-- "notfound" (the answer didn't have them: offline, or hidden from /who), or nil.
function ns.LocateState(name)
    local key = ShortKey(name)
    if not key then return nil end
    if inFlight and ((inFlight.kind == "name" and inFlight.nameKey == key) or (inFlight.kind == "zone" and inFlight.members[key])) then
        return "looking"
    end
    if queued["name:" .. key] then return "queued" end
    for _, q in ipairs(queue) do
        if q.kind == "zone" and q.members[key] then return "queued" end
    end
    local t = notFound[key]
    if t and GetTime() - t <= ASKED_AGAIN_AFTER then return "notfound" end
    return nil
end

-- A listing's members (a group's, or a chat poster) whose zone isn't known and isn't being looked
-- up or just came back not found: what its map button would scan.
function ns.UnknownMembers(e)
    local out = {}
    if not e or e.isSelf or e.isDelisted then return out end
    for _, p in ipairs(e.members or {}) do
        if p.name and (not p.areaName or p.areaName == "") and not ns.GetKnownLocation(p.name)
            and not ns.LocateState(p.name) then
            out[#out + 1] = p
        end
    end
    return out
end

-- Scan one listing (its map button): its lookups go to the front of the queue (a zone sweep first
-- for a group), and the first runs now, on the button's click. Returns how many members it's for.
function ns.LocateEntry(e)
    local members = ns.UnknownMembers(e)
    if #members == 0 then return 0 end
    ns.QueueLocate(members, true, e)
    ns.PumpLocate(true)
    if ns.QueueRender then ns.QueueRender() end
    return #members
end

-- A /who answer arrived. Remember it, and if it was one of Seeker's quiet lookups, note who it
-- didn't find, send /who results back to chat (unless the Who tab is open) and refresh the
-- tooltip on show.
function ns.OnWhoListUpdate()
    ns.RememberWhoResults()
    if ns.silentWhoUntil and GetTime() < ns.silentWhoUntil then
        local entry = inFlight
        inFlight = nil
        if entry and entry.kind == "name" and not ns.GetKnownLocation(entry.name) then
            notFound[entry.nameKey] = GetTime()
        end
        -- Seeker hears /who answers before the game does, so the quiet lookup is only ended on the
        -- next frame, after the game's own listeners have (not) seen this one.
        C_Timer.After(0, function()
            EndQuietLookup()
            RefreshOpenTooltip()
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
-- Every listing seen this session, per search (category and activities). The first results of
-- each search are only remembered, so you're told about what's new since, not about everything
-- already listed when you first look somewhere. Every result is remembered, filtered out or not,
-- so loosening a filter doesn't announce listings you could have seen all along.
local seenBySearch = {}

-- A listing's lasting identity: its leader and what it's for. The game can number the same
-- listing differently from one search to the next, so the result ID alone made everything
-- "new" again. Nil while the game hasn't sent the leader's name yet.
local function ListingKey(e)
    local who = pcall(LeaderKey, e.leaderName) and LeaderKey(e.leaderName)
    if not who then return nil end
    local acts = {}
    for i, id in ipairs(e.activityIDs or {}) do acts[i] = id end
    table.sort(acts)
    return who .. "|" .. table.concat(acts, ",")
end

local function AlertSound()
    local kit = SOUNDKIT and (SOUNDKIT.UI_GROUP_FINDER_RECEIVE_APPLICATION or SOUNDKIT.RAID_WARNING or SOUNDKIT.READY_CHECK)
    if kit then PlaySound(kit, "Master") end
end

-- Called whenever search results arrive (from Seeker's search, a keybinding, or the game's own).
-- searchKey: what the search covered (ns.SearchKey); a search Seeker didn't make has its own.
function ns.CheckNewMatches(searchKey)
    local a = ns.db.alerts
    searchKey = searchKey or "other"
    local seen = seenBySearch[searchKey]
    local primed = seen ~= nil
    if not seen then
        seen = {}
        seenBySearch[searchKey] = seen
    end
    -- Everything the search found, filtered out or not, by its leader and activities.
    local all = {}
    local okAll, allGroups, allPlayers = pcall(ns.Collect)
    if okAll then
        for _, list in ipairs({ allGroups, allPlayers }) do
            for _, e in ipairs(list) do
                local key = ListingKey(e)
                if key then all[key] = true end
                -- And by result ID: one seen before its leader's name arrived isn't new once it does.
                if e.id then all["#" .. tostring(e.id)] = true end
            end
        end
    end
    local ok, groups, players = pcall(ns.GetFiltered)
    if not ok then return end
    local fresh = {}
    for _, list in ipairs({ groups, players }) do
        for _, e in ipairs(list) do
            -- One whose leader the game hasn't named yet isn't announced (nothing to say who);
            -- it's announced once its name arrives, if it's still new then.
            local key = ListingKey(e)
            if primed and key and not seen[key] and not seen["#" .. tostring(e.id)] and not e.isSelf and not e.isDelisted and not e.outsidePick
                and not e.fromChat and (not a.fullXPOnly or e.xpStatus == "safe") then
                fresh[#fresh + 1] = e
            end
        end
    end
    for key in pairs(all) do seen[key] = true end
    if not a.enabled or #fresh == 0 then return end
    if a.mode ~= "all" then return ns.AlertRoles(fresh, a) end

    local parts = {}
    for i = 1, math.min(3, #fresh) do
        local e = fresh[i]
        local act = e.xpActivity or RelevantActivities(e)[1]
        local kind = e.isSolo and L["player"] or (L["group %d/%d"]):format(e.numMembers, e.maxPlayers)
        parts[#parts + 1] = (L["%s (%s, %s, lvl %s)"]):format(ns.ShortName and ns.ShortName(e.leaderName) or e.leaderName or "?",
            kind, act and ns.GetActivityName(act) or "?", e.maxLevel and tostring(e.maxLevel) or "?")
    end
    local more = #fresh > 3 and (L[" and %d more"]):format(#fresh - 3) or ""
    ns.Print((L["%d new: %s%s. |cff999999/seeker to open|r"]):format(#fresh, table.concat(parts, ", "), more))
    if a.sound then AlertSound() end
    if a.flash and FlashClientIcon then FlashClientIcon() end
end

-- The roles alerts: in a party, new players who can play a role it still needs ("Healer listed:
-- Bob"); on your own, new groups with a seat for one of your roles. Names are links: click one
-- to whisper them.
local ROLE_WORDS = { tank = TANK or L["Tank"], healer = HEALER or L["Healer"], dps = DAMAGER or L["DPS"] }

local function NameLink(e)
    local full = e.leaderName or "?"
    local short = ns.ShortName and ns.ShortName(full) or full
    return ("|Hplayer:%s|h[%s]|h"):format(full, short)
end

local function WhereBit(e)
    local act = e.xpActivity or RelevantActivities(e)[1]
    local bits = { act and ns.GetActivityName(act) or nil }
    if e.inDungeon then
        bits[#bits + 1] = L["inside"]
    elseif e.hops then
        bits[#bits + 1] = e.hops == 0 and L["same zone"] or e.hops == 1 and L["1 zone away"] or (L["%d zones away"]):format(e.hops)
    end
    return table.concat(bits, ", ")
end

function ns.AlertRoles(fresh, a)
    local lines = {}
    local need = ns.MyGroupNeeds()
    if need then
        -- In a party: players who can fill what it's missing.
        for _, e in ipairs(fresh) do
            if e.isSolo and e.roles then
                local can = {}
                for _, key in ipairs({ "tank", "healer", "dps" }) do
                    if need[key] and e.roles[key] then can[#can + 1] = ROLE_WORDS[key] end
                end
                if #can > 0 then
                    lines[#lines + 1] = (L["%s listed: %s, level %s (%s)"]):format(table.concat(can, "/"), NameLink(e),
                        e.maxLevel and tostring(e.maxLevel) or "?", WhereBit(e))
                end
            end
        end
    else
        -- On your own: groups with a seat for you.
        for _, e in ipairs(fresh) do
            if not e.isSolo and e.myFit and #e.myFit > 0 then
                local as = {}
                for _, key in ipairs(e.myFit) do as[#as + 1] = ROLE_WORDS[key] end
                lines[#lines + 1] = (L["Room for you as %s: %s's group, %d/%d, level %s (%s)"]):format(table.concat(as, "/"),
                    NameLink(e), e.numMembers, e.maxPlayers, e.maxLevel and tostring(e.maxLevel) or "?", WhereBit(e))
            end
        end
    end
    if #lines == 0 then return end
    for i = 1, math.min(3, #lines) do ns.Print(lines[i]) end
    if #lines > 3 then ns.Print((L["...and %d more. |cff999999/seeker to open|r"]):format(#lines - 3)) end
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

-- Why you can't invite anyone right now, or nil when you can: only the leader or an assistant
-- can invite, and a raid holds 40. A full party of five is fine: the game offers to convert it
-- to a raid when you invite a sixth, as its own Invite button allows.
function ns.InviteBlocker()
    if not IsInGroup() then return nil end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return L["Only the leader or an assistant can invite."]
    end
    if IsInRaid and IsInRaid() and (GetNumGroupMembers() or 0) >= 40 then
        return L["Your raid is full."]
    end
    return nil
end

-- The game only lets you invite solo players, and only when you can invite (see InviteBlocker).
function ns.CanInvite(e)
    if not e or not e.isSolo or e.isSelf then return false end
    return ns.InviteBlocker() == nil
end

-- viaPopup: invite as the game's Who list does (UnitPopupSharedUtil.TryInvite, which handles the
-- game's own invite rules and confirmations), else as its Browse page does (InviteUnit).
function ns.Invite(name, viaPopup)
    if not name then return end
    local blocker = ns.InviteBlocker()
    if blocker then
        ns.Print(blocker)
        return false
    end
    if ns.MarkContact then ns.MarkContact(name, "invited") end -- cards show it, then the answer
    if viaPopup and UnitPopupSharedUtil and UnitPopupSharedUtil.TryInvite then
        local ok = pcall(UnitPopupSharedUtil.TryInvite, { name = name }, "INVITE", name)
        if ok then return true end
    end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
    return true
end

-- Forever has no applications: you ask the leader. This opens a whisper with a request ready to
-- send (your level, class, roles and the dungeon); you press Enter to send it.
---------------------------------------------------------------------------
-- Message templates (Request to join, and the optional whisper sent with an invite)
---------------------------------------------------------------------------
ns.DEFAULT_REQUEST_MESSAGE = L["Hi! Could I join you for [dungeon]? I'm a level [level] [class] ([roles])."]
ns.DEFAULT_INVITE_MESSAGE = "" -- empty: inviting sends no whisper, as the game's Invite
ns.MAX_WHISPER = 255

-- The placeholders, in the order the Messages window lists them.
ns.MESSAGE_TOKENS = {
    { "level", L["your level"] },
    { "class", L["your class"] },
    { "roles", L["the roles you've ticked, e.g. Tank/Healer"] },
    { "dungeon", L["the dungeon they're listed for"] },
    { "name", L["your name"] },
    { "target", L["their name"] },
    { "zone", L["the zone you're in"] },
}

local function MyRoles()
    local roles = {}
    local r = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
    if r then
        if r.tank then roles[#roles + 1] = TANK or L["Tank"] end
        if r.healer then roles[#roles + 1] = HEALER or L["Healer"] end
        if r.dps then roles[#roles + 1] = DAMAGER or L["DPS"] end
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
        name = ns.UnitFullName("player") or "",
        target = e and ns.ShortName and ns.ShortName(e.leaderName) or (e and e.leaderName) or "",
        zone = GetRealZoneText and GetRealZoneText() or "",
    }
    local text = template:gsub("%[(%a+)%]", function(key)
        local v = values[key:lower()]
        return v -- unknown [words] are left as typed
    end)
    text = text:gsub("%(%s*%)", ""):gsub("%[%s*%]", ""):gsub("  +", " "):gsub("%s+([%.,!?])", "%1")
    text = strtrim(text)
    return ns.TrimToBytes(text, ns.MAX_WHISPER)
end

-- Cut text to at most this many bytes without splitting a character (UTF-8: a character's
-- continuation bytes are 0x80-0xBF, so step back off them), as a whisper can't carry half of one.
function ns.TrimToBytes(text, maxBytes)
    if #text <= maxBytes then return text end
    local cut = maxBytes
    while cut > 0 do
        local nextByte = text:byte(cut + 1)
        if not nextByte or nextByte < 0x80 or nextByte > 0xBF then break end
        cut = cut - 1
    end
    return text:sub(1, cut)
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
    if ns.MarkContact then ns.MarkContact(e.leaderName, "requested") end
end

-- Invite a listed player, and whisper them your invite message if you've set one. The click is
-- what sends it, as the invite itself.
function ns.InviteListed(e)
    if not e or not e.leaderName then return end
    if not ns.Invite(e.leaderName) then return end
    local msg = ns.RenderMessage(ns.InviteMessage(), e)
    if msg ~= "" and SendChatMessage then
        local ok, err = pcall(SendChatMessage, msg, "WHISPER", nil, e.leaderName)
        if not ok then ns.Print(L["Couldn't send your invite message: "] .. tostring(err)) end
    end
end

-- Whether you can use the group finder at all (the game refuses to open its window otherwise,
-- e.g. below the level it needs). Returns true, or false and the game's reason.
function ns.CanUseGroupFinder()
    if not (C_LFGInfo and C_LFGInfo.CanPlayerUsePremadeGroup) then return true end
    local ok, canUse, reason = pcall(C_LFGInfo.CanPlayerUsePremadeGroup)
    if not ok or canUse ~= false then return true end
    if type(reason) ~= "string" or reason == "" then
        reason = L["You can't use the group finder yet."]
    end
    return false, reason
end

-- The game's own group finder loads on demand, the first time its window opens. Seeker borrows its
-- description box and can open its window, so it loads it itself (out of combat, as loading a
-- part of the game's interface then is safest).
local NATIVE_ADDON = "Blizzard_GroupFinder_VanillaStyle"
function ns.LoadNativeFinder()
    if _G.LFGListingComment then return true end
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded(NATIVE_ADDON) then return true end
    if InCombatLockdown and InCombatLockdown() then return false end
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not load then return false end
    local ok, loaded = pcall(load, NATIVE_ADDON)
    return ok and loaded and true or false
end

function ns.ReportListing(e, advertisement)
    if not (ReportInfo and ReportFrame and Enum.ReportType and Enum.ReportType.GroupFinderPosting) then
        ns.Print(L["Reporting isn't available here."])
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
    if not ok then ns.Print(L["Couldn't open the report: "] .. tostring(err)) end
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
    ns.Print(L["  Comment box:"], _G.LFGListingComment and "found" or L["not loaded"])
    ns.Print(L["  Game LFG windows found:"], #(ns.nativeFound or {}) > 0 and table.concat(ns.nativeFound, ", ") or L["none yet"])
    ns.Print(L["  Replace mode:"], ns.db.replaceNative and "on" or "off")
    ns.Print(L["  Listed:"], ns.HasListing() and "yes" or "no")
    local getter = LFG.GetFilteredSearchResults or LFG.GetSearchResults
    if not getter then return end
    local total, results = getter()
    ns.Print(L["Results:"], tostring(total))
    local id = results and results[1]
    if not id then return end
    local info = LFG.GetSearchResultInfo(id)
    if info then
        for k, v in pairs(info) do ns.Print("  info." .. tostring(k), tostring(v)) end
    end
end
