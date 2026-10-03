-- HH-043: a WANTED outlaw just killed someone near you.
--
--   WANTED · Ganker Wiadro (?? Dwarf Rogue) killed Headhunta in Elwynn Forest, 1 min ago
--   5 kills · WANTED until caught · Coward
--   [Join the posse] [Decline]
--
-- Triggered by new reports (HH_REPORT_ADDED) from other players (or simulated ones).
-- The WANTED list is recomputed about 1 s after a report arrives, so the check runs
-- after that. Rules (docs/addon/features.md section 4):
--   - only fresh kills (FRESH seconds) and never our own death
--   - in range (Alerts/Zones.lua, settings.alerts.range): popup + center text + sound
--   - farther away on the same continent: one chat line only
--   - other continents: nothing
--   - one popup per outlaw per THROTTLE seconds (Alerts framework), queued in combat
--   - after a Decline or a timed-out popup: no popup about any outlaw for 20 min, chat
--     lines only (Posse)
--   - while in a posse: no popup about other outlaws unless they are in our zone
--   - at most one WANTED or hotspot popup per 3 min (Alerts.POPUP_GAP)
-- Level window: deferred on purpose (author, 2026-09-23), see tickets HH-043.

local addonName, ns = ...
local L = ns.L

local Activity = ns:RegisterModule("Activity", {})

local OWNER = "Activity"

Activity.FRESH = 600
Activity.THROTTLE = 120
Activity.CHECK_DELAY = 1.5  -- after the WANTED recompute (1 s debounce)

-- "60 Night Elf Hunter" (skull icon for a skull level)
local function Describe(enemy)
    return ns.DeathReports.Describe(enemy)
end

local Ago = ns.Utils.Ago

-- Every WANTED enemy in the report (killer first, then assists)
local function WantedIn(report)
    local Engine, Wanted = ns.RulesEngine, ns.Wanted
    local found = {}
    local enemies = { report.killer }
    for _, assist in ipairs(report.assists or {}) do enemies[#enemies + 1] = assist end
    for _, enemy in ipairs(enemies) do
        local entry = Wanted:Get(Engine.EnemyId(enemy))
        if entry and entry.wanted then found[#found + 1] = { entry = entry, enemy = enemy } end
    end
    return found
end

function Activity:Check(report)
    local U = ns.Utils
    if report.origin == "local" then return end
    if report.victim and U.SameCharacter(report.victim.key, U.UnitKey("player")) then return end
    local age = U.ServerTime() - (report.t or 0)
    if age > self.FRESH then return end

    local inRange, distance = ns.Zones.InRange(report.mapID)
    for _, hit in ipairs(WantedIn(report)) do
        local entry, enemy = hit.entry, hit.enemy
        local Wanted = ns.Wanted
        local name = enemy.key and U.DisplayName(enemy.key) or entry.name
        local zone = U.MapName(report.mapID) or L.UNKNOWN_ZONE
        local victim = U.DisplayName(report.victim and report.victim.key) or "?"
        local badges = Wanted.BadgeNames(entry)
        local headline = string.format(L.ACTIVITY_HEADLINE, Wanted.RankName(entry.rank), name, Describe(enemy),
            victim, zone, Ago(age))
        local details = string.format(L.ACTIVITY_DETAILS, math.floor(entry.kills))
            .. (badges ~= "" and (" · " .. badges) or "")
        local layerMatch, myLayer = ns.Layer:Compare(report.layer, report.mapID)
        if layerMatch == "same" then
            details = details .. "\n" .. L.LAYER_SAME
        elseif layerMatch == "different" then
            details = details .. "\n" .. string.format(L.LAYER_DIFFERENT, myLayer, report.layer)
        end
        local posse = ns.Posse:Summary(entry.id)
        if posse then details = details .. "\n" .. posse end

        if ns.Posse:IsMember(entry.id) then
            -- Already hunting this outlaw: short update, no popup, waypoint follows
            if distance then
                ns.Alerts:Show({
                    key = "posse-update:" .. entry.id .. ":" .. tostring(report.id),
                    throttle = 0,
                    text = string.format(L.POSSE_UPDATE_CENTER, name, zone),
                    chat = headline .. " · " .. details:gsub("\n", " · "),
                    sound = "soft",
                })
                ns.Posse:Refresh(entry, report)
            end
        elseif ns.Posse:RecentlyDeclined() then
            -- We declined a posse lately (any outlaw): chat line only
            if distance then
                ns.Alerts:Show({ key = "declined:" .. entry.id, throttle = self.THROTTLE, chat = headline })
            end
        elseif inRange and distance ~= "zone" and ns.Posse:Hunting() then
            -- Busy with another outlaw's posse: a chat line, unless this one is right here
            ns.Alerts:Show({ key = "hunting:" .. entry.id, throttle = self.THROTTLE, chat = headline })
        elseif inRange and not Wanted.InLevelWindow(entry) then
            -- HH-047: not a fight for our level (either way): a chat line, no popup
            ns.Alerts:Show({ key = "activity-level:" .. entry.id, throttle = self.THROTTLE,
                chat = headline .. " · " .. L.ACTIVITY_NOT_YOUR_LEVEL })
        elseif inRange then
            ns.Alerts:Show({
                key = "activity:" .. entry.id,
                throttle = self.THROTTLE,
                text = string.format(L.ACTIVITY_CENTER, Wanted.RankName(entry.rank), name, zone),
                chat = headline .. " · " .. details,
                sound = true,
                popup = {
                    text = headline .. "\n" .. details,
                    accept = L.POSSE_JOIN,
                    decline = L.POSSE_DECLINE,
                    onAccept = function() ns.Posse:Join(entry, report) end,
                    onDecline = function(reason) ns.Posse:Decline(entry, report, reason) end,
                },
            })
        elseif distance == "continent" then
            ns.Alerts:Show({ key = "activity-far:" .. entry.id, throttle = self.THROTTLE, chat = headline })
        end
    end
end

-- Reports often arrive in batches (one Report click can carry several deaths). They
-- are collected for CHECK_DELAY, then only the NEWEST report per killer is checked,
-- so the alert describes the latest kill, not whichever came first.
local pending = {}
local flushScheduled = false

local function FlushPending()
    flushScheduled = false
    local newest = {}   -- killer id -> report
    local order = {}
    for _, report in ipairs(pending) do
        local id = ns.RulesEngine.EnemyId(report.killer) or report.id
        local current = newest[id]
        if not current then order[#order + 1] = id end
        if not current or (report.t or 0) > (current.t or 0) then newest[id] = report end
    end
    wipe(pending)
    for _, id in ipairs(order) do
        Activity:Check(newest[id])
    end
end

function Activity:Enqueue(report)
    pending[#pending + 1] = report
    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(self.CHECK_DELAY, FlushPending)
    end
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("HH_REPORT_ADDED", function(_, report) Activity:Enqueue(report) end, OWNER)
end, OWNER)
