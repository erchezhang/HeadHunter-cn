-- Gangs (HH-155, website WEB-118, app APP-026): friends on one WoW Forever world and
-- faction under one name, at most 10, with one leader. The website owns them: the addon
-- records what the player did (create, invite, accept, leave, kick, rename, lead) in
-- db.gangActions, HeadHunter Sync uploads each once, and the download brings back each
-- world's gangs (HeadHunter_SiteData worlds[...].gangs) and what came of every action
-- (characters[...].gang_results: done, waiting or refused with a reason).
--
-- ns.db.gangActions (per home): list of { uid, by (our player key), kind, t, name (create,
--   rename; accept: the gang's name as invited), player (invite, kick, lead: a player
--   key), leader (accept: the inviter), told (true once its result was said) }, kept
--   GANG_KEEP seconds.
-- An invite is an addon whisper (type "A": "i;<gang name>"); the invited player's popup
-- answers "a" (accept) or "d" (decline). The leader's invite and the member's accept each
-- go to the website from their own account, which joins them. WoW Forever only.
-- Fires HH_GANG_CHANGED.

local addonName, ns = ...

local Gangs = ns:RegisterModule("Gangs", {})
local L = ns.L

local OWNER = "Gangs"

Gangs.NAME_MIN = 3
Gangs.NAME_MAX = 24
Gangs.MAX_MEMBERS = 10
-- seconds an invite stays open
Gangs.INVITE_TIMEOUT = 60
-- invites sent per INVITE_WINDOW
Gangs.INVITE_LIMIT = 5
Gangs.INVITE_WINDOW = 60
-- seconds for the invited player's addon to say it got the invite; silence means not
-- online or no HeadHunter
Gangs.ACK_WAIT = 10
-- seconds our actions are kept
Gangs.GANG_KEEP = 30 * 86400
Gangs.POPUP = "HEADHUNTER_GANG_INVITE"
Gangs.CREATE_POPUP = "HEADHUNTER_GANG_CREATE"
Gangs.LEAVE_POPUP = "HEADHUNTER_GANG_LEAVE"
Gangs.KINDS = { create = true, invite = true, accept = true, leave = true, kick = true, rename = true, lead = true }
Gangs.REASONS = {
    name_invalid = true, name_taken = true, in_a_gang = true, not_in_a_gang = true, not_leader = true,
    not_member = true, full = true, cooldown = true, rename_too_soon = true, hidden = true, other_world = true,
    unknown_gang = true, not_forever = true,
}

-- player key -> time we invited them
local sentInvites = {}
-- player key -> true once their addon said it got our invite
local heard = {}
-- times of our recent invites
local inviteLog = {}
-- { leader, name, at, sender }: the invite on show
local incoming
local counter = 0

local function Store()
    return ns.db and ns.db.gangActions
end

local function Me()
    return ns.Utils.UnitKey("player")
end

function Gangs.Enabled()
    return ns.Features.RealmlessNames == true
end

-- "  Black   Hand " -> "Black Hand"
function Gangs.CleanName(name)
    return (tostring(name or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- The website's rule: 3 to 24 letters or digits, inner spaces, ' and -; starts with a
-- letter or digit (any alphabet: bytes 128+ are taken as letters)
function Gangs.ValidName(name)
    name = Gangs.CleanName(name)
    local length = #name:gsub("[\128-\191]", "")
    if length < Gangs.NAME_MIN or length > Gangs.NAME_MAX then return false end
    if name:find("^[ '%-]") then return false end
    return not name:find("[^%w '%-\128-\255]")
end

-------------------------------------------------
-- Our actions
-------------------------------------------------

function Gangs:Record(kind, fields)
    local store = Store()
    local me = Me()
    if not store or not me or not Gangs.KINDS[kind] then return nil end
    counter = counter + 1
    local t = ns.Utils.ServerTime()
    local action = { uid = me .. ":" .. t .. ":" .. counter, by = me, kind = kind, t = t }
    for key, value in pairs(fields or {}) do action[key] = value end
    store[#store + 1] = action
    ns:Debug("Gang action", action.uid, kind)
    ns.Events:Fire("HH_GANG_CHANGED", action)
    return action
end

-- Our character's actions, oldest first
function Gangs:Actions()
    local me = Me()
    local list = {}
    for _, action in ipairs(Store() or {}) do
        if type(action) == "table" and action.by == me then list[#list + 1] = action end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

function Gangs:Prune(now)
    local store = Store()
    if not store then return end
    local minTime = (now or ns.Utils.ServerTime()) - Gangs.GANG_KEEP
    local kept = {}
    for _, action in ipairs(store) do
        if type(action) == "table" and (tonumber(action.t) or 0) >= minTime then kept[#kept + 1] = action end
    end
    ns.db.gangActions = kept
end

-------------------------------------------------
-- What the website said
-------------------------------------------------

-- uid -> { status, reason, gang } for our character
function Gangs:Results()
    return ns.SiteData:GangResults(Me())
end

-- Our gang: the website's, with our actions it has not answered yet laid over it.
-- { name, leader, members = { { key, class, race, sex, level } }, pending (true while
-- an action waits for HeadHunter Sync) } or nil
function Gangs:Mine()
    local me = Me()
    if not me or not Gangs.Enabled() then return nil end
    local gang
    for _, g in ipairs(ns.SiteData:Gangs()) do
        for _, member in ipairs(g.members) do
            if member.key == me then gang = { name = g.name, leader = g.leader, members = g.members, confirmed = true } end
        end
    end
    local results = self:Results()
    for _, action in ipairs(self:Actions()) do
        local result = results[action.uid]
        if not result or result.status == "waiting" then
            if action.kind == "create" then
                gang = { name = action.name, leader = me, members = { { key = me } }, pending = true }
            elseif action.kind == "accept" and (not gang or not result) then
                gang = { name = action.name or "?", leader = action.leader, members = { { key = action.leader }, { key = me } },
                    pending = true }
            elseif action.kind == "leave" then
                gang = nil
            elseif action.kind == "rename" and gang then
                gang = { name = action.name, leader = gang.leader, members = gang.members, pending = true,
                    confirmed = gang.confirmed }
            elseif action.kind == "invite" and action.accepted and gang then
                local known = false
                for _, member in ipairs(gang.members) do
                    if ns.Utils.SameCharacter(member.key, action.player) then known = true end
                end
                if not known then
                    local members = {}
                    for i, member in ipairs(gang.members) do members[i] = member end
                    members[#members + 1] = { key = action.player, pending = true }
                    gang = { name = gang.name, leader = gang.leader, members = members, pending = gang.pending,
                        confirmed = gang.confirmed }
                end
            end
        end
    end
    return gang
end

-- A member's class: the website's, else ours for us, else what we saw of them
function Gangs:MemberClass(member)
    if member.class then return member.class end
    local U = ns.Utils
    if U.SameCharacter(member.key, Me()) and UnitClass then
        local _, class = UnitClass("player")
        return class
    end
    local seen = ns.EnemyCache and ns.EnemyCache:ByKey(member.key)
    return seen and seen.class or nil
end

function Gangs:IsLeader(gang)
    gang = gang or self:Mine()
    return gang ~= nil and gang.leader ~= nil and ns.Utils.SameCharacter(gang.leader, Me())
end

-- The gang a player is in, by the website's lists: its name, or nil
function Gangs:Of(key)
    if not key then return nil end
    for _, g in ipairs(ns.SiteData:Gangs()) do
        for _, member in ipairs(g.members) do
            if ns.Utils.SameCharacter(member.key, key) then return g.name end
        end
    end
    return nil
end

-- Says once what came of each answered action
function Gangs:TellResults()
    local results = self:Results()
    for _, action in ipairs(self:Actions()) do
        local result = results[action.uid]
        if result and not action.told and result.status ~= "waiting" then
            action.told = true
            if result.status == "refused" then
                local reason = Gangs.REASONS[result.reason] and L["GANG_REFUSED_" .. result.reason:upper()] or result.reason
                ns:Print(string.format(L.GANG_REFUSED, L["GANG_KIND_" .. action.kind:upper()], tostring(reason)))
            elseif action.kind == "create" or action.kind == "accept" or action.kind == "rename" then
                ns:Print(string.format(L.GANG_CONFIRMED, result.gang or action.name or "?"))
            end
        end
    end
end

-------------------------------------------------
-- Invites
-------------------------------------------------

local function UnderInviteLimit(now)
    local recent = {}
    for _, at in ipairs(inviteLog) do
        if now - at < Gangs.INVITE_WINDOW then recent[#recent + 1] = at end
    end
    inviteLog = recent
    return #recent < Gangs.INVITE_LIMIT
end

-- Invite a player key; returns true when the whisper went out
function Gangs:Invite(key)
    local gang = self:Mine()
    if not gang then ns:Print(L.GANG_NOT_IN_A_GANG) return false end
    if not self:IsLeader(gang) then ns:Print(L.GANG_NOT_LEADER) return false end
    if not gang.confirmed then ns:Print(L.GANG_INVITE_UNCONFIRMED) return false end
    if not key or ns.Utils.SameCharacter(key, Me()) then ns:Print(L.GANG_INVITE_WHO) return false end
    if #gang.members >= Gangs.MAX_MEMBERS then ns:Print(L.GANG_FULL) return false end
    local now = ns.Utils.Now()
    if not UnderInviteLimit(now) then ns:Print(L.GANG_INVITE_SLOW) return false end
    inviteLog[#inviteLog + 1] = now
    sentInvites[key] = now
    heard[key] = nil
    ns.Transport:SendDirect(ns.Protocol.TYPES.GANG, { "i;" .. gang.name }, key)
    self:Record("invite", { player = key })
    C_Timer.After(Gangs.ACK_WAIT, function()
        if sentInvites[key] == now and not heard[key] then
            ns:Print(string.format(L.GANG_NO_ADDON, ns.Utils.DisplayName(key)))
        end
    end)
    ns:Print(string.format(L.GANG_INVITE_SENT, ns.Utils.DisplayName(key), gang.name))
    return true
end

local function Answer(code, target)
    ns.Transport:SendDirect(ns.Protocol.TYPES.GANG, { code }, target)
end

function Gangs:AcceptInvite()
    local invite = incoming
    incoming = nil
    if not invite or ns.Utils.Now() - invite.at > Gangs.INVITE_TIMEOUT then return nil end
    local action = self:Record("accept", { leader = invite.leader, name = invite.name })
    Answer("a", invite.sender)
    ns:Print(string.format(L.GANG_JOIN_WAITING, invite.name))
    return action
end

function Gangs:DeclineInvite()
    local invite = incoming
    incoming = nil
    if invite then Answer("d", invite.sender) end
end

local function OnInvite(name, sender)
    local leader = ns.Utils.PlayerKey(sender)
    name = Gangs.CleanName(name)
    if not leader or not Gangs.ValidName(name) then return end
    if not Gangs.Enabled() or ns.Database:GetSetting("gangInvites") == false or Gangs:Mine() then
        Answer("d", sender)
        return
    end
    Answer("r", sender)
    incoming = { leader = leader, name = name, at = ns.Utils.Now(), sender = sender }
    StaticPopupDialogs[Gangs.POPUP].text = string.format(L.GANG_INVITE_POPUP, ns.Utils.DisplayName(leader), name)
    StaticPopup_Show(Gangs.POPUP)
end

-- Our latest invite action of a player, while it is not answered by the website
local function InviteActionOf(key)
    local found
    for _, action in ipairs(Gangs:Actions()) do
        if action.kind == "invite" and ns.Utils.SameCharacter(action.player, key) then found = action end
    end
    return found
end

local function OnAnswer(code, sender)
    local key = ns.Utils.PlayerKey(sender)
    local at = key and sentInvites[key]
    if not at or ns.Utils.Now() - at > Gangs.INVITE_TIMEOUT then return end
    heard[key] = true
    if code == "r" then return end
    sentInvites[key] = nil
    local accepted = code == "a"
    if accepted then
        local action = InviteActionOf(key)
        if action then action.accepted = true end
        ns.Events:Fire("HH_GANG_CHANGED", action)
    end
    ns:Print(string.format(accepted and L.GANG_INVITE_ACCEPTED or L.GANG_INVITE_DECLINED, ns.Utils.DisplayName(key)))
end

function Gangs:OnMessage(record, sender)
    if type(record) ~= "string" then return end
    local code, rest = record:match("^(%a);?(.*)$")
    if code == "i" then
        OnInvite(rest, sender)
    elseif code == "a" or code == "d" or code == "r" then
        OnAnswer(code, sender)
    end
end

-- Forget invites and limits (tests)
function Gangs:Reset()
    sentInvites, inviteLog, incoming, counter, heard = {}, {}, nil, 0, {}
end

-------------------------------------------------
-- /hh gang
-------------------------------------------------

local function Rest(args, from)
    local words = {}
    for i = from, #args do words[#words + 1] = args[i] end
    return table.concat(words, " ")
end

-- A typed name, else the target if it is a friendly player
local function Named(args)
    local typed = Rest(args, 2)
    if typed ~= "" then return ns.Utils.PlayerKey(typed) end
    if UnitIsPlayer and UnitIsPlayer("target") and not (UnitIsEnemy and UnitIsEnemy("player", "target")) then
        return ns.Utils.UnitKey("target")
    end
    return nil
end

local function Member(gang, key)
    for _, member in ipairs(gang and gang.members or {}) do
        if ns.Utils.SameCharacter(member.key, key) then return member end
    end
    return nil
end

function Gangs:PrintStatus()
    local gang = self:Mine()
    if not gang then ns:Print(L.GANG_NONE) return end
    local names = {}
    for _, member in ipairs(gang.members) do
        local name = ns.Utils.DisplayName(member.key)
        names[#names + 1] = ns.Utils.SameCharacter(member.key, gang.leader) and (name .. " *") or name
    end
    ns:Print(string.format(gang.pending and L.GANG_STATUS_PENDING or L.GANG_STATUS, gang.name, #gang.members,
        table.concat(names, ", ")))
end

function Gangs:Command(args)
    if not Gangs.Enabled() then ns:Print(L.GANG_FOREVER_ONLY) return end
    local sub = args[1] and args[1]:lower() or ""
    local gang = self:Mine()
    if sub == "" or sub == "info" then
        self:PrintStatus()
    elseif sub == "create" then
        local name = Gangs.CleanName(Rest(args, 2))
        if gang then ns:Print(L.GANG_ALREADY) return end
        if not Gangs.ValidName(name) then ns:Print(L.GANG_BAD_NAME) return end
        self:Record("create", { name = name })
        ns:Print(string.format(L.GANG_CREATE_WAITING, name))
    elseif sub == "invite" then
        self:Invite(Named(args))
    elseif sub == "leave" then
        if not gang then ns:Print(L.GANG_NOT_IN_A_GANG) return end
        self:Record("leave")
        ns:Print(string.format(L.GANG_LEFT, gang.name))
    elseif sub == "kick" or sub == "lead" then
        if not gang then ns:Print(L.GANG_NOT_IN_A_GANG) return end
        if not self:IsLeader(gang) then ns:Print(L.GANG_NOT_LEADER) return end
        local key = Named(args)
        if not key or ns.Utils.SameCharacter(key, Me()) or not Member(gang, key) then ns:Print(L.GANG_NOT_MEMBER) return end
        self:Record(sub, { player = key })
        ns:Print(string.format(sub == "kick" and L.GANG_KICKED or L.GANG_LEAD_GIVEN, ns.Utils.DisplayName(key)))
    elseif sub == "color" then
        if ns.GangChat.SetColor(args[2]) then ns:Print(L.GANG_CHAT_COLOR_SET) else ns:Print(L.GANG_CHAT_COLOR_BAD) end
    elseif sub == "socialtab" then
        local mode = args[2] and args[2]:lower()
        ns.Database:SetSetting("gangSocialTab", mode == "on")
        ns:Print(mode == "on" and L.GANG_SOCIALTAB_ON or L.GANG_SOCIALTAB_OFF)
    elseif sub == "rename" then
        if not gang then ns:Print(L.GANG_NOT_IN_A_GANG) return end
        if not self:IsLeader(gang) then ns:Print(L.GANG_NOT_LEADER) return end
        local name = Gangs.CleanName(Rest(args, 2))
        if not Gangs.ValidName(name) then ns:Print(L.GANG_BAD_NAME) return end
        self:Record("rename", { name = name })
        ns:Print(string.format(L.GANG_RENAME_WAITING, name))
    else
        ns:Print(L.GANG_USAGE)
    end
end

-- The name a popup's edit box holds (the box's field differs between client versions)
local function PopupText(popup)
    local box = popup and (popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox()))
    return box and box.GetText and box:GetText() or ""
end

-- Create gang: a popup asks for the name, then the same checks as /hh gang create
function Gangs:PromptCreate()
    if not Gangs.Enabled() then ns:Print(L.GANG_FOREVER_ONLY) return end
    if self:Mine() then ns:Print(L.GANG_ALREADY) return end
    StaticPopup_Show(Gangs.CREATE_POPUP)
end

-- Leave (the buttons): a popup asks first; a leader is told the lead passes on
function Gangs:PromptLeave()
    local gang = self:Mine()
    if not gang then ns:Print(L.GANG_NOT_IN_A_GANG) return end
    local others = #gang.members > 1
    local text = self:IsLeader(gang) and others and L.GANG_LEAVE_POPUP_LEADER or L.GANG_LEAVE_POPUP
    StaticPopupDialogs[Gangs.LEAVE_POPUP].text = string.format(text, gang.name)
    StaticPopup_Show(Gangs.LEAVE_POPUP)
end

function Gangs:CreateFromPopup(popup)
    local args = { "create" }
    for word in PopupText(popup):gmatch("%S+") do args[#args + 1] = word end
    self:Command(args)
end

ns.SlashCommands:Register("gang", function(args) Gangs:Command(args) end, L.HELP_GANG)

ns.Events:Register("HH_INITIALIZED", function()
    Gangs:Prune()
    StaticPopupDialogs[Gangs.POPUP] = {
        text = "",
        button1 = L.GANG_ACCEPT,
        button2 = L.GANG_DECLINE,
        OnAccept = function() Gangs:AcceptInvite() end,
        OnCancel = function() Gangs:DeclineInvite() end,
        timeout = Gangs.INVITE_TIMEOUT,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    StaticPopupDialogs[Gangs.LEAVE_POPUP] = {
        text = "",
        button1 = L.GANG_LEAVE_BUTTON,
        button2 = CANCEL,
        OnAccept = function() Gangs:Command({ "leave" }) end,
        timeout = 0,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    StaticPopupDialogs[Gangs.CREATE_POPUP] = {
        text = L.GANG_CREATE_POPUP,
        button1 = L.GANG_CREATE_BUTTON,
        button2 = CANCEL,
        hasEditBox = 1,
        maxLetters = Gangs.NAME_MAX,
        OnAccept = function(popup) Gangs:CreateFromPopup(popup) end,
        EditBoxOnEnterPressed = function(box)
            local popup = box:GetParent()
            Gangs:CreateFromPopup(popup)
            popup:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    ns.Transport:RegisterHandler(ns.Protocol.TYPES.GANG, function(record, sender)
        Gangs:OnMessage(record, sender)
    end)
    if Gangs.Enabled() then Gangs:TellResults() end
end, OWNER)
