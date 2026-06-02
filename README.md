# mac-keepawake

Keep your Mac fully awake - **even with the lid closed** - and dim the backlight while it's shut.

- **On AC power:** stays awake automatically, lid open or closed. No commands.
- **On battery:** run `keepawake` to stay awake (Ctrl+C to stop). It even survives unplugging.
- **Lid closed:** the backlight drops to 0 to save power and heat, while the screen keeps *rendering* - so screen sharing / remote control / "computer use" still work. Open the lid and your exact brightness comes back.
- **No login wall:** the screen never sleeps or locks while it's meant to be awake, so you return to your desktop, not a password prompt.

Built for headless / remote workflows - e.g. driving the Mac from your phone (Claude Code Remote Control, SSH, screen sharing) with the lid shut.

## Why

macOS gives you blunt options: either it sleeps when you close the lid, or you keep the whole display blazing. `caffeinate` stops *system* sleep but not display sleep or the lock screen - and it can't keep the machine awake with the lid closed at all. This wires up the missing pieces:

| Goal | How |
|------|-----|
| Stay awake with the lid **closed** | `pmset disablesleep` (toggled automatically) |
| Never sleep / lock the screen on AC | `pmset displaysleep 0` + screen saver off |
| Stay awake on battery, on demand | the `keepawake` command |
| Dim the backlight while the lid is shut | a tiny `DisplayServices` helper (`dsbright`) |

## Requirements

- macOS 11+ (built and tested on Apple Silicon / M1; Intel Macs should work too)
- Xcode Command Line Tools, to compile the ~20-line brightness helper: `xcode-select --install`
- An admin account (the installer uses `sudo`)

## Install

```bash
git clone https://github.com/fainir/mac-keepawake.git
cd mac-keepawake
./install.sh
```

Run it as your normal user - it asks for your password when it needs root. It's active immediately and after every reboot/login.

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

## Usage

**On the charger:** nothing to do. Close the lid, walk away - it stays awake and reachable, and you come back to a live desktop.

**On battery:**
```bash
keepawake
```
Keeps the Mac awake (lid open or closed), screen on, no lock. Press **Ctrl+C** to stop and return to normal battery sleep. Start it while plugged in and then unplug - it keeps going.

**Brightness** is automatic (dims on lid-close, restores on open), but you can also drive it directly:
```bash
dsbright g        # read brightness (0.0 - 1.0)
dsbright s 0.5    # set brightness
```

## How it works

Four small pieces in `/usr/local/bin`, wired through `launchd`:

- **`ac-keepawake.sh`** - LaunchDaemon (root). Watches the power source with `pmset -g pslog`; sets `disablesleep 1` on AC (awake, lid included), `0` on battery.
- **`keepawake`** - foreground battery command. Holds `caffeinate -d` (display) and re-asserts `disablesleep 1` every 2s so it survives an unplug; restores normal behavior on Ctrl+C.
- **`lid-brightness.sh`** - LaunchAgent (your session). Polls the lid via `ioreg AppleClamshellState`; saves & zeroes brightness on close, restores it on open.
- **`dsbright`** - a ~20-line C helper that reads/sets brightness through the private `DisplayServices` framework - the only reliable way on Apple Silicon, where the old IOKit brightness API returns "unsupported".

The installer also sets `pmset -c displaysleep 0` and turns the screen saver off, so the machine never drops to the lock screen while it's supposed to stay awake.

## Verify

```bash
cat /var/log/ac-keepawake.log     # AC/battery transitions
cat /tmp/lid-brightness.log       # lid open/close + brightness restore
pmset -g | grep SleepDisabled     # 1 = won't sleep, 0 = normal
```

## Uninstall

```bash
./uninstall.sh
```
Removes everything and restores stock sleep / display / screen-saver behavior.

## Notes & caveats

- **Heat / battery:** a closed lid traps heat. On AC it's fine on a desk; don't run heavy CPU loads sealed in a bag. On battery, keep-awake drains faster - plug in for long sessions.
- **`disablesleep`** disables *all* sleep while active (that's what enables lid-closed operation). The daemon turns it back off automatically on battery.
- **Private API:** `dsbright` uses `DisplayServices`, a private framework - stable in practice, but Apple could change it in a major macOS release. If brightness control ever breaks, everything else still works.
- **sudoers:** the installer adds `/etc/sudoers.d/keepawake` allowing passwordless `/usr/bin/pmset` for your user, so `keepawake` never prompts mid-loop. `uninstall.sh` removes it.
- **Computer use with the lid closed:** the framebuffer keeps rendering even at backlight 0, so screenshots/clicks work headless. If you have *no* external display and your Mac fully powers the panel off, attach a cheap HDMI "dummy" display.

## License

MIT - see [LICENSE](LICENSE).
