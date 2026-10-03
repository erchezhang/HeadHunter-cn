-- HH-111 names and help in Battle alerts, HH-112 whisper from the Duels list.
-- Made-up players only.

return function(T, H)
    local function Ids(from, to)
        local ids = {}
        for i = from, to do ids[#ids + 1] = string.format("E%07d", i) end
        return ids
    end

    local function Ping(ns, mapID, sender, ids, enemies, layer)
        local record = ns.Protocol.EncodeHotspot(mapID, H.serverTime - 5, 0.4, 0.6, ids, enemies, layer)
        H.Deliver(ns.Protocol.Pack("A", "P", { record }), sender)
    end

    local function HotspotPopup()
        for _, p in ipairs(H.popups) do
            if p.which == "HEADHUNTER_HOTSPOT" then return p end
        end
    end

    local function OurLayer(layer)
        H.units.nameplate9 = { name = "Defias Thug", faction = "Horde", isPlayer = false,
            guid = "Creature-0-4613-0-" .. layer .. "-116-0000ABCD" }
    end

    T.case("the ping carries enemy names and our layer; old pings still decode", function()
        local P = H.Boot({ client = "era" }).Protocol
        local record = P.EncodeHotspot(1436, 1790000000, 0.25, 0.75, { "AB12CD34" },
            { { name = "Grimtusk", class = "ROGUE", level = 34 }, { name = "Dusk;Blade", class = "MAGE", level = -1 },
              { name = "Skarn" }, { name = "Fourth" } }, 7)
        local mapID, _, _, _, ids, enemies, layer = P.DecodeHotspot(record)
        T.eq(mapID, 1436, "map")
        T.eq(#ids, 1, "ids")
        T.eq(#enemies, 3, "at most three names")
        T.eq(enemies[1].name, "Grimtusk", "name")
        T.eq(enemies[1].class, "ROGUE", "class")
        T.eq(enemies[1].level, 34, "level")
        T.eq(enemies[2].name, "DuskBlade", "separators taken out")
        T.eq(enemies[2].level, -1, "skull")
        T.eq(enemies[3].level, nil, "unknown level")
        T.eq(layer, 7, "layer")

        local old = P.EncodeHotspot(1436, 1790000000, 0.25, 0.75, { "AB12CD34" })
        local _, _, _, _, oldIds, oldEnemies, oldLayer = P.DecodeHotspot(old)
        T.eq(#oldIds, 1, "an old ping still decodes")
        T.eq(#oldEnemies, 0, "without names")
        T.eq(oldLayer, nil, "and without a layer")
    end)

    T.case("the Battle popup and chat line name the enemies", function()
        local ns = H.Boot({ client = "era" })
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 10), { { name = "Grimtusk", class = "ROGUE", level = 34 } })
        local popup = HotspotPopup()
        T.ok(popup ~= nil, "Battle popup")
        T.ok(popup.text:find("Enemies: Grimtusk (34 Rogue)", 1, true) ~= nil, "names in the popup: " .. popup.text)
        T.ok(H.Printed("Enemies: Grimtusk"), "names in chat")
        T.noErrors()
    end)

    T.case("our own ping sends the names of the enemies we fight", function()
        H.Boot({ client = "forever" })
        H.inCombat = true
        H.units.nameplate1 = { name = "Grim", realm = "Reaper", level = 60, class = "ROGUE", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-4613-00ABCDEF" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.Advance(5)
        H.Advance(3)
        local ping
        for _, m in ipairs(H.sent) do if m.message:find("^1AP:") then ping = m end end
        T.ok(ping and ping.message:find("Grim Reaper/R/60", 1, true) ~= nil, "name, class and level in the ping")
        T.noErrors()
    end)

    T.case("Help sends a quiet help note, never chat", function()
        -- Forever: the channel reaches everyone (on Era the note goes to guild and group)
        local ns = H.Boot({ client = "forever" })
        Ping(ns, 1436, "Alpha Hunter", Ids(1, 10))
        _G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.OnAccept()
        H.Advance(3)
        local note
        for _, m in ipairs(H.sent) do if m.message:find("^1AB:") then note = m end end
        T.ok(note ~= nil, "help note sent as an addon message")
        T.eq(#H.chatSent, 0, "no chat")
        T.noErrors()
    end)

    T.case("players fighting there see who is coming; others do not", function()
        local ns = H.Boot({ client = "era" })
        local U = ns.Utils
        local help = ns.Protocol.Pack("A", "B", { ns.Protocol.EncodeHelp(1436, H.serverTime) })
        H.Deliver(help, "Iron-Firemaw")
        T.ok(not H.Printed("is coming to the fight"), "not fighting there: nothing")

        ns.Hotspots:AddFighter(1436, U.CompactName(U.UnitKey("player")), H.serverTime, 0.4, 0.6, {})
        H.Deliver(help, "Iron-Firemaw")
        T.ok(H.Printed("|cffff7fff|Hplayer:Iron|h%[Iron%]|h|r is coming to the fight in Westfall"), "fighting there: told, a click whispers them")
        H.printed = {}
        H.Deliver(help, "Iron-Firemaw")
        T.ok(not H.Printed("is coming to the fight"), "once a minute per helper")
        T.noErrors()
    end)

    T.case("Help whispers one fighter for an invite only when on another layer", function()
        local ns = H.Boot({ client = "era" })
        OurLayer(7)
        Ping(ns, 1429, "Alpha-Firemaw", Ids(1, 10), nil, 9)
        _G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.OnAccept()
        T.eq(#H.chatSent, 1, "one whisper")
        T.eq(H.chatSent[1].chatType, "WHISPER", "whisper")
        T.eq(H.chatSent[1].target, "Alpha-Firemaw", "to the fighter")
        T.ok(H.chatSent[1].text:find("invite", 1, true) ~= nil, "asks for an invite")

        local ns2 = H.Boot({ client = "era" })
        OurLayer(9)
        Ping(ns2, 1429, "Alpha-Firemaw", Ids(1, 10), nil, 9)
        _G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.OnAccept()
        T.eq(#H.chatSent, 0, "same layer: no whisper")

        local ns3 = H.Boot({ client = "era" })
        OurLayer(7)
        ns3.db.settings.alerts.whisperInvite = false
        Ping(ns3, 1429, "Alpha-Firemaw", Ids(1, 10), nil, 9)
        _G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.OnAccept()
        T.eq(#H.chatSent, 0, "whisper setting off: no whisper")
        T.noErrors()
    end)

    T.case("the Duels list whispers players of our own faction", function()
        local ns = H.Boot({ client = "era" })
        local told
        _G.ChatFrame_SendTell = function(name) told = name end
        local function Duel(winner, loser, faction)
            ns.Duels:Add({ winner = winner, loser = loser, t = H.serverTime - 600, faction = faction,
                winnerLevel = 30, loserLevel = 30 }, "local")
        end
        Duel("Ironmaple-Firemaw", "Fernwick-Gehennas", "Alliance")
        Duel("Grimtusk-Firemaw", "Skarn-Firemaw", "Horde")
        H.Advance(1)
        H.Slash("")
        ns.MainWindow:SelectTab("duels")
        local rows = ns.MainWindow.shownRows
        local maple, fern
        for _, row in ipairs(rows) do
            if row.whisper == "Ironmaple-Firemaw" then maple = row end
            if row.whisper == "Fernwick-Gehennas" then fern = row end
        end
        T.ok(maple ~= nil, "our faction: whisper")
        T.ok(fern ~= nil, "another realm too")
        T.ok(maple.tooltip[#maple.tooltip]:find("whisper", 1, true) ~= nil, "the tooltip says so")
        ns.MainWindow:OnRowClick(maple)
        T.eq(told, "Ironmaple", "whisper opened, our realm dropped")
        ns.MainWindow:OnRowClick(fern)
        T.eq(told, "Fernwick-Gehennas", "another realm keeps it")

        ns.MainWindow:SetFaction("Horde")
        for _, row in ipairs(ns.MainWindow.shownRows) do
            T.eq(row.whisper, nil, "the other faction cannot be whispered")
        end
        _G.ChatFrame_SendTell = nil
        T.noErrors()
    end)
end
