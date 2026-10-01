-- Bootstrap. Loaded last: every module file has run by now.

local addonName, ns = ...
local L = ns.L

local Events = ns.Events

Events:OnAddonLoaded(function()
    if not ns.IsSupported then
        ns:Print(string.format(L.UNSUPPORTED_CLIENT, tostring(ns.Expansion.InterfaceVersion)))
        return
    end
    ns.Database:Initialize()
    ns.Guards:Initialize()
    Events:Fire("HH_INITIALIZED")
end, "Main")

Events:Register("PLAYER_LOGIN", function()
    Events:Unregister("PLAYER_LOGIN", "Main")
    if not ns.IsSupported then return end
    ns.Database:ConfirmHome()
    ns.Database:RememberPlayer()
    ns:Print(string.format(L.LOADED, ns.version))
    if ns.Database:ResetsOnReload() then
        ns:Print(L.FOREVER_SAVED_VARS)
    end
    -- HeadHunter_Dev noSharing (Core/Dev.lua): say that nothing is sent
    if ns.Dev.NoSharing() then
        ns:Print(L.DEV_NO_SHARING)
    end
end, "Main")

Events:Register("PLAYER_LOGOUT", function()
    if ns.db then ns.Database:OnLogout() end
end, "Main")
