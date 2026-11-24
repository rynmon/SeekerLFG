-- Seeker LFG: groups and players looking in chat. On a classic-style server many groups still form
-- in the LookingForGroup and world channels, not the group finder. Seeker reads those messages
-- ("LF2M SM Arm need heal", "Priest LFG DM"), works out the dungeon, whether it's a group looking
-- for more (LFM) or a player looking for a group (LFG), and which roles, and shows them as cards
-- beside the group finder's, with the same filters. English messages only.
local ADDON, ns = ...
local L = ns.L -- translations (Locale.lua)

local POST_TTL = 10 * 60 -- a post is shown for ten minutes, or until its poster posts again
local posts = {}         -- poster's first-name key -> post
local nextID = -1000     -- chat cards get negative ids, apart from the game's search results

---------------------------------------------------------------------------
-- Reading a message
---------------------------------------------------------------------------
-- Lowercase words with single spaces and a space at each end, so " word " finds whole words.
-- Colours and links are dropped; apostrophes stay (Zul'Farrak).
local function Normalize(s)
    -- Links first (|Hitem:123|h[Name]|h keeps "[Name]"), while their codes are still in their case.
    s = (s or ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:lower():gsub("[^%w']", " "):gsub("%s+", " ")
    return " " .. strtrim(s) .. " "
end

local function Has(t, word) return t:find(" " .. word .. " ", 1, true) ~= nil end

-- Every activity the game has, by its name, to match messages against: built once, and again
-- when what's available changes.
local index
local function BuildIndex()
    index = { all = {}, firstWord = {} }
    local LFG = C_LFGList
    if not (LFG and LFG.GetAvailableCategories and LFG.GetAvailableActivities) then return end
    local firstCount, firstID = {}, {}
    local STOP = { lower = true, upper = true, the = true, ruins = true, temple = true, old = true,
        hall = true, halls = true, city = true, keep = true, tower = true, scarlet = true, blackrock = true,
        dire = true, razorfen = true, stratholme = true }
    for _, cat in ipairs(LFG.GetAvailableCategories() or {}) do
        for _, id in ipairs(LFG.GetAvailableActivities(cat) or {}) do
            local a = ns.GetActivity(id)
            if a and a.fullName then
                local full = Normalize(a.fullName):gsub("^ the ", " ")
                index.all[#index.all + 1] = { id = id, full = full, short = a.shortName and a.shortName ~= "" and Normalize(a.shortName) }
                -- A distinctive first word on its own ("krol'dok", "uldaman"), if no other activity shares it.
                local first = full:match("^ (%S+)")
                if first and #first >= 5 and not STOP[first] then
                    firstCount[first] = (firstCount[first] or 0) + 1
                    firstID[first] = id
                end
            end
        end
    end
    for word, n in pairs(firstCount) do
        if n == 1 then index.firstWord[word] = firstID[word] end
    end
end

-- Activities whose name has all these phrases.
local function ByPhrases(found, ...)
    local phrases = { ... }
    for _, entry in ipairs(index.all) do
        local ok = true
        for _, p in ipairs(phrases) do
            if not entry.full:find(p, 1, true) then ok = false break end
        end
        if ok then found[entry.id] = true end
    end
end

-- The usual abbreviations: word -> phrases an activity's name must contain.
local ALIASES = {
    rfc = { "ragefire" }, wc = { "wailing caverns" }, vc = { "deadmines" }, deadmines = { "deadmines" },
    sfk = { "shadowfang" }, stocks = { "stockade" }, stockade = { "stockade" }, stockades = { "stockade" },
    bfd = { "blackfathom" }, gnomer = { "gnomeregan" }, rfk = { "razorfen kraul" }, rfd = { "razorfen downs" },
    ulda = { "uldaman" }, uld = { "uldaman" }, zf = { "zul'farrak" }, zulfarrak = { "zul'farrak" },
    mara = { "maraudon" }, st = { "sunken temple" }, brd = { "blackrock depths" },
    lbrs = { "lower blackrock" }, ubrs = { "upper blackrock" }, scholo = { "scholomance" }, scholomance = { "scholomance" },
    dme = { "dire maul", "east" }, dmw = { "dire maul", "west" }, dmn = { "dire maul", "north" },
    cath = { "cathedral" }, cathedral = { "cathedral" }, armory = { "armory" }, armoury = { "armory" },
    graveyard = { "graveyard" }, library = { "library" },
    mc = { "molten core" }, ony = { "onyxia" }, onyxia = { "onyxia" }, bwl = { "blackwing" }, zg = { "zul'gurub" },
    aq20 = { "ruins of ahn'qiraj" }, aq40 = { "temple of ahn'qiraj" }, naxx = { "naxxramas" },
    wsg = { "warsong" }, av = { "alterac valley" }, stv = { "stranglethorn" },
}

-- Which activities a message is about (a set of ids), or nil.
local function FindActivities(t)
    if not index then BuildIndex() end
    local found = {}
    for word, phrases in pairs(ALIASES) do
        if Has(t, word) then ByPhrases(found, unpack(phrases)) end
    end
    -- Scarlet Monastery: "sm" or "scarlet", with a wing (gy, lib, arm, cath) or all of them.
    if Has(t, "sm") or Has(t, "scarlet") then
        local wings = { gy = "graveyard", graveyard = "graveyard", lib = "library", library = "library",
            arm = "armory", armory = "armory", armoury = "armory", cath = "cathedral", cathedral = "cathedral" }
        local any = false
        for word, wing in pairs(wings) do
            if Has(t, word) then ByPhrases(found, wing) any = true end
        end
        if not any then ByPhrases(found, "scarlet") end
    end
    -- "dm": the Deadmines, unless a Dire Maul wing follows ("dm east", "dm n", "dm tribute").
    if Has(t, "dm") then
        local wing
        for word, w in pairs({ east = "east", e = "east", west = "west", w = "west", north = "north", n = "north", tribute = "north", trib = "north" }) do
            if t:find(" dm " .. word .. " ", 1, true) then wing = w end
        end
        if wing then ByPhrases(found, "dire maul", wing) else ByPhrases(found, "deadmines") end
    end
    if t:find(" dire maul ", 1, true) and not next(found) then ByPhrases(found, "dire maul") end
    -- Stratholme: undead side (Service Gate) or live side (Main Gate), else both.
    if Has(t, "strat") or Has(t, "stratholme") then
        if Has(t, "ud") or Has(t, "undead") or Has(t, "dead") or Has(t, "service") then
            ByPhrases(found, "stratholme", "service")
        elseif Has(t, "live") or Has(t, "living") or Has(t, "main") then
            ByPhrases(found, "stratholme", "main")
        else
            ByPhrases(found, "stratholme")
        end
    end
    -- Any activity named in full ("scarlet armory", "krol'dok stronghold"), or by its distinctive first word.
    for _, entry in ipairs(index.all) do
        if t:find(entry.full, 1, true) or (entry.short and t:find(entry.short, 1, true)) then found[entry.id] = true end
    end
    for word, id in pairs(index.firstWord) do
        if Has(t, word) then found[id] = true end
    end
    if not next(found) then return nil end
    local ids = {}
    for id in pairs(found) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local ROLE_WORDS = { tank = { "tank", "tanks", "mt" }, healer = { "heal", "healer", "heals", "healz", "healers" }, dps = { "dps", "dd", "damage" } }

-- "lfm" (a group looking for more), "lfg" (a player looking for a group), or nil. The most
-- explicit wins: "LFM"/"LF2M" is a group and "LFG" a player, whatever else the message says
-- ("LFG need group for DM" is a player); then "LF tank" and "need" mean a group, and a bare "LF"
-- a player.
local function FindIntent(t)
    for _, w in ipairs({ "wts", "wtb", "selling", "buying", "wtt" }) do
        if Has(t, w) then return nil end -- trading, not grouping
    end
    if Has(t, "lfm") or t:find(" lf%dm ") then return "lfm" end
    if Has(t, "lfg") or t:find(" looking for group ", 1, true) or t:find(" lf group ", 1, true)
        or t:find(" lf grp ", 1, true) or t:find(" need group ", 1, true) or t:find(" need grp ", 1, true) then
        return "lfg"
    end
    -- "LF tank", "LF MC tank": a role asked for is a group's need, unless it's offered
    -- ("LF DM as tank", "LF DM, I'm a healer").
    if Has(t, "lf") or t:find(" lf%d ") then
        for _, words in pairs(ROLE_WORDS) do
            for _, w in ipairs(words) do
                if Has(t, w) then
                    if t:find(" as a? ?" .. w .. " ") or t:find(" i'?m a? ?" .. w .. " ") then return "lfg" end
                    return "lfm"
                end
            end
        end
    end
    if t:find(" lf %d ") or Has(t, "need") then return "lfm" end
    if Has(t, "lf") then return "lfg" end
    return nil
end

local function FindRoles(t)
    local roles, any = { tank = false, healer = false, dps = false }, false
    for role, words in pairs(ROLE_WORDS) do
        for _, w in ipairs(words) do
            if Has(t, w) then roles[role] = true any = true break end
        end
    end
    return roles, any
end

-- "lf2m" or "lf 2": how many they still need.
local function FindNeedCount(t)
    local n = t:match(" lf(%d)m ") or t:match(" lf (%d) ")
    return n and tonumber(n)
end

---------------------------------------------------------------------------
-- Posts
---------------------------------------------------------------------------
local function IsMe(name)
    local me = UnitName("player")
    return me and ns.LocationKey(name) == ns.LocationKey(me)
end

local function InMyGroup(name)
    for _, unit in ipairs(ns.MyGroupUnits()) do
        if ns.LocationKey(UnitName(unit)) == ns.LocationKey(name) then return true end
    end
    return false
end

-- Expired posts go, about once a minute (with the window closed nothing else clears them).
local lastPrune = 0
local function PruneExpired()
    local now = GetTime()
    if now - lastPrune < 60 then return end
    lastPrune = now
    for key, post in pairs(posts) do
        if now - post.time > POST_TTL then posts[key] = nil end
    end
end

local function OnChannelMessage(text, sender, channelBaseName, guid)
    PruneExpired()
    local cfg = ns.db and ns.db.chat
    if not (cfg and cfg.enabled) or type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
    if cfg.lfgChannelOnly and not (channelBaseName or ""):lower():find("lookingforgroup", 1, true) then return end
    if IsMe(sender) or InMyGroup(sender) then return end
    local t = Normalize(text)
    local kind = FindIntent(t)
    if not kind then return end
    local ids = FindActivities(t)
    if not ids then return end
    local roles, anyRole = FindRoles(t)

    local key = ns.LocationKey(sender)
    local old = posts[key]
    local classFile
    if guid and GetPlayerInfoByGUID then
        local ok, _, cls = pcall(GetPlayerInfoByGUID, guid)
        if ok then classFile = cls end
    end
    posts[key] = {
        id = old and old.id or nextID,
        name = sender, classFile = classFile or (old and old.classFile),
        text = text, channel = channelBaseName, time = GetTime(),
        kind = kind, ids = ids, roles = roles, anyRole = anyRole, needCount = FindNeedCount(t),
    }
    if not old then nextID = nextID - 1 end
    -- Where they are and their level are found when you ask (the map button on their card).
    if ns.QueueRender then ns.QueueRender() end
    if not old and cfg.alerts then C_Timer.After(0.3, function() ns.AlertChatPost(key) end) end
end

-- A post as a card, like the group finder's (rebuilt on every redraw, so a level or zone found by
-- a lookup, from its card's map button, shows).
local function BuildEntry(post)
    local known = ns.GetKnownPlayer and ns.GetKnownPlayer(post.name)
    local zone = ns.GetKnownLocation(post.name)
    local isSolo = post.kind == "lfg"
    local maxPlayers = 0
    for _, id in ipairs(post.ids) do
        local a = ns.GetActivity(id)
        if a and a.maxNumPlayers and a.maxNumPlayers > maxPlayers then maxPlayers = a.maxNumPlayers end
    end
    if maxPlayers == 0 then maxPlayers = 5 end
    local level = known and known.level
    local p = {
        name = post.name, level = level, classFilename = post.classFile or (known and known.classFile),
        areaName = zone or "", isLeader = true, assignedRole = "NONE",
        lfgRoles = isSolo and post.roles or nil,
    }
    local members = isSolo and 1 or (post.needCount and math.max(1, maxPlayers - post.needCount) or 1)
    return {
        id = post.id,
        fromChat = true,
        chat = post,
        info = { name = "", comment = post.text },
        members = { p },
        leader = p,
        leaderName = post.name,
        activityIDs = post.ids,
        age = GetTime() - post.time,
        isSelf = false,
        isSolo = isSolo,
        numMembers = members,
        maxPlayers = maxPlayers,
        tanks = 0, healers = 0, dps = 0,
        roles = isSolo and post.roles or nil,
        -- What a group says it needs; none named means it could be anything.
        chatNeeds = (not isSolo and post.anyRole) and post.roles or nil,
        maxLevel = level, minLevel = level,
        friends = 0, guildmates = 0,
        displayType = Enum and Enum.LFGListDisplayType and Enum.LFGListDisplayType.Comment,
    }
end

-- Cards for the posts that fit what you're browsing: your listing's activities, or the category
-- you've picked (the activity picks and every other filter apply as to the game's listings).
-- skip: poster keys already shown by a group finder listing (that one wins).
function ns.ChatEntries(skip)
    local groups, players = {}, {}
    local cfg = ns.db and ns.db.chat
    if not (cfg and cfg.enabled) then return groups, players end
    local scope = {}
    if ns.db.searchSelf and ns.HasListing() then
        for _, id in ipairs(ns.GetListing().activityIDs or {}) do scope[id] = true end
    end
    local now = GetTime()
    for key, post in pairs(posts) do
        if now - post.time > POST_TTL then
            posts[key] = nil
        elseif not (skip and skip[key]) then
            local fits = false
            for _, id in ipairs(post.ids) do
                if next(scope) then
                    if scope[id] then fits = true end
                else
                    local a = ns.GetActivity(id)
                    if a and a.categoryID == ns.db.categoryID then fits = true end
                end
            end
            if fits then
                local e = BuildEntry(post)
                if e.isSolo then players[#players + 1] = e else groups[#groups + 1] = e end
            end
        end
    end
    return groups, players
end

-- A new chat post that passes your filters, in chat (when that alert is on).
function ns.AlertChatPost(key)
    local post = posts[key]
    if not post then return end
    local ok, groups, players = pcall(ns.GetFiltered)
    if not ok then return end
    for _, list in ipairs({ groups, players }) do
        for _, e in ipairs(list) do
            if e.id == post.id then
                local what = post.kind == "lfm" and L["group"] or L["player"]
                ns.Print((L["From chat: %s (%s, %s): %s"]):format(ns.ShortName and ns.ShortName(post.name) or post.name,
                    what, ns.GetActivityName(post.ids[1]), post.text))
                return
            end
        end
    end
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("CHAT_MSG_CHANNEL")
    ev:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
    ev:RegisterEvent("PLAYER_LEVEL_UP")
    ev:SetScript("OnEvent", function(_, event, text, sender, _, _, _, _, _, _, channelBaseName, _, _, guid)
        if event == "CHAT_MSG_CHANNEL" then
            local ok, err = pcall(OnChannelMessage, text, sender, channelBaseName, guid)
            if not ok and ns.debugChat then ns.Print("chat: " .. tostring(err)) end
        else
            index = nil -- what's available changed: rebuild the names on the next message
        end
    end)
end

-- For testing without waiting for chat: /seeker chattest <message> reads it as if posted.
function ns.TestChatMessage(text)
    local t = Normalize(text)
    local kind, ids = FindIntent(t), FindActivities(t)
    local roles = FindRoles(t)
    local names = {}
    for _, id in ipairs(ids or {}) do names[#names + 1] = ns.GetActivityName(id) end
    local r = {}
    for k, v in pairs(roles) do if v then r[#r + 1] = k end end
    ns.Print(("%s -> %s | %s | %s | need %s"):format(text, tostring(kind), #names > 0 and table.concat(names, ", ") or "-",
        #r > 0 and table.concat(r, "/") or "-", tostring(FindNeedCount(t) or "-")))
end
