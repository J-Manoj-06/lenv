# ⚡ QUICK FIX CHECKLIST - Just Copy-Paste!

## 🎯 What to Do RIGHT NOW (5 mins)

You have **1 main file to create/update** and **3 values to enter**.

---

## STEP 1: Get Your Credentials (2 mins)

### From Cloudflare

Go to: https://dash.cloudflare.com

**Find R2 Dashboard:**
1. Click "R2" in left sidebar
2. Click your bucket "lenv-storage"
3. Copy these 5 values:

```
Account ID:           [COPY FROM PAGE]
Bucket Name:          lenv-storage
Access Key ID:        [COPY FROM API TOKENS]
Secret Access Key:    [COPY FROM API TOKENS - SHOWN ONLY ONCE!]
R2 Domain:            files.lenv1.tech
```

### From Firebase

Go to: https://console.firebase.google.com

**Find Cloud Function URL:**
1. Click "Functions" in left sidebar
2. Look for `uploadFileToR2` function
3. Copy the HTTPS URL that looks like:
   ```
   https://us-central1-your-project.cloudfunctions.net/uploadFileToR2
   ```

---

## STEP 2: Update Config File (1 min)

**File:** `lib/config/cloudflare_config.dart`

Replace these 6 lines with your values:

```dart
class CloudflareConfig {
  static const String accountId = 'PASTE_YOUR_ACCOUNT_ID_HERE';
  static const String bucketName = 'lenv-storage';
  static const String accessKeyId = 'PASTE_YOUR_ACCESS_KEY_HERE';
  static const String secretAccessKey = 'PASTE_YOUR_SECRET_ACCESS_KEY_HERE';
  static const String r2Domain = 'files.lenv1.tech';
  static const String firebaseCloudFunctionUrl = 'PASTE_YOUR_CLOUD_FUNCTION_URL_HERE';
}
```

**Example (filled):**
```dart
class CloudflareConfig {
  static const String accountId = '4c51b62d64def00af4856f10b6104fe2';
  static const String bucketName = 'lenv-storage';
  static const String accessKeyId = 'e5606eba19c4cc21cb9493128afc1f01';
  static const String secretAccessKey = 'e060ff4595dd7d3e420eebaa76a5eb9b2d360bb7e078e5b039121dcac6e65e7e';
  static const String r2Domain = 'files.lenv1.tech';
  static const String firebaseCloudFunctionUrl = 'https://us-central1-new-reward-prod.cloudfunctions.net/uploadFileToR2';
}
```

---

## STEP 3: Deploy Cloud Function (2 mins)

Open terminal in your project root:

```bash
# Go to functions folder
cd functions

# Deploy the upload function
firebase deploy --only functions:uploadFileToR2
```

Wait for it to say: ✔ Deploy complete!

Copy the function URL if you don't have it yet.

---

## ✅ DONE! Test It Now

```bash
# Run app
flutter run

# In app:
# 1. Login
# 2. Go to Dashboard (home)
# 3. Click orange wrench icon (🔧) top-right
# 4. Click green "🎥 Test Media Upload" button
# 5. Click "Pick Image from Gallery"
# 6. Watch progress bar (should show 0% → 100%)
# 7. If successful, image is in R2 ✅
```

---

## 🔍 Verify It Worked

### Check 1: Progress Bar Shows
- [ ] You pick image
- [ ] Progress bar appears
- [ ] Shows percentage (0% → 100%)
- [ ] No red error text

### Check 2: File in Cloudflare R2
- [ ] Go to https://dash.cloudflare.com
- [ ] Click R2 → lenv-storage
- [ ] Look for folder: `schools/test-school/communities/test-conv-123/groups/test-group/messages/[id]/photo.jpg`
- [ ] File should be there ✅

### Check 3: Metadata in Firebase Firestore
- [ ] Go to https://console.firebase.google.com
- [ ] Click Firestore Database
- [ ] Navigate: schools → test-school → communities → test-conv-123 → groups → test-group → messages → [id] → files → photo.jpg
- [ ] Should see document with metadata ✅

---

## ⚠️ If It Fails

### Error: "Missing authorization token"
- ✅ Login first before uploading

### Error: "Invalid token"
- ✅ Restart app (token refreshes automatically)

### Error: "R2 upload failed with status 401/403"
- ✅ Check your credentials are correct (copy-paste, no typos)
- ✅ Check API token has permissions: s3:PutObject, s3:GetObject, s3:ListBucket

### Error: "Upload timeout"
- ✅ Try smaller image
- ✅ Check internet connection

### Progress bar doesn't show
- ✅ Restart app
- ✅ Check console for errors

### File not in R2
- ✅ Check R2 bucket exists
- ✅ Check credentials are correct
- ✅ Check bucket name is exactly: `lenv-storage`

### No metadata in Firestore
- ✅ Check Firestore is enabled in Firebase Console
- ✅ Check Security Rules allow writes: `allow write: if request.auth != null;`

---

## 📋 Copy-Paste Summary

You need to:

1. **Get 6 values:**
   - accountId (from Cloudflare)
   - accessKeyId (from Cloudflare)
   - secretAccessKey (from Cloudflare)
   - r2Domain (your custom domain)
   - firebaseCloudFunctionUrl (from Firebase)

2. **Update 1 file:**
   - `lib/config/cloudflare_config.dart` - paste the 6 values

3. **Deploy 1 function:**
   - `firebase deploy --only functions:uploadFileToR2`

4. **Test:**
   - Run app → Login → Dev Tools → Test Media Upload

That's it! 🎉

---

## 🚨 Don't Forget

- [ ] Copy Secret Access Key to safe place (shows only ONCE)
- [ ] Don't share credentials with anyone
- [ ] For production, use secure storage (flutter_secure_storage)
- [ ] Set up Firestore Security Rules properly before production

---

## 📞 Still Need Help?

Read: **COMPLETE_SETUP_GUIDE.md** (in project root)

It has:
- ✅ Architecture explanation
- ✅ All code samples
- ✅ Step-by-step instructions
- ✅ Full troubleshooting section
- ✅ Common errors + fixes

---

**Time to Complete:** 5-10 minutes  
**Difficulty:** Easy (just copy-paste)  
**Status:** All code is ready - just needs your credentials
