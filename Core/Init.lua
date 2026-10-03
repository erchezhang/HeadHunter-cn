local addonName, ns = ...

ns.addonName = addonName

-- Read version from TOC file (C_AddOns on Forever, the global on Era)
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.version = (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) or "0.0.0"

ns.Modules = {}

-- Modules are also reachable as ns.<Name> (ns.Utils, ns.Events, ...)
function ns:RegisterModule(name, module)
    assert(self[name] == nil, "module name collides with a namespace field: " .. name)
    self.Modules[name] = module
    self[name] = module
    return module
end

function ns:GetModule(name)
    return self.Modules[name]
end

-- tostring every argument, nils included, and join with spaces
local function Join(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end
ns.Join = Join

local PREFIX = "|cffc41e3a[HeadHunter]|r "

function ns:Print(...)
    print(PREFIX .. Join(...))
end

-- Debug lines always land in the in-memory log (Core/Log.lua). They reach chat only
-- while debug mode is on: sync and detection must stay silent for normal players.
function ns:Debug(...)
    local msg = Join(...)
    local log = self.Modules.Log
    if log then log:Add("debug", msg) end
    if self.debugMode then
        print("|cff888888[HH]|r " .. msg)
    end
end

-- Errors go to the client's error handler so BugGrabber/BugSack collect them
-- instead of spamming chat. Only the first copy of an error is shown: a handler that
-- fails on every UNIT_HEALTH would otherwise flood the screen. Repeats go to the log.
local errorCounts = {}

function ns:Error(err)
    local text = tostring(err)
    local count = (errorCounts[text] or 0) + 1
    errorCounts[text] = count
    local log = self.Modules.Log
    if log then log:Add("error", count > 1 and (text .. " (x" .. count .. ")") or text) end
    if count > 1 then return end
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(err)
    else
        print(PREFIX .. tostring(err))
    end
end

ns.debugMode = false
