# Deleted Messages Fix Implementation Guide

## 🚨 Critical Issues Fixed

### Problem 1: Deleted Messages Appearing in Search
**Issue**: Deleted messages were visible in search results because the search function didn't filter `isDeleted` flag.

### Problem 2: R2 Storage Bloat & Cost
**Issue**: When messages were deleted, media files (images, PDFs, audio) remained in Cloudflare R2 storage permanently, causing unnecessary storage costs.

---

## ✅ Solution Implemented in Community Messages

### File: `lib/services/community_service.dart`

#### Fix 1: Filter Deleted Messages from Search
```dart
// BEFORE (showing deleted messages):
final messages = snap.docs
    .map((doc) => CommunityMessageModel.fromFirestore(doc))
    .where(matches)
    .toList();

// AFTER (filtering out deleted messages):
final messages = snap.docs
    .map((doc) => CommunityMessageModel.fromFirestore(doc))
    .where((m) => !(m.isDeleted ?? false)) // Exclude deleted messages
    .where(matches)
    .toList();
```

#### Fix 2: Delete R2 Files on Message Deletion
```dart
// BEFORE (only soft delete in Firestore, files remain in R2):
await messageRef.update({
  'isDeleted': true,
  'imageUrl': '', // Only clears reference, file stays in R2!
  'fileUrl': '',
});

// AFTER (deletes R2 files before soft delete):
// 1. Extract R2 keys from message data
final r2Keys = _extractR2KeysFromMessage(data);

// 2. Delete files from R2
final r2Service = CloudflareR2Service(...);
for (final key in r2Keys) {
  await r2Service.deleteFile(key: key);
}

// 3. Then soft delete in Firestore
await messageRef.update({
  'isDeleted': true,
  'deletedAt': FieldValue.serverTimestamp(),
  'content': 'This message was deleted',
  'imageUrl': '',
  'fileUrl': '',
  'mediaMetadata': null,
});
```

#### Helper Methods Added
```dart
/// Extract R2 keys from message data for cleanup
List<String> _extractR2KeysFromMessage(Map<String, dynamic>? data) {
  // Extracts keys from:
  // - mediaMetadata.r2Key (primary)
  // - mediaMetadata.thumbnailR2Key (for thumbnails)
  // - imageUrl (legacy fallback)
  // - fileUrl (legacy fallback)
}

/// Extract R2 key from full URL
String _extractR2KeyFromUrl(String url) {
  // Converts: https://files.lenv1.tech/community/abc123.jpg
  // To: community/abc123.jpg
}
```

---

## 🔧 Implementation Checklist for Other Chat Types

Apply these same fixes to other message services:

### Services to Update:
- [ ] **Group Chat** (`lib/services/group_chat_service.dart` or similar)
- [ ] **Staff Room Chat** (`lib/services/staff_room_service.dart` or similar)
- [ ] **Direct Messages** (if applicable)
- [ ] **Teacher-Student Chat** (if applicable)

### For Each Service:

#### Step 1: Add Import
```dart
import 'cloudflare_r2_service.dart';
import '../config/cloudflare_config.dart';
```

#### Step 2: Update Search Functions
Look for functions like `searchMessages()` and add the deleted filter:
```dart
.where((m) => !(m.isDeleted ?? false)) // Add this line
.where(matches)
```

#### Step 3: Update Delete Functions
Look for functions like `deleteMessage()` and add R2 cleanup:
1. Extract R2 keys before deletion
2. Delete files from R2
3. Then soft delete in Firestore

#### Step 4: Add Helper Methods
Copy the helper methods from `community_service.dart`:
- `_extractR2KeysFromMessage()`
- `_extractR2KeyFromUrl()`

---

## 💰 Cost Savings Impact

### Before Fix:
- ❌ Every deleted message's files remain in R2 forever
- ❌ Costs accumulate: $0.015/GB/month × deleted files
- ❌ Example: 10,000 deleted messages with 5MB files = 50GB = **$0.75/month wasted**

### After Fix:
- ✅ Deleted message files are removed from R2 immediately
- ✅ Zero storage cost for deleted messages
- ✅ Clean storage = predictable costs

---

## 🔍 Where Deleted Items Can Appear

### Search Functions to Check:
1. **Message Search** - ✅ Fixed in community_service.dart
2. **Group Chat Search** - Needs same fix
3. **Staff Room Search** - Needs same fix
4. **Announcement Search** - Check if applicable
5. **Media Gallery Search** - Check if applicable

### Query Functions to Check:
Look for any function that fetches messages without filtering `isDeleted`:
```dart
// BAD - Will show deleted messages:
.collection('messages')
.orderBy('createdAt')
.get()

// GOOD - Filters out deleted messages:
.collection('messages')
.where('isDeleted', isEqualTo: false) // Firestore query
.orderBy('createdAt')
.get()

// OR (client-side filter):
.get()
.docs
.where((doc) => !(doc.data()['isDeleted'] ?? false))
```

---

## 🧪 Testing Guide

### Test 1: Search Filter
1. Send a message in community
2. Verify it appears in search
3. Delete the message
4. Search again - message should NOT appear
5. ✅ PASS: Deleted message is filtered out

### Test 2: R2 Cleanup
1. Send a message with image/PDF/audio
2. Check R2 storage (via Cloudflare dashboard)
3. Delete the message
4. Wait 1 minute
5. Check R2 storage again
6. ✅ PASS: File is deleted from R2

### Test 3: Other Users
1. User A sends message with media
2. User B searches and sees the message
3. User A deletes the message
4. User B searches again
5. ✅ PASS: User B doesn't see deleted message

---

## 🚀 Priority Implementation Order

1. **HIGH PRIORITY**: Group Chat & Staff Room (most used)
2. **MEDIUM PRIORITY**: Direct Messages
3. **LOW PRIORITY**: Any other chat types

---

## 📊 Monitoring

After implementing fixes:
1. Monitor R2 storage usage (should decrease or stabilize)
2. Check Cloudflare R2 dashboard for storage trends
3. Monitor delete operation success rate in logs
4. Watch for any "Failed to delete R2 file" warnings

---

## ⚠️ Edge Cases Handled

1. **R2 deletion fails**: Continues with Firestore deletion (message still marked deleted)
2. **Empty R2 keys**: Safely skips deletion
3. **Invalid URLs**: Handled gracefully with try-catch
4. **Multiple media files**: All files deleted in loop
5. **Thumbnails**: Both main file and thumbnail deleted

---

## 🔄 Future Enhancements (Optional)

Consider creating a Cloudflare Worker for orphaned file cleanup:
- Similar to announcement cleanup workers
- Runs hourly to check for orphaned files
- Cross-references Firestore and R2
- Deletes files not referenced in any active message

---

**Status**: ✅ Implemented in Community Messages  
**Next**: Implement in Group Chat and Staff Room  
**Estimated Time**: 30 minutes per service
