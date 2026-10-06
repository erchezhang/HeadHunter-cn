-- HH-134: duel spots, places where players duel now (docs/addon/features.md section 10).
--
-- A zone and layer is a duel spot when HeadHunters saw at least MIN_DUELS duels between
-- at least MIN_PLAYERS different players there in the last WINDOW seconds. Only duels
-- where both players are level MIN_LEVEL or higher count (author, 2026-10-05); the level
-- gap does not matter here, unlike the Duels list.
--
-- Our own duels and the duels we watch come from Sync/Duels.lua (HH_DUEL_SEEN, once both
-- levels are known). We keep them under our zone and our layer (Detection/Layer.lua),
-- and at most every PING_INTERVAL seconds a ping (protocol type Z: zone, time, position,
-- layer, the duels as name hashes) goes out on the automatic routes. Pings from the
-- other faction never arrive (Sync/Transport.lua), so the HeadHunters we can ask for an
-- invite are always our faction. Many witnesses see the same duel: the same two players
-- within DEDUPE seconds is one duel.
-- Anti-fake (author, 2026-10-06): a changed addon could send made-up duels. A spot we did
-- not see ourselves needs MIN_WITNESSES different HeadHunters, and one HeadHunter adds at
-- most SENDER_DUELS new duels per WINDOW.
--
-- Players see a duel spot as a mark on the world map (UI/MapMarkers.lua; a click asks a
-- HeadHunter on that layer for an invite), a chat line when one starts in the alert
-- range (alerts.duelSpots; names as links, a click whispers them) and /hh duelspots.
-- A spot also needs a duel in the last QUIET seconds: when duels stop for 3 minutes it is
-- gone (author, 2026-10-06). The map keeps it as it last was until then (MAP_TIME).

local addonName, ns = ...
local L = ns.L

local DuelSpots = ns:RegisterModule("DuelSpots", {})

local OWNER = "DuelSpots"

DuelSpots.WINDOW = 1200
DuelSpots.MIN_DUELS = 10
DuelSpots.MIN_PLAYERS = 5
DuelSpots.MIN_LEVEL = 19
DuelSpots.MIN_WITNESSES = 2
DuelSpots.SENDER_DUELS = 10
DuelSpots.QUIET = 180
DuelSpots.MAP_TIME = DuelSpots.QUIET
DuelSpots.DEDUPE = ns.Duels.DEDUPE
DuelSpots.TICK = 5
DuelSpots.PING_INTERVAL = 60
DuelSpots.ALERT_THROTTLE = 1800
DuelSpots.MAX_SKEW = 300
DuelSpots.MAX_NAMES = 3
DuelSpots.UNKNOWN_LAYER = "?"
DuelSpots.ICON = "Interface\\AddOns\\HeadHunter\\Assets\\Textures\\swords"

-- zone -> layer key -> { duels = { { a, b, t, x, y, sim, mine } }, reporters = { who -> { t, sender, sim, added } } }.
-- added: when this reporter's new duels arrived (the anti-fake limit). The layer key is
-- the layer number, or UNKNOWN_LAYER when the reporter could not tell.
local spots = {}
-- "zone:layer" -> the spot as it last was, for the map (MAP_TIME)
local remembered = {}
-- "zone:layer" -> true while the spot is announced, so the chat line comes once per start
local announced = {}
local unsent = false
local lastPing = 0

local function LayerKey(layer)
    return layer or DuelSpots.UNKNOWN_LAYER
end

local function SpotId(zone, layerKey)
    return zone .. ":" .. tostring(layerKey)
end

local function Bucket(zone, layerKey)
    spots[zone] = spots[zone] or {}
    spots[zone][layerKey] = spots[zone][layerKey] or { duels = {}, reporters = {} }
    return spots[zone][layerKey]
end

local function Me()
    local U = ns.Utils
    return U.CompactName(U.UnitKey("player"))
end

-------------------------------------------------
-- Inputs
-------------------------------------------------

-- The duel we already have for the same two players within DEDUPE seconds, or nil
local function Known(bucket, duel)
    for _, have in ipairs(bucket.duels) do
        if have.a == duel.a and have.b == duel.b and math.abs(have.t - duel.t) < DuelSpots.DEDUPE then return have end
    end
    return nil
end

-- The same duel on a known layer of the zone, or nil
local function KnownOnLayer(zone, duel)
    for layerKey, bucket in pairs(spots[zone] or {}) do
        local have = layerKey ~= DuelSpots.UNKNOWN_LAYER and Known(bucket, duel)
        if have then return have end
    end
    return nil
end

-- Takes the same duel out of the zone's unknown layer; returns it, or nil
local function TakeUnknown(zone, duel)
    local unknown = spots[zone] and spots[zone][DuelSpots.UNKNOWN_LAYER]
    local have = unknown and Known(unknown, duel)
    if not have then return nil end
    for i, other in ipairs(unknown.duels) do
        if other == have then
            table.remove(unknown.duels, i)
            break
        end
    end
    return have
end

-- Adds duels seen on mapID and layer by `who` (compact name). sender: the name to
-- whisper, only for other HeadHunters. duels: { a, b, t } with a and b as
-- Protocol.NameHash. sim: test data from /hh sim duels, never sent and never whispered.
-- Returns the zone and the layer key, or nil.
-- Anti-fake: another HeadHunter adds at most SENDER_DUELS new duels to a zone and layer
-- per WINDOW, counted by when they arrive (an old duel time does not help). Duels they
-- report that we already know only make them a witness.
-- A known layer wins over an unknown one (author, 2026-10-06: one duel made two marks,
-- "Layer unknown" and "Layer 32"): a duel without a layer that a known layer already
-- has is not counted again, and a duel with a layer takes over its copy without one.
function DuelSpots:Add(mapID, layer, who, t, x, y, duels, sender, sim)
    local zone = ns.Zones.ZoneOf(mapID)
    if not zone or not who then return nil end
    local layerKey = LayerKey(layer)
    local bucket = Bucket(zone, layerKey)
    local reporter = bucket.reporters[who] or { t = t, added = {} }
    bucket.reporters[who] = reporter
    if reporter.t < t then reporter.t = t end
    reporter.sender, reporter.sim = sender, sim
    local now = ns.Utils.ServerTime()
    local recent = {}
    for _, at in ipairs(reporter.added) do
        if now - at <= self.WINDOW then recent[#recent + 1] = at end
    end
    reporter.added = recent
    local tookUnknown = false
    for _, duel in ipairs(duels or {}) do
        local a, b = duel.a, duel.b
        if a > b then a, b = b, a end
        local mine = not sender and not sim or nil
        local entry = { a = a, b = b, t = duel.t, x = x, y = y, sim = sim, mine = mine }
        local have = Known(bucket, entry)
        if not have and layerKey == self.UNKNOWN_LAYER then have = KnownOnLayer(zone, entry) end
        local capped = sender and not sim and #reporter.added >= self.SENDER_DUELS
        local taken = not have and layerKey ~= self.UNKNOWN_LAYER and TakeUnknown(zone, entry)
        if have then
            have.mine = have.mine or mine
        elseif taken then
            entry.mine = entry.mine or taken.mine
            bucket.duels[#bucket.duels + 1] = entry
            tookUnknown = true
        elseif not capped then
            bucket.duels[#bucket.duels + 1] = entry
            if sender then reporter.added[#reporter.added + 1] = now end
        end
    end
    if tookUnknown then
        if #spots[zone][self.UNKNOWN_LAYER].duels == 0 then remembered[SpotId(zone, self.UNKNOWN_LAYER)] = nil end
        self:Evaluate(zone, self.UNKNOWN_LAYER)
    end
    return zone, layerKey
end

-- A duel we saw ourselves (HH_DUEL_SEEN): counted when both players are MIN_LEVEL+
function DuelSpots:OnDuelSeen(duel)
    if not ns.Guards:IsActive() or type(duel) ~= "table" then return nil end
    local winnerLevel, loserLevel = tonumber(duel.winnerLevel), tonumber(duel.loserLevel)
    if not (winnerLevel and loserLevel and winnerLevel >= self.MIN_LEVEL and loserLevel >= self.MIN_LEVEL) then
        return nil
    end
    local U, P = ns.Utils, ns.Protocol
    local mapID = U.PlayerMapID()
    local _, x, y = ns.Zones.ToZone(mapID, U.PlayerPosition(mapID))
    local t = tonumber(duel.t) or U.ServerTime()
    local zone, layerKey = self:Add(mapID, ns.Layer:Current(), Me(), t, x, y,
        { { a = P.NameHash(duel.winner), b = P.NameHash(duel.loser), t = t } })
    if not zone then return nil end
    unsent = true
    self:Evaluate(zone, layerKey)
    self:Tick()
    return zone, layerKey
end

-- When we entered our zone: our layer can only be learned for duels seen after that
local zoneSince = 0

-- Our layer became known (HH_LAYER_CHANGED): the duels we saw in this zone since we
-- came here, while our layer was still unknown, were on this layer, so they move to it.
-- Duels heard from others keep their own layer. Returns how many moved.
function DuelSpots:AdoptLayer(layer, zone)
    local unknown = layer and zone and spots[zone] and spots[zone][self.UNKNOWN_LAYER]
    if not unknown then return 0 end
    local me, moved = Me(), {}
    local kept = {}
    for _, duel in ipairs(unknown.duels) do
        if duel.mine and duel.t >= zoneSince then moved[#moved + 1] = duel else kept[#kept + 1] = duel end
    end
    if #moved == 0 then return 0 end
    unknown.duels = kept
    local mine = unknown.reporters[me]
    local stillMine = false
    for _, duel in ipairs(kept) do
        if duel.mine then stillMine = true end
    end
    if mine and not stillMine then unknown.reporters[me] = nil end
    local bucket = Bucket(zone, layer)
    for _, duel in ipairs(moved) do
        local have = Known(bucket, duel)
        if have then have.mine = true else bucket.duels[#bucket.duels + 1] = duel end
    end
    local reporter = bucket.reporters[me] or { t = 0, added = {} }
    bucket.reporters[me] = reporter
    if mine and mine.t > reporter.t then reporter.t = mine.t end
    unsent = true
    if #unknown.duels == 0 then remembered[SpotId(zone, self.UNKNOWN_LAYER)] = nil end
    self:Evaluate(zone, self.UNKNOWN_LAYER)
    self:Evaluate(zone, layer)
    return #moved
end

-------------------------------------------------
-- State
-------------------------------------------------

-- Duels and different players on a zone and layer in the WINDOW (older duels are
-- forgotten, reporters after WINDOW)
function DuelSpots:State(zone, layerKey, now)
    local bucket = spots[zone] and spots[zone][layerKey]
    if not bucket then return 0, 0 end
    now = now or ns.Utils.ServerTime()
    local kept, players, count = {}, {}, 0
    for _, duel in ipairs(bucket.duels) do
        if duel.t >= now - self.WINDOW then
            kept[#kept + 1] = duel
            players[duel.a], players[duel.b] = true, true
        end
    end
    bucket.duels = kept
    for who, reporter in pairs(bucket.reporters) do
        if reporter.t < now - self.WINDOW then bucket.reporters[who] = nil end
    end
    for _ in pairs(players) do count = count + 1 end
    return #kept, count
end

-- Anti-fake: a spot we did not see ourselves needs MIN_WITNESSES different HeadHunters
-- who reported duels there in the WINDOW, so one changed addon alone cannot make one.
-- Our own duels and test data (/hh sim duels) are trusted.
function DuelSpots:Witnessed(zone, layerKey, now)
    local bucket = spots[zone] and spots[zone][layerKey]
    if not bucket then return false end
    now = now or ns.Utils.ServerTime()
    local me, count = Me(), 0
    for who, reporter in pairs(bucket.reporters) do
        if now - reporter.t <= self.WINDOW then
            if who == me or reporter.sim then return true end
            count = count + 1
        end
    end
    return count >= self.MIN_WITNESSES
end

-- Duels without a layer are kept (they move to a layer once one is known) but never make
-- a spot: a mark, a menu row or a chat line on "Layer unknown" cannot be joined
-- (author, 2026-10-06).
function DuelSpots:IsSpot(zone, layerKey, now)
    now = now or ns.Utils.ServerTime()
    local duels, players = self:State(zone, layerKey, now)
    if layerKey == self.UNKNOWN_LAYER then return false, duels, players end
    local ok = duels >= self.MIN_DUELS and players >= self.MIN_PLAYERS and self:Witnessed(zone, layerKey, now)
        and self:LastDuel(zone, layerKey) >= now - self.QUIET
    return ok, duels, players
end

-- Time of the newest duel on a zone and layer, 0 when none
function DuelSpots:LastDuel(zone, layerKey)
    local newest = 0
    for _, duel in ipairs(spots[zone] and spots[zone][layerKey] and spots[zone][layerKey].duels or {}) do
        if duel.t > newest then newest = duel.t end
    end
    return newest
end

-- The newest duel's place and time on a zone and layer
local function Newest(bucket)
    local best
    for _, duel in ipairs(bucket.duels) do
        if not best or duel.t > best.t then best = duel end
    end
    return best
end

local function Snapshot(zone, layerKey, duels, players)
    local newest = Newest(spots[zone][layerKey])
    return { zone = zone, layerKey = layerKey, layer = layerKey ~= DuelSpots.UNKNOWN_LAYER and layerKey or nil,
        duels = duels, players = players, x = newest and newest.x, y = newest and newest.y, t = newest and newest.t or 0 }
end

-- Duel spots for the map and /hh duelspots, busiest first: the ones that pass the rule
-- now, and the ones that did within MAP_TIME as they last were (remembered = true).
-- Each: { zone, layerKey, layer, duels, players, x, y, t = newest duel }.
-- Duel spots grouped by zone, for one map mark per zone (author, 2026-10-06), busiest
-- zone first: { zone, spots (busiest layer first), duels (all layers), x, y (the busiest
-- layer's), t (newest duel) }
function DuelSpots:ByZone(now)
    local groups, list = {}, {}
    for _, spot in ipairs(self:Active(now)) do
        local group = groups[spot.zone]
        if not group then
            group = { zone = spot.zone, spots = {}, duels = 0, x = spot.x, y = spot.y, t = 0 }
            groups[spot.zone] = group
            list[#list + 1] = group
        end
        group.spots[#group.spots + 1] = spot
        group.duels = group.duels + spot.duels
        if spot.t > group.t then group.t = spot.t end
    end
    table.sort(list, function(p, q)
        if p.duels ~= q.duels then return p.duels > q.duels end
        return p.zone < q.zone
    end)
    return list
end

-- The layer a click on a zone's mark asks an invite for: the busiest one we are not on
-- with a HeadHunter to ask, or nil
function DuelSpots:InviteSpot(group)
    for _, spot in ipairs(group.spots) do
        if not self:OnOurLayer(spot.zone, spot.layerKey) and self:Inviters(spot.zone, spot.layerKey)[1] then return spot end
    end
    return nil
end

-- The layers of a zone's mark to choose from (right-click): every one we are not on,
-- busiest first
function DuelSpots:MenuSpots(group)
    local list = {}
    for _, spot in ipairs(group.spots) do
        if not self:OnOurLayer(spot.zone, spot.layerKey) then list[#list + 1] = spot end
    end
    return list
end

function DuelSpots:Active(now)
    now = now or ns.Utils.ServerTime()
    local list, seen = {}, {}
    for zone, layers in pairs(spots) do
        for layerKey in pairs(layers) do
            local ok, duels, players = self:IsSpot(zone, layerKey, now)
            if ok then
                local spot = Snapshot(zone, layerKey, duels, players)
                local id = SpotId(zone, layerKey)
                remembered[id] = spot
                seen[id] = true
                list[#list + 1] = spot
            end
        end
    end
    for id, spot in pairs(remembered) do
        if not seen[id] then
            if now - spot.t > self.MAP_TIME then
                remembered[id] = nil
            else
                local copy = {}
                for k, v in pairs(spot) do copy[k] = v end
                copy.remembered = true
                list[#list + 1] = copy
            end
        end
    end
    table.sort(list, function(p, q)
        if p.duels ~= q.duels then return p.duels > q.duels end
        if p.zone ~= q.zone then return p.zone < q.zone end
        return tostring(p.layerKey) < tostring(q.layerKey)
    end)
    return list
end

-- Other HeadHunters who saw duels on that zone and layer, newest first: the names to
-- whisper (our faction only, as Transport drops the other faction's pings)
-- Also returns the reporters themselves, in the same order (sim tells test data)
function DuelSpots:Inviters(zone, layerKey, now)
    local bucket = spots[zone] and spots[zone][layerKey]
    if not bucket then return {}, {} end
    now = now or ns.Utils.ServerTime()
    local me, list = Me(), {}
    for who, reporter in pairs(bucket.reporters) do
        if who ~= me and reporter.sender and reporter.t >= now - self.WINDOW then list[#list + 1] = reporter end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    local names = {}
    for i, reporter in ipairs(list) do names[i] = reporter.sender end
    return names, list
end

-- True when we are in that zone on that layer now
function DuelSpots:OnOurLayer(zone, layerKey)
    if layerKey == self.UNKNOWN_LAYER then return false end
    return ns.Layer:Compare(layerKey, zone) == "same"
end

-------------------------------------------------
-- Texts
-------------------------------------------------

function DuelSpots.Icon()
    return "|T" .. DuelSpots.ICON .. ":14:14|t"
end

-- "12 duels, 6 players in 10 min"
function DuelSpots.Describe(spot)
    return string.format(L.DUEL_SPOT_DESCRIBE, spot.duels, spot.players, math.floor(DuelSpots.WINDOW / 60))
end

-- "Layer 3", "Layer 3 (your layer)" or "Layer unknown"
function DuelSpots:LayerText(spot)
    if not spot.layer then return L.DUEL_SPOT_LAYER_UNKNOWN end
    if self:OnOurLayer(spot.zone, spot.layerKey) then return string.format(L.DUEL_SPOT_LAYER_YOURS, spot.layer) end
    return string.format(L.DUEL_SPOT_LAYER, spot.layer)
end

-- Up to MAX_NAMES HeadHunters there, as chat links when `links`, else plain names
function DuelSpots:InviterNames(zone, layerKey, links)
    local U, parts = ns.Utils, {}
    for i, sender in ipairs(self:Inviters(zone, layerKey)) do
        if i > self.MAX_NAMES then break end
        local key = U.PlayerKey(sender)
        parts[#parts + 1] = (links and U.PlayerLink(key)) or U.DisplayName(key) or sender
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- The chat line: "Duels in Orgrimmar (Layer 3): 12 duels, 6 players in 10 min. Ask for an
-- invite: [Brakka]"; the invite part only when we are not on that layer
function DuelSpots:Line(spot)
    local zoneName = ns.Utils.MapName(spot.zone) or L.UNKNOWN_ZONE
    local line = string.format(L.DUEL_SPOT_LINE, DuelSpots.Icon(), zoneName, self:LayerText(spot), DuelSpots.Describe(spot))
    local names = not self:OnOurLayer(spot.zone, spot.layerKey) and self:InviterNames(spot.zone, spot.layerKey, true)
    if names then line = line .. string.format(L.DUEL_SPOT_ASK, names) end
    return line
end

-------------------------------------------------
-- Invite
-------------------------------------------------

-- Asks the newest HeadHunter on that zone and layer for a group invite, by whisper.
-- Runs inside a click (the map mark), which allows the whisper. A made-up HeadHunter
-- from /hh sim duels gets no whisper: chat shows what would be sent.
function DuelSpots:AskInvite(zone, layerKey)
    local U = ns.Utils
    local zoneName = U.MapName(zone) or L.UNKNOWN_ZONE
    if self:OnOurLayer(zone, layerKey) then
        ns:Print(L.DUEL_SPOT_SAME_LAYER)
        return "same"
    end
    local names, reporters = self:Inviters(zone, layerKey)
    local target = names[1]
    if not target then
        ns:Print(string.format(L.DUEL_SPOT_NOBODY, zoneName))
        return nil
    end
    local text = string.format(L.DUEL_SPOT_WHISPER, zoneName)
    if reporters[1].sim then
        ns:Print(string.format(L.SIM_DUELS_WHISPER, target, text))
        return "sim", target
    end
    local ok = pcall(SendChatMessage, text, "WHISPER", nil, target)
    if not ok then return nil end
    ns:Print(string.format(L.POSSE_WHISPERED, U.DisplayName(U.PlayerKey(target)) or target))
    return "whispered", target
end

-------------------------------------------------
-- Alerts
-------------------------------------------------

local function AlertsOn()
    return ns.db ~= nil and ns.db.settings.alerts.duelSpots ~= false
end

-- We saw duels there ourselves lately: we are there, nothing to tell us
local function WeAreThere(zone, layerKey, now)
    local mine = spots[zone][layerKey].reporters[Me()]
    return mine ~= nil and now - mine.t <= DuelSpots.WINDOW
end

-- Test spots (/hh sim duels) are not held back by the alert throttle, so each run shows
-- the chat line again.
function DuelSpots:Evaluate(zone, layerKey, sim)
    ns.Events:Fire("HH_DUEL_SPOTS_CHANGED", zone)
    local now = ns.Utils.ServerTime()
    local ok, duels, players = self:IsSpot(zone, layerKey, now)
    local id = SpotId(zone, layerKey)
    if not ok then
        announced[id] = nil
        return false
    end
    local spot = Snapshot(zone, layerKey, duels, players)
    remembered[id] = spot
    if announced[id] then return false end
    announced[id] = true
    if not AlertsOn() or WeAreThere(zone, layerKey, now) or self:OnOurLayer(zone, layerKey) then return false end
    if not ns.Zones.InRange(zone) then return false end
    ns.Alerts:Show({ key = "duels:" .. id, throttle = sim and 0 or self.ALERT_THROTTLE, chat = self:Line(spot), combat = true })
    return true
end

-------------------------------------------------
-- Test data: /hh sim duels [clear]
-------------------------------------------------

-- Made-up duelists, and the other layers with their made-up HeadHunter and duel count:
-- two of them, so the right-click menu has a choice. Never real players.
DuelSpots.SIM_DUELISTS = { "Testone", "Testtwo", "Testthree", "Testfour", "Testfive", "Testsix", "Testseven" }
DuelSpots.SIM_DUELS = 12
DuelSpots.SIM_OTHERS = {
    { step = 1, headhunter = "Testeight", duels = 14 },
    { step = 2, headhunter = "Testnine", duels = 11 },
}

-- A made-up name as this client writes names: "Testsix Sim" on WoW Forever (given and
-- family name), "Testsix-<our realm>" on Classic Era
local function SimName(given)
    if ns.Features.RealmlessNames then return given .. " Sim" end
    return given .. "-" .. tostring(ns.Utils.PlayerRealm())
end

local function SimDuels(now, count)
    local P, list, names = ns.Protocol, {}, DuelSpots.SIM_DUELISTS
    for i = 1, count or DuelSpots.SIM_DUELS do
        list[i] = { a = P.NameHash(SimName(names[(i - 1) % #names + 1])), b = P.NameHash(SimName(names[i % #names + 1])),
            t = now - (i - 1) * 45 }
    end
    return list
end

-- Test spots where we stand, only on our screen: one on our layer, and one on each of
-- the next SIM_OTHERS layers with a made-up HeadHunter to ask for an invite (the click
-- only prints the whisper). Returns the zone and the other layers; or nil and "zone"
-- when the zone or our position cannot be read, "layer" when our layer is not known yet
-- (a spot on "Layer unknown" would not show what players see). Test spots from an
-- earlier run are removed first, so only the newest set shows.
function DuelSpots:Simulate()
    local U = ns.Utils
    local mapID = U.PlayerMapID()
    local zone, x, y = ns.Zones.ToZone(mapID, U.PlayerPosition(mapID))
    if not zone or not x then return nil, "zone" end
    local now = U.ServerTime()
    local layer = ns.Layer:Current()
    if not layer then return nil, "layer" end
    self:ClearSim()
    local here = self:Add(zone, layer, "sim:here", now, x, y, SimDuels(now), nil, true)
    if here then self:Evaluate(zone, LayerKey(layer), true) end
    local others = {}
    for _, other in ipairs(self.SIM_OTHERS) do
        local otherLayer = layer + other.step
        local headhunter = SimName(other.headhunter)
        self:Add(zone, otherLayer, U.CompactName(headhunter), now, x, y, SimDuels(now, other.duels), headhunter, true)
        announced[SpotId(zone, otherLayer)] = nil
        self:Evaluate(zone, otherLayer, true)
        others[#others + 1] = otherLayer
    end
    return zone, others
end

-- Removes every test duel and test HeadHunter; returns how many test duels went
function DuelSpots:ClearSim()
    local removed = 0
    for zone, layers in pairs(spots) do
        for layerKey, bucket in pairs(layers) do
            local kept = {}
            for _, duel in ipairs(bucket.duels) do
                if duel.sim then removed = removed + 1 else kept[#kept + 1] = duel end
            end
            bucket.duels = kept
            for who, reporter in pairs(bucket.reporters) do
                if reporter.sim then bucket.reporters[who] = nil end
            end
            local id = SpotId(zone, layerKey)
            if not self:IsSpot(zone, layerKey) then
                remembered[id] = nil
                announced[id] = nil
            end
        end
    end
    ns.Events:Fire("HH_DUEL_SPOTS_CHANGED")
    return removed
end

-------------------------------------------------
-- Pings
-------------------------------------------------

-- Sends the duels we saw ourselves on our zone and layer, newest first, when we saw new
-- ones and the last ping is PING_INTERVAL seconds old. Test duels from /hh sim duels
-- never go out. Players who /reload or log in lose what they heard, so a HeadHunter who
-- saw duels here in the WINDOW and is still on that zone and layer sends them again
-- every REFRESH seconds, even with nothing new (author, 2026-10-06). Duels we only heard
-- from others are never sent on: passed on, a faker's duels would look like a second
-- witness.
DuelSpots.REFRESH = 180

function DuelSpots:Tick()
    if not ns.Guards:IsActive() then return false end
    local U = ns.Utils
    local now = U.ServerTime()
    local wait = unsent and self.PING_INTERVAL or self.REFRESH
    if now - lastPing < wait then return false end
    local mapID = U.PlayerMapID()
    local zone = ns.Zones.ZoneOf(mapID)
    local layer = ns.Layer:Current()
    local bucket = zone and spots[zone] and spots[zone][LayerKey(layer)]
    unsent = false
    if not bucket or not WeAreThere(zone, LayerKey(layer), now) then return false end
    self:State(zone, LayerKey(layer), now)
    local duels = {}
    for _, duel in ipairs(bucket.duels) do
        if duel.mine then duels[#duels + 1] = duel end
    end
    if #duels == 0 then return false end
    table.sort(duels, function(a, b) return a.t > b.t end)
    lastPing = now
    local _, x, y = ns.Zones.ToZone(mapID, U.PlayerPosition(mapID))
    local Protocol, Transport = ns.Protocol, ns.Transport
    Transport:Queue(Protocol.TYPES.DUEL_SPOT, Protocol.EncodeDuelSpot(zone, now, x, y, layer, duels),
        Transport.PRIORITY.hotspot, "Z:" .. zone)
    return true
end

function DuelSpots:OnPeerPing(record, sender, faction)
    local U = ns.Utils
    if faction and faction ~= U.UnitFaction("player") then return nil end
    local mapID, t, x, y, layer, duels = ns.Protocol.DecodeDuelSpot(record)
    if not mapID then return nil end
    local now = U.ServerTime()
    if t > now + self.MAX_SKEW or now - t > self.WINDOW then return nil end
    local zone, layerKey = self:Add(mapID, layer, U.CompactName(sender), t, x, y, duels, sender)
    if zone then self:Evaluate(zone, layerKey) end
    return zone, layerKey
end

local function Ticker()
    C_Timer.After(DuelSpots.TICK, function()
        local ok, err = pcall(DuelSpots.Tick, DuelSpots)
        if not ok then ns:Error(err) end
        Ticker()
    end)
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.DUEL_SPOT, function(record, sender, faction)
        DuelSpots:OnPeerPing(record, sender, faction)
    end)
    ns.Events:Register("HH_DUEL_SEEN", function(_, duel) DuelSpots:OnDuelSeen(duel) end, OWNER)
    ns.Events:Register("HH_LAYER_CHANGED", function(_, layer, zone) DuelSpots:AdoptLayer(layer, zone) end, OWNER)
    local function Arrived() zoneSince = ns.Utils.ServerTime() end
    ns.Events:Register("PLAYER_ENTERING_WORLD", Arrived, OWNER)
    ns.Events:Register("ZONE_CHANGED_NEW_AREA", Arrived, OWNER)
    Ticker()
end, OWNER)

ns.SlashCommands:Register("duelspots", function()
    local list = DuelSpots:Active()
    if #list == 0 then
        ns:Print(L.DUEL_SPOT_NONE)
        return
    end
    for _, spot in ipairs(list) do ns:Print(DuelSpots:Line(spot)) end
end, L.HELP_DUELSPOTS)
