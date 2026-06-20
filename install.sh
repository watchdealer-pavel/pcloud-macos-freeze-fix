#!/bin/bash
# Installer for the pCloud hang watchdog.
# Copies watchdog.sh into your Library, writes a LaunchAgent plist with the
# correct paths for your account, and loads it. Re-running this is safe; it
# reloads the agent.
set -euo pipefail

LABEL="com.pcloud-watchdog"
SUPPORT_DIR="$HOME/Library/Application Support/pcloud-watchdog"
LOG_DIR="$HOME/Library/Logs/pcloud-watchdog"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing pCloud watchdog..."

mkdir -p "$SUPPORT_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
cp "$SRC_DIR/watchdog.sh" "$SUPPORT_DIR/watchdog.sh"
chmod +x "$SUPPORT_DIR/watchdog.sh"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SUPPORT_DIR/watchdog.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/launchd.err.log</string>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/launchd.out.log</string>
</dict>
</plist>
PLIST_EOF

# Reload cleanly: unload an old copy if present, then load the new one.
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "Done."
echo "  Agent:  $LABEL (runs every 30s)"
echo "  Script: $SUPPORT_DIR/watchdog.sh"
echo "  Logs:   $LOG_DIR/watchdog.log"
echo
echo "If your pCloud Drive is not mounted at \"\$HOME/pCloud Drive\", edit MOUNT"
echo "at the top of watchdog.sh and run ./install.sh again."
