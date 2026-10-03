-- HH-020: silent, batched, asynchronous transport.
-- Principles: docs/addon/tickets.md M2 "Sync principles" and features.md section 7.
--
--   Transport:Queue(typeCode, record, priority, coalesceKey)
--   Transport:RegisterHandler(typeCode, function(record, sender, faction, chatType) end)
--   Transport:SendRealmWide(typeCode, records)   -- Era: only from a click / typed command
--   Transport:SendDirect(typeCode, records, target) -- addon whispers to one player (catch-up)
--
-- Automatic routes (addon messages, no player action needed), chosen per flush:
--   Forever: the hidden channel HeadHunterSync (realm/region wide)
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
Transport.CHAT_MARK = "HH1:"     -- marks our lines in channel chat text

Transport.FLUSH_INTERVAL = 3
Transport.COMBAT_FLUSH_INTERVAL = 10
Transport.BURST = 4          -- messages that may go out back to back
Transport.PER_SECOND = 1     -- sustained messages per second
Transport.INBOX_BUDGET_MS = 3
Transport.JOIN_DEFER_MAX = 15 -- x 2 s waiting for the server channels to take /1
Transport.MAX_OUTBOX = 200    -- records kept while no route is available
Transport.MAX_TEXT_MESSAGES = 2 -- channel text lines sent per click
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

-- Chat filter args: self, event, text, playerName, languageName, channelName ("5. Name"),
-- playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, ...

-- Hide our channel's join/leave/notice lines
local function ChannelNoticeFilter(_, _, _, _, _, channelName, _, _, _, _, channelBaseName)
    return IsOurChannel(channelBaseName, channelName)
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

-- Join after the server channels (General, Trade...) so ours never takes /1.
-- A player who left every server channel keeps slot 1 empty forever, so the wait
-- is capped.
function Transport:JoinChannel(attempt)
    attempt = attempt or 1
    if self:ChannelID() then
        self.joined = true
        return
    end
    -- GetChannelName returns id, name, ...: keep only the id (a second argument to
    -- tonumber would be taken as the number base)
    local slotOne = tonumber((ns.Utils.SafeCall(GetChannelName, 1)))
    if (not slotOne or slotOne == 0) and attempt <= self.JOIN_DEFER_MAX then
        C_Timer.After(2, function() self:JoinChannel(attempt + 1) end)
        return
    end
    -- frameID 0: the channel is not added to any chat window
    local join = securecall or function(fn, ...) return fn(...) end
    pcall(join, JoinChannelByName, self.CHANNEL, nil, 0, 0)
    C_Timer.After(3, function()
        self.joined = self:ChannelID() ~= nil
        ns:Debug("Sync channel", self.joined and "joined" or "NOT joined", self:ChannelID())
    end)
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
    return true
end

-- Addon-message routes usable right now, without any player action
function Transport:AutoRoutes()
    local routes = {}
    local channelID = self:ChannelID()
    if channelID and not self.channelRefused then
        routes[1] = { chatType = "CHANNEL", target = channelID }
        return routes
    end
    if ns.Utils.SafeCall(IsInGuild) then
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

-- Pack and send as much of the outbox as the token bucket allows, on every route
function Transport:Flush()
    if #outbox == 0 then
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

    if sentUpTo > 0 then
        local remaining = {}
        for j = sentUpTo + 1, #outbox do remaining[#remaining + 1] = outbox[j] end
        for j = 1, sentUpTo do
            if outbox[j].key then coalesce[outbox[j].key] = nil end
        end
        outbox = remaining
        ns:Debug("Sync flushed", sentUpTo, "record(s) via", self.diag.routes, "-", #outbox, "left")
    end
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
    -- HH-110: any message shows its sender is online, not only a presence one
    ns.Presence:Heard(sender, faction, typeCode == TYPES.PRESENCE and records[1] or nil)
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
    ns:Print(string.format(ns.L.SYNC_STATUS, channelID and ("joined #" .. channelID) or "not joined",
        #outbox, s.sent, s.records, s.received, s.dropped, s.failed))
    local routes = {}
    for _, route in ipairs(Transport:AutoRoutes()) do routes[#routes + 1] = route.chatType end
    ns:Print(string.format(ns.L.SYNC_DIAG, tostring(ns.Utils.UnitFaction("player")),
        #routes > 0 and table.concat(routes, "+") or "none",
        d.blocked or "no", tostring(d.lastResult), tostring(d.lastSender), tostring(d.lastIgnored)))
    local rejected = ns.Reports and ns.Reports.lastRejected
    if rejected then ns:Print(string.format(ns.L.SYNC_REJECTED, rejected)) end
end, ns.L.HELP_SYNC)
