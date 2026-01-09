# 🚀 Cloudflare Worker Deployment Guide - 24hr Media Deletion

## Overview

This guide covers deploying a **Cloudflare Worker** that automatically deletes announcement media after 24 hours. Unlike Firebase Cloud Functions, this runs on Cloudflare's edge network with:

- ✅ **Free tier**: 100,000 requests/day (more than enough for hourly cron)
- ✅ **Zero cold starts**: Always responsive
- ✅ **Direct R2 access**: No external API calls for storage
- ✅ **Firestore REST API**: Simple HTTP queries to Firebase

---

## 📋 Prerequisites

1. **Cloudflare account** with Workers enabled
2. **R2 bucket** already created (`lenv-storage`)
3. **Firebase project** with Firestore enabled
4. **Wrangler CLI** installed (comes with npm dependencies)

---

## 🔑 Step 1: Get Firebase Credentials

### 1.1 Get Project ID
1. Open [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Click **⚙️ Settings** → **Project Settings**
4. Copy **Project ID** (e.g., `your-project-12345`)

### 1.2 Get Web API Key
1. Same page, scroll to **Web API Key**
2. Copy the key (starts with `AIzaSy...`)

**Note**: This is your public Web API Key, safe to use in Workers for read/write operations with Firestore security rules.

---

## ⚙️ Step 2: Configure Cloudflare Worker

### 2.1 Review Configuration

The worker config is in `cloudflare-worker/wrangler-delete-media.jsonc`:

```jsonc
{
  "name": "delete-expired-media-worker",
  "main": "src/delete-expired-media.ts",
  "compatibility_date": "2024-12-10",
  
  "r2_buckets": [
    {
      "binding": "R2_BUCKET",
      "bucket_name": "lenv-storage",
      "preview_bucket_name": "lenv-storage"
    }
  ],
  
  "triggers": {
    "crons": ["0 * * * *"]  // Every hour at minute 0
  }
}
```

**Cron Schedule Options**:
- `0 * * * *` - Every hour (recommended)
- `0 */2 * * *` - Every 2 hours
- `0 */6 * * *` - Every 6 hours
- `0 0 * * *` - Once per day at midnight

### 2.2 Set Secrets

Secrets are encrypted environment variables:

```powershell
cd d:\new_reward\cloudflare-worker

# Set Firebase Project ID
npx wrangler secret put FIREBASE_PROJECT_ID --config wrangler-delete-media.jsonc
# When prompted, enter: your-firebase-project-id

# Set Firebase API Key
npx wrangler secret put FIREBASE_API_KEY --config wrangler-delete-media.jsonc
# When prompted, enter: AIzaSy...
```

**Verify secrets are set**:
```powershell
npx wrangler secret list --config wrangler-delete-media.jsonc
```

Should show:
```
FIREBASE_PROJECT_ID
FIREBASE_API_KEY
```

---

## 🚀 Step 3: Deploy Worker

### 3.1 Deploy to Cloudflare

```powershell
cd d:\new_reward\cloudflare-worker
npm run deploy:media-cleanup
```

**Expected output**:
```
✨ Built successfully in 1.2s
✨ Uploaded delete-expired-media-worker (XX KB)
✨ Published delete-expired-media-worker
   https://delete-expired-media-worker.YOUR_SUBDOMAIN.workers.dev
✨ Scheduled on 0 * * * *
```

### 3.2 Verify Deployment

1. Open [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to **Workers & Pages**
3. Find `delete-expired-media-worker`
4. Click on it to view details

**Check Triggers**:
- Click **Triggers** tab
- Verify cron schedule: `0 * * * *`

**Check Bindings**:
- Click **Settings** tab → **Bindings**
- Verify R2 bucket: `lenv-storage`

**Check Environment Variables**:
- Click **Settings** tab → **Variables and Secrets**
- Verify `FIREBASE_PROJECT_ID` and `FIREBASE_API_KEY` exist (values hidden)

---

## 🧪 Step 4: Test the Worker

### 4.1 Manual Trigger Test

Get your worker URL from Cloudflare Dashboard, then:

```powershell
# Replace with your actual values
$WORKER_URL = "https://delete-expired-media-worker.YOUR_SUBDOMAIN.workers.dev"
$API_KEY = "AIzaSy..."  # Your Firebase API Key

curl -X POST "$WORKER_URL/trigger-cleanup" `
  -H "Authorization: Bearer $API_KEY" `
  -H "Content-Type: application/json"
```

**Expected response**:
```json
{
  "success": true,
  "deletedCount": 0,
  "timestamp": "2024-12-11T10:30:00.000Z"
}
```

### 4.2 Test Locally

```powershell
cd d:\new_reward\cloudflare-worker
npm run dev:media-cleanup
```

Then open browser to `http://localhost:8787/trigger-cleanup`

---

## 📊 Step 5: Monitor Worker

### 5.1 Real-time Logs (Tail)

```powershell
cd d:\new_reward\cloudflare-worker
npm run tail:media-cleanup
```

**Expected logs**:
```
🗑️ [MEDIA] Starting cleanup of 24h+ announcement media...
📂 [MEDIA] Found 3 expired announcement media to delete
  🗑️  Deleted R2 file: announcement_12345.jpg
  🗑️  Deleted R2 thumbnail: thumbnail_12345.jpg
✨ [MEDIA] Cleanup completed! Deleted: 3
```

### 5.2 View Past Logs

1. Cloudflare Dashboard → Workers & Pages
2. Click `delete-expired-media-worker`
3. Click **Logs** tab
4. View scheduled cron trigger logs

### 5.3 Check Analytics

1. Same page, click **Metrics** tab
2. View:
   - Requests per day
   - Execution time
   - Success rate

---

## 🔧 Step 6: Configure Firestore Security Rules

Ensure your Firestore security rules allow the worker to:
1. Read `media_messages` collection
2. Update documents (set `deletedAt`)

**Add to `firestore.rules`**:
```javascript
match /media_messages/{messageId} {
  // Allow read/write with valid API key
  allow read, write: if request.auth != null;
  
  // Or use custom claims for worker access
  allow update: if request.auth != null 
    && request.resource.data.keys().hasOnly(['deletedAt']);
}
```

**Deploy rules**:
```powershell
firebase deploy --only firestore:rules
```

---

## 💰 Cost Analysis

### Cloudflare Workers Free Tier
- **100,000 requests/day**
- Scheduled crons: 24/day (1 per hour)
- Manual triggers: Minimal
- **Monthly usage**: ~720 requests
- **Cost**: **$0.00** (well within free tier)

### R2 Operations
- **Class A operations** (delete): 1 million free/month
- Deletes per hour: ~10-50 files
- Monthly deletes: ~7,200-36,000
- **Cost**: **$0.00** (within free tier)

### Firestore REST API
- **Read operations**: ~24/day = 720/month
- **Write operations**: ~10-50/day = 300-1,500/month
- **Cost**: ~$0.01/month

### Total Cost
**$0.00 - $0.01/month** 🎉

---

## 🛠️ Troubleshooting

### Issue: Worker not executing on schedule

**Solution 1: Verify cron syntax**
```jsonc
// In wrangler-delete-media.jsonc
"triggers": {
  "crons": ["0 * * * *"]  // Must be array of strings
}
```

**Solution 2: Check Cloudflare Dashboard**
- Workers & Pages → delete-expired-media-worker → Triggers
- Verify cron schedule is active

**Solution 3: Redeploy**
```powershell
npm run deploy:media-cleanup
```

---

### Issue: "Unauthorized" error in logs

**Solution 1: Check Firestore security rules**
- Ensure API key can access `media_messages` collection
- Test in Firebase Console

**Solution 2: Verify API key is correct**
```powershell
npx wrangler secret list --config wrangler-delete-media.jsonc
# Should show FIREBASE_API_KEY

# Re-set if needed
npx wrangler secret put FIREBASE_API_KEY --config wrangler-delete-media.jsonc
```

---

### Issue: "R2 bucket not found" error

**Solution 1: Verify bucket name**
- Check Cloudflare Dashboard → R2
- Bucket should be named exactly `lenv-storage`

**Solution 2: Update wrangler config**
```jsonc
"r2_buckets": [
  {
    "binding": "R2_BUCKET",
    "bucket_name": "lenv-storage",  // ← Match your actual bucket
    "preview_bucket_name": "lenv-storage"
  }
]
```

**Solution 3: Redeploy**
```powershell
npm run deploy:media-cleanup
```

---

### Issue: Media not being deleted

**Check 1: Verify media exists in Firestore**
```javascript
// Firebase Console → Firestore
// Query: media_messages
// Where: mediaType == "announcement" AND createdAt < 24 hours ago
```

**Check 2: Check worker logs**
```powershell
npm run tail:media-cleanup
```

**Check 3: Manual trigger**
```powershell
curl -X POST https://delete-expired-media-worker.YOUR_SUBDOMAIN.workers.dev/trigger-cleanup `
  -H "Authorization: Bearer YOUR_FIREBASE_API_KEY"
```

---

## 📝 Maintenance

### Update Worker Code

1. Edit `cloudflare-worker/src/delete-expired-media.ts`
2. Deploy changes:
```powershell
npm run deploy:media-cleanup
```

### Change Schedule

1. Edit `cloudflare-worker/wrangler-delete-media.jsonc`:
```jsonc
"triggers": {
  "crons": ["0 */2 * * *"]  // Every 2 hours
}
```
2. Redeploy

### View All Secrets

```powershell
npx wrangler secret list --config wrangler-delete-media.jsonc
```

### Delete Secret

```powershell
npx wrangler secret delete FIREBASE_API_KEY --config wrangler-delete-media.jsonc
```

---

## ✅ Deployment Checklist

- [ ] Obtained Firebase Project ID
- [ ] Obtained Firebase Web API Key
- [ ] Set Cloudflare secrets (PROJECT_ID, API_KEY)
- [ ] Reviewed cron schedule in wrangler config
- [ ] Deployed worker to Cloudflare
- [ ] Verified worker in Cloudflare Dashboard
- [ ] Verified cron trigger is active
- [ ] Verified R2 bucket binding
- [ ] Tested manual trigger
- [ ] Monitored logs for first execution
- [ ] Updated Firestore security rules (if needed)
- [ ] Tested announcement upload with `mediaType: 'announcement'`

---

## 🎯 Summary

✅ **Deployed to**: Cloudflare Workers (not Firebase)  
✅ **Schedule**: Runs every hour via cron trigger  
✅ **Cost**: $0/month (free tier)  
✅ **Firestore**: Uses REST API (no Firebase Admin SDK needed)  
✅ **R2 Access**: Direct binding (no external API)  
✅ **Monitoring**: Real-time logs via `wrangler tail`  

**Your worker is now live and will automatically delete announcement media after 24 hours!** 🚀

---

## 📚 Related Files

| File | Purpose |
|------|---------|
| `cloudflare-worker/src/delete-expired-media.ts` | Worker source code |
| `cloudflare-worker/wrangler-delete-media.jsonc` | Worker configuration |
| `cloudflare-worker/package.json` | NPM scripts for deploy/dev |
| `lib/models/media_message.dart` | MediaMessage model with mediaType |
| `lib/services/media_upload_service.dart` | Upload service |

---

## 🆘 Support

**Cloudflare Workers Docs**: https://developers.cloudflare.com/workers/  
**Firestore REST API**: https://firebase.google.com/docs/firestore/use-rest-api  
**Cron Triggers**: https://developers.cloudflare.com/workers/configuration/cron-triggers/  
**Wrangler CLI**: https://developers.cloudflare.com/workers/wrangler/
