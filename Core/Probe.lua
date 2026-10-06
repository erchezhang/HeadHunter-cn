-- HH-007 spike: find out, in game, what each client offers for killer detection.
--
--   /hh probe        one-shot report of API/event availability (+ current target)
--   /hh probe watch  toggle live logging of combat and death signals
--   /hh probe screenshot  take one screenshot and log whether it worked (HH-132)
--
-- Everything goes to the debug log (/hh log), which is copyable, so results can be
-- pasted into docs/addon/README.md.

local addonName, ns = ...
local L = ns.L

local Probe = ns:RegisterModule("Probe", {})

local OWNER = "Probe"

local function Write(...)
    ns.Log:Add("probe", ns.Join(...))
end

-- tostring can raise on a secret value; show a marker instead
local function Show(value)
    if value ~= nil and ns.Utils.Accessible(value) == nil then
        return "<secret>"
    end
    local ok, text = pcall(tostring, value)
    return ok and text or "<unprintable>"
end

local function ShowAll(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = Show((select(i, ...)))
    end
    return table.concat(parts, ", ")
end

-------------------------------------------------
-- Availability
-------------------------------------------------

local scratch = CreateFrame("Frame")

local function EventAvailable(event)
    if ns.Events.IsRestricted(event) then
        return "restricted (never registered on this client)"
    end
    if C_EventUtils and C_EventUtils.IsEventValid then
        local ok, valid = pcall(C_EventUtils.IsEventValid, event)
        if ok then return valid and "yes" or "no" end
    end
    local ok = pcall(scratch.RegisterEvent, scratch, event)
    if ok then
        scratch:UnregisterEvent(event)
        return "yes (registered)"
    end
    return "no (register failed)"
end

local function Exists(value)
    return value ~= nil and "yes" or "no"
end

local function FunctionNames(tbl)
    if type(tbl) ~= "table" then return "-" end
    local names = {}
    for key, value in pairs(tbl) do
        if type(value) == "function" then names[#names + 1] = key end
    end
    table.sort(names)
    return table.concat(names, " ")
end

local EVENTS = {
    "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_DEAD", "PARTY_KILL", "PLAYER_PVP_KILLS_CHANGED",
    "UNIT_COMBAT", "CHAT_MSG_COMBAT_HONOR_GAIN", "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_TARGET_CHANGED", "UNIT_TARGET", "DUEL_REQUESTED", "DUEL_FINISHED",
}

local function ReportTarget()
    local U = ns.Utils
    if not UnitExists("target") then
        Write("target: none (target an enemy player and run /hh probe again)")
        return
    end
    Write("target raw UnitName:", ShowAll(U.SafeCall(UnitName, "target")))
    Write("target raw GetUnitName(true):", ShowAll(U.SafeCall(GetUnitName, "target", true)),
        "UnitFullName:", ShowAll(U.SafeCall(UnitFullName, "target")))
    Write("player raw UnitName:", ShowAll(U.SafeCall(UnitName, "player")),
        "GetUnitName(true):", ShowAll(U.SafeCall(GetUnitName, "player", true)))
    Write("target key:", Show(U.UnitKey("target")), "enemy player:", Show(U.UnitIsEnemyPlayer("target")))
    Write("target level:", Show(U.UnitLevel("target")), "class:", Show(U.UnitClass("target")),
        "race:", Show(U.UnitRace("target")), "sex:", Show(U.UnitSex("target")),
        "guild:", Show(U.UnitGuild("target")), "faction:", Show(U.UnitFaction("target")))
    local guid = U.UnitGUID("target")
    Write("target GUID:", Show(guid))
    if guid and GetPlayerInfoByGUID then
        Write("GetPlayerInfoByGUID:", ShowAll(U.SafeCall(GetPlayerInfoByGUID, guid)))
    end
end

-- HH-121 spike: can map positions become yards, and can we read a group member's position?
local function ReportWorldPosition(mapID)
    local U = ns.Utils
    local x, y = U.PlayerPosition(mapID)
    local toWorld = C_Map and C_Map.GetWorldPosFromMapPos
    Write("C_Map.GetWorldPosFromMapPos:", Exists(toWorld), "CreateVector2D:", Exists(CreateVector2D))
    if toWorld and CreateVector2D and mapID and x then
        local ok, continent, pos = pcall(toWorld, mapID, CreateVector2D(x, y))
        if ok and pos and pos.GetXY then
            Write("world pos (yards): continent", Show(continent), "x, y:", ShowAll(pos:GetXY()))
        else
            Write("world pos: failed", Show(continent))
        end
    end
    if UnitExists("party1") and C_Map and C_Map.GetPlayerMapPosition and mapID then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "party1")
        Write("party1", Show(U.UnitKey("party1")), "map pos:", ok and pos and pos.GetXY and ShowAll(pos:GetXY()) or "none")
    else
        Write("party1: none (group with someone in the same zone and run /hh probe again)")
    end
end

function Probe:Run()
    local E = ns.Expansion
    Write("==== HeadHunter probe", ns.version, "====")
    Write("build:", ShowAll(GetBuildInfo()))
    Write("client:", E.ClientKey, "interface:", E.InterfaceVersion, "WOW_PROJECT_ID:", Show(WOW_PROJECT_ID))
    Write("SavedVariables restored from disk this load:", Show(ns.Database.restoredFromDisk),
        "loadCount:", Show(ns.db and ns.db.meta.loadCount))

    for _, event in ipairs(EVENTS) do
        Write("event", event .. ":", EventAvailable(event))
    end

    Write("CombatLogGetCurrentEventInfo:", Exists(CombatLogGetCurrentEventInfo))
    Write("GetPlayerInfoByGUID:", Exists(GetPlayerInfoByGUID))
    Write("C_DeathRecap:", Exists(C_DeathRecap), "functions:", FunctionNames(C_DeathRecap))
    Write("C_Map.SetUserWaypoint:", Exists(C_Map and C_Map.SetUserWaypoint),
        "CanSetUserWaypointOnMap:", Exists(C_Map and C_Map.CanSetUserWaypointOnMap))
    Write("TooltipDataProcessor:", Exists(TooltipDataProcessor), "Settings API:", Exists(Settings and Settings.RegisterCanvasLayoutCategory))
    Write("C_ChatInfo.SendAddonMessage:", Exists(C_ChatInfo and C_ChatInfo.SendAddonMessage),
        "C_BattleNet.SendGameData:", Exists(C_BattleNet and C_BattleNet.SendGameData))
    Write("canaccessvalue:", Exists(canaccessvalue), "issecretvalue:", Exists(issecretvalue))
    Write("GetServerTime:", Exists(GetServerTime), "realm:", Show(ns.Utils.PlayerRealm()),
        "server:", Show(ns.Utils.PlayerServer()), "player key:", Show(ns.Utils.UnitKey("player")))

    local mapID = ns.Utils.PlayerMapID()
    Write("map:", Show(mapID), Show(ns.Utils.MapName(mapID)), "continent:", Show(ns.Utils.ContinentOf(mapID)),
        "pos:", ShowAll(ns.Utils.PlayerPosition(mapID)))
    ReportWorldPosition(mapID)

    ReportTarget()
    Write("==== end probe ====")
end

-------------------------------------------------
-- Watch mode
-------------------------------------------------

local function DumpDeathRecap()
    if not C_DeathRecap then
        Write("death recap: C_DeathRecap missing")
        return
    end
    for _, fnName in ipairs({ "HasRecapEvents", "GetRecapEvents", "GetRecapMaxHealth", "GetRecapLink" }) do
        local fn = C_DeathRecap[fnName]
        if fn then
            local ok, result = pcall(fn)
            Write("death recap", fnName .. "():", ok and Show(result) or ("error " .. Show(result)))
            if ok and type(result) == "table" then
                local first = result[1]
                if type(first) == "table" then
                    local fields = {}
                    for key, value in pairs(first) do
                        fields[#fields + 1] = key .. "=" .. Show(value)
                    end
                    Write("death recap first event:", table.concat(fields, " "))
                end
                Write("death recap events:", #result)
            end
        end
    end
end

local function OnCombatLog()
    if not CombatLogGetCurrentEventInfo then return end
    local info = { CombatLogGetCurrentEventInfo() }
    local subevent, sourceFlags, destGUID = info[2], info[6], info[8]
    if destGUID ~= UnitGUID("player") or type(sourceFlags) ~= "number" then return end
    local isPlayer = bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x400) > 0
    local isHostile = bit.band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40) > 0
    if not (isPlayer and isHostile) then return end
    Write("CLEU", subevent, "from", Show(info[5]), Show(info[4]), "args:", ShowAll(unpack(info, 12, 18)))
end

local WATCHED = {
    PLAYER_DEAD = function()
        Write("PLAYER_DEAD at", date("%H:%M:%S"), "target:", Show(ns.Utils.UnitKey("target")))
        C_Timer.After(1, DumpDeathRecap)
    end,
    PARTY_KILL = function(_, ...) Write("PARTY_KILL", ShowAll(...)) end,
    PLAYER_PVP_KILLS_CHANGED = function(_, ...) Write("PLAYER_PVP_KILLS_CHANGED", ShowAll(...)) end,
    CHAT_MSG_COMBAT_HONOR_GAIN = function(_, ...) Write("HONOR_GAIN", ShowAll(...)) end,
    UNIT_COMBAT = function(_, unit, ...)
        if unit == "player" then Write("UNIT_COMBAT player", ShowAll(...)) end
    end,
    NAME_PLATE_UNIT_ADDED = function(_, unit)
        if ns.Utils.UnitIsEnemyPlayer(unit) then
            Write("nameplate enemy", Show(ns.Utils.UnitKey(unit)), "level", Show(ns.Utils.UnitLevel(unit)),
                Show(ns.Utils.UnitClass(unit)), Show(ns.Utils.UnitRace(unit)))
        end
    end,
    COMBAT_LOG_EVENT_UNFILTERED = OnCombatLog,
    -- Duels (High Noon on Forever judges our own duels from these)
    DUEL_REQUESTED = function(_, ...) Write("DUEL_REQUESTED", ShowAll(...)) end,
    DUEL_FINISHED = function(_, ...)
        local U = ns.Utils
        Write("DUEL_FINISHED", ShowAll(...), "player hp:", Show(U.SafeCall(UnitHealth, "player")),
            "target:", Show(U.UnitKey("target")), "level", Show(U.UnitLevel("target")),
            "hp:", Show(U.SafeCall(UnitHealth, "target")))
    end,
    DUEL_INBOUNDS = function() Write("DUEL_INBOUNDS") end,
    DUEL_OUTOFBOUNDS = function() Write("DUEL_OUTOFBOUNDS") end,
    PLAYER_REGEN_DISABLED = function() Write("combat start, target:", Show(ns.Utils.UnitKey("target"))) end,
    PLAYER_REGEN_ENABLED = function() Write("combat end") end,
    START_TIMER = function(_, ...) Write("START_TIMER", ShowAll(...)) end,
    CHAT_MSG_SYSTEM = function(_, message) Write("system:", Show(message)) end,
    UNIT_HEALTH = function(_, unit)
        if unit ~= "player" and unit ~= "target" then return end
        local hp = ns.Utils.SafeCall(UnitHealth, unit)
        -- Only the telling cases: hidden from addons, or down to the duel's 1 HP
        if type(hp) ~= "number" or ns.Utils.Accessible(hp) == nil or hp <= 1 then
            Write("UNIT_HEALTH", unit, Show(hp))
        end
    end,
}

-------------------------------------------------
-- Witness mode (HH-121 spike): what do we see when another player dies near us?
--   Era      the combat log: UNIT_DIED, PARTY_KILL and the killing blow (overkill)
--   Forever  no combat log: a player's nameplate or our target turning dead
-------------------------------------------------

local SWING_OVERKILL, SPELL_OVERKILL = 13, 16
local SPELL_DAMAGE_EVENTS = { SPELL_DAMAGE = true, RANGE_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true }

local function IsOtherPlayer(guid, flags)
    return guid ~= UnitGUID("player") and type(flags) == "number"
        and bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x400) > 0
end

local function Hostile(flags)
    return type(flags) == "number" and bit.band(flags, COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40) > 0
end

local function OnWitnessCombatLog()
    if not CombatLogGetCurrentEventInfo then return end
    local info = { CombatLogGetCurrentEventInfo() }
    local subevent, sourceName, destGUID, destName, destFlags = info[2], info[5], info[8], info[9], info[10]
    if subevent == "UNIT_DIED" or subevent == "PARTY_KILL" then
        Write("witness", subevent, "dest", Show(destName), IsOtherPlayer(destGUID, destFlags) and "player" or "npc",
            Hostile(destFlags) and "hostile" or "not hostile", "source", Show(sourceName), "at", date("%H:%M:%S"))
        return
    end
    if not IsOtherPlayer(destGUID, destFlags) then return end
    local overkill = subevent == "SWING_DAMAGE" and info[SWING_OVERKILL]
        or SPELL_DAMAGE_EVENTS[subevent] and info[SPELL_OVERKILL]
    if type(overkill) == "number" and overkill >= 0 then
        Write("witness killing blow", subevent, "on", Show(destName), "by", Show(sourceName), "overkill", Show(overkill))
    end
end

local deadSeen = {}

-- reason: "target" when we just targeted the unit: then say what we see, even when
-- nothing is dead, so a quiet log never leaves the question open
local function CheckDead(unit, reason)
    local U = ns.Utils
    if not (unit == "target" or unit:find("^nameplate")) then return end
    local isPlayer = U.SafeCall(UnitIsPlayer, unit)
    local guid = U.UnitGUID(unit)
    local dead = U.SafeCall(UnitIsDead, unit)
    if reason == "target" and guid then
        Write("witness target", Show(U.UnitKey(unit)), "player:", Show(U.Accessible(isPlayer)),
            "dead:", Show(U.Accessible(dead)), "dead secret:", Show(dead ~= nil and U.Accessible(dead) == nil),
            "enemy:", Show(U.UnitIsEnemyPlayer(unit)), "at", date("%H:%M:%S"))
    end
    if U.Accessible(isPlayer) ~= true or not guid then return end
    if U.Accessible(dead) == true then
        if not deadSeen[guid] then
            deadSeen[guid] = true
            Write("witness dead unit", unit, Show(U.UnitKey(unit)), "enemy:", Show(U.UnitIsEnemyPlayer(unit)),
                "at", date("%H:%M:%S"))
        end
    elseif dead ~= nil and U.Accessible(dead) == nil then
        Write("witness", unit, "UnitIsDead is secret")
    else
        deadSeen[guid] = nil
    end
end

local WITNESS = {
    COMBAT_LOG_EVENT_UNFILTERED = OnWitnessCombatLog,
    UNIT_HEALTH = function(_, unit) CheckDead(unit) end,
    NAME_PLATE_UNIT_ADDED = function(_, unit) CheckDead(unit) end,
    PLAYER_TARGET_CHANGED = function() CheckDead("target", "target") end,
}

function Probe:SetWitness(on)
    self.witnessing = on
    local owner = OWNER .. "Witness"
    for event, handler in pairs(WITNESS) do
        if ns.Events.IsRestricted(event) then
            if on then Write("witness", event .. ": restricted, skipped") end
        elseif on then
            local ok = ns.Events:Register(event, handler, owner)
            Write("witness", event .. ":", ok and "registered" or "NOT available")
        else
            ns.Events:Unregister(event, owner)
        end
    end
end

function Probe:SetWatch(on)
    self.watching = on
    for event, handler in pairs(WATCHED) do
        if ns.Events.IsRestricted(event) then
            if on then Write("watch", event .. ": restricted, skipped") end
        elseif on then
            local ok = ns.Events:Register(event, handler, OWNER)
            Write("watch", event .. ":", ok and "registered" or "NOT available")
        else
            ns.Events:Unregister(event, OWNER)
        end
    end
end

-------------------------------------------------
-- Screenshot (HH-132 spike)
-------------------------------------------------

local SHOT_OWNER = OWNER .. "Screenshot"
local SHOT_EVENTS = { "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED" }

local SHOT_QUALITY = "screenshotQuality"
local SHOT_QUALITY_MIN, SHOT_QUALITY_MAX = 1, 10

local function GetSetting(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return get and get(name)
end

local function SetSetting(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    return set ~= nil and pcall(set, name, value)
end

local function CVar(name)
    return Show(GetSetting(name))
end

-- Can an addon take a screenshot on this client, in which format, and when? The local
-- time is what the game puts in the file name, so the sync app can match it to a death.
-- With a quality (1-10) the picture is taken at that jpeg quality and the player's own
-- setting comes back once the game has written the file
function Probe:Screenshot(quality)
    Write("==== screenshot probe ====")
    Write("Screenshot:", Exists(Screenshot), "screenshotFormat:", CVar("screenshotFormat"),
        "screenshotQuality:", CVar(SHOT_QUALITY))
    local own
    if quality then
        own = GetSetting(SHOT_QUALITY)
        Write("quality for this one:", quality, "set:", SetSetting(SHOT_QUALITY, tostring(quality)) and "ok" or "failed")
    end
    local function Restore()
        if own == nil then return end
        SetSetting(SHOT_QUALITY, own)
        Write("quality back to:", CVar(SHOT_QUALITY))
        own = nil
    end
    for _, event in ipairs(SHOT_EVENTS) do
        local ok = ns.Events:Register(event, function(name)
            Write(name, "at", date("%Y-%m-%d %H:%M:%S"))
            for _, other in ipairs(SHOT_EVENTS) do ns.Events:Unregister(other, SHOT_OWNER) end
            Restore()
        end, SHOT_OWNER)
        Write("event", event .. ":", ok and "registered" or "NOT available")
    end
    if not Screenshot then
        Restore()
        return
    end
    local ok, err = pcall(Screenshot)
    Write("Screenshot() called:", ok and "ok" or Show(err), "local time:", date("%Y-%m-%d %H:%M:%S"),
        "server time:", Show(ns.Utils.ServerTime()))
    if not ok then Restore() end
end

ns.SlashCommands:Register("probe", function(args)
    if args[1] and args[1]:lower() == "screenshot" then
        local quality = tonumber(args[2])
        if quality then
            quality = math.max(SHOT_QUALITY_MIN, math.min(SHOT_QUALITY_MAX, math.floor(quality)))
        end
        Probe:Screenshot(quality)
        ns:Print(L.PROBE_DONE)
        return
    end
    if args[1] and args[1]:lower() == "watch" then
        Probe:SetWatch(not Probe.watching)
        ns:Print(Probe.watching and L.PROBE_WATCH_ON or L.PROBE_WATCH_OFF)
        return
    end
    if args[1] and args[1]:lower() == "witness" then
        Probe:SetWitness(not Probe.witnessing)
        ns:Print(Probe.witnessing and L.PROBE_WITNESS_ON or L.PROBE_WITNESS_OFF)
        return
    end
    Probe:Run()
    ns:Print(L.PROBE_DONE)
    ns.Log:Show()
end, L.HELP_PROBE)
