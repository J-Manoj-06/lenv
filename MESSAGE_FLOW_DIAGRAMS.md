# Message Flow Comparison: Community Chat vs Staff Room

## Upload Flow Diagram

### Community Chat - PROBLEMATIC FLOW
```
1. User picks image
   ↓
2. _uploadMultipleImages()
   ├─ Create MediaMetadata
   │  └─ thumbnail = /data/user/.../image.jpg  ❌ LOCAL PATH
   │  └─ localPath = /data/user/.../image.jpg
   │
   └─ Add to _pendingMessages
      └─ setState() → UI shows with local file
   
3. BackgroundUploadService.queueUpload()
   ├─ Upload to R2
   └─ Get back mediaMessage with:
      └─ r2Url = "https://r2.example.com/file"
      └─ thumbnailUrl = "https://r2.example.com/thumb"  (IF PROVIDED)

4. background_upload_service.dart processes upload
   ├─ Create new MediaMetadata
   │  ├─ publicUrl = mediaMessage.r2Url  ✅ CORRECT
   │  ├─ thumbnail = mediaMessage.thumbnailUrl ← CHECK THIS!
   │  │  └─ If null:  thumbnail = '' ❌ EMPTY!
   │  │  └─ If set:   thumbnail = URL ✅ CORRECT
   │  └─ localPath = NOT SET ✅ CORRECT (excluded by toFirestore())
   │
   └─ Call _communityService.sendMessage(mediaMetadata)
      └─ Firestore save:
         {
           "mediaMetadata": {
             "thumbnail": ???  ← DEPENDS ON ABOVE
             "localPath": null ✅ NOT SAVED (correct)
           }
         }

5. Message arrives at receiver (or sender refresh)
   ├─ Load from Firestore
   ├─ MediaMetadata.fromFirestore()
   │  ├─ thumbnail = data['thumbnail']  ← GETS SAVED VALUE
   │  │  └─ If was URL: ✅ Can display thumbnail
   │  │  └─ If was '': ❌ BROKEN - no thumbnail
   │  │  └─ If was local path (OLD BUG): ❌ BROKEN - invalid path
   │  └─ localPath = null  ← NOT IN FIRESTORE (correct)
   │
   └─ Display via _buildMetadataAttachment()
      └─ MediaPreviewCard receives:
         ├─ thumbnail (from Firestore) - might be '' or URL
         ├─ localPath = null or value from _localSenderMediaPaths
         │  └─ _localSenderMediaPaths only has CURRENT SESSION entries
         │  └─ So old messages will have localPath = null
         └─ If thumbnail is '', shows broken image ❌
```

### Staff Room - CORRECT FLOW (Single File)
```
1. User picks document/file
   ↓
2. _uploadFile()
   ├─ Create pending message Map
   │  ├─ attachmentUrl = 'pending'
   │  ├─ attachmentName = 'document.pdf'
   │  ├─ attachmentSize = 123456
   │  ├─ thumbnailUrl = null or placeholder
   │  └─ No mediaMetadata field
   │
   └─ Store in _localFilePaths[messageId] = local path
      └─ Only used for PENDING messages

3. BackgroundUploadService.queueUpload()
   ├─ Upload to R2
   └─ Get back mediaMessage with:
      └─ r2Url = "https://r2.example.com/file"
      └─ thumbnailUrl = "https://r2.example.com/thumb"  ✅ REAL URL

4. background_upload_service.dart processes upload
   ├─ Create MediaMetadata for building info only
   │  ├─ publicUrl = mediaMessage.r2Url  ✅
   │  └─ thumbnail = mediaMessage.thumbnailUrl  ✅
   │
   └─ Call FirebaseFirestore.instance.collection().set()
      └─ Firestore save (NO mediaMetadata field):
         {
           "attachmentUrl": "https://r2.example.com/file",  ✅
           "attachmentType": "application/octet-stream",
           "attachmentName": "document.pdf",
           "attachmentSize": 123456,
           "thumbnailUrl": "https://r2.example.com/thumb",  ✅
         }

5. Message arrives at receiver (or reload)
   ├─ Load from Firestore (RAW MAP, no model conversion)
   ├─ Extract fields directly:
   │  ├─ attachmentUrl = "https://r2.example.com/file"  ✅ REAL URL
   │  ├─ attachmentName = "document.pdf"
   │  ├─ thumbnailUrl = "https://r2.example.com/thumb"  ✅ REAL URL
   │  └─ isPending = false
   │
   └─ Display via _buildAttachmentWidget()
      └─ MediaPreviewCard receives:
         ├─ thumbnailBase64 = "https://r2.example.com/thumb"  ✅ REAL URL
         ├─ localPath = null (not in Map, isPending=false)  ✅ CORRECT
         └─ r2Key extracted from URL  ✅ CAN DOWNLOAD
```

---

## Loading Previously Uploaded Messages

### Community Chat Problem
```
Scenario: User views a message uploaded 1 hour ago

1. Load message from Firestore
   ├─ Data: { mediaMetadata: { thumbnail: ???, localPath: null } }
   └─ Convert via MediaMetadata.fromFirestore()
      ├─ thumbnail = ??? (whatever was saved)
      │  ├─ If was empty '': ❌ No thumbnail
      │  ├─ If was URL: ✅ Can show thumbnail  
      │  └─ If was local path: ❌ Invalid path (old session)
      └─ localPath = null  ← NOT IN FIRESTORE

2. Render in _buildMetadataAttachment()
   └─ MediaPreviewCard(
       thumbnailBase64: metadata.thumbnail,  ← BROKEN IF ''
       localPath: metadata.localPath ?? _localSenderMediaPaths[msgId],
      )
      │
      └─ _localSenderMediaPaths[msgId] = ???
         ├─ If current user sent it this session: ✅ Has entry
         │  └─ Can show local file
         ├─ If other user sent it: ❌ No entry
         │  └─ Must download (slow)
         └─ If user sent it, app closed, app reopened: ❌ Entry gone
            └─ Must download (LOST CACHE)

Result: ❌ BROKEN if thumbnail wasn't properly saved as URL
```

### Staff Room Correct Approach
```
Scenario: User views a message uploaded 1 hour ago

1. Load message from Firestore
   ├─ Data: { attachmentUrl: "https://...", thumbnailUrl: "https://..." }
   └─ Use directly (no model conversion)

2. Build in _buildAttachmentWidget()
   └─ MediaPreviewCard(
       thumbnailBase64: thumbnailUrl,  ← "https://r2.example.com/thumb"
       localPath: isPending ? _localFilePaths[msgId] : null,
       r2Key: extracted from attachmentUrl,
      )
      │
      └─ Result: ✅ HAS REAL THUMBNAIL URL
         ├─ Can show cached thumbnail
         ├─ Can download full file from r2Key
         └─ Works every time

Result: ✅ WORKS because thumbnail is always a URL
```

---

## Data Structure Comparison

### Community Chat Message in Firestore

```json
{
  "id": "msg_123",
  "senderId": "user_456",
  "senderName": "Alice",
  "message": "Check this out",
  "timestamp": 1234567890,
  "type": "image",
  "mediaMetadata": {
    "messageId": "pending_123_0",
    "r2Key": "files/image.jpg",
    "publicUrl": "https://r2.example.com/files/image.jpg",
    "thumbnail": "???" ← PROBLEM: Could be empty or invalid!
    // "localPath" is intentionally NOT here (not saved to firestore)
    "fileSize": 12345,
    "mimeType": "image/jpeg",
    "originalFileName": "photo.jpg",
    "uploadedAt": {...},
    "expiresAt": {...}
  },
  "multipleMedia": null
}
```

### Staff Room Single File in Firestore

```json
{
  "id": "msg_789",
  "senderId": "user_456",
  "senderName": "Teacher",
  "senderRole": "teacher",
  "text": "",
  "timestamp": {...},
  "createdAt": 1234567890,
  "attachmentUrl": "https://r2.example.com/files/document.pdf" ✅ URL
  "attachmentType": "application/pdf",
  "attachmentName": "document.pdf",
  "attachmentSize": 567890,
  "thumbnailUrl": "https://r2.example.com/thumbs/document.jpg" ✅ URL
  // No mediaMetadata field at all
}
```

---

## What Thumbnail Value Should Be

### During Pending State (UI Display)
- **Source**: Local device file path
- **Value**: `/data/user/0/com.example/cache/IMG_123.jpg`
- **UI**: Shows with File() widget
- **Problem**: This gets lost when app restarts

### After Upload (Firestore Storage)
- **Source**: Generated by media upload service
- **Value**: `https://r2.cdn.example.com/thumbs/file_id_thumb.jpg`
- **UI**: Shows with CachedNetworkImage
- **Correct**: Works across sessions, survives app restart

### Current Community Chat Bug
- **Upload pending**: ✅ Local path (works for pending)
- **Sent to Firestore**: ❌ Might be empty string or stale local path
- **On reload**: ❌ Cannot display thumbnail

---

## Timeline of Bug Manifestation

```
User sends image in Community Chat:

T+0s: User picks image
     └─ Thumbnail: /data/user/.../IMG_123.jpg  ✅ Shows while uploading

T+5s: Upload completes
     └─ thumbnailUrl from MediaUploadService: (needs verification)
     └─ Saved to Firestore: ???

T+10s: Message arrives from Firestore
     └─ If thumbnail saved correctly: ✅ Shows thumbnail
     └─ If thumbnail is empty: ❌ Broken display
     └─ If thumbnail is old path: ❌ Broken display

T+30min: User closes and reopens app
     └─ Message reloads from cache
     └─ Thumbnail field: ??? (unchanged)
     └─ If empty: ❌ Still broken
     └─ If invalid path: ❌ Still broken

```

---

## Checklist for Verification

- [ ] Check what `MediaUploadService` returns as `thumbnailUrl`
  - Location: `lib/services/media_upload_service.dart`
  - Look for: `thumbnailUrl` field in response

- [ ] Verify thumbnail value in Firestore after upload
  - Check Console URL: `https://console.firebase.google.com/`
  - Collection: `communities/{id}/messages`
  - Field: `mediaMetadata.thumbnail`
  - Should be: URL (https://...) or base64 encoded image
  - Not: Local paths (/data/user/...) or empty strings

- [ ] Test community message after reload
  - Send image in community chat
  - Wait for delivery
  - Close and reopen app
  - Check: Does thumbnail display?

- [ ] Compare with staff room message
  - Send file in staff room  
  - Wait for delivery
  - Close and reopen app
  - Check: Does thumbnail display? (Should be ✅)
