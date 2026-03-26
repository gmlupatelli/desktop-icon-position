# Architecture

Technical details of how the Desktop Icon Position Manager works.

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

- Uses JXA (JavaScript for Automation) via `osascript -l JavaScript`
- Reads `NSScreen` frames (Cocoa coordinates: bottom-left origin, Y up)
- Converts to Quartz/CG coordinates (top-left origin, Y down) to match Finder's system
- Conversion formula: `cgY = mainScreenHeight - cocoaOriginY - screenHeight`

## Profile File Format

Stored at `~/.desktop_icon_profiles/<name>.txt`:

```
#FINGERPRINT|566459849ad08e7084399efd0414acb8
#DISPLAY|0|0|1792|1120
#DISPLAY|912|-1080|1920|1080
#SETTINGS|60|12
filename.txt|1960|50
photo.jpg|2000|150
```

- `#FINGERPRINT|<md5>` — MD5 hash of sorted display geometry, used for auto-profile matching
- `#DISPLAY|originX|originY|width|height` — Display geometry at time of save (Quartz/CG coordinates)
- `#SETTINGS|iconSize|textSize` — Finder icon size and text size at time of save
- Other lines are `iconName|x|y` positions

## Display Fingerprinting

A display fingerprint is an MD5 hash of sorted display geometry lines. This allows automatic profile matching:

```bash
get_display_frames | sort | md5 -q
# e.g., "566459849ad08e7084399efd0414acb8" → shortened to "56645984"
```

When using `save auto`, the profile name is `auto_<fingerprint>`. When using `restore auto` or `watch auto`, the script scans all saved profiles for a matching `#FINGERPRINT` line.

## Key Functions

| Function | Purpose |
|----------|---------|
| `get_display_frames()` | JXA/NSScreen to get display origins+sizes in CG coords |
| `get_display_count()` | JXA/NSScreen to get display count (instant, replaces `system_profiler`) |
| `get_display_fingerprint()` | MD5 hash of sorted display geometry for auto-profile matching |
| `find_display_for_point(x, y, displays)` | Determine which display contains a point |
| `remap_coordinates(saved, current, icons)` | Core conversion — remap icons to new display layout |
| `find_profile_for_fingerprint(fp)` | Scan saved profiles and return one matching the given fingerprint |
| `cmd_restore()` | Restore settings, disable arrangement, batch-set positions, verify and re-apply drift |
| `cmd_watch()` | Poll for display fingerprint changes, auto-restore on change |

## Icon Position Read/Write

- **Read:** AppleScript `desktop position of item` in Finder (returns `{x, y}` in global coords)
- **Write:** AppleScript `set desktop position of item "name" of desktop to {x, y}`

## Restore Process

The restore flow uses several techniques to prevent Finder from rearranging icons:

1. **Restore icon size and text size** — If saved settings differ from current, set them back to prevent layout recalculation
2. **Disable Finder arrangement** — `set arrangement of (icon view options of desktop's window) to not arranged` turns off Snap to Grid
3. **Batch position-setting** — All icon positions are set in a single AppleScript block wrapped in `ignoring application responses` (prevents Finder from queuing re-arrange between individual icon placements)
4. **Post-restore verification** — After 3 seconds, batch-reads all current positions, compares with targets (2px tolerance), and batch-reapplies any that drifted

This approach is inspired by [Desktop Icon Manager (DIM)](https://github.com/com-entonos/Desktop-Icon-Manager), which uses the same `ignoring application responses` + arrangement-disable pattern.

## Known Limitations

- First run requires granting Accessibility/Automation permissions to Terminal
- The `watch` command uses JXA-based display fingerprint polling (every 3s) — not event-driven
- Filenames containing the `|` character would break the delimiter (extremely rare on macOS)
- Auto-profile fingerprint matching returns the first match — if multiple profiles share a fingerprint, only one is used
