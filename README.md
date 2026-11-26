# Wallpaper Rotation

A bar widget and drop-down panel for controlling Omarchy's wallpaper rotation.
It manages the existing `omarchy-bg-rotate.timer` user systemd timer — it does
not start a second Quickshell process and does not replace the stock rotation
script.

## What it does

- Shows the current theme, wallpaper count and an Active/Paused indicator.
- Sets the rotation interval from presets (1, 2, 5, 10, 15, 30, 60 minutes) or a
  custom value from 1 to 240 minutes.
- Pauses/resumes rotation by disabling/enabling the timer.
- Forces one immediate rotation ("Next wallpaper").
- Resets to the 5-minute default.

Click the cloud icon in the bar to open the panel. Escape closes it.

## How it works

`scripts/rotatectl.sh` writes a systemd override at
`~/.config/systemd/user/omarchy-bg-rotate.timer.d/override.conf`, reloads the
user systemd manager and restarts the timer if it was running. Status is
reported to QML as JSON. No state is written inside the plugin directory (that
would trigger an endless shell hot-reload); the remembered interval goes to
`~/.local/state/omarchy/shaun.wallpaper-rotator/settings.json`.

## Install

```sh
omarchy plugin add https://github.com/a77lic7ion/omarchy-wallpaper-rotator.git --enable
```

Or, for a local copy, add `shaun.wallpaper-rotator` to `plugins[]` and to a section
of `bar.layout` in `~/.config/omarchy/shell.json`, then:

```sh
omarchy restart shell
```

## Themes and local folders

The panel lists every installed theme (user themes under
`~/.config/omarchy/themes/` and stock themes under `$OMARCHY_PATH/themes/`)
with a checkbox and its image count. Check one or more to rotate across all of
their backgrounds; check none to rotate only the active theme (stock
behaviour). **All** / **None** are shortcuts.

**Add folder** opens a directory picker. Images and videos in the top level of
each added folder join the rotation pool too. Counts and the background list
are shared between the panel and the rotator via `scripts/theme-lib.sh`, so
they always agree; duplicate paths are de-duplicated.

A user systemd service override at
`~/.config/systemd/user/omarchy-bg-rotate.service.d/override.conf` points the
stock timer at `scripts/rotate.sh`, which walks the selected themes/folders,
finds the current wallpaper symlink and calls `omarchy-theme-bg-set` on the
next file. Packaged Omarchy files are never edited.

## Remove

```sh
omarchy plugin disable shaun.wallpaper-rotator
omarchy plugin remove shaun.wallpaper-rotator
```

Then remove the id from `plugins[]` and `bar.layout` in
`~/.config/omarchy/shell.json` if it is still there, and run
`omarchy restart shell`. To restore the stock 5-minute timer and stock rotate
script, use the panel's **Reset to 5 min default** and **None**, remove any
added folders, then delete both overrides under
`~/.config/systemd/user/omarchy-bg-rotate.timer.d/override.conf` and
`~/.config/systemd/user/omarchy-bg-rotate.service.d/override.conf` and run
`systemctl --user daemon-reload`.

## Requirements

- Omarchy with the Quattro shell (bar-widget plugin kind).
- The stock `omarchy-bg-rotate.timer` / `omarchy-bg-rotate.service` user units.
- No external packages; only bash, coreutils, find, sed and systemctl.
