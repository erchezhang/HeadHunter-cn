-- WEB-080: the website's tournaments in game (author, 2026-09-30). Tournaments are made
-- and joined only on the website; HeadHunter Sync brings them in (Sync/SiteData.lua) and
-- the addon only reads them: the Tournaments tab and /hh tour list them. Check-in and
-- the matches in game come later (M9), on this same data. The tournaments players made
-- and joined in game over addon messages (HH-101 to HH-104) are gone; older addons may
-- still send them (type V), and nobody handles those any more.
--
-- Tournaments:List(now) -> the website's tournaments not over yet, soonest first
-- Tournaments.State(t, now) -> "open" | "closed" | "locked" | "running"
-- Tournaments.Bracket(t) -> the rounds as the website builds them (Brackets.Build)

local addonName, ns = ...
local L = ns.L

local Tournaments = ns:RegisterModule("Tournaments", {})

-- A started tournament counts as running this long after its last day's start, as on
-- the website (Tournament::RUNNING_HOURS)
Tournaments.RUNNING = 6 * 3600

function Tournaments.LastStart(t)
    return t.days[#t.days]
end

function Tournaments.State(t, now)
    if now >= t.startsAt then return "running" end
    if now >= t.locksAt then return "locked" end
    if t.signupsClosed then return "closed" end
    return "open"
end

function Tournaments:List(now)
    now = now or ns.Utils.ServerTime()
    local list = {}
    for _, t in ipairs(ns.SiteData:Tournaments()) do
        if now < Tournaments.LastStart(t) + Tournaments.RUNNING then list[#list + 1] = t end
    end
    table.sort(list, function(a, b)
        if a.startsAt ~= b.startsAt then return a.startsAt < b.startsAt end
        return a.id < b.id
    end)
    return list
end

function Tournaments:Get(id, now)
    for _, t in ipairs(self:List(now)) do
        if t.id == id then return t end
    end
    return nil
end

-- Events tab (author, 2026-10-01): being played now, or still to come
function Tournaments.Ongoing(t, now)
    return Tournaments.State(t, now) == "running"
end

-- The bracket as the website builds it (Brackets.Build), with the website's results and
-- the ones confirmed in game since (Tournament/Matches.lua)
function Tournaments.Bracket(t)
    local B = ns.Brackets
    local results = {}
    for _, r in ipairs(t.results or {}) do results[#results + 1] = r end
    local live = ns.Matches and ns.Matches:Results(t.id) or {}
    for _, r in ipairs(live) do results[#results + 1] = r end
    return B.Build(B.Seed(t.drawn or {}, nil, t.bracketSeed), results,
        { bestOf = t.bestOf, finalBestOf = t.finalBestOf, thirdPlace = t.thirdPlace })
end

-- The round being played: the first with a match to play, else the last
function Tournaments.CurrentRound(rounds)
    for _, round in ipairs(rounds) do
        for _, m in ipairs(round.matches) do
            if not m.bye and m.a and m.b and not m.winner then return round.number end
        end
    end
    return #rounds > 0 and #rounds or 1
end

-- "Round 2", "Quarterfinals", "Semifinals", "Final"
function Tournaments.RoundName(number, count)
    local fromEnd = count - number
    if count > 1 and fromEnd == 0 then return L.EVENT_FINAL end
    if count > 2 and fromEnd == 1 then return L.EVENT_SEMIFINALS end
    if count > 3 and fromEnd == 2 then return L.EVENT_QUARTERFINALS end
    return string.format(L.EVENT_ROUND, number)
end

-- A side of a match to show: the player's name (short on our realm) or the team's
function Tournaments.SideName(t, entrant)
    local person = entrant and t.people and t.people[entrant]
    if not person then return nil end
    return person.key and ns.Utils.DisplayName(person.key) or person.name
end

-- A side as the event view shows it (author, 2026-10-01): race and class icons, the
-- name in its class color; a team's name as it is
function Tournaments.SideLabel(t, entrant)
    local name = Tournaments.SideName(t, entrant)
    local person = name and t.people[entrant]
    if not person or person.team then return name end
    local U = ns.Utils
    local icons = U.RaceIcon(person.race, person.sex) .. U.ClassIcon(person.class)
    return (icons ~= "" and (icons .. " ") or "") .. ns.MainWindow.ClassColored(name, person.class)
end

-- "Best of 3" or "Best of 3, final Best of 5"
function Tournaments.Series(t)
    local text = string.format(L.TOUR_BEST_OF, t.bestOf)
    if t.finalBestOf and t.finalBestOf > t.bestOf then
        text = text .. string.format(L.TOUR_FINAL_BEST_OF, t.finalBestOf)
    end
    return text
end

-- "60" or "50-59"
function Tournaments.Levels(t)
    if not t.minLevel then return "?" end
    if not t.maxLevel or t.maxLevel == t.minLevel then return tostring(t.minLevel) end
    return t.minLevel .. "-" .. t.maxLevel
end

-- "12/16" or "12" (no limit)
function Tournaments.Entrants(t)
    return t.places and (t.entrants .. "/" .. t.places) or tostring(t.entrants)
end

function Tournaments.Where(t)
    return ns.Arena.VenueName(t.venue) or t.venue
end

-- "in 25 min", "in 3 h 20 min", "in 2 d 4 h"; "started 2 h ago" once it runs
function Tournaments.Start(t, now)
    if now >= t.startsAt then return string.format(L.TOUR_STARTED, ns.Utils.Ago(now - t.startsAt)) end
    local minutes = math.ceil((t.startsAt - now) / 60)
    if minutes < 60 then return string.format(L.TOUR_IN_MIN, minutes) end
    if minutes < 1440 then return string.format(L.TOUR_IN_HOURS, math.floor(minutes / 60), minutes % 60) end
    return string.format(L.TOUR_IN_DAYS, math.floor(minutes / 1440), math.floor(minutes % 1440 / 60))
end

-- /hh tour: the website's tournaments on our world
ns.SlashCommands:Register("tour", function()
    local now = ns.Utils.ServerTime()
    local list = Tournaments:List(now)
    print(string.format(L.TOUR_HEADER, #list))
    for i, t in ipairs(list) do
        local start = Tournaments.Start(t, now)
        print(string.format(L.TOUR_LINE, i, t.name, t.teamSize, t.teamSize, Tournaments.Series(t),
            Tournaments.Where(t), start, Tournaments.Entrants(t), ns.Utils.DisplayName(t.host) or t.host or "?"))
    end
    if #list == 0 then print(L.EMPTY_UPCOMING) end
end, L.HELP_TOUR)
