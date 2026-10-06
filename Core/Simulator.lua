-- HH-005: inject fake data so rules, alerts and UI can be tested without real gankers.
--
--   /hh sim death "<name>" <level|skull> <CLASS> <RACE> [sex]
--   /hh sim sighting "<name>" <level|skull> <CLASS> <RACE> [sex]
--   /hh sim demo [clear]   every tab filled with a made-up story (Core/Demo.lua)
--   /hh sim send ...       simulated deaths shared with other characters (debug)
--   /hh sim clear          remove every simulated death and test catch
--   /hh sim duels [clear]  test duel spots in our zone, only on our screen (HH-134)
--
-- Forever names contain a space, so quote them: /hh sim death "Grim Reaper" skull ROGUE Human
-- Simulated data goes through the same internal events as real data:
--   HH_DEATH_REPORT(report, source)   consumed from HH-013 on
--   HH_ENEMY_SEEN(enemy, source)      consumed from HH-010 on

local addonName, ns = ...
local L = ns.L

local Simulator = ns:RegisterModule("Simulator", {})

local CLASSES = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}

local serial = 0

-- Returns an enemy record or nil + usage error
function Simulator:ParseEnemy(args)
    local U = ns.Utils
    local key = U.PlayerKey(args[1])
    if not key then
        return nil, string.format(L.SIM_BAD_NAME, tostring(args[1]))
    end
    local levelArg = args[2] and args[2]:lower()
    local level = levelArg == "skull" and -1 or tonumber(levelArg)
    local class = args[3] and args[3]:upper()
    local race = args[4]
    if not level or not CLASSES[class] or not race then
        return nil
    end
    local sex = tonumber(args[5])
    if sex ~= 2 and sex ~= 3 then sex = 1 end
    return {
        key = key,
        level = level,
        class = class,
        race = race,
        sex = sex,
        lastSeen = U.ServerTime(),
    }
end

local function PlayerSnapshot()
    local U = ns.Utils
    return {
        key = U.UnitKey("player"),
        level = U.UnitLevel("player"),
        class = U.UnitClass("player"),
        race = U.UnitRace("player"),
    }
end

-- Same shape as a real death report (HH-013)
function Simulator:BuildDeathReport(killer)
    local U = ns.Utils
    local now = U.ServerTime()
    serial = serial + 1
    local victim = PlayerSnapshot()
    local mapID = U.PlayerMapID()
    local x, y = U.PlayerPosition(mapID)
    return {
        id = string.format("%s:%d:sim%d", victim.key or "?", now, serial),
        t = now,
        victim = victim,
        killer = killer,
        assists = {},
        mapID = mapID,
        x = x,
        y = y,
        confidence = "sim",
    }
end

local function Describe(enemy)
    local level = enemy.level == -1 and "skull" or tostring(enemy.level)
    return string.format("%s %s %s", level, enemy.race, enemy.class)
end

-- /hh sim send "<killer>" [kills] [level|skull] [CLASS] [RACE] ["Zone"]
-- Debug only. Simulated deaths OF THIS CHARACTER, sent over the real sync so a
-- second character receives them (two-character tests of alerts and posses).
-- Must run from the typed command: on Era the realm-wide send needs that
-- hardware event.
-- After the kill count the values may come in any order: a number or "skull" is the
-- level, a class token the class, a zone name the place (its middle; default: where we
-- stand), anything else the race.
function Simulator.SendOptions(args)
    local options = { level = 60, class = "ROGUE", race = "Orc" }
    local levelSet = false
    for i = 3, #args do
        local value = args[i]
        local lower = value:lower()
        if not levelSet and (lower == "skull" or tonumber(value)) then
            options.level = lower == "skull" and -1 or tonumber(value)
            levelSet = true
        elseif CLASSES[value:upper()] then
            options.class = value:upper()
        elseif ns.Zones.FindByName(value) then
            options.mapID = ns.Zones.FindByName(value)
        else
            options.race = value
        end
    end
    return options
end

-- Refused where the zone cannot be read: other players would see "an unknown zone"
-- (HH-123). A named zone always works.
function Simulator:Send(args)
    local U = ns.Utils
    if not ns.debugMode then
        ns:Print(L.SIM_SEND_NEEDS_DEBUG)
        return
    end
    local key = U.PlayerKey(args[1])
    local count = tonumber(args[2]) or 1
    if not key or count < 1 or count > 10 then
        ns:Print(L.SIM_SEND_USAGE)
        return
    end
    local options = Simulator.SendOptions(args)
    local level, class, race = options.level, options.class, options.race

    local victim = PlayerSnapshot()
    local mapID, x, y = options.mapID, 0.5, 0.5
    if not mapID then
        mapID = U.PlayerMapID()
        x, y = U.PlayerPosition(mapID)
    end
    if not mapID or not x then
        ns:Print(L.SIM_SEND_NO_ZONE)
        return
    end
    local now = U.ServerTime()
    local records = {}
    for i = 1, count do
        local t = now - (count - i) * 60
        local report = {
            id = victim.key .. ":" .. t,
            t = t,
            victim = { key = victim.key, level = victim.level, class = victim.class, race = victim.race },
            killer = { key = key, name = key, level = level, class = class, race = race },
            assists = {},
            mapID = mapID, x = x, y = y,
            layer = not options.mapID and ns.Layer:Current() or nil, -- layers compare within one zone
            confidence = "sim",
            shared = true, -- sent to other HeadHunters, so login catch-up may pass it on
        }
        if ns.Reports:Add(report, "sim") then
            local record = ns.Protocol.EncodeDeath(report,
                ns.Protocol.MAX_MESSAGE - 4 - #ns.Transport.CHAT_MARK)
            if record then
                records[#records + 1] = record
                ns.Transport:Queue(ns.Protocol.TYPES.DEATH, record, ns.Transport.PRIORITY.alert, "D:" .. report.id)
            end
        end
    end
    if ns.Transport:RealmWideNeedsClick() and #records > 0 then
        ns.Transport:SendRealmWide(ns.Protocol.TYPES.DEATH, records)
    end
    ns:Print(string.format(L.SIM_SENT, #records, U.DisplayName(key), U.MapName(mapID) or L.UNKNOWN_ZONE))
end

-- /hh sim clear: removes every simulated death (our own and those other characters sent
-- with /hh sim send or /hh spree) and our /hh catch test catches. Outlaws left with no
-- kills drop out of WANTED, At large and the Hall of Shame with the next recompute.
-- Each test character clears its own data; bounty earned in tests stays.
function Simulator:Clear()
    local db = ns.db
    if not db then return nil end
    local removed = { reports = 0, deaths = 0, catches = 0 }
    for id, report in pairs(db.reports or {}) do
        if type(report) == "table" and report.confidence == "sim" and not report.demo then
            db.reports[id] = nil
            removed.reports = removed.reports + 1
        end
    end
    local kept = {}
    for _, report in ipairs(db.deaths or {}) do
        if type(report) == "table" and report.confidence == "sim" and not report.demo then
            removed.deaths = removed.deaths + 1
        else
            kept[#kept + 1] = report
        end
    end
    db.deaths = kept
    for id, record in pairs(db.justice or {}) do
        if type(record) == "table" and record.how == "sim" then
            db.justice[id] = nil
            removed.catches = removed.catches + 1
        end
    end
    ns.Wanted:RequestRecompute()
    return removed
end

-- /hh sim event ongoing|upcoming|clear (HeadHunter_Dev only): a made-up event of our
-- faction and level on the Events tab, being played now or starting later. Kept in
-- memory only; a /reload or clear takes it away.
Simulator.EVENT_PLAYERS = { "Testone", "Testtwo", "Testthree", "Testfour" }
Simulator.EVENT_LATER = 2 * 3600   -- an upcoming one starts this many seconds from now
Simulator.EVENT_STARTED = 600      -- an ongoing one started this many seconds ago
Simulator.EVENT_LOCK = 3600        -- locked this long before the start, as on the website
local testEvents = 0

function Simulator:Event(kind)
    if not ns.Dev.Present() then
        ns:Print(L.SIM_EVENT_NEEDS_DEV)
        return
    end
    if kind == "clear" then
        ns:Print(string.format(L.SIM_EVENT_CLEARED, ns.SiteData:ClearTestTournaments()))
    elseif kind == "ongoing" or kind == "upcoming" then
        local U = ns.Utils
        local now = U.ServerTime()
        local startsAt = kind == "ongoing" and now - self.EVENT_STARTED or now + self.EVENT_LATER
        local level = U.UnitLevel("player") or 1
        local realm = U.PlayerRealm()
        local players = {}
        for i, name in ipairs(self.EVENT_PLAYERS) do
            players[i] = { entrant = "p" .. i, name = name, realm = realm }
        end
        testEvents = testEvents + 1
        local t = ns.SiteData:AddTestTournament({
            id = "test-" .. testEvents, name = string.format(L.SIM_EVENT_NAME, testEvents), venue = "gurubashi",
            format = "1v1", best_of = 1, faction = false, min_level = level, max_level = level, places = 8,
            starts_at = startsAt, locks_at = startsAt - self.EVENT_LOCK, signups_closed = false,
            host = { name = U.UnitName("player"), realm = realm }, organizers = {}, players = players, teams = {},
        })
        if t then ns:Print(string.format(L.SIM_EVENT_ADDED, t.name, kind == "ongoing" and L.TAB_ONGOING or L.TAB_UPCOMING)) end
    else
        ns:Print(L.SIM_USAGE_EVENT)
        return
    end
    if ns.MainWindow and ns.MainWindow.Refresh then ns.MainWindow:Refresh() end
end

-- /hh sim duels [clear] (HH-134): test duel spots in our zone, to see the map mark, the
-- chat line and the invite clicks before a release. Only on our screen: never sent, and
-- the made-up HeadHunters get no whisper (Alerts/DuelSpots.lua).
function Simulator:Duels(kind)
    if kind == "clear" then
        ns:Print(string.format(L.SIM_DUELS_CLEARED, ns.DuelSpots:ClearSim()))
        return
    end
    local zone, others = ns.DuelSpots:Simulate()
    if not zone then
        ns:Print(others == "layer" and L.SIM_DUELS_NO_LAYER or L.SIM_DUELS_NO_ZONE)
        return
    end
    ns:Print(string.format(L.SIM_DUELS, ns.Utils.MapName(zone) or L.UNKNOWN_ZONE, others[1], others[2]))
end

ns.SlashCommands:Register("sim", function(args)
    local kind = table.remove(args, 1)
    kind = kind and kind:lower()
    if kind == "send" then
        Simulator:Send(args)
        return
    end
    if kind == "clear" then
        local removed = Simulator:Clear()
        if removed then
            ns:Print(string.format(L.SIM_CLEARED, removed.reports, removed.deaths, removed.catches))
        end
        return
    end
    if kind == "demo" then
        if args[1] and args[1]:lower() == "clear" then ns.Demo:Clear() else ns.Demo:Run() end
        return
    end
    if kind == "event" then
        Simulator:Event(args[1] and args[1]:lower())
        return
    end
    if kind == "duels" then
        Simulator:Duels(args[1] and args[1]:lower())
        return
    end
    if kind ~= "death" and kind ~= "sighting" then
        print(L.SIM_USAGE_DEATH)
        print(L.SIM_USAGE_SIGHTING)
        print(L.SIM_USAGE_DEMO)
        print(L.SIM_USAGE_CLEAR)
        print(L.SIM_USAGE_DUELS)
        if ns.Dev.Present() then print(L.SIM_USAGE_EVENT) end
        return
    end
    local enemy, err = Simulator:ParseEnemy(args)
    if not enemy then
        ns:Print(err or (kind == "death" and L.SIM_USAGE_DEATH or L.SIM_USAGE_SIGHTING))
        return
    end
    if kind == "death" then
        local report = Simulator:BuildDeathReport(enemy)
        ns:Debug("sim death report", report.id)
        ns.Events:Fire("HH_DEATH_REPORT", report, "sim")
        ns:Print(string.format(L.SIM_DEATH, enemy.key, Describe(enemy)))
    else
        ns:Debug("sim sighting", enemy.key)
        ns.Events:Fire("HH_ENEMY_SEEN", enemy, "sim")
        ns:Print(string.format(L.SIM_SIGHTING, enemy.key, Describe(enemy)))
    end
end, L.HELP_SIM)
