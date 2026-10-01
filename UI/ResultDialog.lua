-- The result of a tournament match, set by the host or a co-organizer (author,
-- 2026-10-01): for matches the duels cannot count (teams, Gurubashi, both factions),
-- and to change what the duels counted. The choices are the website's: every score the
-- match's series can end with, or a side that did not come.
--
--   Match result
--   Grimtusk vs Marla (Best of 3)
--   Result   [Grimtusk wins 2 - 1   v]
--                               [Save] [Cancel]

local addonName, ns = ...
local L = ns.L

local ResultDialog = ns:RegisterModule("ResultDialog", {})

ResultDialog.WIDTH = 380
ResultDialog.HEIGHT = 190

local frame
local options = {}       -- the dropdown's choices, refilled for each match
ResultDialog.values = nil -- { t, round, match, choice }

-- { value = "2-1" | "ff-a" | "ff-b", label }
function ResultDialog.Options(aName, bName, bestOf)
    local list = {}
    for _, s in ipairs(ns.Matches.Scores(bestOf)) do
        local winner = s[1] > s[2] and aName or bName
        local score = math.max(s[1], s[2]) .. " - " .. math.min(s[1], s[2])
        list[#list + 1] = { value = s[1] .. "-" .. s[2], label = string.format(L.RESULT_WINS, winner, score) }
    end
    list[#list + 1] = { value = "ff-a", label = string.format(L.EVENT_NO_SHOW, aName) }
    list[#list + 1] = { value = "ff-b", label = string.format(L.EVENT_NO_SHOW, bName) }
    return list
end

local function CreateDialog()
    local Theme = ns.Theme
    local f = CreateFrame("Frame", "HeadHunterResultDialog", UIParent)
    f:SetSize(ResultDialog.WIDTH, ResultDialog.HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "HeadHunterResultDialog")
    Theme.StyleFrame(f, L.RESULT_DLG_TITLE)

    f.match = Theme.Text(f, "bold", 15, "foreground")
    f.match:SetPoint("TOPLEFT", 18, -60)
    f.match:SetWidth(ResultDialog.WIDTH - 36)
    f.match:SetJustifyH("LEFT")

    local label = Theme.Text(f, "bold", 13, "gold")
    label:SetPoint("TOPLEFT", 18, -94)
    label:SetText(L.RESULT_DLG_RESULT)
    f.choice = ns.Select.Create(f, {
        width = 230, options = options,
        get = function() return ResultDialog.values and ResultDialog.values.choice end,
        set = function(value) ResultDialog.values.choice = value end,
    })
    f.choice:SetPoint("TOPLEFT", 96, -88)

    f.error = Theme.Text(f, "text", 13, "wanted")
    f.error:SetPoint("BOTTOMLEFT", 18, 50)
    f.error:SetWidth(ResultDialog.WIDTH - 36)
    f.error:SetJustifyH("LEFT")

    f.save = Theme.Button(f, L.RESULT_DLG_SAVE, "gold", 110, 26)
    f.save:SetPoint("BOTTOMRIGHT", -134, 16)
    f.save:SetScript("OnClick", function() ResultDialog:Save() end)
    f.close = Theme.Button(f, CANCEL or "Cancel", "outline", 110, 26)
    f.close:SetPoint("BOTTOMRIGHT", -18, 16)
    f.close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

-- choice: the score to start with ("2-1"), e.g. what the duels counted
function ResultDialog:Open(t, round, match, choice)
    local m, bestOf
    local r = ns.Tournaments.Bracket(t)[round]
    m, bestOf = r and r.matches[match], r and r.bestOf
    if not (m and m.a and m.b) then return false end
    local aName = ns.Tournaments.SideName(t, m.a) or m.a
    local bName = ns.Tournaments.SideName(t, m.b) or m.b
    frame = frame or CreateDialog()
    for i = #options, 1, -1 do options[i] = nil end
    for i, opt in ipairs(self.Options(aName, bName, bestOf)) do options[i] = opt end
    self.values = { t = t, round = round, match = match, choice = choice or options[1].value }
    frame.match:SetText(string.format(L.RESULT_DLG_MATCH, aName, bName, bestOf))
    frame.choice:Refresh()
    frame.error:SetText("")
    frame:Show()
    return true
end

function ResultDialog:IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Save: a click (the result goes out to the players)
function ResultDialog:Save()
    local v = self.values
    if not v then return false end
    local winsA, winsB = tostring(v.choice):match("^(%d+)%-(%d+)$")
    local forfeit = tostring(v.choice):match("^ff%-(%a)$")
    local ok, reason = ns.Matches:Confirm(v.t, v.round, v.match, tonumber(winsA), tonumber(winsB), forfeit)
    if not ok then
        if frame then frame.error:SetText(L["RESULT_ERR_" .. tostring(reason):upper()] or tostring(reason)) end
        return false
    end
    if frame then frame:Hide() end
    return true
end
