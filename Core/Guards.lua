-- Instance and duel guards (docs/addon/features.md section 8).
--
-- Inside any instance (battlegrounds, arenas, dungeons, raids, scenarios) HeadHunter
-- is OFF: no alerts, no detection, no marks penalties, no sending and no receiving.
-- The world events stop at the frame (Events:SetSuspended); modules also check
-- Guards:IsActive() or listen for HH_SUSPEND_CHANGED.

local addonName, ns = ...

local Guards = ns:RegisterModule("Guards", {})

Guards.InstanceSuspended = false
Guards.InstanceType = "none"
Guards.InDuel = false
Guards.DuelOpponent = nil
Guards.lastDuelEnd = nil

function Guards:UpdateInstance()
    local inInstance, instanceType = ns.Utils.SafeCall(IsInInstance)
    local suspended = inInstance == true
    instanceType = suspended and (instanceType or "unknown") or "none"

    local changed = suspended ~= self.InstanceSuspended
    self.InstanceSuspended = suspended
    self.InstanceType = instanceType
    ns.Events:SetSuspended(suspended)
    if changed then
        ns:Debug("Instance guard:", suspended and ("suspended (" .. instanceType .. ")") or "active")
        ns.Events:Fire("HH_SUSPEND_CHANGED", suspended, instanceType)
    end
end

-- True when HeadHunter may detect, alert and send
function Guards:IsActive()
    return ns.IsSupported and not self.InstanceSuspended
end

-- Duels end at 1 HP, so they never cause a death. The window matters for attacker
-- tracking (HH-011): damage from a duel opponent must not be attributed to a later kill.
function Guards:RecentlyDueled(window)
    if self.InDuel then return true end
    return self.lastDuelEnd ~= nil and (ns.Utils.Now() - self.lastDuelEnd) < (window or 10)
end

function Guards:Initialize()
    local Events = ns.Events
    local function update() self:UpdateInstance() end
    Events:Register("PLAYER_ENTERING_WORLD", update, "Guards")
    Events:Register("ZONE_CHANGED_NEW_AREA", update, "Guards")

    -- DUEL_REQUESTED only fires for the challenged player; the challenger learns of the
    -- duel when it finishes. Good enough for the attacker-window check.
    Events:Register("DUEL_REQUESTED", function(_, opponent)
        self.InDuel = true
        self.DuelOpponent = ns.Utils.PlayerKey(opponent)
    end, "Guards")
    Events:Register("DUEL_FINISHED", function()
        self.InDuel = false
        self.lastDuelEnd = ns.Utils.Now()
    end, "Guards")

    self:UpdateInstance()
end
