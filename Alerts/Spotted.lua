-- A watched outlaw spotted (author, 2026-10-01): when we see a WANTED outlaw (or one at
-- large, or with a player's bounty; Alerts/Sighting.lua), the HeadHunters nearby hear
-- where, so a posse can close in before the next kill. Quiet on purpose:
--   sending    we wait SEND_DELAY_MIN..MAX seconds first; a spot of the same outlaw
--              from anyone in that time or in the last EVERY seconds means we send
--              nothing. The first spotter speaks for everyone, and each outlaw goes
--              out at most once per EVERY.
--   receiving  only outlaws we know as watched, only in our alert range, not when we
--              saw them ourselves in the last EVERY. The same outlaw again: in the
--              same zone after SAME_ZONE_EVERY (15 min), in a new zone after EVERY
--              (5 min: he moved on). At most MAX_PER_MINUTE lines a minute. Off with
--              the alerts.
-- Protocol type L (Sync/Protocol.lua EncodeSpotted), on the automatic routes: Forever
-- the hidden channel, Era guild and group.

local addonName, ns = ...
local L = ns.L

local Spotted = ns:RegisterModule("Spotted", {})

local OWNER = "Spotted"

Spotted.EVERY = 300
Spotted.SAME_ZONE_EVERY = 900
Spotted.SEND_DELAY_MIN = 1
Spotted.SEND_DELAY_MAX = 3
Spotted.MAX_PER_MINUTE = 3
Spotted.MAX_SKEW = 300

local lastSpot = {}  -- outlaw id -> Now() of the last spot anyone sent (ours or a peer's)
local seenByUs = {}  -- outlaw id -> Now() we saw them ourselves
local shown = {}     -- Now() of each spotted line shown, for the per-minute cap
local told = {}      -- outlaw id -> { at = Now(), zone } of the last line we showed

local function Recent(at, window)
    return at ~= nil and ns.Utils.Now() - at < window
end

local function Watched(entry)
    return ns.Wanted.Hunted(entry) or ns.Bounties:ActiveOn(entry)
end

-- We saw a watched outlaw (the sighting alert showed): tell the others, unless someone
-- already did
function Spotted:OnSeen(entry)
    local U = ns.Utils
    seenByUs[entry.id] = U.Now()
    if Recent(lastSpot[entry.id], self.EVERY) then return end
    local mapID = U.PlayerMapID()
    local zone, x, y = ns.Zones.ToZone(mapID, U.PlayerPosition(mapID))
    if not zone then return end
    local t = U.ServerTime()
    local wait = self.SEND_DELAY_MIN + math.random() * (self.SEND_DELAY_MAX - self.SEND_DELAY_MIN)
    C_Timer.After(wait, function()
        -- Someone else spoke first
        if Recent(lastSpot[entry.id], Spotted.EVERY) then return end
        lastSpot[entry.id] = U.Now()
        local P = ns.Protocol
        ns.Transport:Queue(P.TYPES.SPOTTED, P.EncodeSpotted(entry.id, zone, t, x, y), ns.Transport.PRIORITY.posse,
            "L:" .. entry.id)
    end)
end

-- Lines shown in the last minute, older ones dropped
local function ShownLastMinute()
    local now = ns.Utils.Now()
    local kept = {}
    for _, at in ipairs(shown) do
        if now - at < 60 then kept[#kept + 1] = at end
    end
    shown = kept
    return #kept
end

function Spotted:OnPeer(record, sender)
    local P, U = ns.Protocol, ns.Utils
    local outlaw, mapID, t, x, y = P.DecodeSpotted(record)
    if not outlaw then return end
    if not outlaw:find("^guid:") then
        outlaw = U.PlayerKey(outlaw)
        if not outlaw then return end
    end
    local serverNow = U.ServerTime()
    if t > serverNow + self.MAX_SKEW or t < serverNow - self.EVERY then return end
    -- A peer spoke: we keep quiet about this outlaw
    lastSpot[outlaw] = U.Now()
    if Recent(seenByUs[outlaw], self.EVERY) then return end
    -- The same outlaw again: a new zone after EVERY, the same zone after SAME_ZONE_EVERY
    local last = told[outlaw]
    if last and Recent(last.at, last.zone == mapID and self.SAME_ZONE_EVERY or self.EVERY) then return end
    local entry = ns.Wanted:Get(outlaw)
    if not Watched(entry) or not ns.Zones.InRange(mapID) then return end
    if ShownLastMinute() >= self.MAX_PER_MINUTE then return end

    local Wanted = ns.Wanted
    local label = entry.wanted and Wanted.RankName(entry.rank)
        or (entry.atLarge and L.SPOTTED_AT_LARGE or L.SPOTTED_BOUNTY)
    local where = U.MapName(mapID) or L.UNKNOWN_ZONE
    if x and y then where = string.format("%s (%.1f, %.1f)", where, x * 100, y * 100) end
    local spotter = U.PlayerLink(U.PlayerKey(sender)) or tostring(sender)
    local ok = ns.Alerts:Show({
        key = "spotted:" .. outlaw .. ":" .. mapID,
        throttle = self.EVERY,
        chat = string.format(L.SPOTTED_CHAT, label, U.DisplayName(entry.key or outlaw) or entry.name or outlaw, where,
            U.Ago(math.max(0, serverNow - t)), spotter),
        sound = "soft",
        combat = true,
    })
    if ok then
        shown[#shown + 1] = U.Now()
        told[outlaw] = { at = U.Now(), zone = mapID }
    end
end

-- Registered at load, so no new HH_INITIALIZED handler changes the login order
ns.Events:Register("HH_OUTLAW_SEEN", function(_, entry) Spotted:OnSeen(entry) end, OWNER)
ns.Transport:RegisterHandler(ns.Protocol.TYPES.SPOTTED, function(record, sender) Spotted:OnPeer(record, sender) end)
