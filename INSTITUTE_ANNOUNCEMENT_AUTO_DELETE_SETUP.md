# Institute Announcement Auto-Delete Setup (24 Hours)

## Overview
Institute announcements (posted by principals) are automatically deleted after **24 hours** from creation. This includes:
- ✅ Firestore document deletion
- ✅ All images deleted from Cloudflare R2
- ✅ Views subcollection cleanup
- ✅ Complete removal from all systems

## How It Works

### Automatic Scheduled Cleanup
The Cloud Function `deleteExpiredInstituteAnnouncements` runs **every hour** and:
1. Queries all announcements where `createdAt < 24 hours ago`
2. Deletes all images from Cloudflare R2 (both `imageCaptions` array and legacy `imageUrl`)
3. Deletes the `views` subcollection (all view records)
4. Deletes the main announcement document from Firestore
5. Logs all operations for monitoring

### Manual Cleanup Trigger
A callable function `deleteExpiredInstituteAnnouncementsManual` is also available for:
- Testing the cleanup logic
- Manual bulk deletion when needed
- Admin panel integration

## Files Modified/Created

### New Files
- **functions/deleteExpiredInstituteAnnouncements.js** - Cloud Function for auto-deletion
  - `deleteExpiredInstituteAnnouncements` - Scheduled function (hourly)
  - `deleteExpiredInstituteAnnouncementsManual` - Callable function for manual trigger

### Updated Files
- **functions/index.js** - Added exports for new functions
- **functions/package.json** - Updated deploy script to include new functions

## Deployment

### Prerequisites
Make sure environment variables are set in `.env` file:
```bash
CLOUDFLARE_R2_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
CLOUDFLARE_R2_ACCESS_KEY_ID=your_access_key
CLOUDFLARE_R2_SECRET_ACCESS_KEY=your_secret_key
CLOUDFLARE_R2_BUCKET_NAME=your_bucket_name
```

### Deploy Command
```bash
cd functions
npm run deploy
```

Or deploy all functions:
```bash
cd functions
npm run deploy-all
```

## Testing

### Test Automatic Cleanup
1. Create a test announcement in Firebase Console
2. Set `createdAt` to 25 hours ago (manually modify timestamp)
3. Wait for the next scheduled run (runs every hour)
4. Verify the announcement is deleted

### Test Manual Cleanup
Using Firebase CLI:
```bash
firebase functions:call deleteExpiredInstituteAnnouncementsManual
```

Using Firebase Console:
1. Go to Functions section
2. Find `deleteExpiredInstituteAnnouncementsManual`
3. Click "Test function"

## Monitoring

### View Logs
```bash
firebase functions:log --only deleteExpiredInstituteAnnouncements
```

### Log Output Example
```
🗑️ [INSTITUTE] Starting cleanup of 24h+ institute announcements...
📂 [INSTITUTE] Found 3 expired announcements to delete
  Processing announcement: abc123
    🗑️  Deleted image from R2
    🗑️  Deleted image from R2
    🗑️  Deleted 15 view records
  ✅ Deleted announcement: abc123
✨ [INSTITUTE] Cleanup completed!
   📊 Deleted announcements: 3
   📊 Deleted images: 6
```

## Data Structure

### Institute Announcement Schema
```javascript
{
  id: "abc123",
  principalId: "user123",
  principalName: "John Doe",
  instituteId: "school123",
  text: "Important announcement",
  imageCaptions: [
    { url: "https://files.lenv1.tech/announcements/img1.jpg", caption: "First image" },
    { url: "https://files.lenv1.tech/announcements/img2.jpg", caption: "Second image" }
  ],
  createdAt: Timestamp, // Used to determine expiry
  expiresAt: Timestamp, // Set to createdAt + 24 hours
  audienceType: "school", // or "standard"
  standards: ["6", "7", "8"],
  
  // Subcollection: views/{userId}
  // Contains view records for each user who viewed the announcement
}
```

## Cleanup Process Flow

```
1. Scheduled Trigger (Every Hour)
   ↓
2. Query: createdAt < (now - 24 hours)
   ↓
3. For each announcement:
   ├── Delete all images from R2 (imageCaptions)
   ├── Delete legacy image (imageUrl)
   ├── Delete views subcollection
   └── Delete main document
   ↓
4. Log results
   └── Return: { deletedCount, imagesDeleted }
```

## Benefits

### 1. **Fresh Content**
- Only shows announcements from the last 24 hours
- Keeps information relevant and timely
- Users don't see outdated announcements

### 2. **Automatic Cleanup**
- No manual intervention required
- Runs reliably every hour
- Self-maintaining system

### 3. **Cost Optimization**
- Reduces Firestore storage costs
- Reduces Cloudflare R2 storage costs
- Cleans up subcollections (views)

### 4. **WhatsApp-Style UX**
- Mimics story/status behavior (24h expiry)
- Familiar user experience
- Encourages timely viewing

## Cost Considerations

### Firestore
- **Deletes**: ~1 write operation per announcement
- **View Cleanup**: ~1 write per view record
- **Batch Size**: 50 announcements per run (rate limiting)

### Cloud Functions
- **Invocations**: 24 times per day (hourly schedule)
- **Duration**: ~2-5 seconds per run (depends on batch size)
- **Memory**: 256MB allocated

### Cloudflare R2
- **Storage**: Reduced by deleting old images
- **Delete Operations**: Free (no charge for DELETE operations)

## Troubleshooting

### Announcements Not Being Deleted

**Check logs:**
```bash
firebase functions:log --only deleteExpiredInstituteAnnouncements
```

**Common issues:**
1. Function not deployed
   - Run: `cd functions && npm run deploy`
2. Environment variables missing
   - Check `.env` file has R2 credentials
3. Timestamp format incorrect
   - Verify `createdAt` is a proper Firestore Timestamp

### Images Not Being Deleted from R2

**Check:**
1. R2 credentials are correct in `.env`
2. Bucket name matches
3. URL format is correct: `https://files.lenv1.tech/announcements/filename.jpg`

**Manual verification:**
```bash
# List R2 objects to see if they exist
# Use Cloudflare R2 dashboard or CLI
```

### Manual Cleanup Not Working

**Verify:**
1. Function is deployed: `firebase functions:list`
2. Call syntax is correct: `firebase functions:call deleteExpiredInstituteAnnouncementsManual`
3. Check function logs for errors

## Security Notes

- The scheduled function runs with admin privileges (no auth required)
- The manual callable function can optionally be restricted to admin users
- Soft-delete can be implemented if audit trail is needed (change from `delete()` to `update({ deletedAt: ... })`)

## Future Enhancements

### Optional Features
1. **Configurable expiry time** (instead of fixed 24h)
2. **Grace period** before deletion
3. **Archive instead of delete** (move to archive collection)
4. **Email notification** before deletion
5. **Bulk restore** functionality (if using soft delete)

### Admin Control
```dart
// In compose screen, allow principal to set custom expiry
final expiresAt = DateTime.now().add(Duration(hours: customHours));
```

## Implementation Complete ✅

- [x] Cloud Function created
- [x] Scheduled trigger configured (hourly)
- [x] R2 image deletion implemented
- [x] Firestore cleanup implemented
- [x] Views subcollection cleanup
- [x] Manual trigger function added
- [x] Logging and monitoring
- [x] Error handling
- [x] Documentation

## Next Steps

1. **Deploy the functions:**
   ```bash
   cd functions
   npm run deploy
   ```

2. **Verify deployment:**
   ```bash
   firebase functions:list | grep deleteExpiredInstitute
   ```

3. **Monitor first run:**
   ```bash
   firebase functions:log --only deleteExpiredInstituteAnnouncements --follow
   ```

4. **Test with old announcement:**
   - Create announcement
   - Manually set createdAt to 25h ago in Firebase Console
   - Wait for next hourly run
   - Verify deletion

---

**Status:** ✅ Ready for deployment
**Auto-Delete:** ✅ Enabled (24 hours)
**Cleanup Scope:** ✅ Complete (Firestore + R2 + Views)
