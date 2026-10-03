-- M3 runtime: recompute, events, expiry, commands.

return function(T, H)
    local function Settle()
        H.Advance(1)                        -- debounce
        for _ = 1, 20 do H.Advance(0) end   -- budgeted frames
    end

    local function Track(ns)
        local events = { added = {}, rank = {}, expired = {}, updated = 0 }
        ns.Events:Register("HH_WANTED_ADDED", function(_, e) events.added[#events.added + 1] = e end, "t")
        ns.Events:Register("HH_WANTED_RANK", function(_, e, old) events.rank[#events.rank + 1] = old .. ">" .. e.rank end, "t")
        ns.Events:Register("HH_WANTED_EXPIRED", function(_, e) events.expired[#events.expired + 1] = e end, "t")
        ns.Events:Register("HH_WANTED_UPDATED", function() events.updated = events.updated + 1 end, "t")
        return events
    end

    T.case("a simulated spree makes a Ganker, announced once", function()
        local ns = H.Boot({ client = "forever" })
        local events = Track(ns)
        H.Slash('spree "Grim Reaper" 5 60')
        T.ok(H.Printed("Simulated 5 kills by Grim Reaper"), "spree done")
        T.eq(#ns.Wanted:List(), 0, "not recomputed inside the command")
        Settle()
        local list = ns.Wanted:List()
        T.eq(#list, 1, "one WANTED")
        T.eq(list[1].key, "Grim Reaper", "who")
        T.eq(list[1].rank, "ganker", "rank")
        T.eq(#events.added, 1, "HH_WANTED_ADDED once")
        T.ok(events.updated >= 1, "HH_WANTED_UPDATED")
        T.noErrors()
    end)

    T.case("more kills raise the rank; the event says from what to what", function()
        local ns = H.Boot({ client = "era" })
        local events = Track(ns)
        H.Slash("spree Gank 5 60")
        Settle()
        H.serverTime = H.serverTime + 300
        H.Slash("spree Gank 7 30")
        Settle()
        T.eq(ns.Wanted:ByKey("Gank-Firemaw").rank, "outlaw", "12 kills = outlaw")
        T.eq(events.rank[1], "ganker>outlaw", "rank event")
    end)

    T.case("the expiry ticker ends WANTED after 7 days without a kill", function()
        local ns = H.Boot({ client = "era" })
        local events = Track(ns)
        H.Slash("spree Gank 5 60")
        Settle()
        T.eq(#ns.Wanted:List(), 1, "wanted")
        H.serverTime = H.serverTime + 6 * 86400
        H.Advance(60)
        Settle()
        T.eq(#ns.Wanted:List(), 1, "still wanted after 6 days")
        H.serverTime = H.serverTime + 86400 + 1
        H.Advance(60)   -- ticker
        Settle()
        T.eq(#ns.Wanted:List(), 0, "expired")
        T.eq(#events.expired, 1, "HH_WANTED_EXPIRED")
    end)

    T.case("reports from other players feed the rules", function()
        local ns = H.Boot({ client = "era" })
        for i = 1, 5 do
            local report = {
                t = H.serverTime - (6 - i) * 60,
                victim = { key = "Victim" .. i .. "-Firemaw", level = 30, class = "MAGE", race = "Gnome" },
                killer = { key = "Gank-Stonespine", name = "Gank-Stonespine", level = 60, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = 1434, confidence = "exact",
            }
            local message = ns.Protocol.Pack("A", "D", { ns.Protocol.EncodeDeath(report) })
            H.Deliver(message, "Victim" .. i .. "-Firemaw")
        end
        Settle()
        local entry = ns.Wanted:ByKey("Gank-Stonespine")
        T.eq(entry and entry.wanted, true, "WANTED from 5 different reporters")
        T.eq(entry.badges.coward, true, "60 on 30 is a coward")
    end)

    T.case("recompute is spread over frames under the budget", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("spree Gank 60 30")
        H.Slash("spree Stab 60 30")
        ns.RulesEngine.YIELD_REPORTS = 10 -- pause often so the budget is exercised
        H.profileStep = 5 -- every clock read costs more than the 3 ms budget
        H.Advance(1)
        H.Advance(0)
        local afterOneFrame = #ns.Wanted:List()
        for _ = 1, 50 do H.Advance(0) end
        T.eq(afterOneFrame, 0, "not finished in one frame")
        T.eq(#ns.Wanted:List(), 2, "finished over several frames")
        T.noErrors()
    end)

    T.case("/hh wanted and /hh outlaw", function()
        local ns = H.Boot({ client = "forever" })
        H.Slash('spree "Grim Reaper" 12 60 60 45')
        Settle()
        H.Slash("wanted")
        T.ok(H.Printed("WANTED: 1"), "header")
        T.ok(H.Printed("Outlaw.*Grim Reaper.*12 kills"), "line")
        H.Slash("outlaw Grim Reaper")
        T.ok(H.Printed("Grim Reaper.*Outlaw"), "outlaw line 1")
        T.ok(H.Printed("Kills known: 12 %(exact 12, guessed 0"), "outlaw line 2")
        T.ok(H.Printed("Bully"), "badge (60 on 45)")
        H.Slash("outlaw Nobody Here")
        T.ok(H.Printed("No kills known for Nobody Here"), "unknown")
        H.Slash("spree")
        T.ok(H.Printed("/hh spree"), "usage")
        T.noErrors()
    end)

    T.case("/hh debug wanted 3 lowers the threshold for testing; off restores 5", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("spree Gank 3 60")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "3 kills: not wanted by the real rule")
        H.Slash("debug wanted 3")
        Settle()
        T.eq(#ns.Wanted:List(), 1, "wanted with the test threshold")
        T.eq(ns.Wanted:List()[1].rank, "ganker", "shown as Ganker")
        H.Slash("wanted")
        T.ok(H.Printed("test threshold: WANTED from 3 kills"), "reminder shown")
        H.Slash("debug wanted off")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "real rule again")
        H.Slash("debug wanted 99")
        T.ok(H.Printed("/hh debug wanted <1%-10|off>"), "usage on bad value")
        T.noErrors()
    end)

    T.case("the Serial Killer window setting is used and clamped", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("spree Gank 5 240") -- 5 victims, 16 minutes from first to last
        Settle()
        T.eq(ns.Wanted:ByKey("Gank-Firemaw").badges.serialkiller, nil, "outside 15 min")
        ns.Database:SetSetting("serialKillerWindowMin", 99) -- clamped to 15
        Settle()
        T.eq(ns.Wanted:ByKey("Gank-Firemaw").badges.serialkiller, nil, "clamped")
        H.Slash("spree Stab 5 150") -- 10 minutes span
        Settle()
        T.eq(ns.Wanted:ByKey("Stab-Firemaw").badges.serialkiller, true, "inside 15 min")
    end)
end
