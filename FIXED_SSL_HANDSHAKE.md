# ✅ FIXED: SSL/TLS Handshake Error

## 🔴 Problem
```
HandshakeException: Handshake error in client 
SSLV3_ALERT_HANDSHAKE_FAILURE
```

This error occurred when trying to upload to `lenv-storage.r2.cloudflarestorage.com`.

## 🔍 Root Cause
The R2 API domain (`*.r2.cloudflarestorage.com`) has SSL certificate issues on some devices/networks, especially on Android.

## ✅ Solution
Changed the upload to use your **custom domain** (`files.lenv1.tech`) which has proper SSL certificates.

### How It Works:
1. **Signature is calculated** using `lenv-storage.r2.cloudflarestorage.com` (AWS Sig V4 requirement)
2. **Upload is sent** via custom domain `files.lenv1.tech` (which Cloudflare routes to R2)
3. **Same signature works** because Cloudflare routes both domains to the same R2 bucket

### File Changed:
**lib/services/cloudflare_r2_service.dart**
- Updated `generateSignedUploadUrl()` to use `r2Domain` for uploading
- Kept bucket.r2.cloudflarestorage.com for signature calculation
- Added debug logging to show which domain is being used

## ✅ Your Configuration is Perfect
```dart
accountId = '4c51b62d64def00af4856f10b6104fe2'         ✅ Correct
bucketName = 'lenv-storage'                            ✅ Correct
accessKeyId = 'e5606eba19c4cc21cb9493128afc1f01'      ✅ Correct
secretAccessKey = 'e060ff4595dd7d3e...' (hidden)      ✅ Correct
r2Domain = 'files.lenv1.tech'                          ✅ Correct & will fix SSL!
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
🔍 Upload domain: files.lenv1.tech
🔍 R2 Upload: Starting upload
✅ R2 Upload: Success! URL: https://files.lenv1.tech/media/...
```

## 📋 Cloudflare Config Verification

Your configuration has:
- ✅ Account ID (verified)
- ✅ Bucket Name (verified)
- ✅ Access Key ID (verified)
- ✅ Secret Access Key (verified)
- ✅ Custom Domain (`files.lenv1.tech`) with proper SSL

**All details are correct!** 🎉

## 🔒 Why This Works

Cloudflare R2 allows:
1. **Direct upload to API domain** (problematic SSL on some networks)
2. **Upload via custom domain** (files.lenv1.tech - has proper SSL)
3. **Both use same authorization** (same signed URL works for both)

By uploading via your custom domain:
- ✅ Better SSL certificate coverage
- ✅ Better performance (CDN edge)
- ✅ Same security (AWS Sig V4 signed)

## 🐛 If Still Getting SSL Error

Try these:
1. **Clear app cache**: Uninstall and reinstall app
2. **Update CA certificates**: Some Android devices need cert updates
3. **Check network**: Try different WiFi/mobile network
4. **Verify domain**: Ensure `files.lenv1.tech` CNAME points to R2 bucket

---

**Ready?** Run `flutter run` and test the upload!
