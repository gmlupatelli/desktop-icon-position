# Architecture

Technical details of the Desktop Icon Position Manager macOS app.

## Project Structure

```
desktop-icon-position/
├── README.md                          # Main docs (app-focused)
├── docs/
│   └── ARCHITECTURE.md                # This file
├── macos-app/
│   ├── Package.swift                  # SPM project, macOS 14+, Swift 6.0
│   ├── Resources/
│   │   ├── Info.plist                 # Bundle config (LSUIElement, permissions)
│   │   ├── DesktopIconPosition.entitlements  # Code signing entitlements
│   │   ├── AppIcon.svg                # Source app icon (1024x1024)
│   │   ├── AppIcon.icns               # Generated icon set (via generate-icns.swift)
│   │   └── MenuBarIcon.svg            # Source menu bar icon
│   ├── Sources/DesktopIconPosition/
│   │   ├── App.swift                  # @main, MenuBarExtra, CLI flags
│   │   ├── Models/
│   │   │   ├── DisplayFrame.swift     # Display geometry (Quartz coords)
│   │   │   ├── IconPosition.swift     # Icon name + x,y
│   │   │   └── Profile.swift          # Full profile: fingerprint, displays, settings, icons
│   │   ├── Services/
│   │   │   ├── CoordinateConverter.swift      # Remap icons between display configs
│   │   │   ├── DisplayService.swift           # NSScreen queries, fingerprint, display names
│   │   │   ├── FinderService.swift            # NSAppleScript calls to Finder
│   │   │   ├── FinderSmokeTestRunner.swift    # --finder-smoke-test CLI runner
│   │   │   ├── ProfileManager.swift           # Read .txt+.json, write .json, CRUD
│   │   │   ├── TimingBenchmarkRunner.swift    # --timing-benchmark CLI runner
│   │   │   └── TimingLog.swift                # Lightweight timing instrumentation
│   │   ├── ViewModels/
│   │   │   ├── AppViewModel.swift             # @Observable state, orchestrates all operations
│   │   │   ├── AppViewModel+Utilities.swift   # Settings window, permissions, license helpers
│   │   │   └── AutomationCoordinator.swift    # Pure decision layer for automation flows
│   │   └── Views/
│   │       ├── MenuBarView.swift      # SwiftUI menu content + NSPanel dialogs
│   │       └── SettingsView.swift     # Settings window
│   └── Tests/DesktopIconPositionTests/
│       ├── AutomationCoordinatorTests.swift
│       ├── CoordinateConverterTests.swift
│       ├── DisplayServiceTests.swift
│       ├── FinderServiceTests.swift
│       └── ProfileManagerTests.swift
├── legacy-desktop-icons-script/           # Legacy shell script (has its own README)
│   ├── README.md
│   └── desktop_icons.sh
├── scripts/
│   ├── build-app.sh                   # Build .app bundle + DMG
│   ├── generate-dmg-assets.swift      # DMG background + layout generation
│   └── generate-icns.swift            # SVG → .icns icon generation
└── build/                             # Build output (gitignored)
    ├── DesktopIconPosition.app/
    └── DesktopIconPosition.dmg
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

```text
Display Change Notification                   App Launch
       │                                           │
       ▼                                           ▼
AppViewModel.handleDisplayChange()            AppViewModel.start()
       │                                           │
       ▼                                           ├─ FinderService.checkPermission()
scheduleDisplayChange()  [debounce]                │
       │                                           ├─ AutomationCoordinator
       ├─ AutomationCoordinator                    │   .planResumeAfterPermissionGranted()
       │                                           │
       ├─ permissionGranted?                       ├─ autoRestoreOnLaunch?
       │  └─ no → skip (UI shows recovery)         │  → issue .restoreAuto action
       │                                           │
       ├─ Update lastFingerprint                   └─ autoSaveOnTimer?
       │                                              → issue timer actions
       └─ autoRestoreEnabled?                      │
          → issue .restoreAuto action              │
       │                                           │
       └─────────────────────┬─────────────────────┘
                             ▼
           AppViewModel.applyAutomationActions()
                             │
                             ├─ .setStatusMessage(...)
                             ├─ .startAutoSaveTimer / .stopAutoSaveTimer
                             │
                             └─ .restoreAuto
                                  │
                                  ├─ ProfileManager.findProfile(forFingerprint:)
                                  └─ AppViewModel.restore(name:profile:)
                                       ├─ CoordinateConverter.remap(icons:from:to:)
                                       ├─ FinderService.prepareForRestore()  [settings + disable arrange]
                                       ├─ FinderService.batchSetPositions()
                                       └─ Adaptive verify chain (0.5s → 1.5s → 3.0s)
                                            └─ FinderService.verifyAndReapply() [early exit on zero drift]
```

If a Finder operation later fails with a permission-denied AppleScript error, `AppViewModel` flips `permissionGranted` to `false`, stops the auto-save timer, and exposes the recovery actions in the menu. `recheckPermission()` retries the lightweight permission probe and, when successful, resumes the launch-time automation that was deferred.

### Services

| Service | Responsibility |
|---------|---------------|
| **AutomationCoordinator** | Pure decision layer for display-change, permission recheck, and post-permission resume flows; returns actions for `AppViewModel` to execute |
| **DisplayService** | `NSScreen` queries, Cocoa→Quartz coordinate conversion, MD5 fingerprint, display names (`localizedName`), display change observer via `didChangeScreenParametersNotification` |
| **FinderService** | NSAppleScript operations: batch read positions (DIM-style `name of items` + `desktop position of items` with fallback to per-item loop), read settings, combined `prepareForRestore` (settings + disable arrangement), batch set positions (`ignoring application responses`), verify & reapply, plus a permission probe and permission-error detection |
| **TimingLog** | Lightweight timing instrumentation gated behind `--timing-benchmark` flag or `TIMING_LOG=1` env var; `measure()` wraps any closure with elapsed-time logging, `summary()` emits total labels |
| **TimingBenchmarkRunner** | CLI benchmark runner (`--timing-benchmark`): performs a full save → restore → adaptive-verify cycle with timing labels, then exits |
| **CoordinateConverter** | `findDisplay(forPoint:in:)`, `matchDisplays(saved:current:)`, and `remap(icons:from:to:)` — smart display-to-display matching with displaced icon parking |
| **ProfileManager** | Read `.txt` + `.json`, write `.json`, list, load, save, find by fingerprint, delete, rename, auto-profile name generation |

### AppViewModel State

| Property | Type | Persistence | Description |
|----------|------|-------------|-------------|
| `launchAtLogin` | `Bool` | SMAppService | macOS Login Items |
| `permissionGranted` | `Bool` | In-memory | Whether Automation permission to control Finder is granted |
| `isStableLocation` | `Bool` | Computed | Whether the app is in /Applications (stable for Launch at Login) |
| `autoRestoreEnabled` | `Bool` | UserDefaults | Auto-restore on display change (default: true) |
| `autoRestoreOnLaunch` | `Bool` | UserDefaults | Auto-restore on app launch (default: true) |
| `autoSaveOnQuit` | `Bool` | UserDefaults | Save auto profile before quitting |
| `autoSaveOnTimer` | `Bool` | UserDefaults | Periodic save toggle |
| `autoSaveIntervalMinutes` | `Int` | UserDefaults | Timer interval (5/10/15/30/60) |
| `showAutoProfiles` | `Bool` | UserDefaults | Show/hide `Auto-` profiles in menus |
| `isRestoring` | `Bool` | In-memory | Guards against overlapping restores |
| `verifyTask` | `Task?` | In-memory | Handle for adaptive verify chain (cancelable) |
| `displayChangeTask` | `Task?` | In-memory | Handle for debounced display-change handler |

### Dialog Implementation

LSUIElement apps (no dock icon) don't receive keyboard events by default. The app uses `NSPanel` (not `NSAlert`) and temporarily switches to `.regular` activation policy to receive keyboard input, then back to `.accessory` after the dialog closes.

### Permission Diagnostics

- `FinderService.checkPermission()` runs a minimal AppleScript against Finder to trigger or confirm Automation permission
- `permissionGranted` gates startup auto-restore, display-change automation, and timer-driven auto-save
- When permission is missing, the menu exposes recovery actions to open System Settings and re-check access
- `recheckPermission()` uses `AutomationCoordinator` to resume deferred launch automation and restart the timer when permission is granted

### Launch At Login Stability

- `isStableLocation` accepts `/Applications` and `~/Applications` as stable install locations
- When the app starts from an unstable path and Launch at Login is still enabled, `AppViewModel.start()` disables it immediately to avoid a broken login item
- The menu replaces the Launch at Login toggle with guidance to move the app when location is unstable

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

- Uses `NSScreen.screens` directly from Swift
- Reads `NSScreen` frames in Cocoa coordinates (bottom-left origin, Y up)
- Converts to Quartz/CG coordinates (top-left origin, Y down) to match Finder
- Conversion formula: `cgY = mainScreenHeight - cocoaOriginY - screenHeight`

## Display Fingerprinting

A display fingerprint is an MD5 hash of sorted display geometry lines:

```
sorted pipe-delimited frames → MD5
e.g., "0|0|1792|1120\n912|-1080|1920|1080\n" → "566459849ad08e7084399efd0414acb8"
```

Auto-profile names include display info and a fingerprint prefix:
```
Auto-Built-in+DELL-U2720Q_56645984
```

Profiles are matched by scanning the fingerprint stored inside the profile JSON, so the name format doesn't affect matching.

## Profile Formats

### JSON (primary format)

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

### Pipe-delimited (legacy, read-only)

The app can read `.txt` profiles created by the legacy shell script. It tries `.json` first, then falls back to `.txt`. New profiles are always saved as `.json`.

```
#FINGERPRINT|566459849ad08e7084399efd0414acb8
#DISPLAY|0|0|1792|1120
#SETTINGS|60|12
filename.txt|40|50
```

## Restore Process

The app uses an optimized restore strategy inspired by [Desktop Icon Manager (DIM)](https://github.com/com-entonos/Desktop-Icon-Manager):

1. **Prepare for restore** — combined AppleScript restores icon size + text size and disables Snap to Grid in one call (`prepareForRestore`), preventing layout recalculation
2. **Batch position-setting** — all icons in one AppleScript block with `ignoring application responses`
3. **Adaptive verify/reapply** — verify at 0.5s, 1.5s, and 3.0s after restore; early-exit when zero drift is detected (typical case completes on first pass); reapply any icons that drifted beyond 2px tolerance
4. **Overlap protection** — `isRestoring` flag prevents concurrent restores; `verifyTask` cancellation stops stale verify chains when a new restore starts

The legacy shell script uses the same general approach (restore settings, disable arrangement, batch set, verify) but with separate AppleScript calls and a fixed 3-second verify delay. See [legacy-desktop-icons-script/README.md](../legacy-desktop-icons-script/README.md) for details.

### Read Optimization

Icon position reads use a two-tier strategy:

1. **Batch read** (primary) — DIM-style `name of items of desktop` + `desktop position of items of desktop` in one AppleScript, joined via text item delimiters. Names and positions use record separator (ASCII 30) and group separator (ASCII 29) delimiters for safe parsing.
2. **Per-item loop** (fallback) — individual `name of item i` + `desktop position of item i` with try/catch, using unit separator (ASCII 31). Handles edge cases where batch coercion fails.

### Display-Change Debounce

macOS fires multiple `didChangeScreenParametersNotification` events during dock/undock. The app uses cancel-and-replace debounce: each notification cancels any pending display-change task and starts a fresh 5-second delay, collapsing rapid-fire events into a single restore.

## Build Pipeline

The build script (`scripts/build-app.sh`) assembles a proper macOS `.app` bundle from the SPM build output:

```
scripts/build-app.sh
       │
       ├─ swift build -c release --package-path macos-app
       │
       ├─ Generate AppIcon.icns (if missing)
       │     └─ scripts/generate-icns.swift
       │         └─ AppIcon.svg → NSImage → PNG ×10 sizes → iconutil → .icns
       │
       ├─ Assemble .app bundle
       │     build/DesktopIconPosition.app/Contents/
       │       ├─ Info.plist
       │       ├─ PkgInfo
       │       ├─ MacOS/DesktopIconPosition
       │       └─ Resources/AppIcon.icns
       │
       ├─ Code signing (optional, if SIGNING_IDENTITY is set)
       │     └─ codesign --deep --options runtime --entitlements ...
       │
       ├─ Notarization (optional, if NOTARIZE=1)
       │     └─ notarytool submit → stapler staple
       │
       └─ Create DMG
             └─ hdiutil create (app + Applications symlink)
```

Code signing and notarization are opt-in via environment variables. Without them, the build produces an unsigned `.app` and DMG that work for local development (users may need to right-click → Open to bypass Gatekeeper).

## Known Limitations

- First run requires granting Automation permission to control Finder
- `SMAppService` Launch at Login requires the app to be at a stable filesystem location — the app detects unstable paths, disables stale login-item registrations, and gates the toggle with a warning
- Auto-profile fingerprint matching returns the first match if multiple profiles share a fingerprint
