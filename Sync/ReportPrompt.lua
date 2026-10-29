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
-- (Release Spirit or the soulstone, accepting a resurrection, recovering the corpse,
-- the spirit healer). That click is a hardware event too, so the waiting reports go
-- with it and nobody clicks Report. While dead or a ghost the Report popup waits; it
-- shows only when the player is alive again with reports still waiting.
-- Forever never shows the popup: its channel carries addon messages.

local addonName, ns = ...
local L = ns.L

local ReportPrompt = ns:RegisterModule("ReportPrompt", {})

local OWNER = "ReportPrompt"
local DIALOG = "HEADHUNTER_REPORT"

local pending = {} -- report ids waiting for the click, oldest first
local hooked = {}

ReportPrompt.GAME_DIALOGS = { "DEATH", "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER",
    "RECOVER_CORPSE", "XP_LOSS", "XP_LOSS_NO_SICKNESS" }

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

-- Runs inside the click on one of the game's popups (HH-152)
function ReportPrompt:OnGameClick()
    if #pending == 0 then return end
    StaticPopup_Hide(DIALOG)
    self:SendPending()
end

-- Each of the game's popups once. A cancel counts only when clicked: the death
-- popup's timeout releases without a click.
function ReportPrompt:HookGameDialogs()
    for _, which in ipairs(self.GAME_DIALOGS) do
        local dialog = StaticPopupDialogs[which]
        if type(dialog) == "table" and not hooked[dialog] then
            hooked[dialog] = true
            if type(dialog.OnAccept) == "function" then
                hooksecurefunc(dialog, "OnAccept", function() ReportPrompt:OnGameClick() end)
            end
            if type(dialog.OnCancel) == "function" then
                hooksecurefunc(dialog, "OnCancel", function(_, _, reason)
                    if reason == "clicked" then ReportPrompt:OnGameClick() end
                end)
            end
        end
    end
end

function ReportPrompt:OnReportAdded(report)
    if report.origin ~= "local" or not ns.Transport:RealmWideNeedsClick() then return end
    if not ns.Guards:IsActive() then return end
    pending[#pending + 1] = report.id
    self:HookGameDialogs()
    if not UnitIsDeadOrGhost("player") then self:Show() end
end

-- Alive again with reports still waiting: no game popup took them, so ask
function ReportPrompt:OnAlive()
    if #pending > 0 and not UnitIsDeadOrGhost("player") then self:Show() end
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
