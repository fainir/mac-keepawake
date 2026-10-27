#!/bin/bash
# lid-brightness: when the lid closes, dim the backlight to 0 to save power/heat
# (the framebuffer keeps rendering, so screen-sharing / computer-use still work).
# When the lid opens, restore the exact previous brightness. If the agent is
# stopped while the lid is closed (logout, uninstall), it restores on the way out.
DSB=/usr/local/bin/dsbright
[ -n "${HOME:-}" ] || HOME=$(cd ~ && pwd)
# Per-user state (not /tmp): it exists only while we have the backlight dimmed.
STATE_DIR="$HOME/Library/Application Support/mac-keepawake"
STATE="$STATE_DIR/brightness"
last=""
get_lid(){ ioreg -r -k AppleClamshellState 2>/dev/null | grep -o '"AppleClamshellState" = [A-Za-z]*' | awk 'NR==1{print $3}'; }
# Put back the brightness saved at lid-close (if any) and forget it.
restore() {
  b=$(cat "$STATE" 2>/dev/null)
  [ -n "$b" ] && "$DSB" s "$b" 2>/dev/null
  rm -f "$STATE"
}
check_lid() {
  cs=$(get_lid)
  if [ -n "$cs" ] && [ "$cs" != "$last" ]; then
    if [ "$cs" = "Yes" ]; then
      # Save only if not already dimmed (e.g. agent restarted with the lid shut).
      if [ ! -f "$STATE" ]; then
        b=$("$DSB" g 2>/dev/null)
        if [ -n "$b" ] && awk -v b="$b" 'BEGIN{exit !(b+0>0)}'; then mkdir -p "$STATE_DIR" && echo "$b" > "$STATE"; fi
      fi
      # Never darken the panel without a saved level to bring it back to.
      if [ -f "$STATE" ]; then
        "$DSB" s 0 2>/dev/null
        echo "$(date '+%F %T') lid CLOSED  -> saved $(cat "$STATE" 2>/dev/null), dimmed to 0"
      else
        echo "$(date '+%F %T') lid CLOSED  -> brightness unreadable or already 0, left as is"
      fi
    else
      restore
      echo "$(date '+%F %T') lid OPENED  -> restored ${b:-(none)}"
    fi
    last="$cs"
  fi
}
on_exit() {
  if [ -f "$STATE" ]; then
    restore
    echo "$(date '+%F %T') agent stopped -> restored ${b:-(none)}"
  fi
  exit 0
}
main() {
  trap on_exit TERM INT HUP
  # `sleep & wait` so a stop signal is handled at once, not after the sleep.
  while :; do check_lid; sleep 1 & wait $!; done
}
# Run only when executed (the tests source this file to call check_lid directly).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
