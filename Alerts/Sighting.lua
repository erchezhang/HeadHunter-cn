-- HH-042: a WANTED outlaw (or at large, or with a player's bounty; a Hall of Shame
-- bully more softly) shows up on a nameplate, as target, under the mouse or as
-- a party member's target.
--
--   WANTED · Ganker Wiadro is here! (?? Dwarf Rogue) · Coward
--
-- Driven by HH_ENEMY_SEEN from the enemy cache, so it inherits its rules: hostile
-- players only, nothing inside instances, and a 2 s refresh throttle per GUID.
-- The same outlaw alerts again at most every THROTTLE seconds. Shown at once even in
-- combat (author, 2026-09-23): the outlaw may be the one attacking us.
-- Level window (docs/addon/features.md section 4) deferred on purpose (tickets HH-043).

local addonName, ns = ...
local L = ns.L

local Sighting = ns:RegisterModule("Sighting", {})

local OWNER = "Sighting"

Sighting.THROTTLE = 300          -- the same outlaw again: 5 minutes (author, 2026-10-01)
Sighting.BULLY_THROTTLE = 600  -- a bully or Deadbeat (Hall of Shame) not WANTED: once per 10 min each

-- WANTED, at large, or with a player's bounty (HH-118)
local function Watched(entry)
    return ns.Wanted.Hunted(entry) or ns.Bounties:ActiveOn(entry)
end

-- The watched entry for an enemy record: by key, or by GUID for Forever outlaws
-- still known only by their given name
function Sighting.WantedEntry(record)
    local Wanted = ns.Wanted
    local entry = record.key and Wanted:ByKey(record.key)
    if not Watched(entry) and record.guid then
        entry = Wanted:Get("guid:" .. record.guid)
    end
    return Watched(entry) and entry or nil
end

-- "60 Night Elf Hunter" (skull icon for a skull level)
local function Describe(record)
    return ns.DeathReports.Describe(record)
end

-- A Hall of Shame bully (killed players 10+ levels lower or grey) who is not WANTED
function Sighting.BullyEntry(record)
    local Wanted = ns.Wanted
    local entry = (record.key and Wanted:ByKey(record.key)) or (record.guid and Wanted:Get("guid:" .. record.guid))
    return entry and entry.badges and entry.badges.coward and entry or nil
end

-- Author, 2026-09-28: bullies alert too, softer and less often than WANTED
function Sighting:OnBullySeen(record, entry)
    if ns.Database:GetSetting("alerts.shame") == false then return end
    local name = ns.Utils.DisplayName(record.key) or entry.name
    ns.Alerts:Show({
        key = "bully:" .. entry.id,
        throttle = self.BULLY_THROTTLE,
        text = string.format(L.SIGHTING_BULLY, name),
        chat = string.format(L.SIGHTING_CHAT_BULLY, name, Describe(record), entry.cowardKills or 0),
        sound = "soft",
        combat = true,
    })
end

function Sighting:OnEnemySeen(record, source)
    if source == "sim" or source == "fallback" then return end
    local entry = self.WantedEntry(record)
    if not entry then
        local bully = self.BullyEntry(record)
        if bully then
            self:OnBullySeen(record, bully)
        elseif record.key and ns.Bounties:IsBlocked(record.key) then
            self:AlertDeadbeat(record.key, true)
        end
        return
    end

    local Wanted = ns.Wanted
    local name = ns.Utils.DisplayName(record.key) or entry.name
    local badges = Wanted.BadgeNames(entry)
    local suffix = badges ~= "" and (" · " .. badges) or ""
    -- The chat line stays with us; Alerts/Spotted.lua tells the others where he is
    local text, chat
    if entry.wanted then
        text = string.format(L.SIGHTING_TEXT, Wanted.RankName(entry.rank), name)
        chat = string.format(L.SIGHTING_CHAT, Wanted.RankName(entry.rank), name, Describe(record),
            math.floor(entry.kills)) .. suffix
    elseif entry.atLarge then
        text = string.format(L.SIGHTING_AT_LARGE, name)
        chat = string.format(L.SIGHTING_CHAT_AT_LARGE, name, Describe(record),
            Wanted.RankName(entry.lastRank), entry.killCount or 0) .. suffix
    else
        text = string.format(L.SIGHTING_BOUNTY, name)
        chat = string.format(L.SIGHTING_CHAT_BOUNTY, name, Describe(record))
    end
    local bounty = ns.Bounties:Line(entry.id)
    if bounty then chat = chat .. " · " .. bounty end

    local alerted = ns.Alerts:Show({
        key = "seen:" .. entry.id,
        throttle = self.THROTTLE,
        text = text,
        chat = chat,
        sound = true,
        combat = true, -- the outlaw may be the one we are fighting: tell us now
    })
    if alerted then ns.Events:Fire("HH_OUTLAW_SEEN", entry) end
end

-- HH-118: a Deadbeat of our own faction (unpaid bounties, blocked 30 days) we target
-- or hover. The enemy cache only follows enemies, so this watches the two units itself.
function Sighting:CheckDeadbeat(unit)
    local U = ns.Utils
    if ns.Database:GetSetting("alerts.shame") == false or not U.UnitIsPlayer(unit) or U.UnitIsEnemyPlayer(unit) then return end
    local key = U.UnitKey(unit)
    if not key or U.SameCharacter(key, U.UnitKey("player")) then return end
    if ns.Bounties:IsBlocked(key) then self:AlertDeadbeat(key, false) end
end

-- enemy: the other faction's Deadbeat, worth bounty points when brought down
function Sighting:AlertDeadbeat(key, enemy)
    local U = ns.Utils
    if ns.Database:GetSetting("alerts.shame") == false then return end
    local _, unpaid = ns.Bounties:Standing(key)
    local name = U.DisplayName(key)
    ns.Alerts:Show({
        key = "deadbeat:" .. U.CompactName(key),
        throttle = self.BULLY_THROTTLE,
        text = string.format(L.SIGHTING_DEADBEAT, name),
        chat = string.format(enemy and L.SIGHTING_CHAT_DEADBEAT_ENEMY or L.SIGHTING_CHAT_DEADBEAT, name, unpaid),
        sound = "soft",
        combat = enemy or nil,
    })
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("HH_ENEMY_SEEN", function(_, record, source) Sighting:OnEnemySeen(record, source) end, OWNER)
    ns.Events:Register("PLAYER_TARGET_CHANGED", function() Sighting:CheckDeadbeat("target") end, OWNER)
    ns.Events:Register("UPDATE_MOUSEOVER_UNIT", function() Sighting:CheckDeadbeat("mouseover") end, OWNER)
end, OWNER)
