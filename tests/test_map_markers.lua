-- HH-046: map markers (fire pins for hotspots, skull pins for WANTED outlaws), and
-- the zone coordinates they rely on.

return function(T, H)
    local function near(actual, expected, label)
        T.ok(actual ~= nil and math.abs(actual - expected) < 1e-9,
            string.format("%s: got %s, want %s", label, tostring(actual), tostring(expected)))
    end

    local function Ping(ns, mapID, sender, enemyIds, ago, x, y)
        local record = ns.Protocol.EncodeHotspot(mapID, H.serverTime - (ago or 5), x or 0.4, y or 0.6, enemyIds)
        H.Deliver(ns.Protocol.Pack("A", "P", { record }), sender)
    end

    local function Ids(from, to)
        local ids = {}
        for i = from, to do ids[#ids + 1] = string.format("E%07d", i) end
        return ids
    end

    local serial = 0
    local function Kill(ns, mapID, ago, killer, x, y)
        serial = serial + 1
        local victim = "Victim" .. serial .. "-Firemaw"
        local t = H.serverTime - (ago or 30)
        killer = killer or "Gank-Stonespine"
        ns.Reports:Add({
            id = victim .. ":" .. t, t = t,
            victim = { key = victim, level = 30 },
            killer = { key = killer, name = killer, level = 60, class = "ROGUE", race = "Orc" },
            assists = {}, mapID = mapID, x = x or 0.5, y = y or 0.25, confidence = "exact",
        }, "peer", victim)
    end

    -- Report arrival + WANTED recompute + delayed death check
    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    local function Battle(ns, mapID)
        Ping(ns, mapID, "Alpha-Firemaw", Ids(1, 12))
        Ping(ns, mapID, "Bravo-Firemaw", Ids(1, 2))
    end

    local function Find(text, lines)
        for _, line in ipairs(lines) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end

    -------------------------------------------------
    -- Zone coordinates
    -------------------------------------------------

    T.case("cave positions become zone positions; unknown rect gives no position", function()
        local Z = H.Boot({ client = "era" }).Zones
        local zone, x, y = Z.ToZone(9001, 0.4, 0.5)
        T.eq(zone, 1429, "zone of the cave")
        T.eq(x, nil, "no rect: no x")
        T.eq(y, nil, "no rect: no y")
        H.mapRects["9001:1429"] = { 0.5, 0.6, 0.2, 0.3 }
        zone, x, y = Z.ToZone(9001, 0.4, 0.5)
        near(x, 0.54, "x on the zone")
        near(y, 0.25, "y on the zone")
        zone, x, y = Z.ToZone(1429, 0.4, 0.5)
        T.eq(x, 0.4, "a zone map stays as is")
    end)

    T.case("our own fight in a cave is placed on the zone (ping and waypoint)", function()
        local ns = H.Boot({ client = "forever" })
        H.playerMap = 9001
        H.mapRects["9001:1429"] = { 0.5, 0.6, 0.2, 0.3 }
        H.inCombat = true
        H.units.nameplate1 = { name = "Grim", realm = "Reaper", level = 60, class = "ROGUE", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-4613-00ABCDEF" }
        H.units.nameplate1target = H.units.player
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.Advance(5) -- tick
        H.Advance(3) -- flush
        local record
        for _, m in ipairs(H.sent) do
            if m.message:find("^1AP:") then record = select(3, ns.Protocol.Unpack(m.message))[1] end
        end
        T.ok(record ~= nil, "ping sent")
        local mapID, _, x, y = ns.Protocol.DecodeHotspot(record)
        T.eq(mapID, 1429, "ping carries the zone")
        near(x, 0.542, "ping x on the zone")
        near(y, 0.265, "ping y on the zone")
        T.eq(ns.Hotspots:Help(1429, "Battle"), "waypoint", "waypoint set")
        near(H.waypoints[#H.waypoints].x, 0.542, "waypoint x on the zone")
        T.noErrors()
    end)

    T.case("deaths in a cave are placed on the zone", function()
        local ns = H.Boot({ client = "era" })
        H.mapRects["9001:1429"] = { 0.5, 0.6, 0.2, 0.3 }
        Kill(ns, 9001, 20, "One-Stonespine", 0.5, 0.5)
        Kill(ns, 9001, 10, "Two-Stonespine", 0.5, 0.5)
        Settle()
        local spots = ns.Hotspots:Active()
        T.eq(#spots, 1, "one burning zone")
        T.eq(spots[1].zone, 1429, "the cave's zone")
        near(spots[1].x, 0.55, "x on the zone")
        near(spots[1].y, 0.25, "y on the zone")
    end)

    -------------------------------------------------
    -- Pin data
    -------------------------------------------------

    T.case("fire pin on its zone, projected on the continent, absent elsewhere", function()
        local ns = H.Boot({ client = "era" })
        Battle(ns, 1417)
        local pins = ns.MapMarkers:PinsFor(1417)
        T.eq(#pins, 1, "one pin on Arathi")
        local pin = pins[1]
        T.eq(pin.kind, "hotspot", "fire pin")
        T.eq(pin.level, 2, "Battle")
        near(pin.size, 0.10, "area: 10% of the zone's width")
        T.eq(pin.alpha, ns.MapMarkers.AREA_ALPHA[2], "Battle shade")
        T.ok(ns.MapMarkers.AREA_ALPHA[3] > pin.alpha and pin.alpha > ns.MapMarkers.AREA_ALPHA[1], "darker = more PvP")
        near(pin.x, 0.4, "x")
        near(pin.y, 0.6, "y")
        T.ok(Find("PvP zone", pin.lines) and Find("Battle", pin.lines) and Find("Arathi Highlands", pin.lines), "title")
        T.ok(Find("≈12 Horde fighting 2 Alliance", pin.lines) and not Find("death", pin.lines), "counts (no deaths: not mentioned)")
        T.ok(Find("just now", pin.lines), "age")

        T.eq(#ns.MapMarkers:PinsFor(1415), 0, "continent without a rect: not placed")
        H.mapRects["1417:1415"] = { 0.5, 0.7, 0.3, 0.5 }
        pins = ns.MapMarkers:PinsFor(1415)
        T.eq(#pins, 1, "on Eastern Kingdoms")
        near(pins[1].x, 0.58, "continent x")
        near(pins[1].y, 0.42, "continent y")
        near(pins[1].size, 0.02, "area shrinks with the zone on the continent")
        T.eq(#ns.MapMarkers:PinsFor(1429), 0, "not on another zone")
        T.eq(#ns.MapMarkers:PinsFor(1414), 0, "not on the other continent")
    end)

    T.case("hotspot alerts say PvP and count both sides", function()
        local ns = H.Boot({ client = "era" })
        Ping(ns, 1429, "Alpha-Firemaw", Ids(1, 12)) -- the player's zone becomes a Battle
        local text
        for _, p in ipairs(H.popups) do
            if p.which == "HEADHUNTER_HOTSPOT" then text = p.text end
        end
        T.ok(text ~= nil, "Battle popup")
        T.ok(text:find("PvP", 1, true) ~= nil, "says PvP")
        T.ok(text:find("≈12 Horde fighting 1 Alliance", 1, true) ~= nil, "both sides: " .. text)
    end)

    T.case("a PvP area of 2+ fires takes a click for help; a Skirmish does not", function()
        local ns = H.Boot({ client = "era" })
        Battle(ns, 1417)
        local battle = ns.MapMarkers:PinsFor(1417)[1]
        T.eq(battle.level, 2, "Battle")
        T.ok(battle.clickable, "clickable")
        T.eq(battle.zone, 1417, "knows its zone")
        T.ok(Find("Left-click", battle.lines), "says what a click does")

        Ping(ns, 1436, "Alpha-Firemaw", Ids(1, 4))
        local skirmish = ns.MapMarkers:PinsFor(1436)[1]
        T.eq(skirmish.level, 1, "Skirmish")
        T.ok(not skirmish.clickable, "no click")
        T.ok(not Find("Left-click", skirmish.lines), "no click hint")
        T.noErrors()
    end)

    T.case("a PvP area stays 10 min after the last activity; new activity restarts it", function()
        local ns = H.Boot({ client = "era" })
        Battle(ns, 1417) -- pings 5 s ago
        T.eq(#ns.MapMarkers:PinsFor(1417), 1, "burning")
        T.eq(ns.Hotspots:Heat(1417), 14, "heat now")
        H.serverTime = H.serverTime + 301
        T.eq(ns.Hotspots:Heat(1417), 0, "the alerts' 5 min window has passed")
        local pins = ns.MapMarkers:PinsFor(1417)
        T.eq(#pins, 1, "still on the map")
        T.eq(pins[1].level, 2, "as it last was: Battle")
        T.ok(Find("5 min ago", pins[1].lines), "says when")

        H.serverTime = H.serverTime + 4 * 60 -- 9 min 6 s after the pings
        T.eq(#ns.MapMarkers:PinsFor(1417), 1, "9 min: still there")
        Battle(ns, 1417)                      -- fighting again
        H.serverTime = H.serverTime + 9 * 60
        T.eq(#ns.MapMarkers:PinsFor(1417), 1, "restarted: 9 min after the new fight")
        H.serverTime = H.serverTime + 2 * 60
        T.eq(#ns.MapMarkers:PinsFor(1417), 0, "gone 10 min after the last activity")
    end)

    T.case("WANTED outlaw: skull pin at the last kill, no fire pin for a lone ganker", function()
        local ns = H.Boot({ client = "era" })
        for i = 1, 4 do Kill(ns, 1436, 60 + i * 30) end
        Kill(ns, 1436, 30, nil, 0.3, 0.7)
        Settle()
        T.eq(#ns.Wanted:List(), 1, "Gank is WANTED")
        local pins = ns.MapMarkers:PinsFor(1436)
        T.eq(#pins, 1, "only the skull")
        local pin = pins[1]
        T.eq(pin.kind, "wanted", "skull pin")
        near(pin.x, 0.3, "last kill x")
        near(pin.y, 0.7, "last kill y")
        T.eq(pin.hunted, false, "not hunting yet")
        T.ok(Find("WANTED", pin.lines) and Find("Gank", pin.lines), "title")
        T.ok(Find("5 kills · until busted", pin.lines), "rank, kills, until caught")
        T.ok(Find("Last kill just now in Westfall", pin.lines), "last kill")
        T.ok(not Find("Click", pin.lines), "no click action (author, 2026-09-23)")
        T.noErrors()
    end)

    T.case("a skull shows for 10 min after the last kill; a new kill brings it back", function()
        local ns = H.Boot({ client = "era" })
        for i = 1, 5 do Kill(ns, 1436, i * 30) end
        Settle()
        T.eq(#ns.MapMarkers:PinsFor(1436), 1, "fresh kill: skull")
        H.serverTime = H.serverTime + 9 * 60
        T.eq(#ns.MapMarkers:PinsFor(1436), 1, "9 min later: still there")
        H.serverTime = H.serverTime + 2 * 60
        T.eq(#ns.MapMarkers:PinsFor(1436), 0, "11 min later: gone from the map")
        T.eq(#ns.Wanted:List(), 1, "but still WANTED")
        Kill(ns, 1417, 10, nil, 0.2, 0.3) -- strikes again elsewhere
        Settle()
        T.eq(#ns.MapMarkers:PinsFor(1436), 0, "not back at the old place")
        T.eq(#ns.MapMarkers:PinsFor(1417), 1, "back on the map at the new kill")
    end)

    T.case("at most 10 skulls on a map, the highest ranked; the outlaw we hunt always", function()
        local ns = H.Boot({ client = "era" })
        for n = 1, 12 do
            local killer = "Gank" .. string.char(64 + n) .. "-Stonespine"
            for i = 1, 5 + n do Kill(ns, 1436, i * 10, killer) end
        end
        for i = 1, 5 do Kill(ns, 1436, 300 + i * 10, "Lowly-Stonespine") end
        Settle()
        T.eq(#ns.Wanted:List(), 13, "13 WANTED")
        -- Skulls only (so many kills also make a PvP area)
        local function Skulls()
            local skulls = {}
            for _, pin in ipairs(ns.MapMarkers:PinsFor(1436)) do
                if pin.kind == "wanted" then skulls[#skulls + 1] = pin end
            end
            return skulls
        end
        local pins = Skulls()
        T.eq(#pins, 10, "10 skulls")
        local names = {}
        for _, pin in ipairs(pins) do names[#names + 1] = pin.id end
        T.ok(table.concat(names, ","):find("GankL", 1, true) ~= nil, "the most kills is shown")
        T.ok(table.concat(names, ","):find("GankA", 1, true) == nil, "the fewest is not")

        ns.Posse:Join(ns.Wanted:ByKey("Lowly-Stonespine"), { mapID = 1436, x = 0.5, y = 0.25 })
        pins = Skulls()
        T.eq(#pins, 10, "still 10")
        T.eq(pins[1].id, "wanted:Lowly-Stonespine", "the one we hunt first")
    end)

    T.case("the outlaw our posse hunts is marked and shows the posse", function()
        local ns = H.Boot({ client = "era" })
        for i = 1, 5 do Kill(ns, 1436, i * 30) end
        Settle()
        local entry = ns.Wanted:List()[1]
        ns.Posse:Join(entry, { mapID = 1436, x = 0.5, y = 0.25 })
        local pin = ns.MapMarkers:PinsFor(1436)[1]
        T.eq(pin.hunted, true, "hunted")
        T.ok(Find("Posse: you", pin.lines), "posse line")
        T.noErrors()
    end)

    -------------------------------------------------
    -- Guiding where the client has no waypoints (Classic Era)
    -------------------------------------------------

    T.case("Help without game waypoints: chat gives the coordinates", function()
        local ns = H.Boot({ client = "era" })
        H.noWaypoints = true
        Battle(ns, 1417)
        T.eq(ns.Hotspots:Help(1417, "Battle"), "coords", "no waypoint: coordinates")
        T.eq(#H.waypoints, 0, "no game waypoint")
        T.ok(H.Printed("PvP Battle in Arathi Highlands at 40.0, 60.0."), "chat says where")
        T.noErrors()
    end)

    T.case("Help with no known position says so", function()
        local ns = H.Boot({ client = "era" })
        H.noWaypoints = true
        ns.Hotspots:Help(1417, "Battle")
        T.ok(H.Printed("PvP Battle in Arathi Highlands: position unknown."), "said so")
    end)

    T.case("Join the posse gives coordinates without game waypoints", function()
        local ns = H.Boot({ client = "era" })
        H.noWaypoints = true
        for i = 1, 5 do Kill(ns, 1436, i * 30, nil, 0.3, 0.7) end
        Settle()
        local entry = ns.Wanted:List()[1]
        ns.Posse:Join(entry, { mapID = 1436, x = 0.3, y = 0.7 })
        T.ok(H.Printed("You joined the posse against Gank%-Stonespine%. Last seen in Westfall at 30%.0, 70%.0%."),
            "join says where")
        T.noErrors()
    end)

    -------------------------------------------------
    -- Drawing
    -------------------------------------------------

    T.case("pins drawn on the shown map, follow map changes, zoom and data", function()
        local ns = H.Boot({ client = "era", worldMap = true })
        local map, M = H.worldMap, ns.MapMarkers
        map:Open(1417)
        T.eq(M:ShownCount(), 0, "nothing yet")
        Battle(ns, 1417)
        H.Advance(0.2)
        T.eq(M:ShownCount(), 1, "redrawn on new data")

        local canvas = map.ScrollContainer.Child
        local drawn
        for _, frame in ipairs(H.AllFrames()) do
            if rawget(frame, "discs") and frame.shown then drawn = frame end
        end
        T.ok(drawn ~= nil, "PvP area shown")
        T.eq(drawn.point[4], 400, "x offset on the canvas")
        T.eq(drawn.point[5], -420, "y offset on the canvas")
        T.eq(drawn.width, 100, "10% of the canvas wide")
        local inner = drawn.discs[3]
        T.eq(rawget(inner, "texture"), M.CIRCLE, "disc")
        T.eq(inner.color[1], 1, "red")
        T.eq(inner.color[4], M.AREA_ALPHA[2], "Battle shade in the middle")
        T.ok(drawn.discs[1].color[4] < inner.color[4], "lighter at the edge")
        T.eq(drawn.label.text.shownText, "PVP", "PVP in the middle")
        T.eq(rawget(drawn.label.icon, "texture"), M.SWORDS_ICON, "under crossed swords")
        T.eq(drawn.label.data.kind, "hotspot", "label carries tooltip and click")

        canvas.scale = 2 -- zoom in
        M:OnUpdate(0.01)
        T.eq(drawn.scale, 1, "the area zooms with the map")
        T.eq(drawn.point[4], 400, "same place on the canvas")
        T.eq(drawn.label.scale, 0.5, "the label keeps its size on screen")

        canvas.scale = 0.1 -- far out: the area keeps a minimum size on screen
        M:OnUpdate(0.01)
        T.eq(drawn.width, 320, "32 px on screen at scale 0.1")

        map:SetMapID(1429)
        T.eq(M:ShownCount(), 0, "another zone")
        map:SetMapID(1417)
        T.eq(M:ShownCount(), 1, "back")
        map:Close()
        T.eq(M:ShownCount(), 0, "closed")

        H.Slash("map off")
        map:Open(1417)
        T.eq(M:ShownCount(), 0, "turned off")
        T.ok(H.Printed("Map pins: off"), "status")
        H.Slash("map on")
        H.Advance(0.2)
        T.eq(M:ShownCount(), 1, "turned on")
        T.noErrors()
    end)

    T.case("other addons' pins on the map never cover ours; tooltips stay above", function()
        local ns = H.Boot({ client = "era", worldMap = true })
        local map, M = H.worldMap, ns.MapMarkers
        local canvas = map.ScrollContainer.Child
        canvas.strata, canvas.frameLevel = "HIGH", 10
        local notes = { strata = "HIGH", frameLevel = 5000 }
        local tooltipish = { strata = "TOOLTIP", frameLevel = 9000 }
        function notes:GetFrameStrata() return self.strata end
        function notes:GetFrameLevel() return self.frameLevel end
        tooltipish.GetFrameStrata, tooltipish.GetFrameLevel = notes.GetFrameStrata, notes.GetFrameLevel
        canvas.children = { notes, tooltipish }
        map:Open(1417)
        Battle(ns, 1417)
        H.Advance(0.2)
        local drawn
        for _, frame in ipairs(H.AllFrames()) do
            if rawget(frame, "discs") and frame.shown then drawn = frame end
        end
        T.ok(drawn:GetFrameLevel() > 5000, "above the highest other pin")

        notes.strata = "DIALOG"
        M:Refresh()
        local overlayStrata
        for _, frame in ipairs(H.AllFrames()) do
            if frame.scripts.OnUpdate and rawget(frame, "strata") then overlayStrata = frame.strata end
        end
        T.eq(overlayStrata, "DIALOG", "follows a higher strata, but never TOOLTIP")

        notes.strata, notes.frameLevel = "HIGH", 9999
        M:Refresh()
        T.ok(drawn:GetFrameLevel() < M.MAX_FRAME_LEVEL, "never past the game's highest level")
        T.noErrors()
    end)

    T.case("a world map that loads later is picked up", function()
        local ns = H.Boot({ client = "era" })
        _G.WorldMapFrame = H.NewWorldMap()
        H.worldMap = _G.WorldMapFrame
        H.Fire("ADDON_LOADED", "Blizzard_WorldMap")
        Battle(ns, 1417)
        H.worldMap:Open(1417)
        T.eq(ns.MapMarkers:ShownCount(), 1, "drawn")
        T.noErrors()
    end)
end
