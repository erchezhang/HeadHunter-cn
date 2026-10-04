-- HH-063: HeadHunter's page in the game options (Esc > Options > AddOns), instead of
-- /hh commands. /hh options (or the Options button in the main window) opens it.
--
-- The page is our own frame with plain widgets (checkboxes, a choice button, -/+
-- buttons) so it looks and works the same on both clients; only its registration
-- differs: the Settings API canvas category where it exists (as GudaBags does), else
-- the older InterfaceOptions panel list.
--
-- SettingsPanel.OPTIONS with Get/Set is the pure part (tested offline). Every change
-- goes through Database:SetSetting, so the modules that listen to
-- HH_SETTING_CHANGED react at once (map pins, WANTED recompute, ...).

local addonName, ns = ...
local L = ns.L

local SettingsPanel = ns:RegisterModule("SettingsPanel", {})

local OWNER = "SettingsPanel"

-- kind: "toggle" | "choice" | "number"; path: Database setting path
SettingsPanel.OPTIONS = {
    { section = "SET_SECTION_ALERTS" },
    { key = "alerts", kind = "toggle", path = "alerts.enabled", label = "SET_ALERTS", tip = "SET_ALERTS_TIP" },
    { key = "sound", kind = "toggle", path = "alerts.sound", label = "SET_SOUND", tip = "SET_SOUND_TIP" },
    { key = "popups", kind = "toggle", path = "alerts.popups", label = "SET_POPUPS", tip = "SET_POPUPS_TIP" },
    { key = "range", kind = "choice", path = "alerts.range", label = "SET_RANGE", tip = "SET_RANGE_TIP",
        choices = { "adjacent", "continent" } },
    { key = "whisper", kind = "toggle", path = "alerts.whisperInvite", label = "SET_WHISPER", tip = "SET_WHISPER_TIP" },
    { key = "shame", kind = "toggle", path = "alerts.shame", label = "SET_SHAME", tip = "SET_SHAME_TIP" },
    { key = "glassPopup", kind = "toggle", path = "alerts.glassPopup", label = "SET_GLASS_POPUP", tip = "SET_GLASS_POPUP_TIP" },
    { key = "glassGap", kind = "number", path = "alerts.glassPopupGap", min = 3, max = 15, step = 1, format = "SET_MINUTES",
        label = "SET_GLASS_GAP", tip = "SET_GLASS_GAP_TIP" },
    { key = "glassThanks", kind = "toggle", path = "alerts.glassThanks", label = "SET_GLASS_THANKS", tip = "SET_GLASS_THANKS_TIP" },
    { section = "SET_SECTION_DISPLAY" },
    { key = "mapPins", kind = "toggle", path = "mapPins", label = "SET_MAP", tip = "SET_MAP_TIP" },
    { key = "tooltip", kind = "toggle", path = "tooltip", label = "SET_TOOLTIP", tip = "SET_TOOLTIP_TIP" },
    { key = "organizerMarks", kind = "toggle", path = "organizerMarks", label = "SET_ORGANIZER_MARKS",
        tip = "SET_ORGANIZER_MARKS_TIP" },
    { key = "wantedMarks", kind = "toggle", path = "wantedMarks", label = "SET_WANTED_MARKS", tip = "SET_WANTED_MARKS_TIP" },
    { key = "shameMarks", kind = "toggle", path = "shameMarks", label = "SET_SHAME_MARKS", tip = "SET_SHAME_MARKS_TIP" },
    { key = "minimap", kind = "toggle", path = "minimap.hidden", invert = true, label = "SET_MINIMAP",
        tip = "SET_MINIMAP_TIP" },
    -- HH-125: the HeadHunter windows (UI/Theme.lua), in %
    { key = "scale", kind = "number", path = "uiScale", min = 90, max = 130, step = 10, format = "SET_PERCENT",
        label = "SET_SCALE", tip = "SET_SCALE_TIP" },
    { section = "SET_SECTION_RULES" },
    { key = "serial", kind = "number", path = "serialKillerWindowMin", min = 5, max = 15, step = 1,
        label = "SET_SERIAL", tip = "SET_SERIAL_TIP" },
}

function SettingsPanel.Option(key)
    for _, option in ipairs(SettingsPanel.OPTIONS) do
        if option.key == key then return option end
    end
    return nil
end

function SettingsPanel.Get(option)
    local value = ns.Database:GetSetting(option.path)
    if option.invert then return not value end
    if option.kind == "toggle" then return value ~= false end
    return value
end

function SettingsPanel.Set(option, value)
    if option.kind == "number" then
        value = math.max(option.min, math.min(option.max, math.floor(tonumber(value) or option.min)))
    elseif option.kind == "choice" then
        local valid = false
        for _, choice in ipairs(option.choices) do valid = valid or choice == value end
        if not valid then return false end
    elseif option.invert then
        value = not value
    end
    ns.Database:SetSetting(option.path, value)
    return true
end

-- A choice option's next value (the button cycles)
function SettingsPanel.NextChoice(option)
    local current = SettingsPanel.Get(option)
    for i, choice in ipairs(option.choices) do
        if choice == current then return option.choices[i % #option.choices + 1] end
    end
    return option.choices[1]
end

-------------------------------------------------
-- Page
-------------------------------------------------

local panel
local widgets = {}   -- key -> { refresh = function() }

local function ShowTip(owner, option)
    if not (GameTooltip and option.tip) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L[option.label])
    GameTooltip:AddLine(L[option.tip], 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideTip()
    if GameTooltip then GameTooltip:Hide() end
end

local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

local function AddToggle(option, y)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 20, y)
    local label = Label(panel, L[option.label])
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check:SetScript("OnClick", function(self)
        SettingsPanel.Set(option, self:GetChecked() and true or false)
    end)
    check:SetScript("OnEnter", function(self) ShowTip(self, option) end)
    check:SetScript("OnLeave", HideTip)
    widgets[option.key] = { refresh = function() check:SetChecked(SettingsPanel.Get(option)) end }
    return y - 28
end

local function AddChoice(option, y)
    local label = Label(panel, L[option.label])
    label:SetPoint("TOPLEFT", 26, y - 6)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(200, 22)
    button:SetPoint("TOPLEFT", 220, y)
    button:SetScript("OnClick", function()
        SettingsPanel.Set(option, SettingsPanel.NextChoice(option))
        widgets[option.key].refresh()
    end)
    button:SetScript("OnEnter", function(self) ShowTip(self, option) end)
    button:SetScript("OnLeave", HideTip)
    widgets[option.key] = { refresh = function()
        button:SetText(L["SET_CHOICE_" .. tostring(SettingsPanel.Get(option)):upper()])
    end }
    return y - 30
end

local function AddNumber(option, y)
    local label = Label(panel, L[option.label])
    label:SetPoint("TOPLEFT", 26, y - 6)
    local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("TOPLEFT", 220, y)
    minus:SetText("-")
    local value = Label(panel, "", "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 10, 0)
    value:SetWidth(60)
    local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("LEFT", value, "RIGHT", 10, 0)
    plus:SetText("+")
    local function Step(delta)
        SettingsPanel.Set(option, (SettingsPanel.Get(option) or option.min) + delta)
        widgets[option.key].refresh()
    end
    minus:SetScript("OnClick", function() Step(-option.step) end)
    plus:SetScript("OnClick", function() Step(option.step) end)
    for _, b in ipairs({ minus, plus }) do
        b:SetScript("OnEnter", function(self) ShowTip(self, option) end)
        b:SetScript("OnLeave", HideTip)
    end
    widgets[option.key] = { refresh = function()
        value:SetText(string.format(L[option.format or "SET_MINUTES"], SettingsPanel.Get(option) or option.min))
    end }
    return y - 30
end

local function CreatePanel()
    panel = CreateFrame("Frame", "HeadHunterSettingsPanel", UIParent)
    panel.name = L.WINDOW_TITLE
    panel:Hide()
    local title = Label(panel, L.WINDOW_TITLE, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local version = Label(panel, "v" .. tostring(ns.version), "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local y = -50
    for _, option in ipairs(SettingsPanel.OPTIONS) do
        if option.section then
            local header = Label(panel, L[option.section], "GameFontNormal")
            header:SetPoint("TOPLEFT", 16, y - 6)
            y = y - 26
        elseif option.kind == "toggle" then
            y = AddToggle(option, y)
        elseif option.kind == "choice" then
            y = AddChoice(option, y)
        elseif option.kind == "number" then
            y = AddNumber(option, y)
        end
    end
    local hint = Label(panel, L.SET_HINT, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, y - 16)

    panel:SetScript("OnShow", function() SettingsPanel:Refresh() end)
    -- Old options frames call these
    panel.okay, panel.cancel, panel.default, panel.refresh = function() end, function() end, function() end,
        function() SettingsPanel:Refresh() end
    return panel
end

function SettingsPanel:Refresh()
    for _, widget in pairs(widgets) do widget.refresh() end
end

-- Returns "settings", "interface" or nil
function SettingsPanel:Register()
    panel = panel or CreatePanel()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, L.WINDOW_TITLE)
        if ok and category then
            pcall(Settings.RegisterAddOnCategory, category)
            self.category = category
            return "settings"
        end
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        return "interface"
    end
    return nil
end

function SettingsPanel:Open()
    if self.registered == "settings" and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category.ID
        pcall(Settings.OpenToCategory, id)
        return true
    end
    if self.registered == "interface" and InterfaceOptionsFrame_OpenToCategory then
        -- The old frame needs the call twice the first time it opens
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
        return true
    end
    return false
end

-- Keep the page in step with /hh commands while it is open
ns.Events:Register("HH_INITIALIZED", function()
    SettingsPanel.registered = SettingsPanel:Register()
    ns:Debug("Settings page:", tostring(SettingsPanel.registered))
    ns.Events:Register("HH_SETTING_CHANGED", function()
        if panel and panel:IsShown() then SettingsPanel:Refresh() end
    end, OWNER)
end, OWNER)

ns.SlashCommands:Register("options", function()
    if not SettingsPanel:Open() then ns:Print(L.SET_UNAVAILABLE) end
end, L.HELP_OPTIONS)
