-- HH-050: HeadHunter Marks and hunter ranks (docs/addon/features.md section 6).
-- Players see them as "bounty" (author, 2026-09-24): the My bounty tab, /hh bounty
-- (/hh marks still works); the code and the saved data keep the name marks.
--
--   +1   joining a posse: once per outlaw per WANTED run (author, 2026-09-28; a
--        login on Forever and a new posse every 30 min used to pay again)
--   +N   a catch we saw: we or our group killed a WANTED outlaw (Sync/Justice.lua);
--        N by the outlaw's rank: Ganker 3, Outlaw 5, Desperado 8, Most Wanted 12,
--        Dead or Alive 20 (author, 2026-09-23). Once per outlaw per minute.
--   -1   Decline while eligible: at most once per 10 min; never in combat, in an
--        instance, AFK or outside the level window (HH-047). Letting the popup time
--        out costs nothing.
--   +5   a catch of a player's bounty target we saw (HH-118, Sync/Bounties.lua)
--   +3   a Hall of Shame bully, or the other faction's Deadbeat (HH-118), brought down by
--        us or our group, not WANTED (author, 2026-09-28): once per player per hour,
--        for as long as they are listed
--   none when the outlaw is 10+ levels below us: hunting down is ganking too.
-- Ranks: Tracker 0, Bounty Hunter 10, Manhunter 25, Headhunter 50, Reaper 100.
--
-- Kept in ns.db.marks = { total, owner, totals, events = newest last }, per character
-- (see Own below). Our rank travels with posse joins (Alerts/Posse.lua), so /hh posse
-- shows each member's rank. Without a server
-- marks can be forged; accepted for now (the website validates later).
-- Fires HH_MARKS_CHANGED(total, event).

local addonName, ns = ...
local L = ns.L

local Marks = ns:RegisterModule("Marks", {})

local OWNER = "Marks"

Marks.RANKS = {
    { min = 0, id = "tracker" },
    { min = 10, id = "bountyhunter" },
    { min = 25, id = "manhunter" },
    { min = 50, id = "headhunter" },
    { min = 100, id = "reaper" },
}
Marks.CATCH = { ganker = 3, outlaw = 5, desperado = 8, mostwanted = 12, deadoralive = 20 }
Marks.JOIN = 1
Marks.BULLY = 3
Marks.BULLY_COOLDOWN = 3600  -- per bully or Deadbeat
Marks.DECLINE = -1
Marks.LEVEL_GAP = 10           -- no marks for hunting 10+ levels down
Marks.JOIN_COOLDOWN = 1800     -- per outlaw (a posse lasts 30 min)
Marks.CATCH_COOLDOWN = 60      -- per outlaw
Marks.DECLINE_COOLDOWN = 600   -- any outlaw
Marks.MAX_EVENTS = 200

local lastJoin, lastCatch, lastBully = {}, {}, {}   -- outlaw id -> GetTime()
local lastDecline

-- Each character has its own bounty (author, 2026-09-30). The saved data is shared by
-- the realm's characters: marks.total is the character we play (marks.owner), the
-- others wait in marks.totals. Events are one list, each with its hunter. The first
-- character to log in after the change takes the old shared total.
local function Own(store)
    local U = ns.Utils
    local me = U.CompactName(U.UnitKey("player"))
    if not me or store.owner == me then return store end
    store.totals = store.totals or {}
    if store.owner then
        store.totals[store.owner] = store.total or 0
        store.total = store.totals[me] or 0
        store.totals[me] = nil
    else
        local key = U.UnitKey("player")
        for _, event in ipairs(store.events or {}) do event.hunter = event.hunter or key end
    end
    store.owner = me
    return store
end

local function Store()
    local store = ns.db and ns.db.marks
    return store and Own(store)
end

local function IsMine(event)
    return ns.Utils.SameCharacter(event.hunter, ns.Utils.UnitKey("player"))
end

-- The saved total of one of our characters (SiteData: the website's number)
function Marks:SetTotalOf(key, total)
    local store = Store()
    if not store then return false end
    local id = ns.Utils.CompactName(key)
    if not id then return false end
    if id == store.owner then
        if total <= (store.total or 0) then return false end
        store.total = total
    else
        store.totals = store.totals or {}
        if total <= (store.totals[id] or 0) then return false end
        store.totals[id] = total
    end
    return true
end

-- At most MAX_EVENTS per character, the oldest go first
function Marks.Trim(store)
    local counts = {}
    for _, event in ipairs(store.events) do
        local id = ns.Utils.CompactName(event.hunter) or "?"
        counts[id] = (counts[id] or 0) + 1
    end
    local kept = {}
    for _, event in ipairs(store.events) do
        local id = ns.Utils.CompactName(event.hunter) or "?"
        if counts[id] > Marks.MAX_EVENTS then
            counts[id] = counts[id] - 1
        else
            kept[#kept + 1] = event
        end
    end
    store.events = kept
end

function Marks:Total()
    local store = Store()
    return store and store.total or 0
end

-- Rank index (1 Tracker … 5 Reaper) for a total
function Marks.RankIndexFor(total)
    local index = 1
    for i, rank in ipairs(Marks.RANKS) do
        if total >= rank.min then index = i end
    end
    return index
end

function Marks:RankIndex()
    return Marks.RankIndexFor(self:Total())
end

function Marks.RankNameByIndex(index)
    local rank = Marks.RANKS[tonumber(index) or 0]
    return rank and L["HUNTER_RANK_" .. rank.id:upper()] or ""
end

-- The next rank's name and the marks still needed, or nil at the top
function Marks:Next()
    local index = self:RankIndex()
    local nextRank = Marks.RANKS[index + 1]
    if not nextRank then return nil end
    return Marks.RankNameByIndex(index + 1), nextRank.min - self:Total()
end

-- The character we play, newest first
function Marks:Events()
    local store = Store()
    local list = {}
    for i = #(store and store.events or {}), 1, -1 do
        if IsMine(store.events[i]) then list[#list + 1] = store.events[i] end
    end
    return list
end

-- Record a change. reason: "join" | "catch" | "decline" | "skip"; outlaw: display name
function Marks:Add(delta, reason, outlaw, rank)
    local store = Store()
    if not store then return nil end
    local before = self:RankIndex()
    store.total = math.max(0, (store.total or 0) + delta)
    -- hunter: whose event it is, as the realm's characters share one list (the sync app splits them)
    local event = { t = ns.Utils.ServerTime(), delta = delta, reason = reason, outlaw = outlaw, rank = rank,
        total = store.total, hunter = ns.Utils.UnitKey("player") }
    store.events[#store.events + 1] = event
    Marks.Trim(store)

    ns:Print(Marks.Describe(event))
    local after = self:RankIndex()
    if after > before then
        ns.Alerts:Show({ key = "hunter-rank:" .. after, throttle = 0, sound = true, combat = true,
            text = string.format(L.MARKS_RANK_UP, Marks.RankNameByIndex(after)) })
    end
    ns.Events:Fire("HH_MARKS_CHANGED", store.total, event)
    return event
end

-- One line for chat and the "My marks" tab
-- What happened, without the numbers ("brought down Outlaw Burner")
function Marks.Reason(event)
    -- One argument per reason string: the outlaw, with the rank for a catch
    local subject = event.outlaw or "?"
    if event.reason == "catch" and event.rank then subject = ns.Wanted.RankName(event.rank) .. " " .. subject end
    return string.format(L["MARKS_REASON_" .. event.reason:upper()], subject)
end

-- "+5 mark(s): brought down Outlaw Burner (57 marks)"
function Marks.Change(event)
    if event.delta > 0 then return "|cff40ff40+" .. event.delta .. "|r" end
    if event.delta < 0 then return "|cffff4040" .. event.delta .. "|r" end
    return "0"
end

function Marks.Describe(event)
    local text = Marks.Reason(event)
    if event.delta == 0 then return text end
    local sign = event.delta > 0 and ("|cff40ff40+" .. event.delta) or ("|cffff4040" .. event.delta)
    return string.format(L.MARKS_LINE, sign, text, event.total or 0)
end

local function OutlawName(entry)
    return entry.key and ns.Utils.DisplayName(entry.key) or entry.name or "?"
end

-- True when the outlaw is 10+ levels below us (a skull outlaw never is)
function Marks.HuntingDown(entry)
    local mine = ns.Utils.UnitLevel("player")
    local theirs = entry.level
    if not mine or mine < 1 or not theirs or theirs < 1 then return false end
    return mine - theirs >= Marks.LEVEL_GAP
end

-------------------------------------------------
-- Earning and losing
-------------------------------------------------

-- A join point for this outlaw since their WANTED run began. Read from the saved events
-- (on Forever: the website's), so a login, a /reload or a new posse pays nothing again.
function Marks:JoinedThisRun(entry)
    local since = entry.wantedSince or entry.firstKill or 0
    local name = OutlawName(entry)
    local store = Store()
    for _, event in ipairs(store and store.events or {}) do
        if event.reason == "join" and (event.t or 0) >= since and IsMine(event)
            and ns.Utils.SameCharacter(event.outlaw, name) then
            return true
        end
    end
    return false
end

function Marks:OnJoin(entry)
    local now = ns.Utils.Now()
    if lastJoin[entry.id] and now - lastJoin[entry.id] < self.JOIN_COOLDOWN then return nil end
    lastJoin[entry.id] = now
    if Marks.HuntingDown(entry) then return self:Add(0, "skip", OutlawName(entry)) end
    if self:JoinedThisRun(entry) then return nil end
    return self:Add(self.JOIN, "join", OutlawName(entry), entry.rank)
end

function Marks:OnCatch(entry)
    -- A posted target that is not WANTED pays the bounty points instead (Sync/Bounties.lua)
    if not ns.Wanted.Hunted(entry) then return nil end
    local now = ns.Utils.Now()
    if lastCatch[entry.id] and now - lastCatch[entry.id] < self.CATCH_COOLDOWN then return nil end
    lastCatch[entry.id] = now
    if Marks.HuntingDown(entry) then return self:Add(0, "skip", OutlawName(entry)) end
    local rank = ns.Wanted.CurrentRank(entry)
    return self:Add(self.CATCH[rank] or self.CATCH.ganker, "catch", OutlawName(entry), rank)
end

-- kind: "bully" | "deadbeat"
function Marks:OnShameKilled(entry, kind)
    local now = ns.Utils.Now()
    if lastBully[entry.id] and now - lastBully[entry.id] < self.BULLY_COOLDOWN then return nil end
    lastBully[entry.id] = now
    if Marks.HuntingDown(entry) then return self:Add(0, "skip", OutlawName(entry)) end
    return self:Add(self.BULLY, kind == "deadbeat" and "deadbeat" or "bully", OutlawName(entry))
end

-- Eligible to be penalised: out of combat, in the open world, not AFK
function Marks.DeclineCounts()
    local U = ns.Utils
    if not ns.Guards:IsActive() then return false end
    if U.SafeCall(UnitAffectingCombat, "player") == true then return false end
    if U.SafeCall(UnitIsAFK, "player") == true then return false end
    return true
end

function Marks:OnDecline(entry, reason)
    -- A popup that timed out, or one outside the level window (HH-047), never costs anything
    if reason == "timeout" or not Marks.DeclineCounts() or Marks.HuntingDown(entry) or not ns.Wanted.InLevelWindow(entry) then
        return nil
    end
    local now = ns.Utils.Now()
    if lastDecline and now - lastDecline < self.DECLINE_COOLDOWN then return nil end
    lastDecline = now
    return self:Add(self.DECLINE, "decline", OutlawName(entry), entry.rank)
end

ns.Events:Register("HH_INITIALIZED", function()
    local Events = ns.Events
    Events:Register("HH_POSSE_JOINED", function(_, entry) Marks:OnJoin(entry) end, OWNER)
    Events:Register("HH_POSSE_DECLINED", function(_, entry, _, reason) Marks:OnDecline(entry, reason) end, OWNER)
    Events:Register("HH_CATCH_WITNESSED", function(_, entry) Marks:OnCatch(entry) end, OWNER)
    Events:Register("HH_SHAME_KILLED", function(_, entry, kind) Marks:OnShameKilled(entry, kind) end, OWNER)
end, OWNER)

-- /hh bounty (players see "bounty"; /hh marks stays as an unlisted alias)
local function ShowBounty()
    ns:Print(string.format(L.MARKS_STATUS, Marks.RankNameByIndex(Marks:RankIndex()), Marks:Total()))
    local nextName, needed = Marks:Next()
    if nextName then ns:Print(string.format(L.MARKS_NEXT, needed, nextName)) end
    for i, event in ipairs(Marks:Events()) do
        if i > 5 then break end
        print("  " .. date("%m-%d %H:%M", event.t) .. "  " .. Marks.Describe(event))
    end
end

ns.SlashCommands:Register("bounty", ShowBounty, L.HELP_MARKS)
ns.SlashCommands:Register("marks", ShowBounty)
