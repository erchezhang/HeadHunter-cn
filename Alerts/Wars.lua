-- HH-136: wars. A hotzone marks a war from its start to its end (author, 2026-10-08):
-- while a zone burns, the addon collects the PvP there, and when the zone has been
-- cold for END_AFTER the war is over and its record waits in the saved data for
-- HeadHunter Sync. The website merges every HeadHunter's record of the same war and
-- shows both sides.
--
-- One war per zone (author, 2026-10-08): the fight may move around the zone and stays
-- one war. The layers seen are kept, so the website can tell when a war was really two
-- fights on two layers.
--   start   the zone reaches 1 fire (Alerts/Hotspots.lua, a lone WANTED ganker is no
--           war); the war begins at the oldest activity still in the zone's window
--   end     the zone has been cold for END_AFTER; the war ends at its last hot moment.
--           Fighting again before that is the same war (a regroup, a corpse run). The
--           map keeps a PvP area just as long (Hotspots.MAP_TIME)
-- A war still going at logout or /reload stays open in the saved data and goes on after
-- the reload, or is closed at the next login; HeadHunter Sync sends only closed wars.
--
-- ns.db.wars (per home), oldest first, kept KEEP, at most MAX_WARS:
--   { id, by (our key), zone, started, ended (nil while open), lastHot, peak (1-3),
--     layers = { layer ids }, kills, honor, deaths (ours in the war),
--     fighters = { [player key] = { side = "ally" | "enemy", faction?, class?, race?,
--                  level?, guild?, first, last } } }
-- Fighters are the players seen in PvP combat there (HH_PVP_SEEN), with or without the
-- addon, at most MAX_FIGHTERS. Fires HH_WAR_STARTED(war) and HH_WAR_ENDED(war).

local addonName, ns = ...
local L = ns.L

local Wars = ns:RegisterModule("Wars", {})

local OWNER = "Wars"

-- END_AFTER: a war is over once its zone was cold this long.
-- CHECK: how often open wars are checked for their end.
Wars.END_AFTER = 600
Wars.CHECK = 30
Wars.KEEP = 30 * 86400
Wars.MAX_WARS = 200
Wars.MAX_FIGHTERS = 300
Wars.LIST = 10

-- Players seen fighting in a zone before it burned (zone -> key -> fighter): they join
-- the war when it starts, as the fight began with them
local recent = {}

local function Store()
    return ns.db and ns.db.wars
end

local function Merge(into, fighter, t)
    into.first = math.min(into.first or t, t)
    into.last = math.max(into.last or t, t)
    for _, field in ipairs({ "side", "faction", "class", "race", "guild" }) do
        if fighter[field] ~= nil then into[field] = fighter[field] end
    end
    local level = tonumber(fighter.level)
    if level and level > 0 and level > (tonumber(into.level) or 0) then into.level = level end
end

local function AddLayer(war, layer)
    layer = tonumber(layer)
    if not layer then return end
    for _, known in ipairs(war.layers) do
        if known == layer then return end
    end
    war.layers[#war.layers + 1] = layer
end

local function Fighters(war)
    local n = 0
    for _ in pairs(war.fighters) do n = n + 1 end
    return n
end

local function AddFighter(war, fighter, t)
    if not fighter.key then return end
    local known = war.fighters[fighter.key]
    if not known then
        if Fighters(war) >= Wars.MAX_FIGHTERS then return end
        known = {}
        war.fighters[fighter.key] = known
    end
    Merge(known, fighter, t)
end

-- The war going on in a zone (nil when none)
function Wars:Open(zone)
    for _, war in ipairs(Store() or {}) do
        if war.zone == zone and not war.ended then return war end
    end
    return nil
end

function Wars:Close(war)
    if war.ended then return end
    war.ended = war.lastHot
    ns.Log:Add("info", "War ended in " .. tostring(war.zone) .. " after " .. (war.ended - war.started) .. " s")
    ns.Events:Fire("HH_WAR_ENDED", war)
end

-- The zone's heat changed: a war starts at 1 fire, a burning zone keeps its war going
function Wars:OnHotspot(zone, now)
    now = now or ns.Utils.ServerTime()
    local store = Store()
    if not store or ns.Hotspots:Level(zone, now) == 0 then return nil end
    local war = self:Open(zone)
    if war and now - war.lastHot > self.END_AFTER then
        self:Close(war)
        war = nil
    end
    if not war then
        local by = ns.Utils.UnitKey("player")
        if not by then return nil end
        local started = math.min(ns.Hotspots:Oldest(zone) or now, now)
        war = { id = by .. ":" .. zone .. ":" .. started, by = by, zone = zone, started = started, lastHot = now,
            peak = 0, layers = {}, fighters = {}, kills = 0, honor = 0, deaths = 0 }
        store[#store + 1] = war
        for _, seen in pairs(recent[zone] or {}) do AddFighter(war, seen, seen.t) end
        AddLayer(war, ns.Layer:Current())
        ns.Log:Add("info", "War started in " .. tostring(zone))
        ns.Events:Fire("HH_WAR_STARTED", war)
    end
    war.lastHot = math.max(war.lastHot, now)
    war.peak = math.max(war.peak, ns.Hotspots:Level(zone, now))
    return war
end

-- Players seen fighting (Alerts/Hotspots.lua); kept for a war that starts in a moment
function Wars:OnSeen(zone, fighters, layer, t)
    t = t or ns.Utils.ServerTime()
    local war = self:OnHotspot(zone, t)
    local window = ns.Hotspots.WINDOW
    recent[zone] = recent[zone] or {}
    for key, seen in pairs(recent[zone]) do
        if seen.t < t - window then recent[zone][key] = nil end
    end
    for _, fighter in ipairs(fighters or {}) do
        if fighter.key then
            local copy = { t = t }
            for k, v in pairs(fighter) do copy[k] = v end
            recent[zone][fighter.key] = copy
            if war then AddFighter(war, fighter, t) end
        end
    end
    if war then AddLayer(war, layer) end
end

-- Our honorable kill (Detection/HonorKills.lua) in a war's zone
function Wars:OnHonorKill(record)
    local war = self:Open(ns.Zones.ZoneOf(record.mapID))
    if not war or (tonumber(record.t) or 0) - war.lastHot > self.END_AFTER then return end
    war.kills = war.kills + 1
    war.honor = war.honor + (tonumber(record.honor) or 0)
    AddLayer(war, record.layer)
end

-- Our PvP death (Detection/DeathReports.lua) in a war's zone: the killer fought there too
function Wars:OnDeath(report)
    local war = self:Open(ns.Zones.ZoneOf(report.mapID))
    if not war or (tonumber(report.t) or 0) - war.lastHot > self.END_AFTER then return end
    war.deaths = war.deaths + 1
    local killer = report.killer
    if type(killer) == "table" and killer.key then
        AddFighter(war, { key = killer.key, side = "enemy", class = killer.class, race = killer.race,
            level = killer.level, guild = killer.guild, faction = killer.faction }, report.t)
    end
    AddLayer(war, report.layer)
end

-- Ends the wars whose zone was cold long enough, and drops old ones
function Wars:Check(now)
    now = now or ns.Utils.ServerTime()
    local store = Store()
    if not store then return end
    for _, war in ipairs(store) do
        if not war.ended and now - war.lastHot >= self.END_AFTER then self:Close(war) end
    end
    local kept = {}
    for _, war in ipairs(store) do
        if not war.ended or war.ended >= now - self.KEEP then kept[#kept + 1] = war end
    end
    while #kept > self.MAX_WARS do table.remove(kept, 1) end
    ns.db.wars = kept
end

local function Ticker()
    C_Timer.After(Wars.CHECK, function()
        local ok, err = pcall(Wars.Check, Wars)
        if not ok then ns:Error(err) end
        Ticker()
    end)
end

ns.Events:Register("HH_INITIALIZED", function()
    local Events = ns.Events
    Wars:Check()
    Events:Register("HH_HOTSPOT_CHANGED", function(_, zone) Wars:OnHotspot(zone) end, OWNER)
    Events:Register("HH_PVP_SEEN", function(_, zone, fighters, layer, t) Wars:OnSeen(zone, fighters, layer, t) end, OWNER)
    Events:Register("HH_HONOR_KILL", function(_, record) Wars:OnHonorKill(record) end, OWNER)
    Events:Register("HH_DEATH_RECORDED", function(_, report) Wars:OnDeath(report) end, OWNER)
    Ticker()
end, OWNER)

-- One line per war, newest first: "Battle · The Barrens · 21:40 – 22:25 · ..."
function Wars:Line(war)
    local allies, enemies = 0, 0
    for _, fighter in pairs(war.fighters) do
        if fighter.side == "enemy" then enemies = enemies + 1 else allies = allies + 1 end
    end
    local peak = math.max(1, war.peak)
    local finish = war.ended and date("%H:%M", war.ended) or L.WAR_ONGOING
    return string.format(L.WAR_LINE, ns.Hotspots.Fire(peak), ns.Utils.MapName(war.zone) or L.UNKNOWN_ZONE,
        date("%H:%M", war.started), finish, allies, enemies, war.kills, war.deaths)
end

ns.SlashCommands:Register("wars", function()
    local store = Store() or {}
    if #store == 0 then
        ns:Print(L.WARS_NONE)
        return
    end
    for i = #store, math.max(1, #store - Wars.LIST + 1), -1 do ns:Print(Wars:Line(store[i])) end
end, L.HELP_WARS)
