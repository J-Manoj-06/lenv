# Teacher Announcement Multi-Image with 24-Hour Auto-Deletion - Complete ✅

## Overview
Teacher announcements now support **multiple image selection (up to 5 images)** with automatic deletion after 24 hours. All images are stored in Cloudflare R2 and automatically cleaned up along with Firebase metadata.

## What Changed

### 1. StatusModel (Data Model)
**File:** `lib/models/status_model.dart`

Added support for multiple images:
```dart
final String? imageUrl; // Deprecated: use imageCaptions instead
final List<Map<String, String>>? imageCaptions; // New: [{url: '...', caption: '...'}]
```

### 2. Teacher Dashboard (UI)
**File:** `lib/screens/teacher/teacher_dashboard.dart`

#### Changes:
1. **Multi-image picker**: Uses `ImagePicker.pickMultiImage()` with fallback to single image
2. **Image preview**: Horizontal scrollable list showing all selected images with counter badges
3. **Upload logic**: Uploads all images to Cloudflare R2 and stores in `imageCaptions` array
4. **Button text**: Shows image count (e.g., "Add More (2/5)")

#### UI Features:
- Select up to 5 images at once
- Preview images in horizontal scroll with counter (1/3, 2/3, etc.)
- Remove individual images with close button
- Legacy single image support maintained

### 3. Announcement Viewer
**File:** `lib/screens/common/announcement_pageview_screen.dart`

#### Changes:
1. **Multi-image display**: Added PageView for horizontal swiping between images
2. **Image counter badge**: Shows current image position (e.g., "1/3")
3. **Legacy support**: Fallback to single `avatarUrl` for old announcements

#### Viewer Features:
- Swipe horizontally between images within an announcement
- Swipe vertically between different announcements
- Image counter badge in top-right
- Smooth transitions

### 4. Cloud Function (Auto-Deletion)
**File:** `functions/deleteExpiredTeacherAnnouncements.js`

#### Features:
- **Scheduled execution**: Runs every 1 hour
- **Multi-image deletion**: Deletes all images from `imageCaptions` array
- **Legacy image deletion**: Also deletes old `imageUrl` field
- **Batch processing**: Handles 50 announcements per run
- **Error handling**: Continues cleanup even if individual deletions fail
- **Logging**: Detailed console logs for monitoring

#### What It Does:
1. Finds expired teacher announcements (`expiresAt < now`)
2. For each announcement:
   - Deletes all images from `imageCaptions` array from Cloudflare R2
   - Deletes legacy `imageUrl` from R2 (if exists)
   - Deletes the Firestore document
3. Logs deleted count for monitoring

## Data Structure

### Teacher Announcement Schema
```javascript
{
  id: "abc123",
  teacherId: "user123",
  teacherName: "John Doe",
  instituteId: "school123",
  className: "Grade 10 - A",
  text: "Important homework reminder",
  
  // Legacy single image (deprecated but maintained for backward compatibility)
  imageUrl: "https://files.lenv1.tech/class_highlights/img1.jpg",
  
  // New multi-image support
  imageCaptions: [
    { url: "https://files.lenv1.tech/class_highlights/img1.jpg", caption: "" },
    { url: "https://files.lenv1.tech/class_highlights/img2.jpg", caption: "" },
    { url: "https://files.lenv1.tech/class_highlights/img3.jpg", caption: "" }
  ],
  
  createdAt: Timestamp, // Auto-generated server timestamp
  expiresAt: Timestamp, // createdAt + 24 hours
  
  audienceType: "school", // or "standard", "section"
  standards: ["10"], // Target grades
  sections: ["A", "B"], // Target sections
  
  viewedBy: ["user456", "user789"] // Array of user IDs who viewed
}
```

## Deployment

### Deploy Cloud Function
```bash
chmod +x deploy_teacher_announcement_autodelete.sh
./deploy_teacher_announcement_autodelete.sh
```

Or manually:
```bash
cd functions
npm install @aws-sdk/client-s3
firebase deploy --only functions:deleteExpiredTeacherAnnouncements,functions:deleteExpiredTeacherAnnouncementsManual
```

### Required Environment Variables
Create `functions/.env` with:
```env
CLOUDFLARE_R2_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
CLOUDFLARE_R2_ACCESS_KEY_ID=your_access_key_id
CLOUDFLARE_R2_SECRET_ACCESS_KEY=your_secret_access_key
CLOUDFLARE_R2_BUCKET_NAME=your_bucket_name
```

## Testing

### Test Multi-Image Creation
1. Open teacher dashboard
2. Tap "My Announcement" avatar
3. Tap "Add Images" button
4. Select multiple images (up to 5)
5. Enter text (optional)
6. Select audience (School/Standards/Sections)
7. Tap "Post Announcement"
8. Verify images appear in horizontal scroll preview

### Test Multi-Image Viewing
1. Open any teacher announcement with multiple images
2. Swipe horizontally to navigate between images
3. Check image counter badge (e.g., "2/3")
4. Swipe vertically to go to next announcement

### Test Auto-Deletion
1. Wait 24 hours after posting announcement
2. Check Cloud Function logs:
   ```bash
   firebase functions:log --only deleteExpiredTeacherAnnouncements
   ```
3. Verify announcement and images are deleted

### Manual Cleanup Test
```bash
# Call manual cleanup function
firebase functions:shell
> deleteExpiredTeacherAnnouncementsManual()
```

Or from Firebase Console:
1. Go to Functions > deleteExpiredTeacherAnnouncementsManual
2. Click "Test function"
3. Check logs for results

## Cost Impact

### Storage Savings
- **Before**: Single image per announcement, manual cleanup required
- **After**: Up to 5 images per announcement, automatic cleanup after 24 hours
- **Benefit**: No storage bloat, ephemeral content like WhatsApp status

### Firestore Savings
- Automatic document deletion prevents database bloat
- No need for manual cleanup scripts
- Consistent 24-hour lifecycle

### Bandwidth Savings
- Only stores images for 24 hours
- Automatic R2 deletion reduces storage costs
- No orphaned files

## Monitoring

### View Cloud Function Logs
```bash
# View recent logs
firebase functions:log --only deleteExpiredTeacherAnnouncements

# View specific time range
firebase functions:log --only deleteExpiredTeacherAnnouncements --limit 100
```

### Check Deletion Stats
Look for these log entries:
```
📂 [TEACHER-ANNOUNCEMENTS] Found X expired announcements
✅ Deleted announcement: abc123
🖼️  Deleted image from R2: file.jpg
📊 Deleted announcements: X
🖼️  Deleted images: Y
```

### Monitor via Firebase Console
1. Go to Firebase Console > Functions
2. Find `deleteExpiredTeacherAnnouncements`
3. Check execution history and logs
4. Monitor error rate and execution time

## Backward Compatibility

### Legacy Single Image Support
- Old announcements with only `imageUrl` still work
- Viewer falls back to `avatarUrl` if `imageCaptions` is empty
- StatusModel maintains both fields for compatibility

### Migration Path
No migration needed! New announcements automatically use `imageCaptions`, old ones continue using `imageUrl`.

## Known Limitations

1. **Image Limit**: Maximum 5 images per announcement (to prevent abuse)
2. **Image Quality**: Compressed to 85% quality to balance quality vs. file size
3. **Fallback**: If `pickMultiImage` fails, falls back to single image selection
4. **Schedule**: Auto-deletion runs every 1 hour, so actual deletion may be up to 25 hours after posting

## Troubleshooting

### Images Not Uploading
1. Check Cloudflare R2 credentials in app
2. Verify network connection
3. Check image size (should be under 10MB)

### Images Not Deleting
1. Check Cloud Function logs for errors
2. Verify R2 credentials in `functions/.env`
3. Check `expiresAt` timestamp in Firestore
4. Ensure function is deployed and scheduled

### Viewer Not Showing Multiple Images
1. Hot restart app (not hot reload) if StatusModel changed
2. Check `imageCaptions` field in Firestore document
3. Verify images are accessible (test URLs in browser)

## Next Steps

### Optional Enhancements
1. **Image Captions**: Add text captions to each image
2. **Image Reordering**: Allow drag-to-reorder before posting
3. **Image Editing**: Add filters or cropping tools
4. **Video Support**: Extend to support videos (YouTube Shorts style)
5. **Analytics**: Track view counts per image

### Performance Optimization
1. **Lazy Loading**: Only load visible images in PageView
2. **Thumbnail Generation**: Generate thumbnails for faster loading
3. **Progressive Loading**: Show low-quality placeholder first

## Summary

✅ **Multi-image selection** (up to 5 images)
✅ **Horizontal swipe** to view multiple images
✅ **24-hour auto-deletion** from Cloudflare R2
✅ **Metadata cleanup** from Firebase
✅ **Backward compatible** with legacy single images
✅ **Deployed Cloud Function** for automatic cleanup
✅ **Monitoring and logging** for operations visibility

**Status**: Ready for testing! 🚀
