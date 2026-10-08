-- Offline test runner (Lua 5.1, same language version as WoW).
-- Usage: tests/run.sh   (or: lua5.1 tests/run.lua <addon root>)

-- The harness replaces the global print to capture addon output; keep the real one
local print = print

local ROOT = assert(arg[1], "usage: lua5.1 tests/run.lua <addon root>")
package.path = ROOT .. "/tests/?.lua;" .. package.path

local H = require("harness")

local T = { passed = 0, failed = 0, current = "" }

local function Fail(message)
    error({ hhFailure = true, message = message }, 0)
end

function T.eq(actual, expected, label)
    if actual ~= expected then
        Fail(string.format("%s: got %s, want %s", label or "value", tostring(actual), tostring(expected)))
    end
end

function T.ok(condition, label)
    if not condition then Fail(label or "expected true") end
end

-- No Lua errors and no protected (forbidden) calls
function T.noErrors()
    if #H.errors > 0 then
        Fail("addon raised errors:\n      " .. table.concat(H.errors, "\n      "))
    end
    if #H.forbidden > 0 then
        Fail("ADDON_ACTION_FORBIDDEN:\n      " .. table.concat(H.forbidden, "\n      "))
    end
end

function T.case(name, fn)
    local ok, err = pcall(fn)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        local message = type(err) == "table" and err.message or tostring(err)
        print(string.format("  FAIL %s > %s\n      %s", T.current, name, message))
    end
end

local SUITES = {
    "test_expansion", "test_events", "test_utils", "test_database", "test_guards", "test_commands",
    "test_classify", "test_enemy_cache", "test_death_reports", "test_era_deaths", "test_forever_deaths",
    "test_protocol", "test_sync", "test_rules_engine", "test_wanted", "test_alerts", "test_spotted", "test_activity", "test_posse", "test_layer", "test_pets", "test_hotspots", "test_wars", "test_duel_spots", "test_map_markers", "test_justice", "test_honor_kills", "test_catchup", "test_relay", "test_witness", "test_glasses", "test_verdict", "test_main_window", "test_tooltip_line", "test_poster", "test_theme", "test_settings_panel", "test_toolbox", "test_marks", "test_level_window", "test_high_noon", "test_tournament", "test_organizers", "test_matches", "test_nameplates", "test_zones", "test_demo", "test_site_data", "test_presence", "test_battle_help", "test_bounties", "test_homes", "test_screenshots", "test_locales",
}

for _, suite in ipairs(SUITES) do
    T.current = suite
    local before = T.failed
    require(suite)(T, H)
    print(string.format("%s %s", T.failed == before and "ok  " or "FAIL", suite))
end

print(string.format("\ntests: %d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
