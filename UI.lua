-- Seeker: two-pane LFG window. Built from the game's own templates and atlases so it
-- wears Forever's bronze skin (as OneCast does): a filter panel on top, then groups and
-- players side by side as two-line cards with party slots, level and actions.
local ADDON, ns = ...

local floor, max, min = math.floor, math.max, math.min
local WHITE = "Interface\\Buttons\\WHITE8X8"

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
-- The game's group finder is 458 x 535. Seeker keeps its height and is only as wide as
-- two panes side by side need.
local FRAME_W, FRAME_H = 920, 535
local TOPBAR_Y = -30
local FILTER_TOP, FILTER_H = 62, 106       -- the filter panel, when it's open
local LISTS_TOP_OPEN = FILTER_TOP + FILTER_H + 4
local LISTS_TOP_CLOSED = FILTER_TOP
local LISTS_BOTTOM = 26
local EDGE, GAP = 5, 8
local HEADER_H, ROW_H = 36, 66   -- the game's category bar, and its three-line search entries
local SCROLL_W = 6
local SLOT = 22
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2, 0.05

-- Text sizes: deliberately larger than the game's small fonts.
local SIZE_NAME, SIZE_SUB, SIZE_LEVEL, SIZE_HEAD, SIZE_LABEL = 15, 12, 17, 14, 13

local XP_COLORS = {
    safe    = { 0.35, 1.00, 0.35 },
    partial = { 1.00, 0.82, 0.20 },
    none    = { 1.00, 0.30, 0.30 },
    unknown = { 0.60, 0.60, 0.60 },
}
local XP_LABELS = { safe = "Full XP", partial = "Partial XP", none = "No XP", unknown = "Unknown" }

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local ROLE_KEYS = { "tank", "healer", "dps" }
local ROLE_NAMES = { tank = "Tank", healer = "Healer", dps = "DPS" }
-- The game's own role icons, in order of preference: the Group Finder's role icons, then the
-- classic LFG role sheet (UI-LFG-ICON-ROLES), then the tiny ones.
local ROLE_LARGE = {
    tank = "groupfinder-icon-role-large-tank",
    healer = "groupfinder-icon-role-large-heal",
    dps = "groupfinder-icon-role-large-dps",
}
local ROLE_TINY = { tank = "roleicon-tiny-tank", healer = "roleicon-tiny-healer", dps = "roleicon-tiny-dps" }
local ROLE_SHEET = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local ROLE_GAME = { tank = "TANK", healer = "HEALER", dps = "DAMAGER" }
local ROLE_FROM_ASSIGNED = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

---------------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------------
local function TryCreate(frameType, name, parent, template)
    local ok, f = pcall(CreateFrame, frameType, name, parent, template)
    if ok then return f end
end

local function HasAtlas(atlas)
    return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- The game's own font objects at their own sizes, as its group finder uses them (so text also
-- follows the game's text size setting where the game's does). Size arguments are ignored;
-- the window's scale grip is how to make everything bigger.
local function Font(fs, object)
    fs:SetFontObject(_G[object] or GameFontNormal)
end

local function Text(parent, object, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", object)
    Font(fs, object, size)
    return fs
end

local function ClassColor(classFile)
    local c
    if C_ClassColor and C_ClassColor.GetClassColor and classFile then c = C_ClassColor.GetClassColor(classFile) end
    c = c or (RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile])
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(floor(r * 255), floor(g * 255), floor(b * 255))
end

local function FormatAge(sec)
    sec = sec or 0
    if sec < 60 then return floor(sec) .. "s" end
    if sec < 3600 then return floor(sec / 60) .. "m" end
    return floor(sec / 3600) .. "h"
end

-- Character names without the realm when it's yours, as the game shows them.
local function ShortName(name)
    if not name then return nil end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and short then return short end
    end
    return name
end
ns.ShortName = ShortName

local function RoleAtlas(key)
    if HasAtlas(ROLE_LARGE[key]) then return ROLE_LARGE[key] end
end

local function RoleSheetCoords(key)
    if GetTexCoordsForRole then
        local ok, l, r, t, b = pcall(GetTexCoordsForRole, ROLE_GAME[key])
        if ok and l then return l, r, t, b end
    end
end

-- Puts a role's native icon on a texture. Returns false if the game has none.
local function ApplyRole(tex, key)
    tex:SetTexCoord(0, 1, 0, 1)
    local atlas = RoleAtlas(key)
    if atlas then tex:SetAtlas(atlas) return true end
    local l, r, t, b = RoleSheetCoords(key)
    if l then
        tex:SetTexture(ROLE_SHEET)
        tex:SetTexCoord(l, r, t, b)
        return true
    end
    if HasAtlas(ROLE_TINY[key]) then tex:SetAtlas(ROLE_TINY[key]) return true end
    return false
end

-- Inline role icon for tooltips.
local function RoleMarkup(key, size)
    size = size or 16
    local atlas = RoleAtlas(key)
    if atlas then return ("|A:%s:%d:%d|a"):format(atlas, size, size) end
    local l, r, t, b = RoleSheetCoords(key)
    if l then
        return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t"):format(ROLE_SHEET, size, size,
            floor(l * 256), floor(r * 256), floor(t * 256), floor(b * 256))
    end
    if HasAtlas(ROLE_TINY[key]) then return ("|A:%s:%d:%d|a"):format(ROLE_TINY[key], size, size) end
    return ({ tank = "|cff5599ffT|r", healer = "|cff55ff55H|r", dps = "|cffff5555D|r" })[key]
end

local function SetClassIcon(tex, classFile)
    local atlas = "classicon-" .. classFile:lower()
    if HasAtlas(atlas) then
        tex:SetAtlas(atlas)
    elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[classFile]))
    else
        tex:SetColorTexture(ClassColor(classFile))
    end
end

local function ClassName(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile:sub(1, 1) .. classFile:sub(2):lower()
end

local function Tooltip(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- Native pieces
---------------------------------------------------------------------------
local function SetTitle(f, text)
    if f.SetTitle then
        f:SetTitle(text)
    elseif f.TitleContainer and f.TitleContainer.TitleText then
        f.TitleContainer.TitleText:SetText(text)
    elseif f.TitleText then
        f.TitleText:SetText(text)
    end
end

local function CreateShell(name, titleText, portraitPath)
    local f = TryCreate("Frame", name, UIParent, "ButtonFrameTemplate")
    if f then
        f.onCloseCallback = function() f:Hide() return false end -- no panel manager: works in combat
        SetTitle(f, titleText)
        local portrait = (f.PortraitContainer and f.PortraitContainer.portrait) or f.portrait
        if portrait then
            portrait:SetTexture(portraitPath)
            portrait:SetTexCoord(0, 1, 0, 1)
        end
        if f.Inset then f.Inset:Hide() end -- we place our own insets
        return f
    end
    f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    local title = Text(f, "GameFontNormal", SIZE_HEAD)
    title:SetPoint("TOP", 0, -12)
    title:SetText(titleText)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    return f
end

local function Inset(parent)
    local i = TryCreate("Frame", nil, parent, "InsetFrameTemplate")
    if not i then
        i = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        i:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        i:SetBackdropColor(0, 0, 0, 0.4)
        i:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)
    end
    return i
end

-- The group finder's own category bar ("Groups", "Solo players"): common-button-list-collapseExpand,
-- inset as its LFGBrowseSearchEntryGroupingTemplate insets it. Text sits 4px low, as there.
local function HeaderBar(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(HEADER_H)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    if HasAtlas("common-button-list-collapseExpand") then
        bg:SetAtlas("common-button-list-collapseExpand")
        bg:SetPoint("TOPLEFT", 3, -8)
        bg:SetPoint("BOTTOMRIGHT", -3, 0)
    else
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.1, 0.08, 0.9)
    end
    h.bg = bg
    return h
end

local function RedButton(parent, text, w, h, small)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    if small then
        -- The game's small button text, for buttons inside list rows.
        b:SetNormalFontObject(GameFontNormalSmall)
        b:SetHighlightFontObject(GameFontHighlightSmall)
        b:SetDisabledFontObject(GameFontDisableSmall)
    end
    b:SetText(text)
    return b
end

local function Check(parent, label, getter, setter, tipTitle, tipBody)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    local fs = c.Text or c.text
    if not fs then
        fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", c, "RIGHT", 0, 1)
    end
    Font(fs, "GameFontHighlight", SIZE_LABEL)
    fs:SetText(label)
    c:SetHitRectInsets(0, -fs:GetStringWidth() - 4, 0, 0)
    c:SetChecked(getter())
    c:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        setter(self:GetChecked() and true or false)
    end)
    if tipTitle then Tooltip(c, tipTitle, tipBody) end
    return c
end

local function NumberBox(parent, getter, setter)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(34, 24)
    Font(eb, "ChatFontNormal", SIZE_LABEL)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(2)
    eb:SetJustifyH("CENTER")
    local v = getter()
    eb:SetText(v and tostring(v) or "")
    eb:SetScript("OnTextChanged", function(self, user)
        if user then setter(tonumber(self:GetText())) end
    end)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

local function Dropdown(parent, width, build, getText)
    local dd = TryCreate("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if dd and dd.SetupMenu then
        dd:SetWidth(width)
        dd:SetupMenu(function(_, root) build(root) end)
        dd.Refresh = function(self) self:GenerateMenu() end
        return dd
    end
    local b = RedButton(parent, getText(), width)
    b:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root) build(root) end)
        end
    end)
    b.Refresh = function(self) self:SetText(getText()) end
    return b
end

local function Radio(root, text, isSelected, onSelect)
    root:CreateRadio(text, isSelected, function()
        onSelect()
        return MenuResponse and MenuResponse.Close
    end)
end

---------------------------------------------------------------------------
-- Seeker's own pieces
---------------------------------------------------------------------------
local toggles = {}
local function UpdateToggles()
    for _, t in ipairs(toggles) do t:UpdateLook() end
end

-- A chip that's on or off: dark with a bronze edge when off, gold-lit when on.
local function Chip(parent, w, h, label, atlas, isOn, onClick, tipTitle, tipBody)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local hl = b:GetHighlightTexture()
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)

    if atlas then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(h - 10, h - 10)
        if label then
            b.icon:SetPoint("LEFT", 8, 0)
        else
            b.icon:SetPoint("CENTER")
        end
        if type(atlas) == "function" then atlas(b.icon) elseif HasAtlas(atlas) then b.icon:SetAtlas(atlas) end
    end
    if label then
        b.text = Text(b, "GameFontHighlight", SIZE_LABEL)
        if b.icon then
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        else
            b.text:SetPoint("CENTER")
        end
        b.text:SetText(label)
    end

    function b:UpdateLook()
        local on = isOn()
        if on then
            self:SetBackdropColor(0.42, 0.28, 0.04, 0.9)
            self:SetBackdropBorderColor(1, 0.82, 0, 1)
            if self.text then self.text:SetTextColor(1, 1, 1) end
            if self.icon then self.icon:SetDesaturated(false); self.icon:SetAlpha(1) end
        else
            self:SetBackdropColor(0.03, 0.03, 0.03, 0.75)
            self:SetBackdropBorderColor(0.5, 0.42, 0.3, 1)
            if self.text then self.text:SetTextColor(0.72, 0.72, 0.72) end
            if self.icon then self.icon:SetDesaturated(not label); self.icon:SetAlpha(label and 1 or 0.55) end
        end
    end
    b:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onClick()
        UpdateToggles()
        ns.Render()
    end)
    if tipTitle then Tooltip(b, tipTitle, tipBody) end
    toggles[#toggles + 1] = b
    b:UpdateLook()
    return b
end

-- A party slot: the game's own role icon, or its empty-seat icon.
local function Slot(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(SLOT, SLOT)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    return s
end

local function SetSlot(s, role, empty)
    s:Show()
    s.icon:SetVertexColor(1, 1, 1, 1)
    s.icon:SetDesaturated(false)
    s.icon:SetTexCoord(0, 1, 0, 1)
    if role and ApplyRole(s.icon, role) then return end
    -- An open seat, or a member whose role we weren't told (shown dimmed, not as open).
    if HasAtlas("groupfinder-icon-emptyslot") then
        s.icon:SetAtlas("groupfinder-icon-emptyslot")
    else
        s.icon:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        s.icon:SetVertexColor(0.2, 0.2, 0.2, 0.8)
    end
    if not empty then
        s.icon:SetVertexColor(0.8, 0.8, 0.8, 1)
    end
end

-- A small icon button (whisper bubble).
local function IconButton(parent, texture, size, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture(texture, "ADD")
    b:GetHighlightTexture():SetAlpha(0.5)
    b:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onClick(self)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

---------------------------------------------------------------------------
-- List pane
---------------------------------------------------------------------------
-- spec = { title, columns = { {label, x, width, justify} }, buildRow(row), populate(row, e) }
local function CreatePane(parent, spec)
    local f = CreateFrame("Frame", nil, parent)
    f.offset = 0

    f.header = HeaderBar(f)
    f.header:SetPoint("TOPLEFT")
    f.header:SetPoint("TOPRIGHT")
    f.title = Text(f.header, "GameFontNormal")
    f.title:SetPoint("LEFT", 12, -4)

    local top = HEADER_H + 2
    f.rows = {}

    local sb = CreateFrame("Slider", nil, f)
    sb:SetOrientation("VERTICAL")
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 2)
    sb:SetWidth(SCROLL_W)
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.35)
    local thumb = sb:CreateTexture(nil, "OVERLAY")
    if HasAtlas("minimal-scrollbar-small-thumb-middle") then
        thumb:SetAtlas("minimal-scrollbar-small-thumb-middle")
    else
        thumb:SetColorTexture(1, 0.82, 0, 0.6)
    end
    thumb:SetSize(SCROLL_W, 40)
    sb:SetThumbTexture(thumb)
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    sb:SetScript("OnValueChanged", function(_, v)
        v = floor(v + 0.5)
        if v ~= f.offset then f.offset = v; f:Refresh() end
    end)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() then
            ns.StepScale(delta)
        else
            sb:SetValue(f.offset - delta * 2)
        end
    end)

    f.empty = Text(f, "GameFontDisable", SIZE_NAME)
    f.empty:SetPoint("TOP", 0, -top - 40)
    f.empty:SetWidth(380)
    f.empty:SetText(spec.emptyText)

    local function MakeRow(i)
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(SCROLL_W + 4), -top - (i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        -- The game's search entry card (common-button-list-mid2) and its hover, inset as there.
        local card = row:CreateTexture(nil, "BACKGROUND")
        card:SetPoint("TOPLEFT", 3, -2)
        card:SetPoint("BOTTOMRIGHT", -3, 0)
        if HasAtlas("common-button-list-mid2") then
            card:SetAtlas("common-button-list-mid2")
        else
            card:SetColorTexture(1, 1, 1, 0.05)
        end
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetPoint("TOPLEFT", 3, -3)
        hover:SetPoint("BOTTOMRIGHT", -3, -1)
        if HasAtlas("common-button-list-mid2-hover") then
            hover:SetAtlas("common-button-list-mid2-hover")
        else
            hover:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        end
        hover:SetBlendMode("ADD")

        -- XP stripe down the card's left edge
        row.xpBar = row:CreateTexture(nil, "ARTWORK")
        row.xpBar:SetPoint("TOPLEFT", 5, -8)
        row.xpBar:SetPoint("BOTTOMLEFT", 5, 6)
        row.xpBar:SetWidth(2)

        -- Leader crown (groups) or class icon (players) before the name, as the game's entries.
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", 10, -11)
        row.icon:SetSize(16, 16)

        -- The game's entry fonts: name (GameFontNormalLarge) over the activity (GameFontDisableLeft).
        row.name = Text(row, "GameFontNormalLarge")
        row.name:SetPoint("TOPLEFT", 28, -11)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.sub = Text(row, "GameFontDisableLeft")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)

        row.level = Text(row, "GameFontNormalLarge")
        row.level:SetJustifyH("CENTER")

        spec.buildRow(row)

        row:SetScript("OnEnter", function(self) if self.item then ns.ShowEntryTooltip(self, self.item) end end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self, button)
            if self.item and button == "RightButton" then ns.EntryMenu(self, self.item) end
        end)
        return row
    end

    function f:Layout()
        local n = max(1, floor((self:GetHeight() - top - 2) / ROW_H))
        for i = #self.rows + 1, n do self.rows[i] = MakeRow(i) end
        self.numRows = n
        for i = n + 1, #self.rows do self.rows[i]:Hide() end
    end
    f:SetScript("OnSizeChanged", function(self) self:Layout(); self:Refresh() end)

    function f:SetData(data, total)
        self.data = data
        self.title:SetText(("%s  |cffb0b0b0(%d of %d)|r"):format(spec.title, #data, total or #data))
        self:Refresh()
    end

    function f:Refresh()
        if not self.numRows then self:Layout() end
        local data = self.data or {}
        local n = self.numRows
        local maxOff = max(0, #data - n)
        if self.offset > maxOff then self.offset = maxOff end
        sb:SetMinMaxValues(0, maxOff)
        sb:SetValue(self.offset)
        sb:SetShown(maxOff > 0)
        for i = 1, n do
            local row = self.rows[i]
            local item = data[self.offset + i]
            row.item = item
            if item then
                local xc = XP_COLORS[item.xpStatus or "unknown"]
                row.xpBar:SetColorTexture(xc[1], xc[2], xc[3], 0.9)
                row.level:SetTextColor(xc[1], xc[2], xc[3])
                spec.populate(row, item)
                row:Show()
            else
                row:Hide()
            end
        end
        self.empty:SetShown(#data == 0)
    end

    return f
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- The second line: what they're listed for, then the listing's extras the game shows
-- (playstyle, new player friendly, Discord). Your own listing and matches to it are coloured
-- as the game colours them (green, blue).
-- Rows follow the game's nested search entry: name, then the activity and where the leader is,
-- then the playstyle line; party (or roles) and actions on the right.

-- Line 2's activity, coloured as the game colours it (your listing green, matches blue).
local function ActivityName(e)
    if e.isSelf then return "|cff80ff80" .. (LFG_SELF_LISTING or "Your listing") .. "|r" end
    local first = e.xpActivity or ns.RelevantActivities(e)[1] or e.activityIDs[1]
    if not first then return "?" end
    local name = ns.GetActivityName(first)
    if #e.activityIDs > 1 then name = name .. ("|cff999999 +%d|r"):format(#e.activityIDs - 1) end
    if e.matchesMine then name = "|cff66bbff" .. name .. "|r" end
    return name
end

-- Friends and guildmates in a listing, as a short badge.
local function SocialText(e)
    local parts = {}
    if (e.friends or 0) > 0 then
        local icon = HasAtlas("groupfinder-icon-friend") and "|A:groupfinder-icon-friend:14:14|a" or ""
        parts[#parts + 1] = ("%s|cff66ccff%d %s|r"):format(icon, e.friends, e.friends == 1 and "friend" or "friends")
    end
    if (e.guildmates or 0) > 0 then
        parts[#parts + 1] = ("|cff40ff40%d %s|r"):format(e.guildmates, e.guildmates == 1 and "guildmate" or "guildmates")
    end
    return table.concat(parts, "  ")
end
ns.SocialText = SocialText

-- Line 3: friends and guildmates, playstyle (green, as the game shows it), new player friendly, Discord.
local function ExtrasText(e)
    local extras = {}
    local social = SocialText(e)
    if social ~= "" then extras[#extras + 1] = social end
    local info = e.info
    if info.generalPlaystyle and info.generalPlaystyle ~= 0 and GetGeneralPlaystyleString then
        local ok, s = pcall(GetGeneralPlaystyleString, info.generalPlaystyle)
        if ok and s and s ~= "" then extras[#extras + 1] = "|cff19ff19" .. s .. "|r" end
    end
    if info.newPlayerFriendly then
        extras[#extras + 1] = HasAtlas("newplayerchat-chaticon-newcomer") and "|A:newplayerchat-chaticon-newcomer:14:14|a" or "|cff80ff80New|r"
    end
    if Enum.LFGEntryVoiceMode and info.voiceMode == Enum.LFGEntryVoiceMode.Discord then
        extras[#extras + 1] = "|cff8c9eff" .. (VOICE_CHAT_MODE_DISCORD or "Discord") .. "|r"
    end
    return table.concat(extras, "  ")
end

-- Where the leader is, after the activity: red on the wrong continent, green at the dungeon.
local function WhereText(e)
    local p = e.leader
    local zone = p and p.areaName
    if not zone or zone == "" then return "" end
    if e.isSolo and e.inDungeon then return "|cff55ff55" .. zone .. "|r" end
    if e.isSolo and e.distance == "far" then
        return ("|cffff5555%s (%s)|r"):format(zone, e.continent or "?")
    end
    return "|cffd0d0d0" .. zone .. "|r"
end

local function ListingTitle(e)
    local n = e.info.name
    if type(n) == "string" and n ~= "" then return n end
end

local LEVEL_X = 236     -- the XP-coloured level, between the text and the right-hand column
local TEXT_W = LEVEL_X - 30

local function BuildTextLines(row)
    row.name:SetWidth(TEXT_W)
    row.sub:SetWidth(TEXT_W)
    row.line3 = Text(row, "GameFontDisableLeft")
    row.line3:SetPoint("TOPLEFT", row.sub, "BOTTOMLEFT", 0, -2)
    row.line3:SetWidth(TEXT_W)
    row.line3:SetJustifyH("LEFT")
    row.line3:SetWordWrap(false)
    row.level:SetPoint("LEFT", LEVEL_X, 0)
    row.level:SetWidth(36)
end

-- Groups: party seats top-right, Request to join and whisper below them.
local function BuildGroupRow(row)
    BuildTextLines(row)
    if HasAtlas("groupfinder-icon-leader") then row.icon:SetAtlas("groupfinder-icon-leader") end
    row.slots = {}
    for i = 5, 1, -1 do
        local s = Slot(row)
        s:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8 - (5 - i) * (SLOT + 1), -8)
        row.slots[i] = s
    end
    row.raid = Text(row, "GameFontHighlight")
    row.raid:SetPoint("TOPRIGHT", -8, -11)

    row.join = RedButton(row, "Request to join", 104, 20, true)
    row.join:SetPoint("BOTTOMRIGHT", -8, 8)
    row.join:SetScript("OnClick", function()
        if row.item then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            ns.RequestToJoin(row.item)
        end
    end)
    row.join:SetMotionScriptsWhileDisabled(true)
    Tooltip(row.join, "Request to join",
        "Opens a whisper to the leader with your request ready to send. Press Enter to send it. Change the message in the cog menu > Messages.\n\nForever's group finder has no applications; leaders invite you from a whisper.")
    row.whisper = IconButton(row, "Interface\\GossipFrame\\GossipGossipIcon", 18, "Whisper the leader",
        function() if row.item then ns.Whisper(row.item.leaderName) end end)
    row.whisper:SetPoint("RIGHT", row.join, "LEFT", -6, 0)
end

local function PopulateGroup(row, e)
    local leader = e.leader or {}
    row.name:SetText(ShortName(e.leaderName) or "?")
    row.name:SetTextColor(ClassColor(leader.classFilename))
    local where = WhereText(e)
    row.sub:SetText(ActivityName(e) .. (where ~= "" and ("  " .. where) or ""))
    row.line3:SetText(ExtrasText(e))
    row.level:SetText(e.maxLevel and tostring(e.maxLevel) or "?")
    row.join:SetShown(not e.isSelf)
    row.whisper:SetShown(not e.isSelf)

    -- More than five (a raid, or a big group): condensed by role, as the game's role-count display.
    if e.maxPlayers > 5 or e.numMembers > 5 then
        for i = 1, 5 do row.slots[i]:Hide() end
        local c = e.counts or {}
        local size = e.maxPlayers > 5 and ("%d/%d"):format(e.numMembers, e.maxPlayers) or tostring(e.numMembers)
        row.raid:SetText(("%s%d  %s%d  %s%d   |cffaaaaaa%s|r"):format(RoleMarkup("tank", 16), c.TANK or e.tanks,
            RoleMarkup("healer", 16), c.HEALER or e.healers, RoleMarkup("dps", 16), c.DAMAGER or e.dps, size))
        row.raid:Show()
        return
    end
    row.raid:Hide()
    -- Members by role (tanks, healers, then damage), then empty seats.
    local ordered = {}
    for _, key in ipairs({ "TANK", "HEALER", "DAMAGER", "NONE" }) do
        for _, p in ipairs(e.members) do
            local r = p.assignedRole
            if r == key or (key == "NONE" and not ROLE_FROM_ASSIGNED[r]) then ordered[#ordered + 1] = p end
        end
    end
    for i = 1, 5 do
        local p = ordered[i]
        if p then
            SetSlot(row.slots[i], ROLE_FROM_ASSIGNED[p.assignedRole])
        elseif i <= e.maxPlayers and i > e.numMembers then
            SetSlot(row.slots[i], nil, true)
        elseif i <= e.numMembers then
            SetSlot(row.slots[i], nil) -- a member we got no details for
        else
            row.slots[i]:Hide()
        end
    end
end

-- Players: the roles they'll play top-right, Invite and whisper below them.
local function BuildPlayerRow(row)
    BuildTextLines(row)
    row.roleSlots = {}
    for i = 1, 3 do
        local s = Slot(row)
        row.roleSlots[i] = s
    end

    row.invite = RedButton(row, INVITE or "Invite", 70, 20, true)
    row.invite:SetPoint("BOTTOMRIGHT", -8, 8)
    row.invite:SetScript("OnClick", function()
        if row.item and ns.CanInvite(row.item) then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            ns.InviteListed(row.item)
        end
    end)
    row.invite:SetMotionScriptsWhileDisabled(true)
    Tooltip(row.invite, INVITE or "Invite", "Invite them to your party, and whisper them your invite message if you've set one (cog menu > Messages). Only the leader or an assistant can invite while you're in a group.")
    row.whisper = IconButton(row, "Interface\\GossipFrame\\GossipGossipIcon", 18, "Whisper",
        function() if row.item then ns.Whisper(row.item.leaderName) end end)
    row.whisper:SetPoint("RIGHT", row.invite, "LEFT", -6, 0)
end

local function PopulatePlayer(row, e)
    local p = e.leader or {}
    row.name:SetText(ShortName(p.name or e.leaderName) or "?")
    row.name:SetTextColor(ClassColor(p.classFilename))
    -- The game's class icon before a solo player's name.
    local classAtlas = p.classFilename and ("groupfinder-icon-class-" .. p.classFilename:lower())
    if classAtlas and HasAtlas(classAtlas) then
        row.icon:SetAtlas(classAtlas)
        row.icon:Show()
    elseif p.classFilename then
        SetClassIcon(row.icon, p.classFilename)
        row.icon:Show()
    else
        row.icon:Hide()
    end
    local where = WhereText(e)
    row.sub:SetText(ActivityName(e) .. (where ~= "" and ("  " .. where) or ""))
    row.line3:SetText(ExtrasText(e))
    row.level:SetText(p.level and tostring(p.level) or "?")
    row.invite:SetShown(not e.isSelf)
    row.whisper:SetShown(not e.isSelf)
    row.invite:SetEnabled(ns.CanInvite(e))

    -- Roles right-aligned, as the game lines them up.
    local shown = {}
    local r = e.roles or {}
    for _, key in ipairs(ROLE_KEYS) do
        if r[key] then shown[#shown + 1] = key end
    end
    for i = 1, 3 do
        local s = row.roleSlots[i]
        local key = shown[i]
        if key then
            s:ClearAllPoints()
            s:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8 - (#shown - i) * (SLOT + 1), -8)
            SetSlot(s, key)
        else
            s:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Tooltip and right-click menu
---------------------------------------------------------------------------
-- Beside the window, never over it: the game's tooltip is see-through, and the filters and
-- columns underneath showed through its text. Groups open to the left, players to the right,
-- swapping sides when the window is too close to the screen's edge.
local TIP_ROOM = 320
local function AnchorBesideWindow(owner, preferLeft)
    local win = _G.SeekerLFGFrame
    if not (win and win:GetLeft() and owner:GetLeft()) then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    local s = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local roomLeft = win:GetLeft() * s
    local roomRight = UIParent:GetWidth() - win:GetRight() * s
    local left = preferLeft
    if left and roomLeft < TIP_ROOM and roomRight >= TIP_ROOM then left = false end
    if not left and roomRight < TIP_ROOM and roomLeft >= TIP_ROOM then left = true end
    -- Offsets are in the tooltip's own scale; the row and window share the window's.
    local k = win:GetEffectiveScale() / GameTooltip:GetEffectiveScale()
    GameTooltip:ClearAllPoints()
    if left then
        GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -(owner:GetLeft() - win:GetLeft()) * k - 6, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", (win:GetRight() - owner:GetRight()) * k + 6, 0)
    end
end

-- Everyone in the listing, read fresh as the game's tooltip reads them: the leader
-- (GetSearchResultLeaderInfo), then each other member (GetSearchResultPlayerInfo).
local function ListingMembers(e)
    local list = {}
    local LFG = C_LFGList
    local okL, leader = pcall(LFG.GetSearchResultLeaderInfo, e.id)
    if okL and leader and leader.name then list[1] = leader end
    for i = 1, e.numMembers or 1 do
        local ok, p = pcall(LFG.GetSearchResultPlayerInfo, e.id, i)
        if ok and p and p.name and not (p.isLeader and list[1]) then list[#list + 1] = p end
    end
    if #list == 0 then return e.members end
    return list
end

-- A member's location: their zone and continent, red when a solo player is on the wrong
-- continent for their dungeon, green when they're at it.
local function MemberWhere(e, p)
    local zone = p.areaName
    if not zone or zone == "" then return "" end
    local cont = ns.GetZoneContinent(zone)
    local text = zone .. (cont and cont ~= zone and (", " .. cont) or "")
    if e.isSolo and e.inDungeon then return "|cff55ff55" .. text .. "|r" end
    if e.isSolo and e.distance == "far" then return "|cffff5555" .. text .. "|r" end
    return "|cffbbbbbb" .. text .. "|r"
end

local function MemberRoles(e, p)
    if e.isSolo then
        local s = ""
        for _, key in ipairs(ROLE_KEYS) do
            if p.lfgRoles and p.lfgRoles[key] then s = s .. RoleMarkup(key, 14) end
        end
        return s
    end
    local key = ROLE_FROM_ASSIGNED[p.assignedRole]
    return key and RoleMarkup(key, 14) or ""
end

local BIG_GROUP = 10 -- the game lists members one by one only up to 10

local function AddMembers(e)
    local members = ListingMembers(e)
    if #members > BIG_GROUP then
        -- A big group, condensed by role: each role's count, then its members by name.
        local byRole = { tank = {}, healer = {}, dps = {}, none = {} }
        for _, p in ipairs(members) do
            local key = ROLE_FROM_ASSIGNED[p.assignedRole] or "none"
            local r, g, b = ClassColor(p.classFilename)
            byRole[key][#byRole[key] + 1] = Hex(r, g, b) .. ShortName(p.name) .. "|r"
                .. (p.isLeader and "|A:groupfinder-icon-leader:12:12|a" or "")
        end
        for _, key in ipairs({ "tank", "healer", "dps", "none" }) do
            local names = byRole[key]
            if #names > 0 then
                local label = key == "none" and (NO_ROLE or "No role") or ROLE_NAMES[key]
                GameTooltip:AddLine(("%s %s (%d)"):format(key ~= "none" and RoleMarkup(key, 14) or "", label, #names), 1, 0.82, 0)
                GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
            end
        end
        return
    end
    for _, p in ipairs(members) do
        local r, g, b = ClassColor(p.classFilename)
        local left = ("%s%s%s|r |cff999999%s %s|r %s"):format(
            (not e.isSolo and p.isLeader) and "|A:groupfinder-icon-leader:12:12|a " or "",
            Hex(r, g, b), ShortName(p.name) or "?", LEVEL_ABBR or "Lv", p.level and tostring(p.level) or "?", MemberRoles(e, p))
        GameTooltip:AddDoubleLine(left, MemberWhere(e, p), 1, 1, 1, 1, 1, 1)
    end
end

function ns.ShowEntryTooltip(owner, e)
    AnchorBesideWindow(owner, not e.isSolo)
    local info = e.info
    -- Each part on its own, so one that fails can't hide the rest.
    local function Part(fn)
        local ok = pcall(fn)
        return ok
    end

    -- Title: the listing's name if it has one, else the leader.
    Part(function()
        local leader = e.leader or {}
        local title = ListingTitle(e)
        if title then
            GameTooltip:AddLine(title, 1, 1, 1)
        else
            GameTooltip:AddLine(ShortName(e.leaderName) or "?", ClassColor(leader.classFilename))
        end
        if info.newPlayerFriendly then
            GameTooltip:AddLine((HasAtlas("newplayerchat-chaticon-newcomer") and "|A:newplayerchat-chaticon-newcomer:14:14|a " or "")
                .. (LFG_LIST_NEW_PLAYER_FRIENDLY_HEADER or LFG_LIST_NEW_PLAYER_FRIENDLY or "New Player Friendly"), 0.1, 1, 0.1)
        end
    end)

    -- Friends and guildmates in it.
    Part(function()
        local social = SocialText(e)
        if social ~= "" then GameTooltip:AddLine(social, 1, 1, 1) end
    end)

    -- Everyone in it, with where they are.
    Part(function()
        GameTooltip:AddLine(" ")
        AddMembers(e)
    end)

    -- The group's note.
    Part(function()
        local comment = info.comment
        if comment and comment ~= "" then
            GameTooltip:AddLine(" ")
            local okF, text = pcall(string.format, LFG_LIST_COMMENT_FORMAT or "\"%s\"", comment)
            GameTooltip:AddLine(okF and text or comment, 0.85, 0.85, 0.85, true)
        end
    end)

    -- Member count by role (the game's line), playstyle, voice chat.
    Part(function()
        GameTooltip:AddLine(" ")
        if e.isSolo then
            if LFG_LIST_TOOLTIP_MEMBERS_SIMPLE then
                GameTooltip:AddLine(LFG_LIST_TOOLTIP_MEMBERS_SIMPLE:format(e.numMembers), 1, 0.82, 0)
            end
        else
            local c = e.counts or {}
            local tanks, healers, dps = c.TANK or e.tanks, c.HEALER or e.healers, c.DAMAGER or e.dps
            if LFG_LIST_TOOLTIP_MEMBERS then
                GameTooltip:AddLine(LFG_LIST_TOOLTIP_MEMBERS:format(e.numMembers, tanks, healers, dps), 1, 0.82, 0)
            else
                GameTooltip:AddLine(("Members: %d (%d/%d/%d)"):format(e.numMembers, tanks, healers, dps), 1, 0.82, 0)
            end
        end
        if info.generalPlaystyle and info.generalPlaystyle ~= 0 and GetGeneralPlaystyleString then
            local okP, s = pcall(GetGeneralPlaystyleString, info.generalPlaystyle)
            if okP and s then GameTooltip:AddLine((PLAYSTYLE or "Playstyle") .. ": |cff19ff19" .. s .. "|r", 0.8, 0.8, 0.8) end
        end
        if Enum.LFGEntryVoiceMode and info.voiceMode and info.voiceMode ~= Enum.LFGEntryVoiceMode.None then
            local labels = {
                [Enum.LFGEntryVoiceMode.Legacy] = VOICE_CHAT_MODE_LEGACY,
                [Enum.LFGEntryVoiceMode.Discord] = VOICE_CHAT_MODE_DISCORD,
                [Enum.LFGEntryVoiceMode.Custom] = VOICE_CHAT_MODE_CUSTOM,
            }
            if labels[info.voiceMode] then
                GameTooltip:AddLine((VOICE_CHAT or "Voice chat") .. ": " .. labels[info.voiceMode], 0.8, 0.8, 0.8)
            end
        end
    end)

    -- What they're listed for, and bosses already down.
    Part(function()
        GameTooltip:AddLine(" ")
        for _, id in ipairs(e.activityIDs) do
            local lo, hi = ns.GetActivityRange(id)
            local where = ns.GetActivityContinent(id)
            GameTooltip:AddLine(ns.GetActivityName(id) .. (lo and (" (%d-%d)"):format(lo, hi) or "")
                .. (where and ("  |cff999999%s|r"):format(where) or ""), 0.6, 0.8, 1)
        end
        if not e.isSolo and C_LFGList.GetSearchResultEncounterInfo then
            local okE, done = pcall(C_LFGList.GetSearchResultEncounterInfo, e.id)
            if okE and done and #done > 0 then
                GameTooltip:AddLine(LFG_LIST_BOSSES_DEFEATED or BOSSES_KILLED or "Bosses defeated:", 1, 0.82, 0)
                for _, boss in ipairs(done) do GameTooltip:AddLine("    " .. boss, 0.9, 0.5, 0.5) end
            end
        end
        if e.isSolo and e.distance == "far" and e.continent then
            GameTooltip:AddLine(("On %s, but the dungeon is in %s."):format(e.continent, e.dungeonContinent or "another continent"),
                1, 0.3, 0.3, true)
        end
    end)

    -- XP for you, and how long it's been listed.
    Part(function()
        GameTooltip:AddLine(" ")
        local c = XP_COLORS[e.xpStatus or "unknown"]
        GameTooltip:AddLine("XP: " .. XP_LABELS[e.xpStatus or "unknown"], c[1], c[2], c[3])
        if e.xpLo then
            GameTooltip:AddLine(("Highest level %d%s vs mobs ~%d-%d. Full XP up to %d, some XP up to %d."):format(
                e.effectiveLevel, e.selfIsHighest and " (you)" or "", e.xpLo, e.xpHi,
                e.xpLo + ns.XP_GAP, e.xpHi + ns.XP_GAP), 0.75, 0.75, 0.75, true)
        end
        GameTooltip:AddLine(("Listed %s ago"):format(FormatAge(e.age)), 0.5, 0.5, 0.5)
    end)

    GameTooltip:Show()
end

function ns.EntryMenu(owner, e)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Whisper(e.leaderName)
        return
    end
    -- The game's own menu: send message, invite (where allowed), report, report advertisement.
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(e.leaderName or "?")
        if e.isSelf then
            root:CreateButton(LFG_LIST_EDIT or "Edit your listing", function() ns.ShowTab("listing") end)
            root:CreateButton(LFG_LIST_UNLIST or "Delist", function() ns.RemoveListing() end)
            return
        end
        root:CreateButton(SEND_MESSAGE or "Whisper", function() ns.Whisper(e.leaderName) end)
        if e.isSolo then
            local invite = root:CreateButton(GROUP_INVITE or "Invite", function() ns.InviteListed(e) end)
            invite:SetEnabled(ns.CanInvite(e))
        else
            root:CreateButton("Request to join", function() ns.RequestToJoin(e) end)
        end
        root:CreateDivider()
        root:CreateButton(LFG_LIST_REPORT_GROUP_FOR or "Report listing", function() ns.ReportListing(e, false) end)
        root:CreateButton(REPORT_GROUP_FINDER_ADVERTISEMENT or "Report advertisement", function() ns.ReportListing(e, true) end)
    end)
end

-- Shared with the Listing and Who pages, so every page is built from the same parts.
ns.UI = {
    TryCreate = TryCreate, HasAtlas = HasAtlas, Font = Font, Text = Text, Tooltip = Tooltip,
    ClassColor = ClassColor, Hex = Hex, ClassName = ClassName, SetClassIcon = SetClassIcon, ShortName = ShortName,
    Inset = Inset, HeaderBar = HeaderBar, RedButton = RedButton, Check = Check, NumberBox = NumberBox,
    Dropdown = Dropdown, Radio = Radio, Chip = Chip, UpdateToggles = UpdateToggles, IconButton = IconButton,
    ApplyRole = ApplyRole, RoleMarkup = RoleMarkup, AnchorBesideWindow = AnchorBesideWindow,
    SIZE_NAME = SIZE_NAME, SIZE_SUB = SIZE_SUB, SIZE_LEVEL = SIZE_LEVEL, SIZE_HEAD = SIZE_HEAD, SIZE_LABEL = SIZE_LABEL,
    ROLE_KEYS = ROLE_KEYS, ROLE_NAMES = ROLE_NAMES, TOPBAR_Y = TOPBAR_Y, FILTER_TOP = FILTER_TOP,
    HEADER_H = HEADER_H, SCROLL_W = SCROLL_W, FRAME_W = FRAME_W, FRAME_H = FRAME_H, WHITE = WHITE,
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame

function ns.Render()
    if not frame or not frame:IsShown() then return end
    ns.UpdateListedState()
    if not frame.pages.browse:IsShown() then return end
    ns.UpdateFiltersButton()
    local groups, players, totalG, totalP = ns.GetFiltered()
    frame.groups:SetData(groups, totalG)
    frame.players:SetData(players, totalP)
    frame.groups.empty:SetText(ns.searching and (SEARCHING or "Searching...")
        or ns.searchFailed and (LFG_LIST_SEARCH_FAILED or "Search failed.")
        or "No groups match. Search, or loosen the filters.")
    frame.players.empty:SetText(ns.searching and (SEARCHING or "Searching...")
        or ns.searchFailed and (LFG_LIST_SEARCH_FAILED or "Search failed.")
        or "No players match. Search, or loosen the filters.")
    frame.searchBtn:SetEnabled(not ns.searching)

    local me = UnitLevel("player") or 0
    local status = ("Level %d.  Kill XP is lost when the highest party member is more than %d levels above the mob."):format(me, ns.XP_GAP)
    local selList = ns.SelectedActivities()
    local sel = selList and #selList == 1 and selList[1]
    if sel then
        local lo, hi = ns.GetActivityRange(sel)
        if lo then
            local note
            if me > hi + ns.XP_GAP then note = "|cffff4d4dyou're too high for any XP here|r"
            elseif me > lo + ns.XP_GAP then note = "|cffffd133you'd only get XP from some mobs|r"
            else note = ("|cff55ff55full XP while nobody is above %d|r"):format(lo + ns.XP_GAP) end
            status = ("Level %d.  %s, mobs ~%d-%d: %s"):format(me, ns.GetActivityName(sel), lo, hi, note)
        end
    end
    frame.status:SetText(status)
end

-- "Filters (3)": how many filters are on while the panel is folded away.
function ns.UpdateFiltersButton()
    if not (frame and frame.filtersBtn) then return end
    local F = ns.db.filters
    local n = 0
    if F.xpMode ~= "off" then n = n + 1 end
    if F.levelMin or F.levelMax then n = n + 1 end
    if ns.AnyOn(F.groupNeeds) then n = n + 1 end
    if ns.AnyOn(F.playerRoles) then n = n + 1 end
    if next(F.classes) then n = n + 1 end
    if F.hideFull then n = n + 1 end
    if F.hideFar then n = n + 1 end
    if F.hideUnknown then n = n + 1 end
    frame.filtersBtn:SetText(n > 0 and ("Filters (%d)"):format(n) or "Filters")
end

local renderPending = false
function ns.QueueRender()
    if renderPending then return end
    renderPending = true
    C_Timer.After(0.15, function()
        renderPending = false
        ns.Render()
    end)
end

-- Position is the top-left corner in the window's own units, so it survives scaling.
function ns.SavePosition()
    if not frame then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then ns.db.pos = { left, top } end
    ns.db.scale = frame:GetScale()
end

-- Scale around the top-left corner, so the window grows down and right instead of jumping.
function ns.SetScale(s)
    if not frame then return end
    s = max(MIN_SCALE, min(MAX_SCALE, s))
    local old = frame:GetScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    frame:SetScale(s)
    if left and top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / s, top * old / s)
    end
end

function ns.StepScale(delta)
    if not frame then return end
    ns.SetScale(frame:GetScale() + delta * SCALE_STEP)
    ns.SavePosition()
end

local function FitScale()
    return min(1, UIParent:GetWidth() * 0.95 / FRAME_W, UIParent:GetHeight() * 0.9 / FRAME_H)
end

local function PickDefaultCategory()
    local db = ns.db
    local cats = ns.GetCategories()
    for _, c in ipairs(cats) do if c.id == db.categoryID then return end end
    db.categoryID = nil
    ns.ClearActivitySelection()
    for _, c in ipairs(cats) do
        if c.name:lower():find("dungeon") then db.categoryID = c.id break end
    end
    db.categoryID = db.categoryID or (cats[1] and cats[1].id)
end

-- The activity dropdown's text, as the game words it: all, one name, or "N activities".
local function ActivityDropdownText()
    if ns.db.searchSelf then return LFG_SELF_LISTING or "Your listing" end
    local sel = ns.SelectedActivities()
    if not sel then return LFGBROWSE_ACTIVITY_HEADER_DEFAULT or "All activities" end
    if #sel == 1 then return ns.GetActivityName(sel[1]) end
    return (LFGBROWSE_ACTIVITY_HEADER or "%d Activities"):format(#sel)
end

local function RefreshDropdowns()
    frame.catDD:Refresh()
    frame.actDD:Refresh()
    local t = ActivityDropdownText()
    if frame.actDD.OverrideText then frame.actDD:OverrideText(t)
    elseif frame.actDD.SetText then frame.actDD:SetText(t) end
end
ns.RefreshDropdowns = function() if frame then RefreshDropdowns() end end

-- Activity label with its level range, coloured by what it'd give you in XP.
local function ActivityLabel(id)
    local name = ns.GetActivityName(id)
    local lo, hi = ns.GetActivityRange(id)
    if not lo then return name end
    local me = UnitLevel("player") or 0
    local color = "|cff999999"
    if me >= lo - 5 and me <= lo + ns.XP_GAP then color = "|cff55ff55"
    elseif me >= lo - 5 and me <= hi + ns.XP_GAP then color = "|cffffd133" end
    return ("%s  %s%d-%d|r"):format(name, color, lo, hi)
end
ns.ActivityLabel = ActivityLabel

local function AddGrip(f)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 6)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        local startX = GetCursorPosition() / UIParent:GetEffectiveScale()
        local startWidth = f:GetWidth() * f:GetScale()
        grip:SetScript("OnUpdate", function()
            local x = GetCursorPosition() / UIParent:GetEffectiveScale()
            ns.SetScale((startWidth + x - startX) / f:GetWidth())
        end)
    end)
    local function EndDrag()
        if grip:GetScript("OnUpdate") then
            grip:SetScript("OnUpdate", nil)
            ns.SavePosition()
        end
    end
    grip:SetScript("OnMouseUp", EndDrag)
    f:HookScript("OnHide", EndDrag)
    Tooltip(grip, "Drag to resize", "Scales the whole window, text included. Ctrl + mouse wheel over the window does the same.")
end

local function BuildFilters(f, panel)
    local db = ns.db
    local F = db.filters
    local L = 12          -- left margin
    local CHIP_X = 96     -- where chips start, after the row labels
    local function Label(text, x, y)
        local fs = Text(panel, "GameFontNormal")
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end

    -- Row 1: level range and XP mode
    Label("Level", L, -15)
    local minBox = NumberBox(panel, function() return F.levelMin end, function(v) F.levelMin = v; ns.QueueRender() end)
    minBox:SetPoint("TOPLEFT", CHIP_X + 4, -9)
    local to = Text(panel, "GameFontHighlightSmall")
    to:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
    to:SetText("to")
    local maxBox = NumberBox(panel, function() return F.levelMax end, function(v) F.levelMax = v; ns.QueueRender() end)
    maxBox:SetPoint("LEFT", to, "RIGHT", 8, 0)

    local xpLabel = Label("XP", CHIP_X + 112, -15)
    local xpModes = {
        { key = "strict", label = "Full XP", tip = "Only show groups and players where every kill gives you XP: nobody more than 12 levels above the dungeon's lowest mobs." },
        { key = "lenient", label = "Any XP", tip = "Also show those where only the tougher mobs give XP: nobody more than 12 levels above the dungeon's highest mobs." },
        { key = "off", label = "Show all", tip = "Don't filter by level." },
    }
    local prev
    for _, m in ipairs(xpModes) do
        local chip = Chip(panel, 78, 26, m.label, nil, function() return F.xpMode == m.key end,
            function() F.xpMode = m.key end, m.label, m.tip)
        if prev then
            chip:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        else
            chip:SetPoint("LEFT", xpLabel, "RIGHT", 8, 0)
        end
        prev = chip
    end

    -- Rows 2 and 3: role chips
    local function RoleRow(label, y, set, verb, extra)
        Label(label, L, y - 7)
        local p
        for _, key in ipairs(ROLE_KEYS) do
            local chip = Chip(panel, 84, 28, ROLE_NAMES[key], function(tex) ApplyRole(tex, key) end, function() return set[key] end,
                function() set[key] = not set[key] end, ROLE_NAMES[key], verb:format(ROLE_NAMES[key]:lower()))
            if p then chip:SetPoint("LEFT", p, "RIGHT", 3, 0) else chip:SetPoint("TOPLEFT", CHIP_X, y) end
            p = chip
        end
        local c = Check(panel, extra.label, function() return F[extra.key] end,
            function(v) F[extra.key] = v; ns.Render() end, extra.label, extra.tip)
        c:SetPoint("LEFT", p, "RIGHT", 8, 0)
    end
    RoleRow("Group needs", -40, F.groupNeeds, "Only show groups with room for a %s. Pick none to show all.",
        { key = "hideFull", label = "Hide full", tip = "Hide groups with no open seats." })
    RoleRow("Player can", -72, F.playerRoles, "Only show players willing to %s. Pick none to show all.",
        { key = "hideFar", label = "Hide far away",
          tip = "Hide players on a different continent from the dungeon they listed, like someone in Kalimdor queued for the Deadmines." })

    -- Right side: classes, then the two level options
    local DIV_X = 566
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.6, 0.5, 0.3, 0.35)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", DIV_X, -8)
    divider:SetPoint("BOTTOMLEFT", DIV_X, 8)

    local CX = DIV_X + 12
    local classLabel = Label("Player class", CX, -15)
    local clear = CreateFrame("Button", nil, panel)
    clear:SetSize(50, 16)
    clear:SetPoint("LEFT", classLabel, "RIGHT", 8, 0)
    clear.text = Text(clear, "GameFontHighlightSmall")
    clear.text:SetPoint("LEFT")
    clear.text:SetText("|cff999999(any)|r")
    clear:SetScript("OnClick", function()
        wipe(F.classes)
        UpdateToggles()
        ns.Render()
    end)
    Tooltip(clear, "Any class", "Clear the class filter.")

    for i, cls in ipairs(CLASSES) do
        local chip = Chip(panel, 34, 34, nil, function(tex) SetClassIcon(tex, cls) end,
            function() return F.classes[cls] end,
            function() F.classes[cls] = not F.classes[cls] or nil end,
            Hex(ClassColor(cls)) .. ClassName(cls) .. "|r", "Only show players of the classes you pick. Pick none to show all.")
        chip:SetPoint("TOPLEFT", CX + (i - 1) * 36, -34)
    end
    local me = Check(panel, "Count my level", function() return F.includeSelf end,
        function(v) F.includeSelf = v; ns.Render() end, "Count my level",
        "Include your own level in the XP check, so the colours show what happens if you join.")
    me:SetPoint("TOPLEFT", CX - 2, -74)
    local unk = Check(panel, "Hide unknown levels", function() return F.hideUnknown end,
        function(v) F.hideUnknown = v; ns.Render() end, "Hide unknown levels",
        "Hide listings the game reported no level for.")
    unk:SetPoint("TOPLEFT", CX + 150, -74)
end

-- Side tabs, after the game's own (Listing, Browse, Who), in the spellbook's side-tab style.
local TABS = {
    { key = "listing", icon = "Interface\\Icons\\INV_SideTab_GroupFinder_c60", fallback = "Interface\\Icons\\INV_Misc_GroupNeedMore",
      label = function() return ns.HasListing() and (LFG_LIST_EDIT or "Your listing") or (LFG_LIST_TAB_1 or "List yourself") end },
    { key = "browse", icon = "Interface\\Icons\\INV_SideTab_GroupBrowsing_c60", fallback = "Interface\\Icons\\INV_Misc_Spyglass_03",
      label = function() return LFG_LIST_TAB_2 or "Browse groups" end },
    { key = "who", icon = "Interface\\Icons\\INV_SideTab_WhoList_c60", fallback = "Interface\\Icons\\INV_Misc_GroupLooking",
      label = function() return LFG_LIST_TAB_3 or WHO or "Who" end },
}

-- The game's own side tab (LargeSideTabButtonTemplate), set up as its group finder sets up its
-- tabs (LFGParentFrameRightTabMixin): sized from the "common-sidetab" art, a 30px icon, the
-- first tab 60px down the window's right edge and 2px between tabs.
local function CreateNativeSideTab(f, def, prev)
    local tab = TryCreate("Frame", nil, f, "LargeSideTabButtonTemplate")
    if not (tab and tab.Icon and tab.SetCustomOnMouseUpHandler) then return nil end
    tab.Icon:SetTexture(def.icon)
    if not tab.Icon:GetTexture() then tab.Icon:SetTexture(def.fallback) end
    -- As the game's group finder tabs: the icon fills the tab's interior (fillToInterior, 50px).
    tab.Icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
    if tab.SetFillToInterior then
        tab:SetFillToInterior(true)
    else
        tab.fillToInterior = true
        tab.Icon:SetSize(50, 50)
    end
    tab.tooltipText = def.label()
    tab:SetCustomOnMouseUpHandler(function(self, button, upInside)
        if button == "LeftButton" and upInside then ns.ShowTab(def.key) end
    end)
    if prev then
        tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
    else
        tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -60)
    end
    tab.key, tab.def = def.key, def
    return tab
end

local function CreateSideTabs(f)
    f.tabs = {}
    local prev
    for i, def in ipairs(TABS) do
        local native = CreateNativeSideTab(f, def, prev)
        if native then
            f.tabs[i] = native
            prev = native
        else
        local tab = CreateFrame("CheckButton", nil, f)
        tab:SetSize(36, 36)
        if prev then
            tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -16)
        else
            tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -46)
        end
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        bg:SetSize(64, 64)
        bg:SetPoint("TOPLEFT", -3, 11)
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(def.icon)
        if not icon:GetTexture() then icon:SetTexture(def.fallback) end
        icon:SetTexCoord(0.03, 0.97, 0.03, 0.97)
        tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        -- The selected glow must be additive: drawn normally, its black background covers the icon.
        local checked = tab:CreateTexture(nil, "OVERLAY")
        checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        checked:SetBlendMode("ADD")
        checked:SetAllPoints()
        tab:SetCheckedTexture(checked)
        tab:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            ns.ShowTab(def.key)
        end)
        tab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(def.label(), 1, 1, 1)
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", GameTooltip_Hide)
        tab.key = def.key
        f.tabs[i] = tab
        prev = tab
        end
    end
end

function ns.ShowTab(key)
    if not frame then ns.Toggle() end
    if not frame.pages[key] then key = "browse" end
    ns.db.tab = key
    for k, page in pairs(frame.pages) do page:SetShown(k == key) end
    for _, tab in ipairs(frame.tabs) do
        tab:SetChecked(tab.key == key)
        if tab.def then tab.tooltipText = tab.def.label() end -- "List yourself" / "Your listing"
    end
    if not frame:IsShown() then frame:Show() end
    if key == "browse" then ns.Render() end
end

-- Listed or not: the eye portrait animates while you're listed (as the game's does), the
-- browse page offers Delist, and the listing page reloads.
function ns.UpdateListedState()
    if not frame then return end
    local listed = ns.HasListing()
    local eye = frame.eye
    if eye and eye.SetStaticMode and frame.eyeListed ~= listed then
        frame.eyeListed = listed
        pcall(eye.SetStaticMode, eye, not listed)
        if listed then
            pcall(eye.StartInitialAnimation, eye)
        else
            pcall(eye.StopAnimating, eye)
        end
    end
    if frame.delistBtn then frame.delistBtn:SetShown(listed and ns.CanEditListing()) end
    if ns.RefreshListingPage and frame.pages.listing and frame.pages.listing:IsShown() then ns.RefreshListingPage() end
end

local function BuildFrame()
    local db = ns.db
    -- The game's own window title (LFG_TITLE: "Looking For Group").
    local f = CreateShell("SeekerLFGFrame", LFG_TITLE or "Looking For Group", "Interface\\LFGFrame\\UI-LFG-PORTRAIT")
    frame = f
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("MEDIUM") -- as the game's own windows (the eye's animation layers are MEDIUM)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.SavePosition()
    end)
    f:SetScale(max(MIN_SCALE, min(MAX_SCALE, db.scale or FitScale())))
    if db.pos then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.pos[1], db.pos[2])
    else
        f:SetPoint("CENTER")
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() then ns.StepScale(delta) end
    end)
    AddGrip(f)
    f:Hide()
    tinsert(UISpecialFrames, "SeekerLFGFrame")

    -- The game's own LFG eye in the portrait: still, then watching while you're listed.
    local portrait = (f.PortraitContainer and f.PortraitContainer.portrait) or f.portrait
    -- Exactly as the game's window makes its portrait (LFGParentFramePortrait): a 64x64
    -- LFGEyeBigTemplate button at HIGH strata, centred 25,-22 from the top-left corner, so it
    -- sits over the portrait ring rather than under it.
    local eye = TryCreate("Button", nil, f, "LFGEyeBigTemplate")
    if eye and eye.SetStaticMode then
        eye:SetFrameStrata("HIGH")
        eye:SetSize(64, 64)
        eye:ClearAllPoints()
        eye:SetPoint("CENTER", f, "TOPLEFT", 25, -22)
        eye:SetScript("OnClick", eye.OnClick)
        eye:SetStaticMode(true)
        eye:Show()
        f.eye = eye
        if portrait then portrait:SetAlpha(0) end -- the eye is the portrait now
    end

    f.pages = {}
    local browse = CreateFrame("Frame", nil, f)
    browse:SetAllPoints()
    f.pages.browse = browse

    -- Cog (all pages): options, like OneCast's.
    local cog = CreateFrame("Button", nil, f)
    cog:SetSize(24, 24)
    cog:SetPoint("TOPRIGHT", -194, TOPBAR_Y)
    cog:SetFrameLevel(f:GetFrameLevel() + 10)
    local cogIcon = cog:CreateTexture(nil, "ARTWORK")
    cogIcon:SetAllPoints()
    if HasAtlas("questlog-icon-setting") then
        cogIcon:SetAtlas("questlog-icon-setting")
    else
        cogIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    end
    cog:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    cog:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.ShowOptionsMenu(self)
    end)
    Tooltip(cog, "Options", "Show all level ranges, replace the game's Looking for Group window, minimap button.")

    -- Browse: top bar (category, activities, search)
    local LEFT = 70
    f.catDD = Dropdown(browse, 140, function(root)
        local cats = ns.GetCategories()
        if ns.HasListing() then
            Radio(root, LFG_SELF_LISTING or "Your listing", function() return db.searchSelf end, function()
                db.searchSelf = true
                RefreshDropdowns()
                if ns.DoSearch() then ns.Render() end
            end)
        end
        if #cats == 0 and not ns.HasListing() then
            root:CreateTitle(LFG_TYPE_NONE or "None available")
        end
        for _, c in ipairs(cats) do
            Radio(root, c.name, function() return not db.searchSelf and db.categoryID == c.id end, function()
                db.categoryID, db.searchSelf = c.id, false
                ns.ClearActivitySelection()
                RefreshDropdowns()
                if ns.DoSearch() then ns.Render() end
            end)
        end
    end, function()
        if db.searchSelf then return LFG_SELF_LISTING or "Your listing" end
        return ns.GetCategoryName(db.categoryID) or CATEGORY or "Category"
    end)
    f.catDD:SetPoint("TOPLEFT", LEFT, TOPBAR_Y)

    -- Activities: sorted into what they'd give you in XP, lowest level first in each, with the level
    -- range in its own right-hand column. Several can be ticked; none ticked means all of them.
    f.actDD = Dropdown(browse, 200, function(root)
        if db.searchSelf or not db.categoryID then
            root:CreateTitle(db.searchSelf and "Searching your listing's activities" or "Pick a category first")
            return
        end
        local function IsOn(id) return ns.IsActivitySelected(id) end
        local function ToggleActivity(id)
            ns.SetActivitySelected(id, not ns.IsActivitySelected(id))
            RefreshDropdowns()
            ns.QueueRender()
        end

        local sections = ns.ActivitySections(db.categoryID)

        -- Quick picks
        root:CreateButton("All activities", function()
            ns.ClearActivitySelection()
            RefreshDropdowns()
            ns.Render()
        end)
        if #sections.full > 0 then
            root:CreateButton(("Every one with full XP for me (%d)"):format(#sections.full), function()
                ns.ClearActivitySelection()
                for _, id in ipairs(sections.full) do ns.SetActivitySelected(id, true) end
                RefreshDropdowns()
                ns.Render()
            end)
        end

        for _, sec in ipairs(ns.ACTIVITY_SECTIONS) do
            local list = sections[sec.key]
            if #list > 0 then
                root:CreateDivider()
                root:CreateTitle(sec.title)
                for _, id in ipairs(list) do
                    local name = ns.GetActivityName(id)
                    if sec.key == "none" then name = "|cff8a8a8a" .. name .. "|r" end
                    local lo, hi = ns.GetActivityRange(id)
                    local range = lo and (lo == hi and tostring(lo) or ("%d-%d"):format(lo, hi)) or ""
                    local box = root:CreateCheckbox(name, IsOn, ToggleActivity, id)
                    if box.AddInitializer and range ~= "" then
                        -- The level range right-aligned, as the game's own menus line up a second column.
                        box:AddInitializer(function(button)
                            if not button.AttachFontString then
                                if button.fontString then button.fontString:SetText(name .. "  " .. sec.color .. range .. "|r") end
                                return
                            end
                            local right = button:AttachFontString()
                            right:SetFontObject(GameFontHighlightSmall)
                            right:SetHeight(20)
                            right:SetPoint("RIGHT", -2, 0)
                            right:SetJustifyH("RIGHT")
                            right:SetText(sec.color .. range .. "|r")
                            local width = 52 + (button.fontString and button.fontString:GetUnboundedStringWidth() or 120)
                                + right:GetUnboundedStringWidth()
                            return width, 20
                        end)
                    elseif range ~= "" and box.SetText then
                        box:SetText(name .. "  " .. sec.color .. range .. "|r")
                    end
                end
            end
        end
    end, ActivityDropdownText)
    f.actDD:SetPoint("LEFT", f.catDD, "RIGHT", 6, 0)

    f.searchBtn = RedButton(browse, SEARCH or "Search", 86, 24)
    f.searchBtn:SetPoint("LEFT", f.actDD, "RIGHT", 8, 0)
    f.searchBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if ns.DoSearch() then ns.Render() end
    end)

    -- Delist, as the game's browse page offers while you're listed.
    f.delistBtn = RedButton(browse, LFG_LIST_UNLIST or "Delist", 76, 24)
    f.delistBtn:SetPoint("LEFT", f.searchBtn, "RIGHT", 4, 0)
    f.delistBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.RemoveListing()
    end)
    Tooltip(f.delistBtn, LFG_LIST_UNLIST or "Delist", "Take your listing off the group finder.")
    f.delistBtn:Hide()

    local find = TryCreate("EditBox", "SeekerLFGFindBox", browse, "SearchBoxTemplate")
        or CreateFrame("EditBox", "SeekerLFGFindBox", browse, "InputBoxTemplate")
    find:SetSize(170, 24)
    find:SetAutoFocus(false)
    find:SetPoint("TOPRIGHT", -16, TOPBAR_Y - 2)
    find:SetText(db.filters.text or "")
    find:HookScript("OnTextChanged", function(self)
        local t = strtrim(self:GetText() or "")
        if t ~= db.filters.text then
            db.filters.text = t
            ns.QueueRender()
        end
    end)
    find:SetScript("OnEnterPressed", find.ClearFocus)
    if find.Instructions then
        find.Instructions:SetText(SEARCH or "Search")
        find.Instructions:SetWordWrap(false)
        find.Instructions:SetMaxLines(1)
    end
    Tooltip(find, SEARCH or "Search", "Filter the lists by name, class, zone or dungeon.")

    -- Filter panel: folds away to give the lists the window's height, as the game's finder has
    -- no filter panel at all. The Filters button shows how many filters are on.
    local panel = Inset(browse)
    panel:SetPoint("TOPLEFT", 4, -FILTER_TOP)
    panel:SetPoint("TOPRIGHT", -6, -FILTER_TOP)
    panel:SetHeight(FILTER_H)
    BuildFilters(f, panel)
    f.filterPanel = panel

    local lists = Inset(browse)
    f.lists = lists
    f.filtersBtn = RedButton(browse, "Filters", 84, 24)
    f.filtersBtn:SetPoint("RIGHT", cog, "LEFT", -6, 0)
    f.filtersBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        db.filtersOpen = not db.filtersOpen
        ns.LayoutBrowse()
    end)
    Tooltip(f.filtersBtn, "Filters", "Show or hide the filters: XP, level, roles, classes and distance. They stay on while hidden.")
    ns.LayoutBrowse = function()
        panel:SetShown(db.filtersOpen and true or false)
        lists:ClearAllPoints()
        lists:SetPoint("TOPLEFT", 4, -(db.filtersOpen and LISTS_TOP_OPEN or LISTS_TOP_CLOSED))
        lists:SetPoint("BOTTOMRIGHT", -6, LISTS_BOTTOM)
        ns.UpdateFiltersButton()
    end
    local paneW = floor((FRAME_W - 10 - 2 * EDGE - GAP) / 2)

    f.groups = CreatePane(lists, {
        title = LFG_LIST_CATEGORY_GROUPS or "Groups",
        emptyText = "No groups match. Search, or loosen the filters.",
        buildRow = BuildGroupRow,
        populate = PopulateGroup,
    })
    f.groups:SetPoint("TOPLEFT", EDGE, -EDGE)
    f.groups:SetPoint("BOTTOMLEFT", EDGE, EDGE)
    f.groups:SetWidth(paneW)

    f.players = CreatePane(lists, {
        title = LFG_LIST_CATEGORY_SOLO_PLAYERS or "Players",
        emptyText = "No players match. Search, or loosen the filters.",
        buildRow = BuildPlayerRow,
        populate = PopulatePlayer,
    })
    f.players:SetPoint("TOPRIGHT", -EDGE, -EDGE)
    f.players:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    f.players:SetWidth(paneW)

    -- Bottom bar: status left, colour key right
    local legend = Text(browse, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOMRIGHT", -24, 8)
    local function key(k)
        local c = XP_COLORS[k]
        return ("|T%s:9:9:0:0:8:8:0:8:0:8:%d:%d:%d|t %s"):format(WHITE,
            floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255), XP_LABELS[k])
    end
    legend:SetText(("%s   %s   %s   %s"):format(key("safe"), key("partial"), key("none"), key("unknown")))

    f.status = Text(browse, "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 14, 8)
    f.status:SetPoint("RIGHT", legend, "LEFT", -16, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)

    ns.LayoutBrowse()
    browse:SetScript("OnShow", function()
        PickDefaultCategory()
        RefreshDropdowns()
        UpdateToggles()
    end)

    -- The other pages
    for _, key in ipairs({ "listing", "who" }) do
        local page = CreateFrame("Frame", nil, f)
        page:SetAllPoints()
        page:Hide()
        f.pages[key] = page
    end
    if ns.BuildListingPage then ns.BuildListingPage(f, f.pages.listing) end
    if ns.BuildWhoPage then ns.BuildWhoPage(f, f.pages.who) end

    CreateSideTabs(f)

    f:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        ns.ShowTab(db.tab or "browse")
        ns.UpdateListedState()
    end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end)
end

function ns.Toggle()
    if not frame then BuildFrame() end
    frame:SetShown(not frame:IsShown())
end

function ns.Show(tab)
    if not frame then BuildFrame() end
    if tab then ns.db.tab = tab end
    if frame:IsShown() then
        if tab then ns.ShowTab(tab) end
    else
        frame:Show()
    end
end

function ns.IsShown()
    return frame and frame:IsShown()
end

---------------------------------------------------------------------------
-- Launcher button on the Blizzard LFG window (best effort; frame names vary by client)
---------------------------------------------------------------------------
-- The game's top-level Looking for Group windows (the Classic-style one, and the modern one).
-- Some load on demand, so this runs again on every ADDON_LOADED.
local NATIVE_FRAMES = { "LFGParentFrame", "PVEFrame" }
local hooked = {}
ns.nativeFound = {}

local function HideNative(host)
    -- Hide on the next frame: hiding inside the game's own show call can confuse its panel manager.
    host:SetAlpha(0)
    C_Timer.After(0, function()
        if InCombatLockdown() or not HideUIPanel then
            host:Hide()
        else
            HideUIPanel(host)
        end
        host:SetAlpha(1)
    end)
end

local function TryAttachLauncher()
    for _, name in ipairs(NATIVE_FRAMES) do
        local host = _G[name]
        if host and not hooked[name] and host.GetObjectType then
            hooked[name] = true
            ns.nativeFound[#ns.nativeFound + 1] = name
            -- A way back from the game's window to ours.
            local b = RedButton(host, "Seeker", 100, 22)
            b:SetPoint("TOPRIGHT", host, "TOPRIGHT", -30, -2)
            b:SetFrameLevel(host:GetFrameLevel() + 20)
            b:SetScript("OnClick", function()
                HideNative(host)
                if not frame or not frame:IsShown() then ns.Toggle() end
            end)
            host:HookScript("OnShow", function(self)
                if not ns.db or ns.allowNative then return end
                -- Who results for our Who tab: the game pops its own window open to show them
                -- (it does that for every /who that goes to the interface). Keep them in ours.
                if ns.whoUntil and GetTime() < ns.whoUntil then
                    HideNative(self)
                    ns.Show("who")
                    if ns.KeepWhoInUI then C_Timer.After(0.05, ns.KeepWhoInUI) end
                    return
                end
                -- Replace mode: whatever opens the game's window opens (or closes) ours instead.
                if not ns.db.replaceNative or IsShiftKeyDown() then return end
                HideNative(self)
                local nativeTab = self.selectedTab
                if nativeTab == 3 then
                    ns.Show("who") -- /who results the game wanted to show
                elseif ns.IsShown() then
                    frame:Hide()
                else
                    ns.Show()
                end
            end)
        end
    end
end
ns.TryAttachLauncher = TryAttachLauncher

-- Open the game's own window, past replace mode.
function ns.OpenNative()
    TryAttachLauncher()
    local name = ns.nativeFound[1]
    local host = name and _G[name]
    ns.allowNative = true
    if LFGVanilla_ToggleFrame and name == "LFGParentFrame" then
        LFGVanilla_ToggleFrame()
    elseif PVEFrame_ToggleFrame and name == "PVEFrame" then
        PVEFrame_ToggleFrame()
    elseif host then
        if ShowUIPanel then ShowUIPanel(host) else host:Show() end
    else
        ns.Print("Couldn't find the game's Looking for Group window.")
    end
    -- The panel manager may show it a moment later, so let it through briefly.
    C_Timer.After(0.5, function() ns.allowNative = false end)
end

function ns.SetReplaceNative(on)
    ns.db.replaceNative = on and true or false
    TryAttachLauncher()
    if on then
        ns.Print("Seeker now opens in place of the game's Looking for Group window. Hold Shift to get the game's one.")
    else
        ns.Print("The game's Looking for Group window is back to normal.")
    end
end

-- Options menu: the minimap button's right-click and the cog in the window.
function ns.ShowOptionsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Seeker LFG")
        -- The game's own option (a CVar shared with its window).
        root:CreateCheckbox(LFG_LIST_IGNORE_SUGGESTED_LEVEL or "Show all level ranges",
            function() return ns.IgnoringLevelRanges() end,
            function() ns.SetIgnoreLevelRanges(not ns.IgnoringLevelRanges()) end)
        root:CreateCheckbox("Replace the game's Looking for Group window",
            function() return ns.db.replaceNative end,
            function() ns.SetReplaceNative(not ns.db.replaceNative) end)
        if ns.HasWhisperMessenger() then
            root:CreateCheckbox("Whisper with Whisper Messenger",
                function() return ns.db.useWhisperMessenger ~= false end,
                function() ns.db.useWhisperMessenger = ns.db.useWhisperMessenger == false end)
        end
        root:CreateCheckbox("Show minimap button",
            function() return ns.db.minimapButton ~= false end,
            function() ns.SetMinimapButton(ns.db.minimapButton == false) end)
        root:CreateDivider()
        root:CreateButton("Open the game's Looking for Group window", function() ns.OpenNative() end)
        local sort = root:CreateButton("Sort")
        for _, m in ipairs(ns.SORT_MODES) do
            sort:CreateRadio(m.label, function() return ns.db.sortMode == m.key end, function()
                ns.db.sortMode = m.key
                ns.Render()
            end)
        end
        local alerts = root:CreateButton("Alerts")
        local A = ns.db.alerts
        alerts:CreateCheckbox("Tell me about new matches", function() return A.enabled end, function() A.enabled = not A.enabled end)
        alerts:CreateCheckbox("Only ones with full XP", function() return A.fullXPOnly end, function() A.fullXPOnly = not A.fullXPOnly end)
        alerts:CreateCheckbox("Play a sound", function() return A.sound end, function() A.sound = not A.sound end)
        alerts:CreateCheckbox("Flash the game's icon", function() return A.flash end, function() A.flash = not A.flash end)
        root:CreateButton("Messages...", function() ns.ShowMessages() end)
        root:CreateButton("All settings...", function() ns.OpenSettings() end)
        root:CreateButton("Reset window position and size", function() SlashCmdList.SEEKERLFG("reset") end)
    end)
end

---------------------------------------------------------------------------
-- Events / slash
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED",
    "LFG_LIST_UPDATE_SEARCH_RESULTS", "LFG_LIST_SEARCH_FAILED", "PLAYER_LEVEL_UP",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_SHOW_SEARCH", "LFG_LIST_AVAILABILITY_UPDATE",
    "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "CVAR_UPDATE", "REPORT_PLAYER_RESULT" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            ns.InitDB()
            local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
            ns.VERSION = getMeta and getMeta(ADDON, "Version")
        end
        TryAttachLauncher()
    elseif event == "PLAYER_LOGIN" then
        TryAttachLauncher()
        ns.SetupMinimapButton()
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        ns.searching, ns.searchFailed = false, true
        ns.Render()
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        ns.searching, ns.searchFailed = false, false
        ns.CheckNewMatches()
        ns.Render()
    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        -- As the game does: a new listing (or an update you made) plays the queue sound and
        -- switches to browsing your listing's activities. The game's own finder runs that search.
        local createdNew = arg1
        if ns.HasListing() then
            if createdNew or ns.pendingListingUpdate then
                PlaySound(SOUNDKIT.PVP_ENTER_QUEUE)
                ns.db.searchSelf = true
                if ns.IsShown() then ns.ShowTab("browse") ns.RefreshDropdowns() end
            end
        else
            if ns.pendingListingUpdate then PlaySound(SOUNDKIT.LFG_DENIED) end
            ns.db.searchSelf = false
            ns.RefreshDropdowns()
        end
        ns.pendingListingUpdate = false
        ns.UpdateListedState()
        ns.QueueRender()
    elseif event == "LFG_LIST_SHOW_SEARCH" then
        -- The game asking to show a search (from a link, for example): show it in ours.
        local activityIDs, showAllLevels = arg1, arg2
        if showAllLevels then ns.SetIgnoreLevelRanges(true) end
        if type(activityIDs) == "table" and activityIDs[1] then
            local a = ns.GetActivity(activityIDs[1])
            if a then
                ns.db.categoryID, ns.db.searchSelf = a.categoryID, false
                ns.ClearActivitySelection()
                for _, id in ipairs(activityIDs) do
                    local ai = ns.GetActivity(id)
                    if ai and ai.categoryID == a.categoryID then ns.SetActivitySelected(id, true) end
                end
            end
        end
        if ns.db.replaceNative then ns.Show("browse") end
        ns.RefreshDropdowns()
        ns.QueueRender()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "LFG_LIST_AVAILABILITY_UPDATE" then
        ns.UpdateListedState()
        ns.QueueRender()
    elseif event == "CVAR_UPDATE" then
        if arg1 == "disableSuggestedLevelActivityFilter" then
            ns.RefreshDropdowns()
            if ns.RefreshListingPage then ns.RefreshListingPage(true) end
        end
    else
        ns.QueueRender()
    end
end)

SLASH_SEEKERLFG1 = "/seeker"
SLASH_SEEKERLFG2 = "/slfg"
SLASH_SEEKERLFG3 = "/gscope" -- the old name, still works
SlashCmdList.SEEKERLFG = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" then
        ns.DebugDump()
    elseif msg == "minimap" then
        ns.SetMinimapButton(ns.db.minimapButton == false)
    elseif msg == "messages" then
        ns.ShowMessages()
    elseif msg:match("^selftest") or msg:match("^test") then
        ns.SelfTest(msg:match("all") and "all" or nil)
    elseif msg == "settings" or msg == "options" then
        ns.OpenSettings()
    elseif msg == "replace" then
        ns.SetReplaceNative(not ns.db.replaceNative)
    elseif msg == "blizzard" then
        ns.OpenNative()
    elseif msg == "reset" then
        ns.db.pos, ns.db.scale = nil, nil
        if frame then
            frame:SetScale(FitScale())
            frame:ClearAllPoints()
            frame:SetPoint("CENTER")
        end
        ns.Print("Window position and size reset.")
    else
        ns.Toggle()
    end
end

function SeekerLFG_OnAddonCompartmentClick()
    ns.Toggle()
end

-- Keybindings (Bindings.xml). A key press counts as a click, so it can run a search even with the
-- window closed; new matches are announced in chat.
BINDING_NAME_SEEKERLFG_TOGGLE = "Open or close Seeker LFG"
BINDING_NAME_SEEKERLFG_SEARCH = "Search again (announces new matches)"

function SeekerLFG_BindingToggle()
    ns.Toggle()
end

function SeekerLFG_BindingSearch()
    if ns.db and not ns.db.categoryID and not ns.db.searchSelf then
        local cats = ns.GetCategories()
        ns.db.categoryID = cats[1] and cats[1].id
    end
    if ns.DoSearch() then ns.Render() end
end
