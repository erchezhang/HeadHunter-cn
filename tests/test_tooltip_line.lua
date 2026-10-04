-- HH-062: a HeadHunter line on enemy player tooltips.

return function(T, H)
    local serial = 0

    local function Spree(ns, killer, n, victimLevel)
        for i = 1, n do
            serial = serial + 1
            local victim = "Victim" .. serial .. "-Firemaw"
            local t = H.serverTime - (n - i + 1) * 30
            ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = victimLevel or 20 },
                killer = { key = killer, name = killer, level = 60, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = 1436, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
        end
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    local function Enemy(name, realm)
        H.units.mouseover = { name = name, realm = realm, level = 60, class = "ROGUE", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-2-000" .. name }
    end

    for _, mode in ipairs({ "script", "processor" }) do
        T.case(mode .. ": a WANTED enemy's tooltip says so, once", function()
            local ns = H.Boot({ client = "era", tooltip = mode })
            T.eq(ns.TooltipLine.hook, mode, "hook used")
            Spree(ns, "Gank-Stonespine", 5)
            Settle()
            Enemy("Gank", "Stonespine")
            H.ShowUnitTooltip("mouseover", 3) -- the client may fire the callback repeatedly
            T.eq(#H.tooltipLines, 1, "one line, not three")
            T.ok(H.tooltipLines[1]:find("WANTED", 1, true) ~= nil, "WANTED")
            T.ok(H.tooltipLines[1]:find("Ganker", 1, true) ~= nil, "rank")
            T.ok(H.tooltipLines[1]:find("5 kills", 1, true) ~= nil, "kills")
            T.ok(H.tooltipLines[1]:find("Bully", 1, true) ~= nil, "badges")
            H.ShowUnitTooltip("mouseover")
            T.eq(#H.tooltipLines, 1, "shown again after the tooltip was cleared")
            T.noErrors()
        end)
    end

    T.case("a known enemy who is not WANTED gets a grey line; strangers and friends none", function()
        local ns = H.Boot({ client = "era", tooltip = "script" })
        Spree(ns, "Sneak-Stonespine", 2)
        Settle()
        Enemy("Sneak", "Stonespine")
        H.ShowUnitTooltip("mouseover")
        T.eq(H.tooltipLines[1], "HeadHunter: 2 kills known · |cffff8000Bully|r", "known")
        Enemy("Nobody", "Stonespine")
        H.ShowUnitTooltip("mouseover")
        T.eq(#H.tooltipLines, 0, "unknown enemy")
        H.units.mouseover = { name = "Sneak", realm = "Stonespine", faction = "Alliance", isPlayer = true, guid = "P-1" }
        H.ShowUnitTooltip("mouseover")
        T.eq(#H.tooltipLines, 0, "same faction (a duel partner, a namesake): nothing")
    end)

    T.case("the posse shows under the WANTED line; caught outlaws only their kills", function()
        local ns = H.Boot({ client = "era", tooltip = "script" })
        Spree(ns, "Gank-Stonespine", 5)
        Settle()
        ns.Posse:Join(ns.Wanted:ByKey("Gank-Stonespine"), { mapID = 1436, x = 0.5, y = 0.5 })
        Enemy("Gank", "Stonespine")
        H.ShowUnitTooltip("mouseover")
        T.eq(H.tooltipLines[2], "Posse: you", "posse line")

        ns.Justice:Record(ns.Wanted:ByKey("Gank-Stonespine"), "test")
        Settle()
        H.ShowUnitTooltip("mouseover")
        T.ok(H.tooltipLines[1]:find("HeadHunter: 5 kills known", 1, true) == 1, "caught: " .. tostring(H.tooltipLines[1]))
        T.ok(not H.tooltipLines[1]:find("busted", 1, true), "no busted count")
    end)

    T.case("forever: Given Family names; /hh tooltip off", function()
        local ns = H.Boot({ client = "forever", tooltip = "processor" })
        Spree(ns, "Grim Reaper", 5)
        Settle()
        H.units.mouseover = { name = "Grim", realm = "Reaper", fullName = "Grim Reaper", level = 60, class = "ROGUE",
            race = "Orc", faction = "Horde", isPlayer = true, guid = "Player-4613-00ABCDEF" }
        H.ShowUnitTooltip("mouseover")
        T.eq(#H.tooltipLines, 1, "found by Given Family")
        H.Slash("tooltip off")
        H.ShowUnitTooltip("mouseover")
        T.eq(#H.tooltipLines, 0, "off")
        T.ok(H.Printed("off"), "said so")
        T.noErrors()
    end)

    T.case("no tooltip to hook: nothing breaks", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.TooltipLine.hook, nil, "no hook")
        T.noErrors()
    end)
end
