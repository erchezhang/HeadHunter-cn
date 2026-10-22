-- HH-151: HeadHunters of every home server share one world (Sync/Bridge.lua). We are
-- Vati Guda of server 6946; group members and carriers of other servers. Made-up
-- players only.

return function(T, H)
    local MY_GUID = "Player-6946-00000001"

    local function Boot(opts)
        local ns = H.Boot({ client = "forever", playerGUID = MY_GUID })
        _G.GetCurrentRegion = function() return 3 end
        for k, v in pairs(opts or {}) do ns.db.settings[k] = v end
        return ns
    end

    -- A group member; known as a HeadHunter once they said hello on the group
    local function Member(ns, unit, name, server, known)
        H.units[unit] = { name = name, guid = "Player-" .. server .. "-0000000" .. #unit, faction = "Alliance",
            isPlayer = true, level = 30 }
        H.inGroup = true
        H.Fire("GROUP_ROSTER_UPDATE")
        if known ~= false then
            H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("A", "N", { "0.7.0" })[1], "PARTY", name)
            for _ = 1, 5 do H.Advance(0) end
        end
    end

    local function DeathRecord(ns, victim, t)
        return ns.Protocol.EncodeDeath({
            t = t or H.serverTime - 20,
            victim = { key = victim, level = 25, class = "MAGE", race = "Gnome" },
            killer = { key = "Gank Master", name = "Gank Master", level = 27, class = "ROGUE", race = "Orc" },
            assists = {}, mapID = 1434, x = 0.5, y = 0.5, confidence = "exact",
        })
    end

    local function Fire(ns, typeCode, record, chatType, sender)
        H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("A", typeCode, { record })[1], chatType, sender)
        for _ = 1, 20 do H.Advance(0) end
    end

    local function Envelope(ns, fields)
        local env = { world = ns.Bridge.World(), author = "Grim Reaper", faction = "Alliance", server = 6856, hops = 1,
            at = H.serverTime - 10, type = "D", record = DeathRecord(ns, "Grim Reaper") }
        for k, v in pairs(fields or {}) do env[k] = v end
        return ns.Protocol.EncodeEnvelope(env)
    end

    local function Carried(chatType)
        local found = {}
        for _, m in ipairs(H.sent) do
            if m.message:find("^1AE:") and (not chatType or m.chatType == chatType) then
                local carriesDeath = m.message:find(";D", 1, true) ~= nil
                if carriesDeath then found[#found + 1] = m end
            end
        end
        return found
    end

    local function Wait(seconds)
        for _ = 1, seconds do H.Advance(1) end
    end

    T.case("a record of our channel goes on to a group member of another server", function()
        local ns = Boot()
        Member(ns, "party1", "Vieta Unbothered", 6856)
        H.sent = {}
        Fire(ns, "D", DeathRecord(ns, "Ash Wren"), "CHANNEL", "Ash Wren")
        Wait(7)
        local sent = Carried("PARTY")
        T.eq(#sent, 1, "carried to the party")
        local _, _, records = ns.Protocol.Unpack(sent[1].message)
        local env = ns.Protocol.DecodeEnvelope(records[1])
        T.eq(env.author, "Ash Wren", "the author kept")
        T.eq(env.hops, 1, "one carrier")
        T.eq(env.world, "eu-?", "our world")
        T.eq(#Carried("CHANNEL"), 0, "not back to the channel")
        T.noErrors()
    end)

    T.case("a group member's own record of another server goes on to our channel", function()
        local ns = Boot()
        Member(ns, "party1", "Vieta Unbothered", 6856)
        H.sent = {}
        Fire(ns, "D", DeathRecord(ns, "Vieta Unbothered"), "PARTY", "Vieta Unbothered")
        Wait(7)
        T.eq(#Carried("CHANNEL"), 1, "carried to our channel")
        T.eq(#Carried("PARTY"), 0, "not back to the group")
    end)

    T.case("nothing is carried for a group of our own server", function()
        local ns = Boot()
        Member(ns, "party1", "Moss Walker", 6946)
        H.sent = {}
        Fire(ns, "D", DeathRecord(ns, "Ash Wren"), "CHANNEL", "Ash Wren")
        Fire(ns, "D", DeathRecord(ns, "Moss Walker"), "PARTY", "Moss Walker")
        Wait(7)
        T.eq(#Carried(), 0, "no envelope")
    end)

    T.case("only the first by name of our server's HeadHunters in the group carries", function()
        local ns = Boot()
        Member(ns, "party1", "Vieta Unbothered", 6856)
        Member(ns, "party2", "Aaron Black", 6946)
        H.sent = {}
        Fire(ns, "D", DeathRecord(ns, "Ash Wren"), "CHANNEL", "Ash Wren")
        Wait(7)
        T.eq(#Carried(), 0, "Aaron Black is our bridge")

        Member(ns, "party2", "Aaron Black", 6946, false)
        local ns2 = Boot()
        Member(ns2, "party1", "Vieta Unbothered", 6856)
        Member(ns2, "party2", "Aaron Black", 6946, false)
        H.sent = {}
        Fire(ns2, "D", DeathRecord(ns2, "Ash Wren"), "CHANNEL", "Ash Wren")
        Wait(7)
        T.eq(#Carried("PARTY"), 1, "a group member without the addon does not count")
    end)

    T.case("a carried death is kept as relayed and counts once a second carrier has it", function()
        local ns = Boot()
        Member(ns, "party1", "Vieta Unbothered", 6856)
        Fire(ns, "E", Envelope(ns), "PARTY", "Vieta Unbothered")
        local id = "Grim Reaper:" .. (H.serverTime - 20)
        local report = ns.Reports:Get(id)
        T.ok(report ~= nil, "stored")
        T.eq(report.origin, "relay", "as relayed")
        T.eq(ns.Relay.Counts(report), false, "one source: does not count yet")

        Fire(ns, "E", Envelope(ns), "CHANNEL", "Moss Walker")
        T.eq(ns.Relay.Counts(ns.Reports:Get(id)), true, "a second carrier: counts")
        T.eq(ns.Bridge.stats.duplicates, 1, "not delivered twice")
        T.noErrors()
    end)

    T.case("a carried catch keeps who made it", function()
        local ns = Boot()
        local record = ns.Protocol.EncodeJustice("Gank Master", H.serverTime - 15, 1434, "Ash Wren")
        Fire(ns, "E", Envelope(ns, { author = "Kestrel Vane", type = "K", record = record }), "CHANNEL", "Moss Walker")
        local catch = ns.Justice:Get("Gank Master:" .. (H.serverTime - 15))
        T.ok(catch ~= nil, "stored")
        T.eq(catch.hunter, "Kestrel Vane", "the author is the hunter, not the killer")
        T.eq(catch.origin, "relay", "as relayed")
    end)

    T.case("envelopes from another world, too old, too many hops, or naming the carrier are refused", function()
        local ns = Boot()
        Fire(ns, "E", Envelope(ns, { world = "us-pvp" }), "CHANNEL", "Moss Walker")
        Fire(ns, "E", Envelope(ns, { at = H.serverTime - 700 }), "CHANNEL", "Moss Walker")
        Fire(ns, "E", Envelope(ns, { hops = 3 }), "CHANNEL", "Moss Walker")
        Fire(ns, "E", Envelope(ns, { author = "Moss Walker", record = DeathRecord(ns, "Moss Walker") }), "CHANNEL", "Moss Walker")
        T.eq(ns.Bridge.stats.refused, 4, "four refused")
        T.eq(ns.Reports:Get("Grim Reaper:" .. (H.serverTime - 20)), nil, "nothing stored")
    end)

    T.case("a record someone else carried while we waited is not carried again", function()
        local ns = Boot()
        Member(ns, "party1", "Vieta Unbothered", 6856)
        H.sent = {}
        local record = DeathRecord(ns, "Ash Wren")
        Fire(ns, "D", record, "CHANNEL", "Ash Wren")
        Fire(ns, "E", Envelope(ns, { author = "Ash Wren", server = 6946, record = record }), "PARTY", "Vieta Unbothered")
        Wait(7)
        T.eq(#Carried(), 0, "skipped")
    end)

    T.case("a carried record goes on once more, never a third time", function()
        local ns = Boot()
        Member(ns, "party1", "Vieta Unbothered", 6856)
        H.sent = {}
        Fire(ns, "E", Envelope(ns, { hops = 1, author = "Ash Wren", server = 6946, record = DeathRecord(ns, "Ash Wren") }),
            "CHANNEL", "Moss Walker")
        Wait(7)
        local sent = Carried("PARTY")
        T.eq(#sent, 1, "on to the group")
        local _, _, records = ns.Protocol.Unpack(sent[1].message)
        T.eq(ns.Protocol.DecodeEnvelope(records[1]).hops, 2, "second carrier")

        H.sent = {}
        Fire(ns, "E", Envelope(ns, { hops = 2, author = "Ivy Stone", server = 6946, record = DeathRecord(ns, "Ivy Stone") }),
            "CHANNEL", "Moss Walker")
        Wait(7)
        T.eq(#Carried(), 0, "two carriers: no further")
    end)

    T.case("at most QUEUE_MAX wait, the hotspot pings are dropped first, and carrying uses half the budget", function()
        local ns = Boot()
        Member(ns, "party1", "Vieta Unbothered", 6856)
        local B = ns.Bridge
        local waiting, dropped = B.QueueCount(), B.stats.dropped
        for i = 1, 20 do
            B:Schedule({ world = B.World(), author = "Ping " .. i, faction = "Alliance", server = 6946, hops = 1,
                at = H.serverTime, type = "P", record = "p" .. i }, "GROUP")
        end
        for i = 1, 100 do
            B:Schedule({ world = B.World(), author = "Dead " .. i, faction = "Alliance", server = 6946, hops = 1,
                at = H.serverTime, type = "D", record = "d" .. i }, "GROUP")
        end
        T.eq(B.QueueCount(), B.QUEUE_MAX, "capped")
        T.eq(B.stats.dropped - dropped, waiting + 20, "the overflow dropped")
        for _, item in ipairs({ B:Take("GROUP", 1000) }) do
            for _, encoded in ipairs(item) do
                T.ok(ns.Protocol.DecodeEnvelope(encoded).type ~= "P", "no hotspot ping kept")
            end
        end

        local ns2 = Boot()
        Member(ns2, "party1", "Vieta Unbothered", 6856)
        H.sent = {}
        for i = 1, 30 do
            ns2.Bridge:Schedule({ world = ns2.Bridge.World(), author = "Dead " .. i, faction = "Alliance", server = 6946,
                hops = 1, at = H.serverTime, type = "D", record = DeathRecord(ns2, "Dead" .. i) }, "GROUP")
        end
        Wait(3)
        H.sent = {}
        Wait(20)
        T.ok(#Carried() <= 12, "about one message every 2 s: " .. #Carried())
        T.noErrors()
    end)

    T.case("a nameplate of another server gets one hidden whisper, and a link pulls once", function()
        local ns = Boot()
        H.units.nameplate1 = { name = "Rook Hale", guid = "Player-6856-00000077", faction = "Alliance", isPlayer = true }
        H.sent = {}
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        Wait(4)
        local whispers = 0
        for _, m in ipairs(H.sent) do
            if m.chatType == "WHISPER" and m.message:find("^1AH:") then whispers = whispers + 1 end
        end
        T.eq(whispers, 1, "one link whisper")
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        Wait(4)
        local again = 0
        for _, m in ipairs(H.sent) do
            if m.chatType == "WHISPER" and m.message:find("^1AH:") then again = again + 1 end
        end
        T.eq(again, 1, "not again within 10 minutes")

        H.sent = {}
        Fire(ns, "H", ns.Protocol.ToB36(6856), "WHISPER", "Rook Hale")
        Wait(4)
        local pull = false
        for _, m in ipairs(H.sent) do
            if m.chatType == "WHISPER" and m.message:find("^1AQ:p") then pull = true end
        end
        T.ok(pull, "a pull of their recent records")
        T.eq(ns.Bridge.stats.links, 1, "linked")
        T.noErrors()
    end)

    T.case("a nameplate of our own server, or of the other faction, gets nothing", function()
        local ns = Boot()
        H.units.nameplate1 = { name = "Moss Walker", guid = "Player-6946-00000077", faction = "Alliance", isPlayer = true }
        H.units.nameplate2 = { name = "Gank Master", guid = "Player-6856-00000078", faction = "Horde", isPlayer = true }
        H.sent = {}
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        Wait(4)
        local whispers = 0
        for _, m in ipairs(H.sent) do
            if m.chatType == "WHISPER" then whispers = whispers + 1 end
        end
        T.eq(whispers, 0, "no whisper")
    end)

    T.case("the setting turns carrying off", function()
        local ns = Boot({ relay = false })
        Member(ns, "party1", "Vieta Unbothered", 6856)
        H.sent = {}
        Fire(ns, "D", DeathRecord(ns, "Ash Wren"), "CHANNEL", "Ash Wren")
        Fire(ns, "E", Envelope(ns), "PARTY", "Vieta Unbothered")
        Wait(7)
        T.eq(#Carried(), 0, "nothing carried")
        T.eq(ns.Reports:Get("Grim Reaper:" .. (H.serverTime - 20)), nil, "envelopes not taken")
    end)

    T.case("/hh online tells our server from the others", function()
        local ns = Boot()
        Member(ns, "party1", "Vieta Unbothered", 6856)
        Fire(ns, "N", "0.7.0", "CHANNEL", "Ash Wren")
        Fire(ns, "E", Envelope(ns, { author = "Rook Hale", type = "N", record = "0.7.0" }), "PARTY", "Vieta Unbothered")
        H.printed = {}
        H.Slash("online")
        T.ok(H.Printed("On your server: 2 · on other servers: 2"), "us and Ash Wren; Vieta and Rook Hale")
    end)

    T.case("load: a raid of 40 from 10 servers stays inside the limits", function()
        local ns = Boot()
        H.units.player.name = "Aa Bridge"
        H.inRaid = true
        for i = 1, 39 do
            local server = 6946 + (i % 10)
            H.units["raid" .. i] = { name = "Raider " .. i, guid = "Player-" .. server .. "-" .. i, faction = "Alliance",
                isPlayer = true, level = 30 }
        end
        H.Fire("GROUP_ROSTER_UPDATE")
        for i = 1, 39 do
            H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("A", "N", { "0.7.0" })[1], "RAID", "Raider " .. i)
        end
        for _ = 1, 20 do H.Advance(0) end
        collectgarbage("collect")
        local memory = collectgarbage("count")
        local started = os.clock()
        for second = 1, 120 do
            for i = 1, 5 do
                local sender = "Raider " .. ((second * 5 + i) % 39 + 1)
                local record = DeathRecord(ns, sender, H.serverTime - second - i)
                H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("A", "D", { record })[1], "RAID", sender)
                local env = Envelope(ns, { author = "Far " .. second .. i, record = DeathRecord(ns, "Far " .. second .. i) })
                H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("A", "E", { env })[1], "CHANNEL", "Ash Wren")
            end
            H.Advance(1)
        end
        local perMessage = (os.clock() - started) * 1000 / 1200
        collectgarbage("collect")
        local grown = collectgarbage("count") - memory
        T.ok(perMessage < 2, string.format("%.3f ms per message", perMessage))
        T.ok(ns.Bridge.stats.forwarded > 0, "we carried: we are our server's bridge")
        T.ok(ns.Bridge.QueueCount() <= ns.Bridge.QUEUE_MAX, "queue within its cap")
        T.ok(ns.Bridge.SeenCount() <= ns.Bridge.SEEN_MAX, "seen ring within its cap")
        T.ok(grown < 4096, string.format("memory grew %.0f KB", grown))
        T.noErrors()
    end)

    T.case("(the region stub goes)", function()
        _G.GetCurrentRegion = nil
    end)
end
