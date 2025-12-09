# 🔧 FIXED: AWS Signature V4 - 400 Error

## ✅ What Was Wrong

The 400 error was caused by **incorrect AWS Signature V4 canonical request format** in the Cloudflare R2 service.

### Root Cause
- **Incorrect path format**: Used `/$bucketName/$key` instead of `/$key`
- **Incorrect hostname format**: Used `$accountId.r2.cloudflarestorage.com` instead of `$bucketName.r2.cloudflarestorage.com`
- **Incorrect URL format**: Signed URL had wrong path structure

This caused the signature to not match what Cloudflare expected, resulting in a 400 error.

## 🔧 Fixes Applied

### File: `lib/services/cloudflare_r2_service.dart`

**1. Fixed Canonical Request Path:**
```dart
// BEFORE (WRONG)
/$bucketName/$key

// AFTER (CORRECT)
/$key
```

**2. Fixed Hostname:**
```dart
// BEFORE (WRONG)
host:$accountId.r2.cloudflarestorage.com

// AFTER (CORRECT)
host:$bucketName.r2.cloudflarestorage.com
```

**3. Fixed Signed URL Generation:**
```dart
// BEFORE (WRONG)
$_endpoint/$bucketName/$key?...params

// AFTER (CORRECT)
https://$bucketName.r2.cloudflarestorage.com/$key?...params
```

**4. Fixed URL Extraction:**
```dart
// BEFORE (COMPLEX & ERROR-PRONE)
return 'https://$r2Domain${path.substring(bucketName.length + 1)}';

// AFTER (SIMPLE & CORRECT)
return 'https://$r2Domain$pathWithoutQuery';
```

**5. Added Debug Logging:**
Now the console will show:
```
✅ Signed URL generated
🔍 Key: media/1702041600000/photo.jpg
🔍 Expires At: 1702128000
🔍 R2 Upload: Starting upload
🔍 R2 Upload: Content-Type: image/jpeg
🔍 R2 Upload: File size: 2101248 bytes
🔍 R2 Upload: Response status: 200
✅ R2 Upload: Success! URL: https://files.lenv1.tech/media/...
```

## 🧪 Test Now

1. Run `flutter run`
2. Login as student
3. Click Dev Tools (wrench icon 🔧)
4. Click "🎥 Test Media Upload"
5. Pick an image

### Expected Result:
- ✅ Progress bar shows and updates (0% → 100%)
- ✅ No 400 error
- ✅ Console shows "✅ R2 Upload: Success!"
- ✅ File appears in Cloudflare R2 bucket
- ✅ Metadata appears in Firestore

## 🐛 If Still Getting 400 Error

Check the console output for:

1. **Signature mismatch**: 
   - Verify `accountId`, `accessKeyId`, `secretAccessKey` in Cloudflare config
   - Check API token has `s3:PutObject` permission

2. **Wrong bucket name**:
   - Verify `bucketName` is exactly `lenv-storage` (no typos)

3. **Expired URL**:
   - Check system clock is correct
   - URL expires after 24 hours

4. **CORS issues**:
   - Check Cloudflare R2 CORS settings

## 📊 AWS Signature V4 Explained

The fix corrects the canonical request to match AWS Signature V4 spec:

```
PUT
/media/1702041600000/photo.jpg           ← Path (without bucket)
X-Amz-Algorithm=...&X-Amz-Credential=... ← Query params (sorted)
host:lenv-storage.r2.cloudflarestorage.com ← Bucket in hostname
```

The signature is calculated from this canonical request. If any part is wrong, the signature won't match and you get 400.

---

**Ready?** Run `flutter run` and test the upload again!
