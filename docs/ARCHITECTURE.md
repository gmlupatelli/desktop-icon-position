# Architecture

Technical details of the Desktop Icon Position Manager — both the macOS app and the legacy shell script.

## Project Structure

```
desktop-icon-position/
├── README.md                          # Main docs (app-focused)
├── docs/
│   └── ARCHITECTURE.md                # This file
├── macos-app/
│   ├── Package.swift                  # SPM project, macOS 14+, Swift 6.0
│   ├── Resources/Info.plist           # LSUIElement, NSAppleEventsUsageDescription
│   ├── Sources/DesktopIconPosition/
│   │   ├── App.swift                  # @main, MenuBarExtra
│   │   ├── Models/
│   │   │   ├── DisplayFrame.swift     # Display geometry (Quartz coords)
│   │   │   ├── IconPosition.swift     # Icon name + x,y
│   │   │   └── Profile.swift          # Full profile: fingerprint, displays, settings, icons
│   │   ├── Services/
│   │   │   ├── CoordinateConverter.swift  # Remap icons between display configs
│   │   │   ├── DisplayService.swift       # NSScreen queries, fingerprint, display names
│   │   │   ├── FinderService.swift        # NSAppleScript calls to Finder
│   │   │   └── ProfileManager.swift       # Read .txt+.json, write .json, CRUD
│   │   ├── ViewModels/
│   │   │   └── AppViewModel.swift     # @Observable state, orchestrates all operations
│   │   └── Views/
│   │       └── MenuBarView.swift      # SwiftUI menu content + NSPanel dialogs
│   └── Tests/DesktopIconPositionTests/
│       ├── CoordinateConverterTests.swift
│       ├── DisplayServiceTests.swift
│       └── ProfileManagerTests.swift
└── scripts/
    ├── README.md                      # Script-specific docs
    └── desktop_icons.sh               # Legacy shell script
```

## macOS App Architecture

### Tech Stack

- **Swift 6.0** with strict concurrency (`@MainActor` throughout)
- **SwiftUI** MenuBarExtra (macOS 14+ requirement for `@Observable` / `@Bindable`)
- **SPM** (Swift Package Manager) — no Xcode project file
- **NSAppleScript** for Finder interaction (inline AppleScript strings)
- **ServiceManagement** `SMAppService` for Launch at Login
- **CryptoKit** `Insecure.MD5` for display fingerprinting

### Data Flow

```
Display Change Notification
       │
       ▼
AppViewModel.handleDisplayChange()
       │
       ├─ autoSaveOnDisplayChange? → saveAutoIfIconsExist() [save outgoing config]
       │
       ├─ Update lastFingerprint
       │
       └─ autoRestoreEnabled? → restoreAuto()
                                    │
                                    ├─ ProfileManager.findProfile(forFingerprint:)
                                    ├─ CoordinateConverter.remap(icons:from:to:)
                                    ├─ FinderService.restoreSettings()
                                    ├─ FinderService.disableArrangement()
                                    ├─ FinderService.batchSetPositions()
                                    └─ FinderService.verifyAndReapply() [after 3s delay]
```

### Services

| Service | Responsibility |
|---------|---------------|
| **DisplayService** | `NSScreen` queries, Cocoa→Quartz coordinate conversion, MD5 fingerprint, display names (`localizedName`), display change observer via `didChangeScreenParametersNotification` |
| **FinderService** | 6 NSAppleScript operations: read positions, read settings, restore settings, disable arrangement, batch set positions (`ignoring application responses`), verify & reapply |
| **CoordinateConverter** | `findDisplay(forPoint:in:)` and `remap(icons:from:to:)` — same algorithm as the shell script |
| **ProfileManager** | Read `.txt` + `.json`, write `.json`, list, load, save, find by fingerprint, delete, rename, auto-profile name generation |

### AppViewModel State

| Property | Type | Persistence | Description |
|----------|------|-------------|-------------|
| `launchAtLogin` | `Bool` | SMAppService | macOS Login Items |
| `autoRestoreEnabled` | `Bool` | UserDefaults | Auto-restore on display change |
| `autoSaveOnLaunch` | `Bool` | UserDefaults | Save auto profile at startup |
| `autoSaveOnDisplayChange` | `Bool` | UserDefaults | Save outgoing config before restore |
| `autoSaveOnQuit` | `Bool` | UserDefaults | Save auto profile before quitting |
| `autoSaveOnTimer` | `Bool` | UserDefaults | Periodic save toggle |
| `autoSaveIntervalMinutes` | `Int` | UserDefaults | Timer interval (5/10/15/30) |
| `showAutoProfiles` | `Bool` | UserDefaults | Show/hide `Auto-` profiles in menus |

### Dialog Implementation

LSUIElement apps (no dock icon) don't receive keyboard events by default. The app uses `NSPanel` (not `NSAlert`) and temporarily switches to `.regular` activation policy to receive keyboard input, then back to `.accessory` after the dialog closes.

---

## Coordinate Conversion Logic

macOS uses a unified global coordinate space across all displays. When an external monitor is disconnected, the origin shifts and saved coordinates become invalid.

**Example:**

```
savedPosition = (1960, 50)          # global coords when saved
sourceDisplay = origin (1920, 0)    # the display the icon was on
relativePos   = (1960-1920, 50-0) = (40, 50)   # position within that display
currentDisplay = origin (0, 0)      # MacBook is now primary
newPosition   = (0+40, 0+50) = (40, 50)        # correct position on single display
```

Icons that would land outside the current display bounds are clamped with 20px padding.

## Display Geometry Detection

- **App:** Uses `NSScreen.screens` directly from Swift
- **Script:** Uses JXA (JavaScript for Automation) via `osascript -l JavaScript`
- Both read `NSScreen` frames in Cocoa coordinates (bottom-left origin, Y up)
- Both convert to Quartz/CG coordinates (top-left origin, Y down) to match Finder
- Conversion formula: `cgY = mainScreenHeight - cocoaOriginY - screenHeight`

## Display Fingerprinting

A display fingerprint is an MD5 hash of sorted display geometry lines. Both the app and script use the same algorithm:

```
sorted pipe-delimited frames → MD5
e.g., "0|0|1792|1120\n912|-1080|1920|1080\n" → "566459849ad08e7084399efd0414acb8"
```

The app generates auto-profile names with display info:
```
Auto-Built-in+DELL-U2720Q_56645984
```

The script uses a simpler format:
```
auto_56645984
```

Both match profiles by scanning the fingerprint stored inside the profile file/JSON, so the naming difference doesn't affect matching.

## Profile Formats

### JSON (app writes, app reads)

```json
{
  "fingerprint": "566459849ad08e7084399efd0414acb8",
  "displays": [
    {"x": 0, "y": 0, "width": 1792, "height": 1120}
  ],
  "settings": {"iconSize": 60, "textSize": 12},
  "icons": [
    {"name": "filename.txt", "x": 40, "y": 50}
  ]
}
```

### Pipe-delimited (script writes, both read)

```
#FINGERPRINT|566459849ad08e7084399efd0414acb8
#DISPLAY|0|0|1792|1120
#SETTINGS|60|12
filename.txt|40|50
```

## Restore Process

Both the app and script use the same restore flow:

1. **Restore icon size and text size** — prevents Finder layout recalculation
2. **Disable Finder arrangement** — `set arrangement of (icon view options of desktop's window) to not arranged`
3. **Batch position-setting** — all icons in one AppleScript block with `ignoring application responses`
4. **Post-restore verification** — after 3 seconds, re-read positions, reapply any that drifted (2px tolerance)

Inspired by [Desktop Icon Manager (DIM)](https://github.com/com-entonos/Desktop-Icon-Manager).

## Known Limitations

- First run requires granting Accessibility/Automation permissions to the app (or Terminal for the script)
- `SMAppService` Launch at Login requires the app to be at a stable filesystem location
- Filenames containing `|` would break the script's pipe-delimited format (extremely rare on macOS)
- Auto-profile fingerprint matching returns the first match if multiple profiles share a fingerprint
- The script cannot read `.json` profiles saved by the app
