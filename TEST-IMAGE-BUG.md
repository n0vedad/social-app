# Test Plan: "Loading bitmap failed" Bug

## Hypothesis
The bug occurs because `moveIfNecessary()` does **NOT** move images from `cache/ImagePicker/` to `cache/bsky-composer/`. The files remain in the ImagePicker cache and get deleted by expo-image-picker or Android before `compressImage()` can use them.

## Preparation

1. **Logging is enabled** (✅ already done)
   - `moveIfNecessary()` logs all paths
   - `compressImage()` logs every loop

2. **Start emulator:**
   ```bash
   pixel7  # or: emulator -avd Pixel_7
   ```

3. **Rebuild app with logging:**
   ```bash
   source ~/.zshrc && nvm use 20
   yarn android
   ```

   Note: Logs are visible in the `yarn android` terminal output - no separate watch needed.

## Test Scenarios

### ✅ Test 1: Baseline - Normal Flow WITH FIX (should always work)

**Goal:** Verify that fix is working correctly

**Steps:**
1. Open app
2. Open Composer
3. Select image
4. Wait 30-60 seconds (or put app in background)
5. Post

**Expected Result:**
- Logs show: `[moveIfNecessary] ✅ CONDITION TRUE - File will be MOVED`
- Logs show: `[moveIfNecessary] ✅ File successfully moved`
- Path: `file:///data/user/0/.../cache/bsky-composer/...`
- Post **always works** (even after waiting, because file is in bsky-composer)

**Confirms Fix:** ✅ Files ARE moved to safe location

---

### 🔴 Test 2: Provoke Error with Bug (should work)

**Goal:** Reproduce the original bug by forcing file deletion

**Steps:**
1. Change [src/state/gallery.ts:255](src/state/gallery.ts#L255):
   ```typescript
   // Remove the ! to reproduce the bug
   if (cacheDir && from.startsWith(cacheDir)) {
   ```
2. Save (Fast Refresh reloads app)
3. Run: `./test-image-bug.sh provoke-error`
4. Follow instructions:
   - Script clears cache first
   - **THEN** select image in Composer
   - Press ENTER
   - Script deletes the file from ImagePicker
   - **Immediately try to post**

**Expected Result:**
- Script says "Fix is NOT active"
- Script finds file in ImagePicker/ and deletes it
- When you try to post: **"Loading bitmap failed"** error!

**Confirms Bug:** ✅ Without `!`, files stay in ImagePicker and can be deleted

---

### ✅ Test 3: Provoke Error with Fix (should NOT work)

**Goal:** Verify that fix prevents the error even when cache is deleted

**Steps:**
1. Make sure Line 255 has the fix: `if (cacheDir && !from.startsWith(cacheDir))`
2. Rebuild if needed: `yarn android`
3. Run: `./test-image-bug.sh provoke-error`
4. Follow instructions:
   - Script clears cache first
   - **THEN** select image in Composer
   - Press ENTER

**Expected Result:**
- Script says "Fix is ACTIVE"
- Aborts with instructions to remove the `!` to test the bug

**Confirms Fix:** ✅ Script detects fix is active from code

---

### 🔍 Test 4: Investigate Cache Directory

**Goal:** See what actually happens in the filesystem

**Steps:**

**With FIX (Line 255 has `!`):**
1. Open app, Composer, select image
2. Run: `./test-image-bug.sh show-cache`
3. Look for files:
   - `cache/ImagePicker/` - ❌ Should be EMPTY (files were moved)
   - `cache/bsky-composer/` - ✅ Should contain file
4. Post (should work)

**With BUG (Line 255 without `!`):**
1. Open app, Composer, select image
2. Run: `./test-image-bug.sh show-cache`
3. Look for files:
   - `cache/ImagePicker/` - ✅ Should contain file
   - `cache/bsky-composer/` - ❌ Should be EMPTY (BUG!)
4. Post immediately (works, but fragile)

**After post:**
```bash
./test-image-bug.sh show-paths
```
- Shows all temporary files from manipulateAsync in `cache/ImageManipulator/`

---

## Quick Commands

```bash
# Show cache directories
./test-image-bug.sh show-cache

# List all cache files
./test-image-bug.sh show-paths

# Clear all cache directories
./test-image-bug.sh clear-cache

# Load test image (2000x2000)
./test-image-bug.sh load-test-image

# Provoke error (interactive, auto-clears cache)
# Script checks fix status, clears cache, waits for image selection, then deletes file
./test-image-bug.sh provoke-error
```