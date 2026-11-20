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
    tip:AddLine("Groups and players side by side, filtered so you keep your XP.", 0.8, 0.8, 0.8, true)
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

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\LFGFrame\\UI-LFG-PORTRAIT")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER")
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)

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

    button = b
    UpdatePosition()
    ns.UpdateMinimapButton()
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
