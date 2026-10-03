-- /hh sim demo: fills every tab with a made-up but believable story, for screenshots.
-- /hh sim demo clear: takes it all out again and puts back the bounty we had.
--
-- Classic Era only (names are "Name-Realm", on our own realm). A busy realm: outlaws
-- of both factions (the Horde side uses the author's player names), each hunting the
-- other faction. Everything stays on this computer: reports, duels and catches go
-- into the saved data marked demo = true, and nothing is sent to other HeadHunters.
--
--   WANTED         20 outlaws, both factions, every rank from Ganker to Dead or Alive
--   Hall of Shame  14 cowards, some caught or never WANTED
--   Duels          a list per faction (us too, from level 55), with a Top Gun each
--   My deaths      our own deaths to the other faction's worst
--   My bounty      a hunter's history up to Headhunter

local addonName, ns = ...
local L = ns.L

local Demo = ns:RegisterModule("Demo", {})

local MINUTE, HOUR = 60, 3600

-- name, class, race token, sex (2 male, 3 female)
Demo.ROSTERS = {
    Horde = {
        { "Moomao", "WARRIOR", "Tauren", 2 },
        { "Intacto", "MAGE", "Scourge", 2 },
        { "Hyperstorm", "SHAMAN", "Orc", 2 },
        { "Molt", "WARRIOR", "Orc", 2 },
        { "Vieta", "PRIEST", "Scourge", 3 },
        { "Jinzz", "PRIEST", "Scourge", 3 },
        { "Qurdi", "ROGUE", "Scourge", 2 },
        { "Monaspa", "WARLOCK", "Scourge", 2 },
        { "Hakkaki", "WARRIOR", "Scourge", 2 },
        { "Aldex", "MAGE", "Scourge", 2 },
        { "Zulgar", "HUNTER", "Troll", 2 },
        { "Brakka", "HUNTER", "Orc", 3 },
        { "Tenzhi", "SHAMAN", "Troll", 3 },
        { "Grimhoof", "DRUID", "Tauren", 2 },
        { "Velka", "ROGUE", "Troll", 3 },
        { "Kargath", "WARLOCK", "Orc", 2 },
        { "Rokhan", "PRIEST", "Troll", 2 },
        { "Thundra", "SHAMAN", "Tauren", 3 },
    },
    Alliance = {
        { "Garrick", "WARRIOR", "Human", 2 },
        { "Kestrel", "ROGUE", "Human", 2 },
        { "Brightmane", "PALADIN", "Dwarf", 2 },
        { "Sylvaria", "HUNTER", "NightElf", 3 },
        { "Fizzwick", "MAGE", "Gnome", 2 },
        { "Morwenna", "WARLOCK", "Human", 3 },
        { "Thorgrim", "HUNTER", "Dwarf", 2 },
        { "Elowen", "DRUID", "NightElf", 3 },
        { "Aldric", "PALADIN", "Human", 2 },
        { "Duskblade", "ROGUE", "NightElf", 2 },
        { "Bramble", "WARLOCK", "Gnome", 3 },
        { "Lunara", "PRIEST", "NightElf", 3 },
        { "Ironvein", "WARRIOR", "Dwarf", 2 },
        { "Seraphine", "PALADIN", "Human", 3 },
        { "Tinkle", "ROGUE", "Gnome", 3 },
        { "Valeria", "PALADIN", "Human", 3 },
        { "Gimble", "WARLOCK", "Gnome", 2 },
        { "Hollis", "MAGE", "Human", 2 },
        { "Kaelen", "WARRIOR", "NightElf", 2 },
    },
}

-- One story per outlaw: kills, minutes since the last kill, minutes between kills, the
-- victims' level range, killer level (default 60), helpers, and a catch (minutes after
-- the last kill). All kills are at least 25 minutes old, so no live alert fires.
Demo.OUTLAWS = {
    -- Horde
    { name = "Moomao", kills = 52, endedAgo = 35, gap = 3, victims = { 22, 34 } },     -- Dead or Alive, Coward, Serial Killer
    { name = "Intacto", kills = 34, endedAgo = 50, gap = 4, victims = { 24, 40 } },    -- Most Wanted, Coward
    { name = "Hyperstorm", kills = 23, endedAgo = 90, gap = 5, victims = { 57, 60 } }, -- Desperado, Gunslinger
    { name = "Molt", kills = 14, endedAgo = 140, gap = 4, victims = { 30, 44 }, helpers = { "Hakkaki" } }, -- Outlaw pair, Duo
    { name = "Qurdi", kills = 9, endedAgo = 70, gap = 3, victims = { 25, 38 } },       -- Ganker, Coward, Serial Killer
    { name = "Monaspa", kills = 7, endedAgo = 200, gap = 5, victims = { 55, 60 }, helpers = { "Vieta", "Jinzz" } }, -- Gang
    { name = "Aldex", kills = 5, endedAgo = 260, gap = 5, victims = { 57, 60 }, level = 52 }, -- Giant Slayer
    { name = "Zulgar", kills = 3, endedAgo = 26 * 60, gap = 180, victims = { 20, 30 } }, -- Coward, never WANTED
    { name = "Brakka", kills = 8, endedAgo = 3 * 24 * 60, gap = 3, victims = { 25, 35 }, caught = 40 }, -- caught
    { name = "Grimhoof", kills = 2, endedAgo = 2 * 24 * 60, gap = 300, victims = { 18, 25 } }, -- Coward
    -- Alliance
    { name = "Garrick", kills = 41, endedAgo = 28, gap = 3, victims = { 20, 35 } },    -- Most Wanted, Coward, Serial Killer
    { name = "Kestrel", kills = 27, endedAgo = 45, gap = 4, victims = { 26, 40 } },    -- Desperado, Coward
    { name = "Brightmane", kills = 18, endedAgo = 100, gap = 5, victims = { 56, 60 } }, -- Outlaw, Gunslinger
    { name = "Sylvaria", kills = 11, endedAgo = 160, gap = 4, victims = { 57, 60 }, helpers = { "Thorgrim" } }, -- Duo
    { name = "Duskblade", kills = 6, endedAgo = 30, gap = 3, victims = { 30, 40 } },   -- Ganker, Coward, Serial Killer
    { name = "Morwenna", kills = 5, endedAgo = 220, gap = 5, victims = { 52, 58 }, helpers = { "Bramble", "Fizzwick" } }, -- Gang
    { name = "Aldric", kills = 5, endedAgo = 300, gap = 5, victims = { 55, 58 }, level = 50 }, -- Giant Slayer
    { name = "Tinkle", kills = 4, endedAgo = 20 * 60, gap = 300, victims = { 22, 32 } }, -- Coward, too slow for WANTED
    { name = "Ironvein", kills = 7, endedAgo = 4 * 24 * 60, gap = 3, victims = { 28, 38 }, caught = 25 }, -- caught
    { name = "Seraphine", kills = 3, endedAgo = 30 * 60, gap = 200, victims = { 24, 30 } }, -- Coward
}

-- The other faction's worst: our own deaths and our bounty hunts
Demo.NEMESES = {
    Horde = { "Moomao", "Intacto", "Molt", "Qurdi", "Hyperstorm" },
    Alliance = { "Garrick", "Kestrel", "Duskblade", "Brightmane", "Sylvaria" },
}

-- Our own deaths: nemesis index, minutes ago
Demo.MY_DEATHS = { { 1, 40 }, { 2, 60 }, { 3, 150 }, { 4, 80 }, { 5, 26 * 60 }, { 1, 30 * 60 } }

-- Bounty history, oldest first: reason, nemesis index, rank, hours ago
Demo.BOUNTY = {
    { "join", 4, "ganker", 76 }, { "catch", 4, "ganker", 73 }, { "join", 5, "ganker", 60 },
    { "catch", 5, "ganker", 59 }, { "decline", 3, "ganker", 50 }, { "join", 3, "outlaw", 40 },
    { "catch", 3, "outlaw", 30 }, { "join", 2, "desperado", 20 }, { "catch", 2, "desperado", 18 },
    { "join", 1, "mostwanted", 9 }, { "catch", 5, "mostwanted", 7 }, { "join", 4, "outlaw", 3 },
    { "join", 1, "deadoralive", 1 }, { "catch", 1, "deadoralive", 1 },
}

Demo.DUELS_PER_FACTION = 90
Demo.MAPS = { 1434, 1417, 1424, 1446, 1440, 1413, 1431, 1444 }

local function OtherFaction(faction)
    return faction == "Horde" and "Alliance" or "Horde"
end

-- name -> { roster row, faction }
local function Find(name)
    for faction, roster in pairs(Demo.ROSTERS) do
        for _, who in ipairs(roster) do
            if who[1] == name then return who, faction end
        end
    end
    return nil
end

local function Key(who)
    return ns.Utils.PlayerKey(who[1])
end

local function Enemy(who, level)
    local key = Key(who)
    return { key = key, name = key, level = level, class = who[2], race = who[3], sex = who[4] }
end

local function Between(range)
    return math.random(range[1], range[2])
end

local function Spot()
    return Demo.MAPS[math.random(#Demo.MAPS)], math.random(200, 800) / 1000, math.random(200, 800) / 1000
end

-------------------------------------------------
-- Building
-------------------------------------------------

local function AddOutlaws(now)
    local added = 0
    local nextVictim = { Horde = 0, Alliance = 0 }
    for _, story in ipairs(Demo.OUTLAWS) do
        local who, faction = Find(story.name)
        local victims = Demo.ROSTERS[OtherFaction(faction)]
        local attackers = { Enemy(who, story.level or 60) }
        for _, helper in ipairs(story.helpers or {}) do attackers[#attackers + 1] = Enemy(Find(helper), 60) end
        local assists = {}
        for a = 2, #attackers do assists[#assists + 1] = attackers[a] end
        local last = now - story.endedAgo * MINUTE
        for i = 1, story.kills do
            local index = nextVictim[faction] % #victims + 1
            nextVictim[faction] = index
            local victim = victims[index]
            local t = last - (story.kills - i) * story.gap * MINUTE
            local mapID, x, y = Spot()
            local report = {
                id = Key(victim) .. ":" .. t .. ":demo:" .. attackers[1].key,
                t = t,
                victim = { key = Key(victim), level = Between(story.victims), class = victim[2], race = victim[3] },
                killer = attackers[1],
                assists = assists,
                mapID = mapID, x = x, y = y,
                confidence = "sim",
                demo = true,
            }
            if ns.Reports:Add(report, "sim") then added = added + 1 end
        end
        if story.caught then
            local hunter = Key(victims[1])
            local t = last + story.caught * MINUTE
            ns.Justice:Add({ id = attackers[1].key .. ":" .. t, outlaw = attackers[1].key, t = t, mapID = Spot(),
                killer = hunter, hunter = hunter, how = "party", demo = true }, "sim")
        end
    end
    return added
end

local function AddMyDeaths(nemeses, now)
    local U = ns.Utils
    local me = {
        key = U.UnitKey("player"), level = U.UnitLevel("player"), class = U.UnitClass("player"),
        race = U.UnitRace("player"),
    }
    for _, death in ipairs(Demo.MY_DEATHS) do
        local who = Find(nemeses[death[1]])
        local t = now - death[2] * MINUTE
        local mapID, x, y = Spot()
        local report = {
            id = (me.key or "?") .. ":" .. t .. ":demo",
            t = t, victim = me, killer = Enemy(who, 60), assists = {},
            mapID = mapID, x = x, y = y, confidence = "exact", demo = true,
        }
        report.classification = ns.Classify.Report(report)
        table.insert(ns.db.deaths, report)
    end
    table.sort(ns.db.deaths, function(a, b) return (a.t or 0) < (b.t or 0) end)
end

-- A duel list for one faction: stronger players (earlier in the roster) win more often
local function AddDuels(faction, me, now)
    local players = {}
    for i, who in ipairs(Demo.ROSTERS[faction]) do
        players[#players + 1] = { key = Key(who), class = who[2], race = who[3], level = 60,
            strength = 0.9 - (i - 1) * 0.035 }
    end
    if me then players[#players + 1] = me end
    local added = 0
    for i = 1, Demo.DUELS_PER_FACTION do
        local a = players[math.random(#players)]
        local b = players[math.random(#players)]
        while b == a do b = players[math.random(#players)] end
        local winner, loser = a, b
        if math.random() >= a.strength / (a.strength + b.strength) then winner, loser = b, a end
        local duel = {
            winner = winner.key, loser = loser.key,
            t = now - (Demo.DUELS_PER_FACTION - i) * 2 * HOUR - math.random(0, 1800) - 30 * MINUTE,
            retreat = math.random() < 0.1 or nil,
            mapID = Spot(), faction = faction,
            winnerClass = winner.class, winnerRace = winner.race, winnerSex = winner.sex, winnerLevel = winner.level,
            loserClass = loser.class, loserRace = loser.race, loserSex = loser.sex, loserLevel = loser.level,
            demo = true,
        }
        if ns.Duels:Add(duel, "sim") then added = added + 1 end
    end

    -- A Top Gun needs +5 and a clear lead: the leader wins more until they have both
    local byKey = {}
    for _, p in ipairs(players) do byKey[p.key] = p end
    for extra = 1, 10 do
        local duels = {}
        for _, duel in ns.Duels:All() do
            if duel.faction == faction then duels[#duels + 1] = duel end
        end
        local list = {}
        for _, p in pairs(ns.HighNoon.Compute(duels)) do list[#list + 1] = p end
        table.sort(list, ns.HighNoon.Better)
        local clear = not (list[2] and ns.HighNoon.Tied(list[1], list[2]))
        if clear and list[1].net >= ns.HighNoon.TOP_GUN_NET then break end
        local winner, loser = byKey[list[1].key], byKey[list[#list].key]
        if not (winner and loser) then break end
        ns.Duels:Add({
            winner = winner.key, loser = loser.key, t = now - 20 * MINUTE + extra * 120,
            mapID = Spot(), faction = faction,
            winnerClass = winner.class, winnerRace = winner.race, winnerSex = winner.sex, winnerLevel = winner.level,
            loserClass = loser.class, loserRace = loser.race, loserSex = loser.sex, loserLevel = loser.level,
            demo = true,
        }, "sim")
        added = added + 1
    end
    return added
end

local function SetBounty(nemeses, now)
    local db = ns.db
    db.demoMarks = db.demoMarks or db.marks
    local total, events = 0, {}
    for _, row in ipairs(Demo.BOUNTY) do
        local reason, nemesis, rank, hoursAgo = row[1], row[2], row[3], row[4]
        local delta = reason == "join" and ns.Marks.JOIN or reason == "decline" and ns.Marks.DECLINE
            or ns.Marks.CATCH[rank]
        total = math.max(0, total + delta)
        events[#events + 1] = { t = now - hoursAgo * HOUR, delta = delta, reason = reason,
            outlaw = nemeses[nemesis], rank = rank, total = total }
    end
    db.marks = { total = total, events = events }
    ns.Events:Fire("HH_MARKS_CHANGED", total, events[#events])
    return #events
end

-------------------------------------------------
-- Commands
-------------------------------------------------

function Demo:Run()
    if not ns.db then return end
    if ns.Features.RealmlessNames then
        ns:Print(L.DEMO_ERA_ONLY)
        return
    end
    self:Clear(true)
    local U = ns.Utils
    local now = U.ServerTime()
    local faction = U.UnitFaction("player") == "Horde" and "Horde" or "Alliance"
    local nemeses = Demo.NEMESES[OtherFaction(faction)]

    local level = U.UnitLevel("player") or 0
    local me
    if level >= 55 then
        me = { key = U.UnitKey("player"), class = U.UnitClass("player"), race = U.UnitRace("player"),
            level = level, strength = 0.6 }
    end

    local kills = AddOutlaws(now)
    AddMyDeaths(nemeses, now)
    local duels = AddDuels(faction, me, now) + AddDuels(OtherFaction(faction), nil, now)
    local bounty = SetBounty(nemeses, now)
    ns:Print(string.format(L.DEMO_DONE, kills, duels, bounty))
end

-- quiet: no chat line (Run clears an earlier demo first)
function Demo:Clear(quiet)
    local db = ns.db
    if not db then return end
    local removed = 0
    for _, store in ipairs({ db.reports, db.duels, db.justice }) do
        for id, item in pairs(store or {}) do
            if type(item) == "table" and item.demo then
                store[id] = nil
                removed = removed + 1
            end
        end
    end
    local kept = {}
    for _, report in ipairs(db.deaths or {}) do
        if type(report) == "table" and report.demo then removed = removed + 1 else kept[#kept + 1] = report end
    end
    db.deaths = kept
    if db.demoMarks then
        db.marks = db.demoMarks
        db.demoMarks = nil
    end
    ns.Duels:Prune()
    ns.Wanted:RequestRecompute()
    ns.HighNoon:RequestRecompute()
    ns.Events:Fire("HH_MARKS_CHANGED", db.marks.total)
    if not quiet then ns:Print(string.format(L.DEMO_CLEARED, removed)) end
end
