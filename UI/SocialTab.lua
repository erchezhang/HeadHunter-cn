-- HH-155: a Gang tab in the game's Social window (FriendsFrame) on WoW Forever, after
-- Contacts and Raid, showing our gang with Invite and Leave.
--
-- Taint rules, from Blizzard's WoW Forever code (Blizzard_FriendsFrame/Camelot): the
-- Social, Raid and Friends keybinds read FriendsFrame.selectedTab before Show/HideUIPanel,
-- which are refused in combat once addon code wrote it, and RaidFrame holds secure group
-- buttons. So:
--   * our tab lives in a holder frame of our own, never in FriendsFrame.Tabs; the window's
--     selectedTab, numTabs and Tabs are never written and PanelTemplates_SetTab /
--     SetNumTabs / UpdateTabs are never called on it;
--   * opening our page: our tab looks selected and every Blizzard tab not (textures only),
--     Blizzard's unprotected pages are hidden, RaidFrame only out of combat (in combat our
--     opaque page covers it);
--   * post-hooks only (hooksecurefunc): FriendsFrame_OnShow (every Blizzard tab click and
--     every opening) closes our page, as Blizzard has just put its own back;
--     FriendsFrame_Update (the window's own refreshes) hides its pages again while ours is
--     open.
-- Blizzard's tab numbers are not their button names: Raid is FriendsFrameTab3 with id 2,
-- and there is no FriendsFrameTab2. Off by default: /hh gang socialtab on|off, then /reload.

local addonName, ns = ...
local L = ns.L

local SocialTab = ns:RegisterModule("SocialTab", {})

local OWNER = "SocialTab"

SocialTab.MAX_BLIZZARD_TABS = 8
SocialTab.ROWS = 10
SocialTab.TAB_GAP = 3
-- Blizzard's pages hidden while ours is open (RaidFrame apart: protected in combat)
SocialTab.PAGES = { "FriendsTabHeader", "FriendsListFrame", "QuickJoinFrame", "RecentAlliesFrame", "RecruitAFriendFrame" }

local holder, tab, panel
local active = false
-- Blizzard's pages we hid on opening ours (`atOpen`) and the ones its own refreshes showed
-- while ours was open (`later`), and its selected tab at opening. A click on that same tab
-- redraws nothing, so both come back from us; a click on another tab shows its page during
-- the click, which our refresh hook hid again, so `later` comes back.
local hidden = { atOpen = {}, later = {} }
local selectedAtOpen

-- The Social window's own tab buttons, in order; numbers may be skipped
function SocialTab.BlizzardTabs()
    local tabs = {}
    for i = 1, SocialTab.MAX_BLIZZARD_TABS do
        local button = _G["FriendsFrameTab" .. i]
        if button then tabs[#tabs + 1] = button end
    end
    return tabs
end

-- The last Blizzard tab on show
function SocialTab.LastShownTab()
    local last
    for _, button in ipairs(SocialTab.BlizzardTabs()) do
        if not button.IsShown or button:IsShown() then last = button end
    end
    return last
end

function SocialTab:Enabled()
    return ns.db ~= nil and ns.db.settings.gangSocialTab == true and ns.Gangs.Enabled()
end

function SocialTab:IsActive()
    return active
end

function SocialTab:Refresh()
    if not panel or not active then return end
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
    if panel.invite.SetEnabled then panel.invite:SetEnabled(gang and gang.confirmed == true or false) end
    if gang then panel.leave:Show() else panel.leave:Hide() end
    if gang then panel.create:Hide() else panel.create:Show() end
end

-- Blizzard's pages out of sight while ours is open; RaidFrame only out of combat
local function HidePage(page, list)
    if page and page.IsShown and page:IsShown() then
        page:Hide()
        list[#list + 1] = page
    end
end

local function HideBlizzardPages(list)
    for _, name in ipairs(SocialTab.PAGES) do HidePage(_G[name], list) end
    local raid = _G.RaidFrame
    local inCombat = InCombatLockdown and InCombatLockdown()
    if raid and not inCombat and raid.GetParent and raid:GetParent() == _G.FriendsFrame then HidePage(raid, list) end
end

-- Pages we hid, back on show; RaidFrame only out of combat
local function ShowPages(list)
    local inCombat = InCombatLockdown and InCombatLockdown()
    for _, page in ipairs(list) do
        if not (inCombat and page == _G.RaidFrame) then page:Show() end
    end
end

-- The window's title text, as a font string
local function TitleText()
    local frame = _G.FriendsFrame
    if frame and frame.GetTitleText then
        local ok, text = pcall(frame.GetTitleText, frame)
        if ok and text then return text end
    end
    return _G.FriendsFrameTitleText
end

-- The window's title says Gang while our page is open; Blizzard's title is kept to put
-- back when its page comes back from us (its own page code sets it when it shows)
local blizzardTitle
local function ShowOurTitle()
    local text = TitleText()
    if not (text and text.SetText) then return end
    local current = text.GetText and text:GetText()
    if current ~= L.TAB_GANG then blizzardTitle = current end
    text:SetText(L.TAB_GANG)
end

local function ShowBlizzardTitle()
    local text = TitleText()
    if text and text.SetText and blizzardTitle then text:SetText(blizzardTitle) end
end

-- How the tabs look only: ours selected and every Blizzard tab not
local function LookOurs()
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
    if PanelTemplates_DeselectTab then
        for _, button in ipairs(SocialTab.BlizzardTabs()) do pcall(PanelTemplates_DeselectTab, button) end
    end
end

function SocialTab:Open()
    if not panel then return end
    active = true
    hidden = { atOpen = {}, later = {} }
    selectedAtOpen = _G.FriendsFrame and _G.FriendsFrame.selectedTab
    HideBlizzardPages(hidden.atOpen)
    LookOurs()
    ShowOurTitle()
    panel:Show()
    self:Refresh()
end

-- Our page away; Blizzard's tabs and page are its own business again
function SocialTab:Close()
    if not active then return end
    active = false
    if panel then panel:Hide() end
    if tab and PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
end

-- After the last tab on show, as the game spaces its own
function SocialTab:Place()
    local last = self.LastShownTab()
    if tab and last then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", last, "TOPRIGHT", SocialTab.TAB_GAP, 0)
    end
end

-- A click on a Blizzard tab, after Blizzard's own handler: our page closes; when the tab
-- was the one Blizzard had selected all along, it redrew nothing, so its page and tab
-- look come back from us
function SocialTab.OnBlizzardTabClick(button)
    if not active then return end
    local frame = _G.FriendsFrame
    local same = frame and frame.selectedTab == selectedAtOpen
    SocialTab:Close()
    if same then ShowPages(hidden.atOpen) end
    ShowPages(hidden.later)
    ShowBlizzardTitle()
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, button) end
    hidden = { atOpen = {}, later = {} }
end

-- FriendsFrame_OnShow: a Blizzard tab was clicked or the window opened
function SocialTab.OnBlizzardShow()
    SocialTab:Close()
    SocialTab:Place()
end

-- FriendsFrame_Update: the window refreshed itself and showed its page again
function SocialTab.OnBlizzardUpdate()
    if active then
        HideBlizzardPages(hidden.later)
        LookOurs()
        ShowOurTitle()
    end
end

local function CreatePanel(frame)
    local p = CreateFrame("Frame", nil, holder)
    local inset = frame.Inset or _G.FriendsFrameInset
    if inset then
        p:SetAllPoints(inset)
    else
        p:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -60)
        p:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    end
    p:SetFrameLevel((frame:GetFrameLevel() or 1) + 50)
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.05, 0.04, 0.03, 1)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 12, -12)
    p.title:SetPoint("RIGHT", -12, 0)
    p.title:SetJustifyH("LEFT")
    p.lines = {}
    for i = 1, SocialTab.ROWS do
        local line = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetPoint("TOPLEFT", 16, -42 - (i - 1) * 20)
        line:SetPoint("RIGHT", -12, 0)
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
    p.create = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.create:SetSize(140, 22)
    p.create:SetPoint("BOTTOMLEFT", 10, 10)
    p.create:SetText(L.GANG_CREATE_BUTTON)
    p.create:SetScript("OnClick", function() ns.Gangs:PromptCreate() end)
    p:Hide()
    return p
end

-- Returns true when the tab was added
function SocialTab:Install()
    local frame = _G.FriendsFrame
    if tab or not frame or not self:Enabled() or not self.LastShownTab() then return false end
    holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    local ok, button = pcall(CreateFrame, "Button", "HeadHunterSocialGangTab", holder, "PanelTabButtonTemplate")
    if not ok or not button then button = CreateFrame("Button", "HeadHunterSocialGangTab", holder, "UIPanelButtonTemplate") end
    button:SetText(L.TAB_GANG)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, button, 0) end
    button:SetScript("OnClick", function() SocialTab:Open() end)
    tab = button
    if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
    panel = CreatePanel(frame)
    self:Place()
    if hooksecurefunc then
        if _G.FriendsFrame_OnShow then hooksecurefunc("FriendsFrame_OnShow", SocialTab.OnBlizzardShow) end
        if _G.FriendsFrame_Update then hooksecurefunc("FriendsFrame_Update", SocialTab.OnBlizzardUpdate) end
    end
    if frame.HookScript then frame:HookScript("OnHide", function() SocialTab:Close() end) end
    for _, button in ipairs(self.BlizzardTabs()) do
        if button.HookScript then
            button:HookScript("OnClick", function(clicked) SocialTab.OnBlizzardTabClick(clicked) end)
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
