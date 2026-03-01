# Smart Media Caching System - Integration Guide

## Overview
This guide explains how to integrate the smart media caching system into all chat modules in the Lenv application.

**Supported Media Types:** Images, Audio, PDF, and Documents (video not supported)

## Core Components Created

### 1. Services
- **`media_cache_service.dart`** - Core caching service with directory management
- **`smart_media_upload_service.dart`** - Upload service that saves locally first
- **`message_initialization_service.dart`** - Initializes messages with local cache check

### 2. Models
- **`cached_media_message.dart`** - Enhanced message model with caching support

### 3. Widgets
- **`universal_media_widget.dart`** - Universal component for all media types

---

## Integration Steps

### Step 1: Update Chat Message Display

For **ALL** chat modules, replace media display logic with `UniversalMediaWidget`.

#### Example for Community Chat:

```dart
// In community_chat_page.dart or similar

import '../widgets/universal_media_widget.dart';
import '../models/cached_media_message.dart';

Widget _buildMediaMessage(CommunityMessageModel message) {
  // Convert to CachedMediaMessage
  final cachedMessage = CachedMediaMessage(
    messageId: message.messageId,
    senderId: message.senderId,
    senderRole: message.senderRole,
    conversationId: message.communityId,
    fileName: message.fileName.isNotEmpty ? message.fileName : 'media',
    fileType: message.mediaMetadata?.mimeType ?? 'application/octet-stream',
    fileSize: message.mediaMetadata?.fileSize ?? 0,
    cloudUrl: message.imageUrl.isNotEmpty ? message.imageUrl : message.fileUrl,
    thumbnailUrl: message.mediaMetadata?.thumbnail,
    mediaType: MediaTypeCategory.fromMimeType(
      message.mediaMetadata?.mimeType ?? 'application/octet-stream',
    ),
    createdAt: message.createdAt,
  );

  return UniversalMediaWidget(
    message: cachedMessage,
    isMe: message.senderId == currentUserId,
    onMediaUpdated: (updatedMessage) {
      // Optional: Update local state when media is downloaded
      setState(() {
        // Update your message list
      });
    },
  );
}
```

#### Apply to these files:
1. `/lib/screens/messages/community_chat_page.dart`
2. `/lib/screens/messages/group_chat_page.dart`
3. `/lib/screens/messages/staff_room_chat_page.dart`
4. `/lib/screens/teacher/messages/chat_screen.dart`
5. Any other chat screens

---

### Step 2: Update Message Loading Logic

When loading messages from Firestore, initialize them with local cache check.

```dart
import '../services/message_initialization_service.dart';

class ChatPage extends StatefulWidget {
  // ...
}

class _ChatPageState extends State<ChatPage> {
  final MessageInitializationService _initService = MessageInitializationService();
  List<CachedMediaMessage> _messages = [];

  Future<void> _loadMessages() async {
    // Load from Firestore
    final snapshot = await FirebaseFirestore.instance
        .collection('messages')
        .where('conversationId', isEqualTo: widget.conversationId)
        .get();

    // Convert to CachedMediaMessage
    final messages = snapshot.docs.map((doc) {
      // Convert your Firestore doc to CachedMediaMessage
      return CachedMediaMessage.fromFirestore(doc);
    }).toList();

    // IMPORTANT: Initialize with local cache check
    final initializedMessages = await _initService.initializeMediaMessages(messages);

    setState(() {
      _messages = initializedMessages;
    });
  }
}
```

---

### Step 3: Update Media Sending Logic

When users send media, use `SmartMediaUploadService` to save locally first.

```dart
import 'package:image_picker/image_picker.dart';
import '../services/smart_media_upload_service.dart';

class ChatPage extends StatefulWidget {
  // ...
}

class _ChatPageState extends State<ChatPage> {
  final SmartMediaUploadService _uploadService = SmartMediaUploadService();

  Future<void> _sendMedia() async {
    // Pick file
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    final messageId = FirebaseFirestore.instance.collection('messages').doc().id;

    // Show sending indicator
    setState(() {
      // Add placeholder message
    });

    // Prepare media (saves locally first, then uploads)
    final mediaMessage = await _uploadService.prepareMediaForSending(
      file: file,
      messageId: messageId,
      senderId: currentUserId,
      senderRole: currentUserRole,
      conversationId: widget.conversationId,
      uploadUrl: 'YOUR_CLOUDFLARE_UPLOAD_URL',
      onProgress: (progress) {
        // Update progress indicator
      },
    );

    if (mediaMessage != null) {
      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .set(mediaMessage.toFirestore());

      // Media is immediately available locally!
      // User can open it right away without re-downloading
    }
  }
}
```

---

### Step 4: Handle App Lifecycle Events

Support logout/login and app reinstall scenarios.

```dart
class ChatPage extends StatefulWidget {
  // ...
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshMediaCache();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App resumed - refresh media cache availability
      _refreshMediaCache();
    }
  }

  Future<void> _refreshMediaCache() async {
    // Re-check which media files are available locally
    final updatedMessages = await _initService.initializeMediaMessages(_messages);
    setState(() {
      _messages = updatedMessages;
    });
  }
}
```

---

## Specific Integration Examples

### Community Chat (community_chat_page.dart)

```dart
// Find where messages are displayed
// Replace this:
if (message.imageUrl.isNotEmpty) {
  return Image.network(message.imageUrl);
}

// With this:
if (message.imageUrl.isNotEmpty || message.fileUrl.isNotEmpty) {
  final cachedMessage = _convertToCachedMediaMessage(message);
  return UniversalMediaWidget(
    message: cachedMessage,
    isMe: message.senderId == widget.currentUserId,
  );
}
```

### Group Chat (group_chat_page.dart)

```dart
// Similar pattern
if (message.mediaMetadata != null) {
  final cachedMessage = CachedMediaMessage(
    messageId: message.id,
    senderId: message.senderId,
    senderRole: 'student',
    conversationId: '${message.classId}_${message.subjectId}',
    fileName: message.mediaMetadata!.originalFileName ?? 'media',
    fileType: message.mediaMetadata!.mimeType ?? 'image/jpeg',
    fileSize: message.mediaMetadata!.fileSize ?? 0,
    cloudUrl: message.mediaMetadata!.publicUrl,
    thumbnailUrl: message.mediaMetadata!.thumbnail,
    mediaType: MediaTypeCategory.fromMimeType(
      message.mediaMetadata!.mimeType ?? 'image/jpeg',
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(message.timestamp),
  );

  return UniversalMediaWidget(message: cachedMessage);
}
```

### Staff Room Chat (staff_room_chat_page.dart)

```dart
// In message builder
if (message.mediaMetadata != null) {
  final cachedMessage = CachedMediaMessage(
    messageId: message.id,
    senderId: message.senderId,
    senderRole: 'teacher',
    conversationId: widget.instituteId,
    fileName: message.mediaMetadata!.originalFileName ?? 'media',
    fileType: message.mediaMetadata!.mimeType ?? 'image/jpeg',
    fileSize: message.mediaMetadata!.fileSize ?? 0,
    cloudUrl: message.mediaMetadata!.publicUrl,
    mediaType: MediaTypeCategory.fromMimeType(
      message.mediaMetadata!.mimeType ?? 'image/jpeg',
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(message.createdAt),
  );

  return UniversalMediaWidget(
    message: cachedMessage,
    isMe: message.senderId == currentTeacherId,
  );
}
```

---

## Testing Checklist

### Basic Functionality
- [ ] User can send media (image, audio, video, PDF)
- [ ] Media is instantly accessible after sending (no re-download)
- [ ] Download button appears for undownloaded media
- [ ] Download button works and saves to local cache
- [ ] Downloaded media opens correctly

### Cache Persistence
- [ ] Media remains cached after app restart
- [ ] Media remains cached after logout/login
- [ ] Different users on same device have separate caches

### Edge Cases
- [ ] Large files download correctly
- [ ] Download progress is shown
- [ ] Download errors are handled gracefully
- [ ] Network interruptions during download are handled
- [ ] Corrupted local files are handled

---

## Configuration

### Directory Structure
The system creates this structure automatically:
```
AppDirectory/
  lenv_media/
    images/
      {messageId}.jpg
      {messageId}.png
    audio/
      {messageId}.mp3
      {messageId}.aac
    videos/
      {messageId}.mp4
    documents/
      {messageId}.pdf
      {messageId}.doc
```

### Storage Management

Add cache management to settings page:

```dart
import '../services/media_cache_service.dart';

class SettingsPage extends StatefulWidget {
  // ...
}

class _SettingsPageState extends State<SettingsPage> {
  final MediaCacheService _cacheService = MediaCacheService();

  Future<void> _showCacheStats() async {
    final stats = await _cacheService.getCacheStatistics();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cache Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Files: ${stats.totalFiles}'),
            Text('Total Size: ${stats.formattedTotalSize}'),
            const SizedBox(height: 16),
            ...stats.stats.entries.map((entry) {
              return Text(
                '${entry.key.name}: ${entry.value.fileCount} files (${entry.value.formattedSize})',
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('This will delete all cached media files. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final results = await _cacheService.clearAllMediaCache();
      
      final totalCleared = results.values.fold(0, (sum, count) => sum + count);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleared $totalCleared files')),
        );
      }
    }
  }
}
```

---

## Performance Optimization

### Batch Operations
When loading many messages:

```dart
// Good: Batch initialization
final initialized = await _initService.initializeMediaMessages(allMessages);

// Bad: One at a time (slow)
for (final message in allMessages) {
  await _initService.initializeMediaMessage(message);
}
```

### Memory Management
For image thumbnails, use the existing thumbnail system to avoid loading full images in list view.

---

## Migration Guide

If you have existing media in chats:

1. Existing media will show download buttons (correct behavior)
2. Once downloaded, it will be cached locally
3. No migration script needed - cache builds organically

---

## Troubleshooting

### Media not showing as downloaded after sending
**Cause:** Upload service not saving locally first
**Fix:** Use `SmartMediaUploadService.prepareMediaForSending()`

### Downloaded media shows download button after app restart
**Cause:** Not running initialization check on load
**Fix:** Call `MessageInitializationService.initializeMediaMessages()` after loading from Firestore

### Media opens but doesn't stay cached
**Cause:** Not using proper file path generation
**Fix:** Use `MediaCacheService.getLocalFilePath()` consistently

---

## Support

For issues or questions, check:
1. Console logs (debug prints included in services)
2. File system permissions
3. Storage availability

---

## Summary

**Key Points:**
1. Always check local cache first (`MessageInitializationService`)
2. Save locally before uploading (`SmartMediaUploadService`)
3. Use `UniversalMediaWidget` for all media display
4. Never store `localPath` in Firestore
5. Re-check cache on app resume/login

**Benefits:**
- No unnecessary downloads
- Instant media access after sending
- Bandwidth savings
- Works offline for cached media
- Consistent behavior across all chat types
