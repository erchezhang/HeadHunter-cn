-- HH-023: login catch-up. What happened while we were offline comes from a peer.
--
-- WANTED is derived from reports + catches, so catch-up passes on those records
-- (never a finished WANTED list) and every client still computes the same result.
--
--   1. hello   we -> automatic routes   Q "h<since>"  "I missed everything after <since>"
--   2. offer   peer -> us (whisper)     O "<count>"   after a random delay, only if it
--                                                     has records newer than <since>
--   3. pull    us -> two best peers     Q "p<since>" the peers with the most records
--   4. data    peer -> us (whisper)     S "D<death>" / "K<catch>" / "U<duel>" ... then "E<count>"
--
-- Offers are tiny, and only SOURCES peers send data, so a busy realm does not flood a
-- player who logs in. With many online only about OFFER_TARGET peers offer (HH-116);
-- a hello nobody offered to goes out once more. <since> is our last logout minus MARGIN (the SavedVariables
-- time); without saved data it is the report lifetime (30 days). Relayed records are
-- stored with origin "relay" (the time checks still apply) and count only once a
-- second source has them (HH-121, Sync/Relay.lua): that is why we pull from two.
-- Era: the automatic hello reaches guild and group only (its channel refuses addon
-- messages). After 15+ minutes away a [Catch up] popup sends it realm-wide as
-- channel text (the click allows that), and so does a typed /hh catchup. Offers,
-- pull and data are addon whispers, which Era allows between any two players.
-- Silent except in debug mode.

local addonName, ns = ...
local L = ns.L

local CatchUp = ns:RegisterModule("CatchUp", {})

local OWNER = "CatchUp"

CatchUp.START_DELAY = 20     -- after login: channel joined, guild known
CatchUp.RETRY = 10           -- no route yet: try again
CatchUp.MAX_WAIT = 120       -- then give up until /hh catchup
CatchUp.OFFER_DELAY = 3      -- peers wait up to this long before offering
CatchUp.OFFER_WAIT = 5       -- after the first offer, collect for this long
CatchUp.NO_OFFER_WAIT = 30   -- no offer by then: nobody has anything for us
CatchUp.GIVE_UP = 60         -- a pull that brings nothing is abandoned
CatchUp.MARGIN = 600         -- ask from 10 min before our last logout
CatchUp.MAX_RECORDS = 300    -- newest first, per answer
CatchUp.MAX_DUELS = 100      -- High Noon duels on top of that (HH-091)
CatchUp.ANSWER_COOLDOWN = 300 -- one answer per requester per 5 minutes
CatchUp.OFFER_TARGET = 5     -- about this many peers offer, however many are online
CatchUp.PROMPT_AWAY = 900    -- Era: offer the realm-wide catch-up after 15 min away
CatchUp.FRESH = 300          -- no automatic hello when our data is newer than this (HH-116)
CatchUp.SOURCES = 2          -- peers we pull from: a relayed record needs two (HH-121)

local state = "idle"         -- idle | asking | pulling | done
local since
local offers = {}            -- array of { sender, count }
local sources = {}           -- the peers we pull from
local pending = {}           -- compact source -> true until its "E" arrives
local received = { reports = 0, catches = 0 }
local answered = {}          -- compact requester -> GetTime() of our last answer
local attempt = 0
local helloRetried = false

CatchUp.last = nil           -- summary of the last catch-up (tests, /hh sync)

local function B36(n) return ns.Protocol.ToB36(n) end
local function FromB36(s) return ns.Protocol.FromB36(s) end

-- Last logout minus a margin, or the whole report lifetime without saved data. The
-- website's lists from the sync app (HH-082) cover what came before their time, so
-- with them we only ask for what is newer (HH-116).
function CatchUp.Since(now)
    now = now or ns.Utils.ServerTime()
    local meta = ns.db and ns.db.meta
    local savedAt = meta and tonumber(meta.savedAt) or 0
    local since = now - ns.Reports.MAX_AGE
    if ns.Database.restoredFromDisk and savedAt > 0 then
        since = math.max(since, savedAt - CatchUp.MARGIN)
    end
    local site = ns.SiteData:GeneratedAt()
    if site then since = math.max(since, site - CatchUp.MARGIN) end
    return since
end

-- Why the automatic hello at login is not needed, or nil (HH-116): a /reload with our
-- saved data, or website data from the sync app, newer than FRESH
function CatchUp.SkipReason(now)
    now = now or ns.Utils.ServerTime()
    local away = CatchUp.AwayFor(now)
    if away and away < CatchUp.FRESH then return "reload" end
    local site = ns.SiteData:GeneratedAt()
    if site and now - site < CatchUp.FRESH then return "website" end
    return nil
end

function CatchUp:State()
    return state
end

-------------------------------------------------
-- Asking (the player who logged in)
-------------------------------------------------

-- realmWide: called from a click or typed command, so on Era the hello may also go
-- to the whole realm as channel text. Returns true when a hello went out.
function CatchUp:Start(realmWide)
    local Transport = ns.Transport
    if not ns.Guards:IsActive() then return false end
    since = since or CatchUp.Since()
    local hello = "h" .. B36(since)
    local canRealm = realmWide and Transport:RealmWideNeedsClick() and Transport:ChannelID() ~= nil
    if state == "asking" or state == "pulling" then
        -- Era: the click widens a hello that only reached guild and group
        if canRealm and state == "asking" then
            return Transport:SendRealmWide(ns.Protocol.TYPES.QUERY, { hello }) > 0
        end
        return false
    end
    local auto = #Transport:AutoRoutes() > 0
    if not auto and not canRealm then return false end
    state, offers, sources, pending = "asking", {}, {}, {}
    received = { reports = 0, catches = 0 }
    helloRetried = false
    if auto then Transport:Queue(ns.Protocol.TYPES.QUERY, hello, Transport.PRIORITY.alert, "Q:hello") end
    if canRealm then Transport:SendRealmWide(ns.Protocol.TYPES.QUERY, { hello }) end
    ns:Debug("Catch-up: asking for records after", since, canRealm and "(realm-wide)" or "")
    -- Hello flush + offer delay + whisper flush, with room for combat flush intervals
    local function NoOffers()
        if state ~= "asking" or #offers > 0 then return end
        -- Only some peers offer on a busy realm: one more hello before giving up
        if auto and not helloRetried then
            helloRetried = true
            Transport:Queue(ns.Protocol.TYPES.QUERY, hello, Transport.PRIORITY.alert, "Q:hello")
            C_Timer.After(CatchUp.NO_OFFER_WAIT, NoOffers)
            return
        end
        state = "done"
        CatchUp.last = { reports = 0, catches = 0, from = nil }
        ns:Debug("Catch-up: no offers")
    end
    C_Timer.After(self.NO_OFFER_WAIT, NoOffers)
    return true
end

local function Choose()
    if state ~= "asking" or #offers == 0 then return end
    table.sort(offers, function(a, b) return a.count > b.count end)
    for _, offer in ipairs(offers) do
        local id = ns.Utils.CompactName(offer.sender)
        if #sources < CatchUp.SOURCES and id and not pending[id] then
            sources[#sources + 1] = offer.sender
            pending[id] = true
            ns.Transport:SendDirect(ns.Protocol.TYPES.QUERY, { "p" .. B36(since) }, offer.sender)
            ns:Debug("Catch-up: pulling", offer.count, "record(s) from", offer.sender)
        end
    end
    state = "pulling"
    C_Timer.After(CatchUp.GIVE_UP, function()
        if state == "pulling" then CatchUp:Finish("timeout") end
    end)
end

function CatchUp:OnOffer(record, sender)
    local count = FromB36(record)
    if state ~= "asking" or not count or count <= 0 then return end
    offers[#offers + 1] = { sender = sender, count = count }
    if #offers == 1 then C_Timer.After(self.OFFER_WAIT, Choose) end
end

function CatchUp:Finish(reason)
    state = "done"
    CatchUp.last = { reports = received.reports, catches = received.catches, from = sources[1], sources = sources,
        reason = reason }
    ns:Debug("Catch-up done (" .. tostring(reason) .. "):", received.reports, "report(s),",
        received.catches, "catch(es) from", table.concat(sources, ", "))
end

-- One of the peers we pull from, still sending
local function Pulling(sender)
    local id = ns.Utils.CompactName(sender)
    return id ~= nil and pending[id] == true
end

function CatchUp:OnData(record, sender)
    if state ~= "pulling" or not Pulling(sender) then return end
    local kind, body = record:sub(1, 1), record:sub(2)
    if kind == "D" then
        if ns.Reports:AddRelayed(body, sender) then received.reports = received.reports + 1 end
    elseif kind == "K" then
        if ns.Justice:AddRelayed(body, sender) then received.catches = received.catches + 1 end
    elseif kind == "U" then
        if ns.Duels:OnRecord(body, sender, "relay") then received.duels = (received.duels or 0) + 1 end
    elseif kind == "W" then
        ns.Bounties:AddRelayedPoster(body, sender)
    elseif kind == "R" then
        ns.Bounties:AddRelayedPayment(body, sender)
    elseif kind == "X" then
        ns.Witness:AddRelayed(body, sender)
    elseif kind == "Y" then
        ns.Evidence:AddRelayed(body, sender)
    elseif kind == "E" then
        pending[ns.Utils.CompactName(sender)] = nil
        if next(pending) == nil then self:Finish("complete") end
    end
end

-------------------------------------------------
-- Answering (everyone else)
-------------------------------------------------

-- The records newer than `since` we can pass on, as S records (newest first)
function CatchUp.Records(sinceTime)
    local Protocol = ns.Protocol
    local maxLength = Protocol.MAX_MESSAGE - 4 - 1 -- header, kind letter
    local records = {}
    for _, record in ipairs(ns.Justice:Since(sinceTime)) do
        records[#records + 1] = "K" .. ns.Justice.Encode(record)
    end
    for _, report in ipairs(ns.Reports:Since(sinceTime, CatchUp.MAX_RECORDS)) do
        if #records >= CatchUp.MAX_RECORDS then break end
        local encoded = Protocol.EncodeDeath(report, maxLength)
        if encoded then records[#records + 1] = "D" .. encoded end
    end
    -- Player bounties (HH-118) after the reports they rest on
    for _, record in ipairs(ns.Bounties:Records(sinceTime)) do records[#records + 1] = record end
    -- Witness records (HH-121): the evidence for those bounties
    for _, w in ipairs(ns.Witness:Since(sinceTime)) do records[#records + 1] = "X" .. Protocol.EncodeWitness(w) end
    for _, record in ipairs(ns.Evidence:Records(sinceTime)) do records[#records + 1] = record end
    -- High Noon duels (HH-091) after the reports: they matter less
    for _, duel in ipairs(ns.Duels:Since(sinceTime, CatchUp.MAX_DUELS)) do
        if #records >= CatchUp.MAX_RECORDS + CatchUp.MAX_DUELS then break end
        records[#records + 1] = "U" .. Protocol.EncodeDuel(duel)
    end
    return records
end

-- The share of peers that offers: 1 while few of our faction are online
function CatchUp.OfferChance(online)
    return math.min(1, CatchUp.OFFER_TARGET / math.max(1, (online or 1) - 1))
end

local function RecentlyAnswered(sender)
    local at = answered[ns.Utils.CompactName(sender)]
    return at ~= nil and ns.Utils.Now() - at < CatchUp.ANSWER_COOLDOWN
end

function CatchUp:OnQuery(record, sender)
    local kind, value = record:sub(1, 1), FromB36(record:sub(2))
    if not value or not ns.Guards:IsActive() then return end
    local Transport, TYPES = ns.Transport, ns.Protocol.TYPES
    if kind == "h" then
        if RecentlyAnswered(sender) then return end
        -- The chance first: building the records scans and encodes up to MAX_RECORDS
        local online = ns.Presence:Count()[ns.Utils.UnitFaction("player") or ""]
        if math.random() >= CatchUp.OfferChance(online) then return end
        local count = #CatchUp.Records(value)
        if count == 0 then return end
        -- Random delay: the requester collects offers for a few seconds anyway
        C_Timer.After(math.random() * self.OFFER_DELAY, function()
            Transport:SendDirect(TYPES.OFFER, { B36(count) }, sender)
        end)
    elseif kind == "p" then
        if RecentlyAnswered(sender) then return end
        answered[ns.Utils.CompactName(sender)] = ns.Utils.Now()
        local records = CatchUp.Records(value)
        records[#records + 1] = "E" .. B36(#records)
        Transport:SendDirect(TYPES.SNAPSHOT, records, sender)
        ns:Debug("Catch-up: sending", #records - 1, "record(s) to", sender)
    end
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

-- Seconds since our last logout, or nil without saved data (a fresh install)
function CatchUp.AwayFor(now)
    local savedAt = ns.db and tonumber(ns.db.meta.savedAt) or 0
    if not ns.Database.restoredFromDisk or savedAt <= 0 then return nil end
    return (now or ns.Utils.ServerTime()) - savedAt
end

-- Era: the automatic hello reaches guild and group only; after a real absence, offer
-- the realm-wide one (it needs the click). Returns true when shown, false when not
-- needed, nil while the channel is not joined yet.
function CatchUp:OfferRealmWide()
    local Transport = ns.Transport
    if not Transport:RealmWideNeedsClick() then return false end
    local away = CatchUp.AwayFor()
    if away and away < self.PROMPT_AWAY then return false end
    if not Transport:ChannelID() then return nil end
    local text = away and string.format(L.CATCHUP_PROMPT, ns.Utils.Ago(away)) or L.CATCHUP_PROMPT_NEW
    return ns.Alerts:Show({
        key = "catchup",
        throttle = 0,
        popup = {
            dialog = ns.Alerts.CATCHUP_POPUP,
            text = text,
            accept = L.CATCHUP_BUTTON,
            decline = L.REPORT_SKIP,
            onAccept = function() CatchUp:Start(true) end,
        },
    }) ~= false
end

-- Wait for a route (channel joined, guild known), then ask once
local function TryStart()
    if attempt == 0 then
        local reason = CatchUp.SkipReason()
        if reason then
            state = "done"
            CatchUp.last = { reports = 0, catches = 0, skipped = reason }
            ns:Debug("Catch-up: not needed (" .. reason .. ")")
            return
        end
    end
    attempt = attempt + 1
    if CatchUp:Start() then return end
    if attempt * CatchUp.RETRY < CatchUp.MAX_WAIT then
        C_Timer.After(CatchUp.RETRY, TryStart)
    else
        ns:Debug("Catch-up: no route (Classic Era: a guild, a group, or the Catch up click)")
    end
end

-- Era: offer the realm-wide catch-up once the channel is joined
local function TryOffer(tries)
    if CatchUp:OfferRealmWide() == nil and tries * CatchUp.RETRY < CatchUp.MAX_WAIT then
        C_Timer.After(CatchUp.RETRY, function() TryOffer(tries + 1) end)
    end
end

ns.Events:Register("HH_INITIALIZED", function()
    local Transport, TYPES = ns.Transport, ns.Protocol.TYPES
    Transport:RegisterHandler(TYPES.QUERY, function(record, sender) CatchUp:OnQuery(record, sender) end)
    Transport:RegisterHandler(TYPES.OFFER, function(record, sender) CatchUp:OnOffer(record, sender) end)
    Transport:RegisterHandler(TYPES.SNAPSHOT, function(record, sender) CatchUp:OnData(record, sender) end)
    since = CatchUp.Since() -- before this session's logout time is written
    C_Timer.After(CatchUp.START_DELAY, TryStart)
    C_Timer.After(CatchUp.START_DELAY, function() TryOffer(1) end)
end, OWNER)

-- A typed command is a hardware event: on Era the hello can go realm-wide
ns.SlashCommands:Register("catchup", function()
    if CatchUp:Start(true) then
        ns:Print(L.CATCHUP_STARTED)
    elseif state == "asking" or state == "pulling" then
        ns:Print(L.CATCHUP_BUSY)
    else
        ns:Print(L.CATCHUP_NO_ROUTE)
    end
end, L.HELP_CATCHUP)
