-- HH-125: the HeadHunter look, the same as the website (head-hunter-web
-- resources/css/app.css): dark leather, gold frames, a wood header with the tabs,
-- Cinzel headings, Alegreya Sans text, Oswald names and Rye for WANTED.
--
--   Theme.StyleFrame(frame, title)          window: leather, gold border, wood header,
--                                           mark, title and close button
--   Theme.CreateTopTabs(frame, tabs, onSelect)  tabs in the header; tabs = { { id, label } }
--                                           returns { buttons, Select(id), Layout() }
--   Theme.Font(fontString, role, size)      role: heading, text, bold, name or western
--   Theme.Button(parent, text, variant)     variant: "gold" or "outline"
--   Theme.Card(parent), Theme.Divider(parent), Theme.Border(frame)
--   Theme.ApplyScale(frame)                 follows the window size (uiScale)
--   Theme.ResizeGrip(frame)                 the corner grip that sets the window size
--
-- Theme.FontFile(role, locale, alphabet) is the pure part (tested offline).

local addonName, ns = ...

local Theme = ns:RegisterModule("Theme", {})

local OWNER = "Theme"

local ASSETS = "Interface\\AddOns\\HeadHunter\\Assets\\"
Theme.TEXTURES = {
    leather = ASSETS .. "Textures\\leather",
    wood = ASSETS .. "Textures\\wood",
    poster = ASSETS .. "Textures\\poster",
    divider = ASSETS .. "Textures\\divider",
    glow = ASSETS .. "Textures\\glow",
    pin = ASSETS .. "Textures\\pin",
    mark = ASSETS .. "Textures\\mark",
}

-- The website's dark theme colours (oklch in app.css, as sRGB)
Theme.COLORS = {
    background = { 0.05, 0.032, 0.02 },
    card = { 0.089, 0.063, 0.043 },
    foreground = { 0.919, 0.863, 0.771 },
    muted = { 0.656, 0.585, 0.491 },
    stone = { 0.84, 0.83, 0.82 },
    gold = { 0.949, 0.69, 0.213 },
    wanted = { 0.802, 0.158, 0.139 },
    parchment = { 0.867, 0.765, 0.611 },
    parchmentText = { 0.174, 0.072, 0.014 },
}

Theme.HEADER_HEIGHT = 44
Theme.SCALE = { default = 100, min = 70, max = 150 } -- the uiScale setting, in % (the corner grip)

-------------------------------------------------
-- Fonts (pure part: which file for which text)
-------------------------------------------------

Theme.FONTS = {
    heading = ASSETS .. "Fonts\\Cinzel-Bold.ttf",
    text = ASSETS .. "Fonts\\AlegreyaSans-Regular.ttf",
    bold = ASSETS .. "Fonts\\AlegreyaSans-Bold.ttf",
    name = ASSETS .. "Fonts\\Oswald-Medium.ttf",
    western = ASSETS .. "Fonts\\Rye-Regular.ttf",
}

-- Clients whose own texts our fonts can show. Chinese and Korean clients keep the
-- game's fonts everywhere, so their texts and ours look the same.
local LATIN_CLIENTS = {
    enUS = true, enGB = true, deDE = true, esES = true, esMX = true, frFR = true, itIT = true, ptBR = true,
}
-- Our fonts with Cyrillic letters (Cinzel and Rye have none)
local CYRILLIC_ROLES = { text = true, bold = true, name = true }

-- The font file for a role on this client and alphabet, or nil for the game's own.
-- alphabet: the game's font family alphabets ("roman", "russian", "korean", ...).
function Theme.FontFile(role, locale, alphabet)
    alphabet = alphabet or "roman"
    local file = Theme.FONTS[role]
    if not file then return nil end
    if locale == "ruRU" then
        return CYRILLIC_ROLES[role] and (alphabet == "roman" or alphabet == "russian") and file or nil
    end
    if not LATIN_CLIENTS[locale] then return nil end
    if alphabet == "roman" then return file end
    if alphabet == "russian" and CYRILLIC_ROLES[role] then return file end
    return nil
end

-------------------------------------------------
-- Fonts (drawing)
-------------------------------------------------

local ALPHABETS = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }
local fontObjects = {}

-- One font object per role and size. Where the client has font families, each
-- alphabet gets our file or the game's own, so a Chinese name on an English client
-- still shows (Oswald has no Chinese letters).
local function FontObject(role, size)
    local name = "HeadHunterFont_" .. role .. "_" .. size
    if fontObjects[name] then return fontObjects[name] end
    local base = _G.GameFontHighlight
    local font
    if CreateFontFamily and base and base.GetFontObjectForAlphabet then
        local members = {}
        for _, alphabet in ipairs(ALPHABETS) do
            local game = base:GetFontObjectForAlphabet(alphabet)
            local gameFile = game and game:GetFont()
            local file = Theme.FontFile(role, ns.locale, alphabet) or gameFile
            if file then
                members[#members + 1] = { alphabet = alphabet, file = file, height = size, flags = "" }
            end
        end
        local ok, family = pcall(CreateFontFamily, name, members)
        if ok then font = family end
    end
    if not font and CreateFont then
        font = CreateFont(name)
        font:SetFont(Theme.FontFile(role, ns.locale) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    end
    fontObjects[name] = font
    return font
end

function Theme.Font(fs, role, size)
    local font = FontObject(role, size)
    if font then fs:SetFontObject(font) end
    return fs
end

-- Sets the text and makes the font smaller until it fits the width (long words such
-- as "РАЗЫСКИВАЕТСЯ" on the poster cannot wrap)
function Theme.FitText(fs, text, role, size, width, smallest)
    Theme.Font(fs, role, size)
    fs:SetText(text)
    while size > (smallest or 12) and (fs:GetStringWidth() or 0) > width do
        size = size - 2
        Theme.Font(fs, role, size)
    end
end

-- A font string in one call: parent, role, size, colour key (Theme.COLORS)
function Theme.Text(parent, role, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Theme.Font(fs, role, size)
    local c = Theme.COLORS[color or "foreground"]
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

-------------------------------------------------
-- Pieces
-------------------------------------------------

local function Solid(parent, layer, color, alpha, sublevel)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    tex:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return tex
end

-- frame-gold: a gold line with a dark line inside it
function Theme.Border(f, alpha)
    local gold = Theme.COLORS.gold
    local lines = {}
    local function Line(color, a, inset, sublevel)
        local top = Solid(f, "BORDER", color, a, sublevel)
        top:SetPoint("TOPLEFT", inset, -inset)
        top:SetPoint("TOPRIGHT", -inset, -inset)
        top:SetHeight(1)
        local bottom = Solid(f, "BORDER", color, a, sublevel)
        bottom:SetPoint("BOTTOMLEFT", inset, inset)
        bottom:SetPoint("BOTTOMRIGHT", -inset, inset)
        bottom:SetHeight(1)
        local left = Solid(f, "BORDER", color, a, sublevel)
        left:SetPoint("TOPLEFT", inset, -inset)
        left:SetPoint("BOTTOMLEFT", inset, inset)
        left:SetWidth(1)
        local right = Solid(f, "BORDER", color, a, sublevel)
        right:SetPoint("TOPRIGHT", -inset, -inset)
        right:SetPoint("BOTTOMRIGHT", -inset, inset)
        right:SetWidth(1)
        for _, line in ipairs({ top, bottom, left, right }) do lines[#lines + 1] = line end
    end
    Line(gold, alpha or 0.45, 0, 1)
    Line({ 0, 0, 0 }, 0.45, 1, 0)
    return lines
end

-- divider-gold: a gold rule fading out at both ends
function Theme.Divider(parent, width)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(Theme.TEXTURES.divider)
    tex:SetSize(width or 200, 1)
    return tex
end

-- A dark card with a gold frame, for groups inside a window
function Theme.Card(parent)
    local card = CreateFrame("Frame", nil, parent)
    local bg = Solid(card, "BACKGROUND", Theme.COLORS.card, 0.92)
    bg:SetAllPoints(card)
    Theme.Border(card, 0.3)
    return card
end

-------------------------------------------------
-- Buttons
-------------------------------------------------

local BUTTON_STYLES = {
    gold = { bg = "gold", bgAlpha = 1, hoverAlpha = 0.85, text = "parchmentText", border = 0 },
    outline = { bg = "gold", bgAlpha = 0, hoverAlpha = 0.12, text = "foreground", border = 0.5 },
}

function Theme.Button(parent, text, variant, width, height)
    local style = BUTTON_STYLES[variant or "outline"] or BUTTON_STYLES.outline
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 110, height or 24)

    local bg = Solid(button, "BACKGROUND", Theme.COLORS[style.bg], style.bgAlpha)
    bg:SetAllPoints(button)
    if style.border > 0 then Theme.Border(button, style.border) end

    local label = Theme.Text(button, variant == "gold" and "heading" or "bold", 12, style.text)
    label:SetPoint("CENTER", 0, 0)
    button:SetFontString(label)
    button:SetText(text or "")

    local function Paint(hover)
        local alpha = hover and style.hoverAlpha or style.bgAlpha
        local c = Theme.COLORS[style.bg]
        bg:SetColorTexture(c[1], c[2], c[3], alpha)
    end
    button:SetScript("OnEnter", function() Paint(true) end)
    button:SetScript("OnLeave", function() Paint(false) end)
    button:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    button.Paint = Paint
    return button
end

-- Choices side by side in one frame, the chosen one gold (the website's filter tabs).
-- options = { { value, label, icon = texture, coords = { l, r, t, b }, tip = hover text } }
-- Returns the frame; frame:Select(value) marks one without calling onSelect.
function Theme.Segmented(parent, options, onSelect, segmentWidth, height)
    local C = Theme.COLORS
    height = height or 24
    segmentWidth = segmentWidth or 110
    local set = CreateFrame("Frame", nil, parent)
    set:SetSize(segmentWidth * #options, height)
    set.buttons = {}
    local dots = {} -- value -> the live dot texture (SetDot)

    local function Paint(button, hover)
        local chosen = button.value == set.value
        local alpha = chosen and 1 or (hover and 0.12 or 0)
        button.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], alpha)
        local text = chosen and C.parchmentText or (hover and C.gold or C.foreground)
        button.label:SetTextColor(text[1], text[2], text[3])
    end

    for i, option in ipairs(options) do
        local button = CreateFrame("Button", nil, set)
        button.value = option.value
        button:SetSize(segmentWidth, height)
        button:SetPoint("LEFT", (i - 1) * segmentWidth, 0)
        button.bg = Solid(button, "BACKGROUND", C.gold, 0)
        button.bg:SetAllPoints(button)
        if i > 1 then
            local line = Solid(button, "BORDER", C.gold, 0.5)
            line:SetPoint("TOPLEFT")
            line:SetPoint("BOTTOMLEFT")
            line:SetWidth(1)
        end
        button.label = Theme.Text(button, "heading", 12, "foreground")
        button.label:SetText(option.label)
        if option.icon then
            button.label:SetPoint("CENTER", 9, 0)
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(option.icon)
            if option.coords then icon:SetTexCoord(unpack(option.coords)) end
            icon:SetSize(16, 16)
            icon:SetPoint("RIGHT", button.label, "LEFT", -4, 0)
        else
            button.label:SetPoint("CENTER")
        end
        button:SetScript("OnClick", function()
            if set.value ~= option.value then onSelect(option.value) end
        end)
        button:SetScript("OnEnter", function(self)
            Paint(self, true)
            if option.tip and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(option.label)
                GameTooltip:AddLine(option.tip, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function(self)
            Paint(self, false)
            if option.tip and GameTooltip then GameTooltip:Hide() end
        end)
        set.buttons[i] = button
    end
    Theme.Border(set, 0.5)

    function set:Select(value)
        self.value = value
        for _, button in ipairs(self.buttons) do Paint(button, false) end
    end

    -- A live dot after an option's text: something is live there (an event being
    -- played on Ongoing)
    function set:SetDot(value, shown)
        for _, button in ipairs(self.buttons) do
            if button.value == value and (shown or dots[value]) then
                if not dots[value] then
                    dots[value] = Theme.LiveDot(button)
                    dots[value]:SetPoint("LEFT", button.label, "RIGHT", Theme.LIVE_DOT_GAP, 0)
                end
                dots[value]:SetShown(shown)
            end
        end
    end
    return set
end

Theme.LIVE_DOT_COLOR = { 0.063, 0.725, 0.506 } -- the website's emerald-500
-- A round mask both clients have; a texture of our own colour needs no game file
Theme.CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- A small filled circle in the live dot colour (square where masks are missing)
function Theme.Circle(parent, layer)
    local c = Theme.LIVE_DOT_COLOR
    local tex = parent:CreateTexture(nil, layer)
    tex:SetColorTexture(c[1], c[2], c[3], 1)
    tex:SetSize(Theme.LIVE_DOT_SIZE, Theme.LIVE_DOT_SIZE)
    local mask = tex.AddMaskTexture and parent.CreateMaskTexture and parent:CreateMaskTexture()
    if mask then
        mask:SetTexture(Theme.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end
    return tex
end
Theme.LIVE_DOT_SIZE = 8
Theme.LIVE_DOT_PING = 1 -- seconds for the ring to grow and fade, like Tailwind's animate-ping
Theme.LIVE_DOT_PING_SCALE = 2
Theme.LIVE_DOT_PING_ALPHA = 0.75

Theme.LIVE_DOT_GAP = 5

-- The website's live dot (LiveDot.vue): a green dot with a ring that grows and fades
-- around it. Its own small frame, so the ring's per-frame update runs only while it is
-- shown and never takes the parent's OnUpdate.
function Theme.LiveDot(parent)
    local dot = CreateFrame("Frame", nil, parent)
    dot:SetSize(Theme.LIVE_DOT_SIZE, Theme.LIVE_DOT_SIZE)
    local ring = Theme.Circle(dot, "ARTWORK")
    ring:SetPoint("CENTER")
    local core = Theme.Circle(dot, "OVERLAY")
    core:SetPoint("CENTER")
    local clock = 0
    dot:SetScript("OnUpdate", function(_, elapsed)
        clock = clock + elapsed
        local size, alpha = Theme.LivePing(clock)
        ring:SetSize(size, size)
        ring:SetAlpha(alpha)
    end)
    dot:Hide()
    return dot
end

-- The ring at `clock` seconds: its size and alpha, from the dot's size at 0.75 to twice
-- the size at 0, then again
function Theme.LivePing(clock)
    local phase = (clock % Theme.LIVE_DOT_PING) / Theme.LIVE_DOT_PING
    local size = Theme.LIVE_DOT_SIZE * (1 + (Theme.LIVE_DOT_PING_SCALE - 1) * phase)
    return size, Theme.LIVE_DOT_PING_ALPHA * (1 - phase)
end

-- A square icon button with a gold hover (the Options gear, the close X)
local function IconButton(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    local hover = Solid(button, "HIGHLIGHT", Theme.COLORS.gold, 0.15)
    hover:SetAllPoints(button)
    return button
end

-------------------------------------------------
-- Window
-------------------------------------------------

local function Tiled(parent, layer, texture, sublevel)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    tex:SetTexture(texture, "REPEAT", "REPEAT")
    tex:SetHorizTile(true)
    tex:SetVertTile(true)
    return tex
end

-- The window chrome. The frame keeps its own size; the header is on top of it.
function Theme.StyleFrame(f, title)
    local C = Theme.COLORS
    local bg = CreateFrame("Frame", nil, f)
    bg:SetAllPoints(f)
    bg:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
    f.themeBg = bg

    -- bg-leather: dark base, leather texture, a soft gold glow from the top
    local base = Solid(bg, "BACKGROUND", C.background, 0.97, -8)
    base:SetAllPoints(bg)
    local leather = Tiled(bg, "BACKGROUND", Theme.TEXTURES.leather, -7)
    leather:SetAllPoints(bg)
    leather:SetVertexColor(0.42, 0.36, 0.32, 0.9)
    local glow = bg:CreateTexture(nil, "BACKGROUND", nil, -6)
    glow:SetTexture(Theme.TEXTURES.glow)
    glow:SetPoint("TOPLEFT", 0, -Theme.HEADER_HEIGHT)
    glow:SetPoint("TOPRIGHT", 0, -Theme.HEADER_HEIGHT)
    glow:SetHeight(180)
    Theme.Border(bg)

    -- bg-wood header with a shadow under it
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(Theme.HEADER_HEIGHT)
    local wood = Tiled(header, "BACKGROUND", Theme.TEXTURES.wood)
    wood:SetAllPoints(header)
    wood:SetVertexColor(0.5, 0.42, 0.36)
    local line = Solid(header, "BORDER", C.gold, 0.3)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    local shadow = Solid(header, "BORDER", { 0, 0, 0 }, 0.35)
    shadow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
    shadow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -1)
    shadow:SetHeight(4)
    f.header = header

    local mark = header:CreateTexture(nil, "ARTWORK")
    mark:SetTexture(Theme.TEXTURES.mark)
    mark:SetSize(30, 30)
    mark:SetPoint("LEFT", 10, 0)
    f.windowTitle = Theme.Text(header, "heading", 15, "gold")
    f.windowTitle:SetPoint("LEFT", mark, "RIGHT", 8, 0)
    f.windowTitle:SetText(title or "")
    f.windowTitle:SetShadowColor(0, 0, 0, 0.8)
    f.windowTitle:SetShadowOffset(1, -1)

    local close = IconButton(header, 26)
    close:SetPoint("RIGHT", -8, 0)
    local x = Theme.Text(close, "bold", 18, "stone")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
    close:SetScript("OnEnter", function() x:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end)
    close:SetScript("OnLeave", function() x:SetTextColor(C.stone[1], C.stone[2], C.stone[3]) end)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeButton = close

    Theme.ApplyScale(f)
    return f
end

-- The Options gear in a header, left of the close button
function Theme.HeaderGear(f, onClick)
    local gear = IconButton(f.header, 26)
    gear:SetPoint("RIGHT", f.closeButton, "LEFT", -4, 0)
    local icon = gear:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetDesaturated(true)
    icon:SetVertexColor(0.95, 0.8, 0.5)
    gear:SetScript("OnClick", onClick)
    return gear
end

-------------------------------------------------
-- Tabs in the header (the website's menu)
-------------------------------------------------

Theme.TAB_FONT = 12
Theme.TAB_PADDING = 12

local function CreateTopTab(f, info, onClick)
    local C = Theme.COLORS
    local tab = CreateFrame("Button", nil, f.header)
    tab.id = info.id
    tab:SetHeight(Theme.HEADER_HEIGHT - 2)
    tab.label = Theme.Text(tab, "heading", Theme.TAB_FONT, "stone")
    tab.label:SetPoint("CENTER", 0, 1)
    tab.label:SetText(info.label)
    tab.underline = Solid(tab, "ARTWORK", C.gold, 1)
    tab.underline:SetPoint("BOTTOMLEFT", 6, 4)
    tab.underline:SetPoint("BOTTOMRIGHT", -6, 4)
    tab.underline:SetHeight(2)

    local function Paint(hover)
        local c = (tab.selected or hover) and C.gold or C.stone
        tab.label:SetTextColor(c[1], c[2], c[3])
        tab.underline:SetShown(tab.selected == true)
    end
    function tab:SetSelected(isSelected)
        tab.selected = isSelected
        Paint(false)
    end
    tab:SetScript("OnEnter", function() Paint(true) end)
    tab:SetScript("OnLeave", function() Paint(false) end)
    tab:SetScript("OnClick", function()
        if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841) end
        onClick(info.id)
    end)
    tab:SetSelected(false)
    return tab
end

function Theme.CreateTopTabs(f, tabs, onSelect)
    local set = { buttons = {}, hidden = {}, dots = {}, dotShown = {} }

    -- Room a tab keeps for its live dot
    local function DotSpace(tab)
        return set.dotShown[tab.id] and (Theme.LIVE_DOT_SIZE + Theme.LIVE_DOT_GAP) or 0
    end
    for i, info in ipairs(tabs) do set.buttons[i] = CreateTopTab(f, info, onSelect) end

    function set:Select(id)
        for _, tab in ipairs(self.buttons) do tab:SetSelected(tab.id == id) end
    end

    -- A live dot in front of a tab's text (Events while an event is being played)
    function set:SetDot(id, shown)
        for _, tab in ipairs(self.buttons) do
            if tab.id == id and (shown or self.dots[id]) and (self.dotShown[id] or false) ~= shown then
                if not self.dots[id] then
                    self.dots[id] = Theme.LiveDot(tab)
                    self.dots[id]:SetPoint("RIGHT", tab.label, "LEFT", -Theme.LIVE_DOT_GAP, 0)
                end
                self.dots[id]:SetShown(shown)
                self.dotShown[id] = shown or nil
                self:Layout()
            end
        end
    end

    -- A tab's text changes (a count on Events); the tabs move to fit
    function set:SetLabel(id, text)
        for _, tab in ipairs(self.buttons) do
            if tab.id == id and tab.label:GetText() ~= text then
                tab.label:SetText(text)
                self:Layout()
            end
        end
    end

    -- A tab that comes and goes (Tournaments); the others move up
    function set:SetTabShown(id, shown)
        for _, tab in ipairs(self.buttons) do
            if tab.id == id then
                self.hidden[id] = not shown or nil
                if shown then tab:Show() else tab:Hide() end
            end
        end
        self:Layout()
    end

    -- Side by side after the title; long languages first lose padding, then font size
    function set:Layout(right)
        local left = (f.windowTitle:GetStringWidth() or 100) + 60
        local room = (f:GetWidth() or 800) - left - (right or 70)
        local shown = {}
        for _, tab in ipairs(self.buttons) do
            if not self.hidden[tab.id] then shown[#shown + 1] = tab end
        end
        local size, padding = Theme.TAB_FONT, Theme.TAB_PADDING
        local function Width()
            local total = 0
            for _, tab in ipairs(shown) do total = total + (tab.label:GetStringWidth() or 60) + 2 * padding + DotSpace(tab) end
            return total
        end
        while Width() > room and (padding > 6 or size > 10) do
            if padding > 6 then
                padding = padding - 2
            else
                size = size - 1
                for _, tab in ipairs(shown) do Theme.Font(tab.label, "heading", size) end
            end
        end
        local x = left
        for _, tab in ipairs(shown) do
            local width = (tab.label:GetStringWidth() or 60) + 2 * padding + DotSpace(tab)
            tab.label:ClearAllPoints()
            tab.label:SetPoint("CENTER", DotSpace(tab) / 2, 1)
            tab:ClearAllPoints()
            tab:SetPoint("BOTTOMLEFT", f.header, "BOTTOMLEFT", x, 1)
            tab:SetWidth(width)
            x = x + width
        end
    end

    set:Layout()
    return set
end

-------------------------------------------------
-- Window size (uiScale, set with the corner grip)
-------------------------------------------------

local scaled = {}

-- The window size as a scale, kept inside its limits
function Theme.Scale()
    local value = tonumber(ns.Database and ns.Database:GetSetting("uiScale")) or Theme.SCALE.default
    value = math.max(Theme.SCALE.min, math.min(Theme.SCALE.max, value))
    return value / 100
end

function Theme.ApplyScale(f)
    scaled[f] = true
    f:SetScale(Theme.Scale())
end

ns.Events:Register("HH_SETTING_CHANGED", function(_, path)
    if path ~= "uiScale" then return end
    for f in pairs(scaled) do f:SetScale(Theme.Scale()) end
end, OWNER)

-- Saves a window size in %, kept inside the limits; every themed window follows it
function Theme.SaveScale(percent)
    percent = math.floor((tonumber(percent) or Theme.SCALE.default) + 0.5)
    percent = math.max(Theme.SCALE.min, math.min(Theme.SCALE.max, percent))
    ns.Database:SetSetting("uiScale", percent)
    return percent
end

-- The scale for a drag of the corner: the window's width on screen at the start, plus
-- how far the cursor moved right, as a share of that width (pure, tested offline)
function Theme.DragScale(startScale, startWidth, moved)
    if not startWidth or startWidth <= 0 then return startScale end
    local scale = startScale * (startWidth + moved) / startWidth
    return math.max(Theme.SCALE.min / 100, math.min(Theme.SCALE.max / 100, scale))
end

-- Keeps the window's top left corner where it is on screen while its scale changes,
-- so the bottom right corner follows the cursor
local function KeepTopLeft(f, left, top)
    local scale = f:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
end

local function ShowGripTip(grip)
    if not GameTooltip then return end
    GameTooltip:SetOwner(grip, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(ns.L.SET_SCALE .. ": " .. string.format(ns.L.SET_PERCENT, math.floor(Theme.Scale() * 100 + 0.5)))
    GameTooltip:AddLine(ns.L.RESIZE_TIP, 1, 1, 1, true)
    GameTooltip:Show()
end

local function EndDrag(grip, f)
    grip.dragging = false
    Theme.SaveScale(f:GetScale() * 100)
    if GameTooltip and GameTooltip:IsOwned(grip) then ShowGripTip(grip) end
end

-- The grip in the bottom right corner of a window (author, 2026-10-05; it replaces the
-- Window size option): drag to make the window and its text bigger or smaller, right
-- click for 100%. It sets the same uiScale, so every themed window follows.
function Theme.ResizeGrip(f)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local scale = f:GetEffectiveScale()
        self.startX = GetCursorPosition()
        self.startScale = f:GetScale()
        self.startWidth = f:GetWidth() * scale
        self.left, self.top = f:GetLeft() * scale, f:GetTop() * scale
        self.dragging = true
    end)
    grip:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            Theme.SaveScale(Theme.SCALE.default)
            if GameTooltip and GameTooltip:IsOwned(self) then ShowGripTip(self) end
        elseif self.dragging then
            EndDrag(self, f)
        end
    end)
    grip:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            EndDrag(self, f)
            return
        end
        f:SetScale(Theme.DragScale(self.startScale, self.startWidth, GetCursorPosition() - self.startX))
        KeepTopLeft(f, self.left, self.top)
    end)
    grip:SetScript("OnEnter", ShowGripTip)
    grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.resizeGrip = grip
    return grip
end
