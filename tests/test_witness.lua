-- HH-121 step 4: a hunted player dies near a HeadHunter, who tells the others where
-- and when (Sync/Witness.lua). WoW Forever: nameplates and the target, no combat log.
-- Made-up players only.

return function(T, H)
    local serial = 0

    -- `killer` kills n victims in the last few minutes (peer reports): WANTED
    local function Spree(ns, killer, n)
        for i = 1, n do
            serial = serial + 1
            local victim = "Victim" .. serial .. " Smith"
            local t = H.serverTime - (n - i + 1) * 30
            ns.Reports:Add({ id = victim .. ":" .. t, t = t, victim = { key = victim, level = 20 },
                killer = { key = killer, name = killer, level = 20, class = "ROGUE", race = "Orc" },
                assists = {}, mapID = 1436, x = 0.5, y = 0.5, confidence = "exact" }, "peer", victim)
        end
    end

    local function Settle()
        H.Advance(1)
        for _ = 1, 10 do H.Advance(0) end
    end

    local function Boot()
        local ns = H.Boot({ client = "forever" })
        H.playerMap, H.playerX, H.playerY = 1436, 0.45, 0.6 -- Westfall
        Spree(ns, "Grim Reaper", 5)
        Settle()
        return ns
    end

    local function Sent(outlaw)
        local found = 0
        for _, m in ipairs(H.sent) do
            if m.message:find("X:" .. outlaw .. ";", 1, true) then found = found + 1 end
        end
        return found
    end

    -- The hunted player in sight on nameplate1, alive or dead
    local function Plate(dead)
        H.units.nameplate1 = { name = "Grim", realm = "Reaper", level = 20, class = "ROGUE", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-1-0000GRIM", dead = dead }
    end

    local function Wait(seconds)
        for _ = 1, seconds do H.Advance(1) end
    end

    T.case("the witness record round trip", function()
        local ns = H.Boot({ client = "forever" })
        local P = ns.Protocol
        local w = P.DecodeWitness(P.EncodeWitness({ outlaw = "Grim Reaper", mapID = 1436, t = 1790000000, x = 0.451,
            y = 0.6, by = "Scout Bright" }))
        T.eq(w.outlaw, "Grim Reaper", "outlaw")
        T.eq(w.t, 1790000000, "time")
        T.eq(w.x, 0.451, "x")
        T.eq(w.killer, nil, "no killer on Forever")
        T.eq(w.by, "Scout Bright", "the witness")
        T.eq(P.DecodeWitness("Grim;1;2;3"), nil, "broken record")
    end)

    T.case("a hunted player seen alive, then dead: the others hear where and when", function()
        local ns = Boot()
        local outlaw = ns.Wanted:ByKey("Grim Reaper").id
        H.sent = {}
        Plate(false)
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        Plate(true)
        H.Fire("UNIT_HEALTH", "nameplate1")
        Wait(12)
        T.eq(Sent(outlaw), 1, "told once")
        local list = ns.Witness:Of(outlaw)
        T.eq(#list, 1, "stored")
        T.eq(list[1].mapID, 1436, "where we were")
        T.eq(list[1].killer, nil, "who landed the blow is unknown on Forever")
        T.noErrors()
    end)

    T.case("a corpse found later, or a player nobody hunts, tells nothing", function()
        local ns = Boot()
        local outlaw = ns.Wanted:ByKey("Grim Reaper").id
        H.sent = {}
        Plate(true)
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        Wait(12)
        T.eq(Sent(outlaw), 0, "dead when first seen: not a death we saw")

        H.units.nameplate2 = { name = "Nobody", realm = "Special", level = 20, class = "MAGE", race = "Orc",
            faction = "Horde", isPlayer = true, guid = "Player-1-0000NOBO", dead = false }
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        H.units.nameplate2.dead = true
        H.Fire("UNIT_HEALTH", "nameplate2")
        Wait(12)
        T.eq(#ns.Witness:Of("Nobody Special"), 0, "not hunted")

        Plate(false)
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        Wait(40)
        Plate(true)
        H.Fire("UNIT_HEALTH", "nameplate1")
        Wait(12)
        T.eq(Sent(outlaw), 0, "seen alive too long ago")
        T.noErrors()
    end)

    T.case("another witness told it first: we stay quiet; the hunter's own record does not count", function()
        local ns = Boot()
        local outlaw = ns.Wanted:ByKey("Grim Reaper").id
        local P = ns.Protocol
        H.sent = {}
        H.Deliver(P.Pack("A", "X", { P.EncodeWitness({ outlaw = outlaw, mapID = 1436, t = H.serverTime, x = 0.4, y = 0.6,
            killer = "Hunter Bold", by = "Hunter Bold" }) }), "Hunter Bold")
        Plate(false)
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        Plate(true)
        H.Fire("UNIT_HEALTH", "nameplate1")
        H.Deliver(P.Pack("A", "X", { P.EncodeWitness({ outlaw = outlaw, mapID = 1436, t = H.serverTime, x = 0.4, y = 0.6,
            by = "Scout Bright" }) }), "Scout Bright")
        Wait(12)
        T.eq(Sent(outlaw), 0, "a witness (not the hunter) was first")
        T.eq(#ns.Witness:Of(outlaw), 2, "the hunter's record and the other witness")
        T.noErrors()
    end)

    T.case("our own catch gets a witness record at once, with us as the killer", function()
        local ns = Boot()
        local entry = ns.Wanted:ByKey("Grim Reaper")
        H.sent = {}
        ns.Justice:Record(entry, "target")
        T.eq(#ns.Witness:Of(entry.id), 1, "stored at once")
        Wait(5)
        T.eq(Sent(entry.id), 1, "sent with the catch")
        local w = ns.Witness:Of(entry.id)[1]
        T.eq(w.killer, ns.Utils.UnitKey("player"), "we landed the blow")
        T.eq(ns.Witness.OwnCatch(w), true, "the hunter's own record")
        T.noErrors()
    end)

    T.case("a group member's catch came first: ours is a witness record", function()
        local ns = Boot()
        local entry = ns.Wanted:ByKey("Grim Reaper")
        local P = ns.Protocol
        H.Deliver(P.Pack("A", "K", { P.EncodeJustice(entry.id, H.serverTime, 1436, "Hunter Bold") }), "Hunter Bold")
        Settle()
        H.sent = {}
        T.eq(ns.Justice:Record(entry, "honor"), nil, "the same catch again")
        Wait(12)
        T.eq(Sent(entry.id), 1, "a witness record instead")
        T.noErrors()
    end)

    T.case("peers: only the witness speaks for themselves; relayed ones need a second source", function()
        local ns = Boot()
        local P = ns.Protocol
        local record = P.EncodeWitness({ outlaw = "Grim Reaper", mapID = 1436, t = H.serverTime - 60, x = 0.4, y = 0.6,
            by = "Scout Bright" })
        H.Deliver(P.Pack("A", "X", { record }), "Liar Loud")
        T.eq(#ns.Witness:Of("Grim Reaper"), 0, "someone else's name refused")
        ns.Witness:AddRelayed(record, "Liar Loud")
        local w = ns.Witness:Of("Grim Reaper")[1]
        T.eq(ns.Relay.Counts(w), false, "one relaying peer: stored, not counted")
        ns.Witness:AddRelayed(record, "Second Peer")
        T.eq(ns.Relay.Counts(w), true, "a second peer: counted")
        T.noErrors()
    end)
end
