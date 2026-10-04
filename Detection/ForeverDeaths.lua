-- HH-012: who killed me, on clients without the combat log (WoW Forever).
--
-- Forever withholds COMBAT_LOG_EVENT_UNFILTERED, but C_DeathRecap exposes the hits
-- of the last death (probe 2026-09-23, build 1.60.1.69913). Each entry has
-- sourceGUID, sourceName ("Given-Realm", no family name), sourceFlags, event,
-- amount, overkill and timestamp (server epoch). The killing blow has overkill >= 0.
-- Full names and levels come from the enemy cache by GUID.
--
-- If the recap is empty or unavailable, the killer is guessed from the target and
-- recent sightings (confidence "inferred").

local addonName, ns = ...

local ForeverDeaths = ns:RegisterModule("ForeverDeaths", {})

local OWNER = "ForeverDeaths"

local TYPE_PLAYER = 0x00000400
local TYPE_PET = 0x00001000
local TYPE_GUARDIAN = 0x00002000
local CONTROL_PLAYER = 0x00000100
local REACTION_HOSTILE = 0x00000040

-- The recap may not be ready on the PLAYER_DEAD frame: try again at these delays
local RECAP_RETRY_DELAYS = { 0.3, 1, 2 }

local deathSerial = 0

-- "player" | "pet" (hostile, player-controlled) | nil
local function HostileKind(entry)
    local U = ns.Utils
    local flags = tonumber(U.Accessible(entry.sourceFlags))
    local guid = U.AccessibleString(entry.sourceGUID)
    if not flags or not guid or bit.band(flags, REACTION_HOSTILE) == 0 then return nil end
    if bit.band(flags, TYPE_PLAYER) ~= 0 then
        -- Duel opponents are flagged hostile too
        return not U.IsSameFactionGUID(guid) and "player" or nil
    end
    if bit.band(flags, TYPE_PET + TYPE_GUARDIAN) ~= 0 and bit.band(flags, CONTROL_PLAYER) ~= 0 then
        return "pet"
    end
    return nil
end

-- Who a recap entry counts for: { id, guid?, key?, name } or nil (NPC, unknown pet)
local function SourceOf(entry)
    local U = ns.Utils
    local kind = HostileKind(entry)
    local guid = U.AccessibleString(entry.sourceGUID)
    if kind == "player" then
        return { id = guid, guid = guid, name = U.AccessibleString(entry.sourceName) }
    end
    if kind == "pet" then
        local owner = ns.PetOwners:Owner(guid) or ns.PetOwners:ScanFor(guid)
        if owner then
            return { id = owner.guid or ("key:" .. owner.key), guid = owner.guid, key = owner.key, name = owner.name }
        end
        return { unknownPet = true }
    end
    return nil
end

local function EnemyOf(source)
    local DR = ns.DeathReports
    if source.guid then return DR.EnemyFromCache(source.guid, source.name) end
    local record = ns.EnemyCache:ByKey(source.key)
    if record then return DR.EnemyFromRecord(record) end
    return { key = source.key, name = source.key }
end

local function ReadRecap()
    local U = ns.Utils
    if not C_DeathRecap or not U.SafeCall(C_DeathRecap.HasRecapEvents) then return nil end
    local events = U.SafeCall(C_DeathRecap.GetRecapEvents)
    if type(events) ~= "table" or #events == 0 then return nil end
    return events
end

-- Build the report from recap entries, or nil when no hostile player took part (PvE).
-- Pets and minions count for their owner (Detection/PetOwners.lua).
function ForeverDeaths:ReportFromRecap(events)
    local U = ns.Utils
    local killerId, killerStamp
    local sources, order = {}, {}
    local unknownPet = false
    for _, entry in ipairs(events) do
        local source = SourceOf(entry)
        if source and source.unknownPet then
            unknownPet = true
        elseif source then
            if not sources[source.id] then
                sources[source.id] = source
                order[#order + 1] = source.id
                -- Class, race, sex and given name by GUID for sources never seen on a unit
                if source.guid then ns.EnemyCache:ObserveGUID(source.guid, source.name, "deathrecap") end
            end
            local overkill = tonumber(U.Accessible(entry.overkill))
            if not killerId and overkill and overkill >= 0 then
                killerId = source.id
                killerStamp = tonumber(U.Accessible(entry.timestamp))
            end
            killerStamp = killerStamp or tonumber(U.Accessible(entry.timestamp))
        end
    end

    local confidence = "exact"
    if #order == 0 then
        if not unknownPet then return nil end
        -- Only a pet of unknown owner: the lone enemy hunter/warlock nearby
        local owner = ns.PetOwners:LikelyOwner()
        if not owner then return nil end
        sources[owner.guid] = { id = owner.guid, guid = owner.guid, key = owner.key, name = owner.key }
        order[1] = owner.guid
        confidence = "inferred"
    end

    -- A mob or pet finishing us while an enemy player was hitting us still counts
    -- fully for that player (author, 2026-09-23): the newest hostile player hit
    killerId = killerId or order[1]
    -- A hunter and their pet are two sources (GUID, and the owner's name) but one
    -- attacker: each player once
    local killer = EnemyOf(sources[killerId])
    local named = { [ns.RulesEngine.EnemyId(killer) or killerId] = true }
    local assists = {}
    for _, id in ipairs(order) do
        if id ~= killerId then
            local enemy = EnemyOf(sources[id])
            local enemyId = ns.RulesEngine.EnemyId(enemy) or id
            if not named[enemyId] then
                named[enemyId] = true
                assists[#assists + 1] = enemy
            end
        end
    end
    return {
        t = killerStamp and math.floor(killerStamp) or nil,
        killer = killer,
        assists = assists,
        confidence = confidence,
    }
end

function ForeverDeaths:ReportFromFallback()
    local record = ns.EnemyCache:LikelyAttacker(10)
    if not record then return nil end
    return {
        killer = ns.DeathReports.EnemyFromRecord(record),
        assists = {},
        confidence = "inferred",
    }
end

function ForeverDeaths:OnPlayerDead()
    if not ns.Guards:IsActive() then return end
    deathSerial = deathSerial + 1
    local serial = deathSerial
    -- Snapshot now: position and level at the moment of death, not after the retries
    local U = ns.Utils
    local mapID = U.PlayerMapID()
    local x, y = U.PlayerPosition(mapID)
    local deathTime = U.ServerTime()

    local attempt = 0
    local function Try()
        if serial ~= deathSerial then return end -- a newer death superseded this one
        attempt = attempt + 1
        local events = ReadRecap()
        local report
        if events then
            report = self:ReportFromRecap(events)
            if not report then
                ns:Debug("Death recap has no hostile player: PvE death")
                return
            end
        elseif attempt < #RECAP_RETRY_DELAYS then
            C_Timer.After(RECAP_RETRY_DELAYS[attempt + 1] - RECAP_RETRY_DELAYS[attempt], Try)
            return
        else
            report = self:ReportFromFallback()
            if not report then
                ns:Debug("Death with no recap and no likely attacker: not reported")
                return
            end
        end
        report.t = report.t or deathTime
        report.mapID, report.x, report.y = mapID, x, y
        ns.Events:Fire("HH_DEATH_REPORT", report, "deathrecap")
    end
    C_Timer.After(RECAP_RETRY_DELAYS[1], Try)
end

ns.Events:Register("HH_INITIALIZED", function()
    if ns.Features.HasCLEU then return end
    ns.Events:Register("PLAYER_DEAD", function() ForeverDeaths:OnPlayerDead() end, OWNER)
end, OWNER)
