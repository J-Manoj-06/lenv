# Cloud Function Upload Setup

## Overview

You're shifting from **client-side direct R2 uploads** to **server-side Firebase Cloud Function uploads**. This is more secure and automatically organizes files.

### Flow

```
Flutter App
    ↓
  Pick Image/PDF
    ↓
Call Cloud Function (uploadFileToR2)
    ↓
Firebase Cloud Function
    ├─ Receive file (base64) + metadata
    ├─ Upload to R2 with organized path:
    │  /schools/{schoolId}/communities/{communityId}/groups/{groupId}/messages/{messageId}/{fileName}
    ├─ Save metadata to Firestore
    └─ Return public URL
    ↓
Flutter App
    ├─ Display in chat
    └─ User sees: https://files.lenv1.tech/schools/.../file.jpg
```

## Files Created

1. **functions/uploadFileToR2.js** - Cloud Function that handles R2 uploads
2. **lib/services/cloud_function_upload_service.dart** - Flutter service to call Cloud Function
3. **lib/providers/media_chat_provider.dart** - Updated with new upload method

## Setup Instructions

### Step 1: Deploy Cloud Function

First, ensure your `.env` has Cloudflare credentials:

```bash
cd functions
cat .env
```

You should see:
```
CF_ACCOUNT_ID=4c51b62d64def00af4856f10b6104fe2
CF_BUCKET_NAME=lenv-storage
CF_ACCESS_KEY_ID=e5606eba19c4cc21cb9493128afc1f01
CF_SECRET_ACCESS_KEY=e060ff4595dd7d3e...
CF_R2_DOMAIN=files.lenv1.tech
```

Deploy the function:

```bash
firebase deploy --only functions:uploadFileToR2
```

Expected output:
```
✔  Function uploaded successfully
   uploadFileToR2: https://us-central1-new-reward-prod.cloudfunctions.net/uploadFileToR2
```

**Note:** Replace `us-central1-new-reward-prod` with your actual Firebase project ID.

### Step 2: Update Cloud Function URL in Flutter

In `lib/providers/media_chat_provider.dart`, update the URL:

```dart
const cloudFunctionUrl = 'https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/uploadFileToR2';
```

Replace `YOUR-PROJECT-ID` with your actual Firebase project ID (check your `firebase.json` or console).

### Step 3: Test Upload

#### Option A: Using Test Screen (Existing)

```
Dashboard (top-right wrench icon)
  ↓
Dev Tools
  ↓
"🎥 Test Media Upload" button
  ↓
"Pick Image from Gallery"
  ↓
Check console for upload status
```

**Current test still uses old method.** To use new Cloud Function method, see Option B.

#### Option B: Using Cloud Function Method (NEW)

In the test screen or your chat screen, use:

```dart
await provider.uploadMediaViaCloudFunction(
  file: File(pickedFile.path),
  schoolId: 'CSK100',
  communityId: 'comm_123',
  groupId: 'group_456',
  messageId: 'msg_789',
);
```

This will:
1. Upload to Cloud Function (HTTPS endpoint)
2. Function uploads to R2 with organized path
3. Returns public URL immediately
4. Displays in chat

## Expected R2 Folder Structure

After successful uploads, your R2 bucket will have:

```
lenv-storage/
├── schools/
│   ├── CSK100/
│   │   ├── communities/
│   │   │   ├── comm_123/
│   │   │   │   ├── groups/
│   │   │   │   │   ├── group_456/
│   │   │   │   │   │   ├── messages/
│   │   │   │   │   │   │   ├── msg_789/
│   │   │   │   │   │   │   │   ├── photo.jpg
│   │   │   │   │   │   │   │   ├── document.pdf
│   │   │   │   │   │   │   │   └── ...
```

**Public URLs:**
```
https://files.lenv1.tech/schools/CSK100/communities/comm_123/groups/group_456/messages/msg_789/photo.jpg
https://files.lenv1.tech/schools/CSK100/communities/comm_123/groups/group_456/messages/msg_789/document.pdf
```

## Firestore Metadata Storage

Each file upload also stores metadata:

**Path:** `schools/{schoolId}/communities/{communityId}/groups/{groupId}/messages/{messageId}/files/{fileName}`

**Data:**
```json
{
  "fileName": "photo.jpg",
  "fileType": "image/jpeg",
  "fileSizeKb": 125.5,
  "r2Path": "schools/CSK100/communities/comm_123/groups/group_456/messages/msg_789/photo.jpg",
  "publicUrl": "https://files.lenv1.tech/schools/CSK100/communities/comm_123/groups/group_456/messages/msg_789/photo.jpg",
  "uploadedBy": "user_uid_123",
  "uploadedAt": "2025-12-08T22:40:00Z",
  "schoolId": "CSK100",
  "communityId": "comm_123",
  "groupId": "group_456",
  "messageId": "msg_789"
}
```

## Benefits of Cloud Function Approach

✅ **Security**
- R2 credentials never exposed to client
- Server-side validation and error handling
- Firebase Authentication required for uploads

✅ **Organization**
- Automatic folder structure based on school/community/group
- Consistent file naming and path structure
- Easy to manage and delete files

✅ **Reliability**
- Server-side retry logic
- Proper AWS Signature V4 signing
- Better error messages and logging

✅ **Cost Efficiency**
- Same R2 costs ($0.015/GB stored)
- Minimal Cloud Function costs (~$0.40/million invocations)
- Total: ~$0.001 per upload

## Troubleshooting

### Error: "Missing authorization token"
- Ensure user is logged in
- Check Firebase Auth is initialized

### Error: "Invalid token"
- Token expired, user needs to re-login
- Check Firebase project ID is correct

### Error: "Upload failed: 403"
- Cloud Function credentials issue
- Check `.env` has correct Cloudflare credentials
- Verify CF_ACCOUNT_ID and CF_SECRET_ACCESS_KEY

### Error: "Upload timeout"
- File too large (>50MB)
- Network connection issue
- Cloud Function taking too long
- Try breaking file into smaller chunks

### File appears in console but not in R2
- Check R2 bucket permissions
- Verify custom domain `files.lenv1.tech` is accessible
- Check Cloudflare firewall rules

### Firestore metadata not saved
- Check Firestore security rules allow writes
- Verify Cloud Function has proper Firestore access
- Check collection paths match the code

## Next Steps

1. **Deploy** the Cloud Function:
   ```bash
   firebase deploy --only functions:uploadFileToR2
   ```

2. **Update** Flutter app with correct Cloud Function URL

3. **Test** by uploading an image and verifying:
   - ✅ Console shows upload progress (10→50→100)
   - ✅ Public URL returned
   - ✅ File appears in R2 bucket
   - ✅ Metadata appears in Firestore

4. **Integrate** into real chat screens:
   - Replace `uploadMedia()` calls with `uploadMediaViaCloudFunction()`
   - Pass school/community/group/message IDs from your chat context

## Environment Variables

**Firebase Project ID:**
- Check in `firebase.json`: look for `"projectId"` field
- Or check Firebase Console: Settings → Project ID

**Cloud Function URL Format:**
```
https://{REGION}-{PROJECT_ID}.cloudfunctions.net/uploadFileToR2
```

Common regions: `us-central1`, `us-west1`, `europe-west1`

## Security Rules (Firestore)

Ensure your Firestore rules allow writes to the upload paths:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /schools/{schoolId}/communities/{communityId}/groups/{groupId}/messages/{messageId}/files/{fileId} {
      allow create: if request.auth != null;
      allow read: if request.auth != null;
      allow update, delete: if request.auth.uid == resource.data.uploadedBy;
    }
  }
}
```

This ensures:
- Only authenticated users can upload
- Anyone in organization can read file metadata
- Only uploader can modify/delete

## What's Different from Old Approach

### Old (Direct R2):
- Flutter ← Signs request locally
- Sends signed request directly to R2
- Problem: Clock skew errors, SSL issues

### New (Cloud Function):
- Flutter ← Calls Cloud Function
- Cloud Function → Signs request on server
- Cloud Function → Sends to R2
- Problem: None (server has correct time, SSL works)

The new approach is **more reliable** because the server handles all the authentication details.
