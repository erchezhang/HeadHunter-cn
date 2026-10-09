-- HH-136: wars. A hotzone marks a war from its start to its end; the record keeps the
-- players seen fighting on both sides and our own kills and deaths in it.

return function(T, H)
    local function Ids(from, to)
        local ids = {}
        for i = from, to do ids[#ids + 1] = string.format("E%07d", i) end
        return ids
    end

    -- Another HeadHunter of our side fighting in the zone, naming the enemies they see
    local function Ping(ns, mapID, sender, enemyIds, ago, enemies, layer)
        local record = ns.Protocol.EncodeHotspot(mapID, H.serverTime - (ago or 5), 0.4, 0.6, enemyIds, enemies, layer)
        H.Deliver(ns.Protocol.Pack("A", "P", { record }), sender)
    end

    local function Battle(ns, mapID, layer)
        Ping(ns, mapID, "Alpha-Firemaw", Ids(1, 12), 20,
            { { name = "Gank-Stonespine", class = "ROGUE", level = 60 } }, layer)
        Ping(ns, mapID, "Bravo-Firemaw", Ids(1, 2), 5, nil, layer)
    end

    T.case("a burning zone starts a war with the players seen fighting there", function()
        local ns = H.Boot({ client = "era" })
        Battle(ns, 1417, 3)
        local war = ns.Wars:Open(1417)
        T.ok(war ~= nil, "a war")
        T.eq(war.by, "Vati-Firemaw", "ours")
        T.eq(war.started, H.serverTime - 20, "begins with the first ping")
        T.eq(war.peak, 2, "Battle")
        T.eq(war.layers[1], 3, "the layer seen")
        T.eq(war.fighters["Alpha-Firemaw"].side, "ally", "a HeadHunter of our side")
        T.eq(war.fighters["Bravo-Firemaw"].side, "ally", "another")
        T.eq(war.fighters["Gank-Stonespine"].side, "enemy", "an enemy named in a ping")
        T.eq(war.fighters["Gank-Stonespine"].class, "ROGUE", "with the class")
        T.eq(ns.db.wars[1], war, "kept in the saved data")
        T.noErrors()
    end)

    T.case("a pause under 10 minutes is the same war; 10 cold minutes end it", function()
        local ns = H.Boot({ client = "era" })
        Battle(ns, 1417)
        local war = ns.Wars:Open(1417)
        local firstHot = war.lastHot

        H.serverTime = H.serverTime + 8 * 60
        ns.Wars:Check()
        T.ok(not war.ended, "8 min quiet: still going")
        Battle(ns, 1417)
        T.eq(#ns.db.wars, 1, "fighting again: the same war")
        T.ok(war.lastHot > firstHot, "goes on")

        local lastHot = war.lastHot
        H.serverTime = H.serverTime + ns.Wars.END_AFTER
        ns.Wars:Check()
        T.eq(war.ended, lastHot, "ended at its last hot moment")
        T.eq(ns.Wars:Open(1417), nil, "no war going on")

        Battle(ns, 1417)
        T.eq(#ns.db.wars, 2, "a new fight is a new war")
        T.noErrors()
    end)

    T.case("one ping is no war; a lone WANTED ganker is no war", function()
        local ns = H.Boot({ client = "era" })
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 1))
        T.eq(ns.Wars:Open(1436), nil, "heat 2: not even a Skirmish")
        T.eq(#ns.db.wars, 0, "nothing kept")
        T.noErrors()
    end)

    T.case("our scan names both sides, and our kills and deaths count in the war", function()
        local ns = H.Boot({ client = "era" })
        H.inCombat = true
        H.playerMap = 1417
        H.units.nameplate1 = { name = "Grim", realm = "Stonespine", level = 60, class = "WARRIOR", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-1-00ABCDEF", inCombat = true, guild = "Red Hand" }
        H.units.nameplate2 = { name = "Rowan", realm = "Firemaw", level = 58, class = "PRIEST", race = "Human",
            faction = "Alliance", isPlayer = true, guid = "Player-1-00FEDCBA", inCombat = true, guild = "Iron Posse" }
        H.units.nameplate1target = H.units.player
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        Ping(ns, 1417, "Alpha-Firemaw", Ids(1, 10))
        H.Advance(5)
        local war = ns.Wars:Open(1417)
        T.ok(war ~= nil, "a war")
        T.eq(war.fighters["Grim-Stonespine"].side, "enemy", "the enemy we fight")
        T.eq(war.fighters["Grim-Stonespine"].guild, "Red Hand", "with the guild")
        T.eq(war.fighters["Rowan-Firemaw"].side, "ally", "our side, without the addon")
        T.eq(war.fighters["Rowan-Firemaw"].level, 58, "with the level")
        T.eq(war.fighters["Vati-Firemaw"].side, "ally", "we fight too")

        H.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Grim-Stonespine dies, honorable kill (Estimated Honor Points: 14)")
        T.eq(war.kills, 1, "our honorable kill")
        T.eq(war.honor, 14, "its honor")

        ns.DeathReports:Record({ killer = { key = "Brute-Stonespine", name = "Brute-Stonespine", level = 60, class = "ROGUE" },
            mapID = 1417, x = 0.5, y = 0.5 }, "exact")
        T.eq(war.deaths, 1, "our death")
        T.eq(war.fighters["Brute-Stonespine"].side, "enemy", "our killer fought there")
        T.noErrors()
    end)

    T.case("a war left open at logout is closed at the next check, and old wars go", function()
        local ns = H.Boot({ client = "era" })
        Battle(ns, 1417)
        local war = ns.Wars:Open(1417)
        H.serverTime = H.serverTime + 3600
        ns.Wars:Check()
        T.eq(war.ended, war.lastHot, "closed at its last hot moment")
        H.serverTime = H.serverTime + ns.Wars.KEEP + 60
        ns.Wars:Check()
        T.eq(#ns.db.wars, 0, "older than 30 days: dropped")
        T.noErrors()
    end)

    T.case("/hh wars lists the wars, newest first", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("wars")
        T.ok(H.Printed("No wars recorded"), "none yet")
        Battle(ns, 1417)
        H.Slash("wars")
        T.ok(H.Printed("Arathi Highlands"), "the zone")
        T.ok(H.Printed("going on"), "still going")
        T.noErrors()
    end)
end
