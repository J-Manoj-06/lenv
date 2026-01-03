# 24-Hour Auto-Delete for Announcements

## Overview
Announcements automatically delete after 24 hours, including:
- ✅ Image files from Cloudflare R2
- ✅ Metadata from Firestore database

## Implementation

### 1. Client-Side Cleanup (Already Implemented)
The app performs automatic cleanup when teachers open the dashboard:

**File**: `lib/screens/teacher/teacher_dashboard.dart`

**Methods**:
- `_cleanupExpiredHighlights()` - Deletes expired teacher announcements
- `_cleanupExpiredPrincipalAnnouncements()` - Deletes expired principal announcements

**When it runs**:
- Automatically triggers 2 seconds after dashboard loads
- Checks for announcements with `expiresAt` < current time
- Deletes image from Cloudflare R2 using extracted key
- Deletes metadata from Firestore

### 2. Announcement Expiration
When posting an announcement:
```dart
final now = DateTime.now();
final expiresAt = now.add(const Duration(hours: 24));

final data = {
  'createdAt': FieldValue.serverTimestamp(),
  'expiresAt': Timestamp.fromDate(expiresAt),  // 24 hours from now
  'imageUrl': imageUrl,  // Image stored in Cloudflare R2
  // ... other fields
};
```

**Collections**:
- `class_highlights` - Teacher announcements (24-hour TTL)
- `institute_announcements` - Principal announcements (24-hour TTL)

### 3. Image Deletion from Cloudflare R2

**Method**: `CloudflareR2Service.deleteFile(key)`

Uses AWS Signature V4 signing to delete files:
```dart
final r2Service = CloudflareR2Service(...);
await r2Service.deleteFile(key: 'class_highlights/timestamp/filename');
```

**Key Extraction**: `_extractR2KeyFromUrl(url)`
- URL: `https://files.lenv1.tech/media/{timestamp}/{filename}`
- Extracted key: `media/{timestamp}/{filename}`

### 4. Firestore Indexes
Added composite indexes for efficient TTL queries:

**File**: `firestore.indexes.json`

```json
{
  "collectionGroup": "class_highlights",
  "fields": [
    { "fieldPath": "teacherId", "order": "ASCENDING" },
    { "fieldPath": "expiresAt", "order": "ASCENDING" }
  ]
},
{
  "collectionGroup": "institute_announcements",
  "fields": [
    { "fieldPath": "instituteId", "order": "ASCENDING" },
    { "fieldPath": "expiresAt", "order": "ASCENDING" }
  ]
}
```

Run to deploy indexes:
```bash
firebase firestore:indexes --project=your-project-id
```

## Optional: Server-Side TTL with Cloud Functions

For guaranteed cleanup without relying on client-side triggers, implement a Cloud Function:

### Cloud Function (Firestore Scheduled Trigger)
```javascript
// functions/src/index.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

export const cleanupExpiredAnnouncements = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    
    // Clean class_highlights
    const highlightsSnapshot = await db.collection('class_highlights')
      .where('expiresAt', '<', now)
      .limit(100)
      .get();
    
    for (const doc of highlightsSnapshot.docs) {
      const imageUrl = doc.data().imageUrl;
      if (imageUrl) {
        // Delete from R2 (requires R2 API credentials)
        // ... implement R2 deletion
      }
      await doc.ref.delete();
    }
    
    // Clean institute_announcements
    const announcementsSnapshot = await db.collection('institute_announcements')
      .where('expiresAt', '<', now)
      .limit(100)
      .get();
    
    for (const doc of announcementsSnapshot.docs) {
      const imageUrl = doc.data().imageUrl;
      if (imageUrl) {
        // Delete from R2
        // ... implement R2 deletion
      }
      await doc.ref.delete();
    }
    
    console.log(`Cleaned up expired announcements`);
  });
```

## Testing Cleanup

### Test Manual Cleanup
1. Open teacher dashboard
2. Wait 2 seconds for cleanup to trigger
3. Check Firestore for deleted documents
4. Check Cloudflare R2 bucket for deleted images

### Test 24-Hour Expiry
1. Create a test announcement
2. Verify `expiresAt` is set to 24 hours from now
3. After 24 hours, announcement auto-deletes

## Troubleshooting

### Images Not Deleting from R2
- Check `_extractR2KeyFromUrl()` is correctly parsing the URL
- Verify Cloudflare credentials in `lib/config/cloudflare_config.dart`
- Check CloudflareR2Service has proper AWS Signature V4 signing

### Firestore Cleanup Not Running
- Dashboard must be opened for client-side cleanup to trigger
- Check console logs for cleanup status messages
- For guaranteed cleanup, deploy Cloud Function alternative

### Missing Indexes
Deploy indexes after updating `firestore.indexes.json`:
```bash
firebase deploy --only firestore:indexes
```

## Features

✅ **Automatic cleanup** - Runs every 2 seconds after dashboard loads
✅ **Image deletion** - Removes from Cloudflare R2 automatically
✅ **Metadata cleanup** - Removes from Firestore automatically
✅ **Permission checks** - Only creator can delete announcements
✅ **Error handling** - Continues even if R2 deletion fails
✅ **Batch processing** - Deletes multiple expired items efficiently

## Security

- Only authors can delete their own announcements
- Confirmation dialog prevents accidental deletion
- Firestore rules should restrict collection access
- Cloudflare R2 API uses signed URLs for security

## References

- [AWS Signature V4](https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html)
- [Cloudflare R2](https://developers.cloudflare.com/r2/)
- [Firestore TTL](https://cloud.google.com/firestore/docs/time-to-live)
