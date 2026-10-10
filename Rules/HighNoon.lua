-- HH-092: High Noon records and ranks (docs/addon/features.md section 10).
--
-- Wins and losses per player from the duel set (Sync/Duels.lua); a retreat is a loss.
-- Everyone with MIN_DUELS or more first, then the Greenhorns (author, 2026-09-27: a
-- Greenhorn at 2-0 is not ahead of 6-5). Within each: net (wins minus losses), then
-- fewer losses, then more wins (author, 2026-09-25: no rating, 1-0 is better than 1-4).
-- The same record: whoever reached it first (the earlier last duel) goes first (author,
-- 2026-09-27), so every place is taken once. Listed from the first duel.
-- Ranks by net: Quickdraw, Sharpshooter (+5), Deadeye (+15), Legend (+30); under
-- MIN_DUELS a player is a Greenhorn. The #1 of each faction is the Top Gun when they
-- are no Greenhorn, have TOP_GUN_NET or more (Sharpshooter; author, 2026-09-28: 6-5 is
-- no Top Gun) and a clear lead (two at the top with the same record: no Top Gun yet). Two lists: Alliance and Horde (duels stay inside a
-- faction). The website ranks the same way.
-- Each rank has its colour, as WoW's item qualities (Greenhorn grey ... Legend purple,
-- Top Gun orange).
--
--   HighNoon.Compute(duels) -> key -> player   (pure, tested offline)
--   HighNoon:Get(key), HighNoon:List(faction)  (listed players, best first, with .position)
-- Fires HH_HIGHNOON_UPDATED after a recompute.
--
-- HH-137 (author, 2026-10-09: an 820 ms freeze in a dueling zone with the window closed):
-- a new duel only marks the lists out of date. They are counted again when someone needs
-- them (HighNoon:Ensure: the Duels tab, a tooltip), once after login, and as a job of
-- BUDGET_MS a frame. Until it is done, Get and List give the last counted lists.

local addonName, ns = ...
local L = ns.L

local HighNoon = ns:RegisterModule("HighNoon", {})

local OWNER = "HighNoon"

HighNoon.MIN_DUELS = 5
HighNoon.TOP_GUN_NET = 5 -- the Top Gun needs Sharpshooter (+5); the website's DuelRatingCalculator::TOP_GUN_NET
HighNoon.DEBOUNCE = 1
-- HH-137: the job's time per frame, and the duels or players between two budget checks
HighNoon.BUDGET_MS = 3
HighNoon.YIELD_EVERY = 200
-- HH-137 (author, 2026-10-09): each faction's list holds its best LIST_SIZE, as many as
-- the website sends; every duel still goes to the website, which ranks everyone
HighNoon.LIST_SIZE = 300
-- Highest first, by net wins
HighNoon.RANKS = {
    { min = 30, id = "legend" },
    { min = 15, id = "deadeye" },
    { min = 5, id = "sharpshooter" },
    { min = -math.huge, id = "quickdraw" },
}

-- Duels needed to lose the Greenhorn label; /hh debug duels <n> lowers it for testing
function HighNoon.MinDuels()
    local test = ns.db and ns.db.settings.testDuelMin
    return test or HighNoon.MIN_DUELS
end

function HighNoon.RankOf(player)
    if player.duels < HighNoon.MinDuels() then return "greenhorn" end
    for _, rank in ipairs(HighNoon.RANKS) do
        if player.net >= rank.min then return rank.id end
    end
    return "quickdraw"
end

-- Past the Greenhorn duels: listed above the Greenhorns and can be Top Gun
function HighNoon.Established(player)
    return player.duels >= HighNoon.MinDuels()
end

-- The same record
function HighNoon.Tied(a, b)
    return a.net == b.net and a.losses == b.losses and a.wins == b.wins
end

-- Best first: Greenhorns last, then net, then fewer losses, then more wins; the same
-- record: whoever reached it first (earlier last duel), then by name
function HighNoon.Better(a, b)
    local ea, eb = HighNoon.Established(a), HighNoon.Established(b)
    if ea ~= eb then return ea end
    if not HighNoon.Tied(a, b) then
        if a.net ~= b.net then return a.net > b.net end
        if a.losses ~= b.losses then return a.losses < b.losses end
        return a.wins > b.wins
    end
    local at, bt = a.lastT or math.huge, b.lastT or math.huge
    if at ~= bt then return at < bt end
    return a.key < b.key
end

-- "+3", "0", "-2"
function HighNoon.NetText(net)
    return net > 0 and ("+" .. net) or tostring(net)
end

-- Gives the frame back now and then: yield is coroutine.yield inside the job, nil otherwise
local function Tick(yield, count)
    if yield and count % HighNoon.YIELD_EVERY == 0 then yield() end
end

-- duels: array. Returns key -> { key, faction, wins, losses, duels, net, rank, lastT, class, race, sex }
-- yield: optional, see Tick
function HighNoon.Compute(duels, yield)
    local players = {}
    local function Player(key, faction, class, race, sex, t)
        local p = players[key]
        if not p then
            p = { key = key, wins = 0, losses = 0, duels = 0 }
            players[key] = p
        end
        -- The newest duel tells the current class, race and faction
        if not p.lastT or t >= p.lastT then
            p.faction = faction or p.faction
            p.class = class or p.class
            p.race = race or p.race
            p.sex = sex or p.sex
            p.lastT = t
        end
        return p
    end
    for i, duel in ipairs(duels) do
        local t = tonumber(duel.t) or 0
        local w = Player(duel.winner, duel.faction, duel.winnerClass, duel.winnerRace, duel.winnerSex, t)
        local l = Player(duel.loser, duel.faction, duel.loserClass, duel.loserRace, duel.loserSex, t)
        w.wins, l.losses = w.wins + 1, l.losses + 1
        w.duels, l.duels = w.duels + 1, l.duels + 1
        Tick(yield, i)
    end
    for _, p in pairs(players) do
        p.faction = HighNoon.FactionOf(p)
        p.net = p.wins - p.losses
        p.rank = HighNoon.RankOf(p)
    end
    return players
end

-- A duel stores one faction for both players, but duels can cross factions and a
-- watcher may guess (author, 2026-09-28: a Troll on the Alliance list). The race tells
-- each player's own faction; the duel's faction only when the race is unknown.
function HighNoon.FactionOf(p)
    return ns.Utils.RaceFaction(p.race) or p.faction
end

local NO_DUELS = {}

-- One player's duels in the order they came; a duel with the same winner and loser once
local function AddOwn(byPlayer, key, duel)
    if not key then return end
    local own = byPlayer[key]
    if not own then
        own = {}
        byPlayer[key] = own
    end
    if own[#own] ~= duel then own[#own + 1] = duel end
end

-- HH-082: the website's records (Sync/SiteData.lua) with ours. A player the website
-- lists keeps its record plus our duels newer than that player's last duel on the
-- list; anyone else keeps the record from our duels. Per player, not per list: the
-- sync app may download a list the website has not rebuilt yet after our upload, and
-- its time would then hide our newest duels (2026-09-26: 2-4 shown instead of 6-5).
-- site: key -> { key, faction, wins, losses, duels, lastT, class, race, sex }
-- Our duels are grouped by player first (HH-137), so each website player looks only at
-- their own: the work grows with duels plus players, not duels times players.
-- yield: optional, see Tick
function HighNoon.Merge(site, duels, since, yield)
    local ours = HighNoon.Compute(duels, yield)
    local byPlayer = {}
    for i, duel in ipairs(duels) do
        AddOwn(byPlayer, duel.winner, duel)
        AddOwn(byPlayer, duel.loser, duel)
        Tick(yield, i)
    end
    local fresh = {}
    local count = 0
    for key, theirs in pairs(site) do
        local cutoff = theirs.lastT or since
        local newer = {}
        for _, duel in ipairs(byPlayer[key] or NO_DUELS) do
            if (tonumber(duel.t) or 0) > cutoff then newer[#newer + 1] = duel end
        end
        fresh[key] = HighNoon.Compute(newer)[key]
        count = count + 1
        Tick(yield, count)
    end
    local players = {}
    for key, theirs in pairs(site) do
        local p = {}
        for k, v in pairs(theirs) do p[k] = v end
        local f = fresh[key]
        if f then
            p.wins, p.losses, p.duels = p.wins + f.wins, p.losses + f.losses, p.duels + f.duels
            if not p.lastT or f.lastT > p.lastT then
                p.lastT = f.lastT
                p.class, p.race, p.sex = f.class or p.class, f.race or p.race, f.sex or p.sex
            end
        end
        p.faction = HighNoon.FactionOf(p)
        p.net = p.wins - p.losses
        p.rank = HighNoon.RankOf(p)
        players[key] = p
    end
    for key, p in pairs(ours) do
        if not players[key] then players[key] = p end
    end
    return players
end

-------------------------------------------------
-- Runtime
-------------------------------------------------

local players = {}
local lists = {}          -- faction -> listed players, best first
local scheduled = false
local computing = false
local again = false
local stale = true

-- The lists from the duels and the website's records, not yet published.
-- yield: optional, see Tick
function HighNoon.Build(yield)
    local duels = {}
    -- A relayed duel counts only once a second source has it (HH-121)
    for _, duel in ns.Duels:All() do
        if ns.Relay.Counts(duel) then duels[#duels + 1] = duel end
        Tick(yield, #duels)
    end
    local site = ns.SiteData:Duelists()
    local built
    if site then
        built = HighNoon.Merge(site, duels, ns.SiteData:GeneratedAt() or 0, yield)
    else
        built = HighNoon.Compute(duels, yield)
    end
    local listed = {}
    local count = 0
    for _, p in pairs(built) do
        p.plain = ns.Utils.DisplayName(p.key) or p.key
        p.needle = p.plain:lower()
        if p.faction and p.duels >= 1 then
            listed[p.faction] = listed[p.faction] or {}
            HighNoon.KeepBest(listed[p.faction], p, HighNoon.LIST_SIZE)
        end
        count = count + 1
        Tick(yield, count)
    end
    for _, list in pairs(listed) do
        for i, p in ipairs(list) do
            p.position = i
            p.topGun = nil
        end
        -- Top Gun: the faction's #1, no Greenhorn, +5 or more and a clear lead
        local first, second = list[1], list[2]
        if first and HighNoon.Established(first) and first.net >= HighNoon.TOP_GUN_NET
            and not (second and HighNoon.Tied(first, second)) then
            first.topGun = true
        end
    end
    return built, listed
end

-- Puts p into list (best first) when it is among the best `size`, in one pass over the
-- players instead of sorting them all: most fall behind the last place and cost one look.
-- better: the order, HighNoon.Better when nil
function HighNoon.KeepBest(list, p, size, better)
    better = better or HighNoon.Better
    local last = #list
    if last >= size and not better(p, list[last]) then return end
    local low, high = 1, last + 1
    while low < high do
        local mid = math.floor((low + high) / 2)
        if better(p, list[mid]) then high = mid else low = mid + 1 end
    end
    table.insert(list, low, p)
    if #list > size then list[#list] = nil end
end

local function Publish(built, listed)
    players, lists = built, listed
    ns.Events:Fire("HH_HIGHNOON_UPDATED")
end

-- At once, in this frame (tests, /hh duels, /hh debug duels)
function HighNoon:Recompute()
    stale = false
    Publish(HighNoon.Build())
end

-- Spread one recompute over frames
local function RunBudgeted()
    local built, listed
    local co = coroutine.create(function() built, listed = HighNoon.Build(coroutine.yield) end)
    local function Step()
        local started = debugprofilestop()
        while coroutine.status(co) ~= "dead" do
            local ok, err = coroutine.resume(co)
            if not ok then
                ns:Error(err)
                break
            end
            if debugprofilestop() - started > HighNoon.BUDGET_MS then break end
        end
        if coroutine.status(co) ~= "dead" then
            C_Timer.After(0, Step)
            return
        end
        computing = false
        if built then Publish(built, listed) end
        if again then
            again = false
            HighNoon:RequestRecompute()
        end
    end
    Step()
end

function HighNoon:RequestRecompute()
    if computing then
        again = true
        return
    end
    if scheduled then return end
    scheduled = true
    C_Timer.After(self.DEBOUNCE, function()
        scheduled = false
        stale = false
        computing = true
        RunBudgeted()
    end)
end

-- A duel came or changed: the lists are out of date until someone needs them
function HighNoon:MarkStale()
    stale = true
end

function HighNoon:IsStale()
    return stale
end

-- Someone needs the lists: count them again when they are out of date
function HighNoon:Ensure()
    if stale then self:RequestRecompute() end
end

function HighNoon:Get(key)
    return key and players[key]
end

-- Listed players of one faction, best first: the best LIST_SIZE
function HighNoon:List(faction)
    return lists[faction] or {}
end

-- Search order: listed players first, then the others, each best first
local function ListedFirst(a, b)
    if (a.position ~= nil) ~= (b.position ~= nil) then return a.position ~= nil end
    return HighNoon.Better(a, b)
end

-- HH-137: anyone with duels whose name holds `text` (any case), also past the lists:
-- listed players first, then the others, best first; at most LIST_SIZE.
-- faction: nil for both
function HighNoon:Search(text, faction)
    local needle = text and text:lower()
    local found = {}
    if not needle or needle == "" then return found end
    for _, p in pairs(players) do
        if p.needle and p.duels >= 1 and (not faction or p.faction == faction)
            and p.needle:find(needle, 1, true) then
            HighNoon.KeepBest(found, p, HighNoon.LIST_SIZE, ListedFirst)
        end
    end
    return found
end

HighNoon.RANK_COLORS = {
    greenhorn = "9d9d9d", quickdraw = "ffffff", sharpshooter = "1eff00",
    deadeye = "0070dd", legend = "a335ee", topgun = "ff8000",
}

-- The rank's name in its colour
function HighNoon.RankName(rank)
    local name = L["DUEL_RANK_" .. tostring(rank):upper()]
    local color = HighNoon.RANK_COLORS[rank]
    if not (name and color) then return name end
    return "|cff" .. color .. name .. "|r"
end

-- "Deadeye #3 (+16)", "Top Gun (+20)", "Greenhorn (2 duels)"
function HighNoon.Title(player)
    if not player then return nil end
    if player.topGun then return string.format(L.DUEL_TITLE_TOPGUN, HighNoon.NetText(player.net)) end
    if player.duels < HighNoon.MinDuels() then
        return string.format(L.DUEL_TITLE_GREENHORN, HighNoon.RankName("greenhorn"), player.duels)
    end
    if not player.position then
        return string.format(L.DUEL_TITLE_UNLISTED, HighNoon.RankName(player.rank), HighNoon.NetText(player.net))
    end
    return string.format(L.DUEL_TITLE, HighNoon.RankName(player.rank), player.position,
        HighNoon.NetText(player.net))
end

-- Once after login for the duels restored from SavedVariables; afterwards on need
ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("HH_DUEL_ADDED", function() HighNoon:MarkStale() end, OWNER)
    ns.Events:Register("HH_DUEL_UPDATED", function() HighNoon:MarkStale() end, OWNER)
    HighNoon:RequestRecompute()
end, OWNER)

-- /hh duels: the top 10 of our faction, and where we stand
ns.SlashCommands:Register("duels", function()
    if stale and not computing then HighNoon:Recompute() end
    local U = ns.Utils
    local faction = U.UnitFaction("player")
    local list = HighNoon:List(faction)
    ns:Print(string.format(L.DUELS_HEADER, faction or "?", #list))
    for i = 1, math.min(10, #list) do
        local p = list[i]
        print(string.format("  #%d  %s  %s  %s  (%d-%d)", i, U.DisplayName(p.key) or p.key,
            HighNoon.RankName(p.rank), HighNoon.NetText(p.net), p.wins, p.losses))
    end
    local me = HighNoon:Get(U.UnitKey("player"))
    if me then ns:Print(string.format(L.DUELS_YOU, HighNoon.Title(me), me.wins, me.losses)) end
end, L.HELP_DUELS)
