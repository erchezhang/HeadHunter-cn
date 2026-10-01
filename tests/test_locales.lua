-- HH-064: translations. Every English key has a zhCN text with the same format codes.

return function(T, H)
    -- The English texts, read from Locales.lua without loading the addon
    local function EnglishTexts()
        local texts = {}
        local file = assert(io.open(H.ROOT .. "/Locales.lua", "r"))
        for line in file:lines() do
            local key, text = line:match('^L%.([%w_]+) = "(.*)"')
            if key then texts[key] = text end
        end
        file:close()
        return texts
    end

    local function Codes(text, pattern)
        local found = {}
        for code in text:gmatch(pattern) do found[#found + 1] = code end
        return table.concat(found, " ")
    end

    T.case("enUS: English texts, class and faction names", function()
        local ns = H.Boot({ client = "era" })
        T.eq(ns.L.TAB_WANTED, "WANTED", "tab")
        T.eq(ns.Utils.ClassName("ROGUE"), "Rogue", "class")
        T.eq(ns.Utils.RaceName("NightElf"), "Night Elf", "race")
        T.eq(ns.Utils.FactionName("Horde"), "Horde", "faction")
        T.noErrors()
    end)

    for _, locale in ipairs({ "zhCN", "zhTW", "koKR", "ruRU", "ptBR", "esES", "esMX", "frFR", "deDE", "itIT" }) do
        T.case(locale .. ": every key translated, same format and color codes", function()
            local ns = H.Boot({ client = "era", locale = locale })
            local english = EnglishTexts()
            local count = 0
            for key, text in pairs(english) do
                count = count + 1
                local translated = rawget(ns.L, key)
                T.ok(translated ~= nil, locale .. " text for " .. key)
                T.eq(Codes(translated, "%%[%-%d%.]*[sdf]"), Codes(text, "%%[%-%d%.]*[sdf]"), "format codes of " .. key)
                T.eq(Codes(translated, "|[cr]"), Codes(text, "|[cr]"), "color codes of " .. key)
            end
            T.ok(count > 400, "English keys read")
            T.noErrors()
        end)
    end

    T.case("zhTW: Taiwan names, not the zhCN ones", function()
        local ns = H.Boot({ client = "era", locale = "zhTW" })
        T.eq(ns.L.TAB_WANTED, "通緝", "tab")
        T.eq(ns.Utils.RaceName("Scourge"), "不死族", "race")
        T.noErrors()
    end)

    T.case("HeadHunter_Dev locale shows zhCN on an English client", function()
        local ns = H.Boot({ client = "era", dev = { locale = "zhCN" } })
        T.eq(ns.locale, "zhCN", "locale")
        T.eq(ns.L.TAB_WANTED, "通缉", "tab")
        T.eq(ns.Utils.RaceName("Scourge"), "亡灵", "race")
        T.noErrors()
    end)

    T.case("zhCN: race and class names", function()
        _G.LOCALIZED_CLASS_NAMES_MALE = { ROGUE = "盗贼" }
        local ns = H.Boot({ client = "era", locale = "zhCN" })
        T.eq(ns.Utils.RaceName("Scourge"), "亡灵", "race")
        T.eq(ns.Utils.ClassName("ROGUE"), "盗贼", "class from the client")
        T.eq(ns.DeathReports.Describe({ level = 60, race = "Orc", class = "ROGUE" }), "60 兽人 盗贼", "describe")
        _G.LOCALIZED_CLASS_NAMES_MALE = nil
        T.noErrors()
    end)
end
