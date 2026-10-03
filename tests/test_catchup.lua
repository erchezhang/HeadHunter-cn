-- HH-023: login catch-up. The player who logs in asks; peers offer; the best one
-- whispers the missed reports and catches.

return function(T, H)
    local serial = 0

    local function Spree(ns, killer, n, ago)
        for i = 1, n do
            serial = serial + 1
            local victim = "Victim" .. serial .. "-Firemaw"
            local t = H.serverTime - (ago or 0) - (n - i + 1) * 30
            ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = 30 },
                killer = { key = killer, name = killer, level = 60, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = 1436, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
        end
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    local function B36(n) return H.ns.Protocol.ToB36(n) end

    local function Sent(pattern, chatType)
        local found = {}
        for _, m in ipairs(H.sent) do
            if m.message:find(pattern) and (not chatType or m.chatType == chatType) then found[#found + 1] = m end
        end
        return found
    end

    local function Query(ns, kind, since, sender)
        H.Deliver(ns.Protocol.Pack("A", "Q", { kind .. B36(since) }), sender or "Newbie-Firemaw")
    end

    -- Let flushes run (hello, offers, whispers)
    local function Run(seconds)
        for _ = 1, seconds do H.Advance(1) end
    end

    -------------------------------------------------
    -- Answering
    -------------------------------------------------

    T.case("a peer with newer records offers them by whisper; one without stays quiet", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 3)
        Query(ns, "h", H.serverTime - 3600)
        Run(8)
        local offers = Sent("^1AO:", "WHISPER")
        T.eq(#offers, 1, "one offer")
        T.eq(offers[1].target, "Newbie-Firemaw", "to the requester")
        T.eq(offers[1].message, "1AO:" .. B36(3), "three records")

        H.sent = {}
        Query(ns, "h", H.serverTime, "Other-Firemaw")
        Run(8)
        T.eq(#Sent("^1AO:"), 0, "nothing newer: no offer")
    end)

    T.case("with many of our faction online only about 5 peers offer", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.CatchUp.OfferChance(3), 1, "few online: everyone offers")
        T.eq(ns.CatchUp.OfferChance(1001), 5 / 1000, "1000 others: 5 of them")
        Spree(ns, "Gank-Stonespine", 3)
        for i = 1, 40 do ns.Presence:Heard("Rider" .. i .. "-Firemaw", "Alliance") end
        local random = math.random
        math.random = function() return 0.5 end
        Query(ns, "h", H.serverTime - 3600)
        Run(8)
        T.eq(#Sent("^1AO:"), 0, "not picked this time")
        math.random = function() return 0.05 end
        Query(ns, "h", H.serverTime - 3600, "Latecomer-Firemaw")
        Run(8)
        math.random = random
        T.eq(#Sent("^1AO:"), 1, "picked")
    end)

    T.case("a pull gets reports and catches by whisper, then an end marker; simulated ones never", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        ns.Justice:Record(ns.Wanted:ByKey("Gank-Stonespine"), "test")
        ns.Reports:Add({ id = "Sim:1", t = H.serverTime - 5, victim = { key = "Vati-Firemaw", level = 30 },
            killer = { key = "Fake-Stonespine", level = 60 }, assists = {}, confidence = "sim" }, "sim")
        H.sent = {}
        Query(ns, "p", H.serverTime - 3600)
        Run(20)
        local data = Sent("^1AS:", "WHISPER")
        T.ok(#data >= 1, "data whispered")
        local all = {}
        for _, m in ipairs(data) do
            T.eq(m.target, "Newbie-Firemaw", "to the requester")
            for _, record in ipairs(select(3, ns.Protocol.Unpack(m.message))) do all[#all + 1] = record end
        end
        local deaths, catches, witnesses, fake = 0, 0, 0, false
        for _, record in ipairs(all) do
            if record:sub(1, 1) == "D" then deaths = deaths + 1 end
            if record:sub(1, 1) == "K" then catches = catches + 1 end
            if record:sub(1, 1) == "X" then witnesses = witnesses + 1 end
            if record:find("Fake", 1, true) then fake = true end
        end
        T.eq(deaths, 5, "five reports")
        T.eq(catches, 1, "one catch")
        T.eq(witnesses, 1, "and our own witness record of it (HH-121)")
        T.eq(fake, false, "simulated report kept to ourselves")
        T.eq(all[#all], "E" .. B36(7), "end marker last")

        H.sent = {}
        Query(ns, "p", H.serverTime - 3600)
        Run(10)
        T.eq(#Sent("^1AS:"), 0, "one answer per requester per 5 minutes")
    end)

    T.case("/hh sim send deaths were shared already, so they are passed on too", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("debug on")
        H.Slash("sim send Ash-Stonespine 2")
        H.Slash("spree Local-Stonespine 2")
        local passed = {}
        for _, record in ipairs(ns.CatchUp.Records(H.serverTime - 3600)) do
            if record:find("Ash", 1, true) then passed.sent = (passed.sent or 0) + 1 end
            if record:find("Local", 1, true) then passed.spree = true end
        end
        T.eq(passed.sent, 2, "sim send: passed on")
        T.eq(passed.spree, nil, "spree: local only")
    end)

    -------------------------------------------------
    -- Asking
    -------------------------------------------------

    T.case("since: last logout minus 10 min, or the whole report lifetime without saved data", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.CatchUp.Since(), H.serverTime - ns.Reports.MAX_AGE, "fresh install")
        ns = H.Boot({ client = "era", savedDB = { meta = { savedAt = H.serverTime - 7200, createdAt = 1, loadCount = 3 } } })
        T.eq(ns.CatchUp.Since(), H.serverTime - 7200 - 600, "from the last logout")
    end)

    T.case("no automatic hello after a /reload or with fresh website data; website data narrows since", function()
        local saved = { meta = { savedAt = H.serverTime - 60, createdAt = 1, loadCount = 3 } }
        local ns = H.Boot({ client = "era", savedDB = saved })
        H.inGuild = true
        Run(25)
        T.eq(#Sent("^1AQ:h"), 0, "reload: no hello")
        T.eq(ns.CatchUp.last.skipped, "reload", "said why")
        H.Slash("catchup")
        Run(4)
        T.eq(#Sent("^1AQ:h", "GUILD"), 1, "/hh catchup still asks")

        local site = { format_version = 1, generated_at = H.serverTime - 120, characters = {},
            worlds = { ["era|eu|Firemaw"] = { generated_at = H.serverTime - 120, wanted = {},
                duels = { alliance = {}, horde = {} } } } }
        ns = H.Boot({ client = "era", siteData = site })
        H.inGuild = true
        Run(25)
        T.eq(#Sent("^1AQ:h"), 0, "fresh website data: no hello")
        T.eq(ns.CatchUp.last.skipped, "website", "said why")

        site.generated_at = H.serverTime - 7200
        site.worlds["era|eu|Firemaw"].generated_at = H.serverTime - 7200
        ns = H.Boot({ client = "era", siteData = site })
        H.inGuild = true
        Run(25)
        T.eq(#Sent("^1AQ:h", "GUILD"), 1, "older website data: hello")
        T.eq(ns.CatchUp.Since(), H.serverTime - 7200 - 600, "only what is newer than the website data")
    end)

    T.case("after login: hello, then pulls go to the two peers with the most records", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        Run(25)
        local hello = Sent("^1AQ:h", "GUILD")
        T.eq(#hello, 1, "hello to the guild")
        T.eq(ns.CatchUp:State(), "asking", "asking")

        H.Deliver(ns.Protocol.Pack("A", "O", { B36(3) }), "Small-Firemaw")
        H.Deliver(ns.Protocol.Pack("A", "O", { B36(7) }), "Big-Firemaw")
        H.Deliver(ns.Protocol.Pack("A", "O", { B36(5) }), "Middle-Firemaw")
        Run(10)
        local pull = Sent("^1AQ:p", "WHISPER")
        T.eq(#pull, 2, "two pulls (a relayed record needs two sources)")
        T.eq(pull[1].target, "Big-Firemaw", "from the peer with the most")
        T.eq(pull[2].target, "Middle-Firemaw", "and the next one")
        T.eq(ns.CatchUp:State(), "pulling", "pulling")
    end)

    T.case("no route (Era, no guild, group or channel): nothing is sent until /hh catchup can", function()
        local ns = H.Boot({ client = "era" })
        H.channels.HeadHunterSync = nil
        Run(25)
        T.eq(#Sent("^1AQ:"), 0, "no hello")
        H.Slash("catchup")
        T.ok(H.Printed("No HeadHunters reachable"), "said so")
        H.inGroup = true
        H.Slash("catchup")
        Run(4)
        T.eq(#Sent("^1AQ:h", "PARTY"), 1, "asked the group")
    end)

    T.case("era: after a real absence a Catch up popup sends the hello realm-wide", function()
        local ns = H.Boot({ client = "era", savedDB = { meta = { savedAt = H.serverTime - 7200, createdAt = 1, loadCount = 3 } } })
        Run(25)
        local popup
        for _, p in ipairs(H.popups) do if p.which == "HEADHUNTER_CATCHUP" then popup = p end end
        T.ok(popup ~= nil, "offered")
        T.ok(popup.text:find("2 h 0 min ago", 1, true) ~= nil, "says how long: " .. popup.text)
        _G.StaticPopupDialogs.HEADHUNTER_CATCHUP.OnAccept()
        T.eq(#H.chatSent, 1, "one channel text line")
        T.ok(H.chatSent[1].text:find("^HH1:1AQ:h") ~= nil, "the hello, realm-wide")
        T.eq(ns.CatchUp:State(), "asking", "asking")
        T.noErrors()
    end)

    T.case("era: no popup after a /reload (just away), none on Forever", function()
        H.Boot({ client = "era", savedDB = { meta = { savedAt = H.serverTime - 60, createdAt = 1, loadCount = 3 } } })
        Run(40)
        for _, p in ipairs(H.popups) do T.ok(p.which ~= "HEADHUNTER_CATCHUP", "no popup after a reload") end
        H.Boot({ client = "forever" })
        Run(40)
        for _, p in ipairs(H.popups) do T.ok(p.which ~= "HEADHUNTER_CATCHUP", "no popup on Forever") end
    end)

    T.case("era: /hh catchup (typed) asks realm-wide without guild or group", function()
        local ns = H.Boot({ client = "era" })
        Run(3)
        H.Slash("catchup")
        T.eq(#H.chatSent, 1, "channel text")
        T.ok(H.chatSent[1].text:find("^HH1:1AQ:h") ~= nil, "the hello")
        T.ok(H.Printed("Asking other HeadHunters"), "said so")
    end)

    T.case("era: a hello received as channel text is answered by whisper", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 3)
        local hello = "HH1:" .. ns.Protocol.Pack("A", "Q", { "h" .. B36(H.serverTime - 3600) })[1]
        H.Fire("CHAT_MSG_CHANNEL", hello, "Newbie-Firemaw", "", "5. HeadHunterSync", "", "", 0, 5, "HeadHunterSync")
        Run(8)
        local offers = Sent("^1AO:", "WHISPER")
        T.eq(#offers, 1, "offer whispered")
        T.eq(offers[1].target, "Newbie-Firemaw", "to the requester")
    end)

    T.case("forever: the hello goes on the hidden channel; nobody offers, nothing happens", function()
        local ns = H.Boot({ client = "forever" })
        Run(25)
        T.eq(#Sent("^1AQ:h", "CHANNEL"), 1, "hello on the channel")
        Run(40)
        T.eq(#Sent("^1AQ:h", "CHANNEL"), 2, "one more hello: on a busy realm only some peers offer")
        Run(40)
        T.eq(#Sent("^1AQ:h", "CHANNEL"), 2, "not a third")
        T.eq(ns.CatchUp:State(), "done", "gave up quietly")
        T.eq(#H.printed, 2, "silent (only the load line and the Forever saved data warning)")
    end)

    T.case("after a long battleground the hello asks from when we went in; a short one asks nothing", function()
        local ns = H.Boot({ client = "forever" })
        Run(130)
        T.eq(ns.CatchUp:State(), "done", "login catch-up over")
        H.sent = {}
        H.instance = { true, "pvp" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        local wentIn = H.serverTime
        H.Advance(60)
        H.serverTime = H.serverTime + 60
        H.instance = { false, "none" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        Run(5)
        T.eq(#Sent("^1AQ:h"), 0, "a minute inside: no hello")

        H.instance = { true, "pvp" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        wentIn = H.serverTime
        H.serverTime = H.serverTime + 1200
        H.instance = { false, "none" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        Run(5)
        local hello = Sent("^1AQ:h", "CHANNEL")
        T.eq(#hello, 1, "20 minutes inside: one hello")
        T.eq(hello[1].message, "1AQ:h" .. B36(wentIn - ns.CatchUp.MARGIN), "since we went in")
        T.noErrors()
    end)

    -------------------------------------------------
    -- End to end
    -------------------------------------------------

    T.case("end to end: a fresh client ends with the same WANTED list as its peer", function()
        -- Peer: Gank is WANTED, Burner was WANTED and caught
        local peer = H.Boot({ client = "era" })
        Spree(peer, "Gank-Stonespine", 5, 600)
        Spree(peer, "Burner-Stonespine", 5, 1200)
        Settle()
        peer.Justice:Record(peer.Wanted:ByKey("Burner-Stonespine"), "test")
        Settle()
        T.eq(#peer.Wanted:List(), 1, "peer: only Gank is WANTED")
        Query(peer, "p", H.serverTime - 30 * 86400, "Newbie-Firemaw")
        Run(30)
        local answer = {}
        for _, m in ipairs(Sent("^1AS:", "WHISPER")) do answer[#answer + 1] = m.message end
        T.ok(#answer > 0, "peer answered")

        -- Fresh client logs in, asks, gets two offers, pulls from both, receives the answers
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        Run(25)
        H.Deliver(ns.Protocol.Pack("A", "O", { B36(11) }), "Helper-Firemaw")
        H.Deliver(ns.Protocol.Pack("A", "O", { B36(11) }), "Second-Firemaw")
        Run(10)
        H.Deliver(answer, "Stranger-Firemaw")
        T.eq(ns.Reports:Count(), 0, "data from a peer we did not pull from is ignored")
        H.Deliver(answer, "Helper-Firemaw")
        Settle()
        T.eq(ns.Reports:Count(), 10, "all ten reports")
        T.eq(ns.CatchUp:State(), "pulling", "waiting for the second peer")
        T.eq(#ns.Wanted:List(), 0, "one peer's word alone makes nobody WANTED (HH-121)")
        H.Deliver(answer, "Second-Firemaw")
        Settle()
        T.eq(ns.Reports:Count(), 10, "the same ten reports")
        T.eq(ns.CatchUp:State(), "done", "complete")
        T.eq(ns.CatchUp.last.catches, 1, "the catch")
        local list = ns.Wanted:List()
        T.eq(#list, 1, "same WANTED list")
        T.eq(list[1].id, "Gank-Stonespine", "Gank")
        T.eq(ns.Wanted:ByKey("Burner-Stonespine").timesCaught, 1, "Burner caught")
        T.eq(#H.centerTexts, 0, "old news: no center text")
        T.noErrors()
    end)
end
