-- HH-102: are we in Gurubashi Arena, or at another tournament venue? (docs/addon/features.md section 11)
--
-- The arena has no map of its own: it is part of Stranglethorn Vale. So it is a
-- position check on that map, locale-safe (no subzone text). Two ovals around the same
-- center: the whole arena (stands and pit) and the pit, where the fights happen.
-- The pit is measured in game; the stands are still a guess (/hh arena shows the
-- position, to set them in game).
--
--   Arena.Where(mapID, x, y) -> "pit" | "arena" | nil   (pure, tested offline)
--   Arena:PlayerWhere()      -> the same for the player

local addonName, ns = ...
local L = ns.L

local Arena = ns:RegisterModule("Arena", {})

Arena.MAP_ID = 1434                      -- Stranglethorn Vale
Arena.CENTER = { x = 0.3055, y = 0.4785 } -- pit center, from its 4 edges measured in game (2026-09-23)
Arena.ARENA = { x = 0.012, y = 0.019 }    -- pit and stands; seats start S 49.2, W 29.7, N 46.5 (back: a guess)
Arena.PIT = { x = 0.007, y = 0.011 }      -- half widths: E 31.2, W 29.9, N 46.8, S 48.9 (+ a small margin)

local function Inside(x, y, size)
    local dx = (x - Arena.CENTER.x) / size.x
    local dy = (y - Arena.CENTER.y) / size.y
    return dx * dx + dy * dy <= 1
end

function Arena.Where(mapID, x, y)
    if mapID ~= Arena.MAP_ID or not x or not y then return nil end
    if Inside(x, y, Arena.PIT) then return "pit" end
    if Inside(x, y, Arena.ARENA) then return "arena" end
    return nil
end

-- The player's zone map (a cave or sub-map counts as its zone) and position on it
function Arena:PlayerWhere()
    local U = ns.Utils
    local mapID = ns.Zones.ZoneOf(U.PlayerMapID())
    if not mapID then return nil end
    local x, y = U.PlayerPosition(mapID)
    return Arena.Where(mapID, x, y), mapID, x, y
end

function Arena:InArena()
    return self:PlayerWhere() ~= nil
end

-------------------------------------------------
-- Venues (author, 2026-09-23): Gurubashi Arena for both factions, and each faction's
-- usual dueling spots outside its capitals, for that faction only. Every venue is an
-- oval on a zone map: `area` (where you must be for check-in) and `fight` (where the
-- games are fought; the pit at Gurubashi, the whole spot elsewhere). The city spots
-- are first guesses from the maps: /hh arena shows the position to set them in game.
-------------------------------------------------

Arena.VENUES = {
    { id = "gurubashi", mapID = Arena.MAP_ID, center = Arena.CENTER, fight = Arena.PIT, area = Arena.ARENA },
    { id = "orgrimmar", mapID = 1411, center = { x = 0.458, y = 0.130 }, fight = { x = 0.015, y = 0.020 },
        area = { x = 0.015, y = 0.020 }, faction = "Horde" },          -- Durotar, outside the gate (a guess)
    { id = "undercity", mapID = 1420, center = { x = 0.618, y = 0.690 }, fight = { x = 0.015, y = 0.020 },
        area = { x = 0.015, y = 0.020 }, faction = "Horde" },          -- Tirisfal, before the ruins (a guess)
    { id = "ironforge", mapID = 1426, center = { x = 0.533, y = 0.355 }, fight = { x = 0.015, y = 0.020 },
        area = { x = 0.015, y = 0.020 }, faction = "Alliance" },       -- Dun Morogh, outside the gate (a guess)
    { id = "stormwind", mapID = 1429, center = { x = 0.328, y = 0.503 }, fight = { x = 0.015, y = 0.020 },
        area = { x = 0.015, y = 0.020 }, faction = "Alliance" },       -- Elwynn, outside the gate (a guess)
}
Arena.VENUE = {}
for _, venue in ipairs(Arena.VENUES) do Arena.VENUE[venue.id] = venue end
Arena.DEFAULT_VENUE = "gurubashi"

local function InOval(venue, x, y, size)
    local dx = (x - venue.center.x) / size.x
    local dy = (y - venue.center.y) / size.y
    return dx * dx + dy * dy <= 1
end

-- "fight" | "area" | nil for a position on a zone map
function Arena.VenueWhere(venueId, mapID, x, y)
    local venue = Arena.VENUE[venueId]
    if not venue or mapID ~= venue.mapID or not x or not y then return nil end
    if InOval(venue, x, y, venue.fight) then return "fight" end
    if InOval(venue, x, y, venue.area) then return "area" end
    return nil
end

function Arena.VenueName(venueId)
    return L["VENUE_" .. tostring(venueId):upper()]
end

-- Where the player is at a venue: "fight" | "area" | nil
function Arena:PlayerAt(venueId)
    local U = ns.Utils
    local mapID = ns.Zones.ZoneOf(U.PlayerMapID())
    if not mapID then return nil end
    return Arena.VenueWhere(venueId, mapID, U.PlayerPosition(mapID))
end

-- The venue the player is at, if any: venue, "fight" | "area", mapID, x, y
function Arena:PlayerVenue()
    local U = ns.Utils
    local mapID = ns.Zones.ZoneOf(U.PlayerMapID())
    if not mapID then return nil end
    local x, y = U.PlayerPosition(mapID)
    for _, venue in ipairs(Arena.VENUES) do
        local where = Arena.VenueWhere(venue.id, mapID, x, y)
        if where then return venue, where, mapID, x, y end
    end
    return nil, nil, mapID, x, y
end

-------------------------------------------------
-- /hh arena: where we are, to check and set the venues in game
ns.SlashCommands:Register("arena", function()
    local venue, where, mapID, x, y = Arena:PlayerVenue()
    local position = x and string.format("%.1f, %.1f", x * 100, y * 100) or "?"
    local text
    if not venue then
        text = L.ARENA_OUTSIDE
    elseif venue.id == "gurubashi" then
        text = where == "fight" and L.ARENA_IN_PIT or L.ARENA_IN_ARENA
    else
        text = string.format(L.VENUE_AT, Arena.VenueName(venue.id))
    end
    ns:Print(string.format(L.ARENA_WHERE, ns.Utils.MapName(mapID) or tostring(mapID), position, text))
end, L.HELP_ARENA)
