# Cloudflare-Only Media System - Quick Start

## What Changed

**Before:** Firebase Cloud Functions + Cloudflare R2  
**Now:** Cloudflare Workers + Cloudflare R2 (all in one ecosystem)

## Key Files Modified

1. **Worker Upload Endpoint** (NEW)
   - File: `cloudflare-worker/src/whatsapp-media-worker.ts` 
   - Feature: POST `/upload` endpoint
   - Status: ✅ Deployed (v0dcd5dfe...)

2. **Flutter Worker Service** (NEW)
   - File: `lib/services/cloudflare_worker_upload_service.dart`
   - Replaces: `cloud_function_upload_service.dart` (Firebase version)
   - Status: ✅ Ready

3. **Media Chat Provider** (UPDATED)
   - File: `lib/providers/media_chat_provider.dart`
   - Change: Uses `CloudflareWorkerUploadService` instead of Firebase
   - Status: ✅ Updated

4. **Opacity Fixes** (FIXED)
   - Files: `swipeable_card.dart`, `motivation_card.dart`, `history_card.dart`, `fact_card.dart`
   - Status: ✅ Fixed (clamped to 0.0-1.0 range)

## Upload Endpoints

### Public Download (Free Egress)
```
GET https://files.lenv1.tech/media/{key}
↓
Worker fetches from R2 via env.MEDIA_BUCKET binding
↓
Returns file (0 egress cost!)
```

### File Upload
```
POST https://whatsapp-media-worker.giridharannj.workers.dev/upload
Content-Type: multipart/form-data

Fields:
  - file: [binary file data]
  - schoolId: "CSK100"
  - communityId: "ABC123"
  - groupId: "GRP456"
  - messageId: "MSG789"

Response:
{
  "success": true,
  "key": "media/schools/CSK100/communities/ABC123/groups/GRP456/messages/MSG789/1765476447456/image.jpg",
  "publicUrl": "https://files.lenv1.tech/media/schools/CSK100/communities/ABC123/groups/GRP456/messages/MSG789/1765476447456/image.jpg",
  "fileName": "image.jpg",
  "fileSize": 245892,
  "expiresAt": "2025-01-10T23:37:27.123Z"
}
```

## Testing

```bash
# 1. Hot reload to apply opacity fixes
r

# 2. Pick an image and upload from chat
# You should see in console:
# "📤 Starting Cloudflare Worker upload"
# "✅ Cloudflare Worker upload complete"
# "Public URL: https://files.lenv1.tech/media/schools/..."

# 3. Verify URL format (should have /media/ not /lenv-storage/)
# Test in browser or curl:
curl -I https://files.lenv1.tech/media/schools/...
# Expected: HTTP 200 OK

# 4. Watch worker logs in real-time
cd cloudflare-worker
npm run tail
```

## Files You Can Delete

- `lib/services/cloud_function_upload_service.dart` (Old Firebase version)
- `lenv-functions/` (Firebase Cloud Functions, no longer needed)
- Any `firebase.json` references to uploadFileToR2 function

## Cost Savings

| Operation | Cost Before | Cost After |
|-----------|------------|-----------|
| Upload | Free (except traffic) | Free |
| Download | $0.0183/GB (egress) | $0 (Worker binding) |
| Compute | $0.40/million requests | $0.50 included/day free |
| **Total** | **High egress charges** | **Almost free** |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| 401 Unauthorized | Firebase auth token expired - re-login |
| 413 Payload Too Large | File exceeds 20MB limit |
| 404 Not Found | Wait 5 seconds for R2 replication (rare) |
| Network timeout | Check internet connection, file might still upload |
| `Cannot find module 'cloudflare_worker_upload_service'` | Run `flutter pub get` |

## What Still Uses Firebase

✅ Firebase Auth (user login)  
✅ Firestore (message storage)  
✅ Cloud Storage (for older media, can migrate later)  

❌ Firebase Cloud Functions (REMOVED)  
❌ Firebase Storage for new media (now Cloudflare R2)

## Next: Optional Cleanup

If you want to fully migrate away from Firebase Functions:

```bash
# 1. Delete Cloud Function from GCP Console
# Navigate to Cloud Functions > uploadFileToR2 > Delete

# 2. Remove from Firebase config
firebase functions:delete uploadFileToR2

# 3. Remove from local code
rm lib/services/cloud_function_upload_service.dart
rm -rf lenv-functions/  # Or keep for reference
```

---

✅ **System is now pure Cloudflare for all media operations**
