# Smart Media Caching - Quick Reference

## 🚀 Quick Start (3 Steps)

### 1. Display Media
```dart
import '../widgets/universal_media_widget.dart';

UniversalMediaWidget(
  message: cachedMediaMessage,
  isMe: isCurrentUser,
)
```

### 2. Load Messages
```dart
import '../services/message_initialization_service.dart';

final initService = MessageInitializationService();
final initialized = await initService.initializeMediaMessages(messages);
```

### 3. Send Media
```dart
import '../services/smart_media_upload_service.dart';

final uploadService = SmartMediaUploadService();
final message = await uploadService.prepareMediaForSending(
  file: pickedFile,
  messageId: messageId,
  senderId: currentUserId,
  senderRole: userRole,
  conversationId: chatId,
  uploadUrl: cloudflareUrl,
);
```

---

## 📦 Core Services

### MediaCacheService
**Purpose:** Manage local file storage  
**Key Methods:**
- `checkIfMediaExists(localPath)` - Check if file exists
- `getLocalFilePath(messageId, mediaType)` - Get expected path
- `saveMediaFile(messageId, mediaType, bytes)` - Save file
- `getCacheStatistics()` - Get cache stats

### SmartMediaUploadService
**Purpose:** Upload media with local-first strategy  
**Key Methods:**
- `prepareMediaForSending()` - Save locally + upload to cloud
- `retryUpload()` - Retry failed uploads

### MessageInitializationService
**Purpose:** Check local cache when loading messages  
**Key Methods:**
- `initializeMediaMessage(message)` - Single message
- `initializeMediaMessages(messages)` - Batch processing

---

## 🎨 Universal Media Widget

**Supports:**
- ✅ Images (.jpg, .png, .gif, .webp)
- ✅ Audio (.mp3, .wav, .aac, .m4a)
- ✅ PDF documents
- ✅ Other documents (.doc, .txt, etc.)

**Features:**
- Shows download button if not cached
- Opens file directly if cached
- Progress indicator during download
- Error handling and retry

---

## 🔄 Message Flow

### Receiving Media
```
Firestore → CachedMediaMessage → Check Local Cache → UniversalMediaWidget
```

### Sending Media
```
Pick File → Save Locally → Upload Cloud → Save to Firestore → Display Immediately
```

---

## 📁 Directory Structure

```
AppDirectory/lenv_media/
  ├── images/{messageId}.jpg
  ├── audio/{messageId}.mp3
  └── documents/{messageId}.pdf
```

---

## 🔧 Integration Pattern

```dart
// 1. Import services
import '../services/media_cache_service.dart';
import '../services/smart_media_upload_service.dart';
import '../services/message_initialization_service.dart';
import '../widgets/universal_media_widget.dart';

// 2. Create service instances
final _cacheService = MediaCacheService();
final _uploadService = SmartMediaUploadService();
final _initService = MessageInitializationService();

// 3. Load and initialize messages
Future<void> loadMessages() async {
  final docs = await firestore.collection('messages').get();
  final messages = docs.map((d) => CachedMediaMessage.fromFirestore(d)).toList();
  final initialized = await _initService.initializeMediaMessages(messages);
  setState(() => _messages = initialized);
}

// 4. Display with UniversalMediaWidget
Widget buildMessage(CachedMediaMessage msg) {
  return UniversalMediaWidget(
    message: msg,
    isMe: msg.senderId == currentUserId,
  );
}

// 5. Send media
Future<void> sendMedia(File file) async {
  final msg = await _uploadService.prepareMediaForSending(
    file: file,
    messageId: generateId(),
    senderId: currentUserId,
    senderRole: 'student',
    conversationId: chatId,
    uploadUrl: uploadEndpoint,
  );
  
  if (msg != null) {
    await firestore.collection('messages').doc(msg.messageId).set(msg.toFirestore());
  }
}
```

---

## ⚠️ Critical Rules

### ✅ DO
- Always check local cache when loading messages
- Save media locally BEFORE uploading to cloud
- Use `UniversalMediaWidget` for all media display
- Generate local paths using `MediaCacheService`
- Initialize messages with `MessageInitializationService`

### ❌ DON'T
- Don't store `localPath` in Firestore (device-specific)
- Don't auto-download media on message load
- Don't skip local cache check
- Don't upload before saving locally
- Don't hardcode file paths

---

## 🔍 Debugging

### Check if media is cached
```dart
final exists = await _cacheService.checkIfMediaExists(localPath);
print('Media cached: $exists');
```

### View cache statistics
```dart
final stats = await _cacheService.getCacheStatistics();
print('Total files: ${stats.totalFiles}');
print('Total size: ${stats.formattedTotalSize}');
```

### Clear cache
```dart
final cleared = await _cacheService.clearAllMediaCache();
print('Cleared: $cleared');
```

---

## 🎯 Key Benefits

1. **No Unnecessary Downloads** - Check local first
2. **Instant Access** - Media available immediately after sending
3. **Bandwidth Savings** - Download only when needed
4. **Offline Support** - Cached media works offline
5. **Consistent Behavior** - Same logic across all chat types

---

## 📱 Chat Modules to Update

- [ ] Community Chat (`community_chat_page.dart`)
- [ ] Group Chat (`group_chat_page.dart`)
- [ ] Staff Room Chat (`staff_room_chat_page.dart`)
- [ ] Teacher-Parent Chat (`chat_screen.dart`)
- [ ] Any other chat screens

---

## 🆘 Common Issues

### Issue: Media not showing as downloaded
**Solution:** Call `MessageInitializationService.initializeMediaMessages()`

### Issue: Re-downloading after app restart
**Solution:** Not checking local cache on load

### Issue: Upload fails but file not accessible
**Solution:** Use `SmartMediaUploadService.prepareMediaForSending()`

---

## 📚 Additional Resources

- Full Integration Guide: `SMART_MEDIA_CACHING_INTEGRATION_GUIDE.md`
- Example Code: `lib/examples/staff_room_chat_caching_example.dart`
- Service Docs: Check individual service files for detailed comments

---

## 🎓 Example Conversions

### StaffRoomMessage → CachedMediaMessage
```dart
CachedMediaMessage(
  messageId: staffMsg.id,
  senderId: staffMsg.senderId,
  senderRole: 'teacher',
  conversationId: instituteId,
  fileName: staffMsg.mediaMetadata!.originalFileName ?? 'media',
  fileType: staffMsg.mediaMetadata!.mimeType ?? 'image/jpeg',
  fileSize: staffMsg.mediaMetadata!.fileSize ?? 0,
  cloudUrl: staffMsg.mediaMetadata!.publicUrl,
  mediaType: MediaTypeCategoryExtension.fromMimeType(
    staffMsg.mediaMetadata!.mimeType ?? 'image/jpeg',
  ),
  createdAt: DateTime.fromMillisecondsSinceEpoch(staffMsg.createdAt),
)
```

### GroupChatMessage → CachedMediaMessage
```dart
CachedMediaMessage(
  messageId: groupMsg.id,
  senderId: groupMsg.senderId,
  senderRole: 'student',
  conversationId: '${groupMsg.classId}_${groupMsg.subjectId}',
  fileName: groupMsg.mediaMetadata!.originalFileName ?? 'media',
  fileType: groupMsg.mediaMetadata!.mimeType ?? 'image/jpeg',
  fileSize: groupMsg.mediaMetadata!.fileSize ?? 0,
  cloudUrl: groupMsg.mediaMetadata!.publicUrl,
  mediaType: MediaTypeCategoryExtension.fromMimeType(
    groupMsg.mediaMetadata!.mimeType ?? 'image/jpeg',
  ),
  createdAt: DateTime.fromMillisecondsSinceEpoch(groupMsg.timestamp),
)
```

---

**Remember:** The system automatically handles cache checking, downloads, and storage. You just need to use the right widgets and services!
