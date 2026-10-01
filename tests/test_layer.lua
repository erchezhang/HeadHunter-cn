-- Layers: detection from NPC GUIDs, reports and posses carry them, popup and whisper.

return function(T, H)
    local function Flow()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    local function NPC(layer)
        return { name = "Defias Thug", faction = "Horde", isPlayer = false,
            guid = "Creature-0-4613-0-" .. layer .. "-116-0000ABCD" }
    end

    T.case("layer from NPC GUIDs", function()
        local L = H.Boot({ client = "era" }).Layer
        T.eq(L.FromGUID("Creature-0-4613-0-1234-567-0000ABCD"), 1234, "zoneUID")
        T.eq(L.FromGUID("Creature-0-4613-88-0-567-0000ABCD"), 88, "zoneUID 0 falls back to instance")
        T.eq(L.FromGUID("GameObject-0-4613-0-55-1-2"), 55, "objects too")
        T.eq(L.FromGUID("Player-4613-00BE1F94"), nil, "players carry no layer")
        T.eq(L.FromGUID("Pet-0-4613-0-55-1-2"), nil, "pets ignored")
        T.eq(L.FromGUID("garbage"), nil, "junk")
        T.eq(L.FromGUID(nil), nil, "nil")
        _G.canaccessvalue = function() return false end
        T.eq(L.FromGUID("Creature-0-4613-0-1234-567-0000ABCD"), nil, "secret value")
        _G.canaccessvalue = nil
    end)

    T.case("current layer: from nameplates, stale after 60 s, cleared on zone change, rescanned", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.Layer:Current(), nil, "unknown at first")
        H.units.nameplate1 = NPC(777)
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        T.eq(ns.Layer:Current(), 777, "read from the NPC nameplate")
        H.units.nameplate1 = nil
        H.clock = H.clock + 61
        T.eq(ns.Layer:Current(), nil, "stale and nothing to rescan")
        H.units.target = NPC(778)
        T.eq(ns.Layer:Current(), 778, "rescanned from the target")
        H.Fire("ZONE_CHANGED_NEW_AREA")
        H.units.target = nil
        T.eq(ns.Layer:Current(), nil, "cleared on zone change")
        H.units.mouseover = NPC(9)
        H.Slash("layer")
        T.ok(H.Printed("Your layer: 9"), "/hh layer")
        T.noErrors()
    end)

    T.case("death reports and posse joins carry the layer over the wire", function()
        local ns = H.Boot({ client = "era" })
        H.units.target = NPC(321)
        local report = ns.DeathReports:Record({ killer = { key = "Gank-Stonespine", level = 60 }, confidence = "exact" }, "test")
        T.eq(report.layer, 321, "recorded at death")
        local decoded = ns.Protocol.DecodeDeath(ns.Protocol.EncodeDeath(report))
        T.eq(decoded.layer, 321, "round trip")
        local _, _, _, layer = ns.Protocol.DecodePosse(ns.Protocol.EncodePosse("Gank-Stonespine", 1429, H.serverTime, 321))
        T.eq(layer, 321, "posse round trip")
    end)

    -- A (layer 777) sends 3 simulated deaths; B is in the same zone on `bLayer`
    local function Scenario(bLayer, whisper)
        H.Boot({ client = "era" })
        H.units.target = NPC(777)
        H.Slash("debug on")
        H.Slash("sim send Gank 3")
        local text = H.chatSent[1].text

        local nsB = H.Boot({ client = "era", dev = { trust = { "Vati-Firemaw" } } })
        H.units.player.name = "Headhunta"
        H.units.target = NPC(bLayer)
        if whisper == false then H.Slash("alerts whisper off") end
        H.Slash("debug wanted 3")
        H.Fire("CHAT_MSG_CHANNEL", text, "Vati-Firemaw", "", "5. HeadHunterSync", "", "", 0, 5, "HeadHunterSync")
        Flow()
        Flow()
        return nsB, _G.StaticPopupDialogs.HEADHUNTER_ALERT
    end

    T.case("same layer: the popup says so and Join sends no whisper", function()
        local _, dialog = Scenario(777)
        T.ok(dialog.text:find("Same layer as you", 1, true) ~= nil, "same layer shown")
        local before = #H.chatSent
        dialog.OnAccept()
        T.eq(#H.chatSent - before, 1, "only the posse channel text, no whisper")
        T.eq(H.chatSent[#H.chatSent].chatType, "CHANNEL", "posse broadcast")
    end)

    T.case("different layer: the popup says so and Join whispers the victim for an invite", function()
        local nsB, dialog = Scenario(900)
        T.ok(dialog.text:find("Different layer", 1, true) and dialog.text:find("you 900, kill on 777", 1, true),
            "different layer shown")
        dialog.OnAccept()
        local whisper
        for _, line in ipairs(H.chatSent) do
            if line.chatType == "WHISPER" then whisper = line end
        end
        T.ok(whisper ~= nil, "whisper sent")
        T.eq(whisper.target, "Vati-Firemaw", "to the victim, as the game named them")
        T.ok(whisper.text:find("invite", 1, true) ~= nil, "asks for an invite")
        T.ok(H.Printed("Asked Vati for a group invite"), "confirmation")
        T.eq(nsB.Posse:Members("Gank-Firemaw")[1].layer, 900, "our layer stored in the posse")
        T.noErrors()
    end)

    T.case("the invite whisper waits for the victim's second death within 15 minutes", function()
        local ns = H.Boot({ client = "era" })
        local function Report(id, t)
            return { id = id, t = t, victim = { key = "Tessa-Firemaw", level = 30 },
                killer = { key = "Gank-Firemaw", name = "Gank-Firemaw", level = 40 }, assists = {},
                mapID = 1429, confidence = "exact" }
        end
        local first = Report("Tessa-Firemaw:1", H.serverTime - 1200)
        ns.Reports:Add(first, "peer", "Tessa-Firemaw")
        T.ok(not ns.Posse.DiedAgain(first), "one death: no whisper")
        ns.Reports:Add(Report("Tessa-Firemaw:2", H.serverTime - 1200 - ns.Posse.WHISPER_REPEAT - 60), "peer", "Tessa-Firemaw")
        T.ok(not ns.Posse.DiedAgain(first), "a death longer ago does not count")
        ns.Reports:Add(Report("Tessa-Firemaw:3", H.serverTime - 600), "peer", "Tessa-Firemaw")
        T.ok(ns.Posse.DiedAgain(first), "died again within 15 minutes: whisper")
        T.noErrors()
    end)

    T.case("the invite whisper can be turned off", function()
        local _, dialog = Scenario(900, false)
        dialog.OnAccept()
        for _, line in ipairs(H.chatSent) do
            T.ok(line.chatType ~= "WHISPER", "no whisper")
        end
    end)

    T.case("/hh posse shows each member's layer", function()
        local ns = H.Boot({ client = "era" })
        local record = ns.Protocol.EncodePosse("Gank-Stonespine", 1429, H.serverTime - 5, 777)
        H.Deliver(ns.Protocol.Pack("A", "J", { record }), "Alpha-Firemaw")
        H.Slash("posse")
        T.ok(H.Printed("Alpha  Elwynn Forest  layer 777"), "member line")
    end)
end
