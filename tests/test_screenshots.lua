-- HH-132: screenshots of our PvP deaths and catches, for the sync app.

return function(T, H)
    local SITE = { format_version = 1, worlds = {} }

    local function Boot(opts)
        opts = opts or {}
        local site = SITE
        if opts.noSync then site = nil end
        local ns = H.Boot({ client = "forever", siteData = site })
        local shots, quality = {}, "3"
        _G.Screenshot = function() shots[#shots + 1] = quality end
        _G.GetCVar = function(name) return name == "screenshotQuality" and quality or nil end
        _G.SetCVar = function(name, value) if name == "screenshotQuality" then quality = value end end
        if opts.on ~= false then ns.Database:SetSetting("screenshots", true) end
        return ns, shots, function() return quality end
    end

    local function Death(killer, classification, t)
        return { id = "Me:" .. (t or H.serverTime), t = t or H.serverTime, classification = classification or "coward",
            killer = { key = killer or "Grim Reaper" }, confidence = "exact" }
    end

    T.case("on by default, can be turned off, and greyed out without HeadHunter Sync", function()
        local ns, shots = Boot({ on = false })
        T.eq(ns.Database:GetSetting("screenshots"), true, "on by default")
        ns.Database:SetSetting("screenshots", false)
        ns.Screenshots:OnDeathRecorded(Death())
        T.eq(#shots, 0, "no picture while off")
        local option = ns.SettingsPanel.Option("screenshots")
        T.eq(ns.SettingsPanel.Available(option), true, "available with the app")

        ns, shots = Boot({ noSync = true })
        T.eq(ns.SettingsPanel.Available(ns.SettingsPanel.Option("screenshots")), false, "needs HeadHunter Sync")
        ns.Screenshots:OnDeathRecorded(Death())
        T.eq(#shots, 0, "no picture without the app, even when on")
    end)

    T.case("a coward death gets a picture at the lowest quality, and the player's quality comes back", function()
        local ns, shots, quality = Boot()
        ns.Screenshots:OnDeathRecorded(Death())
        T.eq(#shots, 1, "one picture")
        T.eq(shots[1], "1", "taken at quality 1")
        T.eq(quality(), "1", "kept until the game wrote it")
        H.Fire("SCREENSHOT_SUCCEEDED")
        T.eq(quality(), "3", "the player's own quality is back")
        local shot = ns.db.screenshots.shots[1]
        T.eq(shot.kinds[1], "death", "kind")
        T.eq(shot.refs[1], "Me:" .. H.serverTime, "the death report")
        T.eq(shot.target, "Grim Reaper", "the killer")
        T.ok(shot.file:match("^WoWScrnShot_%d%d%d%d%d%d_%d%d%d%d%d%d$") ~= nil, "the file name the game uses: " .. shot.file)
        T.noErrors()
    end)

    T.case("every death by an enemy player gets a picture, fair or not; never a simulation", function()
        local ns, shots = Boot()
        ns.Screenshots:OnDeathRecorded(Death("Fair Fighter", "fair"))
        T.eq(#shots, 1, "a fair death counts toward WANTED, so it gets one")
        ns.Screenshots:OnDeathRecorded({ id = "y", t = H.serverTime, classification = "unknown", killer = { name = "?" } })
        T.eq(#shots, 1, "no picture without a known killer")
        ns.Screenshots:OnDeathRecorded({ id = "x", t = 1, classification = "coward", killer = { key = "Sim" }, confidence = "sim" })
        T.eq(#shots, 1, "never for a simulation")
    end)

    T.case("one picture per killer an hour, a daily cap, and events close together share one", function()
        local ns, shots = Boot()
        ns.Screenshots:OnDeathRecorded(Death("Grim Reaper"))
        H.serverTime = H.serverTime + 60
        ns.Screenshots:OnDeathRecorded(Death("Grim Reaper", nil, H.serverTime))
        T.eq(#shots, 1, "camped by the same killer: one picture")
        H.serverTime = H.serverTime + 2
        ns.Events:Fire("HH_JUSTICE_ADDED", { id = "Brute:1", outlaw = "Brute", t = H.serverTime, origin = "local" })
        T.eq(#shots, 2, "a catch is its own picture")
        H.serverTime = H.serverTime + 2
        ns.Events:Fire("HH_SHAME_KILLED", { id = "Bully", key = "Bully" }, "bully")
        T.eq(#shots, 2, "two seconds later: the same picture")
        T.eq(table.concat(ns.db.screenshots.shots[2].kinds, ","), "wanted,bully", "both kinds on it")

        H.serverTime = H.serverTime + ns.Screenshots.WINDOW
        ns.Screenshots:OnDeathRecorded(Death("Grim Reaper", nil, H.serverTime))
        T.eq(#shots, 3, "a new picture after an hour")

        ns.db.screenshots.day.count = ns.Screenshots.DAY_CAP
        H.serverTime = H.serverTime + 60
        ns.Events:Fire("HH_SHAME_KILLED", { id = "Payless", key = "Payless" }, "deadbeat")
        T.eq(#shots, 3, "no more after the daily cap")
        T.noErrors()
    end)

    T.case("each of our deaths keeps what happened with its picture, for the website", function()
        local ns = Boot()
        local first, again = Death("Grim Reaper"), Death("Grim Reaper", nil, H.serverTime + 60)
        ns.Screenshots:OnDeathRecorded(first)
        H.serverTime = H.serverTime + 60
        ns.Screenshots:OnDeathRecorded(again)
        T.eq(first.shot, "taken", "a picture")
        T.eq(again.shot, "limit", "the same killer within the hour")
        ns.Database:SetSetting("screenshots", false)
        local off = Death("Other Killer", nil, H.serverTime + 120)
        ns.Screenshots:OnDeathRecorded(off)
        T.eq(off.shot, "off", "the option was off")

        ns = Boot({ noSync = true })
        local noApp = Death()
        ns.Screenshots:OnDeathRecorded(noApp)
        T.eq(noApp.shot, "no_app", "HeadHunter Sync is not installed")
    end)

    T.case("another player's catch and demo catches get no picture", function()
        local ns, shots = Boot()
        ns.Events:Fire("HH_JUSTICE_ADDED", { id = "Brute:1", outlaw = "Brute", t = H.serverTime, origin = "peer" })
        ns.Events:Fire("HH_JUSTICE_ADDED", { id = "Brute:2", outlaw = "Brute", t = H.serverTime, origin = "sim", demo = true })
        T.eq(#shots, 0, "only our own catches")
        T.eq(#ns.db.screenshots.shots, 0, "nothing listed")
    end)
end
