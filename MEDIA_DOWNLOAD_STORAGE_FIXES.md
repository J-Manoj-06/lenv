# Media Download & Storage - FINAL FIXES

## What Was Wrong

1. **File size showing "Unknown size"** → Fixed by ensuring fileSize is properly captured
2. **Files not actually saving to mobile device** → Fixed by using Downloads directory

## Key Changes Made

### 1. Storage Location Fixed
**OLD:** Internal app cache (not accessible)
```
/data/data/com.lenv.reward/app_flutter/media/
```

**NEW:** Downloads directory (actually accessible)
```
/storage/emulated/0/Downloads/NewReward_Media/
```

**Fallbacks (if Downloads unavailable):**
1. External storage: `/storage/emulated/0/Android/data/com.lenv.reward/files/media/`
2. App documents: `/data/data/com.lenv.reward/files/media/`

### 2. Comprehensive Logging Added
Every download operation now logs:
- 📁 Which storage location is being used
- 🌐 HTTP download starting
- 📍 Local file path being created
- 📂 Parent directory creation status
- ⬇️ Download progress (every 100KB)
- 💾 File write to disk
- ✅ File verification
- 🔑 Metadata saved

### 3. Error Handling Improved
The system now catches and logs:
- HTTP download errors
- File write failures
- Directory creation issues
- Storage permission problems
- Missing files after write

## How to Test

### Step 1: Send a File to Chat
1. Open a chat group
2. Tap attachment icon
3. Upload a PDF, image, or audio file
4. **CHECK:** Console logs show fileSize being captured

### Step 2: Download a File
1. Find the message with the file
2. **LOOK FOR:** Correct file size (e.g., "2.0 MB", "156 KB")
3. Tap "Download {size}" button
4. **WATCH CONSOLE LOGS** for download progress

**Expected Console Output:**
```
📁 Using Downloads: /storage/emulated/0/Downloads/NewReward_Media
🌐 Making HTTP request to: https://files.lenv1.tech/media/...
📦 Content length: 2.0 MB
📁 Getting local file path for: media/...
📍 Local path: /storage/.../NewReward_Media/media_...
📂 Creating parent directory...
✅ Parent directory exists: true
⬇️ Starting download...
  ⬇️ Progress: 25% (512.0 KB/2.0 MB)
  ⬇️ Progress: 50% (1.0 MB/2.0 MB)
  ⬇️ Progress: 75% (1.5 MB/2.0 MB)
  ⬇️ Progress: 100% (2.0 MB/2.0 MB)
💾 Writing 2.0 MB to disk...
✅ Bytes written successfully
💾 Saved to: /storage/.../NewReward_Media/media_...
📦 File size: 2097152 bytes (2.0 MB)
📂 File exists: true
✅ Download complete: document.pdf (2.0 MB)
🔑 Saved with key: media/1234567/document.pdf
```

### Step 3: Verify Files Actually Exist
**Method 1: File Manager (Easiest)**
1. Open file manager app on your phone
2. Navigate to: **Downloads**
3. Look for folder: **NewReward_Media**
4. **EXPECTED:** See all downloaded files inside
5. Can tap files to open them directly

**Method 2: Android Studio Device Explorer**
1. Connect phone via USB debugging
2. Open Android Studio → Device File Explorer
3. Navigate to: `/storage/emulated/0/Downloads/NewReward_Media/`
4. **EXPECTED:** See all downloaded files
5. Can download files to computer to verify

### Step 4: Reopen File (Test Caching)
1. Close the chat message
2. Reopen the chat
3. Find the same message
4. **EXPECTED:** Button now says "Open {filename}" not "Download"
5. **NO network request** should be made (check logs)
6. Tap "Open" → Should open immediately from local cache

## File Size Display

### How It Works Now

**For images with metadata:**
```
1765476431861.jpg
113.9 KB  ← Actual size from metadata
```

**For PDFs with metadata:**
```
DepositOpeningReceipt_200013501.pdf
1.2 MB  ← Actual size from metadata
```

**For legacy files without size:**
```
File_Name.pdf
Unknown size  ← Will be updated once downloaded
```

### Why It Shows Actual Size
- fileSize is captured during upload: `fileSize: uploadBytes.length`
- Stored in Firestore in mediaMetadata
- Passed to MediaPreviewCard as `fileSize: metadata.fileSize ?? 0`
- Formatted for display: "113.9 KB", "2.0 MB", etc.

## File Storage Structure

### After Download
```
/storage/emulated/0/Downloads/NewReward_Media/
├── media_1234567_document.pdf          (2.0 MB)
├── media_9876543_audio.m4a             (4.5 MB)
├── media_5555555_image.jpg             (156 KB)
└── media_7777777_presentation.pdf      (1.2 MB)
```

### Metadata Storage (SharedPreferences)
```json
{
  "downloaded_media_v1": {
    "media/1234567/document.pdf": {
      "key": "media/1234567/document.pdf",
      "localPath": "/storage/.../NewReward_Media/media_1234567_document.pdf",
      "fileName": "document.pdf",
      "fileSize": 2097152,
      "mimeType": "application/pdf",
      "downloadedAt": "2025-12-12T16:42:00.000Z"
    }
  }
}
```

## Debugging Download Failures

### Issue: Download button appears but fails

**Check Console for:**
1. HTTP error code (e.g., 404, 500)
   - Files.lenv1.tech URL is wrong
   - Verify Cloudflare Worker is running
   
2. File write error
   - Check if `/storage/emulated/0/Downloads/` is writable
   - Check storage space: Settings → Storage
   
3. Parent directory creation failed
   - Permission issue
   - Check WRITE_EXTERNAL_STORAGE permission granted

### Issue: File shows as downloaded but doesn't exist

**Check:**
1. File manager → Downloads/NewReward_Media/
2. Verify file actually exists
3. Check console logs for "File exists: false"

### Issue: "Unknown size" appears

**This is normal if:**
- File is legacy attachment without metadata
- Will update once download completes

**Once downloaded:**
- App checks actual file size: `await file.length()`
- Updates metadata with real size
- Next time you see the card, it will show correct size

## Testing Checklist

- [ ] App launches without errors
- [ ] File sizes display correctly (not "0 B")
- [ ] Download button shows correct size
- [ ] Tapping download starts the process
- [ ] Console shows download progress logs
- [ ] File appears in file manager
- [ ] Reopen message shows "Open" button (not "Download")
- [ ] Tap "Open" opens file immediately
- [ ] Can access file from file manager directly
- [ ] Long press shows "Delete from device"
- [ ] Deleting removes file and button reverts to "Download"

## Important Notes

### Storage Locations (Priority Order)
1. **Downloads/NewReward_Media/** ← BEST (most accessible)
2. **Android/data/com.lenv.reward/files/media/** ← Fallback 1
3. **App documents folder** ← Fallback 2

The system will automatically use the first available location.

### File Naming
- R2 Key: `media/1234567/My File.pdf`
- Local: `media_1234567_My_File.pdf`
- Pattern: `/` → `_`, spaces → `_`, dots → `_`

### Permissions (Already Configured)
- `WRITE_EXTERNAL_STORAGE` ✅
- `READ_EXTERNAL_STORAGE` ✅
- Both included in AndroidManifest.xml

## Architecture Diagram

```
User Sends File (Upload)
    ↓
FileSize captured: 2097152 bytes
    ↓
Stored in mediaMetadata.fileSize
    ↓
Sent to Firebase Firestore
    ↓
Chat displays MediaPreviewCard
    ↓
Shows: [Icon] Filename (2.0 MB) [Download]
    ↓
User taps "Download"
    ↓
MediaRepository.downloadMedia(r2Key)
    ↓
HTTP GET from files.lenv1.tech/media/{r2Key}
    ↓
Stream to /storage/.../Downloads/NewReward_Media/
    ↓
Verify file exists
    ↓
Update metadata with actual file size
    ↓
Button changes to "Open"
    ↓
Show 📂 File Manager or [Audio Icon] Play Audio
    ↓
User taps "Open"
    ↓
Appropriate viewer opens (PDF/Audio/Image)
```

## Summary

✅ **File sizes now display correctly** - Using fileSize from upload metadata
✅ **Files actually save to device** - Using Downloads directory + fallbacks
✅ **Comprehensive logging** - Every step documented in console
✅ **Error handling** - Catches and reports all failure scenarios
✅ **Local caching** - No re-download on reopens
✅ **File manager integration** - Files accessible from file manager

The system will now successfully download files to your mobile device in the Downloads folder where you can see and manage them.
