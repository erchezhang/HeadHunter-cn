-- HH-011: killer detection from the combat log (Classic Era).

return function(T, H)
    local ME = "Player-1-00000001"
    local GANK, STAB, PET, MOB = "Player-2-AAAA", "Player-3-BBBB", "Pet-0-1", "Creature-0-1"

    local function Setup()
        local ns = H.Boot({ client = "era" })
        H.guidInfo[GANK] = { class = "ROGUE", race = "Orc", sex = 2, name = "Gank", realm = "Stonespine" }
        H.guidInfo[STAB] = { class = "WARRIOR", race = "Troll", sex = 3, name = "Stab", realm = "Stonespine" }
        return ns
    end

    local function Swing(sourceGUID, sourceName, flags, amount, overkill)
        H.FireCLEU(1, "SWING_DAMAGE", false, sourceGUID, sourceName, flags, 0,
            ME, "Vati", 0x511, 0, amount, overkill)
    end

    local function Spell(sourceGUID, sourceName, flags, amount, overkill)
        H.FireCLEU(1, "SPELL_DAMAGE", false, sourceGUID, sourceName, flags, 0,
            ME, "Vati", 0x511, 0, 1752, "Sinister Strike", 1, amount, overkill)
    end

    T.case("killing blow and assist, with level from an earlier nameplate", function()
        local ns = Setup()
        H.units.nameplate1 = { name = "Stab", realm = "Stonespine", level = 60, class = "WARRIOR",
            race = "Troll", faction = "Horde", isPlayer = true, guid = STAB }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")

        Swing(GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 300, -1)
        Spell(STAB, "Stab-Stonespine", H.FLAGS_HOSTILE_PLAYER, 120, 45)
        H.Fire("PLAYER_DEAD")

        T.eq(#ns.db.deaths, 1, "one report")
        local report = ns.db.deaths[1]
        T.eq(report.killer.key, "Stab-Stonespine", "killing blow wins over damage")
        T.eq(report.killer.level, 60, "level from the nameplate")
        T.eq(report.confidence, "exact", "exact")
        T.eq(report.classification, "coward", "60 vs 30")
        T.eq(#report.assists, 1, "one assist")
        T.eq(report.assists[1].key, "Gank-Stonespine", "assist")
        T.eq(report.assists[1].class, "ROGUE", "assist class from GUID")
        T.noErrors()
    end)

    T.case("NPC-only death is not reported", function()
        local ns = Setup()
        Swing(MOB, "Defias Thug", H.FLAGS_HOSTILE_NPC, 200, 10)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 0, "no report")
    end)

    T.case("NPC killing blow while a player was hitting: the player gets a full kill", function()
        local ns = Setup()
        Swing(GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 200, -1)
        Swing(MOB, "Defias Thug", H.FLAGS_HOSTILE_NPC, 50, 10)
        H.Fire("PLAYER_DEAD")
        T.eq(ns.db.deaths[1].killer.key, "Gank-Stonespine", "killer")
        T.eq(ns.db.deaths[1].confidence, "exact", "full kill (author rule)")
    end)

    T.case("a single hit by the ganker before a mob finishes us is a full kill", function()
        local ns = Setup()
        Swing(MOB, "Defias Thug", H.FLAGS_HOSTILE_NPC, 300, -1)
        Spell(GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 15, -1)
        Swing(MOB, "Defias Thug", H.FLAGS_HOSTILE_NPC, 80, 5)
        H.Fire("PLAYER_DEAD")
        T.eq(ns.db.deaths[1].killer.key, "Gank-Stonespine", "ganker credited")
        T.eq(ns.db.deaths[1].confidence, "exact", "full kill")
    end)

    T.case("hits older than the attacker window do not count", function()
        local ns = Setup()
        Swing(GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 200, -1)
        H.clock = H.clock + 20
        Swing(MOB, "Defias Thug", H.FLAGS_HOSTILE_NPC, 50, 10)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 0, "PvE death")
    end)

    T.case("a summoned pet's killing blow goes to its owner", function()
        local ns = Setup()
        H.FireCLEU(1, "SPELL_SUMMON", false, GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 0,
            PET, "Voidwalker", H.FLAGS_HOSTILE_PET, 0, 697, "Summon Voidwalker", 32)
        Swing(PET, "Voidwalker", H.FLAGS_HOSTILE_PET, 90, 12)
        H.Fire("PLAYER_DEAD")
        T.eq(ns.db.deaths[1].killer.key, "Gank-Stonespine", "owner credited")
        T.eq(ns.db.deaths[1].confidence, "exact", "exact")
    end)

    T.case("a hunter and their pet are one attacker, also when the owner is known by name only", function()
        local ns = Setup()
        ns.PetOwners:Learn(PET, "Gank-Stonespine", nil)
        Swing(PET, "Cat", H.FLAGS_HOSTILE_PET, 40)
        Spell(STAB, "Stab-Stonespine", H.FLAGS_HOSTILE_PLAYER, 30)
        Spell(GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 60, 5)
        H.Fire("PLAYER_DEAD")
        local report = ns.db.deaths[1]
        T.eq(report.killer.key, "Gank-Stonespine", "the hunter")
        T.eq(#report.assists, 1, "the hunter once, the other player as the one assist")
        T.eq(report.assists[1].key, "Stab-Stonespine", "the other player")
        T.noErrors()
    end)

    T.case("friendly players (duels, mind control) are ignored", function()
        local ns = Setup()
        Swing("Player-5", "Friend-Firemaw", H.FLAGS_FRIENDLY_PLAYER, 500, 20)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 0, "no report")
    end)

    -- Duel opponents are flagged hostile in the combat log, like enemies
    local DUELIST = "Player-6-DUEL"

    T.case("duel hits never count toward a later death", function()
        local ns = Setup()
        H.guidInfo[DUELIST] = { class = "WARRIOR", race = "Human", sex = 2, name = "Duelist", realm = "Firemaw" }
        Swing(DUELIST, "Duelist", H.FLAGS_HOSTILE_PLAYER, 400, -1)
        H.Fire("DUEL_FINISHED")
        Swing(MOB, "Defias Thug", H.FLAGS_HOSTILE_NPC, 50, 10)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 0, "no report")
        T.eq(ns.EnemyCache:ByGUID(DUELIST), nil, "duelist not cached as an enemy")
    end)

    T.case("same-faction hostile player is dropped even without a duel event", function()
        local ns = Setup()
        H.guidInfo[DUELIST] = { class = "WARRIOR", race = "Dwarf", sex = 2, name = "Duelist", realm = "Firemaw" }
        Swing(DUELIST, "Duelist", H.FLAGS_HOSTILE_PLAYER, 400, 20)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 0, "no report")
    end)

    T.case("an enemy who kills us right after a duel is still reported", function()
        local ns = Setup()
        H.guidInfo[DUELIST] = { class = "WARRIOR", race = "Human", sex = 2, name = "Duelist", realm = "Firemaw" }
        Swing(DUELIST, "Duelist", H.FLAGS_HOSTILE_PLAYER, 400, -1)
        H.Fire("DUEL_FINISHED")
        Swing(GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 300, 25)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 1, "reported")
        T.eq(ns.db.deaths[1].killer.key, "Gank-Stonespine", "real enemy")
        T.eq(#ns.db.deaths[1].assists, 0, "duelist is not an assist")
    end)

    T.case("deaths inside instances are never reported", function()
        local ns = Setup()
        H.instance = { true, "pvp" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        Swing(GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 300, 50)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 0, "no report in a battleground")
        H.instance = { false, "none" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 0, "battleground hits do not leak out")
        T.noErrors()
    end)

    T.case("attackers reset after each death", function()
        local ns = Setup()
        Swing(GANK, "Gank-Stonespine", H.FLAGS_HOSTILE_PLAYER, 300, 50)
        H.Fire("PLAYER_DEAD")
        H.serverTime = H.serverTime + 60
        Swing(MOB, "Defias Thug", H.FLAGS_HOSTILE_NPC, 200, 10)
        H.Fire("PLAYER_DEAD")
        T.eq(#ns.db.deaths, 1, "second death is PvE")
    end)
end
