-- HH-048: Justice served. A WANTED outlaw killed by a HeadHunter or their group is
-- no longer WANTED, for everyone.

return function(T, H)
    local serial = 0

    -- `killer` kills n distinct victims in the last few minutes (peer reports)
    local function Spree(ns, killer, n, mapID, forever)
        for i = 1, n do
            serial = serial + 1
            local victim = forever and ("Victim " .. string.char(64 + (serial % 26) + 1) .. "x" .. serial)
                or ("Victim" .. serial .. "-Firemaw")
            local t = H.serverTime - (n - i + 1) * 30
            ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = 30 },
                killer = { key = killer, name = killer, level = 60, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = mapID or 1436, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
        end
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    -- PARTY_KILL of `victimName` by a source with `sourceFlags`
    local function PartyKill(victimName, sourceFlags, sourceName)
        H.FireCLEU(H.serverTime, "PARTY_KILL", false, "Player-1-00000001", sourceName or "Vati",
            sourceFlags or H.FLAGS_FRIENDLY_PLAYER, 0, "Player-2-0000BEEF", victimName, H.FLAGS_HOSTILE_PLAYER, 0)
    end

    local function Popup(which)
        for _, p in ipairs(H.popups) do
            if p.which == which then return p end
        end
        return nil
    end

    local function Centers(text)
        for _, line in ipairs(H.centerTexts) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end

    T.case("protocol round trip", function()
        local P = H.Boot({ client = "era" }).Protocol
        local outlaw, t, mapID, killer = P.DecodeJustice(P.EncodeJustice("Gank-Stonespine", 1790000000, 1436, "Vati-Firemaw"))
        T.eq(outlaw, "Gank-Stonespine", "outlaw")
        T.eq(t, 1790000000, "time")
        T.eq(mapID, 1436, "map")
        T.eq(killer, "Vati-Firemaw", "killer")
        T.eq(select(4, P.DecodeJustice(P.EncodeJustice("Gank-Stonespine", 1790000000))), nil, "no killer")
        T.eq(P.DecodeJustice("x;y"), nil, "malformed")
    end)

    T.case("era: our killing blow on a WANTED outlaw ends WANTED and says so", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Settle()
        T.eq(#ns.Wanted:List(), 1, "WANTED")

        PartyKill("Gank-Stonespine")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "no longer WANTED")
        local entry = ns.Wanted:ByKey("Gank-Stonespine")
        T.eq(entry.timesCaught, 1, "caught once")
        T.ok(Centers("Justice served!"), "center text")
        T.ok(H.Printed("Justice served!.*Gank%-Stonespine.*%(4 kills%) was brought down by you in"), "chat line")
        for _, pin in ipairs(ns.MapMarkers:PinsFor(1436)) do
            T.ok(pin.kind ~= "wanted", "skull gone from the map")
        end
        T.noErrors()
    end)

    T.case("an outlaw at large can still be caught: off the list, bounty of the last rank", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Settle()
        H.serverTime = H.serverTime + 8 * 86400
        H.Advance(61)
        Settle()
        local entry = ns.Wanted:ByKey("Gank-Stonespine")
        T.eq(entry.wanted, false, "WANTED ran out")
        T.eq(entry.atLarge, true, "at large")
        local total = ns.Marks:Total()

        PartyKill("Gank-Stonespine")
        Settle()
        T.eq(ns.Wanted:ByKey("Gank-Stonespine").atLarge, nil, "no longer at large")
        T.eq(#ns.Wanted:AtLarge(), 0, "off the list")
        T.eq(ns.Marks:Total(), total + 3, "Ganker bounty")
        T.ok(H.Printed("Justice served!.*Ganker.*Gank%-Stonespine.*%(4 kills%)"), "chat line")
        T.noErrors()
    end)

    T.case("era: [Announce] sends the catch realm-wide; guild gets it automatically", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        Spree(ns, "Gank-Stonespine", 4)
        Settle()
        PartyKill("Gank-Stonespine")
        Settle()
        H.Advance(3)
        local guild
        for _, m in ipairs(H.sent) do
            if m.chatType == "GUILD" and m.message:find("^1AK:") then guild = m end
        end
        T.ok(guild ~= nil, "sent to the guild")

        local popup = Popup("HEADHUNTER_JUSTICE")
        T.ok(popup ~= nil and popup.text:find("Announce it to all HeadHunters", 1, true) ~= nil, "announce offered")
        _G.StaticPopupDialogs.HEADHUNTER_JUSTICE.OnAccept()
        T.eq(#H.chatSent, 1, "one channel text line")
        T.ok(H.chatSent[1].text:find("^HH1:1AK:") ~= nil, "catch record")
        T.ok(H.Printed("Announced to all HeadHunters"), "confirmed")
        T.noErrors()
    end)

    T.case("era: a group member's killing blow counts; a stranger's does not", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Spree(ns, "Other-Stonespine", 4)
        Settle()
        PartyKill("Other-Stonespine", 0x512, "Stranger") -- friendly player, AFFILIATION_PARTY
        PartyKill("Gank-Stonespine", 0x518, "Stranger")  -- friendly player, AFFILIATION_OUTSIDER
        Settle()
        T.eq(ns.Wanted:ByKey("Other-Stonespine").wanted, false, "group kill: caught")
        T.eq(ns.Wanted:ByKey("Gank-Stonespine").wanted, true, "a stranger's kill: still WANTED")
        T.ok(H.Printed("was brought down by Stranger"), "names who landed the blow")
    end)

    T.case("era: someone else's kill is our catch when we hit the outlaw in the last minute", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Spree(ns, "Late-Stonespine", 4)
        Spree(ns, "Untouched-Stonespine", 4)
        Settle()
        local function Hit(guid, name)
            H.FireCLEU(H.serverTime, "SPELL_DAMAGE", false, "Player-1-00000001", "Vati", H.FLAGS_FRIENDLY_PLAYER, 0,
                guid, name, H.FLAGS_HOSTILE_PLAYER, 0, 133, "Fireball", 4, 500)
        end
        local function Died(guid, name)
            H.FireCLEU(H.serverTime, "UNIT_DIED", false, "", nil, 0, 0, guid, name, H.FLAGS_HOSTILE_PLAYER, 0)
        end
        Hit("Player-2-0000BEEF", "Gank-Stonespine")
        Hit("Player-2-0000CAFE", "Late-Stonespine")
        H.Advance(30)
        -- A player without HeadHunter, not in our group, lands the blow
        Died("Player-2-0000BEEF", "Gank-Stonespine")
        Settle()
        T.eq(ns.Wanted:ByKey("Gank-Stonespine").wanted, false, "we helped: caught")
        H.Advance(31)
        Died("Player-2-0000CAFE", "Late-Stonespine")
        Died("Player-2-0000D00D", "Untouched-Stonespine")
        Settle()
        T.eq(ns.Wanted:ByKey("Late-Stonespine").wanted, true, "our hit was more than a minute before")
        T.eq(ns.Wanted:ByKey("Untouched-Stonespine").wanted, true, "we never hit them")
        T.noErrors()
    end)

    T.case("era: killing an enemy who is not WANTED records nothing", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 2)
        Settle()
        PartyKill("Gank-Stonespine")
        Settle()
        local n = 0
        for _ in ns.Justice:All() do n = n + 1 end
        T.eq(n, 0, "no catch")
    end)

    T.case("one catch per outlaw per minute (the whole group sees the kill)", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Settle()
        T.ok(ns.Justice:Record(ns.Wanted:ByKey("Gank-Stonespine"), "test") ~= nil, "first")
        H.serverTime = H.serverTime + 30
        T.eq(ns.Justice:Record(ns.Wanted:ByKey("Gank-Stonespine"), "test"), nil, "30 s later: same catch")
    end)

    T.case("a catch from another HeadHunter ends WANTED here; posse members see it on screen", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Settle()
        ns.Posse:Join(ns.Wanted:ByKey("Gank-Stonespine"), { mapID = 1436, x = 0.5, y = 0.5 })
        local record = ns.Protocol.EncodeJustice("Gank-Stonespine", H.serverTime - 5, 1436, "Hunter-Firemaw")
        H.Deliver(ns.Protocol.Pack("A", "K", { record }), "Hunter-Firemaw")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "no longer WANTED")
        T.ok(H.Printed("was brought down by Hunter in Westfall"), "chat line")
        T.ok(Centers("brought down by Hunter"), "posse member: center text")
        T.eq(Popup("HEADHUNTER_JUSTICE"), nil, "no announce popup for someone else's catch")
        T.noErrors()
    end)

    T.case("peer catches: implausible times, malformed records and floods are dropped", function()
        local ns = H.Boot({ client = "era" })
        local P = ns.Protocol
        local function Send(outlaw, ago, sender)
            H.Deliver(P.Pack("A", "K", { P.EncodeJustice(outlaw, H.serverTime - ago, 1436) }), sender or "Hunter-Firemaw")
        end
        local function Count()
            local n = 0
            for _ in ns.Justice:All() do n = n + 1 end
            return n
        end
        Send("Gank-Stonespine", -3600)
        Send("Gank-Stonespine", 31 * 86400)
        H.Deliver(P.Pack("A", "K", { "garbage" }), "Hunter-Firemaw")
        T.eq(Count(), 0, "rejected")
        for i = 1, 7 do Send("Gank" .. i .. "-Stonespine", 10) end
        T.eq(Count(), 5, "rate limited per sender")
    end)

    T.case("forever: our WANTED target dies while we fight it", function()
        local ns = H.Boot({ client = "forever" })
        Spree(ns, "Grim Reaper", 4, 1436, true)
        Settle()
        T.eq(#ns.Wanted:List(), 1, "WANTED")
        H.units.target = { name = "Grim", realm = "Reaper", fullName = "Grim Reaper", level = 60, class = "ROGUE",
            race = "Orc", faction = "Horde", isPlayer = true, guid = "Player-4613-00ABCDEF", dead = true }

        H.Fire("UNIT_HEALTH", "target") -- not in combat: someone else's fight
        Settle()
        T.eq(#ns.Wanted:List(), 1, "not our fight")

        H.inCombat = true
        H.Fire("UNIT_HEALTH", "target")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "caught")
        T.eq(#H.forbidden, 0, "never touched the combat log")
        T.noErrors()
    end)

    T.case("forever: a group kill of a WANTED outlaw we did not target counts by the honorable kill line", function()
        local ns = H.Boot({ client = "forever" })
        Spree(ns, "Grim Reaper", 4, 1436, true)
        Settle()
        T.eq(#ns.Wanted:List(), 1, "WANTED")
        H.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Some Body dies, honorable kill Rank: Scout (Estimated Honor Points: 10)")
        Settle()
        T.eq(#ns.Wanted:List(), 1, "another player's death: no catch")
        -- the given name only, with the realm as Forever's death recap gives it
        H.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Grim-ClassicBetaPvP2 dies, honorable kill Rank: Scout (Estimated Honor Points: 10)")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "caught with the group")
        T.eq(#H.forbidden, 0, "never touched the combat log")
        T.noErrors()
    end)

    T.case("era: the honorable kill line of a WANTED outlaw is a catch too", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Settle()
        H.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Gank-Stonespine dies, honorable kill (Estimated Honor Points: 12)")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "caught")
        T.noErrors()
    end)

    T.case("/hh catch (debug) records a catch of a WANTED outlaw", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Settle()
        H.Slash("catch Gank-Stonespine")
        T.ok(H.Printed("debug tool"), "needs debug mode")
        H.Slash("debug on")
        H.Slash("catch Gank-Stonespine")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "caught")
        H.Slash("catch Nobody-Stonespine")
        T.ok(H.Printed("is not WANTED right now"), "not WANTED")
    end)

    T.case("/hh outlaw shows how often an outlaw was caught", function()
        local ns = H.Boot({ client = "era" })
        Spree(ns, "Gank-Stonespine", 4)
        Settle()
        PartyKill("Gank-Stonespine")
        Settle()
        H.Slash("outlaw Gank-Stonespine")
        T.ok(H.Printed("caught: 1"), "caught count")
    end)
end
