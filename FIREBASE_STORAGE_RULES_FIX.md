# Firebase Storage Rules Deployment Guide

## Issue Fixed
The announcement image upload was failing with **Firebase Storage 404 errors** because:
- ❌ Firebase Storage had no security rules configured
- ❌ The `institute_announcements/` folder wasn't accessible to principals
- ❌ Missing Storage configuration in `firebase.json`

## Solution Implemented

### 1. Created Storage Rules File
**File**: `firebase/storage.rules`

Allows:
- ✅ Principals to upload announcement images to `institute_announcements/`
- ✅ Teachers to upload community announcements
- ✅ All authenticated users to read attachments
- ✅ Users to upload to group chats, messages, and their own media

### 2. Updated Firebase Configuration
**File**: `firebase.json`

Added:
```json
"storage": {
  "rules": "firebase/storage.rules"
}
```

## Deployment Instructions

### Option A: Using Firebase CLI (Recommended)

```bash
# Login to Firebase
firebase login

# Deploy only storage rules
firebase deploy --only storage

# Or deploy everything
firebase deploy
```

### Option B: Using Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Storage** → **Rules** tab
4. Copy contents of `firebase/storage.rules`
5. Paste into the rules editor
6. Click **Publish**

## What Now Works

✅ Principals can post announcements with images
✅ Teachers can upload community announcements
✅ Message attachments in group chats
✅ Student community messages with media
✅ Parent-teacher group chat attachments

## Testing the Fix

1. Go to **Institute Announcements** screen
2. Click **Create Announcement**
3. Add image and text
4. Click **Post**
5. Image should upload successfully (no more 404 errors)

## Important Notes

- The rules automatically deny all other access patterns
- File sizes are limited by Firebase Storage limits (default ~5GB per file)
- Uploaded files are private to authenticated users only
- Consider adding cleanup rules in Firebase Console for old temporary files

## Troubleshooting

**Still getting 404 errors?**
- Clear app cache: Settings → Apps → LENV Rewards → Storage → Clear Cache
- Reinstall the app
- Check that your Firebase project has Storage enabled
- Verify your Firebase rules deployment was successful

**Images uploading but not displaying?**
- Check that users have read permissions (should be automatic)
- Verify image URL is being saved correctly in Firestore
- Check device storage space
