#!/bin/bash
# Uninstaller for the pCloud hang watchdog.
# Unloads and removes the LaunchAgent and the installed script. Logs are kept
# unless you pass --purge-logs.
set -euo pipefail

LABEL="com.pcloud-watchdog"
SUPPORT_DIR="$HOME/Library/Application Support/pcloud-watchdog"
LOG_DIR="$HOME/Library/Logs/pcloud-watchdog"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "Uninstalling pCloud watchdog..."

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$SUPPORT_DIR"

if [ "${1:-}" = "--purge-logs" ]; then
  rm -rf "$LOG_DIR"
  echo "Removed agent, script, and logs."
else
  echo "Removed agent and script. Logs kept at $LOG_DIR (use --purge-logs to delete)."
fi
