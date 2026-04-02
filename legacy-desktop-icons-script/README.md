# Desktop Icon Position — Shell Script (Legacy)

> **Note:** This shell script is the original implementation of the icon position manager. The recommended tool is now the [macOS menu bar app](../macos-app/). The script remains functional and is useful for automation, scripting, or environments where the app can't be installed.

## License

This script is covered by the repository's [personal-use license](../LICENSE). You
may use and modify it for your own private personal purposes only.

You may not redistribute this script or any modified version, and you may not
use it for commercial, business, organizational, or revenue-generating purposes
without prior written permission. Commercial licensing inquiries:
[gmlupatelli@gmail.com](mailto:gmlupatelli@gmail.com).

## Quick Start

```bash
# Make the script executable
chmod +x legacy-desktop-icons-script/desktop_icons.sh

# Save icon positions while docked to external monitor
./legacy-desktop-icons-script/desktop_icons.sh save docked

# ... disconnect your external monitor ...

# Restore — icons auto-converted for single display!
./legacy-desktop-icons-script/desktop_icons.sh restore docked
```

## Auto Profiles

Auto profiles use a display fingerprint (MD5 hash of display geometry) to automatically match the right profile for your current setup:

```bash
# Save a profile tagged to your current display configuration
./legacy-desktop-icons-script/desktop_icons.sh save auto

# Restore — automatically finds the profile matching your current displays
./legacy-desktop-icons-script/desktop_icons.sh restore auto

# Watch mode — auto-selects the right profile on any display change
./legacy-desktop-icons-script/desktop_icons.sh watch auto
```

## Commands

| Command | Description |
|---------|-------------|
| `save <profile>` | Save icon positions + display geometry + settings |
| `save auto` | Save with auto-detected display fingerprint |
| `restore <profile>` | Smart restore — auto-converts if displays changed |
| `restore auto` | Restore matching profile for current displays |
| `convert <src> <dst>` | Convert and save as a new profile for current displays |
| `list <profile>` | Show saved positions, settings, and fingerprint |
| `profiles` | List all saved profiles with fingerprints |
| `watch <profile>` | Auto-restore when display geometry changes (polls every 3s) |
| `watch auto` | Auto-restore using display fingerprint matching |
| `count` | Show current display count and geometry |

## Requirements

- macOS (tested on macOS with Finder)
- Terminal must have **Accessibility / Automation** permissions (System Settings > Privacy & Security)

## Profile Format

Profiles are stored at `~/.desktop_icon_profiles/<name>.txt` in a pipe-delimited format:

```
#FINGERPRINT|566459849ad08e7084399efd0414acb8
#DISPLAY|0|0|1792|1120
#DISPLAY|912|-1080|1920|1080
#SETTINGS|60|12
filename.txt|1960|50
photo.jpg|2000|150
```

- `#FINGERPRINT|<md5>` — MD5 hash of sorted display geometry for auto-profile matching
- `#DISPLAY|originX|originY|width|height` — Display geometry at save time (Quartz/CG coordinates)
- `#SETTINGS|iconSize|textSize` — Finder icon and text size at save time
- Other lines: `iconName|x|y` positions

## Anti-Drift Measures

The script uses several techniques (inspired by [Desktop Icon Manager](https://github.com/com-entonos/Desktop-Icon-Manager)) to prevent macOS from rearranging icons after restore:

1. **Disables Finder arrangement** — Turns off "Snap to Grid" before restoring
2. **Restores icon/text size** — Prevents Finder from recalculating layout
3. **Batch placement** — Sets all positions in a single AppleScript call wrapped in `ignoring application responses`
4. **Post-restore verification** — Waits 3 seconds, re-reads positions, and batch-corrects drift

## Compatibility with the macOS App

The script and app share the same `~/.desktop_icon_profiles/` directory. Key differences:

| | Shell Script | macOS App |
|---|---|---|
| Profile format written | `.txt` (pipe-delimited) | `.json` |
| Profile format read | `.txt` only | `.txt` and `.json` |
| Auto-profile prefix | `auto_` | `Auto-` |
| Display change detection | Polling (3s interval) | `NSApplication.didChangeScreenParametersNotification` |

The macOS app can read profiles saved by the script. The script cannot read JSON profiles saved by the app.

## Key Functions

| Function | Purpose |
|----------|---------|
| `get_display_frames()` | JXA/NSScreen to get display geometry in CG coords |
| `get_display_count()` | JXA/NSScreen to get display count |
| `get_display_fingerprint()` | MD5 hash of sorted display geometry |
| `find_display_for_point()` | Determine which display contains a point |
| `remap_coordinates()` | Core conversion — remap icons to new display layout |
| `find_profile_for_fingerprint()` | Scan profiles for matching fingerprint |
| `cmd_restore()` | Full restore: settings, arrangement, positions, verify |
| `cmd_watch()` | Poll for display changes, auto-restore |
