-- HH-090 / HH-091: High Noon duel records (docs/addon/features.md section 10).
--
-- Detection: the game announces every duel result in chat to the players nearby
-- (CHAT_MSG_SYSTEM, the client's DUEL_WINNER_KNOCKOUT and DUEL_WINNER_RETREAT
-- strings, turned into patterns so it works in every language). Any HeadHunter nearby
-- records the duel, even when the duelists do not use the addon. A retreat counts as a
-- loss. Duels never touch WANTED.
-- WoW Forever sends no result line: there the duelists' own addons judge their duel
-- (DUEL_REQUESTED or our StartDuel, countdown or entering combat, UNIT_HEALTH,
-- DUEL_OUTOFBOUNDS, DUEL_FINISHED; see "Our own duels" below). Era does both; the pair
-- dedupe keeps one.
-- Only fair duels count: both levels known, both at least MIN_LEVEL (10), and at most
-- LEVEL_RANGE apart (author, 2026-09-23: beating lowbies must not climb the list).
-- Checked when a duel is seen, when a record arrives and when stored duels are pruned.
-- A witness finds levels on the units it can read (target, mouseover, party, raid,
-- nameplates) and on their targets: a duelist mostly targets the other one. When a
-- level is still unknown the duel waits up to LEVEL_WAIT (2 hours, author 2026-09-30)
-- until we see that player; a copy from another HeadHunter ends the wait.
--
-- ns.db.duels is a grow-only set, keyed "<winner>><loser>:<time>". Many witnesses see
-- the same duel: the same pair within DEDUPE seconds is one duel.
-- Every result we see also fires HH_DUEL_RESULT(winner, loser, retreat) at once, before
-- the fairness and dedupe rules: tournament games count every duel (Tournament/Matches.lua).
-- Duels happen inside one faction; the record says which. Other-faction HeadHunters'
-- duel records are accepted too (Transport lets only this type through), rate limited,
-- so High Noon can list both factions. Shared on the automatic routes and by login
-- catch-up (Sync/CatchUp.lua). Fires HH_DUEL_ADDED(duel), and HH_DUEL_UPDATED(duel) when a
-- relayed duel gets its second source (HH-121).

local addonName, ns = ...
local L = ns.L

local Duels = ns:RegisterModule("Duels", {})

local OWNER = "Duels"

Duels.DEDUPE = 60           -- the same pair within a minute is one duel
Duels.MAX_AGE = 90 * 86400  -- a season
Duels.MAX_COUNT = 5000
Duels.MAX_SKEW = 300
Duels.SENDER_LIMIT = 30     -- duel records accepted per sender per window
Duels.SENDER_WINDOW = 600
Duels.WITNESS_DELAY = 10    -- a witness waits up to this long and shares only if nobody did
Duels.LEVEL_RANGE = 5       -- the most levels apart two duelists can be
Duels.MIN_LEVEL = 10        -- High Noon starts at level 10 (author, 2026-09-23)
Duels.MIN_FIGHT = 2         -- seconds after the last countdown line: shorter is a cancel
Duels.PENDING = 90          -- a challenge not fought within this many seconds is dropped
Duels.LEVEL_WAIT = 2 * 3600 -- a duel with an unknown level waits this long for it
Duels.MAX_WAITING = 50

-- enUS, used when the client's strings are missing
Duels.KNOCKOUT_FORMAT = "%1$s has defeated %2$s in a duel"
Duels.RETREAT_FORMAT = "%2$s has fled from %1$s in a duel"

local byPair = {}           -- "a|b" (sorted) -> array of times, for the dedupe
local senderLog = {}
local unshared = {}         -- "a|b" -> { t, heard }: our witnessed duels waiting to be shared
local waiting = {}          -- { duel, at }: duels waiting for a level, oldest first
local patterns              -- built on first use: { { pattern, order, retreat } ... }

local function Store()
    return ns.db and ns.db.duels
end

-------------------------------------------------
-- Detection
-------------------------------------------------

-- A client format string ("%1$s has defeated %2$s in a duel", or with plain %s) as a
-- Lua pattern; order[i] = which argument capture i is
function Duels.Pattern(format)
    local pattern, order, pos = "^", {}, 1
    while true do
        local s, e, index = format:find("%%(%d*)%$?s", pos)
        local literal = format:sub(pos, s and s - 1 or nil)
        pattern = pattern .. (literal:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
        if not s then break end
        order[#order + 1] = tonumber(index) or (#order + 1)
        pattern = pattern .. "(.+)"
        pos = e + 1
    end
    return pattern .. "$", order
end

local function Patterns()
    if patterns then return patterns end
    patterns = {}
    for _, item in ipairs({ { DUEL_WINNER_KNOCKOUT or Duels.KNOCKOUT_FORMAT, false },
            { DUEL_WINNER_RETREAT or Duels.RETREAT_FORMAT, true } }) do
        local pattern, order = Duels.Pattern(item[1])
        patterns[#patterns + 1] = { pattern = pattern, order = order, retreat = item[2] }
    end
    return patterns
end

-- A system message: winner, loser, retreat; or nil when it is not a duel result
function Duels.Parse(message)
    if type(message) ~= "string" then return nil end
    for _, p in ipairs(Patterns()) do
        local captures = { message:match(p.pattern) }
        if #captures == #p.order and #captures >= 2 then
            local args = {}
            for i, value in ipairs(captures) do args[p.order[i]] = value end
            if args[1] and args[2] then return args[1], args[2], p.retreat end
        end
    end
    return nil
end

-- Unit tokens to look for the duelists (level, class, race, faction), then the targets
-- of those units: a duelist mostly targets the other one
local tokens
local function Tokens()
    if tokens then return tokens end
    local units = { "player", "target", "mouseover", "focus" }
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    tokens = {}
    for _, unit in ipairs(units) do tokens[#tokens + 1] = unit end
    for _, unit in ipairs(units) do
        if unit ~= "player" then tokens[#tokens + 1] = unit .. "target" end
    end
    return tokens
end

local function FindUnit(key)
    local U = ns.Utils
    for _, token in ipairs(Tokens()) do
        if U.UnitIsPlayer(token) and U.SameCharacter(U.UnitKey(token), key) then return token end
    end
    return nil
end

-- Players seen lately (target, mouseover, nameplates, our opponent at the countdown):
-- the duel message can come when the duelist is no longer targeted.
-- key -> { level, class, race, sex, at }
Duels.SEEN_WINDOW = 600
local seenUnits = {}

-- Also remembers the unit's target, unless `noTarget`
function Duels:RememberUnit(unit, noTarget)
    local U = ns.Utils
    if type(unit) ~= "string" or not U.UnitIsPlayer(unit) then return end
    local key = U.UnitKey(unit)
    if not key then return end
    local level = U.UnitLevel(unit)
    local old = seenUnits[key] or {}
    seenUnits[key] = {
        level = level and level >= 1 and level or old.level,
        class = U.UnitClass(unit) or old.class,
        race = U.UnitRace(unit) or old.race,
        sex = U.UnitSex(unit) or old.sex,
        at = U.Now(),
    }
    self:CheckWaiting(key)
    if not noTarget then self:RememberUnit(unit .. "target", true) end
end

local function Seen(key)
    local seen = seenUnits[key]
    return seen and ns.Utils.Now() - seen.at < Duels.SEEN_WINDOW and seen or {}
end

-- A duelist's level, class, race and sex: from a visible unit, else seen lately, else
-- the enemy cache. The level is nil when unknown (a skull, -1, is unknown too: only
-- "10+ above us").
local function Profile(key, unit)
    local U = ns.Utils
    local seen, enemy = Seen(key), ns.EnemyCache:ByKey(key) or {}
    local level = unit and U.UnitLevel(unit)
    if not level or level < 1 then level = seen.level or tonumber(enemy.level) end
    return {
        level = level and level >= 1 and level or nil,
        class = unit and U.UnitClass(unit) or seen.class or enemy.class,
        race = unit and U.UnitRace(unit) or seen.race or enemy.race,
        sex = unit and U.UnitSex(unit) or seen.sex or enemy.sex,
    }
end

-- Both levels known, both MIN_LEVEL or higher, and at most LEVEL_RANGE apart
function Duels.Fair(duel)
    local a, b = tonumber(duel.winnerLevel), tonumber(duel.loserLevel)
    return a ~= nil and b ~= nil and a >= Duels.MIN_LEVEL and b >= Duels.MIN_LEVEL
        and math.abs(a - b) <= Duels.LEVEL_RANGE
end

-- Whose duel was it? A duelist we can see tells; one the enemy cache knows is the
-- other faction; otherwise our own (duels nearby are mostly our faction's).
function Duels.FactionOf(winner, loser, winnerUnit, loserUnit)
    local U = ns.Utils
    local unit = winnerUnit or loserUnit
    local faction = unit and U.UnitFaction(unit)
    if faction then return faction end
    local mine = U.UnitFaction("player")
    if ns.EnemyCache:ByKey(winner) or ns.EnemyCache:ByKey(loser) then
        return mine == "Alliance" and "Horde" or (mine == "Horde" and "Alliance" or nil)
    end
    return mine
end

-- The countdown ("Duel starting: 3"): a duel of ours begins
local function IsCountdown(message)
    local format = DUEL_COUNTDOWN or "Duel starting: %d"
    local pattern = "^" .. format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%d", "%%d+") .. "$"
    return message:find(pattern) ~= nil
end

function Duels:OnSystemMessage(message)
    if not ns.Guards:IsActive() or type(message) ~= "string" then return nil end
    local winnerName, loserName, retreat = Duels.Parse(message)
    if not winnerName then
        if IsCountdown(message) then
            self:OnOwnDuelStart()
        elseif message:lower():find("duel", 1, true) then
            ns:Debug("Duel message not understood:", message)
        end
        return nil
    end
    return self:OnResultLine(winnerName, loserName, retreat)
end

-------------------------------------------------
-- Our own duels: the opponent is the challenger (DUEL_REQUESTED), the one we challenged
-- (StartDuel) or our target when the fight starts. Forever's result line has given
-- names only ("Rot has defeated Dampa in a duel", 2026-09-24) and comes after
-- DUEL_FINISHED, so at DUEL_FINISHED we wait RESULT_WAIT seconds for it; without one,
-- the one at 1 HP lost and leaving the duel area (DUEL_OUTOFBOUNDS) is a retreat.
-- On Era the result line has full names; the pair dedupe keeps one duel.
-------------------------------------------------

Duels.RESULT_WAIT = 2

local own = nil            -- { opponent = key, fled = bool, low = { [key] = true } }
local finished = nil       -- our duel waiting for its result line: { me, opponent }

local function GivenName(key)
    return type(key) == "string" and (key:match("^(%S+) ") or key):lower() or nil
end

-- A name from a result line as a key. Forever's line has given names only: matched
-- against our own duel, else against a single nearby player with that given name.
function Duels:ResolveName(name)
    local U = ns.Utils
    local key = U.PlayerKey(name)
    if key or not ns.Features.RealmlessNames or type(name) ~= "string" then return key end
    local given = name:lower()
    local pair = finished or own
    for _, candidate in ipairs({ U.UnitKey("player"), pair and pair.opponent }) do
        if GivenName(candidate) == given then return candidate end
    end
    local found
    local function Check(token)
        if not U.UnitIsPlayer(token) then return true end
        local k = U.UnitKey(token)
        if k and GivenName(k) == given then
            if found and not U.SameCharacter(found, k) then return false end -- two of them: unsure
            found = k
        end
        return true
    end
    for _, token in ipairs(Tokens()) do if not Check(token) then return nil end end
    return found
end

local function IsPair(duel, a, b)
    local U = ns.Utils
    return duel and duel.opponent and ((U.SameCharacter(a, duel.opponent) and U.SameCharacter(b, U.UnitKey("player")))
        or (U.SameCharacter(b, duel.opponent) and U.SameCharacter(a, U.UnitKey("player"))))
end

function Duels:OnResultLine(winnerName, loserName, retreat)
    local winner, loser = self:ResolveName(winnerName), self:ResolveName(loserName)
    if not (winner and loser) then
        ns:Debug("Duel result, players not known:", winnerName, ">", loserName)
        return nil
    end
    -- Our own duel: the line decides, not our health judgement
    if IsPair(finished, winner, loser) then finished = nil end
    if IsPair(own, winner, loser) then own.decided = true end
    ns.Events:Fire("HH_DUEL_RESULT", winner, loser, retreat)
    return self:Record(winner, loser, retreat)
end

local function Health(unit)
    local U = ns.Utils
    return tonumber(U.Accessible(U.SafeCall(_G.UnitHealth, unit)))
end

local function OpponentFromTarget()
    local U = ns.Utils
    if not U.UnitIsPlayer("target") then return nil end
    local key = U.UnitKey("target")
    if not key or U.SameCharacter(key, U.UnitKey("player")) then return nil end
    Duels:RememberUnit("target")
    return key
end

-- Remember our opponent from any unit that shows them (we may target someone else)
local function RememberOpponent()
    local unit = own and own.opponent and FindUnit(own.opponent)
    if unit then Duels:RememberUnit(unit) end
end

-- Someone challenged us
function Duels:OnDuelRequested(name)
    own = { opponent = ns.Utils.PlayerKey(name), low = {}, at = ns.Utils.Now() }
    RememberOpponent()
    ns:Debug("Duel requested by", tostring(own.opponent))
end

-- We challenged someone (StartDuel from the unit menu or /duel): the opponent is the
-- unit or name passed, else our target
function Duels:OnChallenge(who)
    local U = ns.Utils
    local opponent
    if type(who) == "string" and U.UnitIsPlayer(who) then
        opponent = U.UnitKey(who)
        Duels:RememberUnit(who)
    elseif type(who) == "string" and who ~= "" then
        opponent = U.PlayerKey(who)
    end
    own = { opponent = opponent or OpponentFromTarget(), low = {}, at = U.Now() }
    RememberOpponent()
    ns:Debug("Duel challenge sent to", tostring(own.opponent))
end

-- The fight begins: a countdown line, or (when the client sends none) entering combat
-- while a duel is pending. The fight starts about a second after the last countdown line.
-- A challenge nobody answered (declined without DUEL_FINISHED, or timed out) goes stale
local function DropStale()
    if own and not own.countdownAt and own.at and ns.Utils.Now() - own.at > Duels.PENDING then own = nil end
end

function Duels:OnOwnDuelStart()
    DropStale()
    own = own or { low = {} }
    own.opponent = own.opponent or OpponentFromTarget()
    RememberOpponent() -- level, class, race and sex, in case we lose sight of them before the end
    own.countdownAt = ns.Utils.Now()
    ns:Debug("Duel countdown against", tostring(own.opponent))
end

function Duels:OnCombatStart()
    DropStale()
    if not own or own.countdownAt then return end
    own.opponent = own.opponent or OpponentFromTarget()
    RememberOpponent()
    -- No countdown seen: the fight is on now, so it counts from MIN_FIGHT back
    own.countdownAt = ns.Utils.Now() - Duels.MIN_FIGHT
    ns:Debug("Duel fight started (combat) against", tostring(own.opponent))
end

-- UNIT_HEALTH during our duel: remember who dropped to 1 HP (health comes back later),
-- and the opponent's level whenever they show up as a unit
function Duels:OnHealth(unit)
    if not own then return end
    local U = ns.Utils
    if unit ~= "player" and unit ~= "target" and not (unit and unit:find("^nameplate")) then return end
    local key = U.UnitKey(unit)
    if unit ~= "player" and key and own.opponent and U.SameCharacter(key, own.opponent) then
        Duels:RememberUnit(unit)
    end
    local hp = Health(unit)
    if hp and hp <= 1 and key then own.low[key] = true end
end

function Duels:OnDuelFinished()
    local duel = own
    own = nil
    if not duel or not ns.Guards:IsActive() then return nil end
    local U = ns.Utils
    -- Cancelled before or right at the start (no countdown, or finished within it)
    if not duel.countdownAt or U.Now() - duel.countdownAt < Duels.MIN_FIGHT then
        ns:Debug("Duel cancelled, not counted")
        return nil
    end
    local me = U.UnitKey("player")
    local opponent = duel.opponent or OpponentFromTarget()
    if not (me and opponent) then
        ns:Debug("Duel finished, opponent unknown")
        return nil
    end
    if duel.decided then return nil end -- the result line came first and recorded it
    local opponentUnit = FindUnit(opponent)
    local meLow = duel.low[me] or (Health("player") or 2) <= 1
    local opponentLow = duel.low[opponent] or (opponentUnit and (Health(opponentUnit) or 2) <= 1)
    local winner, loser, retreat
    if duel.fled then
        winner, loser, retreat = opponent, me, true
    elseif meLow then
        winner, loser, retreat = opponent, me, false
    else
        -- We stand: they went down (maybe unseen: enemy health can be hidden) or ran away
        winner, loser, retreat = me, opponent, not opponentLow
    end
    -- The result line usually follows: it gets RESULT_WAIT seconds to decide instead
    local wait = { opponent = opponent }
    finished = wait
    C_Timer.After(Duels.RESULT_WAIT, function()
        if finished ~= wait then return end
        finished = nil
        ns:Debug("Duel: no result line, judged by health")
        ns.Events:Fire("HH_DUEL_RESULT", winner, loser, retreat)
        Duels:Record(winner, loser, retreat)
    end)
    return nil
end

-- A duel result from any source we saw ourselves: store it and share it
function Duels:Record(winner, loser, retreat)
    local U = ns.Utils
    if not (winner and loser) then return nil end
    local winnerUnit, loserUnit = FindUnit(winner), FindUnit(loser)
    local w, l = Profile(winner, winnerUnit), Profile(loser, loserUnit)
    local duel = {
        winner = winner, loser = loser, t = U.ServerTime(), retreat = retreat or nil,
        mapID = ns.Zones.ZoneOf(U.PlayerMapID()),
        faction = Duels.FactionOf(winner, loser, winnerUnit, loserUnit),
        winnerClass = w.class, winnerRace = w.race, winnerSex = w.sex, winnerLevel = w.level,
        loserClass = l.class, loserRace = l.race, loserSex = l.sex, loserLevel = l.level,
    }
    if not (duel.winnerLevel and duel.loserLevel) then
        self:Wait(duel)
        return nil
    end
    return self:Keep(duel)
end

-- A duel with both levels: store and share it when it is fair
function Duels:Keep(duel, late)
    if not Duels.Fair(duel) then
        ns:Debug("Duel not counted (levels", tostring(duel.winnerLevel), "vs", tostring(duel.loserLevel) .. "):",
            duel.winner, ">", duel.loser)
        return nil
    end
    local added = self:Add(duel, "local")
    ns:Debug(added and (late and "Duel recorded (late):" or "Duel recorded:") or "Duel already known:",
        duel.winner, "(" .. duel.winnerLevel .. ") >", duel.loser, "(" .. duel.loserLevel .. ")", duel.faction)
    if added then self:Share(added) end
    return added
end

-------------------------------------------------
-- Store
-------------------------------------------------

local function PairKey(a, b)
    if a > b then a, b = b, a end
    return a .. "|" .. b
end

local function SameDuel(a, b)
    return PairKey(a.winner, a.loser) == PairKey(b.winner, b.loser) and math.abs(a.t - b.t) < Duels.DEDUPE
end

local function Expire()
    local now = ns.Utils.Now()
    for i = #waiting, 1, -1 do
        local item = waiting[i]
        if now - item.at > Duels.LEVEL_WAIT then
            table.remove(waiting, i)
            local duel = item.duel
            ns:Debug("Duel not counted (levels", tostring(duel.winnerLevel), "vs", tostring(duel.loserLevel) .. "):",
                duel.winner, ">", duel.loser)
        end
    end
end

-- A duel with an unknown level waits until we see that player
function Duels:Wait(duel)
    Expire()
    for _, item in ipairs(waiting) do
        if SameDuel(item.duel, duel) then return end
    end
    if #waiting >= self.MAX_WAITING then table.remove(waiting, 1) end
    waiting[#waiting + 1] = { duel = duel, at = ns.Utils.Now() }
    ns:Debug("Duel waiting for a level:", duel.winner, ">", duel.loser)
end

-- Fills in the missing side of a waiting duel from a player we just saw
local function Fill(duel, side, key)
    if duel[side .. "Level"] or not ns.Utils.SameCharacter(duel[side], key) then return end
    local p = Profile(key, FindUnit(key))
    duel[side .. "Level"] = p.level
    duel[side .. "Class"] = duel[side .. "Class"] or p.class
    duel[side .. "Race"] = duel[side .. "Race"] or p.race
    duel[side .. "Sex"] = duel[side .. "Sex"] or p.sex
end

function Duels:CheckWaiting(key)
    if #waiting == 0 then return end
    Expire()
    local ready = {}
    for i = #waiting, 1, -1 do
        local duel = waiting[i].duel
        Fill(duel, "winner", key)
        Fill(duel, "loser", key)
        if duel.winnerLevel and duel.loserLevel then
            table.remove(waiting, i)
            ready[#ready + 1] = duel
        end
    end
    for _, duel in ipairs(ready) do self:Keep(duel, true) end
end

function Duels:WaitingCount()
    return #waiting
end

-- HH-116: a duel next to many HeadHunters would go out once per witness. The duelists
-- share their own at once; a witness waits a random 1..WITNESS_DELAY seconds and stays
-- quiet when another copy arrived meanwhile.
function Duels:Share(duel)
    local U, Transport = ns.Utils, ns.Transport
    local function Send()
        Transport:Queue(ns.Protocol.TYPES.DUEL, ns.Protocol.EncodeDuel(duel), Transport.PRIORITY.bulk, "U:" .. duel.id)
    end
    local me = U.UnitKey("player")
    if U.SameCharacter(duel.winner, me) or U.SameCharacter(duel.loser, me) then
        Send()
        return
    end
    local key = PairKey(duel.winner, duel.loser)
    local wait = { t = duel.t }
    unshared[key] = wait
    C_Timer.After(1 + math.random() * (self.WITNESS_DELAY - 1), function()
        if unshared[key] == wait then unshared[key] = nil end
        if wait.heard then
            ns:Debug("Duel already shared by another witness:", duel.id)
            return
        end
        Send()
    end)
end

-- A peer's copy of a duel we are about to share
local function HeardFromPeer(duel)
    local wait = unshared[PairKey(duel.winner, duel.loser)]
    if wait and math.abs(wait.t - duel.t) < Duels.DEDUPE then wait.heard = true end
end

local function SeenRecently(duel)
    for _, t in ipairs(byPair[PairKey(duel.winner, duel.loser)] or {}) do
        if math.abs(t - duel.t) < Duels.DEDUPE then return true end
    end
    return false
end

local function Index(duel)
    local key = PairKey(duel.winner, duel.loser)
    byPair[key] = byPair[key] or {}
    table.insert(byPair[key], duel.t)
end

function Duels:All()
    return pairs(Store() or {})
end

function Duels:Count()
    local n = 0
    for _ in self:All() do n = n + 1 end
    return n
end

-- Returns the stored duel, or nil (a duplicate, or no database yet)
function Duels:Add(duel, origin, sender)
    local store = Store()
    if not store or not duel.winner or not duel.loser or duel.winner == duel.loser then return nil end
    if not Duels.Fair(duel) then return nil end
    if SeenRecently(duel) then return nil end
    duel.id = duel.winner .. ">" .. duel.loser .. ":" .. duel.t
    if store[duel.id] then return nil end
    duel.origin, duel.sender = origin, sender
    store[duel.id] = duel
    Index(duel)
    for i = #waiting, 1, -1 do
        if SameDuel(waiting[i].duel, duel) then table.remove(waiting, i) end
    end
    ns.Events:Fire("HH_DUEL_ADDED", duel)
    return duel
end

function Duels:Prune(now)
    local store = Store()
    if not store then return end
    local minTime = (now or ns.Utils.ServerTime()) - self.MAX_AGE
    local list = {}
    for id, duel in pairs(store) do
        if type(duel) ~= "table" or (tonumber(duel.t) or 0) < minTime or not Duels.Fair(duel) then
            store[id] = nil
        else
            list[#list + 1] = duel
        end
    end
    if #list > self.MAX_COUNT then
        table.sort(list, function(a, b) return a.t < b.t end)
        for i = 1, #list - self.MAX_COUNT do store[list[i].id] = nil end
    end
    byPair = {}
    for _, duel in pairs(store) do Index(duel) end
end

-- Duels newer than `since`, newest first, at most `limit` (login catch-up)
function Duels:Since(since, limit)
    local list = {}
    for _, duel in self:All() do
        if duel.t > since then list[#list + 1] = duel end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    for i = #list, (limit or #list) + 1, -1 do list[i] = nil end
    return list
end

-------------------------------------------------
-- Peers
-------------------------------------------------

local function UnderRateLimit(sender)
    local id = ns.Utils.CompactName(sender)
    local now = ns.Utils.Now()
    local recent = {}
    for _, at in ipairs(senderLog[id] or {}) do
        if now - at < Duels.SENDER_WINDOW then recent[#recent + 1] = at end
    end
    senderLog[id] = recent
    if #recent >= Duels.SENDER_LIMIT then return false end
    recent[#recent + 1] = now
    return true
end

-- A duel record from another HeadHunter (either faction), or relayed at login
function Duels:OnRecord(record, sender, origin)
    local duel = ns.Protocol.DecodeDuel(record)
    if not duel then return nil end
    local U = ns.Utils
    duel.winner, duel.loser = U.PlayerKey(duel.winner), U.PlayerKey(duel.loser)
    if not (duel.winner and duel.loser) then return nil end
    local now = U.ServerTime()
    if duel.t > now + self.MAX_SKEW or duel.t < now - self.MAX_AGE then return nil end
    -- A copy of a duel we have: a second source for a relayed one (HH-121)
    local have = Store() and Store()[duel.winner .. ">" .. duel.loser .. ":" .. duel.t]
    if have then
        if origin ~= "relay" then HeardFromPeer(duel) end
        local counts = origin == "relay" and ns.Relay.Vouch(have, sender, have.winner, have.loser)
            or origin ~= "relay" and ns.Relay.Confirm(have, origin or "peer", sender)
        if counts then ns.Events:Fire("HH_DUEL_UPDATED", have) end
        return nil
    end
    if origin ~= "relay" and not UnderRateLimit(sender) then return nil end
    if origin ~= "relay" then HeardFromPeer(duel) end
    if origin == "relay" then
        duel.origin = "relay"
        ns.Relay.Vouch(duel, sender, duel.winner, duel.loser)
    end
    return self:Add(duel, origin or "peer", sender)
end

ns.Events:Register("HH_INITIALIZED", function()
    Duels:Prune()
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.DUEL, function(record, sender) Duels:OnRecord(record, sender) end)
    ns.Events:Register("CHAT_MSG_SYSTEM", function(_, message) Duels:OnSystemMessage(message) end, OWNER)
    ns.Events:Register("PLAYER_TARGET_CHANGED", function() Duels:RememberUnit("target") end, OWNER)
    ns.Events:Register("UPDATE_MOUSEOVER_UNIT", function() Duels:RememberUnit("mouseover") end, OWNER)
    ns.Events:Register("NAME_PLATE_UNIT_ADDED", function(_, unit) Duels:RememberUnit(unit) end, OWNER)
    ns.Events:Register("UNIT_TARGET", function(_, unit)
        if unit ~= "player" then Duels:RememberUnit(unit) end
    end, OWNER)
    -- Our own duels (the only way on Forever)
    ns.Events:Register("DUEL_REQUESTED", function(_, name) Duels:OnDuelRequested(name) end, OWNER)
    ns.Events:Register("DUEL_OUTOFBOUNDS", function() if own then own.fled = true end end, OWNER)
    ns.Events:Register("DUEL_INBOUNDS", function() if own then own.fled = false end end, OWNER)
    ns.Events:Register("UNIT_HEALTH", function(_, unit) Duels:OnHealth(unit) end, OWNER)
    ns.Events:Register("DUEL_FINISHED", function() Duels:OnDuelFinished() end, OWNER)
    -- Forever may send no countdown line: entering combat with a duel pending starts it
    ns.Events:Register("PLAYER_REGEN_DISABLED", function() Duels:OnCombatStart() end, OWNER)
    -- Our own challenges (no event tells the challenger a duel is pending)
    if type(_G.StartDuel) == "function" and hooksecurefunc then
        hooksecurefunc("StartDuel", function(who) Duels:OnChallenge(who) end)
    end
end, OWNER)
