-- The toolbox (author, 2026-10-07): the website's macro command table
-- (headhunterwow.com/about) as clickable buttons, with the layer (phase) ID on top.
-- IDs only mean something inside one zone, so the zone is shown next to it.
--
--   /hh toolbox, /hh tool, /hh t open the window (registered at the bottom)
--   /hht (top level) opens it too; with arguments it runs them as /hh <args>
--   Each button shows its short description right under it (Toolbox.Desc); the
--   tooltip still shows the full help line on hover.
--   Toolbox.LayerLines()  the card's texts (pure, tested offline)
--   Toolbox:RunCommand(c) what a button does: the same as typing /hh c
--
-- The layer comes from Detection/Layer.lua (read from nearby NPC GUIDs). The card
-- updates when HH_LAYER_CHANGED fires or the Refresh button rescans.

local addonName, ns = ...
local L = ns.L

local Toolbox = ns:RegisterModule("Toolbox", {})

local OWNER = "Toolbox"

Toolbox.WIDTH = 440
Toolbox.HEIGHT = 690

-- The commands of the website's table, in its order. Labels differ where the command
-- takes arguments; the buttons run the bare command (a usage line explains the rest).
local LABELS = {
    show = "/hh",
    outlaw = "/hh outlaw <name>",
    map = "/hh map on/off",
    tooltip = "/hh tooltip on/off",
}
Toolbox.COMMANDS = {
    "show", "help", "options", "wanted", "outlaw", "deaths", "posse", "bounty",
    "hotspots", "duels", "duelspots", "map", "tooltip", "minimap",
    "claim", "catchup", "online", "layer",
}

function Toolbox.Label(cmd)
    return LABELS[cmd] or ("/hh " .. cmd)
end

-- The short description under a button: its help line without the command part
-- ("|c…/hh wanted|r: Current WANTED list" -> "Current WANTED list"). Pure, tested.
function Toolbox.Desc(cmd)
    local help = ns.SlashCommands:Help(cmd)
    if not help then return "" end
    local desc = help:match("|r:%s*(.+)$") or help
    return (desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The layer card's texts: the big ID, the line under it and the zone name (pure).
function Toolbox.LayerLines()
    local layer, zone, age = ns.Layer:Status()
    if not layer then return "?", L.LAYER_UNKNOWN, "" end
    local name = zone and ns.Utils.MapName(zone)
    return tostring(layer), string.format(L.LAYER_CURRENT, layer, age), name or ""
end

function Toolbox:RunCommand(cmd)
    ns.SlashCommands:Run(cmd)
end

local frame
local CreateToolboxFrame -- forward declaration, defined below

function Toolbox:Frame()
    return frame
end

function Toolbox:IsShown()
    return frame ~= nil and frame:IsShown()
end

local function Update()
    if not frame then return end
    local value, info, zone = Toolbox.LayerLines()
    frame.layerValue:SetText(value)
    frame.layerInfo:SetText(info)
    frame.layerZone:SetText(zone)
end

-- Refresh button: scan the nearby NPCs again, then repaint
function Toolbox:Refresh()
    ns.Layer:Scan()
    Update()
end

function Toolbox:Toggle()
    frame = frame or CreateToolboxFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:Refresh()
    end
end

-- Assigns the forward declaration above; a new `local` here would shadow it
CreateToolboxFrame = function()
    local f = CreateFrame("Frame", "HeadHunterToolboxFrame", UIParent)
    f:SetSize(Toolbox.WIDTH, Toolbox.HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "HeadHunterToolboxFrame")

    local Theme = ns.Theme
    Theme.StyleFrame(f, L.TOOLBOX_TITLE)
    Theme.ResizeGrip(f)

    -- Layer card: the ID big on the left, how old the reading is and where it was
    local card = Theme.Card(f)
    card:SetPoint("TOPLEFT", 16, -(Theme.HEADER_HEIGHT + 12))
    card:SetPoint("TOPRIGHT", -16, -(Theme.HEADER_HEIGHT + 12))
    card:SetHeight(92)

    local label = Theme.Text(card, "bold", 12, "gold")
    label:SetPoint("TOPLEFT", 12, -10)
    label:SetText(L.TOOLBOX_SECTION_LAYER)

    f.refresh = Theme.Button(card, L.TOOLBOX_REFRESH, "outline", 90, 24)
    f.refresh:SetPoint("TOPRIGHT", -10, -8)
    f.refresh:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.TOOLBOX_REFRESH_TIP)
        GameTooltip:Show()
    end)
    f.refresh:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.refresh:SetScript("OnClick", function() Toolbox:Refresh() end)

    f.layerValue = Theme.Text(card, "heading", 30, "gold")
    f.layerValue:SetPoint("TOPLEFT", 12, -34)

    f.layerInfo = Theme.Text(card, "text", 13, "foreground")
    f.layerInfo:SetPoint("TOPLEFT", 110, -46)
    f.layerInfo:SetJustifyH("LEFT")

    f.layerZone = Theme.Text(card, "text", 12, "muted")
    f.layerZone:SetPoint("TOPLEFT", 110, -68)
    f.layerZone:SetJustifyH("LEFT")

    -- The website's command table as buttons: two columns, the description of
    -- each command right under its button (the full help line on hover)
    local heading = Theme.Text(f, "bold", 13, "gold")
    heading:SetPoint("TOPLEFT", 18, -(Theme.HEADER_HEIGHT + 12 + 92 + 16))
    heading:SetText(L.TOOLBOX_SECTION_COMMANDS)

    f.buttons = {}
    f.descs = {}
    local startY = Theme.HEADER_HEIGHT + 12 + 92 + 44
    local colWidth, gap, rowHeight = 198, 8, 54
    for i, cmd in ipairs(Toolbox.COMMANDS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local button = Theme.Button(f, Toolbox.Label(cmd), "outline", colWidth, 26)
        button:SetPoint("TOPLEFT", 18 + col * (colWidth + gap), -(startY + row * rowHeight))
        local help = ns.SlashCommands:Help(cmd)
        button:SetScript("OnEnter", function(self)
            if not GameTooltip or not help then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(help)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        button:SetScript("OnClick", function() Toolbox:RunCommand(cmd) end)
        f.buttons[cmd] = button
        -- The description right under the button: small, muted, up to two lines
        local desc = Theme.Text(f, "text", 10, "muted")
        desc:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -28)
        desc:SetWidth(colWidth - 4)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetMaxLines(2)
        desc:SetText(Toolbox.Desc(cmd))
        f.descs[cmd] = desc
    end

    return f
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("HH_LAYER_CHANGED", function() Update() end, OWNER)
end, OWNER)

ns.SlashCommands:Register("toolbox", function() Toolbox:Toggle() end, L.HELP_TOOLBOX)
-- Aliases of the same window (all stay: /hh toolbox, /hh tool, /hh t)
ns.SlashCommands:Register("t", function() Toolbox:Toggle() end, L.HELP_TOOLBOX_SHORT)
ns.SlashCommands:Register("tool", function() Toolbox:Toggle() end)

-- Top level: /hht opens the toolbox; with arguments it runs them like /hh <args>
SLASH_HEADHUNTER_TOOLBOX1 = "/hht"
SlashCmdList.HEADHUNTER_TOOLBOX = function(input)
    if type(input) == "string" and input:match("%S") then
        ns.SlashCommands:Run(input)
    else
        Toolbox:Toggle()
    end
end
