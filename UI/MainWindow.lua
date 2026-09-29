-- HH-060: the main window. /hh (no arguments) or the minimap button toggles it.
--
-- Tabs:
--   WANTED         players' bounties first (HH-118, merged per target, newest first),
--                  then who is WANTED now; sort by rank, kills or last kill; Alliance or
--                  Horde (the switch top left, the enemy faction first)
--   Hall of Shame  every enemy with the Coward badge (killed lowbies), WANTED or not;
--                  then players who did not pay their bounties (HH-118, blocked 30 days)
--   High Noon      the best duelists (HH-093), Alliance or Horde (the switch top left)
--   My deaths      our own PvP deaths, newest first
--   My marks       our HeadHunter rank and what earned or cost marks (HH-050)
--   Tournaments    Gurubashi Tournaments (HH-103): a click selects one; Create, Join /
--                  Leave and Cancel (own) top left; UI/TournamentDialog.lua creates
-- A row click opens the outlaw's poster (UI/Poster.lua).
--
-- MainWindow.Rows(tab, sortKey, now) is the pure part (tested offline): one table per
-- row with the text of each column. The rest only draws it, in the GudaBags look
-- (UI/Theme.lua: dark window, tabs on the bottom edge).

local addonName, ns = ...
local L = ns.L

local MainWindow = ns:RegisterModule("MainWindow", {})

local OWNER = "MainWindow"

MainWindow.WIDTH = 620
MainWindow.HEIGHT = 440
MainWindow.ROW_HEIGHT = 18
MainWindow.MAX_ROWS = 300
MainWindow.BOARD_MIN = 25    -- the WANTED tab fills up to this many rows with outlaws at large
MainWindow.REFRESH = 30      -- seconds, while shown ("5 min ago" texts)

MainWindow.TABS = { "wanted", "shame", "duels", "deaths", "marks", "tours" }

-- Columns per tab: key, header, width, sort key (WANTED only)
MainWindow.COLUMNS = {
    wanted = {
        { key = "rank", header = "COL_RANK", width = 90, sort = "rank" },
        { key = "name", header = "COL_NAME", width = 150 },
        { key = "kills", header = "COL_KILLS", width = 50, sort = "kills" },
        { key = "lastKill", header = "COL_LAST_KILL", width = 200, sort = "last" },
        { key = "badges", header = "COL_BADGES", width = 100 },
    },
    shame = {
        { key = "name", header = "COL_NAME", width = 150 },
        { key = "desc", header = "COL_WHO", width = 130 },
        { key = "coward", header = "COL_COWARD_KILLS", width = 90 },
        { key = "kills", header = "COL_KILLS", width = 50 },
        { key = "status", header = "COL_STATUS", width = 170 },
    },
    duels = {
        { key = "position", header = "COL_POSITION", width = 30 },
        { key = "name", header = "COL_NAME", width = 170 },
        { key = "rank", header = "COL_DUEL_RANK", width = 110 },
        { key = "record", header = "COL_RECORD", width = 70 },
        { key = "net", header = "COL_NET", width = 60 },
        { key = "lastDuel", header = "COL_LAST_DUEL", width = 110 },
    },
    tours = {
        { key = "name", header = "COL_TOUR", width = 125 },
        { key = "format", header = "COL_FORMAT", width = 35 },
        { key = "series", header = "COL_SERIES", width = 70 },
        { key = "start", header = "COL_START", width = 90 },
        { key = "level", header = "COL_LEVEL", width = 40 },
        { key = "teams", header = "COL_TEAMS", width = 45 },
        { key = "organizer", header = "COL_ORGANIZER", width = 80 },
        { key = "status", header = "COL_STATUS", width = 85 },
    },
    marks = {
        { key = "time", header = "COL_WHEN", width = 90 },
        { key = "change", header = "COL_CHANGE", width = 60 },
        { key = "reason", header = "COL_REASON", width = 340 },
        { key = "total", header = "COL_TOTAL", width = 60 },
    },
    deaths = {
        { key = "time", header = "COL_WHEN", width = 90 },
        { key = "name", header = "COL_KILLER", width = 150 },
        { key = "desc", header = "COL_WHO", width = 130 },
        { key = "kind", header = "COL_KIND", width = 100 },
        { key = "zone", header = "COL_ZONE", width = 120 },
    },
}

-------------------------------------------------
-- Rows (pure)
-------------------------------------------------

local function ClassColored(text, class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color then return text end
    return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
end

MainWindow.ClassColored = ClassColored

local function OutlawName(entry)
    return entry.key and ns.Utils.DisplayName(entry.key) or entry.name or "?"
end

-- Race icon + name in class color
local function Named(name, who)
    local icon = ns.Utils.RaceIcon(who.race, who.sex)
    return (icon ~= "" and (icon .. " ") or "") .. ClassColored(name, who.class)
end
MainWindow.Named = Named

-- Faction as the client shows it (FACTION_ALLIANCE / FACTION_HORDE: "联盟" on zhCN)
local function FactionLabel(faction)
    if faction == "Alliance" then return _G.FACTION_ALLIANCE or "Alliance" end
    if faction == "Horde" then return _G.FACTION_HORDE or "Horde" end
    return faction
end
MainWindow.FactionLabel = FactionLabel

-- Hover tooltip lines for an enemy (first line = title)
function MainWindow.EntryTooltip(entry, now)
    now = now or ns.Utils.ServerTime()
    local Wanted = ns.Wanted
    local lines = {
        Named(OutlawName(entry), entry),
        "|cffaaaaaa" .. ns.DeathReports.Describe(entry) .. "|r",
    }
    if entry.wanted then
        lines[#lines + 1] = string.format(L.TIP_WANTED, Wanted.RankName(entry.rank), math.floor(entry.kills))
    elseif entry.atLarge then
        lines[#lines + 1] = string.format(L.TIP_AT_LARGE, Wanted.RankName(entry.lastRank))
    else
        local bounty = ns.Bounties:Summary(entry.id, now)
        lines[#lines + 1] = bounty and string.format(L.TIP_BOUNTY_ONLY, ns.Bounties.Gold(bounty.gold)) or L.TIP_NOT_WANTED
    end
    local badges = Wanted.BadgeNames(entry)
    if badges ~= "" then lines[#lines + 1] = badges end
    if entry.lastKill then
        lines[#lines + 1] = string.format(L.TIP_LAST_KILL, ns.Utils.Ago(math.max(0, now - entry.lastKill.t)),
            ns.Utils.MapName(entry.lastKill.mapID) or L.UNKNOWN_ZONE)
    end
    lines[#lines + 1] = string.format(L.TIP_HISTORY, entry.killCount or 0, entry.timesWanted or 0, entry.timesCaught or 0)
    local posse = ns.Posse:Summary(entry.id)
    if posse then lines[#lines + 1] = posse end
    lines[#lines + 1] = L.WINDOW_ROW_HINT
    return lines
end

local function RankOrder(entry)
    return entry.rank and ns.RulesEngine.RANK_ORDER[entry.rank] or 0
end

local function LastKillTime(entry)
    return entry.lastKill and entry.lastKill.t or 0
end

local SORTS = {
    rank = function(a, b)
        if RankOrder(a) ~= RankOrder(b) then return RankOrder(a) > RankOrder(b) end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return LastKillTime(a) > LastKillTime(b)
    end,
    kills = function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return LastKillTime(a) > LastKillTime(b)
    end,
    last = function(a, b)
        return LastKillTime(a) > LastKillTime(b)
    end,
}

function MainWindow.EnemyFaction()
    local mine = ns.Utils.UnitFaction("player")
    if mine == "Horde" then return "Alliance" end
    if mine == "Alliance" then return "Horde" end
    return nil
end

-- The website's WANTED list holds both factions. Entries without a race come from our
-- own reports (Forever given-name-only killers), and those are always enemies.
function MainWindow.EntryFaction(entry)
    return ns.Utils.RaceFaction(entry.race) or MainWindow.EnemyFaction()
end

-- Every outlaw WANTED now, sorted; then (author, 2026-09-26) outlaws at large, newest
-- first, until the list has BOARD_MIN rows. A busy realm fills it with WANTED alone.
local function WantedRows(sortKey, now, faction)
    local function Ours(entry) return not faction or MainWindow.EntryFaction(entry) == faction end
    local list = {}
    for _, entry in ipairs(ns.Wanted:List()) do
        if Ours(entry) then list[#list + 1] = entry end
    end
    table.sort(list, SORTS[sortKey] or SORTS.rank)
    for _, entry in ipairs(ns.Wanted:AtLarge()) do
        if #list >= MainWindow.BOARD_MIN then break end
        if Ours(entry) then list[#list + 1] = entry end
    end
    local rows = {}
    for _, summary in ipairs(ns.Bounties:Board(now)) do
        local entry = ns.Wanted:Get(summary.target)
        if entry and Ours(entry) then rows[#rows + 1] = MainWindow.BountyRow(entry, summary, now) end
    end
    for _, entry in ipairs(list) do
        local kill = entry.lastKill
        local lastKill = "-"
        if kill then
            lastKill = ns.Utils.Ago(math.max(0, now - kill.t)) .. " · " .. (ns.Utils.MapName(kill.mapID) or L.UNKNOWN_ZONE)
        end
        local rank = entry.wanted and ns.Wanted.RankName(entry.rank) or L.AT_LARGE
        rows[#rows + 1] = {
            id = entry.id,
            atLarge = entry.atLarge or nil,
            rank = rank,
            name = Named(OutlawName(entry), entry),
            kills = entry.wanted and tostring(math.floor(entry.kills)) or ("|cff999999" .. (entry.killCount or 0) .. "|r"),
            lastKill = lastKill,
            badges = ns.Wanted.BadgeNames(entry),
            tooltip = MainWindow.EntryTooltip(entry, now),
        }
    end
    return rows
end

-- HH-118: one target with players' bounties, on top of the WANTED tab
function MainWindow.BountyRow(entry, summary, now)
    local Bounties = ns.Bounties
    local poster = summary.newest
    local detail
    if summary.count > 1 then
        detail = string.format(L.BOUNTY_POSTERS, summary.count)
    else
        detail = string.format(L.BOUNTY_DETAIL, Bounties.ReasonText(poster.reason), ns.Utils.DisplayName(poster.owner))
    end
    local tooltip = MainWindow.EntryTooltip(entry, now)
    table.insert(tooltip, 2, "|cffffd100" .. Bounties:Line(entry.id, now) .. "|r")
    return {
        id = entry.id,
        bounty = true,
        rank = string.format(L.BOUNTY_RANK, Bounties.Gold(summary.gold)),
        name = Named(OutlawName(entry), entry),
        kills = tostring(entry.killCount or 0),
        lastKill = detail .. " · " .. string.format(L.BOUNTY_LEFT, ns.Wanted.TimeLeft({ wantedUntil = poster["until"] }, now)),
        badges = ns.Wanted.BadgeNames(entry),
        tooltip = tooltip,
    }
end

local function ShameRows(now)
    local list = {}
    for _, entry in pairs(ns.Wanted:All()) do
        if entry.badges and entry.badges.coward then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        if (a.cowardKills or 0) ~= (b.cowardKills or 0) then return (a.cowardKills or 0) > (b.cowardKills or 0) end
        if a.killCount ~= b.killCount then return a.killCount > b.killCount end
        return OutlawName(a) < OutlawName(b)
    end)
    local rows = {}
    for _, entry in ipairs(list) do
        local status
        if entry.wanted then
            status = string.format(L.SHAME_WANTED, ns.Wanted.RankName(entry.rank))
        else
            status = string.format(L.SHAME_PAST, entry.timesWanted or 0, entry.timesCaught or 0)
        end
        rows[#rows + 1] = {
            id = entry.id,
            name = Named(OutlawName(entry), entry),
            desc = ns.DeathReports.Describe(entry),
            coward = tostring(entry.cowardKills or 0),
            kills = tostring(entry.killCount or 0),
            status = status,
            tooltip = MainWindow.EntryTooltip(entry, now),
        }
    end
    -- HH-118: owners blocked for unpaid bounties
    for _, shamed in ipairs(ns.Bounties:Shamed(now)) do
        local name = ns.Utils.DisplayName(shamed.owner) or shamed.owner
        local daysLeft = math.max(1, math.ceil((shamed.blockedUntil - now) / 86400))
        rows[#rows + 1] = {
            name = name,
            desc = L.SHAME_UNPAID_WHO,
            coward = "-",
            kills = "-",
            status = string.format(L.SHAME_UNPAID, shamed.unpaid, daysLeft),
            tooltip = { name, L.SHAME_UNPAID_TIP, string.format(L.SHAME_UNPAID, shamed.unpaid, daysLeft) },
        }
    end
    return rows
end

-- High Noon (HH-093): the listed duelists of one faction, best first
-- HH-112: players of our own faction can be whispered from the list (not ourselves)
function MainWindow.CanWhisper(key, faction)
    local U = ns.Utils
    return key ~= nil and faction ~= nil and faction == U.UnitFaction("player")
        and not U.SameCharacter(key, U.UnitKey("player"))
end

local function DuelRows(faction, now)
    local HighNoon = ns.HighNoon
    local rows = {}
    for _, p in ipairs(HighNoon:List(faction)) do
        local name = Named(ns.Utils.DisplayName(p.key) or p.key, p)
        local lastDuel = p.lastT and ns.Utils.Ago(math.max(0, now - p.lastT)) or "-"
        local whisper = MainWindow.CanWhisper(p.key, p.faction) and p.key or nil
        local tooltip = { name, string.format(L.DUEL_TOOLTIP, HighNoon.Title(p)),
            string.format(L.TIP_DUEL, p.wins, p.losses, lastDuel) }
        if whisper then tooltip[#tooltip + 1] = L.WINDOW_ROW_WHISPER end
        rows[#rows + 1] = {
            position = tostring(p.position),
            name = name,
            rank = HighNoon.RankName(p.topGun and "topgun" or p.rank),
            record = p.wins .. "-" .. p.losses,
            net = HighNoon.NetText(p.net),
            lastDuel = lastDuel,
            whisper = whisper,
            tooltip = tooltip,
        }
    end
    return rows
end

-- Our marks history (HH-050), newest first
local function MarksRows()
    local rows = {}
    for _, event in ipairs(ns.Marks:Events()) do
        rows[#rows + 1] = {
            time = date("%m-%d %H:%M", event.t),
            change = ns.Marks.Change(event),
            reason = ns.Marks.Reason(event),
            total = tostring(event.total or 0),
        }
    end
    return rows
end

local function DeathRows(now)
    local deaths = ns.db and ns.db.deaths or {}
    local rows = {}
    for i = #deaths, 1, -1 do
        local report = deaths[i]
        if type(report) == "table" and type(report.killer) == "table" then
            local id = ns.RulesEngine.EnemyId(report.killer)
            local zone = ns.Utils.MapName(report.mapID) or L.UNKNOWN_ZONE
            local kind = ns.Classify.ReportLabel(report)
            local name = Named(ns.DeathReports.DisplayName(report.killer), report.killer)
            -- This death first, then what we know about the killer overall
            local entry = id and ns.Wanted:Get(id)
            local tooltip = entry and MainWindow.EntryTooltip(entry, now) or { name, L.WINDOW_ROW_HINT }
            table.insert(tooltip, 2, string.format(L.TIP_KILLED_YOU, date("%m-%d %H:%M", report.t), zone, kind))
            if id and ns.Bounties:CanPost(id, now) then tooltip[#tooltip + 1] = L.BOUNTY_ROW_HINT end
            rows[#rows + 1] = {
                id = id,
                time = date("%m-%d %H:%M", report.t),
                name = name,
                desc = ns.DeathReports.Describe(report.killer),
                kind = kind,
                zone = zone,
                tooltip = tooltip,
            }
        end
    end
    return rows
end

-- "in 25 min", "in 3 h 20 min", "in 2 d 4 h"
local function StartsIn(seconds)
    local minutes = math.ceil(seconds / 60)
    if minutes < 60 then return string.format(L.TOUR_IN_MIN, minutes) end
    if minutes < 1440 then return string.format(L.TOUR_IN_HOURS, math.floor(minutes / 60), minutes % 60) end
    return string.format(L.TOUR_IN_DAYS, math.floor(minutes / 1440), math.floor(minutes % 1440 / 60))
end

-- Gurubashi Tournaments (HH-103), soonest first
local function TourRows(now)
    local TN = ns.Tournaments
    local rows = {}
    for _, t in ipairs(TN:List()) do
        local status = TN:JoinStatus(t)
        local organizer = ns.Utils.DisplayName(t.organizer) or t.organizer
        local bracket = L["TOUR_BRACKET_" .. t.bracket:upper()]
        local start = t.start > now and StartsIn(t.start - now) or ns.Utils.Ago(now - t.start)
        local statusText = L["TOUR_STATUS_" .. status:upper()] or status
        local tooltip = {
            "|cffffd100" .. t.name .. "|r",
            string.format(L.TIP_TOUR_FORMAT, t.format, t.format, bracket, t.bestOf),
            string.format(L.TIP_TOUR_VENUE, TN.Where(t)),
            string.format(L.TIP_TOUR_START, start, ns.Arena.RealmClock((t.start - now) / 60) or "?"),
            string.format(L.TIP_TOUR_TEAMS, #t.order, t.maxTeams, t.minLevel),
            string.format(L.TIP_TOUR_ORGANIZER, organizer),
            statusText,
        }
        for _, teamId in ipairs(t.order) do
            local team = t.entrants[teamId]
            local names = {}
            for i, member in ipairs(team.members) do
                names[i] = (ns.Utils.DisplayName(member) or member)
                    .. (team.here and team.here[member] and L.TIP_TOUR_HERE or "")
            end
            tooltip[#tooltip + 1] = "|cffaaaaaa  " .. table.concat(names, ", ") .. "|r"
        end
        rows[#rows + 1] = {
            id = t.id, tour = true, name = t.name, format = t.format .. "v" .. t.format,
            series = string.format(L.TOUR_SERIES, t.bestOf, t.bracket == "robin" and L.TOUR_ROBIN_SHORT or ""),
            start = start, level = t.minLevel .. "+", teams = #t.order .. "/" .. t.maxTeams,
            organizer = organizer, status = statusText, tooltip = tooltip,
        }
    end
    return rows
end

-- Buttons for the selected tournament: { action = "join" | "leave" | "here" | nil, cancel = bool }
local ACTION = { open = "join", joined = "leave", checkin_me = "here" }

function MainWindow.TourActions(t)
    local TN = ns.Tournaments
    if not t then return {} end
    local status = TN:JoinStatus(t)
    local open = t.state ~= "finished" and t.state ~= "cancelled"
    return {
        action = ACTION[status],
        cancel = open and TN:IsOrganizer(t) or false,
    }
end

-- tab: one of TABS; sortKey (WANTED): "rank" | "kills" | "last"; faction (WANTED, High Noon): "Alliance" | "Horde"
function MainWindow.Rows(tab, sortKey, now, faction)
    now = now or ns.Utils.ServerTime()
    local rows
    if tab == "tours" then
        rows = TourRows(now)
    elseif tab == "duels" then
        rows = DuelRows(faction, now)
    elseif tab == "marks" then
        rows = MarksRows()
    elseif tab == "shame" then
        rows = ShameRows(now)
    elseif tab == "deaths" then
        rows = DeathRows(now)
    else
        rows = WantedRows(sortKey, now, faction)
    end
    for i = #rows, MainWindow.MAX_ROWS + 1, -1 do rows[i] = nil end
    return rows
end

-------------------------------------------------
-- Drawing
-------------------------------------------------

local frame
-- faction: High Noon list, wantedFaction: WANTED list (nil = the default of each tab)
local current = { tab = "wanted", sort = "rank", faction = nil, wantedFaction = nil }
local rowFrames = {}
local sinceRefresh = 0

local function CreateMainFrame()
    local f = CreateFrame("Frame", "HeadHunterMainFrame", UIParent)
    f:SetSize(MainWindow.WIDTH, MainWindow.HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "HeadHunterMainFrame")

    -- The GudaBags look (UI/Theme.lua): dark window, tabs on the bottom edge
    ns.Theme.StyleFrame(f, L.WINDOW_TITLE)
    local tabs = {}
    for i, tab in ipairs(MainWindow.TABS) do tabs[i] = { id = tab, label = L["TAB_" .. tab:upper()] } end
    f.tabs = ns.Theme.CreateTabs(f, tabs, function(tab) MainWindow:SelectTab(tab) end)
    -- Under development: the Tournaments tab (the last one) only with /hh debug tours on
    for _, button in ipairs(f.tabs.buttons) do
        if button.id == "tours" then f.toursTab = button end
    end
    if not MainWindow.ToursEnabled() then f.toursTab:Hide() end

    f.options = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.options:SetSize(80, 20)
    f.options:SetPoint("TOPRIGHT", -30, -6)
    f.options:SetText(L.OPTIONS_BUTTON)
    f.options:SetScript("OnClick", function() ns.SettingsPanel:Open() end)

    -- WANTED and High Noon: switch between the Alliance and Horde lists
    f.faction = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.faction:SetSize(110, 20)
    f.faction:SetPoint("TOPLEFT", 14, -6)
    f.faction:SetScript("OnClick", function() MainWindow:SwitchFaction() end)
    f.faction:Hide()

    -- Tournaments: Create, Join / Leave and Cancel for the selected one
    local function TourButton(width, x, onClick)
        local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        button:SetSize(width, 20)
        button:SetPoint("TOPLEFT", x, -6)
        button:SetScript("OnClick", onClick)
        button:Hide()
        return button
    end
    f.tourCreate = TourButton(80, 14, function() ns.TournamentDialog:Open() end)
    f.tourCreate:SetText(L.TOUR_BUTTON_CREATE)
    f.tourAction = TourButton(80, 98, function() MainWindow:TourAction() end)
    f.tourCancel = TourButton(80, 182, function()
        if current.selected then ns.Tournaments:DoCancel(current.selected) end
    end)
    f.tourCancel:SetText(L.TOUR_BUTTON_CANCEL)

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.count:SetPoint("BOTTOMRIGHT", -16, 10)

    -- Forever: saved data resets on reload (known client issue), on every tab; hover for more
    f.forever = CreateFrame("Frame", nil, f)
    f.forever:SetSize(360, 14)
    f.forever:SetPoint("BOTTOMLEFT", 16, 8)
    f.forever.text = f.forever:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.forever.text:SetPoint("LEFT")
    f.forever.text:SetTextColor(1, 0.53, 0)
    f.forever.text:SetText(L.FOREVER_SAVED_VARS_SHORT)
    f.forever:EnableMouse(true)
    f.forever:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.FOREVER_SAVED_VARS, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.forever:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if ns.Database:ResetsOnReload() then f.forever:Show() else f.forever:Hide() end

    -- Column headers (buttons: clicking a sortable one sorts)
    f.headers = {}
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 14, -56)
    f.scroll:SetPoint("BOTTOMRIGHT", -34, 28)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(MainWindow.WIDTH - 50, MainWindow.ROW_HEIGHT)
    f.scroll:SetScrollChild(f.content)

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER", f, "CENTER", 0, -20)

    f:SetScript("OnUpdate", function(_, elapsed)
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh >= MainWindow.REFRESH then MainWindow:Refresh() end
    end)
    f:Hide()
    return f
end

local function ShowRowTooltip(row)
    if not (GameTooltip and row.data and row.data.tooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    for i, line in ipairs(row.data.tooltip) do
        if i == 1 then GameTooltip:SetText(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function RowFrame(i)
    local row = rowFrames[i]
    if row then return row end
    row = CreateFrame("Button", nil, frame.content)
    row:SetHeight(MainWindow.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * MainWindow.ROW_HEIGHT)
    row:SetPoint("RIGHT", frame.content, "RIGHT")
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.selectedMark = row:CreateTexture(nil, "BACKGROUND")
    row.selectedMark:SetAllPoints(row)
    row.selectedMark:SetColorTexture(1, 0.82, 0, 0.15)
    row.selectedMark:Hide()
    row.cells = {}
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(self) MainWindow:OnRowClick(self.data) end)
    rowFrames[i] = row
    return row
end

local function Cell(row, c)
    local cell = row.cells[c]
    if not cell then
        cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        row.cells[c] = cell
    end
    return cell
end

local function LayoutHeaders(columns)
    for _, header in ipairs(frame.headers) do header:Hide() end
    local x = 14
    for c, column in ipairs(columns) do
        local header = frame.headers[c]
        if not header then
            header = CreateFrame("Button", nil, frame)
            header:SetHeight(18)
            header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            header.text:SetPoint("LEFT", header, "LEFT", 2, 0)
            header:SetScript("OnClick", function(self)
                if self.sort then MainWindow:SetSort(self.sort) end
            end)
            frame.headers[c] = header
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -34)
        header:SetWidth(column.width)
        header.sort = column.sort
        header.text:SetText(L[column.header])
        -- The sorted column in white, the others in the usual gold
        if column.sort and column.sort == current.sort then
            header.text:SetTextColor(1, 1, 1)
        else
            header.text:SetTextColor(1, 0.82, 0)
        end
        header:Show()
        x = x + column.width
    end
end

function MainWindow:Refresh()
    sinceRefresh = 0
    if not (frame and frame:IsShown()) then return end
    local columns = self.COLUMNS[current.tab]
    frame.tabs:Select(current.tab)
    LayoutHeaders(columns)
    local rows = self.Rows(current.tab, current.sort, nil, self:ListFaction())
    for i, data in ipairs(rows) do
        local row = RowFrame(i)
        row.data = data
        local x = 2
        for c, column in ipairs(columns) do
            local cell = Cell(row, c)
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", x, 0)
            cell:SetWidth(column.width - 4)
            cell:SetText(data[column.key] or "")
            cell:Show()
            x = x + column.width
        end
        for c = #columns + 1, #row.cells do row.cells[c]:Hide() end
        if data.tour and data.id == current.selected then row.selectedMark:Show() else row.selectedMark:Hide() end
        row:Show()
    end
    for i = #rows + 1, #rowFrames do
        rowFrames[i]:Hide()
        rowFrames[i].data = nil
    end
    frame.content:SetHeight(math.max(1, #rows) * self.ROW_HEIGHT)
    if current.tab == "marks" then
        frame.count:SetText(string.format(L.MARKS_STATUS, ns.Marks.RankNameByIndex(ns.Marks:RankIndex()), ns.Marks:Total()))
    else
        local count = string.format(L.WINDOW_COUNT, #rows)
        local siteAt = (current.tab == "wanted" or current.tab == "duels") and ns.SiteData:GeneratedAt()
        if siteAt then
            count = count .. string.format(L.WINDOW_SITE_DATA, ns.Utils.Ago(math.max(0, ns.Utils.ServerTime() - siteAt)))
        end
        frame.count:SetText(count)
    end
    frame.empty:SetText(#rows == 0 and L["EMPTY_" .. current.tab:upper()] or "")
    if current.tab == "duels" or current.tab == "wanted" then
        frame.faction:SetText(string.format(L.FACTION_BUTTON, FactionLabel(self:ListFaction()) or "?"))
        frame.faction:Show()
    else
        frame.faction:Hide()
    end
    self:UpdateTourButtons()
    self.shownRows = rows
end

-- The Tournaments tab's buttons follow the selected tournament
function MainWindow:UpdateTourButtons()
    local onTab = current.tab == "tours"
    local t = current.selected and ns.Tournaments:Get(current.selected)
    if not t then current.selected = nil end
    local actions = self.TourActions(t)
    local create = onTab and ns.Tournaments:CanHost()
    self.tourButtons = { create = create, action = onTab and actions.action or nil, cancel = onTab and actions.cancel }
    if not frame then return end
    if create then frame.tourCreate:Show() else frame.tourCreate:Hide() end
    if onTab and actions.action then
        frame.tourAction:SetText(L["TOUR_BUTTON_" .. actions.action:upper()])
        frame.tourAction:Show()
    else
        frame.tourAction:Hide()
    end
    if onTab and actions.cancel then frame.tourCancel:Show() else frame.tourCancel:Hide() end
end

function MainWindow:TourAction()
    local t = current.selected and ns.Tournaments:Get(current.selected)
    local action = self.TourActions(t).action
    if action == "here" then
        ns.Tournaments:DoCheckIn(t.id)
    elseif action then
        ns.Tournaments:DoJoin(t.id, action == "leave")
    end
    self:Refresh()
end

function MainWindow:SelectedTour()
    return current.selected
end

-- The Tournaments tab is under development: hidden unless /hh debug tours on
function MainWindow.ToursEnabled()
    return ns.db and ns.db.settings.devTournaments and true or false
end

-- Shows or hides the Tournaments tab after /hh debug tours on|off
function MainWindow:ApplyToursTab()
    local on = self.ToursEnabled()
    if not on and current.tab == "tours" then current.tab = "wanted" end
    if frame and frame.toursTab then
        if on then frame.toursTab:Show() else frame.toursTab:Hide() end
    end
    self:Refresh()
end

function MainWindow:SelectTab(tab)
    if tab == "tours" and not self.ToursEnabled() then tab = "wanted" end
    current.tab = tab
    if frame and frame.scroll.SetVerticalScroll then frame.scroll:SetVerticalScroll(0) end
    self:Refresh()
end

function MainWindow:SetSort(sortKey)
    current.sort = sortKey
    self:Refresh()
end

-- The High Noon list on show: the one picked with the switch, else our faction's
function MainWindow:DuelFaction()
    return current.faction or ns.Utils.UnitFaction("player")
end

-- The WANTED list on show: the one picked with the switch, else the enemy faction's
function MainWindow:WantedFaction()
    return current.wantedFaction or self.EnemyFaction()
end

-- The faction list of the tab on show (WANTED or High Noon), nil on the other tabs
function MainWindow:ListFaction()
    if current.tab == "wanted" then return self:WantedFaction() end
    if current.tab == "duels" then return self:DuelFaction() end
    return nil
end

function MainWindow:SwitchFaction()
    if current.tab == "wanted" then
        current.wantedFaction = self:WantedFaction() == "Horde" and "Alliance" or "Horde"
    else
        current.faction = self:DuelFaction() == "Horde" and "Alliance" or "Horde"
    end
    self:Refresh()
end

function MainWindow:Current()
    return current.tab, current.sort
end

-- A row opens the outlaw's poster (HH-061); on the Tournaments tab it selects
function MainWindow:OnRowClick(data)
    if data and data.tour then
        current.selected = data.id
        self:Refresh()
    elseif data and data.whisper then
        ns.Utils.OpenWhisper(data.whisper)
    elseif data and data.id then
        ns.Poster:Show(data.id)
    end
end

function MainWindow:IsShown()
    return frame ~= nil and frame:IsShown()
end

function MainWindow:Toggle()
    frame = frame or CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:Refresh()
    end
end

-- Coalesce bursts of data events into one redraw
local pending = false
function MainWindow:RequestRefresh()
    if pending or not self:IsShown() then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        MainWindow:Refresh()
    end)
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

ns.Events:Register("HH_INITIALIZED", function()
    local request = function() MainWindow:RequestRefresh() end
    for _, event in ipairs({ "HH_WANTED_UPDATED", "HH_DEATH_RECORDED", "HH_REPORT_UPDATED", "HH_MARKS_CHANGED",
            "HH_HIGHNOON_UPDATED", "HH_TOURNAMENT_UPDATED", "HH_BOUNTY_UPDATED" }) do
        ns.Events:Register(event, request, OWNER)
    end
end, OWNER)

-- /hh with no arguments opens the window (see Core/SlashCommands.lua)
ns.SlashCommands:Register("show", function() MainWindow:Toggle() end, L.HELP_SHOW)
