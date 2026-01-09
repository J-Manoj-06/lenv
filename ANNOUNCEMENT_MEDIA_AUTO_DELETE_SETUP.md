# 24-Hour Announcement Media Auto-Deletion Setup (Cloudflare Workers)

## ✅ What's Been Implemented

### 1. **MediaMessage Model Updated**
- Added `mediaType` field: `'announcement'`, `'message'`, or `'community'`
- Determines deletion policy (ephemeral vs permanent)
- Location: `lib/models/media_message.dart`

### 2. **MediaUploadService Updated**
- Added `mediaType` parameter (defaults to `'message'`)
- Saves mediaType to Firestore metadata
- Location: `lib/services/media_upload_service.dart`

### 3. **Cloudflare Worker Created**
- **`delete-expired-media-worker`**: Scheduled to run every hour
  - Finds announcement media older than 24 hours using Firestore REST API
  - Deletes from Cloudflare R2 (file + thumbnail)
  - Soft-deletes Firestore document (sets `deletedAt`)
  
- Location: `cloudflare-worker/src/delete-expired-media.ts`

### 4. **Provider Updated**
- `media_chat_provider.dart` now uses `mediaType: 'message'` for permanent storage
- Location: `lib/providers/media_chat_provider.dart`

---

## 🚀 Deployment Steps

### Step 1: Get Firebase Credentials

You need your Firebase Web API Key and Project ID:

1. **Firebase Console** → Project Settings → General
2. Copy **Project ID** (e.g., `your-project-12345`)
3. Scroll to **Web API Key** and copy it (e.g., `AIzaSy...`)

### Step 2: Configure Cloudflare Worker Secrets

```powershell
cd d:\new_reward\cloudflare-worker

# Set Firebase credentials as Cloudflare secrets
npx wrangler secret put FIREBASE_PROJECT_ID --config wrangler-delete-media.jsonc
# Enter your Firebase Project ID when prompted

npx wrangler secret put FIREBASE_API_KEY --config wrangler-delete-media.jsonc
# Enter your Firebase Web API Key when prompted
```

### Step 3: Deploy Cloudflare Worker

```powershell
cd d:\new_reward\cloudflare-worker
npm run deploy:media-cleanup
```

This deploys the worker with:
- **Cron schedule**: Every hour (`0 * * * *`)
- **R2 access**: Connected to your `lenv-storage` bucket
- **Firestore access**: Uses REST API with your credentials

### Step 4: Verify Deployment

Check Cloudflare Dashboard:
1. Go to Cloudflare Dashboard → Workers & Pages
2. Find `delete-expired-media-worker`
3. Click **Triggers** tab → Verify cron schedule shows "Every hour"
4. Click **Settings** tab → Verify R2 bucket binding

### Step 5: Test the Worker

**Manual trigger for testing:**
```powershell
# Get your worker URL from Cloudflare Dashboard
curl -X POST https://delete-expired-media-worker.YOUR_SUBDOMAIN.workers.dev/trigger-cleanup `
  -H "Authorization: Bearer YOUR_FIREBASE_API_KEY"
```

Or test locally:
```powershell
npm run dev:media-cleanup
# Then visit http://localhost:8787/trigger-cleanup in browser
```

---

## 📝 Usage Guide

### For Announcement Uploads (24-hour auto-delete):
```dart
final media = await mediaUploadService.uploadMedia(
  file: file,
  conversationId: announcementId,
  senderId: currentUser.uid,
  senderRole: userRole,
  mediaType: 'announcement', // ← Auto-deleted after 24 hours
);
```

### For Message Uploads (permanent):
```dart
final media = await mediaUploadService.uploadMedia(
  file: file,
  conversationId: conversationId,
  senderId: currentUser.uid,
  senderRole: userRole,
  mediaType: 'message', // ← Permanent (default)
);
```

### For Community Posts (permanent):
```dart
final media = await mediaUploadService.uploadMedia(
  file: file,
  conversationId: communityId,
  senderId: currentUser.uid,
  senderRole: userRole,
  mediaType: 'community', // ← Permanent
);
```

---

## 🔍 Monitoring

### Check Worker Logs (Real-time)
```powershell
cd d:\new_reward\cloudflare-worker
npm run tail:media-cleanup
```

Expected output:
```
🗑️ [MEDIA] Starting cleanup of 24h+ announcement media...
📂 [MEDIA] Found 5 expired announcement media to delete
  🗑️  Deleted R2 file: announcement_12345.jpg
  🗑️  Deleted R2 thumbnail: thumbnail_12345.jpg
✨ [MEDIA] Cleanup completed! Deleted: 5
```

### Check Past Executions
1. Cloudflare Dashboard → Workers & Pages
2. Click on `delete-expired-media-worker`
3. Click **Logs** tab
4. View scheduled trigger logs

### Query Firestore for Deleted Media
```javascript
// In Firebase Console → Firestore
// Filter collection: media_messages
// Where: mediaType == "announcement" AND deletedAt != null
```

---

## 💰 Cost Optimization

### Cloudflare Workers Costs
- **Free Tier**: 100,000 requests/day
- **Scheduled triggers**: 24 executions/day (1 per hour)
- **Cost**: **$0/month** (well within free tier)

### R2 Storage Costs
- Before: All media stored permanently
- After: Announcement media auto-deleted after 24 hours
- **Savings**: ~50-70% reduction in R2 storage (assuming 50% of media is announcements)

### Firestore Costs
- Soft delete: Keeps audit trail with `deletedAt` timestamp
- REST API queries: ~24 read operations/day
- **Cost**: < $0.01/month

### Total Cost
- **Cloudflare Worker**: $0/month (free tier)
- **R2 Storage**: 50-70% reduction
- **Firestore**: < $0.01/month
- **Total Estimated Savings**: ~$5-10/month at scale

---

## 🛠️ Troubleshooting

### Worker Not Deleting Media

**Check 1: Verify Secrets Are Set**
```powershell
cd d:\new_reward\cloudflare-worker
npx wrangler secret list --config wrangler-delete-media.jsonc
```

Should show:
- `FIREBASE_PROJECT_ID`
- `FIREBASE_API_KEY`

**Check 2: Check Worker Logs**
```powershell
npm run tail:media-cleanup
```
Look for error messages.

**Check 3: Verify Firestore Query**
Test the Firestore REST API manually:
```powershell
$PROJECT_ID = "your-firebase-project-id"
$API_KEY = "your-firebase-api-key"
$URL = "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/media_messages"

curl "$URL?key=$API_KEY"
```

**Check 4: Manual Trigger Test**
```powershell
curl -X POST https://delete-expired-media-worker.YOUR_SUBDOMAIN.workers.dev/trigger-cleanup `
  -H "Authorization: Bearer YOUR_FIREBASE_API_KEY"
```

### R2 Delete Failing

**Error**: "Access Denied" or "NoSuchKey"
- Verify R2 bucket binding is correct in `wrangler-delete-media.jsonc`
- Check bucket name matches exactly: `lenv-storage`

**Error**: File not found (404)
- File might already be manually deleted
- Worker logs this as warning, continues normally

### Scheduled Trigger Not Running

**Check Cloudflare Dashboard**:
1. Workers & Pages → `delete-expired-media-worker`
2. Triggers tab → Verify cron schedule
3. Should show: `0 * * * *` (every hour at minute 0)

**Verify Schedule Syntax**:
```jsonc
// In wrangler-delete-media.jsonc
"triggers": {
  "crons": ["0 * * * *"]  // Runs at :00 every hour
}
```

---

## 📊 Expected Behavior

| Time | Action | Media Status |
|------|--------|--------------|
| 0h | Upload announcement media | Active, visible in app |
| 12h | — | Still active |
| 24h | — | Still active (deletion happens at 25h) |
| 25h | Cloudflare Worker runs | Deleted from R2, `deletedAt` set |
| Future | Query filters deletedAt | Hidden from app (soft-deleted) |

---

## ✅ Checklist

- [ ] Obtained Firebase Project ID and Web API Key
- [ ] Set Cloudflare secrets (`FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`)
- [ ] Deployed Cloudflare Worker
- [ ] Verified worker appears in Cloudflare Dashboard
- [ ] Verified cron schedule is active (every hour)
- [ ] Tested announcement upload with `mediaType: 'announcement'`
- [ ] Confirmed message/community uploads use `mediaType: 'message'`/`'community'`
- [ ] Monitored worker logs for first execution

---

## 📖 Additional Documentation

- **Usage guide**: `lib/services/MEDIA_TYPE_DOCUMENTATION.dart`
- **Worker code**: `cloudflare-worker/src/delete-expired-media.ts`
- **Worker config**: `cloudflare-worker/wrangler-delete-media.jsonc`
- **Model definition**: `lib/models/media_message.dart`
- **Upload service**: `lib/services/media_upload_service.dart`

---

## 🎯 Summary

✅ **Announcement media**: Auto-deleted after 24 hours by Cloudflare Worker  
✅ **Message/Community media**: Permanent storage  
✅ **Cost optimized**: Free worker execution + reduced R2 storage  
✅ **Fully automated**: Runs every hour via Cloudflare Cron Triggers  
✅ **No Firebase Cloud Functions**: Uses Firestore REST API instead

The system is now ready for deployment to Cloudflare! 🚀

---

## 📝 Usage Guide

### For Announcement Uploads (24-hour auto-delete):
