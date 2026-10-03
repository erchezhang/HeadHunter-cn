-- HH-121 step 5: keep the evidence. Sightings (Alerts/Spotted.lua) live in memory only;
-- when a gold bounty claim on a target arrives, the target's sightings from WINDOW
-- seconds before to WINDOW seconds after the claim become saved data ("pinned"), and so
-- do the ones that arrive later inside that time. The claim's verdict
-- (Bounties:Verdict, step 6) then survives a /reload, and login catch-up passes them on
-- ("Y" records), counted only once a second source has them (Sync/Relay.lua).
-- ns.db.pinned: id "<outlaw>:<t>:<by>" -> { outlaw, t, mapID, x, y, by }, kept as long
-- as the claims (Bounties:Prune).

local addonName, ns = ...

local Evidence = ns:RegisterModule("Evidence", {})

local OWNER = "Evidence"

Evidence.WINDOW = 600          -- seconds around a claim

local function Store()
    return ns.db and ns.db.pinned
end

function Evidence:All()
    return pairs(Store() or {})
end

-- The pinned sightings of one outlaw within `window` seconds of `t`, oldest first
function Evidence:Of(outlaw, t, window)
    local list = {}
    for _, s in self:All() do
        if s.outlaw == outlaw and math.abs(s.t - t) <= (window or self.WINDOW) then list[#list + 1] = s end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

-- Returns the stored sighting, or nil when we have it
function Evidence:Pin(outlaw, s, origin, sender)
    local store = Store()
    if not store or not s.by then return nil end
    local id = outlaw .. ":" .. s.t .. ":" .. s.by
    local have = store[id]
    if have then
        if origin ~= "relay" then ns.Relay.Confirm(have, origin, sender) end
        return nil
    end
    local pinned = { id = id, outlaw = outlaw, t = s.t, mapID = s.mapID, x = s.x, y = s.y, by = s.by,
        origin = origin, sender = sender }
    if origin == "relay" then ns.Relay.Vouch(pinned, sender, s.by) end
    store[id] = pinned
    return pinned
end

-- Is there a claim on this outlaw within WINDOW of t?
local function ClaimNear(outlaw, t)
    for _, poster in ns.Bounties:All() do
        local pay = poster.target == outlaw and ns.Bounties:Payment(poster.id)
        if pay and math.abs(pay.claimedAt - t) <= Evidence.WINDOW then return true end
    end
    return false
end

-- A claim arrived or changed: pin what we saw of its target around it
function Evidence:OnClaims()
    for _, poster in ns.Bounties:All() do
        local pay = ns.Bounties:Payment(poster.id)
        if pay then
            for _, s in ipairs(ns.Spotted:Sightings(poster.target)) do
                if math.abs(s.t - pay.claimedAt) <= self.WINDOW then self:Pin(poster.target, s, "local") end
            end
        end
    end
end

-- A sighting arrived: pinned when a claim on that outlaw is near
function Evidence:OnSpotted(outlaw, s)
    if ClaimNear(outlaw, s.t) then self:Pin(outlaw, s, "local") end
end

function Evidence:Prune(now)
    local store = Store()
    if not store then return end
    local B = ns.Bounties
    local keepFrom = (now or ns.Utils.ServerTime()) - B.BLOCK_WINDOW - B.MAX_DURATION
    for id, s in pairs(store) do
        if type(s) ~= "table" or (tonumber(s.t) or 0) < keepFrom then store[id] = nil end
    end
end

-- Pinned sightings to hand to a peer, newest first: "Y<spotted record>;<by>"
function Evidence:Records(since)
    local list = {}
    for _, s in self:All() do
        if s.t > since then list[#list + 1] = s end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    local P, records = ns.Protocol, {}
    for _, s in ipairs(list) do records[#records + 1] = "Y" .. P.EncodeSpotted(s.outlaw, s.mapID, s.t, s.x, s.y) .. ";" .. s.by end
    return records
end

-- A pinned sighting passed on at login catch-up
function Evidence:AddRelayed(body, sender)
    local U = ns.Utils
    local record, by = body:match("^(.*);([^;]+)$")
    if not record then return nil end
    local outlaw, mapID, t, x, y = ns.Protocol.DecodeSpotted(record)
    by = U.PlayerKey(by)
    if not outlaw or not by then return nil end
    if not outlaw:find("^guid:") then
        outlaw = U.PlayerKey(outlaw)
        if not outlaw then return nil end
    end
    local now = U.ServerTime()
    if t > now + ns.Bounties.MAX_SKEW or t < now - ns.Bounties.BLOCK_WINDOW - ns.Bounties.MAX_DURATION then return nil end
    return self:Pin(outlaw, { t = t, mapID = mapID, x = x, y = y, by = by }, "relay", sender)
end

ns.Events:Register("HH_INITIALIZED", function()
    Evidence:Prune()
    ns.Events:Register("HH_BOUNTY_UPDATED", function() Evidence:OnClaims() end, OWNER)
    ns.Events:Register("HH_OUTLAW_SPOTTED", function(_, outlaw, s) Evidence:OnSpotted(outlaw, s) end, OWNER)
end, OWNER)
