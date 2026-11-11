-- HH-141: the website's lists shared in game (Sync/SharedSite.lua): two vouchers, withdrawn
-- entries, our own download first, catch-up, the broadcast and its limits. Made-up players only.

return function(T, H)
    local function Settle()
        H.Advance(1)
        for _ = 1, 20 do H.Advance(0) end
    end

    local function Outlaw(name, overrides)
        local w = {
            name = name, realm = "Firemaw", faction = "horde", class = "rogue", race = "undead", sex = 2, level = 34,
            rank = "most_wanted", kills = 31, badges = { "coward" },
            wanted_since = H.serverTime - 7200, wanted_until = H.serverTime + 86400,
            last_kill_at = H.serverTime - 3600, last_map_id = 1436, times_wanted = 2, times_caught = 1,
            kill_count = 40, coward_kills = 12,
        }
        for k, v in pairs(overrides or {}) do w[k] = v end
        return w
    end

    -- The HeadHunter_Data file with one world, Firemaw, holding these lists
    local function Data(generatedAt, lists)
        local world = { generated_at = generatedAt, duels = { alliance = {}, horde = {} } }
        for k, v in pairs(lists or {}) do world[k] = v end
        return { format_version = 1, generated_at = generatedAt, worlds = { ["era|eu|Firemaw"] = world }, characters = {} }
    end

    -- A list as a HeadHunter with the sync app shares it (boots that HeadHunter: build
    -- every list before the receiver boots)
    local function List(generatedAt, wanted, extra)
        local lists = { wanted = wanted or { Outlaw("Duskblade") } }
        for k, v in pairs(extra or {}) do lists[k] = v end
        local sender = H.Boot({ client = "era", siteData = Data(generatedAt, lists) })
        return sender.SharedSite.Records(sender.SharedSite.BROADCAST_MAX)
    end

    local function Deliver(ns, records, sender)
        H.Deliver(ns.Protocol.Pack("A", "C", records), sender)
    end

    local function Wanted(ns)
        ns.Wanted:ComputeNow()
        local names = {}
        for _, entry in ipairs(ns.Wanted:List()) do names[#names + 1] = entry.key end
        table.sort(names)
        return table.concat(names, ",")
    end

    T.case("a shared list's records read back as the website's entries", function()
        local records = List(H.serverTime - 600, nil, {
            bullies = { { name = "Bully", realm = "Firemaw", class = "warrior", race = "orc", coward_kills = 4, kill_count = 6 } },
            deadbeats = { { name = "Miser", realm = "Firemaw", unpaid = 3, blocked_until = H.serverTime + 3600 } },
        })
        local ns = H.Boot({ client = "era" })
        local kinds = {}
        for _, record in ipairs(records) do
            local kind, gen, key, entry = ns.SharedSite.Decode(record)
            kinds[#kinds + 1] = kind
            T.eq(gen, H.serverTime - 600, "the list time")
            if kind == "W" then
                T.eq(key, "Duskblade-Firemaw", "who")
                T.eq(entry.rank, "mostwanted", "rank")
                T.eq(entry.kills, 31, "kills")
                T.eq(entry.lastKill.mapID, 1436, "where")
            end
        end
        T.eq(table.concat(kinds, ","), "L,W,B,D", "a marker, then each list")
        T.noErrors()
    end)

    T.case("one HeadHunter's word makes nobody WANTED; a second one does", function()
        local records = List(H.serverTime - 600)
        local ns = H.Boot({ client = "era" })
        Deliver(ns, records, "Alpha-Firemaw")
        T.eq(Wanted(ns), "", "one voucher")
        Deliver(ns, records, "Alpha-Firemaw")
        T.eq(Wanted(ns), "", "the same voucher twice is still one")
        Deliver(ns, records, "Bravo-Firemaw")
        T.eq(Wanted(ns), "Duskblade-Firemaw", "two vouchers")
        T.noErrors()
    end)

    T.case("an entry the website dropped goes once both vouchers' newer lists lack it", function()
        local old = List(H.serverTime - 600)
        local newer = List(H.serverTime - 60, { Outlaw("Gloom") })
        local ns = H.Boot({ client = "era" })
        Deliver(ns, old, "Alpha-Firemaw")
        Deliver(ns, old, "Bravo-Firemaw")
        T.eq(Wanted(ns), "Duskblade-Firemaw", "both vouch")

        Deliver(ns, newer, "Alpha-Firemaw")
        Deliver(ns, newer, "Bravo-Firemaw")
        T.eq(Wanted(ns), "Duskblade-Firemaw,Gloom-Firemaw", "for a moment, while the new lists arrive")
        H.serverTime = H.serverTime + ns.SharedSite.GRACE + 1
        T.eq(Wanted(ns), "Gloom-Firemaw", "withdrawn")
        T.noErrors()
    end)

    T.case("our own download stays the source; shared entries fill in for an older one", function()
        local shared = List(H.serverTime - 600, { Outlaw("Gloom") })
        local fresher = List(H.serverTime - 10, { Outlaw("Gloom") })
        local ns = H.Boot({ client = "era", siteData = Data(H.serverTime - 60, { wanted = { Outlaw("Duskblade") } }) })
        Deliver(ns, shared, "Alpha-Firemaw")
        Deliver(ns, shared, "Bravo-Firemaw")
        T.eq(Wanted(ns), "Duskblade-Firemaw", "our newer download wins: Gloom is not on it")

        Deliver(ns, fresher, "Alpha-Firemaw")
        Deliver(ns, fresher, "Bravo-Firemaw")
        T.eq(Wanted(ns), "Duskblade-Firemaw,Gloom-Firemaw", "a newer shared list fills in")
        T.noErrors()
    end)

    T.case("a shared Deadbeat counts like the website's own", function()
        local records = List(H.serverTime - 600, {}, {
            deadbeats = { { name = "Miser", realm = "Firemaw", unpaid = 3, blocked_until = H.serverTime + 3600 } },
        })
        local ns = H.Boot({ client = "era" })
        Deliver(ns, records, "Alpha-Firemaw")
        T.eq(ns.SiteData:Deadbeat("Miser-Firemaw"), nil, "one voucher")
        Deliver(ns, records, "Bravo-Firemaw")
        T.eq(ns.SiteData:Deadbeat("Miser-Firemaw").unpaid, 3, "two vouchers")
        T.ok(next(ns.SiteData:Deadbeats()) ~= nil, "in the list")
        T.noErrors()
    end)

    T.case("the catch-up answer carries our own lists, whatever the since", function()
        local ns = H.Boot({ client = "era", siteData = Data(H.serverTime - 600, { wanted = { Outlaw("Duskblade") } }) })
        local found = 0
        for _, record in ipairs(ns.CatchUp.Records(H.serverTime)) do
            if record:sub(1, 1) == "C" then found = found + 1 end
        end
        T.eq(found, 2, "the marker and the WANTED entry")
        T.noErrors()
    end)

    T.case("after login the list is shared once, unless two others already did", function()
        local random = math.random
        math.random = function() return 0 end
        local ns = H.Boot({ client = "era", siteData = Data(H.serverTime - 600, { wanted = { Outlaw("Duskblade") } }) })
        H.inGuild = true
        H.Advance(ns.SharedSite.DELAY_MIN + 1)
        H.Advance(ns.Transport.FLUSH_INTERVAL + 1)
        Settle()
        local shared = 0
        for _, m in ipairs(H.sent) do
            if m.message:find("^1AC:") then shared = shared + 1 end
        end
        T.ok(shared >= 1, "shared")
        T.eq(ns.SharedSite:Broadcast(ns.SiteData:GeneratedAt()), 0, "not again within 10 minutes")

        local quiet = H.Boot({ client = "era", siteData = Data(H.serverTime - 600, { wanted = { Outlaw("Duskblade") } }) })
        local records = quiet.SharedSite.Records(100)
        Deliver(quiet, records, "Alpha-Firemaw")
        Deliver(quiet, records, "Bravo-Firemaw")
        T.eq(quiet.SharedSite:Broadcast(quiet.SiteData:GeneratedAt()), 0, "two others shared the same list")
        math.random = random
        T.noErrors()
    end)

    T.case("2000 entries from 20 HeadHunters: kept within limits, spread over frames", function()
        local ns = H.Boot({ client = "era" })
        local gen = ns.Protocol.ToB36(H.serverTime - 600)
        local records = { "L;" .. gen }
        for i = 1, 2000 do
            records[#records + 1] = table.concat({ "W", gen, "Outlaw" .. i .. "-Firemaw", "ganker", ns.Protocol.ToB36(50),
                ns.Protocol.ToB36(H.serverTime + 3600), "", "", "", "", "", "", "", "", "", "" }, ";")
        end
        local messages = ns.Protocol.Pack("A", "C", records)
        H.profileStep = 0.5
        for s = 1, 20 do
            for _, m in ipairs(messages) do H.Fire("CHAT_MSG_ADDON", "HeadHunter", m, "CHANNEL", "Sender" .. s .. "-Firemaw") end
        end
        local frames = 0
        while #H.timers > 0 and frames < 5000 do
            H.Advance(0)
            frames = frames + 1
        end
        H.profileStep = 0
        T.ok(frames > 10, "spread over " .. frames .. " frames")
        local kept = 0
        for _ in pairs(ns.SharedSite:Wanted()) do kept = kept + 1 end
        T.ok(kept <= ns.SharedSite.PER_LIST, "at most " .. ns.SharedSite.PER_LIST .. " kept: " .. kept)
        T.noErrors()
    end)

    -- HH-158: a players' bounty from Tallon on Gravelgrin, a target the receiver never saw;
    -- posted an hour before the harness clock every boot starts at
    local BOUNTY_T = 1780000000 - 3600
    local POSTER_ID = "Tallon-Firemaw:" .. BOUNTY_T
    local function Bounty()
        return { t = BOUNTY_T, owner = { name = "Tallon", realm = "Firemaw", faction = "alliance" },
            target = { name = "Gravelgrin", realm = "Firemaw", faction = "horde", class = "rogue", race = "orc", sex = 2 },
            reason = 2, gold = 20000, ["until"] = BOUNTY_T + 3 * 86400 }
    end

    local function BountyList(generatedAt)
        return List(generatedAt or H.serverTime - 600, {}, { bounties = { Bounty() } })
    end

    local function Board(ns)
        ns.Wanted:ComputeNow()
        local names = {}
        for _, summary in ipairs(ns.Bounties:Board()) do names[#names + 1] = summary.target end
        return table.concat(names, ",")
    end

    T.case("players' bounties: shared with the target's looks, read back as the website's", function()
        local records = BountyList()
        local ns = H.Boot({ client = "era" })
        local found
        for _, record in ipairs(records) do
            local kind, _, key, entry = ns.SharedSite.Decode(record)
            if kind == "P" then found = { key = key, entry = entry } end
        end
        T.ok(found ~= nil, "a P record")
        T.eq(found.key, POSTER_ID, "keyed by the poster id")
        T.eq(found.entry.poster.gold, 20000, "gold in copper")
        T.eq(found.entry.poster.reason, 2, "reason")
        T.eq(found.entry.poster["until"], BOUNTY_T + 3 * 86400, "until")
        T.eq(found.entry.target.race, ns.SiteData.Race("orc"), "the target's race")
        T.eq(found.entry.target.sex, 2, "and sex")
        T.noErrors()
    end)

    T.case("players' bounties: one HeadHunter's word is not enough; a second makes it run", function()
        local records = BountyList()
        local ns = H.Boot({ client = "era" })
        Deliver(ns, records, "Alpha-Firemaw")
        T.eq(Board(ns), "", "one voucher")
        Deliver(ns, records, "Bravo-Firemaw")
        T.eq(Board(ns), "Gravelgrin-Firemaw", "two vouchers")
        local rows = ns.MainWindow.Rows("wanted", "rank", nil, "Horde")
        T.eq(rows[1].id, "Gravelgrin-Firemaw", "on top of the WANTED tab, though we never saw them")
        T.ok(rows[1].rank:find("2g", 1, true) ~= nil, "with the reward")
        T.noErrors()
    end)

    T.case("players' bounties: a voucher and a different peer's relay are two sources", function()
        local records = BountyList()
        local relayed = function(ns)
            return ns.Protocol.EncodePoster({ owner = "Tallon-Firemaw", target = "Gravelgrin-Firemaw", reason = 2,
                gold = 20000, ["until"] = BOUNTY_T + 3 * 86400, t = BOUNTY_T })
        end
        local same = H.Boot({ client = "era" })
        same.Bounties:AddRelayedPoster(relayed(same), "Alpha-Firemaw")
        Deliver(same, records, "Alpha-Firemaw")
        T.eq(Board(same), "", "the same character relaying and vouching is one source")

        local ns = H.Boot({ client = "era" })
        ns.Bounties:AddRelayedPoster(relayed(ns), "Helper-Firemaw")
        T.eq(Board(ns), "", "one relay")
        Deliver(ns, records, "Alpha-Firemaw")
        T.eq(Board(ns), "Gravelgrin-Firemaw", "a relay and a voucher")
        T.noErrors()
    end)

    T.case("players' bounties: the owner sharing their download counts alone", function()
        local records = BountyList()
        local ns = H.Boot({ client = "era" })
        Deliver(ns, records, "Tallon-Firemaw")
        T.eq(Board(ns), "Gravelgrin-Firemaw", "the owner's word")
        T.noErrors()
    end)

    T.case("players' bounties: withdrawn once the vouchers' newer lists lack it", function()
        local old, newer = BountyList(H.serverTime - 600), List(H.serverTime - 60, {}, { bounties = {} })
        local ns = H.Boot({ client = "era" })
        Deliver(ns, old, "Alpha-Firemaw")
        Deliver(ns, old, "Bravo-Firemaw")
        T.eq(Board(ns), "Gravelgrin-Firemaw", "both vouch")
        Deliver(ns, newer, "Alpha-Firemaw")
        Deliver(ns, newer, "Bravo-Firemaw")
        H.serverTime = H.serverTime + ns.SharedSite.GRACE + 1
        T.eq(Board(ns), "", "claimed or ended on the website")
        T.noErrors()
    end)

    T.case("players' bounties: a shared one is claimed by our killing blow and never passed on", function()
        local records = BountyList()
        local ns = H.Boot({ client = "era" })
        Deliver(ns, records, "Alpha-Firemaw")
        Deliver(ns, records, "Bravo-Firemaw")
        T.eq(Board(ns), "Gravelgrin-Firemaw", "running")
        H.FireCLEU(H.serverTime, "PARTY_KILL", false, "Player-1-00000001", "Vati",
            H.FLAGS_FRIENDLY_PLAYER, 0, "Player-2-0000BEEF", "Gravelgrin", H.FLAGS_HOSTILE_PLAYER, 0)
        Settle()
        local pay = ns.Bounties:Payment(POSTER_ID)
        T.ok(pay ~= nil and pay.status == "claimed", "claimed")
        T.eq(ns.Bounties:Get(POSTER_ID).origin, "website", "kept as the website's")
        T.eq(ns.Bounties:Get(POSTER_ID).vouchers, nil, "without the vouchers")
        for _, record in ipairs(ns.Bounties:Records(0)) do
            T.ok(record:sub(1, 1) ~= "W", "the poster is not passed on")
        end
        T.noErrors()
    end)

    local function Relayed(ns, owner, target)
        return ns.Protocol.EncodePoster({ owner = owner or "Tallon-Firemaw", target = target or "Gravelgrin-Firemaw",
            reason = 2, gold = 20000, ["until"] = BOUNTY_T + 3 * 86400, t = BOUNTY_T })
    end

    local function CountEvents(ns, event)
        local fired = { n = 0 }
        ns.Events:Register(event, function() fired.n = fired.n + 1 end, "Test")
        return fired
    end

    T.case("players' bounties: claimed over a copy only one peer relayed, it becomes the website's", function()
        local records = BountyList()
        local ns = H.Boot({ client = "era" })
        ns.Bounties:AddRelayedPoster(Relayed(ns), "Helper-Firemaw")
        Deliver(ns, records, "Alpha-Firemaw")
        T.eq(Board(ns), "Gravelgrin-Firemaw", "a relay and a voucher")
        H.FireCLEU(H.serverTime, "PARTY_KILL", false, "Player-1-00000001", "Vati",
            H.FLAGS_FRIENDLY_PLAYER, 0, "Player-2-0000BEEF", "Gravelgrin", H.FLAGS_HOSTILE_PLAYER, 0)
        Settle()
        T.eq(ns.Bounties:Payment(POSTER_ID).status, "claimed", "claimed")
        T.eq(ns.Bounties:Get(POSTER_ID).origin, "website", "our relayed copy is now the website's")
        T.ok(ns.Relay.Counts(ns.Bounties:Get(POSTER_ID)), "and counts")
        for _, record in ipairs(ns.Bounties:Records(0)) do
            T.ok(record:sub(1, 1) ~= "W", "never passed on")
        end
        T.noErrors()
    end)

    T.case("players' bounties: our own newer download wins over older shared lists", function()
        local shared = BountyList(H.serverTime - 600)
        local ns = H.Boot({ client = "era", siteData = Data(H.serverTime - 60, { bounties = {} }) })
        Deliver(ns, shared, "Alpha-Firemaw")
        Deliver(ns, shared, "Bravo-Firemaw")
        T.eq(Board(ns), "", "claimed or ended on the website since: not brought back")
        T.noErrors()
    end)

    T.case("players' bounties: the lists are told only when a bounty starts or stops counting", function()
        local records = BountyList()
        local newer = List(H.serverTime - 60, {}, { bounties = {} })
        local ns = H.Boot({ client = "era" })
        local updated = CountEvents(ns, "HH_BOUNTY_UPDATED")
        Deliver(ns, records, "Alpha-Firemaw")
        T.eq(updated.n, 0, "one voucher: nothing counts yet")
        Deliver(ns, records, "Bravo-Firemaw")
        T.eq(updated.n, 1, "the second voucher: it counts")
        Deliver(ns, records, "Charlie-Firemaw")
        Deliver(ns, records, "Alpha-Firemaw")
        T.eq(updated.n, 1, "more vouches change nothing")

        Deliver(ns, newer, "Alpha-Firemaw")
        Deliver(ns, newer, "Bravo-Firemaw")
        T.eq(updated.n, 1, "while the new lists arrive")
        H.serverTime = H.serverTime + ns.SharedSite.GRACE + 1
        ns.SharedSite:Prune()
        T.eq(updated.n, 2, "only Charlie still vouches: it stops counting")
        T.eq(Board(ns), "", "off the board")
        ns.SharedSite:Prune()
        T.eq(updated.n, 2, "told once")
        T.noErrors()
    end)

    T.case("players' bounties on WoW Forever: names without realms, one relay and one voucher", function()
        local t = BOUNTY_T
        local function Person(name, extra)
            local person = { name = name, faction = "horde" }
            for k, v in pairs(extra or {}) do person[k] = v end
            return person
        end
        local sender = H.Boot({ client = "forever", siteData = { format_version = 1, characters = {}, worlds = {
            ["forever|us|pvp"] = { generated_at = H.serverTime - 600, duels = { alliance = {}, horde = {} },
                bounties = { { t = t, owner = Person("Sven Shmoves"),
                    target = Person("Gobeuse Devier", { faction = "alliance", class = "druid", race = "night_elf", sex = 3 }),
                    reason = 2, gold = 20000, ["until"] = t + 3 * 86400 } } },
        } } })
        local records = sender.SharedSite.Records(sender.SharedSite.BROADCAST_MAX)
        local ns = H.Boot({ client = "forever" })
        ns.Bounties:AddRelayedPoster(Relayed(ns, "Sven Shmoves", "Gobeuse Devier"), "Mephalion Aethelnyx")
        Deliver(ns, records, "Mephalion Aethelnyx")
        T.eq(Board(ns), "", "the same character relaying and vouching is one source")
        Deliver(ns, records, "Other Hunter")
        T.eq(Board(ns), "Gobeuse Devier", "a second character")
        T.eq(ns.MainWindow.Rows("wanted", "rank", nil, "Alliance")[1].id, "Gobeuse Devier", "an Alliance row")
        T.noErrors()
    end)
end
