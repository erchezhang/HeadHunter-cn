-- HH-128: a sheriff's star on tournament hosts and co-organizers (docs/addon/tickets.md).
-- Gold for the host, silver for co-organizers, on player tooltips, before their chat
-- lines and above their head (UI/Nameplates.lua). Only HeadHunter users see it. Who organizes comes only from the website data
-- (Sync/SiteData.lua: the tournaments HeadHunter Sync brought in), never from a player's
-- own addon message, which an edited addon could fake.
--
-- When (author, 2026-09-30): from 1 hour before the start (the lock), during the
-- tournament, until 30 minutes after it ends. The addon does not know the end yet (no
-- match results), so the star stops AFTER seconds after the start. A tournament of
-- several days has the same window on each day.
--
-- Organizers:RoleOf(key, now) -> "host" | "organizer", tournament; or nil
-- Organizers.Star(role, size) -> the star as chat and tooltip text (|T...|t)

local addonName, ns = ...
local L = ns.L

local Organizers = ns:RegisterModule("Organizers", {})

Organizers.BEFORE = 3600
Organizers.AFTER = 4 * 3600
Organizers.STAR = "Interface\\AddOns\\HeadHunter\\Assets\\Textures\\star"
-- The texture is white; the color tints it (the website's gold, and silver)
Organizers.COLORS = { host = { 230, 180, 34 }, organizer = { 192, 192, 192 } }
-- Chat where players talk; channels are left alone (Sync/Transport.lua filters its own)
Organizers.CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

function Organizers.Star(role, size)
    local color = Organizers.COLORS[role] or Organizers.COLORS.organizer
    size = size or 14
    return string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t",
        Organizers.STAR, size, size, color[1], color[2], color[3])
end

function Organizers:Enabled()
    return ns.db ~= nil and ns.db.settings.organizerMarks ~= false
end

-- The start of the day whose window is open now, or nil. A tournament of several days
-- (author, 2026-09-30) has a window on each day.
local function InWindow(tournament, now)
    for _, start in ipairs(tournament.days or { tournament.startsAt }) do
        if now >= start - Organizers.BEFORE and now <= start + Organizers.AFTER then return start end
    end
    return nil
end

-- The role of a player now: "host" before "organizer" when both
function Organizers:RoleOf(key, now)
    if not key then return nil end
    local U = ns.Utils
    now = now or U.ServerTime()
    local found, foundTournament
    for _, tournament in ipairs(ns.SiteData:Tournaments()) do
        if InWindow(tournament, now) then
            if U.SameCharacter(tournament.host, key) then return "host", tournament end
            for _, organizer in ipairs(tournament.organizers) do
                if not found and U.SameCharacter(organizer, key) then found, foundTournament = "organizer", tournament end
            end
        end
    end
    return found, foundTournament
end

-- Host or co-organizer of this tournament, at any time (who may call and confirm its
-- matches, Tournament/Matches.lua): only by the website data
function Organizers.IsOrganizerOf(tournament, key)
    local U = ns.Utils
    if not (tournament and key) then return false end
    if U.SameCharacter(tournament.host, key) then return true end
    for _, organizer in ipairs(tournament.organizers or {}) do
        if U.SameCharacter(organizer, key) then return true end
    end
    return false
end

-- "starts in 45 min" or "in progress", for the day whose window is open
function Organizers.Status(tournament, now)
    local start = InWindow(tournament, now) or tournament.startsAt
    if now < start then
        return string.format(L.TOURNAMENT_STARTS_IN, math.max(1, math.ceil((start - now) / 60)))
    end
    return L.TOURNAMENT_IN_PROGRESS
end

-- The tooltip line for a player unit: { text, r, g, b } or nil
function Organizers:TooltipLine(unit, now)
    local U = ns.Utils
    if not self:Enabled() or not unit or not U.UnitIsPlayer(unit) then return nil end
    now = now or U.ServerTime()
    local role, tournament = self:RoleOf(U.UnitKey(unit), now)
    if not role then return nil end
    local format = role == "host" and L.TOOLTIP_TOURNAMENT_HOST or L.TOOLTIP_TOURNAMENT_ORGANIZER
    return { Organizers.Star(role) .. " " .. string.format(format, tournament.name, Organizers.Status(tournament, now)),
        1, 0.82, 0 }
end

-- Chat filter: the star before the message of a host or co-organizer
function Organizers.ChatFilter(_, _, message, author, ...)
    local U = ns.Utils
    if not Organizers:Enabled() or type(U.AccessibleString(message)) ~= "string" then return false end
    local role = Organizers:RoleOf(U.PlayerKey(U.AccessibleString(author)))
    if not role then return false end
    return false, Organizers.Star(role, 12) .. " " .. message, author, ...
end

-- /hh organizers (not in the help, a check like /hh probe): the tournaments from the
-- website data, their host and co-organizers, and how the addon sees the target
ns.SlashCommands:Register("organizers", function()
    local U = ns.Utils
    local now = U.ServerTime()
    local list = ns.SiteData:Tournaments()
    print(string.format("HeadHunter organizers: %d tournament(s) in the website data, marks %s",
        #list, Organizers:Enabled() and "on" or "off"))
    for _, t in ipairs(list) do
        print(string.format("  %s: starts in %d min, star window %s", t.name, math.floor((t.startsAt - now) / 60),
            InWindow(t, now) and "open" or "closed"))
        print("    host: " .. tostring(t.host) .. " (" .. tostring(U.CompactName(t.host)) .. ")")
        for _, key in ipairs(t.organizers) do
            print("    co-organizer: " .. tostring(key) .. " (" .. tostring(U.CompactName(key)) .. ")")
        end
    end
    local name, second = U.UnitName("target")
    local key = U.UnitKey("target")
    print(string.format("  target: name %s / %s, full %s, key %s (%s), role %s", tostring(name), tostring(second),
        tostring(U.AccessibleString(U.SafeCall(_G.GetUnitName, "target", true))), tostring(key),
        tostring(U.CompactName(key)), tostring((Organizers:RoleOf(key, now)))))
end)

-- Registered at load (the filter does nothing until the database is ready), so no new
-- HH_INITIALIZED handler changes the login order of the other modules
do
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then
        for _, event in ipairs(Organizers.CHAT_EVENTS) do
            pcall(add, event, Organizers.ChatFilter)
        end
    end
end
