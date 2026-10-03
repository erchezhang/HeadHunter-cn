-- HH-004: safe unit API, player identity, map and table helpers.

return function(T, H)
    -------------------------------------------------
    -- Identity
    -------------------------------------------------

    T.case("Era player keys are Name-Realm", function()
        local U = H.Boot({ client = "era" }).Utils
        T.eq(U.PlayerKey("Gank"), "Gank-Firemaw", "own realm filled in")
        T.eq(U.PlayerKey("Gank", "Stone Spine"), "Gank-StoneSpine", "realm spaces removed")
        T.eq(U.PlayerKey("Gank-Stonespine"), "Gank-Stonespine", "embedded realm kept")
        T.eq(U.PlayerKey("  Gank  "), "Gank-Firemaw", "trimmed")
        T.eq(U.PlayerKey("O\226\128\153Neil"), "O'Neil-Firemaw", "typographic apostrophe folded")
        T.eq(U.DisplayName("Gank-Firemaw"), "Gank", "own realm hidden")
        T.eq(U.DisplayName("Gank-Stonespine"), "Gank-Stonespine", "foreign realm shown")
        T.eq(U.UnitKey("player"), "Vati-Firemaw", "UnitKey")
    end)

    T.case("Era rejects placeholders and malformed names", function()
        local U = H.Boot({ client = "era" }).Utils
        T.eq(U.PlayerKey(nil), nil, "nil")
        T.eq(U.PlayerKey(""), nil, "empty")
        T.eq(U.PlayerKey("Unknown"), nil, "Unknown")
        T.eq(U.PlayerKey("Inconnu"), nil, "Inconnu")
        T.eq(U.PlayerKey("Two Words"), nil, "space in Era name")
        T.eq(U.PlayerKey("Bad|cffname"), nil, "escape sequence")
        T.eq(U.PlayerKey(42), nil, "non-string")
    end)

    T.case("Forever player keys are realmless 'Given Family'", function()
        local U = H.Boot({ client = "forever" }).Utils
        T.eq(U.PlayerKey("Grim Reaper"), "Grim Reaper", "plain")
        T.eq(U.PlayerKey("Grim   Reaper"), "Grim Reaper", "spaces collapsed")
        T.eq(U.PlayerKey("Grim Reaper-SomeRealm"), "Grim Reaper", "realm suffix dropped")
        T.eq(U.PlayerKey("Grim"), nil, "single word")
        T.eq(U.PlayerKey("A B C"), nil, "three words")
        T.eq(U.PlayerKey("Unknown Person"), nil, "placeholder")
        T.eq(U.DisplayName("Grim Reaper"), "Grim Reaper", "display unchanged")
        T.eq(U.UnitKey("player"), "Vati Guda", "UnitKey")
    end)

    T.case("Forever unit keys join UnitName's given + family values", function()
        local U = H.Boot({ client = "forever" }).Utils
        -- As seen in game: UnitName("target") -> "Joob", "Stabber"; GUID realm ClassicBetaPvP2
        H.units.target = { name = "Joob", realm = "Stabber", guid = "Player-4613-00BE1F94",
            guidRealm = "ClassicBetaPvP2", isPlayer = true }
        T.eq(U.UnitKey("target"), "Joob Stabber", "given + family")

        H.units.target = { name = "Joob", realm = "ClassicBetaPvP2", guid = "Player-9",
            guidRealm = "ClassicBetaPvP2", isPlayer = true }
        T.eq(U.UnitKey("target"), nil, "second value is the realm: not a family name")

        H.units.target = { name = "Joob", realm = "Firemaw", guid = "Player-9", isPlayer = true }
        T.eq(U.UnitKey("target"), nil, "second value is the player's realm")

        H.units.target = { name = "Joob", fullName = "Joob Stabber", guid = "Player-9", isPlayer = true }
        T.eq(U.UnitKey("target"), "Joob Stabber", "GetUnitName full form")

        H.units.target = { name = "Joob", guid = "Player-9", isPlayer = true }
        T.eq(U.UnitKey("target"), nil, "given name only")
        T.noErrors()
    end)

    -------------------------------------------------
    -- Unit wrappers
    -------------------------------------------------

    T.case("UnitLevel keeps skull, rejects junk, survives errors and secrets", function()
        local U = H.Boot({ client = "era" }).Utils
        H.units.target = { name = "Gank", level = 60, isPlayer = true }
        T.eq(U.UnitLevel("target"), 60, "normal")
        H.units.target.level = -1
        T.eq(U.UnitLevel("target"), -1, "skull")
        H.units.target.level = 0
        T.eq(U.UnitLevel("target"), nil, "zero is unknown")
        _G.UnitLevel = function() error("protected") end
        T.eq(U.UnitLevel("target"), nil, "raising API")
        _G.UnitLevel = function() return 60 end
        _G.canaccessvalue = function() return false end
        T.eq(U.UnitLevel("target"), nil, "secret value")
        T.eq(U.UnitName("target"), nil, "secret name")
        _G.canaccessvalue = nil
        T.noErrors()
    end)

    T.case("UnitSex, class and race tokens", function()
        local U = H.Boot({ client = "era" }).Utils
        H.units.target = { name = "Gank", sex = 3, class = "WARLOCK", race = "Scourge", isPlayer = true }
        T.eq(U.UnitSex("target"), 3, "female")
        T.eq(U.UnitClass("target"), "WARLOCK", "class token")
        T.eq(U.UnitRace("target"), "Scourge", "race token")
        T.eq(U.UnitSex("nobody"), 1, "unknown sex")
        T.eq(U.UnitClass("nobody"), nil, "missing unit")
    end)

    T.case("UnitIsEnemyPlayer needs a player of the other faction", function()
        local U = H.Boot({ client = "era" }).Utils
        H.units.target = { name = "Gank", faction = "Horde", isPlayer = true }
        T.eq(U.UnitIsEnemyPlayer("target"), true, "horde player")
        H.units.target.faction = "Alliance"
        T.eq(U.UnitIsEnemyPlayer("target"), false, "same faction")
        H.units.target = { name = "Defias Thug", faction = "Horde", isPlayer = false }
        T.eq(U.UnitIsEnemyPlayer("target"), false, "npc")
    end)

    -------------------------------------------------
    -- Map, time, tables, tokenizer
    -------------------------------------------------

    T.case("map helpers", function()
        local U = H.Boot({ client = "era" }).Utils
        T.eq(U.PlayerMapID(), 1429, "map")
        T.eq(U.MapName(1429), "Elwynn Forest", "name")
        T.eq(U.ContinentOf(1429), 1415, "continent")
        local x, y = U.PlayerPosition()
        T.eq(x, 0.42, "x")
        T.eq(y, 0.65, "y")
        _G.C_Map = nil
        T.eq(U.PlayerMapID(), nil, "no C_Map")
        T.eq(U.ContinentOf(1429), nil, "no C_Map continent")
        T.noErrors()
    end)

    T.case("ApplyDefaults copies tables and keeps existing values", function()
        local U = H.Boot({ client = "era" }).Utils
        local defaults = { list = {}, nested = { a = 1, b = 2 } }
        local one = U.ApplyDefaults({ nested = { a = 9 } }, defaults)
        local two = U.ApplyDefaults({}, defaults)
        T.eq(one.nested.a, 9, "existing kept")
        T.eq(one.nested.b, 2, "missing filled")
        T.ok(one.list ~= two.list and one.list ~= defaults.list, "tables not shared")
    end)

    T.case("Tokenize groups quoted words", function()
        local U = H.Boot({ client = "era" }).Utils
        local t = U.Tokenize('death "Grim Reaper" skull ROGUE Human')
        T.eq(#t, 5, "count")
        T.eq(t[2], "Grim Reaper", "quoted")
        T.eq(t[3], "skull", "after quote")
        local open = U.Tokenize('sim "Grim Reaper')
        T.eq(open[2], "Grim Reaper", "unterminated quote")
        T.eq(#U.Tokenize("   "), 0, "blank")
    end)

    -------------------------------------------------
    -- Distances in yards (HH-121 step 2)
    -------------------------------------------------

    T.case("map positions become world yards; distances only on one continent", function()
        local U = H.Boot({ client = "forever" }).Utils
        -- Made-up maps: 1 and 2 on continent 0 (a zone and its city), 3 on continent 1,
        -- each 1000 x 1000 yards, the city map starting 500 yards east of the zone
        local origins = { [1] = { 0, 0, 0 }, [2] = { 0, 500, 0 }, [3] = { 1, 0, 0 } }
        _G.CreateVector2D = function(x, y) return { x = x, y = y } end
        _G.C_Map.GetWorldPosFromMapPos = function(mapID, v)
            local o = origins[mapID]
            if not o then return nil end
            return o[1], { GetXY = function() return o[2] + v.x * 1000, o[3] + v.y * 1000 end }
        end

        local zone = U.WorldPos(1, 0.5, 0.5)
        T.eq(zone.continent, 0, "continent")
        T.eq(zone.x, 500, "x in yards")
        local city = U.WorldPos(2, 0.03, 0.54)
        T.eq(U.Yards(zone, city), 50, "a city map and its zone compare directly")
        local far = U.WorldPos(3, 0.5, 0.5)
        T.eq(U.Yards(zone, far), nil, "no distance across continents")
        T.eq(U.WorldPos(99, 0.5, 0.5), nil, "unknown map")
        T.eq(U.WorldPos(1, nil, 0.5), nil, "no position")

        T.eq(U.TooFar(zone, U.WorldPos(1, 0.6, 0.5), 0), false, "100 yards at once: within the margin")
        T.eq(U.TooFar(zone, U.WorldPos(1, 0.9, 0.5), 10), true, "400 yards in 10 s: too far")
        T.eq(U.TooFar(zone, U.WorldPos(1, 0.9, 0.5), 30), false, "400 yards in 30 s: a fast mount")
        T.eq(U.TooFar(zone, far, 0), false, "another continent is never too far")
        T.eq(U.TooFar(zone, nil, 0), false, "an unknown place is never too far")
        _G.CreateVector2D = nil
    end)
end
