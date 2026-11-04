-- HH-155: a Gang tab in the game's Social window (FriendsFrame), after Friends, Who, Guild
-- and Raid, showing our gang with Invite and Leave. Built so it taints nothing: our own
-- tab button sits after the last Blizzard tab, and Blizzard's tab count and selection
-- (PanelTemplates_SetNumTabs, FriendsFrame.numTabs, selectedTab) are never written. A
-- click on our tab lays our panel over the window's content; a click on any Blizzard
-- tab, or closing the window, hides it again through post-hooks that change nothing of
-- Blizzard's. Off by default until the taint probe on both clients is clean:
-- /hh gang socialtab on|off (setting gangSocialTab), then /reload.

local addonName, ns = ...
local L = ns.L

local SocialTab = ns:RegisterModule("SocialTab", {})

local OWNER = "SocialTab"

SocialTab.MAX_BLIZZARD_TABS = 8
SocialTab.ROWS = 10

local tab, panel

-- The Social window's own tab buttons, in order
function SocialTab.BlizzardTabs()
    local tabs = {}
    for i = 1, SocialTab.MAX_BLIZZARD_TABS do
        local button = _G["FriendsFrameTab" .. i]
        if not button then break end
        tabs[#tabs + 1] = button
    end
    return tabs
end

-- The last Blizzard tab on show, and the gap the game itself leaves between two tabs
-- (Classic overlaps them by 15, newer UIs space them), read from the second tab's anchor
function SocialTab.Anchor(tabs)
    local last
    for _, button in ipairs(tabs) do
        if not button.IsShown or button:IsShown() then last = button end
    end
    local gap = -15
    local second = tabs[2]
    if second and second.GetPoint then
        local ok, _, relative, _, x = pcall(second.GetPoint, second, 1)
        if ok and relative == tabs[1] and type(x) == "number" then gap = x end
    end
    return last, gap
end

function SocialTab:Enabled()
    return ns.db ~= nil and ns.db.settings.gangSocialTab == true and ns.Gangs.Enabled()
end

function SocialTab:Refresh()
    if not panel or not panel:IsShown() then return end
    local gang = ns.Gangs:Mine()
    local U = ns.Utils
    if gang then
        panel.title:SetText(string.format(gang.pending and L.GANG_HEADER_PENDING or L.GANG_HEADER, gang.name))
    else
        panel.title:SetText(L.GANG_HEADER_NONE)
    end
    for i = 1, SocialTab.ROWS do
        local member = gang and gang.members[i]
        local line = panel.lines[i]
        if member then
            local leads = U.SameCharacter(member.key, gang.leader)
            line:SetText(U.DisplayName(member.key) .. "  |cffaaaaaa" .. (leads and L.GANG_ROLE_LEADER or L.GANG_ROLE_MEMBER) .. "|r")
        else
            line:SetText(i == 1 and not gang and L.EMPTY_GANG or "")
        end
    end
    if gang and ns.Gangs:IsLeader(gang) then panel.invite:Show() else panel.invite:Hide() end
    if gang then panel.leave:Show() else panel.leave:Hide() end
end

function SocialTab:ShowPanel()
    if not panel then return end
    panel:Show()
    self:Refresh()
end

function SocialTab:HidePanel()
    if panel then panel:Hide() end
end

local function CreatePanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -60)
    p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 30)
    p:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.05, 0.04, 0.03, 0.97)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 10, -10)
    p.title:SetPoint("RIGHT", -10, 0)
    p.title:SetJustifyH("LEFT")
    p.lines = {}
    for i = 1, SocialTab.ROWS do
        local line = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 18)
        line:SetPoint("RIGHT", -10, 0)
        line:SetJustifyH("LEFT")
        p.lines[i] = line
    end
    p.invite = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.invite:SetSize(120, 22)
    p.invite:SetPoint("BOTTOMLEFT", 10, 10)
    p.invite:SetText(L.GANG_INVITE_BUTTON)
    p.invite:SetScript("OnClick", function() ns.Gangs:Command({ "invite" }) end)
    p.leave = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.leave:SetSize(90, 22)
    p.leave:SetPoint("BOTTOMRIGHT", -10, 10)
    p.leave:SetText(L.GANG_LEAVE_BUTTON)
    p.leave:SetScript("OnClick", function() ns.Gangs:Command({ "leave" }) end)
    p:Hide()
    return p
end

-- Returns true when the tab was added
function SocialTab:Install()
    local frame = _G.FriendsFrame
    if tab or not frame or not self:Enabled() then return false end
    local blizzard = self.BlizzardTabs()
    local last, gap = self.Anchor(blizzard)
    if not last then return false end
    local ok, button = pcall(CreateFrame, "Button", "HeadHunterSocialGangTab", frame, "FriendsFrameTabTemplate")
    if not ok or not button then button = CreateFrame("Button", "HeadHunterSocialGangTab", frame, "UIPanelButtonTemplate") end
    button:SetPoint("LEFT", last, "RIGHT", gap, 0)
    button:SetText(L.TAB_GANG)
    button:SetScript("OnClick", function() SocialTab:ShowPanel() end)
    tab = button
    panel = CreatePanel(frame)
    for _, blizzardTab in ipairs(blizzard) do
        if blizzardTab.HookScript then
            blizzardTab:HookScript("OnClick", function() SocialTab:HidePanel() end)
        end
    end
    if frame.HookScript then frame:HookScript("OnHide", function() SocialTab:HidePanel() end) end
    return true
end

-- For tests
function SocialTab:Parts()
    return tab, panel
end

ns.Events:Register("HH_INITIALIZED", function()
    SocialTab:Install()
    ns.Events:Register("HH_GANG_CHANGED", function() SocialTab:Refresh() end, OWNER)
end, OWNER)
