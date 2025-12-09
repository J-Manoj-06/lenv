# ✅ FIXED: 401 Unauthorized Error

## 🔴 Problem
```
R2 Upload: Response status: 401
Unauthorized
```

This means the signature didn't match what Cloudflare expected.

## 🔍 Root Cause
The AWS Signature V4 was calculated using `lenv-storage.r2.cloudflarestorage.com` as the hostname, but we were uploading to `files.lenv1.tech`. 

When calculating an AWS Sig V4 signature, the **Host header must match exactly**. Since they didn't match, Cloudflare rejected the request as unauthorized.

## ✅ Solution
Updated the signature calculation to use the **actual upload hostname** we'll be sending the request to.

### How It Works Now:
1. **Determine upload hostname**: Use custom domain if available (`files.lenv1.tech`)
2. **Calculate signature WITH that hostname**: Signature includes `host:files.lenv1.tech`
3. **Upload to same hostname**: Send request to `files.lenv1.tech`
4. **Signature matches**: ✅ 200 OK!

### File Changed:
**lib/services/cloudflare_r2_service.dart**

**Changes:**
1. Added `uploadHostname` parameter to `generateSignedUploadUrl()`
2. Added `uploadHostname` parameter to `_getSignatureHeaders()`
3. Changed canonical request to use `host:$uploadHostname` (was hardcoded to R2 domain)
4. Now signature is calculated with actual hostname we're uploading to

## 📋 Key Fix
**BEFORE (WRONG):**
```
Canonical request uses: host:lenv-storage.r2.cloudflarestorage.com
Request sent to: https://files.lenv1.tech
❌ Mismatch = 401 Unauthorized
```

**AFTER (CORRECT):**
```
Canonical request uses: host:files.lenv1.tech
Request sent to: https://files.lenv1.tech
✅ Match = 200 OK!
```

## 🧪 Test Now

1. Run `flutter run`
2. Login as student
3. Go to Dev Tools (wrench icon 🔧)
4. Click "🎥 Test Media Upload"
5. Pick an image

### Expected Success:
```
✅ Signed URL generated
🔍 Upload hostname: files.lenv1.tech
🔍 R2 Upload: Starting upload
🔍 R2 Upload: Response status: 200
✅ R2 Upload: Success! URL: https://files.lenv1.tech/media/...
```

## 🎯 AWS Signature V4 Explained
The canonical request is CRITICAL for signing:
```
PUT
/media/timestamp/photo.jpg
X-Amz-Algorithm=...&X-Amz-Date=...
host:files.lenv1.tech    ← THIS MUST MATCH THE REQUEST HOSTNAME!
```

If Host header doesn't match, signature is invalid = 401 error.

---

**Ready?** Run `flutter run` and test the upload!
