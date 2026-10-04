-- HH-048: "Justice served!" when a WANTED outlaw is caught (Sync/Justice.lua).
--
--   Our catch:      center text + chat + sound; on Era also [Announce] to the realm
--   Someone else's: a chat line; posse members of that outlaw also get center text
-- Driven by HH_WANTED_CAUGHT, so it describes what the rules decided, once.

local addonName, ns = ...
local L = ns.L

local JusticeAlerts = ns:RegisterModule("JusticeAlerts", {})

local OWNER = "JusticeAlerts"

local function Name(key)
    return key and ns.Utils.DisplayName(key) or "?"
end

function JusticeAlerts:OnCaught(entry, before)
    local record = ns.Justice:Latest(entry.id)
    if not record then return end
    local U, Wanted = ns.Utils, ns.Wanted
    local outlaw = entry.key and U.DisplayName(entry.key) or entry.name
    local rank = Wanted.RankName(Wanted.CurrentRank(before))
    local kills = math.floor(before.wanted and before.kills or before.killCount or 0)
    local zone = U.MapName(record.mapID) or L.UNKNOWN_ZONE
    local byMe = U.SameCharacter(record.killer, U.UnitKey("player"))
    local line = string.format(L.JUSTICE_LINE, rank, outlaw, kills, byMe and L.POSSE_YOU or Name(record.killer), zone)
    local alert = { key = "justice:" .. record.id, throttle = 0, chat = line }

    if record.origin == "local" then
        alert.text = string.format(L.JUSTICE_CENTER, outlaw)
        alert.sound = true
        -- Era: the realm hears about it only through a click
        if ns.Justice:PendingAnnounce() > 0 then
            alert.popup = {
                dialog = ns.Alerts.JUSTICE_POPUP,
                text = line .. "\n\n" .. L.JUSTICE_ANNOUNCE_QUESTION,
                accept = L.JUSTICE_ANNOUNCE,
                decline = CLOSE or "Close",
                onAccept = function() ns.Justice:Announce() end,
                onDecline = function() ns.Justice:SkipAnnounce() end,
            }
        end
    elseif record.origin == "relay" then
        -- Learned at login (HH-023): old news, the chat line is enough
    elseif ns.Posse:IsMember(entry.id) then
        alert.text = string.format(L.JUSTICE_CENTER_POSSE, outlaw, byMe and L.POSSE_YOU or Name(record.killer))
        alert.sound = "soft"
    end
    ns.Alerts:Show(alert)
    if record.origin == "peer" then JusticeAlerts:AskGlass(record, outlaw) end
end

-- Barflies (author, 2026-10-04): another HeadHunter busted a WANTED player just now; a
-- HeadHunter card under the minimap (UI/Toast.lua) asks to raise a glass, and only glasses from it count for the Barflies ranking.
-- Not in combat (it waits up to GLASS_WAIT seconds for the fight to end) and never in an
-- instance (Alerts:Show and its queue), off in Settings. At most one every few minutes
-- (the glassPopupGap setting, 3 to 15, default 5): five busts in a minute ask once, for
-- the first; the others stay in the Busted list.
JusticeAlerts.GLASS_WAIT = 30
JusticeAlerts.GLASS_ICON = "Interface\\Icons\\INV_Drink_05"
JusticeAlerts.GLASS_GAP = { default = 5, min = 3, max = 15 } -- minutes

local glassShownAt, glassAskedAt  -- Now() of the last glass popup shown, and asked for

function JusticeAlerts.GlassGap()
    local G = JusticeAlerts.GLASS_GAP
    local minutes = tonumber(ns.db and ns.db.settings.alerts.glassPopupGap) or G.default
    return math.max(G.min, math.min(G.max, minutes)) * 60
end

-- A player on the poster: faction crest, race and class icons, then the level ("??" for
-- a skull); "" when nothing is known
function JusticeAlerts.WhoLine(who, faction)
    local icons = ns.MainWindow.FactionIcon(faction, 18) .. ns.Utils.RaceIcon(who.race, who.sex, 18)
        .. ns.Utils.ClassIcon(who.class, 18)
    local level = who.level == -1 and "??" or who.level
    if not level then return icons end
    level = (LEVEL or "Level") .. " " .. level
    return icons == "" and level or (icons .. "  " .. level)
end

-- test (/hh dev glass): a made-up bust; the glass is never saved or sent
function JusticeAlerts:AskGlass(record, outlaw, test)
    local db = ns.db
    if not (db and db.settings.alerts.glassPopup) or not ns.Glasses:CanRaise(record) then return nil end
    local now = ns.Utils.Now()
    if glassShownAt and now - glassShownAt < JusticeAlerts.GlassGap() then return nil end
    -- One waiting for a fight to end is enough
    if glassAskedAt and now - glassAskedAt < self.GLASS_WAIT then return nil end
    glassAskedAt = now
    local by = record.killer or record.hunter
    local outlawWho = ns.Wanted:Get(record.outlaw) or ns.EnemyCache:ByKey(record.outlaw) or record.outlawWho or {}
    local byWho = ns.Justice.KillerWho(record) or ns.Justice.Identity(by) or (by and ns.EnemyCache:ByKey(by)) or {}
    return ns.Alerts:Show({
        key = "glass:" .. record.id,
        throttle = 0,
        maxAge = self.GLASS_WAIT,
        sound = "soft",
        toast = {
            heading = L.POSTER_WANTED,
            title = outlaw,
            titleInfo = JusticeAlerts.WhoLine(outlawWho, outlawWho.faction or ns.MainWindow.EntryFaction(outlawWho)),
            stamp = L.GLASS_STAMP,
            text = string.format(L.GLASS_BUSTED_BY, Name(by)),
            textInfo = JusticeAlerts.WhoLine(byWho, byWho.faction or ns.Utils.RaceFaction(byWho.race)),
            icon = self.GLASS_ICON,
            accept = L.GLASS_RAISE,
            decline = CANCEL or "Cancel",
            seconds = self.GLASS_WAIT,
            onAccept = function()
                if test then
                    print("HeadHunter dev: test glass raised (not saved, not sent)")
                else
                    ns.Glasses:Raise(record, true)
                end
            end,
        },
    })
end

-- Forget when the last glass popup was (tests)
function JusticeAlerts:ResetGlass()
    glassShownAt, glassAskedAt = nil, nil
end

-- /hh dev glass (HeadHunter_Dev): the popup of a made-up bust of `outlaw` by a made-up
-- HeadHunter, at once (the gap is forgotten); the other rules still apply
function JusticeAlerts:TestGlass(outlaw)
    self:ResetGlass()
    local now = ns.Utils.ServerTime()
    local horde = ns.Utils.UnitFaction("player") == "Horde"
    local record = { id = outlaw .. ":" .. now .. ":dev", outlaw = outlaw, t = now, killer = "Kestrel Vane",
        hunter = "Kestrel Vane", origin = "peer", killerClass = "HUNTER", killerRace = horde and "Tauren" or "Dwarf",
        killerSex = 3, killerFaction = horde and "Horde" or "Alliance", killerLevel = 30,
        outlawWho = { class = "ROGUE", race = horde and "Human" or "Orc", sex = 2, level = 30,
            faction = horde and "Alliance" or "Horde" } }
    return self:AskGlass(record, ns.Utils.DisplayName(outlaw) or outlaw, true)
end

-- Glasses to our catches (author, 2026-10-04): a chat line when another HeadHunter
-- raises a glass to a catch of ours. Glasses that come within THANKS_WAIT seconds of the
-- first make one line ("X and 4 others"). Through Alerts:Show, so none in instances and
-- held during a fight; off with the glassThanks setting.
JusticeAlerts.THANKS_WAIT = 10

local thanks = {} -- catch id -> the HeadHunters who raised a glass, first first

function JusticeAlerts:OnGlass(g)
    if g.origin ~= "peer" or not (ns.db and ns.db.settings.alerts.glassThanks) then return end
    local catch = ns.Justice:Get(g.outlaw .. ":" .. g.caughtAt)
    if not catch or not ns.Glasses.Own(catch, ns.Utils.UnitKey("player")) then return end
    local id = g.outlaw .. ":" .. g.caughtAt
    if thanks[id] then
        table.insert(thanks[id], g.by)
        return
    end
    thanks[id] = { g.by }
    C_Timer.After(self.THANKS_WAIT, function() JusticeAlerts:SayThanks(id, catch) end)
end

function JusticeAlerts:SayThanks(id, catch)
    local names = thanks[id]
    thanks[id] = nil
    if not names then return nil end
    local U = ns.Utils
    local entry = ns.Wanted:Get(catch.outlaw)
    local outlaw = (entry and (entry.key and U.DisplayName(entry.key) or entry.name))
        or (not catch.outlaw:find("^guid:") and U.DisplayName(catch.outlaw)) or "?"
    local line = #names == 1 and string.format(L.GLASS_THANKS, Name(names[1]), outlaw)
        or string.format(L.GLASS_THANKS_MORE, Name(names[1]), #names - 1, outlaw)
    return ns.Alerts:Show({ key = "thanks:" .. id .. ":" .. U.Now(), throttle = 0, chat = line, sound = "soft" })
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("HH_GLASS_ADDED", function(_, g) JusticeAlerts:OnGlass(g) end, OWNER)
    ns.Events:Register("HH_WANTED_CAUGHT", function(_, entry, before) JusticeAlerts:OnCaught(entry, before) end, OWNER)
    ns.Events:Register("HH_ALERT_SHOWN", function(_, alert)
        if alert.key and alert.key:find("^glass:") then glassShownAt = ns.Utils.Now() end
    end, OWNER)
end, OWNER)
