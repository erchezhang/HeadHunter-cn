-- HH-020: silent, batched, asynchronous transport.
-- Principles: docs/addon/tickets.md M2 "Sync principles" and features.md section 7.
--
--   Transport:Queue(typeCode, record, priority, coalesceKey)
--   Transport:RegisterHandler(typeCode, function(record, sender, faction, chatType) end)
--   Transport:SendRealmWide(typeCode, records)   -- Era: only from a click / typed command
--   Transport:SendDirect(typeCode, records, target) -- addon whispers to one player (catch-up)
--
-- Automatic routes (addon messages, no player action needed), chosen per flush:
--   Forever: the hidden channel HeadHunterSync (realm/region wide, every layer), and
--            RAID or PARTY too when grouped, so a group always shares, also when the
--            channel does not reach one of them (HH-150). A message heard twice (channel
--            and group) from the same sender within DUPLICATE_WINDOW is taken once.
--            1.0.4: since the launch (2026-11-04) the server refuses addon messages on
--            custom channels, answering 0 then a hidden notice (or code 7). A refusal
--            notice, code 7, or SILENT_SENDS channel sends without hearing anyone there
--            for SILENT_FOR seconds make the channel deaf: it is left out of the routes and
--            one probe goes on it every PROBE_EVERY seconds; hearing anyone there ends it.
--            Records then spread by addon whisper among the channel's members
--            (Sync/Gossip.lua), and Forever never falls back to GUILD (its messages may
--            show in guild members' chat). If someone puts a password on the channel, we
--            move to BACKUP_CHANNEL.
--   Era:     GUILD when in a guild, RAID or PARTY when grouped. Era refuses addon
--            messages on custom channels (result 4 InvalidChatType, in game 2026-09-23).
-- Realm-wide on Era: plain chat text on the same channel IS delivered when it comes
-- from a hardware event (in game 2026-09-23), so SendRealmWide is called from the
-- "Report to all HeadHunters" click (Sync/ReportPrompt.lua) and /hh report.
--
-- Outbox: records wait and are packed into as few messages as possible every
-- FLUSH_INTERVAL seconds (COMBAT_FLUSH_INTERVAL in combat), sent under a token
-- bucket, never while suspended (instances). Inbox: received records are handled
-- under a per-frame time budget, never inside the event handler.
-- Nothing here prints to chat except in debug mode and the manual tests.

local addonName, ns = ...

local Transport = ns:RegisterModule("Transport", {})

local OWNER = "Transport"

Transport.PREFIX = "HeadHunter"
Transport.CHANNEL = "HeadHunterSync"
Transport.BACKUP_CHANNEL = "HeadHunterSync2"
-- 1.0.4: the channel refused (see the header)
Transport.SILENT_SENDS = 3
Transport.SILENT_FOR = 300
Transport.PROBE_EVERY = 300
Transport.HEARD_FOR = 600
Transport.REFUSAL_NOTICES = { NOT_ALLOWED_IN_CHANNEL = true, TRIAL_RESTRICTED = true, MUTED = true }
Transport.CHAT_MARK = "HH1:"     -- marks our lines in channel chat text

Transport.FLUSH_INTERVAL = 3
Transport.COMBAT_FLUSH_INTERVAL = 10
Transport.BURST = 4          -- messages that may go out back to back
Transport.PER_SECOND = 1     -- sustained messages per second
Transport.INBOX_BUDGET_MS = 3
Transport.JOIN_DEFER_MAX = 30 -- x JOIN_STEP s waiting for the player's channels to be back
Transport.JOIN_STEP = 1
-- 1.0.6: the player's channel list must stay the same this many steps before we join
Transport.JOIN_CALM_STEPS = 2
-- 1.0.6: placeholders in the free numbers below the player's last channel while ours join,
-- left PAD_HOLD seconds after; at most PAD_MAX of them
Transport.PAD_PREFIX = "HHPad"
Transport.PAD_MAX = 8
Transport.PAD_WAIT = 2
Transport.PAD_HOLD = 8
Transport.GENERAL_REJOIN_WAIT = 1
Transport.MAX_OUTBOX = 200    -- records kept while no route is available
Transport.MAX_TEXT_MESSAGES = 2 -- channel text lines sent per click
Transport.DUPLICATE_WINDOW = 30 -- seconds a message heard on one route is not taken again
Transport.JOIN_RETRIES = 3    -- joins tried after the first, JOIN_RETRY_DELAY apart, before the warning
Transport.JOIN_RETRY_DELAY = 20
-- HH-151: records carried for HeadHunters of other servers use at most half the send
-- budget, after our own (Sync/Bridge.lua); RELAY_TAKE records are packed per message
Transport.RELAY_PER_SECOND = 0.5
Transport.RELAY_BURST = 2
Transport.RELAY_TAKE = 3
Transport.MAX_DIRECT = 150    -- whisper messages waiting (catch-up answers)

-- Lower number = sent first
Transport.PRIORITY = { alert = 1, posse = 2, hotspot = 3, bulk = 4 }

local outbox = {}      -- array of { type, record, priority, key, seq }
local coalesce = {}    -- key -> outbox entry
local inbox = {}       -- queue of { type, record, sender, faction, chatType }
local inboxHead = 1    -- next item to handle
local inboxTail = 0    -- last item added (explicit: # is undefined once the front is cleared)
local handlers = {}
local seq = 0
local direct = {}      -- array of { message, target }: whispers to one player, oldest first

local tokens = Transport.BURST
local lastRefill
local relayTokens = Transport.RELAY_BURST
local relayRefill

Transport.stats = { sent = 0, records = 0, received = 0, dropped = 0, failed = 0 }

-- Diagnostics for /hh sync
Transport.diag = { blocked = nil, lastResult = nil, lastSender = nil, lastIgnored = nil, routes = nil }

local function MyFactionCode()
    return ns.Protocol.FACTION_CODE[ns.Utils.UnitFaction("player") or ""]
end

-------------------------------------------------
-- Channel
-------------------------------------------------

function Transport:ChannelID()
    local id = tonumber((ns.Utils.SafeCall(GetChannelName, self.CHANNEL)))
    return id and id > 0 and id or nil
end

local function IsOurChannel(channelBaseName, channelName)
    local ours = Transport.CHANNEL:lower()
    if type(channelBaseName) == "string" and channelBaseName:lower() == ours then return true end
    return type(channelName) == "string" and channelName:lower():match("^%d+%. (.+)$") == ours
end

-- 1.0.6: our placeholders' join and leave notices are hidden too
local function IsOurPad(channelBaseName, channelName)
    local ok, pad = pcall(function()
        return Transport.IsPad(channelBaseName) or Transport.IsPad(type(channelName) == "string" and channelName:match("^%d+%. (.+)$"))
    end)
    return ok and pad
end

-- Chat filter args: self, event, text, playerName, languageName, channelName ("5. Name"),
-- playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, ...

-- Hide our channel's join/leave/notice lines
local function ChannelNoticeFilter(_, _, _, _, _, channelName, _, _, _, _, channelBaseName)
    return IsOurChannel(channelBaseName, channelName) or IsOurPad(channelBaseName, channelName)
end

-- Hide our marked chat-text lines
local function ChannelTextFilter(_, _, text, _, _, channelName, _, _, _, _, channelBaseName)
    return IsOurChannel(channelBaseName, channelName) and type(text) == "string"
        and text:sub(1, #Transport.CHAT_MARK) == Transport.CHAT_MARK
end

local function InstallChatFilters()
    local add = ChatFrame_AddMessageEventFilter
        or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if not add then return end
    for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
            "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
        pcall(add, event, ChannelNoticeFilter)
    end
    pcall(add, "CHAT_MSG_CHANNEL", ChannelTextFilter)
end

-- 1.0.5: our own channels: this one, its backup, and gang chat channels (Sync/GangChat.lua)
function Transport.IsOwnChannel(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    if lower == Transport.CHANNEL:lower() or lower == Transport.BACKUP_CHANNEL:lower() then return true end
    if Transport.IsPad(name) then return true end
    return ns.GangChat ~= nil and ns.GangChat.IsGangChannel(name) == true
end

function Transport.IsPad(name)
    return type(name) == "string" and name:sub(1, #Transport.PAD_PREFIX):lower() == Transport.PAD_PREFIX:lower()
end

-- The joined channels: { { number, name } } in order (empty without GetChannelList)
function Transport.Channels()
    local channels = {}
    if type(GetChannelList) ~= "function" then return channels end
    local list = { ns.Utils.SafeCall(GetChannelList) }
    for i = 2, #list, 3 do
        local number, name = tonumber(list[i - 1]), list[i]
        local ok, readable = pcall(function() return type(name) == "string" and name ~= "" end)
        if number and ok and readable then channels[#channels + 1] = { number = number, name = name } end
    end
    return channels
end

-- The highest number of the player's channels (not ours), and of ours, or 0
function Transport.HighestNumbers()
    local others, ours = 0, 0
    for _, channel in ipairs(Transport.Channels()) do
        if Transport.IsOwnChannel(channel.name) then
            if not Transport.IsPad(channel.name) then ours = math.max(ours, channel.number) end
        else
            others = math.max(others, channel.number)
        end
    end
    return others, ours
end

-- The game's or the player's own channels are in place: one joined channel that is not
-- ours (1.0.5: our gang channel in /1 used to count, so ours took /2 and General /3;
-- seen in game 2026-11-06). Without GetChannelList: anything in slot 1.
function Transport.OthersJoined()
    return Transport.OtherChannels() ~= ""
end

-- The player's channels that are not ours, as "number:name" in order ("" when none);
-- without GetChannelList: what holds slot 1
function Transport.OtherChannels()
    if type(GetChannelList) ~= "function" then
        local slotOne = tonumber((ns.Utils.SafeCall(GetChannelName, 1)))
        return (slotOne and slotOne > 0) and "1" or ""
    end
    local list = { ns.Utils.SafeCall(GetChannelList) }
    local parts = {}
    for i = 2, #list, 3 do
        local ok, other = pcall(function() return type(list[i]) == "string" and not Transport.IsOwnChannel(list[i]) end)
        if ok and other then parts[#parts + 1] = tostring(list[i - 1]) .. ":" .. list[i] end
    end
    return table.concat(parts, ",")
end

-- Join after the player's channels (General, Trade, LocalDefense, their own...), so ours
-- never takes a number of theirs: once a channel not ours is there and the list stayed the
-- same JOIN_CALM_STEPS steps (1.0.6: joined as soon as General was back, ours could take
-- /2 before LocalDefense or Trade; reported by a player 2026-11-07). A player who left
-- every server channel has none, so the wait is capped at JOIN_DEFER_MAX steps.
function Transport:JoinChannel(attempt, last, calm)
    attempt = attempt or 1
    if self:ChannelID() then
        if attempt == 1 and self:Misplaced() then
            self:LeaveOwnChannels()
        else
            self.joined = true
            ns.Events:Fire("HH_SYNC_CHANNEL_JOINED")
            return
        end
    end
    local others = self.OtherChannels()
    calm = (others ~= "" and others == last) and (calm or 0) + 1 or 0
    local settled = others ~= "" and (calm >= self.JOIN_CALM_STEPS or type(GetChannelList) ~= "function")
    if not settled and attempt <= self.JOIN_DEFER_MAX then
        C_Timer.After(self.JOIN_STEP, function() self:JoinChannel(attempt + 1, others, calm) end)
        return
    end
    self:Seat()
end

-- 1.0.6: one of ours sits below one of the player's channels (an older version took /1 and
-- /2, and the game saved its own channels behind them; seen in game 2026-11-07: gang /1,
-- ours /2, General /3, LocalDefense /5)
function Transport:Misplaced()
    local others, ours = self.HighestNumbers()
    local lowestOurs
    for _, channel in ipairs(self.Channels()) do
        if self.IsOwnChannel(channel.name) and not self.IsPad(channel.name) then
            lowestOurs = math.min(lowestOurs or channel.number, channel.number)
        end
    end
    return ours > 0 and lowestOurs ~= nil and lowestOurs < others
end

-- Our sync and gang channels, left so they can join again at the end
function Transport:LeaveOwnChannels()
    for _, channel in ipairs(self.Channels()) do
        if self.IsOwnChannel(channel.name) and not self.IsPad(channel.name) then
            pcall(LeaveChannelByName, channel.name)
        end
    end
    ns.Log:Add("info", "Sync channels were before the player's channels: joined again at the end")
end

-- 1.0.6: once per character, General back to the lowest number when the game saved it
-- behind our old channels (it rejoins into the lowest free number, and the game saves that)
function Transport:FixGeneralOnce(continue)
    local db = ns.db
    local me = ns.Utils.UnitKey("player")
    local done = db and me and type(db.channelOrderFixed) == "table" and db.channelOrderFixed[me]
    if not (db and me) or done then return continue() end
    db.channelOrderFixed = type(db.channelOrderFixed) == "table" and db.channelOrderFixed or {}
    db.channelOrderFixed[me] = true
    local general
    for _, channel in ipairs(self.Channels()) do
        if not general and not self.IsOwnChannel(channel.name) and channel.name:lower():find("^general") then general = channel end
    end
    local lowestFree = 1
    for _, channel in ipairs(self.Channels()) do
        if channel.number == lowestFree then lowestFree = lowestFree + 1 end
    end
    if not general or general.number <= lowestFree then return continue() end
    pcall(LeaveChannelByName, general.name)
    local frame = _G.DEFAULT_CHAT_FRAME
    local frameID = frame and frame.GetID and frame:GetID() or 1
    local function Back()
        for _, channel in ipairs(self.Channels()) do
            if channel.name:lower():find("^general") then return true end
        end
        return false
    end
    C_Timer.After(self.GENERAL_REJOIN_WAIT, function()
        pcall(JoinChannelByName, "General", nil, frameID)
        C_Timer.After(self.GENERAL_REJOIN_WAIT, function()
            if not Back() then pcall(JoinChannelByName, general.name, nil, frameID) end
            C_Timer.After(self.GENERAL_REJOIN_WAIT, function()
                if Back() then
                    ns.Log:Add("info", "General moved back to the lowest free number, once for this character")
                else
                    ns.Log:Add("info", "General could not be joined again after the channel order fix")
                    ns:Print(ns.L.SYNC_GENERAL_REJOIN)
                end
                continue()
            end)
        end)
    end)
end

-- Placeholders in the free numbers below the player's last channel, so ours take numbers
-- after it; returns their names
function Transport:FillHoles()
    local others = self.HighestNumbers()
    local taken = {}
    for _, channel in ipairs(self.Channels()) do taken[channel.number] = true end
    local pads = {}
    self.padSalt = self.padSalt or string.format("%05x", math.random(0, 1048575))
    for number = 1, others do
        if not taken[number] and #pads < self.PAD_MAX then
            local name = self.PAD_PREFIX .. self.padSalt .. (#pads + 1)
            pads[#pads + 1] = name
            local join = type(JoinTemporaryChannel) == "function" and JoinTemporaryChannel or JoinChannelByName
            pcall(join, name, nil, 0)
        end
    end
    return pads
end

function Transport:LeavePads(pads)
    for _, name in ipairs(pads or {}) do pcall(LeaveChannelByName, name) end
end

-- General fixed once, the holes filled, then ours join at the end; the placeholders go
-- PAD_HOLD seconds later (the gang channel joins after ours, Sync/GangChat.lua)
function Transport:Seat()
    if type(GetChannelList) ~= "function" then return self:TryJoin(0) end
    self:FixGeneralOnce(function()
        local pads = self:FillHoles()
        C_Timer.After(#pads > 0 and self.PAD_WAIT or 0, function()
            self:TryJoin(0)
            C_Timer.After(self.PAD_HOLD, function() self:LeavePads(pads) end)
        end)
    end)
end

-- frameID 0: the channel is not added to any chat window. Not joined after the retries
-- (a password on it, an account that may not use custom channels): one warning, and the
-- group and guild routes carry on (HH-150).
function Transport:TryJoin(retry)
    local join = securecall or function(fn, ...) return fn(...) end
    pcall(join, JoinChannelByName, self.CHANNEL, nil, 0, 0)
    C_Timer.After(3, function()
        self.joined = self:ChannelID() ~= nil
        ns:Debug("Sync channel", self.joined and "joined" or "NOT joined", self:ChannelID())
        if self.joined then ns.Events:Fire("HH_SYNC_CHANNEL_JOINED") end
        if self.joined or self.channelRefused then return end
        if retry < self.JOIN_RETRIES then
            C_Timer.After(self.JOIN_RETRY_DELAY, function() self:TryJoin(retry + 1) end)
        else
            self:ChannelBlocked("not joined")
        end
    end)
end

-- The channel cannot be used: said once per session, in chat and the log
function Transport:ChannelBlocked(reason)
    self.channelRefused = self.channelRefused or reason
    if self.blockedWarned then return end
    self.blockedWarned = true
    ns.Log:Add("info", "Sync channel blocked: " .. tostring(reason))
    ns:Print(ns.L.SYNC_CHANNEL_BLOCKED)
end

-- CHANNEL_PASSWORD_REQUEST: someone put a password on our channel. The first time we move
-- to BACKUP_CHANNEL (its members are who the gossip whispers); on that one too, warned.
function Transport:OnPasswordRequest(channelName)
    if type(channelName) ~= "string" or channelName:lower() ~= self.CHANNEL:lower() then return end
    if self.CHANNEL ~= self.BACKUP_CHANNEL then
        ns.Log:Add("info", "Sync channel has a password: moving to " .. self.BACKUP_CHANNEL)
        self.CHANNEL = self.BACKUP_CHANNEL
        self:TryJoin(0)
        return
    end
    self:ChannelBlocked("password")
end

-- 1.0.4: the channel carries our messages: someone else was heard there lately
function Transport:ChannelWorks()
    local at = self.channelHeardAt
    return at ~= nil and ns.Utils.Now() - at < self.HEARD_FOR
end

-- The server refuses our addon messages on the channel (the reason), or nil
function Transport:ChannelDeaf()
    return self.channelDeaf
end

function Transport:SetChannelDeaf(reason)
    if self.channelDeaf then return end
    self.channelDeaf = reason
    self.silence = nil
    ns.Log:Add("info", "Sync channel refused by the server (" .. tostring(reason) .. "): sharing by whisper")
    ns.Events:Fire("HH_SYNC_CHANNEL_CHANGED")
end

-- Someone else's message came on the channel: it works again
function Transport:HeardOnChannel()
    self.channelHeardAt = ns.Utils.Now()
    self.silence = nil
    if self.channelDeaf then
        self.channelDeaf = nil
        ns.Log:Add("info", "Sync channel works again")
        ns.Events:Fire("HH_SYNC_CHANNEL_CHANGED")
    end
end

-- A channel send the game accepted: too many of them without hearing anyone there is a
-- refusal that does not reach us
function Transport:NoteChannelSend()
    local now = ns.Utils.Now()
    local silence = self.silence
    if not silence then
        silence = { sends = 0, since = now }
        self.silence = silence
    end
    silence.sends = silence.sends + 1
    if silence.sends >= self.SILENT_SENDS and now - silence.since >= self.SILENT_FOR then
        self:SetChannelDeaf("nobody heard")
    end
end

-- CHAT_MSG_CHANNEL_NOTICE(_USER) on our channel: a refusal notice makes it deaf. The
-- arguments may be secret values, so every look at them is guarded.
function Transport:OnChannelNotice(notice, channelName, channelBaseName)
    local ok, ours = pcall(function()
        return type(notice) == "string" and self.REFUSAL_NOTICES[notice] == true
            and (IsOurChannel(channelBaseName, channelName))
    end)
    if ok and ours then self:SetChannelDeaf(notice) end
end

-------------------------------------------------
-- Sending
-------------------------------------------------

-- Enum.SendAddonMessageResult values (numbers, in case the Enum table is missing)
local RESULT = {
    [0] = "Success", [1] = "InvalidPrefix", [2] = "InvalidMessage", [3] = "AddonMessageThrottle",
    [4] = "InvalidChatType", [5] = "NotInGroup", [6] = "TargetRequired", [7] = "InvalidChannel",
    [8] = "ChannelThrottle", [9] = "GeneralError", [10] = "NotInGuild",
}
Transport.RESULT = RESULT

-- Results that will never succeed on retry for the CHANNEL route
local PERMANENT = { [1] = true, [2] = true, [4] = true, [7] = true }

local function Describe(result)
    if type(result) == "number" then
        return tostring(result) .. " (" .. (RESULT[result] or "?") .. ")"
    end
    return tostring(result)
end
Transport.DescribeResult = Describe

-- Raw send; returns ok, result. In test mode (HeadHunter_Dev noSharing, Core/Dev.lua)
-- nothing is sent, and the queue treats it as sent so it does not retry.
local function RawSend(message, chatType, target)
    if ns.Dev.NoSharing() then return true, "not sent: test mode" end
    local sender = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    local ok, result = pcall(sender, Transport.PREFIX, message, chatType, target)
    if not ok then return false, "error: " .. tostring(result) end
    -- Modern clients return an Enum.SendAddonMessageResult (0 = success); older ones
    -- return nothing or a boolean
    if result == false or (type(result) == "number" and result ~= 0) then return false, result end
    return true, result
end

local function Send(message, route)
    local ok, result = RawSend(message, route.chatType, route.target)
    Transport.diag.lastResult = route.chatType .. " " .. Describe(result)
    if not ok then
        Transport.stats.failed = Transport.stats.failed + 1
        ns:Debug("Sync send failed:", route.chatType, Describe(result))
        if route.chatType == "CHANNEL" and PERMANENT[result] then
            Transport.channelRefused = Describe(result)
        end
        return false
    end
    if route.chatType == "CHANNEL" then Transport:NoteChannelSend() end
    return true
end

-- 1.0.4: one addon whisper (Sync/Gossip.lua keeps its own budget). Returns true when the
-- game took it.
function Transport:Whisper(message, target)
    local ok, result = RawSend(message, "WHISPER", target)
    if not ok then ns:Debug("Sync whisper failed:", tostring(target), Describe(result)) end
    return ok
end

-- 1.0.4: one small message on the deaf channel every PROBE_EVERY seconds; anyone heard
-- there afterwards ends the deafness (HeardOnChannel)
function Transport:Probe()
    local channelID = self:ChannelID()
    local faction = MyFactionCode()
    if not (self.channelDeaf and channelID and faction and ns.Guards:IsActive()) then return end
    local message = ns.Protocol.Pack(faction, ns.Protocol.TYPES.PRESENCE, { ns.version })[1]
    if message then RawSend(message, "CHANNEL", channelID) end
end

-- Addon-message routes usable right now, without any player action
function Transport:AutoRoutes()
    local routes = {}
    local channelID = self:ChannelID()
    if channelID and not self.channelRefused and not self.channelDeaf then
        routes[1] = { chatType = "CHANNEL", target = channelID }
        if ns.Utils.SafeCall(IsInRaid) then
            routes[2] = { chatType = "RAID" }
        elseif ns.Utils.SafeCall(IsInGroup) then
            routes[2] = { chatType = "PARTY" }
        end
        return routes
    end
    if ns.IsEra and ns.Utils.SafeCall(IsInGuild) then
        routes[#routes + 1] = { chatType = "GUILD" }
    end
    if ns.Utils.SafeCall(IsInRaid) then
        routes[#routes + 1] = { chatType = "RAID" }
    elseif ns.Utils.SafeCall(IsInGroup) then
        routes[#routes + 1] = { chatType = "PARTY" }
    end
    return routes
end

-- True when realm-wide sending needs a click (Era)
function Transport:RealmWideNeedsClick()
    return self.channelRefused ~= nil
end

-------------------------------------------------
-- Outbox
-------------------------------------------------

function Transport:Queue(typeCode, record, priority, coalesceKey)
    if type(record) ~= "string" or record == "" then return false end
    if ns.Gossip then
        if typeCode == ns.Protocol.TYPES.QUERY and record:sub(1, 1) == "h" then
            ns.Gossip:Ask(record)
        else
            ns.Gossip:Spread(typeCode, record)
        end
    end
    local existing = coalesceKey and coalesce[coalesceKey]
    if existing then
        existing.record = record
        return true
    end
    seq = seq + 1
    local entry = { type = typeCode, record = record, priority = priority or self.PRIORITY.bulk,
        key = coalesceKey, seq = seq }
    outbox[#outbox + 1] = entry
    if coalesceKey then coalesce[coalesceKey] = entry end
    -- No route for a long time (Era, solo, no guild): keep the newest, most urgent
    if #outbox > self.MAX_OUTBOX then
        table.sort(outbox, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.seq > b.seq
        end)
        local dropped = table.remove(outbox)
        if dropped.key then coalesce[dropped.key] = nil end
    end
    return true
end

function Transport:PendingCount()
    return #outbox
end

local function Refill(now)
    lastRefill = lastRefill or now
    tokens = math.min(Transport.BURST, tokens + (now - lastRefill) * Transport.PER_SECOND)
    lastRefill = now
end

-- HH-151: the routes carried records go out on: the group, and our channel
local function RelayRoutes(channelID, refused)
    local routes = {}
    if ns.Utils.SafeCall(IsInRaid) then
        routes[#routes + 1] = { name = "GROUP", chatType = "RAID" }
    elseif ns.Utils.SafeCall(IsInGroup) then
        routes[#routes + 1] = { name = "GROUP", chatType = "PARTY" }
    end
    if channelID and not refused and not Transport.channelDeaf then
        routes[#routes + 1] = { name = "CHANNEL", chatType = "CHANNEL", target = channelID }
    end
    return routes
end

-- Carried records, while both buckets have a token: ours first (Flush), then these
local function FlushRelay(faction)
    local Bridge = ns.Bridge
    if not Bridge or Bridge.QueueCount() == 0 then return end
    local now = ns.Utils.Now()
    relayRefill = relayRefill or now
    relayTokens = math.min(Transport.RELAY_BURST, relayTokens + (now - relayRefill) * Transport.RELAY_PER_SECOND)
    relayRefill = now
    for _, route in ipairs(RelayRoutes(Transport:ChannelID(), Transport.channelRefused)) do
        while tokens >= 1 and relayTokens >= 1 do
            local records = Bridge:Take(route.name, Transport.RELAY_TAKE)
            if #records == 0 then break end
            local messages = ns.Protocol.Pack(faction, ns.Protocol.TYPES.ENVELOPE, records)
            for _, message in ipairs(messages) do
                if tokens < 1 or relayTokens < 1 then
                    Bridge.stats.dropped = Bridge.stats.dropped + 1
                elseif Send(message, route) then
                    tokens, relayTokens = tokens - 1, relayTokens - 1
                    Transport.stats.sent = Transport.stats.sent + 1
                end
            end
        end
    end
end

-- Pack and send as much of the outbox as the token bucket allows, on every route
function Transport:Flush()
    if #outbox == 0 and not (ns.Bridge and ns.Bridge.QueueCount() > 0) then
        self.diag.blocked = nil
        return
    end
    local faction = MyFactionCode()
    local routes = self:AutoRoutes()
    local names = {}
    for _, route in ipairs(routes) do names[#names + 1] = route.chatType end
    self.diag.routes = #names > 0 and table.concat(names, "+") or "none"

    if not ns.Guards:IsActive() then
        self.diag.blocked = "suspended (instance)"
    elseif not faction then
        self.diag.blocked = "faction unknown"
    elseif #routes == 0 and ns.Gossip and ns.Gossip:Active() then
        self:DropGossiped()
        self.diag.blocked = nil
        FlushRelay(faction)
        return
    elseif #routes == 0 then
        self.diag.blocked = self.channelRefused
            and ("no automatic route (channel refused: " .. self.channelRefused
                .. "; not in a guild or group) - realm-wide needs the Report button or /hh report")
            or "channel not joined"
    else
        self.diag.blocked = nil
    end
    if self.diag.blocked then return end

    table.sort(outbox, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.seq < b.seq
    end)

    Refill(ns.Utils.Now())
    -- Group consecutive records of the same type (outbox is sorted by priority) and
    -- send message by message while tokens last (one token per route); unsent
    -- records stay queued in order
    local sentUpTo = 0
    local i = 1
    while i <= #outbox and tokens >= #routes do
        local typeCode = outbox[i].type
        local records, last = {}, i
        while last <= #outbox and outbox[last].type == typeCode do
            records[#records + 1] = outbox[last].record
            last = last + 1
        end
        local messages, consumed = ns.Protocol.Pack(faction, typeCode, records)
        local groupDone = true
        for m, message in ipairs(messages) do
            if tokens < #routes then
                groupDone = false
                break
            end
            local anyOk = false
            for _, route in ipairs(routes) do
                if Send(message, route) then
                    anyOk = true
                    self.stats.sent = self.stats.sent + 1
                end
                tokens = tokens - 1
            end
            if not anyOk then
                groupDone = false
                break
            end
            -- HH-110: the others heard from us, so the next presence repeat can wait
            if typeCode ~= ns.Protocol.TYPES.PRESENCE then self.lastBroadcastAt = ns.Utils.Now() end
            self.stats.records = self.stats.records + consumed[m]
            sentUpTo = sentUpTo + consumed[m]
        end
        if not groupDone then break end
        -- Records consumed without a message (oversized) still count as handled
        sentUpTo = last - 1
        i = last
    end

    FlushRelay(faction)

    if sentUpTo > 0 then
        local remaining = {}
        for j = sentUpTo + 1, #outbox do remaining[#remaining + 1] = outbox[j] end
        for j = 1, sentUpTo do
            if outbox[j].key then coalesce[outbox[j].key] = nil end
        end
        outbox = remaining
        ns.Log:Add("debug", string.format("Sync flushed %d record(s) via %s - %d left", sentUpTo, tostring(self.diag.routes), #outbox))
    end
end

-- 1.0.4: with no automatic route, what the gossip took is not kept for a later group
function Transport:DropGossiped()
    local kept = {}
    for _, entry in ipairs(outbox) do
        local gossiped = (ns.Gossip.SPREAD[entry.type] == true) or entry.type == ns.Protocol.TYPES.QUERY
        if gossiped then
            if entry.key then coalesce[entry.key] = nil end
        else
            kept[#kept + 1] = entry
        end
    end
    outbox = kept
end

-------------------------------------------------
-- Direct: addon whispers to one player (works on both clients, no route needed)
-------------------------------------------------

-- Packs records into messages for `target`; they go out after the outbox, under the
-- same token bucket. Returns the number of messages queued.
function Transport:SendDirect(typeCode, records, target)
    local faction = MyFactionCode()
    if not faction or not target or #records == 0 then return 0 end
    local messages = ns.Protocol.Pack(faction, typeCode, records)
    local queued = 0
    for _, message in ipairs(messages) do
        if #direct >= self.MAX_DIRECT then break end
        direct[#direct + 1] = { message = message, target = target }
        queued = queued + 1
    end
    return queued
end

function Transport:DirectCount()
    return #direct
end

function Transport:FlushDirect()
    if #direct == 0 or not ns.Guards:IsActive() then return end
    Refill(ns.Utils.Now())
    while #direct > 0 and tokens >= 1 do
        local item = table.remove(direct, 1)
        -- A failed whisper (player gone offline) is dropped, never retried
        if Send(item.message, { chatType = "WHISPER", target = item.target }) then
            self.stats.sent = self.stats.sent + 1
        end
        tokens = tokens - 1
    end
end

local function ProbeLoop()
    C_Timer.After(Transport.PROBE_EVERY, function()
        local ok, err = pcall(Transport.Probe, Transport)
        if not ok then ns:Error(err) end
        ProbeLoop()
    end)
end

local function ScheduleFlush()
    local inCombat = ns.Utils.SafeCall(UnitAffectingCombat, "player")
    local delay = inCombat and Transport.COMBAT_FLUSH_INTERVAL or Transport.FLUSH_INTERVAL
    C_Timer.After(delay, function()
        local ok, err = pcall(Transport.Flush, Transport)
        if not ok then ns:Error(err) end
        -- Alerts and pings first; catch-up whispers take what the bucket has left
        ok, err = pcall(Transport.FlushDirect, Transport)
        if not ok then ns:Error(err) end
        ScheduleFlush()
    end)
end

-------------------------------------------------
-- Realm-wide chat text (Era). MUST run inside a hardware event.
-------------------------------------------------

-- Returns the number of lines sent
function Transport:SendRealmWide(typeCode, records)
    local channelID = self:ChannelID()
    local faction = MyFactionCode()
    if not channelID or not faction or #records == 0 or ns.Dev.NoSharing() then return 0 end
    local messages = ns.Protocol.Pack(faction, typeCode, records, ns.Protocol.MAX_MESSAGE - #self.CHAT_MARK)
    local sent = 0
    for i = 1, math.min(#messages, self.MAX_TEXT_MESSAGES) do
        local ok, err = pcall(SendChatMessage, self.CHAT_MARK .. messages[i], "CHANNEL", nil, channelID)
        if not ok then
            ns:Debug("Channel text send failed:", tostring(err))
            break
        end
        sent = sent + 1
        self.stats.sent = self.stats.sent + 1
    end
    return sent
end

-------------------------------------------------
-- Inbox
-------------------------------------------------

function Transport:RegisterHandler(typeCode, handler)
    handlers[typeCode] = handler
end

local processing = false

local function ProcessInbox()
    local clock = debugprofilestop
    local started = clock()
    while inboxHead <= inboxTail do
        local item = inbox[inboxHead]
        inbox[inboxHead] = nil
        inboxHead = inboxHead + 1
        local handler = handlers[item.type]
        if handler then
            local ok, err = pcall(handler, item.record, item.sender, item.faction, item.chatType)
            if not ok then ns:Error(err) end
        end
        if ns.Bridge and (item.chatType == "CHANNEL" or item.chatType == "PARTY" or item.chatType == "RAID") then
            local ok, err = pcall(ns.Bridge.Heard, ns.Bridge, item.type, item.record, item.sender, item.faction, item.chatType)
            if not ok then ns:Error(err) end
        end
        if clock() - started > Transport.INBOX_BUDGET_MS then
            C_Timer.After(0, ProcessInbox)
            return
        end
    end
    inbox, inboxHead, inboxTail = {}, 1, 0
    processing = false
end

local loggedSenderShape = false

-- Common receive path for addon messages and channel text.
-- Handlers receive the raw sender; identity checks use Utils.SameCharacter.
function Transport:Receive(message, chatType, sender)
    if not loggedSenderShape then
        -- The sender format on Forever is not documented; record the first one seen
        loggedSenderShape = true
        ns:Debug("Sync first sender shape:", tostring(sender))
    end
    if not ns.Utils.CompactName(sender) then
        self.diag.lastIgnored = "unreadable sender " .. tostring(sender)
        return
    end
    if ns.Utils.SameCharacter(sender, ns.Utils.UnitKey("player")) then return end
    if chatType == "CHANNEL" then self:HeardOnChannel() end
    if self:HeardBefore(sender, message) then
        self.stats.duplicates = (self.stats.duplicates or 0) + 1
        return
    end
    self.diag.lastSender = tostring(sender) .. " via " .. tostring(chatType)
    local faction, typeCode, records = ns.Protocol.Unpack(message)
    if not faction then
        self.stats.dropped = self.stats.dropped + 1
        self.diag.lastIgnored = "unparseable message from " .. tostring(sender)
        return
    end
    -- Other-faction traffic can share a custom channel; it is never ours to trust,
    -- except duel records (High Noon lists both factions; they never touch WANTED),
    -- pings (the manual test, HH-100: does anything cross factions?) and presence
    -- (HH-110: the online count per faction). Their bounty payments are not taken any
    -- more (HH-121, author 2026-10-02): a Deadbeat needs a verified claim, and their
    -- posters and witnesses never reach us; their Deadbeats come from the website.
    local TYPES = ns.Protocol.TYPES
    if chatType == "WHISPER" and ns.Gossip then
        ns.Gossip:Heard(sender, faction, nil, typeCode == TYPES.PRESENCE)
    end
    -- HH-110: any message shows its sender is online, not only a presence one
    ns.Presence:Heard(sender, faction, typeCode == TYPES.PRESENCE and records[1] or nil, self.ServerOf(sender, chatType))
    if faction ~= ns.Utils.UnitFaction("player") then
        self.stats.crossFaction = (self.stats.crossFaction or 0) + 1
        ns:Debug("Other faction (" .. faction .. ") message from", tostring(sender), "via", tostring(chatType),
            "type", tostring(typeCode))
        if typeCode ~= TYPES.DUEL and typeCode ~= TYPES.PING and typeCode ~= TYPES.PRESENCE then
            self.diag.lastIgnored = "other faction (" .. faction .. ") from " .. tostring(sender)
            return
        end
    end
    for _, record in ipairs(records) do
        inboxTail = inboxTail + 1
        inbox[inboxTail] = { type = typeCode, record = record, sender = sender, faction = faction, chatType = chatType }
        self.stats.received = self.stats.received + 1
    end
    if not processing then
        processing = true
        C_Timer.After(0, ProcessInbox)
    end
end

-- The same message from the same sender within DUPLICATE_WINDOW (sent on the channel and
-- to the group): true the second time. Old entries go every DUPLICATE_WINDOW.
local heard, heardPrunedAt = {}, 0
function Transport:HeardBefore(sender, message)
    local now = ns.Utils.Now()
    if now - heardPrunedAt >= self.DUPLICATE_WINDOW then
        for key, at in pairs(heard) do
            if now - at >= self.DUPLICATE_WINDOW then heard[key] = nil end
        end
        heardPrunedAt = now
    end
    local key = tostring(ns.Utils.CompactName(sender) or sender) .. "\0" .. message
    local at = heard[key]
    heard[key] = now
    return at ~= nil and now - at < self.DUPLICATE_WINDOW
end

-- HH-151: the home server of a sender, when the route tells it: our channel is our
-- server's, a group member's comes from their GUID
function Transport.ServerOf(sender, chatType)
    if chatType == "CHANNEL" then return ns.Utils.PlayerServer() end
    if (chatType == "PARTY" or chatType == "RAID") and ns.Bridge then return ns.Bridge.GroupServer(sender) end
    return nil
end

-- HH-151: a record carried for its author, handled as if they had sent it (inbox budget)
function Transport:Dispatch(typeCode, record, sender, faction, chatType)
    inboxTail = inboxTail + 1
    inbox[inboxTail] = { type = typeCode, record = record, sender = sender, faction = faction, chatType = chatType }
    if not processing then
        processing = true
        C_Timer.After(0, ProcessInbox)
    end
end

function Transport:OnAddonMessage(prefix, message, chatType, sender)
    if prefix ~= self.PREFIX then return end
    self:Receive(message, chatType, sender)
end

-- CHAT_MSG_CHANNEL: text, sender, language, channelName, target, flags,
-- zoneChannelID, channelIndex, channelBaseName
function Transport:OnChannelText(text, sender, _, channelName, _, _, _, _, channelBaseName)
    if not IsOurChannel(channelBaseName, channelName) or type(text) ~= "string" then return end
    if text:sub(1, #self.CHAT_MARK) ~= self.CHAT_MARK then return end
    local body = text:sub(#self.CHAT_MARK + 1)
    if body:sub(1, 5) == "test " then
        -- /hh sync chat
        if not ns.Utils.SameCharacter(sender, ns.Utils.UnitKey("player")) then
            ns:Print(string.format(ns.L.SYNC_CHAT_RECEIVED, tostring(sender), body))
        end
        return
    end
    self:Receive(body, "CHANNELTEXT", sender)
end

-------------------------------------------------
-- Wiring
-------------------------------------------------

ns.Events:Register("HH_INITIALIZED", function()
    local Events = ns.Events
    -- Known from the in-game probe: skip the doomed first attempt on Era
    if ns.IsEra then
        Transport.channelRefused = "4 (InvalidChatType) on Classic Era"
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(Transport.PREFIX)
    end
    InstallChatFilters()
    Events:Register("CHAT_MSG_ADDON", function(_, ...) Transport:OnAddonMessage(...) end, OWNER)
    Events:Register("CHAT_MSG_CHANNEL", function(_, ...) Transport:OnChannelText(...) end, OWNER)
    pcall(Events.Register, Events, "CHANNEL_PASSWORD_REQUEST", function(_, name) Transport:OnPasswordRequest(name) end, OWNER)
    for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
        pcall(Events.Register, Events, event, function(_, notice, _, _, channelName, _, _, _, _, channelBaseName)
            Transport:OnChannelNotice(notice, channelName, channelBaseName)
        end, OWNER .. event)
    end
    Events:Register("PLAYER_ENTERING_WORLD", function()
        if not Transport.joinStarted then
            Transport.joinStarted = true
            Transport:JoinChannel()
        end
    end, OWNER)
    Transport:RegisterHandler(ns.Protocol.TYPES.PING, function(record, sender, faction, chatType)
        -- Manual connectivity test: shown in chat because the player asked for it
        ns:Print(string.format(ns.L.SYNC_PING_RECEIVED, tostring(sender), tostring(faction), tostring(record),
            tostring(chatType)))
    end)
    ScheduleFlush()
    if not ns.IsEra then ProbeLoop() end
end, OWNER)

-------------------------------------------------
-- /hh sync
-------------------------------------------------

-- /hh sync probe: which chat types does this client accept for addon messages?
function Transport:ProbeChatTypes()
    local faction = MyFactionCode() or "A"
    local me = ns.Utils.UnitName("player")
    local routes = {
        { "CHANNEL", self:ChannelID() },
        { "GUILD" }, { "PARTY" }, { "RAID" }, { "SAY" }, { "YELL" },
        { "WHISPER", me },
    }
    for _, route in ipairs(routes) do
        local chatType, target = route[1], route[2]
        local message = ns.Protocol.Header(faction, ns.Protocol.TYPES.PING) .. "probe " .. chatType
        local ok, result = RawSend(message, chatType, target)
        ns:Print(string.format(ns.L.SYNC_PROBE_LINE, chatType, ok and "accepted" or "refused", Describe(result)))
    end
end

ns.SlashCommands:Register("sync", function(args)
    local sub = args[1] and args[1]:lower()
    if sub == "chat" then
        local channelID = Transport:ChannelID()
        if not channelID then
            ns:Print(ns.L.SYNC_CHAT_NO_CHANNEL)
            return
        end
        local ok, err = pcall(SendChatMessage, Transport.CHAT_MARK .. "test " .. date("%H:%M:%S"), "CHANNEL", nil, channelID)
        ns:Print(ok and ns.L.SYNC_CHAT_SENT or string.format(ns.L.SYNC_CHAT_FAILED, tostring(err)))
        return
    end
    if sub == "probe" then
        Transport:ProbeChatTypes()
        return
    end
    -- /hh sync whisper "<name>": an addon whisper ping (HH-100: can it cross factions?)
    -- /hh sync gossip "<name>": the same ping, in a gossip envelope (1.0.4)
    if sub == "gossip" then
        local target = args[2]
        if not target or not ns.Gossip:Test(target) then
            ns:Print(ns.L.SYNC_WHISPER_USAGE)
            return
        end
        ns:Print(string.format(ns.L.SYNC_WHISPER_QUEUED, target))
        return
    end
    if sub == "whisper" then
        local target = args[2]
        if not target then
            ns:Print(ns.L.SYNC_WHISPER_USAGE)
            return
        end
        Transport:SendDirect(ns.Protocol.TYPES.PING, { "whisper " .. date("%H:%M:%S") }, target)
        ns:Print(string.format(ns.L.SYNC_WHISPER_QUEUED, target))
        return
    end
    if sub == "ping" then
        Transport:Queue(ns.Protocol.TYPES.PING, date("%H:%M:%S"), Transport.PRIORITY.alert, "ping")
        ns:Print(ns.L.SYNC_PING_QUEUED)
        return
    end
    local s, d = Transport.stats, Transport.diag
    local channelID = Transport:ChannelID()
    local channelState = channelID and ("joined #" .. channelID) or "not joined"
    local refusal = Transport.channelRefused or Transport.channelDeaf
    if channelID and refusal then
        channelState = channelState .. " (" .. string.format(ns.L.SYNC_CHANNEL_DEAF, refusal) .. ")"
    end
    ns:Print(string.format(ns.L.SYNC_STATUS, channelState,
        #outbox, s.sent, s.records, s.received, s.dropped, s.failed))
    local routes = {}
    for _, route in ipairs(Transport:AutoRoutes()) do routes[#routes + 1] = route.chatType end
    ns:Print(string.format(ns.L.SYNC_DIAG, tostring(ns.Utils.UnitFaction("player")),
        #routes > 0 and table.concat(routes, "+") or "none",
        d.blocked or "no", tostring(d.lastResult), tostring(d.lastSender), tostring(d.lastIgnored)))
    local B = ns.Bridge
    if B then
        local servers = {}
        for _, server in pairs(B.GroupServers()) do servers[server] = true end
        servers[ns.Utils.PlayerServer() or 0] = nil
        local others = 0
        for _ in pairs(servers) do others = others + 1 end
        ns:Print(string.format(ns.L.SYNC_RELAY, B.Enabled() and "on" or "off", B.World(), others,
            B.stats.forwarded, B.stats.delivered, B.stats.duplicates, B.stats.skipped, B.stats.dropped,
            B.stats.refused, B.QueueCount(), B.SeenCount(), B.stats.links))
    end
    local G = ns.Gossip
    if G and G.Enabled() then
        local reachable, ours = G:Reachable()
        local gs = G.stats
        ns:Print(string.format(ns.L.SYNC_GOSSIP, G:Active() and "on" or "off", G:PeerCount(), reachable, ours, G:KnownCount(),
            gs.spread, gs.passed, gs.sent, gs.failed, gs.dropped, gs.unreachable, G:QueueCount()))
    end
    local rejected = ns.Reports and ns.Reports.lastRejected
    if rejected then ns:Print(string.format(ns.L.SYNC_REJECTED, rejected)) end
end, ns.L.HELP_SYNC)
