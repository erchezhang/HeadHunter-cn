-- HH-046: map markers. PvP areas for hotspots (Alerts/Hotspots.lua: a translucent red
-- zone with "PVP" in the middle, darker as the fight grows) and skull pins for WANTED
-- outlaws (Rules/Wanted.lua) on the world map, in the zone, continent and world views.
-- Hover: details (no click action; author, 2026-09-23).
--
-- Drawn on our own layer over the map canvas, not through the map's data-provider
-- system: on the 12.x engine (Forever) reading WorldMapFrame.mapID taints the addon
-- and raises false ADDON_ACTION_FORBIDDEN, and pin templates need XML. The shown map
-- is taken from a SetMapID hook instead, and the canvas is read inside securecall.
--
-- MapMarkers:PinsFor(mapID, now) is the pure part (tested offline): which pins, where
-- on that map and which tooltip lines. The rest only draws it.

local addonName, ns = ...
local L = ns.L

local MapMarkers = ns:RegisterModule("MapMarkers", {})

local OWNER = "MapMarkers"

MapMarkers.SKULL_ICON = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
MapMarkers.CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- white disc
MapMarkers.AREA_COLOR = { 1, 0.1, 0.05 }
-- The PvP mark in the middle of an area: crossed swords over a small "PVP" in gold
MapMarkers.SWORDS_ICON = "Interface\\AddOns\\HeadHunter\\Assets\\Textures\\swords"
MapMarkers.SWORDS_SIZE = 18
MapMarkers.LABEL_COLOR = { 1, 0.82, 0.4 }
MapMarkers.AREA_ALPHA = { 0.22, 0.36, 0.52 } -- by fire level: darker = more PvP
MapMarkers.AREA_WIDTH = 0.10               -- diameter, as a share of the zone's width
MapMarkers.AREA_MIN_PX = 32                -- never smaller on screen (continent view)
MapMarkers.WANTED_MAP_TIME = 600           -- a skull shows for 10 min after the outlaw's last
                                           -- kill (each new kill restarts it); the WANTED
                                           -- status itself lasts hours to days
MapMarkers.WANTED_SIZE = 16
MapMarkers.HUNTED_SIZE = 20                -- an outlaw our posse is hunting
MapMarkers.REFRESH = 10                    -- seconds, while the map is shown (timers, cooling)
MapMarkers.FRAME_LEVEL = 2000              -- above the map's own pins
MapMarkers.MAX_FRAME_LEVEL = 10000         -- the game's highest frame level
-- Strata from low to high. Other addons' map pins may sit in a higher one; ours follow
-- up to FULLSCREEN_DIALOG, never TOOLTIP, so tooltips stay on top.
MapMarkers.STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
MapMarkers.MAX_PER_KIND = 10               -- PvP areas and skulls each, per map (author,
                                           -- 2026-09-26): the hottest and highest ranked

-------------------------------------------------
-- Pin data
-------------------------------------------------

-- Is ancestor above mapID in the map tree?
local function IsAncestor(ancestor, mapID)
    local id = mapID
    for _ = 1, 10 do
        local info = C_Map and ns.Utils.SafeCall(C_Map.GetMapInfo, id)
        local parent = info and tonumber(info.parentMapID)
        if not parent or parent == 0 then return false end
        if parent == ancestor then return true end
        id = parent
    end
    return false
end

-- x, y on zone -> x, y on mapID (the zone itself or a map above it), plus the zone's
-- width as a share of mapID's width; nil when the zone is not on mapID
function MapMarkers.Project(zone, x, y, mapID)
    if not (zone and x and y and mapID) then return nil end
    if zone == mapID then return x, y, 1 end
    if not IsAncestor(mapID, zone) then return nil end
    local minX, maxX, minY, maxY = ns.Zones.RectOn(zone, mapID)
    if not minX then return nil end
    return minX + x * (maxX - minX), minY + y * (maxY - minY), maxX - minX
end

local function OutlawName(entry)
    return entry.key and ns.Utils.DisplayName(entry.key) or entry.name
end

local function HotspotPin(spot, mapID, now)
    local x, y, zoneWidth = MapMarkers.Project(spot.zone, spot.x, spot.y, mapID)
    if not x then return nil end
    local zoneName = ns.Utils.MapName(spot.zone) or L.UNKNOWN_ZONE
    return {
        kind = "hotspot",
        id = "hot:" .. spot.zone,
        x = x, y = y,
        size = MapMarkers.AREA_WIDTH * zoneWidth, -- diameter as a share of the map's width
        alpha = MapMarkers.AREA_ALPHA[spot.level] or MapMarkers.AREA_ALPHA[1],
        level = spot.level,
        lines = {
            string.format(L.MAP_HOTSPOT_TITLE, L["HOTSPOT_LEVEL_" .. spot.level], zoneName),
            ns.Hotspots.Describe(spot.a, spot.e, spot.d),
            ns.Utils.Ago(math.max(0, now - spot.t)),
        },
    }
end

local function WantedPin(entry, mapID, now)
    local kill = entry.lastKill
    -- The newest place: the last kill, or a later sighting (HH-121 step 3, Alerts/Spotted.lua)
    local seen = ns.Spotted:Latest(entry.id)
    local place = kill
    if seen and seen.x and (not kill or seen.t > kill.t) then place = seen end
    -- Only where the outlaw is now: an old place says little about where they are
    if not place or now - place.t > MapMarkers.WANTED_MAP_TIME then return nil end
    local zone, zx, zy = ns.Zones.ToZone(place.mapID, place.x, place.y)
    local x, y = MapMarkers.Project(zone, zx, zy, mapID)
    if not x then return nil end
    local zoneName = ns.Utils.MapName(zone) or L.UNKNOWN_ZONE
    local lines = {
        ns.Utils.RaceIcon(entry.race, entry.sex) .. " " .. string.format(L.MAP_WANTED_TITLE, OutlawName(entry)),
        string.format(L.MAP_WANTED_STATUS, ns.Wanted.RankName(entry.rank), math.floor(entry.kills)),
    }
    local badges = ns.Wanted.BadgeNames(entry)
    if badges ~= "" then lines[#lines + 1] = badges end
    lines[#lines + 1] = string.format(place == seen and L.MAP_WANTED_SEEN or L.MAP_WANTED_LAST_KILL,
        ns.Utils.Ago(math.max(0, now - place.t)), zoneName)
    local posse = ns.Posse:Summary(entry.id)
    if posse then lines[#lines + 1] = posse end
    return {
        kind = "wanted",
        id = "wanted:" .. entry.id,
        x = x, y = y,
        hunted = ns.Posse:IsMember(entry.id),
        lines = lines,
    }
end

-------------------------------------------------
-- Guiding the player
-------------------------------------------------

-- The game's waypoint at x, y on mapID where the client allows it. Returns "waypoint",
-- or "coords" plus the position on the zone (Classic Era refuses user waypoints; the
-- skull and PvP area already show the place, chat gives the coordinates), or nil
-- when the position is unknown.
function MapMarkers.Guide(mapID, x, y)
    if not (mapID and x and y) then return nil end
    if ns.Utils.SetWaypoint(mapID, x, y) then return "waypoint" end
    local _, zx, zy = ns.Zones.ToZone(mapID, x, y)
    if not zx then return nil end
    return "coords", zx, zy
end

-- Guide, then say in chat what happened. waypointText: the line for a game waypoint;
-- label ("PvP Battle in Westfall") starts the other lines.
function MapMarkers.GuideAndTell(mapID, x, y, label, waypointText)
    local how, zx, zy = MapMarkers.Guide(mapID, x, y)
    if how == "waypoint" then
        ns:Print(waypointText)
    elseif how == "coords" then
        ns:Print(string.format(L.GUIDE_COORDS, label, zx * 100, zy * 100))
    else
        ns:Print(string.format(L.GUIDE_UNKNOWN, label))
    end
    return how
end

-- Pins to draw on mapID: hotspots first, then WANTED outlaws (drawn on top)
function MapMarkers:PinsFor(mapID, now)
    mapID = tonumber(mapID)
    if not mapID then return {} end
    now = now or ns.Utils.ServerTime()
    local pins = {}
    local shown = 0
    -- Active() is hottest first
    for _, spot in ipairs(ns.Hotspots:Active(now)) do
        if shown >= MapMarkers.MAX_PER_KIND then break end
        local pin = HotspotPin(spot, mapID, now)
        if pin then
            pins[#pins + 1] = pin
            shown = shown + 1
        end
    end
    -- List() is highest rank first; an outlaw our posse hunts goes first
    local outlaws, others = {}, {}
    for _, entry in ipairs(ns.Wanted:List()) do
        local list = ns.Posse:IsMember(entry.id) and outlaws or others
        list[#list + 1] = entry
    end
    for _, entry in ipairs(others) do outlaws[#outlaws + 1] = entry end
    shown = 0
    for _, entry in ipairs(outlaws) do
        if shown >= MapMarkers.MAX_PER_KIND then break end
        local pin = WantedPin(entry, mapID, now)
        if pin then
            pins[#pins + 1] = pin
            shown = shown + 1
        end
    end
    return pins
end

function MapMarkers:Enabled()
    return ns.db ~= nil and ns.db.settings.mapPins ~= false
end

-------------------------------------------------
-- Drawing
-------------------------------------------------

local attached = false
local shownMap           -- from the SetMapID hook; never read from WorldMapFrame
local canvas, overlay
local pools, active = { hotspot = {}, wanted = {} }, {}
local lastScale
local sinceRefresh = 0

local function ReadCanvas()
    local found
    securecall(function()
        local container = WorldMapFrame and WorldMapFrame.ScrollContainer
        found = container and container.Child
    end)
    return found
end

local STRATA_RANK = {}
for rank, strata in ipairs(MapMarkers.STRATA) do STRATA_RANK[strata] = rank end

-- Other addons draw on the same canvas (map notes, quest helpers, fog clearing) and may
-- put their pins high. The highest strata and frame level among them (the canvas's own
-- when none is higher), read again at every redraw, as addons add pins later.
local function TopOfCanvas()
    local strata, level = canvas:GetFrameStrata(), canvas:GetFrameLevel() or 0
    pcall(function()
        for _, child in ipairs({ canvas:GetChildren() }) do
            local childStrata = child ~= overlay and child:GetFrameStrata()
            local rank = childStrata and STRATA_RANK[childStrata]
            if rank and rank > (STRATA_RANK[strata] or 0) then
                strata, level = childStrata, child:GetFrameLevel() or 0
            elseif rank and childStrata == strata then
                level = math.max(level, child:GetFrameLevel() or 0)
            end
        end
    end)
    return strata, level
end

-- Just above everything else on the canvas, with room left for our own pins
local function RaiseOverlay()
    local strata, top = TopOfCanvas()
    if STRATA_RANK[strata] then overlay:SetFrameStrata(strata) end
    local reserve = MapMarkers.MAX_PER_KIND * 2 + 2
    local level = math.max((canvas:GetFrameLevel() or 0) + MapMarkers.FRAME_LEVEL, top + 1)
    overlay:SetFrameLevel(math.min(level, MapMarkers.MAX_FRAME_LEVEL - reserve))
end

-- The overlay covers the canvas, so pins pan and zoom with the map
local function EnsureOverlay()
    local current = ReadCanvas()
    if not current then return false end
    if not overlay then
        overlay = CreateFrame("Frame", nil, current)
        overlay:SetScript("OnUpdate", function(_, elapsed) MapMarkers:OnUpdate(elapsed) end)
    elseif current ~= canvas then
        overlay:SetParent(current)
    end
    canvas = current
    overlay:ClearAllPoints()
    overlay:SetAllPoints(canvas)
    RaiseOverlay()
    overlay:Show()
    return true
end

local function ShowTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    for i, line in ipairs(button.data.lines) do
        if i == 1 then GameTooltip:SetText(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

-- Hover = details. No click action (the pin already shows the place), so clicks go
-- through to the map where the client allows it.
local function MakeInteractive(button)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
end

-- Skull: an icon with a fixed size on screen
local function NewSkull()
    local pin = CreateFrame("Button", nil, overlay)
    pin.kind = "wanted"
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints(pin)
    pin.icon:SetTexture(MapMarkers.SKULL_ICON)
    MakeInteractive(pin)
    return pin
end

-- PvP area: stacked translucent red discs (darker towards the middle) that cover a
-- patch of the map and zoom with it, plus crossed swords over a small "PVP" of fixed
-- size on screen. Only that mark takes the mouse, so the area never blocks clicks on
-- the map.
local DISCS = { { size = 1, alpha = 0.45 }, { size = 0.66, alpha = 0.7 }, { size = 0.33, alpha = 1 } }

local function NewArea()
    local pin = CreateFrame("Frame", nil, overlay)
    pin.kind = "hotspot"
    pin.discs = {}
    for i, disc in ipairs(DISCS) do
        local texture = pin:CreateTexture(nil, "ARTWORK", nil, i)
        texture:SetTexture(MapMarkers.CIRCLE)
        texture:SetPoint("CENTER", pin, "CENTER")
        pin.discs[i] = texture
    end
    local label = CreateFrame("Button", nil, pin)
    label:SetPoint("CENTER", pin, "CENTER")
    label:SetSize(32, MapMarkers.SWORDS_SIZE + 12)
    label.icon = label:CreateTexture(nil, "OVERLAY")
    label.icon:SetTexture(MapMarkers.SWORDS_ICON)
    label.icon:SetSize(MapMarkers.SWORDS_SIZE, MapMarkers.SWORDS_SIZE)
    label.icon:SetPoint("TOP", label, "TOP")
    label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label.text:SetPoint("TOP", label.icon, "BOTTOM", 0, 1)
    label.text:SetText(L.MAP_PVP)
    label.text:SetTextColor(unpack(MapMarkers.LABEL_COLOR))
    label.text:SetShadowColor(0, 0, 0, 1)
    label.text:SetShadowOffset(1, -1)
    MakeInteractive(label)
    pin.label = label
    return pin
end

local function CanvasScale()
    local scale = canvas:GetScale() or 1
    if scale <= 0 then scale = 1 end
    return scale
end

-- Called again whenever the zoom changes
local function Place(pin)
    local data = pin.data
    local scale = CanvasScale()
    local width, height = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    pin:ClearAllPoints()
    if pin.kind == "hotspot" then
        -- Part of the map: zooms with it, but never shrinks below AREA_MIN_PX on screen
        local diameter = math.max(data.size * width, MapMarkers.AREA_MIN_PX / scale)
        pin:SetScale(1)
        pin:SetSize(diameter, diameter)
        for i, disc in ipairs(pin.discs) do
            disc:SetSize(diameter * DISCS[i].size, diameter * DISCS[i].size)
        end
        pin:SetPoint("CENTER", overlay, "TOPLEFT", data.x * width, -data.y * height)
        pin.label:SetScale(1 / scale)
    else
        -- Same size on screen whatever the zoom: undo the canvas scale
        local s = 1 / scale
        pin:SetScale(s)
        pin:SetPoint("CENTER", overlay, "TOPLEFT", data.x * width / s, -data.y * height / s)
    end
end

local function Style(pin)
    local data = pin.data
    if pin.kind == "hotspot" then
        local r, g, b = unpack(MapMarkers.AREA_COLOR)
        for i, disc in ipairs(pin.discs) do
            disc:SetVertexColor(r, g, b, data.alpha * DISCS[i].alpha)
        end
        pin.label.data = data
    else
        local size = data.hunted and MapMarkers.HUNTED_SIZE or MapMarkers.WANTED_SIZE
        pin:SetSize(size, size)
    end
end

local function Acquire(kind)
    local list = pools[kind]
    return table.remove(list) or (kind == "hotspot" and NewArea() or NewSkull())
end

local function HideAll()
    for _, pin in ipairs(active) do
        pin:Hide()
        pin.data = nil
        if pin.kind == "hotspot" then pin.label.data = nil end
        local list = pools[pin.kind]
        list[#list + 1] = pin
    end
    active = {}
end

function MapMarkers:Refresh()
    HideAll()
    sinceRefresh = 0
    if not (attached and WorldMapFrame:IsShown() and self:Enabled()) then return end
    if not EnsureOverlay() then return end
    lastScale = canvas:GetScale()
    for i, data in ipairs(self:PinsFor(shownMap)) do
        local pin = Acquire(data.kind)
        pin.data = data
        pin:SetFrameLevel(overlay:GetFrameLevel() + i)
        Style(pin)
        Place(pin)
        pin:Show()
        active[#active + 1] = pin
    end
end

-- Runs only while the map is shown (the overlay lives on its canvas)
function MapMarkers:OnUpdate(elapsed)
    sinceRefresh = sinceRefresh + elapsed
    if sinceRefresh >= self.REFRESH then
        self:Refresh()
        return
    end
    local scale = canvas and canvas:GetScale()
    if scale and scale ~= lastScale then
        lastScale = scale
        for _, pin in ipairs(active) do Place(pin) end
    end
end

-- Coalesce bursts of data events into one redraw
local pending = false
function MapMarkers:RequestRefresh()
    if pending or not (attached and WorldMapFrame:IsShown()) then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        MapMarkers:Refresh()
    end)
end

-- Number of pins on the map now (tests, /hh map)
function MapMarkers:ShownCount()
    return #active
end

function MapMarkers:Attach()
    if attached or not (WorldMapFrame and hooksecurefunc) then return false end
    attached = true
    hooksecurefunc(WorldMapFrame, "SetMapID", function(_, mapID)
        shownMap = tonumber(mapID)
        MapMarkers:Refresh()
    end)
    WorldMapFrame:HookScript("OnShow", function()
        -- Before the first SetMapID the map opens on the player's zone
        shownMap = shownMap or ns.Utils.PlayerMapID()
        MapMarkers:Refresh()
    end)
    WorldMapFrame:HookScript("OnHide", HideAll)
    return true
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

ns.Events:Register("HH_INITIALIZED", function()
    if not MapMarkers:Attach() then
        -- The map may be load-on-demand: attach when it loads
        ns.Events:Register("ADDON_LOADED", function(_, name)
            if name == "Blizzard_WorldMap" and MapMarkers:Attach() then
                ns.Events:Unregister("ADDON_LOADED", OWNER)
            end
        end, OWNER)
    end
    local request = function() MapMarkers:RequestRefresh() end
    for _, event in ipairs({ "HH_WANTED_UPDATED", "HH_HOTSPOT_CHANGED", "HH_POSSE_CHANGED", "HH_OUTLAW_SPOTTED" }) do
        ns.Events:Register(event, request, OWNER)
    end
    ns.Events:Register("HH_SETTING_CHANGED", function(_, path)
        if path == "mapPins" then request() end
    end, OWNER)
end, OWNER)

-- /hh map [on|off]
ns.SlashCommands:Register("map", function(args)
    local mode = args[1] and args[1]:lower()
    if mode == "on" or mode == "off" then
        ns.Database:SetSetting("mapPins", mode == "on")
    end
    local pins = MapMarkers:PinsFor(ns.Zones.ZoneOf(ns.Utils.PlayerMapID()))
    ns:Print(string.format(L.MAP_STATUS, MapMarkers:Enabled() and L.ON or L.OFF, #pins))
end, L.HELP_MAP)
