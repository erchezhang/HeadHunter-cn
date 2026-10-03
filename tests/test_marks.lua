-- HH-050: HeadHunter Marks and hunter ranks.

return function(T, H)
    local serial = 0

    local function Spree(ns, killer, n, killerLevel)
        for i = 1, n do
            serial = serial + 1
            local victim = "Victim" .. serial .. "-Firemaw"
            local t = H.serverTime - (n - i + 1) * 30
            ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = 20 },
                killer = { key = killer, name = killer, level = killerLevel or 60, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = 1436, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
        end
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    local function Entry(ns, key) return ns.Wanted:ByKey(key) end

    T.case("ranks by total", function()
        local M = H.Boot({ client = "era" }).Marks
        local CASES = { { 0, "Tracker" }, { 9, "Tracker" }, { 10, "Bounty Hunter" }, { 25, "Manhunter" },
            { 49, "Manhunter" }, { 50, "Headhunter" }, { 100, "Reaper" }, { 500, "Reaper" } }
        for _, c in ipairs(CASES) do
            T.eq(M.RankNameByIndex(M.RankIndexFor(c[1])), c[2], "rank at " .. c[1])
        end
    end)

    T.case("a catch pays by the outlaw's rank, once per outlaw per minute", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 5)      -- Ganker
        Spree(ns, "Big-Stonespine", 12)      -- Outlaw
        Settle()
        H.Slash("debug on")
        H.Slash("catch Gank-Stonespine")
        T.eq(ns.Marks:Total(), 3, "Ganker: +3")
        T.ok(H.Printed("%+3|r bounty: brought down .*Ganker.* Gank%-Stonespine %(total 3%)"), "chat line")
        ns.Marks:OnCatch(Entry(ns, "Gank-Stonespine"))
        T.eq(ns.Marks:Total(), 3, "the same catch seen twice: once")
        H.Slash("catch Big-Stonespine")
        T.eq(ns.Marks:Total(), 8, "Outlaw: +5")
        T.eq(ns.db.marks.total, 8, "saved")
        T.eq(ns.db.marks.events[#ns.db.marks.events].hunter, ns.Utils.UnitKey("player"), "whose event it is")
    end)

    T.case("rank up is announced", function()
        local ns = H.Boot({ client = "era" })
        ns.db.marks.total = 8
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        ns.Marks:OnCatch(Entry(ns, "Gank-Stonespine"))
        T.eq(ns.Marks:Total(), 11, "11")
        local shown = false
        for _, text in ipairs(H.centerTexts) do shown = shown or text:find("Bounty Hunter", 1, true) ~= nil end
        T.ok(shown, "You are now a Bounty Hunter!")
        local next, needed = ns.Marks:Next()
        T.eq(next, "Manhunter", "next rank")
        T.eq(needed, 14, "14 more")
    end)

    T.case("joining a posse: +1 once per outlaw per WANTED run", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("debug on")
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        local entry = Entry(ns, "Gank-Stonespine")
        ns.Posse:Join(entry, { mapID = 1436, x = 0.5, y = 0.5 })
        T.eq(ns.Marks:Total(), 1, "+1")
        ns.Posse:Join(entry, { mapID = 1436, x = 0.5, y = 0.5 })
        T.eq(ns.Marks:Total(), 1, "joining again: nothing")
        H.clock = H.clock + 1801
        H.serverTime = H.serverTime + 1801
        ns.Posse:Join(Entry(ns, "Gank-Stonespine"), { mapID = 1436, x = 0.5, y = 0.5 })
        T.eq(ns.Marks:Total(), 1, "a new posse on the same WANTED run: nothing")

        H.Slash("catch Gank-Stonespine")
        local afterCatch = ns.Marks:Total()
        H.clock = H.clock + 3600
        H.serverTime = H.serverTime + 3600
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        ns.Posse:Join(Entry(ns, "Gank-Stonespine"), { mapID = 1436, x = 0.5, y = 0.5 })
        T.eq(ns.Marks:Total(), afterCatch + 1, "WANTED again after the catch: +1")
    end)

    T.case("forever: a login forgets the posse, but a join point this WANTED run is not paid again", function()
        local ns = H.Boot({ client = "forever" })
        Spree(ns, "Gank Stone", 5)
        Settle()
        local entry = Entry(ns, "Gank Stone")
        T.eq(ns.Posse:IsMember(entry.id), false, "not in the posse after the login")
        ns.db.marks.total = 1
        ns.db.marks.events[1] = { t = H.serverTime, delta = 1, reason = "join", outlaw = "Gank Stone", total = 1,
            origin = "site" }
        ns.Posse:Join(entry, { mapID = 1436, x = 0.5, y = 0.5 })
        T.eq(ns.Posse:IsMember(entry.id), true, "joined again")
        T.eq(ns.Marks:Total(), 1, "no second point")
    end)

    T.case("no marks for hunting 10+ levels down", function()
        local ns = H.Boot({ client = "era" }) -- the player is level 30
        Spree(ns, "Lowbie-Stonespine", 5, 18)
        Settle()
        ns.Marks:OnCatch(Entry(ns, "Lowbie-Stonespine"))
        ns.Posse:Join(Entry(ns, "Lowbie-Stonespine"), { mapID = 1436, x = 0.5, y = 0.5 })
        T.eq(ns.Marks:Total(), 0, "nothing")
        T.ok(H.Printed("No bounty: Lowbie%-Stonespine is 10%+ levels below you"), "said why")
    end)

    T.case("decline: -1 while eligible, at most every 10 min, never in combat", function()
        local ns = H.Boot({ client = "era" })
        ns.db.marks.total = 5
        Spree(ns, "Gank-Stonespine", 5)
        Spree(ns, "Other-Stonespine", 5)
        Settle()
        H.inCombat = true
        ns.Posse:Decline(Entry(ns, "Gank-Stonespine"), {})
        T.eq(ns.Marks:Total(), 5, "in combat: no penalty")
        H.inCombat = false
        ns.Posse:Decline(Entry(ns, "Gank-Stonespine"), {})
        T.eq(ns.Marks:Total(), 4, "-1")
        ns.Posse:Decline(Entry(ns, "Other-Stonespine"), {})
        T.eq(ns.Marks:Total(), 4, "within 10 min: once")
        H.clock = H.clock + 601
        H.instance = { true, "party" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        ns.Posse:Decline(Entry(ns, "Other-Stonespine"), {})
        T.eq(ns.Marks:Total(), 4, "in an instance: no penalty")
    end)

    T.case("marks never go below zero", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        ns.Posse:Decline(Entry(ns, "Gank-Stonespine"), {})
        T.eq(ns.Marks:Total(), 0, "0")
    end)

    T.case("our hunter rank travels with posse joins; /hh posse shows ranks", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        ns.db.marks.total = 30
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        ns.Posse:Join(Entry(ns, "Gank-Stonespine"), { mapID = 1436, x = 0.5, y = 0.5 })
        H.Advance(3)
        local record
        for _, m in ipairs(H.sent) do
            if m.message:find("^1AJ:") then record = select(3, ns.Protocol.Unpack(m.message))[1] end
        end
        T.eq(select(5, ns.Protocol.DecodePosse(record)), 3, "Manhunter = rank 3")
        local peer = ns.Protocol.EncodePosse("Gank-Stonespine", 1436, H.serverTime - 5, nil, 5)
        H.Deliver(ns.Protocol.Pack("A", "J", { peer }), "Alpha-Firemaw")
        H.Slash("posse")
        T.ok(H.Printed("Alpha %(Reaper%)"), "peer's rank")
        T.ok(H.Printed("you %(Manhunter%)"), "ours")
    end)

    T.case("My bounty tab, /hh bounty and the /hh marks alias", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        ns.Posse:Join(Entry(ns, "Gank-Stonespine"), { mapID = 1436, x = 0.5, y = 0.5 })
        ns.Marks:OnCatch(Entry(ns, "Gank-Stonespine"))
        local rows = ns.MainWindow.Rows("marks")
        T.eq(#rows, 2, "two events")
        T.ok(rows[1].reason:find("brought down", 1, true) ~= nil, "newest first")
        T.eq(rows[1].total, "4", "running total")
        T.ok(rows[2].change:find("+1", 1, true) ~= nil, "join +1")
        H.Slash("bounty")
        T.ok(H.Printed("HeadHunter rank: .*Tracker.* · bounty 4"), "status")
        T.ok(H.Printed("6 more for Bounty Hunter"), "next rank")
        H.printed = {}
        H.Slash("marks")
        T.ok(H.Printed("HeadHunter rank: .*Tracker.* · bounty 4"), "/hh marks still works")
        H.printed = {}
        H.Slash("help")
        T.ok(H.Printed("/hh bounty"), "help lists /hh bounty")
        T.ok(not H.Printed("/hh marks"), "the alias stays out of the help")
        T.eq(ns.L.TAB_MARKS, "My bounty", "tab label")
        T.noErrors()
    end)

    T.case("each character has its own bounty; the first one keeps the old total", function()
        local ns = H.Boot({ client = "era" })
        ns.db.marks = { total = 12, events = { { t = H.serverTime - 60, delta = 12, reason = "catch", outlaw = "X",
            rank = "mostwanted", total = 12 } } }
        T.eq(ns.Marks:Total(), 12, "the old total goes to the character we play")
        T.eq(#ns.Marks:Events(), 1, "with its events")
        H.units.player.name = "Tovik"
        T.eq(ns.Marks:Total(), 0, "another character starts at 0")
        T.eq(#ns.Marks:Events(), 0, "and sees none of the first one's events")
        ns.Marks:Add(3, "bully", "Brute")
        T.eq(ns.Marks:Total(), 3, "own bounty")
        T.eq(ns.MainWindow.Rows("marks")[1].total, "3", "running total of this character")
        H.units.player.name = "Vati"
        T.eq(ns.Marks:Total(), 12, "the first character's bounty is back")
        T.eq(#ns.Marks:Events(), 1, "and its events only")
        H.units.player.name = "Tovik"
        T.eq(ns.Marks:Total(), 3, "the second one's too")
        T.noErrors()
    end)

    T.case("each character's bounty is kept over a logout", function()
        local ns = H.Boot({ client = "era" })
        ns.Marks:Add(5, "catch", "Brute", "outlaw")
        local saved = ns.Database:Root()
        H.Install({ client = "era", savedDB = saved })
        H.units.player.name = "Tovik"
        local alt = H.Load()
        H.Fire("ADDON_LOADED", "HeadHunter")
        H.Fire("PLAYER_LOGIN")
        T.eq(alt.Marks:Total(), 0, "the new character")
        alt.Marks:Add(1, "join", "Brute", "outlaw")
        T.eq(alt.Marks:Total(), 1, "its own")
        T.eq(#alt.db.marks.events, 2, "one list, each event with its hunter")
        T.noErrors()
    end)

    T.case("the website's totals go to each character", function()
        local ns = H.Boot({ client = "era" })
        T.ok(ns.Marks:SetTotalOf("Tovik-Firemaw", 20), "another character")
        T.eq(ns.Marks:Total(), 0, "not ours")
        T.ok(ns.Marks:SetTotalOf("Vati-Firemaw", 7), "ours")
        T.eq(ns.Marks:Total(), 7, "ours")
        T.ok(not ns.Marks:SetTotalOf("Vati-Firemaw", 5), "never lower")
        H.units.player.name = "Tovik"
        T.eq(ns.Marks:Total(), 20, "the other character's")
        T.noErrors()
    end)
end
