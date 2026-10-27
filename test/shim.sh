#!/bin/bash
# Fake system command for the tests. test/run.sh symlinks it as sudo, pmset,
# ioreg, launchctl, defaults, dsbright, ... and puts only those links (plus a few
# harmless real tools) on PATH. Every call is appended to $KA_T/calls. Nothing is
# ever executed for real: "sudo install"/"sudo rm" act on the fake root $KA_T/root.
name=${0##*/}
T=${KA_T:?KA_T must point at the test sandbox}
echo "$name $*" >> "$T/calls"

case $name in
  sudo)
    [ "${1:-}" = "-n" ] && shift
    [ -f "$T/sudo_fail" ] && { echo "sudo: a password is required" >&2; exit 1; }
    case ${1:-} in
      install)  # sudo install [opts] SRC DST -> copy into the fake root
        args=("$@"); n=${#args[@]}
        dst="$T/root${args[n-1]}"
        /bin/mkdir -p "${dst%/*}" && /bin/cp "${args[n-2]}" "$dst" ;;
      rm)
        shift
        for p in "$@"; do case $p in -*) ;; *) /bin/rm -f "$T/root$p" ;; esac; done ;;
    esac
    exit 0 ;;
  pmset)
    case "$*" in
      "-g ps")
        if [ "$(/bin/cat "$T/power" 2>/dev/null)" = AC ]; then
          echo "Now drawing from 'AC Power'"
        else
          echo "Now drawing from 'Battery Power'"
        fi
        echo " -InternalBattery-0 (id=123)	80%; charged; 0:00 remaining present: true" ;;
      "-g custom") /bin/cat "$T/pmset_custom" ;;
    esac
    exit 0 ;;
  ioreg)
    lid=$(/bin/cat "$T/lid" 2>/dev/null)
    [ -n "$lid" ] && printf '+-o IOPMrootDomain  <class IOPMrootDomain>\n    {\n      "AppleClamshellCausesSleep" = No\n      "AppleClamshellState" = %s\n    }\n' "$lid"
    exit 0 ;;
  dsbright)
    case ${1:-} in
      g) [ -f "$T/brightness" ] || { echo "dsbright: no built-in display online" >&2; exit 5; }
         /bin/cat "$T/brightness" ;;
      s) echo "$2" > "$T/brightness" ;;
    esac
    exit 0 ;;
  defaults)  # defaults -currentHost read|write|delete com.apple.screensaver idleTime [-int N]
    case ${2:-} in
      read)   [ -f "$T/idle" ] || exit 1; /bin/cat "$T/idle" ;;
      write)  echo "${6:-}" > "$T/idle" ;;
      delete) [ -f "$T/idle" ] || exit 1; /bin/rm -f "$T/idle" ;;
    esac
    exit 0 ;;
  launchctl)
    if [ "${1:-}" = bootstrap ] && [ -f "$T/no_gui" ]; then
      case ${2:-} in gui/*) echo "Bootstrap failed: 125: Domain does not support specified action" >&2; exit 125 ;; esac
    fi
    exit 0 ;;
  clang)  # create whatever -o names, so install.sh has something to copy
    while [ $# -gt 0 ]; do [ "$1" = -o ] && { : > "$2"; break; }; shift; done
    exit 0 ;;
  rm)  # only ever delete inside the sandbox
    for p in "$@"; do
      case $p in -*) ;; "$T"/*) /bin/rm -rf "$p" ;; *) echo "rm-skipped $p" >> "$T/calls" ;; esac
    done
    exit 0 ;;
  uname) echo Darwin ;;
  id)
    case ${1:-} in
      -u)  /bin/cat "$T/uid" 2>/dev/null || echo 501 ;;
      -un) echo tester ;;
    esac ;;
  caffeinate) exec /bin/sleep 30 ;;  # stays alive so keepawake has a real pid to kill
  pkill) exit 1 ;;                   # "no process matched"
  pgrep) [ -f "$T/keepawake_running" ] ;;
  *) exit 0 ;;                       # xcode-select and anything else: succeed quietly
esac
