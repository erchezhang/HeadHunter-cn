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

-- Two tabs (author, 2026-10-05): General (alerts, HeadHunter Sync, rules) and Display
SettingsPanel.PAGES = {
    { id = "general", label = "SET_TAB_GENERAL" },
    { id = "display", label = "SET_TAB_DISPLAY" },
}

-- kind: "toggle" | "choice" | "number"; path: Database setting path. A section starts a
-- block of its page; the options after it belong to that page
SettingsPanel.OPTIONS = {
    { section = "SET_SECTION_ALERTS", page = "general" },
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
    { key = "duelSpots", kind = "toggle", path = "alerts.duelSpots", label = "SET_DUEL_SPOTS", tip = "SET_DUEL_SPOTS_TIP" },
    { section = "SET_SECTION_SYNC", page = "general" },
    -- HH-132: needs HeadHunter Sync, which uploads and deletes the pictures
    { key = "screenshots", kind = "toggle", path = "screenshots", label = "SET_SCREENSHOTS", tip = "SET_SCREENSHOTS_TIP",
        available = function() return ns.Screenshots.SyncInstalled() end, unavailable = "SET_NEEDS_SYNC" },
    { section = "SET_SECTION_RULES", page = "general" },
    { key = "serial", kind = "number", path = "serialKillerWindowMin", min = 5, max = 15, step = 1,
        label = "SET_SERIAL", tip = "SET_SERIAL_TIP" },
    { section = "SET_SECTION_DISPLAY", page = "display" },
    { key = "mapPins", kind = "toggle", path = "mapPins", label = "SET_MAP", tip = "SET_MAP_TIP" },
    { key = "tooltip", kind = "toggle", path = "tooltip", label = "SET_TOOLTIP", tip = "SET_TOOLTIP_TIP" },
    { key = "organizerMarks", kind = "toggle", path = "organizerMarks", label = "SET_ORGANIZER_MARKS",
        tip = "SET_ORGANIZER_MARKS_TIP" },
    { key = "wantedMarks", kind = "toggle", path = "wantedMarks", label = "SET_WANTED_MARKS", tip = "SET_WANTED_MARKS_TIP" },
    { key = "shameMarks", kind = "toggle", path = "shameMarks", label = "SET_SHAME_MARKS", tip = "SET_SHAME_MARKS_TIP" },
    { key = "minimap", kind = "toggle", path = "minimap.hidden", invert = true, label = "SET_MINIMAP",
        tip = "SET_MINIMAP_TIP" },}

-- The page an option or section is on: its section's page
function SettingsPanel.PageOf(key)
    local page
    for _, option in ipairs(SettingsPanel.OPTIONS) do
        page = option.page or page
        if option.key == key or option.section == key then return page end
    end
    return nil
end

function SettingsPanel.Option(key)
    for _, option in ipairs(SettingsPanel.OPTIONS) do
        if option.key == key then return option end
    end
    return nil
end

-- false when the option needs something this player does not have (option.available)
function SettingsPanel.Available(option)
    return option.available == nil or option.available() == true
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
local host           -- the page the widgets are built on
local pages, tabs = {}, {} -- page id -> frame, page id -> its tab button
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
    local check = CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 20, y)
    local label = Label(host, L[option.label])
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    local note = option.unavailable and Label(host, L[option.unavailable], "GameFontDisableSmall")
    if note then note:SetPoint("LEFT", label, "RIGHT", 8, 0) end
    check:SetScript("OnClick", function(self)
        SettingsPanel.Set(option, self:GetChecked() and true or false)
    end)
    check:SetScript("OnEnter", function(self) ShowTip(self, option) end)
    check:SetScript("OnLeave", HideTip)
    widgets[option.key] = { refresh = function()
        local available = SettingsPanel.Available(option)
        check:SetChecked(available and SettingsPanel.Get(option))
        if available then check:Enable() else check:Disable() end
        label:SetFontObject(available and "GameFontHighlight" or "GameFontDisable")
        if note then note:SetShown(not available) end
    end }
    return y - 28
end

local function AddChoice(option, y)
    local label = Label(host, L[option.label])
    label:SetPoint("TOPLEFT", 26, y - 6)
    local button = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
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
    local label = Label(host, L[option.label])
    label:SetPoint("TOPLEFT", 26, y - 6)
    local minus = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("TOPLEFT", 220, y)
    minus:SetText("-")
    local value = Label(host, "", "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 10, 0)
    value:SetWidth(60)
    local plus = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
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

    -- Text tabs like the game's own Game | AddOns: the chosen one gold and underlined
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, SettingsPanel.TAB_LINE_ALPHA)
    divider:SetPoint("TOPLEFT", 16, -SettingsPanel.TAB_BOTTOM)
    divider:SetPoint("TOPRIGHT", -16, -SettingsPanel.TAB_BOTTOM)
    divider:SetHeight(1)
    local x = 16
    for _, page in ipairs(SettingsPanel.PAGES) do
        local tab = CreateFrame("Button", nil, panel)
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        tab.text:SetPoint("CENTER", 0, 1)
        tab.text:SetText(L[page.label])
        local width = (tab.text:GetStringWidth() or 60) + 2 * SettingsPanel.TAB_PADDING
        tab:SetSize(width, SettingsPanel.TAB_HEIGHT)
        tab:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", x, -SettingsPanel.TAB_BOTTOM)
        x = x + width + SettingsPanel.TAB_GAP
        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        hover:SetColorTexture(1, 1, 1, SettingsPanel.TAB_HOVER_ALPHA)
        hover:SetAllPoints(tab)
        tab.underline = tab:CreateTexture(nil, "OVERLAY")
        tab.underline:SetColorTexture(1, 0.82, 0, 1)
        tab.underline:SetPoint("BOTTOMLEFT", 0, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", 0, 0)
        tab.underline:SetHeight(2)
        tab:SetScript("OnClick", function() SettingsPanel:ShowPage(page.id) end)
        tabs[page.id] = tab
        local frame = CreateFrame("Frame", nil, panel)
        frame:SetPoint("TOPLEFT", 0, -(SettingsPanel.TAB_BOTTOM + 6))
        frame:SetPoint("BOTTOMRIGHT")
        frame:Hide()
        pages[page.id] = frame
    end

    local y = {}
    for _, option in ipairs(SettingsPanel.OPTIONS) do
        if option.section then host = pages[option.page] end
        local top = y[host] or -6
        if option.section then
            local header = Label(host, L[option.section], "GameFontNormal")
            header:SetPoint("TOPLEFT", 16, top - 6)
            y[host] = top - 26
        elseif option.kind == "toggle" then
            y[host] = AddToggle(option, top)
        elseif option.kind == "choice" then
            y[host] = AddChoice(option, top)
        elseif option.kind == "number" then
            y[host] = AddNumber(option, top)
        end
    end
    for _, page in pairs(pages) do
        local hint = Label(page, L.SET_HINT, "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", 16, (y[page] or -6) - 16)
    end
    SettingsPanel:ShowPage(SettingsPanel.page)

    panel:SetScript("OnShow", function() SettingsPanel:Refresh() end)
    -- Old options frames call these
    panel.okay, panel.cancel, panel.default, panel.refresh = function() end, function() end, function() end,
        function() SettingsPanel:Refresh() end
    return panel
end

SettingsPanel.TAB_HEIGHT = 28
SettingsPanel.TAB_BOTTOM = 76     -- the line under the tabs, from the top of the page
SettingsPanel.TAB_PADDING = 12
SettingsPanel.TAB_GAP = 4
SettingsPanel.TAB_HOVER_ALPHA = 0.08
SettingsPanel.TAB_LINE_ALPHA = 0.2
SettingsPanel.page = "general"

-- Show one tab's options; the tab on show is gold and underlined
function SettingsPanel:ShowPage(id)
    self.page = id
    for pageId, frame in pairs(pages) do
        if pageId == id then frame:Show() else frame:Hide() end
        local tab = tabs[pageId]
        if tab then
            tab.text:SetFontObject(pageId == id and "GameFontNormalLarge" or "GameFontHighlightLarge")
            tab.underline:SetShown(pageId == id)
        end
    end
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
