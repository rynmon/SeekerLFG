-- Seeker: minimap button (same build as OneCast's, so the two sit together naturally).
local ADDON, ns = ...

local button

-- Round unless a minimap addon says otherwise (the GetMinimapShape convention).
local function MinimapIsRound()
    return not GetMinimapShape or GetMinimapShape() == "ROUND"
end

local function UpdatePosition()
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

function ns.UpdateMinimapButton()
    if button then button:SetShown(ns.db.minimapButton ~= false) end
end

function ns.SetMinimapButton(show)
    ns.db.minimapButton = show and true or false
    ns.UpdateMinimapButton()
    ns.Print(show and "Minimap button shown." or "Minimap button hidden. /seeker minimap brings it back.")
end

-- Shared by the minimap button and the addon compartment.
function ns.FillTooltip(tip, isMinimap)
    tip:SetText("Seeker LFG", 1, 1, 1)
    -- Listed: what for (as the game's minimap eye tooltip shows). Otherwise, what Seeker is.
    local entry = ns.HasListing() and ns.GetListing()
    if entry and entry.activityIDs and #entry.activityIDs > 0 then
        tip:AddLine((LFG_LIST_MY_ACTIVITY_LIST_HEADER or "You're listed for:"), 0.1, 1, 0.1)
        for i, id in ipairs(entry.activityIDs) do
            if i > 8 then
                tip:AddLine(("    and %d more"):format(#entry.activityIDs - 8), 0.8, 0.8, 0.8)
                break
            end
            tip:AddLine("    " .. ns.GetActivityName(id), 1, 1, 1)
        end
    else
        tip:AddLine("Groups and players side by side, filtered so you keep your XP.", 0.8, 0.8, 0.8, true)
    end
    tip:AddLine(" ")
    tip:AddLine("|cffffd100Click|r to open or close", 1, 1, 1)
    if isMinimap then
        tip:AddLine("|cffffd100Right-click|r for options", 1, 1, 1)
        tip:AddLine("|cffffd100Drag|r to move", 1, 1, 1)
    end
end

local function ShowMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Toggle()
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Seeker LFG")
        root:CreateButton("Open Seeker", function() ns.Toggle() end)
        root:CreateButton("Reset window position and size", function() SlashCmdList.SEEKERLFG("reset") end)
        root:CreateButton("Hide minimap button", function() ns.SetMinimapButton(false) end)
    end)
end

function ns.SetupMinimapButton()
    if button or not Minimap then return end
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

    -- The game's own minimap LFG eye (LFGEyeTemplate, as its group finder's minimap button uses):
    -- still, then watching while you're listed. Falls back to its still art, then the portrait.
    local eye = ns.UI and ns.UI.TryCreate("Frame", nil, b, "LFGEyeTemplate")
    if eye and eye.SetStaticMode then
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
    else
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("CENTER")
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("groupfinder-eye-single") then
            icon:SetAtlas("groupfinder-eye-single")
        else
            icon:SetTexture("Interface\\LFGFrame\\UI-LFG-PORTRAIT")
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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

    b:SetScript("OnClick", function(self, mouseButton)
        GameTooltip:Hide()
        if mouseButton == "RightButton" then
            if ns.ShowOptionsMenu and MenuUtil then ns.ShowOptionsMenu(self) else ShowMenu(self) end
        else
            ns.Toggle()
        end
    end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
            UpdatePosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        ns.FillTooltip(GameTooltip, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    -- Watching while you're listed, as the game's minimap eye does.
    b:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    b:RegisterEvent("PLAYER_ENTERING_WORLD")
    b:SetScript("OnEvent", function() ns.UpdateMinimapEye() end)

    button = b
    UpdatePosition()
    ns.UpdateMinimapButton()
    ns.UpdateMinimapEye()
end

function ns.UpdateMinimapEye()
    local eye = button and button.eye
    if not eye then return end
    local listed = ns.HasListing()
    if button.eyeListed == listed then return end
    button.eyeListed = listed
    pcall(eye.SetStaticMode, eye, not listed)
    if listed then
        pcall(eye.StartInitialAnimation, eye)
    else
        pcall(eye.StopAnimating, eye)
    end
end

-- Addon compartment (the minimap's addon list) hover
function SeekerLFG_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton or UIParent, "ANCHOR_LEFT")
    ns.FillTooltip(GameTooltip, false)
    GameTooltip:Show()
end

function SeekerLFG_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
