-- A dropdown select, as in GudaBags (UI/Controls/Select.lua, same author): the modern
-- WowStyle1DropdownTemplate radio menu where the client has it, otherwise the classic
-- UIDropDownMenuTemplate.
--
--   Select.Create(parent, config) -> container
--     config = { width, options = { { value, label }, ... }, get = fn() -> value, set = fn(value) }
--   container:Refresh()        show the current value (after get() changed)
--   container:Choose(value)    pick a value as a click would (set + Refresh)
--   Select.ContextMenu(owner, title, entries)   a menu at the cursor; entries = { { label, func } }

local addonName, ns = ...

local Select = ns:RegisterModule("Select", {})

Select.HEIGHT = 26

local counter = 0

local function LabelOf(options, value)
    for _, opt in ipairs(options) do
        if opt.value == value then return opt.label end
    end
    return ""
end

function Select.Create(parent, config)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(config.width or 160, Select.HEIGHT)
    local options = config.options

    function container:Choose(value)
        config.set(value)
        self:Refresh()
    end

    local modern = _G.DoesTemplateExist and _G.DoesTemplateExist("WowStyle1DropdownTemplate") and _G.MenuUtil
    if modern then
        local dropdown = CreateFrame("DropdownButton", nil, container, "WowStyle1DropdownTemplate")
        dropdown:SetPoint("LEFT", container, "LEFT", 0, 0)
        dropdown:SetWidth(config.width or 160)
        -- Built from the options as they are now: a dialog may fill them after creating it
        -- (UI/ResultDialog.lua), so Refresh builds the menu again
        local function Setup()
            local entries = {}
            for i, opt in ipairs(options) do entries[i] = { opt.label, opt.value } end
            MenuUtil.CreateRadioMenu(dropdown, function(value) return config.get() == value end,
                function(value) config.set(value) end, unpack(entries))
        end
        Setup()
        function container:Refresh()
            Setup()
            dropdown:GenerateMenu()
        end
        container.dropdown = dropdown
        return container
    end

    -- Classic: the old dropdown needs a global name for its parts
    counter = counter + 1
    local dropdown = CreateFrame("Frame", "HeadHunterSelect" .. counter, container, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", container, "LEFT", -16, 0)
    UIDropDownMenu_SetWidth(dropdown, (config.width or 160) - 30)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if (level or 1) ~= 1 then return end
        local current = config.get()
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = opt.label, opt.value
            info.checked = opt.value == current
            info.func = function()
                container:Choose(opt.value)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    function container:Refresh() UIDropDownMenu_SetText(dropdown, LabelOf(options, config.get())) end
    container.dropdown = dropdown
    container:Refresh()
    return container
end

-- A menu at the cursor (right-click menus): the modern MenuUtil context menu where the
-- client has it, otherwise the classic dropdown list. Picking an entry runs its func.
local contextFrame

function Select.ContextMenu(owner, title, entries)
    if _G.MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle(title)
            for _, entry in ipairs(entries) do root:CreateButton(entry.label, entry.func) end
        end)
        return "modern"
    end
    contextFrame = contextFrame or CreateFrame("Frame", "HeadHunterContextMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(contextFrame, function(_, level)
        if (level or 1) ~= 1 then return end
        local header = UIDropDownMenu_CreateInfo()
        header.text, header.isTitle, header.notCheckable = title, true, true
        UIDropDownMenu_AddButton(header, level)
        for _, entry in ipairs(entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable = entry.label, true
            info.func = function()
                CloseDropDownMenus()
                entry.func()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, contextFrame, "cursor", 0, 0)
    return "classic"
end
