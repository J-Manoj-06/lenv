# Institute Announcement Auto-Delete - Cloudflare Worker

## ✅ Complete Implementation (FREE)

This Cloudflare Worker automatically deletes institute announcements after **24 hours**, including all images from R2 and Firestore data.

---

## 🚀 Quick Deploy

```bash
cd cloudflare-worker
./deploy-institute-cleanup.sh
```

---

## What Was Created

### 1. Worker Code
**File:** `src/institute-announcement-cleanup.ts`
- Scheduled function (runs every hour)
- Manual trigger endpoint
- Complete cleanup logic

### 2. Configuration
**File:** `wrangler-institute-cleanup.jsonc`
- Cron schedule: `0 * * * *` (every hour)
- R2 bucket binding
- Environment variables

### 3. Deployment Script
**File:** `deploy-institute-cleanup.sh`
- Automated deployment
- Configuration checks
- API key setup

---

## How It Works

### Automatic Cleanup (Every Hour)

```
1. Scheduled Trigger (Every Hour)
   ↓
2. Query Firestore: createdAt < (now - 24h)
   ↓
3. For each expired announcement:
   ├── Extract image URLs (imageCaptions + imageUrl)
   ├── Delete all images from R2
   ├── Delete views subcollection (up to 100 records)
   └── Delete main Firestore document
   ↓
4. Log Results
   └── Return: { deletedCount, imagesDeleted, viewsDeleted }
```

### Manual Trigger

```bash
# Test the worker
curl -X POST https://institute-announcement-cleanup.YOUR_SUBDOMAIN.workers.dev
```

---

## Deployment Steps

### Step 1: Set Firebase API Key (One-Time)

Get your API key from Firebase Console:
1. Go to: https://console.firebase.google.com/project/lenv-cb08e/settings/general
2. Scroll to "Web API Key"
3. Copy the key (looks like: `AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXX`)

Set it as a secret:
```bash
cd cloudflare-worker
wrangler secret put FIREBASE_API_KEY --config wrangler-institute-cleanup.jsonc
```

Paste your API key when prompted.

### Step 2: Deploy the Worker

```bash
./deploy-institute-cleanup.sh
```

Or manually:
```bash
wrangler deploy --config wrangler-institute-cleanup.jsonc
```

---

## Monitoring

### View Real-Time Logs

```bash
wrangler tail --config wrangler-institute-cleanup.jsonc
```

### Expected Log Output

```
🗑️ [INSTITUTE] Starting scheduled cleanup of 24h+ announcements...
📅 Searching for announcements older than: 2026-01-16T10:30:00.000Z
📂 Found 3 expired announcements to delete
  Processing announcement: abc123
    🗑️  Deleted image from R2
    🗑️  Deleted image from R2
    🗑️  Deleted 12 view records
  ✅ Deleted announcement: abc123
✅ [INSTITUTE] Cleanup completed: {
  deletedCount: 3,
  imagesDeleted: 6,
  viewsDeleted: 25,
  totalExpired: 3
}
```

---

## Testing

### Test with Curl

```bash
# Health check
curl https://institute-announcement-cleanup.YOUR_SUBDOMAIN.workers.dev

# Manual trigger
curl -X POST https://institute-announcement-cleanup.YOUR_SUBDOMAIN.workers.dev
```

### Test with Old Announcement

1. Create a test announcement in Firebase Console
2. Manually set `createdAt` to 25 hours ago
3. Trigger manual cleanup or wait for next hourly run
4. Verify announcement is deleted

---

## Configuration Details

### Cron Schedule

```jsonc
"crons": ["0 * * * *"]
```

Runs at the start of every hour:
- 00:00, 01:00, 02:00, ... 23:00

### R2 Bucket Binding

```jsonc
"r2_buckets": [
  {
    "binding": "R2_BUCKET",
    "bucket_name": "lenv-storage"
  }
]
```

### Environment Variables

```jsonc
"vars": {
  "FIREBASE_PROJECT_ID": "lenv-cb08e"
}
```

### Secrets (Encrypted)

- `FIREBASE_API_KEY` - Set via `wrangler secret put`

---

## What Gets Deleted

### From Firestore

1. **Main Document**
   ```
   /institute_announcements/{announcementId}
   ```

2. **Views Subcollection**
   ```
   /institute_announcements/{announcementId}/views/{userId}
   ```
   (All view records)

### From R2

All image files referenced in:
- `imageCaptions` array: `[{url: '...', caption: '...'}, ...]`
- `imageUrl` field (legacy single image)

Example deletions:
```
announcements/abc123_image1.jpg
announcements/abc123_image2.jpg
announcements/abc123_image3.jpg
```

---

## Cost Analysis

### Cloudflare Workers

**FREE TIER:**
- 100,000 requests/day
- 10ms CPU time per request
- Unlimited cron triggers

**Our Usage:**
- 24 cron triggers/day (hourly)
- ~2-5 seconds per run
- Well within free tier ✅

### Cloudflare R2

**FREE TIER:**
- 10 GB storage
- Unlimited DELETE operations (FREE)
- Class A operations: 1 million/month

**Our Usage:**
- DELETE operations: FREE ✅
- Reduces storage costs ✅

### Firebase (Firestore)

**Operations:**
- READ: 1 query per hour (24/day)
- DELETE: 1 per announcement + views
- Well within free tier ✅

---

## Troubleshooting

### Worker Not Deployed

```bash
# Check if wrangler is installed
wrangler --version

# Install if needed
npm install -g wrangler

# Login to Cloudflare
wrangler login

# Deploy
cd cloudflare-worker
./deploy-institute-cleanup.sh
```

### API Key Not Set

```bash
# Check secrets
wrangler secret list --config wrangler-institute-cleanup.jsonc

# Set if missing
wrangler secret put FIREBASE_API_KEY --config wrangler-institute-cleanup.jsonc
```

### Announcements Not Being Deleted

1. **Check logs:**
   ```bash
   wrangler tail --config wrangler-institute-cleanup.jsonc
   ```

2. **Verify schedule:**
   - Go to Cloudflare Dashboard
   - Workers & Pages > Overview
   - Find `institute-announcement-cleanup`
   - Check "Triggers" tab

3. **Test manually:**
   ```bash
   curl -X POST https://your-worker-url.workers.dev
   ```

### R2 Images Not Deleted

1. **Check R2 binding:**
   - Verify `wrangler-institute-cleanup.jsonc` has correct bucket name
   - Ensure bucket exists in Cloudflare R2

2. **Check image URLs:**
   - Must be full URLs: `https://files.lenv1.tech/announcements/file.jpg`
   - Worker extracts key: `announcements/file.jpg`

---

## Verify Deployment

### Check Worker Status

```bash
# List all workers
wrangler deployments list --config wrangler-institute-cleanup.jsonc

# View dashboard
# Go to: https://dash.cloudflare.com/
# Navigate to: Workers & Pages
# Find: institute-announcement-cleanup
```

### Test Endpoints

```bash
# Health check (GET)
curl https://institute-announcement-cleanup.YOUR_SUBDOMAIN.workers.dev

# Expected response:
{
  "status": "healthy",
  "worker": "institute-announcement-cleanup",
  "message": "POST to trigger manual cleanup",
  "schedule": "Every 1 hour",
  "retention": "24 hours"
}
```

---

## Advanced Configuration

### Change Retention Period

Edit `src/institute-announcement-cleanup.ts`:

```typescript
// Current: 24 hours
const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

// Change to 48 hours
const fortyEightHoursAgo = new Date(Date.now() - 48 * 60 * 60 * 1000);
```

Redeploy after changes.

### Change Schedule Frequency

Edit `wrangler-institute-cleanup.jsonc`:

```jsonc
// Current: Every hour
"crons": ["0 * * * *"]

// Every 30 minutes
"crons": ["*/30 * * * *"]

// Every 6 hours
"crons": ["0 */6 * * *"]
```

---

## Comparison: Cloudflare vs Firebase

| Feature | Cloudflare Workers | Firebase Functions |
|---------|-------------------|-------------------|
| **Cost** | FREE ✅ | Requires Blaze Plan 💰 |
| **Scheduled Triggers** | Unlimited FREE | Costs per invocation |
| **R2 Integration** | Native ✅ | Requires SDK |
| **Setup** | Simple config | Complex IAM |
| **Logs** | Real-time tail | Cloud Logging |

**Winner:** Cloudflare Workers (FREE + Simple) ✅

---

## Files Summary

### Created
- ✅ `src/institute-announcement-cleanup.ts` - Worker code
- ✅ `wrangler-institute-cleanup.jsonc` - Configuration
- ✅ `deploy-institute-cleanup.sh` - Deployment script
- ✅ `CLOUDFLARE_INSTITUTE_ANNOUNCEMENT_AUTODELETE.md` - This documentation

### Modified
- None (completely separate worker)

---

## Next Steps

1. **Deploy the worker:**
   ```bash
   cd cloudflare-worker
   ./deploy-institute-cleanup.sh
   ```

2. **Get your worker URL:**
   - Check deployment output
   - Or find in Cloudflare Dashboard

3. **Test manual trigger:**
   ```bash
   curl -X POST https://your-worker-url.workers.dev
   ```

4. **Monitor first run:**
   ```bash
   wrangler tail --config wrangler-institute-cleanup.jsonc
   ```

5. **Create test announcement:**
   - Set `createdAt` to 25h ago
   - Verify deletion works

---

## Support & Maintenance

### Regular Monitoring

```bash
# View logs
wrangler tail --config wrangler-institute-cleanup.jsonc

# Check metrics in dashboard
# https://dash.cloudflare.com/
```

### Update Worker

```bash
# Make changes to src/institute-announcement-cleanup.ts
# Redeploy
./deploy-institute-cleanup.sh
```

---

## Status

✅ **Implementation:** Complete  
✅ **Testing:** Manual trigger ready  
✅ **Deployment:** Script ready  
✅ **Cost:** FREE (Cloudflare Workers)  
✅ **Schedule:** Every 1 hour  
✅ **Retention:** 24 hours  
✅ **Cleanup:** Firestore + R2 + Views  

---

## Summary

Your institute announcements will now automatically be deleted after 24 hours using a FREE Cloudflare Worker. The worker:

- ✅ Runs automatically every hour
- ✅ Deletes announcements older than 24 hours
- ✅ Removes all images from R2
- ✅ Cleans up views subcollection
- ✅ Completely removes from Firestore
- ✅ Costs nothing (FREE tier)
- ✅ No Firebase paid plan required

**Deploy now:**
```bash
cd cloudflare-worker && ./deploy-institute-cleanup.sh
```
