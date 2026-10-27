#!/bin/bash
# ac-keepawake: keep this Mac awake (lid open OR closed) whenever on AC power.
# On battery, restore normal sleep. Only acts on actual power-source CHANGES, so
# a manual override on battery (e.g. `keepawake`) is preserved until you plug/unplug.
PMSET=/usr/bin/pmset
GREP=/usr/bin/grep
DATE=/bin/date
PGREP=/usr/bin/pgrep
# A running `keepawake` owns disablesleep: unplugging must not switch it off underneath it.
KEEPAWAKE_RE='^(/bin/)?bash /usr/local/bin/keepawake( |$)'
last=""
apply() {
  local src
  if "$PMSET" -g ps | "$GREP" -q "AC Power"; then src="AC"; else src="BATT"; fi
  if [ "$src" != "$last" ]; then
    last="$src"
    if [ "$src" = "AC" ]; then
      "$PMSET" -a disablesleep 1
      echo "$("$DATE" '+%Y-%m-%d %H:%M:%S') AC -> disablesleep 1 (awake, lid open/closed)"
    elif "$PGREP" -qf "$KEEPAWAKE_RE"; then
      echo "$("$DATE" '+%Y-%m-%d %H:%M:%S') BATTERY -> keepawake running, leaving disablesleep 1"
    else
      "$PMSET" -a disablesleep 0
      echo "$("$DATE" '+%Y-%m-%d %H:%M:%S') BATTERY -> disablesleep 0 (normal sleep)"
    fi
  fi
}
main() {
  apply
  "$PMSET" -g pslog | while read -r _; do apply; done
}
# Run only when executed (the tests source this file to call apply directly).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
