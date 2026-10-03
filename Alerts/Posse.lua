-- HH-044: posses. Who is hunting which WANTED outlaw.
--
-- Join (the popup button): waypoint at the last known position, we become a member,
-- and the join is sent to other HeadHunters:
--   Forever: queued on the hidden channel (posse priority)
--   Era:     sent realm-wide as channel text right away (the click is the hardware
--            event), plus queued for guild / party
-- Received joins (protocol type J, "outlawId;mapID;time;layer;hunterRank", the sender
-- is the member) keep a member list per outlaw for TTL seconds. Shown in the activity
-- popup ("Posse: A, B") and by /hh posse (with each member's hunter rank, HH-050).
-- Decline: HH_POSSE_DECLINED(entry, report, reason), counted by marks (Rules/Marks.lua)
-- unless the popup only timed out (reason "timeout").
-- Our own joins are also kept in ns.db.posse for their 30 minutes, so a /reload still
-- knows we ride with the posse: no second [Join the posse], no second bounty for it.
-- Events: HH_POSSE_JOINED(entry, report), HH_POSSE_CHANGED(outlawId).

local addonName, ns = ...
local L = ns.L

local Posse = ns:RegisterModule("Posse", {})

local OWNER = "Posse"

Posse.TTL = 1800        -- a join counts for 30 minutes
Posse.MAX_SKEW = 300
Posse.SHOWN_NAMES = 3   -- names shown in popups, then "+N"
Posse.QUIET_SIZE = 10   -- above this many members we join without telling the others (HH-116)

local posses = {}        -- outlawId -> compact member -> { name, t, mapID, self }

local function Prune(outlawId, now)
    local members = posses[outlawId]
    if not members then return end
    for id, member in pairs(members) do
        if now - member.t > Posse.TTL then members[id] = nil end
    end
    if next(members) == nil then posses[outlawId] = nil end
end

-- hunterRank: the member's HeadHunter rank index (Rules/Marks.lua), when known
local function AddMember(outlawId, name, t, mapID, isSelf, layer, hunterRank)
    local id = ns.Utils.CompactName(name)
    if not id then return false end
    posses[outlawId] = posses[outlawId] or {}
    local known = posses[outlawId][id]
    posses[outlawId][id] = { name = name, t = t, mapID = mapID, layer = layer, hunterRank = hunterRank,
        self = isSelf or (known and known.self) or nil }
    if isSelf and ns.db and ns.db.posse then
        ns.db.posse[outlawId] = { t = t, mapID = mapID, layer = layer, hunterRank = hunterRank }
    end
    ns.Events:Fire("HH_POSSE_CHANGED", outlawId)
    return not known
end

-- After a reload: our joins that still count, back in the member lists (not sent again)
function Posse:Restore(now)
    local saved = ns.db and ns.db.posse
    if not saved then return end
    now = now or ns.Utils.ServerTime()
    local me = ns.Utils.UnitKey("player") or "me"
    for outlawId, join in pairs(saved) do
        if type(join) ~= "table" or now - (tonumber(join.t) or 0) > self.TTL then
            saved[outlawId] = nil
        else
            AddMember(outlawId, me, join.t, join.mapID, true, join.layer, join.hunterRank)
        end
    end
end

-- Members of one posse: us first, then earliest first
function Posse:Members(outlawId)
    local now = ns.Utils.ServerTime()
    Prune(outlawId, now)
    local list = {}
    for _, member in pairs(posses[outlawId] or {}) do list[#list + 1] = member end
    table.sort(list, function(a, b)
        if (a.self or false) ~= (b.self or false) then return a.self == true end
        return a.t < b.t
    end)
    return list
end

-- In any posse right now (author, 2026-09-26: no popups about other outlaws then)
function Posse:Hunting()
    for outlawId in pairs(posses) do
        if self:IsMember(outlawId) then return true end
    end
    return false
end

function Posse:IsMember(outlawId)
    for _, member in ipairs(self:Members(outlawId)) do
        if member.self then return true end
    end
    return false
end

-- "Posse: Alpha, Bravo, Charlie +2" or nil when empty
function Posse:Summary(outlawId)
    local members = self:Members(outlawId)
    if #members == 0 then return nil end
    local names = {}
    for i = 1, math.min(#members, self.SHOWN_NAMES) do
        names[i] = members[i].self and L.POSSE_YOU or ns.Utils.DisplayName(members[i].name) or members[i].name
    end
    local text = table.concat(names, ", ")
    if #members > self.SHOWN_NAMES then text = text .. " +" .. (#members - self.SHOWN_NAMES) end
    return string.format(L.POSSE_SUMMARY, text)
end

-------------------------------------------------
-- Join / decline
-------------------------------------------------

-- The game's waypoint where the client allows it (Classic Era does not)
local function Guide(report)
    return ns.MapMarkers.Guide(report.mapID, report.x, report.y)
end

-- A big posse needs no more join messages: the "+N" already says enough
function Posse:Full(outlawId)
    return #self:Members(outlawId) > self.QUIET_SIZE
end

-- Runs inside the popup click (a hardware event): Era may send channel text here
local function Broadcast(outlawId, mapID, t, layer, hunterRank)
    if Posse:Full(outlawId) then return end
    local Protocol, Transport = ns.Protocol, ns.Transport
    local record = Protocol.EncodePosse(outlawId, mapID, t, layer, hunterRank)
    Transport:Queue(Protocol.TYPES.POSSE, record, Transport.PRIORITY.posse, "J:" .. outlawId)
    if Transport:RealmWideNeedsClick() then
        Transport:SendRealmWide(Protocol.TYPES.POSSE, { record })
    end
end

Posse.WHISPER_REPEAT = 900   -- a second death of the same victim within 15 minutes

-- Did the victim of this report die another time within WHISPER_REPEAT?
function Posse.DiedAgain(report)
    local victim = report and report.victim and report.victim.key
    local t = report and tonumber(report.t)
    if not victim or not t then return false end
    local U = ns.Utils
    for _, other in ns.Reports:All() do
        if other.id ~= report.id and other.victim and U.SameCharacter(other.victim.key, victim)
                and math.abs((tonumber(other.t) or 0) - t) <= Posse.WHISPER_REPEAT then
            return true
        end
    end
    return false
end

-- Already riding with this posse (also after a reload): nothing to join, nothing earned
function Posse:Join(entry, report)
    if self:IsMember(entry.id) then return false end
    local U = ns.Utils
    local name = entry.key and U.DisplayName(entry.key) or entry.name
    local zone = U.MapName(report.mapID) or L.UNKNOWN_ZONE
    local how, zx, zy = Guide(report)
    if how == "waypoint" then
        ns:Print(string.format(L.POSSE_JOINED_PIN, name, zone))
    elseif how == "coords" then
        ns:Print(string.format(L.POSSE_JOINED_COORDS, name, zone, zx * 100, zy * 100))
    else
        ns:Print(string.format(L.POSSE_JOINED, name, zone))
    end
    local now = U.ServerTime()
    local myLayer = ns.Layer:Current()
    local myRank = ns.Marks:RankIndex()
    AddMember(entry.id, U.UnitKey("player") or "me", now, U.PlayerMapID(), true, myLayer, myRank)
    Broadcast(entry.id, U.PlayerMapID(), now, myLayer, myRank)

    -- Another layer: ask the victim for a group invite (moves us to their layer), but
    -- only when they died again within WHISPER_REPEAT (a single death is not worth a
    -- whisper; being camped is). report.sender is the name the game gave us, so it is
    -- always a valid target. Runs inside the popup click, which allows the whisper.
    if ns.Layer:Compare(report.layer, report.mapID) == "different"
            and ns.db.settings.alerts.whisperInvite and report.sender and Posse.DiedAgain(report) then
        local ok = pcall(SendChatMessage, string.format(L.POSSE_WHISPER, name), "WHISPER", nil, report.sender)
        if ok then ns:Print(string.format(L.POSSE_WHISPERED, U.DisplayName(U.PlayerKey(report.sender)) or report.sender)) end
    end
    ns.Events:Fire("HH_POSSE_JOINED", entry, report)
    return true
end

-- Decline (author, 2026-09-26): no WANTED popup about any outlaw for DECLINE_QUIET
-- seconds, chat lines only. A popup that timed out holds the same way (the player did
-- not want it), without the bounty penalty.
Posse.DECLINE_QUIET = 1200
local lastDecline     -- GetTime() of our last decline

function Posse:Decline(entry, report, reason)
    lastDecline = ns.Utils.Now()
    ns.Events:Fire("HH_POSSE_DECLINED", entry, report, reason)
end

function Posse:RecentlyDeclined()
    return lastDecline ~= nil and ns.Utils.Now() - lastDecline < self.DECLINE_QUIET
end

-- A new kill by an outlaw we are hunting (author, 2026-09-23): the waypoint follows
-- the newest kill and our membership is refreshed (and re-announced to other
-- HeadHunters on the automatic routes).
function Posse:Refresh(entry, report)
    local U = ns.Utils
    Guide(report)
    local now = U.ServerTime()
    local myLayer = ns.Layer:Current()
    local myRank = ns.Marks:RankIndex()
    AddMember(entry.id, U.UnitKey("player") or "me", now, U.PlayerMapID(), true, myLayer, myRank)
    if self:Full(entry.id) then return end
    local Protocol, Transport = ns.Protocol, ns.Transport
    Transport:Queue(Protocol.TYPES.POSSE, Protocol.EncodePosse(entry.id, U.PlayerMapID(), now, myLayer, myRank),
        Transport.PRIORITY.posse, "J:" .. entry.id)
end

-- Another HeadHunter saw an outlaw we hunt (HH-121 step 3, Alerts/Spotted.lua): the
-- waypoint follows, and a posse line takes the place of the general spotted line
function Posse:OnSpotted(outlawId, sighting)
    local U = ns.Utils
    if not self:IsMember(outlawId) or U.SameCharacter(sighting.by, U.UnitKey("player")) then return end
    local entry = ns.Wanted:Get(outlawId)
    local name = entry and (entry.key and U.DisplayName(entry.key) or entry.name) or outlawId
    local zone = U.MapName(sighting.mapID) or L.UNKNOWN_ZONE
    local spotter = U.DisplayName(sighting.by) or sighting.by
    ns.MapMarkers.GuideAndTell(sighting.mapID, sighting.x, sighting.y,
        string.format(L.POSSE_SPOTTED, name, zone, spotter), string.format(L.POSSE_SPOTTED_PIN, name, zone, spotter))
end

-------------------------------------------------
-- Receiving
-------------------------------------------------

function Posse:OnPeerJoin(record, sender)
    local outlawId, mapID, t, layer, hunterRank = ns.Protocol.DecodePosse(record)
    if not outlawId then return end
    local now = ns.Utils.ServerTime()
    if t > now + self.MAX_SKEW or now - t > self.TTL then return end
    local isNew = AddMember(outlawId, sender, t, mapID, false, layer, hunterRank)
    -- Only hunters in the same posse hear about new members
    if isNew and self:IsMember(outlawId) then
        local entry = ns.Wanted:Get(outlawId)
        local outlaw = entry and (entry.key and ns.Utils.DisplayName(entry.key) or entry.name) or outlawId
        ns:Print(string.format(L.POSSE_MEMBER_JOINED, ns.Utils.DisplayName(ns.Utils.PlayerKey(sender)) or sender, outlaw))
    end
end

ns.Events:Register("HH_INITIALIZED", function()
    Posse:Restore()
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.POSSE, function(record, sender) Posse:OnPeerJoin(record, sender) end)
    ns.Events:Register("HH_OUTLAW_SPOTTED", function(_, outlawId, sighting) Posse:OnSpotted(outlawId, sighting) end,
        OWNER)
end, OWNER)

ns.SlashCommands:Register("posse", function()
    local now = ns.Utils.ServerTime()
    local any = false
    for outlawId in pairs(posses) do
        Prune(outlawId, now)
    end
    for outlawId in pairs(posses) do
        any = true
        local entry = ns.Wanted:Get(outlawId)
        local outlaw = entry and (entry.key and ns.Utils.DisplayName(entry.key) or entry.name) or outlawId
        ns:Print(string.format("|cffff4040%s|r · %s", outlaw, Posse:Summary(outlawId) or ""))
        for _, member in ipairs(Posse:Members(outlawId)) do
            local name = member.self and L.POSSE_YOU or ns.Utils.DisplayName(member.name) or member.name
            -- Hunter rank (HH-050) when the member's join carried it
            local rank = member.hunterRank and ns.Marks.RankNameByIndex(member.hunterRank) or ""
            if rank ~= "" then name = name .. " (" .. rank .. ")" end
            print(string.format("  %s  %s  %s", name, ns.Utils.MapName(member.mapID) or "?",
                member.layer and string.format(L.LAYER_TAG, member.layer) or ""))
        end
    end
    if not any then ns:Print(L.POSSE_NONE) end
end, L.HELP_POSSE)

-- Another realm's saved joins (Core/Database.lua ConfirmHome)
ns.Events:Register("HH_HOME_CHANGED", function() Posse:Restore() end, OWNER)
