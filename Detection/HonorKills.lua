-- Honorable kills by map and time (players' request, 2026-10-07): in big open-world
-- fights a side wants to show how many honorable kills it got where and when. Every
-- honorable kill the game gives us is kept with its time and place, HeadHunter Sync
-- sends our own to the website, and the website adds them up. Nobody judges who won.
--
-- The game gives an honorable kill to everyone who helped, not only the killing blow,
-- so the sum over all players is the game's own count, and each one belongs to one
-- player only: nothing is shared in game and nothing is counted twice.
--   Era      "X dies, honorable kill ..." names the victim. Its "awarded N honor" lines
--            are bonus honor, not kills.
--   Forever  "You have been awarded N Honor." names nobody (seen in game 2026-10-04).
--            An award right after a named line is the same kill.
-- Sync/Justice.lua reads the honor lines (none inside instances or duels) and fires
-- HH_HONOR_LINE(kind, name, text).
--
-- ns.db.honorKills, oldest first, kept DAYS days and at most LIMIT:
--   { t, seq (tells apart kills in the same second), by (our key), mapID, x, y, layer,
--     victim (player key, when the line names one), honor }
-- Fires HH_HONOR_KILL(record).

local addonName, ns = ...
local L = ns.L

local HonorKills = ns:RegisterModule("HonorKills", {})

local OWNER = "HonorKills"

-- SAME_KILL: an award this many seconds after a named line is that kill.
-- RECENT: /hh hk shows the kills of this many seconds.
HonorKills.SAME_KILL = 2
HonorKills.RECENT = 86400

-- Now() of the last named honorable kill line
local lastNamed = -math.huge

-- The honor points of a line: its last number ("Estimated Honor Points: 10", "awarded 5 Honor")
function HonorKills.HonorOf(text)
    local points
    for number in tostring(text):gmatch("%d+") do points = tonumber(number) end
    return points
end

-- Award lines count as kills only where the named line does not come (Forever)
local function AwardsAreKills()
    return not ns.Features.HasCLEU
end

function HonorKills:OnHonorLine(kind, name, text)
    local now = ns.Utils.Now()
    if kind == "kill" then
        lastNamed = now
        return self:Record(name, HonorKills.HonorOf(text))
    end
    if kind == "award" and AwardsAreKills() and now - lastNamed > self.SAME_KILL then
        return self:Record(nil, HonorKills.HonorOf(text))
    end
    return nil
end

function HonorKills:Record(victimName, honor)
    local U = ns.Utils
    local by = U.UnitKey("player")
    if not (ns.db and by) then return nil end
    local list = ns.db.honorKills
    local t = math.floor(U.ServerTime())
    local seq = 1
    for i = #list, 1, -1 do
        if list[i].t ~= t then break end
        seq = math.max(seq, (tonumber(list[i].seq) or 1) + 1)
    end
    local mapID = U.PlayerMapID()
    local x, y = U.PlayerPosition(mapID)
    local record = {
        t = t, seq = seq, by = by, mapID = mapID, x = x, y = y, layer = ns.Layer:Current(),
        victim = victimName and U.PlayerKey(victimName) or nil, honor = honor,
    }
    list[#list + 1] = record
    ns.Log:Add("info", "Honorable kill: " .. (record.victim or "?") .. " in " .. tostring(mapID))
    ns.Events:Fire("HH_HONOR_KILL", record)
    return record
end

-- Our character's honorable kills per zone since `since`, most first: { mapID, count }
function HonorKills:PerZone(since)
    local me = ns.Utils.UnitKey("player")
    local counts = {}
    for _, kill in ipairs(ns.db and ns.db.honorKills or {}) do
        if kill.t >= since and ns.Utils.SameCharacter(kill.by, me) and kill.mapID then
            counts[kill.mapID] = (counts[kill.mapID] or 0) + 1
        end
    end
    local zones = {}
    for mapID, count in pairs(counts) do zones[#zones + 1] = { mapID = mapID, count = count } end
    table.sort(zones, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.mapID < b.mapID
    end)
    return zones
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("HH_HONOR_LINE", function(_, kind, name, text) HonorKills:OnHonorLine(kind, name, text) end, OWNER)
end, OWNER)

ns.SlashCommands:Register("hk", function()
    local zones = HonorKills:PerZone(ns.Utils.ServerTime() - HonorKills.RECENT)
    if #zones == 0 then
        ns:Print(L.HONOR_KILLS_NONE)
        return
    end
    ns:Print(L.HONOR_KILLS_HEADER)
    for _, zone in ipairs(zones) do
        ns:Print(string.format(L.HONOR_KILLS_ZONE, ns.Utils.MapName(zone.mapID) or tostring(zone.mapID), zone.count))
    end
end, L.HELP_HK)
