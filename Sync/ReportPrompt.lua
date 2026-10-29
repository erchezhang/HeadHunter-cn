-- Classic Era: "Report to all HeadHunters" (author decision 2026-09-23: click to report).
--
-- Era refuses addon messages on custom channels, so a death cannot go realm-wide
-- on its own. Plain chat text on the HeadHunter channel is delivered when it comes
-- from a hardware event, so after each real PvP death a popup offers
--   Report <killer> (<classification>) to all HeadHunters?   [Report] [Skip]
-- and the click sends every waiting report. /hh report does the same (a typed
-- command is a hardware event too). Guild and group still get reports
-- automatically (Sync/Transport.lua); this is the realm-wide path only.
--
-- HH-152: the player clicks one of the game's own popups after almost every death
-- (Release Spirit, Reincarnation or the soulstone, accepting a resurrection, recovering
-- the corpse, the spirit healer). That click is a hardware event too, so the waiting
-- reports go with it and nobody clicks Report. The hooks sit on the game functions
-- those clicks call, not on the popups: Classic Era's death popup has its own button
-- handlers (seen in game 2026-10-30: Reincarnation did not send). While dead or a ghost
-- the Report popup waits; it shows only when the player is alive again with reports
-- still waiting.
-- Forever never shows the popup: its channel carries addon messages.

local addonName, ns = ...
local L = ns.L

local ReportPrompt = ns:RegisterModule("ReportPrompt", {})

local OWNER = "ReportPrompt"
local DIALOG = "HEADHUNTER_REPORT"

local pending = {} -- report ids waiting for the click, oldest first
local hooked = false

ReportPrompt.GAME_FUNCTIONS = { "RepopMe", "UseSoulstone", "AcceptResurrect", "RetrieveCorpse", "AcceptXPLoss" }

function ReportPrompt:PendingCount()
    return #pending
end

-- Must run inside a hardware event (the popup button or a typed command)
function ReportPrompt:SendPending()
    local Protocol, Transport = ns.Protocol, ns.Transport
    local records = {}
    for _, id in ipairs(pending) do
        local report = ns.Reports:Get(id)
        local record = report and Protocol.EncodeDeath(report, Protocol.MAX_MESSAGE - 4 - #Transport.CHAT_MARK)
        if record then records[#records + 1] = record end
    end
    wipe(pending)
    if #records == 0 then
        ns:Print(L.REPORT_NOTHING)
        return 0
    end
    local sent = Transport:SendRealmWide(Protocol.TYPES.DEATH, records)
    ns:Print(sent > 0 and string.format(L.REPORT_SENT, #records) or L.REPORT_FAILED)
    return sent
end

function ReportPrompt:Skip()
    wipe(pending)
end

function ReportPrompt:Show()
    local report = ns.Reports:Get(pending[#pending])
    if not report then return end
    local DR = ns.DeathReports
    local text = string.format(L.REPORT_PROMPT, DR.DisplayName(report.killer),
        ns.Classify.ReportLabel(report))
    if #pending > 1 then
        text = text .. "\n" .. string.format(L.REPORT_MORE, #pending - 1)
    end
    StaticPopupDialogs[DIALOG].text = text
    StaticPopup_Show(DIALOG)
end

-- Runs inside the click that called one of the game's functions (HH-152)
function ReportPrompt:OnGameClick(how)
    if #pending == 0 then return end
    ns:Debug("Report sent with the game's click:", how)
    StaticPopup_Hide(DIALOG)
    self:SendPending()
end

-- Once, on the first report waiting: the game's functions exist by then
function ReportPrompt:HookGameFunctions()
    if hooked then return end
    hooked = true
    for _, name in ipairs(self.GAME_FUNCTIONS) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function() ReportPrompt:OnGameClick(name) end)
        end
    end
    if C_DeathInfo and type(C_DeathInfo.UseSelfResurrectOption) == "function" then
        hooksecurefunc(C_DeathInfo, "UseSelfResurrectOption", function()
            ReportPrompt:OnGameClick("UseSelfResurrectOption")
        end)
    end
end

function ReportPrompt:OnReportAdded(report)
    if report.origin ~= "local" or not ns.Transport:RealmWideNeedsClick() then return end
    if not ns.Guards:IsActive() then return end
    pending[#pending + 1] = report.id
    self:HookGameFunctions()
    if UnitIsDeadOrGhost("player") then
        ns:Debug("Report waits for the game's click:", report.id)
    else
        self:Show()
    end
end

-- Alive again with reports still waiting: no game popup took them, so ask
function ReportPrompt:OnAlive()
    if #pending > 0 and not UnitIsDeadOrGhost("player") then
        ns:Debug("Report popup: alive with", #pending, "waiting")
        self:Show()
    end
end

ns.Events:Register("HH_INITIALIZED", function()
    StaticPopupDialogs[DIALOG] = {
        text = "",
        button1 = L.REPORT_BUTTON,
        button2 = L.REPORT_SKIP,
        OnAccept = function() ReportPrompt:SendPending() end,
        OnCancel = function() ReportPrompt:Skip() end,
        timeout = 0,
        whileDead = 1,      -- the player is usually dead or a ghost when this shows
        hideOnEscape = 1,
        preferredIndex = 3, -- avoid the slots Blizzard's own popups use
    }
    ns.Events:Register("HH_REPORT_ADDED", function(_, report) ReportPrompt:OnReportAdded(report) end, OWNER)
    ns.Events:Register("PLAYER_ALIVE", function() ReportPrompt:OnAlive() end, OWNER)
    ns.Events:Register("PLAYER_UNGHOST", function() ReportPrompt:OnAlive() end, OWNER)
end, OWNER)

ns.SlashCommands:Register("report", function()
    if #pending == 0 then
        ns:Print(L.REPORT_NOTHING)
        return
    end
    StaticPopup_Hide(DIALOG)
    ReportPrompt:SendPending()
end, L.HELP_REPORT)
