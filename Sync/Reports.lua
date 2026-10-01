-- HH-022: the shared set of death reports, and what enters it.
--
-- ns.db.reports is a grow-only set keyed by report id ("<victim key>:<time>"):
-- our own deaths plus every death other addon users of our faction reported
-- (origin "peer"), or passed on at login by another HeadHunter (origin "relay", HH-023).
-- Reports never change except to complete a given-name-only enemy. Everything the
-- rules derive (WANTED, ranks, badges; M3) is computed from this set, so the order
-- in which reports arrive never matters.
--
-- Own deaths (HH_DEATH_RECORDED) are added and broadcast. Simulated deaths are
-- added locally (so rules and UI can be tested) but never broadcast.
-- Peer reports are accepted only when:
--   - the sender IS the victim (nobody can report deaths on someone else's behalf)
--   - the time is plausible (not in the future, not older than MAX_AGE)
--   - the sender stays under a per-sender rate limit
--   - a test death (/hh sim send) comes from a character we trust (HH-123, Core/Dev.lua)
-- Fires HH_REPORT_ADDED(report) and HH_REPORT_UPDATED(report).

local addonName, ns = ...

local Reports = ns:RegisterModule("Reports", {})

local OWNER = "Reports"

Reports.MAX_AGE = 30 * 86400    -- WANTED lasts until caught or 7 days without a kill (HH-048)
Reports.MAX_COUNT = 5000
Reports.MAX_SKEW = 300          -- seconds a peer's clock may run ahead
Reports.SENDER_LIMIT = 10       -- reports accepted per sender per window
Reports.SENDER_WINDOW = 600

local senderLog = {}            -- compact sender -> array of GetTime() of accepted reports

local function Store()
    return ns.db and ns.db.reports
end

function Reports:Get(id)
    local store = Store()
    return id and store and store[id]
end

function Reports:Count()
    local total, mine, peers = 0, 0, 0
    for _, report in pairs(Store() or {}) do
        total = total + 1
        if report.origin == "local" or report.origin == "sim" then mine = mine + 1 else peers = peers + 1 end
    end
    return total, mine, peers
end

-- Iterate every report: for id, report in Reports:All()
function Reports:All()
    return pairs(Store() or {})
end

-- HH-123: another player's test death counts only when the one who sent it to us
-- is a character we trust. Our own simulations and demo data (origin "sim") always do.
function Reports.IsForeignTest(report, sender)
    return report.confidence == "sim" and report.origin ~= "sim" and not ns.Dev.Trusts(sender)
end

local function SentBy(report)
    return report.origin == "relay" and report.relayedBy or report.sender
end

function Reports:Prune(now)
    local store = Store()
    if not store then return end
    now = now or ns.Utils.ServerTime()
    local minTime = now - self.MAX_AGE
    local list = {}
    for id, report in pairs(store) do
        if type(report) ~= "table" or (tonumber(report.t) or 0) < minTime
                or Reports.IsForeignTest(report, SentBy(report)) then
            store[id] = nil
        else
            list[#list + 1] = report
        end
    end
    if #list > self.MAX_COUNT then
        table.sort(list, function(a, b) return a.t < b.t end)
        for i = 1, #list - self.MAX_COUNT do
            store[list[i].id] = nil
        end
    end
end

function Reports:Add(report, origin, sender)
    local store = Store()
    if not store or not report.id or store[report.id] then return nil end
    report.origin = origin
    report.sender = sender
    report.classification = report.classification or ns.Classify.Report(report)
    store[report.id] = report
    ns:Debug("Report added", report.id, "origin", origin)
    ns.Events:Fire("HH_REPORT_ADDED", report)
    return report
end

-------------------------------------------------
-- Outgoing
-------------------------------------------------

local function Broadcast(report)
    local record = ns.Protocol.EncodeDeath(report)
    if not record then
        ns:Debug("Report too large to send:", report.id)
        return
    end
    ns.Transport:Queue(ns.Protocol.TYPES.DEATH, record, ns.Transport.PRIORITY.alert, "D:" .. report.id)
end

function Reports:OnDeathRecorded(report)
    if report.confidence == "sim" then
        self:Add(report, "sim")
        return
    end
    if self:Add(report, "local") then
        Broadcast(report)
    end
end

-- A given-name-only enemy in one of OUR reports was completed: tell peers
local function BroadcastIdentity(report, enemy)
    ns.Transport:Queue(ns.Protocol.TYPES.IDENTITY, ns.Protocol.EncodeIdentity(report.id, enemy),
        ns.Transport.PRIORITY.bulk, "G:" .. report.id .. ":" .. enemy.guid)
end

-------------------------------------------------
-- Incoming
-------------------------------------------------

local function UnderRateLimit(sender)
    local id = ns.Utils.CompactName(sender)
    local now = ns.Utils.Now()
    local log = senderLog[id] or {}
    local recent = {}
    for _, at in ipairs(log) do
        if now - at < Reports.SENDER_WINDOW then recent[#recent + 1] = at end
    end
    if #recent >= Reports.SENDER_LIMIT then
        senderLog[id] = recent
        return false
    end
    recent[#recent + 1] = now
    senderLog[id] = recent
    return true
end

-- Canonical keys: the sender's client may format names differently than ours
local function Canonical(report)
    local U = ns.Utils
    report.victim.key = U.PlayerKey(report.victim.key)
    if not report.victim.key then return false end
    local enemies = { report.killer }
    for _, assist in ipairs(report.assists) do enemies[#enemies + 1] = assist end
    for _, enemy in ipairs(enemies) do
        if enemy.key then
            enemy.key = U.PlayerKey(enemy.key)
            if not enemy.key then return false end
            enemy.name = enemy.key
        end
    end
    report.id = report.victim.key .. ":" .. report.t
    return true
end

-- Remember why the last peer report was refused (shown by /hh sync)
local function Reject(...)
    Reports.lastRejected = ns.Join(...)
    ns:Debug("Peer report rejected:", Reports.lastRejected)
end

function Reports:OnPeerDeath(record, sender)
    local report = ns.Protocol.DecodeDeath(record)
    if not report or not Canonical(report) then
        Reject("malformed from", sender)
        return
    end
    if not ns.Utils.SameCharacter(sender, report.victim.key) then
        Reject("sender", sender, "is not the victim", report.victim.key)
        return
    end
    local now = ns.Utils.ServerTime()
    if report.t > now + self.MAX_SKEW or report.t < now - self.MAX_AGE then
        Reject("implausible time", report.t, "now", now, "from", sender)
        return
    end
    if Reports.IsForeignTest(report, sender) then
        Reject("test data from", sender)
        return
    end
    if self:Get(report.id) then return end
    if not UnderRateLimit(sender) then
        Reject("rate limit for", sender)
        return
    end
    self:Add(report, "peer", sender)
end

-- A report passed on by another HeadHunter during login catch-up (HH-023). It is
-- not from the victim, so it is taken on the relaying peer's word; the time checks
-- still apply. Returns the added report, or nil. relayedBy is kept apart from
-- report.sender, which is always the victim (the posse whisper goes there).
function Reports:AddRelayed(record, relayedBy)
    local report = ns.Protocol.DecodeDeath(record)
    if not report or not Canonical(report) then return nil end
    local now = ns.Utils.ServerTime()
    if report.t > now + self.MAX_SKEW or report.t < now - self.MAX_AGE then return nil end
    if Reports.IsForeignTest(report, relayedBy) then return nil end
    report.relayedBy = relayedBy
    return self:Add(report, "relay")
end

-- Reports to hand to a peer who missed them, newer than `since`, newest first, at
-- most `limit`. Local-only simulations (/hh spree, /hh sim death) stay here;
-- /hh sim send ones were shared already (report.shared). Test deaths of other
-- players are never passed on (HH-123).
function Reports:Since(since, limit)
    local list = {}
    for _, report in self:All() do
        local test = report.confidence == "sim" or report.origin == "sim"
        if report.t > since and (not test or (report.origin == "sim" and report.shared)) then
            list[#list + 1] = report
        end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    for i = #list, (limit or #list) + 1, -1 do list[i] = nil end
    return list
end

function Reports:OnPeerIdentity(record, sender)
    local reportId, identity = ns.Protocol.DecodeIdentity(record)
    if not reportId then return end
    local report = self:Get(reportId)
    -- Only the victim of that report may complete it
    if not report or report.origin == "local" or report.origin == "sim"
            or not ns.Utils.SameCharacter(sender, report.victim.key) then return end
    identity.key = ns.Utils.PlayerKey(identity.key)
    if not identity.key then return end
    self:Complete(report, identity)
end

-------------------------------------------------
-- Completing given-name-only enemies
-------------------------------------------------

-- identity: { guid, key, level?, class?, race?, sex? } (a cache record works too)
function Reports:Complete(report, identity)
    local changed = false
    local enemies = { report.killer }
    for _, assist in ipairs(report.assists or {}) do enemies[#enemies + 1] = assist end
    for _, enemy in ipairs(enemies) do
        if ns.DeathReports.CompleteEnemy(enemy, identity) then
            changed = true
        end
        -- Own reports share their table with ns.db.deaths, which DeathReports may
        -- have completed first; so send on "resolved and not sent yet", not on "changed"
        if report.origin == "local" and identity.guid and enemy.guid == identity.guid
                and enemy.key and not enemy.identitySent then
            enemy.identitySent = true
            BroadcastIdentity(report, enemy)
        end
    end
    -- Own reports may have been completed by DeathReports first (shared table):
    -- "involves the GUID" decides, not "changed here"
    if changed or (identity.guid and ns.DeathReports.Involves(report, identity.guid)) then
        report.classification = ns.Classify.Report(report)
        ns.Events:Fire("HH_REPORT_UPDATED", report)
    end
    return changed
end

function Reports:OnEnemyResolved(guid, record)
    for _, report in self:All() do
        self:Complete(report, record)
    end
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

ns.Events:Register("HH_INITIALIZED", function()
    local Events = ns.Events
    Reports:Prune()
    Events:Register("HH_DEATH_RECORDED", function(_, report) Reports:OnDeathRecorded(report) end, OWNER)
    Events:Register("HH_ENEMY_RESOLVED", function(_, guid, record) Reports:OnEnemyResolved(guid, record) end, OWNER)
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.DEATH, function(record, sender) Reports:OnPeerDeath(record, sender) end)
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.IDENTITY, function(record, sender) Reports:OnPeerIdentity(record, sender) end)
end, OWNER)

ns.SlashCommands:Register("reports", function()
    local total, mine, peers = Reports:Count()
    ns:Print(string.format(ns.L.REPORTS_HEADER, total, mine, peers))
    local list = {}
    for _, report in Reports:All() do list[#list + 1] = report end
    table.sort(list, function(a, b) return a.t > b.t end)
    local DR = ns.DeathReports
    for i = 1, math.min(10, #list) do
        local r = list[i]
        print(string.format("  %s  %s killed %s (%s, %s)  %s", date("%m-%d %H:%M", r.t),
            DR.DisplayName(r.killer), ns.Utils.DisplayName(r.victim.key), r.origin,
            tostring(r.confidence), ns.Utils.MapName(r.mapID) or "?"))
    end
end, ns.L.HELP_REPORTS)
