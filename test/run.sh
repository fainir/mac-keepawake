#!/bin/bash
# mac-keepawake test suite:  ./test/run.sh
#
# Hermetic: nothing here changes real power, display, sudo or launchd state.
# Scripts run with PATH set to ONLY test/shim.sh links (sudo, pmset, ioreg,
# launchctl, defaults, ...) plus a few harmless real tools, a temp HOME and a
# fake root; a command that is neither fails with "command not found" instead
# of reaching the real system. The absolute-path commands the scripts use
# ($PMSET, $PGREP, $DSB, $CAFFEINATE) are overridden after sourcing.
#
# Also runs bash -n, shellcheck, plutil -lint and a clang build of dsbright
# (never executed) when those tools exist; with CI=true they are required.
# shellcheck disable=SC2016  # single-quoted bash -c snippets expand inside the sandbox
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS=(install.sh uninstall.sh src/keepawake src/ac-keepawake.sh src/lid-brightness.sh test/run.sh test/shim.sh)
SAFE_TOOLS=(cat grep awk sed head mkdir dirname mktemp sleep date visudo)
SHIMS=(sudo pmset ioreg launchctl defaults dsbright clang xcode-select uname id caffeinate pkill pgrep rm)
pass=0; fail=0

ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
has()  { grep -qF -- "$2" "$1" 2>/dev/null; }      # has FILE TEXT
lacks() { ! has "$1" "$2"; }
count() { grep -cF -- "$2" "$1" 2>/dev/null; }     # count FILE TEXT
same() { [ "$1" = "$2" ] || { echo "       expected: $2"; echo "       actual:   $1"; return 1; }; }
need() {  # need TOOL: true if present; skip locally, fail on CI
  command -v "$1" >/dev/null 2>&1 && return 0
  if [ "${CI:-}" = true ]; then bad "$1 is required on CI"; else echo "  skip $1 not installed"; fi
  return 1
}

# Fresh sandbox in $T: shims, safe tools, fake root, temp HOME and TMPDIR.
new_sandbox() {
  T="$(mktemp -d)"
  mkdir -p "$T/shims" "$T/bin" "$T/root" "$T/home" "$T/tmp"
  local c
  for c in "${SHIMS[@]}"; do ln -s "$REPO/test/shim.sh" "$T/shims/$c"; done
  for c in "${SAFE_TOOLS[@]}"; do ln -s "$(command -v "$c")" "$T/bin/$c"; done
  : > "$T/calls"
  echo AC > "$T/power"
  set_ac_displaysleep 5
  echo 300 > "$T/idle"
  STATE_DIR="$T/home/Library/Application Support/mac-keepawake"
  # bash with a clean environment: only the sandbox PATH, HOME and TMPDIR.
  sbx=(env -i PATH="$T/shims:$T/bin" HOME="$T/home" TMPDIR="$T/tmp" KA_T="$T" /bin/bash)
}
in_sandbox() { "${sbx[@]}" "$@"; }
set_ac_displaysleep() {  # rewrite the `pmset -g custom` fixture
  printf 'Battery Power:\n displaysleep         2\n sleep                1\nAC Power:\n Sleep On Power Button 1\n displaysleep         %s\n sleep                1\n' "$1" > "$T/pmset_custom"
}
# Line number of the first call containing TEXT (0 if none).
line_of() { local n; n=$(grep -nF -- "$1" "$T/calls" | head -n 1 | cut -d: -f1); echo "${n:-0}"; }
before() { local a b; a=$(line_of "$1"); b=$(line_of "$2"); [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -lt "$b" ]; }
# Wait up to ~5s for FILE to contain TEXT.
wait_for() { local _; for _ in $(seq 50); do has "$1" "$2" && return 0; sleep 0.1; done; return 1; }

echo "== lint and build"
for f in "${SCRIPTS[@]}"; do check "bash -n $f" bash -n "$REPO/$f"; done
if need shellcheck; then
  check "shellcheck" shellcheck -x "${SCRIPTS[@]/#/$REPO/}"
fi
if need plutil; then
  for p in "$REPO"/src/*.plist; do check "plutil -lint ${p##*/}" plutil -lint -s "$p"; done
fi
if need clang; then
  B="$(mktemp -d)"
  check "dsbright.c builds with -Wall -Wextra -Werror (not run)" \
    clang -O2 -Wall -Wextra -Werror -o "$B/dsbright" "$REPO/src/dsbright.c" -framework CoreGraphics
  rm -rf "$B"
fi

echo "== launchd plists"
if need plutil; then
  for p in "$REPO"/src/*.plist; do
    f=${p##*/}
    label=$(plutil -extract Label raw -o - "$p")
    prog=$(plutil -extract ProgramArguments.0 raw -o - "$p")
    check "$f: Label matches file name" same "$label.plist" "$f"
    check "$f: RunAtLoad + KeepAlive" same "$(plutil -extract RunAtLoad raw -o - "$p") $(plutil -extract KeepAlive raw -o - "$p")" "true true"
    check "$f: program $prog is installed by install.sh" has "$REPO/install.sh" " $prog"
    check "$f: program $prog is removed by uninstall.sh" has "$REPO/uninstall.sh" "$prog"
    check "$f: plist is removed by uninstall.sh" has "$REPO/uninstall.sh" "/$f"
  done
fi

echo "== ac-keepawake (daemon)"
new_sandbox
ac_step() {  # ac_step LAST -> runs apply once, prints the new $last
  in_sandbox -c '. "$1"; PMSET="$KA_T/shims/pmset"; PGREP="$KA_T/shims/pgrep"; last=$2; apply >> "$KA_T/daemon.log"; echo "$last"' _ "$REPO/src/ac-keepawake.sh" "$1"
}
last=$(ac_step "")
check "on AC: sets disablesleep 1" same "$(count "$T/calls" "pmset -a disablesleep 1")" 1
last=$(ac_step "$last")
check "still on AC: does not re-apply" same "$(count "$T/calls" "pmset -a disablesleep")" 1
echo BATT > "$T/power"; last=$(ac_step "$last")
check "unplugged: sets disablesleep 0" same "$(count "$T/calls" "pmset -a disablesleep 0")" 1
check "logs each transition" same "$(grep -c 'disablesleep' "$T/daemon.log")" 2
# Unplugging while `keepawake` runs must not switch sleep back on underneath it.
: > "$T/calls"; echo AC > "$T/power"; last=$(ac_step "$last")
touch "$T/keepawake_running"; echo BATT > "$T/power"; last=$(ac_step "$last")
check "unplugged while keepawake runs: leaves disablesleep 1" lacks "$T/calls" "pmset -a disablesleep 0"
check "unplugged while keepawake runs: says so in the log" has "$T/daemon.log" "keepawake running"
check "looks for keepawake by its exact command line" has "$T/calls" "pgrep -qf ^(/bin/)?bash /usr/local/bin/keepawake( |\$)"
rm -rf "$T"

echo "== keepawake (battery command)"
new_sandbox
run_keepawake() {  # run keepawake's main() in the background (exec'd, so $! is that bash)
  "${sbx[@]}" -c '. "$1"; PMSET="$KA_T/shims/pmset"; CAFFEINATE="$KA_T/shims/caffeinate"; main' _ "$REPO/src/keepawake" > "$T/ka.out" 2>&1 &
  ka_pid=$!
}
in_sandbox "$REPO/install.sh" > /dev/null 2>&1   # only to get the sudoers rule it writes
rule_cmds=$(sed -n 's/.*NOPASSWD: //p' "$T/root/etc/sudoers.d/keepawake")
: > "$T/calls"
echo BATT > "$T/power"
run_keepawake
check "starts caffeinate -d (display awake)" wait_for "$T/calls" "caffeinate -d -w"
check "sets disablesleep 1" wait_for "$T/calls" "pmset -a disablesleep 1"
check "prints ON banner" wait_for "$T/ka.out" "keepawake ON"
kill -TERM "$ka_pid"; wait "$ka_pid"; rc=$?
check "stops cleanly on TERM (exit 0)" same "$rc" 0
check "on battery: hands back disablesleep 0" has "$T/calls" "pmset -a disablesleep 0"
check "prints stopped message" has "$T/ka.out" "keepawake stopped"
# Every root command keepawake ran must be covered by the installer's sudoers rule.
uncovered=0
while read -r line; do
  cmd=${line#sudo }; cmd=${cmd#-n }
  case $cmd in "$T/shims/pmset"*) cmd="/usr/bin/pmset${cmd#"$T/shims/pmset"}" ;; esac
  case ", $rule_cmds," in *", $cmd,"*) ;; *) echo "       not in sudoers rule: $cmd"; uncovered=1 ;; esac
done < <(grep '^sudo ' "$T/calls")
check "every sudo command it ran is allowed by the sudoers rule" same "$uncovered" 0
: > "$T/calls"; echo AC > "$T/power"
in_sandbox -c '. "$1"; PMSET="$KA_T/shims/pmset"; restore_power_state' _ "$REPO/src/keepawake"
check "on AC: hands back disablesleep 1 (non-interactive sudo)" has "$T/calls" "sudo -n $T/shims/pmset -a disablesleep 1"
: > "$T/calls"; touch "$T/sudo_fail"
run_keepawake; wait "$ka_pid"; rc=$?
check "sudo refused: exits 1" same "$rc" 1
check "sudo refused: explains why" has "$T/ka.out" "is mac-keepawake installed"
check "sudo refused: does not loop" same "$(count "$T/calls" "disablesleep 1")" 1
rm -rf "$T"

echo "== lid-brightness (agent)"
new_sandbox
lid_step() {  # lid_step LAST -> runs check_lid once, prints the new $last
  in_sandbox -c '. "$1"; DSB="$KA_T/shims/dsbright"; last=$2; check_lid >> "$KA_T/agent.log"; echo "$last"' _ "$REPO/src/lid-brightness.sh" "$1"
}
echo No > "$T/lid"; echo 0.6000 > "$T/brightness"
last=$(lid_step "")
check "lid open at start, nothing saved: brightness untouched" lacks "$T/calls" "dsbright s"
echo Yes > "$T/lid"; last=$(lid_step "$last")
check "lid closed: saves brightness per user (not /tmp)" same "$(cat "$STATE_DIR/brightness" 2>/dev/null)" 0.6000
check "lid closed: dims to 0" same "$(cat "$T/brightness")" 0
last=$(lid_step "")   # agent restarted (KeepAlive) while still closed
check "restart while closed: keeps the saved level" same "$(cat "$STATE_DIR/brightness" 2>/dev/null)" 0.6000
echo No > "$T/lid"; last=$(lid_step "$last")
check "lid opened: restores exact level" same "$(cat "$T/brightness")" 0.6000
check "lid opened: forgets the saved level" same "$([ -e "$STATE_DIR/brightness" ] && echo present || echo gone)" gone
echo 0.0300 > "$T/brightness"
echo Yes > "$T/lid"; last=$(lid_step "$last")
echo No > "$T/lid"; last=$(lid_step "$last")
check "low brightness (0.03) is restored too" same "$(cat "$T/brightness")" 0.0300
: > "$T/calls"; rm -f "$T/brightness"   # dsbright g fails (e.g. no built-in display online)
echo Yes > "$T/lid"; last=$(lid_step "$last")
check "brightness unreadable: does not dim blindly" lacks "$T/calls" "dsbright s 0"
check "brightness unreadable: says so in the log" has "$T/agent.log" "left as is"
: > "$T/calls"; rm -f "$T/lid"           # desktop Mac: no clamshell key at all
last=$(lid_step "")
check "no lid (desktop Mac): does nothing" lacks "$T/calls" "dsbright"
check "never uses a /tmp state file" lacks "$REPO/src/lid-brightness.sh" "/tmp/"
# Stopping the agent (logout / uninstall) while dimmed must bring the backlight back.
echo 0.7000 > "$T/brightness"; echo Yes > "$T/lid"
"${sbx[@]}" -c '. "$1"; DSB="$KA_T/shims/dsbright"; main' _ "$REPO/src/lid-brightness.sh" > "$T/agent.out" 2>&1 &
agent_pid=$!
check "agent loop dims on close" wait_for "$T/agent.out" "dimmed to 0"
kill -TERM "$agent_pid"; wait "$agent_pid"; rc=$?
check "agent stops cleanly on TERM (exit 0)" same "$rc" 0
check "agent stop while dimmed: restores brightness" same "$(cat "$T/brightness")" 0.7000
check "agent stop: logs the restore" has "$T/agent.out" "agent stopped -> restored 0.7000"
rm -rf "$T"

echo "== install.sh"
new_sandbox
in_sandbox "$REPO/install.sh" > "$T/install.out" 2>&1; rc=$?
check "install exits 0" same "$rc" 0
check "install: no 'command not found' (every command is shimmed)" lacks "$T/install.out" "command not found"
for f in /usr/local/bin/dsbright /usr/local/bin/keepawake /usr/local/bin/ac-keepawake.sh /usr/local/bin/lid-brightness.sh \
         /etc/sudoers.d/keepawake /Library/LaunchDaemons/com.user.ackeepawake.plist /Library/LaunchAgents/com.user.lidbrightness.plist; do
  check "install places $f" test -f "$T/root$f"
done
check "sudoers rule allows only 'pmset -a disablesleep 0|1' for this user" same "$(cat "$T/root/etc/sudoers.d/keepawake")" \
  "tester ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
check "sudoers rule passes visudo -cf" visudo -qcf "$T/root/etc/sudoers.d/keepawake"
check "sudoers file installed root:wheel 0440" has "$T/calls" "sudo install -m 440 -o root -g wheel"
check "dsbright is built in a private mktemp dir, not /tmp/dsbright" has "$T/calls" "clang -O2 -o $T/tmp/mac-keepawake."
check "build dir is cleaned up" same "$(ls -A "$T/tmp")" ""
check "install never deletes anything outside its own temp dir" lacks "$T/calls" "rm-skipped"
check "saves previous settings for uninstall" same "$(cat "$STATE_DIR/pre-install-settings" 2>/dev/null)" "$(printf 'displaysleep=5\nidleTime=300')"
check "sets AC displaysleep 0" has "$T/calls" "sudo pmset -c displaysleep 0"
check "turns the screen saver off" same "$(cat "$T/idle")" 0
check "loads the daemon" has "$T/calls" "sudo launchctl bootstrap system /Library/LaunchDaemons/com.user.ackeepawake.plist"
check "loads the agent" has "$T/calls" "launchctl bootstrap gui/501 /Library/LaunchAgents/com.user.lidbrightness.plist"
# Re-run: macOS now reports our own values (0), which must not overwrite the saved originals.
set_ac_displaysleep 0
touch "$T/no_gui"   # and pretend we are on SSH with nobody logged in to the GUI
in_sandbox "$REPO/install.sh" > "$T/install2.out" 2>&1; rc=$?
check "re-install exits 0 even with no GUI session" same "$rc" 0
check "re-install explains the agent starts at next login" has "$T/install2.out" "next login"
check "re-install keeps the original saved settings" same "$(cat "$STATE_DIR/pre-install-settings")" "$(printf 'displaysleep=5\nidleTime=300')"
rm -rf "$T"

new_sandbox   # upgrading from an older mac-keepawake: settings are already ours
set_ac_displaysleep 0; echo 0 > "$T/idle"
in_sandbox "$REPO/install.sh" > /dev/null 2>&1
check "upgrade over old install: records 'unknown' rather than 0" same "$(cat "$STATE_DIR/pre-install-settings")" "$(printf 'displaysleep=\nidleTime=')"
rm -rf "$T"

new_sandbox
echo 0 > "$T/uid"
in_sandbox "$REPO/install.sh" > "$T/install.out" 2>&1; rc=$?
check "install refuses to run as root" same "$rc" 1
check "install as root touches nothing" lacks "$T/calls" "sudo "
rm -rf "$T"

echo "== uninstall.sh"
new_sandbox
in_sandbox "$REPO/install.sh" > /dev/null 2>&1
: > "$T/calls"
in_sandbox "$REPO/uninstall.sh" > "$T/uninstall.out" 2>&1; rc=$?
check "uninstall exits 0" same "$rc" 0
check "uninstall: no 'command not found'" lacks "$T/uninstall.out" "command not found"
check "removes everything install placed" same "$(find "$T/root" -type f)" ""
check "restores disablesleep 0" has "$T/calls" "sudo pmset -a disablesleep 0"
check "restores the previous AC displaysleep (5)" has "$T/calls" "sudo pmset -c displaysleep 5"
check "restores the previous screen saver delay (300)" same "$(cat "$T/idle" 2>/dev/null)" 300
check "removes its per-user state" same "$([ -e "$STATE_DIR" ] && echo present || echo gone)" gone
check "stops a running keepawake first" before "pkill -f ^(/bin/)?bash /usr/local/bin/keepawake" "sudo rm -f /etc/sudoers.d/keepawake"
check "drops the sudoers rule before the final disablesleep 0" before "sudo rm -f /etc/sudoers.d/keepawake" "sudo pmset -a disablesleep 0"
check "stops the agent (which restores brightness)" has "$T/calls" "launchctl bootout gui/501/com.user.lidbrightness"
check "removes the daemon log" has "$T/calls" "/var/log/ac-keepawake.log"
in_sandbox "$REPO/uninstall.sh" > /dev/null 2>&1; rc=$?
check "uninstall is safe to re-run" same "$rc" 0
rm -rf "$T"

new_sandbox   # installed by an older version: no saved settings
rm -f "$T/idle"
in_sandbox "$REPO/uninstall.sh" > /dev/null 2>&1
check "no saved settings: AC displaysleep back to macOS default (10)" has "$T/calls" "sudo pmset -c displaysleep 10"
check "no saved settings: screen saver back to macOS default" has "$T/calls" "defaults -currentHost delete com.apple.screensaver idleTime"
rm -rf "$T"

new_sandbox   # tampered saved file must not reach sudo pmset
mkdir -p "$STATE_DIR"; printf 'displaysleep=5; touch /x\nidleTime=abc\n' > "$STATE_DIR/pre-install-settings"
in_sandbox "$REPO/uninstall.sh" > /dev/null 2>&1
check "garbage saved displaysleep: falls back to 10" has "$T/calls" "sudo pmset -c displaysleep 10"
check "garbage saved idleTime: falls back to macOS default" has "$T/calls" "defaults -currentHost delete com.apple.screensaver idleTime"
rm -rf "$T"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
