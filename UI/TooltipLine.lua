-- HH-062: a HeadHunter line on enemy player tooltips.
--
--   WANTED enemy:           "WANTED · Ganker · 8 kills · Coward, Gunslinger"
--   known, not WANTED now:  "HeadHunter: 12 kills known · caught 1x · Coward" (grey)
--   unknown enemy:          nothing
--   any player with duels:  "High Noon: Deadeye #3 (1250)" (HH-093)
--   a player's bounty:      "Bounty: 20g by Tallon · Camped me" (HH-118)
--   a tournament organizer: "★ Tournament host: Gate Brawl · in progress" (HH-128, any player)
--
-- Hook: TooltipDataProcessor (unit post-call) where the client has it, else the
-- tooltip's OnTooltipSetUnit script. Either may run more than once for one tooltip,
-- so the line is added once until the tooltip is cleared. /hh tooltip turns it off.
--
-- TooltipLine.Lines(entry) is the pure part (tested offline).

local addonName, ns = ...
local L = ns.L

local TooltipLine = ns:RegisterModule("TooltipLine", {})

local OWNER = "TooltipLine"

-- Lines to add for one enemy entry: array of { text, r, g, b }
function TooltipLine.Lines(entry)
    if not entry then return {} end
    local Wanted = ns.Wanted
    local badges = Wanted.BadgeNames(entry)
    local suffix = badges ~= "" and (" · " .. badges) or ""
    if entry.wanted then
        local line = string.format(L.TOOLTIP_WANTED, Wanted.RankName(entry.rank), math.floor(entry.kills)) .. suffix
        local lines = { { line, 1, 1, 1 } }
        local posse = ns.Posse:Summary(entry.id)
        if posse then lines[2] = { posse, 0.6, 0.8, 1 } end
        return lines
    end
    if entry.atLarge then
        local line = string.format(L.TOOLTIP_AT_LARGE, Wanted.RankName(entry.lastRank), entry.killCount or 0)
        return { { line .. suffix, 1, 0.75, 0.5 } }
    end
    if (entry.killCount or 0) == 0 then return {} end
    local line = string.format(L.TOOLTIP_KNOWN, entry.killCount)
    return { { line .. suffix, 0.7, 0.7, 0.7 } }
end

-- The enemy on a unit token, or nil
function TooltipLine.EntryForUnit(unit)
    local U = ns.Utils
    if not unit or not U.UnitIsEnemyPlayer(unit) then return nil end
    local key = U.UnitKey(unit)
    local entry = key and ns.Wanted:ByKey(key)
    if entry then return entry end
    local guid = U.UnitGUID(unit)
    return guid and ns.Wanted:Get("guid:" .. guid)
end

-- HH-093: "High Noon: Deadeye #3 (1250)" on any player (friend or foe) with duels
function TooltipLine.DuelLine(unit)
    local U = ns.Utils
    if not unit or not U.UnitIsPlayer(unit) then return nil end
    local title = ns.HighNoon.Title(ns.HighNoon:Get(U.UnitKey(unit)))
    return title and { string.format(L.DUEL_TOOLTIP, title), 1, 1, 1 } or nil
end

function TooltipLine:Enabled()
    return ns.db ~= nil and ns.db.settings.tooltip ~= false and ns.Guards:IsActive()
end

-- tooltip: the GameTooltip-like frame being filled
function TooltipLine:Fill(tooltip)
    if not self:Enabled() or not tooltip or tooltip.hhLineAdded then return end
    local U = ns.Utils
    local _, unit = U.SafeCall(tooltip.GetUnit, tooltip)
    unit = U.AccessibleString(unit)
    local entry = self.EntryForUnit(unit)
    local lines = self.Lines(entry)
    local bounty = entry and ns.Bounties:Line(entry.id)
    if bounty then lines[#lines + 1] = { bounty, 1, 0.82, 0 } end
    local duel = self.DuelLine(unit)
    if duel then lines[#lines + 1] = duel end
    -- HH-128: the sheriff's star on a tournament's host or co-organizer (any player)
    local organizer = ns.Organizers:TooltipLine(unit)
    if organizer then table.insert(lines, 1, organizer) end
    if #lines == 0 then return end
    tooltip.hhLineAdded = true
    for _, line in ipairs(lines) do
        tooltip:AddLine(line[1], line[2], line[3], line[4])
    end
end

local function HookCleared(tooltip)
    if tooltip and tooltip.HookScript then
        pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self) self.hhLineAdded = nil end)
    end
end

-- Returns "processor", "script" or nil (nothing to hook)
function TooltipLine:Install()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
            and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            local ok, err = pcall(TooltipLine.Fill, TooltipLine, tooltip)
            if not ok then ns:Error(err) end
        end)
        HookCleared(GameTooltip)
        return "processor"
    end
    if GameTooltip and GameTooltip.HookScript then
        local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
            local fine, err = pcall(TooltipLine.Fill, TooltipLine, tooltip)
            if not fine then ns:Error(err) end
        end)
        if ok then
            HookCleared(GameTooltip)
            return "script"
        end
    end
    return nil
end

ns.Events:Register("HH_INITIALIZED", function()
    TooltipLine.hook = TooltipLine:Install()
    ns:Debug("Tooltip line hook:", tostring(TooltipLine.hook))
end, OWNER)

ns.SlashCommands:Register("tooltip", function(args)
    local mode = args[1] and args[1]:lower()
    if mode == "on" or mode == "off" then
        ns.Database:SetSetting("tooltip", mode == "on")
    else
        ns.Database:SetSetting("tooltip", not TooltipLine:Enabled())
    end
    ns:Print(TooltipLine:Enabled() and L.TOOLTIP_ON or L.TOOLTIP_OFF)
end, L.HELP_TOOLTIP)
