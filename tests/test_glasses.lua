-- Raise a glass to a catch (Sync/Glasses.lua): any HeadHunter, one per catch, never to
-- their own, shared with the others, and the website's count when it is larger.
-- Made-up players only.

return function(T, H)
    local function Wait(seconds)
        for _ = 1, seconds do H.Advance(1) end
    end

    -- A catch of Grim Reaper by `hunter` (another HeadHunter by default)
    local function Catch(ns, hunter)
        local t = H.serverTime - 60
        return ns.Justice:Add({ id = "Grim Reaper:" .. t, outlaw = "Grim Reaper", t = t, mapID = 1436,
            killer = hunter or "Kestrel Vane", hunter = hunter or "Kestrel Vane" }, "peer", hunter or "Kestrel Vane")
    end

    -- Every HeadHunter card shown (UI/Toast.lua)
    local function Cards(ns)
        local shown = {}
        local show = ns.Toast.Show
        ns.Toast.Show = function(toast, notice)
            shown[#shown + 1] = notice
            return show(toast, notice)
        end
        return shown
    end

    local function Sent()
        local found = 0
        for _, m in ipairs(H.sent) do
            if m.message:find("Y:", 1, true) or m.message:find("|Y|", 1, true) then found = found + 1 end
        end
        return found
    end

    T.case("protocol: a glass from the popup says so; older 4-field glasses still read", function()
        local P = H.Boot({ client = "forever" }).Protocol
        local g = P.DecodeGlass(P.EncodeGlass({ outlaw = "Grim Reaper", caughtAt = 100, t = 160, by = "Rowan Ash", popup = true }))
        T.eq(g.popup, true, "from the popup")
        T.eq(g.by, "Rowan Ash", "by")
        T.eq(P.DecodeGlass(P.EncodeGlass({ outlaw = "Grim Reaper", caughtAt = 100, t = 160, by = "Rowan Ash" })).popup, nil,
            "from the list")
        T.eq(P.DecodeGlass("Grim Reaper;2s;4g"), nil, "broken")
    end)

    T.case("protocol: a catch carries the hunter's level; one without it still reads", function()
        local P = H.Boot({ client = "forever" }).Protocol
        local who = { class = "HUNTER", race = "Dwarf", faction = "Alliance", sex = 3, level = 42 }
        local _, _, _, killer, read = P.DecodeJustice(P.EncodeJustice("Grim Reaper", 100, 1436, "Kestrel Vane", who))
        T.eq(killer, "Kestrel Vane", "the hunter")
        T.eq(read.level, 42, "level")
        T.eq(read.class, "HUNTER", "class")
        local old = P.EncodeJustice("Grim Reaper", 100, 1436, "Kestrel Vane", { class = "HUNTER", race = "Dwarf",
            faction = "Alliance", sex = 3 })
        T.eq(select(5, P.DecodeJustice(old)).level, nil, "no level")
    end)

    T.case("a peer's bust: a popup asks to raise a glass, and that glass counts for the Barflies", function()
        local ns = H.Boot({ client = "forever" })
        local catch = Catch(ns)
        local cards = Cards(ns)
        H.inCombat = true
        ns.JusticeAlerts:AskGlass(catch, "Grim Reaper")
        T.eq(#cards, 0, "not in combat")
        H.Advance(ns.JusticeAlerts.GLASS_WAIT + 5)
        H.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        T.eq(#cards, 0, "too late after the fight: dropped")

        ns.JusticeAlerts:AskGlass(catch, "Grim Reaper")
        T.eq(#cards, 1, "the HeadHunter card")
        T.eq(ns.Toast:IsShown(), true, "on show")
        T.eq(#H.popups, 0, "not the game's popup")
        T.eq(cards[1].title, "Grim Reaper", "the outlaw on the poster")
        T.eq(cards[1].stamp, "BUSTED", "the red stamp")
        T.eq(cards[1].decline, "Cancel", "two buttons")
        T.ok(cards[1].text:find("Busted by Kestrel Vane", 1, true) ~= nil, cards[1].text)
        ns.Toast:Accept()
        T.eq(ns.Toast:IsShown(), false, "closed by the button")
        local mine
        for _, g in ns.Glasses:All() do mine = g end
        T.eq(mine.popup, true, "raised from the popup")

        ns.JusticeAlerts:AskGlass(catch, "Grim Reaper")
        T.eq(#cards, 1, "not again once raised")
        T.noErrors()
    end)

    T.case("five busts in a minute: one glass popup, the next after the gap (3 to 15 min)", function()
        local ns = H.Boot({ client = "forever" })
        local cards = Cards(ns)
        for i = 1, 5 do
            local t = H.serverTime - i
            local catch = ns.Justice:Add({ id = "Outlaw" .. i .. " Smith:" .. t, outlaw = "Outlaw" .. i .. " Smith", t = t,
                killer = "Kestrel Vane", hunter = "Kestrel Vane" }, "peer", "Kestrel Vane")
            ns.JusticeAlerts:AskGlass(catch, "Outlaw" .. i)
            H.Advance(10)
        end
        T.eq(#cards, 1, "one card for five busts")
        T.eq(ns.JusticeAlerts.GlassGap(), 300, "5 minutes by default")
        ns.db.settings.alerts.glassPopupGap = 1
        T.eq(ns.JusticeAlerts.GlassGap(), 180, "at least 3")
        ns.db.settings.alerts.glassPopupGap = 60
        T.eq(ns.JusticeAlerts.GlassGap(), 900, "at most 15")
        ns.db.settings.alerts.glassPopupGap = 5
        H.Advance(300)
        local t = H.serverTime - 1
        local later = ns.Justice:Add({ id = "Late Gank:" .. t, outlaw = "Late Gank", t = t, killer = "Kestrel Vane",
            hunter = "Kestrel Vane" }, "peer", "Kestrel Vane")
        ns.JusticeAlerts:AskGlass(later, "Late")
        T.eq(#cards, 2, "after the gap: the next one")
        T.noErrors()
    end)

    T.case("/hh dev glass: the popup at once, and a test glass is never saved or sent", function()
        local ns = H.Boot({ client = "forever" })
        _G.HeadHunter_Dev = {}
        local cards = Cards(ns)
        H.Slash("dev glass")
        T.eq(#cards, 1, "the card")
        T.eq(cards[1].title, "Grim Reaver", "a made-up bust")
        T.ok(cards[1].titleInfo:find("Level 30", 1, true) ~= nil, "the outlaw's level: " .. cards[1].titleInfo)
        T.ok(cards[1].textInfo:find("Level 30", 1, true) ~= nil, "the hunter's level")
        T.ok(cards[1].textInfo:find("|T", 1, true) ~= nil, "icons, no class name")
        T.eq(cards[1].textInfo:find("Hunter", 1, true), nil, "no class name")
        H.sent = {}
        ns.Toast:Accept()
        local count = 0
        for _ in ns.Glasses:All() do count = count + 1 end
        T.eq(count, 0, "not saved")
        H.Advance(10)
        T.eq(#H.sent, 0, "not sent")
        H.Slash("dev glass")
        T.eq(#cards, 2, "again at once: the gap does not apply to the test")
        _G.HeadHunter_Dev = nil
        T.noErrors()
    end)

    T.case("no glass popup when turned off, or inside an instance", function()
        local ns = H.Boot({ client = "forever" })
        local catch = Catch(ns)
        local cards = Cards(ns)
        ns.db.settings.alerts.glassPopup = false
        ns.JusticeAlerts:AskGlass(catch, "Grim Reaper")
        T.eq(#cards, 0, "turned off")
        ns.db.settings.alerts.glassPopup = true
        H.instance = { true, "pvp" }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        ns.JusticeAlerts:AskGlass(catch, "Grim Reaper")
        T.eq(#cards, 0, "in a battleground")
        T.noErrors()
    end)

    T.case("we raise a glass once, it is shared, and the count shows", function()
        local ns = H.Boot({ client = "forever" })
        local catch = Catch(ns)
        T.eq(ns.Glasses:CanRaise(catch), true, "another hunter's catch")
        H.sent = {}
        T.ok(ns.Glasses:Raise(catch) ~= nil, "raised")
        Wait(10)
        T.ok(#H.sent > 0, "sent to the others")
        T.eq(ns.Glasses:Count(catch), 1, "one glass")
        T.eq(ns.Glasses:CanRaise(catch), false, "once per catch")
        T.eq(ns.Glasses:Raise(catch), nil, "not twice")
        T.noErrors()
    end)

    T.case("never to our own catch", function()
        local ns = H.Boot({ client = "forever" })
        local catch = Catch(ns, ns.Utils.UnitKey("player"))
        T.eq(ns.Glasses:CanRaise(catch), false, "our own catch")
        T.eq(ns.Glasses:Raise(catch), nil, "not raised")
        T.noErrors()
    end)

    T.case("peers: only for themselves, never to their own catch, under a limit", function()
        local ns = H.Boot({ client = "forever" })
        local P = ns.Protocol
        local catch = Catch(ns)
        local function Glass(by, sender)
            H.Deliver(P.Pack("A", P.TYPES.GLASS, { P.EncodeGlass({ outlaw = "Grim Reaper", caughtAt = catch.t,
                t = H.serverTime, by = by }) }), sender or by)
        end
        Glass("Rowan Ash")
        T.eq(ns.Glasses:Count(catch), 1, "a peer's glass")
        Glass("Rowan Ash")
        T.eq(ns.Glasses:Count(catch), 1, "one per HeadHunter")
        Glass("Other Name", "Rowan Ash")
        T.eq(ns.Glasses:Count(catch), 1, "nobody raises one for someone else")
        Glass("Kestrel Vane")
        T.eq(ns.Glasses:Count(catch), 1, "the hunter never to their own catch")
        T.eq(select(2, ns.Glasses:Of(catch)), false, "not ours")
        T.eq(ns.Glasses:CanRaise(catch), true, "we still can")
        T.noErrors()
    end)

    T.case("a glass to our catch: a chat line, several close together in one", function()
        local ns = H.Boot({ client = "forever" })
        local P = ns.Protocol
        local catch = Catch(ns, ns.Utils.UnitKey("player"))
        local function Glass(by)
            H.Deliver(P.Pack("A", P.TYPES.GLASS, { P.EncodeGlass({ outlaw = "Grim Reaper", caughtAt = catch.t,
                t = H.serverTime, by = by }) }), by)
        end
        local function Said(text)
            for _, line in ipairs(H.printed) do
                if tostring(line):find(text, 1, true) then return true end
            end
            return false
        end
        Glass("Rowan Ash")
        H.Advance(ns.JusticeAlerts.THANKS_WAIT + 1)
        T.ok(Said("Rowan Ash raised a glass to your catch of Grim Reaper!"), "one glass")

        -- Kestrel Vane's catch of another outlaw: not ours
        local t = H.serverTime - 30
        ns.Justice:Add({ id = "Dusk Fang:" .. t, outlaw = "Dusk Fang", t = t, killer = "Kestrel Vane",
            hunter = "Kestrel Vane" }, "peer", "Kestrel Vane")
        H.Deliver(P.Pack("A", P.TYPES.GLASS, { P.EncodeGlass({ outlaw = "Dusk Fang", caughtAt = t,
            t = H.serverTime, by = "Moss Walker" }) }), "Moss Walker")
        H.Advance(ns.JusticeAlerts.THANKS_WAIT + 1)
        T.ok(not Said("Moss Walker"), "not our catch")

        T.noErrors()
    end)

    T.case("glasses to our catch close together make one line; none when turned off", function()
        local ns = H.Boot({ client = "forever" })
        local P = ns.Protocol
        local catch = Catch(ns, ns.Utils.UnitKey("player"))
        local function Glass(by)
            H.Deliver(P.Pack("A", P.TYPES.GLASS, { P.EncodeGlass({ outlaw = "Grim Reaper", caughtAt = catch.t,
                t = H.serverTime, by = by }) }), by)
        end
        local function Count(text)
            local n = 0
            for _, line in ipairs(H.printed) do
                if tostring(line):find(text, 1, true) then n = n + 1 end
            end
            return n
        end
        Glass("Rowan Ash")
        H.Advance(2)
        Glass("Moss Walker")
        Glass("Tarn Ironhoof")
        H.Advance(ns.JusticeAlerts.THANKS_WAIT)
        T.eq(Count("Rowan Ash and 2 others raised a glass to your catch of Grim Reaper!"), 1, "one line")
        T.eq(Count("Moss Walker"), 0, "not each one")

        ns.db.settings.alerts.glassThanks = false
        Glass("Wren Duskmantle")
        H.Advance(ns.JusticeAlerts.THANKS_WAIT + 1)
        T.eq(Count("Wren Duskmantle"), 0, "turned off")
        T.noErrors()
    end)

    T.case("the website's count when it is larger", function()
        local ns = H.Boot({ client = "forever" })
        local catch = Catch(ns)
        ns.Glasses:Raise(catch)
        local site = ns.SiteData.Glasses
        ns.SiteData.Glasses = function() return 7 end
        T.eq(ns.Glasses:Count(catch), 7, "the website knows more")
        ns.SiteData.Glasses = site
        T.eq(ns.Glasses:Count(catch), 1, "ours without it")
        T.noErrors()
    end)

    T.case("the Busted list: a mug with the count, raised with a click", function()
        local ns = H.Boot({ client = "forever" })
        Catch(ns)
        local glass = ns.MainWindow.Rows("busted")[1].actions[1]
        T.eq(glass.kind, "glass", "the mug")
        T.eq(glass.count, 0, "no glasses yet")
        T.eq(glass.canRaise, true, "we may raise one")
        T.eq(glass.raised, false, "not raised")
        T.ok(ns.MainWindow.Rows("busted")[1].tooltip[3]:find("click the mug to raise a glass", 1, true) ~= nil,
            "the row says how to raise one")
        ns.MainWindow:OnRowAction(nil, glass)
        local row = ns.MainWindow.Rows("busted")[1]
        T.eq(row.actions[1].count, 1, "raised")
        T.eq(row.actions[1].raised, true, "ours")
        T.eq(row.actions[1].canRaise, false, "once")
        T.ok(row.tooltip[3]:find("Glasses raised: 1", 1, true) ~= nil, "tooltip: " .. row.tooltip[3])

        -- Drawn: the mug button, no text button
        H.Slash("")
        ns.MainWindow:SelectSection("busted")
        local drawn = ns.MainWindow.shownRows and ns.MainWindow.shownRows[1]
        T.ok(drawn ~= nil, "a row drawn")
        T.noErrors()
    end)
end
