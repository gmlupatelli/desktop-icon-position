#!/bin/bash
# build-app.sh — Build DesktopIconPosition.app bundle and DMG
#
# Usage:
#   scripts/build-app.sh                          # unsigned build
#   SIGNING_IDENTITY="Developer ID" scripts/build-app.sh   # signed build
#
# Optional environment variables:
#   SIGNING_IDENTITY  — Code signing identity (e.g., "Developer ID Application: Name (TEAMID)")
#   NOTARIZE=1        — Submit for notarization after signing
#   APPLE_ID          — Apple ID email (required if NOTARIZE=1)
#   TEAM_ID           — Apple Developer Team ID (required if NOTARIZE=1)
#   APP_PASSWORD      — App-specific password for notarization (required if NOTARIZE=1)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DesktopIconPosition"
BUNDLE_NAME="Desktop Icon Position"
BUILD_DIR="${REPO_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
RESOURCES_DIR="${REPO_ROOT}/macos-app/Resources"
ICNS_PATH="${RESOURCES_DIR}/AppIcon.icns"
DMG_BG="${BUILD_DIR}/dmg-background.png"
DMG_BG_2X="${BUILD_DIR}/dmg-background@2x.png"
VOLUME_ICON="${BUILD_DIR}/VolumeIcon.icns"

echo "=== Building ${BUNDLE_NAME} ==="

# --- Step 1: Swift build (release) ---
echo "→ Compiling (release)..."
swift build -c release --package-path "${REPO_ROOT}/macos-app"

# Find the built executable
EXECUTABLE=$(swift build -c release --package-path "${REPO_ROOT}/macos-app" --show-bin-path)/${APP_NAME}
if [[ ! -f "$EXECUTABLE" ]]; then
    echo "Error: Executable not found at ${EXECUTABLE}" >&2
    exit 1
fi
echo "  Binary: ${EXECUTABLE}"

# --- Step 2: Generate AppIcon.icns if missing ---
if [[ ! -f "$ICNS_PATH" ]]; then
    echo "→ Generating AppIcon.icns from SVG..."
    swift "${REPO_ROOT}/scripts/generate-icns.swift"
fi

if [[ ! -f "$ICNS_PATH" ]]; then
    echo "Warning: AppIcon.icns not found — app will have no icon" >&2
fi

# --- Step 3: Assemble .app bundle ---
echo "→ Assembling ${APP_NAME}.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp "${RESOURCES_DIR}/Info.plist" "${APP_BUNDLE}/Contents/"

# Copy icon
if [[ -f "$ICNS_PATH" ]]; then
    cp "$ICNS_PATH" "${APP_BUNDLE}/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo "  Bundle: ${APP_BUNDLE}"

# --- Step 4: Code signing (optional) ---
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    echo "→ Signing with identity: ${SIGNING_IDENTITY}"
    ENTITLEMENTS="${RESOURCES_DIR}/${APP_NAME}.entitlements"
    codesign --deep --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"
    echo "  Signed and hardened."

    # Verify signature
    codesign --verify --verbose=2 "$APP_BUNDLE"
else
    echo "  Skipping code signing (set SIGNING_IDENTITY to enable)"
fi

# --- Step 5: Notarization (optional) ---
if [[ "${NOTARIZE:-}" == "1" ]]; then
    if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
        echo "Error: NOTARIZE=1 requires SIGNING_IDENTITY" >&2
        exit 1
    fi
    if [[ -z "${APPLE_ID:-}" || -z "${TEAM_ID:-}" || -z "${APP_PASSWORD:-}" ]]; then
        echo "Error: NOTARIZE=1 requires APPLE_ID, TEAM_ID, and APP_PASSWORD" >&2
        exit 1
    fi

    echo "→ Notarizing..."
    ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    xcrun stapler staple "$APP_BUNDLE"
    rm -f "$ZIP_PATH"
    echo "  Notarized and stapled."
fi

# --- Step 6: Generate DMG assets if missing ---
if [[ ! -f "$DMG_BG" || ! -f "$DMG_BG_2X" || ! -f "$VOLUME_ICON" ]]; then
    echo "→ Generating DMG assets (background + volume icon)..."
    swift "${REPO_ROOT}/scripts/generate-dmg-assets.swift"
fi

# --- Step 7: Create polished DMG ---
echo "→ Creating DMG..."
rm -f "$DMG_PATH"

DMG_TEMP="${BUILD_DIR}/${APP_NAME}-temp.dmg"
VOLUME_PATH="/Volumes/${BUNDLE_NAME}"

# Calculate DMG size (app size + 20MB headroom)
APP_SIZE_KB=$(du -sk "$APP_BUNDLE" | cut -f1)
DMG_SIZE_KB=$(( APP_SIZE_KB + 20480 ))

# Create writable DMG
hdiutil create -size "${DMG_SIZE_KB}k" -type UDIF -fs HFS+ \
    -volname "$BUNDLE_NAME" "$DMG_TEMP"

# Mount it and capture device path
ATTACH_OUTPUT=$(hdiutil attach "$DMG_TEMP" -mountpoint "$VOLUME_PATH" -nobrowse)
DEVICE=$(echo "$ATTACH_OUTPUT" | grep Apple_HFS | awk '{print $1}')
echo "  Mounted on device: ${DEVICE}"

# Copy app and create Applications symlink
cp -R "$APP_BUNDLE" "$VOLUME_PATH/"
ln -s /Applications "$VOLUME_PATH/Applications"

# Add hidden background images (Retina support)
mkdir -p "$VOLUME_PATH/.background"
if [[ -f "$DMG_BG" ]]; then
    cp "$DMG_BG" "$VOLUME_PATH/.background/background.png"
fi
if [[ -f "$DMG_BG_2X" ]]; then
    cp "$DMG_BG_2X" "$VOLUME_PATH/.background/background@2x.png"
fi

# Set volume icon
if [[ -f "$VOLUME_ICON" ]]; then
    cp "$VOLUME_ICON" "$VOLUME_PATH/.VolumeIcon.icns"
    SetFile -a C "$VOLUME_PATH" &>/dev/null || true
fi

# Style the DMG window with AppleScript
# Window size: 660x400, app at (165, 175), Applications at (495, 195)
echo "  Styling Finder window..."
osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "Desktop Icon Position"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 760, 532}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 160
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png"
        set position of item "DesktopIconPosition.app" of container window to {165, 165}
        set position of item "Applications" of container window to {495, 165}
        close
        open
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

# Wait for Finder to write .DS_Store
sync
sleep 2

# Hide hidden files
SetFile -a V "$VOLUME_PATH/.background" &>/dev/null || true
SetFile -a V "$VOLUME_PATH/.VolumeIcon.icns" &>/dev/null || true

# Tell Finder to release the volume
osascript -e "tell application \"Finder\" to eject disk \"${BUNDLE_NAME}\"" &>/dev/null || true
sleep 3

# Unmount using device path (more reliable than mount point)
for i in 1 2 3; do
    if ! mount | grep -q "$VOLUME_PATH"; then
        break
    fi
    hdiutil detach "$DEVICE" -force &>/dev/null || true
    sleep 2
done

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$DMG_TEMP"

echo "  DMG: ${DMG_PATH}"

# --- Done ---
echo ""
echo "=== Build complete ==="
echo "  App:  ${APP_BUNDLE}"
echo "  DMG:  ${DMG_PATH}"
echo ""
echo "To install: open ${DMG_PATH}"
