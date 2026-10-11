-- HH-014: grey level and kill classification.

return function(T, H)
    T.case("grey level follows the Classic formula", function()
        local C = H.Boot({ client = "era" }).Classify
        local EXPECTED = {
            [1] = 0, [5] = 0, [6] = 1, [9] = 4, [10] = 4, [20] = 13, [30] = 22,
            [39] = 31, [40] = 31, [50] = 39, [59] = 47, [60] = 47,
        }
        for level, grey in pairs(EXPECTED) do
            T.eq(C.GreyLevel(level), grey, "grey at " .. level)
        end
    end)

    T.case("kill classification", function()
        local C = H.Boot({ client = "era" }).Classify
        local CASES = {
            { -1, 10, "coward", "skull" },
            { 60, 47, "coward", "grey victim at 60" },
            { 60, 50, "coward", "10+ levels" },
            { 30, 22, "coward", "grey victim at 30" },
            { 30, 23, "normal", "7 above, not grey" },
            { 20, 20, "fair", "same level" },
            { 23, 20, "fair", "3 above" },
            { 17, 20, "fair", "3 below" },
            { 24, 20, "normal", "4 above" },
            { 16, 20, "giant", "4 below" },
            { nil, 20, "unknown", "killer level unknown" },
            { 20, nil, "unknown", "victim level unknown" },
            { 0, 20, "unknown", "zero level" },
        }
        for _, c in ipairs(CASES) do
            T.eq(C.Kill(c[1], c[2]), c[3], c[4])
        end
    end)

    T.case("group size is judged next to the levels: Duo (2), Gang (3+)", function()
        local C = H.Boot({ client = "era" }).Classify
        local function Report(assists, killerLevel, victimLevel)
            local list = {}
            for i = 1, assists do list[i] = { key = "A" .. i .. "-Stonespine", level = 60 } end
            return { killer = { key = "K-Stonespine", level = killerLevel or 60 },
                victim = { level = victimLevel or 60 }, assists = list }
        end
        T.eq(C.Group(1), nil, "alone")
        T.eq(C.Group(2), "duo", "2")
        T.eq(C.Group(3), "gang", "3")
        T.eq(C.Group(6), "gang", "6")
        T.eq(C.Report(Report(2)), "fair", "the level judgement stays")
        T.ok(C.IsFair("fair", nil) and not C.IsFair("fair", "duo"), "with help: not fair")
        T.ok(not C.IsGiant("giant", "gang"), "with help: no giant slaying")

        T.eq(C.ReportLabel(Report(0)), "|cff40ff40Fair fight|r", "1 vs 1")
        T.eq(C.ReportLabel(Report(1)), "|cffcc66ffDuo|r (2 vs 1)", "same level 2 vs 1: only the group")
        T.eq(C.ReportLabel(Report(2)), "|cffcc66ffGang|r (3 vs 1)", "same level 3 vs 1")
        T.eq(C.ReportLabel(Report(1, 60, 20)), "|cffff8000Bully kill|r · |cffcc66ffDuo|r (2 vs 1)", "lowbie + duo")
        T.eq(C.ReportLabel(Report(3, -1)), "|cffff8000Bully kill|r · |cffcc66ffGang|r (4 vs 1)", "skull + gang")
    end)

    T.case("a group fight: our group members in the fight, no Duo or Gang", function()
        local C = H.Boot({ client = "era" }).Classify
        local function Report(assists, helpers, victimLevel, killerLevel)
            local list = {}
            for i = 1, assists do list[i] = { key = "A" .. i .. "-Stonespine", level = 60 } end
            return { killer = { key = "K-Stonespine", level = killerLevel or 60 }, victim = { level = victimLevel or 60 },
                assists = list, helpers = helpers }
        end
        T.eq(C.Group(4, 2), "group", "4 vs 3")
        T.eq(C.Group(1, 1), "group", "1 vs 2")
        T.eq(C.Group(3, 0), "gang", "no helpers: a gang")
        T.eq(C.Helpers(Report(0)), 0, "old reports: alone")
        T.ok(not C.IsFair("fair", "group"), "not one on one")
        T.eq(C.ReportLabel(Report(3, 2)), "|cffcc66ffGroup fight|r (4 vs 3)", "4 vs 3")
        T.eq(C.ReportLabel(Report(0, 1)), "|cffcc66ffGroup fight|r (1 vs 2)", "1 vs 2")
        T.eq(C.ReportLabel(Report(1, 1, 20)), "|cffff8000Bully kill|r · |cffcc66ffGroup fight|r (2 vs 2)",
            "a lowbie kill stays a Bully kill")
        T.eq(C.ReportLabel(Report(0, 3, 30, 23)), "|cffcc66ffGroup fight|r (1 vs 4)",
            "Underdog is 1 vs 1 only (HH-143)")
        T.eq(C.ReportLabel(Report(1, 0, 30, 23)), "|cffcc66ffDuo|r (2 vs 1)", "no Underdog with help")
        T.eq(C.ReportLabel(Report(0, 0, 30, 23)), "|cff40c0ffUnderdog win|r", "1 vs 1: Underdog")
    end)
end
