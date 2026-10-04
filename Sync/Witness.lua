-- HH-121 step 4: witness records. When a hunted player (WANTED, at large, or with a
-- player's bounty) dies near a HeadHunter, that HeadHunter tells the others who died,
-- when and where, and who landed the blow when the client can tell (WoW Forever has no
-- combat log: killer empty). They later confirm or reject bounty claims (step 6).
-- Never a WANTED recompute.
--
-- Seeing it (spike 2026-10-02): a hunted player's nameplate or our target turning dead,
-- seen alive less than ALIVE_WINDOW seconds before (a corpse found later says nothing
-- about the time). Only players we know as hunted are watched, so big fights cost
-- nothing. The hunter sends one for their own catch at once (HH_JUSTICE_ADDED, origin
-- "local"), so every claim has a place; a group member whose catch was a copy of
-- another's (Justice:Record) sends one too.
-- Sending: others wait 1..SEND_DELAY seconds (Forever: from just after the honor
-- window) and stay quiet when another witness of the same death (not the hunter's own
-- record) arrived first, or when the death is our own catch.
-- Receiving: only the witness speaks for themselves (by = sender), under a per-sender
-- limit. Stored in ns.db.witness (id "<outlaw>:<t>:<by>") as long as the reports (30
-- days), passed on at login catch-up ("X" records) and, relayed, counted only once a
-- second source has them (Sync/Relay.lua).
-- Fires HH_WITNESS_ADDED(record), and HH_HUNTED_DIED(outlaw id, GUID) when we saw a
-- hunted player die (Sync/Justice.lua makes it our catch on Forever when the game
-- gives us honor for it).

local addonName, ns = ...

local Witness = ns:RegisterModule("Witness", {})

local OWNER = "Witness"

Witness.ALIVE_WINDOW = 30      -- seconds: seen alive this recently, the death is now
Witness.SAME_DEATH = 60        -- seconds: records this close are the same death
Witness.SEND_DELAY = 10        -- others wait up to this long before telling
Witness.MAX_SKEW = 300
Witness.SENDER_LIMIT = 10      -- records accepted per sender per window
Witness.SENDER_WINDOW = 600

local watched = {}             -- GUID -> outlaw id of a hunted player in sight
local alive = {}               -- GUID -> Now() we last saw them alive
local senderLog = {}

local function Store()
    return ns.db and ns.db.witness
end

function Witness:All()
    return pairs(Store() or {})
end

-- The records of one outlaw's deaths within `window` seconds of `t` (every one
-- without t), oldest first
function Witness:Of(outlaw, t, window)
    local list = {}
    for _, w in self:All() do
        if w.outlaw == outlaw and (not t or math.abs(w.t - t) <= (window or self.SAME_DEATH)) then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

-- The hunter's own record: they landed the blow and sent it themselves
function Witness.OwnCatch(w)
    return w.killer ~= nil and ns.Utils.SameCharacter(w.killer, w.by)
end

function Witness:Add(w, origin, sender)
    local store = Store()
    if not store or not w.outlaw or not w.by then return nil end
    w.id = w.outlaw .. ":" .. w.t .. ":" .. w.by
    if store[w.id] then return nil end
    w.origin, w.sender = origin, sender
    store[w.id] = w
    ns:Debug("Witness added", w.id, "origin", origin)
    ns.Events:Fire("HH_WITNESS_ADDED", w)
    return w
end

function Witness:Prune(now)
    local store = Store()
    if not store then return end
    local minTime = (now or ns.Utils.ServerTime()) - ns.Reports.MAX_AGE
    for id, w in pairs(store) do
        if type(w) ~= "table" or (tonumber(w.t) or 0) < minTime then store[id] = nil end
    end
end

-- Records to hand to a peer who missed them, newest first
function Witness:Since(since)
    local list = {}
    for _, w in self:All() do
        if w.t > since then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

-------------------------------------------------
-- Seeing a death
-------------------------------------------------

local function Hunted(entry)
    return entry ~= nil and (ns.Wanted.Hunted(entry) or ns.Bounties:ActiveOn(entry))
end

-- Someone else already told this death (not the hunter's own record)
local function Told(outlaw, t)
    local me = ns.Utils.UnitKey("player")
    for _, w in ipairs(Witness:Of(outlaw, t)) do
        if not Witness.OwnCatch(w) and not ns.Utils.SameCharacter(w.by, me) then return true end
    end
    return false
end

-- This death is our own catch: its record already says where we were, and we cannot
-- witness our own claim
local function OurCatch(outlaw, t)
    local me = ns.Utils.UnitKey("player")
    for _, record in ns.Justice:All() do
        if record.outlaw == outlaw and record.origin == "local" and ns.Utils.SameCharacter(record.hunter, me)
                and math.abs(record.t - t) <= Witness.SAME_DEATH then
            return true
        end
    end
    return false
end

-- Seconds before telling a death we saw: on Forever our catch comes only with the
-- honor award (Sync/Justice.lua), so wait for it first
function Witness.SendDelay()
    local min = ns.Features.HasCLEU and 1 or ns.Justice.HONOR_WINDOW + 1
    return min + math.random() * math.max(Witness.SEND_DELAY - min, 0)
end

-- We saw `outlaw` die at `t`; killer: who landed the blow, nil when unknown; own: our
-- own catch (sent at once, never skipped). Returns the record when it was sent now.
function Witness:Saw(outlaw, t, killer, own)
    local U = ns.Utils
    local me = U.UnitKey("player")
    if not me or not ns.Guards:IsActive() then return nil end
    local mapID = U.PlayerMapID()
    local zone, x, y = ns.Zones.ToZone(mapID, U.PlayerPosition(mapID))
    if not zone then return nil end
    local w = { outlaw = outlaw, mapID = zone, t = t, x = x, y = y, killer = killer, by = me }
    local function Go()
        if not own and (Told(outlaw, t) or OurCatch(outlaw, t)) then return nil end
        if not self:Add(w, "local") then return nil end
        local P, Transport = ns.Protocol, ns.Transport
        Transport:Queue(P.TYPES.WITNESS, P.EncodeWitness(w), Transport.PRIORITY.posse, "X:" .. w.id)
        return w
    end
    if own then return Go() end
    C_Timer.After(self.SendDelay(), Go)
    return nil
end

-- A unit came into sight (discover: a new nameplate or target) or its health changed:
-- remember hunted players, and their deaths. Health changes of players nobody hunts
-- cost one table lookup.
function Witness:Check(unit, discover)
    local U = ns.Utils
    if type(unit) ~= "string" or not (unit == "target" or unit:find("^nameplate")) then return end
    local guid = U.UnitGUID(unit)
    if not guid then return end
    local outlaw = watched[guid]
    if not outlaw then
        if not discover then return end
        if U.Accessible(U.SafeCall(UnitIsPlayer, unit)) ~= true then return end
        local key = U.UnitKey(unit)
        local entry = key and ns.Wanted:ByKey(key)
        if not Hunted(entry) then return end
        outlaw = entry.id
        watched[guid] = outlaw
    end
    local dead = U.Accessible(U.SafeCall(UnitIsDead, unit))
    if dead == false then
        alive[guid] = U.Now()
    elseif dead == true then
        local seen = alive[guid]
        alive[guid] = nil
        if seen and U.Now() - seen <= self.ALIVE_WINDOW then
            self:Saw(outlaw, U.ServerTime())
            ns.Events:Fire("HH_HUNTED_DIED", outlaw, guid)
        end
    end
end

-- Our own catch (Sync/Justice.lua): the claim gets a place at once
function Witness:OnCatch(record)
    if record.origin ~= "local" then return end
    self:Saw(record.outlaw, record.t, record.killer, true)
end

-------------------------------------------------
-- Peers
-------------------------------------------------

local function UnderRateLimit(sender)
    local id = ns.Utils.CompactName(sender)
    if not id then return false end
    local now = ns.Utils.Now()
    local recent = {}
    for _, at in ipairs(senderLog[id] or {}) do
        if now - at < Witness.SENDER_WINDOW then recent[#recent + 1] = at end
    end
    senderLog[id] = recent
    if #recent >= Witness.SENDER_LIMIT then return false end
    recent[#recent + 1] = now
    return true
end

-- Canonical keys and a plausible time, or nil
local function Decode(record)
    local U = ns.Utils
    local w = ns.Protocol.DecodeWitness(record)
    if not w then return nil end
    if not w.outlaw:find("^guid:") then
        w.outlaw = U.PlayerKey(w.outlaw)
        if not w.outlaw then return nil end
    end
    w.by = U.PlayerKey(w.by)
    if not w.by then return nil end
    w.killer = w.killer and U.PlayerKey(w.killer) or nil
    local now = U.ServerTime()
    if w.t > now + Witness.MAX_SKEW or w.t < now - ns.Reports.MAX_AGE then return nil end
    return w
end

function Witness:OnPeer(record, sender)
    local w = Decode(record)
    if not w or not ns.Utils.SameCharacter(sender, w.by) then return nil end
    local have = (Store() or {})[w.outlaw .. ":" .. w.t .. ":" .. w.by]
    if have then
        ns.Relay.Confirm(have, "peer", sender)
        return nil
    end
    if not UnderRateLimit(sender) then return nil end
    return self:Add(w, "peer", sender)
end

-- Passed on at login catch-up: counts only once a second source has it (step 0)
function Witness:AddRelayed(record, sender)
    local w = Decode(record)
    if not w then return nil end
    local have = (Store() or {})[w.outlaw .. ":" .. w.t .. ":" .. w.by]
    if have then
        ns.Relay.Vouch(have, sender, have.by)
        return nil
    end
    w.origin = "relay"
    ns.Relay.Vouch(w, sender, w.by)
    return self:Add(w, "relay", sender)
end

-- Forget what is in sight (tests, leaving the world)
function Witness:Reset()
    watched, alive, senderLog = {}, {}, {}
end

ns.Events:Register("HH_INITIALIZED", function()
    local Events = ns.Events
    Witness:Prune()
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.WITNESS, function(record, sender) Witness:OnPeer(record, sender) end)
    Events:Register("NAME_PLATE_UNIT_ADDED", function(_, unit) Witness:Check(unit, true) end, OWNER)
    Events:Register("UNIT_HEALTH", function(_, unit) Witness:Check(unit) end, OWNER)
    Events:Register("PLAYER_TARGET_CHANGED", function() Witness:Check("target", true) end, OWNER)
    Events:Register("HH_JUSTICE_ADDED", function(_, record) Witness:OnCatch(record) end, OWNER)
end, OWNER)
