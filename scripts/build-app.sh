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

# --- Step 6: Create DMG ---
echo "→ Creating DMG..."
rm -f "$DMG_PATH"

# Stage DMG contents
DMG_STAGING="${BUILD_DIR}/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$BUNDLE_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"
echo "  DMG: ${DMG_PATH}"

# --- Done ---
echo ""
echo "=== Build complete ==="
echo "  App:  ${APP_BUNDLE}"
echo "  DMG:  ${DMG_PATH}"
echo ""
echo "To install: open ${DMG_PATH}"
