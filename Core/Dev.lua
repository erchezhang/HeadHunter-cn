-- HH-123: settings for the author's own PCs, from the separate addon HeadHunter_Dev
-- (listed as OptionalDeps). It is never in this repo or a release, so every player
-- has none and gets the defaults.
--
-- Interface\AddOns\HeadHunter_Dev\Config.lua:
--   HeadHunter_Dev = { trust = { "Testone-Firemaw", "Testtwo Forever" } }
--
-- trust: characters whose test deaths (/hh sim send) we count. The check is on our
-- side, so another player's own HeadHunter_Dev never makes us count their test data.
--
-- locale: show a translation on any client: "zhCN", "zhTW", "koKR", "ruRU", "ptBR", "esES", "esMX", "frFR", "deDE" or "itIT" (read by Locales.lua).
-- Class and faction names still come from the client, so they stay in its language.
--
-- noSharing = true: test mode, for example with the local development sync app (author,
-- 2026-09-30). Nothing leaves this client: no addon messages and no channel text
-- (Sync/Transport.lua), so local test data never reaches other players. Receiving still
-- works. A chat line at login says it is on (Core/Main.lua).

local addonName, ns = ...

local Dev = ns:RegisterModule("Dev", {})

local function Config()
    local config = _G.HeadHunter_Dev
    return type(config) == "table" and config or nil
end

-- This PC has HeadHunter_Dev: the test commands work (/hh sim event)
function Dev.Present()
    return Config() ~= nil
end

function Dev.NoSharing()
    local config = Config()
    return config ~= nil and config.noSharing == true
end

function Dev.Trusts(name)
    local config = Config()
    if not name or not config or type(config.trust) ~= "table" then return false end
    for _, trusted in ipairs(config.trust) do
        if type(trusted) == "string" and ns.Utils.SameCharacter(name, trusted) then return true end
    end
    return false
end

-- Test entries (author, 2026-09-30): /hh dev wanted and /hh dev shame (UI/Nameplates.lua)
-- put the target in the WANTED list or the Hall of Shame, only on this client and only
-- with a HeadHunter_Dev config. Rules/Wanted.lua merges them like the website's entries,
-- so lists, tooltips and marks show them. Memory only, so a /reload clears them.
local tests = { wanted = {}, shame = {} }

function Dev.Enabled()
    return Config() ~= nil
end

-- key -> entry, in the shape of Sync/SiteData.lua WantedEntry and BullyEntry
function Dev.TestEntries(kind)
    return Config() and tests[kind] or {}
end

local function Entry(kind, key, unit)
    local U = ns.Utils
    local now = U.ServerTime()
    local entry = {
        id = key, key = key, name = key,
        level = U.UnitLevel(unit), class = U.UnitClass(unit), race = U.UnitRace(unit), sex = U.UnitSex(unit),
        wanted = false, kills = 0, killCount = 1, cowardKills = 0, timesWanted = 0, timesCaught = 0,
        badges = {}, lastKill = { t = now }, source = "dev",
    }
    if kind == "wanted" then
        entry.wanted, entry.rank, entry.peakRank, entry.kills, entry.timesWanted = true, "outlaw", "outlaw", 1, 1
        entry.wantedSince, entry.wantedUntil = now, now + 86400
    else
        entry.cowardKills = 1
    end
    return entry
end

-- Adds or removes the unit; returns true when it is now in, nil when it is no player
function Dev.ToggleTest(kind, unit)
    local key = ns.Utils.UnitIsPlayer(unit) and ns.Utils.UnitKey(unit)
    if not key or not tests[kind] then return nil end
    tests[kind][key] = not tests[kind][key] and Entry(kind, key, unit) or nil
    return tests[kind][key] ~= nil, key
end

function Dev.ClearTests()
    tests = { wanted = {}, shame = {} }
end
