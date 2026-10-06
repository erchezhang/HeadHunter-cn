-- HH-082: data from the website, written by the desktop sync app into the separate
-- addon HeadHunter_Data (Data.lua sets HeadHunter_SiteData; listed as OptionalDeps, so
-- it loads before us). The game loads it as addon code, so it also works on WoW
-- Forever, where saved variables are not loaded back.
--
-- The file keeps the website's names (the /api/v1/sync/download answer):
--   worlds["era|eu|Firemaw"] / ["forever|us|pvp"] = { generated_at, wanted = {...},
--     duels = { alliance = {...}, horde = {...} }, deadbeats = {...}, bullies = {...},
--     tournaments = {...} (WEB-080: the Tournaments tab and the organizer stars read them),
--     busted = { { name, realm, caught_at, map_id, hunter, killer_name, glasses } } (the catches),
--     barflies = { { name, realm, glasses, last_glass_at, title, position } } (the most glasses raised) }
--   forever_servers = { ["4620"] = "pve", ... }: WoW Forever server numbers and their realm type
--   characters = { { world, name, deaths, duels, catches, bounty = { total, events } } }
-- This module picks our world, maps names to the addon's (player keys, "ROGUE",
-- "Scourge", "mostwanted") and:
--   * gives Wanted and HighNoon the website's lists to merge with what we saw
--     (Rules/Wanted.lua MergeSite, Rules/HighNoon.lua Merge)
--   * restores our own deaths, duels, catches and bounty events at login, marked
--     origin "website" so the sync app never uploads them again
--   * tells us at login when we are on the website's WANTED list ourselves: the other
--     faction's reports never reach our addon, so this is the only way to learn it
--
--   SiteData:Wanted() -> id -> WANTED entry     SiteData:Duelists() -> key -> player
--   SiteData:Bullies() -> id -> Hall of Shame entry (Rules/Wanted.lua MergeBullies)
--   SiteData:GeneratedAt()                      nil when there is no data for our world

local addonName, ns = ...

local SiteData = ns:RegisterModule("SiteData", {})

local OWNER = "SiteData"

SiteData.FORMAT_VERSION = 1
SiteData.ORIGIN = "website"

local RACES = {
    human = "Human", dwarf = "Dwarf", night_elf = "NightElf", gnome = "Gnome", draenei = "Draenei",
    orc = "Orc", undead = "Scourge", tauren = "Tauren", troll = "Troll", blood_elf = "BloodElf",
    skyborne = "Skyborne",
}
local FACTIONS = { alliance = "Alliance", horde = "Horde" }

local world, wanted, duelists, deadbeats, bullies, tournaments, busted, glasses

-------------------------------------------------
-- Names
-------------------------------------------------

local function Number(value)
    return type(value) == "number" and value or nil
end

local function Text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

function SiteData.Class(class)
    return Text(class) and class:upper() or nil
end

function SiteData.Race(race)
    return Text(race) and RACES[race] or nil
end

function SiteData.Faction(faction)
    return Text(faction) and FACTIONS[faction] or nil
end

-- "most_wanted" -> "mostwanted", "serial_killer" -> "serialkiller"
function SiteData.Token(value)
    return Text(value) and (value:gsub("_", "")) or nil
end

-- { name, realm } -> the addon's player key
function SiteData.Key(person)
    if type(person) ~= "table" then return nil end
    return ns.Utils.PlayerKey(Text(person.name), Text(person.realm))
end

-------------------------------------------------
-- Our world
-------------------------------------------------

local function Split(key)
    return key:match("^([^|]+)|([^|]+)|(.+)$")
end

-- WoW Forever (author, 2026-09-29): every realm has the same name, so the website lists
-- server numbers with their realm type ("4620" = "pve"). Our realm type, or nil when the
-- file has no list or does not know our server yet (then any Forever world counts).
local function ForeverRealmType(data)
    if not ns.Features.RealmlessNames then return nil end
    local servers = type(data) == "table" and data.forever_servers
    local server = ns.Utils.PlayerServer()
    if type(servers) ~= "table" or not server then return nil end
    return Text(servers[tostring(server)]) or Text(servers[server])
end

-- Ours: same client and region (when known) and, on Era, the same realm; on Forever
-- the realm type of our server when the website knows it
local function IsOurWorld(key, realmType)
    if type(key) ~= "string" then return false end
    local client, region, place = Split(key)
    if client ~= ns.Expansion.ClientKey then return false end
    local myRegion = (ns.db and ns.db.meta.region) or ns.Utils.Region()
    if myRegion and region ~= myRegion then return false end
    if ns.Features.RealmlessNames then return realmType == nil or place == realmType end
    local realm = ns.Utils.PlayerRealm()
    return realm ~= nil and place:gsub("%s", ""):lower() == realm:gsub("%s", ""):lower()
end

-- The first matching world, by key, so the choice does not depend on table order
local function FindWorld(data)
    if type(data.worlds) ~= "table" then return nil end
    local realmType = ForeverRealmType(data)
    if ns.Features.RealmlessNames and not realmType then
        ns:Debug("Website data: our Forever server", tostring(ns.Utils.PlayerServer()), "is not on its list yet")
    end
    local keys = {}
    for key in pairs(data.worlds) do
        if IsOurWorld(key, realmType) and type(data.worlds[key]) == "table" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys[1] and data.worlds[keys[1]]
end

local function Data()
    local data = _G.HeadHunter_SiteData
    if type(data) ~= "table" or data.format_version ~= SiteData.FORMAT_VERSION then return nil end
    return data
end

-------------------------------------------------
-- Lists
-------------------------------------------------

function SiteData.WantedEntry(w)
    local key = SiteData.Key(w)
    local rank = SiteData.Token(w.rank)
    local wantedUntil = Number(w.wanted_until)
    if not key or not rank or not ns.RulesEngine.RANK_ORDER[rank] or not wantedUntil then return nil end
    local badges = {}
    for _, badge in ipairs(type(w.badges) == "table" and w.badges or {}) do
        if Text(badge) then badges[SiteData.Token(badge)] = true end
    end
    local kills = Number(w.kills) or 0
    local lastKillAt = Number(w.last_kill_at)
    return {
        id = key, key = key, name = key,
        level = Number(w.level), class = SiteData.Class(w.class), race = SiteData.Race(w.race), sex = Number(w.sex),
        wanted = true, rank = rank, peakRank = rank, kills = kills,
        wantedSince = Number(w.wanted_since), wantedUntil = wantedUntil,
        timesWanted = Number(w.times_wanted) or 1, timesCaught = Number(w.times_caught) or 0,
        killCount = Number(w.kill_count) or math.floor(kills), cowardKills = Number(w.coward_kills) or 0,
        badges = badges,
        lastKill = lastKillAt and { t = lastKillAt, mapID = Number(w.last_map_id) } or nil,
        source = SiteData.ORIGIN,
    }
end

-- A Hall of Shame bully from the website: an entry that is not WANTED, with the bully badge
function SiteData.BullyEntry(b)
    local key = SiteData.Key(b)
    local cowardKills = Number(b.coward_kills)
    if not key or not cowardKills or cowardKills < 1 then return nil end
    local lastKillAt = Number(b.last_kill_at)
    return {
        id = key, key = key, name = key,
        level = Number(b.level), class = SiteData.Class(b.class), race = SiteData.Race(b.race), sex = Number(b.sex),
        wanted = false, kills = 0, timesWanted = 0, timesCaught = 0,
        killCount = Number(b.kill_count) or cowardKills, cowardKills = cowardKills,
        badges = { coward = true },
        lastKill = lastKillAt and { t = lastKillAt } or nil,
        source = SiteData.ORIGIN,
    }
end

function SiteData.Duelist(d, faction)
    local key = SiteData.Key(d)
    local wins, losses = Number(d.wins), Number(d.losses)
    if not key or not wins or not losses then return nil end
    return {
        key = key, faction = faction,
        class = SiteData.Class(d.class), race = SiteData.Race(d.race), sex = Number(d.sex),
        wins = wins, losses = losses, duels = Number(d.duels) or (wins + losses),
        lastT = Number(d.last_duel_at),
        source = SiteData.ORIGIN,
    }
end

-- A tournament from the website (WEB-080): tournaments are made and joined only there
-- (Tournament/Tournaments.lua lists them, Tournament/Organizers.lua marks their hosts)
-- { id, name, venue, teamSize, bestOf, finalBestOf, thirdPlace, bracketSeed, faction,
--   minLevel, maxLevel, places, entrants (count), drawn (entrant ids), people, results,
--   joined (keys of every signed-up character),
--   url, startsAt, days, locksAt, signupsClosed, finished, ended, host = key,
--   hostInfo = { class, race, sex, faction }, organizers = { key ... } }
function SiteData.Tournament(t)
    local id, startsAt = Text(t.id), Number(t.starts_at)
    if not id or not startsAt then return nil end
    local organizers = {}
    for _, person in ipairs(type(t.organizers) == "table" and t.organizers or {}) do
        local key = SiteData.Key(person)
        if key then organizers[#organizers + 1] = key end
    end
    -- Every day's start, day 1 first: a tournament may run over several days (author, 2026-09-30)
    local days = { startsAt }
    for _, day in ipairs(type(t.days) == "table" and t.days or {}) do
        if Number(day) and Number(day) > days[#days] then days[#days + 1] = Number(day) end
    end
    local teamSize = tonumber((Text(t.format) or "1v1"):match("^(%d)v")) or 1
    local places = Number(t.places)
    -- Who is drawn, as the website draws them (TournamentBracketService::entrants): the
    -- players with a place, or the full teams among those with a place, in sign-up
    -- order (author, 2026-10-01). people: entrant id -> { name, key, class, team }
    local drawn, people = {}, {}
    local teams = type(t.teams) == "table" and #t.teams > 0
    for i, e in ipairs(teams and t.teams or (type(t.players) == "table" and t.players or {})) do
        local entrant = type(e) == "table" and Text(e.entrant)
        if entrant and (not places or i <= places) then
            if teams then
                if type(e.members) == "table" and #e.members >= teamSize then drawn[#drawn + 1] = entrant end
                people[entrant] = { name = Text(e.name) or entrant, team = true, faction = SiteData.Faction(e.faction) }
            else
                drawn[#drawn + 1] = entrant
                people[entrant] = { name = Text(e.name) or entrant, key = SiteData.Key(e), class = SiteData.Class(e.class),
                    race = SiteData.Race(e.race), sex = Number(e.sex), faction = SiteData.Faction(e.faction) }
            end
        end
    end
    local results = {}
    for _, r in ipairs(type(t.results) == "table" and t.results or {}) do
        if type(r) == "table" and Number(r.round) and Number(r.match) and Text(r.a) and Text(r.b) then
            results[#results + 1] = { round = r.round, match = r.match, a = r.a, b = r.b,
                winsA = Number(r.wins_a) or 0, winsB = Number(r.wins_b) or 0,
                forfeit = (r.forfeit == "a" or r.forfeit == "b") and r.forfeit or nil }
        end
    end
    -- Every signed-up character, with or without a place: the event view says Event link
    -- instead of Join event for them
    local joined = {}
    for _, e in ipairs(type(t.players) == "table" and t.players or {}) do
        joined[#joined + 1] = type(e) == "table" and SiteData.Key(e) or nil
    end
    for _, team in ipairs(type(t.teams) == "table" and t.teams or {}) do
        for _, member in ipairs(type(team) == "table" and type(team.members) == "table" and team.members or {}) do
            joined[#joined + 1] = type(member) == "table" and SiteData.Key(member) or nil
        end
    end
    -- Players, or teams in team formats
    local entrants = type(t.teams) == "table" and #t.teams > 0 and #t.teams
        or type(t.players) == "table" and #t.players or 0
    return {
        id = id, name = Text(t.name) or "?", venue = Text(t.venue) or "gurubashi",
        teamSize = teamSize,
        bestOf = Number(t.best_of) or 1, finalBestOf = Number(t.final_best_of),
        thirdPlace = t.third_place_match == true, bracketSeed = Number(t.bracket_seed) or 1,
        faction = Text(t.faction) and FACTIONS[t.faction] or nil,
        minLevel = Number(t.min_level), maxLevel = Number(t.max_level),
        places = places, entrants = entrants, drawn = drawn, people = people, results = results,
        joined = joined, url = Text(t.url),
        startsAt = startsAt, days = days, locksAt = Number(t.locks_at) or startsAt - 3600,
        signupsClosed = t.signups_closed == true,
        finished = t.finished == true, ended = t.ended == true,
        host = SiteData.Key(t.host), organizers = organizers,
        hostInfo = type(t.host) == "table" and { class = SiteData.Class(t.host.class), race = SiteData.Race(t.host.race),
            sex = Number(t.host.sex), faction = SiteData.Faction(t.host.faction) } or {},
    }
end

function SiteData:Load()
    world, wanted, duelists, deadbeats, bullies, tournaments, busted, glasses = nil, nil, nil, nil, nil, nil, nil, nil
    local data = Data()
    world = data and FindWorld(data)
    if not world then return false end
    wanted = {}
    for _, w in ipairs(type(world.wanted) == "table" and world.wanted or {}) do
        local entry = type(w) == "table" and SiteData.WantedEntry(w)
        if entry then wanted[entry.id] = entry end
    end
    duelists = {}
    for token, faction in pairs(FACTIONS) do
        local list = type(world.duels) == "table" and world.duels[token]
        for _, d in ipairs(type(list) == "table" and list or {}) do
            local player = type(d) == "table" and SiteData.Duelist(d, faction)
            if player then duelists[player.key] = player end
        end
    end
    -- HH-118: both factions' Deadbeats (Classic Era's addon messages do not cross factions)
    deadbeats = {}
    for _, d in ipairs(type(world.deadbeats) == "table" and world.deadbeats or {}) do
        local key = type(d) == "table" and SiteData.Key(d)
        local untilT = key and Number(d.blocked_until)
        if untilT then deadbeats[ns.Utils.CompactName(key)] = { key = key, unpaid = Number(d.unpaid) or 2, blockedUntil = untilT } end
    end
    -- Both factions' bullies with a kill in the last 30 days (author, 2026-09-28)
    bullies = {}
    for _, b in ipairs(type(world.bullies) == "table" and world.bullies or {}) do
        local entry = type(b) == "table" and SiteData.BullyEntry(b)
        if entry then bullies[entry.id] = entry end
    end
    -- WEB-080: the world's open tournaments
    tournaments = {}
    for _, t in ipairs(type(world.tournaments) == "table" and world.tournaments or {}) do
        local tournament = type(t) == "table" and SiteData.Tournament(t)
        if tournament then tournaments[#tournaments + 1] = tournament end
    end
    -- The world's catches, with who busted them and the glasses raised (UI Busted list)
    busted, glasses = {}, {}
    for _, b in ipairs(type(world.busted) == "table" and world.busted or {}) do
        local catch = type(b) == "table" and SiteData.Busted(b)
        if catch then
            busted[#busted + 1] = catch
            glasses[catch.outlaw .. ":" .. catch.t] = catch.glasses
        end
    end
    return true
end

local function Who(person)
    if type(person) ~= "table" then return nil end
    local race = SiteData.Race(person.race)
    return { class = SiteData.Class(person.class), race = race, sex = Number(person.sex),
        faction = SiteData.Faction(person.faction) or ns.Utils.RaceFaction(race) }
end

-- A catch from the website as the addon keeps one (Sync/Justice.lua): outlaw key and
-- time, where, who landed the blow (the reporting HeadHunter, with race and class), and
-- the glasses raised; or nil
function SiteData.Busted(b)
    local outlaw, t = SiteData.Key(b), Number(b.caught_at)
    if not outlaw or not t then return nil end
    local hunter = SiteData.Key(b.hunter)
    local killer = hunter or ns.Utils.PlayerKey(Text(b.killer_name))
    local catch = { id = outlaw .. ":" .. t, outlaw = outlaw, t = t, mapID = Number(b.map_id), hunter = hunter,
        killer = killer, outlawWho = Who(b), glasses = Number(b.glasses) or 0, origin = "website" }
    local who = hunter and Who(b.hunter)
    if who then ns.Justice.SetKillerWho(catch, who) end
    return catch
end

-- The website's catches of our world, newest first
function SiteData:BustedList()
    return busted or {}
end

-- Barflies (author, 2026-10-04): the players who raised the most glasses from the popup,
-- in the last 30 days, most first: { key, class, race, sex, faction, glasses, lastGlass,
-- title ("barfly", "regular", "saloon_legend"), position }
function SiteData:Barflies()
    local data = Data()
    local w = data and world
    local list = {}
    for i, b in ipairs(type(w) == "table" and type(w.barflies) == "table" and w.barflies or {}) do
        local key = type(b) == "table" and SiteData.Key(b)
        local glasses = key and Number(b.glasses)
        if glasses then
            local race = SiteData.Race(b.race)
            list[#list + 1] = { key = key, class = SiteData.Class(b.class), race = race, sex = Number(b.sex),
                faction = SiteData.Faction(b.faction) or ns.Utils.RaceFaction(race), glasses = glasses,
                lastGlass = Number(b.last_glass_at), title = Text(b.title), position = Number(b.position) or i }
        end
    end
    return list
end

-- The website's count of glasses raised to a catch, or nil
function SiteData:Glasses(outlaw, caughtAt)
    return glasses and outlaw and caughtAt and glasses[outlaw .. ":" .. caughtAt] or nil
end

-- A website page from the download's links ("tournaments", "create_tournament"), or nil
function SiteData:Link(name)
    local data = Data()
    local links = data and type(data.links) == "table" and data.links
    return links and Text(links[name]) or nil
end

-- The website's open tournaments of our world, soonest first
local testTournaments = {} -- /hh sim event (HeadHunter_Dev only): in memory, never saved or sent

function SiteData:Tournaments()
    if #testTournaments == 0 then return tournaments or {} end
    local list = {}
    for _, t in ipairs(tournaments or {}) do list[#list + 1] = t end
    for _, t in ipairs(testTournaments) do list[#list + 1] = t end
    return list
end

-- A made-up event in the website's format, for testing the Events tab in game
function SiteData:AddTestTournament(raw)
    local t = SiteData.Tournament(raw)
    if t then testTournaments[#testTournaments + 1] = t end
    return t
end

function SiteData:ClearTestTournaments()
    local count = #testTournaments
    testTournaments = {}
    return count
end

-- The website's Hall of Shame bullies: id -> entry
function SiteData:Bullies()
    return bullies or {}
end

-- The website's Deadbeat record for a player key: { key, unpaid, blockedUntil } or nil
function SiteData:Deadbeat(key)
    local id = key and ns.Utils.CompactName(key)
    return id and deadbeats and deadbeats[id] or nil
end

-- Every Deadbeat the website listed: compact name -> record
function SiteData:Deadbeats()
    return deadbeats or {}
end

function SiteData:GeneratedAt()
    return world and Number(world.generated_at)
end

function SiteData:Wanted()
    return wanted
end

function SiteData:Duelists()
    return duelists
end

-------------------------------------------------
-- Our own records
-------------------------------------------------

local function Enemy(attacker)
    local level = attacker.skull and -1 or Number(attacker.level)
    local key = SiteData.Key(attacker)
    if key then
        return { key = key, name = key, level = level, class = SiteData.Class(attacker.class),
            race = SiteData.Race(attacker.race), faction = SiteData.Faction(attacker.faction), sex = Number(attacker.sex) }
    end
    local guid = Text(attacker.guid)
    if not guid then return nil end
    return { guid = guid, name = Text(attacker.given_name), nameIncomplete = true, level = level,
        class = SiteData.Class(attacker.class), race = SiteData.Race(attacker.race), faction = SiteData.Faction(attacker.faction) }
end

function SiteData.Death(d, me)
    local t = Number(d.t)
    if not t or type(d.attackers) ~= "table" then return nil end
    local killer, assists = nil, {}
    for _, attacker in ipairs(d.attackers) do
        local enemy = type(attacker) == "table" and Enemy(attacker)
        if enemy then
            if attacker.role == "killer" and not killer then killer = enemy else assists[#assists + 1] = enemy end
        end
    end
    killer = killer or table.remove(assists, 1)
    if not killer then return nil end
    return {
        id = me .. ":" .. t, t = t,
        victim = { key = me, level = Number(d.victim_level), class = SiteData.Class(d.victim_class),
            race = SiteData.Race(d.victim_race) },
        killer = killer, assists = assists,
        mapID = Number(d.map_id), x = Number(d.x), y = Number(d.y), layer = Number(d.layer),
        confidence = Text(d.confidence) or "inferred", classification = Text(d.classification),
        origin = SiteData.ORIGIN,
    }
end

function SiteData.DuelRecord(d)
    local winner, loser = type(d.winner) == "table" and d.winner, type(d.loser) == "table" and d.loser
    local t = Number(d.t)
    if not winner or not loser or not t then return nil end
    return {
        winner = SiteData.Key(winner), loser = SiteData.Key(loser), t = t,
        mapID = Number(d.map_id), retreat = d.retreat == true or nil, faction = SiteData.Faction(d.faction),
        winnerClass = SiteData.Class(winner.class), winnerRace = SiteData.Race(winner.race),
        winnerSex = Number(winner.sex), winnerLevel = Number(d.winner_level),
        loserClass = SiteData.Class(loser.class), loserRace = SiteData.Race(loser.race),
        loserSex = Number(loser.sex), loserLevel = Number(d.loser_level),
    }
end

function SiteData.Catch(c, me)
    local outlaw, t = SiteData.Key(c.outlaw), Number(c.t)
    if not outlaw or not t then return nil end
    return { id = outlaw .. ":" .. t, outlaw = outlaw, t = t, mapID = Number(c.map_id),
        killer = Text(c.killer_name), hunter = me }
end

function SiteData.MarksEvent(e, me)
    local t, delta = Number(e.t), Number(e.bounty)
    if not t or not delta or not Text(e.type) then return nil end
    return { t = t, delta = delta, reason = e.type, outlaw = Text(e.outlaw_name), rank = SiteData.Token(e.outlaw_rank),
        total = Number(e.total_after), hunter = me, origin = SiteData.ORIGIN }
end

local function RestoreDeaths(list, me)
    local db, added = ns.db, 0
    for _, d in ipairs(list) do
        local report = type(d) == "table" and SiteData.Death(d, me)
        if report and not ns.DeathReports:Find(report.id) then
            db.deaths[#db.deaths + 1] = report
            added = added + 1
        end
    end
    if added > 0 then
        table.sort(db.deaths, function(a, b) return (a.t or 0) < (b.t or 0) end)
        ns.Database:Prune()
    end
    return added
end

local function RestoreMarks(bounty, me)
    ns.Marks:Total() -- the character we play owns marks.total
    local store = ns.db.marks
    local seen, added = {}, 0
    for _, event in ipairs(store.events) do
        seen[table.concat({ event.t or 0, event.reason or "", event.hunter or "" }, "|")] = true
    end
    for _, e in ipairs(type(bounty.events) == "table" and bounty.events or {}) do
        local event = type(e) == "table" and SiteData.MarksEvent(e, me)
        local id = event and table.concat({ event.t, event.reason, me }, "|")
        if event and not seen[id] then
            seen[id] = true
            store.events[#store.events + 1] = event
            added = added + 1
        end
    end
    if added > 0 then
        table.sort(store.events, function(a, b) return (a.t or 0) < (b.t or 0) end)
        ns.Marks.Trim(store)
    end
    -- Each character keeps its own total
    if Number(bounty.total) and ns.Marks:SetTotalOf(me, bounty.total) then added = added + 1 end
    return added
end

-- Returns how many records were added
function SiteData:Restore()
    local data = Data()
    if not (data and ns.db and type(data.characters) == "table") then return 0 end
    local realmType = ForeverRealmType(data)
    local added = 0
    for _, c in ipairs(data.characters) do
        local me
        if type(c) == "table" and IsOurWorld(c.world, realmType) then
            local _, _, place = Split(c.world)
            me = ns.Utils.PlayerKey(Text(c.name), not ns.Features.RealmlessNames and place or nil)
        end
        if me then
            added = added + RestoreDeaths(type(c.deaths) == "table" and c.deaths or {}, me)
            for _, d in ipairs(type(c.duels) == "table" and c.duels or {}) do
                local duel = type(d) == "table" and SiteData.DuelRecord(d)
                if duel and ns.Duels:Add(duel, SiteData.ORIGIN) then added = added + 1 end
            end
            for _, j in ipairs(type(c.catches) == "table" and c.catches or {}) do
                local record = type(j) == "table" and SiteData.Catch(j, me)
                if record and ns.Justice:Add(record, SiteData.ORIGIN) then added = added + 1 end
            end
            if type(c.bounty) == "table" then
                added = added + RestoreMarks(c.bounty, me)
            end
        end
    end
    if added > 0 then ns.Events:Fire("HH_MARKS_CHANGED", ns.db.marks.total) end
    return added
end

-- Our own entry in the website's WANTED list, while it runs
function SiteData:SelfWanted(now)
    local me = ns.Utils.UnitKey("player")
    if not me then return nil end
    now = now or ns.Utils.ServerTime()
    for _, entry in pairs(wanted or {}) do
        if ns.Utils.SameCharacter(entry.key, me) and entry.wantedUntil > now then return entry end
    end
    return nil
end

SiteData.SELF_WANTED_DELAY = 10  -- after login, once the chat is up

function SiteData:TellSelfWanted()
    local entry = self:SelfWanted()
    if not entry then return false end
    local L, U = ns.L, ns.Utils
    local enemies = U.UnitFaction("player") == "Horde" and "Alliance" or "Horde"
    local rank = ns.Wanted.RankName(entry.rank)
    local age = U.Ago(math.max(0, U.ServerTime() - (self:GeneratedAt() or U.ServerTime())))
    return ns.Alerts:Show({
        key = "self-wanted",
        throttle = 0,
        text = L.SELF_WANTED_CENTER,
        chat = string.format(L.SELF_WANTED, enemies, rank, math.floor(entry.kills or 0), age),
        sound = "soft",
    }) ~= false
end

ns.Events:Register("HH_INITIALIZED", function()
    SiteData:Load()
end, OWNER)

-- Our world's lists and our own records, into the current home's data
local function LoadAndRestore()
    SiteData:Load()
    local added = SiteData:Restore()
    if added > 0 then ns:Debug("Website data restored", added, "records") end
    ns.Wanted:RequestRecompute()
    ns.HighNoon:RequestRecompute()
end

-- Our character is known at login
ns.Events:Register("PLAYER_LOGIN", function()
    if not ns.db then return end
    LoadAndRestore()
    C_Timer.After(SiteData.SELF_WANTED_DELAY, function() SiteData:TellSelfWanted() end)
end, OWNER)

-- The realm became known after the load (Core/Database.lua ConfirmHome)
ns.Events:Register("HH_HOME_CHANGED", LoadAndRestore, OWNER)
