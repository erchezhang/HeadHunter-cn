-- HH-155: a Gang tab in the game's Social window on WoW Forever, after Blizzard's own tabs,
-- showing our gang with Invite and Leave. WoW Forever has two Social windows and the server
-- picks one (C_SocialUI.IsSystemEnabled, which may change while playing): the side-tab
-- window SocialUIFrame of 1.60 (the second half of this file) or the older FriendsFrame
-- with tabs at its bottom (the first half). Our tab is put on both; the one on show is used.
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
-- and there is no FriendsFrameTab2. On by default since 1.0.2: /hh gang socialtab on|off, then
-- /reload.

local addonName, ns = ...
local L = ns.L

local SocialTab = ns:RegisterModule("SocialTab", {})

local OWNER = "SocialTab"

SocialTab.MAX_BLIZZARD_TABS = 8
-- members shown at once; the mouse wheel scrolls through the rest (up to 20)
SocialTab.ROWS = 12
SocialTab.TAB_GAP = 3
SocialTab.ROW_HEIGHT = 24
-- the text without a gang: bigger, with room between its lines
SocialTab.EMPTY_SPACING = 8
-- the Sync note, from the window's top left: right after the round portrait, under the title
SocialTab.NOTE_LEFT = 66
SocialTab.NOTE_TOP = 36
SocialTab.NOTE_WIDTH = 300
-- our list on the window: under the note, above the button bar
SocialTab.LIST_TOP = 68
SocialTab.LIST_LEFT = 6
SocialTab.LIST_RIGHT = 8
SocialTab.LIST_BOTTOM = 28
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

-- Our gang into a page: its rows from p.offset, the range when there are more members than
-- rows, the text without a gang, and the buttons for who we are in it
local function FillPanel(p)
    local gang = ns.Gangs:Mine()
    local count = gang and #gang.members or 0
    p.offset = math.max(0, math.min(rawget(p, "offset") or 0, count - p.rows))
    local panel = p
    for i = 1, p.rows do
        local member = gang and gang.members[p.offset + i]
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
    if count > p.rows then
        local first = p.offset + 1
        panel.more:SetText(string.format(L.GANG_MEMBERS_RANGE, first, math.min(count, p.offset + p.rows), count))
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
    if panel.invite.SetEnabled then panel.invite:SetEnabled(gang ~= nil) end
    if gang then panel.leave:Show() else panel.leave:Hide() end
    if gang then panel.create:Hide() else panel.create:Show() end
end

local side = {}
local ShowSideTitle

function SocialTab:Refresh()
    if panel and active then
        ShowOurTitle()
        FillPanel(panel)
    end
    if side.panel and side.active then
        ShowSideTitle()
        FillPanel(side.panel)
    end
end

-- The mouse wheel over a member list: up shows earlier members, down later ones
function SocialTab:Scroll(delta, p)
    p = p or panel
    if not p then return end
    p.offset = (rawget(p, "offset") or 0) - (delta or 0) * 3
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

-- Our title: "Gang"; "Gang - Black Hand" for our gang, with "(not on the website yet)" until
-- the website confirmed it
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

-- Our page's own round icon: a dark circle with the HeadHunter crosshair laid over the
-- window's portrait, part of our page (it shows and hides with it). The game's portrait is
-- never changed, so Contacts and Raid keep their own icons.
SocialTab.PORTRAIT = "Interface\\AddOns\\HeadHunter\\Assets\\Textures\\mark"
local badge

local function PortraitTexture(frame)
    frame = frame or _G.FriendsFrame
    if frame and frame.GetPortrait then
        local ok, texture = pcall(frame.GetPortrait, frame)
        if ok and texture then return texture end
    end
    return frame and (frame.portrait or frame.PortraitContainer and frame.PortraitContainer.portrait) or nil
end

-- The game's round portrait shape: a filled circle, transparent around it
SocialTab.CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function CreateBadge(frame, page)
    frame, page = frame or _G.FriendsFrame, page or panel
    local portrait = PortraitTexture(frame)
    if not portrait then return nil end
    local b = CreateFrame("Frame", nil, page)
    b:SetAllPoints(portrait)
    b:SetFrameStrata(frame.GetFrameStrata and frame:GetFrameStrata() or "MEDIUM")
    b:SetFrameLevel((frame:GetFrameLevel() or 1) + 60)
    b.background = b:CreateTexture(nil, "BACKGROUND")
    b.background:SetAllPoints(b)
    b.background:SetTexture(SocialTab.CIRCLE)
    b.background:SetVertexColor(0.08, 0.06, 0.05, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -6)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 6)
    b.icon:SetTexture(SocialTab.PORTRAIT)
    if b.CreateMaskTexture and b.icon.AddMaskTexture then
        local mask = b:CreateMaskTexture()
        if mask then
            mask:SetAllPoints(b)
            mask:SetTexture(SocialTab.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            b.icon:AddMaskTexture(mask)
        end
    end
    return b
end

local function ShowOurPortrait()
    badge = badge or CreateBadge()
    if badge then badge:Show() end
end

-- How the tabs look only: ours selected and every Blizzard tab not
local function LookOurs()
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
    if PanelTemplates_DeselectTab then
        for _, button in ipairs(SocialTab.BlizzardTabs()) do pcall(PanelTemplates_DeselectTab, button) end
    end
end

-- The Sync note, placed again each time our page opens: the window's top left, a fixed
-- width (the Raid page changes the window, which moved a note stretched to its edge)
function SocialTab:PlaceNote()
    local frame = _G.FriendsFrame
    if not (panel and panel.note and frame) then return end
    panel.note:ClearAllPoints()
    panel.note:SetPoint("TOPLEFT", frame, "TOPLEFT", SocialTab.NOTE_LEFT, -SocialTab.NOTE_TOP)
    panel.note:SetWidth(SocialTab.NOTE_WIDTH)
end

function SocialTab:Open()
    if not panel then return end
    self:PlaceNote()
    active = true
    hidden = { atOpen = {}, later = {} }
    selectedAtOpen = _G.FriendsFrame and _G.FriendsFrame.selectedTab
    HideBlizzardPages(hidden.atOpen)
    LookOurs()
    ShowOurTitle()
    ShowOurPortrait()
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
        ShowOurPortrait()
    end
end

-- Our page: on the window at fixed offsets, not on its inset (the Raid page moves the inset
-- up, having no header, which shrank the grey strip above our list). The blue note that
-- members need HeadHunter Sync sits at the top, under the title bar, right after the round
-- portrait, on up to two lines; set on the window itself, as the game moves the portrait
-- when it changes pages.
-- layout (the side-tab window): { parent, rows, listTop, Place(p), PlaceNote(p),
-- PlaceButton(p, button, left) }
local function CreatePanel(frame, layout)
    layout = layout or {}
    local p = CreateFrame("Frame", nil, layout.parent or holder)
    p.rows = layout.rows or SocialTab.ROWS
    if layout.Place then
        layout.Place(p)
    else
        p:SetPoint("TOPLEFT", frame, "TOPLEFT", SocialTab.LIST_LEFT, -SocialTab.LIST_TOP)
        p:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SocialTab.LIST_RIGHT, SocialTab.LIST_BOTTOM)
    end
    p:SetFrameLevel((frame:GetFrameLevel() or 1) + 50)
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.05, 0.04, 0.03, 1)
    p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    p.empty:SetPoint("TOPLEFT", 16, -(layout.listTop or 16))
    p.empty:SetPoint("RIGHT", -16, 0)
    p.empty:SetJustifyH("LEFT")
    p.empty:SetSpacing(SocialTab.EMPTY_SPACING)
    p.empty:Hide()
    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.note:SetJustifyH("LEFT")
    p.note:SetJustifyV("TOP")
    p.note:SetWordWrap(true)
    p.note:SetText(L.GANG_SYNC_NOTE)
    p.note:SetTextColor(0.4, 0.7, 1)
    p.more = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.more:SetPoint("BOTTOMRIGHT", -14, 8)
    p.more:Hide()
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(self, delta) SocialTab:Scroll(delta, self) end)
    p.lines, p.roles, p.borders, p.clicks = {}, {}, {}, {}
    for i = 1, p.rows do
        local top = -(layout.listTop or 8) - (i - 1) * SocialTab.ROW_HEIGHT
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
    local function PlaceButton(button, left)
        if layout.PlaceButton then return layout.PlaceButton(p, button, left) end
        if left then
            button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SocialTab.BAR_EDGE, SocialTab.BAR_BOTTOM)
        else
            button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SocialTab.BAR_EDGE, SocialTab.BAR_BOTTOM)
        end
    end
    PlaceButton(p.invite, true)
    p.invite:SetText(L.GANG_INVITE_BUTTON)
    p.invite:SetScript("OnClick", function() ns.Gangs:Command({ "invite" }) end)
    p.leave = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.leave:SetSize(90, 22)
    PlaceButton(p.leave, false)
    p.leave:SetText(L.GANG_LEAVE_BUTTON)
    p.leave:SetScript("OnClick", function() ns.Gangs:PromptLeave() end)
    p.create = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.create:SetSize(140, 22)
    PlaceButton(p.create, true)
    if layout.PlaceNote then layout.PlaceNote(p) end
    p.create:SetText(L.GANG_CREATE_BUTTON)
    p.create:SetScript("OnClick", function() ns.Gangs:PromptCreate() end)
    p:Hide()
    return p
end

-- The older FriendsFrame: returns true when the tab was added
function SocialTab:InstallFriends()
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
    if self.SideWindowInUse() and side.tab then return self:OpenSideFromWindow() end
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

-------------------------------------------------
-- The side-tab Social window of WoW Forever 1.60 (SocialUIFrame, Blizzard_SocialUI)
-------------------------------------------------
-- Blizzard builds its tabs (Friends, Recent Allies, Friend Requests, Raid) from a private
-- list into a pool, again on every opening, and the Social and Raid keybinds read the
-- window's selected tab (SocialUIControl.ToggleToTab), while the Raid page holds secure unit
-- buttons. So, as with the older window:
--   * our tab is a button of our own (Blizzard's SocialUITabTemplate look) in a holder frame
--     of ours, put under Blizzard's last tab after each RefreshTabs; Blizzard's tab list,
--     selectedTab and lastSelectedTabType are never written, SelectTab never called;
--   * opening our page: Blizzard's tabs look unselected (SetChecked: textures only), its
--     page is hidden (the Raid page only out of combat; in combat our opaque page covers
--     it), and the title is ours (SetTitle: the title text only);
--   * post-hooks only: SelectTab (every Blizzard tab click, even on the tab already
--     selected, and every opening and closing) closes our page and puts Blizzard's page,
--     tab look and title back; RefreshContentFrame hides Blizzard's page again while ours
--     is open; RefreshTabs places our tab again.

SocialTab.SIDE_ROWS = 20
SocialTab.SIDE_TAB_GAP = 3
-- the first Blizzard tab's place, when no Blizzard tab is on show
SocialTab.SIDE_FIRST_TAB_TOP = 122
-- our tab's icon, the size of Blizzard's tab icons when the game tells it
SocialTab.SIDE_ICON_SIZE = 30
SocialTab.SIDE_ICON_ATLAS = "friends-icon-tab-friends"
-- our page inside the window: where Blizzard puts its pages (under the Battle.net bar)
SocialTab.SIDE_NOTE_TOP = 10
SocialTab.SIDE_LIST_TOP = 44
SocialTab.SIDE_EDGE = 8

function SocialTab.SideWindow()
    return _G.SocialUIFrame
end

-- True while the server has the side-tab window in use instead of the older one
function SocialTab.SideWindowInUse()
    local control = _G.SocialUIControl
    if not (control and control.IsEnabled and SocialTab.SideWindow()) then return false end
    local ok, enabled = pcall(control.IsEnabled)
    return ok and enabled == true
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

-- Blizzard's tab buttons on show, in their order (read from the window, never written)
function SocialTab.SideTabs()
    local frame = SocialTab.SideWindow()
    local tabs = {}
    if not (frame and frame.GetTabByType and type(frame.availableTabData) == "table") then return tabs end
    for _, data in ipairs(frame.availableTabData) do
        local ok, button = pcall(frame.GetTabByType, frame, data.tabType)
        if ok and button then tabs[#tabs + 1] = button end
    end
    return tabs
end

-- Under Blizzard's last tab, as it spaces its own
function SocialTab:PlaceSide()
    local frame = self.SideWindow()
    if not (side.tab and frame) then return end
    local tabs = self.SideTabs()
    side.tab:ClearAllPoints()
    if #tabs > 0 then
        side.tab:SetPoint("TOPLEFT", tabs[#tabs], "BOTTOMLEFT", 0, -SocialTab.SIDE_TAB_GAP)
    else
        side.tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -SocialTab.SIDE_FIRST_TAB_TOP)
    end
end

local function SetLook(button, checked)
    if button and button.SetChecked then pcall(button.SetChecked, button, checked) end
end

local function SidePage(frame)
    local page = frame and frame.activeContentFrame
    if type(page) ~= "table" or not page.IsShown then return nil end
    return page
end

-- Blizzard's page out of sight; the Raid page only out of combat
local function HideSidePage(frame)
    local page = SidePage(frame)
    if page and page:IsShown() and not (page == frame.RaidFrame and InCombat()) then page:Hide() end
end

function ShowSideTitle()
    local frame = SocialTab.SideWindow()
    if frame and frame.SetTitle then pcall(frame.SetTitle, frame, SocialTab.Title()) end
end

function SocialTab:OpenSide()
    local frame = self.SideWindow()
    if not (side.panel and frame) then return end
    side.active = true
    HideSidePage(frame)
    for _, button in ipairs(self.SideTabs()) do SetLook(button, false) end
    SetLook(side.tab, true)
    side.badge = side.badge or CreateBadge(frame, side.panel)
    if side.badge then side.badge:Show() end
    side.panel:Show()
    self:Refresh()
end

function SocialTab:CloseSide()
    if not side.active then return end
    side.active = false
    if side.panel then side.panel:Hide() end
    SetLook(side.tab, false)
end

-- After Blizzard's SelectTab: its page, tab look and title are back. A click on the tab it
-- had selected all along changes nothing on its side, so they come back from us.
function SocialTab.OnSideSelect()
    if not side.active then return end
    SocialTab:CloseSide()
    local frame = SocialTab.SideWindow()
    if not frame then return end
    local page = SidePage(frame)
    if page and not page:IsShown() and not (page == frame.RaidFrame and InCombat()) then page:Show() end
    local selected = frame.GetSelectedTab and frame:GetSelectedTab()
    for _, button in ipairs(SocialTab.SideTabs()) do
        SetLook(button, selected ~= nil and button.tabData ~= nil and button.tabData.tabType == selected)
    end
    if frame.RefreshTitle then pcall(frame.RefreshTitle, frame) end
end

-- After Blizzard's RefreshContentFrame: its page hidden again while ours is open
function SocialTab.OnSideContent()
    if side.active then HideSidePage(SocialTab.SideWindow()) end
end

local function CreateSideTab(frame)
    local ok, button = pcall(CreateFrame, "Button", "HeadHunterSocialSideGangTab", side.holder, "SocialUITabTemplate")
    if not ok or not button then
        ok, button = pcall(CreateFrame, "Button", "HeadHunterSocialSideGangTab", side.holder, "LargeSideTabButtonTemplate")
    end
    if not ok or not button then button = CreateFrame("Button", "HeadHunterSocialSideGangTab", side.holder) end
    button.tooltipText = (HIGHLIGHT_FONT_COLOR and HIGHLIGHT_FONT_COLOR.WrapTextInColorCode)
        and HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(L.TAB_GANG) or L.TAB_GANG
    local icon = rawget(button, "Icon")
    if type(icon) == "table" and icon.SetTexture then
        icon:SetTexture(SocialTab.PORTRAIT)
        local size = SocialTab.SIDE_ICON_SIZE
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SocialTab.SIDE_ICON_ATLAS)
        if type(info) == "table" and info.width then size = info.width end
        icon:SetSize(size, size)
    end
    -- No counter under our icon: the template starts with its Count shown, which lifts the
    -- icon by 5 (Blizzard's tabs clear it in Initialize)
    if type(rawget(button, "SetCount")) == "function" then
        pcall(button.SetCount, button, nil)
    end
    button:SetScript("OnClick", function() SocialTab:OpenSide() end)
    button:SetFrameLevel((frame:GetFrameLevel() or 1) + 2)
    SetLook(button, false)
    return button
end

local function CreateSidePanel(frame)
    return CreatePanel(frame, {
        parent = side.holder,
        rows = SocialTab.SIDE_ROWS,
        listTop = SocialTab.SIDE_LIST_TOP,
        Place = function(p)
            local bar = frame.BattleNetBar
            if type(bar) == "table" then
                p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 5)
            else
                p:SetPoint("TOPLEFT", frame, "TOPLEFT", SocialTab.LIST_LEFT, -SocialTab.LIST_TOP)
            end
            p:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        end,
        PlaceNote = function(p)
            p.note:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -SocialTab.SIDE_NOTE_TOP)
            p.note:SetPoint("RIGHT", p, "RIGHT", -14, 0)
        end,
        PlaceButton = function(p, button, left)
            if left then
                button:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", SocialTab.SIDE_EDGE, SocialTab.SIDE_EDGE)
            else
                button:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -SocialTab.SIDE_EDGE, SocialTab.SIDE_EDGE)
            end
        end,
    })
end

-- The side-tab window: returns true when the tab was added
function SocialTab:InstallSide()
    local frame = self.SideWindow()
    if side.tab or not frame or not self:Enabled() then return false end
    side.holder = CreateFrame("Frame", nil, frame)
    side.holder:SetAllPoints(frame)
    side.tab = CreateSideTab(frame)
    side.panel = CreateSidePanel(frame)
    self:PlaceSide()
    if hooksecurefunc then
        if frame.SelectTab then hooksecurefunc(frame, "SelectTab", SocialTab.OnSideSelect) end
        if frame.RefreshContentFrame then hooksecurefunc(frame, "RefreshContentFrame", SocialTab.OnSideContent) end
        if frame.RefreshTabs then hooksecurefunc(frame, "RefreshTabs", function() SocialTab:PlaceSide() end) end
    end
    if frame.HookScript then frame:HookScript("OnHide", function() SocialTab:CloseSide() end) end
    return true
end

-- Our Gang page in the side-tab window, from the HeadHunter window: out of combat only
function SocialTab:OpenSideFromWindow()
    local frame = self.SideWindow()
    if not (self:Enabled() and frame and side.tab) then return false end
    if InCombat() then
        ns:Print(L.GANG_SOCIAL_COMBAT)
        return false
    end
    if not frame:IsShown() and ShowUIPanel then ShowUIPanel(frame) end
    if frame:IsShown() then self:OpenSide() end
    return frame:IsShown()
end

function SocialTab:IsSideActive()
    return side.active == true
end

-- Both windows; returns true when a tab was added to either
function SocialTab:Install()
    local friends = self:InstallFriends()
    local sideAdded = self:InstallSide()
    return friends or sideAdded
end

-- For tests
function SocialTab:Parts()
    return tab, panel
end

function SocialTab:SideParts()
    return side.tab, side.panel
end

ns.Events:Register("HH_INITIALIZED", function()
    SocialTab:Install()
    ns.Events:Register("HH_GANG_CHANGED", function() SocialTab:Refresh() end, OWNER)
    ns.Events:Register("ADDON_LOADED", function(_, name)
        if name == "Blizzard_SocialUI" then SocialTab:InstallSide() end
    end, OWNER)
end, OWNER)
