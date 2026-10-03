-- HH-047: the WANTED popup only for players who can really fight the outlaw
-- (the outlaw's level -5 to +9). The harness turns the window off by default, so
-- every case here boots with levelWindow = true.

return function(T, H)
    local serial = 0

    local function Spree(ns, killerLevel, n)
        for i = 1, n do
            serial = serial + 1
            local victim = "Victim" .. serial .. "-Firemaw"
            local t = H.serverTime - (n - i + 1) * 20
            ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = 30 },
                killer = { key = "Gank-Stonespine", name = "Gank-Stonespine", level = killerLevel, class = "ROGUE",
                    race = "Orc" },
                assists = {}, mapID = 1429, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
        end
    end

    local function Flow()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
        H.Advance(0.5)
        for _ = 1, 3 do H.Advance(0) end
    end

    local function Popups()
        local n = 0
        for _, p in ipairs(H.popups) do if p.which == "HEADHUNTER_ALERT" then n = n + 1 end end
        return n
    end

    T.case("the window: outlaw level -5 to +9; skull: no upper bound; unknown: everyone", function()
        local W = H.Boot({ client = "era", levelWindow = true }).Wanted
        local level20 = { level = 20 }
        T.eq(W.InLevelWindow(level20, 14), false, "20 - 6")
        T.eq(W.InLevelWindow(level20, 15), true, "20 - 5")
        T.eq(W.InLevelWindow(level20, 29), true, "20 + 9")
        T.eq(W.InLevelWindow(level20, 30), false, "20 + 10: that would be ganking the ganker")
        local level60 = { level = 60 }
        T.eq(W.InLevelWindow(level60, 55), true, "60 - 5")
        T.eq(W.InLevelWindow(level60, 54), false, "60 - 6")
        local skull = { level = -1, levelMin = 40 }
        T.eq(W.InLevelWindow(skull, 34), false, "skull, min 40: 34 is too low")
        T.eq(W.InLevelWindow(skull, 35), true, "35")
        T.eq(W.InLevelWindow(skull, 60), true, "no upper bound")
        T.eq(W.InLevelWindow({}, 10), true, "level unknown: do not hide it")
    end)

    T.case("outside the window: a chat line, no popup, no center text", function()
        local ns = H.Boot({ client = "era", levelWindow = true }) -- the player is 30
        Spree(ns, 60, 5)
        Flow()
        T.eq(#ns.Wanted:List(), 1, "WANTED")
        T.eq(Popups(), 0, "no popup for a level 30 about a level 60")
        T.eq(#H.centerTexts, 0, "no center text")
        T.ok(H.Printed("not your level range"), "a chat line says why")
        T.noErrors()
    end)

    T.case("inside the window: the usual popup", function()
        local ns = H.Boot({ client = "era", levelWindow = true })
        Spree(ns, 33, 5)
        Flow()
        T.eq(Popups(), 1, "popup for a level 30 about a level 33")
    end)

    T.case("outside the window a decline costs nothing", function()
        local ns = H.Boot({ client = "era", levelWindow = true })
        ns.db.marks.total = 5
        Spree(ns, 60, 5)
        Flow()
        ns.Posse:Decline(ns.Wanted:ByKey("Gank-Stonespine"), {})
        T.eq(ns.Marks:Total(), 5, "no penalty")
    end)

    T.case("/hh debug levels off|on", function()
        local ns = H.Boot({ client = "era", levelWindow = true })
        T.eq(ns.Wanted.LevelWindowOff(), false, "on by default")
        H.Slash("debug levels off")
        T.eq(ns.Wanted.LevelWindowOff(), true, "off")
        T.ok(H.Printed("level window OFF"), "said so")
        T.eq(ns.Wanted.InLevelWindow({ level = 60 }, 30), true, "every level while off")
        H.Slash("debug levels on")
        T.eq(ns.Wanted.LevelWindowOff(), false, "on again")
    end)
end
