-- Raise a glass (author, 2026-10-04): any HeadHunter can raise a glass to a catch in the
-- Busted list, the saloon's way to say well done, with or without a website account.
-- One per HeadHunter and catch, never to their own catch, no bounty. A glass stays
-- raised: a "lowered" message some players missed would leave the counts different.
-- Shared with the HeadHunters online (type "Y"; the sender speaks only for themselves),
-- under a per-sender limit. HeadHunter Sync sends the glasses we know to the website,
-- which adds its own and sends the counts back (Sync/SiteData.lua): a catch shows the
-- larger of the two.
-- ns.db.glasses: id "<outlaw>:<caught at>:<by>" -> { outlaw, caughtAt, t, by }, kept as
-- long as the catches (Reports.MAX_AGE).
-- Fires HH_GLASS_ADDED(glass).

local addonName, ns = ...

local Glasses = ns:RegisterModule("Glasses", {})

local OWNER = "Glasses"

Glasses.MAX_SKEW = 300
Glasses.SENDER_LIMIT = 20      -- glasses accepted per sender per window
Glasses.SENDER_WINDOW = 600

local senderLog = {}

local function Store()
    return ns.db and ns.db.glasses
end

function Glasses.Id(outlaw, caughtAt, by)
    return outlaw .. ":" .. caughtAt .. ":" .. by
end

function Glasses:All()
    return pairs(Store() or {})
end

-- The glasses raised to a catch (a Justice record), and whether we raised one
function Glasses:Of(catch)
    local me = ns.Utils.UnitKey("player")
    local count, ours = 0, false
    for _, g in self:All() do
        if g.outlaw == catch.outlaw and g.caughtAt == catch.t then
            count = count + 1
            ours = ours or ns.Utils.SameCharacter(g.by, me)
        end
    end
    return count, ours
end

-- The count to show: ours or the website's, the larger
function Glasses:Count(catch)
    local count = self:Of(catch)
    return math.max(count, ns.SiteData:Glasses(catch.outlaw, catch.t) or 0)
end

-- A catch by this character: who landed the blow or who reported it
function Glasses.Own(catch, who)
    local U = ns.Utils
    return (catch.killer and U.SameCharacter(catch.killer, who)) or (catch.hunter and U.SameCharacter(catch.hunter, who))
        or false
end

function Glasses:CanRaise(catch)
    local me = ns.Utils.UnitKey("player")
    if not me or Glasses.Own(catch, me) then return false end
    local _, ours = self:Of(catch)
    return not ours
end

function Glasses:Add(g, origin, sender)
    local store = Store()
    if not store or not g.outlaw or not g.by or not g.caughtAt then return nil end
    g.id = Glasses.Id(g.outlaw, g.caughtAt, g.by)
    if store[g.id] then return nil end
    g.origin, g.sender = origin, sender
    store[g.id] = g
    ns.Events:Fire("HH_GLASS_ADDED", g)
    return g
end

-- We raise a glass to a catch (a Justice record); popup: from the popup at the moment of
-- the bust (Alerts/Justice.lua), the only glasses the Barflies ranking counts. nil when
-- we may not.
function Glasses:Raise(catch, popup)
    if not catch or not self:CanRaise(catch) then return nil end
    local U = ns.Utils
    local g = self:Add({ outlaw = catch.outlaw, caughtAt = catch.t, t = U.ServerTime(), by = U.UnitKey("player"),
        popup = popup and true or nil }, "local")
    if not g then return nil end
    local P, Transport = ns.Protocol, ns.Transport
    Transport:Queue(P.TYPES.GLASS, P.EncodeGlass(g), Transport.PRIORITY.bulk, "Y:" .. g.id)
    return g
end

function Glasses:Prune(now)
    local store = Store()
    if not store then return end
    local minTime = (now or ns.Utils.ServerTime()) - ns.Reports.MAX_AGE
    for id, g in pairs(store) do
        if type(g) ~= "table" or (tonumber(g.caughtAt) or 0) < minTime then store[id] = nil end
    end
end

-------------------------------------------------
-- Peers
-------------------------------------------------

local function UnderRateLimit(sender)
    local id = ns.Utils.CompactName(sender)
    if not id then return false end
    local now = ns.Utils.Now()
    local recent = {}
    for _, at in ipairs(senderLog[id] or {}) do
        if now - at < Glasses.SENDER_WINDOW then recent[#recent + 1] = at end
    end
    senderLog[id] = recent
    if #recent >= Glasses.SENDER_LIMIT then return false end
    recent[#recent + 1] = now
    return true
end

function Glasses:OnPeer(record, sender)
    local U = ns.Utils
    local g = ns.Protocol.DecodeGlass(record)
    if not g or not U.SameCharacter(sender, g.by) then return nil end
    if not g.outlaw:find("^guid:") then
        g.outlaw = U.PlayerKey(g.outlaw)
        if not g.outlaw then return nil end
    end
    g.by = U.PlayerKey(g.by)
    if not g.by then return nil end
    local now = U.ServerTime()
    if g.t > now + self.MAX_SKEW or g.caughtAt < now - ns.Reports.MAX_AGE then return nil end
    -- Never to their own catch, when we know the catch
    local catch = ns.Justice:Get(g.outlaw .. ":" .. g.caughtAt)
    if catch and Glasses.Own(catch, g.by) then return nil end
    if not UnderRateLimit(sender) then return nil end
    return self:Add(g, "peer", sender)
end

-- Forget the senders' limits (tests)
function Glasses:Reset()
    senderLog = {}
end

ns.Events:Register("HH_INITIALIZED", function()
    Glasses:Prune()
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.GLASS, function(record, sender) Glasses:OnPeer(record, sender) end)
end, OWNER)
