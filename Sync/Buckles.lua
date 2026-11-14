-- HH-161: the website's buckles (WEB-127) in game. The website rolls and decides; the
-- download (Sync/SiteData.lua, read once per load) brings our characters' finds and the
-- world's worn buckles, and this module only shows them:
--
--   * the login reveal: "You found a buckle", once per find (`uid`, kept account-wide in
--     db.bucklesShown), our characters' finds one after another, never in combat or an
--     instance; a quiet find (awarded for what was earned before buckles started) is only
--     marked shown
--   * the buckle case (/hh buckles): each of our characters' buckles, rarest first, with
--     counts and where they came from, and the ones still to find
--   * a worn buckle on the player tooltip (UI/TooltipLine.lua)
--
-- Each buckle is a texture (Assets/Buckles/<id>.tga, the website's design without its
-- name, which is a translated text here). A buckle id this version does not know shows
-- its quality's plate (plate_<quality>.tga) with the English name the download gives, so
-- a new buckle with an existing look needs no release.

local addonName, ns = ...
local L = ns.L

local Buckles = ns:RegisterModule("Buckles", {})

local OWNER = "Buckles"

Buckles.TEXTURES = "Interface\\AddOns\\HeadHunter\\Assets\\Buckles\\"

-- The plate's place on its 256x128 texture: left, right, top, bottom in pixels
Buckles.CROP = { 40, 216, 0, 128 }

-- Seconds after login before the reveal
Buckles.REVEAL_DELAY = 12

-- The website's Buckle enum, in its order; Pioneer can no longer be earned
Buckles.CATALOG = {
    { id = "tin_star", quality = "uncommon" },
    { id = "badge_taker", quality = "rare" },
    { id = "hunters_bane", quality = "epic" },
    { id = "fair_fight", quality = "uncommon" },
    { id = "bully_breaker", quality = "rare" },
    { id = "iron_justice", quality = "epic" },
    { id = "quick_hand", quality = "uncommon" },
    { id = "upset_at_high_noon", quality = "rare" },
    { id = "fastest_gun", quality = "epic" },
    { id = "last_call", quality = "uncommon" },
    { id = "whiskey_neat", quality = "rare" },
    { id = "saloon_royalty", quality = "epic" },
    { id = "dead_mans_hand", quality = "legendary" },
    { id = "sunset_rider", quality = "legendary" },
    { id = "pioneer", quality = "awarded", earnedOnce = true },
    { id = "champion", quality = "awarded" },
    { id = "finalist", quality = "awarded" },
}

-- id -> catalogue entry, with its place in the catalogue
Buckles.BY_ID = {}
for i, entry in ipairs(Buckles.CATALOG) do
    entry.place = i
    Buckles.BY_ID[entry.id] = entry
end

-- WoW's item quality colours; Awarded is the heirloom gold
Buckles.QUALITY_COLORS = {
    uncommon = "1eff00", rare = "0070dd", epic = "a335ee", legendary = "ff8000", awarded = "e6cc80",
}

-- Rarest first
Buckles.QUALITY_RANK = { awarded = 1, legendary = 2, epic = 3, rare = 4, uncommon = 5 }

-- Where a dropped buckle came from: the download's source -> its text (the other player's name)
Buckles.SOURCE_TEXT = {
    hunter_kill = "BUCKLE_FROM_KILL",
    punishment = "BUCKLE_FROM_PUNISHMENT",
    duel_upset = "BUCKLE_FROM_DUEL",
    glass = "BUCKLE_FROM_GLASS",
}

local waiting = false

-- The buckle's quality: the catalogue's, else the one the download gave, else Uncommon
function Buckles.Quality(id, given)
    local known = Buckles.BY_ID[id]
    if known then return known.quality end
    return Buckles.QUALITY_COLORS[given or ""] and given or "uncommon"
end

-- The texture: the buckle's own, or its quality's plate for a buckle this version does not know
function Buckles.Texture(id, quality)
    if Buckles.BY_ID[id] then return Buckles.TEXTURES .. id end
    return Buckles.TEXTURES .. "plate_" .. Buckles.Quality(id, quality)
end

-- The translated name; else the download's English name; else the id read as words
function Buckles.Name(id, given)
    if type(id) ~= "string" then return given or "?" end
    local text = rawget(L, "BUCKLE_" .. id:upper())
    if text then return text end
    if given then return given end
    return (id:gsub("_", " "):gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

function Buckles.QualityName(quality)
    return rawget(L, "BUCKLE_Q_" .. tostring(quality):upper()) or tostring(quality)
end

function Buckles.ColoredName(id, quality, given)
    return "|cff" .. Buckles.QUALITY_COLORS[Buckles.Quality(id, quality)] .. Buckles.Name(id, given) .. "|r"
end

-- An inline texture for chat and tooltips: the plate cropped, height in pixels
function Buckles.Icon(id, quality, height)
    local c = Buckles.CROP
    local h = height or 14
    local w = math.floor(h * (c[2] - c[1]) / (c[4] - c[3]) + 0.5)
    return string.format("|T%s:%d:%d:0:0:256:128:%d:%d:%d:%d|t", Buckles.Texture(id, quality), h, w, c[1], c[2], c[3], c[4])
end

-- What a find came from: "Kill of the HeadHunter Moo Mello", Pioneer's line, the tournament
function Buckles.FromText(find)
    local key = Buckles.SOURCE_TEXT[find.source or ""]
    if key then
        return string.format(L[key], find.other and ns.Utils.DisplayName(find.other) or L.BUCKLE_SOMEONE)
    end
    if find.buckle == "pioneer" then return L.BUCKLE_FROM_PIONEER end
    return find.tournament or L.BUCKLE_FROM_TOURNAMENT
end

-- Who found it: "Found by Grul Ironhide", "Awarded to Grul Ironhide"
function Buckles.WhoText(find)
    local name = find.owner and ns.Utils.DisplayName(find.owner) or "?"
    return string.format(find.source == "award" and L.BUCKLE_AWARDED_TO or L.BUCKLE_FOUND_BY, name)
end

-- Where and when: "Stranglethorn Vale · 2026-11-14"
function Buckles.WhereText(find)
    local parts = {}
    local zone = find.mapID and ns.Utils.MapName(find.mapID)
    if zone then parts[#parts + 1] = zone end
    local at = find.eventAt or find.foundAt
    if at then parts[#parts + 1] = date("%Y-%m-%d", at) end
    return table.concat(parts, " · ")
end

function Buckles:MarkShown(uid)
    if ns.db and uid then ns.db.bucklesShown[tostring(uid)] = true end
end

function Buckles:IsShown(uid)
    return ns.db ~= nil and uid ~= nil and ns.db.bucklesShown[tostring(uid)] == true
end

-- Our characters' finds not shown yet, oldest first, and the quiet ones among them
function Buckles:Pending()
    local pending, quiet = {}, {}
    if not ns.db then return pending, quiet end
    for _, find in ipairs(ns.SiteData:BuckleFinds()) do
        if find.uid and not self:IsShown(find.uid) then
            local list = find.quiet and quiet or pending
            list[#list + 1] = find
        end
    end
    table.sort(pending, function(a, b) return (a.foundAt or 0) < (b.foundAt or 0) end)
    return pending, quiet
end

-- Whether a popup may show now: not in combat, not in an instance
function Buckles.CanShow()
    if InCombatLockdown and InCombatLockdown() then return false end
    return ns.Guards:IsActive()
end

-- Shows the new finds; in combat or an instance it waits for the fight or the instance to
-- end (PLAYER_REGEN_ENABLED, HH_SUSPEND_CHANGED), without polling
function Buckles:Reveal()
    local pending, quiet = self:Pending()
    for _, find in ipairs(quiet) do self:MarkShown(find.uid) end
    waiting = false
    if #pending == 0 or ns.BuckleDialog:IsRevealShown() then return false end
    if not self.CanShow() then
        waiting = true
        return false
    end
    return ns.BuckleDialog:ShowFinds(pending)
end

function Buckles:IsWaiting()
    return waiting
end

-- One character's case: each owned buckle once with its count and finds, rarest first,
-- then the ones still to find (not those that can no longer be earned)
function Buckles.CharacterCase(finds, worn)
    local byId, owned = {}, {}
    for _, find in ipairs(finds) do
        local entry = byId[find.buckle]
        if not entry then
            entry = { buckle = find.buckle, name = find.name, quality = Buckles.Quality(find.buckle, find.quality), finds = {} }
            byId[find.buckle] = entry
            owned[#owned + 1] = entry
        end
        entry.finds[#entry.finds + 1] = find
    end
    table.sort(owned, function(a, b)
        local ra, rb = Buckles.QUALITY_RANK[a.quality], Buckles.QUALITY_RANK[b.quality]
        if ra ~= rb then return ra < rb end
        local pa, pb = Buckles.BY_ID[a.buckle], Buckles.BY_ID[b.buckle]
        return (pa and pa.place or 99) < (pb and pb.place or 99)
    end)
    local missing = {}
    for _, entry in ipairs(Buckles.CATALOG) do
        if not byId[entry.id] and not entry.earnedOnce then missing[#missing + 1] = entry.id end
    end
    return { owned = owned, missing = missing, worn = worn }
end

-- Our characters' cases: { { key, case } }, the character we play first, then by name
function Buckles:Cases()
    local byOwner, owners = {}, {}
    for _, find in ipairs(ns.SiteData:BuckleFinds()) do
        if not byOwner[find.owner] then
            byOwner[find.owner] = {}
            owners[#owners + 1] = find.owner
        end
        table.insert(byOwner[find.owner], find)
    end
    local me = ns.Utils.UnitKey("player")
    local mine = false
    for _, owner in ipairs(owners) do
        if ns.Utils.SameCharacter(owner, me) then mine = true end
    end
    if me and not mine then
        owners[#owners + 1] = me
        byOwner[me] = {}
    end
    table.sort(owners, function(a, b)
        local aMe, bMe = ns.Utils.SameCharacter(a, me), ns.Utils.SameCharacter(b, me)
        if aMe ~= bMe then return aMe end
        return a < b
    end)
    local cases = {}
    for _, owner in ipairs(owners) do
        cases[#cases + 1] = { key = owner, case = self.CharacterCase(byOwner[owner], ns.SiteData:OwnWornBuckle(owner)) }
    end
    return cases
end

local function RevealSoon()
    C_Timer.After(Buckles.REVEAL_DELAY, function() Buckles:Reveal() end)
end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("PLAYER_LOGIN", RevealSoon, OWNER)
    ns.Events:Register("PLAYER_REGEN_ENABLED", function()
        if waiting then Buckles:Reveal() end
    end, OWNER)
    ns.Events:Register("HH_SUSPEND_CHANGED", function(_, suspended)
        if waiting and not suspended then Buckles:Reveal() end
    end, OWNER)
end, OWNER)

ns.SlashCommands:Register("buckles", function()
    ns.BuckleDialog:ShowCase()
end, L.HELP_BUCKLES)
