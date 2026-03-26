#!/bin/bash
# ================================================================
# Desktop Icon Position Manager for macOS (Multi-Display Aware)
# ================================================================
# Saves, converts, and restores desktop icon positions across
# different display configurations. Solves the macOS icon shuffle
# when connecting/disconnecting external monitors.
#
# Usage:
#   ./desktop_icons.sh save     <profile>           -- Save positions + display geometry
#   ./desktop_icons.sh restore  <profile>            -- Smart restore (auto-converts if needed)
#   ./desktop_icons.sh convert  <source> <target>    -- Convert profile for current displays
#   ./desktop_icons.sh list     <profile>            -- List positions in a profile
#   ./desktop_icons.sh profiles                      -- Show all saved profiles
#   ./desktop_icons.sh watch    <profile>            -- Auto-restore when displays change
#   ./desktop_icons.sh count                         -- Show current display info
# ================================================================

SAVE_DIR="$HOME/.desktop_icon_profiles"
mkdir -p "$SAVE_DIR"

get_display_frames() {
    osascript -l JavaScript <<'JSEOF'
ObjC.import("AppKit");
var screens = $.NSScreen.screens;
var mainFrame = screens.objectAtIndex(0).frame;
var mainH = mainFrame.size.height;
var lines = [];
for (var i = 0; i < screens.count; i++) {
    var f = screens.objectAtIndex(i).frame;
    var cgX = Math.round(f.origin.x);
    var cgY = Math.round(mainH - f.origin.y - f.size.height);
    var w   = Math.round(f.size.width);
    var h   = Math.round(f.size.height);
    lines.push(cgX + "|" + cgY + "|" + w + "|" + h);
}
lines.join("\n");
JSEOF
}

get_display_count() {
    osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.screens.count'
}

get_display_fingerprint() {
    local frames
    frames=$(get_display_frames)
    echo "$frames" | sort | md5 -q
}

find_display_for_point() {
    local px=$1 py=$2
    local displays="$3"
    while IFS='|' read -r dx dy dw dh; do
        [ -z "$dx" ] && continue
        if (( px >= dx && px < dx + dw && py >= dy && py < dy + dh )); then
            echo "$dx|$dy|$dw|$dh"
            return 0
        fi
    done <<< "$displays"
    echo "$displays" | head -1
    return 1
}

remap_coordinates() {
    local saved_displays="$1"
    local current_displays="$2"
    local icon_data="$3"
    local cmx cmy cmw cmh
    IFS='|' read -r cmx cmy cmw cmh <<< "$(echo "$current_displays" | head -1)"
    local PAD=20
    while IFS='|' read -r name px py; do
        [ -z "$name" ] && continue
        local orig_display
        orig_display=$(find_display_for_point "$px" "$py" "$saved_displays")
        local odx ody odw odh
        IFS='|' read -r odx ody odw odh <<< "$orig_display"
        local relX=$((px - odx))
        local relY=$((py - ody))
        local newX=$((cmx + relX))
        local newY=$((cmy + relY))
        if (( newX < cmx + PAD ));       then newX=$((cmx + PAD)); fi
        if (( newY < cmy + PAD ));       then newY=$((cmy + PAD)); fi
        if (( newX > cmx + cmw - PAD )); then newX=$((cmx + cmw - PAD)); fi
        if (( newY > cmy + cmh - PAD )); then newY=$((cmy + cmh - PAD)); fi
        echo "$name|$newX|$newY"
    done <<< "$icon_data"
}

cmd_save() {
    local PROFILE="$1"
    local SAVE_FILE="$SAVE_DIR/${PROFILE}.txt"
    echo "Saving to profile: \"$PROFILE\"..."
    local DISPLAY_COUNT
    DISPLAY_COUNT=$(get_display_count)
    echo "   Detected $DISPLAY_COUNT display(s)"
    local FRAMES
    FRAMES=$(get_display_frames)
    if [ -z "$FRAMES" ]; then
        echo "ERROR: Could not read display geometry. Check Accessibility permissions."
        exit 1
    fi
    echo "   Display geometry:"
    while IFS='|' read -r dx dy dw dh; do
        echo "     Display Origin ($dx, $dy) -- ${dw}x${dh}"
    done <<< "$FRAMES"
    local SETTINGS
    SETTINGS=$(osascript <<'ASEOF'
tell application "Finder"
    set iSize to icon size of (icon view options of desktop's window)
    set tSize to text size of (icon view options of desktop's window)
    return (iSize as text) & "|" & (tSize as text)
end tell
ASEOF
)
    echo "   Icon size: $(echo "$SETTINGS" | cut -d'|' -f1), Text size: $(echo "$SETTINGS" | cut -d'|' -f2)"
    local ICONS
    ICONS=$(osascript <<'ASEOF'
tell application "Finder"
    set allItems to every item of desktop
    set posData to ""
    repeat with anItem in allItems
        try
            set itemName to name of anItem as text
            set itemPos to desktop position of anItem
            set posX to item 1 of itemPos as integer
            set posY to item 2 of itemPos as integer
            set posData to posData & itemName & "|" & posX & "|" & posY & linefeed
        end try
    end repeat
end tell
return posData
ASEOF
)
    local FINGERPRINT
    FINGERPRINT=$(get_display_fingerprint)
    echo "   Display fingerprint: ${FINGERPRINT:0:8}"
    {
        echo "#FINGERPRINT|$FINGERPRINT"
        while IFS= read -r line; do
            [ -n "$line" ] && echo "#DISPLAY|$line"
        done <<< "$FRAMES"
        echo "#SETTINGS|$SETTINGS"
        echo "$ICONS"
    } > "$SAVE_FILE"
    local ICON_COUNT
    ICON_COUNT=$(grep -v '^#' "$SAVE_FILE" | grep -c '|' 2>/dev/null || echo "0")
    echo ""
    echo "DONE: Saved $ICON_COUNT icon(s) to profile \"$PROFILE\""
    echo "   File: $SAVE_FILE"
}

cmd_restore() {
    local PROFILE="$1"
    local SAVE_FILE="$SAVE_DIR/${PROFILE}.txt"
    if [ ! -f "$SAVE_FILE" ]; then
        echo "ERROR: Profile \"$PROFILE\" not found."
        echo ""
        echo "Available profiles:"
        cmd_profiles
        exit 1
    fi
    local SAVED_DISPLAYS
    SAVED_DISPLAYS=$(grep '^#DISPLAY|' "$SAVE_FILE" | sed 's/^#DISPLAY|//')
    local ICON_DATA
    ICON_DATA=$(grep -v '^#' "$SAVE_FILE" | grep '|')
    local CURRENT_DISPLAYS
    CURRENT_DISPLAYS=$(get_display_frames)
    if [ -n "$SAVED_DISPLAYS" ] && [ "$SAVED_DISPLAYS" != "$CURRENT_DISPLAYS" ]; then
        echo "Display setup changed -- auto-converting coordinates..."
        echo ""
        echo "   Profile was saved with:"
        while IFS='|' read -r dx dy dw dh; do
            echo "      Display at ($dx, $dy) -- ${dw}x${dh}"
        done <<< "$SAVED_DISPLAYS"
        echo ""
        echo "   Current setup:"
        while IFS='|' read -r dx dy dw dh; do
            echo "      Display at ($dx, $dy) -- ${dw}x${dh}"
        done <<< "$CURRENT_DISPLAYS"
        echo ""
        ICON_DATA=$(remap_coordinates "$SAVED_DISPLAYS" "$CURRENT_DISPLAYS" "$ICON_DATA")
    else
        echo "Display geometry matches -- restoring directly."
        echo ""
    fi
    # Restore saved icon size and text size (prevents Finder layout recalc)
    local SAVED_SETTINGS
    SAVED_SETTINGS=$(grep '^#SETTINGS|' "$SAVE_FILE" | sed 's/^#SETTINGS|//')
    if [ -n "$SAVED_SETTINGS" ]; then
        local SAVED_ICON_SIZE SAVED_TEXT_SIZE
        IFS='|' read -r SAVED_ICON_SIZE SAVED_TEXT_SIZE <<< "$SAVED_SETTINGS"
        echo "Restoring icon size ($SAVED_ICON_SIZE) and text size ($SAVED_TEXT_SIZE)..."
        osascript <<ASEOF
tell application "Finder"
    set icon size of (icon view options of desktop's window) to $SAVED_ICON_SIZE
    set text size of (icon view options of desktop's window) to $SAVED_TEXT_SIZE
end tell
ASEOF
    fi

    # Disable Finder arrangement (Snap to Grid etc.) to prevent icon drift
    echo "Disabling Finder auto-arrange..."
    osascript <<'ASEOF'
tell application "Finder"
    if arrangement of (icon view options of desktop's window) is not not arranged then
        set arrangement of (icon view options of desktop's window) to not arranged
    end if
end tell
ASEOF

    echo "Restoring from profile: \"$PROFILE\"..."
    echo ""

    # Build a single AppleScript to set all positions at once (faster, prevents mid-restore rearrange)
    local AS_SCRIPT=""
    local ICON_COUNT=0
    while IFS='|' read -r name posX posY; do
        [ -z "$name" ] && continue
        local escaped_name
        escaped_name=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
        AS_SCRIPT="${AS_SCRIPT}
            try
                set desktop position of item \"$escaped_name\" of desktop to {$posX, $posY}
            end try"
        ICON_COUNT=$((ICON_COUNT + 1))
    done <<< "$ICON_DATA"

    # Execute batch restore wrapped in 'ignoring application responses'
    local RESULT
    RESULT=$(osascript <<ASEOF
tell application "Finder"
    ignoring application responses
$AS_SCRIPT
    end ignoring
end tell
return "done"
ASEOF
    )
    echo "   Set positions for $ICON_COUNT icon(s)."

    # Post-restore verification: wait, batch-read positions, re-apply drifted icons
    echo ""
    echo "Verifying positions (waiting 3 seconds)..."
    sleep 3

    # Batch-read all current positions in one AppleScript call
    local CURRENT_POSITIONS
    CURRENT_POSITIONS=$(osascript <<'ASEOF'
tell application "Finder"
    set allItems to every item of desktop
    set posData to ""
    repeat with anItem in allItems
        try
            set itemName to name of anItem as text
            set itemPos to desktop position of anItem
            set posX to item 1 of itemPos as integer
            set posY to item 2 of itemPos as integer
            set posData to posData & itemName & "|" & posX & "|" & posY & linefeed
        end try
    end repeat
end tell
return posData
ASEOF
    )

    # Build lookup of current positions
    local DRIFTED=0
    local VERIFIED=0
    local REAPPLY_SCRIPT=""
    while IFS='|' read -r name posX posY; do
        [ -z "$name" ] && continue
        # Find this icon's current position in the batch read
        local curLine
        curLine=$(echo "$CURRENT_POSITIONS" | grep -F "$name|" | head -1)
        if [ -z "$curLine" ]; then
            continue
        fi
        local curX curY
        IFS='|' read -r _ curX curY <<< "$curLine"
        local dX=$(( curX - posX )) dY=$(( curY - posY ))
        # Allow 2px tolerance for rounding
        if (( dX > 2 || dX < -2 || dY > 2 || dY < -2 )); then
            DRIFTED=$((DRIFTED + 1))
            local escaped_name
            escaped_name=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
            REAPPLY_SCRIPT="${REAPPLY_SCRIPT}
                try
                    set desktop position of item \"$escaped_name\" of desktop to {$posX, $posY}
                end try"
        else
            VERIFIED=$((VERIFIED + 1))
        fi
    done <<< "$ICON_DATA"

    # Re-apply drifted icons in a single batch
    if [ "$DRIFTED" -gt 0 ]; then
        osascript <<ASEOF
tell application "Finder"
    ignoring application responses
$REAPPLY_SCRIPT
    end ignoring
end tell
ASEOF
        echo "   Corrected $DRIFTED drifted icon(s), $VERIFIED already correct."
    else
        echo "   All $VERIFIED icon(s) verified in correct position."
    fi
    echo ""
    echo "Restore complete."
}

cmd_convert() {
    local SOURCE="$1"
    local TARGET="$2"
    local SOURCE_FILE="$SAVE_DIR/${SOURCE}.txt"
    local TARGET_FILE="$SAVE_DIR/${TARGET}.txt"
    if [ ! -f "$SOURCE_FILE" ]; then
        echo "ERROR: Source profile \"$SOURCE\" not found."
        exit 1
    fi
    if [ "$SOURCE" = "$TARGET" ]; then
        echo "ERROR: Source and target profile names must be different."
        exit 1
    fi
    local SAVED_DISPLAYS
    SAVED_DISPLAYS=$(grep '^#DISPLAY|' "$SOURCE_FILE" | sed 's/^#DISPLAY|//')
    if [ -z "$SAVED_DISPLAYS" ]; then
        echo "ERROR: Profile \"$SOURCE\" has no display geometry data."
        echo "   It was saved with an older script. Re-save it with this version."
        exit 1
    fi
    local CURRENT_DISPLAYS
    CURRENT_DISPLAYS=$(get_display_frames)
    local ICON_DATA
    ICON_DATA=$(grep -v '^#' "$SOURCE_FILE" | grep '|')
    echo "Converting: \"$SOURCE\" -> \"$TARGET\""
    echo ""
    echo "   Source display setup:"
    while IFS='|' read -r dx dy dw dh; do
        echo "      Origin ($dx, $dy) -- ${dw}x${dh}"
    done <<< "$SAVED_DISPLAYS"
    echo ""
    echo "   Target (current) display setup:"
    while IFS='|' read -r dx dy dw dh; do
        echo "      Origin ($dx, $dy) -- ${dw}x${dh}"
    done <<< "$CURRENT_DISPLAYS"
    echo ""
    local REMAPPED
    REMAPPED=$(remap_coordinates "$SAVED_DISPLAYS" "$CURRENT_DISPLAYS" "$ICON_DATA")
    {
        while IFS= read -r line; do
            [ -n "$line" ] && echo "#DISPLAY|$line"
        done <<< "$CURRENT_DISPLAYS"
        echo "$REMAPPED"
    } > "$TARGET_FILE"
    echo "   Coordinate mapping:"
    paste <(echo "$ICON_DATA") <(echo "$REMAPPED") | while IFS=$'\t' read -r old new; do
        local oname oX oY nname nX nY
        IFS='|' read -r oname oX oY <<< "$old"
        IFS='|' read -r nname nX nY <<< "$new"
        [ -z "$oname" ] && continue
        if [ "$oX" = "$nX" ] && [ "$oY" = "$nY" ]; then
            echo "      $oname: ($oX, $oY) -- unchanged"
        else
            echo "      $oname: ($oX, $oY) -> ($nX, $nY)"
        fi
    done
    local ICON_COUNT
    ICON_COUNT=$(grep -v '^#' "$TARGET_FILE" | grep -c '|' 2>/dev/null || echo "0")
    echo ""
    echo "DONE: Converted $ICON_COUNT icon(s) -> saved as \"$TARGET\""
    echo ""
    echo "   To apply now:  $0 restore $TARGET"
}

cmd_list() {
    local PROFILE="$1"
    local SAVE_FILE="$SAVE_DIR/${PROFILE}.txt"
    if [ ! -f "$SAVE_FILE" ]; then
        echo "ERROR: Profile \"$PROFILE\" not found."
        exit 1
    fi
    local SAVED_FP
    SAVED_FP=$(grep '^#FINGERPRINT|' "$SAVE_FILE" | sed 's/^#FINGERPRINT|//')
    [ -n "$SAVED_FP" ] && echo "Display fingerprint: ${SAVED_FP:0:8}"
    local SAVED_SETTINGS
    SAVED_SETTINGS=$(grep '^#SETTINGS|' "$SAVE_FILE" | sed 's/^#SETTINGS|//')
    if [ -n "$SAVED_SETTINGS" ]; then
        local S_ICON_SIZE S_TEXT_SIZE
        IFS='|' read -r S_ICON_SIZE S_TEXT_SIZE <<< "$SAVED_SETTINGS"
        echo "Icon size: $S_ICON_SIZE, Text size: $S_TEXT_SIZE"
    fi
    local SAVED_DISPLAYS
    SAVED_DISPLAYS=$(grep '^#DISPLAY|' "$SAVE_FILE" | sed 's/^#DISPLAY|//')
    if [ -n "$SAVED_DISPLAYS" ]; then
        echo "Display geometry when saved:"
        while IFS='|' read -r dx dy dw dh; do
            echo "   Origin ($dx, $dy) -- ${dw}x${dh}"
        done <<< "$SAVED_DISPLAYS"
        echo ""
    else
        echo "WARNING: No display geometry (saved with older version)"
        echo ""
    fi
    echo "Icon positions in profile \"$PROFILE\":"
    echo "   ---------------------------------------------"
    grep -v '^#' "$SAVE_FILE" | grep '|' | while IFS='|' read -r name posX posY; do
        [ -z "$name" ] && continue
        printf "   %-35s (%s, %s)\n" "$name" "$posX" "$posY"
    done
    echo "   ---------------------------------------------"
    local ICON_COUNT
    ICON_COUNT=$(grep -v '^#' "$SAVE_FILE" | grep -c '|' 2>/dev/null || echo "0")
    echo "   Total: $ICON_COUNT icon(s)"
}

cmd_profiles() {
    local FILES=("$SAVE_DIR"/*.txt)
    if [ ! -e "${FILES[0]}" ]; then
        echo "   (none -- use 'save <profile>' to create one)"
        return
    fi
    for f in "${FILES[@]}"; do
        local PNAME
        PNAME=$(basename "$f" .txt)
        local ICON_COUNT
        ICON_COUNT=$(grep -v '^#' "$f" | grep -c '|' 2>/dev/null || echo "0")
        local DISPLAY_COUNT
        DISPLAY_COUNT=$(grep -c '^#DISPLAY|' "$f" 2>/dev/null || echo "0")
        local FP
        FP=$(grep '^#FINGERPRINT|' "$f" | sed 's/^#FINGERPRINT|//')
        local MOD_DATE
        MOD_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f")
        local FP_TAG=""
        [ -n "$FP" ] && FP_TAG=" [${FP:0:8}]"
        echo "   $PNAME -- $ICON_COUNT icons, $DISPLAY_COUNT display(s)$FP_TAG -- saved $MOD_DATE"
    done
}

cmd_watch() {
    local PROFILE="$1"
    local USE_AUTO=false
    if [ "$PROFILE" = "auto" ]; then
        USE_AUTO=true
        echo "Watching for display changes (auto-profile mode)..."
        echo "   Will auto-select profile by display fingerprint."
    else
        local SAVE_FILE="$SAVE_DIR/${PROFILE}.txt"
        if [ ! -f "$SAVE_FILE" ]; then
            echo "ERROR: Profile \"$PROFILE\" not found. Save it first!"
            exit 1
        fi
        echo "Watching for display changes..."
        echo "   Will restore profile \"$PROFILE\" when displays change."
    fi
    echo "   Auto-converts coordinates if display geometry differs."
    echo "   Press Ctrl+C to stop."
    echo ""
    local LAST_FINGERPRINT
    LAST_FINGERPRINT=$(get_display_fingerprint)
    local LAST_COUNT
    LAST_COUNT=$(get_display_count)
    echo "   Current displays: $LAST_COUNT (fingerprint: ${LAST_FINGERPRINT:0:8})"
    while true; do
        sleep 3
        local CURRENT_FINGERPRINT
        CURRENT_FINGERPRINT=$(get_display_fingerprint)
        if [ "$CURRENT_FINGERPRINT" != "$LAST_FINGERPRINT" ]; then
            local CURRENT_COUNT
            CURRENT_COUNT=$(get_display_count)
            echo ""
            echo "   Display change! ($LAST_COUNT -> $CURRENT_COUNT, fingerprint: ${CURRENT_FINGERPRINT:0:8})"
            echo "   Waiting 5 seconds for macOS to settle..."
            sleep 5
            echo ""
            if [ "$USE_AUTO" = true ]; then
                local AUTO_PROFILE
                AUTO_PROFILE=$(find_profile_for_fingerprint "$CURRENT_FINGERPRINT")
                if [ -n "$AUTO_PROFILE" ]; then
                    echo "   Auto-selected profile: \"$AUTO_PROFILE\""
                    cmd_restore "$AUTO_PROFILE"
                else
                    echo "   No profile found for fingerprint ${CURRENT_FINGERPRINT:0:8}."
                    echo "   Save one with: $0 save auto"
                fi
            else
                cmd_restore "$PROFILE"
            fi
            LAST_FINGERPRINT="$CURRENT_FINGERPRINT"
            LAST_COUNT=$CURRENT_COUNT
        fi
    done
}

cmd_count() {
    local COUNT
    COUNT=$(get_display_count)
    echo "Displays connected: $COUNT"
    echo ""
    echo "   Display geometry (Quartz coordinates):"
    get_display_frames | while IFS='|' read -r dx dy dw dh; do
        echo "     Display Origin ($dx, $dy) -- ${dw}x${dh}"
    done
}

find_profile_for_fingerprint() {
    local target_fp="$1"
    local FILES=("$SAVE_DIR"/*.txt)
    [ ! -e "${FILES[0]}" ] && return
    for f in "${FILES[@]}"; do
        local fp
        fp=$(grep '^#FINGERPRINT|' "$f" | sed 's/^#FINGERPRINT|//')
        if [ "$fp" = "$target_fp" ]; then
            basename "$f" .txt
            return
        fi
    done
}

case "$1" in
    save)
        if [ -z "$2" ]; then
            echo "ERROR: Specify a profile name.  Example: $0 save docked"
            exit 1
        fi
        if [ "$2" = "auto" ]; then
            FP=$(get_display_fingerprint)
            PROFILE_NAME="auto_${FP:0:8}"
            echo "Auto-profile: display fingerprint ${FP:0:8}"
            cmd_save "$PROFILE_NAME"
        else
            cmd_save "$2"
        fi
        ;;
    restore)
        if [ -z "$2" ]; then
            echo "ERROR: Specify a profile name.  Example: $0 restore docked"
            exit 1
        fi
        if [ "$2" = "auto" ]; then
            FP=$(get_display_fingerprint)
            PROFILE_NAME=$(find_profile_for_fingerprint "$FP")
            if [ -z "$PROFILE_NAME" ]; then
                echo "ERROR: No profile found for current display fingerprint (${FP:0:8})."
                echo "   Save one first: $0 save auto"
                exit 1
            fi
            echo "Auto-profile: matched \"$PROFILE_NAME\" (fingerprint ${FP:0:8})"
            cmd_restore "$PROFILE_NAME"
        else
            cmd_restore "$2"
        fi
        ;;
    convert)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "ERROR: Specify source and target profiles."
            echo "   Example: $0 convert docked undocked"
            exit 1
        fi
        cmd_convert "$2" "$3"
        ;;
    list)
        if [ -z "$2" ]; then
            echo "ERROR: Specify a profile name.  Example: $0 list docked"
            exit 1
        fi
        cmd_list "$2"
        ;;
    profiles)
        echo "Saved profiles:"
        cmd_profiles
        ;;
    watch)
        if [ -z "$2" ]; then
            echo "ERROR: Specify a profile.  Example: $0 watch docked"
            exit 1
        fi
        cmd_watch "$2"
        ;;
    count)
        cmd_count
        ;;
    *)
        echo "Desktop Icon Position Manager for macOS"
        echo "======================================================="
        echo ""
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  save     <profile>            Save icon positions + display geometry"
        echo "  save     auto                 Save with auto-detected display fingerprint"
        echo "  restore  <profile>            Restore (auto-converts if displays changed)"
        echo "  restore  auto                 Restore matching profile for current displays"
        echo "  convert  <source> <target>    Convert profile for current display setup"
        echo "  list     <profile>            Show saved positions in a profile"
        echo "  profiles                      List all saved profiles"
        echo "  watch    <profile>            Auto-restore when displays disconnect"
        echo "  watch    auto                 Auto-restore using display fingerprint matching"
        echo "  count                         Show current display info"
        echo ""
        echo "Quick Start:"
        echo "  $0 save docked               # Save with external monitor connected"
        echo "  # ... disconnect monitor ..."
        echo "  $0 restore docked            # Icons auto-converted and restored!"
        echo ""
        echo "Auto Profiles:"
        echo "  $0 save auto                 # Save profile tagged to current displays"
        echo "  $0 restore auto              # Auto-match and restore for current displays"
        echo "  $0 watch auto                # Watch and auto-select right profile"
        echo ""
        exit 1
        ;;
esac
