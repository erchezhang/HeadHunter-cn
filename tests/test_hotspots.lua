-- HH-045: PvP hotspots (heat = A + E + 2*D over 5 min, fire levels, alerts).

return function(T, H)
    local function Ping(ns, mapID, sender, enemyIds, ago)
        local record = ns.Protocol.EncodeHotspot(mapID, H.serverTime - (ago or 5), 0.4, 0.6, enemyIds)
        H.Deliver(ns.Protocol.Pack("A", "P", { record }), sender)
    end

    local function Ids(from, to)
        local ids = {}
        for i = from, to do ids[#ids + 1] = string.format("E%07d", i) end
        return ids
    end

    local deathSerial = 0
    local function Death(ns, mapID, ago, killer)
        deathSerial = deathSerial + 1
        local victim = "Dead" .. deathSerial .. "-Firemaw"
        local t = H.serverTime - (ago or 10)
        killer = killer or "Someone-Stonespine"
        ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = 40 },
            killer = { key = killer, name = killer, level = 40 },
            assists = {}, mapID = mapID, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
    end

    -- Report arrival + WANTED recompute + delayed death check
    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    local function Popups()
        local n = 0
        for _, p in ipairs(H.popups) do if p.which == "HEADHUNTER_HOTSPOT" then n = n + 1 end end
        return n
    end

    T.case("hotspot ping round trip", function()
        local P = H.Boot({ client = "era" }).Protocol
        local mapID, t, x, y, ids = P.DecodeHotspot(P.EncodeHotspot(1417, 1790000000, 0.25, 0.75, { "AB12CD34", "ZZ99", "bad-id!" }))
        T.eq(mapID, 1417, "map")
        T.eq(t, 1790000000, "time")
        T.eq(x, 0.25, "x")
        T.eq(y, 0.75, "y")
        T.eq(#ids, 3, "ids")
        T.eq(ids[3], "badid", "ids are sanitised")
        T.eq(P.DecodeHotspot("a;b"), nil, "malformed")
    end)

    T.case("heat = HeadHunters + distinct enemies + 2 x deaths, over 5 minutes", function()
        local ns = H.Boot({ client = "era" })
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 3))
        Ping(ns, 1436, "Bravo-Firemaw", Ids(2, 5)) -- overlaps: 5 distinct enemies
        Death(ns, 1436)
        local heat, level, a, e, d = ns.Hotspots:Heat(1436)
        T.eq(a, 2, "HeadHunters")
        T.eq(e, 5, "distinct enemies")
        T.eq(d, 1, "deaths")
        T.eq(heat, 9, "2 + 5 + 2")
        T.eq(level, 1, "Skirmish")
        H.serverTime = H.serverTime + 301
        heat = ns.Hotspots:Heat(1436)
        T.eq(heat, 0, "older than 5 minutes: gone")
    end)

    T.case("levels: Skirmish chat, Battle popup, Warzone center text; announced only when climbing", function()
        local ns = H.Boot({ client = "era" }) -- player in Elwynn; Westfall is adjacent
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 4)) -- heat 5
        T.ok(H.Printed("Skirmish.*Westfall"), "Skirmish chat line")
        T.eq(Popups(), 0, "no popup for a Skirmish")
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 4)) -- same level again
        local lines = #H.printed
        T.eq(#H.printed, lines, "not repeated")
        Ping(ns, 1436, "Bravo-Firemaw", Ids(5, 9)) -- heat 11
        T.eq(Popups(), 1, "Battle popup")
        T.ok(_G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.text:find("Battle", 1, true) ~= nil, "Battle text")
        T.ok(_G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.text:find("Horde", 1, true) ~= nil, "enemy faction named")
        T.eq(#H.centerTexts, 0, "no center text for a Battle")
        Death(ns, 1436)
        Death(ns, 1436)
        H.clock = H.clock + ns.Alerts.POPUP_GAP -- one popup per 3 min
        Ping(ns, 1436, "Charlie-Firemaw", Ids(10, 14)) -- heat 3 + 14 + 4 = 21
        T.ok(H.centerTexts[#H.centerTexts]:find("Warzone", 1, true) ~= nil, "Warzone center text")
        T.noErrors()
    end)

    T.case("the alert names the HeadHunters of our side in the fight", function()
        local ns = H.Boot({ client = "era" })
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 5))
        Ping(ns, 1436, "Bravo-Firemaw", Ids(6, 10))
        local text = _G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.text
        T.ok(text:find("Fighting: Bravo, Alpha", 1, true) ~= nil, "newest first: " .. text)
        -- The chat line: links to whisper them with a click; the popup cannot be clicked
        T.ok(H.Printed("Fighting: |cffff7fff|Hplayer:Bravo|h%[Bravo%]|h|r, |cffff7fff|Hplayer:Alpha|h%[Alpha%]|h|r"), "names to click in chat")
        T.ok(not text:find("|Hplayer:", 1, true), "plain names in the popup")
        T.eq(ns.Utils.PlayerLink("Iron-Stonespine"), "|cffff7fff|Hplayer:Iron-Stonespine|h[Iron-Stonespine]|h|r",
            "another realm keeps it, in the whisper color")
        _G.ChatTypeInfo.WHISPER = { r = 0, g = 1, b = 0 }
        T.eq(ns.Utils.PlayerLink("Iron"), "|cff00ff00|Hplayer:Iron|h[Iron]|h|r", "the player's own whisper color")
        _G.ChatTypeInfo.WHISPER = nil
        T.noErrors()
    end)

    T.case("a lone WANTED outlaw's kills: Battle heat, but a chat line only", function()
        local ns = H.Boot({ client = "era" })
        for i = 1, 5 do Death(ns, 1436, i * 30, "Gank-Stonespine") end -- heat 10, WANTED ganker
        Settle()
        T.eq(ns.Wanted:ByKey("Gank-Stonespine").wanted, true, "precondition: WANTED")
        T.eq(Popups(), 0, "no Battle popup")
        T.ok(H.Printed("Battle.*Westfall"), "chat line")
    end)

    T.case("deaths by two different killers are a real Battle", function()
        local ns = H.Boot({ client = "era" })
        for i = 1, 3 do Death(ns, 1436, i * 30, "Gank-Stonespine") end
        for i = 1, 2 do Death(ns, 1436, i * 40, "Stab-Stonespine") end
        Settle()
        T.eq(Popups(), 1, "Battle popup")
    end)

    T.case("a lone outlaw plus enemies seen fighting is a real Battle", function()
        local ns = H.Boot({ client = "era" })
        for i = 1, 4 do Death(ns, 1436, i * 30, "Gank-Stonespine") end -- heat 8
        Settle()
        T.eq(Popups(), 0, "Skirmish so far")
        H.clock = H.clock + ns.Alerts.POPUP_GAP -- after the WANTED popup about Gank
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 3)) -- + 1 + 3 = 12
        T.eq(Popups(), 1, "Battle popup")
    end)

    T.case("out of range: nothing; continent range: alerted", function()
        local ns = H.Boot({ client = "era" })
        Ping(ns, 1434, "Alpha-Firemaw", Ids(1, 12)) -- Stranglethorn, heat 13
        T.eq(Popups(), 0, "not adjacent")
        T.ok(not H.Printed("Battle"), "no chat either")
        H.Slash("alerts range continent")
        Ping(ns, 1434, "Bravo-Firemaw", Ids(1, 12))
        T.eq(Popups(), 1, "continent range")
    end)

    T.case("Help sets a waypoint to the fight; Ignore mutes the zone", function()
        local ns = H.Boot({ client = "era" })
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 10))
        _G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.OnAccept()
        T.eq(H.waypoints[1].uiMapID, 1436, "waypoint zone")
        T.eq(H.waypoints[1].x, 0.4, "waypoint position")
        T.ok(H.Printed("Waypoint set to the fight in Westfall"), "confirmation")

        local ns2 = H.Boot({ client = "era" })
        Ping(ns2, 1436, "Alpha-Firemaw", Ids(1, 10))
        _G.StaticPopupDialogs.HEADHUNTER_HOTSPOT.OnCancel()
        Ping(ns2, 1436, "Bravo-Firemaw", Ids(11, 25)) -- would be a Warzone
        T.eq(#H.centerTexts, 0, "muted")
    end)

    T.case("our own fight: pings go out, and we are not alerted about it", function()
        local ns = H.Boot({ client = "forever" })
        H.inCombat = true
        H.units.nameplate1 = { name = "Grim", realm = "Reaper", level = 60, class = "ROGUE", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-4613-00ABCDEF" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.Advance(5) -- tick
        H.Advance(3) -- flush
        local ping
        for _, m in ipairs(H.sent) do if m.message:find("^1AP:") then ping = m end end
        T.ok(ping ~= nil, "ping sent")
        T.ok(ping.message:find("00ABCDEF", 1, true) ~= nil, "short enemy id")
        local sent = #H.sent
        H.Advance(5)
        H.Advance(3)
        T.eq(#H.sent, sent, "at most one ping per 30 s")

        Ping(ns, 1429, "Other Hunter", Ids(1, 12)) -- our own zone becomes a Battle
        T.eq(Popups(), 0, "not alerted about our own fight")
        T.noErrors()
    end)

    T.case("our own deaths put us in the fight: no alert about it", function()
        local ns = H.Boot({ client = "era" })
        local me = ns.Utils.UnitKey("player")
        for i = 1, 5 do
            local t = H.serverTime - (5 - i) * 60
            ns.Reports:Add({ id = me .. ":" .. t, t = t, victim = { key = me, level = 30 },
                killer = { key = (i % 2 == 0) and "Torch-Stonespine" or "Burner-Stonespine", level = 60 },
                assists = {}, mapID = 1429, x = 0.5, y = 0.5, confidence = "sim" }, "sim")
        end
        Settle()
        T.eq(Popups(), 0, "no popup about our own deaths")
        T.ok(not H.Printed("Battle"), "no chat line either")
        local heat, level, a = ns.Hotspots:Heat(1429)
        T.eq(level, 2, "still a Battle for the map and for others")
        T.eq(a, 1, "we count as a HeadHunter in that fight")
        T.noErrors()
    end)

    T.case("no pings out of combat or inside instances", function()
        local ns = H.Boot({ client = "forever" })
        H.units.nameplate1 = { name = "Grim", realm = "Reaper", faction = "Horde", isPlayer = true, guid = "Player-1" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.Advance(5); H.Advance(3)
        T.eq(#H.sent, 0, "out of combat")
        H.inCombat = true
        H.instance = { true, "pvp" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        H.Advance(5); H.Advance(3)
        T.eq(#H.sent, 0, "inside a battleground")
    end)

    T.case("the hotspot line says only what is known", function()
        local D = H.Boot({ client = "era" }).Hotspots.Describe
        T.eq(D(0, 0, 4), "4 death(s) in 5 min", "deaths only (e.g. from reports)")
        T.eq(D(0, 3, 0), "≈3 Horde seen fighting", "enemies only")
        T.eq(D(2, 0, 1), "2 Alliance fighting, 1 death(s) in 5 min", "ours only")
        T.eq(D(5, 4, 4), "≈4 Horde fighting 5 Alliance, 4 death(s) in 5 min", "everything")
    end)

    T.case("/hh hotspots lists active zones", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("hotspots")
        T.ok(H.Printed("No PvP activity"), "empty")
        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 3))
        H.Slash("hotspots")
        T.ok(H.Printed("Westfall: heat 4 %(HeadHunters 1, enemies 3, deaths 0%)"), "listed")
    end)

    T.case("ping: our side rides along as +ids, older clients see only the enemies", function()
        local P = H.Boot({ client = "forever" }).Protocol
        local record = P.EncodeHotspot(1429, H.serverTime, 0.4, 0.6, { "E0000001", "E0000002" }, nil, nil,
            { "A0000001", "A0000002" })
        local _, _, _, _, ids, _, _, allies = P.DecodeHotspot(record)
        T.eq(#ids, 2, "enemies")
        T.eq(#allies, 2, "our side")
        T.eq(allies[1], "A0000001", "the sender first")
        -- What a 0.3 client reads from the id list: plain ids only
        local field = record:match("^[^;]*;[^;]*;[^;]*;[^;]*;([^;]*)")
        local old = 0
        for id in field:gmatch("[^,]+") do if id:match("^%w+$") then old = old + 1 end end
        T.eq(old, 2, "an older client counts only the enemies")
        T.eq(select(8, P.DecodeHotspot(P.EncodeHotspot(1429, H.serverTime, 0.4, 0.6, { "E0000001" }))), nil,
            "no allies from an older ping")
        -- A full ping drops allies to stay short enough
        local enemies = {}
        for i = 1, 3 do enemies[i] = { name = "Longername Number" .. i, class = "ROGUE", level = 60 } end
        local long = P.EncodeHotspot(1429, H.serverTime, 0.4, 0.6, Ids(1, 12), enemies, 5, Ids(13, 24))
        T.ok(#long <= P.PING_BUDGET, "fits: " .. #long)
    end)

    T.case("a 3 vs 2 fight shows 3 vs 2: allies count, passers-by and old enemies do not", function()
        local ns = H.Boot({ client = "forever" })
        H.inCombat = true
        local function Unit(i, faction, inCombat)
            H.units["nameplate" .. i] = { name = "Unit" .. i, realm = "Reaper", level = 30, class = "WARRIOR",
                race = faction == "Horde" and "Orc" or "Human", faction = faction, isPlayer = true,
                guid = string.format("Player-4613-0000000%d", i), inCombat = inCombat }
        end
        Unit(1, "Horde", true)      -- the two we fight
        Unit(2, "Horde", true)
        Unit(3, "Horde", false)     -- an enemy riding past
        Unit(4, "Alliance", true)   -- our side, without HeadHunter
        Unit(5, "Alliance", true)
        Unit(6, "Alliance", false)  -- our side, not fighting
        H.Advance(5) -- tick
        -- Another HeadHunter fought two other enemies here 4 minutes ago
        Ping(ns, 1429, "Other Hunter", { "OLD00001", "OLD00002" }, 240)
        local _, _, a, e = ns.Hotspots:Heat(1429)
        T.eq(a, 4, "5 min: us, our two allies and the other HeadHunter")
        T.eq(e, 4, "5 min: every enemy fighting in the zone")
        local nowA, nowE = ns.Hotspots:Now(1429)
        T.eq(nowA, 3, "now: 3 of us")
        T.eq(nowE, 2, "now: 2 of them")
        T.noErrors()
    end)

    T.case("enemies attacking us count when the combat flag is hidden, and our group's targets are seen", function()
        local ns = H.Boot({ client = "forever" })
        H.inCombat = true
        local SECRET = {}
        _G.issecretvalue = function(value) return value == SECRET end
        local function Player(unit, i, faction, inCombat)
            H.units[unit] = { name = "Unit" .. i, realm = "Reaper", level = 30, class = "WARRIOR",
                race = faction == "Horde" and "Orc" or "Human", faction = faction, isPlayer = true,
                guid = string.format("Player-4613-0000000%d", i), inCombat = inCombat }
        end
        Player("nameplate1", 1, "Horde", SECRET)   -- combat flag hidden, hitting one of us
        Player("nameplate1target", 4, "Alliance", true)
        Player("nameplate2", 2, "Horde", SECRET)   -- combat flag hidden, targeting nobody of ours
        Player("party1", 5, "Alliance", true)      -- a group member far away...
        Player("party1target", 3, "Horde", true)   -- ...fighting an enemy we cannot see
        local fighting, idle, unknown = ns.Hotspots.ScanFighters()
        T.eq(fighting, 2, "the attacker and the group member's enemy")
        T.eq(idle, 1, "the one targeting nobody of ours")
        T.eq(unknown, 2, "two hidden combat flags")
        H.Advance(5) -- tick
        local _, nowE = ns.Hotspots:Now(1429)
        T.eq(nowE, 2, "the map shows 2 enemies")
        _G.issecretvalue = nil
        T.noErrors()
    end)
end
