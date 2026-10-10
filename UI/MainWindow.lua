-- HH-060: the main window. /hh (no arguments) or the minimap button toggles it.
--
-- Sections (author, 2026-10-01): the top tabs, each with its own sub-tabs in the
-- toolbar: Bounty board (WANTED · Bullies · Deadbeats), Busted, Duels, Events (Ongoing ·
-- Upcoming · Finished), Me (My deaths · My marks). The views:
--   WANTED         players' bounties first (HH-118, merged per target, newest first),
--                  then who is WANTED now; sort by rank, kills or last kill
--   Bullies        every enemy with the Coward badge (killed lowbies), WANTED or not
--   Deadbeats      players who did not pay their bounties (HH-118, blocked 30 days)
--   (the Hall of Shame of older versions, split as on the website: author, 2026-10-02)
--   Busted         the WANTED players caught, newest first, and who busted them
--   High Noon      the best duelists (HH-093); All ranks both factions in one list
-- The Bounty board and Duels have the faction switch top right (author, 2026-10-01):
-- All, Alliance or Horde, All first; the board's views share one choice, Duels has its own
--   My deaths      our own PvP deaths, newest first
--   My marks       our HeadHunter rank and what earned or cost marks (HH-050)
--   Events         the website's tournaments on our world (WEB-080), being played, to
--                  come, or over (the final decided or ended by the host); a click opens
--                  the event: its rounds, who meets who, the scores, the places once
--                  finished, and its website link to copy (Tournament/Tournaments.lua)
-- A row click opens the outlaw's poster (UI/Poster.lua).
-- Sub-tabs on the left; the filters on the right: the search by name (WANTED, Bullies,
-- Deadbeats, Duels, My deaths; one per tab), then the faction switch at the edge;
-- the rows keep their place.
--
-- MainWindow.Rows(tab, sortKey, now) is the pure part (tested offline): one table per
-- row with the text of each column. The rest only draws it, in the website's look
-- (UI/Theme.lua, HH-125: leather, gold frame, tabs in the wood header).

local addonName, ns = ...
local L = ns.L

local MainWindow = ns:RegisterModule("MainWindow", {})

local OWNER = "MainWindow"

MainWindow.WIDTH = 840
MainWindow.HEIGHT = 580
MainWindow.ROW_HEIGHT = 26
MainWindow.TEXT_SIZE = 14    -- the list text; names one bigger (HH-125)
MainWindow.NAME_SIZE = 15
-- HH-137: every row of a list is shown, but only the rows in view get a frame, moved
-- along while scrolling. Without a known height (tests): this many.
MainWindow.VISIBLE_FALLBACK = 20
MainWindow.BOARD_MIN = 25    -- the WANTED tab fills up to this many rows with outlaws at large
MainWindow.REFRESH = 30      -- seconds, while shown ("5 min ago" texts)
MainWindow.TAB_COUNT = "%s (%d)" -- a header tab with a count: "Events (2)"
MainWindow.EVENT_LINK_WIDTH = 110 -- Join event / Event link; wider for longer languages
MainWindow.BUTTON_PADDING = 12

-- The top tabs and their views (the sub-tabs); a view is what the list shows
MainWindow.SECTIONS = {
    { id = "board", views = { "wanted", "bullies", "deadbeats" } },
    { id = "busted", views = { "busted", "barflies" } },
    { id = "duels", views = { "duels" } },
    -- Upcoming first and opened by default (author, 2026-10-05)
    { id = "events", views = { "upcoming", "ongoing", "finished" } },
    { id = "me", views = { "deaths", "marks" } },
}
MainWindow.TABS = { "wanted", "bullies", "deadbeats", "busted", "barflies", "duels", "upcoming", "ongoing", "finished", "deaths", "marks" }
-- Tabs of older versions
MainWindow.OLD_TABS = { tours = "upcoming", shame = "bullies" }
-- The faction crests in the Alliance / Horde switch: the game's PvP flag icons,
-- cut to the crest
MainWindow.FACTION_ICONS = {
    Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
}
MainWindow.FACTION_ICON_COORDS = { 0.03, 0.62, 0.02, 0.62 }
-- The faction switch: both factions or one; All lists everyone (no faction)
MainWindow.ALL = "All"
MainWindow.BOARD_TABS = { wanted = true, bullies = true, deadbeats = true }
-- Tabs with a search box, each with its own search (the long lists)
MainWindow.SEARCH_TABS = { wanted = true, bullies = true, deadbeats = true, busted = true, barflies = true, duels = true,
    deaths = true }
-- What a sub-tab lists, on hover (author, 2026-10-02)
MainWindow.TAB_TIPS = { wanted = "TIP_TAB_WANTED", bullies = "TIP_TAB_BULLIES", deadbeats = "TIP_TAB_DEADBEATS" }
-- The box fits between three sub-tabs and the faction switch on one row
MainWindow.SEARCH_WIDTH = 140

-- Columns per tab: key, header, width, sort key (WANTED only); name columns use the
-- name font, like the website's player cells
MainWindow.COLUMNS = {
    wanted = {
        { key = "rank", header = "COL_RANK", width = 125, sort = "rank" },
        { key = "name", header = "COL_NAME", width = 215, font = "name" },
        { key = "kills", header = "COL_KILLS", width = 70, sort = "kills" },
        { key = "lastKill", header = "COL_LAST_KILL", width = 245, sort = "last" },
        { key = "badges", header = "COL_BADGES", width = 135 },
    },
    bullies = {
        { key = "name", header = "COL_NAME", width = 215, font = "name" },
        { key = "desc", header = "COL_WHO", width = 180 },
        { key = "coward", header = "COL_COWARD_KILLS", width = 115 },
        { key = "kills", header = "COL_KILLS", width = 70 },
        { key = "status", header = "COL_STATUS", width = 210 },
    },
    deadbeats = {
        { key = "name", header = "COL_NAME", width = 300, font = "name" },
        { key = "unpaid", header = "COL_UNPAID", width = 190 },
        { key = "blocked", header = "COL_BLOCKED", width = 300 },
    },
    busted = {
        { key = "time", header = "COL_WHEN", width = 125 },
        { key = "name", header = "COL_NAME", width = 245, font = "name" },
        { key = "by", header = "COL_BUSTED_BY", width = 215, font = "name" },
        { key = "zone", header = "COL_ZONE", width = 105 }, -- then the Raise a glass button
    },
    barflies = {
        { key = "position", header = "COL_POSITION", width = 40 },
        { key = "name", header = "COL_NAME", width = 260, font = "name" },
        { key = "title", header = "COL_RANK", width = 170 },
        { key = "glasses", header = "COL_GLASSES", width = 120 },
        { key = "lastGlass", header = "COL_LAST_GLASS", width = 200 },
    },
    duels = {
        { key = "position", header = "COL_POSITION", width = 40 },
        { key = "name", header = "COL_NAME", width = 235, font = "name" },
        { key = "rank", header = "COL_DUEL_RANK", width = 145 },
        { key = "record", header = "COL_RECORD", width = 100 },
        { key = "net", header = "COL_NET", width = 80 },
        { key = "lastDuel", header = "COL_LAST_DUEL", width = 190 },
    },
    events = {
        { key = "name", header = "COL_TOUR", width = 180 },
        { key = "format", header = "COL_FORMAT", width = 50 },
        { key = "series", header = "COL_SERIES", width = 100 },
        { key = "start", header = "COL_START", width = 135 },
        { key = "level", header = "COL_LEVEL", width = 55 },
        { key = "teams", header = "COL_ENTRANTS", width = 70 },
        { key = "organizer", header = "COL_HOST", width = 110, font = "name" },
        { key = "status", header = "COL_STATUS", width = 80 },
    },
    -- One event's round: who meets who
    -- The last 200 px hold the row's buttons (Call, Ready, Confirm ...)
    event = {
        { key = "match", header = "COL_MATCH", width = 36 },
        { key = "a", header = "COL_ENTRANT", width = 180, font = "name" },
        { key = "score", header = "COL_SCORE", width = 56 },
        { key = "b", header = "COL_OPPONENT", width = 180, font = "name" },
        { key = "status", header = "COL_STATUS", width = 150 },
    },
    marks = {
        { key = "time", header = "COL_WHEN", width = 125 },
        { key = "change", header = "COL_CHANGE", width = 80 },
        { key = "reason", header = "COL_REASON", width = 480 },
        { key = "total", header = "COL_TOTAL", width = 95 },
    },
    deaths = {
        { key = "time", header = "COL_WHEN", width = 125 },
        { key = "name", header = "COL_KILLER", width = 205, font = "name" },
        { key = "desc", header = "COL_WHO", width = 180 },
        { key = "kind", header = "COL_KIND", width = 125 },
        { key = "zone", header = "COL_ZONE", width = 145 },
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

-- A faction crest for text, cut like the switch's, or "" when unknown
function MainWindow.FactionIcon(faction, size)
    local texture = faction and MainWindow.FACTION_ICONS[faction]
    if not texture then return "" end
    size = size or 14
    local c = MainWindow.FACTION_ICON_COORDS
    local function Px(v) return math.floor(v * 64 + 0.5) end
    return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", texture, size, size, Px(c[1]), Px(c[2]), Px(c[3]), Px(c[4]))
end

-- Faction crest, race icon, the name in class color, then the class icon (author,
-- 2026-10-01); no crest when faction is nil; muted: the name in grey (a side that did
-- not come), the icons kept
function MainWindow.Labeled(name, who, faction, muted)
    local icons = MainWindow.FactionIcon(faction) .. ns.Utils.RaceIcon(who.race, who.sex)
    local class = ns.Utils.ClassIcon(who.class)
    local shown = muted and ("|cff808080" .. name .. "|r") or ClassColored(name, who.class)
    return (icons ~= "" and (icons .. " ") or "") .. shown .. (class ~= "" and (" " .. class) or "")
end

-- A player in the lists: without a faction of its own, an outlaw's is the one of its
-- race, else the enemy's
local function Named(name, who)
    return MainWindow.Labeled(name, who, who.faction or MainWindow.EntryFaction(who))
end
MainWindow.Named = Named

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
    lines[#lines + 1] = string.format(L.TIP_HISTORY, entry.killCount or 0)
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
            plain = OutlawName(entry),
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
        plain = OutlawName(entry),
        name = Named(OutlawName(entry), entry),
        kills = tostring(entry.killCount or 0),
        lastKill = detail .. " · " .. string.format(L.BOUNTY_LEFT, ns.Wanted.TimeLeft({ wantedUntil = poster["until"] }, now)),
        badges = ns.Wanted.BadgeNames(entry),
        tooltip = tooltip,
    }
end

-- faction: "Alliance" | "Horde" or nil for both
local function BullyRows(now, faction)
    local list = {}
    for _, entry in pairs(ns.Wanted:All()) do
        if entry.badges and entry.badges.coward and (not faction or MainWindow.EntryFaction(entry) == faction) then
            list[#list + 1] = entry
        end
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
            -- No WANTED or busted counts in the addon (author, 2026-10-04): it only knows
            -- what it saw, the website has the whole record
            status = L.TIP_NOT_WANTED
        end
        rows[#rows + 1] = {
            id = entry.id,
            plain = OutlawName(entry),
            name = Named(OutlawName(entry), entry),
            desc = ns.DeathReports.Describe(entry),
            coward = tostring(entry.cowardKills or 0),
            kills = tostring(entry.killCount or 0),
            status = status,
            tooltip = MainWindow.EntryTooltip(entry, now),
        }
    end
    return rows
end

-- HH-118: owners blocked for unpaid bounties, longest block first; faction: "Alliance" |
-- "Horde" or nil for both; a Deadbeat of an unknown faction only shows with both
local function DeadbeatRows(now, faction)
    local rows = {}
    for _, shamed in ipairs(ns.Bounties:Shamed(now)) do
        if not faction or shamed.faction == faction then
            local plain = ns.Utils.DisplayName(shamed.owner) or shamed.owner
            local name = MainWindow.Labeled(plain, {}, shamed.faction)
            local daysLeft = math.max(1, math.ceil((shamed.blockedUntil - now) / 86400))
            rows[#rows + 1] = {
                plain = plain,
                name = name,
                unpaid = tostring(shamed.unpaid),
                blocked = string.format(L.BOUNTY_DAYS, daysLeft),
                tooltip = { name, L.SHAME_UNPAID_TIP, string.format(L.SHAME_UNPAID, shamed.unpaid, daysLeft) },
            }
        end
    end
    return rows
end

-- High Noon (HH-093): the listed duelists of one faction, best first; with no faction
-- both lists in one, # their place in it (ranks and Top Guns stay per faction)
-- HH-112: players of our own faction can be whispered from the list (not ourselves)
function MainWindow.CanWhisper(key, faction)
    local U = ns.Utils
    return key ~= nil and faction ~= nil and faction == U.UnitFaction("player")
        and not U.SameCharacter(key, U.UnitKey("player"))
end

-- Both factions' lists in one, best first: they are sorted, so one merge does it
local function BothLists(HighNoon)
    local a, b = HighNoon:List("Alliance"), HighNoon:List("Horde")
    local list, i, j = {}, 1, 1
    while a[i] or b[j] do
        if b[j] == nil or (a[i] ~= nil and HighNoon.Better(a[i], b[j])) then
            list[#list + 1] = a[i]
            i = i + 1
        else
            list[#list + 1] = b[j]
            j = j + 1
        end
    end
    return list
end

-- One duelist's row; filled the first time a field is read, so a long list costs only
-- the rows that are drawn (HH-137)
local DuelRow = {}
DuelRow.__index = function(row, field)
    local p, now = rawget(row, "player"), rawget(row, "now")
    if not p or rawget(row, "filled") then return nil end
    local HighNoon = ns.HighNoon
    local plain = p.plain or ns.Utils.DisplayName(p.key) or p.key
    local name = Named(plain, p)
    local lastDuel = p.lastT and ns.Utils.Ago(math.max(0, now - p.lastT)) or "-"
    local whisper = MainWindow.CanWhisper(p.key, p.faction) and p.key or nil
    local tooltip = { name, string.format(L.DUEL_TOOLTIP, HighNoon.Title(p)),
        string.format(L.TIP_DUEL, p.wins, p.losses, lastDuel) }
    if whisper then tooltip[#tooltip + 1] = L.WINDOW_ROW_WHISPER end
    rawset(row, "filled", true)
    rawset(row, "plain", plain)
    rawset(row, "name", name)
    rawset(row, "rank", HighNoon.RankName(p.topGun and "topgun" or p.rank))
    rawset(row, "record", p.wins .. "-" .. p.losses)
    rawset(row, "net", HighNoon.NetText(p.net))
    rawset(row, "lastDuel", lastDuel)
    rawset(row, "whisper", whisper)
    rawset(row, "tooltip", tooltip)
    return rawget(row, field)
end

-- The Duels tab: one faction's list or both in one, # the place in it. A search looks
-- at every duelist (HH-137), and one past the lists shows without a place.
local function DuelRows(faction, now, search)
    local HighNoon = ns.HighNoon
    local list = faction and HighNoon:List(faction) or BothLists(HighNoon)
    local place = {}
    for i, p in ipairs(list) do place[p] = faction and p.position or i end
    if search and search ~= "" then list = HighNoon:Search(search, faction) end
    local rows = {}
    for i, p in ipairs(list) do
        rows[i] = setmetatable({ player = p, now = now, position = place[p] and tostring(place[p]) or "-" }, DuelRow)
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
    local deaths = ns.DeathReports:Mine()
    local rows = {}
    for i = #deaths, 1, -1 do
        local report = deaths[i]
        if type(report) == "table" and type(report.killer) == "table" then
            local id = ns.RulesEngine.EnemyId(report.killer)
            local zone = ns.Utils.MapName(report.mapID) or L.UNKNOWN_ZONE
            local kind = ns.Classify.ReportLabel(report)
            local plain = ns.DeathReports.DisplayName(report.killer)
            local name = Named(plain, report.killer)
            -- This death first, then what we know about the killer overall
            local entry = id and ns.Wanted:Get(id)
            local tooltip = entry and MainWindow.EntryTooltip(entry, now) or { name, L.WINDOW_ROW_HINT }
            table.insert(tooltip, 2, string.format(L.TIP_KILLED_YOU, date("%m-%d %H:%M", report.t), zone, kind))
            if id and ns.Bounties:CanPost(id, now) then tooltip[#tooltip + 1] = L.BOUNTY_ROW_HINT end
            rows[#rows + 1] = {
                id = id,
                time = date("%m-%d %H:%M", report.t),
                plain = plain,
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

-- Busted (author, 2026-10-04): every catch we know of (Sync/Justice.lua) and the website's of our world,
-- newest first; a relayed one once a second source has it. The HeadHunter mark before the name says
-- they were WANTED when busted, though they may not be now.
MainWindow.MARK_ICON = "|TInterface\\AddOns\\HeadHunter\\Assets\\Textures\\mark:14:14|t "
-- Raise a glass: the game's ale mug
MainWindow.GLASS_TEXTURE = "Interface\\Icons\\INV_Drink_05"

local function BustedRows(now)
    local U = ns.Utils
    local list = {}
    for _, record in ns.Justice:All() do
        if type(record) == "table" and record.outlaw and ns.Relay.Counts(record) then list[#list + 1] = record end
    end
    -- The website's catches of our world too (author, 2026-10-04), the ones we do not
    -- know already (same outlaw within a minute)
    local known = #list
    for _, catch in ipairs(ns.SiteData:BustedList()) do
        local seen = false
        for i = 1, known do
            if list[i].outlaw == catch.outlaw and math.abs((list[i].t or 0) - catch.t) <= ns.Justice.DEDUPE then
                seen = true
                break
            end
        end
        if not seen then list[#list + 1] = catch end
    end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    local rows = {}
    for _, record in ipairs(list) do
        local entry = ns.Wanted:Get(record.outlaw)
        local who = entry or ns.EnemyCache:ByKey(record.outlaw) or record.outlawWho or {}
        local plain = (entry and OutlawName(entry))
            or (not record.outlaw:find("^guid:") and U.DisplayName(record.outlaw)) or "?"
        local by = record.killer or record.hunter
        local byName = by and U.DisplayName(by) or "?"
        -- Their race and class: sent with the catch, else what we see of them now
        local byWho = ns.Justice.KillerWho(record) or ns.Justice.Identity(by) or (by and ns.EnemyCache:ByKey(by))
        local zone = U.MapName(record.mapID) or L.UNKNOWN_ZONE
        local when = date("%m-%d %H:%M", record.t)
        local tooltip = entry and MainWindow.EntryTooltip(entry, now) or { Named(plain, who), L.WINDOW_ROW_HINT }
        table.insert(tooltip, 2, string.format(L.TIP_BUSTED, when, zone, byName))
        -- Raise a glass (Sync/Glasses.lua): the count, and the button while we may raise one
        local glasses = ns.Glasses:Count(record)
        local canRaise = ns.Glasses:CanRaise(record)
        local _, raised = ns.Glasses:Of(record)
        local own = ns.Glasses.Own(record, U.UnitKey("player"))
        table.insert(tooltip, 3, string.format(canRaise and L.TIP_GLASSES_RAISE or L.TIP_GLASSES, glasses))
        rows[#rows + 1] = {
            id = entry and entry.id or nil,
            time = when,
            plain = plain,
            name = MainWindow.MARK_ICON .. Named(plain, who),
            by = byWho and MainWindow.Labeled(byName, byWho, byWho.faction or ns.Utils.RaceFaction(byWho.race)) or byName,
            byPlain = byName,
            zone = zone,
            glasses = glasses,
            tooltip = tooltip,
            actions = { { kind = "glass", catch = record, count = glasses, canRaise = canRaise, raised = raised, own = own } },
        }
    end
    return rows
end

-- Barflies (author, 2026-10-04): the players who raised the most glasses from the popup
-- at the moment of a bust, in the last 30 days, from the website's ranking (the download)
MainWindow.BARFLY_TITLES = { barfly = "BARFLY_BARFLY", regular = "BARFLY_REGULAR", saloon_legend = "BARFLY_LEGEND",
    drunken_master = "BARFLY_DRUNKEN" }

local function BarflyRows(now)
    local U = ns.Utils
    local rows = {}
    for i, b in ipairs(ns.SiteData:Barflies()) do
        local plain = U.DisplayName(b.key) or b.key
        local title = MainWindow.BARFLY_TITLES[b.title]
        rows[#rows + 1] = {
            position = tostring(b.position or i),
            plain = plain,
            name = Named(plain, b),
            title = title and L[title] or "",
            glasses = tostring(b.glasses),
            lastGlass = b.lastGlass and U.Ago(math.max(0, now - b.lastGlass)) or "-",
            tooltip = { Named(plain, b), string.format(L.TIP_GLASSES, b.glasses) },
        }
    end
    return rows
end

-- The website's tournaments (WEB-080), soonest first, being played (ongoing) or to come
-- (upcoming); a tooltip with the details, a click opens the event
local function EventRows(view, now)
    local TN = ns.Tournaments
    local rows = {}
    for _, t in ipairs(TN:List(now)) do
        local kind = (TN.Over(t, now) and "finished") or (TN.Ongoing(t, now) and "ongoing") or "upcoming"
        if kind == view then
            local hostName = ns.Utils.DisplayName(t.host) or t.host or "?"
            local who = t.hostInfo or {}
            local host = ClassColored(hostName, who.class)
            local status = L["TOUR_STATUS_" .. TN.State(t, now):upper()]
            local format = t.teamSize .. "v" .. t.teamSize
            local tooltip = {
                "|cffffd100" .. t.name .. "|r",
                format .. " · " .. TN.Series(t),
                string.format(L.TIP_TOUR_VENUE, TN.Where(t)),
                string.format(L.TIP_TOUR_START, TN.Start(t, now)),
            }
            if #t.days > 1 then tooltip[#tooltip + 1] = string.format(L.TIP_TOUR_DAYS, #t.days) end
            tooltip[#tooltip + 1] = string.format(L.TIP_TOUR_ENTRANTS, TN.Entrants(t), TN.Levels(t))
            tooltip[#tooltip + 1] = string.format(L.TIP_TOUR_HOST, MainWindow.Labeled(hostName, who, who.faction or t.faction))
            tooltip[#tooltip + 1] = status
            tooltip[#tooltip + 1] = "|cffaaaaaa" .. L.TIP_EVENT_OPEN .. "|r"
            rows[#rows + 1] = {
                event = t.id, name = t.name, format = format, series = TN.Series(t), start = TN.Start(t, now),
                level = TN.Levels(t), teams = TN.Entrants(t), organizer = host, status = status, tooltip = tooltip,
            }
        end
    end
    return rows
end

-- A finished event's places on one line: "1st X   2nd Y   3rd Z, W" (players with their
-- icons); an event the host ended before its final says so; nil while it is not over
MainWindow.PLACES_HEIGHT = 24
function MainWindow.PlacesLine(t)
    local TN = ns.Tournaments
    local places = TN.Finished(t) and TN.Places(t)
    if not places then
        return t.ended and ("|cffaaaaaa" .. L.EVENT_ENDED .. "|r") or nil
    end
    local parts = {
        string.format(L.EVENT_PLACE_1, TN.SideLabel(t, places.first) or "?"),
        string.format(L.EVENT_PLACE_2, TN.SideLabel(t, places.second) or "?"),
    }
    if #places.third > 0 then
        local third = {}
        for i, entrant in ipairs(places.third) do third[i] = TN.SideLabel(t, entrant) or "?" end
        parts[#parts + 1] = string.format(L.EVENT_PLACE_3, table.concat(third, ", "))
    end
    return table.concat(parts, "     ")
end

-- The live state of a match to play, and its buttons: the organizer's call, ready,
-- games and confirm (Tournament/Matches.lua); a called player's Ready
local function MatchState(t, round, m, now, organizer)
    local M, TN = ns.Matches, ns.Tournaments
    local call = M:Call(t.id, round, m.match)
    local actions = {}
    if organizer then
        if not call then
            actions[1] = { kind = "call", label = L.EVENT_ACT_CALL }
            actions[2] = { kind = "set", label = L.EVENT_ACT_SET }
            return nil, actions
        end
        actions[2] = { kind = "set", label = L.EVENT_ACT_SET }
        local wa, wb = call.wins.a, call.wins.b
        if call.decided then
            actions[1] = { kind = "confirm", label = string.format(L.EVENT_ACT_CONFIRM, wa .. " - " .. wb) }
            return string.format(L.EVENT_ST_DECIDED, wa, wb), actions
        end
        if #call.games > 0 then return string.format(L.EVENT_ST_PLAYING, wa, wb), actions end
        if call.go then return L.EVENT_ST_GO, actions end
        local left = call.readyBy - now
        local ready = (call.ready.a and 1 or 0) + (call.ready.b and 1 or 0)
        if left > 0 then
            return string.format(L.EVENT_ST_CALLED, ready, math.floor(left / 60), left % 60), actions
        end
        local late = not call.ready.a and "a" or "b"
        local name = TN.SideName(t, late == "a" and m.a or m.b) or "?"
        actions[1] = { kind = "noshow", side = late, label = string.format(L.EVENT_ACT_NOSHOW, name) }
        actions[2] = { kind = "call", label = L.EVENT_ACT_RECALL }
        return string.format(L.EVENT_ST_NOT_READY, name), actions
    end
    local mine = M:Mine()
    if mine and mine.tid == t.id and mine.round == round and mine.match == m.match and not mine.ready then
        actions[1] = { kind = "ready", label = L.EVENT_ACT_READY }
        return L.EVENT_ST_CALLED_YOU, actions
    end
    return nil, actions
end

-- One round of an event: who meets who, the score, what is left (pure, tested offline)
function MainWindow.MatchRows(t, roundNumber, now)
    local TN = ns.Tournaments
    now = now or ns.Utils.ServerTime()
    local rounds = TN.Bracket(t)
    local round = rounds[roundNumber]
    local rows = {}
    if not round then return rows end
    -- Matches are called once the tournament has started
    local state = TN.State(t, now)
    local organizer = ns.Matches.IsOrganizer(t) and (state == "running" or state == "finished")
    for _, m in ipairs(round.matches) do
        local a, b = TN.SideName(t, m.a), TN.SideName(t, m.b)
        local played = m.winner ~= nil and not m.bye
        local status
        if m.bye then
            status = L.EVENT_FREE_PASS
        elseif not (m.a and m.b) then
            status = L.EVENT_NOT_DECIDED
        elseif m.forfeit then
            status = L.EVENT_ST_NO_SHOW
        elseif played then
            status = L.EVENT_PLAYED
        else
            status = L.EVENT_TO_PLAY
        end
        local actions = {}
        if m.a and m.b and not m.bye and not m.winner then
            local live
            live, actions = MatchState(t, round.number, m, now, organizer)
            status = live or status
        elseif played and organizer and not ns.Brackets.NextIsPlayed(rounds, round.number, m.match) then
            actions = { { kind = "set", label = L.EVENT_ACT_CHANGE } }
        end
        -- The winner: a green check before the name (the name keeps its class color); a
        -- side that did not come in grey. The details in the tooltip (the columns are short)
        local won = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t %s"
        local function Side(side, entrant, name)
            if not name then return "" end
            if m.forfeit == side then return TN.SideLabel(t, entrant, true) end
            local label = TN.SideLabel(t, entrant)
            return played and m.winner == side and string.format(won, label) or label
        end
        local tooltip = { m.thirdPlace and L.EVENT_THIRD_PLACE
            or string.format(L.EVENT_MATCH_TITLE, TN.RoundName(round.number, #rounds), m.match) }
        if a and b then tooltip[#tooltip + 1] = a .. " vs " .. b end
        if m.forfeit then tooltip[#tooltip + 1] = string.format(L.EVENT_NO_SHOW, m.forfeit == "a" and a or b) end
        tooltip[#tooltip + 1] = status
        rows[#rows + 1] = {
            eventMatch = { round = round.number, match = m.match },
            match = m.thirdPlace and L.EVENT_THIRD_SHORT or ("#" .. m.match),
            a = Side("a", m.a, a),
            b = Side("b", m.b, b),
            tooltip = tooltip,
            score = m.forfeit and L.EVENT_FF or (played and (m.winsA .. " - " .. m.winsB)) or (m.bye and "" or "vs"),
            status = status,
            actions = actions,
        }
    end
    return rows
end

-- tab: one of TABS; sortKey (WANTED): "rank" | "kills" | "last"; faction (WANTED, Bullies,
-- Deadbeats, High Noon): "Alliance" | "Horde", nil for both (not High Noon)
-- Rows keep their place (the Duels # column) and are only left out, so a search by
-- part of a name, any case, finds players far down the list too
local function Matching(rows, search)
    local needle = search and search ~= "" and search:lower() or nil
    if not needle then return rows end
    local found = {}
    for _, row in ipairs(rows) do
        if row.plain and row.plain:lower():find(needle, 1, true) then found[#found + 1] = row end
    end
    return found
end

function MainWindow.Rows(tab, sortKey, now, faction, search)
    now = now or ns.Utils.ServerTime()
    local rows
    if tab == "ongoing" or tab == "upcoming" or tab == "finished" then
        rows = EventRows(tab, now)
    elseif tab == "duels" then
        rows = DuelRows(faction, now, search)
    elseif tab == "marks" then
        rows = MarksRows()
    elseif tab == "bullies" then
        rows = BullyRows(now, faction)
    elseif tab == "deadbeats" then
        rows = DeadbeatRows(now, faction)
    elseif tab == "deaths" then
        rows = DeathRows(now)
    elseif tab == "busted" then
        rows = BustedRows(now)
    elseif tab == "barflies" then
        rows = BarflyRows(now)
    else
        rows = WantedRows(sortKey, now, faction)
    end
    if MainWindow.SEARCH_TABS[tab] and tab ~= "duels" then rows = Matching(rows, search) end
    return rows
end

-------------------------------------------------
-- Drawing
-------------------------------------------------

local frame
-- duelFaction, boardFaction: the faction switch on Duels and on the Bounty board
-- searches: tab -> the text in its search box
-- event: the open event's id (Events), round: the round shown in it (nil: the one played)
-- lastView: section -> the view last shown there
local current = { tab = "wanted", sort = "rank", duelFaction = MainWindow.ALL, boardFaction = MainWindow.ALL, searches = {},
    event = nil, round = nil, lastView = {} }

function MainWindow.SectionOf(view)
    for _, section in ipairs(MainWindow.SECTIONS) do
        for _, v in ipairs(section.views) do
            if v == view then return section end
        end
    end
    return MainWindow.SECTIONS[1]
end
local rowFrames = {}
-- The list last drawn, its rows and columns, for PaintVisible
local painted = {}
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

    -- The website's look (UI/Theme.lua): leather, gold frame, tabs in the wood header
    local Theme = ns.Theme
    Theme.StyleFrame(f, L.WINDOW_TITLE)
    Theme.ResizeGrip(f)
    local tabs = {}
    for i, section in ipairs(MainWindow.SECTIONS) do
        tabs[i] = { id = section.id, label = L["SECTION_" .. section.id:upper()] }
    end
    f.tabs = Theme.CreateTopTabs(f, tabs, function(id) MainWindow:SelectSection(id) end)

    f.options = Theme.HeaderGear(f, function() ns.SettingsPanel:Open() end)
    f.options:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.OPTIONS_BUTTON)
        GameTooltip:Show()
    end)
    f.options:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- The toolbar under the header (only on tabs with buttons)
    local toolbarY = -(Theme.HEADER_HEIGHT + 10)
    -- Bounty board and Duels: All, Alliance or Horde, the one on show gold, top right
    local U = ns.Utils
    f.faction = Theme.Segmented(f, {
        { value = MainWindow.ALL, label = L.FACTION_ALL },
        { value = "Alliance", label = U.FactionName("Alliance"), icon = MainWindow.FACTION_ICONS.Alliance,
            coords = MainWindow.FACTION_ICON_COORDS },
        { value = "Horde", label = U.FactionName("Horde"), icon = MainWindow.FACTION_ICONS.Horde,
            coords = MainWindow.FACTION_ICON_COORDS },
    }, function(faction) MainWindow:SetFaction(faction) end, 100)
    f.faction:SetPoint("TOPRIGHT", -18, toolbarY)
    f.faction:Hide()

    -- A section's sub-tabs, top left
    f.subtabs = {}
    for _, section in ipairs(MainWindow.SECTIONS) do
        if #section.views > 1 then
            local options = {}
            for i, view in ipairs(section.views) do
                local tip = MainWindow.TAB_TIPS[view]
                options[i] = { value = view, label = L["TAB_" .. view:upper()], tip = tip and L[tip] }
            end
            local set = Theme.Segmented(f, options, function(view) MainWindow:SelectTab(view) end)
            set:SetPoint("TOPLEFT", 16, toolbarY)
            set:Hide()
            f.subtabs[section.id] = set
        end
    end

    -- An open event: Back, its name, the round switch, Join event or Event link
    f.eventBack = Theme.Button(f, L.EVENT_BACK, "outline", 80, 24)
    f.eventBack:SetPoint("TOPLEFT", 16, toolbarY)
    f.eventBack:SetScript("OnClick", function() MainWindow:CloseEvent() end)
    f.eventTitle = Theme.Text(f, "heading", 15, "gold")
    f.eventTitle:SetPoint("LEFT", f.eventBack, "RIGHT", 12, 0)
    f.eventTitle:SetWidth(240)
    f.eventTitle:SetJustifyH("LEFT")
    f.eventTitle:SetWordWrap(false)
    f.eventLink = Theme.Button(f, L.EVENT_LINK, "gold", MainWindow.EVENT_LINK_WIDTH, 24)
    f.eventLink:SetPoint("TOPRIGHT", -18, toolbarY)
    f.eventLink:SetScript("OnClick", function() MainWindow:CopyEventLink() end)
    f.eventNext = Theme.Button(f, ">", "outline", 28, 24)
    f.eventNext:SetPoint("RIGHT", f.eventLink, "LEFT", -12, 0)
    f.eventNext:SetScript("OnClick", function() MainWindow:ShowRound(1) end)
    f.eventRound = Theme.Text(f, "text", 14, "foreground")
    f.eventRound:SetPoint("RIGHT", f.eventNext, "LEFT", -8, 0)
    f.eventPrev = Theme.Button(f, "<", "outline", 28, 24)
    f.eventPrev:SetPoint("RIGHT", f.eventRound, "LEFT", -8, 0)
    f.eventPrev:SetScript("OnClick", function() MainWindow:ShowRound(-1) end)
    -- The Events list: events are made on the website, a link to copy
    f.eventsCreate = Theme.Button(f, L.EVENTS_CREATE, "gold", 150, 24)
    f.eventsCreate:SetPoint("TOPRIGHT", -18, toolbarY)
    f.eventsCreate:SetScript("OnClick", function() MainWindow:CopyCreateLink() end)
    f.eventsInfo = Theme.Text(f, "text", 13, "muted")
    f.eventsInfo:SetPoint("RIGHT", f.eventsCreate, "LEFT", -12, 0)
    f.eventsInfo:SetJustifyH("RIGHT")
    f.eventsInfo:SetText(L.EVENTS_INFO)
    f.eventsCreate:Hide()
    f.eventsInfo:Hide()
    -- Our confirmed results to the website: a quick UI reload saves them, then HeadHunter
    -- Sync sends them (an addon cannot reach the website itself)
    f.eventSend = Theme.Button(f, "", "gold", 140, 24)
    -- A finished event: 1st, 2nd and 3rd over its matches (or that the host ended it)
    f.eventPlaces = Theme.Text(f, "text", 14, "foreground")
    f.eventPlaces:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -(Theme.HEADER_HEIGHT + 46))
    f.eventPlaces:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.eventPlaces:SetJustifyH("LEFT")
    f.eventPlaces:SetWordWrap(false)
    f.eventPlaces:Hide()
    f.eventSend:SetPoint("RIGHT", f.eventPrev, "LEFT", -12, 0)
    f.eventSend:SetScript("OnClick", function() MainWindow:SendToWebsite() end)
    for _, w in ipairs({ f.eventBack, f.eventTitle, f.eventLink, f.eventNext, f.eventRound, f.eventPrev, f.eventSend }) do
        w:Hide()
    end

    -- Search tabs: find a player by name (Esc or the x clears it, a second Esc leaves the box)
    local search = CreateFrame("EditBox", nil, f)
    search:SetSize(MainWindow.SEARCH_WIDTH, 24)
    search:SetPoint("TOPRIGHT", -18, toolbarY)
    search:SetAutoFocus(false)
    search:SetTextInsets(8, 26, 0, 0)
    Theme.Font(search, "text", 14)
    local fg = Theme.COLORS.foreground
    search:SetTextColor(fg[1], fg[2], fg[3])
    local searchBg = search:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints(search)
    searchBg:SetColorTexture(0, 0, 0, 0.35)
    Theme.Border(search, 0.45)
    search.hint = Theme.Text(search, "text", 14, "muted")
    search.hint:SetPoint("LEFT", 8, 0)
    search.hint:SetWidth(MainWindow.SEARCH_WIDTH - 16)
    search.hint:SetJustifyH("LEFT")
    search.hint:SetWordWrap(false)
    search.hint:SetText(L.SEARCH_PLAYER)
    search.clear = CreateFrame("Button", nil, search)
    search.clear:SetSize(20, 20)
    search.clear:SetPoint("RIGHT", -3, 0)
    search.clear.x = Theme.Text(search.clear, "bold", 15, "stone")
    search.clear.x:SetPoint("CENTER", 0, 1)
    search.clear.x:SetText("x")
    local stone, gold = Theme.COLORS.stone, Theme.COLORS.gold
    search.clear:SetScript("OnEnter", function(self) self.x:SetTextColor(gold[1], gold[2], gold[3]) end)
    search.clear:SetScript("OnLeave", function(self) self.x:SetTextColor(stone[1], stone[2], stone[3]) end)
    search.clear:SetScript("OnClick", function() MainWindow:ClearSearch() end)
    search.clear:Hide()
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        self.clear:SetShown(text ~= "")
        MainWindow:SetSearch(text)
    end)
    search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:Hide()
    f.search = search

    f.count = Theme.Text(f, "text", 13, "muted")
    f.count:SetPoint("BOTTOMRIGHT", -26, 11)

    -- Forever: saved data resets on reload (known client issue), on every tab; hover for more
    f.forever = CreateFrame("Frame", nil, f)
    f.forever:SetSize(420, 16)
    f.forever:SetPoint("BOTTOMLEFT", 18, 9)
    f.forever.text = Theme.Text(f.forever, "text", 13, "gold")
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

    -- Column headers (buttons: clicking a sortable one sorts), a gold line under them
    f.headers = {}
    f.headerLine = f:CreateTexture(nil, "ARTWORK")
    f.headerLine:SetColorTexture(Theme.COLORS.gold[1], Theme.COLORS.gold[2], Theme.COLORS.gold[3], 0.35)
    f.headerLine:SetHeight(1)
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(MainWindow.WIDTH - 50, MainWindow.ROW_HEIGHT)
    f.scroll:SetScrollChild(f.content)
    f.scroll:HookScript("OnVerticalScroll", function() MainWindow:PaintVisible() end)
    f.scroll:HookScript("OnSizeChanged", function() MainWindow:PaintVisible() end)

    f.empty = Theme.Text(f, "text", 16, "muted")
    f.empty:SetPoint("CENTER", f, "CENTER", 0, -20)

    f:SetScript("OnUpdate", function(_, elapsed)
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh >= MainWindow.REFRESH then MainWindow:Refresh() end
    end)
    f:Hide()
    return f
end

-- At the mouse and following it, not past the end of the wide row (author, 2026-10-04)
local function ShowRowTooltip(row)
    if not (GameTooltip and row.data and row.data.tooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
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
    local gold = ns.Theme.COLORS.gold
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(gold[1], gold[2], gold[3], 0.08)
    -- A thin line between rows, as in the website's tables
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(gold[1], gold[2], gold[3], 0.1)
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
        cell = row:CreateFontString(nil, "OVERLAY")
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        row.cells[c] = cell
    end
    return cell
end

-- One row of the list on a row frame, at its place in the list (index from 1)
local function PaintRow(row, data, columns, index)
    row:ClearAllPoints()
    row:SetPoint("RIGHT", frame.content, "RIGHT")
    row:SetPoint("TOPLEFT", 0, -(index - 1) * MainWindow.ROW_HEIGHT)
    row.data = data
    local x = 2
    for c, column in ipairs(columns) do
        local cell = Cell(row, c)
        if column.font == "name" then
            ns.Theme.Font(cell, "name", MainWindow.NAME_SIZE)
        else
            ns.Theme.Font(cell, "text", MainWindow.TEXT_SIZE)
        end
        local fg = ns.Theme.COLORS.foreground
        cell:SetTextColor(fg[1], fg[2], fg[3])
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", row, "LEFT", x, 0)
        cell:SetWidth(column.width - 4)
        cell:SetText(data[column.key] or "")
        cell:Show()
        x = x + column.width
    end
    for c = #columns + 1, #row.cells do row.cells[c]:Hide() end
    MainWindow:LayoutRowButtons(row, data.actions)
    row:Show()
end

-- The rows in view, from the list last drawn (HH-137); called on refresh and on scroll
function MainWindow:PaintVisible()
    if not frame or not painted.rows then return end
    local rows, columns = painted.rows, painted.columns
    local offset = tonumber((frame.scroll:GetVerticalScroll())) or 0
    local height = tonumber((frame.scroll:GetHeight()))
    local count = (height and height > 0) and (math.ceil(height / self.ROW_HEIGHT) + 1) or self.VISIBLE_FALLBACK
    local first = math.max(1, math.floor(offset / self.ROW_HEIGHT) + 1)
    for slot = 1, count do
        local data = rows[first + slot - 1]
        if data then
            PaintRow(RowFrame(slot), data, columns, first + slot - 1)
        elseif rowFrames[slot] then
            rowFrames[slot]:Hide()
            rowFrames[slot].data = nil
        end
    end
    for slot = count + 1, #rowFrames do
        rowFrames[slot]:Hide()
        rowFrames[slot].data = nil
    end
end

-- The list starts under the toolbar (every section has one)
-- extra: room for a line over the list (a finished event's places)
local function ListTop(extra)
    return ns.Theme.HEADER_HEIGHT + 44 + (extra or 0)
end

local function LayoutHeaders(columns, extra)
    local Theme = ns.Theme
    for _, header in ipairs(frame.headers) do header:Hide() end
    local top = ListTop(extra)
    local x = 16
    for c, column in ipairs(columns) do
        local header = frame.headers[c]
        if not header then
            header = CreateFrame("Button", nil, frame)
            header:SetHeight(22)
            header.text = Theme.Text(header, "heading", 12, "gold")
            header.text:SetPoint("LEFT", header, "LEFT", 2, 0)
            header.text:SetJustifyH("LEFT")
            header:SetScript("OnClick", function(self)
                if self.sort then MainWindow:SetSort(self.sort) end
            end)
            frame.headers[c] = header
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -top)
        header:SetWidth(column.width)
        header.text:SetWidth(column.width - 4)
        header.sort = column.sort
        header.text:SetText(L[column.header])
        -- The sorted column in the light text colour, the others gold
        local color = (column.sort and column.sort == current.sort) and Theme.COLORS.foreground or Theme.COLORS.gold
        header.text:SetTextColor(color[1], color[2], color[3])
        header:Show()
        x = x + column.width
    end
    frame.headerLine:ClearAllPoints()
    frame.headerLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -(top + 23))
    frame.headerLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -(top + 23))
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", 16, -(top + 26))
    frame.scroll:SetPoint("BOTTOMRIGHT", -34, 34)
end

local shownOngoing -- the ongoing count last logged (debug)

-- The Duels tab needs the High Noon lists: they are counted again when out of date (HH-137)
function MainWindow:Refresh()
    sinceRefresh = 0
    if not (frame and frame:IsShown()) then return end
    if current.tab == "duels" then ns.HighNoon:Ensure() end
    local event = self:OpenEvent()
    local columns = event and self.COLUMNS.event or self.COLUMNS[current.tab] or self.COLUMNS.events
    local section = self.SectionOf(current.tab)
    frame.tabs:Select(section.id)
    local ongoing = ns.Tournaments:OngoingCount()
    if ongoing ~= shownOngoing then
        ns:Debug("Events: ongoing", ongoing, "live dot", ongoing > 0)
        shownOngoing = ongoing
    end
    frame.subtabs.events:SetDot("ongoing", ongoing > 0)
    frame.tabs:SetDot("events", ongoing > 0)
    local upcoming = ns.Tournaments:UpcomingCount()
    frame.tabs:SetLabel("events", upcoming > 0 and string.format(self.TAB_COUNT, L.SECTION_EVENTS, upcoming)
        or L.SECTION_EVENTS)
    local places = event and self.PlacesLine(event) or nil
    frame.eventPlaces:SetText(places or "")
    if places then frame.eventPlaces:Show() else frame.eventPlaces:Hide() end
    LayoutHeaders(columns, places and MainWindow.PLACES_HEIGHT or 0)
    local search = not event and self:Search() or nil
    local rows
    if event then
        local count = #ns.Tournaments.Bracket(event)
        current.round = current.round and math.max(1, math.min(current.round, count)) or nil
        rows = self.MatchRows(event, self:EventRound(event))
    else
        rows = self.Rows(current.tab, current.sort, nil, self:ListFaction(), search)
    end
    painted.rows, painted.columns = rows, columns
    frame.content:SetHeight(math.max(1, #rows) * self.ROW_HEIGHT)
    self:PaintVisible()
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
    if #rows > 0 then
        frame.empty:SetText("")
    elseif event then
        frame.empty:SetText(L.EMPTY_EVENT)
    elseif search then
        frame.empty:SetText(string.format(L.SEARCH_EMPTY, (search:gsub("|", "||"))))
    else
        frame.empty:SetText(L["EMPTY_" .. current.tab:upper()])
    end
    self:LayoutToolbar(section, event)
    self.shownRows = rows
end

-- Up to two buttons at the right end of a row (the event view's Call, Ready, Confirm ...)
-- Raise a glass on a Busted row (author, 2026-10-04): the mug and the count, no button
-- frame; it lights up a little on hover and says what it does in a tooltip
local function GlassButton(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(64, 22)
    b:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexture(MainWindow.GLASS_TEXTURE)
    b.count = b:CreateFontString(nil, "OVERLAY")
    ns.Theme.Font(b.count, "text", MainWindow.TEXT_SIZE)
    b.count:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.82, 0, 0.15)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.action then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        -- What a click does, or why it does nothing; then the count
        local a = self.action
        GameTooltip:SetText((a.canRaise and L.GLASS_RAISE) or (a.own and L.GLASS_OWN) or L.GLASS_RAISED)
        GameTooltip:AddLine(string.format(L.TIP_GLASSES, a.count))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self) MainWindow:OnRowAction(row.data, self.action) end)
    return b
end

function MainWindow:LayoutRowButtons(row, actions)
    row.actionButtons = rawget(row, "actionButtons") or {}
    local glass = actions and actions[1] and actions[1].kind == "glass" and actions[1]
    if glass then
        row.glassButton = rawget(row, "glassButton") or GlassButton(row)
        local b = row.glassButton
        b.action = glass
        b.count:SetText(tostring(glass.count))
        -- Raised by us: the mug in colour and a gold count; not yet: grey
        b.icon:SetDesaturated(not glass.raised)
        local color = glass.raised and ns.Theme.COLORS.gold or ns.Theme.COLORS.muted
        if color then b.count:SetTextColor(color[1], color[2], color[3]) end
        b:Show()
        actions = nil
    elseif rawget(row, "glassButton") then
        row.glassButton:Hide()
    end
    for i = 1, 2 do
        local action = actions and actions[i]
        local button = row.actionButtons[i]
        if action and not button then
            button = ns.Theme.Button(row, "", i == 1 and "gold" or "outline", 96, 20)
            button:SetPoint("RIGHT", row, "RIGHT", -4 - (i - 1) * 100, 0)
            button:SetScript("OnClick", function(self) MainWindow:OnRowAction(row.data, self.action) end)
            row.actionButtons[i] = button
        end
        if button then
            button.action = action
            if action then
                button:SetText(action.label)
                button:Show()
            else
                button:Hide()
            end
        end
    end
end

-- A row button: Raise a glass (Busted), or the event view's match buttons
function MainWindow:OnRowAction(data, action)
    if action and action.kind == "glass" then
        if ns.Glasses:Raise(action.catch) then self:Refresh() end
        return
    end
    self:OnMatchAction(data, action)
end

-- A row button of the event view
function MainWindow:OnMatchAction(data, action)
    local t = self:OpenEvent()
    if not (t and data and data.eventMatch and action) then return end
    local round, match = data.eventMatch.round, data.eventMatch.match
    local M = ns.Matches
    if action.kind == "call" then
        M:CallMatch(t, round, match)
    elseif action.kind == "ready" then
        M:Ready()
    elseif action.kind == "confirm" then
        local call = M:Call(t.id, round, match)
        if call then M:Confirm(t, round, match, call.wins.a, call.wins.b) end
    elseif action.kind == "noshow" then
        M:Confirm(t, round, match, 0, 0, action.side)
    elseif action.kind == "set" then
        local call = M:Call(t.id, round, match)
        ns.ResultDialog:Open(t, round, match, call and call.decided and (call.wins.a .. "-" .. call.wins.b) or nil)
    end
    self:Refresh()
end

-- The toolbar of the section on show: its sub-tabs, the faction switch, the search; an
-- open event has its own (Back, name, round switch, Join event or Event link)
function MainWindow:LayoutToolbar(section, event)
    for id, set in pairs(frame.subtabs) do
        if id == section.id and not event then
            set:Select(current.tab)
            set:Show()
        else
            set:Hide()
        end
    end
    local choice = not event and self:FactionChoice()
    if choice then
        frame.faction:Select(choice)
        frame.faction:Show()
    else
        frame.faction:Hide()
    end
    frame.search:ClearAllPoints()
    if choice then
        frame.search:SetPoint("RIGHT", frame.faction, "LEFT", -12, 0)
    else
        frame.search:SetPoint("TOPRIGHT", -18, -(ns.Theme.HEADER_HEIGHT + 10))
    end
    if not event and self.SEARCH_TABS[current.tab] then frame.search:Show() else frame.search:Hide() end
    for _, w in ipairs({ frame.eventBack, frame.eventTitle, frame.eventLink, frame.eventNext, frame.eventRound,
            frame.eventPrev }) do
        if event then w:Show() else w:Hide() end
    end
    local eventsList = section.id == "events" and not event
    for _, w in ipairs({ frame.eventsCreate, frame.eventsInfo }) do
        if eventsList then w:Show() else w:Hide() end
    end
    local unsent = event and ns.Matches:Unsent() or 0
    if unsent > 0 then
        frame.eventSend:SetText(string.format(L.EVENT_SEND, unsent))
        frame.eventSend:Show()
    else
        frame.eventSend:Hide()
    end
    if event then
        local TN = ns.Tournaments
        frame.eventLink:SetText(self.EventLinkJoins(event) and L.EVENT_JOIN or L.EVENT_LINK)
        local textWidth = frame.eventLink:GetFontString() and frame.eventLink:GetFontString():GetStringWidth() or 0
        frame.eventLink:SetWidth(math.max(self.EVENT_LINK_WIDTH, (tonumber(textWidth) or 0) + 2 * self.BUTTON_PADDING))
        local count = #TN.Bracket(event)
        local round = self:EventRound(event)
        frame.eventTitle:SetText(event.name .. " · " .. event.teamSize .. "v" .. event.teamSize .. " · " .. TN.Series(event))
        frame.eventRound:SetText(count > 0 and string.format(L.EVENT_ROUND_OF, TN.RoundName(round, count), round, count) or "")
        if frame.eventPrev.SetEnabled then
            frame.eventPrev:SetEnabled(round > 1)
            frame.eventNext:SetEnabled(round < count)
        end
    end
end

-- The open event, or nil (it may have ended since)
function MainWindow:OpenEvent()
    if not current.event then return nil end
    local t = ns.Tournaments:Get(current.event)
    if not t then current.event = nil end
    return t
end

-- The round shown in the open event: the one picked, else the one being played
function MainWindow:EventRound(t)
    return current.round or ns.Tournaments.CurrentRound(ns.Tournaments.Bracket(t))
end

function MainWindow:ShowEvent(id)
    current.event, current.round = id, nil
    if frame and frame.scroll.SetVerticalScroll then frame.scroll:SetVerticalScroll(0) end
    self:Refresh()
end

function MainWindow:CloseEvent()
    current.event, current.round = nil, nil
    self:Refresh()
end

-- The previous (-1) or next (1) round of the open event
function MainWindow:ShowRound(step)
    local t = self:OpenEvent()
    if not t then return end
    local count = #ns.Tournaments.Bracket(t)
    current.round = math.max(1, math.min(count, self:EventRound(t) + step))
    self:Refresh()
end

-- Join event while sign-up is open and our character is not in it yet (joining happens
-- on the website); Event link once we joined or sign-up closed (author, 2026-10-05)
function MainWindow.EventLinkJoins(t, now)
    local TN = ns.Tournaments
    return TN.State(t, now or ns.Utils.ServerTime()) == "open" and not TN.Joined(t)
end

-- The open event's page on the website, to copy: an addon cannot open a browser. To
-- join, the page itself (where the Join button is), else its bracket
function MainWindow:CopyEventLink()
    local t = self:OpenEvent()
    if not t then return end
    if not t.url then
        ns:Print(L.EVENT_NO_LINK)
        return
    end
    if self.EventLinkJoins(t) then
        self:ShowLink(L.EVENT_JOIN_TEXT, (t.url:gsub("%?.*$", "")))
    else
        self:ShowLink(L.EVENT_LINK_TEXT, t.url)
    end
end

-- The website's page to make an event, to copy
function MainWindow:CopyCreateLink()
    local url = ns.SiteData:Link("create_tournament")
    if not url then
        ns:Print(L.EVENTS_NO_LINK)
        return false
    end
    self:ShowLink(L.EVENTS_CREATE_TEXT, url)
    return true
end

-- A popup with a link selected in a box, for Ctrl+C
function MainWindow:ShowLink(text, url)
    if not StaticPopupDialogs.HEADHUNTER_LINK then
        StaticPopupDialogs.HEADHUNTER_LINK = {
            button1 = OKAY or "OK",
            hasEditBox = true,
            editBoxWidth = 360,
            OnShow = function(dialog, url)
                local box = dialog.editBox or dialog.EditBox
                if box then
                    box:SetText(url or "")
                    box:HighlightText()
                    box:SetFocus()
                end
            end,
            EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
            EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopupDialogs.HEADHUNTER_LINK.text = text
    StaticPopup_Show("HEADHUNTER_LINK", nil, nil, url)
end

-- Reload the UI (a click, after a yes) so the game saves our results for HeadHunter Sync
function MainWindow:SendToWebsite()
    local unsent = ns.Matches:Unsent()
    if unsent == 0 then return false end
    if not StaticPopupDialogs.HEADHUNTER_SEND then
        StaticPopupDialogs.HEADHUNTER_SEND = {
            button1 = YES or "Yes",
            button2 = NO or "No",
            OnAccept = function() ReloadUI() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopupDialogs.HEADHUNTER_SEND.text = string.format(L.EVENT_SEND_CONFIRM, unsent)
    StaticPopup_Show("HEADHUNTER_SEND")
    return true
end

function MainWindow:SelectSection(id)
    for _, section in ipairs(self.SECTIONS) do
        if section.id == id then
            self:SelectTab(current.lastView[id] or section.views[1])
            return
        end
    end
end

function MainWindow:SelectTab(tab)
    tab = self.OLD_TABS[tab] or tab
    local section = self.SectionOf(tab)
    local known = false
    for _, view in ipairs(section.views) do known = known or view == tab end
    if not known then tab = section.views[1] end
    current.tab = tab
    current.lastView[section.id] = tab
    current.event, current.round = nil, nil
    if frame and frame.scroll.SetVerticalScroll then frame.scroll:SetVerticalScroll(0) end
    -- The box shows this tab's own search
    if frame and self.SEARCH_TABS[tab] then
        frame.search:SetText(current.searches[tab] or "")
        frame.search.hint:SetShown(current.searches[tab] == nil)
        frame.search.clear:SetShown(current.searches[tab] ~= nil)
    end
    self:Refresh()
end

-- The search of the tab on show; empty or only spaces shows the whole list
function MainWindow:SetSearch(text)
    if not self.SEARCH_TABS[current.tab] then return end
    text = (text or ""):match("^%s*(.-)%s*$")
    local search = text ~= "" and text or nil
    if search == current.searches[current.tab] then return end
    current.searches[current.tab] = search
    if frame and frame.scroll.SetVerticalScroll then frame.scroll:SetVerticalScroll(0) end
    self:Refresh()
end

-- The x in the box: empties the search of the tab on show
function MainWindow:ClearSearch()
    if not frame then return end
    frame.search:SetText("")
    frame.search:ClearFocus()
    frame.search.hint:Show()
    frame.search.clear:Hide()
    self:SetSearch("")
end

function MainWindow:Search()
    return self.SEARCH_TABS[current.tab] and current.searches[current.tab] or nil
end

function MainWindow:SetSort(sortKey)
    current.sort = sortKey
    self:Refresh()
end

-- Duels' switch: ALL, "Alliance" or "Horde"
function MainWindow:DuelFaction()
    return current.duelFaction
end

-- The Bounty board's switch (WANTED, Bullies and Deadbeats): ALL, "Alliance" or "Horde"
function MainWindow:BoardFaction()
    return current.boardFaction
end

-- The switch's choice on the tab on show, nil on tabs without the switch
function MainWindow:FactionChoice()
    if self.BOARD_TABS[current.tab] then return current.boardFaction end
    if current.tab == "duels" then return current.duelFaction end
    return nil
end

-- The faction list of the tab on show: nil for All and on tabs without the switch
function MainWindow:ListFaction()
    local choice = self:FactionChoice()
    return choice ~= self.ALL and choice or nil
end

-- Shows ALL or a faction's list on the tab on show
function MainWindow:SetFaction(faction)
    if self.BOARD_TABS[current.tab] then
        current.boardFaction = faction
    elseif current.tab == "duels" then
        current.duelFaction = faction
    else
        return
    end
    if frame and frame.scroll.SetVerticalScroll then frame.scroll:SetVerticalScroll(0) end
    self:Refresh()
end

-- The next list on the switch: All, Alliance, Horde, then All again
function MainWindow:SwitchFaction()
    local order = { [self.ALL] = "Alliance", Alliance = "Horde", Horde = self.ALL }
    local choice = self:FactionChoice()
    if choice then self:SetFaction(order[choice] or self.ALL) end
end

function MainWindow:Current()
    return current.tab, current.sort
end

-- A row opens the outlaw's poster (HH-061), or the event (Events)
function MainWindow:OnRowClick(data)
    if data and data.event then
        self:ShowEvent(data.event)
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
            "HH_HIGHNOON_UPDATED", "HH_BOUNTY_UPDATED", "HH_MATCHES_CHANGED", "HH_GLASS_ADDED" }) do
        ns.Events:Register(event, request, OWNER)
    end
    -- New duels while the Duels tab is open: its lists are counted again (HH-137)
    local onDuels = function()
        if current.tab == "duels" then MainWindow:RequestRefresh() end
    end
    ns.Events:Register("HH_DUEL_ADDED", onDuels, OWNER)
    ns.Events:Register("HH_DUEL_UPDATED", onDuels, OWNER)
end, OWNER)

-- /hh with no arguments opens the window (see Core/SlashCommands.lua)
ns.SlashCommands:Register("show", function() MainWindow:Toggle() end, L.HELP_SHOW)
