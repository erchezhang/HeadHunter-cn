-- HH-045: PvP hotspots, "fire" levels per zone (docs/addon/features.md section 5).
--
-- Over the last WINDOW seconds, per zone:
--   A = players of our side in PvP combat there: every HeadHunter's pings carry the
--       players of our faction they see in combat, with or without HeadHunter, and
--       themselves (author, 2026-10-04: we were 3, the map said 1)
--   E = distinct enemy players seen in combat there (merged across all pings)
--   D = deaths reported there
--   heat = A + E + 2*D
-- The map and the alert text show A and E of the last NOW_WINDOW seconds, the fight as
-- it is now (author, 2026-10-04: 2 enemies said 5); the levels use the whole WINDOW.
-- Only HeadHunters (they send pings) are named with whisper links.
-- Levels: >= 4 Skirmish (chat line), >= 10 Battle (popup + sound),
--         >= 20 Warzone (popup + sound + raid-warning text).
--
-- We count as "in PvP combat" while in combat with enemy players fighting our side
-- around us (nameplates, target, focus, mouseover, group) in the last FIGHT_RECENT
-- seconds. An enemy fights our side when they target us or a player of our faction, or
-- when we or a group member in combat target them (author, 2026-10-09: being in combat
-- near us is not enough, both may be fighting NPCs). Then, at most every PING_INTERVAL seconds, a ping
-- (protocol type P: map, time, position, short enemy ids) goes out on the
-- automatic routes.
-- We are in the fight ourselves only when an enemy is engaged with us or our group: it
-- targets us or a group member close to us, or we or such a member target it (1.0.5:
-- fighting a turtle while enemies fought another Horde player nearby made us a fighter,
-- pinged as one and kept from the alert; seen in game 2026-11-06). Enemies fighting
-- others of our faction are still seen for the map and the pings of a fight we are in.
-- Alerts: when a zone climbs a level, inside the alert range, never for a fight we
-- are in ourselves, at most once per zone and level per LEVEL_THROTTLE. Kept quiet for
-- our own fight, a zone alerts again once there is new activity there after it (1.0.5:
-- it used to stay "announced" while the zone kept burning, so a later fight of others
-- there was never said). A ping whose enemies all fought us is still our fight, and so
-- is such an enemy seen again (1.0.9: our partner kept chasing the Priest we fought,
-- and their pings alerted us about our own fight a minute later; seen in game 2026-11-11).
-- [Help] sets a waypoint to the newest fight; [Ignore] mutes the zone for IGNORE_TIME.
-- HH-136: fires HH_PVP_SEEN(zone, fighters, layer, t) with the players seen fighting,
-- from our own scan and from other HeadHunters' pings, for Alerts/Wars.lua:
--   fighters = { { key, side = "ally" | "enemy", class?, race?, level?, guild?, faction? } }
-- HH-163: a zone holds several PvP areas (author, 2026-11-15: Stranglethorn Vale has
-- fights at the Arena and at Booty Bay at once). Activity more than AREA_RADIUS of the
-- zone's width from an area starts another one; activity with no position joins the
-- newest area. Each area has its own heat, level, alert, [Help] and [Ignore]; areas that
-- come together merge without an alert. The map and the alerts take a zone's hottest
-- `hotspotsPerZone` areas (1 to MAX_AREAS). Heat, Level and Oldest stay per zone (wars).

local addonName, ns = ...
local L = ns.L

local Hotspots = ns:RegisterModule("Hotspots", {})

local OWNER = "Hotspots"

Hotspots.WINDOW = 300
Hotspots.NOW_WINDOW = 120
-- HH-164: an area remembers it is the same fight (its players, place, alert level and
-- [Ignore]) this long after its newest activity, like a war (Wars.END_AFTER): a regroup or
-- a corpse run is no news. Never shorter than MAP_MINUTES_MAX, or a mark would go early.
Hotspots.AREA_MEMORY = 600
-- HH-164: a PvP area's mark stays on the map this many minutes after the newest activity
-- in it, the setting hotspotMapMinutes (author, 2026-11-15: 10 was long; it was 20 until
-- 2026-10-08)
Hotspots.MAP_MINUTES_MIN = 3
Hotspots.MAP_MINUTES_DEFAULT = 5
Hotspots.MAP_MINUTES_MAX = 10
Hotspots.TICK = 5
Hotspots.FIGHT_RECENT = 15
Hotspots.PING_INTERVAL = 30
Hotspots.LEVEL_THROTTLE = 300
Hotspots.IGNORE_TIME = 600
Hotspots.MAX_SKEW = 300
Hotspots.LEVELS = { { heat = 20, id = 3 }, { heat = 10, id = 2 }, { heat = 4, id = 1 } }
-- From this level (Battle) a click on the map's PvP mark is Help (author, 2026-10-08):
-- never for a Skirmish
Hotspots.INVITE_LEVEL = 2
-- HH-163: activity further than this from an area, as a share of the zone's width,
-- starts another area in the same zone (author, 2026-11-15)
Hotspots.AREA_RADIUS = 0.15
-- HH-163: the most areas per zone the map shows and alerts (the setting goes 1 to this)
Hotspots.MAX_AREAS = 3

-- zone mapID -> { fighters = {id -> {t, x, y}}, allies = {id -> {t, x, y}},
-- enemies = {id -> {t, x, y}}, deaths = {id -> {t, x, y}}, names = {name -> {t, x, y}} }
local zones = {}
-- zone -> { short id -> t }: the enemies of our own fight there (1.0.9), kept for WINDOW
local ownEnemies = {}
-- HH-163: zone -> { area id -> what an area keeps between looks: x, y, t (newest activity),
-- heat, announced (highest level said in this burst), quietSince (our own fight's latest
-- moment), ignoredUntil (GetTime()), spot (its last hot state, for the map: MapTime) }
local areaState = {}
local areaSerial = 0
local lastPing = 0

-- The zone's activity lists, for a change: each call counts as one (version), so the areas
-- are worked out again
local function Zone(mapID)
    local zone = ns.Zones.ZoneOf(mapID)
    if not zone then return nil end
    zones[zone] = zones[zone] or { fighters = {}, allies = {}, enemies = {}, deaths = {}, names = {}, version = 0 }
    zones[zone].version = zones[zone].version + 1
    return zone, zones[zone]
end

-- Short, stable enemy id for pings: the last 8 characters of the GUID
function Hotspots.ShortId(guid)
    guid = tostring(guid or ""):gsub("[^%w]", "")
    return guid:sub(-8)
end

-------------------------------------------------
-- Inputs
-------------------------------------------------

-- The time of a list entry: a table with t, or a plain time
local function Stamp(value)
    if type(value) == "table" then return value.t end
    return value
end

-- Keeps the newest sighting of `id` in `list`, with the place of the ping that saw it
local function Seen(list, id, t, x, y)
    local known = list[id]
    if not known or (Stamp(known) or 0) < t then list[id] = { t = t, x = x, y = y } end
end

-- who: compact name (the key); extra: { sender = name to whisper, layer, enemies =
-- { { name, class, level } } } from 0.1.8 pings (HH-111); allies = short ids of our
-- side in combat, the fighter among them (0.4.0+; nil from older pings: the fighter
-- counts alone). HH-163: enemies, allies and names keep the ping's place, for the areas.
function Hotspots:AddFighter(mapID, who, t, x, y, enemyIds, extra)
    local zone, data = Zone(mapID)
    if not zone or not who then return nil end
    extra = extra or {}
    data.fighters[who] = { t = t, x = x, y = y, sender = extra.sender, layer = extra.layer,
        allies = extra.allies ~= nil or nil, enemies = enemyIds }
    for _, id in ipairs(enemyIds or {}) do Seen(data.enemies, id, t, x, y) end
    for _, id in ipairs(extra.allies or {}) do Seen(data.allies, id, t, x, y) end
    for _, enemy in ipairs(extra.enemies or {}) do
        if enemy.name then
            data.names[enemy.name] = { t = t, name = enemy.name, class = enemy.class, level = enemy.level, x = x, y = y }
        end
    end
    return zone
end

-- "Grimtusk (34 Rogue), Dusk (?? Mage)": up to MAX_PING_NAMES enemies seen fighting
-- in one area (HH-163) within the window, newest first; nil when no names are known
function Hotspots:EnemyNames(area, now)
    local since = (now or ns.Utils.ServerTime()) - self.WINDOW
    local list = {}
    for _, enemy in pairs(area.names) do
        if enemy.t >= since then list[#list + 1] = enemy end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.t > b.t end)
    local parts = {}
    for i = 1, math.min(#list, ns.Protocol.MAX_PING_NAMES) do
        local e = list[i]
        local class = ns.Utils.ClassName(e.class)
        local about = {}
        if e.level then about[#about + 1] = e.level == -1 and "??" or tostring(e.level) end
        if class then about[#about + 1] = class end
        parts[i] = #about > 0 and string.format("%s (%s)", e.name, table.concat(about, " ")) or e.name
    end
    return table.concat(parts, ", ")
end

-- HeadHunters of our faction fighting in one area (HH-163), newest first (not us):
-- "Brakka, Zulgar". links: the names as chat links, to whisper them with a click (our
-- faction only)
function Hotspots:FighterNames(area, now, links)
    local U = ns.Utils
    local since = (now or U.ServerTime()) - self.WINDOW
    local me = U.CompactName(U.UnitKey("player"))
    local list = {}
    for who, fighter in pairs(area.fighters) do
        if who ~= me and fighter.sender and fighter.t >= since then list[#list + 1] = fighter end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.t > b.t end)
    local parts = {}
    for i = 1, math.min(#list, ns.Protocol.MAX_PING_NAMES) do
        local key = U.PlayerKey(list[i].sender)
        parts[i] = (links and U.PlayerLink(key)) or U.DisplayName(key) or list[i].sender
    end
    return table.concat(parts, ", ")
end

function Hotspots:AddDeath(report)
    local zone, data = Zone(report.mapID)
    if not zone or not report.id then return nil end
    -- Reports keep the map the victim stood on (maybe a cave); hotspots use the zone
    local _, x, y = ns.Zones.ToZone(report.mapID, report.x, report.y)
    local U = ns.Utils
    local t = report.t or U.ServerTime()
    data.deaths[report.id] = { t = t, killer = ns.RulesEngine.EnemyId(report.killer), x = x, y = y }
    -- Our own death: we were in that fight (a quick gank can end before our combat
    -- tick sees it), so we count as a HeadHunter there and are not alerted about it
    if report.victim and U.SameCharacter(report.victim.key, U.UnitKey("player")) then
        local me = U.CompactName(U.UnitKey("player"))
        local known = me and data.fighters[me]
        if me and (not known or known.t < t) then data.fighters[me] = { t = t, x = x, y = y } end
    end
    return zone
end

-------------------------------------------------
-- Heat
-------------------------------------------------

local function CountRecent(map, since)
    local n = 0
    for key, value in pairs(map) do
        local t = type(value) == "table" and value.t or value
        if t >= since then n = n + 1 else map[key] = nil end
    end
    return n
end

-- Our side: the allies the pings named, and the fighters whose pings named none
local function OurSide(data, since)
    local n = 0
    for _, ally in pairs(data.allies) do
        if (Stamp(ally) or 0) >= since then n = n + 1 end
    end
    for _, fighter in pairs(data.fighters) do
        if fighter.t >= since and not fighter.allies then n = n + 1 end
    end
    return n
end

-- heat, level (0-3), A, E, D for a zone's activity or one of its areas
local function HeatOf(data, now)
    if not data then return 0, 0, 0, 0, 0 end
    local since = now - Hotspots.WINDOW
    CountRecent(data.fighters, since)
    CountRecent(data.allies, since)
    local a = OurSide(data, since)
    local e = CountRecent(data.enemies, since)
    local d = CountRecent(data.deaths, since)
    local heat = a + e + 2 * d
    for _, level in ipairs(Hotspots.LEVELS) do
        if heat >= level.heat then return heat, level.id, a, e, d end
    end
    return heat, 0, a, e, d
end

-- heat, level (0-3), A, E, D for a whole zone (wars and `/hh` tools; the map and the
-- alerts use its areas, HH-163)
function Hotspots:Heat(zone, now)
    return HeatOf(zones[zone], now or ns.Utils.ServerTime())
end

-- A and E of a zone's activity or one of its areas in the last NOW_WINDOW seconds
local function NowOf(data, now)
    if not data then return 0, 0 end
    local since = now - Hotspots.NOW_WINDOW
    local e = 0
    for _, enemy in pairs(data.enemies) do
        if (Stamp(enemy) or 0) >= since then e = e + 1 end
    end
    return OurSide(data, since), e
end

-- A and E as the fight is now (the last NOW_WINDOW seconds), for the map and alerts
function Hotspots:Now(zone, now)
    return NowOf(zones[zone], now or ns.Utils.ServerTime())
end

-- The zone's fire level (0-3) as the map sees it: 0 for a lone WANTED ganker
function Hotspots:Level(zone, now)
    local _, level, a, e = self:Heat(zone, now)
    if level > 0 and self:IsLoneOutlaw(zone, a, e) then return 0 end
    return level
end

-- Time of the oldest activity still in the zone's window (nil when none): when the
-- fight that made the zone burn began
function Hotspots:Oldest(zone)
    local data = zones[zone]
    if not data then return nil end
    local oldest
    for _, list in ipairs({ data.fighters, data.enemies, data.deaths }) do
        for _, value in pairs(list) do
            local t = type(value) == "table" and value.t or value
            if not oldest or t < oldest then oldest = t end
        end
    end
    return oldest
end

-- True when the zone's heat is only deaths by ONE WANTED outlaw (no fighters, no
-- enemies seen): that is a ganker, already covered by the WANTED popup, not a
-- battle (author, 2026-09-23: chat line only).
function Hotspots:IsLoneOutlaw(zone, a, e, data)
    if a > 0 or e > 0 then return false end
    local killer
    for _, death in pairs((data or zones[zone]).deaths) do
        if not death.killer or (killer and death.killer ~= killer) then return false end
        killer = death.killer
    end
    local entry = killer and ns.Wanted:Get(killer)
    return entry ~= nil and entry.wanted == true
end

-- Newest known fight position in the zone (a fighter or a death), in zone coordinates
local function LastPosition(data)
    local best
    for _, list in ipairs({ data.fighters, data.deaths }) do
        for _, item in pairs(list) do
            if item.x and item.y and (not best or item.t > best.t) then best = item end
        end
    end
    if best then return best.x, best.y end
    return nil
end

-------------------------------------------------
-- Areas (HH-163)
-------------------------------------------------

-- The lists an area holds, like a zone; names only follow the area they were seen in
local AREA_LISTS = { "fighters", "allies", "enemies", "deaths" }
local ZONE_LISTS = { "fighters", "allies", "enemies", "deaths", "names" }
-- How far a merged-away area id is followed to the area that took it
local MAX_ALIAS_HOPS = 8

local function NewArea(x, y, t)
    return { fighters = {}, allies = {}, enemies = {}, deaths = {}, names = {}, keys = {}, x = x, y = y, t = t }
end

local function Distance(x1, y1, x2, y2)
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

-- The area whose middle is nearest to x, y; within AREA_RADIUS unless `anyDistance`
local function NearestArea(areas, x, y, anyDistance)
    local best, bestDistance
    for _, area in ipairs(areas) do
        if area.x then
            local distance = Distance(x, y, area.x, area.y)
            if (anyDistance or distance <= Hotspots.AREA_RADIUS) and (not bestDistance or distance < bestDistance) then
                best, bestDistance = area, distance
            end
        end
    end
    return best
end

-- Newest first; the same moment in a fixed order, so every HeadHunter gets the same areas
local function NewestFirst(p, q)
    if p.t ~= q.t then return p.t > q.t end
    return p.key < q.key
end

-- Areas hottest first, then the newest
local function HottestArea(p, q)
    if p.heat ~= q.heat then return p.heat > q.heat end
    return p.t > q.t
end

-- A zone's spots hottest first, then the oldest area
local function HottestSpot(p, q)
    if p.heat ~= q.heat then return p.heat > q.heat end
    return p.id < q.id
end

-- Every zone's shown spots hottest first, in a fixed order
local function HottestOnMap(p, q)
    if p.heat ~= q.heat then return p.heat > q.heat end
    if p.zone ~= q.zone then return p.zone < q.zone end
    return p.id < q.id
end

local function AddItem(area, item)
    area[item.list][item.id] = item.value
    area.keys[#area.keys + 1] = item.key
end

-- A zone's activity within WINDOW (the zone's lists are pruned first), split by place,
-- newest area first. The newest activity is an area's middle; activity within
-- AREA_RADIUS of a middle joins the nearest one, further away it starts another area.
-- So two areas' middles are always more than AREA_RADIUS apart, and areas whose fights
-- came together are one. Activity with no position joins the newest area (or makes one
-- with no place). Each area lists its activity's keys ("enemies:E0000001"), which tell
-- which area seen before it is.
local function Split(data, now)
    local since = now - Hotspots.WINDOW
    for _, list in ipairs(ZONE_LISTS) do CountRecent(data[list], since) end
    local items = {}
    for _, list in ipairs(AREA_LISTS) do
        for id, value in pairs(data[list]) do
            items[#items + 1] = { list = list, id = id, key = list .. ":" .. tostring(id), value = value, t = Stamp(value) }
        end
    end
    table.sort(items, NewestFirst)
    local areas, loose = {}, {}
    for _, item in ipairs(items) do
        local x, y = item.value.x, item.value.y
        if x and y then
            local area = NearestArea(areas, x, y)
            if not area then
                area = NewArea(x, y, item.t)
                areas[#areas + 1] = area
            end
            AddItem(area, item)
        else
            loose[#loose + 1] = item
        end
    end
    if #loose > 0 and #areas == 0 then areas[1] = NewArea(nil, nil, loose[1].t) end
    for _, item in ipairs(loose) do AddItem(areas[1], item) end
    for key, name in pairs(data.names) do
        local area = (name.x and name.y and NearestArea(areas, name.x, name.y, true)) or areas[1]
        if area then area.names[key] = name end
    end
    return areas
end

-- The area id that `id` is now: an area merged into another is found under the other's id
local function Resolve(state, id)
    for _ = 1, MAX_ALIAS_HOPS do
        if not id or state.entries[id] then return id end
        id = state.aliases[id]
    end
    return nil
end

-- How many of the area's activity keys each area seen before held: id -> count
local function Votes(state, area)
    local votes = {}
    for _, key in ipairs(area.keys) do
        local id = state.owner[key]
        if id and state.entries[id] then votes[id] = (votes[id] or 0) + 1 end
    end
    return votes
end

-- The id with the most votes, not taken yet; the same count: the higher alert, then the older
local function MostVoted(state, votes, taken)
    local best, bestCount
    for id, count in pairs(votes) do
        if not taken[id] then
            local entry, other = state.entries[id], best and state.entries[best]
            local better = not best or count > bestCount
                or (count == bestCount and ((entry.announced or 0) > (other.announced or 0)
                    or ((entry.announced or 0) == (other.announced or 0) and id < best)))
            if better then best, bestCount = id, count end
        end
    end
    return best
end

-- The nearest area seen before within AREA_RADIUS of the area's middle, not taken yet
local function NearestEntry(state, area, taken)
    if not area.x then return nil end
    local best, bestDistance
    for id, entry in pairs(state.entries) do
        if not taken[id] and entry.x then
            local distance = Distance(area.x, area.y, entry.x, entry.y)
            if distance <= Hotspots.AREA_RADIUS and (not bestDistance or distance < bestDistance) then
                best, bestDistance = entry, distance
            end
        end
    end
    return best
end

local function Take(area, entry, taken)
    taken[entry.id] = true
    area.id, area.entry = entry.id, entry
end

-- An area keeps the id of the area seen before that held most of its activity, so it stays
-- the same fight while it moves, grows or loses players (within AREA_MEMORY, also after a
-- quiet spell). The hottest area chooses first. An area with none of an earlier area's
-- players is the earlier area at about its place, if there is one (a regroup of others).
-- An area seen before whose activity went mostly into another area merged into it: the
-- area keeps the highest alert level and the longest [Ignore], and its own level counts
-- as said, so a merge never alerts. A new area split off from one seen before starts with
-- that one's alert level and [Ignore], so a split never alerts either.
local function Match(state, areas)
    local taken, bestOf, waiting = {}, {}, {}
    for _, area in ipairs(areas) do
        local votes = Votes(state, area)
        for id, count in pairs(votes) do
            if not bestOf[id] or count > bestOf[id].count then bestOf[id] = { area = area, count = count } end
        end
        local id = MostVoted(state, votes, taken)
        if id then
            Take(area, state.entries[id], taken)
        else
            waiting[#waiting + 1] = { area = area, votes = votes }
        end
    end
    for _, wait in ipairs(waiting) do
        local entry = NearestEntry(state, wait.area, taken)
        if not entry then
            areaSerial = areaSerial + 1
            entry = { id = areaSerial }
            local parent = state.entries[MostVoted(state, wait.votes, {}) or 0]
            if parent then entry.announced, entry.ignoredUntil = parent.announced, parent.ignoredUntil end
            state.entries[entry.id] = entry
        end
        Take(wait.area, entry, taken)
    end
    for id, entry in pairs(state.entries) do
        local best = bestOf[id]
        if not taken[id] and best then
            local target = best.area.entry
            target.announced = math.max(target.announced or 0, entry.announced or 0, best.area.level)
            target.ignoredUntil = math.max(target.ignoredUntil or 0, entry.ignoredUntil or 0)
            target.quietSince = target.quietSince or entry.quietSince
            state.entries[id] = nil
            state.aliases[id] = target.id
        end
    end
end

-- A zone's areas now, hottest first: each with heat, level, a, e, d (the window), id and
-- entry (what it keeps between looks). Worked out once per zone change and second, so the
-- map, the alerts and Help share one result. Areas quiet for AREA_MEMORY are forgotten;
-- until then they keep their players, so a regroup is still the same fight.
function Hotspots:Areas(zone, now)
    now = now or ns.Utils.ServerTime()
    local data = zones[zone]
    local version = data and data.version
    local state = areaState[zone]
    local cache = state and state.cache
    if cache and cache.now == now and cache.version == version then return cache.areas end
    local areas = data and Split(data, now) or {}
    for _, area in ipairs(areas) do
        area.heat, area.level, area.a, area.e, area.d = HeatOf(area, now)
    end
    table.sort(areas, HottestArea)
    state = state or { entries = {}, owner = {}, aliases = {} }
    areaState[zone] = state
    Match(state, areas)
    local owner, current = {}, {}
    for _, area in ipairs(areas) do
        current[area.id] = true
        local entry = area.entry
        entry.x, entry.y = area.x or entry.x, area.y or entry.y
        entry.t = math.max(entry.t or 0, area.t or 0)
        for _, key in ipairs(area.keys) do owner[key] = area.id end
    end
    for id, entry in pairs(state.entries) do
        if not current[id] and now - (entry.t or 0) > self.AREA_MEMORY then state.entries[id] = nil end
    end
    for key, id in pairs(state.owner) do
        if not owner[key] and not current[id] and state.entries[id] then owner[key] = id end
    end
    state.owner = owner
    for old, id in pairs(state.aliases) do
        if not Resolve(state, id) then state.aliases[old] = nil end
    end
    if next(state.entries) == nil then
        areaState[zone] = nil
    else
        state.cache = { now = now, version = version, areas = areas }
    end
    return areas
end

-- One area of the zone now, by id, following merges (nil when it has no activity left)
function Hotspots:FindArea(zone, id, now)
    local areas = self:Areas(zone, now)
    local state = areaState[zone]
    id = state and Resolve(state, id)
    for _, area in ipairs(areas) do
        if area.id == id then return area end
    end
    return nil
end

-- What an area keeps between looks, by id, following merges
local function Entry(zone, id)
    local state = areaState[zone]
    id = state and Resolve(state, id)
    return id and state.entries[id]
end

-- [Ignore] on an area: no alerts about it for IGNORE_TIME, also after a merge
function Hotspots:IgnoreArea(zone, id)
    self:Areas(zone)
    local entry = Entry(zone, id)
    if entry then entry.ignoredUntil = ns.Utils.Now() + self.IGNORE_TIME end
end

-- A whole-number setting kept within min..max, `default` when unset
local function SettingNumber(key, min, max, default)
    local value = tonumber(ns.db and ns.db.settings[key]) or default
    return math.max(min, math.min(max, math.floor(value)))
end

-- HH-164: how long a PvP area's mark stays after its newest activity, in seconds: the
-- setting, MAP_MINUTES_MIN to MAP_MINUTES_MAX minutes
function Hotspots.MapTime()
    return 60 * SettingNumber("hotspotMapMinutes", Hotspots.MAP_MINUTES_MIN, Hotspots.MAP_MINUTES_MAX,
        Hotspots.MAP_MINUTES_DEFAULT)
end

-- How many of a zone's areas the map shows and alerts: the setting, 1 to MAX_AREAS
function Hotspots.PerZone()
    return SettingNumber("hotspotsPerZone", 1, Hotspots.MAX_AREAS, Hotspots.MAX_AREAS)
end

-- Only a lone WANTED ganker's kills: the skull marks it, so no PvP area and no popup
local function IsLone(zone, area)
    return area.level > 0 and Hotspots:IsLoneOutlaw(zone, area.a, area.e, area)
end

-- The area as it is now, if it burns (level 1+, and not a lone WANTED ganker):
--   { zone, id, level, heat, a, e, d, x, y, t = newest activity }. Also kept for the map.
local function Burning(zone, area, now)
    if area.level == 0 or IsLone(zone, area) then return nil end
    local a, e = NowOf(area, now)
    local entry = area.entry
    local spot = { zone = zone, id = area.id, level = area.level, heat = area.heat, a = a, e = e, d = area.d,
        x = area.x or entry.x, y = area.y or entry.y, t = area.t }
    entry.spot = spot
    return spot
end

-- A zone's PvP areas, hottest first, all of them: burning areas as they are now, and
-- areas that burned as they last were (remembered = true), each while its newest activity
-- is at most `keep` seconds old
local function ZoneSpots(zone, now, keep)
    local list, seen = {}, {}
    for _, area in ipairs(Hotspots:Areas(zone, now)) do
        local spot = Burning(zone, area, now)
        if spot then
            seen[area.id] = true
            if now - spot.t <= keep then list[#list + 1] = spot end
        end
    end
    local state = areaState[zone]
    for id, entry in pairs(state and state.entries or {}) do
        if not seen[id] and entry.spot and now - entry.t <= keep then
            local copy = {}
            for k, v in pairs(entry.spot) do copy[k] = v end
            copy.remembered, copy.t = true, entry.t
            list[#list + 1] = copy
        end
    end
    table.sort(list, HottestSpot)
    return list
end

-- A zone's PvP areas for the map, hottest first: each until MapTime() after its newest
-- activity, also while it still burns (HH-164)
function Hotspots:Spots(zone, now)
    return ZoneSpots(zone, now or ns.Utils.ServerTime(), self.MapTime())
end

-- PvP areas for the map (HH-046), hottest first: each zone's hottest PerZone() areas
-- (HH-163). x, y is the area's newest fight position (nil when none is known).
-- Lone-outlaw areas are left out: the WANTED skull pin already marks that ganker.
function Hotspots:Active(now)
    now = now or ns.Utils.ServerTime()
    local list, known, zoneList = {}, {}, {}
    for _, source in ipairs({ zones, areaState }) do
        for zone in pairs(source) do
            if not known[zone] then
                known[zone] = true
                zoneList[#zoneList + 1] = zone
            end
        end
    end
    local limit = self.PerZone()
    for _, zone in ipairs(zoneList) do
        for i, spot in ipairs(self:Spots(zone, now)) do
            if i > limit then break end
            list[#list + 1] = spot
        end
    end
    table.sort(list, HottestOnMap)
    return list
end

-------------------------------------------------
-- Alerts
-------------------------------------------------

Hotspots.FIRE_ICON = "Interface\\Icons\\Spell_Fire_Fire"

local function Fire(level)
    local icon = "|T" .. Hotspots.FIRE_ICON .. ":14:14|t"
    return string.rep(icon, level)
end
Hotspots.Fire = Fire

local function EnemyFaction()
    local mine = ns.Utils.UnitFaction("player")
    if mine == "Alliance" then return ns.Utils.FactionName("Horde") end
    if mine == "Horde" then return ns.Utils.FactionName("Alliance") end
    return L.ENEMIES
end
Hotspots.EnemyFaction = EnemyFaction

-- Our side of the fight. The count next to it is the players of our faction the
-- HeadHunters there see in combat, so it is a lower bound.
local function OwnFaction()
    local mine = ns.Utils.UnitFaction("player")
    if mine == "Alliance" or mine == "Horde" then return ns.Utils.FactionName(mine) end
    return L.HEADHUNTERS
end
Hotspots.OwnFaction = OwnFaction

-- "≈4 Horde fighting 5 Alliance, 4 death(s) in 5 min", saying only what is known:
-- a = HeadHunters fighting, e = enemies seen, d = deaths
function Hotspots.Describe(a, e, d)
    local parts = {}
    if e > 0 and a > 0 then
        parts[1] = string.format(L.HOTSPOT_BOTH, e, EnemyFaction(), a, OwnFaction())
    elseif e > 0 then
        parts[1] = string.format(L.HOTSPOT_ENEMIES, e, EnemyFaction())
    elseif a > 0 then
        parts[1] = string.format(L.HOTSPOT_OURS, a, OwnFaction())
    end
    if d > 0 then parts[#parts + 1] = string.format(L.HOTSPOT_DEATHS, d) end
    return table.concat(parts, ", ")
end

-- Where a fight is: the area's middle (HH-163; as it last was when it has gone quiet), or
-- the zone's newest fight without an area; nil when unknown
function Hotspots:Place(zone, areaId)
    if areaId then
        self:Areas(zone)
        local entry = Entry(zone, areaId)
        if entry and entry.x and entry.y then return entry.x, entry.y end
    end
    local data = zones[zone]
    if not data then return nil end
    return LastPosition(data)
end

-- [Help]: a waypoint to the newest fight where the client allows it (Classic Era does
-- not), and chat always says where it is. title: "Battle", ...
-- HH-111: the players fighting there get a quiet "help on the way" note (an addon
-- message, never chat). One whisper asks a fighter there for a group invite, like the
-- posse (alerts.whisperInvite): from any zone, or inside the zone when they are on
-- another layer, and each HeadHunter at most once an hour (HH-145, Alerts/Invites.lua).
-- Runs inside the popup click, which allows the whisper. fromMap (a shift-click on the
-- map mark, author 2026-10-16): the whisper is only opened for the player to send, to
-- the newest fighter there, without the hourly limit. HH-163: areaId is the area of the
-- popup or the map mark: the way to that fight and a fighter there; without it, the zone.
function Hotspots:Help(zone, title, fromMap, areaId)
    local x, y = self:Place(zone, areaId)
    local zoneName = ns.Utils.MapName(zone) or L.UNKNOWN_ZONE
    local how = ns.MapMarkers.GuideAndTell(zone, x, y, string.format(L.GUIDE_HOTSPOT, title, zoneName),
        string.format(L.HOTSPOT_WAYPOINT, zoneName))

    local U = ns.Utils
    ns.Transport:Queue(ns.Protocol.TYPES.HELP, ns.Protocol.EncodeHelp(zone, U.ServerTime()),
        ns.Transport.PRIORITY.alert, "B:" .. zone)

    local state, target = self:InviteState(zone, nil, fromMap, areaId)
    if state == "ok" and fromMap then
        U.OpenWhisper(U.PlayerKey(target.sender), string.format(L.HOTSPOT_WHISPER, zoneName))
    elseif state == "ok" then
        local ok = pcall(SendChatMessage, string.format(L.HOTSPOT_WHISPER, zoneName), "WHISPER", nil, target.sender)
        if ok then
            ns.Invites:Mark(target.sender)
            ns:Print(string.format(L.POSSE_WHISPERED, U.DisplayName(U.PlayerKey(target.sender)) or target.sender))
        end
    elseif state == "asked" then
        ns:Print(string.format(L.INVITE_ALREADY_ASKED, ns.Invites.Minutes(target)))
    end
    return how
end

-- The newest other fighter who said which layer they are on, can be whispered and was
-- not asked for an invite in the last hour (any, with noLimit); also the seconds until
-- the first of the ones we asked is free again. With a zone: inside it only fighters on
-- another layer than ours (from another zone layers cannot be compared, and any fighter
-- can invite).
function Hotspots.InviteTarget(data, me, zone, now, noLimit)
    local here = zone and ns.Zones.ZoneOf(ns.Utils.PlayerMapID()) == zone
    local best, left
    for who, fighter in pairs(data.fighters) do
        if who ~= me and fighter.sender and fighter.layer
                and (not here or ns.Layer:Compare(fighter.layer, zone) == "different") then
            local wait = not noLimit and ns.Invites:Left(fighter.sender, now)
            if wait then
                left = math.min(left or wait, wait)
            elseif not best or fighter.t > best.t then
                best = fighter
            end
        end
    end
    return best, left
end

-- Whether Help asks for an invite now (HH-145): "ok" and the fighter to whisper,
-- "asked" and the seconds until one is free again, or "none" (nobody to ask, the
-- option alerts.whisperInvite is off, or every fighter there is on our layer). noLimit:
-- for the map mark, which only opens the whisper. areaId: only the fighters of that area
-- (HH-163); an area with no activity left has nobody to ask.
function Hotspots:InviteState(zone, now, noLimit, areaId)
    local data = zones[zone]
    if areaId then data = self:FindArea(zone, areaId, now) end
    if not data or not ns.db.settings.alerts.whisperInvite then return "none" end
    local target, left = self.InviteTarget(data, ns.Utils.CompactName(ns.Utils.UnitKey("player")), zone, now, noLimit)
    if target then return "ok", target end
    if left then return "asked", left end
    return "none"
end

-- Someone clicked [Help] for a zone: tell us if we are fighting there
Hotspots.HELP_NOTE_THROTTLE = 60
function Hotspots:OnHelp(record, sender)
    local mapID, t = ns.Protocol.DecodeHelp(record)
    if not mapID or not t then return end
    local U = ns.Utils
    local now = U.ServerTime()
    if t > now + self.MAX_SKEW or now - t > self.WINDOW then return end
    local zone = ns.Zones.ZoneOf(mapID)
    local data = zone and zones[zone]
    local mine = data and data.fighters[U.CompactName(U.UnitKey("player"))]
    if not mine or now - mine.t > self.FIGHT_RECENT * 4 then return end
    -- A link: a click whispers them (the helper is on our faction)
    local name = U.PlayerLink(U.PlayerKey(sender)) or tostring(sender)
    ns.Alerts:Show({
        key = "help:" .. tostring(U.CompactName(sender)),
        throttle = self.HELP_NOTE_THROTTLE,
        chat = string.format(L.HOTSPOT_HELP_COMING, name, U.MapName(zone) or L.UNKNOWN_ZONE),
        combat = true,
    })
    ns.Events:Fire("HH_HELP_COMING", zone, sender)
end

-- One area's alert, when it climbs a level: never for our own fight there, nor while
-- [Ignore] mutes it or the zone is out of the alert range
local function AlertArea(zone, area, now, me)
    local entry, level, lone = area.entry, area.level, IsLone(zone, area)
    if (entry.announced or 0) >= level then return end
    local mine = me and area.fighters[me]
    if mine and now - mine.t <= Hotspots.FIGHT_RECENT * 4 then
        entry.quietSince = mine.t
        ns:Debug("Hotspot: quiet, our own fight in", zone, "area", area.id, "level", level)
        return
    end
    if entry.quietSince then
        if not Hotspots:ActivitySince(zone, entry.quietSince + Hotspots.FIGHT_RECENT * 4, me, area) then return end
        entry.quietSince = nil
    end
    if entry.ignoredUntil and ns.Utils.Now() < entry.ignoredUntil then return end
    if not ns.Zones.InRange(zone) then return end
    entry.announced = level

    local zoneName = ns.Utils.MapName(zone) or L.UNKNOWN_ZONE
    local title = L["HOTSPOT_LEVEL_" .. level]
    local nowA, nowE = NowOf(area, now)
    local line = string.format(L.HOTSPOT_LINE, Fire(level), title, zoneName, Hotspots.Describe(nowA, nowE, area.d))
    local names = Hotspots:EnemyNames(area, now)
    if names then line = line .. string.format(L.HOTSPOT_NAMES, names) end
    local chat = line
    local fighters = Hotspots:FighterNames(area, now)
    if fighters then
        line = line .. string.format(L.HOTSPOT_FIGHTING, fighters)
        chat = chat .. string.format(L.HOTSPOT_FIGHTING, Hotspots:FighterNames(area, now, true))
    end
    local alert = {
        key = "hot:" .. zone .. ":" .. area.id .. ":" .. level,
        throttle = Hotspots.LEVEL_THROTTLE,
        chat = chat,
    }
    local areaId = area.id
    if level >= 2 and not lone then
        alert.sound = true
        alert.popup = {
            dialog = ns.Alerts.HOTSPOT_POPUP,
            text = line,
            accept = L.HOTSPOT_HELP,
            decline = L.HOTSPOT_IGNORE,
            onAccept = function() Hotspots:Help(zone, title, nil, areaId) end,
            onDecline = function() Hotspots:IgnoreArea(zone, areaId) end,
        }
    end
    if level >= 3 and not lone then
        alert.text = string.format(L.HOTSPOT_CENTER, Fire(level), title, zoneName)
    end
    ns.Alerts:Show(alert)
    ns.Events:Fire("HH_HOTSPOT", zone, level, area.heat)
end

-- The zone's data changed: the map redraws (HH_HOTSPOT_CHANGED), every burning area is
-- kept for the map (even if the map is not open now), and each of the zone's hottest
-- PerZone() areas alerts on its own (HH-163). HH_HOTSPOT is only for alerts. The ranking is
-- the map's, but over every area burning or remembered within AREA_MEMORY, so how long
-- marks stay on the map never changes who is alerted (HH-164). A lone WANTED ganker's area
-- is no spot and takes no place, but still gets its chat line. An area keeps the level it
-- was announced at while it is remembered, so a regroup at that level is no news.
function Hotspots:Evaluate(zone)
    ns.Events:Fire("HH_HOTSPOT_CHANGED", zone)
    local now = ns.Utils.ServerTime()
    local me = ns.Utils.CompactName(ns.Utils.UnitKey("player"))
    local limit = self.PerZone()
    local ranked = {}
    for rank, spot in ipairs(ZoneSpots(zone, now, self.AREA_MEMORY)) do
        if rank > limit then break end
        ranked[spot.id] = true
    end
    for _, area in ipairs(self:Areas(zone, now)) do
        if area.level == 0 then
            area.entry.quietSince = nil
        elseif ranked[area.id] or IsLone(zone, area) then
            AlertArea(zone, area, now, me)
        end
    end
end

-- 1.0.9: a ping that names enemies, all of them from our own fight (`ours`: short id -> t)
local function OurFightOnly(ids, ours)
    if not ours or not ids or #ids == 0 then return false end
    for _, id in ipairs(ids) do
        if not ours[id] then return false end
    end
    return true
end

-- 1.0.5: someone else fought, an enemy was seen fighting, or someone died in the zone at
-- `since` or later (our own fight left out: our pings, and since 1.0.9 the pings and
-- enemies of our own fight, only those we fought within WINDOW: an old fight's enemy
-- seen again is new activity)
-- area: the area of the zone to look at (HH-163)
function Hotspots:ActivitySince(zone, since, me, area)
    local ours = ownEnemies[zone]
    if ours then CountRecent(ours, ns.Utils.ServerTime() - self.WINDOW) end
    for who, fighter in pairs(area.fighters) do
        if who ~= me and (fighter.t or 0) >= since and not OurFightOnly(fighter.enemies, ours) then return true end
    end
    for id, enemy in pairs(area.enemies) do
        if (tonumber(Stamp(enemy)) or 0) >= since and not (ours and ours[id]) then return true end
    end
    for _, death in pairs(area.deaths) do
        if (tonumber(death.t) or 0) >= since then return true end
    end
    return false
end

-------------------------------------------------
-- Our own fight
-------------------------------------------------

-- The units we can look at: what we target, focus and point at, our group close to us
-- and what they target, and every nameplate (friendly nameplates only when the player shows them)
local SCAN_UNITS = { "target", "focus", "mouseover", "targettarget", "focustarget" }
for i = 1, 4 do SCAN_UNITS[#SCAN_UNITS + 1] = "party" .. i end
for i = 1, 4 do SCAN_UNITS[#SCAN_UNITS + 1] = "party" .. i .. "target" end
for i = 1, 40 do SCAN_UNITS[#SCAN_UNITS + 1] = "raid" .. i end
for i = 1, 40 do SCAN_UNITS[#SCAN_UNITS + 1] = "raid" .. i .. "target" end
for i = 1, 40 do SCAN_UNITS[#SCAN_UNITS + 1] = "nameplate" .. i end

local fightingEnemies, fightingAllies = {}, {} -- guid -> Now() last seen in combat
local engagedAt                                -- Now() an enemy was last engaged with us or our group
local allyInfo = {}                            -- guid -> who that ally is (HH_PVP_SEEN)

-- Who a player of our side is, read while their unit is in sight
local function PlayerInfo(unit, side)
    local U = ns.Utils
    local key = U.UnitKey(unit)
    if not key then return nil end
    return { key = key, side = side, class = U.UnitClass(unit), race = U.UnitRace(unit),
        level = U.UnitLevel(unit), guild = U.UnitGuild(unit), faction = U.UnitFaction(unit) }
end

-- In combat: true, false, or nil when the client hides it (WoW Forever may for enemies)
local function InCombat(unit)
    local U = ns.Utils
    local value = U.SafeCall(UnitAffectingCombat, unit)
    if value == nil or U.Accessible(value) == nil then return nil end
    return value and true or false
end

-- An enemy whose target is one of us is in the fight, whatever the combat flag says
local function TargetsOurSide(unit, mine)
    local U = ns.Utils
    local target = unit .. "target"
    return mine ~= nil and U.UnitIsPlayer(target) and U.UnitFaction(target) == mine
end

-- 1.0.5: an enemy whose target is us or a group member close to us (`ours`: GUID -> true)
local function TargetsUs(unit, ours)
    local guid = ns.Utils.UnitGUID(unit .. "target")
    return guid ~= nil and ours[guid] == true
end

-- A group member too far away to be in our fight, or what that member targets (HH-143:
-- a raid spread over the zone filled wars with players who were not there)
local function FarGroupUnit(unit)
    local member = unit:match("^(party%d+)") or unit:match("^(raid%d+)")
    return member ~= nil and not ns.Utils.UnitInFightRange(member)
end

-- The enemies our side is attacking: our target, and the target of each group member
-- in combat close to us (GUID -> true)
local GROUP_TARGETS = { "target" }
for i = 1, 4 do GROUP_TARGETS[#GROUP_TARGETS + 1] = "party" .. i end
for i = 1, 40 do GROUP_TARGETS[#GROUP_TARGETS + 1] = "raid" .. i end

-- 1.0.5: us and the group members close to us (GUID -> true)
local function OurSide()
    local U = ns.Utils
    local ours = {}
    local me = U.UnitGUID("player")
    if me then ours[me] = true end
    for i = 2, #GROUP_TARGETS do
        local unit = GROUP_TARGETS[i]
        local guid = U.UnitGUID(unit)
        if guid and not FarGroupUnit(unit) then ours[guid] = true end
    end
    return ours
end

local function OurTargets()
    local U = ns.Utils
    local targets = {}
    for _, unit in ipairs(GROUP_TARGETS) do
        local target = unit == "target" and unit or unit .. "target"
        local attacking = unit == "target" or (InCombat(unit) ~= false and not FarGroupUnit(unit))
        local guid = attacking and U.UnitGUID(target)
        if guid then targets[guid] = true end
    end
    return targets
end

-- Players in the fight around us now: enemies fighting our side, and players of our
-- faction in combat (not us). Returns what it saw, for the debug log: enemies fighting,
-- enemies not, combat unknown, and enemies engaged with us or our group
function Hotspots.ScanFighters()
    local U = ns.Utils
    local now = U.Now()
    local me, mine = U.UnitGUID("player"), U.UnitFaction("player")
    local attacked = OurTargets()
    local ours = OurSide()
    local engaged = 0
    local seen = {}
    local fighting, idle, unknown = 0, 0, 0
    for _, unit in ipairs(SCAN_UNITS) do
        local guid = U.UnitGUID(unit)
        if guid and guid ~= me and not seen[guid] and U.UnitIsPlayer(unit) and not FarGroupUnit(unit) then
            seen[guid] = true
            local combat = InCombat(unit)
            if U.UnitIsEnemyPlayer(unit) then
                if combat == nil then unknown = unknown + 1 end
                local withUs = TargetsUs(unit, ours) or (combat ~= false and attacked[guid] == true)
                if withUs or TargetsOurSide(unit, mine) then
                    ns.EnemyCache:ObserveUnit(unit, "nameplate")
                    fightingEnemies[guid] = now
                    fighting = fighting + 1
                    if withUs then
                        engaged = engaged + 1
                        engagedAt = now
                    end
                else
                    idle = idle + 1
                end
            elseif combat and mine and U.UnitFaction(unit) == mine then
                fightingAllies[guid] = now
                allyInfo[guid] = PlayerInfo(unit, "ally") or allyInfo[guid]
            end
        end
    end
    return fighting, idle, unknown, engaged
end

-- 1.0.5: an enemy was engaged with us or our group within FIGHT_RECENT
function Hotspots.Engaged()
    return engagedAt ~= nil and ns.Utils.Now() - engagedAt <= Hotspots.FIGHT_RECENT
end

-- GUIDs seen in combat within `seconds` (older ones are forgotten)
local function Recent(list, seconds)
    local now, guids = ns.Utils.Now(), {}
    for guid, at in pairs(list) do
        if now - at <= seconds then
            guids[#guids + 1] = guid
        else
            list[guid] = nil
            allyInfo[guid] = nil
        end
    end
    table.sort(guids)
    return guids
end

function Hotspots:Tick()
    if not ns.Guards:IsActive() then return end
    local U = ns.Utils
    if not U.SafeCall(UnitAffectingCombat, "player") then return end
    local fighting, idle, unknown, engaged = Hotspots.ScanFighters()
    ns.Log:Add("debug", string.format("PvP scan: enemies fighting %d (with us %d), not fighting %d, combat unknown %d",
        fighting, engaged, idle, unknown))
    local guids = Recent(fightingEnemies, self.FIGHT_RECENT)
    if #guids == 0 or not Hotspots.Engaged() then return end
    -- Our side: us first, then the players of our faction fighting around us
    local allies = { Hotspots.ShortId(U.UnitGUID("player")) }
    local seen = { PlayerInfo("player", "ally") }
    for _, guid in ipairs(Recent(fightingAllies, self.FIGHT_RECENT)) do
        allies[#allies + 1] = Hotspots.ShortId(guid)
        seen[#seen + 1] = allyInfo[guid]
    end
    local ids, enemies = {}, {}
    for i, guid in ipairs(guids) do
        ids[i] = Hotspots.ShortId(guid)
        local record = ns.EnemyCache:ByGUID(guid)
        local name = record and (U.DisplayName(record.key) or record.name)
        if name and #enemies < ns.Protocol.MAX_PING_NAMES then
            enemies[#enemies + 1] = { name = name, class = record.class, level = record.level }
        end
        if record and record.key then
            seen[#seen + 1] = { key = record.key, side = "enemy", class = record.class, race = record.race,
                level = record.level, guild = record.guild, faction = record.faction }
        end
    end
    -- Pings carry the zone, so the position must be on the zone map too (not a cave's)
    local mapID = U.PlayerMapID()
    local _, x, y = ns.Zones.ToZone(mapID, U.PlayerPosition(mapID))
    local now = U.ServerTime()
    local layer = ns.Layer:Current()
    local zone = self:AddFighter(mapID, U.CompactName(U.UnitKey("player")), now, x, y, ids,
        { enemies = enemies, layer = layer, allies = allies })
    if not zone then return end
    ownEnemies[zone] = ownEnemies[zone] or {}
    CountRecent(ownEnemies[zone], now - self.WINDOW)
    for _, id in ipairs(ids) do ownEnemies[zone][id] = now end
    ns.Events:Fire("HH_PVP_SEEN", zone, seen, layer, now)
    if now - lastPing >= self.PING_INTERVAL then
        lastPing = now
        local Protocol, Transport = ns.Protocol, ns.Transport
        Transport:Queue(Protocol.TYPES.HOTSPOT, Protocol.EncodeHotspot(zone, now, x, y, ids, enemies, layer, allies),
            Transport.PRIORITY.hotspot, "P:" .. zone)
    end
    self:Evaluate(zone)
end

function Hotspots:OnPeerPing(record, sender)
    local mapID, t, x, y, ids, enemies, layer, allies = ns.Protocol.DecodeHotspot(record)
    if not mapID then return end
    local now = ns.Utils.ServerTime()
    if t > now + self.MAX_SKEW or now - t > self.WINDOW then return end
    local zone = self:AddFighter(mapID, ns.Utils.CompactName(sender), t, x, y, ids,
        { sender = sender, layer = layer, enemies = enemies, allies = allies })
    if not zone then return end
    local U = ns.Utils
    local seen = { { key = U.PlayerKey(sender), side = "ally", faction = U.UnitFaction("player") } }
    for _, enemy in ipairs(enemies or {}) do
        local key = U.PlayerKey(enemy.name)
        if key then seen[#seen + 1] = { key = key, side = "enemy", class = enemy.class, level = enemy.level } end
    end
    ns.Events:Fire("HH_PVP_SEEN", zone, seen, layer, t)
    self:Evaluate(zone)
end

local function Ticker()
    C_Timer.After(Hotspots.TICK, function()
        local ok, err = pcall(Hotspots.Tick, Hotspots)
        if not ok then ns:Error(err) end
        Ticker()
    end)
end

-- Deaths are evaluated after the WANTED recompute (1 s debounce), so the lone
-- outlaw check sees whether the killer is WANTED. One check per zone per burst.
Hotspots.DEATH_DELAY = 1.5
local deathCheckPending = {}

local function ScheduleDeathCheck(zone)
    if deathCheckPending[zone] then return end
    deathCheckPending[zone] = true
    C_Timer.After(Hotspots.DEATH_DELAY, function()
        deathCheckPending[zone] = nil
        Hotspots:Evaluate(zone)
    end)
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.HOTSPOT, function(record, sender) Hotspots:OnPeerPing(record, sender) end)
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.HELP, function(record, sender) Hotspots:OnHelp(record, sender) end)
    ns.Events:Register("HH_REPORT_ADDED", function(_, report)
        local zone = Hotspots:AddDeath(report)
        if zone then ScheduleDeathCheck(zone) end
    end, OWNER)
    Ticker()
end, OWNER)

-- The zone's name and, when known, the area's place on its map: "Westfall 40, 60"
local function AreaLabel(zone, area)
    local name = ns.Utils.MapName(zone) or tostring(zone)
    if not (area.x and area.y) then return name end
    return string.format("%s %.0f, %.0f", name, area.x * 100, area.y * 100)
end

-- HH-163: a line per area, zone by zone, every area (the setting does not apply)
ns.SlashCommands:Register("hotspots", function()
    local now = ns.Utils.ServerTime()
    local list = {}
    for zone in pairs(zones) do list[#list + 1] = zone end
    table.sort(list)
    local any = false
    for _, zone in ipairs(list) do
        for _, area in ipairs(Hotspots:Areas(zone, now)) do
            if area.heat > 0 then
                any = true
                ns:Print(string.format(L.HOTSPOT_STATUS, Fire(area.level), AreaLabel(zone, area),
                    area.heat, area.a, area.e, area.d))
            end
        end
    end
    if not any then ns:Print(L.HOTSPOT_NONE) end
end, L.HELP_HOTSPOTS)
