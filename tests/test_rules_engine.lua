-- M3: WANTED rules (pure engine). These cases are the rule contract the website
-- must reproduce as well (WEB-033).

return function(T, H)
    local MIN = 60
    local T0 = 1790000000

    local function Engine()
        return H.Boot({ client = "era" }).RulesEngine
    end

    -- r(minutesFromT0, victim, opts) -> a report killed by "Gank-Stonespine"
    local function Report(minutes, victim, opts)
        opts = opts or {}
        return {
            id = (victim or "V") .. ":" .. (T0 + math.floor(minutes * MIN)),
            t = T0 + math.floor(minutes * MIN),
            victim = { key = victim or "Victim-Firemaw", level = opts.victimLevel or 40 },
            killer = opts.killer or { key = "Gank-Stonespine", level = opts.killerLevel or 42 },
            assists = opts.assists or {},
            confidence = opts.confidence or "exact",
        }
    end

    local DAY = 86400

    local function Compute(reports, nowMinutes, opts)
        local entries = Engine().Compute(reports, T0 + math.floor(nowMinutes * MIN), opts)
        return entries["Gank-Stonespine"], entries
    end

    -- Catches of Gank-Stonespine at these minutes
    local function Caught(...)
        local times = {}
        for i, minutes in ipairs({ ... }) do times[i] = T0 + math.floor(minutes * MIN) end
        return { catches = { ["Gank-Stonespine"] = times } }
    end

    local function Spree(fromMinute, n, prefix)
        local reports = {}
        for i = 1, n do reports[i] = Report(fromMinute + i - 1, (prefix or "V") .. i) end
        return reports
    end

    local function Join(a, b)
        local all = {}
        for _, r in ipairs(a) do all[#all + 1] = r end
        for _, r in ipairs(b) do all[#all + 1] = r end
        return all
    end

    T.case("rank thresholds", function()
        local E = Engine()
        local CASES = {
            { 4, nil }, { 4.5, nil }, { 5, "ganker" }, { 9, "ganker" }, { 10, "outlaw" }, { 19, "outlaw" },
            { 20, "desperado" }, { 29, "desperado" }, { 30, "mostwanted" }, { 49, "mostwanted" },
            { 50, "deadoralive" }, { 500, "deadoralive" },
        }
        for _, c in ipairs(CASES) do
            T.eq(E.Rank(c[1]), c[2], "rank at " .. c[1])
        end
    end)

    T.case("4 kills in 20 min is not WANTED; the 5th makes a Ganker", function()
        local four = { Report(0, "A"), Report(5, "B"), Report(10, "C"), Report(15, "D") }
        local e = Compute(four, 16)
        T.eq(e.wanted, false, "4 kills")
        T.eq(e.killCount, 4, "kills known")

        local five = { Report(0, "A"), Report(5, "B"), Report(10, "C"), Report(15, "D"), Report(19, "E") }
        e = Compute(five, 20)
        T.eq(e.wanted, true, "5 kills")
        T.eq(e.kills, 5, "count")
        T.eq(e.rank, "ganker", "rank")
        T.eq(e.wantedUntil, T0 + 19 * MIN + 7 * DAY, "until caught, or 7 days without a kill")
        T.eq(e.timesWanted, 1, "times wanted")
    end)

    T.case("the same victim killed 5 times also counts", function()
        local e = Compute({ Report(0, "A"), Report(3, "A"), Report(6, "A"), Report(9, "A"), Report(12, "A") }, 13)
        T.eq(e.wanted, true, "wanted")
    end)

    T.case("5 kills spread over more than 20 minutes are not enough", function()
        local e = Compute({ Report(0, "A"), Report(6, "B"), Report(12, "C"), Report(18, "D"), Report(24, "E") }, 25)
        T.eq(e.wanted, false, "window")
    end)

    T.case("inferred kills weigh half", function()
        local inferred = { confidence = "inferred" }
        local reports = {}
        for i = 1, 9 do reports[i] = Report(i, "V" .. i, inferred) end
        T.eq(Compute(reports, 10).wanted, false, "9 x 0.5 = 4.5")
        reports[10] = Report(10, "V10", inferred)
        local e = Compute(reports, 11)
        T.eq(e.wanted, true, "10 x 0.5 = 5")
        T.eq(e.kills, 5, "weighted count")
    end)

    T.case("kills while WANTED raise the count and the rank follows", function()
        local reports = {}
        for i = 1, 12 do reports[i] = Report(i, "V" .. i) end
        local e = Compute(reports, 13)
        T.eq(e.kills, 12, "12 kills")
        T.eq(e.rank, "outlaw", "outlaw")
        T.eq(e.wantedUntil, T0 + 12 * MIN + 7 * DAY, "7 days after the last kill")
        T.eq(e.peakRank, "outlaw", "peak")
    end)

    T.case("7 days without a kill: the status ends and the count resets", function()
        local reports = { Report(0, "A"), Report(1, "B"), Report(2, "C"), Report(3, "D"), Report(4, "E") }
        local e = Compute(reports, 4 + 7 * 24 * 60 - 1)
        T.eq(e.wanted, true, "a minute before 7 days")
        e = Compute(reports, 4 + 7 * 24 * 60 + 1)
        T.eq(e.wanted, false, "expired")
        T.eq(e.expired, true, "flag")
        T.eq(e.kills, 0, "no current count")

        -- Two more kills later: count restarted, not WANTED
        local later = 8 * 24 * 60
        reports[6] = Report(later, "F")
        reports[7] = Report(later + 1, "G")
        e = Compute(reports, later + 2)
        T.eq(e.wanted, false, "count reset")

        -- Three more in the same window: WANTED again, second time
        reports[8] = Report(later + 2, "H")
        reports[9] = Report(later + 3, "I")
        reports[10] = Report(later + 4, "J")
        e = Compute(reports, later + 5)
        T.eq(e.wanted, true, "wanted again")
        T.eq(e.kills, 5, "fresh count")
        T.eq(e.timesWanted, 2, "second time")
    end)

    T.case("each kill while WANTED restarts the 7 days", function()
        local reports = { Report(0, "A"), Report(1, "B"), Report(2, "C"), Report(3, "D"), Report(4, "E"),
            Report(6 * 24 * 60, "F") }
        local e = Compute(reports, 12 * 24 * 60)
        T.eq(e.wanted, true, "6 days after the 6th kill")
        T.eq(e.kills, 6, "6")
    end)

    -------------------------------------------------
    -- Justice served (HH-048)
    -------------------------------------------------

    T.case("a catch ends WANTED and resets the count", function()
        local e = Compute(Spree(0, 6), 30, Caught(20))
        T.eq(e.wanted, false, "caught")
        T.eq(e.expired, false, "not an expiry")
        T.eq(e.kills, 0, "count reset")
        T.eq(e.rank, nil, "no rank")
        T.eq(e.timesCaught, 1, "caught once")
        T.eq(e.lastCaught, T0 + 20 * MIN, "when")
        T.eq(e.killCount, 6, "history kept")
    end)

    T.case("after a catch, kills before it never count: 5 fresh kills are needed", function()
        -- WANTED at minute 4, caught at 10, then 4 kills within 20 min of the old ones
        local reports = Join(Spree(0, 5), Spree(11, 4, "W"))
        local e = Compute(reports, 15, Caught(10))
        T.eq(e.wanted, false, "4 fresh kills are not enough")
        reports = Join(reports, { Report(15, "W5") })
        e = Compute(reports, 16, Caught(10))
        T.eq(e.wanted, true, "the 5th fresh kill")
        T.eq(e.kills, 5, "fresh count")
        T.eq(e.timesWanted, 2, "second time")
        T.eq(e.timesCaught, 1, "caught once")
    end)

    T.case("a catch while not WANTED is no catch, but still resets the count", function()
        local reports = Join(Spree(0, 4), { Report(5, "Z") })
        local e = Compute(reports, 6, Caught(4))
        T.eq(e.wanted, false, "4 kills + catch + 1 kill")
        T.eq(e.timesCaught, 0, "not WANTED at the time: not counted")
    end)

    T.case("a catch after the 7 days ran out is not counted", function()
        local e = Compute(Spree(0, 5), 8 * 24 * 60, Caught(7 * 24 * 60 + 10))
        T.eq(e.timesCaught, 0, "already expired")
        T.eq(e.expired, true, "expired")
    end)

    T.case("a kill in the same second as a catch came first; a future catch waits", function()
        local e = Compute(Spree(0, 5), 5, Caught(4))
        T.eq(e.wanted, false, "the 5th kill at minute 4, then the catch at minute 4")
        T.eq(e.timesCaught, 1, "caught")
        e = Compute(Spree(0, 5), 5, Caught(60))
        T.eq(e.wanted, true, "a catch in the future does nothing yet")
    end)

    T.case("catches in any order give the same result", function()
        local reports = Join(Join(Spree(0, 5), Spree(30, 5, "W")), Spree(60, 5, "X"))
        local a = Compute(reports, 70, Caught(10, 40))
        local b = Compute(reports, 70, Caught(40, 10))
        T.eq(a.wanted, b.wanted, "wanted")
        T.eq(a.timesCaught, 2, "caught twice")
        T.eq(b.timesCaught, 2, "caught twice (reversed)")
        T.eq(a.timesWanted, 3, "wanted three times")
    end)

    T.case("3+ on one victim: Gang for every attacker; same level is not fair (no Gunslinger)", function()
        local reports = {}
        for i = 1, 3 do
            -- Gank and two friends, all the victim's level: fair by level, but 3 vs 1
            reports[i] = Report(i, "V" .. i, { killerLevel = 40, assists = {
                { key = "Pal-Stonespine", level = 40 }, { key = "Buddy-Stonespine", level = 40 } } })
        end
        local e, entries = Compute(reports, 5)
        T.eq(e.badges.gang, true, "Gang")
        T.eq(e.gangKills, 3, "three gang kills")
        T.eq(e.badges.coward, nil, "same level: not Coward")
        T.eq(e.badges.gunslinger, nil, "not a Gunslinger")
        T.eq(entries["Pal-Stonespine"].badges.gang, true, "the assists too")
    end)

    T.case("a group fight (the victim had group members in it): no Gang, still counts toward WANTED", function()
        local reports = {}
        for i = 1, 5 do
            reports[i] = Report(i, "V" .. i, { killerLevel = 40, assists = {
                { key = "Pal-Stonespine", level = 40 }, { key = "Buddy-Stonespine", level = 40 } } })
            reports[i].helpers = 2
        end
        local e = Compute(reports, 6)
        T.eq(e.badges.gang, nil, "not Gang")
        T.eq(e.gangKills, 0, "no gang kills")
        T.eq(e.badges.gunslinger, nil, "not one on one")
        T.eq(e.wanted, true, "WANTED as before")
    end)

    T.case("2 on one victim: Duo; a lowbie kill with help is still Coward", function()
        local reports = {}
        for i = 1, 3 do
            -- Gank (60) and a friend kill level 20 victims
            reports[i] = Report(i, "V" .. i, { killerLevel = 60, victimLevel = 20,
                assists = { { key = "Pal-Stonespine", level = 60 } } })
        end
        local e, entries = Compute(reports, 5)
        T.eq(e.badges.duo, true, "Duo")
        T.eq(e.duoKills, 3, "three duo kills")
        T.eq(e.badges.gang, nil, "not Gang")
        T.eq(e.badges.coward, true, "Coward: the victims were lowbies")
        T.eq(entries["Pal-Stonespine"].badges.duo, true, "the partner too")
    end)

    T.case("assists get the kill too; GUID-only enemies are tracked by GUID", function()
        local _, entries = Compute({
            Report(0, "A", { assists = { { key = "Helper-Stonespine", level = 40 } } }),
            Report(1, "B", { assists = { { guid = "Player-9", name = "Kuh", nameIncomplete = true } } }),
        }, 2)
        T.eq(entries["Helper-Stonespine"].killCount, 1, "assist counted")
        T.eq(entries["guid:Player-9"].killCount, 1, "GUID id")
        T.eq(entries["guid:Player-9"].name, "Kuh", "given name shown")
        T.eq(entries["guid:Player-9"].nameIncomplete, true, "flagged incomplete")
    end)

    T.case("badges", function()
        -- Coward: one skull kill
        local e = Compute({ Report(0, "A", { killer = { key = "Gank-Stonespine", level = -1 } }) }, 1)
        T.eq(e.badges.coward, true, "coward")

        -- Gunslinger: 3 fair of 4
        e = Compute({
            Report(0, "A", { killerLevel = 40 }), Report(10, "B", { killerLevel = 41 }),
            Report(20, "C", { killerLevel = 39 }), Report(30, "D", { killerLevel = 47 }),
        }, 31)
        T.eq(e.badges.gunslinger, true, "gunslinger")
        T.eq(e.badges.coward, nil, "not coward")

        -- Giant Slayer: 2 kills of higher-level victims
        e = Compute({ Report(0, "A", { killerLevel = 30 }), Report(10, "B", { killerLevel = 30 }) }, 11)
        T.eq(e.badges.giantslayer, true, "giant slayer")
    end)

    T.case("serial killer needs 5 victims in separate engagements inside the window", function()
        local E = Engine()
        local function Kills(spec)
            local list = {}
            for i, k in ipairs(spec) do list[i] = { t = T0 + k[1], victim = k[2], weight = 1 } end
            return list
        end
        T.eq(E.IsSerialKiller(Kills({ { 0, "A" }, { 120, "B" }, { 240, "C" }, { 360, "D" }, { 480, "E" } })), true,
            "5 victims, 2 min apart")
        T.eq(E.IsSerialKiller(Kills({ { 0, "A" }, { 10, "B" }, { 20, "C" }, { 30, "D" }, { 40, "E" } })), false,
            "one group fight (<= 60 s apart) is one engagement")
        T.eq(E.IsSerialKiller(Kills({ { 0, "A" }, { 300, "B" }, { 600, "C" }, { 900, "D" }, { 1200, "E" } })), false,
            "spread over 20 min, window 15")
        T.eq(E.IsSerialKiller(Kills({ { 0, "A" }, { 300, "B" }, { 600, "C" }, { 900, "D" }, { 1200, "E" } }), 25 * 60), true,
            "same with a larger window")
        T.eq(E.IsSerialKiller(Kills({ { 0, "A" }, { 120, "B" }, { 240, "C" }, { 360, "D" }, { 480, "A" } })), false,
            "a repeat victim does not count twice")
        T.eq(E.IsSerialKiller(Kills({ { 0, "A" }, { 120, "B" }, { 240, "C" }, { 250, "X" }, { 360, "D" }, { 480, "E" } })), true,
            "an extra kill in the same fight does not break it")
    end)

    T.case("result does not depend on report order", function()
        local reports = {}
        for i = 1, 25 do reports[i] = Report(i * 3, "V" .. (i % 7)) end
        local forward = Compute(reports, 80)
        local shuffled = {}
        for i = #reports, 1, -1 do shuffled[#shuffled + 1] = reports[i] end
        local backward = Compute(shuffled, 80)
        T.eq(forward.kills, backward.kills, "kills")
        T.eq(forward.rank, backward.rank, "rank")
        T.eq(forward.wantedUntil, backward.wantedUntil, "timer")
        T.eq(forward.badges.serialkiller, backward.badges.serialkiller, "badge")
    end)

    -- At large (author, 2026-09-26): shown and catchable, the WANTED rule itself unchanged
    T.case("at large: WANTED ran out without a catch; a later catch or a new WANTED ends it", function()
        local DAYS8 = 8 * 24 * 60
        local e = Compute(Spree(0, 10), DAYS8)
        T.eq(e.wanted, false, "7 days without a kill: no longer WANTED")
        T.eq(e.atLarge, true, "at large")
        T.eq(e.lastRank, "outlaw", "the rank it had")

        e = Compute(Join(Spree(0, 10), { Report(DAYS8, "Late") }), DAYS8 + 1)
        T.eq(e.atLarge, true, "a single kill after it ran out: still at large")

        e = Compute(Spree(0, 10), DAYS8 + 10, Caught(DAYS8))
        T.eq(e.atLarge, nil, "caught while at large")
        T.eq(e.caughtAtLarge, T0 + DAYS8 * MIN, "when")
        T.eq(e.timesCaught, 0, "not a WANTED catch")

        e = Compute(Spree(0, 5), 10, Caught(5))
        T.eq(e.atLarge, nil, "caught while WANTED: never at large")

        e = Compute(Join(Spree(0, 5), Spree(DAYS8, 5, "W")), DAYS8 + 5)
        T.eq(e.wanted, true, "WANTED again")
        T.eq(e.atLarge, nil, "not at large")
    end)
end
