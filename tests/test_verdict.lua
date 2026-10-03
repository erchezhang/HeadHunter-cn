-- HH-121 steps 5 and 6: the sightings around a claim are kept (Sync/Evidence.lua), and
-- each gold bounty claim gets a verdict from other players' data (Bounties:Verdict).
-- WoW Forever. Made-up players and maps (each map 1000 x 1000 yards).

return function(T, H)
    local OWNER, TARGET, HUNTER = "Owner Bright", "Grim Reaper", "Hunter Bold"

    -- Made-up world: Westfall (1436) at 0, Elwynn (1429) 5000 yards east, both continent 0
    local function World()
        local origins = { [1436] = 0, [1429] = 5000 }
        _G.CreateVector2D = function(x, y) return { x = x, y = y } end
        _G.C_Map.GetWorldPosFromMapPos = function(mapID, v)
            local ox = origins[mapID]
            if not ox then return nil end
            return 0, { GetXY = function() return ox + v.x * 1000, v.y * 1000 end }
        end
    end

    -- A running poster on TARGET and HUNTER's claim at `at`; returns the poster id
    local function Claim(ns, at)
        local t = at - 3600
        local poster = { id = OWNER .. ":" .. t, owner = OWNER, target = TARGET, reason = 1, gold = 50000,
            ["until"] = t + 86400, t = t }
        ns.Bounties:Add(poster, "peer", OWNER)
        ns.Bounties:AddPayment({ posterId = poster.id, hunter = HUNTER, status = "claimed", claimedAt = at, t = at }, "peer")
        return poster.id
    end

    -- A witness record of TARGET's death, sent by `by`
    local function Witnessed(ns, by, t, mapID, x, y, killer)
        local P = ns.Protocol
        H.Deliver(P.Pack("A", "X", { P.EncodeWitness({ outlaw = TARGET, mapID = mapID or 1436, t = t, x = x or 0.5,
            y = y or 0.5, killer = killer, by = by }) }), by)
    end

    -- A sighting of TARGET alive, sent by `by`
    local function Spotted(ns, by, t, mapID, x, y)
        local P = ns.Protocol
        H.Deliver(P.Pack("A", "L", { P.EncodeSpotted(TARGET, mapID or 1436, t, x or 0.5, y or 0.5) }), by)
    end

    local function Boot()
        local ns = H.Boot({ client = "forever" })
        World()
        return ns
    end

    T.case("verified: another player saw the target die there and then; the hunter's own word is not enough", function()
        local ns = Boot()
        local at = H.serverTime - 30
        local id = Claim(ns, at)
        Witnessed(ns, HUNTER, at, 1436, 0.5, 0.5, HUNTER)
        T.eq(ns.Bounties:Verdict(id), "unverified", "only the hunter's own record")
        Witnessed(ns, "Scout Bright", at + 3)
        local verdict, by = ns.Bounties:Verdict(id)
        T.eq(verdict, "verified", "a witness")
        T.eq(by, "Scout Bright", "who saw it")
        _G.CreateVector2D = nil
        T.noErrors()
    end)

    T.case("verified: the target's own death report names the hunter", function()
        local ns = Boot()
        local at = H.serverTime - 30
        local id = Claim(ns, at)
        ns.Reports:Add({ id = TARGET .. ":" .. at, t = at, victim = { key = TARGET, level = 20 },
            killer = { key = HUNTER, name = HUNTER, level = 20, class = "MAGE", race = "Human" },
            assists = {}, mapID = 1436, x = 0.5, y = 0.5, confidence = "exact" }, "peer", TARGET)
        T.eq(select(2, ns.Bounties:Verdict(id)), TARGET, "verified by the target")
        _G.CreateVector2D = nil
        T.noErrors()
    end)

    T.case("rejected: seen alive too far away just before the claim", function()
        local ns = Boot()
        local at = H.serverTime - 30
        Spotted(ns, "Scout Bright", at - 20, 1429, 0.5, 0.5) -- 5000 yards away, 20 s before
        local id = Claim(ns, at)
        Witnessed(ns, HUNTER, at, 1436, 0.5, 0.5, HUNTER)
        local verdict, by = ns.Bounties:Verdict(id)
        T.eq(verdict, "rejected", "could not be there")
        T.eq(by, "Scout Bright", "who saw them")

        local near = Boot()
        Spotted(near, "Scout Bright", at - 20, 1436, 0.6, 0.5) -- 100 yards away
        local nearId = Claim(near, at)
        Witnessed(near, HUNTER, at, 1436, 0.5, 0.5, HUNTER)
        T.eq(near.Bounties:Verdict(nearId), "unverified", "close enough: nothing against it")
        _G.CreateVector2D = nil
        T.noErrors()
    end)

    T.case("no rejection when the target died in between (a release moves them), or without the claim's place", function()
        local ns = Boot()
        local at = H.serverTime - 30
        Spotted(ns, "Scout Bright", at - 200, 1429, 0.5, 0.5)
        Witnessed(ns, "Other Eye", at - 150, 1429, 0.5, 0.5)
        local id = Claim(ns, at)
        Witnessed(ns, HUNTER, at, 1436, 0.5, 0.5, HUNTER)
        T.eq(ns.Bounties:Verdict(id), "unverified", "a death between the sighting and the claim")

        local blind = Boot()
        Spotted(blind, "Scout Bright", at - 20, 1429, 0.5, 0.5)
        local blindId = Claim(blind, at)
        T.eq(blind.Bounties:Verdict(blindId), "unverified", "no place for the claim: nothing to compare")
        _G.CreateVector2D = nil
        T.noErrors()
    end)

    T.case("evidence both ways: unverified; a relayed witness alone does not verify", function()
        local ns = Boot()
        local at = H.serverTime - 30
        Spotted(ns, "Scout Bright", at - 20, 1429, 0.5, 0.5)
        local id = Claim(ns, at)
        Witnessed(ns, HUNTER, at, 1436, 0.5, 0.5, HUNTER)
        Witnessed(ns, "Friend Fake", at + 2)
        T.eq(ns.Bounties:Verdict(id), "unverified", "a witness and a sighting disagree")

        local relayed = Boot()
        local rid = Claim(relayed, at)
        local P = relayed.Protocol
        relayed.Witness:AddRelayed(P.EncodeWitness({ outlaw = TARGET, mapID = 1436, t = at + 2, x = 0.5, y = 0.5,
            by = "Scout Bright" }), "Liar Loud")
        T.eq(relayed.Bounties:Verdict(rid), "unverified", "one peer's relay")
        _G.CreateVector2D = nil
        T.noErrors()
    end)

    T.case("the sightings around a claim are kept, the verdict survives losing the memory, and changes are told", function()
        local ns = Boot()
        local at = H.serverTime - 30
        Spotted(ns, "Scout Bright", at - 20, 1429, 0.5, 0.5)
        local id = Claim(ns, at)
        T.eq(#ns.Evidence:Of(TARGET, at), 1, "pinned when the claim arrived")
        Spotted(ns, "Other Eye", at + 60, 1436, 0.4, 0.5)
        T.eq(#ns.Evidence:Of(TARGET, at), 2, "and a later sighting near the claim")
        ns.Spotted:Reset()
        T.eq(#ns.Spotted:Sightings(TARGET), 0, "memory gone (a /reload)")
        local updates = 0
        ns.Events:Register("HH_BOUNTY_UPDATED", function() updates = updates + 1 end, "TestVerdict")
        ns.Bounties:RefreshVerdicts()
        Witnessed(ns, HUNTER, at, 1436, 0.5, 0.5, HUNTER)
        T.eq(ns.Bounties:Verdict(id), "rejected", "the kept sighting still counts")
        T.ok(updates >= 1, "the change was told")

        -- Passed on at login catch-up: one peer is not enough
        local fresh = Boot()
        Claim(fresh, at)
        for _, record in ipairs(ns.Evidence:Records(at - 3600)) do fresh.Evidence:AddRelayed(record:sub(2), "Helper Kind") end
        local kept = fresh.Evidence:Of(TARGET, at)
        T.eq(#kept, 2, "relayed")
        T.eq(fresh.Relay.Counts(kept[1]), false, "one relaying peer: not counted yet")
        _G.CreateVector2D = nil
        T.noErrors()
    end)
end
