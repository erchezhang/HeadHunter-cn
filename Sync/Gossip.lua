-- 1.0.4: sharing by addon whisper among the HeadHunters of the channel's member list.
--
-- Since WoW Forever's launch (2026-11-04) the server refuses addon messages on custom
-- channels: SendAddonMessage still answers 0, then a hidden notice (NOT_ALLOWED_IN_CHANNEL)
-- or code 7. Seen in game 2026-11-06: two characters in HeadHunterSync (129 members, of
-- several home servers), both sending "Success", neither receiving anything. Joining still
-- works, the member list can be read once it is asked for (SetSelectedDisplayChannel, as
-- Blizzard's Chat Channels window does), and addon whispers reach players of every home
-- server. So:
--   * Transport stops sending on the channel once it is refused (Transport:ChannelDeaf) and
--     tries it again every Transport.PROBE_EVERY seconds;
--   * the member list (names, home servers from the GUIDs) is read after joining and every
--     ROSTER_EVERY seconds, only while the Chat Channels window is closed, as asking for it
--     selects our channel there; it is also who is online (Sync/Presence.lua);
--   * a record of ours goes in an envelope (Protocol E, Sync/Bridge.lua) by whisper to
--     FANOUT members, who pass it on to FANOUT more, up to MAX_HOPS; the relay's seen keys
--     stop the copies, and its rules (world, faction, lifetime) apply to what arrives;
--   * the catch-up hello goes by whisper to HELLO_PEERS members (Sync/CatchUp.lua);
--   * a member the game answers with "No player named ..." is skipped for UNREACHABLE_FOR
--     seconds and the line is hidden; a member heard from tells their faction and world, and
--     only members of ours, or not known yet, get records;
--   * whispers have their own budget (PER_SECOND, BURST), at most PER_TARGET_MINUTE a minute
--     to one member; our own records go before carried ones, and LOW ones are dropped first;
--   * members known to run this gossip (they whispered us an envelope) are picked first, plus
--     DISCOVER unknown ones so newly updated players are found; while fewer than MANY_KNOWN
--     are known our own records go to OWN_FANOUT members (an older addon drops an envelope,
--     so in the first days most picks would end there).
-- WoW Forever only: Classic Era keeps its guild, group and whisper routes.

local addonName, ns = ...

local Gossip = ns:RegisterModule("Gossip", {})

local OWNER = "Gossip"

Gossip.FANOUT = 3
Gossip.OWN_FANOUT = 5
Gossip.DISCOVER = 1
Gossip.MANY_KNOWN = 10
Gossip.MAX_HOPS = 4
Gossip.HELLO_PEERS = 5
Gossip.ROSTER_EVERY = 300
Gossip.ROSTER_WAIT = 3
Gossip.ROSTER_RETRY = 30
Gossip.ROSTER_MAX = 500
Gossip.UNREACHABLE_FOR = 3600
Gossip.QUIET_FOR = 30
Gossip.PER_SECOND = 2
Gossip.BURST = 6
Gossip.PER_TARGET_MINUTE = 6
Gossip.QUEUE_MAX = 300
Gossip.FLUSH_EVERY = 0.5

local TYPES = ns.Protocol.TYPES

-- What spreads this way: what the relay carries, but presence (the member list says who is
-- online) and the manual ping
Gossip.SPREAD = {
    [TYPES.DEATH] = true, [TYPES.JUSTICE] = true, [TYPES.PUNISHMENT] = true, [TYPES.WITNESS] = true,
    [TYPES.POSTER] = true, [TYPES.PAYMENT] = true, [TYPES.GLASS] = true, [TYPES.DUEL] = true,
    [TYPES.POSSE] = true, [TYPES.SPOTTED] = true, [TYPES.HOTSPOT] = true, [TYPES.DUEL_SPOT] = true,
}
-- Sent last and dropped first when the budget runs short
Gossip.LOW = { [TYPES.HOTSPOT] = true, [TYPES.DUEL_SPOT] = true, [TYPES.DUEL] = true, [TYPES.GLASS] = true }

Gossip.stats = { spread = 0, passed = 0, sent = 0, failed = 0, dropped = 0, unreachable = 0, rosters = 0 }

-- compact name -> { key, server, faction, world, unreachableUntil, sentAt = { times } }
local peers = {}
local rosterCount = 0
local rosterAt
local rosterPending = false
local queue = {}
local seq = 0
local tokens = Gossip.BURST
local refilledAt
-- compact name -> when we last whispered them (for the "No player named" line)
local recent = {}

function Gossip.Enabled()
    return not ns.IsEra and ns.Features.RealmlessNames == true and ns.Bridge.Enabled()
end

-- Sharing goes by whisper while the channel does not carry our messages
function Gossip:Active()
    return self.Enabled() and ns.Guards:IsActive() and not ns.Transport:ChannelWorks()
end

function Gossip:PeerCount()
    return rosterCount
end

function Gossip:QueueCount()
    return #queue
end

-- The members not known to be out of reach, and how many are known to be of our faction
function Gossip:Reachable()
    local now, mine = ns.Utils.Now(), ns.Utils.UnitFaction("player")
    local reachable, ours = 0, 0
    for _, peer in pairs(peers) do
        if not peer.me and (peer.unreachableUntil or 0) <= now then
            reachable = reachable + 1
            if peer.faction == mine then ours = ours + 1 end
        end
    end
    return reachable, ours
end

-------------------------------------------------
-- The member list
-------------------------------------------------

-- Our channel's place in the channel list (Blizzard's channel "ID" for the roster calls)
function Gossip.ChannelIndex()
    local count = tonumber(ns.Utils.SafeCall(GetNumDisplayChannels)) or 30
    local ours = ns.Transport.CHANNEL:lower()
    for i = 1, count do
        local name = ns.Utils.SafeCall(GetChannelDisplayInfo, i)
        if type(name) == "string" and (name:match("^%d+%. (.+)$") or name):lower() == ours then return i end
    end
    return nil
end

local function ChannelWindowOpen()
    local frame = _G.ChannelFrame
    return frame ~= nil and frame.IsShown ~= nil and frame:IsShown() == true
end

-- The members of our channel by compact name, from the roster the server sent
function Gossip:ReadRoster(index)
    local U = ns.Utils
    local count = tonumber((select(5, U.SafeCall(GetChannelDisplayInfo, index)))) or 0
    if count <= 0 or not (C_ChatInfo and C_ChatInfo.GetChannelRosterInfo) then return nil end
    local members, me = {}, U.CompactName(U.UnitKey("player"))
    for r = 1, math.min(count, self.ROSTER_MAX) do
        local ok, name, _, _, guid = pcall(C_ChatInfo.GetChannelRosterInfo, index, r)
        local compact = ok and U.CompactName(name)
        if compact then
            members[compact] = { key = U.PlayerKey(name) or name, server = U.GUIDServer(guid), me = compact == me }
        end
    end
    return members
end

function Gossip:ApplyRoster(members)
    local kept = {}
    local count = 0
    for name, member in pairs(members) do
        local peer = peers[name] or {}
        peer.key, peer.server, peer.me = member.key, member.server or peer.server, member.me
        kept[name] = peer
        count = count + 1
    end
    peers, rosterCount, rosterAt = kept, count, ns.Utils.Now()
    self.stats.rosters = self.stats.rosters + 1
    ns.Presence:SetRoster(kept)
    ns:Debug("Gossip: member list read,", count, "members")
end

-- Asks the server for the member list (as selecting the channel in the Chat Channels window
-- does), then reads it ROSTER_WAIT seconds later; later while that window is open
function Gossip:RequestRoster()
    if rosterPending or not self.Enabled() then return end
    local index = self.ChannelIndex()
    if not index or ChannelWindowOpen() then
        C_Timer.After(self.ROSTER_RETRY, function() self:RequestRoster() end)
        return
    end
    rosterPending = true
    pcall(SetSelectedDisplayChannel, index)
    C_Timer.After(self.ROSTER_WAIT, function()
        rosterPending = false
        local now = self.ChannelIndex()
        local members = now and self:ReadRoster(now)
        if members and next(members) then self:ApplyRoster(members) end
    end)
end

-------------------------------------------------
-- Members heard from
-------------------------------------------------

-- A whisper from a member says their faction and that they can be reached; one that
-- carried an envelope (world given) also runs this gossip
function Gossip:Heard(sender, faction, world)
    local name = ns.Utils.CompactName(sender)
    if not name then return end
    local peer = peers[name]
    if not peer then
        peer = { key = sender }
        peers[name] = peer
    end
    peer.faction = faction or peer.faction
    peer.world = world or peer.world
    peer.modern = peer.modern or world ~= nil
    peer.unreachableUntil = nil
end

-- Members known to run this gossip and in reach
function Gossip:KnownCount()
    local now, n = ns.Utils.Now(), 0
    for _, peer in pairs(peers) do
        if peer.modern and not peer.me and (peer.unreachableUntil or 0) <= now then n = n + 1 end
    end
    return n
end

local function Eligible(name, peer, now, mine, exclude)
    if peer.me or exclude[name] or (peer.unreachableUntil or 0) > now then return false end
    if peer.faction and peer.faction ~= mine then return false end
    if peer.world and not ns.Bridge.SameWorld(peer.world) then return false end
    local sent = 0
    for _, at in ipairs(peer.sentAt or {}) do
        if now - at < 60 then sent = sent + 1 end
    end
    return sent < Gossip.PER_TARGET_MINUTE
end

local function Shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- Up to `count` members known to run this gossip, at random, then unknown ones for the
-- rest and at least DISCOVER of them; none of `exclude` (compact names)
function Gossip:Pick(count, exclude)
    local now, mine = ns.Utils.Now(), ns.Utils.UnitFaction("player")
    local known, unknown = {}, {}
    for name, peer in pairs(peers) do
        if Eligible(name, peer, now, mine, exclude or {}) then
            local list = peer.modern and known or unknown
            list[#list + 1] = peer
        end
    end
    Shuffle(known)
    Shuffle(unknown)
    local picked = {}
    for i = 1, math.min(count, #known) do picked[#picked + 1] = known[i] end
    local discover = math.max(self.DISCOVER, count - #picked)
    for i = 1, math.min(discover, #unknown) do picked[#picked + 1] = unknown[i] end
    return picked
end

-------------------------------------------------
-- Queue and budget
-------------------------------------------------

local function Drop()
    local victim = 1
    for i, item in ipairs(queue) do
        if item.low then
            victim = i
            break
        end
    end
    table.remove(queue, victim)
    Gossip.stats.dropped = Gossip.stats.dropped + 1
end

local function Add(peer, typeCode, record, own, low)
    if #queue >= Gossip.QUEUE_MAX then Drop() end
    seq = seq + 1
    queue[#queue + 1] = { target = peer.key, name = ns.Utils.CompactName(peer.key), type = typeCode, record = record,
        own = own, low = low, seq = seq }
end

local function Order(a, b)
    if a.own ~= b.own then return a.own end
    if a.low ~= b.low then return not a.low end
    return a.seq < b.seq
end

-- Whispers what the budget allows: for each target in turn, all its waiting records of one
-- type packed together
function Gossip:Flush()
    if #queue == 0 then return end
    if not ns.Guards:IsActive() then return end
    local U = ns.Utils
    local faction = ns.Protocol.FACTION_CODE[U.UnitFaction("player") or ""]
    if not faction then return end
    local now = U.Now()
    refilledAt = refilledAt or now
    tokens = math.min(self.BURST, tokens + (now - refilledAt) * self.PER_SECOND)
    refilledAt = now
    table.sort(queue, Order)
    while #queue > 0 and tokens >= 1 do
        local first = queue[1]
        local records, keep = {}, {}
        for _, item in ipairs(queue) do
            if item.target == first.target and item.type == first.type then
                records[#records + 1] = item.record
            else
                keep[#keep + 1] = item
            end
        end
        queue = keep
        local peer = peers[first.name]
        for _, message in ipairs(ns.Protocol.Pack(faction, first.type, records)) do
            if tokens < 1 then
                self.stats.dropped = self.stats.dropped + 1
            else
                tokens = tokens - 1
                recent[first.name] = now
                if peer then
                    peer.sentAt = peer.sentAt or {}
                    peer.sentAt[#peer.sentAt + 1] = now
                    while #peer.sentAt > self.PER_TARGET_MINUTE do table.remove(peer.sentAt, 1) end
                end
                if ns.Transport:Whisper(message, first.target) then
                    self.stats.sent = self.stats.sent + 1
                else
                    self.stats.failed = self.stats.failed + 1
                end
            end
        end
    end
end

-------------------------------------------------
-- Spreading
-------------------------------------------------

-- An envelope to FANOUT members, none of `exclude`; returns how many it went to
function Gossip:Pass(env, exclude, own)
    local encoded = ns.Protocol.EncodeEnvelope(env)
    if not encoded then return 0 end
    local fanout = (own and self:KnownCount() < self.MANY_KNOWN) and self.OWN_FANOUT or self.FANOUT
    local picked = self:Pick(fanout, exclude)
    for _, peer in ipairs(picked) do Add(peer, TYPES.ENVELOPE, encoded, own, self.LOW[env.type] == true) end
    return #picked
end

-- A record of ours, queued for the automatic routes: also whispered on while the channel
-- does not carry it. Returns true when it went into the gossip.
function Gossip:Spread(typeCode, record)
    if not self.SPREAD[typeCode] or not self:Active() then return false end
    local U = ns.Utils
    local env = { world = ns.Bridge.World(), author = U.UnitKey("player"), faction = U.UnitFaction("player"),
        server = U.PlayerServer(), hops = 1, at = U.ServerTime(), type = typeCode, record = record }
    if not env.author or not env.faction then return false end
    ns.Bridge:MarkSeen(ns.Bridge.Key(env.author, typeCode, record))
    self.stats.spread = self.stats.spread + 1
    return self:Pass(env, nil, true) > 0
end

-- A carried envelope we have just delivered: on to FANOUT more, until MAX_HOPS
function Gossip:Forward(env, carrier)
    if env.hops >= self.MAX_HOPS or env.type == TYPES.PING or not self:Active() then return end
    local U = ns.Utils
    local next = { world = env.world, author = env.author, faction = env.faction, server = env.server,
        hops = env.hops + 1, at = env.at, type = env.type, record = env.record }
    local exclude = {}
    for _, who in ipairs({ carrier, env.author }) do
        local name = U.CompactName(who)
        if name then exclude[name] = true end
    end
    if self:Pass(next, exclude, false) > 0 then self.stats.passed = self.stats.passed + 1 end
end

-- The catch-up hello: to HELLO_PEERS members, who answer by whisper as to a channel hello
function Gossip:Ask(record)
    if not self:Active() then return false end
    local picked = self:Pick(self.HELLO_PEERS)
    for _, peer in ipairs(picked) do Add(peer, TYPES.QUERY, record, true, false) end
    return #picked > 0
end

-- /hh sync gossip "<name>": a test ping in an envelope to one player, the way gossip sends
-- (its receiver shows it, and never passes a ping on). Returns true when it was queued.
function Gossip:Test(target)
    local U = ns.Utils
    local name = U.CompactName(target)
    local env = { world = ns.Bridge.World(), author = U.UnitKey("player"), faction = U.UnitFaction("player"),
        server = U.PlayerServer(), hops = 1, at = U.ServerTime(), type = TYPES.PING, record = "gossip " .. date("%H:%M:%S") }
    local encoded = name and env.author and env.faction and ns.Protocol.EncodeEnvelope(env)
    if not encoded then return false end
    ns.Bridge:MarkSeen(ns.Bridge.Key(env.author, env.type, env.record))
    Add(peers[name] or { key = target }, TYPES.ENVELOPE, encoded, true, false)
    return true
end

-------------------------------------------------
-- "No player named X is currently playing."
-------------------------------------------------

local notFound

local function NotFoundPattern()
    if notFound ~= nil then return notFound end
    local format = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
    if type(format) ~= "string" then
        notFound = false
        return notFound
    end
    local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    notFound = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
    return notFound
end

-- The member a "not found" line names, when we whispered them within QUIET_FOR
function Gossip.NotFound(text)
    local pattern = NotFoundPattern()
    if not pattern or type(text) ~= "string" then return nil end
    local name = ns.Utils.CompactName(text:match(pattern))
    local at = name and recent[name]
    if at and ns.Utils.Now() - at <= Gossip.QUIET_FOR then return name end
    return nil
end

function Gossip:OnSystemMessage(text)
    local name = self.NotFound(text)
    if not name then return end
    local peer = peers[name]
    if peer then
        peer.unreachableUntil = ns.Utils.Now() + self.UNREACHABLE_FOR
        self.stats.unreachable = self.stats.unreachable + 1
    end
end

function Gossip.SystemFilter(_, _, text)
    return Gossip.NotFound(text) ~= nil
end

-- Forget everything (tests)
function Gossip:Reset()
    peers, rosterCount, rosterAt, rosterPending, queue, recent = {}, 0, nil, false, {}, {}
    tokens, refilledAt, seq = self.BURST, nil, 0
    for k in pairs(self.stats) do self.stats[k] = 0 end
end

local function FlushLoop()
    C_Timer.After(Gossip.FLUSH_EVERY, function()
        local ok, err = pcall(Gossip.Flush, Gossip)
        if not ok then ns:Error(err) end
        FlushLoop()
    end)
end

local function RosterLoop()
    C_Timer.After(Gossip.ROSTER_EVERY, function()
        Gossip:RequestRoster()
        RosterLoop()
    end)
end

ns.Events:Register("HH_INITIALIZED", function()
    if not Gossip.Enabled() then return end
    ns.Events:Register("CHAT_MSG_SYSTEM", function(_, text) Gossip:OnSystemMessage(text) end, OWNER)
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then pcall(add, "CHAT_MSG_SYSTEM", Gossip.SystemFilter) end
    ns.Events:Register("HH_SYNC_CHANNEL_JOINED", function() Gossip:RequestRoster() end, OWNER)
    FlushLoop()
    RosterLoop()
end, OWNER)
