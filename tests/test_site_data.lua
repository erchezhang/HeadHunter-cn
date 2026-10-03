-- HH-082: website data from the HeadHunter_Data addon (Sync/SiteData.lua): world
-- choice, WANTED and Duels merge, and our own records restored at login.
-- Made-up players only.

return function(T, H)
    local function Settle()
        H.Advance(1)
        for _ = 1, 20 do H.Advance(0) end
    end

    local function Outlaw(name, overrides)
        local w = {
            name = name, realm = "Firemaw", faction = "horde", class = "rogue", race = "undead", sex = 2, level = 34,
            rank = "most_wanted", kills = 31, badges = { "coward", "serial_killer" },
            wanted_since = H.serverTime - 7200, wanted_until = H.serverTime + 86400,
            last_kill_at = H.serverTime - 3600, last_map_id = 1436, times_wanted = 2, times_caught = 1,
            kill_count = 40, coward_kills = 12,
        }
        for k, v in pairs(overrides or {}) do w[k] = v end
        return w
    end

    local function Duelist(name, wins, losses)
        return { name = name, realm = "Firemaw", class = "warrior", race = "human", sex = 2,
            wins = wins, losses = losses, duels = wins + losses, net = wins - losses, last_duel_at = H.serverTime - 7200 }
    end

    local function EraData(overrides)
        local data = {
            format_version = 1,
            generated_at = H.serverTime - 600,
            worlds = {
                ["era|eu|Firemaw"] = {
                    generated_at = H.serverTime - 600,
                    wanted = { Outlaw("Duskblade") },
                    duels = { alliance = { Duelist("Ironmaple", 6, 1) }, horde = {} },
                },
                ["era|eu|Gehennas"] = {
                    generated_at = H.serverTime - 600,
                    wanted = { Outlaw("Otherrealm", { realm = "Gehennas" }) },
                    duels = { alliance = {}, horde = {} },
                },
            },
            characters = {},
        }
        for k, v in pairs(overrides or {}) do data[k] = v end
        return data
    end

    T.case("no website data: nothing changes", function()
        local ns = H.Boot({ client = "era" })
        Settle()
        T.eq(ns.SiteData:GeneratedAt(), nil, "no data")
        T.eq(ns.SiteData:Wanted(), nil, "no WANTED list")
        T.eq(#ns.Wanted:List(), 0, "nobody WANTED")
        T.noErrors()
    end)

    T.case("on the website's WANTED list ourselves: told once at login", function()
        local data = EraData()
        table.insert(data.worlds["era|eu|Firemaw"].wanted, Outlaw("Vati", { faction = "alliance", race = "human",
            rank = "ganker", kills = 5 }))
        local ns = H.Boot({ client = "era", siteData = data })
        Settle()
        H.Advance(ns.SiteData.SELF_WANTED_DELAY)
        T.ok(H.Printed("You are WANTED.* by the Horde: .*Ganker.*, 5 kills"), "chat line")
        T.eq(H.centerTexts[#H.centerTexts], "You are WANTED!", "center text")

        ns = H.Boot({ client = "era", siteData = EraData() })
        Settle()
        H.Advance(ns.SiteData.SELF_WANTED_DELAY)
        T.ok(not H.Printed("You are WANTED"), "not on the list: nothing")
        T.noErrors()
    end)

    T.case("an unknown format is ignored", function()
        local ns = H.Boot({ client = "era", siteData = { format_version = 99, worlds = {} } })
        Settle()
        T.eq(ns.SiteData:GeneratedAt(), nil, "ignored")
        T.noErrors()
    end)

    T.case("Era takes the world of our realm and maps the website's names", function()
        local ns = H.Boot({ client = "era", siteData = EraData() })
        Settle()
        T.eq(ns.SiteData:GeneratedAt(), H.serverTime - 600, "our world")
        local list = ns.Wanted:List()
        T.eq(#list, 1, "only our realm's outlaw")
        local e = list[1]
        T.eq(e.key, "Duskblade-Firemaw", "player key")
        T.eq(e.rank, "mostwanted", "rank token")
        T.eq(e.class, "ROGUE", "class token")
        T.eq(e.race, "Scourge", "race token")
        T.ok(e.badges.coward and e.badges.serialkiller, "badge tokens")
        T.eq(e.lastKill.t, H.serverTime - 3600, "last kill")
        T.eq(e.cowardKills, 12, "coward kills for the Hall of Shame")
        T.eq(e.source, "website", "marked as website")
        T.noErrors()
    end)

    T.case("the website's bullies join our Hall of Shame, alert and pay +3 when brought down", function()
        local data = EraData()
        data.worlds["era|eu|Firemaw"].bullies = {
            { name = "Greystomp", realm = "Firemaw", faction = "horde", class = "warrior", race = "orc", level = 40,
                coward_kills = 4, kill_count = 9, last_kill_at = H.serverTime - 86400 },
            { name = "Duskblade", realm = "Firemaw", faction = "horde", class = "rogue", race = "undead", level = 34,
                coward_kills = 20, kill_count = 45, last_kill_at = H.serverTime - 3600 },
            { name = "Broken", realm = "Firemaw", coward_kills = 0 },
        }
        local ns = H.Boot({ client = "era", siteData = data })
        Settle()
        local grey = ns.Wanted:ByKey("Greystomp-Firemaw")
        T.ok(grey ~= nil and grey.badges.coward, "a bully we never saw")
        T.eq(grey.wanted, false, "not WANTED")
        T.eq(#ns.Wanted:List(), 1, "the WANTED list is unchanged")
        T.eq(ns.Wanted:ByKey("Duskblade-Firemaw").cowardKills, 20, "the higher bully count wins")
        T.eq(ns.Wanted:ByKey("Broken-Firemaw"), nil, "no bully kills: left out")

        local names = {}
        for _, row in ipairs(ns.MainWindow.Rows("bullies")) do names[#names + 1] = row.name .. ":" .. row.coward end
        T.ok(table.concat(names, " "):find("Greystomp.*:4") ~= nil, "in the Bullies tab")

        ns.Sighting:OnEnemySeen({ key = "Greystomp-Firemaw", level = 40, class = "WARRIOR", race = "Orc" }, "target")
        T.ok(H.Printed("BULLY.*Greystomp.*4 kills of lowbies"), "the bully alert")

        H.FireCLEU(H.serverTime, "PARTY_KILL", false, "Player-1-00000001", "Vati", H.FLAGS_FRIENDLY_PLAYER, 0,
            "Player-2-0000BEEF", "Greystomp", H.FLAGS_HOSTILE_PLAYER, 0)
        Settle()
        T.eq(ns.Marks:Total(), 3, "+3 bounty for bringing them down")
        T.noErrors()
    end)

    T.case("a realm name with spaces matches our normalized realm", function()
        H.Install({ client = "era" })
        local data = EraData()
        data.worlds = { ["era|eu|Living Flame"] = data.worlds["era|eu|Firemaw"] }
        data.worlds["era|eu|Living Flame"].wanted = { Outlaw("Duskblade", { realm = "Living Flame" }) }
        local ns = H.Boot({ client = "era", siteData = data })
        H.realm = "LivingFlame"
        ns.SiteData:Load()
        T.eq(ns.SiteData:GeneratedAt(), H.serverTime - 600, "matched without spaces")
        T.ok(ns.SiteData:Wanted()["Duskblade-LivingFlame"], "key without spaces")
        H.realm = "Firemaw"
        T.noErrors()
    end)

    T.case("Forever takes the world of our client and region", function()
        local data = {
            format_version = 1,
            worlds = {
                ["forever|us|pvp"] = { generated_at = H.serverTime - 60, wanted = { Outlaw("Grim Tusk", { realm = nil }) },
                    duels = { alliance = {}, horde = {} } },
                ["era|us|Firemaw"] = { generated_at = H.serverTime - 60, wanted = { Outlaw("Duskblade") } },
            },
            characters = {},
        }
        local ns = H.Boot({ client = "forever", siteData = data })
        Settle()
        local list = ns.Wanted:List()
        T.eq(#list, 1, "the Forever world only")
        T.eq(list[1].key, "Grim Tusk", "Forever key has no realm")
        T.noErrors()
    end)

    local function ForeverData(servers)
        local function Character(name, t)
            return { name = name, deaths = {}, duels = {}, catches = {}, bounty = { total = 3, events = {
                { t = t, type = "catch", bounty = 3, total_after = 3, outlaw_name = "Somebody", outlaw_rank = "ganker" },
            } } }
        end
        local pvpMain, pveAlt = Character("Pvp Main", H.serverTime - 900), Character("Pve Alt", H.serverTime - 800)
        pvpMain.world, pveAlt.world = "forever|us|pvp", "forever|us|pve"
        return {
            format_version = 1,
            forever_servers = servers,
            worlds = {
                ["forever|us|pvp"] = { generated_at = H.serverTime - 60, wanted = { Outlaw("Pvp Ganker", { realm = nil }) },
                    duels = { alliance = {}, horde = {} } },
                ["forever|us|pve"] = { generated_at = H.serverTime - 60, wanted = { Outlaw("Pve Ganker", { realm = nil }) },
                    duels = { alliance = {}, horde = {} } },
            },
            characters = { pvpMain, pveAlt },
        }
    end

    local function RestoredFrom(ns)
        local names = {}
        for _, event in ipairs(ns.db.marks.events) do names[#names + 1] = event.hunter end
        table.sort(names)
        return table.concat(names, ",")
    end

    T.case("forever: our server number picks our realm's lists and only its characters", function()
        local ns = H.Boot({ client = "forever", playerGUID = "Player-4620-00ABCDEF",
            siteData = ForeverData({ ["4619"] = "pvp", ["4620"] = "pve" }) })
        Settle()
        local list = ns.Wanted:List()
        T.eq(#list, 1, "one world only")
        T.eq(list[1].key, "Pve Ganker", "the Normal realm's list")
        T.eq(RestoredFrom(ns), "Pve Alt", "only the Normal realm's character is restored")

        local pvp = H.Boot({ client = "forever", playerGUID = "Player-4619-00ABCDEF",
            siteData = ForeverData({ ["4619"] = "pvp", ["4620"] = "pve" }) })
        Settle()
        T.eq(pvp.Wanted:List()[1].key, "Pvp Ganker", "the PvP realm's list")
        T.eq(RestoredFrom(pvp), "Pvp Main", "only the PvP realm's character")
        T.noErrors()
    end)

    T.case("forever: a server the website does not know yet, or an older file, works as before", function()
        local ns = H.Boot({ client = "forever", playerGUID = "Player-4700-00ABCDEF",
            siteData = ForeverData({ ["4619"] = "pvp", ["4620"] = "pve" }) })
        Settle()
        T.eq(#ns.Wanted:List(), 1, "a list as before")
        T.eq(RestoredFrom(ns), "Pve Alt,Pvp Main", "every Forever character as before")

        local old = H.Boot({ client = "forever", playerGUID = "Player-4620-00ABCDEF", siteData = ForeverData(nil) })
        Settle()
        T.eq(#old.Wanted:List(), 1, "no server list: a list as before")
        T.noErrors()
    end)

    T.case("an expired website entry, or one we caught since, is not WANTED", function()
        local data = EraData()
        data.worlds["era|eu|Firemaw"].wanted = {
            Outlaw("Duskblade", { wanted_until = H.serverTime - 1 }),
            Outlaw("Stonejaw"),
        }
        local ns = H.Boot({ client = "era", siteData = data })
        ns.Justice:Add({ id = "Stonejaw-Firemaw:" .. (H.serverTime - 60), outlaw = "Stonejaw-Firemaw",
            t = H.serverTime - 60, hunter = "Vati-Firemaw" }, "local")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "expired and caught")
        T.noErrors()
    end)

    T.case("MergeSite keeps whichever side saw the newer kill", function()
        local ns = H.Boot({ client = "era" })
        local now = H.serverTime
        local site = {
            A = { id = "A", wanted = true, rank = "desperado", kills = 22, wantedUntil = now + 100, lastKill = { t = now - 50 } },
            B = { id = "B", wanted = true, rank = "outlaw", kills = 11, wantedUntil = now + 100, lastKill = { t = now - 500 } },
            C = { id = "C", wanted = true, rank = "ganker", kills = 5, wantedUntil = now + 100, lastKill = { t = now - 50 } },
        }
        local entries = {
            A = { id = "A", wanted = true, rank = "ganker", kills = 4, lastKill = { t = now - 100 }, guid = "g-A", killCount = 99 },
            B = { id = "B", wanted = true, rank = "ganker", kills = 6, lastKill = { t = now - 10 } },
            C = { id = "C", wanted = false, lastKill = { t = now - 900 } },
        }
        ns.Wanted.MergeSite(entries, site, {}, now)
        T.eq(entries.A.rank, "desperado", "website newer: theirs")
        T.eq(entries.A.guid, "g-A", "our GUID kept")
        T.eq(entries.A.killCount, 99, "the larger kill count kept")
        T.eq(entries.B.rank, "ganker", "ours newer: ours")
        T.eq(entries.C.wanted, true, "not WANTED here, WANTED on the website")
        T.noErrors()
    end)

    T.case("the Duels list starts from the website and adds newer local duels", function()
        local ns = H.Boot({ client = "era", siteData = EraData() })
        local function Duel(winner, loser, t)
            ns.Duels:Add({ winner = winner, loser = loser, t = t, faction = "Alliance", winnerLevel = 30, loserLevel = 30 }, "local")
        end
        -- The website's last duel of Ironmaple is 2 h ago (Duelist last_duel_at)
        Duel("Ironmaple-Firemaw", "Fernwick-Firemaw", H.serverTime - 8000) -- before it: already counted there
        Duel("Ironmaple-Firemaw", "Fernwick-Firemaw", H.serverTime - 60)   -- after: added
        Settle()
        local maple = ns.HighNoon:Get("Ironmaple-Firemaw")
        T.eq(maple.wins, 7, "6 from the website + 1 newer")
        T.eq(maple.losses, 1, "losses from the website")
        T.eq(maple.source, "website", "website record")
        local fern = ns.HighNoon:Get("Fernwick-Firemaw")
        T.eq(fern.losses, 2, "not on the website: all our duels count")
        T.noErrors()
    end)

    T.case("a list the website had not rebuilt yet still gets our newer duels", function()
        -- The list is 10 min old, but Ironmaple's last duel on it is 2 h old: the sync
        -- app fetched it before the website counted our upload
        local ns = H.Boot({ client = "era", siteData = EraData() })
        ns.Duels:Add({ winner = "Ironmaple-Firemaw", loser = "Fernwick-Firemaw", t = H.serverTime - 3000,
            faction = "Alliance", winnerLevel = 30, loserLevel = 30 }, "local")
        Settle()
        T.eq(ns.HighNoon:Get("Ironmaple-Firemaw").wins, 7, "counted, although older than the list")
        local list = ns.HighNoon:List("Alliance")
        T.eq(list[1].key, "Ironmaple-Firemaw", "leader")
        T.eq(list[1].topGun, true, "Top Gun")
        T.noErrors()
    end)

    T.case("our own records come back at login, once, marked as website", function()
        local data = EraData({
            characters = {
                {
                    world = "era|eu|Firemaw", name = "Vati",
                    deaths = { {
                        t = H.serverTime - 5000, victim_level = 30, victim_class = "rogue", victim_race = "human",
                        map_id = 1429, x = 0.4, y = 0.6, confidence = "exact", classification = "coward",
                        attackers = {
                            { role = "killer", name = "Duskblade", realm = "Firemaw", class = "rogue", race = "undead", level = 40 },
                            { role = "assist", given_name = "Sneak", guid = "Player-1-0ABC", skull = true },
                        },
                    } },
                    duels = { {
                        t = H.serverTime - 4000,
                        winner = { name = "Vati", realm = "Firemaw", class = "rogue", race = "human" },
                        loser = { name = "Fernwick", realm = "Firemaw", class = "mage", race = "gnome" },
                        winner_level = 30, loser_level = 29, map_id = 1429, faction = "alliance",
                    } },
                    catches = { { t = H.serverTime - 3000, outlaw = { name = "Duskblade", realm = "Firemaw" }, map_id = 1436 } },
                    bounty = { total = 12, events = {
                        { t = H.serverTime - 3000, type = "catch", bounty = 12, total_after = 12, outlaw_name = "Duskblade", outlaw_rank = "most_wanted" },
                    } },
                },
                { world = "era|eu|Gehennas", name = "Elsewhere", deaths = { { t = H.serverTime - 100, victim_level = 10,
                    attackers = { { role = "killer", name = "X", realm = "Gehennas" } } } } },
            },
        })
        local ns = H.Boot({ client = "era", siteData = data })
        Settle()

        T.eq(#ns.db.deaths, 1, "our death restored, not the other realm's")
        local death = ns.db.deaths[1]
        T.eq(death.id, "Vati-Firemaw:" .. (H.serverTime - 5000), "the addon's death id")
        T.eq(death.killer.key, "Duskblade-Firemaw", "killer key")
        T.eq(death.killer.race, "Scourge", "killer race token")
        T.eq(death.assists[1].nameIncomplete, true, "given-name-only assist")
        T.eq(death.assists[1].level, -1, "skull")
        T.eq(death.origin, "website", "marked")
        T.eq(ns.Duels:Count(), 1, "duel restored")
        local _, duel = next(ns.db.duels)
        T.eq(duel.faction, "Alliance", "faction token")
        T.eq(duel.origin, "website", "duel marked")
        local catch = ns.Justice:Get("Duskblade-Firemaw:" .. (H.serverTime - 3000))
        T.ok(catch and catch.hunter == "Vati-Firemaw", "catch restored with its hunter")
        T.eq(ns.db.marks.total, 12, "our bounty total")
        T.eq(#ns.db.marks.events, 1, "bounty event restored")
        T.eq(ns.db.marks.events[1].rank, "mostwanted", "rank token")

        T.eq(ns.SiteData:Restore(), 0, "a second restore adds nothing")
        T.noErrors()
    end)

    T.case("the window says when the website list is from", function()
        local ns = H.Boot({ client = "era", siteData = EraData() })
        Settle()
        H.Slash("")
        ns.MainWindow:SelectTab("wanted")
        local count = _G.HeadHunterMainFrame.count.shownText
        T.ok(count:find("website list from 10 min ago", 1, true), "note on the WANTED tab: " .. count)
        ns.MainWindow:SelectTab("deaths")
        T.ok(not _G.HeadHunterMainFrame.count.shownText:find("website", 1, true), "not on My deaths")
        T.noErrors()
    end)
end
