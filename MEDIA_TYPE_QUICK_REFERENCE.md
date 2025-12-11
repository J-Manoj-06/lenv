# 📌 Media Upload Quick Reference

## When to Use Each MediaType

### ⏰ `mediaType: 'announcement'` 
**Auto-deleted after 24 hours**

Use for:
- Class announcements
- Institute-wide announcements
- Time-sensitive notifications
- Temporary event posters

```dart
await mediaUploadService.uploadMedia(
  file: file,
  conversationId: announcementId,
  senderId: currentUser.uid,
  senderRole: 'teacher',
  mediaType: 'announcement', // ← Ephemeral
);
```

---

### 💬 `mediaType: 'message'` 
**Permanent storage**

Use for:
- 1-on-1 chat messages
- Direct messages between users
- Personal conversations
- Private file sharing

```dart
await mediaUploadService.uploadMedia(
  file: file,
  conversationId: conversationId,
  senderId: currentUser.uid,
  senderRole: userRole,
  mediaType: 'message', // ← Default, permanent
);
```

---

### 👥 `mediaType: 'community'` 
**Permanent storage**

Use for:
- Group chat messages
- Community posts
- Shared resources
- Study materials

```dart
await mediaUploadService.uploadMedia(
  file: file,
  conversationId: communityId,
  senderId: currentUser.uid,
  senderRole: userRole,
  mediaType: 'community', // ← Permanent
);
```

---

## Deletion Timeline

| MediaType | Lifetime | Deletion Method |
|-----------|----------|-----------------|
| `announcement` | 24 hours | Auto-deleted by Cloud Function |
| `message` | Permanent | Never auto-deleted |
| `community` | Permanent | Never auto-deleted |

---

## ⚠️ Important Notes

1. **Default behavior**: If you don't specify `mediaType`, it defaults to `'message'` (permanent)

2. **Soft delete**: Announcement media is soft-deleted first (sets `deletedAt` timestamp)
   - Files deleted from R2 immediately
   - Firestore document kept for 30 days (audit trail)
   - Hard-deleted after 30 days

3. **Cloud Function schedule**:
   - Runs every hour to check for 24h+ old announcements
   - Batch processes up to 50 media items per run

4. **Cost optimization**:
   - Only announcement media is cleaned up
   - Messages and community posts remain for user access
   - Reduces R2 storage costs significantly

---

## 🔧 Testing

### Test Announcement Auto-Deletion
```dart
// 1. Upload test announcement
final media = await mediaUploadService.uploadMedia(
  file: testFile,
  conversationId: 'test-announcement',
  senderId: 'test-user',
  senderRole: 'teacher',
  mediaType: 'announcement',
);

// 2. Note the media.id and media.r2Url

// 3. Wait 25 hours (or manually trigger Cloud Function)

// 4. Query Firestore to verify deletion
final doc = await FirebaseFirestore.instance
  .collection('media_messages')
  .doc(media.id)
  .get();

print('deletedAt: ${doc.data()?['deletedAt']}'); // Should be set
```

### Verify R2 Deletion
```dart
// Try to access the R2 URL after 24 hours
// Should return 404 Not Found
```

---

## 🚨 Common Mistakes

❌ **DON'T** use `mediaType: 'announcement'` for permanent content
```dart
// BAD - User's important message will be deleted!
await mediaUploadService.uploadMedia(
  file: importantDocument,
  conversationId: chatId,
  senderId: userId,
  senderRole: 'student',
  mediaType: 'announcement', // ← Will auto-delete!
);
```

✅ **DO** use correct mediaType for each feature
```dart
// GOOD - Permanent storage for important content
await mediaUploadService.uploadMedia(
  file: importantDocument,
  conversationId: chatId,
  senderId: userId,
  senderRole: 'student',
  mediaType: 'message', // ← Permanent
);
```

---

## 📱 UI Considerations

### Show Expiry Warning for Announcements
```dart
if (media.mediaType == 'announcement') {
  final expiresAt = media.createdAt.add(Duration(hours: 24));
  final timeLeft = expiresAt.difference(DateTime.now());
  
  return Text(
    'Expires in ${timeLeft.inHours}h ${timeLeft.inMinutes % 60}m',
    style: TextStyle(color: Colors.orange),
  );
}
```

### Filter Out Deleted Media
```dart
// Query only active media
final activeMedia = await FirebaseFirestore.instance
  .collection('media_messages')
  .where('conversationId', '==', conversationId)
  .where('deletedAt', '==', null) // ← Filter soft-deleted
  .orderBy('createdAt', descending: true)
  .get();
```

---

## 📚 Related Files

- **Model**: `lib/models/media_message.dart`
- **Service**: `lib/services/media_upload_service.dart`
- **Provider**: `lib/providers/media_chat_provider.dart`
- **Cloud Function**: `functions/deleteExpiredMediaAnnouncements.js`
- **Full Setup Guide**: `ANNOUNCEMENT_MEDIA_AUTO_DELETE_SETUP.md`
- **Documentation**: `lib/services/MEDIA_TYPE_DOCUMENTATION.dart`
