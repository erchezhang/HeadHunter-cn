-- M3 runtime: keeps the WANTED list derived from the shared report set.
--
-- Recomputes (Rules/Engine.lua) after reports arrive, debounced, inside a coroutine
-- that yields on a per-frame time budget (features.md section 7). A ticker catches
-- timers that run out between reports. Changes are announced as events for alerts
-- (M4) and UI (M6):
--   HH_WANTED_ADDED(entry)            an enemy became WANTED
--   HH_WANTED_RANK(entry, oldRank)    rank went up
--   HH_WANTED_EXPIRED(entry)          7 days without a kill
--   HH_WANTED_CAUGHT(entry, before)   killed by a HeadHunter or their group (HH-048),
--                                     WANTED or at large (before.atLarge)
--   HH_WANTED_UPDATED()               the list changed in any way
--
--   Wanted:Get(id), Wanted:ByKey(key), Wanted:List() (WANTED only, sorted),
--   Wanted:All() (every enemy with kills)

local addonName, ns = ...
local L = ns.L

local Wanted = ns:RegisterModule("Wanted", {})

local OWNER = "Wanted"

Wanted.DEBOUNCE = 1          -- seconds after the last report before recomputing
Wanted.BUDGET_MS = 3         -- per frame
Wanted.EXPIRY_CHECK = 60     -- seconds

local entries = {}           -- id -> entry
local computing = false
local dirty = false
local scheduled = false

function Wanted:Get(id)
    return id and entries[id]
end

function Wanted:ByKey(key)
    return key and entries[key]
end

function Wanted:All()
    return entries
end

local function RankOrder(entry)
    return entry.rank and ns.RulesEngine.RANK_ORDER[entry.rank] or 0
end

-- At large (author, 2026-09-26): WANTED ran out without a catch, newest last kill first
function Wanted:AtLarge()
    local list = {}
    for _, entry in pairs(entries) do
        if entry.atLarge then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        return (a.lastKill and a.lastKill.t or 0) > (b.lastKill and b.lastKill.t or 0)
    end)
    return list
end

-- WANTED now, or at large: an outlaw a catch still ends
function Wanted.Hunted(entry)
    return entry ~= nil and (entry.wanted or entry.atLarge) and true or false
end

-- The rank to show and pay for: the current one, or the last one while at large
function Wanted.CurrentRank(entry)
    return entry and (entry.rank or (entry.atLarge and entry.lastRank)) or nil
end

-- Currently WANTED, highest rank first, then most kills, then most recent
function Wanted:List()
    local list = {}
    for _, entry in pairs(entries) do
        if entry.wanted then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        local ra, rb = RankOrder(a), RankOrder(b)
        if ra ~= rb then return ra > rb end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return (a.lastKill and a.lastKill.t or 0) > (b.lastKill and b.lastKill.t or 0)
    end)
    return list
end

local function SerialWindow()
    local minutes = ns.db and tonumber(ns.db.settings.serialKillerWindowMin) or 15
    minutes = math.max(5, math.min(15, minutes))
    return minutes * 60
end

-- Compare old and new, fire change events
local function Publish(newEntries)
    local old = entries
    entries = newEntries
    local changed = false
    for id, entry in pairs(newEntries) do
        local before = old[id]
        if entry.wanted and not (before and before.wanted) then
            changed = true
            ns.Events:Fire("HH_WANTED_ADDED", entry)
        elseif entry.wanted and before and before.wanted and RankOrder(entry) > RankOrder(before) then
            changed = true
            ns.Events:Fire("HH_WANTED_RANK", entry, before.rank)
        elseif before and before.wanted and not entry.wanted then
            changed = true
            if entry.lastCaught and entry.lastCaught ~= before.lastCaught then
                ns.Events:Fire("HH_WANTED_CAUGHT", entry, before)
            else
                ns.Events:Fire("HH_WANTED_EXPIRED", entry)
            end
        elseif before and before.atLarge and not entry.atLarge and not entry.wanted
                and entry.caughtAtLarge and entry.caughtAtLarge ~= before.caughtAtLarge then
            changed = true
            ns.Events:Fire("HH_WANTED_CAUGHT", entry, before)
        elseif not before or (entry.wanted and entry.kills ~= before.kills)
                or (entry.atLarge or false) ~= (before.atLarge or false)
                or (entry.badges and entry.badges.coward or false) ~= (before.badges and before.badges.coward or false) then
            changed = true
        end
    end
    for id, before in pairs(old) do
        if not newEntries[id] then
            changed = true
            if before.wanted then ns.Events:Fire("HH_WANTED_EXPIRED", before) end
        end
    end
    if changed then ns.Events:Fire("HH_WANTED_UPDATED") end
end

-- HH-047 level window (features.md section 4): the WANTED popup, and the Decline
-- penalty, only for players who can really fight the outlaw: from the outlaw's level
-- - 5 to + 9 (at +10 hunting them would be ganking too). A skull outlaw (level
-- unknown, at least levelMin) has no upper bound. Unknown level: everyone.
-- /hh debug levels off turns it off for testing with high-level characters.
Wanted.LEVEL_BELOW = 5
Wanted.LEVEL_ABOVE = 9

function Wanted.LevelWindowOff()
    return ns.db ~= nil and ns.db.settings.testNoLevelWindow == true
end

function Wanted.InLevelWindow(entry, myLevel)
    if Wanted.LevelWindowOff() then return true end
    myLevel = myLevel or ns.Utils.UnitLevel("player")
    if not myLevel or myLevel < 1 then return true end
    local level = entry.level
    if not level or level == -1 then
        if not entry.levelMin then return true end
        return myLevel >= entry.levelMin - Wanted.LEVEL_BELOW
    end
    return myLevel >= level - Wanted.LEVEL_BELOW and myLevel <= level + Wanted.LEVEL_ABOVE
end

-- Testing override of the WANTED threshold (/hh debug wanted <n|off>); nil = real rule
function Wanted.TestThreshold()
    local n = ns.db and tonumber(ns.db.settings.testWantedKills)
    if n and n >= 1 and n <= 10 then return n end
    return nil
end

local function LastKillAt(entry)
    return entry.lastKill and entry.lastKill.t or 0
end

-- HH-082: the website's WANTED entries (Sync/SiteData.lua) next to ours. Theirs count
-- while their time runs, unless a catch we know of came after their last kill; when we
-- both have the outlaw WANTED, the one with the newer kill wins.
-- entries: id -> entry (changed in place); site: id -> entry; catches: id -> { t... }
function Wanted.MergeSite(entries, site, catches, now)
    for id, theirs in pairs(site or {}) do
        local caughtAfter = false
        for _, t in ipairs(catches[id] or {}) do
            if t > LastKillAt(theirs) then caughtAfter = true end
        end
        local ours = entries[id]
        if theirs.wantedUntil > now and not caughtAfter then
            if not ours or not ours.wanted or LastKillAt(theirs) > LastKillAt(ours) then
                local merged = {}
                for k, v in pairs(theirs) do merged[k] = v end
                if ours then
                    merged.guid = ours.guid
                    merged.killCount = math.max(merged.killCount or 0, ours.killCount or 0)
                    merged.cowardKills = math.max(merged.cowardKills or 0, ours.cowardKills or 0)
                end
                entries[id] = merged
            end
        end
    end
    return entries
end

-- The website's Hall of Shame bullies next to ours (author, 2026-09-28): a player we
-- know gets the bully badge and the higher bully count; one we never saw is added, not
-- WANTED. Their alerts and the +3 bounty then work as for our own bullies.
-- entries: id -> entry (changed in place); site: id -> entry (Sync/SiteData.lua)
function Wanted.MergeBullies(entries, site)
    for id, theirs in pairs(site or {}) do
        local ours = entries[id]
        if ours then
            -- A copy: a merged website or test entry shares its badges table with the source
            local badges = {}
            for k, v in pairs(ours.badges or {}) do badges[k] = v end
            badges.coward = true
            ours.badges = badges
            ours.cowardKills = math.max(ours.cowardKills or 0, theirs.cowardKills or 0)
            ours.level = ours.level or theirs.level
        else
            local copy = {}
            for k, v in pairs(theirs) do copy[k] = v end
            copy.badges = { coward = true }
            entries[id] = copy
        end
    end
    return entries
end

-- HH-118: the targets of the website's players' bounties that we never saw, added as
-- plain entries (not WANTED), so their bounty shows on the WANTED tab and the poster.
-- entries: id -> entry (changed in place); site: id -> entry (Sync/SiteData.lua)
function Wanted.MergeBountyTargets(entries, site)
    for id, theirs in pairs(site or {}) do
        if not entries[id] then
            local copy = {}
            for k, v in pairs(theirs) do copy[k] = v end
            copy.badges = {}
            entries[id] = copy
        end
    end
    return entries
end

-- Synchronous recompute (tests, and the coroutine body). The website's lists other
-- HeadHunters shared in game merge after our own download (HH-141, Sync/SharedSite.lua).
function Wanted:ComputeNow(yield)
    local reports = {}
    -- A relayed report counts only once a second source has it (HH-121)
    for _, report in ns.Reports:All() do
        if ns.Relay.Counts(report) then reports[#reports + 1] = report end
    end
    local now = ns.Utils.ServerTime()
    local catches = ns.Justice:CatchesByOutlaw()
    local result = ns.RulesEngine.Compute(reports, now,
        { serialWindow = SerialWindow(), wantedKills = Wanted.TestThreshold(), catches = catches },
        yield)
    Wanted.MergeSite(result, ns.SiteData:Wanted(), catches, now)
    -- Test entries from /hh dev (Core/Dev.lua), this client only
    Wanted.MergeSite(result, ns.Dev.TestEntries("wanted"), catches, now)
    Wanted.MergeBullies(result, ns.SiteData:Bullies())
    Wanted.MergeSite(result, ns.SharedSite:Wanted(), catches, now)
    Wanted.MergeBullies(result, ns.SharedSite:Bullies())
    Wanted.MergeBullies(result, ns.Dev.TestEntries("shame"))
    Wanted.MergeBountyTargets(result, ns.SiteData:BountyTargets())
    Wanted.FromSightings(result, function(key) return ns.EnemyCache:ByKey(key) end)
    Publish(result)
    return result
end

-- What we saw on the player themselves beats what death reports say (author,
-- 2026-10-04: another player's report made a level 30 female hunter "level 20, male"):
-- race, class and sex from our sighting, the level when we saw them after their last kill.
-- sighting: key -> the enemy cache record, or nil
function Wanted.FromSightings(entries, sighting)
    for _, entry in pairs(entries) do
        local seen = entry.key and sighting(entry.key)
        if type(seen) == "table" then
            entry.race = seen.race or entry.race
            entry.class = seen.class or entry.class
            entry.sex = seen.sex or entry.sex
            local lastKill = entry.lastKill and entry.lastKill.t or 0
            if seen.level and (not entry.level or (seen.lastSeen or 0) >= lastKill) then
                entry.level, entry.levelMin = seen.level, nil
            end
        end
    end
    return entries
end

-- Spread one recompute over frames
local function RunBudgeted()
    local co = coroutine.create(function() Wanted:ComputeNow(coroutine.yield) end)
    local function Step()
        local started = debugprofilestop()
        while coroutine.status(co) ~= "dead" do
            local ok, err = coroutine.resume(co)
            if not ok then
                ns:Error(err)
                break
            end
            if debugprofilestop() - started > Wanted.BUDGET_MS then break end
        end
        if coroutine.status(co) ~= "dead" then
            C_Timer.After(0, Step)
            return
        end
        computing = false
        if dirty then Wanted:RequestRecompute() end
    end
    Step()
end

function Wanted:RequestRecompute()
    if computing then
        dirty = true
        return
    end
    if scheduled then return end
    scheduled = true
    C_Timer.After(self.DEBOUNCE, function()
        scheduled = false
        dirty = false
        computing = true
        RunBudgeted()
    end)
end

-- Timers run out without any new report: re-check against the clock
function Wanted:CheckExpiry()
    local now = ns.Utils.ServerTime()
    for _, entry in pairs(entries) do
        if entry.wanted and entry.wantedUntil and now > entry.wantedUntil then
            self:RequestRecompute()
            return
        end
    end
end

local function ExpiryTicker()
    C_Timer.After(Wanted.EXPIRY_CHECK, function()
        Wanted:CheckExpiry()
        ExpiryTicker()
    end)
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

ns.Events:Register("HH_INITIALIZED", function()
    local request = function() Wanted:RequestRecompute() end
    ns.Events:Register("HH_REPORT_ADDED", request, OWNER)
    ns.Events:Register("HH_REPORT_UPDATED", request, OWNER)
    ns.Events:Register("HH_JUSTICE_ADDED", request, OWNER)
    ns.Events:Register("HH_JUSTICE_UPDATED", request, OWNER)
    ns.Events:Register("HH_SETTING_CHANGED", function(_, path)
        if path == "serialKillerWindowMin" or path == "testWantedKills" then request() end
    end, OWNER)
    Wanted:RequestRecompute() -- reports restored from SavedVariables
    ExpiryTicker()
end, OWNER)

-------------------------------------------------
-- Display helpers and commands
-------------------------------------------------

local BADGE_ORDER = { "coward", "gang", "duo", "serialkiller", "gunslinger", "giantslayer" }

function Wanted.RankName(rank)
    return rank and L["RANK_" .. rank:upper()] or L.RANK_NONE
end

function Wanted.BadgeNames(entry)
    local names = {}
    for _, badge in ipairs(BADGE_ORDER) do
        if entry.badges[badge] then names[#names + 1] = L["BADGE_" .. badge:upper()] end
    end
    return table.concat(names, ", ")
end

function Wanted.TimeLeft(entry, now)
    local left = (entry.wantedUntil or 0) - (now or ns.Utils.ServerTime())
    if left <= 0 then return "0m" end
    local hours = math.floor(left / 3600)
    local minutes = math.floor((left % 3600) / 60)
    if hours >= 24 then return string.format("%dd %dh", math.floor(hours / 24), hours % 24) end
    if hours > 0 then return string.format("%dh %dm", hours, minutes) end
    return string.format("%dm", minutes)
end

local function DisplayName(entry)
    if entry.key then return ns.Utils.DisplayName(entry.key) end
    return entry.name
end

ns.SlashCommands:Register("wanted", function()
    local list = Wanted:List()
    ns:Print(string.format(L.WANTED_HEADER, #list))
    local test = Wanted.TestThreshold()
    if test then ns:Print(string.format(L.WANTED_TEST_THRESHOLD, test)) end
    for i = 1, math.min(15, #list) do
        local e = list[i]
        local badges = Wanted.BadgeNames(e)
        local lastKill = e.lastKill and ns.Utils.Ago(ns.Utils.ServerTime() - e.lastKill.t) or "-"
        print(string.format(L.WANTED_LINE, Wanted.RankName(e.rank), DisplayName(e), math.floor(e.kills), lastKill,
            badges ~= "" and ("  · " .. badges) or ""))
    end
end, L.HELP_WANTED)

ns.SlashCommands:Register("outlaw", function(args)
    local query = table.concat(args, " ")
    if query == "" then
        ns:Print(L.OUTLAW_USAGE)
        return
    end
    local key = ns.Utils.PlayerKey(query)
    local entry = Wanted:ByKey(key)
    if not entry then
        -- Given-name-only entries: match by name
        for _, e in pairs(entries) do
            if (e.name or ""):lower() == query:lower() then entry = e break end
        end
    end
    if not entry then
        ns:Print(string.format(L.OUTLAW_UNKNOWN, query))
        return
    end
    ns:Print(string.format(L.OUTLAW_LINE1, DisplayName(entry), entry.wanted and Wanted.RankName(entry.rank) or L.NOT_WANTED,
        entry.wanted and Wanted.TimeLeft(entry) or "-"))
    ns:Print(string.format(L.OUTLAW_LINE2, entry.killCount, entry.exactKills, entry.guessedKills,
        entry.peakRank and Wanted.RankName(entry.peakRank) or "-", Wanted.BadgeNames(entry)))
    if entry.lastKill then
        ns:Print(string.format(L.OUTLAW_LINE3, date("%m-%d %H:%M", entry.lastKill.t),
            ns.Utils.DisplayName(entry.lastKill.victim) or "?", ns.Utils.MapName(entry.lastKill.mapID) or "?"))
    end
end, L.HELP_OUTLAW)

-- /hh sim spree "<name>" <kills> [secondsApart] [killerLevel] [victimLevel]
-- Distinct fake victims, stored as simulated reports (never broadcast).
ns.SlashCommands:Register("spree", function(args)
    local U = ns.Utils
    local key = U.PlayerKey(args[1])
    local count = tonumber(args[2])
    if not key or not count or count < 1 or count > 60 then
        ns:Print(L.SPREE_USAGE)
        return
    end
    local gap = tonumber(args[3]) or 120
    local killerLevel = tonumber(args[4]) or 60
    local victimLevel = tonumber(args[5]) or 40
    local now = U.ServerTime()
    local realm = ns.Features.RealmlessNames and "" or ("-" .. (U.PlayerRealm() or "Realm"))
    for i = 1, count do
        local victim = ns.Features.RealmlessNames and ("Victim Number" .. i) or ("Victim" .. i .. realm)
        local t = now - (count - i) * gap
        ns.Reports:Add({
            -- The killer is part of the id: two sprees at the same moment share victim names
            id = victim .. ":" .. t .. ":spree:" .. key,
            t = t,
            victim = { key = U.PlayerKey(victim), level = victimLevel },
            killer = { key = key, name = key, level = killerLevel, class = "ROGUE", race = "Orc" },
            assists = {},
            mapID = U.PlayerMapID(),
            confidence = "sim",
        }, "sim")
    end
    ns:Print(string.format(L.SPREE_DONE, count, U.DisplayName(key)))
end, L.HELP_SPREE)
