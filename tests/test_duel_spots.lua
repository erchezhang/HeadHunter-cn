-- HH-134: duel spots (10 duels between 5 different players level 19+ in 20 min, per zone and
-- layer), pings, the chat line, the invite whisper and the map mark. Made-up players only.

return function(T, H)
    local NAMES = { "Tovik", "Marla", "Grenn", "Sully", "Pike", "Odda", "Brannic" }

    local function OurLayer(layer)
        H.units.nameplate9 = { name = "Defias Thug", faction = "Horde", isPlayer = false,
            guid = "Creature-0-4613-0-" .. layer .. "-116-0000ABCD" }
    end

    -- `n` duels among the first `players` NAMES, one minute apart, newest `ago` seconds old
    local function DuelList(ns, n, players, ago)
        local P, list = ns.Protocol, {}
        for i = 1, n do
            local a = NAMES[(i - 1) % players + 1]
            local b = NAMES[i % players + 1]
            list[#list + 1] = { a = P.NameHash(a .. "-Firemaw"), b = P.NameHash(b .. "-Firemaw"),
                t = H.serverTime - (ago or 5) - (i - 1) * 61 }
        end
        return list
    end

    local function Ping(ns, mapID, sender, duels, layer, faction)
        local record = ns.Protocol.EncodeDuelSpot(mapID, H.serverTime, 0.4, 0.6, layer, duels)
        H.Deliver(ns.Protocol.Pack(faction or "A", "Z", { record }), sender)
    end

    -- `n` duels from Brakka (or `sender`), and Wren, a second HeadHunter, saw the newest one:
    -- two witnesses, as a spot we did not see ourselves needs
    local function Spot(ns, mapID, layer, n, players, ago, sender)
        local list = DuelList(ns, n, players, ago)
        Ping(ns, mapID, sender or "Brakka-Firemaw", list, layer)
        Ping(ns, mapID, "Wren-Firemaw", { list[1] }, layer)
    end

    -- Tooltip lines as text; a two-column row is "left | right"
    local function Flat(lines)
        local parts = {}
        for i, line in ipairs(lines) do parts[i] = type(line) == "table" and (line[1] .. " | " .. line[2]) or line end
        return table.concat(parts, "\n")
    end


    local function Seen(ns, winner, loser, winnerLevel, loserLevel)
        ns.Events:Fire("HH_DUEL_SEEN", { winner = winner, loser = loser, t = H.serverTime,
            winnerLevel = winnerLevel or 30, loserLevel = loserLevel or 30 })
    end

    T.case("name hash and duel spot record round trip, long names fit one message", function()
        local P = H.Boot({ client = "forever" }).Protocol
        T.eq(P.NameHash("Tovik Stone"), P.NameHash("tovik stone"), "case does not matter")
        T.eq(#P.NameHash("Tovik Stone"), 4, "4 characters")
        T.ok(P.NameHash("Tovik Stone") ~= P.NameHash("Marla Stone"), "different players differ")
        local duels = {}
        for i = 1, 12 do
            duels[i] = { a = P.NameHash("Longgivenname Longfamilyname" .. i), b = P.NameHash("Otherlongname Familyname" .. i),
                t = H.serverTime - i * 50 }
        end
        local record = P.EncodeDuelSpot(1429, H.serverTime, 0.25, 0.75, 4321, duels)
        local mapID, t, x, y, layer, decoded = P.DecodeDuelSpot(record)
        T.eq(mapID, 1429, "map")
        T.eq(t, H.serverTime, "time")
        T.eq(x, 0.25, "x")
        T.eq(y, 0.75, "y")
        T.eq(layer, 4321, "layer")
        T.eq(#decoded, P.MAX_SPOT_DUELS, "at most 10 duels")
        T.eq(decoded[1].t, H.serverTime - 50, "duel time")
        local messages = P.Pack("A", "Z", { record })
        T.eq(#messages, 1, "one message")
        T.ok(#messages[1] <= P.MAX_MESSAGE, "within 255 bytes")
        local _, _, _, _, noLayer = P.DecodeDuelSpot(P.EncodeDuelSpot(1429, H.serverTime, nil, nil, nil, {}))
        T.eq(noLayer, nil, "no layer")
        T.eq(P.DecodeDuelSpot("a;b"), nil, "malformed")
    end)

    T.case("10 duels between 5 players make a spot; 9 duels or 4 players do not", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        Spot(ns, 1436, 3, 9, 5)
        T.eq(#D:Active(), 0, "9 duels: no spot")
        Spot(ns, 1436, 3, 10, 5)
        local list = D:Active()
        T.eq(#list, 1, "10 duels between 5 players: a spot")
        T.eq(list[1].duels, 10, "the same duels are not counted twice")
        T.eq(list[1].players, 5, "players")
        T.eq(list[1].layer, 3, "layer")
        Spot(ns, 1417, 5, 10, 4, nil, "Zulgar-Firemaw")
        T.eq(#D:Active(), 1, "10 duels between 4 players: no spot")
        T.noErrors()
    end)

    T.case("anti-fake: one HeadHunter alone makes no spot; a second one or our own duel does", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        local list = DuelList(ns, 10, 5)
        Ping(ns, 1436, "Brakka-Firemaw", list, 3)
        T.eq(D:State(1436, 3), 10, "the duels are kept")
        T.eq(#D:Active(), 0, "one HeadHunter alone: no spot")
        Ping(ns, 1436, "Wren-Firemaw", { list[1] }, 3)
        T.eq(#D:Active(), 1, "a second HeadHunter saw duels there: a spot")
        OurLayer(5)
        Ping(ns, 1429, "Iron-Firemaw", DuelList(ns, 10, 5), 5)
        T.eq(#D:Active(), 1, "Elwynn: one HeadHunter alone")
        Seen(ns, "Tovik-Firemaw", "Marla-Firemaw")
        T.eq(#D:Active(), 2, "we saw a duel there ourselves: a spot")
        T.noErrors()
    end)

    T.case("anti-fake: one HeadHunter adds at most 10 new duels in 20 min", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        local P = ns.Protocol
        Ping(ns, 1436, "Brakka-Firemaw", DuelList(ns, 10, 5), 3)
        local more = {}
        for i = 1, 10 do
            more[i] = { a = P.NameHash("Fake" .. i .. "-Firemaw"), b = P.NameHash("Made" .. i .. "-Firemaw"),
                t = H.serverTime - 30 - i * 61 }
        end
        Ping(ns, 1436, "Brakka-Firemaw", more, 3)
        T.eq(D:State(1436, 3), 10, "no more from Brakka")
        Ping(ns, 1436, "Zulgar-Firemaw", more, 3)
        T.eq(D:State(1436, 3), 20, "another HeadHunter can add them")
        H.serverTime = H.serverTime + 1201
        local later = {}
        for i = 1, 3 do
            later[i] = { a = P.NameHash("Late" .. i .. "-Firemaw"), b = P.NameHash("Duel" .. i .. "-Firemaw"), t = H.serverTime - i * 61 }
        end
        Ping(ns, 1436, "Brakka-Firemaw", later, 3)
        T.eq(D:State(1436, 3), 3, "20 min later Brakka can add duels again")
        T.noErrors()
    end)

    T.case("each layer counts alone; two witnesses of the same duels count them once", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        Ping(ns, 1436, "Brakka-Firemaw", DuelList(ns, 6, 5), 3)
        Ping(ns, 1436, "Zulgar-Firemaw", DuelList(ns, 10, 5, 0), 3)
        local duels, players = D:State(1436, 3)
        T.eq(duels, 10, "same duels from two witnesses: once")
        T.eq(players, 5, "players")
        Ping(ns, 1436, "Iron-Firemaw", DuelList(ns, 6, 5), 8)
        T.eq(#D:Active(), 1, "layer 8 has 6 duels: not a spot")
        Spot(ns, 1436, nil, 10, 5, 100, "Iron-Firemaw")
        local list = D:Active()
        T.eq(#list, 1, "duels without a layer never show")
        T.noErrors()
    end)

    T.case("no duel for 3 min: the spot is gone; duels older than 20 min drop out", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        Spot(ns, 1436, 3, 10, 5)
        T.eq(#D:Active(), 1, "spot")
        H.serverTime = H.serverTime + 170
        T.eq(#D:Active(), 1, "the last duel under 3 min ago: still a spot")
        H.serverTime = H.serverTime + 10
        T.eq(#D:Active(), 0, "no duel for 3 min: gone")
        H.serverTime = H.serverTime + 520
        T.eq(D:State(1436, 3), 9, "the oldest duel is over 20 min old")
        T.noErrors()
    end)

    T.case("our own duels count only when both players are level 19 or higher", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        OurLayer(5)
        Seen(ns, "Tovik-Firemaw", "Marla-Firemaw", 30, 18)
        T.eq(D:State(1429, 5), 0, "a level 18 player: not counted")
        Seen(ns, "Tovik-Firemaw", "Marla-Firemaw", 19, 60)
        T.eq(D:State(1429, 5), 1, "both 19+: counted, the level gap does not matter")
        Seen(ns, "Marla-Firemaw", "Tovik-Firemaw", 19, 60)
        T.eq(D:State(1429, 5), 1, "the same pair within a minute: one duel")
        T.noErrors()
    end)

    T.case("duels we saw before our layer was known move to it once it is; heard ones stay", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        Seen(ns, "Tovik-Firemaw", "Marla-Firemaw")
        Ping(ns, 1429, "Brakka-Firemaw", DuelList(ns, 3, 5, 200), nil)
        T.eq(D:State(1429, D.UNKNOWN_LAYER), 4, "layer unknown at first")
        OurLayer(32)
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate9")
        T.eq(D:State(1429, 32), 1, "our duel moved to layer 32")
        T.eq(D:State(1429, D.UNKNOWN_LAYER), 3, "Brakka's stay where Brakka put them")
        T.noErrors()
    end)

    T.case("one duel never makes two marks: a known layer wins over an unknown one", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        local list = DuelList(ns, 10, 5)
        Ping(ns, 1436, "Brakka-Firemaw", list, nil)
        Ping(ns, 1436, "Wren-Firemaw", { list[1] }, nil)
        T.eq(#D:Active(), 0, "only heard without a layer: never shown")
        Ping(ns, 1436, "Zulgar-Firemaw", list, 32)
        Ping(ns, 1436, "Iron-Firemaw", { list[1] }, 32)
        T.eq(D:State(1436, 32), 10, "the duels moved to layer 32")
        T.eq(D:State(1436, D.UNKNOWN_LAYER), 0, "none left without a layer")
        Ping(ns, 1436, "Pell-Firemaw", list, nil)
        T.eq(D:State(1436, D.UNKNOWN_LAYER), 0, "a later copy without a layer is not counted again")
        T.eq(#D:Active(), 1, "one mark, on layer 32")
        local live = 0
        for _, spot in ipairs(D:Active()) do if not spot.remembered then live = live + 1 end end
        T.eq(live, 1, "one live mark, on layer 32")
        T.noErrors()
    end)

    T.case("/hh sim duels waits until our layer is known", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("sim duels")
        T.ok(H.Printed("Your layer is not known yet"), "says so")
        T.eq(#ns.DuelSpots:Active(), 0, "no spot on Layer unknown")
        T.noErrors()
    end)

    T.case("a duel we watch in chat reaches the duel spots, also when it is not fair", function()
        local ns = H.Boot({ client = "era" })
        OurLayer(5)
        H.units.target = { name = "Tovik", level = 40, class = "WARRIOR", race = "Human", faction = "Alliance", isPlayer = true }
        H.units.targettarget = { name = "Marla", level = 20, class = "MAGE", race = "Gnome", faction = "Alliance", isPlayer = true }
        H.Fire("CHAT_MSG_SYSTEM", "Tovik has defeated Marla in a duel")
        T.eq(ns.Duels:Count(), 0, "not on the Duels list (20 levels apart)")
        T.eq(ns.DuelSpots:State(1429, 5), 1, "counted for the duel spot")
        T.noErrors()
    end)

    T.case("our duels go out in a ping with our layer, at most once a minute", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        OurLayer(5)
        Seen(ns, "Tovik-Firemaw", "Marla-Firemaw")
        for _ = 1, 10 do H.Advance(1) end
        local found
        for _, m in ipairs(H.sent) do
            local _, typeCode, records = ns.Protocol.Unpack(m.message)
            if typeCode == "Z" then found = records[1] end
        end
        T.ok(found ~= nil, "a duel spot ping was sent")
        local mapID, _, _, _, layer, duels = ns.Protocol.DecodeDuelSpot(found)
        T.eq(mapID, 1429, "our zone")
        T.eq(layer, 5, "our layer")
        T.eq(#duels, 1, "our duel")
        T.ok(not ns.DuelSpots:Tick(), "no second ping within a minute")
        T.noErrors()
    end)

    T.case("our duels go out again every 3 min for players who reload; others' duels never do", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        OurLayer(5)
        Ping(ns, 1429, "Brakka-Firemaw", DuelList(ns, 4, 5), 5)
        Seen(ns, "Tovik-Firemaw", "Pike-Firemaw")
        for _ = 1, 10 do H.Advance(1) end
        local function SentDuels()
            local found
            for _, m in ipairs(H.sent) do
                local _, typeCode, records = ns.Protocol.Unpack(m.message)
                if typeCode == "Z" then found = records[1] end
            end
            return found and select(6, ns.Protocol.DecodeDuelSpot(found))
        end
        T.eq(#SentDuels(), 1, "only the duel we saw, not Brakka's")
        H.sent = {}
        H.serverTime = H.serverTime + 120
        T.ok(not ns.DuelSpots:Tick(), "nothing new within 3 min")
        H.serverTime = H.serverTime + 61
        T.ok(ns.DuelSpots:Tick(), "after 3 min: sent again")
        H.serverTime = H.serverTime + 1201
        T.ok(not ns.DuelSpots:Tick(), "our duel is over 20 min old: nothing to send")
        T.noErrors()
    end)

    T.case("chat line with whisper links when a spot starts in range, once", function()
        local ns = H.Boot({ client = "era" })
        OurLayer(5)
        Spot(ns, 1436, 3, 10, 5)
        T.ok(H.Printed("Duels in Westfall %(Layer 3%): 10 duels, 5 players in 20 min%."), "chat line")
        T.ok(H.Printed("Ask for an invite: .*|Hplayer:Brakka|h%[Brakka%]|h"), "a click on the name whispers them")
        local lines = #H.printed
        Ping(ns, 1436, "Zulgar-Firemaw", DuelList(ns, 10, 5), 3)
        T.eq(#H.printed, lines, "not repeated")
        T.noErrors()
    end)

    T.case("no chat line out of range, with the option off, or on our own layer", function()
        local ns = H.Boot({ client = "era" })
        OurLayer(5)
        Spot(ns, 1413, 3, 10, 5)
        T.ok(not H.Printed("Duels in"), "The Barrens: out of range")
        ns.Database:SetSetting("alerts.duelSpots", false)
        Spot(ns, 1436, 3, 10, 5)
        T.ok(not H.Printed("Duels in"), "option off")
        ns.Database:SetSetting("alerts.duelSpots", true)
        Spot(ns, 1429, 5, 10, 5)
        T.ok(not H.Printed("Duels in"), "our zone and layer: we can see it")
        T.noErrors()
    end)

    T.case("ask for an invite: the newest HeadHunter on that layer, never the other faction", function()
        local ns = H.Boot({ client = "era" })
        local D = ns.DuelSpots
        OurLayer(5)
        Ping(ns, 1436, "Brakka-Firemaw", DuelList(ns, 10, 5), 3)
        H.serverTime = H.serverTime + 5
        Ping(ns, 1436, "Zulgar-Firemaw", DuelList(ns, 2, 5), 3)
        Ping(ns, 1436, "Iron-Firemaw", DuelList(ns, 2, 5), 7)
        Ping(ns, 1436, "Grunt-Firemaw", DuelList(ns, 2, 5), 3, "H")
        local names = D:Inviters(1436, 3)
        T.eq(#names, 2, "our faction, that layer")
        T.eq(names[1], "Zulgar-Firemaw", "newest first")
        H.chatSent = {}
        local how, target = D:AskInvite(1436, 3)
        T.eq(how, "whispered", "whispered")
        T.eq(target, "Zulgar-Firemaw", "the newest")
        T.eq(H.chatSent[1].chatType, "WHISPER", "whisper")
        T.ok(H.chatSent[1].text:find("duels in Westfall", 1, true) ~= nil, "says why")
        T.ok(H.Printed("Asked Zulgar for a group invite"), "told")
        T.eq(D:AskInvite(1417, 3), nil, "nobody there")
        T.ok(H.Printed("No HeadHunter in Arathi Highlands"), "says so")
        T.noErrors()
    end)

    T.case("ask for an invite on our own layer: no whisper", function()
        local ns = H.Boot({ client = "era" })
        OurLayer(5)
        Ping(ns, 1429, "Brakka-Firemaw", DuelList(ns, 10, 4), 5)
        H.chatSent = {}
        T.eq(ns.DuelSpots:AskInvite(1429, 5), "same", "same layer")
        T.eq(#H.chatSent, 0, "no whisper")
        T.ok(H.Printed("already on this layer"), "told")
        T.noErrors()
    end)

    T.case("map mark: zone, layer, counts, HeadHunters and the click hint", function()
        local ns = H.Boot({ client = "era" })
        OurLayer(5)
        Spot(ns, 1436, 3, 10, 5)
        local pin
        for _, p in ipairs(ns.MapMarkers:PinsFor(1436)) do if p.kind == "duels" then pin = p end end
        T.ok(pin ~= nil, "duel mark on Westfall")
        T.eq(pin.zone, 1436, "zone")
        T.eq(pin.layerKey, 3, "layer")
        local text = Flat(pin.lines)
        T.ok(text:find("Westfall", 1, true) ~= nil, "zone name")
        T.ok(text:find("Layer 3 | 10 duels, 5 players", 1, true) ~= nil, "a row for the layer with its duels")
        T.eq(pin.id, "duels:1436", "one mark for the zone")
        T.ok(text:find("HeadHunters there:", 1, true) ~= nil and text:find("Brakka", 1, true) ~= nil, "who is there")
        T.ok(text:find("Left-click: ask a HeadHunter for a group invite to Layer 3", 1, true) ~= nil, "left click names the layer")
        T.ok(text:find("Right-click: choose the layer", 1, true) ~= nil, "right click hint")
        H.mapRects["1436:1415"] = { 0.3, 0.4, 0.6, 0.8 }
        local onContinent = false
        for _, p in ipairs(ns.MapMarkers:PinsFor(1415)) do if p.kind == "duels" then onContinent = true end end
        T.ok(onContinent, "on the continent map too")
        T.noErrors()
    end)

    T.case("/hh sim duels: our layer and the next two, never sent or whispered", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        OurLayer(5)
        H.Slash("sim duels")
        T.ok(H.Printed("Test duel spots in Elwynn Forest"), "told")
        local list = ns.DuelSpots:Active()
        T.eq(#list, 3, "three spots")
        local layers = {}
        for _, spot in ipairs(list) do layers[spot.layerKey] = spot end
        T.ok(layers[5] ~= nil, "on our layer")
        T.ok(layers[6] ~= nil and layers[7] ~= nil, "on the next two layers")
        T.ok(H.Printed("Duels in Elwynn Forest %(Layer 6%).*Testeight"), "chat line for the other layer")
        local pins = {}
        for _, pin in ipairs(ns.MapMarkers:PinsFor(1429)) do if pin.kind == "duels" then pins[#pins + 1] = pin end end
        T.eq(#pins, 1, "one map mark for the zone")
        local text = Flat(pins[1].lines)
        T.ok(text:find("Layer 5 (your layer) | 12 duels", 1, true) ~= nil, "our layer has a row")
        T.ok(text:find("Layer 6 | 14 duels", 1, true) ~= nil and text:find("Layer 7 | 11 duels", 1, true) ~= nil, "the other layers have rows")
        T.eq(pins[1].layerKey, 6, "a left click asks for the other layer")
        local menu = ns.MapMarkers.DuelMenu(pins[1])
        T.eq(#menu, 2, "the right-click menu lists the two layers we are not on")
        T.ok(menu[1].label:find("Layer 6", 1, true) ~= nil and menu[2].label:find("Layer 7", 1, true) ~= nil, "busiest first")
        menu[1].func()
        T.ok(H.Printed("Test: no whisper sent"), "picking it asks for that layer")
        _G.ToggleDropDownMenu = function() end
        T.eq(ns.Select.ContextMenu(UIParent, "Title", menu), "classic", "the menu opens on Classic")
        H.chatSent = {}
        T.eq(ns.DuelSpots:AskInvite(1429, 6), "sim", "made-up HeadHunter")
        T.eq(#H.chatSent, 0, "no whisper")
        T.ok(H.Printed("Test: no whisper sent"), "the whisper is printed")
        H.serverTime = H.serverTime + 120
        for _ = 1, 10 do H.Advance(1) end
        for _, m in ipairs(H.sent or {}) do
            local _, typeCode = ns.Protocol.Unpack(m.message)
            T.ok(typeCode ~= "Z", "test duels are never sent")
        end
        local lines = #H.printed
        OurLayer(9)
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate9")
        H.Slash("sim duels")
        T.ok(#H.printed > lines + 1, "a second run shows the chat line again")
        T.eq(#ns.DuelSpots:Active(), 3, "the old test spots are replaced, not added to")
        H.Slash("sim duels clear")
        T.ok(H.Printed("Test duel spots removed"), "cleared")
        T.eq(#ns.DuelSpots:Active(), 0, "no spots left")
        T.noErrors()
    end)

    T.case("/hh duelspots lists the spots, or says there are none", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("duelspots")
        T.ok(H.Printed("No duel spots right now"), "none")
        Spot(ns, 1413, 3, 10, 5)
        H.Slash("duelspots")
        T.ok(H.Printed("Duels in The Barrens %(Layer 3%)"), "any range")
        T.noErrors()
    end)
end
