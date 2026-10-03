-- HH-021: wire format. Pure string functions, no WoW API, offline-tested.
--
-- One addon message (<= 255 bytes) carries records of ONE type:
--   "1" <faction A|H> <type char> ":" record ( "~" record )*
-- Fields inside a record are separated by ";", sub-fields by ",".
-- Utils.PlayerKey rejects names containing ; , ~ | : so they never collide.
-- Numbers are base36. A version other than "1" is ignored (forward compatible).
--
-- Types (docs/addon/tickets.md, HH-021):
--   D  death report          (HH-022)
--   G  identity: GUID -> full key for a report killer/assist that was incomplete
--   Q  WANTED query          (HH-023, later)
--   S  WANTED snapshot chunk (HH-023, later)
--   J  posse join            (HH-044, later)
--   P  hotspot ping          (HH-045, later)

local addonName, ns = ...

local Protocol = ns:RegisterModule("Protocol", {})

Protocol.VERSION = "1"
Protocol.MAX_MESSAGE = 255
Protocol.MAX_ASSISTS = 4

Protocol.TYPES = {
    DEATH = "D", IDENTITY = "G", QUERY = "Q", SNAPSHOT = "S", POSSE = "J", HOTSPOT = "P",
    JUSTICE = "K", -- a WANTED outlaw killed by a HeadHunter or their group (HH-048)
    OFFER = "O",   -- catch-up: "I have N records for you" (HH-023)
    DUEL = "U",    -- High Noon: a duel someone saw (HH-091); also accepted from the other faction
    -- "V" was the in-game tournament (HH-101, removed 2026-09-30): not used again, as older
    -- addons may still send it
    PING = "T", -- /hh sync ping: manual connectivity test
    PRESENCE = "N", -- HH-110: "here" with our version, counts who is online; both factions
    HELP = "B",     -- HH-111: "help on the way" to a Battle hotspot
    SPOTTED = "L",  -- a watched outlaw spotted there (Alerts/Spotted.lua)
    MATCH = "M",    -- a tournament match: call, ready, game, result (Tournament/Matches.lua)
    POSTER = "W",   -- HH-118: a player's bounty poster on their killer
    PAYMENT = "R",  -- HH-118: a bounty claimed, paid or unpaid (sent by the hunter)
    WITNESS = "X",  -- HH-121: a hunted player died near the sender (Sync/Witness.lua)
}

local FACTION_CODE = { Alliance = "A", Horde = "H" }
local FACTION_NAME = { A = "Alliance", H = "Horde" }
Protocol.FACTION_CODE = FACTION_CODE

local CLASS_CODE = {
    WARRIOR = "W", PALADIN = "P", HUNTER = "H", ROGUE = "R", PRIEST = "I",
    SHAMAN = "S", MAGE = "M", WARLOCK = "L", DRUID = "D",
}
local RACE_CODE = {
    Human = "H", Dwarf = "D", NightElf = "N", Gnome = "G", Draenei = "E",
    Orc = "O", Scourge = "U", Tauren = "T", Troll = "R", BloodElf = "B",
}
-- "s": simulated death sent on purpose for two-character testing (/hh sim send)
local CONFIDENCE_CODE = { exact = "e", inferred = "i", sim = "s" }

local function Invert(t)
    local out = {}
    for k, v in pairs(t) do out[v] = k end
    return out
end
local CLASS_NAME, RACE_NAME, CONFIDENCE_NAME = Invert(CLASS_CODE), Invert(RACE_CODE), Invert(CONFIDENCE_CODE)

-- Skyborne (WoW Forever) is played by both factions, so its code tells the faction too
-- (author, 2026-09-29). Older clients do not know these codes and read no race.
Protocol.SKYBORNE = "Skyborne"
local SKYBORNE_CODE = { Alliance = "K", Horde = "Y" }
local SKYBORNE_UNKNOWN_FACTION = "Q"
local SKYBORNE_FACTION = Invert(SKYBORNE_CODE)

local function RaceCode(race, faction)
    if race == Protocol.SKYBORNE then return SKYBORNE_CODE[faction] or SKYBORNE_UNKNOWN_FACTION end
    return RACE_CODE[race] or ""
end

-- race, faction (the faction only when the code tells it)
local function RaceFromCode(code)
    if code == SKYBORNE_UNKNOWN_FACTION then return Protocol.SKYBORNE, nil end
    local faction = SKYBORNE_FACTION[code]
    if faction then return Protocol.SKYBORNE, faction end
    return RACE_NAME[code], nil
end

-------------------------------------------------
-- Primitives
-------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

function Protocol.ToB36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local out = {}
    while n > 0 do
        local d = n % 36
        table.insert(out, 1, DIGITS:sub(d + 1, d + 1))
        n = math.floor(n / 36)
    end
    return table.concat(out)
end

function Protocol.FromB36(s)
    if type(s) ~= "string" or s == "" or not s:match("^[0-9a-z]+$") or #s > 10 then return nil end
    return tonumber(s, 36)
end

-- Split keeping empty fields ("a;;b" -> {"a", "", "b"})
function Protocol.Split(s, sep)
    local out = {}
    local pos = 1
    while true do
        local i = s:find(sep, pos, true)
        if not i then
            out[#out + 1] = s:sub(pos)
            return out
        end
        out[#out + 1] = s:sub(pos, i - 1)
        pos = i + 1
    end
end
local Split = Protocol.Split

local function Blank(v)
    return v == nil or v == ""
end

-- Level: "" unknown, "s" skull, else base36
local function EncodeLevel(level)
    if level == -1 then return "s" end
    if not level then return "" end
    return Protocol.ToB36(level)
end

local function DecodeLevel(s)
    if s == "s" then return -1 end
    if Blank(s) then return nil end
    local level = Protocol.FromB36(s)
    if not level or level < 1 or level > 100 then return false end
    return level
end

-- Position 0..1 -> 0..999
local function EncodeCoord(v)
    if not v then return "" end
    return Protocol.ToB36(math.max(0, math.min(999, math.floor(v * 1000))))
end

local function DecodeCoord(s)
    if Blank(s) then return nil end
    local n = Protocol.FromB36(s)
    return n and n <= 999 and n / 1000 or nil
end

-------------------------------------------------
-- Enemy: key-or-name , incomplete , level , class , race , sex , guid
-- The GUID is only sent for incomplete (given-name-only) entries, which need it
-- to be completed later.
-------------------------------------------------

local function EncodeEnemy(enemy)
    local incomplete = enemy.nameIncomplete and not enemy.key
    return table.concat({
        enemy.key or enemy.name or "",
        incomplete and "1" or "",
        EncodeLevel(enemy.level),
        CLASS_CODE[enemy.class] or "",
        RaceCode(enemy.race, enemy.faction),
        (enemy.sex == 2 or enemy.sex == 3) and tostring(enemy.sex) or "",
        incomplete and (enemy.guid or "") or "",
    }, ",")
end

local function DecodeEnemy(s)
    local f = Split(s, ",")
    if #f ~= 7 or Blank(f[1]) then return nil end
    local level = DecodeLevel(f[3])
    if level == false then return nil end
    local race, faction = RaceFromCode(f[5])
    local enemy = {
        level = level,
        class = CLASS_NAME[f[4]],
        race = race,
        faction = faction,
        sex = tonumber(f[6]),
    }
    if f[2] == "1" then
        if Blank(f[7]) then return nil end
        enemy.name = f[1]
        enemy.nameIncomplete = true
        enemy.guid = f[7]
    else
        enemy.key = f[1]
        enemy.name = f[1]
    end
    return enemy
end

-------------------------------------------------
-- Death report:
--   t ; victimKey ; victimLevel ; victimClass ; victimRace ; mapID ; x ; y ;
--   confidence ; layer ; killer ; assist ; assist ... ; h<helpers>
-- The last field, "h" + our group members in the fight, is only sent when there were
-- any (0.1.9). Older clients read it as a broken assist and skip it.
-------------------------------------------------

local KILLER_FIELD = 11

local function HelpersField(report)
    local helpers = tonumber(report.helpers)
    if not helpers or helpers < 1 then return nil end
    return "h" .. Protocol.ToB36(math.min(math.floor(helpers), 39))
end

function Protocol.EncodeDeath(report, maxLength)
    maxLength = maxLength or (Protocol.MAX_MESSAGE - 4)
    local v = report.victim
    local fields = {
        Protocol.ToB36(report.t),
        v.key,
        EncodeLevel(v.level),
        CLASS_CODE[v.class] or "",
        RaceCode(v.race, v.faction),
        report.mapID and Protocol.ToB36(report.mapID) or "",
        EncodeCoord(report.x),
        EncodeCoord(report.y),
        CONFIDENCE_CODE[report.confidence] or "i",
        report.layer and Protocol.ToB36(report.layer) or "",
        EncodeEnemy(report.killer),
    }
    local helpers = HelpersField(report)
    local tail = helpers and (";" .. helpers) or ""
    local base = table.concat(fields, ";")
    if #base + #tail > maxLength then return nil end
    -- Assists are optional: add as many as fit
    local out = base
    for i = 1, math.min(#(report.assists or {}), Protocol.MAX_ASSISTS) do
        local candidate = out .. ";" .. EncodeEnemy(report.assists[i])
        if #candidate + #tail > maxLength then break end
        out = candidate
    end
    return out .. tail
end

-- Returns a report table, or nil for anything malformed
function Protocol.DecodeDeath(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    local helpers = #f > KILLER_FIELD and f[#f]:match("^h(%w+)$")
    if helpers then
        helpers = Protocol.FromB36(helpers)
        f[#f] = nil
    end
    if #f < KILLER_FIELD then return nil end
    local t = Protocol.FromB36(f[1])
    local victimLevel = DecodeLevel(f[3])
    if not t or Blank(f[2]) or not victimLevel or victimLevel == -1 then return nil end
    local killer = DecodeEnemy(f[KILLER_FIELD])
    if not killer then return nil end
    local report = {
        t = t,
        victim = { key = f[2], level = victimLevel, class = CLASS_NAME[f[4]], race = RaceFromCode(f[5]),
            faction = select(2, RaceFromCode(f[5])) },
        mapID = Protocol.FromB36(f[6]),
        x = DecodeCoord(f[7]),
        y = DecodeCoord(f[8]),
        confidence = CONFIDENCE_NAME[f[9]] or "inferred",
        layer = Protocol.FromB36(f[10]),
        helpers = helpers or nil,
        killer = killer,
        assists = {},
    }
    for i = KILLER_FIELD + 1, math.min(#f, KILLER_FIELD + Protocol.MAX_ASSISTS) do
        local assist = DecodeEnemy(f[i])
        if assist then report.assists[#report.assists + 1] = assist end
    end
    report.id = report.victim.key .. ":" .. t
    return report
end

-------------------------------------------------
-- Identity: reportId ; guid ; key ; level ; class ; race ; sex
-------------------------------------------------

function Protocol.EncodeIdentity(reportId, enemy)
    return table.concat({
        reportId, enemy.guid or "", enemy.key or "", EncodeLevel(enemy.level),
        CLASS_CODE[enemy.class] or "", RaceCode(enemy.race, enemy.faction),
        (enemy.sex == 2 or enemy.sex == 3) and tostring(enemy.sex) or "",
    }, ";")
end

function Protocol.DecodeIdentity(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if #f ~= 7 or Blank(f[1]) or Blank(f[2]) or Blank(f[3]) then return nil end
    local level = DecodeLevel(f[4])
    if level == false then return nil end
    return f[1], {
        guid = f[2], key = f[3], level = level,
        class = CLASS_NAME[f[5]], race = RaceFromCode(f[6]), faction = select(2, RaceFromCode(f[6])),
        sex = tonumber(f[7]),
    }
end

-------------------------------------------------
-- Posse join: outlawId ; mapID ; time ; layer ; hunterRank   (the sender is the member)
-- hunterRank: the member's HeadHunter rank (1 Tracker … 5 Reaper, HH-050); records
-- without it (4 fields) are still read.
-------------------------------------------------

function Protocol.EncodePosse(outlawId, mapID, t, layer, hunterRank)
    return table.concat({ outlawId, mapID and Protocol.ToB36(mapID) or "", Protocol.ToB36(t),
        layer and Protocol.ToB36(layer) or "", hunterRank and Protocol.ToB36(hunterRank) or "" }, ";")
end

-- Returns outlawId, mapID, time, layer, hunterRank
function Protocol.DecodePosse(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if (#f ~= 4 and #f ~= 5) or Blank(f[1]) then return nil end
    local t = Protocol.FromB36(f[3])
    if not t then return nil end
    return f[1], Protocol.FromB36(f[2]), t, Protocol.FromB36(f[4]), Protocol.FromB36(f[5])
end

-------------------------------------------------
-- Duel (High Noon, HH-091):
--   winner ; loser ; time ; mapID ; flags ("r" = retreat) ; faction (A/H) ;
--   winnerClass ; winnerRace ; loserClass ; loserRace   (codes, blank when unknown;
--   a lower-case race code is a female character) ;
--   winnerLevel ; loserLevel   (base 36)
-------------------------------------------------

local function Level(n)
    return n and n >= 1 and Protocol.ToB36(n) or ""
end

local function RaceSexCode(race, sex)
    local code = race and RaceCode(race)
    if code and sex == 3 then return code:lower() end
    return code or ""
end

-- race, sex (2 male, 3 female; nil when the code is blank or unknown)
local function RaceSexName(code)
    local race = RaceFromCode(code:upper())
    if not race then return nil, nil end
    return race, code == code:lower() and 3 or 2
end

function Protocol.EncodeDuel(duel)
    return table.concat({
        duel.winner, duel.loser, Protocol.ToB36(duel.t), duel.mapID and Protocol.ToB36(duel.mapID) or "",
        duel.retreat and "r" or "", FACTION_CODE[duel.faction] or "",
        CLASS_CODE[duel.winnerClass] or "", RaceSexCode(duel.winnerRace, duel.winnerSex),
        CLASS_CODE[duel.loserClass] or "", RaceSexCode(duel.loserRace, duel.loserSex),
        Level(duel.winnerLevel), Level(duel.loserLevel),
    }, ";")
end

-- Returns a duel table, or nil
function Protocol.DecodeDuel(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if #f ~= 12 or Blank(f[1]) or Blank(f[2]) then return nil end
    local t = Protocol.FromB36(f[3])
    if not t then return nil end
    local winnerRace, winnerSex = RaceSexName(f[8])
    local loserRace, loserSex = RaceSexName(f[10])
    return {
        winner = f[1], loser = f[2], t = t, mapID = Protocol.FromB36(f[4]), retreat = f[5] == "r" or nil,
        faction = FACTION_NAME[f[6]], winnerClass = CLASS_NAME[f[7]], winnerRace = winnerRace, winnerSex = winnerSex,
        loserClass = CLASS_NAME[f[9]], loserRace = loserRace, loserSex = loserSex,
        winnerLevel = Protocol.FromB36(f[11]), loserLevel = Protocol.FromB36(f[12]),
    }
end

-------------------------------------------------
-- Justice: outlawId ; time ; mapID ; killer (who landed the blow, display only).
-- The sender is the hunter who saw it (the killer or in their group).
-------------------------------------------------

function Protocol.EncodeJustice(outlawId, t, mapID, killer)
    return table.concat({ outlawId, Protocol.ToB36(t), mapID and Protocol.ToB36(mapID) or "", killer or "" }, ";")
end

-- Returns outlawId, time, mapID, killer (nil when blank)
function Protocol.DecodeJustice(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if #f ~= 4 or Blank(f[1]) then return nil end
    local t = Protocol.FromB36(f[2])
    if not t then return nil end
    return f[1], t, Protocol.FromB36(f[3]), not Blank(f[4]) and f[4] or nil
end

-------------------------------------------------
-- Poster (HH-118): owner ; target ; reason (1-4) ; gold (copper) ; until ; time
-- The sender is the owner. The target is an enemy id (a key, or "guid:..." for a
-- Forever killer known only by the given name).
-------------------------------------------------

function Protocol.EncodePoster(poster)
    return table.concat({ poster.owner, poster.target, Protocol.ToB36(poster.reason), Protocol.ToB36(poster.gold),
        Protocol.ToB36(poster["until"]), Protocol.ToB36(poster.t) }, ";")
end

-- Returns a poster table, or nil
function Protocol.DecodePoster(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if #f ~= 6 or Blank(f[1]) or Blank(f[2]) then return nil end
    local reason, gold = Protocol.FromB36(f[3]), Protocol.FromB36(f[4])
    local untilT, t = Protocol.FromB36(f[5]), Protocol.FromB36(f[6])
    if not (reason and gold and untilT and t) then return nil end
    return { owner = f[1], target = f[2], reason = reason, gold = gold, ["until"] = untilT, t = t }
end

-------------------------------------------------
-- Bounty payment (HH-118): posterId ; hunter ; status (c claimed, p paid, u unpaid) ;
-- claimedAt ; time. Sent only by the hunter (the one who receives the gold).
-------------------------------------------------

local PAY_CODE = { claimed = "c", paid = "p", unpaid = "u" }
local PAY_NAME = Invert(PAY_CODE)

function Protocol.EncodePayment(pay)
    return table.concat({ pay.posterId, pay.hunter, PAY_CODE[pay.status] or "c", Protocol.ToB36(pay.claimedAt),
        Protocol.ToB36(pay.t) }, ";")
end

-- Returns a payment table, or nil
function Protocol.DecodePayment(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if #f ~= 5 or Blank(f[1]) or Blank(f[2]) or not PAY_NAME[f[3]] then return nil end
    local claimedAt, t = Protocol.FromB36(f[4]), Protocol.FromB36(f[5])
    if not (claimedAt and t) then return nil end
    return { posterId = f[1], hunter = f[2], status = PAY_NAME[f[3]], claimedAt = claimedAt, t = t }
end

-------------------------------------------------
-- Hotspot ping: mapID ; time ; x ; y ; enemyIds (comma separated short ids)
--   [ ; names ; layer ]  (0.1.8+) names: up to MAX_PING_NAMES "name/classCode/level",
--   comma separated, so a Battle popup can say who is fighting; layer: ours, for
--   the [Help] invite whisper. Older clients accept only the first 5 fields.
-- The sender is the HeadHunter in PvP combat there.
-------------------------------------------------

Protocol.MAX_PING_ENEMIES = 12
Protocol.MAX_PING_NAMES = 3

-- enemies: optional list of { name, class, level }; layer: optional number
function Protocol.EncodeHotspot(mapID, t, x, y, enemyIds, enemies, layer)
    local ids = {}
    for i = 1, math.min(#enemyIds, Protocol.MAX_PING_ENEMIES) do
        local id = tostring(enemyIds[i]):gsub("[^%w]", "")
        ids[#ids + 1] = id
    end
    local fields = { Protocol.ToB36(mapID), Protocol.ToB36(t), EncodeCoord(x), EncodeCoord(y), table.concat(ids, ",") }
    if (enemies and #enemies > 0) or layer then
        local names = {}
        for i = 1, math.min(#(enemies or {}), Protocol.MAX_PING_NAMES) do
            local e = enemies[i]
            local name = tostring(e.name or ""):gsub("[;,~/|:%c]", "")
            if name ~= "" then
                local level = tonumber(e.level)
                names[#names + 1] = table.concat({ name, CLASS_CODE[e.class or ""] or "",
                    level and (level == -1 and "s" or tostring(level)) or "" }, "/")
            end
        end
        fields[6] = table.concat(names, ",")
        fields[7] = layer and Protocol.ToB36(layer) or ""
    end
    return table.concat(fields, ";")
end

-- Returns mapID, time, x, y, enemyIds, enemies ({ name, class, level }), layer
function Protocol.DecodeHotspot(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if #f ~= 5 and #f ~= 7 then return nil end
    local mapID, t = Protocol.FromB36(f[1]), Protocol.FromB36(f[2])
    if not mapID or not t then return nil end
    local ids = {}
    if f[5] ~= "" then
        for id in f[5]:gmatch("[^,]+") do
            if #ids < Protocol.MAX_PING_ENEMIES and id:match("^%w+$") then ids[#ids + 1] = id end
        end
    end
    local enemies, layer = {}, nil
    if #f == 7 then
        for part in (f[6] or ""):gmatch("[^,]+") do
            local name, class, level = part:match("^([^/]+)/(%u?)/(%w*)$")
            if name and #enemies < Protocol.MAX_PING_NAMES then
                enemies[#enemies + 1] = { name = name, class = CLASS_NAME[class],
                    level = level == "s" and -1 or tonumber(level) }
            end
        end
        layer = f[7] ~= "" and Protocol.FromB36(f[7]) or nil
    end
    return mapID, t, DecodeCoord(f[3]), DecodeCoord(f[4]), ids, enemies, layer
end

-------------------------------------------------
-- Help on the way (HH-111): mapID ; time. The sender clicked [Help] on a Battle
-- popup for that zone; players fighting there get a quiet note.
-------------------------------------------------

function Protocol.EncodeHelp(mapID, t)
    return Protocol.ToB36(mapID) .. ";" .. Protocol.ToB36(t)
end

function Protocol.DecodeHelp(s)
    if type(s) ~= "string" then return nil end
    local mapID, t = s:match("^(%w+);(%w+)$")
    return mapID and Protocol.FromB36(mapID), t and Protocol.FromB36(t)
end

-------------------------------------------------
-- Spotted (author, 2026-10-01): outlawId ; mapID ; time ; x ; y. The sender saw a
-- watched outlaw (WANTED, at large, or with a player's bounty) there.
-------------------------------------------------

function Protocol.EncodeSpotted(outlawId, mapID, t, x, y)
    return table.concat({ outlawId, Protocol.ToB36(mapID), Protocol.ToB36(t), EncodeCoord(x), EncodeCoord(y) }, ";")
end

-- Returns outlawId, mapID, time, x, y
function Protocol.DecodeSpotted(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if #f ~= 5 or Blank(f[1]) then return nil end
    local mapID, t = Protocol.FromB36(f[2]), Protocol.FromB36(f[3])
    if not mapID or not t then return nil end
    return f[1], mapID, t, DecodeCoord(f[4]), DecodeCoord(f[5])
end

-------------------------------------------------
-- Witness (HH-121): outlaw ; mapID ; t ; x ; y ; killer ; by
-- A hunted player died near `by`; killer is empty when the witness could not tell
-- (WoW Forever has no combat log). Numbers base 36, coordinates 0..999.
-------------------------------------------------

function Protocol.EncodeWitness(w)
    return table.concat({ w.outlaw, Protocol.ToB36(w.mapID), Protocol.ToB36(w.t), EncodeCoord(w.x), EncodeCoord(w.y),
        w.killer or "", w.by }, ";")
end

-- Returns { outlaw, mapID, t, x, y, killer, by } or nil
function Protocol.DecodeWitness(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    if #f ~= 7 or Blank(f[1]) or Blank(f[7]) then return nil end
    local mapID, t = Protocol.FromB36(f[2]), Protocol.FromB36(f[3])
    if not mapID or not t then return nil end
    return { outlaw = f[1], mapID = mapID, t = t, x = DecodeCoord(f[4]), y = DecodeCoord(f[5]),
        killer = not Blank(f[6]) and f[6] or nil, by = f[7] }
end

-------------------------------------------------
-- Tournament match (author, 2026-10-01): kind ; tournament ; round ; match ; ...
--   C ;tid;round;match;readyBy      D ;tid;round;match      R ;tid;round;match
--   G ;tid;round;match;winnerKey;t
--   F ;tid;round;match;a;b;winsA;winsB;forfeit;t
-- Numbers base 36; names and ids as they are (no separators in them).
-------------------------------------------------

local MATCH_FIELDS = { C = 5, D = 4, R = 4, G = 6, F = 10 }

function Protocol.EncodeMatch(kind, tid, round, match, ...)
    local fields = { kind, tid, Protocol.ToB36(round), Protocol.ToB36(match) }
    for _, v in ipairs({ ... }) do
        fields[#fields + 1] = type(v) == "number" and Protocol.ToB36(v) or tostring(v or "")
    end
    return table.concat(fields, ";")
end

-- Returns kind, tid, round, match, and the kind's other fields as strings
function Protocol.DecodeMatch(s)
    if type(s) ~= "string" then return nil end
    local f = Split(s, ";")
    local kind = f[1]
    if not MATCH_FIELDS[kind] or #f ~= MATCH_FIELDS[kind] or Blank(f[2]) then return nil end
    local round, match = Protocol.FromB36(f[3]), Protocol.FromB36(f[4])
    if not round or not match then return nil end
    return kind, f[2], round, match, select(5, unpack(f))
end

-------------------------------------------------
-- Messages
-------------------------------------------------

function Protocol.Header(factionCode, typeCode)
    return Protocol.VERSION .. factionCode .. typeCode .. ":"
end

-- Pack records into as few messages as possible, in order. Returns the messages
-- and, per message, how many input records it consumed (so a caller that can only
-- send some of the messages knows how many records went out). A record that cannot
-- fit even alone is consumed without being sent (callers keep records far below
-- the limit).
-- maxLength defaults to MAX_MESSAGE (channel chat text passes less: its marker
-- takes room).
function Protocol.Pack(factionCode, typeCode, records, maxLength)
    maxLength = maxLength or Protocol.MAX_MESSAGE
    local header = Protocol.Header(factionCode, typeCode)
    local messages, consumed = {}, {}
    local current, count = nil, 0
    for _, record in ipairs(records) do
        if #header + #record > maxLength then
            count = count + 1
        elseif current and #current + 1 + #record <= maxLength then
            current = current .. "~" .. record
            count = count + 1
        else
            if current then
                messages[#messages + 1], consumed[#consumed + 1] = current, count
                count = 0
            end
            current = header .. record
            count = count + 1
        end
    end
    if current then
        messages[#messages + 1], consumed[#consumed + 1] = current, count
    elseif count > 0 and #consumed > 0 then
        consumed[#consumed] = consumed[#consumed] + count
    end
    return messages, consumed
end

-- Returns faction name, type code, records; or nil for anything we do not speak
function Protocol.Unpack(message)
    if type(message) ~= "string" or #message > Protocol.MAX_MESSAGE then return nil end
    local version, factionCode, typeCode, body = message:match("^(%d)([AH])(%u):(.*)$")
    if version ~= Protocol.VERSION or not body or body == "" then return nil end
    return FACTION_NAME[factionCode], typeCode, Split(body, "~")
end
