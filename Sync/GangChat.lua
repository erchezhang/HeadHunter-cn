-- HH-155: gang chat, like guild chat. The website gives each gang a hidden game chat
-- channel with a password and sends both only to its members (the download's
-- characters[...].gang_chat). We join it and it is an ordinary chat channel: shown in the
-- main chat window the first time (the game's chat settings move it to any window or tab),
-- its lines labelled "[Gang]" by a chat filter, its sticky chat box (/<number> + space) with
-- the header "Gang:", in the gang chat colour. /gang <text> sends; /gang alone opens the
-- chat box on gang chat. The chat box's chat type is never set from our code (that taints
-- protected commands typed in chat). A gang's channel changes when a member is kicked; any
-- other HHG channel we are in is left. WoW Forever only, once the website confirmed the gang.

local addonName, ns = ...
local L = ns.L

local GangChat = ns:RegisterModule("GangChat", {})

local OWNER = "GangChat"

GangChat.PREFIX = "HHG"
-- seconds after login before joining, so the game's own channels take the first slots
GangChat.JOIN_DELAY = 12
GangChat.DEFAULT_COLOR = "ff9f40"

local current
-- player key -> { online = true (joined or spoke in the gang channel) or false (left it), t }
local presence = {}

-- The channel and password the website sent for our character, or nil
function GangChat.Credentials()
    if not ns.Gangs.Enabled() then return nil end
    return ns.SiteData:GangChat(ns.Utils.UnitKey("player"))
end

local function OurChannel(channelBaseName, channelName)
    local name = channelBaseName ~= "" and channelBaseName or (type(channelName) == "string" and channelName:match("^%d+%. (.+)$"))
    return current ~= nil and name == current
end

local function ChannelId(name)
    local id = name and tonumber((ns.Utils.SafeCall(GetChannelName, name)))
    return id and id > 0 and id or nil
end

local function IsGangChannel(name)
    return type(name) == "string" and name:sub(1, #GangChat.PREFIX) == GangChat.PREFIX
end

-- The first time we are in a gang channel it goes to the main chat window; after that the
-- player's own chat settings decide where it shows
local function ShowInMainWindow(name)
    if not ns.db or ns.db.settings.gangChatShown == name then return end
    local window = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    if window then
        if window.AddChannel then
            pcall(window.AddChannel, window, name)
        elseif ChatFrame_AddChannel then
            pcall(ChatFrame_AddChannel, window, name)
        end
    end
    ns.Database:SetSetting("gangChatShown", name)
end

-- The gang chat colour on the channel's own chat colour
local function PaintChannel(name)
    local id = ChannelId(name)
    if id and ChangeChatColor then pcall(ChangeChatColor, "CHANNEL" .. id, GangChat.Color()) end
end

-- Old gang channels we are still in (a kick moved the gang, or we left it)
local function LeaveOthers(keep)
    if not GetChannelList then return end
    local list = { ns.Utils.SafeCall(GetChannelList) }
    for i = 2, #list, 3 do
        local name = list[i]
        if IsGangChannel(name) and name ~= keep then pcall(LeaveChannelByName, name) end
    end
end

function GangChat:Join()
    local chat = self.Credentials()
    LeaveOthers(chat and chat.channel)
    if not chat then
        current = nil
        return false
    end
    current = chat.channel
    if not ChannelId(chat.channel) then
        local join = securecall or function(fn, ...) return fn(...) end
        pcall(join, JoinChannelByName, chat.channel, chat.password, 0, 0)
    end
    ShowInMainWindow(chat.channel)
    PaintChannel(chat.channel)
    return true
end

function GangChat:Leave()
    if current then pcall(LeaveChannelByName, current) end
    current = nil
end

function GangChat:Channel()
    return current
end

-- What the gang channel last told us of a player: { online, t (Utils.Now()) } or nil
function GangChat:Seen(key)
    for name, state in pairs(presence) do
        if ns.Utils.SameCharacter(name, key) then return state end
    end
    return nil
end

function GangChat:OnJoinLeave(joined, sender, channelBaseName, channelName)
    if not OurChannel(channelBaseName, channelName) then return end
    local key = ns.Utils.PlayerKey(sender)
    if not key then return end
    presence[key] = { online = joined, t = ns.Utils.Now() }
    ns.Events:Fire("HH_GANG_CHANGED")
end

-- "ff9f40" -> r, g, b (0..1)
function GangChat.Color()
    local hex = ns.db and ns.db.settings.gangChatColor or GangChat.DEFAULT_COLOR
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then hex = GangChat.DEFAULT_COLOR end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function GangChat.SetColor(hex)
    hex = type(hex) == "string" and hex:gsub("^#", ""):lower() or ""
    if not hex:match("^%x%x%x%x%x%x$") then return false end
    ns.Database:SetSetting("gangChatColor", hex)
    if current then PaintChannel(current) end
    return true
end

-- A line in our channel: its sender spoke, so they are online
function GangChat:OnChannelText(text, sender, channelBaseName, channelName)
    if not OurChannel(channelBaseName, channelName) or type(text) ~= "string" then return end
    local key = ns.Utils.PlayerKey(sender)
    if key then presence[key] = { online = true, t = ns.Utils.Now() } end
end

-- Chat filter: our channel's lines say "[Gang]" instead of "[6. HHGxk3...]"; its join and
-- leave notices are not shown
function GangChat.LabelFilter(_, _, text, sender, language, channelName, target, flags, zoneId, index, baseName, ...)
    if not OurChannel(baseName or "", channelName) then return false end
    return false, text, sender, language, L.TAB_GANG, target, flags, zoneId, index, L.TAB_GANG, ...
end

function GangChat.NoticeFilter(_, _, _, _, _, channelName, _, _, _, _, baseName)
    return OurChannel(baseName or "", channelName)
end

-- The sticky chat box on our channel says "Gang:" (a post-hook on Blizzard's header update;
-- only the header's text and the box's insets change, never its chat type)
function GangChat.OnHeaderUpdate(editBox)
    if not (editBox and editBox.GetAttribute and current) then return end
    if editBox:GetAttribute("chatType") ~= "CHANNEL" or tonumber(editBox:GetAttribute("channelTarget")) ~= ChannelId(current) then
        return
    end
    local header = editBox.header or (editBox.GetName and editBox:GetName() and _G[editBox:GetName() .. "Header"])
    if not (header and header.SetText) then return end
    header:SetText(L.GANG_CHAT_HEADER)
    header:SetTextColor(GangChat.Color())
    if editBox.SetTextInsets and header.GetWidth then
        local _, right, top, bottom = editBox:GetTextInsets()
        editBox:SetTextInsets(15 + header:GetWidth(), right or 13, top or 0, bottom or 0)
    end
end

-- /gang <text> sends to gang chat; /gang alone opens the chat box on it, as /<number> would
function GangChat:Send(text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local id = ChannelId(current)
    if not id then ns:Print(L.GANG_CHAT_NONE) return false end
    if text == "" then
        if ChatFrame_OpenChat then ChatFrame_OpenChat("/" .. id .. " ") else ns:Print(L.GANG_CHAT_USAGE) end
        return false
    end
    SendChatMessage(text, "CHANNEL", nil, id)
    return true
end

_G.SLASH_HEADHUNTERGANGCHAT1 = "/gang"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList.HEADHUNTERGANGCHAT = function(text) GangChat:Send(text) end

ns.Events:Register("HH_INITIALIZED", function()
    ns.Events:Register("CHAT_MSG_CHANNEL", function(_, text, sender, _, channelName, _, _, _, _, channelBaseName)
        GangChat:OnChannelText(text, sender, channelBaseName, channelName)
    end, OWNER)
    ns.Events:Register("CHAT_MSG_CHANNEL_JOIN", function(_, _, sender, _, channelName, _, _, _, _, channelBaseName)
        GangChat:OnJoinLeave(true, sender, channelBaseName, channelName)
    end, OWNER)
    ns.Events:Register("CHAT_MSG_CHANNEL_LEAVE", function(_, _, sender, _, channelName, _, _, _, _, channelBaseName)
        GangChat:OnJoinLeave(false, sender, channelBaseName, channelName)
    end, OWNER)
    ns.Events:Register("HH_GANG_CHANGED", function(_, action)
        if action and action.kind == "leave" then GangChat:Leave() end
    end, OWNER)
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then
        pcall(add, "CHAT_MSG_CHANNEL", GangChat.LabelFilter)
        for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN",
                "CHAT_MSG_CHANNEL_LEAVE" }) do
            pcall(add, event, GangChat.NoticeFilter)
        end
    end
    if hooksecurefunc and _G.ChatEdit_UpdateHeader then hooksecurefunc("ChatEdit_UpdateHeader", GangChat.OnHeaderUpdate) end
    C_Timer.After(GangChat.JOIN_DELAY, function() GangChat:Join() end)
end, OWNER)
