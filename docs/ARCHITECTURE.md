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
| **CoordinateConverter** | `findDisplay(forPoint:in:)`, `matchDisplays(saved:current:)`, and `remap(icons:from:to:)` — smart display-to-display matching with displaced icon parking |
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

macOS uses a unified global coordinate space across all displays. When an external monitor is disconnected, the origin shifts and saved coordinates become invalid. The app uses a smart display-to-display matching algorithm to handle arbitrary display configuration changes.

### Display Matching Algorithm (`matchDisplays`)

Given saved displays and current displays, the algorithm builds a mapping `[savedIndex: currentIndex]`:

1. **Score all pairs** — For each (saved, current) pair, compute:
   - **Overlap area** (higher = better match) — the intersection area of the two display rectangles
   - **Center distance** (lower = better match) — Euclidean distance between display centers
2. **Sort candidates** — Primary sort: overlap area descending. Tiebreaker: center distance ascending.
3. **Greedy assignment** — Iterate sorted candidates. If the saved display is unassigned, assign it to the current display. Multiple saved displays can map to the same current display (e.g., 3 saved → 2 current).
4. **Fallback** — Any unmatched saved display maps to current display 0 (primary).

### Icon Remapping (`remap`)

For each icon in the saved profile:

1. **Find source display** — Which saved display contained this icon?
2. **Look up target display** — Use the `matchDisplays` mapping.
3. **Native icons** (source display overlaps target display):
   - Compute relative position within source display
   - Apply same relative offset on target display
   - Clamp to target bounds with 20px padding
4. **Displaced icons** (source display has no overlap with target, e.g., a removed monitor):
   - Park in a grid at the **bottom** of the target display
   - Grid spacing: 100px horizontal, 100px vertical
   - Fill right-to-left, bottom-up (starting 120px from right edge, 120px from bottom)
   - Each displaced icon gets a unique grid slot

### Example: 2 displays → 1 display

```
Saved:   [MacBook 0,0,1792,1120]  [External 1792,0,1920,1080]
Current: [MacBook 0,0,1792,1120]

Icon on MacBook at (40, 50)    → stays at (40, 50)         [native]
Icon on External at (1900, 50) → parked at (1672, 1000)    [displaced, grid slot 0]
Icon on External at (2000, 50) → parked at (1572, 1000)    [displaced, grid slot 1]
```

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
