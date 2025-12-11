# 🎨 Cloudflare Worker Visual Deployment Guide

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter App (Dart)                          │
│                                                                 │
│  MediaUploadService.uploadMedia(                               │
│    file: announcementImage,                                    │
│    mediaType: 'announcement'  ← 24-hour deletion               │
│  )                                                             │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│              Cloudflare R2 Storage (Media Files)                │
│                                                                 │
│  /media/announcement_12345.jpg                                 │
│  /thumbnails/thumbnail_12345.jpg                               │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│            Firebase Firestore (Metadata)                        │
│                                                                 │
│  media_messages/{id}                                           │
│  ├─ mediaType: "announcement"                                  │
│  ├─ createdAt: 2024-12-11T10:00:00Z                          │
│  ├─ r2Url: "https://pub-xxx.r2.dev/media/..."                │
│  └─ deletedAt: null                                            │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ [24 hours pass]
                     │
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│         Cloudflare Worker (Scheduled Cron)                      │
│                                                                 │
│  Trigger: Every hour (0 * * * *)                               │
│  ├─ Query Firestore REST API                                   │
│  ├─ Find: mediaType='announcement' AND createdAt < 24h        │
│  ├─ Delete from R2 (file + thumbnail)                         │
│  └─ Update Firestore: deletedAt = now()                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Deployment Flow

```
Step 1: Get Firebase Credentials
┌─────────────────────────────────────┐
│ Firebase Console                    │
│ ├─ Project Settings                 │
│ ├─ Copy Project ID                  │
│ └─ Copy Web API Key                 │
└─────────────────────────────────────┘
            ↓
Step 2: Set Cloudflare Secrets
┌─────────────────────────────────────┐
│ Terminal                            │
│ $ wrangler secret put               │
│   FIREBASE_PROJECT_ID               │
│ $ wrangler secret put               │
│   FIREBASE_API_KEY                  │
└─────────────────────────────────────┘
            ↓
Step 3: Deploy Worker
┌─────────────────────────────────────┐
│ Terminal                            │
│ $ npm run deploy:media-cleanup      │
│                                     │
│ ✅ Worker deployed                  │
│ ✅ Cron trigger active              │
│ ✅ R2 binding configured            │
└─────────────────────────────────────┘
```

---

## Media Type Decision Tree

```
                User Uploads Media
                       │
                       ↓
           ┌───────────┴───────────┐
           │                       │
      mediaType='announcement'  mediaType='message'/'community'
           │                       │
           ↓                       ↓
    ┌─────────────┐         ┌─────────────┐
    │  24 HOURS   │         │  PERMANENT  │
    │             │         │             │
    │ Auto-delete │         │ Never       │
    │ by Worker   │         │ deleted     │
    └─────────────┘         └─────────────┘
           │                       │
           ↓                       ↓
    After 24 hours:          Stays forever:
    ├─ Delete R2            ├─ R2 file kept
    ├─ Delete thumbnail     ├─ Firestore kept
    └─ Set deletedAt        └─ Always visible
```

---

## Cost Comparison

```
Firebase Cloud Functions               Cloudflare Workers
┌──────────────────────┐              ┌──────────────────────┐
│ Requires:            │              │ Requirements:        │
│ ├─ Blaze Plan        │              │ ├─ Free tier        │
│ ├─ Cloud Scheduler   │              │ ├─ Built-in cron    │
│ └─ Cold starts       │              │ └─ Zero cold starts │
│                      │              │                      │
│ Cost: $0.10-0.50/mo  │              │ Cost: $0.00/month   │
└──────────────────────┘              └──────────────────────┘
         ❌                                    ✅
```

---

## Worker Execution Timeline

```
Hour 0:00  ──► Worker runs
              ├─ Query Firestore for expired media
              ├─ Found 3 announcements older than 24h
              ├─ Delete from R2
              └─ Update Firestore
              
Hour 1:00  ──► Worker runs
              ├─ Query Firestore
              └─ No expired media found
              
Hour 2:00  ──► Worker runs
              ├─ Query Firestore
              ├─ Found 1 announcement older than 24h
              └─ Delete from R2
              
... continues every hour ...
```

---

## File Structure

```
cloudflare-worker/
│
├── src/
│   ├── index.ts                    (Existing upload worker)
│   └── delete-expired-media.ts     ← NEW: Deletion worker
│
├── wrangler.jsonc                  (Existing upload config)
├── wrangler-delete-media.jsonc     ← NEW: Deletion config
│
├── .dev.vars                       (Existing upload secrets)
├── .dev.vars.delete-media          ← NEW: Deletion secrets
│
├── package.json                    ← Updated with scripts
│
└── Documentation
    ├── MEDIA_DELETION_DEPLOYMENT.md
    ├── QUICK_START_MEDIA_DELETION.md
    └── (this file)
```

---

## Monitoring Dashboard

```
┌─────────────────────────────────────────────────────────────┐
│ Cloudflare Dashboard                                        │
│                                                             │
│ Workers & Pages → delete-expired-media-worker               │
│                                                             │
│ ┌─────────────────────────────────────────────────────┐   │
│ │ Metrics                                              │   │
│ │ ├─ Requests: 24/day                                 │   │
│ │ ├─ Success Rate: 100%                               │   │
│ │ └─ Avg Duration: 500ms                              │   │
│ └─────────────────────────────────────────────────────┘   │
│                                                             │
│ ┌─────────────────────────────────────────────────────┐   │
│ │ Logs                                                 │   │
│ │ 🗑️ [MEDIA] Starting cleanup...                      │   │
│ │ 📂 [MEDIA] Found 3 expired media                    │   │
│ │ ✨ [MEDIA] Cleanup completed! Deleted: 3            │   │
│ └─────────────────────────────────────────────────────┘   │
│                                                             │
│ ┌─────────────────────────────────────────────────────┐   │
│ │ Triggers                                             │   │
│ │ ├─ Cron: 0 * * * * (Every hour)                     │   │
│ │ └─ Status: ✅ Active                                 │   │
│ └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Commands Reference

```powershell
# Deploy worker
npm run deploy:media-cleanup

# View real-time logs
npm run tail:media-cleanup

# Test locally
npm run dev:media-cleanup

# List secrets
npx wrangler secret list --config wrangler-delete-media.jsonc

# Set secret
npx wrangler secret put SECRET_NAME --config wrangler-delete-media.jsonc

# Manual trigger (production)
curl -X POST https://delete-expired-media-worker.YOUR_SUBDOMAIN.workers.dev/trigger-cleanup `
  -H "Authorization: Bearer YOUR_FIREBASE_API_KEY"
```

---

## Success Indicators

```
✅ Deployment Success
   ├─ Worker appears in Cloudflare Dashboard
   ├─ Cron trigger shows "Active"
   ├─ R2 bucket binding shows "lenv-storage"
   └─ Secrets list shows FIREBASE_PROJECT_ID and FIREBASE_API_KEY

✅ Runtime Success
   ├─ Logs show "Starting cleanup..."
   ├─ Logs show "Found X expired media" or "No expired media found"
   ├─ Logs show "Cleanup completed! Deleted: X"
   └─ Firestore shows deletedAt timestamp on deleted media

✅ Integration Success
   ├─ Announcement uploads use mediaType: 'announcement'
   ├─ Message uploads use mediaType: 'message'
   ├─ Community uploads use mediaType: 'community'
   └─ App filters out deleted media (deletedAt != null)
```

---

## Troubleshooting Quick Guide

```
Problem: Worker not deleting media
├─ Check 1: Verify cron trigger is active (Cloudflare Dashboard)
├─ Check 2: View logs (npm run tail:media-cleanup)
├─ Check 3: Manual trigger test
└─ Check 4: Verify Firestore has expired announcements

Problem: "Unauthorized" error
├─ Check 1: Verify FIREBASE_API_KEY secret is set
├─ Check 2: Test Firestore API manually
└─ Check 3: Check Firestore security rules

Problem: "R2 bucket not found"
├─ Check 1: Verify bucket name is "lenv-storage"
├─ Check 2: Check R2 binding in wrangler config
└─ Check 3: Redeploy worker

Problem: Cron not triggering
├─ Check 1: Verify cron syntax: "0 * * * *"
├─ Check 2: Check Triggers tab in Cloudflare Dashboard
└─ Check 3: Redeploy worker
```

---

## Timeline Example

```
Day 1, 10:00 AM - Upload announcement
                  ├─ mediaType: 'announcement'
                  ├─ createdAt: 2024-12-11T10:00:00Z
                  └─ Status: Active ✅

Day 2, 10:00 AM - Still visible
                  └─ Status: Active ✅

Day 2, 11:00 AM - Worker runs (25 hours after upload)
                  ├─ Query finds expired announcement
                  ├─ Delete from R2 ✓
                  ├─ Set deletedAt: 2024-12-12T11:00:00Z
                  └─ Status: Soft-deleted ⚠️

Day 2, 11:01 AM - App checks deletedAt
                  └─ Status: Hidden from users ❌
```

---

## Summary Checklist

Before deployment:
- [ ] Got Firebase Project ID
- [ ] Got Firebase Web API Key
- [ ] Reviewed cron schedule (every hour)
- [ ] Understood soft-delete approach

During deployment:
- [ ] Set FIREBASE_PROJECT_ID secret
- [ ] Set FIREBASE_API_KEY secret
- [ ] Ran `npm run deploy:media-cleanup`
- [ ] Verified in Cloudflare Dashboard

After deployment:
- [ ] Monitored real-time logs
- [ ] Tested manual trigger
- [ ] Uploaded test announcement
- [ ] Waited 25h and verified deletion

---

## 🎯 Final Check

```
✅ Worker deployed to Cloudflare
✅ Cron trigger active (every hour)
✅ R2 binding configured
✅ Firestore REST API integrated
✅ Secrets set correctly
✅ Logs showing successful execution
✅ Cost: $0/month

Status: READY FOR PRODUCTION 🚀
```

---

**Need detailed steps?** See `MEDIA_DELETION_DEPLOYMENT.md`  
**Need quick start?** See `QUICK_START_MEDIA_DELETION.md`  
**Need overview?** See `CLOUDFLARE_MEDIA_DELETION_SUMMARY.md`
