#!/bin/bash
# Remove mac-keepawake and restore normal macOS behavior.
set -uo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user (no sudo)."; exit 1; }
UID_NUM="$(id -u)"

echo "==> Stopping services..."
sudo launchctl bootout system/com.user.ackeepawake 2>/dev/null || true
launchctl bootout "gui/$UID_NUM/com.user.lidbrightness" 2>/dev/null || true

echo "==> Removing files..."
sudo rm -f /Library/LaunchDaemons/com.user.ackeepawake.plist /Library/LaunchAgents/com.user.lidbrightness.plist
sudo rm -f /usr/local/bin/dsbright /usr/local/bin/keepawake /usr/local/bin/ac-keepawake.sh /usr/local/bin/lid-brightness.sh
sudo rm -f /etc/sudoers.d/keepawake
rm -f /tmp/.lid_brightness_saved /tmp/lid-brightness.log

echo "==> Restoring default sleep / display / screen-saver..."
sudo pmset -a disablesleep 0
sudo pmset -c displaysleep 2
defaults -currentHost write com.apple.screensaver idleTime -int 1200

echo "Done. Normal sleep behavior restored."
