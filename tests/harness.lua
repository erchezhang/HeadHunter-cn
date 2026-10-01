-- Offline harness: stubs just enough of the WoW API to load the real addon files
-- (in TOC order) under a chosen client, fire events at them and inspect the result.
-- Never loaded by the game (tests/ is not in the TOC).

local H = {}

local ROOT = assert(arg and arg[1], "usage: lua5.1 tests/run.lua <addon root>")
H.ROOT = ROOT

local CLIENTS = {
    era = { iface = 11509, project = 2 },
    -- Forever reports WOW_PROJECT_ID 1 (mainline); probe 2026-09-23, build 1.60.1.69913
    forever = { iface = 16001, project = 1 },
}
H.CLIENTS = CLIENTS

-------------------------------------------------
-- Frames
-------------------------------------------------

local frames

local function NoOp() end

local function NewFrame(name)
    local frame = { registered = {}, scripts = {}, shown = false, name = name }
    function frame:RegisterEvent(event)
        if H.removedEvents[event] then
            error("Attempt to register unknown event \"" .. event .. "\"")
        end
        -- The real client does not raise here: it blocks the call and reports
        -- ADDON_ACTION_FORBIDDEN, which pcall cannot catch. Record it instead.
        if H.protectedEvents[event] then
            H.forbidden[#H.forbidden + 1] = "RegisterEvent(" .. event .. ")"
            return
        end
        self.registered[event] = true
    end
    function frame:UnregisterEvent(event) self.registered[event] = nil end
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:GetScript(script) return self.scripts[script] end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:CreateFontString() return NewFrame() end
    function frame:CreateTexture() return NewFrame() end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    -- rawget: a missing field would otherwise be the no-op method below
    function frame:GetFrameLevel() return rawget(self, "frameLevel") or 0 end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:GetFrameStrata() return rawget(self, "strata") or "MEDIUM" end
    -- frame.children: other frames on this one (a test adds other addons' map pins)
    function frame:GetChildren() return unpack(rawget(self, "children") or {}) end
    function frame:SetScale(scale) self.scale = scale end
    function frame:GetScale() return rawget(self, "scale") or 1 end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetTexture(texture) self.texture = texture end
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function frame:SetText(text) self.shownText = text end
    function frame:GetVerticalScrollRange() return 0 end
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    -- Any other widget method is a harmless no-op
    return setmetatable(frame, { __index = function() return NoOp end })
end

-- World map stand-in: a canvas (ScrollContainer.Child) plus the script hooks the
-- addon adds. map:Open(mapID) / map:Close() drive it like a player would.
local function NewWorldMap()
    local map = NewFrame()
    map.hooks = {}
    function map:HookScript(script, fn) self.hooks[script] = fn end
    function map:SetMapID(mapID) self.mapID = mapID end
    function map:Open(mapID)
        self.shown = true
        if self.hooks.OnShow then self.hooks.OnShow(self) end
        if mapID then self:SetMapID(mapID) end
    end
    function map:Close()
        self.shown = false
        if self.hooks.OnHide then self.hooks.OnHide(self) end
    end
    local canvas = NewFrame()
    function canvas:GetWidth() return 1000 end
    function canvas:GetHeight() return 700 end
    map.ScrollContainer = { Child = canvas }
    return map
end
H.NewWorldMap = NewWorldMap

-- Every frame created since the last Install
function H.AllFrames()
    return frames
end

-------------------------------------------------
-- Environment
-------------------------------------------------

-- Replaces every stubbed global. opts.client = "era" | "forever" | custom
-- { iface = n, project = n }.
-- opts.playerGUID sets our GUID (WoW Forever: its server number tells the realm).
function H.Install(opts)
    opts = opts or {}
    local client = type(opts.client) == "table" and opts.client or CLIENTS[opts.client or "era"]

    frames = {}
    H.printed = {}
    H.errors = {}
    H.timers = {}
    H.clock = 1000
    H.serverTime = 1780000000
    H.realm = "Firemaw"
    H.instance = { false, "none" }
    H.removedEvents = {}
    H.protectedEvents = {}
    H.forbidden = {}
    if client == CLIENTS.forever then
        H.protectedEvents.COMBAT_LOG_EVENT_UNFILTERED = true
    end
    H.units = {
        player = {
            name = client == CLIENTS.forever and "Vati Guda" or "Vati",
            level = 30, class = "ROGUE", race = "Human", sex = 2,
            guid = opts.playerGUID or "Player-1-00000001", faction = "Alliance", isPlayer = true,
        },
    }
    H.maps = {
        [1429] = { mapID = 1429, name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
        [1436] = { mapID = 1436, name = "Westfall", mapType = 3, parentMapID = 1415 },
        [1434] = { mapID = 1434, name = "Stranglethorn Vale", mapType = 3, parentMapID = 1415 },
        [1417] = { mapID = 1417, name = "Arathi Highlands", mapType = 3, parentMapID = 1415 },
        [1413] = { mapID = 1413, name = "The Barrens", mapType = 3, parentMapID = 1414 },
        [9001] = { mapID = 9001, name = "Jasperlode Mine", mapType = 5, parentMapID = 1429 },
        [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
        [1414] = { mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 947 },
        [947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 },
    }
    H.waypoints = {}
    H.noWaypoints = false
    _G.UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, x = x, y = y } end }
    _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
    H.playerMap = 1429
    H.playerX, H.playerY = 0.42, 0.65
    H.gameTime = { 13, 0 }           -- realm clock (GetGameTime): hours, minutes
    _G.GetGameTime = function() return H.gameTime[1], H.gameTime[2] end

    _G.HeadHunter_DB = opts.savedDB
    _G.HeadHunter_SiteData = opts.siteData
    _G.HeadHunter_Dev = opts.dev
    _G.SLASH_HEADHUNTER1, _G.SLASH_HEADHUNTER2 = nil, nil
    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.UIParent = NewFrame()
    _G.ChatFontNormal = {}
    _G.BackdropTemplateMixin = nil
    _G.canaccessvalue = nil
    _G.issecretvalue = nil
    _G.tinsert = table.insert
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.strsplit = function(sep, s)
        local out, pos = {}, 1
        while true do
            local i = s:find(sep, pos, true)
            if not i then out[#out + 1] = s:sub(pos) break end
            out[#out + 1] = s:sub(pos, i - 1)
            pos = i + 1
        end
        return unpack(out)
    end
    _G.C_NamePlate = nil

    -- Chat channels and addon messages (Sync)
    H.channels = { General = 1 }     -- name -> channel id; slot 1 holds General
    H.joinWorks = true
    H.sent = {}                      -- { prefix, message, chatType, target } (accepted sends)
    H.attempts = {}                  -- every send attempt { chatType, result }
    H.sendResults = {}
    H.chatFilters = {}
    H.inCombat = false
    H.profileStep = 0                -- ms added per debugprofilestop() call
    H.profileNow = 0
    _G.securecall = function(fn, ...) return fn(...) end
    _G.GetChannelName = function(id)
        if type(id) == "number" then
            for name, channelID in pairs(H.channels) do
                if channelID == id then return channelID, name end
            end
            return 0
        end
        return H.channels[id] or 0
    end
    _G.JoinChannelByName = function(name)
        if H.joinWorks then H.channels[name] = 5 end
    end
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        -- H.sendResults[chatType] overrides the result (Era: CHANNEL -> 4 InvalidChatType)
        SendAddonMessage = function(prefix, message, chatType, target)
            local result = H.sendResults[chatType] or 0
            H.attempts[#H.attempts + 1] = { chatType = chatType, result = result }
            if result ~= 0 then return result end
            H.sent[#H.sent + 1] = { prefix = prefix, message = message, chatType = chatType, target = target }
            return 0
        end,
    }
    _G.ChatFrame_AddMessageEventFilter = function(event, fn) H.chatFilters[event] = fn end
    -- Guild / group state (Era automatic routes)
    H.inGuild, H.inRaid, H.inGroup = false, false, false
    _G.IsInGuild = function() return H.inGuild end
    _G.IsInRaid = function() return H.inRaid end
    _G.IsInGroup = function() return H.inGroup or H.inRaid end

    -- Alert output
    H.centerTexts, H.sounds = {}, {}
    _G.RaidWarningFrame = {}
    _G.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
    _G.RaidNotice_AddMessage = function(_, text) H.centerTexts[#H.centerTexts + 1] = text end
    _G.PlaySound = function(kit, channel) H.sounds[#H.sounds + 1] = kit end
    _G.SOUNDKIT = nil
    _G.OKAY, _G.CANCEL = "Okay", "Cancel"

    -- StaticPopup: H.popups records every StaticPopup_Show
    H.popups = {}
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which, _, _, data)
        H.popups[#H.popups + 1] = { which = which, text = _G.StaticPopupDialogs[which].text, data = data }
    end
    _G.StaticPopup_Hide = function() end

    H.chatSent = {}
    _G.SendChatMessage = function(text, chatType, language, target)
        H.chatSent[#H.chatSent + 1] = { text = text, chatType = chatType, target = target }
    end
    _G.UnitAffectingCombat = function(unit)
        local u = H.units[unit]
        if u and unit ~= "player" and u.inCombat ~= nil then return u.inCombat end
        return H.inCombat
    end
    -- The duel challenge (unit menu, /duel); Sync/Duels.lua hooks it
    H.duelsStarted = {}
    _G.StartDuel = function(who) H.duelsStarted[#H.duelsStarted + 1] = who end
    _G.debugprofilestop = function() H.profileNow = H.profileNow + H.profileStep; return H.profileNow end

    -- Combat log (Era): H.FireCLEU sets the current event
    H.cleu = {}
    -- Death recap (Forever): nil = no recap, otherwise a list of recap events
    H.recap = nil

    _G.WOW_PROJECT_CLASSIC = 2
    _G.WOW_PROJECT_MAINLINE = 1
    _G.WOW_PROJECT_ID = client.project
    _G.GetBuildInfo = function() return "1.0.0", "00000", "Jan 1 2026", client.iface end
    _G.C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
    _G.CombatLogGetCurrentEventInfo = (client ~= CLIENTS.forever)
        and function() return unpack(H.cleu, 1, H.cleu.n or #H.cleu) end or nil
    _G.C_EventUtils = nil
    _G.C_DeathRecap = (client == CLIENTS.forever) and {
        HasRecapEvents = function() return H.recap ~= nil and #H.recap > 0 end,
        GetRecapEvents = function() return H.recap end,
        GetRecapMaxHealth = function() return 100 end,
        GetRecapLink = function() return "[You died.]" end,
    } or nil

    _G.CreateFrame = function(_, name) return NewFrame(name) end
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        H.printed[#H.printed + 1] = table.concat(parts, " ")
    end
    _G.geterrorhandler = function()
        return function(err) H.errors[#H.errors + 1] = tostring(err) end
    end
    _G.date = os.date
    _G.time = os.time
    _G.GetTime = function() return H.clock end
    _G.GetServerTime = function() return H.serverTime end
    _G.C_Timer = {
        After = function(delay, fn) H.timers[#H.timers + 1] = { at = H.clock + delay, fn = fn } end,
    }
    _G.bit = {
        band = function(a, b)
            local result, bitValue = 0, 1
            while a > 0 and b > 0 do
                if a % 2 == 1 and b % 2 == 1 then result = result + bitValue end
                a, b, bitValue = math.floor(a / 2), math.floor(b / 2), bitValue * 2
            end
            return result
        end,
    }

    local function Unit(unit) return H.units[unit] end
    _G.UnitExists = function(unit) return Unit(unit) ~= nil end
    -- u.realm is UnitName's second value. On Forever that is the family name for
    -- other players; u.guidRealm is what GetPlayerInfoByGUID reports.
    _G.UnitName = function(unit) local u = Unit(unit); if u then return u.name, u.realm end end
    _G.GetUnitName = function(unit) local u = Unit(unit); return u and (u.fullName or u.name) end
    _G.UnitFullName = function(unit) local u = Unit(unit); if u then return u.name, u.realm end end
    _G.UnitLevel = function(unit) local u = Unit(unit); return u and u.level or 0 end
    _G.UnitClass = function(unit) local u = Unit(unit); if u then return u.class, u.class end end
    _G.UnitRace = function(unit) local u = Unit(unit); if u then return u.race, u.race end end
    _G.UnitSex = function(unit) local u = Unit(unit); return u and u.sex end
    _G.UnitHealth = function(unit) local u = Unit(unit); return u and (u.health or 100) end
    _G.UnitGUID = function(unit) local u = Unit(unit); return u and u.guid end
    _G.UnitFactionGroup = function(unit) local u = Unit(unit); if u then return u.faction, u.faction end end
    _G.UnitIsPlayer = function(unit) local u = Unit(unit); return u ~= nil and u.isPlayer == true end
    _G.UnitIsDead = function(unit) local u = Unit(unit); return u ~= nil and u.dead == true end
    _G.UnitIsDeadOrGhost = function(unit) local u = Unit(unit); return u ~= nil and u.dead == true end
    -- Group members: u.inCombat, u.inRange (nil = range not checked), u.map
    _G.UnitIsUnit = function(a, b) return Unit(a) ~= nil and Unit(a) == Unit(b) end
    _G.UnitIsConnected = function(unit) local u = Unit(unit); return u ~= nil and u.offline ~= true end
    _G.UnitInRange = function(unit)
        local u = Unit(unit)
        if not u or u.inRange == nil then return false, false end
        return u.inRange, true
    end
    -- Pets: u.playerControlled, u.hostile, u.tooltip = { "line2", "line3" }
    _G.UnitPlayerControlled = function(unit) local u = Unit(unit); return u ~= nil and (u.playerControlled or u.isPlayer) == true end
    _G.UnitCanAttack = function(_, unit) local u = Unit(unit); return u ~= nil and (u.hostile or u.faction == "Horde") == true end
    _G.UNITNAME_TITLE_PET = "%s's Pet"
    _G.UNITNAME_TITLE_MINION = "%s's Minion"
    _G.UNITNAME_TITLE_GUARDIAN = "%s's Guardian"
    _G.C_TooltipInfo = {
        GetUnit = function(unit)
            local u = Unit(unit)
            if not u then return nil end
            local lines = { { leftText = u.name } }
            for _, text in ipairs(u.tooltip or {}) do lines[#lines + 1] = { leftText = text } end
            return { lines = lines }
        end,
    }
    _G.GetGuildInfo = function(unit) local u = Unit(unit); return u and u.guild end
    -- H.guidInfo[guid] = { class, race, sex, name, realm } for players seen only by GUID
    H.guidInfo = {}
    _G.GetPlayerInfoByGUID = function(guid)
        local info = H.guidInfo[guid]
        if info then
            return info.class, info.class, info.race, info.race, info.sex, info.name, info.realm
        end
        for _, u in pairs(H.units) do
            if u.guid == guid then
                return u.class, u.class, u.race, u.race, u.sex, u.name, u.guidRealm or H.realm
            end
        end
    end
    _G.GetNormalizedRealmName = function() return H.realm end
    _G.GetRealmName = function() return H.realm end
    _G.GetLocale = function() return opts.locale or "enUS" end
    _G.IsInInstance = function() return H.instance[1], H.instance[2] end

    _G.Enum = { UIMapType = { Continent = 2 } }
    _G.C_Map = {
        GetBestMapForUnit = function(unit)
            local u = unit and unit ~= "player" and H.units[unit]
            if u and u.map then return u.map end
            return H.playerMap
        end,
        GetMapInfo = function(id) return H.maps[id] end,
        GetPlayerMapPosition = function()
            return { GetXY = function() return H.playerX, H.playerY end }
        end,
        -- H.noWaypoints: the client refuses user waypoints (as Classic Era does)
        CanSetUserWaypointOnMap = function() return not H.noWaypoints end,
        SetUserWaypoint = function(point) H.waypoints[#H.waypoints + 1] = point end,
        GetMapRectOnMap = function(child, parent)
            local r = H.mapRects[child .. ":" .. parent]
            if r then return r[1], r[2], r[3], r[4] end
        end,
    }
    -- "child:parent" -> { minX, maxX, minY, maxY }: where a map sits on a map above it
    H.mapRects = {}

    -- hooksecurefunc(table, "method", hook) and hooksecurefunc("global", hook)
    _G.hooksecurefunc = function(target, method, hook)
        if type(target) == "string" then
            target, method, hook = _G, target, method
        end
        local original = target[method]
        target[method] = function(...)
            local results = { original(...) }
            hook(...)
            return unpack(results)
        end
    end
    _G.GameTooltip = nil
    _G.RAID_CLASS_COLORS = {
        ROGUE = { r = 1, g = 0.96, b = 0.41 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    }
    -- opts.tooltip = "script" (OnTooltipSetUnit) | "processor" (TooltipDataProcessor):
    -- a GameTooltip stand-in; H.ShowUnitTooltip(unit) shows a unit on it and
    -- H.tooltipLines collects the added lines
    _G.TooltipDataProcessor = nil
    H.tooltipLines = {}
    if opts.tooltip then
        -- A plain table: missing fields must read as nil, as on a real tooltip
        local tip = setmetatable(NewFrame("GameTooltip"), nil)
        for _, method in ipairs({ "SetOwner", "SetText", "Show", "Hide", "ClearLines" }) do
            tip[method] = function() end
        end
        tip.hooks = {}
        function tip:HookScript(script, fn)
            self.hooks[script] = self.hooks[script] or {}
            table.insert(self.hooks[script], fn)
        end
        function tip:GetUnit() return self.unitName, self.unit end
        function tip:AddLine(text) H.tooltipLines[#H.tooltipLines + 1] = text end
        local postCalls = {}
        if opts.tooltip == "processor" then
            _G.Enum.TooltipDataType = { Unit = 2 }
            _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCalls[#postCalls + 1] = fn end }
        end
        local function Run(script)
            for _, fn in ipairs(tip.hooks[script] or {}) do fn(tip) end
        end
        -- times: how often the client fires the unit callback for this one tooltip
        function H.ShowUnitTooltip(unit, times)
            Run("OnTooltipCleared")
            H.tooltipLines = {}
            tip.unit = unit
            tip.unitName = H.units[unit] and H.units[unit].name
            for _ = 1, times or 1 do
                Run("OnTooltipSetUnit")
                for _, fn in ipairs(postCalls) do fn(tip, {}) end
            end
        end
    end

    -- Classic dropdowns (UIDropDownMenuTemplate): H.OpenDropdown(frame) runs its
    -- initializer and returns the entries (info tables; info.func() picks one)
    _G.DoesTemplateExist, _G.MenuUtil = nil, nil
    H.menuButtons = {}
    _G.UIDropDownMenu_SetWidth = function() end
    _G.UIDropDownMenu_Initialize = function(frame, fn) frame.initialize = fn end
    _G.UIDropDownMenu_CreateInfo = function() return {} end
    _G.UIDropDownMenu_AddButton = function(info) H.menuButtons[#H.menuButtons + 1] = info end
    _G.UIDropDownMenu_SetText = function(frame, text) frame.menuText = text end
    _G.CloseDropDownMenus = function() end
    function H.OpenDropdown(frame)
        H.menuButtons = {}
        frame.initialize(frame, 1)
        return H.menuButtons
    end
    _G.CLASS_ICON_TCOORDS = { ROGUE = { 0.49609375, 0.7421875, 0, 0.25 } }

    -- opts.options = "settings" (Settings API canvas category) | "interface" (old
    -- InterfaceOptions list) | nil (neither). H.optionsOpened records what was opened.
    H.optionsOpened = nil
    _G.Settings, _G.InterfaceOptions_AddCategory, _G.InterfaceOptionsFrame_OpenToCategory = nil, nil, nil
    if opts.options == "settings" then
        _G.Settings = {
            RegisterCanvasLayoutCategory = function(panel, name)
                return { ID = name, panel = panel, GetID = function(self) return self.ID end }
            end,
            RegisterAddOnCategory = function() end,
            OpenToCategory = function(id) H.optionsOpened = id end,
        }
    elseif opts.options == "interface" then
        _G.InterfaceOptions_AddCategory = function() end
        _G.InterfaceOptionsFrame_OpenToCategory = function(panel) H.optionsOpened = panel end
    end
    -- opts.minimap: a Minimap frame exists (the minimap button needs one)
    _G.Minimap = opts.minimap and NewFrame("Minimap") or nil
    -- opts.worldMap: the world map exists at load (otherwise it never loads)
    _G.WorldMapFrame = opts.worldMap and NewWorldMap() or nil
    H.worldMap = _G.WorldMapFrame
end

-------------------------------------------------
-- Loading and events
-------------------------------------------------

-- Load every file listed in the real TOC, in order, with a fresh namespace
function H.Load()
    local ns = {}
    local toc = assert(io.open(ROOT .. "/HeadHunter.toc", "r"))
    for line in toc:lines() do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local path = ROOT .. "/" .. line:gsub("\\", "/")
            local chunk = assert(loadfile(path))
            chunk("HeadHunter", ns)
        end
    end
    toc:close()
    H.ns = ns
    return ns
end

function H.Fire(event, ...)
    for _, frame in ipairs(frames) do
        local onEvent = frame.scripts.OnEvent
        if frame.registered[event] and onEvent then
            onEvent(frame, event, ...)
        end
    end
end

-- Install + load + ADDON_LOADED + PLAYER_LOGIN + PLAYER_ENTERING_WORLD
-- opts.levelWindow: keep the HH-047 level window on. Off by default, as with
-- /hh debug levels off, so alert tests are free to mix levels (the player is 30).
function H.Boot(opts)
    H.Install(opts)
    local ns = H.Load()
    H.Fire("ADDON_LOADED", "HeadHunter")
    if ns.db and not (opts and opts.levelWindow) then ns.db.settings.testNoLevelWindow = true end
    H.Fire("PLAYER_LOGIN")
    H.Fire("PLAYER_ENTERING_WORLD", true, false)
    return ns
end

function H.Advance(seconds)
    H.clock = H.clock + seconds
    local due = {}
    local pending = {}
    for _, timer in ipairs(H.timers) do
        if timer.at <= H.clock then due[#due + 1] = timer else pending[#pending + 1] = timer end
    end
    H.timers = pending
    for _, timer in ipairs(due) do timer.fn() end
end

-- Fire one combat log event. Arguments are CombatLogGetCurrentEventInfo's returns
-- from index 1 (timestamp) on; nils are allowed.
function H.FireCLEU(...)
    H.cleu = { n = select("#", ...), ... }
    H.Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

-- Flags of a hostile player / hostile player-controlled pet, as the client sends them
H.FLAGS_HOSTILE_PLAYER = 0x548   -- TYPE_PLAYER | CONTROL_PLAYER | REACTION_HOSTILE | AFFILIATION_OUTSIDER
H.FLAGS_HOSTILE_PET = 0x1148     -- TYPE_PET | CONTROL_PLAYER | REACTION_HOSTILE | AFFILIATION_OUTSIDER
H.FLAGS_HOSTILE_NPC = 0xA48      -- TYPE_NPC | CONTROL_NPC | REACTION_HOSTILE | AFFILIATION_OUTSIDER
H.FLAGS_FRIENDLY_PLAYER = 0x511  -- TYPE_PLAYER | CONTROL_PLAYER | REACTION_FRIENDLY | AFFILIATION_MINE

-- Deliver addon messages to the currently booted client as if sent by `sender`
function H.Deliver(messages, sender)
    for _, m in ipairs(messages) do
        H.Fire("CHAT_MSG_ADDON", m.prefix or "HeadHunter", m.message or m, "CHANNEL", sender)
    end
    -- Let the inbox drain (it runs on C_Timer.After(0))
    for _ = 1, 20 do H.Advance(0) end
end

function H.Slash(input)
    _G.SlashCmdList.HEADHUNTER(input)
end

function H.Printed(pattern)
    for _, line in ipairs(H.printed) do
        if line:find(pattern) then return true end
    end
    return false
end

return H
