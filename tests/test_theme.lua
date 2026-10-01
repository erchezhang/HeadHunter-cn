-- HH-125: the website's look (UI/Theme.lua): fonts per client language, Window size.

return function(T, H)
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

    T.case("Window size: 100% by default, 90 to 130 in steps of 10, windows follow at once", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.Theme.Scale(), 1, "default")
        H.Slash("")
        local window = _G.HeadHunterMainFrame
        T.eq(window:GetScale(), 1, "window at 100%")

        local S = ns.SettingsPanel
        local option = S.Option("scale")
        S.Set(option, 120)
        T.eq(ns.db.settings.uiScale, 120, "saved")
        T.eq(window:GetScale(), 1.2, "the open window follows")
        S.Set(option, 500)
        T.eq(ns.db.settings.uiScale, 130, "not above 130%")
        S.Set(option, 10)
        T.eq(ns.db.settings.uiScale, 90, "not below 90%")
        ns.db.settings.uiScale = nil
        T.eq(ns.Theme.Scale(), 1, "an old save without the setting: 100%")
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
