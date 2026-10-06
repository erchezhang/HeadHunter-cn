-- WEB-080: the website's tournaments in game (author, 2026-09-30). Tournaments are made
-- and joined only on the website; HeadHunter Sync brings them in (Sync/SiteData.lua) and
-- the addon only reads them: the Tournaments tab and /hh tour list them. Check-in and
-- the matches in game come later (M9), on this same data. The tournaments players made
-- and joined in game over addon messages (HH-101 to HH-104) are gone; older addons may
-- still send them (type V), and nobody handles those any more.
--
-- Tournaments:List(now) -> the website's tournaments not over yet, soonest first
-- Tournaments.State(t, now) -> "open" | "closed" | "locked" | "running" | "finished" | "ended"
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

-- Started: running until the final is decided ("finished", also from the results
-- confirmed in game, so it shows at once) or the host ends it early ("ended", website)
function Tournaments.State(t, now)
    if now >= t.startsAt then
        if t.ended then return "ended" end
        if Tournaments.Finished(t) then return "finished" end
        return "running"
    end
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

-- Our character signed up on the website (a place or the waitlist, alone or in a team)
function Tournaments.Joined(t, key)
    key = key or ns.Utils.UnitKey("player")
    for _, joined in ipairs(t.joined or {}) do
        if ns.Utils.SameCharacter(joined, key) then return true end
    end
    return false
end

-- Still to come: not started yet (the count on the Events tab in the header)
function Tournaments:UpcomingCount(now)
    now = now or ns.Utils.ServerTime()
    local count = 0
    for _, t in ipairs(self:List(now)) do
        if now < t.startsAt then count = count + 1 end
    end
    return count
end

-- Being played now: a blinking dot on the Ongoing tab
function Tournaments:OngoingCount(now)
    now = now or ns.Utils.ServerTime()
    local count = 0
    for _, t in ipairs(self:List(now)) do
        if Tournaments.Ongoing(t, now) then count = count + 1 end
    end
    return count
end

-- Events tab (author, 2026-10-01): being played now, still to come, or over
function Tournaments.Ongoing(t, now)
    return Tournaments.State(t, now) == "running"
end

function Tournaments.Over(t, now)
    local state = Tournaments.State(t, now)
    return state == "finished" or state == "ended"
end

-- The website says it is over, or the final (and the match for 3rd place when it is
-- on) has a result here (author, 2026-10-01)
function Tournaments.Finished(t)
    if t.finished or t.ended then return true end
    local rounds = Tournaments.Bracket(t)
    local last = rounds[#rounds]
    if not last or #last.matches == 0 then return false end
    for _, m in ipairs(last.matches) do
        if m.bye or not m.winner then return false end
    end
    return true
end

-- 1st, 2nd and 3rd as entrant ids: { first, second, third = {...} }, or nil while the
-- final has no result. Without a match for 3rd place both semifinal losers share it.
function Tournaments.Places(t)
    local rounds = Tournaments.Bracket(t)
    local last = rounds[#rounds]
    local final = last and last.matches[1]
    if not final or final.bye or not final.winner then return nil end
    local function Loser(m) return m.winner == "a" and m.b or m.a end
    local places = { first = final[final.winner], second = Loser(final), third = {} }
    local third = last.matches[2]
    if third and third.thirdPlace then
        if third.winner then places.third[1] = third[third.winner] end
    elseif #rounds > 1 then
        for _, m in ipairs(rounds[#rounds - 1].matches) do
            if m.winner and not m.bye then places.third[#places.third + 1] = Loser(m) end
        end
    end
    return places
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

-- A side as the event view shows it (author, 2026-10-01): like the other lists, faction
-- crest, race icon, the name in its class color, class icon; a team's name after its
-- faction crest. muted: the name in grey with the icons kept (a side that did not come)
function Tournaments.SideLabel(t, entrant, muted)
    local name = Tournaments.SideName(t, entrant)
    local person = name and t.people[entrant]
    if not person then return name and muted and ("|cff808080" .. name .. "|r") or name end
    if person.team then
        local crest = ns.MainWindow.FactionIcon(person.faction or t.faction)
        return (crest ~= "" and (crest .. " ") or "") .. (muted and ("|cff808080" .. name .. "|r") or name)
    end
    local faction = person.faction or ns.Utils.RaceFaction(person.race) or t.faction
    return ns.MainWindow.Labeled(name, person, faction, muted)
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
