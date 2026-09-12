#!/usr/bin/env bash
# Delete the per-run UserDefaults plists the Swift test fixtures left in
# ~/Library/Preferences before ScratchDefaults (2026-09-02): every fixture
# built `UserDefaults(suiteName: "<prefix>-<UUID>")` there, and
# `removePersistentDomain` empties that plist without deleting it. Tim's
# machine had 59,899 of them. Only the exact fixture names below are
# touched; nothing else on the machine uses them.
#
# Usage: Scripts/clean_test_defaults.sh [--dry-run]
set -euo pipefail

prefs="$HOME/Library/Preferences"
uuid='[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'
prefixes='activation-flow-tests|activation-warning-tests|auto-update-tests|complete-activation-tests|deck-activation-tests|deck-pin-tests|deck-tests|dup-relogin-tests|echo-loop-tests|floating-deck-tests|fresh-install-activation-tests|health-chip-tests|install-update-tests|issue241-slot|issue241-tests|issue242|issue297-tests|issue302-tests|issue303-tests|issue315-tests|issue317-tests|issue319-tests|issue321-tests|issue326-tests|issue330-tests|issue343-tests|issue424-tests|issue488|modeldeck-burnwindow-[a-z]+|modeldeck-chrome-[a-z]+|modeldeck-onboarding|modeldeck\.tests\.clientkeys|pin-window-tests|signin-again-tests|silent-activation-tests|stale-refresh-tests|warning-tests'
fixed='modeldeck-tests-(defaults|drift|env|first-open|garbage|moved|scope-switch|unchanged|vanished)'
pattern="^(($prefixes)[-.]$uuid|$fixed)\.plist$"

matches=$(ls "$prefs" | grep -E "$pattern" || true)
count=$(printf '%s\n' "$matches" | grep -c . || true)

if [[ "${1:-}" == "--dry-run" ]]; then
    echo "would delete $count test plist(s) from $prefs"
    exit 0
fi
if [[ "$count" -gt 0 ]]; then
    printf '%s\n' "$matches" | (cd "$prefs" && xargs rm --)
fi
echo "deleted $count test plist(s) from $prefs"
