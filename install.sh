#!/bin/bash
# mac-keepawake installer.  Run as your normal user (NOT with sudo) - it will
# ask for your password when it needs root.
set -euo pipefail

[ "$(uname)" = "Darwin" ] || { echo "macOS only."; exit 1; }
[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user (no sudo); it will prompt when needed."; exit 1; }

USER_NAME="$(id -un)"
UID_NUM="$(id -u)"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Checking Xcode command line tools (needed to build the brightness helper)..."
if ! xcode-select -p >/dev/null 2>&1; then
  echo "    Missing. Run:  xcode-select --install   then re-run ./install.sh"; exit 1
fi

echo "==> Compiling dsbright (DisplayServices brightness helper)..."
clang -O2 -o /tmp/dsbright "$HERE/src/dsbright.c" -framework CoreGraphics

echo "==> Installing binaries to /usr/local/bin ..."
sudo mkdir -p /usr/local/bin
sudo cp /tmp/dsbright            /usr/local/bin/dsbright
sudo cp "$HERE/src/keepawake"        /usr/local/bin/keepawake
sudo cp "$HERE/src/ac-keepawake.sh"  /usr/local/bin/ac-keepawake.sh
sudo cp "$HERE/src/lid-brightness.sh" /usr/local/bin/lid-brightness.sh
sudo chown root:wheel /usr/local/bin/dsbright /usr/local/bin/keepawake /usr/local/bin/ac-keepawake.sh /usr/local/bin/lid-brightness.sh
sudo chmod 755        /usr/local/bin/dsbright /usr/local/bin/keepawake /usr/local/bin/ac-keepawake.sh /usr/local/bin/lid-brightness.sh

echo "==> Allowing passwordless 'pmset' for keepawake (scoped to you)..."
echo "$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset" | sudo tee /etc/sudoers.d/keepawake >/dev/null
sudo chmod 440 /etc/sudoers.d/keepawake
sudo visudo -cf /etc/sudoers.d/keepawake >/dev/null || { echo "sudoers check failed"; sudo rm -f /etc/sudoers.d/keepawake; exit 1; }

echo "==> Installing launch services..."
sudo cp "$HERE/src/com.user.ackeepawake.plist"   /Library/LaunchDaemons/
sudo cp "$HERE/src/com.user.lidbrightness.plist" /Library/LaunchAgents/
sudo chown root:wheel /Library/LaunchDaemons/com.user.ackeepawake.plist /Library/LaunchAgents/com.user.lidbrightness.plist
sudo chmod 644        /Library/LaunchDaemons/com.user.ackeepawake.plist /Library/LaunchAgents/com.user.lidbrightness.plist

echo "==> Display settings: AC display never sleeps + screen saver off (no lock screen)..."
sudo pmset -c displaysleep 0
defaults -currentHost write com.apple.screensaver idleTime -int 0

echo "==> Loading daemon + agent..."
sudo launchctl bootout system/com.user.ackeepawake 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.user.ackeepawake.plist
launchctl bootout "gui/$UID_NUM/com.user.lidbrightness" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" /Library/LaunchAgents/com.user.lidbrightness.plist

echo
echo "Installed."
echo "  - On AC power: stays awake automatically (lid open or closed)."
echo "  - On battery : run 'keepawake' to stay awake; Ctrl+C to stop."
echo "  - Lid closed : backlight dims to 0; opens -> restores your level."
