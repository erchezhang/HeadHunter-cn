#!/usr/bin/env bash
# HeadHunter offline tests. Needs Lua 5.1 (apt install lua5.1).
# From Windows: wsl -d Ubuntu-22.04 -- bash "/mnt/g/Games/Battle.net/World of Warcraft/_forever_/Interface/AddOns/HeadHunter/tests/run.sh"
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=0
checked=0

# 1. Syntax pass on every addon file
while IFS= read -r -d '' file; do
    checked=$((checked + 1))
    if ! luac5.1 -p "$file"; then
        failures=$((failures + 1))
    fi
done < <(find "$ROOT" -name '*.lua' -not -path "$ROOT/tests/*" -print0)
echo "syntax: $checked file(s) checked, $failures failed"

# 2. Behaviour suites against the real files, loaded in TOC order
lua5.1 "$ROOT/tests/run.lua" "$ROOT" || failures=$((failures + 1))

if [ "$failures" -ne 0 ]; then
    echo "FAILED"
    exit 1
fi
echo "OK"
