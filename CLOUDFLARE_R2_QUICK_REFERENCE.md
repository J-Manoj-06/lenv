# ⚡ Quick Reference: All Media Uploads Now Use Cloudflare R2

## 🎯 What Changed?

**Firebase Storage** → **Cloudflare R2** for all media uploads across the app.

---

## 📦 Updated Features

| Feature | File | Upload Path |
|---------|------|-------------|
| 📣 Announcements (Admin) | `institute_announcement_compose_screen.dart` | `announcements/` |
| 🎓 Classroom Highlights (Teacher) | `teacher_dashboard.dart` | `class_highlights/` |
| 💬 Group Messages | `community_chat_page.dart` | `community_messages/` |
| 👤 Profile Images | `storage_service.dart` | `profiles/` |
| 🎁 Reward Images | `storage_service.dart` | `rewards/` |
| 📎 Test Attachments | `storage_service.dart` | `tests/` |

---

## 🔐 R2 Service Configuration

**File**: `lib/services/cloudflare_r2_service.dart` (already exists)

**Credentials** (hardcoded in code):
- Bucket: `lenv-media`
- Domain: `https://files.lenv1.tech`
- Account ID: `8e3e4c3c27f74e76e85a75e51e8ac0c5`

---

## 📝 How to Upload (Standard Pattern)

```dart
import '../../services/cloudflare_r2_service.dart';

// 1. Initialize service
final r2Service = CloudflareR2Service(
  accountId: '8e3e4c3c27f74e76e85a75e51e8ac0c5',
  bucketName: 'lenv-media',
  accessKeyId: 'ae58fa3c9d19493c8e3dd83bbdd7a32b',
  secretAccessKey: 'f4f39d5aef9b3e80b5db6e3fd1e6b5e3c8d5f7a2b4c6e8f0a1b3c5d7e9f0a1b3',
  r2Domain: 'https://files.lenv1.tech',
);

// 2. Read file as bytes
final fileBytes = await File(image.path).readAsBytes();

// 3. Upload
final imageUrl = await r2Service.uploadMedia(
  fileBytes: fileBytes,
  fileName: 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
  folderPath: 'announcements',  // Change as needed
  contentType: 'image/jpeg',
);

// 4. Use URL
print('Uploaded to: $imageUrl');
```

---

## ✅ Recent Changes

### Removed (Firebase Storage)
```dart
import 'package:firebase_storage/firebase_storage.dart';

final ref = FirebaseStorage.instance.ref()...
await ref.putFile(...)
final url = await ref.getDownloadURL()
```

### Added (Cloudflare R2)
```dart
import '../../services/cloudflare_r2_service.dart';

final url = await r2Service.uploadMedia(...)
```

---

## 🧪 Test Upload

**Go to**: Settings → Storage Debug  
**Click**: Test Storage  
**Should see**: ✅ ALL TESTS PASSED

---

## 🚀 Files Modified

1. ✅ `institute_announcement_compose_screen.dart` - Announcements
2. ✅ `teacher_dashboard.dart` - Class highlights  
3. ✅ `community_chat_page.dart` - Group messages
4. ✅ `storage_service.dart` - Central storage service
5. ✅ `storage_debug_screen.dart` - Diagnostics
6. ✅ `FIX_STUDENT_MESSAGE_IMAGE_UPLOAD.md` - Documentation

---

## 📊 Benefits

- ✅ Works immediately (no Firebase Storage API setup needed)
- ✅ 60% cheaper than Firebase Storage
- ✅ CDN-accelerated via Cloudflare
- ✅ S3-compatible (industry standard)
- ✅ Simpler integration

---

## ⚠️ If Upload Fails

1. Check R2 credentials in code
2. Run storage diagnostics (Settings → Storage Debug)
3. Verify `https://files.lenv1.tech` is accessible
4. Check Cloudflare R2 dashboard for bucket status

---

## 🔗 File URLs

All uploaded files are accessible at:
```
https://files.lenv1.tech/{folderPath}/{fileName}
```

Example:
```
https://files.lenv1.tech/announcements/image_1234567890.jpg
https://files.lenv1.tech/class_highlights/image_9876543210.jpg
https://files.lenv1.tech/profiles/user123.jpg
```

---

**Last Updated**: 2025-01-15  
**Status**: ✅ All uploads migrated to Cloudflare R2
