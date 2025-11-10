#!/bin/bash

# Test script for Image Loading Bug
# This script provokes the "Loading bitmap failed" error

echo "=== Image Loading Bug Test ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Android paths setup
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

# Function to find package name
get_package_name() {
    grep "applicationId" android/app/build.gradle | sed "s/.*'\(.*\)'.*/\1/" | head -1
}

PACKAGE_NAME=$(get_package_name)
if [ -z "$PACKAGE_NAME" ]; then
    PACKAGE_NAME="xyz.blueskyweb.app"
fi

echo "Package: $PACKAGE_NAME"
echo ""

# Check if device/emulator is connected (only for commands that need it)
check_device() {
    DEVICES=$(adb devices | grep -v "List of devices" | grep -v "^$" | wc -l)
    if [ "$DEVICES" -eq 0 ]; then
        echo -e "${RED}❌ No device/emulator found!${NC}"
        echo ""
        echo "Please start the emulator first:"
        echo "  pixel7"
        echo "  (or: emulator -avd Pixel_7)"
        echo ""
        exit 1
    fi
}

# Helper function to clear cache
clear_cache_internal() {
    adb shell "run-as $PACKAGE_NAME sh -c 'rm -rf cache/ImagePicker/* cache/bsky-composer/* cache/ImageManipulator/*'" 2>/dev/null
}

# Check helper functions FIRST
if [ "$1" = "clear-cache" ]; then
    check_device
    echo -e "${YELLOW}Clearing all relevant cache directories...${NC}"
    clear_cache_internal
    echo -e "${GREEN}✅ Cache cleared${NC}"
    echo ""
    echo "You can now test with a clean cache state."
    exit 0
fi

if [ "$1" = "provoke-error" ]; then
    check_device

    echo -e "${RED}Provoking 'Loading bitmap failed' error...${NC}"
    echo ""

    # Check the actual code in gallery.ts to determine if fix is active
    echo -e "${YELLOW}Checking fix status in gallery.ts...${NC}"

    if grep -q "if (cacheDir && !from.startsWith(cacheDir))" src/state/gallery.ts; then
        echo -e "${GREEN}Fix is ACTIVE${NC}"
        echo "(Line 255 has the '!' operator)"
        echo ""
        echo -e "${YELLOW}⚠️  Cannot provoke error with fix active!${NC}"
        echo ""
        echo "The files are being moved to bsky-composer/, so deleting"
        echo "from ImagePicker/ won't cause an error."
        echo ""
        echo "To test the bug:"
        echo "1. Change src/state/gallery.ts Line 255:"
        echo "   From: if (cacheDir && !from.startsWith(cacheDir))"
        echo "   To:   if (cacheDir && from.startsWith(cacheDir))"
        echo "2. Save the file (Fast Refresh should reload the app)"
        echo "3. Run this command again"
        echo ""
        exit 0
    elif grep -q "if (cacheDir && from.startsWith(cacheDir))" src/state/gallery.ts; then
        echo -e "${RED}Fix is NOT active${NC}"
        echo "(Line 255 missing the '!' operator - bug is active)"
        echo -e "${GREEN}✅ Ready to provoke error${NC}"
        echo ""
    else
        echo -e "${RED}❌ Could not find the condition in gallery.ts!${NC}"
        echo "Line 255 may have been modified."
        exit 1
    fi

    # Clear cache to ensure only the new image will be in ImagePicker
    echo -e "${YELLOW}Clearing cache...${NC}"
    clear_cache_internal
    echo -e "${GREEN}✅ Cache cleared${NC}"
    echo ""

    echo "INSTRUCTIONS:"
    echo "1. NOW select an image in the Composer (DO NOT post!)"
    echo "2. Press ENTER here when the image is selected..."
    read
    echo ""

    # Find the file in ImagePicker directory (should be the only one after cache clear)
    echo -e "${YELLOW}Searching for image file in ImagePicker...${NC}"
    IMAGE_FILE=$(adb shell "run-as $PACKAGE_NAME ls -t cache/ImagePicker/ 2>/dev/null" | head -1 | tr -d '\r')

    if [ -n "$IMAGE_FILE" ]; then
        IMAGE_FILE="cache/ImagePicker/$IMAGE_FILE"
    fi

    if [ -z "$IMAGE_FILE" ]; then
        echo -e "${RED}❌ No file found in ImagePicker directory!${NC}"
        echo ""
        echo "Did you select an image after the cache was cleared?"
        exit 1
    fi

    echo "Found: $IMAGE_FILE"
    echo ""

    # Try to delete the specific file
    echo -e "${YELLOW}Deleting ImagePicker file with run-as...${NC}"
    CACHE_PATH="/data/data/$PACKAGE_NAME/$IMAGE_FILE"

    # Use run-as to delete as app user
    DELETE_RESULT=$(adb shell "run-as $PACKAGE_NAME rm -f $CACHE_PATH" 2>&1)

    if echo "$DELETE_RESULT" | grep -q "Package.*unknown\|not debuggable"; then
        echo -e "${RED}❌ run-as failed: App is not debuggable!${NC}"
        exit 1
    elif [ -n "$DELETE_RESULT" ]; then
        echo -e "${RED}❌ Error deleting: $DELETE_RESULT${NC}"
        exit 1
    else
        # Check if file is really gone
        CHECK=$(adb shell "run-as $PACKAGE_NAME ls $CACHE_PATH" 2>&1)
        if echo "$CHECK" | grep -q "No such file"; then
            echo -e "${GREEN}✅ File successfully deleted!${NC}"
        else
            echo -e "${RED}❌ File still exists!${NC}"
            exit 1
        fi
    fi

    echo ""
    echo -e "${YELLOW}Try to post in the app NOW!${NC}"
    echo ""
    echo "Expected: 'Loading bitmap failed'"
    exit 0
fi

if [ "$1" = "show-cache" ]; then
    check_device
    echo -e "${YELLOW}Relevant cache directories:${NC}"
    echo ""

    FOUND_ANY=false

    # ImagePicker
    FILES=$(adb shell "run-as $PACKAGE_NAME ls cache/ImagePicker/ 2>/dev/null")
    if [ -n "$FILES" ]; then
        echo -e "${GREEN}ImagePicker:${NC}"
        echo "$FILES" | sed 's/^/  /'
        echo ""
        FOUND_ANY=true
    fi

    # bsky-composer
    FILES=$(adb shell "run-as $PACKAGE_NAME ls cache/bsky-composer/ 2>/dev/null")
    if [ -n "$FILES" ]; then
        echo -e "${GREEN}bsky-composer:${NC}"
        echo "$FILES" | sed 's/^/  /'
        echo ""
        FOUND_ANY=true
    fi

    # ImageManipulator
    FILES=$(adb shell "run-as $PACKAGE_NAME ls cache/ImageManipulator/ 2>/dev/null")
    if [ -n "$FILES" ]; then
        echo -e "${GREEN}ImageManipulator:${NC}"
        echo "$FILES" | sed 's/^/  /'
        echo ""
        FOUND_ANY=true
    fi

    if [ "$FOUND_ANY" = false ]; then
        echo "  (all directories empty)"
        echo ""
    fi

    exit 0
fi

if [ "$1" = "show-paths" ]; then
    check_device
    echo -e "${YELLOW}Relevant cache files:${NC}"
    echo ""

    FOUND_ANY=false

    # ImagePicker
    FILES=$(adb shell "run-as $PACKAGE_NAME find cache/ImagePicker/ -type f 2>/dev/null")
    if [ -n "$FILES" ]; then
        echo -e "${GREEN}ImagePicker:${NC}"
        echo "$FILES" | sed 's/^/  /'
        echo ""
        FOUND_ANY=true
    fi

    # bsky-composer
    FILES=$(adb shell "run-as $PACKAGE_NAME find cache/bsky-composer/ -type f 2>/dev/null")
    if [ -n "$FILES" ]; then
        echo -e "${GREEN}bsky-composer:${NC}"
        echo "$FILES" | sed 's/^/  /'
        echo ""
        FOUND_ANY=true
    fi

    # ImageManipulator
    FILES=$(adb shell "run-as $PACKAGE_NAME find cache/ImageManipulator/ -type f 2>/dev/null")
    if [ -n "$FILES" ]; then
        echo -e "${GREEN}ImageManipulator:${NC}"
        echo "$FILES" | sed 's/^/  /'
        echo ""
        FOUND_ANY=true
    fi

    if [ "$FOUND_ANY" = false ]; then
        echo "  (no files found)"
        echo ""
    fi

    exit 0
fi

if [ "$1" = "load-test-image" ]; then
    check_device
    echo -e "${GREEN}Loading test image into emulator...${NC}"
    wget -q -O /tmp/test-image.jpg https://picsum.photos/2000/2000
    if [ $? -eq 0 ]; then
        adb push /tmp/test-image.jpg /sdcard/Download/test-image.jpg
        adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Download/test-image.jpg
        echo -e "${GREEN}✅ Test image loaded! Open the Gallery/Photos app in the emulator.${NC}"
    else
        echo -e "${RED}❌ Download error${NC}"
    fi
    exit 0
fi

# No parameters - show instructions only

echo "============================================"
echo -e "${GREEN}AVAILABLE COMMANDS:${NC}"
echo ""
echo "  ./test-image-bug.sh                - Show this guide"
echo "  ./test-image-bug.sh show-cache     - Show cache directories"
echo "  ./test-image-bug.sh show-paths     - Show all files in cache"
echo "  ./test-image-bug.sh clear-cache    - Clear all cache directories"
echo "  ./test-image-bug.sh load-test-image - Load 2000x2000 test image"
echo "  ./test-image-bug.sh provoke-error  - Provoke the error (auto-clears cache+logs)"
echo ""
echo "NOTE: Logs are visible in 'yarn android' output - no separate watch needed"
echo ""
echo "============================================"
echo -e "${GREEN}MANUAL TESTS:${NC}"
echo ""
echo "1. NORMAL TEST WITH FIX (works):"
echo "   - Run: yarn android (watch logs in this terminal)"
echo "   - Open app, Composer, select image"
echo "   - Logs show: '✅ CONDITION TRUE - File will be MOVED'"
echo "   - Run: ./test-image-bug.sh show-cache"
echo "   - Expected: File in bsky-composer, NOT in ImagePicker"
echo ""
echo "2. TEST WITH MARY'S BUG (Line 255: from.startsWith without !):"
echo "   - Change src/state/gallery.ts Line 255:"
echo "     From: if (cacheDir && !from.startsWith(cacheDir))"
echo "     To:   if (cacheDir && from.startsWith(cacheDir))"
echo "   - Rebuild: yarn android"
echo "   - Open app, select image"
echo "   - Logs show: '❌ CONDITION FALSE - File will NOT be moved'"
echo "   - Run: ./test-image-bug.sh show-cache"
echo "   - Expected: File in ImagePicker, NOT in bsky-composer"
echo ""
echo "3. PROVOKE ERROR (interactive test):"
echo "   - Run: ./test-image-bug.sh provoke-error"
echo "   - Script checks if fix is active (Line 255)"
echo "   - If fix active: Aborts with instructions"
echo "   - If bug active: Clears cache, waits for image selection,"
echo "     then deletes file from ImagePicker to provoke error"
echo ""

