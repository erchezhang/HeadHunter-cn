-- HH-110: HeadHunters online (Sync/Presence.lua). Made-up players only.

return function(T, H)
    local function Here(ns, faction, version)
        return ns.Protocol.Pack(faction, ns.Protocol.TYPES.PRESENCE, { version or "0.1.7" })
    end

    local function SentPresence(ns)
        local found = 0
        for _, m in ipairs(H.sent) do
            if m.message:find("^%d%a" .. ns.Protocol.TYPES.PRESENCE .. ":") then found = found + 1 end
        end
        return found
    end

    T.case("you alone count as one, on your faction", function()
        local ns = H.Boot({ client = "forever" })
        local count = ns.Presence:Count()
        T.eq(count.total, 1, "you")
        T.eq(count.Alliance, 1, "your faction")
        T.eq(count.Horde, 0, "other faction")
        T.eq(count.scope, "region", "Forever reaches the region")
        T.noErrors()
    end)

    T.case("players heard on Forever count per faction, the other faction too", function()
        local ns = H.Boot({ client = "forever" })
        H.Deliver(Here(ns, "A"), "Iron Maple")
        H.Deliver(Here(ns, "H", "0.1.6"), "Grim Tusk")
        H.Deliver(Here(ns, "A"), "Iron Maple") -- the same player twice
        local count = ns.Presence:Count()
        T.eq(count.total, 3, "you and two others")
        T.eq(count.Alliance, 2, "Alliance")
        T.eq(count.Horde, 1, "Horde")
        T.eq(ns.Presence:Versions()["0.1.6"], 1, "their version")
        T.noErrors()
    end)

    T.case("any message shows its sender is online, not only presence", function()
        local ns = H.Boot({ client = "forever" })
        H.Deliver(ns.Protocol.Pack("H", ns.Protocol.TYPES.PING, { "hello" }), "Grim Tusk")
        T.eq(ns.Presence:Count().Horde, 1, "a ping from the other faction counts")
        T.noErrors()
    end)

    T.case("players not heard within the window drop out", function()
        local ns = H.Boot({ client = "forever" })
        H.Deliver(Here(ns, "A"), "Iron Maple")
        H.Advance(ns.Presence.WINDOW - 60)
        T.eq(ns.Presence:Count().total, 2, "still online")
        H.Advance(120)
        T.eq(ns.Presence:Count().total, 1, "gone")
        T.noErrors()
    end)

    T.case("we say here after login and answer a newcomer once", function()
        local ns = H.Boot({ client = "forever" })
        H.Advance(ns.Presence.FIRST_DELAY)
        H.Advance(ns.Transport.FLUSH_INTERVAL)
        -- The catch-up hello counts as being here (HH-116): when it went out first, the
        -- first presence is skipped on purpose; which one goes out first is timing
        local hello = 0
        for _, m in ipairs(H.sent) do
            if m.message:find("^%d%a" .. ns.Protocol.TYPES.QUERY .. ":h") then hello = hello + 1 end
        end
        local first = SentPresence(ns)
        T.eq(first + math.min(hello, 1) >= 1, true, "here after login (presence or the catch-up hello)")

        H.Deliver(Here(ns, "A"), "Iron Maple")
        H.Advance(ns.Presence.ANSWER_DELAY)
        H.Advance(ns.Transport.FLUSH_INTERVAL)
        T.eq(SentPresence(ns), first + 1, "answered the newcomer")

        H.Deliver(Here(ns, "H"), "Grim Tusk")
        H.Advance(ns.Presence.ANSWER_DELAY)
        H.Advance(ns.Transport.FLUSH_INTERVAL)
        T.eq(SentPresence(ns), first + 1, "no second answer within the cooldown")
        T.noErrors()
    end)

    T.case("with many online only about 5 answer a newcomer", function()
        local ns = H.Boot({ client = "forever" })
        T.eq(ns.Presence.AnswerChance(4), 1, "few online: we answer")
        T.eq(ns.Presence.AnswerChance(1001), 5 / 1000, "1000 others: 5 of them")
        for i = 1, 50 do ns.Presence:Heard("Rider Number" .. i, "Alliance") end
        H.Advance(ns.Presence.ANSWER_COOLDOWN + ns.Presence.ANSWER_DELAY)
        H.Advance(ns.Transport.FLUSH_INTERVAL)
        local before = SentPresence(ns)
        local random = math.random
        math.random = function() return 0.5 end
        H.Deliver(Here(ns, "A"), "Fresh Face")
        H.Advance(ns.Presence.ANSWER_DELAY)
        H.Advance(ns.Transport.FLUSH_INTERVAL)
        math.random = random
        T.eq(SentPresence(ns), before, "not picked: no answer")
        T.eq(ns.Presence:Count().total, 52, "the newcomer still counts")
    end)

    T.case("above 500 online the count switches off for the session: 500+ online, nothing sent", function()
        local ns = H.Boot({ client = "forever" })
        for i = 1, 500 do ns.Presence:Heard("Rider Number" .. i, i % 2 == 0 and "Alliance" or "Horde") end
        T.eq(ns.Presence:Count().total, 501, "counted, us included")
        T.eq(ns.Presence:Capped(), true, "switched off")
        T.eq(ns.Presence.Short(ns.Presence:Count()), "500+ online", "window line")
        H.Slash("online")
        T.ok(H.Printed("More than 500 HeadHunters online"), "/hh online says why")
        local before = SentPresence(ns)
        H.Deliver(Here(ns, "A"), "Fresh Face")
        for _ = 1, 3 do H.Advance(ns.Presence.INTERVAL) end
        T.eq(SentPresence(ns), before, "no answers, no repeats")
        T.noErrors()
    end)

    T.case("the totals follow a player who changes faction and drop the ones not heard", function()
        local ns = H.Boot({ client = "forever" })
        ns.Presence:Heard("Iron Maple", "Alliance")
        ns.Presence:Heard("Iron Maple", "Horde")
        local count = ns.Presence:Count()
        T.eq(count.Horde, 1, "moved")
        T.eq(count.Alliance, 1, "only us")
        H.Advance(ns.Presence.WINDOW + ns.Presence.PRUNE_EVERY)
        T.eq(ns.Presence:Count().total, 1, "dropped after the window")
    end)

    T.case("no separate here at login when the catch-up hello already went out", function()
        local ns = H.Boot({ client = "forever" })
        for _ = 1, 40 do H.Advance(1) end
        local hello = 0
        for _, m in ipairs(H.sent) do if m.message:find("^%d%aQ:h") then hello = hello + 1 end end
        T.eq(hello, 1, "the hello went out")
        T.eq(SentPresence(ns), 0, "no here: the hello told everyone we are online")
    end)

    T.case("the repeat waits while we broadcast anything else", function()
        local ns = H.Boot({ client = "forever" })
        local now = ns.Utils.Now()
        ns.Transport.lastBroadcastAt = nil
        T.ok(ns.Presence.RepeatNeeded(now), "nothing sent: repeat")
        ns.Transport.lastBroadcastAt = now - 60
        T.ok(not ns.Presence.RepeatNeeded(now), "sent a minute ago: wait")
        ns.Transport.lastBroadcastAt = now - ns.Presence.INTERVAL
        T.ok(ns.Presence.RepeatNeeded(now), "sent an interval ago: repeat")
        T.noErrors()
    end)

    T.case("Classic Era says guild and group", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.Presence:Count().scope, "group", "Era cannot reach the realm")
        H.Slash("online")
        T.ok(H.Printed("in your guild and group: 1"), "the command says so")
        T.noErrors()
    end)

    T.case("/hh online shows the count; the window does not", function()
        local ns = H.Boot({ client = "forever" })
        H.Deliver(Here(ns, "H"), "Grim Tusk")
        H.Slash("")
        T.ok(type(_G.HeadHunterMainFrame.online) ~= "table", "no online line in the window")
        H.Slash("online")
        T.ok(H.Printed("Alliance 1, Horde 1"), "command, per faction")
        T.ok(H.Printed("0.1.7"), "versions")
        T.noErrors()
    end)
end
