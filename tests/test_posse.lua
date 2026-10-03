-- HH-044: posse join broadcast, member lists, popup summary.

return function(T, H)
    local function Flow()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    -- Make an outlaw WANTED with a fresh kill in the player's zone and open its popup
    local function WantedPopup(ns, name)
        H.Slash("spree " .. name .. " 5 60")
        Flow()
        return _G.StaticPopupDialogs.HEADHUNTER_ALERT
    end

    local function JoinMessage(ns, outlawId, ago)
        local record = ns.Protocol.EncodePosse(outlawId, 1429, H.serverTime - (ago or 10))
        return ns.Protocol.Pack("A", "J", { record })
    end

    T.case("posse record round trip", function()
        local P = H.Boot({ client = "forever" }).Protocol
        local id, mapID, t = P.DecodePosse(P.EncodePosse("Grim Reaper", 1434, 1790000000))
        T.eq(id, "Grim Reaper", "outlaw id with a space")
        T.eq(mapID, 1434, "map")
        T.eq(t, 1790000000, "time")
        id = P.DecodePosse(P.EncodePosse("guid:Player-7", nil, 1790000000))
        T.eq(id, "guid:Player-7", "GUID id")
        T.eq(P.DecodePosse("x;;"), nil, "no time")
        T.eq(P.DecodePosse(";5;7"), nil, "no outlaw")
    end)

    T.case("forever: Join adds us and sends a posse message on the channel", function()
        local ns = H.Boot({ client = "forever" })
        local dialog = WantedPopup(ns, '"Grim Reaper"')
        dialog.OnAccept()
        T.eq(ns.Posse:IsMember("Grim Reaper"), true, "member")
        T.eq(ns.Posse:Summary("Grim Reaper"), "Posse: you", "summary")
        H.Advance(3)
        local found
        for _, m in ipairs(H.sent) do
            if m.message:find("^1AJ:Grim Reaper;") then found = m end
        end
        T.ok(found ~= nil, "J message sent")
        T.eq(found.chatType, "CHANNEL", "on the channel")
        T.eq(#H.chatSent, 0, "no channel text on Forever")
        T.noErrors()
    end)

    T.case("era: Join sends realm-wide channel text in the click, and guild when in one", function()
        local ns = H.Boot({ client = "era" })
        H.inGuild = true
        local dialog = WantedPopup(ns, "Gank")
        dialog.OnAccept()
        T.eq(#H.chatSent, 1, "channel text in the click")
        T.ok(H.chatSent[1].text:find("^HH1:1AJ:Gank%-Firemaw;") ~= nil, "posse record")
        H.Advance(3)
        local guild
        for _, m in ipairs(H.sent) do
            if m.chatType == "GUILD" and m.message:find("^1AJ:") then guild = m end
        end
        T.ok(guild ~= nil, "also sent to the guild")
    end)

    T.case("another hunter's join: member list, and a chat line only for fellow members", function()
        local ns = H.Boot({ client = "era" })
        H.Deliver(JoinMessage(ns, "Gank-Stonespine"), "Hunter-Firemaw")
        T.eq(#ns.Posse:Members("Gank-Stonespine"), 1, "member stored")
        T.ok(not H.Printed("joined the posse"), "not in that posse: no chat")

        local dialog = WantedPopup(ns, "Gank")
        dialog.OnAccept()
        H.Deliver(JoinMessage(ns, "Gank-Firemaw"), "Hunter-Firemaw")
        T.ok(H.Printed("Hunter joined the posse against"), "fellow member announced")
        T.eq(ns.Posse:Summary("Gank-Firemaw"), "Posse: you, Hunter", "summary")
        T.noErrors()
    end)

    T.case("the activity popup lists the posse", function()
        local ns = H.Boot({ client = "era" })
        H.Deliver(JoinMessage(ns, "Gank-Firemaw", 30), "Alpha-Firemaw")
        H.Deliver(JoinMessage(ns, "Gank-Firemaw", 20), "Bravo-Firemaw")
        local dialog = WantedPopup(ns, "Gank")
        T.ok(dialog.text:find("Posse: Alpha, Bravo", 1, true) ~= nil, "posse shown in the popup")
    end)

    T.case("summary shows at most 3 names then +N", function()
        local ns = H.Boot({ client = "era" })
        for i, name in ipairs({ "Alpha", "Bravo", "Charlie", "Delta", "Echo" }) do
            H.Deliver(JoinMessage(ns, "Gank-Stonespine", 60 - i), name .. "-Firemaw")
        end
        T.eq(ns.Posse:Summary("Gank-Stonespine"), "Posse: Alpha, Bravo, Charlie +2", "summary")
    end)

    T.case("joins expire after 30 minutes; implausible or malformed joins are ignored", function()
        local ns = H.Boot({ client = "era" })
        H.Deliver(JoinMessage(ns, "Gank-Stonespine"), "Alpha-Firemaw")
        H.serverTime = H.serverTime + 1801
        T.eq(#ns.Posse:Members("Gank-Stonespine"), 0, "expired")
        H.Slash("posse")
        T.ok(H.Printed("No active posses"), "/hh posse")

        H.Deliver(JoinMessage(ns, "Gank-Stonespine", -3600), "Alpha-Firemaw")
        H.Deliver(JoinMessage(ns, "Gank-Stonespine", 3600), "Alpha-Firemaw")
        H.Deliver({ "1AJ:garbage" }, "Alpha-Firemaw")
        T.eq(#ns.Posse:Members("Gank-Stonespine"), 0, "rejected")
        T.noErrors()
    end)

    -- A new fresh kill by Gank-Firemaw on mapID (another player died)
    local extra = 0
    local function NewKill(ns, mapID, x)
        extra = extra + 1
        local victim = "Late" .. extra .. "-Firemaw"
        ns.Reports:Add({
            id = victim .. ":" .. H.serverTime, t = H.serverTime,
            victim = { key = victim, level = 40 },
            killer = { key = "Gank-Firemaw", name = "Gank-Firemaw", level = 60, class = "ROGUE", race = "Orc" },
            assists = {}, mapID = mapID, x = x or 0.3, y = 0.3, confidence = "exact",
        }, "peer", victim)
        Flow()
    end

    local function AlertPopups()
        local n = 0
        for _, p in ipairs(H.popups) do
            if p.which == "HEADHUNTER_ALERT" then n = n + 1 end
        end
        return n
    end

    T.case("in the posse: new kills give a short update, no popup, and move the waypoint", function()
        local ns = H.Boot({ client = "era" })
        local dialog = WantedPopup(ns, "Gank")
        dialog.OnAccept()
        local popups, waypoints = AlertPopups(), #H.waypoints
        H.clock = H.clock + 180
        H.serverTime = H.serverTime + 180
        H.Advance(3)
        local sentBefore = #H.sent
        NewKill(ns, 1436, 0.61)
        T.eq(AlertPopups(), popups, "no new popup")
        T.ok(H.centerTexts[#H.centerTexts]:find("struck again in Westfall", 1, true) ~= nil, "short update")
        T.eq(H.sounds[#H.sounds], 3175, "soft sound")
        T.eq(#H.waypoints, waypoints + 1, "waypoint moved")
        T.eq(H.waypoints[#H.waypoints].uiMapID, 1436, "to the new kill")
        T.eq(H.waypoints[#H.waypoints].x, 0.61, "new position")
        T.eq(ns.Posse:Members("Gank-Firemaw")[1].t, H.serverTime, "membership refreshed")
        T.noErrors()
    end)

    T.case("in the posse: a kill on another continent gives nothing", function()
        local ns = H.Boot({ client = "era" })
        WantedPopup(ns, "Gank").OnAccept()
        local texts = #H.centerTexts
        NewKill(ns, 1413)
        T.eq(#H.centerTexts, texts, "nothing")
    end)

    T.case("after Decline: no popup about any outlaw for 20 minutes, chat lines only", function()
        local ns = H.Boot({ client = "era" })
        local dialog = WantedPopup(ns, "Gank")
        dialog.OnCancel()
        local popups = AlertPopups()
        local function Wait(seconds)
            H.clock = H.clock + seconds
            H.serverTime = H.serverTime + seconds
        end
        Wait(180)
        NewKill(ns, 1429)
        T.eq(AlertPopups(), popups, "no popup after decline")
        T.ok(H.Printed("killed Late"), "chat line")
        H.Slash("spree Rakkar 5 60")
        Flow()
        T.eq(AlertPopups(), popups, "another outlaw: no popup either")
        T.ok(H.Printed("Rakkar"), "its chat line")
        Wait(900)
        NewKill(ns, 1429)
        T.eq(AlertPopups(), popups, "still quiet after 18 min")
        Wait(150)
        NewKill(ns, 1429)
        T.eq(AlertPopups(), popups + 1, "popup again after 20 min")
    end)

    T.case("a popup that times out holds popups like a Decline, without the bounty penalty", function()
        local ns = H.Boot({ client = "era" })
        local dialog = WantedPopup(ns, "Gank")
        local total = ns.Marks:Total()
        dialog.OnCancel(nil, nil, "timeout")
        T.eq(ns.Marks:Total(), total, "no penalty")
        T.eq(ns.Posse:RecentlyDeclined(), true, "held")
        local popups = AlertPopups()
        H.clock = H.clock + 200
        H.serverTime = H.serverTime + 200
        NewKill(ns, 1429)
        T.eq(AlertPopups(), popups, "no popup")
    end)

    T.case("in a posse: other outlaws nearby are chat lines, one in our own zone still asks", function()
        local ns = H.Boot({ client = "era" })
        WantedPopup(ns, "Gank").OnAccept()
        T.eq(ns.Posse:Hunting(), true, "hunting")
        local popups = AlertPopups()
        -- Five peer kills by one outlaw in mapID, the newest now
        local function Spree(killer, mapID)
            for i = 1, 5 do
                extra = extra + 1
                local victim = "Late" .. extra .. "-Firemaw"
                local t = H.serverTime - (5 - i) * 60
                ns.Reports:Add({
                    id = victim .. ":" .. t, t = t, victim = { key = victim, level = 40 },
                    killer = { key = killer, name = killer, level = 40, class = "ROGUE", race = "Orc" },
                    assists = {}, mapID = mapID, x = 0.3, y = 0.3, confidence = "exact",
                }, "peer", victim)
            end
            Flow()
        end
        H.clock = H.clock + 200
        H.serverTime = H.serverTime + 200
        Spree("Rakkar-Firemaw", 1436)       -- Westfall, next to Elwynn
        T.eq(AlertPopups(), popups, "no popup for another outlaw next door")
        T.ok(H.Printed("Rakkar"), "a chat line")
        H.clock = H.clock + 200
        H.serverTime = H.serverTime + 200
        Spree("Tuskar-Firemaw", 1429)       -- Elwynn, our zone
        T.eq(AlertPopups(), popups + 1, "an outlaw in our own zone still asks")
    end)

    T.case("a posse of more than 10 hears no more join messages", function()
        local ns = H.Boot({ client = "forever" })
        for i = 1, 11 do H.Deliver(JoinMessage(ns, "Grim Reaper"), "Rider Number" .. i) end
        T.eq(ns.Posse:Full("Grim Reaper"), true, "full")
        local dialog = WantedPopup(ns, '"Grim Reaper"')
        dialog.OnAccept()
        T.eq(ns.Posse:IsMember("Grim Reaper"), true, "we are in")
        H.Advance(3)
        for _, m in ipairs(H.sent) do
            T.ok(not m.message:find("^1AJ:"), "no join message")
        end
    end)

    T.case("/hh posse lists active posses", function()
        local ns = H.Boot({ client = "era" })
        H.Deliver(JoinMessage(ns, "Gank-Stonespine"), "Alpha-Firemaw")
        H.Slash("posse")
        T.ok(H.Printed("Gank%-Stonespine.*Posse: Alpha"), "listed")
    end)

    T.case("a reload keeps our posse: no second Join button, no second bounty", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("spree Gank 5 60")
        for _ = 1, 3 do H.Advance(1) for _ = 1, 10 do H.Advance(0) end end
        local entry = ns.Wanted:ByKey("Gank-Firemaw")
        T.ok(ns.Posse:Join(entry, { mapID = 1436, x = 0.5, y = 0.5 }), "joined")
        T.eq(ns.Marks:Total(), 1, "+1")

        local saved = ns.db
        ns = H.Boot({ client = "era", savedDB = saved })
        for _ = 1, 3 do H.Advance(1) for _ = 1, 10 do H.Advance(0) end end
        entry = ns.Wanted:ByKey("Gank-Firemaw")
        T.eq(ns.Posse:IsMember(entry.id), true, "still in the posse after the reload")
        T.eq(ns.Poster.Content(entry.id).canJoin, false, "no Join the posse button")
        T.eq(ns.Posse:Join(entry, { mapID = 1436, x = 0.5, y = 0.5 }), false, "joining again does nothing")
        T.eq(ns.Marks:Total(), 1, "no second bounty")

        H.serverTime = H.serverTime + 1801
        T.eq(ns.Posse:IsMember(entry.id), false, "after 30 minutes the join is over")
        T.noErrors()
    end)
end
