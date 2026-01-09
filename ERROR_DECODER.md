# 🔴 ERROR DECODER - What Your Errors Mean

Use this to quickly understand what's wrong. Then go to **COMPLETE_SETUP_GUIDE.md** for the full fix.

---

## 📱 FLUTTER/APP ERRORS

### ❌ "User not authenticated" or "please login first"

**What it means:** You're not logged in before uploading

**Fix:**
1. Login to app first
2. Make sure Firebase Authentication is working
3. Check you're using correct Firebase project

**Verify:**
```dart
final user = FirebaseAuth.instance.currentUser;
print('User: ${user?.email}'); // Should print email, not null
```

---

### ❌ "Failed to get authentication token"

**What it means:** Firebase can't give you an ID token

**Why:** 
- Internet connection lost
- Firebase Auth service not responding
- Project misconfiguration

**Fix:**
1. Restart app (forces token refresh)
2. Check internet connection
3. Re-login
4. Restart Firebase emulator if using local Firebase

---

### ❌ "Upload timeout (took more than 5 minutes)"

**What it means:** Upload is taking too long

**Why:**
- Internet connection is very slow
- File is huge (should be < 50MB)
- Cloud Function is overloaded
- Server not responding

**Fix:**
1. Try with smaller image
2. Check internet connection
3. Wait a bit and retry
4. Increase timeout in code:
```dart
// In cloud_function_upload_service.dart
.timeout(
  const Duration(minutes: 10), // increase from 5 to 10
  onTimeout: () => throw Exception('Upload timeout'),
),
```

---

### ❌ "Upload failed: 400" or "Bad Request"

**What it means:** You're sending wrong data to Cloud Function

**Why:**
- File is not base64 encoded properly
- Missing required fields (fileName, fileBase64, etc)
- Field format is wrong

**Check in code:**
```dart
// Make sure requestBody has ALL these fields:
{
  'fileName': fileName,         // ✅ must be string
  'fileBase64': fileBase64,     // ✅ must be base64 encoded
  'fileType': mimeType,         // ✅ must be MIME type (image/jpeg)
  'schoolId': schoolId,         // ✅ must be string
  'communityId': communityId,   // ✅ must be string
  'groupId': groupId,           // ✅ must be string
  'messageId': messageId,       // ✅ must be string
}
```

---

### ❌ "Upload failed: 500" or "Internal Server Error"

**What it means:** Something wrong on Cloud Function side

**Why:**
- Cloudflare credentials are wrong
- R2 bucket doesn't exist
- Firestore write failed
- Cloud Function crashed

**Fix:**
1. Check **Cloud Function logs**:
```bash
firebase functions:log
# Look for error messages
```

2. Common causes:
   - Wrong accountId
   - Wrong accessKeyId
   - Wrong secretAccessKey
   - Wrong bucketName
   - Firestore security rules too strict

---

### ❌ Progress Bar Doesn't Show

**What it means:** UI is not updating when upload happens

**Why:**
- Provider not listening to changes
- notifyListeners() not being called
- Widget not using Consumer

**Fix:**
1. Restart app (full close, reopen)
2. Check test screen is wrapped with Consumer:
```dart
Consumer<MediaChatProvider>(
  builder: (context, provider, child) => ... 
)
```

3. Check provider calls notifyListeners():
```dart
onProgress: (progress) {
  _uploadProgress[messageId] = progress;
  notifyListeners(); // ← Must have this
},
```

---

### ❌ "CORS error" or "blocked by browser"

**What it means:** Cloud Function is not configured for Flutter

**Why:**
- CORS headers missing in Cloud Function
- Wrong origin

**Fix:**
Make sure Cloud Function has CORS headers:
```javascript
res.set('Access-Control-Allow-Origin', '*');
res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

if (req.method === 'OPTIONS') {
  res.status(204).send('');
  return;
}
```

---

### ❌ "Exception: Failed to upload file"

**What it means:** Generic upload failure

**Why:** Many reasons - check console for more details

**Fix:**
1. Look at console/logs for detailed error
2. Check internet connection
3. Try again
4. If persists, check each step of flow

---

## ☁️ CLOUD FUNCTION ERRORS

### ❌ "Missing authorization token" (Cloud Function)

**What it means:** Flutter didn't send Firebase token to Cloud Function

**Why:**
- User not logged in (get failed before sending)
- Authorizaton header malformed
- Token is null

**Fix in Flutter:**
```dart
final token = await currentUser.getIdToken();
if (token == null) {
  throw Exception('Failed to get token');
}

// MUST send as:
headers: {
  'Authorization': 'Bearer $token',  // Bearer prefix!
}
```

---

### ❌ "Invalid token" or "Token verification failed"

**What it means:** Firebase can't verify the token

**Why:**
- Token is expired
- Wrong Firebase project
- Token got corrupted
- Wrong project in Cloud Function

**Fix:**
1. Check Cloud Function is in **same** Firebase project
2. Restart app to refresh token
3. Re-login
4. Verify in Cloud Function:
```javascript
try {
  decodedToken = await admin.auth().verifyIdToken(token);
} catch (error) {
  // This is where error happens
  console.error('Token error:', error.message);
}
```

---

### ❌ "File too large. Max 50MB"

**What it means:** Image is bigger than 50MB limit

**Why:**
- Original file is huge
- Compression not working

**Fix:**
1. Use smaller image
2. Increase limit in Cloud Function:
```javascript
const maxSizeBytes = 100 * 1024 * 1024; // 100MB instead of 50MB
```

3. Rebuild and deploy:
```bash
firebase deploy --only functions:uploadFileToR2
```

---

### ❌ "Invalid base64" or "Buffer.from"

**What it means:** File wasn't encoded to base64 properly

**Why:**
- String isn't valid base64
- Contains invalid characters
- Encoding error

**Fix in Flutter:**
```dart
// Flutter MUST send as:
final fileBytes = await file.readAsBytes();
final fileBase64 = base64Encode(fileBytes); // ← Use dart:convert
final requestBody = jsonEncode({
  'fileBase64': fileBase64, // ← This MUST be valid base64
});
```

---

### ❌ "R2 upload failed with status 401" or "403"

**What it means:** Cloudflare R2 rejected the upload

**Why:**
- accountId is wrong
- accessKeyId is wrong
- secretAccessKey is wrong
- API token expired
- API token doesn't have permissions
- Bucket doesn't exist
- Bucket name is wrong

**Fix:**
1. **Check credentials in Cloud Function:**
```javascript
const CF_CONFIG = {
  accountId: 'YOUR_ACCOUNT_ID',     // ← Check this
  bucketName: 'YOUR_BUCKET',         // ← Check this
  accessKeyId: 'YOUR_KEY',           // ← Check this
  secretAccessKey: 'YOUR_SECRET',    // ← Check this
  r2Domain: 'YOUR_DOMAIN',           // ← Check this
};
```

2. **Verify on Cloudflare Dashboard:**
   - Go to https://dash.cloudflare.com
   - Click R2 Buckets
   - Copy Account ID (shown on page)
   - Copy Bucket Name (shown in list)
   - Click R2 Settings → API Tokens
   - Check you have active token
   - Check token has: s3:PutObject, s3:GetObject, s3:ListBucket permissions

3. **Re-deploy Cloud Function:**
```bash
firebase deploy --only functions:uploadFileToR2
```

---

### ❌ "R2 upload failed with status 404"

**What it means:** R2 bucket not found

**Why:**
- Bucket name is wrong
- Bucket was deleted
- Bucket is in different region

**Fix:**
1. Verify bucket exists:
   - Go to https://dash.cloudflare.com
   - Click R2 → look for your bucket
   - If not there, create it

2. Check bucket name in config matches exactly:
```javascript
const CF_CONFIG = {
  bucketName: 'lenv-storage', // ← MUST match Cloudflare exactly
};
```

---

### ❌ "Failed to save metadata to Firestore"

**What it means:** File uploaded to R2 but metadata write failed

**Why:**
- Firestore not enabled
- Firestore path wrong
- Firestore security rules block write
- Firestore quota exceeded

**Fix:**
1. Check Firestore is enabled:
   - Go to https://console.firebase.google.com
   - Click Firestore Database
   - Should say "Create database" button is gone

2. Check Firestore rules allow writes:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;  // ← For testing
    }
  }
}
```

3. Check path is correct in Cloud Function:
```javascript
const fileRef = db
  .collection('schools')
  .doc(schoolId)                  // ← Must exist or be created
  .collection('communities')
  .doc(communityId)              // ← Must exist or be created
  .collection('groups')
  .doc(groupId)                  // ← Must exist or be created
  .collection('messages')
  .doc(messageId)                // ← Must exist or be created
  .collection('files')
  .doc(fileName);

await fileRef.set(fileMetadata);
```

**Firebase allows creating nested docs automatically**, so this should work.

---

### ❌ "Signature verification failed"

**What it means:** R2 doesn't recognize the AWS signature

**Why:**
- secretAccessKey is wrong
- accountId is wrong
- Date/time is wrong (server time mismatch)
- Signature algorithm wrong

**Fix:**
1. Check credentials again:
```javascript
const CF_CONFIG = {
  accessKeyId: 'GET_FROM_CLOUDFLARE',
  secretAccessKey: 'GET_FROM_CLOUDFLARE',
};
```

2. Check server time is correct:
```javascript
const date = new Date();
console.log('Server time:', date.toISOString());
// Should be close to your computer time
```

3. If time is off, R2 will reject signature
   - Cloud Function runs on Google servers (UTC)
   - Should be fine unless your server is WAY off

---

## 🗄️ FIRESTORE ERRORS

### ❌ "Document not found" or empty collection

**What it means:** Metadata wasn't saved or path is wrong

**Why:**
- Path is wrong
- Firestore write failed
- Firestore rules block write
- Wrong project

**Fix:**
1. Check Firestore has data:
   - Go to https://console.firebase.google.com
   - Click Firestore Database
   - Look for collection "schools"
   - Navigate path: schools → test-school → communities → test-conv-123 → groups → test-group → messages
   - Look for your messageId folder
   - Inside should be "files" collection
   - Inside should be photo.jpg document

2. If nothing there:
   - Check Cloud Function logs: `firebase functions:log`
   - Look for Firestore write errors
   - Check Firestore rules allow write

---

### ❌ "Permission denied" or "PERMISSION_DENIED"

**What it means:** Firestore security rules blocked the write

**Why:**
- User not authenticated
- Rules too strict
- Wrong user role

**Fix:**
Update Firestore security rules to allow authenticated users:

Go to https://console.firebase.google.com → Firestore → Rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

Then click "Publish"

---

## 📦 CLOUDFLARE R2 ERRORS

### ❌ "File not found" after upload says successful

**What it means:** File should be in R2 but isn't

**Why:**
- Upload didn't actually complete
- Wrong bucket checked
- Wrong path checked
- File was deleted

**Fix:**
1. Check correct bucket:
   - Go to https://dash.cloudflare.com
   - Click R2 → "lenv-storage" (your bucket name)
   - NOT a different bucket

2. Check correct path:
   - Look for: schools/test-school/communities/test-conv-123/groups/test-group/messages/{messageId}/
   - Inside should be photo.jpg

3. Check Cloud Function logs:
```bash
firebase functions:log
```
Look for "✅ File uploaded to R2" message

---

### ❌ "Public URL doesn't work"

**What it means:** File is in R2 but you can't access it via public link

**Why:**
- Custom domain not set up
- Default URL being used instead of custom domain
- Bucket visibility set wrong

**Fix:**
1. Check custom domain is set up in Cloudflare:
   - Go to https://dash.cloudflare.com
   - Click R2 → lenv-storage bucket
   - Click Settings
   - Look for "Custom domain"
   - Should say "files.lenv1.tech" or your domain

2. If not set up:
   - Click "Connect domain"
   - Add your domain (files.lenv1.tech)
   - Wait for DNS propagation (usually instant)

3. Test access:
```
Open in browser: https://files.lenv1.tech/schools/test-school/communities/test-conv-123/groups/test-group/messages/{id}/photo.jpg
Should show image or download
```

---

### ❌ "CORS error" accessing file from Flutter

**What it means:** R2 blocked request due to CORS

**Why:**
- R2 CORS rules too strict
- Not configured for Flutter

**Fix:**
Go to R2 bucket Settings and add CORS rule:

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST"],
      "AllowedHeaders": ["*"],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

---

## 🔑 CREDENTIAL ERRORS

### ❌ "Missing required fields"

**What it means:** Cloud Function request is missing something

**Check all these are in request:**
```
✅ fileName
✅ fileBase64
✅ fileType
✅ schoolId
✅ communityId
✅ groupId
✅ messageId
```

All must be present!

---

### ❌ "Invalid credentials" or "UnauthorizedOperation"

**What it means:** One of your credential values is wrong

**Fix:**
1. **Get fresh values from Cloudflare:**
   - Go to https://dash.cloudflare.com
   - Click R2
   - Copy Account ID word-for-word (exactly)
   - Click Settings → API Tokens
   - Create new token if you don't have one
   - Copy Access Key ID (word-for-word)
   - Copy Secret Access Key (save it!)

2. **Update in Cloud Function:**
```javascript
const CF_CONFIG = {
  accountId: 'PASTE_EXACTLY',
  accessKeyId: 'PASTE_EXACTLY',
  secretAccessKey: 'PASTE_EXACTLY',
};
```

3. **Re-deploy:**
```bash
firebase deploy --only functions:uploadFileToR2
```

---

## 🎯 ERROR DIAGNOSIS FLOWCHART

```
Error appears
    ↓
Is it in FLUTTER console?
├─ YES → Go to "FLUTTER/APP ERRORS" above
└─ NO → Check Cloud Function logs

firebase functions:log
    ↓
Is error in Cloud Function logs?
├─ YES → Go to "CLOUD FUNCTION ERRORS" above
└─ NO → Check R2 console and Firestore console

Check Cloudflare R2 dashboard
    ↓
Is file in R2?
├─ YES → Error in FIRESTORE or PUBLIC URL
│        Go to "FIRESTORE ERRORS" or "CLOUDFLARE R2 ERRORS"
└─ NO → Error in R2 upload
         Go to "CLOUDFLARE R2 ERRORS"

Check Firestore
    ↓
Is metadata there?
├─ YES → Problem solved!
└─ NO → Go to "FIRESTORE ERRORS"
```

---

## ✅ QUICK FIXES BY SYMPTOM

| Symptom | Most Likely Cause | Quick Fix |
|---------|-------------------|-----------|
| Progress bar doesn't show | Provider not listening | Restart app |
| File not in R2, no error | Credentials wrong | Copy from Cloudflare again |
| 401/403 error | API token permissions | Check token has s3:PutObject |
| Timeout | Internet slow or file huge | Use smaller image |
| Metadata missing | Firestore rules | Allow `write: if request.auth != null` |
| File in R2 but can't access | Domain not set | Set custom domain in R2 |
| Token error | User not logged in | Login before uploading |
| Path wrong | Config values wrong | Verify schoolId, communityId, etc |

---

## 📞 How to Report Errors

When asking for help, provide:

1. **The exact error message** (all of it)
2. **Where it appears** (Flutter console? Cloud Function? R2?)
3. **What you did** (clicked upload, then...)
4. **Have you checked:**
   - [ ] Logged in?
   - [ ] Credentials correct?
   - [ ] Cloud Function deployed?
   - [ ] Internet working?
   - [ ] Firestore enabled?

---

**Use this guide + COMPLETE_SETUP_GUIDE.md troubleshooting section to fix any error! ✅**
