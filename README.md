# mac-keepawake

[![CI](https://github.com/fainir/mac-keepawake/actions/workflows/ci.yml/badge.svg)](https://github.com/fainir/mac-keepawake/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Keep your Mac fully awake - **even with the lid closed** - and dim the backlight while it's shut. For people who drive a MacBook remotely (SSH, screen sharing, Claude Code Remote Control) with the lid down.

macOS sleeps the moment you close the lid unless you have an external display attached, and `caffeinate` can't stop that, nor the display sleeping into a lock screen. mac-keepawake wires up the missing pieces with a few shell scripts, a tiny C helper and two `launchd` jobs:

- **On AC power:** stays awake automatically, lid open or closed. No commands.
- **On battery:** run `keepawake` to stay awake (Ctrl+C to stop). It keeps going if you unplug while it runs.
- **Lid closed:** the backlight drops to 0 to save power and heat, while the screen keeps *rendering* - so screen sharing / remote control / "computer use" still work. Open the lid and your exact brightness comes back.
- **No login wall:** the screen never sleeps or locks while it's meant to be awake, so you return to your desktop, not a password prompt.

![mac-keepawake demo](assets/demo.gif)

> The backlight dimming is a *physical* effect (the framebuffer keeps rendering), so it can't be screen-recorded - this terminal demo shows the controls and live output instead.

## What it changes on your Mac

Read this before installing. Everything here is undone by `./uninstall.sh`.

| Change | Where | What `uninstall.sh` does |
|--------|-------|--------------------------|
| `disablesleep 1` while on AC (no sleep at all, lid included); `0` on battery | system power setting, driven by a root LaunchDaemon | sets it back to `0` |
| Display never sleeps on AC (`pmset -c displaysleep 0`) | system power setting | restores your previous value (saved at install), or 10 min |
| Screen saver off (`idleTime 0`) | your user's screen-saver prefs | restores your previous value, or the macOS default |
| Passwordless `sudo pmset -a disablesleep 0` and `... 1` - those two commands only, your user only | `/etc/sudoers.d/keepawake` | removes it |
| `keepawake`, `dsbright`, `ac-keepawake.sh`, `lid-brightness.sh` | `/usr/local/bin/` | removes them |
| LaunchDaemon `com.user.ackeepawake` (root, watches the power source) | `/Library/LaunchDaemons/` | stops and removes it |
| LaunchAgent `com.user.lidbrightness` (runs in each user's login session, watches the lid) | `/Library/LaunchAgents/` | stops it (which restores the backlight if it was dimmed) and removes it |
| Logs and state | `/var/log/ac-keepawake.log`, `/tmp/lid-brightness.log`, `~/Library/Application Support/mac-keepawake/` | removes them |

Things to know:

- **Heat:** a closed lid traps heat. On AC on a desk it's fine; don't run heavy CPU loads with the lid shut in a bag or on a bed.
- **Battery:** `keepawake` on battery drains faster than normal sleep would. Plug in for long sessions.
- **No auto-lock on AC:** with display sleep and the screen saver off, the Mac never locks itself while plugged in. Anyone who opens the lid gets your desktop. Lock it yourself (Ctrl+Cmd+Q) when you walk away from it in public.
- **Root access:** the installer uses `sudo` once; afterwards only `pmset -a disablesleep 0|1` can run without a password.

## Requirements

- macOS 11+ (built and tested on Apple Silicon / M1; Intel Macs should work but are untested)
- Xcode Command Line Tools, to compile the small brightness helper: `xcode-select --install`
- An admin account (the installer uses `sudo`)

## Install

```bash
git clone https://github.com/fainir/mac-keepawake.git
cd mac-keepawake
./install.sh
```

Run it as your normal user - it asks for your password when it needs root. It's active immediately and after every reboot/login, and it's safe to re-run (e.g. after pulling an update). Installing over SSH while nobody is logged in to the desktop works too; the brightness agent then starts at your next login.


Or with Homebrew (same installer, run once after `brew install`):

```bash
brew install fainir/tap/mac-keepawake
mac-keepawake-install
```

Undo with `mac-keepawake-uninstall`.

## Usage

**On the charger:** nothing to do. Close the lid, walk away - it stays awake and reachable, and you come back to a live desktop.

**On battery:**

```console
$ keepawake
[keepawake ON: screen stays on, awake lid open/closed, survives unplug. Press Ctrl+C to stop.]
^C
[keepawake stopped - control returned to the automatic daemon]
```

Keeps the Mac awake (lid open or closed), screen on, no lock. Press **Ctrl+C** (or close the terminal window) to stop and return to normal battery sleep. Start it while plugged in and then unplug - it keeps going.

**Brightness** is automatic (dims on lid-close, restores on open), but you can also drive the built-in display directly:

```bash
dsbright g        # read brightness (0.0 - 1.0)
dsbright s 0.5    # set brightness (0.0 - 1.0; anything else is rejected)
```

## Check that it's working

```bash
pmset -g | grep SleepDisabled     # 1 = won't sleep, 0 = normal
cat /var/log/ac-keepawake.log     # AC/battery transitions
cat /tmp/lid-brightness.log       # lid open/close + brightness restore
```

The logs have one line per event, e.g. `AC -> disablesleep 1 (awake, lid open/closed)` or `lid CLOSED  -> saved 0.6000, dimmed to 0`.

## Uninstall

```bash
./uninstall.sh
```

Stops everything, removes every file listed above, and puts sleep, display sleep and the screen saver back the way they were before you installed. It's safe to run more than once.

**Mac won't sleep on battery?** If `keepawake` was killed hard (`kill -9`, a crash) it can't clean up, and sleep stays disabled until the next plug/unplug. Fix it right away with:

```bash
sudo pmset -a disablesleep 0
```

## How it works

Four small pieces in `/usr/local/bin`, wired through `launchd`:

- **`ac-keepawake.sh`** - LaunchDaemon (root). Watches the power source with `pmset -g pslog`; sets `disablesleep 1` on AC (awake, lid included), `0` on battery - unless `keepawake` is running, which then owns the setting.
- **`keepawake`** - foreground battery command. Holds `caffeinate -d` (display) and re-asserts `disablesleep 1` every 2s; on exit it puts back whatever the daemon would have set for the current power source.
- **`lid-brightness.sh`** - LaunchAgent (your session). Polls the lid once a second via `ioreg AppleClamshellState`; saves and zeroes the brightness on close, restores it on open, and also restores it if the agent is stopped while the lid is shut.
- **`dsbright`** - a small C helper that reads/sets the built-in display's brightness through the private `DisplayServices` framework - the only reliable way on Apple Silicon, where the old IOKit brightness API returns "unsupported". It never touches external monitors.

The installer also sets `pmset -c displaysleep 0` and turns the screen saver off, so the machine never drops to the lock screen while it's supposed to stay awake.

## Limitations

- **Private API:** `dsbright` uses `DisplayServices`, a private framework - stable in practice, but Apple could change it in a major macOS release. If brightness control ever breaks, everything else still works.
- **External displays:** `dsbright` only ever adjusts the built-in panel, so closing the lid with a monitor attached (where the monitor becomes the "main" display) never dims the monitor. If it can't read the built-in panel's brightness, the agent leaves the backlight alone rather than dimming it with no way back.
- **Computer use with the lid closed:** the framebuffer keeps rendering even at backlight 0, so screenshots/clicks work headless. If you have *no* external display and your Mac fully powers the panel off, attach a cheap HDMI "dummy" display.
- **Multiple users:** the brightness agent runs for every account that logs in, but the passwordless `pmset` rule and the screen-saver change only apply to the user who ran `install.sh`.

## Or just build it with a coding agent (Claude Code, Codex, etc.)

Don't want to clone this? Paste the prompt below into a terminal coding agent running on your Mac - Claude Code, Codex, Cursor, anything - and it'll build the same system from scratch. The non-obvious macOS gotchas are baked into the prompt so it won't waste time going down dead ends:

```
Build a macOS tool that keeps my Mac fully awake - including when the lid is
closed - for headless/remote use (I drive it from my phone over SSH / Claude
Code Remote Control).

Requirements:
1. On AC power: stay awake automatically, lid open OR closed, no command needed,
   and it must survive a reboot.
2. On battery: a command called `keepawake` that I run in Terminal to keep it
   awake (lid open or closed); Ctrl+C stops it and returns to normal sleep. It
   must keep working if I start it while plugged in and then unplug.
3. While it is awake the screen must NOT lock or show the login page - I should
   come back to my live desktop.
4. When the lid closes, drop the backlight to minimum to save power and heat,
   and restore my exact previous brightness when it opens. The screen must keep
   rendering at minimum backlight so screenshots / screen-sharing still work.

macOS specifics to save you time (these are the non-obvious parts):
- `sudo pmset disablesleep 1` is the ONLY setting that keeps the system awake
  with the lid closed. It is a global flag and does not reliably persist across
  reboot, so drive it from a root LaunchDaemon (RunAtLoad + KeepAlive) that sets
  it from the power source: read state with `pmset -g ps`, react to changes with
  `pmset -g pslog`.
- `disablesleep` does NOT stop display sleep or the lock screen. To kill the
  login page, also run `sudo pmset -c displaysleep 0` and disable the screen
  saver: `defaults -currentHost write com.apple.screensaver idleTime -int 0`.
- Read lid state with `ioreg -r -k AppleClamshellState` (value "Yes" = closed).
- On Apple Silicon the `brightness` Homebrew tool and the legacy IOKit brightness
  API both fail with "unsupported" (error -536870201). Use the PRIVATE
  DisplayServices framework instead: DisplayServicesGetBrightness(CGDirectDisplayID,
  float*) and DisplayServicesSetBrightness(CGDirectDisplayID, float). Write a tiny
  C helper that dlopen()s
  /System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices, and
  run the lid/brightness watcher as a LaunchAgent (user GUI session - DisplayServices
  will not work from a root daemon).
- `keepawake` should hold `caffeinate -d` for the display and re-assert
  `disablesleep 1` every ~2s so it overrides the daemon the instant I unplug; on
  exit it should restore power-appropriate state.

Deliver: the daemon + watcher scripts, the C helper, launchd plists (a
LaunchDaemon for the power piece and a LaunchAgent for brightness), an idempotent
install.sh and an uninstall.sh that restores defaults, and a README. Validate
before finishing: bash -n on the scripts, plutil -lint on the plists, and compile
the helper.
```

## Development

```bash
./test/run.sh
```

Runs `bash -n`, `shellcheck` (if installed), `plutil -lint` on the plists, a strict `clang` build of `dsbright`, and the behaviour tests for the daemon, `keepawake`, the lid agent, `install.sh` and `uninstall.sh`. The tests are hermetic: every system command (`sudo`, `pmset`, `ioreg`, `launchctl`, `defaults`, `dsbright`, ...) is replaced by a logging stand-in from `test/shim.sh` on a locked-down `PATH`, with a temporary `HOME` and a fake root, so running them never changes your Mac's settings. CI runs the same script on `macos-latest`.

## License

MIT - see [LICENSE](LICENSE).

---

### More open source by [Nir Feinstein](https://nirfeinste.in)

- [agent-harness](https://github.com/fainir/agent-harness) - make Claude Code or Codex act as a product team, a CEO or a portfolio manager
- [frugal](https://github.com/fainir/frugal) - your agent finds the cheaper honest way before it pays for anything
- [flipback](https://github.com/fainir/flipback) - an automatic `/goal` for every turn: sends Claude Code back when it stops early
- [recall](https://github.com/fainir/recall) - your Claude Code memory in every agent, over MCP
- [All projects](https://nirfeinste.in/#open-source)
