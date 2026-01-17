# 🗑️ Institute Announcement Auto-Delete - Quick Start

## What It Does
✅ Automatically deletes institute announcements after **24 hours**  
✅ Removes all images from Cloudflare R2  
✅ Cleans up view records  
✅ Complete removal from all systems  

---

## Deployment (One-Time Setup)

### Method 1: Using Deployment Script
```bash
./deploy_institute_announcement_autodelete.sh
```

### Method 2: Manual Deployment
```bash
cd functions
npm run deploy
```

---

## How It Works

### Automatic Schedule
- Runs **every 1 hour** automatically
- No manual intervention needed
- Processes up to 50 announcements per run

### What Gets Deleted
1. All images from Cloudflare R2 (from `imageCaptions` array)
2. Legacy single image (if exists)
3. Views subcollection (all view records)
4. Main announcement document from Firestore

### Timeline
```
Announcement Created → 24 Hours Pass → Next Hourly Run → DELETED
```

---

## Monitoring

### View Logs
```bash
# Real-time monitoring
firebase functions:log --only deleteExpiredInstituteAnnouncements --follow

# Recent logs
firebase functions:log --only deleteExpiredInstituteAnnouncements
```

### Expected Log Output
```
🗑️ [INSTITUTE] Starting cleanup of 24h+ institute announcements...
📂 [INSTITUTE] Found 2 expired announcements to delete
  Processing announcement: abc123
    🗑️  Deleted image from R2
    🗑️  Deleted image from R2
    🗑️  Deleted 8 view records
  ✅ Deleted announcement: abc123
✨ [INSTITUTE] Cleanup completed!
   📊 Deleted announcements: 2
   📊 Deleted images: 4
```

---

## Testing

### Test Automatic Deletion
1. Create a test announcement
2. In Firebase Console, edit the announcement
3. Change `createdAt` timestamp to 25 hours ago
4. Wait for next hourly run (check logs)
5. Verify announcement is deleted

### Test Manual Deletion
```bash
firebase functions:call deleteExpiredInstituteAnnouncementsManual
```

---

## Verify Deployment

```bash
# List all functions
firebase functions:list

# Should show:
# - deleteExpiredInstituteAnnouncements
# - deleteExpiredInstituteAnnouncementsManual
```

---

## Troubleshooting

### Functions Not Deployed
```bash
cd functions
npm install
firebase login
firebase use --add  # Select your project
npm run deploy
```

### Environment Variables Missing
Check `functions/.env` has:
```
CLOUDFLARE_R2_ENDPOINT=https://...
CLOUDFLARE_R2_ACCESS_KEY_ID=...
CLOUDFLARE_R2_SECRET_ACCESS_KEY=...
CLOUDFLARE_R2_BUCKET_NAME=...
```

### Announcements Not Being Deleted
1. Check logs for errors
2. Verify timestamps are correct (Firestore Timestamp format)
3. Ensure function is scheduled (check Firebase Console → Functions)

---

## Files Created/Modified

### New Files
- ✅ `functions/deleteExpiredInstituteAnnouncements.js` - Cloud Function
- ✅ `deploy_institute_announcement_autodelete.sh` - Deployment script
- ✅ `INSTITUTE_ANNOUNCEMENT_AUTO_DELETE_SETUP.md` - Full documentation
- ✅ `INSTITUTE_ANNOUNCEMENT_AUTO_DELETE_QUICKSTART.md` - This file

### Updated Files
- ✅ `functions/index.js` - Added function exports
- ✅ `functions/package.json` - Updated deploy script

---

## Benefits

🕒 **24-Hour Freshness**
- Only recent announcements visible
- Automatic expiry like WhatsApp stories
- Keeps content relevant

💰 **Cost Savings**
- Reduces Firestore storage
- Reduces R2 storage
- Automatic cleanup of subcollections

🎯 **Zero Maintenance**
- Runs automatically every hour
- No manual deletion needed
- Self-maintaining system

---

## Cost Impact

### Firestore
- Reduced storage (old announcements removed)
- Writes: ~1 per announcement + views count

### Cloudflare R2
- Storage savings from deleted images
- Delete operations: FREE

### Cloud Functions
- 24 invocations/day (hourly)
- ~2-5 seconds per run
- Very low cost

---

## Next Steps After Deployment

1. ✅ Deploy functions (see above)
2. ✅ Monitor first run with logs
3. ✅ Create test announcement
4. ✅ Verify 24h deletion works
5. ✅ Announce feature to users

---

## Support

See full documentation: `INSTITUTE_ANNOUNCEMENT_AUTO_DELETE_SETUP.md`

**Status:** ✅ Implementation Complete  
**Auto-Delete:** ✅ 24 Hours  
**Cleanup:** ✅ Firestore + Cloudflare R2 + Views  
