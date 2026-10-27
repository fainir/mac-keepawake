#!/bin/bash
# Remove mac-keepawake and restore normal macOS behavior.  Safe to re-run.
# No `set -e` on purpose: keep going and clean up as much as possible.
set -uo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user (no sudo)."; exit 1; }
UID_NUM="$(id -u)"
STATE_DIR="$HOME/Library/Application Support/mac-keepawake"
SAVED="$STATE_DIR/pre-install-settings"

echo "==> Stopping keepawake (if running) and services..."
# keepawake re-asserts disablesleep every 2s; stop it while its sudoers rule still exists.
pkill -f '^(/bin/)?bash /usr/local/bin/keepawake( |$)' 2>/dev/null || true
sudo rm -f /etc/sudoers.d/keepawake
sudo launchctl bootout system/com.user.ackeepawake 2>/dev/null || true
# Stopping the agent also restores the backlight if it had dimmed it.
launchctl bootout "gui/$UID_NUM/com.user.lidbrightness" 2>/dev/null || true

echo "==> Restoring sleep / display / screen-saver settings..."
saved() { sed -n "s/^$1=//p" "$SAVED" 2>/dev/null | head -n 1; }
ds="$(saved displaysleep)"
idle="$(saved idleTime)"
case "$ds" in ''|*[!0-9]*) ds=10 ;; esac   # macOS default on the power adapter
sudo pmset -a disablesleep 0
sudo pmset -c displaysleep "$ds"
case "$idle" in
  ''|*[!0-9]*) defaults -currentHost delete com.apple.screensaver idleTime 2>/dev/null || true ;;
  *)           defaults -currentHost write com.apple.screensaver idleTime -int "$idle" ;;
esac
echo "    disablesleep=0, AC displaysleep=$ds, screensaver idleTime=${idle:-macOS default}"

echo "==> Removing files..."
sudo rm -f /Library/LaunchDaemons/com.user.ackeepawake.plist /Library/LaunchAgents/com.user.lidbrightness.plist
sudo rm -f /usr/local/bin/dsbright /usr/local/bin/keepawake /usr/local/bin/ac-keepawake.sh /usr/local/bin/lid-brightness.sh
sudo rm -f /var/log/ac-keepawake.log
rm -rf "$STATE_DIR"
rm -f /tmp/.lid_brightness_saved /tmp/lid-brightness.log

echo "Done. Normal sleep behavior restored."
