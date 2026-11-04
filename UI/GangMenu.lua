-- HH-155: the right-click menu on a gang member (the Social window's Gang page and the
-- HeadHunter window's Gang view): Whisper and Invite to group for anyone; Make leader and
-- Kick (asked first) for the gang's leader. A frame of our own, never Blizzard's player
-- menu, so it taints nothing.

local addonName, ns = ...
local L = ns.L

local GangMenu = ns:RegisterModule("GangMenu", {})

GangMenu.KICK_POPUP = "HEADHUNTER_GANG_KICK"
GangMenu.ITEM_HEIGHT = 20
GangMenu.WIDTH = 160

local menu

-- The items for one member: { label, run } in order
function GangMenu.Items(key)
    local U = ns.Utils
    local items = {}
    if not key or U.SameCharacter(key, U.UnitKey("player")) then return items end
    items[#items + 1] = { label = L.GANG_MENU_WHISPER, run = function() U.OpenWhisper(key) end }
    items[#items + 1] = { label = L.GANG_MENU_INVITE, run = function() GangMenu.InviteToGroup(key) end }
    local gang = ns.Gangs:Mine()
    if gang and ns.Gangs:IsLeader(gang) then
        items[#items + 1] = { label = L.GANG_MENU_LEAD, run = function() ns.Gangs:Command({ "lead", U.DisplayName(key) }) end }
        items[#items + 1] = { label = L.GANG_MENU_KICK, run = function() GangMenu.AskKick(key) end }
    end
    return items
end

function GangMenu.InviteToGroup(key)
    local name = ns.Utils.DisplayName(key)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        pcall(C_PartyInfo.InviteUnit, name)
    elseif InviteUnit then
        pcall(InviteUnit, name)
    end
end

function GangMenu.AskKick(key)
    StaticPopupDialogs[GangMenu.KICK_POPUP].text = string.format(L.GANG_KICK_POPUP, ns.Utils.DisplayName(key))
    StaticPopupDialogs[GangMenu.KICK_POPUP].OnAccept = function()
        ns.Gangs:Command({ "kick", ns.Utils.DisplayName(key) })
    end
    StaticPopup_Show(GangMenu.KICK_POPUP)
end

local function CreateMenu()
    local m = CreateFrame("Frame", "HeadHunterGangMenu", UIParent)
    m:SetFrameStrata("DIALOG")
    m:SetWidth(GangMenu.WIDTH)
    m:EnableMouse(true)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(m)
    bg:SetColorTexture(0.06, 0.05, 0.04, 0.96)
    m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.title:SetPoint("TOPLEFT", 10, -8)
    m.title:SetPoint("RIGHT", -10, 0)
    m.title:SetJustifyH("LEFT")
    m.buttons = {}
    m:Hide()
    tinsert(UISpecialFrames, "HeadHunterGangMenu")
    return m
end

local function Button(i)
    local button = menu.buttons[i]
    if button then return button end
    button = CreateFrame("Button", nil, menu)
    button:SetHeight(GangMenu.ITEM_HEIGHT)
    button:SetPoint("TOPLEFT", 6, -28 - (i - 1) * GangMenu.ITEM_HEIGHT)
    button:SetPoint("RIGHT", -6, 0)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", 6, 0)
    button:SetFontString(text)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(button)
    hover:SetColorTexture(1, 0.82, 0, 0.15)
    menu.buttons[i] = button
    return button
end

-- Opens the menu for a member at the cursor; returns its items (none for ourselves)
function GangMenu:Open(key)
    local items = self.Items(key)
    if #items == 0 then return items end
    menu = menu or CreateMenu()
    menu.title:SetText(ns.Utils.DisplayName(key))
    for i, item in ipairs(items) do
        local button = Button(i)
        button:SetText(item.label)
        button:SetScript("OnClick", function()
            menu:Hide()
            item.run()
        end)
        button:Show()
    end
    for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetHeight(36 + #items * GangMenu.ITEM_HEIGHT)
    menu:ClearAllPoints()
    local x, y = GetCursorPosition and GetCursorPosition()
    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if x and y then
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    else
        menu:SetPoint("CENTER")
    end
    menu:Show()
    return items
end

function GangMenu:Close()
    if menu then menu:Hide() end
end

ns.Events:Register("HH_INITIALIZED", function()
    StaticPopupDialogs[GangMenu.KICK_POPUP] = {
        text = "",
        button1 = L.GANG_MENU_KICK,
        button2 = CANCEL,
        timeout = 0,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end, "GangMenu")
