-- /hh and /headhunter. Modules register their own subcommands:
--   ns.SlashCommands:Register("probe", handler, L.HELP_PROBE)
-- handler(args) receives the tokens after the command (see Utils.Tokenize).

local addonName, ns = ...
local L = ns.L

local SlashCommands = ns:RegisterModule("SlashCommands", {})

local handlers = {}
local order = {}

function SlashCommands:Register(name, handler, help)
    if not handlers[name] then
        order[#order + 1] = name
    end
    handlers[name] = { run = handler, help = help }
end

function SlashCommands:PrintHelp()
    print(L.HELP_HEADER)
    for _, name in ipairs(order) do
        local help = handlers[name].help
        if help then print(help) end
    end
end

-- The help line of one command, for a tooltip (UI/Toolbox.lua)
function SlashCommands:Help(name)
    local entry = handlers[name]
    return entry and entry.help
end

function SlashCommands:Run(input)
    local args = ns.Utils.Tokenize(input)
    local command = table.remove(args, 1)
    -- /hh alone opens the main window (UI/MainWindow.lua registers "show")
    command = command and command:lower() or (handlers.show and "show" or "help")
    local entry = handlers[command]
    if not entry then
        ns:Print(string.format(L.UNKNOWN_COMMAND, command))
        return
    end
    local ok, err = pcall(entry.run, args)
    if not ok then ns:Error(err) end
end

-------------------------------------------------
-- Built-in commands
-------------------------------------------------

local function OnOff(value)
    return value and "yes" or "no"
end

SlashCommands:Register("help", function()
    SlashCommands:PrintHelp()
end)

SlashCommands:Register("status", function()
    local E = ns.Expansion
    local F = ns.Features
    local db = ns.db
    ns:Print(string.format(L.STATUS_CLIENT, E.ClientKey, E.InterfaceVersion))
    ns:Print(string.format(L.STATUS_FEATURES, OnOff(F.HasCLEU), OnOff(F.SavedVarsReliable), OnOff(F.HasSecretValues)))
    if db then
        ns:Print(string.format(L.STATUS_DB, db.schemaVersion, OnOff(ns.Database.restoredFromDisk),
            db.meta.loadCount, #db.deaths, ns.Utils.CountKeys(db.enemies)))
    end
    if db and db.settings.testWantedKills then
        ns:Print(string.format(L.WANTED_TEST_THRESHOLD, db.settings.testWantedKills))
    end
    if ns.Guards.InstanceSuspended then
        ns:Print(string.format(L.STATUS_SUSPENDED, ns.Guards.InstanceType))
    else
        ns:Print(L.STATUS_ACTIVE)
    end
end, L.HELP_STATUS)

SlashCommands:Register("debug", function(args)
    local mode = args[1] and args[1]:lower()
    -- /hh debug levels <off|on>: testing override of the level window (HH-047)
    if mode == "levels" then
        local value = args[2] and args[2]:lower()
        if value == "off" or value == "on" then
            ns.Database:SetSetting("testNoLevelWindow", value == "off" or nil)
        end
        ns:Print(ns.Wanted.LevelWindowOff() and L.DEBUG_LEVELS_OFF or L.DEBUG_LEVELS_ON)
        return
    end
    -- /hh debug duels <n|off>: testing override of the Greenhorn threshold (MIN_DUELS)
    if mode == "duels" then
        local value = args[2] and args[2]:lower()
        local n = tonumber(value)
        if value == "off" then
            ns.Database:SetSetting("testDuelMin", nil)
        elseif n and n >= 1 and n <= ns.HighNoon.MIN_DUELS then
            ns.Database:SetSetting("testDuelMin", math.floor(n))
        else
            ns:Print(L.DEBUG_DUELS_USAGE)
            return
        end
        ns.HighNoon:Recompute()
        ns:Print(string.format(L.DEBUG_DUELS, ns.HighNoon.MinDuels()))
        return
    end
    -- /hh debug wanted <n|off>: testing override of the WANTED kill threshold
    if mode == "wanted" then
        local value = args[2] and args[2]:lower()
        local n = tonumber(value)
        if value == "off" then
            ns.Database:SetSetting("testWantedKills", nil)
            ns:Print(L.DEBUG_WANTED_OFF)
        elseif n and n >= 1 and n <= 10 then
            ns.Database:SetSetting("testWantedKills", math.floor(n))
            ns:Print(string.format(L.DEBUG_WANTED_ON, math.floor(n)))
        else
            ns:Print(L.DEBUG_WANTED_USAGE)
        end
        return
    end
    local on
    if mode == "on" then
        on = true
    elseif mode == "off" then
        on = false
    else
        on = not ns.debugMode
    end
    ns.debugMode = on
    if ns.db then ns.Database:SetSetting("debug", on) end
    ns:Print(on and L.DEBUG_ON or L.DEBUG_OFF)
end, L.HELP_DEBUG)

SlashCommands:Register("log", function(args)
    if args[1] and args[1]:lower() == "clear" then
        ns.Log:Clear()
        ns:Print(L.LOG_CLEARED)
        return
    end
    ns.Log:Toggle()
end, L.HELP_LOG)

SLASH_HEADHUNTER1 = "/hh"
SLASH_HEADHUNTER2 = "/headhunter"
SlashCmdList.HEADHUNTER = function(input)
    SlashCommands:Run(input)
end
