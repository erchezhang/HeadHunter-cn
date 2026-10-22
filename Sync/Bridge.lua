-- HH-151: HeadHunters of every home server share one world.
--
-- On WoW Forever every character has a hidden home server (the middle number of its
-- GUID). Players of many servers share one world per region and ruleset, but the
-- hidden channel only joins the players of one server (in game 2026-10-22: Mo Mao of
-- 6946 and Vieta of 6856, grouped, each owned their own HeadHunterSync). So records are
-- carried across servers:
--   - by the group: a HeadHunter in a group with HeadHunters of other servers passes
--     what his channel hears to the group, and what they send to the group on to his
--     channel. One bridge per server in a group: the first by name of that server's
--     HeadHunters there; it waits HOLD_MIN..HOLD_MAX s and stays quiet when someone
--     else carried the record first;
--   - by a link: a player of our faction whose nameplate shows, from another server and
--     not in our group, gets one hidden whisper (LINK); when they answer, both pull each
--     other's last LINK_PULL_SINCE seconds once (CatchUp:PullFrom).
-- A carried record goes in an envelope (Protocol: E) with its author and world, at most
-- MAX_HOPS carriers and LIFETIME seconds. What changes WANTED, bounty or ranks goes
-- through the relay rules (Sync/Relay.lua: a second source or a direct copy); the rest
-- is taken as from its author. A carrier earns nothing for it.
-- Performance: envelopes are handled in the inbox under its time budget; SEEN_MAX keys
-- at most; QUEUE_MAX carried records wait at most, P and Z dropped first; carried
-- messages use at most half of the send budget, after our own (Transport:Flush).

local addonName, ns = ...

local Bridge = ns:RegisterModule("Bridge", {})

local OWNER = "Bridge"

Bridge.MAX_HOPS = 2
Bridge.LIFETIME = 600
Bridge.MAX_SKEW = 300
Bridge.SEEN_MAX = 4000
Bridge.QUEUE_MAX = 100
Bridge.HOLD_MIN = 1
Bridge.HOLD_MAX = 3
Bridge.LINK_EVERY = 600
Bridge.LINK_PER_MINUTE = 4
Bridge.LINK_PULL_SINCE = 600

local TYPES = ns.Protocol.TYPES

-- Carried across servers; LOW ones go last and are dropped first
Bridge.CARRIED = {
    [TYPES.DEATH] = true, [TYPES.JUSTICE] = true, [TYPES.PUNISHMENT] = true, [TYPES.WITNESS] = true,
    [TYPES.POSTER] = true, [TYPES.PAYMENT] = true, [TYPES.GLASS] = true, [TYPES.DUEL] = true,
    [TYPES.POSSE] = true, [TYPES.SPOTTED] = true, [TYPES.PRESENCE] = true, [TYPES.PING] = true,
    [TYPES.HOTSPOT] = true, [TYPES.DUEL_SPOT] = true,
}
Bridge.LOW = { [TYPES.HOTSPOT] = true, [TYPES.DUEL_SPOT] = true }

-- They count through the relay rules: a second carrier of the same record is a second
-- source, so its copy still goes to the store (Relay.Vouch), never on again
Bridge.COUNTED = {
    [TYPES.DEATH] = true, [TYPES.JUSTICE] = true, [TYPES.PUNISHMENT] = true, [TYPES.WITNESS] = true,
    [TYPES.POSTER] = true, [TYPES.PAYMENT] = true,
}

-- Other-faction records taken, as Transport:Receive does for direct ones
local CROSS_FACTION = { [TYPES.DUEL] = true, [TYPES.PING] = true, [TYPES.PRESENCE] = true }

Bridge.stats = { forwarded = 0, delivered = 0, duplicates = 0, refused = 0, dropped = 0, skipped = 0, links = 0 }

-------------------------------------------------
-- World
-------------------------------------------------

local ruleset

local function RuleActive(rule)
    if rule == nil or not C_GameRules or type(C_GameRules.IsGameRuleActive) ~= "function" then return nil end
    local ok, active = pcall(C_GameRules.IsGameRuleActive, rule)
    if not ok or active == nil then return nil end
    return active == true
end

local function RulesetFromRealmName()
    local name = ns.Utils.SafeCall(GetRealmName)
    if type(name) ~= "string" then return nil end
    name = " " .. name:lower() .. " "
    if name:find("hardcore", 1, true) then return "hc" end
    if name:find("roleplay", 1, true) or name:find("[%s%-]rp[%s%-%d]") then return "rp" end
    if name:find("pvp", 1, true) then return "pvp" end
    if name:find("pve", 1, true) or name:find("normal", 1, true) then return "pve" end
    return nil
end

-- pvp, pve, rp or hc; "?" while the game does not say. Kept once known.
function Bridge.Ruleset()
    if ruleset then return ruleset end
    local rules = Enum and Enum.GameRule
    local hc = RuleActive(rules and rules.HardcoreRuleset)
    local rp = RuleActive(rules and rules.RPRuleset)
    local pvp = RuleActive(rules and rules.PvPRuleset)
    local found = (hc and "hc") or (rp and "rp") or (pvp and "pvp") or nil
    local fromName = RulesetFromRealmName()
    if not found and hc == false and rp == false and pvp == false then found = fromName or "pve" end
    found = found or fromName
    if found then ruleset = found end
    return found or "?"
end

-- "eu-pvp": the region and the ruleset of our world
function Bridge.World()
    return (ns.Utils.Region() or "?") .. "-" .. Bridge.Ruleset()
end

-- The same world; a part one side does not know yet does not split it
function Bridge.SameWorld(tag)
    if type(tag) ~= "string" then return false end
    local region, rules = tag:match("^([^%-]+)%-(.+)$")
    local myRegion, myRules = Bridge.World():match("^([^%-]+)%-(.+)$")
    if not region then return false end
    local function Same(a, b) return a == b or a == "?" or b == "?" end
    return Same(region, myRegion) and Same(rules, myRules)
end

-------------------------------------------------
-- Group
-------------------------------------------------

local groupServers, groupDirty = {}, true

-- Group members by compact name -> home server, read again after a roster change
function Bridge.GroupServers()
    if not groupDirty then return groupServers end
    local U = ns.Utils
    groupServers, groupDirty = {}, false
    local raid = U.SafeCall(IsInRaid)
    local count = raid and 40 or 4
    for i = 1, count do
        local unit = (raid and "raid" or "party") .. i
        local key = U.UnitKey(unit)
        local server = U.GUIDServer(U.UnitGUID(unit))
        local name = key and U.CompactName(key)
        if name and server then groupServers[name] = server end
    end
    return groupServers
end

function Bridge.GroupServer(sender)
    local name = ns.Utils.CompactName(sender)
    return name and Bridge.GroupServers()[name] or nil
end

-- A HeadHunter of another server is in our group, and we are our server's bridge in it:
-- the first by name of the HeadHunters of our server there
function Bridge.IsBridge()
    local U = ns.Utils
    local mine = U.PlayerServer()
    local me = U.CompactName(U.UnitKey("player"))
    if not mine or not me then return false, false end
    local first, others = me, false
    for name, server in pairs(Bridge.GroupServers()) do
        if ns.Presence:Knows(name) then
            if server ~= mine then
                others = true
            elseif name < first then
                first = name
            end
        end
    end
    return first == me, others
end

-------------------------------------------------
-- Seen keys (a ring) and carried keys
-------------------------------------------------

local seen, seenOrder, seenHead, seenCount = {}, {}, 1, 0
local carried = {}

local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

function Bridge.Key(author, typeCode, record)
    return (ns.Utils.CompactName(author) or "?") .. typeCode .. Hash(record)
end

local function Remember(key)
    if seen[key] then return end
    if seenCount >= Bridge.SEEN_MAX then
        local old = seenOrder[seenHead]
        seen[old], carried[old] = nil, nil
        seenOrder[seenHead] = key
        seenHead = seenHead % Bridge.SEEN_MAX + 1
    else
        seenCount = seenCount + 1
        seenOrder[seenCount] = key
    end
    seen[key] = true
end

function Bridge.SeenCount()
    return seenCount
end

-------------------------------------------------
-- Queue: carried records waiting for their hold and the budget
-------------------------------------------------

local queue = {}

function Bridge.Enabled()
    return ns.db ~= nil and ns.db.settings.relay ~= false and not ns.IsEra
end

local function Drop()
    local victim = 1
    for i, item in ipairs(queue) do
        if Bridge.LOW[item.env.type] then
            victim = i
            break
        end
    end
    table.remove(queue, victim)
    Bridge.stats.dropped = Bridge.stats.dropped + 1
end

-- route: "GROUP" or "CHANNEL"; remembered: the key is already in the seen ring (an
-- envelope we delivered and pass on)
function Bridge:Schedule(env, route, remembered)
    local key = Bridge.Key(env.author, env.type, env.record)
    if not remembered then
        if seen[key] then return false end
        Remember(key)
    end
    if #queue >= self.QUEUE_MAX then Drop() end
    local hold = self.HOLD_MIN + math.random() * (self.HOLD_MAX - self.HOLD_MIN)
    queue[#queue + 1] = { env = env, route = route, key = key, readyAt = ns.Utils.Now() + hold }
    return true
end

function Bridge.QueueCount()
    return #queue
end

-- The envelopes ready to go on one route, at most `limit`, own types first then the low
-- ones; a record someone else carried meanwhile is skipped
function Bridge:Take(route, limit)
    local now, records, keep = ns.Utils.Now(), {}, {}
    for pass = 1, 2 do
        for _, item in ipairs(queue) do
            local low = Bridge.LOW[item.env.type] == true
            if not item.taken and item.route == route and item.readyAt <= now and low == (pass == 2) then
                item.taken = true
                if carried[item.key] then
                    Bridge.stats.skipped = Bridge.stats.skipped + 1
                elseif #records < limit then
                    local encoded = ns.Protocol.EncodeEnvelope(item.env)
                    if encoded then records[#records + 1] = encoded end
                else
                    item.taken = nil
                end
            end
        end
    end
    for _, item in ipairs(queue) do
        if not item.taken then keep[#keep + 1] = item end
    end
    queue = keep
    Bridge.stats.forwarded = Bridge.stats.forwarded + #records
    return records
end

-------------------------------------------------
-- Heard directly: maybe carried on
-------------------------------------------------

local function Envelope(typeCode, record, author, faction, server, hops, at)
    return { world = Bridge.World(), author = author, faction = faction, server = server, hops = hops,
        at = at, type = typeCode, record = record }
end

-- A record straight from its author: from our channel (our server) on to the group, or
-- from a group member of another server on to our channel
function Bridge:Heard(typeCode, record, sender, faction, chatType)
    if not self.CARRIED[typeCode] or not self.Enabled() or not ns.Guards:IsActive() then return end
    local U = ns.Utils
    local mine = U.PlayerServer()
    if not mine then return end
    if chatType == "CHANNEL" then
        local bridge, others = self.IsBridge()
        if bridge and others then
            self:Schedule(Envelope(typeCode, record, sender, faction, mine, 1, U.ServerTime()), "GROUP")
        end
    elseif chatType == "PARTY" or chatType == "RAID" then
        local server = self.GroupServer(sender)
        if server and server ~= mine and self.IsBridge() then
            self:Schedule(Envelope(typeCode, record, sender, faction, server, 1, U.ServerTime()), "CHANNEL")
        end
    end
end

-------------------------------------------------
-- An envelope
-------------------------------------------------

local function Deliver(env, carrier)
    local T = env.type
    if T == TYPES.DEATH then
        ns.Reports:AddRelayed(env.record, carrier)
    elseif T == TYPES.JUSTICE then
        ns.Justice:AddRelayed(env.record, carrier, env.author)
    elseif T == TYPES.PUNISHMENT then
        ns.Punishments:AddRelayed(env.record, carrier)
    elseif T == TYPES.WITNESS then
        ns.Witness:AddRelayed(env.record, carrier)
    elseif T == TYPES.POSTER then
        ns.Bounties:AddRelayedPoster(env.record, carrier)
    elseif T == TYPES.PAYMENT then
        ns.Bounties:AddRelayedPayment(env.record, carrier)
    elseif T == TYPES.PRESENCE then
        ns.Presence:Heard(env.author, env.faction, env.record, env.server)
    else
        ns.Transport:Dispatch(T, env.record, env.author, env.faction, "RELAY")
    end
end

function Bridge:OnEnvelope(record, carrier, _, chatType)
    if not self.Enabled() then return end
    local U = ns.Utils
    local env = ns.Protocol.DecodeEnvelope(record)
    local now = U.ServerTime()
    if not env or not self.CARRIED[env.type] or not self.SameWorld(env.world)
        or env.hops < 1 or env.hops > self.MAX_HOPS
        or env.at > now + self.MAX_SKEW or now - env.at > self.LIFETIME
        or U.SameCharacter(env.author, carrier) then
        self.stats.refused = self.stats.refused + 1
        return
    end
    if U.SameCharacter(env.author, U.UnitKey("player")) then return end
    if env.faction ~= U.UnitFaction("player") and not CROSS_FACTION[env.type] then return end
    local key = self.Key(env.author, env.type, env.record)
    if seen[key] then
        carried[key] = true
        self.stats.duplicates = self.stats.duplicates + 1
        if self.COUNTED[env.type] then Deliver(env, carrier) end
        return
    end
    Remember(key)
    self.stats.delivered = self.stats.delivered + 1
    Deliver(env, carrier)
    if env.hops >= self.MAX_HOPS or not ns.Guards:IsActive() then return end
    local next = { world = env.world, author = env.author, faction = env.faction, server = env.server,
        hops = env.hops + 1, at = env.at, type = env.type, record = env.record }
    local mine = U.PlayerServer()
    if chatType == "CHANNEL" then
        local bridge, others = self.IsBridge()
        if bridge and others then self:Schedule(next, "GROUP", true) end
    elseif chatType == "PARTY" or chatType == "RAID" then
        local server = self.GroupServer(carrier)
        if server and mine and server ~= mine and self.IsBridge() then self:Schedule(next, "CHANNEL", true) end
    end
end

-------------------------------------------------
-- Links: the nameplate whisper
-------------------------------------------------

local asked, answered, pulled, sentThisMinute, minuteStart = {}, {}, {}, 0, 0

function Bridge:OnNameplate(unit)
    if not self.Enabled() or not ns.Guards:IsActive() then return end
    local U = ns.Utils
    if not U.SafeCall(UnitIsPlayer, unit) or U.SafeCall(UnitIsUnit, unit, "player") then return end
    if U.UnitFaction(unit) ~= U.UnitFaction("player") then return end
    if U.SafeCall(UnitInParty, unit) or U.SafeCall(UnitInRaid, unit) then return end
    local mine, theirs = U.PlayerServer(), U.GUIDServer(U.UnitGUID(unit))
    if not mine or not theirs or theirs == mine then return end
    local key = U.UnitKey(unit)
    local name = key and U.CompactName(key)
    if not name then return end
    local now = U.Now()
    if asked[name] and now - asked[name] < self.LINK_EVERY then return end
    if now - minuteStart >= 60 then minuteStart, sentThisMinute = now, 0 end
    if sentThisMinute >= self.LINK_PER_MINUTE then return end
    sentThisMinute = sentThisMinute + 1
    asked[name] = now
    ns.Transport:SendDirect(TYPES.LINK, { ns.Protocol.ToB36(mine) }, key)
end

function Bridge:OnLink(record, sender, faction, chatType)
    if chatType ~= "WHISPER" or not self.Enabled() then return end
    local U = ns.Utils
    local server = ns.Protocol.FromB36(record)
    local mine = U.PlayerServer()
    local name = U.CompactName(sender)
    if not server or not mine or server == mine or not name then return end
    ns.Presence:Heard(sender, faction, nil, server)
    local now = U.Now()
    if not answered[name] or now - answered[name] >= self.LINK_EVERY then
        answered[name] = now
        ns.Transport:SendDirect(TYPES.LINK, { ns.Protocol.ToB36(mine) }, sender)
    end
    if not pulled[name] or now - pulled[name] >= self.LINK_EVERY then
        pulled[name] = now
        self.stats.links = self.stats.links + 1
        ns.CatchUp:PullFrom(sender, U.ServerTime() - self.LINK_PULL_SINCE)
    end
end

-- Forget everything (tests)
function Bridge:Reset()
    seen, seenOrder, seenHead, seenCount, carried, queue = {}, {}, 1, 0, {}, {}
    asked, answered, pulled, sentThisMinute, minuteStart = {}, {}, {}, 0, 0
    groupServers, groupDirty, ruleset = {}, true, nil
    for k in pairs(self.stats) do self.stats[k] = 0 end
end

ns.Events:Register("HH_INITIALIZED", function()
    local Transport = ns.Transport
    Transport:RegisterHandler(TYPES.ENVELOPE, function(record, sender, faction, chatType)
        Bridge:OnEnvelope(record, sender, faction, chatType)
    end)
    Transport:RegisterHandler(TYPES.LINK, function(record, sender, faction, chatType)
        Bridge:OnLink(record, sender, faction, chatType)
    end)
    ns.Events:Register("GROUP_ROSTER_UPDATE", function() groupDirty = true end, OWNER)
    ns.Events:Register("NAME_PLATE_UNIT_ADDED", function(_, unit) Bridge:OnNameplate(unit) end, OWNER)
end, OWNER)
