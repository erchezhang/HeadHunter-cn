-- HH-121 step 0: relayed records alone never hurt anyone.
--
-- Login catch-up (Sync/CatchUp.lua) passes on records on the relaying peer's word, so
-- an edited client could hand someone fake "unpaid" records (a Deadbeat), fake deaths
-- (an innocent player WANTED), fake catches (a real WANTED ended) or fake duels. A
-- relayed record (origin "relay") is stored and shown, but it counts for WANTED,
-- catches, duel ranks, active bounties and Deadbeats only once a second source has it:
--   - a copy straight from its author (it then becomes a "peer" record), or
--   - its author relaying it, or
--   - the same record relayed by a second peer (catch-up pulls from two).
-- record.relayers holds the compact names of the peers that relayed it, until it
-- counts; then only record.confirmed stays (small saved data).

local addonName, ns = ...

local Relay = ns:RegisterModule("Relay", {})

Relay.SOURCES = 2              -- relayers needed when the author is not one of them

function Relay.Sources(record)
    local n = 0
    for _ in pairs(record.relayers or {}) do n = n + 1 end
    return n
end

-- Does this record count for the rules? Everything not relayed does. A shared website
-- record (HH-158, Sync/SharedSite.lua) carries `vouchers` (compact names: the HeadHunters
-- who shared it from their download and the peers who relayed it to us) and counts once
-- SOURCES of them are different characters, or its author is one of them.
function Relay.Counts(record)
    if type(record) ~= "table" then return true end
    if record.vouchers then
        local author = ns.Utils.CompactName(record.author)
        local n = 0
        for name in pairs(record.vouchers) do
            if name == author then return true end
            n = n + 1
        end
        return n >= Relay.SOURCES
    end
    if record.origin ~= "relay" then return true end
    return record.confirmed == true or Relay.Sources(record) >= Relay.SOURCES
end

-- One more peer relayed the record; authors: the characters who made it (a relay by
-- one of them is as good as their own copy). Returns true when the record now counts
-- and did not before.
function Relay.Vouch(record, relayer, ...)
    if record.origin ~= "relay" or not relayer or Relay.Counts(record) then return false end
    local id = ns.Utils.CompactName(relayer)
    if not id then return false end
    record.relayers = record.relayers or {}
    record.relayers[id] = true
    for i = 1, select("#", ...) do
        local author = select(i, ...)
        if author and ns.Utils.SameCharacter(relayer, author) then record.confirmed = true end
    end
    if not Relay.Counts(record) then return false end
    record.confirmed, record.relayers = true, nil
    return true
end

-- The author's own copy arrived for a record we only had relayed. Returns true when
-- the record now counts and did not before.
function Relay.Confirm(record, origin, sender)
    if record.origin ~= "relay" then return false end
    local before = Relay.Counts(record)
    record.origin, record.sender = origin, sender
    record.relayers, record.confirmed = nil, nil
    return not before
end
