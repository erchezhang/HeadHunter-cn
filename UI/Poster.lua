-- HH-061: the poster. Everything known about one enemy, opened from a row of the main
-- window. HH-125: a parchment WANTED poster like the website's, with the details
-- in a card next to it.
--
--   paper:  WANTED / DEAD OR ALIVE / Name / 60 Orc Rogue / WANTED · Ganker · 8 kills /
--           Bully, Gunslinger / Reward 20g (players' bounties) · Last kill 5 min ago
--   card:   Kills known: 12 (exact 10, guessed 2) · WANTED 2x · caught 1x · peak rank
--           Recent kills: when · victim · zone · kill type (newest first)
--           Posse: you, Hunterx
--           Bounty: 20g by Tallon · Camped me   (HH-118)
--           [Post a bounty] (our killer, last 24 h)   [Join the posse]
--
-- Poster.Content(id, now) is the pure part (tested offline).

local addonName, ns = ...
local L = ns.L

local Poster = ns:RegisterModule("Poster", {})

local OWNER = "Poster"

Poster.WIDTH = 720
Poster.HEIGHT = 480
Poster.PAPER_WIDTH = 300
Poster.PORTRAIT = 84
Poster.RECENT = 8

-------------------------------------------------
-- Content (pure)
-------------------------------------------------

-- The enemy's reports, newest first: { report, enemy } (the killer or an assist)
local function KillsOf(id, limit)
    local Engine = ns.RulesEngine
    local list = {}
    for _, report in ns.Reports:All() do
        local enemies = { report.killer }
        for _, assist in ipairs(report.assists or {}) do enemies[#enemies + 1] = assist end
        for _, enemy in ipairs(enemies) do
            if Engine.EnemyId(enemy) == id then
                list[#list + 1] = { report = report, enemy = enemy }
                break
            end
        end
    end
    table.sort(list, function(a, b) return a.report.t > b.report.t end)
    for i = #list, (limit or #list) + 1, -1 do list[i] = nil end
    return list
end
Poster.KillsOf = KillsOf

function Poster.Content(id, now)
    local entry = id and ns.Wanted:Get(id)
    if not entry then return nil end
    now = now or ns.Utils.ServerTime()
    local U, Wanted = ns.Utils, ns.Wanted
    local name = entry.key and U.DisplayName(entry.key) or entry.name or "?"
    local icons = U.RaceIcon(entry.race, entry.sex, 18) .. U.ClassIcon(entry.class, 18)
    local c = {
        id = entry.id,
        name = name,
        title = (icons ~= "" and (icons .. " ") or "") .. ns.MainWindow.ClassColored(name, entry.class),
        who = ns.DeathReports.Describe(entry),
        raceAtlas = U.RaceAtlas(entry.race, entry.sex), -- the portrait on the paper
        wanted = entry.wanted == true,
        badges = Wanted.BadgeNames(entry),
        history = string.format(L.POSTER_HISTORY, entry.killCount or 0, entry.exactKills or 0, entry.guessedKills or 0,
            entry.peakRank and Wanted.RankName(entry.peakRank) or "-"),
        posse = ns.Posse:Summary(entry.id),
        bounty = ns.Bounties:Line(entry.id, now), -- HH-118
        recent = {},
    }
    -- The paper's Reward: the players' bounties on them, in gold
    local summary = ns.Bounties:Summary(entry.id, now)
    c.reward = summary and ns.Bounties.Gold(summary.gold) or nil
    local canPost, whyNot = ns.Bounties:CanPost(entry.id, now)
    c.canPost = canPost
    c.postLocked = (whyNot == "level" or whyNot == "targetlevel") and whyNot or nil
    if entry.wanted then
        c.status = string.format(L.TIP_WANTED, Wanted.RankName(entry.rank), math.floor(entry.kills))
    elseif entry.atLarge then
        c.status = string.format(L.TIP_AT_LARGE, Wanted.RankName(entry.lastRank))
    else
        -- HH-118: a player's bounty lists them on the WANTED tab too. Otherwise no status:
        -- a WANTED poster that says "Not WANTED" reads wrong (Hall of Shame bullies)
        c.status = summary and string.format(L.TIP_BOUNTY_ONLY, ns.Bounties.Gold(summary.gold)) or nil
    end
    local kill = entry.lastKill
    if kill then
        c.lastKill = string.format(L.TIP_LAST_KILL, U.Ago(math.max(0, now - kill.t)), U.MapName(kill.mapID) or L.UNKNOWN_ZONE)
    end
    local kills = KillsOf(entry.id, Poster.RECENT)
    for _, item in ipairs(kills) do
        local report = item.report
        local attackers = ns.Classify.Attackers(report)
        local kind = ns.Classify.Enemy(item.enemy.level, report.victim and report.victim.level, attackers)
        c.recent[#c.recent + 1] = string.format(L.POSTER_KILL, U.Ago(math.max(0, now - report.t)),
            U.DisplayName(report.victim and report.victim.key) or "?", U.MapName(report.mapID) or L.UNKNOWN_ZONE,
            ns.Classify.Label(kind, attackers, ns.Classify.Helpers(report)))
    end
    -- Join needs a kill to go to (and WANTED status); not twice
    c.newestReport = kills[1] and kills[1].report
    c.canJoin = Wanted.Hunted(entry) and c.newestReport ~= nil and not ns.Posse:IsMember(entry.id)
    return c
end

-------------------------------------------------
-- Actions
-------------------------------------------------

local shownId

function Poster:Join()
    local c = Poster.Content(shownId)
    if not (c and c.canJoin) then return false end
    ns.Posse:Join(ns.Wanted:Get(c.id), c.newestReport)
    self:Refresh()
    return true
end

-------------------------------------------------
-- Drawing
-------------------------------------------------

local frame

-- A line of text under another one: role and size as in Theme.Font
local function Text(parent, role, size, color, anchor, relative, x, y, width)
    local fs = ns.Theme.Text(parent, role, size, color)
    fs:SetPoint("TOPLEFT", relative or parent, anchor or "TOPLEFT", x or 0, y or 0)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    return fs
end

-- A centred line on the paper
local function PaperText(paper, role, size, color, relative, y)
    local fs = ns.Theme.Text(paper, role, size, color)
    fs:SetPoint("TOP", relative or paper, relative and "BOTTOM" or "TOP", 0, y)
    fs:SetWidth(Poster.PAPER_WIDTH - 50)
    fs:SetJustifyH("CENTER")
    return fs
end

-- The paper is dark ink on parchment: the game's light colour codes would not read on it
local function Ink(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function PaperRule(paper, relative, y)
    local ink = ns.Theme.COLORS.parchmentText
    local rule = paper:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(ink[1], ink[2], ink[3], 0.3)
    rule:SetSize(Poster.PAPER_WIDTH - 60, 1)
    rule:SetPoint("TOP", relative, "BOTTOM", 0, y)
    return rule
end

-- The parchment WANTED poster, like the website's WantedPoster
local function CreatePaper(f)
    local Theme = ns.Theme
    local paper = CreateFrame("Frame", nil, f)
    paper:SetSize(Poster.PAPER_WIDTH, Poster.HEIGHT - Theme.HEADER_HEIGHT - 28)
    paper:SetPoint("TOPLEFT", 16, -(Theme.HEADER_HEIGHT + 12))
    local bg = paper:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(Theme.TEXTURES.poster)
    bg:SetAllPoints(paper)
    local pin = paper:CreateTexture(nil, "ARTWORK")
    pin:SetTexture(Theme.TEXTURES.pin)
    pin:SetSize(16, 16)
    pin:SetPoint("TOP", 0, -10)

    paper.wanted = PaperText(paper, "western", 44, "wanted", nil, -28)
    Theme.FitText(paper.wanted, L.POSTER_WANTED, "western", 44, Poster.PAPER_WIDTH - 50, 20)
    paper.alive = PaperText(paper, "heading", 11, "parchmentText", paper.wanted, -2)
    paper.alive:SetText(L.POSTER_DEAD_OR_ALIVE)
    paper.rule = PaperRule(paper, paper.alive, -10)

    -- The portrait: the race icon in black and white, in a thin ink frame
    local ink = Theme.COLORS.parchmentText
    local portrait = CreateFrame("Frame", nil, paper)
    portrait:SetSize(Poster.PORTRAIT + 6, Poster.PORTRAIT + 6)
    portrait:SetPoint("TOP", paper.rule, "BOTTOM", 0, -10)
    local frameBg = portrait:CreateTexture(nil, "BACKGROUND")
    frameBg:SetAllPoints(portrait)
    frameBg:SetColorTexture(ink[1], ink[2], ink[3], 0.55)
    portrait.icon = portrait:CreateTexture(nil, "ARTWORK")
    portrait.icon:SetPoint("TOPLEFT", 3, -3)
    portrait.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    portrait.icon:SetDesaturated(true)
    portrait.icon:SetVertexColor(0.92, 0.9, 0.86)
    paper.portrait = portrait

    paper.name = PaperText(paper, "western", 24, "parchmentText", portrait, -8)
    paper.who = PaperText(paper, "text", 14, "parchmentText", paper.name, -4)
    paper.status = PaperText(paper, "bold", 15, "parchmentText", paper.who, -12)
    paper.badges = PaperText(paper, "heading", 11, "parchmentText", paper.status, -8)

    -- Reward on the left, the last kill on the right, over a rule at the bottom
    local ink = Theme.COLORS.parchmentText
    local bottomRule = paper:CreateTexture(nil, "ARTWORK")
    bottomRule:SetColorTexture(ink[1], ink[2], ink[3], 0.3)
    bottomRule:SetSize(Poster.PAPER_WIDTH - 60, 1)
    bottomRule:SetPoint("BOTTOM", 0, 74)
    paper.rewardLabel = Text(paper, "heading", 10, "parchmentText", "BOTTOMLEFT", bottomRule, 0, -10)
    paper.rewardLabel:SetText(L.POSTER_REWARD)
    paper.reward = Text(paper, "western", 22, "wanted", "BOTTOMLEFT", paper.rewardLabel, 0, -2)
    paper.lastKill = ns.Theme.Text(paper, "text", 12, "parchmentText")
    paper.lastKill:SetPoint("TOPRIGHT", bottomRule, "BOTTOMRIGHT", 0, -10)
    paper.lastKill:SetWidth(140)
    paper.lastKill:SetJustifyH("RIGHT")
    return paper
end

local function CreatePosterFrame()
    local f = CreateFrame("Frame", "HeadHunterPosterFrame", UIParent)
    f:SetSize(Poster.WIDTH, Poster.HEIGHT)
    -- Above the main window (HIGH), which it is opened from and may overlap
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "HeadHunterPosterFrame")
    local Theme = ns.Theme
    Theme.StyleFrame(f, L.POSTER_HEADER)
    f.paper = CreatePaper(f)

    -- The details in a card next to the paper
    local card = Theme.Card(f)
    card:SetPoint("TOPLEFT", f.paper, "TOPRIGHT", 14, 0)
    card:SetPoint("BOTTOMRIGHT", -16, 16)
    f.card = card
    local width = Poster.WIDTH - Poster.PAPER_WIDTH - 16 - 14 - 16 - 32
    f.history = Text(card, "text", 13, "muted", "TOPLEFT", card, 16, -16, width)
    f.recentHeader = Text(card, "heading", 13, "gold", "BOTTOMLEFT", f.history, 0, -14, width)
    f.recentHeader:SetText(L.POSTER_RECENT)
    local divider = Theme.Divider(card, width)
    divider:SetPoint("TOPLEFT", f.recentHeader, "BOTTOMLEFT", 0, -4)
    f.recent = {}
    local previous = divider
    for i = 1, Poster.RECENT do
        f.recent[i] = Text(card, "text", 13, "foreground", "BOTTOMLEFT", previous, 0, i == 1 and -6 or -4, width)
        f.recent[i]:SetWordWrap(false)
        previous = f.recent[i]
    end
    f.posse = Text(card, "text", 13, "foreground", "BOTTOMLEFT", previous, 0, -12, width)
    f.bounty = Text(card, "bold", 14, "gold", "BOTTOMLEFT", f.posse, 0, -6, width)

    f.postButton = Theme.Button(card, L.BOUNTY_POST_BUTTON, "outline", 150, 26)
    f.postButton:SetPoint("BOTTOMLEFT", 16, 16)
    f.postButton:SetScript("OnClick", function() ns.BountyDialog:Open(shownId) end)
    if f.postButton.SetMotionScriptsWhileDisabled then f.postButton:SetMotionScriptsWhileDisabled(true) end
    f.postButton:HookScript("OnEnter", function(self)
        if self:IsEnabled() or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local c = Poster.Content(shownId)
        GameTooltip:SetText(L["BOUNTY_ERR_" .. string.upper(c and c.postLocked or "level")], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.postButton:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    f.joinButton = Theme.Button(card, L.POSSE_JOIN, "gold", 170, 26)
    f.joinButton:SetPoint("BOTTOMRIGHT", -16, 16)
    f.joinButton:SetScript("OnClick", function() Poster:Join() end)

    f:Hide()
    return f
end

function Poster:Refresh()
    if not (frame and frame:IsShown()) then return end
    local c = Poster.Content(shownId)
    if not c then
        frame:Hide()
        return
    end
    local paper, C = frame.paper, ns.Theme.COLORS
    -- No race known: no portrait, the name moves up under the rule
    paper.name:ClearAllPoints()
    if c.raceAtlas then
        paper.portrait.icon:SetAtlas(c.raceAtlas)
        paper.portrait:Show()
        paper.name:SetPoint("TOP", paper.portrait, "BOTTOM", 0, -8)
    else
        paper.portrait:Hide()
        paper.name:SetPoint("TOP", paper.rule, "BOTTOM", 0, -12)
    end
    ns.Theme.FitText(paper.name, c.name, "western", 24, Poster.PAPER_WIDTH - 50, 14)
    paper.who:SetText(Ink(c.who))
    paper.status:SetText(Ink(c.status))
    local statusColor = c.wanted and C.wanted or C.parchmentText
    paper.status:SetTextColor(statusColor[1], statusColor[2], statusColor[3])
    paper.badges:SetText(Ink(c.badges))
    -- No status (not WANTED, no bounty): the badges move up, no empty line
    paper.badges:ClearAllPoints()
    paper.badges:SetPoint("TOP", c.status and paper.status or paper.who, "BOTTOM", 0, -8)
    paper.reward:SetText(c.reward or "-")
    paper.lastKill:SetText(Ink(c.lastKill))
    frame.history:SetText(c.history)
    for i, line in ipairs(frame.recent) do line:SetText(c.recent[i] or "") end
    if #c.recent == 0 then frame.recent[1]:SetText(L.POSTER_NO_KILLS) end
    frame.posse:SetText(c.posse or "")
    frame.bounty:SetText(c.bounty or "")
    if c.canJoin then frame.joinButton:Show() else frame.joinButton:Hide() end
    frame.postButton:SetShown(c.canPost or c.postLocked)
    frame.postButton:SetEnabled(c.canPost == true)
    self.shown = c
end

function Poster:Show(id)
    if not (id and ns.Wanted:Get(id)) then return false end
    frame = frame or CreatePosterFrame()
    shownId = id
    -- Always in the middle of the main window (author, 2026-09-30), else of the screen
    local main = _G.HeadHunterMainFrame
    frame:ClearAllPoints()
    if main and main:IsShown() then
        frame:SetPoint("CENTER", main, "CENTER")
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
    frame:Show()
    frame:Raise()
    self:Refresh()
    return true
end

function Poster:Hide()
    if frame then frame:Hide() end
end

function Poster:IsShown()
    return frame ~= nil and frame:IsShown()
end

function Poster:ShownId()
    return self:IsShown() and shownId or nil
end

ns.Events:Register("HH_INITIALIZED", function()
    local refresh = function() Poster:Refresh() end
    for _, event in ipairs({ "HH_WANTED_UPDATED", "HH_POSSE_CHANGED", "HH_BOUNTY_UPDATED" }) do
        ns.Events:Register(event, refresh, OWNER)
    end
end, OWNER)
