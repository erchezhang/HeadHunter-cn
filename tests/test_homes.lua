-- Saved data per realm ("home", Core/Database.lua): each realm keeps its own deaths,
-- duels, bounty and enemies; old mixed data moves to one home. Made-up players only.

return function(T, H)
    local PVP, NORMAL = 4619, 4620

    local function GUID(server)
        return "Player-" .. server .. "-00ABCDEF"
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 5 do H.Advance(0) end
    end

    local function AddDuel(ns)
        ns.Duels:Add({ winner = "Grim Tusk", loser = "Moss Walker", t = H.serverTime - 60, faction = "Horde",
            winnerLevel = 20, loserLevel = 20 }, "local")
    end

    T.case("forever: each server keeps its own data; switching back brings it again", function()
        local pvp = H.Boot({ client = "forever", playerGUID = GUID(PVP) })
        AddDuel(pvp)
        pvp.db.deaths[#pvp.db.deaths + 1] = { id = "Vati Guda:1", t = H.serverTime - 30, victim = { key = "Vati Guda" } }
        pvp.db.marks.total = 7
        local saved = pvp.Database:Root()

        local normal = H.Boot({ client = "forever", playerGUID = GUID(NORMAL), savedDB = saved })
        T.eq(normal.Database:HomeKey(), "forever|" .. NORMAL, "the Normal realm's home")
        T.eq(#normal.db.deaths, 0, "no PvP deaths")
        T.eq(next(normal.db.duels), nil, "no PvP duels")
        T.eq(normal.db.marks.total, 0, "own bounty")
        T.eq(normal.db.settings.alerts.range, "adjacent", "settings are the account's")

        local back = H.Boot({ client = "forever", playerGUID = GUID(PVP), savedDB = saved })
        T.eq(#back.db.deaths, 1, "PvP deaths back")
        T.eq(back.db.marks.total, 7, "PvP bounty back")
        T.ok(next(back.db.duels) ~= nil, "PvP duels back")
        T.noErrors()
    end)

    T.case("each home keeps the region the game gave on it, not the account's last one", function()
        _G.GetCurrentRegion = function() return 1 end
        local us = H.Boot({ client = "forever", playerGUID = GUID(PVP) })
        local saved = us.Database:Root()
        _G.GetCurrentRegion = function() return 5 end
        H.Boot({ client = "forever", playerGUID = GUID(6746), savedDB = saved })
        _G.GetCurrentRegion = nil

        T.eq(saved.homes["forever|" .. PVP].region, "us", "the US server's home stays US")
        T.eq(saved.homes["forever|6746"].region, "cn", "the Chinese server's home is CN")
        T.eq(saved.meta.region, "cn", "the account's last region, as before")
        T.noErrors()
    end)

    T.case("era: each realm keeps its own data", function()
        local firemaw = H.Boot({ client = "era" })
        firemaw.db.marks.total = 3
        local saved = firemaw.Database:Root()
        H.Install({ client = "era" })
        H.realm = "Gehennas"
        local ns = H.Load()
        _G.HeadHunter_DB = saved
        H.Fire("ADDON_LOADED", "HeadHunter")
        T.eq(ns.Database:HomeKey(), "era|gehennas", "another realm")
        T.eq(ns.db.marks.total, 0, "its own bounty")
        T.eq(saved.homes["era|firemaw"].marks.total, 3, "Firemaw keeps its own")
        T.noErrors()
    end)

    T.case("old mixed data moves to the PvP server on Forever", function()
        local old = { schemaVersion = 1, meta = { loadCount = 3 },
            deaths = { { id = "Vati Guda:1", t = H.serverTime - 30, victim = { key = "Vati Guda" } } },
            marks = { total = 5, events = {} }, wanted = {} }
        local ns = H.Boot({ client = "forever", playerGUID = GUID(NORMAL), savedDB = old })
        local root = ns.Database:Root()
        T.eq(#root.homes["forever|" .. PVP].deaths, 1, "old deaths on the PvP server")
        T.eq(root.homes["forever|" .. PVP].marks.total, 5, "old bounty on the PvP server")
        T.eq(root.deaths, nil, "nothing left at the root")
        T.eq(root.wanted, nil, "the unused WANTED table is gone")
        T.eq(#ns.db.deaths, 0, "the Normal realm starts fresh")
        T.eq(root.schemaVersion, ns.Database.SCHEMA_VERSION, "schema stamped")
        T.noErrors()
    end)

    T.case("old mixed data on Era moves to the realm of the last character", function()
        local old = { schemaVersion = 1, meta = { player = { key = "Vati-Gehennas", realm = "Gehennas" } },
            marks = { total = 4, events = {} } }
        local ns = H.Boot({ client = "era", savedDB = old })
        T.eq(ns.Database:Root().homes["era|gehennas"].marks.total, 4, "old bounty on Gehennas")
        T.eq(ns.db.marks.total, 0, "Firemaw starts fresh")
        T.noErrors()
    end)

    T.case("the home is fixed once the game tells the server; modules hear it", function()
        local ns = H.Boot({ client = "forever", playerGUID = GUID(PVP) })
        local changed
        ns.Events:Register("HH_HOME_CHANGED", function(_, key) changed = key end, "test")
        H.units.player.guid = nil
        ns.Database:Initialize()
        T.eq(ns.Database:HomeKey(), "forever|" .. PVP, "the last home while the server is unknown")

        H.units.player.guid = GUID(NORMAL)
        T.eq(#ns.db.deaths, 0, "the first data access checks again")
        T.eq(ns.Database:HomeKey(), "forever|" .. NORMAL, "moved to the right home")
        Settle()
        T.eq(changed, "forever|" .. NORMAL, "HH_HOME_CHANGED fired")
        T.noErrors()
    end)

    T.case("each home remembers its own last character for the sync app", function()
        local ns = H.Boot({ client = "forever", playerGUID = GUID(NORMAL) })
        H.Fire("PLAYER_LOGOUT")
        local root = ns.Database:Root()
        T.eq(root.homes["forever|" .. NORMAL].player.server, NORMAL, "the home's player")
        T.eq(root.meta.player.key, root.homes["forever|" .. NORMAL].player.key, "and the account's last one")
        T.eq(root.meta.home, "forever|" .. NORMAL, "the last home")
        T.noErrors()
    end)
end
