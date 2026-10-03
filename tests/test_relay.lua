-- HH-121 step 0: a record relayed at login catch-up counts only once a second source
-- has it. Made-up players only.

return function(T, H)
    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    -- Five deaths to `killer` in five minutes, as catch-up records
    local function SpreeRecords(ns, killer)
        local records = {}
        for i = 1, 5 do
            local t = H.serverTime - 600 + i * 60
            local victim = "Victim" .. i .. "-Firemaw"
            records[i] = ns.Protocol.EncodeDeath({ id = victim .. ":" .. t, t = t,
                victim = { key = victim, level = 30 },
                killer = { key = killer, name = killer, level = 32, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = 1436, x = 0.5, y = 0.5, confidence = "exact" })
        end
        return records
    end

    local function Relayed(ns, records, relayer)
        for _, record in ipairs(records) do ns.Reports:AddRelayed(record, relayer) end
        Settle()
    end

    T.case("the rule: two different relayers, or the author relaying it", function()
        local ns = H.Boot({ client = "era" })
        local R = ns.Relay
        local record = { origin = "relay" }
        T.eq(R.Counts(record), false, "nobody yet")
        T.eq(R.Vouch(record, "Helper-Firemaw"), false, "one relayer")
        T.eq(R.Vouch(record, "Helper-Firemaw"), false, "the same relayer again")
        T.eq(R.Counts(record), false, "still not")
        T.eq(R.Vouch(record, "Second-Firemaw"), true, "a second relayer")
        T.eq(record.relayers, nil, "the relayer list is dropped once it counts")
        T.eq(R.Counts(record), true, "counts")

        local own = { origin = "relay" }
        T.eq(R.Vouch(own, "Author-Firemaw", "Author-Firemaw"), true, "relayed by its author")
        T.eq(R.Counts({ origin = "peer" }), true, "a direct copy always counts")
        T.noErrors()
    end)

    T.case("deaths: one peer's relay makes nobody WANTED; a second peer or the victim does", function()
        local ns = H.Boot({ client = "era" })
        local records = SpreeRecords(ns, "Gank-Stonespine")
        Relayed(ns, records, "Helper-Firemaw")
        T.eq(ns.Reports:Count(), 5, "stored")
        T.eq(#ns.Wanted:List(), 0, "not WANTED on one peer's word")
        Relayed(ns, records, "Second-Firemaw")
        T.eq(#ns.Wanted:List(), 1, "WANTED once a second peer relayed the same deaths")

        local other = H.Boot({ client = "era" })
        local more = SpreeRecords(other, "Stab-Stonespine")
        Relayed(other, more, "Helper-Firemaw")
        for _, record in ipairs(more) do
            local report = other.Protocol.DecodeDeath(record)
            H.Deliver(other.Protocol.Pack("A", "D", { record }), report.victim.key)
        end
        Settle()
        T.eq(#other.Wanted:List(), 1, "WANTED once the victims' own copies arrived")
        T.noErrors()
    end)

    T.case("catches: a relayed catch alone does not end a real WANTED", function()
        local ns = H.Boot({ client = "era" })
        local records = SpreeRecords(ns, "Gank-Stonespine")
        Relayed(ns, records, "Helper-Firemaw")
        Relayed(ns, records, "Second-Firemaw")
        T.eq(#ns.Wanted:List(), 1, "WANTED")
        local catch = ns.Protocol.EncodeJustice("Gank-Stonespine", H.serverTime - 30, 1436, "Liar-Firemaw")
        ns.Justice:AddRelayed(catch, "Liar-Firemaw")
        Settle()
        T.eq(#ns.Wanted:List(), 0, "the hunter relaying their own catch counts, as their live message would")

        local fresh = H.Boot({ client = "era" })
        Relayed(fresh, records, "Helper-Firemaw")
        Relayed(fresh, records, "Second-Firemaw")
        local fake = fresh.Protocol.EncodeJustice("Gank-Stonespine", H.serverTime - 30, 1436, "Hunter-Firemaw")
        fresh.Justice:AddRelayed(fake, "Liar-Firemaw")
        Settle()
        T.eq(#fresh.Wanted:List(), 1, "one peer's catch: still WANTED")
        fresh.Justice:AddRelayed(fake, "Second-Firemaw")
        Settle()
        T.eq(#fresh.Wanted:List(), 0, "two peers: caught")
        T.noErrors()
    end)

    T.case("bounties: one peer's unpaid makes no Deadbeat, and a relayed claim takes nobody's place", function()
        local ns = H.Boot({ client = "era" })
        local P = ns.Protocol
        local posterId = "Miser-Firemaw:" .. (H.serverTime - 5 * 86400)
        local claimedAt = H.serverTime - 4 * 86400
        ns.Bounties:Add({ id = posterId, owner = "Miser-Firemaw", target = "Gank-Stonespine", reason = 1, gold = 50000,
            ["until"] = H.serverTime - 3 * 86400, t = H.serverTime - 5 * 86400 }, "peer", "Miser-Firemaw")
        -- Someone else saw the kill, so the claim is verified (step 7)
        ns.Witness:Add({ outlaw = "Gank-Stonespine", mapID = 1436, t = claimedAt, x = 0.5, y = 0.5, by = "Eye-Firemaw" },
            "peer", "Eye-Firemaw")
        local unpaid = P.EncodePayment({ posterId = posterId, hunter = "Kestrel-Firemaw", status = "unpaid",
            claimedAt = claimedAt, t = H.serverTime - 86400 })
        ns.Bounties:AddRelayedPayment(unpaid, "Liar-Firemaw")
        T.eq(ns.Bounties:IsBlocked("Miser-Firemaw"), false, "no Deadbeat on one peer's word")
        T.eq(#ns.Bounties:Shamed(), 0, "not on the Deadbeats tab")
        ns.Bounties:AddRelayedPayment(unpaid, "Second-Firemaw")
        T.eq(ns.Bounties:IsBlocked("Miser-Firemaw"), true, "a Deadbeat once a second peer has it")

        local claimed = "Owner-Firemaw:" .. (H.serverTime - 3600)
        H.Deliver(P.Pack("A", "R", { P.EncodePayment({ posterId = claimed, hunter = "Kestrel-Firemaw", status = "claimed",
            claimedAt = H.serverTime - 1800, t = H.serverTime - 1800 }) }), "Kestrel-Firemaw")
        T.eq(ns.Bounties:Payment(claimed).hunter, "Kestrel-Firemaw", "the hunter's own claim")
        ns.Bounties:AddRelayedPayment(P.EncodePayment({ posterId = claimed, hunter = "Thief-Firemaw", status = "claimed",
            claimedAt = H.serverTime - 3000, t = H.serverTime - 3000 }), "Liar-Firemaw")
        T.eq(ns.Bounties:Payment(claimed).hunter, "Kestrel-Firemaw", "an earlier relayed claim does not take it")
        T.noErrors()
    end)

    T.case("posters: a relayed poster is not active until a second source has it", function()
        local ns = H.Boot({ client = "era" })
        local P = ns.Protocol
        local t = H.serverTime - 600
        local record = P.EncodePoster({ owner = "Owner-Firemaw", target = "Gank-Stonespine", reason = 1, gold = 50000,
            ["until"] = t + 86400, t = t })
        ns.Bounties:AddRelayedPoster(record, "Liar-Firemaw")
        T.ok(ns.Bounties:Get("Owner-Firemaw:" .. t) ~= nil, "stored")
        T.eq(#ns.Bounties:ActiveFor("Gank-Stonespine"), 0, "not active")
        ns.Bounties:AddRelayedPoster(record, "Owner-Firemaw")
        T.eq(#ns.Bounties:ActiveFor("Gank-Stonespine"), 1, "active once its owner relayed it")
        T.noErrors()
    end)

    T.case("duels: a relayed duel counts for the list only with a second source", function()
        local ns = H.Boot({ client = "era" })
        local record = ns.Protocol.EncodeDuel({ winner = "Quick-Firemaw", loser = "Slow-Firemaw", t = H.serverTime - 60,
            faction = "Alliance", winnerLevel = 60, loserLevel = 60 })
        ns.Duels:OnRecord(record, "Liar-Firemaw", "relay")
        ns.HighNoon:Recompute()
        T.eq(#ns.HighNoon:List("Alliance"), 0, "one peer's duel: not listed")
        ns.Duels:OnRecord(record, "Slow-Firemaw", "relay")
        ns.HighNoon:Recompute()
        T.eq(#ns.HighNoon:List("Alliance"), 2, "listed once a duelist relayed it too")
        T.noErrors()
    end)
end
