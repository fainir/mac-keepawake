#!/bin/bash
# mac-keepawake installer.  Run as your normal user (NOT with sudo) - it will
# ask for your password when it needs root.  Safe to re-run.
set -euo pipefail

[ "$(uname)" = "Darwin" ] || { echo "macOS only."; exit 1; }
[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user (no sudo); it will prompt when needed."; exit 1; }

USER_NAME="$(id -un)"
UID_NUM="$(id -u)"
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$HOME/Library/Application Support/mac-keepawake"
SAVED="$STATE_DIR/pre-install-settings"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/mac-keepawake.XXXXXX")"   # private (0700) build dir, not a guessable path
trap 'rm -rf "$BUILD"' EXIT

echo "==> Checking Xcode command line tools (needed to build the brightness helper)..."
if ! xcode-select -p >/dev/null 2>&1; then
  echo "    Missing. Run:  xcode-select --install   then re-run ./install.sh"; exit 1
fi

echo "==> Compiling dsbright (DisplayServices brightness helper)..."
clang -O2 -o "$BUILD/dsbright" "$HERE/src/dsbright.c" -framework CoreGraphics

echo "==> Installing binaries to /usr/local/bin ..."
sudo mkdir -p /usr/local/bin
sudo install -m 755 -o root -g wheel "$BUILD/dsbright"             /usr/local/bin/dsbright
sudo install -m 755 -o root -g wheel "$HERE/src/keepawake"         /usr/local/bin/keepawake
sudo install -m 755 -o root -g wheel "$HERE/src/ac-keepawake.sh"   /usr/local/bin/ac-keepawake.sh
sudo install -m 755 -o root -g wheel "$HERE/src/lid-brightness.sh" /usr/local/bin/lid-brightness.sh

echo "==> Allowing passwordless 'pmset -a disablesleep 0|1' for keepawake (only those two commands, only you)..."
printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' "$USER_NAME" > "$BUILD/sudoers"
# Validate before it goes anywhere near /etc/sudoers.d - a broken file there breaks sudo.
visudo -cf "$BUILD/sudoers" >/dev/null || { echo "sudoers rule failed validation; aborting."; exit 1; }
sudo install -m 440 -o root -g wheel "$BUILD/sudoers" /etc/sudoers.d/keepawake

echo "==> Installing launch services..."
sudo install -m 644 -o root -g wheel "$HERE/src/com.user.ackeepawake.plist"   /Library/LaunchDaemons/com.user.ackeepawake.plist
sudo install -m 644 -o root -g wheel "$HERE/src/com.user.lidbrightness.plist" /Library/LaunchAgents/com.user.lidbrightness.plist

# Remember the settings we are about to change so uninstall.sh can put them back.
# Only on the first install: a re-run must not record our own values as "previous".
if [ ! -f "$SAVED" ]; then
  prev_ds="$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{ac=1; next} /^[^ ]/{ac=0} ac && $1=="displaysleep" && !n{print $2; n=1}' || true)"
  prev_idle="$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || true)"
  # Both already 0 = most likely an older mac-keepawake install; let uninstall use macOS defaults.
  if [ "$prev_ds" = "0" ] && [ "$prev_idle" = "0" ]; then prev_ds=""; prev_idle=""; fi
  mkdir -p "$STATE_DIR"
  printf 'displaysleep=%s\nidleTime=%s\n' "$prev_ds" "$prev_idle" > "$SAVED"
  echo "==> Saved your current settings (displaysleep=${prev_ds:-default}, screensaver idleTime=${prev_idle:-default}) for uninstall."
fi

echo "==> Display settings: AC display never sleeps + screen saver off (no lock screen)..."
sudo pmset -c displaysleep 0
defaults -currentHost write com.apple.screensaver idleTime -int 0

echo "==> Loading daemon + agent..."
sudo launchctl bootout system/com.user.ackeepawake 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.user.ackeepawake.plist
launchctl bootout "gui/$UID_NUM/com.user.lidbrightness" 2>/dev/null || true
if ! launchctl bootstrap "gui/$UID_NUM" /Library/LaunchAgents/com.user.lidbrightness.plist 2>/dev/null; then
  # No GUI session (e.g. installing over SSH while logged out): launchd starts it at next login.
  echo "    Lid/brightness agent will start at your next login (no GUI session right now)."
fi

echo
echo "Installed."
echo "  - On AC power: stays awake automatically (lid open or closed)."
echo "  - On battery : run 'keepawake' to stay awake; Ctrl+C to stop."
echo "  - Lid closed : backlight dims to 0; opens -> restores your level."
echo "  - To undo everything: ./uninstall.sh"
