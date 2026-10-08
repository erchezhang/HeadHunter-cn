-- HH-118: player bounties, WANTED posters by players (docs/addon/features.md section 12).
--
-- A player killed in the last 24 hours puts a gold bounty on their killer (or an
-- assist): a reason from a list, 2g to 15g, 1 to 7 days, both from level 15. Any HeadHunter of their
-- faction whose killing blow brings the target down while the poster runs claims it,
-- and the owner pays by mail. HeadHunter never holds or moves gold without the
-- owner's click.
--
-- Two grow-only sets, like reports and catches:
--   ns.db.posters[id]     { id = owner:time, owner, target (enemy id), reason (1-4),
--                           gold (copper), until, t, sentAt (ours: gold sent) }
--   ns.db.bountyPay[id]   { posterId, hunter, status, claimedAt, t } by poster id
-- Protocol W (poster) is accepted only from the owner, only when the target killed or
-- helped kill the owner in a report we know, with 1 active poster per owner and 30 min
-- between posters. Protocol R (payment) only from the hunter: "claimed" at the catch,
-- "paid" when the hunter's mailbox shows the owner's gold, "unpaid" 3 days after the
-- claim without it. A later "paid" beats "unpaid"; the earliest claim wins a poster.
-- Blocked: an owner with an unpaid claim (author, 2026-09-28: one is enough), for 30
-- days from the newest one turning unpaid; every client derives it the same way, ignores the owner's
-- posters and lists them on the Deadbeats tab (author, 2026-09-28). Since HH-121 step 7
-- only a verified claim counts (Bounties:Verdict: another player saw the kill). The
-- other faction's Deadbeats come from the website (SiteData): their posters and
-- witnesses never reach us, so their claims cannot be verified here.
-- A claim is a catch (Sync/Justice.lua, record K) of the target by our own killing
-- blow, within the poster's time, not 10+ levels above the target. Everyone who saw
-- it earns +5 bounty points (Rules/Marks.lua). The hunter gets center text; on Era the
-- claim goes past guild and group only with [Announce] (a click), or /hh claim. The
-- owner gets an alert when the claim arrives (at login: a chat line), and pays at the
-- next mailbox.
-- Alts (HH-122): the addon cannot see accounts, so an alt on the other faction can
-- bring down its own main. One kill claims one poster (the largest), a hunter claims
-- on the same target at most once in 7 days, and an older repeat claim of the same
-- pair counts as a possible alt: its "unpaid" makes no Deadbeat.
-- Fires HH_BOUNTY_UPDATED() when a poster or payment changes.

local addonName, ns = ...
local L = ns.L

local Bounties = ns:RegisterModule("Bounties", {})

local OWNER = "Bounties"
local DAY = 86400

Bounties.REASONS = { "camped", "mobs", "lowlevel", "group" }
Bounties.DAYS = { 1, 2, 3, 7 }
Bounties.MIN_GOLD = 2 * 10000        -- copper (author, 2026-09-28: 2g to 15g on the beta)
Bounties.MAX_GOLD = 15 * 10000
Bounties.MIN_LEVEL = 15              -- the owner's level at the death (author, 2026-09-28)
Bounties.MIN_TARGET_LEVEL = 15       -- the enemy's level at that death (author, 2026-09-28)
Bounties.MAX_DURATION = 7 * DAY
Bounties.POST_WINDOW = DAY           -- our deaths from the last 24 hours
Bounties.POST_COOLDOWN = 1800        -- between two posters of one owner
Bounties.UNPAID_AFTER = 3 * DAY
Bounties.BLOCK_HUNTERS = 1
Bounties.BLOCK_WINDOW = 30 * DAY
Bounties.CLAIM_MARKS = 5
Bounties.CLAIM_RECENT = 300          -- a catch this old still makes our claim
Bounties.PAIR_COOLDOWN = 7 * DAY     -- one claim per hunter and target (HH-122)
Bounties.MAX_SKEW = 300
Bounties.SENDER_LIMIT = 5
Bounties.SENDER_WINDOW = 600
Bounties.CHECK = 60                  -- seconds between unpaid checks

local STATUS_RANK = { claimed = 1, unpaid = 2, paid = 3 }

local senderLog = {}
local lastClaimMarks = {}            -- target id -> GetTime()
local payQueue = {}                  -- poster ids the owner is asked to pay at this mailbox
local toAnnounce = {}                -- Era: our claims waiting for the [Announce] click

local function Posters()
    return ns.db and ns.db.posters
end

local function Payments()
    return ns.db and ns.db.bountyPay
end

local function Me()
    return ns.Utils.UnitKey("player")
end

local function Changed()
    ns.Events:Fire("HH_BOUNTY_UPDATED")
end

function Bounties:Get(id)
    local store = Posters()
    return id and store and store[id]
end

function Bounties:All()
    return pairs(Posters() or {})
end

-- Ours and the website's running ones we never heard in game (SiteData): shown and
-- claimable. A claimed one is kept in ns.db with origin "website" (Bounties:OnCatch),
-- never passed on at catch-up or uploaded
function Bounties:Listed()
    local list = {}
    for id, poster in pairs(ns.SiteData:Posters()) do list[id] = poster end
    for id, poster in pairs(Posters() or {}) do list[id] = poster end
    return pairs(list)
end

function Bounties:Payment(posterId)
    local store = Payments()
    return posterId and store and store[posterId]
end

-- The owner's key from a poster id ("<owner>:<time>"; keys never hold a colon)
function Bounties.OwnerOf(posterId)
    return posterId and posterId:match("^(.+):%d+$")
end

-------------------------------------------------
-- Rules (pure over the two sets)
-------------------------------------------------

-- The hunter's newest claim on this target before this one (time, then poster id, so
-- every client orders the same), or nil
function Bounties:PriorClaim(hunter, target, claimedAt, posterId)
    posterId = posterId or ""
    local newest
    for otherId, pay in pairs(Payments() or {}) do
        local poster = self:Get(otherId)
        if otherId ~= posterId and poster and poster.target == target and ns.Utils.SameCharacter(pay.hunter, hunter)
                and (pay.claimedAt < claimedAt or (pay.claimedAt == claimedAt and otherId < posterId))
                and (not newest or pay.claimedAt > newest) then
            newest = pay.claimedAt
        end
    end
    return newest
end

-- The same hunter claimed on the same target less than 7 days before: no claim
function Bounties:IsRepeat(hunter, target, claimedAt, posterId)
    local prior = self:PriorClaim(hunter, target, claimedAt, posterId)
    return prior ~= nil and claimedAt - prior < self.PAIR_COOLDOWN
end

-- The hunter claimed on this target before: maybe the target's own alt
function Bounties:LooksLikeAlt(posterId)
    local poster, pay = self:Get(posterId), self:Payment(posterId)
    return poster ~= nil and pay ~= nil and self:PriorClaim(pay.hunter, poster.target, pay.claimedAt, posterId) ~= nil
end

-- The hunter's first claim we know of
function Bounties:FirstClaim(posterId)
    local pay = self:Payment(posterId)
    if not pay then return false end
    for otherId, other in pairs(Payments() or {}) do
        if otherId ~= posterId and ns.Utils.SameCharacter(other.hunter, pay.hunter) and other.claimedAt <= pay.claimedAt then
            return false
        end
    end
    return true
end

-- An unpaid claim that counts against the owner (HH-121 step 7): not maybe an alt, and
-- verified by another player's data (Bounties:Verdict)
local function CountsAsUnpaid(posterId, pay)
    return pay.status == "unpaid" and ns.Relay.Counts(pay) and not Bounties:LooksLikeAlt(posterId)
        and Bounties:CachedVerdict(posterId) == "verified"
end

-- Per owner: the newest unpaid time of each hunter, newest first
local function UnpaidTimes(owner)
    local byHunter = {}
    for posterId, pay in pairs(Payments() or {}) do
        if ns.Utils.SameCharacter(Bounties.OwnerOf(posterId), owner) and CountsAsUnpaid(posterId, pay) then
            local hunter = ns.Utils.CompactName(pay.hunter)
            if hunter then byHunter[hunter] = math.max(byHunter[hunter] or 0, pay.t) end
        end
    end
    local times = {}
    for _, t in pairs(byHunter) do times[#times + 1] = t end
    return times
end

-- Only unpaid claims known by `now` (a poster checked at its own time)
local function UnpaidBy(owner, now)
    local times = {}
    for _, t in ipairs(UnpaidTimes(owner)) do
        if t <= now + Bounties.MAX_SKEW then times[#times + 1] = t end
    end
    table.sort(times, function(a, b) return a > b end)
    table.sort(times, function(a, b) return a > b end)
    return times
end

-- When the owner's block ends: 30 days after the newest unpaid (of BLOCK_HUNTERS hunters)
-- (counted from the newest), or nil when they are not blocked
function Bounties:BlockedUntil(owner, now)
    if not owner then return nil end
    now = now or ns.Utils.ServerTime()
    local t = UnpaidBy(owner, now)[self.BLOCK_HUNTERS]
    local ours = t and now < t + self.BLOCK_WINDOW and t + self.BLOCK_WINDOW or nil
    -- The website's list (HH-082 data): Classic Era learns the other faction's this way
    local site = ns.SiteData:Deadbeat(owner)
    local theirs = site and now < site.blockedUntil and site.blockedUntil or nil
    if ours and theirs then return math.max(ours, theirs) end
    return ours or theirs
end

function Bounties:IsBlocked(owner, now)
    return self:BlockedUntil(owner, now) ~= nil
end

-- The Deadbeats tab (author, 2026-09-28): every blocked owner we know of, longest block
-- first: { owner, faction, unpaid, blockedUntil }; faction is the one of the records'
-- sender (the other faction's records keep theirs, ours have none), the race's for a
-- known enemy, else nil
function Bounties:Shamed(now)
    now = now or ns.Utils.ServerTime()
    local seen, list = {}, {}
    local owners, sides = {}, {}
    for posterId, pay in pairs(Payments() or {}) do
        local owner = self.OwnerOf(posterId)
        owners[#owners + 1] = owner
        sides[owner] = sides[owner] or (type(pay) == "table" and pay.faction) or ns.Utils.UnitFaction("player")
    end
    for _, site in pairs(ns.SiteData:Deadbeats()) do owners[#owners + 1] = site.key end
    for _, owner in ipairs(owners) do
        local id = ns.Utils.CompactName(owner)
        if id and not seen[id] then
            seen[id] = true
            local untilT = self:BlockedUntil(owner, now)
            if untilT then
                local _, unpaid = self:Standing(owner)
                local known = ns.Wanted:Get(id)
                local faction = sides[owner] or (known and ns.Utils.RaceFaction(known.race)) or nil
                list[#list + 1] = { owner = owner, faction = faction, unpaid = math.max(unpaid, #UnpaidTimes(owner)),
                    blockedUntil = untilT }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.blockedUntil ~= b.blockedUntil then return a.blockedUntil > b.blockedUntil end
        return a.owner < b.owner
    end)
    return list
end

-- How the owner pays: paid and unpaid claims (all we know of; the website's count when higher)
function Bounties:Standing(owner)
    local paid, unpaid = 0, 0
    for posterId, pay in pairs(Payments() or {}) do
        if ns.Utils.SameCharacter(self.OwnerOf(posterId), owner) then
            if pay.status == "paid" then
                paid = paid + 1
            elseif CountsAsUnpaid(posterId, pay) then
                unpaid = unpaid + 1
            end
        end
    end
    local site = ns.SiteData:Deadbeat(owner)
    if site then unpaid = math.max(unpaid, site.unpaid) end
    return paid, unpaid
end

-------------------------------------------------
-- Verdict (HH-121 step 6)
-------------------------------------------------

Bounties.WITNESS_WINDOW = 60         -- a death this close to the claim is the claimed one
Bounties.CONFIRM_WAIT = 30           -- after our claim, the witnesses' time (Witness.SEND_DELAY) and more

-- Did the target die (a witness record or their own report) after `from` and before `to`?
local function DiedBetween(target, from, to)
    for _, w in ipairs(ns.Witness:Of(target, (from + to) / 2, (to - from) / 2)) do
        if w.t > from and w.t < to then return true end
    end
    for _, report in ns.Reports:All() do
        if report.t > from and report.t < to and ns.Utils.SameCharacter(report.victim and report.victim.key, target) then
            return true
        end
    end
    return false
end

-- Is the hunter named in the report (the killer or an assist)?
local function Names(report, hunter)
    local U = ns.Utils
    if report.killer and U.SameCharacter(report.killer.key, hunter) then return true end
    for _, assist in ipairs(report.assists or {}) do
        if U.SameCharacter(assist.key, hunter) then return true end
    end
    return false
end

-- How sure we are that a claim happened, from other players' data only (the hunter's
-- own data never counts for or against it):
--   "verified"    a witness saw the target die then (within WITNESS_WINDOW), or the
--                 target's own death report names the hunter
--   "rejected"    a sighting before the claim, a witness or the target's own report
--                 puts the target farther from the claim's place than they could go
--                 (Utils.TooFar); the place is the hunter's own witness record
--   "unverified"  nothing either way, or evidence both ways (one liar must not make
--                 an honest owner a Deadbeat, nor cost an honest hunter the gold)
-- Returns the verdict and who it rests on (a witness, spotter or the target), or nil.
function Bounties:Verdict(posterId)
    local poster, pay = self:Get(posterId), self:Payment(posterId)
    if not (poster and pay) then return nil end
    local U, Relay = ns.Utils, ns.Relay
    local target, hunter, at = poster.target, pay.hunter, pay.claimedAt
    local function Other(record, by) return Relay.Counts(record) and not U.SameCharacter(by, hunter) end

    local place
    for _, w in ipairs(ns.Witness:Of(target, at, self.WITNESS_WINDOW)) do
        if U.SameCharacter(w.by, hunter) and Relay.Counts(w) then place = U.WorldPos(w.mapID, w.x, w.y) end
    end
    local function Far(mapID, x, y, t)
        return place ~= nil and U.TooFar(place, U.WorldPos(mapID, x, y), math.abs(t - at))
    end

    local verifiedBy, rejectedBy
    for _, w in ipairs(ns.Witness:Of(target, at, self.WITNESS_WINDOW)) do
        if Other(w, w.by) then
            if Far(w.mapID, w.x, w.y, w.t) then
                rejectedBy = rejectedBy or w.by
            else
                verifiedBy = verifiedBy or w.by
            end
        end
    end
    for _, report in ns.Reports:All() do
        if math.abs(report.t - at) <= self.WITNESS_WINDOW and U.SameCharacter(report.victim and report.victim.key, target)
                and Other(report, target) then
            if Names(report, hunter) then
                verifiedBy = verifiedBy or target
            elseif Far(report.mapID, report.x, report.y, report.t) then
                rejectedBy = rejectedBy or target
            end
        end
    end
    -- Seen alive before the claim, with no death in between (a release can move a
    -- player to a graveyard, so later sightings prove nothing)
    local sightings = {}
    for _, s in ipairs(ns.Spotted:Sightings(target)) do sightings[#sightings + 1] = s end
    for _, s in ipairs(ns.Evidence:Of(target, at)) do sightings[#sightings + 1] = s end
    for _, s in ipairs(sightings) do
        if s.t <= at and at - s.t <= ns.Evidence.WINDOW and Other(s, s.by) and Far(s.mapID, s.x, s.y, s.t)
                and not DiedBetween(target, s.t, at - self.WITNESS_WINDOW) then
            rejectedBy = rejectedBy or s.by
        end
    end

    if verifiedBy and rejectedBy then return "unverified" end
    if verifiedBy then return "verified", verifiedBy end
    if rejectedBy then return "rejected", rejectedBy end
    return "unverified"
end

local verdicts = {}                  -- poster id -> { verdict, by }, the last one worked out

-- The claim's verdict, worked out once and kept until new evidence or a new payment
-- (the Deadbeat checks ask often: tooltips, nameplates). Returns the verdict and who.
function Bounties:CachedVerdict(posterId)
    local cached = verdicts[posterId]
    if not cached then
        local verdict, by = self:Verdict(posterId)
        cached = { verdict or "unverified", by }
        verdicts[posterId] = cached
    end
    return cached[1], cached[2]
end

-- The owner and the hunter hear when a claim is rejected
local function TellRejected(posterId, by)
    local poster, pay = Bounties:Get(posterId), Bounties:Payment(posterId)
    if not (poster and pay) then return end
    local U, me = ns.Utils, Me()
    local hunter, target, spotter = U.DisplayName(pay.hunter), Bounties.TargetName(poster.target), U.DisplayName(by) or by
    local text
    if U.SameCharacter(poster.owner, me) then
        text = string.format(L.BOUNTY_REJECTED_OWNER, hunter, target, spotter)
    elseif U.SameCharacter(pay.hunter, me) then
        text = string.format(L.BOUNTY_REJECTED_HUNTER, target, spotter)
    end
    if text then ns.Alerts:Show({ key = "bounty-rejected:" .. posterId, throttle = 0, chat = text }) end
end

-- New evidence on a target: work the verdicts of the claims on them out again, and
-- tell the UI when one changed. target nil: every claim.
function Bounties:RefreshVerdicts(target)
    local changed = false
    for posterId in pairs(Payments() or {}) do
        local poster = self:Get(posterId)
        if poster and (not target or poster.target == target) then
            local before = verdicts[posterId] and verdicts[posterId][1]
            verdicts[posterId] = nil
            local verdict, by = self:CachedVerdict(posterId)
            if before ~= nil and before ~= verdict then
                changed = true
                if verdict == "rejected" then TellRejected(posterId, by) end
            end
        end
    end
    if changed then Changed() end
end

-- Running: not run out, not claimed, the owner not blocked; a relayed poster only
-- once a second source has it (HH-121)
function Bounties:IsActive(poster, now)
    now = now or ns.Utils.ServerTime()
    return poster ~= nil and now < poster["until"] and ns.Relay.Counts(poster) and not self:Payment(poster.id)
        and not self:IsBlocked(poster.owner, now)
end

-- The running posters on one enemy id, newest first
function Bounties:ActiveFor(targetId, now)
    local list = {}
    if not targetId then return list end
    for _, poster in self:Listed() do
        if poster.target == targetId and self:IsActive(poster, now) then list[#list + 1] = poster end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

-- An enemy entry with at least one running poster
function Bounties:ActiveOn(entry, now)
    return entry ~= nil and #self:ActiveFor(entry.id, now) > 0
end

-- Merged per target: { target, posters, count, gold, newest } or nil
function Bounties:Summary(targetId, now)
    local posters = self:ActiveFor(targetId, now)
    if #posters == 0 then return nil end
    local gold = 0
    for _, poster in ipairs(posters) do gold = gold + poster.gold end
    return { target = targetId, posters = posters, count = #posters, gold = gold, newest = posters[1] }
end

-- Every target with a running poster, newest poster first
function Bounties:Board(now)
    local byTarget, list = {}, {}
    for _, poster in self:Listed() do
        if not byTarget[poster.target] and self:IsActive(poster, now) then
            byTarget[poster.target] = true
            list[#list + 1] = self:Summary(poster.target, now)
        end
    end
    table.sort(list, function(a, b) return a.newest.t > b.newest.t end)
    return list
end

-- The owner's running poster, if any
function Bounties:ActiveOf(owner, now)
    for _, poster in self:All() do
        if ns.Utils.SameCharacter(poster.owner, owner) and self:IsActive(poster, now) then return poster end
    end
    return nil
end

-- The victim's level at that death decides, on every client the same way
function Bounties.OldEnough(report)
    return (tonumber(report.victim and report.victim.level) or 0) >= Bounties.MIN_LEVEL
end

-- The enemy's level in that report: MIN_TARGET_LEVEL or higher, a skull (-1) or unknown
function Bounties.TargetOldEnough(enemy)
    local level = tonumber(enemy and enemy.level)
    return not level or level < 1 or level >= Bounties.MIN_TARGET_LEVEL
end

-- True when the target killed or helped kill the owner at or before `at`, within the
-- post window, while the owner and the target were both old enough
function Bounties.KilledBy(owner, target, at)
    local Engine = ns.RulesEngine
    for _, report in ns.Reports:All() do
        if report.t <= at + Bounties.MAX_SKEW and at - report.t <= Bounties.POST_WINDOW + Bounties.MAX_SKEW
                and ns.Utils.SameCharacter(report.victim and report.victim.key, owner)
                and Bounties.OldEnough(report) then
            if Engine.EnemyId(report.killer) == target and Bounties.TargetOldEnough(report.killer) then return true end
            for _, assist in ipairs(report.assists or {}) do
                if Engine.EnemyId(assist) == target and Bounties.TargetOldEnough(assist) then return true end
            end
        end
    end
    return false
end

-- Why a poster breaks the owner limits: "active", "cooldown", "blocked" or nil
function Bounties:OwnerLimit(poster)
    if self:IsBlocked(poster.owner, poster.t) then return "blocked" end
    for _, other in self:All() do
        if other.id ~= poster.id and ns.Utils.SameCharacter(other.owner, poster.owner) then
            if other.t <= poster.t and other["until"] > poster.t and not self:Payment(other.id) then return "active" end
            if math.abs(poster.t - other.t) < self.POST_COOLDOWN then return "cooldown" end
        end
    end
    return nil
end

-------------------------------------------------
-- Storing
-------------------------------------------------

function Bounties:Add(poster, origin, sender)
    local store = Posters()
    if not store or not poster.id or store[poster.id] then return nil end
    poster.origin = origin
    poster.sender = sender
    store[poster.id] = poster
    ns:Debug("Poster added", poster.id, "origin", origin)
    Changed()
    return poster
end

-- Keeps the strongest status of the earliest claim. Returns the stored payment when it changed.
function Bounties:AddPayment(pay, origin)
    local store = Payments()
    if not store or not pay.posterId then return nil end
    local have = store[pay.posterId]
    if have then
        local sameHunter = ns.Utils.SameCharacter(have.hunter, pay.hunter)
        if sameHunter and (STATUS_RANK[pay.status] or 0) <= (STATUS_RANK[have.status] or 0) then return nil end
        if not sameHunter and pay.claimedAt >= have.claimedAt then return nil end
        -- An unconfirmed relay never takes a claim away from another hunter (HH-121)
        if not sameHunter and ns.Relay.Counts(have) and not ns.Relay.Counts(pay) then return nil end
    end
    pay.origin = origin
    store[pay.posterId] = pay
    verdicts[pay.posterId] = nil
    ns:Debug("Bounty payment", pay.posterId, pay.status, "origin", origin)
    Changed()
    return pay
end

function Bounties:Prune(now)
    now = now or ns.Utils.ServerTime()
    local keepFrom = now - self.BLOCK_WINDOW - self.MAX_DURATION
    for id, poster in pairs(Posters() or {}) do
        if type(poster) ~= "table" or (tonumber(poster["until"]) or 0) < keepFrom then Posters()[id] = nil end
    end
    for id, pay in pairs(Payments() or {}) do
        if type(pay) ~= "table" or (tonumber(pay.claimedAt) or 0) < keepFrom then Payments()[id] = nil end
    end
end

local function Broadcast(typeCode, record, coalesceKey, realmWide)
    local Transport = ns.Transport
    Transport:Queue(typeCode, record, Transport.PRIORITY.alert, coalesceKey)
    -- Era: the realm-wide channel only inside a click (posting is one)
    if realmWide and Transport:RealmWideNeedsClick() then Transport:SendRealmWide(typeCode, { record }) end
end

local function SendPayment(pay)
    Broadcast(ns.Protocol.TYPES.PAYMENT, ns.Protocol.EncodePayment(pay), "R:" .. pay.posterId .. ":" .. pay.status)
end

-------------------------------------------------
-- Posting (ours)
-------------------------------------------------

-- Enemies who killed us or helped in the last 24 hours, newest death first:
-- { id, enemy, report }, one per enemy id
function Bounties:PostableTargets(now)
    now = now or ns.Utils.ServerTime()
    local deaths = ns.DeathReports:Mine()
    local Engine = ns.RulesEngine
    local list, seen = {}, {}
    for i = #deaths, 1, -1 do
        local report = deaths[i]
        if type(report) == "table" and report.t >= now - self.POST_WINDOW and report.confidence ~= "sim" then
            local enemies = { report.killer }
            for _, assist in ipairs(report.assists or {}) do enemies[#enemies + 1] = assist end
            for _, enemy in ipairs(enemies) do
                local id = Engine.EnemyId(enemy)
                if id and not seen[id] then
                    seen[id] = true
                    list[#list + 1] = { id = id, enemy = enemy, report = report }
                end
            end
        end
    end
    return list
end

-- Can we post on this enemy now? true, or false and the reason key
function Bounties:CanPost(targetId, now)
    now = now or ns.Utils.ServerTime()
    local me = Me()
    if not me then return false, "unknown" end
    local killer, oldEnough, targetOldEnough = false, false, false
    for _, target in ipairs(self:PostableTargets(now)) do
        if target.id == targetId then
            killer = true
            oldEnough = oldEnough or self.OldEnough(target.report)
            targetOldEnough = targetOldEnough or self.TargetOldEnough(target.enemy)
        end
    end
    if not killer then return false, "notkiller" end
    if not oldEnough then return false, "level" end
    if not targetOldEnough then return false, "targetlevel" end
    local limit = self:OwnerLimit({ id = "", owner = me, t = now })
    if limit then return false, limit end
    return true
end

-- Post a bounty (a click: the dialog's Post button). gold in whole gold, days one of
-- DAYS. Returns the poster, or nil and the reason key.
function Bounties:Post(targetId, reason, gold, days)
    local now = ns.Utils.ServerTime()
    local ok, why = self:CanPost(targetId, now)
    if not ok then return nil, why end
    if not self.REASONS[tonumber(reason) or 0] then return nil, "reason" end
    local copper = math.floor((tonumber(gold) or 0) * 10000)
    if copper < self.MIN_GOLD then return nil, "gold" end
    if copper > self.MAX_GOLD then return nil, "toomuch" end
    days = tonumber(days)
    local validDays = false
    for _, d in ipairs(self.DAYS) do
        if d == days then validDays = true end
    end
    if not validDays then return nil, "days" end
    local me = Me()
    local poster = { id = me .. ":" .. now, owner = me, target = targetId, reason = tonumber(reason), gold = copper,
        ["until"] = now + days * DAY, t = now }
    self:Add(poster, "local")
    Broadcast(ns.Protocol.TYPES.POSTER, ns.Protocol.EncodePoster(poster), "W:" .. poster.id, true)
    ns:Print(string.format(L.BOUNTY_POSTED, self.Gold(copper), self.TargetName(targetId), days))
    return poster
end

-------------------------------------------------
-- Peers
-------------------------------------------------

local function UnderRateLimit(sender)
    local id = ns.Utils.CompactName(sender)
    local now = ns.Utils.Now()
    local recent = {}
    for _, at in ipairs(senderLog[id] or {}) do
        if now - at < Bounties.SENDER_WINDOW then recent[#recent + 1] = at end
    end
    senderLog[id] = recent
    if #recent >= Bounties.SENDER_LIMIT then return false end
    recent[#recent + 1] = now
    return true
end

-- Canonical keys and the checks every poster passes, however it came
local function ValidPoster(poster)
    local U = ns.Utils
    poster.owner = U.PlayerKey(poster.owner)
    if not poster.owner then return false end
    if not poster.target:find("^guid:") then
        poster.target = U.PlayerKey(poster.target)
        if not poster.target then return false end
    end
    poster.id = poster.owner .. ":" .. poster.t
    local now = U.ServerTime()
    if poster.t > now + Bounties.MAX_SKEW or poster.t < now - Bounties.BLOCK_WINDOW then return false end
    local duration = poster["until"] - poster.t
    if duration <= 0 or duration > Bounties.MAX_DURATION + Bounties.MAX_SKEW then return false end
    if poster.gold < Bounties.MIN_GOLD or poster.gold > Bounties.MAX_GOLD then return false end
    if not Bounties.REASONS[poster.reason] then return false end
    return true
end

function Bounties:OnPeerPoster(record, sender)
    local poster = ns.Protocol.DecodePoster(record)
    if not poster or not ValidPoster(poster) then return nil end
    if not ns.Utils.SameCharacter(sender, poster.owner) then return nil end
    local have = self:Get(poster.id)
    if have then
        -- The owner's own copy of a poster we only had relayed (HH-121)
        if ns.Relay.Confirm(have, "peer", sender) then Changed() end
        return nil
    end
    -- Only your own killer: nobody can post an innocent player
    if not self.KilledBy(poster.owner, poster.target, poster.t) then return nil end
    if self:OwnerLimit(poster) or not UnderRateLimit(sender) then return nil end
    return self:Add(poster, "peer", sender)
end

-- Passed on at login catch-up (HH-023): stored on the relaying peer's word, as reports
-- are, but active only once a second source has it (HH-121, Sync/Relay.lua)
function Bounties:AddRelayedPoster(record, sender)
    local poster = ns.Protocol.DecodePoster(record)
    if not poster or not ValidPoster(poster) then return nil end
    local have = self:Get(poster.id)
    if have then
        if ns.Relay.Vouch(have, sender, have.owner) then Changed() end
        return nil
    end
    poster.origin = "relay"
    ns.Relay.Vouch(poster, sender, poster.owner)
    return self:Add(poster, "relay", sender)
end

local function ValidPayment(pay)
    local U = ns.Utils
    pay.hunter = U.PlayerKey(pay.hunter)
    if not pay.hunter or not Bounties.OwnerOf(pay.posterId) then return false end
    local now = U.ServerTime()
    if pay.claimedAt > now + Bounties.MAX_SKEW or pay.claimedAt < now - Bounties.BLOCK_WINDOW - Bounties.MAX_DURATION then
        return false
    end
    local poster = Bounties:Get(pay.posterId)
    if poster and (pay.claimedAt < poster.t or pay.claimedAt > poster["until"] + Bounties.MAX_SKEW) then return false end
    -- Nobody claims their own bounty
    if U.SameCharacter(pay.hunter, Bounties.OwnerOf(pay.posterId)) then return false end
    if poster and Bounties:IsRepeat(pay.hunter, poster.target, pay.claimedAt, pay.posterId) then return false end
    return true
end

-- Our poster was claimed: tell us who brought the target down and that we owe gold
function Bounties:NotifyOwner(pay)
    local poster = self:Get(pay.posterId)
    if not (poster and pay.status == "claimed" and ns.Relay.Counts(pay) and ns.Utils.SameCharacter(poster.owner, Me())) then
        return
    end
    local U = ns.Utils
    local hunter, target = U.DisplayName(pay.hunter), self.TargetName(poster.target)
    local alert = { key = "bounty-owner:" .. poster.id, throttle = 0,
        chat = string.format(L.BOUNTY_OWNER_CHAT, hunter, target, self.Gold(poster.gold), self.ReasonText(poster.reason)) }
    -- Learned at login (catch-up): the chat line is enough
    if pay.origin ~= "relay" then
        alert.text = string.format(L.BOUNTY_OWNER_CENTER, hunter, target)
        alert.sound = true
    end
    ns.Alerts:Show(alert)
end

-- faction: the sender's. The other faction's records are not ours (HH-121: their
-- Deadbeats come from the website; Transport drops them already).
function Bounties:OnPeerPayment(record, sender, faction)
    local pay = ns.Protocol.DecodePayment(record)
    if not pay or not ValidPayment(pay) then return nil end
    if faction ~= nil and faction ~= ns.Utils.UnitFaction("player") then return nil end
    -- Only the hunter: they are the one who gets the gold
    if not ns.Utils.SameCharacter(sender, pay.hunter) or not UnderRateLimit(sender) then return nil end
    -- The hunter's own copy of a payment we only had relayed (HH-121)
    local have = self:Payment(pay.posterId)
    if have and have.status == pay.status and ns.Utils.SameCharacter(have.hunter, pay.hunter)
            and ns.Relay.Confirm(have, "peer", sender) then
        Changed()
        self:NotifyOwner(have)
        return have
    end
    local added = self:AddPayment(pay, "peer")
    if added then self:NotifyOwner(added) end
    return added
end

-- Passed on at login catch-up: it counts for Deadbeats, and the owner is asked to pay,
-- only once a second source has it (HH-121, Sync/Relay.lua)
function Bounties:AddRelayedPayment(record, sender)
    local pay = ns.Protocol.DecodePayment(record)
    if not pay or not ValidPayment(pay) then return nil end
    local have = self:Payment(pay.posterId)
    if have and have.status == pay.status and ns.Utils.SameCharacter(have.hunter, pay.hunter) then
        if ns.Relay.Vouch(have, sender, have.hunter) then
            Changed()
            self:NotifyOwner(have)
        end
        return nil
    end
    pay.origin = "relay"
    ns.Relay.Vouch(pay, sender, pay.hunter)
    local added = self:AddPayment(pay, "relay")
    if added then self:NotifyOwner(added) end
    return added
end

-- Posters and payments to pass on at catch-up: "W..." and "R..." records
function Bounties:Records(since)
    local Protocol, records = ns.Protocol, {}
    local now = ns.Utils.ServerTime()
    for _, poster in self:All() do
        if poster.t > since and poster["until"] > now and poster.origin ~= "website" then
            records[#records + 1] = "W" .. Protocol.EncodePoster(poster)
        end
    end
    for _, pay in pairs(Payments() or {}) do
        if pay.t > since then records[#records + 1] = "R" .. Protocol.EncodePayment(pay) end
    end
    return records
end

-------------------------------------------------
-- Claiming (the hunter)
-------------------------------------------------

-- A catch was stored: our killing blow on a posted target claims its posters
function Bounties:OnCatch(record)
    local U = ns.Utils
    local me = Me()
    if not (me and record.killer and U.SameCharacter(record.killer, me)) then return end
    local now = U.ServerTime()
    if now - record.t > self.CLAIM_RECENT then return end
    local entry = ns.Wanted:Get(record.outlaw)
    -- One kill claims one poster: the largest, then the oldest; the others stay open
    local best
    for _, poster in ipairs(self:ActiveFor(record.outlaw, record.t)) do
        if record.t >= poster.t and not U.SameCharacter(poster.owner, me)
                and (not best or poster.gold > best.gold or (poster.gold == best.gold and poster.t < best.t)) then
            best = poster
        end
    end
    if not best then return end
    if entry and ns.Marks.HuntingDown(entry) then
        ns:Print(string.format(L.BOUNTY_NO_CLAIM_LEVEL, self.TargetName(record.outlaw)))
        return
    end
    if self:IsRepeat(me, record.outlaw, record.t, best.id) then
        ns:Print(string.format(L.BOUNTY_NO_CLAIM_REPEAT, self.TargetName(record.outlaw)))
        return
    end
    -- A website bounty is kept once claimed: the website stops listing it, and the claim
    -- line and the paid check at the mailbox still need it
    if not self:Get(best.id) and Posters() then
        local copy = {}
        for k, v in pairs(best) do copy[k] = v end
        Posters()[best.id] = copy
    end
    local claimed = { best }
    local lines, gold = {}, 0
    for _, poster in ipairs(claimed) do
        local pay = { posterId = poster.id, hunter = me, status = "claimed", claimedAt = record.t, t = now }
        if self:AddPayment(pay, "local") then
            SendPayment(pay)
            if ns.Transport:RealmWideNeedsClick() then toAnnounce[#toAnnounce + 1] = pay.posterId end
            lines[#lines + 1] = string.format(L.BOUNTY_CLAIMED, self.Gold(poster.gold), U.DisplayName(poster.owner))
            gold = gold + poster.gold
            -- HH-121: once the witnesses had their time, say when nobody else saw it
            local posterId, target = poster.id, self.TargetName(record.outlaw)
            C_Timer.After(self.CONFIRM_WAIT, function()
                if self:CachedVerdict(posterId) == "unverified" then ns:Print(string.format(L.BOUNTY_CLAIM_UNCONFIRMED, target)) end
            end)
        end
    end
    if #lines == 0 then return end
    local alert = { key = "bounty-claim:" .. record.id, throttle = 0, sound = true,
        text = string.format(L.BOUNTY_CLAIMED_CENTER, self.Gold(gold), self.TargetName(record.outlaw)),
        chat = table.concat(lines, "\n") }
    -- Era: the owner may be outside our guild and group; the realm hears it only through a click
    if #toAnnounce > 0 then
        alert.popup = {
            dialog = ns.Alerts.BOUNTY_POPUP,
            text = alert.chat .. "\n\n" .. L.BOUNTY_ANNOUNCE_QUESTION,
            accept = L.JUSTICE_ANNOUNCE,
            decline = CLOSE or "Close",
            onAccept = function() Bounties:Announce() end,
            onDecline = function() Bounties:SkipAnnounce() end,
        }
    end
    ns.Alerts:Show(alert)
end

function Bounties:PendingAnnounce()
    return #toAnnounce
end

-- Era: our claims to the whole realm. Must run inside a hardware event (the popup
-- button or a typed /hh claim).
function Bounties:Announce()
    local records = {}
    for _, posterId in ipairs(toAnnounce) do
        local pay = self:Payment(posterId)
        if pay then records[#records + 1] = ns.Protocol.EncodePayment(pay) end
    end
    wipe(toAnnounce)
    if #records == 0 then return 0 end
    local sent = ns.Transport:SendRealmWide(ns.Protocol.TYPES.PAYMENT, records)
    ns:Print(sent > 0 and L.BOUNTY_ANNOUNCED or L.REPORT_FAILED)
    return sent
end

function Bounties:SkipAnnounce()
    wipe(toAnnounce)
end

-- Everyone who saw the catch of a posted target: +5 bounty points
function Bounties:OnWitnessed(entry)
    if not self:ActiveOn(entry) then return end
    local now = ns.Utils.Now()
    if lastClaimMarks[entry.id] and now - lastClaimMarks[entry.id] < 60 then return end
    lastClaimMarks[entry.id] = now
    if ns.Marks.HuntingDown(entry) then return end
    ns.Marks:Add(self.CLAIM_MARKS, "claim", self.TargetName(entry.id))
end

-- Our claims 3 days old without the gold: unpaid
function Bounties:CheckUnpaid(now)
    now = now or ns.Utils.ServerTime()
    local me = Me()
    for posterId, pay in pairs(Payments() or {}) do
        if pay.status == "claimed" and ns.Utils.SameCharacter(pay.hunter, me) and now - pay.claimedAt >= self.UNPAID_AFTER then
            local unpaid = { posterId = posterId, hunter = pay.hunter, status = "unpaid", claimedAt = pay.claimedAt, t = now }
            if self:AddPayment(unpaid, "local") then SendPayment(unpaid) end
        end
    end
end

-------------------------------------------------
-- Mail
-------------------------------------------------

function Bounties.Subject(targetId)
    return string.format(L.BOUNTY_MAIL_SUBJECT, Bounties.TargetName(targetId))
end

-- The recipient for SendMail: the name alone on our own realm
function Bounties.MailName(key)
    return ns.Utils.DisplayName(key)
end

-- The subject names the target, whose name clients may write differently (a
-- given-name-only Forever killer): the inbox matches the prefix, the sender and the gold
local function IsBountySubject(subject)
    local prefix = string.format(L.BOUNTY_MAIL_SUBJECT, "")
    return type(subject) == "string" and subject:sub(1, #prefix) == prefix
end

-- The hunter opened the mailbox: gold from an owner we claimed from is the proof
function Bounties:CheckInbox()
    if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
    local U = ns.Utils
    local me = Me()
    local now = U.ServerTime()
    for posterId, pay in pairs(Payments() or {}) do
        local poster = self:Get(posterId)
        if poster and pay.status ~= "paid" and U.SameCharacter(pay.hunter, me) then
            for i = 1, (U.SafeCall(GetInboxNumItems) or 0) do
                local _, _, sender, subject, money = U.SafeCall(GetInboxHeaderInfo, i)
                if sender and U.SameCharacter(sender, poster.owner) and IsBountySubject(subject)
                        and (tonumber(money) or 0) >= poster.gold then
                    local paid = { posterId = posterId, hunter = pay.hunter, status = "paid", claimedAt = pay.claimedAt, t = now }
                    if self:AddPayment(paid, "local") then
                        SendPayment(paid)
                        ns:Print(string.format(L.BOUNTY_PAID, U.DisplayName(poster.owner), self.Gold(poster.gold)))
                    end
                    break
                end
            end
        end
    end
end

-- Our posters with a claim and no gold sent yet
function Bounties:ToPay()
    local me = Me()
    local list = {}
    for _, poster in self:All() do
        local pay = self:Payment(poster.id)
        if pay and pay.status ~= "paid" and ns.Relay.Counts(pay) and not poster.sentAt
                and ns.Utils.SameCharacter(poster.owner, me) and self:CachedVerdict(poster.id) ~= "rejected" then
            list[#list + 1] = poster.id
        end
    end
    table.sort(list)
    return list
end

-- "Kestrel brought down Grim Reaper (your bounty: Camped me). Send 20g?"
function Bounties:AskNext()
    local poster = self:Get(payQueue[1])
    if not poster then return false end
    local pay = self:Payment(poster.id)
    local hunter, target = ns.Utils.DisplayName(pay.hunter), self.TargetName(poster.target)
    local text = string.format(L.BOUNTY_PAY_PROMPT, hunter, target, self.ReasonText(poster.reason), self.Gold(poster.gold))
    -- HH-121: who saw it; not confirmed means not paying makes no Deadbeat
    local verdict, by = self:CachedVerdict(poster.id)
    if verdict ~= "verified" then
        text = text .. L.BOUNTY_PAY_UNVERIFIED
    else
        text = text .. string.format(L.BOUNTY_PAY_VERIFIED, ns.Utils.DisplayName(by) or by)
        if self:LooksLikeAlt(poster.id) then
            text = text .. string.format(L.BOUNTY_PAY_ALT, hunter, target)
        elseif self:FirstClaim(poster.id) then
            text = text .. string.format(L.BOUNTY_PAY_FIRST, hunter)
        end
    end
    StaticPopupDialogs[self.PAY_POPUP].text = text
    StaticPopup_Show(self.PAY_POPUP)
    return true
end

function Bounties:OnMailShow()
    payQueue = self:ToPay()
    self:CheckInbox()
    self:AskNext()
end

-- [Send]: the owner's click writes and sends the mail. Returns true when sent.
function Bounties:PayNext()
    local posterId = table.remove(payQueue, 1)
    local poster = self:Get(posterId)
    local pay = self:Payment(posterId)
    if not (poster and pay) then return false end
    local U = ns.Utils
    if not (SendMail and SetSendMailMoney) then
        ns:Print(L.BOUNTY_PAY_NO_MAIL)
        return false
    end
    if GetMoney and (U.SafeCall(GetMoney) or 0) < poster.gold then
        ns:Print(string.format(L.BOUNTY_PAY_NO_GOLD, self.Gold(poster.gold)))
        return false
    end
    -- Never more than the posted amount, never COD
    if U.SafeCall(SetSendMailMoney, poster.gold) == false then
        ns:Print(L.BOUNTY_PAY_NO_MAIL)
        return false
    end
    U.SafeCall(SendMail, self.MailName(pay.hunter), self.Subject(poster.target),
        string.format(L.BOUNTY_MAIL_BODY, self.TargetName(poster.target), self.ReasonText(poster.reason)))
    poster.sentAt = U.ServerTime()
    ns:Print(string.format(L.BOUNTY_PAY_SENT, self.Gold(poster.gold), U.DisplayName(pay.hunter)))
    Changed()
    C_Timer.After(0.5, function() Bounties:AskNext() end)
    return true
end

-- [Later]: ask again at the next mailbox
function Bounties:Later()
    wipe(payQueue)
end

-------------------------------------------------
-- Display
-------------------------------------------------

-- "20g"
function Bounties.Gold(copper)
    return math.floor((tonumber(copper) or 0) / 10000) .. "g"
end

function Bounties.ReasonText(reason)
    local id = Bounties.REASONS[tonumber(reason) or 0]
    return id and L["BOUNTY_REASON_" .. id:upper()] or "?"
end

function Bounties.TargetName(targetId)
    local entry = ns.Wanted:Get(targetId)
    if entry then return entry.key and ns.Utils.DisplayName(entry.key) or entry.name or "?" end
    if targetId and targetId:find("^guid:") then return "?" end
    return ns.Utils.DisplayName(targetId) or "?"
end

-- " · pays up", " · 1 unpaid"
function Bounties:StandingText(owner)
    local paid, unpaid = self:Standing(owner)
    if unpaid > 0 then return string.format(L.BOUNTY_UNPAID_WARNING, unpaid) end
    if paid > 0 then return L.BOUNTY_PAYS_UP end
    return ""
end

-- "Bounty: 20g by Tallon · Camped me", or "Bounty: 3 posters · 45g"; nil without one
function Bounties:Line(targetId, now)
    local summary = self:Summary(targetId, now)
    if not summary then return nil end
    if summary.count > 1 then return string.format(L.BOUNTY_LINE_MANY, summary.count, self.Gold(summary.gold)) end
    local poster = summary.newest
    return string.format(L.BOUNTY_LINE, self.Gold(poster.gold), ns.Utils.DisplayName(poster.owner),
        self.ReasonText(poster.reason)) .. self:StandingText(poster.owner)
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

Bounties.PAY_POPUP = "HEADHUNTER_BOUNTY_PAY"

local function Ticker()
    C_Timer.After(Bounties.CHECK, function()
        Bounties:CheckUnpaid()
        Ticker()
    end)
end

ns.Events:Register("HH_INITIALIZED", function()
    local Events, Protocol = ns.Events, ns.Protocol
    Bounties:Prune()
    ns.Transport:RegisterHandler(Protocol.TYPES.POSTER, function(record, sender) Bounties:OnPeerPoster(record, sender) end)
    ns.Transport:RegisterHandler(Protocol.TYPES.PAYMENT, function(record, sender, faction)
        Bounties:OnPeerPayment(record, sender, faction)
    end)
    Events:Register("HH_JUSTICE_ADDED", function(_, record) Bounties:OnCatch(record) end, OWNER)
    Events:Register("HH_CATCH_WITNESSED", function(_, entry) Bounties:OnWitnessed(entry) end, OWNER)
    Events:Register("MAIL_SHOW", function() Bounties:OnMailShow() end, OWNER)
    Events:Register("MAIL_INBOX_UPDATE", function() Bounties:CheckInbox() end, OWNER)
    Events:Register("MAIL_CLOSED", function() Bounties:Later() end, OWNER)
    -- New evidence for a claim (HH-121): its verdict may change
    Events:Register("HH_WITNESS_ADDED", function(_, w) Bounties:RefreshVerdicts(w.outlaw) end, OWNER)
    Events:Register("HH_OUTLAW_SPOTTED", function(_, outlaw) Bounties:RefreshVerdicts(outlaw) end, OWNER)
    Events:Register("HH_REPORT_ADDED", function(_, report)
        local victim = report.victim and report.victim.key
        if victim then Bounties:RefreshVerdicts(victim) end
    end, OWNER)
    StaticPopupDialogs[Bounties.PAY_POPUP] = {
        text = "",
        button1 = L.BOUNTY_PAY_SEND,
        button2 = L.BOUNTY_PAY_LATER,
        OnAccept = function() Bounties:PayNext() end,
        OnCancel = function() Bounties:Later() end,
        timeout = 0,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    Bounties:CheckUnpaid()
    Ticker()
end, OWNER)

ns.SlashCommands:Register("claim", function()
    if Bounties:PendingAnnounce() == 0 then
        ns:Print(L.BOUNTY_ANNOUNCE_NOTHING)
        return
    end
    StaticPopup_Hide(ns.Alerts.BOUNTY_POPUP)
    Bounties:Announce()
end, L.HELP_CLAIM)

-- One claim as a chat line: "Grim Reaper · 5g · Kestrel for Tallon · unpaid · verified (Bravo saw it)"
function Bounties:ClaimLine(posterId)
    local poster, pay = self:Get(posterId), self:Payment(posterId)
    if not (poster and pay) then return nil end
    local U = ns.Utils
    local verdict, by = self:CachedVerdict(posterId)
    local who = U.DisplayName(by) or by
    local verdictText = verdict == "verified" and string.format(L.VERDICT_VERIFIED, who)
        or verdict == "rejected" and string.format(L.VERDICT_REJECTED, who) or L.VERDICT_UNVERIFIED
    return string.format(L.BOUNTIES_LINE, self.TargetName(poster.target), self.Gold(poster.gold), U.DisplayName(pay.hunter),
        U.DisplayName(poster.owner), L["BOUNTIES_STATUS_" .. string.upper(pay.status)] or pay.status, verdictText)
end

-- /hh bounties: our claims, as owner or hunter, newest first, with their verdicts (HH-121)
ns.SlashCommands:Register("bounties", function()
    local U, me = ns.Utils, Me()
    local list = {}
    for posterId, pay in pairs(Payments() or {}) do
        if U.SameCharacter(pay.hunter, me) or U.SameCharacter(Bounties.OwnerOf(posterId), me) then
            list[#list + 1] = { id = posterId, t = pay.claimedAt }
        end
    end
    if #list == 0 then
        ns:Print(L.BOUNTIES_NONE)
        return
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    ns:Print(L.BOUNTIES_HEADER)
    for i = 1, math.min(10, #list) do
        local line = Bounties:ClaimLine(list[i].id)
        if line then print("  " .. date("%m-%d %H:%M", list[i].t) .. "  " .. line) end
    end
end, L.HELP_BOUNTIES)
