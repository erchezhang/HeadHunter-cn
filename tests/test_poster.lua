-- HH-061: the poster (everything known about one enemy).

return function(T, H)
    local serial = 0

    -- `killer` kills n victims, `step` seconds apart, the newest `ago` seconds ago
    local function Spree(ns, killer, n, opts)
        opts = opts or {}
        for i = 1, n do
            serial = serial + 1
            local victim = "Victim" .. serial .. "-Firemaw"
            local t = H.serverTime - (opts.ago or 0) - (n - i) * (opts.step or 60)
            local enemy = { key = killer, name = killer, level = 60, class = "ROGUE", race = "Orc", sex = 3 }
            local report = { id = victim .. ":" .. t, t = t, victim = { key = victim, level = opts.victimLevel or 20 },
                killer = enemy, assists = {}, mapID = opts.mapID or 1436, x = 0.3, y = 0.7, confidence = "exact" }
            if opts.asAssist then
                report.killer = { key = "Other-Stonespine", level = 60 }
                report.assists = { enemy }
            end
            ns.Reports:Add(report, "peer", victim)
        end
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    T.case("content: who, status, last kill, history, recent kills newest first", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 10)
        Spree(ns, "Gank-Stonespine", 1, { asAssist = true, victimLevel = 58 })
        Settle()
        local c = ns.Poster.Content("Gank-Stonespine")
        T.ok(c.title:find("raceicon-orc-female", 1, true) ~= nil, "race icon")
        T.ok(c.title:find("ICONS-CLASSES", 1, true) ~= nil, "class icon")
        T.ok(c.title:find("Gank-Stonespine", 1, true) ~= nil, "name")
        T.eq(c.who, "60 Orc Rogue", "who")
        T.eq(c.raceAtlas, "raceicon-orc-female", "the portrait on the paper")
        T.eq(c.reward, nil, "no players' bounty: no reward")
        T.ok(c.wanted, "WANTED")
        T.ok(c.status:find("11 kills", 1, true) ~= nil, "status: " .. c.status)
        T.ok(c.badges:find("Bully", 1, true) ~= nil, "badges")
        T.eq(c.lastKill, "Last kill just now in Westfall", "last kill")
        T.ok(c.history:find("Kills known: 11 (exact 11, guessed 0) · WANTED 1x · caught 0x", 1, true) ~= nil,
            "history: " .. c.history)
        T.eq(#c.recent, 8, "eight most recent")
        T.ok(c.recent[1]:find("^just now · Victim%d+ · Westfall · ") ~= nil, "newest first: " .. c.recent[1])
        T.ok(c.recent[1]:find("Duo", 1, true) ~= nil, "an assist: 2 vs 1 = Duo")
        T.ok(c.recent[2]:find("Bully kill", 1, true) ~= nil, "coward kill")
        T.ok(c.canJoin, "can join the posse")
    end)

    T.case("not WANTED: no Join; unknown enemy: no poster", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Sneak-Stonespine", 2)
        Settle()
        local c = ns.Poster.Content("Sneak-Stonespine")
        T.eq(c.wanted, false, "not WANTED")
        T.eq(c.status, nil, "no status: the poster does not say Not WANTED")
        T.eq(c.canJoin, false, "no Join")
        T.eq(ns.Poster.Content("Nobody-Stonespine"), nil, "unknown: nothing")
        T.eq(ns.Poster:Show("Nobody-Stonespine"), false, "not opened")
    end)

    T.case("Join the posse from the poster; the button goes away", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        T.ok(ns.Poster:Show("Gank-Stonespine"), "shown")
        T.ok(ns.Poster.shown.canJoin, "Join offered")
        T.ok(ns.Poster:Join(), "joined")
        T.ok(ns.Posse:IsMember("Gank-Stonespine"), "in the posse")
        T.ok(H.Printed("You joined the posse against Gank%-Stonespine"), "the usual message")
        T.eq(ns.Poster.shown.canJoin, false, "no second Join")
        T.eq(ns.Poster.shown.posse, "Posse: you", "posse line")
        T.noErrors()
    end)

    T.case("the poster follows the rules: a catch shows at once", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        ns.Poster:Show("Gank-Stonespine")
        ns.Justice:Record(ns.Wanted:ByKey("Gank-Stonespine"), "test")
        Settle()
        T.eq(ns.Poster.shown.wanted, false, "no longer WANTED")
        T.ok(ns.Poster.shown.history:find("caught 1x", 1, true) ~= nil, "caught")
        T.noErrors()
    end)
end
