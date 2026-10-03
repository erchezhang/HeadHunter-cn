-- HH-041 alert framework and HH-042 sighting alert.

return function(T, H)
    local function Settle()
        H.Advance(1)
        for _ = 1, 20 do H.Advance(0) end
    end

    local function Alert(key, extra)
        local a = { key = key, text = "center " .. key, chat = "chat " .. key, sound = true }
        for k, v in pairs(extra or {}) do a[k] = v end
        return a
    end

    -------------------------------------------------
    -- Framework
    -------------------------------------------------

    T.case("an alert shows center text, a chat line and a sound; the same key is throttled", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.Alerts:Show(Alert("a")), true, "shown")
        T.eq(H.centerTexts[1], "center a", "center text")
        T.ok(H.Printed("chat a"), "chat line")
        T.eq(#H.sounds, 1, "sound")
        T.eq(ns.Alerts:Show(Alert("a")), false, "throttled")
        H.clock = H.clock + 61
        T.eq(ns.Alerts:Show(Alert("a")), true, "after the throttle")
        T.eq(ns.Alerts:Show(Alert("b")), true, "other keys are independent")
        T.noErrors()
    end)

    T.case("in combat alerts wait and show when combat ends, once per key", function()
        local ns = H.Boot({ client = "era" })
        H.inCombat = true
        T.eq(ns.Alerts:Show(Alert("x", { chat = "old" })), "queued", "queued")
        T.eq(ns.Alerts:Show(Alert("x", { chat = "new" })), "queued", "queued again")
        T.eq(ns.Alerts:Show(Alert("y")), "queued", "second key")
        T.eq(#H.centerTexts, 0, "nothing shown in combat")
        T.eq(ns.Alerts:QueuedCount(), 2, "merged per key")
        H.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        T.eq(#H.centerTexts, 2, "both shown after combat")
        T.ok(H.Printed("^.*new$"), "newest version of a merged alert")
        T.ok(not H.Printed("^.*old$"), "older version dropped")
        T.eq(ns.Alerts:QueuedCount(), 0, "queue empty")
    end)

    T.case("alerts that waited too long are dropped", function()
        local ns = H.Boot({ client = "era" })
        H.inCombat = true
        ns.Alerts:Show(Alert("stale"))
        H.clock = H.clock + 90
        H.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        T.eq(#H.centerTexts, 0, "stale alert dropped")
    end)

    T.case("never inside instances; entering one drops the queue", function()
        local ns = H.Boot({ client = "era" })
        H.inCombat = true
        ns.Alerts:Show(Alert("queued-before"))
        H.instance = { true, "pvp" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        T.eq(ns.Alerts:Show(Alert("inside")), false, "dropped inside")
        H.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        H.instance = { false, "none" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        H.Fire("PLAYER_REGEN_ENABLED")
        T.eq(#H.centerTexts, 0, "nothing leaked out of the instance")
    end)

    T.case("settings: alerts off, sound off", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("alerts sound off")
        ns.Alerts:Show(Alert("quiet"))
        T.eq(#H.centerTexts, 1, "shown")
        T.eq(#H.sounds, 0, "no sound")
        H.Slash("alerts off")
        T.eq(ns.Alerts:Show(Alert("off")), false, "alerts disabled")
        H.Slash("alerts")
        T.ok(H.Printed("Alerts: off · sound: off · range: adjacent"), "status")
        H.Slash("alerts on")
        H.Slash("alerts test")
        T.ok(H.Printed("alert test"), "test alert")
        T.noErrors()
    end)

    T.case("popups go through one StaticPopup with callbacks", function()
        local ns = H.Boot({ client = "era" })
        local accepted, declined = false, false
        ns.Alerts:Show(Alert("p", { popup = { text = "Join?", accept = "Join", decline = "Decline",
            onAccept = function() accepted = true end, onDecline = function() declined = true end } }))
        T.eq(H.popups[#H.popups].which, "HEADHUNTER_ALERT", "popup shown")
        local dialog = _G.StaticPopupDialogs.HEADHUNTER_ALERT
        T.eq(dialog.text, "Join?", "text")
        T.eq(dialog.button1, "Join", "accept label")
        dialog.OnAccept()
        T.eq(accepted, true, "accept callback")
        dialog.OnCancel()
        T.eq(declined, true, "decline callback")
    end)

    local function PopupAlert(key, dialog)
        return Alert(key, { popup = { dialog = dialog, text = "Join " .. key .. "?", accept = "Join", decline = "Decline" } })
    end

    local function PopupCount()
        local n = 0
        for _, p in ipairs(H.popups) do
            if p.which == "HEADHUNTER_ALERT" or p.which == "HEADHUNTER_HOTSPOT" then n = n + 1 end
        end
        return n
    end

    T.case("popups at least 3 minutes apart; one that comes sooner is a chat line only", function()
        local ns = H.Boot({ client = "era" })
        ns.Alerts:Show(PopupAlert("first"))
        T.eq(PopupCount(), 1, "first popup")
        ns.Alerts:Show(PopupAlert("hot", ns.Alerts.HOTSPOT_POPUP))
        T.eq(PopupCount(), 1, "a hotspot popup waits for the gap too")
        T.ok(H.Printed("chat hot"), "its chat line")
        T.eq(#H.centerTexts, 1, "no center text")
        T.eq(#H.sounds, 1, "no sound")
        H.clock = H.clock + ns.Alerts.POPUP_GAP
        ns.Alerts:Show(PopupAlert("later"))
        T.eq(PopupCount(), 2, "after 3 minutes")
        ns.Alerts:Show(PopupAlert("era", ns.Alerts.JUSTICE_POPUP))
        T.eq(H.popups[#H.popups].which, "HEADHUNTER_JUSTICE", "our own catch is not held back")
    end)

    T.case("after combat only the newest waiting popup is shown", function()
        local ns = H.Boot({ client = "era" })
        H.inCombat = true
        ns.Alerts:Show(PopupAlert("older"))
        H.clock = H.clock + 5
        ns.Alerts:Show(PopupAlert("newer", ns.Alerts.HOTSPOT_POPUP))
        ns.Alerts:Show(Alert("plain"))
        H.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        T.eq(PopupCount(), 1, "one popup")
        T.eq(H.popups[#H.popups].which, "HEADHUNTER_HOTSPOT", "the newest")
        T.ok(H.Printed("chat older"), "the older one as a chat line")
        T.eq(#H.sounds, 2, "sounds: the newest popup and the plain alert")
    end)

    T.case("a popup that times out calls decline with the reason", function()
        local ns = H.Boot({ client = "era" })
        local reason
        ns.Alerts:Show(Alert("t", { popup = { text = "Join?", accept = "Join", decline = "Decline",
            onDecline = function(why) reason = why end } }))
        _G.StaticPopupDialogs.HEADHUNTER_ALERT.OnCancel(nil, nil, "timeout")
        T.eq(reason, "timeout", "reason passed on")
    end)

    -------------------------------------------------
    -- Sighting (HH-042)
    -------------------------------------------------

    local function WantedGank(ns)
        H.Slash("spree Gank 5 60 60 40")
        Settle()
        T.eq(ns.Wanted:ByKey("Gank-Firemaw").wanted, true, "precondition: Gank is WANTED")
    end

    local function GankPlate(level)
        return { name = "Gank", level = level or -1, class = "ROGUE", race = "Orc", sex = 2,
            faction = "Horde", isPlayer = true, guid = "Player-2-GANK" }
    end

    T.case("a WANTED outlaw on a nameplate raises a sighting alert", function()
        local ns = H.Boot({ client = "era" })
        WantedGank(ns)
        H.units.nameplate1 = GankPlate()
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        T.eq(#H.centerTexts, 1, "center text")
        T.ok(H.centerTexts[1]:find("WANTED") and H.centerTexts[1]:find("Gank"), "names the outlaw")
        local expected, found = "spotted (" .. ns.Utils.SKULL_TEXT .. " Orc Rogue)", false
        for _, line in ipairs(H.printed) do found = found or line:find(expected, 1, true) ~= nil end
        T.ok(found, "chat line with the skull icon (not ??), race, class")
        T.ok(H.Printed("Bully"), "badge")
        T.eq(#H.sounds, 1, "sound")
        T.noErrors()
    end)

    T.case("an outlaw at large on a nameplate alerts like WANTED", function()
        local ns = H.Boot({ client = "era" })
        WantedGank(ns)
        H.serverTime = H.serverTime + 8 * 86400
        H.Advance(61)
        Settle()
        T.eq(ns.Wanted:ByKey("Gank-Firemaw").atLarge, true, "at large")
        H.units.nameplate1 = GankPlate()
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        T.ok(H.centerTexts[#H.centerTexts]:find("At large", 1, true) ~= nil, "center text")
        T.ok(H.Printed("At large.*Gank.*spotted.*was .*Ganker"), "chat line with the last rank")
        T.eq(#H.sounds, 1, "sound")
    end)

    T.case("the same outlaw alerts again only after 5 minutes", function()
        local ns = H.Boot({ client = "era" })
        WantedGank(ns)
        H.units.target = GankPlate()
        H.Fire("PLAYER_TARGET_CHANGED")
        H.clock = H.clock + 30
        H.Fire("PLAYER_TARGET_CHANGED")
        T.eq(#H.centerTexts, 1, "throttled")
        H.clock = H.clock + 200
        H.Fire("PLAYER_TARGET_CHANGED")
        T.eq(#H.centerTexts, 1, "still throttled after 3 minutes and a half")
        H.clock = H.clock + 80
        H.Fire("PLAYER_TARGET_CHANGED")
        T.eq(#H.centerTexts, 2, "alerts again")
    end)

    T.case("enemies who are not WANTED raise nothing", function()
        local ns = H.Boot({ client = "era" })
        H.Slash("spree Gank 2 60 45 40") -- 5 levels apart: no bully either
        Settle()
        H.units.nameplate1 = GankPlate()
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.units.nameplate2 = { name = "Nobody", faction = "Horde", isPlayer = true, guid = "Player-3" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        T.eq(#H.centerTexts, 0, "silent")
    end)

    T.case("seen during combat: shown at once, not again after combat", function()
        local ns = H.Boot({ client = "era" })
        WantedGank(ns)
        H.inCombat = true
        H.units.nameplate1 = GankPlate()
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        T.eq(#H.centerTexts, 1, "shown in combat")
        T.eq(#H.sounds, 1, "with sound")
        H.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        T.eq(#H.centerTexts, 1, "not repeated when combat ends")
    end)

    T.case("combat alerts with a popup still wait for combat to end", function()
        local ns = H.Boot({ client = "era" })
        H.inCombat = true
        T.eq(ns.Alerts:Show(Alert("p", { combat = true, popup = { text = "x" } })), "queued", "popup waits")
        T.eq(ns.Alerts:Show(Alert("c", { combat = true, text = "now" })), true, "no popup: at once")
    end)

    T.case("forever: an outlaw known only by GUID is recognised when seen", function()
        local ns = H.Boot({ client = "forever" })
        for i = 1, 5 do
            ns.Reports:Add({
                id = "Victim Number" .. i .. ":" .. (H.serverTime - i * 60),
                t = H.serverTime - i * 60,
                victim = { key = "Victim Number" .. i, level = 20 },
                killer = { guid = "Player-7", name = "Kuh", nameIncomplete = true },
                assists = {}, confidence = "exact",
            }, "peer")
        end
        Settle()
        T.eq(ns.Wanted:Get("guid:Player-7").wanted, true, "precondition: WANTED by GUID")
        H.units.nameplate1 = { name = "Kuh", realm = "Blam", level = 22, class = "HUNTER", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-7" }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        T.eq(#H.centerTexts, 1, "sighting alert")
        T.ok(H.centerTexts[1]:find("Kuh Blam", 1, true) ~= nil, "shown with the full name just learned")
        T.noErrors()
    end)
end
