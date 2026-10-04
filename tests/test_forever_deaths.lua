-- HH-012: killer detection from C_DeathRecap (WoW Forever).
-- Recap entries use the field names and values from the in-game probe (2026-09-23).

return function(T, H)
    local KUH, LOKI = "Player-4613-00A96B33", "Player-4613-00BF065F"
    local HOSTILE_PLAYER = 66888 -- sourceFlags seen in game (player + hostile)

    local function Hit(guid, name, overkill, amount, timestamp, flags)
        return {
            event = "SWING_DAMAGE", sourceGUID = guid, sourceName = name,
            sourceFlags = flags or HOSTILE_PLAYER, overkill = overkill, amount = amount or 50,
            timestamp = timestamp or 1790109611.265, destName = "Or", currentHP = 70,
        }
    end

    local function Setup()
        local ns = H.Boot({ client = "forever" })
        -- Seen on a nameplate 5 s before the death, as in the probe
        H.units.nameplate1 = { name = "Kuh", realm = "Blam", level = 20, class = "HUNTER", race = "Orc",
            sex = 2, faction = "Horde", isPlayer = true, guid = KUH }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.guidInfo[LOKI] = { class = "WARRIOR", race = "Tauren", sex = 2, name = "Lokiju", realm = "ClassicBetaPvP2" }
        return ns
    end

    T.case("recap killing blow is the exact killer; name and level come from the cache", function()
        local ns = Setup()
        H.recap = {
            Hit(KUH, "Kuh-ClassicBetaPvP2", 40, 110),
            Hit(LOKI, "Lokiju-ClassicBetaPvP2", -1, 30),
            Hit("Creature-0-1", "Plainstrider", -1, 5, nil, 0xA48),
        }
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 0, "waits for the recap")
        H.Advance(0.3)
        T.eq(#ns.db.deaths, 1, "recorded")
        local report = ns.db.deaths[1]
        T.eq(report.killer.key, "Kuh Blam", "full key from the cache")
        T.eq(report.killer.level, 20, "level from the cache")
        T.eq(report.confidence, "exact", "exact")
        T.eq(report.t, 1790109611, "recap timestamp")
        T.eq(report.classification, "giant", "level 20 killed level 30")
        T.eq(#report.assists, 1, "NPC is not an assist")
        T.eq(report.assists[1].name, "Lokiju", "assist given name")
        T.eq(report.assists[1].nameIncomplete, true, "assist incomplete")
        T.eq(report.assists[1].class, "WARRIOR", "assist class from GUID")
        T.eq(report.mapID, 1429, "map at death")
        T.noErrors()
    end)

    T.case("a hunter and their pet are one attacker, even with the owner known by name only", function()
        local ns = Setup()
        local pet = "Pet-0-6783-1-15275-165189-0800264887"
        ns.PetOwners:Learn(pet, "Kuh Blam") -- from the pet's tooltip: a name, no GUID
        H.recap = {
            Hit(KUH, "Kuh-ClassicBetaPvP2", 40, 110),
            Hit(pet, "Aida", -1, 30, nil, 0x1148),
            Hit(LOKI, "Lokiju-ClassicBetaPvP2", -1, 30),
        }
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        local report = ns.db.deaths[1]
        T.eq(report.killer.key, "Kuh Blam", "the hunter")
        T.eq(report.killer.sex, 2, "sex from the cache")
        T.eq(#report.assists, 1, "the pet is not a second Kuh")
        T.eq(report.assists[1].name, "Lokiju", "the other attacker")
        T.noErrors()
    end)

    T.case("a killer not seen before is recorded with the given name only", function()
        local ns = H.Boot({ client = "forever" })
        H.guidInfo[LOKI] = { class = "WARRIOR", race = "Tauren", sex = 2, name = "Lokiju", realm = "ClassicBetaPvP2" }
        H.recap = { Hit(LOKI, "Lokiju-ClassicBetaPvP2", 12) }
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        local killer = ns.db.deaths[1].killer
        T.eq(killer.key, nil, "no key yet")
        T.eq(killer.name, "Lokiju", "given name from the recap")
        T.eq(killer.nameIncomplete, true, "incomplete")
        T.ok(H.Printed("Killed by .*Lokiju"), "chat line still shown")
        T.noErrors()
    end)

    T.case("recap that is not ready yet is retried", function()
        local ns = Setup()
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        T.eq(#ns.db.deaths, 0, "not ready")
        H.recap = { Hit(KUH, "Kuh-ClassicBetaPvP2", 40) }
        H.Advance(0.7)
        T.eq(#ns.db.deaths, 1, "picked up on retry")
        T.eq(ns.db.deaths[1].confidence, "exact", "exact")
    end)

    T.case("no recap at all: fall back to the live enemy target (inferred)", function()
        local ns = Setup()
        H.units.target = { name = "Kuh", realm = "Blam", level = 20, class = "HUNTER", race = "Orc",
            faction = "Horde", isPlayer = true, guid = KUH }
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        H.Advance(0.7)
        T.eq(#ns.db.deaths, 0, "still retrying")
        H.Advance(1)
        T.eq(#ns.db.deaths, 1, "fallback after the last retry")
        T.eq(ns.db.deaths[1].killer.key, "Kuh Blam", "target")
        T.eq(ns.db.deaths[1].confidence, "inferred", "inferred")
    end)

    T.case("no recap and no likely attacker: nothing reported", function()
        local ns = H.Boot({ client = "forever" })
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3); H.Advance(0.7); H.Advance(1)
        T.eq(#ns.db.deaths, 0, "no report")
        T.noErrors()
    end)

    T.case("PvE recap is not reported", function()
        local ns = Setup()
        H.recap = { Hit("Creature-0-1", "Plainstrider", 10, 20, nil, 0xA48) }
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        T.eq(#ns.db.deaths, 0, "no report")
    end)

    T.case("hostile player in the recap but an NPC killing blow: the player gets a full kill", function()
        local ns = Setup()
        H.recap = {
            Hit("Creature-0-1", "Plainstrider", 10, 20, nil, 0xA48),
            Hit(KUH, "Kuh-ClassicBetaPvP2", -1, 60),
        }
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        T.eq(ns.db.deaths[1].killer.key, "Kuh Blam", "player credited")
        T.eq(ns.db.deaths[1].confidence, "exact", "full kill (author rule)")
    end)

    T.case("secret recap fields are treated as missing", function()
        local ns = Setup()
        H.recap = { Hit(KUH, "Kuh-ClassicBetaPvP2", 40) }
        _G.canaccessvalue = function(v) return v ~= HOSTILE_PLAYER end
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        T.eq(#ns.db.deaths, 0, "hostility unreadable: not reported")
        _G.canaccessvalue = nil
        T.noErrors()
    end)

    T.case("a same-faction (duel) source in the recap is ignored", function()
        local ns = Setup()
        H.guidInfo["Player-6-DUEL"] = { class = "WARRIOR", race = "Human", sex = 2, name = "Duelist" }
        H.recap = { Hit("Player-6-DUEL", "Duelist", 30) }
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        T.eq(#ns.db.deaths, 0, "no report")
        T.eq(ns.EnemyCache:PartialByGUID("Player-6-DUEL"), nil, "not cached")
    end)

    T.case("deaths inside instances are never reported", function()
        local ns = Setup()
        H.instance = { true, "arena" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        H.recap = { Hit(KUH, "Kuh-ClassicBetaPvP2", 40) }
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        T.eq(#ns.db.deaths, 0, "no report")
    end)

    T.case("a newer death supersedes a pending one", function()
        local ns = Setup()
        H.Fire("PLAYER_DEAD")
        H.Fire("PLAYER_DEAD")
        H.recap = { Hit(KUH, "Kuh-ClassicBetaPvP2", 40) }
        H.Advance(0.3)
        T.eq(#ns.db.deaths, 1, "only one report")
    end)
end
