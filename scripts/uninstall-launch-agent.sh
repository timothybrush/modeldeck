#!/bin/bash
# Uninstall the ModelDeck LaunchAgent from this machine.
#
# Boots the agent out of the GUI login session and removes the plist.
# Idempotent: safe to run when the agent is not loaded or not installed.
# Leaves data (including managed Codex profiles and recovery backups) and
# Keychain entries in place. README Uninstall covers optional data removal.
#
# Usage: scripts/uninstall-launch-agent.sh
set -euo pipefail

LABEL="ai.hermes.modeldeck"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI_TARGET="gui/$(id -u)"

launchctl bootout "$GUI_TARGET/$LABEL" 2>/dev/null && echo "Booted out $GUI_TARGET/$LABEL" || echo "$LABEL was not loaded"

if [[ -f "$PLIST" ]]; then
  rm "$PLIST"
  echo "Removed $PLIST"
else
  echo "No plist at $PLIST"
fi

echo "Data (including managed Codex profiles and recovery backups) and the Keychain token were left in place."
echo "Deleting the ModelDeck data directory also removes those Codex profiles; see README Uninstall before deleting data."
