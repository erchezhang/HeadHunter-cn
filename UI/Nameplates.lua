-- Marks above players' heads, on their nameplates (author, 2026-09-30). Only HeadHunter
-- users see them. Side by side when a player has more than one:
--   wanted     the HeadHunter crosshair on a WANTED player, either faction
--   shame      a white feather on a Hall of Shame bully or Deadbeat (Alerts/Sighting.lua)
--   organizer  the sheriff's star on a tournament host (gold) or co-organizer (silver),
--              HH-128, Tournament/Organizers.lua
-- Nameplates for your own faction are off by default in the game, so marks on them
-- need friendly nameplates on. Shown when a nameplate appears, hidden when it goes, and
-- every REFRESH seconds the shown ones are checked again (WANTED and the organizers'
-- time window change while they are on screen). Nameplates the game keeps from addons
-- (IsForbidden) are skipped; everything runs in pcall.

local addonName, ns = ...

local Nameplates = ns:RegisterModule("Nameplates", {})

local OWNER = "Nameplates"

Nameplates.SIZE = 22
Nameplates.GAP = 2
Nameplates.REFRESH = 60

local function WantedEntry(unit)
    local U = ns.Utils
    local key = U.UnitKey(unit)
    local entry = key and ns.Wanted:ByKey(key)
    if entry then return entry end
    local guid = U.UnitGUID(unit)
    entry = guid and ns.Wanted:Get("guid:" .. guid)
    if entry or not key then return entry end
    -- The same player in another shape (Forever: "Given Family", "GivenFamily", a realm)
    for _, other in pairs(ns.Wanted:All()) do
        if U.SameCharacter(other.key, key) then return other end
    end
    return nil
end
Nameplates.WantedEntry = WantedEntry

-- In order, left to right. For(unit) -> true, r, g, b (0..1) to show, else nil
Nameplates.BADGES = {
    {
        id = "wanted",
        texture = "Interface\\AddOns\\HeadHunter\\Assets\\Textures\\mark",
        For = function(unit)
            if not ns.db or ns.db.settings.wantedMarks == false then return nil end
            local entry = WantedEntry(unit)
            if entry and entry.wanted then return true, 1, 1, 1 end
            return nil
        end,
    },
    {
        id = "shame",
        texture = "Interface\\AddOns\\HeadHunter\\Assets\\Textures\\feather",
        For = function(unit)
            if not ns.db or ns.db.settings.shameMarks == false then return nil end
            local entry = WantedEntry(unit)
            local key = ns.Utils.UnitKey(unit)
            if (entry and entry.badges and entry.badges.coward) or (key and ns.Bounties:IsBlocked(key)) then
                return true, 1, 1, 1
            end
            return nil
        end,
    },
    {
        id = "organizer",
        texture = "Interface\\AddOns\\HeadHunter\\Assets\\Textures\\star",
        For = function(unit)
            local role = ns.Organizers:Enabled() and ns.Organizers:RoleOf(ns.Utils.UnitKey(unit))
            local color = role and ns.Organizers.COLORS[role]
            if color then return true, color[1] / 255, color[2] / 255, color[3] / 255 end
            return nil
        end,
    },
}

local function PlateFor(unit)
    local api = _G.C_NamePlate
    if not (api and api.GetNamePlateForUnit and unit) then return nil end
    local plate = ns.Utils.SafeCall(api.GetNamePlateForUnit, unit)
    if type(plate) ~= "table" or (plate.IsForbidden and plate:IsForbidden()) then return nil end
    return plate
end

-- The texture of one badge on one nameplate, made the first time
local function Texture(plate, badge)
    plate.hhBadges = rawget(plate, "hhBadges") or {}
    local texture = plate.hhBadges[badge.id]
    if not texture then
        texture = plate:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(badge.texture)
        texture:SetSize(Nameplates.SIZE, Nameplates.SIZE)
        plate.hhBadges[badge.id] = texture
    end
    return texture
end

-- Shows the marks this unit has, centred in a row above its nameplate
function Nameplates:Update(unit)
    local plate = PlateFor(unit)
    if not plate then return end
    -- No marks inside an instance (Core/Guards.lua): battleground plates are not ours
    if not ns.Guards:IsActive() then return self:Hide(unit) end
    local isPlayer = ns.Utils.UnitIsPlayer(unit)
    local shown = {}
    for _, badge in ipairs(self.BADGES) do
        local show, r, g, b = false
        if isPlayer then show, r, g, b = badge.For(unit) end
        local existing = rawget(plate, "hhBadges") and plate.hhBadges[badge.id]
        if show then
            local texture = Texture(plate, badge)
            texture:SetVertexColor(r, g, b, 1)
            shown[#shown + 1] = texture
        elseif existing then
            existing:Hide()
        end
    end
    local width = #shown * self.SIZE + math.max(0, #shown - 1) * self.GAP
    for i, texture in ipairs(shown) do
        local x = -width / 2 + (i - 1) * (self.SIZE + self.GAP) + self.SIZE / 2
        texture:ClearAllPoints()
        texture:SetPoint("BOTTOM", plate, "TOP", x, 2)
        texture:Show()
    end
end

function Nameplates:Hide(unit)
    local plate = PlateFor(unit)
    for _, texture in pairs(plate and rawget(plate, "hhBadges") or {}) do texture:Hide() end
end

-- Every nameplate on screen again
function Nameplates:Refresh()
    local api = _G.C_NamePlate
    local plates = api and api.GetNamePlates and ns.Utils.SafeCall(api.GetNamePlates)
    for _, plate in ipairs(type(plates) == "table" and plates or {}) do
        local unit = rawget(plate, "namePlateUnitToken")
        if unit then self:Update(unit) end
    end
end

local function Safely(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns:Debug("Nameplate marks:", tostring(err)) end
end

-- Registered at load (they do nothing until the database is ready), so no new
-- HH_INITIALIZED handler changes the login order of the other modules
ns.Events:Register("NAME_PLATE_UNIT_ADDED", function(_, unit) Safely(Nameplates.Update, Nameplates, unit) end, OWNER)
ns.Events:Register("NAME_PLATE_UNIT_REMOVED", function(_, unit) Safely(Nameplates.Hide, Nameplates, unit) end, OWNER)
-- The lists changed (new data, a recompute): the marks at once, not at the next REFRESH
ns.Events:Register("HH_WANTED_UPDATED", function() Safely(Nameplates.Refresh, Nameplates) end, OWNER)
ns.Events:Register("HH_SUSPEND_CHANGED", function() Safely(Nameplates.Refresh, Nameplates) end, OWNER)

local function RefreshLoop()
    Safely(Nameplates.Refresh, Nameplates)
    C_Timer.After(Nameplates.REFRESH, RefreshLoop)
end
C_Timer.After(Nameplates.REFRESH, RefreshLoop)

-- /hh dev check: why a unit has or has not got its marks, step by step
function Nameplates:Check(unit)
    local U = ns.Utils
    local name, second = U.UnitName(unit)
    local key = U.UnitKey(unit)
    print(string.format("HeadHunter dev check: name %s / %s, full %s, key %s, player %s", tostring(name),
        tostring(second), tostring(U.AccessibleString(U.SafeCall(_G.GetUnitName, unit, true))), tostring(key),
        tostring(U.UnitIsPlayer(unit))))
    local entry = WantedEntry(unit)
    print(string.format("  list entry %s, WANTED %s, bully %s, Deadbeat %s, bullies from the website %d",
        tostring(entry and entry.key), tostring(entry and entry.wanted), tostring(entry and entry.badges and entry.badges.coward),
        tostring(key and ns.Bounties:IsBlocked(key)), (function()
            local n = 0
            for _ in pairs(ns.SiteData:Bullies()) do n = n + 1 end
            return n
        end)()))
    local api = _G.C_NamePlate
    local plate = api and api.GetNamePlateForUnit and U.SafeCall(api.GetNamePlateForUnit, unit)
    print(string.format("  nameplate %s, forbidden %s, options wanted %s shame %s", tostring(plate ~= nil),
        tostring(plate and plate.IsForbidden and plate:IsForbidden()), tostring(ns.db.settings.wantedMarks),
        tostring(ns.db.settings.shameMarks)))
    for _, badge in ipairs(self.BADGES) do
        local ok, show = pcall(badge.For, unit)
        print(string.format("  %s: %s", badge.id, ok and tostring(show) or ("error " .. tostring(show))))
    end
    local ok, err = pcall(self.Update, self, unit)
    if not ok then print("  update error " .. tostring(err)) end
end

-- /hh dev wanted | shame | glass | check | clear (not in the help, only with HeadHunter_Dev):
-- the target in the WANTED list or the Hall of Shame as a test, see Core/Dev.lua; glass:
-- the Raise a glass popup of a made-up bust (Alerts/Justice.lua TestGlass)
ns.SlashCommands:Register("dev", function(args)
    if not ns.Dev.Enabled() then return end
    local kind = args[1] and args[1]:lower()
    if kind == "clear" then
        ns.Dev.ClearTests()
        print("HeadHunter dev: test entries cleared")
    elseif kind == "check" then
        Nameplates:Check("target")
        return
    elseif kind == "glass" then
        -- The Raise a glass popup at once, for the target or a made-up outlaw; the glass
        -- is never saved or sent
        local outlaw = ns.Utils.UnitIsPlayer("target") and ns.Utils.UnitKey("target") or "Grim Reaver"
        if not ns.JusticeAlerts:TestGlass(outlaw) then
            print("HeadHunter dev: no glass popup (in combat it waits; turned off, or in an instance)")
        end
        return
    elseif kind == "wanted" or kind == "shame" then
        local on, key = ns.Dev.ToggleTest(kind, "target")
        if on == nil then
            print("HeadHunter dev: target a player first")
            return
        end
        print(string.format("HeadHunter dev: %s %s the %s list (test, this client only)", key,
            on and "added to" or "removed from", kind == "wanted" and "WANTED" or "Hall of Shame"))
    else
        print("HeadHunter dev: /hh dev wanted | shame | glass | check | clear")
        return
    end
    ns.Wanted:RequestRecompute()
end)
