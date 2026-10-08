-- HH-060: minimap buttons. Left-click the head toggles the main window, left-click
-- the gear opens the toolbox; drag either one to move both around the minimap (one
-- angle, kept in settings.minimap); /hh minimap shows or hides both.

local addonName, ns = ...
local L = ns.L

local MinimapButton = ns:RegisterModule("MinimapButton", {})

local OWNER = "MinimapButton"

MinimapButton.ICON = "Interface\\Icons\\INV_Misc_Head_Human_01"
MinimapButton.TOOLBOX_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
MinimapButton.SIZE = 31
MinimapButton.TOOLBOX_GAP = 24 -- degrees between the two buttons on the rim

local button      -- the head: the main window
local toolButton  -- the gear: the toolbox

-- Position on the minimap's edge for an angle in degrees
function MinimapButton.Offset(angle, radius)
    local rad = math.rad(angle)
    return math.cos(rad) * radius, math.sin(rad) * radius
end

local function Settings()
    return ns.db.settings.minimap
end

local function Place()
    local radius = (Minimap:GetWidth() or 140) / 2 + 10
    local x, y = MinimapButton.Offset(Settings().angle, radius)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    if toolButton then
        x, y = MinimapButton.Offset(Settings().angle - MinimapButton.TOOLBOX_GAP, radius)
        toolButton:ClearAllPoints()
        toolButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not (mx and px and scale and scale > 0) then return end
    Settings().angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    Place()
end

-- One rim button: the addon's look, drag both, the hint on hover
local function NewButton(name, icon, onClick, title)
    local b = CreateFrame("Button", name, Minimap)
    b:SetSize(MinimapButton.SIZE, MinimapButton.SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local tex = b:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(icon)
    tex:SetSize(20, 20)
    tex:SetPoint("CENTER", b, "CENTER", 0, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", b, "TOPLEFT")

    b:SetScript("OnClick", onClick)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(L.MINIMAP_HINT, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function Create()
    button = NewButton("HeadHunterMinimapButton", MinimapButton.ICON,
        function() ns.MainWindow:Toggle() end, L.WINDOW_TITLE)
    toolButton = NewButton("HeadHunterToolboxMinimapButton", MinimapButton.TOOLBOX_ICON,
        function() if ns.Toolbox then ns.Toolbox:Toggle() end end, L.TOOLBOX_TITLE)
    Place()
end

function MinimapButton:Apply()
    if not Minimap then return end
    if Settings().hidden then
        if button then button:Hide() end
        if toolButton then toolButton:Hide() end
        return
    end
    if not button then Create() end
    button:Show()
    toolButton:Show()
end

function MinimapButton:IsShown()
    return button ~= nil and button:IsShown()
end

function MinimapButton:IsToolboxShown()
    return toolButton ~= nil and toolButton:IsShown()
end

ns.Events:Register("HH_INITIALIZED", function()
    MinimapButton:Apply()
    -- The options page (and /hh minimap) change it through the database
    ns.Events:Register("HH_SETTING_CHANGED", function(_, path)
        if path == "minimap.hidden" then MinimapButton:Apply() end
    end, OWNER)
end, OWNER)

ns.SlashCommands:Register("minimap", function()
    ns.Database:SetSetting("minimap.hidden", not Settings().hidden)
    ns:Print(Settings().hidden and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end, L.HELP_MINIMAP)
