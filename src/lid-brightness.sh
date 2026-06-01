#!/bin/bash
# lid-brightness: when the lid closes, dim the backlight to 0 to save power/heat
# (the framebuffer keeps rendering, so screen-sharing / computer-use still work).
# When the lid opens, restore the exact previous brightness.
DSB=/usr/local/bin/dsbright
STATE=/tmp/.lid_brightness_saved
last=""
get_lid(){ ioreg -r -k AppleClamshellState 2>/dev/null | grep -o '"AppleClamshellState" = [A-Za-z]*' | awk 'NR==1{print $3}'; }
while :; do
  cs=$(get_lid)
  if [ -n "$cs" ] && [ "$cs" != "$last" ]; then
    if [ "$cs" = "Yes" ]; then
      b=$("$DSB" g 2>/dev/null)
      if [ -n "$b" ] && awk "BEGIN{exit !($b>0.05)}"; then echo "$b" > "$STATE"; fi
      "$DSB" s 0 2>/dev/null
      echo "$(date '+%F %T') lid CLOSED  -> saved $(cat $STATE 2>/dev/null), dimmed to 0"
    else
      b=$(cat "$STATE" 2>/dev/null)
      [ -n "$b" ] && "$DSB" s "$b" 2>/dev/null
      echo "$(date '+%F %T') lid OPENED  -> restored ${b:-(none)}"
    fi
    last="$cs"
  fi
  sleep 1
done
