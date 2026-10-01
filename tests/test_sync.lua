-- HH-020 / HH-022: transport and report acceptance, end to end.

return function(T, H)
    local function RealDeath(ns, t, killerKey)
        return ns.DeathReports:Record({
            t = t or H.serverTime,
            killer = { key = killerKey or "Gank-Stonespine", name = killerKey or "Gank-Stonespine", level = 60, class = "ROGUE", race = "Orc" },
            confidence = "exact",
        }, "test")
    end

    -- A peer message as another client would send it
    local function PeerMessage(ns, report, factionCode)
        local record = ns.Protocol.EncodeDeath(report)
        return ns.Protocol.Pack(factionCode or "A", "D", { record })
    end

    local function PeerReport(victimKey, t, killer)
        return {
            t = t or H.serverTime,
            victim = { key = victimKey, level = 25, class = "MAGE", race = "Gnome" },
            killer = killer or { key = "Gank-Stonespine", name = "Gank-Stonespine", level = 60, class = "ROGUE", race = "Orc" },
            assists = {}, mapID = 1434, x = 0.5, y = 0.5, confidence = "exact",
        }
    end

    -------------------------------------------------
    -- Transport
    -------------------------------------------------

    T.case("joins the hidden channel after the server channels", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.Transport:ChannelID(), 5, "joined")
        T.ok(H.chatFilters.CHAT_MSG_CHANNEL_NOTICE ~= nil, "notice filter installed")
        -- self, event, text, playerName, language, channelName, playerName2, flags,
        -- zoneChannelID, channelIndex, channelBaseName
        local filter = H.chatFilters.CHAT_MSG_CHANNEL_NOTICE
        T.eq(filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "5. HeadHunterSync", "", "", 0, 5, "HeadHunterSync"),
            true, "our notices hidden")
        T.eq(filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "5. HeadHunterSync", "", "", 0, 5, nil),
            true, "hidden by display name when the base name is missing")
        T.eq(filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "1. General", "", "", 0, 1, "General"),
            false, "other channels untouched")
    end)

    T.case("waits while slot 1 is empty, then joins anyway", function()
        H.Install({ client = "era" })
        H.channels = {}
        local ns = H.Load()
        H.Fire("ADDON_LOADED", "HeadHunter")
        H.Fire("PLAYER_ENTERING_WORLD", true, false)
        T.eq(ns.Transport:ChannelID(), nil, "deferred")
        H.channels.General = 1
        H.Advance(2)
        T.eq(ns.Transport:ChannelID(), 5, "joined once General took /1")
        T.noErrors()
    end)

    T.case("own death is queued, batched and sent silently on the channel", function()
        local ns = H.Boot({ client = "forever" })
        H.printed = {}
        RealDeath(ns)
        T.eq(#H.sent, 0, "not sent immediately")
        T.eq(ns.Transport:PendingCount(), 1, "queued")
        H.Advance(3)
        T.eq(#H.sent, 1, "sent on flush")
        local m = H.sent[1]
        T.eq(m.prefix, "HeadHunter", "prefix")
        T.eq(m.chatType, "CHANNEL", "channel")
        T.eq(m.target, 5, "channel id")
        T.ok(#m.message <= 255, "size")
        T.ok(m.message:find("^1AD:") ~= nil, "header")
        for _, line in ipairs(H.printed) do
            T.ok(not line:lower():find("sync"), "nothing about sync in chat: " .. line)
        end
        T.noErrors()
    end)

    T.case("simulated deaths are stored but never broadcast", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim death Gank 60 ROGUE Orc")
        local total, mine = ns.Reports:Count()
        T.eq(total, 1, "stored")
        T.eq(mine, 1, "as own")
        H.Advance(3)
        T.eq(#H.sent, 0, "not sent")
    end)

    T.case("nothing is sent inside instances; sent after leaving", function()
        local ns = H.Boot({ client = "forever" })
        RealDeath(ns)
        H.instance = { true, "pvp" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        H.Advance(3)
        T.eq(#H.sent, 0, "paused")
        H.instance = { false, "none" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        H.Advance(3)
        T.eq(#H.sent, 1, "sent after leaving")
    end)

    T.case("flush interval is longer in combat", function()
        local ns = H.Boot({ client = "forever" })
        H.inCombat = true
        H.Advance(3)          -- first flush was scheduled out of combat; next one is combat-paced
        RealDeath(ns)
        H.Advance(3)
        T.eq(#H.sent, 0, "not yet")
        H.Advance(7)
        T.eq(#H.sent, 1, "after 10 s")
    end)

    T.case("token bucket limits bursts; the rest follows later", function()
        local ns = H.Boot({ client = "forever" })
        for i = 1, 5 do ns.Transport:Queue("D", string.rep("x", 200) .. i, 1) end
        H.Advance(3)
        T.eq(#H.sent, ns.Transport.BURST, "burst")
        H.Advance(3)
        T.eq(#H.sent, 5, "rest sent after refill")
    end)

    T.case("coalescing keeps one record per key", function()
        local ns = H.Boot({ client = "forever" })
        ns.Transport:Queue("P", "old", 3, "hotspot:1434")
        ns.Transport:Queue("P", "new", 3, "hotspot:1434")
        T.eq(ns.Transport:PendingCount(), 1, "one entry")
        H.Advance(3)
        T.eq(H.sent[1].message, "1AP:new", "latest wins")
    end)

    -------------------------------------------------
    -- Receiving (HH-022)
    -------------------------------------------------

    T.case("a peer's own death is accepted", function()
        local ns = H.Boot({ client = "era" })
        local added
        ns.Events:Register("HH_REPORT_ADDED", function(_, report) added = report end, "t")
        H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw")), "Victim-Firemaw")
        local _, _, peers = ns.Reports:Count()
        T.eq(peers, 1, "stored")
        T.eq(added.origin, "peer", "origin")
        T.eq(added.killer.key, "Gank-Stonespine", "killer")
        T.eq(added.classification, "coward", "classified on arrival")
        T.eq(#ns.db.deaths, 0, "not one of MY deaths")
        T.noErrors()
    end)

    T.case("same-realm sender without realm still matches the victim", function()
        local ns = H.Boot({ client = "era" })
        H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw")), "Victim")
        local _, _, peers = ns.Reports:Count()
        T.eq(peers, 1, "accepted")
    end)

    T.case("reports about someone else are rejected (anti-spoof)", function()
        local ns = H.Boot({ client = "era" })
        H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw")), "Liar-Firemaw")
        T.eq(ns.Reports:Count(), 0, "rejected")
    end)

    -- HH-123: /hh sim send test deaths of other players
    local function TestReport(victimKey, t)
        local report = PeerReport(victimKey, t)
        report.confidence = "sim"
        return report
    end

    T.case("another player's test deaths count only from a trusted character", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("debug on")
        H.Deliver(PeerMessage(ns, TestReport("Tester-Firemaw")), "Tester-Firemaw")
        T.eq(ns.Reports:Count(), 0, "debug mode alone does not trust anyone")
        T.ok(ns.Reports.lastRejected:find("test data", 1, true), "reason kept for /hh sync")

        ns = H.Boot({ client = "era", dev = { trust = { "Tester-Firemaw" } } })
        H.Deliver(PeerMessage(ns, TestReport("Tester-Firemaw")), "Tester-Firemaw")
        H.Deliver(PeerMessage(ns, TestReport("Stranger-Firemaw")), "Stranger-Firemaw")
        H.Deliver(PeerMessage(ns, PeerReport("Stranger-Firemaw")), "Stranger-Firemaw")
        local _, _, peers = ns.Reports:Count()
        T.eq(peers, 2, "trusted test death and the stranger's real death")
    end)

    T.case("test deaths are relayed only from a trusted character and never passed on", function()
        local ns = H.Boot({ client = "era", dev = { trust = { "Tester-Firemaw" } } })
        local record = ns.Protocol.EncodeDeath(TestReport("Tester-Firemaw", H.serverTime - 60))
        T.eq(ns.Reports:AddRelayed(record, "Stranger-Firemaw"), nil, "untrusted relay refused")
        local added = ns.Reports:AddRelayed(record, "Tester-Firemaw")
        T.ok(added, "trusted relay kept")
        T.eq(added.sender, nil, "the relayer is not taken as the victim")
        T.eq(#ns.Reports:Since(H.serverTime - 3600), 0, "not passed on to others")
    end)

    T.case("saved test deaths of untrusted players are dropped at load", function()
        local saved = { reports = {} }
        local function Put(id, origin, sender, relayedBy)
            saved.reports[id] = { id = id, t = H.serverTime - 60, victim = { key = "Tester-Firemaw" },
                killer = { key = "Gank-Stonespine", name = "Gank-Stonespine" }, assists = {},
                confidence = "sim", origin = origin, sender = sender, relayedBy = relayedBy }
        end
        Put("a", "peer", "Tester-Firemaw")
        Put("b", "peer", "Stranger-Firemaw")
        Put("c", "relay", nil, "Stranger-Firemaw")
        Put("d", "sim")
        local ns = H.Boot({ client = "era", savedDB = saved, dev = { trust = { "Tester-Firemaw" } } })
        T.ok(ns.Reports:Get("a"), "trusted kept")
        T.eq(ns.Reports:Get("b"), nil, "untrusted peer dropped")
        T.eq(ns.Reports:Get("c"), nil, "untrusted relay dropped")
        T.ok(ns.Reports:Get("d"), "our own simulation kept")
    end)

    T.case("/hh sim send is refused where the zone cannot be read", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("debug on")
        H.playerMap = nil
        H.Slash("sim send Gank-Stonespine 2")
        T.ok(H.Printed("cannot be read"), "told why")
        T.eq(ns.Reports:Count(), 0, "nothing sent")
        H.Slash("sim send Gank-Stonespine 2 \"Westfall\"")
        T.eq(ns.Reports:Count(), 2, "a named zone still works")
    end)

    T.case("other-faction, echo, foreign prefix and junk are ignored", function()
        local ns = H.Boot({ client = "era" })
        H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw"), "H"), "Victim-Firemaw")
        H.Deliver(PeerMessage(ns, PeerReport("Vati-Firemaw")), "Vati-Firemaw")
        H.Deliver({ { prefix = "OtherAddon", message = "whatever" } }, "Victim-Firemaw")
        H.Deliver({ "1AD:garbage" }, "Victim-Firemaw")
        H.Deliver({ "nonsense" }, "Victim-Firemaw")
        T.eq(ns.Reports:Count(), 0, "nothing stored")
        T.eq(ns.Transport.stats.dropped, 1, "unparseable message counted")
        T.noErrors()
    end)

    T.case("implausible times are rejected", function()
        local ns = H.Boot({ client = "era" })
        H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw", H.serverTime + 3600)), "Victim-Firemaw")
        H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw", H.serverTime - 31 * 86400)), "Victim-Firemaw")
        T.eq(ns.Reports:Count(), 0, "rejected")
        H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw", H.serverTime + 60)), "Victim-Firemaw")
        T.eq(ns.Reports:Count(), 1, "small clock skew allowed")
    end)

    T.case("duplicates are ignored and senders are rate limited", function()
        local ns = H.Boot({ client = "era" })
        local report = PeerReport("Victim-Firemaw")
        H.Deliver(PeerMessage(ns, report), "Victim-Firemaw")
        H.Deliver(PeerMessage(ns, report), "Victim-Firemaw")
        T.eq(ns.Reports:Count(), 1, "duplicate ignored")
        for i = 1, 15 do
            H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw", H.serverTime - i * 60)), "Victim-Firemaw")
        end
        T.eq(ns.Reports:Count(), ns.Reports.SENDER_LIMIT, "capped per sender")
        H.clock = H.clock + ns.Reports.SENDER_WINDOW + 1
        H.Deliver(PeerMessage(ns, PeerReport("Victim-Firemaw", H.serverTime - 3000)), "Victim-Firemaw")
        T.eq(ns.Reports:Count(), ns.Reports.SENDER_LIMIT + 1, "window slides")
    end)

    -- Forever keys are "Given Family": an Era-style killer key would be malformed there
    local FOREVER_KILLER = { key = "Grim Reaper", name = "Grim Reaper", level = 60, class = "ROGUE", race = "Orc" }

    T.case("forever: sender formats with realm or without space match the victim", function()
        local ns = H.Boot({ client = "forever" })
        H.Deliver(PeerMessage(ns, PeerReport("Joob Stabber", H.serverTime - 10, FOREVER_KILLER)), "Joob Stabber-ClassicBetaPvP2")
        H.Deliver(PeerMessage(ns, PeerReport("Joob Stabber", H.serverTime - 20, FOREVER_KILLER)), "JoobStabber-ClassicBetaPvP2")
        H.Deliver(PeerMessage(ns, PeerReport("Joob Stabber", H.serverTime - 30, FOREVER_KILLER)), "Joob")
        T.eq(ns.Reports:Count(), 2, "two formats accepted, given name alone rejected")
    end)

    T.case("the inbox is processed under a time budget", function()
        local ns = H.Boot({ client = "era" })
        H.profileStep = 2 -- every record costs 2 ms against a 3 ms budget
        local messages = {}
        for i = 1, 6 do
            messages[i] = PeerMessage(ns, PeerReport("Victim" .. i .. "-Firemaw", H.serverTime - i))[1]
            H.Fire("CHAT_MSG_ADDON", "HeadHunter", messages[i], "CHANNEL", "Victim" .. i .. "-Firemaw")
        end
        T.eq(ns.Reports:Count(), 0, "nothing handled inside the event")
        H.Advance(0)
        local afterOne = ns.Reports:Count()
        T.ok(afterOne > 0 and afterOne < 6, "partial batch per frame: " .. afterOne)
        for _ = 1, 10 do H.Advance(0) end
        T.eq(ns.Reports:Count(), 6, "all handled over several frames")
    end)

    -------------------------------------------------
    -- Completing incomplete killers across clients
    -------------------------------------------------

    T.case("identity from the victim completes a peer report; from anyone else it does not", function()
        local ns = H.Boot({ client = "forever" })
        local report = PeerReport("Joob Stabber", H.serverTime - 10,
            { name = "Kuh", nameIncomplete = true, guid = "Player-4613-00A96B33" })
        H.Deliver(PeerMessage(ns, report), "Joob Stabber")
        local id = "Joob Stabber:" .. (H.serverTime - 10)
        local identity = ns.Protocol.EncodeIdentity(id, { guid = "Player-4613-00A96B33", key = "Kuh Blam", level = 20, class = "HUNTER" })
        local message = ns.Protocol.Pack("A", "G", { identity })
        H.Deliver(message, "Someone Else")
        T.eq(ns.Reports:Get(id).killer.key, nil, "stranger ignored")
        H.Deliver(message, "Joob Stabber")
        T.eq(ns.Reports:Get(id).killer.key, "Kuh Blam", "victim completes")
        T.eq(ns.Reports:Get(id).killer.level, 20, "level filled")
    end)

    T.case("own incomplete report: identity is broadcast once when the GUID resolves", function()
        local ns = H.Boot({ client = "forever" })
        ns.DeathReports:Record({
            killer = { guid = "Player-7", name = "Kuh", nameIncomplete = true },
            confidence = "exact",
        }, "test")
        H.Advance(3)
        local before = #H.sent
        H.units.nameplate1 = { name = "Kuh", realm = "Blam", level = 20, class = "HUNTER", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-7" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.Advance(3)
        T.eq(#H.sent, before + 1, "one identity message")
        T.ok(H.sent[#H.sent].message:find("^1AG:") ~= nil, "identity type")
        T.ok(H.sent[#H.sent].message:find("Kuh Blam", 1, true) ~= nil, "carries the full key")
        H.clock = H.clock + 5
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.Advance(3)
        T.eq(#H.sent, before + 1, "not repeated")
        T.noErrors()
    end)

    T.case("end to end: a Forever death reaches another Forever client", function()
        -- Client A dies to Kuh Blam (seen on a nameplate), via Death Recap
        local nsA = H.Boot({ client = "forever" })
        H.units.nameplate1 = { name = "Kuh", realm = "Blam", level = 20, class = "HUNTER", race = "Orc",
            sex = 2, faction = "Horde", isPlayer = true, guid = "Player-4613-00A96B33" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.recap = { { sourceGUID = "Player-4613-00A96B33", sourceName = "Kuh-ClassicBetaPvP2",
            sourceFlags = 66888, overkill = 40, amount = 110, timestamp = H.serverTime - 5 } }
        H.Fire("PLAYER_DEAD")
        H.Advance(0.3)
        H.Advance(3)
        T.eq(#H.sent, 1, "A broadcast its death")
        local wire = { H.sent[1] }
        local victim = nsA.db.deaths[1].victim.key

        -- Client B, another character, receives it
        local nsB = H.Boot({ client = "forever" })
        H.units.player.name = "Other Person"
        H.Deliver(wire, victim .. "-ClassicBetaPvP")
        local total, mine, peers = nsB.Reports:Count()
        T.eq(peers, 1, "B stored A's death")
        local id = victim .. ":" .. (H.serverTime - 5)
        local got = nsB.Reports:Get(id)
        T.eq(got.killer.key, "Kuh Blam", "killer")
        T.eq(got.killer.level, 20, "level")
        T.eq(got.confidence, "exact", "confidence")
        T.noErrors()
    end)

    T.case("/hh sync ping reaches another client and is printed there", function()
        H.Boot({ client = "forever" })
        H.Slash("sync ping")
        H.Advance(3)
        T.eq(#H.sent, 1, "ping sent")
        T.ok(H.sent[1].message:find("^1AT:") ~= nil, "ping type")
        local wire = { H.sent[1] }
        H.Boot({ client = "forever" })
        H.Deliver(wire, "Other-Firemaw")
        T.ok(H.Printed("Sync ping from Other%-Firemaw"), "printed on the receiver")
        T.noErrors()
    end)

    T.case("a permanent channel refusal stops retries instead of looping", function()
        local ns = H.Boot({ client = "forever" })
        H.sendResults.CHANNEL = 4
        H.Slash("sync ping")
        for _ = 1, 10 do H.Advance(3) end
        T.eq(#H.attempts, 1, "tried once, not every 3 s")
        T.eq(ns.Transport.stats.failed, 1, "one failure")
        H.Slash("sync")
        T.ok(H.Printed("channel refused: 4 %(InvalidChatType%)"), "reason shown")
        T.noErrors()
    end)

    T.case("a throttle result is retried", function()
        local ns = H.Boot({ client = "forever" })
        H.sendResults.CHANNEL = 3
        H.Slash("sync ping")
        H.Advance(3)
        H.sendResults.CHANNEL = nil
        H.Advance(3)
        T.eq(#H.sent, 1, "sent on retry")
    end)

    T.case("/hh sync probe reports every chat type", function()
        H.Boot({ client = "era" })
        H.sendResults.CHANNEL = 4
        H.sendResults.PARTY = 5
        H.Slash("sync probe")
        T.ok(H.Printed("via CHANNEL: refused · result 4 %(InvalidChatType%)"), "channel refused")
        T.ok(H.Printed("via PARTY: refused · result 5 %(NotInGroup%)"), "party")
        T.ok(H.Printed("via WHISPER: accepted"), "whisper")
        T.noErrors()
    end)

    T.case("/hh sync chat: channel text is sent, received, and hidden from chat windows", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sync chat")
        T.eq(#H.chatSent, 1, "sent")
        T.eq(H.chatSent[1].chatType, "CHANNEL", "chat type")
        T.eq(H.chatSent[1].target, 5, "our channel")
        T.ok(H.chatSent[1].text:find("^HH1:test ") ~= nil, "marked text")

        -- CHAT_MSG_CHANNEL: text, sender, language, channelName, target, flags,
        -- zoneChannelID, channelIndex, channelBaseName
        H.Fire("CHAT_MSG_CHANNEL", "HH1:test 01:02:03", "Other-Firemaw", "", "5. HeadHunterSync", "", "", 0, 5, "HeadHunterSync")
        T.ok(H.Printed("Channel text from Other%-Firemaw: test 01:02:03"), "received")
        local filter = H.chatFilters.CHAT_MSG_CHANNEL
        T.eq(filter(nil, "CHAT_MSG_CHANNEL", "HH1:test", "Other", "", "5. HeadHunterSync", "", "", 0, 5, "HeadHunterSync"),
            true, "our line hidden")
        T.eq(filter(nil, "CHAT_MSG_CHANNEL", "LFG deadmines", "Other", "", "2. Trade", "", "", 0, 2, "Trade"),
            false, "other channels untouched")
        H.Fire("CHAT_MSG_CHANNEL", "HH1:x", "Other-Firemaw", "", "2. Trade", "", "", 0, 2, "Trade")
        T.ok(not H.Printed("Channel text from Other%-Firemaw: x"), "marker on another channel ignored")
        T.noErrors()
    end)

    -------------------------------------------------
    -- Classic Era routes (channel addon messages are refused there)
    -------------------------------------------------

    T.case("era: never tries the channel; no guild or group means nothing sent automatically", function()
        local ns = H.Boot({ client = "era" })
        RealDeath(ns)
        H.Advance(3)
        T.eq(#H.attempts, 0, "no doomed channel attempt")
        T.eq(ns.Transport:PendingCount(), 1, "kept for when a route appears")
        H.Slash("sync")
        T.ok(H.Printed("auto routes none"), "no route shown")
        T.ok(H.Printed("realm%-wide needs the Report button"), "reason shown")
        T.noErrors()
    end)

    T.case("era: in a guild, reports go out via GUILD", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        RealDeath(ns)
        H.Advance(3)
        T.eq(#H.sent, 1, "sent")
        T.eq(H.sent[1].chatType, "GUILD", "guild route")
    end)

    T.case("era: in a guild and a party, both routes get the message", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild, H.inGroup = true, true
        RealDeath(ns)
        H.Advance(3)
        T.eq(#H.sent, 2, "two routes")
        T.eq(H.sent[1].chatType, "GUILD", "guild")
        T.eq(H.sent[2].chatType, "PARTY", "party")
    end)

    T.case("era: a report that became sendable later still goes out", function()
        local ns = H.Boot({ client = "era" })
        RealDeath(ns)
        H.Advance(3)
        T.eq(#H.sent, 0, "no route yet")
        H.inRaid = true
        H.Advance(3)
        T.eq(#H.sent, 1, "sent once grouped")
        T.eq(H.sent[1].chatType, "RAID", "raid route")
    end)

    T.case("era: death prompt, Report click sends channel text, another client stores it", function()
        local ns = H.Boot({ client = "era" })
        RealDeath(ns, nil, "Sacredsnack-Mograine")
        T.eq(#H.popups, 1, "prompt shown")
        T.ok(H.popups[1].text:find("Sacredsnack%-Mograine") ~= nil, "prompt names the killer")
        T.ok(H.popups[1].text:find("Bully kill") ~= nil, "prompt shows the kill type")
        T.eq(_G.StaticPopupDialogs.HEADHUNTER_REPORT.whileDead, 1, "usable while dead")

        _G.StaticPopupDialogs.HEADHUNTER_REPORT.OnAccept()
        T.eq(#H.chatSent, 1, "one channel text line")
        local line = H.chatSent[1]
        T.eq(line.chatType, "CHANNEL", "channel")
        T.eq(line.target, 5, "our channel")
        T.ok(line.text:find("^HH1:1AD:") ~= nil, "marked protocol message")
        T.ok(#line.text <= 255, "fits in a chat line")
        T.eq(ns.ReportPrompt:PendingCount(), 0, "nothing left waiting")
        T.ok(H.Printed("Reported 1 death"), "confirmation")

        -- Another Era client on the same channel
        local text = line.text
        local nsB = H.Boot({ client = "era" })
        H.units.player.name = "Headhunta"
        H.Fire("CHAT_MSG_CHANNEL", text, "Vati-Firemaw", "", "5. HeadHunterSync", "", "", 0, 5, "HeadHunterSync")
        for _ = 1, 5 do H.Advance(0) end
        local _, _, peers = nsB.Reports:Count()
        T.eq(peers, 1, "stored as a peer report")
        T.eq(nsB.Transport.diag.lastSender, "Vati-Firemaw via CHANNELTEXT", "arrived as channel text")
        T.noErrors()
    end)

    T.case("era: several deaths wait for one click; Skip drops them; /hh report sends", function()
        local ns = H.Boot({ client = "era" })
        RealDeath(ns, H.serverTime - 20)
        RealDeath(ns, H.serverTime - 10)
        T.eq(ns.ReportPrompt:PendingCount(), 2, "two waiting")
        T.ok(H.popups[#H.popups].text:find("%+1 more") ~= nil, "count shown")
        _G.StaticPopupDialogs.HEADHUNTER_REPORT.OnCancel()
        T.eq(ns.ReportPrompt:PendingCount(), 0, "skipped")
        T.eq(#H.chatSent, 0, "nothing sent")
        H.Slash("report")
        T.ok(H.Printed("No death reports waiting"), "nothing to send")
        RealDeath(ns, H.serverTime - 5)
        H.Slash("report")
        T.eq(#H.chatSent, 1, "/hh report sent it")
    end)

    T.case("era: simulated deaths and Forever deaths never prompt", function()
        H.Boot({ client = "era" })
        H.Slash("sim death Gank 60 ROGUE Orc")
        T.eq(#H.popups, 0, "no prompt for sim")
        local nsF = H.Boot({ client = "forever" })
        RealDeath(nsF)
        T.eq(#H.popups, 0, "no prompt on Forever")
    end)

    T.case("/hh sync and /hh reports", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim death Gank 60 ROGUE Orc")
        H.Slash("sync")
        H.Slash("reports")
        T.ok(H.Printed("Sync: channel joined #5"), "/hh sync")
        T.ok(H.Printed("Sync diag: faction Alliance"), "/hh sync diag")
        T.ok(H.Printed("Shared reports: 1"), "/hh reports")
        T.noErrors()
    end)

    T.case("test mode (HeadHunter_Dev noSharing): nothing is sent, and the chat says so", function()
        local ns = H.Boot({ client = "era", dev = { noSharing = true } })
        H.inGuild = true
        T.ok(H.Printed("Test mode"), "login line")
        H.units.target = { name = "Gank", level = 31, class = "ROGUE", race = "Dwarf", faction = "Alliance", isPlayer = true }
        H.units.mouseover = { name = "Bob", level = 29, class = "MAGE", race = "Gnome", faction = "Alliance", isPlayer = true }
        H.Fire("CHAT_MSG_SYSTEM", "Gank has defeated Bob in a duel")
        for _ = 1, 30 do H.Advance(1) end
        T.eq(ns.Duels:Count(), 1, "still stored")
        T.eq(#H.sent, 0, "no addon message")
        T.eq(ns.Transport:SendRealmWide("U", { "x" }), 0, "no channel text")
        T.noErrors()
    end)

    T.case("without test mode the same duel is shared", function()
        local ns = H.Boot({ client = "era", dev = { trust = { "Tester-Firemaw" } } })
        H.inGuild = true
        T.ok(not H.Printed("Test mode"), "no login line")
        H.units.target = { name = "Gank", level = 31, class = "ROGUE", race = "Dwarf", faction = "Alliance", isPlayer = true }
        H.units.mouseover = { name = "Bob", level = 29, class = "MAGE", race = "Gnome", faction = "Alliance", isPlayer = true }
        H.Fire("CHAT_MSG_SYSTEM", "Gank has defeated Bob in a duel")
        for _ = 1, 30 do H.Advance(1) end
        T.eq(ns.Duels:Count(), 1, "stored")
        T.ok(#H.sent > 0, "shared")
        T.noErrors()
    end)
end
