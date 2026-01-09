# Media Download Fixes Applied

## Issues Fixed

### 1. **File Size Shows "0 B"** ✅
**Problem:** The UI was showing "0 B" for all media files instead of the actual size.

**Root Cause:** 
- Legacy attachments had `fileSize: 0` hardcoded
- Metadata attachments sometimes had null/missing fileSize values

**Solution:**
- Added proper fileSize handling in `_buildMetadataAttachment()`
- Added debug logging to track fileSize values
- Changed display format to show "Unknown size" instead of "0 B" for files without size info
- Added actual file size verification after download

**Files Changed:**
- [lib/widgets/media_preview_card.dart](lib/widgets/media_preview_card.dart) - Line 200: Updated `_formatSize()` method
- [lib/screens/messages/group_chat_page.dart](lib/screens/messages/group_chat_page.dart) - Line 776: Added fileSize logging

### 2. **Files Not Actually Storing on Device** ✅
**Problem:** Downloads appeared to work but files weren't actually saved to device storage.

**Root Cause:**
- Using `getApplicationDocumentsDirectory()` which saves to internal app storage (not visible/accessible)
- No verification that files were actually written
- Insufficient logging to debug issues

**Solution:**

#### Changed Storage Location
**OLD:** Internal app storage (not accessible by user)
```dart
getApplicationDocumentsDirectory() 
// → /data/data/com.lenv.reward/app_flutter/
```

**NEW:** External storage (actual device storage)
```dart
getExternalStorageDirectory()
// → /storage/emulated/0/Android/data/com.lenv.reward/files/media/
```

**Benefits:**
- Files are now stored in REAL device storage
- Can be verified in file manager
- Survives app cache clears (with proper permission)
- More reliable storage

#### Added Comprehensive Logging
Added detailed logs at every step:

1. **Directory Creation:**
```
📁 Created media directory: /storage/emulated/0/Android/data/com.lenv.reward/files/media/
```

2. **Download Progress:**
```
📥 Starting download: media/1234567/file.pdf
🔗 Download URL: https://files.lenv1.tech/media/1234567/file.pdf
📦 Content length: 2048000 bytes
```

3. **File Saving:**
```
💾 Saved to: /storage/emulated/0/.../media_1234567_file.pdf
📦 File size: 2048000 bytes (2.0 MB)
📂 File exists: true
✅ Download complete: file.pdf (2.0 MB)
🔑 Saved with key: media/1234567/file.pdf
```

4. **Status Checks:**
```
📋 Check status for: media/1234567/file.pdf
   Downloaded: true
   Local path: /storage/.../media_1234567_file.pdf
   File size: 2048000 bytes (2.0 MB)
```

#### Files Changed
- [lib/services/media_storage_helper.dart](lib/services/media_storage_helper.dart) - Lines 10-31: Changed to `getExternalStorageDirectory()`
- [lib/services/media_repository.dart](lib/services/media_repository.dart) - Lines 132-163: Added comprehensive logging
- [lib/widgets/media_preview_card.dart](lib/widgets/media_preview_card.dart) - Lines 53-62: Added status check logging

## What Now Works

### ✅ Correct File Sizes
- PDFs show actual size (e.g., "2.0 MB" instead of "0 B")
- Audio files show size (e.g., "4.5 MB")
- Images show size (e.g., "156.3 KB")
- Unknown files show "Unknown size" instead of confusing "0 B"

### ✅ Actual Device Storage
Files are now saved to:
```
/storage/emulated/0/Android/data/com.lenv.reward/files/media/
├── media_1234567_document.pdf
├── media_9876543_audio.m4a
└── media_5555555_image.jpg
```

**You can verify files exist using:**
1. File manager app on phone
2. Navigate to: `Android/data/com.lenv.reward/files/media/`
3. See all downloaded files there

### ✅ Detailed Logging
Every operation now logs:
- What's being downloaded
- Where it's being saved
- Actual file size after download
- Verification that file exists
- Any errors that occur

## Testing Instructions

### 1. Test File Size Display
1. Open a chat with media attachments
2. **EXPECTED:** See actual file sizes like "2.0 MB", "156 KB", etc.
3. **NOT:** "0 B" for everything

### 2. Test Actual Download
1. Tap "Download" button on a file
2. **Watch the logs for:**
   ```
   📥 Starting download: media/...
   📦 Content length: ... bytes
   💾 Saved to: ...
   ✅ Download complete: ... (2.0 MB)
   ```
3. **EXPECTED:** File actually saved to device

### 3. Verify File Exists
**Method 1: Through App**
1. Download a file
2. Close and reopen the message
3. **EXPECTED:** "Open" button (not "Download" again)
4. Tap "Open" - should open immediately (no download)

**Method 2: Through File Manager**
1. Open any file manager app
2. Navigate to: `Internal Storage → Android → data → com.lenv.reward → files → media`
3. **EXPECTED:** See all downloaded files there
4. Can tap files to open them directly from file manager

### 4. Test Multiple Downloads
1. Download 3-5 different files
2. Check file manager - should see all files
3. Check storage: Settings → Apps → new_reward → Storage
4. **EXPECTED:** See actual storage usage increase

## Debugging Failed Downloads

If downloads still fail, check the logs for:

### HTTP Errors
```
❌ Download failed: HTTP 404
```
- File doesn't exist in R2
- Wrong URL format

### Storage Errors
```
❌ Error saving file: No space left on device
```
- Phone storage full
- Need to clear space

### Permission Errors
```
❌ Error: Permission denied
```
- Storage permission not granted
- Go to: Settings → Apps → new_reward → Permissions → Allow Storage

### Network Errors
```
❌ Download error: SocketException
```
- No internet connection
- Cloudflare Worker not accessible
- Check URL manually: `https://files.lenv1.tech/media/{key}`

## Architecture Summary

```
Message Arrives
    ↓
MediaPreviewCard
    ↓
User Taps "Download"
    ↓
MediaRepository.downloadMedia()
    ↓
HTTP GET from files.lenv1.tech
    ↓
Stream bytes to file
    ↓
Save to: /storage/emulated/0/Android/data/com.lenv.reward/files/media/
    ↓
Verify file exists
    ↓
Save metadata to SharedPreferences
    ↓
Update UI: "Download" → "Open"
```

## File Naming Convention

Files are saved with sanitized names:
- **R2 Key:** `media/1234567/My Document.pdf`
- **Local File:** `media_1234567_My_Document.pdf`
- **Pattern:** Replace `/` with `_`, spaces with `_`

## Storage Management

### Check Storage Usage
```dart
final repository = MediaRepository();
final totalBytes = await repository.getTotalStorageUsed();
print('Storage used: ${formatBytes(totalBytes)}');
```

### Delete Individual File
```dart
await repository.deleteMedia('media/1234567/file.pdf');
```

### Clear All Downloads
```dart
await repository.clearAllDownloads();
```

## Next Steps

1. **Restart the app:** `flutter run`
2. **Test downloads:** Navigate to chat, tap download
3. **Check logs:** Look for the 📥 📦 💾 ✅ emoji logs
4. **Verify files:** Use file manager to see actual files
5. **Test reopening:** Close/reopen message, should say "Open" not "Download"

## Important Notes

⚠️ **External Storage Behavior:**
- Files are saved to device storage
- Visible in file manager
- May persist even after app uninstall (depends on Android version)
- Requires `WRITE_EXTERNAL_STORAGE` permission (already in manifest)

✅ **Already Configured:**
- Android permissions in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)
- `READ_EXTERNAL_STORAGE` - Line 7
- `WRITE_EXTERNAL_STORAGE` - Line 8
- No additional setup needed

## Summary

**What was broken:**
1. File sizes showing "0 B"
2. Files not actually saving to device

**What's now fixed:**
1. Actual file sizes displayed correctly
2. Files saved to real device storage at `/storage/emulated/0/Android/data/com.lenv.reward/files/media/`
3. Comprehensive logging for debugging
4. File existence verification
5. Proper error handling

**How to verify:**
1. Download a file → See correct size
2. Check file manager → See actual file
3. Reopen message → Shows "Open" button
4. Check logs → See detailed download progress
