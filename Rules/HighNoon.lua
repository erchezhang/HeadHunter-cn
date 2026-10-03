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

local addonName, ns = ...
local L = ns.L

local HighNoon = ns:RegisterModule("HighNoon", {})

local OWNER = "HighNoon"

HighNoon.MIN_DUELS = 5
HighNoon.TOP_GUN_NET = 5 -- the Top Gun needs Sharpshooter (+5); the website's DuelRatingCalculator::TOP_GUN_NET
HighNoon.DEBOUNCE = 1
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

-- duels: array. Returns key -> { key, faction, wins, losses, duels, net, rank, lastT, class, race, sex }
function HighNoon.Compute(duels)
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
    for _, duel in ipairs(duels) do
        local t = tonumber(duel.t) or 0
        local w = Player(duel.winner, duel.faction, duel.winnerClass, duel.winnerRace, duel.winnerSex, t)
        local l = Player(duel.loser, duel.faction, duel.loserClass, duel.loserRace, duel.loserSex, t)
        w.wins, l.losses = w.wins + 1, l.losses + 1
        w.duels, l.duels = w.duels + 1, l.duels + 1
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

-- HH-082: the website's records (Sync/SiteData.lua) with ours. A player the website
-- lists keeps its record plus our duels newer than that player's last duel on the
-- list; anyone else keeps the record from our duels. Per player, not per list: the
-- sync app may download a list the website has not rebuilt yet after our upload, and
-- its time would then hide our newest duels (2026-09-26: 2-4 shown instead of 6-5).
-- site: key -> { key, faction, wins, losses, duels, lastT, class, race, sex }
function HighNoon.Merge(site, duels, since)
    local ours = HighNoon.Compute(duels)
    local fresh = {}
    for key, theirs in pairs(site) do
        local cutoff = theirs.lastT or since
        local newer = {}
        for _, duel in ipairs(duels) do
            if (duel.winner == key or duel.loser == key) and (tonumber(duel.t) or 0) > cutoff then
                newer[#newer + 1] = duel
            end
        end
        fresh[key] = HighNoon.Compute(newer)[key]
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

function HighNoon:Recompute()
    local duels = {}
    -- A relayed duel counts only once a second source has it (HH-121)
    for _, duel in ns.Duels:All() do
        if ns.Relay.Counts(duel) then duels[#duels + 1] = duel end
    end
    local site = ns.SiteData:Duelists()
    if site then
        players = HighNoon.Merge(site, duels, ns.SiteData:GeneratedAt() or 0)
    else
        players = HighNoon.Compute(duels)
    end
    lists = {}
    for _, p in pairs(players) do
        if p.faction and p.duels >= 1 then
            lists[p.faction] = lists[p.faction] or {}
            table.insert(lists[p.faction], p)
        end
    end
    for _, list in pairs(lists) do
        table.sort(list, HighNoon.Better)
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
    ns.Events:Fire("HH_HIGHNOON_UPDATED")
end

function HighNoon:RequestRecompute()
    if scheduled then return end
    scheduled = true
    C_Timer.After(self.DEBOUNCE, function()
        scheduled = false
        HighNoon:Recompute()
    end)
end

function HighNoon:Get(key)
    return key and players[key]
end

-- Listed players of one faction, best first
function HighNoon:List(faction)
    return lists[faction] or {}
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
    return string.format(L.DUEL_TITLE, HighNoon.RankName(player.rank), player.position or 0,
        HighNoon.NetText(player.net))
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("HH_DUEL_ADDED", function() HighNoon:RequestRecompute() end, OWNER)
    ns.Events:Register("HH_DUEL_UPDATED", function() HighNoon:RequestRecompute() end, OWNER)
    HighNoon:RequestRecompute() -- duels restored from SavedVariables
end, OWNER)

-- /hh duels: the top 10 of our faction, and where we stand
ns.SlashCommands:Register("duels", function()
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
