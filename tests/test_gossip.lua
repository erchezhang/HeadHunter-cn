-- 1.0.4: the server refuses addon messages on the channel since WoW Forever's launch;
-- records spread by addon whisper among the channel's members (Sync/Gossip.lua). We are
-- Vati Guda of server 6938, Horde; the channel's members are made-up players.

return function(T, H)
    local MY_GUID = "Player-6938-00000001"
    local MEMBERS = {
        { "Arisaka Hautelame", "Player-6940-0008D0A4" },
        { "Amozis Riverhorn", "Player-6842-00771F42" },
        { "Moon Sedai", "Player-6940-000547F5" },
        { "Tobin Ashford", "Player-6938-00000002" },
        { "Rowan Fairhill", "Player-6938-00000003" },
        { "Kira Dawnblade", "Player-6856-00000004" },
        { "Vati Guda", MY_GUID },
    }

    -- The Chat Channels list: General, then HeadHunterSync at place 2 with its members
    local function Channels(members)
        H.channels.HeadHunterSync = 2
        local selected
        _G.GetNumDisplayChannels = function() return 2 end
        _G.GetChannelDisplayInfo = function(i)
            if i == 1 then return "General", false, false, 1, 50 end
            if i == 2 then return "HeadHunterSync", false, false, 2, #members end
            return nil
        end
        _G.SetSelectedDisplayChannel = function(i) selected = i end
        C_ChatInfo.GetChannelRosterInfo = function(index, r)
            if index ~= 2 or selected ~= 2 then return nil end
            local m = members[r]
            if not m then return nil end
            return m[1], false, false, m[2]
        end
    end

    local function Boot(members)
        local ns = H.Boot({ client = "forever", playerGUID = MY_GUID })
        H.units.player.faction = "Horde"
        _G.GetCurrentRegion = function() return 3 end
        Channels(members or MEMBERS)
        return ns
    end

    local function ReadRoster(ns)
        ns.Gossip:RequestRoster()
        H.Advance(ns.Gossip.ROSTER_WAIT)
    end

    local function Death(ns, t, victim)
        return ns.Protocol.EncodeDeath({
            t = t or H.serverTime - 20,
            victim = { key = victim or "Vati Guda", level = 25, class = "MAGE", race = "Undead" },
            killer = { key = "Gank Master", name = "Gank Master", level = 27, class = "ROGUE", race = "Human" },
            assists = {}, mapID = 1434, x = 0.5, y = 0.5, confidence = "exact",
        })
    end

    local function Whispers(prefix)
        local found = {}
        for _, m in ipairs(H.sent) do
            if m.chatType == "WHISPER" and (not prefix or m.message:find(prefix, 1, true)) then found[#found + 1] = m end
        end
        return found
    end

    local function Envelope(ns, fields)
        local env = { world = ns.Bridge.World(), author = "Arisaka Hautelame", faction = "Horde", server = 6940, hops = 1,
            at = H.serverTime - 10, type = "D", record = Death(ns, nil, "Arisaka Hautelame") }
        for k, v in pairs(fields or {}) do env[k] = v end
        return ns.Protocol.EncodeEnvelope(env)
    end

    local function Whispered(ns, record, sender, typeCode)
        H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("H", typeCode or "E", { record })[1], "WHISPER", sender)
        for _ = 1, 20 do H.Advance(0) end
    end

    local function Wait(seconds)
        for _ = 1, seconds * 2 do H.Advance(0.5) end
    end

    T.case("a refusal notice on our channel makes it deaf: no channel route, the reason in /hh sync, hearing someone ends it", function()
        local ns = Boot()
        H.Fire("CHAT_MSG_CHANNEL_NOTICE", "NOT_ALLOWED_IN_CHANNEL", "", "", "2. HeadHunterSync", "", "", 0, 2, "HeadHunterSync")
        T.eq(ns.Transport:ChannelDeaf(), "NOT_ALLOWED_IN_CHANNEL", "deaf")
        for _, route in ipairs(ns.Transport:AutoRoutes()) do
            T.ok(route.chatType ~= "CHANNEL" and route.chatType ~= "GUILD", "no channel, and never the guild on Forever")
        end
        H.printed = {}
        H.Slash("sync")
        T.ok(H.Printed("refused by the server: NOT_ALLOWED_IN_CHANNEL"), "said in /hh sync")
        T.ok(H.Printed("Gossip: on"), "the gossip line")
        H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("H", "N", { "1.0.4" })[1], "CHANNEL", "Moon Sedai")
        H.Advance(0)
        T.eq(ns.Transport:ChannelDeaf(), nil, "someone heard on the channel: it works again")
        T.ok(not ns.Gossip:Active(), "and the gossip rests")
    end)

    T.case("channel sends the game took but nobody answered for five minutes make it deaf", function()
        local ns = Boot()
        for _ = 1, 3 do
            ns.Transport:NoteChannelSend()
            H.Advance(ns.Transport.SILENT_FOR / 2)
        end
        T.eq(ns.Transport:ChannelDeaf(), "nobody heard", "deaf")
    end)

    T.case("the member list: read once asked for, with home servers; it is who is online", function()
        local ns = Boot()
        ReadRoster(ns)
        T.eq(ns.Gossip:PeerCount(), #MEMBERS, "every member")
        T.eq(ns.Presence:Count().total, #MEMBERS, "the online count is the list's")
        T.eq(ns.Presence:Count().scope, "channel", "and says so")
        T.ok(ns.Presence:Knows("tobinashford"), "a member counts as online (the Gang tab)")
        local ours, others = ns.Presence:Servers()
        T.eq(ours, 2, "two others on our server")
        T.eq(others, 4, "four on other servers")
    end)

    T.case("the member list is not asked for while the Chat Channels window is open", function()
        local ns = Boot()
        local asked = false
        _G.SetSelectedDisplayChannel = function() asked = true end
        _G.ChannelFrame = CreateFrame("Frame")
        ChannelFrame:Show()
        ns.Gossip:RequestRoster()
        T.ok(not asked, "not while it shows")
        ChannelFrame:Hide()
        H.Advance(ns.Gossip.ROSTER_RETRY)
        T.ok(asked, "once it closed")
        _G.ChannelFrame = nil
    end)

    T.case("our record goes by whisper to five members while few run the new gossip, in an envelope we authored", function()
        local ns = Boot()
        ReadRoster(ns)
        H.sent = {}
        ns.Transport:Queue("D", Death(ns), ns.Transport.PRIORITY.alert)
        Wait(1)
        local sent = Whispers("1HE:")
        T.eq(#sent, ns.Gossip.OWN_FANOUT, "five whispers")
        local targets = {}
        for _, m in ipairs(sent) do
            T.ok(m.target ~= "Vati Guda", "never to ourselves")
            T.ok(not targets[m.target], "different members")
            targets[m.target] = true
            local _, typeCode, records = ns.Protocol.Unpack(m.message)
            local env = ns.Protocol.DecodeEnvelope(records[1])
            T.eq(typeCode, "E", "an envelope")
            T.eq(env.hops, 1, "first hop")
            T.ok(ns.Utils.SameCharacter(env.author, "Vati Guda"), "we are the author")
        end
    end)

    T.case("a first hop from its author counts as their own copy and goes on to three more; a copy is not passed twice", function()
        local ns = Boot()
        ReadRoster(ns)
        H.sent = {}
        local before = ns.Reports:Count()
        local record = Envelope(ns)
        Whispered(ns, record, "Arisaka Hautelame")
        T.eq(ns.Reports:Count(), before + 1, "stored as the author's own report")
        Wait(1)
        local passed = Whispers("1HE:")
        T.eq(#passed, ns.Gossip.FANOUT, "passed on to three")
        for _, m in ipairs(passed) do
            T.ok(m.target ~= "Arisaka Hautelame", "not back to the author")
            local _, _, records = ns.Protocol.Unpack(m.message)
            T.eq(ns.Protocol.DecodeEnvelope(records[1]).hops, 2, "second hop")
        end
        H.sent = {}
        Whispered(ns, Envelope(ns, { hops = 2 }), "Moon Sedai")
        Wait(1)
        T.eq(#Whispers("1HE:"), 0, "a copy we have is not passed on again")
    end)

    T.case("an envelope at the last hop is taken but not passed on; a first hop not from its author is refused", function()
        local ns = Boot()
        ReadRoster(ns)
        H.sent = {}
        Whispered(ns, Envelope(ns, { hops = ns.Gossip.MAX_HOPS }), "Moon Sedai")
        Wait(1)
        T.eq(#Whispers("1HE:"), 0, "the last hop stops")
        local refused = ns.Bridge.stats.refused
        Whispered(ns, Envelope(ns, { hops = ns.Gossip.MAX_HOPS + 1, record = Death(ns, H.serverTime - 30, "Moon Sedai") }), "Moon Sedai")
        T.eq(ns.Bridge.stats.refused, refused + 1, "beyond the last hop: refused")
    end)

    T.case("a member the game says is not playing is skipped for an hour, and that line is hidden", function()
        local ns = Boot({ { "Arisaka Hautelame", "Player-6940-0008D0A4" }, { "Moon Sedai", "Player-6940-000547F5" },
            { "Vati Guda", MY_GUID } })
        _G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
        ReadRoster(ns)
        H.sent = {}
        ns.Transport:Queue("D", Death(ns), ns.Transport.PRIORITY.alert)
        Wait(1)
        T.eq(#Whispers("1HE:"), 2, "both members")
        local line = "No player named 'Moon Sedai' is currently playing."
        T.ok(ns.Gossip.SystemFilter(nil, "CHAT_MSG_SYSTEM", line), "the line is hidden")
        H.Fire("CHAT_MSG_SYSTEM", line)
        local reachable = ns.Gossip:Reachable()
        T.eq(reachable, 1, "one member left in reach")
        H.sent = {}
        ns.Transport:Queue("D", Death(ns, H.serverTime - 5), ns.Transport.PRIORITY.alert)
        Wait(1)
        local sent = Whispers("1HE:")
        T.eq(#sent, 1, "only the one in reach")
        T.eq(sent[1].target, "Arisaka Hautelame", "who answered")
        T.ok(not ns.Gossip.SystemFilter(nil, "CHAT_MSG_SYSTEM", "No player named 'Someone Else' is currently playing."),
            "a player we never whispered keeps the game's line")
    end)

    T.case("a member heard to be of the other faction gets no records", function()
        local ns = Boot({ { "Arisaka Hautelame", "Player-6940-0008D0A4" }, { "Moon Sedai", "Player-6940-000547F5" },
            { "Vati Guda", MY_GUID } })
        ReadRoster(ns)
        H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("A", "T", { "hello" })[1], "WHISPER", "Moon Sedai")
        H.Advance(0)
        H.sent = {}
        ns.Transport:Queue("D", Death(ns), ns.Transport.PRIORITY.alert)
        Wait(1)
        local sent = Whispers("1HE:")
        T.eq(#sent, 1, "one whisper")
        T.eq(sent[1].target, "Arisaka Hautelame", "to our faction's member only")
    end)

    T.case("the catch-up hello goes by whisper to a few members", function()
        local ns = Boot()
        ReadRoster(ns)
        H.sent = {}
        ns.Transport:Queue("Q", "h1", ns.Transport.PRIORITY.alert, "Q:hello")
        Wait(1)
        T.eq(#Whispers("1HQ:h1"), ns.Gossip.HELLO_PEERS, "five hellos")
    end)

    T.case("whispers keep to their budget: a burst at once, the rest as tokens come", function()
        local ns = Boot()
        ReadRoster(ns)
        H.sent = {}
        for i = 1, 10 do ns.Transport:Queue("D", Death(ns, H.serverTime - 100 - i), ns.Transport.PRIORITY.alert) end
        H.Advance(0.5)
        T.ok(#Whispers() <= ns.Gossip.BURST + 1, "no more than the burst at once")
        Wait(30)
        T.ok(#Whispers() > ns.Gossip.BURST, "the rest follows")
        T.noErrors()
    end)

    T.case("/hh sync gossip: a test ping in an envelope to one player, shown there and never passed on", function()
        local ns = Boot()
        ReadRoster(ns)
        H.sent = {}
        H.Slash('sync gossip "Moon Sedai"')
        Wait(1)
        local sent = Whispers("1HE:")
        T.eq(#sent, 1, "one envelope")
        T.eq(sent[1].target, "Moon Sedai", "to that player")
        local _, _, records = ns.Protocol.Unpack(sent[1].message)
        local env = ns.Protocol.DecodeEnvelope(records[1])
        T.eq(env.type, "T", "a ping")
        H.printed, H.sent = {}, {}
        Whispered(ns, ns.Protocol.EncodeEnvelope({ world = ns.Bridge.World(), author = "Arisaka Hautelame", faction = "Horde",
            server = 6940, hops = 1, at = H.serverTime, type = "T", record = "gossip 15:40:00" }), "Arisaka Hautelame")
        T.ok(H.Printed("Sync ping from Arisaka Hautelame"), "the receiver shows it")
        Wait(1)
        T.eq(#Whispers("1HE:"), 0, "and never passes a ping on")
    end)

    T.case("members known to run the new gossip are picked first, plus one more to find others", function()
        local ns = Boot()
        ReadRoster(ns)
        Whispered(ns, Envelope(ns, { author = "Moon Sedai", record = Death(ns, H.serverTime - 40, "Moon Sedai") }), "Moon Sedai")
        Whispered(ns, Envelope(ns, { author = "Kira Dawnblade", record = Death(ns, H.serverTime - 41, "Kira Dawnblade") }),
            "Kira Dawnblade")
        T.eq(ns.Gossip:KnownCount(), 2, "two known")
        for _ = 1, 20 do
            local picked = ns.Gossip:Pick(ns.Gossip.FANOUT)
            local names = {}
            for _, peer in ipairs(picked) do names[ns.Utils.CompactName(peer.key)] = true end
            T.ok(names.moonsedai and names.kiradawnblade, "both known ones every time")
            T.eq(#picked, ns.Gossip.FANOUT, "and unknown ones for the rest")
        end
        for i = 1, 8 do
            Whispered(ns, Envelope(ns, { author = "Known" .. i .. " Hunter", record = Death(ns, H.serverTime - 50 - i, "Known" .. i .. " Hunter") }),
                "Known" .. i .. " Hunter")
        end
        T.eq(ns.Gossip:KnownCount(), 10, "ten known")
        local picked = ns.Gossip:Pick(ns.Gossip.FANOUT)
        local unknown = 0
        for _, peer in ipairs(picked) do
            if not peer.modern then unknown = unknown + 1 end
        end
        T.eq(#picked, ns.Gossip.FANOUT + ns.Gossip.DISCOVER, "three known and one to discover")
        T.eq(unknown, ns.Gossip.DISCOVER, "one of them unknown")
        H.sent = {}
        ns.Transport:Queue("D", Death(ns, H.serverTime - 70), ns.Transport.PRIORITY.alert)
        Wait(1)
        local ours = 0
        for _, m in ipairs(Whispers("1HE:")) do
            local _, _, records = ns.Protocol.Unpack(m.message)
            for _, record in ipairs(records) do
                if ns.Utils.SameCharacter(ns.Protocol.DecodeEnvelope(record).author, "Vati Guda") then ours = ours + 1 end
            end
        end
        T.eq(ours, ns.Gossip.FANOUT + ns.Gossip.DISCOVER, "with many known, our record goes to three plus one")
    end)

    T.case("versions: newer is compared by numbers, a release candidate is older than its release", function()
        local ns = Boot()
        local P = ns.Presence
        T.ok(P.Newer("1.0.5", "1.0.4"), "1.0.5 > 1.0.4")
        T.ok(P.Newer("1.1.0", "1.0.10"), "1.1.0 > 1.0.10")
        T.ok(not P.Newer("1.0.4", "1.0.4"), "not the same")
        T.ok(not P.Newer("1.0.3", "1.0.4"), "not an older one")
        T.ok(P.Newer("1.1.0", "1.1.0-rc.1"), "a release over its candidate")
        T.ok(not P.Newer("@project-version@", "1.0.4"), "something that is no version is ignored")
    end)

    T.case("a newer version heard from two players is said once a session; from one, or an older one, not", function()
        local ns = Boot()
        ns.version = "1.0.4"
        local function Version(sender, version, chatType)
            H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("H", "N", { version })[1], chatType or "WHISPER", sender)
            H.Advance(0)
        end
        H.printed = {}
        Version("Moon Sedai", "1.0.3")
        Version("Moon Sedai", "1.0.5")
        T.ok(not H.Printed("newer HeadHunter"), "not from one player")
        Version("Tobin Ashford", "1.0.5", "PARTY")
        T.ok(H.Printed("newer HeadHunter %(1.0.5%) is available; you have 1.0.4"), "said once two players run it")
        H.printed = {}
        Version("Kira Dawnblade", "1.0.5")
        T.ok(not H.Printed("newer HeadHunter"), "only once")
        Version("Kira Dawnblade", "1.0.6")
        Version("Rowan Fairhill", "1.0.6")
        T.ok(H.Printed("newer HeadHunter %(1.0.6%)"), "again for an even newer one")
    end)

    T.case("the first whisper to a member in a session carries our version, the next ones not", function()
        local ns = Boot({ { "Arisaka Hautelame", "Player-6940-0008D0A4" }, { "Vati Guda", MY_GUID } })
        ReadRoster(ns)
        H.sent = {}
        ns.Transport:Queue("D", Death(ns), ns.Transport.PRIORITY.alert)
        Wait(1)
        local presence = Whispers("1HN:")
        T.eq(#presence, 1, "our version once")
        T.ok(presence[1].message:find(ns.version, 1, true), "with our version")
        H.sent = {}
        ns.Transport:Queue("D", Death(ns, H.serverTime - 5), ns.Transport.PRIORITY.alert)
        Wait(1)
        T.eq(#Whispers("1HN:"), 0, "not again this session")
        T.eq(#Whispers("1HE:"), 1, "the record still goes")
    end)

    T.case("versions: newer is compared by numbers, a release candidate is older than its release", function()
        local ns = Boot()
        local P = ns.Presence
        T.ok(P.Newer("1.0.5", "1.0.4"), "1.0.5 > 1.0.4")
        T.ok(P.Newer("1.1.0", "1.0.10"), "1.1.0 > 1.0.10")
        T.ok(not P.Newer("1.0.4", "1.0.4"), "not the same")
        T.ok(not P.Newer("1.0.3", "1.0.4"), "not an older one")
        T.ok(P.Newer("1.1.0", "1.1.0-rc.1"), "a release over its candidate")
        T.ok(not P.Newer("@project-version@", "1.0.4"), "something that is no version is ignored")
    end)

    T.case("a newer version heard from two players is said once a session; from one, or an older one, not", function()
        local ns = Boot()
        ns.version = "1.0.4"
        local function Version(sender, version, chatType)
            H.Fire("CHAT_MSG_ADDON", "HeadHunter", ns.Protocol.Pack("H", "N", { version })[1], chatType or "WHISPER", sender)
            H.Advance(0)
        end
        H.printed = {}
        Version("Moon Sedai", "1.0.3")
        Version("Moon Sedai", "1.0.5")
        T.ok(not H.Printed("newer HeadHunter"), "not from one player")
        Version("Tobin Ashford", "1.0.5", "PARTY")
        T.ok(H.Printed("newer HeadHunter %(1.0.5%) is available; you have 1.0.4"), "said once two players run it")
        H.printed = {}
        Version("Kira Dawnblade", "1.0.5")
        T.ok(not H.Printed("newer HeadHunter"), "only once")
        Version("Kira Dawnblade", "1.0.6")
        Version("Rowan Fairhill", "1.0.6")
        T.ok(H.Printed("newer HeadHunter %(1.0.6%)"), "again for an even newer one")
    end)

    T.case("the first whisper to a member in a session carries our version, the next ones not", function()
        local ns = Boot({ { "Arisaka Hautelame", "Player-6940-0008D0A4" }, { "Vati Guda", MY_GUID } })
        ReadRoster(ns)
        H.sent = {}
        ns.Transport:Queue("D", Death(ns), ns.Transport.PRIORITY.alert)
        Wait(1)
        local presence = Whispers("1HN:")
        T.eq(#presence, 1, "our version once")
        T.ok(presence[1].message:find(ns.version, 1, true), "with our version")
        H.sent = {}
        ns.Transport:Queue("D", Death(ns, H.serverTime - 5), ns.Transport.PRIORITY.alert)
        Wait(1)
        T.eq(#Whispers("1HN:"), 0, "not again this session")
        T.eq(#Whispers("1HE:"), 1, "the record still goes")
    end)

    T.case("hello: each member gets our version once, one every two seconds", function()
        local ns = Boot()
        ReadRoster(ns)
        H.sent = {}
        H.Advance(ns.Gossip.HELLO_SPACING)
        Wait(1)
        T.eq(#Whispers("1HN:"), 1, "one hello at a time")
        Wait(ns.Gossip.HELLO_SPACING * #MEMBERS)
        local told = {}
        for _, m in ipairs(Whispers("1HN:")) do
            T.ok(not told[m.target], "never twice to one member")
            told[m.target] = true
        end
        local count = 0
        for _ in pairs(told) do count = count + 1 end
        T.eq(count, #MEMBERS - 1, "every member but us")
        T.ok(not told["Vati Guda"], "not to ourselves")
    end)

    T.case("a member whose hello reaches us runs the gossip, and gets our hello back once", function()
        local ns = Boot()
        ReadRoster(ns)
        T.eq(ns.Gossip:KnownCount(), 0, "nobody known yet")
        H.sent = {}
        Whispered(ns, "1.0.5", "Moon Sedai", "N")
        T.eq(ns.Gossip:KnownCount(), 1, "known once their hello came")
        Wait(1)
        local back = {}
        for _, m in ipairs(Whispers("1HN:")) do
            if m.target == "Moon Sedai" then back[#back + 1] = m end
        end
        T.eq(#back, 1, "our hello back")
        Whispered(ns, "1.0.5", "Moon Sedai", "N")
        Wait(1)
        local again = 0
        for _, m in ipairs(Whispers("1HN:")) do
            if m.target == "Moon Sedai" then again = again + 1 end
        end
        T.eq(again, 1, "only once")
    end)

    T.case("cleanup: the channel list and region stubs of these tests", function()
        _G.GetCurrentRegion, _G.GetNumDisplayChannels, _G.GetChannelDisplayInfo = nil, nil, nil
        _G.SetSelectedDisplayChannel, _G.ERR_CHAT_PLAYER_NOT_FOUND_S = nil, nil
        T.ok(true, "done")
    end)
end
