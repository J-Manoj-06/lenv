# ⚡ Quick Start: Deploy Media Deletion Worker to Cloudflare

## 3-Step Deployment

### Step 1: Get Firebase Credentials (2 minutes)

1. Open https://console.firebase.google.com
2. Select your project → **⚙️ Settings** → **Project Settings**
3. Copy:
   - **Project ID** (e.g., `your-project-12345`)
   - **Web API Key** (starts with `AIzaSy...`)

---

### Step 2: Set Cloudflare Secrets (1 minute)

```powershell
cd d:\new_reward\cloudflare-worker

npx wrangler secret put FIREBASE_PROJECT_ID --config wrangler-delete-media.jsonc
# Paste your Project ID when prompted

npx wrangler secret put FIREBASE_API_KEY --config wrangler-delete-media.jsonc
# Paste your Web API Key when prompted
```

---

### Step 3: Deploy (30 seconds)

```powershell
npm run deploy:media-cleanup
```

**Done!** ✅

---

## Verify Deployment

### Check it's live:
```powershell
# View real-time logs
npm run tail:media-cleanup
```

### Manual test:
```powershell
curl -X POST https://delete-expired-media-worker.YOUR_SUBDOMAIN.workers.dev/trigger-cleanup `
  -H "Authorization: Bearer YOUR_FIREBASE_API_KEY"
```

---

## What Happens Next?

1. **Every hour at :00** - Worker runs automatically
2. **Queries Firestore** - Finds announcement media older than 24h
3. **Deletes from R2** - Removes files and thumbnails
4. **Soft-deletes Firestore** - Sets `deletedAt` timestamp

---

## Cost

**$0/month** - 100% within Cloudflare free tier

---

## Monitoring

**Real-time logs**:
```powershell
npm run tail:media-cleanup
```

**Cloudflare Dashboard**:
- Workers & Pages → `delete-expired-media-worker` → Logs

---

## Need Help?

See full guide: `MEDIA_DELETION_DEPLOYMENT.md`

---

## Summary

✅ Worker deployed to Cloudflare (not Firebase)  
✅ Runs every hour automatically  
✅ Deletes announcement media after 24 hours  
✅ Messages and community media stay permanent  
✅ Zero cost ($0/month)  

**Your media deletion is now automated!** 🎉
