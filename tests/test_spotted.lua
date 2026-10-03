-- A watched outlaw spotted (Alerts/Spotted.lua): the first spotter tells the HeadHunters
-- nearby where, and nobody floods the chat. Made-up players only.

return function(T, H)
    local serial = 0

    -- `killer` kills n distinct victims in the last few minutes (peer reports): WANTED
    local function Spree(ns, killer, n)
        for i = 1, n do
            serial = serial + 1
            local victim = "Victim" .. serial .. "-Firemaw"
            local t = H.serverTime - (n - i + 1) * 30
            ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = 30 },
                killer = { key = killer, name = killer, level = 60, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = 1436, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
        end
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
    end

    local function Boot()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        H.playerMap, H.playerX, H.playerY = 1436, 0.45, 0.6 -- Westfall
        Spree(ns, "Gank-Stonespine", 5)
        Spree(ns, "Other-Stonespine", 5)
        Spree(ns, "Third-Stonespine", 5)
        Spree(ns, "Fourth-Stonespine", 5)
        Settle()
        return ns
    end

    local function Sent(outlaw)
        local found = 0
        for _, m in ipairs(H.sent) do
            if m.message:find("^1AL:" .. outlaw:gsub("%-", "%%-") .. ";") then found = found + 1 end
        end
        return found
    end

    local function Spot(ns, outlaw, mapID, sender, ago)
        H.Deliver(ns.Protocol.Pack("A", "L", {
            ns.Protocol.EncodeSpotted(outlaw, mapID or 1436, H.serverTime - (ago or 0), 0.3, 0.7) }), sender or "Scout-Firemaw")
    end

    local function Seen(ns, outlaw)
        ns.Sighting:OnEnemySeen({ key = outlaw, level = 60, class = "ROGUE", race = "Orc" }, "target")
    end

    T.case("seeing a WANTED outlaw tells the guild where, once", function()
        local ns = Boot()
        Seen(ns, "Gank-Stonespine")
        for _ = 1, 5 do H.Advance(1) end
        T.eq(Sent("Gank-Stonespine"), 1, "spotted sent")
        H.Advance(120)
        Seen(ns, "Gank-Stonespine")
        for _ = 1, 5 do H.Advance(1) end
        T.eq(Sent("Gank-Stonespine"), 1, "not again within 5 minutes")
        T.noErrors()
    end)

    T.case("the first spotter speaks for everyone", function()
        local ns = Boot()
        Seen(ns, "Gank-Stonespine")
        Spot(ns, "Gank-Stonespine") -- another HeadHunter was quicker
        for _ = 1, 5 do H.Advance(1) end
        T.eq(Sent("Gank-Stonespine"), 0, "we keep quiet")
        T.noErrors()
    end)

    T.case("others nearby get one line, with where, when and who, and a link to whisper the spotter", function()
        local ns = Boot()
        Spot(ns, "Gank-Stonespine", 1436, "Scout-Firemaw", 60)
        T.ok(H.Printed("SPOTTED.*Gank.*in Westfall %(30%.0, 70%.0%), 1 min ago, by |cffff7fff|Hplayer:Scout|h%[Scout%]|h|r"), "the line")
        H.printed = {}
        H.Advance(400)
        Spot(ns, "Gank-Stonespine", 1436, "Other-Firemaw")
        T.ok(not H.Printed("SPOTTED"), "same zone: not again within 15 minutes")
        Spot(ns, "Gank-Stonespine", 1429, "Other-Firemaw")
        T.ok(H.Printed("SPOTTED.*Gank.*Elwynn"), "a new zone after 5 minutes: told")
        T.noErrors()
    end)

    T.case("no line when we saw him ourselves, far away, or not watched; at most 3 a minute", function()
        local ns = Boot()
        Seen(ns, "Gank-Stonespine")
        H.printed = {}
        Spot(ns, "Gank-Stonespine")
        T.ok(not H.Printed("SPOTTED"), "we saw him ourselves")
        Spot(ns, "Nobody-Stonespine")
        T.ok(not H.Printed("SPOTTED"), "not WANTED")
        Spot(ns, "Other-Stonespine", 1446) -- Tanaris, another continent: out of the "adjacent" range
        T.ok(not H.Printed("SPOTTED"), "too far")
        for _, outlaw in ipairs({ "Other-Stonespine", "Third-Stonespine", "Fourth-Stonespine" }) do
            Spot(ns, outlaw, 1436, "Scout" .. outlaw)
        end
        local lines = 0
        for _, line in ipairs(H.printed) do
            if line:find("SPOTTED") then lines = lines + 1 end
        end
        T.ok(lines <= 3, "at most 3 a minute: " .. lines)
        T.noErrors()
    end)

    T.case("sightings are remembered: ours and the peers', the last 10, at most 10 per sender in 10 minutes", function()
        local ns = Boot()
        Seen(ns, "Gank-Stonespine")
        local mine = ns.Spotted:Latest("Gank-Stonespine")
        T.eq(mine.by, "Vati-Firemaw", "our own sighting")
        T.eq(mine.mapID, 1436, "where we were")
        Spot(ns, "Gank-Stonespine", 1429, "Scout-Firemaw", 30)
        T.eq(#ns.Spotted:Sightings("Gank-Stonespine"), 2, "and a peer's")
        T.eq(ns.Spotted:Latest("Gank-Stonespine").by, "Vati-Firemaw", "the newest is last")
        Spot(ns, "Gank-Stonespine", 1429, "Copy-Firemaw", 30)
        T.eq(#ns.Spotted:Sightings("Gank-Stonespine"), 2, "the same sighting again is kept once")

        for i = 1, 12 do Spot(ns, "Other-Stonespine", 1436, "Flood-Firemaw", 100 + i) end
        T.eq(#ns.Spotted:Sightings("Other-Stonespine"), 10, "one sender: at most 10 in 10 minutes")
        for i = 1, 5 do Spot(ns, "Other-Stonespine", 1436, "Scout" .. i .. "-Firemaw", i) end
        local list = ns.Spotted:Sightings("Other-Stonespine")
        T.eq(#list, 10, "the last 10 kept")
        T.eq(list[#list].t, H.serverTime - 1, "newest last")
        T.noErrors()
    end)

    T.case("a posse member hears a sighting from the posse, and the map skull moves there", function()
        local ns = Boot()
        local entry = ns.Wanted:ByKey("Gank-Stonespine")
        ns.Posse:Join(entry, { mapID = 1436, x = 0.5, y = 0.5 })
        H.printed = {}
        Spot(ns, "Gank-Stonespine", 1436, "Scout-Firemaw", 10)
        T.ok(H.Printed("Posse: .*Gank.* seen in Westfall by Scout%. The waypoint moved there%."), "the posse line")
        T.ok(not H.Printed("SPOTTED"), "not the general line as well")

        local skull
        for _, pin in ipairs(ns.MapMarkers:PinsFor(1436, H.serverTime)) do
            if pin.id == "wanted:Gank-Stonespine" then skull = pin end
        end
        T.ok(skull ~= nil, "a skull")
        T.ok(table.concat(skull.lines, " "):find("Seen just now in Westfall", 1, true) ~= nil,
            "at the sighting, newer than the last kill")
        T.noErrors()
    end)

    T.case("the spotted record round trip", function()
        local ns = H.Boot({ client = "era" })
        local P = ns.Protocol
        local outlaw, mapID, t, x, y = P.DecodeSpotted(P.EncodeSpotted("guid:Player-1-00ABCDEF", 1436, 1790000000, 0.451, 0.6))
        T.eq(outlaw, "guid:Player-1-00ABCDEF", "outlaw")
        T.eq(mapID, 1436, "map")
        T.eq(t, 1790000000, "time")
        T.eq(x, 0.451, "x")
        T.eq(y, 0.6, "y")
        T.eq(P.DecodeSpotted("broken"), nil, "broken record")
    end)
end
