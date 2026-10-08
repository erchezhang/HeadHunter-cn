-- Honorable kills by map and time (players' request, 2026-10-07): every honorable kill
-- the game gives us is kept with its time and place for the website.

return function(T, H)
    local function Honor(text)
        H.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", text)
    end

    T.case("era: an honorable kill line is kept with its victim, place and honor", function()
        local ns = H.Boot({ client = "era" })
        H.playerMap = 1417
        Honor("Gank-Stonespine dies, honorable kill Rank: Scout (Estimated Honor Points: 12)")
        local kills = ns.db.honorKills
        T.eq(#kills, 1, "kept")
        T.eq(kills[1].victim, "Gank-Stonespine", "victim")
        T.eq(kills[1].by, "Vati-Firemaw", "ours")
        T.eq(kills[1].t, H.serverTime, "time")
        T.eq(kills[1].seq, 1, "first in its second")
        T.eq(kills[1].mapID, 1417, "map")
        T.eq(kills[1].x, H.playerX, "x")
        T.eq(kills[1].honor, 12, "honor")
        T.noErrors()
    end)

    T.case("era: an award line is bonus honor, not a kill", function()
        local ns = H.Boot({ client = "era" })
        Honor("You have been awarded 5 honor points.")
        T.eq(#ns.db.honorKills, 0, "not a kill")
        T.noErrors()
    end)

    T.case("forever: the award line is a kill with no name, once per kill", function()
        local ns = H.Boot({ client = "forever" })
        Honor("You have been awarded 5 Honor.")
        T.eq(#ns.db.honorKills, 1, "kept")
        T.eq(ns.db.honorKills[1].victim, nil, "no name")
        T.eq(ns.db.honorKills[1].by, "Vati Guda", "ours")
        T.eq(ns.db.honorKills[1].honor, 5, "honor")
        H.Advance(10)
        Honor("Grim Reaper dies, honorable kill Rank: Scout (Estimated Honor Points: 10)")
        Honor("You have been awarded 10 Honor.")
        T.eq(#ns.db.honorKills, 2, "a named line and its award are one kill")
        T.eq(ns.db.honorKills[2].victim, "Grim Reaper", "named")
        T.noErrors()
    end)

    T.case("two kills in the same second are told apart", function()
        local ns = H.Boot({ client = "era" })
        Honor("Gank-Stonespine dies, honorable kill (Estimated Honor Points: 12)")
        Honor("Stab-Stonespine dies, honorable kill (Estimated Honor Points: 9)")
        T.eq(ns.db.honorKills[1].seq, 1, "first")
        T.eq(ns.db.honorKills[2].seq, 2, "second")
        T.noErrors()
    end)

    T.case("nothing inside a battleground", function()
        local ns = H.Boot({ client = "era" })
        H.instance = { true, "pvp" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        Honor("Gank-Stonespine dies, honorable kill (Estimated Honor Points: 12)")
        T.eq(#ns.db.honorKills, 0, "not kept")
        T.noErrors()
    end)

    T.case("/hh hk counts our kills per zone, most first", function()
        local ns = H.Boot({ client = "era" })
        H.playerMap = 1436
        Honor("Gank-Stonespine dies, honorable kill (Estimated Honor Points: 12)")
        H.playerMap = 1417
        Honor("Stab-Stonespine dies, honorable kill (Estimated Honor Points: 9)")
        Honor("Grim-Stonespine dies, honorable kill (Estimated Honor Points: 9)")
        local zones = ns.HonorKills:PerZone(H.serverTime - 60)
        T.eq(#zones, 2, "two zones")
        T.eq(zones[1].mapID, 1417, "most first")
        T.eq(zones[1].count, 2, "count")
        H.Slash("hk")
        T.ok(H.Printed("Arathi Highlands: 2"), "printed")
        T.ok(H.Printed("Westfall: 1"), "printed")
        T.noErrors()
    end)

    T.case("kills older than 30 days are dropped", function()
        local ns = H.Boot({ client = "era" })
        Honor("Gank-Stonespine dies, honorable kill (Estimated Honor Points: 12)")
        ns.Database:Prune(H.serverTime + 31 * 86400)
        T.eq(#ns.db.honorKills, 0, "dropped")
        T.noErrors()
    end)
end
