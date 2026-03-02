# Auto-Download Prevention - Integration for Other Chats

This guide shows how to apply the same system to **other chat types** (Group Chat, Community Chat, etc).

## Overview

The system is already integrated in:
- ✅ Staff Room Chat (`staff_room_chat_page.dart`)
- ✅ Multi-Image Message Bubble (`multi_image_message_bubble.dart`)
- ✅ Media Preview Card (`media_preview_card.dart`)

To apply to other chats:
1. Copy the pattern from `multi_image_message_bubble.dart`
2. Import `MediaAvailabilityService`
3. Add cache checking in image loading widgets

---

## Step-by-Step Integration Guide

### Step 1: Import the Service
```dart
import '../services/media_availability_service.dart';

class _YourChatState extends State<YourChatPage> {
  final MediaAvailabilityService _availabilityService = 
      MediaAvailabilityService();
  
  // ... rest of your state
}
```

### Step 2: Create Image Widget with Cache Checking
```dart
class CachedImageTile extends StatefulWidget {
  final String imageUrl;
  final VoidCallback onTap;
  
  const CachedImageTile({
    required this.imageUrl,
    required this.onTap,
  });
  
  @override
  State<CachedImageTile> createState() => _CachedImageTileState();
}

class _CachedImageTileState extends State<CachedImageTile> {
  bool _isCached = false;
  String? _cachedPath;
  final MediaAvailabilityService _availabilityService = 
      MediaAvailabilityService();

  @override
  void initState() {
    super.initState();
    _checkCacheStatus();
  }

  Future<void> _checkCacheStatus() async {
    try {
      // Extract r2Key from URL
      String r2Key = widget.imageUrl;
      if (r2Key.startsWith('http')) {
        final uri = Uri.parse(r2Key);
        r2Key = uri.path.replaceFirst('/', '');
      }

      // Check if cached
      final availability = 
          await _availabilityService.checkMediaAvailability(r2Key);

      if (mounted) {
        setState(() {
          _isCached = availability.isCached;
        });

        if (_isCached) {
          final path = 
              await _availabilityService.getCachedFilePath(r2Key);
          if (mounted && path != null) {
            setState(() {
              _cachedPath = path;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Cache check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // If cached locally, show from file
    if (_isCached && _cachedPath != null) {
      final file = File(_cachedPath!);
      if (file.existsSync()) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Image.file(
            file,
            fit: BoxFit.cover,
          ),
        );
      }
    }

    // Not cached - show download button
    if (!_isCached) {
      return GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_download, size: 32),
                SizedBox(height: 8),
                Text('Tap to download'),
              ],
            ),
          ),
        ),
      );
    }

    // Fallback: loading placeholder
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
```

### Step 3: Use in Your Chat Widget
```dart
class GroupChatMessageBubble extends StatelessWidget {
  final List<String> imageUrls;
  
  const GroupChatMessageBubble({
    required this.imageUrls,
  });
  
  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: imageUrls.map((url) {
        return CachedImageTile(
          imageUrl: url,
          onTap: () {
            // Handle download / view
            debugPrint('Tapped: $url');
          },
        );
      }).toList(),
    );
  }
}
```

---

## Integration Checklist for Each Chat Type

### For `group_chat_page.dart`
- [ ] Import `MediaAvailabilityService`
- [ ] Find image/media loading widget
- [ ] Add cache check in `initState()`
- [ ] Update `build()` to check `_isCached`
- [ ] Show local file or download button
- [ ] Test: Fresh install shows download buttons
- [ ] Test: Downloaded images persist after restart

### For `community_chat_page.dart`
- [ ] Same steps as above
- [ ] Check if using `MultiImageMessageBubble` (already integrated!)
- [ ] If custom widget, apply pattern

### For `chat_screen.dart` (Parent/Teacher Chat)
- [ ] Import service
- [ ] Add cache checking to image widget
- [ ] Verify with tests

### For `parent_section_group_chat_screen.dart`
- [ ] Import service
- [ ] Find image loading code
- [ ] Add cache checking
- [ ] Test

---

## Common Patterns

### Pattern 1: Single Image in Message
```dart
// In message builder
if (message.hasImage) {
  return CachedImageTile(
    imageUrl: message.imageUrl,
    onTap: () => _viewImage(message.imageUrl),
  );
}
```

### Pattern 2: Multiple Images
```dart
// In message builder
if (message.hasMultipleImages) {
  return MultiImageMessageBubble(
    imageUrls: message.imageUrls,
    onImageTap: (index) => _viewImage(message.imageUrls[index]),
  );
}
```

### Pattern 3: Image with Thumbnail
```dart
// Show thumbnail OR placeholder based on cache
if (message.hasThumbnail) {
  // Check if thumbnail cached
  return CachedThumbnailWidget(
    thumbnailUrl: message.thumbnailUrl,
    onTap: _downloadFull,
  );
}
```

---

## Testing Each Integration

### Test Template
```dart
// In your chat page test
testWidgets('Images dont auto-download on fresh install', (WidgetTester tester) async {
  // 1. Mock fresh install (empty cache)
  // 2. Load chat with images
  // 3. VERIFY: Images show "Download" button
  // 4. VERIFY: No network requests made
  // 5. VERIFY: No loading spinners
});

testWidgets('Cached images load instantly', (WidgetTester tester) async {
  // 1. Pre-populate cache with image
  // 2. Load chat
  // 3. VERIFY: Image appears immediately
  // 4. VERIFY: No re-download
});
```

---

## Migration Order

**Priority 1 (Most Used):**
1. ✅ Staff Room Chat (DONE)
2. Group Chat (`group_chat_page.dart`)
3. Community Chat (`community_chat_page.dart`)

**Priority 2 (Secondary):**
4. Teacher-Parent Chat (`chat_screen.dart`)
5. Parent Group Chat (`parent_section_group_chat_screen.dart`)

**Priority 3 (Announcements):**
6. Announcement PageView (`announcement_pageview_screen.dart`)

---

## Troubleshooting

### Issue: Images still auto-downloading
**Solution:** Check if using `CachedNetworkImage` directly
- ❌ `CachedNetworkImage(imageUrl: url)` ← Auto-downloads!
- ✅ Check cache first, then decide what to load ← Correct!

### Issue: Cache not persisting
**Solution:** Ensure `MediaStorageHelper` is initialized
- Call in `main()`: `await MediaStorageHelper().initialize()`

### Issue: Download button always shows
**Solution:** Cache check failing
- Check logs for: `Error checking media availability:`
- Verify r2Key extraction from URL is correct

---

## Verification Commands

### Check cache statistics
```dart
final stats = await MediaStorageHelper().getCacheStatistics();
print('Total cached files: ${stats.totalFiles}');
print('Total size: ${stats.formattedTotalSize}');
```

### Clear all cache (for testing)
```dart
await MediaStorageHelper().clearAllMediaCache();
```

### Check specific file
```dart
final path = await MediaAvailabilityService()
    .getCachedFilePath('media/image123');
print('Cached at: $path');
```

---

## Key Differences from CachedNetworkImage

| Aspect | CachedNetworkImage | Our System |
|--------|-------------------|-----------|
| Auto-Download | ✗ YES (automatic) | ✓ NO (manual) |
| Initial Check | Network-first | Cache-first |
| User Control | No (automatic) | Yes (explicit) |
| Bandwidth | More (unwanted) | Less (user-selected) |
| Performance | Fast (if cached) | Instant (if cached) |

---

## Production Checklist

Before deploying to production:

- [ ] All chats integrated
- [ ] Tests pass (fresh install, download, persist)
- [ ] No auto-downloads in logs
- [ ] Cache works across logins
- [ ] Cache works across reinstalls
- [ ] Corrupted cache handled gracefully
- [ ] Error messages clear and helpful
- [ ] Bandwidth measurement shows improvement
- [ ] User feedback positive (if beta tested)

---

## Support

**Questions?** Refer to:
1. [Main Implementation Guide](AUTO_DOWNLOAD_PREVENTION_COMPLETE.md)
2. [Quick Start Guide](AUTO_DOWNLOAD_PREVENTION_QUICK_START.md)
3. Service Code: `lib/services/media_availability_service.dart`
4. Example Widget: `lib/widgets/multi_image_message_bubble.dart` (lines 430-540)

---

## Summary

The system is **ready to deploy**. Apply to other chats following the patterns shown above. All chats will then:
- ✅ Respect user choice (no auto-download)
- ✅ Save bandwidth significantly
- ✅ Work consistently across the app
