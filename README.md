# Desktop Icon Position Manager for macOS

A macOS menu bar app that saves, converts, and restores desktop icon positions across different display configurations. Solves the macOS icon shuffle when connecting/disconnecting external monitors.

## The Problem

When a MacBook is connected to an external monitor and you arrange desktop icons, disconnecting the external display causes macOS to scramble all icon positions. This happens because macOS uses a global coordinate system that spans all displays — when a display is removed, the coordinate origin shifts and icons end up off-screen.

## The App

A lightweight menu bar app (no dock icon) that handles everything automatically:

- **Auto-saves** your icon layout on launch, display change, quit, or periodically
- **Auto-restores** on app launch and when you connect/disconnect displays — finds the right profile by display fingerprint
- **Coordinate remapping** — converts icon positions between different display configurations
- **Anti-drift protection** — disables Snap to Grid, batch-sets positions, and verifies after restore
- **Permission diagnostics** — detects missing Finder Automation access and guides recovery from the menu
- **Launch at Login** — starts automatically via macOS Login Items; disables itself when the app is launched from an unstable path and prompts to move to /Applications

### Menu Bar Features

| Feature | Description |
|---------|-------------|
| Save Auto | Save icon positions tagged to your current display config |
| Save As... | Save with a custom profile name |
| Update Profile | Overwrite an existing profile with current positions |
| Restore | Restore any saved profile (auto-converts coordinates if displays changed) |
| Manage Profiles | Rename or delete saved profiles |
| Launch at Login | Start the app automatically when you log in |
| Auto-Save | Toggle auto-save on launch, display change, quit, or a 5/10/15/30/60-minute timer |
| Auto-Restore | Toggle auto-restore on display change and on launch |
| Show Auto Profiles | Toggle visibility of auto-generated profiles in menus |

### Auto Profiles

Auto profiles use human-readable names with display info and a fingerprint hash:

```
Auto-Built-in_a1b2c3d4              (single MacBook display)
Auto-Built-in+DELL-U2720Q_e5f6g7h8  (MacBook + external monitor)
```

The app automatically matches the right profile to your current display setup and restores it.

## Build & Run

Requires **macOS 14+** and **Xcode** (for Swift 6.0).

### Quick Development Build

```bash
cd macos-app
swift build
.build/debug/DesktopIconPosition
```

### Finder Smoke Test

To manually exercise the real Finder AppleScript read/write path against temporary desktop items with edge-case names:

```bash
swift run --package-path macos-app DesktopIconPosition --finder-smoke-test
```

This creates and removes temporary files on your Desktop and requires Finder Automation permission.

### Production Build (.app + DMG)

```bash
scripts/build-app.sh
```

This produces:
- `build/DesktopIconPosition.app` — proper macOS app bundle with icon
- `build/DesktopIconPosition.dmg` — disk image with drag-to-Applications

To install, open the DMG and drag the app to Applications.

### Code Signing (Optional)

Set environment variables to sign and notarize:

```bash
# Sign only
SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build-app.sh

# Sign + notarize
SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" \
  NOTARIZE=1 APPLE_ID="you@example.com" TEAM_ID="TEAMID" \
  APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
  scripts/build-app.sh
```

Or open `macos-app/Package.swift` in Xcode and build/run from there.

### Permissions

On startup, the app runs a lightweight Finder AppleScript check. If macOS has not asked yet, this triggers the **Automation** consent prompt.

If permission is denied:
- launch auto-save, launch auto-restore, display-change automation, and timer-based auto-save are skipped
- the menu shows **Open System Settings** and **Re-check Permission** actions
- once permission is granted in System Settings, **Re-check Permission** resumes the deferred automation behavior without restarting the app

Finder control requires macOS **Automation** permission (System Settings > Privacy & Security). The legacy shell script requires the same permission for Terminal.

Launch at Login is only reliable when the app lives in `/Applications` or `~/Applications`. If the app is later launched from an unstable path such as a DMG mount or Downloads, the app turns Launch at Login back off and shows guidance to move it.

## Profiles

Profiles are stored at `~/.desktop_icon_profiles/`. The app writes `.json` and can also read `.txt` profiles from the legacy shell script.

Each profile contains:
- Display fingerprint (MD5 hash of display geometry)
- Display frames (Quartz/CG coordinates)
- Finder settings (icon size, text size)
- Icon positions (name, x, y)

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for technical details.

## Shell Script (Legacy)

The original shell script implementation is still available at [legacy-desktop-icons-script/desktop_icons.sh](legacy-desktop-icons-script/). It's useful for automation or environments where the app can't be installed. See the [script README](legacy-desktop-icons-script/README.md) for usage details.

## How It Works

On save, the app captures icon positions, display geometry, icon size, text size, and a display fingerprint together as a profile. On restore:

1. Restores icon size and text size to prevent Finder layout recalculation
2. Disables Finder's auto-arrange (Snap to Grid) to prevent icon drift
3. Detects if the display setup changed and auto-converts coordinates
4. Sets all icon positions in a single batch using `ignoring application responses`
5. Verifies positions after 3 seconds and corrects any that drifted

Coordinate conversion works by finding which display each icon was on, calculating its relative position within that display, and remapping onto the current display layout (with 20px padding for out-of-bounds icons).

## Roadmap

- [x] Shell script with save/restore/watch and coordinate conversion
- [x] Anti-drift measures (disable Snap to Grid, batch restore, verification)
- [x] Per-display auto-profiles with display fingerprinting
- [x] Native macOS menu bar app (Swift/SwiftUI)
- [x] Event-driven display change detection (replaces polling)
- [x] Launch at Login
- [x] Auto-save on launch, display change, quit, and periodic timer
- [x] Profile management (rename, delete, update)
- [x] Human-readable auto-profile names with display info
- [x] Smart multi-display mapping with displaced icon parking
- [x] App icon and custom menu bar icon
- [x] Proper macOS distribution (.app bundle + DMG)
