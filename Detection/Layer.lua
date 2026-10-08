-- Which layer (Era) / shard (Forever) of the zone we are on.
--
-- The layer is the zoneUID field of NPC and object GUIDs:
--   Creature-0-<server>-<instance>-<zoneUID>-<npcID>-<spawnUID>
-- as layer addons read it on both clients. A zoneUID of 0 falls back to the
-- instance field.
-- Only meaningful inside one zone: readings are tied to the zone they were taken
-- in and cleared on zone change. Unknown (nil) until an NPC has been seen.
--
--   Layer:Current(maxAge) -> layerID or nil
--   Layer.FromGUID(guid)  -> layerID or nil (pure)
--   HH_LAYER_CHANGED(layer, zone) fires when our layer in a zone is first read or changes

local addonName, ns = ...

local Layer = ns:RegisterModule("Layer", {})

local OWNER = "Layer"

Layer.MAX_ID = 100000
Layer.FRESH = 60              -- seconds a reading stays valid
Layer.SCAN_UNITS = { "target", "mouseover", "focus", "softenemy", "softfriend", "softinteract" }

local reading                  -- { id, zone, at }

local LAYERED_TYPES = { Creature = true, Vehicle = true, GameObject = true, Vignette = true }

local function Parse(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local guidType, zero, _, instanceId, zoneUid = strsplit("-", guid)
    if not LAYERED_TYPES[guidType] or zero ~= "0" then return nil end
    local layer = tonumber(zoneUid)
    if not layer or layer < 0 or layer >= Layer.MAX_ID then return nil end
    if layer > 0 then return layer end
    local instance = tonumber(instanceId)
    if instance and instance > 0 and instance < Layer.MAX_ID then return instance end
    return nil
end

-- pcall: GUIDs can be secret values on the 12.x engine (Forever)
function Layer.FromGUID(guid)
    guid = ns.Utils.AccessibleString(guid)
    if not guid then return nil end
    local ok, layer = pcall(Parse, guid)
    return ok and layer or nil
end

-- Fires HH_LAYER_CHANGED(layer, zone) when the reading for this zone is new or differs
local function Record(layer)
    if not layer then return false end
    local zone = ns.Zones.ZoneOf(ns.Utils.PlayerMapID())
    local old = reading and reading.zone == zone and reading.id
    reading = { id = layer, zone = zone, at = ns.Utils.Now() }
    if old ~= layer then ns.Events:Fire("HH_LAYER_CHANGED", layer, zone) end
    return true
end

-- Read one unit (NPCs only: player GUIDs carry no layer)
function Layer:ObserveUnit(unit)
    if ns.Utils.UnitIsPlayer(unit) then return false end
    return Record(Layer.FromGUID(ns.Utils.UnitGUID(unit)))
end

function Layer:Scan()
    for _, unit in ipairs(self.SCAN_UNITS) do
        if self:ObserveUnit(unit) then return true end
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = ns.Utils.SafeCall(C_NamePlate.GetNamePlates)
        for _, plate in ipairs(type(plates) == "table" and plates or {}) do
            local ok, unit = pcall(function() return plate.namePlateUnitToken end)
            if ok and unit and self:ObserveUnit(unit) then return true end
        end
    end
    for i = 1, 40 do
        if self:ObserveUnit("nameplate" .. i) then return true end
    end
    return false
end

-- Current layer, or nil when unknown or stale. Rescans when the reading is old.
function Layer:Current(maxAge)
    maxAge = maxAge or self.FRESH
    local zone = ns.Zones.ZoneOf(ns.Utils.PlayerMapID())
    local fresh = reading and reading.zone == zone and ns.Utils.Now() - reading.at <= maxAge
    if not fresh then
        reading = nil
        self:Scan()
    end
    return reading and reading.id or nil
end

function Layer:Clear()
    reading = nil
end

-- The raw reading behind Current(): layer, zone and age in seconds, or nil when
-- unknown or stale (the toolbox card shows all three).
function Layer:Status()
    local layer = Layer:Current()
    if not layer then return nil end
    return layer, reading.zone, math.floor(ns.Utils.Now() - reading.at)
end

-- Compare a layer seen on mapID with ours. "same" | "different" | nil (unknown, or
-- another zone: layer numbers only mean something inside one zone). Also returns
-- our layer.
function Layer:Compare(otherLayer, mapID)
    if not otherLayer or not mapID then return nil end
    local Zones = ns.Zones
    if Zones.ZoneOf(mapID) ~= Zones.ZoneOf(ns.Utils.PlayerMapID()) then return nil end
    local mine = self:Current()
    if not mine then return nil end
    return mine == otherLayer and "same" or "different", mine
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

ns.Events:Register("HH_INITIALIZED", function()
    local Events = ns.Events
    Events:Register("NAME_PLATE_UNIT_ADDED", function(_, unit) Layer:ObserveUnit(unit) end, OWNER)
    Events:Register("PLAYER_TARGET_CHANGED", function() Layer:ObserveUnit("target") end, OWNER)
    Events:Register("UPDATE_MOUSEOVER_UNIT", function() Layer:ObserveUnit("mouseover") end, OWNER)
    Events:Register("ZONE_CHANGED_NEW_AREA", function() Layer:Clear() end, OWNER)
end, OWNER)

ns.SlashCommands:Register("layer", function()
    local layer = Layer:Current()
    if layer then
        ns:Print(string.format(ns.L.LAYER_CURRENT, layer, math.floor(ns.Utils.Now() - reading.at)))
    else
        ns:Print(ns.L.LAYER_UNKNOWN)
    end
end, ns.L.HELP_LAYER)
