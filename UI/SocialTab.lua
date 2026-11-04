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
-- members shown at once; the mouse wheel scrolls through the rest (up to 50)
SocialTab.ROWS = 12
SocialTab.TAB_GAP = 3
SocialTab.ROW_HEIGHT = 24
-- the text without a gang: bigger, with room between its lines
SocialTab.EMPTY_SPACING = 8
-- Our buttons sit in the window's bottom bar, under the content area, like Blizzard's own
SocialTab.BAR_EDGE = 6
SocialTab.BAR_BOTTOM = 4
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

local ShowOurTitle

function SocialTab:Refresh()
    if not panel or not active then return end
    ShowOurTitle()
    local gang = ns.Gangs:Mine()
    local U = ns.Utils
    local count = gang and #gang.members or 0
    SocialTab.offset = math.max(0, math.min(SocialTab.offset or 0, count - SocialTab.ROWS))
    for i = 1, SocialTab.ROWS do
        local member = gang and gang.members[SocialTab.offset + i]
        local line, role, border, click = panel.lines[i], panel.roles[i], panel.borders[i], panel.clicks[i]
        if member then
            line:SetText(SocialTab.MemberName(member))
            role:SetText(SocialTab.MemberDetails(member, gang))
            border:Show()
            click.key = member.key
            click:Show()
        else
            line:SetText("")
            role:SetText("")
            border:Hide()
            click.key = nil
            click:Hide()
        end
    end
    if count > SocialTab.ROWS then
        local first = SocialTab.offset + 1
        panel.more:SetText(string.format(L.GANG_MEMBERS_RANGE, first, math.min(count, SocialTab.offset + SocialTab.ROWS), count))
        panel.more:Show()
    else
        panel.more:Hide()
    end
    if gang then
        panel.empty:Hide()
    else
        panel.empty:SetText(ns.Gangs.EmptyText())
        panel.empty:Show()
    end
    if gang and ns.Gangs:IsLeader(gang) then panel.invite:Show() else panel.invite:Hide() end
    if panel.invite.SetEnabled then panel.invite:SetEnabled(gang and gang.confirmed == true or false) end
    if gang then panel.leave:Show() else panel.leave:Hide() end
    if gang then panel.create:Hide() else panel.create:Show() end
end

-- The mouse wheel over the member list: up shows earlier members, down later ones
function SocialTab:Scroll(delta)
    SocialTab.offset = (SocialTab.offset or 0) - (delta or 0) * 3
    self:Refresh()
end

-- "[icon] Name" in the member's class colour
function SocialTab.MemberName(member)
    local U = ns.Utils
    local class = ns.Gangs:MemberClass(member)
    local icon = U.ClassIcon(class, 16)
    return (icon ~= "" and (icon .. " ") or "") .. ns.MainWindow.ClassColored(U.DisplayName(member.key), class)
end

-- "Level 12 · Online · Leader": level when known, online in green, offline in grey
function SocialTab.MemberDetails(member, gang)
    local parts = {}
    local level = ns.Gangs:MemberLevel(member)
    if level then parts[#parts + 1] = string.format(L.GANG_LEVEL, level) end
    parts[#parts + 1] = ns.Gangs:IsOnline(member.key) and ("|cff40ff40" .. L.GANG_ONLINE .. "|r") or ("|cff808080" .. L.GANG_OFFLINE .. "|r")
    parts[#parts + 1] = ns.Utils.SameCharacter(member.key, gang.leader) and L.GANG_ROLE_LEADER or L.GANG_ROLE_MEMBER
    return table.concat(parts, " · ")
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

-- Our title: "Gang"; "Gang - Black Hand" for our gang, with "(waiting for Sync)" until the
-- website confirmed it
function SocialTab.Title()
    local gang = ns.Gangs:Mine()
    if not gang then return L.TAB_GANG end
    local waiting = gang.pending or not gang.confirmed
    return string.format(waiting and L.GANG_WINDOW_TITLE_PENDING or L.GANG_WINDOW_TITLE, gang.name)
end

-- The window's title is ours while our page is open; Blizzard's title is kept to put back
-- when its page comes back from us (its own page code sets it when it shows)
local blizzardTitle
local ourTitle
function ShowOurTitle()
    local text = TitleText()
    if not (text and text.SetText) then return end
    local current = text.GetText and text:GetText()
    if current ~= ourTitle then blizzardTitle = current end
    ourTitle = SocialTab.Title()
    text:SetText(ourTitle)
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

-- The Blizzard tab button of a tab number (Raid is FriendsFrameTab3 with id 2)
local function TabWithId(id)
    for _, button in ipairs(SocialTab.BlizzardTabs()) do
        if button.GetID and button:GetID() == id then return button end
    end
    return nil
end

-- Blizzard's page is back: our page closes and what Blizzard showed comes back from us.
-- Its own redraw ran inside the click while ours was still open, so our refresh hook hid
-- that page again (`later`); a click on the tab Blizzard had selected all along redraws
-- nothing, so the pages hidden at opening come back too.
function SocialTab:Restore()
    if not active then return end
    local frame = _G.FriendsFrame
    local selected = frame and frame.selectedTab
    local same = selected == selectedAtOpen
    self:Close()
    if same then ShowPages(hidden.atOpen) end
    ShowPages(hidden.later)
    ShowBlizzardTitle()
    local button = type(selected) == "number" and TabWithId(selected)
    if button and PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, button) end
    hidden = { atOpen = {}, later = {} }
end

-- A click on a Blizzard tab, after Blizzard's own handler
function SocialTab.OnBlizzardTabClick(button)
    SocialTab:Restore()
    if button and PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, button) end
end

-- FriendsFrame_OnShow: a Blizzard tab was clicked (WoW Forever calls it from the tab's
-- click, after its own redraw) or the window opened
function SocialTab.OnBlizzardShow()
    SocialTab:Restore()
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
    p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    p.empty:SetPoint("TOPLEFT", 16, -16)
    p.empty:SetPoint("RIGHT", -16, 0)
    p.empty:SetJustifyH("LEFT")
    p.empty:SetSpacing(SocialTab.EMPTY_SPACING)
    p.empty:Hide()
    p.more = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.more:SetPoint("BOTTOMRIGHT", -14, 8)
    p.more:Hide()
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta) SocialTab:Scroll(delta) end)
    p.lines, p.roles, p.borders, p.clicks = {}, {}, {}, {}
    for i = 1, SocialTab.ROWS do
        local top = -8 - (i - 1) * SocialTab.ROW_HEIGHT
        local line = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetPoint("TOPLEFT", 14, top - 4)
        line:SetPoint("RIGHT", -190, 0)
        line:SetJustifyH("LEFT")
        local role = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        role:SetPoint("TOPRIGHT", -14, top - 6)
        role:SetJustifyH("RIGHT")
        local border = p:CreateTexture(nil, "ARTWORK")
        border:SetColorTexture(1, 0.82, 0, 0.18)
        border:SetHeight(1)
        border:SetPoint("TOPLEFT", 10, top - SocialTab.ROW_HEIGHT + 1)
        border:SetPoint("TOPRIGHT", -10, top - SocialTab.ROW_HEIGHT + 1)
        border:Hide()
        local click = CreateFrame("Button", nil, p)
        click:SetPoint("TOPLEFT", 10, top)
        click:SetPoint("RIGHT", -10, 0)
        click:SetHeight(SocialTab.ROW_HEIGHT)
        click:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        click:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.key then ns.GangMenu:Open(self.key, self) end
        end)
        click:Hide()
        p.lines[i], p.roles[i], p.borders[i], p.clicks[i] = line, role, border, click
    end
    p.invite = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.invite:SetSize(120, 22)
    p.invite:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SocialTab.BAR_EDGE, SocialTab.BAR_BOTTOM)
    p.invite:SetText(L.GANG_INVITE_BUTTON)
    p.invite:SetScript("OnClick", function() ns.Gangs:Command({ "invite" }) end)
    p.leave = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.leave:SetSize(90, 22)
    p.leave:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SocialTab.BAR_EDGE, SocialTab.BAR_BOTTOM)
    p.leave:SetText(L.GANG_LEAVE_BUTTON)
    p.leave:SetScript("OnClick", function() ns.Gangs:PromptLeave() end)
    p.create = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.create:SetSize(140, 22)
    p.create:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SocialTab.BAR_EDGE, SocialTab.BAR_BOTTOM)
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

-- The HeadHunter window's "Social window" button: the Social window opens on our Gang page.
-- Out of combat only (Show/HideUIPanel are refused then), and never through
-- ToggleFriendsFrame, which would write the window's selected tab from our code.
function SocialTab:OpenFromWindow()
    local frame = _G.FriendsFrame
    if not (self:Enabled() and frame and tab) then return false end
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L.GANG_SOCIAL_COMBAT)
        return false
    end
    if not frame:IsShown() and ShowUIPanel then ShowUIPanel(frame) end
    if frame:IsShown() then self:Open() end
    return frame:IsShown()
end

-- For tests
function SocialTab:Parts()
    return tab, panel
end

ns.Events:Register("HH_INITIALIZED", function()
    SocialTab:Install()
    ns.Events:Register("HH_GANG_CHANGED", function() SocialTab:Refresh() end, OWNER)
end, OWNER)
