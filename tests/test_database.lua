-- HH-003: database defaults, restore, migration guard and pruning.

return function(T, H)
    local DAY = 86400

    for _, client in ipairs({ "era", "forever" }) do
        T.case(client .. ": fresh load with no SavedVariables", function()
            local ns = H.Boot({ client = client })
            T.ok(ns.db ~= nil, "db created")
            T.eq(_G.HeadHunter_DB, ns.Database:Root(), "mirrored to the SavedVariable")
            T.eq(ns.Database.restoredFromDisk, false, "restoredFromDisk")
            T.eq(ns.db.meta.loadCount, 1, "loadCount")
            T.eq(ns.db.schemaVersion, ns.Database.SCHEMA_VERSION, "schema")
            T.eq(ns.db.settings.alerts.range, "adjacent", "default range")
            T.eq(#ns.db.deaths, 0, "no deaths")
            T.noErrors()
        end)
    end

    T.case("saves the account's region for the sync app", function()
        local ns = H.Boot({ client = "era" })
        for code, name in pairs({ [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }) do
            _G.GetCurrentRegion = function() return code end
            T.eq(ns.Utils.Region(), name, "region " .. code)
        end
        _G.GetCurrentRegion = function() return 3 end
        ns.Database:Initialize()
        T.eq(ns.db.meta.region, "eu", "saved in meta")
        _G.GetCurrentRegion = nil
        T.eq(ns.Utils.Region(), nil, "unknown without the API")
        ns.Database:Initialize()
        T.eq(ns.db.meta.region, "eu", "the last known region stays")
        T.noErrors()
    end)

    T.case("remembers the character played last and the client, for the sync app", function()
        local ns = H.Boot({ client = "era" })
        local player = ns.db.meta.player
        T.eq(ns.db.meta.client, "era", "client")
        T.eq(player.key, ns.Utils.UnitKey("player"), "key")
        T.eq(player.realm, ns.Utils.PlayerRealm(), "realm on Era")
        T.eq(player.class, "ROGUE", "class")
        T.eq(player.race, "Human", "race")
        T.eq(player.faction, "Alliance", "faction")
        T.eq(player.level, 30, "level")
        H.units.player.level = 31
        H.Fire("PLAYER_LOGOUT")
        T.eq(ns.db.meta.player.level, 31, "refreshed at logout")

        T.eq(player.server, nil, "no server number on Era")

        local forever = H.Boot({ client = "forever", playerGUID = "Player-4620-00ABCDEF" })
        T.eq(forever.db.meta.client, "forever", "Forever client")
        T.eq(forever.db.meta.player.realm, nil, "no realm on Forever")
        T.eq(forever.db.meta.player.server, 4620, "the server number tells the Forever realm")
        T.noErrors()
    end)

    T.case("restored partial database keeps values and gains defaults", function()
        local saved = { settings = { alerts = { range = "continent" } }, meta = { loadCount = 4 } }
        local ns = H.Boot({ client = "era", savedDB = saved })
        T.eq(ns.Database:Root(), saved, "same table")
        T.eq(ns.Database.restoredFromDisk, true, "restoredFromDisk")
        T.eq(ns.db.settings.alerts.range, "continent", "kept")
        T.eq(ns.db.settings.alerts.sound, true, "filled")
        T.eq(ns.db.meta.loadCount, 5, "load counted")
        T.eq(ns.db.schemaVersion, ns.Database.SCHEMA_VERSION, "schema stamped")
    end)

    T.case("a database from a newer addon version is left alone", function()
        local ns = H.Boot({ client = "era", savedDB = { schemaVersion = 99 } })
        T.eq(ns.db.schemaVersion, 99, "schema untouched")
    end)

    T.case("screenshots turn on once for saved data from 0.4.3 and 0.4.4 (off was the old default)", function()
        local ns = H.Boot({ client = "era", savedDB = { schemaVersion = 3, settings = { screenshots = false } } })
        T.eq(ns.Database:GetSetting("screenshots"), true, "turned on")
        ns.Database:SetSetting("screenshots", false)
        local saved = _G.HeadHunter_DB
        ns = H.Boot({ client = "era", savedDB = saved })
        T.eq(ns.Database:GetSetting("screenshots"), false, "a player's own off stays off after that")
    end)

    T.case("debug setting restores debug mode", function()
        local ns = H.Boot({ client = "era", savedDB = { settings = { debug = true } } })
        T.eq(ns.debugMode, true, "debugMode")
    end)

    T.case("prune drops old deaths and keeps the newest within the cap", function()
        local ns = H.Boot({ client = "era" })
        local now = H.serverTime
        local deaths = { { t = now - 31 * DAY } }
        for i = 1, 510 do deaths[#deaths + 1] = { t = now - 510 + i } end
        ns.db.deaths = deaths
        ns.Database:Prune(now)
        T.eq(#ns.db.deaths, 500, "capped")
        T.eq(ns.db.deaths[1].t, now - 499, "oldest kept")
        T.eq(ns.db.deaths[500].t, now, "newest kept")
    end)

    T.case("prune drops stale enemies and trims the oldest over the cap", function()
        local ns = H.Boot({ client = "era" })
        local now = H.serverTime
        ns.Database.LIMITS.enemies = 3
        ns.db.enemies = {
            stale = { lastSeen = now - 8 * DAY },
            a = { lastSeen = now - 40 },
            b = { lastSeen = now - 30 },
            c = { lastSeen = now - 20 },
            d = { lastSeen = now - 10 },
            broken = "not a table",
        }
        ns.Database:Prune(now)
        T.eq(ns.db.enemies.stale, nil, "stale removed")
        T.eq(ns.db.enemies.broken, nil, "junk removed")
        T.eq(ns.db.enemies.a, nil, "oldest trimmed")
        T.ok(ns.db.enemies.b and ns.db.enemies.c and ns.db.enemies.d, "newest kept")
    end)

    T.case("settings get/set by path fire HH_SETTING_CHANGED", function()
        local ns = H.Boot({ client = "era" })
        local changed
        ns.Events:Register("HH_SETTING_CHANGED", function(_, path, value) changed = path .. "=" .. tostring(value) end, "t")
        T.eq(ns.Database:SetSetting("alerts.range", "continent"), true, "set")
        T.eq(ns.Database:GetSetting("alerts.range"), "continent", "get")
        T.eq(changed, "alerts.range=continent", "event")
        T.eq(ns.Database:SetSetting("nope.deeper.key", 1), false, "unknown path")
    end)

    T.case("the debug log is kept across a reload", function()
        local ns = H.Boot({ client = "forever" })
        ns.Log:Add("info", "WANTED death seen before the reload")
        H.Fire("PLAYER_LOGOUT")
        local saved = _G.HeadHunter_DB
        T.ok(#saved.log > 0, "saved with the data")

        local after = H.Boot({ client = "forever", savedDB = saved })
        local text = table.concat(after.Log:Lines(), "\n")
        T.ok(text:find("WANTED death seen before the reload", 1, true) ~= nil, "still there")
        T.ok(text:find("Reload", 1, true) ~= nil, "the reload is marked")
        T.noErrors()
    end)

    T.case("logout stamps savedAt", function()
        local ns = H.Boot({ client = "forever" })
        H.serverTime = H.serverTime + 60
        H.Fire("PLAYER_LOGOUT")
        T.eq(ns.db.meta.savedAt, H.serverTime, "savedAt")
    end)
end
