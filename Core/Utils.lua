local addonName, ns = ...

local Utils = ns:RegisterModule("Utils", {})

-------------------------------------------------
-- Safe access
--
-- Every unit API goes through these. On the 12.x engine (Forever) a call can raise,
-- or return a "secret value" that may be held but not compared, indexed or matched.
-- Both are treated as "unknown" (nil) so callers never error mid-combat.
-- Globals are looked up at call time so tests can stub them.
-------------------------------------------------

function Utils.Accessible(value)
    if value == nil then return nil end
    local canaccess = _G.canaccessvalue
    if canaccess and not canaccess(value) then return nil end
    local issecret = _G.issecretvalue
    if issecret and issecret(value) then return nil end
    return value
end
local Accessible = Utils.Accessible

local function PassIfOk(ok, ...)
    if not ok then return nil end
    return ...
end

function Utils.SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    return PassIfOk(pcall(fn, ...))
end
local SafeCall = Utils.SafeCall

function Utils.AccessibleString(value)
    value = Accessible(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end
local AccessibleString = Utils.AccessibleString

-------------------------------------------------
-- Unit API wrappers
-------------------------------------------------

function Utils.UnitName(unit)
    local name, realm = SafeCall(_G.UnitName, unit)
    return AccessibleString(name), AccessibleString(realm)
end

-- -1 means skull (10+ levels above the player). nil means unknown.
function Utils.UnitLevel(unit)
    local level = tonumber(Accessible(SafeCall(_G.UnitLevel, unit)))
    if not level then return nil end
    level = math.floor(level)
    if level == -1 or (level >= 1 and level <= 100) then
        return level
    end
    return nil
end

-- Locale-independent class token, e.g. "ROGUE"
function Utils.UnitClass(unit)
    local _, classFile = SafeCall(_G.UnitClass, unit)
    return AccessibleString(classFile)
end

-- Locale-independent race token, e.g. "Scourge", "NightElf"
function Utils.UnitRace(unit)
    local _, raceFile = SafeCall(_G.UnitRace, unit)
    return AccessibleString(raceFile)
end

-- 1 = unknown, 2 = male, 3 = female
function Utils.UnitSex(unit)
    local sex = tonumber(Accessible(SafeCall(_G.UnitSex, unit)))
    if sex == 2 or sex == 3 then return sex end
    return 1
end

function Utils.UnitGUID(unit)
    return AccessibleString(SafeCall(_G.UnitGUID, unit))
end

-- A player GUID is "Player-<server number>-<id>"
Utils.PLAYER_GUID_SERVER = "^Player%-(%d+)%-"

-- The server number of a player GUID ("Player-4620-011810AD" -> 4620). On WoW Forever
-- the realm name is the same everywhere, so this is how realms are told apart.
function Utils.GUIDServer(guid)
    return type(guid) == "string" and tonumber(guid:match(Utils.PLAYER_GUID_SERVER)) or nil
end

function Utils.PlayerServer()
    return Utils.GUIDServer(Utils.UnitGUID("player"))
end

-- Home keys: where saved data belongs (Core/Database.lua), "forever|4620" or "era|firemaw"
Utils.HOME_FOREVER = "forever"
Utils.HOME_ERA = "era"
Utils.HOME_SEPARATOR = "|"

function Utils.ForeverHome(server)
    return Utils.HOME_FOREVER .. Utils.HOME_SEPARATOR .. server
end

function Utils.EraHome(realm)
    return Utils.HOME_ERA .. Utils.HOME_SEPARATOR .. (realm:gsub("%s", ""):lower())
end

-- Our home, or nil while the game does not tell our server or realm yet
function Utils.HomeKey()
    if ns.Features.RealmlessNames then
        local server = Utils.PlayerServer()
        return server and Utils.ForeverHome(server) or nil
    end
    local realm = Utils.PlayerRealm()
    return realm and Utils.EraHome(realm) or nil
end

-- "Alliance" / "Horde"
function Utils.UnitFaction(unit)
    return AccessibleString((SafeCall(_G.UnitFactionGroup, unit)))
end

function Utils.UnitGuild(unit)
    return AccessibleString((SafeCall(_G.GetGuildInfo, unit)))
end

function Utils.UnitIsPlayer(unit)
    return Accessible(SafeCall(_G.UnitIsPlayer, unit)) == true
end

-- A player of the opposing faction. Same-faction hostility only exists in duels,
-- which HeadHunter never counts.
function Utils.UnitIsEnemyPlayer(unit)
    if not Utils.UnitIsPlayer(unit) then return false end
    local theirs = Utils.UnitFaction(unit)
    local mine = Utils.UnitFaction("player")
    return theirs ~= nil and mine ~= nil and theirs ~= mine
end

-- Races are faction-locked in Classic, so the race token tells the faction of a
-- player known only by GUID. Needed because the combat log and Death Recap flag a
-- DUEL opponent as hostile exactly like an enemy player.
local RACE_FACTION = {
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
    Draenei = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde", BloodElf = "Horde",
}

function Utils.RaceFaction(raceFile)
    return raceFile and RACE_FACTION[raceFile]
end

-- True only when the GUID is known to be a player of our own faction.
-- Unknown race or faction -> false (trust the hostility flags).
function Utils.IsSameFactionGUID(guid)
    if not guid then return false end
    local _, _, _, raceFile = SafeCall(_G.GetPlayerInfoByGUID, guid)
    local theirs = Utils.RaceFaction(AccessibleString(raceFile))
    local mine = Utils.UnitFaction("player")
    return theirs ~= nil and theirs == mine
end

-------------------------------------------------
-- Player identity
--
-- A player key is the stable identity used everywhere (DB, sync, rules):
--   Era:     "Name-Realm"      (realm normalised, no spaces)
--   Forever: "Given Family"    (realmless; an API "-Realm" suffix is dropped,
--                               since Forever names carry no realm)
-------------------------------------------------

-- Placeholder names the client returns before a unit resolves
local UNKNOWN_NAMES = {
    unknown = true, inconnu = true, unbekannt = true,
    desconocido = true, desconhecido = true, sconosciuto = true,
}

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
Utils.Trim = Trim

local function CleanName(name)
    name = AccessibleString(name)
    if not name then return nil end
    -- Typographic quotes and dashes (UTF-8) folded to ASCII
    name = name:gsub("\226\128\152", "'"):gsub("\226\128\153", "'")
        :gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
    name = Trim(name):gsub("%s+", " ")
    -- ; , ~ : | are wire separators (Sync/Protocol.lua) and never appear in real names
    if name == "" or #name > 80 or name:find("[%c|:;,~]") then return nil end
    return name
end

-- GetCurrentRegion(): 1 US (Oceanic realms too), 2 KR, 3 EU, 4 TW, 5 CN
local REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }

-- The account's region as the website names it, or nil when the client does not say
function Utils.Region()
    return REGIONS[tonumber(Accessible(SafeCall(_G.GetCurrentRegion)))]
end

function Utils.PlayerRealm()
    local realm = AccessibleString(SafeCall(_G.GetNormalizedRealmName))
    if not realm then
        realm = AccessibleString(SafeCall(_G.GetRealmName))
        realm = realm and realm:gsub("%s", "")
    end
    return realm
end

local function ForeverKey(name)
    local hyphen = name:find("-", 1, true)
    local base = hyphen and Trim(name:sub(1, hyphen - 1)) or name
    local given, family = base:match("^(%S+) (%S+)$")
    if not given or UNKNOWN_NAMES[given:lower()] then return nil end
    return given .. " " .. family
end

local function EraKey(name, realm)
    local hyphen = name:find("-", 1, true)
    if hyphen then
        realm = name:sub(hyphen + 1)
        name = name:sub(1, hyphen - 1)
    end
    if name == "" or name:find("%s") or UNKNOWN_NAMES[name:lower()] then return nil end
    if not realm or realm == "" then
        realm = Utils.PlayerRealm()
    end
    if not realm then return nil end
    realm = realm:gsub("%s", "")
    if realm == "" then return nil end
    return name .. "-" .. realm
end

-- name may already carry "-Realm"; realm is optional (defaults to the player's)
function Utils.PlayerKey(name, realm)
    name = CleanName(name)
    if not name then return nil end
    if ns.Features.RealmlessNames then
        return ForeverKey(name)
    end
    return EraKey(name, AccessibleString(realm))
end

-- The realm GetPlayerInfoByGUID reports for a unit (7th return)
local function UnitRealmByGUID(unit)
    local guid = Utils.UnitGUID(unit)
    if not guid then return nil end
    local _, _, _, _, _, _, realm = SafeCall(_G.GetPlayerInfoByGUID, guid)
    return AccessibleString(realm)
end

-- Forever: for other players UnitName returns the given name and the family name as
-- two values (probe 2026-09-23: "Joob", "Stabber"), so the second value is only a
-- realm when it matches one. Order: GetUnitName(unit, true), a one-value full name,
-- then given + family.
local function ForeverUnitKey(unit)
    local key = Utils.PlayerKey(AccessibleString(SafeCall(_G.GetUnitName, unit, true)))
    if key then return key end
    local name, second = Utils.UnitName(unit)
    if not name then return nil end
    key = Utils.PlayerKey(name)
    if key or not second then return key end
    if second == Utils.PlayerRealm() or second == UnitRealmByGUID(unit) then return nil end
    return Utils.PlayerKey(name .. " " .. second)
end

function Utils.UnitKey(unit)
    if ns.Features.RealmlessNames then
        return ForeverUnitKey(unit)
    end
    return Utils.PlayerKey(Utils.UnitName(unit))
end

-- Comparison form of a character name or key. Addon-message senders may arrive in
-- a different shape than unit names (on Forever: "Given Family", "GivenFamily"
-- or with a "-Realm" suffix), so identity checks compare this instead of raw strings.
--   Era:     lowercase "name-realm"
--   Forever: lowercase given+family with no spaces and no realm
function Utils.CompactName(name)
    if ns.Features.RealmlessNames then
        name = AccessibleString(name)
        if not name then return nil end
        local base = (name:match("^([^%-]+)") or name):gsub("%s", ""):lower()
        return base ~= "" and base or nil
    end
    local key = Utils.PlayerKey(name)
    return key and key:lower()
end

function Utils.SameCharacter(a, b)
    local ca = Utils.CompactName(a)
    return ca ~= nil and ca == Utils.CompactName(b)
end

-- HH-112: open the chat box with a whisper to a player (same faction only: the game
-- does not let the factions whisper each other). key: player key; on our own realm the
-- realm is dropped.
function Utils.OpenWhisper(key)
    local target = key and Utils.DisplayName(key)
    if not target or target == "" then return false end
    if _G.ChatFrame_SendTell then
        SafeCall(_G.ChatFrame_SendTell, target)
        return true
    end
    if _G.ChatFrame_OpenChat then
        SafeCall(_G.ChatFrame_OpenChat, "/w " .. target .. " ")
        return true
    end
    return false
end

-- Short form for display: drops the realm when it is the player's own
function Utils.DisplayName(key)
    if not key or ns.Features.RealmlessNames then return key end
    local name, realm = key:match("^(.-)%-(.+)$")
    if name and realm == Utils.PlayerRealm() then return name end
    return key
end

-- A player of our faction as a chat link (author, 2026-10-01): a left click whispers
-- them, a right click opens the game's player menu. Only for chat lines: popups and
-- center text cannot be clicked.
function Utils.PlayerLink(key)
    local name = Utils.DisplayName(key)
    if not name or name == "" then return nil end
    return "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
end

-------------------------------------------------
-- Time
-------------------------------------------------

-- Seconds since epoch, shared by all clients. Use for anything that is synced.
function Utils.ServerTime()
    return (GetServerTime and GetServerTime()) or time()
end

-- Local monotonic seconds. Use for windows and throttles on this client only.
function Utils.Now()
    return GetTime()
end

-- "just now" / "5 min ago" / "8 h 52 min ago" / "3 d 4 h ago"
function Utils.Ago(seconds)
    local L = ns.L
    if seconds < 60 then return L.JUST_NOW end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return string.format(L.MINUTES_AGO, minutes) end
    local hours = math.floor(minutes / 60)
    if hours < 24 then return string.format(L.HOURS_AGO, hours, minutes % 60) end
    return string.format(L.DAYS_AGO, math.floor(hours / 24), hours % 24)
end

-------------------------------------------------
-- Map
-------------------------------------------------

local function MapInfo(mapID)
    if not mapID or not C_Map then return nil end
    return SafeCall(C_Map.GetMapInfo, mapID)
end

function Utils.PlayerMapID()
    if not C_Map then return nil end
    return tonumber(Accessible(SafeCall(C_Map.GetBestMapForUnit, "player")))
end

-- x, y in 0..1 on mapID, or nil (instances, unmapped areas)
function Utils.PlayerPosition(mapID)
    mapID = mapID or Utils.PlayerMapID()
    if not mapID or not C_Map then return nil end
    local pos = SafeCall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not pos then return nil end
    local x, y = SafeCall(pos.GetXY, pos)
    x, y = tonumber(Accessible(x)), tonumber(Accessible(y))
    if not x or not y then return nil end
    return x, y
end

function Utils.MapName(mapID)
    local info = MapInfo(mapID)
    return info and AccessibleString(info.name)
end

-- Walk up the map tree to the continent map (Eastern Kingdoms, Kalimdor)
function Utils.ContinentOf(mapID)
    local continentType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
    local id = mapID
    for _ = 1, 10 do
        local info = MapInfo(id)
        if not info then return nil end
        if info.mapType == continentType then return id end
        id = info.parentMapID
        if not id or id == 0 then return nil end
    end
    return nil
end

-------------------------------------------------
-- Race icons (as in GudaBags Core/Utils.lua)
-------------------------------------------------

-- Race tokens whose atlas name differs
local RACE_ATLAS = { scourge = "undead" }
local GENDER_ATLAS = { [2] = "male", [3] = "female" }

-- Inline race icon for text ("|A:raceicon-orc-male:14:14|a"), or "" when the race is
-- unknown. race: token ("Orc", "Scourge", "NightElf"); sex: 2 male, 3 female.
-- Forever has the larger retail art ("raceicon128-...").
function Utils.RaceIcon(race, sex, size)
    local atlas = Utils.RaceAtlas(race, sex)
    if not atlas then return "" end
    size = size or 14
    return string.format("|A:%s:%d:%d|a", atlas, size, size)
end

-- The race icon's atlas name ("raceicon-orc-male"), or nil when the race is unknown
function Utils.RaceAtlas(race, sex)
    if type(race) ~= "string" or race == "" then return nil end
    local name = race:lower()
    name = RACE_ATLAS[name] or name
    local prefix = ns.IsForever and "raceicon128" or "raceicon"
    return string.format("%s-%s-%s", prefix, name, GENDER_ATLAS[sex] or "male")
end

-- A level for text: the skull icon for -1 (10+ levels above the viewer), "?" unknown
Utils.SKULL_TEXT = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t"

function Utils.LevelText(level)
    if level == -1 then return Utils.SKULL_TEXT end
    return level and tostring(level) or "?"
end

-- A race token as players know it ("NightElf" -> "Night Elf", "Scourge" -> "Undead").
-- ns.RaceDisplay holds the names for other languages (Locales_<locale>.lua).
local RACE_NAMES = { NightElf = "Night Elf", Scourge = "Undead" }

function Utils.RaceName(race)
    if not race then return nil end
    return ns.RaceDisplay and ns.RaceDisplay[race] or RACE_NAMES[race] or race
end

-- A class token as players know it ("ROGUE" -> "Rogue"), in the client's language
function Utils.ClassName(class)
    if not class then return nil end
    return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
        or class:sub(1, 1) .. class:sub(2):lower()
end

-- "Alliance" / "Horde" in the client's language
function Utils.FactionName(faction)
    if faction == "Alliance" then return FACTION_ALLIANCE or faction end
    if faction == "Horde" then return FACTION_HORDE or faction end
    return faction
end

-- Inline class icon for text, from the client's class icon sheet, or "" when unknown
function Utils.ClassIcon(class, size)
    local coords = type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not coords then return "" end
    size = size or 14
    return string.format("|TInterface\\WorldStateFrame\\ICONS-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t", size, size,
        coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

-- Map pin + tracked waypoint at x, y (0..1) on mapID. False when the client or the
-- map does not allow it.
function Utils.SetWaypoint(mapID, x, y)
    if not (mapID and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return false end
    if C_Map.CanSetUserWaypointOnMap and not SafeCall(C_Map.CanSetUserWaypointOnMap, mapID) then
        return false
    end
    local point = SafeCall(UiMapPoint.CreateFromCoordinates, mapID, x, y)
    if not point then return false end
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return ok
end

-------------------------------------------------
-- Tables
-------------------------------------------------

function Utils.CopyTable(source)
    local copy = {}
    for k, v in pairs(source) do
        copy[k] = type(v) == "table" and Utils.CopyTable(v) or v
    end
    return copy
end

-- Fill keys missing from target with (copies of) defaults. Existing values win.
function Utils.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = type(v) == "table" and Utils.CopyTable(v) or v
        elseif type(target[k]) == "table" and type(v) == "table" then
            Utils.ApplyDefaults(target[k], v)
        end
    end
    return target
end

function Utils.CountKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-------------------------------------------------
-- Slash arguments: whitespace-separated, "double quotes" group words
-- (needed for Forever names, which contain a space)
-------------------------------------------------

function Utils.Tokenize(input)
    local tokens = {}
    input = input or ""
    local pos = 1
    while pos <= #input do
        local s = input:find("%S", pos)
        if not s then break end
        if input:sub(s, s) == '"' then
            local e = input:find('"', s + 1, true)
            if not e then
                tokens[#tokens + 1] = input:sub(s + 1)
                break
            end
            tokens[#tokens + 1] = input:sub(s + 1, e - 1)
            pos = e + 1
        else
            local e = input:find("%s", s) or (#input + 1)
            tokens[#tokens + 1] = input:sub(s, e - 1)
            pos = e
        end
    end
    return tokens
end
