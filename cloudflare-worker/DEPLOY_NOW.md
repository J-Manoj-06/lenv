# 🚀 DEPLOY NOW - Institute Announcement Auto-Delete

## ⚡ Quick Start (2 Steps)

### Step 1: Set Firebase API Key

```bash
cd cloudflare-worker
wrangler secret put FIREBASE_API_KEY --config wrangler-institute-cleanup.jsonc
```

**Where to get the API key:**
1. Open: https://console.firebase.google.com/project/lenv-cb08e/settings/general
2. Scroll to "Web API Key"
3. Copy the key (starts with `AIzaSy...`)
4. Paste it when prompted

### Step 2: Deploy

```bash
./deploy-institute-cleanup.sh
```

That's it! ✅

---

## What This Does

✅ **Automatic 24-hour deletion** of institute announcements  
✅ **Deletes all images** from Cloudflare R2  
✅ **Removes views** subcollection  
✅ **Cleans up Firestore** completely  
✅ **Runs every hour** automatically  
✅ **Completely FREE** (Cloudflare Workers)  

---

## Testing After Deployment

### 1. Get Your Worker URL
After deployment, you'll see:
```
✅ Published institute-announcement-cleanup
   https://institute-announcement-cleanup.YOUR_ACCOUNT.workers.dev
```

### 2. Test Manual Trigger
```bash
curl -X POST https://institute-announcement-cleanup.YOUR_ACCOUNT.workers.dev
```

### 3. Monitor Logs
```bash
wrangler tail --config wrangler-institute-cleanup.jsonc
```

---

## Files Created

✅ `src/institute-announcement-cleanup.ts` - Worker code  
✅ `wrangler-institute-cleanup.jsonc` - Configuration  
✅ `deploy-institute-cleanup.sh` - Deployment script  
✅ `CLOUDFLARE_INSTITUTE_ANNOUNCEMENT_AUTODELETE.md` - Full docs  

---

## How It Works

```
Every Hour → Check Firestore → Find announcements > 24h old
   ↓
Delete images from R2 → Delete views → Delete Firestore doc
   ↓
Log results → Done!
```

---

## Cost

**$0.00** - Completely FREE using Cloudflare Workers free tier

No Firebase paid plan needed! ✅

---

## Full Documentation

See: `CLOUDFLARE_INSTITUTE_ANNOUNCEMENT_AUTODELETE.md`

---

## Ready to Deploy?

```bash
cd /home/manoj/Desktop/new_reward/cloudflare-worker

# Set API key (one-time)
wrangler secret put FIREBASE_API_KEY --config wrangler-institute-cleanup.jsonc

# Deploy
./deploy-institute-cleanup.sh
```

Done! 🎉
