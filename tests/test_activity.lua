-- HH-040 zones and HH-043 WANTED activity popup.

return function(T, H)
    -- WANTED activity popups only (hotspots use their own dialog)
    local function WantedPopups()
        local n = 0
        for _, p in ipairs(H.popups) do
            if p.which == "HEADHUNTER_ALERT" then n = n + 1 end
        end
        return n
    end

    -- Report added + WANTED recompute (1 s) + activity check (1.5 s)
    local function Flow()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    -- A peer report of Gank killing someone, `ago` seconds ago, on mapID
    local serial = 0
    local function Kill(ns, mapID, ago, victim)
        serial = serial + 1
        local t = H.serverTime - (ago or 30)
        victim = victim or ("Victim" .. serial .. "-Firemaw")
        return ns.Reports:Add({
            id = victim .. ":" .. t, t = t,
            victim = { key = victim, level = 30 },
            killer = { key = "Gank-Stonespine", name = "Gank-Stonespine", level = 60, class = "ROGUE", race = "Orc" },
            assists = {}, mapID = mapID, x = 0.5, y = 0.25, confidence = "exact",
        }, "peer", victim)
    end

    -- Gank becomes WANTED with 5 kills; the newest one on mapID
    local function WantedSpree(ns, mapID, ago)
        for i = 1, 4 do Kill(ns, 1429, 600 + i * 30) end
        Kill(ns, mapID, ago or 30)
        Flow()
    end

    -------------------------------------------------
    -- Zones (HH-040)
    -------------------------------------------------

    T.case("neighbor table is symmetric and only uses known zones", function()
        local Z = H.Boot({ client = "era" }).Zones
        for a, list in pairs(Z.NEIGHBORS) do
            T.ok(Z.CONTINENT[a] ~= nil, "known zone " .. a)
            for b in pairs(list) do
                T.ok(Z.NEIGHBORS[b][a], "symmetric " .. a .. "-" .. b)
                T.eq(Z.CONTINENT[a], Z.CONTINENT[b], "same continent " .. a .. "-" .. b)
            end
        end
    end)

    T.case("distance and range", function()
        local ns = H.Boot({ client = "era" })
        local Z = ns.Zones
        T.eq(Z.Distance(1429, 1429), "zone", "same zone")
        T.eq(Z.Distance(9001, 1429), "zone", "a mine inside Elwynn counts as Elwynn")
        T.eq(Z.Distance(1436, 1429), "adjacent", "Westfall borders Elwynn")
        T.eq(Z.Distance(1434, 1429), "continent", "Stranglethorn does not border Elwynn")
        T.eq(Z.Distance(1413, 1429), nil, "other continent")
        T.eq(Z.Distance(nil, 1429), nil, "unknown map")
        T.eq(Z.InRange(1436, 1429), true, "adjacent in default range")
        T.eq(Z.InRange(1434, 1429), false, "continent outside default range")
        H.Slash("alerts range continent")
        T.eq(Z.InRange(1434, 1429), true, "continent range")
        T.eq(Z.InRange(1413, 1429), false, "never another continent")
        T.noErrors()
    end)

    -------------------------------------------------
    -- Activity popup (HH-043)
    -------------------------------------------------

    T.case("a WANTED outlaw kills next door: popup with Join the posse / Decline", function()
        local ns = H.Boot({ client = "era" })
        local joined, declined
        ns.Events:Register("HH_POSSE_JOINED", function(_, entry) joined = entry.key end, "t")
        ns.Events:Register("HH_POSSE_DECLINED", function(_, entry) declined = entry.key end, "t")
        WantedSpree(ns, 1436)
        local popups = 0
        for _, p in ipairs(H.popups) do
            if p.which == "HEADHUNTER_ALERT" then popups = popups + 1 end
        end
        T.eq(popups, 1, "one popup for the whole spree")
        local dialog = _G.StaticPopupDialogs.HEADHUNTER_ALERT
        T.ok(dialog.text:find("Gank%-Stonespine") and dialog.text:find("Westfall"), "who and where")
        T.ok(dialog.text:find("Bully") ~= nil, "badges")
        T.eq(dialog.button1, "Join the posse", "accept label")
        T.eq(dialog.button2, "Decline", "decline label")
        T.ok(H.centerTexts[#H.centerTexts]:find("is killing in Westfall") ~= nil, "center text")

        dialog.OnAccept()
        T.eq(joined, "Gank-Stonespine", "HH_POSSE_JOINED")
        T.eq(H.waypoints[1].uiMapID, 1436, "waypoint on the kill's map")
        T.eq(H.waypoints[1].x, 0.5, "waypoint x")
        T.ok(H.Printed("Waypoint set in Westfall"), "confirmation")
        dialog.OnCancel()
        T.eq(declined, "Gank-Stonespine", "HH_POSSE_DECLINED")
        T.noErrors()
    end)

    T.case("farther on the same continent: one chat line, no popup", function()
        local ns = H.Boot({ client = "era" })
        WantedSpree(ns, 1434)
        T.eq(WantedPopups(), 0, "no popup")
        T.eq(#H.centerTexts, 0, "no center text")
        T.ok(H.Printed("killed .* in Stranglethorn Vale"), "chat line")
    end)

    T.case("continent range turns the far kill into a popup", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("alerts range continent")
        WantedSpree(ns, 1434)
        T.eq(WantedPopups(), 1, "popup")
    end)

    T.case("another continent: nothing at all", function()
        local ns = H.Boot({ client = "era" })
        H.printed = {}
        WantedSpree(ns, 1413)
        T.eq(WantedPopups(), 0, "no popup")
        T.ok(not H.Printed("killed"), "no chat line")
    end)

    T.case("stale kills, our own death and non-WANTED killers raise nothing", function()
        local ns = H.Boot({ client = "era" })
        -- Not WANTED yet (2 kills)
        Kill(ns, 1429, 30)
        Kill(ns, 1429, 40)
        Flow()
        T.eq(WantedPopups(), 0, "not wanted")
        -- WANTED, but the newest kill is 11 minutes old
        Kill(ns, 1429, 660)
        Kill(ns, 1429, 670)
        Flow()
        T.eq(WantedPopups(), 0, "stale")
        -- Fresh kill, but we are the victim
        Kill(ns, 1429, 5, "Vati-Firemaw")
        Flow()
        T.eq(WantedPopups(), 0, "our own death")
    end)

    T.case("in combat the popup waits for combat to end", function()
        local ns = H.Boot({ client = "era" })
        H.inCombat = true
        WantedSpree(ns, 1429)
        T.eq(WantedPopups(), 0, "waits")
        H.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        T.eq(WantedPopups(), 1, "shown after combat")
    end)

    T.case("/hh sim send: optional values in any order, a zone name places the deaths there", function()
        local ns = H.Boot({ client = "era" })
        local S = ns.Simulator
        local o = S.SendOptions({ "Gank", "5", "22", "Westfall" })
        T.eq(o.level, 22, "level")
        T.eq(o.mapID, 1436, "zone by name")
        o = S.SendOptions({ "Gank", "5", "westf", "MAGE", "skull", "Gnome" })
        T.eq(o.mapID, 1436, "a unique start of the name")
        T.eq(o.class, "MAGE", "class")
        T.eq(o.level, -1, "skull")
        T.eq(o.race, "Gnome", "anything else is the race")
        T.eq(ns.Zones.FindByName("Nowhere Land"), nil, "unknown zone")

        H.Slash("debug on")
        H.Slash('sim send Gank 2 22 "Westfall"')
        T.ok(H.Printed("Sent 2 simulated death%(s%) by Gank in Westfall"), "says where")
        for _, report in ns.Reports:All() do
            T.eq(report.mapID, 1436, "placed in Westfall")
            T.eq(report.x, 0.5, "the middle of the zone")
            T.eq(report.layer, nil, "no layer outside our zone")
        end
        T.noErrors()
    end)

    T.case("/hh sim clear removes simulated deaths and test catches, real ones stay", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("debug on")
        H.Slash("spree Gank 5 60")
        H.Slash('sim death "Stab" 60 ROGUE Orc')
        ns.Reports:Add({ id = "Real-Firemaw:1", t = H.serverTime - 60, victim = { key = "Real-Firemaw", level = 30 },
            killer = { key = "Brute-Stonespine", level = 32, class = "WARRIOR", race = "Orc" },
            assists = {}, mapID = 1429, confidence = "exact" }, "peer", "Real-Firemaw")
        Flow()
        T.eq(ns.Wanted:ByKey("Gank-Firemaw").wanted, true, "precondition: the spree made Gank WANTED")
        H.Slash("catch Gank")
        Flow()

        H.Slash("sim clear")
        Flow()
        T.ok(H.Printed("Test data removed: 6 simulated report%(s%), 1 of your simulated death%(s%), 1 test catch"),
            "says what went")
        T.eq(ns.Wanted:ByKey("Gank-Firemaw"), nil, "the simulated outlaw is gone")
        T.eq(#ns.Wanted:AtLarge(), 0, "not at large either")
        T.ok(ns.Reports:Get("Real-Firemaw:1") ~= nil, "a real report stays")
        T.eq(#ns.db.deaths, 0, "no simulated death left in My deaths")
        T.noErrors()
    end)

    T.case("/hh sim send: A's simulated deaths reach B, who gets the WANTED popup", function()
        -- Character A (Era) sends 3 simulated deaths
        local nsA = H.Boot({ client = "era" })
        H.Slash("sim send Gank 3")
        T.ok(H.Printed("debug tool"), "refused without debug mode")
        T.eq(#H.chatSent, 0, "nothing sent")
        H.Slash("debug on")
        H.Slash("sim send Gank 3 60 ROGUE Orc")
        T.ok(H.Printed("Sent 3 simulated death"), "sent")
        T.eq(#H.chatSent, 1, "realm-wide channel text from the typed command")
        T.eq(WantedPopups(), 0, "A gets no popup about its own deaths")
        local text = H.chatSent[1].text

        -- Character B receives them
        local nsB = H.Boot({ client = "era", dev = { trust = { "Vati-Firemaw" } } })
        H.units.player.name = "Headhunta"
        H.Slash("debug wanted 3")
        H.Fire("CHAT_MSG_CHANNEL", text, "Vati-Firemaw", "", "5. HeadHunterSync", "", "", 0, 5, "HeadHunterSync")
        -- The recompute requested by "debug wanted 3" runs first; the reports trigger a second one
        Flow()
        Flow()
        local _, _, peers = nsB.Reports:Count()
        T.eq(peers, 3, "B stored 3 peer reports")
        local entry = nsB.Wanted:ByKey("Gank-Firemaw")
        T.eq(entry and entry.wanted, true, "WANTED on B")
        T.eq(entry.exactKills, 3, "sim kills count fully")
        T.eq(WantedPopups(), 1, "B gets the popup")
        T.ok(_G.StaticPopupDialogs.HEADHUNTER_ALERT.text:find("killed Vati in Elwynn Forest", 1, true) ~= nil,
            "names A and the zone")
        T.noErrors()
    end)

    T.case("a batch of reports alerts once, about the newest kill", function()
        local ns = H.Boot({ client = "era" })
        for i = 9, 0, -1 do Kill(ns, 1429, i * 60 + 5) end -- 9 min ago ... just now, arriving together
        Flow()
        T.eq(WantedPopups(), 1, "one popup")
        T.ok(_G.StaticPopupDialogs.HEADHUNTER_ALERT.text:find("just now", 1, true) ~= nil, "about the newest kill")
        -- 5 deaths in 5 min in our zone reach Battle heat, but all by one WANTED
        -- outlaw: the hotspot is only a chat line (author, 2026-09-23)
        local hotspot = false
        for _, p in ipairs(H.popups) do
            if p.which == "HEADHUNTER_HOTSPOT" then hotspot = true end
        end
        T.eq(hotspot, false, "no Battle popup for a lone outlaw")
        T.ok(H.Printed("Battle.*Elwynn Forest"), "Battle chat line")
    end)

    T.case("a spree simulated with /hh spree triggers the popup too", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("spree Gank 5 60")
        Flow()
        T.eq(WantedPopups(), 1, "popup for simulated reports")
        T.noErrors()
    end)
end
