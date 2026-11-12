-- M3 (HH-030/031/032): the WANTED rules. Pure functions over death reports, no WoW
-- API, fully offline-tested. The website applies the same rules
-- (docs/website/plan.md); keep both in sync.
--
-- Rules: docs/addon/features.md sections 1-3.
--   Kill        every enemy in a report (killer and each assist) gets one kill, once
--               even when the report names them twice, weighted by confidence:
--               exact 1, inferred 0.5, sim 1
--   WANTED      enters at WANTED_KILLS weighted kills within WANTED_WINDOW
--               (5 in 20 min) on at least WANTED_VICTIMS different victims (2); each
--               kill while WANTED adds to the count
--   Repeats     one victim's deaths to the same enemy count toward WANTED at most
--               REPEAT_KILLS times per REPEAT_WINDOW (3 per hour); the others are
--               still kills (totals, badges). A report comes from its victim, so
--               one player alone can never make someone WANTED (author, 2026-10-04;
--               2 victims and 3 an hour for the release 2026-11-04, so A, A, B, B, A
--               makes WANTED. Emergency plan: 3 victims and 2 an hour, the same in
--               the website's WantedEvaluator).
--               Test deaths (sim: our own, or from a trusted character) are exempt; a lowered test threshold
--               (/hh debug wanted <n>) lowers the victims needed too
--   Ends        when a HeadHunter or their group kills the outlaw (a "catch",
--               Sync/Justice.lua; author 2026-09-23), or after WANTED_IDLE (7 days)
--               without a kill. Either way the count resets: the next WANTED
--               needs a fresh 5 kills in 20 min (kills before a catch never count)
--   Rank        Ganker 5-9, Outlaw 10-19, Desperado 20-29, Most Wanted 30-49,
--               Dead or Alive 50+
--   Badges      Coward (the Bully mark, the Hall of Shame): a coward kill (skull or
--                 grey victim), with help or not, within the last BULLY_WINDOW (30
--                 days, HH-160 in 1.1.1); it ends by itself 30 days after the newest one
--               Gang: any kill with 3+ attackers on one victim; Duo: with exactly 2
--                 (author 2026-09-23; group size is judged next to the levels)
--               Serial Killer: 5+ distinct victims in separate engagements
--                 (kills <= 60 s apart are one engagement) within the serial window
--               Gunslinger: 3+ kills and more than half of them fair one-on-one
--               Giant Slayer: 2+ one-on-one kills of higher-level victims
--
-- Everything is derived from the report set, so the result does not depend on the
-- order in which reports arrived.

local addonName, ns = ...

local Engine = ns:RegisterModule("RulesEngine", {})

local MINUTE, DAY = 60, 86400

Engine.WANTED_KILLS = 5
Engine.WANTED_WINDOW = 20 * MINUTE
Engine.WANTED_VICTIMS = 2
Engine.REPEAT_KILLS = 3
Engine.REPEAT_WINDOW = 60 * MINUTE
Engine.ENGAGEMENT_GAP = 60
Engine.SERIAL_VICTIMS = 5
Engine.DEFAULT_SERIAL_WINDOW = 15 * MINUTE
Engine.GUNSLINGER_MIN_KILLS = 3
Engine.GIANT_SLAYER_KILLS = 2
Engine.WANTED_IDLE = 7 * DAY   -- WANTED ends after this long without a kill
-- HH-160 (1.1.1, author 2026-11-12): a bully kill counts for this long; the website's
-- WantedEvaluator::BULLY_WINDOW has the same
Engine.BULLY_WINDOW = 30 * DAY
Engine.WEIGHT = { exact = 1, inferred = 0.5, sim = 1 }

-- How often Compute calls `yield` (reports, then enemies)
Engine.YIELD_REPORTS = 200
Engine.YIELD_ENEMIES = 50

-- Highest first
Engine.RANKS = {
    { min = 50, id = "deadoralive" },
    { min = 30, id = "mostwanted" },
    { min = 20, id = "desperado" },
    { min = 10, id = "outlaw" },
    { min = 5, id = "ganker" },
}
local RANK_ORDER = { ganker = 1, outlaw = 2, desperado = 3, mostwanted = 4, deadoralive = 5 }
Engine.RANK_ORDER = RANK_ORDER

-- Weighted sums compare with a small tolerance (0.5 steps)
local EPSILON = 1e-6

function Engine.Rank(kills)
    local k = math.floor(kills + EPSILON)
    for _, rank in ipairs(Engine.RANKS) do
        if k >= rank.min then return rank.id end
    end
    return nil
end

-- Identity of an enemy inside the rules: its player key, or its GUID while only
-- the given name is known (Forever stealth kills)
function Engine.EnemyId(enemy)
    if type(enemy) ~= "table" then return nil end
    if enemy.key then return enemy.key end
    if enemy.guid then return "guid:" .. enemy.guid end
    return nil
end

-- A bully kill at time t still counts at `now` (HH-160: within BULLY_WINDOW)
function Engine.BullyKillCounts(t, now)
    return now - t <= Engine.BULLY_WINDOW
end

-- The entry is a Bully at `now`: the coward badge, and its newest bully kill (when known)
-- within BULLY_WINDOW; an entry without that time (an older website download) keeps its badge
function Engine.IsBully(entry, now)
    if not (entry and entry.badges and entry.badges.coward) then return false end
    return entry.lastCowardKill == nil or Engine.BullyKillCounts(entry.lastCowardKill, now)
end

-------------------------------------------------
-- Kill collection
-------------------------------------------------

-- Richer enemy info wins; newer wins between equals
local function Better(current, candidate, t, currentT)
    if not current then return true end
    if candidate.key and not current.key then return true end
    if candidate.level and not current.level then return true end
    if (candidate.class or candidate.race) and not (current.class or current.race) then return true end
    return t >= (currentT or 0)
end

-- What we know of a player named twice in one report (killer and assist, a Forever
-- death recap): the first entry, with the fields only the second one has
local INFO_FIELDS = { "key", "guid", "level", "class", "race", "sex", "faction" }

local function Merged(first, second)
    local merged = {}
    for k, v in pairs(first) do merged[k] = v end
    for _, field in ipairs(INFO_FIELDS) do
        if merged[field] == nil then merged[field] = second[field] end
    end
    return merged
end

-- reports: array of report tables. yield: optional function called now and then
-- (the runtime passes coroutine.yield to spread the work over frames).
-- Returns id -> { kills = {...}, info = enemy table, infoT = time }
function Engine.CollectKills(reports, yield)
    local classify = ns.Classify.Enemy
    local byEnemy = {}
    for index, report in ipairs(reports) do
        local weight = Engine.WEIGHT[report.confidence] or Engine.WEIGHT.inferred
        local victimLevel = report.victim and report.victim.level
        -- A report may name one attacker twice: one death is one kill for them, and they
        -- are one attacker in the group size
        local enemies, named = {}, {}
        local function Take(enemy)
            local id = Engine.EnemyId(enemy)
            if enemy == nil then return end
            if id and named[id] then
                enemies[named[id]] = Merged(enemies[named[id]], enemy)
                return
            end
            enemies[#enemies + 1] = enemy
            if id then named[id] = #enemies end
        end
        Take(report.killer)
        for _, assist in ipairs(report.assists or {}) do Take(assist) end
        for _, enemy in ipairs(enemies) do
            local id = Engine.EnemyId(enemy)
            if id then
                local bucket = byEnemy[id]
                if not bucket then
                    bucket = { kills = {} }
                    byEnemy[id] = bucket
                end
                -- The level judgement, and the group size (duo / gang / group fight) for each attacker
                local class, group = classify(enemy.level, victimLevel, #enemies, ns.Classify.Helpers(report))
                bucket.kills[#bucket.kills + 1] = {
                    t = report.t,
                    weight = weight,
                    sim = report.confidence == "sim" or nil,
                    victim = report.victim and report.victim.key,
                    class = class,
                    group = group,
                    mapID = report.mapID, x = report.x, y = report.y,
                    reportId = report.id,
                }
                if Better(bucket.info, enemy, report.t, bucket.infoT) then
                    bucket.info, bucket.infoT = enemy, report.t
                end
            end
        end
        if yield and index % Engine.YIELD_REPORTS == 0 then yield() end
    end
    return byEnemy
end

-------------------------------------------------
-- Serial Killer
-------------------------------------------------

-- 5+ distinct victims, each from a separate engagement, within `window` seconds
function Engine.IsSerialKiller(kills, window)
    window = window or Engine.DEFAULT_SERIAL_WINDOW
    local n = #kills
    for i = 1, n do
        local seen, count = {}, 0
        local engagementUsed = false
        local previousT
        for j = i, n do
            local kill = kills[j]
            if kill.t - kills[i].t > window then break end
            if previousT and kill.t - previousT > Engine.ENGAGEMENT_GAP then
                engagementUsed = false -- a new engagement starts
            end
            previousT = kill.t
            if not engagementUsed and kill.victim and not seen[kill.victim] then
                seen[kill.victim] = true
                count = count + 1
                engagementUsed = true
                if count >= Engine.SERIAL_VICTIMS then return true end
            end
        end
    end
    return false
end

-------------------------------------------------
-- One enemy
-------------------------------------------------

-- opts.wantedKills overrides WANTED_KILLS (testing only: /hh debug wanted <n>).
-- HH-160: cowardKills counts the bully kills within BULLY_WINDOW of `now`;
-- lastCowardKill is the newest of them, bullyRecountAt when the oldest drops out.
-- catches: times this enemy was killed by a HeadHunter or their group (any order).
function Engine.Evaluate(kills, now, opts, catches)
    opts = opts or {}
    local wantedKills = opts.wantedKills or Engine.WANTED_KILLS
    table.sort(kills, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return (a.reportId or "") < (b.reportId or "")
    end)
    local catchTimes = {}
    for i, t in ipairs(catches or {}) do catchTimes[i] = t end
    table.sort(catchTimes)
    local wantedVictims = math.min(Engine.WANTED_VICTIMS, wantedKills)

    local counted, byVictim = {}, {}
    for i, kill in ipairs(kills) do
        counted[i] = kill.weight
        if kill.victim and not kill.sim then
            local recent = {}
            for _, t in ipairs(byVictim[kill.victim] or {}) do
                if t > kill.t - Engine.REPEAT_WINDOW then recent[#recent + 1] = t end
            end
            if #recent >= Engine.REPEAT_KILLS then
                counted[i] = 0
            else
                recent[#recent + 1] = kill.t
            end
            byVictim[kill.victim] = recent
        end
    end

    local windowVictims, windowDistinct = {}, 0
    local function WindowVictim(i, step)
        if counted[i] <= 0 then return end
        local victim = (not kills[i].sim and kills[i].victim) or ("#" .. i)
        local n = (windowVictims[victim] or 0) + step
        if step > 0 and n == 1 then windowDistinct = windowDistinct + 1 end
        if step < 0 and n == 0 then windowDistinct = windowDistinct - 1 end
        windowVictims[victim] = n > 0 and n or nil
    end

    local wanted, count, wantedUntil, wantedSince = false, 0, 0, nil
    local timesWanted, peakRank = 0, nil
    local windowStart, windowSum = 1, 0
    local total, coward, fair, giant, gang, duo = 0, 0, 0, 0, 0, 0
    local exact, partial = 0, 0
    local firstCoward, lastCoward = nil, nil
    local nextCatch, timesCaught, lastCaught = 1, 0, nil
    local ranOut = false -- the last WANTED ended by 7 days without a kill
    -- At large (author, 2026-09-26): the last WANTED ran out without a catch; a catch
    -- later still ends it. Display and catches only, the WANTED rule is unchanged.
    local atLarge, lastRank, caughtAtLarge = false, nil, nil

    -- A catch at time t, before kill number `nextKill`: WANTED ends and the count
    -- restarts; the kills before it never count toward a new WANTED
    local function ApplyCatch(t, nextKill)
        if wanted and t <= wantedUntil then
            timesCaught = timesCaught + 1
            lastCaught = t
        elseif wanted then
            ranOut = true -- it had already run out before this catch
            caughtAtLarge = t
        elseif atLarge then
            caughtAtLarge = t
        end
        atLarge = false
        wanted, count = false, 0
        windowStart, windowSum = nextKill, 0
        windowVictims, windowDistinct = {}, 0
    end

    for i, kill in ipairs(kills) do
        -- A kill at the same second as a catch happened before it
        while catchTimes[nextCatch] and catchTimes[nextCatch] < kill.t do
            ApplyCatch(catchTimes[nextCatch], i)
            nextCatch = nextCatch + 1
        end
        total = total + kill.weight
        if kill.weight >= 1 then exact = exact + 1 else partial = partial + 1 end
        if ns.Classify.IsCoward(kill.class) and Engine.BullyKillCounts(kill.t, now) then
            coward = coward + 1
            firstCoward = firstCoward or kill.t
            lastCoward = kill.t
        end
        if kill.group == "gang" then gang = gang + 1 end
        if kill.group == "duo" then duo = duo + 1 end
        if ns.Classify.IsFair(kill.class, kill.group) then fair = fair + 1 end
        if ns.Classify.IsGiant(kill.class, kill.group) then giant = giant + 1 end

        windowSum = windowSum + counted[i]
        WindowVictim(i, 1)
        while kills[windowStart].t < kill.t - Engine.WANTED_WINDOW do
            windowSum = windowSum - counted[windowStart]
            WindowVictim(windowStart, -1)
            windowStart = windowStart + 1
        end

        if wanted and kill.t > wantedUntil then
            wanted, count = false, 0 -- 7 days without a kill before this one
            atLarge = true
        end
        if wanted then
            count = count + counted[i]
        elseif windowSum >= wantedKills - EPSILON and windowDistinct >= wantedVictims then
            wanted, count, wantedSince = true, windowSum, kill.t
            timesWanted = timesWanted + 1
            ranOut = false
            atLarge = false
        end
        if wanted then
            wantedUntil = kill.t + Engine.WANTED_IDLE
            local rank = Engine.Rank(count) or "ganker"
            lastRank = rank
            if rank and (not peakRank or RANK_ORDER[rank] > RANK_ORDER[peakRank]) then
                peakRank = rank
            end
        end
    end

    -- Catches after the last kill (a catch "in the future" is ignored until then)
    while catchTimes[nextCatch] and catchTimes[nextCatch] <= now do
        ApplyCatch(catchTimes[nextCatch], #kills + 1)
        nextCatch = nextCatch + 1
    end

    local last = kills[#kills]
    local active = wanted and now <= wantedUntil
    if wanted and not active then atLarge = true end
    return {
        wanted = active,
        atLarge = (atLarge and not active) or nil,
        lastRank = lastRank,          -- the rank when WANTED last ended (or now)
        caughtAtLarge = caughtAtLarge, -- a catch after WANTED ran out
        expired = (wanted and not active) or ranOut, -- ended by 7 days without a kill
        timesCaught = timesCaught,
        lastCaught = lastCaught,
        kills = active and count or 0,
        -- Below the Ganker threshold only with a lowered test threshold: still a Ganker
        rank = active and (Engine.Rank(count) or "ganker") or nil,
        wantedUntil = wanted and wantedUntil or nil,
        wantedSince = wantedSince,
        timesWanted = timesWanted,
        peakRank = peakRank,
        totalKills = total,
        killCount = #kills,
        exactKills = exact,     -- weight 1 (exact, sim)
        guessedKills = partial, -- weight 0.5 (inferred)
        cowardKills = coward,   -- Hall of Shame
        lastCowardKill = lastCoward,
        bullyRecountAt = firstCoward and firstCoward + Engine.BULLY_WINDOW,
        gangKills = gang,       -- 3+ attackers on one victim
        duoKills = duo,         -- 2 attackers on one victim
        badges = {
            coward = coward > 0 or nil,
            gang = gang > 0 or nil,
            duo = duo > 0 or nil,
            serialkiller = Engine.IsSerialKiller(kills, opts.serialWindow) or nil,
            gunslinger = (#kills >= Engine.GUNSLINGER_MIN_KILLS and fair * 2 > #kills) or nil,
            giantslayer = giant >= Engine.GIANT_SLAYER_KILLS or nil,
        },
        firstKill = kills[1] and kills[1].t,
        lastKill = last and {
            t = last.t, victim = last.victim, mapID = last.mapID, x = last.x, y = last.y,
        },
    }
end

-- reports: array. opts.catches: enemy id -> array of catch times (Sync/Justice.lua).
-- Returns id -> entry (every enemy with at least one kill)
function Engine.Compute(reports, now, opts, yield)
    opts = opts or {}
    local byEnemy = Engine.CollectKills(reports, yield)
    local entries = {}
    local processed = 0
    for id, bucket in pairs(byEnemy) do
        local entry = Engine.Evaluate(bucket.kills, now, opts, opts.catches and opts.catches[id])
        local info = bucket.info or {}
        entry.id = id
        entry.key = info.key
        entry.guid = info.guid
        entry.name = info.key or info.name or id
        entry.nameIncomplete = info.key == nil or nil
        entry.level = info.level
        entry.levelMin = info.levelMin
        entry.class = info.class
        entry.race = info.race
        entry.sex = info.sex
        entries[id] = entry
        processed = processed + 1
        if yield and processed % Engine.YIELD_ENEMIES == 0 then yield() end
    end
    return entries
end
