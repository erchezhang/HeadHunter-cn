-- HeadHunter_DB: settings and meta for the account, the data per realm ("home").
--
-- Each realm keeps its own data (author, 2026-09-29): a Normal realm character must
-- not see what PvP realm characters collected. HeadHunter_DB.homes["forever|4620"] or
-- ["era|firemaw"] (Utils.HomeKey) holds the HOME_TABLES; settings, meta and zones stay
-- at the root. ns.db is a proxy: ns.db.deaths is the current home's, ns.db.settings the
-- root's, so modules read and write it as before. DB:Root() is the saved table.
--
-- Runtime state lives in memory (ns.db). The SavedVariable is a best-effort mirror:
-- on Forever the client could write it at logout but not load it back (docs/README.md
-- "Known bug"), so every module must work from an empty database on every load and
-- recover shared state from peers (HH-023).

local addonName, ns = ...

local DB = ns:RegisterModule("Database", {})

DB.SCHEMA_VERSION = 4

-- Old saved data mixed every realm. On WoW Forever it goes to the PvP realm, where the
-- author played most (author, 2026-09-29); Era takes the realm of the last character.
DB.LEGACY_FOREVER_SERVER = 4619

-- Used only when neither the game nor meta.home tells the home yet
DB.FALLBACK_HOME = "unknown"

-- Per home; anything else in ns.db is the root's
DB.HOME_TABLES = {
    deaths = true, reports = true, enemies = true, justice = true, posters = true, posse = true,
    bountyPay = true, duels = true, eventResults = true, marks = true, demoMarks = true, player = true,
    witness = true, pinned = true, glasses = true, screenshots = true, honorKills = true, wars = true,
}

DB.LIMITS = {
    deaths = 500,
    deathMaxAgeDays = 30,
    enemies = 2000,
    enemyMaxAgeDays = 7,
    honorKills = 5000,
    honorKillMaxAgeDays = 30,
}

local DEFAULTS = {
    schemaVersion = DB.SCHEMA_VERSION,
    meta = {
        createdAt = 0,
        lastLoadAt = 0,
        savedAt = 0,
        loadCount = 0,
    },
    settings = {
        debug = false,
        alerts = {
            enabled = true,
            sound = true,
            popups = true,
            range = "adjacent", -- "adjacent" | "continent"
            whisperInvite = true, -- Join on another layer: whisper the victim for an invite
            shame = true, -- a Hall of Shame bully or Deadbeat in sight: center text and chat (author, 2026-09-28)
            glassPopup = true, -- Raise a glass when another HeadHunter busts a WANTED player (Barflies, author, 2026-10-04)
            glassPopupGap = 5, -- minutes between two glass popups, 3..15 (author, 2026-10-04)
            glassThanks = true, -- a chat line when a HeadHunter raises a glass to our catch (author, 2026-10-04)
            duelSpots = true, -- HH-134: a chat line when a duel spot starts in the alert range (author, 2026-10-05)
        },
        serialKillerWindowMin = 15, -- 5..15
        mapPins = true, -- HH-046: hotspot and WANTED pins on the world map
        tooltip = true, -- HH-062: WANTED line on enemy player tooltips
        organizerMarks = true, -- HH-128: the star on tournament hosts and co-organizers
        wantedMarks = true, -- the HeadHunter crosshair above WANTED players (UI/Nameplates.lua)
        shameMarks = true, -- the white feather above Hall of Shame players
        minimap = { angle = 200, hidden = false }, -- HH-060 minimap button
        uiScale = 100, -- HH-125: window size, 70..150 %, set with the corner grip of the main window
        screenshots = true, -- HH-132: pictures of our PvP deaths and catches, for the admins (needs HeadHunter Sync)
    },
    zones = {}, -- zone mapID -> { name, continent, locale }: names for the website (Alerts/Zones.lua)
    homes = {}, -- home key -> HOME_DEFAULTS
}

local HOME_DEFAULTS = {
    deaths = {},  -- array of death reports, oldest first (HH-013)
    reports = {}, -- report id -> report: own + peer deaths, grow-only (HH-022)
    enemies = {}, -- player key -> enemy record (HH-010)
    justice = {}, -- catch id -> WANTED outlaw killed by a HeadHunter or their group (HH-048)
    posters = {}, -- poster id -> player bounty on their killer (HH-118)
    posse = {}, -- outlaw id -> our own join { t, mapID, layer, hunterRank }, kept over a reload
    bountyPay = {}, -- poster id -> claim and payment of that bounty (HH-118)
    duels = {},   -- High Noon: duel id -> duel someone saw (HH-091)
    witness = {}, -- HH-121: witness id -> a hunted player who died near a HeadHunter (Sync/Witness.lua)
    pinned = {},  -- HH-121: sighting id -> a sighting kept as evidence for a bounty claim (Sync/Evidence.lua)
    glasses = {}, -- glass id -> a HeadHunter raised a glass to a catch (Sync/Glasses.lua)
    screenshots = {}, -- HH-132: pictures taken for the sync app (Sync/Screenshots.lua)
    -- Our honorable kills by map and time, oldest first (Detection/HonorKills.lua)
    honorKills = {},
    -- HH-136: wars, a hotzone's fight from start to end (Alerts/Wars.lua), oldest first
    wars = {},
    -- Tournament match results confirmed in game (Tournament/Matches.lua): every
    -- HeadHunter's bracket; our own go to the website with HeadHunter Sync
    eventResults = {},
    marks = { total = 0, events = {} }, -- HH-050
}

-- MIGRATIONS[n] upgrades a database from schema n-1 to n
local MIGRATIONS = {}

local DAY = 86400

local root, home

-- ns.db: HOME_TABLES from the current home, the rest from the root
local proxy = setmetatable({}, {
    __index = function(_, key)
        if DB.HOME_TABLES[key] then
            DB:ConfirmHome()
            return home and home[key]
        end
        return root and root[key]
    end,
    __newindex = function(_, key, value)
        if DB.HOME_TABLES[key] then home[key] = value else root[key] = value end
    end,
})

function DB:Root()
    return root
end

function DB:HomeKey()
    return self.homeKey
end

-- The old data's home (schema 1 had one store for every realm)
local function LegacyHome(db)
    if ns.Features.RealmlessNames then return ns.Utils.ForeverHome(DB.LEGACY_FOREVER_SERVER) end
    local realm = type(db.meta) == "table" and type(db.meta.player) == "table" and db.meta.player.realm
    return type(realm) == "string" and ns.Utils.EraHome(realm) or ns.Utils.HomeKey() or DB.FALLBACK_HOME
end

MIGRATIONS[2] = function(db)
    local key = LegacyHome(db)
    db.homes[key] = db.homes[key] or {}
    for name in pairs(DB.HOME_TABLES) do
        if name ~= "player" and db[name] ~= nil then
            db.homes[key][name] = db[name]
            db[name] = nil
        end
    end
    db.wanted = nil
    db.meta.home = db.meta.home or key
end

-- The tournaments players made in game are gone (author, 2026-09-30): they come only
-- from the website now (Tournament/Tournaments.lua)
MIGRATIONS[3] = function(db)
    db.tournaments = nil
    for _, home in pairs(db.homes) do
        if type(home) == "table" then home.tournaments = nil end
    end
end

-- Screenshots are on by default (author, 2026-10-05). 0.4.3 and 0.4.4 saved the old
-- default (off) into every player's settings the same day, so it is turned on once
MIGRATIONS[4] = function(db)
    if type(db.settings) == "table" then db.settings.screenshots = true end
end

-- Use this home's data. Returns true when the home changed.
function DB:BindHome(key)
    key = key or ns.Utils.HomeKey() or root.meta.home or self.FALLBACK_HOME
    if key == self.homeKey then return false end
    root.homes[key] = root.homes[key] or {}
    ns.Utils.ApplyDefaults(root.homes[key], HOME_DEFAULTS)
    home = root.homes[key]
    self.homeKey = key
    self.homeConfirmed = ns.Utils.HomeKey() == key
    root.meta.home = key
    ns:Debug("Database home:", key)
    return true
end

-- Bound from meta.home while the game did not tell our server or realm: the first data
-- access once it does moves to the right home, and HH_HOME_CHANGED lets the modules
-- rebuild what they keep in memory
function DB:ConfirmHome()
    if self.homeConfirmed or not root then return end
    local key = ns.Utils.HomeKey()
    if not key then return end
    self.homeConfirmed = true
    if self:BindHome(key) then
        self:Prune()
        C_Timer.After(0, function() ns.Events:Fire("HH_HOME_CHANGED", key) end)
    end
end

function DB:Initialize()
    local Utils = ns.Utils
    local saved = HeadHunter_DB
    local restored = type(saved) == "table"
    local db = restored and saved or {}
    local savedVersion = restored and (tonumber(db.schemaVersion) or 0) or self.SCHEMA_VERSION

    Utils.ApplyDefaults(db, DEFAULTS)
    db.schemaVersion = savedVersion
    self:Migrate(db)

    local now = Utils.ServerTime()
    if db.meta.createdAt == 0 then db.meta.createdAt = now end
    db.meta.lastLoadAt = now
    db.meta.loadCount = db.meta.loadCount + 1
    -- For the desktop sync app: which region and game this data belongs to
    db.meta.region = Utils.Region() or db.meta.region
    db.meta.client = ns.Expansion.ClientKey

    -- Lets /hh status and the probe report whether this client loaded SavedVariables
    self.restoredFromDisk = restored

    root, home = db, nil
    self.homeKey, self.homeConfirmed = nil, false
    self:BindHome()

    HeadHunter_DB = db
    ns.db = proxy
    ns.debugMode = db.settings.debug == true

    self:Prune(now)
    ns:Debug("Database ready. Restored from disk:", restored, "schema:", db.schemaVersion)
    return db
end

-- Forever does not load SavedVariables back (known client bug): true while that holds,
-- false by itself once the client restores them
function DB:ResetsOnReload()
    return not ns.Features.SavedVarsReliable and not self.restoredFromDisk
end

function DB:Migrate(db)
    local version = tonumber(db.schemaVersion) or 0
    if version > self.SCHEMA_VERSION then
        -- Written by a newer addon version: leave it untouched rather than guess
        ns:Debug("Database schema", version, "is newer than", self.SCHEMA_VERSION)
        return
    end
    for v = version + 1, self.SCHEMA_VERSION do
        if MIGRATIONS[v] then
            MIGRATIONS[v](db)
        end
    end
    db.schemaVersion = self.SCHEMA_VERSION
end

-- The records of a list (oldest first) from `minTime` on, the newest `limit` of them
function DB.KeepRecent(list, minTime, limit)
    local kept = {}
    for _, record in ipairs(list or {}) do
        if type(record) == "table" and (tonumber(record.t) or 0) >= minTime then
            kept[#kept + 1] = record
        end
    end
    while #kept > limit do table.remove(kept, 1) end
    return kept
end

-- Drop old or excess records. Runs on load and logout.
function DB:Prune(now)
    local db = ns.db
    if not db then return end
    now = now or ns.Utils.ServerTime()
    local limits = self.LIMITS

    local minDeathTime = now - limits.deathMaxAgeDays * DAY
    local kept = {}
    for _, report in ipairs(db.deaths) do
        if type(report) == "table" and (tonumber(report.t) or 0) >= minDeathTime then
            kept[#kept + 1] = report
        end
    end
    local excess = #kept - limits.deaths
    if excess > 0 then
        local trimmed = {}
        for i = excess + 1, #kept do
            trimmed[#trimmed + 1] = kept[i]
        end
        kept = trimmed
    end
    db.deaths = kept
    db.honorKills = DB.KeepRecent(db.honorKills, now - limits.honorKillMaxAgeDays * DAY, limits.honorKills)

    local minSeen = now - limits.enemyMaxAgeDays * DAY
    local byAge = {}
    for key, enemy in pairs(db.enemies) do
        local seen = type(enemy) == "table" and tonumber(enemy.lastSeen) or 0
        if seen < minSeen then
            db.enemies[key] = nil
        else
            byAge[#byAge + 1] = { key = key, seen = seen }
        end
    end
    if #byAge > limits.enemies then
        table.sort(byAge, function(a, b) return a.seen < b.seen end)
        for i = 1, #byAge - limits.enemies do
            db.enemies[byAge[i].key] = nil
        end
    end
end

function DB:OnLogout()
    if not ns.db then return end
    self:Prune()
    self:RememberPlayer()
    ns.db.meta.savedAt = ns.Utils.ServerTime()
end

-- For the desktop sync app: the saved data is written at logout, so meta.player names
-- the character played last and each home's player the last one of that realm (their
-- own deaths, catches and bounty).
function DB:RememberPlayer()
    local U = ns.Utils
    local key = U.UnitKey("player")
    if not (ns.db and key) then return end
    local race = U.UnitRace("player")
    local player = {
        key = key,
        realm = not ns.Features.RealmlessNames and U.PlayerRealm() or nil,
        server = ns.Features.RealmlessNames and U.PlayerServer() or nil,
        class = U.UnitClass("player"),
        race = race,
        sex = U.UnitSex("player"),
        level = U.UnitLevel("player"),
        faction = U.UnitFaction("player") or U.RaceFaction(race),
        guild = U.UnitGuild("player"),
    }
    ns.db.meta.player = player
    ns.db.player = U.CopyTable(player)
end

-------------------------------------------------
-- Settings: dotted paths, e.g. "alerts.range"
-------------------------------------------------

local function Resolve(path)
    local node = ns.db.settings
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        keys[#keys + 1] = key
    end
    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if type(node) ~= "table" then return nil end
    end
    return node, keys[#keys]
end

function DB:GetSetting(path)
    local node, key = Resolve(path)
    return node and node[key]
end

function DB:SetSetting(path, value)
    local node, key = Resolve(path)
    if not node then return false end
    node[key] = value
    ns.Events:Fire("HH_SETTING_CHANGED", path, value)
    return true
end
