-- Core/Events.lua: dispatcher behaviour the rest of the addon relies on.

return function(T, H)
    T.case("CLEU on Forever is never registered (it would be ADDON_ACTION_FORBIDDEN)", function()
        local ns = H.Boot({ client = "forever" })
        local ok = ns.Events:Register("COMBAT_LOG_EVENT_UNFILTERED", function() end, "test")
        T.eq(ok, false, "Register result")
        T.noErrors()
    end)

    T.case("CLEU on Era registers normally", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.Events:Register("COMBAT_LOG_EVENT_UNFILTERED", function() end, "test"), true, "Register result")
        T.noErrors()
    end)

    T.case("an event the client rejects returns false instead of raising", function()
        local ns = H.Boot({ client = "era" })
        H.removedEvents.SOME_REMOVED_EVENT = true
        T.eq(ns.Events:Register("SOME_REMOVED_EVENT", function() end, "test"), false, "Register result")
        T.noErrors()
    end)

    T.case("a failing handler is reported and does not stop other handlers", function()
        local ns = H.Boot({ client = "era" })
        local reached = false
        ns.Events:Register("HH_TEST", function() error("boom") end, "a")
        ns.Events:Register("HH_TEST", function() reached = true end, "b")
        ns.Events:Fire("HH_TEST")
        T.ok(reached, "second handler ran")
        T.eq(#H.errors, 1, "errors collected by the error handler")
        T.ok(H.errors[1]:find("boom") ~= nil, "error message kept")
    end)

    T.case("the same error again is logged but shown only once", function()
        local ns = H.Boot({ client = "era" })
        ns.Events:Register("HH_TEST", function() error("boom") end, "a")
        ns.Events:Fire("HH_TEST")
        ns.Events:Fire("HH_TEST")
        ns.Events:Fire("HH_TEST")
        T.eq(#H.errors, 1, "shown once")
        local logged = 0
        for _, line in ipairs(ns.Log:Lines()) do
            if line:find("boom") then logged = logged + 1 end
        end
        T.eq(logged, 3, "every copy logged")
    end)

    T.case("custom events never touch the frame; unregister stops delivery", function()
        local ns = H.Boot({ client = "era" })
        local count = 0
        ns.Events:Register("HH_PING", function() count = count + 1 end, "t")
        ns.Events:Fire("HH_PING")
        ns.Events:Unregister("HH_PING", "t")
        ns.Events:Fire("HH_PING")
        T.eq(count, 1, "deliveries")
        T.noErrors()
    end)

    T.case("WoW events reach registered handlers with their arguments", function()
        local ns = H.Boot({ client = "era" })
        local got
        ns.Events:Register("UNIT_COMBAT", function(_, unit) got = unit end, "t")
        H.Fire("UNIT_COMBAT", "player", "WOUND")
        T.eq(got, "player", "argument")
    end)
end
