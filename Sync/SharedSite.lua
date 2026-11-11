-- HH-141: the website's lists, shared in game (author, 2026-10-10: players without
-- HeadHunter Sync never got the website's WANTED, Hall of Shame and Deadbeats).
--
-- Who shares: a HeadHunter whose sync app downloaded the lists (Sync/SiteData.lua) shares
-- its own download, never one it heard: the sender is the voucher, so nothing is relayed.
-- Trust: an entry counts once VOUCHERS different HeadHunters shared it from their current
-- list (author: two vouchers, like relayed reports, Sync/Relay.lua). A voucher whose newer
-- list no longer has an entry stops vouching for it (withdrawn on the website), after
-- GRACE seconds while the rest of that list arrives. The entry kept is the one from the
-- newest list. Our own download stays the source for us (author): shared entries only
-- fill gaps, or replace an older download.
--
-- Sending (on the automatic routes; Classic Era: guild and group, as channels refuse
-- addon messages there):
--   broadcast  after our list loads, a random wait of DELAY_MIN..DELAY_MAX seconds, and
--              nothing when SUPPRESS others already shared the same or a newer list; at
--              most once per BROADCAST_EVERY. Entries sent before this session in the same
--              shape go as a short "keep" record. At most BROADCAST_MAX per list.
--   catch-up   in the answer to a pull (Sync/CatchUp.lua), at most CATCHUP_MAX per list.
--
-- Records (protocol type C, fields ";", numbers base36), first letter the kind:
--   L gen                                        a list: everything after it is its content
--   W gen key rank kills*10 until since lastT lastMap level class race killCount coward timesWanted timesCaught
--   B gen key coward killCount lastT level class race
--   D gen key unpaid blockedUntil
--   P gen owner t target reason gold until class race sex      HH-158: a running players' bounty
--   k gen kind key                               "still on my list", unchanged
--
-- HH-158 (author, 2026-11-11): players' bounties count by sources, not vouchers alone
-- (Relay.Counts): two different characters among the vouchers and the peers who relayed
-- the poster to us, or the owner among them. Their key is the poster id. The lists are
-- told only when a bounty starts or stops counting, or a target comes or goes.
--
-- Performance (author): receiving runs in the transport inbox (3 ms a frame); one WANTED
-- recount (debounced, budgeted) only when an entry starts or stops counting; at most
-- PER_LIST entries per kind are kept, expired ones are pruned on a timer.

local addonName, ns = ...

local SharedSite = ns:RegisterModule("SharedSite", {})

local OWNER = "SharedSite"

SharedSite.KINDS = { "W", "B", "D", "P" }

SharedSite.TYPE = "C"
SharedSite.VOUCHERS = 2
SharedSite.GRACE = 120
SharedSite.DELAY_MIN = 5
SharedSite.DELAY_MAX = 60
SharedSite.SUPPRESS = 2
SharedSite.BROADCAST_EVERY = 600
SharedSite.BROADCAST_MAX = 100
SharedSite.CATCHUP_MAX = 300
SharedSite.PER_LIST = 500
SharedSite.ORIGIN = "shared"
-- A full catch-up answer and a broadcast of every kind, with their list markers
SharedSite.SENDER_LIMIT = #SharedSite.KINDS * (SharedSite.CATCHUP_MAX + SharedSite.BROADCAST_MAX) + 2
SharedSite.SENDER_WINDOW = 600
SharedSite.PRUNE_EVERY = 60

-- kind -> key -> { entry, gen, vouches = { [voucher] = gen } }; Deadbeats by compact name, as
-- Sync/SiteData.lua keeps them; players' bounties by poster id
local store = { W = {}, B = {}, D = {}, P = {} }
-- voucher -> { gen, previous, changedAt }
local lists = {}
-- voucher -> list of arrival times, for the rate limit
local arrivals = {}
-- what we broadcast this session: kind .. key -> encoded payload
local sent = {}
local lastBroadcast = nil
-- HH-158: SharedSite:Posters, kept for one second of server time while nothing changed
local postersVersion, postersCache = 0, nil

local function B36(n) return ns.Protocol.ToB36(math.floor(tonumber(n) or 0)) end
local function Num(s) return s and s ~= "" and ns.Protocol.FromB36(s) or nil end
local function Text(s) return s ~= nil and s ~= "" and s or nil end

-------------------------------------------------
-- Encoding
-------------------------------------------------

function SharedSite.EncodeWanted(gen, e)
    return table.concat({ "W", B36(gen), e.key, e.rank, B36((e.kills or 0) * 10), B36(e.wantedUntil),
        B36(e.wantedSince), B36(e.lastKill and e.lastKill.t), B36(e.lastKill and e.lastKill.mapID),
        B36(e.level), e.class or "", e.race or "", B36(e.killCount), B36(e.cowardKills),
        B36(e.timesWanted), B36(e.timesCaught) }, ";")
end

function SharedSite.EncodeBully(gen, e)
    return table.concat({ "B", B36(gen), e.key, B36(e.cowardKills), B36(e.killCount),
        B36(e.lastKill and e.lastKill.t), B36(e.level), e.class or "", e.race or "" }, ";")
end

function SharedSite.EncodeDeadbeat(gen, d)
    return table.concat({ "D", B36(gen), d.key, B36(d.unpaid), B36(d.blockedUntil) }, ";")
end

-- item: { key = poster id, poster, target = the target's entry or nil }
function SharedSite.EncodePoster(gen, item)
    local p, target = item.poster, item.target or {}
    return table.concat({ "P", B36(gen), p.owner, B36(p.t), p.target, B36(p.reason), B36(p.gold), B36(p["until"]),
        target.class or "", target.race or "", B36(target.sex) }, ";")
end

-- The payload without the list time, to tell whether an entry changed since we sent it
local function Shape(encoded)
    return (encoded:gsub("^(%a);[^;]*;", "%1;"))
end

local function Split(s)
    local fields = {}
    for field in (s .. ";"):gmatch("([^;]*);") do fields[#fields + 1] = field end
    return fields
end

-- record -> kind, gen, key, entry (nil for a list marker or a keep record's entry)
function SharedSite.Decode(record)
    if type(record) ~= "string" or #record < 3 then return nil end
    local f = Split(record)
    local kind, gen = f[1], Num(f[2])
    if not gen then return nil end
    if kind == "L" then return "L", gen end
    if kind == "k" then
        return Text(f[4]) and ("k" .. (f[3] or "")) or nil, gen, Text(f[4])
    end
    local key = Text(f[3])
    if not key then return nil end
    if kind == "W" and #f == 16 then
        local rank, untilT = f[4], Num(f[6])
        if not untilT or not ns.RulesEngine.RANK_ORDER[rank] then return nil end
        local kills = (Num(f[5]) or 0) / 10
        local lastT = Num(f[8])
        return "W", gen, key, {
            id = key, key = key, name = key, level = Num(f[10]), class = Text(f[11]), race = Text(f[12]),
            wanted = true, rank = rank, peakRank = rank, kills = kills,
            wantedSince = Num(f[7]), wantedUntil = untilT,
            killCount = Num(f[13]) or math.floor(kills), cowardKills = Num(f[14]) or 0,
            timesWanted = Num(f[15]) or 1, timesCaught = Num(f[16]) or 0,
            badges = {}, lastKill = lastT and { t = lastT, mapID = Num(f[9]) } or nil,
            source = "website",
        }
    elseif kind == "B" and #f == 9 then
        local coward = Num(f[4]) or 0
        if coward < 1 then return nil end
        local lastT = Num(f[6])
        return "B", gen, key, {
            id = key, key = key, name = key, level = Num(f[7]), class = Text(f[8]), race = Text(f[9]),
            wanted = false, kills = 0, timesWanted = 0, timesCaught = 0,
            killCount = Num(f[5]) or coward, cowardKills = coward, badges = { coward = true },
            lastKill = lastT and { t = lastT } or nil, source = "website",
        }
    elseif kind == "D" and #f == 5 then
        local untilT = Num(f[5])
        if not untilT then return nil end
        return "D", gen, key, { key = key, unpaid = Num(f[4]) or 2, blockedUntil = untilT }
    elseif kind == "P" and #f == 11 then
        return SharedSite.DecodePoster(gen, key, f)
    end
    return nil
end

-- A players' bounty record's fields -> "P", gen, poster id, { poster, target }, or nil.
-- The poster passes the checks of every poster (Bounties.ValidPoster); its author is the
-- owner, for Relay.Counts.
function SharedSite.DecodePoster(gen, ownerKey, f)
    local poster = { owner = ownerKey, t = Num(f[4]), target = Text(f[5]), reason = Num(f[6]), gold = Num(f[7]),
        ["until"] = Num(f[8]), origin = SharedSite.ORIGIN }
    if not poster.t or not poster.target or not poster.reason or not poster.gold or not poster["until"] then return nil end
    if not ns.Bounties.ValidPoster(poster) then return nil end
    poster.author = poster.owner
    return "P", gen, poster.id, {
        poster = poster,
        target = ns.SiteData.BountyTargetEntry(poster.target, Text(f[9]), Text(f[10]), Num(f[11])),
    }
end

-------------------------------------------------
-- Receiving
-------------------------------------------------

local function UnderRateLimit(voucher, now)
    local list = arrivals[voucher] or {}
    local kept = {}
    for _, t in ipairs(list) do
        if now - t < SharedSite.SENDER_WINDOW then kept[#kept + 1] = t end
    end
    if #kept >= SharedSite.SENDER_LIMIT then
        arrivals[voucher] = kept
        return false
    end
    kept[#kept + 1] = now
    arrivals[voucher] = kept
    return true
end

-- A voucher's word still holds for this list time: its current list, or its previous one
-- for GRACE seconds while the new one arrives
local function Holds(voucher, gen, now)
    local list = lists[voucher]
    if not list then return false end
    if gen == list.gen then return true end
    return gen == list.previous and now - list.changedAt < SharedSite.GRACE
end

local function Counts(slot, now)
    local count = 0
    for voucher, gen in pairs(slot.vouches) do
        if Holds(voucher, gen, now) then count = count + 1 end
    end
    return count >= SharedSite.VOUCHERS
end

local function NoteList(voucher, gen, now)
    local list = lists[voucher]
    if not list then
        lists[voucher] = { gen = gen, changedAt = now }
    elseif gen > list.gen then
        lists[voucher] = { gen = gen, previous = list.gen, changedAt = now }
    end
end

local function Size(kind)
    local n = 0
    for _ in pairs(store[kind]) do n = n + 1 end
    return n
end

-- HH-158: a bounty slot as a poster, when others shared it from a list newer than our own
-- download and one of them still vouches: a copy with vouchers = { [compact name] = true }
local function SharedCopy(slot, now, ownGen)
    if ownGen and slot.gen <= ownGen then return nil end
    local vouchers, any = {}, false
    for voucher, gen in pairs(slot.vouches) do
        if Holds(voucher, gen, now) then vouchers[voucher], any = true, true end
    end
    if not any then return nil end
    local copy = {}
    for k, v in pairs(slot.entry.poster) do copy[k] = v end
    copy.vouchers = vouchers
    return copy
end

-- Does a bounty slot count now, with the peers who relayed our copy? Stored on the slot;
-- true when that changed
local function NoteCounting(slot, now)
    local copy = SharedCopy(slot, now, ns.SiteData:GeneratedAt())
    local counts = copy ~= nil and ns.Relay.Counts(ns.Bounties:WithOurRelay(copy))
    if counts == (slot.counting == true) then return false end
    slot.counting = counts
    return true
end

-- One record from a HeadHunter's own list. Returns true when the record was taken.
function SharedSite:OnRecord(record, sender, now)
    local voucher = sender and ns.Utils.CompactName(sender)
    if not voucher then return false end
    now = now or ns.Utils.ServerTime()
    if not UnderRateLimit(voucher, now) then return false end
    local kind, gen, key, entry = SharedSite.Decode(record)
    if not kind then return false end
    local list = lists[voucher]
    if list and gen < list.gen and gen ~= list.previous then return false end
    NoteList(voucher, gen, now)
    if kind == "L" then return true end

    local real = kind:sub(1, 1) == "k" and kind:sub(2) or kind
    local slots = store[real]
    if not slots then return false end
    if real == "D" then key = ns.Utils.CompactName(key) end
    if not key then return false end
    local slot, created = slots[key], false
    if not slot then
        if not entry or Size(real) >= SharedSite.PER_LIST then return false end
        slot, created = { vouches = {} }, true
        slots[key] = slot
    end
    local before = Counts(slot, now)
    if entry and (not slot.gen or gen >= slot.gen) then
        slot.entry, slot.gen = entry, gen
    end
    if not slot.entry then
        slots[key] = nil
        return false
    end
    slot.vouches[voucher] = math.max(slot.vouches[voucher] or 0, gen)
    if real == "P" then
        postersVersion = postersVersion + 1
        if created then ns.Wanted:RequestRecompute() end
        if NoteCounting(slot, now) then ns.Events:Fire("HH_BOUNTY_UPDATED") end
    elseif Counts(slot, now) ~= before and real ~= "D" then
        ns.Wanted:RequestRecompute()
    end
    return true
end

-------------------------------------------------
-- Reading: what counts, after our own download
-------------------------------------------------

-- The counting entries of a kind, unless our own download is as new or newer: then it
-- has the website's word on every entry, also the ones it no longer lists (author: our
-- own download stays the source). id -> entry
local function Counting(kind, now)
    now = now or ns.Utils.ServerTime()
    local ownGen = ns.SiteData:GeneratedAt()
    local result = {}
    for key, slot in pairs(store[kind]) do
        if (not ownGen or slot.gen > ownGen) and Counts(slot, now) then result[key] = slot.entry end
    end
    return result
end

-- The website's WANTED others shared, for Wanted.MergeSite: id -> entry
function SharedSite:Wanted(now)
    return Counting("W", now)
end

-- The website's Hall of Shame others shared, for Wanted.MergeBullies: id -> entry
function SharedSite:Bullies(now)
    return Counting("B", now)
end

-- A Deadbeat others shared: { key, unpaid, blockedUntil } or nil
function SharedSite:Deadbeat(key, now)
    local id = key and ns.Utils.CompactName(key)
    local slot = id and store.D[id]
    if not slot then return nil end
    return Counting("D", now)[id]
end

-- Every Deadbeat others shared: compact name -> record
function SharedSite:Deadbeats(now)
    return Counting("D", now)
end

-- HH-158: the players' bounties others shared from a list newer than our own download,
-- with at least one voucher whose word holds; Relay.Counts decides whether each counts.
-- poster id -> a copy with vouchers. Read often (sightings, tooltips, the board), so built
-- once per second of server time while nothing changed; callers must not change it.
function SharedSite:Posters(now)
    now = now or ns.Utils.ServerTime()
    local ownGen = ns.SiteData:GeneratedAt()
    local cache = postersCache
    if cache and cache.version == postersVersion and cache.now == now and cache.ownGen == ownGen then
        return cache.result
    end
    local result = {}
    for id, slot in pairs(store.P) do result[id] = SharedCopy(slot, now, ownGen) end
    postersCache = { version = postersVersion, now = now, ownGen = ownGen, result = result }
    return result
end

-- Their targets, for Wanted.MergeBountyTargets: id -> entry
function SharedSite:BountyTargets(now)
    local result = {}
    for id in pairs(self:Posters(now)) do
        local target = store.P[id].entry.target
        result[target.id] = result[target.id] or target
    end
    return result
end

-------------------------------------------------
-- Sending
-------------------------------------------------

-- Our own download's records, best first, at most `max` per list: the marker first
function SharedSite.Records(max, keepUnchanged)
    local gen = ns.SiteData:GeneratedAt()
    if not gen then return {} end
    local records = { "L;" .. B36(gen) }
    local function Add(kind, list, encode, better)
        local entries = {}
        for _, e in pairs(list or {}) do entries[#entries + 1] = e end
        table.sort(entries, better)
        for i = 1, math.min(max, #entries) do
            local encoded = encode(gen, entries[i])
            local key = kind .. (entries[i].key or "")
            if keepUnchanged and sent[key] == Shape(encoded) then
                records[#records + 1] = table.concat({ "k", B36(gen), kind, entries[i].key }, ";")
            else
                records[#records + 1] = encoded
            end
            if keepUnchanged then sent[key] = Shape(encoded) end
        end
    end
    local now = ns.Utils.ServerTime()
    local wanted = {}
    for id, e in pairs(ns.SiteData:Wanted() or {}) do
        if (e.wantedUntil or 0) > now then wanted[id] = e end
    end
    Add("W", wanted, SharedSite.EncodeWanted, function(a, b) return (a.kills or 0) > (b.kills or 0) end)
    Add("B", ns.SiteData:Bullies(), SharedSite.EncodeBully, function(a, b) return (a.cowardKills or 0) > (b.cowardKills or 0) end)
    local deadbeats = {}
    for _, d in pairs(ns.SiteData:Deadbeats()) do
        if (d.blockedUntil or 0) > now then deadbeats[#deadbeats + 1] = d end
    end
    Add("D", deadbeats, SharedSite.EncodeDeadbeat, function(a, b) return (a.blockedUntil or 0) > (b.blockedUntil or 0) end)
    local posters, targets = {}, ns.SiteData:BountyTargets()
    for id, p in pairs(ns.SiteData:Posters()) do
        if p["until"] > now then posters[#posters + 1] = { key = id, poster = p, target = targets[p.target] } end
    end
    Add("P", posters, SharedSite.EncodePoster, function(a, b) return a.poster.t > b.poster.t end)
    return records
end

-- How many other HeadHunters shared a list as new as ours or newer
local function HeardAsNew(gen)
    local count = 0
    for _, list in pairs(lists) do
        if list.gen >= gen then count = count + 1 end
    end
    return count
end

-- After our list loaded: a random wait, then share it unless enough others did
function SharedSite:ScheduleBroadcast()
    local gen = ns.SiteData:GeneratedAt()
    if not gen then return end
    local wait = self.DELAY_MIN + math.random() * (self.DELAY_MAX - self.DELAY_MIN)
    C_Timer.After(wait, function() SharedSite:Broadcast(gen) end)
end

-- Returns how many records went to the outbox
function SharedSite:Broadcast(gen)
    local now = ns.Utils.ServerTime()
    if gen ~= ns.SiteData:GeneratedAt() then return 0 end
    if lastBroadcast and now - lastBroadcast < self.BROADCAST_EVERY then return 0 end
    if HeardAsNew(gen) >= self.SUPPRESS then
        ns:Debug("Website lists already shared by", self.SUPPRESS, "others")
        return 0
    end
    lastBroadcast = now
    local records = SharedSite.Records(self.BROADCAST_MAX, true)
    local P = ns.Transport.PRIORITY
    for i, record in ipairs(records) do
        ns.Transport:Queue(self.TYPE, record, P.bulk, "C:" .. i .. ":" .. record:sub(1, 1) .. (record:match("^%a;[^;]*;([^;]*)") or ""))
    end
    return #records
end

-- When an entry of a kind ends by itself; bullies have no end
local ENDS = {
    W = function(entry) return entry.wantedUntil or 0 end,
    D = function(entry) return entry.blockedUntil or 0 end,
    P = function(entry) return entry.poster["until"] end,
}

-- Expired entries go by their own end, any entry when nobody vouches. A bounty that
-- stops or starts counting here (a voucher's word ran out, HH-158) refreshes the lists.
function SharedSite:Prune(now)
    now = now or ns.Utils.ServerTime()
    local bountiesBefore = Size("P")
    for kind, ends in pairs(ENDS) do
        for key, slot in pairs(store[kind]) do
            if ends(slot.entry) <= now then store[kind][key] = nil end
        end
    end
    for _, kind in ipairs(self.KINDS) do
        for key, slot in pairs(store[kind]) do
            local holds = false
            for voucher, gen in pairs(slot.vouches) do holds = holds or Holds(voucher, gen, now) end
            if not holds then store[kind][key] = nil end
        end
    end
    postersVersion = postersVersion + 1
    local changed = false
    for _, slot in pairs(store.P) do changed = NoteCounting(slot, now) or changed end
    local gone = Size("P") ~= bountiesBefore
    if gone then ns.Wanted:RequestRecompute() end
    if changed or gone then ns.Events:Fire("HH_BOUNTY_UPDATED") end
end

-- For tests
function SharedSite:Reset()
    store = { W = {}, B = {}, D = {}, P = {} }
    lists, arrivals, sent, lastBroadcast = {}, {}, {}, nil
    postersVersion, postersCache = 0, nil
end

local function PruneTicker()
    C_Timer.After(SharedSite.PRUNE_EVERY, function()
        SharedSite:Prune()
        PruneTicker()
    end)
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Transport:RegisterHandler(SharedSite.TYPE, function(record, sender) SharedSite:OnRecord(record, sender) end)
    PruneTicker()
end, OWNER)

ns.Events:Register("PLAYER_LOGIN", function() SharedSite:ScheduleBroadcast() end, OWNER)
ns.Events:Register("HH_HOME_CHANGED", function() SharedSite:ScheduleBroadcast() end, OWNER)
