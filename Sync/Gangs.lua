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
-- members at most (author, 2026-11-04: 50, was 10), as the website
Gangs.MAX_MEMBERS = 50
-- seconds an invite stays open
Gangs.INVITE_TIMEOUT = 60
-- invites sent per INVITE_WINDOW
Gangs.INVITE_LIMIT = 5
Gangs.INVITE_WINDOW = 60
-- seconds for the invited player's addon to say it got the invite; silence means not
-- online or no HeadHunter
Gangs.ACK_WAIT = 10
-- seconds after leaving a gang (or being kicked) before joining one again, as the website
Gangs.JOIN_COOLDOWN = 86400
-- seconds our actions are kept
Gangs.GANG_KEEP = 30 * 86400
Gangs.POPUP = "HEADHUNTER_GANG_INVITE"
Gangs.CREATE_POPUP = "HEADHUNTER_GANG_CREATE"
Gangs.LEAVE_POPUP = "HEADHUNTER_GANG_LEAVE"
-- The website's Gangs page, where taken names can be checked (the download's own link wins)
Gangs.SITE_GANGS = "https://headhunterwow.com/gangs"
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

-- Members who told us they left (player key -> time), until the website's list catches up
local function Departed()
    return ns.db and ns.db.gangDeparted or {}
end

local function Me()
    return ns.Utils.UnitKey("player")
end

-- Our class token ("ROGUE"), or nil
local function MyClass()
    if not UnitClass then return nil end
    local _, class = UnitClass("player")
    return class
end

-- Our level, or nil
local function MyLevel()
    local level = UnitLevel and UnitLevel("player")
    return type(level) == "number" and level > 0 and level or nil
end

-- A level from a message, or nil
local function LevelOf(text)
    local level = tonumber(text)
    return level and level > 0 and level <= 255 and level or nil
end

-- A class token from a message, or nil ("ROGUE" only: capitals)
local function ClassToken(text)
    return type(text) == "string" and text:match("^%u+$") or nil
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
    for key, at in pairs(ns.db.gangDeparted or {}) do
        if at < minTime then ns.db.gangDeparted[key] = nil end
    end
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
                gang = { name = action.name or "?", leader = action.leader,
                    members = { { key = action.leader, class = action.leaderClass, level = action.leaderLevel }, { key = me } },
                    pending = true }
            elseif action.kind == "leave" then
                gang = nil
            elseif action.kind == "rename" and gang then
                gang = { name = action.name, leader = gang.leader, members = gang.members, pending = true,
                    confirmed = gang.confirmed }
            elseif action.kind == "kick" and gang then
                gang = Gangs.Without(gang, action.player)
            elseif action.kind == "invite" and action.accepted and gang then
                local known = false
                for _, member in ipairs(gang.members) do
                    if ns.Utils.SameCharacter(member.key, action.player) then known = true end
                end
                if not known then
                    local members = {}
                    for i, member in ipairs(gang.members) do members[i] = member end
                    members[#members + 1] = { key = action.player, pending = true, class = action.memberClass,
                        level = action.memberLevel }
                    gang = { name = gang.name, leader = gang.leader, members = members, pending = gang.pending,
                        confirmed = gang.confirmed }
                end
            end
        end
    end
    if gang then
        local departed = Departed()
        for key, at in pairs(departed) do
            local member = nil
            for _, m in ipairs(gang.members) do
                if ns.Utils.SameCharacter(m.key, key) then member = m end
            end
            if member and (member.joinedAt or 0) < at then gang = Gangs.Without(gang, key) end
        end
    end
    return gang
end

-- The gang without one member (a kick or a member who said they left)
function Gangs.Without(gang, key)
    local members = {}
    for _, member in ipairs(gang.members) do
        if not ns.Utils.SameCharacter(member.key, key) then members[#members + 1] = member end
    end
    return { name = gang.name, leader = gang.leader, members = members, pending = gang.pending, confirmed = gang.confirmed }
end

-- A member's class: the website's, else ours for us, else what an invite or its answer
-- carried, else what we saw of them
function Gangs:MemberClass(member)
    if member.class then return member.class end
    local U = ns.Utils
    if U.SameCharacter(member.key, Me()) then return MyClass() end
    for _, action in ipairs(self:Actions()) do
        if action.kind == "invite" and U.SameCharacter(action.player, member.key) and action.memberClass then
            return action.memberClass
        end
        if action.kind == "accept" and U.SameCharacter(action.leader, member.key) and action.leaderClass then
            return action.leaderClass
        end
    end
    local seen = ns.EnemyCache and ns.EnemyCache:ByKey(member.key)
    return seen and seen.class or nil
end

-- A member's level: the website's, else ours for us, else what an invite or its answer carried
function Gangs:MemberLevel(member)
    if member.level then return member.level end
    local U = ns.Utils
    if U.SameCharacter(member.key, Me()) then return MyLevel() end
    for _, action in ipairs(self:Actions()) do
        if action.kind == "invite" and U.SameCharacter(action.player, member.key) and action.memberLevel then
            return action.memberLevel
        end
        if action.kind == "accept" and U.SameCharacter(action.leader, member.key) and action.leaderLevel then
            return action.leaderLevel
        end
    end
    return nil
end

-- Whether a member is online: us; else the latest sign wins. Joining or speaking in the gang
-- chat channel says online; leaving it says offline (a logout, or leaving the gang) unless
-- the HeadHunter channel heard them after that; else heard there lately (Presence).
function Gangs:IsOnline(key)
    local U = ns.Utils
    if U.SameCharacter(key, Me()) then return true end
    local chat = ns.GangChat and ns.GangChat:Seen(key)
    if chat and chat.online then return true end
    local name = U.CompactName(key)
    local heard = name and ns.Presence:LastHeard(name)
    if chat and not chat.online and (not heard or heard <= chat.t) then return false end
    return name ~= nil and ns.Presence:Knows(name) == true
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

-- Whether a gang of the website's lists on our world has this name already (any case)
function Gangs:NameTaken(name)
    local wanted = Gangs.CleanName(name):lower()
    for _, g in ipairs(ns.SiteData:Gangs()) do
        if Gangs.CleanName(g.name):lower() == wanted then return true end
    end
    return false
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
function Gangs:Invite(key, class, level)
    local gang = self:Mine()
    if not gang then ns:Print(L.GANG_NOT_IN_A_GANG) return false end
    if not self:IsLeader(gang) then ns:Print(L.GANG_NOT_LEADER) return false end
    if not gang.confirmed then ns:Print(L.GANG_INVITE_UNCONFIRMED) return false end
    if not key or ns.Utils.SameCharacter(key, Me()) then ns:Print(L.GANG_INVITE_WHO) return false end
    for _, member in ipairs(gang.members) do
        if ns.Utils.SameCharacter(member.key, key) then
            ns:Print(string.format(L.GANG_ALREADY_MEMBER, ns.Utils.DisplayName(key)))
            return false
        end
    end
    local leftAt = Departed()[key]
    local wait = leftAt and (leftAt + Gangs.JOIN_COOLDOWN - ns.Utils.ServerTime())
    if wait and wait > 0 then
        ns:Print(string.format(L.GANG_RULE_COOLDOWN_OTHER, ns.Utils.DisplayName(key), Gangs.Hours(wait)))
        return false
    end
    if #gang.members >= Gangs.MAX_MEMBERS then ns:Print(L.GANG_FULL) return false end
    local now = ns.Utils.Now()
    if not UnderInviteLimit(now) then ns:Print(L.GANG_INVITE_SLOW) return false end
    inviteLog[#inviteLog + 1] = now
    sentInvites[key] = now
    heard[key] = nil
    ns.Transport:SendDirect(ns.Protocol.TYPES.GANG, { "i;" .. gang.name .. ";" .. (MyClass() or "") .. ";" .. (MyLevel() or "") }, key)
    self:Record("invite", { player = key, memberClass = ClassToken(class), memberLevel = LevelOf(level) })
    C_Timer.After(Gangs.ACK_WAIT, function()
        if sentInvites[key] == now and not heard[key] then
            ns:Print(string.format(L.GANG_NO_ADDON, ns.Utils.DisplayName(key)))
        end
    end)
    ns:Print(string.format(L.GANG_INVITE_SENT, ns.Utils.DisplayName(key), gang.name))
    return true
end

-- Seconds until we may join a gang again after our own last leave, or nil
function Gangs:CooldownLeft(now)
    now = now or ns.Utils.ServerTime()
    local last
    for _, action in ipairs(self:Actions()) do
        if action.kind == "leave" and not action.cooldownCleared and (not last or action.t > last) then last = action.t end
    end
    local left = last and (last + Gangs.JOIN_COOLDOWN - now)
    return left and left > 0 and left or nil
end

-- "17 h", "40 min"
function Gangs.Hours(seconds)
    if seconds >= 3600 then return string.format(L.GANG_HOURS, math.ceil(seconds / 3600)) end
    return string.format(L.GANG_MINUTES, math.max(1, math.ceil(seconds / 60)))
end

local function Answer(code, target)
    ns.Transport:SendDirect(ns.Protocol.TYPES.GANG, { code }, target)
end

function Gangs:AcceptInvite()
    local invite = incoming
    incoming = nil
    if not invite or ns.Utils.Now() - invite.at > Gangs.INVITE_TIMEOUT then return nil end
    local action = self:Record("accept", { leader = invite.leader, name = invite.name, leaderClass = invite.leaderClass,
        leaderLevel = invite.leaderLevel })
    Answer("a;" .. (MyClass() or "") .. ";" .. (MyLevel() or ""), invite.sender)
    ns:Print(string.format(L.GANG_JOIN_WAITING, invite.name))
    return action
end

function Gangs:DeclineInvite()
    local invite = incoming
    incoming = nil
    if invite then Answer("d", invite.sender) end
end

local function OnInvite(rest, sender)
    local leader = ns.Utils.PlayerKey(sender)
    local name, leaderClass, leaderLevel = rest:match("^(.-);(%u*);?(%d*)$")
    name = Gangs.CleanName(name or rest)
    if not leader or not Gangs.ValidName(name) then return end
    if Gangs.Enabled() and Gangs:Mine() then
        Answer("g", sender)
        ns:Print(string.format(L.GANG_INVITE_WHILE_IN_GANG, ns.Utils.DisplayName(leader), name))
        return
    end
    if not Gangs.Enabled() or ns.Database:GetSetting("gangInvites") == false then
        Answer("d", sender)
        return
    end
    local wait = Gangs:CooldownLeft()
    if wait then
        Answer("c;" .. wait, sender)
        ns:Print(string.format(L.GANG_RULE_COOLDOWN_SELF, Gangs.Hours(wait)))
        return
    end
    Answer("r", sender)
    incoming = { leader = leader, name = name, at = ns.Utils.Now(), sender = sender, leaderClass = ClassToken(leaderClass),
        leaderLevel = LevelOf(leaderLevel) }
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

local function OnAnswer(code, sender, rest)
    local key = ns.Utils.PlayerKey(sender)
    local at = key and sentInvites[key]
    if not at or ns.Utils.Now() - at > Gangs.INVITE_TIMEOUT then return end
    heard[key] = true
    if code == "r" then return end
    if code == "g" then
        sentInvites[key] = nil
        ns:Print(string.format(L.GANG_INVITEE_IN_GANG, ns.Utils.DisplayName(key)))
        return
    end
    if code == "c" then
        sentInvites[key] = nil
        local wait = tonumber(rest) or Gangs.JOIN_COOLDOWN
        ns:Print(string.format(L.GANG_RULE_COOLDOWN_OTHER, ns.Utils.DisplayName(key), Gangs.Hours(wait)))
        return
    end
    sentInvites[key] = nil
    local accepted = code == "a"
    if accepted then
        local action = InviteActionOf(key)
        if action then
            action.accepted = true
            local class, level = (rest or ""):match("^(%u*);?(%d*)$")
            action.memberClass = ClassToken(class) or action.memberClass
            action.memberLevel = LevelOf(level) or action.memberLevel
        end
        ns.Events:Fire("HH_GANG_CHANGED", action)
    end
    ns:Print(string.format(accepted and L.GANG_INVITE_ACCEPTED or L.GANG_INVITE_DECLINED, ns.Utils.DisplayName(key)))
end

function Gangs:OnMessage(record, sender)
    if type(record) ~= "string" then return end
    local code, rest = record:match("^(%a);?(.*)$")
    if code == "i" then
        OnInvite(rest, sender)
    elseif code == "a" or code == "d" or code == "r" or code == "c" or code == "g" then
        OnAnswer(code, sender, rest)
    elseif code == "l" then
        self:OnLeft(sender)
    end
end

-- A member said they left: off our list now, until the website's list catches up
function Gangs:OnLeft(sender)
    local key = ns.Utils.PlayerKey(sender)
    local gang = self:Mine()
    if not (key and gang and ns.db) then return end
    local inGang = false
    for _, member in ipairs(gang.members) do
        if ns.Utils.SameCharacter(member.key, key) then inGang = true end
    end
    if not inGang then return end
    ns.db.gangDeparted = ns.db.gangDeparted or {}
    ns.db.gangDeparted[key] = ns.Utils.ServerTime()
    ns:Print(string.format(L.GANG_MEMBER_LEFT, ns.Utils.DisplayName(key)))
    ns.Events:Fire("HH_GANG_CHANGED")
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

-- A typed name, else the target if it is a friendly player (then with its class and level)
local function Named(args)
    local typed = Rest(args, 2)
    if typed ~= "" then return ns.Utils.PlayerKey(typed) end
    if UnitIsPlayer and UnitIsPlayer("target") and not (UnitIsEnemy and UnitIsEnemy("player", "target")) then
        local class = UnitClass and select(2, UnitClass("target"))
        local level = UnitLevel and UnitLevel("target")
        return ns.Utils.UnitKey("target"), class, level
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
        if self:NameTaken(name) then ns:Print(L.GANG_NAME_TAKEN) return end
        local wait = self:CooldownLeft()
        if wait then ns:Print(string.format(L.GANG_RULE_COOLDOWN_SELF, Gangs.Hours(wait))) return end
        self:Record("create", { name = name })
        ns:Print(string.format(L.GANG_CREATE_WAITING, name))
    elseif sub == "invite" then
        local key, class, level = Named(args)
        self:Invite(key, class, level)
    elseif sub == "leave" then
        if not gang then ns:Print(L.GANG_NOT_IN_A_GANG) return end
        for _, member in ipairs(gang.members) do
            if not ns.Utils.SameCharacter(member.key, Me()) then
                ns.Transport:SendDirect(ns.Protocol.TYPES.GANG, { "l" }, member.key)
            end
        end
        self:Record("leave")
        ns:Print(string.format(L.GANG_LEFT, gang.name))
    elseif sub == "kick" or sub == "lead" then
        if not gang then ns:Print(L.GANG_NOT_IN_A_GANG) return end
        if not self:IsLeader(gang) then ns:Print(L.GANG_NOT_LEADER) return end
        local key = Named(args)
        if not key or ns.Utils.SameCharacter(key, Me()) or not Member(gang, key) then ns:Print(L.GANG_NOT_MEMBER) return end
        self:Record(sub, { player = key })
        ns:Print(string.format(sub == "kick" and L.GANG_KICKED or L.GANG_LEAD_GIVEN, ns.Utils.DisplayName(key)))
    elseif sub == "testreset" and ns.Dev.Present() then
        for _, action in ipairs(self:Actions()) do
            if action.kind == "leave" then action.cooldownCleared = true end
        end
        if ns.db then ns.db.gangDeparted = {} end
        ns:Print(L.GANG_TEST_RESET)
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
    local link = Gangs.NamesLink()
    StaticPopupDialogs[Gangs.CREATE_POPUP].text = L.GANG_CREATE_POPUP .. "\n\n" .. string.format(L.GANG_NAMES_LINK, link)
    ns:Print(string.format(L.GANG_NAMES_LINK, link))
    StaticPopup_Show(Gangs.CREATE_POPUP)
end

-- The website's Gangs page, where taken names can be checked
function Gangs.NamesLink()
    return ns.SiteData:Link("gangs") or Gangs.SITE_GANGS
end

-- Not in a gang: first where to check that a name is free, then how to make one
function Gangs.EmptyText()
    return string.format(L.GANG_NAMES_LINK, Gangs.NamesLink()) .. "\n\n" .. L.EMPTY_GANG
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
