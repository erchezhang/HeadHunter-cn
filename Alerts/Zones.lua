-- HH-040: which zones are "near" for alerts (docs/addon/features.md section 4).
--
-- Range setting (settings.alerts.range):
--   "adjacent"  (default) the player's zone and the zones bordering it
--   "continent" anywhere on the player's continent
--
-- Classic uiMapIDs (Classic Era; Forever uses the same Vanilla maps). Borders follow
-- Vanilla roads and paths; boats and flight paths do not count. Each border is listed once and made symmetric below. Confirm doubtful
-- borders in game (HH-070).

local addonName, ns = ...

local Zones = ns:RegisterModule("Zones", {})

local EASTERN_KINGDOMS, KALIMDOR = 1415, 1414

-- mapID -> continent (also the list of known zones)
local CONTINENT = {}
local EK = {
    1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429,
    1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437, 1453, 1455, 1458,
}
local KAL = {
    1411, 1412, 1413, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448,
    1449, 1450, 1451, 1452, 1454, 1456, 1457,
}
for _, id in ipairs(EK) do CONTINENT[id] = EASTERN_KINGDOMS end
for _, id in ipairs(KAL) do CONTINENT[id] = KALIMDOR end

local BORDERS = {
    -- Eastern Kingdoms
    { 1429, 1436 }, { 1429, 1431 }, { 1429, 1433 }, { 1429, 1453 },  -- Elwynn: Westfall, Duskwood, Redridge, Stormwind
    { 1436, 1431 },                                                    -- Westfall - Duskwood
    { 1431, 1433 }, { 1431, 1430 }, { 1431, 1434 },                    -- Duskwood: Redridge, Deadwind, Stranglethorn
    { 1433, 1428 },                                                    -- Redridge - Burning Steppes
    { 1430, 1435 },                                                    -- Deadwind - Swamp of Sorrows
    { 1435, 1419 },                                                    -- Swamp - Blasted Lands
    { 1428, 1427 },                                                    -- Burning Steppes - Searing Gorge
    { 1427, 1418 }, { 1427, 1432 },                                    -- Searing Gorge: Badlands, Loch Modan (gate)
    { 1418, 1432 },                                                    -- Badlands - Loch Modan
    { 1432, 1426 }, { 1432, 1437 },                                    -- Loch Modan: Dun Morogh, Wetlands
    { 1426, 1455 },                                                    -- Dun Morogh - Ironforge
    { 1437, 1417 },                                                    -- Wetlands - Arathi
    { 1417, 1424 }, { 1417, 1425 },                                    -- Arathi: Hillsbrad, Hinterlands
    { 1424, 1416 }, { 1424, 1421 }, { 1424, 1425 },                    -- Hillsbrad: Alterac, Silverpine, Hinterlands
    { 1416, 1421 }, { 1416, 1422 },                                    -- Alterac: Silverpine, Western Plaguelands
    { 1421, 1420 },                                                    -- Silverpine - Tirisfal
    { 1420, 1422 }, { 1420, 1458 },                                    -- Tirisfal: Western Plaguelands, Undercity
    { 1422, 1423 }, { 1422, 1425 },                                    -- WPL: EPL, Hinterlands
    -- Kalimdor
    { 1411, 1413 }, { 1411, 1454 },                                    -- Durotar: Barrens, Orgrimmar
    { 1454, 1413 },                                                    -- Orgrimmar - Barrens
    { 1413, 1412 }, { 1413, 1440 }, { 1413, 1442 }, { 1413, 1445 }, { 1413, 1441 }, -- Barrens
    { 1412, 1456 },                                                    -- Mulgore - Thunder Bluff
    { 1442, 1440 }, { 1442, 1443 },                                    -- Stonetalon: Ashenvale, Desolace
    { 1440, 1439 }, { 1440, 1448 }, { 1440, 1447 },                    -- Ashenvale: Darkshore, Felwood, Azshara
    { 1438, 1457 },                                                    -- Teldrassil - Darnassus
    { 1448, 1452 }, { 1448, 1450 }, { 1452, 1450 },                    -- Felwood, Winterspring, Moonglade
    { 1443, 1444 },                                                    -- Desolace - Feralas
    { 1444, 1441 },                                                    -- Feralas - Thousand Needles
    { 1441, 1446 },                                                    -- Thousand Needles - Tanaris
    { 1446, 1449 },                                                    -- Tanaris - Un'Goro
    { 1449, 1451 },                                                    -- Un'Goro - Silithus
}

local NEIGHBORS = {}
for _, pair in ipairs(BORDERS) do
    local a, b = pair[1], pair[2]
    NEIGHBORS[a] = NEIGHBORS[a] or {}
    NEIGHBORS[b] = NEIGHBORS[b] or {}
    NEIGHBORS[a][b] = true
    NEIGHBORS[b][a] = true
end

Zones.CONTINENT = CONTINENT
Zones.NEIGHBORS = NEIGHBORS

-- Normalise any map (cave, sub-zone, micro-dungeon) to the zone it belongs to
function Zones.ZoneOf(mapID)
    mapID = tonumber(mapID)
    local id = mapID
    for _ = 1, 6 do
        if not id then return mapID end
        if CONTINENT[id] then return id end
        local info = C_Map and ns.Utils.SafeCall(C_Map.GetMapInfo, id)
        if not info or not info.parentMapID or info.parentMapID == 0 then break end
        id = info.parentMapID
    end
    return mapID
end

-- Where childMapID sits on ancestorMapID: minX, maxX, minY, maxY (0..1), or nil
function Zones.RectOn(childMapID, ancestorMapID)
    if not (C_Map and childMapID and ancestorMapID) then return nil end
    local U = ns.Utils
    local minX, maxX, minY, maxY = U.SafeCall(C_Map.GetMapRectOnMap, childMapID, ancestorMapID)
    minX, maxX = tonumber(U.Accessible(minX)), tonumber(U.Accessible(maxX))
    minY, maxY = tonumber(U.Accessible(minY)), tonumber(U.Accessible(maxY))
    if not (minX and maxX and minY and maxY) or maxX <= minX or maxY <= minY then return nil end
    return minX, maxX, minY, maxY
end

Zones.ZONE_TYPE = 3

-- Is mapID the continent itself (in a cave the game may give no map closer than that) or a
-- dungeon entrance or other map whose parent is the continent (author, 2026-11-15: fights
-- at the Gnomeregan and Razorfen Downs entrances showed on the continent, named Kalimdor
-- or Eastern Kingdoms, but not on Dun Morogh or the Barrens)? Zones and new Forever zones
-- are not.
local function Orphan(mapID)
    if CONTINENT[mapID] then return false end
    local info = C_Map and ns.Utils.SafeCall(C_Map.GetMapInfo, mapID)
    if not info then return false end
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or Zones.ZONE_TYPE
    return info.mapType ~= zoneType
end

-- Is cx, cy (0..1 on continent) inside zone's box on that continent? Returns the box's area.
local function BoxArea(zone, continent, cx, cy)
    local minX, maxX, minY, maxY = Zones.RectOn(zone, continent)
    if not minX or cx < minX or cx > maxX or cy < minY or cy > maxY then return nil end
    return (maxX - minX) * (maxY - minY)
end

-- The known zone at cx, cy on continent: the one the game names there, else the smallest
-- zone whose box holds the point (boxes overlap; a small one is the closer fit). nil if none.
local function ZoneAt(continent, cx, cy)
    local info = C_Map and ns.Utils.SafeCall(C_Map.GetMapInfoAtPosition, continent, cx, cy)
    local named = info and Zones.ZoneOf(tonumber(info.mapID))
    if named and CONTINENT[named] == continent then return named end
    local best, bestArea
    for zone, onContinent in pairs(CONTINENT) do
        local area = onContinent == continent and BoxArea(zone, continent, cx, cy)
        if area and (not bestArea or area < bestArea) then best, bestArea = zone, area end
    end
    return best
end

-- x, y on mapID as continent, cx, cy on its continent, or nil
local function OnContinent(mapID, x, y)
    local continent = ns.Utils.ContinentOf(mapID)
    if continent == mapID then return continent, x, y end
    local minX, maxX, minY, maxY = Zones.RectOn(mapID, continent)
    if not minX then return nil end
    return continent, minX + x * (maxX - minX), minY + y * (maxY - minY)
end

-- An orphan map's position as zone, x, y on the zone around it, or nil
local function Locate(mapID, x, y)
    local continent, cx, cy = OnContinent(mapID, x, y)
    if not continent then return nil end
    local zone = ZoneAt(continent, cx, cy)
    local zMinX, zMaxX, zMinY, zMaxY = Zones.RectOn(zone, continent)
    if not zMinX then return nil end
    return zone, (cx - zMinX) / (zMaxX - zMinX), (cy - zMinY) / (zMaxY - zMinY)
end

-- A position on mapID (a cave, sub-zone or dungeon entrance map included) as a position
-- on its zone: zone, x, y. The position is nil when it cannot be translated (a wrong spot
-- is worse than none).
function Zones.ToZone(mapID, x, y)
    local zone = Zones.ZoneOf(mapID)
    if not zone or not (x and y) then return zone, nil, nil end
    if Orphan(zone) then
        local found, zx, zy = Locate(zone, x, y)
        if found then return found, zx, zy end
    end
    if zone == tonumber(mapID) then return zone, x, y end
    local minX, maxX, minY, maxY = Zones.RectOn(mapID, zone)
    if not minX then return zone, nil, nil end
    return zone, minX + x * (maxX - minX), minY + y * (maxY - minY)
end

function Zones.ContinentOf(mapID)
    local zone = Zones.ZoneOf(mapID)
    return zone and (CONTINENT[zone] or ns.Utils.ContinentOf(zone))
end

-- A zone by its name as the game shows it ("Silverpine Forest"), ignoring case; a
-- unique start of a name also works ("silverpine"). nil when unknown or unclear.
function Zones.FindByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local wanted = name:lower()
    local found
    for mapID in pairs(CONTINENT) do
        local zoneName = ns.Utils.MapName(mapID)
        local lower = zoneName and zoneName:lower()
        if lower == wanted then return mapID end
        if lower and lower:sub(1, #wanted) == wanted then
            if found then return nil end
            found = mapID
        end
    end
    return found
end

function Zones.AreNeighbors(a, b)
    return NEIGHBORS[a] ~= nil and NEIGHBORS[a][b] == true
end

-- "zone" | "adjacent" | "continent" | nil (farther or unknown)
function Zones.Distance(eventMapID, playerMapID)
    local a, b = Zones.ZoneOf(eventMapID), Zones.ZoneOf(playerMapID)
    if not a or not b then return nil end
    if a == b then return "zone" end
    if Zones.AreNeighbors(a, b) then return "adjacent" end
    local ca, cb = Zones.ContinentOf(a), Zones.ContinentOf(b)
    if ca and ca == cb then return "continent" end
    return nil
end

-- Is an event on eventMapID inside the player's alert range?
function Zones.InRange(eventMapID, playerMapID, range)
    local distance = Zones.Distance(eventMapID, playerMapID or ns.Utils.PlayerMapID())
    if not distance then return false, nil end
    range = range or (ns.db and ns.db.settings.alerts.range) or "adjacent"
    if distance == "continent" then return range == "continent", distance end
    return true, distance
end

-------------------------------------------------
-- Zone names for the website: the game knows every zone's name, the saved data does
-- not. Each zone seen in a report, duel or catch is kept in ns.db.zones, so the
-- desktop sync app can send new zones (new Forever zones too). Names come in the
-- player's language; the website keeps its own English names first.
-------------------------------------------------

function Zones:Remember(mapID)
    local store = ns.db and ns.db.zones
    local zone = Zones.ZoneOf(mapID)
    if not store or not zone or store[zone] then return nil end
    local name = ns.Utils.MapName(zone)
    if not name then return nil end
    store[zone] = {
        name = name,
        continent = Zones.ContinentOf(zone),
        locale = ns.Utils.SafeCall(_G.GetLocale),
    }
    return store[zone]
end

ns.Events:Register("HH_INITIALIZED", function()
    for _, event in ipairs({ "HH_REPORT_ADDED", "HH_DUEL_ADDED", "HH_JUSTICE_ADDED" }) do
        ns.Events:Register(event, function(_, record) Zones:Remember(record and record.mapID) end, "Zones")
    end
end, "Zones")
