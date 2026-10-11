-- HH-013: the report pipeline (validation, storage, classification, completion).

return function(T, H)
    T.case("a simulated death is recorded, classified and announced", function()
        local ns = H.Boot({ client = "forever" })
        local recorded
        ns.Events:Register("HH_DEATH_RECORDED", function(_, report) recorded = report end, "t")
        H.Slash('sim death "Grim Reaper" skull ROGUE Orc')
        T.eq(#ns.db.deaths, 1, "stored")
        local report = ns.db.deaths[1]
        T.eq(recorded, report, "HH_DEATH_RECORDED")
        T.eq(report.classification, "coward", "skull is coward")
        T.eq(report.victim.level, 30, "victim level")
        T.eq(report.confidence, "sim", "confidence")
        T.ok(H.Printed("Killed by .*Grim Reaper"), "chat line")
        T.ok(H.Printed("Bully kill"), "classification shown")
        T.noErrors()
    end)

    T.case("the same report id is only recorded once", function()
        local ns = H.Boot({ client = "era" })
        local t = H.serverTime
        ns.DeathReports:Record({ id = "Vati-Firemaw:1", t = t, killer = { key = "Gank-Stonespine", level = 30 } }, "test")
        ns.DeathReports:Record({ id = "Vati-Firemaw:1", t = t, killer = { key = "Gank-Stonespine" } }, "test")
        T.eq(#ns.db.deaths, 1, "deduplicated")
        T.eq(ns.db.deaths[1].classification, "fair", "30 vs 30")
    end)

    T.case("invalid reports are dropped", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.DeathReports:Record({ t = 1 }, "test"), nil, "no killer")
        T.eq(ns.DeathReports:Record("junk", "test"), nil, "not a table")
        H.units.player.name = nil
        T.eq(ns.DeathReports:Record({ killer = { key = "X-Y" } }, "test"), nil, "victim unknown")
        T.eq(#ns.db.deaths, 0, "nothing stored")
        T.noErrors()
    end)

    T.case("a report fills time, victim and position when missing", function()
        local ns = H.Boot({ client = "era" })
        local report = ns.DeathReports:Record({ killer = { key = "Gank-Stonespine", level = 45 } }, "test")
        T.eq(report.t, H.serverTime, "time")
        T.eq(report.id, "Vati-Firemaw:" .. H.serverTime, "id")
        T.eq(report.victim.key, "Vati-Firemaw", "victim")
        T.eq(report.mapID, 1429, "map")
        T.eq(report.x, 0.42, "x")
        T.eq(report.classification, "coward", "45 vs 30 is 15 levels")
    end)

    T.case("an incomplete killer is completed when its GUID is resolved", function()
        local ns = H.Boot({ client = "forever" })
        local updated
        ns.Events:Register("HH_DEATH_UPDATED", function(_, report) updated = report end, "t")
        local report = ns.DeathReports:Record({
            killer = { guid = "Player-7", name = "Kuh", nameIncomplete = true, class = "HUNTER" },
            assists = { { guid = "Player-8", name = "Lokiju", nameIncomplete = true } },
        }, "test")
        T.eq(report.classification, "unknown", "no level yet")

        H.units.nameplate1 = { name = "Kuh", realm = "Blam", level = 30, class = "HUNTER", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-7" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        T.eq(report.killer.key, "Kuh Blam", "killer completed")
        T.eq(report.killer.nameIncomplete, nil, "flag cleared")
        T.eq(report.killer.level, 30, "level filled")
        T.eq(report.classification, "fair", "reclassified")
        T.eq(updated, report, "HH_DEATH_UPDATED")

        H.units.nameplate2 = { name = "Lokiju", realm = "Hardwood", level = 20, faction = "Horde",
            isPlayer = true, guid = "Player-8" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        T.eq(report.assists[1].key, "Lokiju Hardwood", "assist completed")
        T.noErrors()
    end)

    T.case("/hh deaths lists newest first", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim death Gank 60 ROGUE Orc")
        H.serverTime = H.serverTime + 100
        H.Slash("sim death Stab 31 WARRIOR Troll")
        H.Slash("deaths")
        T.ok(H.Printed("PvP deaths recorded: 2"), "header")
        local first, second
        for i, line in ipairs(H.printed) do
            -- Own-realm names are shown without the realm
            if line:find("^  .* Stab %(") then first = first or i end
            if line:find("^  .* Gank %(") then second = second or i end
        end
        T.ok(first and second and first < second, "newest first")
        T.noErrors()
    end)

    T.case("group members in the fight make it a group fight", function()
        local ns = H.Boot({ client = "forever" })
        H.inGroup = true
        H.units.party1 = { name = "Brakka Stonefist", isPlayer = true, inCombat = true, inRange = true }
        H.units.party2 = { name = "Zulgar Mossback", isPlayer = true, dead = true, inCombat = false, inRange = true }
        H.units.party3 = { name = "Thrag Ironhide", isPlayer = true, inCombat = true, inRange = false }
        H.units.party4 = { name = "Mog Bristleback", isPlayer = true, inCombat = false, inRange = true }
        T.eq(ns.DeathReports.CountHelpers(), 2, "in combat or dead, and near")
        local killer = { key = "Kira Dawnblade", level = 30 }
        local assists = { { key = "Ellis Brightwood", level = 30 }, { key = "Tobin Ashford", level = 30 },
            { key = "Rowan Fairhill", level = 30 } }
        local report = ns.DeathReports:Record({ t = H.serverTime, killer = killer, assists = assists }, "test")
        T.eq(report.helpers, 2, "stored on the report")
        T.ok(H.Printed("Group fight.* %(4 vs 3%)"), "chat line says 4 vs 3")

        H.inGroup = false
        T.eq(ns.DeathReports.CountHelpers(), 0, "no group: alone")
        T.noErrors()
    end)

    T.case("group members far away in our zone are not in the fight (HH-143)", function()
        local ns = H.Boot({ client = "forever" })
        _G.CreateVector2D = function(x, y) return { x = x, y = y } end
        _G.C_Map.GetWorldPosFromMapPos = function(_, v)
            return 0, { GetXY = function() return v.x * 1000, v.y * 1000 end }
        end
        H.inGroup = true
        H.playerX, H.playerY = 0.5, 0.5
        H.units.party1 = { name = "Brakka Stonefist", isPlayer = true, inCombat = true, x = 0.53, y = 0.5 }
        H.units.party2 = { name = "Zulgar Mossback", isPlayer = true, dead = true, map = H.playerMap, x = 0.9, y = 0.1 }
        H.units.party3 = { name = "Thrag Ironhide", isPlayer = true, inCombat = true, map = H.playerMap }
        H.units.party4 = { name = "Mog Bristleback", isPlayer = true, inCombat = true, inRange = true, x = 0.1, y = 0.9 }
        T.eq(ns.Utils.UnitYards("party1"), 30, "30 yards from us")
        T.eq(ns.Utils.UnitYards("party3"), nil, "no place known")
        T.eq(ns.DeathReports.CountHelpers(), 1, "only the one within 100 yards")

        local report = ns.DeathReports:Record({ t = H.serverTime, killer = { key = "Fizz Sparkle", level = 23 } }, "test")
        H.units.party1 = nil
        local alone = ns.DeathReports:Record({ t = H.serverTime + 60, killer = { key = "Fizz Sparkle", level = 23 } }, "test")
        T.eq(report.helpers, 1, "the one close by")
        T.eq(alone.helpers, 0, "a raid across the zone: alone")
        _G.CreateVector2D = nil
        T.noErrors()
    end)
end
