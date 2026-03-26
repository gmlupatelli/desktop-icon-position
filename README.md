# Desktop Icon Position Manager for macOS

Saves, converts, and restores desktop icon positions across different display configurations. Solves the macOS icon shuffle when connecting/disconnecting external monitors.

## The Problem

When a MacBook is connected to an external monitor and you arrange desktop icons on the MacBook screen, disconnecting the external display causes macOS to scramble all icon positions. This happens because macOS uses a global coordinate system that spans all displays — when a display is removed, the coordinate origin shifts and icons end up off-screen.

## How It Works

The script saves icon positions, display geometry, icon size, text size, and a display fingerprint together as a "profile." On restore, it:

1. Restores icon size and text size to prevent Finder layout recalculation
2. Disables Finder's auto-arrange (Snap to Grid) to prevent icon drift
3. Detects if the display setup has changed and auto-converts coordinates
4. Sets all icon positions in a single batch using `ignoring application responses`
5. Verifies positions after 3 seconds and corrects any that drifted

Coordinate conversion works by finding which display each icon was on, calculating its relative position within that display, and remapping onto the current primary display (with 20px padding for out-of-bounds icons).

## Quick Start

```bash
# Make the script executable
chmod +x scripts/desktop_icons.sh

# Save icon positions while docked to external monitor
./scripts/desktop_icons.sh save docked

# ... disconnect your external monitor ...

# Restore — icons auto-converted for single display!
./scripts/desktop_icons.sh restore docked
```

### Auto Profiles

Auto profiles use a display fingerprint (hash of display geometry) to automatically match the right profile for your current setup:

```bash
# Save a profile tagged to your current display configuration
./scripts/desktop_icons.sh save auto

# Restore — automatically finds the profile matching your current displays
./scripts/desktop_icons.sh restore auto

# Watch mode — auto-selects the right profile on any display change
./scripts/desktop_icons.sh watch auto
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

## Profiles

Profiles are stored at `~/.desktop_icon_profiles/<name>.txt` and contain display fingerprint, display geometry, icon/text size settings, and icon positions. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the file format and technical details.

## Anti-Drift Measures

The script uses several techniques (inspired by [Desktop Icon Manager](https://github.com/com-entonos/Desktop-Icon-Manager)) to prevent macOS from rearranging icons after restore:

1. **Disables Finder arrangement** — Turns off "Snap to Grid" and similar auto-arrange settings before restoring
2. **Restores icon/text size** — Prevents Finder from recalculating layout due to size changes
3. **Batch placement** — Sets all positions in a single AppleScript call wrapped in `ignoring application responses`
4. **Post-restore verification** — Waits 3 seconds, re-reads all positions, and batch-corrects any that drifted

## Roadmap

- [x] Get the shell script working reliably across display configurations
- [x] Fix icon drift (disable Snap to Grid, batch restore, verification)
- [x] Per-display auto-profiles with display fingerprinting
- [ ] Convert into a native macOS application (Swift/AppKit)
- [ ] Launch Agent for auto-running watch mode on login
- [ ] Event-driven display change detection (replace polling)
- [ ] Support for more than 2 displays with display-to-display mapping
- [ ] Support for more than 2 displays
