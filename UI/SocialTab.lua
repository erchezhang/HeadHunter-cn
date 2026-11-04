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
SocialTab.STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }

local tab, panel

-- The Social window's own tab buttons, in order; numbers may be skipped (WoW Forever has
-- 1 Contacts, 3 Raid, 4 Quick Join and no 2)
function SocialTab.BlizzardTabs()
    local tabs = {}
    for i = 1, SocialTab.MAX_BLIZZARD_TABS do
        local button = _G["FriendsFrameTab" .. i]
        if button then tabs[#tabs + 1] = button end
    end
    return tabs
end

-- The last Blizzard tab on show, and the gap the game itself leaves between two tabs
-- (Classic overlaps them by 15, WoW Forever spaces them by 3), read from the first tab
-- anchored to another tab
function SocialTab.Anchor(tabs)
    local last
    local isTab = {}
    for _, button in ipairs(tabs) do
        isTab[button] = true
        if not button.IsShown or button:IsShown() then last = button end
    end
    local gap = -15
    for _, button in ipairs(tabs) do
        if button.GetPoint then
            local ok, _, relative, _, x = pcall(button.GetPoint, button, 1)
            if ok and isTab[relative] and type(x) == "number" then
                gap = x
                break
            end
        end
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

-- One strata above the Social window, so its pages' buttons (Convert to Raid, Raid Info)
-- stay under our panel
function SocialTab.StrataAbove(frame)
    local current = frame.GetFrameStrata and frame:GetFrameStrata() or "MEDIUM"
    for i, strata in ipairs(SocialTab.STRATA) do
        if strata == current then return SocialTab.STRATA[math.min(i + 1, #SocialTab.STRATA - 1)] end
    end
    return "HIGH"
end

-- How the tabs look only: ours selected and Blizzard's selected one not, or back. The
-- window's selectedTab is read, never written.
local function LookSelected(ours)
    local frame = _G.FriendsFrame
    local selected = frame and frame.selectedTab
    local blizzard = type(selected) == "number" and _G["FriendsFrameTab" .. selected] or nil
    if ours then
        if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
        if blizzard and PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, blizzard) end
    else
        if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
        if blizzard and PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, blizzard) end
    end
end

-- The Social window redraws its tabs on its own (roster and friend updates); while our
-- panel is open, our look is laid over it again, after Blizzard's code ran
local function OnTabsRedrawn(frame)
    if frame == _G.FriendsFrame and panel and panel:IsShown() then LookSelected(true) end
end
SocialTab.OnTabsRedrawn = OnTabsRedrawn

function SocialTab:ShowPanel()
    if not panel then return end
    panel:SetFrameStrata(self.StrataAbove(_G.FriendsFrame))
    panel:Show()
    LookSelected(true)
    self:Refresh()
end

function SocialTab:HidePanel()
    if panel and panel:IsShown() then
        panel:Hide()
        LookSelected(false)
    end
end

local function CreatePanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -60)
    p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 30)
    p:SetFrameStrata(SocialTab.StrataAbove(parent))
    p:SetToplevel(true)
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.05, 0.04, 0.03, 1)
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
    button:SetPoint("TOPLEFT", last, "TOPRIGHT", gap, 0)
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
    if hooksecurefunc then
        for _, name in ipairs({ "PanelTemplates_UpdateTabs", "PanelTemplates_SetTab" }) do
            if _G[name] then hooksecurefunc(name, OnTabsRedrawn) end
        end
    end
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
