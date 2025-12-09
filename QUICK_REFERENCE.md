# Media Messaging - Quick Reference Guide

## 🚀 Quick Integration (30 minutes)

### Step 1: Prepare
```bash
flutter pub get
```

### Step 2: Configure
```dart
// lib/config/cloudflare_config.dart
class CloudflareConfig {
  static const String accountId = 'YOUR_ACCOUNT_ID';
  static const String bucketName = 'app-media';
  static const String accessKeyId = 'YOUR_API_KEY';
  static const String secretAccessKey = 'YOUR_SECRET';
  static const String r2Domain = 'cdn.yourdomain.com';
}
```

### Step 3: Initialize
```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await LocalCacheService().initialize();  // ← Add this
  runApp(MyApp());
}
```

### Step 4: Add Provider
```dart
// chat_screen.dart
class ChatScreen extends StatefulWidget {
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late MediaChatProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = MediaChatProvider(conversationId: widget.conversationId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<dynamic>>(
        stream: _provider.getUnifiedMessagesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Loading();
          return MessageList(messages: snapshot.data ?? []);
        },
      ),
      bottomNavigationBar: Row(
        children: [
          IconButton(
            icon: Icon(Icons.photo),
            onPressed: () => _provider.pickAndUploadImage(),
          ),
          IconButton(
            icon: Icon(Icons.camera_alt),
            onPressed: () => _provider.captureAndUploadImage(),
          ),
        ],
      ),
    );
  }
}
```

### Step 5: Display Messages
```dart
// Build media in list
if (message is MediaMessage) {
  return MediaChatBubble(
    media: message,
    isOwn: isOwner,
    onTap: () => showPreview(message),
  );
}
```

---

## 📦 Core APIs

### Upload Image
```dart
await provider.pickAndUploadImage();
```

### Upload from Camera
```dart
await provider.captureAndUploadImage();
```

### Upload PDF
```dart
await provider.pickAndUploadPdf();
```

### Stream Messages
```dart
provider.getUnifiedMessagesStream()
  .listen((messages) {
    // Update UI
  });
```

### Load More (Pagination)
```dart
await provider.loadMoreMedia();
```

### Mark as Read
```dart
await provider.markMediaAsRead(media);
```

### Delete Media
```dart
await provider.deleteMedia(media);
```

### Download Media
```dart
await provider.downloadMedia(media);
```

---

## 🎨 UI Components

### Media Chat Bubble
```dart
MediaChatBubble(
  media: media,
  isOwn: true,
  onTap: () => preview(media),
  onLongPress: () => showOptions(media),
  onDownload: () => download(media),
)
```

### Image Preview
```dart
MediaImagePreview(
  media: media,
  maxWidth: 300,
  onTap: () => fullScreen(media),
)
```

### PDF Preview
```dart
MediaPdfPreview(
  media: media,
  maxWidth: 280,
  onTap: () => openPdf(media),
  onDownload: () => download(media),
)
```

### Upload Progress
```dart
MediaUploadProgress(
  fileName: 'photo.jpg',
  progress: 45,
  onCancel: () => cancelUpload(),
)
```

---

## 🔄 Lifecycle

### On Login
```dart
Future<void> login() async {
  await Firebase Auth...
  
  // Save session
  await LocalCacheService().saveUserSession(
    userId: user.uid,
    userRole: 'teacher',
    schoolCode: schoolCode,
  );
  
  // Load messages
  await provider.refreshMedia();
}
```

### On Logout
```dart
Future<void> logout() async {
  // Clear cache
  await LocalCacheService().clearUserData();
  
  // Sign out
  await FirebaseAuth.instance.signOut();
  
  // Navigate
  navigation.goToLogin();
}
```

---

## 📊 Monitoring

### Check Upload Progress
```dart
provider.uploadProgress.forEach((mediaId, progress) {
  print('$mediaId: $progress%');
});
```

### Check Errors
```dart
if (provider.currentError != null) {
  showError(provider.currentError!);
  provider.clearError();
}
```

### Cache Statistics
```dart
final stats = await provider.getCacheStats();
print('Cached messages: ${stats['messages']}');
print('Cached media: ${stats['media']}');
print('Has session: ${stats['hasUserSession']}');
```

---

## 🔐 Security Checklist

Before deployment:

- [ ] Update CloudflareConfig with real credentials
- [ ] Use secure storage for credentials (flutter_secure_storage)
- [ ] Update Firestore security rules
- [ ] Test rules with different user roles
- [ ] Verify R2 bucket permissions
- [ ] Setup custom domain for R2 (optional but recommended)
- [ ] Enable CORS if needed
- [ ] Setup API token expiry/rotation policy

---

## 🐛 Debugging

### Enable Logging
```dart
// In services
print('✅ Upload started');
print('❌ Error occurred: $e');
print('📊 Progress: $progress%');
```

### Test Image Compression
```dart
final originalSize = file.lengthSync();
final compressed = _compressImage(bytes);
final ratio = (compressed.length / originalSize) * 100;
print('Compression: ${100 - ratio}% reduction');
```

### Check Cache
```dart
final session = LocalCacheService().getUserSession();
print('User: ${session?['userId']}');
print('Role: ${session?['userRole']}');
```

### Verify Firestore Write
```dart
_firestore
  .collection('conversations')
  .doc(conversationId)
  .collection('media')
  .snapshots()
  .listen((snapshot) {
    print('Media count: ${snapshot.docs.length}');
  });
```

---

## 🌐 File Formats Supported

| Type | Extensions | Max Size |
|------|-----------|----------|
| Images | jpg, jpeg, png, gif | 50 MB |
| PDFs | pdf | 100 MB |

### Supported MIME Types
```dart
'image/jpeg'       // .jpg, .jpeg
'image/png'        // .png
'image/gif'        // .gif
'image/webp'       // .webp
'application/pdf'  // .pdf
```

---

## 💾 Cache Details

### What's Cached
- ✅ Message metadata
- ✅ Media metadata (URL, thumbnail, etc)
- ✅ Unread counts
- ✅ User session

### Cache Duration
- **Messages**: 1 hour (configurable)
- **Session**: Until logout
- **Media URLs**: Until deleted

### Cache Size Limit
- Default: Unlimited (Hive)
- Recommended: Monitor device storage
- Auto-cleanup: On logout

---

## ⚡ Performance Tips

### Image Optimization
```dart
// Change compression settings
static const int THUMBNAIL_QUALITY = 70;    // Lower = smaller
static const int MAX_IMAGE_WIDTH = 1920;    // Lower = faster
```

### Network Optimization
```dart
// Disable progress callback if not needed
// Progress tracking adds network overhead
await uploadMedia(
  file: file,
  onProgress: null,  // Faster
);
```

### Cache Optimization
```dart
// Clear old cache periodically
if (isCacheStale(conversationId, maxAge: Duration(hours: 1))) {
  await refreshMedia();
}
```

---

## 🚀 Deployment Checklist

### Before Going Live
- [ ] Test with real Cloudflare credentials
- [ ] Test with 10+ concurrent users
- [ ] Monitor Firebase costs for 24 hours
- [ ] Monitor Cloudflare R2 bandwidth
- [ ] Test on slow network (3G)
- [ ] Test on low battery mode
- [ ] Test cache clearing on logout
- [ ] Verify error messages are user-friendly
- [ ] Check image compression quality
- [ ] Test PDF uploads (large files)
- [ ] Test pagination (100+ media items)
- [ ] Verify read receipts work
- [ ] Test delete functionality
- [ ] Monitor for memory leaks

### Monitoring
- Cloudflare Dashboard: R2 metrics
- Firebase Console: Usage tab
- Google Analytics: User behavior
- Crash logs: Device logs

---

## 📞 Quick Help

### "Upload not working"
1. Check CloudflareConfig has real credentials
2. Verify R2 bucket exists
3. Check API token permissions
4. Look at Firebase logs: `firebase functions logs`

### "Images blurry"
1. Increase THUMBNAIL_QUALITY to 85-90
2. Increase MAX_IMAGE_WIDTH to 2560
3. Use PNG for better quality (larger file)

### "Cache not updating"
1. Call `provider.refreshMedia()`
2. Check cache duration: `Duration(hours: 1)`
3. Verify Firestore has new data

### "Download not working"
1. Implement download in `downloadMedia()`
2. Check R2 URL is accessible
3. Add download permission (AndroidManifest.xml)

---

## 📚 Documentation Structure

```
MEDIA_MESSAGING_SETUP.md        ← Start here (complete guide)
MEDIA_MESSAGING_CHECKLIST.md    ← Implementation checklist
MEDIA_MESSAGING_COMPLETE.md     ← Architecture & details
QUICK_REFERENCE.md              ← This file (API reference)

Code:
lib/services/                   ← Core logic
lib/models/                     ← Data models
lib/widgets/                    ← UI components
lib/providers/                  ← State management
lib/config/                     ← Configuration
```

---

## 🎯 Example Use Cases

### Use Case 1: Share Homework PDF
```dart
// 1. Teacher picks PDF
await provider.pickAndUploadPdf();

// 2. See in chat
MediaChatBubble(media: pdf)

// 3. Student downloads
await provider.downloadMedia(pdf);
```

### Use Case 2: Share Class Photo
```dart
// 1. Teacher captures photo
await provider.captureAndUploadImage();

// 2. Compressed & cached
// Original: 15MB → Compressed: 2MB, Thumbnail: 18KB

// 3. Instant preview on all phones
MediaImagePreview(media: image)
```

### Use Case 3: Message History
```dart
// 1. Load recent media
final recent = await provider.getMediaPaginated(limit: 20);

// 2. Scroll to load more
await provider.loadMoreMedia();

// 3. Cache for offline
LocalCacheService().getCachedMessages(conversationId);
```

---

## 🎓 Key Concepts

### Signed URLs
- Generated on client
- Valid for 24 hours
- No credentials exposed
- AWS Signature V4

### Image Compression
- Resize to 1920×1080
- JPEG quality 85
- ~70% size reduction
- Lossless thumbnail

### Cost Optimization
- Files in R2 ($0.015/GB)
- Metadata in Firestore ($0.06/1M reads)
- Thumbnails cached locally
- 99% cheaper than Firebase Storage

### Cache Management
- Hive for local storage
- Auto-clear on logout
- TTL for freshness
- Offline access support

---

**Version**: 1.0.0  
**Last Updated**: December 2025  
**Status**: Complete ✅

For detailed setup, see: **MEDIA_MESSAGING_SETUP.md**
