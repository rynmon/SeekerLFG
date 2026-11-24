-- Seeker: the minimap button and the broker launcher.
--
-- Seeker is a LibDataBroker launcher, so it shows in broker bars (Titan Panel, ChocolateBar,
-- Bazooka...), and its minimap button is a LibDBIcon one, which minimap button collectors (that
-- gather every addon's button into one bar) pick up. On the button sits the game's own LFG eye,
-- still, then watching while you're listed, as the game's minimap eye does. If the libraries
-- aren't there for some reason, Seeker makes its own button as before.
local ADDON, ns = ...
local L = ns.L -- translations (Locale.lua)

local LDB_NAME = "SeekerLFG" -- the broker object's name, and LibDBIcon's (its button is LibDBIcon10_SeekerLFG)
local ICON = "Interface\\LFGFrame\\UI-LFG-PORTRAIT"
local ICON_COORDS = { 0.08, 0.92, 0.08, 0.92 }

local button      -- the minimap button, LibDBIcon's or Seeker's own
local dataObject  -- the broker launcher
local dbIcon      -- LibDBIcon, when it's loaded

local function GetLib(name)
    return LibStub and LibStub(name, true)
end

---------------------------------------------------------------------------
-- Showing and hiding
---------------------------------------------------------------------------
function ns.UpdateMinimapButton()
    local show = ns.db.minimapButton ~= false
    if dbIcon then
        ns.db.minimap.hide = not show
        if show then dbIcon:Show(LDB_NAME) else dbIcon:Hide(LDB_NAME) end
    elseif button then
        button:SetShown(show)
    end
end

function ns.SetMinimapButton(show)
    ns.db.minimapButton = show and true or false
    ns.UpdateMinimapButton()
    ns.Print(show and L["Minimap button shown."] or L["Minimap button hidden. /seeker minimap brings it back."])
end

---------------------------------------------------------------------------
-- Tooltip (the minimap button, broker displays and the addon compartment)
---------------------------------------------------------------------------
function ns.FillTooltip(tip, isMinimap)
    tip:SetText("Seeker LFG", 1, 1, 1)
    -- Listed: what for (as the game's minimap eye tooltip shows). Otherwise, what Seeker is.
    local entry = ns.HasListing() and ns.GetListing()
    if entry and entry.activityIDs and #entry.activityIDs > 0 then
        -- As the game's minimap eye: grouped by activity group (a group is one line past 20
        -- activities), then your description.
        tip:AddLine((LFG_LIST_MY_ACTIVITY_LIST_HEADER or L["You're listed for:"]), 0.1, 1, 0.1)
        if ns.AddActivityLines then
            ns.AddActivityLines(tip, entry.activityIDs, nil, false, true, 20)
        else
            for _, id in ipairs(entry.activityIDs) do tip:AddLine("    " .. ns.GetActivityName(id), 1, 1, 1) end
        end
        if type(entry.comment) == "string" and entry.comment ~= "" then
            local ok, text = pcall(string.format, LFG_LIST_COMMENT_FORMAT or "\"%s\"", entry.comment)
            tip:AddLine(ok and text or entry.comment, 0.5, 0.5, 0.5, true)
        end
    else
        tip:AddLine(L["Groups and players side by side, filtered so you keep your XP."], 0.8, 0.8, 0.8, true)
    end
    -- Can't use the group finder (too low a level, for example): say why.
    local canUse, reason = ns.CanUseGroupFinder()
    if not canUse then tip:AddLine(reason, 1, 0.3, 0.3, true) end
    tip:AddLine(" ")
    tip:AddLine(L["|cffffd100Click|r to open or close"], 1, 1, 1)
    if isMinimap then
        tip:AddLine(L["|cffffd100Right-click|r for options"], 1, 1, 1)
        tip:AddLine(L["|cffffd100Drag|r to move"], 1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------
local function ShowMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Toggle()
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Seeker LFG")
        root:CreateButton(L["Open Seeker"], function() ns.Toggle() end)
        root:CreateButton(L["Reset window position and size"], function() SlashCmdList.SEEKERLFG("reset") end)
        root:CreateButton(L["Hide minimap button"], function() ns.SetMinimapButton(false) end)
    end)
end

-- Left: open or close. Right: the options menu. The same from the minimap and broker displays.
local function OnClick(owner, mouseButton)
    GameTooltip:Hide()
    if mouseButton == "RightButton" then
        if ns.ShowOptionsMenu and MenuUtil then ns.ShowOptionsMenu(owner) else ShowMenu(owner) end
    else
        ns.Toggle()
    end
end

---------------------------------------------------------------------------
-- The game's LFG eye, on the button
---------------------------------------------------------------------------
-- The game's own minimap LFG eye (LFGEyeTemplate, as its group finder's minimap button uses).
-- Returns true if it's there; the button's own icon is then hidden under it.
local function AddEye(b)
    local eye = ns.UI and ns.UI.TryCreate("Frame", nil, b, "LFGEyeTemplate")
    if not (eye and eye.SetStaticMode) then return false end
    -- The template is built for a 45px eye and its glows use their art's own size, so a smaller
    -- frame doesn't shrink them: scale the whole eye down to the minimap button's 20px icon.
    eye:SetSize(45, 45)
    eye:SetScale(20 / 45)
    eye:SetPoint("CENTER", 0, 0)
    -- The template has its own mouse scripts, which made the eye catch clicks meant for the
    -- button underneath. It's only a picture here: let every click and hover through.
    eye:EnableMouse(false)
    if eye.SetMouseClickEnabled then eye:SetMouseClickEnabled(false) end
    if eye.SetMouseMotionEnabled then eye:SetMouseMotionEnabled(false) end
    for _, child in ipairs({ eye:GetChildren() }) do
        if child.EnableMouse then child:EnableMouse(false) end
    end
    eye:SetFrameLevel(b:GetFrameLevel() + 1)
    eye:SetStaticMode(true)
    eye:Show()
    b.eye = eye
    return true
end

---------------------------------------------------------------------------
-- The broker launcher and LibDBIcon button
---------------------------------------------------------------------------
local function SetupBroker(ldb, icon)
    -- LibDBIcon keeps its position and shown state in ns.db.minimap. Carried over once from
    -- Seeker's own button (its angle is measured the same way); shown or hidden follows
    -- ns.db.minimapButton, which the options and /seeker minimap set.
    local db = ns.db.minimap
    if db.minimapPos == nil then db.minimapPos = ns.db.minimapAngle or 200 end
    db.hide = ns.db.minimapButton == false
    db.showInCompartment = nil -- the TOC already lists Seeker in the addon compartment

    dataObject = ldb:NewDataObject(LDB_NAME, {
        type = "launcher",
        label = "Seeker LFG",
        text = "Seeker LFG",
        icon = ICON,
        iconCoords = ICON_COORDS,
        OnClick = OnClick,
        OnTooltipShow = function(tip) ns.FillTooltip(tip, true) end,
    })
    if not dataObject then return false end -- another copy already made it
    icon:Register(LDB_NAME, dataObject, db)
    dbIcon = icon
    button = icon:GetMinimapButton(LDB_NAME)
    if button and AddEye(button) and button.icon then button.icon:SetAlpha(0) end
    return true
end

---------------------------------------------------------------------------
-- Seeker's own button (only when the libraries aren't loaded)
---------------------------------------------------------------------------
local function MinimapIsRound()
    return not GetMinimapShape or GetMinimapShape() == "ROUND"
end

local function UpdateOwnPosition()
    local angle = math.rad(ns.db.minimapAngle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    if MinimapIsRound() then
        x, y = x * (halfW + 5), y * (halfH + 5)
    else
        local edge = math.max(math.abs(x), math.abs(y))
        x, y = x / edge * (halfW + 10), y / edge * (halfH + 10)
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function SetupOwnButton()
    local b = CreateFrame("Button", "SeekerLFGMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("CENTER")

    if not AddEye(b) then
        -- No eye template: its still art, else the portrait, masked round.
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("CENTER")
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("groupfinder-eye-single") then
            icon:SetAtlas("groupfinder-eye-single")
        else
            icon:SetTexture(ICON)
            icon:SetTexCoord(unpack(ICON_COORDS))
            local mask = b:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(icon)
            icon:AddMaskTexture(mask)
        end
    end

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", OnClick)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
            UpdateOwnPosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        ns.FillTooltip(GameTooltip, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    button = b
    UpdateOwnPosition()
end

---------------------------------------------------------------------------
-- Setup (at login) and the eye's state
---------------------------------------------------------------------------
function ns.SetupMinimapButton()
    if button or not Minimap then return end
    local ldb, icon = GetLib("LibDataBroker-1.1"), GetLib("LibDBIcon-1.0")
    if not (ldb and icon and SetupBroker(ldb, icon)) then SetupOwnButton() end

    -- Watching while you're listed, as the game's minimap eye does.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() ns.UpdateMinimapEye() end)

    ns.UpdateMinimapButton()
    ns.UpdateMinimapEye()
end

function ns.UpdateMinimapEye()
    local listed = ns.HasListing()
    -- Broker displays show whether you're listed.
    if dataObject then dataObject.text = listed and L["Listed"] or "Seeker LFG" end
    local eye = button and button.eye
    if not eye or button.eyeListed == listed then return end
    button.eyeListed = listed
    pcall(eye.SetStaticMode, eye, not listed)
    if listed then
        pcall(eye.StartInitialAnimation, eye)
    else
        pcall(eye.StopAnimating, eye)
    end
end

---------------------------------------------------------------------------
-- Addon compartment (the minimap's addon list) hover
---------------------------------------------------------------------------
function SeekerLFG_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton or UIParent, "ANCHOR_LEFT")
    ns.FillTooltip(GameTooltip, false)
    GameTooltip:Show()
end

function SeekerLFG_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
