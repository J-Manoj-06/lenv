# Teacher Announcement Multi-Image - Quick Reference

## For Developers

### Model Changes
- **StatusModel**: Added `imageCaptions` field (List<Map<String, String>>)
- **Backward compatible**: Legacy `imageUrl` still supported

### UI Changes
- Multi-image picker (up to 5 images)
- Horizontal scroll preview with counter badges
- Remove individual images before posting

### Viewer Changes
- Horizontal PageView for swiping between images
- Image counter badge (e.g., "2/3")
- Legacy single image fallback

### Auto-Deletion
- Cloud Function: `deleteExpiredTeacherAnnouncements`
- Schedule: Every 1 hour
- Target: `class_highlights` collection
- Deletes: All images from R2 + Firestore metadata

## For Testing

### Create Multi-Image Announcement
1. Teacher Dashboard → My Announcement
2. Add Images → Select multiple (max 5)
3. Post Announcement
4. Verify horizontal scroll preview

### View Multi-Image Announcement
1. Tap any announcement avatar
2. Swipe horizontally for images
3. Swipe vertically for announcements
4. Check counter badge

### Deploy Cloud Function
```bash
./deploy_teacher_announcement_autodelete.sh
```

## For Monitoring

### View Logs
```bash
firebase functions:log --only deleteExpiredTeacherAnnouncements
```

### Manual Cleanup
```bash
firebase functions:shell
> deleteExpiredTeacherAnnouncementsManual()
```

## Important Notes

⚠️ **Hot Restart Required**: After model changes, do hot restart (not hot reload)
✅ **Limit**: Maximum 5 images per announcement
✅ **Auto-Delete**: Images deleted after 24 hours automatically
✅ **Backward Compatible**: Old single-image announcements still work
