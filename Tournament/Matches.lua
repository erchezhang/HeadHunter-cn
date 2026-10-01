-- Tournament matches in game (author, 2026-10-01). The host or a co-organizer calls a
-- match of the round being played from the event view (UI/MainWindow.lua): both
-- players get an alert and a whisper (the whisper reaches players without the addon
-- too) with PREPARE seconds to be at the venue and say they are ready: the Ready button,
-- or a whisper with "ready". When both are ready they are told to duel. Every duel
-- between the two is a game (Sync/Duels.lua HH_DUEL_RESULT; the players' own addons
-- report their games too, which counts on Forever where nobody else sees the result).
-- When a side has the wins its series needs, the organizer confirms the score. The
-- confirmed result moves the winner on for every HeadHunter and is kept for the website
-- (ns.db.eventResults; HeadHunter Sync sends our own to the website).
-- Who may call and confirm comes only from the website data
-- (Organizers.IsOrganizerOf), never from a player's own message. Duels happen inside one
-- faction: team, Gurubashi and both-faction matches get their result by hand
-- (UI/ResultDialog.lua), like any score the organizer changes.
--
-- Protocol type M (Sync/Protocol.lua EncodeMatch):
--   C call      organizer -> both players (addon whisper)
--   D duel now  organizer -> both players, once both are ready
--   R ready     player -> organizer
--   G game      player -> organizer
--   F result    organizer -> both players and every HeadHunter (automatic routes)

local addonName, ns = ...
local L = ns.L

local Matches = ns:RegisterModule("Matches", {})

local OWNER = "Matches"

Matches.PREPARE = 180      -- seconds to be ready (author, 2026-10-01)
Matches.GAME_DEDUPE = 10   -- reports of one game from both players and the organizer
Matches.TICK = 5           -- the event view's countdown

local unsent = 0  -- results we confirmed since the last reload: saved to disk only at a reload
local calls = {}  -- organizer: match id -> { t, round, match, a, b, aKey, bKey, readyBy, ready, go, wins, games }
local mine        -- player: { tid, round, match, organizer, opponent, readyBy, ready }

local function Me()
    return ns.Utils.UnitKey("player")
end

function Matches.Id(tid, round, match)
    return tid .. ":" .. round .. ":" .. match
end

local function Changed()
    ns.Events:Fire("HH_MATCHES_CHANGED")
end

local function Results()
    return ns.db and ns.db.eventResults or {}
end

-- The scores a series can end with, as the website's form offers them:
-- { { winsA, winsB } }, the winner first reaching the wins needed
function Matches.Scores(bestOf)
    local need = ns.Brackets.WinsNeeded(bestOf)
    local list = {}
    for lost = 0, need - 1 do list[#list + 1] = { need, lost } end
    for lost = need - 1, 0, -1 do list[#list + 1] = { lost, need } end
    return list
end

-- The results confirmed in game for one tournament, for Tournaments.Bracket
function Matches:Results(tid)
    local list = {}
    for _, r in pairs(Results()) do
        if r.tournament == tid then list[#list + 1] = r end
    end
    table.sort(list, function(x, y) return (x.t or 0) < (y.t or 0) end)
    return list
end

-- A match of a tournament's bracket, with its round's series
local function BracketMatch(t, round, number)
    local rounds = ns.Tournaments.Bracket(t)
    local r = rounds[round]
    return r and r.matches[number], r and r.bestOf, rounds
end

local function KeyOf(t, entrant)
    local person = entrant and t.people and t.people[entrant]
    return person and person.key or nil
end

local function Target(key)
    return ns.Utils.DisplayName(key)
end

function Matches.IsOrganizer(t)
    return ns.Organizers.IsOrganizerOf(t, Me())
end

-- The live state of a match for the event view: the organizer's call, or our own
function Matches:Call(tid, round, match)
    return calls[Matches.Id(tid, round, match)]
end

function Matches:Mine()
    return mine
end

-------------------------------------------------
-- Organizer
-------------------------------------------------

-- Calls a match: alert + whisper to both players, PREPARE seconds to get ready. A click.
function Matches:CallMatch(t, round, number)
    if not Matches.IsOrganizer(t) then return false end
    local m, bestOf = BracketMatch(t, round, number)
    if not m or m.bye or not (m.a and m.b) or m.winner then return false end
    local U, P = ns.Utils, ns.Protocol
    local id = Matches.Id(t.id, round, number)
    local readyBy = U.ServerTime() + self.PREPARE
    calls[id] = {
        tid = t.id, round = round, match = number, a = m.a, b = m.b, aKey = KeyOf(t, m.a), bKey = KeyOf(t, m.b),
        bestOf = bestOf or 1, readyBy = readyBy, ready = {}, wins = { a = 0, b = 0 }, games = {},
    }
    local call = calls[id]
    local record = P.EncodeMatch("C", t.id, round, number, readyBy)
    local roundName = ns.Tournaments.RoundName(round, #ns.Tournaments.Bracket(t))
    for _, side in ipairs({ "a", "b" }) do
        local key = call[side .. "Key"]
        if key then
            ns.Transport:SendDirect(P.TYPES.MATCH, { record }, Target(key))
            local opponent = ns.Tournaments.SideName(t, side == "a" and m.b or m.a) or "?"
            pcall(SendChatMessage, string.format(L.EVENT_CALL_WHISPER, t.name, roundName, opponent,
                ns.Tournaments.Where(t), math.floor(self.PREPARE / 60)), "WHISPER", nil, Target(key))
        end
    end
    Changed()
    return true
end

local function SideOf(call, key)
    local U = ns.Utils
    if call.aKey and U.SameCharacter(call.aKey, key) then return "a" end
    if call.bKey and U.SameCharacter(call.bKey, key) then return "b" end
    return nil
end

function Matches:MarkReady(call, side)
    if not side or call.ready[side] then return end
    call.ready[side] = true
    if call.ready.a and call.ready.b and not call.go then
        call.go = true
        local record = ns.Protocol.EncodeMatch("D", call.tid, call.round, call.match)
        for _, key in ipairs({ call.aKey, call.bKey }) do
            ns.Transport:SendDirect(ns.Protocol.TYPES.MATCH, { record }, Target(key))
        end
    end
    Changed()
end

-- A game between the two sides of a called match (from the duel we saw or a report)
function Matches:AddGame(call, winnerKey, t)
    local side = SideOf(call, winnerKey)
    if not side or call.decided then return false end
    t = t or ns.Utils.ServerTime()
    local last = call.games[#call.games]
    if last and math.abs(t - last.t) < self.GAME_DEDUPE then return false end
    call.games[#call.games + 1] = { winner = side, t = t }
    call.wins[side] = call.wins[side] + 1
    if call.wins[side] >= ns.Brackets.WinsNeeded(call.bestOf) then call.decided = side end
    Changed()
    return true
end

-- Confirms a match's result (the decided games, a changed score, or a no-show with
-- forfeit = the side that did not come). Checked as the website checks it. A click.
function Matches:Confirm(t, round, number, winsA, winsB, forfeit)
    if not Matches.IsOrganizer(t) then return false, "organizer" end
    local m, bestOf, rounds = BracketMatch(t, round, number)
    if not m or m.bye or not (m.a and m.b) then return false, "match" end
    if ns.Brackets.NextIsPlayed(rounds, round, number) then return false, "locked" end
    if forfeit then
        winsA, winsB = 0, 0
    else
        local valid = false
        for _, s in ipairs(Matches.Scores(bestOf)) do valid = valid or (s[1] == winsA and s[2] == winsB) end
        if not valid then return false, "score" end
    end
    local U, P = ns.Utils, ns.Protocol
    local id = Matches.Id(t.id, round, number)
    local result = { tournament = t.id, round = round, match = number, a = m.a, b = m.b, winsA = winsA, winsB = winsB,
        forfeit = forfeit, t = U.ServerTime(), organizer = Me(), origin = "local" }
    if ns.db then ns.db.eventResults[id] = result end
    local record = P.EncodeMatch("F", t.id, round, number, m.a, m.b, winsA, winsB, forfeit or "", result.t)
    ns.Transport:Queue(P.TYPES.MATCH, record, ns.Transport.PRIORITY.alert, "M:" .. id)
    for _, key in ipairs({ KeyOf(t, m.a), KeyOf(t, m.b) }) do
        if key then ns.Transport:SendDirect(P.TYPES.MATCH, { record }, Target(key)) end
    end
    calls[id] = nil
    unsent = unsent + 1
    ns:Print(L.EVENT_SAVED_HINT)
    Changed()
    return true
end

-- Results we confirmed that the website does not have yet (author, 2026-10-01): the game
-- writes them to disk only at a reload or logout, and HeadHunter Sync sends them then
function Matches:Unsent()
    return unsent
end

-------------------------------------------------
-- Player
-------------------------------------------------

function Matches:OnCall(tid, round, number, readyBy, sender)
    local t = ns.Tournaments:Get(tid)
    if not t or not ns.Organizers.IsOrganizerOf(t, ns.Utils.PlayerKey(sender)) then return end
    local m = BracketMatch(t, round, number)
    if not m then return end
    local U = ns.Utils
    local me = Me()
    local aKey, bKey = KeyOf(t, m.a), KeyOf(t, m.b)
    local opponent = (aKey and U.SameCharacter(aKey, me) and bKey) or (bKey and U.SameCharacter(bKey, me) and aKey)
    if not opponent then return end
    mine = { tid = tid, round = round, match = number, organizer = sender, opponent = opponent, readyBy = readyBy }
    local name = Target(opponent)
    local minutes = math.max(1, math.ceil((readyBy - U.ServerTime()) / 60))
    ns.Alerts:Show({
        key = "call:" .. Matches.Id(tid, round, number),
        throttle = 5,
        text = string.format(L.EVENT_CALLED_CENTER, name),
        chat = string.format(L.EVENT_CALLED_CHAT, t.name, name, ns.Tournaments.Where(t), minutes),
        sound = true,
        popup = {
            dialog = ns.Alerts.TOUR_POPUP,
            text = string.format(L.EVENT_CALLED_POPUP, t.name, name, ns.Tournaments.Where(t), minutes),
            accept = L.EVENT_READY,
            decline = L.EVENT_LATER,
            onAccept = function() Matches:Ready() end,
        },
    })
    Changed()
end

-- We are ready for our called match
function Matches:Ready()
    if not mine then
        ns:Print(L.EVENT_NOT_CALLED)
        return false
    end
    mine.ready = true
    ns.Transport:SendDirect(ns.Protocol.TYPES.MATCH,
        { ns.Protocol.EncodeMatch("R", mine.tid, mine.round, mine.match) }, mine.organizer)
    ns:Print(L.EVENT_READY_SENT)
    Changed()
    return true
end

function Matches:OnGo()
    if not mine then return end
    local name = Target(mine.opponent)
    ns.Alerts:Show({
        key = "go:" .. Matches.Id(mine.tid, mine.round, mine.match),
        throttle = 5,
        text = string.format(L.EVENT_GO_CENTER, name),
        chat = string.format(L.EVENT_GO_CHAT, name),
        sound = true,
        popup = {
            dialog = ns.Alerts.TOUR_POPUP,
            text = string.format(L.EVENT_GO_CHAT, name),
            accept = L.EVENT_DUEL,
            decline = L.EVENT_LATER,
            onAccept = function() Matches:Challenge() end,
        },
    })
end

-- Challenges our opponent to a duel (the popup click)
function Matches:Challenge()
    if not mine then return false end
    local ok = pcall(StartDuel, Target(mine.opponent))
    if not ok then ns:Print(string.format(L.EVENT_DUEL_HINT, Target(mine.opponent))) end
    return ok
end

function Matches:OnResult(tid, round, number, a, b, winsA, winsB, forfeit, t, sender)
    local tournament = ns.Tournaments:Get(tid)
    if not tournament or not ns.Organizers.IsOrganizerOf(tournament, ns.Utils.PlayerKey(sender)) then return end
    if not ns.db then return end
    local id = Matches.Id(tid, round, number)
    local known = ns.db.eventResults[id]
    if known and (known.t or 0) >= t then return end
    ns.db.eventResults[id] = { tournament = tid, round = round, match = number, a = a, b = b, winsA = winsA,
        winsB = winsB, forfeit = forfeit, t = t, organizer = ns.Utils.PlayerKey(sender), origin = "peer" }
    if mine and mine.tid == tid and mine.round == round and mine.match == number then
        mine = nil
        ns:Print(string.format(L.EVENT_RESULT_CHAT, tournament.name, ns.Tournaments.SideName(tournament, a) or a,
            forfeit and L.EVENT_FF or (winsA .. " - " .. winsB), ns.Tournaments.SideName(tournament, b) or b))
    end
    calls[id] = nil
    Changed()
end

-------------------------------------------------
-- Messages, duels, whispers
-------------------------------------------------

function Matches:OnRecord(record, sender)
    local kind, tid, round, number, f5, f6, f7, f8, f9, f10 = ns.Protocol.DecodeMatch(record)
    if not kind then return end
    local B36 = ns.Protocol.FromB36
    if kind == "C" then
        local readyBy = B36(f5)
        if readyBy then self:OnCall(tid, round, number, readyBy, sender) end
    elseif kind == "D" then
        if mine and mine.tid == tid and mine.round == round and mine.match == number then self:OnGo() end
    elseif kind == "R" then
        local call = calls[Matches.Id(tid, round, number)]
        if call then self:MarkReady(call, SideOf(call, ns.Utils.PlayerKey(sender))) end
    elseif kind == "G" then
        local call = calls[Matches.Id(tid, round, number)]
        -- Only the two players report their games; the organizer confirms in the end
        if call and SideOf(call, ns.Utils.PlayerKey(sender)) then self:AddGame(call, f5, B36(f6)) end
    elseif kind == "F" then
        local winsA, winsB, t = B36(f7), B36(f8), B36(f10)
        if f5 ~= "" and f6 ~= "" and winsA and winsB and t then
            self:OnResult(tid, round, number, f5, f6, winsA, winsB, (f9 == "a" or f9 == "b") and f9 or nil, t, sender)
        end
    end
end

-- A duel ended between winner and loser (every result, fair or not)
function Matches:OnDuel(winner, loser)
    local U = ns.Utils
    local now = U.ServerTime()
    for _, call in pairs(calls) do
        local w, l = SideOf(call, winner), SideOf(call, loser)
        if w and l and w ~= l then self:AddGame(call, winner, now) end
    end
    if mine and (U.SameCharacter(winner, mine.opponent) or U.SameCharacter(loser, mine.opponent))
            and (U.SameCharacter(winner, Me()) or U.SameCharacter(loser, Me())) then
        ns.Transport:SendDirect(ns.Protocol.TYPES.MATCH,
            { ns.Protocol.EncodeMatch("G", mine.tid, mine.round, mine.match, winner, now) }, mine.organizer)
    end
end

-- A whisper from a called player saying "ready" (players without the addon)
function Matches:OnWhisper(text, sender)
    if type(text) ~= "string" or not text:lower():find("ready", 1, true) then return end
    local key = ns.Utils.PlayerKey(ns.Utils.AccessibleString(sender))
    for _, call in pairs(calls) do
        local side = key and SideOf(call, key)
        if side then self:MarkReady(call, side) end
    end
end

function Matches:Pending()
    return next(calls) ~= nil or mine ~= nil
end

-- Registered at load, so no new HH_INITIALIZED handler changes the login order
ns.Transport:RegisterHandler(ns.Protocol.TYPES.MATCH, function(record, sender) Matches:OnRecord(record, sender) end)
ns.Events:Register("HH_DUEL_RESULT", function(_, winner, loser) Matches:OnDuel(winner, loser) end, OWNER)
ns.Events:Register("CHAT_MSG_WHISPER", function(_, text, sender) Matches:OnWhisper(text, sender) end, OWNER)

-- The countdown on the event view while something is called
local function Tick()
    if Matches:Pending() then Changed() end
    C_Timer.After(Matches.TICK, Tick)
end
C_Timer.After(Matches.TICK, Tick)

-- /hh ready (not in the help): ready for our called match, when the popup is gone
ns.SlashCommands:Register("ready", function() Matches:Ready() end)
