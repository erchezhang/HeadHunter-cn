-- HH-125: the website's look (UI/Theme.lua): fonts per client language, Window size.

return function(T, H)
    T.case("game file paths keep their folders (a single backslash would drop them)", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.Theme.CIRCLE_MASK, [[Interface\CHARACTERFRAME\TempPortraitAlphaMask]], "the live dot's round mask")
        local seen = 0
        for _, path in ipairs({ ns.Theme.CIRCLE_MASK, ns.Hotspots.FIRE_ICON, ns.Screenshots and ns.Screenshots.FILE_PREFIX }) do
            if type(path) == "string" and path:find("^Interface") then
                T.ok(path:find("\\", 1, true) ~= nil, "folders kept: " .. path)
                seen = seen + 1
            end
        end
        T.eq(seen, 2, "both paths checked")
    end)

    T.case("fonts: ours on Latin clients, the game's on Chinese and Korean ones", function()
        local ns = H.Boot({ client = "era" })
        local F = ns.Theme.FontFile
        local fonts = ns.Theme.FONTS
        for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR" }) do
            for role, file in pairs(fonts) do
                T.eq(F(role, locale), file, locale .. " " .. role)
            end
        end
        for _, locale in ipairs({ "zhCN", "zhTW", "koKR" }) do
            for role in pairs(fonts) do
                T.eq(F(role, locale), nil, locale .. " " .. role .. " keeps the game's font")
            end
        end
        T.eq(F("name", "enUS", "simplifiedchinese"), nil, "a Chinese name on an English client: the game's letters")
        T.eq(F("name", "enUS", "russian"), fonts.name, "Oswald has Cyrillic")
        T.eq(F("heading", "enUS", "russian"), nil, "Cinzel has none")
        T.eq(F("unknown", "enUS"), nil, "unknown role")
        T.noErrors()
    end)

    T.case("fonts on a Russian client: ours only where they have Cyrillic", function()
        local ns = H.Boot({ client = "era", locale = "ruRU" })
        local F = ns.Theme.FontFile
        T.eq(F("text", "ruRU"), ns.Theme.FONTS.text, "Alegreya Sans")
        T.eq(F("name", "ruRU", "russian"), ns.Theme.FONTS.name, "Oswald")
        T.eq(F("heading", "ruRU"), nil, "no Cinzel")
        T.eq(F("western", "ruRU"), nil, "no Rye")
        T.noErrors()
    end)

    T.case("window size: set with the corner grip, 70 to 150%, no option, windows follow at once", function()
        local ns = H.Boot({ client = "era" })
        local Theme = ns.Theme
        T.eq(Theme.Scale(), 1, "default")
        T.eq(ns.SettingsPanel.Option("scale"), nil, "no Window size option any more")
        H.Slash("")
        local window = _G.HeadHunterMainFrame
        T.eq(window:GetScale(), 1, "window at 100%")
        T.ok(window.resizeGrip ~= nil, "a grip in the corner")

        T.eq(Theme.DragScale(1, 800, 200), 1.25, "800 px wide, dragged 200 px right: 125%")
        T.eq(Theme.DragScale(1, 800, -200), 0.75, "dragged left: smaller")
        T.eq(Theme.DragScale(1, 800, 2000), 1.5, "not above 150%")
        T.eq(Theme.DragScale(1, 800, -2000), 0.7, "not below 70%")

        T.eq(Theme.SaveScale(124.6), 125, "saved in whole %")
        T.eq(ns.db.settings.uiScale, 125, "saved")
        T.eq(window:GetScale(), 1.25, "the open window follows")
        T.eq(Theme.SaveScale(500), 150, "not above 150%")
        window.resizeGrip.scripts.OnMouseUp(window.resizeGrip, "RightButton")
        T.eq(ns.db.settings.uiScale, 100, "right click: back to 100%")
        ns.db.settings.uiScale = nil
        T.eq(Theme.Scale(), 1, "an old save without the setting: 100%")
        T.noErrors()
    end)

    T.case("the tabs sit in the header", function()
        H.Boot({ client = "era" })
        H.Slash("")
        local tabs = _G.HeadHunterMainFrame.tabs
        local header = _G.HeadHunterMainFrame.header
        for _, tab in ipairs(tabs.buttons) do
            T.eq(tab.point[2], header, tab.id .. " in the header")
        end
        T.noErrors()
    end)
end
