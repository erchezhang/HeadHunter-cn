-- Punished (author, 2026-10-20): a Hall of Shame player who is not WANTED, a bully or the
-- other faction's Deadbeat, brought down by a HeadHunter or their group (HH_SHAME_KILLED,
-- Sync/Justice.lua). A WANTED bully stays a catch (Busted). Shown in the Punished tab next
-- to Busted; any HeadHunter can raise a glass to one as to a bust (Sync/Glasses.lua,
-- caughtAt = the punishment's time).
--
-- ns.db.punishments: id "<outlaw>:<t>:<by>" -> { id, outlaw, t, by (the HeadHunter
--   credited), kind ("bully" | "deadbeat"), mapID, killer (who landed the blow),
--   killerClass, killerRace, killerSex, killerFaction, killerLevel (as a catch),
--   outlawWho = { class, race, sex, level, faction }, origin ("local" | "peer" | "relay"),
--   sender }, kept as long as the catches (Reports.MAX_AGE).
-- One per bully per hour (the +3 bounty's Marks.BULLY_COOLDOWN), by whoever came first:
-- a group's HeadHunters all see the kill. None when we hunt 10+ levels down (no bounty
-- either). Shared with type "F" (older addons ignore it; the sender speaks only for
-- themselves) under a per-sender limit, and passed on in login catch-up as "F" records.
-- Fires HH_PUNISHMENT_ADDED(record).

local addonName, ns = ...

local Punishments = ns:RegisterModule("Punishments", {})

local OWNER = "Punishments"

Punishments.MAX_SKEW = 300
Punishments.DEDUPE = 60        -- one punishment per outlaw per minute from peers (a group's kill)
Punishments.SENDER_LIMIT = 5   -- punishments accepted per sender per window
Punishments.SENDER_WINDOW = 600
Punishments.KINDS = { bully = true, deadbeat = true }

local senderLog = {}

local function Store()
    return ns.db and ns.db.punishments
end

function Punishments.Id(outlaw, t, by)
    return outlaw .. ":" .. t .. ":" .. by
end

function Punishments:All()
    return pairs(Store() or {})
end

-- The punishment of an outlaw at that time (a glass names only these two), or nil
function Punishments:At(outlaw, t)
    for _, record in self:All() do
        if type(record) == "table" and record.outlaw == outlaw and record.t == t then return record end
    end
    return nil
end

-- Newest punishment of one outlaw, by anyone
function Punishments:Latest(outlaw)
    local best
    for _, record in self:All() do
        if type(record) == "table" and record.outlaw == outlaw and (not best or record.t > best.t) then best = record end
    end
    return best
end

function Punishments:Prune(now)
    local store = Store()
    if not store then return end
    local minTime = (now or ns.Utils.ServerTime()) - ns.Reports.MAX_AGE
    for id, record in pairs(store) do
        if type(record) ~= "table" or (tonumber(record.t) or 0) < minTime then store[id] = nil end
    end
end

function Punishments:Add(record, origin, sender)
    local store = Store()
    if not store or not record.outlaw or not record.t or not record.by then return nil end
    record.id = Punishments.Id(record.outlaw, record.t, record.by)
    if store[record.id] then return nil end
    record.origin, record.sender = origin, sender
    store[record.id] = record
    ns:Debug("Punishment added", record.id, "origin", origin)
    ns.Events:Fire("HH_PUNISHMENT_ADDED", record)
    return record
end

function Punishments.Encode(record)
    return ns.Protocol.EncodePunishment({ outlaw = record.outlaw, t = record.t, mapID = record.mapID, kind = record.kind,
        by = record.by, killer = record.killer, killerWho = ns.Justice.KillerWho(record) })
end

-- The outlaw's race, class and level as we know them, for the list and the popup
local function OutlawWho(entry)
    local seen = entry.key and ns.EnemyCache:ByKey(entry.key) or {}
    local race = entry.race or seen.race
    return { class = entry.class or seen.class, race = race, sex = entry.sex or seen.sex,
        level = entry.level or seen.level, faction = seen.faction or ns.Utils.RaceFaction(race) }
end

-- Our own: entry is the Hall of Shame entry (or { id, key } for a Deadbeat), kind
-- "bully" | "deadbeat", killer who landed the blow (nil = us)
function Punishments:OnShameKilled(entry, kind, killer)
    if not (entry and entry.id) or ns.Marks.HuntingDown(entry) then return nil end
    local U = ns.Utils
    local me = U.UnitKey("player")
    if not me then return nil end
    local now = U.ServerTime()
    local latest = self:Latest(entry.id)
    if latest and now - latest.t < ns.Marks.BULLY_COOLDOWN then return nil end
    local record = { outlaw = entry.id, t = now, by = me, kind = kind == "deadbeat" and "deadbeat" or "bully",
        mapID = ns.Zones.ZoneOf(U.PlayerMapID()), killer = killer or me, outlawWho = OutlawWho(entry) }
    ns.Justice.SetKillerWho(record, ns.Justice.Identity(record.killer))
    if not self:Add(record, "local") then return nil end
    local Transport = ns.Transport
    Transport:Queue(ns.Protocol.TYPES.PUNISHMENT, self.Encode(record), Transport.PRIORITY.alert, "F:" .. record.id)
    return record
end

-- Punishments to hand to a peer who missed them, newest first
function Punishments:Since(since)
    local list = {}
    for _, record in self:All() do
        if type(record) == "table" and record.t > since then list[#list + 1] = record end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
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
        if now - at < Punishments.SENDER_WINDOW then recent[#recent + 1] = at end
    end
    senderLog[id] = recent
    if #recent >= Punishments.SENDER_LIMIT then return false end
    recent[#recent + 1] = now
    return true
end

-- A decoded record with our keys and a plausible time, or nil
local function Checked(p)
    local U = ns.Utils
    if not p then return nil end
    if not p.outlaw:find("^guid:") then
        p.outlaw = U.PlayerKey(p.outlaw)
        if not p.outlaw then return nil end
    end
    p.by = U.PlayerKey(p.by)
    if not p.by then return nil end
    local now = U.ServerTime()
    if p.t > now + Punishments.MAX_SKEW or p.t < now - ns.Reports.MAX_AGE then return nil end
    p.killer = p.killer and U.PlayerKey(p.killer) or p.by
    local who = p.killerWho
    p.killerWho = nil
    ns.Justice.SetKillerWho(p, who)
    return p
end

-- A group member's punishment of the same kill, or one we have already
local function Known(p)
    local store = Store()
    if store and store[Punishments.Id(p.outlaw, p.t, p.by)] then return true end
    local latest = Punishments:Latest(p.outlaw)
    return latest ~= nil and math.abs(latest.t - p.t) < Punishments.DEDUPE
end

function Punishments:OnPeer(record, sender)
    local p = Checked(ns.Protocol.DecodePunishment(record))
    if not p or not ns.Utils.SameCharacter(sender, p.by) or Known(p) then return nil end
    if not UnderRateLimit(sender) then return nil end
    return self:Add(p, "peer", sender)
end

-- Passed on by another HeadHunter during login catch-up (HH-023): no rate limit (one
-- pull brings many), the time checks still apply
function Punishments:AddRelayed(record, sender)
    local p = Checked(ns.Protocol.DecodePunishment(record))
    if not p or Known(p) then return nil end
    return self:Add(p, "relay", sender)
end

-- Forget the senders' limits (tests)
function Punishments:Reset()
    senderLog = {}
end

ns.Events:Register("HH_INITIALIZED", function()
    Punishments:Prune()
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.PUNISHMENT, function(record, sender)
        Punishments:OnPeer(record, sender)
    end)
    ns.Events:Register("HH_SHAME_KILLED", function(_, entry, kind, killer)
        Punishments:OnShameKilled(entry, kind, killer)
    end, OWNER)
end, OWNER)
