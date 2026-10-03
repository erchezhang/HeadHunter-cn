-- /hh sim demo: every tab filled for screenshots, and taken out again.

return function(T, H)
    local function Settle()
        H.Advance(1)
        for _ = 1, 30 do H.Advance(0) end
        H.Advance(1)
        for _ = 1, 5 do H.Advance(0) end
    end

    local function CountDemo(store)
        local n = 0
        for _, item in pairs(store) do if item.demo then n = n + 1 end end
        return n
    end

    local function Entry(ns, name) return ns.Wanted:ByKey(ns.Utils.PlayerKey(name)) end

    T.case("WANTED: both factions, every rank, every badge", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim demo")
        Settle()
        local list = ns.Wanted:List()
        T.eq(#list, 20, "outlaws")
        local ranks = {}
        for _, entry in ipairs(list) do ranks[entry.rank] = (ranks[entry.rank] or 0) + 1 end
        T.eq(ranks.deadoralive, 1, "Dead or Alive")
        T.eq(ranks.mostwanted, 2, "Most Wanted")
        T.eq(ranks.desperado, 2, "Desperado")
        T.eq(ranks.outlaw, 5, "Outlaw")
        T.eq(ranks.ganker, 10, "Ganker")
        T.eq(Entry(ns, "Moomao").rank, "deadoralive", "Moomao leads")
        T.eq(Entry(ns, "Garrick").rank, "mostwanted", "an Alliance outlaw too")
        T.ok(Entry(ns, "Moomao").badges.serialkiller, "Serial Killer")
        T.ok(Entry(ns, "Hyperstorm").badges.gunslinger, "Gunslinger")
        T.ok(Entry(ns, "Hakkaki").badges.duo, "Duo")
        T.ok(Entry(ns, "Jinzz").badges.gang, "Gang")
        T.ok(Entry(ns, "Aldex").badges.giantslayer, "Underdog")
        T.ok(H.Printed("Demo data added"), "chat line")
        T.noErrors()
    end)

    T.case("Bullies: 14 cowards, some caught or never WANTED", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim demo")
        Settle()
        T.eq(#ns.MainWindow.Rows("bullies"), 14, "rows in the tab")
        local never = Entry(ns, "Tinkle")
        T.ok(never.badges.coward and not never.wanted and (never.timesWanted or 0) == 0, "Tinkle: too slow for WANTED")
        local caught = Entry(ns, "Brakka")
        T.ok(caught.badges.coward and not caught.wanted, "Brakka: not WANTED now")
        T.eq(caught.timesCaught, 1, "Brakka was caught")
    end)

    T.case("duel lists for both factions, each with a Top Gun", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim demo")
        Settle()
        for _, faction in ipairs({ "Alliance", "Horde" }) do
            local list = ns.HighNoon:List(faction)
            T.ok(#list >= 15, faction .. " list")
            local topGuns = 0
            for _, p in ipairs(list) do if p.topGun then topGuns = topGuns + 1 end end
            T.eq(topGuns, 1, faction .. " Top Gun")
        end
    end)

    T.case("my deaths and bounty come from the other faction", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim demo")
        Settle()
        T.eq(#ns.db.deaths, #ns.Demo.MY_DEATHS, "deaths")
        T.eq(ns.db.deaths[#ns.db.deaths].killer.key, ns.Utils.PlayerKey("Moomao"), "we are Alliance: the Horde kills us")
        T.eq(ns.Marks:Total(), 57, "bounty")
        T.eq(ns.Marks.RankNameByIndex(ns.Marks:RankIndex()), "Headhunter", "rank")
        T.eq(#ns.Marks:Events(), #ns.Demo.BOUNTY, "events")
    end)

    T.case("a Horde character is hunted by the Alliance", function()
        local ns = H.Boot({ client = "era" })
        H.units.player.faction = "Horde"
        H.Slash("sim demo")
        Settle()
        T.eq(ns.db.deaths[#ns.db.deaths].killer.key, ns.Utils.PlayerKey("Garrick"), "killed by Garrick")
        T.eq(#ns.Wanted:List(), 20, "the same WANTED list")
        T.noErrors()
    end)

    T.case("clear takes it all out and puts our bounty back", function()
        local ns = H.Boot({ client = "era" })
        ns.db.marks = { total = 7, events = { { t = H.serverTime - 60, delta = 1, reason = "join", outlaw = "X", total = 7 } } }
        H.Slash("sim demo")
        H.Slash("sim demo")
        Settle()
        T.eq(ns.Marks:Total(), 57, "demo bounty, run twice")
        H.Slash("sim demo clear")
        Settle()
        T.eq(CountDemo(ns.db.reports), 0, "reports")
        T.eq(CountDemo(ns.db.duels), 0, "duels")
        T.eq(CountDemo(ns.db.justice), 0, "catches")
        T.eq(#ns.db.deaths, 0, "deaths")
        T.eq(ns.Marks:Total(), 7, "our own bounty is back")
        T.eq(#ns.Wanted:List(), 0, "WANTED empty")
        T.eq(#ns.HighNoon:List("Horde"), 0, "duels empty")
        T.ok(H.Printed("Demo data removed"), "chat line")
        T.noErrors()
    end)

    T.case("nothing is sent", function()
        H.Boot({ client = "era" })
        Settle()
        local before = #H.sent
        H.Slash("sim demo")
        Settle()
        T.eq(#H.sent, before, "no addon messages")
    end)

    T.case("Forever: refused, Era names only", function()
        local ns = H.Boot({ client = "forever" })
        H.Slash("sim demo")
        T.ok(H.Printed("only runs on Classic Era"), "message")
        T.eq(ns.Utils.CountKeys(ns.db.reports), 0, "no reports")
    end)
end
