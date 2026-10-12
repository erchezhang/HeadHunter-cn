-- HH-145: the HeadHunters we asked for a group invite from a map mark (a duel spot or a
-- PvP area), so each of them gets at most one invite whisper from us per LIMIT (author,
-- 2026-10-12). Three players asking the same HeadHunter are still three whispers; one
-- player clicking again asks the next HeadHunter there, or nobody.
-- Saved per home in db.invites (compact name -> time asked), so a /reload does not ask
-- again; Core/Database.lua prunes it. Made-up HeadHunters from /hh sim duels are kept in
-- memory only. Fires HH_INVITE_ASKED(name) after each ask, so the map tooltips change.

local addonName, ns = ...

local Invites = ns:RegisterModule("Invites", {})

Invites.LIMIT = ns.Database.LIMITS.inviteSeconds

local simAsked = {}

local function Key(name)
    return name and ns.Utils.CompactName(name)
end

local function AskedAt(key)
    if simAsked[key] then return simAsked[key] end
    local saved = ns.db and ns.db.invites
    return saved and saved[key]
end

-- Seconds until we may ask that HeadHunter again, or nil when we may now
function Invites:Left(name, now)
    local key = Key(name)
    local t = key and AskedAt(key)
    if not t then return nil end
    local left = t + self.LIMIT - (now or ns.Utils.ServerTime())
    return left > 0 and left or nil
end

-- We just asked that HeadHunter. sim: a made-up one, remembered in memory only
function Invites:Mark(name, now, sim)
    local key = Key(name)
    if not key then return end
    now = now or ns.Utils.ServerTime()
    if sim then
        simAsked[key] = now
    elseif ns.db and ns.db.invites then
        ns.db.invites[key] = now
    end
    ns.Events:Fire("HH_INVITE_ASKED", name)
end

-- The first of names we may ask now; or nil and the shortest time until one is free
function Invites:Pick(names, now)
    local shortest
    for _, name in ipairs(names) do
        local left = self:Left(name, now)
        if not left then return name end
        if not shortest or left < shortest then shortest = left end
    end
    return nil, shortest
end

function Invites:ClearSim()
    simAsked = {}
end

-- Whole minutes for the texts, at least 1
function Invites.Minutes(seconds)
    return math.max(1, math.ceil((seconds or 0) / 60))
end
