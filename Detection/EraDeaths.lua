-- HH-011: who killed me, on clients with the combat log (Classic Era).
--
-- Every hit on the player from a hostile player, or from a hostile player's pet or
-- minion, is kept for ATTACKER_WINDOW seconds and credited to the player (pet
-- owners: Detection/PetOwners.lua). The hit with overkill >= 0 is the killing blow.
-- On PLAYER_DEAD the killer and assists are resolved through the enemy cache (level,
-- race, sex) and handed to the report pipeline.
--   - a mob, an unknown pet or a fall finishing us while an enemy player (or his pet)
--     hit us: full kill for that player (author, 2026-09-23)
--   - only a pet of unknown owner hit us: its owner is looked up at death (tooltip),
--     else the single enemy hunter/warlock seen recently gets it as "inferred"
--   - no hostile player and no player-controlled pet: PvE, not reported

local addonName, ns = ...

local EraDeaths = ns:RegisterModule("EraDeaths", {})

local OWNER = "EraDeaths"

local ATTACKER_WINDOW = 15
local KILLING_BLOW_WINDOW = 2

-- COMBATLOG_OBJECT_* bits (constants may be missing at load time)
local TYPE_PLAYER = 0x00000400
local TYPE_NPC = 0x00000800
local TYPE_PET = 0x00001000
local TYPE_GUARDIAN = 0x00002000
local CONTROL_PLAYER = 0x00000100
local REACTION_HOSTILE = 0x00000040

-- Subevent -> index of the amount argument; overkill follows it
local AMOUNT_INDEX = {
    SWING_DAMAGE = 12,
    RANGE_DAMAGE = 15,
    SPELL_DAMAGE = 15,
    SPELL_PERIODIC_DAMAGE = 15,
    SPELL_BUILDING_DAMAGE = 15,
    DAMAGE_SHIELD = 15,
    DAMAGE_SPLIT = 15,
}

-- A hostile hunter/warlock doing any of these to his own pet reveals the owner
local OWNER_TO_PET = {
    SPELL_SUMMON = true, SPELL_CAST_SUCCESS = true, SPELL_AURA_APPLIED = true,
    SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true, SPELL_ENERGIZE = true,
}

local band = bit.band

local playerGUID
local sameFaction = {}  -- guid -> true/false, memoised (the combat log is hot)
local attackers = {}    -- id (guid, or "key:<key>") -> { guid?, key?, name, damage, lastHit }
local petHits = {}      -- pet guid (owner unknown yet) -> { name, damage, lastHit }
local killingBlow       -- { id, pet?, at }
local lastHit           -- last damage to the player from ANY source, for the death log

local function SourceKind(flags)
    if band(flags, TYPE_PLAYER) ~= 0 then return "player" end
    if band(flags, TYPE_PET) ~= 0 then return "pet" end
    if band(flags, TYPE_GUARDIAN) ~= 0 then return "guardian" end
    if band(flags, TYPE_NPC) ~= 0 then return "npc" end
    return "other"
end

local function IsHostile(flags)
    return band(flags, REACTION_HOSTILE) ~= 0
end

local function IsPlayer(flags)
    return band(flags, TYPE_PLAYER) ~= 0
end

local function IsPlayerPet(flags)
    return type(flags) == "number" and band(flags, TYPE_PET + TYPE_GUARDIAN) ~= 0 and band(flags, CONTROL_PLAYER) ~= 0
end

function EraDeaths:Reset()
    wipe(attackers)
    wipe(petHits)
    killingBlow = nil
end

local function OwnerId(owner)
    return owner.guid or ("key:" .. owner.key)
end

local function KeyOf(who)
    return who.key or (who.name and ns.Utils.PlayerKey(who.name))
end

-- The attacker a player or a pet's owner already is: by GUID, or by name when a pet's
-- owner was learned without a GUID, so a hunter and their pet are one attacker (seen in
-- game 2026-10-30: "Gang 3vs1" for a hunter, their pet and one more)
local function AttackerIdOf(owner)
    local id = OwnerId(owner)
    if attackers[id] then return id end
    local key = KeyOf(owner)
    for otherId, entry in pairs(attackers) do
        if (owner.guid and entry.guid == owner.guid) or (key and KeyOf(entry) == key) then
            return otherId
        end
    end
    return id
end

local function Hit(owner, amount, overkill, now)
    local id = AttackerIdOf(owner)
    local entry = attackers[id]
    if not entry then
        entry = { guid = owner.guid, key = owner.key, name = owner.name, damage = 0 }
        attackers[id] = entry
    end
    entry.guid = entry.guid or owner.guid
    entry.damage = entry.damage + (amount or 0)
    entry.lastHit = now
    if overkill and overkill >= 0 then
        killingBlow = { id = id, at = now }
    end
end

local function IsFriendlyPlayer(guid)
    local friendly = sameFaction[guid]
    if friendly == nil then
        friendly = ns.Utils.IsSameFactionGUID(guid)
        sameFaction[guid] = friendly
    end
    return friendly
end

function EraDeaths:OnCombatLog()
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, _, destFlags =
        CombatLogGetCurrentEventInfo()
    if type(sourceFlags) ~= "number" then return end

    -- Every hit on us, whoever it came from, for the death log (/hh debug)
    playerGUID = playerGUID or ns.Utils.UnitGUID("player")
    if destGUID == playerGUID and AMOUNT_INDEX[subevent] then
        local _, overkill = select(AMOUNT_INDEX[subevent], CombatLogGetCurrentEventInfo())
        lastHit = { name = sourceName, kind = SourceKind(sourceFlags), hostile = IsHostile(sourceFlags),
            subevent = subevent, overkill = overkill, at = ns.Utils.Now() }
    end

    if not IsHostile(sourceFlags) then return end

    if IsPlayer(sourceFlags) then
        -- Duel opponents are flagged hostile: drop players of our own faction
        if IsFriendlyPlayer(sourceGUID) then return end
        -- Any hostile player in the log is worth caching (GUID, name, class, race)
        ns.EnemyCache:ObserveGUID(sourceGUID, sourceName, "combatlog")
        -- A hunter/warlock summoning, healing or buffing his pet reveals the owner
        if OWNER_TO_PET[subevent] and IsPlayerPet(destFlags) and not ns.PetOwners:Owner(destGUID) then
            local _, classFile = ns.Utils.SafeCall(GetPlayerInfoByGUID, sourceGUID)
            if subevent == "SPELL_SUMMON" or ns.PetOwners.PET_CLASSES[classFile] then
                ns.PetOwners:Learn(destGUID, sourceName, sourceGUID)
            end
        end
    end

    if destGUID ~= playerGUID then return end
    local amountIndex = AMOUNT_INDEX[subevent]
    if not amountIndex then return end
    local amount, overkill = select(amountIndex, CombatLogGetCurrentEventInfo())
    amount, overkill = tonumber(amount), tonumber(overkill)
    local now = ns.Utils.Now()

    if IsPlayer(sourceFlags) then
        Hit({ guid = sourceGUID, name = sourceName }, amount, overkill, now)
    elseif IsPlayerPet(sourceFlags) then
        local owner = ns.PetOwners:Owner(sourceGUID)
        if owner then
            Hit(owner, amount, overkill, now)
        else
            -- Owner unknown for now: resolved at death
            local pet = petHits[sourceGUID] or { name = sourceName, damage = 0 }
            pet.damage = pet.damage + (amount or 0)
            pet.lastHit = now
            petHits[sourceGUID] = pet
            if overkill and overkill >= 0 then
                killingBlow = { pet = sourceGUID, at = now }
            end
        end
    end
end

-- Pets whose owner was unknown during the fight: look again now (tooltip scan)
local function ResolvePetHits(now)
    local unresolved = false
    for petGUID, pet in pairs(petHits) do
        if now - pet.lastHit <= ATTACKER_WINDOW then
            local owner = ns.PetOwners:Owner(petGUID) or ns.PetOwners:ScanFor(petGUID)
            if owner then
                local id = AttackerIdOf(owner)
                local entry = attackers[id] or { guid = owner.guid, key = owner.key, name = owner.name, damage = 0, lastHit = 0 }
                entry.damage = entry.damage + pet.damage
                entry.lastHit = math.max(entry.lastHit, pet.lastHit)
                attackers[id] = entry
                if killingBlow and killingBlow.pet == petGUID then
                    killingBlow = { id = id, at = killingBlow.at }
                end
            else
                unresolved = true
                ns:Debug("Death: pet", tostring(pet.name), "dealt", pet.damage, "- owner unknown")
            end
        end
    end
    return unresolved
end

-- Hostile players (and resolved pet owners) who hit us within the window, most damage first
function EraDeaths:RecentAttackers(now)
    local list = {}
    for id, entry in pairs(attackers) do
        if now - entry.lastHit <= ATTACKER_WINDOW then
            entry.id = id
            list[#list + 1] = entry
        else
            attackers[id] = nil
        end
    end
    table.sort(list, function(a, b) return a.damage > b.damage end)
    return list
end

local function EnemyOf(entry)
    local DR = ns.DeathReports
    if entry.guid then return DR.EnemyFromCache(entry.guid, entry.name) end
    local record = ns.EnemyCache:ByKey(entry.key)
    if record then return DR.EnemyFromRecord(record) end
    return { key = entry.key, name = entry.key }
end

function EraDeaths:OnPlayerDead()
    if not ns.Guards:IsActive() then
        self:Reset()
        return
    end
    local now = ns.Utils.Now()
    local petUnresolved = ResolvePetHits(now)
    local list = self:RecentAttackers(now)

    -- Death log: what landed the last hit, and which enemy players were on us
    if lastHit then
        ns:Debug(string.format("Death: last hit %s (%s, %s) %s overkill %s, %.1fs before death",
            tostring(lastHit.name), lastHit.kind, lastHit.hostile and "hostile" or "not hostile",
            tostring(lastHit.subevent), tostring(lastHit.overkill), now - lastHit.at))
    end
    for _, entry in ipairs(list) do
        ns:Debug(string.format("Death: enemy player %s dealt %d, last hit %.1fs before death%s", tostring(entry.name),
            entry.damage, now - entry.lastHit, killingBlow and killingBlow.id == entry.id and " (killing blow)" or ""))
    end
    lastHit = nil

    local confidence = "exact"
    if #list == 0 and petUnresolved then
        -- Only a pet of unknown owner was on us: the lone enemy hunter/warlock nearby
        local owner = ns.PetOwners:LikelyOwner()
        if owner then
            list = { { guid = owner.guid, key = owner.key, name = owner.key, damage = 0, lastHit = now, id = owner.guid } }
            confidence = "inferred"
            ns:Debug("Death: pet owner guessed as", owner.key)
        end
    end

    if #list == 0 then
        self:Reset()
        return
    end

    -- A mob, an unknown pet or a fall finishing us while an enemy player was on us
    -- still counts fully for that player, even for a single hit (author,
    -- 2026-09-23). The one who dealt the most damage is the killer.
    local killerEntry
    if killingBlow and killingBlow.id and now - killingBlow.at <= KILLING_BLOW_WINDOW and attackers[killingBlow.id] then
        killerEntry = attackers[killingBlow.id]
    else
        killerEntry = list[1]
    end

    local report = { killer = EnemyOf(killerEntry), assists = {}, confidence = confidence }
    for _, entry in ipairs(list) do
        if entry ~= killerEntry then
            report.assists[#report.assists + 1] = EnemyOf(entry)
        end
    end
    self:Reset()
    ns.Events:Fire("HH_DEATH_REPORT", report, "combatlog")
end

ns.Events:Register("HH_INITIALIZED", function()
    if not ns.Features.HasCLEU then return end
    playerGUID = ns.Utils.UnitGUID("player")
    ns.Events:Register("COMBAT_LOG_EVENT_UNFILTERED", function() EraDeaths:OnCombatLog() end, OWNER)
    ns.Events:Register("PLAYER_DEAD", function() EraDeaths:OnPlayerDead() end, OWNER)
    ns.Events:Register("HH_SUSPEND_CHANGED", function() EraDeaths:Reset() end, OWNER)
    -- Second line of defence: nothing hit during a duel may count toward a later death
    ns.Events:Register("DUEL_FINISHED", function() EraDeaths:Reset() end, OWNER)
end, OWNER)
